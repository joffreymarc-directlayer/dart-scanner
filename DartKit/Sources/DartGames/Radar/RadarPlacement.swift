import DartCore

/// Placement of a round target of Radar: `place(radius, obstacles)` of GAMES.md §15.3.
/// Everything is in whole millimetres, in the frame of the board (origin at the bull centre, +x towards the 6,
/// +y towards the 20), and every computation is in integers.
public enum RadarPlacement {
    /// A disc already on the board: centre and radius, in whole millimetres.
    public struct Disc: Hashable, Sendable {
        public var x: Int
        public var y: Int
        public var radius: Int

        public init(x: Int, y: Int, radius: Int) {
            self.x = x
            self.y = y
            self.radius = radius
        }
    }

    /// A centre on the 5 mm lattice, in whole millimetres.
    public struct Point: Hashable, Sendable {
        public var x: Int
        public var y: Int

        public init(x: Int, y: Int) {
            self.x = x
            self.y = y
        }
    }

    /// Outer radius of the scoring area: a disc must fit entirely inside it.
    public static let boardRadius = 170
    /// Pitch of the lattice of centres.
    public static let latticeStep = 5
    /// Smallest free space between two discs.
    public static let gap = 6

    /// The centres where a disc of `radius` may go, in drawing order: row by row, `y` from −170 up to 170 and,
    /// inside a row, `x` from −170 up to 170. A centre is kept when
    /// - `x² + y² ≤ (170 − radius)²`: the disc fits inside the scoring area;
    /// - for every obstacle, `(x − ox)² + (y − oy)² ≥ (radius + or + 6)²`: at least 6 mm between two discs.
    /// When no centre is left, the list is computed again without the second condition (overlap accepted): that
    /// fallback only makes the function total, no known game reaches it. Never empty: the centre of the board
    /// always fits.
    public static func candidates(radius: Int, obstacles: [Disc]) -> [Point] {
        let runs = freeRuns(radius: radius, obstacles: obstacles)
        var points: [Point] = []
        points.reserveCapacity(runs.count)
        for run in runs.row.indices {
            let y = coordinate(runs.row[run])
            for column in runs.first[run]...runs.last[run] {
                points.append(Point(x: coordinate(column), y: y))
            }
        }
        return points
    }

    /// Centre of a new disc: `candidates[random.nextInt(below: candidates.count)]`. Exactly one draw.
    public static func place(radius: Int, obstacles: [Disc], random: inout SeededRandom) -> Point {
        let runs = freeRuns(radius: radius, obstacles: obstacles)
        guard runs.count >= 1 else {
            // Unreachable (see `candidates`); the draw is still consumed.
            _ = random.next()
            return Point(x: 0, y: 0)
        }
        // The candidate of that index, without building the list.
        var index = random.nextInt(below: runs.count)
        for run in runs.row.indices {
            let length = runs.last[run] - runs.first[run] + 1
            if index < length {
                return Point(x: coordinate(runs.first[run] + index), y: coordinate(runs.row[run]))
            }
            index -= length
        }
        return Point(x: 0, y: 0)
    }

    // MARK: Private

    // The candidate list is never scanned point by point: a row of the lattice is an interval of columns, an
    // obstacle forbids an interval of each row, and what is left is a few runs of consecutive columns. A replay
    // places the five targets again at every undo and correction, and this is what keeps it cheap.

    /// Rows and columns of the lattice: coordinate −170 + 5 × index, index 0 to 68.
    private static let lineCount = 2 * boardRadius / latticeStep + 1

    private static func coordinate(_ index: Int) -> Int { latticeStep * index - boardRadius }

    /// The candidates as runs of consecutive columns, in drawing order.
    private struct Runs {
        /// Lattice row of each run.
        var row: [Int] = []
        /// First and last column of each run, both included.
        var first: [Int] = []
        var last: [Int] = []
        /// Number of candidates.
        var count = 0

        mutating func append(row: Int, first: Int, last: Int) {
            self.row.append(row)
            self.first.append(first)
            self.last.append(last)
            count += last - first + 1
        }
    }

    /// Columns of each row where a disc of some radius lies inside the scoring area: `first[row]...last[row]`,
    /// empty when `first[row] > last[row]`.
    private struct Extents: Sendable {
        var first: [Int]
        var last: [Int]
    }

    /// The extents of the three radii of the game are computed once: a game asks for them at every placement.
    private static let gameExtents: [Int: Extents] = {
        var table: [Int: Extents] = [:]
        for size in RadarRules.slots { table[size.radius] = computeExtents(radius: size.radius) }
        return table
    }()

    private static func computeExtents(radius: Int) -> Extents {
        var extents = Extents(first: [], last: [])
        let reach = abs(boardRadius - radius)
        for row in 0..<lineCount {
            let y = coordinate(row)
            // x² + y² ≤ reach²  ⟺  |x| ≤ ⌊√(reach² − y²)⌋.
            let room = reach * reach - y * y
            guard room >= 0 else {
                extents.first.append(1)
                extents.last.append(0)
                continue
            }
            let half = integerSquareRoot(room, from: reach)
            extents.first.append(max(0, ceilingColumn(-half)))
            extents.last.append(min(lineCount - 1, floorColumn(half)))
        }
        return extents
    }

    /// `candidates` as runs, fallback included.
    private static func freeRuns(radius: Int, obstacles: [Disc]) -> Runs {
        let extents = gameExtents[radius] ?? computeExtents(radius: radius)
        if !obstacles.isEmpty {
            let free = runs(extents: extents, radius: radius, obstacles: obstacles)
            if free.count >= 1 { return free }
        }
        return runs(extents: extents, radius: radius, obstacles: [])
    }

    private static func runs(extents: Extents, radius: Int, obstacles: [Disc]) -> Runs {
        // Obstacles as flat lists: centre, and clearance `radius + or + gap`.
        let centreX = obstacles.map(\.x), centreY = obstacles.map(\.y)
        let clearance = obstacles.map { abs(radius + $0.radius + gap) }
        // Forbidden intervals of the current row, sorted by their first column.
        var low = [Int](repeating: 0, count: obstacles.count)
        var high = [Int](repeating: 0, count: obstacles.count)
        var runs = Runs()
        for row in 0..<lineCount {
            let first = extents.first[row], last = extents.last[row]
            guard first <= last else { continue }
            let y = coordinate(row)
            var forbidden = 0
            for obstacle in centreX.indices {
                // (x − ox)² + (y − oy)² < clearance²  ⟺  |x − ox| ≤ ⌊√(clearance² − (y − oy)² − 1)⌋.
                let dy = y - centreY[obstacle]
                let room = clearance[obstacle] * clearance[obstacle] - dy * dy
                guard room >= 1 else { continue }
                let half = integerSquareRoot(room - 1, from: clearance[obstacle])
                let from = max(first, ceilingColumn(centreX[obstacle] - half))
                let through = min(last, floorColumn(centreX[obstacle] + half))
                guard from <= through else { continue }
                // Insertion in order: there are five obstacles at most in a game.
                var slot = forbidden
                while slot > 0 && low[slot - 1] > from {
                    low[slot] = low[slot - 1]
                    high[slot] = high[slot - 1]
                    slot -= 1
                }
                low[slot] = from
                high[slot] = through
                forbidden += 1
            }
            // What the forbidden intervals leave of the row.
            var cursor = first
            for interval in 0..<forbidden {
                if low[interval] > cursor { runs.append(row: row, first: cursor, last: low[interval] - 1) }
                cursor = max(cursor, high[interval] + 1)
            }
            if cursor <= last { runs.append(row: row, first: cursor, last: last) }
        }
        return runs
    }

    /// Smallest column whose coordinate is at least `x`.
    private static func ceilingColumn(_ x: Int) -> Int {
        -floorDivision(-(x + boardRadius), by: latticeStep)
    }

    /// Largest column whose coordinate is at most `x`.
    private static func floorColumn(_ x: Int) -> Int {
        floorDivision(x + boardRadius, by: latticeStep)
    }

    /// Division rounded towards −∞ (`/` rounds towards zero).
    private static func floorDivision(_ value: Int, by divisor: Int) -> Int {
        let quotient = value / divisor
        return value % divisor < 0 ? quotient - 1 : quotient
    }

    /// ⌊√value⌋ for `value ≥ 0`, in integers only (Newton's iteration), starting from `guess ≥ ⌊√value⌋`.
    private static func integerSquareRoot(_ value: Int, from guess: Int) -> Int {
        guard value > 0 else { return 0 }
        var root = max(guess, 1)
        var next = (root + value / root) / 2
        while next < root {
            root = next
            next = (root + value / root) / 2
        }
        return root
    }
}
