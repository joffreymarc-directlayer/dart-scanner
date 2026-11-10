import Foundation
import Testing
import DartCore
import DartGames
import DartAudio
import DartTestSupport
@testable import DartUI

/// `PlayViewModel` against ARCHITECTURE.md §8.6, with a source that records its commands and `SilentSoundPlayer`.
/// Darts are `DartProposal` values with fixed ids, so that saved games compare equal from one run to the next.
@MainActor
@Suite struct GameFlowPlayViewModelTests {
    // MARK: Start-up (§8.6, "Démarrage")

    @Test func run_newGame_opensTheStreamThenStartsTheSourceThenAnnouncesTheFirstPlayer() async throws {
        let rig = try GameFlowRig(.killer, ["level": "hard"], players: 2, seed: 1)
        let task = await rig.start(boardConfirmedEmpty: true)
        #expect(rig.source?.streamsOpened == 1)
        #expect(rig.commands == [.gameStarted(boardConfirmedEmpty: true), .turnBegan(expectedDarts: 3)])
        // "Au tour de J1": the interface cue `gameStarted`.
        #expect(rig.sound.played == CueMapping.cues(for: .gameStarted(firstPlayer: 0),
                                                    context: CueContext(gameID: .killer, players: testPlayers(2))))
        rig.source?.finish()
        await task.value
    }

    @Test func run_gameResumedInTheMiddleOfATurn_beginsTheTurnWithTheDartsStillExpected() async throws {
        let rig = try GameFlowRig(.highScore, players: 2, script: "T20, S5")
        let task = await rig.start()
        #expect(rig.commands == [.gameStarted(boardConfirmedEmpty: false), .turnBegan(expectedDarts: 1)])
        rig.source?.finish()
        await task.value
    }

    @Test func run_gameResumedOnAClosedTurn_closesTheTurn() async throws {
        let rig = try GameFlowRig(.highScore, players: 2, script: "T20, S5, S1")
        let task = await rig.start()
        #expect(rig.commands == [.gameStarted(boardConfirmedEmpty: false), .turnClosed])
        rig.source?.finish()
        await task.value
    }

    @Test func run_secondCall_onlySubscribesAgain() async throws {
        let rig = try GameFlowRig(.highScore, players: 1)
        let first = await rig.start()
        rig.source?.finish()
        await first.value
        let game = rig.game
        let second = Task { @MainActor in await game.run(boardConfirmedEmpty: true) }
        await rig.settle()
        #expect(rig.source?.streamsOpened == 2)
        #expect(rig.commands == [.gameStarted(boardConfirmedEmpty: false), .turnBegan(expectedDarts: 3)])
        #expect(rig.sound.played.count == 1)
        rig.source?.finish()
        await second.value
    }

    @Test func run_withoutASource_announcesAndReturns() async throws {
        let rig = try GameFlowRig(.highScore, players: 2, withSource: false)
        await rig.game.run(boardConfirmedEmpty: false)
        #expect(rig.game.hasStarted && rig.game.inputStatus == .manualOnly && !rig.game.hasSource)
        #expect(rig.spoken == ["Au tour de J1"])
    }

    @Test func eventsOfTheStream_reachTheGame_inOrder() async throws {
        let rig = try GameFlowRig(.highScore, players: 1)
        let source = try #require(rig.source)
        let task = await rig.start()
        source.emit(.statusChanged(.live))
        source.emit(.dart(gameFlowProposal("T20", id: 1)))
        source.emit(.dart(gameFlowProposal("S5", id: 2)))
        source.emit(.dart(gameFlowProposal("D1", id: 3)))
        source.finish()
        await task.value
        #expect(rig.game.inputStatus == .live)
        #expect(rig.notations() == ["T20", "S5", "D1"])
        #expect(rig.game.turnRecords.map(\.id) == [gameFlowID(1), gameFlowID(2), gameFlowID(3)])
        #expect(rig.commands == [.gameStarted(boardConfirmedEmpty: false), .turnBegan(expectedDarts: 3), .turnClosed])
    }

    // MARK: Arrival of a dart (§8.6, "Arrivée d'une fléchette")

    @Test func receive_threeCertainties() throws {
        let rig = try GameFlowRig(.highScore, players: 1)
        // Certain: counted, not flagged.
        rig.game.receive(gameFlowProposal("T20", id: 1, certainty: .certain))
        #expect(rig.notations() == ["T20"] && rig.game.turnRecords[0].needsReview == false)
        // Needs review: counted AND flagged, followed by the `dartNeedsReview` cue.
        let beforeReview = rig.sound.played.count
        rig.game.receive(gameFlowProposal("S19", id: 2, certainty: .needsReview))
        #expect(rig.notations() == ["T20", "S19"] && rig.game.turnRecords[1].needsReview)
        let reviewCues = Array(rig.sound.played[beforeReview...])
        #expect(reviewCues.suffix(1) == CueMapping.cues(for: .dartNeedsReview,
                                                        context: CueContext(gameID: .highScore, players: testPlayers(1))))
        // Undecided: NOT sent to the game, queued, the correction sheet opens on it.
        let beforeUndecided = rig.sound.played.count
        rig.game.receive(gameFlowProposal("T3", id: 3, certainty: .undecided))
        #expect(rig.notations() == ["T20", "S19"])
        #expect(rig.game.pending.map(\.id) == [gameFlowID(3)])
        #expect(rig.game.correction == .pending(id: gameFlowID(3)))
        #expect(Array(rig.sound.played[beforeUndecided...]) == CueMapping.cues(for: .dartUndecided,
                                                                             context: CueContext(gameID: .highScore, players: testPlayers(1))))
        #expect(!rig.game.canEndTurn)
    }

    @Test func receive_behindAnUndecidedDart_queuesInOrder_andResolvingReplaysThem() throws {
        let rig = try GameFlowRig(.highScore, players: 1)
        rig.game.receive(gameFlowProposal("T20", id: 1, certainty: .undecided))
        rig.game.receive(gameFlowProposal("S5", id: 2, certainty: .certain))
        rig.game.receive(gameFlowManual("S1", id: 3))
        #expect(rig.game.pending.map(\.id) == [gameFlowID(1), gameFlowID(2), gameFlowID(3)])
        #expect(rig.game.turnRecords.isEmpty && rig.commands.isEmpty)
        rig.game.resolvePending(with: .treble(20))
        #expect(rig.game.pending.isEmpty && rig.game.correction == nil)
        #expect(rig.game.turnRecords.map(\.id) == [gameFlowID(1), gameFlowID(2), gameFlowID(3)])
        #expect(rig.notations() == ["T20", "S5", "S1"])
        // The manual dart is reported, then the third dart closes the turn.
        #expect(rig.commands == [.manualDartAdded, .turnClosed])
    }

    @Test func resolvePending_stopsAtTheNextUndecidedDart() throws {
        let rig = try GameFlowRig(.highScore, players: 1)
        rig.game.receive(gameFlowProposal("T20", id: 1, certainty: .undecided))
        rig.game.receive(gameFlowProposal("S5", id: 2))
        rig.game.receive(gameFlowProposal("S7", id: 3, certainty: .undecided))
        rig.game.receive(gameFlowProposal("S1", id: 4))
        rig.game.resolvePending(with: .treble(20))
        #expect(rig.notations() == ["T20", "S5"])
        #expect(rig.game.pending.map(\.id) == [gameFlowID(3), gameFlowID(4)])
        #expect(rig.game.correction == .pending(id: gameFlowID(3)))
        rig.game.resolvePending(with: .single(7))
        #expect(rig.notations() == ["T20", "S5", "S7"] && rig.game.pending.isEmpty)
        // The fourth dart arrived after the turn was closed by the third: it is dropped.
        #expect(rig.game.prompt == .dartIgnored)
    }

    @Test func resolvePending_sameHitKeepsThePosition_anotherHitIsCorrectedWithoutPosition() throws {
        let rig = try GameFlowRig(.highScore, players: 1)
        let tip = BoardPoint(x: 1, y: 104)
        rig.game.receive(gameFlowProposal("T20", id: 1, certainty: .undecided, position: tip))
        rig.game.resolvePending(with: .treble(20))
        #expect(rig.game.turnRecords[0].position == tip && !rig.game.turnRecords[0].corrected)
        rig.game.receive(gameFlowProposal("T1", id: 2, certainty: .undecided, position: BoardPoint(x: 30, y: 100)))
        rig.game.resolvePending(with: .single(1))
        let second = rig.game.turnRecords[1]
        #expect(second.hit == .single(1) && second.position == nil && second.corrected && !second.needsReview)
        #expect(second.origin == .camera && second.id == gameFlowID(2))
        // A tap on the virtual board of the sheet gives the hit and the position together.
        let tap = BoardTap(hit: .single(5), position: BoardPoint(x: -40, y: 120))
        rig.game.receive(gameFlowProposal("S12", id: 3, certainty: .undecided))
        rig.game.resolvePending(with: tap)
        #expect(rig.game.turnRecords[2].hit == .single(5) && rig.game.turnRecords[2].position == tap.position)
    }

    @Test func resolvePending_withNil_discardsTheDetection_thenReceivesTheNextOnes() throws {
        let rig = try GameFlowRig(.highScore, players: 1)
        rig.game.receive(gameFlowProposal("T20", id: 1, certainty: .undecided))
        rig.game.receive(gameFlowProposal("S5", id: 2))
        rig.game.resolvePending(with: nil)
        #expect(rig.commands == [.dartDiscarded(gameFlowID(1))])
        #expect(rig.notations() == ["S5"] && rig.game.pending.isEmpty)
    }

    @Test func receive_outsideThrowing_isIgnored() throws {
        let rig = try GameFlowRig(.highScore, players: 2, script: "T20, T20, T20")
        let journal = rig.game.match.entries
        rig.game.receive(gameFlowProposal("S5", id: 9))
        #expect(rig.game.match.entries == journal)
        #expect(rig.game.prompt == .dartIgnored && rig.commands.isEmpty)
        #expect(rig.sound.played == CueMapping.cues(for: .dartIgnored, context: CueContext(gameID: .highScore, players: testPlayers(2))))
    }

    @Test func receive_acceptedDart_soundsSavesThenTellsTheSource_inThisOrder() throws {
        let rig = try GameFlowRig(.highScore, players: 2)
        let context = CueContext(gameID: .highScore, players: testPlayers(2))
        rig.game.receive(gameFlowManual("T20", id: 1))
        #expect(rig.commands == [.manualDartAdded])
        rig.game.receive(gameFlowProposal("T20", id: 2))
        #expect(rig.commands == [.manualDartAdded])
        var reference = try GameRegistry.standard.match(.highScore, players: 2)
        reference.throwDart(DartRecord(id: gameFlowID(1), hit: .treble(20), origin: .manual))
        reference.throwDart(DartRecord(id: gameFlowID(2), hit: .treble(20), origin: .camera))
        let third = reference.throwDart(DartRecord(id: gameFlowID(3), hit: .treble(20), origin: .camera))
        rig.game.receive(gameFlowProposal("T20", id: 3))
        // The third dart closes the turn: `turnClosed`, and the 180 is announced.
        #expect(rig.commands == [.manualDartAdded, .turnClosed])
        #expect(Array(rig.sound.played.suffix(CueMapping.cues(for: third.events, context: context).count))
                == CueMapping.cues(for: third.events, context: context))
        // The save holds the same journal, ids and origins included (the start dates of the two matches differ).
        #expect(rig.savedRecord()?.entries == reference.entries)
        #expect(rig.savedRecord()?.configuration == reference.configuration)
    }

    @Test func tapBoard_keepsThePosition_aHitPickedInAListHasNone() throws {
        let rig = try GameFlowRig(.radar, players: 1, seed: 1)
        let tap = BoardTap(hit: .single(20), position: BoardPoint(x: -80, y: 95))
        rig.game.tapBoard(tap)
        #expect(rig.game.turnRecords[0].position == tap.position && rig.game.turnRecords[0].origin == .manual)
        rig.game.addMiss()
        #expect(rig.game.turnRecords[1].hit == .miss && rig.game.turnRecords[1].position == nil)
        rig.game.correctDart(at: 0, to: .single(1))
        #expect(rig.game.turnRecords[0].position == nil && rig.game.turnRecords[0].corrected)
        let moved = BoardPoint(x: 70, y: -65)
        rig.game.correctDart(at: 0, to: .single(3), position: moved)
        #expect(rig.game.turnRecords[0].position == moved)
    }

    // MARK: Corrections and resynchronisation (§8.6, "Corrections")

    @Test func corrections_saveAndResynchroniseTheSource_inTheExactOrder() throws {
        let rig = try GameFlowRig(.highScore, players: 2)
        let source = try #require(rig.source)
        rig.game.receive(gameFlowProposal("T20", id: 1))
        rig.game.receive(gameFlowProposal("S5", id: 2, certainty: .needsReview))
        rig.game.receive(gameFlowProposal("S1", id: 3))
        #expect(source.commands == [.turnClosed])
        source.clearCommands()

        // A phantom dart of the source: removed, discarded, the turn reopens for one dart.
        rig.game.removeDart(at: 1)
        #expect(source.commands == [.dartDiscarded(gameFlowID(2)), .turnBegan(expectedDarts: 1)])
        #expect(rig.notations() == ["T20", "S1"] && rig.savedRecord() == rig.game.match.record)
        source.clearCommands()

        // Another hit picked in a list: no position, the turn stays open.
        rig.game.correctDart(at: 1, to: .treble(1))
        #expect(source.commands == [.turnBegan(expectedDarts: 1)])
        #expect(rig.notations() == ["T20", "T1"] && rig.game.turnRecords[1].corrected)
        source.clearCommands()

        // A manual dart closes the turn; undo reopens it.
        rig.game.addMiss()
        #expect(source.commands == [.manualDartAdded, .turnClosed])
        source.clearCommands()
        rig.game.undo()
        #expect(source.commands == [.turnBegan(expectedDarts: 1)])
        #expect(rig.effects.last == .tick)
        source.clearCommands()

        // Accepting a dart "à vérifier" as it is: saved, and the source is told the phase again.
        rig.game.receive(gameFlowProposal("D20", id: 4, certainty: .needsReview))
        source.clearCommands()
        rig.game.confirmDart(at: 2)
        #expect(!rig.game.turnRecords[2].needsReview && rig.savedRecord() == rig.game.match.record)
        #expect(source.commands == [.turnClosed])
        // A manual dart removed: not reported to the source.
        source.clearCommands()
        rig.game.undo()
        rig.game.addMiss()
        source.clearCommands()
        rig.game.removeDart(at: 2)
        #expect(source.commands == [.turnBegan(expectedDarts: 1)])
    }

    @Test func undo_ofAnEndTurn_reopensTheLastTurn_andCloses() throws {
        let rig = try GameFlowRig(.highScore, players: 2, script: "T20, S5, S1 |")
        rig.game.undo()
        #expect(rig.game.snapshot.currentPlayer == 0 && rig.game.match.phase == .turnComplete)
        #expect(rig.commands == [.turnClosed])
        // Undo on an empty journal does nothing at all.
        let empty = try GameFlowRig(.highScore, players: 1)
        empty.game.undo()
        #expect(empty.commands.isEmpty && empty.sound.played.isEmpty && empty.savedRecord() == nil)
    }

    @Test func correction_thatMakesTheFirstDartABust_dropsTheNextDarts_andClosesTheTurn() throws {
        // X01 double out from 10 (X01-2): S2, D4 wins; correcting S2 into S15 busts and drops D4.
        let rig = try GameFlowRig(.x01, ["startScore": 301, "outRule": "double"], players: 1,
                                  script: "T20, T20, T20 | T20, T17, MISS |")
        rig.game.receive(gameFlowProposal("S2", id: 1))
        rig.game.receive(gameFlowProposal("S1", id: 2))
        #expect(rig.game.match.phase == .throwing)
        rig.source?.clearCommands()
        rig.game.correctDart(at: 0, to: .single(15))
        #expect(rig.notations() == ["S15"] && rig.game.match.phase == .turnComplete)
        #expect(rig.commands == [.turnClosed])
    }

    // MARK: End of the turn (§8.6, "Fin du tour")

    @Test func endTurn_reportsTheDartsOfTheSource_thenEndsTheTurn_thenBeginsTheNext() throws {
        let rig = try GameFlowRig(.highScore, players: 2)
        rig.game.receive(gameFlowProposal("T20", id: 1))
        rig.game.receive(gameFlowManual("S5", id: 2))
        rig.game.receive(gameFlowProposal("S1", id: 3, certainty: .needsReview, origin: .scan))
        rig.game.correctDart(at: 2, to: .single(18))
        rig.source?.clearCommands()
        rig.game.requestEndTurn()
        #expect(rig.commands == [.turnConfirmed([DartFeedback(id: gameFlowID(1), wasCorrected: false),
                                                 DartFeedback(id: gameFlowID(3), wasCorrected: true)]),
                                 .turnBegan(expectedDarts: 3)])
        #expect(rig.game.snapshot.currentPlayer == 1 && rig.savedRecord() == rig.game.match.record)
        #expect(rig.spoken.last == "Au tour de J2")
        // A turn without a dart of the source: no `turnConfirmed` at all.
        rig.source?.clearCommands()
        rig.game.receive(gameFlowManual("S5", id: 4))
        rig.game.receive(gameFlowManual("S5", id: 5))
        rig.game.receive(gameFlowManual("S5", id: 6))
        rig.source?.clearCommands()
        rig.game.endTurn()
        #expect(rig.commands == [.turnBegan(expectedDarts: 3)])
    }

    @Test func requestEndTurn_shortTurn_asksFirst_whenTheGameWantsIt() throws {
        let rig = try GameFlowRig(.highScore, players: 2)
        rig.game.receive(gameFlowManual("T20", id: 1))
        rig.game.requestEndTurn()
        #expect(rig.game.prompt == .confirmShortTurn && rig.game.snapshot.currentPlayer == 0)
        rig.game.endTurn()
        #expect(rig.game.snapshot.currentPlayer == 1 && rig.game.prompt == nil)
        // An empty turn is short too.
        rig.game.requestEndTurn()
        #expect(rig.game.prompt == .confirmShortTurn)
        // A closed turn passes without a question.
        rig.game.prompt = nil
        rig.game.receive(gameFlowManual("S1", id: 2))
        rig.game.receive(gameFlowManual("S1", id: 3))
        rig.game.receive(gameFlowManual("S1", id: 4))
        rig.game.requestEndTurn()
        #expect(rig.game.prompt == nil && rig.game.snapshot.currentPlayer == 0)
    }

    @Test func requestEndTurn_golf_shortTurnPassesWithoutConfirmation() throws {
        let rig = try GameFlowRig(.golf, players: 2)
        #expect(rig.game.descriptor.confirmsShortTurn == false)
        rig.game.receive(gameFlowManual("T1", id: 1))
        rig.game.requestEndTurn()
        #expect(rig.game.prompt == nil && rig.game.snapshot.currentPlayer == 1)
        rig.game.requestEndTurn()
        #expect(rig.game.prompt == nil && rig.game.snapshot.currentPlayer == 0 && rig.game.snapshot.round == 2)
    }

    @Test func canEndTurn_isFalseWhileADartWaits_orOnceFinished() throws {
        let rig = try GameFlowRig(.highScore, ["rounds": 1], players: 1)
        #expect(rig.game.canEndTurn)
        rig.game.receive(gameFlowProposal("T20", id: 1, certainty: .undecided))
        #expect(!rig.game.canEndTurn)
        rig.game.requestEndTurn()
        rig.game.endTurn()
        #expect(rig.game.snapshot.round == 1 && rig.game.match.entries.isEmpty)
        rig.game.resolvePending(with: .treble(20))
        rig.game.endTurn()
        #expect(rig.game.isFinished && !rig.game.canEndTurn)
    }

    // MARK: Events of the source (§8.6, "Événements de la source")

    @Test func boardCleared_endsAClosedTurn_onlyWithTheSetting() throws {
        let manualEnd = try GameFlowRig(.highScore, players: 2, script: "T20, T20, T20")
        manualEnd.game.handle(.boardCleared)
        #expect(manualEnd.game.prompt == .boardCleared && manualEnd.game.snapshot.currentPlayer == 0)
        #expect(manualEnd.sound.played == CueMapping.cues(for: .boardCleared, context: CueContext(gameID: .highScore, players: testPlayers(2))))

        let automatic = try GameFlowRig(.highScore, players: 2, endsTurnOnTakeout: true, script: "T20, T20, T20")
        automatic.game.handle(.boardCleared)
        #expect(automatic.game.prompt == nil && automatic.game.snapshot.currentPlayer == 1)
        #expect(automatic.commands == [.turnBegan(expectedDarts: 3)])

        // An open turn is never ended by the camera, even with the setting.
        let open = try GameFlowRig(.highScore, players: 2, endsTurnOnTakeout: true, script: "T20")
        open.game.handle(.boardCleared)
        #expect(open.game.prompt == .boardCleared && open.game.snapshot.currentPlayer == 0)

        // Nor while a dart waits for an answer: X01 double out from 10, S2 then an undecided dart; correcting
        // S2 into S15 busts and closes the turn while the undecided dart still waits.
        let waiting = try GameFlowRig(.x01, ["startScore": 301, "outRule": "double"], players: 2, endsTurnOnTakeout: true,
                                      script: "T20, T20, T20 | MISS ×3 | T20, T17, MISS | MISS ×3 |")
        waiting.game.receive(gameFlowProposal("S2", id: 1))
        waiting.game.receive(gameFlowProposal("S1", id: 2, certainty: .undecided))
        waiting.game.correctDart(at: 0, to: .single(15))
        #expect(waiting.game.match.phase == .turnComplete && waiting.game.pending.count == 1)
        waiting.game.handle(.boardCleared)
        #expect(waiting.game.prompt == .boardCleared && waiting.game.snapshot.currentPlayer == 0)
    }

    @Test func otherEvents_updateTheScreen() throws {
        let rig = try GameFlowRig(.highScore, players: 1)
        let context = CueContext(gameID: .highScore, players: testPlayers(1))
        rig.game.receive(gameFlowProposal("T20", id: 1))
        rig.game.receive(gameFlowProposal("S5", id: 2))
        rig.game.handle(.dartDisturbed(id: gameFlowID(1)))
        #expect(rig.game.turnRecords[0].needsReview && rig.savedRecord()?.entries.first == rig.game.match.entries.first)
        rig.game.handle(.dartRemoved(id: gameFlowID(2), reason: .fellOut))
        #expect(rig.game.prompt == .dartFellOut(index: 1))
        rig.game.correctDart(at: 1, to: .miss)
        #expect(rig.notations() == ["T20", "MISS"] && rig.game.prompt == nil)
        rig.game.handle(.dartRemoved(id: gameFlowID(1), reason: .takeout))
        rig.game.handle(.dartRemoved(id: gameFlowID(99), reason: .fellOut))
        rig.game.prompt = nil
        #expect(rig.game.prompt == nil)

        rig.game.handle(.possibleMiss)
        #expect(rig.game.prompt == .possibleMiss)
        rig.game.addMiss()
        #expect(rig.notations() == ["T20", "MISS", "MISS"] && rig.game.prompt == nil)

        let advisory = LocalizedText(fr: "Lumière changée", en: "Light changed")
        rig.game.handle(.advisory(advisory))
        #expect(rig.game.prompt == .advisory(advisory))

        let before = rig.sound.played.count
        rig.game.handle(.statusChanged(.live))
        rig.game.handle(.statusChanged(.needsCalibration))
        rig.game.handle(.statusChanged(.needsCalibration))
        #expect(rig.game.inputStatus == .needsCalibration)
        #expect(Array(rig.sound.played[before...]) == CueMapping.cues(for: .calibrationLost, context: context))

        rig.game.confirmBoardEmpty()
        #expect(rig.commands.last == .boardConfirmedEmpty)
    }

    // MARK: End of the game (§8.6, "Fin de la partie": the three mandatory tests)

    @Test func endOnADart_staysSavedAndCorrectable_untilFinishGame() throws {
        // KIL-1: J1 arms, then kills J2 with the third dart of a turn on D6.
        let rig = try GameFlowRig(.killer, ["level": "hard"], players: 2, seed: 1)
        let source = try #require(rig.source)
        drive(rig, "S11, D11, T11 | MISS ×3 | S6, T6", firstID: 1)
        source.clearCommands()
        rig.game.receive(gameFlowProposal("D6", id: 50))
        #expect(rig.game.isFinished && rig.game.snapshot.finishReason == .lastPlayerStanding)
        #expect(source.commands == [.turnClosed])
        #expect(rig.savedRecord() == rig.game.match.record)
        // The context of the winning dart is the snapshot AFTER it: the winner is named.
        #expect(rig.game.snapshot.winners == [0] && rig.spoken.last == "J1 gagne la partie")
        #expect(rig.effects.contains(.victory))

        // Undo the winning dart: the game reopens and the source expects one dart again.
        source.clearCommands()
        rig.game.undo()
        #expect(rig.game.match.phase == .throwing && source.commands == [.turnBegan(expectedDarts: 1)])
        #expect(rig.savedRecord() == rig.game.match.record)

        // The winning dart again, then the results screen is left.
        source.clearCommands()
        rig.game.receive(gameFlowProposal("D6", id: 50))
        rig.game.finishGame()
        let winningTurn = rig.game.turnRecords.map { DartFeedback(id: $0.id, wasCorrected: false) }
        #expect(winningTurn.count == 3)
        #expect(source.commands == [.turnClosed, .turnConfirmed(winningTurn), .gameEnded])
        #expect(rig.savedRecord() == nil)
        // Once only.
        rig.game.finishGame()
        rig.game.suspend()
        #expect(source.commands.filter { $0 == .gameEnded }.count == 1)
    }

    @Test func endAtTheRoundLimit_confirmsOnce() throws {
        let rig = try GameFlowRig(.highScore, ["rounds": 1], players: 1)
        let source = try #require(rig.source)
        rig.game.receive(gameFlowProposal("T20", id: 1))
        rig.game.receive(gameFlowProposal("T20", id: 2))
        rig.game.receive(gameFlowProposal("T19", id: 3))
        source.clearCommands()
        rig.game.endTurn()
        #expect(rig.game.isFinished && rig.game.snapshot.finishReason == .roundLimit)
        #expect(source.commands == [.turnConfirmed([1, 2, 3].map { DartFeedback(id: gameFlowID($0), wasCorrected: false) }),
                                    .turnClosed])
        #expect(rig.savedRecord() == rig.game.match.record && rig.game.turnRecords.isEmpty)
        source.clearCommands()
        rig.game.finishGame()
        #expect(source.commands == [.gameEnded])
        #expect(rig.savedRecord() == nil)
    }

    @Test func finishedGameResumed_opensOnItsResults_andClosesTheTurn() async throws {
        let store = InMemoryStore()
        let first = try GameFlowRig(match: GameRegistry.standard.match(.highScore, ["rounds": 1], players: 1), store: store)
        drive(first, "T20, T20, T20 |", firstID: 1)
        #expect(first.game.isFinished)
        let saved = try #require(first.savedRecord())

        let resumed = try GameFlowRig(match: GameRegistry.standard.restoreMatch(saved), store: store)
        #expect(resumed.game.isFinished && resumed.game.snapshot.phase == .finished)
        let task = await resumed.start(boardConfirmedEmpty: true)
        #expect(resumed.commands == [.gameStarted(boardConfirmedEmpty: true), .turnClosed])
        #expect(resumed.sound.played.isEmpty)
        resumed.source?.finish()
        await task.value
        // Still correctable: undoing the last endTurn reopens the last turn.
        resumed.game.undo()
        #expect(!resumed.game.isFinished && resumed.game.match.phase == .turnComplete)
    }

    @Test func suspend_tellsTheSourceOnly_andKeepsTheSave() throws {
        let rig = try GameFlowRig(.highScore, players: 2)
        rig.game.receive(gameFlowProposal("T20", id: 1))
        let saved = rig.savedRecord()
        rig.source?.clearCommands()
        rig.game.suspend()
        #expect(rig.commands == [.gameEnded] && rig.savedRecord() == saved && saved != nil)
    }

    @Test func savedGame_resumesTheSameJournal() throws {
        let store = InMemoryStore()
        let rig = try GameFlowRig(match: GameRegistry.standard.match(.radar, players: 2, seed: 1), store: store)
        rig.game.tapBoard(BoardTap(hit: .single(12), position: BoardPoint(x: -80, y: 95)))
        rig.game.receive(gameFlowProposal("T20", id: 2, certainty: .needsReview, position: BoardPoint(x: 0, y: 104)))
        let saved = try #require(rig.savedRecord())
        let restored = try GameRegistry.standard.restoreMatch(saved)
        #expect(restored.record == rig.game.match.record && restored.snapshot == rig.game.snapshot)
        #expect(restored.currentTurn.map(\.position) == rig.game.turnRecords.map(\.position))
        #expect(restored.currentTurn[1].needsReview)
    }

    @Test func soundContext_andResultsTitle_comeFromWinnerTitle() throws {
        // FOO-7: J1 pushes the ball into the goal he defends; side B wins on an own goal.
        let rig = try GameFlowRig(.football, ["goalsToWin": 1], players: 2)
        rig.game.receive(gameFlowManual("T11", id: 1))
        rig.game.receive(gameFlowManual("S11", id: 2))
        #expect(rig.game.isFinished)
        let title = try #require(rig.game.snapshot.winnerTitle)
        #expect(title.fr == "Le camp B gagne")
        #expect(rig.sound.played.contains { $0.announcement?.text == title })
        // Before the end, no title is ever said.
        let other = try GameFlowRig(.football, players: 2)
        other.game.receive(gameFlowManual("S6", id: 1))
        #expect(!other.sound.played.contains { $0.announcement?.text.fr.contains("camp") == true })
    }

    @Test func rematchConfiguration_samePlayersAndOptions_newSeed() throws {
        let rig = try GameFlowRig(.killer, ["level": "medium", "lives": 5], players: 3, seed: 4)
        let configuration = rig.game.rematchConfiguration(seed: 99)
        #expect(configuration.seed == 99 && configuration.gameID == .killer)
        #expect(configuration.players == rig.game.match.players)
        #expect(configuration.options == rig.game.match.configuration.options)
        #expect(configuration.options.int("lives") == 5 && configuration.options.string("level") == "medium")
    }
}

/// Plays a script of GAMES.md §2.11 through the view model: "," separates darts, "|" is the next-player button
/// (`endTurn`), "×3" repeats a dart. Every dart is a certain camera proposal with the next fixed id.
@MainActor
@discardableResult
func gameFlowDriveScript(_ game: PlayViewModel, _ script: String, firstID: Int) -> Int {
    var next = firstID
    let turns = script.components(separatedBy: "|")
    for (index, turn) in turns.enumerated() {
        for token in turn.components(separatedBy: ",") {
            let text = token.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            let parts = text.components(separatedBy: "×")
            let times = parts.count > 1 ? Int(parts[1].trimmingCharacters(in: .whitespaces)) ?? 1 : 1
            let notation = parts[0].trimmingCharacters(in: .whitespaces)
            for _ in 0..<times {
                game.receive(gameFlowProposal(notation, id: next))
                next += 1
            }
        }
        if index < turns.count - 1 { game.endTurn() }
    }
    return next
}

@MainActor
@discardableResult
private func drive(_ rig: GameFlowRig, _ script: String, firstID: Int) -> Int {
    gameFlowDriveScript(rig.game, script, firstID: firstID)
}
