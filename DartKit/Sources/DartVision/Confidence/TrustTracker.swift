import Foundation
import simd
import CoreGraphics
import CoreVideo
import DartCore

/// Tightens the high threshold when the player keeps correcting confident darts (section 7.6).
///
/// - Corrected `high` darts: when at least `trustCorrectionsToDegrade` (2) of the last `trustWindow` (15) darts were
///   high and corrected, the high threshold rises to `degradedHighThreshold` (0.95) and `accuracyDegraded` turns on.
///   Both stay until `trustWindow` darts in a row are recorded without a correction; the threshold is then the
///   configured one again.
/// - Low or corrected darts: over the last `scanSuggestionWindow` (12) camera darts, a rate above
///   `scanSuggestionRate` (30 %) calls for the one-dart lighting check (`shouldSuggestLightingCheck`). When that
///   rate is still above the limit after another full window of darts, `shouldSuggestScanMode` turns on: the
///   problem persisted after the first advice.
public struct TrustTracker: Sendable {
    private let parameters: ConfidenceParameters
    /// The last records, oldest first, at most `max(trustWindow, scanSuggestionWindow)` of them.
    private var history: [(tier: ConfidenceTier, wasCorrected: Bool)]
    private var degraded: Bool
    /// Darts recorded without a correction since the last correction.
    private var uncorrectedStreak: Int
    /// Records in a row at which the low-or-corrected rate was above the limit (full window only).
    private var poorRateStreak: Int

    public init(parameters: ConfidenceParameters = .init()) {
        self.parameters = parameters
        history = []
        degraded = false
        uncorrectedStreak = 0
        poorRateStreak = 0
    }

    public mutating func record(tier: ConfidenceTier, wasCorrected: Bool) {
        history.append((tier, wasCorrected))
        let keep = max(1, parameters.trustWindow, parameters.scanSuggestionWindow)
        if history.count > keep { history.removeFirst(history.count - keep) }

        uncorrectedStreak = wasCorrected ? 0 : uncorrectedStreak + 1
        if degraded {
            if uncorrectedStreak >= max(1, parameters.trustWindow) { degraded = false }
        } else {
            let recent = history.suffix(max(1, parameters.trustWindow))
            let correctedHighs = recent.filter { $0.tier == .high && $0.wasCorrected }.count
            if correctedHighs >= max(1, parameters.trustCorrectionsToDegrade) { degraded = true }
        }

        let window = max(1, parameters.scanSuggestionWindow)
        if history.count >= window {
            let recent = history.suffix(window)
            let poor = recent.filter { $0.tier == .low || $0.wasCorrected }.count
            poorRateStreak = Double(poor) / Double(window) > parameters.scanSuggestionRate ? poorRateStreak + 1 : 0
        } else {
            poorRateStreak = 0
        }
    }

    public var thresholds: ConfidenceThresholds {
        var result = parameters.thresholds
        if degraded { result.high = max(result.high, parameters.degradedHighThreshold) }
        return result
    }

    public var accuracyDegraded: Bool {
        degraded
    }

    public var shouldSuggestScanMode: Bool {
        poorRateStreak > max(1, parameters.scanSuggestionWindow)
    }
}

extension TrustTracker {
    /// More than `scanSuggestionRate` of the last `scanSuggestionWindow` camera darts were low or corrected:
    /// `advisory(.suggestLightingCheck)` (section 7.6). Internal: `ScanEngine` reads it.
    var shouldSuggestLightingCheck: Bool {
        poorRateStreak > 0
    }
}
