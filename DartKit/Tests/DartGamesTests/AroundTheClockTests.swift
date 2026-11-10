import Testing
import DartCore
import DartGames
import DartTestSupport

/// GAMES.md §6.9: the seven Around-the-Clock vectors, then every rule paragraph of §6 that the vectors leave aside.
@Suite struct AroundTheClockTests {
    private let registry = GameRegistry.standard

    // MARK: Helpers

    private func ints(_ match: GameMatch, _ name: String) -> [Int] {
        match.snapshot.players.map { row in
            if case .int(let value)? = row.facts[name] { return value }
            return Int.min
        }
    }

    // MARK: ATC-1 to ATC-7

    @Test func atc1_anyBedOfTheTargetAdvancesByOne() throws {
        var match = try registry.match(.aroundTheClock, players: 1)
        let outcomes = match.play("S1, D2, T3")
        #expect(match.fact(0, "progress") == 3)
        #expect(match.fact(0, "target") == 4)
        #expect(match.phase == .turnComplete)
        #expect(outcomes[0].events == [.dartRegistered(player: 0, hit: .single(1)), .targetHit(player: 0, number: 1, advancedBy: 1)])
        #expect(outcomes[1].events == [.dartRegistered(player: 0, hit: .double(2)), .targetHit(player: 0, number: 2, advancedBy: 1)])
        #expect(outcomes[2].events == [.dartRegistered(player: 0, hit: .treble(3)), .targetHit(player: 0, number: 3, advancedBy: 1),
                                       .turnCompleted(player: 0)])
    }

    @Test func atc2_inOrderOnly() throws {
        var match = try registry.match(.aroundTheClock, players: 1)
        let outcomes = match.play("S2, S1, S1")
        // S2 comes too early, the second S1 is useless.
        #expect(match.fact(0, "progress") == 1)
        #expect(match.fact(0, "target") == 2)
        #expect(outcomes[0].events == [.dartRegistered(player: 0, hit: .single(2)), .noEffect(player: 0)])
        #expect(outcomes[1].events == [.dartRegistered(player: 0, hit: .single(1)), .targetHit(player: 0, number: 1, advancedBy: 1)])
        #expect(outcomes[2].events == [.dartRegistered(player: 0, hit: .single(1)), .noEffect(player: 0), .turnCompleted(player: 0)])
    }

    @Test func atc3_jumpsWithTheMultipliers() throws {
        var match = try registry.match(.aroundTheClock, ["multiplierJump": true], players: 1)
        let outcomes = match.play("T1, D4, S6")
        #expect(match.fact(0, "progress") == 6)
        #expect(match.fact(0, "target") == 7)
        #expect(outcomes[0].events == [.dartRegistered(player: 0, hit: .treble(1)), .targetHit(player: 0, number: 1, advancedBy: 3)])
        #expect(outcomes[1].events == [.dartRegistered(player: 0, hit: .double(4)), .targetHit(player: 0, number: 4, advancedBy: 2)])
        #expect(outcomes[2].events == [.dartRegistered(player: 0, hit: .single(6)), .targetHit(player: 0, number: 6, advancedBy: 1),
                                       .turnCompleted(player: 0)])
    }

    @Test func atc4_victoryAndRanking() throws {
        var match = try registry.match(.aroundTheClock, ["multiplierJump": true], players: 2)
        let outcomes = match.play("T1, T4, T7 | S1, S2, MISS | T10, T13, T16 | S3, MISS, MISS | D19")
        #expect(match.phase == .finished && match.snapshot.finishReason == .victory)
        #expect(ints(match, "progress") == [20, 3])
        #expect(match.snapshot.ranks == [1, 2])
        // The game stops on the dart: no `turnCompleted`, and `gameFinished` comes last.
        #expect(outcomes.last?.events == [.dartRegistered(player: 0, hit: .double(19)),
                                          .targetHit(player: 0, number: 19, advancedBy: 2),
                                          .gameFinished(reason: .victory)])
        #expect(match.turnNotation == ["D19"])
    }

    @Test func atc5_finishOnTheBull_theJumpNeverPassesTwenty() throws {
        var match = try registry.match(.aroundTheClock, ["multiplierJump": true, "finishOnBull": true], players: 1)
        var outcomes = match.play("T1, T4, T7 | T10, T13, T16 | T19, S20")
        // 18 + 3 is capped at 20.
        #expect(match.fact(0, "progress") == 20)
        #expect(match.fact(0, "target") == 25)
        // S20 has no effect: the target is the bull now.
        #expect(outcomes.last?.events == [.dartRegistered(player: 0, hit: .single(20)), .noEffect(player: 0)])
        #expect(match.phase == .throwing)

        outcomes = match.play("DB")
        #expect(match.fact(0, "progress") == 21)
        #expect(match.phase == .finished && match.snapshot.finishReason == .victory)
        #expect(outcomes[0].events == [.dartRegistered(player: 0, hit: .innerBull), .targetHit(player: 0, number: 25, advancedBy: 1),
                                       .gameFinished(reason: .victory)])
    }

    @Test func atc6_theBullDoesNotCountBeforeTheEnd() throws {
        var match = try registry.match(.aroundTheClock, ["finishOnBull": true], players: 1)
        let outcomes = match.play("SB, S1, DB")
        #expect(match.fact(0, "progress") == 1)
        #expect(match.fact(0, "target") == 2)
        #expect(outcomes[0].events == [.dartRegistered(player: 0, hit: .outerBull), .noEffect(player: 0)])
        #expect(outcomes[2].events == [.dartRegistered(player: 0, hit: .innerBull), .noEffect(player: 0), .turnCompleted(player: 0)])
    }

    @Test func atc7_roundLimitAndTie() throws {
        var match = try registry.match(.aroundTheClock, ["maxRounds": 1], players: 3)
        let outcomes = match.play("S1, S2, S3 | S1, MISS, MISS | S1, S2, S3 |")
        #expect(match.phase == .finished && match.snapshot.finishReason == .roundLimit)
        #expect(ints(match, "progress") == [3, 1, 3])
        #expect(match.snapshot.ranks == [1, 3, 1])
        #expect(match.snapshot.winners == [0, 2])
        #expect(outcomes.last?.events == [.gameFinished(reason: .roundLimit)])
    }

    // MARK: Options and players (GAMES.md §6.1, §6.2)

    @Test func defaults_winOnTheTwenty_noJump_noRoundLimit() throws {
        let match = try registry.match(.aroundTheClock, players: 2)
        #expect(match.configuration.options == ["finishOnBull": false, "multiplierJump": false, "maxRounds": .null])
        #expect(match.snapshot.roundLimit == nil)
        #expect(ints(match, "progress") == [0, 0] && ints(match, "target") == [1, 1] && ints(match, "dartsThrown") == [0, 0])
        #expect(match.snapshot.ranks == [1, 1])
    }

    @Test func players_fromOneToEight_andRefusedOptions() throws {
        for players in 1...8 {
            let match = try registry.match(.aroundTheClock, players: players)
            #expect(match.snapshot.players.count == players && match.phase == .throwing)
        }
        for players in [0, 9] {
            #expect(throws: GameConfigurationError.playerCountOutOfRange(allowed: 1...8, actual: players)) {
                try registry.match(.aroundTheClock, players: players)
            }
        }
        let refused: [(String, OptionValue)] = [("finishOnBull", 1), ("multiplierJump", "yes"), ("maxRounds", 0),
                                                ("maxRounds", 100), ("maxRounds", false)]
        for (key, value) in refused {
            #expect(throws: GameConfigurationError.invalidOptionValue(key: key), "\(key): \(value)") {
                try registry.match(.aroundTheClock, GameOptions([key: value]), players: 2)
            }
        }
        // A rule built without the kernel refuses the same configurations, and draws nothing.
        var random = SeededRandom(seed: 5)
        #expect(throws: GameConfigurationError.self) {
            try AroundTheClockRules(configuration: GameConfiguration(gameID: .aroundTheClock, players: testPlayers(9), seed: 5),
                                    random: &random)
        }
        _ = try AroundTheClockRules(configuration: GameConfiguration(gameID: .aroundTheClock, players: testPlayers(3), seed: 5),
                                    random: &random)
        #expect(random == SeededRandom(seed: 5))
    }

    // MARK: Effect of a dart (GAMES.md §6.4)

    @Test func wholeGame_oneToTwentyInOrder_winsOnTheTwenty() throws {
        var match = try registry.match(.aroundTheClock, players: 1)
        for number in 1...20 {
            if match.phase == .turnComplete { match.endTurn() }
            #expect(match.fact(0, "target") == .int(number) && match.fact(0, "progress") == .int(number - 1))
            // Every other number, the bulls and a MISS do nothing; the three beds of the target advance by one.
            for hit in Hit.all {
                var copy = match
                let events = copy.throwDart(DartRecord(hit: hit)).events
                if hit.number == number {
                    #expect(events.prefix(2) == [.dartRegistered(player: 0, hit: hit), .targetHit(player: 0, number: number, advancedBy: 1)])
                    #expect(copy.fact(0, "progress") == .int(number))
                } else {
                    #expect(events.prefix(2) == [.dartRegistered(player: 0, hit: hit), .noEffect(player: 0)])
                    #expect(copy.fact(0, "progress") == .int(number - 1))
                }
            }
            let outcome = match.throwDart(DartRecord(hit: .single(number)))
            if number == 20 {
                #expect(outcome.events == [.dartRegistered(player: 0, hit: .single(20)), .targetHit(player: 0, number: 20, advancedBy: 1),
                                           .gameFinished(reason: .victory)])
            }
        }
        #expect(match.phase == .finished && match.snapshot.finishReason == .victory)
        #expect(match.fact(0, "progress") == 20 && match.fact(0, "target") == 0 && match.fact(0, "dartsThrown") == 20)
        // Twenty darts: six full turns and two darts of the seventh; the winning volley stays.
        #expect(match.snapshot.round == 7 && match.turnNotation == ["S19", "S20"])
        #expect(match.throwDart(DartRecord(hit: .single(1))) == .rejected(.gameFinished))
        #expect(match.endTurn() == .rejected(.gameFinished))
    }

    @Test func withoutFinishOnBull_theBullNeverCounts() throws {
        var match = try registry.match(.aroundTheClock, ["multiplierJump": true], players: 1)
        match.play("SB, DB, T1 | T4, T7, T10 | T13, T16, SB")
        #expect(match.fact(0, "progress") == 18)
        let outcomes = match.play("| DB, T19")
        #expect(outcomes[1].events == [.dartRegistered(player: 0, hit: .innerBull), .noEffect(player: 0)])
        // 18 + 3 is capped at 20, which is the goal: the game is won, without any bull.
        #expect(outcomes[2].events == [.dartRegistered(player: 0, hit: .treble(19)), .targetHit(player: 0, number: 19, advancedBy: 2),
                                       .gameFinished(reason: .victory)])
        #expect(match.fact(0, "progress") == 20 && match.fact(0, "target") == 0)
    }

    @Test(arguments: [Hit.outerBull, Hit.innerBull])
    func finishOnBull_eitherBullFinishes(bull: Hit) throws {
        var match = try registry.match(.aroundTheClock, ["finishOnBull": true, "multiplierJump": true], players: 2)
        match.play("T1, T4, T7 | MISS | T10, T13, T16 | MISS | D19")
        #expect(ints(match, "progress") == [20, 0] && ints(match, "target") == [25, 1])
        #expect(match.phase == .throwing)
        // Only a bull does something now: the 20 is done, and no number is the target any more.
        for hit in Hit.all where !hit.isBull {
            var copy = match
            #expect(copy.throwDart(DartRecord(hit: hit)).events.contains(.noEffect(player: 0)), "\(hit)")
            #expect(copy.fact(0, "progress") == 20)
        }
        // The inner bull is not "a double of the bull" here: both bulls validate the last target, by one.
        let outcome = match.throwDart(DartRecord(hit: bull))
        #expect(outcome.events == [.dartRegistered(player: 0, hit: bull), .targetHit(player: 0, number: 25, advancedBy: 1),
                                   .gameFinished(reason: .victory)])
        #expect(ints(match, "progress") == [21, 0] && ints(match, "target") == [0, 1])
        #expect(match.snapshot.ranks == [1, 2] && match.snapshot.finishReason == .victory)
    }

    @Test func multiplierJump_isCappedAtTwenty_fromEveryProgress() throws {
        for progress in 0..<20 {
            for finishOnBull in [false, true] {
                var base = try registry.match(.aroundTheClock, ["multiplierJump": true, "finishOnBull": .bool(finishOnBull),
                                                                "maxRounds": .null], players: 1)
                for number in stride(from: 1, through: progress, by: 1) {
                    if base.phase == .turnComplete { base.endTurn() }
                    base.throwDart(DartRecord(hit: .single(number)))
                }
                if base.phase == .turnComplete { base.endTurn() }
                #expect(base.fact(0, "progress") == .int(progress))
                let target = progress + 1
                for hit in [Hit.single(target), .double(target), .treble(target)] {
                    var match = base
                    let reached = min(20, progress + hit.multiplier)
                    let events = match.throwDart(DartRecord(hit: hit)).events
                    #expect(events.prefix(2) == [.dartRegistered(player: 0, hit: hit),
                                                 .targetHit(player: 0, number: target, advancedBy: reached - progress)])
                    #expect(match.fact(0, "progress") == .int(reached))
                    // At 20 the game is won, unless a bull is still needed: the jump never passes the bull.
                    if reached == 20 {
                        #expect((match.phase == .finished) == !finishOnBull)
                        #expect(match.fact(0, "target") == (finishOnBull ? 25 : 0))
                    } else {
                        #expect(match.fact(0, "target") == .int(reached + 1) && match.phase != .finished)
                    }
                }
            }
        }
    }

    @Test func multiplierJump_off_isTheDefault() throws {
        var match = try registry.match(.aroundTheClock, players: 1)
        match.play("T1, D2, T3")
        #expect(match.fact(0, "progress") == 3)
        // With the jump, the skipped numbers are validated: after T1 the target is the 4, and the 2 does nothing.
        var jump = try registry.match(.aroundTheClock, ["multiplierJump": true], players: 1)
        let outcomes = jump.play("T1, D2, T3")
        #expect(jump.fact(0, "progress") == 3 && jump.fact(0, "target") == 4)
        #expect(outcomes[1].events == [.dartRegistered(player: 0, hit: .double(2)), .noEffect(player: 0)])
    }

    @Test func dartsThrown_countsEveryDart_ofEveryPlayer() throws {
        var match = try registry.match(.aroundTheClock, players: 3)
        match.play("S1, MISS, SB | S5 | | S2, S3, S4 | MISS, MISS")
        #expect(ints(match, "dartsThrown") == [6, 3, 0])
        #expect(ints(match, "progress") == [4, 0, 0] && ints(match, "target") == [5, 1, 1])
    }

    // MARK: Victory, ranking, round limit (GAMES.md §6.5, §6.6)

    @Test func victory_stopsTheGameOnTheDart_theOthersDoNotFinishTheRound() throws {
        var match = try registry.match(.aroundTheClock, ["multiplierJump": true], players: 3)
        match.play("T1, T4, T7 | T1, T4, MISS | S1, MISS, MISS | T10, T13, T16 | T7, T10, T13 | S2, S3, MISS | S19")
        #expect(match.phase == .throwing && ints(match, "progress") == [19, 15, 3])
        #expect(match.snapshot.ranks == [1, 2, 3])
        let outcome = match.throwDart(DartRecord(hit: .single(20)))
        #expect(outcome.events.last == .gameFinished(reason: .victory))
        #expect(!outcome.events.contains(.turnCompleted(player: 0)))
        #expect(match.phase == .finished && match.snapshot.winners == [0] && match.snapshot.round == 3)
        #expect(match.turnNotation == ["S19", "S20"])
    }

    @Test func ranking_byProgress_withTies_atAnyTime() throws {
        var match = try registry.match(.aroundTheClock, players: 4)
        match.play("S1, S2, MISS | S1, MISS, MISS | S1, S2, MISS | MISS")
        #expect(match.snapshot.ranks == [1, 3, 1, 4])
        match.play("| S3")
        #expect(match.snapshot.ranks == [1, 3, 2, 4])
    }

    @Test func roundLimit_isOptional() throws {
        var unlimited = try registry.match(.aroundTheClock, players: 2)
        for _ in 0..<200 { unlimited.endTurn() }
        #expect(unlimited.phase == .throwing && unlimited.snapshot.round == 101)
        var limited = try registry.match(.aroundTheClock, ["maxRounds": 3], players: 2)
        #expect(limited.snapshot.roundLimit == 3)
        limited.play("S1 | | S2 | S1 | | S2, S3")
        #expect(limited.phase == .throwing && limited.snapshot.round == 3)
        // The limit only acts at the confirmation.
        #expect(limited.endTurn().events == [.turnCompleted(player: 1), .gameFinished(reason: .roundLimit)])
        #expect(ints(limited, "progress") == [2, 3] && limited.snapshot.ranks == [2, 1])
        #expect(limited.snapshot.finishReason == .roundLimit && limited.snapshot.turn.darts.isEmpty)
    }

    // MARK: Undo and corrections (GAMES.md §2.5)

    @Test func corrections_replayTheWholeTurn() throws {
        var match = try registry.match(.aroundTheClock, players: 1)
        match.play("S1, S2, S3")
        #expect(match.fact(0, "progress") == 3)
        // The first dart missed: the 2 and the 3 came too early.
        #expect(match.replaceDart(at: 0, with: .miss).applied)
        #expect(match.fact(0, "progress") == 0 && match.fact(0, "dartsThrown") == 3 && match.phase == .turnComplete)
        #expect(match.removeDart(at: 0).applied)
        #expect(match.turnNotation == ["S2", "S3"] && match.fact(0, "dartsThrown") == 2 && match.phase == .throwing)
        #expect(match.replaceDart(at: 0, with: .treble(1)).applied && match.replaceDart(at: 1, with: .double(2)).applied)
        #expect(match.fact(0, "progress") == 2)
    }

    @Test func undo_ofTheWinningDart_reopensTheGame() throws {
        var match = try registry.match(.aroundTheClock, ["multiplierJump": true], players: 1)
        match.play("T1, T4, T7 | T10, T13, T16 | T19")
        #expect(match.phase == .finished)
        let won = match.snapshot
        match.undo()
        #expect(match.phase == .throwing && match.fact(0, "progress") == 18 && match.snapshot.finishReason == nil)
        // A correction of the winning volley: the dart that won was a single 19, the game goes on.
        match.play("T19")
        #expect(match.snapshot == won)
        #expect(match.replaceDart(at: 0, with: .single(19)).applied)
        #expect(match.phase == .throwing && match.fact(0, "progress") == 19 && match.fact(0, "target") == 20)
        // A correction that wins drops the darts that follow.
        match.play("MISS, MISS")
        let edit = match.replaceDart(at: 0, with: .double(19))
        #expect(edit.applied && edit.dropped.count == 2 && match.phase == .finished && match.turnNotation == ["D19"])
        while match.canUndo { match.undo() }
        #expect(try match.snapshot == registry.match(.aroundTheClock, ["multiplierJump": true], players: 1).snapshot)
    }

    @Test func effectKeys_followTheAdvance() throws {
        var plain = try registry.match(.aroundTheClock, players: 2)
        plain.play("S1")
        // Without the jump the three beds of the target are one and the same dart.
        let plainKeys = Dictionary(grouping: Hit.all, by: { plain.effectKey(for: $0) })
        #expect(plainKeys.values.map(\.count).sorted() == [3, 60])
        #expect(plain.effectKey(for: .single(2)) == plain.effectKey(for: .treble(2)))
        var jump = try registry.match(.aroundTheClock, ["multiplierJump": true], players: 2)
        jump.play("S1")
        let jumpKeys = Dictionary(grouping: Hit.all, by: { jump.effectKey(for: $0) })
        #expect(jumpKeys.values.map(\.count).sorted() == [1, 1, 1, 60])
    }

    // MARK: Presentation (GAMES.md §6.7, ARCHITECTURE.md §5.5, §5.6)

    @Test func highlights_theTargetOfTheCurrentPlayer() throws {
        var match = try registry.match(.aroundTheClock, ["finishOnBull": true, "multiplierJump": true], players: 2)
        #expect(match.snapshot.highlights == [BoardHighlight(zone: .sector(1), role: .target)])
        match.play("T1")
        // The target moves at once.
        #expect(match.snapshot.highlights == [BoardHighlight(zone: .sector(4), role: .target)])
        match.play("T4, T7")
        #expect(match.phase == .turnComplete && match.snapshot.highlights == [BoardHighlight(zone: .sector(10), role: .target)])
        // Each player has their own target.
        match.endTurn()
        #expect(match.snapshot.highlights == [BoardHighlight(zone: .sector(1), role: .target)])
        match.play("| T10, T13, T16 | | T19")
        // After the 20, the bull: both bulls, as one zone.
        #expect(match.snapshot.highlights == [BoardHighlight(zone: .bull, role: .target)])
        #expect(match.snapshot.highlights[0].zone.contains(.outerBull) && match.snapshot.highlights[0].zone.contains(.innerBull))
        match.play("SB")
        #expect(match.phase == .finished && match.snapshot.highlights.isEmpty)
    }

    @Test func highlights_areExactlyTheHitsThatAdvance() throws {
        for finishOnBull in [false, true] {
            var match = try registry.match(.aroundTheClock, ["finishOnBull": .bool(finishOnBull), "maxRounds": .null], players: 1)
            while match.phase != .finished {
                if match.phase == .turnComplete { match.endTurn() }
                let highlights = match.snapshot.highlights
                #expect(highlights.count == 1 && highlights[0].owner == nil && highlights[0].label == nil)
                var next: Hit?
                for hit in Hit.all {
                    var copy = match
                    let advances = !copy.throwDart(DartRecord(hit: hit)).events.contains(.noEffect(player: 0))
                    #expect(highlights[0].zone.contains(hit) == advances, "\(hit)")
                    if advances { next = hit }
                }
                match.throwDart(DartRecord(hit: try #require(next)))
            }
            #expect(match.fact(0, "progress") == .int(finishOnBull ? 21 : 20))
        }
    }

    @Test func scoreboard_targetProgressBarAndDarts() throws {
        var match = try registry.match(.aroundTheClock, ["finishOnBull": true, "multiplierJump": true], players: 2)
        #expect(match.snapshot.title == LocalizedText(fr: "Tour de l'horloge", en: "Around the Clock"))
        #expect(match.snapshot.variant == nil)
        #expect(match.snapshot.objective == LocalizedText(fr: "Cible : 1", en: "Target: 1"))
        let unit = LocalizedText(fr: "cible", en: "target")
        #expect(match.snapshot.players[0].primary == ScoreValue("1", unit: unit))
        #expect(match.snapshot.players[0].meter == Meter(value: 0, maximum: 21, style: .bar))
        #expect(match.snapshot.players[0].detail == LocalizedText(fr: "0 fléchette", en: "0 darts"))

        match.play("T1, S2, T4")
        #expect(match.snapshot.players[0].primary == ScoreValue("7", unit: unit))
        #expect(match.snapshot.players[0].meter == Meter(value: 6, maximum: 21, style: .bar))
        #expect(match.snapshot.players[0].detail == LocalizedText(fr: "3 fléchettes", en: "3 darts"))
        #expect(match.snapshot.players[0].facts == ["progress": 6, "target": 7, "dartsThrown": 3])
        #expect(match.snapshot.objective == LocalizedText(fr: "Cible : 7", en: "Target: 7"))
        #expect(match.snapshot.turn.darts.map(\.caption) == [
            DartCaption(LocalizedText(fr: "+3 numéros", en: "+3 numbers"), tone: .positive),
            DartCaption(LocalizedText(fr: "Sans effet", en: "No effect"), tone: .neutral),
            DartCaption(LocalizedText(fr: "+3 numéros", en: "+3 numbers"), tone: .positive),
        ])
        match.play("| S1")
        #expect(match.snapshot.objective == LocalizedText(fr: "Cible : 2", en: "Target: 2"))
        #expect(match.snapshot.turn.darts.map(\.caption) == [DartCaption(LocalizedText(fr: "1 validé", en: "1 done"), tone: .positive)])
        #expect(match.snapshot.players[1].detail == LocalizedText(fr: "1 fléchette", en: "1 dart"))

        match.play("| T7, T10, T13 | | T16, T19")
        #expect(match.snapshot.players[0].primary == ScoreValue("Bull", unit: unit))
        #expect(match.snapshot.objective == LocalizedText(fr: "Cible : bull", en: "Target: bull"))
        #expect(match.snapshot.players[0].meter == Meter(value: 20, maximum: 21, style: .bar))
        // T19 from 18: one number was left, the caption says so.
        #expect(match.snapshot.turn.darts.last?.caption == DartCaption(LocalizedText(fr: "+2 numéros", en: "+2 numbers"), tone: .positive))
        match.play("DB")
        #expect(match.phase == .finished)
        #expect(match.snapshot.players[0].primary == ScoreValue("✓"))
        #expect(match.snapshot.players[0].meter == Meter(value: 21, maximum: 21, style: .bar))
        #expect(match.snapshot.turn.darts.last?.caption == DartCaption(LocalizedText(fr: "Bull validé", en: "Bull done"), tone: .positive))
        #expect(match.snapshot.objective == nil)
        #expect(match.snapshot.outcome == LocalizedText(fr: "Premier arrivé au bout, en 9 fléchettes.", en: "First to the end, in 9 darts."))
        #expect(match.snapshot.players[0].resultLines == [LocalizedText(verbatim: "21 / 21"), LocalizedText(fr: "9 fléchettes", en: "9 darts")])
        #expect(match.snapshot.players[1].resultLines == [LocalizedText(verbatim: "1 / 21"), LocalizedText(fr: "1 fléchette", en: "1 dart")])
        #expect(match.snapshot.players.allSatisfy { $0.badges.isEmpty && !$0.isEliminated })
        #expect(match.snapshot.facts.isEmpty && match.snapshot.winnerTitle == nil)
    }

    /// After a game ended at the round limit the kernel's volley is empty while the rule's per-turn state is still
    /// that of the last turn (ARCHITECTURE.md §4.7).
    @Test func results_roundLimit_emptyVolleyAndOutcome() throws {
        var match = try registry.match(.aroundTheClock, ["maxRounds": 1], players: 2)
        match.play("S1, S2, MISS | S1, MISS, MISS")
        #expect(match.snapshot.turn.darts.count == 3 && match.snapshot.outcome == nil)
        match.endTurn()
        #expect(match.phase == .finished && match.snapshot.turn.darts.isEmpty && match.currentTurn.isEmpty)
        #expect(match.snapshot.highlights.isEmpty)
        #expect(match.snapshot.outcome == LocalizedText(fr: "Le plus avancé à la limite de manches : 2 / 20.",
                                                        en: "Furthest at the round limit: 2 / 20."))
        match.undo()
        #expect(match.phase == .turnComplete && match.snapshot.turn.darts.compactMap(\.caption).count == 3)

        var tie = try registry.match(.aroundTheClock, ["maxRounds": 1], players: 2)
        tie.play("S1 | S1 |")
        #expect(tie.snapshot.ranks == [1, 1])
        #expect(tie.snapshot.outcome == LocalizedText(fr: "Égalité à la limite de manches : 1 / 20.", en: "Tie at the round limit: 1 / 20."))
    }

    // MARK: Properties on random journals

    /// Random games against a few lines of arithmetic written from GAMES.md §6.3 and §6.4, with undo and replay.
    @Test func randomGames_matchAnIndependentCount_andReplay() throws {
        var random = SeededRandom(seed: 2024)
        var victories = 0
        for game in 0..<80 {
            let players = 1 + random.nextInt(below: 8)
            let finishOnBull = random.nextInt(below: 2) == 0
            let jump = random.nextInt(below: 2) == 0
            let limit: OptionValue = random.nextInt(below: 3) == 0 ? .int(1 + random.nextInt(below: 12)) : .null
            var match = try registry.match(.aroundTheClock, ["finishOnBull": .bool(finishOnBull), "multiplierJump": .bool(jump),
                                                             "maxRounds": limit], players: players)
            var progress = Array(repeating: 0, count: players)
            var darts = Array(repeating: 0, count: players)
            var snapshots = [match.snapshot]
            var inputs = 0
            while match.phase != .finished && inputs < 700 {
                inputs += 1
                let player = match.snapshot.currentPlayer
                if match.phase == .turnComplete || random.nextInt(below: 15) == 0 {
                    match.endTurn()
                } else {
                    let done = progress[player]
                    // Mostly the target, so that games end; sometimes anything.
                    let roll = random.nextInt(below: 10)
                    let hit: Hit
                    if roll < 7 {
                        hit = done >= 20 ? (roll % 2 == 0 ? .outerBull : .innerBull)
                                         : [Hit.single(done + 1), .double(done + 1), .treble(done + 1)][random.nextInt(below: 3)]
                    } else {
                        hit = Hit.all[random.nextInt(below: Hit.all.count)]
                    }
                    #expect(match.throwDart(DartRecord(hit: hit)).isAccepted)
                    darts[player] += 1
                    if done < 20, hit.number == done + 1 {
                        progress[player] = min(20, done + (jump ? hit.multiplier : 1))
                    } else if done == 20, finishOnBull, hit.isBull {
                        progress[player] = 21
                    }
                    let goal = finishOnBull ? 21 : 20
                    #expect((match.phase == .finished) == (progress[player] == goal), "game \(game)")
                    if progress[player] == goal {
                        victories += 1
                        #expect(match.snapshot.finishReason == .victory && match.snapshot.winners == [player])
                    }
                }
                #expect(ints(match, "progress") == progress && ints(match, "dartsThrown") == darts, "game \(game)")
                #expect(ints(match, "target") == progress.map { $0 < 20 ? $0 + 1 : ($0 == 20 && finishOnBull ? 25 : 0) })
                snapshots.append(match.snapshot)
            }
            let best = progress.max() ?? 0
            #expect(match.snapshot.winners == progress.indices.filter { progress[$0] == best })
            #expect(try registry.restoreMatch(match.record).snapshot == match.snapshot)
            for index in stride(from: match.entries.count - 1, through: 0, by: -1) {
                match.undo()
                #expect(match.snapshot == snapshots[index])
            }
        }
        #expect(victories >= 20)
    }

    /// A pseudo-random Around-the-Clock input: mostly the target of the current player.
    private static func botInput(for match: GameMatch, random: inout SeededRandom) -> GameInput {
        if match.phase == .turnComplete || random.nextInt(below: 16) == 0 { return .endTurn }
        var target = 0
        if case .int(let value)? = match.fact(match.snapshot.currentPlayer, "target") { target = value }
        let roll = random.nextInt(below: 10)
        if roll >= 7 || target == 0 { return .dart(Hit.all[random.nextInt(below: Hit.all.count)]) }
        if target == 25 { return .dart(roll % 2 == 0 ? .outerBull : .innerBull) }
        return .dart([Hit.single(target), .double(target), .treble(target)][random.nextInt(below: 3)])
    }

    @Test func randomGames_sameEffectKey_sameFuture_positionsIgnored() throws {
        var setup = SeededRandom(seed: 606)
        for game in 0..<24 {
            let players = 1 + setup.nextInt(below: 8)
            let options: GameOptions = [
                "finishOnBull": .bool(game % 2 == 0), "multiplierJump": .bool(game % 4 < 2),
                "maxRounds": game % 3 == 0 ? .int(1 + setup.nextInt(below: 10)) : .null,
            ]
            var match = try registry.match(.aroundTheClock, options, players: players)
            var bot = SeededRandom(seed: setup.next())
            var inputs = 0
            while match.phase != .finished && inputs < 500 {
                inputs += 1
                if inputs % 6 == 1 {
                    KillerTestProperties.expectSameEffectKeySameFuture(match, botSeed: UInt64(game * 1_000 + inputs),
                                                                       bot: Self.botInput)
                }
                #expect(match.killerApply(Self.botInput(for: match, random: &bot)).isAccepted)
                KillerTestProperties.expectWellFormed(ranks: match.snapshot.ranks, players: players)
                #expect(match.snapshot.turn.darts.map(\.hit) == match.currentTurn.map(\.hit))
                #expect(match.snapshot.highlights.isEmpty == (match.phase == .finished))
                #expect(match.snapshot.turn.darts.allSatisfy { $0.caption != nil })
            }
            if match.phase == .finished {
                #expect(!match.killerApply(.endTurn).isAccepted && !match.killerApply(.dart(.treble(20))).isAccepted)
            }
            KillerTestProperties.expectPositionsIgnored(from: try registry.match(.aroundTheClock, options, players: players),
                                                        journal: match.entries)
        }
    }
}
