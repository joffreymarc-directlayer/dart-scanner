import SwiftUI
import DartCore
import DartAudio

/// Sound, voice, haptics, camera, language (mock-up `Settings`). Every change goes through `app.settings`, which
/// saves it and pushes the sound settings to the sound service at once (§8.10).
struct SettingsScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(\.appLanguage) private var language

    init() {}

    var body: some View {
        @Bindable var app = app
        ScrollView {
            SettingsContent(settings: $app.settings, supportsHaptics: app.environment.sound.supportsHaptics,
                            actions: Self.actions(app: app),
                            showsHeader: false)
        }
        .scrollIndicators(.hidden)
        .navigationTitle(Text(verbatim: L10n.string("settings.title", .game, language: language)))
    }

    /// Where the settings lead (§8.5): the calibration flow, the roster.
    static func actions(app: AppModel) -> SettingsActions {
        SettingsActions(back: { if !app.path.isEmpty { app.path.removeLast() } },
                        recalibrate: { app.cameraFlow = .calibration },
                        players: { app.path.append(.players) })
    }
}

struct SettingsActions {
    var back: () -> Void = {}
    var recalibrate: () -> Void = {}
    var players: () -> Void = {}
}

/// The settings without their shell.
struct SettingsContent: View {
    @Binding var settings: AppSettings
    let supportsHaptics: Bool
    var actions = SettingsActions()
    var showsHeader = true

    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        let metrics = Theme.Metrics(sizeClass)
        VStack(alignment: .leading, spacing: 14) {
            if showsHeader {
                HStack(spacing: Theme.Spacing.inline) {
                    Button(action: actions.back) {
                        Image(systemName: "chevron.left")
                            .font(SetupFonts.back)
                            .frame(width: Theme.Control.touchTarget, height: Theme.Control.touchTarget)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(DesignRowButtonStyle())
                    .padding(.leading, -10)
                    .accessibilityLabel(L10n.text("common.back", .common))
                    L10n.text("settings.title", .game)
                        .font(Theme.Typography.screenTitle)
                }
                .frame(height: Theme.Control.touchTarget)
            }
            section("settings.sound") {
                ToggleRow(L10n.text("settings.effects", .game), isOn: $settings.audio.effectsEnabled)
                separator
                ToggleRow(L10n.text("settings.caller", .game), subtitle: L10n.text("settings.caller.detail", .game),
                          isOn: $settings.audio.callerEnabled)
                separator
                choiceRow("settings.voice", options: [(AppLanguage.fr, L10n.text("language.fr", .game)),
                                                      (AppLanguage.en, L10n.text("language.en", .game))],
                          selection: $settings.audio.callerLanguage)
                separator
                HStack(spacing: Theme.Spacing.row) {
                    L10n.text("settings.volume", .game)
                        .font(Theme.Typography.body)
                        .frame(width: 76, alignment: .leading)
                    LevelSlider(value: $settings.audio.volume)
                }
                .frame(minHeight: 56)
                separator
                ToggleRow(L10n.text("settings.silentMode", .game), subtitle: L10n.text("settings.silentMode.detail", .game),
                          isOn: $settings.audio.playsInSilentMode)
                separator
                ToggleRow(L10n.text("settings.ducking", .game), subtitle: L10n.text("settings.ducking.detail", .game),
                          isOn: $settings.audio.ducksMusicWhileSpeaking)
                separator
                ToggleRow(L10n.text("settings.haptics", .game), subtitle: L10n.text("settings.haptics.detail", .game),
                          isOn: $settings.audio.hapticsEnabled, isEnabled: supportsHaptics)
            }
            section("settings.camera") {
                choiceRow("settings.scanMode", options: [(ScanMode.live, L10n.text("settings.scanMode.live", .game)),
                                                         (ScanMode.photo, L10n.text("settings.scanMode.photo", .game))],
                          selection: $settings.scanMode)
                separator
                ToggleRow(L10n.text("settings.endsTurnOnTakeout", .game),
                          subtitle: L10n.text("settings.endsTurnOnTakeout.detail", .game),
                          isOn: $settings.endsTurnOnTakeout)
                separator
                linkRow("settings.recalibrate", action: actions.recalibrate)
            }
            section("settings.language") {
                choiceRow("settings.language.interface",
                          options: [(SettingsLanguageChoice.system, L10n.text("settings.language.system", .game)),
                                    (SettingsLanguageChoice.fr, L10n.text("language.fr", .game)),
                                    (SettingsLanguageChoice.en, L10n.text("language.en", .game))],
                          selection: Binding(get: { SettingsLanguageChoice(settings.language) },
                                             set: { settings.language = $0.language }),
                          width: 240)
            }
            section("settings.players") {
                linkRow("settings.players.manage", action: actions.players)
            }
        }
        .padding(.horizontal, metrics.screenMargin)
        .padding(.vertical, Theme.Spacing.section)
        .frame(maxWidth: sizeClass == .regular ? 640 : .infinity, alignment: .topLeading)
        .frame(maxWidth: .infinity)
    }

    private func section(_ title: LocalizedStringKey, @ViewBuilder rows: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.inline) {
            L10n.text(title, .game)
                .font(SetupFonts.section)
                .foregroundStyle(Theme.Palette.textSecondary)
            VStack(spacing: 0) { rows() }
                .padding(.horizontal, Theme.Spacing.cardInset)
                .background(Theme.Palette.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                        .strokeBorder(Theme.Palette.line, lineWidth: Theme.Control.border)
                }
        }
    }

    private var separator: some View {
        Rectangle().fill(Theme.Palette.line).frame(height: Theme.Control.border)
    }

    private func choiceRow<Value: Hashable>(_ title: LocalizedStringKey, options: [(value: Value, label: Text)],
                                            selection: Binding<Value>, width: CGFloat = 188) -> some View {
        HStack(spacing: Theme.Spacing.row) {
            L10n.text(title, .game)
                .font(Theme.Typography.body)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, alignment: .leading)
            SegmentedChoice(options: options, selection: selection)
                .frame(width: width)
        }
        .frame(minHeight: 56)
    }

    private func linkRow(_ title: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                L10n.text(title, .game)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Palette.textPrimary)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .foregroundStyle(Theme.Palette.textSecondary)
            }
            .frame(minHeight: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(DesignRowButtonStyle())
    }
}

/// The language of the interface: the system's, or one chosen (`AppSettings.language`).
enum SettingsLanguageChoice: Hashable {
    case system, fr, en

    init(_ language: AppLanguage?) {
        switch language {
        case nil: self = .system
        case .fr?: self = .fr
        case .en?: self = .en
        }
    }

    var language: AppLanguage? {
        switch self {
        case .system: return nil
        case .fr: return .fr
        case .en: return .en
        }
    }
}
