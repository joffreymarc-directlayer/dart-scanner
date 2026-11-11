import Foundation
import CoreGraphics
import Observation
import DartCore
import DartVision
import DartAudio

/// The steps of the calibration (ARCHITECTURE.md §8.7, table "Calibrage"; VISION.md §2.3, §4.7, §4.8):
/// authorisation and start, placement guide the first time, frozen still, initial handles, handles moved by the
/// player with the live wireframe and one advice, "Valider", proof view and tap test, adoption, then the optional
/// one-dart check. Every heavy computation runs in a detached task with `Sendable` values (§11).
@MainActor
@Observable
final class CalibrationFlowModel {
    enum Stage: Hashable {
        case starting
        /// Access refused, no camera, camera taken: the camera-denied screen.
        case unavailable(CameraIssue)
        /// The placement guide, before the first calibration of this camera.
        case placement
        /// Frozen still being taken ("Ne bougez plus").
        case capturing
        /// Handles moved by the player over the still.
        case adjusting
        case validating
        /// The light and dark sectors are swapped: the player touches the real 20.
        case touchTwenty
        /// Proof view and tap test, before the adoption.
        case proof
        /// Saved; the one-dart check is offered.
        case adopted
        /// One-dart check: the vision is armed, the player plants a dart.
        case checkThrow
        case checkCapturing
        /// The player touches the tip of the dart on the still.
        case checkTap
        case checking
        case checkResult(LightingCheckResult.Verdict)
    }

    let camera: CameraModel
    /// The service of sound, given by the view (`AppEnvironment.sound`): tap test and validation cue.
    @ObservationIgnored var sound: (any SoundPlaying)?

    private(set) var stage: Stage = .starting
    private(set) var still: RGBImage?
    private(set) var picture: CGImage?
    private(set) var handles: CalibrationHandles?
    /// C1 on the current handles: the live wireframe and its advice (nil when the handles are refused).
    private(set) var preview: BoardCalibration?
    /// Issues of the current handles or of the last validation, most actionable first.
    private(set) var issues: [CalibrationIssue] = []
    /// Result of "Valider".
    private(set) var result: BoardCalibration?
    /// The board seen from the front through `result` (VISION.md §4.7, "vue de preuve").
    private(set) var rectified: CGImage?
    /// Hit announced by the last tap of the tap test.
    private(set) var tappedHit: Hit?
    /// Still of the one-dart check, and the tip the player touched on it.
    private(set) var checkPicture: CGImage?
    private(set) var checkTip: ImagePoint?
    private(set) var checkResult: LightingCheckResult?
    /// True once this flow deposited `arm` for the one-dart check: closing it then deposits `pause(.user)`.
    private(set) var hasArmed = false

    @ObservationIgnored private var checkStill: RGBImage?
    @ObservationIgnored private let calibrator = BoardCalibrator(parameters: CalibrationParameters())

    init(camera: CameraModel) {
        self.camera = camera
    }

    // MARK: Steps 1 to 4

    /// Step 1, then the placement guide or the still.
    func start() async {
        stage = .starting
        await camera.activate()
        if case .unavailable(let issue) = camera.readiness {
            stage = .unavailable(issue)
            return
        }
        if camera.savedCalibration == nil {
            stage = .placement
            return
        }
        await captureStill()
    }

    /// The player read the placement guide.
    func continueAfterPlacement() async {
        await captureStill()
    }

    /// Steps 3 and 4: a still averaged over 8 frames, then the previous handles, the automatic location or the
    /// default circle.
    func captureStill() async {
        stage = .capturing
        let image: RGBImage
        do {
            image = try await camera.service.captureStill(averaging: 8)
        } catch {
            stage = .unavailable((error as? ScanServiceError)?.issue ?? camera.service.issue ?? .noCamera)
            return
        }
        still = image
        picture = image.cameraPicture
        result = nil
        rectified = nil
        tappedHit = nil
        if let previous = camera.calibration ?? camera.savedCalibration, previous.imageSize == image.size {
            setHandles(previous.handles)
        } else if let located = await Self.locate(in: image) {
            setHandles(located)
        } else {
            setHandles(CalibrationHandles.centredDefault(in: image.size))
        }
        stage = .adjusting
    }

    /// "Détection auto": the colour locator, from scratch.
    func locateAutomatically() async {
        guard let still, stage == .adjusting else { return }
        if let located = await Self.locate(in: still) {
            setHandles(located)
        } else {
            issues = [.edgesNotFound]
        }
    }

    // MARK: Step 5

    func moveHandle(_ handle: CalibrationHandle, to point: ImagePoint) {
        guard stage == .adjusting, var moved = handles else { return }
        moved[handle] = point
        setHandles(moved)
    }

    /// True when "Valider" is possible: four handles that C1 accepts.
    var canValidate: Bool {
        stage == .adjusting && preview != nil && !issues.contains(where: \.isBlocking)
    }

    // MARK: Step 6

    func validate() async {
        guard let still, let handles, canValidate || stage == .touchTwenty else { return }
        stage = .validating
        let info = camera.service.frameInfo
        let rotation = info?.rotationDegrees ?? 0
        let intrinsics = info?.intrinsics
        let calibrator = self.calibrator
        let outcome = await Task.detached(priority: .userInitiated) {
            calibrator.calibrate(handles: handles, still: still, rotationDegrees: rotation, intrinsics: intrinsics)
        }.value
        switch outcome {
        case .failure(.rejected(let refused)):
            issues = refused
            stage = .adjusting
        case .failure(.degenerateHandles):
            issues = [.quadNotConvex]
            stage = .adjusting
        case .success(let calibration):
            issues = calibration.quality.issues
            if calibration.quality.issues.contains(.sectorPhaseMismatch) {
                stage = .touchTwenty
                return
            }
            result = calibration
            rectified = await Self.rectify(still, with: calibration)
            stage = .proof
        }
    }

    /// The player touched the real 20: the wireframe turns by the nearest whole number of sectors (an odd one
    /// when the colours are swapped), then the calibration is made again.
    func touchTwenty(at point: ImagePoint) async {
        guard stage == .touchTwenty, let reoriented = handles?.reoriented(twentyAt: point, parityPreserving: false) else { return }
        setHandles(reoriented)
        await validate()
    }

    /// Back to the handles from the proof view.
    func adjustAgain() {
        guard stage == .proof || stage == .touchTwenty else { return }
        result = nil
        rectified = nil
        tappedHit = nil
        stage = .adjusting
        if let handles { setHandles(handles) }
    }

    // MARK: Step 7

    /// Tap test: the hit under the finger, announced by the voice.
    @discardableResult
    func tapTest(at point: ImagePoint) -> Hit? {
        guard stage == .proof || stage == .adopted, let result else { return nil }
        let hit = result.hit(at: point, board: .standard)
        tappedHit = hit
        sound?.say(CallerPhrases.hit(hit), priority: .high)
        return hit
    }

    // MARK: Step 8

    func adopt() async {
        guard stage == .proof, let result else { return }
        await camera.adopt(result, lightingCheckPassed: false)
        sound?.play(CueMapping.cues(for: .calibrationValidated, context: CameraFlowCue.context))
        stage = .adopted
    }

    // MARK: Step 9: one-dart check

    /// Arms the vision on an empty board: the next dart planted is the one of the check.
    func startLightingCheck() {
        guard stage == .adopted || isCheckResult else { return }
        camera.enqueue(.arm(boardConfirmedEmpty: true))
        hasArmed = true
        checkPicture = nil
        checkTip = nil
        checkResult = nil
        stage = .checkThrow
    }

    /// The dart is planted: a still to touch its tip on.
    func captureCheckStill() async {
        guard stage == .checkThrow else { return }
        stage = .checkCapturing
        do {
            let image = try await camera.service.captureStill(averaging: 8)
            checkStill = image
            checkPicture = image.cameraPicture
            stage = .checkTap
        } catch {
            stage = .checkResult(.failed)
        }
    }

    /// The player touched the tip: the vision compares it with its own detection (VISION.md §4.8).
    func confirmTip(at point: ImagePoint) async {
        guard stage == .checkTap, let result else { return }
        checkTip = point
        stage = .checking
        let tip = result.boardPoint(for: point)
        guard let outcome = await camera.service.runLightingCheck(confirmedTip: tip) else {
            stage = .checkResult(.failed)
            return
        }
        checkResult = outcome
        camera.recordLightingCheck(outcome)
        if outcome.verdict == .verified {
            await camera.adopt(result, lightingCheckPassed: true)
        }
        stage = .checkResult(outcome.verdict)
    }

    private var isCheckResult: Bool {
        if case .checkResult = stage { return true }
        return false
    }

    // MARK: Closing

    /// The flow closes, whatever its step: when it armed the vision for the check, `pause(.user)` stops it
    /// (§8.7: only the `arm` of the next game wakes it up again).
    func close() {
        if hasArmed {
            camera.enqueue(.pause(.user))
            hasArmed = false
        }
    }

    // MARK: Private

    private func setHandles(_ next: CalibrationHandles) {
        handles = next
        guard let still else { return }
        let info = camera.service.frameInfo
        switch calibrator.preview(handles: next, imageSize: still.size, rotationDegrees: info?.rotationDegrees ?? 0,
                                  intrinsics: info?.intrinsics) {
        case .success(let calibration):
            preview = calibration
            issues = calibration.quality.issues
        case .failure(.rejected(let refused)):
            preview = nil
            issues = refused
        case .failure(.degenerateHandles):
            preview = nil
            issues = [.quadNotConvex]
        }
    }

    private nonisolated static func locate(in still: RGBImage) async -> CalibrationHandles? {
        await Task.detached(priority: .userInitiated) {
            ColourBoardLocator(parameters: ColourBoardLocator.Parameters()).locate(in: still, upDirection: SIMD2(0, -1))?.handles
        }.value
    }

    private nonisolated static func rectify(_ still: RGBImage, with calibration: BoardCalibration) async -> CGImage? {
        await Task.detached(priority: .userInitiated) {
            BoardRectifier(calibration: calibration).rectify(still).rgb.cameraPicture
        }.value
    }
}

/// The context of the interface cues of the camera flow: no game, no player.
enum CameraFlowCue {
    static let context = CueContext(gameID: GameID("camera"), players: [], winners: [], winnerTitle: nil)
}
