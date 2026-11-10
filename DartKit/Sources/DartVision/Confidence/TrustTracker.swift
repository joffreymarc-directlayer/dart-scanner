import Foundation
import simd
import CoreGraphics
import CoreVideo
import DartCore

/// Tightens the high threshold when the player keeps correcting confident darts (section 7.6).
public struct TrustTracker: Sendable {
    public init(parameters: ConfidenceParameters = .init()) { fatalError("unimplemented") }
    public mutating func record(tier: ConfidenceTier, wasCorrected: Bool) { fatalError("unimplemented") }
    public var thresholds: ConfidenceThresholds { get { fatalError("unimplemented") } }
    public var accuracyDegraded: Bool { get { fatalError("unimplemented") } }
    public var shouldSuggestScanMode: Bool { get { fatalError("unimplemented") } }
}
