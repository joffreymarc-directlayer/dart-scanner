import Foundation
import simd
import CoreGraphics
import CoreVideo
import DartCore

/// Writes one directory per session: `calibration.json`, `events.jsonl`, `gate.jsonl`, `corrections.jsonl`
/// and, per analysed scene, `NNNN-reference.png`, `NNNN-current.png`, `NNNN-analysis.json`.
public final class DirectoryRecorder: ScanRecording, @unchecked Sendable {
    public init(directory: URL) throws { fatalError("unimplemented") }
    public func record(calibration: BoardCalibration) { fatalError("unimplemented") }
    public func record(reference: CanvasImage?, current: CanvasImage, analysis: SceneAnalysis, gate: [GateSample], at time: TimeInterval) { fatalError("unimplemented") }
    public func record(event: ScanEvent, at time: TimeInterval) { fatalError("unimplemented") }
    public func record(correctionOf observation: DartObservation, correctedTip: BoardPoint?) { fatalError("unimplemented") }
}
