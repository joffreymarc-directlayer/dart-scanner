import SwiftUI
import DartCore
import DartAudio

// The pure layout of the play screen (ARCHITECTURE.md §8.3, §8.8; mock-ups `PlayKiller`, `PlayX01`,
// `PadPlayKiller`). Fed with plain values, so that SnapshotTool renders it; `PlayScreen` adds the model, the
// sheets and the tasks. It never tests the identifier of the game: the template comes from `playStyle`, the
// board from `boardGeometry`, the texts from the snapshot.

/// What the play screen shows, as values.
struct PlayContentModel {
    var snapshot: GameSnapshot
    var players: [Player]
    var playStyle: PlayStyle
    var boardGeometry: BoardGeometry
    /// Journal records of the current turn, aligned with `snapshot.turn.darts`.
    var records: [DartRecord]
    /// Undecided darts, not counted yet.
    var pending: [Hit]
    var inputStatus: InputStatus
    var prompt: PlayPrompt?
    var canEndTurn: Bool
    var canUndo: Bool

    /// The board is darkened around the highlights on the board template only: on the score template the
    /// mock-up `PlayX01` leaves the board bright around a checkout ring (§8.4.3, DESIGN.md §3).
    var dimsBoard: Bool { playStyle == .board }

    /// Darts drawn on the board: the recorded position when there is one, else the centre of the bed (§8.8).
    var markers: [BoardDartMarker] {
        records.compactMap { record in
            guard let position = record.position ?? BoardGeometry.standard.centre(of: record.hit) else { return nil }
            let style: BoardDartMarker.Style
            if record.needsReview {
                style = .review
            } else if playStyle == .score {
                style = .player(snapshot.currentPlayer)
            } else {
                style = .neutral
            }
            return BoardDartMarker(id: record.id, position: position, label: nil, style: style)
        }
    }

    /// The actions of the header (§8.6, "Accès aux écrans caméra depuis la partie"): "Photo" ALWAYS, whatever
    /// the input mode and the camera; the live scan only when the game has a source.
    var headerActions: [PlayHeaderAction] {
        inputStatus == .manualOnly ? [.photo] : [.scanView, .photo]
    }

    func name(of player: PlayerIndex) -> String {
        players.indices.contains(player) ? players[player].name : "?"
    }

    func row(of player: PlayerIndex) -> PlayerRow? {
        snapshot.players.first { $0.player == player }
    }
}

/// An action of the header of the play screen.
enum PlayHeaderAction: Hashable {
    /// The scan pill opens `LiveScanView`.
    case scanView
    /// "Photo" opens `PhotoModeView`.
    case photo
}

/// What the buttons of the play screen do. Every action is optional: the snapshots pass none.
struct PlayContentActions {
    var tapBoard: (BoardTap) -> Void = { _ in }
    var longPressBoard: ((BoardTap) -> Void)?
    /// A dart of the current turn (index in `records`), then a waiting dart (index in `pending`).
    var openDart: (Int) -> Void = { _ in }
    var openPending: (Int) -> Void = { _ in }
    var miss: () -> Void = {}
    var undo: () -> Void = {}
    var nextPlayer: () -> Void = {}
    var photo: () -> Void = {}
    var scanView: () -> Void = {}
    var quit: () -> Void = {}
    var acceptPrompt: () -> Void = {}
    var dismissPrompt: () -> Void = {}
    var confirmBoardEmpty: () -> Void = {}
}

/// The play screen without its shell.
struct PlayContent: View {
    let model: PlayContentModel
    var actions = PlayContentActions()
    /// The app scrolls the list of players; SnapshotTool cannot render a scroll view (§8.11).
    var scrollsPlayers = false
    /// Camera thumbnail of the side column (lot U3), when the game has a source.
    var thumbnail: AnyView?

    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        GeometryReader { proxy in
            let layout = PlayLayout.resolve(for: proxy.size)
            let metrics = Theme.Metrics(sizeClass)
            // A short screen in landscape (an iPhone): the actions go under the board, the current card drops its
            // big number (the player's row shows it), the camera thumbnail goes under the players and the prompt
            // over the board. The right column then keeps its height for the players, and nothing covers them.
            let short = layout == .sideBySide && proxy.size.height < PlayScreenLayout.shortHeight
            PlayScreenLayout(mode: layout, metrics: metrics, listHeight: listHeight(metrics: metrics), short: short) {
                VStack(alignment: .leading, spacing: Theme.Spacing.block) {
                    PlayHeader(model: model, actions: actions, regular: sizeClass == .regular)
                    PlayCurrentCard(model: model, actions: actions, metrics: metrics, regular: sizeClass == .regular,
                                    showsScore: !short)
                }
                board(promptOver: short)
                if short, let thumbnail {
                    VStack(spacing: Theme.Spacing.block) {
                        playerList(metrics: metrics)
                        thumbnail
                    }
                } else {
                    playerList(metrics: metrics)
                }
                VStack(spacing: Theme.Spacing.block) {
                    if layout == .sideBySide, !short, let thumbnail { thumbnail }
                    if !short { PlayPromptBanner(model: model, actions: actions) }
                    PlayActionBar(model: model, actions: actions, metrics: metrics)
                }
            }
            .padding(.horizontal, metrics.screenMargin)
            .padding(.vertical, layout == .sideBySide ? metrics.screenMargin : Theme.Spacing.section)
        }
    }

    /// Height of the whole list of players (or of the Cricket grid), without scrolling.
    private func listHeight(metrics: Theme.Metrics) -> CGFloat {
        let spacing: CGFloat = sizeClass == .regular ? 8 : 6
        if let grid = model.snapshot.grid {
            return 28 + CGFloat(grid.marks.count) * (metrics.playerRowHeight + 6)
        }
        let count = CGFloat(model.snapshot.players.count)
        return count * metrics.playerRowHeight + max(0, count - 1) * spacing
    }

    private func board(promptOver: Bool) -> some View {
        DartboardView(highlights: model.snapshot.highlights, darts: model.markers, geometry: model.boardGeometry,
                      dimsUnhighlighted: model.dimsBoard, showsNumbers: true,
                      // Manual input stays possible in every state (§8.6): a dart out of turn is refused by
                      // `receive`, which says so ("Tour terminé, retirez les fléchettes").
                      onTap: actions.tapBoard, onLongPress: actions.longPressBoard)
            .overlay(alignment: .bottomTrailing) {
                PlayMissButton(action: actions.miss)
            }
            .overlay(alignment: .bottom) {
                if promptOver {
                    // Over the lower half of the board, above "Manqué", which stays reachable.
                    PlayPromptBanner(model: model, actions: actions)
                        .padding(.bottom, Theme.Control.touchTarget + 4)
                }
            }
    }

    @ViewBuilder
    private func playerList(metrics: Theme.Metrics) -> some View {
        let rows = VStack(spacing: sizeClass == .regular ? 8 : 6) {
            if let grid = model.snapshot.grid {
                PlayGridView(grid: grid, model: model, metrics: metrics)
            } else {
                ForEach(model.snapshot.players, id: \.player) { row in
                    PlayPlayerRowView(row: row, model: model, metrics: metrics)
                }
            }
        }
        if scrollsPlayers {
            ScrollView { rows }
                .scrollIndicators(.hidden)
        } else {
            // Exactly the height the layout gives: what does not fit is cut, never drawn under the actions.
            Color.clear
                .overlay(alignment: .top) { rows }
                .clipped()
        }
    }
}

// MARK: - Layout

/// Places the four blocks of the play screen. One layout for both arrangements, so that the board keeps its
/// identity (and its drawing) across a rotation (§8.8): `stacked` puts the top block, the board, the players and
/// the actions in one column; `sideBySide` puts the board on the left over the full height and the three other
/// blocks in a column on the right. Subviews, in order: top (header and current player), board, players, actions.
private struct PlayScreenLayout: Layout {
    let mode: PlayLayout
    let metrics: Theme.Metrics
    /// Height the list of players needs to show every row.
    let listHeight: CGFloat
    /// `sideBySide` in a container lower than `shortHeight`: the actions are placed under the board, and the right
    /// column holds the top block and the players only (`PlayContent` drops the big number of the card and puts
    /// the prompt over the board).
    var short = false

    /// Below this height (an iPhone in landscape: 440 pt at most) `sideBySide` is short.
    static let shortHeight: CGFloat = 560

    private var gap: CGFloat { Theme.Spacing.block }
    /// Space between the board and the right column in `sideBySide` (mock-up `PadPlayKiller`: 32).
    private var columnGap: CGFloat { metrics.screenMargin }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        proposal.replacingUnspecifiedDimensions(by: CGSize(width: 393, height: 852))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count == 4 else { return }
        let top = subviews[0], board = subviews[1], list = subviews[2], actions = subviews[3]
        switch mode {
        case .stacked:
            let width = bounds.width
            let topHeight = top.sizeThatFits(ProposedViewSize(width: width, height: nil)).height
            let actionsHeight = actions.sizeThatFits(ProposedViewSize(width: width, height: nil)).height
            // The board: a square of at most 45 % of the height, as large as the players then still fit in full;
            // when they cannot, the board keeps 30 % of the height and the list scrolls.
            let around = bounds.height - topHeight - actionsHeight - 3 * gap
            let fitting = around - listHeight
            let floor = min(width, bounds.height * 0.3, around - metrics.playerRowHeight)
            let side = max(0, min(width, bounds.height * 0.45, max(fitting, floor)))
            var y = bounds.minY
            top.place(at: CGPoint(x: bounds.minX, y: y), proposal: ProposedViewSize(width: width, height: topHeight))
            y += topHeight + gap
            board.place(at: CGPoint(x: bounds.midX, y: y), anchor: .top, proposal: ProposedViewSize(width: side, height: side))
            y += side + gap
            let listSpace = max(0, bounds.maxY - actionsHeight - gap - y)
            list.place(at: CGPoint(x: bounds.minX, y: y), proposal: ProposedViewSize(width: width, height: listSpace))
            actions.place(at: CGPoint(x: bounds.minX, y: bounds.maxY), anchor: .bottomLeading,
                          proposal: ProposedViewSize(width: width, height: actionsHeight))
        case .sideBySide where short:
            // Left: the board, then the actions under it. Right: the top block, then the players to the bottom.
            let gap = Theme.Spacing.block
            let widest = max(0, min(bounds.height, bounds.width * 0.6))
            let actionsHeight = actions.sizeThatFits(ProposedViewSize(width: widest, height: nil)).height
            let side = max(0, min(bounds.height - actionsHeight - gap, bounds.width * 0.6))
            board.place(at: CGPoint(x: bounds.minX, y: bounds.minY), anchor: .topLeading,
                        proposal: ProposedViewSize(width: side, height: side))
            actions.place(at: CGPoint(x: bounds.minX, y: bounds.maxY), anchor: .bottomLeading,
                          proposal: ProposedViewSize(width: side, height: actionsHeight))
            let x = bounds.minX + side + columnGap
            let width = max(0, bounds.maxX - x)
            let topHeight = top.sizeThatFits(ProposedViewSize(width: width, height: nil)).height
            top.place(at: CGPoint(x: x, y: bounds.minY), proposal: ProposedViewSize(width: width, height: topHeight))
            let y = bounds.minY + topHeight + gap
            list.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(width: width, height: max(0, bounds.maxY - y)))
        case .sideBySide:
            let side = max(0, min(bounds.height, bounds.width * 0.6))
            board.place(at: CGPoint(x: bounds.minX, y: bounds.midY), anchor: .leading,
                        proposal: ProposedViewSize(width: side, height: side))
            let x = bounds.minX + side + columnGap
            let width = max(0, bounds.maxX - x)
            let topHeight = top.sizeThatFits(ProposedViewSize(width: width, height: nil)).height
            let actionsHeight = actions.sizeThatFits(ProposedViewSize(width: width, height: nil)).height
            let columnGap = Theme.Spacing.section
            top.place(at: CGPoint(x: x, y: bounds.minY), proposal: ProposedViewSize(width: width, height: topHeight))
            let y = bounds.minY + topHeight + columnGap
            let listHeight = max(0, bounds.maxY - actionsHeight - columnGap - y)
            list.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(width: width, height: listHeight))
            actions.place(at: CGPoint(x: x, y: bounds.maxY), anchor: .bottomLeading,
                          proposal: ProposedViewSize(width: width, height: actionsHeight))
        }
    }
}

// MARK: - Header

/// Title, variant and round, objective; state of the scan, "Photo", leave.
private struct PlayHeader: View {
    let model: PlayContentModel
    let actions: PlayContentActions
    let regular: Bool
    @Environment(\.appLanguage) private var language

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            // 26 pt in the header (mock-ups), 44 pt to the finger (DESIGN.md §1).
            PlayTouchTarget(width: 26, height: Theme.Control.touchTarget) {
                Button(action: actions.quit) {
                    Image(systemName: "xmark")
                        .font(Theme.Typography.controlSymbol)
                        .frame(width: Theme.Control.touchTarget, height: Theme.Control.touchTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(DesignRowButtonStyle())
                .accessibilityLabel(L10n.text("play.quit", .game))
            }
            VStack(alignment: .leading, spacing: Theme.Spacing.lines) {
                // Title and subtitle on one line when they fit (mock-up `PlayKiller`), else one under the other.
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.inline) {
                        title
                        subtitleText.lineLimit(1).fixedSize()
                    }
                    VStack(alignment: .leading, spacing: 0) {
                        title
                        subtitleText
                            .lineLimit(2)
                            .minimumScaleFactor(0.85)
                    }
                }
                if let objective = model.snapshot.objective {
                    Text(verbatim: objective[language])
                        .font(regular ? PlayFonts.objectiveRegular : PlayFonts.objective)
                        .foregroundStyle(Theme.Palette.accent)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            PlayStatusPill(status: model.inputStatus, regular: regular, opensScan: model.headerActions.contains(.scanView),
                           action: actions.scanView)
            if model.headerActions.contains(.photo) {
                // The capsule's width in the header, 44 pt to the finger (DESIGN.md §5).
                PlayTouchTarget(width: regular ? 40 : 36, height: Theme.Control.touchTarget) {
                    Button(action: actions.photo) {
                        Image(systemName: "camera")
                            .font(PlayFonts.pillIcon)
                            .foregroundStyle(Theme.Palette.textPrimary)
                            .frame(width: regular ? 40 : 36, height: regular ? 30 : 28)
                            .background(Theme.Palette.surface, in: Capsule())
                            .overlay { Capsule().strokeBorder(Theme.Palette.line, lineWidth: Theme.Control.border) }
                            .frame(width: Theme.Control.touchTarget, height: Theme.Control.touchTarget)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(DesignRowButtonStyle())
                    .accessibilityLabel(L10n.text("play.photo", .game))
                }
            }
        }
    }

    private var title: some View {
        Text(verbatim: model.snapshot.title[language])
            .font(regular ? PlayFonts.titleRegular : Theme.Typography.gameTitle)
            .lineLimit(1)
            .fixedSize()
    }

    private var subtitleText: some View {
        Text(verbatim: subtitle)
            .font(regular ? PlayFonts.subtitleRegular : Theme.Typography.secondary)
            .foregroundStyle(Theme.Palette.textSecondary)
    }

    /// "Facile · manche 4 sur 15".
    private var subtitle: String {
        var parts: [String] = []
        if let variant = model.snapshot.variant { parts.append(variant[language]) }
        let round = model.snapshot.round
        if let limit = model.snapshot.roundLimit {
            parts.append(L10n.string("play.round.limit \(round) \(limit)", .game, language: language))
        } else {
            parts.append(L10n.string("play.round \(round)", .game, language: language))
        }
        return parts.joined(separator: " · ")
    }
}

/// State of the automatic input: a dot and a word. Opens the live scan when the game has a source.
private struct PlayStatusPill: View {
    let status: InputStatus
    let regular: Bool
    let opensScan: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Circle().fill(dot).frame(width: 8, height: 8)
                L10n.text(PlayStatusText.key(for: status), .game)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .font(regular ? PlayFonts.pillRegular : PlayFonts.pill)
            .foregroundStyle(Theme.Palette.textSecondary)
            .padding(.horizontal, regular ? 12 : 10)
            .frame(height: regular ? 30 : 28)
            .background(Theme.Palette.surface, in: Capsule())
            .overlay { Capsule().strokeBorder(Theme.Palette.line, lineWidth: Theme.Control.border) }
            .frame(minHeight: Theme.Control.touchTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(DesignRowButtonStyle())
        .disabled(!opensScan)
    }

    private var dot: Color {
        switch status {
        case .live, .awaitingCapture, .preparing: return Theme.Palette.info
        case .obstructed, .needsEmptyBoard: return Theme.Palette.accent
        case .needsCalibration, .unavailable: return Theme.Palette.boardRed
        case .manualOnly, .paused: return Theme.Palette.textTertiary
        }
    }
}

/// Keys of the scan states (table `Game`).
enum PlayStatusText {
    static func key(for status: InputStatus) -> LocalizedStringKey {
        switch status {
        case .manualOnly: return "play.status.manual"
        case .preparing: return "play.status.preparing"
        case .live: return "play.status.live"
        case .awaitingCapture: return "play.status.awaitingCapture"
        case .obstructed: return "play.status.obstructed"
        case .paused: return "play.status.paused"
        case .needsEmptyBoard: return "play.status.needsEmptyBoard"
        case .needsCalibration: return "play.status.needsCalibration"
        case .unavailable: return "play.status.unavailable"
        }
    }
}

// MARK: - Current player

/// "Au tour de Léa", badges, the main value; the big number of the score template; the three dart slots.
private struct PlayCurrentCard: View {
    let model: PlayContentModel
    let actions: PlayContentActions
    let metrics: Theme.Metrics
    let regular: Bool
    /// The big number of the score template; dropped in a short column, where the player's row shows it.
    var showsScore = true
    @Environment(\.appLanguage) private var language

    var body: some View {
        let player = model.snapshot.currentPlayer
        let row = model.row(of: player)
        VStack(alignment: .leading, spacing: model.playStyle == .score ? 8 : (regular ? 12 : 10)) {
            HStack(spacing: Theme.Spacing.inline) {
                Circle().fill(Theme.playerColor(player)).frame(width: regular ? 14 : 12, height: regular ? 14 : 12)
                // The caller's phrase, so that screen and voice elide alike ("Au tour d'Alice", ARCHITECTURE.md §7.5).
                Text(verbatim: CallerPhrases.nextPlayer(model.name(of: player))[language])
                    .font(regular ? PlayFonts.turnOfRegular : PlayFonts.turnOf)
                    .lineLimit(1)
                    .layoutPriority(1)
                if let row {
                    ForEach(Array(row.badges.enumerated()), id: \.offset) { _, badge in
                        PlayBadge(badge: badge, isCurrent: true, regular: regular)
                    }
                }
                Spacer(minLength: 0)
                if model.playStyle == .board, let trailing = boardTrailing(row) {
                    Text(verbatim: trailing)
                        .font(regular ? PlayFonts.detailRegular : Theme.Typography.secondary)
                        .foregroundStyle(Theme.Palette.textSecondary)
                        .lineLimit(1)
                }
                if model.playStyle == .score, !showsScore {
                    // Without the big number: the hint (a checkout) or the summary of the turn stays on this line.
                    if let hint = model.snapshot.turn.hint {
                        hintText(hint)
                    } else if let summary = model.snapshot.turn.summary {
                        Text(verbatim: summary[language])
                            .font(Theme.Typography.secondary)
                            .foregroundStyle(Theme.Palette.textSecondary)
                            .lineLimit(1)
                    }
                }
            }
            if model.playStyle == .score, showsScore, let row {
                scoreBlock(row)
            }
            PlaySlots(model: model, actions: actions, regular: regular)
        }
        .padding(regular ? 14 : 12)
        .background(Theme.Palette.surface, in: RoundedRectangle(cornerRadius: regular ? 18 : Theme.Radius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: regular ? 18 : Theme.Radius.card, style: .continuous)
                .strokeBorder(Theme.Palette.line, lineWidth: Theme.Control.border)
        }
    }

    /// Board template: the summary of the turn when the game gives one ("Ce trou : 3"), else the main value.
    private func boardTrailing(_ row: PlayerRow?) -> String? {
        if let summary = model.snapshot.turn.summary { return summary[language] }
        guard let row else { return nil }
        return PlayText.primary(row.primary, language: language)
    }

    /// Score template (mock-up `PlayX01`): the big number, the summary of the turn and the hint; the meter of
    /// the row under the big number (the glass being filled of Beer Tap, DESIGN.md §4).
    private func scoreBlock(_ row: PlayerRow) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .bottom, spacing: Theme.Spacing.row) {
                HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.inline) {
                    Text(verbatim: row.primary.text)
                        .font(Theme.Typography.bigScore)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    if let unit = row.primary.unit {
                        Text(verbatim: unit[language])
                            .font(PlayFonts.unit)
                            .foregroundStyle(Theme.Palette.textSecondary)
                    }
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 6) {
                    if let summary = model.snapshot.turn.summary {
                        Text(verbatim: summary[language])
                            .font(Theme.Typography.secondary)
                            .foregroundStyle(Theme.Palette.textSecondary)
                    }
                    if let hint = model.snapshot.turn.hint {
                        hintText(hint)
                    }
                }
            }
            if let meter = row.meter {
                PlayMeterView(meter: meter, color: Theme.playerColor(row.player), width: 140)
            }
        }
    }

    /// The hint of the turn ("T20 T19 D12"), outlined in `accent`.
    private func hintText(_ hint: LocalizedText) -> some View {
        Text(verbatim: hint[language])
            .font(PlayFonts.hint)
            .foregroundStyle(Theme.Palette.accent)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Theme.Palette.accent, lineWidth: Theme.Control.borderBadge)
            }
    }
}

/// The three slots of the current turn: a recorded dart, a waiting dart, or an empty place.
private struct PlaySlots: View {
    let model: PlayContentModel
    let actions: PlayContentActions
    let regular: Bool
    @Environment(\.appLanguage) private var language

    var body: some View {
        let capacity = max(model.snapshot.turn.capacity, 1)
        HStack(spacing: regular ? 10 : 8) {
            ForEach(0..<capacity, id: \.self) { index in
                slot(index)
            }
        }
    }

    @ViewBuilder
    private func slot(_ index: Int) -> some View {
        let darts = model.snapshot.turn.darts
        let shape = RoundedRectangle(cornerRadius: regular ? 14 : Theme.Radius.row, style: .continuous)
        let height: CGFloat = regular ? 64 : 48
        if index < darts.count {
            let record = model.records.indices.contains(index) ? model.records[index] : nil
            let review = record?.needsReview ?? false
            Button { actions.openDart(index) } label: {
                VStack(spacing: Theme.Spacing.lines) {
                    Text(verbatim: darts[index].hit.notation)
                        .font(regular ? PlayFonts.slotRegular : PlayFonts.slot)
                        .foregroundStyle(Theme.Palette.textPrimary)
                    if review {
                        L10n.text("play.slot.review", .game)
                            .font(regular ? PlayFonts.slotCaptionRegular : PlayFonts.slotCaption)
                            .foregroundStyle(Theme.Palette.accent)
                    } else if let caption = darts[index].caption {
                        Text(verbatim: caption.text[language])
                            .font(regular ? PlayFonts.slotCaptionRegular : PlayFonts.slotCaption)
                            .foregroundStyle(caption.tone == .neutral ? Theme.Palette.textSecondary : Theme.color(for: caption.tone))
                    }
                }
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, 4)
                .frame(maxWidth: .infinity, minHeight: height, maxHeight: height)
                .background(Theme.Palette.background, in: shape)
                .overlay {
                    shape.strokeBorder(review ? Theme.Palette.accent : Theme.Palette.line,
                                       lineWidth: review ? Theme.Control.borderStrong : Theme.Control.border)
                }
                .contentShape(shape)
            }
            .buttonStyle(DesignRowButtonStyle())
        } else if index - darts.count < model.pending.count {
            let waiting = index - darts.count
            Button { actions.openPending(waiting) } label: {
                VStack(spacing: Theme.Spacing.lines) {
                    Text(verbatim: "\(model.pending[waiting].notation) ?")
                        .font(regular ? PlayFonts.slotRegular : PlayFonts.slot)
                        .foregroundStyle(Theme.Palette.accent)
                    L10n.text("play.slot.undecided", .game)
                        .font(regular ? PlayFonts.slotCaptionRegular : PlayFonts.slotCaption)
                        .foregroundStyle(Theme.Palette.accent)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity, minHeight: height, maxHeight: height)
                .overlay { shape.strokeBorder(Theme.Palette.accent, style: StrokeStyle(lineWidth: Theme.Control.borderStrong, dash: [5, 4])) }
                .contentShape(shape)
            }
            .buttonStyle(DesignRowButtonStyle())
        } else {
            L10n.text(PlayText.emptySlotKey(index), .game)
                .font(regular ? PlayFonts.emptySlotRegular : Theme.Typography.secondary)
                .foregroundStyle(Theme.Palette.textTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity, minHeight: height, maxHeight: height)
                .overlay { shape.strokeBorder(Theme.Palette.lineStrong, style: StrokeStyle(lineWidth: Theme.Control.border, dash: [4, 3])) }
        }
    }
}

// MARK: - Players

/// One line of the scoreboard (mock-ups `PlayKiller`, `PlayX01`): dot, name, detail, meter or badges, value.
private struct PlayPlayerRowView: View {
    let row: PlayerRow
    let model: PlayContentModel
    let metrics: Theme.Metrics
    @Environment(\.appLanguage) private var language
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        let regular = sizeClass == .regular
        let isCurrent = row.player == model.snapshot.currentPlayer && model.snapshot.phase != .finished
        let color = Theme.playerColor(row.player)
        let shape = RoundedRectangle(cornerRadius: regular ? 14 : Theme.Radius.row, style: .continuous)
        HStack(spacing: regular ? 12 : 10) {
            Circle().fill(color).frame(width: regular ? 12 : 10, height: regular ? 12 : 10)
            Text(verbatim: model.name(of: row.player))
                .font(regular ? PlayFonts.rowNameRegular : PlayFonts.rowName)
                .lineLimit(1)
                .frame(minWidth: regular ? 52 : 44, alignment: .leading)
                .fixedSize(horizontal: true, vertical: false)
            if let detail = row.detail {
                Text(verbatim: detail[language])
                    .font(model.playStyle == .board ? (regular ? PlayFonts.zoneRegular : PlayFonts.zone)
                                                    : (regular ? PlayFonts.detailRegular : Theme.Typography.secondary))
                    .foregroundStyle(model.playStyle == .board ? color : Theme.Palette.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            Spacer(minLength: 0)
            if let meter = row.meter {
                PlayMeterView(meter: meter, color: color, width: regular ? 72 : 56)
            }
            ForEach(Array(row.badges.enumerated()), id: \.offset) { _, badge in
                PlayBadge(badge: badge, isCurrent: isCurrent, regular: regular)
            }
            primary(regular: regular)
        }
        .padding(.horizontal, regular ? 14 : 12)
        .frame(height: metrics.playerRowHeight)
        .background(Theme.Palette.surface, in: shape)
        .overlay {
            shape.strokeBorder(isCurrent ? color : Theme.Palette.line,
                               lineWidth: isCurrent ? Theme.Control.borderStrong : Theme.Control.border)
        }
        .opacity(row.isEliminated ? Theme.Control.disabledOpacity + 0.15 : 1)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func primary(regular: Bool) -> some View {
        if model.playStyle == .score {
            Text(verbatim: row.primary.text)
                .font(regular ? PlayFonts.rowScoreRegular : PlayFonts.rowScore)
                .lineLimit(1)
        } else {
            Text(verbatim: PlayText.primary(row.primary, language: language))
                .font(regular ? PlayFonts.rowValueRegular : PlayFonts.rowValue)
                .lineLimit(1)
                .frame(minWidth: regular ? 52 : 46, alignment: .trailing)
        }
    }
}

/// Cricket: the marks table replaces the list of players (§8.8).
private struct PlayGridView: View {
    let grid: ScoreGrid
    let model: PlayContentModel
    let metrics: Theme.Metrics

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Text(verbatim: "").frame(width: 76, alignment: .leading)
                ForEach(grid.columns.indices, id: \.self) { column in
                    Text(verbatim: grid.columns[column])
                        .font(PlayFonts.gridHeader)
                        .foregroundStyle(grid.dead[safe: column] == true ? Theme.Palette.textTertiary : Theme.Palette.textPrimary)
                        .strikethrough(grid.dead[safe: column] == true)
                        .frame(maxWidth: .infinity)
                }
                Text(verbatim: "").frame(width: 44)
            }
            .frame(height: 28)
            ForEach(grid.marks.indices, id: \.self) { player in
                let isCurrent = player == model.snapshot.currentPlayer && model.snapshot.phase != .finished
                HStack(spacing: 0) {
                    HStack(spacing: 6) {
                        Circle().fill(Theme.playerColor(player)).frame(width: 10, height: 10)
                        Text(verbatim: model.name(of: player))
                            .font(PlayFonts.rowName)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .frame(width: 76, alignment: .leading)
                    ForEach(grid.marks[player].indices, id: \.self) { column in
                        PlayMarkView(marks: grid.marks[player][column], color: Theme.playerColor(player))
                            .frame(maxWidth: .infinity)
                    }
                    Text(verbatim: model.row(of: player)?.primary.text ?? "")
                        .font(PlayFonts.rowScore)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .frame(width: 44, alignment: .trailing)
                }
                .padding(.horizontal, 10)
                .frame(height: metrics.playerRowHeight)
                .background(Theme.Palette.surface, in: shape)
                .overlay {
                    shape.strokeBorder(isCurrent ? Theme.playerColor(player) : Theme.Palette.line,
                                       lineWidth: isCurrent ? Theme.Control.borderStrong : Theme.Control.border)
                }
                .padding(.bottom, 6)
            }
        }
    }
}

/// Cricket marks: "/" for one, "X" for two, a circled X for three; the count is also read aloud.
private struct PlayMarkView: View {
    let marks: Int
    let color: Color

    var body: some View {
        ZStack {
            if marks >= 3 {
                Circle().strokeBorder(color, lineWidth: 2).frame(width: 22, height: 22)
            }
            if marks >= 1 {
                Rectangle().fill(marks >= 1 ? color : .clear).frame(width: 2.5, height: 16).rotationEffect(.degrees(35))
            }
            if marks >= 2 {
                Rectangle().fill(color).frame(width: 2.5, height: 16).rotationEffect(.degrees(-35))
            }
        }
        .frame(width: 24, height: 24)
        .accessibilityLabel(Text(verbatim: String(marks)))
    }
}

/// A badge of a scoreboard line. `accent` is filled on the current player and neutral elsewhere (mock-up
/// `PlayKiller`); a positive or negative badge is an outline in its colour.
private struct PlayBadge: View {
    let badge: Badge
    let isCurrent: Bool
    let regular: Bool
    @Environment(\.appLanguage) private var language

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.badge, style: .continuous)
        let style = PlayBadgeStyle(tone: badge.tone, isCurrent: isCurrent)
        Text(verbatim: badge.text[language])
            .font(regular ? PlayFonts.badgeRegular : Theme.Typography.badge)
            .foregroundStyle(style.text)
            .lineLimit(1)
            .padding(.horizontal, regular ? 9 : 8)
            .padding(.vertical, Theme.Spacing.lines)
            .background(style.fill, in: shape)
            .overlay { if let border = style.border { shape.strokeBorder(border, lineWidth: Theme.Control.border) } }
            .fixedSize()
    }
}

private struct PlayBadgeStyle {
    var fill: Color
    var text: Color
    var border: Color?

    init(tone: Tone, isCurrent: Bool) {
        switch tone {
        case .accent where isCurrent:
            fill = Theme.Palette.accent; text = Theme.Palette.onAccent; border = nil
        case .accent, .neutral:
            fill = Theme.Palette.surfaceRaised; text = Theme.Palette.textPrimary; border = Theme.Palette.lineStrong
        case .positive:
            fill = .clear; text = Theme.Palette.boardGreen; border = Theme.Palette.boardGreen
        case .negative:
            fill = .clear; text = Theme.Palette.boardRed; border = Theme.Palette.boardRed
        }
    }
}

/// Pips (Killer arming) or a bar (lives, progress, the ball, the glass).
private struct PlayMeterView: View {
    let meter: Meter
    let color: Color
    let width: CGFloat

    var body: some View {
        switch meter.style {
        case .pips:
            HStack(spacing: 4) {
                ForEach(0..<max(0, min(meter.maximum, 9)), id: \.self) { index in
                    if index < meter.value {
                        Circle().fill(Theme.Palette.textPrimary).frame(width: 8, height: 8)
                    } else {
                        Circle().strokeBorder(Theme.Palette.textTertiary, lineWidth: 1.5).frame(width: 8, height: 8)
                    }
                }
            }
            .accessibilityLabel(Text(verbatim: "\(meter.value)/\(meter.maximum)"))
        case .bar:
            let fraction = meter.maximum > 0 ? min(1, max(0, CGFloat(meter.value) / CGFloat(meter.maximum))) : 0
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.Palette.line)
                Capsule().fill(color).frame(width: width * fraction)
            }
            .frame(width: width, height: 6)
            .accessibilityLabel(Text(verbatim: "\(meter.value)/\(meter.maximum)"))
        }
    }
}

// MARK: - Actions

/// "Manqué", always visible over the corner of the board (§8.6).
private struct PlayMissButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            L10n.text("play.miss", .game)
                .font(PlayFonts.pill)
                .foregroundStyle(Theme.Palette.textPrimary)
                .padding(.horizontal, 12)
                .frame(height: 30)
                .background(Theme.Palette.surface, in: Capsule())
                .overlay { Capsule().strokeBorder(Theme.Palette.lineStrong, lineWidth: Theme.Control.border) }
                .frame(minHeight: Theme.Control.touchTarget, alignment: .bottom)
                .contentShape(Rectangle())
        }
        .buttonStyle(DesignRowButtonStyle())
    }
}

/// Undo and "Fléchettes retirées, suivant".
private struct PlayActionBar: View {
    let model: PlayContentModel
    let actions: PlayContentActions
    let metrics: Theme.Metrics

    var body: some View {
        HStack(spacing: 10) {
            Button(action: actions.undo) {
                Image(systemName: "arrow.uturn.backward")
                    .font(PlayFonts.undo)
                    .frame(width: metrics.buttonHeight, height: metrics.buttonHeight)
                    .foregroundStyle(model.canUndo ? Theme.Palette.textPrimary : Theme.Palette.textTertiary)
                    .background(Theme.Palette.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                            .strokeBorder(Theme.Palette.line, lineWidth: Theme.Control.border)
                    }
                    .contentShape(Rectangle())
            }
            .buttonStyle(DesignRowButtonStyle())
            .disabled(!model.canUndo)
            .accessibilityLabel(L10n.text("play.undo", .game))
            PrimaryButton(L10n.text("play.nextPlayer", .game), isEnabled: model.canEndTurn, action: actions.nextPlayer)
                .overlay {
                    if model.prompt == .boardCleared {
                        RoundedRectangle(cornerRadius: Theme.Radius.card + 4, style: .continuous)
                            .strokeBorder(Theme.Palette.accent.opacity(0.55), lineWidth: 3)
                            .padding(-5)
                    }
                }
        }
    }
}

/// The message of the moment, with its answer: a dart ignored, a bounce-out, a dart that fell out, a short turn,
/// the advice of the camera, a board to clear.
private struct PlayPromptBanner: View {
    let model: PlayContentModel
    let actions: PlayContentActions
    @Environment(\.appLanguage) private var language

    var body: some View {
        if let content {
            HStack(spacing: Theme.Spacing.row) {
                Image(systemName: content.icon)
                    .foregroundStyle(content.tint)
                content.text
                    .font(PlayFonts.prompt)
                    .foregroundStyle(Theme.Palette.textPrimary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let accept = content.accept {
                    Button(action: content.isBoardQuestion ? actions.confirmBoardEmpty : actions.acceptPrompt) {
                        accept
                            .font(PlayFonts.promptButton)
                            .lineLimit(1)
                            .fixedSize()
                            .foregroundStyle(Theme.Palette.onAccent)
                            .padding(.horizontal, 12)
                            .frame(minHeight: 36)
                            .background(Theme.Palette.accent, in: Capsule())
                            .frame(minHeight: Theme.Control.touchTarget)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(DesignRowButtonStyle())
                }
                if content.dismissable {
                    Button(action: actions.dismissPrompt) {
                        Image(systemName: "xmark")
                            .font(PlayFonts.pillIcon)
                            .foregroundStyle(Theme.Palette.textSecondary)
                            .frame(width: Theme.Control.touchTarget, height: Theme.Control.touchTarget)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(DesignRowButtonStyle())
                    .accessibilityLabel(L10n.text("common.close", .common))
                }
            }
            .padding(.leading, Theme.Spacing.row)
            .padding(.trailing, content.dismissable ? 0 : Theme.Spacing.row)
            .frame(minHeight: Theme.Control.rowHeight)
            .background(Theme.Palette.surfaceRaised, in: RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                    .strokeBorder(content.tint.opacity(0.6), lineWidth: Theme.Control.border)
            }
        }
    }

    private struct Content {
        var icon: String
        var tint: Color
        var text: Text
        var accept: Text?
        var dismissable = true
        var isBoardQuestion = false
    }

    private var content: Content? {
        // The board to clear (§8.7) comes first: nothing is detected until the player answers.
        if model.inputStatus == .needsEmptyBoard {
            return Content(icon: "hand.raised", tint: Theme.Palette.accent, text: L10n.text("play.prompt.needsEmptyBoard", .game),
                           accept: L10n.text("play.prompt.boardEmpty", .game), dismissable: false, isBoardQuestion: true)
        }
        switch model.prompt {
        case .none:
            return nil
        case .dartIgnored?:
            return Content(icon: "hand.raised", tint: Theme.Palette.accent, text: L10n.text("play.prompt.dartIgnored", .game))
        case .possibleMiss?:
            return Content(icon: "arrow.uturn.down", tint: Theme.Palette.info, text: L10n.text("play.prompt.possibleMiss", .game),
                           accept: L10n.text("play.miss", .game))
        case .dartFellOut?:
            return Content(icon: "arrow.down.to.line", tint: Theme.Palette.info, text: L10n.text("play.prompt.fellOut", .game),
                           accept: L10n.text("play.prompt.fellOut.accept", .game))
        case .confirmShortTurn?:
            return Content(icon: "questionmark.circle", tint: Theme.Palette.accent, text: L10n.text("play.prompt.shortTurn", .game),
                           accept: L10n.text("play.prompt.shortTurn.confirm", .game))
        case .boardCleared?:
            return Content(icon: "checkmark.circle", tint: Theme.Palette.info, text: L10n.text("play.prompt.boardCleared", .game))
        case .advisory(let text)?:
            return Content(icon: "info.circle", tint: Theme.Palette.info, text: Text(verbatim: text[language]))
        }
    }
}

// MARK: - Touch targets

/// A control that takes only `width` × `height` in its row but taps over its own, larger frame (44 pt, DESIGN.md
/// §1): it is laid over a placeholder of the smaller size, above its neighbours. A content shape larger than the
/// frame of a button does not do it: such a button takes no tap outside its frame (GameFlowReviewGestureTests).
struct PlayTouchTarget<Content: View>: View {
    var width: CGFloat?
    var height: CGFloat?
    @ViewBuilder var content: Content

    var body: some View {
        Color.clear
            .frame(width: width, height: height)
            .overlay { content }
            .zIndex(1)
    }
}

// MARK: - Texts and fonts

/// Texts the play screen builds from the snapshot.
enum PlayText {
    /// "3 vies", "187", "2 buts".
    static func primary(_ value: ScoreValue, language: AppLanguage) -> String {
        guard let unit = value.unit else { return value.text }
        return "\(value.text) \(unit[language])"
    }

    /// "1re fléchette", "2e fléchette", "3e fléchette".
    static func emptySlotKey(_ index: Int) -> LocalizedStringKey {
        switch index {
        case 0: return "play.slot.1"
        case 1: return "play.slot.2"
        default: return "play.slot.3"
        }
    }
}

/// Sizes read on the mock-ups `PlayKiller`, `PlayX01` and `PadPlayKiller` (iPhone, then iPad).
enum PlayFonts {
    static let titleRegular = Font.system(size: 28, weight: .heavy)
    static let subtitleRegular = Font.system(size: 15, weight: .regular)
    static let objective = Font.system(size: 15, weight: .bold)
    static let objectiveRegular = Font.system(size: 17, weight: .bold)
    static let pill = Font.system(size: 12, weight: .semibold)
    static let pillRegular = Font.system(size: 13, weight: .semibold)
    static let pillIcon = Font.system(size: 14, weight: .semibold)
    static let turnOf = Font.system(size: 17, weight: .bold)
    static let turnOfRegular = Font.system(size: 20, weight: .bold)
    static let detailRegular = Font.system(size: 15, weight: .regular)
    static let unit = Font.system(size: 15, weight: .regular)
    static let hint = Font.system(size: 14, weight: .bold)
    static let slot = Font.system(size: 17, weight: .bold)
    static let slotRegular = Font.system(size: 22, weight: .bold)
    static let slotCaption = Font.system(size: 11, weight: .semibold)
    static let slotCaptionRegular = Font.system(size: 13, weight: .semibold)
    static let emptySlotRegular = Font.system(size: 15, weight: .regular)
    static let rowName = Font.system(size: 15, weight: .bold)
    static let rowNameRegular = Font.system(size: 18, weight: .bold)
    static let zone = Font.system(size: 13, weight: .semibold)
    static let zoneRegular = Font.system(size: 15, weight: .semibold)
    static let rowValue = Font.system(size: 13, weight: .semibold)
    static let rowValueRegular = Font.system(size: 15, weight: .semibold)
    static let rowScore = Font.system(size: 20, weight: .heavy).monospacedDigit()
    static let rowScoreRegular = Font.system(size: 24, weight: .heavy).monospacedDigit()
    static let badgeRegular = Font.system(size: 13, weight: .bold)
    static let gridHeader = Font.system(size: 13, weight: .bold)
    static let undo = Font.system(size: 20, weight: .semibold)
    static let prompt = Font.system(size: 15, weight: .semibold)
    static let promptButton = Font.system(size: 15, weight: .bold)
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
