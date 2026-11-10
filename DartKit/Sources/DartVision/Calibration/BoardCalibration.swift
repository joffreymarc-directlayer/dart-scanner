import Foundation
import simd
import CoreGraphics
import CoreVideo
import DartCore

public enum CalibrationIssue: String, Codable, Sendable, CaseIterable {
    // Blocking: "Valider" is disabled.
    case handlesMirrored, quadNotConvex, horizonCrossesBoard, boardOutOfFrame, resolutionTooLow
    // Advisory: lowers the grade, scanning stays possible.
    case resolutionLow, viewTooFrontal, viewTooOblique, dartMarginCutOff
    case sectorPhaseMismatch, edgesNotFound, refinementRejected, intrinsicsApproximate
    public var isBlocking: Bool {
        switch self {
        case .handlesMirrored, .quadNotConvex, .horizonCrossesBoard, .boardOutOfFrame, .resolutionTooLow: return true
        default: return false
        }
    }
}

public struct CalibrationQuality: Hashable, Codable, Sendable {
    public enum Grade: Int, Codable, Sendable, Comparable {
        case poor, fair, good
        public static func < (lhs: Grade, rhs: Grade) -> Bool { lhs.rawValue < rhs.rawValue }
    }
    public var grade: Grade
    /// RMS of inlier edge residuals in mm; nil when no still was assessed (`preview`).
    public var edgeResidualRMS: Double?
    public var edgeInlierFraction: Double?
    public var measuredFraction: Double?
    public var refinementApplied: Bool
    /// Largest handle move made by the refinement, px.
    public var maxHandleShift: Double
    /// Worst-direction scale over the bull and 8 points on r = 170, px/mm.
    public var minPixelsPerMillimetre: Double
    /// Angle between the board normal and the ray to the bull, degrees.
    public var viewAngleDegrees: Double
    /// `(|F| - 170) / D`: below 0.16 darts near the camera side are seen end-on.
    public var minTanObliquity: Double
    /// `(|F| + 170) / D`: above 0.84 a hidden millimetre of point costs almost a millimetre.
    public var maxTanObliquity: Double
    /// Most actionable first.
    public var issues: [CalibrationIssue]
    /// `max(0.3, edgeResidualRMS)`, shown as "Précision estimée ± x mm".
    ///
    /// Without an assessed still (`preview`) the residual is unknown: the figure is then 1 mm, the accuracy one can
    /// expect from four handles placed by hand (VISION.md §4.6: 1 to 3 px of placement noise at about 2 px/mm).
    public var estimatedAccuracy: Double {
        guard let residual = edgeResidualRMS, residual.isFinite else { return 1 }
        return max(0.3, residual)
    }
}

/// Overlay geometry in image pixels; DartUI maps it into the preview.
public struct BoardWireframe: Sendable {
    /// Six closed polylines (ring radii), innermost first.
    public var rings: [[ImagePoint]]
    /// Twenty segments from the outer bull to the outer double wire.
    public var wires: [[ImagePoint]]
    public var numberAnchors: [(number: Int, point: ImagePoint)]
    /// Closed polyline of the region that must stay in view (board disc plus the dart margin).
    public var safeFrame: [ImagePoint]
}

/// The result of calibration. Valid only for frames of `imageSize` delivered with `rotationDegrees`.
public struct BoardCalibration: Hashable, Codable, Sendable, Identifiable {
    /// Digest of the content (section 4.1): equal inputs give an equal calibration, bit for bit.
    public let id: UUID
    /// Always the reference date: the calibrator takes no clock (section 4.1).
    public let createdAt: Date
    public let imageSize: PixelSize
    public let rotationDegrees: Int
    /// Handles as the user (or the locator) placed them.
    public let userHandles: CalibrationHandles
    /// Handles after refinement; equal to `userHandles` when the refinement was rejected.
    public let handles: CalibrationHandles
    /// H: metric board mm to image px.
    public let boardToImage: Homography
    /// G = H⁻¹.
    public let imageToBoard: Homography
    public let ringRadii: RingRadii
    /// Height of the wires above the sisal that this calibration compensates, mm (section 4.6, C6). 0 = no compensation.
    public let wireHeight: Double
    public let intrinsics: CameraIntrinsics
    public let pose: CameraPose
    public let quality: CalibrationQuality
    /// Nominal board coordinates of an image point: G, then the wire-height correction
    /// `pose.removingParallax(from:height: -wireHeight)`, then `ringRadii.toNominal`.
    public func boardPoint(for point: ImagePoint) -> BoardPoint {
        let metric = imageToBoard.apply(SIMD2(point.x, point.y))
        var board = BoardPoint(x: metric.x, y: metric.y)
        if wireHeight != 0 {
            board = pose.removingParallax(from: board, height: -wireHeight)
        }
        return ringRadii.toNominal(board)
    }

    /// Image position of a nominal board point (exact inverse of `boardPoint(for:)`).
    public func imagePoint(for point: BoardPoint) -> ImagePoint {
        var board = ringRadii.fromNominal(point)
        if wireHeight != 0 {
            board = pose.apparentPosition(of: board, height: -wireHeight)
        }
        let image = boardToImage.apply(SIMD2(board.x, board.y))
        return ImagePoint(x: image.x, y: image.y)
    }

    /// Scored hit under an image point: the tap test of the setup screen and tap-the-tips in photo mode.
    public func hit(at point: ImagePoint, board: BoardGeometry) -> Hit {
        board.hit(at: boardPoint(for: point))
    }

    /// Source px/mm at a nominal board point (worst and best direction).
    ///
    /// Singular values of the Jacobian of `imagePoint(for:)` at `point`: the Jacobian of `H` at the metric point,
    /// times the wire-height homothety `D / (D + s)` about `F`, times the Jacobian of the radial remap
    /// `ringRadii.fromNominal` (slope of the piece along the radius, `r_metric / r_nominal` across it).
    public func localScale(at point: BoardPoint) -> (min: Double, max: Double) {
        let nominal = SIMD2(point.x, point.y)
        let radius = simd_length(nominal)
        let remap = BoardCalibration.radialRemap(radius: radius, from: RingRadii.nominal.knots, to: ringRadii.knots)
        let direction = radius > 0 && radius.isFinite ? nominal / radius : SIMD2(0, 1)
        let normal = SIMD2(-direction.y, direction.x)
        // J_remap = slope · r̂r̂ᵀ + stretch · t̂t̂ᵀ.
        let radial = simd_double2x2(rows: [remap.slope * direction.x * direction, remap.slope * direction.y * direction])
        let tangential = simd_double2x2(rows: [remap.stretch * normal.x * normal, remap.stretch * normal.y * normal])
        var jacobian = radial + tangential
        var metric = ringRadii.fromNominal(point)
        if wireHeight != 0 {
            let distance = pose.distance
            let factor = distance / (distance + wireHeight)
            jacobian = factor * jacobian
            metric = pose.apparentPosition(of: metric, height: -wireHeight)
        }
        let total = boardToImage.jacobian(at: SIMD2(metric.x, metric.y)) * jacobian
        return BoardCalibration.singularValues(of: total)
    }

    /// The overlay (VISION.md §4.7): six rings of `ringSegments` sides, twenty wires, four numbers, and the region
    /// that must stay in view. Everything lies on the plane of the wires, through `H`: the wire-height correction
    /// moves scored points only, never the drawing (§4.6, C6).
    ///
    /// - `rings`: the six metric ring radii, innermost first; each polyline has `ringSegments + 1` points, the last
    ///   repeating the first, so that it can be drawn closed as it is (at least 3 segments).
    /// - `wires`: twenty two-point segments, from the outer bull to the outer double wire, at `9° + 18°·m`.
    /// - `numberAnchors`: 20, 6, 3 and 11 at the middle of their sectors, 198 mm from the centre (in the number ring),
    ///   next to the handles.
    /// - `safeFrame`: the boundary of the board disc swept by the dart margin away from the camera foot point
    ///   (`CalibrationParameters.dartMargin`, the zone of the `dartMarginCutOff` check), closed like the rings.
    public func wireframe(ringSegments: Int) -> BoardWireframe {
        let segments = min(max(3, ringSegments), 4096)
        func image(_ p: SIMD2<Double>) -> ImagePoint {
            let q = boardToImage.apply(p)
            return ImagePoint(x: q.x, y: q.y)
        }
        func polyline(_ point: (Double) -> SIMD2<Double>) -> [ImagePoint] {
            (0...segments).map { index in
                let angle = 2 * Double.pi * Double(index % segments) / Double(segments)
                return image(point(angle))
            }
        }
        let rings = ringRadii.all.map { radius in
            polyline { radius * SIMD2(sin($0), cos($0)) }
        }
        let wires = (0..<20).map { wire -> [ImagePoint] in
            let a = (9 + 18 * Double(wire)) * .pi / 180
            let direction = SIMD2(sin(a), cos(a))
            return [image(ringRadii.outerBull * direction), image(ringRadii.doubleOuter * direction)]
        }
        let anchorRadius = 198.0
        let numberAnchors: [(number: Int, point: ImagePoint)] = [
            (20, image(SIMD2(0, anchorRadius))), (6, image(SIMD2(anchorRadius, 0))),
            (3, image(SIMD2(0, -anchorRadius))), (11, image(SIMD2(-anchorRadius, 0))),
        ]
        let zone = CalibrationDartZone(footPoint: pose.footPoint, margin: CalibrationParameters().dartMargin)
        let safeFrame = polyline { zone.boundary(at: $0) }
        return BoardWireframe(rings: rings, wires: wires, numberAnchors: numberAnchors, safeFrame: safeFrame)
    }
}

extension BoardCalibration {
    /// Value and slopes of the piecewise-linear radial remap that sends the knots `from` onto the knots `to`, at
    /// radius `radius` of the `from` side: `slope` along the radius, `stretch = mapped / radius` across it (the
    /// slope of the first piece at the centre). The same pieces as `RingRadii.toNominal` and `fromNominal`.
    static func radialRemap(radius: Double, from: [Double], to: [Double]) -> (slope: Double, stretch: Double) {
        let last = from.count - 1
        guard last >= 1, from.count == to.count, radius.isFinite else { return (1, 1) }
        var slope = 1.0
        var mapped = to[last] + (radius - from[last])
        for i in 1...last where radius <= from[i] {
            let span = from[i] - from[i - 1]
            slope = span > 0 ? (to[i] - to[i - 1]) / span : 1
            let t = span > 0 ? (radius - from[i - 1]) / span : 0
            mapped = to[i - 1] + t * (to[i] - to[i - 1])
            break
        }
        let stretch = radius > 0 ? mapped / radius : slope
        return (slope, stretch)
    }

    /// Singular values of a 2×2 matrix, smaller first (VISION.md §4.2, local scale).
    static func singularValues(of matrix: simd_double2x2) -> (min: Double, max: Double) {
        let a = matrix.columns.0.x, c = matrix.columns.0.y
        let b = matrix.columns.1.x, d = matrix.columns.1.y
        let trace = a * a + b * b + c * c + d * d
        let det = (a * d - b * c) * (a * d - b * c)
        let root = max(0, trace * trace - 4 * det).squareRoot()
        return (max(0, (trace - root) / 2).squareRoot(), max(0, (trace + root) / 2).squareRoot())
    }
}

/// The zone where darts can appear (lot V2, internal): tips on the board disc `r ≤ 170`, bodies up to `margin` mm
/// beyond their tip, away from the camera foot point `F` (VISION.md §2.1). A point `q` is inside when `|q| ≤ 170`, or
/// when the segment `{q − λ·unit(q − F), 0 ≤ λ ≤ margin}` comes within 170 mm of the centre: the rule of the
/// rectifier's region of interest (`BoardRectifier`), with the tips on the scoring area.
struct CalibrationDartZone: Sendable {
    let footPoint: BoardPoint
    let margin: Double
    static let tipRadius: Double = 170

    func contains(_ q: SIMD2<Double>) -> Bool {
        let tip = CalibrationDartZone.tipRadius
        let radiusSquared = simd_length_squared(q)
        if radiusSquared <= tip * tip { return true }
        let away = q - SIMD2(footPoint.x, footPoint.y)
        let length = simd_length(away)
        guard length > 0, length.isFinite, margin > 0 else { return false }
        let along = simd_dot(q, away) / length
        let lambda = min(max(along, 0), margin)
        return radiusSquared - 2 * lambda * along + lambda * lambda <= tip * tip
    }

    /// Farthest point of the zone along the clockwise angle `angle` from the centre (searched by 0.5 mm steps
    /// outwards from the board edge).
    func boundary(at angle: Double) -> SIMD2<Double> {
        let direction = SIMD2(sin(angle), cos(angle))
        let tip = CalibrationDartZone.tipRadius
        var radius = tip
        var probe = tip
        let outer = tip + max(0, margin)
        while probe <= outer {
            if contains(probe * direction) { radius = probe }
            probe += 0.5
        }
        return radius * direction
    }
}
