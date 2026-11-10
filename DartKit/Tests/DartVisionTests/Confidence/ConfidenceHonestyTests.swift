import Foundation
import simd
import Testing
import DartCore
@testable import DartVision

/// Honesty of the confidence on detected darts (VISION.md §10.2, F2 and F3): the whole chain, detector then model,
/// on the nominal scene of the T group (500 darts of the probe's mix, 200 in debug builds), the one sample from which
/// every statistic of that scene is read, as in the probe table of §5.4.
@Suite(.serialized, .tags(.heavy)) struct ConfidenceHonestyTests {
    static var trials: [DetectionHarness.Trial] { DetectionTipTests.nominal }

    /// F2: at least 99 % of the high darts are right, and at least 65 % of the darts are high.
    @Test func f2_honestHighTier() {
        let trials = Self.trials
        let highs = trials.filter { $0.tier == .high }
        let right = highs.filter(\.isCorrect).count
        #expect(Double(right) >= 0.99 * Double(highs.count), "\(right) right of \(highs.count) high")
        #expect(Double(highs.count) >= 0.65 * Double(trials.count), "\(highs.count) high of \(trials.count)")
    }

    /// F3: the true bed is among the first three candidates for at least 99 % of the darts whose tip error is
    /// under 3 mm.
    @Test func f3_truthInTopThree() {
        let close = Self.trials.filter { $0.error < 3 }
        let found = close.filter { trial in
            trial.observation?.candidates.prefix(3).contains { $0.hit == trial.truthHit } == true
        }.count
        #expect(close.count > Self.trials.count / 2)
        #expect(Double(found) >= 0.99 * Double(close.count), "\(found) of \(close.count)")
    }

    /// Never a low dart without the player: a low tier always means a confidence under the medium threshold, and
    /// every observation keeps its candidates, a usable uncertainty and a correction list.
    @Test func lowTierIsNeverScored() {
        for trial in Self.trials {
            guard let seen = trial.observation else { continue }
            #expect(seen.tier == ConfidenceThresholds.standard.tier(for: seen.confidence))
            #expect(!seen.candidates.isEmpty && seen.candidates.count <= 6)
            #expect(seen.uncertainty.sigmaAlong > 0 && seen.uncertainty.sigmaAcross > 0)
            #expect(seen.correctionChoices().count >= min(4, Set(seen.candidates.map(\.hit) + seen.nearbyHits).count))
        }
    }
}
