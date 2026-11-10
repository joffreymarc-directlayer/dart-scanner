import Foundation
import Testing
import DartCore
import DartGames
import DartTestSupport

/// GAMES.md §7.9: the seven Shanghai vectors, then every rule paragraph of §7 that the vectors leave aside.
@Suite struct ShanghaiTests {
    private let registry = GameRegistry.standard

    // MARK: Helpers

    private func points(_ match: GameMatch) -> [Int] {
        match.snapshot.players.map { row in
            if case .int(let value)? = row.facts["points"] { return value }
            return Int.min
        }
    }

    /// A game brought to the start of `round` by empty turns.
    private func match(atRound round: Int, _ options: GameOptions = [:], players: Int = 1) throws -> GameMatch {
        var match = try registry.match(.shanghai, options, players: players)
        for _ in 0..<((round - 1) * players) {
            match.endTurn()
        }
        #expect(match.snapshot.round == round && match.snapshot.currentPlayer == 0 && match.phase == .throwing)
        return match
    }

    // MARK: SHA-1 to SHA-7

    @Test(arguments: ["S1, D1, T1", "T1, D1, S1"])
    func sha1_shanghaiInRoundOne(script: String) throws {
        var match = try registry.match(.shanghai, players: 2)
        let outcomes = match.play(script)
        #expect(match.phase == .finished && match.snapshot.finishReason == .victory)
        #expect(points(match) == [6, 0])
        #expect(match.snapshot.ranks == [1, 2])
        let last = try #require(Hit(notation: script.components(separatedBy: ", ")[2]))
        #expect(outcomes[2].events == [.dartRegistered(player: 0, hit: last), .targetScored(player: 0, points: last.points),
                                       .shanghai(player: 0), .gameFinished(reason: .victory)])
    }

    @Test func sha1_eventsOfTheThirdDart() throws {
        var match = try registry.match(.shanghai, players: 2)
        let outcomes = match.play("S1, D1, T1")
        #expect(outcomes[0].events == [.dartRegistered(player: 0, hit: .single(1)), .targetScored(player: 0, points: 1)])
        #expect(outcomes[1].events == [.dartRegistered(player: 0, hit: .double(1)), .targetScored(player: 0, points: 2)])
        #expect(outcomes[2].events == [.dartRegistered(player: 0, hit: .treble(1)), .targetScored(player: 0, points: 3),
                                       .shanghai(player: 0), .gameFinished(reason: .victory)])
        // The game ended on a dart: the winning volley stays, and every input is refused.
        #expect(match.turnNotation == ["S1", "D1", "T1"] && match.snapshot.turn.darts.count == 3)
        #expect(match.endTurn() == .rejected(.gameFinished))
        #expect(match.throwDart(DartRecord(hit: .single(1))) == .rejected(.gameFinished))
    }

    @Test func sha2_onlyTheNumberOfTheRoundCounts() throws {
        var match = try registry.match(.shanghai, players: 2)
        let outcomes = match.play("T1, T1, S1 | S20, S18, MISS")
        #expect(points(match) == [7, 0])
        // No Shanghai: two trebles and a single.
        #expect(!outcomes.flatMap(\.events).contains(.shanghai(player: 0)))
        #expect(match.phase == .turnComplete && match.snapshot.currentPlayer == 1 && match.snapshot.round == 1)
        // Traditional: the neighbours 20 and 18 of the 1 are worth nothing.
        #expect(outcomes[4].events == [.dartRegistered(player: 1, hit: .single(20)), .noEffect(player: 1)])
        #expect(outcomes[5].events == [.dartRegistered(player: 1, hit: .single(18)), .noEffect(player: 1)])
        #expect(outcomes[6].events == [.dartRegistered(player: 1, hit: .miss), .noEffect(player: 1), .turnCompleted(player: 1)])
    }

    @Test func sha3_lite_neighboursAreWorthTheSingleOfTheTarget() throws {
        var match = try registry.match(.shanghai, ["variant": "lite"], players: 2)
        let outcomes = match.play("S20, T18, D1 | S5, S4, MISS")
        // Neighbours of 1: 20 and 18. 1 + 1 + 2.
        #expect(points(match) == [4, 0])
        #expect(outcomes[0].events == [.dartRegistered(player: 0, hit: .single(20)), .neighbourHit(player: 0, points: 1)])
        // Whatever the bed: a treble of a neighbour is still worth the single of the target.
        #expect(outcomes[1].events == [.dartRegistered(player: 0, hit: .treble(18)), .neighbourHit(player: 0, points: 1)])
        #expect(outcomes[2].events == [.dartRegistered(player: 0, hit: .double(1)), .targetScored(player: 0, points: 2),
                                       .turnCompleted(player: 0)])
        // 5 and 4 are two sectors away from the 1.
        #expect(outcomes[4].events == [.dartRegistered(player: 1, hit: .single(5)), .noEffect(player: 1)])
        #expect(outcomes[5].events == [.dartRegistered(player: 1, hit: .single(4)), .noEffect(player: 1)])
    }

    @Test func sha4_lite_roundSeven() throws {
        var match = try registry.match(.shanghai, ["variant": "lite"], players: 1)
        match.play("MISS | MISS | MISS | MISS | MISS | MISS | T19, S7, T7")
        #expect(match.snapshot.round == 7)
        // Neighbours of 7: 19 and 16. 7 + 7 + 21.
        #expect(points(match) == [35])
    }

    @Test func sha5_lite_aNeighbourDoesNotMakeAShanghai() throws {
        var match = try registry.match(.shanghai, ["variant": "lite"], players: 1)
        let outcomes = match.play("MISS | S17, D2, T2")
        #expect(match.snapshot.round == 2)
        #expect(points(match) == [12])
        #expect(match.phase == .turnComplete)
        #expect(match.snapshot.finishReason == nil)
        #expect(outcomes[2].events == [.dartRegistered(player: 0, hit: .single(17)), .neighbourHit(player: 0, points: 2)])
        #expect(outcomes[4].events == [.dartRegistered(player: 0, hit: .treble(2)), .targetScored(player: 0, points: 6),
                                       .turnCompleted(player: 0)])
    }

    @Test func sha6_normalEnd() throws {
        var match = try registry.match(.shanghai, ["rounds": 2], players: 2)
        match.play("S1, S1, MISS | T1, MISS, MISS | D2, MISS, S2 | S2, S2, MISS")
        #expect(points(match) == [8, 7])
        #expect(match.phase == .turnComplete)
        #expect(match.endTurn().events == [.gameFinished(reason: .roundLimit)])
        #expect(match.phase == .finished && match.snapshot.finishReason == .roundLimit)
        #expect(match.snapshot.ranks == [1, 2])
        #expect(match.snapshot.turn.darts.isEmpty && match.currentTurn.isEmpty)
    }

    @Test func sha7_aShanghaiWinsEvenWithFewerPoints() throws {
        var match = try registry.match(.shanghai, ["rounds": 2], players: 2)
        let outcomes = match.play("T1, T1, T1 | MISS ×3 | T2, T2, T2 | S2, T2, D2")
        #expect(points(match) == [27, 12])
        #expect(match.phase == .finished && match.snapshot.finishReason == .victory)
        #expect(match.snapshot.ranks == [2, 1])
        #expect(outcomes.last?.events == [.dartRegistered(player: 1, hit: .double(2)), .targetScored(player: 1, points: 4),
                                          .shanghai(player: 1), .gameFinished(reason: .victory)])
    }

    // MARK: Options and players (GAMES.md §7.1, §7.2)

    @Test func rounds_defaultSeven_anyValueFromOneToTwenty() throws {
        #expect(try registry.match(.shanghai, players: 2).snapshot.roundLimit == 7)
        for rounds in 1...20 {
            let match = try registry.match(.shanghai, ["rounds": .int(rounds)], players: 2)
            #expect(match.snapshot.roundLimit == rounds && match.snapshot.round == 1)
            #expect(match.configuration.options == ["rounds": .int(rounds), "variant": "traditional"])
        }
        // The schema lets a custom value through; the engine refuses what it cannot play.
        let refused: [OptionValue] = [0, 21, -3, 99, "7", .null, true, .strings(["7"])]
        for value in refused {
            #expect(throws: GameConfigurationError.invalidOptionValue(key: "rounds"), "\(value)") {
                try registry.match(.shanghai, ["rounds": value], players: 2)
            }
        }
        #expect(throws: GameConfigurationError.invalidOptionValue(key: "variant")) {
            try registry.match(.shanghai, ["variant": "pro"], players: 2)
        }
        // The limit is `rounds`: there is no `maxRounds` option.
        #expect(throws: GameConfigurationError.unknownOption(key: "maxRounds")) {
            try registry.match(.shanghai, ["maxRounds": 5], players: 2)
        }
    }

    @Test func players_fromOneToEight() throws {
        for players in 1...8 {
            let match = try registry.match(.shanghai, players: players)
            #expect(points(match) == Array(repeating: 0, count: players))
            #expect(match.snapshot.ranks == Array(repeating: 1, count: players))
            #expect(match.phase == .throwing && match.snapshot.currentPlayer == 0 && match.snapshot.round == 1)
        }
        for players in [0, 9] {
            #expect(throws: GameConfigurationError.playerCountOutOfRange(allowed: 1...8, actual: players)) {
                try registry.match(.shanghai, players: players)
            }
        }
        // A rule built without the kernel refuses the same configurations.
        var random = SeededRandom(seed: 0)
        #expect(throws: GameConfigurationError.invalidOptionValue(key: "rounds")) {
            try ShanghaiRules(configuration: GameConfiguration(gameID: .shanghai, options: ["rounds": 25],
                                                               players: testPlayers(2), seed: 0), random: &random)
        }
        // Shanghai draws nothing.
        #expect(random == SeededRandom(seed: 0))
    }

    // MARK: Effect of a dart (GAMES.md §7.4)

    @Test func everyRound_theNumberOfTheRoundScoresItsValueTimesTheMultiplier() throws {
        var match = try registry.match(.shanghai, ["rounds": 20], players: 1)
        var total = 0
        for round in 1...20 {
            #expect(match.snapshot.round == round)
            // Every other number, the bulls and a MISS do nothing in the traditional variant.
            for hit in Hit.all where hit.number != round {
                var copy = match
                #expect(copy.throwDart(DartRecord(hit: hit)).events == [.dartRegistered(player: 0, hit: hit), .noEffect(player: 0)])
                #expect(points(copy) == [total])
            }
            // Two doubles and a treble: 7 times the number, and no Shanghai.
            let outcomes = match.play("D\(round), T\(round), D\(round)")
            #expect(outcomes[0].events == [.dartRegistered(player: 0, hit: .double(round)), .targetScored(player: 0, points: 2 * round)])
            #expect(outcomes[1].events == [.dartRegistered(player: 0, hit: .treble(round)), .targetScored(player: 0, points: 3 * round)])
            #expect(outcomes[2].events == [.dartRegistered(player: 0, hit: .double(round)), .targetScored(player: 0, points: 2 * round),
                                           .turnCompleted(player: 0)])
            total += 7 * round
            #expect(points(match) == [total])
            let end = match.endTurn().events
            #expect(end == (round == 20 ? [.gameFinished(reason: .roundLimit)]
                                        : [.roundStarted(round: round + 1), .turnStarted(player: 0, round: round + 1)]))
        }
        #expect(total == 1470 && match.phase == .finished && match.snapshot.finishReason == .roundLimit)
    }

    @Test func lite_theTwoNeighboursOfEveryRound_whateverTheBed() throws {
        let ring = [20, 1, 18, 4, 13, 6, 10, 15, 2, 17, 3, 19, 7, 16, 8, 11, 14, 9, 12, 5]
        for round in 1...20 {
            let index = try #require(ring.firstIndex(of: round))
            let neighbours = [ring[(index + 19) % 20], ring[(index + 1) % 20]]
            let lite = try match(atRound: round, ["variant": "lite", "rounds": 20])
            let traditional = try match(atRound: round, ["rounds": 20])
            for hit in Hit.all {
                var copy = lite
                let events = copy.throwDart(DartRecord(hit: hit)).events
                var strict = traditional
                let strictEvents = strict.throwDart(DartRecord(hit: hit)).events
                if hit.number == round {
                    #expect(events == [.dartRegistered(player: 0, hit: hit), .targetScored(player: 0, points: round * hit.multiplier)])
                    #expect(strictEvents == events)
                } else if let number = hit.number, neighbours.contains(number) {
                    // The single of the target, whatever the bed of the neighbour.
                    #expect(events == [.dartRegistered(player: 0, hit: hit), .neighbourHit(player: 0, points: round)], "round \(round), \(hit)")
                    #expect(points(copy) == [round])
                    #expect(strictEvents == [.dartRegistered(player: 0, hit: hit), .noEffect(player: 0)])
                } else {
                    #expect(events == [.dartRegistered(player: 0, hit: hit), .noEffect(player: 0)], "round \(round), \(hit)")
                    #expect(points(copy) == [0] && strictEvents == events)
                }
            }
        }
    }

    // MARK: Shanghai (GAMES.md §7.4, §7.6)

    @Test(arguments: ["S3, D3, T3", "S3, T3, D3", "D3, S3, T3", "D3, T3, S3", "T3, S3, D3", "T3, D3, S3"])
    func shanghai_inAnyOrder_winsOnTheThirdDart(script: String) throws {
        for variant in ["traditional", "lite"] {
            var match = try match(atRound: 3, ["variant": .string(variant)], players: 2)
            let outcomes = match.play(script)
            #expect(outcomes[1].events.count == 2 && match.snapshot.finishReason == .victory)
            #expect(outcomes[2].events.suffix(2) == [.shanghai(player: 0), .gameFinished(reason: .victory)])
            #expect(points(match) == [18, 0] && match.snapshot.ranks == [1, 2] && match.snapshot.round == 3)
        }
    }

    @Test(arguments: ["S4, S4, D4", "T4, D4, D4", "S4, T4, T4", "S4, D4, MISS", "T4, D4, S5", "S4, D4, T3", "DB, D4, T4", "S4, D4, SB"])
    func shanghai_needsSingleDoubleAndTrebleOfTheExactNumber(script: String) throws {
        for variant in ["traditional", "lite"] {
            var match = try match(atRound: 4, ["variant": .string(variant)], players: 2)
            let outcomes = match.play(script)
            #expect(match.phase == .turnComplete && match.snapshot.finishReason == nil)
            #expect(!outcomes.flatMap(\.events).contains(.shanghai(player: 0)))
        }
    }

    @Test func shanghai_countsTheCurrentVolleyOnly() throws {
        var match = try registry.match(.shanghai, players: 2)
        // J1 throws the single and the double of the 1; J2's treble does not complete them.
        match.play("S1, D1, MISS | T1, MISS, MISS")
        #expect(match.phase == .turnComplete && points(match) == [3, 3])
        // Round 2: an old S1 is worth nothing, and the three beds must be of the 2.
        match.play("| S1, D2, T2 | S2, D2, T2")
        #expect(match.phase == .finished && match.snapshot.finishReason == .victory)
        #expect(points(match) == [13, 15] && match.snapshot.ranks == [2, 1] && match.snapshot.winners == [1])
    }

    @Test func shanghai_ranksItsAuthorFirst_thenThePoints() throws {
        var match = try registry.match(.shanghai, ["rounds": 3], players: 4)
        match.play("T1, T1, T1 | T1, T1, D1 | T1, T1, T1 | MISS ×3 |")
        #expect(match.snapshot.ranks == [1, 3, 1, 4])
        // Round 2: J2, third on points, throws a Shanghai.
        match.play("MISS ×3 | T2, S2, D2")
        #expect(match.phase == .finished && match.snapshot.finishReason == .victory)
        #expect(points(match) == [9, 20, 9, 0])
        // The author first, whatever the points; then the points, with the tie shared.
        #expect(match.snapshot.ranks == [2, 1, 2, 4])
        var low = try registry.match(.shanghai, ["rounds": 3], players: 3)
        low.play("T1, T1, T1 | T1, T1, T1 | S1, D1, T1")
        #expect(points(low) == [9, 9, 6] && low.snapshot.ranks == [2, 2, 1])
    }

    @Test func normalEnd_aTieInFrontGivesSeveralWinners() throws {
        var match = try registry.match(.shanghai, ["rounds": 1], players: 3)
        match.play("S1, MISS, MISS | D1, MISS, MISS | S1, S1, MISS")
        #expect(match.phase == .turnComplete && match.snapshot.finishReason == nil)
        match.endTurn()
        #expect(match.phase == .finished && match.snapshot.finishReason == .roundLimit)
        #expect(points(match) == [1, 2, 2] && match.snapshot.ranks == [3, 1, 1] && match.snapshot.winners == [1, 2])
        #expect(match.endTurn() == .rejected(.gameFinished))
    }

    @Test func turns_areThreeDarts_withoutBust_andMayBeShort() throws {
        var match = try registry.match(.shanghai, players: 2)
        let outcomes = match.play("S1 | | T1, T1, T1")
        #expect(outcomes[1].events == [.turnCompleted(player: 0), .turnStarted(player: 1, round: 1)])
        #expect(outcomes[2].events == [.turnCompleted(player: 1), .roundStarted(round: 2), .turnStarted(player: 0, round: 2)])
        // Round 2 now: the 1 is worth nothing any more.
        #expect(points(match) == [1, 0] && match.phase == .turnComplete)
        #expect(match.throwDart(DartRecord(hit: .single(2))) == .rejected(.turnComplete))
    }

    // MARK: Undo and corrections (GAMES.md §2.5)

    @Test func corrections_makeAndBreakAShanghai() throws {
        var match = try registry.match(.shanghai, players: 2)
        match.play("S1, D1, MISS")
        #expect(match.phase == .turnComplete)
        // The third dart was a treble: the game is won.
        #expect(match.replaceDart(at: 2, with: .treble(1)).applied)
        #expect(match.phase == .finished && match.snapshot.finishReason == .victory && points(match) == [6, 0])
        #expect(match.snapshot.ranks == [1, 2])
        // The winning volley stays correctable: the first dart was a MISS, no Shanghai after all.
        #expect(match.replaceDart(at: 0, with: .miss).applied)
        #expect(match.phase == .turnComplete && match.snapshot.finishReason == nil && points(match) == [5, 0])
        #expect(match.snapshot.ranks == [1, 2] && match.turnNotation == ["MISS", "D1", "T1"])
        #expect(match.replaceDart(at: 0, with: .single(1)).applied)
        #expect(match.phase == .finished)
        // Undo of the winning dart, then of everything.
        #expect(match.undo().applied)
        #expect(match.phase == .throwing && points(match) == [3, 0] && match.turnNotation == ["S1", "D1"])
        #expect(match.removeDart(at: 0).applied)
        #expect(points(match) == [2, 0] && match.turnNotation == ["D1"])
        while match.canUndo { match.undo() }
        #expect(try match.snapshot == registry.match(.shanghai, players: 2).snapshot)
    }

    @Test func undo_acrossARound_restoresTheNumberOfTheRound() throws {
        var match = try registry.match(.shanghai, ["variant": "lite"], players: 1)
        match.play("S1, S20, S18 |")
        #expect(match.snapshot.round == 2 && points(match) == [3])
        let roundTwo = match.snapshot
        match.play("S2, S15, S17")
        #expect(points(match) == [9])
        for _ in 0..<3 { match.undo() }
        #expect(match.snapshot == roundTwo)
        match.undo()
        #expect(match.snapshot.round == 1 && match.phase == .turnComplete && match.turnNotation == ["S1", "S20", "S18"])
        #expect(try registry.restoreMatch(match.record).snapshot == match.snapshot)
    }

    @Test func effectKeys_followThePoints() throws {
        let traditional = try match(atRound: 6)
        // Three different gains on the target; everything else is "nothing".
        let keys = Dictionary(grouping: Hit.all, by: { traditional.effectKey(for: $0) })
        #expect(keys.values.map(\.count).sorted() == [1, 1, 1, 60])
        #expect(traditional.effectKey(for: .single(5)) == traditional.effectKey(for: .miss))
        let lite = try match(atRound: 6, ["variant": "lite"])
        // Neighbours of the 6: 13 and 10. Their six beds have one and the same effect, the single of the target.
        let liteKeys = Dictionary(grouping: Hit.all, by: { lite.effectKey(for: $0) })
        #expect(liteKeys.values.map(\.count).sorted() == [1, 1, 1, 6, 54])
        #expect(lite.effectKey(for: .single(13)) == lite.effectKey(for: .treble(10)))
        #expect(lite.effectKey(for: .single(13)) != lite.effectKey(for: .miss))
        // Same gain, but not the same game: only the single of the target can still lead to a Shanghai.
        #expect(lite.effectKey(for: .single(13)) != lite.effectKey(for: .single(6)))
    }

    // MARK: Presentation (GAMES.md §7.7, ARCHITECTURE.md §5.5, §5.6)

    @Test func highlights_theSectorOfTheRound_bedByBed_withWhatEachIsWorth() throws {
        for round in [1, 4, 7, 20] {
            let match = try match(atRound: round, ["rounds": 20], players: 2)
            #expect(match.snapshot.highlights == [
                BoardHighlight(zone: .single(round), role: .target, label: "+\(round)"),
                BoardHighlight(zone: .double(round), role: .target, label: "+\(2 * round)"),
                BoardHighlight(zone: .treble(round), role: .target, label: "+\(3 * round)"),
            ])
            // Together the three beds are exactly the sector of the round, and nothing belongs to a player.
            for hit in Hit.all {
                #expect(match.snapshot.highlights.contains { $0.zone.contains(hit) } == BoardZone.sector(round).contains(hit))
            }
            #expect(match.snapshot.highlights.allSatisfy { $0.owner == nil })
        }
    }

    @Test func highlights_lite_theTwoNeighboursAreSecondary() throws {
        var match = try match(atRound: 4, ["variant": "lite"], players: 2)
        let expected = [
            BoardHighlight(zone: .single(4), role: .target, label: "+4"),
            BoardHighlight(zone: .double(4), role: .target, label: "+8"),
            BoardHighlight(zone: .treble(4), role: .target, label: "+12"),
            BoardHighlight(zone: .sector(18), role: .secondary, label: "+4"),
            BoardHighlight(zone: .sector(13), role: .secondary, label: "+4"),
        ]
        #expect(match.snapshot.highlights == expected)
        // Same picture for the next player of the round, and in `turnComplete`.
        match.play("MISS ×3")
        #expect(match.phase == .turnComplete && match.snapshot.highlights == expected)
        match.endTurn()
        #expect(match.snapshot.currentPlayer == 1 && match.snapshot.highlights == expected)
        // A highlighted zone is a zone that scores, and the reverse.
        for hit in Hit.all {
            var copy = match
            let scores = !copy.throwDart(DartRecord(hit: hit)).events.contains(.noEffect(player: 1))
            #expect(match.snapshot.highlights.contains { $0.zone.contains(hit) } == scores, "\(hit)")
        }
        // None once the game is finished.
        match.play("S4, D4, T4")
        #expect(match.phase == .finished && match.snapshot.highlights.isEmpty)
    }

    @Test func scoreboard_objectiveRowsAndCaptions() throws {
        var match = try registry.match(.shanghai, ["variant": "lite"], players: 2)
        #expect(match.snapshot.title == LocalizedText(verbatim: "Shanghai"))
        #expect(match.snapshot.variant == LocalizedText(verbatim: "Lite"))
        #expect(match.snapshot.objective == LocalizedText(fr: "Numéro 1", en: "Number 1"))
        #expect(match.snapshot.players[0].detail == LocalizedText(fr: "Volée : 0", en: "Turn: 0"))
        // J2 has not played yet.
        #expect(match.snapshot.players[1].detail == nil)
        #expect(match.snapshot.turn.summary == LocalizedText(fr: "Volée : 0", en: "Turn: 0"))

        match.play("T1, S20, S5")
        #expect(match.snapshot.players[0].primary == ScoreValue(4) && match.snapshot.players[0].facts == ["points": 4])
        #expect(match.snapshot.players[0].detail == LocalizedText(fr: "Volée : 4", en: "Turn: 4"))
        #expect(match.snapshot.turn.summary == LocalizedText(fr: "Volée : 4", en: "Turn: 4"))
        #expect(match.snapshot.turn.darts.map(\.caption) == [
            DartCaption(LocalizedText(verbatim: "+3"), tone: .positive),
            DartCaption(LocalizedText(verbatim: "+1"), tone: .positive),
            DartCaption(LocalizedText(verbatim: "0"), tone: .neutral),
        ])
        match.play("| D1")
        // J1 keeps the total of the last volley; J2's runs.
        #expect(match.snapshot.players.map(\.detail) == [LocalizedText(fr: "Volée : 4", en: "Turn: 4"),
                                                         LocalizedText(fr: "Volée : 2", en: "Turn: 2")])
        #expect(match.snapshot.turn.summary == LocalizedText(fr: "Volée : 2", en: "Turn: 2"))
        match.play("|")
        #expect(match.snapshot.objective == LocalizedText(fr: "Numéro 2", en: "Number 2"))
        #expect(match.snapshot.players[0].detail == LocalizedText(fr: "Volée : 0", en: "Turn: 0"))
        #expect(match.snapshot.players.allSatisfy { $0.badges.isEmpty && $0.meter == nil && !$0.isEliminated })
        #expect(match.snapshot.facts.isEmpty && match.snapshot.grid == nil && match.snapshot.winnerTitle == nil)
        #expect(try registry.match(.shanghai, players: 1).snapshot.variant == LocalizedText(fr: "Traditionnel", en: "Traditional"))
    }

    /// After a game ended at the round limit the kernel's volley is empty while the rule's per-turn state is still
    /// that of the last turn (ARCHITECTURE.md §4.7).
    @Test func results_normalEnd_emptyVolleyAndOutcome() throws {
        var match = try registry.match(.shanghai, ["rounds": 1], players: 2)
        match.play("T1, S1, MISS | S1, MISS, MISS")
        #expect(match.snapshot.turn.darts.count == 3 && match.snapshot.outcome == nil)
        match.endTurn()
        #expect(match.phase == .finished && match.snapshot.turn.darts.isEmpty && match.currentTurn.isEmpty)
        #expect(match.snapshot.outcome == LocalizedText(fr: "Meilleur total après 1 manche : 4 points.",
                                                        en: "Highest total after 1 round: 4 points."))
        #expect(match.snapshot.players[0].resultLines == [LocalizedText(fr: "Meilleure volée : 4", en: "Best turn: 4")])
        #expect(match.snapshot.objective == LocalizedText(fr: "Numéro 1", en: "Number 1"))
        match.undo()
        #expect(match.phase == .turnComplete && match.snapshot.turn.darts.compactMap(\.caption).count == 3)

        var tie = try registry.match(.shanghai, ["rounds": 2], players: 2)
        tie.play("S1 | S1 | | |")
        #expect(tie.phase == .finished && tie.snapshot.ranks == [1, 1])
        #expect(tie.snapshot.outcome == LocalizedText(fr: "Égalité à 1 point après 2 manches.", en: "Tie at 1 point after 2 rounds."))
    }

    @Test func results_shanghai() throws {
        var match = try match(atRound: 5, players: 2)
        match.play("MISS | T5, S5, D5")
        #expect(match.phase == .finished && match.snapshot.winners == [1])
        #expect(match.snapshot.outcome == LocalizedText(fr: "Shanghai en manche 5 : simple, double et triple du 5.",
                                                        en: "Shanghai in round 5: single, double and treble of 5."))
        #expect(match.snapshot.players[1].badges == [Badge(LocalizedText(verbatim: "Shanghai"), tone: .accent)])
        #expect(match.snapshot.players[1].resultLines == [LocalizedText(fr: "Meilleure volée : 30", en: "Best turn: 30"),
                                                          LocalizedText(fr: "Shanghai manche 5", en: "Shanghai in round 5")])
        #expect(match.snapshot.players[0].badges.isEmpty)
        // The winning volley is kept, with its captions.
        #expect(match.snapshot.turn.darts.map(\.caption?.text) == ["+15", "+5", "+10"].map { LocalizedText(verbatim: $0) })
    }

    // MARK: Properties on random journals

    /// Random games against a few lines of arithmetic written from GAMES.md §7.4, with undo and replay at the end.
    @Test(arguments: ["traditional", "lite"])
    func randomGames_matchAnIndependentCount_andReplay(variant: String) throws {
        let ring = [20, 1, 18, 4, 13, 6, 10, 15, 2, 17, 3, 19, 7, 16, 8, 11, 14, 9, 12, 5]
        var random = SeededRandom(seed: variant == "lite" ? 71 : 17)
        var shanghais = 0
        for game in 0..<60 {
            let players = 1 + random.nextInt(below: 8)
            let rounds = 1 + random.nextInt(below: 20)
            var match = try registry.match(.shanghai, ["variant": .string(variant), "rounds": .int(rounds)], players: players)
            var expected = Array(repeating: 0, count: players)
            var volley: [Hit] = []
            var snapshots = [match.snapshot]
            while match.phase != .finished {
                let round = match.snapshot.round
                let player = match.snapshot.currentPlayer
                if match.phase == .turnComplete || random.nextInt(below: 12) == 0 {
                    match.endTurn()
                    volley = []
                } else {
                    // Mostly the number of the round and its neighbours, so that Shanghais happen.
                    let roll = random.nextInt(below: 10)
                    let index = ring.firstIndex(of: round) ?? 0
                    let number = roll < 6 ? round : roll < 8 ? ring[(index + 1 + 18 * (roll % 2)) % 20] : 1 + random.nextInt(below: 20)
                    let hit = [Hit.single(number), .double(number), .treble(number), .miss, .outerBull][random.nextInt(below: roll == 9 ? 5 : 3)]
                    match.throwDart(DartRecord(hit: hit))
                    volley.append(hit)
                    if hit.number == round {
                        expected[player] += round * hit.multiplier
                    } else if variant == "lite", let other = hit.number, ring[(index + 1) % 20] == other || ring[(index + 19) % 20] == other {
                        expected[player] += round
                    }
                    let won = Set(volley.filter { $0.number == round }.map(\.multiplier)) == [1, 2, 3]
                    #expect((match.phase == .finished) == won, "game \(game)")
                    if won {
                        shanghais += 1
                        #expect(match.snapshot.finishReason == .victory && match.snapshot.ranks[player] == 1)
                        #expect(match.snapshot.winners == [player])
                    }
                }
                #expect(points(match) == expected, "game \(game)")
                snapshots.append(match.snapshot)
            }
            if match.snapshot.finishReason == .roundLimit {
                #expect(match.snapshot.round == rounds)
                let best = expected.max() ?? 0
                #expect(match.snapshot.winners == expected.indices.filter { expected[$0] == best })
            }
            #expect(try registry.restoreMatch(match.record).snapshot == match.snapshot)
            #expect(snapshots.count == match.entries.count + 1)
            for index in stride(from: match.entries.count - 1, through: 0, by: -1) {
                match.undo()
                #expect(match.snapshot == snapshots[index])
            }
        }
        #expect(shanghais >= 3)
    }

    /// A pseudo-random Shanghai input: mostly the number of the round and its neighbours.
    private static func botInput(for match: GameMatch, random: inout SeededRandom) -> GameInput {
        if match.phase == .turnComplete || random.nextInt(below: 14) == 0 { return .endTurn }
        let round = match.snapshot.round
        let roll = random.nextInt(below: 10)
        if roll == 9 { return .dart([Hit.miss, .outerBull, .innerBull][random.nextInt(below: 3)]) }
        var number = round
        if roll >= 6, (1...20).contains(round) {
            let pair = BoardGeometry.standard.neighbours(of: round)
            number = roll == 6 ? pair.clockwise : roll == 7 ? pair.anticlockwise : 1 + random.nextInt(below: 20)
        }
        return .dart([Hit.single(number), .double(number), .treble(number)][random.nextInt(below: 3)])
    }

    @Test(arguments: ["traditional", "lite"])
    func randomGames_sameEffectKey_sameFuture_positionsIgnored(variant: String) throws {
        var setup = SeededRandom(seed: variant == "lite" ? 8 : 9)
        for game in 0..<15 {
            let players = 1 + setup.nextInt(below: 8)
            let options: GameOptions = ["variant": .string(variant), "rounds": .int(1 + setup.nextInt(below: 9))]
            var match = try registry.match(.shanghai, options, players: players)
            var bot = SeededRandom(seed: setup.next())
            var inputs = 0
            while match.phase != .finished {
                inputs += 1
                if inputs % 4 == 1 {
                    KillerTestProperties.expectSameEffectKeySameFuture(match, botSeed: UInt64(game * 1_000 + inputs),
                                                                       bot: Self.botInput)
                }
                #expect(match.killerApply(Self.botInput(for: match, random: &bot)).isAccepted)
                KillerTestProperties.expectWellFormed(ranks: match.snapshot.ranks, players: players)
                #expect(match.snapshot.turn.darts.map(\.hit) == match.currentTurn.map(\.hit))
                #expect(match.snapshot.highlights.isEmpty == (match.phase == .finished))
            }
            #expect(!match.killerApply(.endTurn).isAccepted && !match.killerApply(.dart(.treble(20))).isAccepted)
            KillerTestProperties.expectPositionsIgnored(from: try registry.match(.shanghai, options, players: players),
                                                        journal: match.entries)
        }
    }
}
