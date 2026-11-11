import SwiftUI
import DartCore

/// Placement guide (VISION.md §2.1, §2.2): where to put the device, pushed from the settings and shown by the
/// calibration the first time. The shell scrolls; `CameraPlacementContent` is the pure layout.
struct PlacementGuideView: View {
    init() {}

    var body: some View {
        ScrollView {
            CameraPlacementContent()
                .padding(.vertical, Theme.Spacing.section)
        }
        .background(Theme.Palette.background)
        .navigationTitle(L10n.text("placement.title", .camera))
        .toolbarTitleDisplayMode(.inline)
    }
}

/// The illustrated sheet of the placement guide, French first (VISION.md §2.1): a side view of the wall, the
/// board and the device, then the rules, then what to avoid. `continueAction` adds the button of the calibration.
struct CameraPlacementContent: View {
    var step: Text?
    var continueAction: (() -> Void)?

    @Environment(\.horizontalSizeClass) private var sizeClass

    private struct Rule: Identifiable {
        let id: String
        let symbol: String
    }

    private static let rules: [Rule] = [
        Rule(id: "placement.rule.stand", symbol: "iphone"),
        Rule(id: "placement.rule.position", symbol: "ruler"),
        Rule(id: "placement.rule.framing", symbol: "viewfinder"),
        Rule(id: "placement.rule.lens", symbol: "camera"),
        Rule(id: "placement.rule.light", symbol: "lightbulb"),
        Rule(id: "placement.rule.still", symbol: "hand.raised"),
    ]

    var body: some View {
        let margin = Theme.Metrics(sizeClass).screenMargin
        VStack(alignment: .leading, spacing: Theme.Spacing.section) {
            VStack(alignment: .leading, spacing: Theme.Spacing.lines + 2) {
                if let step {
                    step
                        .font(Theme.Typography.secondary)
                        .foregroundStyle(Theme.Palette.textSecondary)
                }
                L10n.text("placement.heading", .camera)
                    .font(CameraStyle.pageTitle)
                    .foregroundStyle(Theme.Palette.textPrimary)
                L10n.text("placement.intro", .camera)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Card {
                CameraPlacementDiagram()
                    .frame(height: 220)
                    .padding(Theme.Spacing.block)
            }
            Card {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(Self.rules.enumerated()), id: \.element.id) { index, rule in
                        if index > 0 {
                            Rectangle().fill(Theme.Palette.line).frame(height: Theme.Control.border)
                        }
                        HStack(alignment: .top, spacing: Theme.Spacing.row) {
                            Image(systemName: rule.symbol)
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(Theme.Palette.info)
                                .frame(width: 24)
                            L10n.text(LocalizedStringKey(rule.id), .camera)
                                .font(Theme.Typography.body)
                                .foregroundStyle(Theme.Palette.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.horizontal, Theme.Spacing.cardInset)
                        .padding(.vertical, Theme.Spacing.block)
                    }
                }
            }
            HStack(alignment: .top, spacing: Theme.Spacing.row) {
                Image(systemName: "xmark.circle")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.Palette.boardRed)
                    .frame(width: 24)
                L10n.text("placement.avoid", .camera)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, Theme.Spacing.cardInset)
            if let continueAction {
                PrimaryButton(L10n.text("placement.continue", .camera), action: continueAction)
            }
        }
        .frame(maxWidth: 640, alignment: .leading)
        .padding(.horizontal, margin)
        .frame(maxWidth: .infinity)
    }
}

/// Side view of the installation (VISION.md §2.1): the board centre at 1.73 m on the wall, the lens 40 to 60 cm
/// below it, about 1 m from the wall, looking up at the board. Drawn to scale in a 2.1 m × 1.4 m box.
private struct CameraPlacementDiagram: View {
    @Environment(\.appLanguage) private var language

    var body: some View {
        Canvas { context, size in
            // Metres to points: the box shows 1.5 m of floor and 2.1 m of height.
            let floorY = size.height - 24
            let scale = min(size.width / 1.5, (floorY - 4) / 2.1)
            let wallX: CGFloat = 18
            func point(_ x: Double, _ y: Double) -> CGPoint {
                CGPoint(x: wallX + CGFloat(x) * scale, y: floorY - CGFloat(y) * scale)
            }
            let line = Theme.Palette.lineStrong
            // Wall and floor.
            var structure = Path()
            structure.move(to: CGPoint(x: wallX, y: 4))
            structure.addLine(to: CGPoint(x: wallX, y: floorY))
            structure.addLine(to: CGPoint(x: size.width - 4, y: floorY))
            context.stroke(structure, with: .color(line), lineWidth: 2)
            // The board: 45 cm across, its centre at 1.73 m.
            let boardTop = point(0, 1.73 + 0.225), boardBottom = point(0, 1.73 - 0.225)
            context.fill(Path(roundedRect: CGRect(x: wallX, y: boardTop.y, width: 7, height: boardBottom.y - boardTop.y),
                              cornerRadius: 2), with: .color(Theme.Palette.boardRed))
            // The lens: 1 m from the wall, 50 cm below the centre; the stand under it.
            let lens = point(1.0, 1.23)
            var stand = Path()
            stand.move(to: lens)
            stand.addLine(to: point(0.85, 0))
            stand.move(to: lens)
            stand.addLine(to: point(1.15, 0))
            stand.move(to: lens)
            stand.addLine(to: point(1.0, 0))
            context.stroke(stand, with: .color(Theme.Palette.textTertiary), lineWidth: 1.5)
            let phone = CGRect(x: lens.x - 4, y: lens.y - 14, width: 8, height: 28)
            context.fill(Path(roundedRect: phone, cornerRadius: 2), with: .color(Theme.Palette.info))
            // Lines of sight to the edges of the board.
            var sight = Path()
            sight.move(to: CGPoint(x: lens.x - 4, y: lens.y))
            sight.addLine(to: CGPoint(x: wallX + 7, y: boardTop.y))
            sight.move(to: CGPoint(x: lens.x - 4, y: lens.y))
            sight.addLine(to: CGPoint(x: wallX + 7, y: boardBottom.y))
            context.stroke(sight, with: .color(Theme.Palette.info.opacity(0.8)), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            // Dimensions.
            var dimensions = Path()
            let centre = point(0, 1.73)
            dimensions.move(to: CGPoint(x: wallX + 10, y: centre.y))
            dimensions.addLine(to: CGPoint(x: lens.x + 22, y: centre.y))
            dimensions.move(to: CGPoint(x: lens.x + 18, y: centre.y))
            dimensions.addLine(to: CGPoint(x: lens.x + 18, y: lens.y))
            context.stroke(dimensions, with: .color(Theme.Palette.accent), style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
            let label = Theme.Typography.secondary
            context.draw(Text(verbatim: L10n.string("placement.diagram.below", .camera, language: language))
                .font(label).foregroundStyle(Theme.Palette.accent),
                         at: CGPoint(x: lens.x + 26, y: (centre.y + lens.y) / 2), anchor: .leading)
            context.draw(Text(verbatim: L10n.string("placement.diagram.centre", .camera, language: language))
                .font(label).foregroundStyle(Theme.Palette.textSecondary),
                         at: CGPoint(x: wallX + 14, y: boardTop.y - 10), anchor: .leading)
            var floorDimension = Path()
            floorDimension.move(to: CGPoint(x: wallX, y: floorY + 6))
            floorDimension.addLine(to: CGPoint(x: lens.x, y: floorY + 6))
            context.stroke(floorDimension, with: .color(Theme.Palette.accent), style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
            context.draw(Text(verbatim: L10n.string("placement.diagram.distance", .camera, language: language))
                .font(label).foregroundStyle(Theme.Palette.textSecondary),
                         at: CGPoint(x: (wallX + lens.x) / 2, y: floorY + 16), anchor: .center)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.text("placement.diagram.label", .camera))
    }
}
