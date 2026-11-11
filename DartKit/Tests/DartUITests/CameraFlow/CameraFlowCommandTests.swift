import Foundation
import Testing
import DartCore
import DartVision
@testable import DartUI

/// The table "Commandes" of ARCHITECTURE.md §8.7 and the single command queue of `CameraModel` (§8.4.8, §11):
/// every writer deposits with `enqueue`, one task delivers, the service receives the commands in the order of the
/// calls. Lists of commands are compared whole with `==` (`ScanCommand` is `Hashable`).
@MainActor
@Suite struct CameraFlowCommandTests {
    private typealias Support = CameraFlowSupport

    @Test func gameStarted_depositsSetTriggerThenArm_atTheFirstGameAndAtTheNext() async {
        let service = FakeScanService()
        let camera = Support.camera(service)
        let first = CameraInputSource(camera: camera, mode: .live)
        first.gameStarted(boardConfirmedEmpty: true)
        await camera.drainQueue()
        #expect(service.commands == [.setTrigger(.automatic), .arm(boardConfirmedEmpty: true)])
        // The next game, in photo mode: `setTrigger` again, because `arm` does not reset the trigger. The board
        // was not confirmed empty ("Pas encore"): nothing is armed until the player confirms it (§8.7).
        first.gameEnded()
        let next = CameraInputSource(camera: camera, mode: .photo)
        next.gameStarted(boardConfirmedEmpty: false)
        await camera.drainQueue()
        #expect(service.commands == [.setTrigger(.automatic), .arm(boardConfirmedEmpty: true), .pause(.user)])
        next.boardConfirmedEmpty()
        await camera.drainQueue()
        #expect(service.commands == [.setTrigger(.automatic), .arm(boardConfirmedEmpty: true), .pause(.user),
                                     .setTrigger(.manual), .arm(boardConfirmedEmpty: true)])
    }

    @Test func everyCommandOfTheTable() async {
        let service = FakeScanService()
        let camera = Support.camera(service)
        let source = CameraInputSource(camera: camera, mode: .live)
        let phantom = Support.id(7)
        source.gameStarted(boardConfirmedEmpty: true)
        source.turnBegan(expectedDarts: 3)
        source.manualDartAdded()
        source.dartDiscarded(phantom)
        source.turnClosed()
        source.boardConfirmedEmpty()
        source.turnBegan(expectedDarts: 2)
        source.gameEnded()
        await camera.drainQueue()
        #expect(service.commands == [.setTrigger(.automatic), .arm(boardConfirmedEmpty: true), .beginVisit(expectedDarts: 3),
                                     .registerManualDart, .discardDart(phantom), .endVisit, .confirmBoardEmpty,
                                     .beginVisit(expectedDarts: 2), .pause(.user)])
        #expect(service.feedback.isEmpty)
    }

    @Test func turnConfirmed_reportsEveryDartOnce() async {
        let service = FakeScanService()
        let camera = Support.camera(service)
        let source = CameraInputSource(camera: camera, mode: .live)
        let a = Support.id(1), b = Support.id(2), c = Support.id(3)
        source.turnConfirmed([DartFeedback(id: a, wasCorrected: false), DartFeedback(id: b, wasCorrected: true)])
        // The same turn confirmed again after an undo, with one more dart: only the new one is reported.
        source.turnConfirmed([DartFeedback(id: a, wasCorrected: false), DartFeedback(id: b, wasCorrected: true),
                              DartFeedback(id: c, wasCorrected: false)])
        await camera.drainQueue()
        #expect(service.feedback.map(\.id) == [a, b, c])
        #expect(service.feedback.map(\.wasCorrected) == [false, true, false])
        #expect(service.commands.isEmpty)
    }

    @Test func aHundredCommands_arriveInTheOrderOfTheDeposits() async {
        let service = FakeScanService()
        let camera = Support.camera(service)
        var expected: [ScanCommand] = []
        for index in 0..<100 {
            let command: ScanCommand
            switch index % 5 {
            case 0: command = .beginVisit(expectedDarts: index % 4)
            case 1: command = .endVisit
            case 2: command = .discardDart(Support.id(index))
            case 3: command = .captureNow(maxDarts: index % 3 + 1)
            default: command = .registerManualDart
            }
            expected.append(command)
            camera.enqueue(command)
        }
        // Deposits are synchronous: nothing has reached the service before the queue runs.
        #expect(service.commands.isEmpty)
        await camera.drainQueue()
        #expect(service.commands == expected)
    }

    @Test func feedbackAndCommands_shareTheSameQueue() async {
        let service = FakeScanService()
        let camera = Support.camera(service)
        let source = CameraInputSource(camera: camera, mode: .live)
        let dart = Support.id(1)
        source.turnConfirmed([DartFeedback(id: dart, wasCorrected: true)])
        source.turnBegan(expectedDarts: 3)
        await camera.drainQueue()
        #expect(service.feedback.map(\.id) == [dart])
        #expect(service.commands == [.beginVisit(expectedDarts: 3)])
    }

    @Test func writers_turnBeganOfTheSource_thenCaptureNowOfThePhotoMode() async throws {
        let service = FakeScanService(still: Support.emptyBoard)
        let camera = Support.camera(service)
        await camera.adopt(Support.syntheticCamera.calibration(grade: .good), lightingCheckPassed: false)
        let source = CameraInputSource(camera: camera, mode: .photo)
        let game = try Support.game(source: source)
        game.handle(.statusChanged(.awaitingCapture))
        let photo = PhotoModeModel(game: game, camera: camera)
        source.turnBegan(expectedDarts: 3)
        photo.scan()
        await camera.drainQueue()
        #expect(service.commands == [.beginVisit(expectedDarts: 3), .captureNow(maxDarts: 3)])
    }

    @Test func writers_gameEndedOfTheOldSource_thenGameStartedOfTheNew() async {
        let service = FakeScanService()
        let camera = Support.camera(service)
        let old = CameraInputSource(camera: camera, mode: .live)
        let rematch = CameraInputSource(camera: camera, mode: .live)
        old.gameEnded()
        rematch.gameStarted(boardConfirmedEmpty: true)
        await camera.drainQueue()
        #expect(service.commands == [.pause(.user), .setTrigger(.automatic), .arm(boardConfirmedEmpty: true)])
    }

    @Test func setForeground_alwaysDepositsPauseBackgroundThenResume_evenAfterTheEndOfAGame() async {
        let service = FakeScanService()
        let camera = Support.camera(service)
        camera.setForeground(false)
        camera.setForeground(true)
        await camera.drainQueue()
        #expect(service.commands == [.pause(.background), .resume])
        // After a game: the queue does not filter this `resume`; the state machine ignores it (row P2c).
        let source = CameraInputSource(camera: camera, mode: .live)
        source.gameEnded()
        camera.setForeground(false)
        camera.setForeground(true)
        await camera.drainQueue()
        #expect(service.commands == [.pause(.background), .resume, .pause(.user), .pause(.background), .resume])
    }

    @Test func gameEnded_isDepositedOnce_andEndsTheStreamsOfTheSource() async {
        let service = FakeScanService()
        let camera = Support.camera(service)
        let source = CameraInputSource(camera: camera, mode: .live)
        let events = source.events()
        source.gameEnded()
        source.gameEnded()
        var count = 0
        for await _ in events { count += 1 }
        #expect(count == 0)
        // A stream asked after the end finishes at once; commands after the end are not lost but `gameStarted` is.
        for await _ in source.events() { count += 1 }
        source.gameStarted(boardConfirmedEmpty: true)
        await camera.drainQueue()
        #expect(count == 0 && service.commands == [.pause(.user)])
    }

    @Test func queries_doNotGoThroughTheQueue() async {
        let service = FakeScanService()
        let camera = Support.camera(service)
        let source = CameraInputSource(camera: camera, mode: .live)
        let id = Support.id(3)
        #expect(await source.rescore(id, tip: BoardPoint(x: 1, y: 2)) == nil)
        service.correctionResult = Support.observation(id, .treble(19), source: .tappedOnPhoto)
        let rescored = await source.rescore(id, tip: BoardPoint(x: 3, y: 4))
        #expect(rescored?.id == id && rescored?.hit == .treble(19) && rescored?.origin == .photo)
        #expect(service.corrections.map(\.tip) == [BoardPoint(x: 1, y: 2), BoardPoint(x: 3, y: 4)])
        #expect(await source.evidenceImage(for: id) == nil)
        await camera.drainQueue()
        #expect(service.commands.isEmpty)
    }

    @Test func makeInputSource_givesASourceUnlessTheCameraIsKnownToBeUnavailable() async {
        let available = Support.camera(FakeScanService())
        // Cold start: `readiness` is still unknown, a source is given all the same (§8.5).
        #expect(available.readiness == .unknown && available.makeInputSource(mode: .live) != nil)
        #expect(available.makeInputSource(mode: .photo)?.status == .preparing)
        let unavailable = Support.camera(FakeScanService(issue: .noCamera))
        #expect(unavailable.makeInputSource(mode: .live) == nil)
        await unavailable.activate()
        #expect(unavailable.readiness == .unavailable(.noCamera) && unavailable.makeInputSource(mode: .photo) == nil)
    }
}
