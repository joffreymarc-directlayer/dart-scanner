import SwiftUI
import PhotosUI
import DartCore
import DartVision

/// Photo mode, always reachable from the play screen (ARCHITECTURE.md §8.6, §8.7): "Scanner la volée" on the
/// stand, and a single photo, imported or taken by hand. The shell of `PhotoModeContent`: the photo picker (no
/// permission needed), the stream of the service, the correction sheet, the camera life cycle.
struct PhotoModeView: View {
    private let game: PlayViewModel
    private let camera: CameraModel
    @State private var model: PhotoModeModel
    @State private var showsPicker = false
    @State private var pickedItem: PhotosPickerItem?
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appLanguage) private var language

    init(game: PlayViewModel, camera: CameraModel) {
        self.game = game
        self.camera = camera
        _model = State(initialValue: PhotoModeModel(game: game, camera: camera))
    }

    var body: some View {
        @Bindable var game = game
        PhotoModeContent(model: PhotoModeContentModel(model: model), actions: actions)
            .background(Theme.Palette.background.ignoresSafeArea())
            .photosPicker(isPresented: $showsPicker, selection: $pickedItem, matching: .images)
            .onChange(of: pickedItem) { _, item in
                guard let item else { return }
                pickedItem = nil
                let model = model
                Task {
                    guard let data = try? await item.loadTransferable(type: Data.self) else { return }
                    await model.importPhoto(data: data)
                }
            }
            // The play screen sits under this cover and cannot present its own sheet.
            .sheet(item: $game.correction) { target in
                CorrectionSheet(game: game, target: target)
                    .appLanguage(language)
                    .preferredColorScheme(.dark)
            }
            .task {
                model.sound = app.environment.sound
                // The stream is opened first, so that no `scanCompleted` is lost.
                async let events: Void = model.listen()
                await camera.activate()
                await events
            }
            .keepsScreenAwake(true)
    }

    private var actions: PhotoModeActions {
        let model = model
        let game = game
        let last = game.turnRecords.indices.last
        return PhotoModeActions(
            close: { dismiss() },
            captureReference: { model.captureReference() },
            scan: { model.scan() },
            importPhoto: { showsPicker = true },
            takePhoto: { Task { await model.takePhoto() } },
            correctLast: last.map { index in { game.correction = .recorded(index: index) } },
            moveUp: { model.moveUp($0) },
            discard: { model.discard($0) },
            confirmReview: { model.confirmReview() },
            moveHandle: { handle, point in model.movePhotoHandle(handle, to: point) },
            locatePhoto: { Task { await model.locatePhoto() } },
            validatePhoto: { Task { await model.validatePhoto() } },
            tapPhoto: { point in
                if model.stage == .photoTouchTwenty {
                    Task { await model.touchPhotoTwenty(at: point) }
                } else {
                    model.tapTip(at: point)
                }
            },
            removeLastTip: { model.removeLastTip() },
            adjustPhoto: { model.adjustPhotoAgain() },
            confirmTips: { model.confirmTips() },
            cancelPhoto: { model.cancelPhoto() })
    }
}

extension PhotoModeContentModel {
    /// The content of a running photo mode.
    @MainActor
    init(model: PhotoModeModel) {
        let camera = model.camera
        let calibration = camera.calibration
        let marks: [CameraTipMark] = model.stage == .review && calibration != nil
            ? model.reviewed.enumerated().compactMap { index, observation in
                guard let calibration else { return nil }
                return CameraTipMark(id: observation.id, point: calibration.imagePoint(for: observation.tip),
                                     label: "\(index + 1) · \(observation.best.notation)", needsReview: observation.tier != .high)
            }
            : []
        let tips: [CameraTipMark] = model.tips.enumerated().map { index, point in
            CameraTipMark(id: PhotoText.tipID(index), point: point, label: model.hit(atTip: point)?.notation ?? "?",
                          needsReview: false)
        }
        let shown = model.photoCalibration ?? model.photoPreview
        self.init(stage: model.stage,
                  hasCamera: camera.service.issue == nil,
                  preview: camera.service.preview,
                  imageSize: camera.service.frameInfo?.size ?? calibration?.imageSize,
                  rotationDegrees: camera.service.frameInfo?.rotationDegrees ?? 0,
                  marks: marks,
                  canCaptureReference: model.canCaptureReference,
                  canScan: model.canScan,
                  canImport: model.canImport,
                  canTakePhoto: model.canTakePhoto,
                  needsNewReference: model.needsNewReference,
                  scansTurns: model.game.inputStatus == .awaitingCapture,
                  asksEmptyBoard: model.game.inputStatus == .needsEmptyBoard,
                  lastHits: model.lastHits,
                  review: model.reviewed.map { PhotoReviewItem(id: $0.id, hit: $0.best, needsCheck: $0.tier != .high) },
                  emptyCause: model.emptyCause,
                  photo: model.photoPicture,
                  photoSize: model.photo?.size,
                  handles: model.stage == .photoTips ? nil : model.photoHandles,
                  wireframe: shown?.wireframe(ringSegments: 96),
                  issues: model.photoIssues,
                  canValidatePhoto: model.canValidatePhoto,
                  tips: tips,
                  remainingDarts: model.remainingDarts)
    }
}

extension PhotoText {
    /// Stable identifiers of the tips touched on a photo, for the marks.
    static func tipID(_ index: Int) -> UUID {
        UUID(uuid: (0x50, 0x48, 0x4F, 0x54, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, UInt8(truncatingIfNeeded: index)))
    }
}
