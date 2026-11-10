import Testing
import DartCore
import DartGames
import DartTestSupport

/// The common vectors COM-1 to COM-7 of GAMES.md §2.12, played by the real X01 of `GameRegistry.standard`.
/// They check the common base (phases, early confirmation, undo, corrections, round limit), not X01 itself.
@Suite struct CommonVectorTests {
    private let registry = GameRegistry.standard

    /// The journal as a vector writes it: ["T20", "S1", "|", "S5"].
    private func journal(_ match: GameMatch) -> [String] {
        match.entries.map { entry in
            switch entry {
            case .dart(let record): return record.hit.notation
            case .endTurn: return "|"
            }
        }
    }

    @Test func com1_fourthDartRefused() throws {
        var match = try registry.match(.x01, ["startScore": 301], players: 1)
        match.play("T20, T20, T20")
        #expect(match.phase == .turnComplete && match.fact(0, "remaining") == 121)
        let before = match.snapshot
        // dart(S20) → refused; state unchanged; journal unchanged (3 entries).
        #expect(match.throwDart(DartRecord(hit: .single(20))) == .rejected(.turnComplete))
        #expect(match.snapshot == before)
        #expect(match.entries.count == 3 && journal(match) == ["T20", "T20", "T20"])
    }

    @Test func com2_earlyConfirmation() throws {
        var match = try registry.match(.x01, ["startScore": 301], players: 2)
        let outcomes = match.play("T20 | S5, S5, S5 |")
        #expect(match.phase == .throwing && match.snapshot.currentPlayer == 0 && match.snapshot.round == 2)
        #expect(match.snapshot.turn.darts.isEmpty && match.currentTurn.isEmpty)
        #expect(match.fact(0, "remaining") == 241 && match.fact(0, "dartsThrown") == 1)
        #expect(match.fact(1, "remaining") == 286 && match.fact(1, "dartsThrown") == 3)
        // The darts not thrown do not exist: the early confirmation closes the turn with one dart.
        #expect(outcomes[1].events == [.turnScored(player: 0, points: 60), .turnCompleted(player: 0),
                                       .turnStarted(player: 1, round: 1)])
        #expect(outcomes[5].events == [.roundStarted(round: 2), .turnStarted(player: 0, round: 2)])
        #expect(journal(match) == ["T20", "|", "S5", "S5", "S5", "|"])
    }

    @Test func com3_correctionIsAReplay() throws {
        var match = try registry.match(.x01, ["startScore": 301], players: 1)
        match.play("T20, S1, S5")
        #expect(match.fact(0, "remaining") == 235)
        let edit = match.replaceDart(at: 1, with: .treble(20))
        #expect(edit == EditOutcome(applied: true, dropped: []))
        #expect(journal(match) == ["T20", "T20", "S5"])
        #expect(match.fact(0, "remaining") == 176 && match.phase == .turnComplete)
    }

    @Test func com4_aCorrectionThatCausesABustRemovesTheFollowingDarts() throws {
        var match = try registry.match(.x01, ["startScore": 301, "outRule": "double"], players: 1)
        match.play("T20, T20, T20 | T20, T17, MISS | S4, S4, D1")
        #expect(match.phase == .finished && match.snapshot.finishReason == .victory && match.fact(0, "remaining") == 0)
        let removed = match.currentTurn
        let edit = match.replaceDart(at: 0, with: .single(9))
        // volley = [S9]; bust(oneLeft); remaining = 10; phase = turnComplete; busts = 1.
        #expect(match.turnNotation == ["S9"])
        #expect(match.fact(0, "remaining") == 10 && match.phase == .turnComplete && match.fact(0, "busts") == 1)
        #expect(match.snapshot.finishReason == nil)
        #expect(match.snapshot.turn.darts.last?.caption == DartCaption(LocalizedText(verbatim: "BUST"), tone: .negative))
        // The two darts that the replay refused left the journal and are handed back.
        #expect(edit.applied && edit.dropped == [removed[1], removed[2]])
        #expect(journal(match) == ["T20", "T20", "T20", "|", "T20", "T17", "MISS", "|", "S9"])
    }

    @Test func com5_aCorrectionThatCancelsABustReopensTheTurn() throws {
        var match = try registry.match(.x01, ["startScore": 301, "outRule": "double"], players: 1)
        let outcomes = match.play("T20, T20, T20 | T20, T17, MISS | S9")
        #expect(outcomes.last?.events == [.dartRegistered(player: 0, hit: .single(9)), .bust(player: 0, reason: .oneLeft),
                                          .turnCompleted(player: 0)])
        #expect(match.phase == .turnComplete && match.fact(0, "remaining") == 10 && match.fact(0, "busts") == 1)
        #expect(match.replaceDart(at: 0, with: .single(4)).applied)
        #expect(match.phase == .throwing && match.turnNotation == ["S4"])
        #expect(match.fact(0, "remaining") == 6 && match.fact(0, "busts") == 0)
    }

    @Test func com6_undoThroughAConfirmation() throws {
        var match = try registry.match(.x01, ["startScore": 301], players: 1)
        match.play("T20, S1, S5 |")
        #expect(match.phase == .throwing && match.snapshot.round == 2 && match.turnNotation.isEmpty)
        #expect(match.fact(0, "remaining") == 235)
        #expect(match.undo().applied)
        #expect(match.phase == .turnComplete && match.snapshot.round == 1 && match.turnNotation == ["T20", "S1", "S5"])
        #expect(match.fact(0, "remaining") == 235)
        #expect(match.undo().applied)
        #expect(match.phase == .throwing && match.turnNotation == ["T20", "S1"] && match.fact(0, "remaining") == 240)
    }

    @Test func com7_theRoundLimitOnlyActsOnTheConfirmation() throws {
        var match = try registry.match(.x01, ["startScore": 301, "maxRounds": 1], players: 3)
        match.play("T20, T20, T20 | S20, S20, S20 | S20, S20, S20")
        #expect(match.phase == .turnComplete && match.snapshot.currentPlayer == 2 && match.snapshot.round == 1)
        #expect(match.endTurn().events == [.gameFinished(reason: .roundLimit)])
        #expect(match.phase == .finished && match.snapshot.finishReason == .roundLimit && match.snapshot.ranks == [1, 2, 2])
        // Empty volley: the confirmed turn is over, in the snapshot as in the journal.
        #expect(match.snapshot.turn.darts.isEmpty && match.currentTurn.isEmpty)
        #expect(match.fact(0, "remaining") == 121 && match.fact(1, "remaining") == 241 && match.fact(2, "remaining") == 241)
        // dart(S1) → refused; endTurn → refused.
        let entries = match.entries.count
        let before = match.snapshot
        #expect(match.throwDart(DartRecord(hit: .single(1))) == .rejected(.gameFinished))
        #expect(match.endTurn() == .rejected(.gameFinished))
        #expect(match.entries.count == entries && match.snapshot == before)
        // The confirmed turn is locked; undoing the confirmation reopens it with its volley (GAMES.md §2.6).
        #expect(!match.replaceDart(at: 0, with: .single(1)).applied && match.entries.count == entries)
        #expect(match.undo().applied)
        #expect(match.phase == .turnComplete && match.turnNotation == ["S20", "S20", "S20"])
        #expect(match.snapshot.turn.darts.map(\.hit) == [.single(20), .single(20), .single(20)])
    }
}
