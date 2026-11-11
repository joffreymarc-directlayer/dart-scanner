import SwiftUI
import DartCore
import DartVision

/// Data of the camera-flow snapshots (ARCHITECTURE.md §8.11): synthetic frames rendered by DartVision stand for
/// the camera, and their exact calibrations for the calibration of the screens. Everything is deterministic:
/// fixed cameras, fixed darts, fixed noise seeds; each frame is rendered once per process.
enum CameraFlowFixtures {
    /// Portrait camera under the board, as on an iPhone stand (VISION.md §2.1, closer than pose A).
    static let portraitCamera = SyntheticCamera(imageSize: PixelSize(width: 720, height: 1280), position: SIMD3(100, -300, 700))
    /// Landscape camera on the side, as on an iPad stand (the side variant of VISION.md §2.1).
    static let landscapeCamera = SyntheticCamera(imageSize: PixelSize(width: 1280, height: 720), position: SIMD3(330, -170, 760))

    /// Tips of the darts of the snapshots, nominal mm: T20; T19 close to the 19/7 wire; S7.
    static let treble20 = BoardPoint(x: 0, y: 103)
    static let treble19 = BoardPoint(x: 103 * sin(205.5 * .pi / 180), y: 103 * cos(205.5 * .pi / 180))
    static let single7 = BoardPoint(x: 140 * sin(216 * .pi / 180), y: 140 * cos(216 * .pi / 180))

    static func camera(_ device: SnapshotDevice) -> SyntheticCamera {
        switch device {
        case .phonePortrait, .padPortrait: return portraitCamera
        case .phoneLandscape, .padLandscape: return landscapeCamera
        }
    }

    // MARK: Frames

    private static let emptyPortrait = render(portraitCamera, darts: [])
    private static let emptyLandscape = render(landscapeCamera, darts: [])
    private static let twoDartsPortrait = render(portraitCamera, darts: [treble20, treble19])
    private static let twoDartsLandscape = render(landscapeCamera, darts: [treble20, treble19])
    private static let threeDartsPortrait = render(portraitCamera, darts: [treble20, treble19, single7])
    private static let threeDartsLandscape = render(landscapeCamera, darts: [treble20, treble19, single7])

    static func emptyBoard(_ device: SnapshotDevice) -> RGBImage {
        camera(device) == portraitCamera ? emptyPortrait : emptyLandscape
    }

    static func twoDarts(_ device: SnapshotDevice) -> RGBImage {
        camera(device) == portraitCamera ? twoDartsPortrait : twoDartsLandscape
    }

    static func threeDarts(_ device: SnapshotDevice) -> RGBImage {
        camera(device) == portraitCamera ? threeDartsPortrait : threeDartsLandscape
    }

    /// The board with darts planted at `tips` (nominal mm), seed 7.
    static func render(_ camera: SyntheticCamera, darts tips: [BoardPoint]) -> RGBImage {
        var scene = SyntheticScene()
        scene.darts = tips.map { SyntheticDart(tip: $0) }
        scene.seed = 7
        return scene.render(camera: camera)
    }

    // MARK: Screens

    /// Step 2: the handles on the junctions, the live wireframe, alignment "Correct" with one advice.
    static func calibrationAdjusting(_ device: SnapshotDevice) -> CalibrationContentModel {
        let camera = camera(device)
        let still = emptyBoard(device)
        let calibration = camera.calibration(grade: .fair)
        return CalibrationContentModel(stage: .adjusting, picture: still.cameraPicture, imageSize: still.size,
                                       handles: camera.exactHandles(), wireframe: calibration.wireframe(ringSegments: 96),
                                       issues: [.resolutionLow, .intrinsicsApproximate], canValidate: true)
    }

    /// Step 3: the result of "Valider", quality "fair" with one advice, the proof view and a tap test.
    static func calibrationProof(_ device: SnapshotDevice) -> CalibrationContentModel {
        let camera = camera(device)
        let still = emptyBoard(device)
        let calibration = camera.calibration(grade: .fair)
        var quality = calibration.quality
        quality.issues = [.dartMarginCutOff]
        return CalibrationContentModel(stage: .proof, picture: still.cameraPicture, imageSize: still.size,
                                       wireframe: calibration.wireframe(ringSegments: 96), quality: quality,
                                       rectified: BoardRectifier(calibration: calibration).rectify(still).rgb.cameraPicture,
                                       tappedHit: .treble(20))
    }

    /// Two darts: T20, sure; T19 near a wire, to be checked. The game is the X01 of the play snapshot, played by
    /// the engine (`GameFlowFixtures.x01InRound6()`, Tom on 24); its two darts take the tips drawn on the frame.
    static func liveScan(_ device: SnapshotDevice) -> ScanLiveContentModel {
        let camera = camera(device)
        let calibration = camera.calibration(grade: .good)
        let frame = twoDarts(device)
        var match = GameFlowFixtures.x01InRound6()
        match?.replaceDart(at: 0, with: .treble(20), position: treble20)
        match?.replaceDart(at: 1, with: .treble(19), position: treble19)
        match?.setNeedsReview(true, at: 1)
        let snapshot = match?.snapshot
        let player = snapshot?.currentPlayer ?? 0
        let records = match?.currentTurn ?? []
        var marks: [CameraTipMark] = []
        var slots: [ScanSlot] = []
        var review: (label: String, target: CorrectionTarget)?
        for (index, slot) in (snapshot?.turn.darts ?? []).enumerated() {
            let record = records.indices.contains(index) ? records[index] : nil
            let needsReview = record?.needsReview ?? false
            let label = slot.hit.notation
            slots.append(ScanSlot(text: LocalizedText(verbatim: label),
                                  caption: needsReview ? CameraText.localized("scan.slot.review") : slot.caption?.text,
                                  kind: .counted(review: needsReview)))
            if needsReview, review == nil { review = (label, .recorded(index: index)) }
            if let record, let position = record.position {
                marks.append(CameraTipMark(id: record.id, point: calibration.imagePoint(for: position),
                                           label: needsReview ? "\(label) ?" : label, needsReview: needsReview))
            }
        }
        while slots.count < 3 {
            slots.append(ScanSlot(text: ScanText.emptySlot(slots.count), caption: nil, kind: .empty))
        }
        return ScanLiveContentModel(
            preview: frame.cameraPicture.map(PreviewContent.image) ?? .none,
            imageSize: frame.size,
            marks: marks,
            status: .live,
            playerName: match.map { $0.players[player].name } ?? "?", playerIndex: player,
            subtitle: snapshot.map(ScanText.subtitle) ?? LocalizedText(verbatim: ""),
            score: snapshot?.players.first { $0.player == player }?.primary,
            slots: slots,
            review: review,
            canEndTurn: true)
    }

    /// Last photo T20, T19, S7; the camera on its stand in manual trigger.
    static func photoMode(_ device: SnapshotDevice) -> PhotoModeContentModel {
        let frame = threeDarts(device)
        return PhotoModeContentModel(stage: .camera, hasCamera: true, preview: frame.cameraPicture.map(PreviewContent.image) ?? .none,
                                     imageSize: frame.size, canCaptureReference: true, canScan: true, canImport: true,
                                     canTakePhoto: true, scansTurns: true, lastHits: [.treble(20), .treble(19), .single(7)])
    }

    /// No camera: only "Importer une photo" is active.
    static var photoModeWithoutCamera: PhotoModeContentModel {
        PhotoModeContentModel(stage: .camera, hasCamera: false, canImport: true, canTakePhoto: false)
    }

    /// A scan that found nothing because the light changed.
    static func photoReviewEmpty(_ device: SnapshotDevice) -> PhotoModeContentModel {
        let frame = emptyBoard(device)
        return PhotoModeContentModel(stage: .review, hasCamera: true, preview: frame.cameraPicture.map(PreviewContent.image) ?? .none,
                                     imageSize: frame.size, scansTurns: true, review: [], emptyCause: .lighting)
    }

    /// A photo calibrated by itself, two tips touched.
    static func photoTips(_ device: SnapshotDevice) -> PhotoModeContentModel {
        let camera = camera(device)
        let calibration = camera.calibration(grade: .fair)
        let photo = threeDarts(device)
        let tips = [treble20, treble19].enumerated().map { index, tip in
            CameraTipMark(id: id(10 + index), point: calibration.imagePoint(for: tip),
                          label: calibration.hit(at: calibration.imagePoint(for: tip), board: .standard).notation, needsReview: false)
        }
        return PhotoModeContentModel(stage: .photoTips, hasCamera: true, canImport: false, photo: photo.cameraPicture,
                                     photoSize: photo.size, wireframe: calibration.wireframe(ringSegments: 96), tips: tips,
                                     remainingDarts: 3)
    }

    static func id(_ n: Int) -> UUID {
        UUID(uuid: (0xCA, 0x3E, 0x7A, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, UInt8(truncatingIfNeeded: n)))
    }
}
