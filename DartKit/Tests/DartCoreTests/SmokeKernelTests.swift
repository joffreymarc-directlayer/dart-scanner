import Foundation
import Testing
import DartCore
import DartTestSupport

/// The turn kernel `TurnBasedEngine` (GAMES.md §2.4 to §2.10, ARCHITECTURE.md §4.7), driven by fixture rules.
@Suite struct SmokeKernelTests {
    private let registry = SmokeFixtures.registry

    private func elim(players: Int, _ options: GameOptions = [:]) throws -> GameMatch {
        try registry.match(SmokeElimRules.id, options, players: players)
    }

    private func x01Engine(players: Int, _ options: GameOptions = [:]) throws -> TurnBasedEngine<SmokeX01Rules> {
        try TurnBasedEngine<SmokeX01Rules>(configuration: GameConfiguration(gameID: .x01, options: options,
                                                                            players: testPlayers(players), seed: 0))
    }

    // MARK: Creation

    @Test func creation_initialState() throws {
        let engine = try x01Engine(players: 3, ["outRule": "double"])
        #expect(engine.phase == .throwing && engine.currentPlayer == 0 && engine.round == 1)
        #expect(engine.darts.isEmpty && engine.positions.isEmpty && engine.finishReason == nil)
        let snapshot = engine.snapshot
        #expect(snapshot.gameID == .x01 && snapshot.phase == .throwing && snapshot.currentPlayer == 0 && snapshot.round == 1)
        #expect(snapshot.turn.darts.isEmpty && snapshot.turn.capacity == 3 && dartsPerTurn == 3)
        #expect(snapshot.roundLimit == 20 && snapshot.finishReason == nil)
        #expect(snapshot.players.count == 3 && snapshot.ranks == [1, 1, 1])
        // The configuration is kept with the options completed by their defaults.
        #expect(engine.configuration.options == ["startScore": 301, "inRule": "straight", "outRule": "double", "maxRounds": 20])
        #expect(engine.configuration.players == testPlayers(3) && engine.configuration.seed == 0)
    }

    @Test func creation_refusesAnInvalidConfiguration() throws {
        // Another game's configuration.
        #expect(throws: GameConfigurationError.unknownGame(.cricket)) {
            try TurnBasedEngine<SmokeX01Rules>(configuration: GameConfiguration(gameID: .cricket, players: testPlayers(2), seed: 0))
        }
        // The first issue of the schema is thrown: the player count comes before the options.
        #expect(throws: GameConfigurationError.playerCountOutOfRange(allowed: 1...8, actual: 9)) {
            try x01Engine(players: 9, ["startScore": 302])
        }
        #expect(throws: GameConfigurationError.invalidOptionValue(key: "startScore")) {
            try x01Engine(players: 2, ["startScore": 302])
        }
        #expect(throws: GameConfigurationError.unknownOption(key: "legs")) {
            try x01Engine(players: 2, ["legs": 3])
        }
        #expect(throws: GameConfigurationError.playerCountOutOfRange(allowed: 2...4, actual: 1)) {
            try elim(players: 1)
        }
        // An error thrown by the rule itself goes through unchanged.
        #expect(throws: GameConfigurationError.invalidOptionValue(key: "broken")) {
            try registry.match(SmokeBrokenRules.id, players: 1)
        }
        // A game that the registry does not know, and a definition asked for another game.
        #expect(throws: GameConfigurationError.unknownGame(.golf)) {
            try registry.match(.golf, players: 1)
        }
        let definition = try #require(registry.definition(for: .x01))
        #expect(throws: GameConfigurationError.unknownGame(SmokeElimRules.id)) {
            try definition.makeEngine(GameConfiguration(gameID: SmokeElimRules.id, players: testPlayers(2), seed: 0))
        }
    }

    @Test func creation_callsTurnStartedOnce_forTheFirstTurnOfTheGame() throws {
        var match = try elim(players: 2)
        #expect(match.gameFact("turnStarts") == .table([[1, 0, 1]]))
        match.play("| |")
        // Later calls never have `isFirstTurnOfGame`.
        #expect(match.gameFact("turnStarts") == .table([[1, 0, 1], [1, 1, 0], [2, 0, 0]]))
    }

    // MARK: Phases

    @Test func dartRefusedOnceTheTurnIsComplete_stateUnchanged() throws {
        var engine = try x01Engine(players: 1)
        for _ in 0..<3 { #expect(engine.apply(.dart(.treble(20))).isAccepted) }
        #expect(engine.phase == .turnComplete)
        let before = engine.snapshot
        let outcome = engine.apply(.dart(.single(20)))
        #expect(outcome == .rejected(.turnComplete))
        #expect(!outcome.isAccepted && outcome.events.isEmpty)
        #expect(engine.snapshot == before && engine.darts == [.treble(20), .treble(20), .treble(20)])
        // `endTurn` is still accepted.
        #expect(engine.apply(.endTurn).isAccepted && engine.phase == .throwing)
    }

    @Test func everyInputRefusedOnceTheGameIsFinished() throws {
        var engine = try x01Engine(players: 1)
        for input in [GameInput.dart(.treble(20)), .dart(.treble(20)), .dart(.treble(20)), .endTurn,
                      .dart(.treble(20)), .dart(.single(11)), .dart(.innerBull)] {
            #expect(engine.apply(input).isAccepted)
        }
        #expect(engine.phase == .finished && engine.finishReason == .victory)
        let before = engine.snapshot
        #expect(engine.apply(.dart(.single(1))) == .rejected(.gameFinished))
        #expect(engine.apply(.endTurn) == .rejected(.gameFinished))
        #expect(engine.apply(.dart(.miss), position: BoardPoint(x: 1, y: 2)) == .rejected(.gameFinished))
        #expect(engine.snapshot == before)
    }

    // MARK: Turn close

    @Test func thirdDartClosesTheTurn_exactlyOnce() throws {
        var match = try elim(players: 3)
        let outcomes = match.play("MISS, MISS, MISS")
        #expect(outcomes[0].events == [.dartRegistered(player: 0, hit: .miss), .noEffect(player: 0)])
        #expect(outcomes[1].events == [.dartRegistered(player: 0, hit: .miss), .noEffect(player: 0)])
        // Closing effects of the rule, then `turnCompleted`.
        #expect(outcomes[2].events == [.dartRegistered(player: 0, hit: .miss), .noEffect(player: 0),
                                       .turnScored(player: 0, points: 3), .turnCompleted(player: 0)])
        #expect(match.phase == .turnComplete && match.snapshot.currentPlayer == 0)
        // The confirmation does not close the turn a second time.
        let confirmation = match.endTurn()
        #expect(confirmation.events == [.zoneChanged(player: 1, zone: [1]), .turnStarted(player: 1, round: 1)])
        #expect(match.fact(0, "closes") == 1)
    }

    @Test func earlyConfirmation_closesTheTurnFirst_evenWithoutADart() throws {
        var match = try elim(players: 3)
        // No dart at all: the turn is closed, then the next one starts.
        #expect(match.endTurn().events == [.turnScored(player: 0, points: 0), .turnCompleted(player: 0),
                                           .zoneChanged(player: 1, zone: [1]), .turnStarted(player: 1, round: 1)])
        match.play("MISS")
        #expect(match.endTurn().events == [.turnScored(player: 1, points: 1), .turnCompleted(player: 1),
                                           .zoneChanged(player: 2, zone: [1]), .turnStarted(player: 2, round: 1)])
        #expect(match.fact(0, "closes") == 1 && match.fact(1, "closes") == 1 && match.fact(2, "closes") == 0)
        #expect(match.phase == .throwing && match.snapshot.currentPlayer == 2 && match.snapshot.turn.darts.isEmpty)
        // The darts that were not thrown do not exist: they are not logged as MISS.
        #expect(SmokeFixtures.journal(match) == ["|", "MISS", "|"])
    }

    @Test func aRuleCanCloseTheTurn_beforeTheThirdDart() throws {
        var match = try elim(players: 3)
        // Self-elimination: the rule returns `.turnClosed`.
        let outcome = match.throwDart(DartRecord(hit: .single(1)))
        #expect(outcome.events == [.dartRegistered(player: 0, hit: .single(1)),
                                   .lifeLost(player: 0, by: 0, livesLeft: 0), .playerEliminated(player: 0, by: 0),
                                   .turnScored(player: 0, points: 1), .turnCompleted(player: 0)])
        #expect(match.phase == .turnComplete && match.snapshot.turn.darts.count == 1)
        #expect(match.throwDart(DartRecord(hit: .single(2))) == .rejected(.turnComplete))
    }

    // MARK: Next player, rounds

    @Test func eliminatedPlayersAreSkipped_andARoundEndsWhenTheOrderWraps() throws {
        var match = try elim(players: 4)
        #expect(match.throwDart(DartRecord(hit: .single(2))).events == [
            .dartRegistered(player: 0, hit: .single(2)), .lifeLost(player: 1, by: 0, livesLeft: 0),
            .playerEliminated(player: 1, by: 0)])
        // J2 is out: J3 plays next, still in round 1.
        #expect(match.endTurn().events == [.turnScored(player: 0, points: 1), .turnCompleted(player: 0),
                                           .zoneChanged(player: 2, zone: [1]), .turnStarted(player: 2, round: 1)])
        #expect(match.endTurn().events.last == .turnStarted(player: 3, round: 1))
        // J4 to J1: the order wraps, round 2 starts. Order: [close], roundStarted, start-of-turn effects, turnStarted.
        #expect(match.endTurn().events == [.turnScored(player: 3, points: 0), .turnCompleted(player: 3), .roundStarted(round: 2),
                                           .zoneChanged(player: 0, zone: [2]), .turnStarted(player: 0, round: 2)])
        #expect(match.snapshot.round == 2 && match.snapshot.currentPlayer == 0)
        match.play("S4 |")
        #expect(match.snapshot.currentPlayer == 2 && match.snapshot.round == 2)
        // J3 to J1, skipping J4 then J2 backwards over the end of the list: round 3.
        #expect(match.endTurn().events == [.turnScored(player: 2, points: 0), .turnCompleted(player: 2), .roundStarted(round: 3),
                                           .zoneChanged(player: 0, zone: [3]), .turnStarted(player: 0, round: 3)])
        // A player's k-th turn is always in round k.
        #expect(match.gameFact("turnStarts") == .table([[1, 0, 1], [1, 2, 0], [1, 3, 0], [2, 0, 0], [2, 2, 0], [3, 0, 0]]))
        #expect(match.snapshot.players.map(\.isEliminated) == [false, true, false, true])
    }

    @Test func aPlayerEliminatedDuringTheirOwnTurnIsSkippedAfterwards() throws {
        var match = try elim(players: 3)
        match.play("S1 | | |")
        // J1 eliminated themselves in round 1; after J3 the order wraps to J2, not to J1.
        #expect(match.snapshot.currentPlayer == 1 && match.snapshot.round == 2)
        match.play("| |")
        #expect(match.snapshot.currentPlayer == 1 && match.snapshot.round == 3)
    }

    @Test func solo_everyConfirmationStartsARound() throws {
        var engine = try x01Engine(players: 1)
        #expect(engine.apply(.endTurn).events == [.turnScored(player: 0, points: 0), .turnCompleted(player: 0),
                                                  .roundStarted(round: 2), .turnStarted(player: 0, round: 2)])
        #expect(engine.round == 2 && engine.currentPlayer == 0 && engine.phase == .throwing)
        _ = engine.apply(.dart(.single(1)))
        _ = engine.apply(.endTurn)
        #expect(engine.round == 3)
    }

    // MARK: Round limit

    @Test func roundLimit_isEvaluatedOnlyWhenEndTurnIsProcessed() throws {
        var match = try elim(players: 2, ["maxRounds": 1])
        match.play("|")
        let outcomes = match.play("MISS, MISS, MISS")
        #expect(outcomes[2].events.last == .turnCompleted(player: 1))
        // Last dart of the last round: the game waits for the confirmation.
        #expect(match.phase == .turnComplete && match.snapshot.round == 1 && match.snapshot.finishReason == nil)
        #expect(match.snapshot.roundLimit == 1)
        #expect(match.snapshot.highlights == [BoardHighlight(zone: .sector(1), role: .target, owner: 0)])
        // The confirmation ends the game: one event, no `roundStarted`, no `turnStarted`.
        #expect(match.endTurn().events == [.gameFinished(reason: .roundLimit)])
        #expect(match.phase == .finished && match.snapshot.finishReason == .roundLimit)
        #expect(match.snapshot.round == 1 && match.snapshot.currentPlayer == 1)
        // The confirmed turn is over: the volley is empty, as after any other confirmation.
        #expect(match.snapshot.turn.darts.isEmpty && match.currentTurn.isEmpty)
        // Both players are still alive, so the rule still gives a highlight: the kernel clears it.
        #expect(match.snapshot.highlights.isEmpty)
        // The rule's `turnStarted` was not called for a turn that never starts.
        #expect(match.gameFact("turnStarts") == .table([[1, 0, 1], [1, 1, 0]]))
        #expect(match.snapshot.ranks == [1, 1] && match.snapshot.winners == [0, 1])
        #expect(match.endTurn() == .rejected(.gameFinished))
    }

    @Test func roundLimit_onAnEarlyConfirmation_closesTheTurnThenEndsTheGame() throws {
        var match = try elim(players: 2, ["maxRounds": 1])
        match.play("|")
        #expect(match.endTurn().events == [.turnScored(player: 1, points: 0), .turnCompleted(player: 1),
                                           .gameFinished(reason: .roundLimit)])
        #expect(match.phase == .finished)
    }

    /// A game ended at the round limit has an empty volley (GAMES.md §2.4, step 3): the turn that `endTurn`
    /// confirmed is over, and the journal has no dart after that `endTurn` either (GAMES.md §2.5).
    @Test func roundLimit_emptiesTheVolleyAndItsPositions() throws {
        var engine = try TurnBasedEngine<SmokeDiscRules>(configuration: GameConfiguration(
            gameID: SmokeDiscRules.id, options: ["rounds": 1], players: testPlayers(1), seed: 5))
        _ = engine.apply(.dart(.single(1)), position: BoardPoint(x: 500, y: 500))
        _ = engine.apply(.dart(.single(2)))
        _ = engine.apply(.dart(.miss))
        #expect(engine.phase == .turnComplete && engine.darts.count == 3 && engine.positions.count == 3)
        #expect(engine.apply(.endTurn).events == [.gameFinished(reason: .roundLimit)])
        #expect(engine.phase == .finished && engine.finishReason == .roundLimit)
        #expect(engine.darts.isEmpty && engine.positions.isEmpty && engine.snapshot.turn.darts.isEmpty)
        // The player and the round stay those of the last turn: no turn has started.
        #expect(engine.currentPlayer == 0 && engine.round == 1)
        // A game that ends ON a dart keeps its volley: that turn was never confirmed.
        var won = try x01Engine(players: 1)
        for input in [GameInput.dart(.treble(20)), .dart(.treble(20)), .dart(.treble(20)), .endTurn,
                      .dart(.treble(20)), .dart(.single(11)), .dart(.innerBull)] {
            _ = won.apply(input)
        }
        #expect(won.phase == .finished && won.darts == [.treble(20), .single(11), .innerBull])
    }

    @Test func noRoundLimit_theGameGoesOn() throws {
        var match = try elim(players: 2)
        #expect(match.snapshot.roundLimit == nil)
        for _ in 0..<50 { match.play("| |") }
        #expect(match.snapshot.round == 51 && match.phase == .throwing)
    }

    // MARK: End of the game on a dart

    @Test func winningDart_noTurnCompleted_gameFinishedLast() throws {
        var match = try elim(players: 2)
        let outcome = match.throwDart(DartRecord(hit: .single(2)))
        #expect(outcome.events == [.dartRegistered(player: 0, hit: .single(2)), .lifeLost(player: 1, by: 0, livesLeft: 0),
                                   .playerEliminated(player: 1, by: 0), .gameFinished(reason: .lastPlayerStanding)])
        // The game is over at once, without a confirmation, and the turn was never "closed".
        #expect(match.phase == .finished && match.snapshot.finishReason == .lastPlayerStanding)
        #expect(match.fact(0, "closes") == 0)
        #expect(match.snapshot.ranks == [1, 2] && match.snapshot.winners == [0])
        #expect(match.snapshot.turn.darts.map(\.hit) == [.single(2)])
    }

    @Test func victoryOnADart_andRanksOfAnEliminationGame() throws {
        var match = try elim(players: 4)
        match.play("S2 | | | S4 | | S3")
        #expect(match.phase == .finished && match.snapshot.finishReason == .lastPlayerStanding)
        // Eliminated players rank after the players alive, the last eliminated first.
        #expect(match.snapshot.ranks == [1, 4, 2, 3])
        var bull = try elim(players: 2)
        var outcomes = bull.play("MISS")
        #expect(bull.snapshot.highlights == [BoardHighlight(zone: .sector(2), role: .target, owner: 1)])
        outcomes = bull.play("DB")
        #expect(outcomes[0].events == [.dartRegistered(player: 0, hit: .innerBull), .gameFinished(reason: .victory)])
        #expect(bull.snapshot.finishReason == .victory && bull.snapshot.ranks == [1, 2])
        // The opponent is still alive and the rule would still highlight their sector: no highlight once finished.
        #expect(bull.snapshot.highlights.isEmpty)
        bull.undo()
        #expect(bull.snapshot.highlights == [BoardHighlight(zone: .sector(2), role: .target, owner: 1)])
    }

    // MARK: Snapshot

    @Test func finishingBedIsHighlighted_untilTheGameIsFinished() throws {
        var engine = try x01Engine(players: 1)
        for input in [GameInput.dart(.treble(20)), .dart(.treble(20)), .dart(.treble(20)), .endTurn,
                      .dart(.treble(20)), .dart(.single(11))] {
            _ = engine.apply(input)
        }
        // 50 left: the finishing bed is highlighted.
        #expect(engine.snapshot.highlights == [BoardHighlight(zone: .innerBull, role: .target)])
        _ = engine.apply(.dart(.innerBull))
        #expect(engine.phase == .finished && engine.snapshot.highlights.isEmpty)
    }

    @Test func highlightsStayDuringTurnComplete_forTheCurrentPlayer() throws {
        var match = try elim(players: 3)
        match.play("MISS, MISS, MISS")
        #expect(match.phase == .turnComplete)
        #expect(match.snapshot.highlights == [BoardHighlight(zone: .sector(2), role: .target, owner: 1),
                                              BoardHighlight(zone: .sector(3), role: .target, owner: 2)])
        match.play("|")
        #expect(match.snapshot.highlights.map(\.zone) == [.sector(1), .sector(3)])
    }

    @Test func outcomeAndWinnerTitle_onlyComeOutOnceFinished() throws {
        var match = try elim(players: 2)
        // The rule gives both at any time; the kernel holds them back.
        #expect(match.snapshot.outcome == nil && match.snapshot.winnerTitle == nil)
        match.play("MISS, MISS, MISS")
        #expect(match.phase == .turnComplete && match.snapshot.outcome == nil && match.snapshot.winnerTitle == nil)
        match.play("| S1")
        #expect(match.phase == .finished)
        #expect(match.snapshot.outcome == LocalizedText(verbatim: "outcome"))
        #expect(match.snapshot.winnerTitle == LocalizedText(verbatim: "winner title"))
        #expect(match.snapshot.highlights.isEmpty)
        // Undoing the winning dart takes them back.
        match.undo()
        #expect(match.phase == .throwing && match.snapshot.outcome == nil && match.snapshot.winnerTitle == nil)
        #expect(!match.snapshot.highlights.isEmpty)
    }

    @Test func snapshot_ranksAndDartSlotsAreFilledByTheKernel() throws {
        var engine = try x01Engine(players: 2)
        _ = engine.apply(.dart(.treble(20)))
        _ = engine.apply(.dart(.single(5)))
        let snapshot = engine.snapshot
        #expect(snapshot.turn.darts == [DartSlot(hit: .treble(20), caption: DartCaption(LocalizedText(verbatim: "60"))),
                                        DartSlot(hit: .single(5), caption: DartCaption(LocalizedText(verbatim: "5")))])
        #expect(snapshot.turn.summary == LocalizedText(verbatim: "65") && snapshot.turn.hint == nil)
        #expect(snapshot.title == LocalizedText(verbatim: "301"))
        // `rank` of each row is overwritten with `ranks()`.
        #expect(snapshot.ranks == [1, 2] && snapshot.players.map(\.rank) == [1, 2])
        #expect(snapshot.players.map(\.player) == [0, 1])
        // A rule that gives no caption leaves the slots without one.
        var match = try elim(players: 2)
        match.play("MISS")
        #expect(match.snapshot.turn.darts == [DartSlot(hit: .miss)])
    }

    @Test func theEngineIsAValue_aCopyIsAnIndependentGame() throws {
        var engine = try x01Engine(players: 2)
        _ = engine.apply(.dart(.treble(20)))
        var copy = engine
        _ = copy.apply(.dart(.treble(20)))
        _ = copy.apply(.endTurn)
        #expect(engine.darts == [.treble(20)] && engine.currentPlayer == 0)
        #expect(engine.snapshot.players[0].facts["remaining"] == 241)
        #expect(copy.darts.isEmpty && copy.currentPlayer == 1)
        #expect(copy.snapshot.players[0].facts["remaining"] == 181)
    }

    @Test func inputWithoutPosition_isTheSameAsANilPosition() throws {
        var a = try x01Engine(players: 1), b = try x01Engine(players: 1)
        #expect(a.apply(.dart(.treble(19))) == b.apply(.dart(.treble(19)), position: nil))
        #expect(a.snapshot == b.snapshot)
    }

    // MARK: A position-dependent rule: the three moments of a draw

    /// The centres that `SmokeDiscRules` draws from a seed, in order: two values of the generator each.
    private func drawnCentres(seed: UInt64, count: Int) -> [[Int]] {
        var rng = SeededRandom(seed: seed)
        var centres: [[Int]] = []
        for _ in 0..<count {
            let x = rng.nextInt(below: SmokeDiscRules.drawBound) - 1000
            let y = rng.nextInt(below: SmokeDiscRules.drawBound) - 1000
            centres.append([x, y])
        }
        return centres
    }

    private func disc(players: Int, seed: UInt64, _ options: GameOptions = [:]) throws -> GameMatch {
        try registry.match(SmokeDiscRules.id, options, players: players, seed: seed)
    }

    private func millimetres(_ centre: [Int]) -> BoardPoint {
        BoardPoint(x: Double(centre[0]) / 10, y: Double(centre[1]) / 10)
    }

    @Test(arguments: [UInt64(0), 1, 42, 0xDEAD_BEEF])
    func draws_atCreation_comeFromInitOnly(seed: UInt64) throws {
        let centres = drawnCentres(seed: seed, count: 1)
        // With moving targets the rule would draw in `turnStarted`: the creation call must not.
        for options in [GameOptions(), ["moving": true]] {
            let match = try disc(players: 2, seed: seed, options)
            #expect(match.gameFact("disc") == .ints(centres[0]))
            #expect(match.gameFact("draws") == 2)
        }
    }

    @Test func draws_duringADart_replaceTheDestroyedTarget() throws {
        let centres = drawnCentres(seed: 7, count: 3)
        var match = try disc(players: 1, seed: 7)
        let outcome = match.throwDart(DartRecord(hit: .single(20), position: millimetres(centres[0])))
        #expect(outcome.events == [.dartRegistered(player: 0, hit: .single(20)), .blobDestroyed(player: 0, blob: 0, points: 10)])
        #expect(match.gameFact("disc") == .ints(centres[1]) && match.gameFact("draws") == 4)
        #expect(match.fact(0, "points") == 10)
        // The next target comes from the next two values of the same generator.
        match.throwDart(DartRecord(hit: .single(20), position: millimetres(centres[1])))
        #expect(match.gameFact("disc") == .ints(centres[2]) && match.gameFact("draws") == 6)
        #expect(match.fact(0, "points") == 20)
    }

    @Test func draws_atTheStartOfATurn_comeJustBeforeTurnStarted() throws {
        let centres = drawnCentres(seed: 3, count: 3)
        var match = try disc(players: 2, seed: 3, ["moving": true])
        #expect(match.endTurn().events == [.turnScored(player: 0, points: 0), .turnCompleted(player: 0),
                                           .blobsMoved, .turnStarted(player: 1, round: 1)])
        #expect(match.gameFact("disc") == .ints(centres[1]) && match.gameFact("draws") == 4)
        #expect(match.endTurn().events == [.turnScored(player: 1, points: 0), .turnCompleted(player: 1), .roundStarted(round: 2),
                                           .blobsMoved, .turnStarted(player: 0, round: 2)])
        #expect(match.gameFact("disc") == .ints(centres[2]) && match.gameFact("draws") == 6)
        // Without the option nothing is drawn at the start of a turn.
        var still = try disc(players: 2, seed: 3)
        #expect(still.endTurn().events == [.turnScored(player: 0, points: 0), .turnCompleted(player: 0),
                                           .turnStarted(player: 1, round: 1)])
        #expect(still.gameFact("disc") == .ints(centres[0]) && still.gameFact("draws") == 2)
    }

    @Test func noDraw_whenTheConfirmationEndsTheGame() throws {
        var match = try disc(players: 1, seed: 3, ["moving": true, "rounds": 1])
        #expect(match.endTurn().events == [.turnScored(player: 0, points: 0), .turnCompleted(player: 0),
                                           .gameFinished(reason: .roundLimit)])
        #expect(match.gameFact("draws") == 2)
    }

    @Test func aPositionDependentRule_readsTheImpactPoint_notTheHit() throws {
        let centre = drawnCentres(seed: 11, count: 1)[0]
        let inside = millimetres(centre)
        let outside = BoardPoint(x: inside.x + 30.1, y: inside.y)
        let onTheEdge = BoardPoint(x: inside.x + 30.0, y: inside.y)
        func events(_ hit: Hit, _ position: BoardPoint?) throws -> [GameEvent] {
            var match = try disc(players: 1, seed: 11)
            return match.throwDart(DartRecord(hit: hit, position: position)).events
        }
        let destroyed = GameEvent.blobDestroyed(player: 0, blob: 0, points: 10)
        // Rule 2: the recorded position, whatever the hit says.
        for hit in [Hit.single(20), .treble(3), .double(11), .innerBull, .outerBull] {
            #expect(try events(hit, inside) == [.dartRegistered(player: 0, hit: hit), destroyed])
            #expect(try events(hit, onTheEdge) == [.dartRegistered(player: 0, hit: hit), destroyed])
            #expect(try events(hit, outside) == [.dartRegistered(player: 0, hit: hit), .noEffect(player: 0)])
        }
        // Rule 1: MISS touches nothing, even with a position inside the target.
        #expect(try events(.miss, inside) == [.dartRegistered(player: 0, hit: .miss), .noEffect(player: 0)])
        #expect(try events(.miss, nil) == [.dartRegistered(player: 0, hit: .miss), .noEffect(player: 0)])
    }

    @Test func aDartWithoutPosition_usesTheCanonicalPositionOfItsBed() throws {
        var touched = 0, untouched = 0
        for seed in UInt64(0)..<60 {
            let centre = drawnCentres(seed: seed, count: 1)[0]
            for hit in Hit.all {
                var match = try disc(players: 1, seed: seed)
                let events = match.throwDart(DartRecord(hit: hit)).events
                let expected = ImpactPoint.canonical(of: hit).map { SmokeDiscRules.touches($0, x: centre[0], y: centre[1]) } ?? false
                #expect(events.contains(.blobDestroyed(player: 0, blob: 0, points: 10)) == expected, "seed \(seed), \(hit)")
                #expect(events.contains(.noEffect(player: 0)) == !expected)
                if expected { touched += 1 } else { untouched += 1 }
            }
        }
        // The sample exercises both outcomes.
        #expect(touched > 0 && untouched > 0)
    }

    @Test func theKernelKeepsThePositionsOfTheTurn_alignedWithItsDarts() throws {
        var engine = try TurnBasedEngine<SmokeDiscRules>(configuration: GameConfiguration(
            gameID: SmokeDiscRules.id, players: testPlayers(1), seed: 5))
        let recorded = BoardPoint(x: 500, y: 500)
        _ = engine.apply(.dart(.single(1)), position: recorded)
        _ = engine.apply(.dart(.single(2)))
        #expect(engine.darts == [.single(1), .single(2)] && engine.positions == [recorded, nil])
        _ = engine.apply(.endTurn, position: recorded)
        // Darts and positions are emptied when the next turn starts; a position given with `endTurn` is ignored.
        #expect(engine.darts.isEmpty && engine.positions.isEmpty)
    }
}
