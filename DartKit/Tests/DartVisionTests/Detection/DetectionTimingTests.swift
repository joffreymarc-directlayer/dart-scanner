import Foundation
import simd
import Testing
import DartCore
@testable import DartVision

/// Cost of one settled event on a 4K source (VISION.md §5.4, §10.2 "Coût"): the four quiet frames rectified and
/// averaged, D2 to D10, then the confidence. The times are printed; only the wide bound of §10.2 (1 s) is required,
/// and only in release builds.
@Suite(.tags(.heavy)) struct DetectionTimingTests {
    @Test func timing_oneEventOn4K() throws {
        let camera = SupportPoses.a.camera
        let calibration = camera.calibration()
        let dart = SyntheticDart(tip: BoardPoint(x: 25, y: 70), leanUpDegrees: 9)
        let emptyImage = SupportScenes.empty(seed: 1).render(camera: camera)
        let frames = (0..<4).map { SupportScenes.darts([dart], seed: UInt64(10 + $0)).render(camera: camera) }
        let rectifier = BoardRectifier(calibration: calibration)
        let reference = rectifier.rectify(emptyImage)
        let detector = DifferencingDartDetector()
        let model = ConfidenceModel()
        let clock = ContinuousClock()
        var rectifyTimes: [Duration] = [], detectTimes: [Duration] = [], confidenceTimes: [Duration] = [], totals: [Duration] = []
        for _ in 0..<5 {
            let start = clock.now
            var accumulator = FrameAccumulator()
            for image in frames {
                accumulator.add(rectifier.rectify(Frame(image: image, timestamp: 0)))
            }
            let current = try #require(accumulator.mean())
            let rectified = clock.now
            let analysis = detector.analyse(DetectionRequest(current: current, reference: reference, emptyReference: reference,
                                                             knownDarts: [], calibration: calibration, noiseSigma: 2))
            let detected = clock.now
            let candidate = try #require(analysis.darts.first)
            let seen = model.observe(candidate, id: UUID(uuidString: "00000000-0000-0000-0000-0000000000E1") ?? UUID(), visit: 1,
                                     indexInVisit: 0, timestamp: 0, source: .liveCamera, calibration: calibration,
                                     context: ConfidenceContext())
            let observed = clock.now
            #expect(seen.best == .single(1))
            rectifyTimes.append(rectified - start)
            detectTimes.append(detected - rectified)
            confidenceTimes.append(observed - detected)
            totals.append(observed - start)
        }
        func median(_ values: [Duration]) -> Duration { values.sorted()[values.count / 2] }
        print("DETECTION TIMING (4K portrait, pose A, median of 5): rectify and average 4 frames \(median(rectifyTimes)), "
              + "D2 to D10 \(median(detectTimes)), confidence \(median(confidenceTimes)), total \(median(totals))")
        #if !DEBUG
        #expect(median(totals) < .seconds(1))
        #endif
    }
}
