import Foundation
import CoreGraphics
import QuartzCore
import Observation
import AVFoundation
import DartCore
import DartVision

/// Real service over `ScanSession`: `CameraFrameSource` on a device, a synthetic demonstration (`SyntheticScene`)
/// in the Simulator and on macOS. `ScanServiceFactory.live()` returns it (ARCHITECTURE.md §8.4.8).
///
/// - the session is created by `start()`, never before: building a service costs nothing and touches no hardware;
/// - `events()` gives a new stream per call; ONE task reads the single stream of the session and forwards it;
/// - capture interruptions and runtime errors pause the vision (`.pause(.background)`) and publish their cause,
///   the end of an interruption resumes it (§6.5, point 2), whatever the state of the game: the state machine
///   ignores a `resume` after the end of a game (VISION.md §6.3, rows P1b and P2c);
/// - a change of the capture angle while the session runs means that the device was moved: the vision is paused
///   with `.pause(.user)`, which `resume` does not lift, and `calibrationLost` is forwarded so that the interface
///   asks for a new calibration (§6.5, point 1).
@MainActor
@Observable
final class LiveScanService: ScanServicing {
    /// "back-wide" for the back camera, "synthetic" for the demonstration: part of the calibration key.
    private(set) var cameraID: String
    private(set) var issue: CameraIssue?
    private(set) var preview: PreviewContent = .none

    @ObservationIgnored private var configuration: VisionConfiguration
    @ObservationIgnored private var session: ScanSession?
    @ObservationIgnored private var source: (any FrameSource)?
    @ObservationIgnored private var capture: CameraFrameSource?
    @ObservationIgnored private var starting: Task<Void, any Error>?
    @ObservationIgnored private var forwarder: Task<Void, Never>?
    @ObservationIgnored private var subscribers: [UUID: AsyncStream<ScanEvent>.Continuation] = [:]
    @ObservationIgnored private var observers: [any NSObjectProtocol] = []
    @ObservationIgnored private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
    @ObservationIgnored private var rotationObservation: NSKeyValueObservation?
    @ObservationIgnored private var captureAngle: Int?
    @ObservationIgnored private var wasMoved = false

    init(configuration: VisionConfiguration = VisionConfiguration()) {
        self.configuration = configuration
        cameraID = LiveScanService.hasBackCamera ? "back-wide" : "synthetic"
    }

    var frameInfo: FrameSourceInfo? {
        source?.info
    }

    /// A NEW stream per call; finished by `stop()`.
    func events() -> AsyncStream<ScanEvent> {
        let (stream, continuation) = AsyncStream.makeStream(of: ScanEvent.self)
        let id = UUID()
        subscribers[id] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { @MainActor [weak self] in self?.subscribers[id] = nil }
        }
        return stream
    }

    /// Asks for camera access if needed, starts the source and the session. Throws `ScanServiceError`:
    /// `.accessDenied` when the access is refused or restricted, `.noCamera` or `.failed` when nothing starts.
    func start() async throws {
        if session != nil { return }
        if let starting {
            try await starting.value
            return
        }
        let task = Task { try await self.open() }
        starting = task
        defer { starting = nil }
        try await task.value
    }

    func stop() async {
        if let starting { _ = try? await starting.value }
        removeObservers()
        let running = session
        session = nil
        source = nil
        capture = nil
        preview = .none
        captureAngle = nil
        wasMoved = false
        forwarder?.cancel()
        forwarder = nil
        await running?.stop()
        for continuation in subscribers.values { continuation.finish() }
        subscribers = [:]
    }

    func captureStill(averaging frames: Int) async throws -> RGBImage {
        guard let session else { throw ScanServiceError(issue: issue ?? .noCamera) }
        do {
            return try await session.captureStill(averaging: frames)
        } catch let error as ScanServiceError {
            throw error
        } catch {
            throw ScanServiceError(issue: .failed(String(describing: error)))
        }
    }

    func setCalibration(_ calibration: BoardCalibration) async {
        await session?.setCalibration(calibration)
    }

    func updateConfiguration(_ configuration: VisionConfiguration) async {
        self.configuration = configuration
        await session?.updateConfiguration(configuration)
    }

    func send(_ command: ScanCommand) async {
        await session?.send(command)
    }

    func correct(_ id: UUID, tip: BoardPoint) async -> DartObservation? {
        await session?.correct(id, tip: tip)
    }

    func recordFeedback(_ id: UUID, wasCorrected: Bool) async {
        await session?.recordFeedback(id, wasCorrected: wasCorrected)
    }

    func evidenceCrop(for id: UUID) async -> CGImage? {
        await session?.evidenceCrop(for: id)
    }

    func runLightingCheck(confirmedTip: BoardPoint) async -> LightingCheckResult? {
        await session?.runLightingCheck(confirmedTip: confirmedTip)
    }

    func currentState() async -> ScanState {
        await session?.currentState() ?? .needsCalibration
    }

    // MARK: Start

    /// A back wide-angle camera exists: an iPhone or an iPad. The Simulator and a Mac have none.
    private static var hasBackCamera: Bool {
        AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) != nil
    }

    private func open() async throws {
        issue = nil
        let source: any FrameSource
        var camera: CameraFrameSource?
        if Self.hasBackCamera {
            if let refused = await Self.accessIssue() {
                issue = refused
                throw ScanServiceError(issue: refused)
            }
            let frames = CameraFrameSource(configuration: CameraConfiguration())
            camera = frames
            source = frames
            cameraID = "back-wide"
        } else {
            source = CameraDemoFrameSource()
            cameraID = "synthetic"
        }
        let configuration = self.configuration
        let session = ScanSession(source: source) {
            ScanEngine(locator: ColourBoardLocator(), configuration: configuration)
        }
        forward(session.events)
        do {
            try await session.start()
        } catch {
            forwarder?.cancel()
            forwarder = nil
            let failure = (error as? ScanServiceError)?.issue ?? (camera == nil ? .noCamera : .failed(String(describing: error)))
            issue = failure
            throw ScanServiceError(issue: failure)
        }
        self.session = session
        self.source = source
        self.capture = camera
        if let camera {
            preview = .captureSession(camera.captureSession)
            captureAngle = source.info?.rotationDegrees
            observe(camera.captureSession)
        } else if let demo = source as? CameraDemoFrameSource, let still = demo.previewFrame?.makeCGImage() {
            preview = .image(still)
        }
    }

    /// What the permission of the camera allows.
    enum Access: Hashable, Sendable {
        case granted
        /// Not determined: the system asks the player, once.
        case ask
        /// Refused by the player, or restricted (parental controls, device management): the camera-denied screen
        /// explains it and the game goes on by hand.
        case refused
    }

    nonisolated static func access(for status: AVAuthorizationStatus) -> Access {
        switch status {
        case .authorized: return .granted
        case .notDetermined: return .ask
        case .denied, .restricted: return .refused
        @unknown default: return .refused
        }
    }

    /// Camera permission: nil when granted, `.accessDenied` when refused or restricted.
    private static func accessIssue() async -> CameraIssue? {
        switch access(for: AVCaptureDevice.authorizationStatus(for: .video)) {
        case .granted: return nil
        case .ask: return await CameraFrameSource.requestAccess() ? nil : .accessDenied
        case .refused: return .accessDenied
        }
    }

    /// ONE task reads the single stream of the session and hands every event to every open stream.
    private func forward(_ events: AsyncStream<ScanEvent>) {
        forwarder?.cancel()
        forwarder = Task { [weak self] in
            for await event in events {
                self?.broadcast(event)
            }
        }
    }

    private func broadcast(_ event: ScanEvent) {
        for continuation in subscribers.values { continuation.yield(event) }
    }

    // MARK: System events (§6.5)

    private func observe(_ captureSession: AVCaptureSession) {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: AVCaptureSession.wasInterruptedNotification, object: captureSession,
                                            queue: .main) { [weak self] notification in
            let cause = CaptureInterruptionObserver.issue(for: notification)
            Task { @MainActor [weak self] in await self?.interrupted(by: cause) }
        })
        observers.append(center.addObserver(forName: AVCaptureSession.interruptionEndedNotification, object: captureSession,
                                            queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in await self?.interruptionEnded() }
        })
        observers.append(center.addObserver(forName: AVCaptureSession.runtimeErrorNotification, object: captureSession,
                                            queue: .main) { [weak self] notification in
            let message = (notification.userInfo?[AVCaptureSessionErrorKey] as? NSError)?.localizedDescription ?? "runtime error"
            Task { @MainActor [weak self] in await self?.interrupted(by: .failed(message)) }
        })
        let device = captureSession.inputs.lazy.compactMap { ($0 as? AVCaptureDeviceInput)?.device }.first
        if let device {
            let coordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: nil)
            rotationCoordinator = coordinator
            rotationObservation = coordinator.observe(\.videoRotationAngleForHorizonLevelCapture, options: [.new]) { [weak self] coordinator, _ in
                let angle = Int(coordinator.videoRotationAngleForHorizonLevelCapture.rounded())
                Task { @MainActor [weak self] in await self?.captureAngleChanged(to: angle) }
            }
        }
    }

    private func removeObservers() {
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers = []
        rotationObservation?.invalidate()
        rotationObservation = nil
        rotationCoordinator = nil
    }

    private func interrupted(by cause: CameraIssue) async {
        guard let session else { return }
        issue = cause
        await session.send(.pause(.background))
    }

    private func interruptionEnded() async {
        guard let session else { return }
        issue = nil
        await session.send(.resume)
    }

    /// The device turned: a calibration is only valid for its `rotationDegrees` (§6.5, point 1).
    private func captureAngleChanged(to angle: Int) async {
        guard let session, let captureAngle, !wasMoved, ((angle - captureAngle) % 360 + 360) % 360 != 0 else { return }
        wasMoved = true
        await session.send(.pause(.user))
        broadcast(.calibrationLost)
    }
}
