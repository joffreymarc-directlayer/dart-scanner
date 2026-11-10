import Foundation
import simd
import CoreGraphics
import CoreVideo
import DartCore

/// Every constant of the detection pipeline (section 5). Lengths in mm, areas in mm², thresholds in 8-bit levels.
public struct DetectionParameters: Hashable, Codable, Sendable {
    // D2 evidence
    public var blurRadius: Int = 1
    public var shadowLowerBound: Double = 0.40
    public var shadowUpperBound: Double = 1.08
    public var gainGridStep: Int = 16
    public var gainMinReferenceNorm: Double = 60
    // D3 mask
    public var evidenceThresholdFloor: Double = 18
    public var noiseMultiplier: Double = 6
    public var edgeGuardPixels: Double = 0.25
    public var silhouetteDilation: Double = 2.0
    public var relockExtraDilation: Double = 3.0
    public var openRadius: Int = 1
    public var closeRadius: Int = 3
    // D4 components and scene classification
    public var speckArea: Double = 15
    public var minChangeArea: Double = 60
    public var maxDartArea: Double = 4000
    public var lightingChangeFraction: Double = 0.35
    public var removedFraction: Double = 0.5
    public var disturbedFraction: Double = 0.15
    public var ghostGuardFraction: Double = 0.5
    // D5 grouping and axis
    public var lineFullWeightDistance: Double = 4
    public var lineZeroWeightDistance: Double = 25
    public var lineIterations: Int = 4
    public var corridorHalfWidth: Double = 20
    public var clutterFraction: Double = 0.8
    public var peelMinArea: Double = 60
    // D6 tip end
    public var usePoseForTipEnd: Bool = true
    public var endFraction: Double = 0.2
    public var flightMinWidth: Double = 12
    public var flightWidthRatio: Double = 2
    public var poseMinTanObliquity: Double = 0.15
    public var onBoardRadius: Double = 180
    // D7 refit on the narrow part
    public var narrowPartFraction: Double = 0.6
    public var narrowMaxWidth: Double = 12
    public var narrowHuberK: Double = 1.5
    public var narrowMinPixels: Int = 40
    // D8 tip walk
    public var walkThresholdRatio: Double = 0.5
    public var walkCorridorHalfWidth: Double = 1.5
    public var walkStep: Double = 0.25
    public var walkBack: Double = 8
    public var walkAhead: Double = 25
    public var walkGap: Double = 2
    public var lateralHalfWidth: Double = 2.5
    /// VISION.md §5.3 prints 0.8 [sonde]. On the delivered renderer (a flat-ended point of radius 1.15 mm, §10.1)
    /// the walk of D8 ends 1.1 mm beyond the entry point, as §5.2 itself states ("à r du vrai point d'entrée"):
    /// with 0.8 the mean along-axis error is +0.31 to +0.33 mm, outside T2 (±0.3); with 1.1 it is +0.03 mm. A
    /// starting value to tune on real recordings (§11.2); reported to the integrator.
    public var tipCapCorrection: Double = 1.1
    // D9 plausibility
    public var pointMaxWidth: Double = 4
    public var pointCheckLength: Double = 6
    public var lowContrastRatio: Double = 1.5
    public var minVisibleLength: Double = 25
    public var minElongation: Double = 4
    public var maxDartLength: Double = 170
    public var maxLeanDegrees: Double = 20
    public var occlusionProbe: Double = 2
    public init() {}
    public static let `default`: DetectionParameters = DetectionParameters()
}
