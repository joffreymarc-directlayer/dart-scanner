import Foundation

/// The two languages of the application. French first.
public enum AppLanguage: String, Codable, Sendable, CaseIterable {
    case fr, en

    /// Language to use for a list of preferred language tags (most preferred first):
    /// the first tag that starts with "fr" or "en"; French when none does.
    public init(preferredLanguages: [String]) {
        for tag in preferredLanguages {
            let lower = tag.lowercased()
            if lower.hasPrefix("fr") { self = .fr; return }
            if lower.hasPrefix("en") { self = .en; return }
        }
        self = .fr
    }

    /// BCP 47 tag of the matching speech voice: "fr-FR" or "en-US".
    public var voiceLanguageCode: String {
        switch self {
        case .fr: return "fr-FR"
        case .en: return "en-US"
        }
    }
}

/// A user-facing text carried in both languages. Engines and descriptors produce it; the UI picks one.
/// No bundle and no key: DartCore, DartGames and DartAudio need no string resources.
public struct LocalizedText: Hashable, Codable, Sendable {
    public var fr: String
    public var en: String

    public init(fr: String, en: String) {
        self.fr = fr
        self.en = en
    }

    /// The same text in both languages: numbers, player names, dart notations.
    public init(verbatim text: String) {
        self.init(fr: text, en: text)
    }

    public subscript(language: AppLanguage) -> String {
        switch language {
        case .fr: return fr
        case .en: return en
        }
    }

    /// Singular/plural pair: `count == 1` (and 0 in French) takes the singular. "1 vie", "3 vies", "0 vie" / "0 lives".
    public static func counted(_ count: Int, fr: (one: String, other: String), en: (one: String, other: String)) -> LocalizedText {
        LocalizedText(fr: "\(count) \(count <= 1 ? fr.one : fr.other)",
                      en: "\(count) \(count == 1 ? en.one : en.other)")
    }
}
