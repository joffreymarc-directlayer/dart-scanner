import Foundation
import Observation
import DartCore
import DartVision

/// State of the camera shared by the home card, the calibration screen, the live scan and the photo mode.
/// Lot U3 owns this file (ARCHITECTURE.md §8.4.8); the printed signatures are kept as they are. Behaviour: §8.7.
///
/// - `activate()` starts the service and revalidates the calibration saved for this camera (VISION.md §4.10);
/// - `enqueue(_:)` and `enqueueFeedback(_:wasCorrected:)` feed THE command queue of DartUI: one `AsyncStream`
///   read by one task, which awaits each operation before taking the next (§8.7, §11);
/// - the model listens to the service for the calibration the vision adjusts or recovers by itself, and saves it.
@MainActor
@Observable
final class CameraModel {
    enum Readiness: Hashable, Sendable {
        /// Never asked, or not started yet.
        case unknown
        case unavailable(CameraIssue)
        /// Frames arrive, no valid calibration.
        case needsCalibration
        /// Calibrated; `grade` is shown on the home card.
        case ready(grade: CalibrationQuality.Grade)
    }

    let service: any ScanServicing
    private let storage: AppStorage
    private(set) var readiness: Readiness = .unknown
    private(set) var calibration: BoardCalibration?
    private(set) var scanState: ScanState = .needsCalibration
    private(set) var lightingCheckPassed = false

    /// Configuration installed in the service with the calibration: the shadow bound of the one-dart check and
    /// the warm-up it makes useless travel with it (VISION.md §4.8, §4.10).
    private(set) var configuration = VisionConfiguration()
    /// The calibration saved for this camera, even when it no longer fits the board: the calibration screen
    /// starts from its handles (VISION.md §4.10, "poignées pré-placées aux anciennes positions").
    private(set) var savedCalibration: BoardCalibration?
    /// True between a successful `activate()` and `deactivate()`.
    private(set) var isActive = false
    /// Shadow bound measured by the last one-dart check, adopted with `adopt(_:lightingCheckPassed: true)`.
    @ObservationIgnored private var checkedShadowLowerBound: Double?

    /// The single command queue (§8.7): two kinds of operations, read by ONE task.
    private enum Operation: Sendable {
        case command(ScanCommand)
        case feedback(UUID, wasCorrected: Bool)
    }

    @ObservationIgnored private let operations: AsyncStream<Operation>.Continuation
    /// The stream until the task that reads it is started (on the first deposit).
    @ObservationIgnored private var waitingOperations: AsyncStream<Operation>?
    @ObservationIgnored private var queueTask: Task<Void, Never>?
    @ObservationIgnored private var deposited = 0
    @ObservationIgnored private var delivered = 0
    @ObservationIgnored private var drainWaiters: [CheckedContinuation<Void, Never>] = []

    @ObservationIgnored private var activation: Task<Void, Never>?
    @ObservationIgnored private var listener: Task<Void, Never>?

    init(service: any ScanServicing, storage: AppStorage) {
        self.service = service
        self.storage = storage
        let (stream, continuation) = AsyncStream.makeStream(of: Operation.self)
        operations = continuation
        waitingOperations = stream
    }

    deinit {
        // Ends the task of the queue once what was deposited has been delivered.
        operations.finish()
    }

    // MARK: Life cycle

    /// Starts the service and, when a calibration is stored for this camera, revalidates it on a fresh still
    /// (`assess`, then `recover`) and installs it in the service: VISION.md §4.10. Idempotent: does nothing when
    /// the service already runs, and a call made while another one is running waits for the same result.
    func activate() async {
        if let activation {
            await activation.value
            return
        }
        guard !isActive else { return }
        let task = Task { await self.performActivation() }
        activation = task
        await task.value
        activation = nil
    }

    /// Stops the session when the camera is no longer needed (ARCHITECTURE.md §8.7, "Cycle de vie").
    func deactivate() async {
        if let activation { await activation.value }
        guard isActive else { return }
        isActive = false
        listener?.cancel()
        listener = nil
        await service.stop()
        readiness = .unknown
    }

    // MARK: Command queue

    /// The ONLY way a `ScanCommand` goes from DartUI to the vision layer: every `CameraInputSource`, the photo
    /// mode, the calibration flow and `setForeground` deposit here, and ONE task of this model awaits
    /// `service.send(_:)` for each command before taking the next. The vision layer therefore receives the
    /// commands in the exact order of the calls, whoever makes them (ARCHITECTURE.md §8.7, §11).
    /// Synchronous: the caller never waits.
    func enqueue(_ command: ScanCommand) {
        deposit(.command(command))
    }

    /// Same queue, same order: `service.recordFeedback(id, wasCorrected:)`.
    func enqueueFeedback(_ id: UUID, wasCorrected: Bool) {
        deposit(.feedback(id, wasCorrected: wasCorrected))
    }

    /// Returns once every operation deposited so far has been delivered to the service. Nothing in the
    /// application waits for the queue; tests and the flows that read the service right after a command do.
    func drainQueue() async {
        guard delivered < deposited else { return }
        await withCheckedContinuation { drainWaiters.append($0) }
    }

    /// Scene phase (`AppModel.setForeground`): deposits `.pause(.background)` when the app leaves the foreground
    /// and `.resume` when it comes back, with `enqueue`. Both always leave: the state machine decides
    /// (VISION.md §6.3, rows P2b and P2c).
    func setForeground(_ active: Bool) {
        enqueue(active ? .resume : .pause(.background))
    }

    // MARK: Calibration

    /// Saves and installs a calibration validated by the player (ARCHITECTURE.md §8.7, steps 8 and 9).
    /// With `lightingCheckPassed`, the shadow bound of the one-dart check goes with it and the warm-up cap of the
    /// first three darts is dropped (VISION.md §4.8); without, both are the defaults of a new installation.
    func adopt(_ calibration: BoardCalibration, lightingCheckPassed: Bool) async {
        var next = configuration
        let defaults = VisionConfiguration()
        if lightingCheckPassed {
            next.detection.shadowLowerBound = checkedShadowLowerBound ?? next.detection.shadowLowerBound
            next.confidence.warmUpDarts = 0
        } else {
            next.detection.shadowLowerBound = defaults.detection.shadowLowerBound
            next.confidence.warmUpDarts = defaults.confidence.warmUpDarts
        }
        // The configuration goes first: the engine sets the warm-up cap of a calibration from the configuration in
        // place when the calibration is installed (VISION.md §6.5), and a later configuration does not change it.
        await service.updateConfiguration(next)
        // Installing the very same calibration again would reset the vision (VISION.md §6.3, row 1): after the
        // one-dart check only the configuration changes.
        if self.calibration != calibration {
            await service.setCalibration(calibration)
        }
        self.calibration = calibration
        self.lightingCheckPassed = lightingCheckPassed
        configuration = next
        savedCalibration = calibration
        storage.save(StoredCalibration(cameraID: service.cameraID, calibration: calibration, configuration: next,
                                       lightingCheckPassed: lightingCheckPassed))
        readiness = .ready(grade: calibration.quality.grade)
    }

    /// Remembers the shadow bound of a one-dart check for the next `adopt(_:lightingCheckPassed: true)`.
    func recordLightingCheck(_ result: LightingCheckResult) {
        checkedShadowLowerBound = result.recommendedShadowLowerBound
    }

    func forgetCalibration() {
        calibration = nil
        lightingCheckPassed = false
        if isActive { readiness = .needsCalibration }
    }

    // MARK: Sources

    /// The automatic dart source for a game, for the given mode (`.live`: automatic trigger; `.photo`: manual
    /// trigger). Returns a source as soon as the camera is not known to be unavailable (`service.issue == nil`),
    /// WHATEVER `readiness`: after a cold start `readiness` is still `.unknown` when the game is created, and
    /// the play screen awaits `activate()` before the game starts (ARCHITECTURE.md §8.6, step 0). Without a
    /// valid calibration the source reports `.needsCalibration`. Nil only when `service.issue != nil`.
    func makeInputSource(mode: ScanMode) -> (any DartInputSource)? {
        guard service.issue == nil else { return nil }
        let source = CameraInputSource(camera: self, mode: mode)
        inputSource = source
        return source
    }

    /// The last source made by `makeInputSource(mode:)`, while its game holds it: the photo mode counts the darts
    /// of a scan with its thresholds, raised for the rest of the game after `accuracyDegraded` (§8.7).
    @ObservationIgnored private(set) weak var inputSource: CameraInputSource?

    // MARK: Events of the service

    /// What the model does with one event of the service: the state for the thumbnail, and the calibrations the
    /// vision changed by itself, which are saved (§8.7, table "Événements"; §8.10).
    func handle(_ event: ScanEvent) {
        switch event {
        case .stateChanged(let state):
            scanState = state
            if state == .calibrationLost { calibrationWasLost() }
        case .calibrationAdjusted(let adjusted), .calibrationRecovered(let adjusted):
            calibration = adjusted
            savedCalibration = adjusted
            storage.save(StoredCalibration(cameraID: service.cameraID, calibration: adjusted, configuration: configuration,
                                           lightingCheckPassed: lightingCheckPassed))
            readiness = .ready(grade: adjusted.quality.grade)
        case .calibrationLost:
            calibrationWasLost()
        default:
            break
        }
    }

    // MARK: Private

    private func calibrationWasLost() {
        if case .ready = readiness { readiness = .needsCalibration }
    }

    private func deposit(_ operation: Operation) {
        startQueueIfNeeded()
        deposited += 1
        operations.yield(operation)
    }

    private func startQueueIfNeeded() {
        guard queueTask == nil, let stream = waitingOperations else { return }
        waitingOperations = nil
        let service = self.service
        queueTask = Task { [weak self] in
            for await operation in stream {
                switch operation {
                case .command(let command):
                    await service.send(command)
                case .feedback(let id, let wasCorrected):
                    await service.recordFeedback(id, wasCorrected: wasCorrected)
                }
                self?.operationDelivered()
            }
        }
    }

    private func operationDelivered() {
        delivered += 1
        guard delivered >= deposited else { return }
        let waiters = drainWaiters
        drainWaiters = []
        for waiter in waiters { waiter.resume() }
    }

    private func performActivation() async {
        do {
            try await service.start()
        } catch {
            readiness = .unavailable((error as? ScanServiceError)?.issue ?? service.issue ?? .noCamera)
            return
        }
        isActive = true
        listen()
        await revalidate()
    }

    /// One task of the model reads the events of the service while it runs.
    private func listen() {
        listener?.cancel()
        let events = service.events()
        listener = Task { [weak self] in
            for await event in events {
                self?.handle(event)
            }
        }
    }

    /// VISION.md §4.10: a fresh still, `assess`, `recover` when drifted; healthy or recovered, the calibration and
    /// its configuration are installed, otherwise the player calibrates again from the old handles.
    private func revalidate() async {
        guard let info = service.frameInfo,
              let stored = storage.loadCalibration(cameraID: service.cameraID, rotationDegrees: info.rotationDegrees,
                                                   imageSize: info.size) else {
            calibration = nil
            readiness = .needsCalibration
            return
        }
        // Every activation revalidates: the board or the stand may have moved while the camera was stopped, and a
        // service started again has no calibration installed.
        savedCalibration = stored.calibration
        let still: RGBImage
        do {
            still = try await service.captureStill(averaging: 8)
        } catch {
            calibration = nil
            readiness = .needsCalibration
            return
        }
        let candidate = stored.calibration
        let checked = await Task.detached(priority: .userInitiated) {
            CameraModel.revalidated(candidate, on: still)
        }.value
        guard let valid = checked else {
            calibration = nil
            readiness = .needsCalibration
            return
        }
        // Configuration first, as in `adopt`: a calibration saved after a verified one-dart check carries
        // `warmUpDarts = 0`, which the engine reads when the calibration is installed.
        await service.updateConfiguration(stored.configuration)
        await service.setCalibration(valid)
        calibration = valid
        lightingCheckPassed = stored.lightingCheckPassed
        configuration = stored.configuration
        if valid != stored.calibration {
            savedCalibration = valid
            storage.save(StoredCalibration(cameraID: stored.cameraID, calibration: valid, configuration: stored.configuration,
                                           lightingCheckPassed: stored.lightingCheckPassed))
        }
        readiness = .ready(grade: valid.quality.grade)
    }

    /// The saved calibration if it still fits the still, the recovered one if it drifted, nil otherwise.
    nonisolated static func revalidated(_ calibration: BoardCalibration, on still: RGBImage) -> BoardCalibration? {
        let calibrator = BoardCalibrator(parameters: CalibrationParameters())
        switch calibrator.assess(calibration, on: still, dartsOnBoard: false).status {
        case .healthy:
            return calibration
        case .drifted:
            return calibrator.recover(calibration, on: still)
        case .lost, .edgesNotVisible:
            return nil
        }
    }
}

/// Where the real application gets its scan service. `AppEnvironment.live()` calls it and never names a
/// concrete type, so that lot U1 does not wait for lot U3.
enum ScanServiceFactory {
    /// The real service: the back camera on a device, the synthetic demonstration in the Simulator.
    @MainActor static func live() -> any ScanServicing { LiveScanService() }
}
