import Testing
import DartCore
import DartGames
import DartTestSupport

/// The turn machine of GAMES.md §2.4 to §2.6 seen through every delivered game of the registry: the round
/// limit, games that always terminate, corrections that replay the journal, and the recorded position that
/// only a position-dependent game may read (§2.13).
@Suite struct CommonTurnTests {
    private let registry = CommonPlayout.registry

    private func describe(_ configuration: GameConfiguration) -> String {
        let options = configuration.options.values.sorted { $0.key < $1.key }.map { "\($0.key): \($0.value)" }
        return "\(configuration.gameID) {\(options.joined(separator: ", "))}, \(configuration.players.count) players, seed \(configuration.seed)"
    }

    // MARK: Round limit (GAMES.md §2.6)

    /// Confirmations alone, without a single dart: no game can be won or lost that way (a victory and an
    /// elimination both happen on a dart, §2.7), so the game runs to its round limit and ends exactly at the
    /// confirmation of the last turn of the last round.
    @Test(arguments: CommonPlayout.deliveredGames)
    func roundLimit_endsTheGameAtTheConfirmationOfTheLastTurn(_ game: GameID) throws {
        let descriptor = try CommonPlayout.descriptor(of: game)
        var random = SeededRandom(seed: CommonPlayout.seed(game, 11))
        var failures = CommonPlayout.Failures()
        var limited = 0
        for _ in 0..<60 {
            var match = try CommonPlayout.randomMatch(descriptor, &random)
            guard let limit = match.snapshot.roundLimit else { continue }
            limited += 1
            let players = match.players.count
            let described = describe(match.configuration)
            failures.check(limit >= 1, "round limit \(limit): \(described)")
            for turn in 0..<(max(limit, 0) * players) {
                // A player's k-th turn is always in round k.
                let before = match.snapshot
                failures.check(before.phase == .throwing && before.round == 1 + turn / players && before.currentPlayer == turn % players,
                               "turn \(turn) is player \(before.currentPlayer) in round \(before.round), phase \(before.phase): \(described)")
                let outcome = match.endTurn()
                failures.record(CommonPlayout.inputViolations(.endTurn, outcome, before: before, after: match.snapshot),
                                "turn \(turn) of \(described)")
                failures.check(match.snapshot.roundLimit == limit, "the round limit changed during \(described)")
            }
            let end = match.snapshot
            failures.check(end.phase == .finished && end.finishReason == .roundLimit && end.round == limit && end.turn.darts.isEmpty,
                           "after \(limit) rounds of confirmations: phase \(end.phase), round \(end.round): \(described)")
            failures.record(CommonPlayout.snapshotViolations(match), described)
            // The end is only evaluated on the confirmation: undoing it gives back an open game.
            failures.check(match.undo().applied && match.phase == .throwing && match.snapshot.finishReason == nil,
                           "undoing the last confirmation: \(described)")
        }
        #expect(failures.isEmpty, "\(failures.report)")
        if limited == 0 {
            print("Common tests: \(game) never has a round limit with the options drawn; its round limit is not checked.")
        }
    }

    // MARK: Games terminate

    /// Random games played forward to their end, on a bare engine. A game with a round limit is over after at
    /// most `limit × players` turns of three darts and a confirmation, whatever is thrown. The limit is only
    /// evaluated on the confirmation, which leaves time for a correction after the last dart (§2.6): a dart
    /// never ends a game with the reason `roundLimit`, and a confirmation never ends it with another one.
    @Test(arguments: CommonPlayout.deliveredGames)
    func randomGames_neverTrap_andAlwaysTerminate(_ game: GameID) throws {
        let descriptor = try CommonPlayout.descriptor(of: game)
        let definition = try #require(registry.definition(for: game))
        var random = SeededRandom(seed: CommonPlayout.seed(game, 13))
        var failures = CommonPlayout.Failures()
        var reasons: Set<FinishReason> = []
        var bounded = 0
        for _ in 0..<CommonPropertyTests.journalCount {
            let configuration = CommonPlayout.randomConfiguration(descriptor, &random)
            var engine = try definition.makeEngine(configuration)
            // Without a round limit nothing bounds a game of random darts: it is played for a while.
            let bound = engine.snapshot.roundLimit.map { $0 * configuration.players.count * (dartsPerTurn + 1) }
            let playout = CommonPlayout.playForward(engine: &engine, descriptor, &random, limit: bound.map { $0 + 1 } ?? 600)
            let end = engine.snapshot
            failures.check(!playout.refused && end.phase == playout.phase && end.finishReason == playout.reason,
                           "the events do not tell the phase \(end.phase): \(describe(configuration))")
            failures.record(CommonPlayout.snapshotViolations(end, of: configuration), describe(configuration))
            if let bound {
                bounded += 1
                failures.check(end.phase == .finished && playout.inputs <= bound,
                               "not finished after \(playout.inputs) inputs: \(describe(configuration))")
            }
            guard let reason = end.finishReason else { continue }
            reasons.insert(reason)
            failures.check((reason == .roundLimit) == !playout.endedOnADart,
                           "\(reason) on a \(playout.endedOnADart ? "dart" : "confirmation"): \(describe(configuration))")
            failures.check(end.winners.allSatisfy { !end.players[$0].isEliminated }, "an eliminated winner: \(describe(configuration))")
            // A finished game refuses everything and keeps its state.
            let refused = engine.apply(.dart(.treble(20))) == .rejected(.gameFinished) && engine.apply(.endTurn) == .rejected(.gameFinished)
            failures.check(refused && engine.snapshot == end, "a finished game took an input: \(describe(configuration))")
        }
        #expect(failures.isEmpty, "\(failures.report)")
        #expect(bounded > 0 && !reasons.isEmpty, "no game of \(game) had a round limit")
    }

    // MARK: Corrections replay the journal (GAMES.md §2.5)

    /// `replaceDart` and `removeDart` edit the journal and replay it: the state is the one of a game played
    /// directly with the edited journal, minus the darts that the replay refuses.
    @Test(arguments: CommonPlayout.deliveredGames)
    func corrections_giveTheStateOfTheEditedJournal(_ game: GameID) throws {
        let descriptor = try CommonPlayout.descriptor(of: game)
        var random = SeededRandom(seed: CommonPlayout.seed(game, 14))
        var failures = CommonPlayout.Failures()
        var applied = 0
        for _ in 0..<CommonPropertyTests.journalCount {
            var match = try CommonPlayout.randomMatch(descriptor, &random)
            CommonPlayout.playForward(&match, descriptor, &random, limit: random.nextInt(below: 60))
            let turn = match.currentTurn
            guard !turn.isEmpty else { continue }
            let index = random.nextInt(below: turn.count)
            let replacement = CommonPlayout.randomDart(descriptor, &random)
            let removing = random.nextInt(below: 3) == 0
            let before = match.entries
            let journal = CommonPlayout.describe(match)
            let edit = removing ? match.removeDart(at: index) : match.replaceDart(at: index, with: replacement.hit, position: replacement.position)
            let described = "\(removing ? "removing" : "replacing by \(replacement.hit)") dart \(index) of the volley of \(journal)"
            failures.check(edit.applied, "not applied: \(described)")
            applied += 1

            // The same edit made by hand on the journal, then played on a new game.
            let start = (before.lastIndex { $0 == .endTurn }).map { $0 + 1 } ?? 0
            var expected = try CommonPlayout.makeMatch(match.configuration)
            var dropped: [Hit] = []
            for (offset, entry) in before.enumerated() {
                guard case .dart(let record) = entry else {
                    expected.endTurn()
                    continue
                }
                var dart = record
                if offset == start + index {
                    if removing { continue }
                    dart.hit = replacement.hit
                    dart.position = replacement.position
                }
                if !expected.throwDart(dart).isAccepted { dropped.append(dart.hit) }
            }
            failures.check(match.snapshot == expected.snapshot, "another state than the edited journal: \(described)")
            failures.check(match.entries.map(\.input) == expected.entries.map(\.input), "another journal: \(described)")
            failures.check(edit.dropped.map(\.hit) == dropped, "other darts dropped: \(described)")
            failures.record(CommonPlayout.snapshotViolations(match), described)
            // A dart of the current turn keeps its identity through a correction (ARCHITECTURE.md §4.8).
            if !removing {
                failures.check(match.currentTurn.count > index && match.currentTurn[index].id == turn[index].id,
                               "the corrected dart lost its id: \(described)")
            }
        }
        #expect(failures.isEmpty, "\(failures.report)")
        #expect(applied > CommonPropertyTests.journalCount / 10)
    }

    // MARK: Recorded position (GAMES.md §2.2, §2.13)

    /// "Same bed, same effect": in a game that does not depend on the position, adding, removing or changing
    /// a recorded position changes no state, no event and no rank.
    @Test(arguments: CommonPlayout.deliveredGames)
    func position_isIgnoredByAGameThatDoesNotDependOnIt(_ game: GameID) throws {
        let descriptor = try CommonPlayout.descriptor(of: game)
        guard !descriptor.dependsOnPosition else { return }
        var random = SeededRandom(seed: CommonPlayout.seed(game, 15))
        let odd: [BoardPoint] = [.centre, BoardPoint(x: .nan, y: .nan), BoardPoint(x: .infinity, y: 12), BoardPoint(x: -5_000, y: 5_000)]
        var failures = CommonPlayout.Failures()
        for _ in 0..<60 {
            let configuration = CommonPlayout.randomConfiguration(descriptor, &random)
            var plain = try CommonPlayout.makeMatch(configuration)
            var placed = try CommonPlayout.makeMatch(configuration)
            for _ in 0..<80 where plain.phase != .finished {
                if plain.phase == .turnComplete || random.nextInt(below: 10) == 0 {
                    failures.check(plain.endTurn() == placed.endTurn(), "endTurn differs: \(CommonPlayout.describe(placed))")
                } else {
                    let hit = CommonPlayout.randomHit(&random)
                    let position: BoardPoint
                    switch random.nextInt(below: 4) {
                    case 0: position = odd[random.nextInt(below: odd.count)]
                    default: position = BoardPoint(x: Double(random.nextInt(below: 3601) - 1800) / 10,
                                                   y: Double(random.nextInt(below: 3601) - 1800) / 10)
                    }
                    let keyed = plain.effectKey(for: hit) == plain.effectKey(for: hit, position: position)
                    let same = plain.throwDart(DartRecord(hit: hit)) == placed.throwDart(DartRecord(hit: hit, position: position))
                    failures.check(keyed && same, "\(hit) with the position (\(position.x), \(position.y)) differs: \(CommonPlayout.describe(placed))")
                }
                failures.check(plain.snapshot == placed.snapshot, "the position changed the state: \(CommonPlayout.describe(placed))")
            }
        }
        #expect(failures.isEmpty, "\(failures.report)")
    }
}
