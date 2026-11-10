import Foundation
import simd
import Testing
import DartCore
@testable import DartVision

/// The synthetic timeline (`SyntheticScript`) and the frame source that renders it (VISION.md §10.1).
@Suite(.timeLimit(.minutes(2))) struct ImagingScriptTests {
    /// A small camera at pose B, fast to render.
    private let camera = SupportPoses.b.camera(longSide: 480)

    /// Every frame of a source, in order.
    private func frames(_ source: SyntheticFrameSource) -> [Frame] {
        var result: [Frame] = []
        while let frame = source.nextFrame() {
            result.append(frame)
        }
        return result
    }

    /// Mean absolute difference between two frames, levels.
    private func difference(_ a: Frame, _ b: Frame) -> Double {
        a.makeRGBImage().meanAbsoluteDifference(to: b.makeRGBImage()) ?? .infinity
    }

    @Test func script_frameCountsAndTimestamps() {
        let dart = SyntheticDart(tip: BoardPoint(x: 10, y: 100))
        let script = SyntheticScript([
            .wait(1), .throwDart(dart), .wait(0.5), .bounceOut, .handRest(0.5), .takeout(duration: 1),
            .fallOut(index: 0), .bump(delta: SIMD3(2, 0, 0), rollDegrees: 0.2), .lightStep(gain: 1.3),
            .lightRamp(gain: 0.8, duration: 0.5), .wait(-1), .wait(.nan),
        ])
        let source = SyntheticFrameSource(script: script, camera: camera, scene: SupportScenes.exact())
        // 30 + (2 + 4) + 15 + 3 + (6 + 15 + 6) + (6 + 30 + 6) + 0 (no dart left) + 3 + 0 + 15 + 0 + 0.
        #expect(source.frameCount == 30 + 6 + 15 + 3 + 27 + 42 + 3 + 15)
        #expect(source.info == nil)
        let all = frames(source)
        #expect(all.count == source.frameCount)
        for (index, frame) in all.enumerated() {
            #expect(frame.timestamp == Double(index) / 30 && frame.size == camera.imageSize && frame.format == .rgb8)
        }
        #expect(source.nextFrame() == nil)
        let info = source.info
        #expect(info == FrameSourceInfo(size: camera.imageSize, nominalFramesPerSecond: 30, rotationDegrees: 0,
                                        intrinsics: camera.intrinsics, isLive: false))
        // Another rate.
        let fast = SyntheticFrameSource(script: SyntheticScript([.wait(1)], framesPerSecond: 60), camera: camera)
        #expect(fast.frameCount == 60 && fast.nextFrame()?.timestamp == 0 && fast.nextFrame()?.timestamp == 1.0 / 60)
        #expect(SyntheticScript([.wait(1)], framesPerSecond: 0).framesPerSecond == 30)
        #expect(SyntheticFrameSource(script: SyntheticScript([]), camera: camera).nextFrame() == nil)
    }

    @Test func script_isDeterministicAndEveryFrameHasItsOwnNoise() {
        let script = SyntheticScript([.wait(0.1), .throwDart(SyntheticDart(tip: BoardPoint(x: -30, y: 60))), .wait(0.1)])
        let first = frames(SyntheticFrameSource(script: script, camera: camera, scene: SupportScenes.empty(seed: 4)))
        let second = frames(SyntheticFrameSource(script: script, camera: camera, scene: SupportScenes.empty(seed: 4)))
        let identical = zip(first, second).allSatisfy { $0.makeRGBImage() == $1.makeRGBImage() }
        #expect(first.count == second.count && identical)
        // Two still frames differ by the noise only: about σ·√2·0.8 = 2.3 levels for σ = 2.
        let noise = difference(first[0], first[1])
        #expect(noise > 1.5 && noise < 3.2, "\(noise)")
        // Without noise, still frames are identical.
        let clean = frames(SyntheticFrameSource(script: SyntheticScript([.wait(0.1)]), camera: camera, scene: SupportScenes.exact()))
        #expect(clean.count == 3 && clean[0].makeRGBImage() == clean[2].makeRGBImage())
        // Another seed, another noise.
        let other = frames(SyntheticFrameSource(script: script, camera: camera, scene: SupportScenes.empty(seed: 5)))
        #expect(other[0].makeRGBImage() != first[0].makeRGBImage())
    }

    @Test func script_throwBounceFallOutAndTakeout() {
        let scene = SupportScenes.exact()
        let dart = SyntheticDart(tip: BoardPoint(x: -30, y: 60), style: .brass)
        let other = SyntheticDart(tip: BoardPoint(x: 50, y: -20))
        let script = SyntheticScript([.wait(0.1), .throwDart(dart), .wait(0.1), .bounceOut, .wait(0.1), .throwDart(other),
                                      .wait(0.1), .fallOut(index: 0), .wait(0.1), .takeout(duration: 0.5), .wait(0.1)])
        let all = frames(SyntheticFrameSource(script: script, camera: camera, scene: scene))
        func render(_ darts: [SyntheticDart]) -> RGBImage {
            var copy = scene
            copy.darts = darts
            return copy.render(camera: camera)
        }
        let empty = render([]), one = render([dart]), two = render([dart, other]), onlyOther = render([other])
        // 0-2 empty; 3-4 in flight; 5-8 vibrating; 9-11 at rest; 12-14 bounce; 15-17 at rest; 18-23 second throw;
        // 24-26 two darts; 27-28 the first falls out; 29-31 the second alone; 32-58 takeout; 59-61 empty.
        #expect(all.count == 62)
        #expect(all[2].makeRGBImage() == empty)
        // The flight is motion: far from both the empty board and the planted dart, and different between frames.
        #expect(all[3].makeRGBImage() != empty && all[4].makeRGBImage() != all[3].makeRGBImage())
        // Vibration: a sub-pixel shift of the planted dart, decaying; then exactly at rest.
        #expect(difference(all[5], Frame(image: one, timestamp: 0)) > difference(all[8], Frame(image: one, timestamp: 0)))
        #expect(all[9].makeRGBImage() == one && all[11].makeRGBImage() == one)
        // Bounce: three frames of motion, then the scene as it was.
        #expect(all[12].makeRGBImage() != one && all[14].makeRGBImage() != one)
        #expect(all[15].makeRGBImage() == one)
        #expect(all[24].makeRGBImage() == two)
        // The first dart falls out.
        #expect(all[27].makeRGBImage() != two && all[29].makeRGBImage() == onlyOther)
        // The takeout: a hand comes in, covers the darts, and leaves an empty board.
        let skin = SIMD3<UInt8>(210, 160, 130)
        let covering = all[32 + 6 + 3].makeRGBImage()
        #expect(covering.pixels.count == empty.pixels.count)
        var skinPixels = 0
        for y in 0..<covering.height {
            for x in 0..<covering.width where covering[x, y] == skin {
                skinPixels += 1
            }
        }
        // About a tenth of the field (part of the disc may be out of view).
        let fraction = Double(skinPixels) / Double(covering.width * covering.height)
        #expect(fraction > 0.06 && fraction < 0.11, "hand covers \(fraction) of the frame")
        #expect(all[59].makeRGBImage() == empty && all[61].makeRGBImage() == empty)
        // The plan: the darts are still there during the first half of the cover, gone in the second half.
        let plan = script.shots(camera: camera, scene: scene)
        #expect(plan.count == 62)
        #expect((32..<45).allSatisfy { plan[$0].geometry.darts == [other] })
        #expect((45..<62).allSatisfy { plan[$0].geometry.darts.isEmpty })
        #expect((32..<59).allSatisfy { plan[$0].geometry.hand != nil } && plan[59].geometry.hand == nil)
        // The hand enters from outside the view.
        let entering = all[32].makeRGBImage()
        var entered = 0
        for y in 0..<entering.height {
            for x in 0..<entering.width where entering[x, y] == skin {
                entered += 1
            }
        }
        #expect(entered < skinPixels / 2)
    }

    @Test func script_handRestBumpAndLight() {
        let scene = SupportScenes.exact()
        let dart = SyntheticDart(tip: BoardPoint(x: 0, y: 103))
        var withDart = scene
        withDart.darts = [dart]
        let delta = SIMD3(1.5, -1.0, 0.0)
        let script = SyntheticScript([.handRest(0.2), .bump(delta: delta, rollDegrees: 0.1), .wait(0.1),
                                      .lightStep(gain: 1.3), .wait(0.1), .lightRamp(gain: 0.7, duration: 0.1), .wait(0.1)])
        let all = frames(SyntheticFrameSource(script: script, camera: camera, scene: withDart))
        // 6 in, 6 at rest, 6 out; 3 of shake; 3; 3; 3 of ramp; 3.
        #expect(all.count == 18 + 3 + 3 + 3 + 3 + 3)
        let skin = SIMD3<UInt8>(210, 160, 130)
        let resting = all[8].makeRGBImage()
        #expect(resting.pixels.count == all[0].makeRGBImage().pixels.count)
        #expect((0..<resting.width).contains { x in (0..<resting.height).contains { resting[x, $0] == skin } })
        #expect(all[8].makeRGBImage() == all[9].makeRGBImage())
        // After the bump, the board is seen by the moved camera.
        let moved = camera.moved(by: delta, rollDegrees: 0.1)
        #expect(all[21].makeRGBImage() == withDart.render(camera: moved))
        #expect(all[21].makeRGBImage() != withDart.render(camera: camera))
        // A light step multiplies the scene's gain; a ramp moves it linearly, frame by frame.
        var brighter = withDart
        brighter.gain = 1.3
        #expect(all[24].makeRGBImage() == brighter.render(camera: moved))
        for (offset, gain) in [(0, 1.3 - 0.6 / 3), (1, 1.3 - 1.2 / 3), (2, 0.7)] {
            var ramp = withDart
            ramp.gain = gain
            #expect(all[27 + offset].makeRGBImage() == ramp.render(camera: moved), "ramp frame \(offset)")
        }
        var dimmer = withDart
        dimmer.gain = 0.7
        #expect(all[30].makeRGBImage() == dimmer.render(camera: moved))
    }

    @Test func frameSource_deliversOnTheQueueAndStops() async throws {
        // In real time: one frame every 1/30 s, so that the stop comes in the middle of the script. Twenty seconds of
        // script: with one second, a busy machine (the whole `swift test` run in parallel) let the 30 frames go out
        // before the test read its fourth one, and the test failed although the source was right.
        let script = SyntheticScript([.wait(20)])
        let source = SyntheticFrameSource(script: script, camera: camera, scene: SupportScenes.exact(), realTime: true)
        let queue = DispatchQueue(label: "imaging.script.test")
        let (stream, continuation) = AsyncStream<TimeInterval>.makeStream()
        try await source.start(on: queue) { frame in
            dispatchPrecondition(condition: .onQueue(queue))
            continuation.yield(frame.timestamp)
        }
        #expect(source.info?.size == camera.imageSize && source.info?.isLive == true)
        var received: [TimeInterval] = []
        for await timestamp in stream {
            received.append(timestamp)
            if received.count == 4 { break }
        }
        await source.stop()
        // Let the queue run whatever was already scheduled: after that, no frame comes any more.
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            queue.async { done.resume() }
        }
        continuation.finish()
        var late: [TimeInterval] = []
        for await timestamp in stream {
            late.append(timestamp)
        }
        let delivered = received + late
        #expect(delivered == (0..<delivered.count).map { Double($0) / 30 })
        #expect(delivered.count < source.frameCount, "\(delivered.count) frames delivered before the stop")
        // Stepping resumes where the delivery stopped.
        #expect(source.nextFrame()?.timestamp == Double(delivered.count) / 30)

        // A source started again delivers the rest of the script.
        let rest = SyntheticFrameSource(script: SyntheticScript([.wait(0.2)]), camera: camera, scene: SupportScenes.exact())
        let (all, sink) = AsyncStream<TimeInterval>.makeStream()
        try await rest.start(on: queue) { sink.yield($0.timestamp) }
        var timestamps: [TimeInterval] = []
        for await timestamp in all {
            timestamps.append(timestamp)
            if timestamps.count == 6 { break }
        }
        #expect(timestamps == (0..<6).map { Double($0) / 30 })
        #expect(rest.nextFrame() == nil)
    }
}
