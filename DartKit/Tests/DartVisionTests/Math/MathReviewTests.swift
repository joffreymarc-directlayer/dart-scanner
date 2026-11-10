import Foundation
import simd
import Testing
import DartCore
@testable import DartVision

/// Adversarial review of lot V1 (`Geometry/`, `SyntheticCamera`): the ground truth recomputed from the formulas of
/// VISION.md §3 and §10.1 alone, and the geometry on inputs that must never trap.
@Suite struct MathReviewTests {
    /// A pinhole camera written from VISION.md §3.1, §3.6 and §10.1, without any code of the lot.
    private struct ReferenceCamera {
        var right: SIMD3<Double>, down: SIMD3<Double>, forward: SIMD3<Double>
        var centre: SIMD3<Double>
        var f: Double, cx: Double, cy: Double

        init(size: PixelSize, fieldOfViewDegrees: Double = 67, centre: SIMD3<Double>, lookAt: SIMD2<Double>) {
            self.centre = centre
            forward = simd_normalize(SIMD3(lookAt.x, lookAt.y, 0) - centre)
            right = simd_normalize(simd_cross(forward, SIMD3(0, 1, 0)))
            down = simd_cross(forward, right)
            // f = (max(W, H) / 2) / tan(FOV / 2), principal point ((W − 1) / 2, (H − 1) / 2).
            f = Double(max(size.width, size.height)) / 2 / tan(fieldOfViewDegrees / 2 * .pi / 180)
            cx = Double(size.width - 1) / 2
            cy = Double(size.height - 1) / 2
        }

        func project(_ p: SIMD3<Double>) -> SIMD2<Double> {
            let q = p - centre
            let z = simd_dot(forward, q)
            return SIMD2(f * simd_dot(right, q) / z + cx, f * simd_dot(down, q) / z + cy)
        }
    }

    private static func uniform(_ random: inout SeededRandom, _ range: ClosedRange<Double>) -> Double {
        range.lowerBound + (range.upperBound - range.lowerBound) * Double(random.next() >> 11) / 9007199254740992.0
    }

    @Test func syntheticCamera_projectsLikeTheDocumentedPinhole() {
        var random = SeededRandom(seed: 0xCA4E_0001)
        var worst = 0.0
        for trial in 0..<300 {
            let size = [PixelSize(width: 3840, height: 2160), PixelSize(width: 2160, height: 3840), PixelSize(width: 1920, height: 1080),
                        PixelSize(width: 1281, height: 719)][trial % 4]
            let centre = SIMD3(Self.uniform(&random, -600...600), Self.uniform(&random, -700...300), Self.uniform(&random, 700...1500))
            let lookAt = SIMD2(Self.uniform(&random, -60...60), Self.uniform(&random, -60...60))
            let fov = Self.uniform(&random, 40...80)
            let camera = SyntheticCamera(imageSize: size, longSideFieldOfViewDegrees: fov, position: centre,
                                         lookAt: BoardPoint(x: lookAt.x, y: lookAt.y))
            let reference = ReferenceCamera(size: size, fieldOfViewDegrees: fov, centre: centre, lookAt: lookAt)
            let h = camera.boardToImage
            for _ in 0..<10 {
                let p = SIMD3(Self.uniform(&random, -230...230), Self.uniform(&random, -230...230), Self.uniform(&random, 0...40))
                let expected = reference.project(p)
                let projected = camera.project(p)
                worst = max(worst, abs(projected.x - expected.x), abs(projected.y - expected.y))
                let onBoard = reference.project(SIMD3(p.x, p.y, 0))
                let mapped = h.apply(SIMD2(p.x, p.y))
                worst = max(worst, abs(mapped.x - onBoard.x), abs(mapped.y - onBoard.y))
            }
        }
        #expect(worst < 1e-6, "largest difference \(worst) px")
    }

    @Test func referencePoses_showTheBoardTheRightWayUp() {
        for pose in SupportPoses.allCases {
            let camera = pose.camera
            let bull = camera.project(SIMD3(0, 0, 0))
            let twenty = camera.project(SIMD3(0, 170, 0)), six = camera.project(SIMD3(170, 0, 0))
            let three = camera.project(SIMD3(0, -170, 0)), eleven = camera.project(SIMD3(-170, 0, 0))
            // 20 up, 6 right, 3 down, 11 left (VISION.md §3.3), the camera looking at the bull from its own side.
            #expect(twenty.y < bull.y && three.y > bull.y && six.x > bull.x && eleven.x < bull.x, "\(pose)")
            // The bull is at the principal point: every reference camera looks at it.
            #expect(abs(bull.x - Double(camera.imageSize.width - 1) / 2) < 1e-6 && abs(bull.y - Double(camera.imageSize.height - 1) / 2) < 1e-6)
            // The whole board with its number ring is in the frame (VISION.md §2.1).
            for k in 0..<36 {
                let a = Double(k) * 10 * .pi / 180
                let p = camera.project(SIMD3(225.5 * sin(a), 225.5 * cos(a), 0))
                #expect(p.x > 0 && p.y > 0 && p.x < Double(camera.imageSize.width - 1) && p.y < Double(camera.imageSize.height - 1), "\(pose) \(k)")
            }
        }
        // Pose A of VISION.md §10.2 gives 2.1 to 2.5 px/mm over the board.
        let a = SupportPoses.a.camera.calibration()
        #expect(a.quality.minPixelsPerMillimetre > 2.0 && a.quality.minPixelsPerMillimetre < 2.5)
    }

    @Test func exactCalibration_qualityFieldsFromTheGroundTruth() throws {
        for pose in SupportPoses.allCases {
            let camera = pose.camera
            let reference = ReferenceCamera(size: camera.imageSize, centre: pose.position, lookAt: SIMD2(0, 0))
            for grade in [CalibrationQuality.Grade.good, .fair, .poor] {
                let calibration = camera.calibration(grade: grade)
                // Worst-direction scale over the bull and 8 points of r = 170, by central differences of the pinhole.
                var worst = Double.infinity
                for k in -1..<8 {
                    let a = Double(max(k, 0)) * .pi / 4
                    let p = k < 0 ? SIMD2<Double>(0, 0) : SIMD2(170 * sin(a), 170 * cos(a))
                    let e = 1e-2
                    let dx = (reference.project(SIMD3(p.x + e, p.y, 0)) - reference.project(SIMD3(p.x - e, p.y, 0))) / (2 * e)
                    let dy = (reference.project(SIMD3(p.x, p.y + e, 0)) - reference.project(SIMD3(p.x, p.y - e, 0))) / (2 * e)
                    // Smaller singular value of [dx dy].
                    let aa = simd_dot(dx, dx), bb = simd_dot(dy, dy), ab = simd_dot(dx, dy)
                    let smallest = ((aa + bb - ((aa - bb) * (aa - bb) + 4 * ab * ab).squareRoot()) / 2).squareRoot()
                    worst = min(worst, smallest)
                }
                let q = calibration.quality
                #expect(abs(q.minPixelsPerMillimetre - worst) / worst < 1e-6, "\(pose) \(q.minPixelsPerMillimetre) vs \(worst)")
                let foot = hypot(pose.position.x, pose.position.y), distance = pose.position.z
                #expect(abs(q.viewAngleDegrees - atan(foot / distance) * 180 / .pi) < 1e-6)
                #expect(abs(q.minTanObliquity - (foot - 170) / distance) < 1e-9)
                #expect(abs(q.maxTanObliquity - (foot + 170) / distance) < 1e-9)
                #expect(q.grade == grade)
                // The pose recovered from H and K is the camera itself: centre and rotation rows.
                #expect(simd_length(calibration.pose.center - pose.position) < 1e-6)
                let rows = [reference.right, reference.down, reference.forward]
                for (row, truth) in zip(calibration.pose.rotationRows, rows) { #expect(simd_length(row - truth) < 1e-9) }
                // The handles are the four junctions of VISION.md §4.1, in the order 20, 6, 3, 11.
                let junctions = [SIMD2(26.59, 167.91), SIMD2(167.91, -26.59), SIMD2(-26.59, -167.91), SIMD2(-167.91, 26.59)]
                for (point, junction) in zip(calibration.handles.points, junctions) {
                    let expected = reference.project(SIMD3(junction.x, junction.y, 0))
                    // The printed junctions are rounded to 0.01 mm: about 0.03 px.
                    #expect(abs(point.x - expected.x) < 0.05 && abs(point.y - expected.y) < 0.05)
                }
                // G = H⁻¹ to 1e-9 mm on the board.
                for k in 0..<12 {
                    let a = Double(k) * .pi / 6
                    let board = SIMD2(150 * sin(a), 150 * cos(a))
                    let back = calibration.imageToBoard.apply(reference.project(SIMD3(board.x, board.y, 0)))
                    #expect(simd_length(back - board) < 1e-6)
                }
            }
        }
    }

    @Test func boardDimensions_areThoseOfDartCore() {
        let board = BoardGeometry.standard
        let radii = RingRadii.nominal
        #expect(radii.innerBull == board.innerBullRadius && radii.outerBull == board.outerBullRadius)
        #expect(radii.trebleInner == board.trebleInnerRadius && radii.trebleOuter == board.trebleOuterRadius)
        #expect(radii.doubleInner == board.doubleInnerRadius && radii.doubleOuter == board.doubleOuterRadius)
        #expect(BoardModel.numberRingRadius == board.boardRadius)
        #expect(SyntheticBoard.wireWidth == 1.4)
        // The colour model agrees with DartCore's scoring on a dense polar grid, away from the boundaries.
        var random = SeededRandom(seed: 0xB0A2_D001)
        for _ in 0..<20_000 {
            let r = Self.uniform(&random, 0...240), a = Self.uniform(&random, 0...(2 * .pi))
            let p = BoardPoint(x: r * sin(a), y: r * cos(a))
            let hit = board.hit(at: p)
            let surface = BoardModel.surface(at: p)
            let painted = SyntheticBoard(radii: .nominal).surface(x: p.x, y: p.y)
            #expect(SyntheticBoard.Paint(surface) == painted)
            if let expected = BoardModel.surface(of: hit, sectorIndex: board.sectorIndex(at: p)) {
                #expect(surface == expected, "\(p)")
            } else {
                #expect(surface == (r <= 225.5 ? .numberRing : .wall))
            }
        }
    }

    // MARK: Inputs that must never trap

    @Test func geometry_degenerateInputsNeverTrap() {
        let square = [SIMD2<Double>(0, 0), SIMD2(1, 0), SIMD2(1, 1), SIMD2(0, 1)]
        let degenerate: [[SIMD2<Double>]] = [
            [], [SIMD2(0, 0)], square.map { $0 * .nan }, [SIMD2(.infinity, 0), SIMD2(1, 0), SIMD2(1, 1), SIMD2(0, 1)],
            Array(repeating: SIMD2(3, 4), count: 4), [SIMD2(0, 0), SIMD2(1, 1), SIMD2(2, 2), SIMD2(3, 3)],
            [SIMD2(0, 0), SIMD2(1, 0), SIMD2(1, 0), SIMD2(0, 1)],
        ]
        for points in degenerate {
            #expect(Homography(from: points, to: points) == nil)
            #expect(Homography(from: square, to: points) == nil)
            #expect(Homography(from: points, to: square) == nil)
            #expect(Homography.unitSquare(to: points) == nil)
        }
        // Extreme but regular quadrilaterals: an answer or nil, never a trap, never a non-finite matrix.
        let extreme: [[SIMD2<Double>]] = [
            [SIMD2(1e300, 0), SIMD2(0, 1e300), SIMD2(-1e300, 0), SIMD2(0, -1e300)],
            [SIMD2(0, 0), SIMD2(1e-14, 0), SIMD2(1e-14, 1e-14), SIMD2(0, 1e-14)],
            [SIMD2(0, 0), SIMD2(1, 0), SIMD2(1, 1e-13), SIMD2(0, 1)],
        ]
        for points in extreme {
            for h in [Homography(from: square, to: points), Homography(from: points, to: square), Homography.unitSquare(to: points)] {
                if let h { #expect(h.isFinite && h.inverse != nil) }
            }
        }
        #expect(Homography(from: square, to: Array(square.prefix(3))) == nil)
        let zero = Homography(simd_double3x3(0))
        let nan = Homography(simd_double3x3(rows: [SIMD3(.nan, 0, 0), SIMD3(0, 1, 0), SIMD3(0, 0, 1)]))
        let rankOne = Homography(simd_double3x3(rows: [SIMD3(1, 2, 3), SIMD3(2, 4, 6), SIMD3(3, 6, 9)]))
        for h in [zero, nan, rankOne] {
            #expect(h.inverse == nil)
            _ = h.apply(SIMD2(1, 2))
            _ = h.jacobian(at: SIMD2(1, 2))
            _ = h.localScale(at: SIMD2(.nan, 2))
            _ = h.concatenating(h)
            #expect(CameraIntrinsics.selfCalibrated(boardToImage: h, imageSize: PixelSize(width: 0, height: 0)) == nil)
            #expect(CameraPose(boardToImage: h, intrinsics: .assumed(imageSize: PixelSize(width: 1920, height: 1080))) == nil)
        }
        // A point on the horizon of a perspective view.
        let view = SupportPoses.a.camera.boardToImage
        let horizon = SIMD2(0.0, -view.row2.z / view.row2.y)
        let atInfinity = view.apply(horizon)
        #expect(!atInfinity.x.isFinite || abs(atInfinity.x) > 1e9)
        _ = view.localScale(at: horizon)
        for fov in [0.0, 180, -10, .nan, .infinity] {
            _ = CameraIntrinsics(longSideFieldOfViewDegrees: fov, imageSize: PixelSize(width: 0, height: -5))
        }
        let zeroFocal = CameraIntrinsics(fx: 0, fy: 0, cx: 0, cy: 0, source: .sampleBuffer)
        #expect(CameraPose(boardToImage: view, intrinsics: zeroFocal) == nil)
        // Degenerate ring radii: the remap stays a function, finite for finite inputs.
        for radii in [RingRadii(innerBull: 0, outerBull: 0, trebleInner: 0, trebleOuter: 0, doubleInner: 0, doubleOuter: 0),
                      RingRadii(innerBull: 50, outerBull: 10, trebleInner: 99, trebleOuter: 99, doubleInner: 170, doubleOuter: 170),
                      RingRadii(innerBull: .nan, outerBull: 15.9, trebleInner: 99, trebleOuter: 107, doubleInner: 162, doubleOuter: 170)] {
            for p in [BoardPoint(x: 0, y: 0), BoardPoint(x: 3, y: 4), BoardPoint(x: 200, y: 1), BoardPoint(x: .nan, y: 1)] {
                _ = radii.toNominal(p)
                _ = radii.fromNominal(p)
            }
            _ = SyntheticBoard(radii: radii).paint(x: 10, y: 10)
        }
        #expect(BoardModel.sectorIndex(at: BoardPoint(x: .nan, y: 1)) == 0)
        #expect(BoardModel.surface(at: BoardPoint(x: .infinity, y: 0)) == .wall)
        // Cameras without a direction, without pixels or without a focal length.
        let cameras = [
            SyntheticCamera(imageSize: PixelSize(width: 64, height: 48), position: SIMD3(0, 0, 0)),
            SyntheticCamera(imageSize: PixelSize(width: 64, height: 48), position: SIMD3(.nan, 0, 1000)),
            SyntheticCamera(imageSize: PixelSize(width: 0, height: 0), position: SIMD3(0, -400, 1000)),
            SyntheticCamera(imageSize: PixelSize(width: 64, height: 48), longSideFieldOfViewDegrees: 0, position: SIMD3(0, -400, 1000)),
            SyntheticCamera(imageSize: PixelSize(width: 64, height: 48), position: SIMD3(0, 1000, 0), lookAt: BoardPoint(x: 0, y: 0)),
            SyntheticCamera(imageSize: PixelSize(width: 64, height: 48), position: SIMD3(0, 0, -1000)),
        ]
        for camera in cameras {
            _ = camera.boardToImage
            _ = camera.project(SIMD3(1, 2, 3))
            _ = camera.exactHandles()
            let calibration = camera.calibration(grade: .fair)
            let rectifier = BoardRectifier(calibration: calibration)
            _ = rectifier.imageRegionOfInterest
            let canvas = rectifier.rectify(RGBImage(width: camera.imageSize.width, height: camera.imageSize.height, fill: SIMD3(1, 2, 3)))
            #expect(canvas.rgb.width == BoardCanvas.side)
            _ = SupportScenes.exact().render(camera: camera)
            _ = camera.moved(by: SIMD3(.nan, 0, 0), rollDegrees: .infinity)
        }
    }
}
