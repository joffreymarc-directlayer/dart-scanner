import Testing
import DartCore
import DartGames
import DartTestSupport

/// GAMES.md §11 Combat (`fight`): the vectors FIG-1 to FIG-4 of §11.9, then every rule paragraph.
///
/// With seed 1 the draw is `shuffled([1…20]) = [2, 15, 11, 4, 20, 5, 7, 17, 16, 14, 3, 1, 12, 8, 19, 10, 18, 13, 9, 6]`
/// (GAMES.md §2.8), so: J1 heal 2, weak 15 and 11; J2 heal 4, weak 20 and 5; J3 heal 7, weak 17 and 16;
/// J4 heal 14, weak 3 and 1; J5 heal 12, weak 8 and 19; J6 heal 10, weak 18 and 13; 9 and 6 belong to nobody.
@Suite struct FightTests {
    private let registry = GameRegistry.standard

    /// One integer fact for every player, in playing order.
    private func ints(_ match: GameMatch, _ name: String) -> [Int] {
        match.snapshot.players.map { row in
            if case .int(let value)? = row.facts[name] { return value }
            return Int.min
        }
    }

    private func eliminated(_ match: GameMatch) -> [Bool] {
        match.snapshot.players.map { $0.facts["eliminated"] == .bool(true) }
    }

    // MARK: Vectors of GAMES.md §11.9

    @Test func fig1_damageHealAndCappedHeal() throws {
        var match = try registry.match(.fight, players: 2, seed: 1)
        #expect(match.fact(0, "healNumber") == 2 && match.fact(0, "weakNumbers") == [15, 11])
        #expect(match.fact(1, "healNumber") == 4 && match.fact(1, "weakNumbers") == [20, 5])
        #expect(ints(match, "lives") == [9, 9])

        let first = match.play("T20, D5, S2")
        #expect(ints(match, "lives") == [9, 4])
        #expect(first[0].events == [.dartRegistered(player: 0, hit: .treble(20)),
                                    .damaged(player: 1, by: 0, amount: 3, livesLeft: 6)])
        #expect(first[1].events == [.dartRegistered(player: 0, hit: .double(5)),
                                    .damaged(player: 1, by: 0, amount: 2, livesLeft: 4)])
        // S2 is J1's heal number, and J1 is already at the maximum.
        #expect(first[2].events == [.dartRegistered(player: 0, hit: .single(2)), .healWasted(player: 0),
                                    .turnCompleted(player: 0)])

        let second = match.play("| S4, T15, S11")
        #expect(ints(match, "lives") == [5, 5])
        #expect(second[1].events == [.dartRegistered(player: 1, hit: .single(4)), .healed(player: 1, amount: 1, lives: 5)])
        #expect(second[2].events == [.dartRegistered(player: 1, hit: .treble(15)),
                                     .damaged(player: 0, by: 1, amount: 3, livesLeft: 6)])
        #expect(second[3].events == [.dartRegistered(player: 1, hit: .single(11)),
                                     .damaged(player: 0, by: 1, amount: 1, livesLeft: 5), .turnCompleted(player: 1)])

        let third = match.play("| T2, S15, S4")
        #expect(ints(match, "lives") == [8, 5])
        #expect(third[1].events == [.dartRegistered(player: 0, hit: .treble(2)), .healed(player: 0, amount: 3, lives: 8)])
        // S15 is a weak spot of J1 himself, S4 is the heal number of J2: no effect.
        #expect(third[2].events == [.dartRegistered(player: 0, hit: .single(15)), .noEffect(player: 0)])
        #expect(third[3].events == [.dartRegistered(player: 0, hit: .single(4)), .noEffect(player: 0), .turnCompleted(player: 0)])
        #expect(ints(match, "kills") == [0, 0] && eliminated(match) == [false, false])
    }

    @Test func fig2_knockOutAndCappedDamage() throws {
        var match = try registry.match(.fight, players: 2, seed: 1)
        let outcomes = match.play("T20, T20, T5")
        #expect(ints(match, "lives") == [9, 0] && eliminated(match) == [false, true])
        #expect(match.phase == .finished && match.snapshot.finishReason == .lastPlayerStanding)
        #expect(match.snapshot.ranks == [1, 2])
        #expect(outcomes[2].events == [.dartRegistered(player: 0, hit: .treble(5)),
                                       .damaged(player: 1, by: 0, amount: 3, livesLeft: 0),
                                       .playerEliminated(player: 1, by: 0), .gameFinished(reason: .lastPlayerStanding)])
        #expect(ints(match, "kills") == [1, 0])

        var short = try registry.match(.fight, ["lives": 2], players: 2, seed: 1)
        let events = short.play("T20")[0].events
        // The treble would take three lives; only two are left: the event carries the real loss.
        #expect(events == [.dartRegistered(player: 0, hit: .treble(20)), .damaged(player: 1, by: 0, amount: 2, livesLeft: 0),
                           .playerEliminated(player: 1, by: 0), .gameFinished(reason: .lastPlayerStanding)])
        #expect(short.phase == .finished && ints(short, "lives") == [2, 0])
    }

    @Test func fig3_threePlayersRoundLimit() throws {
        var match = try registry.match(.fight, ["maxRounds": 1], players: 3, seed: 1)
        #expect(match.fact(2, "healNumber") == 7 && match.fact(2, "weakNumbers") == [17, 16])
        let outcomes = match.play("T20, S5, T17 | T2, D4, S17 | S16, MISS, S15")
        #expect(ints(match, "lives") == [8, 7, 5] && match.phase == .turnComplete)
        // J2: T2 is J1's heal number (no effect), then heal +2. J3: S16 is his own weak spot (no effect).
        #expect(outcomes[4].events == [.dartRegistered(player: 1, hit: .treble(2)), .noEffect(player: 1)])
        #expect(outcomes[5].events == [.dartRegistered(player: 1, hit: .double(4)), .healed(player: 1, amount: 2, lives: 7)])
        #expect(outcomes[8].events == [.dartRegistered(player: 2, hit: .single(16)), .noEffect(player: 2)])
        #expect(match.endTurn().events == [.gameFinished(reason: .roundLimit)])
        #expect(match.phase == .finished && match.snapshot.finishReason == .roundLimit)
        #expect(match.snapshot.ranks == [1, 2, 3])
    }

    @Test func fig4_eliminatedPlayerIsSkippedAndItsNumbersAreInert() throws {
        var match = try registry.match(.fight, players: 3, seed: 1)
        let outcomes = match.play("T20, T5, T20 |")
        #expect(ints(match, "lives") == [9, 0, 9] && eliminated(match) == [false, true, false])
        #expect(match.snapshot.currentPlayer == 2 && match.snapshot.round == 1)
        // Two players are left: the knock-out closes nothing by itself, the third dart closes the turn.
        #expect(outcomes[2].events == [.dartRegistered(player: 0, hit: .treble(20)),
                                       .damaged(player: 1, by: 0, amount: 3, livesLeft: 0),
                                       .playerEliminated(player: 1, by: 0), .turnCompleted(player: 0)])
        #expect(outcomes[3].events == [.turnStarted(player: 2, round: 1)])

        let next = match.play("S20, S4, S15")
        #expect(ints(match, "lives") == [8, 0, 9])
        #expect(next[0].events == [.dartRegistered(player: 2, hit: .single(20)), .noEffect(player: 2)])
        #expect(next[1].events == [.dartRegistered(player: 2, hit: .single(4)), .noEffect(player: 2)])
        #expect(next[2].events == [.dartRegistered(player: 2, hit: .single(15)),
                                   .damaged(player: 0, by: 2, amount: 1, livesLeft: 8), .turnCompleted(player: 2)])
        #expect(match.snapshot.ranks == [2, 3, 1])
    }

    // MARK: §11.2 Options

    @Test func options_defaultsAreNineLivesAnd15Rounds() throws {
        let match = try registry.match(.fight, players: 4, seed: 7)
        #expect(ints(match, "lives") == [9, 9, 9, 9] && ints(match, "kills") == [0, 0, 0, 0])
        #expect(eliminated(match) == [false, false, false, false])
        #expect(match.snapshot.roundLimit == 15 && match.snapshot.ranks == [1, 1, 1, 1])
        #expect(match.configuration.options == FightRules.descriptor.defaultOptions)
    }

    @Test func options_livesFrom1To20AndPlayersFrom2To6() throws {
        for lives in [1, 2, 9, 20] {
            let match = try registry.match(.fight, ["lives": .int(lives)], players: 6, seed: 3)
            #expect(ints(match, "lives") == Array(repeating: lives, count: 6))
            #expect(match.snapshot.players.map(\.meter) == Array(repeating: Meter(value: lives, maximum: lives, style: .bar), count: 6))
        }
        for value in [OptionValue.int(0), .int(21), .null, .string("9")] {
            #expect(throws: GameConfigurationError.invalidOptionValue(key: "lives")) {
                try registry.match(.fight, ["lives": value], players: 2)
            }
        }
        #expect(throws: GameConfigurationError.playerCountOutOfRange(allowed: 2...6, actual: 1)) {
            try registry.match(.fight, players: 1)
        }
        #expect(throws: GameConfigurationError.playerCountOutOfRange(allowed: 2...6, actual: 7)) {
            try registry.match(.fight, players: 7)
        }
        #expect(throws: GameConfigurationError.invalidOptionValue(key: "maxRounds")) {
            try registry.match(.fight, ["maxRounds": 0], players: 2)
        }
        let unlimited = try registry.match(.fight, ["maxRounds": .null], players: 2)
        #expect(unlimited.snapshot.roundLimit == nil)
    }

    // MARK: §11.3 Initial state

    @Test func draw_isTheShuffleOfTheSeedThreeNumbersPerPlayer() throws {
        for seed in UInt64(0)..<40 {
            var random = SeededRandom(seed: seed)
            let shuffled = random.shuffled(Array(1...20))
            for players in 2...6 {
                let match = try registry.match(.fight, players: players, seed: seed)
                for i in 0..<players {
                    #expect(match.fact(i, "healNumber") == .int(shuffled[3 * i]), "seed \(seed)")
                    #expect(match.fact(i, "weakNumbers") == .ints([shuffled[3 * i + 1], shuffled[3 * i + 2]]), "seed \(seed)")
                }
            }
        }
    }

    @Test func draw_noNumberIsSharedAndTheSeedDecides() throws {
        var layouts: Set<[Int]> = []
        for seed in UInt64(0)..<60 {
            let match = try registry.match(.fight, players: 6, seed: seed)
            var numbers: [Int] = []
            for row in match.snapshot.players {
                guard case .int(let heal)? = row.facts["healNumber"], case .ints(let weak)? = row.facts["weakNumbers"] else {
                    Issue.record("missing fact")
                    return
                }
                #expect(weak.count == 2)
                numbers.append(heal)
                numbers += weak
            }
            #expect(numbers.count == 18 && Set(numbers).count == 18 && numbers.allSatisfy((1...20).contains))
            layouts.insert(numbers)
            // Same seed, same draw.
            #expect(try registry.match(.fight, players: 6, seed: seed).snapshot == match.snapshot)
        }
        #expect(layouts.count > 50)
    }

    @Test func draw_sixPlayersSeed1() throws {
        let match = try registry.match(.fight, players: 6, seed: 1)
        #expect(ints(match, "healNumber") == [2, 4, 7, 14, 12, 10])
        #expect(match.snapshot.players.map { $0.facts["weakNumbers"] } == [[15, 11], [20, 5], [17, 16], [3, 1], [8, 19], [18, 13]])
    }

    // MARK: §11.4 Effect of a dart

    @Test func dart_missAndBullsHaveNoEffect() throws {
        for hit in [Hit.miss, .outerBull, .innerBull] {
            var match = try registry.match(.fight, players: 2, seed: 1)
            #expect(match.throwDart(DartRecord(hit: hit)).events == [.dartRegistered(player: 0, hit: hit), .noEffect(player: 0)])
            #expect(ints(match, "lives") == [9, 9])
        }
    }

    @Test func dart_everyNumberDoesWhatItsOwnerSays() throws {
        // Six players, seed 1, J3 throws (heal 7, weak 17 and 16) after losing two lives.
        var base = try registry.match(.fight, players: 6, seed: 1)
        base.play("D17 | MISS | ")
        #expect(base.snapshot.currentPlayer == 2 && ints(base, "lives") == [9, 9, 7, 9, 9, 9])
        let victims: [Int: Int] = [15: 0, 11: 0, 20: 1, 5: 1, 3: 3, 1: 3, 8: 4, 19: 4, 18: 5, 13: 5]
        for number in 1...20 {
            for (hit, force) in [(Hit.single(number), 1), (.double(number), 2), (.treble(number), 3)] {
                var match = base
                let events = match.throwDart(DartRecord(hit: hit)).events
                var lives = [9, 9, 7, 9, 9, 9]
                if number == 7 {
                    let gain = min(2, force)
                    lives[2] += gain
                    #expect(events == [.dartRegistered(player: 2, hit: hit), .healed(player: 2, amount: gain, lives: 7 + gain)], "\(hit)")
                } else if let victim = victims[number] {
                    lives[victim] -= force
                    #expect(events == [.dartRegistered(player: 2, hit: hit),
                                       .damaged(player: victim, by: 2, amount: force, livesLeft: 9 - force)], "\(hit)")
                } else {
                    // 17 and 16 (his own weak spots), 2, 4, 14, 12 and 10 (heal numbers of the others), 9 and 6 (nobody's).
                    #expect(events == [.dartRegistered(player: 2, hit: hit), .noEffect(player: 2)], "\(hit)")
                }
                #expect(ints(match, "lives") == lives, "\(hit)")
            }
        }
    }

    @Test func dart_healIsCappedAtTheStartingLives() throws {
        var match = try registry.match(.fight, players: 2, seed: 1)
        match.play("MISS | S15 |")                      // J1 at 8
        #expect(ints(match, "lives") == [8, 9])
        // A treble would give three lives: only one fits. The event carries the real gain.
        #expect(match.play("T2")[0].events == [.dartRegistered(player: 0, hit: .treble(2)), .healed(player: 0, amount: 1, lives: 9)])
        #expect(match.play("D2")[0].events == [.dartRegistered(player: 0, hit: .double(2)), .healWasted(player: 0)])
        #expect(ints(match, "lives") == [9, 9])
        match.play("MISS | T15, T11 |")                 // J1 at 3
        #expect(match.play("D2")[0].events == [.dartRegistered(player: 0, hit: .double(2)), .healed(player: 0, amount: 2, lives: 5)])
        #expect(match.play("T2")[0].events == [.dartRegistered(player: 0, hit: .treble(2)), .healed(player: 0, amount: 3, lives: 8)])
        #expect(match.play("T2")[0].events == [.dartRegistered(player: 0, hit: .treble(2)), .healed(player: 0, amount: 1, lives: 9),
                                               .turnCompleted(player: 0)])
        #expect(ints(match, "lives") == [9, 9])
    }

    @Test func dart_bothWeakSpotsOfAPlayerHurtHim() throws {
        var match = try registry.match(.fight, ["lives": 20], players: 2, seed: 1)
        match.play("S20, D5, T20 | D15, T11, S11")
        #expect(ints(match, "lives") == [14, 14] && ints(match, "kills") == [0, 0])
    }

    @Test func dart_knockOutGivesAKillAndOnlyTheLastOneEndsTheGame() throws {
        var match = try registry.match(.fight, ["lives": 1], players: 4, seed: 1)
        let outcomes = match.play("S20, T17, D3")
        #expect(outcomes[0].events == [.dartRegistered(player: 0, hit: .single(20)), .damaged(player: 1, by: 0, amount: 1, livesLeft: 0),
                                       .playerEliminated(player: 1, by: 0)])
        #expect(outcomes[1].events == [.dartRegistered(player: 0, hit: .treble(17)), .damaged(player: 2, by: 0, amount: 1, livesLeft: 0),
                                       .playerEliminated(player: 2, by: 0)])
        #expect(outcomes[2].events == [.dartRegistered(player: 0, hit: .double(3)), .damaged(player: 3, by: 0, amount: 1, livesLeft: 0),
                                       .playerEliminated(player: 3, by: 0), .gameFinished(reason: .lastPlayerStanding)])
        #expect(ints(match, "kills") == [3, 0, 0, 0] && eliminated(match) == [false, true, true, true])
        // Eliminated players come after the survivor, the last one out first (GAMES.md §11.6).
        #expect(match.snapshot.ranks == [1, 4, 3, 2] && match.snapshot.winners == [0])
        #expect(match.snapshot.players.map(\.isEliminated) == [false, true, true, true])
    }

    @Test func dart_gameWonOnTheFirstDartKeepsItsVolley() throws {
        var match = try registry.match(.fight, ["lives": 1], players: 2, seed: 1)
        match.play("S5")
        #expect(match.phase == .finished && match.turnNotation == ["S5"])
        #expect(match.throwDart(DartRecord(hit: .single(5))) == .rejected(.gameFinished))
        #expect(match.endTurn() == .rejected(.gameFinished))
    }

    // MARK: §11.5 Turn

    @Test func turn_eliminatedPlayersAreSkippedAcrossTheEndOfARound() throws {
        var match = try registry.match(.fight, ["lives": 1], players: 4, seed: 1)
        // J1 knocks J2 out; J3 knocks J1 out; J4 passes: the next player is J3 again, in round 2.
        match.play("S20 |")
        #expect(match.snapshot.currentPlayer == 2 && match.snapshot.round == 1)
        match.play("S15 |")
        #expect(match.snapshot.currentPlayer == 3 && match.snapshot.round == 1 && eliminated(match) == [true, true, false, false])
        #expect(match.endTurn().events == [.turnCompleted(player: 3), .roundStarted(round: 2), .turnStarted(player: 2, round: 2)])
        #expect(match.snapshot.currentPlayer == 2 && match.snapshot.round == 2)
        match.play("MISS |")
        #expect(match.snapshot.currentPlayer == 3 && match.snapshot.round == 2)
        // The numbers of the two eliminated players are inert, their heal numbers too.
        #expect(match.play("T15, T20, T2").allSatisfy { $0.events.contains(.noEffect(player: 3)) })
        // J3 and J4 have one life each; J3 has a kill. J1 went out after J2.
        #expect(ints(match, "kills") == [1, 0, 1, 0] && match.snapshot.ranks == [3, 4, 1, 2])
    }

    @Test func turn_noBustAndThreeDartsPerTurn() throws {
        var match = try registry.match(.fight, players: 2, seed: 1)
        let outcomes = match.play("S9, S6, S13")
        #expect(outcomes.map(\.events.count) == [2, 2, 3] && match.phase == .turnComplete)
        #expect(match.throwDart(DartRecord(hit: .single(20))) == .rejected(.turnComplete))
        #expect(ints(match, "lives") == [9, 9])
        #expect(match.endTurn().events == [.turnStarted(player: 1, round: 1)])
        #expect(match.endTurn().events == [.turnCompleted(player: 1), .roundStarted(round: 2), .turnStarted(player: 0, round: 2)])
    }

    // MARK: §11.6 Ranking

    @Test func ranking_livesThenKillsThenTie() throws {
        var match = try registry.match(.fight, ["lives": 2, "maxRounds": 1], players: 4, seed: 1)
        match.play("D3 |")                               // J1 knocks J4 out: one kill, still two lives
        #expect(ints(match, "lives") == [2, 2, 2, 0] && ints(match, "kills") == [1, 0, 0, 0])
        #expect(match.snapshot.ranks == [1, 2, 2, 4])
        match.play("S15 |")                              // J2 hurts J1: lives come before kills
        #expect(ints(match, "lives") == [1, 2, 2, 0] && match.snapshot.ranks == [3, 1, 1, 4])
        match.play("|")
        #expect(match.phase == .finished && match.snapshot.finishReason == .roundLimit)
        #expect(match.snapshot.ranks == [3, 1, 1, 4] && match.snapshot.winners == [1, 2])
    }

    @Test func ranking_roundLimitIsReachedWhenTheLastSurvivorOfTheListConfirms() throws {
        var match = try registry.match(.fight, ["lives": 1, "maxRounds": 1], players: 3, seed: 1)
        match.play("S17 |")                              // J1 knocks J3 out
        #expect(match.snapshot.currentPlayer == 1)
        // J2 is now the last player of the round.
        #expect(match.endTurn().events == [.turnCompleted(player: 1), .gameFinished(reason: .roundLimit)])
        #expect(match.snapshot.ranks == [1, 2, 3])
    }

    // MARK: §11.7 Scoreboard and highlights

    @Test func highlights_healNumberAndWeakSpotsOfLivingOpponents() throws {
        var match = try registry.match(.fight, players: 3, seed: 1)
        // J1 at the maximum: his heal number is his own, without use right now.
        #expect(Set(match.snapshot.highlights) == [
            BoardHighlight(zone: .sector(2), role: .own, owner: 0, marker: .heal),
            BoardHighlight(zone: .sector(20), role: .target, owner: 1), BoardHighlight(zone: .sector(5), role: .target, owner: 1),
            BoardHighlight(zone: .sector(17), role: .target, owner: 2), BoardHighlight(zone: .sector(16), role: .target, owner: 2),
        ])
        #expect(match.snapshot.highlights.count == 5)
        // J2, hurt: his heal number becomes useful. His own weak spots are not highlighted.
        match.play("S20 |")
        #expect(Set(match.snapshot.highlights) == [
            BoardHighlight(zone: .sector(4), role: .secondary, owner: 1, marker: .heal),
            BoardHighlight(zone: .sector(15), role: .target, owner: 0), BoardHighlight(zone: .sector(11), role: .target, owner: 0),
            BoardHighlight(zone: .sector(17), role: .target, owner: 2), BoardHighlight(zone: .sector(16), role: .target, owner: 2),
        ])
        // Healed back to the maximum during the turn: `own` again, also once the turn is complete.
        match.play("S4, MISS, MISS")
        #expect(match.phase == .turnComplete)
        #expect(match.snapshot.highlights.contains(BoardHighlight(zone: .sector(4), role: .own, owner: 1, marker: .heal)))
        // J3 knocks J1 out: the weak spots of an eliminated player are not targets any more.
        match.play("| T15, T15, T15 | ")
        #expect(match.snapshot.currentPlayer == 1 && eliminated(match) == [true, false, false])
        #expect(Set(match.snapshot.highlights) == [
            BoardHighlight(zone: .sector(4), role: .own, owner: 1, marker: .heal),
            BoardHighlight(zone: .sector(17), role: .target, owner: 2), BoardHighlight(zone: .sector(16), role: .target, owner: 2),
        ])
        match.play("T17, T17, T17")
        #expect(match.phase == .finished && match.snapshot.highlights.isEmpty)
    }

    @Test func highlights_everyTargetHurtsItsOwnerAndNothingElseDoes() throws {
        var match = try registry.match(.fight, players: 5, seed: 9)
        match.play("MISS | MISS | MISS |")
        let targets = match.snapshot.highlights.filter { $0.role == .target }
        for number in 1...20 {
            var copy = match
            let events = copy.throwDart(DartRecord(hit: .single(number))).events
            let highlight = targets.first { $0.zone == .sector(number) }
            let victim: Int? = events.compactMap { event -> Int? in
                if case .damaged(let player, _, _, _) = event { return player }
                return nil
            }.first
            #expect(highlight?.owner == victim, "\(number)")
        }
        #expect(targets.count == 8 && targets.allSatisfy { $0.owner != 3 && $0.marker == nil })
    }

    @Test func presentation_rowsBadgesAndCaptions() throws {
        var match = try registry.match(.fight, players: 3, seed: 1)
        #expect(match.snapshot.title == LocalizedText(fr: "Combat", en: "Fight") && match.snapshot.gameID == .fight)
        #expect(match.snapshot.winnerTitle == nil && match.snapshot.objective == nil)
        let first = match.snapshot.players[0]
        #expect(first.primary == ScoreValue(9, unit: LocalizedText(fr: "vies", en: "lives")))
        #expect(first.detail == LocalizedText(fr: "Soin 2 · Faibles 15, 11", en: "Heal 2 · Weak 15, 11"))
        #expect(first.meter == Meter(value: 9, maximum: 9, style: .bar) && first.badges.isEmpty && !first.isEliminated)

        match.play("T20, T5, S2")
        #expect(match.snapshot.turn.darts.map(\.caption) == [
            DartCaption(LocalizedText(fr: "J2 −3 vies", en: "J2 −3 lives"), tone: .negative),
            DartCaption(LocalizedText(fr: "J2 −3 vies", en: "J2 −3 lives"), tone: .negative),
            DartCaption(LocalizedText(fr: "Soin inutile", en: "Heal wasted")),
        ])
        match.play("| T15, S4, S9")
        #expect(match.snapshot.turn.darts.map(\.caption) == [
            DartCaption(LocalizedText(fr: "J1 −3 vies", en: "J1 −3 lives"), tone: .negative),
            DartCaption(LocalizedText(fr: "+1 vie", en: "+1 life"), tone: .positive),
            DartCaption(LocalizedText(fr: "Sans effet", en: "No effect")),
        ])
        match.play("| T20, S20, MISS")
        #expect(match.snapshot.turn.darts.map(\.caption) == [
            DartCaption(LocalizedText(fr: "J2 −3 vies", en: "J2 −3 lives"), tone: .negative),
            DartCaption(LocalizedText(fr: "J2 K.-O.", en: "J2 K.O."), tone: .negative),
            DartCaption(LocalizedText(fr: "Sans effet", en: "No effect")),
        ])
        let out = match.snapshot.players[1]
        #expect(out.isEliminated && out.badges == [Badge(LocalizedText(fr: "K.-O.", en: "K.O."), tone: .negative)])
        #expect(out.primary == ScoreValue(0, unit: LocalizedText(fr: "vie", en: "lives")))
        #expect(out.meter == Meter(value: 0, maximum: 9, style: .bar))
        #expect(match.snapshot.players[0].primary == ScoreValue(6, unit: LocalizedText(fr: "vies", en: "lives")))
        #expect(match.snapshot.players[0].badges.isEmpty)
    }

    @Test func presentation_resultsOfBothEndings() throws {
        var duel = try registry.match(.fight, ["lives": 3], players: 3, seed: 1)
        duel.play("T20, T17")
        #expect(duel.phase == .finished && duel.snapshot.finishReason == .lastPlayerStanding)
        #expect(duel.snapshot.outcome == LocalizedText(fr: "Dernier debout, avec 3 vies restantes.",
                                                       en: "Last one standing, with 3 lives left."))
        #expect(duel.snapshot.players[0].resultLines == [LocalizedText(fr: "2 K.-O.", en: "2 knockouts")])
        #expect(duel.snapshot.players[1].resultLines == [LocalizedText(fr: "K.-O. manche 1", en: "Knocked out in round 1")])
        #expect(duel.snapshot.winnerTitle == nil)

        var limit = try registry.match(.fight, ["maxRounds": 1], players: 2, seed: 1)
        limit.play("S20 | MISS |")
        #expect(limit.phase == .finished && limit.snapshot.ranks == [1, 2])
        #expect(limit.snapshot.outcome == LocalizedText(fr: "En tête à la limite de manches, avec 9 vies.",
                                                        en: "Ahead at the round limit, with 9 lives."))
        // The volley is empty after a finish at the round limit, whatever the rule remembers of the last turn.
        #expect(limit.snapshot.turn.darts.isEmpty && limit.snapshot.players[0].resultLines.isEmpty)

        var tie = try registry.match(.fight, ["maxRounds": 1], players: 2, seed: 1)
        tie.play("| |")
        #expect(tie.snapshot.ranks == [1, 1])
        #expect(tie.snapshot.outcome == LocalizedText(fr: "Égalité à la limite de manches, avec 9 vies.",
                                                      en: "Tied at the round limit, with 9 lives."))
    }

    // MARK: Undo, corrections, replay (GAMES.md §2.5): the draw is rebuilt from the seed every time

    @Test func correction_undoingAKnockOutBringsThePlayerBack() throws {
        var match = try registry.match(.fight, players: 3, seed: 1)
        match.play("T20, T5, T20 | S20")
        #expect(eliminated(match) == [false, true, false] && match.snapshot.currentPlayer == 2)
        match.undo()
        match.undo()
        #expect(match.phase == .turnComplete && match.snapshot.currentPlayer == 0 && eliminated(match) == [false, true, false])
        match.undo()
        #expect(match.phase == .throwing && ints(match, "lives") == [9, 3, 9] && eliminated(match) == [false, false, false])
        #expect(ints(match, "kills") == [0, 0, 0] && match.snapshot.ranks == [1, 3, 1])
        // The numbers have not moved: same seed, same draw.
        #expect(match.fact(1, "healNumber") == 4 && match.fact(1, "weakNumbers") == [20, 5])
        match.play("MISS |")
        #expect(match.snapshot.currentPlayer == 1)
    }

    @Test func correction_replacingTheWinningDartReopensTheGame() throws {
        var match = try registry.match(.fight, players: 2, seed: 1)
        match.play("T20, T20, T5")
        #expect(match.phase == .finished)
        let edit = match.replaceDart(at: 2, with: .double(5))
        #expect(edit.applied && edit.dropped.isEmpty)
        #expect(match.phase == .turnComplete && ints(match, "lives") == [9, 1] && match.snapshot.finishReason == nil)
        #expect(ints(match, "kills") == [0, 0] && match.snapshot.ranks == [1, 2])
        // The other way round: the first dart becomes the knock-out, the darts after it disappear.
        var short = try registry.match(.fight, ["lives": 3], players: 2, seed: 1)
        short.play("S20, S9, S5")
        #expect(short.phase == .turnComplete && ints(short, "lives") == [3, 1])
        let win = short.replaceDart(at: 0, with: .treble(20))
        #expect(win.applied && win.dropped.map(\.hit) == [.single(9), .single(5)])
        #expect(short.phase == .finished && short.turnNotation == ["T20"] && ints(short, "lives") == [3, 0])
        short.removeDart(at: 0)
        #expect(short.phase == .throwing && short.turnNotation.isEmpty && ints(short, "lives") == [3, 3])
    }

    @Test func effectKey_groupsTheDartsOfEqualEffect() throws {
        var match = try registry.match(.fight, players: 3, seed: 1)
        // Nobody's number, the bulls and a miss: nothing happens, whatever the bed.
        #expect(match.effectKey(for: .single(9)) == match.effectKey(for: .treble(6)))
        #expect(match.effectKey(for: .single(9)) == match.effectKey(for: .innerBull))
        #expect(match.effectKey(for: .single(9)) == match.effectKey(for: .miss))
        // A wasted heal is not "nothing" for the sound, and a multiplier changes a real hit.
        #expect(match.effectKey(for: .single(2)) != match.effectKey(for: .single(9)))
        #expect(match.effectKey(for: .single(2)) == match.effectKey(for: .treble(2)))
        #expect(match.effectKey(for: .single(20)) != match.effectKey(for: .double(20)))
        // Both weak spots of a player do the same thing to him.
        #expect(match.effectKey(for: .double(20)) == match.effectKey(for: .double(5)))
        #expect(match.effectKey(for: .double(20)) != match.effectKey(for: .double(17)))
        // One life left: every bed of a weak spot is the same knock-out.
        match.play("T20, T20, D5 |")
        #expect(ints(match, "lives") == [9, 1, 9])
        match.play("| ")
        #expect(match.snapshot.currentPlayer == 2)
        #expect(match.effectKey(for: .single(20)) == match.effectKey(for: .treble(5)))
        #expect(match.effectKey(for: .single(20)) != match.effectKey(for: .single(15)))
    }

    @Test func position_aRecordedPositionChangesNothing() throws {
        var plain = try registry.match(.fight, players: 2, seed: 1)
        var placed = plain
        for (index, hit) in [Hit.treble(20), .single(2), .miss, .single(15), .double(4), .innerBull].enumerated() {
            #expect(plain.throwDart(DartRecord(hit: hit))
                    == placed.throwDart(DartRecord(hit: hit, position: BoardPoint(x: 40 - Double(index) * 25, y: -7))))
            if plain.phase == .turnComplete { #expect(plain.endTurn() == placed.endTurn()) }
        }
        #expect(plain.snapshot == placed.snapshot)
    }

    @Test func replay_aSavedGameDrawsTheSameNumbersAgain() throws {
        // The numbers are not saved: they come back from the seed, here the largest one.
        var match = try registry.match(.fight, ["lives": 4], players: 5, seed: .max)
        let numbers = match.snapshot.players.map { [$0.facts["healNumber"], $0.facts["weakNumbers"]] }
        for _ in 0..<4 {
            for number in [20, 5, 17, 3, 12] where match.phase == .throwing { match.throwDart(DartRecord(hit: .double(number))) }
            match.endTurn()
        }
        let saved = try MoonLandingReplayChecks.restoredFromJSON(match)
        #expect(saved.snapshot == match.snapshot && saved.entries == match.entries)
        #expect(saved.snapshot.players.map { [$0.facts["healNumber"], $0.facts["weakNumbers"]] } == numbers)
        #expect(try MoonLandingReplayChecks.replay(match.record).events == MoonLandingReplayChecks.replay(saved.record).events)
        // Another seed is another game.
        #expect(try registry.match(.fight, ["lives": 4], players: 5, seed: .max - 1).snapshot != registry.match(.fight, ["lives": 4], players: 5, seed: .max).snapshot)
    }

    @Test func effectKey_equalKeysLeaveEqualFutures() throws {
        var pairs = 0
        for seed in UInt64(1)...3 {
            pairs += try MoonLandingReplayChecks.equalKeysHaveEqualFutures(
                .fight, ["lives": 3, "maxRounds": 6], players: Int(seed) + 2, seed: seed, fuzzSeed: seed &+ 50, states: 40,
                hits: Hit.all.filter { $0.number != nil } + [.miss])
        }
        #expect(pairs > 100)
    }

    @Test func replay_theJournalAloneRebuildsTheGame() throws {
        // Numbered beds only (plus one miss and one bull): with three numbers per player most darts do something.
        let hits = Hit.all.filter { $0.number != nil } + [.miss, .innerBull]
        var knockOuts = 0, finished = 0
        for seed in UInt64(1)...4 {
            for (players, lives) in [(2, 2), (3, 4), (6, 3), (4, 9)] {
                try MoonLandingReplayChecks.fuzz(
                    .fight, ["lives": .int(lives), "maxRounds": 5], players: players, seed: seed,
                    fuzzSeed: seed &* 131 &+ UInt64(players), steps: 140, hits: hits
                ) { snapshot in
                    knockOuts += snapshot.players.filter(\.isEliminated).count
                    finished += snapshot.phase == .finished ? 1 : 0
                    var alive = 0, kills = 0, out = 0
                    for row in snapshot.players {
                        guard case .int(let left)? = row.facts["lives"], case .int(let killed)? = row.facts["kills"],
                              case .bool(let eliminated)? = row.facts["eliminated"] else {
                            Issue.record("missing fact")
                            return
                        }
                        #expect((0...lives).contains(left) && eliminated == (left == 0) && row.isEliminated == eliminated)
                        #expect(row.meter == Meter(value: left, maximum: lives, style: .bar))
                        alive += eliminated ? 0 : 1
                        out += eliminated ? 1 : 0
                        kills += killed
                    }
                    #expect(kills == out && alive >= 1)
                    #expect((alive == 1) == (snapshot.finishReason == .lastPlayerStanding))
                    if snapshot.phase != .finished {
                        #expect(snapshot.players[snapshot.currentPlayer].isEliminated == false)
                    }
                    // Eliminated players are ranked after every survivor.
                    let worstAlive = snapshot.players.filter { !$0.isEliminated }.map(\.rank).max() ?? 0
                    #expect(snapshot.players.filter(\.isEliminated).allSatisfy { $0.rank > worstAlive })
                }
            }
        }
        // The walk is not a quiet one: players go out and games end along the way.
        #expect(knockOuts > 50 && finished > 50)
    }
}
