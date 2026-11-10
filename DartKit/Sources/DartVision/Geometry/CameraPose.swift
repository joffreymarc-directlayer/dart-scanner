import Foundation
import simd
import CoreGraphics
import CoreVideo
import DartCore

/// Camera pose relative to the board, recovered from the homography and the intrinsics.
public struct CameraPose: Hashable, Codable, Sendable {
    /// Camera centre in the board frame, mm. `center.z > 0` in front of the board.
    public let center: SIMD3<Double>
    /// Rows of the board-to-camera rotation (camera x right, y down, z forward).
    public let rotationRows: [SIMD3<Double>]
    /// True when the intrinsics were self-calibrated or assumed.
    public let isApproximate: Bool

    /// Nil when the recovered camera centre is behind the board plane (mirrored handles).
    public init?(boardToImage: Homography, intrinsics: CameraIntrinsics) {
        guard intrinsics.fx != 0, intrinsics.fy != 0 else { return nil }
        // B = K⁻¹·H, column by column: K⁻¹·(a, b, c) = ((a − cx·c) / fx, (b − cy·c) / fy, c).
        func column(_ index: Int) -> SIMD3<Double> {
            let a = boardToImage.row0[index], b = boardToImage.row1[index], c = boardToImage.row2[index]
            return SIMD3((a - intrinsics.cx * c) / intrinsics.fx, (b - intrinsics.cy * c) / intrinsics.fy, c)
        }
        let b1 = column(0), b2 = column(1), b3 = column(2)
        let lengths = simd_length(b1) + simd_length(b2)
        guard lengths.isFinite, lengths > 0 else { return nil }
        // λ = ±2 / (‖b1‖ + ‖b2‖), sign such that the board origin is in front of the camera.
        var lambda = 2 / lengths
        if lambda * b3.z < 0 { lambda = -lambda }
        let scaled1 = lambda * b1, scaled2 = lambda * b2
        let length1 = simd_length(scaled1)
        guard length1 > 0 else { return nil }
        let r1 = scaled1 / length1
        let orthogonal2 = scaled2 - simd_dot(r1, scaled2) * r1
        let length2 = simd_length(orthogonal2)
        guard length2 > 0 else { return nil }
        let r2 = orthogonal2 / length2
        let r3 = simd_cross(r1, r2)
        let t = lambda * b3
        // C = −Rᵀ·t with R = [r1 r2 r3] (columns).
        let centre = -SIMD3(simd_dot(r1, t), simd_dot(r2, t), simd_dot(r3, t))
        guard centre.x.isFinite, centre.y.isFinite, centre.z.isFinite, centre.z > 0 else { return nil }
        self.center = centre
        self.rotationRows = [SIMD3(r1.x, r2.x, r3.x), SIMD3(r1.y, r2.y, r3.y), SIMD3(r1.z, r2.z, r3.z)]
        self.isApproximate = intrinsics.isApproximate
    }

    /// Internal: a pose known from the ground truth (synthetic cameras).
    init(center: SIMD3<Double>, rotationRows: [SIMD3<Double>], isApproximate: Bool) {
        self.center = center
        self.rotationRows = rotationRows
        self.isApproximate = isApproximate
    }

    /// F: orthogonal projection of the camera centre on the board plane.
    public var footPoint: BoardPoint {
        BoardPoint(x: center.x, y: center.y)
    }

    /// D: distance from the camera centre to the board plane, mm.
    public var distance: Double {
        center.z
    }

    /// `|point - F| / D`: board millimetres of error per hidden millimetre of height at `point`.
    public func tanObliquity(at point: BoardPoint) -> Double {
        let dx = point.x - center.x, dy = point.y - center.y
        return (dx * dx + dy * dy).squareRoot() / center.z
    }

    /// Where a point at `height` mm above `point` appears in the board plane: `X + (X - F) * s / (D - s)`.
    public func apparentPosition(of point: BoardPoint, height: Double) -> BoardPoint {
        let factor = height / (center.z - height)
        return BoardPoint(x: point.x + (point.x - center.x) * factor, y: point.y + (point.y - center.y) * factor)
    }

    /// Inverse of `apparentPosition`.
    public func removingParallax(from apparent: BoardPoint, height: Double) -> BoardPoint {
        // X' = F + (X − F)·D / (D − s), hence X = F + (X' − F)·(D − s) / D.
        let factor = (center.z - height) / center.z
        return BoardPoint(x: center.x + (apparent.x - center.x) * factor, y: center.y + (apparent.y - center.y) * factor)
    }
}
