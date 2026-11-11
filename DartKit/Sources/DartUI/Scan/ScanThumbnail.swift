import SwiftUI
import DartCore
import DartVision

/// Camera thumbnail of the iPad column (mock-up `PadPlayKiller`): the camera image, "Caméra en direct", what the
/// vision sees, and "Agrandir", which opens the live scan.
struct ScanThumbnail: View {
    private let camera: CameraModel
    private let onExpand: () -> Void

    init(camera: CameraModel, onExpand: @escaping () -> Void) {
        self.camera = camera
        self.onExpand = onExpand
    }

    var body: some View {
        ScanThumbnailContent(preview: camera.service.preview, rotationDegrees: camera.service.frameInfo?.rotationDegrees ?? 0,
                             state: camera.scanState, readiness: camera.readiness, issue: camera.service.issue,
                             onExpand: onExpand)
    }
}

/// The pure layout of the thumbnail.
struct ScanThumbnailContent: View {
    let preview: PreviewContent
    var rotationDegrees = 0
    let state: ScanState
    let readiness: CameraModel.Readiness
    var issue: CameraIssue?
    var onExpand: () -> Void = {}

    @Environment(\.appLanguage) private var language
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        // On a phone in landscape the column is short: one strip of 64 pt keeps room for the players.
        let compact = sizeClass != .regular
        let height = compact ? CameraStyle.compactThumbnailHeight : CameraStyle.thumbnailHeight
        let shape = RoundedRectangle(cornerRadius: compact ? Theme.Radius.row : 18, style: .continuous)
        HStack(spacing: 0) {
            CameraPreviewView(content: preview, rotationDegrees: rotationDegrees, fills: true)
                .frame(width: height)
                .clipped()
            if compact {
                HStack(spacing: Theme.Spacing.row) {
                    VStack(alignment: .leading, spacing: 0) {
                        title
                        detail
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    expand
                }
                .padding(.horizontal, Theme.Spacing.block)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.Palette.surface)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    title
                    detail
                    Spacer(minLength: 0)
                    expand
                }
                .padding(.leading, Theme.Spacing.section)
                .padding(.trailing, 14)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(Theme.Palette.surface)
            }
        }
        .frame(height: height)
        .clipShape(shape)
        .overlay { shape.strokeBorder(Theme.Palette.line, lineWidth: Theme.Control.border) }
        .accessibilityElement(children: .combine)
    }

    private var title: some View {
        L10n.text("scan.thumbnail.title", .camera)
            .font(CameraStyle.thumbnailTitle)
            .foregroundStyle(Theme.Palette.textPrimary)
            .lineLimit(1)
    }

    private var detail: some View {
        Text(verbatim: Self.detail(state: state, readiness: readiness, issue: issue, language: language))
            .font(Theme.Typography.secondary)
            .foregroundStyle(Theme.Palette.textSecondary)
            .lineLimit(2)
            .minimumScaleFactor(0.85)
    }

    private var expand: some View {
        Button(action: onExpand) {
            L10n.text("scan.thumbnail.expand", .camera)
                .font(CameraStyle.link)
                .foregroundStyle(Theme.Palette.textPrimary)
                .lineLimit(1)
                .padding(.horizontal, Theme.Spacing.section)
                .frame(minHeight: Theme.Control.touchTarget)
                .background(Theme.Palette.surfaceRaised, in: RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(DesignRowButtonStyle())
    }

    /// What the vision sees, in one line.
    static func detail(state: ScanState, readiness: CameraModel.Readiness, issue: CameraIssue?, language: AppLanguage) -> String {
        if let issue { return L10n.string(CameraText.issueKey(issue), .camera, language: language) }
        switch readiness {
        case .unavailable(let issue): return L10n.string(CameraText.issueKey(issue), .camera, language: language)
        case .needsCalibration: return L10n.string("scan.thumbnail.needsCalibration", .camera, language: language)
        case .unknown, .ready: break
        }
        switch state {
        case .watching(let darts):
            switch darts {
            case 0: return L10n.string("scan.thumbnail.empty", .camera, language: language)
            case 1: return L10n.string("scan.thumbnail.darts.one", .camera, language: language)
            default: return L10n.string("scan.thumbnail.darts.other \(darts)", .camera, language: language)
            }
        case .motion, .settling, .analysing: return L10n.string("scan.thumbnail.motion", .camera, language: language)
        case .awaitingTakeout: return L10n.string("scan.thumbnail.awaitingTakeout", .camera, language: language)
        case .takeout: return L10n.string("scan.thumbnail.takeout", .camera, language: language)
        case .obstructed: return L10n.string("scan.thumbnail.obstructed", .camera, language: language)
        case .paused: return L10n.string("scan.thumbnail.paused", .camera, language: language)
        case .idle, .arming: return L10n.string("scan.thumbnail.preparing", .camera, language: language)
        case .needsCalibration, .calibrationLost: return L10n.string("scan.thumbnail.needsCalibration", .camera, language: language)
        }
    }
}
