import SwiftUI
import DartCore

/// Roster management: add, rename, reorder, delete. A player's colour is the colour of their place (DESIGN.md
/// §2), shown here in the order of the roster.
struct PlayersScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(\.appLanguage) private var language
    @State private var newName = ""
    @State private var renaming: Player?
    @State private var renamed = ""

    init() {}

    var body: some View {
        ScrollView {
            PlayersContent(players: app.roster, actions: actions, showsHeader: false)
        }
        .scrollIndicators(.hidden)
        .safeAreaInset(edge: .bottom) { addBar }
        .navigationTitle(Text(verbatim: L10n.string("players.title", .game, language: language)))
        .alert(Text(verbatim: L10n.string("players.rename \(renaming?.name ?? "")", .game, language: language)),
               isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField(L10n.string("players.namePlaceholder", .game, language: language), text: $renamed)
            Button(L10n.string("common.save", .common, language: language)) { commitRename() }
            Button(L10n.string("common.cancel", .common, language: language), role: .cancel) { renaming = nil }
        }
    }

    private var actions: PlayersActions {
        PlayersActions(
            rename: { player in
                renamed = player.name
                renaming = player
            },
            move: { player, offset in app.roster = PlayersRoster.moving(player, by: offset, in: app.roster) },
            delete: { player in app.roster.removeAll { $0.id == player.id } })
    }

    private var addBar: some View {
        HStack(spacing: Theme.Spacing.row) {
            TextField(L10n.string("players.namePlaceholder", .game, language: language), text: $newName)
                .textFieldStyle(.plain)
                .font(Theme.Typography.body)
                .padding(.horizontal, 14)
                .frame(height: Theme.Control.rowHeight)
                .background(Theme.Palette.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                        .strokeBorder(Theme.Palette.line, lineWidth: Theme.Control.border)
                }
                .onSubmit(add)
            PrimaryButton(L10n.text("players.add", .game), systemImage: "plus",
                          isEnabled: !PlayersRoster.cleaned(newName).isEmpty, action: add)
                .frame(width: 132)
        }
        .padding(.horizontal, Theme.Metrics.compact.screenMargin)
        .padding(.vertical, Theme.Spacing.block)
        .background(Theme.Palette.background)
    }

    private func add() {
        let name = PlayersRoster.cleaned(newName)
        guard !name.isEmpty else { return }
        app.roster.append(Player(name: name))
        newName = ""
    }

    private func commitRename() {
        defer { renaming = nil }
        guard let player = renaming else { return }
        app.roster = PlayersRoster.renaming(player, to: renamed, in: app.roster)
    }
}

/// Pure edits of the roster.
enum PlayersRoster {
    /// A name without the spaces around it.
    static func cleaned(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The roster with `player` moved by `offset` places, kept inside the list.
    static func moving(_ player: Player, by offset: Int, in roster: [Player]) -> [Player] {
        guard let index = roster.firstIndex(where: { $0.id == player.id }) else { return roster }
        let target = min(max(index + offset, 0), roster.count - 1)
        guard target != index else { return roster }
        var result = roster
        let moved = result.remove(at: index)
        result.insert(moved, at: target)
        return result
    }

    /// The roster with `player` renamed; an empty name keeps the old one.
    static func renaming(_ player: Player, to name: String, in roster: [Player]) -> [Player] {
        let name = cleaned(name)
        guard !name.isEmpty else { return roster }
        return roster.map { $0.id == player.id ? Player(id: $0.id, name: name) : $0 }
    }
}

struct PlayersActions {
    var rename: (Player) -> Void = { _ in }
    /// -1 moves up, +1 moves down.
    var move: (Player, Int) -> Void = { _, _ in }
    var delete: (Player) -> Void = { _ in }
}

/// The roster without its shell (snapshot `players`).
struct PlayersContent: View {
    let players: [Player]
    var actions = PlayersActions()
    var showsHeader = true

    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        let metrics = Theme.Metrics(sizeClass)
        VStack(alignment: .leading, spacing: 14) {
            if showsHeader {
                L10n.text("players.title", .game)
                    .font(Theme.Typography.screenTitle)
                    .frame(height: Theme.Control.touchTarget)
            }
            Group {
                if players.count == 1 {
                    L10n.text("players.count.one", .game)
                } else {
                    L10n.text("players.count.other \(players.count)", .game)
                }
            }
            .font(SetupFonts.section)
            .foregroundStyle(Theme.Palette.textSecondary)
            if players.isEmpty {
                L10n.text("players.empty", .game)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Palette.textSecondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(players.enumerated()), id: \.element.id) { index, player in
                        if index > 0 {
                            Rectangle().fill(Theme.Palette.line).frame(height: Theme.Control.border)
                        }
                        row(player, index: index)
                    }
                }
                .padding(.horizontal, Theme.Spacing.cardInset)
                .background(Theme.Palette.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                        .strokeBorder(Theme.Palette.line, lineWidth: Theme.Control.border)
                }
            }
            L10n.text("players.colorHint", .game)
                .font(Theme.Typography.secondary)
                .foregroundStyle(Theme.Palette.textTertiary)
        }
        .padding(.horizontal, metrics.screenMargin)
        .padding(.vertical, Theme.Spacing.section)
        .frame(maxWidth: sizeClass == .regular ? 640 : .infinity, alignment: .topLeading)
        .frame(maxWidth: .infinity)
    }

    private func row(_ player: Player, index: Int) -> some View {
        HStack(spacing: Theme.Spacing.row) {
            Button { actions.rename(player) } label: {
                HStack(spacing: Theme.Spacing.row) {
                    PlayerChip(name: player.name, index: index)
                    Spacer(minLength: 0)
                    Image(systemName: "pencil")
                        .foregroundStyle(Theme.Palette.textTertiary)
                }
                .frame(minHeight: Theme.Control.rowHeight)
                .contentShape(Rectangle())
            }
            .buttonStyle(DesignRowButtonStyle())
            .accessibilityLabel(L10n.text("players.rename \(player.name)", .game))
            iconButton("chevron.up", label: "players.moveUp \(player.name)", isEnabled: index > 0) { actions.move(player, -1) }
            iconButton("chevron.down", label: "players.moveDown \(player.name)", isEnabled: index < players.count - 1) {
                actions.move(player, 1)
            }
            iconButton("trash", label: "players.delete \(player.name)", tint: Theme.Palette.boardRed) { actions.delete(player) }
        }
    }

    private func iconButton(_ symbol: String, label: LocalizedStringKey, isEnabled: Bool = true,
                            tint: Color = Theme.Palette.textSecondary, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(Theme.Typography.controlSymbol)
                .foregroundStyle(isEnabled ? tint : Theme.Palette.textTertiary)
                .frame(width: 36, height: Theme.Control.touchTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(DesignRowButtonStyle())
        .disabled(!isEnabled)
        .accessibilityLabel(L10n.text(label, .game))
    }
}
