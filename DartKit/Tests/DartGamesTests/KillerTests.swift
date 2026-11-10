import Testing
import DartCore
import DartGames
import DartTestSupport

/// GAMES.md §5.9: the seven Killer vectors, one method per vector (several for the vectors made of independent games).
@Suite struct KillerTests {
    private let registry = GameRegistry.standard

    // MARK: Helpers

    private func zones(_ match: GameMatch) -> [[Int]] {
        match.snapshot.players.map { row in
            if case .ints(let zone)? = row.facts["zone"] { return zone }
            return []
        }
    }

    private func ints(_ match: GameMatch, _ name: String) -> [Int] {
        match.snapshot.players.map { row in
            if case .int(let value)? = row.facts[name] { return value }
            return Int.min
        }
    }

    private func bools(_ match: GameMatch, _ name: String) -> [Bool?] {
        match.snapshot.players.map { row in
            if case .bool(let value)? = row.facts[name] { return value }
            return nil
        }
    }

    // MARK: KIL-1

    @Test func kil1_hardDuel_armThenKillTheLastOpponent() throws {
        var match = try registry.match(.killer, ["level": "hard"], players: 2, seed: 1)
        #expect(zones(match) == [[11], [6]])
        #expect(match.fact(0, "zone") == [11] && match.fact(1, "zone") == [6])
        #expect(ints(match, "lives") == [3, 3])

        var outcomes = match.play("S11, D11, T11")
        #expect(match.fact(0, "armingProgress") == 3)
        // A double and a treble are one hit each.
        #expect(match.fact(0, "isKiller") == true && match.fact(1, "isKiller") == false)
        #expect(match.phase == .turnComplete)
        #expect(outcomes[0].events == [.dartRegistered(player: 0, hit: .single(11)), .armingHit(player: 0, progress: 1)])
        #expect(outcomes[1].events == [.dartRegistered(player: 0, hit: .double(11)), .armingHit(player: 0, progress: 2)])
        #expect(outcomes[2].events == [.dartRegistered(player: 0, hit: .treble(11)), .armingHit(player: 0, progress: 3),
                                       .becameKiller(player: 0), .turnCompleted(player: 0)])

        match.play("| MISS ×3 | S6, T6")
        #expect(match.fact(1, "lives") == 1)
        #expect(match.phase == .throwing)

        outcomes = match.play("D6")
        #expect(match.fact(1, "lives") == 0)
        #expect(match.fact(1, "eliminated") == true && match.snapshot.players[1].isEliminated)
        #expect(match.fact(0, "kills") == 1)
        #expect(match.phase == .finished && match.snapshot.finishReason == .lastPlayerStanding)
        #expect(match.snapshot.ranks == [1, 2])
        #expect(outcomes[0].events == [.dartRegistered(player: 0, hit: .double(6)),
                                       .lifeLost(player: 1, by: 0, livesLeft: 0),
                                       .playerEliminated(player: 1, by: 0),
                                       .gameFinished(reason: .lastPlayerStanding)])
    }

    // MARK: KIL-2

    @Test func kil2_easyThreePlayers_armingMidTurnAndZoneOfAnEliminatedPlayer() throws {
        var match = try registry.match(.killer, ["level": "easy"], players: 3, seed: 1)
        #expect(zones(match) == [[8, 11, 14], [6, 10, 15], [20, 1, 18]])

        var outcomes = match.play("S8, T14, S6")
        #expect(match.fact(0, "armingProgress") == 2)
        // S6 has no effect: J1 is not a Killer yet.
        #expect(outcomes[2].events == [.dartRegistered(player: 0, hit: .single(6)), .noEffect(player: 0), .turnCompleted(player: 0)])
        #expect(ints(match, "lives") == [3, 3, 3])

        let before = match.snapshot.players.map(\.facts)
        outcomes = match.play("| S11, DB, S20")
        // No change: J2 is not a Killer, and the bull plays no part.
        #expect(match.snapshot.players.map(\.facts) == before)
        #expect(outcomes[1].events == [.dartRegistered(player: 1, hit: .single(11)), .noEffect(player: 1)])
        #expect(outcomes[2].events == [.dartRegistered(player: 1, hit: .innerBull), .noEffect(player: 1)])
        #expect(outcomes[3].events == [.dartRegistered(player: 1, hit: .single(20)), .noEffect(player: 1), .turnCompleted(player: 1)])

        outcomes = match.play("| S19, MISS, S20")
        // S19 is a free number.
        #expect(outcomes[1].events == [.dartRegistered(player: 2, hit: .single(19)), .noEffect(player: 2)])
        #expect(ints(match, "armingProgress") == [2, 0, 1])

        outcomes = match.play("| D11, S10, S15")
        // J1 becomes a Killer on D11, then hits J2 twice in the same turn.
        #expect(outcomes[1].events == [.dartRegistered(player: 0, hit: .double(11)), .armingHit(player: 0, progress: 3),
                                       .becameKiller(player: 0)])
        #expect(outcomes[2].events == [.dartRegistered(player: 0, hit: .single(10)), .lifeLost(player: 1, by: 0, livesLeft: 2)])
        #expect(ints(match, "lives") == [3, 1, 3])

        outcomes = match.play("| S6, S6, S6 | MISS ×3 | S6, S14, S1")
        #expect(match.fact(1, "armingProgress") == 3)
        // J2 is eliminated by S6 (outcome index 9: 1 endTurn, 3 darts, 1 endTurn, 3 darts, 1 endTurn, then S6).
        #expect(outcomes[9].events == [.dartRegistered(player: 0, hit: .single(6)), .lifeLost(player: 1, by: 0, livesLeft: 0),
                                       .playerEliminated(player: 1, by: 0)])
        // S14 is J1's own zone, without penalty: no effect.
        #expect(outcomes[10].events == [.dartRegistered(player: 0, hit: .single(14)), .noEffect(player: 0)])
        #expect(ints(match, "lives") == [3, 0, 2])
        #expect(match.fact(0, "kills") == 1)
        #expect(match.phase == .turnComplete)

        outcomes = match.play("| S10, S18, S18")
        // J2 is skipped.
        #expect(outcomes[0].events == [.turnStarted(player: 2, round: 3)])
        #expect(match.snapshot.currentPlayer == 2)
        // S10 is in the zone of an eliminated player: no effect.
        #expect(outcomes[1].events == [.dartRegistered(player: 2, hit: .single(10)), .noEffect(player: 2)])
        #expect(match.fact(2, "armingProgress") == 3)

        outcomes = match.play("| T20, S1")
        #expect(ints(match, "lives") == [3, 0, 0])
        #expect(match.phase == .finished && match.snapshot.finishReason == .lastPlayerStanding)
        #expect(match.snapshot.round == 4)
        #expect(match.fact(0, "kills") == 2)
        #expect(match.snapshot.ranks == [1, 3, 2])
        // dart(S1) is then refused, and so is the confirmation.
        #expect(match.throwDart(DartRecord(hit: .single(1))) == .rejected(.gameFinished))
        #expect(match.endTurn() == .rejected(.gameFinished))
        #expect(match.entries.count == 34)
    }

    /// KIL-2, last line again: a Killer who hits the zone of an eliminated player gets nothing either.
    @Test func kil2_zoneOfAnEliminatedPlayerIsInertForAKiller() throws {
        var match = try registry.match(.killer, ["level": "easy"], players: 3, seed: 1)
        match.play("S8, T14, S6 | S11, DB, S20 | S19, MISS, S20 | D11, S10, S15 | S6, S6, S6 | MISS ×3 | S6, S14, S1 |")
        match.play("S10, S18, S18 |")
        let before = match.snapshot.players.map(\.facts)
        let outcomes = match.play("S10, D15")
        #expect(outcomes[0].events == [.dartRegistered(player: 0, hit: .single(10)), .noEffect(player: 0)])
        #expect(outcomes[1].events == [.dartRegistered(player: 0, hit: .double(15)), .noEffect(player: 0)])
        #expect(match.snapshot.players.map(\.facts) == before)
        // The zone of the eliminated player is not redistributed.
        #expect(zones(match) == [[8, 11, 14], [6, 10, 15], [20, 1, 18]])
    }

    // MARK: KIL-3

    /// The draws of KIL-3, straight from the generator: 20 initial draws, then one draw per redraw.
    @Test func kil3_drawSequenceOfTheDocument() {
        var random = SeededRandom(seed: 7)
        #expect(ringLayout(playerCount: 3, width: 1, rng: &random) == [[14], [15], [4]])
        var afterLayout = SeededRandom(seed: 7)
        for _ in 0..<20 { _ = afterLayout.next() }
        #expect(afterLayout == random)
        // 17, 17, 17, 17, 18 and 18 candidates give the indices 12, 9, 7, 10, 14 and 3: 26 draws in all.
        #expect([17, 17, 17, 17, 18, 18].map { random.nextInt(below: $0) } == [12, 9, 7, 10, 14, 3])
        var afterGame = SeededRandom(seed: 7)
        for _ in 0..<26 { _ = afterGame.next() }
        #expect(afterGame == random)
    }

    @Test func kil3_expert_redrawAtEveryTurn_deterministic() throws {
        var match = try registry.match(.killer, ["level": "expert"], players: 3, seed: 7)
        #expect(zones(match) == [[14], [15], [4]])
        var steps: [GameSnapshot] = [match.snapshot]
        func play(_ script: String) -> [InputOutcome] {
            var outcomes: [InputOutcome] = []
            // One input at a time, so that every intermediate snapshot is recorded.
            var token = ""
            for character in script + "," {
                if character == "," || character == "|" {
                    if !token.trimmingCharacters(in: .whitespaces).isEmpty {
                        for outcome in match.play(token) {
                            outcomes.append(outcome)
                        }
                        steps.append(match.snapshot)
                    }
                    token = ""
                    if character == "|" {
                        outcomes.append(match.endTurn())
                        steps.append(match.snapshot)
                    }
                } else {
                    token.append(character)
                }
            }
            return outcomes
        }

        var outcomes = play("S14, MISS, MISS | MISS, MISS, MISS | MISS, MISS, MISS |")
        #expect(match.fact(0, "armingProgress") == 1)
        // No redraw at the first turn of J2 nor of J3.
        #expect(outcomes[3].events == [.turnStarted(player: 1, round: 1)])
        #expect(outcomes[7].events == [.turnStarted(player: 2, round: 1)])
        // Start of J1's second turn: 15 and 4 (the others) and 14 (the old one) are excluded; index 12 of 17 is 16.
        #expect(zones(match) == [[16], [15], [4]])
        #expect(outcomes[11].events == [.roundStarted(round: 2), .zoneChanged(player: 0, zone: [16]), .turnStarted(player: 0, round: 2)])

        outcomes = play("S14, S16, T16 |")
        // S14 has no effect: 14 belongs to nobody any more.
        #expect(outcomes[0].events == [.dartRegistered(player: 0, hit: .single(14)), .noEffect(player: 0)])
        #expect(match.fact(0, "armingProgress") == 3 && match.fact(0, "isKiller") == true)
        // Redraw of J2: 16, 4 and 15 excluded; index 9 of 17 is 11.
        #expect(zones(match) == [[16], [11], [4]])
        #expect(outcomes[3].events == [.zoneChanged(player: 1, zone: [11]), .turnStarted(player: 1, round: 2)])

        outcomes = play("MISS, MISS, MISS |")
        // Redraw of J3: 16, 11 and 4 excluded; index 7 of 17 is 9.
        #expect(zones(match) == [[16], [11], [9]])
        #expect(outcomes[3].events == [.zoneChanged(player: 2, zone: [9]), .turnStarted(player: 2, round: 2)])

        outcomes = play("MISS, MISS, MISS |")
        // Redraw of J1: 11, 9 and 16 excluded; index 10 of 17 is 13.
        #expect(zones(match) == [[13], [11], [9]])
        #expect(match.snapshot.round == 3)
        #expect(outcomes[3].events == [.roundStarted(round: 3), .zoneChanged(player: 0, zone: [13]), .turnStarted(player: 0, round: 3)])

        outcomes = play("S11, S11, S11")
        #expect(match.fact(1, "lives") == 0 && match.fact(1, "eliminated") == true)
        #expect(match.fact(0, "kills") == 1)
        #expect(match.phase == .turnComplete)

        outcomes = play("|")
        // J2 is skipped, without a draw. Redraw of J3: 13 and 9 excluded; index 14 of 18 is 17.
        #expect(outcomes[0].events == [.zoneChanged(player: 2, zone: [17]), .turnStarted(player: 2, round: 3)])
        #expect(match.snapshot.currentPlayer == 2)
        #expect(match.fact(0, "zone") == [13] && match.fact(2, "zone") == [17])

        outcomes = play("MISS, MISS, MISS |")
        // Redraw of J1: 17 and 13 excluded; index 3 of 18 is 4 (4 and 11 can be drawn again).
        #expect(outcomes[3].events == [.roundStarted(round: 4), .zoneChanged(player: 0, zone: [4]), .turnStarted(player: 0, round: 4)])
        #expect(match.fact(0, "zone") == [4] && match.fact(2, "zone") == [17])
        #expect(ints(match, "lives") == [3, 0, 3])
        #expect(match.snapshot.round == 4 && match.snapshot.currentPlayer == 0)

        // Undo then endTurn: the same state (J1 on the 4).
        let final = match.snapshot
        #expect(match.undo().applied)
        #expect(match.phase == .turnComplete && match.snapshot.currentPlayer == 2 && match.fact(0, "zone") == [13])
        #expect(match.endTurn().events == [.roundStarted(round: 4), .zoneChanged(player: 0, zone: [4]), .turnStarted(player: 0, round: 4)])
        #expect(match.snapshot == final)

        // Replaying the whole journal gives the same zones (the same snapshot) at every step.
        #expect(steps.count == match.entries.count + 1)
        var replayed = try registry.match(.killer, ["level": "expert"], players: 3, seed: 7)
        #expect(replayed.snapshot == steps[0])
        for (index, entry) in match.entries.enumerated() {
            switch entry {
            case .dart(let record): replayed.throwDart(record)
            case .endTurn: replayed.endTurn()
            }
            #expect(replayed.snapshot == steps[index + 1], "step \(index + 1)")
        }
        #expect(try registry.restoreMatch(match.record).snapshot == final)
    }

    // MARK: KIL-4

    @Test func kil4_selfHitPenalty_duel_theKillerEliminatesHimself() throws {
        var match = try registry.match(.killer, ["level": "hard", "lives": 1, "armingHits": 1, "selfHitPenalty": true],
                                       players: 2, seed: 2)
        #expect(zones(match) == [[3], [5]])
        let outcomes = match.play("S3, S3")
        #expect(outcomes[0].events == [.dartRegistered(player: 0, hit: .single(3)), .armingHit(player: 0, progress: 1),
                                       .becameKiller(player: 0)])
        #expect(outcomes[1].events == [.dartRegistered(player: 0, hit: .single(3)),
                                       .lifeLost(player: 0, by: 0, livesLeft: 0),
                                       .playerEliminated(player: 0, by: 0),
                                       .gameFinished(reason: .lastPlayerStanding)])
        #expect(match.phase == .finished && match.snapshot.finishReason == .lastPlayerStanding)
        #expect(match.snapshot.ranks == [2, 1])
        // No kill is counted for a self-elimination.
        #expect(ints(match, "kills") == [0, 0])
    }

    @Test func kil4_selfHitPenalty_threePlayers_theTurnIsClosedAfterTwoDarts() throws {
        var match = try registry.match(.killer, ["level": "hard", "lives": 1, "armingHits": 1, "selfHitPenalty": true],
                                       players: 3, seed: 2)
        #expect(zones(match) == [[3], [12], [18]])
        let outcomes = match.play("S3, S3")
        #expect(match.fact(0, "eliminated") == true)
        #expect(match.phase == .turnComplete)
        #expect(match.turnNotation == ["S3", "S3"])
        #expect(outcomes[1].events == [.dartRegistered(player: 0, hit: .single(3)),
                                       .lifeLost(player: 0, by: 0, livesLeft: 0),
                                       .playerEliminated(player: 0, by: 0),
                                       .turnCompleted(player: 0)])
        #expect(match.throwDart(DartRecord(hit: .single(12))) == .rejected(.turnComplete))
        #expect(match.entries.count == 2)

        #expect(match.endTurn().events == [.turnStarted(player: 1, round: 1)])
        #expect(match.snapshot.currentPlayer == 1 && match.snapshot.round == 1)
    }

    @Test func kil4_selfHitPenalty_costsOneLifePerHitOnceKiller() throws {
        var match = try registry.match(.killer, ["level": "hard", "selfHitPenalty": true], players: 2, seed: 2)
        #expect(zones(match) == [[3], [5]])
        let outcomes = match.play("S3, S3, S3 | MISS ×3 | S3, S5, MISS")
        #expect(ints(match, "lives") == [2, 2])
        #expect(match.fact(0, "armingProgress") == 3)
        #expect(outcomes[8].events == [.dartRegistered(player: 0, hit: .single(3)), .lifeLost(player: 0, by: 0, livesLeft: 2)])
        #expect(outcomes[9].events == [.dartRegistered(player: 0, hit: .single(5)), .lifeLost(player: 1, by: 0, livesLeft: 2)])
    }

    // MARK: KIL-5

    @Test func kil5_medium_roundLimitAndRanking() throws {
        var match = try registry.match(.killer, ["level": "medium", "maxRounds": 2], players: 4, seed: 42)
        #expect(zones(match) == [[9, 12], [16, 8], [1, 18], [17, 3]])
        match.play("S9, S12, S9 | S16, S16, MISS | MISS ×3 | S17, S3, S17 |")
        match.play("S16, S1, S1 | MISS, S8, S9 | S18, MISS, MISS | S9, S16, S16")
        #expect(match.phase == .turnComplete)
        #expect(ints(match, "armingProgress") == [3, 3, 1, 3])
        #expect(ints(match, "lives") == [1, 0, 1, 3])
        #expect(ints(match, "kills") == [0, 0, 0, 1])
        #expect(bools(match, "eliminated") == [false, true, false, false])

        #expect(match.endTurn().events == [.gameFinished(reason: .roundLimit)])
        #expect(match.phase == .finished && match.snapshot.finishReason == .roundLimit)
        // J4: 3 lives. J1 and J3: 1 life and no kill, split by the arming progress, 3 against 1. J2: eliminated.
        #expect(match.snapshot.ranks == [2, 4, 3, 1])
        #expect(match.snapshot.roundLimit == 2 && match.snapshot.round == 2)
        #expect(match.snapshot.turn.darts.isEmpty)
    }

    // MARK: KIL-6

    @Test func kil6_mediumDuel() throws {
        var match = try registry.match(.killer, ["level": "medium"], players: 2, seed: 1)
        #expect(zones(match) == [[6, 10], [11, 14]])
        match.play("S6, D10, T6 | S14, S11, MISS | S11, S14, S11")
        #expect(match.phase == .finished && match.snapshot.finishReason == .lastPlayerStanding)
        #expect(ints(match, "lives") == [3, 0])
        #expect(ints(match, "armingProgress") == [3, 2])
        #expect(match.snapshot.ranks == [1, 2])
    }

    // MARK: KIL-7

    @Test(arguments: [7, 8])
    func kil7_easyRefusesMoreThanSixPlayers(players: Int) {
        #expect(throws: GameConfigurationError.choiceUnavailable(
            key: "level", note: LocalizedText(fr: "6 joueurs maximum en Facile", en: "6 players maximum in Easy"))) {
            try registry.match(.killer, ["level": "easy"], players: players, seed: 1)
        }
        // `easy` is the default level.
        #expect(throws: GameConfigurationError.self) {
            try registry.match(.killer, players: players, seed: 1)
        }
    }

    @Test func kil7_easySixPlayers() throws {
        let match = try registry.match(.killer, ["level": "easy"], players: 6, seed: 1)
        #expect(zones(match) == [[14, 9, 12], [5, 20, 1], [6, 10, 15], [16, 8, 11], [17, 3, 19], [18, 4, 13]])
        // 18 distinct numbers; 2 and 7 stay free.
        #expect(Set(zones(match).flatMap { $0 }) == Set(1...20).subtracting([2, 7]))
    }

    @Test func kil7_mediumEightPlayers() throws {
        let match = try registry.match(.killer, ["level": "medium"], players: 8, seed: 1)
        #expect(zones(match) == [[18, 4], [6, 10], [7, 16], [9, 12], [3, 19], [15, 2], [11, 14], [5, 20]])
    }

    @Test(arguments: ["hard", "expert"])
    func kil7_hardAndExpertEightPlayers(level: String) throws {
        let match = try registry.match(.killer, ["level": .string(level)], players: 8, seed: 1)
        #expect(zones(match) == [[11], [16], [4], [5], [17], [14], [6], [7]])
    }

    @Test(arguments: ["easy", "medium", "hard", "expert"])
    func kil7_onePlayerIsRefused(level: String) {
        #expect(throws: GameConfigurationError.playerCountOutOfRange(allowed: 2...8, actual: 1)) {
            try registry.match(.killer, ["level": .string(level)], players: 1, seed: 1)
        }
        #expect(throws: GameConfigurationError.playerCountOutOfRange(allowed: 2...8, actual: 9)) {
            try registry.match(.killer, ["level": .string(level)], players: 9, seed: 1)
        }
    }
}
