import Foundation
import simd
import CoreGraphics
import CoreVideo
import DartCore
import os

/// Thin concurrency wrapper: one serial queue, one frame source, one engine, one stream of events.
///
/// - **One queue.** The engine is touched only on the session's serial queue, which is also the queue the source
///   delivers its frames on (`FrameSource.start(on:handler:)`). Every `async` method hops onto it.
/// - **Ordered commands.** `setCalibration`, `updateConfiguration`, `send` and `recordFeedback` are applied in the
///   order they are called, one at a time: `send(.arm)` first lets a camera source converge and lock focus, exposure
///   and white balance (VISION.md §2.4), and a command sent meanwhile waits for it.
/// - **Events.** Each read of `events` returns a NEW stream that receives every event emitted from then on; a stream
///   ends when its reader cancels it, or when the session is released.
/// - **Heat** (VISION.md §2.4): at `ProcessInfo.ThermalState.serious` one frame in two is processed and
///   `advisory(.thermalThrottling)` is emitted; at `.critical` the session sends `pause(.thermal)`, and `resume`
///   once the device cooled down, if the machine is still in that pause.
public final class ScanSession: @unchecked Sendable {
    public init(source: any FrameSource, makeEngine: @escaping @Sendable () -> ScanEngine) {
        self.source = source
        self.engine = makeEngine()
        self.thermalState = { ProcessInfo.processInfo.thermalState }
    }

    public var events: AsyncStream<ScanEvent> {
        let (stream, continuation) = AsyncStream.makeStream(of: ScanEvent.self, bufferingPolicy: .unbounded)
        let id = subscribers.withLock { state in
            state.next += 1
            state.list.append((state.next, continuation))
            return state.next
        }
        continuation.onTermination = { [weak self] _ in
            self?.subscribers.withLock { state in state.list.removeAll { $0.id == id } }
        }
        return stream
    }

    public func start() async throws {
        let alreadyRunning = status.withLock { state -> Bool in
            if state.running || state.starting { return true }
            state.starting = true
            return false
        }
        guard !alreadyRunning else { return }
        do {
            await onQueue { session in session.engine.restartGate() }
            try await source.start(on: queue) { [weak self] frame in
                self?.receive(frame)
            }
            status.withLock { state in
                state.starting = false
                state.running = true
            }
        } catch {
            status.withLock { $0.starting = false }
            throw error
        }
    }

    public func stop() async {
        await source.stop()
        status.withLock { $0.running = false }
        await onQueue { session in
            session.failStills(ScanSessionError.stopped)
            session.engine.restartGate()
        }
    }

    /// Mean of the next `frames` frames at full resolution: the frozen still for the calibration screen.
    public func captureStill(averaging frames: Int = 8) async throws -> RGBImage {
        guard status.withLock({ $0.running }) else { throw ScanSessionError.notRunning }
        let count = min(ScanSession.maximumStillFrames, max(1, frames))
        let nominal = source.info?.nominalFramesPerSecond ?? 30
        let rate = nominal.isFinite && nominal > 0 ? nominal : 30
        let timeout = stillTimeout + Double(count) / rate * 3
        return try await withCheckedThrowingContinuation { continuation in
            queue.async { [self] in
                stillSerial += 1
                let id = stillSerial
                stills.append(ScanSessionStill(id: id, frames: count, continuation: continuation))
                queue.asyncAfter(deadline: .now() + timeout) { [self] in
                    failStill(id, ScanSessionError.noFrames)
                }
            }
        }
    }

    public func setCalibration(_ calibration: BoardCalibration) async {
        await ordered { session in
            await session.onQueue { $0.broadcast($0.engine.setCalibration(calibration)) }
        }
    }

    public func send(_ command: ScanCommand) async {
        await ordered { session in
            if case .arm = command, session.status.withLock({ $0.running }),
               let camera = session.source as? any CameraControlling {
                _ = try? await camera.lockFocusExposureWhiteBalance()
            }
            await session.onQueue { $0.broadcast($0.engine.handle(command)) }
        }
    }

    public func correct(_ id: UUID, tip: BoardPoint) async -> DartObservation? {
        await onQueue { $0.engine.correct(id, tip: tip) }
    }

    public func recordFeedback(_ id: UUID, wasCorrected: Bool) async {
        await ordered { session in
            await session.onQueue { session in
                session.engine.recordFeedback(id, wasCorrected: wasCorrected)
                session.broadcast(session.engine.takePendingEvents())
            }
        }
    }

    public func evidenceCrop(for id: UUID, span: Double = 50, scale: Double = 6) async -> CGImage? {
        let crop = await onQueue { $0.engine.evidenceCrop(for: id, span: span, scale: scale) }
        return crop?.makeCGImage()
    }

    public func runLightingCheck(confirmedTip: BoardPoint) async -> LightingCheckResult? {
        await onQueue { $0.engine.runLightingCheck(confirmedTip: confirmedTip) }
    }

    public func updateConfiguration(_ configuration: VisionConfiguration) async {
        await ordered { session in
            await session.onQueue { session in
                session.engine.configuration = configuration
                session.broadcast(session.engine.takePendingEvents())
            }
        }
    }

    public func currentState() async -> ScanState {
        await onQueue { $0.engine.state }
    }

    public func debugSnapshot() async -> ScanDebugSnapshot {
        await onQueue { $0.engine.debugSnapshot() }
    }

    // MARK: - Internal state (lot V5)

    let source: any FrameSource
    /// The engine; touched only on `queue`.
    let engine: ScanEngine
    let queue = DispatchQueue(label: "DartVision.ScanSession", qos: .userInitiated)
    /// Reads the thermal state of the device; replaced in tests before `start`.
    var thermalState: @Sendable () -> ProcessInfo.ThermalState
    /// Seconds a still may wait for its frames beyond their own duration; set in tests before `start`.
    var stillTimeout: TimeInterval = 5
    private let commands = ScanSessionCommandLine()
    private let subscribers = OSAllocatedUnfairLock(initialState: ScanSessionSubscribers())
    private let status = OSAllocatedUnfairLock(initialState: ScanSessionStatus())

    // Touched only on `queue`.
    private var stills: [ScanSessionStill] = []
    private var stillSerial = 0
    private var throttling = false
    private var skipNextFrame = false
    private var pausedForHeat = false

    deinit {
        let list = subscribers.withLock { $0.list }
        for (_, continuation) in list {
            continuation.finish()
        }
    }
}

/// Why a session call failed (lot V5).
enum ScanSessionError: Error, Sendable {
    /// `captureStill` before `start`.
    case notRunning
    /// The session was stopped while a still was being captured.
    case stopped
    /// No frame arrived in time.
    case noFrames
}

/// Open event streams (lot V5).
struct ScanSessionSubscribers: Sendable {
    var next = 0
    var list: [(id: Int, continuation: AsyncStream<ScanEvent>.Continuation)] = []
}

/// Running state of the source (lot V5).
struct ScanSessionStatus: Sendable {
    var running = false
    var starting = false
}

/// A still being averaged (lot V5).
struct ScanSessionStill: Sendable {
    var id: Int
    var frames: Int
    var added = 0
    var size: PixelSize?
    var sums: [UInt16] = []
    var continuation: CheckedContinuation<RGBImage, any Error>
}

/// Runs the ordered operations of a session one at a time, in call order (lot V5).
actor ScanSessionCommandLine {
    private var busy = false
    private var waiting: [CheckedContinuation<Void, Never>] = []

    func acquire() async {
        guard busy else {
            busy = true
            return
        }
        await withCheckedContinuation { continuation in
            waiting.append(continuation)
        }
    }

    func release() {
        if waiting.isEmpty {
            busy = false
        } else {
            waiting.removeFirst().resume()
        }
    }
}

// MARK: - Queue work (lot V5)

extension ScanSession {
    /// Frames a still can average: 16-bit sums hold 257 frames of 255.
    static let maximumStillFrames = 257

    /// Runs `body` on the session queue and returns its result.
    func onQueue<T: Sendable>(_ body: @escaping @Sendable (ScanSession) -> T) async -> T {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                continuation.resume(returning: body(self))
            }
        }
    }

    /// Runs an ordered operation: after every earlier one, before every later one.
    func ordered(_ body: @Sendable (ScanSession) async -> Void) async {
        await commands.acquire()
        await body(self)
        await commands.release()
    }

    /// Yields events to every open stream.
    func broadcast(_ events: [ScanEvent]) {
        guard !events.isEmpty else { return }
        let list = subscribers.withLock { $0.list }
        for event in events {
            for (_, continuation) in list {
                continuation.yield(event)
            }
        }
    }

    /// One frame from the source, on the queue.
    func receive(_ frame: Frame) {
        serveStills(frame)
        switch thermalState() {
        case .critical:
            if case .paused = engine.state {} else {
                pausedForHeat = true
                broadcast(engine.handle(.pause(.thermal)))
            }
            return
        case .serious:
            if !throttling {
                throttling = true
                broadcast([.advisory(.thermalThrottling)])
            }
            liftHeatPause()
            skipNextFrame.toggle()
            if !skipNextFrame { return }
        default:
            throttling = false
            skipNextFrame = false
            liftHeatPause()
        }
        broadcast(engine.process(frame))
    }

    private func liftHeatPause() {
        guard pausedForHeat else { return }
        pausedForHeat = false
        if engine.state == .paused(.thermal) { broadcast(engine.handle(.resume)) }
    }

    // MARK: Stills

    private func serveStills(_ frame: Frame) {
        guard !stills.isEmpty else { return }
        var finished: [(CheckedContinuation<RGBImage, any Error>, RGBImage)] = []
        for index in stills.indices {
            if stills[index].size != frame.size {
                stills[index].size = frame.size
                stills[index].added = 0
                stills[index].sums = [UInt16](repeating: 0, count: max(0, frame.size.width * frame.size.height * 3))
            }
            ScanSession.add(frame, to: &stills[index].sums)
            stills[index].added += 1
            if stills[index].added >= stills[index].frames {
                finished.append((stills[index].continuation, ScanSession.mean(stills[index])))
            }
        }
        stills.removeAll { $0.added >= $0.frames }
        for (continuation, image) in finished {
            continuation.resume(returning: image)
        }
    }

    private func failStill(_ id: Int, _ error: ScanSessionError) {
        guard let index = stills.firstIndex(where: { $0.id == id }) else { return }
        let still = stills.remove(at: index)
        still.continuation.resume(throwing: error)
    }

    func failStills(_ error: ScanSessionError) {
        let pending = stills
        stills = []
        for still in pending {
            still.continuation.resume(throwing: error)
        }
    }

    /// Adds the R, G, B bytes of a frame to `sums` (`width × height × 3` values).
    private static func add(_ frame: Frame, to sums: inout [UInt16]) {
        let width = frame.size.width, height = frame.size.height
        guard width > 0, height > 0, sums.count == width * height * 3 else { return }
        let stride = frame.bytesPerPixel, red = frame.redOffset
        frame.withUnsafeBytes { bytes, bytesPerRow in
            guard let base = bytes.baseAddress, bytesPerRow >= width * stride, bytes.count >= bytesPerRow * height else { return }
            let source = base.assumingMemoryBound(to: UInt8.self)
            sums.withUnsafeMutableBufferPointer { total in
                for y in 0..<height {
                    var pixel = source + y * bytesPerRow
                    var index = y * width * 3
                    for _ in 0..<width {
                        total[index] &+= UInt16(pixel[red])
                        total[index + 1] &+= UInt16(pixel[1])
                        total[index + 2] &+= UInt16(pixel[2 - red])
                        pixel += stride
                        index += 3
                    }
                }
            }
        }
    }

    private static func mean(_ still: ScanSessionStill) -> RGBImage {
        let size = still.size ?? PixelSize(width: 0, height: 0)
        let count = UInt32(max(1, still.added)), half = count / 2
        let pixels = still.sums.map { UInt8(min(255, (UInt32($0) + half) / count)) }
        return RGBImage(width: max(0, size.width), height: max(0, size.height), pixels: pixels)
    }
}
