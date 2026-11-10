import SwiftUI
import DartCore

/// Sheet of the "+" of the setup screen: a saved player, a new one, or the roster screen. A shell only (it
/// holds a text field, ARCHITECTURE.md §8.11).
struct SetupPlayerPicker: View {
    let available: [Player]
    let canAdd: Bool
    let pick: (Player) -> Void
    let create: (String) -> Void
    let manage: () -> Void
    let close: () -> Void

    @State private var name = ""
    @Environment(\.appLanguage) private var language

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.section) {
                HStack {
                    L10n.text("setup.pick.title", .game)
                        .font(Theme.Typography.gameTitle)
                    Spacer(minLength: 0)
                    Button(action: close) {
                        Image(systemName: "xmark")
                            .font(PlayCorrectionFonts.close)
                            .frame(width: Theme.Control.touchTarget, height: Theme.Control.touchTarget)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(DesignRowButtonStyle())
                    .accessibilityLabel(L10n.text("common.close", .common))
                }
                if available.isEmpty {
                    L10n.text("setup.pick.empty", .game)
                        .font(Theme.Typography.secondary)
                        .foregroundStyle(Theme.Palette.textSecondary)
                } else {
                    SetupFlowLayout(spacing: Theme.Spacing.inline) {
                        ForEach(available) { player in
                            Button { pick(player) } label: {
                                HStack(spacing: Theme.Spacing.inline) {
                                    Image(systemName: "plus").font(Theme.Typography.badge)
                                    Text(verbatim: player.name).font(Theme.Typography.chip).lineLimit(1)
                                }
                                .foregroundStyle(Theme.Palette.textPrimary)
                                .padding(.horizontal, 14)
                                .frame(height: Theme.Control.touchTarget)
                                .background(Theme.Palette.surface, in: Capsule())
                                .overlay { Capsule().strokeBorder(Theme.Palette.line, lineWidth: Theme.Control.border) }
                                .contentShape(Capsule())
                            }
                            .buttonStyle(DesignRowButtonStyle())
                            .disabled(!canAdd)
                        }
                    }
                }
                L10n.text("setup.pick.new", .game)
                    .font(SetupFonts.section)
                    .foregroundStyle(Theme.Palette.textSecondary)
                TextField(L10n.string("setup.pick.namePlaceholder", .game, language: language), text: $name)
                    .textFieldStyle(.plain)
                    .font(Theme.Typography.body)
                    .padding(.horizontal, 14)
                    .frame(height: Theme.Control.rowHeight)
                    .background(Theme.Palette.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                            .strokeBorder(Theme.Palette.line, lineWidth: Theme.Control.border)
                    }
                    .onSubmit(submit)
                PrimaryButton(L10n.text("setup.pick.create", .game), isEnabled: canAdd && !trimmed.isEmpty, action: submit)
                SecondaryButton(L10n.text("setup.pick.manage", .game), systemImage: "person.2", action: manage)
            }
            .padding(Theme.Metrics.compact.screenMargin)
        }
        .background(Theme.Palette.background.ignoresSafeArea())
    }

    private var trimmed: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func submit() {
        guard canAdd, !trimmed.isEmpty else { return }
        create(trimmed)
        name = ""
    }
}
