import Foundation
import simd
import Testing
import DartCore
@testable import DartVision

extension CalibrationTests {
    /// Drift check and recovery (VISION.md §4.9): `assess` and `recover` on stills and frames. Case C8.
    @Suite struct CalibrationDriftTests {
        private let calibrator = BoardCalibrator()

        /// A calibration made by the calibrator from slightly noisy handles on an empty board.
        private func calibrated(_ camera: SyntheticCamera, seed: UInt64) throws -> BoardCalibration {
            var random = SupportRandom(seed: seed)
            let handles = CalibrationFixtures.noisy(camera.exactHandles(), sigma: 1, random: &random)
            return try #require(CalibrationFixtures.calibrate(handles: handles, still: CalibrationFixtures.still(camera, seed: seed),
                                                              camera: camera))
        }

        @Test func c8_threeDartsOnTheBoardAreHealthy() async throws {
            var random = SupportRandom(seed: 81)
            for (index, camera) in SupportPoses.cameras.enumerated() {
                await Task.yield()
                let calibration = try calibrated(camera, seed: UInt64(80 + index))
                let darts = (0..<3).map { _ in SupportScenes.randomDart(&random) }
                let still = SupportScenes.darts(darts, seed: UInt64(90 + index)).render(camera: camera)
                let health = calibrator.assess(calibration, on: still, dartsOnBoard: true)
                #expect(health.status == .healthy, "pose \(index): \(health)")
                #expect(health.medianResidual <= 0.5 && health.inlierFraction >= 0.5 && health.measuredFraction >= 0.3)
                // The empty board as well.
                let empty = calibrator.assess(calibration, on: CalibrationFixtures.still(camera, seed: 3), dartsOnBoard: false)
                #expect(empty.status == .healthy && empty.inlierFraction >= 0.9 && empty.medianResidual < 0.2)
            }
        }

        @Test func c8_smallShiftDriftsAndIsRecovered() async throws {
            for (index, camera) in SupportPoses.cameras.enumerated() {
                await Task.yield()
                let calibration = try calibrated(camera, seed: UInt64(70 + index))
                var scene = SupportScenes.empty(seed: UInt64(71 + index))
                scene.shift = SIMD2(3, -2)
                let still = scene.render(camera: camera)
                let health = calibrator.assess(calibration, on: still, dartsOnBoard: false)
                #expect(health.status == .drifted, "pose \(index): \(health)")
                let recovered = try #require(calibrator.recover(calibration, on: still))
                let truth = CalibrationFixtures.shifted(camera.boardToImage, by: scene.shift)
                let errors = CalibrationFixtures.errors(of: recovered, truth: truth)
                #expect(errors.max <= 0.4, "pose \(index): \(errors)")
                // What the recovery keeps and what it changes.
                #expect(recovered.userHandles == calibration.handles && recovered.handles != calibration.handles)
                #expect(recovered.ringRadii == calibration.ringRadii && recovered.wireHeight == calibration.wireHeight)
                #expect(recovered.intrinsics == calibration.intrinsics && recovered.imageSize == calibration.imageSize)
                #expect(recovered.quality.refinementApplied && recovered.id != calibration.id)
                // After the recovery, the shifted still is healthy.
                #expect(calibrator.assess(recovered, on: still, dartsOnBoard: false).status == .healthy)
            }
        }

        @Test func c8_largeShiftIsLost() async throws {
            for (index, camera) in SupportPoses.cameras.enumerated() {
                await Task.yield()
                let calibration = try calibrated(camera, seed: UInt64(60 + index))
                for k in 0..<4 {
                    await Task.yield()
                    let a = (22.5 + 90 * Double(k) + 11 * Double(index)) * Double.pi / 180
                    var scene = SupportScenes.empty(seed: UInt64(61 + index + 10 * k))
                    scene.shift = SIMD2(40 * cos(a), 40 * sin(a))
                    let still = scene.render(camera: camera)
                    let health = calibrator.assess(calibration, on: still, dartsOnBoard: false)
                    #expect(health.status == .lost, "pose \(index), direction \(k): \(health)")
                    #expect(calibrator.recover(calibration, on: still) == nil)
                }
            }
        }

        @Test func c8_uniformGreyShowsNoEdges() async throws {
            for (index, camera) in SupportPoses.cameras.enumerated() {
                await Task.yield()
                let calibration = try calibrated(camera, seed: UInt64(50 + index))
                let grey = RGBImage(width: camera.imageSize.width, height: camera.imageSize.height, fill: SIMD3(128, 128, 128))
                let health = calibrator.assess(calibration, on: grey, dartsOnBoard: false)
                #expect(health.status == .edgesNotVisible && health.measuredFraction == 0)
                #expect(calibrator.recover(calibration, on: grey) == nil)
                // Darkness: the board is there, but no edge reaches the energy of an edge.
                var dark = SupportScenes.empty(seed: UInt64(55 + index))
                dark.gain = 0.05
                #expect(calibrator.assess(calibration, on: dark.render(camera: camera), dartsOnBoard: false).status == .edgesNotVisible)
            }
        }

        @Test func assessAndRecover_readFramesLikeStills() async throws {
            let camera = SupportPoses.b.camera
            let calibration = try calibrated(camera, seed: 40)
            var scene = SupportScenes.empty(seed: 41)
            scene.shift = SIMD2(2, 2)
            let still = scene.render(camera: camera)
            let frame = Frame(image: still, timestamp: 12)
            #expect(calibrator.assess(calibration, on: frame, dartsOnBoard: false)
                == calibrator.assess(calibration, on: still, dartsOnBoard: false))
            #expect(calibrator.recover(calibration, on: frame) == calibrator.recover(calibration, on: still))
            #expect(calibrator.recover(calibration, on: still) != nil)
        }

        @Test func assess_ofAnotherImageSizeIsLost() async throws {
            let camera = SupportPoses.b.camera
            let calibration = try calibrated(camera, seed: 30)
            let small = SupportScenes.empty().render(camera: SupportPoses.b.camera(longSide: 960))
            #expect(calibrator.assess(calibration, on: small, dartsOnBoard: false).status == .lost)
            #expect(calibrator.recover(calibration, on: small) == nil)
        }
    }
}
