import Foundation
import simd
import CoreGraphics
import CoreVideo
import DartCore

/// Scoring from stills (section 8). No state, no camera.
public struct PhotoScorer: Sendable {
    public init(detector: any DartDetecting = DifferencingDartDetector(), confidence: ConfidenceModel = .init()) { fatalError("unimplemented") }
    /// Rectified, zoomable view of a calibrated photo for tap-the-tips.
    public func rectified(_ photo: RGBImage, calibration: BoardCalibration) -> CanvasImage { fatalError("unimplemented") }
    /// The player tapped a tip on the photo (image pixels): the guaranteed path.
    public func observation(forTappedTip point: ImagePoint, calibration: BoardCalibration, visit: Int,
                            indexInVisit: Int) -> DartObservation { fatalError("unimplemented") }
    /// Optional layer: differences a calibrated photo against an empty-board canvas taken from another viewpoint.
    /// Every result is flagged `crossViewpoint` and capped below the high tier.
    public func score(photo: RGBImage, calibration: BoardCalibration, emptyReference: CanvasImage, maxDarts: Int = 3,
                      parameters: DetectionParameters = .default) -> [DartObservation] { fatalError("unimplemented") }
}
