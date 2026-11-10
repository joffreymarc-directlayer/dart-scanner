import SwiftUI
import DartCore

// Localisation helpers (ARCHITECTURE.md §8.9).

/// String tables of DartUI. One table per work item, so that no two items edit the same file.
enum L10nTable: String, CaseIterable {
    /// Buttons, generic words, errors (lot U1).
    case common = "Common"
    /// Home, setup, play, correction, results, settings (lot U2).
    case game = "Game"
    /// Permission, placement guide, calibration, live scan, photo mode (lot U3).
    case camera = "Camera"
}

enum L10n {
    /// Resource bundle of DartUI (the `.strings` tables).
    static var bundle: Bundle { .module }

    /// SwiftUI text for a key of a table of `Bundle.module`. Follows `\.locale` (set at the root by `appLanguage(_:)`).
    static func text(_ key: LocalizedStringKey, _ table: L10nTable) -> Text {
        Text(key, tableName: table.rawValue, bundle: .module)
    }

    /// Plain string in an explicit language (accessibility labels built in code, tests, SnapshotTool).
    /// Interpolations follow the String Catalog rules: "turn.total \(n)" looks up the key "turn.total %lld".
    static func string(_ key: String.LocalizationValue, _ table: L10nTable, language: AppLanguage) -> String {
        var resource = LocalizedStringResource(key, table: table.rawValue, bundle: .atURL(Bundle.module.bundleURL))
        resource.locale = Locale(identifier: language.rawValue)
        return String(localized: resource)
    }
}

private struct AppLanguageKey: EnvironmentKey {
    static let defaultValue: AppLanguage = .fr
}

extension EnvironmentValues {
    /// Language of the interface. Set once at the root together with `\.locale`.
    var appLanguage: AppLanguage {
        get { self[AppLanguageKey.self] }
        set { self[AppLanguageKey.self] = newValue }
    }
}

extension View {
    /// Sets `\.appLanguage` and `\.locale` together, so that `Text(_:bundle:)` and `LocalizedText` agree.
    func appLanguage(_ language: AppLanguage) -> some View {
        environment(\.appLanguage, language).environment(\.locale, Locale(identifier: language.rawValue))
    }
}

/// Displays a `LocalizedText` in the language of the environment.
struct LocalizedTextView: View {
    let text: LocalizedText
    @Environment(\.appLanguage) private var language

    init(_ text: LocalizedText) {
        self.text = text
    }

    var body: some View {
        Text(verbatim: text[language])
    }
}
