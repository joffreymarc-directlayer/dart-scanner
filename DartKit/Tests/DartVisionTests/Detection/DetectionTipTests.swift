import Foundation
import simd
import Testing
import DartCore
@testable import DartVision

/// The tip, in the canvas, over the four reference poses (VISION.md §10.2, group T): 500 darts per case in release
/// builds, fewer in debug builds. Each scenario is rendered once (a lazily built static batch, computed on GCD
/// worker threads) and shared by the tests that read it. The suite is serialised: tests waiting on the same batch
/// would otherwise hold most of the cooperative threads of Swift concurrency and starve the asynchronous tests of
/// other suites (the real-time frame source of `ImagingScriptTests` missed its stop).
///
/// Darts follow the mix of the probe of §5.4: tail up by 0 to 18 degrees, a little sideways lean, three barrel
/// colours, 20 % black points (`DetectionHarness.probeDart`). "Visible tip" (T1 to T3) means a steel point: the black
/// point is the documented weak case (§11.1, limit 5), counted in F2 and tested on black beds by T5.
@Suite(.serialized, .tags(.heavy)) struct DetectionTipTests {
    static let count = DetectionHarness.count(500, debug: 200)

    static let nominal = DetectionHarness.batch(DetectionHarness.Setup(), count: count, seed: 101, makeDart: DetectionHarness.probeDart)
    static let withoutPose: [DetectionHarness.Trial] = {
        var setup = DetectionHarness.Setup()
        setup.parameters.usePoseForTipEnd = false
        return DetectionHarness.batch(setup, count: count, seed: 101, makeDart: DetectionHarness.probeDart)
    }()
    static let softShadow: [DetectionHarness.Trial] = {
        var setup = DetectionHarness.Setup()
        setup.shadowStrength = 0.65
        return DetectionHarness.batch(setup, count: count, seed: 202, makeDart: DetectionHarness.probeDart)
    }()
    static let hardShadow: [DetectionHarness.Trial] = {
        var setup = DetectionHarness.Setup()
        setup.shadowStrength = 0.20
        return DetectionHarness.batch(setup, count: count, seed: 303, makeDart: DetectionHarness.probeDart)
    }()
    static let blackOnBlack = DetectionHarness.batch(DetectionHarness.Setup(), count: count, seed: 404) { random in
        SyntheticDart(tip: DetectionHarness.tip(on: .black, random: &random), leanUpDegrees: random.uniform(0...18),
                      leanSideDegrees: random.uniform(-6...6), style: .allBlack)
    }
    static let falling = DetectionHarness.batch(DetectionHarness.Setup(), count: count, seed: 505) { random in
        var dart = DetectionHarness.probeDart(&random)
        dart.leanUpDegrees = -random.uniform(0...18)
        return dart
    }
    static let occluded = DetectionHarness.occludedBatch(count: count, seed: 606)

    private static func visible(_ trials: [DetectionHarness.Trial]) -> [DetectionHarness.Trial] {
        trials.filter { DetectionHarness.hasSteelPoint($0.dart) }
    }

    // MARK: Report

    /// Not an assertion: the accuracy report asked for by the lot (per pose, per lean, per lighting), printed once.
    @Test func t0_accuracyReport() {
        var lines = ["DETECTION REPORT (\(Self.count) darts per scenario; error in mm; high = tier high)"]
        for (name, trials) in [("no shadow", Self.nominal), ("shadow 0.65", Self.softShadow), ("shadow 0.20", Self.hardShadow),
                               ("falling (tail down)", Self.falling), ("all black on black", Self.blackOnBlack)] {
            lines.append(DetectionHarness.summary(name, trials))
            for pose in SupportPoses.allCases {
                lines.append(DetectionHarness.summary("  pose \(pose)", trials.filter { $0.pose == pose }))
            }
            for (low, high) in [(-18.0, -9.0), (-9.0, 0.0), (0.0, 6.0), (6.0, 12.0), (12.0, 18.0)] {
                let bucket = trials.filter { $0.dart.leanUpDegrees >= low && $0.dart.leanUpDegrees < high }
                if !bucket.isEmpty { lines.append(DetectionHarness.summary("  lean \(Int(low))..\(Int(high))°", bucket)) }
            }
        }
        print(lines.joined(separator: "\n"))
    }

    // MARK: T1

    /// T1: median ≤ 1.2 mm and p95 ≤ 2.0 mm for the darts with a visible tip, without shadow and with a 0.65 shadow.
    @Test func t1_tipError() {
        for (name, trials) in [("no shadow", Self.nominal), ("shadow 0.65", Self.softShadow)] {
            let errors = Self.visible(trials).map(\.error)
            let median = DetectionHarness.quantile(errors, 0.5) ?? .infinity
            let p95 = DetectionHarness.quantile(errors, 0.95) ?? .infinity
            #expect(median <= 1.2, "\(name): median \(median)")
            #expect(p95 <= 2.0, "\(name): p95 \(p95)")
        }
    }

    // MARK: T2

    /// T2: mean signed error along the dart axis (the cap correction) within ±0.3 mm, on the visible tips of the
    /// scene without shadow (gross failures beyond 5 mm left out: they are not a bias).
    @Test func t2_alongAxisBias() {
        let along = Self.visible(Self.nominal).filter { $0.error < 5 }.compactMap { $0.alongError(camera: $0.pose.camera) }
        #expect(along.count > Self.count / 2)
        let mean = along.reduce(0, +) / Double(max(1, along.count))
        #expect(abs(mean) <= 0.3, "mean along-axis error \(mean)")
    }

    // MARK: T3

    /// T3: the right end is the tip for ≥ 99 % of visible darts with the camera under the board (poses A to C), and
    /// for ≥ 95 % (all poses) without the pose rule.
    @Test func t3_tipEnd() {
        let below = Self.visible(Self.nominal).filter { $0.pose != .d }
        let right = below.filter { $0.hasCorrectEnd(camera: $0.pose.camera) }.count
        #expect(Double(right) >= 0.99 * Double(below.count), "\(right) of \(below.count) with the pose rule")
        let withoutPose = Self.visible(Self.withoutPose)
        let rightWithout = withoutPose.filter { $0.hasCorrectEnd(camera: $0.pose.camera) }.count
        #expect(Double(rightWithout) >= 0.95 * Double(withoutPose.count), "\(rightWithout) of \(withoutPose.count) without it")
    }

    // MARK: T4

    /// T4: the best segment is the true one for ≥ 97 % of the darts more than 2 mm from a wire, ≥ 93 % in all; on the
    /// darts with a visible tip, like T1 (the whole mix, all-black darts on black beds included, is in the report).
    @Test func t4_segment() {
        let trials = Self.visible(Self.nominal)
        let away = trials.filter { DetectionHarness.distanceToBoundary($0.dart.tip) > 2 }
        let awayCorrect = away.filter(\.isCorrect).count
        let correct = trials.filter(\.isCorrect).count
        #expect(Double(awayCorrect) >= 0.97 * Double(away.count), "\(awayCorrect) of \(away.count) away from wires")
        #expect(Double(correct) >= 0.93 * Double(trials.count), "\(correct) of \(trials.count) in all")
    }

    // MARK: T5

    /// T5: an all-black dart on black sectors: at most 1 % of the high answers are wrong.
    @Test func t5_blackDartOnBlackSectors() {
        let highs = Self.blackOnBlack.filter { $0.tier == .high }
        let wrong = highs.filter { !$0.isCorrect }.count
        #expect(Double(wrong) <= 0.01 * Double(highs.count), "\(wrong) wrong of \(highs.count) high")
    }

    // MARK: T6

    /// T6: a second dart whose tip is in the band hidden by the first: `tipPossiblyOccluded` and not high in ≥ 90 %.
    @Test func t6_hiddenTip() {
        let trials = Self.occluded
        #expect(trials.count >= Self.count / 2)
        let flagged = trials.filter {
            $0.observation?.flags.contains(.tipPossiblyOccluded) == true && $0.tier != .high
        }.count
        #expect(Double(flagged) >= 0.9 * Double(trials.count), "\(flagged) of \(trials.count)")
    }

    // MARK: T7

    /// T7: a 0.20 shadow, outside the model: ≥ 90 % low, and ≤ 1 % wrong among the high ones (as F2, T5, T8).
    @Test func t7_hardShadow() {
        let trials = Self.hardShadow
        let low = trials.filter { $0.tier == .low }.count
        let highs = trials.filter { $0.tier == .high }
        let highWrong = highs.filter { !$0.isCorrect }.count
        #expect(Double(low) >= 0.9 * Double(trials.count), "\(low) low of \(trials.count)")
        #expect(Double(highWrong) <= 0.01 * Double(highs.count), "\(highWrong) wrong of \(highs.count) high")
    }

    // MARK: T8

    /// T8: falling darts (tail down by 0 to 18 degrees): ≥ 95 % correct among the high ones.
    @Test func t8_fallingDarts() {
        let highs = Self.falling.filter { $0.tier == .high }
        let correct = highs.filter(\.isCorrect).count
        #expect(Double(correct) >= 0.95 * Double(highs.count), "\(correct) correct of \(highs.count) high")
    }
}
