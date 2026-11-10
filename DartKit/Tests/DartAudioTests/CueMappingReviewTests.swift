import Foundation
import Testing
import DartCore
import DartAudio

/// Adversarial review of the table event → sound (ARCHITECTURE.md §7.3). The table is written again here, from the
/// document, as an oracle; then whole batches as the fourteen engines emit them (event orders of GAMES.md §2.10 and
/// §n.8) are checked cue by cue, with delays computed by hand from the sequencing rules.
@Suite struct CueMappingReviewTests {
    private let players = [Player(name: "Léa"), Player(name: "Tom"), Player(name: "Alice")]

    private func context(winners: [PlayerIndex] = [], title: LocalizedText? = nil) -> CueContext {
        CueContext(gameID: .x01, players: players, winners: winners, winnerTitle: title)
    }

    private func low(_ fr: String, _ en: String? = nil) -> Announcement {
        Announcement(LocalizedText(fr: fr, en: en ?? fr), priority: .low)
    }

    private func normal(_ fr: String, _ en: String? = nil) -> Announcement {
        Announcement(LocalizedText(fr: fr, en: en ?? fr), priority: .normal)
    }

    private func high(_ fr: String, _ en: String? = nil) -> Announcement {
        Announcement(LocalizedText(fr: fr, en: en ?? fr), priority: .high)
    }

    // MARK: - The table, line by line

    private struct Line: Equatable {
        var effects: [SoundEffect] = []
        var sentence: Announcement?
        var haptic: HapticPattern?
    }

    /// The line of §7.3 for one event alone, in a context where Léa (0) has won.
    private func table(_ event: GameEvent) -> Line {
        let name = { (index: Int) in self.players[index].name }
        switch event {
        case .dartRegistered(_, let hit):
            let call: (String, String)
            switch hit.bed {
            case .miss: call = ("Manqué", "Miss")
            case .outerBull: call = ("Bull", "Bull")
            case .innerBull: call = ("Double bull", "Bullseye")
            case .single: call = ("\(hit.number ?? 0)", "\(hit.number ?? 0)")
            case .double: call = ("Double \(hit.number ?? 0)", "Double \(hit.number ?? 0)")
            case .treble: call = ("Triple \(hit.number ?? 0)", "Treble \(hit.number ?? 0)")
            }
            return Line(effects: [hit.isMiss ? .dartDull : .dartImpact], sentence: low(call.0, call.1), haptic: .light)
        case .noEffect, .doubleInRequired, .healWasted, .shotPlayed, .turnCompleted, .roundStarted, .targetDead, .checkout, .landed:
            return Line()
        case .turnStarted(let player, _):
            // Of the three players, only Alice starts with a vowel.
            let of = name(player) == "Alice" ? "d'Alice" : "de \(name(player))"
            return Line(effects: [.turnChange], sentence: normal("Au tour \(of)", "\(name(player)) to throw"))
        case .turnScored(_, let points):
            return Line(sentence: normal("\(points)"))
        case .highTurn:
            return Line(effects: [.highTurn], haptic: .medium)
        case .oneEighty:
            return Line(effects: [.fanfare], sentence: high("Cent quatre-vingts !", "One hundred and eighty!"), haptic: .success)
        case .bust:
            return Line(effects: [.bust], sentence: high("Bust"), haptic: .failure)
        case .doubleInOpened:
            return Line(effects: [.scoreUp])
        case .marksScored(_, _, let count):
            return Line(effects: Array(repeating: .tick, count: min(max(count, 0), 9)))
        case .targetClosed:
            return Line(effects: [.lock], haptic: .medium)
        case .pointsScored, .pointsGiven, .targetScored, .neighbourHit, .targetHit:
            return Line(effects: [.scoreUp])
        case .armingHit:
            return Line(effects: [.tick])
        case .becameKiller(let player):
            return Line(effects: [.powerUp], sentence: normal("\(name(player)) est Killer", "\(name(player)) is a Killer"), haptic: .medium)
        case .lifeLost, .damaged, .sectorDamaged:
            return Line(effects: [.damage], haptic: .medium)
        case .healed, .sectorStrengthened:
            return Line(effects: [.heal])
        case .sectorClaimed, .sectorConquered:
            return Line(effects: [.claim])
        case .kingOfTheHill(let player):
            return Line(effects: [.powerUp], sentence: normal("\(name(player)) est Roi", "\(name(player)) is King"), haptic: .medium)
        case .zoneChanged(_, let zone):
            let numbers = zone.map(String.init).joined(separator: ", ")
            return Line(effects: [.zoneMove], sentence: zone.count == 1
                ? normal("Nouveau numéro : \(numbers)", "New number: \(numbers)")
                : normal("Nouveaux numéros : \(numbers)", "New numbers: \(numbers)"))
        case .shanghai:
            return Line(effects: [.fanfare], sentence: high("Shanghai !", "Shanghai!"), haptic: .success)
        case .halved:
            return Line(effects: [.halved], sentence: normal("Score divisé par deux", "Score halved"), haptic: .warning)
        case .glassFilled:
            return Line(effects: [.scoreUp], haptic: .medium)
        case .bonusGlass:
            return Line(effects: [.powerUp], sentence: normal("Tournée offerte !", "This one's on the house!"), haptic: .success)
        case .ballMoved:
            return Line(effects: [.tick])
        case .goalScored(_, _, _, let ownGoal):
            return ownGoal
                ? Line(effects: [.halved], sentence: high("Contre son camp !", "Own goal!"), haptic: .warning)
                : Line(effects: [.fanfare], sentence: high("But !", "Goal!"), haptic: .success)
        case .blobDamaged:
            return Line(effects: [.damage], haptic: .medium)
        case .blobDestroyed:
            return Line(effects: [.powerUp], haptic: .heavy)
        case .blobsMoved:
            return Line(effects: [.zoneMove])
        case .holeCompleted(_, _, let strokes, _):
            return Line(sentence: strokes == 1 ? normal("1 coup", "1 stroke") : normal("\(strokes) coups", "\(strokes) strokes"))
        case .holeInOne:
            return Line(effects: [.fanfare], sentence: high("Trou en un !", "Hole in one!"), haptic: .success)
        case .playerEliminated(let player, _):
            return Line(effects: [.eliminated], sentence: high("\(name(player)) est éliminé", "\(name(player)) is out"), haptic: .heavy)
        case .gameFinished:
            return Line(effects: [.victory], sentence: high("Léa gagne la partie", "Léa wins"), haptic: .success)
        }
    }

    /// Every case of `GameEvent`, with the variants that change a line.
    private var samples: [GameEvent] {
        var events: [GameEvent] = Hit.all.map { .dartRegistered(player: 1, hit: $0) }
        events += [
            .noEffect(player: 0), .doubleInRequired(player: 0), .healWasted(player: 0),
            .turnCompleted(player: 0), .roundStarted(round: 4), .targetDead(target: 25), .checkout(player: 0, points: 170, darts: 3),
            .landed(player: 0), .turnStarted(player: 0, round: 1), .turnStarted(player: 2, round: 9),
            .highTurn(player: 0, points: 100), .highTurn(player: 0, points: 179), .oneEighty(player: 1),
            .bust(player: 0, reason: .belowZero), .bust(player: 0, reason: .notADouble), .bust(player: 0, reason: .oneLeft),
            .doubleInOpened(player: 0), .targetClosed(player: 0, target: 25), .pointsScored(player: 0, points: 75),
            .pointsGiven(player: 0, to: [1, 2], pointsEach: 25), .armingHit(player: 0, progress: 3), .becameKiller(player: 1),
            .lifeLost(player: 2, by: 0, livesLeft: 0), .zoneChanged(player: 1, zone: [5]), .zoneChanged(player: 1, zone: [5, 20, 1]),
            .targetHit(player: 0, number: 20, advancedBy: 1), .targetScored(player: 0, points: 60), .neighbourHit(player: 0, points: 1),
            .shanghai(player: 2), .halved(player: 0, points: 0), .damaged(player: 2, by: 1, amount: 3, livesLeft: 4),
            .healed(player: 1, amount: 2, lives: 10), .sectorClaimed(player: 0, sector: 25), .sectorStrengthened(player: 0, sector: 4, lives: 3),
            .sectorDamaged(player: 1, sector: 4, livesLeft: 2), .sectorConquered(player: 0, sector: 4, from: 1), .kingOfTheHill(player: 2),
            .glassFilled(player: 0, count: 3, glasses: 9), .bonusGlass(player: 0, glasses: 10), .ballMoved(player: 0, by: -3, ball: 0),
            .goalScored(player: 0, side: 0, goals: 2, ownGoal: false), .goalScored(player: 2, side: 0, goals: 3, ownGoal: true),
            .blobDamaged(player: 0, blob: 4, points: 15, hitPointsLeft: 2), .blobDestroyed(player: 0, blob: 0, points: 115), .blobsMoved,
            .holeCompleted(player: 0, hole: 9, strokes: 1, total: 20), .holeCompleted(player: 0, hole: 9, strokes: 2, total: 21),
            .holeCompleted(player: 0, hole: 9, strokes: 15, total: 45), .holeInOne(player: 0, hole: 9),
            .playerEliminated(player: 2, by: 1), .gameFinished(reason: .victory), .gameFinished(reason: .lastPlayerStanding),
            .gameFinished(reason: .roundLimit),
        ]
        events += (1...5).map { .shotPlayed(player: 0, strokes: $0) }
        events += (0...4).map { .marksScored(player: 0, target: 20, count: $0) }
        return events
    }

    @Test func everyEventAlone_hasItsLineOfTheTable() {
        let finished = context(winners: [0])
        for event in samples {
            let cues = CueMapping.cues(for: [event], context: finished)
            let found = Line(effects: cues.compactMap(\.effect),
                             sentence: cues.compactMap(\.announcement).first,
                             haptic: cues.compactMap(\.haptic).first)
            #expect(found == table(event), "\(event)")
            #expect(cues.compactMap(\.announcement).count <= 1 && cues.compactMap(\.haptic).count <= 1, "\(event)")
            #expect(cues.allSatisfy { $0.effect != nil || $0.announcement != nil || $0.haptic != nil }, "\(event)")
        }
    }

    @Test func soloGame_saysNoName_atTheStartOfATurn_butStillChangesTurnAudibly() {
        let solo = CueContext(gameID: .aroundTheClock, players: [Player(name: "Léa")], winners: [0])
        #expect(CueMapping.cues(for: [.roundStarted(round: 2), .turnStarted(player: 0, round: 2)], context: solo) == [AudioCue(effect: .turnChange)])
        // The rest of the table does not depend on the number of players.
        #expect(CueMapping.cues(for: [.gameFinished(reason: .victory)], context: solo).last?.announcement
            == high("Léa gagne la partie", "Léa wins"))
    }

    // MARK: - Whole batches, as the engines emit them

    @Test func x01_everyTotalOfAClosingThirdDart() {
        for points in 0...180 {
            var events: [GameEvent] = [.dartRegistered(player: 0, hit: .single(1)), .turnScored(player: 0, points: points)]
            if points == 180 { events.append(.oneEighty(player: 0)) }
            if (100...179).contains(points) { events.append(.highTurn(player: 0, points: points)) }
            events.append(.turnCompleted(player: 0))
            let expected: [AudioCue]
            switch points {
            case 180:
                expected = [AudioCue(effect: .dartImpact, announcement: low("1"), delay: 0),
                            AudioCue(effect: .fanfare, announcement: high("Cent quatre-vingts !", "One hundred and eighty!"),
                                     haptic: .success, delay: 0.12)]
            case 100...179:
                expected = [AudioCue(effect: .dartImpact, announcement: low("1"), delay: 0),
                            AudioCue(announcement: normal("\(points)"), delay: 0),
                            AudioCue(effect: .highTurn, haptic: .medium, delay: 0.12)]
            default:
                expected = [AudioCue(effect: .dartImpact, announcement: low("1"), haptic: .light, delay: 0),
                            AudioCue(announcement: normal("\(points)"), delay: 0)]
            }
            #expect(CueMapping.cues(for: events, context: context()) == expected, "\(points)")
        }
    }

    @Test func x01_turnConfirmedEarly_totalThenNextPlayer() {
        let events: [GameEvent] = [.turnScored(player: 0, points: 45), .turnCompleted(player: 0), .turnStarted(player: 1, round: 1)]
        #expect(CueMapping.cues(for: events, context: context()) == [
            AudioCue(announcement: normal("45"), delay: 0),
            AudioCue(effect: .turnChange, announcement: normal("Au tour de Tom", "Tom to throw"), delay: 0),
        ])
    }

    @Test func x01_dartNotCountedBeforeTheDoubleIn_soundsDull() {
        #expect(CueMapping.cues(for: [.dartRegistered(player: 0, hit: .treble(20)), .doubleInRequired(player: 0)], context: context())
            == [AudioCue(effect: .dartDull, announcement: low("Triple 20", "Treble 20"), haptic: .light)])
        #expect(CueMapping.cues(for: [.dartRegistered(player: 0, hit: .double(20)), .doubleInOpened(player: 0)], context: context()) == [
            AudioCue(effect: .dartImpact, announcement: low("Double 20"), haptic: .light, delay: 0),
            AudioCue(effect: .scoreUp, delay: 0.12),
        ])
    }

    @Test func moonLanding_landingWinsTheGame() {
        let events: [GameEvent] = [.dartRegistered(player: 0, hit: .double(10)), .landed(player: 0), .gameFinished(reason: .victory)]
        #expect(CueMapping.cues(for: events, context: context(winners: [0])) == [
            AudioCue(effect: .dartImpact, announcement: low("Double 10"), delay: 0),
            AudioCue(effect: .victory, haptic: .success, delay: 0.12),
            AudioCue(announcement: high("Léa gagne la partie", "Léa wins"), delay: 0.72),
        ])
    }

    @Test func cricket_cutThroat_twoMarksCloseThenGivePoints() {
        let events: [GameEvent] = [.dartRegistered(player: 0, hit: .treble(20)), .marksScored(player: 0, target: 20, count: 2),
                                   .targetClosed(player: 0, target: 20), .pointsGiven(player: 0, to: [1, 2], pointsEach: 20)]
        #expect(CueMapping.cues(for: events, context: context()) == [
            AudioCue(effect: .dartImpact, announcement: low("Triple 20", "Treble 20"), delay: 0),
            AudioCue(effect: .tick, delay: 0.12),
            AudioCue(effect: .tick, delay: 0.21),
            AudioCue(effect: .lock, haptic: .medium, delay: 0.33),
            AudioCue(effect: .scoreUp, delay: 0.45),
        ])
    }

    @Test func killer_lastArmingHitMakesAKiller() {
        let events: [GameEvent] = [.dartRegistered(player: 2, hit: .double(7)), .armingHit(player: 2, progress: 3), .becameKiller(player: 2)]
        #expect(CueMapping.cues(for: events, context: context()) == [
            AudioCue(effect: .dartImpact, announcement: low("Double 7"), delay: 0),
            AudioCue(effect: .tick, delay: 0.12),
            AudioCue(effect: .powerUp, announcement: normal("Alice est Killer", "Alice is a Killer"), haptic: .medium, delay: 0.24),
        ])
    }

    @Test func killer_aKillerWhoHitsHisOwnZone_endsTheGame() {
        let events: [GameEvent] = [.dartRegistered(player: 1, hit: .treble(9)), .lifeLost(player: 1, by: 1, livesLeft: 0),
                                   .playerEliminated(player: 1, by: 1), .gameFinished(reason: .lastPlayerStanding)]
        #expect(CueMapping.cues(for: events, context: context(winners: [0])) == [
            AudioCue(effect: .dartImpact, announcement: low("Triple 9", "Treble 9"), delay: 0),
            AudioCue(effect: .damage, delay: 0.12),
            AudioCue(effect: .eliminated, announcement: high("Tom est éliminé", "Tom is out"), delay: 0.24),
            AudioCue(effect: .victory, haptic: .success, delay: 0.36),
            AudioCue(announcement: high("Léa gagne la partie", "Léa wins"), delay: 0.96),
        ])
    }

    @Test func killerExpert_newRound_newNumberAfterTheName() {
        let events: [GameEvent] = [.turnCompleted(player: 2), .roundStarted(round: 5), .zoneChanged(player: 0, zone: [11]),
                                   .turnStarted(player: 0, round: 5)]
        #expect(CueMapping.cues(for: events, context: context()) == [
            AudioCue(effect: .zoneMove, delay: 0),
            AudioCue(effect: .turnChange, announcement: normal("Au tour de Léa", "Léa to throw"), delay: 0.12),
            AudioCue(announcement: normal("Nouveau numéro : 11", "New number: 11"), delay: 0.12),
        ])
    }

    @Test func aroundTheClock_and_shanghai() {
        #expect(CueMapping.cues(for: [.dartRegistered(player: 0, hit: .treble(19)), .targetHit(player: 0, number: 19, advancedBy: 2)],
                                context: context()) == [
            AudioCue(effect: .dartImpact, announcement: low("Triple 19", "Treble 19"), haptic: .light, delay: 0),
            AudioCue(effect: .scoreUp, delay: 0.12),
        ])
        // The Shanghai that wins: two `success` haptics, the first one stays.
        let events: [GameEvent] = [.dartRegistered(player: 1, hit: .treble(5)), .targetScored(player: 1, points: 15),
                                   .shanghai(player: 1), .gameFinished(reason: .victory)]
        #expect(CueMapping.cues(for: events, context: context(winners: [1])) == [
            AudioCue(effect: .dartImpact, announcement: low("Triple 5", "Treble 5"), delay: 0),
            AudioCue(effect: .scoreUp, delay: 0.12),
            AudioCue(effect: .fanfare, announcement: high("Shanghai !", "Shanghai!"), haptic: .success, delay: 0.24),
            AudioCue(effect: .victory, delay: 0.36),
            AudioCue(announcement: high("Tom gagne la partie", "Tom wins"), delay: 0.96),
        ])
    }

    @Test func halveIt_aRoundMissedOnConfirmation_halvesThenCallsTheNextPlayer() {
        let events: [GameEvent] = [.halved(player: 0, points: 15), .turnCompleted(player: 0), .turnStarted(player: 1, round: 3)]
        #expect(CueMapping.cues(for: events, context: context()) == [
            AudioCue(effect: .halved, announcement: normal("Score divisé par deux", "Score halved"), haptic: .warning, delay: 0),
            AudioCue(effect: .turnChange, announcement: normal("Au tour de Tom", "Tom to throw"), delay: 0.12),
        ])
    }

    @Test func fight_wastedHealSoundsDull_andTheKnockOutIsHeavy() {
        #expect(CueMapping.cues(for: [.dartRegistered(player: 0, hit: .single(20)), .healWasted(player: 0)], context: context())
            == [AudioCue(effect: .dartDull, announcement: low("20"), haptic: .light)])
        let events: [GameEvent] = [.dartRegistered(player: 0, hit: .double(3)), .damaged(player: 2, by: 0, amount: 2, livesLeft: 0),
                                   .playerEliminated(player: 2, by: 0)]
        #expect(CueMapping.cues(for: events, context: context()) == [
            AudioCue(effect: .dartImpact, announcement: low("Double 3"), delay: 0),
            AudioCue(effect: .damage, delay: 0.12),
            AudioCue(effect: .eliminated, announcement: high("Alice est éliminé", "Alice is out"), haptic: .heavy, delay: 0.24),
        ])
    }

    @Test func conqueror_kingAndTakenHouse() {
        #expect(CueMapping.cues(for: [.dartRegistered(player: 2, hit: .innerBull), .kingOfTheHill(player: 2)], context: context()) == [
            AudioCue(effect: .dartImpact, announcement: low("Double bull", "Bullseye"), delay: 0),
            AudioCue(effect: .powerUp, announcement: normal("Alice est Roi", "Alice is King"), haptic: .medium, delay: 0.12),
        ])
        let events: [GameEvent] = [.dartRegistered(player: 0, hit: .single(6)), .sectorConquered(player: 0, sector: 6, from: 1),
                                   .playerEliminated(player: 1, by: 0), .gameFinished(reason: .lastPlayerStanding)]
        #expect(CueMapping.cues(for: events, context: context(winners: [0])) == [
            AudioCue(effect: .dartImpact, announcement: low("6"), delay: 0),
            AudioCue(effect: .claim, delay: 0.12),
            AudioCue(effect: .eliminated, announcement: high("Tom est éliminé", "Tom is out"), delay: 0.24),
            AudioCue(effect: .victory, haptic: .success, delay: 0.36),
            AudioCue(announcement: high("Léa gagne la partie", "Léa wins"), delay: 0.96),
        ])
    }

    @Test func football_aWinningOwnGoal_saysTheSideThatWins() {
        let title = LocalizedText(fr: "Le camp B gagne", en: "Side B wins")
        let events: [GameEvent] = [.dartRegistered(player: 0, hit: .single(11)), .ballMoved(player: 0, by: -1, ball: 0),
                                   .goalScored(player: 0, side: 1, goals: 3, ownGoal: true), .gameFinished(reason: .victory)]
        #expect(CueMapping.cues(for: events, context: context(winners: [1], title: title)) == [
            AudioCue(effect: .dartImpact, announcement: low("11"), delay: 0),
            AudioCue(effect: .tick, delay: 0.12),
            AudioCue(effect: .halved, announcement: high("Contre son camp !", "Own goal!"), delay: 0.24),
            AudioCue(effect: .victory, haptic: .success, delay: 0.36),
            AudioCue(announcement: Announcement(title, priority: .high), delay: 0.96),
        ])
    }

    @Test func radar_movingTargetsAtTheEndOfAnEarlyTurn() {
        let events: [GameEvent] = [.turnScored(player: 2, points: 90), .turnCompleted(player: 2), .roundStarted(round: 2),
                                   .blobsMoved, .turnStarted(player: 0, round: 2)]
        #expect(CueMapping.cues(for: events, context: context()) == [
            AudioCue(announcement: normal("90"), delay: 0),
            AudioCue(effect: .zoneMove, delay: 0),
            AudioCue(effect: .turnChange, announcement: normal("Au tour de Léa", "Léa to throw"), delay: 0.12),
        ])
    }

    @Test func golf_holeConfirmedAfterTwoDarts_thenNextPlayer() {
        let events: [GameEvent] = [.holeCompleted(player: 0, hole: 3, strokes: 4, total: 11), .turnCompleted(player: 0),
                                   .turnStarted(player: 1, round: 3)]
        #expect(CueMapping.cues(for: events, context: context()) == [
            AudioCue(announcement: normal("4 coups", "4 strokes"), delay: 0),
            AudioCue(effect: .turnChange, announcement: normal("Au tour de Tom", "Tom to throw"), delay: 0),
        ])
        // The last hole ends at the confirmation: only the end of the game is heard.
        #expect(CueMapping.cues(for: [.gameFinished(reason: .roundLimit)], context: context(winners: [2])) == [
            AudioCue(effect: .victory, haptic: .success, delay: 0),
            AudioCue(announcement: high("Alice gagne la partie", "Alice wins"), delay: 0.6),
        ])
    }

    @Test func mapping_isAPureFunctionOfItsInput() {
        // Same events and context, same cues, in any order of calls and from several tasks at once.
        let events: [GameEvent] = [.dartRegistered(player: 0, hit: .treble(20)), .marksScored(player: 0, target: 20, count: 3),
                                   .targetClosed(player: 0, target: 20), .turnCompleted(player: 0)]
        let reference = CueMapping.cues(for: events, context: context())
        let results = (0..<64).map { _ in CueMapping.cues(for: events, context: context()) }
        #expect(results.allSatisfy { $0 == reference })
    }
}
