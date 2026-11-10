import Foundation

/// The only two inputs of an engine (GAMES.md §2.4).
/// A dart may come with the recorded position of its impact; the position travels beside the input
/// (`GameEngine.apply(_:position:)`) and only a position-dependent game reads it (GAMES.md §2.13).
public enum GameInput: Hashable, Codable, Sendable {
    /// One dart, wherever it comes from (camera or manual input).
    case dart(Hit)
    /// The explicit "darts pulled / next player" confirmation.
    case endTurn
}

public enum GamePhase: String, Codable, Sendable {
    /// The current player may throw. `dart` and `endTurn` are accepted.
    case throwing
    /// The turn is closed and waits for the confirmation. `dart` is refused, `endTurn` is accepted.
    case turnComplete
    /// The game is over. Every input is refused.
    case finished
}

public enum FinishReason: String, Codable, Sendable {
    /// A player met the winning condition on a dart.
    case victory
    /// Only one player is left (elimination games).
    case lastPlayerStanding
    /// The round limit was reached; decided when `endTurn` is processed.
    case roundLimit
}

public enum InputRejection: String, Codable, Sendable {
    /// A dart arrived while the turn waits for `endTurn`: "Tour terminé, retirez les fléchettes".
    case turnComplete
    case gameFinished
}

/// Result of applying one input. A rejected input changes nothing and is not logged.
public enum InputOutcome: Hashable, Sendable {
    case accepted([GameEvent])
    case rejected(InputRejection)

    public var isAccepted: Bool {
        if case .accepted = self { return true }
        return false
    }

    /// Events of an accepted input, in order; empty when rejected.
    public var events: [GameEvent] {
        if case .accepted(let events) = self { return events }
        return []
    }
}
