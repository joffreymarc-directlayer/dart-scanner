import Foundation
import CoreGraphics
import DartCore
import DartVision

/// Adapts the scan service of a `CameraModel` to `DartInputSource` by the two tables of ARCHITECTURE.md §8.7.
/// `mode` fixes the trigger: `.live` = automatic, `.photo` = manual.
/// Reads `camera.service.events()`. Deposits every command with `camera.enqueue(_:)` and every feedback with
/// `camera.enqueueFeedback(_:wasCorrected:)`: it never calls `service.send` itself and owns no queue.
/// Created by `CameraModel.makeInputSource(mode:)`.
@MainActor
final class CameraInputSource: DartInputSource {
    private let camera: CameraModel
    private let mode: ScanMode
    /// `.standard`, raised for the rest of the game by `advisory(.accuracyDegraded)` (§8.7, "Seuils de palier").
    private(set) var thresholds: ConfidenceThresholds
    /// A source is born `.preparing` (§8.7, "Statut d'une source avant le premier stateChanged").
    private(set) var status: InputStatus = .preparing
    /// `needsEmptyBoard` is kept until `stateChanged(.arming)` or the loss of the calibration (§8.7).
    private var keepsEmptyBoardRequest = false
    /// "Pas encore" (`gameStarted(boardConfirmedEmpty: false)`): the board may still hold darts, so the vision is
    /// NOT armed until the player confirms it empty (`boardConfirmedEmpty()`); the status stays `.needsEmptyBoard`
    /// (`.needsCalibration` without a calibration) and nothing the vision reports is a dart of the game (§8.7).
    private var awaitsEmptyBoard = false
    /// The visit as the game last described it (`beginVisit(n)`, less the darts entered by hand since, or
    /// `endVisit`), deposited again after the arming of a confirmation: `arm` resets the counters of the vision.
    private var visit: ScanCommand?
    /// Identifiers already reported to the vision: one feedback per dart (§8.7).
    private var reported: Set<UUID> = []
    private var subscribers: [UUID: AsyncStream<DartInputEvent>.Continuation] = [:]
    private var reader: Task<Void, Never>?
    private var stateCheck: Task<Void, Never>?
    private var hasEnded = false

    init(camera: CameraModel, mode: ScanMode, thresholds: ConfidenceThresholds = .standard) {
        self.camera = camera
        self.mode = mode
        self.thresholds = thresholds
    }

    // MARK: Events

    /// A NEW stream per call; finishes when the source stops (`gameEnded`) or when the service stops.
    /// The events of the service are read by ONE task of the source, opened by the first call.
    func events() -> AsyncStream<DartInputEvent> {
        let (stream, continuation) = AsyncStream.makeStream(of: DartInputEvent.self)
        guard !hasEnded else {
            continuation.finish()
            return stream
        }
        let id = UUID()
        subscribers[id] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { @MainActor [weak self] in self?.subscribers[id] = nil }
        }
        startReading()
        return stream
    }

    // MARK: Commands (table "Commandes" of §8.7)

    func gameStarted(boardConfirmedEmpty: Bool) {
        guard !hasEnded else { return }
        startReading()
        if camera.service.issue != nil {
            // Access refused or camera lost during `activate()`: the game is played by hand.
            publish(.unavailable)
            return
        }
        guard boardConfirmedEmpty else {
            // Arming now would take the darts still in the board into the references: pulling them out would
            // then read as darts. The vision waits, unarmed, for "Elle est vide".
            awaitsEmptyBoard = true
            checkStateWhileAwaiting()
            return
        }
        arm()
    }

    func turnBegan(expectedDarts: Int) {
        visit = .beginVisit(expectedDarts: expectedDarts)
        guard !awaitsEmptyBoard else { return }
        camera.enqueue(.beginVisit(expectedDarts: expectedDarts))
    }

    func turnClosed() {
        visit = .endVisit
        guard !awaitsEmptyBoard else { return }
        camera.enqueue(.endVisit)
    }

    func dartDiscarded(_ id: UUID) {
        camera.enqueue(.discardDart(id))
    }

    func manualDartAdded() {
        if case .beginVisit(let expected) = visit {
            visit = .beginVisit(expectedDarts: max(0, expected - 1))
        }
        guard !awaitsEmptyBoard else { return }
        camera.enqueue(.registerManualDart)
    }

    func turnConfirmed(_ feedback: [DartFeedback]) {
        for item in feedback where !reported.contains(item.id) {
            reported.insert(item.id)
            camera.enqueueFeedback(item.id, wasCorrected: item.wasCorrected)
        }
    }

    func boardConfirmedEmpty() {
        guard awaitsEmptyBoard else {
            camera.enqueue(.confirmBoardEmpty)
            return
        }
        // First arming of this game, on the board the player has just emptied, then the visit of the game.
        guard !hasEnded, camera.service.issue == nil else { return }
        awaitsEmptyBoard = false
        keepsEmptyBoardRequest = true
        arm()
        if let visit { camera.enqueue(visit) }
    }

    func gameEnded() {
        guard !hasEnded else { return }
        hasEnded = true
        camera.enqueue(.pause(.user))
        stateCheck?.cancel()
        reader?.cancel()
        reader = nil
        for continuation in subscribers.values { continuation.finish() }
        subscribers = [:]
    }

    // MARK: Queries (outside the queue)

    func evidenceImage(for id: UUID) async -> CGImage? {
        await camera.service.evidenceCrop(for: id)
    }

    func rescore(_ id: UUID, tip point: BoardPoint) async -> DartProposal? {
        guard let observation = await camera.service.correct(id, tip: point) else { return nil }
        return DartProposal(observation: observation, thresholds: thresholds)
    }

    // MARK: Table "Événements" of §8.7

    /// What one event of the vision becomes for the game. Updates `status` (published only when it changes),
    /// the kept `needsEmptyBoard` request and the thresholds.
    func translate(_ event: ScanEvent) -> [DartInputEvent] {
        if awaitsEmptyBoard {
            return translateWhileAwaiting(event)
        }
        switch event {
        case .stateChanged(let state):
            return statusEvents(for: state)
        case .calibrationLost:
            keepsEmptyBoardRequest = false
            return change(to: .needsCalibration)
        case .needsEmptyBoard:
            keepsEmptyBoardRequest = true
            return change(to: .needsEmptyBoard)
        case .dart(let observation):
            return [.dart(DartProposal(observation: observation, thresholds: thresholds))]
        case .dartDisturbed(let id):
            return [.dartDisturbed(id: id)]
        case .dartRemoved(let id, let reason):
            return [.dartRemoved(id: id, reason: reason == .fellOut ? .fellOut : .takeout)]
        case .possibleMiss:
            return [.possibleMiss]
        case .takeoutCompleted:
            return [.boardCleared]
        case .advisory(let advisory):
            if advisory == .accuracyDegraded {
                thresholds.high = VisionConfiguration().confidence.degradedHighThreshold
            }
            return [.advisory(CameraText.advice(for: advisory))]
        case .takeoutStalled, .lightingChanged, .unrecognizedChange:
            return CameraText.advice(for: event, mode: mode).map { [.advisory($0)] } ?? []
        case .takeoutStarted, .calibrationAdjusted, .calibrationRecovered, .scanCompleted:
            // The model saves the calibrations; the photo mode reads `scanCompleted` from its own stream.
            return []
        }
    }

    /// Status of a state of the vision, for a mode (rows `stateChanged` of the table).
    static func status(for state: ScanState, mode: ScanMode) -> InputStatus {
        switch state {
        case .idle, .arming:
            return .preparing
        case .watching, .awaitingTakeout:
            return mode == .photo ? .awaitingCapture : .live
        case .motion, .settling, .analysing, .takeout:
            return mode == .photo ? .preparing : .live
        case .obstructed:
            return .obstructed
        case .paused:
            return .paused
        case .needsCalibration, .calibrationLost:
            return .needsCalibration
        }
    }

    // MARK: Private

    /// `setTrigger` for the mode of the game, then `arm(boardConfirmedEmpty: true)`.
    private func arm() {
        camera.enqueue(.setTrigger(mode == .live ? .automatic : .manual))
        camera.enqueue(.arm(boardConfirmedEmpty: true))
        checkStateAfterArming()
    }

    /// Before the board is confirmed empty: only the calibration, its loss and the advice reach the game.
    private func translateWhileAwaiting(_ event: ScanEvent) -> [DartInputEvent] {
        switch event {
        case .stateChanged(let state):
            return change(to: state == .needsCalibration || state == .calibrationLost ? .needsCalibration : .needsEmptyBoard)
        case .calibrationLost:
            return change(to: .needsCalibration)
        case .needsEmptyBoard:
            return change(to: .needsEmptyBoard)
        case .advisory(let advisory):
            if advisory == .accuracyDegraded {
                thresholds.high = VisionConfiguration().confidence.degradedHighThreshold
            }
            return [.advisory(CameraText.advice(for: advisory))]
        default:
            // A dart, a removal, a bounce or a takeout of a board that may still hold darts is not the game's.
            return []
        }
    }

    private func statusEvents(for state: ScanState) -> [DartInputEvent] {
        let next = Self.status(for: state, mode: mode)
        if keepsEmptyBoardRequest {
            // Only a new arming lifts the request, and the loss of the calibration replaces it.
            switch state {
            case .arming:
                keepsEmptyBoardRequest = false
            case .needsCalibration, .calibrationLost:
                keepsEmptyBoardRequest = false
            default:
                return []
            }
        }
        return change(to: next)
    }

    private func change(to next: InputStatus) -> [DartInputEvent] {
        guard next != status else { return [] }
        status = next
        return [.statusChanged(next)]
    }

    private func publish(_ next: InputStatus) {
        for event in change(to: next) { send(event) }
    }

    private func send(_ event: DartInputEvent) {
        for continuation in subscribers.values { continuation.yield(event) }
    }

    /// Opens the stream of the service once, synchronously, so that no event that follows a command is lost.
    private func startReading() {
        guard reader == nil, !hasEnded else { return }
        let events = camera.service.events()
        reader = Task { [weak self] in
            for await event in events {
                guard let self, !Task.isCancelled else { return }
                for output in self.translate(event) { self.send(output) }
            }
            self?.serviceStopped()
        }
    }

    private func serviceStopped() {
        reader = nil
        for continuation in subscribers.values { continuation.finish() }
        subscribers = [:]
    }

    /// After "Pas encore": `.needsEmptyBoard`, or `.needsCalibration` while the vision has no calibration.
    private func checkStateWhileAwaiting() {
        stateCheck?.cancel()
        let service = camera.service
        stateCheck = Task { [weak self] in
            let state = await service.currentState()
            guard let self, !Task.isCancelled, !self.hasEnded, self.awaitsEmptyBoard else { return }
            self.publish(state == .needsCalibration || state == .calibrationLost ? .needsCalibration : .needsEmptyBoard)
        }
    }

    /// After `arm`: in `needsCalibration` and `calibrationLost`, where `arm` changes nothing and emits nothing
    /// (VISION.md §6.3), the source says so itself; in any other state the `stateChanged` that follow carry the status.
    private func checkStateAfterArming() {
        stateCheck?.cancel()
        let service = camera.service
        stateCheck = Task { [weak self] in
            let state = await service.currentState()
            guard let self, !Task.isCancelled, !self.hasEnded else { return }
            if state == .needsCalibration || state == .calibrationLost {
                self.keepsEmptyBoardRequest = false
                self.publish(.needsCalibration)
            }
        }
    }
}
