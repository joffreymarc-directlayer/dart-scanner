import SwiftUI
import DartCore
import DartVision

// The pure layout of the live scan (mock-up `LiveScan`; ARCHITECTURE.md §8.3): the camera image, a ring and a
// label on every dart of the turn (white when sure, amber with "?" when it must be checked), the state in a bubble,
// and the panel with the player, the score, the three slots, "Vérifier" and "Fléchettes retirées".

/// One slot of the turn.
struct ScanSlot: Hashable {
    enum Kind: Hashable {
        case counted(review: Bool)
        /// Not counted yet: the player must answer.
        case pending
        case empty
    }

    var text: LocalizedText
    var caption: LocalizedText?
    var kind: Kind
}

/// What the live scan shows, as values.
struct ScanLiveContentModel {
    var preview: PreviewContent
    var imageSize: PixelSize?
    var rotationDegrees = 0
    var marks: [CameraTipMark] = []
    var status: InputStatus
    var issue: CameraIssue?
    var phase: GamePhase = .throwing
    var playerName: String
    var playerIndex: PlayerIndex
    var subtitle: LocalizedText
    var score: ScoreValue?
    var slots: [ScanSlot]
    /// Label of the first dart to check ("T19") and what opens it.
    var review: (label: String, target: CorrectionTarget)?
    var canEndTurn: Bool
    var prompt: PlayPrompt?

    /// Darts counted or waiting in the turn.
    var dartsInTurn: Int {
        slots.filter { $0.kind != .empty }.count
    }
}

struct ScanLiveActions {
    var close: () -> Void = {}
    var review: (CorrectionTarget) -> Void = { _ in }
    var miss: () -> Void = {}
    var nextPlayer: () -> Void = {}
    var confirmBoardEmpty: () -> Void = {}
    var acceptPrompt: () -> Void = {}
    var dismissPrompt: () -> Void = {}
}

struct ScanLiveContent: View {
    let model: ScanLiveContentModel
    var actions = ScanLiveActions()
    var insets = EdgeInsets()

    @Environment(\.appLanguage) private var language

    var body: some View {
        CameraScreenFrame(insets: insets) {
            GeometryReader { proxy in
                ZStack(alignment: .topLeading) {
                    CameraPreviewView(content: model.preview, rotationDegrees: model.rotationDegrees, fills: true)
                        .frame(width: proxy.size.width, height: proxy.size.height)
                    if let size = model.imageSize {
                        CameraTipsOverlay(marks: model.marks, fit: CameraImageFit(imageSize: size, viewSize: proxy.size, fills: true))
                    }
                }
            }
        } top: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    CameraRoundButton(systemImage: "xmark", label: L10n.text("scan.close", .camera), action: actions.close)
                    CameraTitlePill(text: ScanText.status(model, language: language), dot: ScanText.dot(model))
                }
                if let prompt = model.prompt {
                    ScanPromptBubble(prompt: prompt, accept: actions.acceptPrompt, dismiss: actions.dismissPrompt)
                        .frame(maxWidth: CameraStyle.panelMaxWidth, alignment: .leading)
                }
            }
        } panel: {
            playerRow
            slots
            buttons
        }
    }

    private var playerRow: some View {
        HStack(alignment: .center, spacing: Theme.Spacing.inline) {
            Circle().fill(Theme.playerColor(model.playerIndex)).frame(width: 12, height: 12)
            Text(verbatim: model.playerName)
                .font(CameraStyle.playerName)
                .foregroundStyle(Theme.Palette.textPrimary)
                .lineLimit(1)
            Text(verbatim: model.subtitle[language])
                .font(Theme.Typography.secondary)
                .foregroundStyle(Theme.Palette.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: Theme.Spacing.inline)
            if let score = model.score {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(verbatim: score.text)
                        .font(CameraStyle.score)
                        .foregroundStyle(Theme.Palette.textPrimary)
                    if let unit = score.unit {
                        Text(verbatim: unit[language])
                            .font(Theme.Typography.secondary)
                            .foregroundStyle(Theme.Palette.textSecondary)
                    }
                }
                .lineLimit(1)
            }
        }
        .frame(minHeight: 34)
    }

    private var slots: some View {
        HStack(spacing: Theme.Spacing.inline) {
            ForEach(model.slots.indices, id: \.self) { index in
                ScanSlotView(slot: model.slots[index])
            }
        }
    }

    @ViewBuilder
    private var buttons: some View {
        HStack(spacing: 10) {
            if model.status == .needsEmptyBoard {
                Button(action: actions.confirmBoardEmpty) {
                    L10n.text("scan.boardEmpty", .camera)
                }
                .buttonStyle(CameraAccentOutlineButtonStyle())
            } else if let review = model.review {
                Button { actions.review(review.target) } label: {
                    Text(verbatim: L10n.string("scan.review \(review.label)", .camera, language: language))
                }
                .buttonStyle(CameraAccentOutlineButtonStyle())
            } else {
                SecondaryButton(L10n.text("scan.miss", .camera), isEnabled: model.phase == .throwing, action: actions.miss)
            }
            PrimaryButton(L10n.text("scan.nextPlayer", .camera), isEnabled: model.canEndTurn, action: actions.nextPlayer)
        }
    }
}

/// A slot of the panel (mock-up `LiveScan`): 48 pt, the hit and its caption, amber when it must be checked,
/// dashed when empty.
private struct ScanSlotView: View {
    let slot: ScanSlot
    @Environment(\.appLanguage) private var language

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
        VStack(spacing: 0) {
            Text(verbatim: slot.text[language])
                .font(slot.kind == .empty ? Theme.Typography.secondary : CameraStyle.slot)
                .foregroundStyle(textColor)
            if let caption = slot.caption {
                Text(verbatim: caption[language])
                    .font(CameraStyle.slotCaption)
                    .foregroundStyle(captionColor)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity, minHeight: 48, maxHeight: 48)
        .background(slot.kind == .empty ? Color.clear : Theme.Palette.background, in: shape)
        .overlay { border(shape) }
    }

    @ViewBuilder
    private func border(_ shape: RoundedRectangle) -> some View {
        switch slot.kind {
        case .counted(let review):
            shape.strokeBorder(review ? Theme.Palette.accent : Theme.Palette.line,
                               lineWidth: review ? Theme.Control.borderBadge : Theme.Control.border)
        case .pending:
            shape.strokeBorder(Theme.Palette.accent, style: StrokeStyle(lineWidth: Theme.Control.borderBadge, dash: [5, 4]))
        case .empty:
            shape.strokeBorder(Theme.Palette.lineStrong, style: StrokeStyle(lineWidth: Theme.Control.border, dash: [4, 3]))
        }
    }

    private var textColor: Color {
        switch slot.kind {
        case .counted: return Theme.Palette.textPrimary
        case .pending: return Theme.Palette.accent
        case .empty: return Theme.Palette.textTertiary
        }
    }

    private var captionColor: Color {
        switch slot.kind {
        case .counted(let review): return review ? Theme.Palette.accent : Theme.Palette.textSecondary
        case .pending: return Theme.Palette.accent
        case .empty: return Theme.Palette.textTertiary
        }
    }
}

/// A message of the game over the camera image, with its answer when it asks a question.
private struct ScanPromptBubble: View {
    let prompt: PlayPrompt
    let accept: () -> Void
    let dismiss: () -> Void
    @Environment(\.appLanguage) private var language

    var body: some View {
        HStack(spacing: Theme.Spacing.row) {
            Text(verbatim: ScanText.prompt(prompt, language: language))
                .font(CameraStyle.bubble)
                .foregroundStyle(Theme.Palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            if ScanText.asks(prompt) {
                Button(action: accept) {
                    L10n.text("scan.prompt.yes", .camera)
                        .font(CameraStyle.link)
                        .foregroundStyle(Theme.Palette.accent)
                        .frame(minWidth: Theme.Control.touchTarget, minHeight: Theme.Control.touchTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(DesignRowButtonStyle())
            }
            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .frame(width: Theme.Control.touchTarget, height: Theme.Control.touchTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(DesignRowButtonStyle())
            .accessibilityLabel(L10n.text("scan.prompt.dismiss", .camera))
        }
        .padding(.leading, 14)
        .padding(.trailing, 2)
        .background(Theme.Palette.cameraScrim, in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
    }
}

/// The words of the scan screens.
enum ScanText {
    static func status(_ model: ScanLiveContentModel, language: AppLanguage) -> Text {
        if let issue = model.issue {
            return Text(verbatim: L10n.string(CameraText.issueKey(issue), .camera, language: language))
        }
        switch model.status {
        case .live, .awaitingCapture:
            guard model.phase == .throwing else { return L10n.text("scan.state.turnClosed", .camera) }
            let next = min(model.dartsInTurn + 1, 3)
            switch next {
            case 1: return L10n.text("scan.state.waiting.1", .camera)
            case 2: return L10n.text("scan.state.waiting.2", .camera)
            default: return L10n.text("scan.state.waiting.3", .camera)
            }
        case .preparing: return L10n.text("scan.state.preparing", .camera)
        case .obstructed: return L10n.text("scan.state.obstructed", .camera)
        case .paused: return L10n.text("scan.state.paused", .camera)
        case .needsEmptyBoard: return L10n.text("scan.state.needsEmptyBoard", .camera)
        case .needsCalibration: return L10n.text("scan.state.needsCalibration", .camera)
        case .unavailable: return L10n.text("scan.state.unavailable", .camera)
        case .manualOnly: return L10n.text("scan.state.manual", .camera)
        }
    }

    static func dot(_ model: ScanLiveContentModel) -> Color {
        if model.issue != nil { return Theme.Palette.boardRed }
        switch model.status {
        case .live, .awaitingCapture, .preparing: return Theme.Palette.info
        case .obstructed, .needsEmptyBoard: return Theme.Palette.accent
        case .needsCalibration, .unavailable: return Theme.Palette.boardRed
        case .manualOnly, .paused: return Theme.Palette.textTertiary
        }
    }

    static func prompt(_ prompt: PlayPrompt, language: AppLanguage) -> String {
        switch prompt {
        case .dartIgnored: return L10n.string("scan.prompt.dartIgnored", .camera, language: language)
        case .possibleMiss: return L10n.string("scan.prompt.possibleMiss", .camera, language: language)
        case .dartFellOut: return L10n.string("scan.prompt.dartFellOut", .camera, language: language)
        case .confirmShortTurn: return L10n.string("scan.prompt.confirmShortTurn", .camera, language: language)
        case .boardCleared: return L10n.string("scan.prompt.boardCleared", .camera, language: language)
        case .advisory(let text): return text[language]
        }
    }

    /// The prompts that ask a yes-or-no question.
    static func asks(_ prompt: PlayPrompt) -> Bool {
        switch prompt {
        case .possibleMiss, .dartFellOut, .confirmShortTurn: return true
        case .dartIgnored, .boardCleared, .advisory: return false
        }
    }
}
