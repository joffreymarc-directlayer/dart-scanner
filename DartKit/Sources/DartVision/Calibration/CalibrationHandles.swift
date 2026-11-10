import Foundation
import simd
import CoreGraphics
import CoreVideo
import DartCore

/// The four draggable calibration points: junctions of the outer double wire (r = 170 mm) with four radial wires.
public enum CalibrationHandle: Int, CaseIterable, Codable, Sendable {
    case wire20_1, wire6_10, wire3_19, wire11_14
    /// `(170 sin a, 170 cos a)` for a = 9, 99, 189, 279 degrees:
    /// about (26.59, 167.91), (167.91, -26.59), (-26.59, -167.91), (-167.91, 26.59).
    public var boardPoint: BoardPoint {
        let degrees: Double
        switch self {
        case .wire20_1: degrees = 9
        case .wire6_10: degrees = 99
        case .wire3_19: degrees = 189
        case .wire11_14: degrees = 279
        }
        let a = degrees * .pi / 180
        return BoardPoint(x: 170 * sin(a), y: 170 * cos(a))
    }
    /// Number printed next to the handle in the overlay: "20", "6", "3", "11".
    public var label: String {
        switch self {
        case .wire20_1: return "20"
        case .wire6_10: return "6"
        case .wire3_19: return "3"
        case .wire11_14: return "11"
        }
    }
}

/// Image positions of the four handles, in `CalibrationHandle` order.
public struct CalibrationHandles: Hashable, Codable, Sendable {
    public var points: [ImagePoint]
    public init(points: [ImagePoint]) {
        self.points = points
    }

    /// Handles of a known homography (used by the locator). Lot V2; `SyntheticCamera.exactHandles()` does not call it.
    ///
    /// Each handle is `boardToImage` applied to the board point of its junction.
    public init(projecting boardToImage: Homography) {
        self.init(points: CalibrationHandle.allCases.map { handle in
            let p = boardToImage.apply(SIMD2(handle.boardPoint.x, handle.boardPoint.y))
            return ImagePoint(x: p.x, y: p.y)
        })
    }

    /// Reads or moves one handle. A handle missing from `points` reads as a point with NaN coordinates (which every
    /// calibration call treats as degenerate); setting it first pads `points` with such points.
    public subscript(handle: CalibrationHandle) -> ImagePoint {
        get {
            let index = handle.rawValue
            return index < points.count ? points[index] : ImagePoint(x: .nan, y: .nan)
        }
        set {
            let index = handle.rawValue
            while points.count <= index {
                points.append(ImagePoint(x: .nan, y: .nan))
            }
            points[index] = newValue
        }
    }

    /// Starting position: a circle of radius `0.3 * min(width, height)` at the image centre.
    ///
    /// The handles sit where a board seen from the front, 20 at the top, would put them: handle `k` at the clockwise
    /// angle `a_k` (9, 99, 189, 279 degrees from the top of the image), at `centre + r · (sin a_k, −cos a_k)`, with the
    /// centre `((W − 1) / 2, (H − 1) / 2)` (VISION.md §3.1). They pass the C1 gate whenever the image is large enough.
    public static func centredDefault(in size: PixelSize) -> CalibrationHandles {
        let centre = SIMD2(Double(size.width - 1) / 2, Double(size.height - 1) / 2)
        let radius = 0.3 * Double(min(size.width, size.height))
        return CalibrationHandles(points: CalibrationHandle.allCases.map { handle in
            // The board point is (170 sin a, 170 cos a); the image y axis points down.
            let direction = SIMD2(handle.boardPoint.x, -handle.boardPoint.y) / 170
            let p = centre + radius * direction
            return ImagePoint(x: p.x, y: p.y)
        })
    }

    public func translated(dx: Double, dy: Double) -> CalibrationHandles {
        CalibrationHandles(points: points.map { ImagePoint(x: $0.x + dx, y: $0.y + dy) })
    }

    /// Pinch and twist of the whole wireframe: `p' = centre + scale · R(radians) · (p − centre)`, with the usual
    /// rotation matrix applied in image coordinates. As the image y axis points down, a positive angle turns the
    /// handles clockwise on the screen (the convention of SwiftUI's `RotationGesture`).
    public func scaledAndRotated(about centre: ImagePoint, scale: Double, radians: Double) -> CalibrationHandles {
        let c = cos(radians), s = sin(radians)
        return CalibrationHandles(points: points.map { point in
            let dx = point.x - centre.x, dy = point.y - centre.y
            return ImagePoint(x: centre.x + scale * (c * dx - s * dy), y: centre.y + scale * (s * dx + c * dy))
        })
    }

    /// Rotates the wireframe by `count` sectors clockwise (18 degrees each). Nil when the handles are degenerate.
    ///
    /// The homography of the handles `H` becomes `H · Rot(18° · count)` (`Homography.boardRotation`): the label "20"
    /// moves to where the 1 was drawn for `count == 1`. Negative counts turn anticlockwise.
    public func rotated(bySectors count: Int) -> CalibrationHandles? {
        guard let transform = CalibrationGeometry.homography(of: self) else { return nil }
        let turns = ((count % 20) + 20) % 20
        let rotated = transform.concatenating(.boardRotation(clockwiseDegrees: 18 * Double(turns)))
        let result = CalibrationHandles(projecting: rotated)
        return result.points.allSatisfy({ $0.x.isFinite && $0.y.isFinite }) ? result : nil
    }

    /// Rotates the wireframe so that the middle of the 20 sector is as close as possible to `point`.
    /// With `parityPreserving`, only multiples of 36 degrees are tried (the red/green phase is kept).
    ///
    /// The middle of the 20 sector is taken at the radius of the tapped point (read through the current handles,
    /// at least the outer bull): every rotation of the wireframe by a whole number of sectors is tried, and the one
    /// whose 20 lands nearest to `point` in the image wins (no rotation on a tie). Nil when the handles are
    /// degenerate or `point` is not finite.
    public func reoriented(twentyAt point: ImagePoint, parityPreserving: Bool) -> CalibrationHandles? {
        guard point.x.isFinite, point.y.isFinite,
              let transform = CalibrationGeometry.homography(of: self), let inverse = transform.inverse else { return nil }
        let tapped = inverse.apply(SIMD2(point.x, point.y))
        let radius = simd_length(tapped)
        let reach = radius.isFinite ? max(RingRadii.nominal.outerBull, radius) : RingRadii.nominal.doubleOuter
        let target = SIMD2(point.x, point.y)
        var best: (count: Int, distance: Double)?
        for count in stride(from: 0, to: 20, by: parityPreserving ? 2 : 1) {
            // Middle of the 20 sector of the wireframe turned by `count` sectors: board angle 18° · count.
            let angle = 18 * Double(count) * .pi / 180
            let image = transform.apply(SIMD2(reach * sin(angle), reach * cos(angle)))
            let distance = simd_length(image - target)
            guard distance.isFinite else { continue }
            if best == nil || distance < (best?.distance ?? .infinity) {
                best = (count, distance)
            }
        }
        guard let chosen = best else { return nil }
        return rotated(bySectors: chosen.count)
    }
}

/// Geometry shared by the calibration files (lot V2, internal).
enum CalibrationGeometry {
    /// The four junction board points, in `CalibrationHandle` order, metric mm.
    static let junctions: [SIMD2<Double>] = CalibrationHandle.allCases.map { SIMD2($0.boardPoint.x, $0.boardPoint.y) }

    /// The C1 closed-form homography (Heckbert) from the four junctions to the four handles. Nil when there are not
    /// four finite handles, two of them coincide, three of them are collinear, or the transform cannot be inverted.
    static func homography(of handles: CalibrationHandles) -> Homography? {
        homography(of: handles.points.map { SIMD2($0.x, $0.y) })
    }

    /// Same, from the four handle positions as vectors.
    static func homography(of points: [SIMD2<Double>]) -> Homography? {
        guard points.count == 4, points.allSatisfy({ $0.x.isFinite && $0.y.isFinite }),
              !hasDegenerateTriple(points),
              let transform = Homography.mapping(from: junctions, to: points),
              transform.inverse != nil else { return nil }
        return transform
    }

    /// True when two of the points coincide or three of them are collinear, relative to the size of the set.
    static func hasDegenerateTriple(_ points: [SIMD2<Double>]) -> Bool {
        var span = 0.0
        for i in points.indices {
            for j in points.indices where j > i {
                span = max(span, simd_length(points[i] - points[j]))
            }
        }
        guard span > 0, span.isFinite else { return true }
        let tolerance = 1e-9 * span * span
        for i in points.indices {
            for j in points.indices where j > i {
                guard simd_length(points[i] - points[j]) > 1e-9 * span else { return true }
                for k in points.indices where k > j {
                    let u = points[j] - points[i], v = points[k] - points[i]
                    if abs(u.x * v.y - u.y * v.x) <= tolerance { return true }
                }
            }
        }
        return false
    }
}
