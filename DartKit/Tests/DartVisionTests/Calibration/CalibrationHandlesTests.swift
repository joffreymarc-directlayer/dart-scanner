import Foundation
import simd
import Testing
import DartCore
@testable import DartVision

extension CalibrationTests {
    /// `CalibrationHandles`: projection, indexing, starting position, the gestures of the setup screen, rotation by
    /// sectors and the "touch the 20" re-orientation (VISION.md §4.3 L8, §4.4).
    @Suite struct CalibrationHandlesTests {
        private func distance(_ a: CalibrationHandles?, _ b: CalibrationHandles) -> Double {
            guard let a, a.points.count == b.points.count else { return .infinity }
            return zip(a.points, b.points).map { simd_length(SIMD2($0.x - $1.x, $0.y - $1.y)) }.max() ?? 0
        }

        @Test func projecting_equalsTheExactHandlesOfEveryPose() async {
            for camera in SupportPoses.cameras {
                await Task.yield()
                let projected = CalibrationHandles(projecting: camera.boardToImage)
                #expect(projected.points.count == 4)
                #expect(distance(projected, camera.exactHandles()) < 1e-6)
            }
        }

        @Test func subscript_readsAndMovesOneHandleInHandleOrder() async {
            let exact = SupportPoses.a.camera.exactHandles()
            var handles = exact
            for handle in CalibrationHandle.allCases {
                await Task.yield()
                #expect(handles[handle] == exact.points[handle.rawValue])
            }
            handles[.wire3_19] = ImagePoint(x: 1, y: 2)
            #expect(handles.points[2] == ImagePoint(x: 1, y: 2))
            #expect(handles.points[0] == exact.points[0] && handles.points[1] == exact.points[1] && handles.points[3] == exact.points[3])
            // Missing handles read as NaN and are padded on write, never out of range.
            var short = CalibrationHandles(points: [])
            #expect(short[.wire11_14].x.isNaN)
            short[.wire6_10] = ImagePoint(x: 5, y: 6)
            #expect(short.points.count == 2 && short.points[0].x.isNaN && short.points[1] == ImagePoint(x: 5, y: 6))
        }

        @Test func centredDefault_isAFrontalCircleThatPassesTheGate() async throws {
            let size = PixelSize(width: 1920, height: 1080)
            let handles = CalibrationHandles.centredDefault(in: size)
            let centre = SIMD2(959.5, 539.5)
            #expect(handles.points.count == 4)
            for (point, handle) in zip(handles.points, CalibrationHandle.allCases) {
                await Task.yield()
                let offset = SIMD2(point.x, point.y) - centre
                #expect(abs(simd_length(offset) - 0.3 * 1080) < 1e-9)
                // Same direction as the junction seen from the front: board +y is image −y.
                let expected = SIMD2(handle.boardPoint.x, -handle.boardPoint.y) / 170
                #expect(simd_length(offset / simd_length(offset) - expected) < 1e-12)
            }
            // A frontal view: it passes C1 and is flagged as too frontal.
            let preview = BoardCalibrator().preview(handles: handles, imageSize: size, rotationDegrees: 0, intrinsics: nil)
            let calibration = try preview.get()
            #expect(calibration.quality.issues.contains(.viewTooFrontal))
            #expect(abs(calibration.boardToImage.apply(SIMD2(0, 0)).x - 959.5) < 1e-9)
        }

        @Test func translatedAndScaledAndRotated_followTheGestures() async {
            let handles = SupportPoses.b.camera.exactHandles()
            let moved = handles.translated(dx: 12.5, dy: -3)
            for (a, b) in zip(moved.points, handles.points) {
                await Task.yield()
                #expect(a.x == b.x + 12.5 && a.y == b.y - 3)
            }
            let centre = ImagePoint(x: 900, y: 500)
            let doubled = handles.scaledAndRotated(about: centre, scale: 2, radians: 0)
            for (a, b) in zip(doubled.points, handles.points) {
                await Task.yield()
                #expect(abs(a.x - (900 + 2 * (b.x - 900))) < 1e-9 && abs(a.y - (500 + 2 * (b.y - 500))) < 1e-9)
            }
            // A quarter turn with a positive angle is clockwise on the screen: right of the centre goes below it.
            let probe = CalibrationHandles(points: [ImagePoint(x: 910, y: 500)])
            let turned = probe.scaledAndRotated(about: centre, scale: 1, radians: .pi / 2)
            #expect(abs(turned.points[0].x - 900) < 1e-9 && abs(turned.points[0].y - 510) < 1e-9)
            // The inverse gesture brings the handles back.
            let back = handles.scaledAndRotated(about: centre, scale: 1.7, radians: 0.4)
                .scaledAndRotated(about: centre, scale: 1 / 1.7, radians: -0.4)
            #expect(distance(back, handles) < 1e-9)
        }

        @Test func rotatedBySectors_turnsTheWireframeClockwise() async {
            let camera = SupportPoses.a.camera
            let exact = camera.exactHandles()
            for count in [-21, -3, -1, 1, 2, 7, 19] {
                await Task.yield()
                // H·Rot(18°·count): each handle lands on the image of its junction turned clockwise.
                let expected = CalibrationHandles(points: CalibrationHandle.allCases.map { handle in
                    let a = (9 + 90 * Double(handle.rawValue) + 18 * Double(count)) * .pi / 180
                    let p = camera.boardToImage.apply(SIMD2(170 * sin(a), 170 * cos(a)))
                    return ImagePoint(x: p.x, y: p.y)
                })
                #expect(distance(exact.rotated(bySectors: count), expected) < 1e-6)
            }
            #expect(distance(exact.rotated(bySectors: 20), exact) < 1e-6)
            #expect(distance(exact.rotated(bySectors: 0), exact) < 1e-9)
            #expect(distance(exact.rotated(bySectors: 3)?.rotated(bySectors: -3), exact) < 1e-6)
            // Degenerate handles.
            let line = CalibrationHandles(points: (0..<4).map { ImagePoint(x: Double($0) * 10, y: 5) })
            #expect(line.rotated(bySectors: 1) == nil)
            #expect(CalibrationHandles(points: Array(exact.points.prefix(3))).rotated(bySectors: 1) == nil)
        }

        @Test func reoriented_bringsTheTwentyUnderTheFinger() async {
            for camera in SupportPoses.cameras {
                await Task.yield()
                let exact = camera.exactHandles()
                // The finger touches the printed 20, in the number ring, or the 20 single.
                let fingers = [BoardPoint(x: 0, y: 198), BoardPoint(x: 3, y: 120), BoardPoint(x: -4, y: 60)]
                    .map { CalibrationFixtures.project(camera, $0) }
                for count in 1..<20 {
                    await Task.yield()
                    guard let wrong = exact.rotated(bySectors: count) else {
                        Issue.record("rotation failed")
                        continue
                    }
                    for finger in fingers {
                        await Task.yield()
                        #expect(distance(wrong.reoriented(twentyAt: finger, parityPreserving: false), exact) < 1e-6)
                        let kept = wrong.reoriented(twentyAt: finger, parityPreserving: true)
                        if count % 2 == 0 {
                            #expect(distance(kept, exact) < 1e-6)
                        } else {
                            // An odd rotation cannot be undone by multiples of 36 degrees: the best is one sector away.
                            let neighbours = [exact.rotated(bySectors: 1), exact.rotated(bySectors: -1)]
                            #expect(neighbours.contains { distance(kept, $0 ?? exact) < 1e-6 })
                        }
                    }
                }
                // Already right: nothing moves.
                #expect(distance(exact.reoriented(twentyAt: fingers[0], parityPreserving: true), exact) < 1e-6)
            }
            let exact = SupportPoses.a.camera.exactHandles()
            #expect(exact.reoriented(twentyAt: ImagePoint(x: .nan, y: 3), parityPreserving: false) == nil)
            let line = CalibrationHandles(points: (0..<4).map { ImagePoint(x: Double($0) * 10, y: 5) })
            #expect(line.reoriented(twentyAt: ImagePoint(x: 1, y: 1), parityPreserving: false) == nil)
        }
    }
}
