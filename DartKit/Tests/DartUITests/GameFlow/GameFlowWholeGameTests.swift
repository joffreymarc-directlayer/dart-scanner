import Foundation
import Testing
import DartCore
import DartGames
import DartAudio
import DartTestSupport
@testable import DartUI

/// Whole games played through `PlayViewModel` with fixed seeds and darts of fixed ids: the Killer at each of its
/// four levels (GAMES.md §5.9) and an X01 (§3.9). The state reached through the view model is the state the
/// engine reaches on the same script, and the source hears one consistent story of turns.
@MainActor
@Suite struct GameFlowWholeGameTests {
    /// Plays `script` through the view model and directly on a match, and checks that both agree.
    private func play(_ game: GameID, _ options: GameOptions, players: Int, seed: UInt64,
                      _ script: String) throws -> GameFlowRig {
        let rig = try GameFlowRig(game, options, players: players, seed: seed)
        gameFlowDriveScript(rig.game, script, firstID: 1)
        var reference = try GameRegistry.standard.match(game, options, players: players, seed: seed)
        reference.play(script)
        #expect(rig.game.snapshot == reference.snapshot)
        #expect(rig.game.match.entries.map(\.input) == reference.entries.map(\.input))
        // Every turn the source began is closed or confirmed: no `turnBegan` without its end.
        let began = rig.commands.filter { if case .turnBegan = $0 { return true } else { return false } }.count
        let ends = rig.game.match.entries.filter { $0 == .endTurn }.count
        #expect(began == ends - (rig.game.isFinished && rig.game.snapshot.finishReason == .roundLimit ? 1 : 0))
        return rig
    }

    private func lives(_ rig: GameFlowRig) -> [FactValue?] {
        rig.game.snapshot.players.map { $0.facts["lives"] }
    }

    @Test func kil1_hard_duelToTheEnd() throws {
        let rig = try play(.killer, ["level": "hard"], players: 2, seed: 1, "S11, D11, T11 | MISS ×3 | S6, T6, D6")
        #expect(rig.game.isFinished && rig.game.snapshot.finishReason == .lastPlayerStanding)
        #expect(rig.game.snapshot.ranks == [1, 2] && lives(rig) == [3, 0])
        #expect(rig.game.snapshot.players[0].facts["kills"] == 1)
        // The winning turn stays correctable until the results are left.
        #expect(rig.savedRecord() == rig.game.match.record)
        rig.game.finishGame()
        #expect(rig.commands.suffix(2) == [.turnConfirmed([7, 8, 9].map { DartFeedback(id: gameFlowID($0), wasCorrected: false) }),
                                           .gameEnded])
        #expect(rig.savedRecord() == nil)
    }

    @Test func kil2_easy_threePlayers() throws {
        let rig = try play(.killer, ["level": "easy"], players: 3, seed: 1, """
            S8, T14, S6 | S11, DB, S20 | S19, MISS, S20 | D11, S10, S15 | S6, S6, S6 | MISS ×3 | S6, S14, S1 |
            S10, S18, S18 | T20, S1
            """)
        #expect(rig.game.snapshot.phase == .finished && rig.game.snapshot.round == 4)
        #expect(lives(rig) == [3, 0, 0] && rig.game.snapshot.ranks == [1, 3, 2])
        #expect(rig.game.snapshot.players[0].facts["kills"] == 2)
        // A dart after the end is ignored, with its prompt and its sound.
        rig.game.receive(gameFlowManual("S1", id: 99))
        #expect(rig.game.prompt == .dartIgnored && rig.effects.last == .rejected)
    }

    @Test func kil3_expert_redrawEveryTurn() throws {
        let rig = try play(.killer, ["level": "expert"], players: 3, seed: 7, """
            S14, MISS, MISS | MISS ×3 | MISS ×3 | S14, S16, T16 | MISS ×3 | MISS ×3 | S11, S11, S11 | MISS ×3 |
            """)
        let zones = rig.game.snapshot.players.map { $0.facts["zone"] }
        #expect(zones[0] == [4] && zones[2] == [17])
        #expect(rig.game.snapshot.round == 4 && rig.game.snapshot.currentPlayer == 0 && lives(rig) == [3, 0, 3])
        // Undo the last endTurn then end the turn again: the same number is drawn (GAMES.md §5.4).
        rig.game.undo()
        rig.game.endTurn()
        #expect(rig.game.snapshot.players[0].facts["zone"] == [4])
        // "Nouveau numéro : 4" is announced after "Au tour de J1".
        #expect(Array(rig.spoken.suffix(2)) == ["Au tour de J1", "Nouveau numéro : 4"])
    }

    @Test func kil5_medium_roundLimit() throws {
        let rig = try play(.killer, ["level": "medium", "maxRounds": 2], players: 4, seed: 42, """
            S9, S12, S9 | S16, S16, MISS | MISS ×3 | S17, S3, S17 |
            S16, S1, S1 | MISS, S8, S9 | S18, MISS, MISS | S9, S16, S16 |
            """)
        #expect(rig.game.isFinished && rig.game.snapshot.finishReason == .roundLimit)
        #expect(rig.game.snapshot.ranks == [2, 4, 3, 1])
        // Ended at the round limit: the last turn was confirmed by `endTurn`, the turn is empty, and leaving the
        // results confirms nothing twice.
        #expect(rig.game.turnRecords.isEmpty && rig.commands.last == .turnClosed)
        rig.game.finishGame()
        #expect(rig.commands.last == .gameEnded)
        #expect(rig.commands.filter { if case .turnConfirmed = $0 { return true } else { return false } }.count == 8)
    }

    @Test func kil6_medium_duel() throws {
        let rig = try play(.killer, ["level": "medium"], players: 2, seed: 1, "S6, D10, T6 | S14, S11, MISS | S11, S14, S11")
        #expect(rig.game.isFinished && lives(rig) == [3, 0] && rig.game.snapshot.ranks == [1, 2])
    }

    @Test func x01_twoPlayers_checkout() throws {
        let rig = try play(.x01, ["startScore": 301], players: 2, seed: 0, "T20, T20, T20 | S20, S1, MISS | T20, S11, DB")
        #expect(rig.game.isFinished && rig.game.snapshot.finishReason == .victory)
        #expect(rig.game.snapshot.players.map { $0.facts["remaining"] } == [0, 280])
        #expect(rig.game.snapshot.winners == [0] && rig.game.snapshot.winnerTitle == nil)
        #expect(rig.spoken.last == "J1 gagne la partie")
        // A mis-detected winning dart is corrected from the results: the game reopens.
        rig.game.correctDart(at: 2, to: .outerBull)
        #expect(!rig.game.isFinished && rig.game.match.phase == .turnComplete)
        #expect(rig.commands.last == .turnClosed)
        rig.game.correctDart(at: 2, to: .innerBull)
        #expect(rig.game.isFinished)
    }

    @Test func x01_bustOnAShortTurn_needsTheConfirmation() throws {
        let rig = try GameFlowRig(.x01, ["startScore": 301, "outRule": "double"], players: 1,
                                  script: "T20, T20, T20 | T20, T17, MISS |")
        rig.game.receive(gameFlowManual("S9", id: 1))
        #expect(rig.game.match.phase == .turnComplete && rig.game.snapshot.players[0].facts["busts"] == 1)
        #expect(rig.effects.contains(.bust))
        // A busted turn is closed: "Fléchettes retirées, suivant" passes without the short-turn question.
        rig.game.requestEndTurn()
        #expect(rig.game.prompt == nil && rig.game.match.phase == .throwing && rig.game.snapshot.round == 4)
    }
}
