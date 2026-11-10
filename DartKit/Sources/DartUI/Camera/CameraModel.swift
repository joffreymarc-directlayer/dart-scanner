import Foundation
import Observation
import DartCore
import DartVision

/// State of the camera shared by the home card, the calibration screen, the live scan and the photo mode.
/// Lot F0 writes the WORKING minimal bodies below: no camera, nothing traps, every game plays by manual input.
/// Lot U3 owns this file and replaces the bodies in wave 3; no other lot edits it. Signatures are frozen.
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

    init(service: any ScanServicing, storage: AppStorage) {
        self.service = service
        self.storage = storage
    }

    /// Starts the service and, when a calibration is stored for this camera, revalidates it on a fresh still
    /// (`assess`, then `recover`) and installs it in the service: VISION.md §4.10. Idempotent: does nothing when
    /// the service already runs, and a call made while another one is running waits for the same result.
    /// Minimal body: does nothing, `readiness` stays `.unknown`.
    func activate() async {}

    /// Stops the session when the camera is no longer needed (ARCHITECTURE.md §8.7, "Cycle de vie").
    /// Minimal body: does nothing.
    func deactivate() async {}

    /// The ONLY way a `ScanCommand` goes from DartUI to the vision layer: every `CameraInputSource`, the photo
    /// mode, the calibration flow and `setForeground` deposit here, and ONE task of this model awaits
    /// `service.send(_:)` for each command before taking the next. The vision layer therefore receives the
    /// commands in the exact order of the calls, whoever makes them (ARCHITECTURE.md §8.7, §11).
    /// Synchronous: the caller never waits. Minimal body: does nothing.
    func enqueue(_ command: ScanCommand) {}

    /// Same queue, same order: `service.recordFeedback(id, wasCorrected:)`. Minimal body: does nothing.
    func enqueueFeedback(_ id: UUID, wasCorrected: Bool) {}

    /// Scene phase (`AppModel.setForeground`): deposits `.pause(.background)` when the app leaves the foreground
    /// and `.resume` when it comes back, with `enqueue`. Minimal body: does nothing.
    func setForeground(_ active: Bool) {}

    /// Saves and installs a calibration validated by the player. Minimal body: kept in memory only.
    func adopt(_ calibration: BoardCalibration, lightingCheckPassed: Bool) async {
        self.calibration = calibration
        self.lightingCheckPassed = lightingCheckPassed
    }

    func forgetCalibration() {
        calibration = nil
        lightingCheckPassed = false
    }

    /// The automatic dart source for a game, for the given mode (`.live`: automatic trigger; `.photo`: manual
    /// trigger). Returns a source as soon as the camera is not known to be unavailable (`service.issue == nil`),
    /// WHATEVER `readiness`: after a cold start `readiness` is still `.unknown` when the game is created, and
    /// the play screen awaits `activate()` before the game starts (ARCHITECTURE.md §8.6, step 0). Without a
    /// valid calibration the source reports `.needsCalibration`. Nil only when `service.issue != nil`.
    /// Minimal body: always nil, so the game is played by manual input.
    func makeInputSource(mode: ScanMode) -> (any DartInputSource)? { nil }
}

/// Where the real application gets its scan service. `AppEnvironment.live()` calls it and never names a
/// concrete type, so that lot U1 does not wait for lot U3.
enum ScanServiceFactory {
    /// Lot F0: the fake without a camera. Lot U3 changes this single line to `LiveScanService()`.
    @MainActor static func live() -> any ScanServicing { FakeScanService(issue: .noCamera) }
}
