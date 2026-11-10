import Foundation
import simd
import CoreGraphics
import CoreVideo
import DartCore

/// One-dart check at setup (section 4.8): validates the chain with the player's darts and light, and sets the shadow bound.
public struct LightingCheckResult: Hashable, Sendable {
    public enum Verdict: Sendable { case verified, shadowTooHard, pointNotVisible, viewTooFrontal, failed }
    public var verdict: Verdict
    /// Distance between the detected tip and the tip the user tapped, mm.
    public var tipError: Double
    /// 5th percentile of the brightness ratio over shadow pixels; nil when fewer than 50 were found.
    public var shadowDepth: Double?
    public var recommendedShadowLowerBound: Double
}

public enum LightingCheck {
    public static func run(reference: CanvasImage, current: CanvasImage, confirmedTip: BoardPoint,
                           calibration: BoardCalibration, noiseSigma: Double,
                           parameters: DetectionParameters) -> LightingCheckResult { fatalError("unimplemented") }
}
