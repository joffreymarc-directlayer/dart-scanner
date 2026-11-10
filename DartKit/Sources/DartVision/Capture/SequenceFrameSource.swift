import Foundation
import simd
import CoreGraphics
import CoreVideo
import DartCore

/// A fixed list of images: tests and replay of recorded stills.
public final class SequenceFrameSource: FrameSource, @unchecked Sendable {
    public init(frames: [RGBImage], framesPerSecond: Double = 30, intrinsics: CameraIntrinsics? = nil) { fatalError("unimplemented") }
    public var info: FrameSourceInfo? { get { fatalError("unimplemented") } }
    /// Synchronous stepping for deterministic tests; nil at the end.
    public func nextFrame() -> Frame? { fatalError("unimplemented") }
    public func start(on queue: DispatchQueue, handler: @escaping @Sendable (Frame) -> Void) async throws { fatalError("unimplemented") }
    public func stop() async { fatalError("unimplemented") }
}
