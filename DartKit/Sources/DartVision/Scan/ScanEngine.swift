import Foundation
import simd
import CoreGraphics
import CoreVideo
import DartCore

/// Root of all tunables; `Codable` so a tuning session can export and reload it as JSON.
public struct VisionConfiguration: Hashable, Codable, Sendable {
    public var calibration: CalibrationParameters = .init()
    public var detection: DetectionParameters = .init()
    public var confidence: ConfidenceParameters = .init()
    public var scan: ScanParameters = .init()
    public init() {}
}

/// Debug sink; every analysed scene can be replayed offline from what it stores.
public protocol ScanRecording: AnyObject, Sendable {
    func record(calibration: BoardCalibration)
    func record(reference: CanvasImage?, current: CanvasImage, analysis: SceneAnalysis, gate: [GateSample], at time: TimeInterval)
    func record(event: ScanEvent, at time: TimeInterval)
    /// A player correction: the original observation and the corrected tip (nil when the dart was a phantom).
    func record(correctionOf observation: DartObservation, correctedTip: BoardPoint?)
}

public struct ScanDebugSnapshot: Sendable {
    public var state: ScanState
    public var lastGate: GateSample?
    public var lastAnalysis: SceneAnalysis?
    public var lastHealth: CalibrationHealth?
    public var lastDetectionDebug: DetectionDebug?
    public var noiseSigma: Double
}

/// Synchronous, deterministic core: gate, reducer, rectifier, detector, confidence. Not thread-safe.
/// Time comes only from frame timestamps. This is the type the tests drive.
///
/// The engine feeds `ScanStateMachine` (VISION.md §6.3) and executes its effects, in the order of the returned list:
///
/// - **Gate.** `MotionGate` runs only while the reducer reads its samples: never in `needsCalibration`, `idle`,
///   `paused`, nor at rest in manual trigger. Each time it starts again its first sample, which would compare with an
///   old frame, is dropped ("porte relancée").
/// - **Accumulation.** `.beginAccumulation` empties the accumulator; every frame whose sample is handled while the
///   reducer accumulates is rectified and added. The settled image `S` is the mean of those frames: quiet frames 3
///   to 6 of a pose, the last four of an arming. `.updateReference` and `.analyse` read it. When an arming completes,
///   the last two accumulated frames give the detection noise `σ̂` and the gate commits its own noise.
/// - **Requests**, answered at once with an input: `.checkCalibration` assesses the current frame (K1 to K5, with
///   the automatic locator in `calibrationLost`), `.analyse` runs the detector and the confidence model.
/// - **What no effect says** (§6.3, "Ce que le moteur fait sans effet du réducteur"): references, silhouettes and
///   gate reference are cleared on `setCalibration` and on an `.arm` after which the state is `arming` or
///   `calibrationLost`; a silhouette is kept for every observation emitted (`dart`, `scanCompleted`) and dropped on
///   `dartRemoved`, on `.discardDart` and on `.rollingAndEmpty` / `.rollingFromEmpty`.
/// - **Observations** are built before the `.settle` input from the counters of the reducer: `visit`,
///   `indexInVisit = dartsInVisit + k`, `beyondVisitLimit` and `afterRelock` added to the candidate's flags BEFORE
///   `ConfidenceModel.observe`, `warmUp` through the context. Their identifiers are a digest of a counter and of the
///   frame time: the same input gives the same identifiers.
/// - **Relock** (§4.9): known silhouettes are dilated by `relockExtraDilation` from then on, the darts of the next
///   event carry `afterRelock`, and when the camera centre moved more than `relockCameraShiftLimit` the next
///   analysis only takes `R := S`. The gate keeps its region and drops its reference, so that the pose in progress
///   is analysed; an episode without lasting change right after a relock is read as the bump it was: `R := S`, no
///   `possibleMiss`.
/// - **Reading of an analysis** (`SettleOutcome`): a `lightingChange` after an episode that moved during two frames
///   or more, or that started from `obstructed`, is a hand in front of the board, hence `.obstruction` (D4 tests the
///   light before the size of the change, and a hand covering a third of the board would otherwise be absorbed into
///   `R`). A `removal` of every known dart while a dart entered by hand may be on the board is `boardEmpty` only
///   when the settled image matches the fresh empty reference.
public final class ScanEngine {
    public init(detector: any DartDetecting = DifferencingDartDetector(), board: BoardGeometry = .standard,
                calibrator: BoardCalibrator = .init(), locator: (any BoardLocating)? = nil,
                configuration: VisionConfiguration = .init(), recorder: (any ScanRecording)? = nil) {
        self.detector = detector
        self.board = board
        self.calibrator = calibrator
        self.locator = locator
        self.settings = configuration
        self.recorder = recorder
        machine = ScanStateMachine(parameters: configuration.scan)
        confidenceModel = ConfidenceModel(board: board, parameters: configuration.confidence)
        trust = TrustTracker(parameters: configuration.confidence)
    }

    public var state: ScanState {
        machine.state
    }

    public var calibration: BoardCalibration? {
        currentCalibration
    }

    /// Darts physically on the board, oldest first.
    public var dartsOnBoard: [DartObservation] {
        known.map(\.observation)
    }

    public var configuration: VisionConfiguration {
        get { settings }
        set { applyConfiguration(newValue) }
    }

    public func setCalibration(_ calibration: BoardCalibration) -> [ScanEvent] {
        var events = takePendingEvents()
        installCalibration(calibration)
        events += feed(.calibrationSet, frame: nil, time: lastTime)
        settleGate()
        return events
    }

    public func process(_ frame: Frame) -> [ScanEvent] {
        var events = takePendingEvents()
        events += processFrame(frame)
        return events
    }

    public func handle(_ command: ScanCommand) -> [ScanEvent] {
        var events = takePendingEvents()
        events += handleCommand(command)
        return events
    }

    /// The player dragged the tip on the evidence crop: re-scores the dart from the new tip (confidence 1).
    public func correct(_ id: UUID, tip: BoardPoint) -> DartObservation? {
        guard tip.x.isFinite, tip.y.isFinite, let index = records.lastIndex(where: { $0.observation.id == id }) else { return nil }
        let original = records[index].observation
        let corrected = confidenceModel.observation(forConfirmedTip: tip, id: id, visit: original.visit,
                                                    indexInVisit: original.indexInVisit, timestamp: original.timestamp)
        records[index].correctedTip = tip
        if let dart = known.firstIndex(where: { $0.id == id }) {
            known[dart].observation = corrected
            known[dart].tip = tip
        }
        return corrected
    }

    /// Feeds `TrustTracker` and the recorder. Call once per camera dart when its visit is confirmed.
    public func recordFeedback(_ id: UUID, wasCorrected: Bool) {
        giveFeedback(id, wasCorrected: wasCorrected, correctedTip: nil, phantom: false)
    }

    /// Rectified crop around a dart of the current visit, with nothing drawn on it.
    public func evidenceCrop(for id: UUID, span: Double, scale: Double) -> RGBImage? {
        guard span.isFinite, scale.isFinite, span > 0, scale > 0,
              let record = records.last(where: { $0.observation.id == id }), let scene = record.scene else { return nil }
        let radii = currentCalibration?.ringRadii ?? .nominal
        return scene.crop(centre: radii.fromNominal(record.observation.tip), span: span, scale: scale)
    }

    /// One-dart check: compares the latest dart with the tip the player tapped and adopts the recommended shadow bound.
    public func runLightingCheck(confirmedTip: BoardPoint) -> LightingCheckResult? {
        guard confirmedTip.x.isFinite, confirmedTip.y.isFinite, let calibration = currentCalibration,
              let scene = lastDartScene else { return nil }
        let result = LightingCheck.run(reference: scene.reference, current: scene.current, confirmedTip: confirmedTip,
                                       calibration: calibration, noiseSigma: detectionNoise, parameters: settings.detection)
        if result.recommendedShadowLowerBound.isFinite {
            settings.detection.shadowLowerBound = result.recommendedShadowLowerBound
        }
        if result.verdict == .verified {
            warmUpRemaining = 0
            verifiedCalibrationID = calibration.id
        }
        return result
    }

    public func debugSnapshot() -> ScanDebugSnapshot {
        ScanDebugSnapshot(state: machine.state, lastGate: lastGate, lastAnalysis: lastAnalysis, lastHealth: lastHealth,
                          lastDetectionDebug: lastDetectionDebug, noiseSigma: detectionNoise)
    }

    // MARK: - Stored state (lot V5)

    let detector: any DartDetecting
    let board: BoardGeometry
    var calibrator: BoardCalibrator
    let locator: (any BoardLocating)?
    var settings: VisionConfiguration
    let recorder: (any ScanRecording)?
    var machine: ScanStateMachine
    var confidenceModel: ConfidenceModel
    var trust: TrustTracker

    var currentCalibration: BoardCalibration?
    var rectifier: BoardRectifier?
    var gate: MotionGate?
    /// False while the gate is stopped: the next frame restarts it and its sample is dropped.
    var gateRunning = false

    /// Rolling reference `R`.
    var rolling: CanvasImage?
    /// Empty reference `E`, and whether it is fresh (`markEmptyStale` turns it stale).
    var empty: CanvasImage?
    var emptyIsFresh = false
    var accumulator = FrameAccumulator()
    /// Mean of the accumulator, computed once per content.
    var settledCache: CanvasImage?
    /// The frame of the current `process` call, still to be added to the accumulator.
    var pendingFrame: Frame?

    /// Darts on the board, oldest first, with their silhouettes.
    var known: [ScanEngineDart] = []
    /// The last observations, for corrections, feedback and evidence crops.
    var records: [ScanEngineRecord] = []
    /// Reference and settled image of the latest dart (one-dart lighting check).
    var lastDartScene: (reference: CanvasImage, current: CanvasImage)?
    /// Candidates of the analysis being settled, by observation id: their silhouettes.
    var pendingSilhouettes: [(id: UUID, silhouette: CanvasMask)] = []
    /// Reference and settled image of the analysis being settled.
    var analysisScene: (reference: CanvasImage, current: CanvasImage)?

    /// Per-frame noise of the rectified frames, measured at arming (`σ̂`).
    var detectionNoise: Double = 0
    /// The next analysis follows a relock: its darts carry `afterRelock`.
    var relockedForNextEvent = false
    /// The camera centre moved more than `relockCameraShiftLimit`: the next analysis only takes `R := S`.
    var skipNextDetection = false
    /// A `.checkCalibration` asked without a frame, run on the next one.
    var pendingCheck = false

    var warmUpRemaining = 0
    var verifiedCalibrationID: UUID?
    var observationSerial: UInt64 = 0

    var lastTime: TimeInterval = 0
    var lastGate: GateSample?
    var lastAnalysis: SceneAnalysis?
    var lastHealth: CalibrationHealth?
    var lastDetectionDebug: DetectionDebug?
    /// Debug images of the differencing detector are kept for `debugSnapshot()` (costs a copy per event).
    var collectsDetectionDebug = false
    /// Gate samples since the last recorded analysis.
    var gateSinceAnalysis: [GateSample] = []
    /// Frames with motion since the machine last rested: the motion of the episode being settled.
    var episodeMotionFrames = 0
    /// `meanLuma` of the samples of the current arming (flicker check, VISION.md §2.4).
    var armingLuma: [Double] = []
    var flickerChecked = false

    /// Events produced outside `process`, `handle` and `setCalibration` (feedback advisories, a new configuration):
    /// they lead the next returned list.
    var pendingEvents: [ScanEvent] = []
}

/// A dart the engine knows on the board (lot V5).
struct ScanEngineDart: Sendable {
    var id: UUID
    var observation: DartObservation
    var tip: BoardPoint
    var silhouette: CanvasMask
    /// Committed before the last relock: its silhouette gets the extra dilation.
    var predatesRelock: Bool
}

/// An observation the engine handed out (lot V5).
struct ScanEngineRecord: Sendable {
    var observation: DartObservation
    /// Settled image the dart was found in; kept for the most recent darts only.
    var scene: CanvasImage?
    var correctedTip: BoardPoint?
    var fedBack = false
}
