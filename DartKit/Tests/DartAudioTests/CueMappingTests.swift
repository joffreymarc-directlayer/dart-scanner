import Foundation
import Testing
import DartCore
import DartAudio

/// The table of ARCHITECTURE.md §7.3, line by line, then its sequencing rules.
/// Only the public API is used: this is what DartUI sees.
@Suite struct CueMappingTests {
    private let players = [Player(name: "Léa"), Player(name: "Tom"), Player(name: "Zoé")]

    private var context: CueContext { CueContext(gameID: .x01, players: players) }

    private func cues(_ events: GameEvent..., in context: CueContext? = nil) -> [AudioCue] {
        CueMapping.cues(for: events, context: context ?? self.context)
    }

    private func sentence(_ fr: String, _ en: String, _ priority: Announcement.Priority) -> Announcement {
        Announcement(LocalizedText(fr: fr, en: en), priority: priority)
    }

    private func sentence(_ text: String, _ priority: Announcement.Priority) -> Announcement {
        Announcement(LocalizedText(verbatim: text), priority: priority)
    }

    // MARK: - One line of the table at a time

    @Test func dartRegistered_impactLowSentenceLightHaptic() {
        #expect(cues(.dartRegistered(player: 0, hit: .treble(20))) == [
            AudioCue(effect: .dartImpact, announcement: sentence("Triple 20", "Treble 20", .low), haptic: .light, delay: 0),
        ])
        #expect(cues(.dartRegistered(player: 1, hit: .innerBull)) == [
            AudioCue(effect: .dartImpact, announcement: sentence("Double bull", "Bullseye", .low), haptic: .light),
        ])
    }

    @Test func dartRegistered_soundsDull_onAMiss() {
        #expect(cues(.dartRegistered(player: 0, hit: .miss)) == [
            AudioCue(effect: .dartDull, announcement: sentence("Manqué", "Miss", .low), haptic: .light),
        ])
    }

    @Test func dartRegistered_soundsDull_whenTheBatchSaysTheDartDidNothing() {
        let dart = GameEvent.dartRegistered(player: 0, hit: .single(7))
        let dull = [AudioCue(effect: .dartDull, announcement: sentence("7", .low), haptic: .light)]
        #expect(cues(dart, .noEffect(player: 0)) == dull)
        #expect(cues(dart, .doubleInRequired(player: 0)) == dull)
        #expect(cues(dart, .healWasted(player: 0)) == dull)
        #expect(cues(dart, .shotPlayed(player: 0, strokes: 5)) == dull)
        // The marker may come anywhere in the batch.
        #expect(cues(dart, .turnCompleted(player: 0), .noEffect(player: 0)).first?.effect == .dartDull)
    }

    @Test func dartRegistered_keepsItsImpact_forAGolfShotThatCounts() {
        let dart = GameEvent.dartRegistered(player: 0, hit: .single(7))
        for strokes in [1, 2, 3, 4, 6] {
            #expect(cues(dart, .shotPlayed(player: 0, strokes: strokes)) == [
                AudioCue(effect: .dartImpact, announcement: sentence("7", .low), haptic: .light),
            ])
        }
    }

    @Test func eventsWithoutSoundSentenceOrHaptic() {
        let silent: [GameEvent] = [
            .noEffect(player: 0), .doubleInRequired(player: 0), .healWasted(player: 0), .shotPlayed(player: 0, strokes: 3),
            .shotPlayed(player: 0, strokes: 5), .turnCompleted(player: 0), .roundStarted(round: 2), .targetDead(target: 20),
            .checkout(player: 0, points: 100, darts: 2), .landed(player: 0),
        ]
        for event in silent {
            #expect(cues(event).isEmpty, "\(event)")
        }
        #expect(CueMapping.cues(for: silent, context: context).isEmpty)
    }

    @Test func turnStarted_turnChangeAndTheNameOfThePlayer() {
        #expect(cues(.turnStarted(player: 1, round: 3)) == [
            AudioCue(effect: .turnChange, announcement: sentence("Au tour de Tom", "Tom to throw", .normal)),
        ])
    }

    @Test func turnStarted_saysNothingInASoloGame() {
        let solo = CueContext(gameID: .aroundTheClock, players: [Player(name: "Léa")])
        #expect(cues(.turnStarted(player: 0, round: 2), in: solo) == [AudioCue(effect: .turnChange)])
    }

    @Test func turnScored_theTotalInDigits_withoutAnyEffect() {
        #expect(cues(.turnScored(player: 0, points: 140)) == [AudioCue(announcement: sentence("140", .normal))])
        #expect(cues(.turnScored(player: 0, points: 0)) == [AudioCue(announcement: sentence("0", .normal))])
    }

    @Test func turnScored_isSilent_whenTheBatchHasAOneEighty() {
        let batch = cues(.turnScored(player: 0, points: 180), .oneEighty(player: 0))
        #expect(batch == [
            AudioCue(effect: .fanfare, announcement: sentence("Cent quatre-vingts !", "One hundred and eighty!", .high), haptic: .success),
        ])
    }

    @Test func turnScored_of180_withoutOneEighty_isSaidInDigits() {
        // Radar: `turnScored`, never `oneEighty`.
        #expect(cues(.turnScored(player: 0, points: 180)) == [AudioCue(announcement: sentence("180", .normal))])
    }

    @Test func highTurn_effectAndMediumHaptic() {
        #expect(cues(.highTurn(player: 0, points: 140)) == [AudioCue(effect: .highTurn, haptic: .medium)])
    }

    @Test func oneEighty_fanfareHighSentenceSuccess() {
        #expect(cues(.oneEighty(player: 0)) == [
            AudioCue(effect: .fanfare, announcement: sentence("Cent quatre-vingts !", "One hundred and eighty!", .high), haptic: .success),
        ])
    }

    @Test func bust_buzzerHighSentenceFailure() {
        for reason in [BustReason.belowZero, .notADouble, .oneLeft] {
            #expect(cues(.bust(player: 0, reason: reason)) == [
                AudioCue(effect: .bust, announcement: sentence("Bust", .high), haptic: .failure),
            ])
        }
    }

    @Test func doubleInOpened_scoreUp() {
        #expect(cues(.doubleInOpened(player: 0)) == [AudioCue(effect: .scoreUp)])
    }

    @Test func marksScored_oneTickPerMark_ninetyMillisecondsApart() {
        #expect(cues(.marksScored(player: 0, target: 20, count: 1)) == [AudioCue(effect: .tick, delay: 0)])
        #expect(cues(.marksScored(player: 0, target: 20, count: 2)) == [
            AudioCue(effect: .tick, delay: 0), AudioCue(effect: .tick, delay: 0.09),
        ])
        #expect(cues(.marksScored(player: 0, target: 25, count: 3)) == [
            AudioCue(effect: .tick, delay: 0), AudioCue(effect: .tick, delay: 0.09), AudioCue(effect: .tick, delay: 0.18),
        ])
    }

    @Test func marksScored_withAnAbsurdCount_neitherTrapsNorFloods() {
        #expect(cues(.marksScored(player: 0, target: 20, count: 0)).isEmpty)
        #expect(cues(.marksScored(player: 0, target: 20, count: -3)).isEmpty)
        #expect(cues(.marksScored(player: 0, target: 20, count: Int.min)).isEmpty)
        let flood = cues(.marksScored(player: 0, target: 20, count: Int.max))
        #expect(flood.count == 9 && flood.allSatisfy { $0.effect == .tick })
    }

    @Test func targetClosed_lockAndMediumHaptic() {
        #expect(cues(.targetClosed(player: 0, target: 20)) == [AudioCue(effect: .lock, haptic: .medium)])
    }

    @Test func pointsOfEveryKind_scoreUp() {
        let events: [GameEvent] = [
            .pointsScored(player: 0, points: 40), .pointsGiven(player: 0, to: [1, 2], pointsEach: 20),
            .targetScored(player: 0, points: 14), .neighbourHit(player: 0, points: 5),
            .targetHit(player: 0, number: 25, advancedBy: 1),
        ]
        for event in events {
            #expect(cues(event) == [AudioCue(effect: .scoreUp)], "\(event)")
        }
    }

    @Test func armingHit_tick() {
        #expect(cues(.armingHit(player: 0, progress: 2)) == [AudioCue(effect: .tick)])
    }

    @Test func becameKiller_powerUpSentenceMedium() {
        #expect(cues(.becameKiller(player: 0)) == [
            AudioCue(effect: .powerUp, announcement: sentence("Léa est Killer", "Léa is a Killer", .normal), haptic: .medium),
        ])
    }

    @Test func livesAndSectorsLost_damageAndMediumHaptic() {
        let events: [GameEvent] = [
            .lifeLost(player: 1, by: 0, livesLeft: 2), .damaged(player: 1, by: 0, amount: 3, livesLeft: 6),
            .sectorDamaged(player: 0, sector: 12, livesLeft: 1),
        ]
        for event in events {
            #expect(cues(event) == [AudioCue(effect: .damage, haptic: .medium)], "\(event)")
        }
    }

    @Test func healsAndReinforcements_heal() {
        #expect(cues(.healed(player: 0, amount: 2, lives: 7)) == [AudioCue(effect: .heal)])
        #expect(cues(.sectorStrengthened(player: 0, sector: 6, lives: 3)) == [AudioCue(effect: .heal)])
    }

    @Test func sectorsTaken_claim() {
        #expect(cues(.sectorClaimed(player: 0, sector: 6)) == [AudioCue(effect: .claim)])
        #expect(cues(.sectorConquered(player: 0, sector: 6, from: 1)) == [AudioCue(effect: .claim)])
    }

    @Test func kingOfTheHill_powerUpSentenceMedium() {
        #expect(cues(.kingOfTheHill(player: 2)) == [
            AudioCue(effect: .powerUp, announcement: sentence("Zoé est Roi", "Zoé is King", .normal), haptic: .medium),
        ])
    }

    @Test func zoneChanged_zoneMoveAndTheNewNumber() {
        #expect(cues(.zoneChanged(player: 1, zone: [16])) == [
            AudioCue(effect: .zoneMove),
            AudioCue(announcement: sentence("Nouveau numéro : 16", "New number: 16", .normal)),
        ])
    }

    @Test func shanghai_fanfareHighSentenceSuccess() {
        #expect(cues(.shanghai(player: 0)) == [
            AudioCue(effect: .fanfare, announcement: sentence("Shanghai !", "Shanghai!", .high), haptic: .success),
        ])
    }

    @Test func halved_fallingToneSentenceWarning() {
        #expect(cues(.halved(player: 0, points: 21)) == [
            AudioCue(effect: .halved, announcement: sentence("Score divisé par deux", "Score halved", .normal), haptic: .warning),
        ])
    }

    // The ten events of lot G4.

    @Test func glassFilled_scoreUpAndMediumHaptic_onceWhateverTheCount() {
        #expect(cues(.glassFilled(player: 0, count: 1, glasses: 1)) == [AudioCue(effect: .scoreUp, haptic: .medium)])
        #expect(cues(.glassFilled(player: 0, count: 3, glasses: 5)) == [AudioCue(effect: .scoreUp, haptic: .medium)])
    }

    @Test func bonusGlass_powerUpSentenceSuccess() {
        #expect(cues(.bonusGlass(player: 0, glasses: 4)) == [
            AudioCue(effect: .powerUp, announcement: sentence("Tournée offerte !", "This one's on the house!", .normal), haptic: .success),
        ])
    }

    @Test func ballMoved_tick() {
        #expect(cues(.ballMoved(player: 0, by: -2, ball: 3)) == [AudioCue(effect: .tick)])
    }

    @Test func goalScored_fanfareHighSentenceSuccess() {
        #expect(cues(.goalScored(player: 0, side: 0, goals: 1, ownGoal: false)) == [
            AudioCue(effect: .fanfare, announcement: sentence("But !", "Goal!", .high), haptic: .success),
        ])
    }

    @Test func goalScored_ownGoal_fallingToneAndWarning() {
        #expect(cues(.goalScored(player: 0, side: 1, goals: 2, ownGoal: true)) == [
            AudioCue(effect: .halved, announcement: sentence("Contre son camp !", "Own goal!", .high), haptic: .warning),
        ])
    }

    @Test func blobDamaged_damageAndMediumHaptic() {
        #expect(cues(.blobDamaged(player: 0, blob: 2, points: 10, hitPointsLeft: 1)) == [AudioCue(effect: .damage, haptic: .medium)])
    }

    @Test func blobDestroyed_powerUpAndHeavyHaptic() {
        #expect(cues(.blobDestroyed(player: 0, blob: 2, points: 60)) == [AudioCue(effect: .powerUp, haptic: .heavy)])
    }

    @Test func blobsMoved_zoneMove() {
        #expect(cues(.blobsMoved) == [AudioCue(effect: .zoneMove)])
    }

    @Test func holeCompleted_theStrokes_withoutAnyEffect() {
        #expect(cues(.holeCompleted(player: 0, hole: 4, strokes: 3, total: 12)) == [
            AudioCue(announcement: sentence("3 coups", "3 strokes", .normal)),
        ])
        #expect(cues(.holeCompleted(player: 0, hole: 4, strokes: 1, total: 10)) == [
            AudioCue(announcement: sentence("1 coup", "1 stroke", .normal)),
        ])
    }

    @Test func holeCompleted_isSilent_whenTheBatchHasAHoleInOne() {
        #expect(cues(.holeCompleted(player: 0, hole: 4, strokes: 1, total: 10), .holeInOne(player: 0, hole: 4)) == [
            AudioCue(effect: .fanfare, announcement: sentence("Trou en un !", "Hole in one!", .high), haptic: .success),
        ])
    }

    @Test func holeInOne_fanfareHighSentenceSuccess() {
        #expect(cues(.holeInOne(player: 0, hole: 9)) == [
            AudioCue(effect: .fanfare, announcement: sentence("Trou en un !", "Hole in one!", .high), haptic: .success),
        ])
    }

    @Test func playerEliminated_effectHighSentenceHeavyHaptic() {
        #expect(cues(.playerEliminated(player: 1, by: 0)) == [
            AudioCue(effect: .eliminated, announcement: sentence("Tom est éliminé", "Tom is out", .high), haptic: .heavy),
        ])
    }

    @Test func gameFinished_victoryThenTheWinner_sixTenthsOfASecondLater() {
        let finished = CueContext(gameID: .x01, players: players, winners: [0])
        for reason in [FinishReason.victory, .lastPlayerStanding, .roundLimit] {
            #expect(cues(.gameFinished(reason: reason), in: finished) == [
                AudioCue(effect: .victory, haptic: .success, delay: 0),
                AudioCue(announcement: sentence("Léa gagne la partie", "Léa wins", .high), delay: 0.6),
            ])
        }
    }

    @Test func gameFinished_namesEveryWinnerOfATie() {
        let tie = CueContext(gameID: .highScore, players: players, winners: [0, 1])
        #expect(cues(.gameFinished(reason: .roundLimit), in: tie).last
            == AudioCue(announcement: sentence("Égalité entre Léa et Tom", "Léa and Tom tie", .high), delay: 0.6))
    }

    @Test func gameFinished_saysTheWinnerTitleAsItIs() {
        // Football: the winners are the players of one side, not a tie. The game says so with a headline.
        let sideA = CueContext(gameID: .football, players: players, winners: [0, 2],
                               winnerTitle: LocalizedText(fr: "Le camp A gagne", en: "Side A wins"))
        #expect(cues(.gameFinished(reason: .victory), in: sideA) == [
            AudioCue(effect: .victory, haptic: .success),
            AudioCue(announcement: sentence("Le camp A gagne", "Side A wins", .high), delay: 0.6),
        ])
        let draw = CueContext(gameID: .football, players: players, winners: [0, 1, 2],
                              winnerTitle: LocalizedText(fr: "Match nul", en: "It's a draw"))
        #expect(cues(.gameFinished(reason: .roundLimit), in: draw).last
            == AudioCue(announcement: sentence("Match nul", "It's a draw", .high), delay: 0.6))
    }

    @Test func gameFinished_doesNotDependOnTheGame() {
        let title = LocalizedText(fr: "Le camp B gagne", en: "Side B wins")
        let events: [GameEvent] = [.dartRegistered(player: 1, hit: .double(11)), .ballMoved(player: 1, by: 2, ball: 6),
                                   .goalScored(player: 1, side: 1, goals: 3, ownGoal: false), .gameFinished(reason: .victory)]
        let games: [GameID] = [.football, .x01, .killer, .golf, GameID("somethingNew")]
        // With a title: the same headline whatever the game is called.
        let titled = games.map { CueMapping.cues(for: events, context: CueContext(gameID: $0, players: players, winners: [1], winnerTitle: title)) }
        #expect(Set(titled).count == 1)
        #expect(titled[0].last?.announcement == Announcement(title, priority: .high))
        // Without one: the winners by name, Football included.
        let untitled = games.map { CueMapping.cues(for: events, context: CueContext(gameID: $0, players: players, winners: [1])) }
        #expect(Set(untitled).count == 1)
        #expect(untitled[0].last?.announcement == sentence("Tom gagne la partie", "Tom wins", .high))
    }

    // MARK: - Sequencing

    @Test func emptyBatch_playsNothing() {
        #expect(CueMapping.cues(for: [], context: context).isEmpty)
    }

    @Test func effects_followTheEvents_twelveHundredthsApart_theFirstAtZero() {
        let batch = cues(.dartRegistered(player: 0, hit: .single(20)), .pointsScored(player: 0, points: 20),
                         .targetClosed(player: 0, target: 20), .turnCompleted(player: 0))
        #expect(batch == [
            AudioCue(effect: .dartImpact, announcement: sentence("20", .low), delay: 0),
            AudioCue(effect: .scoreUp, delay: 0.12),
            AudioCue(effect: .lock, haptic: .medium, delay: 0.24),
        ])
    }

    @Test func x01_thirdDartOfA140() {
        let batch = cues(.dartRegistered(player: 0, hit: .treble(20)), .turnScored(player: 0, points: 140),
                         .highTurn(player: 0, points: 140), .turnCompleted(player: 0))
        #expect(batch == [
            AudioCue(effect: .dartImpact, announcement: sentence("Triple 20", "Treble 20", .low), delay: 0),
            AudioCue(announcement: sentence("140", .normal), delay: 0),
            AudioCue(effect: .highTurn, haptic: .medium, delay: 0.12),
        ])
    }

    @Test func x01_thirdDartOfA180() {
        let batch = cues(.dartRegistered(player: 0, hit: .treble(20)), .turnScored(player: 0, points: 180),
                         .oneEighty(player: 0), .turnCompleted(player: 0))
        #expect(batch == [
            AudioCue(effect: .dartImpact, announcement: sentence("Triple 20", "Treble 20", .low), delay: 0),
            AudioCue(effect: .fanfare, announcement: sentence("Cent quatre-vingts !", "One hundred and eighty!", .high),
                     haptic: .success, delay: 0.12),
        ])
    }

    @Test func x01_bust() {
        let batch = cues(.dartRegistered(player: 0, hit: .treble(20)), .bust(player: 0, reason: .belowZero), .turnCompleted(player: 0))
        #expect(batch == [
            AudioCue(effect: .dartImpact, announcement: sentence("Triple 20", "Treble 20", .low), delay: 0),
            AudioCue(effect: .bust, announcement: sentence("Bust", .high), haptic: .failure, delay: 0.12),
        ])
    }

    @Test func cricket_trebleThatClosesItsTarget() {
        let batch = cues(.dartRegistered(player: 0, hit: .treble(20)), .marksScored(player: 0, target: 20, count: 3),
                         .targetClosed(player: 0, target: 20), .turnCompleted(player: 0))
        #expect(batch == [
            AudioCue(effect: .dartImpact, announcement: sentence("Triple 20", "Treble 20", .low), delay: 0),
            AudioCue(effect: .tick, delay: 0.12),
            AudioCue(effect: .tick, delay: 0.21),
            AudioCue(effect: .tick, delay: 0.30),
            AudioCue(effect: .lock, haptic: .medium, delay: 0.42),
        ])
    }

    @Test func killer_lastLifeTaken_endsTheGame() {
        let finished = CueContext(gameID: .killer, players: Array(players.prefix(2)), winners: [0])
        let batch = cues(.dartRegistered(player: 0, hit: .single(5)), .lifeLost(player: 1, by: 0, livesLeft: 0),
                         .playerEliminated(player: 1, by: 0), .gameFinished(reason: .lastPlayerStanding), in: finished)
        #expect(batch == [
            AudioCue(effect: .dartImpact, announcement: sentence("5", .low), delay: 0),
            AudioCue(effect: .damage, delay: 0.12),
            AudioCue(effect: .eliminated, announcement: sentence("Tom est éliminé", "Tom is out", .high), delay: 0.24),
            AudioCue(effect: .victory, haptic: .success, delay: 0.36),
            AudioCue(announcement: sentence("Léa gagne la partie", "Léa wins", .high), delay: 0.96),
        ])
    }

    @Test func killerExpert_newNumberIsSaidAfterTheNameOfThePlayer() {
        // The engine emits `zoneChanged` BEFORE `turnStarted`; the caller says the name first.
        let batch = cues(.turnCompleted(player: 0), .roundStarted(round: 2), .zoneChanged(player: 1, zone: [16]),
                         .turnStarted(player: 1, round: 2))
        #expect(batch == [
            AudioCue(effect: .zoneMove, delay: 0),
            AudioCue(effect: .turnChange, announcement: sentence("Au tour de Tom", "Tom to throw", .normal), delay: 0.12),
            AudioCue(announcement: sentence("Nouveau numéro : 16", "New number: 16", .normal), delay: 0.12),
        ])
    }

    @Test func killerExpert_newNumberIsSaidRightAfterTheName_notAtTheEndOfTheBatch() {
        // Whatever follows `turnStarted` in a batch, the new number is said with the name, at its instant.
        let batch = cues(.zoneChanged(player: 1, zone: [16]), .turnStarted(player: 1, round: 2), .blobsMoved)
        #expect(batch == [
            AudioCue(effect: .zoneMove, delay: 0),
            AudioCue(effect: .turnChange, announcement: sentence("Au tour de Tom", "Tom to throw", .normal), delay: 0.12),
            AudioCue(announcement: sentence("Nouveau numéro : 16", "New number: 16", .normal), delay: 0.12),
            AudioCue(effect: .zoneMove, delay: 0.24),
        ])
        // Without a name to say first (a batch without `turnStarted`), it is said at the last effect.
        #expect(cues(.zoneChanged(player: 1, zone: [7]), .blobsMoved) == [
            AudioCue(effect: .zoneMove, delay: 0),
            AudioCue(effect: .zoneMove, delay: 0.12),
            AudioCue(announcement: sentence("Nouveau numéro : 7", "New number: 7", .normal), delay: 0.12),
        ])
    }

    @Test func radar_movingTargetsThenNextPlayer() {
        #expect(cues(.blobsMoved, .turnStarted(player: 2, round: 1)) == [
            AudioCue(effect: .zoneMove, delay: 0),
            AudioCue(effect: .turnChange, announcement: sentence("Au tour de Zoé", "Zoé to throw", .normal), delay: 0.12),
        ])
    }

    @Test func radar_aTurnOf180_isAnnouncedLikeAnyTotal() {
        let batch = cues(.dartRegistered(player: 0, hit: .single(6)), .blobDestroyed(player: 0, blob: 1, points: 70),
                         .turnScored(player: 0, points: 180), .turnCompleted(player: 0))
        #expect(batch == [
            AudioCue(effect: .dartImpact, announcement: sentence("6", .low), delay: 0),
            AudioCue(effect: .powerUp, haptic: .heavy, delay: 0.12),
            AudioCue(announcement: sentence("180", .normal), delay: 0.12),
        ])
    }

    @Test func golf_holeInOne() {
        let batch = cues(.dartRegistered(player: 0, hit: .double(4)), .shotPlayed(player: 0, strokes: 1),
                         .holeCompleted(player: 0, hole: 4, strokes: 1, total: 9), .holeInOne(player: 0, hole: 4),
                         .turnCompleted(player: 0))
        #expect(batch == [
            AudioCue(effect: .dartImpact, announcement: sentence("Double 4", .low), delay: 0),
            AudioCue(effect: .fanfare, announcement: sentence("Trou en un !", "Hole in one!", .high), haptic: .success, delay: 0.12),
        ])
    }

    @Test func golf_fiveStrokesSoundsDull_andTheHoleIsAnnounced() {
        let batch = cues(.dartRegistered(player: 0, hit: .single(17)), .shotPlayed(player: 0, strokes: 5),
                         .holeCompleted(player: 0, hole: 4, strokes: 5, total: 14), .turnCompleted(player: 0))
        #expect(batch == [
            AudioCue(effect: .dartDull, announcement: sentence("17", .low), haptic: .light, delay: 0),
            AudioCue(announcement: sentence("5 coups", "5 strokes", .normal), delay: 0),
        ])
    }

    @Test func football_aMoveThatScores() {
        let batch = cues(.dartRegistered(player: 0, hit: .single(6)), .ballMoved(player: 0, by: 1, ball: 7),
                         .goalScored(player: 0, side: 0, goals: 1, ownGoal: false))
        #expect(batch == [
            AudioCue(effect: .dartImpact, announcement: sentence("6", .low), delay: 0),
            AudioCue(effect: .tick, delay: 0.12),
            AudioCue(effect: .fanfare, announcement: sentence("But !", "Goal!", .high), haptic: .success, delay: 0.24),
        ])
    }

    @Test func beerTap_turnOfAHundredWithAFreeGlass() {
        let batch = cues(.dartRegistered(player: 0, hit: .treble(20)), .glassFilled(player: 0, count: 2, glasses: 5),
                         .turnScored(player: 0, points: 120), .highTurn(player: 0, points: 120),
                         .bonusGlass(player: 0, glasses: 6), .turnCompleted(player: 0))
        #expect(batch == [
            AudioCue(effect: .dartImpact, announcement: sentence("Triple 20", "Treble 20", .low), delay: 0),
            AudioCue(effect: .scoreUp, delay: 0.12),
            AudioCue(announcement: sentence("120", .normal), delay: 0.12),
            AudioCue(effect: .highTurn, delay: 0.24),
            AudioCue(effect: .powerUp, announcement: sentence("Tournée offerte !", "This one's on the house!", .normal),
                     haptic: .success, delay: 0.36),
        ])
    }

    @Test func halveIt_aMissedRoundHalvesTheScore() {
        let batch = cues(.dartRegistered(player: 0, hit: .miss), .noEffect(player: 0), .halved(player: 0, points: 20),
                         .turnCompleted(player: 0))
        #expect(batch == [
            AudioCue(effect: .dartDull, announcement: sentence("Manqué", "Miss", .low), delay: 0),
            AudioCue(effect: .halved, announcement: sentence("Score divisé par deux", "Score halved", .normal),
                     haptic: .warning, delay: 0.12),
        ])
    }

    @Test func oneHapticPerBatch_theStrongest() {
        // failure > success > warning > heavy > medium > light: each event beats the ones before it.
        let ladder: [(GameEvent, HapticPattern)] = [
            (.dartRegistered(player: 0, hit: .single(1)), .light),
            (.targetClosed(player: 0, target: 20), .medium),
            (.blobDestroyed(player: 0, blob: 0, points: 60), .heavy),
            (.halved(player: 0, points: 10), .warning),
            (.shanghai(player: 0), .success),
            (.bust(player: 0, reason: .oneLeft), .failure),
        ]
        for count in 1...ladder.count {
            let events = ladder.prefix(count).map(\.0)
            for batch in [events, Array(events.reversed())] {
                let haptics = CueMapping.cues(for: batch, context: context).compactMap(\.haptic)
                #expect(haptics == [ladder[count - 1].1], "\(batch)")
            }
        }
    }

    @Test func oneHapticPerBatch_staysOnTheCueOfItsEvent() {
        let batch = cues(.dartRegistered(player: 0, hit: .single(1)), .lifeLost(player: 1, by: 0, livesLeft: 1),
                         .lifeLost(player: 2, by: 0, livesLeft: 1))
        // Two events of the same strength: the first keeps the haptic.
        #expect(batch.map(\.haptic) == [nil, .medium, nil])
        #expect(batch.map(\.delay) == [0, 0.12, 0.24])
    }

    @Test func unknownPlayer_staysSilent_withoutTrapping() {
        let nobody = CueContext(gameID: .killer, players: [])
        #expect(cues(.turnStarted(player: 4, round: 1), in: nobody) == [AudioCue(effect: .turnChange)])
        #expect(cues(.turnStarted(player: -1, round: 1)) == [AudioCue(effect: .turnChange)])
        #expect(cues(.becameKiller(player: 9)) == [AudioCue(effect: .powerUp, haptic: .medium)])
        #expect(cues(.kingOfTheHill(player: Int.max)) == [AudioCue(effect: .powerUp, haptic: .medium)])
        #expect(cues(.playerEliminated(player: 9, by: 0)) == [AudioCue(effect: .eliminated, haptic: .heavy)])
        // Winners that the context does not know are left out of the sentence.
        let strange = CueContext(gameID: .x01, players: players, winners: [7, 1, -2])
        #expect(cues(.gameFinished(reason: .victory), in: strange).last?.announcement
            == sentence("Tom gagne la partie", "Tom wins", .high))
        #expect(cues(.zoneChanged(player: 0, zone: [])) == [AudioCue(effect: .zoneMove)])
    }

    // MARK: - The catalogue of GAMES.md §2.10

    /// The catalogue, as printed: one line per game, the names of its own events.
    private static let catalogue: [(game: String, events: [String])] = [
        ("all", ["dartRegistered", "noEffect", "turnCompleted", "roundStarted", "turnStarted", "playerEliminated", "gameFinished"]),
        ("raw points", ["turnScored", "oneEighty", "highTurn"]),
        ("x01", ["doubleInOpened", "doubleInRequired", "bust", "checkout"]),
        ("cricket", ["marksScored", "targetClosed", "targetDead", "pointsScored", "pointsGiven"]),
        ("killer", ["armingHit", "becameKiller", "lifeLost", "zoneChanged"]),
        ("aroundTheClock", ["targetHit"]),
        ("shanghai", ["targetScored", "neighbourHit", "shanghai"]),
        ("halveIt", ["targetScored", "halved"]),
        ("moonLanding", ["bust", "landed"]),
        ("fight", ["damaged", "healed", "healWasted"]),
        ("conqueror", ["sectorClaimed", "sectorStrengthened", "sectorDamaged", "sectorConquered", "kingOfTheHill"]),
        ("beerTap", ["glassFilled", "bonusGlass"]),
        ("football", ["ballMoved", "goalScored"]),
        ("radar", ["blobDamaged", "blobDestroyed", "blobsMoved"]),
        ("golf", ["shotPlayed", "holeCompleted", "holeInOne"]),
    ]

    /// One event of every case of `GameEvent`.
    private static let oneOfEach: [GameEvent] = [
        .dartRegistered(player: 0, hit: .treble(20)), .noEffect(player: 0), .turnCompleted(player: 0), .roundStarted(round: 2),
        .turnStarted(player: 1, round: 2), .playerEliminated(player: 1, by: 0), .gameFinished(reason: .victory),
        .turnScored(player: 0, points: 60), .oneEighty(player: 0), .highTurn(player: 0, points: 120),
        .bust(player: 0, reason: .belowZero), .doubleInOpened(player: 0), .doubleInRequired(player: 0),
        .checkout(player: 0, points: 40, darts: 1), .landed(player: 0),
        .marksScored(player: 0, target: 20, count: 2), .targetClosed(player: 0, target: 20), .targetDead(target: 20),
        .pointsScored(player: 0, points: 20), .pointsGiven(player: 0, to: [1], pointsEach: 20),
        .armingHit(player: 0, progress: 1), .becameKiller(player: 0), .lifeLost(player: 1, by: 0, livesLeft: 2),
        .zoneChanged(player: 0, zone: [16]),
        .targetHit(player: 0, number: 3, advancedBy: 1),
        .targetScored(player: 0, points: 14), .neighbourHit(player: 0, points: 5), .shanghai(player: 0), .halved(player: 0, points: 12),
        .damaged(player: 1, by: 0, amount: 2, livesLeft: 5), .healed(player: 0, amount: 1, lives: 6), .healWasted(player: 0),
        .sectorClaimed(player: 0, sector: 6), .sectorStrengthened(player: 0, sector: 6, lives: 2),
        .sectorDamaged(player: 0, sector: 13, livesLeft: 1), .sectorConquered(player: 0, sector: 13, from: 1), .kingOfTheHill(player: 0),
        .glassFilled(player: 0, count: 1, glasses: 2), .bonusGlass(player: 0, glasses: 3),
        .ballMoved(player: 0, by: 1, ball: 5), .goalScored(player: 0, side: 0, goals: 1, ownGoal: false),
        .blobDamaged(player: 0, blob: 0, points: 10, hitPointsLeft: 1), .blobDestroyed(player: 0, blob: 0, points: 60), .blobsMoved,
        .shotPlayed(player: 0, strokes: 2), .holeCompleted(player: 0, hole: 1, strokes: 2, total: 2), .holeInOne(player: 0, hole: 1),
    ]

    /// The name of the case. Exhaustive, without `default`: a new `GameEvent` case stops this file from
    /// compiling until the catalogue test knows it.
    private static func name(of event: GameEvent) -> String {
        switch event {
        case .dartRegistered: return "dartRegistered"
        case .noEffect: return "noEffect"
        case .turnCompleted: return "turnCompleted"
        case .roundStarted: return "roundStarted"
        case .turnStarted: return "turnStarted"
        case .playerEliminated: return "playerEliminated"
        case .gameFinished: return "gameFinished"
        case .turnScored: return "turnScored"
        case .oneEighty: return "oneEighty"
        case .highTurn: return "highTurn"
        case .bust: return "bust"
        case .doubleInOpened: return "doubleInOpened"
        case .doubleInRequired: return "doubleInRequired"
        case .checkout: return "checkout"
        case .landed: return "landed"
        case .marksScored: return "marksScored"
        case .targetClosed: return "targetClosed"
        case .targetDead: return "targetDead"
        case .pointsScored: return "pointsScored"
        case .pointsGiven: return "pointsGiven"
        case .armingHit: return "armingHit"
        case .becameKiller: return "becameKiller"
        case .lifeLost: return "lifeLost"
        case .zoneChanged: return "zoneChanged"
        case .targetHit: return "targetHit"
        case .targetScored: return "targetScored"
        case .neighbourHit: return "neighbourHit"
        case .shanghai: return "shanghai"
        case .halved: return "halved"
        case .damaged: return "damaged"
        case .healed: return "healed"
        case .healWasted: return "healWasted"
        case .sectorClaimed: return "sectorClaimed"
        case .sectorStrengthened: return "sectorStrengthened"
        case .sectorDamaged: return "sectorDamaged"
        case .sectorConquered: return "sectorConquered"
        case .kingOfTheHill: return "kingOfTheHill"
        case .glassFilled: return "glassFilled"
        case .bonusGlass: return "bonusGlass"
        case .ballMoved: return "ballMoved"
        case .goalScored: return "goalScored"
        case .blobDamaged: return "blobDamaged"
        case .blobDestroyed: return "blobDestroyed"
        case .blobsMoved: return "blobsMoved"
        case .shotPlayed: return "shotPlayed"
        case .holeCompleted: return "holeCompleted"
        case .holeInOne: return "holeInOne"
        }
    }

    @Test func catalogue_everyEventOfGamesMdIsACaseOfGameEvent_andHasASample() {
        let printed = Set(Self.catalogue.flatMap(\.events))
        let sampled = Self.oneOfEach.map(Self.name(of:))
        #expect(printed.count == 47)
        #expect(sampled.count == 47 && Set(sampled) == printed)
        // The ten events that version 1.1 added for the four games of lot G4.
        let g4 = Self.catalogue.suffix(4).flatMap(\.events)
        #expect(g4.count == 10 && Set(g4).isSubset(of: Set(sampled)))
    }

    @Test func catalogue_noEventIsLeftUnmapped() {
        let finished = CueContext(gameID: .x01, players: players, winners: [0])
        // The lines of the table that are printed with three dashes: nothing to hear, nothing to feel.
        let silentByTheTable: Set<String> = [
            "noEffect", "doubleInRequired", "healWasted", "shotPlayed", "turnCompleted", "roundStarted", "targetDead",
            "checkout", "landed",
        ]
        var silent: Set<String> = []
        for event in Self.oneOfEach {
            let cues = CueMapping.cues(for: [event], context: finished)
            if cues.isEmpty { silent.insert(Self.name(of: event)) }
            for cue in cues {
                #expect(cue.effect != nil || cue.announcement != nil || cue.haptic != nil, "empty cue for \(event)")
            }
        }
        #expect(silent == silentByTheTable)
        // The four silent markers still change what is heard: the dart of their batch sounds dull.
        for marker in [GameEvent.noEffect(player: 0), .doubleInRequired(player: 0), .healWasted(player: 0),
                       .shotPlayed(player: 0, strokes: 5)] {
            let batch = CueMapping.cues(for: [.dartRegistered(player: 0, hit: .single(1)), marker], context: finished)
            #expect(batch.map(\.effect) == [.dartDull], "\(marker)")
        }
    }

    @Test func catalogue_everyEventWithASentenceInTheTable_speaks_andNoOther() {
        let finished = CueContext(gameID: .x01, players: players, winners: [0])
        let speaking: [String: Announcement.Priority] = [
            "dartRegistered": .low, "turnStarted": .normal, "turnScored": .normal, "oneEighty": .high, "bust": .high,
            "becameKiller": .normal, "kingOfTheHill": .normal, "zoneChanged": .normal, "shanghai": .high, "halved": .normal,
            "bonusGlass": .normal, "goalScored": .high, "holeCompleted": .normal, "holeInOne": .high,
            "playerEliminated": .high, "gameFinished": .high,
        ]
        for event in Self.oneOfEach {
            let name = Self.name(of: event)
            let sentences = CueMapping.cues(for: [event], context: finished).compactMap(\.announcement)
            #expect(sentences.map(\.priority) == (speaking[name].map { [$0] } ?? []), "\(name)")
            #expect(sentences.allSatisfy { !$0.text.fr.isEmpty && !$0.text.en.isEmpty }, "\(name)")
            // The sentence of the table is the sentence of `CallerPhrases`.
            #expect(sentences.first?.text == (speaking[name] == nil ? nil : CallerPhrases.phrase(for: event, context: finished)), "\(name)")
        }
    }

    // MARK: - Properties over random batches

    @Test func randomBatches_keepTheSequencingRules() {
        var random = SeededRandom(seed: 20_261_110)
        let finished = CueContext(gameID: .x01, players: players, winners: [2])
        for _ in 0..<500 {
            let events = (0..<random.nextInt(below: 8)).map { _ in Self.oneOfEach[random.nextInt(below: Self.oneOfEach.count)] }
            let cues = CueMapping.cues(for: events, context: finished)

            // Deterministic.
            #expect(cues == CueMapping.cues(for: events, context: finished))
            // No empty cue; delays are whole milliseconds that never go back.
            #expect(cues.allSatisfy { $0.effect != nil || $0.announcement != nil || $0.haptic != nil })
            #expect(cues.map(\.delay) == cues.map(\.delay).sorted())
            #expect(cues.allSatisfy { $0.delay >= 0 && ($0.delay * 1000).rounded() / 1000 == $0.delay })
            // At most one haptic: the strongest of what each event asks for on its own.
            let strength: [HapticPattern] = [.light, .medium, .heavy, .warning, .success, .failure]
            let wanted = events.flatMap { CueMapping.cues(for: [$0], context: finished).compactMap(\.haptic) }
            let strongest = wanted.max { strength.firstIndex(of: $0)! < strength.firstIndex(of: $1)! }
            #expect(cues.compactMap(\.haptic) == (strongest.map { [$0] } ?? []))
            // The effects are those of the events, in order, the first at 0 s, 0.12 s apart (0.09 s between ticks
            // of one `marksScored`).
            let dull = events.contains { ["noEffect", "doubleInRequired", "healWasted"].contains(Self.name(of: $0)) }
            let alone = events.flatMap { event -> [SoundEffect] in
                let effects = CueMapping.cues(for: [event], context: finished).compactMap(\.effect)
                return dull && effects == [.dartImpact] ? [.dartDull] : effects
            }
            let effects = cues.filter { $0.effect != nil }
            #expect(effects.compactMap(\.effect) == alone)
            if let first = effects.first { #expect(first.delay == 0) }
            for (before, after) in zip(effects, effects.dropFirst()) {
                let gap = ((after.delay - before.delay) * 1000).rounded()
                #expect(gap == 120 || (gap == 90 && before.effect == .tick && after.effect == .tick))
            }
            // The winner is named last, 0.6 s after the victory effect.
            if let victory = cues.first(where: { $0.effect == .victory }) {
                let named = cues.first { $0.announcement?.text == LocalizedText(fr: "Zoé gagne la partie", en: "Zoé wins") }
                #expect(named != nil)
                if let named { #expect(((named.delay - victory.delay) * 1000).rounded() >= 600) }
            }
        }
    }

    // MARK: - Interface cues

    @Test func interface_gameStarted() {
        #expect(CueMapping.cues(for: .gameStarted(firstPlayer: 1), context: context) == [
            AudioCue(effect: .turnChange, announcement: sentence("Au tour de Tom", "Tom to throw", .normal)),
        ])
        let solo = CueContext(gameID: .golf, players: [Player(name: "Léa")])
        #expect(CueMapping.cues(for: .gameStarted(firstPlayer: 0), context: solo) == [AudioCue(effect: .turnChange)])
        #expect(CueMapping.cues(for: .gameStarted(firstPlayer: 12), context: context) == [AudioCue(effect: .turnChange)])
    }

    @Test func interface_theOtherLinesOfTheTable() {
        let expected: [(InterfaceCue, AudioCue)] = [
            (.dartNeedsReview, AudioCue(effect: .needsReview, haptic: .light)),
            (.dartUndecided, AudioCue(effect: .needsReview, announcement: sentence("À vérifier", "Please check", .normal), haptic: .warning)),
            (.dartIgnored, AudioCue(effect: .rejected, haptic: .warning)),
            (.possibleMiss, AudioCue(haptic: .light)),
            (.boardCleared, AudioCue(haptic: .light)),
            (.undo, AudioCue(effect: .tick, haptic: .light)),
            (.correctionApplied, AudioCue(effect: .confirm, haptic: .light)),
            (.shutter, AudioCue(effect: .shutter, haptic: .medium)),
            (.calibrationValidated, AudioCue(effect: .confirm, haptic: .success)),
            (.calibrationLost, AudioCue(effect: .alert, announcement: sentence("Calibrage perdu", "Calibration lost", .high), haptic: .failure)),
            (.buttonTap, AudioCue(haptic: .light)),
        ]
        for (cue, audio) in expected {
            #expect(CueMapping.cues(for: cue, context: context) == [audio], "\(cue)")
            // Nothing here depends on the game or on its players.
            #expect(CueMapping.cues(for: cue, context: CueContext(gameID: .radar, players: [])) == [audio], "\(cue)")
        }
    }
}
