import Foundation
import Testing
import DartCore
@testable import DartAudio

/// Adversarial review of what the player hears and feels (ARCHITECTURE.md §7.3 to §7.6): mapped batches go through
/// the real `AudioDirector`, `ScoreCaller` and priority rules, over outputs that record and a clock driven by hand.
@MainActor
@Suite struct AudioDirectorReviewTests {
    private let effects = AudioTestEffects()
    private let voice = AudioTestVoice()
    private let haptics = AudioTestHaptics()
    private let clock = AudioTestClock()
    private let players = [Player(name: "Léa"), Player(name: "Tom")]

    private func makeDirector(_ change: (inout AudioSettings) -> Void = { _ in }) -> AudioDirector {
        var settings = AudioSettings()
        change(&settings)
        let effects = self.effects
        return AudioDirector(settings: settings, effects: { effects.receive($0) }, voice: voice, haptics: haptics,
                             schedule: clock.scheduler)
    }

    private func play(_ director: AudioDirector, _ events: [GameEvent], winners: [PlayerIndex] = []) {
        director.play(CueMapping.cues(for: events, context: CueContext(gameID: .x01, players: players, winners: winners)))
    }

    /// Lets the clock run and every sentence end, one at a time, until nothing is left to say.
    private func sayEverything() {
        for _ in 0..<50 {
            clock.advance(by: 1)
            voice.finishLast()
        }
    }

    // MARK: - X01, every total

    @Test func x01_everyClosingTotal_isHeardAsTheTableSays() {
        for points in 0...180 {
            let voice = AudioTestVoice()
            let haptics = AudioTestHaptics()
            let clock = AudioTestClock()
            let director = AudioDirector(settings: AudioSettings(), effects: { _ in }, voice: voice, haptics: haptics,
                                         schedule: clock.scheduler)
            var events: [GameEvent] = [.dartRegistered(player: 0, hit: .treble(20)), .turnScored(player: 0, points: points)]
            if points == 180 { events.append(.oneEighty(player: 0)) }
            if (100...179).contains(points) { events.append(.highTurn(player: 0, points: points)) }
            events.append(.turnCompleted(player: 0))
            director.play(CueMapping.cues(for: events, context: CueContext(gameID: .x01, players: players)))
            for _ in 0..<5 {
                clock.advance(by: 1)
                voice.finishLast()
            }
            if points == 180 {
                // Only the exclamation: never "Triple 20" cut by it, never "180" after it.
                #expect(voice.spoken == ["Cent quatre-vingts !"] && voice.stops == 0)
                #expect(haptics.played == [.success])
            } else {
                // The dart, then the total, each to its end.
                #expect(voice.spoken == ["Triple 20", "\(points)"] && voice.stops == 0, "\(points)")
                #expect(haptics.played == [(100...179).contains(points) ? .medium : .light], "\(points)")
            }
        }
    }

    @Test func x01_bustThenNextPlayer_bothSaidInFull() {
        let director = makeDirector()
        play(director, [.dartRegistered(player: 0, hit: .treble(20)), .bust(player: 0, reason: .belowZero), .turnCompleted(player: 0)])
        clock.advance(by: 0.12)
        #expect(voice.spoken == ["Bust"] && haptics.played == [.failure])
        // The next player is called while "Bust" is still said: it waits for it.
        play(director, [.turnStarted(player: 1, round: 2)])
        #expect(voice.spoken == ["Bust"] && voice.stops == 0)
        voice.finishLast()
        #expect(voice.spoken == ["Bust", "Au tour de Tom"] && voice.stops == 0)
    }

    @Test func x01_checkout_theWinningDartIsCalled_thenTheWinner() {
        let director = makeDirector()
        play(director, [.dartRegistered(player: 1, hit: .double(16)), .checkout(player: 1, points: 32, darts: 1),
                        .gameFinished(reason: .victory)], winners: [1])
        #expect(voice.spoken == ["Double 16"])
        voice.finishLast()
        clock.advance(by: 0.72)
        #expect(voice.spoken == ["Double 16", "Tom gagne la partie"] && voice.stops == 0)
        #expect(effects.played == [.play(.dartImpact, after: 0), .play(.victory, after: 0.12)])
        #expect(haptics.played == [.success])
    }

    // MARK: - Darts in quick succession

    @Test func nextDart_replacesTheCallOfThePreviousOne_butNeverAScoreOrAName() {
        let director = makeDirector()
        play(director, [.dartRegistered(player: 0, hit: .treble(20))])
        play(director, [.dartRegistered(player: 0, hit: .treble(19))])
        #expect(voice.orders.map(Self.name) == ["warmUp", "speak Triple 20", "stop", "speak Triple 19"])
        // A total and a name are never replaced by a dart call: the call is dropped instead.
        play(director, [.dartRegistered(player: 0, hit: .single(5)), .turnScored(player: 0, points: 62), .turnCompleted(player: 0)])
        play(director, [.turnStarted(player: 1, round: 1)])
        play(director, [.dartRegistered(player: 1, hit: .single(1))])
        sayEverything()
        #expect(voice.spoken == ["Triple 20", "Triple 19", "5", "62", "Au tour de Tom"])
    }

    @Test func killerExpert_theNewNumberFollowsTheName_afterTheTurnTotal() {
        let director = makeDirector()
        play(director, [.dartRegistered(player: 0, hit: .single(3)), .lifeLost(player: 1, by: 0, livesLeft: 2), .turnCompleted(player: 0)])
        play(director, [.roundStarted(round: 2), .zoneChanged(player: 1, zone: [14]), .turnStarted(player: 1, round: 2)])
        sayEverything()
        #expect(voice.spoken == ["3", "Au tour de Tom", "Nouveau numéro : 14"])
        #expect(effects.played.suffix(2) == [.play(.zoneMove, after: 0), .play(.turnChange, after: 0.12)])
    }

    // MARK: - No unbounded queue, no blocked voice

    @Test func aVoiceThatNeverEnds_neverBlocks_andTheQueueStaysBounded() {
        let director = makeDirector()
        for index in 1...20 {
            director.say(LocalizedText(verbatim: "\(index)"))
        }
        #expect(voice.spoken == ["1"])
        // The voice reports nothing: every sentence is given up after the timeout, the next one starts.
        for _ in 0..<10 {
            clock.advance(by: ScoreCaller.sentenceTimeout)
        }
        // The first one, then the last four that waited: the older ones were dropped, nothing more is said.
        #expect(voice.spoken == ["1", "17", "18", "19", "20"])
        #expect(clock.pending == 0)
    }

    // MARK: - Haptics only where there is a Taptic Engine

    @Test func iPad_neverVibrates_butHearsEverything() {
        haptics.isSupported = false
        let director = makeDirector()
        #expect(!director.supportsHaptics)
        play(director, [.dartRegistered(player: 0, hit: .single(5)), .lifeLost(player: 1, by: 0, livesLeft: 0),
                        .playerEliminated(player: 1, by: 0), .gameFinished(reason: .lastPlayerStanding)], winners: [0])
        for cue in InterfaceCue.allForReview {
            director.play(CueMapping.cues(for: cue, context: CueContext(gameID: .x01, players: players)))
        }
        sayEverything()
        #expect(haptics.played.isEmpty)
        #expect(!effects.played.isEmpty && !voice.spoken.isEmpty)
    }

    @Test func iPhone_vibratesOncePerBatch_theStrongest() {
        let director = makeDirector()
        play(director, [.dartRegistered(player: 0, hit: .single(5)), .lifeLost(player: 1, by: 0, livesLeft: 0),
                        .playerEliminated(player: 1, by: 0), .gameFinished(reason: .lastPlayerStanding)], winners: [0])
        clock.advance(by: 2)
        #expect(haptics.played == [.success])
        director.play(CueMapping.cues(for: .calibrationLost, context: CueContext(gameID: .x01, players: players)))
        #expect(haptics.played == [.success, .failure])
    }

    // MARK: - Leaving, muting, stopping in the middle of a batch

    @Test func leavingTheForeground_beforeTheWinnerIsNamed_forgetsTheName() {
        let director = makeDirector()
        play(director, [.dartRegistered(player: 0, hit: .double(20)), .checkout(player: 0, points: 40, darts: 1),
                        .gameFinished(reason: .victory)], winners: [0])
        // Back in the foreground before the name was due: what the older batch still had to say is forgotten too.
        director.setActive(false)
        clock.advance(by: 0.1)
        director.setActive(true)
        clock.advance(by: 2)
        #expect(voice.spoken == ["Double 20"] && haptics.played.isEmpty)
        play(director, [.turnStarted(player: 1, round: 1)])
        #expect(voice.spoken == ["Double 20", "Au tour de Tom"])
    }

    @Test func muting_inTheMiddleOfABatch_silencesWhatIsStillToCome() {
        let director = makeDirector()
        play(director, [.dartRegistered(player: 0, hit: .single(5)), .lifeLost(player: 1, by: 0, livesLeft: 0),
                        .playerEliminated(player: 1, by: 0), .gameFinished(reason: .lastPlayerStanding)], winners: [0])
        clock.advance(by: 0.3)
        // "5" was left out (the elimination would cut it within half a second); the elimination started at 0.24 s.
        #expect(voice.spoken == ["Tom est éliminé"])
        director.settings.isMuted = true
        #expect(voice.orders.last == .stop && effects.orders.last == .stopAll)
        clock.advance(by: 2)
        // Neither the winner's name nor the haptic of the victory, due at 0.36 s and 0.96 s.
        #expect(voice.spoken == ["Tom est éliminé"] && haptics.played.isEmpty)
    }

    @Test func voiceSettings_reachEverySentence_volumeKeptIn0To1() {
        let director = makeDirector { $0.volume = 1.5; $0.ducksMusicWhileSpeaking = false; $0.callerLanguage = .en }
        play(director, [.turnStarted(player: 1, round: 1)])
        director.settings.volume = .nan
        director.settings.ducksMusicWhileSpeaking = true
        director.settings.callerLanguage = .fr
        play(director, [.turnStarted(player: 0, round: 1)])
        voice.finishLast()
        #expect(voice.sentences.map(\.text) == ["Tom to throw", "Au tour de Léa"])
        #expect(voice.sentences.map(\.volume) == [1, 0])
        #expect(voice.sentences.map(\.ducksOthers) == [false, true])
    }

    private static func name(_ order: AudioTestVoice.Order) -> String {
        switch order {
        case .warmUp: return "warmUp"
        case .speak(let sentence): return "speak \(sentence.text)"
        case .stop: return "stop"
        case .reset: return "reset"
        }
    }
}

private extension InterfaceCue {
    /// Every interface cue once.
    static let allForReview: [InterfaceCue] = [
        .gameStarted(firstPlayer: 0), .dartNeedsReview, .dartUndecided, .dartIgnored, .possibleMiss, .boardCleared, .undo,
        .correctionApplied, .shutter, .calibrationValidated, .calibrationLost, .buttonTap,
    ]
}
