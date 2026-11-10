import Foundation
import simd
import CoreGraphics
import CoreVideo
import DartCore

public struct SyntheticDartStyle: Hashable, Sendable {
    public var point: SIMD3<UInt8>
    public var barrel: SIMD3<UInt8>
    public var shaft: SIMD3<UInt8>
    public var flight: SIMD3<UInt8>
    public init(point: SIMD3<UInt8>, barrel: SIMD3<UInt8>, shaft: SIMD3<UInt8>, flight: SIMD3<UInt8>) {
        self.point = point
        self.barrel = barrel
        self.shaft = shaft
        self.flight = flight
    }
    /// Silver point, dark tungsten barrel, black shaft, blue flight.
    public static let steelTungsten: SyntheticDartStyle = SyntheticDartStyle(
        point: SIMD3(200, 200, 205), barrel: SIMD3(95, 95, 100), shaft: SIMD3(22, 22, 24), flight: SIMD3(40, 80, 200))
    /// Silver point, brass barrel, white shaft, red flight.
    public static let brass: SyntheticDartStyle = SyntheticDartStyle(
        point: SIMD3(200, 200, 205), barrel: SIMD3(190, 150, 60), shaft: SIMD3(230, 230, 230), flight: SIMD3(220, 40, 40))
    /// Black point, barrel and shaft: the case that breaks naive differencing on black sectors.
    public static let allBlack: SyntheticDartStyle = SyntheticDartStyle(
        point: SIMD3(25, 25, 25), barrel: SIMD3(25, 25, 25), shaft: SIMD3(22, 22, 24), flight: SIMD3(230, 200, 40))
}

public struct SyntheticDart: Hashable, Sendable {
    /// Entry point on the board plane, metric mm.
    public var tip: BoardPoint
    /// Tail-up lean in degrees (positive: the flight is higher than the tip).
    public var leanUpDegrees: Double
    public var leanSideDegrees: Double
    public var style: SyntheticDartStyle
    public init(tip: BoardPoint, leanUpDegrees: Double = 8, leanSideDegrees: Double = 0, style: SyntheticDartStyle = .steelTungsten) {
        self.tip = tip
        self.leanUpDegrees = leanUpDegrees
        self.leanSideDegrees = leanSideDegrees
        self.style = style
    }
}

// MARK: - Geometry (lot V1, internal)

extension SyntheticDart {
    /// Dimensions of the rendered dart, mm (VISION.md §10.1). Lengths are measured along the axis from the
    /// entry point; negative values are inside the board.
    enum Shape {
        /// The point: 22 mm visible plus 8 mm stuck in the board, diameter 2.3.
        static let pointStart: Double = -8
        static let pointEnd: Double = 22
        static let pointRadius: Double = 1.15
        /// The barrel: 50 mm, diameter 6.8.
        static let barrelEnd: Double = 72
        static let barrelRadius: Double = 3.4
        /// The shaft: 43 mm, diameter 5.2.
        static let shaftEnd: Double = 115
        static let shaftRadius: Double = 2.6
        /// The flight: two perpendicular plates of 40 x 34 mm, 0.3 mm thick, over the end of the shaft.
        static let flightStart: Double = 110
        static let flightEnd: Double = 150
        static let flightHalfWidth: Double = 17
        static let flightHalfThickness: Double = 0.15
        /// Total length outside the board.
        static let visibleLength: Double = 150
    }

    /// Unit vector from the entry point along the dart, out of the board: `(tan side, tan up, 1)` normalised.
    /// A perpendicular dart points along +z; a positive `leanUpDegrees` raises the flight towards +y (the 20),
    /// a positive `leanSideDegrees` moves it towards +x (the 6). Leans are limited to ±85 degrees.
    var axis: SIMD3<Double> {
        let up = min(85, max(-85, leanUpDegrees.isFinite ? leanUpDegrees : 0)) * .pi / 180
        let side = min(85, max(-85, leanSideDegrees.isFinite ? leanSideDegrees : 0)) * .pi / 180
        return simd_normalize(SIMD3(tan(side), tan(up), 1))
    }

    /// The dart moved by `offset` mm (board frame). Used by the script for a dart in flight; a dart whose entry
    /// point leaves the board plane is rendered through `SyntheticDartSolid` only.
    func solid(offset: SIMD3<Double> = SIMD3(0, 0, 0)) -> SyntheticDartSolid {
        SyntheticDartSolid(dart: self, offset: offset)
    }
}

/// One dart as the ray caster sees it: an axis, three solid cylinders and two thin plates.
///
/// A ray (or a shadow segment) is exactly intersected with each part; the part it enters first wins, which also
/// gives the exact occlusion between darts (VISION.md §10.1). The point continues 8 mm into the board: the
/// board plane cuts it, since every ray stops there.
struct SyntheticDartSolid: Sendable {
    /// Entry point (the origin of the axis), board frame.
    let ox: Double, oy: Double, oz: Double
    /// Unit axis, from the entry point to the flight.
    let ax: Double, ay: Double, az: Double
    /// Unit vectors across the axis: the planes of the two flight plates.
    let ux: Double, uy: Double, uz: Double
    let vx: Double, vy: Double, vz: Double
    /// Packed colours (`r | g << 8 | b << 16`).
    let pointColour: UInt32
    let barrelColour: UInt32
    let shaftColour: UInt32
    let flightColour: UInt32

    init(dart: SyntheticDart, offset: SIMD3<Double>) {
        let axis = dart.axis
        ox = dart.tip.x + offset.x
        oy = dart.tip.y + offset.y
        oz = offset.z
        ax = axis.x; ay = axis.y; az = axis.z
        // First plate: the plane of the axis and of the board's "up".
        var across = SIMD3<Double>(0, 1, 0) - axis.y * axis
        if simd_length(across) < 1e-9 { across = SIMD3(1, 0, 0) - axis.x * axis }
        across = simd_normalize(across)
        let other = simd_cross(axis, across)
        ux = across.x; uy = across.y; uz = across.z
        vx = other.x; vy = other.y; vz = other.z
        pointColour = SyntheticDartSolid.pack(dart.style.point)
        barrelColour = SyntheticDartSolid.pack(dart.style.barrel)
        shaftColour = SyntheticDartSolid.pack(dart.style.shaft)
        flightColour = SyntheticDartSolid.pack(dart.style.flight)
    }

    static func pack(_ colour: SIMD3<UInt8>) -> UInt32 {
        UInt32(colour.x) | UInt32(colour.y) << 8 | UInt32(colour.z) << 16
    }

    /// Point of the axis at `distance` mm from the entry point.
    func axisPoint(_ distance: Double) -> SIMD3<Double> {
        SIMD3(ox + distance * ax, oy + distance * ay, oz + distance * az)
    }

    /// First intersection of the segment `p + t·d`, `0 <= t <= limit`, with the three cylinders (point, barrel,
    /// shaft), each closed by its two end discs. Returns the parameter where the segment enters the nearest one,
    /// or a negative value when it misses them all; `colour` receives the colour of that part. A segment that
    /// starts inside a part enters it at 0.
    @inline(__always)
    func hitBody(px: Double, py: Double, pz: Double, dx: Double, dy: Double, dz: Double, limit: Double,
                 colour: inout UInt32) -> Double {
        let wx = px - ox, wy = py - oy, wz = pz - oz
        // Along the axis: s(t) = ps + t·ds. Across it: q + t·e, whose squared length is a·t² + 2·b·t + c.
        let ps = wx * ax + wy * ay + wz * az, ds = dx * ax + dy * ay + dz * az
        let qx = wx - ps * ax, qy = wy - ps * ay, qz = wz - ps * az
        let ex = dx - ds * ax, ey = dy - ds * ay, ez = dz - ds * az
        let a = ex * ex + ey * ey + ez * ez, b = qx * ex + qy * ey + qz * ez, c = qx * qx + qy * qy + qz * qz
        let shape = SyntheticDart.Shape.self
        var nearest = -1.0
        let point = SyntheticDartSolid.cylinderEntry(ps: ps, ds: ds, a: a, b: b, c: c, from: shape.pointStart,
                                                     to: shape.pointEnd, radius: shape.pointRadius, limit: limit)
        if point >= 0 {
            nearest = point
            colour = pointColour
        }
        let barrel = SyntheticDartSolid.cylinderEntry(ps: ps, ds: ds, a: a, b: b, c: c, from: shape.pointEnd,
                                                      to: shape.barrelEnd, radius: shape.barrelRadius, limit: limit)
        if barrel >= 0 && (nearest < 0 || barrel < nearest) {
            nearest = barrel
            colour = barrelColour
        }
        let shaft = SyntheticDartSolid.cylinderEntry(ps: ps, ds: ds, a: a, b: b, c: c, from: shape.barrelEnd,
                                                     to: shape.shaftEnd, radius: shape.shaftRadius, limit: limit)
        if shaft >= 0 && (nearest < 0 || shaft < nearest) {
            nearest = shaft
            colour = shaftColour
        }
        return nearest
    }

    /// Entry parameter, in `[0, limit]`, of a segment into the solid cylinder of radius `radius` between the
    /// axial positions `from` and `to`; negative when the segment misses it. The segment is described as in
    /// `hitBody`: axial position `ps + t·ds`, squared distance to the axis `a·t² + 2·b·t + c`.
    @inline(__always)
    private static func cylinderEntry(ps: Double, ds: Double, a: Double, b: Double, c: Double, from: Double, to: Double,
                                      radius: Double, limit: Double) -> Double {
        var enter = 0.0, leave = limit
        let k = c - radius * radius
        if a > 0 {
            let discriminant = b * b - a * k
            if discriminant < 0 { return -1 }
            let root = discriminant.squareRoot()
            let first = (-b - root) / a, last = (-b + root) / a
            if first > enter { enter = first }
            if last < leave { leave = last }
            if enter > leave { return -1 }
        } else if k > 0 {
            // Parallel to the axis and outside the radius.
            return -1
        }
        if ds != 0 {
            let t0 = (from - ps) / ds, t1 = (to - ps) / ds
            let near = t0 < t1 ? t0 : t1, far = t0 < t1 ? t1 : t0
            if near > enter { enter = near }
            if far < leave { leave = far }
        } else if ps < from || ps > to {
            return -1
        }
        return enter <= leave ? enter : -1
    }

    /// Closest hit of the segment `p + t·d`, `0 <= t <= limit`, with the two flight plates; negative when missed.
    @inline(__always)
    func hitFlight(px: Double, py: Double, pz: Double, dx: Double, dy: Double, dz: Double, limit: Double) -> Double {
        // The segment in the frame of the dart: along the axis, across in the two plate planes.
        let wx = px - ox, wy = py - oy, wz = pz - oz
        let ps = wx * ax + wy * ay + wz * az, ds = dx * ax + dy * ay + dz * az
        let pu = wx * ux + wy * uy + wz * uz, du = dx * ux + dy * uy + dz * uz
        let pv = wx * vx + wy * vy + wz * vz, dv = dx * vx + dy * vy + dz * vz
        let wide = SyntheticDart.Shape.flightHalfWidth, thin = SyntheticDart.Shape.flightHalfThickness
        let first = SyntheticDartSolid.slabEntry(ps, ds, pu, du, pv, dv, wide, thin, limit)
        let second = SyntheticDartSolid.slabEntry(ps, ds, pu, du, pv, dv, thin, wide, limit)
        if first < 0 { return second }
        if second < 0 { return first }
        return first < second ? first : second
    }

    /// Entry parameter of a segment into the box `flightStart...flightEnd` x `±halfU` x `±halfV`; negative when missed.
    @inline(__always)
    private static func slabEntry(_ ps: Double, _ ds: Double, _ pu: Double, _ du: Double, _ pv: Double, _ dv: Double,
                                  _ halfU: Double, _ halfV: Double, _ limit: Double) -> Double {
        var enter = 0.0, leave = limit
        // Along the axis.
        if ds > 1e-300 || ds < -1e-300 {
            let t0 = (SyntheticDart.Shape.flightStart - ps) / ds, t1 = (SyntheticDart.Shape.flightEnd - ps) / ds
            let near = t0 < t1 ? t0 : t1, far = t0 < t1 ? t1 : t0
            if near > enter { enter = near }
            if far < leave { leave = far }
        } else if ps < SyntheticDart.Shape.flightStart || ps > SyntheticDart.Shape.flightEnd {
            return -1
        }
        if enter > leave { return -1 }
        if du > 1e-300 || du < -1e-300 {
            let t0 = (-halfU - pu) / du, t1 = (halfU - pu) / du
            let near = t0 < t1 ? t0 : t1, far = t0 < t1 ? t1 : t0
            if near > enter { enter = near }
            if far < leave { leave = far }
        } else if pu < -halfU || pu > halfU {
            return -1
        }
        if enter > leave { return -1 }
        if dv > 1e-300 || dv < -1e-300 {
            let t0 = (-halfV - pv) / dv, t1 = (halfV - pv) / dv
            let near = t0 < t1 ? t0 : t1, far = t0 < t1 ? t1 : t0
            if near > enter { enter = near }
            if far < leave { leave = far }
        } else if pv < -halfV || pv > halfV {
            return -1
        }
        return enter > leave ? -1 : enter
    }
}

/// A capsule of the plane `z = constant` that contains the projection of a part of a dart from a point source
/// (the camera centre, or the lamp): a cheap test that spares the exact one for almost every ray.
struct SyntheticFootprint: Sendable {
    var x0: Double, y0: Double, x1: Double, y1: Double
    var radius: Double
    /// False when the projection is unbounded (a part at or above the source): the exact test always runs.
    var bounded: Bool

    static let everywhere = SyntheticFootprint(x0: 0, y0: 0, x1: 0, y1: 0, radius: .infinity, bounded: false)

    @inline(__always)
    func contains(x: Double, y: Double) -> Bool {
        if !bounded { return true }
        let ex = x1 - x0, ey = y1 - y0
        let px = x - x0, py = y - y0
        let length2 = ex * ex + ey * ey
        var t = length2 > 0 ? (px * ex + py * ey) / length2 : 0
        if t < 0 { t = 0 } else if t > 1 { t = 1 }
        let qx = px - t * ex, qy = py - t * ey
        return qx * qx + qy * qy <= radius * radius
    }

    /// True when `(x, y)` is within `margin` mm of the footprint.
    @inline(__always)
    func isWithin(_ margin: Double, x: Double, y: Double) -> Bool {
        if !bounded { return true }
        let ex = x1 - x0, ey = y1 - y0
        let px = x - x0, py = y - y0
        let length2 = ex * ex + ey * ey
        var t = length2 > 0 ? (px * ex + py * ey) / length2 : 0
        if t < 0 { t = 0 } else if t > 1 { t = 1 }
        let qx = px - t * ex, qy = py - t * ey
        let reach = radius + margin
        return qx * qx + qy * qy <= reach * reach
    }

    /// Axis-aligned bounding box in the plane.
    var box: (minX: Double, minY: Double, maxX: Double, maxY: Double) {
        (min(x0, x1) - radius, min(y0, y1) - radius, max(x0, x1) + radius, max(y0, y1) + radius)
    }

    /// Footprint on the plane `z = plane` of the sphere-swept segment `from → to` of radius `radius`, seen from `source`.
    static func project(from: SIMD3<Double>, to: SIMD3<Double>, radius: Double, source: SIMD3<Double>,
                        plane: Double) -> SyntheticFootprint {
        let drop = source.z - plane
        guard drop > 0 else { return .everywhere }
        var largest = 0.0
        var ends: [SIMD2<Double>] = []
        let samples = 8
        for index in 0...samples {
            let q = from + (to - from) * (Double(index) / Double(samples))
            let height = source.z - q.z
            // The sphere must be entirely below the source.
            guard height > radius * 1.05 + 1e-6 else { return .everywhere }
            let toCentre = q - source
            let distance = simd_length(toCentre)
            guard distance > radius * 1.05 else { return .everywhere }
            // Cone of the sphere: half-angle α around a direction at γ from the plane normal.
            let cosGamma = height / distance
            let sinGamma = max(0, 1 - cosGamma * cosGamma).squareRoot()
            let sinAlpha = radius / distance
            let cosAlpha = max(0, 1 - sinAlpha * sinAlpha).squareRoot()
            let cosSum = cosGamma * cosAlpha - sinGamma * sinAlpha
            guard cosSum > 0.05 else { return .everywhere }
            // Far edge of the cone on the plane, measured from the image of the centre.
            let reach = radius * drop / (height * cosSum)
            if reach > largest { largest = reach }
            if index == 0 || index == samples {
                let k = drop / height
                ends.append(SIMD2(source.x + toCentre.x * k, source.y + toCentre.y * k))
            }
        }
        guard ends.count == 2, largest.isFinite else { return .everywhere }
        return SyntheticFootprint(x0: ends[0].x, y0: ends[0].y, x1: ends[1].x, y1: ends[1].y,
                                  radius: largest * 1.05 + 0.05, bounded: true)
    }
}
