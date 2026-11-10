import Foundation

/// Everything that defines a game before the first dart (GAMES.md §2.4): `state = reduce(configuration, inputs)`.
public struct GameConfiguration: Hashable, Codable, Sendable {
    public var gameID: GameID
    public var options: GameOptions
    /// Playing order; fixed for the whole game. Shuffling is the setup screen's job.
    public var players: [Player]
    /// Drawn by the application when the game is created and saved with it (GAMES.md §2.8).
    public var seed: UInt64

    public init(gameID: GameID, options: GameOptions = [:], players: [Player], seed: UInt64) {
        self.gameID = gameID
        self.options = options
        self.players = players
        self.seed = seed
    }
}

/// Why a game cannot be created. There is never a silent fallback.
public enum GameConfigurationError: Error, Hashable, Sendable {
    case unknownGame(GameID)
    case playerCountOutOfRange(allowed: ClosedRange<Int>, actual: Int)
    case unknownOption(key: String)
    /// Wrong type, out of range, or a custom value the engine cannot read.
    case invalidOptionValue(key: String)
    /// The selected choice does not allow this number of players (Killer `easy` with 7 or 8 players).
    case choiceUnavailable(key: String, note: LocalizedText?)
}
