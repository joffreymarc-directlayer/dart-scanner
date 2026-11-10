import Testing
import DartCore
import DartGames
import DartTestSupport

/// Golf (GAMES.md §16): the vectors GOL-1 to GOL-7, then the rule paragraphs they do not reach.
@Suite struct GolfTests {
    private let registry = GameRegistry.standard

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

    private func strokes(_ match: GameMatch) -> [Int] { ints(match, "strokes") }
    private func toPar(_ match: GameMatch) -> [Int] { ints(match, "toPar") }

    /// Value of each dart of a script, read from its `shotPlayed` event.
    private func values(_ outcomes: [InputOutcome]) -> [Int] {
        outcomes.flatMap(\.events).compactMap { event in
            if case .shotPlayed(_, let strokes) = event { return strokes }
            return nil
        }
    }

    // MARK: Vectors (GAMES.md §16.9)

    @Test func gol1_valueOfADartTheLastOneCounts() throws {
        var match = try registry.match(.golf, players: 1)
        let outcomes = match.play("S1, T1, S5")
        #expect(values(outcomes) == [3, 2, 5])
        #expect(match.fact(0, "strokes") == 5 && match.fact(0, "holeScores") == [5] && match.fact(0, "toPar") == 2)
        #expect(match.phase == .turnComplete)
        #expect(outcomes[0].events == [.dartRegistered(player: 0, hit: .single(1)), .shotPlayed(player: 0, strokes: 3)])
        #expect(outcomes[2].events == [.dartRegistered(player: 0, hit: .single(5)), .shotPlayed(player: 0, strokes: 5),
                                       .holeCompleted(player: 0, hole: 1, strokes: 5, total: 5), .turnCompleted(player: 0)])
    }

    @Test func gol2_stoppingInTimeAndAHoleWithoutADart() throws {
        var match = try registry.match(.golf, players: 1)
        var outcomes = match.play("S1 |")
        #expect(match.fact(0, "strokes") == 3 && match.fact(0, "holeScores") == [3] && match.snapshot.round == 2)
        #expect(outcomes[1].events == [.holeCompleted(player: 0, hole: 1, strokes: 3, total: 3), .turnCompleted(player: 0),
                                       .roundStarted(round: 2), .turnStarted(player: 0, round: 2)])
        // Hole 2 without a dart: 5.
        outcomes = match.play("|")
        #expect(match.fact(0, "strokes") == 8 && match.fact(0, "holeScores") == [3, 5] && match.fact(0, "toPar") == 2)
        #expect(match.snapshot.round == 3)
        #expect(outcomes[0].events == [.holeCompleted(player: 0, hole: 2, strokes: 5, total: 8), .turnCompleted(player: 0),
                                       .roundStarted(round: 3), .turnStarted(player: 0, round: 3)])
    }

    @Test func gol3_theDoubleClosesTheTurnHoleInOne() throws {
        var match = try registry.match(.golf, players: 2)
        let outcomes = match.play("S20, D1")
        #expect(values(outcomes) == [5, 1])
        #expect(match.phase == .turnComplete && match.turnNotation == ["S20", "D1"])
        #expect(match.fact(0, "strokes") == 1 && match.fact(0, "toPar") == -2)
        #expect(match.throwDart(DartRecord(hit: .single(1))) == .rejected(.turnComplete))
        #expect(outcomes[1].events == [.dartRegistered(player: 0, hit: .double(1)), .shotPlayed(player: 0, strokes: 1),
                                       .holeCompleted(player: 0, hole: 1, strokes: 1, total: 1),
                                       .holeInOne(player: 0, hole: 1), .turnCompleted(player: 0)])
        match.play("| T1, S1, MISS")
        #expect(match.fact(1, "strokes") == 5 && match.snapshot.ranks == [1, 2])
    }

    @Test func gol4_bestDartVariant() throws {
        let script = "T1, S1, MISS | MISS, MISS, S1 |"
        var best = try registry.match(.golf, ["countedDart": "best"], players: 2)
        best.play(script)
        #expect(strokes(best) == [2, 3] && best.snapshot.ranks == [1, 2])
        // The same journal with `last`.
        var last = try registry.match(.golf, ["countedDart": "last"], players: 2)
        last.play(script)
        #expect(strokes(last) == [5, 3] && last.snapshot.ranks == [2, 1])
    }

    @Test func gol5_fullGameOverTwoHolesRankedAgainstPar() throws {
        var match = try registry.match(.golf, ["holes": 2], players: 2)
        match.play("T1 | S1, S1, D1 |")
        #expect(strokes(match) == [2, 1] && toPar(match) == [-1, -2] && match.snapshot.ranks == [2, 1])
        #expect(match.snapshot.round == 2)
        let highlights = match.snapshot.highlights
        #expect(highlights.filter { $0.role == .target }.map(\.zone) == [.double(2), .treble(2)])
        #expect(highlights.filter { $0.role == .secondary }.map(\.zone) == [.single(2)])
        #expect(highlights.count == 3)

        // J1 has played 2 holes, J2 only one.
        match.play("S2, T2 |")
        #expect(strokes(match) == [4, 1] && toPar(match) == [-2, -2] && match.snapshot.ranks == [1, 1])

        match.play("SB, DB, S1 |")
        #expect(match.phase == .finished && match.snapshot.finishReason == .roundLimit)
        #expect(strokes(match) == [4, 6] && match.snapshot.ranks == [1, 2])
        #expect(match.fact(0, "holeScores") == [2, 2] && match.fact(1, "holeScores") == [1, 5])
    }

    @Test func gol6_refusedConfigurations() {
        #expect(throws: GameConfigurationError.invalidOptionValue(key: "holes")) {
            try registry.match(.golf, ["holes": 0], players: 1)
        }
        #expect(throws: GameConfigurationError.invalidOptionValue(key: "holes")) {
            try registry.match(.golf, ["holes": 19], players: 1)
        }
        #expect(throws: GameConfigurationError.playerCountOutOfRange(allowed: 1...8, actual: 9)) {
            try registry.match(.golf, players: 9)
        }
    }

    @Test func gol7_correctionsIntoADoubleOutOfADouble() throws {
        var match = try registry.match(.golf, players: 1)
        match.play("S1, T1, S5")
        #expect(match.fact(0, "strokes") == 5)
        // At the replay the double closes the turn: T1 and S5 leave the journal.
        var edit = match.replaceDart(at: 0, with: .double(1))
        #expect(edit.applied && edit.dropped.map(\.hit) == [.treble(1), .single(5)])
        #expect(match.turnNotation == ["D1"] && match.phase == .turnComplete)
        #expect(match.fact(0, "strokes") == 1 && match.fact(0, "holeScores") == [1])
        #expect(match.entries.count == 1)

        match = try registry.match(.golf, players: 1)
        match.play("S20, D1")
        #expect(match.phase == .turnComplete && match.fact(0, "strokes") == 1)
        // The turn reopens: nothing is counted before the close.
        edit = match.replaceDart(at: 1, with: .single(1))
        #expect(edit.applied && edit.dropped.isEmpty)
        #expect(match.turnNotation == ["S20", "S1"] && match.phase == .throwing)
        #expect(match.fact(0, "strokes") == 0 && match.fact(0, "holeScores") == .ints([]))
        #expect(match.fact(0, "holesPlayed") == 0 && match.gameFact("provisional") == 3)
    }

    // MARK: Rule paragraphs beyond the vectors

    /// §16.4: on hole r, Dr = 1, Tr = 2, Sr = 3, and everything else is 5, for every hole and every bed.
    @Test func golf_valueOfEveryBedOnEveryHole() throws {
        for hole in 1...18 {
            var match = try registry.match(.golf, ["holes": 18], players: 1)
            for _ in 1..<hole { match.endTurn() }
            #expect(match.snapshot.round == hole)
            for hit in Hit.all {
                var copy = match
                let outcome = copy.throwDart(DartRecord(hit: hit))
                var expected = 5
                if hit.number == hole {
                    expected = hit.bed == .double ? 1 : hit.bed == .treble ? 2 : 3
                }
                // Never `noEffect`: every dart sets or confirms the score of the hole.
                let closing: [GameEvent] = expected == 1
                    ? [.holeCompleted(player: 0, hole: hole, strokes: 1, total: 5 * (hole - 1) + 1),
                       .holeInOne(player: 0, hole: hole), .turnCompleted(player: 0)]
                    : []
                #expect(outcome.events == [.dartRegistered(player: 0, hit: hit), .shotPlayed(player: 0, strokes: expected)] + closing,
                        "hole \(hole), \(hit)")
                #expect(copy.phase == (expected == 1 ? .turnComplete : .throwing))
                #expect(copy.gameFact("provisional") == .int(expected))
            }
        }
    }

    /// §16.2: the engine accepts 1 to 18 holes, although the setup screen offers 9 and 18; anything else is refused.
    @Test func golf_holesIsACustomValueValidatedByTheEngine() throws {
        for holes in 1...18 {
            let match = try registry.match(.golf, ["holes": .int(holes)], players: 2)
            #expect(match.snapshot.roundLimit == holes)
        }
        #expect(try registry.match(.golf, players: 1).configuration.options == ["holes": 9, "countedDart": "last"])
        for value in [OptionValue.int(-1), .int(20), .string("nine"), .bool(true), .null, .strings(["9"])] {
            #expect(throws: GameConfigurationError.invalidOptionValue(key: "holes")) {
                try registry.match(.golf, ["holes": value], players: 1)
            }
        }
        #expect(throws: GameConfigurationError.invalidOptionValue(key: "countedDart")) {
            try registry.match(.golf, ["countedDart": "first"], players: 1)
        }
    }

    /// §16.4: the provisional score is 5 before any dart, then the last value (`last`) or the smallest (`best`).
    @Test func golf_provisionalScore() throws {
        var last = try registry.match(.golf, players: 2)
        var best = try registry.match(.golf, ["countedDart": "best"], players: 2)
        #expect(last.gameFact("provisional") == 5 && best.gameFact("provisional") == 5)
        let expected: [(dart: String, last: FactValue, best: FactValue)] = [("T1", 2, 2), ("S1", 3, 2), ("MISS", 5, 2)]
        for step in expected {
            last.play(step.dart)
            best.play(step.dart)
            #expect(last.gameFact("provisional") == step.last, "\(step.dart)")
            #expect(best.gameFact("provisional") == step.best, "\(step.dart)")
        }
        // Nothing is added to `strokes` before the close… which the third dart was.
        #expect(strokes(last) == [5, 0] && strokes(best) == [2, 0])
        // A new turn starts at 5 again, for the next player.
        last.play("|")
        best.play("|")
        #expect(last.gameFact("provisional") == 5 && best.gameFact("provisional") == 5)
        best.play("S5, S1")
        #expect(best.gameFact("provisional") == 3 && strokes(best) == [2, 0])
        #expect(best.fact(1, "holesPlayed") == 0 && best.fact(1, "holeScores") == .ints([]))
    }

    /// §16.4: the double of the hole closes the turn in both variants, and only it.
    @Test func golf_onlyTheDoubleOfTheHoleClosesTheTurn() throws {
        for counted in ["last", "best"] {
            var match = try registry.match(.golf, ["countedDart": .string(counted)], players: 1)
            // D2 on hole 1 is just a 5; DB is not the double of any hole.
            match.play("D2, DB")
            #expect(match.phase == .throwing && match.gameFact("provisional") == 5)
            let outcome = match.play("D1")[0]
            #expect(outcome.events.suffix(3) == [.holeCompleted(player: 0, hole: 1, strokes: 1, total: 1),
                                                 .holeInOne(player: 0, hole: 1), .turnCompleted(player: 0)])
            // Hole 2: its double as a first dart closes the turn after one dart.
            match.play("| D2")
            #expect(match.phase == .turnComplete && match.turnNotation == ["D2"])
            #expect(match.fact(0, "strokes") == 2 && match.fact(0, "holeScores") == [1, 1] && match.fact(0, "toPar") == -4)
        }
    }

    /// §16.5, §16.8: `holeCompleted` at every close, whatever closes the turn, and `holeInOne` for a score of 1 only.
    @Test func golf_closingEvents() throws {
        var match = try registry.match(.golf, players: 1)
        // Third dart, score 2: no fanfare.
        var outcomes = match.play("MISS, S1, T1")
        #expect(outcomes[2].events == [.dartRegistered(player: 0, hit: .treble(1)), .shotPlayed(player: 0, strokes: 2),
                                       .holeCompleted(player: 0, hole: 1, strokes: 2, total: 2), .turnCompleted(player: 0)])
        // Early confirmation on a treble, then on a single.
        outcomes = match.play("| T2 | S3 |")
        #expect(outcomes[2].events == [.holeCompleted(player: 0, hole: 2, strokes: 2, total: 4), .turnCompleted(player: 0),
                                       .roundStarted(round: 3), .turnStarted(player: 0, round: 3)])
        #expect(outcomes[4].events == [.holeCompleted(player: 0, hole: 3, strokes: 3, total: 7), .turnCompleted(player: 0),
                                       .roundStarted(round: 4), .turnStarted(player: 0, round: 4)])
        // The double as a third dart: the close comes once, with the fanfare.
        outcomes = match.play("S4, T4, D4")
        #expect(outcomes[2].events == [.dartRegistered(player: 0, hit: .double(4)), .shotPlayed(player: 0, strokes: 1),
                                       .holeCompleted(player: 0, hole: 4, strokes: 1, total: 8),
                                       .holeInOne(player: 0, hole: 4), .turnCompleted(player: 0)])
        #expect(match.endTurn().events == [.roundStarted(round: 5), .turnStarted(player: 0, round: 5)])
        #expect(match.fact(0, "holeScores") == [2, 2, 3, 1])
        // No event of this game is ever `noEffect`.
        #expect(!match.play("MISS, SB, DB |").flatMap(\.events).contains(.noEffect(player: 0)))
    }

    /// §16.5: in `best` a later miss costs nothing; in `last` it costs the hole.
    @Test func golf_stoppingIsAMoveOfTheGame() throws {
        var match = try registry.match(.golf, players: 1)
        // Keep the 3…
        match.play("S1 |")
        #expect(match.fact(0, "holeScores") == [3])
        // …or risk it and lose.
        match.play("S2, MISS |")
        #expect(match.fact(0, "holeScores") == [3, 5])
        // …or risk it and win.
        match.play("S3, MISS, T3")
        #expect(match.fact(0, "holeScores") == [3, 5, 2] && match.fact(0, "strokes") == 10 && match.fact(0, "toPar") == 1)
        #expect(match.fact(0, "holesPlayed") == 3)
    }

    /// §16.6: provisional ranks are by `toPar`, which is fair between players who have not played the same holes.
    @Test func golf_ranksFollowToPar() throws {
        var match = try registry.match(.golf, players: 3)
        #expect(match.snapshot.ranks == [1, 1, 1])
        // J1 plays par on hole 1: level with the two players who have not played yet.
        match.play("S1 |")
        #expect(toPar(match) == [0, 0, 0] && match.snapshot.ranks == [1, 1, 1])
        // J2 misses: +2. J3 scores a 2: −1.
        match.play("MISS | T1 |")
        #expect(toPar(match) == [0, 2, -1] && strokes(match) == [3, 5, 2] && match.snapshot.ranks == [2, 3, 1])
        // The score of the hole in progress does not count before the close.
        match.play("D3, T2")
        #expect(toPar(match) == [0, 2, -1] && match.snapshot.ranks == [2, 3, 1])
    }

    /// §16.6: no victory on a dart; the game ends at the confirmation of the last turn of hole `holes`.
    @Test func golf_endOfGame() throws {
        var match = try registry.match(.golf, ["holes": 1], players: 2)
        match.play("D1 | S1")
        #expect(match.phase == .throwing && match.snapshot.finishReason == nil)
        let outcome = match.endTurn()
        #expect(outcome.events == [.holeCompleted(player: 1, hole: 1, strokes: 3, total: 3), .turnCompleted(player: 1),
                                   .gameFinished(reason: .roundLimit)])
        #expect(match.phase == .finished && match.snapshot.ranks == [1, 2] && strokes(match) == [1, 3])
        #expect(!match.endTurn().isAccepted && !match.throwDart(DartRecord(hit: .double(1))).isAccepted)
        // Volley emptied at the round limit: the provisional score is the one of a turn without a dart.
        #expect(match.snapshot.turn.darts.isEmpty && match.gameFact("provisional") == 5)
        #expect(match.snapshot.highlights.isEmpty && match.snapshot.turn.summary == nil)
        // Undoing the confirmation gives the turn back, with its provisional score.
        match.undo()
        #expect(match.phase == .throwing && match.gameFact("provisional") == 3 && strokes(match) == [1, 0])
    }

    // MARK: Undo, corrections, replay (GAMES.md §2.5)

    @Test func golf_undoAndCorrections() throws {
        var match = try registry.match(.golf, ["countedDart": "best"], players: 1)
        match.play("S1, T1, MISS")
        #expect(match.fact(0, "strokes") == 2)
        // Removing the best dart changes the score of the hole and reopens the turn.
        match.removeDart(at: 1)
        #expect(match.phase == .throwing && match.fact(0, "strokes") == 0 && match.gameFact("provisional") == 3)
        match.play("MISS")
        #expect(match.fact(0, "holeScores") == [3])
        // Undo through the close, then through the darts.
        match.play("| D2")
        #expect(match.fact(0, "holeScores") == [3, 1] && match.phase == .turnComplete)
        match.undo()
        #expect(match.fact(0, "holeScores") == [3] && match.phase == .throwing && match.snapshot.round == 2)
        match.undo()
        #expect(match.phase == .turnComplete && match.snapshot.round == 1 && match.turnNotation == ["S1", "MISS", "MISS"])
        // A correction into the double in the middle of the turn drops what follows.
        let edit = match.replaceDart(at: 1, with: .double(1))
        #expect(edit.dropped.map(\.hit) == [.miss] && match.turnNotation == ["S1", "D1"])
        #expect(match.fact(0, "holeScores") == [1] && match.phase == .turnComplete)
    }

    @Test func golf_replayIsDeterministic() throws {
        for counted in ["last", "best"] {
            var match = try registry.match(.golf, ["holes": 5, "countedDart": .string(counted)], players: 3)
            var random = SeededRandom(seed: 99)
            var snapshots: [GameSnapshot] = []
            while match.phase != .finished {
                if match.phase == .turnComplete || random.nextInt(below: 4) == 0 {
                    match.endTurn()
                } else {
                    // One dart in three aims at the hole.
                    let hole = match.snapshot.round
                    let aimed = [Hit.single(hole), .treble(hole), .double(hole)][random.nextInt(below: 3)]
                    let hit = random.nextInt(below: 3) == 0 ? aimed : Hit.all[random.nextInt(below: Hit.all.count)]
                    match.throwDart(DartRecord(hit: hit))
                }
                snapshots.append(match.snapshot)
                // Derived values of §16.3.
                for row in match.snapshot.players {
                    guard case .ints(let scores)? = row.facts["holeScores"] else {
                        Issue.record("holeScores is a list")
                        return
                    }
                    #expect(row.facts["strokes"] == .int(scores.reduce(0, +)))
                    #expect(row.facts["holesPlayed"] == .int(scores.count))
                    #expect(row.facts["toPar"] == .int(scores.reduce(0, +) - 3 * scores.count))
                    #expect(scores.allSatisfy { [1, 2, 3, 5].contains($0) })
                }
            }
            #expect(match.snapshot.players.allSatisfy { $0.facts["holesPlayed"] == 5 })
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
    @Test func golf_sameEffectKeySameFuture() throws {
        var pairs = 0
        for seed in 0..<60 as Range<UInt64> {
            var random = SeededRandom(seed: seed)
            let counted = seed % 2 == 0 ? "last" : "best"
            var match = try registry.match(.golf, ["holes": 4, "countedDart": .string(counted)], players: 1 + random.nextInt(below: 3))
            func dart() -> Hit {
                let hole = match.snapshot.round
                return random.nextInt(below: 2) == 0 ? Hit.all[random.nextInt(below: Hit.all.count)]
                    : [Hit.single(hole), .treble(hole)][random.nextInt(below: 2)]
            }
            for _ in 0..<random.nextInt(below: 12) where match.phase != .finished {
                if match.phase == .turnComplete || random.nextInt(below: 6) == 0 { match.endTurn() }
                else { match.throwDart(DartRecord(hit: dart())) }
            }
            guard match.phase == .throwing else { continue }
            let groups = Dictionary(grouping: Hit.all) { match.effectKey(for: $0) }
            // Four effects: the double, the treble and the single of the hole, and the 60 other beds.
            #expect(groups.count == 4 && groups.values.map(\.count).sorted() == [1, 1, 1, 60])
            for group in groups.values where group.count > 1 {
                var first = match, second = match
                first.throwDart(DartRecord(hit: group[0]))
                second.throwDart(DartRecord(hit: group[group.count - 1]))
                pairs += 1
                for _ in 0..<12 where first.phase != .finished {
                    let hit = dart()
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
        #expect(pairs > 30)
    }

    /// The rule is as strict as the schema when it is built without the kernel.
    @Test func golf_ruleBuiltOnItsOwn() throws {
        var random = SeededRandom(seed: 0)
        func configuration(_ options: GameOptions, players: Int = 2) -> GameConfiguration {
            GameConfiguration(gameID: .golf, options: options, players: testPlayers(players), seed: 0)
        }
        #expect(throws: GameConfigurationError.invalidOptionValue(key: "holes")) {
            _ = try GolfRules(configuration: configuration(["holes": 19]), random: &random)
        }
        #expect(throws: GameConfigurationError.invalidOptionValue(key: "countedDart")) {
            _ = try GolfRules(configuration: configuration(["countedDart": 1]), random: &random)
        }
        #expect(throws: GameConfigurationError.playerCountOutOfRange(allowed: 1...8, actual: 9)) {
            _ = try GolfRules(configuration: configuration([:], players: 9), random: &random)
        }
        let rules = try GolfRules(configuration: configuration([:]), random: &random)
        #expect(rules.roundLimit == 9 && rules.ranks() == [1, 1])
        #expect(random == SeededRandom(seed: 0))
    }

    // MARK: Presentation (GAMES.md §16.7, ARCHITECTURE.md §5.6)

    @Test func golf_scoreboard() throws {
        var match = try registry.match(.golf, players: 2)
        #expect(match.snapshot.title == LocalizedText(verbatim: "Golf") && match.snapshot.variant == nil)
        #expect(try registry.match(.golf, ["countedDart": "best"], players: 1).snapshot.variant
                == LocalizedText(fr: "Meilleure fléchette", en: "Best dart"))
        #expect(match.snapshot.objective == LocalizedText(fr: "Trou 1 / 9 · par 3", en: "Hole 1 / 9 · par 3"))
        #expect(match.snapshot.turn.summary == LocalizedText(fr: "Ce trou : 5", en: "This hole: 5"))
        #expect(match.snapshot.players[0].detail == nil)
        #expect(match.snapshot.players[0].badges == [Badge(LocalizedText(verbatim: "Par"))])
        #expect(match.snapshot.highlights == [
            BoardHighlight(zone: .double(1), role: .target, label: "1"),
            BoardHighlight(zone: .treble(1), role: .target, label: "2"),
            BoardHighlight(zone: .single(1), role: .secondary, label: "3"),
        ])

        match.play("T1 | MISS, S1, S7 | S2, D2")
        #expect(match.snapshot.objective == LocalizedText(fr: "Trou 2 / 9 · par 3", en: "Hole 2 / 9 · par 3"))
        #expect(match.snapshot.turn.summary == LocalizedText(fr: "Ce trou : 1", en: "This hole: 1"))
        #expect(match.snapshot.players.map(\.primary) == [
            ScoreValue(3, unit: LocalizedText(fr: "coups", en: "strokes")),
            ScoreValue(5, unit: LocalizedText(fr: "coups", en: "strokes")),
        ])
        #expect(match.snapshot.players.map(\.detail) == [LocalizedText(verbatim: "2 · 1"), LocalizedText(verbatim: "5")])
        #expect(match.snapshot.players.map(\.badges) == [
            [Badge(LocalizedText(verbatim: "−3"), tone: .positive)],
            [Badge(LocalizedText(verbatim: "+2"), tone: .negative)],
        ])
        #expect(match.snapshot.players[0].facts == ["strokes": 3, "holesPlayed": 2, "holeScores": [2, 1], "toPar": -3])
        #expect(match.snapshot.facts == ["provisional": 1])
        #expect(match.snapshot.turn.darts.map(\.caption) == [
            DartCaption(LocalizedText(fr: "3 coups", en: "3 strokes"), tone: .neutral),
            DartCaption(LocalizedText(fr: "1 coup", en: "1 stroke"), tone: .positive),
        ])
        #expect(match.snapshot.highlights.map(\.zone) == [.double(2), .treble(2), .single(2)])

        // The captions of a miss and of a treble.
        match.play("| MISS, T2")
        #expect(match.snapshot.turn.darts.map(\.caption) == [
            DartCaption(LocalizedText(fr: "5 coups", en: "5 strokes"), tone: .negative),
            DartCaption(LocalizedText(fr: "2 coups", en: "2 strokes"), tone: .positive),
        ])
        #expect(match.snapshot.winnerTitle == nil && match.snapshot.outcome == nil)
    }

    @Test func golf_results() throws {
        var match = try registry.match(.golf, ["holes": 2], players: 2)
        match.play("D1 | S1 | T2 | MISS |")
        #expect(match.phase == .finished && match.snapshot.ranks == [1, 2])
        #expect(match.snapshot.outcome == LocalizedText(fr: "3 coups sur 2 trous (−3).", en: "3 strokes over 2 holes (−3)."))
        #expect(match.snapshot.players.map(\.resultLines) == [
            [LocalizedText(fr: "Écart au par : −3", en: "To par: −3"), LocalizedText(fr: "1 trou en un", en: "1 hole in one")],
            [LocalizedText(fr: "Écart au par : +2", en: "To par: +2")],
        ])
        #expect(match.snapshot.objective == LocalizedText(fr: "Trou 2 / 2 · par 3", en: "Hole 2 / 2 · par 3"))

        var tie = try registry.match(.golf, ["holes": 1], players: 2)
        tie.play("S1 | S1 |")
        #expect(tie.snapshot.ranks == [1, 1])
        #expect(tie.snapshot.outcome == LocalizedText(fr: "Égalité à 3 coups (Par).", en: "A tie at 3 strokes (Par)."))
        #expect(tie.snapshot.players[0].resultLines == [LocalizedText(fr: "Écart au par : Par", en: "To par: Par")])
    }
}
