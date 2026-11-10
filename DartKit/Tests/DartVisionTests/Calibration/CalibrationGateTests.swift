import Foundation
import simd
import Testing
import DartCore
@testable import DartVision

extension CalibrationTests {
    /// C1 and C7 through `preview` (VISION.md §4.4, §4.7): the closed form, the sanity gate and its issues, the pose,
    /// and the identity of the result. Cases C5 (geometric part), C10 and C11.
    @Suite struct CalibrationGateTests {
        private let calibrator = BoardCalibrator()

        private func preview(_ handles: CalibrationHandles, _ camera: SyntheticCamera,
                             parameters: CalibrationParameters = .init()) -> Result<BoardCalibration, CalibrationError> {
            BoardCalibrator(parameters: parameters).preview(handles: handles, imageSize: camera.imageSize, rotationDegrees: 0,
                                                            intrinsics: camera.intrinsics)
        }

        private func blockingIssues(_ result: Result<BoardCalibration, CalibrationError>) -> [CalibrationIssue] {
            if case .failure(.rejected(let issues)) = result { return issues }
            return []
        }

        @Test func preview_isTheExactCalibrationOfExactHandles() async throws {
            for camera in SupportPoses.cameras {
                await Task.yield()
                let calibration = try preview(camera.exactHandles(), camera).get()
                let truth = camera.calibration()
                for point in CalibrationFixtures.boardPoints(count: 50) {
                    await Task.yield()
                    let p = SIMD2(point.x, point.y)
                    #expect(simd_length(calibration.boardToImage.apply(p) - truth.boardToImage.apply(p)) < 1e-6)
                }
                #expect(simd_length(calibration.pose.center - camera.position) < 1e-6)
                #expect(calibration.userHandles == camera.exactHandles() && calibration.handles == calibration.userHandles)
                #expect(calibration.ringRadii == .nominal && calibration.wireHeight == 0 && calibration.intrinsics == camera.intrinsics)
                let quality = calibration.quality
                #expect(quality.grade == .poor && !quality.refinementApplied && quality.maxHandleShift == 0)
                #expect(quality.edgeResidualRMS == nil && quality.edgeInlierFraction == nil && quality.measuredFraction == nil)
                #expect(abs(quality.minPixelsPerMillimetre - truth.quality.minPixelsPerMillimetre) < 1e-9)
                #expect(abs(quality.viewAngleDegrees - truth.quality.viewAngleDegrees) < 1e-6)
                #expect(abs(quality.minTanObliquity - truth.quality.minTanObliquity) < 1e-9)
                #expect(abs(quality.maxTanObliquity - truth.quality.maxTanObliquity) < 1e-9)
                #expect(quality.issues.allSatisfy { !$0.isBlocking && $0 != .refinementRejected && $0 != .edgesNotFound })
            }
        }

        @Test func preview_copiesTheWireHeightAndIsDeterministic() async throws {
            let camera = SupportPoses.a.camera
            var parameters = CalibrationParameters()
            parameters.wireHeight = 0.7
            let first = try preview(camera.exactHandles(), camera, parameters: parameters).get()
            let second = try preview(camera.exactHandles(), camera, parameters: parameters).get()
            #expect(first.wireHeight == 0.7)
            #expect(first == second && first.id == second.id)
            #expect(first.createdAt == Date(timeIntervalSinceReferenceDate: 0))
            let moved = try preview(camera.exactHandles().translated(dx: 1, dy: 0), camera, parameters: parameters).get()
            #expect(moved.id != first.id)
        }

        @Test func preview_withoutIntrinsicsSelfCalibratesOrAssumes() async throws {
            let camera = SupportPoses.a.camera
            let calibration = try calibrator.preview(handles: camera.exactHandles(), imageSize: camera.imageSize,
                                                     rotationDegrees: 90, intrinsics: nil).get()
            #expect(calibration.intrinsics.source == .selfCalibrated)
            #expect(abs(calibration.intrinsics.fx - camera.intrinsics.fx) / camera.intrinsics.fx < 1e-6)
            #expect(calibration.quality.issues.contains(.intrinsicsApproximate) && calibration.pose.isApproximate)
            #expect(calibration.rotationDegrees == 90)
            // A frontal view cannot be self-calibrated: the 67 degree fallback.
            let frontal = SyntheticCamera(imageSize: PixelSize(width: 2160, height: 3840), position: SIMD3(0, 0, 1100))
            let assumed = try calibrator.preview(handles: frontal.exactHandles(), imageSize: frontal.imageSize,
                                                 rotationDegrees: 0, intrinsics: nil).get()
            #expect(assumed.intrinsics.source == .assumed && assumed.quality.issues.contains(.intrinsicsApproximate))
        }

        @Test func c10_alignedOrCoincidentHandlesAreDegenerate() async {
            let camera = SupportPoses.a.camera
            let exact = camera.exactHandles().points
            let still = RGBImage(width: camera.imageSize.width, height: camera.imageSize.height, fill: SIMD3(120, 120, 125))
            let cases: [[ImagePoint]] = [
                (0..<4).map { ImagePoint(x: 100 + 50 * Double($0), y: 200 + 20 * Double($0)) },   // four on a line
                [exact[0], exact[1], exact[2], ImagePoint(x: 2 * exact[2].x - exact[1].x, y: 2 * exact[2].y - exact[1].y)],
                [exact[0], exact[1], exact[1], exact[3]],                                            // two coincide
                [exact[0], exact[0], exact[0], exact[0]],
                Array(exact.prefix(3)),
                exact + [exact[0]],
                [exact[0], exact[1], ImagePoint(x: .nan, y: 3), exact[3]],
            ]
            for points in cases {
                await Task.yield()
                let handles = CalibrationHandles(points: points)
                #expect(preview(handles, camera) == .failure(.degenerateHandles))
                let full = calibrator.calibrate(handles: handles, still: still, rotationDegrees: 0, intrinsics: camera.intrinsics)
                #expect(full == .failure(.degenerateHandles))
            }
        }

        @Test func c11_reversedHandlesAreMirrored() async {
            for camera in SupportPoses.cameras {
                await Task.yield()
                let exact = camera.exactHandles().points
                let reversed = CalibrationHandles(points: [exact[0], exact[3], exact[2], exact[1]])
                let issues = blockingIssues(preview(reversed, camera))
                #expect(issues.contains(.handlesMirrored))
                #expect(issues.allSatisfy { $0.isBlocking })
            }
        }

        @Test func c5_blockingAndAdvisoryIssuesOfThePlacement() async throws {
            // Board out of frame: the camera looks below the board, whose top leaves the image.
            let beside = SyntheticCamera(imageSize: PixelSize(width: 1920, height: 1080), position: SIMD3(0, -400, 1000),
                                         lookAt: BoardPoint(x: 0, y: -330))
            #expect(blockingIssues(preview(beside.exactHandles(), beside)) == [.boardOutOfFrame])

            // 0.7 px/mm: a small sensor far away.
            let far = CalibrationFixtures.camera(pixelsPerMillimetre: 0.75, viewAngle: 20,
                                                 imageSize: PixelSize(width: 1080, height: 1920))
            #expect(blockingIssues(preview(far.exactHandles(), far)) == [.resolutionTooLow])
            let farTruth = far.calibration().quality.minPixelsPerMillimetre
            #expect(farTruth > 0.6 && farTruth < 0.8)

            // A frontal view passes with an advisory.
            let frontal = SyntheticCamera(imageSize: PixelSize(width: 2160, height: 3840), position: SIMD3(0, 0, 1100))
            let frontalQuality = try preview(frontal.exactHandles(), frontal).get().quality
            #expect(frontalQuality.issues.contains(.viewTooFrontal) && frontalQuality.minTanObliquity < 0.21)

            // A very oblique view.
            let oblique = CalibrationFixtures.camera(pixelsPerMillimetre: 2, viewAngle: 50)
            let obliqueQuality = try preview(oblique.exactHandles(), oblique).get().quality
            #expect(obliqueQuality.issues.contains(.viewTooOblique) && obliqueQuality.maxTanObliquity > 0.84)

            // 1.3 px/mm: allowed, with an advisory.
            let low = CalibrationFixtures.camera(pixelsPerMillimetre: 1.45, viewAngle: 20)
            let lowQuality = try preview(low.exactHandles(), low).get().quality
            #expect(lowQuality.minPixelsPerMillimetre < 1.5 && lowQuality.minPixelsPerMillimetre >= 0.8)
            #expect(lowQuality.issues.contains(.resolutionLow))

            // The reference poses frame the board and its dart margin.
            for camera in [SupportPoses.a.camera, SupportPoses.c.camera, SupportPoses.d.camera] {
                await Task.yield()
                let quality = try preview(camera.exactHandles(), camera).get().quality
                #expect(quality.issues.isEmpty)
            }

            // An empty image frames nothing.
            let empty = calibrator.preview(handles: SupportPoses.a.camera.exactHandles(), imageSize: PixelSize(width: 0, height: 0),
                                           rotationDegrees: 0, intrinsics: nil)
            #expect(blockingIssues(empty).contains(.boardOutOfFrame))

            // Mirrored and crossed handles.
            let exact = SupportPoses.a.camera.exactHandles().points
            let crossed = CalibrationHandles(points: [exact[0], exact[2], exact[1], exact[3]])
            #expect(blockingIssues(preview(crossed, SupportPoses.a.camera)).contains(.quadNotConvex))
        }

        @Test func c5_dartMarginCutOffWhenTheFrameIsTightAboveTheBoard() async throws {
            // Camera under the board, close and aimed below the bull: the board is in the frame, the margin above it is not.
            let camera = SyntheticCamera(imageSize: PixelSize(width: 2160, height: 3840), position: SIMD3(0, -400, 700),
                                         lookAt: BoardPoint(x: 0, y: -300))
            let calibration = try preview(camera.exactHandles(), camera).get()
            let zone = CalibrationDartZone(footPoint: calibration.pose.footPoint, margin: 135)
            let visible = CalibrationGate.visibleFraction(of: zone, transform: calibration.boardToImage, imageSize: camera.imageSize)
            #expect(visible < 0.9 && visible > 0.5)
            #expect(calibration.quality.issues == [.dartMarginCutOff])
            #expect(CalibrationGate.discIsInside(calibration.boardToImage, radius: 180, imageSize: camera.imageSize))
        }

        @Test func horizonAcrossTheBoardIsBlocking() async {
            // A plane whose horizon is the line x = 200 mm of the board: w = 1 − x / 200 vanishes inside r = 230,
            // while the four junctions (|x| ≤ 168) stay in front of it.
            let transform = Homography(simd_double3x3(rows: [SIMD3(2, 0, 900), SIMD3(0, -2, 600), SIMD3(-1.0 / 200, 0, 1)]))
            let handles = CalibrationHandles(projecting: transform)
            let result = calibrator.preview(handles: handles, imageSize: PixelSize(width: 1920, height: 1080),
                                            rotationDegrees: 0, intrinsics: nil)
            let issues = blockingIssues(result)
            #expect(issues.contains(.horizonCrossesBoard) && issues.contains(.boardOutOfFrame))
            #expect(!issues.contains(.handlesMirrored) && !issues.contains(.quadNotConvex))
        }

        @Test func issues_followTheDeclarationOrder() async {
            let shuffled: [CalibrationIssue] = [.intrinsicsApproximate, .sectorPhaseMismatch, .resolutionLow, .boardOutOfFrame,
                                                .handlesMirrored, .resolutionLow, .refinementRejected, .edgesNotFound]
            #expect(CalibrationGate.ordered(shuffled) == [.handlesMirrored, .boardOutOfFrame, .resolutionLow,
                                                          .sectorPhaseMismatch, .edgesNotFound, .refinementRejected,
                                                          .intrinsicsApproximate])
        }

        @Test func discIsInside_isExact() async {
            let camera = SupportPoses.b.camera
            let h = camera.boardToImage
            // The extreme x and y of the circle r = 180, found by dense sampling, against the analytic answer.
            var minimum = SIMD2(Double.infinity, Double.infinity), maximum = -minimum
            for k in 0..<20_000 {
                await Task.yield()
                let a = 2 * Double.pi * Double(k) / 20_000
                let p = h.apply(SIMD2(180 * sin(a), 180 * cos(a)))
                minimum = simd_min(minimum, p)
                maximum = simd_max(maximum, p)
            }
            let inside = minimum.x >= -0.5 && minimum.y >= -0.5 && maximum.x <= 1919.5 && maximum.y <= 1079.5
            #expect(CalibrationGate.discIsInside(h, radius: 180, imageSize: camera.imageSize) == inside)
            // Just fitting and just not fitting.
            let shift = SIMD2(-(minimum.x + 0.5) + 0.01, -(minimum.y + 0.5) + 0.01)
            let far = maximum + shift
            let width = Int((far.x + 0.5).rounded(.up)) + 1, height = Int((far.y + 0.5).rounded(.up)) + 1
            let moved = CalibrationFixtures.shifted(h, by: shift)
            #expect(CalibrationGate.discIsInside(moved, radius: 180, imageSize: PixelSize(width: width, height: height)))
            let tight = CalibrationFixtures.shifted(h, by: shift - SIMD2(0.02, 0))
            #expect(!CalibrationGate.discIsInside(tight, radius: 180, imageSize: PixelSize(width: width, height: height)))
        }
    }
}
