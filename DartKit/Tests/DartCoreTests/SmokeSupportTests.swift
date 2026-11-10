import Foundation
import Testing
import DartCore
import DartTestSupport

/// The vector DSL of `DartTestSupport` (ARCHITECTURE.md §12.1, GAMES.md §2.11).
@Suite struct SmokeSupportTests {
    private let registry = SmokeFixtures.registry

    @Test func testPlayers_haveStableIdentifiersAndNames() {
        let players = testPlayers(3)
        #expect(players.map(\.name) == ["J1", "J2", "J3"])
        #expect(players.map(\.id.uuidString) == ["00000000-0000-0000-0000-000000000001", "00000000-0000-0000-0000-000000000002",
                                                 "00000000-0000-0000-0000-000000000003"])
        #expect(testPlayers(3) == players && testPlayers(0).isEmpty)
        #expect(Set(testPlayers(8).map(\.id)).count == 8)
    }

    @Test func match_buildsAGameForAVector() throws {
        let match = try registry.match(.x01, ["outRule": "double"], players: 2, seed: 5)
        #expect(match.configuration.gameID == .x01 && match.configuration.seed == 5)
        #expect(match.players == testPlayers(2))
        #expect(match.configuration.options.string("outRule") == "double")
        // Options and seed are optional: defaults, seed 0.
        let plain = try registry.match(.x01, players: 1)
        #expect(plain.configuration.seed == 0 && plain.configuration.options.int("startScore") == 301)
    }

    @Test func play_readsDartsConfirmationsAndRepetitions() throws {
        var match = try registry.match(.x01, players: 2)
        let outcomes = match.play("T20, S5, MISS | MISS ×3 |")
        // One outcome per input, in order: 3 darts, endTurn, 3 darts, endTurn.
        #expect(outcomes.count == 8 && outcomes.allSatisfy(\.isAccepted))
        #expect(SmokeFixtures.journal(match) == ["T20", "S5", "MISS", "|", "MISS", "MISS", "MISS", "|"])
        #expect(outcomes[3].events.last == .turnStarted(player: 1, round: 1))
        #expect(match.fact(0, "remaining") == 236 && match.fact(1, "dartsThrown") == 3)
        // Notations are read as `Hit(notation:)` reads them; spaces and an empty script are harmless.
        #expect(match.play("").isEmpty && match.play("   ").isEmpty)
        match.play("t20,d16 , 25")
        #expect(match.turnNotation == ["T20", "D16", "SB"])
        // A refused input is reported in its place, and is not logged.
        let refused = match.play("S1, |")
        #expect(refused.count == 2 && refused[0] == .rejected(.turnComplete) && refused[1].isAccepted)
        #expect(SmokeFixtures.journal(match).suffix(4) == ["T20", "D16", "SB", "|"])
    }

    @Test func play_readsARecordedPosition() throws {
        var match = try registry.match(SmokeDiscRules.id, players: 1, seed: 1)
        match.play("S6@(124.0, 0.0), S6, MISS@(-12.5, 40.25)")
        let turn = match.currentTurn
        #expect(turn.map(\.hit) == [.single(6), .single(6), .miss])
        // With "@": a recorded position in board millimetres. Without: none.
        #expect(turn.map(\.position) == [BoardPoint(x: 124.0, y: 0.0), nil, BoardPoint(x: -12.5, y: 40.25)])
        #expect(turn.allSatisfy { $0.origin == .manual && !$0.needsReview && !$0.corrected })
        // The comma inside "@( … )" separates x from y, not two darts; a repetition keeps the position.
        var second = try registry.match(SmokeDiscRules.id, players: 1, seed: 1)
        let outcomes = second.play("T20@( 0.5 ,-103 ) ×2 | D3@(0,-166)")
        #expect(outcomes.count == 4)
        #expect(second.entries.map(\.position) == [BoardPoint(x: 0.5, y: -103), BoardPoint(x: 0.5, y: -103), nil, BoardPoint(x: 0, y: -166)])
    }

    @Test func facts_areReadByTheirGamesMdName() throws {
        var match = try registry.match(SmokeElimRules.id, ["lives": 2], players: 3)
        #expect(match.fact(0, "lives") == 2 && match.fact(2, "eliminated") == false)
        #expect(match.fact(1, "nope") == nil && match.gameFact("nope") == nil)
        match.play("S2, S2")
        #expect(match.fact(1, "lives") == 0 && match.fact(1, "eliminated") == true)
        #expect(match.gameFact("turnStarts") == .table([[1, 0, 1]]))
        #expect(match.turnNotation == ["S2", "S2"])
    }

    @Test func skeletonGames_areTheGamesWhoseCreationThrowsUnknownGame() {
        // A skeleton is skipped; a game that fails for another reason is NOT a skeleton and stays in the list.
        #expect(registry.skeletonGames == [SmokeSkeletonRules.id])
        #expect(registry.deliveredDefinitions.map(\.id) == [.x01, SmokeElimRules.id, SmokeDiscRules.id, SmokeBrokenRules.id])
        #expect(registry.descriptors.map(\.id) == [.x01, SmokeElimRules.id, SmokeDiscRules.id, SmokeSkeletonRules.id, SmokeBrokenRules.id])
        // Probed with the smallest allowed number of players (2 for the elimination probe).
        let onlyDelivered = GameRegistry([GameDefinition(rules: SmokeElimRules.self), GameDefinition(rules: SmokeX01Rules.self)])
        #expect(onlyDelivered.skeletonGames.isEmpty)
        #expect(onlyDelivered.deliveredDefinitions.map(\.id) == [SmokeElimRules.id, .x01])
        #expect(GameRegistry([]).skeletonGames.isEmpty && GameRegistry([]).deliveredDefinitions.isEmpty)
    }

    @Test func registry_findsADefinitionByItsId() throws {
        #expect(registry.definition(for: .x01)?.descriptor == SmokeX01Rules.descriptor)
        #expect(registry.definition(for: SmokeDiscRules.id)?.descriptor.dependsOnPosition == true)
        #expect(registry.definition(for: .cricket) == nil)
        // A definition can also be built from a closure.
        let custom = GameDefinition(descriptor: SmokeElimRules.descriptor) { configuration in
            try TurnBasedEngine<SmokeElimRules>(configuration: configuration)
        }
        #expect(custom.id == SmokeElimRules.id)
        let engine = try custom.makeEngine(GameConfiguration(gameID: SmokeElimRules.id, players: testPlayers(2), seed: 0))
        #expect(engine.snapshot.players.count == 2 && engine.configuration.options.int("lives") == 1)
        // The definition refuses the configuration of another game before its closure runs.
        let fixed = GameConfiguration(gameID: SmokeElimRules.id, players: testPlayers(2), seed: 0)
        let careless = GameDefinition(descriptor: SmokeElimRules.descriptor) { _ in
            try TurnBasedEngine<SmokeElimRules>(configuration: fixed)
        }
        #expect(throws: GameConfigurationError.unknownGame(.x01)) {
            try careless.makeEngine(GameConfiguration(gameID: .x01, players: testPlayers(2), seed: 0))
        }
    }
}
