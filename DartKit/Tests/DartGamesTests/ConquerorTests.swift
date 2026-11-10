import Testing
import DartCore
import DartGames
import DartTestSupport

/// GAMES.md §12 Conquérant (`conqueror`): the vectors CON-1 to CON-7 of §12.9, then every rule paragraph.
///
/// Ring order, clockwise from the top: 20, 1, 18, 4, 13, 6, 10, 15, 2, 17, 3, 19, 7, 16, 8, 11, 14, 9, 12, 5.
/// With seed 1 and two players the homes are 6 (J1) and 11 (J2): the neighbours of 6 are 13 and 10, those of
/// 11 are 8 and 14. With seed 1 and three players the homes are 6, 16 and 20.
@Suite struct ConquerorTests {
    private let registry = GameRegistry.standard

    /// `J1 = { 6: 3, 10: 1 }` of GAMES.md §12.9: the sectors of a player with their lives.
    private func sectors(_ match: GameMatch, _ player: Int) -> [Int: Int] {
        if case .map(let sectors)? = match.fact(player, "sectors") { return sectors }
        return [-1: -1]
    }

    private func ints(_ match: GameMatch, _ name: String) -> [Int] {
        match.snapshot.players.map { row in
            if case .int(let value)? = row.facts[name] { return value }
            return Int.min
        }
    }

    private func eliminated(_ match: GameMatch) -> [Bool] {
        match.snapshot.players.map { $0.facts["eliminated"] == .bool(true) }
    }

    // MARK: Vectors of GAMES.md §12.9

    @Test func con1_claimStrengthenKingConquerAndReconquer() throws {
        var match = try registry.match(.conqueror, players: 2, seed: 1)
        #expect(ints(match, "homeSector") == [6, 11])
        #expect(sectors(match, 0) == [6: 3] && sectors(match, 1) == [11: 3])
        #expect(match.gameFact("king") == -1)

        let first = match.play("S10, S15, S20")
        #expect(sectors(match, 0) == [6: 3, 10: 1, 15: 1])
        #expect(first[0].events == [.dartRegistered(player: 0, hit: .single(10)), .sectorClaimed(player: 0, sector: 10)])
        // 15 is next to the 10 claimed one dart earlier: adjacency is read at the time of the dart.
        #expect(first[1].events == [.dartRegistered(player: 0, hit: .single(15)), .sectorClaimed(player: 0, sector: 15)])
        #expect(first[2].events == [.dartRegistered(player: 0, hit: .single(20)), .noEffect(player: 0), .turnCompleted(player: 0)])

        let second = match.play("| S8, S8, T14")
        #expect(sectors(match, 1) == [11: 3, 8: 2, 14: 1])
        #expect(second[2].events == [.dartRegistered(player: 1, hit: .single(8)), .sectorStrengthened(player: 1, sector: 8, lives: 2)])
        // Without `multipliersCount` a treble is one hit.
        #expect(second[3].events == [.dartRegistered(player: 1, hit: .treble(14)), .sectorClaimed(player: 1, sector: 14),
                                     .turnCompleted(player: 1)])

        let third = match.play("| SB, S14, S14")
        #expect(match.gameFact("king") == 0)
        #expect(sectors(match, 0) == [6: 3, 10: 1, 15: 1, 14: 2] && sectors(match, 1) == [11: 3, 8: 2])
        #expect(third[1].events == [.dartRegistered(player: 0, hit: .outerBull), .kingOfTheHill(player: 0)])
        #expect(third[2].events == [.dartRegistered(player: 0, hit: .single(14)), .sectorConquered(player: 0, sector: 14, from: 1)])
        #expect(third[3].events == [.dartRegistered(player: 0, hit: .single(14)), .sectorStrengthened(player: 0, sector: 14, lives: 2),
                                    .turnCompleted(player: 0)])

        let fourth = match.play("| S14, S14, DB")
        #expect(fourth[1].events == [.dartRegistered(player: 1, hit: .single(14)), .sectorDamaged(player: 1, sector: 14, livesLeft: 1)])
        #expect(fourth[2].events == [.dartRegistered(player: 1, hit: .single(14)), .sectorConquered(player: 1, sector: 14, from: 0)])
        #expect(fourth[3].events == [.dartRegistered(player: 1, hit: .innerBull), .kingOfTheHill(player: 1), .turnCompleted(player: 1)])
        #expect(match.gameFact("king") == 1)
        #expect(sectors(match, 0) == [6: 3, 10: 1, 15: 1] && sectors(match, 1) == [11: 3, 8: 2, 14: 1])
        #expect(ints(match, "totalLives") == [5, 6] && ints(match, "sectorCount") == [3, 3])
        #expect(match.phase == .turnComplete && match.snapshot.round == 2)
    }

    @Test func con2_multipliersKingAndHomeCapture() throws {
        var match = try registry.match(.conqueror, ["multipliersCount": true], players: 2, seed: 1)
        let first = match.play("T10, D13, T6")
        #expect(sectors(match, 0) == [6: 3, 10: 3, 13: 2])
        // T6 on the home, already at three lives: no effect.
        #expect(first[2].events == [.dartRegistered(player: 0, hit: .treble(6)), .noEffect(player: 0), .turnCompleted(player: 0)])

        let second = match.play("| DB, T6")
        #expect(match.gameFact("king") == 1)
        #expect(eliminated(match) == [true, false])
        #expect(sectors(match, 1) == [11: 3, 6: 1, 10: 3, 13: 2] && sectors(match, 0) == [:])
        #expect(match.phase == .finished && match.snapshot.finishReason == .lastPlayerStanding)
        #expect(match.snapshot.ranks == [2, 1])
        #expect(second[2].events == [.dartRegistered(player: 1, hit: .treble(6)), .sectorConquered(player: 1, sector: 6, from: 0),
                                     .playerEliminated(player: 0, by: 1), .gameFinished(reason: .lastPlayerStanding)])
    }

    @Test func con3_threePlayersInheritanceAndEliminationOrder() throws {
        var match = try registry.match(.conqueror, players: 3, seed: 1)
        #expect(ints(match, "homeSector") == [6, 16, 20])
        let outcomes = match.play("SB, S16, S16 | S8, S7, MISS | MISS ×3 | S16")
        #expect(eliminated(match) == [false, true, false])
        // J1 inherits the 7 and the 8 of J2, with their lives.
        #expect(sectors(match, 0) == [6: 3, 16: 1, 7: 1, 8: 1] && sectors(match, 1) == [:] && sectors(match, 2) == [20: 3])
        #expect(match.gameFact("king") == 0)
        #expect(match.phase == .throwing && match.turnNotation == ["S16"])
        #expect(outcomes.last?.events == [.dartRegistered(player: 0, hit: .single(16)), .sectorConquered(player: 0, sector: 16, from: 1),
                                          .playerEliminated(player: 1, by: 0)])

        var current = [match.snapshot.currentPlayer]
        match.play("S20, S20 |")
        current.append(match.snapshot.currentPlayer)
        match.play("MISS ×3 |")
        current.append(match.snapshot.currentPlayer)
        // J2 is skipped: J1, then J3, then J1 again.
        #expect(current == [0, 2, 0])
        match.play("S20")
        #expect(match.phase == .finished && match.snapshot.finishReason == .lastPlayerStanding)
        #expect(match.snapshot.round == 3 && match.snapshot.ranks == [1, 3, 2])
        #expect(eliminated(match) == [false, true, true])
        #expect(sectors(match, 0) == [6: 3, 16: 1, 7: 1, 8: 1, 20: 1])
    }

    @Test func con4_roundLimitTotalLives() throws {
        var match = try registry.match(.conqueror, ["maxRounds": 1], players: 2, seed: 1)
        let outcomes = match.play("S10, S15, S6 | S8, S8, S14 |")
        #expect(sectors(match, 0) == [6: 3, 10: 1, 15: 1] && sectors(match, 1) == [11: 3, 8: 2, 14: 1])
        #expect(ints(match, "totalLives") == [5, 6])
        #expect(outcomes[2].events == [.dartRegistered(player: 0, hit: .single(6)), .noEffect(player: 0), .turnCompleted(player: 0)])
        #expect(outcomes.last?.events == [.gameFinished(reason: .roundLimit)])
        #expect(match.phase == .finished && match.snapshot.finishReason == .roundLimit && match.snapshot.ranks == [2, 1])
    }

    @Test func con5_theKingAttacksAnywhereButClaimsOnlyByAdjacency() throws {
        var match = try registry.match(.conqueror, players: 2, seed: 1)
        let outcomes = match.play("SB, S9, S13 | MISS ×3 | S11, S12, MISS")
        #expect(match.gameFact("king") == 0)
        // S9: neutral and not adjacent, even for the King. S13: adjacent to the home.
        #expect(outcomes[1].events == [.dartRegistered(player: 0, hit: .single(9)), .noEffect(player: 0)])
        #expect(outcomes[2].events == [.dartRegistered(player: 0, hit: .single(13)), .sectorClaimed(player: 0, sector: 13),
                                       .turnCompleted(player: 0)])
        // S11: the home of J2, attacked by the King from afar. S12: neutral, not adjacent.
        #expect(outcomes[8].events == [.dartRegistered(player: 0, hit: .single(11)), .sectorDamaged(player: 0, sector: 11, livesLeft: 2)])
        #expect(outcomes[9].events == [.dartRegistered(player: 0, hit: .single(12)), .noEffect(player: 0)])
        #expect(sectors(match, 0) == [6: 3, 13: 1] && sectors(match, 1) == [11: 2])
    }

    @Test func con6_noAttackWithoutAdjacencyNorCrown() throws {
        var match = try registry.match(.conqueror, players: 2, seed: 1)
        let outcomes = match.play("S10, S10, S10 | S10, S6, S14")
        #expect(sectors(match, 0) == [6: 3, 10: 3] && sectors(match, 1) == [11: 3, 14: 1])
        #expect(outcomes[4].events == [.dartRegistered(player: 1, hit: .single(10)), .noEffect(player: 1)])
        #expect(outcomes[5].events == [.dartRegistered(player: 1, hit: .single(6)), .noEffect(player: 1)])
        #expect(outcomes[6].events == [.dartRegistered(player: 1, hit: .single(14)), .sectorClaimed(player: 1, sector: 14),
                                       .turnCompleted(player: 1)])
    }

    @Test func con7_homesAreNeverAdjacent() throws {
        #expect(ints(try registry.match(.conqueror, players: 4, seed: 42), "homeSector") == [9, 16, 1, 17])
        #expect(ints(try registry.match(.conqueror, players: 8, seed: 1), "homeSector") == [18, 6, 7, 9, 3, 15, 11, 5])
        // The property behind the two examples, for every number of players: the home is the first number of the
        // player's block of `ringLayout(width: 2)`, so two homes are never neighbours and both neighbours are free.
        let geometry = BoardGeometry.standard
        for seed in UInt64(0)..<120 {
            for players in 2...8 {
                let match = try registry.match(.conqueror, players: players, seed: seed)
                let homes = ints(match, "homeSector")
                var random = SeededRandom(seed: seed)
                #expect(homes == ringLayout(playerCount: players, width: 2, rng: &random).map { $0[0] }, "seed \(seed)")
                #expect(Set(homes).count == players && homes.allSatisfy((1...20).contains))
                for home in homes {
                    let around = geometry.neighbours(of: home)
                    #expect(!homes.contains(around.anticlockwise) && !homes.contains(around.clockwise), "seed \(seed)")
                }
                for player in 0..<players {
                    #expect(sectors(match, player) == [homes[player]: 3])
                }
            }
        }
    }

    // MARK: §12.2 Options and §12.3 initial state

    @Test func options_defaultsAndRefusals() throws {
        let match = try registry.match(.conqueror, players: 5, seed: 3)
        #expect(match.snapshot.roundLimit == 15 && match.gameFact("king") == -1)
        #expect(ints(match, "totalLives") == [3, 3, 3, 3, 3] && ints(match, "sectorCount") == [1, 1, 1, 1, 1])
        #expect(eliminated(match) == [false, false, false, false, false] && match.snapshot.ranks == [1, 1, 1, 1, 1])
        #expect(match.configuration.options == ConquerorRules.descriptor.defaultOptions)
        #expect(try registry.match(.conqueror, ["maxRounds": .null], players: 2).snapshot.roundLimit == nil)
        #expect(throws: GameConfigurationError.playerCountOutOfRange(allowed: 2...8, actual: 1)) {
            try registry.match(.conqueror, players: 1)
        }
        #expect(throws: GameConfigurationError.playerCountOutOfRange(allowed: 2...8, actual: 9)) {
            try registry.match(.conqueror, players: 9)
        }
        #expect(throws: GameConfigurationError.invalidOptionValue(key: "multipliersCount")) {
            try registry.match(.conqueror, ["multipliersCount": "yes"], players: 2)
        }
        #expect(throws: GameConfigurationError.invalidOptionValue(key: "maxRounds")) {
            try registry.match(.conqueror, ["maxRounds": 100], players: 2)
        }
    }

    // MARK: §12.4 Effect of a dart

    @Test func dart_missHasNoEffect() throws {
        var match = try registry.match(.conqueror, players: 2, seed: 1)
        #expect(match.play("MISS")[0].events == [.dartRegistered(player: 0, hit: .miss), .noEffect(player: 0)])
        #expect(sectors(match, 0) == [6: 3] && match.gameFact("king") == -1)
    }

    @Test func dart_bullCrownsUntilAnotherPlayerHitsIt() throws {
        var match = try registry.match(.conqueror, players: 3, seed: 1)
        let first = match.play("DB, SB, DB")
        #expect(first[0].events == [.dartRegistered(player: 0, hit: .innerBull), .kingOfTheHill(player: 0)])
        // Already King: both bulls do nothing.
        #expect(first[1].events == [.dartRegistered(player: 0, hit: .outerBull), .noEffect(player: 0)])
        #expect(first[2].events == [.dartRegistered(player: 0, hit: .innerBull), .noEffect(player: 0), .turnCompleted(player: 0)])
        // The King stays King through the turns of the others.
        match.play("| MISS |")
        #expect(match.gameFact("king") == 0 && match.snapshot.currentPlayer == 2)
        #expect(match.play("SB")[0].events == [.dartRegistered(player: 2, hit: .outerBull), .kingOfTheHill(player: 2)])
        #expect(match.gameFact("king") == 2)
        // The crown is not a sector: nobody's lives changed.
        #expect(ints(match, "totalLives") == [3, 3, 3])
    }

    @Test func dart_ownSectorGainsLivesUpToThree() throws {
        var match = try registry.match(.conqueror, players: 2, seed: 1)
        let outcomes = match.play("S10, S10, S10 | MISS | S10, D10, T6")
        #expect(outcomes[1].events == [.dartRegistered(player: 0, hit: .single(10)), .sectorStrengthened(player: 0, sector: 10, lives: 2)])
        #expect(outcomes[2].events == [.dartRegistered(player: 0, hit: .single(10)), .sectorStrengthened(player: 0, sector: 10, lives: 3),
                                       .turnCompleted(player: 0)])
        // At three lives a sector cannot grow: no effect, on a claimed sector as on the home.
        #expect(outcomes[6].events == [.dartRegistered(player: 0, hit: .single(10)), .noEffect(player: 0)])
        #expect(outcomes[7].events == [.dartRegistered(player: 0, hit: .double(10)), .noEffect(player: 0)])
        #expect(outcomes[8].events == [.dartRegistered(player: 0, hit: .treble(6)), .noEffect(player: 0), .turnCompleted(player: 0)])
        #expect(sectors(match, 0) == [6: 3, 10: 3])
    }

    @Test func dart_multipliersGiveTheForceOfTheDart() throws {
        var match = try registry.match(.conqueror, ["multipliersCount": true], players: 2, seed: 1)
        // Claims: 1, 2 or 3 lives at once.
        let first = match.play("S10, D13, T15")
        #expect(sectors(match, 0) == [6: 3, 10: 1, 13: 2, 15: 3])
        #expect(first.map { $0.events[1] } == [.sectorClaimed(player: 0, sector: 10), .sectorClaimed(player: 0, sector: 13),
                                               .sectorClaimed(player: 0, sector: 15)])
        // Strengthening is capped at three lives, and the event carries the new lives.
        let second = match.play("| MISS | T10, D13, S13")
        #expect(second[3].events == [.dartRegistered(player: 0, hit: .treble(10)), .sectorStrengthened(player: 0, sector: 10, lives: 3)])
        #expect(second[4].events == [.dartRegistered(player: 0, hit: .double(13)), .sectorStrengthened(player: 0, sector: 13, lives: 3)])
        #expect(second[5].events == [.dartRegistered(player: 0, hit: .single(13)), .noEffect(player: 0), .turnCompleted(player: 0)])
        // Attacks: J2, King, takes two lives with a double, then conquers with a treble whose excess is lost.
        let third = match.play("| DB, D15, T15")
        #expect(third[2].events == [.dartRegistered(player: 1, hit: .double(15)), .sectorDamaged(player: 1, sector: 15, livesLeft: 1)])
        #expect(third[3].events == [.dartRegistered(player: 1, hit: .treble(15)), .sectorConquered(player: 1, sector: 15, from: 0),
                                    .turnCompleted(player: 1)])
        #expect(sectors(match, 0) == [6: 3, 10: 3, 13: 3] && sectors(match, 1) == [11: 3, 15: 1])
        // The bulls crown whatever their multiplier.
        #expect(match.gameFact("king") == 1)
    }

    @Test func dart_withoutMultipliersEveryBedIsOneHit() throws {
        for hit in [Hit.single(10), .double(10), .treble(10)] {
            var match = try registry.match(.conqueror, players: 2, seed: 1)
            match.throwDart(DartRecord(hit: hit))
            #expect(sectors(match, 0) == [6: 3, 10: 1], "\(hit)")
            match.throwDart(DartRecord(hit: hit))
            #expect(sectors(match, 0) == [6: 3, 10: 2], "\(hit)")
        }
    }

    @Test func dart_adjacencyIsLostWithTheSectorThatGaveIt() throws {
        var match = try registry.match(.conqueror, players: 2, seed: 1)
        // J1 claims 10; J2, King, conquers it: J1 is no longer next to 15, J2 is.
        match.play("S10 | SB, S10 |")
        #expect(sectors(match, 0) == [6: 3] && sectors(match, 1) == [11: 3, 10: 1])
        #expect(match.play("S15")[0].events == [.dartRegistered(player: 0, hit: .single(15)), .noEffect(player: 0)])
        // The 10 is next to J1's home: he can take it back without the crown.
        #expect(match.play("S10")[0].events == [.dartRegistered(player: 0, hit: .single(10)), .sectorConquered(player: 0, sector: 10, from: 1)])
        #expect(match.play("S15")[0].events == [.dartRegistered(player: 0, hit: .single(15)), .sectorClaimed(player: 0, sector: 15),
                                                .turnCompleted(player: 0)])
        #expect(sectors(match, 0) == [6: 3, 10: 1, 15: 1] && sectors(match, 1) == [11: 3])
    }

    @Test func dart_homeCaptureEliminatesAndPassesTheTerritoryWithItsLives() throws {
        var match = try registry.match(.conqueror, ["multipliersCount": true], players: 3, seed: 1)
        // Homes 6, 16, 20. J2 builds 8 (2 lives) and 7 (3 lives) and takes the crown.
        match.play("MISS | D8, T7, SB | MISS |")
        #expect(sectors(match, 1) == [16: 3, 8: 2, 7: 3] && match.gameFact("king") == 1)
        // J1 becomes King, weakens the home of J2, then takes it in round 3.
        match.play("DB, D16 | MISS | MISS |")
        #expect(match.gameFact("king") == 0 && sectors(match, 1) == [16: 1, 8: 2, 7: 3])
        let capture = match.play("T16")
        #expect(capture[0].events == [.dartRegistered(player: 0, hit: .treble(16)), .sectorConquered(player: 0, sector: 16, from: 1),
                                      .playerEliminated(player: 1, by: 0)])
        // The former home is an ordinary sector with one life; the rest keeps its lives.
        #expect(sectors(match, 0) == [6: 3, 16: 1, 8: 2, 7: 3] && sectors(match, 1) == [:])
        #expect(ints(match, "totalLives") == [9, 0, 3] && ints(match, "sectorCount") == [4, 0, 1])
        #expect(eliminated(match) == [false, true, false] && match.snapshot.ranks == [1, 3, 2])
        #expect(match.phase == .throwing && match.snapshot.players.map(\.isEliminated) == [false, true, false])
        // On the board the fallen home is a plain sector of J1: the home marker stays on the homes still standing.
        #expect(match.snapshot.highlights.contains(BoardHighlight(zone: .sector(16), role: .secondary, owner: 0, strength: 1)))
        #expect(match.snapshot.highlights.filter { $0.marker == .home }.map(\.zone) == [.sector(6), .sector(20)])
        // J3 takes the crown and conquers the former home of J2: nobody is eliminated by that.
        match.play("| SB, S16")
        #expect(match.snapshot.currentPlayer == 2 && eliminated(match) == [false, true, false])
        #expect(sectors(match, 0) == [6: 3, 8: 2, 7: 3] && sectors(match, 2) == [20: 3, 16: 1])
        #expect(match.phase == .throwing)
    }

    @Test func dart_aFormerKingLosesHisReachAndTheNewKingKeepsHisCrown() throws {
        var match = try registry.match(.conqueror, players: 3, seed: 1)   // homes 6, 16, 20
        match.play("SB | MISS | MISS |")                 // J1 is King
        match.play("S16, S16 | SB | MISS |")             // the home of J2 is down to 1; J2 takes the crown
        #expect(match.gameFact("king") == 1 && sectors(match, 1) == [16: 1])
        // J1, no longer King and next to nothing of J2, cannot finish the job.
        #expect(match.play("S16")[0].events == [.dartRegistered(player: 0, hit: .single(16)), .noEffect(player: 0)])
        // J3 takes the crown, then the home of J2: J2 is out, and the crown stays on J3.
        let capture = match.play("| MISS | SB, S16")
        #expect(capture.last?.events == [.dartRegistered(player: 2, hit: .single(16)), .sectorConquered(player: 2, sector: 16, from: 1),
                                         .playerEliminated(player: 1, by: 2)])
        #expect(eliminated(match) == [false, true, false] && match.gameFact("king") == 2)
        #expect(sectors(match, 2) == [20: 3, 16: 1])
    }

    @Test func dart_eliminatingTheKingLeavesNoKing() throws {
        // Two players would end the game; with three, the crown must be vacant after the King's home falls.
        var match = try registry.match(.conqueror, players: 3, seed: 1)
        // J1 walks from his home 6 to the 16 of J2 by adjacency: 6 → 10 → 15 → 2 → 17 → 3 → 19 → 7, then attacks 16.
        match.play("S10, S15, S2 | SB | MISS |")         // J2 is King
        match.play("S17, S3, S19 | MISS | MISS |")
        match.play("S7, S16, S16 | MISS | MISS |")
        #expect(match.gameFact("king") == 1 && sectors(match, 1) == [16: 1])
        let capture = match.play("S16")
        #expect(capture[0].events == [.dartRegistered(player: 0, hit: .single(16)), .sectorConquered(player: 0, sector: 16, from: 1),
                                      .playerEliminated(player: 1, by: 0)])
        #expect(match.gameFact("king") == -1 && eliminated(match) == [false, true, false])
        #expect(match.snapshot.players[1].badges == [Badge(LocalizedText(fr: "Éliminé", en: "Eliminated"), tone: .negative)])
        // Without a King and without adjacency, the home of J3 (20) is out of reach.
        #expect(match.play("S20")[0].events == [.dartRegistered(player: 0, hit: .single(20)), .noEffect(player: 0)])
    }

    // MARK: §12.5 and §12.6 Turn, elimination, ranking

    @Test func turn_eliminatedPlayersAreSkippedAndTheRoundLimitStillApplies() throws {
        var match = try registry.match(.conqueror, ["maxRounds": 2], players: 3, seed: 1)
        match.play("SB, S20, S20 | MISS | MISS |")
        match.play("S20")                                 // J3 is out in round 2
        #expect(eliminated(match) == [false, false, true] && match.phase == .throwing)
        match.play("|")
        #expect(match.snapshot.currentPlayer == 1 && match.snapshot.round == 2)
        // J2 is now the last player of the round: his confirmation ends the game at the limit.
        #expect(match.endTurn().events == [.turnCompleted(player: 1), .gameFinished(reason: .roundLimit)])
        #expect(match.snapshot.ranks == [1, 2, 3] && ints(match, "totalLives") == [4, 3, 0])
    }

    @Test func ranking_totalLivesThenSectorCountThenTie() throws {
        var match = try registry.match(.conqueror, ["maxRounds": 2], players: 2, seed: 1)
        match.play("S10 | S8 |")
        // Four lives and two sectors each: tie.
        #expect(ints(match, "totalLives") == [4, 4] && ints(match, "sectorCount") == [2, 2] && match.snapshot.ranks == [1, 1])
        // J1, King, takes a life from the home of J2; J2 claims the 14: four lives each, but three sectors for J2.
        match.play("SB, S11 | S14")
        #expect(ints(match, "totalLives") == [4, 4] && ints(match, "sectorCount") == [2, 3] && match.snapshot.ranks == [2, 1])
        // One more life for J1: lives come first.
        match.undo()
        match.undo()
        match.play("S10 |")
        #expect(ints(match, "totalLives") == [5, 3] && match.snapshot.ranks == [1, 2])
        match.play("|")
        #expect(match.phase == .finished && match.snapshot.finishReason == .roundLimit && match.snapshot.winners == [0])
    }

    @Test func ranking_livesComeBeforeSectors() throws {
        var match = try registry.match(.conqueror, ["multipliersCount": true, "maxRounds": 1], players: 2, seed: 1)
        match.play("T10 | S8, S14 |")
        // J1: six lives on two sectors. J2: five lives on three sectors. The lives decide.
        #expect(ints(match, "totalLives") == [6, 5] && ints(match, "sectorCount") == [2, 3])
        #expect(match.phase == .finished && match.snapshot.ranks == [1, 2] && match.snapshot.winners == [0])
    }

    @Test func ranking_eliminatedPlayersComeLastInReverseOrder() throws {
        var match = try registry.match(.conqueror, players: 4, seed: 42)   // homes 9, 16, 1, 17
        match.play("SB, S16, S16 | MISS | MISS | MISS |")
        match.play("S16, S17, S17 | MISS | MISS |")                        // J2 out in round 2; J4's home at 1
        #expect(match.snapshot.currentPlayer == 0 && match.snapshot.round == 3)
        match.play("S17")                                                  // J4 out in round 3
        #expect(eliminated(match) == [false, true, false, true])
        // J1 has 5 lives on 3 sectors, J3 his home: J1, J3, then J4 (last out), then J2.
        #expect(match.snapshot.ranks == [1, 4, 2, 3] && match.phase == .throwing)
        match.play("S1, S1 | MISS | S1")
        #expect(match.phase == .finished && match.snapshot.finishReason == .lastPlayerStanding)
        #expect(match.snapshot.ranks == [1, 4, 2, 3] && match.snapshot.winners == [0])
    }

    // MARK: §12.7 Scoreboard and highlights

    @Test func highlights_rolesForTheCurrentPlayer() throws {
        var match = try registry.match(.conqueror, players: 2, seed: 1)
        // Start: the home (3 lives) is `own`, its two neutral neighbours are targets, the far home is an opponent's,
        // and the bull is worth a try.
        #expect(Set(match.snapshot.highlights) == [
            BoardHighlight(zone: .sector(6), role: .own, owner: 0, strength: 3, marker: .home),
            BoardHighlight(zone: .sector(13), role: .target), BoardHighlight(zone: .sector(10), role: .target),
            BoardHighlight(zone: .sector(11), role: .opponent, owner: 1, strength: 3, marker: .home),
            BoardHighlight(zone: .bull, role: .secondary),
        ])
        #expect(match.snapshot.highlights.count == 5)

        // J1 claims the 10 (1 life: worth strengthening) and takes the crown: everything of J2 becomes a target,
        // and the bull is his.
        match.play("S10, SB")
        #expect(Set(match.snapshot.highlights) == [
            BoardHighlight(zone: .sector(6), role: .own, owner: 0, strength: 3, marker: .home),
            BoardHighlight(zone: .sector(10), role: .secondary, owner: 0, strength: 1),
            BoardHighlight(zone: .sector(13), role: .target), BoardHighlight(zone: .sector(15), role: .target),
            BoardHighlight(zone: .sector(11), role: .target, owner: 1, strength: 3, marker: .home),
            BoardHighlight(zone: .bull, role: .own, owner: 0, marker: .crown),
        ])

        // J2: his home, his two neighbours; the sectors of J1 are out of reach; the bull carries the King's colour.
        match.play("MISS |")
        #expect(Set(match.snapshot.highlights) == [
            BoardHighlight(zone: .sector(11), role: .own, owner: 1, strength: 3, marker: .home),
            BoardHighlight(zone: .sector(8), role: .target), BoardHighlight(zone: .sector(14), role: .target),
            BoardHighlight(zone: .sector(6), role: .opponent, owner: 0, strength: 3, marker: .home),
            BoardHighlight(zone: .sector(10), role: .opponent, owner: 0, strength: 1),
            BoardHighlight(zone: .bull, role: .secondary, owner: 0, marker: .crown),
        ])
        match.play("S8, S8, S8")
        #expect(match.phase == .turnComplete)
        #expect(match.snapshot.highlights.contains(BoardHighlight(zone: .sector(8), role: .own, owner: 1, strength: 3)))
        #expect(match.snapshot.highlights.contains(BoardHighlight(zone: .sector(16), role: .target)))
    }

    @Test func highlights_anOpponentSectorNextToMineIsATargetWithoutTheCrown() throws {
        var match = try registry.match(.conqueror, players: 2, seed: 1)
        // J1 walks 10, 15; J2 walks 14, 9, 12; J1 goes on 2, 17, 3 … not needed: make the borders meet on the 8 side.
        match.play("S13, S4, S18 | S8, S16, S7 |")
        match.play("S1, S20, S5 | S19, S3, S17 |")
        match.play("S12 |")
        // J1 owns 6, 13, 4, 18, 1, 20, 5, 12; J2 owns 11, 8, 16, 7, 19, 3, 17. The 9 and the 14 lie between 12 and 11.
        #expect(match.snapshot.currentPlayer == 1)
        let byZone = Dictionary(uniqueKeysWithValues: match.snapshot.highlights.map { ($0.zone, $0) })
        #expect(byZone[.sector(14)] == BoardHighlight(zone: .sector(14), role: .target))
        #expect(byZone[.sector(9)] == nil)                                  // neutral, next to nothing of J2
        #expect(byZone[.sector(12)]?.role == .opponent)                     // J1's, not adjacent to J2
        match.play("S14, S9")
        // Now the 12 of J1 touches the 9 of J2: attackable, in J1's colour.
        #expect(match.snapshot.highlights.contains(BoardHighlight(zone: .sector(12), role: .target, owner: 0, strength: 1)))
        #expect(match.play("S12")[0].events == [.dartRegistered(player: 1, hit: .single(12)), .sectorConquered(player: 1, sector: 12, from: 0),
                                                .turnCompleted(player: 1)])
    }

    @Test func highlights_agreeWithTheRulesOnEveryNumber() throws {
        // A sector is `target` or `secondary` exactly when a dart on it does something; the same for the bull.
        var random = SeededRandom(seed: 2026)
        for seed in UInt64(1)...3 {
            for (players, multipliers) in [(2, false), (3, true), (5, false), (8, true)] {
                var match = try registry.match(.conqueror, ["multipliersCount": .bool(multipliers), "maxRounds": 12],
                                               players: players, seed: seed)
                for _ in 0..<90 where match.phase != .finished {
                    if match.phase == .throwing {
                        let roles = Dictionary(uniqueKeysWithValues: match.snapshot.highlights.map { ($0.zone, $0.role) })
                        #expect(roles.count == match.snapshot.highlights.count)
                        for number in 1...20 {
                            var copy = match
                            let useful = !copy.throwDart(DartRecord(hit: .single(number))).events.contains(.noEffect(player: match.snapshot.currentPlayer))
                            let role = roles[.sector(number)]
                            #expect(useful == (role == .target || role == .secondary), "seed \(seed) sector \(number) role \(String(describing: role))")
                        }
                        var copy = match
                        let crowned = copy.throwDart(DartRecord(hit: .outerBull)).events.contains(.kingOfTheHill(player: match.snapshot.currentPlayer))
                        #expect(crowned == (roles[.bull] == .secondary))
                        #expect(roles[.bull] == .secondary || roles[.bull] == .own)
                    }
                    if match.phase == .turnComplete || random.nextInt(below: 9) == 0 {
                        match.endTurn()
                    } else {
                        // Mostly useful darts, so that territories grow, meet and fall.
                        let useful = match.snapshot.highlights.filter { $0.role == .target || $0.role == .secondary }
                        if random.nextInt(below: 4) == 0 || useful.isEmpty {
                            match.throwDart(DartRecord(hit: Hit.all[random.nextInt(below: Hit.all.count)]))
                        } else {
                            let zone = useful[random.nextInt(below: useful.count)].zone
                            let hit: Hit = zone.number.map { random.nextInt(below: 2) == 0 ? .single($0) : .treble($0) } ?? .innerBull
                            match.throwDart(DartRecord(hit: hit))
                        }
                    }
                }
            }
        }
    }

    @Test func presentation_rowsBadgesAndCaptions() throws {
        var match = try registry.match(.conqueror, players: 2, seed: 1)
        #expect(match.snapshot.title == LocalizedText(fr: "Conquérant", en: "Conqueror") && match.snapshot.gameID == .conqueror)
        #expect(match.snapshot.variant == nil && match.snapshot.winnerTitle == nil)
        let first = match.snapshot.players[0]
        #expect(first.primary == ScoreValue(3, unit: LocalizedText(fr: "vies", en: "lives")))
        #expect(first.detail == LocalizedText(fr: "1 secteur · maison 6", en: "1 sector · home 6"))
        #expect(first.badges.isEmpty && !first.isEliminated && first.meter == nil)

        match.play("S10, S10, S20")
        #expect(match.snapshot.turn.darts.map(\.caption) == [
            DartCaption(LocalizedText(fr: "10 revendiqué", en: "10 claimed"), tone: .positive),
            DartCaption(LocalizedText(fr: "10 renforcé", en: "10 fortified"), tone: .positive),
            DartCaption(LocalizedText(fr: "Sans effet", en: "No effect")),
        ])
        #expect(match.snapshot.players[0].primary == ScoreValue(5, unit: LocalizedText(fr: "vies", en: "lives")))
        #expect(match.snapshot.players[0].detail == LocalizedText(fr: "2 secteurs · maison 6", en: "2 sectors · home 6"))

        match.play("| SB, S10, S10")
        #expect(match.snapshot.turn.darts.map(\.caption) == [
            DartCaption(LocalizedText(fr: "Roi !", en: "King!"), tone: .positive),
            DartCaption(LocalizedText(fr: "J1 −1 vie", en: "J1 −1 life"), tone: .negative),
            DartCaption(LocalizedText(fr: "10 conquis", en: "10 conquered"), tone: .positive),
        ])
        #expect(match.snapshot.players[1].badges == [Badge(LocalizedText(fr: "Roi", en: "King"), tone: .accent)])
        #expect(match.snapshot.players[0].badges.isEmpty)

        let multipliers = try registry.match(.conqueror, ["multipliersCount": true], players: 2, seed: 1)
        #expect(multipliers.snapshot.variant == LocalizedText(fr: "Multiplicateurs", en: "Multipliers"))
    }

    @Test func presentation_resultsOfBothEndings() throws {
        var match = try registry.match(.conqueror, ["multipliersCount": true], players: 2, seed: 1)
        match.play("T10, D13, T6 | DB, T6")
        #expect(match.phase == .finished)
        #expect(match.snapshot.turn.darts.map(\.caption) == [
            DartCaption(LocalizedText(fr: "Roi !", en: "King!"), tone: .positive),
            DartCaption(LocalizedText(fr: "J1 éliminé", en: "J1 eliminated"), tone: .negative),
        ])
        #expect(match.snapshot.outcome == LocalizedText(fr: "Dernier en jeu, maître de 4 secteurs.",
                                                        en: "Last one in play, holding 4 sectors."))
        let loser = match.snapshot.players[0]
        #expect(loser.isEliminated && loser.badges == [Badge(LocalizedText(fr: "Éliminé", en: "Eliminated"), tone: .negative)])
        #expect(loser.primary == ScoreValue(0, unit: LocalizedText(fr: "vie", en: "lives")))
        #expect(loser.detail == LocalizedText(fr: "Maison 6 perdue", en: "Home 6 lost"))
        #expect(loser.resultLines == [LocalizedText(fr: "Éliminé manche 1", en: "Eliminated in round 1")])
        #expect(match.snapshot.players[1].resultLines == [LocalizedText(fr: "4 secteurs", en: "4 sectors")])
        #expect(match.snapshot.players[1].badges == [Badge(LocalizedText(fr: "Roi", en: "King"), tone: .accent)])
        // The home of an eliminated player stays in the facts as the sector it was.
        #expect(ints(match, "homeSector") == [6, 11])

        var limit = try registry.match(.conqueror, ["maxRounds": 1], players: 2, seed: 1)
        limit.play("S10, S15, S6 | S8, S8, S14 |")
        #expect(limit.snapshot.outcome == LocalizedText(fr: "En tête à la limite de manches, avec 6 vies.",
                                                        en: "Ahead at the round limit, with 6 lives."))
        #expect(limit.snapshot.turn.darts.isEmpty && limit.snapshot.highlights.isEmpty)
        var tie = try registry.match(.conqueror, ["maxRounds": 1], players: 3, seed: 1)
        tie.play("| | |")
        #expect(tie.phase == .finished && tie.snapshot.ranks == [1, 1, 1])
        #expect(tie.snapshot.outcome == LocalizedText(fr: "Égalité à la limite de manches, avec 3 vies.",
                                                      en: "Tied at the round limit, with 3 lives."))
    }

    // MARK: Undo, corrections, replay (GAMES.md §2.5): the homes are rebuilt from the seed every time

    @Test func correction_undoingAHomeCaptureGivesEverythingBack() throws {
        var match = try registry.match(.conqueror, players: 3, seed: 1)
        match.play("SB, S16, S16 | S8, S7, MISS | MISS ×3 |")
        let before = match.snapshot
        match.play("S16")
        #expect(eliminated(match) == [false, true, false] && sectors(match, 0) == [6: 3, 16: 1, 7: 1, 8: 1])
        match.undo()
        #expect(match.snapshot == before)
        #expect(sectors(match, 1) == [16: 1, 8: 1, 7: 1] && match.gameFact("king") == 0 && ints(match, "homeSector") == [6, 16, 20])
        // Three lives each; J2 holds three sectors.
        #expect(eliminated(match) == [false, false, false] && match.snapshot.ranks == [2, 1, 2])
    }

    @Test func correction_replacingADartRewritesEverythingAfterIt() throws {
        var match = try registry.match(.conqueror, players: 2, seed: 1)
        match.play("S10, S15, S2")
        #expect(sectors(match, 0) == [6: 3, 10: 1, 15: 1, 2: 1])
        // Without the 10 the chain never starts: 15 and 2 are not adjacent any more.
        match.replaceDart(at: 0, with: .single(9))
        #expect(sectors(match, 0) == [6: 3] && match.turnNotation == ["S9", "S15", "S2"] && match.phase == .turnComplete)
        match.removeDart(at: 0)
        #expect(match.phase == .throwing && match.turnNotation == ["S15", "S2"] && sectors(match, 0) == [6: 3])
        match.replaceDart(at: 0, with: .single(10))
        match.replaceDart(at: 1, with: .single(15))
        #expect(sectors(match, 0) == [6: 3, 10: 1, 15: 1])
        // A correction that wins the game drops the darts that follow.
        var end = try registry.match(.conqueror, ["multipliersCount": true], players: 2, seed: 1)
        end.play("SB, D11, S12")
        #expect(sectors(end, 1) == [11: 1] && end.phase == .turnComplete)
        let win = end.replaceDart(at: 1, with: .treble(11))
        #expect(win.dropped.map(\.hit) == [.single(12)] && end.phase == .finished && end.turnNotation == ["SB", "T11"])
        #expect(end.snapshot.ranks == [1, 2])
    }

    @Test func effectKey_groupsTheDartsOfEqualEffect() throws {
        let match = try registry.match(.conqueror, players: 2, seed: 1)
        // Without multipliers the three beds of a number are one and the same hit.
        #expect(match.effectKey(for: .single(10)) == match.effectKey(for: .treble(10)))
        #expect(match.effectKey(for: .single(10)) != match.effectKey(for: .single(13)))
        #expect(match.effectKey(for: .outerBull) == match.effectKey(for: .innerBull))
        // Every useless dart is the same useless dart.
        #expect(match.effectKey(for: .single(9)) == match.effectKey(for: .double(6)))
        #expect(match.effectKey(for: .single(9)) == match.effectKey(for: .miss))
        // With multipliers a claim keeps its force in the facts, but a conquest forgets its excess.
        var strong = try registry.match(.conqueror, ["multipliersCount": true], players: 2, seed: 1)
        #expect(strong.effectKey(for: .single(10)) != strong.effectKey(for: .treble(10)))
        strong.play("S10 | SB |")
        strong.play("MISS |")
        #expect(strong.snapshot.currentPlayer == 1 && sectors(strong, 0) == [6: 3, 10: 1])
        #expect(strong.effectKey(for: .single(10)) == strong.effectKey(for: .treble(10)))
        #expect(strong.effectKey(for: .single(6)) != strong.effectKey(for: .double(6)))
    }

    @Test func position_aRecordedPositionChangesNothing() throws {
        var plain = try registry.match(.conqueror, players: 2, seed: 1)
        var placed = plain
        for (index, hit) in [Hit.single(10), .outerBull, .miss, .single(8), .treble(14), .single(10)].enumerated() {
            #expect(plain.throwDart(DartRecord(hit: hit))
                    == placed.throwDart(DartRecord(hit: hit, position: BoardPoint(x: Double(index) * 17, y: 60 - Double(index) * 9))))
            if plain.phase == .turnComplete { #expect(plain.endTurn() == placed.endTurn()) }
        }
        #expect(plain.snapshot == placed.snapshot)
    }

    @Test func replay_aSavedGameDrawsTheSameHomesAgain() throws {
        // The homes are not saved: they come back from the seed, here the largest one.
        var match = try registry.match(.conqueror, ["multipliersCount": true], players: 6, seed: .max)
        let homes = ints(match, "homeSector")
        for _ in 0..<3 {
            for home in homes where match.phase != .finished {
                // Everybody claims the clockwise neighbour of his home, then takes the crown.
                let neighbour = BoardGeometry.standard.neighbours(of: home).clockwise
                if match.snapshot.currentPlayer == homes.firstIndex(of: home) {
                    match.throwDart(DartRecord(hit: .double(neighbour)))
                    match.throwDart(DartRecord(hit: .outerBull))
                    match.endTurn()
                }
            }
        }
        #expect(ints(match, "sectorCount") == [2, 2, 2, 2, 2, 2] && ints(match, "totalLives") == [6, 6, 6, 6, 6, 6])
        #expect(match.gameFact("king") == 5 && match.snapshot.round == 4)
        let saved = try MoonLandingReplayChecks.restoredFromJSON(match)
        #expect(saved.snapshot == match.snapshot && saved.entries == match.entries)
        #expect(ints(saved, "homeSector") == homes)
        #expect(try MoonLandingReplayChecks.replay(match.record).events == MoonLandingReplayChecks.replay(saved.record).events)
    }

    @Test func effectKey_equalKeysLeaveEqualFutures() throws {
        var pairs = 0
        for seed in UInt64(1)...4 {
            pairs += try MoonLandingReplayChecks.equalKeysHaveEqualFutures(
                .conqueror, ["multipliersCount": .bool(seed % 2 == 0), "maxRounds": 8], players: Int(seed) + 1, seed: seed,
                fuzzSeed: seed &+ 60, states: 40, hits: Hit.all + [.innerBull, .outerBull])
        }
        #expect(pairs > 100)
    }

    @Test func replay_theJournalAloneRebuildsTheGame() throws {
        // Two darts out of three go where the board says a dart is useful, so that territories grow, meet and fall;
        // the third is any of the 63 values.
        func pick(_ snapshot: GameSnapshot, _ random: inout SeededRandom) -> Hit {
            let useful = snapshot.highlights.filter { $0.role == .target || $0.role == .secondary }
            guard random.nextInt(below: 3) > 0, !useful.isEmpty else { return Hit.all[random.nextInt(below: Hit.all.count)] }
            guard let number = useful[random.nextInt(below: useful.count)].zone.number else { return .innerBull }
            return [Hit.single(number), .double(number), .treble(number)][random.nextInt(below: 3)]
        }
        var eliminations = 0, finished = 0
        for seed in UInt64(1)...4 {
            for (players, multipliers) in [(2, false), (3, true), (5, false), (8, true)] {
                try MoonLandingReplayChecks.fuzz(
                    .conqueror, ["multipliersCount": .bool(multipliers), "maxRounds": 6], players: players, seed: seed,
                    fuzzSeed: seed &* 977 &+ UInt64(players), steps: 130, pick: pick
                ) { snapshot in
                    eliminations += snapshot.players.filter(\.isEliminated).count
                    finished += snapshot.phase == .finished ? 1 : 0
                    var owned: [Int: Int] = [:]
                    var inPlay = 0
                    for row in snapshot.players {
                        guard case .map(let sectors)? = row.facts["sectors"], case .int(let total)? = row.facts["totalLives"],
                              case .int(let count)? = row.facts["sectorCount"], case .int(let home)? = row.facts["homeSector"],
                              case .bool(let eliminated)? = row.facts["eliminated"] else {
                            Issue.record("missing fact")
                            return
                        }
                        #expect(total == sectors.values.reduce(0, +) && count == sectors.count)
                        #expect(sectors.allSatisfy { (1...20).contains($0.key) && (1...3).contains($0.value) })
                        #expect(eliminated ? sectors.isEmpty : sectors[home] != nil)
                        #expect(row.isEliminated == eliminated)
                        for sector in sectors.keys {
                            #expect(owned[sector] == nil, "sector \(sector) has two owners")
                            owned[sector] = row.player
                        }
                        inPlay += eliminated ? 0 : 1
                    }
                    guard case .int(let king)? = snapshot.facts["king"] else {
                        Issue.record("missing king")
                        return
                    }
                    #expect(king == -1 || (snapshot.players.indices.contains(king) && !snapshot.players[king].isEliminated))
                    #expect(inPlay >= 1 && (inPlay == 1) == (snapshot.finishReason == .lastPlayerStanding))
                    let worstInPlay = snapshot.players.filter { !$0.isEliminated }.map(\.rank).max() ?? 0
                    #expect(snapshot.players.filter(\.isEliminated).allSatisfy { $0.rank > worstInPlay })
                }
            }
        }
        // The walk is not a quiet one: homes fall and games end along the way.
        #expect(eliminations > 50 && finished > 50)
    }
}
