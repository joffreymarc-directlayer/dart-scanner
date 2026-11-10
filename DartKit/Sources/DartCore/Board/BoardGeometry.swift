import Foundation

/// Board dimensions in millimetres and the conversion from a board point to a scored hit.
/// `standard` is the regulation steel-tip board. DartUI builds a second value with thicker rings for drawing
/// (DESIGN.md §3) and uses `remap(_:to:)` to move points between the two.
public struct BoardGeometry: Hashable, Sendable {
    /// Numbers clockwise from the top: 20, 1, 18, 4, 13, 6, 10, 15, 2, 17, 3, 19, 7, 16, 8, 11, 14, 9, 12, 5.
    public var sectorOrder: [Int]
    public var innerBullRadius: Double
    public var outerBullRadius: Double
    public var trebleInnerRadius: Double
    public var trebleOuterRadius: Double
    public var doubleInnerRadius: Double
    public var doubleOuterRadius: Double
    /// Outer radius of the number ring (overall diameter 451 mm).
    public var boardRadius: Double

    public init(sectorOrder: [Int] = BoardGeometry.standardSectorOrder,
                innerBullRadius: Double, outerBullRadius: Double,
                trebleInnerRadius: Double, trebleOuterRadius: Double,
                doubleInnerRadius: Double, doubleOuterRadius: Double,
                boardRadius: Double) {
        precondition(sectorOrder.count == 20 && Set(sectorOrder) == Set(1...20), "sectorOrder must be a permutation of 1...20")
        self.sectorOrder = sectorOrder
        self.innerBullRadius = innerBullRadius
        self.outerBullRadius = outerBullRadius
        self.trebleInnerRadius = trebleInnerRadius
        self.trebleOuterRadius = trebleOuterRadius
        self.doubleInnerRadius = doubleInnerRadius
        self.doubleOuterRadius = doubleOuterRadius
        self.boardRadius = boardRadius
    }

    public static let standardSectorOrder = [20, 1, 18, 4, 13, 6, 10, 15, 2, 17, 3, 19, 7, 16, 8, 11, 14, 9, 12, 5]

    /// Regulation board: bulls 6.35 / 15.9, treble 99–107, double 162–170, overall diameter 451.
    public static let standard = BoardGeometry(
        innerBullRadius: 6.35, outerBullRadius: 15.9,
        trebleInnerRadius: 99, trebleOuterRadius: 107,
        doubleInnerRadius: 162, doubleOuterRadius: 170,
        boardRadius: 225.5
    )

    /// Angular width of a sector, degrees.
    public static let sectorWidthDegrees: Double = 18

    // MARK: Scoring

    /// Scored hit of a point in the coordinates of THIS geometry; MISS beyond the outer double radius, and for a
    /// point with a non-finite coordinate.
    /// A point exactly on a ring boundary goes to the higher-scoring bed (bull, treble, double);
    /// a point exactly on a radial boundary goes to the clockwise sector.
    public func hit(at point: BoardPoint) -> Hit {
        let r = point.radius
        // Also false for a NaN or infinite radius (a non-finite coordinate): such a point is off the board.
        guard r <= doubleOuterRadius else { return .miss }
        if r <= innerBullRadius { return .innerBull }
        if r <= outerBullRadius { return .outerBull }
        let number = sectorOrder[sectorIndex(at: point)]
        if r >= trebleInnerRadius && r <= trebleOuterRadius { return .treble(number) }
        if r >= doubleInnerRadius { return .double(number) }
        return .single(number)
    }

    /// Index 0...19 in `sectorOrder` of the wedge that contains `point`: `floor(((α + 9°) mod 360°) / 18°)`.
    /// 0 for a point without an angle (a NaN coordinate).
    public func sectorIndex(at point: BoardPoint) -> Int {
        let shifted = (point.clockwiseDegrees + 9).truncatingRemainder(dividingBy: 360)
        guard shifted.isFinite else { return 0 }
        return min(19, max(0, Int(shifted / 18)))
    }

    // MARK: Sectors

    /// Index 0...19 of a number in `sectorOrder`. Precondition: `number` in 1...20.
    public func sectorIndex(of number: Int) -> Int {
        guard let index = sectorOrder.firstIndex(of: number) else { preconditionFailure("sector number out of range") }
        return index
    }

    /// The two adjacent numbers on the ring (GAMES.md §2.1). `neighbours(of: 20) == (5, 1)`.
    public func neighbours(of number: Int) -> (anticlockwise: Int, clockwise: Int) {
        let i = sectorIndex(of: number)
        return (sectorOrder[(i + 19) % 20], sectorOrder[(i + 1) % 20])
    }

    public func areAdjacent(_ a: Int, _ b: Int) -> Bool {
        let n = neighbours(of: a)
        return n.anticlockwise == b || n.clockwise == b
    }

    /// Clockwise angle of the middle of a sector, degrees from +y: 0 for the 20, 18 for the 1, …, 342 for the 5.
    public func centreAngle(of number: Int) -> Double {
        Double(sectorIndex(of: number)) * Self.sectorWidthDegrees
    }

    /// Angular extent of a sector, clockwise degrees from +y: `centre − 9 ... centre + 9` (−9...9 for the 20).
    public func angularRange(of number: Int) -> ClosedRange<Double> {
        let c = centreAngle(of: number)
        return (c - 9)...(c + 9)
    }

    // MARK: Bands

    /// The six radial bands of the scoring area, innermost first.
    public enum Band: Int, CaseIterable, Sendable {
        case innerBull, outerBull, innerSingle, treble, outerSingle, double
    }

    public func radialRange(of band: Band) -> ClosedRange<Double> {
        switch band {
        case .innerBull: return 0...innerBullRadius
        case .outerBull: return innerBullRadius...outerBullRadius
        case .innerSingle: return outerBullRadius...trebleInnerRadius
        case .treble: return trebleInnerRadius...trebleOuterRadius
        case .outerSingle: return trebleOuterRadius...doubleInnerRadius
        case .double: return doubleInnerRadius...doubleOuterRadius
        }
    }

    /// A representative point in the middle of a bed, in the coordinates of this geometry; nil for MISS.
    /// Singles use the outer single band; SB uses the middle of the outer bull ring, towards the 20.
    public func centre(of hit: Hit) -> BoardPoint? {
        func mid(_ band: Band) -> Double {
            let range = radialRange(of: band)
            return (range.lowerBound + range.upperBound) / 2
        }
        switch hit.bed {
        case .miss: return nil
        case .innerBull: return .centre
        case .outerBull: return BoardPoint(radius: mid(.outerBull), clockwiseDegrees: 0)
        case .single: return BoardPoint(radius: mid(.outerSingle), clockwiseDegrees: centreAngle(of: hit.number ?? 20))
        case .treble: return BoardPoint(radius: mid(.treble), clockwiseDegrees: centreAngle(of: hit.number ?? 20))
        case .double: return BoardPoint(radius: mid(.double), clockwiseDegrees: centreAngle(of: hit.number ?? 20))
        }
    }

    // MARK: Remapping

    /// Piecewise-linear radial remap from this geometry to `other`: every ring boundary of `self` lands on the same
    /// boundary of `other`, angles are unchanged. Beyond the outer double the scale is that of the number ring.
    /// `standard.remap(p, to: display)` draws a nominal point on the thick-ring board; the reverse call turns a tap
    /// on that drawing into a nominal position. `other.hit(at: remap(p, to: other)) == hit(at: p)` away from boundaries.
    /// The centre, and a point whose radius is not finite (a NaN or infinite coordinate), are returned unchanged.
    public func remap(_ point: BoardPoint, to other: BoardGeometry) -> BoardPoint {
        let r = point.radius
        guard r > 0, r.isFinite else { return point }
        let from = knots, to = other.knots
        var mapped = r * to[to.count - 1] / from[from.count - 1]
        for i in 1..<from.count where r <= from[i] {
            let span = from[i] - from[i - 1]
            let t = span > 0 ? (r - from[i - 1]) / span : 0
            mapped = to[i - 1] + t * (to[i] - to[i - 1])
            break
        }
        let scale = mapped / r
        return BoardPoint(x: point.x * scale, y: point.y * scale)
    }

    private var knots: [Double] {
        [0, innerBullRadius, outerBullRadius, trebleInnerRadius, trebleOuterRadius, doubleInnerRadius, doubleOuterRadius, boardRadius]
    }
}
