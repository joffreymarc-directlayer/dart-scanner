import Foundation

/// Shared-rank computation of GAMES.md §2.7.
public enum Ranking {
    /// `keys[player]` is compared lexicographically and SMALLER IS BETTER (negate a value to rank it descending).
    /// Players with equal keys share a rank and the next rank is skipped: keys [[1], [1], [5]] give [1, 1, 3].
    /// Elimination games prefix the key with 0 for players alive and 1 for eliminated ones, followed for the
    /// latter by minus their elimination order (the last eliminated ranks best).
    public static func ranks(keys: [[Int]]) -> [Int] {
        keys.map { key in
            1 + keys.filter { $0.lexicographicallyPrecedes(key) }.count
        }
    }
}
