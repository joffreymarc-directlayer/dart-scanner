import Foundation
import simd
import Testing
import DartCore
@testable import DartVision

extension CalibrationTests {
    /// Automatic board finding, the optional layer (VISION.md §4.3): conic fit, construction, phase, orientation.
    /// Cases L1 to L5.
    @Suite struct CalibrationLocatorTests {
        private let locator = ColourBoardLocator()

        /// `H` of a camera in the coordinates of a work image averaged by `factor`: `x_work = (x + 0.5) / factor − 0.5`.
        private func workTransform(_ transform: Homography, factor: Int) -> Homography {
            let f = Double(factor)
            let scale = Homography(simd_double3x3(rows: [SIMD3(1 / f, 0, 0.5 / f - 0.5), SIMD3(0, 1 / f, 0.5 / f - 0.5),
                                                         SIMD3(0, 0, 1)]))
            return scale.concatenating(transform)
        }

        /// The conic of the board circle of `radius` seen through `transform`: `H⁻ᵀ·diag(1, 1, −R²)·H⁻¹`, A + C = 1.
        private func circleConic(_ transform: Homography, radius: Double) -> ConicFit? {
            guard let inverse = transform.inverse?.matrix else { return nil }
            let q = inverse.transpose * simd_double3x3(diagonal: SIMD3(1, 1, -radius * radius)) * inverse
            return ConicFit(matrix: q).normalised
        }

        /// Largest distance between corresponding handles, px.
        private func distance(_ a: CalibrationHandles, _ b: CalibrationHandles) -> Double {
            zip(a.points, b.points).map { simd_length(SIMD2($0.x - $1.x, $0.y - $1.y)) }.max() ?? .infinity
        }

        @Test func l1_conicFitIsExactWithoutNoise() async throws {
            for camera in SupportPoses.cameras {
                await Task.yield()
                let h = camera.boardToImage
                let points = (0..<360).map { k -> SIMD2<Double> in
                    let a = 2 * Double.pi * Double(k) / 360
                    return h.apply(SIMD2(170 * sin(a), 170 * cos(a)))
                }
                let fitted = try #require(ConicFit.fit(points))
                let truth = try #require(circleConic(h, radius: 170))
                // Coefficients of x², xy, y² are of order 1; of x and y of order L; the constant of order L².
                let size = Double(max(camera.imageSize.width, camera.imageSize.height))
                #expect(abs(fitted.a - truth.a) < 1e-8 && abs(fitted.b - truth.b) < 1e-8 && abs(fitted.c - truth.c) < 1e-8)
                #expect(abs(fitted.d - truth.d) / size < 1e-8 && abs(fitted.e - truth.e) / size < 1e-8)
                #expect(abs(fitted.f - truth.f) / (size * size) < 1e-8)
                #expect(fitted.isEllipse && abs(fitted.a + fitted.c - 1) < 1e-12)
                #expect(points.allSatisfy { fitted.sampsonDistance($0) < 1e-6 })
            }
        }

        @Test func l1_constructionFromANoisyEllipseAt640Pixels() async throws {
            var random = SupportRandom(seed: 101)
            for camera in SupportPoses.cameras {
                await Task.yield()
                let factor = Int((Double(max(camera.imageSize.width, camera.imageSize.height)) / 640).rounded())
                let h = workTransform(camera.boardToImage, factor: factor)
                let points = (0..<360).map { k -> SIMD2<Double> in
                    let a = 2 * Double.pi * Double(k) / 360
                    return h.apply(SIMD2(170 * sin(a), 170 * cos(a))) + 0.5 * SIMD2(random.gaussian(), random.gaussian())
                }
                let fitted = try #require(ConicFit.robustFit(points, tolerance: 1.5))
                #expect(fitted.kept.filter { $0 }.count >= 300)
                let centre = h.apply(SIMD2(0, 0))
                let provisional = try #require(ColourBoardLocator.provisionalHomography(conic: fitted.conic, centre: centre))
                let back = try #require(provisional.inverse)
                // Exact up to a rotation: radii are what the construction must get right.
                let radial = CalibrationFixtures.boardPoints(count: 200, seed: 102).map { point -> Double in
                    let read = back.apply(h.apply(SIMD2(point.x, point.y)))
                    return abs(simd_length(read) - (point.x * point.x + point.y * point.y).squareRoot())
                }
                #expect(CalibrationFixtures.summary(radial).p95 <= 2)
                // A physical view: negative Jacobian determinant at the bull.
                #expect(simd_determinant(provisional.jacobian(at: SIMD2(0, 0))) < 0)
            }
        }

        @Test func l1_constructionWithoutNoiseIsARotationOfTheTruth() async throws {
            for camera in SupportPoses.cameras {
                await Task.yield()
                let h = camera.boardToImage
                let conic = try #require(circleConic(h, radius: 170))
                let provisional = try #require(ColourBoardLocator.provisionalHomography(conic: conic, centre: h.apply(SIMD2(0, 0))))
                let rotation = try #require(provisional.inverse).concatenating(h)
                // H0⁻¹·H is a pure rotation of the board (VISION.md §4.3, L5).
                for point in CalibrationFixtures.boardPoints(count: 50) {
                    await Task.yield()
                    let p = SIMD2(point.x, point.y)
                    #expect(abs(simd_length(rotation.apply(p)) - simd_length(p)) < 1e-6)
                }
            }
        }

        @Test func l2_phaseByTheTenthHarmonic() async throws {
            for (index, camera) in SupportPoses.cameras.enumerated() {
                await Task.yield()
                let still = CalibrationFixtures.still(camera, seed: UInt64(20 + index))
                let work = try #require(ColourBoardLocator.WorkImage(still, longSide: 640, parameters: .init()))
                let h = workTransform(camera.boardToImage, factor: work.factor)
                for gamma in [0, 5.5, 12.3, 18, 29.9, 35.2] {
                    await Task.yield()
                    let provisional = h.concatenating(.boardRotation(clockwiseDegrees: gamma))
                    let expected = (36 - gamma.truncatingRemainder(dividingBy: 36)).truncatingRemainder(dividingBy: 36)
                    for radius in [166.0, 103.0] {
                        await Task.yield()
                        let phase = try #require(ColourBoardLocator.phase(of: work, through: provisional, radius: radius))
                        #expect(ColourBoardLocator.angularDistance(phase.beta, expected, period: 36) <= 0.5,
                                "pose \(index) γ \(gamma) r \(radius): \(phase.beta)")
                        #expect(phase.contrast >= 0.5 && phase.contrast <= 0.7)
                    }
                }
            }
        }

        /// The twelve poses of L3: 0.9 to 1.5 m, 15 to 35 degrees, below, below-left and below-right, roll within ±10.
        private var l3Cameras: [SyntheticCamera] {
            let azimuths: [Double] = [180, 150, 210]
            return (0..<12).map { (k: Int) -> SyntheticCamera in
                let distance: Double = 900 + 600 * Double(k) / 11
                let angle: Double = 15 + 20 * Double((k * 7) % 12) / 11
                let roll: Double = -10 + 20 * Double((k * 5) % 12) / 11
                return SupportRandom.camera(distance: distance, viewAngleDegrees: angle, azimuthDegrees: azimuths[k % 3],
                                            rollDegrees: roll, imageSize: PixelSize(width: 2160, height: 3840))
            }
        }

        @Test func l3_twelvePoses() async throws {
            var found = 0
            let calibrator = BoardCalibrator()
            for (index, camera) in l3Cameras.enumerated() {
                await Task.yield()
                let still = CalibrationFixtures.still(camera, seed: UInt64(30 + index))
                guard let location = locator.locate(in: still, upDirection: SIMD2(0, -1)) else { continue }
                let exact = camera.exactHandles()
                guard distance(location.handles, exact) <= 10 else { continue }
                found += 1
                #expect(location.alternatives.count == 9)
                #expect(location.phaseContrast >= 0.35 && location.phaseContrast <= 0.7)
                // The calibration then runs as with handles placed by hand.
                let calibration = try #require(CalibrationFixtures.calibrate(calibrator, handles: location.handles, still: still,
                                                                             camera: camera))
                #expect(calibration.quality.refinementApplied, "pose \(index)")
                #expect(CalibrationFixtures.errors(of: calibration, truth: camera.boardToImage).p95 <= 1.0, "pose \(index)")
            }
            #expect(found >= 11)
        }

        /// An image of `width × height` whose pixel `(x, y)` is `colour(x, y)`.
        private func image(width: Int, height: Int, _ colour: (Int, Int) -> SIMD3<UInt8>) -> RGBImage {
            var pixels = [UInt8](repeating: 0, count: width * height * 3)
            for y in 0..<height {
                for x in 0..<width {
                    let c = colour(x, y)
                    let index = (y * width + x) * 3
                    pixels[index] = c.x
                    pixels[index + 1] = c.y
                    pixels[index + 2] = c.z
                }
            }
            return RGBImage(width: width, height: height, pixels: pixels)
        }

        @Test func l4_noFalsePositives() async {
            let width = 1920, height = 1080
            var random = SupportRandom(seed: 44)
            var images: [RGBImage] = []
            // Fine colour noise, and coarse colour noise in 24-pixel blocks.
            let fine = (0..<(width * height)).map { _ in
                SIMD3(UInt8(random.int(below: 256)), UInt8(random.int(below: 256)), UInt8(random.int(below: 256)))
            }
            images.append(image(width: width, height: height) { x, y in fine[y * width + x] })
            let blocks = (0..<(80 * 45)).map { _ in
                SIMD3(UInt8(random.int(below: 256)), UInt8(random.int(below: 256)), UInt8(random.int(below: 256)))
            }
            images.append(image(width: width, height: height) { x, y in blocks[(y / 24) * 80 + x / 24] })
            // Red and green stripes, upright and slanted.
            for slant in [0.0, 0.6] {
                await Task.yield()
                images.append(image(width: width, height: height) { x, y in
                    Int((Double(x) + slant * Double(y)) / 30) % 2 == 0 ? SIMD3(200, 40, 40) : SIMD3(30, 140, 70)
                })
            }
            // A single red ring; then the same ring alternating red and green like a double ring, without a bull.
            for alternating in [false, true] {
                await Task.yield()
                images.append(image(width: width, height: height) { x, y in
                    let dx = Double(x) - 960, dy = Double(y) - 540
                    let r = (dx * dx + dy * dy).squareRoot()
                    guard r >= 330, r <= 360 else { return SIMD3(120, 120, 125) }
                    let sector = Int(((atan2(dx, -dy) * 180 / .pi + 369).truncatingRemainder(dividingBy: 360)) / 18)
                    return alternating && sector % 2 == 1 ? SIMD3(30, 140, 70) : SIMD3(200, 40, 40)
                })
            }
            // A blank wall.
            images.append(RGBImage(width: width, height: height, fill: SIMD3(120, 120, 125)))
            for (index, image) in images.enumerated() {
                await Task.yield()
                #expect(locator.locate(in: image, upDirection: SIMD2(0, -1)) == nil, "image \(index)")
            }
        }

        @Test func l5_cameraRolledByThirtyDegrees() async throws {
            for (index, roll) in [30.0, -30].enumerated() {
                await Task.yield()
                let camera = SyntheticCamera(imageSize: PixelSize(width: 2160, height: 3840), position: SIMD3(150, -450, 1100),
                                             rollDegrees: roll)
                let still = CalibrationFixtures.still(camera, seed: UInt64(50 + index))
                let location = try #require(locator.locate(in: still, upDirection: SIMD2(0, -1)))
                let exact = camera.exactHandles()
                // The orientation nearest to the top of the image is the wrong one; the right one is an alternative.
                #expect(distance(location.handles, exact) > 50)
                #expect(location.alternatives.contains { distance($0, exact) <= 10 })
                // Touching the true 20 restores it.
                let twenty = CalibrationFixtures.project(camera, BoardPoint(x: 0, y: 198))
                let restored = try #require(location.handles.reoriented(twentyAt: twenty, parityPreserving: true))
                #expect(distance(restored, exact) <= 10)
                // So does giving the locator the camera's own up direction: the image of the board's +y at the bull.
                let up = camera.boardToImage.jacobian(at: SIMD2(0, 0)).columns.1
                let tilted = try #require(locator.locate(in: still, upDirection: up))
                #expect(distance(tilted.handles, exact) <= 10)
            }
        }

        @Test func locator_worksThroughTheProtocolAndOnSmallImages() async throws {
            let finder: any BoardLocating = ColourBoardLocator()
            let camera = SupportPoses.b.camera
            let still = CalibrationFixtures.still(camera, seed: 60)
            let location = try #require(finder.locate(in: still, upDirection: SIMD2(0, -1)))
            #expect(distance(location.handles, camera.exactHandles()) <= 10)
            // A zero up direction means "the top of the image".
            let fallback = try #require(finder.locate(in: still, upDirection: SIMD2(0, 0)))
            #expect(fallback.handles == location.handles)
            // A tiny image is no board.
            #expect(finder.locate(in: RGBImage(width: 4, height: 4, fill: SIMD3(200, 40, 40)), upDirection: SIMD2(0, -1)) == nil)
        }

        @Test func workImage_averagesBlocksAndMapsBack() async throws {
            let source = image(width: 48, height: 32) { x, y in x < 4 && y < 4 ? SIMD3(200, 40, 40) : SIMD3(0, 0, 0) }
            let work = try #require(ColourBoardLocator.WorkImage(source, longSide: 12, parameters: .init()))
            #expect(work.factor == 4 && work.width == 12 && work.height == 8)
            #expect(work.rgb[0] == SIMD3(200, 40, 40) && work.rgb[1] == SIMD3(0, 0, 0))
            #expect(work.sourcePoint(SIMD2(0, 0)) == ImagePoint(x: 1.5, y: 1.5))
            #expect(work.sourcePoint(SIMD2(2, 1)) == ImagePoint(x: 9.5, y: 5.5))
            #expect(ColourBoardLocator.WorkImage(source, longSide: 48, parameters: .init())?.factor == 1)
            #expect(ColourBoardLocator.WorkImage.otsuThreshold([Int](repeating: 0, count: 256)) == 0.5)
            var twoPeaks = [Int](repeating: 0, count: 256)
            twoPeaks[20] = 100
            twoPeaks[200] = 100
            let threshold = ColourBoardLocator.WorkImage.otsuThreshold(twoPeaks)
            #expect(threshold > 20.0 / 256 && threshold <= 200.0 / 256)
        }

        /// A target that has everything but the structure of a board: a bull, a gap, then red and green sectors from
        /// 25 mm to the outer edge (no single beds). It passes the ellipse, the bull and the phase; L6 refuses it.
        @Test func l4_aColouredPieIsNoBoard() async {
            let scale = 2.0
            let pie = image(width: 1920, height: 1080) { x, y in
                let dx = (Double(x) - 959.5) / scale, dy = (539.5 - Double(y)) / scale
                let r = (dx * dx + dy * dy).squareRoot()
                let sector = Int(((atan2(dx, dy) * 180 / .pi + 369).truncatingRemainder(dividingBy: 360)) / 18)
                if r <= 16 { return r <= 6.35 ? SIMD3(200, 40, 40) : SIMD3(30, 140, 70) }
                if r < 25 || r > 170 { return SIMD3(120, 120, 125) }
                return sector % 2 == 0 ? SIMD3(200, 40, 40) : SIMD3(30, 140, 70)
            }
            #expect(locator.locate(in: pie, upDirection: SIMD2(0, -1)) == nil)
        }

        @Test func conic_sampsonDistanceAndRobustFit() async throws {
            // Circle x² + y² − 100² = 0, A + C = 1 after normalisation.
            let circle = ConicFit(a: 1, b: 0, c: 1, d: 0, e: 0, f: -10_000)
            for (radius, expected) in [(101.0, 1.0), (97.0, 3.0), (100.0, 0.0)] {
                await Task.yield()
                let distance = circle.sampsonDistance(SIMD2(radius * cos(0.3), radius * sin(0.3)))
                #expect(abs(distance - expected) < 0.02 * max(1, expected))
            }
            let ellipse = try #require(circle.ellipse)
            #expect(abs(ellipse.major - 100) < 1e-9 && abs(ellipse.minor - 100) < 1e-9 && simd_length(ellipse.centre) < 1e-9)
            #expect(ConicFit(a: 1, b: 0, c: -1, d: 0, e: 0, f: -1).ellipse == nil)
            // 10 % of outliers, 6 to 15 px off, are dropped and the circle is found again exactly.
            var random = SupportRandom(seed: 7)
            var points: [SIMD2<Double>] = []
            var outlier: [Bool] = []
            for k in 0..<200 {
                await Task.yield()
                let a = 2 * Double.pi * Double(k) / 200
                let wrong = k % 10 == 3
                let radius = wrong ? 100 + random.uniform(6...15) : 100
                points.append(SIMD2(300 + radius * cos(a), 200 + radius * sin(a)))
                outlier.append(wrong)
            }
            let fitted = try #require(ConicFit.robustFit(points, tolerance: 1.5))
            #expect(fitted.kept == outlier.map { !$0 })
            let centre = try #require(fitted.conic.ellipse)
            #expect(simd_length(centre.centre - SIMD2(300, 200)) < 1e-6 && abs(centre.major - 100) < 1e-6)
            // Intersections of a line through the centre with the circle.
            let hits = try #require(ConicFit.intersections(circle.matrix, point: SIMD3(0, 0, 1), direction: SIMD3(1, 0, 0)))
            let xs = [ConicFit.point(hits.0)?.x ?? 0, ConicFit.point(hits.1)?.x ?? 0].sorted()
            #expect(abs(xs[0] + 100) < 1e-9 && abs(xs[1] - 100) < 1e-9)
            #expect(ConicFit.intersections(circle.matrix, point: SIMD3(0, 500, 1), direction: SIMD3(1, 0, 0)) == nil)
        }
    }
}
