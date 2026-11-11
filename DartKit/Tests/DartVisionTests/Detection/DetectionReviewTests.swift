import Foundation
import simd
import Testing
import DartCore
@testable import DartVision

/// Independent checks of lot V3 by its review (RV2), on hand-made canvases: the dark end of a hard shadow taken for
/// the point (D9, `implausiblyLong`), hostile requests, a tip that is not a number. Fast: no rendering.
@Suite struct DetectionReviewTests {
    // MARK: Hand-made canvases

    static let cream = SIMD3<UInt8>(225, 205, 165)

    /// A canvas of one colour, valid everywhere.
    static func plain(_ colour: SIMD3<UInt8>) -> CanvasImage {
        let side = BoardCanvas.side
        return CanvasImage(rgb: RGBImage(width: side, height: side, fill: colour), valid: GrayImage(width: side, height: side, fill: 255))
    }

    /// Paints the band `x0 ≤ along < x1` (board mm), `|across| ≤ halfWidth`, with `colour`; `along` and `across` are
    /// measured along `direction` and a quarter turn from it (+x and +y by default).
    static func paint(_ canvas: inout CanvasImage, x0: Double, x1: Double, halfWidth: Double, colour: SIMD3<UInt8>,
                      direction: SIMD2<Double> = SIMD2(1, 0)) {
        let side = BoardCanvas.side
        for j in 0..<side {
            for i in 0..<side {
                let q = BoardCanvas.boardPoint(x: Double(i), y: Double(j))
                let along = q.x * direction.x + q.y * direction.y, across = -q.x * direction.y + q.y * direction.x
                guard along >= x0, along < x1, abs(across) <= halfWidth else { continue }
                let o = 3 * (j * side + i)
                canvas.rgb.pixels[o] = colour.x
                canvas.rgb.pixels[o + 1] = colour.y
                canvas.rgb.pixels[o + 2] = colour.z
            }
        }
    }

    /// A dart lying along +x on a cream bed, its entry point at x = 60 mm and its flight towards +x: point 60–80,
    /// barrel 80–130, shaft 130–170, flight 170–200 (board mm), in the given colours.
    static func dart(point: SIMD3<UInt8>, barrel: SIMD3<UInt8>, shaft: SIMD3<UInt8>, flight: SIMD3<UInt8>,
                     shadowFrom shadowStart: Double? = nil, direction: SIMD2<Double> = SIMD2(1, 0)) -> CanvasImage {
        var canvas = plain(cream)
        if let shadowStart {
            // A hard shadow (20 % of the light) of the point, from `shadowStart` up to the entry point.
            let dark = SIMD3<UInt8>(UInt8(0.2 * 225), UInt8(0.2 * 205), UInt8(0.2 * 165))
            paint(&canvas, x0: shadowStart, x1: 60, halfWidth: 1.2, colour: dark, direction: direction)
        }
        paint(&canvas, x0: 60, x1: 80, halfWidth: 1.2, colour: point, direction: direction)
        paint(&canvas, x0: 80, x1: 130, halfWidth: 3.4, colour: barrel, direction: direction)
        paint(&canvas, x0: 130, x1: 170, halfWidth: 2.6, colour: shaft, direction: direction)
        paint(&canvas, x0: 170, x1: 200, halfWidth: 17, colour: flight, direction: direction)
        return canvas
    }

    static let steel = SIMD3<UInt8>(200, 200, 205), tungsten = SIMD3<UInt8>(95, 95, 100)
    static let black = SIMD3<UInt8>(25, 25, 25), blue = SIMD3<UInt8>(40, 80, 200), yellow = SIMD3<UInt8>(230, 200, 40)

    /// The guard of the review on `current` against a cream reference, the walk ending at `end` (board x, mm).
    static func foreignDarkEnd(_ current: CanvasImage, end: Double) -> Bool {
        let parameters = DetectionParameters()
        let evidence = ChangeEvidence(reference: plain(cream), current: current, excluded: CanvasMask(), threshold: 18,
                                      parameters: parameters)
        // The line runs along −x towards the tip; position t is the board point (100 − t, 0).
        let line = BlobAnalysis.Line(mean: SIMD2(100, 0), direction: SIMD2(-1, 0), largeVariance: 1, smallVariance: 0)
        return TipEstimator.endIsForeignDarkening(crossing: 100 - end, start: 100 - 200, line: line, evidence: evidence,
                                                  parameters: parameters)
    }

    /// D9 (review RV2): a hard shadow of the point beyond the entry point, darker than the shadow model allows, on a
    /// bright bed, ends the walk; the coloured point and barrel right behind it show that the dark end is not the
    /// point. Without the shadow, and for an all-black dart (dark down to its flight), nothing is flagged.
    @Test func foreignDarkEnd_shadowBeyondTheTip() {
        let steelDart = Self.dart(point: Self.steel, barrel: Self.tungsten, shaft: Self.black, flight: Self.blue)
        #expect(!Self.foreignDarkEnd(steelDart, end: 60))
        for start in [57.0, 50.0, 30.0] {
            let shadowed = Self.dart(point: Self.steel, barrel: Self.tungsten, shaft: Self.black, flight: Self.blue, shadowFrom: start)
            #expect(Self.foreignDarkEnd(shadowed, end: start), "shadow from \(start)")
        }
        let blackDart = Self.dart(point: Self.black, barrel: Self.black, shaft: Self.black, flight: Self.yellow)
        #expect(!Self.foreignDarkEnd(blackDart, end: 60))
        // A detached piece of shadow: dark, then the bed, then the coloured dart.
        var detached = steelDart
        Self.paint(&detached, x0: 30, x1: 40, halfWidth: 1.2,
                   colour: SIMD3(UInt8(0.2 * 225), UInt8(0.2 * 205), UInt8(0.2 * 165)))
        #expect(Self.foreignDarkEnd(detached, end: 30))
    }

    /// The same through the detector and the confidence model, in pose A: a dart pointing away from the camera foot
    /// point (its tip towards it), entry point at (0, 60). Clean, it is found at the high tier, 1.1 mm behind the end
    /// of its flat painted point (the cap correction of D8 expects the round end of a real one);
    /// with the hard shadow of its point running 12 mm towards the camera, the tip lands at the end of the shadow
    /// and must not be high.
    @Test func detector_shadowBeyondTheTipIsNotHigh() throws {
        let calibration = SupportPoses.a.camera.calibration()
        let empty = Self.plain(Self.cream)
        func observe(_ current: CanvasImage) throws -> (DartCandidate, DartObservation) {
            let analysis = DifferencingDartDetector().analyse(DetectionRequest(current: current, reference: empty, emptyReference: empty,
                                                                               knownDarts: [], calibration: calibration, noiseSigma: 2))
            let candidate = try #require(analysis.darts.first, "\(analysis.kind)")
            let observation = ConfidenceModel().observe(candidate, id: UUID(uuidString: "00000000-0000-0000-0000-0000000000A3") ?? UUID(),
                                                        visit: 0, indexInVisit: 0, timestamp: 0, source: .liveCamera,
                                                        calibration: calibration, context: ConfidenceContext())
            return (candidate, observation)
        }
        let up = SIMD2<Double>(0, 1)
        let (clean, cleanObservation) = try observe(Self.dart(point: Self.steel, barrel: Self.tungsten, shaft: Self.black, flight: Self.blue,
                                                              direction: up))
        #expect(hypot(clean.tip.x, clean.tip.y - 61.1) < 0.3, "\(clean.tip)")
        #expect(!clean.flags.contains(.implausiblyLong) && cleanObservation.tier == .high, "\(clean.flags.rawValue)")
        let (shadowed, shadowedObservation) = try observe(Self.dart(point: Self.steel, barrel: Self.tungsten, shaft: Self.black,
                                                                    flight: Self.blue, shadowFrom: 48, direction: up))
        #expect(shadowed.tip.y < 55, "the walk follows the shadow: \(shadowed.tip)")
        #expect(shadowed.flags.contains(.implausiblyLong) && shadowedObservation.tier == .low, "\(shadowed.flags.rawValue)")
    }

    // MARK: Hostile requests (none may trap)

    @Test func hostileRequests_neverTrap() {
        let camera = SupportPoses.a.camera
        let calibration = camera.calibration()
        let detector = DifferencingDartDetector()
        let empty = Self.plain(Self.cream)
        let withDart = Self.dart(point: Self.steel, barrel: Self.tungsten, shaft: Self.black, flight: Self.blue)
        let tiny = CanvasImage(rgb: RGBImage(width: 2, height: 2, fill: SIMD3(1, 2, 3)), valid: GrayImage(width: 2, height: 2, fill: 255))
        let broken = CanvasImage(rgb: RGBImage(width: BoardCanvas.side, height: BoardCanvas.side, pixels: []),
                                 valid: GrayImage(width: BoardCanvas.side, height: BoardCanvas.side, pixels: []))
        let known = KnownDart(id: UUID(uuidString: "00000000-0000-0000-0000-0000000000A1") ?? UUID(), tip: BoardPoint(x: 0, y: 0),
                              silhouette: CanvasMask(GrayImage(width: BoardCanvas.side, height: BoardCanvas.side, fill: 255)))
        let small = CanvasMask(unsortedSpans: [640, 600, 620])
        let requests: [DetectionRequest] = [
            DetectionRequest(current: withDart, reference: empty, emptyReference: empty, knownDarts: [], calibration: calibration,
                             noiseSigma: .nan, maxNewDarts: Int.min),
            DetectionRequest(current: withDart, reference: empty, emptyReference: nil, knownDarts: [], calibration: calibration,
                             noiseSigma: .infinity, maxNewDarts: Int.max),
            DetectionRequest(current: withDart, reference: empty, emptyReference: empty,
                             knownDarts: [KnownDart(id: known.id, tip: known.tip, silhouette: small)], calibration: calibration,
                             noiseSigma: -4, maxNewDarts: 0, extraSilhouetteDilation: 1e12),
            DetectionRequest(current: withDart, reference: empty, emptyReference: empty, knownDarts: [known], calibration: calibration,
                             noiseSigma: 2, extraSilhouetteDilation: .nan),
            DetectionRequest(current: tiny, reference: empty, emptyReference: tiny, knownDarts: [], calibration: calibration, noiseSigma: 2),
            DetectionRequest(current: withDart, reference: tiny, emptyReference: broken, knownDarts: [], calibration: calibration,
                             noiseSigma: 2),
            DetectionRequest(current: broken, reference: broken, emptyReference: nil, knownDarts: [known], calibration: calibration,
                             noiseSigma: 2, maxNewDarts: 3),
            DetectionRequest(current: withDart, reference: nil, emptyReference: nil, knownDarts: [], calibration: calibration,
                             noiseSigma: 2),
        ]
        for request in requests {
            let analysis = detector.analyse(request)
            #expect(analysis.darts.count <= 3)
            #expect(analysis.darts.allSatisfy { $0.tip.x.isFinite && $0.tip.y.isFinite })
        }
        // The dart itself is found through all this.
        #expect(detector.analyse(requests[0]).darts.count == 1)
    }

    /// A detector may hand over a tip that is not a number (a model, a fake): the posterior is then all MISS, which
    /// must not reach the game as a certain miss. Other absurd fields only lower the confidence.
    @Test func confidence_ofATipThatIsNotANumber() {
        let calibration = SupportPoses.a.camera.calibration()
        let model = ConfidenceModel()
        let id = UUID(uuidString: "00000000-0000-0000-0000-0000000000A2") ?? UUID()
        for tip in [BoardPoint(x: .nan, y: 0), BoardPoint(x: 0, y: .infinity), BoardPoint(x: -.infinity, y: .nan)] {
            let candidate = DartCandidate(tip: tip, axis: SIMD2(0, 1), silhouette: CanvasMask())
            let observation = model.observe(candidate, id: id, visit: 0, indexInVisit: 0, timestamp: 0, source: .liveCamera,
                                            calibration: calibration, context: ConfidenceContext())
            #expect(observation.tier == .low && observation.confidence == 0, "\(tip)")
            #expect(observation.tier(collapsingBy: { _ in 0 }) == .low)
        }
        for (axis, along, across, span, score) in [(SIMD2<Double>(.nan, 0), Double.nan, -1.0, Double.nan, Double.nan),
                                                   (SIMD2(0, 0), .infinity, .infinity, .infinity, .infinity),
                                                   (SIMD2(1e300, 1e300), 1e300, 0, -5, 1)] {
            let candidate = DartCandidate(tip: BoardPoint(x: 10, y: 60), axis: axis, silhouette: CanvasMask(), sigmaAlong: along,
                                          sigmaAcross: across, occlusionSpan: span, score: score)
            let observation = model.observe(candidate, id: id, visit: 0, indexInVisit: 0, timestamp: 0, source: .liveCamera,
                                            calibration: calibration, context: ConfidenceContext(warmUpRemaining: Int.max, cap: .nan))
            #expect(observation.confidence.isFinite && observation.confidence >= 0 && observation.confidence <= 1)
            #expect(!observation.candidates.isEmpty && abs(observation.candidates.map(\.probability).reduce(0, +) - 1) < 1e-9)
            #expect(observation.tier != .high)
        }
    }
}
