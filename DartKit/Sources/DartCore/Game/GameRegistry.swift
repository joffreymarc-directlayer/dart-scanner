import Foundation

/// A game the application can offer: its descriptor and the way to create its engine.
public struct GameDefinition: Sendable, Identifiable {
    public let descriptor: GameDescriptor
    private let make: @Sendable (GameConfiguration) throws -> any GameEngine

    public var id: GameID { descriptor.id }

    public init(descriptor: GameDescriptor, makeEngine: @escaping @Sendable (GameConfiguration) throws -> any GameEngine) {
        self.descriptor = descriptor
        self.make = makeEngine
    }

    /// A game written as `TurnBasedRules`: `GameDefinition(rules: X01Rules.self)`.
    public init<Rules: TurnBasedRules>(rules: Rules.Type) {
        self.init(descriptor: Rules.descriptor) { try TurnBasedEngine<Rules>(configuration: $0) }
    }

    /// Throws `GameConfigurationError`.
    public func makeEngine(_ configuration: GameConfiguration) throws -> any GameEngine {
        guard configuration.gameID == descriptor.id else {
            throw GameConfigurationError.unknownGame(configuration.gameID)
        }
        return try make(configuration)
    }
}

/// The list of games, in display order. The home screen, the setup screen and the play screen are driven by it.
/// DartGames provides the populated value (`GameRegistry.standard`).
public struct GameRegistry: Sendable {
    public let definitions: [GameDefinition]

    public init(_ definitions: [GameDefinition]) {
        self.definitions = definitions
    }

    public var descriptors: [GameDescriptor] {
        definitions.map(\.descriptor)
    }

    public func definition(for id: GameID) -> GameDefinition? {
        definitions.first { $0.id == id }
    }

    /// Creates a new game. Throws `GameConfigurationError`.
    public func makeMatch(_ configuration: GameConfiguration) throws -> GameMatch {
        guard let definition = definition(for: configuration.gameID) else {
            throw GameConfigurationError.unknownGame(configuration.gameID)
        }
        return try GameMatch(definition: definition, configuration: configuration)
    }

    /// Rebuilds a saved game by replaying its journal. Throws `GameConfigurationError`.
    public func restoreMatch(_ record: MatchRecord) throws -> GameMatch {
        guard let definition = definition(for: record.configuration.gameID) else {
            throw GameConfigurationError.unknownGame(record.configuration.gameID)
        }
        return try GameMatch(definition: definition, record: record)
    }
}
