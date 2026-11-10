import Foundation
import Testing
import DartCore
import DartGames
import DartTestSupport

/// Properties checked on EVERY delivered game of the registry with 200 random journals each
/// (ARCHITECTURE.md §12.1): replaying the record gives the same snapshot; undoing everything gives back the
/// initial state; two darts of the same `effectKey` followed by the same inputs give the same facts; `ranks`
/// is well formed; no input makes an engine trap.
///
/// A journal is a random game: valid options drawn from the descriptor, then 20 to 100 operations among darts,
/// confirmations, undo, corrections and removals (`CommonPlayout.step`). For a position-dependent game every
/// dart carries, one time out of two, a position drawn in the square of ±180 mm.
@Suite struct CommonPropertyTests {
    static let journalCount = 200

    /// The `index`-th random game of `game` for the property `salt`, after `20 + [0, spread)` random operations.
    /// `afterEach` sees the match after every operation, with the snapshot and the journal length before it.
    private func randomGame(_ game: GameID, _ descriptor: GameDescriptor, salt: UInt64, index: Int, spread: Int = 81,
                            afterEach: (GameMatch, CommonPlayout.Step, GameSnapshot, Int) -> Void = { _, _, _, _ in })
    throws -> GameMatch {
        var random = SeededRandom(seed: CommonPlayout.seed(game, salt &* 1_000 &+ UInt64(index)))
        var match = try CommonPlayout.randomMatch(descriptor, &random)
        let operations = 20 + random.nextInt(below: spread)
        for _ in 0..<operations {
            let before = match.snapshot
            let entries = match.entries.count
            let step = CommonPlayout.step(&match, descriptor, &random)
            afterEach(match, step, before, entries)
        }
        return match
    }

    /// Feeds the journal of `source` to a new engine of the same configuration, entry by entry.
    /// Returns what the engine answered to each entry, and its last snapshot.
    private func feedAgain(_ source: GameMatch) throws -> (outcomes: [InputOutcome], snapshot: GameSnapshot) {
        var engine = try source.definition.makeEngine(source.configuration)
        let outcomes = source.entries.map { engine.apply($0.input, position: $0.position) }
        return (outcomes, engine.snapshot)
    }

    // MARK: Replaying the record gives the same snapshot

    @Test(arguments: CommonPlayout.deliveredGames)
    func replayingTheRecord_givesTheSameSnapshot(_ game: GameID) throws {
        let descriptor = try CommonPlayout.descriptor(of: game)
        var failures = CommonPlayout.Failures()
        var finishedGames = 0
        for index in 0..<Self.journalCount {
            let match = try randomGame(game, descriptor, salt: 1, index: index)
            if match.phase == .finished { finishedGames += 1 }
            // GameRegistry.restoreMatch replays the journal on a new engine: same state, nothing dropped.
            let restored = try CommonPlayout.registry.restoreMatch(match.record)
            failures.check(restored.snapshot == match.snapshot && restored.record == match.record,
                           "the restored game differs: \(CommonPlayout.describe(match))")
            // The saved form is JSON: the game survives the round trip, positions included.
            let decoded = try JSONDecoder().decode(MatchRecord.self, from: JSONEncoder().encode(match.record))
            failures.check(decoded == match.record, "the record changed through JSON: \(CommonPlayout.describe(match))")
            let reloaded = try CommonPlayout.registry.restoreMatch(decoded)
            failures.check(reloaded.snapshot == match.snapshot, "the reloaded game differs: \(CommonPlayout.describe(match))")
            // Same configuration and same inputs: same state AND same events, twice (GAMES.md §2.4).
            let first = try feedAgain(match)
            let second = try feedAgain(match)
            failures.check(first.outcomes.allSatisfy { $0.isAccepted }, "the journal holds a refused input: \(CommonPlayout.describe(match))")
            failures.check(first.snapshot == match.snapshot && second.snapshot == match.snapshot,
                           "the journal fed again gives another state: \(CommonPlayout.describe(match))")
            failures.check(first.outcomes == second.outcomes, "the journal fed twice gives other events: \(CommonPlayout.describe(match))")
        }
        #expect(failures.isEmpty, "\(failures.report)")
        // The journals are long enough to reach the end of a game.
        #expect(finishedGames > 0, "no journal of \(game) reached the end of a game")
    }

    // MARK: Undoing everything gives back the initial state

    @Test(arguments: CommonPlayout.deliveredGames)
    func undoingEverything_givesBackTheInitialState(_ game: GameID) throws {
        let descriptor = try CommonPlayout.descriptor(of: game)
        var failures = CommonPlayout.Failures()
        for index in 0..<Self.journalCount {
            // Shorter journals: every undo replays the whole game.
            var match = try randomGame(game, descriptor, salt: 2, index: index, spread: 36)
            let described = CommonPlayout.describe(match)
            // The state after each entry of the journal, played forward once.
            var forward = try CommonPlayout.makeMatch(match.configuration)
            var history = [forward.snapshot]
            for entry in match.entries {
                switch entry {
                case .dart(let record): forward.throwDart(record)
                case .endTurn: forward.endTurn()
                }
                history.append(forward.snapshot)
            }
            failures.check(forward.entries == match.entries && forward.snapshot == match.snapshot,
                           "the journal played forward gives another state: \(described)")
            // Each undo removes the last entry, whatever it is, and gives the state of the journal without it:
            // draws included, since the generator is recreated at every replay (GAMES.md §2.5, §2.8).
            var remaining = match.entries.count
            var mismatch: Int?
            while match.canUndo {
                let edit = match.undo()
                remaining -= 1
                if !edit.applied || !edit.dropped.isEmpty || match.entries.count != remaining || match.snapshot != history[remaining] {
                    mismatch = mismatch ?? remaining
                }
            }
            failures.check(mismatch == nil, "undo down to \(mismatch ?? -1) entries differs from the replay: \(described)")
            failures.check(remaining == 0 && match.entries.isEmpty && match.snapshot == history[0],
                           "undoing everything does not give back the initial state: \(described)")
            // On an empty journal undo does nothing.
            failures.check(!match.undo().applied && match.snapshot == history[0], "undo on an empty journal: \(described)")
        }
        #expect(failures.isEmpty, "\(failures.report)")
    }

    // MARK: Two darts of the same effectKey, followed by the same inputs, give the same facts

    @Test(arguments: CommonPlayout.deliveredGames)
    func twoDartsOfTheSameEffectKey_followedByTheSameInputs_giveTheSameFacts(_ game: GameID) throws {
        let descriptor = try CommonPlayout.descriptor(of: game)
        var failures = CommonPlayout.Failures()
        var compared = 0
        for index in 0..<Self.journalCount {
            var random = SeededRandom(seed: CommonPlayout.seed(game, 3_000 &+ UInt64(index)))
            var match = try CommonPlayout.randomMatch(descriptor, &random)
            for _ in 0..<random.nextInt(below: 60) {
                _ = CommonPlayout.step(&match, descriptor, &random)
            }
            // Back to a state where a dart is accepted.
            while match.phase != .throwing && match.canUndo { match.undo() }
            guard match.phase == .throwing else { continue }

            // For a position-dependent game the two darts share their position (GAMES.md §2.13).
            let position = CommonPlayout.randomPosition(descriptor, &random)
            let groups = Dictionary(grouping: Hit.all.indices) { match.effectKey(for: Hit.all[$0], position: position) }
            // Dictionary order changes with every process: the groups are sorted before one is drawn.
            let candidates = groups.values.filter { $0.count >= 2 }.sorted { $0[0] < $1[0] }
            guard !candidates.isEmpty else { continue }
            let group = candidates[random.nextInt(below: candidates.count)]
            let pick = random.nextInt(below: group.count)
            let other = (pick + 1 + random.nextInt(below: group.count - 1)) % group.count
            let hits = [Hit.all[group[pick]], Hit.all[group[other]]]
            let described = "\(hits[0]) and \(hits[1]) after \(CommonPlayout.describe(match))"

            var first = match, second = match
            let thrown = first.throwDart(DartRecord(hit: hits[0], position: position)).isAccepted
                && second.throwDart(DartRecord(hit: hits[1], position: position)).isAccepted
            failures.check(thrown, "a dart was refused while throwing: \(described)")
            var steps = 0
            var divergence: String?
            func compare() {
                guard divergence == nil else { return }
                let a = first.snapshot, b = second.snapshot
                if a.players.map(\.facts) != b.players.map(\.facts) {
                    divergence = "player facts differ"
                } else if a.facts != b.facts {
                    divergence = "game facts differ"
                } else if a.phase != b.phase {
                    divergence = "phases differ"
                } else if a.ranks != b.ranks {
                    divergence = "ranks differ"
                }
            }
            compare()
            // The same continuation for both: darts while the turn is open, the confirmation once it is closed.
            var continuation: [String] = []
            while steps < 12 && divergence == nil && first.phase != .finished {
                steps += 1
                if first.phase == .turnComplete || random.nextInt(below: 8) == 0 {
                    first.endTurn()
                    second.endTurn()
                    continuation.append("|")
                } else {
                    let dart = CommonPlayout.randomDart(descriptor, &random)
                    first.throwDart(dart)
                    second.throwDart(dart)
                    continuation.append(dart.hit.notation)
                }
                compare()
            }
            failures.check(divergence == nil, "\(divergence ?? "") after \(continuation): \(described)")
            compared += 1
        }
        #expect(failures.isEmpty, "\(failures.report)")
        // Every game has darts of equal effect (at least where a dart does nothing): the property was exercised.
        #expect(compared > 0, "no pair of darts of equal effect was found for \(game)")
    }

    // MARK: Ranks are well formed, and the common rules hold after every operation

    @Test(arguments: CommonPlayout.deliveredGames)
    func ranksAreWellFormed_andTheCommonRulesHold_afterEveryOperation(_ game: GameID) throws {
        let descriptor = try CommonPlayout.descriptor(of: game)
        var failures = CommonPlayout.Failures()
        var phases: Set<GamePhase> = []
        for index in 0..<Self.journalCount {
            _ = try randomGame(game, descriptor, salt: 4, index: index) { match, step, before, entries in
                phases.insert(match.phase)
                var violations = CommonPlayout.snapshotViolations(match)
                let after = match.snapshot
                switch step {
                case .dart(let dart, let outcome):
                    violations += CommonPlayout.inputViolations(.dart(dart.hit), outcome, before: before, after: after)
                    // Only an accepted input is logged (GAMES.md §2.4).
                    if match.entries.count != entries + (outcome.isAccepted ? 1 : 0) { violations.append("journal length after a dart") }
                    if outcome.isAccepted && match.entries.last != .dart(dart) { violations.append("the dart is not the last entry") }
                case .endTurn(let outcome):
                    violations += CommonPlayout.inputViolations(.endTurn, outcome, before: before, after: after)
                    if match.entries.count != entries + (outcome.isAccepted ? 1 : 0) { violations.append("journal length after endTurn") }
                    if outcome.isAccepted && match.entries.last != .endTurn { violations.append("endTurn is not the last entry") }
                case .undo(let edit):
                    // Undo removes the last entry whatever it is; on an empty journal it does nothing.
                    if edit.applied != (entries > 0) { violations.append("undo applied: \(edit.applied) with \(entries) entries") }
                    if match.entries.count != max(entries - 1, 0) { violations.append("journal length after undo") }
                    if !edit.applied && after != before { violations.append("an undo that did nothing changed the state") }
                case .replace(let edit), .remove(let edit):
                    if !edit.applied && (after != before || match.entries.count != entries) {
                        violations.append("a correction that did nothing changed the state")
                    }
                    if edit.applied && match.entries.count > entries { violations.append("a correction lengthened the journal") }
                }
                failures.record(violations, CommonPlayout.describe(match))
            }
        }
        #expect(failures.isEmpty, "\(failures.report)")
        // The walk went through the three phases.
        #expect(phases == [.throwing, .turnComplete, .finished])
    }

    // MARK: No input makes an engine trap

    /// Every hit, in every phase, with every kind of recorded position, the unreadable ones included: a game
    /// is a total function of its inputs (GAMES.md §2.13). The process surviving is the assertion.
    @Test(arguments: CommonPlayout.deliveredGames)
    func noInputMakesAnEngineTrap(_ game: GameID) throws {
        let descriptor = try CommonPlayout.descriptor(of: game)
        let positions: [BoardPoint?] = [
            nil, .centre, BoardPoint(x: 169.9, y: 0), BoardPoint(x: -1_000, y: 1_000),
            BoardPoint(x: .nan, y: 0), BoardPoint(x: 0, y: .nan), BoardPoint(x: .infinity, y: -.infinity),
            BoardPoint(x: .greatestFiniteMagnitude, y: -.greatestFiniteMagnitude),
            BoardPoint(x: .leastNonzeroMagnitude, y: -0.0), BoardPoint(x: 0.05, y: -0.05),
        ]
        var random = SeededRandom(seed: CommonPlayout.seed(game, 5))
        var failures = CommonPlayout.Failures()
        var inputs = 0
        for round in 0..<Self.journalCount {
            var match = try CommonPlayout.randomMatch(descriptor, &random)
            // Every hit once per game, in a shuffled order, each with one of the positions; then random darts.
            let hits = random.shuffled(Hit.all) + (0..<17).map { _ in CommonPlayout.randomHit(&random) }
            for (index, hit) in hits.enumerated() {
                let position = positions[(index + round) % positions.count]
                if match.phase == .finished { break }
                // Sometimes an early confirmation, or an edit inside or outside the volley.
                switch random.nextInt(below: 12) {
                case 0: match.endTurn()
                case 1: match.replaceDart(at: random.nextInt(below: 5) - 1, with: hit, position: position)
                case 2: match.removeDart(at: random.nextInt(below: 5) - 1)
                default: break
                }
                match.throwDart(DartRecord(hit: hit, position: position))
                // Trying a dart on a copy of the engine must not trap either.
                if index % 5 == 0 { _ = match.effectKey(for: hit, position: position) }
                if match.phase == .turnComplete && random.nextInt(below: 4) != 0 { match.endTurn() }
                inputs += 1
            }
            failures.record(CommonPlayout.snapshotViolations(match), CommonPlayout.describe(match))
            // Refused inputs and useless edits at the very end do not trap either.
            match.throwDart(DartRecord(hit: .treble(20), position: positions[round % positions.count]))
            match.endTurn()
            match.endTurn()
            match.replaceDart(at: 7, with: .miss)
            match.removeDart(at: -1)
            while match.canUndo && random.nextInt(below: 3) != 0 { match.undo() }
            failures.record(CommonPlayout.snapshotViolations(match), CommonPlayout.describe(match))
        }
        #expect(failures.isEmpty, "\(failures.report)")
        #expect(inputs > Self.journalCount * 5)
    }
}
