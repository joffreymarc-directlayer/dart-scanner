import Foundation
import simd
import CoreGraphics
import CoreVideo
import DartCore

/// Reads a `DirectoryRecorder` directory back for offline tuning on macOS.
public struct RecordedSession: Sendable {
    public struct Scene: Sendable {
        public var time: TimeInterval
        public var reference: CanvasImage?
        public var current: CanvasImage
        public var gate: [GateSample]
    }
    public init(directory: URL) throws { fatalError("unimplemented") }
    public var calibration: BoardCalibration { get { fatalError("unimplemented") } }
    public var scenes: [Scene] { get { fatalError("unimplemented") } }
    /// Runs a detector over every recorded scene with the given parameters.
    public func replay(detector: any DartDetecting, parameters: DetectionParameters, noiseSigma: Double) -> [SceneAnalysis] { fatalError("unimplemented") }
}
