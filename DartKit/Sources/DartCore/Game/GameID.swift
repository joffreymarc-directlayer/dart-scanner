import Foundation

/// Stable identifier of a game: the `id` column of GAMES.md §1. Used in persistence; never rename one.
public struct GameID: RawRepresentable, Hashable, Codable, Sendable, CustomStringConvertible {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public var description: String { rawValue }

    public static let x01 = GameID("x01")
    public static let cricket = GameID("cricket")
    public static let killer = GameID("killer")
    public static let aroundTheClock = GameID("aroundTheClock")
    public static let shanghai = GameID("shanghai")
    public static let highScore = GameID("highScore")
    public static let halveIt = GameID("halveIt")
    public static let moonLanding = GameID("moonLanding")
    public static let fight = GameID("fight")
    public static let conqueror = GameID("conqueror")
    public static let beerTap = GameID("beerTap")
    public static let football = GameID("football")
    public static let radar = GameID("radar")
    public static let golf = GameID("golf")
}
