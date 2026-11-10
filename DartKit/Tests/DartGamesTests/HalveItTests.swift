import Testing
import DartCore
import DartGames
import DartTestSupport

/// GAMES.md §9 La Moitié (`halveIt`): the vectors HAL-1 to HAL-5 of §9.9, then every rule paragraph.
/// The default list of targets is 20, 16, D7, 14, T10, BULL: one target per round.
@Suite struct HalveItTests {
    private let registry = GameRegistry.standard

    private func points(_ match: GameMatch) -> [Int] {
        match.snapshot.players.map { row in
            if case .int(let value)? = row.facts["points"] { return value }
            return Int.min
        }
    }

    private func hitThisTurn(_ match: GameMatch) -> [Bool] {
        match.snapshot.players.map { $0.facts["hitThisTurn"] == .bool(true) }
    }

    private func targets(_ list: [String]) -> GameOptions {
        ["targets": .strings(list)]
    }

    // MARK: Vectors of GAMES.md §9.9

    @Test func hal1_fullGameWithTheDefaultList() throws {
        var match = try registry.match(.halveIt, players: 1)
        let first = match.play("S20, MISS, T20")
        #expect(points(match) == [80])
        #expect(first[0].events == [.dartRegistered(player: 0, hit: .single(20)), .targetScored(player: 0, points: 20)])
        let second = match.play("| MISS ×3")
        #expect(points(match) == [40])              // halved
        #expect(second.last?.events == [.dartRegistered(player: 0, hit: .miss), .noEffect(player: 0),
                                        .halved(player: 0, points: 40), .turnCompleted(player: 0)])
        let third = match.play("| S7, T7, MISS")
        #expect(points(match) == [20])              // halved: only D7 counts
        #expect(third[1].events == [.dartRegistered(player: 0, hit: .single(7)), .noEffect(player: 0)])
        #expect(third.last?.events.contains(.halved(player: 0, points: 20)) == true)
        let fourth = match.play("| D14, S20, MISS")
        #expect(points(match) == [48])
        #expect(fourth[1].events == [.dartRegistered(player: 0, hit: .double(14)), .targetScored(player: 0, points: 28)])
        #expect(fourth.last?.events == [.dartRegistered(player: 0, hit: .miss), .noEffect(player: 0), .turnCompleted(player: 0)])
        let fifth = match.play("| S10, D10, MISS")
        #expect(points(match) == [24])              // halved: only T10 counts
        #expect(fifth.last?.events.contains(.halved(player: 0, points: 24)) == true)
        let sixth = match.play("| SB, DB, MISS")
        #expect(points(match) == [99])
        #expect(sixth[1].events == [.dartRegistered(player: 0, hit: .outerBull), .targetScored(player: 0, points: 25)])
        #expect(sixth[2].events == [.dartRegistered(player: 0, hit: .innerBull), .targetScored(player: 0, points: 50)])
        #expect(match.phase == .turnComplete && match.snapshot.round == 6)
        #expect(match.endTurn().events == [.gameFinished(reason: .roundLimit)])
        #expect(match.phase == .finished && match.snapshot.finishReason == .roundLimit)
        #expect(points(match) == [99] && match.snapshot.ranks == [1])
    }

    @Test func hal2_roundingUp() throws {
        var match = try registry.match(.halveIt, players: 1)
        var successive: [Int] = []
        for turn in ["S20, MISS, MISS", "| MISS ×3", "| MISS ×3", "| MISS ×3"] {
            match.play(turn)
            successive += points(match)
        }
        #expect(successive == [20, 10, 5, 3])
        #expect(match.snapshot.round == 4 && match.phase == .turnComplete)
    }

    @Test func hal3_theHalvingWaitsForTheCloseOfTheTurn() throws {
        var match = try registry.match(.halveIt, players: 1)
        match.play("T20, S5, S5 | MISS, S16, S1 | MISS, MISS")
        // Two darts thrown, no division yet.
        #expect(points(match) == [76] && match.phase == .throwing)
        #expect(match.endTurn().events == [.halved(player: 0, points: 38), .turnCompleted(player: 0),
                                           .roundStarted(round: 4), .turnStarted(player: 0, round: 4)])
        #expect(points(match) == [38] && match.snapshot.round == 4)
    }

    @Test func hal4_startingScoreOf40() throws {
        var match = try registry.match(.halveIt, ["startingScore": 40], players: 2)
        #expect(points(match) == [40, 40])
        match.play("MISS ×3 | S20, MISS, MISS")
        #expect(points(match) == [20, 60])
    }

    @Test func hal5_anyDoubleAndAnyTreble() throws {
        var match = try registry.match(.halveIt, targets(["anyDouble", "anyTreble"]), players: 1)
        let outcomes = match.play("DB, D3, S20 | T1, DB, MISS")
        // 50 + 6, then 3: DB is a double, never a treble.
        #expect(points(match) == [59])
        #expect(outcomes[0].events == [.dartRegistered(player: 0, hit: .innerBull), .targetScored(player: 0, points: 50)])
        #expect(outcomes[1].events == [.dartRegistered(player: 0, hit: .double(3)), .targetScored(player: 0, points: 6)])
        #expect(outcomes[2].events == [.dartRegistered(player: 0, hit: .single(20)), .noEffect(player: 0), .turnCompleted(player: 0)])
        #expect(outcomes[4].events == [.dartRegistered(player: 0, hit: .treble(1)), .targetScored(player: 0, points: 3)])
        #expect(outcomes[5].events == [.dartRegistered(player: 0, hit: .innerBull), .noEffect(player: 0)])
    }

    // MARK: §9.2 Options

    @Test func options_defaultsAreTheShortListFromZero() throws {
        let match = try registry.match(.halveIt, players: 3)
        #expect(points(match) == [0, 0, 0] && hitThisTurn(match) == [false, false, false])
        #expect(match.snapshot.roundLimit == 6 && match.gameFact("target") == "20")
        #expect(match.snapshot.ranks == [1, 1, 1])
        #expect(match.configuration.options == HalveItRules.descriptor.defaultOptions)
    }

    @Test func options_theLongListHasNineRounds() throws {
        var match = try registry.match(.halveIt, targets(["15", "16", "anyDouble", "17", "18", "anyTreble", "19", "20", "BULL"]), players: 1)
        #expect(match.snapshot.roundLimit == 9)
        var seen: [FactValue?] = []
        for _ in 0..<9 {
            seen.append(match.gameFact("target"))
            match.play("MISS |")
        }
        #expect(seen == ["15", "16", "anyDouble", "17", "18", "anyTreble", "19", "20", "BULL"])
        #expect(match.phase == .finished && match.snapshot.round == 9)
        // The target of a finished game stays the last one: the round does not move any more.
        #expect(match.gameFact("target") == "BULL")
    }

    @Test func options_customListsFromOneToTwelveTargets() throws {
        let one = try registry.match(.halveIt, targets(["T20"]), players: 2)
        #expect(one.snapshot.roundLimit == 1 && one.gameFact("target") == "T20")
        let twelve = try registry.match(.halveIt, targets(["1", "2", "3", "4", "5", "6", "7", "8", "9", "10", "D20", "BULL"]), players: 2)
        #expect(twelve.snapshot.roundLimit == 12 && twelve.gameFact("target") == "1")
        // The same target may come twice, and every number, double and treble from 1 to 20 is a target.
        let twice = try registry.match(.halveIt, targets(["20", "20", "D1", "T1", "D20", "T20"]), players: 1)
        #expect(twice.snapshot.roundLimit == 6)
        // The notation is read without regard to case, as dart notations are; the fact is the canonical form.
        let relaxed = try registry.match(.halveIt, targets(["d7", "t10", "bull", "ANYDOUBLE", "anytreble"]), players: 1)
        #expect(relaxed.gameFact("target") == "D7" && relaxed.snapshot.roundLimit == 5)
    }

    @Test(arguments: [
        OptionValue.strings([]),
        .strings(["1", "2", "3", "4", "5", "6", "7", "8", "9", "10", "11", "12", "13"]),
        .strings(["20", "S20"]), .strings(["0"]), .strings(["21"]), .strings(["D0"]), .strings(["D21"]), .strings(["T21"]),
        .strings(["DB"]), .strings(["SB"]), .strings(["25"]), .strings(["MISS"]), .strings(["D"]), .strings([""]),
        .strings(["020"]), .strings(["D07"]), .strings(["20 "]), .strings(["anyBull"]), .strings(["-5"]), .strings(["T1.5"]),
        .strings(["20", "double"]), .string("20"), .int(20), .bool(true), .null,
    ])
    func options_unreadableTargetsAreRefused(value: OptionValue) {
        #expect(throws: GameConfigurationError.invalidOptionValue(key: "targets")) {
            try registry.match(.halveIt, ["targets": value], players: 2)
        }
    }

    @Test func options_schemaRefusals() {
        #expect(throws: GameConfigurationError.invalidOptionValue(key: "startingScore")) {
            try registry.match(.halveIt, ["startingScore": 20], players: 2)
        }
        #expect(throws: GameConfigurationError.playerCountOutOfRange(allowed: 1...8, actual: 9)) {
            try registry.match(.halveIt, players: 9)
        }
        #expect(throws: GameConfigurationError.unknownOption(key: "maxRounds")) {
            try registry.match(.halveIt, ["maxRounds": 3], players: 2)
        }
    }

    // MARK: §9.2 Target kinds and §9.4 effect of a dart

    /// Every one of the 63 darts against one target: the darts that count, and what they earn.
    private func gains(target: String) throws -> [Hit: Int] {
        var result: [Hit: Int] = [:]
        for hit in Hit.all {
            var match = try registry.match(.halveIt, targets([target]), players: 1)
            let events = match.throwDart(DartRecord(hit: hit)).events
            if events == [.dartRegistered(player: 0, hit: hit), .noEffect(player: 0)] {
                #expect(points(match) == [0] && hitThisTurn(match) == [false], "\(target) \(hit)")
                continue
            }
            guard events.count == 2, case .targetScored(player: 0, points: let gain) = events[1] else {
                Issue.record("unexpected events for \(hit) on \(target): \(events)")
                continue
            }
            #expect(points(match) == [gain] && hitThisTurn(match) == [true], "\(target) \(hit)")
            result[hit] = gain
        }
        return result
    }

    @Test func target_numberCountsItsThreeBeds() throws {
        #expect(try gains(target: "20") == [.single(20): 20, .double(20): 40, .treble(20): 60])
        #expect(try gains(target: "7") == [.single(7): 7, .double(7): 14, .treble(7): 21])
        #expect(try gains(target: "1") == [.single(1): 1, .double(1): 2, .treble(1): 3])
    }

    @Test func target_doubleAndTrebleOfANumberCountThatBedOnly() throws {
        #expect(try gains(target: "D7") == [.double(7): 14])
        #expect(try gains(target: "T10") == [.treble(10): 30])
        #expect(try gains(target: "D20") == [.double(20): 40])
        #expect(try gains(target: "T20") == [.treble(20): 60])
    }

    @Test func target_anyDoubleIsTheTwentyDoublesAndTheInnerBull() throws {
        var expected: [Hit: Int] = [.innerBull: 50]
        for number in 1...20 { expected[.double(number)] = 2 * number }
        #expect(try gains(target: "anyDouble") == expected)
    }

    @Test func target_anyTrebleIsTheTwentyTrebles() throws {
        var expected: [Hit: Int] = [:]
        for number in 1...20 { expected[.treble(number)] = 3 * number }
        #expect(try gains(target: "anyTreble") == expected)
    }

    @Test func target_bullIsBothBulls() throws {
        #expect(try gains(target: "BULL") == [.outerBull: 25, .innerBull: 50])
    }

    @Test func dart_theTargetIsTheOneOfTheRound() throws {
        var match = try registry.match(.halveIt, players: 2)
        // Round 1, target 20, for both players.
        match.play("S16, D7, S20 | T20, S14, MISS |")
        #expect(points(match) == [20, 60] && match.snapshot.round == 2 && match.gameFact("target") == "16")
        // Round 2, target 16: the 20 does not count any more.
        match.play("T20, S20, S16 | D16 |")
        #expect(points(match) == [36, 92] && match.gameFact("target") == "D7")
    }

    // MARK: §9.5 Turn

    @Test func turn_halvingRoundsUpAndIsAnnouncedBeforeTheTurnCompletes() throws {
        // 80 → 40, 5 → 3, 1 → 1, 0 → 0 (GAMES.md §9.5).
        var eighty = try registry.match(.halveIt, players: 1)
        eighty.play("T20, S20, MISS |")
        #expect(eighty.play("MISS ×3").last?.events == [.dartRegistered(player: 0, hit: .miss), .noEffect(player: 0),
                                                         .halved(player: 0, points: 40), .turnCompleted(player: 0)])
        var five = try registry.match(.halveIt, targets(["5", "20", "20", "20"]), players: 1)
        five.play("S5 |")
        #expect(five.endTurn().events.first == .halved(player: 0, points: 3))
        #expect(five.endTurn().events.first == .halved(player: 0, points: 2))
        #expect(five.endTurn().events == [.halved(player: 0, points: 1), .turnCompleted(player: 0), .gameFinished(reason: .roundLimit)])
        // 1 → 1 and 0 → 0: the division still takes place, and is still announced.
        var one = try registry.match(.halveIt, targets(["1", "20", "20"]), players: 1)
        one.play("S1 |")
        #expect(one.endTurn().events.first == .halved(player: 0, points: 1))
        #expect(one.endTurn().events.first == .halved(player: 0, points: 1))
        #expect(points(one) == [1] && one.phase == .finished)
        var zero = try registry.match(.halveIt, players: 1)
        #expect(zero.play("MISS ×3").last?.events == [.dartRegistered(player: 0, hit: .miss), .noEffect(player: 0),
                                                       .halved(player: 0, points: 0), .turnCompleted(player: 0)])
        #expect(points(zero) == [0])
    }

    @Test func turn_oneHitIsEnoughWhereverItComes() throws {
        for script in ["S20, MISS, MISS", "MISS, S20, MISS", "MISS, MISS, S20"] {
            var match = try registry.match(.halveIt, ["startingScore": 40], players: 1)
            let outcomes = match.play(script)
            #expect(points(match) == [60], "\(script)")
            #expect(outcomes.last?.events.last == .turnCompleted(player: 0))
            #expect(!outcomes.flatMap(\.events).contains { if case .halved = $0 { return true } else { return false } })
        }
    }

    @Test func turn_earlyConfirmationHalvesEvenWithoutADart() throws {
        var match = try registry.match(.halveIt, ["startingScore": 40], players: 2)
        #expect(match.endTurn().events == [.halved(player: 0, points: 20), .turnCompleted(player: 0),
                                           .turnStarted(player: 1, round: 1)])
        // One dart on the target, then the confirmation: no division.
        match.play("D20")
        #expect(match.endTurn().events == [.turnCompleted(player: 1), .roundStarted(round: 2), .turnStarted(player: 0, round: 2)])
        #expect(points(match) == [20, 80])
        // The confirmation of a turn already closed divides nothing a second time.
        match.play("MISS ×3")
        #expect(points(match) == [10, 80])
        #expect(match.endTurn().events == [.turnStarted(player: 1, round: 2)])
        #expect(points(match) == [10, 80])
    }

    @Test func turn_threeDartsPerTurnAndNothingCutsItShort() throws {
        var match = try registry.match(.halveIt, players: 1)
        match.play("T20, T20, T20")
        #expect(points(match) == [180] && match.phase == .turnComplete)
        #expect(match.throwDart(DartRecord(hit: .treble(20))) == .rejected(.turnComplete))
        #expect(points(match) == [180] && match.entries.count == 3)
    }

    // MARK: §9.6 End and ranking

    @Test func end_atTheConfirmationOfTheLastTurnOfTheLastTarget() throws {
        var match = try registry.match(.halveIt, targets(["20", "BULL"]), players: 3)
        match.play("S20 | T20 | D20 |")
        #expect(match.snapshot.round == 2 && points(match) == [20, 60, 40] && match.snapshot.ranks == [3, 1, 2])
        match.play("DB | MISS | SB, SB, SB")
        #expect(match.phase == .turnComplete && points(match) == [70, 30, 115])
        #expect(match.endTurn().events == [.gameFinished(reason: .roundLimit)])
        #expect(match.phase == .finished && match.snapshot.ranks == [2, 3, 1] && match.snapshot.winners == [2])
        #expect(match.throwDart(DartRecord(hit: .innerBull)) == .rejected(.gameFinished))
        #expect(match.endTurn() == .rejected(.gameFinished))
        #expect(match.snapshot.players.allSatisfy { !$0.isEliminated })
    }

    @Test func ranking_tiesShareARank() throws {
        var match = try registry.match(.halveIt, targets(["20"]), players: 4)
        match.play("S20 | D20 | S20 | MISS |")
        #expect(points(match) == [20, 40, 20, 0] && match.snapshot.ranks == [2, 1, 2, 4] && match.phase == .finished)
    }

    // MARK: §9.7 Scoreboard and highlights

    @Test func highlights_followTheTargetOfTheRound() throws {
        var match = try registry.match(.halveIt, targets(["20", "D7", "T10", "anyDouble", "anyTreble", "BULL"]), players: 1)
        #expect(match.snapshot.highlights == [BoardHighlight(zone: .sector(20), role: .target)])
        match.play("|")
        #expect(match.snapshot.highlights == [BoardHighlight(zone: .double(7), role: .target)])
        match.play("|")
        #expect(match.snapshot.highlights == [BoardHighlight(zone: .treble(10), role: .target)])
        match.play("|")
        #expect(Set(match.snapshot.highlights) == Set((1...20).map { BoardHighlight(zone: .double($0), role: .target) }
                                                      + [BoardHighlight(zone: .innerBull, role: .target)]))
        #expect(match.snapshot.highlights.count == 21)
        match.play("|")
        #expect(Set(match.snapshot.highlights) == Set((1...20).map { BoardHighlight(zone: .treble($0), role: .target) }))
        #expect(match.snapshot.highlights.count == 20)
        match.play("| MISS ×3")
        // Still shown while the turn waits for its confirmation; gone once the game is over.
        #expect(match.phase == .turnComplete && match.snapshot.highlights == [BoardHighlight(zone: .bull, role: .target)])
        match.play("|")
        #expect(match.phase == .finished && match.snapshot.highlights.isEmpty)
    }

    @Test func highlights_coverExactlyTheDartsThatCount() throws {
        for target in ["20", "3", "D7", "T10", "anyDouble", "anyTreble", "BULL"] {
            let match = try registry.match(.halveIt, targets([target]), players: 1)
            let counted = try gains(target: target)
            for hit in Hit.all {
                #expect(match.snapshot.highlights.contains { $0.zone.contains(hit) } == (counted[hit] != nil), "\(target) \(hit)")
            }
            #expect(match.snapshot.highlights.allSatisfy { $0.role == .target && $0.owner == nil })
        }
    }

    @Test func facts_hitThisTurnIsForTheCurrentTurnOnly() throws {
        var match = try registry.match(.halveIt, players: 2)
        match.play("MISS")
        #expect(hitThisTurn(match) == [false, false])
        match.play("S20")
        #expect(hitThisTurn(match) == [true, false])
        match.play("MISS")
        #expect(match.phase == .turnComplete && hitThisTurn(match) == [true, false])
        match.play("|")
        #expect(hitThisTurn(match) == [false, false] && match.snapshot.currentPlayer == 1)
        match.play("T20 |")
        #expect(hitThisTurn(match) == [false, false] && match.snapshot.currentPlayer == 0 && match.gameFact("target") == "16")
        // Once the game is over no turn is in progress: the mark of the last turn does not linger.
        var last = try registry.match(.halveIt, ["targets": .strings(["20"])], players: 2)
        last.play("MISS | S20")
        #expect(hitThisTurn(last) == [false, true])
        last.play("|")
        #expect(last.phase == .finished && hitThisTurn(last) == [false, false])
        #expect(last.snapshot.players.allSatisfy { $0.badges.isEmpty })
    }

    @Test func presentation_objectiveBadgeAndCaptions() throws {
        var match = try registry.match(.halveIt, players: 2)
        #expect(match.snapshot.title == LocalizedText(fr: "La Moitié", en: "Halve-It") && match.snapshot.gameID == .halveIt)
        #expect(match.snapshot.objective == LocalizedText(fr: "Cible : 20", en: "Target: 20"))
        #expect(match.snapshot.turn.hint == LocalizedText(fr: "Ensuite : 16 · D7 · 14 · T10 · Bull", en: "Next: 16 · D7 · 14 · T10 · Bull"))
        #expect(match.snapshot.players.map(\.primary) == [ScoreValue(0), ScoreValue(0)])
        #expect(match.snapshot.players.allSatisfy { $0.detail == nil && $0.badges.isEmpty && $0.meter == nil })
        #expect(match.snapshot.winnerTitle == nil && match.snapshot.variant == nil)

        match.play("S5, T20")
        #expect(match.snapshot.turn.darts.map(\.caption) == [
            DartCaption(LocalizedText(fr: "Sans effet", en: "No effect")),
            DartCaption(LocalizedText(verbatim: "+60"), tone: .positive),
        ])
        #expect(match.snapshot.turn.summary == LocalizedText(fr: "Volée : +60", en: "Turn: +60"))
        #expect(match.snapshot.players[0].badges == [Badge(LocalizedText(fr: "Cible touchée", en: "Target hit"), tone: .positive)])
        #expect(match.snapshot.players[1].badges.isEmpty && match.snapshot.players[0].primary == ScoreValue(60))

        match.play("| MISS ×3")
        #expect(match.snapshot.turn.summary == LocalizedText(fr: "Divisé par deux : 0", en: "Halved: 0"))
        #expect(match.snapshot.players.allSatisfy { $0.badges.isEmpty })
        match.play("| ")
        #expect(match.snapshot.objective == LocalizedText(fr: "Cible : 16", en: "Target: 16"))
        #expect(match.snapshot.turn.hint == LocalizedText(fr: "Ensuite : D7 · 14 · T10 · Bull", en: "Next: D7 · 14 · T10 · Bull"))

        var kinds = try registry.match(.halveIt, targets(["anyDouble", "anyTreble", "BULL"]), players: 1)
        #expect(kinds.snapshot.objective == LocalizedText(fr: "Cible : un double", en: "Target: any double"))
        #expect(kinds.snapshot.turn.hint == LocalizedText(fr: "Ensuite : un triple · Bull", en: "Next: any treble · Bull"))
        kinds.play("|")
        #expect(kinds.snapshot.objective == LocalizedText(fr: "Cible : un triple", en: "Target: any treble"))
        kinds.play("|")
        #expect(kinds.snapshot.objective == LocalizedText(fr: "Cible : Bull", en: "Target: Bull"))
        // Last round: nothing comes next.
        #expect(kinds.snapshot.turn.hint == nil)
    }

    @Test func presentation_results() throws {
        var match = try registry.match(.halveIt, targets(["20", "16"]), players: 2)
        match.play("T20 | S20 | MISS | S16 |")
        #expect(match.phase == .finished && points(match) == [30, 36] && match.snapshot.ranks == [2, 1])
        #expect(match.snapshot.outcome == LocalizedText(fr: "Vainqueur avec 36 points.", en: "Winner with 36 points."))
        #expect(match.snapshot.players[0].resultLines == [LocalizedText(fr: "1 division", en: "1 halving")])
        #expect(match.snapshot.players[1].resultLines.isEmpty)
        // The volley is empty after the round limit: no caption and no summary of a turn that is not shown.
        #expect(match.snapshot.turn.darts.isEmpty && match.snapshot.turn.summary == nil)

        var tie = try registry.match(.halveIt, targets(["20"]), players: 3)
        tie.play("S20 | S20 | MISS |")
        #expect(tie.snapshot.ranks == [1, 1, 3])
        #expect(tie.snapshot.outcome == LocalizedText(fr: "Égalité à 20 points.", en: "Tied at 20 points."))
        var single = try registry.match(.halveIt, targets(["1"]), players: 1)
        single.play("S1 |")
        #expect(single.snapshot.outcome == LocalizedText(fr: "Vainqueur avec 1 point.", en: "Winner with 1 point."))
    }

    // MARK: Undo, corrections, replay (GAMES.md §2.5)

    @Test func correction_changingTheOnlyScoringDartHalvesAndBack() throws {
        var match = try registry.match(.halveIt, ["startingScore": 40], players: 1)
        match.play("MISS, S20, MISS")
        #expect(points(match) == [60] && match.phase == .turnComplete)
        match.replaceDart(at: 1, with: .single(5))
        #expect(points(match) == [20] && match.phase == .turnComplete && match.turnNotation == ["MISS", "S5", "MISS"])
        match.replaceDart(at: 2, with: .treble(20))
        #expect(points(match) == [100] && hitThisTurn(match) == [true])
        // Removing a dart reopens the turn: the division is undone until the turn closes again.
        match.removeDart(at: 2)
        #expect(points(match) == [40] && match.phase == .throwing && match.turnNotation == ["MISS", "S5"])
        match.play("MISS")
        #expect(points(match) == [20] && match.phase == .turnComplete)
    }

    @Test func correction_undoThroughADivisionAndAConfirmation() throws {
        var match = try registry.match(.halveIt, ["startingScore": 40], players: 1)
        match.play("MISS ×3 |")
        #expect(points(match) == [20] && match.snapshot.round == 2)
        match.undo()
        #expect(points(match) == [20] && match.phase == .turnComplete && match.snapshot.round == 1)
        match.undo()
        #expect(points(match) == [40] && match.phase == .throwing && match.turnNotation == ["MISS", "MISS"])
        match.undo()
        match.undo()
        #expect(points(match) == [40] && !match.canUndo)
        let nothing = match.undo()
        #expect(!nothing.applied && nothing.dropped.isEmpty)
    }

    @Test func effectKey_groupsTheDartsOfEqualEffect() throws {
        let match = try registry.match(.halveIt, players: 1)
        // Off target: every dart is the same useless dart, until the third one, which closes the turn.
        #expect(match.effectKey(for: .single(5)) == match.effectKey(for: .innerBull))
        #expect(match.effectKey(for: .single(5)) == match.effectKey(for: .miss))
        #expect(match.effectKey(for: .single(20)) != match.effectKey(for: .double(20)))
        #expect(match.effectKey(for: .single(20)) != match.effectKey(for: .single(5)))
    }

    @Test func position_aRecordedPositionChangesNothing() throws {
        var plain = try registry.match(.halveIt, players: 2)
        var placed = plain
        for (index, hit) in [Hit.treble(20), .single(5), .miss, .single(20), .double(16), .innerBull].enumerated() {
            #expect(plain.throwDart(DartRecord(hit: hit))
                    == placed.throwDart(DartRecord(hit: hit, position: BoardPoint(x: -Double(index) * 12, y: 100))))
            if plain.phase == .turnComplete { #expect(plain.endTurn() == placed.endTurn()) }
        }
        #expect(plain.snapshot == placed.snapshot)
    }

    @Test func effectKey_equalKeysLeaveEqualFutures() throws {
        var pairs = 0
        for (index, list) in [["20", "16", "D7", "14", "T10", "BULL"], ["anyDouble", "anyTreble", "BULL", "3"]].enumerated() {
            pairs += try MoonLandingReplayChecks.equalKeysHaveEqualFutures(
                .halveIt, ["targets": .strings(list)], players: index + 1, seed: 0, fuzzSeed: UInt64(index) + 70, states: 50,
                hits: Hit.all)
        }
        // One group per state here: the darts that miss the target of the round.
        #expect(pairs > 50)
    }

    @Test func replay_theJournalAloneRebuildsTheGame() throws {
        let lists = [["20", "16", "D7", "14", "T10", "BULL"], ["anyDouble", "anyTreble", "BULL", "3"], ["T20", "D20", "20"]]
        // Darts that count for one target or another, and some that never do.
        let hits: [Hit] = [.miss, .single(20), .double(20), .treble(20), .single(16), .double(7), .single(14), .treble(10),
                           .outerBull, .innerBull, .single(3), .treble(3), .single(9)]
        var halvings = 0
        for fuzzSeed in UInt64(1)...4 {
            for (index, list) in lists.enumerated() {
                let players = [1, 3, 8][index]
                try MoonLandingReplayChecks.fuzz(
                    .halveIt, ["targets": .strings(list), "startingScore": index == 1 ? 40 : 0], players: players,
                    seed: fuzzSeed, fuzzSeed: fuzzSeed &* 31 &+ UInt64(index), steps: 140, hits: hits
                ) { snapshot in
                    #expect(snapshot.roundLimit == list.count && (1...list.count).contains(snapshot.round))
                    #expect(snapshot.facts["target"] == .text(list[snapshot.round - 1]))
                    for row in snapshot.players {
                        guard case .int(let points)? = row.facts["points"], case .bool(let hit)? = row.facts["hitThisTurn"] else {
                            Issue.record("missing fact")
                            return
                        }
                        #expect(points >= 0 && row.primary == ScoreValue(points) && !row.isEliminated)
                        #expect(!hit || row.player == snapshot.currentPlayer)
                    }
                    #expect(snapshot.finishReason == nil || snapshot.finishReason == .roundLimit)
                    halvings += snapshot.turn.summary?.en.hasPrefix("Halved") == true ? 1 : 0
                }
            }
        }
        #expect(halvings > 100)
    }
}
