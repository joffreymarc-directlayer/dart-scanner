import Foundation
import simd
import CoreGraphics
import CoreVideo
import DartCore

/// Pinhole intrinsics in pixels, origin top-left.
public struct CameraIntrinsics: Hashable, Codable, Sendable {
    public enum Source: String, Codable, Sendable {
        /// Intrinsic matrix delivered with the sample buffer.
        case sampleBuffer
        /// Derived from the active format's field of view.
        case fieldOfView
        /// Single-plane self-calibration from the homography.
        case selfCalibrated
        /// Fallback: 67 degrees along the long side.
        case assumed
    }
    public var fx: Double
    public var fy: Double
    public var cx: Double
    public var cy: Double
    public var source: Source
    public init(fx: Double, fy: Double, cx: Double, cy: Double, source: Source) {
        self.fx = fx
        self.fy = fy
        self.cx = cx
        self.cy = cy
        self.source = source
    }

    /// `f = (max(width, height) / 2) / tan(fov / 2)`, principal point at the image centre.
    public init(longSideFieldOfViewDegrees: Double, imageSize: PixelSize) {
        let longSide = Double(max(imageSize.width, imageSize.height))
        let focal = (longSide / 2) / tan(longSideFieldOfViewDegrees * .pi / 360)
        self.init(fx: focal, fy: focal,
                  cx: Double(imageSize.width - 1) / 2, cy: Double(imageSize.height - 1) / 2,
                  source: .fieldOfView)
    }

    /// Zhang single-plane formula with the principal point at the image centre.
    /// Nil when both denominators are ill-conditioned or f is outside [0.5, 3] * max(width, height).
    public static func selfCalibrated(boardToImage: Homography, imageSize: PixelSize) -> CameraIntrinsics? {
        let cx = Double(imageSize.width - 1) / 2
        let cy = Double(imageSize.height - 1) / 2
        // H̃ = T·H with T = [[1, 0, −cx], [0, 1, −cy], [0, 0, 1]]: the principal point moves to the origin.
        let h31 = boardToImage.row2.x, h32 = boardToImage.row2.y
        let h11 = boardToImage.row0.x - cx * h31, h12 = boardToImage.row0.y - cx * h32
        let h21 = boardToImage.row1.x - cy * h31, h22 = boardToImage.row1.y - cy * h32

        // Orthogonality of r1 and r2, or equality of their lengths: whichever has the larger denominator.
        let orthogonalDenominator = h31 * h32
        let lengthDenominator = h32 * h32 - h31 * h31
        let focalSquared: Double
        if abs(orthogonalDenominator) >= abs(lengthDenominator) {
            guard orthogonalDenominator != 0 else { return nil }
            focalSquared = -(h11 * h12 + h21 * h22) / orthogonalDenominator
        } else {
            focalSquared = (h11 * h11 + h21 * h21 - h12 * h12 - h22 * h22) / lengthDenominator
        }
        guard focalSquared.isFinite, focalSquared > 0 else { return nil }

        // Conditioning. With this focal the two columns are λ·r1 and λ·r2, so (h31² + h32²) / λ² is sin² of the
        // angle between the optical axis and the board normal. Both denominators are of that order: under a few
        // degrees they vanish and the focal is noise.
        let scaleSquared = ((h11 * h11 + h21 * h21 + h12 * h12 + h22 * h22) / focalSquared + h31 * h31 + h32 * h32) / 2
        guard scaleSquared.isFinite, scaleSquared > 0 else { return nil }
        let sinSquared = (h31 * h31 + h32 * h32) / scaleSquared
        guard sinSquared >= selfCalibrationMinimumSinSquared else { return nil }

        let focal = focalSquared.squareRoot()
        let longSide = Double(max(imageSize.width, imageSize.height))
        guard focal >= 0.5 * longSide, focal <= 3 * longSide else { return nil }
        return CameraIntrinsics(fx: focal, fy: focal, cx: cx, cy: cy, source: .selfCalibrated)
    }

    public static func assumed(imageSize: PixelSize) -> CameraIntrinsics {
        var intrinsics = CameraIntrinsics(longSideFieldOfViewDegrees: assumedLongSideFieldOfViewDegrees, imageSize: imageSize)
        intrinsics.source = .assumed
        return intrinsics
    }

    public var matrix: simd_double3x3 {
        simd_double3x3(rows: [SIMD3(fx, 0, cx), SIMD3(0, fy, cy), SIMD3(0, 0, 1)])
    }

    /// True for `.selfCalibrated` and `.assumed`.
    public var isApproximate: Bool {
        switch source {
        case .selfCalibrated, .assumed: return true
        case .sampleBuffer, .fieldOfView: return false
        }
    }
}

extension CameraIntrinsics {
    /// Field of view of the fallback intrinsics, along the long side (VISION.md §4.2, case 4).
    static let assumedLongSideFieldOfViewDegrees: Double = 67

    /// Self-calibration is refused when the optical axis is within 3 degrees of the board normal: sin²(3°)
    /// (VISION.md §10.2, M5: fallback under 3 degrees).
    static let selfCalibrationMinimumSinSquared: Double = 0.0027390523158633317
}
