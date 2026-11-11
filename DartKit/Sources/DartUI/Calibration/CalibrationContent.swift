import SwiftUI
import DartCore
import DartVision

// The pure layout of the calibration (mock-up `Calibration`; ARCHITECTURE.md §8.3, §8.7): the camera image with
// the wireframe in `accent`, the four handles, the instruction in a bubble, and the panel with the alignment, one
// advice and the actions. Fed with plain values: SnapshotTool renders it with a synthetic still.

/// What the calibration screen shows, as values.
struct CalibrationContentModel {
    var stage: CalibrationFlowModel.Stage
    /// The frozen still (or the still of the one-dart check); nil while the camera starts.
    var picture: CGImage?
    var imageSize: PixelSize?
    /// The live camera while no still is shown.
    var preview: PreviewContent = .none
    var rotationDegrees = 0
    var handles: CalibrationHandles?
    /// Wireframe of the handles (adjusting) or of the result (proof).
    var wireframe: BoardWireframe?
    var issues: [CalibrationIssue] = []
    var canValidate = false
    /// Quality of the result of "Valider".
    var quality: CalibrationQuality?
    var rectified: CGImage?
    var tappedHit: Hit?
    var checkTip: ImagePoint?
}

/// What the buttons of the calibration do. The snapshots pass none.
struct CalibrationContentActions {
    var close: () -> Void = {}
    var openSettings: () -> Void = {}
    var continuePlacement: () -> Void = {}
    var locate: () -> Void = {}
    var validate: () -> Void = {}
    var moveHandle: ((CalibrationHandle, ImagePoint) -> Void)?
    /// A touch on the image: the real 20, the tap test, the tip of the check dart.
    var tapImage: ((ImagePoint) -> Void)?
    var adjustAgain: () -> Void = {}
    var adopt: () -> Void = {}
    var startCheck: () -> Void = {}
    var dartPlanted: () -> Void = {}
}

struct CalibrationContent: View {
    let model: CalibrationContentModel
    var actions = CalibrationContentActions()
    /// Status bar and home indicator of SnapshotTool; the safe area in the app.
    var insets = EdgeInsets()

    @Environment(\.appLanguage) private var language

    var body: some View {
        switch model.stage {
        case .unavailable(let issue):
            CameraDeniedContent(issue: issue, openSettings: actions.openSettings, continueManually: actions.close)
                .padding(insets)
        case .placement:
            VStack(spacing: 0) {
                HStack {
                    CameraRoundButton(systemImage: "chevron.left", label: L10n.text("camera.close", .camera),
                                      action: actions.close)
                    Spacer()
                }
                .padding(.horizontal, Theme.Metrics.compact.screenMargin)
                CameraPlacementContent(step: CalibrationText.step(1), continueAction: actions.continuePlacement)
                    .padding(.top, Theme.Spacing.block)
                Spacer(minLength: 0)
            }
            .padding(.top, insets.top + Theme.Spacing.block)
            .padding(.bottom, insets.bottom)
        default:
            CameraScreenFrame(insets: insets) {
                media
            } top: {
                CameraTopBar(buttonImage: "chevron.left", buttonLabel: L10n.text("camera.close", .camera),
                             title: CalibrationText.title(for: model.stage), bubble: bubble, action: actions.close)
            } panel: {
                panel
            }
        }
    }

    // MARK: Image

    @ViewBuilder
    private var media: some View {
        if let picture = model.picture, let size = model.imageSize {
            GeometryReader { proxy in
                let fit = CameraImageFit(imageSize: size, viewSize: proxy.size, fills: false)
                ZStack(alignment: .topLeading) {
                    Image(decorative: picture, scale: 1)
                        .resizable()
                        .interpolation(.medium)
                        .frame(width: CGFloat(size.width) * fit.scale, height: CGFloat(size.height) * fit.scale)
                        .offset(x: fit.origin.x, y: fit.origin.y)
                    overlay(fit: fit, picture: picture)
                }
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
            }
            .overlay(alignment: .bottomTrailing) {
                if let rectified = model.rectified, showsProof {
                    CalibrationProofInset(picture: rectified)
                        .padding(Theme.Spacing.block)
                }
            }
        } else {
            CameraPreviewView(content: model.preview, rotationDegrees: model.rotationDegrees, fills: true)
        }
    }

    private var showsProof: Bool {
        model.stage == .proof || model.stage == .adopted
    }

    @ViewBuilder
    private func overlay(fit: CameraImageFit, picture: CGImage) -> some View {
        switch model.stage {
        case .adjusting, .validating:
            CalibrationOverlay(wireframe: model.wireframe, handles: model.handles, fit: fit, still: picture,
                               onMove: model.stage == .adjusting ? actions.moveHandle : nil)
        case .touchTwenty, .proof, .adopted:
            CalibrationOverlay(wireframe: model.wireframe, handles: nil, fit: fit, onTap: actions.tapImage)
        case .checkTap:
            CalibrationOverlay(wireframe: nil, handles: nil, fit: fit, still: picture, onTap: actions.tapImage)
        case .checking, .checkResult:
            if let tip = model.checkTip {
                CameraTipsOverlay(marks: [CameraTipMark(id: CalibrationText.checkMark, point: tip, label: "+", needsReview: false)],
                                  fit: fit)
            }
        default:
            EmptyView()
        }
    }

    private var bubble: Text? {
        if model.stage == .proof || model.stage == .adopted, let hit = model.tappedHit {
            return Text(verbatim: L10n.string("calibration.tapTest.hit \(hit.notation)", .camera, language: language))
        }
        return CalibrationText.instruction(for: model.stage)
    }

    // MARK: Panel

    @ViewBuilder
    private var panel: some View {
        switch model.stage {
        case .adjusting, .validating, .touchTwenty, .starting, .capturing:
            CalibrationAlignmentRow(level: CalibrationAlignment(issues: model.issues, hasWireframe: model.wireframe != nil))
            CalibrationNote(text: CalibrationText.advice(for: model.issues) ?? L10n.text("calibration.hint.setup", .camera))
            HStack(spacing: 10) {
                if model.stage == .touchTwenty {
                    SecondaryButton(L10n.text("calibration.adjust", .camera), action: actions.adjustAgain)
                } else {
                    SecondaryButton(L10n.text("calibration.locate", .camera), isEnabled: model.stage == .adjusting,
                                    action: actions.locate)
                }
                PrimaryButton(L10n.text("calibration.validate", .camera), isEnabled: model.canValidate,
                              action: actions.validate)
            }
        case .proof, .adopted:
            if let quality = model.quality {
                CalibrationQualityRow(quality: quality)
            }
            CalibrationNote(text: proofNote)
            HStack(spacing: 10) {
                if model.stage == .proof {
                    SecondaryButton(L10n.text("calibration.adjust", .camera), action: actions.adjustAgain)
                    PrimaryButton(L10n.text("calibration.adopt", .camera), action: actions.adopt)
                } else {
                    SecondaryButton(L10n.text("calibration.check.start", .camera), action: actions.startCheck)
                    PrimaryButton(L10n.text("calibration.finish", .camera), action: actions.close)
                }
            }
        case .checkThrow, .checkCapturing:
            CalibrationNote(text: L10n.text("calibration.check.detail", .camera))
            HStack(spacing: 10) {
                SecondaryButton(L10n.text("calibration.finish", .camera), action: actions.close)
                PrimaryButton(L10n.text("calibration.check.planted", .camera), isEnabled: model.stage == .checkThrow,
                              action: actions.dartPlanted)
            }
        case .checkTap, .checking:
            CalibrationNote(text: L10n.text("calibration.check.tapDetail", .camera))
            SecondaryButton(L10n.text("calibration.finish", .camera), action: actions.close)
        case .checkResult(let verdict):
            CalibrationVerdictRow(verdict: verdict)
            HStack(spacing: 10) {
                SecondaryButton(L10n.text("calibration.check.again", .camera), action: actions.startCheck)
                PrimaryButton(L10n.text("calibration.finish", .camera), action: actions.close)
            }
        case .unavailable, .placement:
            EmptyView()
        }
    }

    private var proofNote: Text {
        if let advice = CalibrationText.advice(for: model.quality?.issues ?? []) { return advice }
        return model.stage == .adopted ? L10n.text("calibration.adopted.detail", .camera) : L10n.text("calibration.proof.detail", .camera)
    }
}

/// How well the handles sit while the player moves them: the four bars of the mock-up. Before "Valider" nothing
/// is measured (VISION.md §4.7: `preview` is always `poor`), so the bars read the geometric advice of C1.
struct CalibrationAlignment: Equatable {
    /// 0 to 4.
    var bars: Int
    var key: LocalizedStringKey

    init(issues: [CalibrationIssue], hasWireframe: Bool) {
        let shown = issues.filter { $0 != .intrinsicsApproximate }
        if !hasWireframe || shown.contains(where: \.isBlocking) {
            bars = 0
            key = "calibration.alignment.blocked"
        } else if shown.isEmpty {
            bars = 3
            key = "calibration.alignment.good"
        } else if shown.count == 1 {
            bars = 2
            key = "calibration.alignment.fair"
        } else {
            bars = 1
            key = "calibration.alignment.poor"
        }
    }

    static func == (lhs: CalibrationAlignment, rhs: CalibrationAlignment) -> Bool {
        lhs.bars == rhs.bars
    }
}

private struct CalibrationBars: View {
    let filled: Int
    let color: Color

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<4, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(index < filled ? color : Theme.Palette.line)
                    .frame(width: 14, height: 8)
            }
        }
        .accessibilityHidden(true)
    }
}

private struct CalibrationAlignmentRow: View {
    let level: CalibrationAlignment

    var body: some View {
        HStack(spacing: 10) {
            L10n.text("calibration.alignment", .camera)
                .font(CameraStyle.panelLabel)
                .foregroundStyle(Theme.Palette.textSecondary)
            Spacer(minLength: Theme.Spacing.inline)
            CalibrationBars(filled: level.bars, color: level.bars == 0 ? Theme.Palette.boardRed : Theme.Palette.info)
            L10n.text(level.key, .camera)
                .font(CameraStyle.panelValue)
                .foregroundStyle(Theme.Palette.textPrimary)
        }
        .frame(minHeight: 24)
        .accessibilityElement(children: .combine)
    }
}

/// "Calibrage précis", "Précision estimée ± 0,4 mm" (VISION.md §4.7): green, amber or red, with its words.
private struct CalibrationQualityRow: View {
    let quality: CalibrationQuality
    @Environment(\.appLanguage) private var language

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.inline) {
            HStack(spacing: 10) {
                BadgeView(L10n.text(CalibrationText.gradeKey(quality.grade), .camera), color: color, filled: true)
                Spacer(minLength: 0)
                CalibrationBars(filled: bars, color: color)
            }
            .frame(minHeight: 24)
            Text(verbatim: L10n.string("calibration.accuracy \(CalibrationText.millimetres(quality.estimatedAccuracy, language))",
                                       .camera, language: language))
                .font(CameraStyle.panelValue)
                .foregroundStyle(Theme.Palette.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .accessibilityElement(children: .combine)
    }

    private var color: Color {
        switch quality.grade {
        case .good: return Theme.Palette.boardGreen
        case .fair: return Theme.Palette.accent
        case .poor: return Theme.Palette.boardRed
        }
    }

    private var bars: Int {
        switch quality.grade {
        case .good: return 4
        case .fair: return 3
        case .poor: return 1
        }
    }
}

private struct CalibrationVerdictRow: View {
    let verdict: LightingCheckResult.Verdict

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.inline) {
            BadgeView(L10n.text(verdict == .verified ? "calibration.check.verified" : "calibration.check.notVerified", .camera),
                      color: verdict == .verified ? Theme.Palette.boardGreen : Theme.Palette.accent, filled: true)
            CalibrationNote(text: L10n.text(CalibrationText.verdictKey(verdict), .camera))
        }
    }
}

private struct CalibrationNote: View {
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

/// The proof view (VISION.md §4.7): the board seen from the front through the calibration, with the ideal
/// wireframe over it; a misalignment jumps out.
private struct CalibrationProofInset: View {
    let picture: CGImage

    var body: some View {
        let side: CGFloat = 132
        // The canvas of `BoardCanvas` spans 640 mm; the inset shows the 380 mm around the bull.
        let shown: CGFloat = 380
        let canvas = side * CGFloat(2 * BoardCanvas.halfExtent) / shown
        ZStack {
            Image(decorative: picture, scale: 1)
                .resizable()
                .interpolation(.medium)
                .frame(width: canvas, height: canvas)
            Canvas { context, size in
                let scale = size.width / shown
                let centre = CGPoint(x: size.width / 2, y: size.height / 2)
                let radii = RingRadii.nominal
                for radius in [radii.innerBull, radii.outerBull, radii.trebleInner, radii.trebleOuter, radii.doubleInner, radii.doubleOuter] {
                    let r = CGFloat(radius) * scale
                    context.stroke(Path(ellipseIn: CGRect(x: centre.x - r, y: centre.y - r, width: 2 * r, height: 2 * r)),
                                   with: .color(Theme.Palette.accent), lineWidth: 1)
                }
                for wire in 0..<20 {
                    let angle = (9 + 18 * Double(wire)) * .pi / 180
                    let inner = CGFloat(RingRadii.nominal.outerBull) * scale, outer = CGFloat(RingRadii.nominal.doubleOuter) * scale
                    var path = Path()
                    path.move(to: CGPoint(x: centre.x + inner * CGFloat(sin(angle)), y: centre.y - inner * CGFloat(cos(angle))))
                    path.addLine(to: CGPoint(x: centre.x + outer * CGFloat(sin(angle)), y: centre.y - outer * CGFloat(cos(angle))))
                    context.stroke(path, with: .color(Theme.Palette.accent), lineWidth: 0.75)
                }
            }
            .frame(width: side, height: side)
        }
        .frame(width: side, height: side)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                .strokeBorder(Theme.Palette.textPrimary, lineWidth: 2)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.text("calibration.proof.label", .camera))
    }
}

/// The words of the calibration.
enum CalibrationText {
    static let checkMark = UUID(uuidString: "C0FFEE00-0000-0000-0000-000000000009") ?? UUID()

    static func step(_ number: Int) -> Text {
        L10n.text("calibration.step \(number)", .camera)
    }

    static func title(for stage: CalibrationFlowModel.Stage) -> Text {
        switch stage {
        case .placement: return step(1)
        case .starting, .capturing, .adjusting, .validating, .touchTwenty: return step(2)
        case .proof, .adopted: return step(3)
        case .checkThrow, .checkCapturing, .checkTap, .checking, .checkResult: return L10n.text("calibration.check.title", .camera)
        case .unavailable: return L10n.text("calibration.title", .camera)
        }
    }

    static func instruction(for stage: CalibrationFlowModel.Stage) -> Text? {
        switch stage {
        case .starting: return L10n.text("calibration.bubble.starting", .camera)
        case .capturing, .checkCapturing: return L10n.text("calibration.bubble.capturing", .camera)
        case .adjusting: return L10n.text("calibration.bubble.adjusting", .camera)
        case .validating: return L10n.text("calibration.bubble.validating", .camera)
        case .touchTwenty: return L10n.text("calibration.bubble.touchTwenty", .camera)
        case .proof: return L10n.text("calibration.bubble.proof", .camera)
        case .adopted: return L10n.text("calibration.bubble.adopted", .camera)
        case .checkThrow: return L10n.text("calibration.bubble.checkThrow", .camera)
        case .checkTap: return L10n.text("calibration.bubble.checkTap", .camera)
        case .checking: return L10n.text("calibration.bubble.checking", .camera)
        case .checkResult, .unavailable, .placement: return nil
        }
    }

    /// One advice at a time, the most useful first (VISION.md §2.3): the first issue that has a message.
    static func advice(for issues: [CalibrationIssue]) -> Text? {
        for issue in issues {
            if let key = adviceKey(issue) { return L10n.text(key, .camera) }
        }
        return nil
    }

    static func adviceKey(_ issue: CalibrationIssue) -> LocalizedStringKey? {
        switch issue {
        case .boardOutOfFrame: return "calibration.advice.boardOutOfFrame"
        case .resolutionTooLow: return "calibration.advice.resolutionTooLow"
        case .handlesMirrored, .quadNotConvex, .horizonCrossesBoard: return "calibration.advice.handlesOrder"
        case .resolutionLow: return "calibration.advice.resolutionLow"
        case .viewTooFrontal: return "calibration.advice.viewTooFrontal"
        case .viewTooOblique: return "calibration.advice.viewTooOblique"
        case .dartMarginCutOff: return "calibration.advice.dartMarginCutOff"
        case .sectorPhaseMismatch: return "calibration.advice.sectorPhaseMismatch"
        case .edgesNotFound: return "calibration.advice.edgesNotFound"
        case .refinementRejected: return "calibration.advice.refinementRejected"
        case .intrinsicsApproximate: return nil
        }
    }

    static func gradeKey(_ grade: CalibrationQuality.Grade) -> LocalizedStringKey {
        switch grade {
        case .good: return "calibration.grade.good"
        case .fair: return "calibration.grade.fair"
        case .poor: return "calibration.grade.poor"
        }
    }

    static func verdictKey(_ verdict: LightingCheckResult.Verdict) -> LocalizedStringKey {
        switch verdict {
        case .verified: return "calibration.check.result.verified"
        case .shadowTooHard: return "calibration.check.result.shadowTooHard"
        case .pointNotVisible: return "calibration.check.result.pointNotVisible"
        case .viewTooFrontal: return "calibration.check.result.viewTooFrontal"
        case .failed: return "calibration.check.result.failed"
        }
    }

    /// "0,4" in French, "0.4" in English.
    static func millimetres(_ value: Double, _ language: AppLanguage) -> String {
        let tenths = (value * 10).rounded() / 10
        let text = String(format: "%.1f", tenths)
        return language == .fr ? text.replacingOccurrences(of: ".", with: ",") : text
    }
}
