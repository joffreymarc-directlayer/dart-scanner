import Foundation
import simd
import Testing
import DartCore
import DartAudio
@testable import DartVision
@testable import DartUI

/// The calibration flow (ARCHITECTURE.md §8.7, table "Calibrage"; VISION.md §4.7, §4.8) on a synthetic still served
/// by `FakeScanService`: the steps, the one-dart check and its `arm` then `pause(.user)`, the real calibrator on a
/// synthetic image, the camera refused.
@MainActor
@Suite(.serialized) struct CameraFlowCalibrationTests {
    private typealias Support = CameraFlowSupport

    /// Largest distance, on the scoring area, between the board point a calibration reads and the truth, mm.
    private func error(of calibration: BoardCalibration) -> Double {
        var worst = 0.0
        for radius in [0.0, 60, 103, 140, 166] {
            for step in 0..<12 {
                let angle = Double(step) * 30 * .pi / 180
                let truth = BoardPoint(x: radius * sin(angle), y: radius * cos(angle))
                let read = calibration.boardPoint(for: Support.project(truth))
                worst = max(worst, hypot(read.x - truth.x, read.y - truth.y))
            }
        }
        return worst
    }

    // MARK: Mandatory test of §8.7: the one-dart check

    @Test func oneDartCheck_depositsArm_thenPauseUserWhenTheFlowCloses() async throws {
        let storage = Support.storage()
        storage.save(Support.stored(Support.syntheticCamera.calibration(grade: .good)))
        let service = FakeScanService(still: Support.emptyBoard)
        let camera = Support.camera(service, storage: storage)
        let flow = CalibrationFlowModel(camera: camera)
        let sound = SilentSoundPlayer()
        flow.sound = sound
        await flow.start()
        // A calibration was saved: no placement guide, the previous handles on the still.
        #expect(flow.stage == .adjusting && service.stillRequests == [8, 8] && flow.canValidate)
        await flow.validate()
        #expect(flow.stage == .proof)
        let grade = try #require(flow.result).quality.grade
        await flow.adopt()
        #expect(flow.stage == .adopted && camera.readiness == .ready(grade: grade))
        #expect(!sound.played.isEmpty)
        await camera.drainQueue()
        #expect(service.commands.isEmpty)
        flow.startLightingCheck()
        await camera.drainQueue()
        #expect(flow.stage == .checkThrow && service.commands == [.arm(boardConfirmedEmpty: true)])
        // The dart is planted, its tip touched; the vision verifies it.
        service.lightingCheckResult = LightingCheckResult(verdict: .verified, tipError: 0.8, shadowDepth: 0.5,
                                                          recommendedShadowLowerBound: 0.42)
        await flow.captureCheckStill()
        #expect(flow.stage == .checkTap && service.stillRequests == [8, 8, 8])
        await flow.confirmTip(at: Support.project(BoardPoint(x: 0, y: 103)))
        #expect(flow.stage == .checkResult(.verified) && camera.lightingCheckPassed)
        let stored = try #require(storage.loadCalibration(cameraID: "fake", rotationDegrees: 0,
                                                          imageSize: Support.emptyBoard.size))
        #expect(stored.lightingCheckPassed && stored.configuration.detection.shadowLowerBound == 0.42)
        flow.close()
        await camera.drainQueue()
        #expect(service.commands == [.arm(boardConfirmedEmpty: true), .pause(.user)])
        // Closed once: closing again deposits nothing more.
        flow.close()
        await camera.drainQueue()
        #expect(service.commands == [.arm(boardConfirmedEmpty: true), .pause(.user)])
    }

    @Test func oneDartCheck_thatFails_stillEndsWithPauseUser() async throws {
        let storage = Support.storage()
        storage.save(Support.stored(Support.syntheticCamera.calibration(grade: .good)))
        let service = FakeScanService(still: Support.emptyBoard)
        let camera = Support.camera(service, storage: storage)
        let flow = CalibrationFlowModel(camera: camera)
        await flow.start()
        await flow.validate()
        await flow.adopt()
        flow.startLightingCheck()
        await flow.captureCheckStill()
        service.lightingCheckResult = LightingCheckResult(verdict: .shadowTooHard, tipError: 4, shadowDepth: 0.2,
                                                          recommendedShadowLowerBound: 0.2)
        await flow.confirmTip(at: Support.project(BoardPoint(x: 0, y: 103)))
        #expect(flow.stage == .checkResult(.shadowTooHard) && !camera.lightingCheckPassed)
        flow.close()
        await camera.drainQueue()
        #expect(service.commands == [.arm(boardConfirmedEmpty: true), .pause(.user)])
    }

    @Test func aFlowClosedWithoutTheCheck_depositsNoCommand() async {
        for stopAt in 0..<3 {
            let storage = Support.storage()
            storage.save(Support.stored(Support.syntheticCamera.calibration(grade: .good)))
            let service = FakeScanService(still: Support.emptyBoard)
            let camera = Support.camera(service, storage: storage)
            let flow = CalibrationFlowModel(camera: camera)
            await flow.start()
            if stopAt > 0 { await flow.validate() }
            if stopAt > 1 { await flow.adopt() }
            flow.close()
            await camera.drainQueue()
            #expect(service.commands.isEmpty, "closed at step \(stopAt)")
        }
    }

    // MARK: Calibration on a synthetic image

    @Test func calibration_onASyntheticImage_fromTheFirstTime() async throws {
        let storage = Support.storage()
        let service = FakeScanService(still: Support.emptyBoard)
        let camera = Support.camera(service, storage: storage)
        let flow = CalibrationFlowModel(camera: camera)
        await flow.start()
        // First calibration of this camera: the placement guide first.
        #expect(flow.stage == .placement && camera.readiness == .needsCalibration)
        await flow.continueAfterPlacement()
        // Step 4: the colour locator placed the handles near the junctions; the live wireframe follows them.
        #expect(flow.stage == .adjusting && service.stillRequests == [8])
        let handles = try #require(flow.handles)
        for (found, exact) in zip(handles.points, Support.syntheticCamera.exactHandles().points) {
            #expect(hypot(found.x - exact.x, found.y - exact.y) < 6)
        }
        #expect(flow.preview != nil && flow.canValidate && !flow.issues.contains(where: \.isBlocking))
        await flow.validate()
        let result = try #require(flow.result)
        #expect(flow.stage == .proof && result.quality.refinementApplied && result.quality.grade >= .fair)
        #expect(error(of: result) < 0.5, "error \(error(of: result)) mm")
        #expect(flow.rectified != nil)
        // Step 7: the tap test reads the bed under the finger.
        #expect(flow.tapTest(at: Support.project(BoardPoint(x: 0, y: 103))) == .treble(20))
        #expect(flow.tapTest(at: Support.project(BoardPoint(x: 0, y: 0))) == .innerBull)
        // Step 8: adopted, installed, saved.
        await flow.adopt()
        #expect(camera.readiness == .ready(grade: result.quality.grade) && service.calibrations == [result])
        #expect(storage.loadCalibration(cameraID: "fake", rotationDegrees: 0, imageSize: result.imageSize)?.calibration == result)
    }

    @Test func handlesMovedOutOfPlace_blockValidation_andAdviseThePlayer() async throws {
        let service = FakeScanService(still: Support.emptyBoard)
        let camera = Support.camera(service)
        let flow = CalibrationFlowModel(camera: camera)
        await flow.start()
        await flow.continueAfterPlacement()
        let handles = try #require(flow.handles)
        // The handle of the 6 dragged across the board, left of the 11: the quadrilateral folds.
        let eleven = handles[.wire11_14]
        flow.moveHandle(.wire6_10, to: ImagePoint(x: eleven.x - 200, y: eleven.y))
        #expect(!flow.canValidate && flow.issues.contains(where: \.isBlocking))
        #expect(CalibrationText.advice(for: flow.issues) != nil)
        await flow.validate()
        #expect(flow.stage == .adjusting && flow.result == nil)
        // Back on the junction: valid again.
        flow.moveHandle(.wire6_10, to: handles[.wire6_10])
        #expect(flow.canValidate)
        // "Détection auto" finds the board again.
        await flow.locateAutomatically()
        #expect(flow.canValidate)
    }

    @Test func swappedColours_askToTouchTheTwenty_thenTheWireframeTurns() async throws {
        let storage = Support.storage()
        // A saved calibration whose wireframe is turned by one sector: every handle sits on a junction, but the
        // light and dark sectors are swapped.
        let exact = Support.syntheticCamera.calibration(grade: .good)
        let turned = try #require(exact.handles.rotated(bySectors: 1))
        let saved = BoardCalibration(id: exact.id, createdAt: exact.createdAt, imageSize: exact.imageSize, rotationDegrees: 0,
                                     userHandles: turned, handles: turned, boardToImage: exact.boardToImage,
                                     imageToBoard: exact.imageToBoard, ringRadii: exact.ringRadii, wireHeight: 0,
                                     intrinsics: exact.intrinsics, pose: exact.pose, quality: exact.quality)
        storage.save(Support.stored(saved))
        let service = FakeScanService(still: Support.emptyBoard)
        let camera = Support.camera(service, storage: storage)
        let flow = CalibrationFlowModel(camera: camera)
        await flow.start()
        #expect(flow.stage == .adjusting && flow.handles == turned)
        await flow.validate()
        #expect(flow.stage == .touchTwenty && flow.issues.contains(.sectorPhaseMismatch))
        // The player touches the middle of the real 20, in the single bed.
        await flow.touchTwenty(at: Support.project(BoardPoint(x: 0, y: 140)))
        let result = try #require(flow.result)
        #expect(flow.stage == .proof && !result.quality.issues.contains(.sectorPhaseMismatch))
        #expect(error(of: result) < 0.5)
    }

    @Test func aRefusedCamera_showsTheDeniedScreen_andManualInputGoesOn() async {
        for issue: CameraIssue in [.accessDenied, .noCamera] {
            let service = FakeScanService(issue: issue)
            let camera = Support.camera(service)
            let flow = CalibrationFlowModel(camera: camera)
            await flow.start()
            #expect(flow.stage == .unavailable(issue) && camera.readiness == .unavailable(issue))
            #expect(camera.makeInputSource(mode: .live) == nil)
            flow.close()
            await camera.drainQueue()
            #expect(service.commands.isEmpty)
        }
        // Without a still the camera cannot calibrate either.
        let silent = FakeScanService()
        let flow = CalibrationFlowModel(camera: Support.camera(silent))
        await flow.start()
        await flow.continueAfterPlacement()
        #expect(flow.stage == .unavailable(.noCamera))
    }

    @Test func contentOfTheFlow_followsItsStage() async throws {
        let service = FakeScanService(still: Support.emptyBoard)
        let camera = Support.camera(service)
        let flow = CalibrationFlowModel(camera: camera)
        await flow.start()
        await flow.continueAfterPlacement()
        let adjusting = CalibrationContentModel(flow: flow)
        #expect(adjusting.picture != nil && adjusting.wireframe?.rings.count == 6 && adjusting.wireframe?.wires.count == 20)
        #expect(adjusting.canValidate && adjusting.quality == nil)
        #expect(CalibrationAlignment(issues: adjusting.issues, hasWireframe: true).bars >= 1)
        await flow.validate()
        let proof = CalibrationContentModel(flow: flow)
        #expect(proof.stage == .proof && proof.quality != nil && proof.rectified != nil)
    }

    @Test func alignmentBars_readTheAdviceOfTheHandles() {
        #expect(CalibrationAlignment(issues: [], hasWireframe: true).bars == 3)
        #expect(CalibrationAlignment(issues: [.intrinsicsApproximate], hasWireframe: true).bars == 3)
        #expect(CalibrationAlignment(issues: [.resolutionLow, .intrinsicsApproximate], hasWireframe: true).bars == 2)
        #expect(CalibrationAlignment(issues: [.resolutionLow, .viewTooFrontal], hasWireframe: true).bars == 1)
        #expect(CalibrationAlignment(issues: [.boardOutOfFrame], hasWireframe: true).bars == 0)
        #expect(CalibrationAlignment(issues: [], hasWireframe: false).bars == 0)
        // One advice at a time, the first issue that has one: none for approximate intrinsics.
        #expect(CalibrationText.adviceKey(.intrinsicsApproximate) == nil)
        #expect(CalibrationText.advice(for: [.intrinsicsApproximate]) == nil)
        for issue in CalibrationIssue.allCases where issue != .intrinsicsApproximate {
            #expect(CalibrationText.adviceKey(issue) != nil, "\(issue)")
        }
        #expect(CalibrationText.millimetres(0.46, .fr) == "0,5" && CalibrationText.millimetres(0.46, .en) == "0.5")
    }
}
