import Foundation
import simd
import Testing
import DartCore
@testable import DartVision

/// What the differencing detector makes of a settled scene (VISION.md §5.2, D4 and D10): the scene kinds the
/// engine relies on, the known darts, peeling, the debug output and determinism; and the one-dart lighting check
/// (§4.8), which runs the same detector.
@Suite struct DetectionSceneTests {
    private let detector = DifferencingDartDetector()
    private let camera = SupportPoses.a.camera
    private var calibration: BoardCalibration { camera.calibration() }

    private func render(_ darts: [SyntheticDart], seed: UInt64, configure: (inout SyntheticScene) -> Void = { _ in }) -> CanvasImage {
        var scene = SupportScenes.darts(darts, seed: seed)
        configure(&scene)
        return scene.renderCanvas(camera: camera)
    }

    private func request(current: CanvasImage, reference: CanvasImage?, empty: CanvasImage?, known: [KnownDart] = [],
                         maxNewDarts: Int = 1, parameters: DetectionParameters = .default) -> DetectionRequest {
        DetectionRequest(current: current, reference: reference, emptyReference: empty, knownDarts: known, calibration: calibration,
                         noiseSigma: 2, maxNewDarts: maxNewDarts, parameters: parameters)
    }

    /// A steel dart in the single of the 1, more than 9 mm from every wire.
    private static let dart = SyntheticDart(tip: BoardPoint(x: 25, y: 70), leanUpDegrees: 9, leanSideDegrees: 2)

    /// The dart as committed by a first detection: its id, tip and silhouette.
    private func committed(_ dart: SyntheticDart, empty: CanvasImage, id: UUID) throws -> (known: KnownDart, scene: CanvasImage) {
        let withDart = render([dart], seed: 21)
        let first = detector.analyse(request(current: withDart, reference: empty, empty: empty))
        let candidate = try #require(first.darts.first)
        return (KnownDart(id: id, tip: candidate.tip, silhouette: candidate.silhouette), withDart)
    }

    @Test func descriptorAndThreshold() {
        #expect(detector.descriptor == DetectorDescriptor(name: "differencing", version: "1", mode: .differential))
        #expect(!detector.needsSourceImage)
        let parameters = DetectionParameters()
        #expect(DifferencingDartDetector.threshold(noiseSigma: 2, parameters: parameters) == 18)
        #expect(DifferencingDartDetector.threshold(noiseSigma: 5, parameters: parameters) == 30)
        #expect(DifferencingDartDetector.threshold(noiseSigma: .nan, parameters: parameters) == 18)
        #expect(DetectionParameters.default == DetectionParameters())
    }

    @Test func noChange_andNoReference() {
        let empty = render([], seed: 1)
        let again = render([], seed: 2)
        let analysis = detector.analyse(request(current: again, reference: empty, empty: empty))
        #expect(analysis.kind == .noChange && analysis.darts.isEmpty)
        #expect(abs(analysis.gain - 1) < 0.01 && analysis.changedBoardFraction < 0.01 && analysis.newObjectArea < 15)
        // A differential detector without a reference has nothing to compare with.
        #expect(detector.analyse(request(current: again, reference: nil, empty: nil)).kind == .unrecognized)
        // A canvas of the wrong size counts as entirely invalid: nothing is found, nothing traps.
        let tiny = CanvasImage(rgb: RGBImage(width: 4, height: 4, fill: SIMD3(1, 2, 3)), valid: GrayImage(width: 4, height: 4, fill: 255))
        #expect(detector.analyse(request(current: tiny, reference: empty, empty: empty)).kind == .noChange)
    }

    /// One new dart: its tip within a millimetre, the axis from the tip towards the flight (away from the camera
    /// foot point), a footprint around it and a dart-like length.
    @Test func oneDart() throws {
        let empty = render([], seed: 1)
        let analysis = detector.analyse(request(current: render([Self.dart], seed: 2), reference: empty, empty: empty))
        #expect(analysis.kind == .darts)
        let candidate = try #require(analysis.darts.first)
        #expect(analysis.darts.count == 1)
        #expect(hypot(candidate.tip.x - 25, candidate.tip.y - 70) < 1)
        let foot = calibration.pose.footPoint
        #expect(simd_dot(candidate.axis, SIMD2(25 - foot.x, 70 - foot.y)) > 0)
        #expect(abs(simd_length(candidate.axis) - 1) < 1e-9)
        #expect(candidate.silhouette.contains(BoardPoint(x: 25, y: 72)))
        #expect(candidate.visibleLength > 60 && candidate.visibleLength < 200)
        #expect(candidate.score == 1 && candidate.flags.isEmpty && candidate.occlusionSpan == 0,
                "flags \(candidate.flags.rawValue) span \(candidate.occlusionSpan)")
        #expect(analysis.newObjectArea > 300 && analysis.newObjectArea < 4000)
        #expect(analysis.removedDartIDs.isEmpty && analysis.disturbedDartIDs.isEmpty)
        // Without an empty reference the dart is flagged.
        let stale = detector.analyse(request(current: render([Self.dart], seed: 2), reference: empty, empty: nil))
        #expect(stale.darts.first?.flags.contains(.emptyReferenceStale) == true)
    }

    /// The same input twice gives the same output, bit for bit; the debug output matches the analysis.
    @Test func deterministic_andDebugOutput() throws {
        let empty = render([], seed: 1)
        let input = request(current: render([Self.dart], seed: 2), reference: empty, empty: empty)
        let first = detector.analyse(input)
        let second = detector.analyse(input)
        let (third, debug) = detector.analyseWithDebug(input)
        let a = try #require(first.darts.first), b = try #require(second.darts.first), c = try #require(third.darts.first)
        #expect(a.tip == b.tip && a.tip == c.tip && a.axis == b.axis && a.silhouette == b.silhouette && a.flags == c.flags)
        #expect(first.gain == second.gain && first.changedBoardFraction == second.changedBoardFraction)
        #expect(debug.threshold == 18)
        #expect(debug.evidence.width == BoardCanvas.side && debug.mask.width == BoardCanvas.side)
        #expect(debug.tips.count == 1 && debug.axes.count == 1)
        let tipPixel = BoardCanvas.pixel(for: a.tip)
        #expect(simd_length(debug.tips[0] - tipPixel) < 1e-9)
        #expect(debug.mask.pixels.contains(255))
        #expect(debug.evidence.pixels.max() ?? 0 > 18)
    }

    /// A committed dart that leaves the board: `removal`, with its id, against the empty reference and without it.
    @Test func removal() throws {
        let empty = render([], seed: 1)
        let id = UUID(uuidString: "00000000-0000-0000-0000-0000000000D1") ?? UUID()
        let (known, withDart) = try committed(Self.dart, empty: empty, id: id)
        let gone = render([], seed: 3)
        let analysis = detector.analyse(request(current: gone, reference: withDart, empty: empty, known: [known]))
        #expect(analysis.kind == .removal && analysis.removedDartIDs == [id] && analysis.darts.isEmpty)
        let blind = detector.analyse(request(current: gone, reference: withDart, empty: nil, known: [known]))
        #expect(blind.kind == .removal && blind.removedDartIDs == [id])
        // Still there: nothing changed.
        let still = detector.analyse(request(current: render([Self.dart], seed: 4), reference: withDart, empty: empty, known: [known]))
        #expect(still.kind == .noChange && still.removedDartIDs.isEmpty && still.disturbedDartIDs.isEmpty)
    }

    /// Something baked into the rolling reference leaves (here a dart that was never committed): the ghost guard
    /// finds the scene equal to the empty board, so no dart is reported.
    @Test func foreignRemoval() {
        let empty = render([], seed: 1)
        let analysis = detector.analyse(request(current: render([], seed: 3), reference: render([Self.dart], seed: 2), empty: empty))
        #expect(analysis.kind == .foreignRemoval && analysis.darts.isEmpty)
    }

    /// A second dart next to a committed one: the new dart only, with the earlier one masked out.
    @Test func secondDart() throws {
        let empty = render([], seed: 1)
        let id = UUID(uuidString: "00000000-0000-0000-0000-0000000000D2") ?? UUID()
        let (known, withDart) = try committed(Self.dart, empty: empty, id: id)
        let other = SyntheticDart(tip: BoardPoint(x: -70, y: -20), leanUpDegrees: 5, style: .brass)
        let analysis = detector.analyse(request(current: render([Self.dart, other], seed: 5), reference: withDart, empty: empty,
                                                known: [known]))
        #expect(analysis.kind == .darts && analysis.darts.count == 1)
        let candidate = try #require(analysis.darts.first)
        #expect(hypot(candidate.tip.x + 70, candidate.tip.y + 20) < 1)
        #expect(!candidate.silhouette.intersects(known.silhouette))
        #expect(analysis.removedDartIDs.isEmpty && analysis.disturbedDartIDs.isEmpty)
    }

    /// A hand covering a large part of the board is an obstruction; a strong change of light is a lighting change.
    @Test func obstructionAndLight() {
        let empty = render([], seed: 1)
        let hand = render([], seed: 2) { $0.hand = (BoardPoint(x: 0, y: -60), 70) }
        #expect(detector.analyse(request(current: hand, reference: empty, empty: empty)).kind == .obstruction)
        // A gain of 1.3 clips the cream beds: the change is not a brightness change any more, on most of the disc.
        let bright = render([], seed: 2) { $0.gain = 1.3 }
        let analysis = detector.analyse(request(current: bright, reference: empty, empty: empty))
        #expect(analysis.kind == .lightingChange)
        #expect(analysis.changedBoardFraction >= 0.35)
        // A gain of 0.9 is absorbed by the gain of D2.
        let dim = render([], seed: 2) { $0.gain = 0.9 }
        #expect(detector.analyse(request(current: dim, reference: empty, empty: empty)).kind == .noChange)
    }

    /// Stills: three separate darts in one still are peeled one by one, each flagged `multiDartStill`.
    @Test func peeling() {
        let empty = render([], seed: 1)
        let darts = [SyntheticDart(tip: BoardPoint(x: 0, y: 100)),
                     SyntheticDart(tip: BoardPoint(x: -90, y: -40), leanUpDegrees: 12, style: .brass),
                     SyntheticDart(tip: BoardPoint(x: 100, y: -60), leanUpDegrees: 4)]
        let analysis = detector.analyse(request(current: render(darts, seed: 2), reference: empty, empty: empty, maxNewDarts: 3))
        #expect(analysis.kind == .darts && analysis.darts.count == 3)
        for dart in darts {
            let nearest = analysis.darts.map { hypot($0.tip.x - dart.tip.x, $0.tip.y - dart.tip.y) }.min() ?? .infinity
            #expect(nearest < 1, "dart at \(dart.tip): \(nearest) mm")
        }
        #expect(analysis.darts.allSatisfy { $0.flags.contains(.multiDartStill) })
        // Asked for one dart, three darts are more than one dart can cover (an obstruction, D4), and two are clutter.
        let single = detector.analyse(request(current: render(darts, seed: 2), reference: empty, empty: empty))
        #expect(single.kind == .obstruction)
        let pair = detector.analyse(request(current: render(Array(darts.prefix(2)), seed: 2), reference: empty, empty: empty))
        #expect(pair.kind == .darts && pair.darts.count == 1)
        #expect(pair.darts.first?.flags.contains(.clutter) == true, "\(pair.kind) \(pair.darts.map(\.flags.rawValue))")
    }

    /// D10: the tip leaves in nominal coordinates, wire height removed then radii stretched.
    @Test func nominalOutput() {
        let exact = calibration
        let radii = RingRadii(innerBull: 6.35, outerBull: 15.9, trebleInner: 98, trebleOuter: 106.5, doubleInner: 162, doubleOuter: 170)
        let custom = BoardCalibration(id: exact.id, createdAt: exact.createdAt, imageSize: exact.imageSize, rotationDegrees: 0,
                                      userHandles: exact.userHandles, handles: exact.handles, boardToImage: exact.boardToImage,
                                      imageToBoard: exact.imageToBoard, ringRadii: radii, wireHeight: 0.7, intrinsics: exact.intrinsics,
                                      pose: exact.pose, quality: exact.quality)
        let estimate = TipEstimator.Estimate(tip: SIMD2(10, 98.5), towardsTip: SIMD2(0, -1), tail: SIMD2(10, 180), visibleLength: 80,
                                             occlusionSpan: 0, flags: [], corridor: [])
        let candidate = DifferencingDartDetector.candidate(estimate, pixels: BlobAnalysis.Pixels(indices: [700 * 1280 + 660]),
                                                           flags: .clutter, calibration: custom)
        let expected = radii.toNominal(custom.pose.removingParallax(from: BoardPoint(x: 10, y: 98.5), height: -0.7))
        #expect(hypot(candidate.tip.x - expected.x, candidate.tip.y - expected.y) < 1e-12)
        #expect(candidate.axis == SIMD2(0, 1) && candidate.flags == .clutter && candidate.visibleLength == 80)
        #expect(!candidate.silhouette.isEmpty)
    }

    // MARK: Lighting check (§4.8)

    @Test func lightingCheck_verifiedWithoutShadow() {
        let empty = render([], seed: 1)
        let result = LightingCheck.run(reference: empty, current: render([Self.dart], seed: 2), confirmedTip: Self.dart.tip,
                                       calibration: calibration, noiseSigma: 2, parameters: DetectionParameters())
        #expect(result.verdict == .verified)
        #expect(result.tipError < 2)
        #expect(result.shadowDepth == nil && result.recommendedShadowLowerBound == 0.5)
    }

    /// The shadow depth is measured off the dart, and the bound follows `clamp(q05 − 0.08, 0.2, 0.5)`.
    @Test func lightingCheck_shadowBound() throws {
        for (strength, low, high) in [(0.35, 0.22, 0.32), (0.65, 0.5, 0.5)] {
            let light = SupportScenes.lampOpposite(to: camera)
            let empty = render([], seed: 1) { $0.light = light; $0.shadowStrength = strength }
            let current = render([Self.dart], seed: 2) { $0.light = light; $0.shadowStrength = strength }
            let result = LightingCheck.run(reference: empty, current: current, confirmedTip: Self.dart.tip, calibration: calibration,
                                           noiseSigma: 2, parameters: DetectionParameters())
            let depth = try #require(result.shadowDepth, "shadow \(strength)")
            #expect(abs(depth - strength) < 0.08, "shadow \(strength): depth \(depth)")
            #expect(result.recommendedShadowLowerBound >= low && result.recommendedShadowLowerBound <= high,
                    "shadow \(strength): bound \(result.recommendedShadowLowerBound)")
            #expect(result.verdict == .verified, "shadow \(strength): \(result.verdict), error \(result.tipError)")
        }
    }

    /// A tap far from the dart is not verified; an all-black dart on a black bed is not visible.
    @Test func lightingCheck_failures() {
        let empty = render([], seed: 1)
        let wrongTap = LightingCheck.run(reference: empty, current: render([Self.dart], seed: 2), confirmedTip: BoardPoint(x: -50, y: 0),
                                         calibration: calibration, noiseSigma: 2, parameters: DetectionParameters())
        #expect(wrongTap.verdict != .verified && wrongTap.tipError > 50)
        let black = SyntheticDart(tip: BoardPoint(x: 0, y: 60), leanUpDegrees: 9, style: .allBlack)
        let hidden = LightingCheck.run(reference: empty, current: render([black], seed: 2), confirmedTip: black.tip,
                                       calibration: calibration, noiseSigma: 2, parameters: DetectionParameters())
        #expect(hidden.verdict == .pointNotVisible, "\(hidden.verdict), error \(hidden.tipError)")
        // Nothing planted at all.
        let nothing = LightingCheck.run(reference: empty, current: render([], seed: 2), confirmedTip: Self.dart.tip,
                                        calibration: calibration, noiseSigma: 2, parameters: DetectionParameters())
        #expect(nothing.verdict == .pointNotVisible && !nothing.tipError.isFinite)
    }
}
