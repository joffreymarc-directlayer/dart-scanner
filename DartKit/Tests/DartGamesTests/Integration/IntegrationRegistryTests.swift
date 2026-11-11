import Testing
import DartCore
import DartGames
import DartTestSupport // skeletonGames, deliveredDefinitions

/// The final assertion of ARCHITECTURE.md §12.1: no game of the registry is a skeleton any more, and the registry
/// has the fourteen ids of §5.2, in the order of the catalogue (GAMES.md §1).
@Suite struct IntegrationRegistryTests {
    private let registry = GameRegistry.standard

    @Test func noGameOfTheRegistryIsASkeleton() {
        #expect(registry.skeletonGames == [])
        #expect(registry.deliveredDefinitions.map(\.id) == registry.definitions.map(\.id))
    }

    @Test func theRegistryHasTheFourteenIds_inTheOrderOfTheCatalogue() {
        #expect(registry.definitions.map(\.id) == [
            .x01, .cricket, .killer, .shanghai, .moonLanding, .fight, .conqueror,
            .beerTap, .football, .radar, .golf,
            .aroundTheClock, .highScore, .halveIt,
        ])
    }

    /// Every game starts through the registry with its default options, at the smallest and at the largest
    /// number of players its defaults allow, and accepts a first dart.
    @Test func everyGameStarts_withItsDefaults_atBothEndsOfItsPlayerRange() throws {
        for descriptor in registry.descriptors {
            let range = descriptor.playerRange(for: descriptor.defaultOptions)
            for count in [range.lowerBound, range.upperBound] {
                var match = try IntegrationSupport.match(descriptor.id, players: count)
                #expect(match.phase == .throwing, "\(descriptor.id) at \(count)")
                #expect(match.snapshot.gameID == descriptor.id)
                #expect(match.snapshot.players.count == count)
                #expect(match.throwDart(DartRecord(hit: .treble(20))).isAccepted, "\(descriptor.id) at \(count)")
            }
        }
    }
}
