import Foundation
import Testing
import DartCore
@testable import DartAudio

/// `AudioDirector` (ARCHITECTURE.md §7.4): what it sends to the effects, the voice and the haptics, with outputs
/// that record instead of playing and a clock driven by hand; then the real service, which must never trap,
/// with or without an audio output.
@MainActor
@Suite struct AudioDirectorTests {
    private let effects = AudioTestEffects()
    private let voice = AudioTestVoice()
    private let haptics = AudioTestHaptics()
    private let clock = AudioTestClock()

    private func makeDirector(_ change: (inout AudioSettings) -> Void = { _ in }) -> AudioDirector {
        var settings = AudioSettings()
        change(&settings)
        let effects = self.effects
        return AudioDirector(settings: settings, effects: { effects.receive($0) }, voice: voice, haptics: haptics,
                             schedule: clock.scheduler)
    }

    private func normal(_ fr: String, _ en: String) -> Announcement {
        Announcement(LocalizedText(fr: fr, en: en), priority: .normal)
    }

    private let players = [Player(name: "Léa"), Player(name: "Tom")]

    // MARK: - prepare

    @Test func prepare_configuresTheEngine_warmsTheVoice_wakesTheHaptics() {
        let director = makeDirector { $0.volume = 0.5; $0.playsInSilentMode = false; $0.callerLanguage = .en }
        #expect(effects.orders.isEmpty && voice.orders.isEmpty && haptics.prepared == 0)
        director.prepare()
        #expect(effects.orders == [.prepare(playsInSilentMode: false, volume: 0.5)])
        #expect(voice.orders == [.warmUp(language: .en, ducksOthers: true)])
        #expect(haptics.prepared == 1)
    }

    @Test func prepare_isIdempotent_andLetsTheEngineTryAgain() {
        let director = makeDirector()
        director.prepare()
        director.prepare()
        director.prepare()
        // The voice is warmed once; the engine gets every `prepare`, which retries a start that failed.
        #expect(voice.orders == [.warmUp(language: .fr, ducksOthers: true)])
        #expect(haptics.prepared == 1)
        #expect(effects.orders == Array(repeating: .prepare(playsInSilentMode: true, volume: 0.8), count: 3))
    }

    @Test func prepare_doesNotWarmAVoiceThatCannotBeHeard() {
        // A warm-up is a silent sentence, and a sentence lowers the user's music: not while the caller is off.
        let director = makeDirector { $0.callerEnabled = false }
        director.prepare()
        #expect(voice.orders.isEmpty && haptics.prepared == 1)
        director.settings.volume = 0.5
        #expect(voice.orders.isEmpty)
        director.settings.callerEnabled = true
        #expect(voice.orders == [.warmUp(language: .fr, ducksOthers: true)])
        // Once.
        director.settings.callerEnabled = false
        director.settings.callerEnabled = true
        director.prepare()
        #expect(voice.orders == [.warmUp(language: .fr, ducksOthers: true)])

        let muted = makeDirector { $0.isMuted = true; $0.callerLanguage = .en }
        muted.prepare()
        #expect(voice.orders.count == 1)
        muted.settings.isMuted = false
        #expect(voice.orders.last == .warmUp(language: .en, ducksOthers: true) && voice.orders.count == 2)
        // Before `prepare`, a change of settings warms nothing.
        let fresh = makeDirector { $0.callerEnabled = false }
        fresh.settings.callerEnabled = true
        #expect(voice.orders.count == 2)
    }

    @Test func play_beforePrepare_preparesFirst() {
        let director = makeDirector()
        director.play(.tick)
        #expect(effects.orders == [.prepare(playsInSilentMode: true, volume: 0.8), .play(.tick, after: 0)])
        #expect(voice.orders == [.warmUp(language: .fr, ducksOthers: true)])
        director.play(.tick)
        #expect(effects.orders.count == 3)
    }

    @Test func play_ofNothing_doesNothing_notEvenPrepare() {
        let director = makeDirector()
        director.play([])
        director.play([AudioCue()])
        #expect(effects.orders.isEmpty && voice.orders.isEmpty && haptics.played.isEmpty && clock.pending == 0)
    }

    // MARK: - play

    @Test func play_sendsEveryEffectAtOnce_withItsDelay() {
        let director = makeDirector()
        director.prepare()
        effects.forget()
        director.play([AudioCue(effect: .dartImpact), AudioCue(effect: .tick, delay: 0.12), AudioCue(effect: .tick, delay: 0.21),
                       AudioCue(effect: .lock, delay: 0.42)])
        #expect(effects.orders == [.play(.dartImpact, after: 0), .play(.tick, after: 0.12), .play(.tick, after: 0.21),
                                   .play(.lock, after: 0.42)])
        // Effects wait on the audio queue, not on the main thread: nothing was scheduled here.
        #expect(clock.pending == 0)
    }

    @Test func play_saysTheSentencesAndPlaysTheHaptics_atTheirDelay() {
        let director = makeDirector()
        director.play([
            AudioCue(effect: .dartImpact, announcement: Announcement(LocalizedText(verbatim: "5"), priority: .low), haptic: .light),
            AudioCue(effect: .eliminated, announcement: Announcement(LocalizedText(fr: "Tom est éliminé", en: "Tom is out"), priority: .high),
                     delay: 0.24),
            AudioCue(effect: .victory, haptic: .success, delay: 0.36),
            AudioCue(announcement: Announcement(LocalizedText(fr: "Léa gagne la partie", en: "Léa wins"), priority: .high), delay: 0.96),
        ])
        // "5" would be cut by "Tom est éliminé" a quarter of a second later: it is not started.
        #expect(voice.spoken.isEmpty && haptics.played == [.light])
        #expect(clock.pendingDelays == [0.24, 0.36, 0.96])
        clock.advance(by: 0.24)
        #expect(voice.spoken == ["Tom est éliminé"] && haptics.played == [.light])
        clock.advance(by: 0.12)
        #expect(haptics.played == [.light, .success])
        clock.advance(by: 0.59)
        #expect(voice.spoken == ["Tom est éliminé"])
        clock.advance(by: 0.02)
        #expect(voice.spoken == ["Tom est éliminé", "Léa gagne la partie"])
        #expect(voice.orders.suffix(2) == [.stop, .speak(voice.sentences[1])])
    }

    @Test func play_keepsTheCallOfTheWinningDart_whichHasTimeBeforeTheWinnerIsNamed() {
        let director = makeDirector()
        director.play(CueMapping.cues(
            for: [.dartRegistered(player: 0, hit: .double(20)), .checkout(player: 0, points: 40, darts: 1),
                  .gameFinished(reason: .victory)],
            context: CueContext(gameID: .x01, players: players, winners: [0])))
        #expect(effects.played == [.play(.dartImpact, after: 0), .play(.victory, after: 0.12)])
        #expect(voice.spoken == ["Double 20"])
        clock.advance(by: 0.72)
        #expect(voice.spoken == ["Double 20", "Léa gagne la partie"])
        #expect(haptics.played == [.success])
    }

    @Test func play_speaksTheLanguageOfTheCaller_notOfTheInterface() {
        let director = makeDirector { $0.callerLanguage = .en }
        director.play(CueMapping.cues(for: .gameStarted(firstPlayer: 0), context: CueContext(gameID: .x01, players: players)))
        #expect(voice.spoken == ["Léa to throw"])
        #expect(voice.sentences.first?.language == .en)
    }

    @Test func play_aMappedBatch_endToEnd() {
        // Third dart of a 180: the exclamation is said, "Triple 20" never starts, "180" is not said twice.
        let director = makeDirector()
        let cues = CueMapping.cues(
            for: [.dartRegistered(player: 0, hit: .treble(20)), .turnScored(player: 0, points: 180), .oneEighty(player: 0),
                  .turnCompleted(player: 0)],
            context: CueContext(gameID: .x01, players: players))
        director.play(cues)
        #expect(effects.played == [.play(.dartImpact, after: 0), .play(.fanfare, after: 0.12)])
        #expect(voice.spoken.isEmpty)
        clock.advance(by: 0.12)
        #expect(voice.spoken == ["Cent quatre-vingts !"] && voice.stops == 0)
        #expect(haptics.played == [.success])
    }

    @Test func play_twoBatches_theTotalFollowsTheDart_thenTheNextPlayer() {
        let director = makeDirector()
        let context = CueContext(gameID: .x01, players: players)
        director.play(CueMapping.cues(
            for: [.dartRegistered(player: 0, hit: .treble(20)), .turnScored(player: 0, points: 140), .highTurn(player: 0, points: 140),
                  .turnCompleted(player: 0)], context: context))
        director.play(CueMapping.cues(for: [.turnStarted(player: 1, round: 1)], context: context))
        #expect(voice.spoken == ["Triple 20"])
        voice.finishLast()
        #expect(voice.spoken == ["Triple 20", "140"])
        voice.finishLast()
        #expect(voice.spoken == ["Triple 20", "140", "Au tour de Tom"])
        #expect(voice.stops == 0)
    }

    @Test func playConveniences_goThroughTheSamePath() {
        let director: any SoundPlaying = makeDirector()
        director.play(.confirm)
        director.say(LocalizedText(fr: "À vérifier", en: "Please check"), priority: .high)
        #expect(effects.played == [.play(.confirm, after: 0)])
        #expect(voice.spoken == ["À vérifier"])
    }

    // MARK: - Settings filter at play time

    @Test func muted_playsNothing() {
        let director = makeDirector { $0.isMuted = true }
        director.play([AudioCue(effect: .fanfare, announcement: normal("Au tour de Léa", "Léa to throw"), haptic: .success),
                       AudioCue(effect: .tick, haptic: .light, delay: 0.3)])
        #expect(effects.orders.isEmpty && voice.orders.isEmpty && haptics.played.isEmpty && clock.pending == 0)
    }

    @Test func eachSwitch_removesItsOwnPart() {
        let cue = AudioCue(effect: .fanfare, announcement: normal("Au tour de Léa", "Léa to throw"), haptic: .success)

        let noEffects = makeDirector { $0.effectsEnabled = false }
        noEffects.play([cue])
        #expect(effects.played.isEmpty && voice.spoken == ["Au tour de Léa"] && haptics.played == [.success])
    }

    @Test func callerDisabled_playsEffectsAndHapticsOnly() {
        let director = makeDirector { $0.callerEnabled = false }
        director.play([AudioCue(effect: .fanfare, announcement: normal("Au tour de Léa", "Léa to throw"), haptic: .success)])
        #expect(effects.played == [.play(.fanfare, after: 0)] && voice.spoken.isEmpty && haptics.played == [.success])
    }

    @Test func hapticsDisabled_orUnsupported_playsNoHaptic() {
        let disabled = makeDirector { $0.hapticsEnabled = false }
        disabled.play([AudioCue(effect: .fanfare, haptic: .success)])
        #expect(effects.played == [.play(.fanfare, after: 0)] && haptics.played.isEmpty)

        haptics.isSupported = false
        let unsupported = makeDirector()
        #expect(!unsupported.supportsHaptics)
        unsupported.play([AudioCue(haptic: .failure), AudioCue(haptic: .light, delay: 0.2)])
        clock.advance(by: 1)
        #expect(haptics.played.isEmpty)
    }

    @Test func supportsHaptics_isWhatTheHardwareSays() {
        let director = makeDirector()
        #expect(director.supportsHaptics)
        haptics.isSupported = false
        #expect(!director.supportsHaptics)
    }

    @Test func settingsChangedDuringABatch_filterWhatIsStillToCome() {
        let director = makeDirector()
        director.play([AudioCue(announcement: normal("un", "one"), haptic: .light, delay: 0.2),
                       AudioCue(announcement: normal("deux", "two"), haptic: .medium, delay: 0.4)])
        director.settings.callerEnabled = false
        clock.advance(by: 0.2)
        #expect(voice.spoken.isEmpty && haptics.played == [.light])
        director.settings.callerEnabled = true
        director.settings.hapticsEnabled = false
        clock.advance(by: 0.2)
        #expect(voice.spoken == ["deux"] && haptics.played == [.light])
    }

    // MARK: - Settings applied immediately

    @Test func muting_stopsEverythingAtOnce() {
        let director = makeDirector()
        director.play([AudioCue(effect: .victory, announcement: normal("Léa gagne la partie", "Léa wins")),
                       AudioCue(announcement: normal("plus tard", "later"), haptic: .success, delay: 0.6)])
        effects.forget()
        director.settings.isMuted = true
        #expect(effects.orders == [.stopAll])
        #expect(voice.orders.last == .stop)
        clock.advance(by: 1)
        #expect(voice.spoken == ["Léa gagne la partie"] && haptics.played.isEmpty)
        // Unmuting plays again.
        director.settings.isMuted = false
        director.play(.tick)
        #expect(effects.orders.last == .play(.tick, after: 0))
    }

    @Test func disablingTheCaller_cutsTheVoice_disablingTheEffects_stopsThem() {
        let director = makeDirector()
        director.play([AudioCue(effect: .victory, announcement: normal("Léa gagne la partie", "Léa wins"))])
        effects.forget()
        director.settings.callerEnabled = false
        #expect(voice.orders.last == .stop && effects.orders.isEmpty)
        director.settings.effectsEnabled = false
        #expect(effects.orders == [.stopAll])
    }

    @Test func volumeAndSilentMode_reachTheEngine() {
        let director = makeDirector()
        director.prepare()
        effects.forget()
        director.settings.volume = 0.3
        #expect(effects.orders == [.configure(playsInSilentMode: true, volume: 0.3)])
        director.settings.playsInSilentMode = false
        #expect(effects.orders.last == .configure(playsInSilentMode: false, volume: 0.3))
        // Out-of-range volumes are brought back; a change that changes nothing sends nothing.
        director.settings.volume = 5
        #expect(effects.orders.last == .configure(playsInSilentMode: false, volume: 1))
        let count = effects.orders.count
        director.settings.volume = 9
        director.settings.callerLanguage = .en
        director.settings.ducksMusicWhileSpeaking = false
        let same = director.settings
        director.settings = same
        #expect(effects.orders.count == count)
    }

    @Test func voiceSettings_areReadWhenASentenceStarts() {
        let director = makeDirector()
        director.settings.callerLanguage = .en
        director.settings.volume = 0.4
        director.settings.ducksMusicWhileSpeaking = false
        director.play([AudioCue(announcement: normal("Au tour de Léa", "Léa to throw"))])
        #expect(voice.sentences.count == 1)
        #expect(voice.sentences.first.map { [$0.text, $0.language.rawValue] } == ["Léa to throw", "en"])
        #expect(voice.sentences.first?.volume == 0.4 && voice.sentences.first?.ducksOthers == false)
    }

    // MARK: - stopAll, setActive

    @Test func stopAll_stopsTheEffectsAndTheVoice_andDropsWhatWasStillToCome() {
        let director = makeDirector()
        director.play([AudioCue(effect: .victory, announcement: normal("Léa gagne la partie", "Léa wins")),
                       AudioCue(announcement: normal("plus tard", "later"), haptic: .success, delay: 0.6)])
        effects.forget()
        director.stopAll()
        #expect(effects.orders == [.stopAll] && voice.orders.last == .stop)
        clock.advance(by: 1)
        #expect(voice.spoken == ["Léa gagne la partie"] && haptics.played.isEmpty)
        // A batch played after `stopAll` is not affected by it.
        director.play([AudioCue(announcement: normal("ensuite", "then"), delay: 0.1)])
        clock.advance(by: 0.1)
        #expect(voice.spoken == ["Léa gagne la partie", "ensuite"])
    }

    @Test func leavingTheForeground_pausesTheEngine_cutsTheVoice_andPlaysNothing() {
        let director = makeDirector()
        director.prepare()
        director.play([AudioCue(announcement: normal("Au tour de Léa", "Léa to throw")),
                       AudioCue(announcement: normal("plus tard", "later"), haptic: .success, delay: 0.6)])
        effects.forget()
        director.setActive(false)
        #expect(effects.orders == [.setActive(false)] && voice.orders.last == .stop)
        clock.advance(by: 1)
        director.play([AudioCue(effect: .tick, announcement: normal("jamais", "never"), haptic: .light)])
        #expect(effects.orders == [.setActive(false)])
        #expect(voice.spoken == ["Au tour de Léa"] && haptics.played.isEmpty)
    }

    @Test func comingBack_restartsTheEngine_andPlaysAgain() {
        let director = makeDirector()
        director.prepare()
        director.setActive(false)
        effects.forget()
        director.setActive(true)
        #expect(effects.orders == [.setActive(true)])
        // Asked again while already active: the engine is told again, which is how a failed start is retried.
        director.setActive(true)
        #expect(effects.orders == [.setActive(true), .setActive(true)])
        director.play([AudioCue(effect: .tick, announcement: normal("Au tour de Tom", "Tom to throw"), haptic: .light)])
        #expect(effects.orders.last == .play(.tick, after: 0))
        #expect(voice.spoken == ["Au tour de Tom"] && haptics.played == [.light])
    }

    // MARK: - The real service

    /// Volume 0: the real engine and the real voice run, and nothing is heard on the machine that runs the tests.
    private var silent: AudioSettings {
        var settings = AudioSettings()
        settings.volume = 0
        return settings
    }

    @Test func realService_prepare_play_stopAll_doNotTrap_evenWithoutAnAudioOutput() async throws {
        let director = AudioDirector(settings: silent)
        #expect(director.settings == silent)
        director.prepare()
        director.prepare()
        let prepared = try #require(await director.effectsStatus())
        // Every effect is synthesised once, whatever the machine. The engine exists and runs when, and only
        // when, the machine has an audio output: without one nothing is built, and nothing traps.
        #expect(prepared.isPrepared && prepared.isActive && prepared.bufferCount == SoundEffect.allCases.count)
        #expect(prepared.isRunning == prepared.hasEngine)
        #expect(prepared.volume == 0)

        let context = CueContext(gameID: .x01, players: players, winners: [0])
        director.play(CueMapping.cues(
            for: [.dartRegistered(player: 0, hit: .treble(20)), .marksScored(player: 0, target: 20, count: 3),
                  .turnScored(player: 0, points: 60), .turnCompleted(player: 0)], context: context))
        for effect in SoundEffect.allCases {
            director.play(effect)
        }
        for haptic in HapticPattern.allCases {
            director.play([AudioCue(haptic: haptic)])
        }
        director.say(LocalizedText(fr: "Au tour de Léa", en: "Léa to throw"))
        director.say(LocalizedText(fr: "Bust", en: "Bust"), priority: .high)
        #expect(await director.effectsStatus() == prepared)
        director.stopAll()
        director.stopAll()
        // Stopping the sounds does not stop the engine: the service is still usable.
        #expect(await director.effectsStatus() == prepared)
        director.play(.tick)
        #expect(await director.effectsStatus() == prepared)
    }

    @Test func realService_backgroundAndForeground_pauseAndRestartTheEngine() async throws {
        let director = AudioDirector(settings: silent)
        // Before `prepare`: nothing to pause, nothing to restart, nothing built.
        director.setActive(false)
        director.setActive(true)
        director.stopAll()
        let idle = try #require(await director.effectsStatus())
        #expect(!idle.isPrepared && !idle.hasEngine && !idle.isRunning && idle.bufferCount == 0)

        director.play(.dartImpact)
        let playing = try #require(await director.effectsStatus())
        #expect(playing.isPrepared && playing.isRunning == playing.hasEngine)

        director.setActive(false)
        director.play(.fanfare)
        let background = try #require(await director.effectsStatus())
        #expect(!background.isActive && !background.isRunning && background.hasEngine == playing.hasEngine)

        director.setActive(true)
        director.play(.fanfare)
        let foreground = try #require(await director.effectsStatus())
        #expect(foreground == playing)
    }

    @Test func realService_settingsReachTheEngine_withoutTrapping() async throws {
        let director = AudioDirector(settings: silent)
        director.prepare()
        var changed = silent
        changed.playsInSilentMode = false
        changed.callerLanguage = .en
        changed.ducksMusicWhileSpeaking = false
        director.settings = changed
        director.say(LocalizedText(fr: "Au tour de Léa", en: "Léa to throw"))
        let restarted = try #require(await director.effectsStatus())
        // A new session category restarts the engine.
        #expect(restarted.isRunning == restarted.hasEngine && restarted.volume == 0)
        changed.isMuted = true
        director.settings = changed
        director.play(.victory)
        #expect(await director.effectsStatus() == restarted)
        #expect(director.settings == changed)
    }

    @Test func realService_onAMac_hasNoHaptics() {
        #if os(macOS)
        #expect(!AudioDirector(settings: silent).supportsHaptics)
        #endif
    }

    @Test func realService_canBeCreatedAndDropped_withoutEverPlaying() async throws {
        // AppEnvironment.live() builds one at launch: creating it touches no audio hardware.
        for _ in 0..<20 {
            _ = AudioDirector()
        }
        let director = AudioDirector(settings: silent)
        let status = try #require(await director.effectsStatus())
        #expect(!status.isPrepared && !status.hasEngine && status.bufferCount == 0)
    }

    @Test func realScheduler_waitsTheWholeSentenceTimeout_andNeverAnAbsurdDelay() {
        // The timeout of a sentence is longer than the longest cue delay: the real clock must not cut it short.
        #expect(ScoreCaller.sentenceTimeout > AudioCueFilter.maximumDelay)
        #expect(AudioDirector.sleepNanoseconds(for: ScoreCaller.sentenceTimeout) == 12_000_000_000)
        #expect(AudioDirector.sleepNanoseconds(for: 0.12) == 120_000_000)
        #expect(AudioDirector.sleepNanoseconds(for: AudioCueFilter.maximumDelay) == 10_000_000_000)
        // Nothing to wait for, or nothing sensible: at once, or the longest wait.
        for delay in [0, -0.5, -.infinity, .nan] {
            #expect(AudioDirector.sleepNanoseconds(for: delay) == 0, "\(delay)")
        }
        #expect(AudioDirector.sleepNanoseconds(for: .infinity) == 60_000_000_000)
        #expect(AudioDirector.sleepNanoseconds(for: 1e300) == 60_000_000_000)
    }

    @Test func engine_isNeitherBuiltNorStarted_onAnOutputWithoutChannelOrSampleRate() {
        // What a machine without audio output reports: connecting to such a format would raise an exception.
        #expect(!EffectsPlayer.canPlay(sampleRate: 0, channelCount: 0))
        #expect(!EffectsPlayer.canPlay(sampleRate: 0, channelCount: 2))
        #expect(!EffectsPlayer.canPlay(sampleRate: 44_100, channelCount: 0))
        #expect(!EffectsPlayer.canPlay(sampleRate: .nan, channelCount: 2))
        #expect(!EffectsPlayer.canPlay(sampleRate: -48_000, channelCount: 2))
        #expect(EffectsPlayer.canPlay(sampleRate: 44_100, channelCount: 1))
        #expect(EffectsPlayer.canPlay(sampleRate: 48_000, channelCount: 2))
        // The fixed format of the effects.
        #expect(EffectsPlayer.sampleRate == 44_100 && EffectsPlayer.voiceCount == 4)
    }
}
