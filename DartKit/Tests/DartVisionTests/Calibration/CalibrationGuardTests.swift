import Foundation
import simd
import Testing
import DartCore
@testable import DartVision

extension CalibrationTests {
    /// The pieces of C3 and of the guards on their own (VISION.md §4.6, §4.9): robust weights of the refinement, every
    /// clause of the acceptance guard and of the health check, read through the parameters that set them.
    @Suite struct CalibrationGuardTests {
        /// Exact observations of every sample through `truth`, with `outliers` of them moved by `offset` mm along their
        /// normal (the first ones of each kind, so that the error is one-sided and does not cancel).
        private func measurement(truth: Homography, outliers: Set<Int>, offset: Double) -> EdgeSampler.Measurement {
            var observations: [EdgeSampler.Observation] = []
            for (index, sample) in EdgeSampler.samples.enumerated() {
                let frame = sample.frame(radii: .nominal)
                let shift = outliers.contains(index) ? offset : 0
                observations.append(EdgeSampler.Observation(sample: index, point: truth.apply(frame.position + shift * frame.normal),
                                                            offset: shift))
            }
            return EdgeSampler.Measurement(observations: observations)
        }

        /// Error on the board of the homography of `handles` against `truth`, mm.
        private func error(_ handles: [SIMD2<Double>], truth: Homography) -> Double {
            guard let inverse = CalibrationGeometry.homography(of: handles)?.inverse else { return .infinity }
            return CalibrationFixtures.boardPoints(count: 100).map { point -> Double in
                simd_length(inverse.apply(truth.apply(SIMD2(point.x, point.y))) - SIMD2(point.x, point.y))
            }.max() ?? .infinity
        }

        /// Outliers on one side of the board: all wire samples of wires 0 to 4 and the ring samples near the 20.
        private var oneSided: Set<Int> {
            Set(EdgeSampler.samples.indices.filter { index in
                switch EdgeSampler.samples[index].kind {
                case .wire(let wire): return wire < 5
                case .ring: return abs(EdgeSampler.samples[index].angle) < 0.5
                }
            })
        }

        @Test func refine_recoversTheTruthFromExactObservations() async {
            let camera = SupportPoses.a.camera
            let truth = camera.boardToImage
            let exact = camera.exactHandles().points.map { SIMD2($0.x, $0.y) }
            var random = SupportRandom(seed: 1)
            let start = exact.map { $0 + 2 * SIMD2(random.gaussian(), random.gaussian()) }
            let refined = HandleRefiner.refine(start: start, tether: start, measurement: measurement(truth: truth, outliers: [], offset: 0),
                                               radii: .nominal, iterations: 6, parameters: .init())
            #expect(error(start, truth: truth) > 0.5)
            #expect(error(refined, truth: truth) < 0.01)
            // The weak spring to the player's handles barely pulls.
            #expect(zip(refined, exact).allSatisfy { simd_length($0 - $1) < 0.05 })
        }

        @Test func refine_ignoresObservationsBeyondTheCutoff() async {
            let camera = SupportPoses.c.camera
            let truth = camera.boardToImage
            let exact = camera.exactHandles().points.map { SIMD2($0.x, $0.y) }
            let gross = measurement(truth: truth, outliers: oneSided, offset: 3.6)
            #expect(Double(oneSided.count) > 0.15 * Double(EdgeSampler.samples.count))
            let robust = HandleRefiner.refine(start: exact, tether: exact, measurement: gross, radii: .nominal, iterations: 6,
                                              parameters: .init())
            var plain = CalibrationParameters()
            plain.huberK = 1e9
            plain.outlierCutoff = 1e9
            let squares = HandleRefiner.refine(start: exact, tether: exact, measurement: gross, radii: .nominal, iterations: 6,
                                               parameters: plain)
            #expect(error(robust, truth: truth) < 0.01)
            #expect(error(squares, truth: truth) > 0.3)
        }

        @Test func refine_downweightsObservationsBetweenHuberAndTheCutoff() async {
            let camera = SupportPoses.d.camera
            let truth = camera.boardToImage
            let exact = camera.exactHandles().points.map { SIMD2($0.x, $0.y) }
            // Every fifth sample pushed outwards (rings) or clockwise (wires) by 2.9 mm: within the cutoff, beyond Huber.
            let spread = Set(stride(from: 0, to: EdgeSampler.samples.count, by: 5))
            let biased = measurement(truth: truth, outliers: spread, offset: 2.9)
            let robust = HandleRefiner.refine(start: exact, tether: exact, measurement: biased, radii: .nominal, iterations: 6,
                                              parameters: .init())
            var plain = CalibrationParameters()
            plain.huberK = 1e9
            plain.outlierCutoff = 1e9
            let squares = HandleRefiner.refine(start: exact, tether: exact, measurement: biased, radii: .nominal, iterations: 6,
                                               parameters: plain)
            #expect(error(robust, truth: truth) < 0.5 * error(squares, truth: truth))
            #expect(HandleRefiner.weight(of: 0.5, parameters: .init()) == 1)
            #expect(HandleRefiner.weight(of: -1.5, parameters: .init()) == 0.5)
            #expect(HandleRefiner.weight(of: 3.01, parameters: .init()) == 0)
            #expect(HandleRefiner.weight(of: .nan, parameters: .init()) == 0)
        }

        @Test func acceptanceGuard_eachClauseRefuses() async throws {
            let camera = SupportPoses.a.camera
            let still = CalibrationFixtures.still(camera, seed: 31)
            var random = SupportRandom(seed: 31)
            let handles = CalibrationFixtures.noisy(camera.exactHandles(), sigma: 1, random: &random)
            let accepted = try #require(CalibrationFixtures.calibrate(handles: handles, still: still, camera: camera))
            #expect(accepted.quality.refinementApplied)
            let clauses: [(String, (inout CalibrationParameters) -> Void)] = [
                ("measured", { $0.minMeasuredFraction = 1.01 }),
                ("inliers", { $0.minInlierFraction = 1.01 }),
                ("rms", { $0.maxInlierRMS = 0.001 }),
                ("shift", { $0.maxHandleShift = 0.01 }),
            ]
            for (name, change) in clauses {
                await Task.yield()
                var parameters = CalibrationParameters()
                change(&parameters)
                let refused = try #require(CalibrationFixtures.calibrate(BoardCalibrator(parameters: parameters), handles: handles,
                                                                         still: still, camera: camera))
                #expect(!refused.quality.refinementApplied && refused.handles == handles, "\(name)")
                #expect(refused.quality.issues.contains(.refinementRejected) && refused.quality.grade == .poor, "\(name)")
            }
        }

        @Test func health_eachClauseDecides() async throws {
            let camera = SupportPoses.c.camera
            let calibration = camera.calibration()
            let still = CalibrationFixtures.still(camera, seed: 32)
            #expect(BoardCalibrator().assess(calibration, on: still, dartsOnBoard: false).status == .healthy)
            var strictInliers = CalibrationParameters()
            strictInliers.driftHealthyInliers = 1.01
            #expect(BoardCalibrator(parameters: strictInliers).assess(calibration, on: still, dartsOnBoard: false).status != .healthy)
            #expect(BoardCalibrator(parameters: strictInliers).assess(calibration, on: still, dartsOnBoard: true).status == .healthy)
            var strictWithDarts = CalibrationParameters()
            strictWithDarts.driftHealthyInliersWithDarts = 1.01
            #expect(BoardCalibrator(parameters: strictWithDarts).assess(calibration, on: still, dartsOnBoard: true).status != .healthy)
            var strictMedian = CalibrationParameters()
            strictMedian.driftHealthyMedian = 0.0001
            #expect(BoardCalibrator(parameters: strictMedian).assess(calibration, on: still, dartsOnBoard: false).status != .healthy)
        }

        /// A board that jumped by 40 px at 1.1 px/mm (pose B) leaves fewer than 30 % of the samples accepted, yet its
        /// edges are all there: the check calls it lost, not invisible (see `BoardCalibrator.assess`). A hand over most
        /// of the board, on the other hand, hides the edges.
        @Test func health_aJumpIsNotDarkness() async throws {
            let camera = SupportPoses.b.camera
            let calibration = camera.calibration()
            var scene = SupportScenes.empty(seed: 63)
            scene.shift = SIMD2(0, 40)
            let still = scene.render(camera: camera)
            let health = BoardCalibrator().assess(calibration, on: still, dartsOnBoard: false)
            #expect(health.measuredFraction < 0.3)
            #expect(health.status == .lost)
            let visible = EdgeSamplerRaster.with(still) { raster in
                EdgeSampler.visibleFraction(raster, boardToImage: calibration.boardToImage, radii: .nominal, parameters: .init())
            }
            #expect(visible > 0.5)

            var hand = SupportScenes.empty(seed: 64)
            hand.hand = (BoardPoint(x: 0, y: 0), 150)
            let covered = BoardCalibrator().assess(calibration, on: hand.render(camera: camera), dartsOnBoard: false)
            #expect(covered.status == .edgesNotVisible)
        }
    }
}
