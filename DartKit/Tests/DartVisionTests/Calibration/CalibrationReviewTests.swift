import Foundation
import simd
import Testing
import DartCore
@testable import DartVision

extension CalibrationTests {
    /// Independent checks of lot V2 by its review (RV2): a board turned on its bracket after calibration, hostile
    /// inputs, determinism. Expected values come from VISION.md §4, not from the code.
    @Suite struct CalibrationReviewTests {
        private let calibrator = BoardCalibrator()

        /// The calibration of exact handles on a clean still of `camera`.
        private func calibrated(_ camera: SyntheticCamera, still: RGBImage) throws -> BoardCalibration {
            try #require(CalibrationFixtures.calibrate(handles: camera.exactHandles(), still: still, camera: camera))
        }

        /// The calibration a still of a board turned by `degrees` (clockwise, about the bull) would have kept: the
        /// handles of `calibration` turned the other way on the board. Built by `preview`, as the engine holds it.
        private func turned(_ calibration: BoardCalibration, by degrees: Double) throws -> BoardCalibration {
            let model = calibration.boardToImage.concatenating(.boardRotation(clockwiseDegrees: -degrees))
            let handles = CalibrationHandles(projecting: model)
            guard case .success(let stale) = calibrator.preview(handles: handles, imageSize: calibration.imageSize,
                                                                 rotationDegrees: 0, intrinsics: calibration.intrinsics)
            else { throw CalibrationReviewError.previewRefused }
            return stale
        }

        private enum CalibrationReviewError: Error { case previewRefused }

        /// VISION.md §4.9: `assess` must not call healthy a board that moved. A board that turned on its bracket keeps
        /// every ring where it was (rings are round), and only the radial wires show the turn: 2° already puts the
        /// wires 6 mm off at the double, a third of a sector at 9°. Before the review, every wire sample that left
        /// its ±4 mm window simply stopped counting, the ring samples were all inliers, and such a board was healthy.
        @Test func assess_aBoardTurnedOnItsBracketIsNotHealthy() async throws {
            let camera = SupportPoses.b.camera
            let still = CalibrationFixtures.still(camera, seed: 11)
            let calibration = try calibrated(camera, still: still)
            #expect(calibrator.assess(calibration, on: still, dartsOnBoard: false).status == .healthy)
            for degrees in [2.0, -3.0, 5.0, 9.0, -9.0] {
                await Task.yield()
                let stale = try turned(calibration, by: degrees)
                let health = calibrator.assess(stale, on: still, dartsOnBoard: false)
                #expect(health.status != .healthy, "turned by \(degrees)°: \(health)")
                #expect(health.status != .edgesNotVisible, "turned by \(degrees)°: \(health)")
                if health.status == .drifted {
                    // A drift is only reported when `recover` brings the wires back.
                    let recovered = try #require(calibrator.recover(stale, on: still))
                    let errors = CalibrationFixtures.errors(of: recovered, truth: camera.boardToImage)
                    #expect(errors.max <= 0.5, "turned by \(degrees)°, recovered: \(errors)")
                }
            }
            // A turn of a tenth of a degree (0.3 mm at the double) is no drift.
            let slight = try turned(calibration, by: 0.1)
            #expect(calibrator.assess(slight, on: still, dartsOnBoard: false).status == .healthy)
        }

        /// The same with three darts on the board (the threshold of §4.9 is then 0.5).
        @Test func assess_aTurnedBoardWithDartsIsNotHealthy() async throws {
            let camera = SupportPoses.a.camera
            let still = CalibrationFixtures.still(camera, seed: 12)
            let calibration = try calibrated(camera, still: still)
            var random = SupportRandom(seed: 13)
            let darts = (0..<3).map { _ in SupportScenes.randomDart(&random) }
            let withDarts = SupportScenes.darts(darts, seed: 14).render(camera: camera)
            #expect(calibrator.assess(calibration, on: withDarts, dartsOnBoard: true).status == .healthy)
            for degrees in [3.0, 6.0] {
                await Task.yield()
                let stale = try turned(calibration, by: degrees)
                let health = calibrator.assess(stale, on: withDarts, dartsOnBoard: true)
                #expect(health.status != .healthy, "turned by \(degrees)°: \(health)")
            }
        }

        // MARK: Hostile inputs (none may trap)

        /// Handles that cannot make a board: none, three, five, a NaN, infinities, absurd magnitudes, a crossed quad.
        @Test func hostileHandles_areRefusedWithoutTrapping() async {
            let camera = SupportPoses.b.camera
            let exact = camera.exactHandles().points
            let nan = ImagePoint(x: .nan, y: .nan)
            let degenerate: [[ImagePoint]] = [
                [], Array(exact.prefix(3)), exact + [exact[0]], [nan, exact[1], exact[2], exact[3]],
                exact.map { ImagePoint(x: .infinity, y: $0.y) }, exact.map { _ in exact[0] },
            ]
            let still = RGBImage(width: 64, height: 36, fill: SIMD3(90, 90, 90))
            for points in degenerate {
                let handles = CalibrationHandles(points: points)
                #expect(calibrator.preview(handles: handles, imageSize: camera.imageSize, rotationDegrees: 0, intrinsics: nil)
                    == .failure(.degenerateHandles), "\(points)")
                #expect(calibrator.calibrate(handles: handles, still: still, rotationDegrees: 0, intrinsics: nil)
                    == .failure(.degenerateHandles), "\(points)")
            }
            // Finite but absurd placements are refused, never accepted.
            let absurd: [[ImagePoint]] = [
                exact.map { ImagePoint(x: $0.x * 1e300, y: $0.y) },
                exact.map { ImagePoint(x: $0.x + 1e12, y: $0.y - 1e12) },
                [exact[0], exact[2], exact[1], exact[3]],
                exact.map { ImagePoint(x: $0.x * 1e-9, y: $0.y * 1e-9) },
            ]
            for points in absurd {
                let result = calibrator.preview(handles: CalibrationHandles(points: points), imageSize: camera.imageSize,
                                                rotationDegrees: 0, intrinsics: nil)
                if case .success(let calibration) = result { Issue.record("accepted \(points): \(calibration.quality)") }
            }
            // Intrinsics that make no camera: refused, never a pose with NaN.
            for intrinsics in [CameraIntrinsics(fx: .nan, fy: .nan, cx: 0, cy: 0, source: .assumed),
                               CameraIntrinsics(fx: 0, fy: 0, cx: 0, cy: 0, source: .assumed)] {
                let result = calibrator.preview(handles: camera.exactHandles(), imageSize: camera.imageSize, rotationDegrees: 0,
                                                intrinsics: intrinsics)
                if case .success(let calibration) = result {
                    #expect(calibration.pose.distance.isFinite && calibration.quality.minTanObliquity.isFinite)
                }
            }
        }

        /// Stills without a board, or not matching their size: the player's handles are kept, the refinement is
        /// refused, nothing traps; `assess` and `recover` answer.
        @Test func hostileStills_neverTrap() async throws {
            let camera = SupportPoses.b.camera
            let size = camera.imageSize
            let handles = camera.exactHandles()
            let stills: [RGBImage] = [
                RGBImage(width: size.width, height: size.height, fill: SIMD3(0, 0, 0)),
                RGBImage(width: size.width, height: size.height, fill: SIMD3(255, 255, 255)),
                RGBImage(width: size.width, height: size.height, pixels: []),
                RGBImage(width: 0, height: 0, pixels: []),
                RGBImage(width: 1, height: 1, fill: SIMD3(200, 40, 40)),
            ]
            for still in stills {
                await Task.yield()
                switch calibrator.calibrate(handles: handles, still: still, rotationDegrees: 0, intrinsics: camera.intrinsics) {
                case .success(let calibration):
                    #expect(calibration.handles == handles && !calibration.quality.refinementApplied)
                    #expect(calibration.quality.grade == .poor && calibration.quality.issues.contains(.refinementRejected))
                case .failure(let error):
                    // A still smaller than the board is a board out of frame.
                    #expect(still.width < size.width, "\(error)")
                }
            }
            let calibration = try calibrated(camera, still: CalibrationFixtures.still(camera, seed: 15))
            for still in stills {
                let health = calibrator.assess(calibration, on: still, dartsOnBoard: false)
                #expect(health.status == .edgesNotVisible || health.status == .lost, "\(health)")
                #expect(calibrator.recover(calibration, on: still) == nil)
            }
        }

        /// The locator on images that hold no board, or barely any pixel: nil, no trap. On a mirror image of a
        /// board it may find the board (the colour pattern of a board is symmetric), but whatever it returns has
        /// finite handles in the image and ten distinct orientations.
        @Test func hostileImages_locator() async {
            let locator = ColourBoardLocator()
            var noise = RGBImage(width: 640, height: 480, fill: SIMD3(0, 0, 0))
            var random = SupportRandom(seed: 16)
            for index in noise.pixels.indices { noise.pixels[index] = UInt8(random.int(below: 256)) }
            let images: [RGBImage] = [
                RGBImage(width: 0, height: 0, pixels: []), RGBImage(width: 1, height: 1, fill: SIMD3(200, 40, 40)),
                RGBImage(width: 7, height: 7, fill: SIMD3(200, 40, 40)), RGBImage(width: 8, height: 8, fill: SIMD3(30, 140, 70)),
                RGBImage(width: 640, height: 480, fill: SIMD3(255, 255, 255)), RGBImage(width: 640, height: 480, fill: SIMD3(200, 40, 40)),
                RGBImage(width: 2000, height: 16, fill: SIMD3(30, 140, 70)), RGBImage(width: 640, height: 480, pixels: [1, 2, 3]),
                noise,
            ]
            for image in images {
                await Task.yield()
                #expect(locator.locate(in: image, upDirection: SIMD2(0, -1)) == nil, "\(image.width)x\(image.height)")
                #expect(locator.locate(in: image, upDirection: SIMD2(.nan, .infinity)) == nil)
            }
            let camera = SupportPoses.b.camera
            let board = CalibrationFixtures.still(camera, seed: 17)
            var mirrored = board
            for y in 0..<board.height {
                for x in 0..<board.width {
                    for channel in 0..<3 {
                        mirrored.pixels[3 * (y * board.width + x) + channel] = board.pixels[3 * (y * board.width + board.width - 1 - x) + channel]
                    }
                }
            }
            if let location = locator.locate(in: mirrored, upDirection: SIMD2(0, -1)) {
                let all = [location.handles] + location.alternatives
                #expect(all.count == 10 && Set(all).count == 10)
                #expect(all.allSatisfy { $0.points.count == 4 && $0.points.allSatisfy { $0.x.isFinite && $0.y.isFinite } })
            }
        }

        /// The other entry points of the calibration on absurd arguments.
        @Test func hostileArguments_handlesAndWireframe() async throws {
            let camera = SupportPoses.b.camera
            let handles = camera.exactHandles()
            #expect(handles.reoriented(twentyAt: ImagePoint(x: .nan, y: 0), parityPreserving: false) == nil)
            #expect(handles.rotated(bySectors: Int.min) != nil && handles.rotated(bySectors: Int.max) != nil)
            #expect(CalibrationHandles(points: []).rotated(bySectors: 1) == nil)
            let calibration = try #require(CalibrationFixtures.preview(handles: handles, camera: camera))
            for segments in [Int.min, -1, 0, 3, Int.max] {
                let wireframe = calibration.wireframe(ringSegments: segments)
                #expect(wireframe.rings.count == 6 && wireframe.rings.allSatisfy { $0.count >= 4 && $0.count <= 4097 })
            }
            #expect(calibration.hit(at: ImagePoint(x: .nan, y: .infinity), board: .standard) == .miss)
            let scale = calibration.localScale(at: BoardPoint(x: .nan, y: 0))
            _ = scale
        }

        // MARK: Determinism

        /// The same still gives the same location, and the same calibration, bit for bit (X16 replays them).
        @Test func locatorAndCalibrator_areDeterministic() async throws {
            let camera = SupportPoses.b.camera
            let still = CalibrationFixtures.still(camera, seed: 18)
            let locator = ColourBoardLocator()
            let first = try #require(locator.locate(in: still, upDirection: SIMD2(0, -1)))
            let second = try #require(locator.locate(in: still, upDirection: SIMD2(0, -1)))
            #expect(first.handles == second.handles && first.alternatives == second.alternatives
                && first.phaseContrast == second.phaseContrast)
            let a = calibrator.calibrate(handles: first.handles, still: still, rotationDegrees: 0, intrinsics: nil)
            let b = calibrator.calibrate(handles: second.handles, still: still, rotationDegrees: 0, intrinsics: nil)
            #expect(a == b)
            let calibration = try #require(try? a.get())
            #expect(calibration.id == (try? b.get())?.id)
            #expect(calibrator.assess(calibration, on: still, dartsOnBoard: false) == calibrator.assess(calibration, on: still, dartsOnBoard: false))
        }
    }
}
