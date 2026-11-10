import Foundation
import simd
import CoreGraphics
import CoreVideo
import DartCore

/// Ring radii of one physical board in mm. The outer double radius is the scale gauge and stays at its nominal value.
public struct RingRadii: Hashable, Codable, Sendable {
    public var innerBull: Double
    public var outerBull: Double
    public var trebleInner: Double
    public var trebleOuter: Double
    public var doubleInner: Double
    public var doubleOuter: Double
    public init(innerBull: Double, outerBull: Double, trebleInner: Double, trebleOuter: Double, doubleInner: Double, doubleOuter: Double) {
        self.innerBull = innerBull
        self.outerBull = outerBull
        self.trebleInner = trebleInner
        self.trebleOuter = trebleOuter
        self.doubleInner = doubleInner
        self.doubleOuter = doubleOuter
    }
    /// The radii of `BoardGeometry.standard`.
    public static let nominal: RingRadii = RingRadii(innerBull: 6.35, outerBull: 15.9, trebleInner: 99, trebleOuter: 107, doubleInner: 162, doubleOuter: 170)
    /// Piecewise-linear radial remap from this board's metric coordinates to nominal coordinates,
    /// so that DartCore classifies with the nominal geometry.
    public func toNominal(_ point: BoardPoint) -> BoardPoint {
        RingRadii.remap(point, from: knots, to: RingRadii.nominal.knots)
    }
    /// Inverse of `toNominal`.
    public func fromNominal(_ point: BoardPoint) -> BoardPoint {
        RingRadii.remap(point, from: RingRadii.nominal.knots, to: knots)
    }
}

extension RingRadii {
    /// Knots of the radial stretch, innermost first: the centre, then the six ring radii (VISION.md §4.6, C4).
    var knots: [Double] {
        [0, innerBull, outerBull, trebleInner, trebleOuter, doubleInner, doubleOuter]
    }

    /// The six ring radii, innermost first.
    var all: [Double] {
        [innerBull, outerBull, trebleInner, trebleOuter, doubleInner, doubleOuter]
    }

    /// True when the six radii are finite, positive and strictly increasing.
    var isWellFormed: Bool {
        var previous = 0.0
        for radius in all {
            guard radius.isFinite, radius > previous else { return false }
            previous = radius
        }
        return true
    }

    /// Piecewise-linear radial remap that sends every knot of `from` to the same knot of `to`, angles unchanged.
    /// Beyond the last knot the radius keeps its distance to that knot: the identity when both outer double radii
    /// are 170. The centre and a point whose radius is not finite are returned unchanged.
    private static func remap(_ point: BoardPoint, from: [Double], to: [Double]) -> BoardPoint {
        let r = (point.x * point.x + point.y * point.y).squareRoot()
        guard r > 0, r.isFinite else { return point }
        let last = from.count - 1
        var mapped = to[last] + (r - from[last])
        for i in 1...last where r <= from[i] {
            let span = from[i] - from[i - 1]
            let t = span > 0 ? (r - from[i - 1]) / span : 0
            mapped = to[i - 1] + t * (to[i] - to[i - 1])
            break
        }
        let scale = mapped / r
        return BoardPoint(x: point.x * scale, y: point.y * scale)
    }
}
