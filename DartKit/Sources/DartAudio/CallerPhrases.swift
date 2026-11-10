// DartAudio — the sentences of the score caller, in both languages (ARCHITECTURE.md §7.5).
import Foundation
import DartCore

/// Sentences of the score caller. Numbers stay in digits: the voice reads "180" as "cent quatre-vingts".
public enum CallerPhrases {
    /// "Triple 20" / "Treble 20", "Double 16", "20", "Bull" (SB), "Double bull" / "Bullseye" (DB), "Manqué" / "Miss".
    public static func hit(_ hit: Hit) -> LocalizedText {
        let number = hit.number ?? 0
        switch hit.bed {
        case .treble: return LocalizedText(fr: "Triple \(number)", en: "Treble \(number)")
        case .double: return LocalizedText(verbatim: "Double \(number)")
        case .single: return LocalizedText(verbatim: "\(number)")
        case .outerBull: return LocalizedText(verbatim: "Bull")
        case .innerBull: return LocalizedText(fr: "Double bull", en: "Bullseye")
        case .miss: return LocalizedText(fr: "Manqué", en: "Miss")
        }
    }

    /// The total in digits, the same in both languages: "140", "180". The exclamation of a 180 belongs to the
    /// `oneEighty` event (`phrase(for:context:)`), which Radar never emits.
    public static func turnTotal(_ points: Int) -> LocalizedText {
        LocalizedText(verbatim: "\(points)")
    }

    /// "Au tour de Léa" / "Léa to throw".
    public static func nextPlayer(_ name: String) -> LocalizedText {
        LocalizedText(fr: "Au tour \(frenchOf(name))", en: "\(name) to throw")
    }

    /// "Léa gagne la partie" / "Léa wins"; "Égalité entre Léa et Tom" / "Léa and Tom tie" for several names.
    /// Not called when `CueContext.winnerTitle` is set: that headline is said instead.
    public static func winners(_ names: [String]) -> LocalizedText {
        switch names.count {
        case 0:
            // Nobody to name (a finished game without a winner): the end of the game is still announced.
            return LocalizedText(fr: "Partie terminée", en: "Game over")
        case 1:
            return LocalizedText(fr: "\(names[0]) gagne la partie", en: "\(names[0]) wins")
        default:
            return LocalizedText(fr: "Égalité entre \(list(names, and: "et"))", en: "\(list(names, and: "and")) tie")
        }
    }

    /// The sentence of one event, by the table of ARCHITECTURE.md §7.3: "Léa est Killer", "Tom est éliminé",
    /// "Nouveau numéro : 16", "Cent quatre-vingts !", "But !", "Trou en un !", "3 coups"… Nil for an event without one.
    public static func phrase(for event: GameEvent, context: CueContext) -> LocalizedText? {
        switch event {
        case .dartRegistered(_, let hit):
            return self.hit(hit)
        case .turnStarted(let player, _):
            // Nothing in a solo game: there is nobody else to call.
            guard context.players.count > 1, let name = name(of: player, in: context) else { return nil }
            return nextPlayer(name)
        case .turnScored(_, let points):
            return turnTotal(points)
        case .oneEighty:
            return LocalizedText(fr: "Cent quatre-vingts !", en: "One hundred and eighty!")
        case .bust:
            return LocalizedText(verbatim: "Bust")
        case .becameKiller(let player):
            guard let name = name(of: player, in: context) else { return nil }
            return LocalizedText(fr: "\(name) est Killer", en: "\(name) is a Killer")
        case .kingOfTheHill(let player):
            guard let name = name(of: player, in: context) else { return nil }
            return LocalizedText(fr: "\(name) est Roi", en: "\(name) is King")
        case .zoneChanged(_, let zone):
            return newZone(zone)
        case .shanghai:
            return LocalizedText(fr: "Shanghai !", en: "Shanghai!")
        case .halved:
            return LocalizedText(fr: "Score divisé par deux", en: "Score halved")
        case .bonusGlass:
            return LocalizedText(fr: "Tournée offerte !", en: "This one's on the house!")
        case .goalScored(_, _, _, let ownGoal):
            return ownGoal
                ? LocalizedText(fr: "Contre son camp !", en: "Own goal!")
                : LocalizedText(fr: "But !", en: "Goal!")
        case .holeCompleted(_, _, let strokes, _):
            return .counted(strokes, fr: (one: "coup", other: "coups"), en: (one: "stroke", other: "strokes"))
        case .holeInOne:
            return LocalizedText(fr: "Trou en un !", en: "Hole in one!")
        case .playerEliminated(let player, _):
            guard let name = name(of: player, in: context) else { return nil }
            return LocalizedText(fr: "\(name) est éliminé", en: "\(name) is out")
        case .gameFinished:
            // A game with sides gives its own headline (Football: "Le camp A gagne", "Match nul"). It is said as it is.
            if let title = context.winnerTitle { return title }
            return winners(context.winners.compactMap { name(of: $0, in: context) })
        case .noEffect, .turnCompleted, .roundStarted, .highTurn, .doubleInOpened, .doubleInRequired, .checkout, .landed,
             .marksScored, .targetClosed, .targetDead, .pointsScored, .pointsGiven, .armingHit, .lifeLost, .targetHit,
             .targetScored, .neighbourHit, .damaged, .healed, .healWasted, .sectorClaimed, .sectorStrengthened,
             .sectorDamaged, .sectorConquered, .glassFilled, .ballMoved, .blobDamaged, .blobDestroyed, .blobsMoved,
             .shotPlayed:
            return nil
        }
    }

    // MARK: Helpers

    /// The name of player `index`, nil when the context has no such player (the caller then stays silent).
    private static func name(of index: PlayerIndex, in context: CueContext) -> String? {
        context.players.indices.contains(index) ? context.players[index].name : nil
    }

    /// "de Léa", "d'Alice": French elides "de" before a vowel. A name starting with H keeps "de". A Y before a
    /// consonant is the vowel of "Yves" ("d'Yves"); before a vowel it is the consonant of "Yann" ("de Yann").
    private static func frenchOf(_ name: String) -> String {
        let letters = name.prefix(2).map { String($0).folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil) }
        guard let first = letters.first else { return "de \(name)" }
        let vowels: Set<String> = ["a", "e", "i", "o", "u", "y", "œ", "æ"]
        let isVowel = first == "y"
            ? letters.count > 1 && letters[1].first?.isLetter == true && !vowels.contains(letters[1])
            : vowels.contains(first)
        return isVowel ? "d'\(name)" : "de \(name)"
    }

    /// "Léa", "Léa et Tom", "Léa, Tom et Zoé".
    private static func list(_ names: [String], and word: String) -> String {
        guard let last = names.last, names.count > 1 else { return names.first ?? "" }
        return "\(names.dropLast().joined(separator: ", ")) \(word) \(last)"
    }

    /// "Nouveau numéro : 16" for the single number of Killer expert; the plural for a wider zone. 25 is the bull.
    private static func newZone(_ zone: [Int]) -> LocalizedText? {
        guard !zone.isEmpty else { return nil }
        let numbers = zone.map { $0 == 25 ? "Bull" : "\($0)" }.joined(separator: ", ")
        return zone.count == 1
            ? LocalizedText(fr: "Nouveau numéro : \(numbers)", en: "New number: \(numbers)")
            : LocalizedText(fr: "Nouveaux numéros : \(numbers)", en: "New numbers: \(numbers)")
    }
}
