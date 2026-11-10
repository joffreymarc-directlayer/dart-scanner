import Foundation
import simd
import Testing
import DartCore
import DartVision

/// The canned inputs of the `Reducer` suites mean what those suites say they mean, with the defaults of
/// `ScanParameters` (VISION.md §6.1, §6.2). If a default changes, this suite says which assumption broke.
@Suite struct ReducerHarnessTests {
    private typealias H = ReducerHarness

    @Test func cannedSamples_areQuietMovingAndLastingWithTheDefaults() {
        let parameters = ScanParameters()
        // A quiet sample is below the calm threshold, a moving one above the start of motion.
        #expect(0.0001 < parameters.quietFraction && 0.02 > parameters.motionOnFraction)
        // The in-between value some tests use is neither.
        #expect(0.0008 >= parameters.quietFraction && 0.0008 <= parameters.motionOnFraction)
        // A dart is 0.5 to 0.7 % of the gate (§6.1): a lasting change; 0.0001 is not one.
        #expect(H.dartChange >= 0.005 && H.dartChange <= 0.007 && H.dartChange >= parameters.noLastingChangeFraction)
        #expect(0.0001 < parameters.noLastingChangeFraction)
        // A border band of 5 % is an intrusion.
        #expect(0.05 > parameters.handBorderFraction)
    }

    @Test func cannedEpisodes_haveTheIntendedKind() {
        var h = H()
        h.start()
        // Three moving frames: 0.1 s, throw-like.
        h.episode()
        #expect(h.machine.lastEpisode.map { abs($0.duration - 0.1) < 1e-9 && !$0.isHandLike(ScanParameters()) } == true)
        h.settle(.noChange)
        // 45 moving frames: 1.5 s, hand-like.
        h.handEpisode()
        #expect(h.machine.lastEpisode.map { abs($0.duration - 1.5) < 1e-9 && $0.isHandLike(ScanParameters()) } == true)
        // Frames are timed at 30 per second.
        #expect(h.frame == 12 + 9 + 51 && abs(h.now - Double(h.frame - 1) / 30) < 1e-12)
    }

    @Test func cannedValues_areDistinctStableAndPlainData() {
        #expect(H.id(1) == H.id(1) && H.id(1) != H.id(2))
        #expect(H.id(12).uuidString == "00000000-0000-0000-0000-000000000012")
        let thresholds = ConfidenceThresholds.standard
        for tier: ConfidenceTier in [.low, .medium, .high] {
            let observation = H.observation(3, tier: tier)
            // The confidence agrees with the tier under the standard thresholds (§7.4).
            switch tier {
            case .high: #expect(observation.confidence >= thresholds.high)
            case .medium: #expect(observation.confidence >= thresholds.medium && observation.confidence < thresholds.high)
            case .low: #expect(observation.confidence < thresholds.medium)
            }
            #expect(observation.tier == tier && observation.id == H.id(3) && !observation.candidates.isEmpty)
        }
        let flagged = H.observation(H.observation(4), flags: [.clutter])
        #expect(flagged.flags == [.clutter] && flagged.id == H.id(4) && flagged.confidence == H.observation(4).confidence)
    }
}

/// Drives a `ScanStateMachine` with canned inputs (VISION.md §10.2, group S): gate samples at 30 frames per
/// second, commands, settle outcomes and calibration health. No image, no engine. Shared by the `Reducer` suites.
struct ReducerHarness {
    var machine: ScanStateMachine
    /// Index of the next frame; its timestamp is `frame / 30`.
    var frame = 0

    /// A dart covers about 0.6 % of the gate (§6.1): what a quiet frame shows against the gate reference
    /// while a new dart is on the board.
    static let dartChange = 0.006

    init(parameters: ScanParameters = .init()) {
        machine = ScanStateMachine(parameters: parameters)
    }

    /// Timestamp of the last frame sent.
    var now: TimeInterval { Double(max(0, frame - 1)) / 30 }

    var state: ScanState { machine.state }

    // MARK: Inputs

    @discardableResult
    mutating func send(_ input: ScanInput) -> [ScanEffect] {
        machine.handle(input)
    }

    @discardableResult
    mutating func command(_ command: ScanCommand) -> [ScanEffect] {
        machine.handle(.command(command))
    }

    /// One gate sample at the next frame time.
    @discardableResult
    mutating func sample(motion: Double, change: Double = 0, border: Double = 0) -> [ScanEffect] {
        let sample = GateSample(timestamp: Double(frame) / 30, motionFraction: motion, changeVsReference: change,
                                borderChange: border, meanLuma: 120)
        frame += 1
        return machine.handle(.gate(sample))
    }

    /// `count` quiet samples; the effects of each one.
    @discardableResult
    mutating func quiet(_ count: Int = 1, change: Double = 0) -> [[ScanEffect]] {
        (0..<count).map { _ in sample(motion: 0.0001, change: change) }
    }

    /// `count` samples in motion; the effects of each one.
    @discardableResult
    mutating func moving(_ count: Int = 1, change: Double = 0.02, border: Double = 0) -> [[ScanEffect]] {
        (0..<count).map { _ in sample(motion: 0.02, change: change, border: border) }
    }

    @discardableResult
    mutating func settle(_ outcome: SettleOutcome) -> [ScanEffect] {
        machine.handle(.settle(outcome, timestamp: now))
    }

    @discardableResult
    mutating func health(_ status: CalibrationHealth.Status, recovered: Bool = false) -> [ScanEffect] {
        machine.handle(.calibrationHealth(status, recovered: recovered, timestamp: now))
    }

    // MARK: Scenarios

    /// Calibration, `arm`, twelve quiet samples: `watching(0)` (rows 1 to 3).
    mutating func start(boardConfirmedEmpty: Bool = true, trigger: ScanTrigger = .automatic) {
        send(.calibrationSet)
        if trigger != machine.trigger { command(.setTrigger(trigger)) }
        command(.arm(boardConfirmedEmpty: boardConfirmedEmpty))
        quiet(12)
    }

    /// A motion episode of `movingFrames` frames followed by the six quiet frames of the pose, with a lasting
    /// change in view: the machine ends in `analysing`. Returns the effects of the last quiet sample.
    @discardableResult
    mutating func episode(movingFrames: Int = 3, border: Double = 0, change: Double = ReducerHarness.dartChange) -> [ScanEffect] {
        moving(movingFrames, border: border)
        return quiet(6, change: change).last ?? []
    }

    /// A throw-like episode whose analysis finds `observation`.
    @discardableResult
    mutating func throwDart(_ observation: DartObservation) -> [ScanEffect] {
        episode()
        return settle(.darts(new: [observation], removed: [], disturbed: []))
    }

    /// A hand in view: a long episode (1.5 s) that ends in `analysing`.
    @discardableResult
    mutating func handEpisode(change: Double = ReducerHarness.dartChange) -> [ScanEffect] {
        episode(movingFrames: 45, change: change)
    }

    // MARK: Values

    static func id(_ number: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", number)) ?? UUID()
    }

    /// A hand-made observation (VISION.md §9.4): only plain-data members are used.
    static func observation(_ number: Int, tier: ConfidenceTier = .high, flags: DartFlags = [],
                            source: ObservationSource = .liveCamera) -> DartObservation {
        let confidence: Double
        switch tier {
        case .high: confidence = 0.93
        case .medium: confidence = 0.7
        case .low: confidence = 0.3
        }
        return DartObservation(id: id(number), visit: 1, indexInVisit: 0, timestamp: 0, tip: BoardPoint(x: 0, y: 103),
                               uncertainty: TipUncertainty(sigmaAlong: 0.85, sigmaAcross: 0.37, axis: SIMD2(0, 1)),
                               candidates: [HitCandidate(hit: .treble(20), probability: 0.93),
                                            HitCandidate(hit: .single(20), probability: 0.07)],
                               nearbyHits: [.single(20), .single(1)], confidence: confidence, tier: tier, flags: flags,
                               source: source)
    }

    /// The same observation with other flags.
    static func observation(_ observation: DartObservation, flags: DartFlags) -> DartObservation {
        DartObservation(id: observation.id, visit: observation.visit, indexInVisit: observation.indexInVisit,
                        timestamp: observation.timestamp, tip: observation.tip, uncertainty: observation.uncertainty,
                        candidates: observation.candidates, nearbyHits: observation.nearbyHits,
                        confidence: observation.confidence, tier: observation.tier, flags: flags,
                        source: observation.source)
    }

    // MARK: Reading effects

    static func events(_ effects: [ScanEffect]) -> [ScanEvent] {
        effects.compactMap { effect in
            if case .emit(let event) = effect { return event }
            return nil
        }
    }

    /// Events without the `stateChanged` ones.
    static func facts(_ effects: [ScanEffect]) -> [ScanEvent] {
        events(effects).filter { event in
            if case .stateChanged = event { return false }
            return true
        }
    }

    /// Effects that are not events: what the engine has to do.
    static func work(_ effects: [ScanEffect]) -> [ScanEffect] {
        effects.filter { effect in
            if case .emit = effect { return false }
            return true
        }
    }

    static func references(_ effects: [ScanEffect]) -> [ScanEffect] {
        effects.filter { effect in
            if case .updateReference = effect { return true }
            return false
        }
    }

    static func analyses(_ effects: [ScanEffect]) -> [ScanEffect] {
        effects.filter { effect in
            if case .analyse = effect { return true }
            return false
        }
    }
}
