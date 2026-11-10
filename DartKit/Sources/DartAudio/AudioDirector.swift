// DartAudio — the real sound service: the main-actor façade over the effects, the voice and the haptics
// (ARCHITECTURE.md §7.4).
import Foundation
import DartCore

/// Runs `action` on the main actor after `delay` seconds. The real one sleeps in a task; the tests pass one
/// that keeps the actions and fires them by hand.
typealias AudioScheduler = @MainActor (_ delay: TimeInterval, _ action: @escaping @MainActor () -> Void) -> Void

/// The real service: AVAudioEngine + player-node pool, AVSpeechSynthesizer, haptics, audio session.
///
/// Threads (ARCHITECTURE.md §11): this façade, the voice and the haptics live on the main actor; the engine and
/// the audio session live on the private serial queue of `EffectsPlayer`, reached through one stream of
/// commands. No method blocks, waits or throws: what cannot be played is skipped.
@MainActor
public final class AudioDirector: SoundPlaying {
    public var settings: AudioSettings {
        didSet { settingsChanged(from: oldValue) }
    }

    public var supportsHaptics: Bool { haptics.isSupported }

    /// Sends one command to the effects player.
    private let effects: @MainActor (EffectsPlayer.Command) -> Void
    /// The stream behind `effects` in the real service; ended when the director goes away.
    private let mailbox: AsyncStream<EffectsPlayer.Command>.Continuation?
    private let caller: ScoreCaller
    private let haptics: any HapticsPlaying
    private let schedule: AudioScheduler
    /// Interruptions and media-server resets of the audio session (iPhone and iPad).
    private var sessionObservation: AudioNotificationObservation?

    private var isPrepared = false
    /// The voice is warmed once, and only when the caller can be heard: a warm-up is a (silent) sentence, and a
    /// sentence lowers the user's music.
    private var isVoiceWarm = false
    private var isActive = true
    /// Bumped by `stopAll` and by leaving the foreground: what an older batch still had to play is dropped.
    private var generation = 0

    public init(settings: AudioSettings = AudioSettings()) {
        let (commands, mailbox) = AsyncStream<EffectsPlayer.Command>.makeStream()
        let player = EffectsPlayer(mailbox: mailbox)
        // The player handles the commands on its own serial queue until the stream ends (`deinit`).
        Task { await player.run(commands) }
        let schedule: AudioScheduler = { delay, action in
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: AudioDirector.sleepNanoseconds(for: delay))
                action()
            }
        }
        self.settings = settings
        self.effects = { mailbox.yield($0) }
        self.mailbox = mailbox
        self.caller = ScoreCaller(settings: settings, voice: ScoreCallerSynthesizer(), schedule: schedule)
        self.haptics = HapticsPlayer()
        self.schedule = schedule
    }

    /// For the tests: the same director over outputs that record what they are asked, and a clock driven by hand.
    init(settings: AudioSettings, effects: @escaping @MainActor (EffectsPlayer.Command) -> Void,
         voice: any ScoreCallerVoice, haptics: any HapticsPlaying, schedule: @escaping AudioScheduler) {
        self.settings = settings
        self.effects = effects
        self.mailbox = nil
        self.caller = ScoreCaller(settings: settings, voice: voice, schedule: schedule)
        self.haptics = haptics
        self.schedule = schedule
    }

    deinit {
        mailbox?.finish()
    }

    public func prepare() {
        // Sent every time: the player's own `prepare` is idempotent, and it retries an engine that did not start.
        effects(.prepare(engineConfiguration))
        guard !isPrepared else { return }
        isPrepared = true
        warmVoiceIfHeard()
        haptics.prepare()
        if mailbox != nil {
            sessionObservation = AudioSessionController.observe { [weak self, mailbox] event in
                // Back to the audio queue for the engine; the voice is rebuilt on the main thread.
                mailbox?.yield(.session(event))
                if event == .mediaServicesWereReset {
                    Task { @MainActor [weak self] in self?.caller.reset() }
                }
            }
        }
    }

    public func play(_ cues: [AudioCue]) {
        guard isActive else { return }
        let playable = AudioCueFilter.withoutSentencesAboutToBeCut(
            AudioCueFilter.playable(cues, settings: settings, supportsHaptics: supportsHaptics))
        guard !playable.isEmpty else { return }
        if !isPrepared { prepare() }
        // Effects go to the audio queue at once, each with its delay: their rhythm does not depend on how
        // busy the main thread is.
        for cue in playable {
            if let effect = cue.effect {
                effects(.play(effect, after: cue.delay))
            }
        }
        // Sentences and haptics belong to the main thread.
        let generation = self.generation
        for moment in AudioCueFilter.timeline(playable) {
            guard moment.cues.contains(where: { $0.announcement != nil || $0.haptic != nil }) else { continue }
            if moment.delay <= 0 {
                perform(moment)
            } else {
                schedule(moment.delay) { [weak self] in
                    guard let self, self.generation == generation, self.isActive else { return }
                    self.perform(moment)
                }
            }
        }
    }

    public func stopAll() {
        generation += 1
        effects(.stopAll)
        caller.stopAll()
    }

    public func setActive(_ active: Bool) {
        isActive = active
        if !active {
            generation += 1
            caller.stopAll()
        }
        // Sent every time: `setActive(true)` is also how an engine that could not start is tried again.
        effects(.setActive(active))
    }

    /// The real scheduler's wait for `delay` seconds. It serves the cues, whose delays the filter already keeps
    /// within `AudioCueFilter.maximumDelay`, and the timeout of a sentence (`ScoreCaller.sentenceTimeout`), which
    /// is longer: so it honours any finite delay up to `longestWait`. Zero for a delay that is negative or not a
    /// number.
    nonisolated static func sleepNanoseconds(for delay: TimeInterval) -> UInt64 {
        guard delay > 0 else { return 0 }
        return UInt64(min(delay, longestWait) * 1_000_000_000)
    }

    /// The longest wait of the real scheduler, in seconds.
    nonisolated static let longestWait: TimeInterval = 60

    /// Where the effects player stands once it has handled every command sent so far; nil over the recording
    /// outputs of the tests. For the tests of the real service.
    func effectsStatus() async -> EffectsPlayer.Status? {
        guard mailbox != nil else { return nil }
        return await withCheckedContinuation { continuation in
            effects(.report(continuation))
        }
    }

    // MARK: - Private

    private var engineConfiguration: EffectsPlayer.Configuration {
        EffectsPlayer.Configuration(playsInSilentMode: settings.playsInSilentMode,
                                    volume: AudioCueFilter.playableVolume(settings.volume))
    }

    private func warmVoiceIfHeard() {
        guard isPrepared, !isVoiceWarm, settings.callerEnabled, !settings.isMuted else { return }
        isVoiceWarm = true
        caller.prepare()
    }

    /// The sentences and the haptics of one instant. The settings are read again: they may have changed since
    /// the batch started.
    private func perform(_ moment: AudioCueFilter.Moment) {
        let cues = AudioCueFilter.playable(moment.cues, settings: settings, supportsHaptics: supportsHaptics)
        let sentences = cues.compactMap(\.announcement)
        if !sentences.isEmpty {
            caller.say(sentences)
        }
        for cue in cues {
            if let haptic = cue.haptic {
                haptics.play(haptic)
            }
        }
    }

    /// Settings apply immediately: what was just switched off stops now, and the engine follows the session
    /// category and the volume.
    private func settingsChanged(from old: AudioSettings) {
        guard settings != old else { return }
        caller.settings = settings
        warmVoiceIfHeard()
        if settings.isMuted && !old.isMuted {
            stopAll()
        } else {
            if !settings.effectsEnabled && old.effectsEnabled { effects(.stopAll) }
            if !settings.callerEnabled && old.callerEnabled { caller.stopAll() }
        }
        let playsInSilentModeChanged = settings.playsInSilentMode != old.playsInSilentMode
        let volumeChanged = AudioCueFilter.playableVolume(settings.volume) != AudioCueFilter.playableVolume(old.volume)
        if playsInSilentModeChanged || volumeChanged {
            effects(.configure(engineConfiguration))
        }
    }
}
