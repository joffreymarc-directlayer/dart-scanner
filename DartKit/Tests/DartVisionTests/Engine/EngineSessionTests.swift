import CoreVideo
import Foundation
import os
import simd
import Testing
import DartCore
@testable import DartVision

/// `ScanSession` and the frame sources (VISION.md §6, §9.2; ARCHITECTURE.md §11): one queue, ordered commands, a
/// new event stream per read, still capture, heat.
@Suite struct EngineSessionTests {
    /// A small camera: the session tests do not look at darts.
    private static let camera = SyntheticCamera(imageSize: PixelSize(width: 480, height: 270), position: SIMD3(0, -400, 1000))

    @Test func sequenceSource_stepsThenDelivers() async throws {
        let images = (0..<5).map { RGBImage(width: 4, height: 3, fill: SIMD3(UInt8($0 * 10), 0, 0)) }
        let stepping = SequenceFrameSource(frames: images, framesPerSecond: 20)
        #expect(stepping.info == nil)
        let first = try #require(stepping.nextFrame())
        #expect(first.timestamp == 0 && first.size == PixelSize(width: 4, height: 3) && first.makeRGBImage() == images[0])
        #expect(stepping.info == FrameSourceInfo(size: PixelSize(width: 4, height: 3), nominalFramesPerSecond: 20,
                                                 rotationDegrees: 0, intrinsics: nil, isLive: false))
        #expect(stepping.nextFrame()?.timestamp == 0.05)

        let source = SequenceFrameSource(frames: images)
        let seen = OSAllocatedUnfairLock(initialState: [TimeInterval]())
        try await source.start(on: DispatchQueue(label: "EngineSessionTests.sequence")) { frame in
            seen.withLock { $0.append(frame.timestamp) }
        }
        #expect(await EngineSessionTests.wait { seen.withLock { $0.count } == 5 })
        #expect(seen.withLock { $0 } == (0..<5).map { Double($0) / 30 })
        await source.stop()
        #expect(source.nextFrame() == nil)
    }

    @Test func session_newStreamPerReadAndArming() async throws {
        let camera = SupportPoses.b.camera
        let source = SyntheticFrameSource(script: SyntheticScript([.wait(20)]), camera: camera, scene: SupportScenes.empty(seed: 7))
        let session = ScanSession(source: source) { ScanEngine() }
        let first = EngineEventLog(session.events)
        let second = EngineEventLog(session.events)
        await session.setCalibration(camera.calibration())
        try await session.start()
        await session.send(.arm(boardConfirmedEmpty: true))
        #expect(await EngineSessionTests.wait(seconds: 60) { first.events.contains(.stateChanged(.watching(dartsOnBoard: 0))) })
        #expect(await EngineSessionTests.wait { second.events.count >= 3 })
        let expected: [ScanEvent] = [.stateChanged(.idle), .stateChanged(.arming), .stateChanged(.watching(dartsOnBoard: 0))]
        #expect(Array(first.events.prefix(3)) == expected && Array(second.events.prefix(3)) == expected)
        #expect(await session.currentState() == .watching(dartsOnBoard: 0))
        let snapshot = await session.debugSnapshot()
        #expect(snapshot.state == .watching(dartsOnBoard: 0) && snapshot.lastGate != nil && snapshot.noiseSigma > 0)
        // A stream read later sees what comes next only.
        let late = EngineEventLog(session.events)
        await session.send(.pause(.user))
        #expect(await EngineSessionTests.wait { late.events == [.stateChanged(.paused(.user))] })
        await session.stop()
        first.cancel()
        second.cancel()
        late.cancel()
    }

    @Test func session_captureStillAveragesTheNextFrames() async throws {
        let source = EngineManualSource()
        let session = ScanSession(source: source) { ScanEngine() }
        // A loaded test machine may starve the task that pushes the frames: no timeout here.
        session.stillTimeout = 600
        await #expect(throws: (any Error).self) { _ = try await session.captureStill(averaging: 2) }
        try await session.start()
        // Frames of levels 10, 20, 30, ... as RGB, then as BGRA buffers: the still is the mean of four of them.
        let pusher = Task {
            for level in 1...2000 where !Task.isCancelled {
                source.push(RGBImage(width: 6, height: 4, fill: SIMD3(UInt8(level % 25 * 10), 7, 200)), time: Double(level) / 30,
                            asBuffer: level % 2 == 0)
                try? await Task.sleep(nanoseconds: 5_000_000)
            }
        }
        let still = try await session.captureStill(averaging: 4)
        pusher.cancel()
        #expect(still.width == 6 && still.height == 4)
        let red = Int(still.pixels[0])
        #expect(still.pixels.enumerated().allSatisfy { index, value in
            switch index % 3 {
            case 0: return Int(value) == red
            case 1: return value == 7
            default: return value == 200
            }
        })
        // The mean of four consecutive levels 10·k: ends in 5 (or is a level of the wrap-around).
        #expect(red % 5 == 0)
        await session.stop()
        await #expect(throws: (any Error).self) { _ = try await session.captureStill(averaging: 1) }
    }

    /// `send(.arm)` lets a camera converge and lock first; a command sent meanwhile waits for it (ordered commands).
    @Test func session_armLocksTheCameraAndKeepsTheOrder() async throws {
        let source = EngineManualSource(lockDelay: 0.3)
        let session = ScanSession(source: source) { ScanEngine() }
        let log = EngineEventLog(session.events)
        await session.setCalibration(EngineSessionTests.camera.calibration())
        try await session.start()
        let arm = Task { await session.send(.arm(boardConfirmedEmpty: true)) }
        #expect(await EngineSessionTests.wait { source.calls.contains("lockStarted") })
        await session.send(.pause(.background))
        await arm.value
        #expect(source.calls == ["lockStarted", "locked"])
        #expect(await session.currentState() == .paused(.background))
        #expect(await EngineSessionTests.wait { log.events.count >= 3 })
        #expect(log.events == [.stateChanged(.idle), .stateChanged(.arming), .stateChanged(.paused(.background))])
        await session.stop()
        log.cancel()
    }

    @Test func session_heatThrottlesPausesAndResumes() async throws {
        let source = EngineManualSource()
        let session = ScanSession(source: source) { ScanEngine() }
        let level = OSAllocatedUnfairLock(initialState: ProcessInfo.ThermalState.nominal)
        session.thermalState = { level.withLock { $0 } }
        let log = EngineEventLog(session.events)
        let calibration = EngineSessionTests.camera.calibration()
        await session.setCalibration(calibration)
        try await session.start()
        await session.send(.arm(boardConfirmedEmpty: true))
        let image = RGBImage(width: calibration.imageSize.width, height: calibration.imageSize.height, fill: SIMD3(90, 90, 90))
        var time = 0.0
        func push() async {
            time += 1.0 / 30
            source.push(image, time: time)
            _ = await session.currentState()
        }
        level.withLock { $0 = .serious }
        await push()
        await push()
        #expect(log.events.filter { $0 == .advisory(.thermalThrottling) }.count == 1)
        level.withLock { $0 = .critical }
        await push()
        #expect(await session.currentState() == .paused(.thermal))
        await push()
        level.withLock { $0 = .fair }
        await push()
        #expect(await session.currentState() == .arming)
        // A pause of the application is never lifted by the cooling.
        level.withLock { $0 = .critical }
        await push()
        await session.send(.pause(.user))
        level.withLock { $0 = .nominal }
        await push()
        #expect(await session.currentState() == .paused(.user))
        #expect(await EngineSessionTests.wait { log.events.count >= 7 })
        #expect(log.events == [.stateChanged(.idle), .stateChanged(.arming), .advisory(.thermalThrottling),
                               .stateChanged(.paused(.thermal)), .stateChanged(.arming), .stateChanged(.paused(.thermal)),
                               .stateChanged(.paused(.user))])
        await session.stop()
        log.cancel()
    }

    @Test func session_queriesWithoutDartsAnswerNil() async throws {
        let session = ScanSession(source: EngineManualSource()) { ScanEngine() }
        let id = try #require(UUID(uuidString: "00000000-0000-0000-0000-0000000000E5"))
        #expect(await session.correct(id, tip: BoardPoint(x: 0, y: 0)) == nil)
        #expect(await session.evidenceCrop(for: id) == nil)
        #expect(await session.runLightingCheck(confirmedTip: BoardPoint(x: 0, y: 0)) == nil)
        await session.recordFeedback(id, wasCorrected: true)
        var configuration = VisionConfiguration()
        configuration.scan.settleFrames = 7
        await session.updateConfiguration(configuration)
        #expect(await session.currentState() == .needsCalibration)
    }

    #if canImport(AVFoundation)
    @Test func camera_configurationWithoutStarting() {
        let camera = CameraFrameSource()
        #expect(camera.info == nil && !camera.captureSession.isRunning)
        #expect(CameraConfiguration().preset == .uhd4K && CameraConfiguration().framesPerSecond == 30)
        #expect(CameraConfiguration().lockDelay == 1.5 && CameraConfiguration().mainsFrequency == nil)
        #expect(CameraFrameSource.mainsFrequency(forRegion: "FR") == .hz50)
        #expect(CameraFrameSource.mainsFrequency(forRegion: "us") == .hz60)
        #expect(CameraFrameSource.mainsFrequency(forRegion: nil) == .hz50)
        #expect(CameraFrameSource.quarterTurns(90) == 90 && CameraFrameSource.quarterTurns(-90) == 270)
        #expect(CameraFrameSource.quarterTurns(359.9) == 0 && CameraFrameSource.quarterTurns(180) == 180)
    }
    #endif

    // MARK: Helpers

    /// Polls `condition` every 10 ms for at most `seconds` (generous: a loaded machine starves the tasks that read the streams).
    static func wait(seconds: Double = 60, _ condition: @Sendable () -> Bool) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now + .milliseconds(Int(seconds * 1000))
        while clock.now < deadline {
            if condition() { return true }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        return condition()
    }
}

/// Reads an event stream into a list (lot V5 tests).
final class EngineEventLog: Sendable {
    private let state = OSAllocatedUnfairLock(initialState: [ScanEvent]())
    private let task: Task<Void, Never>

    init(_ stream: AsyncStream<ScanEvent>) {
        let state = self.state
        task = Task {
            for await event in stream {
                state.withLock { $0.append(event) }
            }
        }
    }

    var events: [ScanEvent] {
        state.withLock { $0 }
    }

    func cancel() {
        task.cancel()
    }
}

/// A frame source driven by the test, which also plays a camera that locks focus and exposure (lot V5 tests).
final class EngineManualSource: FrameSource, CameraControlling {
    private struct State: Sendable {
        var handler: (@Sendable (Frame) -> Void)?
        var queue: DispatchQueue?
        var size: PixelSize?
        var calls: [String] = []
    }

    private let state = OSAllocatedUnfairLock(initialState: State())
    private let lockDelay: Double

    init(lockDelay: Double = 0) {
        self.lockDelay = lockDelay
    }

    var info: FrameSourceInfo? {
        state.withLock { state in
            state.size.map { FrameSourceInfo(size: $0, nominalFramesPerSecond: 30, rotationDegrees: 0, intrinsics: nil, isLive: true) }
        }
    }

    var calls: [String] {
        state.withLock { $0.calls }
    }

    func start(on queue: DispatchQueue, handler: @escaping @Sendable (Frame) -> Void) async throws {
        state.withLock { state in
            state.handler = handler
            state.queue = queue
            state.size = PixelSize(width: 0, height: 0)
        }
    }

    func stop() async {
        state.withLock { $0.handler = nil }
    }

    /// Delivers one frame on the session queue, as an RGB image or as a 32BGRA buffer.
    func push(_ image: RGBImage, time: TimeInterval, asBuffer: Bool = false) {
        guard let (handler, queue) = state.withLock({ state -> ((@Sendable (Frame) -> Void), DispatchQueue)? in
            guard let handler = state.handler, let queue = state.queue else { return nil }
            return (handler, queue)
        }) else { return }
        queue.async {
            if asBuffer, let buffer = EngineGateTests.pixelBuffer(image), let frame = Frame(pixelBuffer: buffer, timestamp: time) {
                handler(frame)
            } else {
                handler(Frame(image: image, timestamp: time))
            }
        }
    }

    func lockFocusExposureWhiteBalance() async throws -> Bool {
        state.withLock { $0.calls.append("lockStarted") }
        try await Task.sleep(nanoseconds: UInt64(lockDelay * 1_000_000_000))
        state.withLock { $0.calls.append("locked") }
        return true
    }

    func unlock() async {
        state.withLock { $0.calls.append("unlocked") }
    }
}
