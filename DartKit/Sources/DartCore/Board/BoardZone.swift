import Foundation

/// A part of the board that a game can highlight (GAMES.md §2.9): a zone made of beds, or a free disc.
public enum BoardZone: Hashable, Codable, Sendable {
    /// The whole wedge of a number: inner single, treble, outer single and double.
    case sector(Int)
    /// Both single beds of a number.
    case single(Int)
    case double(Int)
    case treble(Int)
    case outerBull
    case innerBull
    /// Outer and inner bull together.
    case bull
    /// A disc laid over the beds, which it overlaps freely: centre (`x`, `y`) and `radius` in NOMINAL board
    /// millimetres, in the frame of `BoardPoint`. It corresponds to no dart notation. Radar targets (GAMES.md §15.7).
    case disc(x: Double, y: Double, radius: Double)

    /// Sector number of the zone; nil for the three bull zones and for a disc.
    public var number: Int? {
        switch self {
        case .sector(let n), .single(let n), .double(let n), .treble(let n): return n
        case .outerBull, .innerBull, .bull, .disc: return nil
        }
    }

    /// True when a dart scored as `hit` lies in this zone. MISS is in no zone, and no hit is "in" a disc:
    /// whether a dart touches a disc depends on its impact point, which only the game knows (GAMES.md §2.13).
    public func contains(_ hit: Hit) -> Bool {
        switch self {
        case .sector(let n): return hit.number == n
        case .single(let n): return hit.bed == .single && hit.number == n
        case .double(let n): return hit.bed == .double && hit.number == n
        case .treble(let n): return hit.bed == .treble && hit.number == n
        case .outerBull: return hit.bed == .outerBull
        case .innerBull: return hit.bed == .innerBull
        case .bull: return hit.isBull
        case .disc: return false
        }
    }

    /// The smallest zone that contains exactly this hit; nil for MISS.
    public init?(_ hit: Hit) {
        switch hit.bed {
        case .miss: return nil
        case .single: self = .single(hit.number ?? 0)
        case .double: self = .double(hit.number ?? 0)
        case .treble: self = .treble(hit.number ?? 0)
        case .outerBull: self = .outerBull
        case .innerBull: self = .innerBull
        }
    }
}
