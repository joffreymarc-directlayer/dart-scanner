import SwiftUI
import DartCore
import DartVision

// The parts shared by the camera screens (mock-ups `Calibration`, `LiveScan`, `PhotoMode`): the camera image over
// the whole width with its buttons and bubbles on a scrim, and the `surface` panel at the bottom. Pure SwiftUI
// (shapes, text, `Image`), so that `ImageRenderer` draws every screen with a synthetic frame (§8.11).

/// Sizes and fonts read on the camera mock-ups.
enum CameraStyle {
    static let titlePill = Font.system(size: 15, weight: .bold)
    static let bubble = Font.system(size: 15, weight: .regular)
    static let panelLabel = Font.system(size: 15, weight: .regular)
    static let panelValue = Font.system(size: 15, weight: .bold)
    static let note = Font.system(size: 13, weight: .regular)
    static let tipLabel = Font.system(size: 14, weight: .heavy)
    static let wireNumber = Font.system(size: 13, weight: .bold)
    static let playerName = Font.system(size: 17, weight: .bold)
    static let score = Font.system(size: 30, weight: .heavy).monospacedDigit()
    static let slot = Font.system(size: 17, weight: .bold)
    static let slotCaption = Font.system(size: 11, weight: .semibold)
    static let chip = Font.system(size: 15, weight: .bold)
    static let smallButton = Font.system(size: 14, weight: .semibold)
    static let link = Font.system(size: 15, weight: .semibold)
    static let thumbnailTitle = Font.system(size: 16, weight: .bold)
    static let pageTitle = Font.system(size: 24, weight: .heavy)

    /// Round button over the image (back, close): 44 pt.
    static let roundButton: CGFloat = 44
    /// Handle of the calibration: 30 pt ring, 3 pt border.
    static let handle: CGFloat = 30
    /// Ring around a detected tip: 20 pt, 3 pt border.
    static let tipRing: CGFloat = 20
    /// Loupe of the calibration and of the taps on a photo (VISION.md §4.4: 4×).
    static let loupe: CGFloat = 124
    static let loupeZoom: CGFloat = 4
    /// Shutter of the photo mode.
    static let shutter: CGFloat = 72
    /// Height of the camera thumbnail of the iPad column (mock-up `PadPlayKiller`).
    static let thumbnailHeight: CGFloat = 128
    /// The same thumbnail in a compact width (a phone in landscape).
    static let compactThumbnailHeight: CGFloat = 64
    /// Widest panel on a large screen: the controls stay where a thumb reaches them.
    static let panelMaxWidth: CGFloat = 560
}

/// Where an image of `imageSize` pixels lies in a view of `viewSize` points, scaled to fit or to fill and
/// centred, as `Image.aspectRatio` and the gravity of the preview layer place it. Image coordinates follow
/// VISION.md §3.1: whole values at the centres of the pixels, so the image spans [−0.5, W − 0.5].
struct CameraImageFit: Equatable {
    var imageSize: CGSize
    var viewSize: CGSize
    var fills: Bool

    init(imageSize: CGSize, viewSize: CGSize, fills: Bool) {
        self.imageSize = imageSize
        self.viewSize = viewSize
        self.fills = fills
    }

    init(imageSize: PixelSize, viewSize: CGSize, fills: Bool) {
        self.init(imageSize: CGSize(width: imageSize.width, height: imageSize.height), viewSize: viewSize, fills: fills)
    }

    /// Points per image pixel.
    var scale: CGFloat {
        guard imageSize.width > 0, imageSize.height > 0 else { return 1 }
        let x = viewSize.width / imageSize.width, y = viewSize.height / imageSize.height
        return fills ? max(x, y) : min(x, y)
    }

    /// Top-left corner of the image in the view.
    var origin: CGPoint {
        CGPoint(x: (viewSize.width - imageSize.width * scale) / 2, y: (viewSize.height - imageSize.height * scale) / 2)
    }

    func viewPoint(_ point: ImagePoint) -> CGPoint {
        CGPoint(x: origin.x + (CGFloat(point.x) + 0.5) * scale, y: origin.y + (CGFloat(point.y) + 0.5) * scale)
    }

    func imagePoint(_ point: CGPoint) -> ImagePoint {
        let s = scale
        return ImagePoint(x: Double((point.x - origin.x) / s - 0.5), y: Double((point.y - origin.y) / s - 0.5))
    }

    /// True when the image point is drawn inside the view.
    func shows(_ point: ImagePoint) -> Bool {
        let p = viewPoint(point)
        return p.x >= 0 && p.y >= 0 && p.x <= viewSize.width && p.y <= viewSize.height
    }
}

/// The layout of a camera screen: the image with its top bar, then the panel. `insets` stands for the status bar
/// and the home indicator in SnapshotTool; in the app the safe area gives them (the image runs under the status
/// bar, the panel under the home indicator).
struct CameraScreenFrame<Media: View, Top: View, Panel: View>: View {
    var insets: EdgeInsets = EdgeInsets()
    let media: Media
    let top: Top
    let panel: Panel

    @Environment(\.horizontalSizeClass) private var sizeClass

    init(insets: EdgeInsets = EdgeInsets(), @ViewBuilder media: () -> Media, @ViewBuilder top: () -> Top,
         @ViewBuilder panel: () -> Panel) {
        self.insets = insets
        self.media = media()
        self.top = top()
        self.panel = panel()
    }

    var body: some View {
        let margin = Theme.Metrics(sizeClass).screenMargin
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                media
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
                    .ignoresSafeArea(.container, edges: .top)
                top
                    .padding(.horizontal, margin)
                    .padding(.top, insets.top + Theme.Spacing.section)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            VStack(alignment: .leading, spacing: Theme.Spacing.block) {
                panel
            }
            .frame(maxWidth: CameraStyle.panelMaxWidth)
            .padding(.horizontal, margin)
            .padding(.top, Theme.Spacing.section)
            .padding(.bottom, Theme.Spacing.section + insets.bottom)
            .frame(maxWidth: .infinity)
            .background(Theme.Palette.surface.ignoresSafeArea(.container, edges: .bottom))
            .overlay(alignment: .top) {
                Rectangle().fill(Theme.Palette.line).frame(height: Theme.Control.border)
            }
        }
        .background(Theme.Palette.background)
    }
}

/// Round 44 pt button on the scrim: back, close.
struct CameraRoundButton: View {
    let systemImage: String
    let label: Text
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Theme.Palette.textPrimary)
                .frame(width: CameraStyle.roundButton, height: CameraStyle.roundButton)
                .background(Theme.Palette.cameraScrim, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(DesignRowButtonStyle())
        .accessibilityLabel(label)
    }
}

/// Pill on the scrim with the title of the screen or the state of the scan, optionally after a coloured dot.
struct CameraTitlePill: View {
    let text: Text
    var dot: Color?

    var body: some View {
        HStack(spacing: Theme.Spacing.inline) {
            if let dot {
                Circle().fill(dot).frame(width: 10, height: 10)
            }
            text
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .font(CameraStyle.titlePill)
        .foregroundStyle(Theme.Palette.textPrimary)
        .padding(.horizontal, Theme.Spacing.section)
        .frame(height: CameraStyle.roundButton)
        .background(Theme.Palette.cameraScrim, in: Capsule())
    }
}

/// The top of a camera screen: a round button and a pill, then an optional bubble of instructions below.
struct CameraTopBar: View {
    let buttonImage: String
    let buttonLabel: Text
    let title: Text
    var dot: Color?
    var bubble: Text?
    /// False: the round button is shown inactive.
    var isEnabled = true
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                CameraRoundButton(systemImage: buttonImage, label: buttonLabel, action: action)
                    .disabled(!isEnabled)
                    .opacity(isEnabled ? 1 : Theme.Control.disabledOpacity)
                CameraTitlePill(text: title, dot: dot)
            }
            if let bubble {
                bubble
                    .font(CameraStyle.bubble)
                    .foregroundStyle(Theme.Palette.textPrimary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 14)
                    .padding(.vertical, Theme.Spacing.block)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.Palette.cameraScrim,
                                in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
                    .frame(maxWidth: CameraStyle.panelMaxWidth, alignment: .leading)
            }
        }
    }
}

/// A full-width button of a panel drawn in `accent` outline (mock-up `LiveScan`, "Vérifier T19").
struct CameraAccentOutlineButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        CameraAccentOutlineBody(configuration: configuration)
    }
}

private struct CameraAccentOutlineBody: View {
    let configuration: ButtonStyle.Configuration
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
        configuration.label
            .font(Theme.Typography.button)
            .foregroundStyle(isEnabled ? Theme.Palette.accent : Theme.Palette.textTertiary)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .padding(.horizontal, Theme.Spacing.section)
            .frame(maxWidth: .infinity, minHeight: Theme.Metrics(sizeClass).buttonHeight)
            .overlay {
                shape.strokeBorder(isEnabled ? Theme.Palette.accent : Theme.Palette.line, lineWidth: Theme.Control.borderBadge)
            }
            .contentShape(shape)
            .opacity(configuration.isPressed ? Theme.Control.pressedOpacity : 1)
    }
}

/// A small outlined key of a panel (mock-up `PhotoMode`, "Cible vide"): 44 pt high, radius 12.
struct CameraKeyButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        CameraKeyBody(configuration: configuration)
    }
}

private struct CameraKeyBody: View {
    let configuration: ButtonStyle.Configuration
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
        configuration.label
            .font(CameraStyle.smallButton)
            .foregroundStyle(isEnabled ? Theme.Palette.textPrimary : Theme.Palette.textTertiary)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.horizontal, Theme.Spacing.block)
            .frame(minHeight: Theme.Control.touchTarget)
            .overlay { shape.strokeBorder(Theme.Palette.line, lineWidth: Theme.Control.border) }
            .contentShape(shape)
            .opacity(isEnabled ? (configuration.isPressed ? Theme.Control.pressedOpacity : 1) : Theme.Control.disabledOpacity)
    }
}

/// A tip seen on the camera image: a ring and its label, white when sure, amber with "?" when it must be checked
/// (mock-up `LiveScan`; DESIGN.md §4: the label doubles the colour).
struct CameraTipMark: Identifiable, Hashable {
    let id: UUID
    var point: ImagePoint
    var label: String
    var needsReview: Bool
}

/// Draws tip marks at their image points over an image placed by `fit`.
struct CameraTipsOverlay: View {
    let marks: [CameraTipMark]
    let fit: CameraImageFit

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(marks) { mark in
                if fit.shows(mark.point) {
                    let point = fit.viewPoint(mark.point)
                    let color = mark.needsReview ? Theme.Palette.accent : Theme.Palette.textPrimary
                    Circle()
                        .strokeBorder(color, lineWidth: 3)
                        .frame(width: CameraStyle.tipRing, height: CameraStyle.tipRing)
                        .position(point)
                    Text(verbatim: mark.label)
                        .font(CameraStyle.tipLabel)
                        .foregroundStyle(color)
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.horizontal, Theme.Spacing.inline)
                        .padding(.vertical, 3)
                        .background(Theme.Palette.background.opacity(0.92),
                                    in: RoundedRectangle(cornerRadius: Theme.Radius.badge, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: Theme.Radius.badge, style: .continuous)
                                .strokeBorder(color, lineWidth: Theme.Control.borderBadge)
                        }
                        .position(x: point.x, y: point.y - 30)
                }
            }
        }
        .frame(width: fit.viewSize.width, height: fit.viewSize.height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: marks.map(\.label).joined(separator: ", ")))
    }
}

extension RGBImage {
    /// A still for a SwiftUI `Image`: nil for an empty image.
    var cameraPicture: CGImage? {
        width > 0 && height > 0 ? makeCGImage() : nil
    }
}
