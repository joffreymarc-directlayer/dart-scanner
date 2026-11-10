import Testing
import DartCore
import DartGames
import DartTestSupport

/// Beer Tap (GAMES.md §13): the vectors BEE-1 to BEE-6, then the rule paragraphs they do not reach.
@Suite struct BeerTapTests {
    private let registry = GameRegistry.standard

    /// An integer fact of one player.
    private func int(_ match: GameMatch, _ player: PlayerIndex, _ name: String) -> Int {
        guard case .int(let value)? = match.fact(player, name) else {
            Issue.record("the fact `\(name)` is an integer")
            return .min
        }
        return value
    }

    /// `poured`, `glasses`, `level` and `bonusGlasses` of one player, in this order.
    private func glass(_ match: GameMatch, _ player: PlayerIndex) -> [Int] {
        ["poured", "glasses", "level", "bonusGlasses"].map { int(match, player, $0) }
    }

    // MARK: Vectors (GAMES.md §13.9)

    @Test func bee1_pourFillAndCarryOver() throws {
        var match = try registry.match(.beerTap, players: 2)
        let outcomes = match.play("S20, S20, S20")
        #expect(match.fact(0, "poured") == 60 && match.fact(0, "glasses") == 1 && match.fact(0, "level") == 10)
        #expect(match.phase == .turnComplete)
        #expect(outcomes[0].events == [.dartRegistered(player: 0, hit: .single(20))])
        #expect(outcomes[2].events == [.dartRegistered(player: 0, hit: .single(20)),
                                       .glassFilled(player: 0, count: 1, glasses: 1),
                                       .turnScored(player: 0, points: 60), .turnCompleted(player: 0)])

        // The T20 fills a glass and leaves 10 in the next one.
        let second = match.play("| T20, MISS, S5")
        #expect(match.fact(1, "poured") == 65 && match.fact(1, "glasses") == 1 && match.fact(1, "level") == 15)
        #expect(second[1].events == [.dartRegistered(player: 1, hit: .treble(20)),
                                     .glassFilled(player: 1, count: 1, glasses: 1)])
        #expect(second[2].events == [.dartRegistered(player: 1, hit: .miss), .noEffect(player: 1)])

        match.play("| T19, S1, S10")
        #expect(match.fact(0, "poured") == 128 && match.fact(0, "glasses") == 2 && match.fact(0, "level") == 28)
        #expect(match.snapshot.round == 2)
    }

    @Test func bee2_freeGlassForATurnOfOneHundredOrMore() throws {
        // Nothing is offered before the turn closes.
        var match = try registry.match(.beerTap, players: 1)
        match.play("T20, T20")
        #expect(glass(match, 0) == [120, 2, 20, 0] && match.phase == .throwing)
        var outcomes = match.play("S20")
        // 140 poured + 50 offered.
        #expect(glass(match, 0) == [190, 3, 40, 1])
        #expect(outcomes[0].events == [.dartRegistered(player: 0, hit: .single(20)), .turnScored(player: 0, points: 140),
                                       .highTurn(player: 0, points: 140), .bonusGlass(player: 0, glasses: 3),
                                       .turnCompleted(player: 0)])

        match = try registry.match(.beerTap, players: 1)
        outcomes = match.play("T20, T20, T20")
        #expect(glass(match, 0) == [230, 4, 30, 1])
        #expect(outcomes[2].events == [.dartRegistered(player: 0, hit: .treble(20)),
                                       .glassFilled(player: 0, count: 1, glasses: 3),
                                       .turnScored(player: 0, points: 180), .oneEighty(player: 0),
                                       .bonusGlass(player: 0, glasses: 4), .turnCompleted(player: 0)])

        // A short turn of 120 points: the glass is offered at the confirmation.
        match = try registry.match(.beerTap, players: 1)
        outcomes = match.play("T20, T20 |")
        #expect(glass(match, 0) == [170, 3, 20, 1] && match.snapshot.round == 2)
        #expect(outcomes[2].events == [.turnScored(player: 0, points: 120), .highTurn(player: 0, points: 120),
                                       .bonusGlass(player: 0, glasses: 3), .turnCompleted(player: 0),
                                       .roundStarted(round: 2), .turnStarted(player: 0, round: 2)])

        // 99 points: no free glass.
        match = try registry.match(.beerTap, players: 1)
        outcomes = match.play("T20, S20, S19")
        #expect(glass(match, 0) == [99, 1, 49, 0])
        #expect(outcomes[2].events == [.dartRegistered(player: 0, hit: .single(19)), .turnScored(player: 0, points: 99),
                                       .turnCompleted(player: 0)])
    }

    @Test func bee3_glassSize() throws {
        var match = try registry.match(.beerTap, ["glassSize": 25], players: 1)
        var outcomes = match.play("S20, T20")
        #expect(match.fact(0, "poured") == 80 && match.fact(0, "glasses") == 3 && match.fact(0, "level") == 5)
        #expect(outcomes[0].events == [.dartRegistered(player: 0, hit: .single(20))])
        #expect(outcomes[1].events == [.dartRegistered(player: 0, hit: .treble(20)),
                                       .glassFilled(player: 0, count: 3, glasses: 3)])

        match = try registry.match(.beerTap, ["glassSize": 100], players: 1)
        match.play("T20, S20, S19")
        #expect(match.fact(0, "poured") == 99 && match.fact(0, "glasses") == 0 && match.fact(0, "level") == 99)
        outcomes = match.play("| S1")
        #expect(match.fact(0, "poured") == 100 && match.fact(0, "glasses") == 1 && match.fact(0, "level") == 0)
        #expect(outcomes[1].events == [.dartRegistered(player: 0, hit: .single(1)),
                                       .glassFilled(player: 0, count: 1, glasses: 1)])
    }

    @Test func bee4_endOfGameAndRanking() throws {
        var match = try registry.match(.beerTap, ["rounds": 1], players: 3)
        let outcomes = match.play("S20, S20, S10 | DB, MISS, MISS | T20, S20, S19 |")
        #expect(match.phase == .finished && match.snapshot.finishReason == .roundLimit)
        #expect((0..<3).map { int(match, $0, "poured") } == [50, 50, 99])
        #expect((0..<3).map { int(match, $0, "glasses") } == [1, 1, 1])
        #expect((0..<3).map { int(match, $0, "level") } == [0, 0, 49])
        // One full glass each: the level of the started glass decides; J1 and J2 tie.
        #expect(match.snapshot.ranks == [2, 2, 1] && match.snapshot.winners == [2])
        #expect(outcomes.last?.events == [.gameFinished(reason: .roundLimit)])
    }

    @Test func bee5_refusedConfigurations() {
        #expect(throws: GameConfigurationError.invalidOptionValue(key: "glassSize")) {
            try registry.match(.beerTap, ["glassSize": 40], players: 1)
        }
        #expect(throws: GameConfigurationError.invalidOptionValue(key: "rounds")) {
            try registry.match(.beerTap, ["rounds": 0], players: 1)
        }
        #expect(throws: GameConfigurationError.invalidOptionValue(key: "rounds")) {
            try registry.match(.beerTap, ["rounds": 21], players: 1)
        }
        #expect(throws: GameConfigurationError.playerCountOutOfRange(allowed: 1...8, actual: 9)) {
            try registry.match(.beerTap, players: 9)
        }
    }

    @Test func bee6_aCorrectionTakesTheFreeGlassBack() throws {
        var match = try registry.match(.beerTap, players: 1)
        match.play("T20, T20, S20")
        #expect(match.fact(0, "poured") == 190 && match.fact(0, "bonusGlasses") == 1)
        let edit = match.replaceDart(at: 0, with: .single(1))
        #expect(edit.applied && edit.dropped.isEmpty)
        // The turn is now worth 81 points only: the replay does not give the glass again.
        #expect(match.turnNotation == ["S1", "T20", "S20"])
        #expect(glass(match, 0) == [81, 1, 31, 0] && match.phase == .turnComplete)
    }

    // MARK: Rule paragraphs beyond the vectors

    @Test func beerTap_everyAcceptedSizeAndRoundCountStarts() throws {
        for size in [25, 50, 100] {
            for rounds in [1, 5, 20] {
                let match = try registry.match(.beerTap, ["glassSize": .int(size), "rounds": .int(rounds)], players: 8)
                #expect(match.snapshot.roundLimit == rounds && match.phase == .throwing)
                #expect((0..<8).allSatisfy { glass(match, $0) == [0, 0, 0, 0] && match.fact($0, "dartsThrown") == 0 })
                #expect(match.snapshot.ranks == Array(repeating: 1, count: 8))
            }
        }
        // The defaults of §13.2: a pint, five rounds.
        let match = try registry.match(.beerTap, players: 1)
        #expect(match.configuration.options == ["glassSize": 50, "rounds": 5] && match.snapshot.roundLimit == 5)
    }

    /// §13.4: every dart is counted, MISS included; a dart that fills no glass says nothing more than itself.
    @Test func beerTap_dartsThrownAndSilentPour() throws {
        var match = try registry.match(.beerTap, players: 2)
        let outcomes = match.play("MISS, S1, D2")
        #expect(outcomes[0].events == [.dartRegistered(player: 0, hit: .miss), .noEffect(player: 0)])
        #expect(outcomes[1].events == [.dartRegistered(player: 0, hit: .single(1))])
        #expect(outcomes[2].events == [.dartRegistered(player: 0, hit: .double(2)), .turnScored(player: 0, points: 5),
                                       .turnCompleted(player: 0)])
        #expect(match.fact(0, "dartsThrown") == 3 && match.fact(1, "dartsThrown") == 0)
        #expect(match.fact(0, "poured") == 5 && match.fact(0, "level") == 5)
    }

    /// §13.4: with a 25 cl glass a T20 fills two glasses from an empty glass and three from a glass holding 15.
    @Test func beerTap_oneDartFillsSeveralGlasses() throws {
        var match = try registry.match(.beerTap, ["glassSize": 25], players: 1)
        var outcomes = match.play("T20")
        #expect(outcomes[0].events == [.dartRegistered(player: 0, hit: .treble(20)),
                                       .glassFilled(player: 0, count: 2, glasses: 2)])
        #expect(match.fact(0, "level") == 10)
        outcomes = match.play("S5, T20")
        #expect(outcomes[1].events.contains(.glassFilled(player: 0, count: 3, glasses: 5)))
        // 125 points: the free glass is one glass of THIS size and leaves the level alone.
        #expect(outcomes[1].events.suffix(3) == [.highTurn(player: 0, points: 125), .bonusGlass(player: 0, glasses: 6),
                                                 .turnCompleted(player: 0)])
        #expect(glass(match, 0) == [150, 6, 0, 1])
    }

    /// §13.5: the threshold is 100 whatever the glass, 100 itself included, and the level does not move.
    @Test func beerTap_bonusThresholdIsExactlyOneHundred() throws {
        for size in [25, 50, 100] {
            var match = try registry.match(.beerTap, ["glassSize": .int(size)], players: 1)
            // T20 + S20 + S20 = 100.
            let outcomes = match.play("T20, S20, S20")
            #expect(match.fact(0, "bonusGlasses") == 1 && match.fact(0, "poured") == .int(100 + size))
            #expect(match.fact(0, "level") == .int(100 % size))
            #expect(outcomes[2].events.contains(.highTurn(player: 0, points: 100)))
            #expect(outcomes[2].events.contains(.bonusGlass(player: 0, glasses: (100 + size) / size)))

            match = try registry.match(.beerTap, ["glassSize": .int(size)], players: 1)
            match.play("T20, S20, S19")
            #expect(match.fact(0, "bonusGlasses") == 0 && match.fact(0, "poured") == 99)
        }
    }

    /// §13.5: the free glass belongs to the turn that earned it, once per turn, turn after turn.
    @Test func beerTap_oneFreeGlassPerTurn() throws {
        var match = try registry.match(.beerTap, players: 2)
        match.play("T20, T20, T20 | S1, S1, S1 | T20, T20, MISS | T20, T20, T20 |")
        // J1: 180 + 50, then 120 + 50. J2: 3, then 180 + 50.
        #expect(glass(match, 0) == [400, 8, 0, 2])
        #expect(glass(match, 1) == [233, 4, 33, 1])
        #expect(match.snapshot.ranks == [1, 2] && match.snapshot.round == 3)
    }

    /// §2.4: a turn confirmed without a dart closes with a total of zero.
    @Test func beerTap_emptyTurn() throws {
        var match = try registry.match(.beerTap, players: 2)
        let outcomes = match.play("|")
        #expect(outcomes[0].events == [.turnScored(player: 0, points: 0), .turnCompleted(player: 0),
                                       .turnStarted(player: 1, round: 1)])
        #expect(glass(match, 0) == [0, 0, 0, 0] && match.fact(0, "dartsThrown") == 0)
    }

    /// §13.6: no victory on a dart; the game ends at the confirmation of the last turn of round `rounds`.
    @Test func beerTap_endsOnlyAtTheConfirmation() throws {
        var match = try registry.match(.beerTap, ["rounds": 2], players: 2)
        match.play("T20, T20, T20 | MISS ×3 | T20, T20, T20 | MISS ×3")
        #expect(match.phase == .turnComplete && match.snapshot.round == 2 && match.snapshot.finishReason == nil)
        // Still correctable before the confirmation.
        match.replaceDart(at: 2, with: .treble(20))
        #expect(match.fact(1, "poured") == 60)
        #expect(match.endTurn().events == [.gameFinished(reason: .roundLimit)])
        #expect(match.phase == .finished && match.snapshot.ranks == [1, 2])
        #expect(!match.throwDart(DartRecord(hit: .single(1))).isAccepted && !match.endTurn().isAccepted)
        // A game ended at the round limit has an empty volley (GAMES.md §2.6); the presentation survives it.
        #expect(match.snapshot.turn.darts.isEmpty && match.currentTurn.isEmpty)
        #expect(match.snapshot.turn.summary == nil && match.snapshot.highlights.isEmpty)
        #expect(match.fact(0, "poured") == 460)
    }

    // MARK: Undo, corrections, replay (GAMES.md §2.5)

    @Test func beerTap_undoWalksBackThroughTheFreeGlass() throws {
        var match = try registry.match(.beerTap, players: 2)
        match.play("T20, T20, S20 |")
        #expect(glass(match, 0) == [190, 3, 40, 1] && match.snapshot.currentPlayer == 1)
        match.undo()
        #expect(match.phase == .turnComplete && glass(match, 0) == [190, 3, 40, 1] && match.snapshot.currentPlayer == 0)
        match.undo()
        #expect(match.phase == .throwing && glass(match, 0) == [120, 2, 20, 0] && match.fact(0, "dartsThrown") == 2)
        match.undo()
        match.undo()
        #expect(glass(match, 0) == [0, 0, 0, 0] && !match.canUndo)
        #expect(!match.undo().applied)
    }

    @Test func beerTap_removingADartReopensTheTurn() throws {
        var match = try registry.match(.beerTap, players: 1)
        match.play("T20, T20, T20")
        #expect(match.fact(0, "bonusGlasses") == 1)
        match.removeDart(at: 1)
        #expect(match.turnNotation == ["T20", "T20"] && match.phase == .throwing)
        #expect(glass(match, 0) == [120, 2, 20, 0] && match.fact(0, "dartsThrown") == 2)
        // A correction can also earn the glass.
        match.play("S1")
        #expect(match.fact(0, "bonusGlasses") == 1)
        match.replaceDart(at: 0, with: .single(1))
        #expect(glass(match, 0) == [62, 1, 12, 0])
        match.replaceDart(at: 0, with: .double(20))
        // 101 points, and the glass again.
        #expect(glass(match, 0) == [151, 3, 1, 1])
    }

    @Test func beerTap_replayIsDeterministic() throws {
        var match = try registry.match(.beerTap, ["glassSize": 25, "rounds": 3], players: 3)
        var random = SeededRandom(seed: 2024)
        var snapshots: [GameSnapshot] = []
        while match.phase != .finished {
            if match.phase == .turnComplete || random.nextInt(below: 7) == 0 {
                match.endTurn()
            } else {
                match.throwDart(DartRecord(hit: Hit.all[random.nextInt(below: Hit.all.count)]))
            }
            snapshots.append(match.snapshot)
        }
        let restored = try registry.restoreMatch(match.record)
        #expect(restored.snapshot == match.snapshot && restored.entries == match.entries)
        // Undo everything, one entry at a time: every earlier snapshot comes back, then the initial state.
        for expected in snapshots.dropLast().reversed() {
            match.undo()
            #expect(match.snapshot == expected)
        }
        match.undo()
        #expect(try match.snapshot == registry.match(.beerTap, ["glassSize": 25, "rounds": 3], players: 3).snapshot)
    }

    /// Invariants of §13.3 on a random game: `glasses` and `level` derive from `poured`, and `poured` is the
    /// points of the darts plus one glass per free glass.
    @Test func beerTap_derivedValuesHoldOnRandomGames() throws {
        for seed in 0..<40 as Range<UInt64> {
            var random = SeededRandom(seed: seed)
            let size = [25, 50, 100][random.nextInt(below: 3)]
            let players = 1 + random.nextInt(below: 8)
            var match = try registry.match(.beerTap, ["glassSize": .int(size), "rounds": 4], players: players)
            var pouredByDarts = Array(repeating: 0, count: players)
            var bonus = Array(repeating: 0, count: players)
            while match.phase != .finished {
                let player = match.snapshot.currentPlayer
                let outcome: InputOutcome
                if match.phase == .turnComplete || random.nextInt(below: 6) == 0 {
                    outcome = match.endTurn()
                } else {
                    let hit = Hit.all[random.nextInt(below: Hit.all.count)]
                    outcome = match.throwDart(DartRecord(hit: hit))
                    pouredByDarts[player] += hit.points
                }
                for event in outcome.events {
                    if case .bonusGlass(let who, _) = event { bonus[who] += 1 }
                }
                for index in 0..<players {
                    let poured = pouredByDarts[index] + bonus[index] * size
                    #expect(glass(match, index) == [poured, poured / size, poured % size, bonus[index]])
                }
            }
            let poured = (0..<players).map { pouredByDarts[$0] + bonus[$0] * size }
            #expect(match.snapshot.ranks == poured.map { mine in 1 + poured.filter { $0 > mine }.count })
        }
    }

    /// Everything a later dart depends on is in the facts (ARCHITECTURE.md §4.7): two darts with the same
    /// `effectKey`, followed by the same inputs, lead to the same facts, ranks and events.
    @Test func beerTap_sameEffectKeySameFuture() throws {
        var pairs = 0
        for seed in 0..<60 as Range<UInt64> {
            var random = SeededRandom(seed: seed)
            let size = [25, 50, 100][random.nextInt(below: 3)]
            var match = try registry.match(.beerTap, ["glassSize": .int(size), "rounds": 3], players: 1 + random.nextInt(below: 3))
            for _ in 0..<random.nextInt(below: 12) where match.phase != .finished {
                if match.phase == .turnComplete || random.nextInt(below: 6) == 0 { match.endTurn() }
                else { match.throwDart(DartRecord(hit: Hit.all[random.nextInt(below: Hit.all.count)])) }
            }
            guard match.phase == .throwing else { continue }
            let groups = Dictionary(grouping: Hit.all) { match.effectKey(for: $0) }
            // Same points, same effect: 43 distinct point values (0 included) for the 63 beds.
            #expect(groups.count == Set(Hit.all.map(\.points)).count)
            for group in groups.values where group.count > 1 {
                var first = match, second = match
                first.throwDart(DartRecord(hit: group[0]))
                second.throwDart(DartRecord(hit: group[group.count - 1]))
                pairs += 1
                for _ in 0..<12 {
                    let hit = Hit.all[random.nextInt(below: Hit.all.count)]
                    let confirm = first.phase != .throwing || random.nextInt(below: 5) == 0
                    let a = confirm ? first.endTurn() : first.throwDart(DartRecord(hit: hit))
                    let b = confirm ? second.endTurn() : second.throwDart(DartRecord(hit: hit))
                    #expect(a == b)
                    #expect(first.snapshot.players.map(\.facts) == second.snapshot.players.map(\.facts))
                    #expect(first.snapshot.ranks == second.snapshot.ranks && first.phase == second.phase)
                }
            }
        }
        #expect(pairs > 100)
    }

    /// The rule is as strict as the schema when it is built without the kernel, and takes the defaults of the
    /// missing options: no configuration can make it divide by zero later.
    @Test func beerTap_ruleBuiltOnItsOwn() throws {
        var random = SeededRandom(seed: 0)
        func configuration(_ options: GameOptions, players: Int = 2) -> GameConfiguration {
            GameConfiguration(gameID: .beerTap, options: options, players: testPlayers(players), seed: 0)
        }
        #expect(throws: GameConfigurationError.invalidOptionValue(key: "glassSize")) {
            _ = try BeerTapRules(configuration: configuration(["glassSize": 0]), random: &random)
        }
        #expect(throws: GameConfigurationError.invalidOptionValue(key: "rounds")) {
            _ = try BeerTapRules(configuration: configuration(["rounds": .null]), random: &random)
        }
        #expect(throws: GameConfigurationError.playerCountOutOfRange(allowed: 1...8, actual: 0)) {
            _ = try BeerTapRules(configuration: configuration([:], players: 0), random: &random)
        }
        #expect(throws: GameConfigurationError.unknownOption(key: "maxRounds")) {
            _ = try BeerTapRules(configuration: configuration(["maxRounds": 3]), random: &random)
        }
        let rules = try BeerTapRules(configuration: configuration([:]), random: &random)
        #expect(rules.roundLimit == 5 && rules.ranks() == [1, 1] && !rules.isEliminated(0))
        // Beer Tap draws nothing.
        #expect(random == SeededRandom(seed: 0))
    }

    // MARK: Presentation (GAMES.md §13.7, ARCHITECTURE.md §5.6)

    @Test func beerTap_scoreboard() throws {
        var match = try registry.match(.beerTap, players: 2)
        #expect(match.snapshot.title == LocalizedText(fr: "Tireuse", en: "Beer Tap"))
        #expect(match.snapshot.variant == LocalizedText(fr: "Pinte", en: "Pint"))
        #expect(match.snapshot.highlights.isEmpty && match.snapshot.winnerTitle == nil)
        #expect(match.snapshot.players[0].detail == nil)
        #expect(match.snapshot.players[0].primary == ScoreValue(0, unit: LocalizedText(fr: "verre", en: "glasses")))
        #expect(match.snapshot.turn.summary == LocalizedText(fr: "Volée : 0", en: "Turn: 0"))

        match.play("T20, T20, S20")
        let row = match.snapshot.players[0]
        #expect(row.primary == ScoreValue(3, unit: LocalizedText(fr: "verres", en: "glasses")))
        #expect(row.meter == Meter(value: 40, maximum: 50, style: .bar))
        #expect(row.detail == LocalizedText(fr: "Dernière volée : 140 · 1 offert", en: "Last turn: 140 · 1 free"))
        #expect(row.facts == ["poured": 190, "glasses": 3, "level": 40, "bonusGlasses": 1, "dartsThrown": 3])
        #expect(match.snapshot.turn.summary == LocalizedText(fr: "Volée : 140", en: "Turn: 140"))
        #expect(match.snapshot.turn.darts.map { $0.caption?.text } == ["60", "60", "20"].map { LocalizedText(verbatim: $0) })
        // The dart that fills a glass is the good news of the turn.
        #expect(match.snapshot.turn.darts.map { $0.caption?.tone } == [.positive, .positive, .neutral])
        #expect(match.snapshot.facts.isEmpty && match.snapshot.outcome == nil)

        match.play("| S20, S5, MISS |")
        #expect(match.snapshot.players[1].detail == LocalizedText(fr: "Dernière volée : 25", en: "Last turn: 25"))
        #expect(match.snapshot.players[1].primary == ScoreValue(0, unit: LocalizedText(fr: "verre", en: "glasses")))
        #expect(match.snapshot.players[1].meter == Meter(value: 25, maximum: 50, style: .bar))

        for (size, label) in [(25, LocalizedText(fr: "Demi", en: "Half")), (100, LocalizedText(verbatim: "Litre"))] {
            let other = try registry.match(.beerTap, ["glassSize": .int(size)], players: 1)
            #expect(other.snapshot.variant == label)
            #expect(other.snapshot.players[0].meter == Meter(value: 0, maximum: size, style: .bar))
        }
    }

    @Test func beerTap_results() throws {
        var match = try registry.match(.beerTap, ["rounds": 1], players: 2)
        match.play("T20, T20, T20 | S20, S20, S10")
        #expect(match.snapshot.outcome == nil)
        match.play("|")
        #expect(match.snapshot.outcome == LocalizedText(fr: "Le plus de bière versée : 230 cl, soit 4 verres pleins.",
                                                        en: "Most beer poured: 230 cl, that is 4 full glasses."))
        #expect(match.snapshot.players[0].resultLines == [LocalizedText(fr: "230 cl versés", en: "230 cl poured"),
                                                          LocalizedText(fr: "1 verre offert", en: "1 free glass")])
        #expect(match.snapshot.players[1].resultLines == [LocalizedText(fr: "50 cl versés", en: "50 cl poured")])
        #expect(match.snapshot.winnerTitle == nil)

        var tie = try registry.match(.beerTap, ["rounds": 1], players: 2)
        tie.play("S20 | D10 |")
        #expect(tie.snapshot.ranks == [1, 1])
        #expect(tie.snapshot.outcome == LocalizedText(fr: "Égalité : 20 cl versés chacun.", en: "A tie: 20 cl poured each."))
    }
}
