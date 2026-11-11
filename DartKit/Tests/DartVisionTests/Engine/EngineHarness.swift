import Foundation
import simd
import DartCore
@testable import DartVision

/// Drives a `ScanEngine` with a synthetic film, frame by frame, and records what comes out (lot V5 tests).
///
/// The film is played step by step: each `SyntheticScript` step is rendered by its own `SyntheticFrameSource`,
/// starting from the darts already at rest, then every frame goes through `ScanEngine.process` with a global
/// timestamp `n / 30`. Commands are sent between frames. Every event is logged with the index of the frame (or
/// of the command) that produced it, and the gate samples that the engine fed to its reducer are kept, so that a
/// test can measure latencies in frames.
final class EngineRun {
    struct Entry: Sendable {
        /// Index of the frame being processed when the event came out; for a command, the number of frames played.
        var frame: Int
        var event: ScanEvent
    }

    /// A thrown dart and the frame at which it came to rest.
    struct Landing: Sendable {
        var dart: SyntheticDart
        var frame: Int
    }

    let engine: ScanEngine
    private(set) var camera: SyntheticCamera
    /// Darts at rest, light, whole-image shift, noise: the scene of the next step.
    private(set) var scene: SyntheticScene
    private(set) var frameCount = 0
    private(set) var log: [Entry] = []
    /// Indices of the frames whose gate sample showed motion (`motionFraction > motionOnFraction`).
    private(set) var motionFrames: [Int] = []
    private(set) var landings: [Landing] = []
    /// Wall-clock time spent in `ScanEngine.process` per frame that emitted events, by frame index.
    private(set) var processingTimes: [(frame: Int, duration: Duration)] = []
    /// Applied to every rendered image before the engine sees it (local light changes).
    var imageFilter: (@Sendable (inout RGBImage) -> Void)?
    let framesPerSecond = 30.0
    private var stepSeed: UInt64

    init(camera: SyntheticCamera, scene: SyntheticScene = SupportScenes.empty(), engine: ScanEngine, seed: UInt64 = 1) {
        self.camera = camera
        self.scene = scene
        self.engine = engine
        stepSeed = seed
    }

    convenience init(camera: SyntheticCamera, seed: UInt64 = 1, configuration: VisionConfiguration = .init(),
                     detector: any DartDetecting = DifferencingDartDetector(), locator: (any BoardLocating)? = nil,
                     recorder: (any ScanRecording)? = nil) {
        let engine = ScanEngine(detector: detector, locator: locator, configuration: configuration, recorder: recorder)
        self.init(camera: camera, scene: SupportScenes.empty(seed: seed), engine: engine, seed: seed)
    }

    // MARK: Commands

    /// Installs the exact calibration of the camera (`SyntheticCamera.calibration(grade:)`).
    @discardableResult
    func calibrate(grade: CalibrationQuality.Grade = .good) -> [ScanEvent] {
        install(camera.calibration(grade: grade))
    }

    @discardableResult
    func install(_ calibration: BoardCalibration) -> [ScanEvent] {
        let events = engine.setCalibration(calibration)
        log += events.map { Entry(frame: frameCount, event: $0) }
        return events
    }

    @discardableResult
    func send(_ command: ScanCommand) -> [ScanEvent] {
        let events = engine.handle(command)
        log += events.map { Entry(frame: frameCount, event: $0) }
        return events
    }

    // MARK: Film

    /// Plays script steps one after the other.
    func play(_ steps: [SyntheticScript.Step]) {
        for step in steps {
            play(step)
        }
    }

    func play(_ step: SyntheticScript.Step) {
        var stepScene = scene
        stepSeed = stepSeed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        stepScene.seed = stepSeed
        let source = SyntheticFrameSource(script: SyntheticScript([step], framesPerSecond: framesPerSecond), camera: camera,
                                          scene: stepScene)
        let first = frameCount
        while let frame = source.nextFrame() {
            feed(frame.makeRGBImage())
        }
        switch step {
        case .throwDart(let dart):
            // At rest from the first frame of vibration, the third of the step.
            landings.append(Landing(dart: dart, frame: first + 2))
            scene.darts.append(dart)
        case .takeout:
            scene.darts.removeAll()
        case .fallOut(let index):
            if scene.darts.indices.contains(index) { scene.darts.remove(at: index) }
        case .bump(let delta, let roll):
            camera = camera.moved(by: delta, rollDegrees: roll)
        case .lightStep(let gain):
            scene.gain *= gain
        case .lightRamp(let gain, _):
            scene.gain *= gain
        case .wait, .bounceOut, .handRest:
            break
        }
    }

    func wait(_ seconds: Double) {
        play(.wait(seconds))
    }

    /// Darts appear or vanish between two frames, without any flight: one frame shows the change with a small
    /// vibration, the next ones are still. For long statistical runs where the flight is not what is measured.
    func teleport(adding added: [SyntheticDart] = [], removingAll: Bool = false, stillFrames: Int = 10) {
        if removingAll { scene.darts.removeAll() }
        scene.darts.append(contentsOf: added)
        stepSeed = stepSeed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        var stepScene = scene
        stepScene.seed = stepSeed
        let base = cachedBase(stepScene)
        let jitter: [Double] = [0.6, -0.4, 0.27, -0.18]
        for (index, size) in (jitter + [Double](repeating: 0, count: max(0, stillFrames))).enumerated() {
            var frameScene = stepScene
            frameScene.shift = scene.shift + SIMD2(0.8, 0.6) * size
            frameScene.seed = SyntheticNoise.mix(stepSeed ^ UInt64(index + 1))
            if index == 0 {
                for dart in added { landings.append(Landing(dart: dart, frame: frameCount)) }
            }
            feed(frameScene.finished(base))
        }
    }

    /// Rays of the last geometries rendered by `teleport`, which keeps coming back to the same boards.
    private var bases: [(darts: [SyntheticDart], camera: SyntheticCamera, base: SyntheticBaseImage)] = []

    private func cachedBase(_ scene: SyntheticScene) -> SyntheticBaseImage {
        if let hit = bases.first(where: { $0.darts == scene.darts && $0.camera == camera }) { return hit.base }
        let base = scene.baseImage(camera: camera)
        bases.insert((scene.darts, camera, base), at: 0)
        if bases.count > 2 { bases.removeLast(bases.count - 2) }
        return base
    }

    /// A knock that moves the whole image by `delta` pixels: three frames of decaying shake around the new
    /// position, which stays.
    func shiftBump(by delta: SIMD2<Double>) {
        scene.shift += delta
        stepSeed = stepSeed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        let base = scene.baseImage(camera: camera)
        var size = 1.5
        for index in 0..<3 {
            var frameScene = scene
            frameScene.shift = scene.shift + SIMD2(0.8, 0.6) * size
            frameScene.seed = SyntheticNoise.mix(stepSeed ^ UInt64(index + 1))
            feed(frameScene.finished(base))
            size *= -0.67
        }
    }

    /// A slow sway of the whole image: the sum of two sines of periods `periods` seconds, `amplitude` pixels at most
    /// along each axis, for `frames` frames.
    func sway(frames: Int, amplitude: Double, periods: (Double, Double) = (2.3, 3.7)) {
        stepSeed = stepSeed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        let base = scene.baseImage(camera: camera)
        for index in 0..<frames {
            let t = Double(index) / framesPerSecond
            let x = amplitude * 0.5 * (sin(2 * .pi * t / periods.0) + sin(2 * .pi * t / periods.1 + 1))
            let y = amplitude * 0.5 * (cos(2 * .pi * t / periods.0 + 0.5) + sin(2 * .pi * t / periods.1))
            var frameScene = scene
            frameScene.shift = scene.shift + SIMD2(x, y)
            frameScene.seed = SyntheticNoise.mix(stepSeed ^ UInt64(index + 1))
            feed(frameScene.finished(base))
        }
    }

    /// Changes the scene for the next steps.
    func update(_ change: (inout SyntheticScene) -> Void) {
        change(&scene)
    }

    /// One image through the engine.
    func feed(_ rendered: RGBImage) {
        var image = rendered
        imageFilter?(&image)
        let frame = Frame(image: image, timestamp: Double(frameCount) / framesPerSecond)
        let clock = ContinuousClock()
        let start = clock.now
        let events = engine.process(frame)
        let elapsed = clock.now - start
        if !events.isEmpty { processingTimes.append((frameCount, elapsed)) }
        if let sample = engine.lastGate, sample.timestamp == frame.timestamp, engine.gateRunning,
           sample.motionFraction > engine.settings.scan.motionOnFraction {
            motionFrames.append(frameCount)
        }
        log += events.map { Entry(frame: frameCount, event: $0) }
        frameCount += 1
    }

    // MARK: Reading the log

    var events: [ScanEvent] {
        log.map(\.event)
    }

    /// Every event except `stateChanged`.
    var facts: [ScanEvent] {
        events.filter {
            if case .stateChanged = $0 { return false }
            return true
        }
    }

    var states: [ScanState] {
        events.compactMap {
            if case .stateChanged(let state) = $0 { return state }
            return nil
        }
    }

    var observations: [DartObservation] {
        events.flatMap { event -> [DartObservation] in
            switch event {
            case .dart(let observation): return [observation]
            case .scanCompleted(let observations): return observations
            default: return []
            }
        }
    }

    /// Frame index of each `dart` event, in order.
    var dartFrames: [Int] {
        log.compactMap {
            if case .dart = $0.event { return $0.frame }
            return nil
        }
    }

    /// One short line per logged event, for failure messages: `frame: kind`.
    var summary: String {
        log.map { entry -> String in
            let text: String
            switch entry.event {
            case .stateChanged(let state): text = "\(state)"
            case .dart(let observation): text = "dart \(observation.best.notation) i\(observation.indexInVisit)"
            case .scanCompleted(let observations): text = "scan \(observations.map(\.best.notation))"
            case .dartRemoved(_, let reason): text = "removed \(reason)"
            case .calibrationAdjusted: text = "calibrationAdjusted"
            case .calibrationRecovered: text = "calibrationRecovered"
            default: text = "\(entry.event)"
            }
            return "\(entry.frame): \(text)"
        }.joined(separator: "; ")
    }

    /// The last frame with motion before `frame`, if any.
    func lastMotion(before frame: Int) -> Int? {
        motionFrames.last { $0 < frame }
    }
}

/// Accuracy of observations against the darts thrown (lot V5 tests).
enum EngineAccuracy {
    /// Distance from the observed tip to the true entry point, mm.
    static func error(_ observation: DartObservation, _ dart: SyntheticDart) -> Double {
        hypot(observation.tip.x - dart.tip.x, observation.tip.y - dart.tip.y)
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
                let direction = BoardModel.wireDirection(wire)
                if point.x * direction.x + point.y * direction.y > 0 {
                    nearest = min(nearest, abs(BoardModel.signedDistanceToWire(wire, point)))
                }
            }
        }
        return nearest
    }

    /// Value at `fraction` of the sorted values (nearest rank); nil when empty.
    static func quantile(_ values: [Double], _ fraction: Double) -> Double? {
        let sorted = values.filter(\.isFinite).sorted()
        guard !sorted.isEmpty else { return nil }
        let rank = Int((fraction * Double(sorted.count)).rounded(.up)) - 1
        return sorted[min(sorted.count - 1, max(0, rank))]
    }

    /// The dart nearest to an observed tip.
    static func nearest(_ observation: DartObservation, among darts: [SyntheticDart]) -> SyntheticDart? {
        darts.min { error(observation, $0) < error(observation, $1) }
    }
}

/// Scenes and cameras of the engine tests (lot V5 tests).
enum EngineScenes {
    /// Pose B of VISION.md §10.2 (1080p landscape, 1.1 to 1.3 px/mm): the camera of the debug runs.
    static var debugCamera: SyntheticCamera {
        SupportPoses.b.camera
    }

    /// A dart with a silver point and the default lean.
    static func steel(_ x: Double, _ y: Double, lean: Double = 9, side: Double = 0) -> SyntheticDart {
        SyntheticDart(tip: BoardPoint(x: x, y: y), leanUpDegrees: lean, leanSideDegrees: side, style: .steelTungsten)
    }

    static func brass(_ x: Double, _ y: Double, lean: Double = 9, side: Double = 0) -> SyntheticDart {
        SyntheticDart(tip: BoardPoint(x: x, y: y), leanUpDegrees: lean, leanSideDegrees: side, style: .brass)
    }

    /// Multiplies the left half of the image by `gain` (a lamp on one side).
    static func brightenLeftHalf(_ gain: Double) -> @Sendable (inout RGBImage) -> Void {
        { image in
            let width = image.width, height = image.height
            for y in 0..<height {
                for x in 0..<(width / 2) {
                    let index = (y * width + x) * 3
                    for channel in 0..<3 {
                        image.pixels[index + channel] = UInt8(min(255, (Double(image.pixels[index + channel]) * gain).rounded()))
                    }
                }
            }
        }
    }
}
