import Foundation
import Testing
import DartCore
@testable import DartVision
@testable import DartUI

/// The life cycle of `CameraModel` (ARCHITECTURE.md §8.7, "Cycle de vie"; VISION.md §4.10): the cold start, the
/// revalidation of a saved calibration on a fresh still, its round trip through `AppStorage`, the adoption, and
/// the calibrations the vision adjusts by itself. The service is `FakeScanService`; the stills are synthetic.
@MainActor
@Suite(.serialized) struct CameraFlowColdStartTests {
    private typealias Support = CameraFlowSupport

    // MARK: Mandatory test of §8.7: cold start

    @Test func coldStart_withASavedCalibration() async {
        let calibration = Support.syntheticCamera.calibration(grade: .good)
        var configuration = VisionConfiguration()
        configuration.detection.shadowLowerBound = 0.3
        let storage = Support.storage()
        storage.save(Support.stored(calibration, configuration: configuration, lightingCheckPassed: true))
        let service = FakeScanService(still: Support.emptyBoard)
        let camera = Support.camera(service, storage: storage)
        #expect(camera.readiness == .unknown)
        // The game is created before `activate()`: it has a source all the same.
        let source = camera.makeInputSource(mode: .live)
        #expect(source != nil)
        await camera.activate()
        #expect(service.isRunning && service.stillRequests == [8])
        #expect(service.calibrations == [calibration] && service.configurations == [configuration])
        #expect(camera.readiness == .ready(grade: .good) && camera.calibration == calibration)
        #expect(camera.lightingCheckPassed && camera.configuration == configuration)
        source?.gameStarted(boardConfirmedEmpty: true)
        await camera.drainQueue()
        #expect(service.commands == [.setTrigger(.automatic), .arm(boardConfirmedEmpty: true)])
    }

    @Test func coldStart_withoutACalibration_theSourcePublishesNeedsCalibration() async throws {
        let service = FakeScanService(still: Support.emptyBoard)
        let camera = Support.camera(service)
        let source = try #require(camera.makeInputSource(mode: .live))
        await camera.activate()
        #expect(camera.readiness == .needsCalibration && service.calibrations.isEmpty && service.stillRequests.isEmpty)
        let recorder = CameraFlowRecorder(source.events())
        source.gameStarted(boardConfirmedEmpty: false)
        // The board is not confirmed empty: nothing is armed (§8.7), and without a calibration the source says so
        // itself.
        #expect(await Support.wait { recorder.items.cameraFlowStatuses == [.needsCalibration] })
        #expect(source.status == .needsCalibration)
        await camera.drainQueue()
        #expect(service.commands.isEmpty)
        recorder.cancel()
    }

    @Test func coldStart_withAnIssueBeforeGameStarted_theSourceIsUnavailable_andDepositsNothing() async throws {
        let service = FakeScanService(still: Support.emptyBoard)
        let camera = Support.camera(service)
        let source = try #require(camera.makeInputSource(mode: .live))
        let recorder = CameraFlowRecorder(source.events())
        // Access refused, or the camera lost, during `activate()`.
        service.issue = .accessDenied
        source.gameStarted(boardConfirmedEmpty: true)
        #expect(source.status == .unavailable)
        #expect(await Support.wait { recorder.items.cameraFlowStatuses == [.unavailable] })
        await camera.drainQueue()
        #expect(service.commands.isEmpty)
        recorder.cancel()
    }

    @Test func coldStart_inACalibratedState_theStatesOfTheVisionCarryTheStatus() async throws {
        let service = FakeScanService(still: Support.emptyBoard)
        let camera = Support.camera(service)
        await camera.adopt(Support.syntheticCamera.calibration(grade: .fair), lightingCheckPassed: false)
        service.emit(.stateChanged(.idle))
        let source = try #require(camera.makeInputSource(mode: .photo))
        let recorder = CameraFlowRecorder(source.events())
        source.gameStarted(boardConfirmedEmpty: true)
        service.emit(.stateChanged(.arming))
        service.emit(.stateChanged(.watching(dartsOnBoard: 0)))
        #expect(await Support.wait { recorder.items.cameraFlowStatuses == [.awaitingCapture] })
        // The check of the state after `arm` read `idle`: it published nothing more.
        try? await Task.sleep(for: .milliseconds(50))
        #expect(recorder.items.cameraFlowStatuses == [.awaitingCapture])
        recorder.cancel()
    }

    @Test func activate_isIdempotent_andConcurrentCallsShareOneActivation() async {
        let storage = Support.storage()
        storage.save(Support.stored(Support.syntheticCamera.calibration(grade: .good)))
        let service = FakeScanService(still: Support.emptyBoard)
        let camera = Support.camera(service, storage: storage)
        async let first: Void = camera.activate()
        async let second: Void = camera.activate()
        _ = await (first, second)
        await camera.activate()
        #expect(service.stillRequests == [8] && service.calibrations.count == 1)
        #expect(camera.isActive && camera.readiness == .ready(grade: .good))
        // Stopped, then started again: the calibration is revalidated and installed again.
        await camera.deactivate()
        #expect(!service.isRunning && !camera.isActive && camera.readiness == .unknown)
        await camera.activate()
        #expect(service.stillRequests == [8, 8] && service.calibrations.count == 2)
    }

    @Test func activate_withoutACamera_isUnavailable() async {
        let camera = Support.camera(FakeScanService(issue: .accessDenied))
        await camera.activate()
        #expect(camera.readiness == .unavailable(.accessDenied) && !camera.isActive)
        #expect(camera.makeInputSource(mode: .live) == nil)
    }

    // MARK: Revalidation (VISION.md §4.10)

    @Test func revalidation_aDriftedCalibrationIsRecoveredInstalledAndSaved() async throws {
        let saved = Support.syntheticCamera.calibration(grade: .good)
        let storage = Support.storage()
        storage.save(Support.stored(saved))
        // The stand was bumped: the whole picture moved by a few pixels.
        let service = FakeScanService(still: Support.shiftedBoard(SIMD2(3, -2)))
        let camera = Support.camera(service, storage: storage)
        await camera.activate()
        let installed = try #require(service.calibrations.first)
        #expect(service.calibrations.count == 1 && installed != saved)
        #expect(camera.calibration == installed && camera.readiness == .ready(grade: installed.quality.grade))
        let stored = try #require(storage.loadCalibration(cameraID: "fake", rotationDegrees: 0, imageSize: saved.imageSize))
        #expect(stored.calibration == installed)
        // The recovered calibration follows the moved board: the bull is about 3 px right and 2 px up.
        let centre = installed.imagePoint(for: BoardPoint(x: 0, y: 0)), before = saved.imagePoint(for: BoardPoint(x: 0, y: 0))
        #expect(abs(centre.x - before.x - 3) < 0.5 && abs(centre.y - before.y + 2) < 0.5)
    }

    @Test func revalidation_aLostCalibrationAsksForANewOne_fromTheOldHandles() async throws {
        let saved = Support.syntheticCamera.calibration(grade: .good)
        let storage = Support.storage()
        storage.save(Support.stored(saved))
        let service = FakeScanService(still: Support.shiftedBoard(SIMD2(70, 50)))
        let camera = Support.camera(service, storage: storage)
        await camera.activate()
        #expect(camera.readiness == .needsCalibration && camera.calibration == nil)
        #expect(service.calibrations.isEmpty && service.configurations.isEmpty)
        // The calibration screen starts from the old handles.
        #expect(camera.savedCalibration == saved)
    }

    @Test func revalidation_anotherImageSizeIsAnotherCalibration() async {
        let storage = Support.storage()
        storage.save(Support.stored(Support.syntheticCamera.calibration(grade: .good)))
        let service = FakeScanService(still: RGBImage(width: 640, height: 480, fill: SIMD3(90, 90, 90)))
        let camera = Support.camera(service, storage: storage)
        await camera.activate()
        #expect(camera.readiness == .needsCalibration && camera.savedCalibration == nil && service.stillRequests.isEmpty)
    }

    // MARK: Persistence (§8.10)

    @Test func storedCalibration_roundTripThroughAppStorage() throws {
        let store = InMemoryStore()
        let storage = AppStorage(store: store)
        var configuration = VisionConfiguration()
        configuration.detection.shadowLowerBound = 0.27
        configuration.confidence.warmUpDarts = 0
        let fair = StoredCalibration(cameraID: "back-wide", calibration: Support.syntheticCamera.calibration(grade: .fair),
                                     configuration: configuration, lightingCheckPassed: true)
        storage.save(fair)
        // A new AppStorage over the same store reads the same value, `wireHeight` and every field included.
        let read = try #require(AppStorage(store: store).loadCalibration(cameraID: "back-wide", rotationDegrees: 0,
                                                                          imageSize: PixelSize(width: 1080, height: 1920)))
        #expect(read == fair && read.calibration.wireHeight == fair.calibration.wireHeight)
        // The key is (camera, rotation, size).
        #expect(storage.loadCalibration(cameraID: "synthetic", rotationDegrees: 0, imageSize: PixelSize(width: 1080, height: 1920)) == nil)
        #expect(storage.loadCalibration(cameraID: "back-wide", rotationDegrees: 90, imageSize: PixelSize(width: 1080, height: 1920)) == nil)
        // A new calibration for the same key replaces the old one; another key is kept beside it.
        let good = StoredCalibration(cameraID: "back-wide", calibration: Support.syntheticCamera.calibration(grade: .good),
                                     configuration: VisionConfiguration(), lightingCheckPassed: false)
        let other = StoredCalibration(cameraID: "synthetic", calibration: CameraFlowFixtures.landscapeCamera.calibration(grade: .poor),
                                      configuration: VisionConfiguration(), lightingCheckPassed: false)
        storage.save(good)
        storage.save(other)
        #expect(storage.loadCalibration(cameraID: "back-wide", rotationDegrees: 0, imageSize: PixelSize(width: 1080, height: 1920)) == good)
        #expect(storage.loadCalibration(cameraID: "synthetic", rotationDegrees: 0, imageSize: PixelSize(width: 1280, height: 720)) == other)
    }

    @Test func adopt_installsSavesAndMakesTheCameraReady() async throws {
        let storage = Support.storage()
        let service = FakeScanService(still: Support.emptyBoard)
        let camera = Support.camera(service, storage: storage)
        let calibration = Support.syntheticCamera.calibration(grade: .fair)
        await camera.adopt(calibration, lightingCheckPassed: false)
        #expect(service.calibrations == [calibration] && service.configurations.count == 1)
        #expect(camera.readiness == .ready(grade: .fair) && !camera.lightingCheckPassed)
        let stored = try #require(storage.loadCalibration(cameraID: "fake", rotationDegrees: 0, imageSize: calibration.imageSize))
        #expect(stored.calibration == calibration && !stored.lightingCheckPassed)
        #expect(stored.configuration.confidence.warmUpDarts == 3)
        // The one-dart check passed: same calibration, not installed again; the bound of the check is kept and
        // the warm-up dropped (VISION.md §4.8).
        camera.recordLightingCheck(LightingCheckResult(verdict: .verified, tipError: 0.6, shadowDepth: 0.55,
                                                       recommendedShadowLowerBound: 0.47))
        await camera.adopt(calibration, lightingCheckPassed: true)
        #expect(service.calibrations == [calibration] && service.configurations.count == 2)
        let checked = try #require(storage.loadCalibration(cameraID: "fake", rotationDegrees: 0, imageSize: calibration.imageSize))
        #expect(checked.lightingCheckPassed && checked.configuration.detection.shadowLowerBound == 0.47)
        #expect(checked.configuration.confidence.warmUpDarts == 0 && service.configurations.last == checked.configuration)
        camera.forgetCalibration()
        #expect(camera.calibration == nil && !camera.lightingCheckPassed)
    }

    @Test func calibrationsAdjustedByTheVision_areSaved_andItsStatesFollowed() async throws {
        let storage = Support.storage()
        let service = FakeScanService(still: Support.emptyBoard)
        let camera = Support.camera(service, storage: storage)
        await camera.activate()
        let adjusted = Support.syntheticCamera.calibration(grade: .fair)
        service.emit(.calibrationAdjusted(adjusted))
        #expect(await Support.wait { camera.calibration == adjusted })
        #expect(camera.readiness == .ready(grade: .fair))
        #expect(storage.loadCalibration(cameraID: "fake", rotationDegrees: 0, imageSize: adjusted.imageSize)?.calibration == adjusted)
        service.emit(.stateChanged(.watching(dartsOnBoard: 2)))
        #expect(await Support.wait { camera.scanState == .watching(dartsOnBoard: 2) })
        service.emit(.calibrationLost)
        #expect(await Support.wait { camera.readiness == .needsCalibration })
        let recovered = Support.syntheticCamera.calibration(grade: .good)
        service.emit(.calibrationRecovered(recovered))
        #expect(await Support.wait { camera.readiness == .ready(grade: .good) })
        #expect(storage.loadCalibration(cameraID: "fake", rotationDegrees: 0, imageSize: recovered.imageSize)?.calibration == recovered)
    }
}
