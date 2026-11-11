import SwiftUI
import DartCore
import DartVision

// The pure layout of the photo mode (mock-up `PhotoMode`; DESIGN.md §4 and §5): the camera image, "Cible vide",
// the shutter, the result of the last photo with "Corriger", and, outside the mock-up, "Importer une photo" and
// "Prendre une photo"; the review of a scan, even empty; the handles and the tips of a single photo. Without a
// camera the image is replaced by `surface` and only "Importer une photo" is active.

/// One dart of the review of a scan.
struct PhotoReviewItem: Identifiable, Hashable {
    let id: UUID
    var hit: Hit
    var needsCheck: Bool
}

/// What the photo mode shows, as values.
struct PhotoModeContentModel {
    var stage: PhotoModeModel.Stage
    var hasCamera: Bool
    var preview: PreviewContent = .none
    var imageSize: PixelSize?
    var rotationDegrees = 0
    /// Tips of the review drawn on the camera image (through the installed calibration).
    var marks: [CameraTipMark] = []
    var canCaptureReference = false
    var canScan = false
    var canImport = true
    var canTakePhoto = false
    var needsNewReference = false
    /// The source of the game is in manual trigger ("Scanner la volée" is the way of this game).
    var scansTurns = false
    /// The source waits for the board to be confirmed empty: "Cible vide" is that confirmation.
    var asksEmptyBoard = false
    var lastHits: [Hit] = []
    var review: [PhotoReviewItem] = []
    var emptyCause: PhotoModeModel.EmptyCause?
    // Single photo
    var photo: CGImage?
    var photoSize: PixelSize?
    var handles: CalibrationHandles?
    var wireframe: BoardWireframe?
    var issues: [CalibrationIssue] = []
    var canValidatePhoto = false
    var tips: [CameraTipMark] = []
    var remainingDarts = 3
}

struct PhotoModeActions {
    var close: () -> Void = {}
    var captureReference: () -> Void = {}
    var scan: () -> Void = {}
    var importPhoto: () -> Void = {}
    var takePhoto: () -> Void = {}
    var correctLast: (() -> Void)?
    var moveUp: (Int) -> Void = { _ in }
    var discard: (Int) -> Void = { _ in }
    var confirmReview: () -> Void = {}
    var moveHandle: ((CalibrationHandle, ImagePoint) -> Void)?
    var locatePhoto: () -> Void = {}
    var validatePhoto: () -> Void = {}
    var tapPhoto: ((ImagePoint) -> Void)?
    var removeLastTip: () -> Void = {}
    var adjustPhoto: () -> Void = {}
    var confirmTips: () -> Void = {}
    var cancelPhoto: () -> Void = {}
}

extension PhotoModeContentModel {
    /// "Retour" leaves the photo mode, or a single photo. Not while a scan is under way nor on its review: the
    /// vision counts the darts of a scan as soon as it answers, and only the review gives them to the game (its
    /// own buttons answer it).
    var canGoBack: Bool {
        stage != .scanning && stage != .review
    }
}

struct PhotoModeContent: View {
    let model: PhotoModeContentModel
    var actions = PhotoModeActions()
    var insets = EdgeInsets()

    @Environment(\.appLanguage) private var language

    var body: some View {
        CameraScreenFrame(insets: insets) {
            media
        } top: {
            CameraTopBar(buttonImage: "chevron.left", buttonLabel: L10n.text("photo.back", .camera), title: title,
                         bubble: bubble, isEnabled: model.canGoBack,
                         action: isPhotoStage ? actions.cancelPhoto : actions.close)
        } panel: {
            panel
        }
    }

    private var isPhotoStage: Bool {
        switch model.stage {
        case .photoLoading, .photoAdjust, .photoValidating, .photoTouchTwenty, .photoTips: return true
        default: return false
        }
    }

    // MARK: Image

    @ViewBuilder
    private var media: some View {
        if isPhotoStage, let photo = model.photo, let size = model.photoSize {
            GeometryReader { proxy in
                let fit = CameraImageFit(imageSize: size, viewSize: proxy.size, fills: false)
                ZStack(alignment: .topLeading) {
                    Image(decorative: photo, scale: 1)
                        .resizable()
                        .interpolation(.medium)
                        .frame(width: CGFloat(size.width) * fit.scale, height: CGFloat(size.height) * fit.scale)
                        .offset(x: fit.origin.x, y: fit.origin.y)
                    switch model.stage {
                    case .photoAdjust, .photoValidating:
                        CalibrationOverlay(wireframe: model.wireframe, handles: model.handles, fit: fit, still: photo,
                                           onMove: model.stage == .photoAdjust ? actions.moveHandle : nil)
                    case .photoTouchTwenty:
                        CalibrationOverlay(wireframe: model.wireframe, handles: nil, fit: fit, still: photo,
                                           onTap: actions.tapPhoto)
                    case .photoTips:
                        CalibrationOverlay(wireframe: model.wireframe, handles: nil, fit: fit, still: photo,
                                           onTap: actions.tapPhoto)
                            .opacity(0.55)
                        CameraTipsOverlay(marks: model.tips, fit: fit)
                            .allowsHitTesting(false)
                    default:
                        EmptyView()
                    }
                }
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
            }
        } else if model.hasCamera {
            GeometryReader { proxy in
                ZStack(alignment: .topLeading) {
                    CameraPreviewView(content: model.preview, rotationDegrees: model.rotationDegrees, fills: true)
                        .frame(width: proxy.size.width, height: proxy.size.height)
                    if let size = model.imageSize, !model.marks.isEmpty {
                        CameraTipsOverlay(marks: model.marks, fit: CameraImageFit(imageSize: size, viewSize: proxy.size, fills: true))
                    }
                }
            }
        } else {
            VStack(spacing: Theme.Spacing.block) {
                Image(systemName: "photo.on.rectangle")
                    .font(.system(size: 40, weight: .regular))
                    .foregroundStyle(Theme.Palette.textTertiary)
                L10n.text("photo.noCamera.image", .camera)
                    .font(Theme.Typography.secondary)
                    .foregroundStyle(Theme.Palette.textTertiary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 40)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.Palette.surface)
        }
    }

    // MARK: Texts over the image

    private var title: Text {
        switch model.stage {
        case .review: return L10n.text("photo.title.review", .camera)
        case .photoLoading, .photoAdjust, .photoValidating, .photoTouchTwenty: return L10n.text("photo.title.handles", .camera)
        case .photoTips: return L10n.text("photo.title.tips", .camera)
        default: return L10n.text("photo.title", .camera)
        }
    }

    private var bubble: Text? {
        switch model.stage {
        case .camera:
            if !model.hasCamera { return L10n.text("photo.bubble.noCamera", .camera) }
            if model.asksEmptyBoard { return L10n.text("scan.state.needsEmptyBoard", .camera) }
            if model.needsNewReference { return L10n.text("photo.bubble.newReference", .camera) }
            return model.scansTurns ? L10n.text("photo.bubble.scan", .camera) : L10n.text("photo.bubble.single", .camera)
        case .scanning: return L10n.text("photo.bubble.scanning", .camera)
        case .review:
            return model.review.isEmpty ? nil : L10n.text("photo.bubble.review", .camera)
        case .photoLoading: return L10n.text("photo.bubble.loading", .camera)
        case .photoAdjust, .photoValidating: return L10n.text("photo.bubble.handles", .camera)
        case .photoTouchTwenty: return L10n.text("calibration.bubble.touchTwenty", .camera)
        case .photoTips:
            if model.remainingDarts == 0 { return L10n.text("photo.bubble.turnFull", .camera) }
            return Text(verbatim: L10n.string("photo.bubble.tips \(model.tips.count) \(model.remainingDarts)", .camera,
                                              language: language))
        case .photoFailed: return L10n.text("photo.bubble.failed", .camera)
        }
    }

    // MARK: Panel

    @ViewBuilder
    private var panel: some View {
        switch model.stage {
        case .camera, .scanning, .photoFailed:
            if !model.lastHits.isEmpty {
                lastPhotoRow
            }
            PhotoNote(text: model.hasCamera ? L10n.text("photo.note.single", .camera) : L10n.text("photo.note.noCamera", .camera))
            shutterRow
            HStack(spacing: 10) {
                SecondaryButton(L10n.text("photo.import", .camera), isEnabled: model.canImport,
                                action: actions.importPhoto)
                SecondaryButton(L10n.text("photo.take", .camera), isEnabled: model.canTakePhoto,
                                action: actions.takePhoto)
            }
        case .review:
            reviewPanel
        case .photoLoading, .photoAdjust, .photoValidating:
            PhotoNote(text: CalibrationText.advice(for: model.issues) ?? L10n.text("photo.note.handles", .camera))
            HStack(spacing: 10) {
                SecondaryButton(L10n.text("calibration.locate", .camera), isEnabled: model.stage == .photoAdjust,
                                action: actions.locatePhoto)
                PrimaryButton(L10n.text("calibration.validate", .camera), isEnabled: model.canValidatePhoto,
                              action: actions.validatePhoto)
            }
        case .photoTouchTwenty:
            PhotoNote(text: CalibrationText.advice(for: model.issues) ?? L10n.text("photo.note.handles", .camera))
            SecondaryButton(L10n.text("photo.handles.again", .camera), action: actions.adjustPhoto)
        case .photoTips:
            if !model.tips.isEmpty {
                HStack(spacing: Theme.Spacing.inline) {
                    ForEach(model.tips) { tip in PhotoChip(text: tip.label) }
                    Spacer(minLength: 0)
                }
                .frame(minHeight: Theme.Control.touchTarget)
            }
            PhotoNote(text: L10n.text("photo.note.tips", .camera))
            HStack(spacing: 10) {
                if model.tips.isEmpty {
                    SecondaryButton(L10n.text("photo.handles.again", .camera), action: actions.adjustPhoto)
                } else {
                    SecondaryButton(L10n.text("photo.tips.removeLast", .camera), action: actions.removeLastTip)
                }
                PrimaryButton(countText, isEnabled: !model.tips.isEmpty, action: actions.confirmTips)
            }
        }
    }

    private var countText: Text {
        switch model.tips.count {
        case 0, 1: return L10n.text("photo.tips.count.one", .camera)
        default: return Text(verbatim: L10n.string("photo.tips.count.other \(model.tips.count)", .camera, language: language))
        }
    }

    /// "Dernière photo  T20  T19  S7   Corriger" (mock-up `PhotoMode`).
    private var lastPhotoRow: some View {
        HStack(spacing: Theme.Spacing.inline) {
            L10n.text("photo.last", .camera)
                .font(CameraStyle.note)
                .foregroundStyle(Theme.Palette.textSecondary)
            ForEach(Array(model.lastHits.enumerated()), id: \.offset) { _, hit in
                PhotoChip(text: hit.notation)
            }
            Spacer(minLength: 0)
            if let correct = actions.correctLast {
                Button(action: correct) {
                    L10n.text("photo.correct", .camera)
                        .font(CameraStyle.link)
                        .foregroundStyle(Theme.Palette.accent)
                        .padding(.horizontal, 4)
                        .frame(minHeight: Theme.Control.touchTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(DesignRowButtonStyle())
            }
        }
        .frame(minHeight: Theme.Control.touchTarget)
    }

    /// "Cible vide", the shutter ("Scanner"), and room for balance.
    private var shutterRow: some View {
        HStack(spacing: Theme.Spacing.inline) {
            Button(action: actions.captureReference) {
                L10n.text("photo.emptyBoard", .camera)
            }
            .buttonStyle(CameraKeyButtonStyle())
            .disabled(!model.canCaptureReference)
            .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: actions.scan) {
                ZStack {
                    Circle().strokeBorder(Theme.Palette.textPrimary, lineWidth: 4)
                    Circle().fill(model.canScan ? Theme.Palette.textPrimary : Theme.Palette.lineStrong)
                        .padding(9)
                }
                .frame(width: CameraStyle.shutter, height: CameraStyle.shutter)
                .contentShape(Circle())
            }
            .buttonStyle(DesignRowButtonStyle())
            .disabled(!model.canScan)
            .accessibilityLabel(L10n.text("photo.scan", .camera))
            L10n.text("photo.scan", .camera)
                .font(CameraStyle.smallButton)
                .foregroundStyle(model.canScan ? Theme.Palette.textPrimary : Theme.Palette.textTertiary)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .accessibilityHidden(true)
        }
        .frame(height: 76)
    }

    @ViewBuilder
    private var reviewPanel: some View {
        if model.review.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Spacing.inline) {
                L10n.text("photo.review.empty", .camera)
                    .font(CameraStyle.playerName)
                    .foregroundStyle(Theme.Palette.textPrimary)
                if let cause = model.emptyCause {
                    PhotoNote(text: L10n.text(PhotoText.causeKey(cause), .camera))
                } else {
                    PhotoNote(text: L10n.text("photo.review.empty.detail", .camera))
                }
            }
            PrimaryButton(L10n.text("photo.review.ok", .camera), action: actions.confirmReview)
        } else {
            VStack(spacing: 6) {
                ForEach(Array(model.review.enumerated()), id: \.element.id) { index, item in
                    PhotoReviewRow(index: index, item: item, moveUp: { actions.moveUp(index) },
                                   discard: { actions.discard(index) })
                }
            }
            PrimaryButton(model.review.count == 1 ? L10n.text("photo.review.confirm.one", .camera)
                          : Text(verbatim: L10n.string("photo.review.confirm.other \(model.review.count)", .camera,
                                                       language: language)),
                          action: actions.confirmReview)
        }
    }
}

private struct PhotoChip: View {
    let text: String

    var body: some View {
        Text(verbatim: text)
            .font(CameraStyle.chip)
            .foregroundStyle(Theme.Palette.textPrimary)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Theme.Palette.background, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.Palette.line, lineWidth: Theme.Control.border)
            }
    }
}

private struct PhotoNote: View {
    let text: Text

    var body: some View {
        text
            .font(CameraStyle.note)
            .foregroundStyle(Theme.Palette.textSecondary)
            .lineSpacing(2)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// One dart of the review: its rank, its hit, "à vérifier", up and discard.
private struct PhotoReviewRow: View {
    let index: Int
    let item: PhotoReviewItem
    let moveUp: () -> Void
    let discard: () -> Void

    var body: some View {
        HStack(spacing: Theme.Spacing.row) {
            Text(verbatim: "\(index + 1)")
                .font(Theme.Typography.badge)
                .foregroundStyle(Theme.Palette.textSecondary)
                .frame(width: 22, height: 22)
                .background(Theme.Palette.surfaceRaised, in: Circle())
            Text(verbatim: item.hit.notation)
                .font(CameraStyle.slot)
                .foregroundStyle(item.needsCheck ? Theme.Palette.accent : Theme.Palette.textPrimary)
            if item.needsCheck {
                BadgeView(L10n.text("scan.slot.review", .camera), color: Theme.Palette.accent)
            }
            Spacer(minLength: 0)
            Button(action: moveUp) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 15, weight: .semibold))
            }
            .buttonStyle(DesignSquareButtonStyle())
            .disabled(index == 0)
            .accessibilityLabel(L10n.text("photo.review.moveUp", .camera))
            Button(action: discard) {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
            }
            .buttonStyle(DesignSquareButtonStyle())
            .accessibilityLabel(L10n.text("photo.review.discard", .camera))
        }
        .padding(.horizontal, Theme.Spacing.block)
        .frame(minHeight: 52)
        .background(Theme.Palette.background, in: RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                .strokeBorder(item.needsCheck ? Theme.Palette.accent : Theme.Palette.line, lineWidth: Theme.Control.border)
        }
    }
}

enum PhotoText {
    static func causeKey(_ cause: PhotoModeModel.EmptyCause) -> LocalizedStringKey {
        switch cause {
        case .obstructed: return "photo.review.cause.obstructed"
        case .lighting: return "photo.review.cause.lighting"
        case .interrupted: return "photo.review.cause.interrupted"
        }
    }
}
