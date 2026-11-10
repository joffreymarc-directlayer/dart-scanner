import Foundation
import simd
import DartCore

/// Analytic colour model of the rendered board (VISION.md §10.1). Internal to DartVision.
///
/// This is the inner loop of the ray caster, so it works on plain numbers: no angle is computed. The twenty
/// radial wires are symmetric under the reflections `x → −x`, `y → −y` and `x ↔ y`; a point is therefore folded
/// into the first half-quadrant, where the wires sit at 9, 27 and 45 degrees from the nearest axis.
/// `BoardModel.surface(at:radii:)` is the readable reference of the same model, and the tests compare the two.
struct SyntheticBoard: Sendable {
    /// Width of a wire, mm.
    static let wireWidth: Double = 1.4

    /// Colours of VISION.md §10.1, indexed by `Paint.rawValue`.
    enum Paint: UInt8, CaseIterable, Sendable {
        case wall, numberRing, black, cream, red, green, wire

        var colour: SIMD3<UInt8> {
            switch self {
            case .wall: return SIMD3(120, 120, 125)
            case .numberRing: return SIMD3(25, 25, 25)
            case .black: return SIMD3(30, 30, 30)
            case .cream: return SIMD3(225, 205, 165)
            case .red: return SIMD3(200, 40, 40)
            case .green: return SIMD3(30, 140, 70)
            case .wire: return SIMD3(190, 190, 190)
            }
        }

        /// The paint of a surface of the reference model.
        init(_ surface: BoardModel.Surface) {
            switch surface {
            case .wall: self = .wall
            case .numberRing: self = .numberRing
            case .black: self = .black
            case .cream: self = .cream
            case .red: self = .red
            case .green: self = .green
            }
        }
    }

    // Squared radii of the surface boundaries.
    private let innerBull2: Double
    private let outerBull2: Double
    private let trebleInner2: Double
    private let trebleOuter2: Double
    private let doubleInner2: Double
    private let doubleOuter2: Double
    private let board2: Double
    // Squared inner and outer radii of the six ring wires, innermost first.
    private let wireLow: (Double, Double, Double, Double, Double, Double)
    private let wireHigh: (Double, Double, Double, Double, Double, Double)
    private let halfWire: Double
    // The six ring radii, innermost first, and the radius of the board.
    private let rings: (Double, Double, Double, Double, Double, Double)
    private let boardRadius: Double
    /// True for a regular board: positive, strictly increasing radii. Only then do the clearances describe the
    /// answers of `isWire` and `surface`; on any other board they are 0 and the renderer shades every sample.
    private let isRegular: Bool
    // Direction cosines of the folded wires.
    private let cos9: Double
    private let sin9: Double
    private let cos27: Double
    private let sin27: Double

    init(radii: RingRadii) {
        innerBull2 = radii.innerBull * radii.innerBull
        outerBull2 = radii.outerBull * radii.outerBull
        trebleInner2 = radii.trebleInner * radii.trebleInner
        trebleOuter2 = radii.trebleOuter * radii.trebleOuter
        doubleInner2 = radii.doubleInner * radii.doubleInner
        doubleOuter2 = radii.doubleOuter * radii.doubleOuter
        let board = max(BoardModel.numberRingRadius, radii.doubleOuter)
        board2 = board * board
        boardRadius = board
        isRegular = radii.isWellFormed
        rings = (radii.innerBull, radii.outerBull, radii.trebleInner, radii.trebleOuter, radii.doubleInner, radii.doubleOuter)
        let half = SyntheticBoard.wireWidth / 2
        halfWire = half
        func low(_ radius: Double) -> Double { let r = max(0, radius - half); return r * r }
        func high(_ radius: Double) -> Double { (radius + half) * (radius + half) }
        wireLow = (low(radii.innerBull), low(radii.outerBull), low(radii.trebleInner),
                   low(radii.trebleOuter), low(radii.doubleInner), low(radii.doubleOuter))
        wireHigh = (high(radii.innerBull), high(radii.outerBull), high(radii.trebleInner),
                    high(radii.trebleOuter), high(radii.doubleInner), high(radii.doubleOuter))
        cos9 = cos(9 * Double.pi / 180)
        sin9 = sin(9 * Double.pi / 180)
        cos27 = cos(27 * Double.pi / 180)
        sin27 = sin(27 * Double.pi / 180)
    }

    /// Largest radius at which anything but the wall can be seen, mm.
    var outerRadius: Double {
        max(board2, wireHigh.5).squareRoot()
    }

    /// Largest radius of a wire, mm.
    var wireOuterRadius: Double {
        wireHigh.5.squareRoot()
    }

    /// True when the point `(x, y)` of the wire plane lies on a wire: one of the six rings, or one of the twenty
    /// radial wires between the outer bull and the outer double wire.
    @inline(__always)
    func isWire(x: Double, y: Double) -> Bool {
        let r2 = x * x + y * y
        if r2 > wireHigh.5 { return false }
        if r2 >= wireLow.5 { return true }
        if r2 <= wireHigh.4 {
            if r2 >= wireLow.4 { return true }
            if r2 <= wireHigh.3 {
                if r2 >= wireLow.3 { return true }
                if r2 <= wireHigh.2 {
                    if r2 >= wireLow.2 { return true }
                    if r2 <= wireHigh.1 {
                        if r2 >= wireLow.1 { return true }
                        // Inside the outer bull there is only the inner bull wire.
                        return r2 <= wireHigh.0 && r2 >= wireLow.0
                    }
                }
            }
        }
        // Between the outer bull and the outer double wire: the radial wires.
        let ax = abs(x), ay = abs(y)
        let a = ax < ay ? ax : ay, b = ax < ay ? ay : ax
        let d9 = a * cos9 - b * sin9
        if d9 <= halfWire && d9 >= -halfWire { return true }
        let d27 = a * cos27 - b * sin27
        if d27 <= halfWire && d27 >= -halfWire { return true }
        // The wire at 45 degrees is the fold itself: a <= b.
        return (b - a) * 0.7071067811865476 <= halfWire
    }

    /// Paint of the board surface at `(x, y)`, wires not included.
    @inline(__always)
    func surface(x: Double, y: Double) -> Paint {
        let r2 = x * x + y * y
        if r2 > doubleOuter2 {
            return r2 > board2 ? .wall : .numberRing
        }
        if r2 <= outerBull2 {
            return r2 <= innerBull2 ? .red : .green
        }
        // Sector parity without an angle: `steps` is the number of wires between the point and the nearest axis.
        let ax = abs(x), ay = abs(y)
        let a = ax < ay ? ax : ay, b = ax < ay ? ay : ax
        var steps = 0
        if a * cos9 - b * sin9 >= 0 { steps += 1 }
        if a * cos27 - b * sin27 >= 0 { steps += 1 }
        // Sector indices on the y axis are even (20 and 3), on the x axis odd (6 and 11).
        if ax > ay { steps += 1 }
        let light = steps & 1 == 1
        let ring = (r2 >= trebleInner2 && r2 <= trebleOuter2) || r2 >= doubleInner2
        if ring { return light ? .green : .red }
        return light ? .cream : .black
    }

    /// Paint seen at `(x, y)` when the wires lie in the board plane.
    @inline(__always)
    func paint(x: Double, y: Double) -> Paint {
        isWire(x: x, y: y) ? .wire : surface(x: x, y: y)
    }

    // MARK: Clearances
    //
    // The renderer fills a whole block of pixels with one colour when nothing can change inside it. These three
    // functions give a LOWER bound of the distance from a point to the nearest place where the answer of
    // `isWire`, `surface` or `paint` changes: a disc of that radius around the point has a single paint.

    /// Lower bound of the distance from `(x, y)` to the nearest edge of a wire, mm (from either side of the edge).
    @inline(__always)
    func wireClearance(x: Double, y: Double) -> Double {
        if !isRegular { return 0 }
        let r = (x * x + y * y).squareRoot()
        var clearance = abs(abs(r - rings.0) - halfWire)
        var edge = abs(abs(r - rings.1) - halfWire)
        if edge < clearance { clearance = edge }
        edge = abs(abs(r - rings.2) - halfWire)
        if edge < clearance { clearance = edge }
        edge = abs(abs(r - rings.3) - halfWire)
        if edge < clearance { clearance = edge }
        edge = abs(abs(r - rings.4) - halfWire)
        if edge < clearance { clearance = edge }
        edge = abs(abs(r - rings.5) - halfWire)
        if edge < clearance { clearance = edge }
        // Radial wires: only where they exist. Further in or out, the ring wire at their end is closer.
        if r >= rings.1 - halfWire && r <= rings.5 + halfWire {
            let ax = abs(x), ay = abs(y)
            let a = ax < ay ? ax : ay, b = ax < ay ? ay : ax
            edge = abs(abs(a * cos9 - b * sin9) - halfWire)
            if edge < clearance { clearance = edge }
            edge = abs(abs(a * cos27 - b * sin27) - halfWire)
            if edge < clearance { clearance = edge }
            edge = abs((b - a) * 0.7071067811865476 - halfWire)
            if edge < clearance { clearance = edge }
        }
        return clearance
    }

    /// Lower bound of the distance from `(x, y)` to the nearest boundary between two surfaces, mm.
    @inline(__always)
    func surfaceClearance(x: Double, y: Double) -> Double {
        if !isRegular { return 0 }
        let r = (x * x + y * y).squareRoot()
        var clearance = abs(r - boardRadius)
        var edge = abs(r - rings.0)
        if edge < clearance { clearance = edge }
        edge = abs(r - rings.1)
        if edge < clearance { clearance = edge }
        edge = abs(r - rings.2)
        if edge < clearance { clearance = edge }
        edge = abs(r - rings.3)
        if edge < clearance { clearance = edge }
        edge = abs(r - rings.4)
        if edge < clearance { clearance = edge }
        edge = abs(r - rings.5)
        if edge < clearance { clearance = edge }
        // Sector boundaries: only between the outer bull and the outer double wire.
        if r >= rings.1 && r <= rings.5 {
            let ax = abs(x), ay = abs(y)
            let a = ax < ay ? ax : ay, b = ax < ay ? ay : ax
            edge = abs(a * cos9 - b * sin9)
            if edge < clearance { clearance = edge }
            edge = abs(a * cos27 - b * sin27)
            if edge < clearance { clearance = edge }
            edge = (b - a) * 0.7071067811865476
            if edge < clearance { clearance = edge }
        }
        return clearance
    }

    /// Lower bound of the distance from `(x, y)` to the nearest change of `paint`, mm: with the wires in the board
    /// plane every surface boundary is under a wire, except the edge of the board.
    @inline(__always)
    func paintClearance(x: Double, y: Double) -> Double {
        let wires = wireClearance(x: x, y: y)
        let edge = abs((x * x + y * y).squareRoot() - boardRadius)
        return edge < wires ? edge : wires
    }
}
