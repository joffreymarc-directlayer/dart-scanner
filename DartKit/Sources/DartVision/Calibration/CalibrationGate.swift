import Foundation
import simd
import DartCore

/// C1 — closed-form homography and sanity gate, with the pose of C7 and the grade of C8 (VISION.md §4.4, §4.7).
/// Internal to DartVision (lot V2).
struct CalibrationGate: Sendable {
    /// H: metric board mm to image px, closed form of the four handles.
    var boardToImage: Homography
    /// G = H⁻¹.
    var imageToBoard: Homography
    var intrinsics: CameraIntrinsics
    var pose: CameraPose
    /// Worst-direction scale over the bull and the eight points of r = 170 at multiples of 45 degrees, px/mm.
    var minPixelsPerMillimetre: Double
    /// `atan(|F| / D)`, degrees.
    var viewAngleDegrees: Double
    /// `(|F| − 170) / D`.
    var minTanObliquity: Double
    /// `(|F| + 170) / D`.
    var maxTanObliquity: Double
    /// Fraction of the dart zone (board disc swept by the dart margin) that lies inside the image.
    var dartZoneVisibleFraction: Double
    /// Advisory issues of the geometry: resolution, view, dart margin, approximate intrinsics.
    var advisories: [CalibrationIssue]

    /// At least this fraction of the dart zone must be in the image (VISION.md §2.3, `dartMarginCutOff`).
    static let minDartZoneFraction = 0.9
    /// The sanity checks of C1 look at the board up to this radius for the horizon, mm.
    static let horizonRadius: Double = 230
    /// … and need this disc inside the image, mm.
    static let frameRadius: Double = 180

    /// Runs C1 on `handles` and, when it passes, C7 (pose) with `intrinsics` (or self-calibrated, or assumed).
    ///
    /// - `.degenerateHandles`: not four finite handles, two of them coincide or three are collinear.
    /// - `.rejected(issues)`: every blocking issue found, in declaration order: `handlesMirrored` (anticlockwise
    ///   handles, or a pose behind the board), `quadNotConvex`, `horizonCrossesBoard` (`w` changes sign within
    ///   r = 230), `boardOutOfFrame` (the disc r = 180 leaves the image), `resolutionTooLow`.
    static func evaluate(handles: CalibrationHandles, imageSize: PixelSize, intrinsics given: CameraIntrinsics?,
                         parameters: CalibrationParameters) -> Result<CalibrationGate, CalibrationError> {
        let points = handles.points.map { SIMD2($0.x, $0.y) }
        guard let transform = CalibrationGeometry.homography(of: points),
              let inverse = transform.inverse else { return .failure(.degenerateHandles) }

        var blocking: [CalibrationIssue] = []
        // Shoelace sum in handle order: positive for clockwise handles on the screen (y down).
        var shoelace = 0.0
        var turns: [Double] = []
        for index in 0..<4 {
            let p = points[index], q = points[(index + 1) % 4], r = points[(index + 2) % 4]
            shoelace += p.x * q.y - q.x * p.y
            let u = q - p, v = r - q
            turns.append(u.x * v.y - u.y * v.x)
        }
        if !(shoelace > 0) { blocking.append(.handlesMirrored) }
        let convex = turns.allSatisfy { $0 > 0 } || turns.allSatisfy { $0 < 0 }
        if !convex { blocking.append(.quadNotConvex) }
        // w = h31·x + h32·y + h33 keeps its sign on the disc r ≤ 230 when |h33| > 230·‖(h31, h32)‖.
        let row2 = transform.row2
        let horizonClear = abs(row2.z) > horizonRadius * (row2.x * row2.x + row2.y * row2.y).squareRoot()
        if !horizonClear { blocking.append(.horizonCrossesBoard) }
        if !horizonClear || !discIsInside(transform, radius: frameRadius, imageSize: imageSize) {
            blocking.append(.boardOutOfFrame)
        }
        var minimumScale = Double.infinity
        for point in [SIMD2<Double>(0, 0)] + (0..<8).map({ k -> SIMD2<Double> in
            let a = Double(k) * .pi / 4
            return SIMD2(170 * sin(a), 170 * cos(a))
        }) {
            let scale = transform.localScale(at: point).min
            minimumScale = scale.isFinite ? min(minimumScale, scale) : 0
        }
        if !(minimumScale >= parameters.hardMinPixelsPerMillimetre) { blocking.append(.resolutionTooLow) }

        // C7: intrinsics in order of preference, then the pose.
        let intrinsics = given
            ?? CameraIntrinsics.selfCalibrated(boardToImage: transform, imageSize: imageSize)
            ?? CameraIntrinsics.assumed(imageSize: imageSize)
        let pose = CameraPose(boardToImage: transform, intrinsics: intrinsics)
        if pose == nil, !blocking.contains(.handlesMirrored) { blocking.append(.handlesMirrored) }
        guard let pose, blocking.isEmpty else { return .failure(.rejected(ordered(blocking))) }

        let foot = pose.footPoint
        let footDistance = (foot.x * foot.x + foot.y * foot.y).squareRoot()
        let distance = pose.distance
        let minTan = (footDistance - 170) / distance
        let maxTan = (footDistance + 170) / distance
        let zone = CalibrationDartZone(footPoint: foot, margin: parameters.dartMargin)
        let visible = visibleFraction(of: zone, transform: transform, imageSize: imageSize)

        var advisories: [CalibrationIssue] = []
        if minimumScale < parameters.goodPixelsPerMillimetre { advisories.append(.resolutionLow) }
        if minTan < parameters.goodMinTan { advisories.append(.viewTooFrontal) }
        if maxTan > parameters.goodMaxTan { advisories.append(.viewTooOblique) }
        if visible < minDartZoneFraction { advisories.append(.dartMarginCutOff) }
        if intrinsics.isApproximate { advisories.append(.intrinsicsApproximate) }

        return .success(CalibrationGate(boardToImage: transform, imageToBoard: inverse, intrinsics: intrinsics,
                                        pose: pose, minPixelsPerMillimetre: minimumScale,
                                        viewAngleDegrees: atan(footDistance / distance) * 180 / .pi,
                                        minTanObliquity: minTan, maxTanObliquity: maxTan,
                                        dartZoneVisibleFraction: visible, advisories: advisories))
    }

    /// Issues in declaration order of `CalibrationIssue`, without repetition: blocking ones first, then the advisory
    /// ones in the order of VISION.md §2.3 (placement, then the wireframe, then the intrinsics).
    static func ordered(_ issues: [CalibrationIssue]) -> [CalibrationIssue] {
        CalibrationIssue.allCases.filter { issues.contains($0) }
    }

    /// C8 (VISION.md §4.7). A wireframe turned by an odd number of sectors (`sectorPhaseMismatch`) scores every dart
    /// wrongly however well its rings fit: it is `poor`.
    static func grade(applied: Bool, rms: Double?, gate: CalibrationGate, phaseMatches: Bool,
                      parameters: CalibrationParameters) -> CalibrationQuality.Grade {
        guard applied, phaseMatches, let rms, rms.isFinite else { return .poor }
        let scale = gate.minPixelsPerMillimetre
        if rms <= parameters.goodRMS, scale >= parameters.goodPixelsPerMillimetre,
           gate.minTanObliquity >= parameters.goodMinTan, gate.maxTanObliquity <= parameters.goodMaxTan {
            return .good
        }
        if rms <= parameters.fairRMS, scale >= parameters.fairPixelsPerMillimetre,
           gate.minTanObliquity >= parameters.fairMinTan, gate.maxTanObliquity <= parameters.fairMaxTan {
            return .fair
        }
        return .poor
    }

    /// True when the image of the board disc of `radius` lies inside the image `[-0.5, W - 0.5] × [-0.5, H - 0.5]`.
    ///
    /// Exact: the image of the circle is a conic whose dual is `C* = H · diag(R², R², −1) · Hᵀ`; its tangents
    /// `x = c` (line `(1, 0, −c)`) solve `C*₀₀ − 2c·C*₀₂ + c²·C*₂₂ = 0`, and likewise for `y`. Requires a horizon that
    /// does not cross the disc, which the caller has checked.
    static func discIsInside(_ transform: Homography, radius: Double, imageSize: PixelSize) -> Bool {
        let h = transform.matrix
        let dual = h * simd_double3x3(diagonal: SIMD3(radius * radius, radius * radius, -1)) * h.transpose
        func extent(_ axis: Int) -> (Double, Double)? {
            // Row/column `axis` of the symmetric dual conic.
            let a = dual[2][2], b = dual[2][axis], c = dual[axis][axis]
            guard a != 0, a.isFinite else { return nil }
            let discriminant = b * b - a * c
            guard discriminant >= 0, discriminant.isFinite else { return nil }
            let root = discriminant.squareRoot()
            let first = (b - root) / a, second = (b + root) / a
            return (min(first, second), max(first, second))
        }
        guard let xs = extent(0), let ys = extent(1) else { return false }
        return xs.0 >= -0.5 && xs.1 <= Double(imageSize.width) - 0.5
            && ys.0 >= -0.5 && ys.1 <= Double(imageSize.height) - 0.5
    }

    /// Fraction of the dart zone whose image is inside the frame, on a 5 mm grid.
    static func visibleFraction(of zone: CalibrationDartZone, transform: Homography, imageSize: PixelSize) -> Double {
        let extent = CalibrationDartZone.tipRadius + max(0, zone.margin)
        let step = 5.0
        let count = Int((extent / step).rounded(.up))
        let row2 = transform.row2
        var inside = 0, total = 0
        let width = Double(imageSize.width) - 0.5, height = Double(imageSize.height) - 0.5
        for i in -count...count {
            for j in -count...count {
                let q = SIMD2(Double(i) * step, Double(j) * step)
                guard zone.contains(q) else { continue }
                total += 1
                let w = row2.x * q.x + row2.y * q.y + row2.z
                // Behind the camera: not in the image. The sign of a visible point is the sign at the bull.
                guard w * row2.z > 0 else { continue }
                let p = transform.apply(q)
                if p.x >= -0.5, p.x <= width, p.y >= -0.5, p.y <= height { inside += 1 }
            }
        }
        return total > 0 ? Double(inside) / Double(total) : 0
    }
}

/// C5 — sector phase check (VISION.md §4.6). Internal to DartVision (lot V2).
enum CalibrationPhase {
    /// Radius of the singles where the check reads the luminance, mm.
    static let radius: Double = 130
    /// Angles read in each sector, degrees from its middle.
    static let offsets: [Double] = [-4, 0, 4]

    /// Mean luminance (Rec. 601) of the odd (cream) sectors minus that of the even (black) ones, at r = 130 mm
    /// through `boardToImage`; nil when no sample of one of the two families is in the image.
    static func contrast(_ raster: EdgeSamplerRaster, boardToImage: Homography) -> Double? {
        var sums = [0.0, 0.0], counts = [0, 0]
        for sector in 0..<20 {
            for offset in offsets {
                let a = (18 * Double(sector) + offset) * .pi / 180
                let p = boardToImage.apply(SIMD2(radius * sin(a), radius * cos(a)))
                guard let colour = raster.sample(x: p.x, y: p.y) else { continue }
                let luma = 0.299 * Double(colour.x) + 0.587 * Double(colour.y) + 0.114 * Double(colour.z)
                sums[sector % 2] += luma
                counts[sector % 2] += 1
            }
        }
        guard counts[0] > 0, counts[1] > 0 else { return nil }
        return sums[1] / Double(counts[1]) - sums[0] / Double(counts[0])
    }

    /// True when the odd sectors are lighter than the even ones by at least `minSectorLumaContrast` levels.
    static func matches(_ raster: EdgeSamplerRaster, boardToImage: Homography, parameters: CalibrationParameters) -> Bool {
        guard let contrast = contrast(raster, boardToImage: boardToImage) else { return false }
        return contrast >= parameters.minSectorLumaContrast
    }
}
