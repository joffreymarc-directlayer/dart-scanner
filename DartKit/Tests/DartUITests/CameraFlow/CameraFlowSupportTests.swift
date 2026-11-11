import Foundation
import Testing
import DartCore
import DartGames
import DartAudio
import DartTestSupport
@testable import DartVision
@testable import DartUI

/// The fixtures of the camera-flow tests are what they claim: the exact calibration of the synthetic camera fits
/// its frames, and the three tips are where the darts are.
@Suite struct CameraFlowSupportTests {
    @Test @MainActor func syntheticCamera_isCalibratedAndHealthy() {
        let calibration = CameraFlowSupport.syntheticCamera.calibration(grade: .good)
        #expect(calibration.imageSize == CameraFlowSupport.emptyBoard.size)
        let health = BoardCalibrator().assess(calibration, on: CameraFlowSupport.emptyBoard, dartsOnBoard: false)
        #expect(health.status == .healthy)
        let hits = CameraFlowSupport.tips.map { BoardGeometry.standard.hit(at: $0) }
        #expect(hits == [.treble(20), .single(19), .single(7)])
        for tip in CameraFlowSupport.tips {
            let point = CameraFlowSupport.project(tip)
            #expect(point.x > 0 && point.y > 0 && point.x < 1080 && point.y < 1920)
            #expect(calibration.hit(at: point, board: .standard) == BoardGeometry.standard.hit(at: tip))
        }
    }
}

/// Helpers shared by the tests of lot U3: stores, games, observations, synthetic frames, waiting.
@MainActor
enum CameraFlowSupport {
    nonisolated static func storage() -> AppStorage {
        AppStorage(store: InMemoryStore())
    }

    /// A camera model over `service`, with an empty store unless one is given.
    static func camera(_ service: FakeScanService, storage: AppStorage = storage()) -> CameraModel {
        CameraModel(service: service, storage: storage)
    }

    /// "Meilleur score" for two players: every dart counts, three per turn.
    nonisolated static func highScoreMatch() throws -> GameMatch {
        try GameRegistry.standard.match(.highScore, players: 2, seed: 1)
    }

    static func game(source: (any DartInputSource)?, storage: AppStorage = storage()) throws -> PlayViewModel {
        let match = try highScoreMatch()
        return PlayViewModel(match: match, source: source, sound: SilentSoundPlayer(), storage: storage, endsTurnOnTakeout: false)
    }

    /// A stable identifier.
    static func id(_ n: Int) -> UUID {
        UUID(uuid: (0xC3, 0xF1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, UInt8(truncatingIfNeeded: n >> 8), UInt8(truncatingIfNeeded: n)))
    }

    /// An observation built by hand, as the service of the tests sends it.
    static func observation(_ id: UUID, _ hit: Hit, tip: BoardPoint? = nil, confidence: Double = 0.95,
                            candidates: [HitCandidate]? = nil, source: ObservationSource = .liveCamera,
                            sigmaAlong: Double = 0.85, sigmaAcross: Double = 0.37,
                            axis: SIMD2<Double> = SIMD2(0, 1), flags: DartFlags = []) -> DartObservation {
        let position = tip ?? BoardGeometry.standard.centre(of: hit) ?? BoardPoint(x: 0, y: 0)
        let thresholds = ConfidenceThresholds.standard
        return DartObservation(id: id, visit: 1, indexInVisit: 0, timestamp: 0, tip: position,
                               uncertainty: TipUncertainty(sigmaAlong: sigmaAlong, sigmaAcross: sigmaAcross, axis: axis),
                               candidates: candidates ?? [HitCandidate(hit: hit, probability: 1)], nearbyHits: [],
                               confidence: confidence, tier: thresholds.tier(for: confidence), flags: flags, source: source)
    }

    // MARK: Synthetic camera

    /// A camera under the board on a 1080 × 1920 sensor, about 1.45 px/mm: the calibrator grades it "fair".
    static let syntheticCamera = SyntheticCamera(imageSize: PixelSize(width: 1080, height: 1920), position: SIMD3(100, -300, 700))

    /// Tips of three darts, nominal mm: T20, S19 and S7 well inside their beds.
    static let tips = [BoardPoint(x: 0, y: 103), BoardPoint(x: 140 * sin(198 * .pi / 180), y: 140 * cos(198 * .pi / 180)),
                       BoardPoint(x: 60 * sin(216 * .pi / 180), y: 60 * cos(216 * .pi / 180))]

    static let emptyBoard: RGBImage = {
        var scene = SyntheticScene()
        scene.seed = 11
        return scene.render(camera: syntheticCamera)
    }()

    static let threeDarts: RGBImage = {
        var scene = SyntheticScene()
        scene.seed = 12
        scene.darts = tips.map { SyntheticDart(tip: $0) }
        return scene.render(camera: syntheticCamera)
    }()

    /// The empty board with the whole image moved by `shift` pixels (a bumped stand).
    static func shiftedBoard(_ shift: SIMD2<Double>) -> RGBImage {
        var scene = SyntheticScene()
        scene.seed = 13
        scene.shift = shift
        return scene.render(camera: syntheticCamera)
    }

    /// The calibration saved for the fake service ("fake", rotation 0, the size of the synthetic frames).
    static func stored(_ calibration: BoardCalibration, configuration: VisionConfiguration = VisionConfiguration(),
                       lightingCheckPassed: Bool = false) -> StoredCalibration {
        StoredCalibration(cameraID: "fake", calibration: calibration, configuration: configuration,
                          lightingCheckPassed: lightingCheckPassed)
    }

    /// The image point of a nominal board point for the synthetic camera.
    static func project(_ point: BoardPoint) -> ImagePoint {
        syntheticCamera.project(SIMD3(point.x, point.y, 0))
    }

    // MARK: Waiting

    /// Lets the tasks of the main actor and the detached computations run until `condition` holds (10 s at most).
    @discardableResult
    static func wait(until condition: @MainActor () -> Bool) async -> Bool {
        for _ in 0..<2000 {
            if condition() { return true }
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(5))
        }
        return condition()
    }
}

/// Collects what a stream yields, on the main actor, while a test runs.
@MainActor
final class CameraFlowRecorder<Element: Sendable> {
    private(set) var items: [Element] = []
    private var task: Task<Void, Never>?

    init(_ stream: AsyncStream<Element>) {
        task = Task { [weak self] in
            for await item in stream {
                self?.items.append(item)
            }
        }
    }

    func cancel() {
        task?.cancel()
    }
}

/// The statuses published by a source, in order.
extension Array where Element == DartInputEvent {
    var cameraFlowStatuses: [InputStatus] {
        compactMap { event in
            if case .statusChanged(let status) = event { return status }
            return nil
        }
    }
}
