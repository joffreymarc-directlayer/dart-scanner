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
    public var estimatedAccuracy: Double { get { fatalError("unimplemented") } }
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
    public let id: UUID
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
    public func boardPoint(for point: ImagePoint) -> BoardPoint { fatalError("unimplemented") }
    /// Image position of a nominal board point (exact inverse of `boardPoint(for:)`).
    public func imagePoint(for point: BoardPoint) -> ImagePoint { fatalError("unimplemented") }
    /// Scored hit under an image point: the tap test of the setup screen and tap-the-tips in photo mode.
    public func hit(at point: ImagePoint, board: BoardGeometry) -> Hit { fatalError("unimplemented") }
    /// Source px/mm at a nominal board point (worst and best direction).
    public func localScale(at point: BoardPoint) -> (min: Double, max: Double) { fatalError("unimplemented") }
    public func wireframe(ringSegments: Int) -> BoardWireframe { fatalError("unimplemented") }
}
