import Foundation
import simd
import Testing
import DartCore
@testable import DartVision

/// The confidence model, the observation's game-aware tier and the trust tracker (VISION.md §7): tests F1 and F4
/// to F7 of §10.2, and the formulas they rest on.
@Suite struct ConfidenceModelTests {
    private let model = ConfidenceModel()
    private let id = UUID(uuidString: "00000000-0000-0000-0000-00000000C0DE") ?? UUID()

    private func observation(_ candidates: [(Hit, Double)], confidence: Double, flags: DartFlags = [],
                             nearby: [Hit] = []) -> DartObservation {
        DartObservation(id: id, visit: 1, indexInVisit: 0, timestamp: 0, tip: BoardPoint(x: 0, y: 100),
                        uncertainty: TipUncertainty(sigmaAlong: 0.9, sigmaAcross: 0.4, axis: SIMD2(0, 1)),
                        candidates: candidates.map { HitCandidate(hit: $0.0, probability: $0.1) }, nearbyHits: nearby,
                        confidence: confidence, tier: ConfidenceThresholds.standard.tier(for: confidence), flags: flags,
                        source: .liveCamera)
    }

    // MARK: Thresholds and observation helpers

    @Test func thresholds_tiers() {
        let thresholds = ConfidenceThresholds.standard
        #expect(thresholds.tier(for: 0.85) == .high)
        #expect(thresholds.tier(for: 0.8499) == .medium)
        #expect(thresholds.tier(for: 0.50) == .medium)
        #expect(thresholds.tier(for: 0.4999) == .low)
        #expect(thresholds.tier(for: 1) == .high)
        #expect(thresholds.tier(for: 0) == .low)
        #expect(thresholds.tier(for: .nan) == .low)
        var degraded = thresholds
        degraded.high = 0.95
        #expect(degraded.tier(for: 0.9) == .medium)
    }

    @Test func observation_bestAndCorrectionChoices() {
        let seen = observation([(.single(11), 0.6), (.single(14), 0.4)], confidence: 0.6,
                               nearby: [.single(11), .double(11), .single(8), .single(14), .treble(11)])
        #expect(seen.best == .single(11))
        #expect(seen.correctionChoices() == [.single(11), .single(14), .double(11), .single(8)])
        #expect(seen.correctionChoices(minimum: 2) == [.single(11), .single(14)])
        #expect(seen.correctionChoices(minimum: 10) == [.single(11), .single(14), .double(11), .single(8), .treble(11)])
        // A hand-made observation without candidates does not trap.
        let empty = observation([], confidence: 0.3, nearby: [.miss])
        #expect(empty.best == .miss)
        #expect(empty.correctionChoices() == [.miss])
        #expect(empty.tier(collapsingBy: { $0 }) == .low)
    }

    // MARK: F5

    /// F5: candidates S11 at 0.6 and S14 at 0.4, confidence 0.6, built by the memberwise initialiser.
    @Test func f5_collapsedTier() {
        let base = observation([(.single(11), 0.6), (.single(14), 0.4)], confidence: 0.6)
        // (a) Same effect, no flag: 0.6 · 1.0 / 0.6 = 1.0, high.
        #expect(base.tier(collapsingBy: { _ in 0 }) == .high)
        // (b) Different effects: the tier stays medium.
        #expect(base.tier(collapsingBy: { $0 }) == .medium)
        #expect(base.tier == .medium)
        // (c) Same effect, each cap keeps the dart below the high tier: 0.84, 0.80, 0.80.
        for flag in [DartFlags.warmUp, .calibrationPoor, .crossViewpoint] {
            let capped = observation([(.single(11), 0.6), (.single(14), 0.4)], confidence: 0.6, flags: flag)
            #expect(capped.tier(collapsingBy: { _ in 0 }) == .medium, "flag \(flag.rawValue)")
        }
        // The caps are exactly 0.84 and 0.80: with thresholds just below them, the tier is high again.
        var thresholds = ConfidenceThresholds()
        thresholds.high = 0.84
        let warm = observation([(.single(11), 0.6), (.single(14), 0.4)], confidence: 0.6, flags: .warmUp)
        #expect(warm.tier(collapsingBy: { _ in 0 }, thresholds: thresholds) == .high)
        thresholds.high = 0.8001
        let poor = observation([(.single(11), 0.6), (.single(14), 0.4)], confidence: 0.6, flags: .calibrationPoor)
        #expect(poor.tier(collapsingBy: { _ in 0 }, thresholds: thresholds) == .medium)
        // The quality of the cues still counts: confidence 0.45 from a quality of 0.75 collapses to 0.75.
        let flagged = observation([(.single(11), 0.6), (.single(14), 0.4)], confidence: 0.45)
        #expect(flagged.tier(collapsingBy: { _ in 0 }) == .medium)
        // A zero first probability (hand-made): the collapsed value is the confidence itself.
        let degenerate = observation([(.single(11), 0), (.single(14), 0)], confidence: 0.9)
        #expect(degenerate.tier(collapsingBy: { _ in 0 }) == .high)
    }

    // MARK: F6

    /// F6: two corrected highs among the last 15 raise the high threshold to 0.95; 15 darts without a correction
    /// bring it back to 0.85.
    @Test func f6_trustTracker() {
        var tracker = TrustTracker()
        #expect(tracker.thresholds.high == 0.85)
        for _ in 0..<10 { tracker.record(tier: .high, wasCorrected: false) }
        tracker.record(tier: .high, wasCorrected: true)
        #expect(tracker.thresholds.high == 0.85)
        #expect(!tracker.accuracyDegraded)
        // A corrected medium dart does not count as a corrected high one.
        tracker.record(tier: .medium, wasCorrected: true)
        #expect(tracker.thresholds.high == 0.85)
        tracker.record(tier: .high, wasCorrected: true)
        #expect(tracker.thresholds.high == 0.95)
        #expect(tracker.accuracyDegraded)
        for index in 0..<15 {
            #expect(tracker.thresholds.high == 0.95, "after \(index) uncorrected darts")
            tracker.record(tier: .high, wasCorrected: false)
        }
        #expect(tracker.thresholds.high == 0.85)
        #expect(!tracker.accuracyDegraded)
        // Two corrected highs further apart than the window do not degrade.
        var spread = TrustTracker()
        spread.record(tier: .high, wasCorrected: true)
        for _ in 0..<15 { spread.record(tier: .high, wasCorrected: false) }
        spread.record(tier: .high, wasCorrected: true)
        #expect(!spread.accuracyDegraded)
    }

    /// Section 7.6, second rule: more than 30 % of the last 12 camera darts low or corrected suggests the lighting
    /// check at once, and the scan mode when it persists over another window.
    @Test func trustTracker_scanSuggestion() {
        var tracker = TrustTracker()
        for _ in 0..<12 { tracker.record(tier: .high, wasCorrected: false) }
        #expect(!tracker.shouldSuggestLightingCheck && !tracker.shouldSuggestScanMode)
        for _ in 0..<4 { tracker.record(tier: .low, wasCorrected: false) }
        // 4 of the last 12 (33 %) are low.
        #expect(tracker.shouldSuggestLightingCheck)
        #expect(!tracker.shouldSuggestScanMode)
        var still = tracker
        for index in 0..<13 {
            still.record(tier: index % 2 == 0 ? .low : .high, wasCorrected: false)
        }
        #expect(still.shouldSuggestScanMode)
        // Back to good darts: both suggestions stop.
        for _ in 0..<12 { still.record(tier: .high, wasCorrected: false) }
        #expect(!still.shouldSuggestLightingCheck && !still.shouldSuggestScanMode)
    }

    // MARK: Model formulas

    /// Section 7.1 at the reference pose A: σ_across ≈ 0.37 mm and σ_along ≈ 0.85 mm (§7.1, [sonde]).
    @Test func uncertainty_formula() throws {
        let calibration = SupportPoses.a.camera.calibration(grade: .good)
        let tip = BoardPoint(x: 0, y: 0)
        let candidate = DartCandidate(tip: tip, axis: .zero, silhouette: CanvasMask())
        let sigma = model.uncertainty(for: candidate, calibration: calibration)
        let ppm = calibration.boardToImage.localScale(at: SIMD2(0, 0)).min
        let tan = calibration.pose.tanObliquity(at: tip)
        #expect(abs(sigma.sigmaAcross - (0.09 + 0.25 / (ppm * ppm)).squareRoot()) < 1e-12)
        #expect(abs(sigma.sigmaAlong - (0.09 + 1 / (ppm * ppm) + (1.5 * tan) * (1.5 * tan)).squareRoot()) < 1e-12)
        #expect(abs(sigma.sigmaAcross - 0.37) < 0.03)
        #expect(abs(sigma.sigmaAlong - 0.85) < 0.1)
        // Without an axis: the direction that leaves the camera foot point.
        let foot = calibration.pose.footPoint
        let away = simd_normalize(SIMD2(-foot.x, -foot.y))
        #expect(simd_length(sigma.axis - away) < 1e-12)
        // Low contrast: 3 mm of hidden point. Detector sigmas win. Poor calibration: σ_cal 0.9.
        var dim = candidate
        dim.flags = .lowTipContrast
        #expect(model.uncertainty(for: dim, calibration: calibration).sigmaAlong > sigma.sigmaAlong + 0.3)
        let supplied = DartCandidate(tip: tip, axis: SIMD2(1, 0), silhouette: CanvasMask(), sigmaAlong: 2, sigmaAcross: 1)
        let given = model.uncertainty(for: supplied, calibration: calibration)
        #expect(given.sigmaAlong == 2 && given.sigmaAcross == 1 && given.axis == SIMD2(1, 0))
        let poor = model.uncertainty(for: candidate, calibration: SupportPoses.a.camera.calibration(grade: .poor))
        #expect(poor.sigmaAcross > 0.9)
    }

    @Test func quality_factors() {
        #expect(model.quality(flags: [], score: 1) == 1)
        #expect(abs(model.quality(flags: .pointNotVisible, score: 1) - 0.4) < 1e-12)
        #expect(abs(model.quality(flags: [.nearEndWide, .clutter], score: 1) - 0.35) < 1e-12)
        #expect(abs(model.quality(flags: [.tipPossiblyOccluded, .beyondVisitLimit], score: 0.5) - 0.18) < 1e-12)
        #expect(abs(model.quality(flags: [.lowTipContrast, .calibrationFair, .afterRelock, .nearCanvasEdge,
                                          .emptyReferenceStale], score: 1) - pow(0.9, 5)) < 1e-12)
        // The caps are not factors.
        #expect(model.quality(flags: [.warmUp, .calibrationPoor, .crossViewpoint], score: 1) == 1)
    }

    /// The posterior: sums to 1, at most 6 entries of at least 0.01, most probable first, and the centre of a bed
    /// is that bed with certainty.
    @Test func posterior_shape() {
        let geometry = BoardGeometry.standard
        let sigma = TipUncertainty(sigmaAlong: 0.9, sigmaAcross: 0.4, axis: SIMD2(0, 1))
        for hit in Hit.all where hit != .miss {
            guard let centre = geometry.centre(of: hit) else { continue }
            let candidates = model.posterior(tip: centre, uncertainty: sigma, occlusionSpan: 0, radii: .nominal)
            #expect(candidates.first?.hit == hit)
        }
        var random = SupportRandom(seed: 9)
        for _ in 0..<200 {
            let tip = random.boardPoint(maxRadius: 175)
            let candidates = model.posterior(tip: tip, uncertainty: sigma, occlusionSpan: 0, radii: .nominal)
            #expect(!candidates.isEmpty && candidates.count <= 6)
            #expect(abs(candidates.reduce(0) { $0 + $1.probability } - 1) < 1e-9)
            #expect(zip(candidates, candidates.dropFirst()).allSatisfy { $0.probability >= $1.probability })
            #expect(Set(candidates.map(\.hit)).count == candidates.count)
        }
        // Zero sigmas: one candidate, the hit under the tip.
        let exact = model.posterior(tip: BoardPoint(x: 0, y: 103), uncertainty: TipUncertainty(sigmaAlong: 0, sigmaAcross: 0, axis: .zero),
                                    occlusionSpan: 0, radii: .nominal)
        #expect(exact == [HitCandidate(hit: .treble(20), probability: 1)])
    }

    /// Observation of a candidate: flags added from the calibration grade and the warm-up, caps applied.
    @Test func observe_flagsAndCaps() {
        let camera = SupportPoses.a.camera
        let candidate = DartCandidate(tip: BoardPoint(x: 0, y: 60), axis: SIMD2(0, 1), silhouette: CanvasMask())
        let good = model.observe(candidate, id: id, visit: 2, indexInVisit: 1, timestamp: 4, source: .liveCamera,
                                 calibration: camera.calibration(grade: .good), context: ConfidenceContext())
        #expect(good.best == .single(20) && good.tier == .high && good.flags.isEmpty)
        #expect(good.confidence == good.candidates[0].probability)
        #expect(good.id == id && good.visit == 2 && good.indexInVisit == 1 && good.timestamp == 4 && good.source == .liveCamera)
        // Nearby hits: the tip's own bed first, then the beds met on circles of 4, 8 and 16 mm (here the 1 and the 5).
        #expect(good.nearbyHits == [.single(20), .single(1), .single(5)])
        let fair = model.observe(candidate, id: id, visit: 2, indexInVisit: 1, timestamp: 4, source: .liveCamera,
                                 calibration: camera.calibration(grade: .fair), context: ConfidenceContext())
        #expect(fair.flags == .calibrationFair && abs(fair.confidence - 0.9 * fair.candidates[0].probability) < 1e-12)
        let poor = model.observe(candidate, id: id, visit: 2, indexInVisit: 1, timestamp: 4, source: .liveCamera,
                                 calibration: camera.calibration(grade: .poor), context: ConfidenceContext())
        #expect(poor.flags == .calibrationPoor && poor.confidence <= 0.80 && poor.tier == .medium)
        let warm = model.observe(candidate, id: id, visit: 2, indexInVisit: 1, timestamp: 4, source: .liveCamera,
                                 calibration: camera.calibration(), context: ConfidenceContext(warmUpRemaining: 2))
        #expect(warm.flags == .warmUp && warm.confidence <= 0.84 && warm.tier == .medium)
        // The last capped dart, then the first free one.
        let last = model.observe(candidate, id: id, visit: 2, indexInVisit: 1, timestamp: 4, source: .liveCamera,
                                 calibration: camera.calibration(), context: ConfidenceContext(warmUpRemaining: 1))
        #expect(last.flags == .warmUp && last.tier == .medium)
        let free = model.observe(candidate, id: id, visit: 2, indexInVisit: 1, timestamp: 4, source: .liveCamera,
                                 calibration: camera.calibration(), context: ConfidenceContext(warmUpRemaining: 0))
        #expect(free.flags.isEmpty && free.tier == .high)
        let cross = model.observe(DartCandidate(tip: BoardPoint(x: 0, y: 60), axis: SIMD2(0, 1), silhouette: CanvasMask(),
                                                flags: .crossViewpoint),
                                  id: id, visit: 0, indexInVisit: 0, timestamp: 0, source: .handheldPhoto,
                                  calibration: camera.calibration(), context: ConfidenceContext())
        #expect(cross.confidence <= 0.80 && cross.tier == .medium)
        let capped = model.observe(candidate, id: id, visit: 2, indexInVisit: 1, timestamp: 4, source: .liveCamera,
                                   calibration: camera.calibration(), context: ConfidenceContext(cap: 0.3))
        #expect(capped.confidence == 0.3 && capped.tier == .low)
        var strict = ConfidenceThresholds()
        strict.high = 0.999_999_9
        let raised = model.observe(DartCandidate(tip: BoardPoint(x: 0, y: 60), axis: SIMD2(0, 1), silhouette: CanvasMask(),
                                                 flags: .lowTipContrast),
                                   id: id, visit: 2, indexInVisit: 1, timestamp: 4, source: .liveCamera,
                                   calibration: camera.calibration(), context: ConfidenceContext(thresholds: strict))
        #expect(raised.tier == .medium)
    }

    @Test func confirmedTip_isCertain() {
        let confirmed = model.observation(forConfirmedTip: BoardPoint(x: 0, y: 103), id: id, visit: 3, indexInVisit: 2, timestamp: 7)
        #expect(confirmed.best == .treble(20) && confirmed.confidence == 1 && confirmed.tier == .high)
        #expect(confirmed.source == .tappedOnPhoto && confirmed.flags.isEmpty)
        #expect(confirmed.candidates == [HitCandidate(hit: .treble(20), probability: 1)])
        #expect(confirmed.uncertainty.sigmaAlong == 0 && confirmed.uncertainty.sigmaAcross == 0)
        #expect(confirmed.visit == 3 && confirmed.indexInVisit == 2 && confirmed.timestamp == 7 && confirmed.id == id)
        #expect(confirmed.nearbyHits.prefix(1) == [.treble(20)] && confirmed.nearbyHits.contains(.single(20)))
    }

    // MARK: F1

    /// F1: the grid posterior against a Monte-Carlo of 100,000 draws on 300 darts (fewer in debug builds): the
    /// largest probability gap is at most 0.03.
    @Test(.tags(.heavy)) func f1_posteriorAgainstMonteCarlo() {
        let draws = DetectionHarness.count(100_000, debug: 10_000)
        let darts = DetectionHarness.count(300, debug: 60)
        let calibration = SupportPoses.a.camera.calibration()
        let geometry = BoardGeometry.standard
        var random = SupportRandom(seed: 77)
        var worst = 0.0
        for _ in 0..<darts {
            let tip = random.boardPoint(maxRadius: 172)
            let candidate = DartCandidate(tip: tip, axis: .zero, silhouette: CanvasMask())
            let sigma = model.uncertainty(for: candidate, calibration: calibration)
            let grid = model.posterior(tip: tip, uncertainty: sigma, occlusionSpan: 0, radii: .nominal)
            var counts: [Hit: Int] = [:]
            let normal = SIMD2(-sigma.axis.y, sigma.axis.x)
            for _ in 0..<draws {
                let p = SIMD2(tip.x, tip.y) + sigma.axis * (random.gaussian() * sigma.sigmaAlong) + normal * (random.gaussian() * sigma.sigmaAcross)
                counts[geometry.hit(at: BoardPoint(x: p.x, y: p.y)), default: 0] += 1
            }
            var hits = Set(counts.keys)
            hits.formUnion(grid.map(\.hit))
            for hit in hits {
                let exact = Double(counts[hit] ?? 0) / Double(draws)
                let estimated = grid.first { $0.hit == hit }?.probability ?? 0
                worst = max(worst, abs(exact - estimated))
            }
        }
        #expect(worst <= 0.03, "largest gap \(worst)")
    }

    // MARK: F4

    /// F4: the ideal case (true tip, q = 1, pose A): 88 to 93 % high, less than 1 % low.
    @Test func f4_idealCase() {
        let calibration = SupportPoses.a.camera.calibration()
        var random = SupportRandom(seed: 44)
        let count = 4000
        var high = 0, low = 0
        for _ in 0..<count {
            let tip = random.boardPoint(maxRadius: 170)
            let seen = model.observe(DartCandidate(tip: tip, axis: .zero, silhouette: CanvasMask()), id: id, visit: 1, indexInVisit: 0,
                                     timestamp: 0, source: .liveCamera, calibration: calibration, context: ConfidenceContext())
            if seen.tier == .high { high += 1 }
            if seen.tier == .low { low += 1 }
        }
        let highShare = Double(high) / Double(count), lowShare = Double(low) / Double(count)
        #expect(highShare >= 0.88 && highShare <= 0.93, "high \(highShare)")
        #expect(lowShare < 0.01, "low \(lowShare)")
    }

    // MARK: F7

    /// F7: a tip hidden over 8 mm across a wire: two candidates, neither above 0.85.
    @Test func f7_hiddenTipAcrossAWire() {
        let calibration = SupportPoses.a.camera.calibration()
        for (radius, wire) in [(60.0, 0), (130.0, 5), (45.0, 13)] {
            // A point of radial wire `wire`, then 4 mm to its anticlockwise side; the hidden span runs across it.
            let direction = BoardModel.wireDirection(wire)
            let towardsClockwise = SIMD2(direction.y, -direction.x)
            let onWire = radius * direction
            let tip = onWire - 4 * towardsClockwise
            let candidate = DartCandidate(tip: BoardPoint(x: tip.x, y: tip.y), axis: -towardsClockwise, silhouette: CanvasMask(),
                                          occlusionSpan: 8, flags: .tipPossiblyOccluded)
            let seen = model.observe(candidate, id: id, visit: 1, indexInVisit: 0, timestamp: 0, source: .liveCamera,
                                     calibration: calibration, context: ConfidenceContext())
            #expect(seen.candidates.count == 2, "wire \(wire): \(seen.candidates)")
            #expect(seen.candidates.allSatisfy { $0.probability < 0.85 })
            #expect(seen.tier != .high)
            // The same tip without the hidden span is certain.
            let visible = model.observe(DartCandidate(tip: BoardPoint(x: tip.x, y: tip.y), axis: -towardsClockwise, silhouette: CanvasMask()),
                                        id: id, visit: 1, indexInVisit: 0, timestamp: 0, source: .liveCamera,
                                        calibration: calibration, context: ConfidenceContext())
            #expect(visible.candidates.count == 1 && visible.tier == .high)
        }
    }
}
