import DartCore

/// Finishing advice of X01: the text of `TurnSnapshot.hint`, "Pour finir : T20 D20" (ARCHITECTURE.md §5.6).
/// It is OUTSIDE the rules (GAMES.md §3.7): an advice never changes what a dart does.
///
/// A small table of one- to three-dart finishes, built once. Among the finishes with the fewest darts it keeps
/// the easiest one: singles before trebles before bulls, and a favourite double to end on in double out.
public enum X01Checkout {
    /// The highest score three darts can finish: T20, T20, T20 in straight out (170 in double out).
    public static let highestFinish = 180

    /// A way to reach exactly zero from `remaining` with at most `darts` darts (1...3), in throwing order:
    /// the fewest darts possible, each dart leaving a score that can still be finished. In double out the last
    /// dart is a double (D1...D20 or DB). Nil when no such finish exists.
    public static func route(remaining: Int, darts: Int, doubleOut: Bool) -> [Hit]? {
        guard remaining >= 1, remaining <= highestFinish, darts >= 1 else { return nil }
        let table = doubleOut ? doubleOutRoutes : straightOutRoutes
        for count in 1...min(darts, dartsPerTurn) {
            if let route = table[count - 1][remaining] { return route }
        }
        return nil
    }

    // MARK: Private

    /// `routes[count - 1][remaining]`: the preferred finish of `remaining` in exactly `count` darts.
    private typealias Table = [[[Hit]?]]

    private static let straightOutRoutes: Table = buildRoutes(doubleOut: false)
    private static let doubleOutRoutes: Table = buildRoutes(doubleOut: true)

    /// Difficulty of a dart that prepares the finish: a single is the easy dart.
    private static func setupCost(_ hit: Hit) -> Int {
        switch hit.bed {
        case .single: return 0
        case .treble: return 2
        case .outerBull, .double: return 3
        case .innerBull, .miss: return 4
        }
    }

    /// Difficulty of the last dart. In double out, the doubles that halve into another double come first.
    private static func finishCost(_ hit: Hit, doubleOut: Bool) -> Int {
        guard doubleOut else {
            switch hit.bed {
            case .single: return 0
            case .double, .treble: return 2
            case .outerBull: return 3
            case .innerBull, .miss: return 4
            }
        }
        guard let number = hit.number else { return 4 }
        switch number {
        case 20, 16: return 0
        case 18, 12, 10, 8: return 1
        case 14, 6, 4, 2: return 2
        default: return 3
        }
    }

    private static func buildRoutes(doubleOut: Bool) -> Table {
        let beds = Hit.all.filter { !$0.isMiss }
        let finishers = beds.filter { !doubleOut || $0.isDouble }
        let size = highestFinish + 1
        var routes = Table(repeating: [[Hit]?](repeating: nil, count: size), count: dartsPerTurn)
        // Best key so far per cell: (cost, points of the first dart, points of the second dart).
        // A lower cost wins, then a bigger first dart, then a bigger second dart; on a full tie the first found stays.
        var keys = [[(cost: Int, first: Int, second: Int)?]](repeating: [(cost: Int, first: Int, second: Int)?](repeating: nil, count: size),
                                                             count: dartsPerTurn)

        func isBetter(_ key: (cost: Int, first: Int, second: Int), than best: (cost: Int, first: Int, second: Int)?) -> Bool {
            guard let best else { return true }
            if key.cost != best.cost { return key.cost < best.cost }
            if key.first != best.first { return key.first > best.first }
            return key.second > best.second
        }

        for last in finishers {
            let lastCost = finishCost(last, doubleOut: doubleOut)
            if isBetter((lastCost, 0, 0), than: keys[0][last.points]) {
                keys[0][last.points] = (lastCost, 0, 0)
                routes[0][last.points] = [last]
            }
            for first in beds {
                let two = first.points + last.points
                guard two < size else { continue }
                let twoCost = lastCost + setupCost(first)
                if isBetter((twoCost, first.points, 0), than: keys[1][two]) {
                    keys[1][two] = (twoCost, first.points, 0)
                    routes[1][two] = [first, last]
                }
                // The bigger dart first: the same two darts in the other order are the same finish.
                for second in beds where second.points <= first.points {
                    let three = two + second.points
                    guard three < size else { continue }
                    let threeCost = twoCost + setupCost(second)
                    if isBetter((threeCost, first.points, second.points), than: keys[2][three]) {
                        keys[2][three] = (threeCost, first.points, second.points)
                        routes[2][three] = [first, second, last]
                    }
                }
            }
        }
        return routes
    }
}
