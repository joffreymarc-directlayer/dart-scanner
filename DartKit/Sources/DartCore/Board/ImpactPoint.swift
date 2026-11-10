import Foundation

/// Impact point of a dart for a POSITION-DEPENDENT game (GAMES.md §2.13), in integer TENTHS of a millimetre,
/// in the frame of `BoardPoint` (origin at the bull centre, +x towards the 6, +y towards the 20).
/// Such a game computes in integers only: no sine, no square root, no floating-point comparison.
/// The thirteen games that do not depend on the position never build this type.
public struct ImpactPoint: Hashable, Sendable {
    public var x: Int
    public var y: Int

    public init(x: Int, y: Int) {
        self.x = x
        self.y = y
    }

    /// Converts a recorded position once: `Int((10 * x).rounded())`, nearest tenth, halves away from zero.
    /// A non-finite coordinate is pushed far off the board instead of trapping.
    public init(_ position: BoardPoint) {
        self.init(x: ImpactPoint.tenths(position.x), y: ImpactPoint.tenths(position.y))
    }

    /// The impact point of an input (GAMES.md §2.13), a total function of (hit, recorded position):
    /// 1. MISS has NO impact point, even when a position was recorded;
    /// 2. otherwise the recorded position, as it is (it is not checked against `hit`);
    /// 3. otherwise the canonical position of the bed.
    public init?(hit: Hit, position: BoardPoint?) {
        if hit.isMiss { return nil }
        if let position {
            self.init(position)
        } else if let canonical = ImpactPoint.canonical(of: hit) {
            self = canonical
        } else {
            return nil
        }
    }

    /// Canonical position of a bed: its middle, i.e. `BoardGeometry.standard.centre(of:)` rounded to the tenth.
    /// DB (0, 0); SB (0, 111); Sn on the OUTER single band (radius 134.5); Tn at radius 103; Dn at radius 166.
    /// Nil for MISS. The table of GAMES.md §2.13 is normative and embedded below: nothing is recomputed.
    public static func canonical(of hit: Hit) -> ImpactPoint? {
        switch hit.bed {
        case .miss: return nil
        case .innerBull: return ImpactPoint(x: 0, y: 0)
        case .outerBull: return ImpactPoint(x: 0, y: 111)
        case .single: return point(in: singles, hit)
        case .treble: return point(in: trebles, hit)
        case .double: return point(in: doubles, hit)
        }
    }

    /// The same point in millimetres.
    public var boardPoint: BoardPoint {
        BoardPoint(x: Double(x) / 10, y: Double(y) / 10)
    }

    // MARK: Private

    private static func tenths(_ millimetres: Double) -> Int {
        let value = (10 * millimetres).rounded()
        guard value.isFinite else { return 1_000_000 }
        return Int(max(-1_000_000, min(1_000_000, value)))
    }

    private static func point(in table: [(x: Int, y: Int)], _ hit: Hit) -> ImpactPoint? {
        guard let number = hit.number, let index = BoardGeometry.standardSectorOrder.firstIndex(of: number) else { return nil }
        return ImpactPoint(x: table[index].x, y: table[index].y)
    }

    // One entry per sector, clockwise from the top: 20, 1, 18, 4, 13, 6, 10, 15, 2, 17, 3, 19, 7, 16, 8, 11, 14, 9, 12, 5.
    private static let singles: [(x: Int, y: Int)] = [
        (0, 1345), (416, 1279), (791, 1088), (1088, 791), (1279, 416),
        (1345, 0), (1279, -416), (1088, -791), (791, -1088), (416, -1279),
        (0, -1345), (-416, -1279), (-791, -1088), (-1088, -791), (-1279, -416),
        (-1345, 0), (-1279, 416), (-1088, 791), (-791, 1088), (-416, 1279),
    ]
    private static let trebles: [(x: Int, y: Int)] = [
        (0, 1030), (318, 980), (605, 833), (833, 605), (980, 318),
        (1030, 0), (980, -318), (833, -605), (605, -833), (318, -980),
        (0, -1030), (-318, -980), (-605, -833), (-833, -605), (-980, -318),
        (-1030, 0), (-980, 318), (-833, 605), (-605, 833), (-318, 980),
    ]
    private static let doubles: [(x: Int, y: Int)] = [
        (0, 1660), (513, 1579), (976, 1343), (1343, 976), (1579, 513),
        (1660, 0), (1579, -513), (1343, -976), (976, -1343), (513, -1579),
        (0, -1660), (-513, -1579), (-976, -1343), (-1343, -976), (-1579, -513),
        (-1660, 0), (-1579, 513), (-1343, 976), (-976, 1343), (-513, 1579),
    ]
}
