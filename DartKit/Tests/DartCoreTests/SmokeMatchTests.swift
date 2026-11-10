import Foundation
import Testing
import DartCore
import DartTestSupport

/// `GameMatch`: the journal, undo, corrections and replay (GAMES.md §2.5, §2.12, §2.13; ARCHITECTURE.md §4.8).
/// The common vectors COM-1 to COM-7 are played by the fixture X01 of `SmokeFixtures`.
@Suite struct SmokeMatchTests {
    private let registry = SmokeFixtures.registry

    // MARK: Common vectors (GAMES.md §2.12)

    @Test func com1_fourthDartRefused() throws {
        var match = try registry.match(.x01, ["startScore": 301], players: 1)
        match.play("T20, T20, T20")
        #expect(match.phase == .turnComplete && match.fact(0, "remaining") == 121)
        let before = match.snapshot
        #expect(match.throwDart(DartRecord(hit: .single(20))) == .rejected(.turnComplete))
        // State unchanged, journal unchanged (3 entries).
        #expect(match.snapshot == before)
        #expect(match.entries.count == 3 && SmokeFixtures.journal(match) == ["T20", "T20", "T20"])
    }

    @Test func com2_earlyConfirmation() throws {
        var match = try registry.match(.x01, ["startScore": 301], players: 2)
        match.play("T20 | S5, S5, S5 |")
        #expect(match.phase == .throwing && match.snapshot.currentPlayer == 0 && match.snapshot.round == 2)
        #expect(match.snapshot.turn.darts.isEmpty && match.currentTurn.isEmpty)
        #expect(match.fact(0, "remaining") == 241 && match.fact(0, "dartsThrown") == 1)
        #expect(match.fact(1, "remaining") == 286 && match.fact(1, "dartsThrown") == 3)
    }

    @Test func com3_correctionIsAReplay() throws {
        var match = try registry.match(.x01, ["startScore": 301], players: 1)
        match.play("T20, S1, S5")
        #expect(match.fact(0, "remaining") == 235)
        let edit = match.replaceDart(at: 1, with: .treble(20))
        #expect(edit == EditOutcome(applied: true, dropped: []))
        #expect(SmokeFixtures.journal(match) == ["T20", "T20", "S5"])
        #expect(match.fact(0, "remaining") == 176 && match.phase == .turnComplete)
    }

    @Test func com4_aCorrectionThatCausesABustRemovesTheFollowingDarts() throws {
        var match = try registry.match(.x01, ["startScore": 301, "outRule": "double"], players: 1)
        match.play("T20, T20, T20 | T20, T17, MISS | S4, S4, D1")
        #expect(match.phase == .finished && match.snapshot.finishReason == .victory && match.fact(0, "remaining") == 0)
        let removed = match.currentTurn
        let edit = match.replaceDart(at: 0, with: .single(9))
        #expect(match.turnNotation == ["S9"])
        #expect(match.fact(0, "remaining") == 10 && match.phase == .turnComplete && match.fact(0, "busts") == 1)
        #expect(match.snapshot.finishReason == nil)
        // The two darts that the replay refused left the journal and are handed back.
        #expect(edit.applied && edit.dropped == [removed[1], removed[2]])
        #expect(edit.dropped.map(\.hit) == [.single(4), .double(1)])
        #expect(SmokeFixtures.journal(match) == ["T20", "T20", "T20", "|", "T20", "T17", "MISS", "|", "S9"])
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
        #expect(match.fact(0, "remaining") == 121 && match.fact(1, "remaining") == 241 && match.fact(2, "remaining") == 241)
        // Empty volley: the confirmed turn is over, in the snapshot as in the journal.
        #expect(match.snapshot.turn.darts.isEmpty && match.currentTurn.isEmpty)
        let entries = match.entries.count
        #expect(match.throwDart(DartRecord(hit: .single(1))) == .rejected(.gameFinished))
        #expect(match.endTurn() == .rejected(.gameFinished))
        #expect(match.entries.count == entries)
        // The darts of the confirmed turn are locked; undoing the confirmation reopens that turn with its volley.
        #expect(!match.replaceDart(at: 0, with: .single(1)).applied && match.entries.count == entries)
        #expect(match.undo().applied)
        #expect(match.phase == .turnComplete && match.turnNotation == ["S20", "S20", "S20"])
        #expect(match.snapshot.turn.darts.map(\.hit) == [.single(20), .single(20), .single(20)])
    }

    // MARK: X01 events through the kernel (GAMES.md §3.9, the cases that exercise the order of events)

    @Test func x01_1_oneEightyThenCheckout() throws {
        var match = try registry.match(.x01, ["startScore": 301], players: 1)
        var outcomes = match.play("T20, T20, T20")
        #expect(match.phase == .turnComplete && match.fact(0, "remaining") == 121)
        #expect(outcomes[2].events == [.dartRegistered(player: 0, hit: .treble(20)), .turnScored(player: 0, points: 180),
                                       .oneEighty(player: 0), .turnCompleted(player: 0)])
        outcomes = match.play("| T20, S11, DB")
        #expect(match.phase == .finished && match.snapshot.finishReason == .victory)
        #expect(match.fact(0, "remaining") == 0 && match.fact(0, "dartsThrown") == 6 && match.snapshot.ranks == [1])
        #expect(outcomes.last?.events == [.dartRegistered(player: 0, hit: .innerBull),
                                          .checkout(player: 0, points: 121, darts: 3), .gameFinished(reason: .victory)])
    }

    @Test func x01_3_doubleInAndDoubleOut() throws {
        var match = try registry.match(.x01, ["startScore": 301, "inRule": "double", "outRule": "double"], players: 2)
        #expect(SmokeFixtures.targets(match) == (1...20).map { BoardZone.double($0) } + [.innerBull])
        let outcomes = match.play("S20, T20, D10")
        #expect(match.fact(0, "isOpen") == true && match.fact(0, "remaining") == 281 && match.fact(0, "dartsThrown") == 3)
        #expect(outcomes[0].events == [.dartRegistered(player: 0, hit: .single(20)), .doubleInRequired(player: 0)])
        #expect(outcomes[1].events == [.dartRegistered(player: 0, hit: .treble(20)), .doubleInRequired(player: 0)])
        #expect(outcomes[2].events == [.dartRegistered(player: 0, hit: .double(10)), .doubleInOpened(player: 0),
                                       .turnScored(player: 0, points: 20), .turnCompleted(player: 0)])
        match.play("| MISS, DB, T20")
        #expect(match.fact(1, "isOpen") == true && match.fact(1, "remaining") == 191 && match.phase == .turnComplete)
    }

    // MARK: Journal

    @Test func aNewMatch_hasAnEmptyJournal_andTheConfigurationWithDefaults() throws {
        let start = Date(timeIntervalSinceReferenceDate: 1_000)
        let definition = try #require(registry.definition(for: .x01))
        let configuration = GameConfiguration(gameID: .x01, options: ["outRule": "double"], players: testPlayers(2), seed: 9)
        var match = try GameMatch(definition: definition, configuration: configuration, startedAt: start)
        #expect(match.entries.isEmpty && !match.canUndo && match.currentTurn.isEmpty)
        #expect(match.phase == .throwing && match.players == testPlayers(2) && match.startedAt == start)
        #expect(match.definition.id == .x01)
        #expect(match.configuration.options == ["startScore": 301, "inRule": "straight", "outRule": "double", "maxRounds": 20])
        #expect(match.record == MatchRecord(configuration: match.configuration, entries: [], startedAt: start))
        // Nothing to undo, nothing to edit.
        #expect(match.undo() == EditOutcome(applied: false))
        #expect(match.replaceDart(at: 0, with: .single(1)) == EditOutcome(applied: false))
        #expect(match.removeDart(at: 0) == EditOutcome(applied: false))
        #expect(match.entries.isEmpty && match.snapshot.phase == .throwing)
    }

    @Test func onlyAcceptedInputsAreLogged_inOrder() throws {
        var match = try registry.match(.x01, players: 2)
        let first = DartRecord(hit: .treble(20), origin: .camera)
        #expect(match.throwDart(first).isAccepted)
        match.play("S5, S1")
        #expect(match.throwDart(DartRecord(hit: .single(2))) == .rejected(.turnComplete))
        #expect(match.endTurn().isAccepted)
        #expect(SmokeFixtures.journal(match) == ["T20", "S5", "S1", "|"])
        #expect(match.entries.first == .dart(first) && match.entries.last == .endTurn)
        #expect(match.entries.map(\.input) == [.dart(.treble(20)), .dart(.single(5)), .dart(.single(1)), .endTurn])
        #expect(match.canUndo)
    }

    @Test func undo_removesTheLastEntry_whateverItIs_downToTheStart() throws {
        var match = try registry.match(.x01, players: 2)
        let initial = match.snapshot
        match.play("T20 | S5, S5, S5 | S1")
        var steps = 0
        while match.canUndo {
            #expect(match.undo().applied)
            steps += 1
        }
        #expect(steps == 7)
        #expect(match.snapshot == initial && match.entries.isEmpty)
        #expect(!match.undo().applied)
    }

    @Test func undoingTheWinningDart_reopensTheGame() throws {
        var match = try registry.match(.x01, players: 1)
        match.play("T20, T20, T20 | T20, S11, DB")
        #expect(match.phase == .finished)
        match.undo()
        #expect(match.phase == .throwing && match.snapshot.finishReason == nil)
        #expect(match.turnNotation == ["T20", "S11"] && match.fact(0, "remaining") == 50)
    }

    @Test func currentTurn_isWhatFollowsTheLastEndTurn_andStaysEditable() throws {
        var match = try registry.match(.x01, players: 1)
        match.play("T20, T20, T20")
        // Still editable in `turnComplete`…
        #expect(match.phase == .turnComplete && match.replaceDart(at: 2, with: .single(20)).applied)
        #expect(match.fact(0, "remaining") == 161)
        match.play("| T17, MISS, MISS | T20, DB")
        // …and in `finished`: a winning dart read wrongly.
        #expect(match.phase == .finished && match.turnNotation == ["T20", "DB"])
        #expect(match.replaceDart(at: 1, with: .outerBull).applied)
        #expect(match.phase == .throwing && match.fact(0, "remaining") == 25 && match.turnNotation == ["T20", "SB"])
        // The darts of a confirmed turn are locked: indices only address the current turn.
        match.play("MISS |")
        #expect(match.currentTurn.isEmpty)
        #expect(!match.replaceDart(at: 0, with: .single(1)).applied && !match.removeDart(at: 0).applied)
        #expect(!match.replaceDart(at: -1, with: .single(1)).applied && !match.replaceDart(at: 3, with: .single(1)).applied)
        #expect(match.fact(0, "remaining") == 25)
    }

    /// `currentTurn` (the journal) and `snapshot.turn.darts` (the kernel) hold the same darts after every operation,
    /// in the three phases and after both ways of ending a game: a view may index one with the slots of the other
    /// (ARCHITECTURE.md §8.4.7).
    @Test func currentTurn_isAlignedWithTheVolleyOfTheSnapshot_inEveryPhase() throws {
        let games: [(id: GameID, options: GameOptions, players: Int)] = [
            (.x01, ["maxRounds": 2], 2),
            (.x01, ["outRule": "double", "maxRounds": 3], 1),
            (SmokeElimRules.id, ["lives": 2, "maxRounds": 2], 3),
            (SmokeDiscRules.id, ["rounds": 2], 2),
        ]
        var random = SeededRandom(seed: 2026)
        var phases: Set<GamePhase> = []
        var reasons: Set<FinishReason> = []
        var operations = 0
        for game in games {
            for seed in UInt64(0)..<10 {
                var match = try registry.match(game.id, game.options, players: game.players, seed: seed)
                for _ in 0..<120 {
                    let hit = Hit.all[random.nextInt(below: Hit.all.count)]
                    switch random.nextInt(below: 10) {
                    case 0...4: match.throwDart(DartRecord(hit: hit))
                    case 5, 6: match.endTurn()
                    case 7: match.undo()
                    case 8: match.replaceDart(at: random.nextInt(below: 3), with: hit)
                    default: match.removeDart(at: random.nextInt(below: 3))
                    }
                    operations += 1
                    #expect(match.currentTurn.map(\.hit) == match.snapshot.turn.darts.map(\.hit),
                            "\(game.id), seed \(seed), journal \(SmokeFixtures.journal(match))")
                    phases.insert(match.phase)
                    if let reason = match.snapshot.finishReason { reasons.insert(reason) }
                }
            }
        }
        // The walk went through every phase and both kinds of ending.
        #expect(operations == 4_800 && phases == [.throwing, .turnComplete, .finished])
        #expect(reasons.contains(.roundLimit) && (reasons.contains(.victory) || reasons.contains(.lastPlayerStanding)))
    }

    @Test func replaceDart_keepsTheId_marksTheCorrection_clearsTheReviewMark() throws {
        var match = try registry.match(.x01, players: 1)
        let seen = DartRecord(hit: .single(1), position: BoardPoint(x: 41.5, y: 127.9), origin: .camera, needsReview: true)
        match.throwDart(seen)
        #expect(match.currentTurn == [seen])
        // Another hit: `corrected` is set, `needsReview` cleared, the id survives, the old position is erased.
        match.replaceDart(at: 0, with: .single(20))
        var record = try #require(match.currentTurn.first)
        #expect(record.id == seen.id && record.hit == .single(20) && record.origin == .camera)
        #expect(record.corrected && !record.needsReview && record.position == nil)
        // The same hit given again with a position: not a correction of the hit.
        var second = try registry.match(.x01, players: 1)
        second.throwDart(seen)
        second.replaceDart(at: 0, with: .single(1), position: BoardPoint(x: 40, y: 128))
        record = try #require(second.currentTurn.first)
        #expect(!record.corrected && !record.needsReview && record.position == BoardPoint(x: 40, y: 128))
    }

    @Test func removeDart_shiftsTheFollowingDarts() throws {
        var match = try registry.match(.x01, players: 1)
        match.play("T20, S1, S5")
        let records = match.currentTurn
        #expect(match.removeDart(at: 1) == EditOutcome(applied: true))
        #expect(match.currentTurn == [records[0], records[2]])
        // Two darts only: the turn is open again.
        #expect(match.phase == .throwing && match.fact(0, "remaining") == 236 && match.fact(0, "dartsThrown") == 2)
        #expect(!match.removeDart(at: 2).applied)
    }

    @Test func needsReview_isClearedByTheConfirmation_andSetByHand() throws {
        var match = try registry.match(.x01, players: 2)
        match.throwDart(DartRecord(hit: .treble(20), origin: .camera, needsReview: true))
        match.throwDart(DartRecord(hit: .single(5), origin: .camera))
        #expect(match.currentTurn.map(\.needsReview) == [true, false])
        // No replay: the hit and the state are unchanged.
        let before = match.snapshot
        match.setNeedsReview(true, at: 1)
        match.setNeedsReview(false, at: 0)
        match.setNeedsReview(true, at: 7)
        #expect(match.currentTurn.map(\.needsReview) == [false, true] && match.snapshot == before)
        match.endTurn()
        // The confirmed turn has no mark left in the journal.
        let marks = match.entries.compactMap { entry -> Bool? in
            if case .dart(let record) = entry { return record.needsReview }
            return nil
        }
        #expect(marks == [false, false])
        // A refused `endTurn` clears nothing.
        var finished = try registry.match(.x01, players: 1)
        finished.play("T20, T20, T20 | T20, S11")
        finished.throwDart(DartRecord(hit: .innerBull, needsReview: true))
        #expect(finished.phase == .finished && finished.endTurn() == .rejected(.gameFinished))
        #expect(finished.currentTurn.map(\.needsReview) == [false, false, true])
    }

    // MARK: Saving and restoring

    @Test func matchRecord_roundTripsThroughJSON_positionsIncluded() throws {
        var match = try registry.match(SmokeDiscRules.id, ["moving": true], players: 2, seed: 77)
        match.throwDart(DartRecord(hit: .single(6), position: BoardPoint(x: 124.0, y: -0.25), origin: .camera, needsReview: true))
        match.play("T20, MISS@(3.5, -4.0) | S1 |")
        match.throwDart(DartRecord(hit: .double(16), position: BoardPoint(x: -117.4, y: -117.4), origin: .photo, corrected: true))
        let record = match.record
        let decoded = try JSONDecoder().decode(MatchRecord.self, from: JSONEncoder().encode(record))
        #expect(decoded == record)
        #expect(decoded.entries.map(\.position) == [BoardPoint(x: 124.0, y: -0.25), nil, BoardPoint(x: 3.5, y: -4.0), nil, nil, nil,
                                                    BoardPoint(x: -117.4, y: -117.4)])
        #expect(decoded.startedAt == match.startedAt && decoded.configuration == match.configuration)
        // Replaying the saved journal gives the same game.
        let restored = try registry.restoreMatch(decoded)
        #expect(restored.snapshot == match.snapshot && restored.entries == match.entries)
        #expect(restored.startedAt == match.startedAt && restored.record == record)
    }

    @Test func restoreMatch_dropsWhatTheRulesRefuse_andRefusesAnUnknownGame() throws {
        let configuration = GameConfiguration(gameID: .x01, players: testPlayers(1), seed: 0)
        let darts = [Hit.treble(20), .treble(20), .treble(20), .single(1)].map { LogEntry.dart(DartRecord(hit: $0)) }
        let start = Date(timeIntervalSinceReferenceDate: 42)
        let restored = try registry.restoreMatch(MatchRecord(configuration: configuration, entries: darts + [.endTurn], startedAt: start))
        // The fourth dart arrived outside `throwing`: it is dropped, as in any replay.
        #expect(SmokeFixtures.journal(restored) == ["T20", "T20", "T20", "|"])
        #expect(restored.fact(0, "remaining") == 121 && restored.snapshot.round == 2 && restored.startedAt == start)
        #expect(throws: GameConfigurationError.unknownGame(.golf)) {
            try registry.restoreMatch(MatchRecord(configuration: GameConfiguration(gameID: .golf, players: testPlayers(1), seed: 0),
                                                  startedAt: start))
        }
    }

    @Test func determinism_sameConfigurationAndInputs_sameSnapshotsAndEvents() throws {
        let script = "S1@(0.0, 0.0), T20, MISS | S6@(124.0, 0.0) | DB, D3@(-12.5, 40.0), S19 |"
        func run(seed: UInt64) throws -> (outcomes: [InputOutcome], snapshots: [GameSnapshot]) {
            var match = try registry.match(SmokeDiscRules.id, ["moving": true], players: 2, seed: seed)
            var outcomes: [InputOutcome] = [], snapshots: [GameSnapshot] = [match.snapshot]
            for part in script.split(separator: "|", omittingEmptySubsequences: false).dropLast() {
                outcomes += match.play(String(part) + "|")
                snapshots.append(match.snapshot)
            }
            return (outcomes, snapshots)
        }
        let first = try run(seed: 2024), second = try run(seed: 2024), other = try run(seed: 2025)
        #expect(first.outcomes == second.outcomes && first.snapshots == second.snapshots)
        // The seed is part of the game: another seed draws other targets.
        #expect(first.snapshots[0].facts["disc"] != other.snapshots[0].facts["disc"])
        // A copy of a match is an independent game.
        var original = try registry.match(.x01, players: 1)
        original.play("T20")
        var copy = original
        copy.play("T20, T20 |")
        #expect(original.entries.count == 1 && original.fact(0, "remaining") == 241)
        #expect(copy.entries.count == 4 && copy.fact(0, "remaining") == 121)
    }

    // MARK: Position (GAMES.md §2.13)

    /// A disc match and the centre of its first target, in millimetres.
    private func discMatch(seed: UInt64 = 21) throws -> (match: GameMatch, centre: BoardPoint) {
        let match = try registry.match(SmokeDiscRules.id, players: 1, seed: seed)
        guard case .ints(let centre)? = match.gameFact("disc"), centre.count == 2 else {
            throw GameConfigurationError.invalidOptionValue(key: "disc")
        }
        return (match, BoardPoint(x: Double(centre[0]) / 10, y: Double(centre[1]) / 10))
    }

    @Test func thePositionGoesToTheEngine_whenThrown_andWhenReplayed() throws {
        let start = try discMatch()
        var match = start.match
        let centre = start.centre
        let far = BoardPoint(x: centre.x + 80, y: centre.y)
        // Same hit, two positions, two effects.
        #expect(match.throwDart(DartRecord(hit: .single(20), position: far)).events.contains(.noEffect(player: 0)))
        #expect(match.throwDart(DartRecord(hit: .single(20), position: centre)).events
            .contains(.blobDestroyed(player: 0, blob: 0, points: 10)))
        #expect(match.fact(0, "points") == 10)
        let afterTwo = match.snapshot
        match.play("MISS")
        // The undo replays the two darts with their positions: same state as before the third dart.
        match.undo()
        #expect(match.snapshot == afterTwo && match.currentTurn.map(\.position) == [far, centre])
        // Removing the first dart replays the second one with ITS position.
        match.removeDart(at: 0)
        #expect(match.fact(0, "points") == 10 && match.currentTurn.map(\.position) == [centre])
    }

    @Test func replaceDart_recordsThePositionItIsGiven_andErasesItOtherwise() throws {
        let start = try discMatch()
        var match = start.match
        let centre = start.centre
        let far = BoardPoint(x: centre.x + 80, y: centre.y)
        match.throwDart(DartRecord(hit: .single(20), position: far))
        #expect(match.fact(0, "points") == 0)
        // Reticle moved onto the target: the new position is recorded and the dart now scores.
        match.replaceDart(at: 0, with: .single(20), position: centre)
        #expect(match.currentTurn.first?.position == centre && match.fact(0, "points") == 10)
        #expect(match.currentTurn.first?.corrected == false)
        // Hit picked in a list: the position is erased, and the canonical position of the bed applies.
        match.replaceDart(at: 0, with: .treble(20))
        #expect(match.currentTurn.first?.position == nil && match.currentTurn.first?.corrected == true)
        let canonical = try #require(ImpactPoint.canonical(of: .treble(20)))
        let touches = SmokeDiscRules.touches(canonical, x: Int((centre.x * 10).rounded()), y: Int((centre.y * 10).rounded()))
        #expect(match.fact(0, "points") == (touches ? 10 : 0))
    }

    @Test func effectKey_ofAPositionDependentGame_isOnHitAndPosition() throws {
        let (match, centre) = try discMatch()
        let far = BoardPoint(x: centre.x + 80, y: centre.y)
        let scoring = Hit.all.filter { !$0.isMiss }
        // At equal position every hit other than MISS has the same key.
        #expect(Set(scoring.map { match.effectKey(for: $0, position: centre) }).count == 1)
        #expect(Set(scoring.map { match.effectKey(for: $0, position: far) }).count == 1)
        // The same hit at two positions of different effect: two keys.
        #expect(match.effectKey(for: .single(20), position: centre) != match.effectKey(for: .single(20), position: far))
        // MISS touches nothing, even at a position inside the target.
        #expect(match.effectKey(for: .miss, position: centre) != match.effectKey(for: .single(20), position: centre))
        #expect(match.effectKey(for: .miss, position: centre) == match.effectKey(for: .miss, position: far))
        // Without a position the canonical position of each bed applies: the keys follow the beds.
        #expect(match.effectKey(for: .single(6)) == match.effectKey(for: .single(6), position: BoardPoint(x: 134.5, y: 0)))
    }

    @Test func effectKey_ofAnOrdinaryGame_ignoresThePosition() throws {
        var match = try registry.match(.x01, ["inRule": "double"], players: 2)
        let positions: [BoardPoint?] = [nil, BoardPoint(x: 0, y: 0), BoardPoint(x: 124, y: 0), BoardPoint(x: .nan, y: 9e9)]
        for hit in Hit.all {
            #expect(Set(positions.map { match.effectKey(for: hit, position: $0) }).count == 1)
        }
        // Not open yet: every non-double dart has the same effect ("double-in required")…
        #expect(match.effectKey(for: .single(5)) == match.effectKey(for: .treble(6)))
        #expect(match.effectKey(for: .single(5)) == match.effectKey(for: .outerBull))
        // …a double opens, and two doubles of different value leave different facts.
        #expect(match.effectKey(for: .double(5)) != match.effectKey(for: .single(5)))
        #expect(match.effectKey(for: .double(5)) != match.effectKey(for: .double(6)))
        #expect(match.effectKey(for: .miss) != match.effectKey(for: .single(5)))
        // Once open, the value counts.
        match.play("D10")
        #expect(match.effectKey(for: .single(5)) != match.effectKey(for: .treble(6)))
        #expect(match.effectKey(for: .single(15)) == match.effectKey(for: .treble(5)))
    }

    @Test func effectKey_triesTheDartOnACopy_andKnowsARefusedDart() throws {
        var match = try registry.match(.x01, players: 1)
        match.play("T20, T20")
        let before = match.snapshot, entries = match.entries
        _ = match.effectKey(for: .treble(20))
        #expect(match.snapshot == before && match.entries == entries)
        // Once the turn is complete every dart is refused alike: one key.
        match.play("T20")
        #expect(match.phase == .turnComplete)
        #expect(Set(Hit.all.map { match.effectKey(for: $0) }).count == 1)
        #expect(match.effectKey(for: .single(1)) == match.effectKey(for: .miss, position: BoardPoint(x: 1, y: 1)))
    }
}
