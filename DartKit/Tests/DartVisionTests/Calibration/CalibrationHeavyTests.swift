import Foundation
import simd
import Testing
import DartCore
@testable import DartVision

extension CalibrationTests {
    /// C2 and C3 (VISION.md §10.2): many seeds of noisy handles on rendered stills of the reference poses.
    ///
    /// Heavy: `swift test -c release --filter CalibrationHeavyTests` runs the 200 seeds of the document. A debug run
    /// keeps the poses at full resolution and runs 40 seeds instead: at 1280×720 the reference poses fall under the
    /// 0.8 px/mm of the C1 gate, so the smaller images of VISION.md §10.2 cannot be calibrated at all.
    @Suite(.tags(.heavy)) struct CalibrationHeavyTests {
        #if DEBUG
        private static let seeds = 40
        #else
        private static let seeds = 200
        #endif

        private struct Outcome: Sendable {
            var seed: Int
            var before: (rms: Double, p95: Double, max: Double)
            var after: (rms: Double, p95: Double, max: Double)
            var applied: Bool
            var handlesKept: Bool
        }

        /// One seed: pose A to D in turn, default nuisances, gain within ±10 %, handles with σ = 2 px of noise.
        private static func run(seed: Int) -> Outcome? {
            let camera = SupportPoses.allCases[seed % 4].camera
            var random = SupportRandom(seed: UInt64(5000 + seed))
            let still = CalibrationFixtures.still(camera, seed: UInt64(seed + 1), gain: random.uniform(0.9...1.1))
            let handles = CalibrationFixtures.noisy(camera.exactHandles(), sigma: 2, random: &random)
            guard let before = CalibrationFixtures.preview(handles: handles, camera: camera),
                  let after = CalibrationFixtures.calibrate(handles: handles, still: still, camera: camera) else { return nil }
            return Outcome(seed: seed,
                           before: CalibrationFixtures.errors(of: before, truth: camera.boardToImage),
                           after: CalibrationFixtures.errors(of: after, truth: camera.boardToImage),
                           applied: after.quality.refinementApplied,
                           handlesKept: after.handles == handles && after.boardToImage == before.boardToImage)
        }

        /// Computed once for both tests, giving the other tests a turn between two seeds: a test that holds a thread of
        /// the cooperative pool for seconds starves the tests that wait for real-time frames (`ImagingScriptTests`).
        private static let outcomes = Task { () -> [Outcome] in
            var results: [Outcome] = []
            for seed in 0..<seeds {
                await Task.yield()
                if let outcome = run(seed: seed) { results.append(outcome) }
            }
            return results
        }

        @Test func c2_noisyHandlesAreRefined() async {
            let results = await Self.outcomes.value
            let seeds = Self.seeds
            #expect(results.count == seeds)
            let good = results.filter { $0.after.rms <= 0.35 && $0.after.p95 <= 0.8 }
            #expect(Double(good.count) >= 0.95 * Double(seeds), "\(results.filter { !($0.after.rms <= 0.35 && $0.after.p95 <= 0.8) }.map(\.seed))")
            // Every seed whose refinement was accepted is within the tolerance.
            #expect(results.filter(\.applied).allSatisfy { $0.after.rms <= 0.35 && $0.after.p95 <= 0.8 })
        }

        @Test func c3_anAcceptedRefinementNeverIncreasesTheError() async {
            for outcome in await Self.outcomes.value {
                if outcome.applied {
                    #expect(outcome.after.rms <= outcome.before.rms, "seed \(outcome.seed)")
                    #expect(outcome.after.p95 <= outcome.before.p95, "seed \(outcome.seed)")
                } else {
                    #expect(outcome.handlesKept, "seed \(outcome.seed)")
                }
            }
        }

        /// Cost on a 4K still (pose A), reported: `preview` (every handle drag), `calibrate`, `assess` of a drifted still
        /// (which runs `recover` too), `locate`. Only a wide bound is required, in release (VISION.md §10.2, "Coût").
        @Test func timing_onA4KStill() async throws {
            let camera = SupportPoses.a.camera
            let still = CalibrationFixtures.still(camera, seed: 1)
            var drifted = SupportScenes.empty(seed: 2)
            drifted.shift = SIMD2(3, -2)
            let moved = drifted.render(camera: camera)
            var random = SupportRandom(seed: 3)
            let handles = CalibrationFixtures.noisy(camera.exactHandles(), sigma: 2, random: &random)
            let calibrator = BoardCalibrator()
            let locator = ColourBoardLocator()
            let clock = ContinuousClock()
            var calibration: BoardCalibration?
            await Task.yield()
            let previewTime = clock.measure {
                for _ in 0..<100 {
                    _ = calibrator.preview(handles: handles, imageSize: camera.imageSize, rotationDegrees: 0,
                                           intrinsics: camera.intrinsics)
                }
            } / 100
            let calibrateTime = clock.measure {
                calibration = CalibrationFixtures.calibrate(calibrator, handles: handles, still: still, camera: camera)
            }
            let result = try #require(calibration)
            var status: CalibrationHealth.Status?
            let assessTime = clock.measure { status = calibrator.assess(result, on: moved, dartsOnBoard: false).status }
            var location: BoardLocation?
            await Task.yield()
            let locateTime = clock.measure { location = locator.locate(in: still, upDirection: SIMD2(0, -1)) }
            print("Calibration timing, 4K still: preview \(previewTime), calibrate \(calibrateTime), "
                  + "assess with recover \(assessTime), locate \(locateTime)")
            #expect(status == .drifted && location != nil)
            #if !DEBUG
            let bound = Duration.seconds(1)
            #expect(previewTime < bound && calibrateTime < bound && assessTime < bound && locateTime < bound)
            #endif
        }
    }
}
