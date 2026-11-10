import Foundation
import Testing
import DartCore
import DartAudio

/// The sentences of the score caller, in both languages (table of ARCHITECTURE.md §7.5).
@Suite struct CallerPhrasesTests {
    private let players = [Player(name: "Léa"), Player(name: "Tom"), Player(name: "Zoé")]

    private var context: CueContext { CueContext(gameID: .x01, players: players) }

    private func phrase(_ event: GameEvent, in context: CueContext? = nil) -> LocalizedText? {
        CallerPhrases.phrase(for: event, context: context ?? self.context)
    }

    // MARK: - The printed table

    @Test func hit_theSixLinesOfTheTable() {
        #expect(CallerPhrases.hit(.treble(20)) == LocalizedText(fr: "Triple 20", en: "Treble 20"))
        #expect(CallerPhrases.hit(.double(16)) == LocalizedText(fr: "Double 16", en: "Double 16"))
        #expect(CallerPhrases.hit(.single(5)) == LocalizedText(fr: "5", en: "5"))
        #expect(CallerPhrases.hit(.outerBull) == LocalizedText(fr: "Bull", en: "Bull"))
        #expect(CallerPhrases.hit(.innerBull) == LocalizedText(fr: "Double bull", en: "Bullseye"))
        #expect(CallerPhrases.hit(.miss) == LocalizedText(fr: "Manqué", en: "Miss"))
    }

    @Test func hit_everyValueHasItsNumberInDigits() {
        var seen: Set<LocalizedText> = []
        for hit in Hit.all {
            let text = CallerPhrases.hit(hit)
            #expect(!text.fr.isEmpty && !text.en.isEmpty)
            if let number = hit.number {
                // The voice reads the digits: no number is ever spelled out.
                #expect(text.fr.hasSuffix("\(number)") && text.en.hasSuffix("\(number)"), "\(hit)")
                #expect(text.fr.split(separator: " ").last == Substring("\(number)"))
            }
            seen.insert(text)
        }
        // 63 values, 63 different sentences.
        #expect(seen.count == 63)
        #expect(CallerPhrases.hit(.single(20)) == LocalizedText(verbatim: "20"))
        #expect(CallerPhrases.hit(.treble(1)) == LocalizedText(fr: "Triple 1", en: "Treble 1"))
    }

    @Test func turnTotal_isTheNumberInDigits_inBothLanguages() {
        #expect(CallerPhrases.turnTotal(140) == LocalizedText(fr: "140", en: "140"))
        #expect(CallerPhrases.turnTotal(0) == LocalizedText(verbatim: "0"))
        #expect(CallerPhrases.turnTotal(7) == LocalizedText(verbatim: "7"))
    }

    @Test func turnTotal_of180_isJust180_theExclamationBelongsToOneEighty() {
        #expect(CallerPhrases.turnTotal(180) == LocalizedText(fr: "180", en: "180"))
        #expect(phrase(.turnScored(player: 0, points: 180)) == LocalizedText(verbatim: "180"))
        #expect(phrase(.oneEighty(player: 0)) == LocalizedText(fr: "Cent quatre-vingts !", en: "One hundred and eighty!"))
    }

    @Test func nextPlayer() {
        #expect(CallerPhrases.nextPlayer("Léa") == LocalizedText(fr: "Au tour de Léa", en: "Léa to throw"))
        #expect(CallerPhrases.nextPlayer("Tom") == LocalizedText(fr: "Au tour de Tom", en: "Tom to throw"))
        #expect(CallerPhrases.nextPlayer("J1") == LocalizedText(fr: "Au tour de J1", en: "J1 to throw"))
    }

    @Test func nextPlayer_elidesBeforeAVowel_asFrenchDoes() {
        #expect(CallerPhrases.nextPlayer("Alice") == LocalizedText(fr: "Au tour d'Alice", en: "Alice to throw"))
        #expect(CallerPhrases.nextPlayer("Élodie").fr == "Au tour d'Élodie")
        #expect(CallerPhrases.nextPlayer("inès").fr == "Au tour d'inès")
        #expect(CallerPhrases.nextPlayer("Olivier").fr == "Au tour d'Olivier")
        #expect(CallerPhrases.nextPlayer("Ugo").fr == "Au tour d'Ugo")
        #expect(CallerPhrases.nextPlayer("Œdipe").fr == "Au tour d'Œdipe")
        // H and Y keep "de": the elision depends on the name, and "de Hugo" is never wrong.
        #expect(CallerPhrases.nextPlayer("Hugo").fr == "Au tour de Hugo")
        #expect(CallerPhrases.nextPlayer("Yann").fr == "Au tour de Yann")
        #expect(CallerPhrases.nextPlayer("").fr == "Au tour de ")
    }

    @Test func winners() {
        #expect(CallerPhrases.winners(["Léa"]) == LocalizedText(fr: "Léa gagne la partie", en: "Léa wins"))
        #expect(CallerPhrases.winners(["Léa", "Tom"]) == LocalizedText(fr: "Égalité entre Léa et Tom", en: "Léa and Tom tie"))
        #expect(CallerPhrases.winners(["Léa", "Tom", "Zoé"])
            == LocalizedText(fr: "Égalité entre Léa, Tom et Zoé", en: "Léa, Tom and Zoé tie"))
        // Nobody to name: the end of the game is still said.
        #expect(CallerPhrases.winners([]) == LocalizedText(fr: "Partie terminée", en: "Game over"))
    }

    @Test func phrase_theLinesOfTheTable() {
        #expect(phrase(.oneEighty(player: 0)) == LocalizedText(fr: "Cent quatre-vingts !", en: "One hundred and eighty!"))
        #expect(phrase(.bonusGlass(player: 0, glasses: 3)) == LocalizedText(fr: "Tournée offerte !", en: "This one's on the house!"))
        #expect(phrase(.goalScored(player: 0, side: 0, goals: 1, ownGoal: false)) == LocalizedText(fr: "But !", en: "Goal!"))
        #expect(phrase(.goalScored(player: 0, side: 1, goals: 1, ownGoal: true)) == LocalizedText(fr: "Contre son camp !", en: "Own goal!"))
        #expect(phrase(.holeCompleted(player: 0, hole: 2, strokes: 3, total: 7)) == LocalizedText(fr: "3 coups", en: "3 strokes"))
        #expect(phrase(.holeCompleted(player: 0, hole: 2, strokes: 1, total: 5)) == LocalizedText(fr: "1 coup", en: "1 stroke"))
        #expect(phrase(.holeCompleted(player: 0, hole: 2, strokes: 5, total: 9)) == LocalizedText(fr: "5 coups", en: "5 strokes"))
        #expect(phrase(.holeInOne(player: 0, hole: 2)) == LocalizedText(fr: "Trou en un !", en: "Hole in one!"))
    }

    @Test func phrase_theSentencesOfTheSoundTable() {
        #expect(phrase(.dartRegistered(player: 0, hit: .treble(20))) == LocalizedText(fr: "Triple 20", en: "Treble 20"))
        #expect(phrase(.turnStarted(player: 0, round: 1)) == LocalizedText(fr: "Au tour de Léa", en: "Léa to throw"))
        #expect(phrase(.turnScored(player: 0, points: 140)) == LocalizedText(verbatim: "140"))
        #expect(phrase(.bust(player: 0, reason: .notADouble)) == LocalizedText(verbatim: "Bust"))
        #expect(phrase(.becameKiller(player: 0)) == LocalizedText(fr: "Léa est Killer", en: "Léa is a Killer"))
        #expect(phrase(.kingOfTheHill(player: 0)) == LocalizedText(fr: "Léa est Roi", en: "Léa is King"))
        #expect(phrase(.zoneChanged(player: 0, zone: [16])) == LocalizedText(fr: "Nouveau numéro : 16", en: "New number: 16"))
        #expect(phrase(.shanghai(player: 0)) == LocalizedText(fr: "Shanghai !", en: "Shanghai!"))
        #expect(phrase(.halved(player: 0, points: 30)) == LocalizedText(fr: "Score divisé par deux", en: "Score halved"))
        #expect(phrase(.playerEliminated(player: 1, by: 0)) == LocalizedText(fr: "Tom est éliminé", en: "Tom is out"))
    }

    @Test func phrase_zoneOfSeveralNumbers_andTheBull() {
        #expect(phrase(.zoneChanged(player: 0, zone: [17, 3, 19]))
            == LocalizedText(fr: "Nouveaux numéros : 17, 3, 19", en: "New numbers: 17, 3, 19"))
        #expect(phrase(.zoneChanged(player: 0, zone: [25])) == LocalizedText(fr: "Nouveau numéro : Bull", en: "New number: Bull"))
        #expect(phrase(.zoneChanged(player: 0, zone: [])) == nil)
    }

    @Test func phrase_gameFinished_namesTheWinners() {
        let one = CueContext(gameID: .x01, players: players, winners: [1])
        #expect(phrase(.gameFinished(reason: .victory), in: one) == LocalizedText(fr: "Tom gagne la partie", en: "Tom wins"))
        let two = CueContext(gameID: .highScore, players: players, winners: [0, 2])
        #expect(phrase(.gameFinished(reason: .roundLimit), in: two)
            == LocalizedText(fr: "Égalité entre Léa et Zoé", en: "Léa and Zoé tie"))
        // Before the end the context has no winner yet: the sentence stays a sentence.
        #expect(phrase(.gameFinished(reason: .roundLimit)) == LocalizedText(fr: "Partie terminée", en: "Game over"))
    }

    @Test func phrase_gameFinished_saysTheWinnerTitleAsItIs_whateverTheGame() {
        for (fr, en) in [("Le camp A gagne", "Side A wins"), ("Le camp B gagne", "Side B wins"), ("Match nul", "It's a draw")] {
            let title = LocalizedText(fr: fr, en: en)
            for game in [GameID.football, .x01, .cricket] {
                let finished = CueContext(gameID: game, players: players, winners: [0, 2], winnerTitle: title)
                #expect(phrase(.gameFinished(reason: .victory), in: finished) == title)
            }
        }
    }

    @Test func phrase_isNil_forEveryEventWithoutASentence() {
        let silent: [GameEvent] = [
            .noEffect(player: 0), .turnCompleted(player: 0), .roundStarted(round: 2), .highTurn(player: 0, points: 120),
            .doubleInOpened(player: 0), .doubleInRequired(player: 0), .checkout(player: 0, points: 40, darts: 1), .landed(player: 0),
            .marksScored(player: 0, target: 20, count: 2), .targetClosed(player: 0, target: 20), .targetDead(target: 20),
            .pointsScored(player: 0, points: 20), .pointsGiven(player: 0, to: [1], pointsEach: 20),
            .armingHit(player: 0, progress: 1), .lifeLost(player: 1, by: 0, livesLeft: 2),
            .targetHit(player: 0, number: 3, advancedBy: 1), .targetScored(player: 0, points: 14), .neighbourHit(player: 0, points: 5),
            .damaged(player: 1, by: 0, amount: 2, livesLeft: 5), .healed(player: 0, amount: 1, lives: 6), .healWasted(player: 0),
            .sectorClaimed(player: 0, sector: 6), .sectorStrengthened(player: 0, sector: 6, lives: 2),
            .sectorDamaged(player: 0, sector: 13, livesLeft: 1), .sectorConquered(player: 0, sector: 13, from: 1),
            .glassFilled(player: 0, count: 1, glasses: 2), .ballMoved(player: 0, by: 1, ball: 5),
            .blobDamaged(player: 0, blob: 0, points: 10, hitPointsLeft: 1), .blobDestroyed(player: 0, blob: 0, points: 60), .blobsMoved,
            .shotPlayed(player: 0, strokes: 2),
        ]
        #expect(silent.count == 31)
        for event in silent {
            #expect(phrase(event) == nil, "\(event)")
        }
    }

    @Test func phrase_soloGame_doesNotCallThePlayer() {
        let solo = CueContext(gameID: .golf, players: [Player(name: "Léa")])
        #expect(phrase(.turnStarted(player: 0, round: 3), in: solo) == nil)
        // The other sentences that carry a name are still said.
        #expect(phrase(.gameFinished(reason: .roundLimit), in: CueContext(gameID: .golf, players: solo.players, winners: [0]))
            == LocalizedText(fr: "Léa gagne la partie", en: "Léa wins"))
    }

    @Test func phrase_unknownPlayer_isNil_withoutTrapping() {
        for player in [-1, 3, 99, Int.max, Int.min] {
            #expect(phrase(.turnStarted(player: player, round: 1)) == nil)
            #expect(phrase(.becameKiller(player: player)) == nil)
            #expect(phrase(.kingOfTheHill(player: player)) == nil)
            #expect(phrase(.playerEliminated(player: player, by: 0)) == nil)
        }
        #expect(phrase(.turnStarted(player: 0, round: 1), in: CueContext(gameID: .x01, players: [])) == nil)
    }

    @Test func phrases_neverContainADigitSpelledOut_exceptTheTwoExclamations() {
        // "Cent quatre-vingts !" and "Trou en un !" are the only sentences that spell a number.
        #expect(CallerPhrases.turnTotal(180).fr == "180")
        #expect(CallerPhrases.hit(.treble(20)).fr == "Triple 20")
        #expect(phrase(.holeCompleted(player: 0, hole: 1, strokes: 2, total: 2))?.fr == "2 coups")
    }
}
