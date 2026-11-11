import Foundation
import CoreGraphics
import Testing
import DartCore
@testable import DartVision
@testable import DartUI

/// Wave 3 integration: the configuration saved with a calibration reaches the service BEFORE the calibration.
/// `ScanEngine` sets the warm-up cap of the first three darts from the configuration in place when a calibration is
/// installed, and a later configuration does not change it (VISION.md §6.5). Installed the other way round, a
/// calibration saved after a verified one-dart check (`warmUpDarts = 0`) capped its first darts again after every
/// restart; the integration probe reproduced it on the real `ScanSession` (first dart 0.84, flag `warmUp`).
@MainActor
@Suite(.serialized) struct CameraFlowInstallOrderTests {
    private typealias Support = CameraFlowSupport

    @Test func coldStart_installsTheSavedConfigurationBeforeTheCalibration() async {
        let calibration = Support.syntheticCamera.calibration(grade: .good)
        var configuration = VisionConfiguration()
        configuration.confidence.warmUpDarts = 0
        let storage = Support.storage()
        storage.save(Support.stored(calibration, configuration: configuration, lightingCheckPassed: true))
        let service = CameraFlowOrderService(still: Support.emptyBoard)
        let camera = CameraModel(service: service, storage: storage)
        await camera.activate()
        #expect(camera.readiness == .ready(grade: .good))
        #expect(service.installs == [.configuration(configuration), .calibration(calibration)])
    }

    @Test func adopt_installsTheConfigurationBeforeTheCalibration() async {
        let calibration = Support.syntheticCamera.calibration(grade: .good)
        let service = CameraFlowOrderService(still: Support.emptyBoard)
        let camera = CameraModel(service: service, storage: Support.storage())
        await camera.activate()
        await camera.adopt(calibration, lightingCheckPassed: false)
        #expect(service.installs == [.configuration(camera.configuration), .calibration(calibration)])
        // After the one-dart check the same calibration is adopted again: only the configuration is sent.
        await camera.adopt(calibration, lightingCheckPassed: true)
        #expect(service.installs.count == 3 && service.installs.last == .configuration(camera.configuration))
        #expect(camera.configuration.confidence.warmUpDarts == 0)
    }
}

/// `FakeScanService` that also records the order of `updateConfiguration` and `setCalibration`.
@MainActor
private final class CameraFlowOrderService: ScanServicing {
    enum Install: Equatable {
        case configuration(VisionConfiguration)
        case calibration(BoardCalibration)
    }

    private let fake: FakeScanService
    private(set) var installs: [Install] = []

    init(still: RGBImage) {
        fake = FakeScanService(still: still)
    }

    var cameraID: String { fake.cameraID }
    var frameInfo: FrameSourceInfo? { fake.frameInfo }
    var preview: PreviewContent { fake.preview }
    var issue: CameraIssue? { fake.issue }
    func events() -> AsyncStream<ScanEvent> { fake.events() }
    func start() async throws { try await fake.start() }
    func stop() async { await fake.stop() }
    func captureStill(averaging frames: Int) async throws -> RGBImage { try await fake.captureStill(averaging: frames) }

    func setCalibration(_ calibration: BoardCalibration) async {
        installs.append(.calibration(calibration))
        await fake.setCalibration(calibration)
    }

    func updateConfiguration(_ configuration: VisionConfiguration) async {
        installs.append(.configuration(configuration))
        await fake.updateConfiguration(configuration)
    }

    func send(_ command: ScanCommand) async { await fake.send(command) }
    func correct(_ id: UUID, tip: BoardPoint) async -> DartObservation? { await fake.correct(id, tip: tip) }
    func recordFeedback(_ id: UUID, wasCorrected: Bool) async { await fake.recordFeedback(id, wasCorrected: wasCorrected) }
    func evidenceCrop(for id: UUID) async -> CGImage? { await fake.evidenceCrop(for: id) }
    func runLightingCheck(confirmedTip: BoardPoint) async -> LightingCheckResult? {
        await fake.runLightingCheck(confirmedTip: confirmedTip)
    }
    func currentState() async -> ScanState { await fake.currentState() }
}
