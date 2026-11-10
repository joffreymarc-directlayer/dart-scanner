import Testing
import DartCore
import DartGames
import DartTestSupport

/// High Score (GAMES.md §8): the vectors HIS-1 to HIS-4 of §8.9, then every rule paragraph that no vector covers.
@Suite struct HighScoreTests {
    private let registry = GameRegistry.standard

    private func points(_ match: GameMatch) -> [FactValue?] {
        match.snapshot.players.indices.map { match.fact($0, "points") }
    }

    // MARK: Vectors (GAMES.md §8.9)

    @Test func his1_simpleAdditionAnd180() throws {
        var match = try registry.match(.highScore, ["rounds": 2], players: 2)
        let outcomes = match.play("T20, T20, T20 | S5, S1, MISS | DB, SB, S20 | T19, D16, S7")
        #expect(points(match) == [275, 102])
        #expect(match.phase == .turnComplete && match.snapshot.round == 2)
        // The third dart of the game.
        #expect(outcomes[2].events == [.dartRegistered(player: 0, hit: .treble(20)), .turnScored(player: 0, points: 180),
                                       .oneEighty(player: 0), .turnCompleted(player: 0)])
        #expect(match.endTurn().events == [.gameFinished(reason: .roundLimit)])
        #expect(match.phase == .finished && match.snapshot.finishReason == .roundLimit && match.snapshot.ranks == [1, 2])
    }

    @Test func his2_tie() throws {
        var match = try registry.match(.highScore, ["rounds": 1], players: 3)
        match.play("S20, S20, S20 | T20, MISS, MISS | S19, S1, MISS |")
        #expect(points(match) == [60, 60, 20])
        #expect(match.snapshot.ranks == [1, 1, 3] && match.snapshot.winners == [0, 1])
        #expect(match.phase == .finished && match.snapshot.finishReason == .roundLimit)
    }

    @Test func his3_shortTurn() throws {
        var match = try registry.match(.highScore, ["rounds": 1], players: 1)
        let outcomes = match.play("S20 |")
        #expect(match.phase == .finished && match.fact(0, "points") == 20 && match.fact(0, "dartsThrown") == 1)
        // The early confirmation closes the turn, then ends the game: the darts not thrown do not exist.
        #expect(outcomes[1].events == [.turnScored(player: 0, points: 20), .turnCompleted(player: 0),
                                       .gameFinished(reason: .roundLimit)])
    }

    @Test func his4_highTurn() throws {
        var match = try registry.match(.highScore, players: 1)
        let outcomes = match.play("T20, T20, S20")
        #expect(match.fact(0, "points") == 140)
        #expect(outcomes[2].events == [.dartRegistered(player: 0, hit: .single(20)), .turnScored(player: 0, points: 140),
                                       .highTurn(player: 0, points: 140), .turnCompleted(player: 0)])
    }

    // MARK: Options and initial state (GAMES.md §8.2, §8.3)

    @Test func initialState_andDefaultOfEightRounds() throws {
        for count in 1...8 {
            let match = try registry.match(.highScore, players: count)
            #expect(match.configuration.options == ["rounds": 8] && match.snapshot.roundLimit == 8)
            #expect(points(match) == Array(repeating: 0, count: count))
            #expect(match.snapshot.players.allSatisfy { $0.facts == ["points": 0, "dartsThrown": 0] })
            #expect(match.snapshot.ranks == Array(repeating: 1, count: count))
            #expect(match.snapshot.highlights.isEmpty && match.snapshot.facts.isEmpty)
        }
        #expect(throws: GameConfigurationError.playerCountOutOfRange(allowed: 1...8, actual: 9)) {
            try registry.match(.highScore, players: 9)
        }
        for rounds in [0, 21] {
            #expect(throws: GameConfigurationError.invalidOptionValue(key: "rounds")) {
                try registry.match(.highScore, ["rounds": .int(rounds)], players: 1)
            }
        }
        #expect(throws: GameConfigurationError.invalidOptionValue(key: "rounds")) {
            try registry.match(.highScore, ["rounds": .null], players: 1)
        }
    }

    @Test(arguments: [1, 2, 8, 20])
    func rounds_theGameEndsAtTheConfirmationOfTheLastTurn(_ rounds: Int) throws {
        var match = try registry.match(.highScore, ["rounds": .int(rounds)], players: 2)
        for round in 1...rounds {
            #expect(match.snapshot.round == round && match.phase == .throwing)
            match.play("S1, S1, S1 | S2, S2, S2")
            // After the last dart of a round the game waits for the confirmation (GAMES.md §2.6).
            #expect(match.phase == .turnComplete && match.snapshot.finishReason == nil)
            match.endTurn()
        }
        #expect(match.phase == .finished && match.snapshot.finishReason == .roundLimit && match.snapshot.round == rounds)
        #expect(points(match) == [.int(3 * rounds), .int(6 * rounds)] && match.snapshot.ranks == [2, 1])
        #expect(match.endTurn() == .rejected(.gameFinished))
    }

    // MARK: Effect of a dart (GAMES.md §8.4)

    @Test func everyBed_addsItsPoints() throws {
        for hit in Hit.all {
            var match = try registry.match(.highScore, players: 1)
            let outcome = match.throwDart(DartRecord(hit: hit))
            var expected: [GameEvent] = [.dartRegistered(player: 0, hit: hit)]
            if hit.isMiss { expected.append(.noEffect(player: 0)) }
            #expect(outcome.events == expected, "\(hit)")
            #expect(match.fact(0, "points") == .int(hit.points) && match.fact(0, "dartsThrown") == 1, "\(hit)")
        }
        // Sn = n, Dn = 2n, Tn = 3n, SB = 25, DB = 50, MISS = 0.
        var match = try registry.match(.highScore, players: 1)
        var totals: [FactValue?] = []
        for script in ["S7", "D7", "T7", "|", "SB", "DB", "MISS"] {
            match.play(script)
            totals.append(match.fact(0, "points"))
        }
        #expect(totals == [7, 21, 42, 42, 67, 117, 117])
        #expect(match.fact(0, "dartsThrown") == 6)
    }

    @Test func nothingShortensATurn_andThereIsNoVictoryOnADart() throws {
        var match = try registry.match(.highScore, ["rounds": 1], players: 2)
        match.play("DB, DB")
        #expect(match.phase == .throwing)
        match.play("DB")
        #expect(match.phase == .turnComplete && match.snapshot.finishReason == nil)
        match.play("| T20, T20, T20")
        // The last dart of the last round does not end the game: the confirmation does.
        #expect(match.phase == .turnComplete && match.snapshot.finishReason == nil && match.snapshot.ranks == [2, 1])
    }

    @Test func turnTotals_highTurnBetween100And179_oneEightyAt180() throws {
        let cases: [(script: String, total: Int, extra: GameEvent?)] = [
            ("T20, S20, S19", 99, nil),
            ("T20, S20, S20", 100, .highTurn(player: 0, points: 100)),
            ("T20, T20, T19", 177, .highTurn(player: 0, points: 177)),
            ("T20, T20, T20", 180, .oneEighty(player: 0)),
            ("MISS, MISS, MISS", 0, nil),
        ]
        for item in cases {
            var match = try registry.match(.highScore, players: 1)
            let events = try #require(match.play(item.script).last).events
            var expected: [GameEvent] = [.turnScored(player: 0, points: item.total)]
            if let extra = item.extra { expected.append(extra) }
            expected.append(.turnCompleted(player: 0))
            #expect(Array(events.dropFirst(events.count - expected.count)) == expected, "\(item.script)")
        }
        // An empty turn is scored too.
        var match = try registry.match(.highScore, players: 2)
        #expect(match.endTurn().events == [.turnScored(player: 0, points: 0), .turnCompleted(player: 0),
                                           .turnStarted(player: 1, round: 1)])
    }

    // MARK: Presentation (GAMES.md §8.7, ARCHITECTURE.md §5.6)

    @Test func presentation_rowsCaptionsAndSummary() throws {
        var match = try registry.match(.highScore, players: 2)
        #expect(match.snapshot.title == LocalizedText(fr: "Meilleur score", en: "High Score"))
        #expect(match.snapshot.variant == nil && match.snapshot.objective == nil && match.snapshot.grid == nil)
        #expect(match.snapshot.players[0].detail == nil)
        #expect(match.snapshot.turn.summary == LocalizedText(fr: "Volée : 0", en: "Turn: 0"))
        match.play("T20, MISS, SB")
        #expect(match.snapshot.turn.darts.map(\.caption) == [DartCaption(LocalizedText(verbatim: "60")),
                                                            DartCaption(LocalizedText(verbatim: "0")),
                                                            DartCaption(LocalizedText(verbatim: "25"))])
        #expect(match.snapshot.turn.summary == LocalizedText(fr: "Volée : 85", en: "Turn: 85"))
        #expect(match.snapshot.turn.hint == nil)
        let row = match.snapshot.players[0]
        #expect(row.primary == ScoreValue(85) && row.badges.isEmpty && row.meter == nil && !row.isEliminated)
        #expect(row.detail == LocalizedText(fr: "Dernière volée : 85", en: "Last turn: 85"))
        match.play("| S1")
        // The scoreboard keeps the last closed turn of each player; the summary follows the current volley.
        #expect(match.snapshot.players[0].detail == LocalizedText(fr: "Dernière volée : 85", en: "Last turn: 85"))
        #expect(match.snapshot.players[1].detail == nil)
        #expect(match.snapshot.turn.summary == LocalizedText(fr: "Volée : 1", en: "Turn: 1"))
    }

    @Test func presentation_results() throws {
        var match = try registry.match(.highScore, ["rounds": 2], players: 2)
        match.play("T20, T20, T20 | S5, S1, MISS | DB, SB, S20 | T19, D16")
        // The results sentence and the lines of the results screen come with the end of the game.
        #expect(match.snapshot.outcome == nil && match.snapshot.winnerTitle == nil)
        #expect(match.snapshot.players.allSatisfy { $0.resultLines.isEmpty })
        match.play("|")
        #expect(match.phase == .finished)
        #expect(match.snapshot.outcome == LocalizedText(fr: "Plus gros total : 275 points.", en: "Highest total: 275 points."))
        #expect(match.snapshot.winnerTitle == nil)
        // Average per turn: 3 × points / dartsThrown, to the tenth.
        #expect(match.snapshot.players[0].resultLines == [
            LocalizedText(fr: "Moyenne par volée : 137,5", en: "Average per turn: 137.5"),
            LocalizedText(fr: "6 fléchettes", en: "6 darts"),
        ])
        #expect(match.snapshot.players[1].resultLines == [
            LocalizedText(fr: "Moyenne par volée : 57,0", en: "Average per turn: 57.0"),
            LocalizedText(fr: "5 fléchettes", en: "5 darts"),
        ])
        // A volley emptied by the kernel at the round limit: no stale summary, no caption, no trap.
        #expect(match.snapshot.turn.darts.isEmpty && match.snapshot.turn.summary == nil)

        var tie = try registry.match(.highScore, ["rounds": 1], players: 3)
        tie.play("S20, S20, S20 | T20 | |")
        #expect(tie.snapshot.ranks == [1, 1, 3])
        #expect(tie.snapshot.outcome == LocalizedText(fr: "Égalité à 60 points.", en: "Tied on 60 points."))
        #expect(tie.snapshot.players[2].resultLines == [
            LocalizedText(fr: "Moyenne par volée : 0,0", en: "Average per turn: 0.0"),
            LocalizedText(fr: "0 fléchette", en: "0 darts"),
        ])
        var one = try registry.match(.highScore, ["rounds": 1], players: 1)
        one.play("S1 |")
        #expect(one.snapshot.outcome == LocalizedText(fr: "Plus gros total : 1 point.", en: "Highest total: 1 point."))
        #expect(one.snapshot.players[0].resultLines.last == LocalizedText(fr: "1 fléchette", en: "1 dart"))

        // Rounded to the NEAREST tenth: 3 × 100 / 7 = 42.857… shows 42.9, not 42.8; 3 × 1 / 4 = 0.75 shows 0.8.
        var rounded = try registry.match(.highScore, ["rounds": 3], players: 1)
        rounded.play("T20, S20, S20 | MISS ×3 | MISS |")
        #expect(rounded.phase == .finished && rounded.fact(0, "dartsThrown") == 7)
        #expect(rounded.snapshot.players[0].resultLines.first == LocalizedText(fr: "Moyenne par volée : 42,9", en: "Average per turn: 42.9"))
        var half = try registry.match(.highScore, ["rounds": 2], players: 1)
        half.play("S1, MISS, MISS | MISS |")
        #expect(half.snapshot.players[0].resultLines.first == LocalizedText(fr: "Moyenne par volée : 0,8", en: "Average per turn: 0.8"))
    }

    // MARK: Same bed, same effect; replay (GAMES.md §2.2, §2.5)

    @Test func effectKey_andPosition() throws {
        let match = try registry.match(.highScore, players: 2)
        #expect(match.effectKey(for: .single(20)) == match.effectKey(for: .double(10)))
        #expect(match.effectKey(for: .single(6)) == match.effectKey(for: .treble(2)))
        #expect(match.effectKey(for: .single(20)) != match.effectKey(for: .single(19)))
        #expect(match.effectKey(for: .miss) != match.effectKey(for: .single(1)))
        #expect(match.effectKey(for: .single(20), position: BoardPoint(x: 1, y: 134)) == match.effectKey(for: .single(20)))

        var plain = try registry.match(.highScore, players: 2)
        var placed = try registry.match(.highScore, players: 2)
        for (index, hit) in [Hit.treble(20), .miss, .innerBull, .single(3)].enumerated() {
            let position = BoardPoint(x: index % 2 == 0 ? .infinity : 12.5, y: -40)
            #expect(plain.throwDart(DartRecord(hit: hit)) == placed.throwDart(DartRecord(hit: hit, position: position)))
            #expect(plain.snapshot == placed.snapshot)
        }
    }

    @Test func undoAndCorrections_rebuildTheSameState() throws {
        var match = try registry.match(.highScore, ["rounds": 2], players: 2)
        var history = [match.snapshot]
        var replayed = try registry.match(.highScore, ["rounds": 2], players: 2)
        match.play("T20, T20, T20 | S5 | DB, SB, S20 | T19, D16, S7 |")
        #expect(match.phase == .finished)
        for entry in match.entries {
            switch entry {
            case .dart(let record): replayed.throwDart(record)
            case .endTurn: replayed.endTurn()
            }
            history.append(replayed.snapshot)
        }
        #expect(replayed.snapshot == match.snapshot)
        #expect(try registry.restoreMatch(match.record).snapshot == match.snapshot)
        // The last turn is confirmed, hence locked; undoing the confirmation reopens it.
        #expect(!match.replaceDart(at: 0, with: .miss).applied)
        match.undo()
        #expect(match.phase == .turnComplete && match.turnNotation == ["T19", "D16", "S7"])
        #expect(match.replaceDart(at: 2, with: .treble(7)).applied && match.fact(1, "points") == 115)
        #expect(match.removeDart(at: 0).applied && match.fact(1, "points") == 58 && match.phase == .throwing)
        match.play("T19 |")
        #expect(match.phase == .finished && points(match) == [275, 115])
        var index = history.count - 1
        var steps = 0
        while match.canUndo {
            match.undo()
            steps += 1
            index -= 1
            if steps > 3 {
                // Past the edited turn the journal is the original one again.
                #expect(match.snapshot == history[index])
            }
        }
        #expect(index == 0 && match.snapshot == history[0])
    }
}
