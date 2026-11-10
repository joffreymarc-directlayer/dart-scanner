import Foundation
import simd
import Testing
import DartCore
@testable import DartVision

extension CalibrationTests {
    /// The members of `BoardCalibration` (VISION.md §4.6 C6, §4.7, §9.2): nominal coordinates through the radial
    /// remap and the wire-height correction, their inverse, the tap test, the local scale and the wireframe.
    @Suite struct CalibrationModelTests {
        /// The exact calibration of `camera`, with other ring radii and a wire height.
        private func calibration(_ camera: SyntheticCamera, radii: RingRadii, wireHeight: Double) -> BoardCalibration {
            let exact = camera.calibration()
            return BoardCalibration(id: exact.id, createdAt: exact.createdAt, imageSize: exact.imageSize,
                                    rotationDegrees: 0, userHandles: exact.userHandles, handles: exact.handles,
                                    boardToImage: exact.boardToImage, imageToBoard: exact.imageToBoard, ringRadii: radii,
                                    wireHeight: wireHeight, intrinsics: exact.intrinsics, pose: exact.pose,
                                    quality: exact.quality)
        }

        private let oddRadii = RingRadii(innerBull: 6.8, outerBull: 15.2, trebleInner: 98, trebleOuter: 106.5,
                                         doubleInner: 161.2, doubleOuter: 170)

        @Test func boardPointAndImagePoint_areExactInverses() async {
            for camera in SupportPoses.cameras {
                await Task.yield()
                for (radii, height) in [(RingRadii.nominal, 0.0), (oddRadii, 0.0), (.nominal, 0.7), (oddRadii, 1.2)] {
                    await Task.yield()
                    let model = calibration(camera, radii: radii, wireHeight: height)
                    for point in CalibrationFixtures.boardPoints(count: 60, seed: 5) + [BoardPoint(x: 0, y: 0), BoardPoint(x: 0, y: 200)] {
                        await Task.yield()
                        let image = model.imagePoint(for: point)
                        let back = model.boardPoint(for: image)
                        #expect(abs(back.x - point.x) < 1e-9 && abs(back.y - point.y) < 1e-9)
                    }
                }
            }
        }

        @Test func boardPoint_appliesTheRadiiThenNothingElseWithoutWireHeight() async {
            let camera = SupportPoses.c.camera
            // Nominal radii and no wire height: the homography alone.
            let plain = calibration(camera, radii: .nominal, wireHeight: 0)
            let image = CalibrationFixtures.project(camera, BoardPoint(x: 40, y: -75))
            let board = plain.boardPoint(for: image)
            #expect(abs(board.x - 40) < 1e-9 && abs(board.y + 75) < 1e-9)
            // This board's treble is at 98 / 106.5 mm: its metric ring lands on the nominal ring.
            let odd = calibration(camera, radii: oddRadii, wireHeight: 0)
            let a = 33 * Double.pi / 180
            let onRing = odd.boardPoint(for: CalibrationFixtures.project(camera, BoardPoint(x: 98 * sin(a), y: 98 * cos(a))))
            #expect(abs((onRing.x * onRing.x + onRing.y * onRing.y).squareRoot() - 99) < 1e-9)
            #expect(abs(atan2(onRing.x, onRing.y) - a) < 1e-12)
        }

        @Test func hit_scoresTheSegmentUnderAnImagePoint() async {
            let board = BoardGeometry.standard
            for camera in SupportPoses.cameras {
                await Task.yield()
                let model = camera.calibration()
                let cases: [(BoardPoint, String)] = [
                    (BoardPoint(x: 0, y: 103), "T20"), (BoardPoint(x: 166, y: 0), "D6"), (BoardPoint(x: 0, y: -60), "S3"),
                    (BoardPoint(x: 0, y: 3), "DB"), (BoardPoint(x: 0, y: 12), "SB"), (BoardPoint(x: 0, y: 175), "MISS"),
                ]
                for (point, notation) in cases {
                    await Task.yield()
                    #expect(model.hit(at: CalibrationFixtures.project(camera, point), board: board).notation == notation)
                }
                // 0.1 mm on each side of the 20/1 wire, in the single.
                let a = 9 * Double.pi / 180
                let onWire = SIMD2(130 * sin(a), 130 * cos(a))
                let across = SIMD2(cos(a), -sin(a))
                let inOne = onWire + 0.1 * across, inTwenty = onWire - 0.1 * across
                #expect(model.hit(at: CalibrationFixtures.project(camera, BoardPoint(x: inOne.x, y: inOne.y)), board: board).notation == "S1")
                #expect(model.hit(at: CalibrationFixtures.project(camera, BoardPoint(x: inTwenty.x, y: inTwenty.y)), board: board).notation == "S20")
            }
        }

        @Test func localScale_matchesFiniteDifferencesOfImagePoint() async {
            for camera in [SupportPoses.a.camera, SupportPoses.d.camera] {
                await Task.yield()
                for (radii, height) in [(RingRadii.nominal, 0.0), (oddRadii, 0.9)] {
                    await Task.yield()
                    let model = calibration(camera, radii: radii, wireHeight: height)
                    for point in [BoardPoint(x: 0, y: 0), BoardPoint(x: 3, y: 4), BoardPoint(x: 50, y: -70),
                                  BoardPoint(x: -120, y: 40), BoardPoint(x: 0, y: 166), BoardPoint(x: 150, y: 150)] {
                        let h = 1e-4
                        func image(_ dx: Double, _ dy: Double) -> SIMD2<Double> {
                            let p = model.imagePoint(for: BoardPoint(x: point.x + dx, y: point.y + dy))
                            return SIMD2(p.x, p.y)
                        }
                        let column0 = (image(h, 0) - image(-h, 0)) / (2 * h)
                        let column1 = (image(0, h) - image(0, -h)) / (2 * h)
                        let numeric = BoardCalibration.singularValues(of: simd_double2x2(columns: (column0, column1)))
                        let scale = model.localScale(at: point)
                        #expect(abs(scale.min - numeric.min) / numeric.min < 1e-5)
                        #expect(abs(scale.max - numeric.max) / numeric.max < 1e-5)
                    }
                }
            }
            // Without radii or wire height it is the scale of H.
            let camera = SupportPoses.b.camera
            let exact = camera.calibration()
            let mine = exact.localScale(at: BoardPoint(x: 20, y: -90))
            let homography = camera.boardToImage.localScale(at: SIMD2(20, -90))
            #expect(abs(mine.min - homography.min) < 1e-12 && abs(mine.max - homography.max) < 1e-12)
        }

        @Test func wireframe_drawsTheBoardOnThePlaneOfTheWires() async {
            let camera = SupportPoses.a.camera
            let model = calibration(camera, radii: oddRadii, wireHeight: 0.7)
            let wireframe = model.wireframe(ringSegments: 72)
            let g = model.imageToBoard
            func board(_ p: ImagePoint) -> SIMD2<Double> { g.apply(SIMD2(p.x, p.y)) }
            #expect(wireframe.rings.count == 6)
            for (ring, radius) in zip(wireframe.rings, oddRadii.all) {
                await Task.yield()
                #expect(ring.count == 73 && ring.first == ring.last)
                for point in ring {
                    await Task.yield()
                    #expect(abs(simd_length(board(point)) - radius) < 1e-9)
                }
            }
            #expect(wireframe.wires.count == 20)
            for (index, wire) in wireframe.wires.enumerated() {
                await Task.yield()
                #expect(wire.count == 2)
                let a = (9 + 18 * Double(index)) * Double.pi / 180
                let inner = board(wire[0]), outer = board(wire[1])
                #expect(simd_length(inner - 15.2 * SIMD2(sin(a), cos(a))) < 1e-9)
                #expect(simd_length(outer - 170 * SIMD2(sin(a), cos(a))) < 1e-9)
            }
            #expect(wireframe.numberAnchors.map(\.number) == [20, 6, 3, 11])
            for (anchor, a) in zip(wireframe.numberAnchors, [0.0, 90, 180, 270]) {
                await Task.yield()
                let p = board(anchor.point)
                #expect(simd_length(p - 198 * SIMD2(sin(a * .pi / 180), cos(a * .pi / 180))) < 1e-9)
            }
            // The safe frame encloses the board and reaches the dart margin on the side away from the camera foot.
            let frame = wireframe.safeFrame.map(board)
            #expect(wireframe.safeFrame.count == 73 && wireframe.safeFrame.first == wireframe.safeFrame.last)
            #expect(frame.allSatisfy { simd_length($0) >= 170 - 1e-9 && simd_length($0) <= 305 + 1e-9 })
            let farthest = frame.max { simd_length($0) < simd_length($1) } ?? .zero
            #expect(simd_length(farthest) > 290 && farthest.y > 0)
            // At least a triangle.
            #expect(model.wireframe(ringSegments: 0).rings.allSatisfy { $0.count == 4 })
        }

        @Test func estimatedAccuracy_isTheResidualWithAFloor() async {
            var quality = SupportPoses.a.camera.calibration().quality
            quality.edgeResidualRMS = 0.12
            #expect(quality.estimatedAccuracy == 0.3)
            quality.edgeResidualRMS = 0.55
            #expect(quality.estimatedAccuracy == 0.55)
            quality.edgeResidualRMS = nil
            #expect(quality.estimatedAccuracy == 1)
        }
    }
}
