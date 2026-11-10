import Foundation
import Testing
import DartCore
import DartGames
import DartTestSupport

/// The expert level of Killer (GAMES.md §5.4, "Retirage du niveau expert"): when a number is redrawn, what is
/// excluded, one draw per redraw on the stream of the game, and above all determinism: undo, replace, remove and
/// replay rebuild exactly the same redraws.
@Suite struct KillerExpertTests {
    private let registry = GameRegistry.standard

    private func expert(players: Int, seed: UInt64, _ more: [String: OptionValue] = [:]) throws -> GameMatch {
        var values = more
        values["level"] = "expert"
        return try registry.match(.killer, GameOptions(values), players: players, seed: seed)
    }

    /// The numbers a player may draw: 1...20 in ascending order, without the numbers of the OTHER players alive
    /// and without the number the player had during the previous turn. Written from GAMES.md §5.4, on the facts.
    private func candidates(for player: PlayerIndex, in match: GameMatch) -> [Int] {
        var excluded = Set(match.killerZones[player])
        for other in match.killerAlive where other != player {
            excluded.formUnion(match.killerZones[other])
        }
        return (1...20).filter { !excluded.contains($0) }
    }

    private func zoneChanges(_ events: [GameEvent]) -> [[Int]] {
        events.compactMap { event in
            if case .zoneChanged(let player, let zone) = event { return [player] + zone }
            return nil
        }
    }

    /// Plays `count` pseudo-random inputs (fewer if the game ends) and returns the snapshot after each one;
    /// `snapshots[0]` is the initial state.
    private func playRandomly(_ match: inout GameMatch, inputs count: Int, botSeed: UInt64) -> [GameSnapshot] {
        var bot = SeededRandom(seed: botSeed)
        var snapshots = [match.snapshot]
        while match.phase != .finished && snapshots.count <= count {
            #expect(match.killerApply(KillerTestBot.input(for: match, random: &bot)).isAccepted)
            snapshots.append(match.snapshot)
        }
        return snapshots
    }

    // MARK: When a number is redrawn

    @Test func roundOne_keepsTheInitialNumbers_theFirstRedrawIsTheSecondTurnOfJ1() throws {
        for players in 2...8 {
            var match = try expert(players: players, seed: 3)
            let initial = match.killerZones
            for turn in 0..<(players - 1) {
                // No redraw at the first turn of any player.
                #expect(match.endTurn().events == [.turnCompleted(player: turn), .turnStarted(player: turn + 1, round: 1)])
                #expect(match.killerZones == initial)
            }
            let expected = candidates(for: 0, in: match)
            #expect(expected.count == 20 - players)
            let events = match.endTurn().events
            let number = match.killerZones[0][0]
            // The redraw happens while the `endTurn` that gives the turn is processed, just before `turnStarted`.
            #expect(events == [.turnCompleted(player: players - 1), .roundStarted(round: 2),
                               .zoneChanged(player: 0, zone: [number]), .turnStarted(player: 0, round: 2)])
            // The number really changes, avoids the others, and the others keep theirs.
            #expect(number != initial[0][0] && expected.contains(number))
            #expect(Array(match.killerZones.dropFirst()) == Array(initial.dropFirst()))
            match.killerExpectInvariants(width: 1, lives: 3, armingHits: 3)
        }
    }

    @Test func fixedLevels_neverRedraw() throws {
        for level in ["easy", "medium", "hard"] {
            var match = try registry.match(.killer, ["level": .string(level), "maxRounds": .null], players: 4, seed: 6)
            let initial = match.killerZones
            var bot = SeededRandom(seed: 60)
            for _ in 0..<400 where match.phase != .finished {
                let outcome = match.killerApply(KillerTestBot.input(for: match, random: &bot))
                #expect(zoneChanges(outcome.events).isEmpty)
            }
            #expect(match.killerZones == initial, "\(level)")
        }
    }

    /// Every redraw of a long random game, for 2 to 8 players, checked against the rule written on the facts and
    /// against a second generator: exactly one draw per redraw, none for anything else.
    @Test(arguments: 2...8)
    func everyRedraw_followsTheRule_andConsumesExactlyOneDraw(players: Int) throws {
        var totalRedraws = 0
        for seed in UInt64(20)..<26 {
            var match = try expert(players: players, seed: seed, ["lives": 4, "armingHits": 2, "maxRounds": 12])
            var model = SeededRandom(seed: seed)
            #expect(ringLayout(playerCount: players, width: 1, rng: &model) == match.killerZones)
            var bot = SeededRandom(seed: seed &* 7 &+ UInt64(players))
            var redraws = 0
            var frozen: [PlayerIndex: [Int]] = [:]
            for _ in 0..<600 where match.phase != .finished {
                let before = match
                let input = KillerTestBot.input(for: match, random: &bot)
                let outcome = match.killerApply(input)
                #expect(outcome.isAccepted)
                match.killerExpectInvariants(width: 1, lives: 4, armingHits: 2)
                let changes = zoneChanges(outcome.events)

                if input == .endTurn, match.phase != .finished, match.snapshot.round > 1 {
                    let next = match.snapshot.currentPlayer
                    let allowed = candidates(for: next, in: before)
                    #expect(allowed.count >= 12)
                    let expected = allowed[model.nextInt(below: allowed.count)]
                    #expect(changes == [[next, expected]], "seed \(seed), round \(match.snapshot.round)")
                    #expect(Array(outcome.events.suffix(2)) == [.zoneChanged(player: next, zone: [expected]),
                                                               .turnStarted(player: next, round: match.snapshot.round)])
                    // Only the player whose turn starts moves; an eliminated player is never redrawn.
                    for other in 0..<players where other != next {
                        #expect(match.killerZones[other] == before.killerZones[other])
                    }
                    #expect(match.killerZones[next] == [expected] && match.killerZones[next] != before.killerZones[next])
                    #expect(!match.killerBools("eliminated")[next])
                    redraws += 1
                } else {
                    // A dart, a turn of round 1 or the end of the game: no zone moves, nothing is drawn.
                    #expect(changes.isEmpty)
                    #expect(match.killerZones == before.killerZones)
                }
                for (player, zone) in frozen {
                    #expect(match.killerZones[player] == zone, "an eliminated player was redrawn")
                }
                for player in 0..<players where match.killerBools("eliminated")[player] && frozen[player] == nil {
                    frozen[player] = match.killerZones[player]
                }
            }
            totalRedraws += redraws
            // The whole journal replays to the same state, redraws included.
            #expect(try registry.restoreMatch(match.record).snapshot == match.snapshot)
        }
        #expect(totalRedraws >= 50, "the games are long enough to hold many redraws")
    }

    @Test func numberOfAnEliminatedPlayer_canBeDrawnAgain_byAPlayerAlive() throws {
        // GAMES.md §5.4: at the expert level the number of an eliminated player becomes drawable again.
        var reused = 0
        for seed in UInt64(0)..<40 {
            var match = try expert(players: 8, seed: seed, ["lives": 1, "armingHits": 1, "maxRounds": .null])
            var bot = SeededRandom(seed: seed &+ 500)
            for _ in 0..<500 where match.phase != .finished {
                match.killerApply(KillerTestBot.input(for: match, random: &bot))
                let zones = match.killerZones
                let eliminated = match.killerBools("eliminated")
                let dead = Set(zones.indices.filter { eliminated[$0] }.map { zones[$0][0] })
                if match.killerAlive.contains(where: { dead.contains(zones[$0][0]) }) {
                    reused += 1
                    // Shared with an eliminated player only: the hit goes to the player alive.
                    let owner = match.killerAlive.first { dead.contains(zones[$0][0]) } ?? 0
                    if match.phase == .throwing, match.killerBools("isKiller")[match.snapshot.currentPlayer],
                       owner != match.snapshot.currentPlayer {
                        var copy = match
                        let events = copy.throwDart(DartRecord(hit: .single(zones[owner][0]))).events
                        #expect(events.contains(.lifeLost(player: owner, by: match.snapshot.currentPlayer, livesLeft: 0)))
                    }
                }
                match.killerExpectInvariants(width: 1, lives: 1, armingHits: 1)
            }
        }
        #expect(reused > 0)
    }

    // MARK: Determinism (GAMES.md §5.4 "Déterminisme", §2.5)

    @Test(arguments: [2, 3, 5, 8])
    func undoThenRedo_rebuildsExactlyTheSameRedraws(players: Int) throws {
        for seed in UInt64(40)..<43 {
            var match = try expert(players: players, seed: seed, ["lives": 5, "armingHits": 2, "maxRounds": 10])
            let snapshots = playRandomly(&match, inputs: 160, botSeed: seed &+ 77)
            let entries = match.entries
            #expect(snapshots.count == entries.count + 1)
            #expect(snapshots.contains { $0.round >= 4 }, "the journal is long enough to hold redraws")

            // Undo, one entry at a time, all the way to the start: every earlier state comes back.
            for index in stride(from: entries.count - 1, through: 0, by: -1) {
                #expect(match.undo().applied)
                #expect(match.snapshot == snapshots[index], "undo to \(index)")
            }
            #expect(match.entries.isEmpty && !match.canUndo)

            // Redo the same inputs: the same numbers are drawn again, the same events come out.
            var twin = try expert(players: players, seed: seed, ["lives": 5, "armingHits": 2, "maxRounds": 10])
            for (index, entry) in entries.enumerated() {
                let events = match.killerApply(entry.input).events
                #expect(twin.killerApply(entry.input).events == events)
                #expect(match.snapshot == snapshots[index + 1], "redo to \(index + 1)")
            }

            // Undo then redo one `endTurn` at a time, wherever one sits in the journal.
            for (index, entry) in entries.enumerated().reversed() {
                if entry == .endTurn {
                    #expect(match.undo().applied)
                    #expect(match.snapshot == snapshots[index])
                    #expect(match.endTurn().isAccepted)
                    #expect(match.snapshot == snapshots[index + 1])
                }
                #expect(match.undo().applied)
            }
            #expect(match.snapshot == snapshots[0])
        }
    }

    @Test(arguments: [2, 4, 8])
    func replayOfASavedGame_givesTheSameSnapshotAtEveryStep(players: Int) throws {
        var match = try expert(players: players, seed: 91, ["lives": 2, "armingHits": 1])
        let snapshots = playRandomly(&match, inputs: 200, botSeed: 919)
        // Every prefix of the journal, restored from scratch, is the state that was seen live.
        for length in stride(from: 0, through: match.entries.count, by: 7) {
            let record = MatchRecord(configuration: match.configuration, entries: Array(match.entries.prefix(length)),
                                     startedAt: match.startedAt)
            #expect(try registry.restoreMatch(record).snapshot == snapshots[length], "prefix \(length)")
        }
        // Through JSON too: the saved game is the configuration (seed included) and the journal.
        let data = try JSONEncoder().encode(match.record)
        let decoded = try JSONDecoder().decode(MatchRecord.self, from: data)
        #expect(decoded == match.record)
        let restored = try registry.restoreMatch(decoded)
        #expect(restored.snapshot == match.snapshot && restored.entries == match.entries)
    }

    @Test func sameSeed_sameJournal_sameEvents_otherSeed_otherNumbers() throws {
        var first = try expert(players: 4, seed: 123)
        var second = try expert(players: 4, seed: 123)
        var other = try expert(players: 4, seed: 124)
        var bot = SeededRandom(seed: 9)
        var differs = first.killerZones != other.killerZones
        for _ in 0..<150 where first.phase != .finished {
            let input = KillerTestBot.input(for: first, random: &bot)
            #expect(first.killerApply(input) == second.killerApply(input))
            #expect(first.snapshot == second.snapshot)
            other.killerApply(input)
            differs = differs || first.killerZones != other.killerZones
        }
        #expect(differs)
    }

    // MARK: Corrections in the current turn

    /// GAMES.md §5.4: correcting a dart of the current turn does not change the number of the current player.
    /// No zone moves at all: zones only change when an `endTurn` starts a turn.
    @Test(arguments: [2, 3, 6, 8])
    func replaceAndRemove_inTheCurrentTurn_neverMoveAZone(players: Int) throws {
        var match = try expert(players: players, seed: 55, ["lives": 9, "armingHits": 2, "maxRounds": .null])
        var bot = SeededRandom(seed: 555)
        var edits = SeededRandom(seed: 5555)
        var corrections = 0
        for _ in 0..<400 where match.phase != .finished {
            match.killerApply(KillerTestBot.input(for: match, random: &bot))
            let turn = match.currentTurn
            guard !turn.isEmpty, match.snapshot.round > 1 else { continue }
            let index = edits.nextInt(below: turn.count)
            let hit = Hit.all[edits.nextInt(below: Hit.all.count)]

            var replaced = match
            #expect(replaced.replaceDart(at: index, with: hit).applied)
            #expect(replaced.killerZones == match.killerZones)
            #expect(replaced.snapshot.currentPlayer == match.snapshot.currentPlayer && replaced.snapshot.round == match.snapshot.round)
            #expect(try registry.restoreMatch(replaced.record).snapshot == replaced.snapshot)
            replaced.killerExpectInvariants(width: 1, lives: 9, armingHits: 2)

            var removed = match
            #expect(removed.removeDart(at: index).applied)
            #expect(removed.killerZones == match.killerZones)
            #expect(try registry.restoreMatch(removed.record).snapshot == removed.snapshot)
            removed.killerExpectInvariants(width: 1, lives: 9, armingHits: 2)

            // Putting the dart back gives the state before the correction, whatever was dropped on the way.
            if replaced.currentTurn.count == turn.count {
                #expect(replaced.replaceDart(at: index, with: turn[index].hit).applied)
                #expect(replaced.snapshot == match.snapshot)
            }
            corrections += 1
        }
        #expect(corrections >= 40)
    }

    /// A correction that cancels an elimination changes who plays next, and therefore who is redrawn with the
    /// next draw of the stream. Both branches are computed here from the generator.
    @Test func correctionThatCancelsAnElimination_changesWhoIsRedrawnNext() throws {
        var match = try expert(players: 3, seed: 7, ["lives": 1, "armingHits": 1])
        #expect(match.killerZones == [[14], [15], [4]])
        match.play("S14, MISS, MISS | MISS | MISS |")
        // Draw 21: J1 moves to the 16, as in KIL-3.
        #expect(match.killerZones == [[16], [15], [4]] && match.fact(0, "isKiller") == true)
        var stream = SeededRandom(seed: 7)
        for _ in 0..<21 { _ = stream.next() }

        match.play("S15")
        #expect(match.killerAlive == [0, 2])
        let eliminated = match

        // Branch A: J2 stays eliminated. J3 plays next and takes draw 22, among 18 numbers (not 16, not 4).
        var branchA = stream
        let numbersA = (1...20).filter { $0 != 16 && $0 != 4 }
        let expectedA = numbersA[branchA.nextInt(below: 18)]
        #expect(match.endTurn().events == [.turnCompleted(player: 0), .zoneChanged(player: 2, zone: [expectedA]),
                                           .turnStarted(player: 2, round: 2)])
        #expect(match.killerZones == [[16], [15], [expectedA]])
        let afterA = match.snapshot

        // Branch B: the dart is corrected to a MISS. J2 is alive, plays next and takes draw 22, among 17 numbers.
        #expect(match.undo().applied)
        #expect(match.snapshot == eliminated.snapshot)
        #expect(match.replaceDart(at: 0, with: .miss).applied)
        // The correction leaves every number where it was, the current player's first of all.
        #expect(match.killerZones == [[16], [15], [4]] && match.killerAlive == [0, 1, 2])
        var branchB = stream
        let numbersB = (1...20).filter { $0 != 16 && $0 != 4 && $0 != 15 }
        let expectedB = numbersB[branchB.nextInt(below: 17)]
        #expect(expectedB == 11)
        #expect(match.endTurn().events == [.turnCompleted(player: 0), .zoneChanged(player: 1, zone: [11]),
                                           .turnStarted(player: 1, round: 2)])
        #expect(match.killerZones == [[16], [11], [4]])
        let afterB = match.snapshot

        // Removing the dart instead of correcting it: J2 is alive just the same, and draws the same number.
        #expect(match.undo().applied)
        #expect(match.removeDart(at: 0).applied)
        #expect(match.currentTurn.isEmpty && match.killerZones == [[16], [15], [4]] && match.phase == .throwing)
        match.endTurn()
        #expect(match.snapshot == afterB)

        // Back to branch A through the journal: exactly the same state as the first time.
        #expect(match.undo().applied)
        match.play("S15")
        #expect(match.snapshot == eliminated.snapshot)
        match.endTurn()
        #expect(match.snapshot == afterA)
    }

    @Test func correctionOfAnEarlierTurn_needsUndo_andReplaysTheSameRedraws() throws {
        var match = try expert(players: 3, seed: 7)
        match.play("S14, MISS, MISS | MISS ×3 | MISS ×3 | S14, S16, T16 | MISS ×3 |")
        #expect(match.killerZones == [[16], [11], [9]] && match.fact(0, "isKiller") == true)
        let reference = match.snapshot
        // The darts of a confirmed turn are locked: undo back to it, correct, play again.
        #expect(!match.replaceDart(at: 0, with: .miss).applied)
        for _ in 0..<5 { match.undo() }
        #expect(match.turnNotation == ["S14", "S16", "T16"] && match.killerZones == [[16], [15], [4]])
        #expect(match.replaceDart(at: 2, with: .miss).applied)
        match.play("| MISS ×3 |")
        // The same numbers are drawn (the darts do not touch the stream); only the arming differs.
        #expect(match.killerZones == [[16], [11], [9]])
        #expect(match.fact(0, "armingProgress") == 2 && match.fact(0, "isKiller") == false)
        #expect(match.replaceDart(at: 0, with: .miss).applied == false)
        for _ in 0..<5 { match.undo() }
        #expect(match.replaceDart(at: 2, with: .treble(16)).applied)
        match.play("| MISS ×3 |")
        #expect(match.snapshot == reference)
    }
}
