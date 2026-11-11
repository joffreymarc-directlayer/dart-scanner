import SwiftUI
import DartCore

/// The results screen (mock-up `Results`, ARCHITECTURE.md §8.6): shown by `PlayScreen` while
/// `snapshot.phase == .finished`. The game's `winnerTitle` replaces the names of the winners when the game gives
/// one ("Le camp A gagne"); otherwise the players ranked first are named in their colour. It never tests the
/// identifier of the game.
struct ResultsContent: View {
    let snapshot: GameSnapshot
    let players: [Player]
    var canUndo = false
    var rematch: () -> Void = {}
    var changeGame: () -> Void = {}
    var undo: () -> Void = {}
    /// The app scrolls the context row, the headline and the ranking, the two buttons staying pinned under them:
    /// 8 players on an iPhone, or any game on an iPhone in landscape, are taller than the screen. SnapshotTool
    /// cannot render a scroll view (§8.11).
    var scrolls = false

    @Environment(\.appLanguage) private var language
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        let metrics = Theme.Metrics(sizeClass)
        VStack(spacing: 0) {
            if scrolls {
                ScrollView { summary(metrics) }
                    .scrollIndicators(.hidden)
                    .scrollBounceBehavior(.basedOnSize)
            } else {
                summary(metrics)
                    .frame(maxHeight: .infinity, alignment: .top)
            }
            VStack(spacing: 10) {
                PrimaryButton(L10n.text("results.rematch", .game), action: rematch)
                SecondaryButton(L10n.text("results.changeGame", .game), action: changeGame)
            }
            .padding(.horizontal, metrics.screenMargin)
            .padding(.top, 20)
            .padding(.bottom, Theme.Spacing.section)
        }
        .frame(maxWidth: sizeClass == .regular ? 640 : .infinity, maxHeight: .infinity, alignment: .top)
        .frame(maxWidth: .infinity)
    }

    /// The context row with undo, the headline and the ranking.
    private func summary(_ metrics: Theme.Metrics) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .center) {
                Text(verbatim: context)
                    .font(ResultsFonts.context)
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Button(action: undo) {
                    Image(systemName: "arrow.uturn.backward")
                        .font(Theme.Typography.controlSymbol)
                        .foregroundStyle(canUndo ? Theme.Palette.textSecondary : Theme.Palette.textTertiary)
                        .frame(width: Theme.Control.touchTarget, height: Theme.Control.touchTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(DesignRowButtonStyle())
                .disabled(!canUndo)
                .accessibilityLabel(L10n.text("play.undo", .game))
            }
            headline
            VStack(spacing: 8) {
                ForEach(ResultsRanking.order(snapshot), id: \.self) { player in
                    rankingRow(player)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(L10n.text("results.ranking", .game))
        }
        .padding(.horizontal, metrics.screenMargin)
        .padding(.top, Theme.Spacing.section)
        .padding(.bottom, 20)
    }

    /// "Killer · Facile · 9 manches".
    private var context: String {
        var parts = [snapshot.title[language]]
        if let variant = snapshot.variant { parts.append(variant[language]) }
        let rounds = snapshot.round
        parts.append(rounds == 1 ? L10n.string("results.rounds.one", .game, language: language)
                                 : L10n.string("results.rounds.other \(rounds)", .game, language: language))
        return parts.joined(separator: " · ")
    }

    /// The winner in very big letters in their colour, or the title of the game in `textPrimary`.
    private var headline: some View {
        VStack(alignment: .leading, spacing: 4) {
            switch ResultsHeadline(snapshot) {
            case .title(let title):
                Text(verbatim: title[language])
                    .font(Theme.Typography.winner)
                    .foregroundStyle(Theme.Palette.textPrimary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.35)
            case .winners(let winners):
                winnersText(winners)
                    .font(Theme.Typography.winner)
                    .lineLimit(2)
                    .minimumScaleFactor(0.35)
                L10n.text(winners.count > 1 ? "results.wins.other" : "results.wins.one", .game)
                    .font(Theme.Typography.screenTitle)
            }
            if let outcome = snapshot.outcome {
                Text(verbatim: outcome[language])
                    .font(ResultsFonts.outcome)
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    /// "Léa", or "Léa et Tom" on a tie, each name in the colour of its player.
    private func winnersText(_ winners: [PlayerIndex]) -> Text {
        var text = Text(verbatim: "")
        for (position, player) in winners.enumerated() {
            if position > 0 {
                let joiner = position == winners.count - 1
                    ? " \(L10n.string("results.and", .game, language: language)) " : ", "
                text = text + Text(verbatim: joiner).foregroundStyle(Theme.Palette.textPrimary)
            }
            text = text + Text(verbatim: name(player)).foregroundStyle(Theme.playerColor(player))
        }
        return text
    }

    private func rankingRow(_ player: PlayerIndex) -> some View {
        let rank = snapshot.ranks.indices.contains(player) ? snapshot.ranks[player] : snapshot.ranks.count
        let row = snapshot.players.first { $0.player == player }
        let isWinner = rank == 1
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
        let lines = row?.resultLines ?? []
        return HStack(spacing: Theme.Spacing.row) {
            Text(verbatim: String(rank))
                .font(ResultsFonts.rank)
                .frame(width: 24, alignment: .leading)
            Circle().fill(Theme.playerColor(player)).frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: Theme.Spacing.lines) {
                Text(verbatim: name(player))
                    .font(ResultsFonts.name)
                    .lineLimit(1)
                if let first = lines.first {
                    Text(verbatim: first[language])
                        .font(Theme.Typography.secondary)
                        .foregroundStyle(Theme.Palette.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if lines.count > 1 {
                Text(verbatim: lines[1][language])
                    .font(Theme.Typography.secondary)
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            } else if let row {
                Text(verbatim: PlayText.primary(row.primary, language: language))
                    .font(ResultsFonts.value)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 64)
        .background(Theme.Palette.surface, in: shape)
        .overlay {
            shape.strokeBorder(isWinner ? Theme.playerColor(player) : Theme.Palette.line,
                               lineWidth: isWinner ? Theme.Control.borderStrong : Theme.Control.border)
        }
        .accessibilityElement(children: .combine)
    }

    private func name(_ player: PlayerIndex) -> String {
        players.indices.contains(player) ? players[player].name : "?"
    }
}

/// The headline of the results, as data: the title the game gives, else the players ranked first.
enum ResultsHeadline: Equatable {
    /// `snapshot.winnerTitle` ("Le camp A gagne", "Match nul"): shown as it is, in `textPrimary`.
    case title(LocalizedText)
    /// The players ranked first, named in their colours, followed by "gagne(nt) la partie".
    case winners([PlayerIndex])

    init(_ snapshot: GameSnapshot) {
        if let title = snapshot.winnerTitle {
            self = .title(title)
        } else {
            self = .winners(snapshot.winners)
        }
    }
}

/// Order of the ranking: by rank, then by place in the game; tied players share their rank ("1, 1, 3").
enum ResultsRanking {
    static func order(_ snapshot: GameSnapshot) -> [PlayerIndex] {
        snapshot.ranks.indices.sorted { lhs, rhs in
            snapshot.ranks[lhs] != snapshot.ranks[rhs] ? snapshot.ranks[lhs] < snapshot.ranks[rhs] : lhs < rhs
        }
    }
}

/// Sizes read on the mock-up `Results`.
enum ResultsFonts {
    static let context = Font.system(size: 13, weight: .semibold)
    static let outcome = Font.system(size: 15, weight: .regular)
    static let rank = Font.system(size: 24, weight: .heavy).monospacedDigit()
    static let name = Font.system(size: 17, weight: .bold)
    static let value = Font.system(size: 15, weight: .bold)
}
