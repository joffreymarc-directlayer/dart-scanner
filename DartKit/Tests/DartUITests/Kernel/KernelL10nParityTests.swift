import Foundation
import SwiftUI
import Testing
import DartCore
@testable import DartUI

/// Mandatory test of ARCHITECTURE.md §8.9: for every string table, the French and the English files hold exactly
/// the same keys, and no value is empty. The files are read as the document says, with
/// `L10n.bundle.url(forResource:withExtension:subdirectory:localization:)` then `NSDictionary(contentsOf:)`.
@Suite struct KernelL10nParityTests {
    private func entries(_ table: L10nTable, _ language: AppLanguage) throws -> [String: String] {
        let url = try #require(L10n.bundle.url(forResource: table.rawValue, withExtension: "strings", subdirectory: nil,
                                               localization: language.rawValue),
                               "\(table.rawValue).strings is missing in \(language.rawValue).lproj")
        return try #require(NSDictionary(contentsOf: url) as? [String: String], "\(table.rawValue) (\(language.rawValue)) is unreadable")
    }

    /// Format specifiers of a key or of a value, in order: "%lld", "%@".
    private func specifiers(_ text: String) -> [String] {
        var found: [String] = []
        var rest = Substring(text)
        while let percent = rest.firstIndex(of: "%") {
            rest = rest[rest.index(after: percent)...]
            if rest.hasPrefix("%") {
                rest = rest.dropFirst()
            } else if rest.hasPrefix("lld") {
                found.append("%lld")
            } else if rest.hasPrefix("@") {
                found.append("%@")
            } else {
                found.append("%?")
            }
        }
        return found
    }

    @Test func everyTable_hasTheSameKeysInFrenchAndEnglish_andNoEmptyValue() throws {
        #expect(L10nTable.allCases.count == 3)
        for table in L10nTable.allCases {
            let french = try entries(table, .fr), english = try entries(table, .en)
            #expect(!french.isEmpty, "\(table.rawValue) is empty")
            let onlyFrench = Set(french.keys).subtracting(english.keys).sorted()
            let onlyEnglish = Set(english.keys).subtracting(french.keys).sorted()
            #expect(onlyFrench.isEmpty, "\(table.rawValue): keys missing in English: \(onlyFrench)")
            #expect(onlyEnglish.isEmpty, "\(table.rawValue): keys missing in French: \(onlyEnglish)")
            for (language, values) in [(AppLanguage.fr, french), (.en, english)] {
                for (key, value) in values {
                    #expect(!key.isEmpty, "\(table.rawValue) (\(language.rawValue)): empty key")
                    #expect(!value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                            "\(table.rawValue) (\(language.rawValue)): \(key) is empty")
                }
            }
        }
    }

    @Test func everyCommonValue_takesTheParametersOfItsKey() throws {
        // "error.playerCount %lld %lld" must be filled by a value with the same two parameters, in both
        // languages: a value with another parameter would print garbage at run time. Checked on the table of
        // lot U1 only: the other tables may use forms that this simple reader does not know (`%1$lld`).
        for language in AppLanguage.allCases {
            for (key, value) in try entries(.common, language) {
                #expect(specifiers(value) == specifiers(key), "Common (\(language.rawValue)): \(key) = \(value)")
                #expect(!specifiers(key).contains("%?"), "Common: \(key) uses a parameter other than %lld and %@")
            }
        }
    }

    @Test func commonKeys_areSymbolic_screenDotElement() throws {
        // §8.9: English symbolic keys of the form `screen.element`, never a sentence used as a key.
        for key in try entries(.common, .fr).keys {
            let name = key.split(separator: " ").first.map(String.init) ?? ""
            #expect(name.contains("."), "\(key)")
            #expect(name.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == ".") }, "\(key)")
            #expect(key.split(separator: " ").dropFirst().allSatisfy { $0 == "%lld" || $0 == "%@" }, "\(key)")
        }
    }

    @Test func theFilesAreNotMixedUp() throws {
        // The French file holds French and the English one English.
        #expect(try entries(.common, .fr)["common.cancel"] == "Annuler")
        #expect(try entries(.common, .en)["common.cancel"] == "Cancel")
        // The key that lot F0 delivered is still there.
        #expect(try entries(.common, .fr)["common.ok"] == "OK" && entries(.common, .en)["common.ok"] == "OK")
    }
}

/// Localisation helpers of ARCHITECTURE.md §8.4.4 and §8.9 with the `Common` table of lot U1.
@MainActor
@Suite struct KernelL10nTests {
    @Test func string_isReadInTheLanguageThatIsAsked() {
        #expect(L10n.string("common.cancel", .common, language: .fr) == "Annuler")
        #expect(L10n.string("common.cancel", .common, language: .en) == "Cancel")
        #expect(L10n.string("common.confirm", .common, language: .fr) == "Valider")
        #expect(L10n.string("board.label", .common, language: .fr) == "Cible")
        #expect(L10n.string("board.label", .common, language: .en) == "Dartboard")
        #expect(L10n.string("control.on", .common, language: .fr) == "Activé")
        #expect(L10n.string("control.off", .common, language: .en) == "Off")
    }

    @Test func string_fillsItsParameters() {
        // Interpolations follow the String Catalog rules: an Int looks up "%lld", a String "%@".
        #expect(L10n.string("board.darts.other \(3)", .common, language: .fr) == "3 fléchettes")
        #expect(L10n.string("board.darts.other \(3)", .common, language: .en) == "3 darts")
        #expect(L10n.string("board.targets \("20, 1, 18")", .common, language: .fr) == "À viser : 20, 1, 18")
        #expect(L10n.string("board.targets \("20, 1, 18")", .common, language: .en) == "Aim at: 20, 1, 18")
        #expect(L10n.string("error.playerCount \(2) \(8)", .common, language: .fr) == "Ce jeu se joue de 2 à 8 joueurs.")
        #expect(L10n.string("error.playerCount \(2) \(8)", .common, language: .en) == "This game is played by 2 to 8 players.")
    }

    @Test func everyCommonKey_isFoundInBothLanguages() throws {
        // Reading a key through `L10n.string` gives the value of the file, never the key itself.
        for language in AppLanguage.allCases {
            let url = try #require(L10n.bundle.url(forResource: "Common", withExtension: "strings", subdirectory: nil,
                                                   localization: language.rawValue))
            let entries = try #require(NSDictionary(contentsOf: url) as? [String: String])
            for (key, value) in entries where !key.contains("%") {
                #expect(L10n.string(String.LocalizationValue(key), .common, language: language) == value, "\(key)")
            }
        }
    }

    @Test func text_followsTheLanguageOfTheEnvironment() throws {
        // `appLanguage(_:)` sets `\.appLanguage` and `\.locale` together: a table text and a `LocalizedText`
        // are in the same language, also under `ImageRenderer`.
        func picture(_ language: AppLanguage, _ view: some View) throws -> KernelBitmap {
            try KernelBitmap(view.font(Theme.Typography.screenTitle).foregroundStyle(Theme.Palette.textPrimary).appLanguage(language),
                             size: CGSize(width: 240, height: 60))
        }
        // The renderer rounds an anti-aliased pixel of text one level up or down from one rendering to the next
        // (measured: the same view rendered twice differs by 1 on up to 63 edge pixels); two different words
        // differ by more than 200 on a thousand pixels. A pixel counts as different beyond 16 levels.
        func differs(_ a: KernelBitmap, _ b: KernelBitmap) -> Bool {
            for y in 0..<60 {
                for x in 0..<240 where a.color(at: CGPoint(x: x, y: y)).distance(to: b.color(at: CGPoint(x: x, y: y))) > 16 {
                    return true
                }
            }
            return false
        }
        let french = try picture(.fr, L10n.text("common.cancel", .common))
        let english = try picture(.en, L10n.text("common.cancel", .common))
        #expect(differs(french, english))
        // Each one is exactly the text of its language, written verbatim.
        #expect(try !differs(french, picture(.fr, Text(verbatim: "Annuler"))))
        #expect(try !differs(english, picture(.fr, Text(verbatim: "Cancel"))))
        // "OK" is the same word in both: the pictures are the same.
        #expect(try !differs(picture(.fr, L10n.text("common.ok", .common)), picture(.en, L10n.text("common.ok", .common))))
        // A `LocalizedText` follows the same language.
        let both = LocalizedText(fr: "Annuler", en: "Cancel")
        #expect(try !differs(french, picture(.fr, LocalizedTextView(both))))
        #expect(try !differs(english, picture(.en, LocalizedTextView(both))))
    }

    @Test func errorMessage_saysWhyAGameCannotStart() {
        let note = LocalizedText(fr: "6 joueurs maximum en Facile", en: "6 players at most in Easy")
        #expect(L10n.message(for: GameConfigurationError.unknownGame(.killer), language: .fr) == "Ce jeu n'est pas encore disponible.")
        #expect(L10n.message(for: GameConfigurationError.unknownGame(.killer), language: .en) == "This game is not available yet.")
        #expect(L10n.message(for: GameConfigurationError.playerCountOutOfRange(allowed: 2...8, actual: 1), language: .fr)
                == "Ce jeu se joue de 2 à 8 joueurs.")
        #expect(L10n.message(for: GameConfigurationError.playerCountOutOfRange(allowed: 4...4, actual: 3), language: .fr)
                == "Ce jeu se joue à 4 joueurs.")
        #expect(L10n.message(for: GameConfigurationError.playerCountOutOfRange(allowed: 4...4, actual: 3), language: .en)
                == "This game is played by 4 players.")
        #expect(L10n.message(for: GameConfigurationError.playerCountOutOfRange(allowed: 1...1, actual: 2), language: .fr)
                == "Ce jeu se joue seul.")
        #expect(L10n.message(for: GameConfigurationError.unknownOption(key: "x"), language: .fr)
                == L10n.message(for: GameConfigurationError.invalidOptionValue(key: "y"), language: .fr))
        #expect(L10n.message(for: GameConfigurationError.invalidOptionValue(key: "y"), language: .en) == "A game option is not valid.")
        // The reason given by the game is said as it is; without one, a generic sentence.
        #expect(L10n.message(for: GameConfigurationError.choiceUnavailable(key: "level", note: note), language: .fr) == note.fr)
        #expect(L10n.message(for: GameConfigurationError.choiceUnavailable(key: "level", note: note), language: .en) == note.en)
        #expect(L10n.message(for: GameConfigurationError.choiceUnavailable(key: "level", note: nil), language: .fr)
                == "Ce choix n'est pas disponible avec ce nombre de joueurs.")
        // Any other error.
        struct Other: Error {}
        #expect(L10n.message(for: Other(), language: .fr) == "Une erreur est survenue.")
        #expect(L10n.message(for: Other(), language: .en) == "Something went wrong.")
        let wrapped: any Error = GameConfigurationError.unknownGame(.radar)
        #expect(L10n.message(for: wrapped, language: .en) == "This game is not available yet.")
    }
}
