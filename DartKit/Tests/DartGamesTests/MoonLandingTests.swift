import Testing
import DartCore
import DartGames
import DartTestSupport

/// GAMES.md §10 Alunissage (`moonLanding`): the vectors MOO-1 to MOO-4 of §10.9, then every rule paragraph.
@Suite struct MoonLandingTests {
    private let registry = GameRegistry.standard

    /// One integer fact for every player, in playing order.
    private func ints(_ match: GameMatch, _ name: String) -> [Int] {
        match.snapshot.players.map { row in
            if case .int(let value)? = row.facts[name] { return value }
            return Int.min
        }
    }

    // MARK: Vectors of GAMES.md §10.9

    @Test func moo1_beginnerOvershootIsEnough() throws {
        var match = try registry.match(.moonLanding, players: 2)
        let outcomes = match.play("T20, T20, T20 | S20, S20, S20 | T20")
        #expect(match.phase == .finished && match.snapshot.finishReason == .victory)
        #expect(match.fact(0, "remaining") == 0 && match.fact(1, "remaining") == 140)
        #expect(match.snapshot.ranks == [1, 2])
        #expect(outcomes.last?.events == [.dartRegistered(player: 0, hit: .treble(20)), .landed(player: 0),
                                          .gameFinished(reason: .victory)])
        // A game won on a dart keeps its volley (GAMES.md §2.6).
        #expect(match.turnNotation == ["T20"] && match.snapshot.turn.darts.map(\.hit) == [.treble(20)])
    }

    @Test func moo2_proOvershootIsABustThenExactLanding() throws {
        var match = try registry.match(.moonLanding, ["exactLanding": true], players: 1)
        let outcomes = match.play("T20, T20, T20 | T20")
        #expect(outcomes.last?.events == [.dartRegistered(player: 0, hit: .treble(20)), .bust(player: 0, reason: .belowZero),
                                          .turnCompleted(player: 0)])
        #expect(match.fact(0, "remaining") == 20 && match.fact(0, "busts") == 1)
        #expect(match.phase == .turnComplete)
        let before = match.snapshot
        #expect(match.throwDart(DartRecord(hit: .single(20))) == .rejected(.turnComplete))
        #expect(match.snapshot == before && match.entries.count == 5)

        let landing = match.play("| S20")
        #expect(match.phase == .finished && match.snapshot.finishReason == .victory)
        #expect(match.fact(0, "remaining") == 0)
        #expect(landing.last?.events == [.dartRegistered(player: 0, hit: .single(20)), .landed(player: 0),
                                         .gameFinished(reason: .victory)])
    }

    @Test func moo3_proBustCancelsTheWholeTurn() throws {
        var match = try registry.match(.moonLanding, ["exactLanding": true], players: 1)
        match.play("T20, T20, T20 | S10")
        #expect(match.fact(0, "remaining") == 10)
        match.play("T20")
        #expect(match.fact(0, "remaining") == 20)
        #expect(match.phase == .turnComplete && match.turnNotation == ["S10", "T20"])
        #expect(match.fact(0, "busts") == 1)
    }

    @Test func moo4_roundLimitAndTie() throws {
        var match = try registry.match(.moonLanding, ["maxRounds": 1], players: 2)
        let outcomes = match.play("T20, MISS, MISS | S20, S20, S20 |")
        #expect(match.phase == .finished && match.snapshot.finishReason == .roundLimit)
        #expect(ints(match, "remaining") == [140, 140])
        #expect(match.snapshot.ranks == [1, 1] && match.snapshot.winners == [0, 1])
        #expect(outcomes.last?.events == [.gameFinished(reason: .roundLimit)])
        // A game finished at the round limit has an empty volley (GAMES.md §2.6).
        #expect(match.snapshot.turn.darts.isEmpty && match.currentTurn.isEmpty)
    }

    // MARK: §10.2 Options

    @Test func options_defaultsAre200BeginnerAnd15Rounds() throws {
        let match = try registry.match(.moonLanding, players: 3)
        #expect(ints(match, "remaining") == [200, 200, 200])
        #expect(ints(match, "dartsThrown") == [0, 0, 0] && ints(match, "busts") == [0, 0, 0])
        #expect(match.snapshot.roundLimit == 15)
        #expect(match.snapshot.ranks == [1, 1, 1])
        #expect(match.configuration.options == MoonLandingRules.descriptor.defaultOptions)
    }

    @Test(arguments: [100, 101, 200, 300, 500, 642, 999])
    func options_distanceFrom100To999IsAccepted(distance: Int) throws {
        let match = try registry.match(.moonLanding, ["distance": .int(distance)], players: 2)
        #expect(ints(match, "remaining") == [distance, distance])
    }

    @Test(arguments: [OptionValue.int(99), .int(1000), .int(0), .int(-200), .int(Int.max), .string("200"), .bool(true),
                      .null, .strings(["200"])])
    func options_distanceOutside100To999IsRefused(value: OptionValue) {
        #expect(throws: GameConfigurationError.invalidOptionValue(key: "distance")) {
            try registry.match(.moonLanding, ["distance": value], players: 2)
        }
    }

    @Test func options_schemaRefusals() {
        #expect(throws: GameConfigurationError.invalidOptionValue(key: "exactLanding")) {
            try registry.match(.moonLanding, ["exactLanding": 1], players: 2)
        }
        #expect(throws: GameConfigurationError.invalidOptionValue(key: "maxRounds")) {
            try registry.match(.moonLanding, ["maxRounds": 100], players: 2)
        }
        #expect(throws: GameConfigurationError.invalidOptionValue(key: "maxRounds")) {
            try registry.match(.moonLanding, ["maxRounds": 0], players: 2)
        }
        #expect(throws: GameConfigurationError.playerCountOutOfRange(allowed: 1...8, actual: 9)) {
            try registry.match(.moonLanding, players: 9)
        }
        #expect(throws: GameConfigurationError.playerCountOutOfRange(allowed: 1...8, actual: 0)) {
            try registry.match(.moonLanding, players: 0)
        }
        #expect(throws: GameConfigurationError.unknownOption(key: "level")) {
            try registry.match(.moonLanding, ["level": "pro"], players: 2)
        }
    }

    @Test func options_noRoundLimitNeverEndsOnAConfirmation() throws {
        var match = try registry.match(.moonLanding, ["maxRounds": .null], players: 2)
        #expect(match.snapshot.roundLimit == nil)
        for _ in 0..<120 { match.play("MISS ×3 |") }
        #expect(match.phase == .throwing && match.snapshot.round == 61 && ints(match, "remaining") == [200, 200])
    }

    @Test func options_roundLimitEndsOnlyAtTheConfirmationOfTheLastTurn() throws {
        var match = try registry.match(.moonLanding, ["maxRounds": 2], players: 2)
        match.play("S1 | S2 | S3 | S4, S5, S6")
        #expect(match.phase == .turnComplete && match.snapshot.round == 2)
        #expect(match.endTurn().events == [.gameFinished(reason: .roundLimit)])
        #expect(ints(match, "remaining") == [196, 183] && match.snapshot.ranks == [2, 1])
        #expect(match.throwDart(DartRecord(hit: .single(1))) == .rejected(.gameFinished))
        #expect(match.endTurn() == .rejected(.gameFinished))
    }

    // MARK: §10.4 Effect of a dart

    @Test func dart_everyBedCountsItsPoints() throws {
        for hit in Hit.all where !hit.isMiss {
            var match = try registry.match(.moonLanding, ["distance": 999], players: 1)
            let outcome = match.throwDart(DartRecord(hit: hit))
            #expect(outcome.events == [.dartRegistered(player: 0, hit: hit)], "\(hit)")
            #expect(match.fact(0, "remaining") == .int(999 - hit.points), "\(hit)")
            #expect(match.fact(0, "dartsThrown") == 1 && match.phase == .throwing)
        }
        var match = try registry.match(.moonLanding, ["distance": 999], players: 1)
        match.play("SB, DB, D20 | T19")
        #expect(match.fact(0, "remaining") == .int(999 - 25 - 50 - 40 - 57))
    }

    @Test(arguments: [false, true])
    func dart_missHasNoEffectAndNeverBusts(exact: Bool) throws {
        var match = try registry.match(.moonLanding, ["distance": 100, "exactLanding": .bool(exact)], players: 1)
        let outcomes = match.play("T20, S20, MISS")
        #expect(outcomes[2].events == [.dartRegistered(player: 0, hit: .miss), .noEffect(player: 0),
                                       .turnScored(player: 0, points: 80), .turnCompleted(player: 0)])
        #expect(match.fact(0, "remaining") == 20 && match.fact(0, "dartsThrown") == 3 && match.fact(0, "busts") == 0)
    }

    @Test func dart_beginnerLandsExactlyOrBeyond() throws {
        // Exactly zero.
        var exact = try registry.match(.moonLanding, ["distance": 100], players: 1)
        #expect(exact.play("DB, DB").last?.events == [.dartRegistered(player: 0, hit: .innerBull), .landed(player: 0),
                                                       .gameFinished(reason: .victory)])
        #expect(exact.fact(0, "remaining") == 0 && exact.phase == .finished)
        // Beyond zero: the distance is clamped, never negative.
        var beyond = try registry.match(.moonLanding, ["distance": 100], players: 1)
        beyond.play("T20, S19, T20")
        #expect(beyond.fact(0, "remaining") == 0 && beyond.phase == .finished && beyond.fact(0, "busts") == 0)
        #expect(beyond.snapshot.finishReason == .victory)
    }

    @Test func dart_proThreeCases() throws {
        // R − v > 0: the distance goes down.
        var match = try registry.match(.moonLanding, ["distance": 100, "exactLanding": true], players: 1)
        match.play("T20, S19")
        #expect(match.fact(0, "remaining") == 21 && match.phase == .throwing)
        // R − v == 0: victory, on any bed (no double is required).
        var landed = match
        #expect(landed.play("T7").last?.events == [.dartRegistered(player: 0, hit: .treble(7)), .landed(player: 0),
                                                   .gameFinished(reason: .victory)])
        #expect(landed.fact(0, "remaining") == 0 && landed.snapshot.finishReason == .victory)
        // R − v < 0, by one point only: bust.
        var busted = match
        #expect(busted.play("D11").last?.events == [.dartRegistered(player: 0, hit: .double(11)),
                                                    .bust(player: 0, reason: .belowZero), .turnCompleted(player: 0)])
        #expect(busted.fact(0, "remaining") == 100 && busted.fact(0, "busts") == 1 && busted.phase == .turnComplete)
        // One point left is playable in Pro mode: there is no "one left" bust here.
        var one = match
        one.play("S20")
        #expect(one.fact(0, "remaining") == 1 && one.phase == .turnComplete && one.fact(0, "busts") == 0)
        one.play("| S1")
        #expect(one.phase == .finished && one.fact(0, "remaining") == 0)
    }

    @Test func dart_fourthDartAndDartsAfterTheEndAreRefused() throws {
        var match = try registry.match(.moonLanding, players: 2)
        match.play("S1, S1, S1")
        #expect(match.throwDart(DartRecord(hit: .single(1))) == .rejected(.turnComplete))
        #expect(match.fact(0, "remaining") == 197 && match.entries.count == 3)
        match.play("| T20, T20, T20 | MISS ×3 | T20")
        #expect(match.phase == .finished)
        #expect(match.throwDart(DartRecord(hit: .single(1))) == .rejected(.gameFinished))
        #expect(match.endTurn() == .rejected(.gameFinished))
    }

    // MARK: §10.5 Turn

    @Test func turn_bustRestoresTheDistanceOfTheTurnStartAndCountsTheDarts() throws {
        var match = try registry.match(.moonLanding, ["distance": 100, "exactLanding": true], players: 2)
        match.play("T20 | MISS ×3 | S20, S10")
        #expect(match.fact(0, "remaining") == 10)
        let bust = match.play("S11")
        #expect(bust[0].events == [.dartRegistered(player: 0, hit: .single(11)), .bust(player: 0, reason: .belowZero),
                                   .turnCompleted(player: 0)])
        // The turn started at 40: both counted darts are cancelled. The darts were thrown all the same.
        #expect(ints(match, "remaining") == [40, 100] && ints(match, "busts") == [1, 0])
        #expect(ints(match, "dartsThrown") == [4, 3])
        // A bust on the first dart closes the turn at once.
        match.play("| MISS ×3 |")
        #expect(match.play("DB")[0].events.contains(.bust(player: 0, reason: .belowZero)))
        #expect(match.phase == .turnComplete && match.turnNotation == ["DB"])
        #expect(ints(match, "remaining") == [40, 100] && ints(match, "busts") == [2, 0])
        // The next turn starts from the restored distance.
        match.play("| MISS ×3 | D20")
        #expect(match.phase == .finished && match.snapshot.ranks == [1, 2])
    }

    @Test func turn_closingEventsOfARawPointsGame() throws {
        var match = try registry.match(.moonLanding, ["distance": 999], players: 1)
        let outcomes = match.play("T20, T20, T20 | T20, T20, S20 | S20, S20, S20 | T20, T20, T19 | T20, S20, S20")
        #expect(outcomes[2].events == [.dartRegistered(player: 0, hit: .treble(20)), .turnScored(player: 0, points: 180),
                                       .oneEighty(player: 0), .turnCompleted(player: 0)])
        #expect(outcomes[3].events == [.roundStarted(round: 2), .turnStarted(player: 0, round: 2)])
        #expect(outcomes[6].events == [.dartRegistered(player: 0, hit: .single(20)), .turnScored(player: 0, points: 140),
                                       .highTurn(player: 0, points: 140), .turnCompleted(player: 0)])
        #expect(outcomes[10].events == [.dartRegistered(player: 0, hit: .single(20)), .turnScored(player: 0, points: 60),
                                        .turnCompleted(player: 0)])
        // 179 is still a high turn, 100 is the first one, 99 is none.
        #expect(outcomes[14].events == [.dartRegistered(player: 0, hit: .treble(19)), .turnScored(player: 0, points: 177),
                                        .highTurn(player: 0, points: 177), .turnCompleted(player: 0)])
        #expect(outcomes[18].events == [.dartRegistered(player: 0, hit: .single(20)), .turnScored(player: 0, points: 100),
                                        .highTurn(player: 0, points: 100), .turnCompleted(player: 0)])
        var low = try registry.match(.moonLanding, ["distance": 999], players: 1)
        #expect(low.play("T20, S20, S19")[2].events == [.dartRegistered(player: 0, hit: .single(19)),
                                                        .turnScored(player: 0, points: 99), .turnCompleted(player: 0)])
    }

    @Test func turn_earlyConfirmationScoresWhatWasThrown() throws {
        var match = try registry.match(.moonLanding, players: 2)
        #expect(match.endTurn().events == [.turnScored(player: 0, points: 0), .turnCompleted(player: 0),
                                           .turnStarted(player: 1, round: 1)])
        match.play("T20, T20")
        #expect(match.endTurn().events == [.turnScored(player: 1, points: 120), .highTurn(player: 1, points: 120),
                                           .turnCompleted(player: 1), .roundStarted(round: 2), .turnStarted(player: 0, round: 2)])
        #expect(ints(match, "remaining") == [200, 80] && ints(match, "dartsThrown") == [0, 2])
        #expect(match.snapshot.currentPlayer == 0 && match.snapshot.round == 2 && match.snapshot.turn.darts.isEmpty)
    }

    @Test func turn_aBustedTurnEmitsNoTurnScore() throws {
        var match = try registry.match(.moonLanding, ["distance": 100, "exactLanding": true], players: 1)
        let outcomes = match.play("T20, T20")
        #expect(!outcomes[1].events.contains { if case .turnScored = $0 { return true } else { return false } })
        // The confirmation of an already closed turn closes nothing a second time.
        #expect(match.endTurn().events == [.roundStarted(round: 2), .turnStarted(player: 0, round: 2)])
    }

    // MARK: §10.6 Ranking

    @Test func ranking_smallestDistanceFirstWithSharedRanks() throws {
        var match = try registry.match(.moonLanding, ["maxRounds": 1], players: 4)
        match.play("S20 | T20 | S20 | S5")
        #expect(match.snapshot.ranks == [2, 1, 2, 4])
        match.play("|")
        #expect(match.phase == .finished && match.snapshot.ranks == [2, 1, 2, 4] && match.snapshot.winners == [1])
        #expect(match.snapshot.players.map(\.rank) == [2, 1, 2, 4])
        #expect(match.snapshot.players.allSatisfy { !$0.isEliminated })
    }

    // MARK: §10.7 Scoreboard and highlights

    @Test func highlights_noneInBeginnerMode() throws {
        var match = try registry.match(.moonLanding, players: 1)
        #expect(match.snapshot.highlights.isEmpty)
        match.play("T20, T20, T20 |")
        #expect(match.fact(0, "remaining") == 20 && match.snapshot.highlights.isEmpty)
    }

    @Test func highlights_proShowsTheBedsWorthExactlyTheDistance() throws {
        var match = try registry.match(.moonLanding, ["distance": 100, "exactLanding": true], players: 2)
        #expect(match.snapshot.highlights.isEmpty)   // nothing is worth 100
        match.play("T20")                            // 40 left
        #expect(Set(match.snapshot.highlights) == [BoardHighlight(zone: .double(20), role: .target)])
        match.play("S4")                             // 36 left
        #expect(Set(match.snapshot.highlights) == [BoardHighlight(zone: .double(18), role: .target),
                                                   BoardHighlight(zone: .treble(12), role: .target)])
        match.play("S18")                            // 18 left, turn complete: still for the current player
        #expect(match.phase == .turnComplete)
        #expect(Set(match.snapshot.highlights) == [BoardHighlight(zone: .single(18), role: .target),
                                                   BoardHighlight(zone: .double(9), role: .target),
                                                   BoardHighlight(zone: .treble(6), role: .target)])
        match.play("| DB")                           // J2: 50 left
        #expect(match.snapshot.highlights == [BoardHighlight(zone: .innerBull, role: .target)])
        match.play("SB")                             // J2: 25 left
        #expect(match.snapshot.highlights == [BoardHighlight(zone: .outerBull, role: .target)])
        match.play("S2")                             // J2: 23 left, no bed is worth 23
        #expect(match.snapshot.highlights.isEmpty)
        match.play("| T6")                           // J1 lands: no highlight once finished
        #expect(match.phase == .finished && match.snapshot.highlights.isEmpty)
    }

    @Test func highlights_everyHighlightedBedLandsAndNoOtherDoes() throws {
        for distance in 1...60 {
            var match = try registry.match(.moonLanding, ["distance": .int(100 + distance), "exactLanding": true], players: 1)
            match.play("DB, DB |")
            #expect(match.fact(0, "remaining") == .int(distance))
            let zones = match.snapshot.highlights.map(\.zone)
            #expect(match.snapshot.highlights.allSatisfy { $0.role == .target && $0.owner == nil })
            #expect(Set(zones).count == zones.count)
            for hit in Hit.all {
                var copy = match
                copy.throwDart(DartRecord(hit: hit))
                #expect((copy.phase == .finished) == zones.contains { $0.contains(hit) }, "\(distance) \(hit)")
            }
        }
    }

    @Test func presentation_titleVariantRowsAndTurn() throws {
        var beginner = try registry.match(.moonLanding, players: 2)
        #expect(beginner.snapshot.title == LocalizedText(fr: "Alunissage", en: "Moon Landing"))
        #expect(beginner.snapshot.variant == LocalizedText(fr: "Débutant", en: "Beginner"))
        #expect(beginner.snapshot.gameID == .moonLanding && beginner.snapshot.winnerTitle == nil)
        #expect(beginner.snapshot.players.map(\.primary) == [ScoreValue(200), ScoreValue(200)])
        #expect(beginner.snapshot.players.map(\.detail) == [nil, nil])
        #expect(beginner.snapshot.turn.summary == LocalizedText(fr: "Volée : 0", en: "Turn: 0"))
        beginner.play("T20, S5")
        #expect(beginner.snapshot.turn.darts.map(\.caption) == [DartCaption(LocalizedText(verbatim: "60")),
                                                                 DartCaption(LocalizedText(verbatim: "5"))])
        #expect(beginner.snapshot.turn.summary == LocalizedText(fr: "Volée : 65", en: "Turn: 65"))
        #expect(beginner.snapshot.turn.capacity == 3)
        beginner.play("MISS |")
        #expect(beginner.snapshot.players[0].primary == ScoreValue(135))
        #expect(beginner.snapshot.players[0].detail == LocalizedText(fr: "Dernière volée : 65", en: "Last turn: 65"))
        #expect(beginner.snapshot.players[1].detail == nil)
        #expect(beginner.snapshot.turn.summary == LocalizedText(fr: "Volée : 0", en: "Turn: 0"))
        #expect(beginner.snapshot.outcome == nil)

        var pro = try registry.match(.moonLanding, ["distance": 100, "exactLanding": true], players: 1)
        #expect(pro.snapshot.variant == LocalizedText(verbatim: "Pro"))
        pro.play("T20, DB")
        #expect(pro.snapshot.turn.summary == LocalizedText(verbatim: "BUST"))
        #expect(pro.snapshot.turn.darts.map(\.caption) == [DartCaption(LocalizedText(verbatim: "60")),
                                                            DartCaption(LocalizedText(verbatim: "BUST"), tone: .negative)])
        #expect(pro.snapshot.players[0].detail == LocalizedText(verbatim: "BUST"))
        pro.play("| T20, D20")
        #expect(pro.phase == .finished)
        #expect(pro.snapshot.turn.darts.last?.caption == DartCaption(LocalizedText(fr: "Posé !", en: "Landed!"), tone: .positive))
    }

    @Test func presentation_resultsAfterAVictoryAndAfterTheRoundLimit() throws {
        var won = try registry.match(.moonLanding, ["distance": 100], players: 2)
        won.play("T20 | S1 | T20")
        #expect(won.snapshot.outcome == LocalizedText(fr: "Posé sur la Lune en 2 fléchettes.", en: "Landed on the Moon in 2 darts."))
        #expect(won.snapshot.winnerTitle == nil && won.snapshot.winners == [0])
        #expect(won.snapshot.players[0].resultLines == [LocalizedText(fr: "2 fléchettes", en: "2 darts")])

        var limit = try registry.match(.moonLanding, ["distance": 100, "exactLanding": true, "maxRounds": 1], players: 3)
        limit.play("T20, T20 | T20 | S20 |")
        #expect(limit.phase == .finished && limit.snapshot.finishReason == .roundLimit && limit.snapshot.ranks == [3, 1, 2])
        #expect(limit.snapshot.outcome == LocalizedText(fr: "Le plus proche de la Lune : encore 40.",
                                                        en: "Closest to the Moon: 40 to go."))
        #expect(limit.snapshot.players[0].resultLines == [LocalizedText(fr: "2 fléchettes", en: "2 darts"),
                                                          LocalizedText(fr: "1 bust", en: "1 bust")])
        // The volley is empty while the rule still remembers the last turn: no caption, no stale summary.
        #expect(limit.snapshot.turn.darts.isEmpty && limit.snapshot.turn.summary == nil)

        var tie = try registry.match(.moonLanding, ["maxRounds": 1], players: 2)
        tie.play("S20 | S20 |")
        #expect(tie.snapshot.outcome == LocalizedText(fr: "Égalité à 180 de la Lune.", en: "Tied, 180 away from the Moon."))
    }

    // MARK: Undo, corrections, replay (GAMES.md §2.5)

    @Test func correction_undoingTheLandingDartReopensTheGame() throws {
        var match = try registry.match(.moonLanding, ["distance": 100], players: 2)
        match.play("T20 | S1 | T20")
        #expect(match.phase == .finished)
        match.undo()
        #expect(match.phase == .throwing && ints(match, "remaining") == [40, 99] && match.snapshot.finishReason == nil)
        #expect(match.snapshot.currentPlayer == 0 && match.snapshot.round == 2 && match.turnNotation.isEmpty)
        // J2 had confirmed after one dart: undoing that confirmation reopens a turn that was never full.
        match.undo()
        #expect(match.phase == .throwing && match.snapshot.currentPlayer == 1 && match.turnNotation == ["S1"])
        #expect(match.snapshot.round == 1 && ints(match, "remaining") == [40, 99])
    }

    @Test func correction_replacingTheBustDartReopensTheTurn() throws {
        var match = try registry.match(.moonLanding, ["distance": 100, "exactLanding": true], players: 1)
        match.play("T20 | S10, T20")
        #expect(match.phase == .turnComplete && match.fact(0, "remaining") == 40 && match.fact(0, "busts") == 1)
        let edit = match.replaceDart(at: 1, with: .single(20))
        #expect(edit.applied && edit.dropped.isEmpty)
        #expect(match.phase == .throwing && match.fact(0, "remaining") == 10 && match.fact(0, "busts") == 0)
        #expect(match.turnNotation == ["S10", "S20"])
        // And the other way round: a correction that creates a bust drops the darts that follow.
        match.play("S5")
        #expect(match.phase == .turnComplete && match.fact(0, "remaining") == 5)
        let bust = match.replaceDart(at: 0, with: .innerBull)
        #expect(bust.applied && bust.dropped.map(\.hit) == [.single(20), .single(5)])
        #expect(match.turnNotation == ["DB"] && match.phase == .turnComplete)
        #expect(match.fact(0, "remaining") == 40 && match.fact(0, "busts") == 1 && match.fact(0, "dartsThrown") == 2)
    }

    @Test func correction_aCorrectedDartCanWinAndRemovingItReopens() throws {
        var match = try registry.match(.moonLanding, ["distance": 100], players: 1)
        match.play("T20, S1, S1")
        let win = match.replaceDart(at: 1, with: .double(20))
        #expect(win.applied && win.dropped.map(\.hit) == [.single(1)])
        #expect(match.phase == .finished && match.turnNotation == ["T20", "D20"])
        match.removeDart(at: 1)
        #expect(match.phase == .throwing && match.fact(0, "remaining") == 40 && match.turnNotation == ["T20"])
    }

    @Test func position_aRecordedPositionChangesNothing() throws {
        var plain = try registry.match(.moonLanding, ["exactLanding": true], players: 2)
        var placed = plain
        let script: [Hit] = [.treble(20), .single(5), .miss, .innerBull, .double(3), .treble(19)]
        for (index, hit) in script.enumerated() {
            let a = plain.throwDart(DartRecord(hit: hit))
            let b = placed.throwDart(DartRecord(hit: hit, position: BoardPoint(x: Double(index) * 31 - 80, y: 12.5)))
            #expect(a == b)
            if plain.phase == .turnComplete { #expect(plain.endTurn() == placed.endTurn()) }
        }
        #expect(plain.snapshot == placed.snapshot)
        #expect(plain.effectKey(for: .single(20)) == plain.effectKey(for: .single(20), position: BoardPoint(x: 3, y: 4)))
    }

    @Test func effectKey_groupsTheDartsOfEqualEffect() throws {
        // Beginner, 20 left: every dart worth 20 or more lands.
        var beginner = try registry.match(.moonLanding, players: 1)
        beginner.play("T20, T20, T20 |")
        #expect(beginner.effectKey(for: .single(20)) == beginner.effectKey(for: .treble(20)))
        #expect(beginner.effectKey(for: .single(20)) != beginner.effectKey(for: .single(19)))
        // Pro, 20 left: every overshoot is the same bust; the exact dart is something else.
        var pro = try registry.match(.moonLanding, ["exactLanding": true], players: 1)
        pro.play("T20, T20, T20 |")
        #expect(pro.effectKey(for: .treble(20)) == pro.effectKey(for: .innerBull))
        #expect(pro.effectKey(for: .treble(20)) != pro.effectKey(for: .double(10)))
        #expect(pro.effectKey(for: .single(20)) == pro.effectKey(for: .double(10)))
        #expect(pro.effectKey(for: .single(3)) != pro.effectKey(for: .single(4)))
    }

    @Test(arguments: [false, true])
    func effectKey_equalKeysLeaveEqualFutures(exact: Bool) throws {
        var pairs = 0
        for seed in UInt64(1)...3 {
            pairs += try MoonLandingReplayChecks.equalKeysHaveEqualFutures(
                .moonLanding, ["distance": 120, "exactLanding": .bool(exact), "maxRounds": 6], players: 2, seed: seed,
                fuzzSeed: seed &+ 40, states: 40, hits: Hit.all)
        }
        #expect(pairs > 100)
    }

    @Test(arguments: [false, true])
    func replay_theJournalAloneRebuildsTheGame(exact: Bool) throws {
        // Big darts to come close quickly, small ones to land exactly.
        let hits: [Hit] = [.miss, .single(20), .double(20), .treble(20), .treble(19), .innerBull, .outerBull, .double(10),
                           .treble(7), .single(13), .single(1), .single(2), .single(3), .single(4), .single(5), .double(1)]
        // One dart out of four goes to a highlighted bed when there is one (Pro mode: a bed that lands exactly).
        func pick(_ snapshot: GameSnapshot, _ random: inout SeededRandom) -> Hit {
            let landing = Hit.all.filter { hit in snapshot.highlights.contains { $0.zone.contains(hit) } }
            guard random.nextInt(below: 4) == 0, !landing.isEmpty else { return hits[random.nextInt(below: hits.count)] }
            return landing[random.nextInt(below: landing.count)]
        }
        var busts = 0, landings = 0
        for fuzzSeed in UInt64(1)...5 {
            for players in [1, 2, 5] {
                try MoonLandingReplayChecks.fuzz(
                    .moonLanding, ["distance": 150, "exactLanding": .bool(exact), "maxRounds": 8], players: players,
                    seed: fuzzSeed, fuzzSeed: fuzzSeed &* 77 &+ UInt64(players), steps: 140, pick: pick
                ) { snapshot in
                    landings += snapshot.finishReason == .victory ? 1 : 0
                    for row in snapshot.players {
                        guard case .int(let remaining)? = row.facts["remaining"], case .int(let darts)? = row.facts["dartsThrown"],
                              case .int(let count)? = row.facts["busts"] else {
                            Issue.record("missing fact")
                            return
                        }
                        #expect((0...150).contains(remaining) && darts >= 0 && count >= 0 && count <= darts)
                        #expect(row.primary == ScoreValue(remaining) && !row.isEliminated)
                        busts += count
                    }
                    let landed = snapshot.players.contains { $0.facts["remaining"] == .int(0) }
                    #expect(landed == (snapshot.finishReason == .victory))
                    if !exact { #expect(snapshot.highlights.isEmpty) }
                }
            }
        }
        // The walk is not a quiet one: games are won along the way, and busts happen in Pro mode only.
        #expect(landings > 20 && (busts > 100) == exact && (busts == 0) != exact)
    }
}
