import Testing
import DartCore
import DartGames
import DartTestSupport

/// Football (GAMES.md §14): the vectors FOO-1 to FOO-7, then the rule paragraphs they do not reach.
@Suite struct FootballTests {
    private let registry = GameRegistry.standard

    private static let rightHalf = [1, 18, 4, 13, 6, 10, 15, 2, 17]
    private static let leftHalf = [19, 7, 16, 8, 11, 14, 9, 12, 5]

    /// An integer fact of every player, in playing order.
    private func ints(_ match: GameMatch, _ name: String) -> [Int] {
        match.players.indices.map { player in
            guard case .int(let value)? = match.fact(player, name) else {
                Issue.record("the fact `\(name)` is an integer")
                return .min
            }
            return value
        }
    }

    private func ball(_ match: GameMatch) -> Int {
        guard case .int(let value)? = match.gameFact("ball") else {
            Issue.record("the game fact `ball` is an integer")
            return .min
        }
        return value
    }

    private func sideGoals(_ match: GameMatch) -> [Int] {
        guard case .ints(let value)? = match.gameFact("sideGoals") else {
            Issue.record("the game fact `sideGoals` is a list")
            return []
        }
        return value
    }

    private func goalsScored(_ match: GameMatch) -> [Int] { ints(match, "goalsScored") }
    private func sides(_ match: GameMatch) -> [Int] { ints(match, "side") }
    private func zones(_ match: GameMatch, _ role: HighlightRole) -> [BoardZone] {
        match.snapshot.highlights.filter { $0.role == role }.map(\.zone)
    }

    // MARK: Vectors (GAMES.md §14.9)

    @Test func foo1_duelPushPushedBackScoreKickOff() throws {
        var match = try registry.match(.football, players: 2)
        #expect(sides(match) == [0, 1] && match.gameFact("step") == [1, 1] && match.gameFact("goalDistance") == 4)
        #expect(ball(match) == 0 && sideGoals(match) == [0, 0])
        #expect(zones(match, .target) == Self.rightHalf.map { BoardZone.sector($0) } + [.bull])
        #expect(zones(match, .avoid) == Self.leftHalf.map { BoardZone.sector($0) })
        #expect(match.snapshot.highlights.count == 19)

        var outcomes = match.play("S6, D10, MISS")
        #expect(ball(match) == 3 && match.phase == .turnComplete)
        #expect(outcomes[0].events == [.dartRegistered(player: 0, hit: .single(6)), .ballMoved(player: 0, by: 1, ball: 1)])
        #expect(outcomes[1].events == [.dartRegistered(player: 0, hit: .double(10)), .ballMoved(player: 0, by: 2, ball: 3)])
        #expect(outcomes[2].events == [.dartRegistered(player: 0, hit: .miss), .noEffect(player: 0), .turnCompleted(player: 0)])

        // S20 lies on the halfway line: no effect. The ball ends in the half that A defends.
        outcomes = match.play("| S11, S20, T14")
        #expect(ball(match) == -1 && match.snapshot.ranks == [2, 1])
        #expect(outcomes[2].events == [.dartRegistered(player: 1, hit: .single(20)), .noEffect(player: 1)])
        #expect(outcomes[3].events == [.dartRegistered(player: 1, hit: .treble(14)), .ballMoved(player: 1, by: -3, ball: -1),
                                       .turnCompleted(player: 1)])
        // Highlights of J2 (side B): mirrored.
        #expect(zones(match, .target) == Self.leftHalf.map { BoardZone.sector($0) } + [.bull])
        #expect(zones(match, .avoid) == Self.rightHalf.map { BoardZone.sector($0) })

        match.play("| S13, T4")
        #expect(ball(match) == 3 && match.phase == .throwing)

        outcomes = match.play("S2")
        #expect(sideGoals(match) == [1, 0] && match.fact(0, "goalsScored") == 1 && ball(match) == 0)
        #expect(match.phase == .turnComplete && match.snapshot.ranks == [1, 2])
        #expect(outcomes[0].events == [.dartRegistered(player: 0, hit: .single(2)), .ballMoved(player: 0, by: 1, ball: 4),
                                       .goalScored(player: 0, side: 0, goals: 1, ownGoal: false),
                                       .turnCompleted(player: 0)])
    }

    @Test func foo2_wrongHalfAndOwnGoal() throws {
        var match = try registry.match(.football, players: 2)
        var outcomes = match.play("S11, S9")
        #expect(ball(match) == -2)
        outcomes += match.play("D14")
        #expect(sideGoals(match) == [0, 1] && goalsScored(match) == [0, 0] && ball(match) == 0)
        #expect(match.snapshot.ranks == [2, 1] && match.phase == .turnComplete)
        #expect(outcomes[2].events == [.dartRegistered(player: 0, hit: .double(14)), .ballMoved(player: 0, by: -2, ball: -4),
                                       .goalScored(player: 0, side: 1, goals: 1, ownGoal: true),
                                       .turnCompleted(player: 0)])
    }

    @Test func foo3_bullBallStoppedOnTheLineVictoryOnGoals() throws {
        var match = try registry.match(.football, ["goalsToWin": 2], players: 2)
        var outcomes = match.play("SB")
        #expect(ball(match) == 2)
        #expect(outcomes[0].events == [.dartRegistered(player: 0, hit: .outerBull), .ballMoved(player: 0, by: 2, ball: 2)])
        outcomes = match.play("S3")
        #expect(outcomes[0].events == [.dartRegistered(player: 0, hit: .single(3)), .noEffect(player: 0)])
        #expect(ball(match) == 2)
        outcomes = match.play("DB")
        #expect(ball(match) == 0 && sideGoals(match) == [1, 0])
        #expect(outcomes[0].events == [.dartRegistered(player: 0, hit: .innerBull),
                                       .goalScored(player: 0, side: 0, goals: 1, ownGoal: false),
                                       .turnCompleted(player: 0)])

        outcomes = match.play("| DB")
        #expect(sideGoals(match) == [1, 1])
        outcomes = match.play("SB")
        #expect(ball(match) == -2)
        #expect(outcomes[0].events == [.dartRegistered(player: 1, hit: .outerBull), .ballMoved(player: 1, by: -2, ball: -2)])
        // Three more steps to the left: the ball stops on the line (-4) and side B scores its second goal.
        outcomes = match.play("T11")
        #expect(match.phase == .finished && match.snapshot.finishReason == .victory)
        #expect(sideGoals(match) == [1, 2] && goalsScored(match) == [1, 2] && ball(match) == 0)
        #expect(match.snapshot.ranks == [2, 1])
        #expect(outcomes[0].events == [.dartRegistered(player: 1, hit: .treble(11)), .ballMoved(player: 1, by: -3, ball: -4),
                                       .goalScored(player: 1, side: 1, goals: 2, ownGoal: false),
                                       .gameFinished(reason: .victory)])
        #expect(match.throwDart(DartRecord(hit: .single(6))) == .rejected(.gameFinished))
        // A game won on a dart keeps its volley (GAMES.md §2.6).
        #expect(match.turnNotation == ["DB", "SB", "T11"] && match.snapshot.turn.darts.count == 3)
    }

    @Test func foo4_sidesAndCompensationByPlayerCount() throws {
        let expected: [(players: Int, sides: [Int], step: FactValue, goalDistance: FactValue)] = [
            (2, [0, 1], [1, 1], 4),
            (3, [0, 1, 0], [1, 2], 8),
            (4, [0, 1, 0, 1], [1, 1], 4),
            (5, [0, 1, 0, 1, 0], [2, 3], 12),
            (6, [0, 1, 0, 1, 0, 1], [1, 1], 4),
            (7, [0, 1, 0, 1, 0, 1, 0], [3, 4], 16),
            (8, [0, 1, 0, 1, 0, 1, 0, 1], [1, 1], 4),
        ]
        for row in expected {
            let match = try registry.match(.football, players: row.players)
            #expect(sides(match) == row.sides, "\(row.players) players")
            #expect(match.gameFact("step") == row.step, "\(row.players) players")
            #expect(match.gameFact("goalDistance") == row.goalDistance, "\(row.players) players")
        }
        let long = try registry.match(.football, ["fieldLength": 6], players: 5)
        #expect(long.gameFact("step") == [2, 3] && long.gameFact("goalDistance") == 18)

        #expect(throws: GameConfigurationError.playerCountOutOfRange(allowed: 2...8, actual: 1)) {
            try registry.match(.football, players: 1)
        }
        #expect(throws: GameConfigurationError.playerCountOutOfRange(allowed: 2...8, actual: 9)) {
            try registry.match(.football, players: 9)
        }
        #expect(throws: GameConfigurationError.invalidOptionValue(key: "fieldLength")) {
            try registry.match(.football, ["fieldLength": 2], players: 2)
        }
        #expect(throws: GameConfigurationError.invalidOptionValue(key: "goalsToWin")) {
            try registry.match(.football, ["goalsToWin": 0], players: 2)
        }
    }

    @Test func foo5_threePlayersTheLonePlayerPushesTwiceAsHard() throws {
        var match = try registry.match(.football, players: 3)
        var outcomes = match.play("S6, S6, S6 | S11, T11, S11")
        // J1 (A, step 1): 3. J2 (B, step 2): −2, −6, −2.
        #expect(ball(match) == -7 && match.snapshot.ranks == [2, 1, 2])
        #expect(outcomes[4].events == [.dartRegistered(player: 1, hit: .single(11)), .ballMoved(player: 1, by: -2, ball: 1)])
        #expect(outcomes[5].events == [.dartRegistered(player: 1, hit: .treble(11)), .ballMoved(player: 1, by: -6, ball: -5)])

        match.play("| D6, S6, S1")
        #expect(match.snapshot.currentPlayer == 2 && match.fact(2, "side") == 0 && ball(match) == -3)

        // Side A plays two turns in a row at the change of round.
        outcomes = match.play("| T6, S6")
        #expect(match.snapshot.currentPlayer == 0 && match.snapshot.round == 2)
        #expect(ball(match) == 1 && match.snapshot.ranks == [1, 3, 1])
    }

    @Test func foo6_roundLimitGoalsThenBallPosition() throws {
        var match = try registry.match(.football, ["maxRounds": 1], players: 4)
        match.play("T6, S6 | MISS ×3 | DB | S11, S11, MISS |")
        #expect(match.phase == .finished && match.snapshot.finishReason == .roundLimit)
        #expect(sideGoals(match) == [2, 0] && goalsScored(match) == [1, 0, 1, 0] && ball(match) == -2)
        // Both players of a side share the rank.
        #expect(match.snapshot.ranks == [1, 3, 1, 3])

        // Level on goals: the ball is in the half that A defends.
        match = try registry.match(.football, ["maxRounds": 1], players: 2)
        match.play("S6, MISS, MISS | S11, S11, MISS |")
        #expect(match.snapshot.finishReason == .roundLimit && sideGoals(match) == [0, 0] && ball(match) == -1)
        #expect(match.snapshot.ranks == [2, 1])

        // A draw.
        match = try registry.match(.football, ["maxRounds": 1], players: 2)
        match.play("S6, MISS, MISS | S11, MISS, MISS |")
        #expect(sideGoals(match) == [0, 0] && ball(match) == 0 && match.snapshot.ranks == [1, 1])
        #expect(match.phase == .finished)
    }

    @Test func foo7_victoryOnAnOwnGoal() throws {
        var match = try registry.match(.football, ["goalsToWin": 1], players: 2)
        let outcomes = match.play("T11, S11")
        #expect(match.phase == .finished && match.snapshot.finishReason == .victory)
        #expect(sideGoals(match) == [0, 1] && goalsScored(match) == [0, 0] && ball(match) == 0)
        #expect(match.snapshot.ranks == [2, 1])
        #expect(outcomes[1].events == [.dartRegistered(player: 0, hit: .single(11)), .ballMoved(player: 0, by: -1, ball: -4),
                                       .goalScored(player: 0, side: 1, goals: 1, ownGoal: true),
                                       .gameFinished(reason: .victory)])
    }

    // MARK: Rule paragraphs beyond the vectors

    /// §14.4: the half that is hit gives the direction, whoever throws; the multiplier gives the distance.
    @Test func football_everyBedMovesTheBallByTheTable() throws {
        for thrower in 0..<2 {
            for hit in Hit.all {
                var match = try registry.match(.football, ["fieldLength": 8], players: 2)
                if thrower == 1 { match.play("|") }
                let outcome = match.throwDart(DartRecord(hit: hit))
                let registered = GameEvent.dartRegistered(player: thrower, hit: hit)
                let attack = thrower == 0 ? 1 : -1
                var move: Int?
                if hit.bed == .outerBull {
                    move = 2 * attack
                } else if let number = hit.number, Self.rightHalf.contains(number) {
                    move = hit.multiplier
                } else if let number = hit.number, Self.leftHalf.contains(number) {
                    move = -hit.multiplier
                }
                if hit.bed == .innerBull {
                    #expect(outcome.events == [registered, .goalScored(player: thrower, side: thrower, goals: 1, ownGoal: false)])
                    #expect(ball(match) == 0 && match.fact(thrower, "goalsScored") == 1)
                } else if let move {
                    #expect(outcome.events == [registered, .ballMoved(player: thrower, by: move, ball: move)], "\(hit)")
                    #expect(ball(match) == move)
                } else {
                    // MISS, and the 20 and the 3 whatever the ring.
                    #expect(hit.isMiss || hit.number == 20 || hit.number == 3)
                    #expect(outcome.events == [registered, .noEffect(player: thrower)], "\(hit)")
                    #expect(ball(match) == 0)
                }
            }
        }
    }

    /// §14.1: with unequal sides a step is worth the size of the other side, for every ring and for the bull.
    @Test func football_stepsOfUnequalSides() throws {
        // Five players: step 2 for A, 3 for B, goal lines at ±12.
        var match = try registry.match(.football, players: 5)
        var outcomes = match.play("S6, D6, SB")
        #expect(outcomes.map { $0.events[1] } == [.ballMoved(player: 0, by: 2, ball: 2), .ballMoved(player: 0, by: 4, ball: 6),
                                                  .ballMoved(player: 0, by: 4, ball: 10)])
        outcomes = match.play("| SB, T6, S11")
        // J2 (B): the bull pushes 2 × 3 to the left; a treble in the wrong half pushes 9 to the right, clamped at +12.
        #expect(outcomes[1].events == [.dartRegistered(player: 1, hit: .outerBull), .ballMoved(player: 1, by: -6, ball: 4)])
        #expect(outcomes[2].events == [.dartRegistered(player: 1, hit: .treble(6)), .ballMoved(player: 1, by: 9, ball: 12),
                                       .goalScored(player: 1, side: 0, goals: 1, ownGoal: true)])
        #expect(outcomes[3].events == [.dartRegistered(player: 1, hit: .single(11)), .ballMoved(player: 1, by: -3, ball: -3),
                                       .turnCompleted(player: 1)])
        #expect(sideGoals(match) == [1, 0] && goalsScored(match) == [0, 0, 0, 0, 0])
        #expect(match.snapshot.ranks == [1, 4, 1, 4, 1])

        // Seven players: step 3 for A, 4 for B, goal lines at ±16.
        match = try registry.match(.football, players: 7)
        outcomes = match.play("T6, MISS, MISS | T11")
        #expect(outcomes[0].events[1] == .ballMoved(player: 0, by: 9, ball: 9))
        #expect(outcomes[4].events[1] == .ballMoved(player: 1, by: -12, ball: -3))
    }

    /// §14.5: a goal does not shorten the turn; the player goes on from the centre spot.
    @Test func football_aGoalDoesNotCloseTheTurn() throws {
        var match = try registry.match(.football, players: 2)
        let outcomes = match.play("DB, T6")
        #expect(outcomes[0].events == [.dartRegistered(player: 0, hit: .innerBull),
                                       .goalScored(player: 0, side: 0, goals: 1, ownGoal: false)])
        #expect(match.phase == .throwing && ball(match) == 3 && sideGoals(match) == [1, 0])
        // Two goals in one turn, the second by the ball.
        let third = match.play("S6")
        #expect(third[0].events == [.dartRegistered(player: 0, hit: .single(6)), .ballMoved(player: 0, by: 1, ball: 4),
                                    .goalScored(player: 0, side: 0, goals: 2, ownGoal: false), .turnCompleted(player: 0)])
        #expect(match.fact(0, "goalsScored") == 2 && ball(match) == 0)
    }

    /// §14.4: DB scores for the thrower's side wherever the ball is, and an own goal is credited to no player.
    @Test func football_innerBullScoresFromAnywhere() throws {
        var match = try registry.match(.football, players: 2)
        match.play("S11, S11, S11 | MISS, MISS")
        #expect(ball(match) == -3)
        let outcomes = match.play("DB")
        #expect(outcomes[0].events == [.dartRegistered(player: 1, hit: .innerBull),
                                       .goalScored(player: 1, side: 1, goals: 1, ownGoal: false), .turnCompleted(player: 1)])
        #expect(ball(match) == 0 && sideGoals(match) == [0, 1] && goalsScored(match) == [0, 1])
    }

    /// §14.6: the first side at `goalsToWin` wins on the dart, whatever the option.
    @Test func football_victoryAtGoalsToWin() throws {
        for goals in [1, 3, 9] {
            var match = try registry.match(.football, ["goalsToWin": .int(goals), "maxRounds": .null], players: 2)
            #expect(match.snapshot.roundLimit == nil)
            var last: InputOutcome?
            for _ in 0..<(3 * goals) where match.phase != .finished {
                if match.phase == .turnComplete { match.play("| MISS ×3 |") }
                last = match.throwDart(DartRecord(hit: .innerBull))
            }
            #expect(match.phase == .finished && match.snapshot.finishReason == .victory)
            #expect(sideGoals(match) == [goals, 0] && match.fact(0, "goalsScored") == .int(goals))
            #expect(last?.events == [.dartRegistered(player: 0, hit: .innerBull),
                                     .goalScored(player: 0, side: 0, goals: goals, ownGoal: false),
                                     .gameFinished(reason: .victory)])
        }
    }

    /// §14.2: `maxRounds` is the round limit, 10 by default, none when nil.
    @Test func football_roundLimit() throws {
        #expect(try registry.match(.football, players: 2).snapshot.roundLimit == 10)
        #expect(try registry.match(.football, ["maxRounds": .null], players: 2).snapshot.roundLimit == nil)
        var match = try registry.match(.football, ["maxRounds": 2], players: 3)
        match.play("| | | | |")
        #expect(match.phase == .throwing && match.snapshot.round == 2 && match.snapshot.currentPlayer == 2)
        #expect(match.endTurn().events == [.turnCompleted(player: 2), .gameFinished(reason: .roundLimit)])
        #expect(match.snapshot.ranks == [1, 1, 1] && match.snapshot.turn.darts.isEmpty)
    }

    /// §14.6: during the game the ranks follow the goals first, then the half where the ball lies.
    @Test func football_provisionalRanks() throws {
        var match = try registry.match(.football, players: 4)
        #expect(match.snapshot.ranks == [1, 1, 1, 1])
        match.play("S6")
        #expect(match.snapshot.ranks == [1, 3, 1, 3])
        match.play("S11, S11")
        #expect(match.snapshot.ranks == [3, 1, 3, 1])
        match.play("| DB, S6, S6 | S11, S11, S11")
        #expect(sideGoals(match) == [0, 1] && ball(match) == -1 && match.snapshot.ranks == [3, 1, 3, 1])
        // Goals come first: the ball in the half that B defends does not put A ahead of B's goal.
        match.play("| S6, S6, S6")
        #expect(sideGoals(match) == [0, 1] && ball(match) == 2 && match.snapshot.ranks == [3, 1, 3, 1])
        // Level on goals again: the ball decides.
        match.play("| DB")
        #expect(sideGoals(match) == [1, 1] && ball(match) == 0 && match.snapshot.ranks == [1, 1, 1, 1])
        match.play("S6")
        #expect(match.snapshot.ranks == [1, 3, 1, 3])
    }

    // MARK: Undo, corrections, replay (GAMES.md §2.5)

    @Test func football_undoAndCorrections() throws {
        var match = try registry.match(.football, ["goalsToWin": 1], players: 2)
        match.play("T11, S11")
        #expect(match.phase == .finished)
        // Undoing the winning dart reopens the game.
        match.undo()
        #expect(match.phase == .throwing && ball(match) == -3 && sideGoals(match) == [0, 0])
        match.play("S11")
        // The winning dart stays correctable: the own goal becomes a move the other way and the turn goes on.
        let edit = match.replaceDart(at: 1, with: .single(6))
        #expect(edit.applied && match.phase == .throwing && ball(match) == -2 && match.snapshot.finishReason == nil)
        match.play("DB")
        #expect(match.phase == .finished && sideGoals(match) == [1, 0] && match.snapshot.ranks == [1, 2])
        // A correction that makes the first dart the winning one drops the rest of the turn.
        let early = match.replaceDart(at: 0, with: .innerBull)
        #expect(early.dropped.map(\.hit) == [.single(6), .innerBull] && match.turnNotation == ["DB"])
        #expect(match.phase == .finished && match.fact(0, "goalsScored") == 1)
        match.removeDart(at: 0)
        #expect(match.phase == .throwing && match.entries.isEmpty && sideGoals(match) == [0, 0])
    }

    @Test func football_replayIsDeterministic() throws {
        for players in [2, 3, 5, 8] {
            var match = try registry.match(.football, ["fieldLength": 3, "goalsToWin": 4, "maxRounds": 6], players: players)
            var random = SeededRandom(seed: UInt64(players))
            var snapshots: [GameSnapshot] = []
            while match.phase != .finished {
                if match.phase == .turnComplete || random.nextInt(below: 9) == 0 {
                    match.endTurn()
                } else {
                    match.throwDart(DartRecord(hit: Hit.all[random.nextInt(below: Hit.all.count)]))
                }
                snapshots.append(match.snapshot)
                // The ball rests strictly between the goal lines, and both players of a side share a rank.
                guard case .int(let distance)? = match.gameFact("goalDistance") else {
                    Issue.record("goalDistance is an integer")
                    return
                }
                #expect(abs(ball(match)) < distance)
                let ranks = match.snapshot.ranks
                #expect((0..<players).allSatisfy { ranks[$0] == ranks[$0 % 2] })
            }
            let restored = try registry.restoreMatch(match.record)
            #expect(restored.snapshot == match.snapshot && restored.entries == match.entries)
            for expected in snapshots.dropLast().reversed() {
                match.undo()
                #expect(match.snapshot == expected)
            }
        }
    }

    /// Everything a later dart depends on is in the facts (ARCHITECTURE.md §4.7): two darts with the same
    /// `effectKey`, followed by the same inputs, lead to the same facts, ranks and events.
    @Test func football_sameEffectKeySameFuture() throws {
        var pairs = 0
        for seed in 0..<60 as Range<UInt64> {
            var random = SeededRandom(seed: seed)
            var match = try registry.match(.football, ["fieldLength": 3, "goalsToWin": 2, "maxRounds": 4],
                                           players: 2 + random.nextInt(below: 4))
            for _ in 0..<random.nextInt(below: 12) where match.phase != .finished {
                if match.phase == .turnComplete || random.nextInt(below: 6) == 0 { match.endTurn() }
                else { match.throwDart(DartRecord(hit: Hit.all[random.nextInt(below: Hit.all.count)])) }
            }
            guard match.phase == .throwing else { continue }
            let groups = Dictionary(grouping: Hit.all) { match.effectKey(for: $0) }
            // MISS, the 20 and the 3 form one group; a single of the right half and one of the left never do.
            #expect(match.effectKey(for: .miss) == match.effectKey(for: .treble(20)))
            #expect(match.effectKey(for: .miss) == match.effectKey(for: .double(3)))
            #expect(match.effectKey(for: .single(6)) == match.effectKey(for: .single(17)))
            #expect(match.effectKey(for: .single(6)) != match.effectKey(for: .single(11)))
            for group in groups.values where group.count > 1 {
                var first = match, second = match
                first.throwDart(DartRecord(hit: group[0]))
                second.throwDart(DartRecord(hit: group[group.count - 1]))
                pairs += 1
                for _ in 0..<12 where first.phase != .finished {
                    let hit = Hit.all[random.nextInt(below: Hit.all.count)]
                    let confirm = first.phase != .throwing || random.nextInt(below: 5) == 0
                    let a = confirm ? first.endTurn() : first.throwDart(DartRecord(hit: hit))
                    let b = confirm ? second.endTurn() : second.throwDart(DartRecord(hit: hit))
                    #expect(a == b)
                    #expect(first.snapshot.players.map(\.facts) == second.snapshot.players.map(\.facts))
                    #expect(first.snapshot.facts == second.snapshot.facts)
                    #expect(first.snapshot.ranks == second.snapshot.ranks && first.phase == second.phase)
                }
            }
        }
        #expect(pairs > 100)
    }

    /// The rule is as strict as the schema when it is built without the kernel: a lone player can never make
    /// the compensation divide by zero.
    @Test func football_ruleBuiltOnItsOwn() throws {
        var random = SeededRandom(seed: 0)
        func configuration(_ options: GameOptions, players: Int = 2) -> GameConfiguration {
            GameConfiguration(gameID: .football, options: options, players: testPlayers(players), seed: 0)
        }
        for count in [0, 1, 9] {
            #expect(throws: GameConfigurationError.playerCountOutOfRange(allowed: 2...8, actual: count)) {
                _ = try FootballRules(configuration: configuration([:], players: count), random: &random)
            }
        }
        #expect(throws: GameConfigurationError.invalidOptionValue(key: "fieldLength")) {
            _ = try FootballRules(configuration: configuration(["fieldLength": 9]), random: &random)
        }
        #expect(throws: GameConfigurationError.invalidOptionValue(key: "goalsToWin")) {
            _ = try FootballRules(configuration: configuration(["goalsToWin": 10]), random: &random)
        }
        #expect(throws: GameConfigurationError.invalidOptionValue(key: "maxRounds")) {
            _ = try FootballRules(configuration: configuration(["maxRounds": 0]), random: &random)
        }
        let rules = try FootballRules(configuration: configuration([:], players: 3), random: &random)
        #expect(rules.roundLimit == 10 && rules.ranks() == [1, 1, 1])
        #expect(random == SeededRandom(seed: 0))
    }

    // MARK: Presentation (GAMES.md §14.7, ARCHITECTURE.md §5.6)

    @Test func football_scoreboard() throws {
        var match = try registry.match(.football, players: 3)
        #expect(match.snapshot.title == LocalizedText(verbatim: "Football") && match.snapshot.variant == nil)
        #expect(match.snapshot.objective == LocalizedText(verbatim: "A 0 – 0 B"))
        // Three players: the goal lines are 8 steps away, the gauge runs over 16.
        #expect(match.snapshot.players.map(\.meter) == Array(repeating: Meter(value: 8, maximum: 16, style: .bar), count: 3))
        #expect(match.snapshot.players.map { $0.badges.map(\.text) } == ["A", "B", "A"].map { [LocalizedText(verbatim: $0)] })
        #expect(match.snapshot.winnerTitle == nil && match.snapshot.outcome == nil)

        match.play("DB, S6, S6 | S11")
        #expect(match.snapshot.objective == LocalizedText(verbatim: "A 1 – 0 B"))
        #expect(ball(match) == 0)
        match.play("S11")
        // Progress of the ball towards the goal each side attacks: goalDistance + ball for A, goalDistance − ball for B.
        #expect(match.snapshot.players.map { $0.meter?.value } == [6, 10, 6])
        #expect(match.snapshot.players.map(\.primary) == [
            ScoreValue(1, unit: LocalizedText(fr: "but", en: "goal")),
            ScoreValue(0, unit: LocalizedText(fr: "but", en: "goals")),
            ScoreValue(1, unit: LocalizedText(fr: "but", en: "goal")),
        ])
        #expect(match.snapshot.players.map(\.detail) == [
            LocalizedText(fr: "1 but marqué", en: "1 goal scored"),
            LocalizedText(fr: "0 but marqué", en: "0 goals scored"),
            LocalizedText(fr: "0 but marqué", en: "0 goals scored"),
        ])
        #expect(match.snapshot.players[1].facts == ["side": 1, "goalsScored": 0])
        #expect(match.snapshot.facts == ["ball": -2, "sideGoals": [1, 0], "goalDistance": 8, "step": [1, 2]])
        #expect(match.snapshot.turn.darts.map { $0.caption?.tone } == [.positive, .positive])
        #expect(match.snapshot.turn.darts.map { $0.caption?.text } == [LocalizedText(verbatim: "← 2"), LocalizedText(verbatim: "← 2")])

        // Captions of the four kinds of dart, seen by a player of side A.
        var captions = try registry.match(.football, players: 2)
        captions.play("S6, S11, MISS")
        #expect(captions.snapshot.turn.darts.map { $0.caption } == [
            DartCaption(LocalizedText(verbatim: "→ 1"), tone: .positive),
            DartCaption(LocalizedText(verbatim: "← 1"), tone: .negative),
            DartCaption(LocalizedText(fr: "Sans effet", en: "No effect"), tone: .neutral),
        ])
        captions.play("| | DB, T11, D11")
        #expect(captions.snapshot.turn.darts.map { $0.caption } == [
            DartCaption(LocalizedText(fr: "But !", en: "Goal!"), tone: .positive),
            DartCaption(LocalizedText(verbatim: "← 3"), tone: .negative),
            DartCaption(LocalizedText(fr: "Contre son camp", en: "Own goal"), tone: .negative),
        ])
    }

    /// §14.7: the winner is a side, not a player: the game gives the headline of the results.
    @Test func football_winnerTitle() throws {
        var match = try registry.match(.football, ["goalsToWin": 1], players: 4)
        match.play("T11")
        // Never before the end.
        #expect(match.snapshot.winnerTitle == nil)
        match.play("S11")
        #expect(match.snapshot.winnerTitle == LocalizedText(fr: "Le camp B gagne", en: "Side B wins"))
        #expect(match.snapshot.winners == [1, 3] && match.snapshot.highlights.isEmpty)
        #expect(match.snapshot.outcome == LocalizedText(fr: "Score final : A 0 – 1 B.", en: "Final score: A 0 – 1 B."))

        match = try registry.match(.football, ["maxRounds": 1], players: 4)
        match.play("T6, S6 | MISS ×3 | DB | S11, S11, MISS |")
        #expect(match.snapshot.winnerTitle == LocalizedText(fr: "Le camp A gagne", en: "Side A wins"))
        #expect(match.snapshot.players.map(\.resultLines) == [
            [LocalizedText(fr: "1 but marqué", en: "1 goal scored")], [LocalizedText(fr: "0 but marqué", en: "0 goals scored")],
            [LocalizedText(fr: "1 but marqué", en: "1 goal scored")], [LocalizedText(fr: "0 but marqué", en: "0 goals scored")],
        ])

        // Level on goals: the side that holds the ball in the opposite half wins.
        match = try registry.match(.football, ["maxRounds": 1], players: 2)
        match.play("S6, MISS, MISS | S11, S11, MISS |")
        #expect(match.snapshot.winnerTitle == LocalizedText(fr: "Le camp B gagne", en: "Side B wins"))
        #expect(match.snapshot.outcome == LocalizedText(
            fr: "A 0 – 0 B : le camp B tient le ballon dans la moitié adverse.",
            en: "A 0 – 0 B: side B holds the ball in the opposite half."))

        match = try registry.match(.football, ["maxRounds": 1], players: 2)
        match.play("S6, MISS, MISS | S11, MISS, MISS |")
        #expect(match.snapshot.winnerTitle == LocalizedText(fr: "Match nul", en: "It's a draw"))
        #expect(match.snapshot.winners == [0, 1])
        #expect(match.snapshot.outcome == LocalizedText(fr: "A 0 – 0 B, ballon au centre.", en: "A 0 – 0 B, ball on the centre spot."))
    }
}
