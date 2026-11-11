import Foundation
import os
import DartCore
import DartVision

/// The demonstration camera of the Simulator and of macOS (ARCHITECTURE.md §8.7, "Cycle de vie"): an empty board
/// rendered by the synthetic renderer of DartVision (`SyntheticScene`, the renderer behind `SyntheticFrameSource`),
/// delivered for as long as the session runs. A `SyntheticFrameSource` plays a finite script and would leave the
/// session without frames after it; this source loops over two renders of the same scene that differ only by
/// their noise, so that the gate of the vision sees a live camera.
final class CameraDemoFrameSource: FrameSource {
    /// Pose A of VISION.md §10.2, closer, on a 1080 × 1920 portrait sensor: about 1.5 px/mm.
    static let demoCamera = SyntheticCamera(imageSize: PixelSize(width: 1080, height: 1920),
                                            position: SIMD3(100, -300, 700))
    static let framesPerSecond: Double = 10

    private struct State: Sendable {
        var frames: [RGBImage] = []
        var started = false
        var generation = 0
        var index = 0
    }

    let camera: SyntheticCamera
    private let state = OSAllocatedUnfairLock(initialState: State())

    init(camera: SyntheticCamera = CameraDemoFrameSource.demoCamera) {
        self.camera = camera
    }

    var info: FrameSourceInfo? {
        state.withLock { state in
            state.started ? FrameSourceInfo(size: camera.imageSize, nominalFramesPerSecond: Self.framesPerSecond,
                                            rotationDegrees: 0, intrinsics: camera.intrinsics, isLive: true) : nil
        }
    }

    /// The first rendered frame, once the source has started: the still preview of the demonstration.
    var previewFrame: RGBImage? {
        state.withLock { $0.frames.first }
    }

    func start(on queue: DispatchQueue, handler: @escaping @Sendable (Frame) -> Void) async throws {
        let rendered = state.withLock { $0.frames }
        let frames = rendered.isEmpty ? Self.render(camera) : rendered
        let generation = state.withLock { state -> Int in
            state.frames = frames
            state.started = true
            state.generation += 1
            return state.generation
        }
        queue.async { [self] in
            deliver(generation: generation, on: queue, to: handler)
        }
    }

    func stop() async {
        state.withLock { $0.generation += 1 }
    }

    /// One frame, then the next one a period later on the same queue, until `stop`.
    private func deliver(generation: Int, on queue: DispatchQueue, to handler: @escaping @Sendable (Frame) -> Void) {
        let next: Frame? = state.withLock { state in
            guard state.generation == generation, !state.frames.isEmpty else { return nil }
            let image = state.frames[state.index % state.frames.count]
            state.index += 1
            return Frame(image: image, timestamp: Double(state.index) / Self.framesPerSecond)
        }
        guard let frame = next else { return }
        handler(frame)
        queue.asyncAfter(deadline: .now() + 1 / Self.framesPerSecond) { [self] in
            deliver(generation: generation, on: queue, to: handler)
        }
    }

    /// Two renders of the empty board with different noise seeds.
    static func render(_ camera: SyntheticCamera) -> [RGBImage] {
        [1, 2].map { seed in
            var scene = SyntheticScene()
            scene.seed = UInt64(seed)
            return scene.render(camera: camera)
        }
    }
}
