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
    /// Section 4.8, on a reference canvas of the empty board and a current canvas with one dart planted:
    ///
    /// 1. the dart is detected (`DifferencingDartDetector`, one new dart) and its tip compared with the tip the
    ///    player tapped;
    /// 2. shadow depth: the 5th percentile of `α*/g` over the changed pixels (`‖c − g·r‖ ≥ τ`) whose colour did not
    ///    change (`‖c − α*·r‖ < τ`, darker than the reference), outside the dart's corridor (20 mm on each side of the
    ///    segment from the tapped tip to the far end of the dart; the stretch beyond the tip, where an aligned shadow
    ///    falls, is kept);
    /// 3. `recommendedShadowLowerBound = clamp(q05 − 0.08, 0.2, 0.5)`, 0.5 with fewer than 50 shadow pixels; the
    ///    detection is then run again with that bound and `tipError` is its distance to the tapped tip;
    /// 4. verdict: `verified` under 2 mm; otherwise the first cause that holds: `viewTooFrontal` (the camera looks
    ///    at the tip more steeply than `poseMinTanObliquity`), `pointNotVisible` (no dart found, or the point flagged
    ///    invisible), `shadowTooHard` (shadows deeper than the lowest bound the model accepts plus its margin), else
    ///    `failed`.
    public static func run(reference: CanvasImage, current: CanvasImage, confirmedTip: BoardPoint,
                           calibration: BoardCalibration, noiseSigma: Double,
                           parameters: DetectionParameters) -> LightingCheckResult {
        let detector = DifferencingDartDetector()
        let first = detect(detector, reference: reference, current: current, calibration: calibration,
                           noiseSigma: noiseSigma, parameters: parameters)
        let tau = DifferencingDartDetector.threshold(noiseSigma: noiseSigma, parameters: parameters)
        let metricTip = calibration.ringRadii.fromNominal(confirmedTip)
        let axis = first.flatMap { ConfidenceModel.unit($0.axis) }
            ?? ConfidenceModel.confidenceAxis(.zero, tip: metricTip, footPoint: calibration.pose.footPoint)
        let reach = max(first?.visibleLength ?? 0, parameters.maxDartLength)
        let depth = shadowDepth(reference: reference, current: current, tip: metricTip, axis: axis, reach: reach,
                                threshold: tau, parameters: parameters)
        var bound = parameters.shadowLowerBound
        if let depth {
            bound = min(maximumBound, max(minimumBound, depth - margin))
        } else {
            bound = maximumBound
        }
        var tuned = parameters
        tuned.shadowLowerBound = bound
        let second = detect(detector, reference: reference, current: current, calibration: calibration,
                            noiseSigma: noiseSigma, parameters: tuned)
        let tipError = second.map { hypot($0.tip.x - confirmedTip.x, $0.tip.y - confirmedTip.y) } ?? .infinity
        let verdict: LightingCheckResult.Verdict
        if tipError < verifiedDistance {
            verdict = .verified
        } else if calibration.pose.tanObliquity(at: metricTip) < parameters.poseMinTanObliquity {
            verdict = .viewTooFrontal
        } else if second == nil || second?.flags.contains(.pointNotVisible) == true {
            verdict = .pointNotVisible
        } else if let depth, depth - margin < minimumBound {
            verdict = .shadowTooHard
        } else {
            verdict = .failed
        }
        return LightingCheckResult(verdict: verdict, tipError: tipError, shadowDepth: depth,
                                   recommendedShadowLowerBound: bound)
    }
}

// MARK: - Helpers (lot V3)

extension LightingCheck {
    /// A detected tip within this distance of the tapped one verifies the chain, mm.
    static let verifiedDistance: Double = 2
    /// `shadowLowerBound = clamp(q05 − margin, minimumBound, maximumBound)`.
    static let margin: Double = 0.08
    static let minimumBound: Double = 0.2
    static let maximumBound: Double = 0.5
    /// Fewer shadow pixels than this: no depth is measured.
    static let minimumShadowPixels = 50
    /// Half-width of the dart's corridor, mm: a flight is 34 mm wide.
    static let corridorHalfWidth: Double = 20

    /// The first candidate of the detector for one new dart; nil when the scene is not read as darts.
    static func detect(_ detector: DifferencingDartDetector, reference: CanvasImage, current: CanvasImage,
                       calibration: BoardCalibration, noiseSigma: Double, parameters: DetectionParameters) -> DartCandidate? {
        let request = DetectionRequest(current: current, reference: reference, emptyReference: reference, knownDarts: [],
                                       calibration: calibration, noiseSigma: noiseSigma, parameters: parameters)
        let analysis = detector.analyse(request)
        return analysis.kind == .darts ? analysis.darts.first : nil
    }

    /// The 5th percentile of `α*/g` over the shadow pixels (step 2); nil with fewer than 50 of them.
    static func shadowDepth(reference: CanvasImage, current: CanvasImage, tip: BoardPoint, axis: SIMD2<Double>,
                            reach: Double, threshold: Double, parameters: DetectionParameters) -> Double? {
        let evidence = ChangeEvidence(reference: reference, current: current, excluded: CanvasMask(), threshold: threshold,
                                      parameters: parameters)
        let side = evidence.side
        let r = evidence.blurredReference.pixels, c = evidence.blurredCurrent.pixels
        let g = Float(evidence.gain)
        let tau = Float(threshold)
        let tipPoint = SIMD2(tip.x, tip.y)
        var ratios: [Double] = []
        for y in 0..<side {
            for x in 0..<side {
                let index = y * side + x
                guard evidence.valid[index] != 0 else { continue }
                let o = index * 3
                let rv = SIMD3(Float(r[o]), Float(r[o + 1]), Float(r[o + 2]))
                let cv = SIMD3(Float(c[o]), Float(c[o + 1]), Float(c[o + 2]))
                guard simd_length(cv - g * rv) >= tau else { continue }
                let alpha = simd_dot(cv, rv) / (simd_dot(rv, rv) + 1)
                guard alpha < g, simd_length(cv - alpha * rv) < tau else { continue }
                // Outside the corridor of the dart: from the tip to its far end, `corridorHalfWidth` on each side.
                let point = BlobAnalysis.point(ofIndex: index)
                let along = simd_dot(point - tipPoint, axis)
                let across = abs(simd_dot(point - tipPoint, SIMD2(-axis.y, axis.x)))
                if along >= 0, along <= reach, across <= corridorHalfWidth { continue }
                ratios.append(Double(alpha / max(g, 1e-6)))
            }
        }
        guard ratios.count >= minimumShadowPixels else { return nil }
        return LightingCheckQuantile.value(ratios, 0.05)
    }
}

/// Quantile of a list, nearest rank (lot V3, internal).
enum LightingCheckQuantile {
    static func value(_ values: [Double], _ fraction: Double) -> Double? {
        let sorted = values.filter { $0.isFinite }.sorted()
        guard !sorted.isEmpty else { return nil }
        let position = min(sorted.count - 1, max(0, Int((fraction * Double(sorted.count - 1)).rounded())))
        return sorted[position]
    }
}
