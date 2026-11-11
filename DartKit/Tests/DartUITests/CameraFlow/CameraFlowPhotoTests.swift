import Foundation
import Testing
import DartCore
import DartAudio
import DartVision
@testable import DartUI

/// The photo mode (ARCHITECTURE.md §8.7, "Mode photo"; VISION.md §8): the imported photo scored by tapped tips,
/// which needs neither camera nor source; the buttons of "Scanner la volée" and what they deposit; the review of
/// a scan, empty or not.
@MainActor
@Suite(.serialized) struct CameraFlowPhotoTests {
    private typealias Support = CameraFlowSupport

    /// A camera calibrated on the synthetic stand and a game whose source is in manual trigger, at rest.
    private func scanningGame(_ service: FakeScanService) async throws -> (CameraModel, CameraInputSource, PlayViewModel) {
        let camera = Support.camera(service)
        await camera.adopt(Support.syntheticCamera.calibration(grade: .good), lightingCheckPassed: false)
        let source = CameraInputSource(camera: camera, mode: .photo)
        let game = try Support.game(source: source)
        game.handle(.statusChanged(.awaitingCapture))
        return (camera, source, game)
    }

    // MARK: Mandatory test of §8.7: an imported photo

    @Test func importedPhoto_threeTappedTips_giveThreeCertainProposals() async throws {
        let service = FakeScanService(issue: .noCamera)
        let camera = Support.camera(service)
        // A game played by hand: no source.
        let game = try Support.game(source: nil)
        let photo = PhotoModeModel(game: game, camera: camera)
        #expect(photo.canImport && !photo.canTakePhoto && !photo.canCaptureReference && !photo.canScan)
        let png = try #require(Support.threeDarts.pngData())
        await photo.importPhoto(data: png)
        // The photo calibrates itself: the colour locator puts the handles, the calibrator refines them.
        #expect(photo.stage == .photoAdjust && photo.canValidatePhoto)
        await photo.validatePhoto()
        #expect(photo.stage == .photoTips && photo.photoCalibration != nil)
        for tip in Support.tips {
            photo.tapTip(at: Support.project(tip))
        }
        // No more than the darts still expected in the turn.
        photo.tapTip(at: Support.project(BoardPoint(x: 0, y: 0)))
        #expect(photo.tips.count == 3 && photo.hit(atTip: Support.project(Support.tips[0])) == .treble(20))
        photo.confirmTips()
        #expect(photo.stage == .camera && photo.lastHits == [.treble(20), .single(19), .single(7)])
        let records = game.turnRecords
        #expect(records.map(\.hit) == [.treble(20), .single(19), .single(7)])
        #expect(records.allSatisfy { $0.origin == .photo && !$0.needsReview } && game.pending.isEmpty)
        for (record, tip) in zip(records, Support.tips) {
            let position = try #require(record.position)
            #expect(hypot(position.x - tip.x, position.y - tip.y) < 1, "\(record.hit): \(position)")
        }
        // Nothing went to the vision.
        await camera.drainQueue()
        #expect(service.commands.isEmpty)
    }

    @Test func singlePhoto_tipsCanBeRemoved_andThePhotoCancelled() async throws {
        let camera = Support.camera(FakeScanService(issue: .noCamera))
        let game = try Support.game(source: nil)
        let photo = PhotoModeModel(game: game, camera: camera)
        await photo.importPhoto(Support.threeDarts)
        await photo.validatePhoto()
        photo.tapTip(at: Support.project(Support.tips[0]))
        photo.tapTip(at: Support.project(Support.tips[1]))
        photo.removeLastTip()
        #expect(photo.tips.count == 1)
        photo.adjustPhotoAgain()
        #expect(photo.stage == .photoAdjust && photo.tips.isEmpty)
        photo.cancelPhoto()
        #expect(photo.stage == .camera && photo.photo == nil && game.turnRecords.isEmpty)
        // A file that is not a picture.
        await photo.importPhoto(data: Data("not a picture".utf8))
        #expect(photo.stage == .photoFailed && photo.canImport)
    }

    @Test func takenPhoto_isOneFrame() async throws {
        let service = FakeScanService(still: Support.threeDarts)
        let camera = Support.camera(service)
        let game = try Support.game(source: nil)
        let photo = PhotoModeModel(game: game, camera: camera)
        #expect(photo.canTakePhoto)
        await photo.takePhoto()
        #expect(service.stillRequests == [1] && photo.stage == .photoAdjust)
    }

    // MARK: Mandatory test of §8.7: the buttons of "Scanner la volée"

    @Test func emptyBoardAndScan_areInactiveOutsideAwaitingCapture() async throws {
        let service = FakeScanService(still: Support.emptyBoard)
        let (camera, _, scanning) = try await scanningGame(service)
        let model = PhotoModeModel(game: scanning, camera: camera)
        #expect(model.canCaptureReference && model.canScan && model.remainingDarts == 3)
        for status: InputStatus in [.preparing, .live, .obstructed, .paused, .needsCalibration, .unavailable] {
            scanning.handle(.statusChanged(status))
            #expect(!model.canCaptureReference && !model.canScan, "\(status)")
        }
        // "Videz la cible, puis confirmez": "Cible vide" is the confirmation; "Scanner" stays inactive.
        scanning.handle(.statusChanged(.needsEmptyBoard))
        #expect(model.canCaptureReference && !model.canScan)
        scanning.handle(.statusChanged(.awaitingCapture))
        #expect(model.canCaptureReference && model.canScan)
        // A camera that is not calibrated.
        let uncalibrated = PhotoModeModel(game: scanning, camera: Support.camera(FakeScanService()))
        #expect(!uncalibrated.canCaptureReference && !uncalibrated.canScan)
    }

    @Test func scan_asksForTheDartsStillExpected_andIsInactiveWhenTheTurnIsFullOrClosed() async throws {
        let service = FakeScanService(still: Support.emptyBoard)
        let (camera, _, game) = try await scanningGame(service)
        let model = PhotoModeModel(game: game, camera: camera)
        model.scan()
        await camera.drainQueue()
        #expect(service.commands.last == .captureNow(maxDarts: 3))
        // "Scanner" stays inactive from the press to `scanCompleted`.
        #expect(model.stage == .scanning && !model.canScan && !model.canCaptureReference)
        model.handle(.scanCompleted([]))
        model.confirmReview()
        // One dart counted by hand, one waiting for an answer: one dart still expected in the turn. The scan asks
        // for the two the vision has not returned: the dart entered by hand is not in its reference, and the
        // review discards its duplicate (CameraFlowReviewFinalTests).
        game.tapBoard(BoardTap(hit: .single(20), position: BoardPoint(x: 0, y: 140)))
        game.receive(DartProposal(observation: Support.observation(Support.id(9), .single(5), confidence: 0.2, source: .scan),
                                  thresholds: .standard))
        game.correction = nil
        #expect(game.turnRecords.count == 1 && game.pending.count == 1 && model.remainingDarts == 1)
        model.scan()
        await camera.drainQueue()
        #expect(service.commands.last == .captureNow(maxDarts: 2))
        model.handle(.scanCompleted([]))
        model.confirmReview()
        // Full: three darts counted or waiting.
        game.resolvePending(with: .single(5))
        game.tapBoard(BoardTap(hit: .single(1), position: BoardPoint(x: 20, y: 140)))
        #expect(game.turnRecords.count == 3 && model.remainingDarts == 0)
        #expect(!model.canScan && model.canCaptureReference)
        // Closed by the rules (phase `turnComplete`): still inactive; "Cible vide" stays active.
        #expect(game.snapshot.phase == .turnComplete && !model.canScan)
        await camera.drainQueue()
        let before = service.commands
        #expect(before.suffix(2) == [.registerManualDart, .endVisit])
        model.scan()
        await camera.drainQueue()
        #expect(service.commands == before)
        model.captureReference()
        await camera.drainQueue()
        #expect(service.commands.last == .captureReference)
    }

    // MARK: Mandatory test of §8.7: an empty scan

    @Test func emptyScan_showsAnEmptyReview_andSendsNothingToTheGame() async throws {
        let service = FakeScanService(still: Support.emptyBoard)
        let (camera, _, game) = try await scanningGame(service)
        let model = PhotoModeModel(game: game, camera: camera)
        let listening = Task { await model.listen() }
        await Task.yield()
        model.scan()
        service.emit(.stateChanged(.settling))
        service.emit(.scanCompleted([]))
        #expect(await Support.wait { model.stage == .review })
        #expect(model.reviewed.isEmpty && model.emptyCause == nil && game.turnRecords.isEmpty && game.pending.isEmpty)
        let content = PhotoModeContentModel(model: model)
        #expect(content.stage == .review && content.review.isEmpty)
        model.confirmReview()
        #expect(model.stage == .camera && game.turnRecords.isEmpty && model.lastHits.isEmpty)
        listening.cancel()
    }

    @Test func emptyScan_namesItsCause() async throws {
        let service = FakeScanService(still: Support.emptyBoard)
        let (camera, _, game) = try await scanningGame(service)
        let causes: [(ScanEvent, PhotoModeModel.EmptyCause)] = [(.advisory(.viewObstructed), .obstructed),
                                                                (.lightingChanged, .lighting),
                                                                (.stateChanged(.paused(.background)), .interrupted)]
        for (event, cause) in causes {
            let model = PhotoModeModel(game: game, camera: camera)
            model.scan()
            model.handle(event)
            model.handle(.scanCompleted([]))
            #expect(model.stage == .review && model.emptyCause == cause, "\(event)")
            model.confirmReview()
        }
        // After a change of light the player must take "Cible vide" again.
        let model = PhotoModeModel(game: game, camera: camera)
        model.handle(.lightingChanged)
        #expect(model.needsNewReference)
        model.captureReference()
        #expect(!model.needsNewReference)
    }

    @Test func scanResult_goesToTheGame_inTheOrderThePlayerKeeps() async throws {
        let service = FakeScanService(still: Support.emptyBoard)
        let (camera, _, game) = try await scanningGame(service)
        let model = PhotoModeModel(game: game, camera: camera)
        let first = Support.observation(Support.id(1), .treble(20), source: .scan)
        let second = Support.observation(Support.id(2), .single(1), source: .scan)
        let phantom = Support.observation(Support.id(3), .single(18), source: .scan)
        model.scan()
        model.handle(.scanCompleted([first, second, phantom]))
        #expect(model.reviewed.map(\.id) == [first.id, second.id, phantom.id])
        model.moveUp(1)
        model.discard(2)
        await camera.drainQueue()
        #expect(service.commands.last == .discardDart(phantom.id))
        model.confirmReview()
        #expect(game.turnRecords.map(\.id) == [second.id, first.id])
        #expect(game.turnRecords.map(\.origin) == [.scan, .scan] && model.lastHits == [.single(1), .treble(20)])
    }

    @Test func withoutACamera_onlyImportIsActive() throws {
        let camera = Support.camera(FakeScanService(issue: .noCamera))
        let game = try Support.game(source: nil)
        let content = PhotoModeContentModel(model: PhotoModeModel(game: game, camera: camera))
        #expect(!content.hasCamera && content.canImport && !content.canTakePhoto && !content.canScan && !content.canCaptureReference)
        let fixture = CameraFlowFixtures.photoModeWithoutCamera
        #expect(!fixture.hasCamera && fixture.canImport && !fixture.canTakePhoto && !fixture.canScan && !fixture.canCaptureReference)
    }
}
