import Foundation
import simd
import CoreGraphics
import CoreVideo
import DartCore

/// A plane projective transform `p' ~ M * (x, y, 1)`. Stored as three rows.
public struct Homography: Hashable, Codable, Sendable {
    public var row0: SIMD3<Double>
    public var row1: SIMD3<Double>
    public var row2: SIMD3<Double>

    public init(_ matrix: simd_double3x3) {
        let c0 = matrix.columns.0, c1 = matrix.columns.1, c2 = matrix.columns.2
        row0 = SIMD3(c0.x, c1.x, c2.x)
        row1 = SIMD3(c0.y, c1.y, c2.y)
        row2 = SIMD3(c0.z, c1.z, c2.z)
    }

    /// Internal: builds the transform from its three rows.
    init(row0: SIMD3<Double>, row1: SIMD3<Double>, row2: SIMD3<Double>) {
        self.row0 = row0
        self.row1 = row1
        self.row2 = row2
    }

    /// Normalised DLT with h33 = 1 (8x8 normal equations, Gaussian elimination with partial pivoting).
    /// Requires at least 4 pairs. Nil when the input is degenerate (pivot below 1e-12).
    public init?(from source: [SIMD2<Double>], to destination: [SIMD2<Double>]) {
        guard source.count >= 4, source.count == destination.count else { return nil }
        guard let from = Homography.hartleyNormalisation(of: source),
              let to = Homography.hartleyNormalisation(of: destination),
              Homography.isInGeneralPosition(source, normalisedBy: from),
              Homography.isInGeneralPosition(destination, normalisedBy: to) else { return nil }

        // Normal equations of the 2N x 8 system, accumulated row by row (VISION.md §4.2).
        var normal = [Double](repeating: 0, count: 64)
        var right = [Double](repeating: 0, count: 8)
        var row = [Double](repeating: 0, count: 8)
        func accumulate(_ value: Double) {
            for i in 0..<8 where row[i] != 0 {
                right[i] += row[i] * value
                for j in 0..<8 {
                    normal[i * 8 + j] += row[i] * row[j]
                }
            }
        }
        for index in source.indices {
            let x = (source[index].x - from.centre.x) * from.scale
            let y = (source[index].y - from.centre.y) * from.scale
            let u = (destination[index].x - to.centre.x) * to.scale
            let v = (destination[index].y - to.centre.y) * to.scale
            row = [x, y, 1, 0, 0, 0, -u * x, -u * y]
            accumulate(u)
            row = [0, 0, 0, x, y, 1, -v * x, -v * y]
            accumulate(v)
        }
        guard let h = LinearSolve.solve(normal, right, minPivot: 1e-12) else { return nil }

        // H = T_image⁻¹ · Ĥ · T_board, with T = [[σ, 0, −σ·cx], [0, σ, −σ·cy], [0, 0, 1]].
        let normalised = simd_double3x3(rows: [SIMD3(h[0], h[1], h[2]), SIMD3(h[3], h[4], h[5]), SIMD3(h[6], h[7], 1)])
        let boardT = simd_double3x3(rows: [
            SIMD3(from.scale, 0, -from.scale * from.centre.x),
            SIMD3(0, from.scale, -from.scale * from.centre.y),
            SIMD3(0, 0, 1),
        ])
        let imageTInverse = simd_double3x3(rows: [
            SIMD3(1 / to.scale, 0, to.centre.x),
            SIMD3(0, 1 / to.scale, to.centre.y),
            SIMD3(0, 0, 1),
        ])
        var result = Homography(imageTInverse * normalised * boardT)
        let h33 = result.row2.z
        if h33 != 0, h33.isFinite {
            result.row0 /= h33
            result.row1 /= h33
            result.row2 /= h33
            result.row2.z = 1
        }
        // A solution that cannot be inverted (collinear points on one side only) is no plane transform.
        guard result.isFinite, result.isInvertible else { return nil }
        self = result
    }

    /// Heckbert closed form: unit square (0,0),(1,0),(1,1),(0,1) to `quad`. Nil when degenerate.
    public static func unitSquare(to quad: [SIMD2<Double>]) -> Homography? {
        guard quad.count == 4 else { return nil }
        let x0 = quad[0].x, y0 = quad[0].y
        let x1 = quad[1].x, y1 = quad[1].y
        let x2 = quad[2].x, y2 = quad[2].y
        let x3 = quad[3].x, y3 = quad[3].y
        let dx1 = x1 - x2, dx2 = x3 - x2, sx = x0 - x1 + x2 - x3
        let dy1 = y1 - y2, dy2 = y3 - y2, sy = y0 - y1 + y2 - y3
        let den = dx1 * dy2 - dy1 * dx2
        guard den != 0, den.isFinite else { return nil }
        let g = (sx * dy2 - sy * dx2) / den
        let h = (dx1 * sy - dy1 * sx) / den
        let result = Homography(row0: SIMD3(x1 - x0 + g * x1, x3 - x0 + h * x3, x0),
                                row1: SIMD3(y1 - y0 + g * y1, y3 - y0 + h * y3, y0),
                                row2: SIMD3(g, h, 1))
        // Three collinear or two coincident corners give a transform that cannot be inverted.
        guard result.isFinite, result.isInvertible else { return nil }
        return result
    }

    /// Rotation of the board frame by a clockwise angle (see section 4.3, step L7).
    public static func boardRotation(clockwiseDegrees: Double) -> Homography {
        let beta = clockwiseDegrees * .pi / 180
        let c = cos(beta), s = sin(beta)
        return Homography(row0: SIMD3(c, s, 0), row1: SIMD3(-s, c, 0), row2: SIMD3(0, 0, 1))
    }

    public static let identity: Homography = Homography(row0: SIMD3(1, 0, 0), row1: SIMD3(0, 1, 0), row2: SIMD3(0, 0, 1))

    public var matrix: simd_double3x3 {
        simd_double3x3(rows: [row0, row1, row2])
    }

    /// Adjugate divided by the determinant; nil when |det| < 1e-9 after equilibration (columns, then rows, scaled to unit length).
    ///
    /// The equilibration (every column, then every row, brought to unit length) replaces one global factor
    /// (unit Frobenius norm): a board-to-image transform mixes millimetres, pixels and a perspective row, and with a
    /// single global factor the determinant of a perfectly regular 4K view falls below the limit
    /// (5e-10 for the reference pose A of VISION.md §10.2). The limit itself is the documented 1e-9.
    public var inverse: Homography? {
        guard isInvertible else { return nil }
        let a = row0.x, b = row0.y, c = row0.z
        let d = row1.x, e = row1.y, f = row1.z
        let g = row2.x, h = row2.y, i = row2.z
        let c00 = e * i - f * h, c01 = c * h - b * i, c02 = b * f - c * e
        let c10 = f * g - d * i, c11 = a * i - c * g, c12 = c * d - a * f
        let c20 = d * h - e * g, c21 = b * g - a * h, c22 = a * e - b * d
        let det = a * c00 + b * c10 + c * c20
        guard det != 0, det.isFinite else { return nil }
        let result = Homography(row0: SIMD3(c00, c01, c02) / det,
                                row1: SIMD3(c10, c11, c12) / det,
                                row2: SIMD3(c20, c21, c22) / det)
        return result.isFinite ? result : nil
    }

    public func apply(_ p: SIMD2<Double>) -> SIMD2<Double> {
        let a = row0.x * p.x + row0.y * p.y + row0.z
        let b = row1.x * p.x + row1.y * p.y + row1.z
        let w = row2.x * p.x + row2.y * p.y + row2.z
        return SIMD2(a / w, b / w)
    }

    /// Jacobian of `apply` at `p` (output units per input unit).
    public func jacobian(at p: SIMD2<Double>) -> simd_double2x2 {
        let a = row0.x * p.x + row0.y * p.y + row0.z
        let b = row1.x * p.x + row1.y * p.y + row1.z
        let w = row2.x * p.x + row2.y * p.y + row2.z
        let u = a / w, v = b / w
        return simd_double2x2(rows: [
            SIMD2((row0.x - u * row2.x) / w, (row0.y - u * row2.y) / w),
            SIMD2((row1.x - v * row2.x) / w, (row1.y - v * row2.y) / w),
        ])
    }

    /// Singular values of the Jacobian at `p`: worst- and best-direction scale.
    public func localScale(at p: SIMD2<Double>) -> (min: Double, max: Double) {
        let j = jacobian(at: p)
        let a = j.columns.0.x, c = j.columns.0.y
        let b = j.columns.1.x, d = j.columns.1.y
        // Eigenvalues of JᵀJ: λ± = (tr ± √(tr² − 4·det)) / 2.
        let trace = a * a + b * b + c * c + d * d
        let det = (a * d - b * c) * (a * d - b * c)
        let root = max(0, trace * trace - 4 * det).squareRoot()
        let low = max(0, (trace - root) / 2).squareRoot()
        let high = max(0, (trace + root) / 2).squareRoot()
        return (min: low, max: high)
    }

    /// Returns `self ∘ first` (apply `first`, then `self`).
    public func concatenating(_ first: Homography) -> Homography {
        Homography(matrix * first.matrix)
    }
}

// MARK: - Internal helpers (lot V1)

extension Homography {
    /// Closed form through four point pairs (Heckbert): `S(destination) · S(source)⁻¹`. Nil when either
    /// quadrilateral is degenerate. This is the homography of step C1, from the four handle junctions.
    static func mapping(from source: [SIMD2<Double>], to destination: [SIMD2<Double>]) -> Homography? {
        guard let fromSquare = unitSquare(to: source), let toSquare = unitSquare(to: destination),
              let back = fromSquare.inverse else { return nil }
        let result = toSquare.concatenating(back)
        return result.isFinite ? result : nil
    }

    var isFinite: Bool {
        row0.x.isFinite && row0.y.isFinite && row0.z.isFinite
            && row1.x.isFinite && row1.y.isFinite && row1.z.isFinite
            && row2.x.isFinite && row2.y.isFinite && row2.z.isFinite
    }

    /// Smallest equilibrated determinant an invertible transform may have (VISION.md §4.2: 1e-9).
    static let minimumConditionedDeterminant = 1e-9

    /// False for a transform that is singular to working precision: see `inverse`.
    var isInvertible: Bool {
        guard let conditioned = conditionedDeterminant else { return false }
        return abs(conditioned) >= Homography.minimumConditionedDeterminant
    }

    /// Determinant after equilibration: each column divided by its Euclidean length, then each row by its own.
    /// Independent of the units of the input and of the output plane and of the overall factor of the matrix.
    /// Nil when a row or a column is zero or when an entry is not finite.
    var conditionedDeterminant: Double? {
        guard isFinite else { return nil }
        var m = [row0, row1, row2]
        for column in 0..<3 {
            let length = (m[0][column] * m[0][column] + m[1][column] * m[1][column] + m[2][column] * m[2][column]).squareRoot()
            guard length > 0, length.isFinite else { return nil }
            for row in 0..<3 {
                m[row][column] /= length
            }
        }
        for row in 0..<3 {
            let length = simd_length(m[row])
            guard length > 0, length.isFinite else { return nil }
            m[row] /= length
        }
        return simd_dot(m[0], simd_cross(m[1], m[2]))
    }

    /// Smallest spread, in Hartley-normalised units (mean distance √2), that counts as two dimensions.
    private static let minimumNormalisedSpread = 1e-9

    /// False when the points do not determine a plane transform: all of them on one line (coincident points
    /// included) or, for exactly four points, three of them on one line. Measured after Hartley normalisation,
    /// so that the test does not depend on the units.
    private static func isInGeneralPosition(_ points: [SIMD2<Double>],
                                            normalisedBy normalisation: (centre: SIMD2<Double>, scale: Double)) -> Bool {
        let normalised = points.map { ($0 - normalisation.centre) * normalisation.scale }
        // Scatter matrix: its smaller eigenvalue is zero when the points are collinear.
        var sxx = 0.0, syy = 0.0, sxy = 0.0
        for p in normalised {
            sxx += p.x * p.x
            syy += p.y * p.y
            sxy += p.x * p.y
        }
        let count = Double(normalised.count)
        let root = ((sxx - syy) * (sxx - syy) + 4 * sxy * sxy).squareRoot()
        let smaller = (sxx + syy - root) / 2 / count
        guard smaller.isFinite, smaller > minimumNormalisedSpread else { return false }
        guard normalised.count == 4 else { return true }
        // Four points: every triangle must have an area.
        for skipped in 0..<4 {
            let triangle = normalised.indices.filter { $0 != skipped }.map { normalised[$0] }
            let u = triangle[1] - triangle[0], v = triangle[2] - triangle[0]
            guard abs(u.x * v.y - u.y * v.x) > minimumNormalisedSpread else { return false }
        }
        return true
    }

    /// Hartley normalisation of a point set: centroid and the factor that brings the mean distance to √2.
    /// Nil when the points coincide or a coordinate is not finite.
    private static func hartleyNormalisation(of points: [SIMD2<Double>]) -> (centre: SIMD2<Double>, scale: Double)? {
        guard !points.isEmpty else { return nil }
        var centre = SIMD2<Double>(0, 0)
        for point in points {
            centre += point
        }
        centre /= Double(points.count)
        var meanDistance = 0.0
        for point in points {
            meanDistance += simd_length(point - centre)
        }
        meanDistance /= Double(points.count)
        guard meanDistance.isFinite, meanDistance > 0 else { return nil }
        let scale = 2.0.squareRoot() / meanDistance
        guard scale.isFinite else { return nil }
        return (centre, scale)
    }
}
