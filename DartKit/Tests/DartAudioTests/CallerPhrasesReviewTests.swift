import Foundation
import Testing
import DartCore
import DartAudio

/// Adversarial review of the caller's sentences (ARCHITECTURE.md §7.3, §7.5): every value a dart can take, every
/// X01 total, the Killer, Fight and Conqueror announcements, and the French elision of player names. The expected
/// texts are written here from the documents, not read back from the code.
@Suite struct CallerPhrasesReviewTests {
    private let players = [Player(name: "Léa"), Player(name: "Tom"), Player(name: "Alice"), Player(name: "Yves")]

    private var context: CueContext { CueContext(gameID: .killer, players: players) }

    // MARK: - Darts

    /// The sentence of one dart, written from the table of §7.5.
    private func expectedCall(_ hit: Hit) -> (fr: String, en: String) {
        switch hit.bed {
        case .miss: return ("Manqué", "Miss")
        case .outerBull: return ("Bull", "Bull")
        case .innerBull: return ("Double bull", "Bullseye")
        case .single: return ("\(hit.number ?? -1)", "\(hit.number ?? -1)")
        case .double: return ("Double \(hit.number ?? -1)", "Double \(hit.number ?? -1)")
        case .treble: return ("Triple \(hit.number ?? -1)", "Treble \(hit.number ?? -1)")
        }
    }

    @Test func everyDart_isCalledAsTheTableSays_inBothLanguages() {
        var count = 0
        for number in 1...20 {
            for hit in [Hit.single(number), .double(number), .treble(number)] {
                let expected = expectedCall(hit)
                #expect(CallerPhrases.hit(hit) == LocalizedText(fr: expected.fr, en: expected.en), "\(hit)")
                count += 1
            }
        }
        for hit in [Hit.outerBull, .innerBull, .miss] {
            let expected = expectedCall(hit)
            #expect(CallerPhrases.hit(hit) == LocalizedText(fr: expected.fr, en: expected.en), "\(hit)")
            count += 1
        }
        // The 62 scoring values and MISS, which is `Hit.all` exactly.
        #expect(count == 63 && Hit.all.count == 63)
        for hit in Hit.all {
            // The phrase of the event is the phrase of the dart, whoever throws it.
            for player in [0, 3, 99] {
                #expect(CallerPhrases.phrase(for: .dartRegistered(player: player, hit: hit), context: context) == CallerPhrases.hit(hit))
            }
        }
    }

    // MARK: - Totals

    @Test func everyX01Total_from0To180_isSaidInDigits() {
        for points in 0...180 {
            let text = LocalizedText(verbatim: "\(points)")
            #expect(CallerPhrases.turnTotal(points) == text, "\(points)")
            #expect(CallerPhrases.phrase(for: .turnScored(player: 0, points: points), context: context) == text, "\(points)")
            // Only the total speaks: the companion events of a closing turn have no sentence of their own.
            #expect(CallerPhrases.phrase(for: .highTurn(player: 0, points: points), context: context) == nil)
        }
        #expect(CallerPhrases.phrase(for: .oneEighty(player: 0), context: context)
            == LocalizedText(fr: "Cent quatre-vingts !", en: "One hundred and eighty!"))
        for reason in [BustReason.belowZero, .notADouble, .oneLeft] {
            #expect(CallerPhrases.phrase(for: .bust(player: 1, reason: reason), context: context) == LocalizedText(fr: "Bust", en: "Bust"))
        }
        // A checkout is announced by the end of the game, never by itself.
        #expect(CallerPhrases.phrase(for: .checkout(player: 0, points: 170, darts: 3), context: context) == nil)
    }

    // MARK: - Names

    @Test func nextPlayer_elidesBeforeEveryVowelSound() {
        let elided = ["Alice", "Émile", "Éloïse", "Ève", "Inès", "Isaac", "Océane", "Olivier", "Ugo", "Ursule", "Œdipe",
                      "alice", "Ïana", "Yves", "Yvonne", "Yvette", "Yvan", "Ysée"]
        for name in elided {
            #expect(CallerPhrases.nextPlayer(name).fr == "Au tour d'\(name)", "\(name)")
            #expect(CallerPhrases.nextPlayer(name).en == "\(name) to throw", "\(name)")
        }
    }

    @Test func nextPlayer_keepsDe_beforeAConsonantSound() {
        // A Y before a vowel is the consonant of "Yann"; an H is left alone ("de Hugo" is never wrong).
        let kept = ["Léa", "Tom", "Zoé", "Bastien", "Yann", "Yanis", "Yohan", "Yasmine", "Youssef", "Hugo", "Hélène", "J1", "Y", "1er"]
        for name in kept {
            #expect(CallerPhrases.nextPlayer(name).fr == "Au tour de \(name)", "\(name)")
        }
    }

    @Test func turnStarted_namesThePlayerWhoseTurnBegins() {
        for (index, player) in players.enumerated() {
            let text = CallerPhrases.phrase(for: .turnStarted(player: index, round: 7), context: context)
            #expect(text == CallerPhrases.nextPlayer(player.name))
        }
        #expect(CallerPhrases.phrase(for: .turnStarted(player: 2, round: 1), context: context)
            == LocalizedText(fr: "Au tour d'Alice", en: "Alice to throw"))
        #expect(CallerPhrases.phrase(for: .turnStarted(player: 3, round: 1), context: context)
            == LocalizedText(fr: "Au tour d'Yves", en: "Yves to throw"))
    }

    // MARK: - Killer, Fight, Conqueror

    @Test func killer_announcements_nameThePlayerTheEventIsAbout() {
        #expect(CallerPhrases.phrase(for: .becameKiller(player: 2), context: context)
            == LocalizedText(fr: "Alice est Killer", en: "Alice is a Killer"))
        // `playerEliminated(player, by)`: the eliminated player is named, never the one who threw.
        #expect(CallerPhrases.phrase(for: .playerEliminated(player: 1, by: 2), context: context)
            == LocalizedText(fr: "Tom est éliminé", en: "Tom is out"))
        // A Killer who hits his own zone eliminates himself.
        #expect(CallerPhrases.phrase(for: .playerEliminated(player: 3, by: 3), context: context)
            == LocalizedText(fr: "Yves est éliminé", en: "Yves is out"))
        #expect(CallerPhrases.phrase(for: .zoneChanged(player: 1, zone: [9]), context: context)
            == LocalizedText(fr: "Nouveau numéro : 9", en: "New number: 9"))
        #expect(CallerPhrases.phrase(for: .zoneChanged(player: 1, zone: [1, 18]), context: context)
            == LocalizedText(fr: "Nouveaux numéros : 1, 18", en: "New numbers: 1, 18"))
        // A life lost or an arming hit is heard, not said.
        #expect(CallerPhrases.phrase(for: .lifeLost(player: 1, by: 0, livesLeft: 1), context: context) == nil)
        #expect(CallerPhrases.phrase(for: .armingHit(player: 1, progress: 2), context: context) == nil)
    }

    @Test func fight_and_conqueror_announcements() {
        // Fight: `damaged` and `healed` are heard; the K.-O. names the victim.
        #expect(CallerPhrases.phrase(for: .damaged(player: 1, by: 0, amount: 3, livesLeft: 0), context: context) == nil)
        #expect(CallerPhrases.phrase(for: .healed(player: 0, amount: 1, lives: 9), context: context) == nil)
        #expect(CallerPhrases.phrase(for: .playerEliminated(player: 0, by: 1), context: context)
            == LocalizedText(fr: "Léa est éliminé", en: "Léa is out"))
        // Conqueror: the King, and the player whose house is taken.
        #expect(CallerPhrases.phrase(for: .kingOfTheHill(player: 3), context: context)
            == LocalizedText(fr: "Yves est Roi", en: "Yves is King"))
        #expect(CallerPhrases.phrase(for: .sectorConquered(player: 0, sector: 5, from: 1), context: context) == nil)
        #expect(CallerPhrases.phrase(for: .playerEliminated(player: 2, by: 0), context: context)
            == LocalizedText(fr: "Alice est éliminé", en: "Alice is out"))
    }

    // MARK: - End of the game

    @Test func winners_ofOneToFivePlayers() {
        let names = ["Léa", "Tom", "Alice", "Yves", "Zoé"]
        #expect(CallerPhrases.winners(Array(names.prefix(1))) == LocalizedText(fr: "Léa gagne la partie", en: "Léa wins"))
        #expect(CallerPhrases.winners(Array(names.prefix(2))) == LocalizedText(fr: "Égalité entre Léa et Tom", en: "Léa and Tom tie"))
        #expect(CallerPhrases.winners(Array(names.prefix(3)))
            == LocalizedText(fr: "Égalité entre Léa, Tom et Alice", en: "Léa, Tom and Alice tie"))
        #expect(CallerPhrases.winners(names)
            == LocalizedText(fr: "Égalité entre Léa, Tom, Alice, Yves et Zoé", en: "Léa, Tom, Alice, Yves and Zoé tie"))
    }

    @Test func gameFinished_namesTheWinnersInTheirOrder_orSaysTheTitle() {
        let finished = CueContext(gameID: .conqueror, players: players, winners: [3, 0])
        #expect(CallerPhrases.phrase(for: .gameFinished(reason: .lastPlayerStanding), context: finished)
            == LocalizedText(fr: "Égalité entre Yves et Léa", en: "Yves and Léa tie"))
        let title = LocalizedText(fr: "Le camp B gagne", en: "Side B wins")
        for game in [GameID.football, .killer, GameID("unknown")] {
            let titled = CueContext(gameID: game, players: players, winners: [1, 3], winnerTitle: title)
            #expect(CallerPhrases.phrase(for: .gameFinished(reason: .victory), context: titled) == title)
        }
    }

    @Test func sentences_neverStartOrEndWithSpace_andAreNeverEmpty() {
        // Every sentence of the table with names that are real, in both languages.
        let finished = CueContext(gameID: .x01, players: players, winners: [0])
        let events: [GameEvent] = [
            .turnStarted(player: 2, round: 1), .turnScored(player: 0, points: 60), .oneEighty(player: 0),
            .bust(player: 0, reason: .oneLeft), .becameKiller(player: 0), .kingOfTheHill(player: 1),
            .zoneChanged(player: 0, zone: [3]), .shanghai(player: 0), .halved(player: 0, points: 8),
            .bonusGlass(player: 0, glasses: 2), .goalScored(player: 0, side: 1, goals: 1, ownGoal: true),
            .goalScored(player: 0, side: 0, goals: 1, ownGoal: false), .holeCompleted(player: 0, hole: 1, strokes: 2, total: 2),
            .holeInOne(player: 0, hole: 1), .playerEliminated(player: 1, by: 0), .gameFinished(reason: .victory),
        ]
        for event in events {
            let text = CallerPhrases.phrase(for: event, context: finished)
            #expect(text != nil, "\(event)")
            for language in [AppLanguage.fr, .en] {
                let said = text?[language] ?? ""
                #expect(!said.isEmpty && said == said.trimmingCharacters(in: .whitespacesAndNewlines), "\(event) \(language)")
            }
        }
    }
}
