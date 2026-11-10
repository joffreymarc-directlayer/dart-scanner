import Foundation
import simd
import Testing
import DartCore
@testable import DartVision

/// Intrinsics, pose, parallax and the exact calibration of the synthetic camera (M4, M5, M6, M10, M12).
@Suite struct MathPoseTests {
    /// A camera at `degrees` off the board normal, looking at the bull from 0.9 to 1.5 m, on any side.
    private func camera(_ random: inout SupportRandom, degrees: Double,
                        imageSize: PixelSize = PixelSize(width: 1920, height: 1080), fieldOfView: Double = 67) -> SyntheticCamera {
        let distance = random.uniform(900...1500), azimuth = random.uniform(0...360)
        let tilt = degrees * .pi / 180, turn = azimuth * .pi / 180
        let position = SIMD3(distance * sin(tilt) * sin(turn), distance * sin(tilt) * cos(turn), distance * cos(tilt))
        return SyntheticCamera(imageSize: imageSize, longSideFieldOfViewDegrees: fieldOfView, position: position,
                               rollDegrees: random.uniform(-10...10))
    }

    // MARK: M4

    @Test func m4_opticalCentreFromExactHAndK() throws {
        var random = SupportRandom(seed: 0x4D34)
        var worst = 0.0
        for index in 0..<50 {
            let degrees = 5 + 40 * Double(index) / 49
            let camera = camera(&random, degrees: degrees)
            let pose = try #require(CameraPose(boardToImage: camera.boardToImage, intrinsics: camera.intrinsics))
            worst = max(worst, simd_distance(pose.center, camera.position))
            #expect(abs(pose.distance - camera.position.z) < 1e-6)
            #expect(abs(pose.footPoint.x - camera.position.x) < 1e-6 && abs(pose.footPoint.y - camera.position.y) < 1e-6)
            #expect(!pose.isApproximate)
            // The rotation rows are those of the camera: right, down, forward.
            let rows = camera.rotationRows
            #expect(simd_distance(pose.rotationRows[0], rows.right) < 1e-9)
            #expect(simd_distance(pose.rotationRows[1], rows.down) < 1e-9)
            #expect(simd_distance(pose.rotationRows[2], rows.forward) < 1e-9)
        }
        #expect(worst < 1e-6, "optical centre: \(worst) mm")
        // Any overall factor of H gives the same pose, a negative one included.
        let a = SupportPoses.a.camera
        for factor in [1e-6, -1.0, -3.5e4] {
            let scaled = Homography(a.boardToImage.matrix * factor)
            let pose = try #require(CameraPose(boardToImage: scaled, intrinsics: a.intrinsics))
            #expect(simd_distance(pose.center, a.position) < 1e-6)
        }
        // Mirrored handles: the centre comes out behind the board.
        let mirror = Homography(simd_double3x3(rows: [SIMD3(-1, 0, 0), SIMD3(0, 1, 0), SIMD3(0, 0, 1)]))
        #expect(CameraPose(boardToImage: a.boardToImage.concatenating(mirror), intrinsics: a.intrinsics) == nil)
        #expect(CameraPose(boardToImage: a.boardToImage, intrinsics: CameraIntrinsics(fx: 0, fy: 0, cx: 0, cy: 0, source: .assumed)) == nil)
        // The pose of an approximate intrinsic matrix is approximate.
        let assumed = CameraIntrinsics.assumed(imageSize: a.imageSize)
        #expect(CameraPose(boardToImage: a.boardToImage, intrinsics: assumed)?.isApproximate == true)
    }

    // MARK: M5

    @Test func m5_selfCalibratedFocal() throws {
        var random = SupportRandom(seed: 0x4D35)
        var worst = 0.0
        for index in 0..<60 {
            let degrees = 10 + 40 * Double(index) / 59
            let size = index % 2 == 0 ? PixelSize(width: 1920, height: 1080) : PixelSize(width: 2160, height: 3840)
            let camera = camera(&random, degrees: degrees, imageSize: size, fieldOfView: random.uniform(55...75))
            let found = try #require(CameraIntrinsics.selfCalibrated(boardToImage: camera.boardToImage, imageSize: size),
                                     "\(degrees) degrees")
            worst = max(worst, abs(found.fx - camera.intrinsics.fx) / camera.intrinsics.fx)
            #expect(found.fx == found.fy && found.source == .selfCalibrated && found.isApproximate)
            #expect(found.cx == Double(size.width - 1) / 2 && found.cy == Double(size.height - 1) / 2)
        }
        #expect(worst < 0.001, "relative focal error: \(worst)")
        // Between 3 and 10 degrees the estimate still exists, and is exact on exact data.
        for degrees in [3.2, 5, 8] {
            let camera = camera(&random, degrees: degrees)
            let found = try #require(CameraIntrinsics.selfCalibrated(boardToImage: camera.boardToImage, imageSize: camera.imageSize),
                                     "\(degrees) degrees")
            #expect(abs(found.fx - camera.intrinsics.fx) / camera.intrinsics.fx < 0.001)
        }
        // Under 3 degrees the view is too frontal: no estimate, the caller falls back to `assumed`.
        for degrees in [0.0, 0.5, 1, 2, 2.9] {
            let camera = camera(&random, degrees: degrees)
            #expect(CameraIntrinsics.selfCalibrated(boardToImage: camera.boardToImage, imageSize: camera.imageSize) == nil,
                    "\(degrees) degrees")
        }
        // A focal outside [0.5, 3] × the long side is refused.
        let narrow = camera(&random, degrees: 30, fieldOfView: 15)
        #expect(narrow.intrinsics.fx > 3 * 1920)
        #expect(CameraIntrinsics.selfCalibrated(boardToImage: narrow.boardToImage, imageSize: narrow.imageSize) == nil)
    }

    @Test func m5_fieldOfViewAndFallbackIntrinsics() {
        let size = PixelSize(width: 2160, height: 3840)
        let fromFormat = CameraIntrinsics(longSideFieldOfViewDegrees: 67, imageSize: size)
        // f = (max(W, H) / 2) / tan(fov / 2), on the long side even in portrait.
        #expect(abs(fromFormat.fx - 1920 / tan(33.5 * .pi / 180)) < 1e-9 && fromFormat.fy == fromFormat.fx)
        #expect(fromFormat.cx == 1079.5 && fromFormat.cy == 1919.5)
        #expect(fromFormat.source == .fieldOfView && !fromFormat.isApproximate)
        let assumed = CameraIntrinsics.assumed(imageSize: size)
        #expect(assumed.source == .assumed && assumed.isApproximate)
        #expect(abs(assumed.fx - fromFormat.fx) < 1e-9 && assumed.cx == fromFormat.cx && assumed.cy == fromFormat.cy)
        #expect(!CameraIntrinsics(fx: 1, fy: 1, cx: 0, cy: 0, source: .sampleBuffer).isApproximate)
        let k = fromFormat.matrix
        #expect(k[0][0] == fromFormat.fx && k[1][1] == fromFormat.fy && k[2][0] == fromFormat.cx && k[2][1] == fromFormat.cy)
        #expect(k[2][2] == 1 && k[0][1] == 0 && k[1][0] == 0 && k[0][2] == 0 && k[1][2] == 0)
    }

    // MARK: M6

    @Test func m6_parallaxAgainstTheProjection() throws {
        var random = SupportRandom(seed: 0x4D36)
        var worst = 0.0, worstInverse = 0.0
        var cameras = SupportPoses.cameras
        for _ in 0..<20 {
            cameras.append(random.camera(viewAngle: 5...45))
        }
        for camera in cameras {
            let h = camera.boardToImage
            let g = try #require(h.inverse)
            let pose = try #require(CameraPose(boardToImage: h, intrinsics: camera.intrinsics))
            for _ in 0..<40 {
                let x = random.boardPoint(maxRadius: 180)
                let height = random.uniform(-2...150)
                // A point at `height` above X, seen by the camera, read back on the board plane through G.
                let image = camera.project(SIMD3(x.x, x.y, height))
                let seen = g.apply(SIMD2(image.x, image.y))
                let predicted = pose.apparentPosition(of: x, height: height)
                worst = max(worst, simd_distance(seen, SIMD2(predicted.x, predicted.y)))
                let removed = pose.removingParallax(from: BoardPoint(x: seen.x, y: seen.y), height: height)
                worstInverse = max(worstInverse, hypot(removed.x - x.x, removed.y - x.y))
            }
        }
        #expect(worst < 1e-6, "apparent position: \(worst) mm")
        #expect(worstInverse < 1e-6, "removing the parallax: \(worstInverse) mm")
        // What is above the board is pushed away from the foot point; tan θ is the cost of a hidden millimetre.
        let pose = try #require(CameraPose(boardToImage: SupportPoses.a.camera.boardToImage, intrinsics: SupportPoses.a.camera.intrinsics))
        let point = BoardPoint(x: 0, y: 100)
        let lifted = pose.apparentPosition(of: point, height: 1)
        let foot = pose.footPoint
        #expect(hypot(lifted.x - foot.x, lifted.y - foot.y) > hypot(point.x - foot.x, point.y - foot.y))
        #expect(abs(hypot(lifted.x - point.x, lifted.y - point.y) - pose.tanObliquity(at: point) * pose.distance / (pose.distance - 1)) < 1e-9)
        #expect(abs(pose.tanObliquity(at: foot)) < 1e-12)
        #expect(pose.apparentPosition(of: point, height: 0) == point)
    }

    // MARK: M10

    @Test func m10_signsOfAPhysicalView() throws {
        var random = SupportRandom(seed: 0x4D3A)
        var cameras: [SyntheticCamera] = SupportPoses.cameras
        while cameras.count < 50 {
            cameras.append(random.camera(viewAngle: 0...50))
        }
        for camera in cameras {
            let handles = camera.exactHandles().points
            #expect(handles.count == 4)
            var lacet = 0.0
            for i in 0..<4 {
                let p = handles[i], q = handles[(i + 1) % 4]
                lacet += p.x * q.y - q.x * p.y
            }
            #expect(lacet > 0, "handle winding \(lacet) at \(camera.position)")
            let j = camera.boardToImage.jacobian(at: SIMD2(0, 0))
            #expect(simd_determinant(j) < 0, "Jacobian determinant at the bull, camera \(camera.position)")
        }
    }

    // MARK: M12

    @Test func m12_exactCalibration() throws {
        let expected: [CalibrationQuality.Grade: (rms: Double, refined: Bool, issues: [CalibrationIssue])] = [
            .good: (0.2, true, []), .fair: (0.5, true, []), .poor: (0.9, false, [.refinementRejected]),
        ]
        var random = SupportRandom(seed: 0x4D3C)
        for pose in SupportPoses.allCases {
            let camera = pose.camera
            for grade in [CalibrationQuality.Grade.good, .fair, .poor] {
                let calibration = camera.calibration(grade: grade)
                // Fields fixed by VISION.md §10.1.
                #expect(calibration.id == UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
                #expect(calibration.createdAt == Date(timeIntervalSinceReferenceDate: 0))
                #expect(calibration.imageSize == camera.imageSize && calibration.rotationDegrees == 0)
                #expect(calibration.intrinsics == camera.intrinsics)
                #expect(calibration.handles == camera.exactHandles() && calibration.userHandles == calibration.handles)
                #expect(calibration.boardToImage == camera.boardToImage)
                #expect(calibration.ringRadii == .nominal && calibration.wireHeight == 0)
                // Two calls give equal values.
                #expect(calibration == camera.calibration(grade: grade))
                #expect(grade == .good ? calibration == camera.calibration() : calibration != camera.calibration())

                // boardToImage against project, imageToBoard on projected points, pose against the position.
                var worstImage = 0.0, worstBoard = 0.0
                for _ in 0..<100 {
                    let p = random.boardPoint(maxRadius: 225)
                    let projected = camera.project(SIMD3(p.x, p.y, 0))
                    let mapped = calibration.boardToImage.apply(SIMD2(p.x, p.y))
                    worstImage = max(worstImage, hypot(mapped.x - projected.x, mapped.y - projected.y))
                    let back = calibration.imageToBoard.apply(SIMD2(projected.x, projected.y))
                    worstBoard = max(worstBoard, hypot(back.x - p.x, back.y - p.y))
                }
                #expect(worstImage < 1e-6, "\(pose) \(grade): boardToImage \(worstImage) px")
                #expect(worstBoard < 1e-6, "\(pose) \(grade): imageToBoard \(worstBoard) mm")
                #expect(simd_distance(calibration.pose.center, camera.position) < 1e-6)
                #expect(!calibration.pose.isApproximate)

                // Quality: the imposed grade, the values of the section, and the true geometry.
                let quality = calibration.quality
                let values = try #require(expected[grade])
                #expect(quality.grade == grade && quality.edgeResidualRMS == values.rms)
                #expect(quality.refinementApplied == values.refined && quality.issues == values.issues)
                #expect(quality.edgeInlierFraction == 1 && quality.measuredFraction == 1 && quality.maxHandleShift == 0)
                let foot = hypot(camera.position.x, camera.position.y), distance = camera.position.z
                #expect(abs(quality.viewAngleDegrees - atan(foot / distance) * 180 / .pi) < 1e-9)
                #expect(abs(quality.minTanObliquity - (foot - 170) / distance) < 1e-9)
                #expect(abs(quality.maxTanObliquity - (foot + 170) / distance) < 1e-9)
                var scale = camera.boardToImage.localScale(at: SIMD2(0, 0)).min
                for k in 0..<8 {
                    let angle = Double(k) * 45 * .pi / 180
                    scale = min(scale, camera.boardToImage.localScale(at: SIMD2(170 * sin(angle), 170 * cos(angle))).min)
                }
                #expect(abs(quality.minPixelsPerMillimetre - scale) < 1e-12)
            }
            // The handles are the projected junctions, read through `points` in `CalibrationHandle` order.
            let handles = camera.exactHandles().points
            for (index, handle) in CalibrationHandle.allCases.enumerated() {
                let projected = camera.project(SIMD3(handle.boardPoint.x, handle.boardPoint.y, 0))
                #expect(handles[index] == projected)
            }
        }
        // Pose A of VISION.md §10.2: 4K portrait, 2.1 to 2.5 px/mm over the board.
        let a = SupportPoses.a.camera.calibration()
        #expect(a.quality.minPixelsPerMillimetre > 2.0 && a.quality.minPixelsPerMillimetre < 2.5)
        #expect(abs(a.quality.viewAngleDegrees - 23.3) < 0.5, "pose A view angle \(a.quality.viewAngleDegrees)")
    }

    @Test func m12_movedCameraKeepsItsOrientation() throws {
        let a = SupportPoses.a.camera
        let moved = a.moved(by: SIMD3(3, -2, 1), rollDegrees: 0.5)
        #expect(moved.position == a.position + SIMD3(3, -2, 1) && moved.rollDegrees == a.rollDegrees + 0.5)
        #expect(moved.imageSize == a.imageSize && moved.intrinsics == a.intrinsics)
        let before = a.rotationRows, after = moved.moved(by: .zero, rollDegrees: -0.5).rotationRows
        #expect(simd_distance(before.forward, after.forward) < 1e-12 && simd_distance(before.right, after.right) < 1e-12)
        // A sideways move of `d` mm shifts the bull by about f·d / distance pixels.
        let shifted = a.moved(by: SIMD3(1, 0, 0), rollDegrees: 0)
        let p0 = a.project(SIMD3(0, 0, 0)), p1 = shifted.project(SIMD3(0, 0, 0))
        let expected = a.intrinsics.fx / simd_length(a.position)
        #expect(abs(hypot(p1.x - p0.x, p1.y - p0.y) - expected) / expected < 0.2)
        // A positive roll turns the camera clockwise as seen from behind it: the image turns anticlockwise, and the
        // 20, straight above the bull without roll, moves to the left.
        let level = SyntheticCamera(imageSize: PixelSize(width: 1920, height: 1080), position: SIMD3(0, -400, 1000))
        let rolled = SyntheticCamera(imageSize: PixelSize(width: 1920, height: 1080), position: SIMD3(0, -400, 1000), rollDegrees: 10)
        let bullLevel = level.project(SIMD3(0, 0, 0)), twentyLevel = level.project(SIMD3(0, 140, 0))
        let bullRolled = rolled.project(SIMD3(0, 0, 0)), twentyRolled = rolled.project(SIMD3(0, 140, 0))
        #expect(abs(twentyLevel.x - bullLevel.x) < 1e-9)
        #expect(twentyRolled.x < bullRolled.x - 10)
        let turn = atan2(-(twentyRolled.x - bullRolled.x), -(twentyRolled.y - bullRolled.y)) * 180 / .pi
        #expect(abs(turn - 10) < 1, "image turned by \(turn) degrees")
        // Nothing behind the camera has an image.
        let behind = a.project(SIMD3(0, 0, 2000))
        #expect(behind.x.isNaN && behind.y.isNaN)
    }
}
