import Testing
import DartCore
import DartGames
import DartTestSupport

/// X01 (GAMES.md §3): the vectors X01-1 to X01-5 of §3.9, then every rule paragraph that no vector covers.
/// The common vectors COM-1 to COM-7, which also play X01, are in `Common/CommonVectorTests.swift`.
@Suite struct X01Tests {
    private let registry = GameRegistry.standard

    /// Zones highlighted with the role `target`, in the order of the snapshot.
    private func targets(_ match: GameMatch) -> [BoardZone] {
        match.snapshot.highlights.filter { $0.role == .target }.map(\.zone)
    }

    /// A one-player game brought to `remaining` at the start of a fresh turn, without a bust on the way.
    private func game(at remaining: Int, _ options: GameOptions = [:]) throws -> GameMatch {
        var match = try registry.match(.x01, options, players: 1)
        let start = try #require(match.fact(0, "remaining"))
        guard case .int(var left) = start else {
            Issue.record("remaining is not an integer")
            return match
        }
        var inTurn = 0
        while left > remaining {
            let gap = left - remaining
            let hit: Hit = gap >= 60 ? .treble(20) : (gap > 20 ? .single(20) : .single(gap))
            #expect(match.throwDart(DartRecord(hit: hit)).isAccepted)
            left -= hit.points
            inTurn += 1
            if inTurn == 3 {
                match.endTurn()
                inTurn = 0
            }
        }
        if inTurn > 0 { match.endTurn() }
        #expect(match.fact(0, "remaining") == .int(remaining) && match.phase == .throwing && match.turnNotation.isEmpty)
        return match
    }

    // MARK: Vectors (GAMES.md §3.9)

    @Test func x01_1_oneEightyThenStraightFinish() throws {
        var match = try registry.match(.x01, ["startScore": 301], players: 1)
        var outcomes = match.play("T20, T20, T20")
        #expect(match.phase == .turnComplete && match.fact(0, "remaining") == 121)
        #expect(outcomes[2].events == [.dartRegistered(player: 0, hit: .treble(20)), .turnScored(player: 0, points: 180),
                                       .oneEighty(player: 0), .turnCompleted(player: 0)])
        outcomes = match.play("| T20, S11, DB")
        #expect(match.phase == .finished && match.snapshot.finishReason == .victory)
        #expect(match.fact(0, "remaining") == 0 && match.fact(0, "dartsThrown") == 6 && match.snapshot.ranks == [1])
        #expect(outcomes.last?.events == [.dartRegistered(player: 0, hit: .innerBull),
                                          .checkout(player: 0, points: 121, darts: 3), .gameFinished(reason: .victory)])
    }

    /// One continuation of X01-2, played from 10 left in double out.
    struct DoubleOutCase: Sendable, CustomTestStringConvertible {
        var name: String
        var script: String
        /// Bust reason of the last dart, nil when it wins.
        var bust: BustReason?
        var dartsThrown: Int

        var testDescription: String { "suite \(name): \(script)" }
    }

    @Test(arguments: [
        DoubleOutCase(name: "a", script: "S15", bust: .belowZero, dartsThrown: 7),
        DoubleOutCase(name: "b", script: "S10", bust: .notADouble, dartsThrown: 7),
        DoubleOutCase(name: "c", script: "S9", bust: .oneLeft, dartsThrown: 7),
        DoubleOutCase(name: "d", script: "D5", bust: nil, dartsThrown: 7),
        DoubleOutCase(name: "e", script: "S2, D4", bust: nil, dartsThrown: 8),
        DoubleOutCase(name: "f", script: "S4, S4, S2", bust: .notADouble, dartsThrown: 9),
        DoubleOutCase(name: "g", script: "S4, S4, D1", bust: nil, dartsThrown: 9),
    ])
    func x01_2_doubleOutFromTen(_ suite: DoubleOutCase) throws {
        var match = try registry.match(.x01, ["startScore": 301, "outRule": "double"], players: 1)
        match.play("T20, T20, T20 | T20, T17, MISS |")
        #expect(match.phase == .throwing && match.snapshot.round == 3)
        #expect(match.fact(0, "remaining") == 10 && match.fact(0, "dartsThrown") == 6)
        #expect(targets(match) == [.double(5)])

        let outcomes = match.play(suite.script)
        let last = try #require(outcomes.last)
        let lastHit = try #require(match.currentTurn.last?.hit)
        #expect(match.fact(0, "dartsThrown") == .int(suite.dartsThrown))
        if let reason = suite.bust {
            #expect(last.events == [.dartRegistered(player: 0, hit: lastHit), .bust(player: 0, reason: reason),
                                    .turnCompleted(player: 0)])
            #expect(match.phase == .turnComplete && match.fact(0, "remaining") == 10 && match.fact(0, "busts") == 1)
            // After a, b, c or f: D5 is refused until `endTurn` is received.
            let before = match.snapshot
            #expect(match.throwDart(DartRecord(hit: .double(5))) == .rejected(.turnComplete))
            #expect(match.snapshot == before)
            #expect(match.endTurn().isAccepted)
            #expect(match.throwDart(DartRecord(hit: .double(5))).isAccepted)
            #expect(match.phase == .finished && match.fact(0, "remaining") == 0)
        } else {
            #expect(match.phase == .finished && match.snapshot.finishReason == .victory)
            #expect(match.fact(0, "remaining") == 0 && match.fact(0, "busts") == 0)
            #expect(last.events.last == .gameFinished(reason: .victory))
        }
    }

    /// Suite f of X01-2, dart by dart: 6, then 2, then bust(notADouble).
    @Test func x01_2f_theRunningScoreIsRestoredByTheBust() throws {
        var match = try registry.match(.x01, ["startScore": 301, "outRule": "double"], players: 1)
        match.play("T20, T20, T20 | T20, T17, MISS |")
        match.play("S4")
        #expect(match.fact(0, "remaining") == 6 && targets(match) == [.double(3)])
        match.play("S4")
        #expect(match.fact(0, "remaining") == 2 && targets(match) == [.double(1)])
        match.play("S2")
        #expect(match.fact(0, "remaining") == 10 && match.fact(0, "busts") == 1 && match.fact(0, "dartsThrown") == 9)
        // Highlights follow the state after the volley, also in `turnComplete` (GAMES.md §2.9).
        #expect(match.phase == .turnComplete && targets(match) == [.double(5)])
    }

    @Test func x01_3_doubleInAndDoubleOut() throws {
        var match = try registry.match(.x01, ["startScore": 301, "inRule": "double", "outRule": "double"], players: 2)
        #expect(targets(match) == (1...20).map { BoardZone.double($0) } + [.innerBull])
        #expect(match.snapshot.highlights.count == 21)
        #expect(match.fact(0, "isOpen") == false && match.fact(1, "isOpen") == false)
        let outcomes = match.play("S20, T20, D10")
        #expect(match.fact(0, "isOpen") == true && match.fact(0, "remaining") == 281 && match.fact(0, "dartsThrown") == 3)
        #expect(outcomes[0].events == [.dartRegistered(player: 0, hit: .single(20)), .doubleInRequired(player: 0)])
        #expect(outcomes[1].events == [.dartRegistered(player: 0, hit: .treble(20)), .doubleInRequired(player: 0)])
        #expect(outcomes[2].events == [.dartRegistered(player: 0, hit: .double(10)), .doubleInOpened(player: 0),
                                       .turnScored(player: 0, points: 20), .turnCompleted(player: 0)])
        let second = match.play("| MISS, DB, T20")
        #expect(match.fact(1, "isOpen") == true && match.fact(1, "remaining") == 191 && match.phase == .turnComplete)
        // MISS before the opening: nothing but `noEffect`; DB opens and counts 50.
        #expect(second[1].events == [.dartRegistered(player: 1, hit: .miss), .noEffect(player: 1)])
        #expect(second[2].events == [.dartRegistered(player: 1, hit: .innerBull), .doubleInOpened(player: 1)])
        #expect(second[3].events == [.dartRegistered(player: 1, hit: .treble(20)), .turnScored(player: 1, points: 110),
                                     .highTurn(player: 1, points: 110), .turnCompleted(player: 1)])
        // The second player is open and far from a finish: no highlight.
        #expect(match.snapshot.highlights.isEmpty)
    }

    @Test func x01_4_twoPlayerVictoryAndRanking() throws {
        var match = try registry.match(.x01, ["startScore": 301], players: 2)
        match.play("T20, T20, T20 | S20, S1, MISS | T20, S11, DB")
        #expect(match.phase == .finished && match.snapshot.finishReason == .victory)
        #expect(match.fact(0, "remaining") == 0 && match.fact(1, "remaining") == 280)
        #expect(match.snapshot.ranks == [1, 2] && match.snapshot.winners == [0])
        // The game stops at once: the other player does not finish the round (GAMES.md §3.6).
        #expect(match.snapshot.currentPlayer == 0 && match.snapshot.round == 2)
        #expect(match.endTurn() == .rejected(.gameFinished))
        #expect(match.snapshot.highlights.isEmpty)
    }

    @Test func x01_5_finishHighlights() throws {
        var match = try registry.match(.x01, ["startScore": 301], players: 1)
        match.play("T20, T20, T20 | T20, S20, S20 | S1")
        #expect(match.fact(0, "remaining") == 20 && targets(match) == [.single(20), .double(10)])
        #expect(match.snapshot.highlights.allSatisfy { $0.role == .target && $0.owner == nil })

        var doubleOut = try registry.match(.x01, ["startScore": 301, "outRule": "double"], players: 1)
        doubleOut.play("T20, T20, T20 | T20, S20, S20 | S1")
        #expect(doubleOut.fact(0, "remaining") == 20 && targets(doubleOut) == [.double(10)])

        var other = try registry.match(.x01, ["startScore": 301], players: 1)
        other.play("T20, T20, T20 | T20, S1")
        #expect(other.fact(0, "remaining") == 60 && other.phase == .throwing && targets(other) == [.treble(20)])
    }

    // MARK: Options and initial state (GAMES.md §3.2, §3.3)

    @Test(arguments: [301, 501, 701])
    func initialState_everyStartScore(_ startScore: Int) throws {
        for count in [1, 2, 8] {
            let match = try registry.match(.x01, ["startScore": .int(startScore)], players: count)
            #expect(match.snapshot.players.count == count)
            for player in 0..<count {
                #expect(match.fact(player, "remaining") == .int(startScore) && match.fact(player, "isOpen") == true)
                #expect(match.fact(player, "dartsThrown") == 0 && match.fact(player, "busts") == 0)
                #expect(match.snapshot.players[player].facts.count == 4)
            }
            #expect(match.snapshot.ranks == Array(repeating: 1, count: count))
            #expect(match.snapshot.title == LocalizedText(verbatim: "\(startScore)"))
            #expect(match.snapshot.roundLimit == 20 && match.snapshot.facts.isEmpty && match.snapshot.highlights.isEmpty)
        }
    }

    @Test func defaults_are301StraightInStraightOutTwentyRounds() throws {
        let match = try registry.match(.x01, players: 2)
        #expect(match.configuration.options == ["startScore": 301, "inRule": "straight", "outRule": "straight", "maxRounds": 20])
        #expect(match.fact(0, "remaining") == 301 && match.fact(0, "isOpen") == true && match.snapshot.roundLimit == 20)
        #expect(match.snapshot.variant == nil)
    }

    @Test func playerCount_oneToEight() throws {
        for count in 1...8 {
            #expect(try registry.match(.x01, players: count).snapshot.players.count == count)
        }
        #expect(throws: GameConfigurationError.playerCountOutOfRange(allowed: 1...8, actual: 9)) {
            try registry.match(.x01, players: 9)
        }
        #expect(throws: GameConfigurationError.playerCountOutOfRange(allowed: 1...8, actual: 0)) {
            try registry.match(.x01, players: 0)
        }
    }

    @Test func invalidOptions_areRefusedAtCreation() {
        #expect(throws: GameConfigurationError.invalidOptionValue(key: "startScore")) {
            try registry.match(.x01, ["startScore": 401], players: 1)
        }
        #expect(throws: GameConfigurationError.invalidOptionValue(key: "inRule")) {
            try registry.match(.x01, ["inRule": "master"], players: 1)
        }
        #expect(throws: GameConfigurationError.invalidOptionValue(key: "outRule")) {
            try registry.match(.x01, ["outRule": true], players: 1)
        }
        #expect(throws: GameConfigurationError.invalidOptionValue(key: "maxRounds")) {
            try registry.match(.x01, ["maxRounds": 0], players: 1)
        }
        #expect(throws: GameConfigurationError.invalidOptionValue(key: "maxRounds")) {
            try registry.match(.x01, ["maxRounds": 100], players: 1)
        }
    }

    /// The rule type itself, created without the kernel: missing options take their defaults, an unreadable
    /// value is refused instead of being replaced silently (ARCHITECTURE.md §4.4).
    @Test func rules_createdDirectly_completeTheDefaultsAndRefuseUnreadableValues() throws {
        var random = SeededRandom(seed: 7)
        let bare = GameConfiguration(gameID: .x01, players: testPlayers(2), seed: 7)
        let rules = try X01Rules(configuration: bare, random: &random)
        #expect(rules.roundLimit == 20 && rules.ranks() == [1, 1])
        #expect(!rules.isEliminated(0) && !rules.isEliminated(1))
        // X01 draws nothing.
        #expect(random == SeededRandom(seed: 7))
        let odd = GameConfiguration(gameID: .x01, options: ["startScore": 170], players: testPlayers(1), seed: 0)
        #expect(throws: GameConfigurationError.invalidOptionValue(key: "startScore")) {
            _ = try X01Rules(configuration: odd, random: &random)
        }
        let unlimited = GameConfiguration(gameID: .x01, options: ["maxRounds": .null], players: testPlayers(1), seed: 0)
        #expect(try X01Rules(configuration: unlimited, random: &random).roundLimit == nil)
        for count in [0, 9] {
            let crowd = GameConfiguration(gameID: .x01, players: testPlayers(count), seed: 0)
            #expect(throws: GameConfigurationError.playerCountOutOfRange(allowed: 1...8, actual: count)) {
                _ = try X01Rules(configuration: crowd, random: &random)
            }
        }
    }

    // MARK: Effect of a dart (GAMES.md §3.4)

    @Test func everyBed_subtractsItsPoints() throws {
        for hit in Hit.all where !hit.isMiss {
            var match = try registry.match(.x01, ["startScore": 701], players: 1)
            let outcome = match.throwDart(DartRecord(hit: hit))
            #expect(outcome.events == [.dartRegistered(player: 0, hit: hit)], "\(hit)")
            #expect(match.fact(0, "remaining") == .int(701 - hit.points), "\(hit)")
            #expect(match.fact(0, "dartsThrown") == 1 && match.phase == .throwing)
        }
        var match = try registry.match(.x01, ["startScore": 701], players: 1)
        #expect(match.play("MISS")[0].events == [.dartRegistered(player: 0, hit: .miss), .noEffect(player: 0)])
        #expect(match.fact(0, "remaining") == 701 && match.fact(0, "dartsThrown") == 1)
    }

    @Test func straightOut_anyBedFinishes_andOneLeftIsNotABust() throws {
        // 3 left, straight out: S3 and T1 both finish; S2 leaves 1, which S1 then finishes.
        for script in ["S3", "T1", "S2, S1", "S1, D1", "S1, S1, S1"] {
            var match = try game(at: 3)
            #expect(targets(match) == [.single(3), .treble(1)])
            let outcomes = match.play(script)
            #expect(match.phase == .finished && match.snapshot.finishReason == .victory, "\(script)")
            #expect(match.fact(0, "remaining") == 0 && match.fact(0, "busts") == 0, "\(script)")
            #expect(outcomes.allSatisfy { !$0.events.contains(.bust(player: 0, reason: .oneLeft)) })
        }
        // Below zero is a bust in straight out too.
        var match = try game(at: 3)
        let outcome = match.play("S4")[0]
        #expect(outcome.events == [.dartRegistered(player: 0, hit: .single(4)), .bust(player: 0, reason: .belowZero),
                                   .turnCompleted(player: 0)])
        #expect(match.fact(0, "remaining") == 3 && match.fact(0, "busts") == 1 && match.phase == .turnComplete)
    }

    @Test func straightOut_bullHighlights() throws {
        #expect(targets(try game(at: 25)) == [.outerBull])
        #expect(targets(try game(at: 50)) == [.innerBull])
        #expect(targets(try game(at: 40)) == [.double(20)])
        #expect(targets(try game(at: 12)) == [.single(12), .double(6), .treble(4)])
        #expect(targets(try game(at: 61)).isEmpty)
        // Double out: only the doubles; 25 and odd numbers have no direct finish.
        #expect(targets(try game(at: 50, ["outRule": "double"])) == [.innerBull])
        #expect(targets(try game(at: 25, ["outRule": "double"])).isEmpty)
        #expect(targets(try game(at: 12, ["outRule": "double"])) == [.double(6)])
        #expect(targets(try game(at: 2, ["outRule": "double"])) == [.double(1)])
        #expect(targets(try game(at: 3, ["outRule": "double"])).isEmpty)
    }

    @Test func doubleOut_innerBullIsADouble_outerBullIsNot() throws {
        var bull = try game(at: 50, ["outRule": "double"])
        let win = bull.play("DB")[0]
        #expect(win.events == [.dartRegistered(player: 0, hit: .innerBull), .checkout(player: 0, points: 50, darts: 1),
                               .gameFinished(reason: .victory)])
        #expect(bull.phase == .finished && bull.fact(0, "remaining") == 0)

        var outer = try game(at: 25, ["outRule": "double"])
        #expect(outer.play("SB")[0].events.contains(.bust(player: 0, reason: .notADouble)))
        #expect(outer.fact(0, "remaining") == 25 && outer.phase == .turnComplete)

        var treble = try game(at: 60, ["outRule": "double"])
        #expect(treble.play("T20")[0].events.contains(.bust(player: 0, reason: .notADouble)))
        var single = try game(at: 20, ["outRule": "double"])
        #expect(single.play("S20")[0].events.contains(.bust(player: 0, reason: .notADouble)))
    }

    @Test func doubleOut_oneLeftIsABust_evenOnADouble() throws {
        // 41 left: D20 leaves 1.
        var match = try game(at: 41, ["outRule": "double"])
        let outcome = match.play("D20")[0]
        #expect(outcome.events == [.dartRegistered(player: 0, hit: .double(20)), .bust(player: 0, reason: .oneLeft),
                                   .turnCompleted(player: 0)])
        #expect(match.fact(0, "remaining") == 41)
        // The cases are evaluated in order: below zero wins over the others.
        var below = try game(at: 41, ["outRule": "double"])
        #expect(below.play("T20")[0].events.contains(.bust(player: 0, reason: .belowZero)))
        // Two left is fine.
        var two = try game(at: 41, ["outRule": "double"])
        #expect(two.play("T13")[0].events == [.dartRegistered(player: 0, hit: .treble(13))])
        #expect(two.fact(0, "remaining") == 2 && two.phase == .throwing)
    }

    // MARK: Bust (GAMES.md §3.5)

    @Test func bust_onTheSecondOrThirdDart_restoresTheScoreOfTheStartOfTheTurn() throws {
        var match = try registry.match(.x01, ["startScore": 301], players: 2)
        match.play("T20, T20, T20 | T20, T20, T20 | T20, S20")
        #expect(match.fact(0, "remaining") == 41)
        let outcome = match.play("T20")[0]
        #expect(outcome.events == [.dartRegistered(player: 0, hit: .treble(20)), .bust(player: 0, reason: .belowZero),
                                   .turnCompleted(player: 0)])
        #expect(match.fact(0, "remaining") == 121 && match.fact(0, "busts") == 1 && match.fact(0, "dartsThrown") == 6)
        #expect(match.phase == .turnComplete && match.snapshot.currentPlayer == 0)
        // The other player is untouched, and plays next.
        #expect(match.fact(1, "remaining") == 121 && match.fact(1, "busts") == 0)
        let next = match.endTurn()
        #expect(next.events == [.turnStarted(player: 1, round: 2)])
        // Straight out: one left is not a bust, going below zero from there is. The three darts stay counted.
        match.play("T20, T20, S2")
        #expect(match.fact(1, "remaining") == 121 && match.fact(1, "busts") == 1 && match.fact(1, "dartsThrown") == 6)
        match.play("| T20, T20, S1")
        #expect(match.phase == .finished && match.fact(0, "remaining") == 0 && match.fact(0, "busts") == 1)
        #expect(match.snapshot.ranks == [1, 2])
    }

    @Test func bust_emitsNeitherTurnScoredNorOneEighty_andTheNextTurnStartsClean() throws {
        var match = try game(at: 10)
        let events = match.play("T20")[0].events
        #expect(!events.contains { if case .turnScored = $0 { return true } else { return false } })
        #expect(match.snapshot.turn.summary == LocalizedText(verbatim: "BUST"))
        #expect(match.snapshot.players[0].detail == LocalizedText(verbatim: "BUST"))
        let next = match.play("| S5, S3")
        #expect(next[0].events == [.roundStarted(round: match.snapshot.round), .turnStarted(player: 0, round: match.snapshot.round)])
        #expect(match.fact(0, "remaining") == 2 && match.fact(0, "busts") == 1)
        #expect(match.snapshot.turn.summary == LocalizedText(fr: "Volée : 8", en: "Turn: 8"))
        // The line of the scoreboard still tells the last closed turn.
        #expect(match.snapshot.players[0].detail == LocalizedText(verbatim: "BUST"))
        match.play("MISS |")
        #expect(match.snapshot.players[0].detail == LocalizedText(fr: "Dernière volée : 8", en: "Last turn: 8"))
    }

    /// GAMES.md §3.5 restores `isOpen` too, "to stay general": from 301 a player cannot bust in the turn where
    /// he opens (180 points at most in three darts), so the kernel never gets there. The rule is therefore
    /// driven directly, with a volley longer than a real one.
    @Test func bust_restoresTheOpening_whenItHappensInTheTurnThatOpened() throws {
        var random = SeededRandom(seed: 0)
        let configuration = GameConfiguration(gameID: .x01, options: ["inRule": "double"], players: testPlayers(2), seed: 0)
        var rules = try X01Rules(configuration: configuration, random: &random)
        var events: [GameEvent] = []
        var darts: [Hit] = []
        func context() -> TurnContext {
            TurnContext(players: configuration.players, currentPlayer: 0, round: 1, darts: darts, phase: .throwing)
        }
        rules.turnStarted(context(), random: &random, events: &events)
        var verdicts: [DartVerdict] = []
        // 301 − 50 − 4 × 60 = 11: the fifth T20 goes below zero.
        for hit in [Hit.innerBull, .treble(20), .treble(20), .treble(20), .treble(20), .treble(20)] {
            darts.append(hit)
            verdicts.append(rules.dartThrown(hit, context(), random: &random, events: &events))
            if hit == .innerBull {
                #expect(rules.presentation(context()).rows[0].facts["isOpen"] == true)
            }
        }
        #expect(verdicts == Array(repeating: DartVerdict.turnContinues, count: 5) + [.turnClosed])
        #expect(events == [.doubleInOpened(player: 0), .bust(player: 0, reason: .belowZero)])
        let facts = rules.presentation(context()).rows[0].facts
        #expect(facts["remaining"] == 301 && facts["isOpen"] == false && facts["busts"] == 1 && facts["dartsThrown"] == 6)
        // The player has to open again: the 21 doubles are back.
        #expect(rules.presentation(context()).highlights.count == 21)
        rules.turnClosed(context(), events: &events)
        #expect(events.count == 2 && rules.ranks() == [1, 1])
    }

    // MARK: Double in (GAMES.md §3.4)

    @Test func doubleIn_nothingCountsBeforeADouble_andEveryDoubleOpens() throws {
        for hit in Hit.all {
            var match = try registry.match(.x01, ["inRule": "double"], players: 1)
            let outcome = match.throwDart(DartRecord(hit: hit))
            #expect(match.fact(0, "dartsThrown") == 1)
            if hit.isMiss {
                #expect(outcome.events == [.dartRegistered(player: 0, hit: hit), .noEffect(player: 0)])
                #expect(match.fact(0, "isOpen") == false && match.fact(0, "remaining") == 301)
            } else if hit.isDouble {
                #expect(outcome.events == [.dartRegistered(player: 0, hit: hit), .doubleInOpened(player: 0)], "\(hit)")
                #expect(match.fact(0, "isOpen") == true && match.fact(0, "remaining") == .int(301 - hit.points), "\(hit)")
                #expect(match.snapshot.players[0].badges.isEmpty)
            } else {
                #expect(outcome.events == [.dartRegistered(player: 0, hit: hit), .doubleInRequired(player: 0)], "\(hit)")
                #expect(match.fact(0, "isOpen") == false && match.fact(0, "remaining") == 301, "\(hit)")
                #expect(match.snapshot.players[0].badges == [Badge(LocalizedText(fr: "À ouvrir", en: "To open"))])
            }
        }
    }

    @Test func doubleIn_onlyTheSubtractedPointsCountInTheTurnTotal() throws {
        var match = try registry.match(.x01, ["inRule": "double"], players: 2)
        // A whole turn without a double scores 0; the second double is an ordinary dart.
        let closed = match.play("T20, T20, SB")
        #expect(closed[2].events == [.dartRegistered(player: 0, hit: .outerBull), .doubleInRequired(player: 0),
                                     .turnScored(player: 0, points: 0), .turnCompleted(player: 0)])
        let second = match.play("| T20, D20, D20")
        #expect(second[2].events == [.dartRegistered(player: 1, hit: .double(20)), .doubleInOpened(player: 1)])
        #expect(second[3].events == [.dartRegistered(player: 1, hit: .double(20)), .turnScored(player: 1, points: 80),
                                     .turnCompleted(player: 1)])
        #expect(match.fact(1, "remaining") == 221 && match.fact(1, "isOpen") == true)
        // Opening is per player and lasts: player 1 still has to open, player 2 does not open twice.
        #expect(match.fact(0, "isOpen") == false && match.fact(0, "remaining") == 301)
        let third = match.play("| MISS | S20")
        #expect(third.last?.events == [.dartRegistered(player: 1, hit: .single(20))])
        #expect(match.fact(1, "remaining") == 201)
    }

    @Test func doubleIn_straightOut_finishHighlightsOnlyOnceOpen() throws {
        var match = try registry.match(.x01, ["inRule": "double"], players: 1)
        #expect(targets(match).count == 21)
        match.play("D20")
        #expect(targets(match).isEmpty)
    }

    // MARK: Turn (GAMES.md §3.5, §2.10)

    @Test func turnTotals_highTurnBetween100And179_oneEightyAt180() throws {
        let cases: [(script: String, total: Int, extra: GameEvent?)] = [
            ("S20, S20, S20", 60, nil),
            ("T20, S20, S19", 99, nil),
            ("T20, S20, S20", 100, .highTurn(player: 0, points: 100)),
            ("T20, T20, T19", 177, .highTurn(player: 0, points: 177)),
            ("T20, T20, T20", 180, .oneEighty(player: 0)),
            ("MISS, MISS, MISS", 0, nil),
        ]
        for item in cases {
            var match = try registry.match(.x01, ["startScore": 701], players: 1)
            let events = try #require(match.play(item.script).last).events
            var expected: [GameEvent] = [.turnScored(player: 0, points: item.total)]
            if let extra = item.extra { expected.append(extra) }
            expected.append(.turnCompleted(player: 0))
            #expect(Array(events.dropFirst(events.count - expected.count)) == expected, "\(item.script)")
            #expect(match.fact(0, "remaining") == .int(701 - item.total))
        }
    }

    @Test func earlyConfirmation_scoresTheDartsThrown_evenNone() throws {
        var match = try registry.match(.x01, players: 2)
        let empty = match.endTurn()
        #expect(empty.events == [.turnScored(player: 0, points: 0), .turnCompleted(player: 0), .turnStarted(player: 1, round: 1)])
        #expect(match.fact(0, "dartsThrown") == 0 && match.fact(0, "remaining") == 301)
        let short = match.play("T20, T20 |")
        #expect(short[2].events == [.turnScored(player: 1, points: 120), .highTurn(player: 1, points: 120),
                                    .turnCompleted(player: 1), .roundStarted(round: 2), .turnStarted(player: 0, round: 2)])
        #expect(match.fact(1, "dartsThrown") == 2 && match.fact(1, "remaining") == 181)
    }

    @Test func winningDart_reportsTheWinningTurn_andClosesNoTurn() throws {
        var match = try game(at: 100)
        let outcomes = match.play("T20, D20")
        #expect(outcomes[1].events == [.dartRegistered(player: 0, hit: .double(20)), .checkout(player: 0, points: 100, darts: 2),
                                       .gameFinished(reason: .victory)])
        // The winning volley stays, and stays correctable (GAMES.md §2.6).
        #expect(match.turnNotation == ["T20", "D20"] && match.snapshot.turn.darts.count == 2)
        #expect(match.snapshot.players[0].detail == LocalizedText(fr: "Dernière volée : 100", en: "Last turn: 100"))
        #expect(match.replaceDart(at: 1, with: .single(20)).applied)
        #expect(match.phase == .throwing && match.fact(0, "remaining") == 20 && match.snapshot.finishReason == nil)
    }

    // MARK: Round limit and ranking (GAMES.md §3.6)

    @Test func roundLimit_lowestRemainingWins_tiesShareARank() throws {
        var match = try registry.match(.x01, ["maxRounds": 2], players: 4)
        match.play("S20, S20, S20 | T20, MISS, MISS | S1 | MISS ×3 |")
        #expect(match.snapshot.ranks == [1, 1, 3, 4] && match.phase == .throwing && match.snapshot.round == 2)
        match.play("MISS ×3 | MISS ×3 | T20, S20 | T20, T20, T20")
        #expect(match.phase == .turnComplete && match.snapshot.ranks == [3, 3, 2, 1])
        let end = match.endTurn()
        #expect(end.events == [.gameFinished(reason: .roundLimit)])
        #expect(match.phase == .finished && match.snapshot.finishReason == .roundLimit)
        #expect(match.fact(0, "remaining") == 241 && match.fact(1, "remaining") == 241)
        #expect(match.fact(2, "remaining") == 220 && match.fact(3, "remaining") == 121)
        #expect(match.snapshot.ranks == [3, 3, 2, 1] && match.snapshot.winners == [3])
        // A volley emptied by the kernel, with the scratch state of the last turn still in the rule.
        #expect(match.snapshot.turn.darts.isEmpty && match.snapshot.turn.summary == nil && match.snapshot.turn.hint == nil)
        #expect(match.snapshot.highlights.isEmpty)
    }

    @Test func roundLimit_defaultIsTwentyRounds() throws {
        var match = try registry.match(.x01, players: 2)
        for round in 1...20 {
            #expect(match.snapshot.round == round && match.phase == .throwing)
            match.play("MISS | S1 |")
        }
        #expect(match.phase == .finished && match.snapshot.finishReason == .roundLimit && match.snapshot.round == 20)
        #expect(match.snapshot.ranks == [2, 1])
        #expect(match.fact(1, "remaining") == 281 && match.fact(1, "dartsThrown") == 20)
    }

    @Test func noRoundLimit_theGameGoesOnUntilSomeoneFinishes() throws {
        var match = try registry.match(.x01, ["maxRounds": .null], players: 2)
        #expect(match.snapshot.roundLimit == nil)
        for _ in 1...120 { match.play("MISS ×3 |") }
        #expect(match.phase == .throwing && match.snapshot.round == 61 && match.snapshot.finishReason == nil)
    }

    // MARK: Presentation (GAMES.md §3.7, ARCHITECTURE.md §5.6)

    @Test func presentation_titleVariantAndRows() throws {
        var match = try registry.match(.x01, ["startScore": 501, "inRule": "double", "outRule": "double"], players: 2)
        #expect(match.snapshot.title == LocalizedText(verbatim: "501"))
        #expect(match.snapshot.variant == LocalizedText(verbatim: "Double in · Double out"))
        #expect(match.snapshot.objective == nil && match.snapshot.grid == nil && match.snapshot.winnerTitle == nil)
        let row = match.snapshot.players[1]
        #expect(row.player == 1 && row.primary == ScoreValue(501) && row.detail == nil && row.meter == nil && !row.isEliminated)
        #expect(row.badges == [Badge(LocalizedText(fr: "À ouvrir", en: "To open"))])
        #expect(match.snapshot.turn.hint == LocalizedText(fr: "Ouvrir sur un double", en: "Open on a double"))
        match.play("D20, T20, S5")
        #expect(match.snapshot.players[0].primary == ScoreValue(396))
        #expect(match.snapshot.players[0].detail == LocalizedText(fr: "Dernière volée : 105", en: "Last turn: 105"))
        #expect(match.snapshot.players[0].badges.isEmpty)
        #expect(match.snapshot.turn.summary == LocalizedText(fr: "Volée : 105", en: "Turn: 105"))

        #expect(try registry.match(.x01, ["outRule": "double"], players: 1).snapshot.variant == LocalizedText(verbatim: "Double out"))
        #expect(try registry.match(.x01, ["inRule": "double"], players: 1).snapshot.variant == LocalizedText(verbatim: "Double in"))
    }

    @Test func presentation_dartCaptions() throws {
        var match = try registry.match(.x01, ["inRule": "double"], players: 1)
        match.play("S20, MISS, D10")
        let captions = match.snapshot.turn.darts.map(\.caption)
        #expect(captions == [DartCaption(LocalizedText(fr: "Double requis", en: "Double needed")),
                             DartCaption(LocalizedText(verbatim: "0")),
                             DartCaption(LocalizedText(verbatim: "20"))])
        var bust = try game(at: 30)
        bust.play("S20, S20")
        #expect(bust.snapshot.turn.darts.map(\.caption) == [DartCaption(LocalizedText(verbatim: "20")),
                                                            DartCaption(LocalizedText(verbatim: "BUST"), tone: .negative)])
        var win = try game(at: 30)
        win.play("S20, S10")
        #expect(win.snapshot.turn.darts.map(\.caption) == [DartCaption(LocalizedText(verbatim: "20")),
                                                           DartCaption(LocalizedText(verbatim: "10"), tone: .positive)])
    }

    @Test func presentation_resultsOfAVictory() throws {
        var match = try registry.match(.x01, players: 2)
        match.play("T20, T20, T20 | S20, S20, S20 | T20, S11")
        // No results sentence before the end.
        #expect(match.snapshot.outcome == nil)
        match.play("DB")
        #expect(match.snapshot.outcome == LocalizedText(fr: "Zéro atteint en 6 fléchettes.", en: "Reached zero in 6 darts."))
        // Average per turn: 3 × (301 − remaining) / dartsThrown (GAMES.md §3.7).
        #expect(match.snapshot.players[0].resultLines == [
            LocalizedText(fr: "Moyenne par volée : 150,5", en: "Average per turn: 150.5"),
            LocalizedText(fr: "6 fléchettes", en: "6 darts"),
        ])
        #expect(match.snapshot.players[1].resultLines == [
            LocalizedText(fr: "Moyenne par volée : 60,0", en: "Average per turn: 60.0"),
            LocalizedText(fr: "3 fléchettes", en: "3 darts"),
        ])
    }

    @Test func presentation_resultsAtTheRoundLimit() throws {
        var match = try registry.match(.x01, ["maxRounds": 1, "outRule": "double"], players: 3)
        match.play("T20, T20, T20 | S20 | D5 |")
        #expect(match.snapshot.outcome == LocalizedText(fr: "Plus petit reste à la limite de manches : 121.",
                                                        en: "Lowest score left at the round limit: 121."))
        var tie = try registry.match(.x01, ["maxRounds": 1], players: 3)
        tie.play("S20 | D10 | MISS |")
        #expect(tie.snapshot.ranks == [1, 1, 3])
        #expect(tie.snapshot.outcome == LocalizedText(fr: "Égalité à la limite de manches : 281 restants.",
                                                      en: "Tied at the round limit with 281 left."))
        // Nobody threw: average 0, and a singular in both languages.
        #expect(tie.snapshot.players[2].resultLines == [
            LocalizedText(fr: "Moyenne par volée : 0,0", en: "Average per turn: 0.0"),
            LocalizedText(fr: "1 fléchette", en: "1 dart"),
        ])
        // The lines of the results screen come with the end of the game, like the results sentence.
        var busted = try game(at: 10, ["maxRounds": 5])
        busted.play("T20 | T20")
        #expect(busted.phase == .turnComplete && busted.snapshot.players[0].resultLines.isEmpty)
        busted.play("|")
        #expect(busted.phase == .finished && busted.fact(0, "dartsThrown") == 9)
        #expect(busted.snapshot.players[0].resultLines.last == LocalizedText(fr: "9 fléchettes · 2 busts", en: "9 darts · 2 busts"))
    }

    /// The average per turn is rounded to the NEAREST tenth: 3 × 100 / 7 = 42.857… shows 42.9, not 42.8.
    @Test func presentation_averageIsRoundedToTheNearestTenth() throws {
        var match = try registry.match(.x01, ["maxRounds": 3], players: 1)
        match.play("T20, S20, S20 | MISS ×3 | MISS |")
        #expect(match.phase == .finished && match.fact(0, "remaining") == 201 && match.fact(0, "dartsThrown") == 7)
        #expect(match.snapshot.players[0].resultLines == [
            LocalizedText(fr: "Moyenne par volée : 42,9", en: "Average per turn: 42.9"),
            LocalizedText(fr: "7 fléchettes", en: "7 darts"),
        ])
        // 3 × 1 / 4 = 0.75: a half tenth goes up.
        var half = try registry.match(.x01, ["maxRounds": 2], players: 1)
        half.play("S1, MISS, MISS | MISS |")
        #expect(half.snapshot.players[0].resultLines.first == LocalizedText(fr: "Moyenne par volée : 0,8", en: "Average per turn: 0.8"))
    }

    // MARK: Finishing advice (ARCHITECTURE.md §5.6: outside the rules)

    @Test func hint_classicFinishes() throws {
        #expect(X01Checkout.route(remaining: 170, darts: 3, doubleOut: true) == [.treble(20), .treble(20), .innerBull])
        #expect(X01Checkout.route(remaining: 100, darts: 3, doubleOut: true) == [.treble(20), .double(20)])
        #expect(X01Checkout.route(remaining: 81, darts: 2, doubleOut: true) == [.treble(19), .double(12)])
        #expect(X01Checkout.route(remaining: 41, darts: 2, doubleOut: true) == [.single(9), .double(16)])
        #expect(X01Checkout.route(remaining: 40, darts: 1, doubleOut: true) == [.double(20)])
        #expect(X01Checkout.route(remaining: 50, darts: 1, doubleOut: true) == [.innerBull])
        #expect(X01Checkout.route(remaining: 180, darts: 3, doubleOut: false) == [.treble(20), .treble(20), .treble(20)])
        #expect(X01Checkout.route(remaining: 20, darts: 3, doubleOut: false) == [.single(20)])
        #expect(X01Checkout.route(remaining: 70, darts: 2, doubleOut: false) == [.treble(20), .single(10)])
        // No finish: bogey numbers, too few darts, nothing left.
        for bogey in [169, 168, 166, 165, 163, 162, 159, 171, 180, 1] {
            #expect(X01Checkout.route(remaining: bogey, darts: 3, doubleOut: true) == nil, "\(bogey)")
        }
        #expect(X01Checkout.route(remaining: 170, darts: 2, doubleOut: true) == nil)
        #expect(X01Checkout.route(remaining: 3, darts: 1, doubleOut: true) == nil)
        #expect(X01Checkout.route(remaining: 179, darts: 3, doubleOut: false) == nil)
        #expect(X01Checkout.route(remaining: 181, darts: 3, doubleOut: false) == nil)
        #expect(X01Checkout.route(remaining: 0, darts: 3, doubleOut: false) == nil)
        #expect(X01Checkout.route(remaining: -5, darts: 3, doubleOut: false) == nil)
        #expect(X01Checkout.route(remaining: 40, darts: 0, doubleOut: true) == nil)
        #expect(X01Checkout.route(remaining: 40, darts: 9, doubleOut: true) == [.double(20)])
    }

    /// Every advice is a real finish with the fewest darts, and an advice exists whenever a finish does:
    /// checked against a brute-force search over every volley of one to three darts.
    @Test(arguments: [false, true])
    func hint_isAlwaysARealFinish_andExistsWheneverOneDoes(_ doubleOut: Bool) {
        let beds = Hit.all.filter { !$0.isMiss }
        let finishers = beds.filter { !doubleOut || $0.isDouble }
        // fewest[r] = smallest number of darts that finishes r.
        var fewest = [Int: Int]()
        for last in finishers {
            fewest[last.points] = 1
        }
        for first in beds {
            for last in finishers where fewest[first.points + last.points] == nil {
                fewest[first.points + last.points] = 2
            }
        }
        for first in beds {
            for second in beds {
                for last in finishers where fewest[first.points + second.points + last.points] == nil {
                    fewest[first.points + second.points + last.points] = 3
                }
            }
        }
        for remaining in 1...200 {
            for darts in 1...3 {
                let route = X01Checkout.route(remaining: remaining, darts: darts, doubleOut: doubleOut)
                guard let needed = fewest[remaining], needed <= darts else {
                    #expect(route == nil, "\(remaining) with \(darts) darts")
                    continue
                }
                guard let route else {
                    Issue.record("no advice for \(remaining) with \(darts) darts")
                    continue
                }
                #expect(route.count == needed, "\(remaining) with \(darts) darts: \(route)")
                #expect(route.map(\.points).reduce(0, +) == remaining, "\(remaining): \(route)")
                #expect(route.allSatisfy { !$0.isMiss })
                #expect(!doubleOut || route.last?.isDouble == true, "\(remaining): \(route)")
            }
        }
    }

    /// Following the advice shown on the play screen wins the game, whatever is left and however many darts remain.
    @Test(arguments: [false, true])
    func hint_followedDartByDart_winsTheGame(_ doubleOut: Bool) throws {
        let options: GameOptions = ["outRule": doubleOut ? "double" : "straight"]
        var advised = 0
        // One left cannot be reached in double out: it is a bust.
        for remaining in (doubleOut ? 2 : 1)...181 {
            for thrown in 0...2 {
                var match = try game(at: remaining, options)
                for _ in 0..<thrown { match.play("MISS") }
                let route = X01Checkout.route(remaining: remaining, darts: 3 - thrown, doubleOut: doubleOut)
                guard let route else {
                    #expect(match.snapshot.turn.hint == nil, "\(remaining) after \(thrown) darts")
                    continue
                }
                advised += 1
                let notation = route.map(\.notation).joined(separator: " ")
                #expect(match.snapshot.turn.hint == LocalizedText(fr: "Pour finir : \(notation)", en: "To finish: \(notation)"))
                for (index, hit) in route.enumerated() {
                    #expect(match.phase == .throwing)
                    let outcome = match.throwDart(DartRecord(hit: hit))
                    #expect(outcome.isAccepted)
                    if index < route.count - 1 {
                        // The advice shrinks as the darts land.
                        let rest = route.dropFirst(index + 1).map(\.notation).joined(separator: " ")
                        #expect(match.snapshot.turn.hint == LocalizedText(fr: "Pour finir : \(rest)", en: "To finish: \(rest)"))
                    }
                }
                #expect(match.phase == .finished && match.snapshot.finishReason == .victory, "\(remaining): \(route)")
                #expect(match.snapshot.turn.hint == nil)
            }
        }
        #expect(advised > 250)
    }

    @Test func hint_onlyWhileThrowing() throws {
        var match = try game(at: 40, ["outRule": "double"])
        #expect(match.snapshot.turn.hint == LocalizedText(fr: "Pour finir : D20", en: "To finish: D20"))
        match.play("S10, S10, S10")
        // 10 left, turn closed: the advice comes back with the next turn.
        #expect(match.phase == .turnComplete && match.snapshot.turn.hint == nil)
        match.endTurn()
        #expect(match.snapshot.turn.hint == LocalizedText(fr: "Pour finir : D5", en: "To finish: D5"))
        // Far from a finish: nothing.
        #expect(try registry.match(.x01, players: 1).snapshot.turn.hint == nil)
    }

    // MARK: Same bed, same effect (GAMES.md §2.2, ARCHITECTURE.md §4.8)

    @Test func effectKey_beforeTheOpeningEveryNonDoubleIsTheSame() throws {
        let match = try registry.match(.x01, ["inRule": "double"], players: 2)
        #expect(match.effectKey(for: .single(5)) == match.effectKey(for: .treble(6)))
        #expect(match.effectKey(for: .single(5)) == match.effectKey(for: .outerBull))
        #expect(match.effectKey(for: .single(5)) != match.effectKey(for: .miss))
        #expect(match.effectKey(for: .double(5)) != match.effectKey(for: .double(6)))
        // Once open, two beds worth the same points have the same effect, unless the out rule tells them apart.
        var open = try registry.match(.x01, players: 1)
        #expect(open.effectKey(for: .single(20)) == open.effectKey(for: .double(10)))
        #expect(open.effectKey(for: .single(20)) != open.effectKey(for: .single(19)))
        open = try game(at: 20, ["outRule": "double"])
        #expect(open.effectKey(for: .single(20)) != open.effectKey(for: .double(10)))
        // The recorded position is never read (GAMES.md §2.13).
        #expect(open.effectKey(for: .single(5), position: BoardPoint(x: 120, y: -3)) == open.effectKey(for: .single(5)))
    }

    @Test func position_changesNothing() throws {
        var plain = try registry.match(.x01, ["inRule": "double", "outRule": "double"], players: 2)
        var placed = try registry.match(.x01, ["inRule": "double", "outRule": "double"], players: 2)
        let script: [Hit?] = [.double(20), .treble(20), .treble(20), nil, .single(1), .innerBull, .miss, nil, .treble(20)]
        for (index, hit) in script.enumerated() {
            guard let hit else {
                #expect(plain.endTurn() == placed.endTurn())
                continue
            }
            let position = BoardPoint(x: Double(index) * 17.5 - 60, y: index % 2 == 0 ? .nan : -200)
            #expect(plain.throwDart(DartRecord(hit: hit)) == placed.throwDart(DartRecord(hit: hit, position: position)))
            #expect(plain.snapshot == placed.snapshot)
        }
    }

    // MARK: Undo and corrections replay the journal (GAMES.md §2.5)

    @Test func undoAndCorrections_rebuildTheSameState() throws {
        var match = try registry.match(.x01, ["inRule": "double", "outRule": "double", "maxRounds": 3], players: 2)
        var history = [match.snapshot]
        for outcome in match.play("S20, D20, T20 | D1, MISS | T20, T20, T20 | S20, S20, T20 | S5, S6") {
            #expect(outcome.isAccepted)
        }
        // Rebuild the history input by input on a second match.
        var replayed = try registry.match(.x01, ["inRule": "double", "outRule": "double", "maxRounds": 3], players: 2)
        for entry in match.entries {
            switch entry {
            case .dart(let record): replayed.throwDart(record)
            case .endTurn: replayed.endTurn()
            }
            history.append(replayed.snapshot)
        }
        #expect(replayed.snapshot == match.snapshot)
        // A correction in the current turn, then its inverse: the state comes back.
        let before = match.snapshot
        #expect(match.fact(0, "remaining") == 10 && match.phase == .throwing)
        #expect(match.replaceDart(at: 0, with: .single(1)).applied)
        #expect(match.snapshot != before && match.fact(0, "remaining") == 14)
        #expect(match.replaceDart(at: 0, with: .single(5)).applied)
        #expect(match.snapshot == before)
        // Undo walks the history backwards, down to the initial state.
        var index = history.count - 1
        while match.canUndo {
            #expect(match.snapshot == history[index])
            match.undo()
            index -= 1
        }
        #expect(index == 0 && match.snapshot == history[0])
    }
}
