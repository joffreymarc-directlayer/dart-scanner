import Foundation
import Testing
import SwiftUI
import DartCore
import DartAudio
import DartVision
@testable import DartUI
#if os(macOS)
import AppKit
#endif

/// Final review of the camera flow (lot U3): "Pas encore" never arms the vision on a board that still holds darts;
/// the single photo stops on a wireframe turned by a sector, as the calibration does; the review of a scan cannot be
/// left without an answer; "Scanner" asks for the darts the vision has not returned yet; the review uses the
/// thresholds of the game's source.
@MainActor
@Suite(.serialized) struct CameraFlowReviewFinalTests {
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

    // MARK: "La cible est-elle vide ?" → "Pas encore"

    /// "Pas encore": nothing arms the vision; the game shows "Videz la cible, puis confirmez"; what the vision might
    /// still report is not a dart of the game. The confirmation arms on the empty board and restores the visit.
    @Test func notYet_theVisionIsArmedOnlyOnceTheBoardIsConfirmedEmpty() async throws {
        let service = FakeScanService(still: Support.emptyBoard)
        let camera = Support.camera(service)
        await camera.adopt(Support.syntheticCamera.calibration(grade: .good), lightingCheckPassed: false)
        service.state = .paused(.user)
        let source = try #require(camera.makeInputSource(mode: .live) as? CameraInputSource)
        let game = try Support.game(source: source)
        let running = Task { await game.run(boardConfirmedEmpty: false) }
        #expect(await Support.wait { game.inputStatus == .needsEmptyBoard })
        await camera.drainQueue()
        #expect(!service.commands.contains { if case .arm = $0 { return true } else { return false } },
                "the vision was armed on a board that still holds darts: \(service.commands)")
        // An old dart pulled out of the board, read as a dart by a vision that would be watching.
        service.emit(.stateChanged(.watching(dartsOnBoard: 0)))
        service.emit(.dart(Support.observation(Support.id(1), .treble(20), confidence: 0.4)))
        service.emit(.possibleMiss(timestamp: 0))
        for _ in 0..<20 { await Task.yield() }
        #expect(game.pending.isEmpty && game.turnRecords.isEmpty && game.prompt == nil)
        #expect(game.inputStatus == .needsEmptyBoard)
        // A dart entered by hand meanwhile: the visit is restored with it.
        game.tapBoard(BoardTap(hit: .single(5), position: .centre))
        // "Elle est vide": armed on the empty board, then the visit as the game last described it.
        let before = service.commands.count
        game.confirmBoardEmpty()
        await camera.drainQueue()
        #expect(Array(service.commands.dropFirst(before)) == [.setTrigger(.automatic), .arm(boardConfirmedEmpty: true),
                                                             .beginVisit(expectedDarts: 2)])
        service.emit(.stateChanged(.arming))
        #expect(await Support.wait { game.inputStatus == .preparing })
        service.emit(.stateChanged(.watching(dartsOnBoard: 0)))
        #expect(await Support.wait { game.inputStatus == .live })
        // From now on a dart of the vision is a dart of the game.
        service.emit(.dart(Support.observation(Support.id(2), .single(19))))
        #expect(await Support.wait { game.turnRecords.count == 2 })
        running.cancel()
        game.suspend()
    }

    /// Without a valid calibration the question is not asked (`boardConfirmedEmpty: false`): the source says the
    /// calibration is missing, never "Videz la cible".
    @Test func notYet_withoutACalibration_theSourceStillSaysNeedsCalibration() async throws {
        let service = FakeScanService(still: Support.emptyBoard)
        let camera = Support.camera(service)
        let source = try #require(camera.makeInputSource(mode: .live))
        await camera.activate()
        let recorder = CameraFlowRecorder(source.events())
        source.gameStarted(boardConfirmedEmpty: false)
        #expect(await Support.wait { recorder.items.cameraFlowStatuses == [.needsCalibration] })
        // Calibrated later: the board must then be confirmed empty.
        service.emit(.stateChanged(.idle))
        #expect(await Support.wait { recorder.items.cameraFlowStatuses == [.needsCalibration, .needsEmptyBoard] })
        recorder.cancel()
    }

    // MARK: Single photo

    /// A wireframe turned by one sector (the handles one wire off) scores every dart wrong: the photo stops at
    /// "touchez le vrai 20", as the calibration does, then scores the true hits.
    @Test func photoPath_aWireframeTurnedByASector_asksForTheTwenty() async throws {
        let camera = Support.camera(FakeScanService(issue: .noCamera))
        let game = try Support.game(source: nil)
        let photo = PhotoModeModel(game: game, camera: camera)
        await photo.importPhoto(Support.threeDarts)
        #expect(photo.stage == .photoAdjust)
        let located = try #require(photo.photoHandles)
        let turned = try #require(located.rotated(bySectors: 1))
        for handle in CalibrationHandle.allCases { photo.movePhotoHandle(handle, to: turned[handle]) }
        await photo.validatePhoto()
        #expect(photo.stage == .photoTouchTwenty, "stage \(photo.stage), issues \(photo.photoIssues)")
        // No tip can be touched before the 20 is fixed.
        photo.tapTip(at: Support.project(Support.tips[0]))
        #expect(photo.tips.isEmpty)
        // The real 20, in the single 20 between the two rings.
        await photo.touchPhotoTwenty(at: Support.project(BoardPoint(x: 0, y: 130)))
        #expect(photo.stage == .photoTips, "stage \(photo.stage), issues \(photo.photoIssues)")
        #expect(!photo.photoIssues.contains(.sectorPhaseMismatch))
        for tip in Support.tips { photo.tapTip(at: Support.project(tip)) }
        photo.confirmTips()
        #expect(game.turnRecords.map(\.hit) == [.treble(20), .single(19), .single(7)])
    }

    /// A photo calibration graded `poor` (VISION.md §4.7): every touched tip is "à vérifier".
    @Test func photoPath_aPoorCalibration_givesDartsToCheck() async throws {
        let camera = Support.camera(FakeScanService(issue: .noCamera))
        let game = try Support.game(source: nil)
        let photo = PhotoModeModel(game: game, camera: camera)
        await photo.importPhoto(Support.threeDarts)
        var handles = try #require(photo.photoHandles)
        // Handles 12 px off (VISION.md C4): the refinement is refused and the grade is poor.
        for handle in CalibrationHandle.allCases {
            let point = handles[handle]
            handles[handle] = ImagePoint(x: point.x + 12, y: point.y)
            photo.movePhotoHandle(handle, to: handles[handle])
        }
        await photo.validatePhoto()
        let calibration = try #require(photo.photoCalibration)
        try #require(calibration.quality.grade == .poor, "grade \(calibration.quality.grade), issues \(photo.photoIssues)")
        #expect(photo.stage == .photoTips)
        photo.tapTip(at: Support.project(Support.tips[0]))
        photo.confirmTips()
        #expect(game.turnRecords.count + game.pending.count == 1)
        #expect(game.turnRecords.allSatisfy { $0.needsReview }, "\(game.turnRecords)")
    }

    // MARK: "Scanner la volée"

    /// "Scanner" asks for the darts the vision has not returned: a dart entered by hand is still in the board and
    /// not in the vision's reference, so the scan proposes it again (the review discards it) and must not take the
    /// place of the last real dart.
    @Test func scan_asksForTheDartsTheVisionHasNotReturned() async throws {
        let service = FakeScanService(still: Support.emptyBoard)
        let (camera, _, game) = try await scanningGame(service)
        game.tapBoard(BoardTap(hit: .single(9), position: .centre))
        game.handle(.statusChanged(.awaitingCapture))
        let model = PhotoModeModel(game: game, camera: camera)
        #expect(model.remainingDarts == 2)
        model.scan()
        await camera.drainQueue()
        #expect(service.commands.last == .captureNow(maxDarts: 3), "\(service.commands)")
        // A dart of a previous scan is in the vision's reference: it is not asked for again.
        model.handle(.scanCompleted([Support.observation(Support.id(3), .single(4), source: .scan)]))
        model.confirmReview()
        #expect(game.turnRecords.map(\.origin) == [.manual, .scan])
        model.scan()
        await camera.drainQueue()
        #expect(service.commands.last == .captureNow(maxDarts: 2), "\(service.commands)")
    }

    /// After `advisory(.accuracyDegraded)` the source raises its high threshold for the rest of the game
    /// (§8.7, "Seuils de palier"): the review of a scan counts with the same thresholds.
    @Test func review_usesTheThresholdsOfTheGameSource() async throws {
        let service = FakeScanService(still: Support.emptyBoard)
        let camera = Support.camera(service)
        await camera.adopt(Support.syntheticCamera.calibration(grade: .good), lightingCheckPassed: false)
        let source = try #require(camera.makeInputSource(mode: .photo) as? CameraInputSource)
        let game = try Support.game(source: source)
        let recorder = CameraFlowRecorder(source.events())
        source.gameStarted(boardConfirmedEmpty: true)
        service.emit(.advisory(.accuracyDegraded))
        #expect(await Support.wait { source.thresholds.high > 0.9 })
        game.handle(.statusChanged(.awaitingCapture))
        let model = PhotoModeModel(game: game, camera: camera)
        model.scan()
        let observation = Support.observation(Support.id(4), .treble(20), confidence: 0.9, source: .scan)
        model.handle(.scanCompleted([observation]))
        model.confirmReview()
        let expected = DartProposal(observation: observation, thresholds: source.thresholds).certainty(game.match)
        #expect(expected == .needsReview)
        #expect(game.turnRecords.map(\.needsReview) == [true])
        recorder.cancel()
    }

    /// A scan the vision never answers (a capture it did not accept) does not keep the photo mode closed for
    /// good: after the wait, the camera stage comes back.
    @Test func scan_withoutAnAnswer_givesTheCameraStageBack() async throws {
        let service = FakeScanService(still: Support.emptyBoard)
        let (camera, _, game) = try await scanningGame(service)
        let model = PhotoModeModel(game: game, camera: camera)
        model.scanTimeout = .milliseconds(50)
        model.scan()
        #expect(model.stage == .scanning)
        #expect(await Support.wait { model.stage == .camera })
        #expect(model.emptyCause == nil && game.turnRecords.isEmpty)
        // A late result is still shown.
        model.handle(.scanCompleted([Support.observation(Support.id(5), .single(1), source: .scan)]))
        #expect(model.stage == .review && model.reviewed.count == 1)
    }

    #if os(macOS)
    /// The darts of a scan are counted by the vision as soon as it answers: the review cannot be left by "Retour"
    /// (its own buttons answer it), nor can a scan under way.
    @Test func review_andScan_cannotBeLeftByTheBackButton() {
        for stage in [PhotoModeModel.Stage.camera, .scanning, .review] {
            var closed = 0
            let model = PhotoModeContentModel(stage: stage, hasCamera: false,
                                              review: [PhotoReviewItem(id: Support.id(6), hit: .treble(20), needsCheck: false)])
            let size = CGSize(width: 393, height: 852)
            _ = NSApplication.shared
            let window = NSWindow(contentRect: NSRect(x: -30_000, y: -30_000, width: size.width, height: size.height),
                                  styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: PhotoModeContent(model: model, actions: PhotoModeActions(close: { closed += 1 }))
                .frame(width: size.width, height: size.height)
                .environment(\.colorScheme, .dark)
                .environment(\.horizontalSizeClass, .compact)
                .appLanguage(.fr))
            window.orderFrontRegardless()
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.3))
            // The round back button: 44 pt, in the margin (20 pt), under the top padding (16 pt).
            let location = CGPoint(x: 20 + 22, y: size.height - (16 + 22))
            for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                if let event = NSEvent.mouseEvent(with: type, location: location, modifierFlags: [],
                                                  timestamp: ProcessInfo.processInfo.systemUptime,
                                                  windowNumber: window.windowNumber, context: nil, eventNumber: 0,
                                                  clickCount: 1, pressure: 1) {
                    window.sendEvent(event)
                }
                RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))
            }
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.3))
            window.close()
            #expect(closed == (stage == .camera ? 1 : 0), "\(stage): back pressed \(closed) time(s)")
        }
    }
    #endif
}
