import Foundation
import CoreGraphics
import ImageIO
import Observation
import DartCore
import DartVision
import DartAudio

/// The photo mode (ARCHITECTURE.md §8.7, "Mode photo"; VISION.md §8): two independent paths.
///
/// - "Scanner la volée": the device on its stand, manual trigger. "Cible vide" deposits `.captureReference`,
///   "Scanner" deposits `.captureNow(maxDarts:)` with the darts still expected in the turn; both go through the
///   single queue of `CameraModel`. Every accepted `captureNow` ends with exactly one `scanCompleted`, read here
///   from a stream of the service of its own, and the review screen is always shown, even empty.
/// - A single photo, imported or taken by hand (`captureStill(averaging: 1)`): calibrated on its own (steps 4 to 6
///   of the calibration applied to the photo), then the player touches each tip and `PhotoScorer` scores it; each
///   dart goes to `game.receive` as a certain proposal with its position. This path needs neither a calibrated
///   stand, nor a source, nor a camera.
@MainActor
@Observable
final class PhotoModeModel {
    enum Stage: Hashable {
        /// The two paths are offered.
        case camera
        /// `captureNow` sent; "Scanner" stays inactive until `scanCompleted`.
        case scanning
        /// Result of a scan, possibly empty.
        case review
        case photoLoading
        /// The handles of the photo.
        case photoAdjust
        case photoValidating
        /// The wireframe is turned by a whole number of sectors (`sectorPhaseMismatch`): the player touches the
        /// real 20 on the photo, as in the calibration (VISION.md §4.7).
        case photoTouchTwenty
        /// The player touches the tips on the photo.
        case photoTips
        /// The photo could not be read or calibrated.
        case photoFailed
    }

    /// Why a scan found nothing new (§8.7: the cause of an empty review when an event preceded the result).
    enum EmptyCause: Hashable {
        /// `advisory(.viewObstructed)`: the view did not settle within 2 s.
        case obstructed
        /// `lightingChanged`.
        case lighting
        /// The capture was interrupted by a pause.
        case interrupted
    }

    let game: PlayViewModel
    let camera: CameraModel
    @ObservationIgnored var sound: (any SoundPlaying)?

    private(set) var stage: Stage = .camera
    /// Observations of the last scan, in the order the player keeps.
    private(set) var reviewed: [DartObservation] = []
    private(set) var emptyCause: EmptyCause?
    /// After `lightingChanged` the player must clear the board and take "Cible vide" again.
    private(set) var needsNewReference = false
    /// Hits of the last scan or photo sent to the game ("Dernière photo").
    private(set) var lastHits: [Hit] = []

    private(set) var photo: RGBImage?
    private(set) var photoPicture: CGImage?
    private(set) var photoHandles: CalibrationHandles?
    private(set) var photoPreview: BoardCalibration?
    private(set) var photoIssues: [CalibrationIssue] = []
    private(set) var photoCalibration: BoardCalibration?
    /// Tips touched on the photo, image pixels.
    private(set) var tips: [ImagePoint] = []

    @ObservationIgnored private var causeBeforeResult: EmptyCause?
    @ObservationIgnored private let calibrator = BoardCalibrator(parameters: CalibrationParameters())
    /// How long a scan waits for its `scanCompleted` before the camera stage comes back: a capture the vision did
    /// not accept is never answered, and the back button is inactive while a scan is under way.
    @ObservationIgnored var scanTimeout: Duration = .seconds(8)
    @ObservationIgnored private var scanWatchdog: Task<Void, Never>?

    init(game: PlayViewModel, camera: CameraModel) {
        self.game = game
        self.camera = camera
    }

    // MARK: Buttons (table of §8.7)

    /// "Cible vide": a calibrated stand and the source of the game at rest in manual trigger, or waiting for the
    /// board to be confirmed empty ("Videz la cible, puis confirmez": "Cible vide" is that confirmation).
    var canCaptureReference: Bool {
        guard stage == .camera, case .ready = camera.readiness else { return false }
        return game.inputStatus == .awaitingCapture || game.inputStatus == .needsEmptyBoard
    }

    /// "Scanner": the source at rest in manual trigger, and the turn still waits for at least one dart.
    var canScan: Bool {
        canCaptureReference && game.inputStatus == .awaitingCapture && game.snapshot.phase == .throwing
            && remainingDarts > 0
    }

    /// Darts still expected in the turn: counted ones and those waiting for an answer are deducted.
    var remainingDarts: Int {
        max(0, 3 - game.turnRecords.count - game.pending.count)
    }

    /// Darts a scan asks the vision for (`captureNow(maxDarts:)`): those it has not returned yet. A dart counted
    /// by the vision (origin camera or scan, or waiting for an answer) is in its reference; a dart entered by hand
    /// or from a photo is not, and the scan proposes it again, which the review discards (VISION.md §6.3). Asking
    /// for `remainingDarts` would let that duplicate take the place of the last real dart.
    var scanDarts: Int {
        let returned = game.turnRecords.filter { $0.origin == .camera || $0.origin == .scan }.count + game.pending.count
        return max(0, 3 - returned)
    }

    /// "Importer une photo": always, without camera, calibration or source.
    var canImport: Bool {
        stage == .camera || stage == .photoFailed
    }

    /// "Prendre une photo": when the service delivers frames.
    var canTakePhoto: Bool {
        canImport && camera.service.issue == nil
    }

    // MARK: Scan of the turn

    func captureReference() {
        guard canCaptureReference else { return }
        needsNewReference = false
        if game.inputStatus == .needsEmptyBoard {
            game.confirmBoardEmpty()
        } else {
            camera.enqueue(.captureReference)
        }
    }

    func scan() {
        guard canScan else { return }
        let darts = scanDarts
        causeBeforeResult = nil
        stage = .scanning
        camera.enqueue(.captureNow(maxDarts: darts))
        sound?.play(CueMapping.cues(for: .shutter, context: CameraFlowCue.context))
        let timeout = scanTimeout
        scanWatchdog?.cancel()
        scanWatchdog = Task { [weak self] in
            try? await Task.sleep(for: timeout)
            guard !Task.isCancelled, let self, self.stage == .scanning else { return }
            self.stage = .camera
        }
    }

    /// Reads the events of the service while the photo mode is on screen (a new stream: §11).
    func listen() async {
        for await event in camera.service.events() {
            handle(event)
        }
    }

    func handle(_ event: ScanEvent) {
        switch event {
        case .scanCompleted(let observations):
            scanWatchdog?.cancel()
            reviewed = observations
            emptyCause = observations.isEmpty ? causeBeforeResult : nil
            causeBeforeResult = nil
            stage = .review
        case .advisory(.viewObstructed):
            causeBeforeResult = .obstructed
        case .lightingChanged:
            causeBeforeResult = .lighting
            needsNewReference = true
        case .stateChanged(.paused):
            if stage == .scanning { causeBeforeResult = .interrupted }
        default:
            break
        }
    }

    /// Moves a dart of the review one place up (when several darts were asked for, their order is unknown).
    func moveUp(_ index: Int) {
        guard index > 0, reviewed.indices.contains(index) else { return }
        reviewed.swapAt(index, index - 1)
    }

    /// A phantom of the review: the vision drops it from its count (`discardDart`), the game never sees it.
    func discard(_ index: Int) {
        guard stage == .review, reviewed.indices.contains(index) else { return }
        let removed = reviewed.remove(at: index)
        camera.enqueue(.discardDart(removed.id))
    }

    /// The darts of the review go to the game, in the order kept.
    func confirmReview() {
        guard stage == .review else { return }
        let observations = reviewed
        reviewed = []
        emptyCause = nil
        stage = .camera
        guard !observations.isEmpty else { return }
        // The thresholds of the game's source: raised for the rest of the game after `accuracyDegraded` (§8.7).
        let thresholds = camera.inputSource?.thresholds ?? .standard
        for observation in observations {
            game.receive(DartProposal(observation: observation, thresholds: thresholds))
        }
        lastHits = observations.map(\.best)
    }

    // MARK: Single photo

    /// A photo picked in the library: decoded off the main thread, upright, at most 4032 px on its long side.
    func importPhoto(data: Data) async {
        guard canImport else { return }
        stage = .photoLoading
        let image = await Task.detached(priority: .userInitiated) { PhotoModeModel.decode(data) }.value
        guard let image else {
            stage = .photoFailed
            return
        }
        await begin(with: image)
    }

    /// A photo already decoded (tests, drag and drop).
    func importPhoto(_ image: RGBImage) async {
        guard canImport else { return }
        await begin(with: image)
    }

    /// A photo taken by hand: one frame, which averaging would blur (VISION.md §8.2).
    func takePhoto() async {
        guard canTakePhoto else { return }
        stage = .photoLoading
        do {
            await begin(with: try await camera.service.captureStill(averaging: 1))
        } catch {
            stage = .photoFailed
        }
    }

    func movePhotoHandle(_ handle: CalibrationHandle, to point: ImagePoint) {
        guard stage == .photoAdjust, var moved = photoHandles else { return }
        moved[handle] = point
        setPhotoHandles(moved)
    }

    func locatePhoto() async {
        guard stage == .photoAdjust, let photo else { return }
        if let located = await Self.locate(in: photo) {
            setPhotoHandles(located)
        } else {
            photoIssues = [.edgesNotFound]
        }
    }

    var canValidatePhoto: Bool {
        stage == .photoAdjust && photoPreview != nil && !photoIssues.contains(where: \.isBlocking)
    }

    /// Calibration of this photo (step 6 of the calibration applied to the photo).
    func validatePhoto() async {
        guard canValidatePhoto, let photo, let handles = photoHandles else { return }
        stage = .photoValidating
        let calibrator = self.calibrator
        let outcome = await Task.detached(priority: .userInitiated) {
            calibrator.calibrate(handles: handles, still: photo, rotationDegrees: 0, intrinsics: nil)
        }.value
        switch outcome {
        case .success(let calibration):
            photoIssues = calibration.quality.issues
            tips = []
            if calibration.quality.issues.contains(.sectorPhaseMismatch) {
                // A wireframe turned by a sector scores every dart wrong (VISION.md §4.7): as the calibration
                // does, the player touches the real 20 first.
                photoCalibration = nil
                stage = .photoTouchTwenty
                return
            }
            photoCalibration = calibration
            stage = .photoTips
        case .failure(.rejected(let issues)):
            photoIssues = issues
            stage = .photoAdjust
        case .failure(.degenerateHandles):
            photoIssues = [.quadNotConvex]
            stage = .photoAdjust
        }
    }

    /// The player touched the real 20 on the photo: the wireframe turns by the nearest whole number of sectors,
    /// then the photo is calibrated again.
    func touchPhotoTwenty(at point: ImagePoint) async {
        guard stage == .photoTouchTwenty,
              let reoriented = photoHandles?.reoriented(twentyAt: point, parityPreserving: false) else { return }
        stage = .photoAdjust
        setPhotoHandles(reoriented)
        await validatePhoto()
    }

    /// Back to the handles from the tips or from "touchez le vrai 20".
    func adjustPhotoAgain() {
        guard stage == .photoTips || stage == .photoTouchTwenty else { return }
        photoCalibration = nil
        tips = []
        stage = .photoAdjust
        if let photoHandles { setPhotoHandles(photoHandles) }
    }

    /// The player touched a tip (image pixels). At most the darts still expected in the turn.
    func tapTip(at point: ImagePoint) {
        guard stage == .photoTips, point.x.isFinite, point.y.isFinite, tips.count < remainingDarts else { return }
        tips.append(point)
    }

    func removeLastTip() {
        guard stage == .photoTips, !tips.isEmpty else { return }
        tips.removeLast()
    }

    /// The hit under a tip of the photo.
    func hit(atTip point: ImagePoint) -> Hit? {
        photoCalibration?.hit(at: point, board: .standard)
    }

    /// Every touched tip becomes a certain proposal with its position, sent to the game in the order touched.
    func confirmTips() {
        guard stage == .photoTips, let calibration = photoCalibration, !tips.isEmpty else { return }
        let scorer = PhotoScorer()
        let visit = game.snapshot.round
        let first = game.turnRecords.count + game.pending.count
        let observations = tips.enumerated().map { index, point in
            scorer.observation(forTappedTip: point, calibration: calibration, visit: visit, indexInVisit: first + index)
        }
        // A calibration graded poor: every dart is "à vérifier" (VISION.md §4.7), even a tip touched by hand.
        let poor = calibration.quality.grade == .poor
        endPhoto()
        for observation in observations {
            var proposal = DartProposal(observation: observation, thresholds: .standard)
            if poor {
                let certainty = proposal.certainty
                proposal.certainty = { match in certainty(match) == .certain ? .needsReview : certainty(match) }
            }
            game.receive(proposal)
        }
        lastHits = observations.map(\.best)
    }

    /// Leaves the photo without counting anything.
    func cancelPhoto() {
        endPhoto()
    }

    // MARK: Private

    private func begin(with image: RGBImage) async {
        guard image.width > 0, image.height > 0 else {
            stage = .photoFailed
            return
        }
        photo = image
        photoPicture = image.cameraPicture
        photoCalibration = nil
        tips = []
        stage = .photoLoading
        let handles = await Self.locate(in: image) ?? CalibrationHandles.centredDefault(in: image.size)
        setPhotoHandles(handles)
        stage = .photoAdjust
    }

    private func endPhoto() {
        photo = nil
        photoPicture = nil
        photoHandles = nil
        photoPreview = nil
        photoIssues = []
        photoCalibration = nil
        tips = []
        stage = .camera
    }

    private func setPhotoHandles(_ handles: CalibrationHandles) {
        photoHandles = handles
        guard let photo else { return }
        switch calibrator.preview(handles: handles, imageSize: photo.size, rotationDegrees: 0, intrinsics: nil) {
        case .success(let calibration):
            photoPreview = calibration
            photoIssues = calibration.quality.issues
        case .failure(.rejected(let issues)):
            photoPreview = nil
            photoIssues = issues
        case .failure(.degenerateHandles):
            photoPreview = nil
            photoIssues = [.quadNotConvex]
        }
    }

    private nonisolated static func locate(in image: RGBImage) async -> CalibrationHandles? {
        await Task.detached(priority: .userInitiated) {
            ColourBoardLocator(parameters: ColourBoardLocator.Parameters()).locate(in: image, upDirection: SIMD2(0, -1))?.handles
        }.value
    }

    /// Decodes JPEG, HEIC or PNG data upright (the EXIF orientation applied), at most `maxPixelSize` on the long side.
    nonisolated static func decode(_ data: Data, maxPixelSize: Int = 4032) -> RGBImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return RGBImage(cgImage: image)
    }
}
