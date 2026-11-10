import Foundation
import simd
import DartCore
@testable import DartVision

/// Synthetic trials of the detection chain in the canvas (lot V3): one dart rendered on a board, the differencing
/// detector against a reference canvas, then the confidence model. Shared by the T, F and P suites.
enum DetectionHarness {
    /// One dart, end to end.
    struct Trial: Sendable {
        var pose: SupportPoses
        var dart: SyntheticDart
        var analysis: SceneAnalysis
        /// The first candidate, when the scene was read as darts.
        var candidate: DartCandidate?
        var observation: DartObservation?

        /// Ground truth.
        var truthHit: Hit { BoardGeometry.standard.hit(at: dart.tip) }
        /// Distance from the detected tip to the true entry point, mm; infinite without a candidate.
        var error: Double {
            guard let tip = candidate?.tip else { return .infinity }
            return hypot(tip.x - dart.tip.x, tip.y - dart.tip.y)
        }
        /// Error along the apparent dart axis, positive beyond the true tip (away from the flight).
        func alongError(camera: SyntheticCamera) -> Double? {
            guard let tip = candidate?.tip else { return nil }
            let towardsTip = -DetectionHarness.apparentAxis(of: dart, camera: camera)
            return (tip.x - dart.tip.x) * towardsTip.x + (tip.y - dart.tip.y) * towardsTip.y
        }
        var isCorrect: Bool { observation?.best == truthHit }
        var tier: ConfidenceTier { observation?.tier ?? .low }
        /// The detected tip end is the true one: the candidate's axis points the same way as the apparent dart.
        func hasCorrectEnd(camera: SyntheticCamera) -> Bool {
            guard let axis = candidate?.axis else { return false }
            return simd_dot(axis, DetectionHarness.apparentAxis(of: dart, camera: camera)) > 0
        }
    }

    /// Unit vector, in the board plane, from the tip of `dart` towards its flight as the camera sees it.
    static func apparentAxis(of dart: SyntheticDart, camera: SyntheticCamera) -> SIMD2<Double> {
        let top = SIMD3(dart.tip.x, dart.tip.y, 0) + dart.axis * 60
        let c = camera.position
        let k = c.z / (c.z - top.z)
        let apparent = SIMD2(c.x + (top.x - c.x) * k, c.y + (top.y - c.y) * k)
        let direction = apparent - SIMD2(dart.tip.x, dart.tip.y)
        let length = simd_length(direction)
        return length > 0 ? direction / length : SIMD2(0, 1)
    }

    /// Distance from a point to the nearest wire or ring boundary of the nominal board, mm.
    static func distanceToBoundary(_ point: BoardPoint) -> Double {
        let r = hypot(point.x, point.y)
        let radii = RingRadii.nominal
        var nearest = Double.infinity
        for radius in [radii.innerBull, radii.outerBull, radii.trebleInner, radii.trebleOuter, radii.doubleInner, radii.doubleOuter] {
            nearest = min(nearest, abs(r - radius))
        }
        if r > radii.outerBull {
            for wire in 0..<20 {
                // Distance to the half-line of the wire from the centre.
                let direction = BoardModel.wireDirection(wire)
                let along = point.x * direction.x + point.y * direction.y
                if along > 0 { nearest = min(nearest, abs(BoardModel.signedDistanceToWire(wire, point))) }
            }
        }
        return nearest
    }

    /// A scene description used to render the reference and the current canvases.
    struct Setup: Sendable {
        var noiseSigma: Double = 2
        var blurPasses: Int = 1
        var shadowStrength: Double = 1
        var lampOpposite = false
        var gain: Double = 1
        var grade: CalibrationQuality.Grade = .good
        var parameters = DetectionParameters()
    }

    static func scene(_ setup: Setup, camera: SyntheticCamera, darts: [SyntheticDart], seed: UInt64) -> SyntheticScene {
        var scene = SyntheticScene()
        scene.darts = darts
        scene.noiseSigma = setup.noiseSigma
        scene.blurPasses = setup.blurPasses
        scene.seed = seed
        if setup.shadowStrength < 1 {
            scene.light = SupportScenes.lampOpposite(to: camera)
            scene.shadowStrength = setup.shadowStrength
        }
        return scene
    }

    /// Renders the empty board (reference) for a camera.
    static func reference(_ setup: Setup, camera: SyntheticCamera, seed: UInt64) -> CanvasImage {
        scene(setup, camera: camera, darts: [], seed: seed).renderCanvas(camera: camera)
    }

    /// Runs one dart on top of `known` darts already in the reference.
    static func trial(_ setup: Setup, pose: SupportPoses, camera: SyntheticCamera, reference: CanvasImage,
                      emptyReference: CanvasImage?, known: [KnownDart] = [], knownDarts: [SyntheticDart] = [],
                      dart: SyntheticDart, seed: UInt64, model: ConfidenceModel = ConfidenceModel()) -> Trial {
        let current = scene(setup, camera: camera, darts: knownDarts + [dart], seed: seed).renderCanvas(camera: camera)
        let calibration = camera.calibration(grade: setup.grade)
        let request = DetectionRequest(current: current, reference: reference, emptyReference: emptyReference, knownDarts: known,
                                       calibration: calibration, noiseSigma: setup.noiseSigma, parameters: setup.parameters)
        let analysis = DifferencingDartDetector().analyse(request)
        let candidate = analysis.kind == .darts ? analysis.darts.first : nil
        let observation = candidate.map {
            model.observe($0, id: UUID(uuidString: "00000000-0000-0000-0000-000000000099") ?? UUID(), visit: 1, indexInVisit: 0,
                          timestamp: 0, source: .liveCamera, calibration: calibration, context: ConfidenceContext())
        }
        return Trial(pose: pose, dart: dart, analysis: analysis, candidate: candidate, observation: observation)
    }

    /// `count` random darts spread evenly over the four poses, each against a fresh empty reference per pose.
    /// `makeDart` draws one dart. The darts are drawn in order from the seeded stream, then the trials run
    /// concurrently; the result, in order, does not depend on the number of cores.
    static func batch(_ setup: Setup, count: Int, seed: UInt64,
                      makeDart: (inout SupportRandom) -> SyntheticDart) -> [Trial] {
        var random = SupportRandom(seed: seed)
        var trials: [Trial] = []
        let poses = SupportPoses.allCases
        for (poseIndex, pose) in poses.enumerated() {
            let camera = pose.camera
            let reference = DetectionHarness.reference(setup, camera: camera, seed: seed &+ 1000 &+ UInt64(poseIndex))
            let share = count / poses.count + (poseIndex < count % poses.count ? 1 : 0)
            let darts = (0..<share).map { _ in makeDart(&random) }
            let jobs = (0..<share).map { $0..<($0 + 1) }
            trials += ImagingParallel.map(jobs) { job in
                let index = job.lowerBound
                return trial(setup, pose: pose, camera: camera, reference: reference, emptyReference: reference,
                             dart: darts[index], seed: seed &+ UInt64(poseIndex * 100_000 + index + 1))
            }
        }
        return trials
    }

    /// Value at `fraction` (0...1) of the sorted finite values; nil when there are none.
    static func quantile(_ values: [Double], _ fraction: Double) -> Double? {
        let sorted = values.filter { $0.isFinite }.sorted()
        guard !sorted.isEmpty else { return nil }
        let position = min(sorted.count - 1, max(0, Int((fraction * Double(sorted.count - 1)).rounded())))
        return sorted[position]
    }

    /// Number of trials for a heavy statistic: the documented count in release builds, fewer in debug builds.
    static func count(_ release: Int, debug: Int) -> Int {
        #if DEBUG
        return debug
        #else
        return release
        #endif
    }

    /// True when the true tip of `dart` is an all-black point on a black surface: invisible by design (E3, T1).
    static func tipInvisible(_ dart: SyntheticDart) -> Bool {
        guard dart.style == .allBlack else { return false }
        let surface = BoardModel.surface(at: dart.tip)
        return surface == .black || surface == .numberRing
    }

    /// A dart of the probe's mix (VISION.md §5.4: "3 couleurs de fût, 20 % de pointes noires"): tip uniform over the
    /// board, tail up by 0 to 18 degrees, sideways lean within ±6 degrees; 40 % steel, 40 % brass, 20 % all black
    /// (black point, barrel and shaft), so that the black points come with black barrels. Read with the point colour
    /// drawn apart from the barrel (a black point on a steel or brass barrel), the bed is right for 70 to 77 % of
    /// black points only, never at the high tier: reported, not tested.
    static func probeDart(_ random: inout SupportRandom) -> SyntheticDart {
        let pick = random.unit()
        let style: SyntheticDartStyle = pick < 0.4 ? .steelTungsten : (pick < 0.8 ? .brass : .allBlack)
        return SyntheticDart(tip: random.boardPoint(maxRadius: 170), leanUpDegrees: random.uniform(0...18),
                             leanSideDegrees: random.uniform(-6...6), style: style)
    }

    /// The point colour of the all-black style.
    static let blackPoint = SyntheticDartStyle.allBlack.point

    /// True when the point of `dart` is steel (visible on every bed): the "visible tip" of T1 to T3.
    static func hasSteelPoint(_ dart: SyntheticDart) -> Bool {
        dart.style.point != blackPoint
    }

    /// A tip uniform over the part of the board that shows `surface` (inside the double ring).
    static func tip(on surface: BoardModel.Surface, random: inout SupportRandom) -> BoardPoint {
        for _ in 0..<10_000 {
            let point = random.boardPoint(maxRadius: 170)
            if BoardModel.surface(at: point) == surface { return point }
        }
        return BoardPoint(x: 0, y: 50)
    }

    /// T6: a first dart already committed, then a second whose tip lies inside the silhouette of the first (the
    /// band of the board that the first dart hides from the camera). One trial per accepted pair.
    static func occludedBatch(count: Int, seed: UInt64) -> [Trial] {
        let setup = Setup()
        var random = SupportRandom(seed: seed)
        var trials: [Trial] = []
        let detector = DifferencingDartDetector()
        for (poseIndex, pose) in SupportPoses.allCases.enumerated() {
            let camera = pose.camera
            let calibration = camera.calibration()
            let empty = reference(setup, camera: camera, seed: seed &+ UInt64(poseIndex))
            var accepted = 0, attempts = 0
            let share = count / 4 + (poseIndex < count % 4 ? 1 : 0)
            while accepted < share, attempts < share * 4 {
                attempts += 1
                var first = probeDart(&random)
                first.style = random.unit() < 0.5 ? .steelTungsten : .brass
                first.style.point = SyntheticDartStyle.steelTungsten.point
                first.tip = random.boardPoint(maxRadius: 140)
                let base = UInt64(poseIndex * 100_000 + attempts * 10)
                let withFirst = scene(setup, camera: camera, darts: [first], seed: seed &+ base &+ 1).renderCanvas(camera: camera)
                let firstRequest = DetectionRequest(current: withFirst, reference: empty, emptyReference: empty, knownDarts: [],
                                                    calibration: calibration, noiseSigma: setup.noiseSigma)
                let firstAnalysis = detector.analyse(firstRequest)
                guard firstAnalysis.kind == .darts, let found = firstAnalysis.darts.first else { continue }
                let known = KnownDart(id: UUID(uuidString: "00000000-0000-0000-0000-0000000000F1") ?? UUID(), tip: found.tip,
                                      silhouette: found.silhouette)
                let direction = apparentAxis(of: first, camera: camera)
                var second: SyntheticDart?
                for _ in 0..<12 {
                    let distance = random.uniform(4...30)
                    let tip = BoardPoint(x: first.tip.x + direction.x * distance, y: first.tip.y + direction.y * distance)
                    if found.silhouette.contains(tip), tip.radius < 165 {
                        var dart = probeDart(&random)
                        dart.tip = tip
                        second = dart
                        break
                    }
                }
                guard let second else { continue }
                // The rolling reference holds the first dart, rendered with its own noise.
                let rolling = scene(setup, camera: camera, darts: [first], seed: seed &+ base &+ 2).renderCanvas(camera: camera)
                trials.append(trial(setup, pose: pose, camera: camera, reference: rolling, emptyReference: empty, known: [known],
                                    knownDarts: [first], dart: second, seed: seed &+ base &+ 3))
                accepted += 1
            }
        }
        return trials
    }

    /// One line of the accuracy report.
    static func summary(_ name: String, _ trials: [Trial]) -> String {
        guard !trials.isEmpty else { return "\(name): no dart" }
        let n = Double(trials.count)
        let errors = trials.map(\.error)
        let correct = trials.filter(\.isCorrect).count
        let highs = trials.filter { $0.tier == .high }
        let highWrong = highs.filter { !$0.isCorrect }.count
        let lows = trials.filter { $0.tier == .low }.count
        func mm(_ value: Double?) -> String { value.map { $0.isFinite ? String(format: "%.2f", $0) : "inf" } ?? "-" }
        func percent(_ count: Int) -> String { String(format: "%.1f%%", 100 * Double(count) / n) }
        return "\(name): n=\(trials.count) correct bed \(percent(correct)) | error median \(mm(quantile(errors, 0.5))) p90 "
            + "\(mm(quantile(errors, 0.9))) p95 \(mm(quantile(errors, 0.95))) | high \(percent(highs.count)) low \(percent(lows)) "
            + "| high and wrong \(highWrong) (\(highs.isEmpty ? "-" : String(format: "%.2f%% of highs", 100 * Double(highWrong) / Double(highs.count))))"
    }
}
