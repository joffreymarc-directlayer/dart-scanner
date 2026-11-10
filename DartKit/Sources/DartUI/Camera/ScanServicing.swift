import Foundation
import CoreGraphics
import DartCore
import DartVision
#if canImport(AVFoundation)
import AVFoundation
#endif

/// What a preview view can show.
enum PreviewContent: @unchecked Sendable {
    #if canImport(AVFoundation)
    /// Live capture session (iOS: `AVCaptureVideoPreviewLayer`).
    case captureSession(AVCaptureSession)
    #endif
    /// A still or a synthetic frame (Simulator, macOS, SnapshotTool).
    case image(CGImage)
    case none
}

/// Why the camera cannot deliver frames.
enum CameraIssue: Hashable, Sendable {
    case accessDenied
    /// Simulator or device without a back camera.
    case noCamera
    /// iPad multitasking: the camera only runs when the app fills the screen.
    case notFullScreen
    case systemPressure
    case failed(String)
}

/// The camera-side seam of DartUI: a thin main-actor facade over `ScanSession` (VISION.md §9.2, section 8).
/// Calibration, live scan and photo mode talk to this protocol; tests, previews and SnapshotTool use `FakeScanService`.
@MainActor
protocol ScanServicing: AnyObject {
    /// Stable identifier of the frame source ("back-wide", "synthetic"): part of the calibration key.
    var cameraID: String { get }
    var frameInfo: FrameSourceInfo? { get }
    var preview: PreviewContent { get }
    var issue: CameraIssue? { get }
    /// A NEW stream per call.
    func events() -> AsyncStream<ScanEvent>

    /// Asks for camera access if needed, starts the source and the session. Throws `ScanServiceError`.
    func start() async throws
    func stop() async
    /// Mean of the next `frames` frames at full resolution (`ScanSession.captureStill(averaging:)`):
    /// 8 for the frozen still of the calibration screen (device on its stand), 1 for a hand-held photo,
    /// which averaging would blur (VISION.md §8.2). Throws `ScanServiceError`.
    func captureStill(averaging frames: Int) async throws -> RGBImage
    func setCalibration(_ calibration: BoardCalibration) async
    func updateConfiguration(_ configuration: VisionConfiguration) async
    func send(_ command: ScanCommand) async
    func correct(_ id: UUID, tip: BoardPoint) async -> DartObservation?
    func recordFeedback(_ id: UUID, wasCorrected: Bool) async
    func evidenceCrop(for id: UUID) async -> CGImage?
    func runLightingCheck(confirmedTip: BoardPoint) async -> LightingCheckResult?
    func currentState() async -> ScanState
}

struct ScanServiceError: Error, Hashable, Sendable {
    var issue: CameraIssue
}

/// Scripted service, COMPLETE from lot F0 on: it emits the events it is given and records what it receives.
/// `FakeScanService(issue: .noCamera)` is the service of previews, of tests, and of the real application until
/// lot U3 delivers `LiveScanService` (see `ScanServiceFactory`).
@MainActor
final class FakeScanService: ScanServicing {
    // MARK: Script (set by the test)

    /// Still returned by `captureStill`; nil makes it throw.
    var still: RGBImage?
    /// When set, `start()` and `captureStill` throw it.
    var issue: CameraIssue?
    /// Value of `currentState()`; `emit(.stateChanged(_))` updates it.
    var state: ScanState = .needsCalibration
    /// Value returned by `correct(_:tip:)`.
    var correctionResult: DartObservation?
    /// Value returned by `evidenceCrop(for:)`.
    var evidence: CGImage?
    /// Value returned by `runLightingCheck(confirmedTip:)`.
    var lightingCheckResult: LightingCheckResult?

    // MARK: Record (read by the test)

    /// Every command received by `send`, in order.
    private(set) var commands: [ScanCommand] = []
    private(set) var isRunning = false
    /// The `frames` argument of every `captureStill(averaging:)` call.
    private(set) var stillRequests: [Int] = []
    private(set) var calibrations: [BoardCalibration] = []
    private(set) var configurations: [VisionConfiguration] = []
    private(set) var feedback: [(id: UUID, wasCorrected: Bool)] = []
    private(set) var corrections: [(id: UUID, tip: BoardPoint)] = []

    private var continuations: [UUID: AsyncStream<ScanEvent>.Continuation] = [:]

    init(still: RGBImage? = nil, issue: CameraIssue? = nil) {
        self.still = still
        self.issue = issue
    }

    /// Pushes an event to every open stream.
    func emit(_ event: ScanEvent) {
        if case .stateChanged(let newState) = event { state = newState }
        for continuation in continuations.values { continuation.yield(event) }
    }

    var cameraID: String { "fake" }

    var frameInfo: FrameSourceInfo? {
        guard isRunning, let still else { return nil }
        return FrameSourceInfo(size: PixelSize(width: still.width, height: still.height), nominalFramesPerSecond: 30,
                               rotationDegrees: 0, intrinsics: nil, isLive: false)
    }

    var preview: PreviewContent { .none }

    func events() -> AsyncStream<ScanEvent> {
        let id = UUID()
        let (stream, continuation) = AsyncStream.makeStream(of: ScanEvent.self)
        continuations[id] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { @MainActor in self?.continuations[id] = nil }
        }
        return stream
    }

    func start() async throws {
        if let issue { throw ScanServiceError(issue: issue) }
        isRunning = true
    }

    func stop() async {
        isRunning = false
        for continuation in continuations.values { continuation.finish() }
        continuations = [:]
    }

    func captureStill(averaging frames: Int) async throws -> RGBImage {
        stillRequests.append(frames)
        if let issue { throw ScanServiceError(issue: issue) }
        guard let still else { throw ScanServiceError(issue: .noCamera) }
        return still
    }

    func setCalibration(_ calibration: BoardCalibration) async { calibrations.append(calibration) }
    func updateConfiguration(_ configuration: VisionConfiguration) async { configurations.append(configuration) }
    func send(_ command: ScanCommand) async { commands.append(command) }

    func correct(_ id: UUID, tip: BoardPoint) async -> DartObservation? {
        corrections.append((id, tip))
        return correctionResult
    }

    func recordFeedback(_ id: UUID, wasCorrected: Bool) async { feedback.append((id, wasCorrected)) }
    func evidenceCrop(for id: UUID) async -> CGImage? { evidence }
    func runLightingCheck(confirmedTip: BoardPoint) async -> LightingCheckResult? { lightingCheckResult }
    func currentState() async -> ScanState { state }
}
