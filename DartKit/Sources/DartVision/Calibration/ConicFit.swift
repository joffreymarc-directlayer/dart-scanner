import Foundation
import simd

/// Conics for the automatic locator (VISION.md §4.3, L3 and L5). Internal to DartVision (lot V2).
///
/// A conic is `A·x² + B·xy + C·y² + D·x + E·y + F = 0`, or `pᵀQp = 0` with `p = (x, y, 1)` and the symmetric
/// `Q = [[A, B/2, D/2], [B/2, C, E/2], [D/2, E/2, F]]`.
struct ConicFit: Hashable, Sendable {
    var a: Double
    var b: Double
    var c: Double
    var d: Double
    var e: Double
    var f: Double

    /// The symmetric matrix `Q`.
    var matrix: simd_double3x3 {
        simd_double3x3(rows: [SIMD3(a, b / 2, d / 2), SIMD3(b / 2, c, e / 2), SIMD3(d / 2, e / 2, f)])
    }

    init(a: Double, b: Double, c: Double, d: Double, e: Double, f: Double) {
        self.a = a
        self.b = b
        self.c = c
        self.d = d
        self.e = e
        self.f = f
    }

    /// The conic of the symmetric matrix `matrix` (its upper triangle is read).
    init(matrix m: simd_double3x3) {
        self.init(a: m[0][0], b: 2 * m[1][0], c: m[1][1], d: 2 * m[2][0], e: 2 * m[2][1], f: m[2][2])
    }

    /// The same conic scaled so that `A + C = 1`; nil when `A + C` is zero or a coefficient is not finite.
    var normalised: ConicFit? {
        let sum = a + c
        guard sum != 0, sum.isFinite else { return nil }
        let result = ConicFit(a: a / sum, b: b / sum, c: c / sum, d: d / sum, e: e / sum, f: f / sum)
        return [result.a, result.b, result.c, result.d, result.e, result.f].allSatisfy(\.isFinite) ? result : nil
    }

    /// `B² − 4AC < 0`.
    var isEllipse: Bool {
        b * b - 4 * a * c < 0
    }

    /// `pᵀQp` at an image point.
    func value(at p: SIMD2<Double>) -> Double {
        a * p.x * p.x + b * p.x * p.y + c * p.y * p.y + d * p.x + e * p.y + f
    }

    /// Sampson distance `|pᵀQp| / (2·‖(Qp)xy‖)`, in the units of the points.
    func sampsonDistance(_ p: SIMD2<Double>) -> Double {
        let gx = 2 * a * p.x + b * p.y + d
        let gy = b * p.x + 2 * c * p.y + e
        let norm = (gx * gx + gy * gy).squareRoot()
        guard norm > 0 else { return .infinity }
        // |pᵀQp| / (2·‖(Qp)xy‖) with (Qp)xy = (gx, gy) / 2.
        return abs(value(at: p)) / norm
    }

    /// Centre, semi-axes (larger first) and area of an ellipse; nil for any other conic.
    var ellipse: (centre: SIMD2<Double>, major: Double, minor: Double, area: Double)? {
        guard isEllipse else { return nil }
        let det = 4 * a * c - b * b
        let centre = SIMD2((b * e - 2 * c * d) / det, (b * d - 2 * a * e) / det)
        let k = -value(at: centre)
        // Eigenvalues of [[A, B/2], [B/2, C]].
        let mean = (a + c) / 2
        let radius = (((a - c) / 2) * ((a - c) / 2) + (b / 2) * (b / 2)).squareRoot()
        let l1 = mean - radius, l2 = mean + radius
        let s1 = k / l1, s2 = k / l2
        guard s1 > 0, s2 > 0, s1.isFinite, s2.isFinite else { return nil }
        let axis1 = s1.squareRoot(), axis2 = s2.squareRoot()
        return (centre, max(axis1, axis2), min(axis1, axis2), Double.pi * axis1 * axis2)
    }

    /// Linear fit with the normalisation `A + C = 1` (VISION.md §4.3, L3): after a Hartley normalisation of the
    /// points, least squares on `A(x² − y²) + B·xy + D·x + E·y + F = −y²` by the 5×5 normal equations, then back to
    /// image units, scaled again to `A + C = 1`. Nil with fewer than five points or a singular system.
    static func fit(_ points: [SIMD2<Double>]) -> ConicFit? {
        guard points.count >= 5 else { return nil }
        var centre = SIMD2<Double>(0, 0)
        for p in points { centre += p }
        centre /= Double(points.count)
        var spread = 0.0
        for p in points { spread += simd_length(p - centre) }
        spread /= Double(points.count)
        guard spread > 0, spread.isFinite else { return nil }
        let scale = 2.0.squareRoot() / spread
        var rows: [[Double]] = []
        var values: [Double] = []
        rows.reserveCapacity(points.count)
        values.reserveCapacity(points.count)
        for p in points {
            let x = (p.x - centre.x) * scale, y = (p.y - centre.y) * scale
            rows.append([x * x - y * y, x * y, x, y, 1])
            values.append(-y * y)
        }
        guard let solution = LinearSolve.leastSquares(rows: rows, values: values, unknowns: 5) else { return nil }
        let normalisedConic = ConicFit(a: solution[0], b: solution[1], c: 1 - solution[0], d: solution[2],
                                       e: solution[3], f: solution[4])
        // Q = Tᵀ·Q'·T with T = [[σ, 0, −σ·cx], [0, σ, −σ·cy], [0, 0, 1]].
        let t = simd_double3x3(rows: [SIMD3(scale, 0, -scale * centre.x), SIMD3(0, scale, -scale * centre.y), SIMD3(0, 0, 1)])
        let q = t.transpose * normalisedConic.matrix * t
        return ConicFit(matrix: q).normalised
    }

    /// L3: fits, then twice drops the points whose Sampson distance exceeds `tolerance` and fits the rest again.
    /// Returns the conic and, for every input point, whether it was kept by the last round.
    static func robustFit(_ points: [SIMD2<Double>], tolerance: Double, rounds: Int = 2) -> (conic: ConicFit, kept: [Bool])? {
        guard var conic = fit(points) else { return nil }
        var kept = [Bool](repeating: true, count: points.count)
        for _ in 0..<max(0, rounds) {
            kept = points.map { conic.sampsonDistance($0) <= tolerance }
            let inliers = zip(points, kept).filter { $0.1 }.map { $0.0 }
            guard let refitted = fit(inliers) else { return nil }
            conic = refitted
        }
        kept = points.map { conic.sampsonDistance($0) <= tolerance }
        return (conic, kept)
    }

    /// Intersections of the line `p + τ·d` (homogeneous) with the conic: the roots of
    /// `τ²·dᵀQd + 2τ·dᵀQp + pᵀQp = 0` (VISION.md §4.3, L5). Nil when the line misses the conic.
    static func intersections(_ q: simd_double3x3, point p: SIMD3<Double>, direction d: SIMD3<Double>)
        -> (SIMD3<Double>, SIMD3<Double>)? {
        let qa = simd_dot(d, q * d), qb = simd_dot(d, q * p), qc = simd_dot(p, q * p)
        guard qa != 0, qa.isFinite else { return nil }
        let discriminant = qb * qb - qa * qc
        guard discriminant >= 0, discriminant.isFinite else { return nil }
        let root = discriminant.squareRoot()
        let t1 = (-qb - root) / qa, t2 = (-qb + root) / qa
        return (p + t1 * d, p + t2 * d)
    }

    /// The image point of a homogeneous point; nil at infinity.
    static func point(_ h: SIMD3<Double>) -> SIMD2<Double>? {
        guard h.z != 0, h.z.isFinite else { return nil }
        let p = SIMD2(h.x / h.z, h.y / h.z)
        return p.x.isFinite && p.y.isFinite ? p : nil
    }
}
