import Testing
import DartCore
import DartGames
import DartTestSupport

/// Review of the common suites of lot G1: their checks can fail (each rule of `CommonPlayout.snapshotViolations`
/// and `inputViolations` is fed a broken value and must report it), they run on the games of lots G1 and G2,
/// and the effect-key property holds in its strong form (same events and same highlights afterwards too).
@Suite struct CommonReviewTests {
    /// The journal as a vector writes it: "T20 S5 | MISS".
    static func journal(_ match: GameMatch) -> String {
        match.entries.map { entry in
            if case .dart(let record) = entry { return record.hit.notation }
            return "|"
        }.joined(separator: " ")
    }

    private let registry = GameRegistry.standard

    /// The parameterized common tests iterate `CommonPlayout.deliveredGames`: an empty or short list would make
    /// them pass without checking anything. The six games of lots G1 and G2 are in it.
    @Test func theCommonSuitesRunOnTheGamesOfLotsG1AndG2() {
        let games: Set<GameID> = [.x01, .cricket, .highScore, .killer, .shanghai, .aroundTheClock]
        #expect(games.isSubset(of: Set(CommonPlayout.deliveredGames)))
    }

    /// Every rule of `snapshotViolations` reports a snapshot broken on purpose, and none reports a sound one.
    @Test func snapshotViolations_reportEveryBrokenRule() throws {
        let configuration = GameConfiguration(gameID: .killer, options: ["level": "hard", "maxRounds": 3],
                                              players: testPlayers(3), seed: 1)
        var match = try CommonPlayout.makeMatch(configuration)
        match.play("S11")
        let sound = match.snapshot
        #expect(CommonPlayout.snapshotViolations(sound, of: configuration) == [])
        #expect(CommonPlayout.snapshotViolations(match) == [])

        var breaks: [(String, (inout GameSnapshot) -> Void)] = []
        breaks.append(("game id", { $0.gameID = .cricket }))
        breaks.append(("missing row", { $0.players.removeLast() }))
        breaks.append(("missing rank", { $0.ranks.removeLast() }))
        breaks.append(("row of another player", { $0.players[1].player = 0 }))
        breaks.append(("row rank", { $0.players[0].rank = 3 }))
        breaks.append(("ranks not shared", { $0.ranks = [1, 3, 3]; for i in 0..<3 { $0.players[i].rank = $0.ranks[i] } }))
        breaks.append(("nobody first", { $0.ranks = [2, 2, 2]; for i in 0..<3 { $0.players[i].rank = 2 } }))
        breaks.append(("eliminated before alive", { $0.players[0].isEliminated = true }))
        breaks.append(("everyone eliminated", { for i in 0..<3 { $0.players[i].isEliminated = true } }))
        breaks.append(("last player standing with three alive", { $0.phase = .finished; $0.finishReason = .lastPlayerStanding }))
        breaks.append(("finished without reason", { $0.phase = .finished }))
        breaks.append(("reason without the end", { $0.finishReason = .victory }))
        breaks.append(("current player", { $0.currentPlayer = 3 }))
        breaks.append(("round 0", { $0.round = 0 }))
        breaks.append(("beyond the limit", { $0.round = 4 }))
        breaks.append(("capacity", { $0.turn.capacity = 4 }))
        breaks.append(("four darts", { $0.turn.darts += Array(repeating: DartSlot(hit: .miss), count: 3) }))
        breaks.append(("throwing after three", { $0.turn.darts += Array(repeating: DartSlot(hit: .miss), count: 2) }))
        breaks.append(("volley after the round limit", { $0.phase = .finished; $0.finishReason = .roundLimit; $0.highlights = [] }))
        breaks.append(("highlights once finished", { $0.phase = .finished; $0.finishReason = .victory; $0.turn.darts = [] }))
        breaks.append(("outcome before the end", { $0.outcome = LocalizedText(verbatim: "x") }))
        breaks.append(("title before the end", { $0.winnerTitle = LocalizedText(verbatim: "x") }))
        for (name, change) in breaks {
            var broken = sound
            change(&broken)
            #expect(!CommonPlayout.snapshotViolations(broken, of: configuration).isEmpty, "\(name) not reported")
        }
    }

    /// Every rule of `inputViolations` reports events or outcomes broken on purpose, and accepts the real ones.
    @Test func inputViolations_reportEveryBrokenRule() throws {
        var match = try registry.match(.x01, ["maxRounds": 1], players: 2)
        let start = match.snapshot
        let dart = match.throwDart(DartRecord(hit: .treble(20)))
        let afterDart = match.snapshot
        #expect(CommonPlayout.inputViolations(.dart(.treble(20)), dart, before: start, after: afterDart) == [])
        match.play("T20")
        let twoDarts = match.snapshot
        let third = match.throwDart(DartRecord(hit: .treble(20)))
        let closed = match.snapshot
        #expect(CommonPlayout.inputViolations(.dart(.treble(20)), third, before: twoDarts, after: closed) == [])
        let end = match.endTurn()
        let next = match.snapshot
        #expect(CommonPlayout.inputViolations(.endTurn, end, before: closed, after: next) == [])
        match.play("S1")
        let open = match.snapshot
        let final = match.endTurn()
        #expect(CommonPlayout.inputViolations(.endTurn, final, before: open, after: match.snapshot) == [])

        let registered = GameEvent.dartRegistered(player: 0, hit: .treble(20))
        let cases: [(String, GameInput, InputOutcome, GameSnapshot, GameSnapshot)] = [
            ("no dartRegistered", .dart(.treble(20)), .accepted([]), start, afterDart),
            ("dartRegistered twice", .dart(.treble(20)), .accepted([registered, registered]), start, afterDart),
            ("dart accepted once closed", .dart(.treble(20)), .accepted([registered]), closed, closed),
            ("dart not in the volley", .dart(.treble(20)), .accepted([registered]), start, start),
            ("turn closed without turnCompleted", .dart(.treble(20)), dart, twoDarts, closed),
            ("turnCompleted while still throwing", .dart(.treble(20)), .accepted([registered, .turnCompleted(player: 0)]), start, afterDart),
            ("the round limit on a dart", .dart(.single(1)), .accepted([.dartRegistered(player: 1, hit: .single(1)),
                                                                        .gameFinished(reason: .roundLimit)]), open, match.snapshot),
            ("refused while throwing", .dart(.treble(20)), .rejected(.turnComplete), start, start),
            ("refused with the wrong reason", .dart(.treble(20)), .rejected(.gameFinished), closed, closed),
            ("a refused input changed the state", .endTurn, .rejected(.turnComplete), closed, next),
            ("endTurn without turnStarted", .endTurn, .accepted([.turnCompleted(player: 0)]), closed, next),
            ("endTurn closing a closed turn", .endTurn, .accepted([.turnCompleted(player: 0)] + end.events), closed, next),
            ("dartRegistered on endTurn", .endTurn, .accepted([registered] + end.events), closed, next),
        ]
        for (name, input, outcome, before, after) in cases {
            #expect(!CommonPlayout.inputViolations(input, outcome, before: before, after: after).isEmpty, "\(name) not reported")
        }
    }

    /// ARCHITECTURE.md §4.8 in its strong form: two darts of the same effect key, followed by the same inputs,
    /// give the same EVENTS for every input that follows, and the same highlights, current player and round as
    /// well as the same facts, phase and ranks (`CommonPropertyTests` compares the last four only). A rule that
    /// kept a per-turn value out of its facts would announce another total or draw another zone. On every
    /// delivered game; for a position-dependent game the two darts share their position (GAMES.md §2.13).
    @Test(arguments: CommonPlayout.deliveredGames)
    func sameEffectKey_sameEventsAndSameBoardAfterwards(_ game: GameID) throws {
        let descriptor = try CommonPlayout.descriptor(of: game)
        var compared = 0
        var failures = CommonPlayout.Failures()
        for index in 0..<150 {
            var random = SeededRandom(seed: CommonPlayout.seed(game, 7_000 &+ UInt64(index)))
            var match = try CommonPlayout.randomMatch(descriptor, &random)
            CommonPlayout.playForward(&match, descriptor, &random, limit: random.nextInt(below: 80))
            while match.phase != .throwing && match.canUndo { match.undo() }
            guard match.phase == .throwing else { continue }
            let position = CommonPlayout.randomPosition(descriptor, &random)
            let groups = Dictionary(grouping: Hit.all) { match.effectKey(for: $0, position: position) }.values
                .filter { $0.count >= 2 }.sorted { $0[0].notation < $1[0].notation }
            guard !groups.isEmpty else { continue }
            let group = groups[random.nextInt(below: groups.count)]
            var first = match, second = match
            first.throwDart(DartRecord(hit: group[0], position: position))
            second.throwDart(DartRecord(hit: group[group.count - 1], position: position))
            for step in 0..<15 where first.phase != .finished {
                let a: InputOutcome, b: InputOutcome
                if first.phase == .turnComplete || random.nextInt(below: 7) == 0 {
                    a = first.endTurn()
                    b = second.endTurn()
                } else {
                    let dart = CommonPlayout.randomDart(descriptor, &random)
                    a = first.throwDart(dart)
                    b = second.throwDart(dart)
                }
                let x = first.snapshot, y = second.snapshot
                failures.check(a == b && x.highlights == y.highlights && x.currentPlayer == y.currentPlayer && x.round == y.round
                               && x.players.map(\.facts) == y.players.map(\.facts) && x.facts == y.facts && x.ranks == y.ranks
                               && x.turn.summary == y.turn.summary && x.turn.hint == y.turn.hint,
                               "\(group[0]) and \(group[group.count - 1]) differ at step \(step) after \(CommonPlayout.describe(match))")
            }
            compared += 1
        }
        #expect(failures.isEmpty, "\(failures.report)")
        #expect(compared > 50)
    }
}
