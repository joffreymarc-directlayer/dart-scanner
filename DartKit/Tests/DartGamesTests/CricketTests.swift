import Testing
import DartCore
import DartGames
import DartTestSupport

/// Cricket (GAMES.md §4): the vectors CRI-1 to CRI-10 of §4.9, then every rule paragraph that no vector covers.
/// In facts and events the bull as a target is written 25 (ARCHITECTURE.md §4.5, §5.5).
@Suite struct CricketTests {
    private let registry = GameRegistry.standard
    private static let bull = 25
    private static let normalTargets = [20, 19, 18, 17, 16, 15, 25]

    /// `J<player + 1>.marks[target]`.
    private func marks(_ match: GameMatch, _ player: PlayerIndex, _ target: Int) -> Int? {
        guard case .map(let map)? = match.fact(player, "marks") else { return nil }
        return map[target]
    }

    private func points(_ match: GameMatch) -> [FactValue?] {
        match.snapshot.players.indices.map { match.fact($0, "points") }
    }

    private func closedCounts(_ match: GameMatch) -> [FactValue?] {
        match.snapshot.players.indices.map { match.fact($0, "closedCount") }
    }

    /// (zone, role) of every highlight, in the order of the snapshot.
    private func roles(_ match: GameMatch) -> [BoardZone: HighlightRole] {
        Dictionary(uniqueKeysWithValues: match.snapshot.highlights.map { ($0.zone, $0.role) })
    }

    // MARK: Vectors (GAMES.md §4.9)

    @Test func cri1_closeScoreDeadTarget() throws {
        var match = try registry.match(.cricket, ["scoring": "standard"], players: 2)
        let outcomes = match.play("T20, S20, D20 | T20, T20, S19")
        #expect(marks(match, 0, 20) == 3 && match.fact(0, "points") == 60)
        #expect(marks(match, 1, 20) == 3 && marks(match, 1, 19) == 1 && match.fact(1, "points") == 0)
        #expect(match.phase == .turnComplete && match.snapshot.currentPlayer == 1)
        #expect(outcomes[0].events == [.dartRegistered(player: 0, hit: .treble(20)), .marksScored(player: 0, target: 20, count: 3),
                                       .targetClosed(player: 0, target: 20)])
        #expect(outcomes[1].events == [.dartRegistered(player: 0, hit: .single(20)), .pointsScored(player: 0, points: 20)])
        #expect(outcomes[2].events == [.dartRegistered(player: 0, hit: .double(20)), .pointsScored(player: 0, points: 40),
                                       .turnCompleted(player: 0)])
        #expect(outcomes[4].events == [.dartRegistered(player: 1, hit: .treble(20)), .marksScored(player: 1, target: 20, count: 3),
                                       .targetClosed(player: 1, target: 20), .targetDead(target: 20)])
        // The second T20 of J2 has no effect: 20 is dead.
        #expect(outcomes[5].events == [.dartRegistered(player: 1, hit: .treble(20)), .noEffect(player: 1)])
        #expect(outcomes[6].events == [.dartRegistered(player: 1, hit: .single(19)), .marksScored(player: 1, target: 19, count: 1),
                                       .turnCompleted(player: 1)])
    }

    @Test func cri2_oneDartClosesThenScores() throws {
        var match = try registry.match(.cricket, ["scoring": "standard"], players: 2)
        let outcomes = match.play("D20, T20, MISS")
        #expect(marks(match, 0, 20) == 3 && match.fact(0, "points") == 40 && match.fact(1, "points") == 0)
        #expect(outcomes[0].events == [.dartRegistered(player: 0, hit: .double(20)), .marksScored(player: 0, target: 20, count: 2)])
        // One closing mark, then two scoring marks: the effects in the order they happen.
        #expect(outcomes[1].events == [.dartRegistered(player: 0, hit: .treble(20)), .marksScored(player: 0, target: 20, count: 1),
                                       .targetClosed(player: 0, target: 20), .pointsScored(player: 0, points: 40)])
        #expect(outcomes[2].events == [.dartRegistered(player: 0, hit: .miss), .noEffect(player: 0), .turnCompleted(player: 0)])
    }

    @Test func cri3_cutThroatWithThree() throws {
        var match = try registry.match(.cricket, ["scoring": "cutThroat"], players: 3)
        let outcomes = match.play("T20, T20, MISS | T20, S20, MISS")
        #expect(marks(match, 0, 20) == 3 && marks(match, 1, 20) == 3 && marks(match, 2, 20) == 0)
        #expect(points(match) == [0, 60, 80])
        // 60 to J2 and J3, then 20 to J3 alone.
        #expect(outcomes[1].events == [.dartRegistered(player: 0, hit: .treble(20)),
                                       .pointsGiven(player: 0, to: [1, 2], pointsEach: 60)])
        #expect(outcomes[4].events == [.dartRegistered(player: 1, hit: .treble(20)), .marksScored(player: 1, target: 20, count: 3),
                                       .targetClosed(player: 1, target: 20)])
        #expect(outcomes[5].events == [.dartRegistered(player: 1, hit: .single(20)), .pointsGiven(player: 1, to: [2], pointsEach: 20)])
    }

    @Test func cri4_bullMarksAndPoints() throws {
        var match = try registry.match(.cricket, ["scoring": "standard"], players: 2)
        let outcomes = match.play("DB, SB, DB")
        #expect(marks(match, 0, Self.bull) == 3 && match.fact(0, "points") == 50)
        #expect(outcomes[0].events == [.dartRegistered(player: 0, hit: .innerBull), .marksScored(player: 0, target: 25, count: 2)])
        #expect(outcomes[1].events == [.dartRegistered(player: 0, hit: .outerBull), .marksScored(player: 0, target: 25, count: 1),
                                       .targetClosed(player: 0, target: 25)])
        #expect(outcomes[2].events == [.dartRegistered(player: 0, hit: .innerBull), .pointsScored(player: 0, points: 50),
                                       .turnCompleted(player: 0)])
    }

    @Test func cri5_victoryOnTheLastClosure() throws {
        var match = try registry.match(.cricket, ["scoring": "standard"], players: 2)
        let outcomes = match.play("T20, T19, T18 | MISS ×3 | T17, T16, T15 | MISS ×3 | DB, SB")
        #expect(match.phase == .finished && match.snapshot.finishReason == .victory)
        #expect(match.fact(0, "closedCount") == 7 && Self.normalTargets.allSatisfy { marks(match, 0, $0) == 3 })
        #expect(points(match) == [0, 0] && match.snapshot.ranks == [1, 2])
        // The game ends on the second dart of the turn, without `turnCompleted`.
        #expect(match.turnNotation == ["DB", "SB"])
        #expect(outcomes.last?.events == [.dartRegistered(player: 0, hit: .outerBull), .marksScored(player: 0, target: 25, count: 1),
                                          .targetClosed(player: 0, target: 25), .gameFinished(reason: .victory)])
        let before = match.snapshot
        #expect(match.throwDart(DartRecord(hit: .single(20))) == .rejected(.gameFinished))
        #expect(match.snapshot == before && match.snapshot.highlights.isEmpty)
    }

    @Test func cri6_allClosedButBehind_noVictoryBeforeCatchingUp() throws {
        var match = try registry.match(.cricket, ["scoring": "standard"], players: 2)
        match.play("T20, S20, S20 | T20, T19, T18 | MISS ×3 | T17, T16, T15 | MISS ×3 | DB, SB, MISS")
        #expect(match.phase == .turnComplete && match.snapshot.finishReason == nil)
        #expect(match.fact(1, "closedCount") == 7 && points(match) == [40, 0])
        // J2 has more marks but fewer points: the score comes first.
        #expect(match.snapshot.ranks == [1, 2])
        let outcomes = match.play("| MISS ×3 | T19")
        #expect(match.phase == .finished && match.snapshot.finishReason == .victory)
        #expect(points(match) == [40, 57] && match.snapshot.ranks == [2, 1])
        #expect(outcomes.last?.events == [.dartRegistered(player: 1, hit: .treble(19)), .pointsScored(player: 1, points: 57),
                                          .gameFinished(reason: .victory)])
    }

    @Test func cri7_cutThroat_theWinnerIsNotTheThrower() throws {
        var match = try registry.match(.cricket, ["scoring": "cutThroat"], players: 3)
        match.play("T20, S20, MISS | T20, T19, T18 | MISS ×3 |")
        match.play("MISS ×3 | T17, T16, T15 | MISS ×3 |")
        match.play("MISS ×3 | DB, SB, MISS |")
        // J2 has closed everything, but J1 is strictly better: no victory.
        #expect(match.fact(1, "closedCount") == 7 && points(match) == [0, 20, 20])
        #expect(match.phase == .throwing && match.snapshot.currentPlayer == 2 && match.snapshot.round == 3)
        match.play("T19, S19")
        #expect(points(match) == [19, 20, 20] && match.phase == .throwing)
        let last = match.play("S19")
        #expect(points(match) == [38, 20, 20])
        #expect(match.phase == .finished && match.snapshot.finishReason == .victory)
        // J2 and J3 both have 20 points; J2 has 21 marks, J3 has 3.
        #expect(match.snapshot.ranks == [3, 1, 2] && match.snapshot.winners == [1])
        // The third dart of J3 ends the game: the points it gives make J2 the winner.
        #expect(last[0].events == [.dartRegistered(player: 2, hit: .single(19)), .pointsGiven(player: 2, to: [0], pointsEach: 19),
                                   .gameFinished(reason: .victory)])
        #expect(match.snapshot.currentPlayer == 2)
    }

    @Test func cri8_cricketLight_drawnTargets() throws {
        var match = try registry.match(.cricket, ["targets": "light"], players: 2, seed: 42)
        #expect(match.gameFact("targets") == [19, 18, 17, 15])
        let outcomes = match.play("T20, T19, S15")
        // T20 has no effect: 20 is not a target.
        #expect(outcomes[0].events == [.dartRegistered(player: 0, hit: .treble(20)), .noEffect(player: 0)])
        #expect(match.fact(0, "marks") == [19: 3, 18: 0, 17: 0, 15: 1])
        #expect(points(match) == [0, 0])
    }

    @Test func cri9_solo() throws {
        var match = try registry.match(.cricket, ["scoring": "standard"], players: 1)
        let outcomes = match.play("T20, T20, T19 | T18, T17, T16 | T15, DB, SB")
        #expect(match.phase == .finished && match.snapshot.finishReason == .victory && match.fact(0, "points") == 0)
        // The second T20 is a lost mark.
        #expect(outcomes[1].events == [.dartRegistered(player: 0, hit: .treble(20)), .noEffect(player: 0)])
        // The game ends on the ninth dart.
        let darts = match.entries.filter { $0 != .endTurn }
        #expect(darts.count == 9 && outcomes.last?.events.last == .gameFinished(reason: .victory))
        #expect(match.snapshot.ranks == [1])
    }

    @Test(arguments: ["standard", "cutThroat"])
    func cri10_roundLimit(_ scoring: String) throws {
        var match = try registry.match(.cricket, ["scoring": .string(scoring), "maxRounds": 1], players: 2)
        let outcomes = match.play("T20, S20, MISS | S19, S18, S17 |")
        #expect(match.phase == .finished && match.snapshot.finishReason == .roundLimit)
        #expect(outcomes.last?.events == [.gameFinished(reason: .roundLimit)])
        // Standard: J1 scores 20 for himself. Cut-throat: the 20 points go to J2, and the fewest points win.
        #expect(points(match) == (scoring == "standard" ? [20, 0] : [0, 20]))
        #expect(match.snapshot.ranks == [1, 2])
        #expect(match.snapshot.turn.darts.isEmpty && match.snapshot.highlights.isEmpty)
    }

    // MARK: Options and initial state (GAMES.md §4.2, §4.3)

    @Test func defaults_areCutThroatNormalTwentyRounds() throws {
        let match = try registry.match(.cricket, players: 3)
        #expect(match.configuration.options == ["scoring": "cutThroat", "targets": "normal", "maxRounds": 20])
        #expect(match.snapshot.roundLimit == 20)
        #expect(match.snapshot.title == LocalizedText(verbatim: "Cricket"))
        #expect(match.snapshot.variant == LocalizedText(verbatim: "Cut-throat"))
        #expect(try registry.match(.cricket, ["scoring": "standard"], players: 1).snapshot.variant == LocalizedText(verbatim: "Standard"))
        #expect(try registry.match(.cricket, ["targets": "light"], players: 1).snapshot.variant
                == LocalizedText(fr: "Cut-throat · Léger", en: "Cut-throat · Light"))
        #expect(try registry.match(.cricket, ["maxRounds": .null], players: 1).snapshot.roundLimit == nil)
    }

    @Test func initialState_normalTargets() throws {
        for count in 1...8 {
            let match = try registry.match(.cricket, players: count, seed: 99)
            #expect(match.gameFact("targets") == .ints(Self.normalTargets) && match.snapshot.facts.count == 1)
            for player in 0..<count {
                #expect(match.fact(player, "points") == 0 && match.fact(player, "closedCount") == 0)
                #expect(match.fact(player, "marks") == [20: 0, 19: 0, 18: 0, 17: 0, 16: 0, 15: 0, 25: 0])
                #expect(match.snapshot.players[player].facts.count == 3)
            }
            #expect(match.snapshot.ranks == Array(repeating: 1, count: count))
            let grid = try #require(match.snapshot.grid)
            #expect(grid.columns == ["20", "19", "18", "17", "16", "15", "B"])
            #expect(grid.marks == Array(repeating: Array(repeating: 0, count: 7), count: count))
            #expect(grid.dead == Array(repeating: false, count: 7))
            // Everything is to close: seven targets, in the order of the list.
            #expect(match.snapshot.highlights == [20, 19, 18, 17, 16, 15].map { BoardHighlight(zone: .sector($0), role: .target) }
                    + [BoardHighlight(zone: .bull, role: .target)])
        }
        #expect(throws: GameConfigurationError.playerCountOutOfRange(allowed: 1...8, actual: 9)) {
            try registry.match(.cricket, players: 9)
        }
        #expect(throws: GameConfigurationError.invalidOptionValue(key: "scoring")) {
            try registry.match(.cricket, ["scoring": "tactics"], players: 2)
        }
        #expect(throws: GameConfigurationError.invalidOptionValue(key: "targets")) {
            try registry.match(.cricket, ["targets": 4], players: 2)
        }
    }

    /// Light: `s = rng.shuffled([15…20])`, the first four of `s`, sorted in decreasing order; no bull (GAMES.md §4.3).
    @Test func light_targetsFollowTheSeed() throws {
        var seen = Set<[Int]>()
        for seed in UInt64(0)..<60 {
            var generator = SeededRandom(seed: seed)
            let expected = Array(generator.shuffled([15, 16, 17, 18, 19, 20]).prefix(4)).sorted(by: >)
            let match = try registry.match(.cricket, ["targets": "light"], players: 2, seed: seed)
            #expect(match.gameFact("targets") == .ints(expected), "seed \(seed)")
            #expect(expected.count == 4 && Set(expected).count == 4 && expected.allSatisfy { (15...20).contains($0) })
            #expect(match.snapshot.grid?.columns == expected.map(String.init))
            #expect(match.snapshot.highlights == expected.map { BoardHighlight(zone: .sector($0), role: .target) })
            guard case .map(let map)? = match.fact(1, "marks") else {
                Issue.record("marks is not a map")
                continue
            }
            #expect(map.keys.sorted(by: >) == expected)
            seen.insert(expected)
        }
        // Fifteen possible sets; sixty seeds reach many of them.
        #expect(seen.count >= 8)
    }

    @Test func light_theBullAndTheUndrawnNumbersHaveNoEffect() throws {
        var match = try registry.match(.cricket, ["targets": "light", "scoring": "standard"], players: 2, seed: 42)
        // Targets 19, 18, 17, 15: neither 20, nor 16, nor the bull.
        for script in ["DB", "SB", "T16", "D20", "S1"] {
            let outcome = try #require(match.play(script).first)
            #expect(outcome.events.contains(.noEffect(player: match.snapshot.currentPlayer)), "\(script)")
            if match.phase == .turnComplete { match.endTurn() }
        }
        #expect(points(match) == [0, 0] && closedCounts(match) == [0, 0])
        // Four targets closed win the game.
        var solo = try registry.match(.cricket, ["targets": "light"], players: 1, seed: 42)
        solo.play("T19, T18, T17 | T15")
        #expect(solo.phase == .finished && solo.snapshot.finishReason == .victory && solo.fact(0, "closedCount") == 4)
    }

    /// The rule type itself: the normal game draws nothing, the light game draws exactly five times.
    @Test func rules_drawOnlyInLight_fiveTimes() throws {
        var random = SeededRandom(seed: 5)
        let normal = GameConfiguration(gameID: .cricket, players: testPlayers(2), seed: 5)
        let rules = try CricketRules(configuration: normal, random: &random)
        #expect(random == SeededRandom(seed: 5))
        #expect(rules.roundLimit == 20 && rules.ranks() == [1, 1] && !rules.isEliminated(1))

        let light = GameConfiguration(gameID: .cricket, options: ["targets": "light"], players: testPlayers(2), seed: 5)
        _ = try CricketRules(configuration: light, random: &random)
        var expected = SeededRandom(seed: 5)
        for _ in 0..<5 { _ = expected.next() }
        #expect(random == expected)

        let odd = GameConfiguration(gameID: .cricket, options: ["scoring": "points"], players: testPlayers(2), seed: 5)
        #expect(throws: GameConfigurationError.invalidOptionValue(key: "scoring")) {
            _ = try CricketRules(configuration: odd, random: &random)
        }
        // A number of players outside the range is refused before anything is drawn.
        let before = random
        for count in [0, 9] {
            let crowd = GameConfiguration(gameID: .cricket, options: ["targets": "light"], players: testPlayers(count), seed: 5)
            #expect(throws: GameConfigurationError.playerCountOutOfRange(allowed: 1...8, actual: count)) {
                _ = try CricketRules(configuration: crowd, random: &random)
            }
        }
        #expect(random == before)
    }

    // MARK: Effect of a dart (GAMES.md §4.4)

    @Test func marks_singleDoubleTreble_onEveryTarget() throws {
        for target in [20, 19, 18, 17, 16, 15] {
            for (hit, count) in [(Hit.single(target), 1), (Hit.double(target), 2), (Hit.treble(target), 3)] {
                var match = try registry.match(.cricket, players: 2)
                let outcome = match.throwDart(DartRecord(hit: hit))
                var expected: [GameEvent] = [.dartRegistered(player: 0, hit: hit), .marksScored(player: 0, target: target, count: count)]
                if count == 3 { expected.append(.targetClosed(player: 0, target: target)) }
                #expect(outcome.events == expected, "\(hit)")
                #expect(marks(match, 0, target) == count && match.fact(0, "closedCount") == .int(count == 3 ? 1 : 0))
                #expect(points(match) == [0, 0])
            }
        }
    }

    @Test func numbersOutsideTheTargets_andMiss_haveNoEffect() throws {
        var hits = (1...14).flatMap { [Hit.single($0), .double($0), .treble($0)] }
        hits.append(.miss)
        for hit in hits {
            var match = try registry.match(.cricket, players: 2)
            let before = match.snapshot.players.map(\.facts)
            #expect(match.throwDart(DartRecord(hit: hit)).events == [.dartRegistered(player: 0, hit: hit), .noEffect(player: 0)], "\(hit)")
            #expect(match.snapshot.players.map(\.facts) == before)
        }
    }

    @Test func lostMarks_aDartThatClosesADeadTargetScoresNothing() throws {
        // J1 closes 20; J2 has two marks and throws a treble: one closing mark, 20 is dead, two marks are lost.
        var match = try registry.match(.cricket, ["scoring": "standard"], players: 2)
        let outcomes = match.play("T20, MISS, MISS | D20, T20")
        #expect(outcomes.last?.events == [.dartRegistered(player: 1, hit: .treble(20)), .marksScored(player: 1, target: 20, count: 1),
                                          .targetClosed(player: 1, target: 20), .targetDead(target: 20)])
        #expect(points(match) == [0, 0] && marks(match, 1, 20) == 3)
        #expect(match.snapshot.grid?.dead == [true, false, false, false, false, false, false])
        // From now on 20 is dead for both.
        #expect(match.play("S20").first?.events == [.dartRegistered(player: 1, hit: .single(20)), .noEffect(player: 1),
                                                    .turnCompleted(player: 1)])
        #expect(match.play("| D20").last?.events == [.dartRegistered(player: 0, hit: .double(20)), .noEffect(player: 0)])
    }

    @Test func solo_everyClosureKillsTheTarget_andNoPointIsEverScored() throws {
        var match = try registry.match(.cricket, players: 1)
        let outcomes = match.play("D20, T20, T20")
        #expect(outcomes[1].events == [.dartRegistered(player: 0, hit: .treble(20)), .marksScored(player: 0, target: 20, count: 1),
                                       .targetClosed(player: 0, target: 20), .targetDead(target: 20)])
        #expect(outcomes[2].events == [.dartRegistered(player: 0, hit: .treble(20)), .noEffect(player: 0), .turnCompleted(player: 0)])
        #expect(match.fact(0, "points") == 0 && roles(match)[.sector(20)] == .inactive)
    }

    @Test func standard_pointsGoToTheThrower_whileAnyOpponentIsOpen() throws {
        var match = try registry.match(.cricket, ["scoring": "standard"], players: 3)
        // J1 and J2 close 19; J3 stays open: both keep scoring on it.
        match.play("T19, T19, MISS | T19, S19, MISS | MISS ×3 |")
        #expect(points(match) == [57, 19, 0])
        let outcome = match.play("D19")[0]
        #expect(outcome.events == [.dartRegistered(player: 0, hit: .double(19)), .pointsScored(player: 0, points: 38)])
        #expect(points(match) == [95, 19, 0])
    }

    @Test func cutThroat_pointsGoOnlyToTheOpponentsStillOpen() throws {
        var match = try registry.match(.cricket, ["scoring": "cutThroat"], players: 4)
        // J1 closes the bull, then J3 closes it too.
        match.play("DB, SB, MISS | MISS ×3 | DB, DB, MISS | MISS ×3 |")
        // J3's second DB: one closing mark, then one scoring mark of 25 given to J2 and J4 (J1 has closed).
        #expect(points(match) == [0, 25, 0, 25])
        let outcome = match.play("DB")[0]
        #expect(outcome.events == [.dartRegistered(player: 0, hit: .innerBull), .pointsGiven(player: 0, to: [1, 3], pointsEach: 50)])
        #expect(points(match) == [0, 75, 0, 75])
        // The thrower never gets a point in cut-throat.
        match.play("SB, SB")
        #expect(points(match) == [0, 125, 0, 125])
        // Once J2 and J4 have closed it too, the bull is dead and gives nothing.
        match.play("| DB, SB, MISS | MISS ×3 | SB, DB")
        #expect(match.snapshot.grid?.dead.last == true)
        let dead = match.play("DB")[0]
        #expect(dead.events == [.dartRegistered(player: 3, hit: .innerBull), .noEffect(player: 3), .turnCompleted(player: 3)])
        #expect(points(match) == [0, 125, 0, 125])
    }

    // MARK: Victory and ranking (GAMES.md §4.6)

    @Test func victory_needsEveryTargetClosed_andNobodyStrictlyBetter() throws {
        // Equal scores: nobody is strictly better, so the first to close everything wins.
        var match = try registry.match(.cricket, ["scoring": "standard"], players: 2)
        match.play("T20, T20, MISS | T15, T15, S15 |")
        #expect(points(match) == [60, 60] && match.snapshot.ranks == [1, 1])
        match.play("MISS ×3 | T20, T19, T18 | MISS ×3 | T17, T16, DB |")
        // J2 needs only one mark on the bull.
        #expect(match.fact(1, "closedCount") == 6 && match.phase == .throwing && match.snapshot.finishReason == nil)
        #expect(match.snapshot.ranks == [2, 1])
        match.play("MISS ×3 | SB")
        #expect(match.phase == .finished && match.snapshot.finishReason == .victory)
        #expect(points(match) == [60, 60] && match.snapshot.ranks == [2, 1] && match.snapshot.winners == [1])
    }

    @Test func cutThroat_aPlayerWhoClosedEverythingWaitsWhileSomeoneHasFewerPoints() throws {
        var match = try registry.match(.cricket, ["scoring": "cutThroat"], players: 2)
        // J1 closes 20 and gives 20 to J2, who then closes everything.
        match.play("T20, S20, MISS | T20, T19, T18 | MISS ×3 | T17, T16, T15 | MISS ×3 | DB, SB, MISS |")
        #expect(match.fact(1, "closedCount") == 7 && points(match) == [0, 20] && match.phase == .throwing)
        #expect(match.snapshot.ranks == [1, 2])
        // J2 catches up by giving points on the targets J1 has not closed.
        match.play("MISS ×3 | S19")
        #expect(points(match) == [19, 20] && match.phase == .throwing)
        let last = match.play("MISS, S15")
        #expect(points(match) == [34, 20] && match.phase == .finished && match.snapshot.ranks == [2, 1])
        #expect(last.last?.events == [.dartRegistered(player: 1, hit: .single(15)), .pointsGiven(player: 1, to: [0], pointsEach: 15),
                                      .gameFinished(reason: .victory)])
    }

    @Test func ranking_scoreFirst_thenClosingMarks_thenTie() throws {
        var match = try registry.match(.cricket, ["scoring": "standard", "maxRounds": 2], players: 4)
        // No points: only the marks count. J1 3 marks, J2 3 marks, J3 4 marks, J4 none.
        match.play("T20, MISS, MISS | S19, S18, S17 | D16, D15, MISS | MISS ×3 |")
        #expect(points(match) == [0, 0, 0, 0] && match.snapshot.ranks == [2, 2, 1, 4])
        // A point beats any number of marks.
        match.play("S20 | MISS | MISS | MISS")
        #expect(points(match) == [20, 0, 0, 0] && match.snapshot.ranks == [1, 3, 2, 4])
        match.play("|")
        #expect(match.phase == .finished && match.snapshot.finishReason == .roundLimit)
        #expect(match.snapshot.ranks == [1, 3, 2, 4] && match.snapshot.winners == [0])
    }

    @Test func ranking_cutThroat_fewestPointsFirst() throws {
        var match = try registry.match(.cricket, ["maxRounds": 1], players: 3)
        match.play("T20, T20, MISS | T20, S20, MISS | MISS ×3 |")
        #expect(points(match) == [0, 60, 80] && match.snapshot.ranks == [1, 2, 3])
        #expect(match.phase == .finished)
        // Marks only count closing marks, three per target at most: J1 has 3, not 6.
        #expect(match.snapshot.players[0].resultLines.last == LocalizedText(fr: "3 marques", en: "3 marks"))
    }

    // MARK: Scoreboard and highlights (GAMES.md §4.7)

    @Test func highlights_targetSecondaryInactive() throws {
        var match = try registry.match(.cricket, ["scoring": "standard"], players: 2)
        match.play("T20, T19, S18 |")
        // For J2 everything is still to close.
        #expect(match.snapshot.highlights.allSatisfy { $0.role == .target && $0.owner == nil })
        match.play("T20, MISS, MISS |")
        // For J1: 20 is dead, 19 is closed and J2 is open on it, the rest is to close.
        var expected: [BoardZone: HighlightRole] = [.sector(20): .inactive, .sector(19): .secondary, .sector(18): .target,
                                                    .sector(17): .target, .sector(16): .target, .sector(15): .target, .bull: .target]
        #expect(roles(match) == expected)
        #expect(match.snapshot.highlights.map(\.zone) == [.sector(20), .sector(19), .sector(18), .sector(17), .sector(16), .sector(15), .bull])
        // Highlights are for the current player, also once the turn is closed.
        match.play("MISS ×3")
        #expect(match.phase == .turnComplete && roles(match) == expected)
        match.endTurn()
        expected[.sector(19)] = .target
        #expect(roles(match) == expected)
    }

    @Test func grid_andFacts_followTheMarks() throws {
        var match = try registry.match(.cricket, ["scoring": "standard"], players: 2)
        match.play("T20, D19, SB | T20, DB, S15")
        let grid = try #require(match.snapshot.grid)
        #expect(grid.columns == ["20", "19", "18", "17", "16", "15", "B"])
        #expect(grid.marks == [[3, 2, 0, 0, 0, 0, 1], [3, 0, 0, 0, 0, 1, 2]])
        #expect(grid.dead == [true, false, false, false, false, false, false])
        #expect(match.fact(0, "marks") == [20: 3, 19: 2, 18: 0, 17: 0, 16: 0, 15: 0, 25: 1])
        #expect(match.fact(1, "marks") == [20: 3, 19: 0, 18: 0, 17: 0, 16: 0, 15: 1, 25: 2])
        #expect(closedCounts(match) == [1, 1])
    }

    @Test func presentation_rowsCaptionsAndSummary() throws {
        var match = try registry.match(.cricket, ["scoring": "standard"], players: 2)
        #expect(match.snapshot.players[0].primary == ScoreValue(0))
        #expect(match.snapshot.players[0].detail == LocalizedText(fr: "0 cible fermée", en: "0 targets closed"))
        #expect(match.snapshot.turn.summary == LocalizedText(fr: "Volée : 0 marque", en: "Turn: 0 marks"))
        match.play("D20, T20, S5")
        #expect(match.snapshot.players[0].primary == ScoreValue(40))
        #expect(match.snapshot.players[0].detail == LocalizedText(fr: "1 cible fermée", en: "1 target closed"))
        #expect(match.snapshot.players[0].badges.isEmpty && match.snapshot.players[0].meter == nil)
        #expect(match.snapshot.turn.darts.map(\.caption) == [
            DartCaption(LocalizedText(fr: "+2 marques", en: "+2 marks"), tone: .positive),
            DartCaption(LocalizedText(fr: "Fermé · +40", en: "Closed · +40"), tone: .positive),
            DartCaption(LocalizedText(fr: "Sans effet", en: "No effect")),
        ])
        // Five marks counted: two to close, one to close, two to score.
        #expect(match.snapshot.turn.summary == LocalizedText(fr: "Volée : 5 marques", en: "Turn: 5 marks"))
        match.play("| S19, T18, S20")
        #expect(match.snapshot.turn.darts.map(\.caption) == [
            DartCaption(LocalizedText(fr: "+1 marque", en: "+1 mark"), tone: .positive),
            DartCaption(LocalizedText(fr: "18 fermé", en: "18 closed"), tone: .positive),
            DartCaption(LocalizedText(fr: "+1 marque", en: "+1 mark"), tone: .positive),
        ])
        match.play("| S20, DB")
        #expect(match.snapshot.turn.darts.map(\.caption) == [
            DartCaption(LocalizedText(verbatim: "+20"), tone: .positive),
            DartCaption(LocalizedText(fr: "+2 marques", en: "+2 marks"), tone: .positive),
        ])
        var cutThroat = try registry.match(.cricket, players: 2)
        cutThroat.play("T20, D20, SB")
        #expect(cutThroat.snapshot.turn.darts.map(\.caption) == [
            DartCaption(LocalizedText(fr: "20 fermé", en: "20 closed"), tone: .positive),
            DartCaption(LocalizedText(fr: "+40 aux adversaires", en: "+40 to opponents"), tone: .positive),
            DartCaption(LocalizedText(fr: "+1 marque", en: "+1 mark"), tone: .positive),
        ])
        var bull = try registry.match(.cricket, players: 2)
        bull.play("DB, DB")
        #expect(bull.snapshot.turn.darts.last?.caption
                == DartCaption(LocalizedText(fr: "Fermé · +25", en: "Closed · +25"), tone: .positive))
        bull.play("MISS | DB, SB")
        #expect(bull.snapshot.turn.darts.last?.caption == DartCaption(LocalizedText(fr: "Bull fermé", en: "Bull closed"), tone: .positive))
    }

    @Test func presentation_results() throws {
        var match = try registry.match(.cricket, ["scoring": "standard"], players: 2)
        match.play("T20, T19, T18 | MISS ×3 | T17, T16, T15 | MISS ×3 | DB")
        // The results sentence and the lines of the results screen come with the end of the game.
        #expect(match.snapshot.outcome == nil && match.snapshot.players.allSatisfy { $0.resultLines.isEmpty })
        match.play("SB")
        #expect(match.snapshot.outcome == LocalizedText(fr: "Toutes les cibles fermées et le meilleur score : 0.",
                                                        en: "All targets closed, with the best score: 0."))
        #expect(match.snapshot.winnerTitle == nil)
        #expect(match.snapshot.players[0].resultLines == [LocalizedText(fr: "7 cibles fermées", en: "7 targets closed"),
                                                         LocalizedText(fr: "21 marques", en: "21 marks")])
        #expect(match.snapshot.players[1].resultLines == [LocalizedText(fr: "0 cible fermée", en: "0 targets closed"),
                                                         LocalizedText(fr: "0 marque", en: "0 marks")])

        var solo = try registry.match(.cricket, players: 1)
        solo.play("T20, T19, T18 | T17, T16, T15 | DB, SB")
        #expect(solo.snapshot.outcome == LocalizedText(fr: "Toutes les cibles fermées.", en: "All targets closed."))

        var limit = try registry.match(.cricket, ["scoring": "standard", "maxRounds": 1], players: 2)
        limit.play("T20, S20, MISS | S19, S18, S17 |")
        #expect(limit.snapshot.outcome == LocalizedText(fr: "En tête à la limite de manches : 20 points, 3 marques.",
                                                        en: "In the lead at the round limit: 20 points, 3 marks."))
        // The volley is empty once the game ended at the round limit; no stale turn summary.
        #expect(limit.snapshot.turn.darts.isEmpty && limit.snapshot.turn.summary == nil)

        var tie = try registry.match(.cricket, ["maxRounds": 1], players: 3)
        tie.play("S20 | S19 | MISS |")
        #expect(tie.snapshot.ranks == [1, 1, 3])
        #expect(tie.snapshot.outcome == LocalizedText(fr: "Égalité à la limite de manches : 0 point, 1 marque.",
                                                      en: "Tied at the round limit: 0 points, 1 mark."))
    }

    // MARK: Same bed, same effect; replay (GAMES.md §2.2, §2.5)

    @Test func effectKey_groupsTheDartsOfEqualEffect() throws {
        var match = try registry.match(.cricket, ["scoring": "standard"], players: 2)
        // Off-target numbers and MISS all do nothing.
        #expect(match.effectKey(for: .single(1)) == match.effectKey(for: .treble(14)))
        #expect(match.effectKey(for: .single(1)) == match.effectKey(for: .miss))
        #expect(match.effectKey(for: .single(20)) != match.effectKey(for: .double(20)))
        #expect(match.effectKey(for: .outerBull) != match.effectKey(for: .innerBull))
        // The position is never read.
        #expect(match.effectKey(for: .single(20), position: BoardPoint(x: -3, y: 9)) == match.effectKey(for: .single(20)))
        // With two marks on a target that the opponent closed, every bed of the number just closes it.
        match.play("T20, MISS, MISS | D20")
        #expect(match.effectKey(for: .single(20)) == match.effectKey(for: .double(20)))
        #expect(match.effectKey(for: .single(20)) == match.effectKey(for: .treble(20)))
    }

    @Test(arguments: ["normal", "light"])
    func undoAndCorrections_rebuildTheSameState(_ targets: String) throws {
        let options: GameOptions = ["targets": .string(targets), "maxRounds": 3]
        var match = try registry.match(.cricket, options, players: 3, seed: 11)
        var history = [match.snapshot]
        var replayed = try registry.match(.cricket, options, players: 3, seed: 11)
        match.play("T20, T19, D18 | S18, DB, T17 | T15, T15, S16 | T19, S19, MISS | D17, D17 | SB, T20, T18 | S15")
        for entry in match.entries {
            switch entry {
            case .dart(let record): replayed.throwDart(record)
            case .endTurn: replayed.endTurn()
            }
            history.append(replayed.snapshot)
        }
        #expect(replayed.snapshot == match.snapshot)
        #expect(try registry.restoreMatch(match.record).snapshot == match.snapshot)
        // A correction and its inverse.
        let before = match.snapshot
        #expect(match.replaceDart(at: 0, with: .treble(19)).applied)
        #expect(match.replaceDart(at: 0, with: .single(15)).applied)
        #expect(match.snapshot == before)
        // The drawn targets survive every replay.
        let drawn = match.gameFact("targets")
        var index = history.count - 1
        while match.canUndo {
            #expect(match.snapshot == history[index] && match.gameFact("targets") == drawn)
            match.undo()
            index -= 1
        }
        #expect(index == 0 && match.snapshot == history[0])
    }

    @Test func correction_canUndoAVictory_andDropTheDartsAfterANewOne() throws {
        var match = try registry.match(.cricket, ["scoring": "standard"], players: 1)
        match.play("T20, T19, T18 | T17, T16, T15 | S1, DB, SB")
        #expect(match.phase == .finished)
        // The winning dart was misread: the game reopens, turn closed after three darts.
        #expect(match.replaceDart(at: 2, with: .single(2)).applied)
        #expect(match.phase == .turnComplete && match.snapshot.finishReason == nil && marks(match, 0, 25) == 2)
        // The first dart was in fact the bull: the game now ends on the second dart and the third one leaves the journal.
        let edit = match.replaceDart(at: 0, with: .outerBull)
        #expect(edit.applied && edit.dropped.map(\.hit) == [.single(2)])
        #expect(match.phase == .finished && match.turnNotation == ["SB", "DB"])
    }
}
