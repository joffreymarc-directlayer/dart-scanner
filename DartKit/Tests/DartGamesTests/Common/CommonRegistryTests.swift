import Testing
import DartCore
import DartGames
import DartTestSupport

/// The registry (ARCHITECTURE.md §5.2, §12.1): fourteen games in the order of the catalogue, default options
/// valid for every allowed number of players, and which games are delivered. True from lot F0 on, the
/// descriptors being final; the games still in skeleton are listed in the output and skipped, never failed.
@Suite struct CommonRegistryTests {
    private let registry = GameRegistry.standard

    @Test func fourteenUniqueIds_inTheOrderOfTheCatalogue() {
        let ids = registry.definitions.map(\.id)
        #expect(ids == [
            .x01, .cricket, .killer, .shanghai, .moonLanding, .fight, .conqueror,
            .beerTap, .football, .radar, .golf,
            .aroundTheClock, .highScore, .halveIt,
        ])
        #expect(Set(ids).count == 14)
        #expect(registry.descriptors.map(\.id) == ids)
        for id in ids {
            #expect(registry.definition(for: id)?.id == id)
        }
    }

    @Test func defaultOptions_areValidForEveryAllowedNumberOfPlayers() {
        for descriptor in registry.descriptors {
            // Every option has its default among the values its own schema accepts.
            let range = descriptor.playerRange(for: descriptor.defaultOptions)
            #expect(!range.isEmpty && descriptor.players.contains(range.lowerBound) && descriptor.players.contains(range.upperBound))
            for count in range {
                #expect(descriptor.validate(options: [:], playerCount: count) == [], "\(descriptor.id), \(count) players")
                #expect(descriptor.validate(options: descriptor.defaultOptions, playerCount: count) == [])
            }
            #expect(descriptor.normalized([:]) == descriptor.defaultOptions)
            #expect(descriptor.defaultOptions.values.count == descriptor.options.count, "\(descriptor.id) has a duplicate option key")
        }
    }

    /// Writes the skipped games in the test output, so that the skip is visible (ARCHITECTURE.md §12.1).
    @Test func skeletonGames_areListedInTheOutput_andSkipped() {
        let skeletons = registry.skeletonGames
        let delivered = registry.deliveredDefinitions.map(\.id)
        if skeletons.isEmpty {
            print("Common tests: every game of the registry is delivered, none is skipped.")
        } else {
            print("Common tests: games still in skeleton, SKIPPED by the common tests: \(skeletons.map(\.rawValue).joined(separator: ", "))")
        }
        print("Common tests: games checked: \(delivered.map(\.rawValue).joined(separator: ", "))")
        // The two lists share nothing and cover the registry, in its order.
        #expect(Set(skeletons).isDisjoint(with: delivered))
        #expect(Set(skeletons).union(delivered) == Set(registry.definitions.map(\.id)))
        #expect(delivered == registry.definitions.map(\.id).filter { !skeletons.contains($0) })
        #expect(CommonPlayout.deliveredGames == delivered)
        // The games of lot G1 are delivered with these tests.
        #expect(delivered.contains(.x01) && delivered.contains(.cricket) && delivered.contains(.highScore))
    }

    /// A delivered game starts with its default options for every number of players its descriptor allows:
    /// any error other than the skeleton's `.unknownGame` is a failure, not a skip.
    @Test func everyGame_startsWithItsDefaults_orIsASkeleton() throws {
        let skeletons = Set(registry.skeletonGames)
        for descriptor in registry.descriptors {
            for count in descriptor.playerRange(for: descriptor.defaultOptions) {
                if skeletons.contains(descriptor.id) {
                    #expect(throws: GameConfigurationError.unknownGame(descriptor.id)) {
                        try registry.match(descriptor.id, players: count)
                    }
                    continue
                }
                let match = try registry.match(descriptor.id, players: count, seed: 3)
                #expect(match.configuration.options == descriptor.defaultOptions, "\(descriptor.id)")
                #expect(match.snapshot.gameID == descriptor.id && match.players.count == count)
                #expect(CommonPlayout.snapshotViolations(match) == [], "\(descriptor.id), \(count) players")
            }
            // Outside its range of players a game is refused, delivered or not: the schema decides first.
            for count in [descriptor.players.lowerBound - 1, descriptor.players.upperBound + 1] {
                #expect(throws: GameConfigurationError.playerCountOutOfRange(allowed: descriptor.players, actual: count)) {
                    try registry.match(descriptor.id, players: count)
                }
            }
        }
    }

    /// GAMES.md §2.4, common initial state: `phase = throwing`, `currentPlayer = J1`, `round = 1`, empty volley,
    /// empty journal; nothing to undo and nothing to correct.
    @Test(arguments: CommonPlayout.deliveredGames)
    func aNewGame_startsInTheCommonInitialState(_ game: GameID) throws {
        let descriptor = try CommonPlayout.descriptor(of: game)
        var random = SeededRandom(seed: CommonPlayout.seed(game, 1))
        for _ in 0..<40 {
            let configuration = CommonPlayout.randomConfiguration(descriptor, &random)
            #expect(descriptor.validate(options: configuration.options, playerCount: configuration.players.count) == [])
            var match = try CommonPlayout.makeMatch(configuration)
            let snapshot = match.snapshot
            #expect(snapshot.phase == .throwing && snapshot.currentPlayer == 0 && snapshot.round == 1)
            #expect(snapshot.turn.darts.isEmpty && snapshot.finishReason == nil)
            #expect(match.entries.isEmpty && !match.canUndo && match.currentTurn.isEmpty)
            #expect(match.configuration == configuration && match.players == configuration.players)
            #expect(snapshot.players.allSatisfy { !$0.isEliminated })
            #expect(CommonPlayout.snapshotViolations(match) == [], "\(CommonPlayout.describe(match))")
            // Nothing to undo, nothing to correct: the state does not move.
            #expect(!match.undo().applied && !match.replaceDart(at: 0, with: .single(1)).applied && !match.removeDart(at: 0).applied)
            #expect(match.snapshot == snapshot && match.entries.isEmpty)
            // Creating the same game twice gives the same state (GAMES.md §2.8: the generator is recreated).
            #expect(try CommonPlayout.makeMatch(configuration).snapshot == snapshot)
        }
    }
}
