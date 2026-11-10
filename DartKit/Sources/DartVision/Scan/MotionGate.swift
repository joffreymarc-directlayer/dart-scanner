import Foundation
import simd
import CoreGraphics
import CoreVideo
import DartCore

/// Cheap per-frame motion measurement on a small green-channel copy of the board region.
public struct MotionGate: Sendable {
    public init(calibration: BoardCalibration, parameters: ScanParameters = .init()) { fatalError("unimplemented") }
    public mutating func ingest(_ frame: Frame) -> GateSample { fatalError("unimplemented") }
    public mutating func setReferenceToCurrent() { fatalError("unimplemented") }
    /// Gate noise in levels, measured over the arming frames.
    public var noiseSigma: Double { get { fatalError("unimplemented") } }
}
