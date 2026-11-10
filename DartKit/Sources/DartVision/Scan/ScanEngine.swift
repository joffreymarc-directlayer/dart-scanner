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
public final class ScanEngine {
    public init(detector: any DartDetecting = DifferencingDartDetector(), board: BoardGeometry = .standard,
                calibrator: BoardCalibrator = .init(), locator: (any BoardLocating)? = nil,
                configuration: VisionConfiguration = .init(), recorder: (any ScanRecording)? = nil) { fatalError("unimplemented") }
    public var state: ScanState { get { fatalError("unimplemented") } }
    public var calibration: BoardCalibration? { get { fatalError("unimplemented") } }
    /// Darts physically on the board, oldest first.
    public var dartsOnBoard: [DartObservation] { get { fatalError("unimplemented") } }
    public var configuration: VisionConfiguration { get { fatalError("unimplemented") } set { fatalError("unimplemented") } }
    public func setCalibration(_ calibration: BoardCalibration) -> [ScanEvent] { fatalError("unimplemented") }
    public func process(_ frame: Frame) -> [ScanEvent] { fatalError("unimplemented") }
    public func handle(_ command: ScanCommand) -> [ScanEvent] { fatalError("unimplemented") }
    /// The player dragged the tip on the evidence crop: re-scores the dart from the new tip (confidence 1).
    public func correct(_ id: UUID, tip: BoardPoint) -> DartObservation? { fatalError("unimplemented") }
    /// Feeds `TrustTracker` and the recorder. Call once per camera dart when its visit is confirmed.
    public func recordFeedback(_ id: UUID, wasCorrected: Bool) { fatalError("unimplemented") }
    /// Rectified crop around a dart of the current visit, with nothing drawn on it.
    public func evidenceCrop(for id: UUID, span: Double, scale: Double) -> RGBImage? { fatalError("unimplemented") }
    /// One-dart check: compares the latest dart with the tip the player tapped and adopts the recommended shadow bound.
    public func runLightingCheck(confirmedTip: BoardPoint) -> LightingCheckResult? { fatalError("unimplemented") }
    public func debugSnapshot() -> ScanDebugSnapshot { fatalError("unimplemented") }
}
