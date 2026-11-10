import Foundation

/// SplitMix64. The ONLY source of randomness of the game engines (GAMES.md §2.8).
/// Engines must not use `SystemRandomNumberGenerator`, `Int.random(in:)`, `shuffled()` or their `using:` variants.
public struct SeededRandom: Hashable, Sendable {
    public private(set) var state: UInt64

    public init(seed: UInt64) {
        state = seed
    }

    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// `next() % bound`. Uniform enough for bound <= 20; exactly reproducible. Precondition: bound >= 1.
    public mutating func nextInt(below bound: Int) -> Int {
        precondition(bound >= 1, "bound must be positive")
        return Int(next() % UInt64(bound))
    }

    /// Fisher–Yates, from the last index down to 1 (`count - 1` draws).
    public mutating func shuffled<T>(_ items: [T]) -> [T] {
        var a = items
        var i = a.count - 1
        while i >= 1 {
            a.swapAt(i, nextInt(below: i + 1))
            i -= 1
        }
        return a
    }
}

/// Places, for each player, a block of `width` consecutive ring numbers (clockwise), without overlap (GAMES.md §2.8).
/// Used by Killer and Conqueror. Draws: 1 (offset) + `20 - p·k` (gaps) + `p - 1` (order).
/// Precondition: `playerCount * width <= 20`.
public func ringLayout(playerCount p: Int, width k: Int, rng: inout SeededRandom) -> [[Int]] {
    precondition(p >= 1 && k >= 1 && p * k <= 20, "zones do not fit on the ring")
    let ring = BoardGeometry.standardSectorOrder
    let offset = rng.nextInt(below: 20)
    var gaps = [Int](repeating: 0, count: p)
    for _ in 0..<(20 - p * k) {
        gaps[rng.nextInt(below: p)] += 1
    }
    let order = rng.shuffled(Array(0..<p))
    var zones = [[Int]](repeating: [], count: p)
    var cursor = offset
    for slot in 0..<p {
        zones[order[slot]] = (0..<k).map { ring[(cursor + $0) % 20] }
        cursor += k + gaps[slot]
    }
    return zones
}
