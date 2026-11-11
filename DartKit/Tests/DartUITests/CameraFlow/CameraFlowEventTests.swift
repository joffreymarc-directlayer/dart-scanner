import Foundation
import Testing
import DartCore
import DartVision
@testable import DartUI

/// The table "Événements" of ARCHITECTURE.md §8.7: what every `ScanEvent` becomes for the game, the statuses in
/// both trigger modes, the `needsEmptyBoard` request that is kept until a new arming, and the thresholds raised
/// by `accuracyDegraded`. Then the same events from the fake service to `PlayViewModel`.
@MainActor
@Suite struct CameraFlowEventTests {
    private typealias Support = CameraFlowSupport

    private func source(_ mode: ScanMode = .live) -> CameraInputSource {
        CameraInputSource(camera: Support.camera(FakeScanService()), mode: mode)
    }

    @Test func statusOfEveryStateOfTheVision_inBothModes() {
        let rows: [(ScanState, live: InputStatus, photo: InputStatus)] = [
            (.idle, .preparing, .preparing),
            (.arming, .preparing, .preparing),
            (.watching(dartsOnBoard: 0), .live, .awaitingCapture),
            (.watching(dartsOnBoard: 2), .live, .awaitingCapture),
            (.awaitingTakeout, .live, .awaitingCapture),
            (.motion, .live, .preparing),
            (.settling, .live, .preparing),
            (.analysing, .live, .preparing),
            (.takeout, .live, .preparing),
            (.obstructed, .obstructed, .obstructed),
            (.paused(.user), .paused, .paused),
            (.paused(.background), .paused, .paused),
            (.paused(.thermal), .paused, .paused),
            (.needsCalibration, .needsCalibration, .needsCalibration),
            (.calibrationLost, .needsCalibration, .needsCalibration),
        ]
        for row in rows {
            #expect(CameraInputSource.status(for: row.0, mode: .live) == row.live, "\(row.0)")
            #expect(CameraInputSource.status(for: row.0, mode: .photo) == row.photo, "\(row.0)")
        }
    }

    @Test func everyEventOfTheTable() throws {
        let source = source()
        let dart = Support.id(1), other = Support.id(2)
        // dart(observation) → dart(DartProposal(observation:thresholds:)).
        let proposals = source.translate(.dart(Support.observation(dart, .treble(20), tip: BoardPoint(x: 0, y: 103))))
        guard case .dart(let proposal)? = proposals.first, proposals.count == 1 else {
            Issue.record("expected one dart, got \(proposals)")
            return
        }
        #expect(proposal.id == dart && proposal.hit == .treble(20) && proposal.origin == .camera)
        #expect(proposal.position == BoardPoint(x: 0, y: 103))
        // dartDisturbed, dartRemoved, possibleMiss, takeoutCompleted.
        guard case .dartDisturbed(let disturbed)? = source.translate(.dartDisturbed(id: other)).first else {
            Issue.record("dartDisturbed")
            return
        }
        #expect(disturbed == other)
        guard case .dartRemoved(let fell, .fellOut)? = source.translate(.dartRemoved(id: dart, reason: .fellOut)).first,
              case .dartRemoved(let pulled, .takeout)? = source.translate(.dartRemoved(id: other, reason: .takeout)).first else {
            Issue.record("dartRemoved")
            return
        }
        #expect(fell == dart && pulled == other)
        guard case .possibleMiss? = source.translate(.possibleMiss(timestamp: 1.5)).first,
              case .boardCleared? = source.translate(.takeoutCompleted).first else {
            Issue.record("possibleMiss or takeoutCompleted")
            return
        }
        // Nothing for the source: takeoutStarted, the calibrations the model saves, the result of a scan.
        let calibration = Support.syntheticCamera.calibration(grade: .good)
        for silent: ScanEvent in [.takeoutStarted, .calibrationAdjusted(calibration), .calibrationRecovered(calibration),
                                  .scanCompleted([]), .scanCompleted([Support.observation(dart, .single(1))])] {
            #expect(source.translate(silent).isEmpty, "\(silent)")
        }
        #expect(source.status == .preparing)
    }

    @Test func advice_comesFromTheCameraTable_inBothLanguages() {
        let source = source()
        let events: [(ScanEvent, String.LocalizationValue)] = [
            (.takeoutStalled(remaining: [Support.id(1)]), "scan.advice.takeoutStalled"),
            (.lightingChanged, "scan.advice.lightingChanged"),
            (.unrecognizedChange, "scan.advice.unrecognizedChange"),
            (.advisory(.viewObstructed), "scan.advice.viewObstructed"),
            (.advisory(.suggestScanMode), "scan.advice.suggestScanMode"),
            (.advisory(.suggestLightingCheck), "scan.advice.suggestLightingCheck"),
            (.advisory(.flicker), "scan.advice.flicker"),
            (.advisory(.lowLight), "scan.advice.lowLight"),
            (.advisory(.thermalThrottling), "scan.advice.thermalThrottling"),
        ]
        for (event, key) in events {
            guard case .advisory(let text)? = source.translate(event).first else {
                Issue.record("no advice for \(event)")
                continue
            }
            #expect(text.fr == L10n.string(key, .camera, language: .fr) && text.en == L10n.string(key, .camera, language: .en))
            #expect(!text.fr.hasPrefix("scan.") && !text.en.hasPrefix("scan.") && text.fr != text.en, "\(event)")
        }
        // In photo mode the light advice asks for a new empty reference.
        guard case .advisory(let photo)? = self.source(.photo).translate(.lightingChanged).first else {
            Issue.record("no advice in photo mode")
            return
        }
        #expect(photo.fr == L10n.string("scan.advice.lightingChanged.photo", .camera, language: .fr))
    }

    @Test func statuses_arePublishedWhenTheyChange() {
        let source = source()
        #expect(source.status == .preparing)
        #expect(source.translate(.stateChanged(.idle)).cameraFlowStatuses.isEmpty)
        #expect(source.translate(.stateChanged(.arming)).cameraFlowStatuses.isEmpty)
        #expect(source.translate(.stateChanged(.watching(dartsOnBoard: 0))).cameraFlowStatuses == [.live])
        // Motion, settle and analysis are still "live": nothing new to publish.
        for state: ScanState in [.motion, .settling, .analysing, .watching(dartsOnBoard: 1), .awaitingTakeout] {
            #expect(source.translate(.stateChanged(state)).isEmpty, "\(state)")
        }
        #expect(source.translate(.stateChanged(.obstructed)).cameraFlowStatuses == [.obstructed])
        #expect(source.translate(.stateChanged(.paused(.background))).cameraFlowStatuses == [.paused])
        #expect(source.translate(.calibrationLost).cameraFlowStatuses == [.needsCalibration])
        #expect(source.translate(.stateChanged(.calibrationLost)).isEmpty)
        #expect(source.status == .needsCalibration)
    }

    @Test func photoMode_restIsAwaitingCapture_andACaptureIsPreparing() {
        let source = source(.photo)
        #expect(source.translate(.stateChanged(.watching(dartsOnBoard: 0))).cameraFlowStatuses == [.awaitingCapture])
        #expect(source.translate(.stateChanged(.settling)).cameraFlowStatuses == [.preparing])
        #expect(source.translate(.stateChanged(.analysing)).isEmpty)
        #expect(source.translate(.stateChanged(.awaitingTakeout)).cameraFlowStatuses == [.awaitingCapture])
    }

    @Test func needsEmptyBoard_isKeptThroughPauseAndIdle_andLiftedByArming() {
        let source = source()
        _ = source.translate(.stateChanged(.watching(dartsOnBoard: 1)))
        // Resumption on a changed scene: `stateChanged(.idle)` first, then `needsEmptyBoard` (VISION.md §6).
        #expect(source.translate(.stateChanged(.idle)).cameraFlowStatuses == [.preparing])
        #expect(source.translate(.needsEmptyBoard).cameraFlowStatuses == [.needsEmptyBoard])
        for state: ScanState in [.paused(.background), .idle, .watching(dartsOnBoard: 0), .obstructed, .paused(.user)] {
            #expect(source.translate(.stateChanged(state)).isEmpty, "\(state)")
            #expect(source.status == .needsEmptyBoard)
        }
        // Only a new arming lifts it.
        #expect(source.translate(.stateChanged(.arming)).cameraFlowStatuses == [.preparing])
        #expect(source.translate(.stateChanged(.watching(dartsOnBoard: 0))).cameraFlowStatuses == [.live])
    }

    @Test func needsEmptyBoard_isReplacedByTheLossOfTheCalibration() {
        for loss: ScanEvent in [.calibrationLost, .stateChanged(.calibrationLost), .stateChanged(.needsCalibration)] {
            let source = source()
            _ = source.translate(.needsEmptyBoard)
            #expect(source.translate(loss).cameraFlowStatuses == [.needsCalibration], "\(loss)")
            // The request is gone: the next states carry the status again.
            #expect(source.translate(.stateChanged(.watching(dartsOnBoard: 0))).cameraFlowStatuses == [.live])
        }
    }

    @Test func accuracyDegraded_raisesTheHighThreshold_forTheRestOfTheGame() throws {
        let source = source()
        let match = try Support.highScoreMatch()
        let before = Support.observation(Support.id(1), .single(20), confidence: 0.9)
        guard case .dart(let sure)? = source.translate(.dart(before)).first else {
            Issue.record("no dart")
            return
        }
        #expect(sure.certainty(match) == .certain)
        _ = source.translate(.advisory(.accuracyDegraded))
        #expect(source.thresholds.high == VisionConfiguration().confidence.degradedHighThreshold)
        guard case .dart(let doubtful)? = source.translate(.dart(Support.observation(Support.id(2), .single(20), confidence: 0.9))).first else {
            Issue.record("no dart")
            return
        }
        #expect(doubtful.certainty(match) == .needsReview)
        // A rescored dart uses the raised thresholds too.
        _ = source.translate(.stateChanged(.watching(dartsOnBoard: 0)))
        #expect(source.thresholds.high == 0.95)
    }

    @Test func eventsOfTheService_reachTheGame() async throws {
        let service = FakeScanService()
        let camera = Support.camera(service)
        let source = CameraInputSource(camera: camera, mode: .live)
        let game = try Support.game(source: source)
        #expect(game.inputStatus == .preparing)
        let run = Task { await game.run(boardConfirmedEmpty: true) }
        await Support.wait { service.commands.count == 3 }
        await camera.drainQueue()
        #expect(service.commands == [.setTrigger(.automatic), .arm(boardConfirmedEmpty: true), .beginVisit(expectedDarts: 3)])
        service.emit(.stateChanged(.arming))
        service.emit(.stateChanged(.watching(dartsOnBoard: 0)))
        #expect(await Support.wait { game.inputStatus == .live })
        let dart = Support.id(5)
        service.emit(.dart(Support.observation(dart, .treble(20), tip: BoardPoint(x: 1, y: 103))))
        #expect(await Support.wait { game.turnRecords.count == 1 })
        #expect(game.turnRecords.first?.id == dart && game.turnRecords.first?.origin == .camera)
        #expect(game.turnRecords.first?.position == BoardPoint(x: 1, y: 103) && game.turnRecords.first?.needsReview == false)
        // A dart of low confidence waits for the player and is not counted.
        service.emit(.dart(Support.observation(Support.id(6), .single(5), confidence: 0.3)))
        #expect(await Support.wait { game.pending.count == 1 })
        #expect(game.turnRecords.count == 1)
        service.emit(.needsEmptyBoard)
        #expect(await Support.wait { game.inputStatus == .needsEmptyBoard })
        game.confirmBoardEmpty()
        await camera.drainQueue()
        #expect(service.commands.last == .confirmBoardEmpty)
        run.cancel()
    }
}
