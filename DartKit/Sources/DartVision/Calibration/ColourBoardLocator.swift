import Foundation
import simd
import CoreGraphics
import CoreVideo
import DartCore

/// Output of automatic board finding: initial handles only. Calibration then runs exactly as with manual handles.
public struct BoardLocation: Sendable {
    /// Handles for the orientation whose 20 is closest to `upDirection`.
    public var handles: CalibrationHandles
    /// The nine other orientations, 36 degrees apart.
    public var alternatives: [CalibrationHandles]
    /// Phase contrast of the red/green alternation, 0...0.64 (identity check).
    public var phaseContrast: Double
}

/// Optional layer: automatic board finding.
public protocol BoardLocating: Sendable {
    /// `upDirection` is the image direction of "up" (default (0, -1)); it picks one of the ten orientations.
    func locate(in still: RGBImage, upDirection: SIMD2<Double>) -> BoardLocation?
}

/// Colour mask, outer ellipse, bull, circle-point construction, 10th-harmonic phase (section 4.3).
public struct ColourBoardLocator: BoardLocating {
    public struct Parameters: Hashable, Codable, Sendable {
        public var workLongSide: Int = 640
        public var minBrightness: Int = 48
        public var saturationRange: ClosedRange<Double> = 0.30...0.55
        public var rayCount: Int = 360
        public var minRunLength: Int = 3
        public var sampsonTolerance: Double = 1.5
        public var bullAreaRange: ClosedRange<Double> = 0.4...2.5
        public var minColouredFraction: Double = 0.7
        public var minUncolouredFraction: Double = 0.8
        public var minPhaseContrast: Double = 0.35
        public var maxPhaseDisagreementDegrees: Double = 3
        public init() {}
    }
    public init(parameters: Parameters = .init()) { fatalError("unimplemented") }
    public func locate(in still: RGBImage, upDirection: SIMD2<Double>) -> BoardLocation? { fatalError("unimplemented") }
}
