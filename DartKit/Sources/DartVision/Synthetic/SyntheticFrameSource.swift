import Foundation
import simd
import CoreGraphics
import CoreVideo
import DartCore

/// Renders a `SyntheticScript` frame by frame.
///
/// Frame `n` has the timestamp `n / framesPerSecond` and its own noise (the scene's seed mixed with `n`), so two
/// runs of the same script give the same frames, bit for bit. Frames that show the same geometry share their
/// rays: only the shift, the gain and the noise are redone. `info` is nil until `start(on:handler:)` or the first
/// `nextFrame()`. With `realTime` the frames are delivered at the script's rate; otherwise as fast as they render.
public final class SyntheticFrameSource: FrameSource, @unchecked Sendable {
    private let camera: SyntheticCamera
    private let scene: SyntheticScene
    private let realTime: Bool
    private let framesPerSecond: Double
    private let shots: [SyntheticScript.Shot]

    /// Guards every `var` below.
    private let lock = NSLock()
    private var next = 0
    private var started = false
    /// Changes on every `start` and `stop`: a delivery loop of an older generation ends.
    private var generation = 0
    private var cached: (geometry: SyntheticScript.Shot.Geometry, base: SyntheticBaseImage)?

    public init(script: SyntheticScript, camera: SyntheticCamera, scene: SyntheticScene = .init(), realTime: Bool = false) {
        self.camera = camera
        self.scene = scene
        self.realTime = realTime
        framesPerSecond = script.framesPerSecond
        shots = script.shots(camera: camera, scene: scene)
    }

    public var info: FrameSourceInfo? {
        lock.withLock {
            started ? FrameSourceInfo(size: camera.imageSize, nominalFramesPerSecond: framesPerSecond, rotationDegrees: 0,
                                      intrinsics: camera.intrinsics, isLive: realTime) : nil
        }
    }

    /// Synchronous stepping for deterministic tests; nil at the end of the script.
    public func nextFrame() -> Frame? {
        lock.withLock {
            started = true
            guard next < shots.count else { return nil }
            let index = next
            next += 1
            return Frame(image: render(index), timestamp: Double(index) / framesPerSecond)
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

    /// Delivers one frame, then schedules the next one on the same queue (so that other work on that queue runs
    /// between two frames), until the end of the script or a `stop`.
    private func deliver(generation current: Int, on queue: DispatchQueue, to handler: @escaping @Sendable (Frame) -> Void) {
        guard lock.withLock({ generation == current }), let frame = nextFrame() else { return }
        handler(frame)
        if realTime {
            queue.asyncAfter(deadline: .now() + 1 / framesPerSecond) { [self] in
                deliver(generation: current, on: queue, to: handler)
            }
        } else {
            queue.async { [self] in
                deliver(generation: current, on: queue, to: handler)
            }
        }
    }

    /// Number of frames of the script.
    var frameCount: Int {
        shots.count
    }

    /// The image of frame `index`. Called with the lock held.
    private func render(_ index: Int) -> RGBImage {
        let shot = shots[index]
        let geometry = shot.geometry
        let base: SyntheticBaseImage
        if let cached, cached.geometry == geometry {
            base = cached.base
        } else {
            base = baseImage(of: geometry)
            cached = (geometry, base)
        }
        var frameScene = scene
        frameScene.shift = scene.shift + shot.jitter
        frameScene.gain = scene.gain * shot.gain
        frameScene.seed = SyntheticNoise.mix(scene.seed ^ SyntheticNoise.mix(UInt64(index) &+ 0x5F0C_A1E5))
        return frameScene.finished(base)
    }

    /// Rays and blur of one geometry; a dart in motion is rendered at each of its positions and averaged.
    private func baseImage(of geometry: SyntheticScript.Shot.Geometry) -> SyntheticBaseImage {
        var frameScene = scene
        frameScene.darts = geometry.darts
        frameScene.hand = geometry.hand.map { (centre: $0.centre, radius: $0.radius) }
        guard let motion = geometry.motion, !motion.offsets.isEmpty else {
            return frameScene.baseImage(camera: geometry.camera)
        }
        let resting = geometry.darts.map { $0.solid() }
        let images = motion.offsets.map { offset in
            frameScene.baseImage(camera: geometry.camera, solids: resting + [motion.dart.solid(offset: offset)])
        }
        return SyntheticBaseImage.average(images)
    }
}

extension SyntheticBaseImage {
    /// Pixel-wise mean of images of the same size, rounded to the nearest level; the content is the union.
    static func average(_ images: [SyntheticBaseImage]) -> SyntheticBaseImage {
        guard let first = images.first else {
            return SyntheticBaseImage(image: RGBImage(width: 0, height: 0, pixels: []), content: SyntheticPixelBox(x0: 0, y0: 0, x1: 0, y1: 0))
        }
        let count = first.image.pixels.count
        guard images.count > 1, images.allSatisfy({ $0.image.width == first.image.width && $0.image.height == first.image.height
                                                     && $0.image.pixels.count == count }) else { return first }
        var sums = [UInt32](repeating: 0, count: count)
        var content = first.content
        for image in images {
            content = content.union(image.content)
            image.image.pixels.withUnsafeBufferPointer { source in
                sums.withUnsafeMutableBufferPointer { total in
                    var index = 0
                    while index < count {
                        total[index] &+= UInt32(source[index])
                        index += 1
                    }
                }
            }
        }
        let divisor = UInt32(images.count), half = UInt32(images.count / 2)
        var pixels = [UInt8](repeating: 0, count: count)
        sums.withUnsafeBufferPointer { total in
            pixels.withUnsafeMutableBufferPointer { out in
                var index = 0
                while index < count {
                    out[index] = UInt8((total[index] + half) / divisor)
                    index += 1
                }
            }
        }
        return SyntheticBaseImage(image: RGBImage(width: first.image.width, height: first.image.height, pixels: pixels), content: content)
    }
}
