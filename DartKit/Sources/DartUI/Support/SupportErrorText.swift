import Foundation
import DartCore

// Errors in words (table `Common`, lot U1). `L10n.swift` is the printed listing of ARCHITECTURE.md §8.4.4 and
// stays as it is; this file adds what a screen shows when a game cannot be created.

extension L10n {
    /// One sentence for the player when `AppModel.startGame` throws. A choice that is not allowed with this
    /// number of players says its own reason when the game gives one ("6 joueurs maximum en Facile").
    static func message(for error: GameConfigurationError, language: AppLanguage) -> String {
        switch error {
        case .unknownGame:
            return string("error.unknownGame", .common, language: language)
        case .playerCountOutOfRange(let allowed, _):
            if allowed.lowerBound == allowed.upperBound {
                return allowed.lowerBound == 1
                    ? string("error.playerCount.exact.one", .common, language: language)
                    : string("error.playerCount.exact.other \(allowed.lowerBound)", .common, language: language)
            }
            return string("error.playerCount \(allowed.lowerBound) \(allowed.upperBound)", .common, language: language)
        case .unknownOption, .invalidOptionValue:
            return string("error.invalidOption", .common, language: language)
        case .choiceUnavailable(_, let note):
            return note?[language] ?? string("error.choiceUnavailable", .common, language: language)
        }
    }

    /// The same for any error: the sentence above for a `GameConfigurationError`, a generic one otherwise.
    static func message(for error: any Error, language: AppLanguage) -> String {
        if let error = error as? GameConfigurationError {
            return message(for: error, language: language)
        }
        return string("error.generic", .common, language: language)
    }
}
