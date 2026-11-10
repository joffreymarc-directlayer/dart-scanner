import Foundation
import simd
import CoreGraphics
import CoreVideo
import DartCore

/// Intermediate images of the differencing detector, for SnapshotTool and the debug overlay.
public struct DetectionDebug: Sendable {
    /// Shadow-tolerant evidence map (D2).
    public var evidence: GrayImage
    /// Binary mask after morphology (D3).
    public var mask: GrayImage
    /// Fitted axis segments in canvas pixels, one per candidate.
    public var axes: [(from: SIMD2<Double>, to: SIMD2<Double>)]
    /// Tips in canvas pixels, one per candidate.
    public var tips: [SIMD2<Double>]
    public var threshold: Double
}

/// Reference differencing in the canvas (section 5). The v1 detector.
///
/// Stateless: every call reads only its request. The steps are those of VISION.md §5.2, D2 to D10, written in
/// `ChangeEvidence` (D2, D3), `BlobAnalysis` (D4, D5) and `TipEstimator` (D6 to D9). No confidence here: the
/// candidates go through `ConfidenceModel`, like those of any detector.
public struct DifferencingDartDetector: DartDetecting {
    public init() {}

    public var descriptor: DetectorDescriptor {
        DetectorDescriptor(name: "differencing", version: "1", mode: .differential)
    }

    public var needsSourceImage: Bool {
        false
    }

    public func analyse(_ request: DetectionRequest) -> SceneAnalysis {
        run(request, keepDebug: false).analysis
    }

    public func analyseWithDebug(_ request: DetectionRequest) -> (analysis: SceneAnalysis, debug: DetectionDebug) {
        let result = run(request, keepDebug: true)
        return (result.analysis, result.debug)
    }
}

// MARK: - Pipeline (lot V3)

extension DifferencingDartDetector {
    /// τ = max(evidenceThresholdFloor, noiseMultiplier·σ̂) (D3); the floor when σ̂ is not a number.
    static func threshold(noiseSigma: Double, parameters: DetectionParameters) -> Double {
        let scaled = noiseSigma.isFinite ? parameters.noiseMultiplier * max(0, noiseSigma) : 0
        return max(parameters.evidenceThresholdFloor, scaled.isFinite ? scaled : 0)
    }

    /// Union of the known silhouettes dilated by `silhouetteDilation + extraSilhouetteDilation`.
    static func dilatedSilhouettes(_ darts: [KnownDart], request: DetectionRequest) -> CanvasMask {
        let extra = request.extraSilhouetteDilation.isFinite ? max(0, request.extraSilhouetteDilation) : 0
        let radius = max(0, request.parameters.silhouetteDilation) + extra
        var union = CanvasMask()
        for dart in darts {
            union = union.union(radius > 0 ? dart.silhouette.dilated(by: radius) : dart.silhouette)
        }
        return union
    }

    private func run(_ request: DetectionRequest, keepDebug: Bool) -> (analysis: SceneAnalysis, debug: DetectionDebug) {
        let parameters = request.parameters
        let side = BoardCanvas.side
        let tau = DifferencingDartDetector.threshold(noiseSigma: request.noiseSigma, parameters: parameters)
        let empty = DetectionDebug(evidence: GrayImage(width: side, height: side, fill: 0),
                                   mask: GrayImage(width: side, height: side, fill: 0), axes: [], tips: [], threshold: tau)
        guard let reference = request.reference else {
            // A differential detector has nothing to compare with.
            return (SceneAnalysis(kind: .unrecognized), empty)
        }
        let maxDarts = max(1, request.maxNewDarts)
        let silhouettes = DifferencingDartDetector.dilatedSilhouettes(request.knownDarts, request: request)

        // D2, D3.
        let evidence = ChangeEvidence(reference: reference, current: request.current, excluded: silhouettes,
                                      threshold: tau, parameters: parameters)
        let mask = evidence.mask(cleared: silhouettes, parameters: parameters)
        var debug = empty
        if keepDebug {
            debug.evidence = GrayImage(width: side, height: side, pixels: evidence.values.map { UInt8(max(0, min(255, $0.rounded()))) })
            debug.mask = mask
        }

        // D4.
        let pixels = BlobAnalysis.newPixels(of: mask, parameters: parameters)
        let area = pixels.area
        func analysis(_ kind: SceneAnalysis.Kind, darts: [DartCandidate] = [], state: BlobAnalysis.KnownState? = nil) -> SceneAnalysis {
            SceneAnalysis(kind: kind, darts: darts, removedDartIDs: state?.removed ?? [], disturbedDartIDs: state?.disturbed ?? [],
                          changedBoardFraction: evidence.changedBoardFraction, newObjectArea: area, gain: evidence.gain)
        }
        if evidence.changedBoardFraction >= parameters.lightingChangeFraction {
            return (analysis(.lightingChange), debug)
        }
        if area > parameters.maxDartArea * Double(maxDarts) {
            return (analysis(.obstruction), debug)
        }
        var emptyEvidence: ChangeEvidence?
        if let emptyReference = request.emptyReference, !request.knownDarts.isEmpty || area >= parameters.minChangeArea {
            emptyEvidence = ChangeEvidence(reference: emptyReference, current: request.current, excluded: silhouettes,
                                           threshold: tau, parameters: parameters)
        }
        let state = BlobAnalysis.knownState(of: request.knownDarts, evidence: evidence, emptyEvidence: emptyEvidence,
                                            parameters: parameters)
        if area < parameters.minChangeArea {
            return (analysis(state.removed.isEmpty ? .noChange : .removal, state: state), debug)
        }
        if let emptyEvidence, !BlobAnalysis.passesGhostGuard(pixels, emptyEvidence: emptyEvidence, parameters: parameters) {
            return (analysis(.foreignRemoval, state: state), debug)
        }

        // D5 to D10.
        var common: DartFlags = []
        if maxDarts > 1 { common.insert(.multiDartStill) }
        if request.emptyReference == nil { common.insert(.emptyReferenceStale) }
        if !state.removed.isEmpty || !state.disturbed.isEmpty { common.insert(.earlierDartDisturbed) }
        let context = TipEstimator.Context(evidence: evidence, knownSilhouettes: silhouettes,
                                           footPoint: request.calibration.pose.footPoint,
                                           cameraDistance: request.calibration.pose.distance, parameters: parameters)
        var candidates: [DartCandidate] = []
        for dart in BlobAnalysis.darts(in: pixels, maxDarts: maxDarts, parameters: parameters) {
            let (oriented, endFlags) = TipEstimator.orient(dart.line, pixels: dart.pixels, context: context)
            var flags = common.union(endFlags)
            if dart.clutter { flags.insert(.clutter) }
            let narrow = TipEstimator.narrowLine(oriented, pixels: dart.pixels, parameters: parameters)
            if narrow == nil { flags.insert(.fewNarrowPixels) }
            let estimate = TipEstimator.estimate(pixels: dart.pixels, line: narrow ?? oriented, elongation: dart.elongation,
                                                 context: context)
            flags.formUnion(estimate.flags)
            guard estimate.tip.x.isFinite, estimate.tip.y.isFinite else { continue }
            candidates.append(DifferencingDartDetector.candidate(estimate, pixels: dart.pixels, flags: flags,
                                                                calibration: request.calibration))
            if keepDebug {
                debug.axes.append((from: BoardCanvas.pixel(for: BoardPoint(x: estimate.tip.x, y: estimate.tip.y)),
                                   to: BoardCanvas.pixel(for: BoardPoint(x: estimate.tail.x, y: estimate.tail.y))))
                debug.tips.append(BoardCanvas.pixel(for: BoardPoint(x: estimate.tip.x, y: estimate.tip.y)))
            }
        }
        if candidates.isEmpty {
            return (analysis(.unrecognized, state: state), debug)
        }
        return (analysis(.darts, darts: candidates, state: state), debug)
    }

    /// D10: the tip in nominal coordinates (wire height removed, then the radial stretch), the axis from the tip
    /// towards the flight, the undilated footprint (P plus the walked corridor).
    static func candidate(_ estimate: TipEstimator.Estimate, pixels: BlobAnalysis.Pixels, flags: DartFlags,
                          calibration: BoardCalibration) -> DartCandidate {
        var metric = BoardPoint(x: estimate.tip.x, y: estimate.tip.y)
        if calibration.wireHeight != 0, calibration.wireHeight.isFinite {
            metric = calibration.pose.removingParallax(from: metric, height: -calibration.wireHeight)
        }
        let tip = calibration.ringRadii.toNominal(metric)
        let side = BoardCanvas.side
        var spans: [Int32] = []
        spans.reserveCapacity((pixels.count + estimate.corridor.count) * 3)
        for index in pixels.indices + estimate.corridor {
            spans.append(Int32(index / side))
            spans.append(Int32(index % side))
            spans.append(Int32(index % side + 1))
        }
        return DartCandidate(tip: tip, axis: -estimate.towardsTip, silhouette: CanvasMask(unsortedSpans: spans),
                             occlusionSpan: estimate.occlusionSpan, visibleLength: estimate.visibleLength, score: 1,
                             flags: flags)
    }
}
