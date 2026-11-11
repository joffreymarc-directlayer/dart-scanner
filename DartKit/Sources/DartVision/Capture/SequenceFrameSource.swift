import Foundation
import simd
import CoreGraphics
import CoreVideo
import DartCore

/// A fixed list of images: tests and replay of recorded stills.
///
/// Frame `n` has the timestamp `n / framesPerSecond`. `info` is nil until `start(on:handler:)` or the first
/// `nextFrame()`; its size is that of the first image. `start` delivers the frames that `nextFrame()` has not
/// returned yet, one per turn of the queue (so that other work on that queue runs between two frames), as fast as
/// they are handled; `stop` ends the delivery.
public final class SequenceFrameSource: FrameSource, @unchecked Sendable {
    public init(frames: [RGBImage], framesPerSecond: Double = 30, intrinsics: CameraIntrinsics? = nil) {
        self.frames = frames
        self.framesPerSecond = framesPerSecond.isFinite && framesPerSecond > 0 ? framesPerSecond : 30
        self.intrinsics = intrinsics
    }

    public var info: FrameSourceInfo? {
        lock.withLock {
            guard started else { return nil }
            let size = frames.first.map { PixelSize(width: $0.width, height: $0.height) } ?? PixelSize(width: 0, height: 0)
            return FrameSourceInfo(size: size, nominalFramesPerSecond: framesPerSecond, rotationDegrees: 0,
                                   intrinsics: intrinsics, isLive: false)
        }
    }

    /// Synchronous stepping for deterministic tests; nil at the end.
    public func nextFrame() -> Frame? {
        lock.withLock {
            started = true
            guard next < frames.count else { return nil }
            let index = next
            next += 1
            return Frame(image: frames[index], timestamp: Double(index) / framesPerSecond)
        }
    }

    public func start(on queue: DispatchQueue, handler: @escaping @Sendable (Frame) -> Void) async throws {
        let current = lock.withLock {
            started = true
            generation += 1
            return generation
        }
        queue.async { [self] in
            deliver(generation: current, on: queue, to: handler)
        }
    }

    public func stop() async {
        lock.withLock {
            generation += 1
        }
    }

    // MARK: - Internal state (lot V5)

    private let frames: [RGBImage]
    private let framesPerSecond: Double
    private let intrinsics: CameraIntrinsics?
    /// Guards every `var` below.
    private let lock = NSLock()
    private var next = 0
    private var started = false
    /// Changes on every `start` and `stop`: a delivery loop of an older generation ends.
    private var generation = 0

    private func deliver(generation current: Int, on queue: DispatchQueue, to handler: @escaping @Sendable (Frame) -> Void) {
        guard lock.withLock({ generation == current }), let frame = nextFrame() else { return }
        handler(frame)
        queue.async { [self] in
            deliver(generation: current, on: queue, to: handler)
        }
    }
}
