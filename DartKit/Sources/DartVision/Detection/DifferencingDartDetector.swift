import Foundation
import simd
import CoreGraphics
import CoreVideo
import DartCore

/// Intermediate images of the differencing detector, for SnapshotTool and the debug overlay.
public struct DetectionDebug: Sendable {
    /// Shadow-tolerant evidence map (D2).
    public var evidence: GrayImage
    /// Binary mask after morphology (D3).
    public var mask: GrayImage
    /// Fitted axis segments in canvas pixels, one per candidate.
    public var axes: [(from: SIMD2<Double>, to: SIMD2<Double>)]
    /// Tips in canvas pixels, one per candidate.
    public var tips: [SIMD2<Double>]
    public var threshold: Double
}

/// Reference differencing in the canvas (section 5). The v1 detector.
public struct DifferencingDartDetector: DartDetecting {
    public init() { fatalError("unimplemented") }
    public var descriptor: DetectorDescriptor { get { fatalError("unimplemented") } }
    public var needsSourceImage: Bool { get { fatalError("unimplemented") } }
    public func analyse(_ request: DetectionRequest) -> SceneAnalysis { fatalError("unimplemented") }
    public func analyseWithDebug(_ request: DetectionRequest) -> (analysis: SceneAnalysis, debug: DetectionDebug) { fatalError("unimplemented") }
}
