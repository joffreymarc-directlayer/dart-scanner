import Foundation

/// Position of a player in `GameConfiguration.players`: J1 = 0, J2 = 1, … (GAMES.md §2.3).
/// It is also the index of the player's colour in the palette of DESIGN.md §2.
public typealias PlayerIndex = Int

/// A person who plays. Kept in the roster between sessions.
public struct Player: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public var name: String

    public init(id: UUID = UUID(), name: String) {
        self.id = id
        self.name = name
    }
}
