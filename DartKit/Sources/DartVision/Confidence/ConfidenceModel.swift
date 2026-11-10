import Foundation
import simd
import CoreGraphics
import CoreVideo
import DartCore

/// Every constant of the confidence model (section 7).
public struct ConfidenceParameters: Hashable, Codable, Sendable {
    public var gridSide: Int = 21
    public var gridSpanSigmas: Double = 3
    public var minCalibrationSigma: Double = 0.3
    public var acrossPixelSigma: Double = 0.5
    public var alongPixelSigma: Double = 1.0
    public var hiddenTipLength: Double = 1.5
    public var hiddenTipLengthLowContrast: Double = 3.0
    public var occlusionSamples: Int = 5
    public var maxCandidates: Int = 6
    public var minCandidateProbability: Double = 0.01
    public var nearbyRadii: [Double] = [4, 8, 16]
    public var thresholds: ConfidenceThresholds = .init()
    public var severeFlagFactor: Double = 0.4
    public var occlusionFactor: Double = 0.6
    public var majorFlagFactor: Double = 0.5
    public var visitLimitFactor: Double = 0.6
    public var moderateFlagFactor: Double = 0.7
    public var minorFlagFactor: Double = 0.9
    public var poorCalibrationCap: Double = 0.80
    public var warmUpDarts: Int = 3
    public var warmUpCap: Double = 0.84
    public var crossViewpointCap: Double = 0.80
    public var trustWindow: Int = 15
    public var trustCorrectionsToDegrade: Int = 2
    public var degradedHighThreshold: Double = 0.95
    public var scanSuggestionWindow: Int = 12
    public var scanSuggestionRate: Double = 0.3
    public init() {}
}

/// Situation of the session when a dart is observed.
public struct ConfidenceContext: Sendable {
    /// Darts still to be capped after a calibration (0 once the one-dart check passed).
    public var warmUpRemaining: Int
    public var thresholds: ConfidenceThresholds
    /// Extra cap from the caller (1 = none).
    public var cap: Double
    public init(warmUpRemaining: Int = 0, thresholds: ConfidenceThresholds = .standard, cap: Double = 1) {
        self.warmUpRemaining = warmUpRemaining
        self.thresholds = thresholds
        self.cap = cap
    }
}

public struct ConfidenceModel: Sendable {
    public init(board: BoardGeometry = .standard, parameters: ConfidenceParameters = .init()) { fatalError("unimplemented") }
    public func uncertainty(for candidate: DartCandidate, calibration: BoardCalibration) -> TipUncertainty { fatalError("unimplemented") }
    /// Probability of each hit: midpoint rule on a `gridSide x gridSide` grid over ±`gridSpanSigmas` sigma.
    public func posterior(tip: BoardPoint, uncertainty: TipUncertainty, occlusionSpan: Double,
                          radii: RingRadii) -> [HitCandidate] { fatalError("unimplemented") }
    /// Product of the flag factors and of the detector score (section 7.3), before caps.
    public func quality(flags: DartFlags, score: Double) -> Double { fatalError("unimplemented") }
    public func observe(_ candidate: DartCandidate, id: UUID, visit: Int, indexInVisit: Int, timestamp: TimeInterval,
                        source: ObservationSource, calibration: BoardCalibration,
                        context: ConfidenceContext) -> DartObservation { fatalError("unimplemented") }
    /// Observation for a tip given by the player (tap or drag): confidence 1, source `.tappedOnPhoto`.
    public func observation(forConfirmedTip tip: BoardPoint, id: UUID, visit: Int, indexInVisit: Int,
                            timestamp: TimeInterval) -> DartObservation { fatalError("unimplemented") }
}
