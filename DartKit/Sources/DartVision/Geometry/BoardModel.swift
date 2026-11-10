import Foundation
import simd
import DartCore

/// The board as the vision code sees it: wires, sectors and surfaces in the frame of VISION.md §3.3
/// (+x towards the 6, +y towards the 20, clockwise angles from +y). Internal to DartVision.
///
/// Scoring stays in DartCore (`BoardGeometry.hit(at:)`); this model only adds what images need: where the wires
/// run and which colour a point of the board has.
enum BoardModel {
    /// Number of sectors and of radial wires.
    static let sectorCount = 20
    /// Angular width of a sector, degrees.
    static let sectorWidthDegrees: Double = 18
    /// Outer radius of the number ring, mm (overall diameter 451).
    static let numberRingRadius: Double = 225.5

    /// What a point of the board plane shows.
    enum Surface: Int, Sendable, CaseIterable {
        /// Beyond the number ring.
        case wall
        /// Between the outer double wire and the edge of the board.
        case numberRing
        /// Single of an even sector index.
        case black
        /// Single of an odd sector index.
        case cream
        /// Double and treble of an even sector index; inner bull.
        case red
        /// Double and treble of an odd sector index; outer bull.
        case green
    }

    /// Clockwise angle of radial wire `m` (0...19), degrees from +y: `9 + 18·m`. Wire 0 separates the 20 from the 1.
    static func wireAngleDegrees(_ wire: Int) -> Double {
        9 + sectorWidthDegrees * Double(wire)
    }

    /// Unit vector along radial wire `m`, from the centre outwards: `(sin α_m, cos α_m)`.
    static func wireDirection(_ wire: Int) -> SIMD2<Double> {
        let a = wireAngleDegrees(wire) * .pi / 180
        return SIMD2(sin(a), cos(a))
    }

    /// Signed distance of a point to radial wire `m`, mm: `x·cos α_m − y·sin α_m`.
    /// Positive on the clockwise side of the wire (for wire 0: in the 1, negative in the 20).
    static func signedDistanceToWire(_ wire: Int, _ point: BoardPoint) -> Double {
        let a = wireAngleDegrees(wire) * .pi / 180
        return point.x * cos(a) - point.y * sin(a)
    }

    /// Index 0...19 of the sector that contains `point`, in the order 20, 1, 18, 4, …:
    /// `floor(((α + 9°) mod 360°) / 18°)`. 0 for a point without an angle.
    static func sectorIndex(at point: BoardPoint) -> Int {
        var degrees = atan2(point.x, point.y) * 180 / .pi
        guard degrees.isFinite else { return 0 }
        if degrees < 0 { degrees += 360 }
        let shifted = (degrees + 9).truncatingRemainder(dividingBy: 360)
        return min(sectorCount - 1, max(0, Int(shifted / sectorWidthDegrees)))
    }

    /// True for the sectors with a cream single and green rings (odd index: 1, 4, 6, 15, …).
    static func isLightSector(_ index: Int) -> Bool {
        index % 2 != 0
    }

    /// Surface at a metric point of a board with the given ring radii (wires not included).
    /// A point exactly on a ring boundary belongs to the higher-scoring bed, as in `BoardGeometry.hit(at:)`.
    static func surface(at point: BoardPoint, radii: RingRadii = .nominal) -> Surface {
        let r = (point.x * point.x + point.y * point.y).squareRoot()
        guard r.isFinite else { return .wall }
        if r <= radii.innerBull { return .red }
        if r <= radii.outerBull { return .green }
        if r > max(numberRingRadius, radii.doubleOuter) { return .wall }
        if r > radii.doubleOuter { return .numberRing }
        let light = isLightSector(sectorIndex(at: point))
        let inRing = (r >= radii.trebleInner && r <= radii.trebleOuter) || r >= radii.doubleInner
        if inRing { return light ? .green : .red }
        return light ? .cream : .black
    }

    /// Surface that `BoardGeometry` and the colour convention of VISION.md §3.3 give to a scored hit in the sector
    /// of index `sectorIndex`; nil for MISS (number ring or wall, which a hit does not tell apart).
    static func surface(of hit: Hit, sectorIndex: Int) -> Surface? {
        switch hit.bed {
        case .miss: return nil
        case .innerBull: return .red
        case .outerBull: return .green
        case .single: return isLightSector(sectorIndex) ? .cream : .black
        case .double, .treble: return isLightSector(sectorIndex) ? .green : .red
        }
    }
}
