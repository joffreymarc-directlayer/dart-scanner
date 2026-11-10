import Foundation
import simd
import Testing
import DartCore
@testable import DartVision

/// Scoring from stills with `PhotoScorer` (VISION.md §8.2, §8.3): tests P3 and P4 of §10.2. Every calibration comes
/// from `SyntheticCamera.calibration(grade:)`.
@Suite struct PhotoScorerTests {
    private let scorer = PhotoScorer()

    /// Board points 0.1 mm on each side of every radial wire and every ring, at several radii and angles.
    private static func boundaryPoints() -> [BoardPoint] {
        var points: [BoardPoint] = []
        for wire in 0..<20 {
            let angle = BoardModel.wireAngleDegrees(wire) * .pi / 180
            for radius in [20.0, 60.0, 103.0, 140.0, 166.0] {
                let shift = 0.1 / radius
                for side in [-1.0, 1.0] {
                    let a = angle + side * shift
                    points.append(BoardPoint(x: radius * sin(a), y: radius * cos(a)))
                }
            }
        }
        let radii = RingRadii.nominal
        for ring in [radii.innerBull, radii.outerBull, radii.trebleInner, radii.trebleOuter, radii.doubleInner, radii.doubleOuter] {
            for step in 0..<20 {
                // Halfway between two wires, so that only the ring changes across the pair.
                let angle = (18 * Double(step)) * .pi / 180
                for offset in [-0.1, 0.1] {
                    points.append(BoardPoint(x: (ring + offset) * sin(angle), y: (ring + offset) * cos(angle)))
                }
            }
        }
        return points
    }

    // MARK: P3

    /// P3: tapping the tips on the photo gives the exact hit, including 0.1 mm on each side of every wire and ring,
    /// for the four reference poses; the observation is certain and comes from the player.
    @Test func p3_tappedTipsAreExact() {
        let points = Self.boundaryPoints()
        for pose in SupportPoses.allCases {
            let camera = pose.camera
            for grade in [CalibrationQuality.Grade.good, .poor] {
                let calibration = camera.calibration(grade: grade)
                for (index, point) in points.enumerated() {
                    let image = camera.project(SIMD3(point.x, point.y, 0))
                    let seen = scorer.observation(forTappedTip: image, calibration: calibration, visit: 2, indexInVisit: index % 3)
                    let expected = BoardGeometry.standard.hit(at: point)
                    #expect(seen.best == expected, "pose \(pose) point \(point): \(seen.best) instead of \(expected)")
                    #expect(seen.confidence == 1 && seen.tier == .high && seen.source == .tappedOnPhoto)
                    #expect(hypot(seen.tip.x - point.x, seen.tip.y - point.y) < 1e-6)
                    #expect(seen.visit == 2 && seen.indexInVisit == index % 3)
                }
            }
        }
        // The pairs really straddle the boundaries: neighbours in the list are different beds.
        let hits = points.map(BoardGeometry.standard.hit(at:))
        #expect(stride(from: 0, to: hits.count, by: 2).allSatisfy { hits[$0] != hits[$0 + 1] })
    }

    /// The tapped tip goes through the stored fields of the calibration only: G, the wire-height correction and the
    /// radial stretch of this board (here a treble ring at 98 to 106.5 mm and wires 0.7 mm high).
    @Test func tappedTip_usesRadiiAndWireHeight() {
        let camera = SupportPoses.a.camera
        let exact = camera.calibration()
        let radii = RingRadii(innerBull: 6.35, outerBull: 15.9, trebleInner: 98, trebleOuter: 106.5, doubleInner: 162, doubleOuter: 170)
        let calibration = BoardCalibration(id: exact.id, createdAt: exact.createdAt, imageSize: exact.imageSize,
                                           rotationDegrees: 0, userHandles: exact.userHandles, handles: exact.handles,
                                           boardToImage: exact.boardToImage, imageToBoard: exact.imageToBoard, ringRadii: radii,
                                           wireHeight: 0.7, intrinsics: exact.intrinsics, pose: exact.pose, quality: exact.quality)
        // A sisal point at 98.4 mm is in the treble of this board, although it would be a single on a nominal one.
        let sisal = BoardPoint(x: 0, y: 98.4)
        let apparent = calibration.pose.apparentPosition(of: sisal, height: -0.7)
        let image = camera.project(SIMD3(apparent.x, apparent.y, 0))
        let seen = scorer.observation(forTappedTip: image, calibration: calibration, visit: 0, indexInVisit: 0)
        #expect(seen.best == .treble(20))
        let expected = radii.toNominal(sisal)
        #expect(hypot(seen.tip.x - expected.x, seen.tip.y - expected.y) < 1e-6)
    }

    /// Same tap, same observation (identifiers included); another tap, another identifier.
    @Test func tappedTip_isDeterministic() {
        let camera = SupportPoses.b.camera
        let calibration = camera.calibration()
        let image = camera.project(SIMD3(10, 50, 0))
        let first = scorer.observation(forTappedTip: image, calibration: calibration, visit: 1, indexInVisit: 0)
        let again = scorer.observation(forTappedTip: image, calibration: calibration, visit: 1, indexInVisit: 0)
        let next = scorer.observation(forTappedTip: image, calibration: calibration, visit: 1, indexInVisit: 1)
        #expect(first == again)
        #expect(first.id != next.id)
    }

    @Test func rectified_isTheRectifiersCanvas() {
        let camera = SupportPoses.b.camera
        let calibration = camera.calibration()
        let photo = SupportScenes.empty(seed: 5).render(camera: camera)
        let canvas = scorer.rectified(photo, calibration: calibration)
        let direct = BoardRectifier(calibration: calibration).rectify(photo)
        #expect(canvas.rgb == direct.rgb && canvas.valid == direct.valid)
        // No dart to find, and nothing for zero darts.
        #expect(scorer.score(photo: photo, calibration: calibration, emptyReference: canvas).isEmpty)
        #expect(scorer.score(photo: photo, calibration: calibration, emptyReference: canvas, maxDarts: 0).isEmpty)
    }

    // MARK: P4

    /// The second viewpoint of P4, "une pose à 15° et 0,2 m de là": a hand-held photo taken 0.2 m to the side of
    /// pose A, turned by 15 degrees (roll), aimed at the bull. Its view angle (22 degrees) stays in the placement
    /// range of VISION.md §2.1. Read as "15 degrees off the board normal" instead, the camera is more frontal than
    /// §2.1 allows, and darts near its foot point are seen end-on (reported to the integrator).
    static func secondViewpoint(of first: SyntheticCamera) -> SyntheticCamera {
        SyntheticCamera(imageSize: first.imageSize, position: first.position + SIMD3(-200, 0, 0), rollDegrees: 15)
    }

    /// P4 (optional layer): the empty board photographed from pose A, three darts photographed from a viewpoint turned
    /// by 15 degrees and 0.2 m away; each photo calibrated on its own. p95 of the tip error ≤ 2.5 mm, and no
    /// dart above the medium tier.
    @Test(.tags(.heavy)) func p4_photoPair() {
        let first = SupportPoses.a.camera
        let second = Self.secondViewpoint(of: first)
        let separation = simd_length(second.position - first.position)
        #expect(separation > 190 && separation < 210, "viewpoints \(separation) mm apart")
        let firstCalibration = first.calibration()
        let secondCalibration = second.calibration()
        let empty = scorer.rectified(SupportScenes.empty(seed: 1).render(camera: first), calibration: firstCalibration)
        var random = SupportRandom(seed: 2024)
        var errors: [Double] = []
        var found = 0, expected = 0
        for photo in 0..<DetectionHarness.count(8, debug: 2) {
            // Three darts in three separate thirds of the board.
            let base = random.uniform(0...120)
            let darts = (0..<3).map { index -> SyntheticDart in
                let angle = (base + 120 * Double(index) + random.uniform(-25...25)) * .pi / 180
                let radius = random.uniform(30...150)
                var dart = DetectionHarness.probeDart(&random)
                dart.style = index == 1 ? .brass : .steelTungsten
                dart.tip = BoardPoint(x: radius * sin(angle), y: radius * cos(angle))
                return dart
            }
            expected += darts.count
            let image = SupportScenes.darts(darts, seed: UInt64(100 + photo)).render(camera: second)
            let seen = scorer.score(photo: image, calibration: secondCalibration, emptyReference: empty)
            found += seen.count
            for observation in seen {
                #expect(observation.tier <= .medium, "photo \(photo): \(observation.tier)")
                #expect(observation.flags.contains(.crossViewpoint) && observation.flags.contains(.multiDartStill))
                #expect(observation.source == .handheldPhoto && observation.confidence <= 0.80)
                let nearest = darts.map { hypot($0.tip.x - observation.tip.x, $0.tip.y - observation.tip.y) }.min() ?? .infinity
                errors.append(nearest)
            }
        }
        #expect(found == expected, "\(found) darts found of \(expected)")
        let p95 = DetectionHarness.quantile(errors, 0.95) ?? .infinity
        #expect(p95 <= 2.5, "p95 \(p95) mm over \(errors.count) darts")
    }
}
