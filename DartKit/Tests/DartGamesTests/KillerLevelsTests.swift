import Testing
import DartCore
import DartGames
import DartTestSupport

/// The four Killer levels with every allowed number of players (GAMES.md §5.2, §5.3): the zones that are drawn,
/// the options, and whole games played to the last survivor.
@Suite struct KillerLevelsTests {
    private let registry = GameRegistry.standard

    private struct LevelCase: Sendable, CustomTestStringConvertible {
        var name: String
        var width: Int
        var players: ClosedRange<Int>
        var testDescription: String { name }
    }

    /// GAMES.md §5.2: easy = 3 adjacent numbers (2 to 6 players), medium = 2, hard = 1, expert = 1 (2 to 8 players).
    private static let levels = [
        LevelCase(name: "easy", width: 3, players: 2...6),
        LevelCase(name: "medium", width: 2, players: 2...8),
        LevelCase(name: "hard", width: 1, players: 2...8),
        LevelCase(name: "expert", width: 1, players: 2...8),
    ]

    private func options(_ level: LevelCase, _ more: [String: OptionValue] = [:]) -> GameOptions {
        var values = more
        values["level"] = .string(level.name)
        return GameOptions(values)
    }

    // MARK: Initial draw

    @Test(arguments: levels)
    private func initialZones_areTheRingLayoutOfTheSeed_neverShared(level: LevelCase) throws {
        for players in level.players {
            for seed in UInt64(0)..<40 {
                let match = try registry.match(.killer, options(level), players: players, seed: seed)
                var random = SeededRandom(seed: seed)
                let expected = ringLayout(playerCount: players, width: level.width, rng: &random)
                #expect(match.killerZones == expected, "\(level.name), \(players) players, seed \(seed)")
                // `width` adjacent numbers each, no number shared, the others free.
                #expect(Set(match.killerZones.flatMap { $0 }).count == players * level.width)
                match.killerExpectInvariants(width: level.width, lives: 3, armingHits: 3)

                // Initial state of every player (GAMES.md §5.3).
                #expect(match.killerInts("lives") == Array(repeating: 3, count: players))
                #expect(match.killerInts("armingProgress") == Array(repeating: 0, count: players))
                #expect(match.killerInts("kills") == Array(repeating: 0, count: players))
                #expect(match.killerBools("isKiller") == Array(repeating: false, count: players))
                #expect(match.killerBools("eliminated") == Array(repeating: false, count: players))
                #expect(match.snapshot.ranks == Array(repeating: 1, count: players))
                #expect(match.phase == .throwing && match.snapshot.currentPlayer == 0 && match.snapshot.round == 1)
                #expect(match.snapshot.roundLimit == 15)
            }
        }
    }

    /// The initial draw consumes 1 + (20 − players × width) + (players − 1) draws, and nothing else: the first
    /// redraw of an expert game continues the same stream.
    @Test(arguments: levels)
    private func initialDraw_consumesTheDocumentedNumberOfDraws(level: LevelCase) throws {
        for players in level.players {
            let configuration = GameConfiguration(gameID: .killer, options: options(level), players: testPlayers(players), seed: 99)
            var random = SeededRandom(seed: 99)
            _ = try KillerRules(configuration: configuration, random: &random)
            var reference = SeededRandom(seed: 99)
            for _ in 0..<(1 + (20 - players * level.width) + (players - 1)) { _ = reference.next() }
            #expect(random == reference, "\(level.name), \(players) players")
        }
    }

    @Test func layouts_dependOnTheSeed_andOnlyOnIt() throws {
        var layouts = Set<[[Int]]>()
        for seed in UInt64(0)..<30 {
            let first = try registry.match(.killer, ["level": "hard"], players: 4, seed: seed)
            let second = try registry.match(.killer, ["level": "hard"], players: 4, seed: seed)
            #expect(first.snapshot == second.snapshot)
            layouts.insert(first.killerZones)
        }
        #expect(layouts.count > 20)
        // Hard and expert draw the same initial numbers; lives and arming hits do not change the draw.
        for seed in UInt64(0)..<10 {
            let hard = try registry.match(.killer, ["level": "hard"], players: 5, seed: seed)
            let expert = try registry.match(.killer, ["level": "expert", "lives": 9, "armingHits": 1], players: 5, seed: seed)
            #expect(hard.killerZones == expert.killerZones)
        }
    }

    // MARK: Player bounds (GAMES.md §5.2: no silent fallback)

    @Test func playerBounds_byLevel() throws {
        let note = LocalizedText(fr: "6 joueurs maximum en Facile", en: "6 players maximum in Easy")
        for level in Self.levels {
            for players in 0...10 {
                let result = Result { try registry.match(.killer, options(level), players: players, seed: 3) }
                switch result {
                case .success(let match):
                    #expect(level.players.contains(players), "\(level.name) accepted \(players) players")
                    #expect(match.snapshot.players.count == players)
                case .failure(let error):
                    #expect(!level.players.contains(players), "\(level.name) refused \(players) players")
                    if (2...8).contains(players) {
                        #expect(error as? GameConfigurationError == .choiceUnavailable(key: "level", note: note))
                    } else {
                        #expect(error as? GameConfigurationError == .playerCountOutOfRange(allowed: 2...8, actual: players))
                    }
                }
            }
        }
    }

    /// A rule built without the kernel refuses the same configurations instead of trapping in `ringLayout`.
    @Test func rulesBuiltDirectly_refuseWhatTheKernelRefuses() {
        func make(_ options: GameOptions, players: Int) throws -> KillerRules {
            var random = SeededRandom(seed: 1)
            return try KillerRules(configuration: GameConfiguration(gameID: .killer, options: options,
                                                                    players: testPlayers(players), seed: 1), random: &random)
        }
        #expect(throws: GameConfigurationError.self) { try make(["level": "easy"], players: 7) }
        #expect(throws: GameConfigurationError.self) { try make([:], players: 8) }
        #expect(throws: GameConfigurationError.self) { try make(["level": "hard"], players: 21) }
        #expect(throws: GameConfigurationError.self) { try make(["level": "hard"], players: 0) }
        #expect(throws: GameConfigurationError.invalidOptionValue(key: "level")) { try make(["level": "insane"], players: 2) }
        #expect(throws: GameConfigurationError.invalidOptionValue(key: "lives")) { try make(["lives": 0], players: 2) }
        // Options left out take the defaults of the descriptor.
        #expect(throws: Never.self) {
            let rules = try make([:], players: 6)
            #expect(rules.roundLimit == 15 && rules.ranks() == [1, 1, 1, 1, 1, 1])
        }
    }

    // MARK: Options (GAMES.md §5.2)

    @Test func defaults_easyThreeLivesThreeArmingHitsNoPenaltyFifteenRounds() throws {
        let match = try registry.match(.killer, players: 3, seed: 1)
        #expect(match.configuration.options == KillerRules.descriptor.defaultOptions)
        #expect(match.configuration.options == ["level": "easy", "lives": 3, "armingHits": 3, "selfHitPenalty": false, "maxRounds": 15])
        #expect(match.killerZones == [[8, 11, 14], [6, 10, 15], [20, 1, 18]])
        #expect(match.snapshot.roundLimit == 15)
        #expect(match.snapshot.variant == LocalizedText(fr: "Facile", en: "Easy"))
    }

    @Test func lives_fromOneToNine() throws {
        for lives in 1...9 {
            var match = try registry.match(.killer, ["level": "hard", "lives": .int(lives), "armingHits": 1, "maxRounds": .null],
                                           players: 2, seed: 1)
            #expect(match.killerInts("lives") == [lives, lives])
            match.play("S11, MISS, MISS |")
            // J1 is a Killer: J2 dies on the `lives`-th hit, not before.
            for hit in 1...lives {
                #expect(match.phase == .throwing)
                if match.snapshot.currentPlayer == 1 { match.play("MISS |") }
                let outcome = match.throwDart(DartRecord(hit: .single(6)))
                #expect(outcome.events.contains(.lifeLost(player: 1, by: 0, livesLeft: lives - hit)))
                #expect(match.fact(1, "lives") == .int(lives - hit))
                if match.phase == .turnComplete { match.endTurn() }
            }
            #expect(match.phase == .finished && match.snapshot.finishReason == .lastPlayerStanding)
            match.killerExpectInvariants(width: 1, lives: lives, armingHits: 1)
        }
    }

    @Test func armingHits_fromOneToFive() throws {
        for armingHits in 1...5 {
            var match = try registry.match(.killer, ["level": "hard", "armingHits": .int(armingHits)], players: 2, seed: 1)
            for hit in 1...armingHits {
                #expect(match.fact(0, "isKiller") == false)
                // An opponent's zone does nothing while the player is not armed.
                if match.snapshot.turn.darts.count == 2 { match.play("MISS | MISS |") }
                #expect(match.throwDart(DartRecord(hit: .double(6))).events.contains(.noEffect(player: 0)))
                var expected: [GameEvent] = [.dartRegistered(player: 0, hit: .treble(11)), .armingHit(player: 0, progress: hit)]
                if hit == armingHits { expected.append(.becameKiller(player: 0)) }
                let events = match.throwDart(DartRecord(hit: .treble(11))).events
                #expect(Array(events.prefix(expected.count)) == expected)
                #expect(match.fact(0, "armingProgress") == .int(hit))
                #expect(match.snapshot.players[0].meter == (hit == armingHits ? nil : Meter(value: hit, maximum: armingHits, style: .pips)))
                if match.phase == .turnComplete { match.play("| MISS |") }
            }
            #expect(match.fact(0, "isKiller") == true)
            match.killerExpectInvariants(width: 1, lives: 3, armingHits: armingHits)
        }
    }

    @Test func optionsOutOfRange_areRefusedByTheSchema() {
        let refused: [(String, OptionValue)] = [
            ("lives", 0), ("lives", 10), ("lives", "3"), ("armingHits", 0), ("armingHits", 6), ("armingHits", .null),
            ("maxRounds", 0), ("maxRounds", 100), ("maxRounds", true), ("selfHitPenalty", 1), ("level", "pro"), ("level", 3),
        ]
        for (key, value) in refused {
            #expect(throws: GameConfigurationError.invalidOptionValue(key: key), "\(key): \(value)") {
                try registry.match(.killer, GameOptions([key: value]), players: 2)
            }
        }
        #expect(throws: GameConfigurationError.unknownOption(key: "zones")) {
            try registry.match(.killer, ["zones": 2], players: 2)
        }
    }

    // MARK: Round limit (GAMES.md §2.6, §5.6)

    @Test func roundLimit_defaultFifteen_isEvaluatedAtTheConfirmation() throws {
        var match = try registry.match(.killer, ["level": "hard"], players: 2, seed: 1)
        for _ in 0..<29 { match.endTurn() }
        #expect(match.snapshot.round == 15 && match.snapshot.currentPlayer == 1 && match.phase == .throwing)
        // The last dart of the last round leaves the game in `turnComplete`: there is time for a correction.
        match.play("MISS, S11, S20")
        #expect(match.phase == .turnComplete && match.snapshot.finishReason == nil)
        #expect(match.endTurn().events == [.gameFinished(reason: .roundLimit)])
        #expect(match.phase == .finished && match.snapshot.finishReason == .roundLimit)
        // Nobody did anything: everybody is first.
        #expect(match.snapshot.ranks == [1, 1] && match.snapshot.winners == [0, 1])
        #expect(match.endTurn() == .rejected(.gameFinished))
        // Undoing the confirmation reopens the last turn with its volley.
        #expect(match.undo().applied)
        #expect(match.phase == .turnComplete && match.turnNotation == ["MISS", "S11", "S20"])
    }

    @Test func roundLimit_none_theGameGoesOn() throws {
        var match = try registry.match(.killer, ["level": "expert", "maxRounds": .null], players: 3, seed: 5)
        #expect(match.snapshot.roundLimit == nil)
        for _ in 0..<(3 * 60) { match.endTurn() }
        #expect(match.snapshot.round == 61 && match.phase == .throwing)
        match.killerExpectInvariants(width: 1, lives: 3, armingHits: 3)
    }

    @Test func roundLimit_oneRound() throws {
        var match = try registry.match(.killer, ["level": "medium", "maxRounds": 1], players: 3, seed: 4)
        match.play("MISS | MISS |")
        #expect(match.phase == .throwing && match.snapshot.currentPlayer == 2)
        match.killerThrow(at: 2, number: 1)
        #expect(match.endTurn().events == [.turnCompleted(player: 2), .gameFinished(reason: .roundLimit)])
        // One arming hit is enough to be alone in front.
        #expect(match.snapshot.ranks == [2, 2, 1])
    }

    // MARK: Whole games

    /// A simple strategy played to the end, at every level and for every number of players: each player arms on
    /// their own zone, then shoots the first opponent alive. Exactly one player survives.
    @Test(arguments: levels)
    private func wholeGame_everyNumberOfPlayers_endsWithOneSurvivor(level: LevelCase) throws {
        for players in level.players {
            for seed in UInt64(11)..<14 {
                var match = try registry.match(.killer, options(level, ["maxRounds": .null]), players: players, seed: seed)
                var eliminationOrder: [PlayerIndex] = []
                var inputs = 0
                while match.phase != .finished && inputs < 5_000 {
                    inputs += 1
                    let outcome: InputOutcome
                    if match.phase == .turnComplete {
                        outcome = match.endTurn()
                    } else {
                        let current = match.snapshot.currentPlayer
                        var target = current
                        if match.killerBools("isKiller")[current] {
                            target = match.killerAlive.first(where: { $0 != current }) ?? current
                        }
                        outcome = match.killerThrow(at: target, number: level.width - 1)[0]
                    }
                    #expect(outcome.isAccepted)
                    for event in outcome.events {
                        if case .playerEliminated(let player, let by) = event {
                            eliminationOrder.append(player)
                            #expect(by == match.snapshot.currentPlayer)
                        }
                    }
                    match.killerExpectInvariants(width: level.width, lives: 3, armingHits: 3)
                }
                let label = "\(level.name), \(players) players, seed \(seed)"
                #expect(match.phase == .finished && match.snapshot.finishReason == .lastPlayerStanding, "\(label)")
                #expect(match.killerAlive.count == 1 && eliminationOrder.count == players - 1, "\(label)")
                #expect(match.killerInts("kills").reduce(0, +) == players - 1, "\(label)")
                // The survivor is first; the others follow in the reverse order of their elimination.
                var expected = Array(repeating: 1, count: players)
                for (position, player) in eliminationOrder.enumerated() {
                    expected[player] = players - position
                }
                #expect(match.snapshot.ranks == expected, "\(label)")
                #expect(match.snapshot.winners == match.killerAlive)
                #expect(match.snapshot.outcome != nil && match.snapshot.highlights.isEmpty)
                // The game ended on a dart: the winning volley is kept, and nothing more is accepted.
                #expect(!match.snapshot.turn.darts.isEmpty)
                #expect(match.throwDart(DartRecord(hit: .miss)) == .rejected(.gameFinished))
                #expect(try registry.restoreMatch(match.record).snapshot == match.snapshot, "\(label)")
            }
        }
    }
}
