import Foundation
import simd
import Testing
import DartCore
@testable import DartVision

/// Hard shadows, outside the model of D2, on rendered scenes (review RV2): new seeds, the four reference poses and
/// eight placements drawn within VISION.md §2.1, the lamp above the board on the side opposite to the camera.
///
/// Before the review, 5 of the 18 darts that came out high on the reference poses were wrong (by 2 to 43 mm, the
/// walk having followed the shadow of the point, or a piece of it, beyond the tip), and 1 of 10 on the placements;
/// T7 allowed them (3 % of all darts). A dart whose end is a hard shadow must not be high. 400 darts per scene in
/// release builds, 40 in debug builds.
@Suite(.serialized, .tags(.heavy)) struct DetectionReviewShadowTests {
    static let count = DetectionHarness.count(400, debug: 40)

    /// Placements of VISION.md §2.1: under the board 1.0 to 1.3 m from the wall, up to 30 cm aside, 40 to 60 cm below
    /// the centre (4K portrait); one in four on the side (4K landscape).
    static func placements(seed: UInt64, count: Int) -> [SyntheticCamera] {
        var random = SupportRandom(seed: seed)
        return (0..<count).map { _ in
            let side = random.unit() < 0.25
            let distance = random.uniform(1000...1300)
            if side {
                let x = (random.unit() < 0.5 ? -1.0 : 1.0) * random.uniform(400...600)
                return SyntheticCamera(imageSize: PixelSize(width: 3840, height: 2160), position: SIMD3(x, random.uniform(-200...0), distance))
            }
            return SyntheticCamera(imageSize: PixelSize(width: 2160, height: 3840),
                                   position: SIMD3(random.uniform(-300...300), -random.uniform(400...600), distance))
        }
    }

    /// The darts under a lamp above the board, on the side opposite to the camera, casting shadows of `strength`.
    static func scene(_ darts: [SyntheticDart], camera: SyntheticCamera, strength: Double, seed: UInt64) -> SyntheticScene {
        var scene = SyntheticScene()
        scene.darts = darts
        scene.seed = seed
        scene.light = SupportScenes.lampOpposite(to: camera)
        scene.shadowStrength = strength
        return scene
    }

    /// Detection and confidence of `count` darts of the probe's mix, spread over `cameras`, under a shadow of
    /// `strength`: (tier, right bed) for each.
    static func run(cameras: [SyntheticCamera], strength: Double, seed: UInt64) -> [(tier: ConfidenceTier, right: Bool)] {
        var random = SupportRandom(seed: seed)
        var results: [(tier: ConfidenceTier, right: Bool)] = []
        for (index, camera) in cameras.enumerated() {
            let reference = scene([], camera: camera, strength: strength, seed: seed &+ 7 &+ UInt64(index)).renderCanvas(camera: camera)
            let calibration = camera.calibration()
            let share = count / cameras.count
            let darts = (0..<share).map { _ in DetectionHarness.probeDart(&random) }
            results += ImagingParallel.map((0..<share).map { $0..<($0 + 1) }) { job -> (tier: ConfidenceTier, right: Bool) in
                let dart = darts[job.lowerBound]
                let current = scene([dart], camera: camera, strength: strength,
                                     seed: seed &+ UInt64(index * 100_000 + job.lowerBound + 11)).renderCanvas(camera: camera)
                let analysis = DifferencingDartDetector().analyse(DetectionRequest(current: current, reference: reference,
                                                                                   emptyReference: reference, knownDarts: [],
                                                                                   calibration: calibration, noiseSigma: 2))
                guard analysis.kind == .darts, let candidate = analysis.darts.first else { return (.low, false) }
                let observation = ConfidenceModel().observe(candidate, id: UUID(uuidString: "00000000-0000-0000-0000-0000000000B1") ?? UUID(),
                                                            visit: 0, indexInVisit: 0, timestamp: 0, source: .liveCamera,
                                                            calibration: calibration, context: ConfidenceContext())
                return (observation.tier, observation.best == BoardGeometry.standard.hit(at: dart.tip))
            }
        }
        return results
    }

    @Test func hardShadow_referencePoses_noHighAndWrong() {
        let results = Self.run(cameras: SupportPoses.cameras, strength: 0.20, seed: 7000)
        let highs = results.filter { $0.tier == .high }
        #expect(highs.allSatisfy { $0.right }, "\(highs.filter { !$0.right }.count) wrong of \(highs.count) high")
        #expect(results.filter { $0.tier == .low }.count >= results.count * 9 / 10)
    }

    @Test func hardShadow_placements_noHighAndWrong() {
        for (strength, seed) in [(0.20, UInt64(7001)), (0.30, UInt64(7002))] {
            let results = Self.run(cameras: Self.placements(seed: 4242, count: 8), strength: strength, seed: seed)
            let highs = results.filter { $0.tier == .high }
            #expect(highs.allSatisfy { $0.right }, "shadow \(strength): \(highs.filter { !$0.right }.count) wrong of \(highs.count) high")
        }
    }
}
