import SwiftUI
import DartCore

/// The levels of a choice option drawn on example boards (mock-up `KillerLevels`): one card per choice with a
/// `.sectors(count:moving:)` pictogram, four example players whose zones are `count` adjacent sectors from the
/// 20, the 6, the 3 and the 11. Built from the descriptor alone: any game whose choices carry such pictograms
/// gets the same explanation.
struct SetupLevelsContent: View {
    let descriptor: GameDescriptor
    let option: OptionDescriptor
    var close: () -> Void = {}

    @Environment(\.appLanguage) private var language
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        let metrics = Theme.Metrics(sizeClass)
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top, spacing: Theme.Spacing.inline) {
                VStack(alignment: .leading, spacing: Theme.Spacing.inline) {
                    L10n.text("setup.levels.title \(descriptor.name[language])", .game)
                        .font(SetupLevelsFonts.title)
                        .fixedSize(horizontal: false, vertical: true)
                    L10n.text("setup.levels.subtitle", .game)
                        .font(SetupLevelsFonts.subtitle)
                        .foregroundStyle(Theme.Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Button(action: close) {
                    Image(systemName: "xmark")
                        .font(PlayCorrectionFonts.close)
                        .frame(width: Theme.Control.touchTarget, height: Theme.Control.touchTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(DesignRowButtonStyle())
                .accessibilityLabel(L10n.text("common.close", .common))
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: sizeClass == .regular ? 220 : 150), spacing: 16)], spacing: 16) {
                ForEach(choices, id: \.value) { choice in
                    card(choice)
                }
            }
        }
        .padding(.horizontal, metrics.screenMargin)
        .padding(.vertical, Theme.Spacing.section + 8)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var choices: [OptionChoice] {
        guard case .choice(let choices) = option.kind else { return [] }
        return choices.filter { $0.illustration != nil }
    }

    private func card(_ choice: OptionChoice) -> some View {
        let range = choice.players ?? descriptor.players
        var moving = false
        var count = 1
        if case .sectors(let sectors, let isMoving)? = choice.illustration {
            count = sectors
            moving = isMoving
        }
        return VStack(spacing: 10) {
            DartboardView(highlights: Self.example(count: count, moving: moving), showsNumbers: true)
                .frame(maxWidth: 200)
                .accessibilityHidden(true)
            Text(verbatim: choice.label[language])
                .font(SetupLevelsFonts.level)
                .multilineTextAlignment(.center)
            if let detail = choice.detail {
                Text(verbatim: detail[language])
                    .font(SetupLevelsFonts.detail)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Group {
                if moving {
                    L10n.text("setup.levels.players \(range.lowerBound) \(range.upperBound)", .game)
                        + Text(verbatim: " ") + L10n.text("setup.levels.moving", .game)
                } else {
                    L10n.text("setup.levels.players \(range.lowerBound) \(range.upperBound)", .game)
                }
            }
            .font(Theme.Typography.secondary)
            .foregroundStyle(Theme.Palette.textSecondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Theme.Palette.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Theme.Palette.line, lineWidth: Theme.Control.border)
        }
    }

    /// Four example players: zones of `count` adjacent sectors from the 20, the 6, the 3 and the 11, clockwise.
    /// A moving zone shows the number left (the 20, faint) and the new one (the 4).
    static func example(count: Int, moving: Bool) -> [BoardHighlight] {
        let order = BoardGeometry.standardSectorOrder
        let width = max(1, min(count, 5))
        var zones: [BoardHighlight] = []
        for (player, first) in [20, 6, 3, 11].enumerated() {
            guard let start = order.firstIndex(of: first) else { continue }
            var numbers = (0..<width).map { order[(start + $0) % 20] }
            if moving && player == 0 {
                zones.append(BoardHighlight(zone: .sector(first), role: .secondary, owner: player))
                numbers = [4]
            }
            zones += numbers.map { BoardHighlight(zone: .sector($0), role: .target, owner: player) }
        }
        return zones
    }
}

/// Sizes read on the mock-up `KillerLevels`.
enum SetupLevelsFonts {
    static let title = Font.system(size: 28, weight: .heavy)
    static let subtitle = Font.system(size: 15, weight: .regular)
    static let level = Font.system(size: 22, weight: .heavy)
    static let detail = Font.system(size: 16, weight: .semibold)
}
