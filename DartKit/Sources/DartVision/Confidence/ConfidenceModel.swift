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
    private let board: BoardGeometry
    private let parameters: ConfidenceParameters

    public init(board: BoardGeometry = .standard, parameters: ConfidenceParameters = .init()) {
        self.board = board
        self.parameters = parameters
    }

    /// Section 7.1: `σ_across = √(σ_cal² + (0.5/ppm)²)`, `σ_along = √(σ_cal² + (1.0/ppm)² + (h·tan θ)²)`, along the
    /// dart axis.
    ///
    /// Reads stored fields of the calibration only (`quality.edgeResidualRMS`, `boardToImage`, `pose`, `ringRadii`).
    /// `σ_cal = max(0.3, RMS)`; a calibration that was never assessed on a still (RMS unknown) is taken as 1 mm, the
    /// cautious side. `ppm` is the worst-direction source scale at the tip. Sigmas the detector supplies win; a
    /// candidate without an axis gets the direction that leaves the camera foot point.
    public func uncertainty(for candidate: DartCandidate, calibration: BoardCalibration) -> TipUncertainty {
        let metric = calibration.ringRadii.fromNominal(candidate.tip)
        let axis = ConfidenceModel.confidenceAxis(candidate.axis, tip: metric, footPoint: calibration.pose.footPoint)
        let rms = calibration.quality.edgeResidualRMS ?? ConfidenceModel.unassessedCalibrationSigma
        let sigmaCalibration = max(parameters.minCalibrationSigma, rms.isFinite ? rms : ConfidenceModel.unassessedCalibrationSigma)
        var ppm = calibration.boardToImage.localScale(at: SIMD2(metric.x, metric.y)).min
        if !(ppm.isFinite && ppm > 0) { ppm = ConfidenceModel.fallbackPixelsPerMillimetre }
        let hidden = candidate.flags.contains(.lowTipContrast) ? parameters.hiddenTipLengthLowContrast : parameters.hiddenTipLength
        var tanTheta = calibration.pose.tanObliquity(at: metric)
        if !tanTheta.isFinite { tanTheta = 0 }
        let across = parameters.acrossPixelSigma / ppm, along = parameters.alongPixelSigma / ppm, lean = hidden * tanTheta
        let sigmaAcross = (sigmaCalibration * sigmaCalibration + across * across).squareRoot()
        let sigmaAlong = (sigmaCalibration * sigmaCalibration + along * along + lean * lean).squareRoot()
        return TipUncertainty(sigmaAlong: ConfidenceModel.usable(candidate.sigmaAlong) ?? sigmaAlong,
                              sigmaAcross: ConfidenceModel.usable(candidate.sigmaAcross) ?? sigmaAcross,
                              axis: axis)
    }

    /// Probability of each hit: each cell of a `gridSide x gridSide` grid over ±`gridSpanSigmas` sigma is read at its
    /// four quarter points (section 7.2).
    ///
    /// Section 7.2. The grid is laid in the metric frame of the board (`radii`), each node is brought back to
    /// nominal coordinates and scored by `BoardGeometry.hit(at:)`. Each cell of the grid is read at its four
    /// quarter points (2x2 sub-cells, each with its own Gaussian weight) rather than at its centre alone: with one
    /// read per cell, a wire that runs along a column of the grid (a dart axis parallel to a radial wire, the usual
    /// case at the top and bottom of the board) moves the whole column, up to 0.11 of the mass, to one side, and
    /// the worst gap to a Monte-Carlo over 300 darts reaches 0.028 to 0.044 with the sample (F1 allows 0.03). With
    /// the quarter points it stays near 0.01. With an occlusion span the distribution is the mean of
    /// `occlusionSamples` Gaussians spread evenly from the tip to `occlusionSpan` mm further towards the tip
    /// (against `uncertainty.axis`, which points to the flight). At most `maxCandidates` hits of probability
    /// `minCandidateProbability` or more are kept, renormalised, most probable first; never empty.
    public func posterior(tip: BoardPoint, uncertainty: TipUncertainty, occlusionSpan: Double,
                          radii: RingRadii) -> [HitCandidate] {
        var weights = [Double](repeating: 0, count: ConfidenceModel.hitSlots)
        let metric = radii.fromNominal(tip)
        let axis = ConfidenceModel.unit(uncertainty.axis) ?? SIMD2(0, 1)
        let normal = SIMD2(-axis.y, axis.x)
        let along = ConfidenceModel.usable(uncertainty.sigmaAlong) ?? 0
        let across = ConfidenceModel.usable(uncertainty.sigmaAcross) ?? 0
        let side = max(1, parameters.gridSide)
        let span = parameters.gridSpanSigmas.isFinite ? max(0, parameters.gridSpanSigmas) : 3
        let samples = occlusionSpan.isFinite && occlusionSpan > 0 ? max(1, parameters.occlusionSamples) : 1
        let occlusion = occlusionSpan.isFinite && occlusionSpan > 0 ? occlusionSpan : 0
        // Quarter points of the cells: 2·side positions per axis, at the centres of the half-cells.
        let fine = 2 * side
        let offsets = (0..<fine).map { index in ((Double(index) + 0.5) / Double(fine) * 2 - 1) * span }
        let gaussian = offsets.map { exp(-$0 * $0 / 2) }
        var total = 0.0
        for sample in 0..<samples {
            let shift = samples > 1 ? occlusion * Double(sample) / Double(samples - 1) : 0
            let centre = SIMD2(metric.x, metric.y) - axis * shift
            for i in 0..<fine {
                let alongOffset = axis * (offsets[i] * along)
                for j in 0..<fine {
                    let weight = gaussian[i] * gaussian[j]
                    let position = centre + alongOffset + normal * (offsets[j] * across)
                    let nominal = radii.toNominal(BoardPoint(x: position.x, y: position.y))
                    weights[ConfidenceModel.slot(of: board.hit(at: nominal))] += weight
                    total += weight
                }
            }
        }
        guard total > 0, total.isFinite else {
            return [HitCandidate(hit: board.hit(at: tip), probability: 1)]
        }
        var ranked: [(slot: Int, probability: Double)] = []
        for slot in 0..<ConfidenceModel.hitSlots where weights[slot] > 0 {
            ranked.append((slot, weights[slot] / total))
        }
        // Most probable first; equal probabilities in the fixed slot order, so that the result never depends on
        // anything but the input.
        ranked.sort { $0.probability != $1.probability ? $0.probability > $1.probability : $0.slot < $1.slot }
        var kept = ranked.prefix(max(1, parameters.maxCandidates)).filter { $0.probability >= parameters.minCandidateProbability }
        if kept.isEmpty, let first = ranked.first { kept = [first] }
        var keptTotal = 0.0
        for entry in kept {
            keptTotal += entry.probability
        }
        return kept.map { HitCandidate(hit: ConfidenceModel.hit(ofSlot: $0.slot), probability: $0.probability / keptTotal) }
    }

    /// Product of the flag factors and of the detector score (section 7.3), before caps.
    public func quality(flags: DartFlags, score: Double) -> Double {
        var q = score.isFinite ? min(1, max(0, score)) : 0
        let factors: [(DartFlags, Double)] = [
            (.pointNotVisible, parameters.severeFlagFactor), (.implausiblyLong, parameters.severeFlagFactor),
            (.nearEndWide, parameters.majorFlagFactor), (.tipEndAmbiguous, parameters.majorFlagFactor),
            (.lowElongation, parameters.majorFlagFactor),
            (.tipPossiblyOccluded, parameters.occlusionFactor),
            (.beyondVisitLimit, parameters.visitLimitFactor),
            (.fewNarrowPixels, parameters.moderateFlagFactor), (.clutter, parameters.moderateFlagFactor),
            (.earlierDartDisturbed, parameters.moderateFlagFactor), (.multiDartStill, parameters.moderateFlagFactor),
            (.lowTipContrast, parameters.minorFlagFactor), (.calibrationFair, parameters.minorFlagFactor),
            (.afterRelock, parameters.minorFlagFactor), (.nearCanvasEdge, parameters.minorFlagFactor),
            (.emptyReferenceStale, parameters.minorFlagFactor),
        ]
        for (flag, factor) in factors where flags.contains(flag) {
            q *= factor
        }
        return q
    }

    /// One dart for the game layer (section 7): the uncertainty of 7.1, the posterior of 7.2, the quality of 7.3,
    /// then the caps.
    ///
    /// Flags added here, the same for every detector: `calibrationFair` or `calibrationPoor` from the grade of the
    /// calibration, and `warmUp` while `context.warmUpRemaining > 0`. Caps: 0.80 with `calibrationPoor`, 0.84 with
    /// `warmUp`, 0.80 with `crossViewpoint` (the parameters' values), and `context.cap`.
    public func observe(_ candidate: DartCandidate, id: UUID, visit: Int, indexInVisit: Int, timestamp: TimeInterval,
                        source: ObservationSource, calibration: BoardCalibration,
                        context: ConfidenceContext) -> DartObservation {
        var flags = candidate.flags
        switch calibration.quality.grade {
        case .good: break
        case .fair: flags.insert(.calibrationFair)
        case .poor: flags.insert(.calibrationPoor)
        }
        if context.warmUpRemaining > 0 { flags.insert(.warmUp) }
        let uncertainty = uncertainty(for: candidate, calibration: calibration)
        let candidates = posterior(tip: candidate.tip, uncertainty: uncertainty,
                                   occlusionSpan: candidate.occlusionSpan, radii: calibration.ringRadii)
        var confidence = (candidates.first?.probability ?? 0) * quality(flags: flags, score: candidate.score)
        if flags.contains(.calibrationPoor) { confidence = min(confidence, parameters.poorCalibrationCap) }
        if flags.contains(.warmUp) { confidence = min(confidence, parameters.warmUpCap) }
        if flags.contains(.crossViewpoint) { confidence = min(confidence, parameters.crossViewpointCap) }
        if context.cap.isFinite { confidence = min(confidence, max(0, context.cap)) }
        // A tip that is not a point of the board plane was not read: its posterior is all MISS (`hit(at:)` is total),
        // which must not reach the game as a certain miss (review RV2).
        if !(candidate.tip.x.isFinite && candidate.tip.y.isFinite) { confidence = 0 }
        if !confidence.isFinite { confidence = 0 }
        return DartObservation(id: id, visit: visit, indexInVisit: indexInVisit, timestamp: timestamp, tip: candidate.tip,
                               uncertainty: uncertainty, candidates: candidates, nearbyHits: nearbyHits(around: candidate.tip),
                               confidence: confidence, tier: context.thresholds.tier(for: confidence), flags: flags,
                               source: source)
    }

    /// Observation for a tip given by the player (tap or drag): confidence 1, source `.tappedOnPhoto`.
    ///
    /// The player's answer is final: one candidate of probability 1, tier `high`, no flag, and zero sigmas, which
    /// also turns off the edge check of a position-dependent game (section 7.4).
    public func observation(forConfirmedTip tip: BoardPoint, id: UUID, visit: Int, indexInVisit: Int,
                            timestamp: TimeInterval) -> DartObservation {
        DartObservation(id: id, visit: visit, indexInVisit: indexInVisit, timestamp: timestamp, tip: tip,
                        uncertainty: TipUncertainty(sigmaAlong: 0, sigmaAcross: 0, axis: SIMD2(0, 1)),
                        candidates: [HitCandidate(hit: board.hit(at: tip), probability: 1)],
                        nearbyHits: nearbyHits(around: tip), confidence: 1, tier: .high, flags: [],
                        source: .tappedOnPhoto)
    }
}

// MARK: - Helpers (lot V3)

extension ConfidenceModel {
    /// Distinct hits at the tip and on circles of `nearbyRadii` around it, nearest first (section 9.1).
    func nearbyHits(around tip: BoardPoint) -> [Hit] {
        var hits: [Hit] = [board.hit(at: tip)]
        for radius in parameters.nearbyRadii where radius.isFinite && radius > 0 {
            for step in 0..<ConfidenceModel.nearbyDirections {
                let angle = Double(step) * 2 * .pi / Double(ConfidenceModel.nearbyDirections)
                let hit = board.hit(at: BoardPoint(x: tip.x + radius * sin(angle), y: tip.y + radius * cos(angle)))
                if !hits.contains(hit) { hits.append(hit) }
            }
        }
        return hits
    }

    /// Directions sampled on each circle of `nearbyRadii`.
    static let nearbyDirections = 16
    /// σ_cal of a calibration whose edges were never measured (`edgeResidualRMS == nil`), mm.
    static let unassessedCalibrationSigma = 1.0
    /// Scale used when the homography gives none at the tip, px/mm (the hard floor of the calibration gate).
    static let fallbackPixelsPerMillimetre = 0.8
    /// Number of distinct hits: MISS, SB, DB and 20 sectors in three beds.
    static let hitSlots = 63

    /// A fixed index for each of the 63 hits.
    static func slot(of hit: Hit) -> Int {
        let number = hit.number ?? 0
        switch hit.bed {
        case .miss: return 0
        case .outerBull: return 1
        case .innerBull: return 2
        case .single: return 2 + number
        case .double: return 22 + number
        case .treble: return 42 + number
        }
    }

    static func hit(ofSlot slot: Int) -> Hit {
        switch slot {
        case 1: return .outerBull
        case 2: return .innerBull
        case 3...22: return .single(slot - 2)
        case 23...42: return .double(slot - 22)
        case 43...62: return .treble(slot - 42)
        default: return .miss
        }
    }

    /// A finite, non-negative value; nil otherwise.
    static func usable(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value >= 0 else { return nil }
        return value
    }

    static func unit(_ vector: SIMD2<Double>) -> SIMD2<Double>? {
        let length = simd_length(vector)
        guard length.isFinite, length > 1e-12 else { return nil }
        return vector / length
    }

    /// The candidate's axis, or the direction that leaves the camera foot point (section 7.1), or +y.
    static func confidenceAxis(_ axis: SIMD2<Double>, tip: BoardPoint, footPoint: BoardPoint) -> SIMD2<Double> {
        if let given = unit(axis) { return given }
        if let away = unit(SIMD2(tip.x - footPoint.x, tip.y - footPoint.y)) { return away }
        return SIMD2(0, 1)
    }
}
