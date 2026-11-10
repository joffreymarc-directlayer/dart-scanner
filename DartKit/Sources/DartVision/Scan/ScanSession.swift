import Foundation
import simd
import CoreGraphics
import CoreVideo
import DartCore

/// Thin concurrency wrapper: one serial queue, one frame source, one engine, one stream of events.
public final class ScanSession: @unchecked Sendable {
    public init(source: any FrameSource, makeEngine: @escaping @Sendable () -> ScanEngine) { fatalError("unimplemented") }
    public var events: AsyncStream<ScanEvent> { get { fatalError("unimplemented") } }
    public func start() async throws { fatalError("unimplemented") }
    public func stop() async { fatalError("unimplemented") }
    /// Mean of the next `frames` frames at full resolution: the frozen still for the calibration screen.
    public func captureStill(averaging frames: Int = 8) async throws -> RGBImage { fatalError("unimplemented") }
    public func setCalibration(_ calibration: BoardCalibration) async { fatalError("unimplemented") }
    public func send(_ command: ScanCommand) async { fatalError("unimplemented") }
    public func correct(_ id: UUID, tip: BoardPoint) async -> DartObservation? { fatalError("unimplemented") }
    public func recordFeedback(_ id: UUID, wasCorrected: Bool) async { fatalError("unimplemented") }
    public func evidenceCrop(for id: UUID, span: Double = 50, scale: Double = 6) async -> CGImage? { fatalError("unimplemented") }
    public func runLightingCheck(confirmedTip: BoardPoint) async -> LightingCheckResult? { fatalError("unimplemented") }
    public func updateConfiguration(_ configuration: VisionConfiguration) async { fatalError("unimplemented") }
    public func currentState() async -> ScanState { fatalError("unimplemented") }
    public func debugSnapshot() async -> ScanDebugSnapshot { fatalError("unimplemented") }
}
