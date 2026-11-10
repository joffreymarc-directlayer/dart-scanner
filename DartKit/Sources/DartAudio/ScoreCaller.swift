// DartAudio — the spoken score caller (ARCHITECTURE.md §7.5). No `#if` in this file: the one setting of the voice
// that macOS does not have goes through `AudioSessionController.setSpeechUsesApplicationSession(_:on:)`.
import Foundation
import AVFoundation
import DartCore

/// What `ScoreCaller` asks of a speech engine. Main thread only. The real one is `ScoreCallerSynthesizer`; the
/// tests pass one that records what it is asked.
@MainActor
protocol ScoreCallerVoice: AnyObject {
    /// Called when the sentence `id` is over: said to the end, or cut by `stop()`.
    var onEnd: ((Int) -> Void)? { get set }
    /// Builds the synthesiser, says one silent space (the first sentence is slow otherwise) and starts looking
    /// for the best voice of `language`. Idempotent.
    func warmUp(language: AppLanguage, ducksOthers: Bool)
    /// Says `text` after whatever is still being said. `ducksOthers` lowers the other apps' audio for the
    /// length of the sentence.
    func speak(_ text: String, id: Int, language: AppLanguage, volume: Float, ducksOthers: Bool)
    /// Cuts everything being said, at once.
    func stop()
    /// Throws the synthesiser away; the next sentence builds a new one.
    func reset()
}

/// Says the announcements, one at a time, by the priority rules of `ScoreCallerQueue`.
@MainActor
final class ScoreCaller {
    /// A sentence whose end was not reported after this long is given up, so that a speech engine that went
    /// silent (no voice installed, speech service down) never blocks the sentences that follow.
    static let sentenceTimeout: TimeInterval = 12

    /// Language, volume and ducking are read when a sentence starts.
    var settings: AudioSettings

    private var queue = ScoreCallerQueue()
    private let voice: any ScoreCallerVoice
    private let schedule: AudioScheduler
    /// The sentence handed to the voice whose end has not been reported.
    private var spokenID: Int?

    init(settings: AudioSettings, voice: any ScoreCallerVoice, schedule: @escaping AudioScheduler) {
        self.settings = settings
        self.voice = voice
        self.schedule = schedule
        voice.onEnd = { [weak self] id in self?.sentenceEnded(id) }
    }

    func prepare() {
        voice.warmUp(language: settings.callerLanguage, ducksOthers: settings.ducksMusicWhileSpeaking)
    }

    /// The sentences of one instant, in order. They are all weighed before the voice is touched: a sentence
    /// replaced within the same call is never started.
    func say(_ announcements: [Announcement]) {
        for announcement in announcements {
            queue.add(announcement)
        }
        speakCurrent()
    }

    /// Cuts the sentence being said and forgets the ones that wait.
    func stopAll() {
        queue.removeAll()
        speakCurrent()
    }

    /// The media services were reset: the synthesiser is rebuilt at the next sentence.
    func reset() {
        queue.removeAll()
        spokenID = nil
        voice.reset()
    }

    /// Makes the voice say `queue.current`, and nothing else.
    private func speakCurrent() {
        guard queue.current?.id != spokenID else { return }
        if spokenID != nil { voice.stop() }
        spokenID = nil
        while let entry = queue.current {
            let text = entry.announcement.text[settings.callerLanguage].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else {
                // Nothing to say in this language: the sentence is over before it starts.
                queue.finish(entry.id)
                continue
            }
            let id = entry.id
            spokenID = id
            voice.speak(text, id: id, language: settings.callerLanguage,
                        volume: AudioCueFilter.playableVolume(settings.volume),
                        ducksOthers: settings.ducksMusicWhileSpeaking)
            schedule(Self.sentenceTimeout) { [weak self] in self?.sentenceTimedOut(id) }
            return
        }
    }

    private func sentenceEnded(_ id: Int) {
        guard id == spokenID else { return }
        spokenID = nil
        queue.finish(id)
        speakCurrent()
    }

    private func sentenceTimedOut(_ id: Int) {
        guard id == spokenID else { return }
        voice.stop()
        sentenceEnded(id)
    }
}

// MARK: - Choice of the voice

/// Which installed voice speaks a language (ARCHITECTURE.md §7.5). The choice itself is a pure function.
enum ScoreCallerVoiceChoice {
    /// What the choice needs to know about one installed voice.
    struct Candidate: Hashable, Sendable {
        var identifier: String
        /// BCP 47 tag: "fr-FR", "en-US".
        var language: String
        /// 1 default, 2 enhanced, 3 premium: the raw values of `AVSpeechSynthesisVoiceQuality`.
        var quality: Int
        var isNovelty: Bool = false
        var isPersonal: Bool = false
    }

    /// The identifier of the voice to use for `languageCode`, nil when no installed voice fits.
    ///
    /// Novelty and personal voices are never chosen. Among the voices of the exact language (or, when there is
    /// none, of the same language in another region), the best quality wins: premium, then enhanced, then
    /// default. At equal quality the system's own default voice is kept, else the first identifier in
    /// alphabetical order, so that the choice never depends on the order of the list.
    static func preferred(among candidates: [Candidate], languageCode: String, systemDefault: String?) -> String? {
        let usable = candidates.filter { !$0.isNovelty && !$0.isPersonal }
        let wanted = normalized(languageCode)
        var matching = usable.filter { normalized($0.language) == wanted }
        if matching.isEmpty {
            let family = wanted.split(separator: "-").first.map(String.init) ?? wanted
            matching = usable.filter { normalized($0.language).split(separator: "-").first.map(String.init) == family }
        }
        guard let best = matching.map(\.quality).max() else { return nil }
        let finalists = matching.filter { $0.quality == best }.map(\.identifier).sorted()
        if let systemDefault, finalists.contains(systemDefault) { return systemDefault }
        return finalists.first
    }

    /// The best installed voice for `languageCode`. Asks the system for its voices, which is slow the first
    /// time: call it off the main thread.
    static func bestInstalledVoice(for languageCode: String) -> AVSpeechSynthesisVoice? {
        let installed = AVSpeechSynthesisVoice.speechVoices()
        let candidates = installed.map { voice in
            Candidate(identifier: voice.identifier, language: voice.language, quality: voice.quality.rawValue,
                      isNovelty: voice.voiceTraits.contains(.isNoveltyVoice),
                      isPersonal: voice.voiceTraits.contains(.isPersonalVoice))
        }
        let systemDefault = AVSpeechSynthesisVoice(language: languageCode)?.identifier
        guard let identifier = preferred(among: candidates, languageCode: languageCode, systemDefault: systemDefault) else {
            return nil
        }
        return installed.first { $0.identifier == identifier }
    }

    /// "fr_FR" and "FR-fr" are "fr-fr".
    private static func normalized(_ languageCode: String) -> String {
        languageCode.replacingOccurrences(of: "_", with: "-").lowercased()
    }
}

// MARK: - AVSpeechSynthesizer

/// The real voice: one `AVSpeechSynthesizer`, kept here (the system does not retain it), and a fresh
/// `AVSpeechUtterance` per sentence.
@MainActor
final class ScoreCallerSynthesizer: ScoreCallerVoice {
    var onEnd: ((Int) -> Void)?

    private var synthesizer: AVSpeechSynthesizer?
    private var delegate: ScoreCallerSpeechDelegate?
    /// Last value given to `usesApplicationAudioSession`, nil for a synthesiser that has not been told yet.
    private var usesApplicationSession: Bool?
    /// The utterances handed to the synthesiser whose end has not been reported, with the sentence they carry
    /// (nil for the warm-up). Keeping them alive keeps their identity unique until then.
    private var live: [ObjectIdentifier: (utterance: AVSpeechUtterance, id: Int?)] = [:]
    /// The best voice found for each language. Until the search answers, the system's default voice speaks.
    private var voices: [AppLanguage: AVSpeechSynthesisVoice] = [:]
    private var requestedVoices: Set<AppLanguage> = []
    /// Bumped when the installed voices change: an answer of an older search is ignored.
    private var voiceGeneration = 0
    private var voicesObservation: AudioNotificationObservation?

    func warmUp(language: AppLanguage, ducksOthers: Bool) {
        guard synthesizer == nil else { return }
        let synthesizer = readySynthesizer(ducksOthers: ducksOthers)
        let utterance = AVSpeechUtterance(string: " ")
        utterance.volume = 0
        live[ObjectIdentifier(utterance)] = (utterance, nil)
        synthesizer.speak(utterance)
        requestVoice(for: language)
    }

    func speak(_ text: String, id: Int, language: AppLanguage, volume: Float, ducksOthers: Bool) {
        let synthesizer = readySynthesizer(ducksOthers: ducksOthers)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice(for: language)
        utterance.volume = volume
        live[ObjectIdentifier(utterance)] = (utterance, id)
        synthesizer.speak(utterance)
    }

    func stop() {
        synthesizer?.stopSpeaking(at: .immediate)
    }

    func reset() {
        synthesizer?.delegate = nil
        synthesizer = nil
        delegate = nil
        usesApplicationSession = nil
        live.removeAll()
    }

    /// The synthesiser, built at the first need, with the ducking asked for.
    private func readySynthesizer(ducksOthers: Bool) -> AVSpeechSynthesizer {
        let synthesizer = self.synthesizer ?? makeSynthesizer()
        // With its own, system-managed session the voice lowers the other apps' audio for the length of the
        // sentence only. The category of the application is never touched around a sentence.
        if usesApplicationSession != !ducksOthers {
            usesApplicationSession = !ducksOthers
            AudioSessionController.setSpeechUsesApplicationSession(!ducksOthers, on: synthesizer)
        }
        return synthesizer
    }

    private func makeSynthesizer() -> AVSpeechSynthesizer {
        let synthesizer = AVSpeechSynthesizer()
        let delegate = ScoreCallerSpeechDelegate { [weak self] utterance in
            Task { @MainActor [weak self] in self?.utteranceEnded(utterance) }
        }
        synthesizer.delegate = delegate
        self.delegate = delegate
        self.synthesizer = synthesizer
        if voicesObservation == nil {
            let token = NotificationCenter.default.addObserver(
                forName: AVSpeechSynthesizer.availableVoicesDidChangeNotification, object: nil, queue: nil
            ) { [weak self] _ in
                Task { @MainActor [weak self] in self?.installedVoicesChanged() }
            }
            voicesObservation = AudioNotificationObservation([token])
        }
        return synthesizer
    }

    private func utteranceEnded(_ utterance: ObjectIdentifier) {
        guard let entry = live.removeValue(forKey: utterance), let id = entry.id else { return }
        onEnd?(id)
    }

    // MARK: Voice

    private func voice(for language: AppLanguage) -> AVSpeechSynthesisVoice? {
        if let voice = voices[language] { return voice }
        requestVoice(for: language)
        return AVSpeechSynthesisVoice(language: language.voiceLanguageCode)
    }

    /// Looks for the best installed voice of `language` off the main thread: listing the voices is slow.
    private func requestVoice(for language: AppLanguage) {
        guard requestedVoices.insert(language).inserted else { return }
        let generation = voiceGeneration
        let languageCode = language.voiceLanguageCode
        Task.detached(priority: .utility) { [weak self] in
            let voice = ScoreCallerVoiceChoice.bestInstalledVoice(for: languageCode)
            await self?.install(voice, for: language, generation: generation)
        }
    }

    private func install(_ voice: AVSpeechSynthesisVoice?, for language: AppLanguage, generation: Int) {
        guard generation == voiceGeneration, let voice else { return }
        voices[language] = voice
    }

    /// A voice was downloaded or removed: the choice is made again at the next sentence.
    private func installedVoicesChanged() {
        voiceGeneration += 1
        voices.removeAll()
        requestedVoices.removeAll()
    }
}

/// Reports the end of every utterance, finished or cancelled, by its identity. The system calls it on a thread
/// of its choice: it only forwards.
private final class ScoreCallerSpeechDelegate: NSObject, AVSpeechSynthesizerDelegate {
    private let utteranceEnded: @Sendable (ObjectIdentifier) -> Void

    init(utteranceEnded: @escaping @Sendable (ObjectIdentifier) -> Void) {
        self.utteranceEnded = utteranceEnded
        super.init()
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        utteranceEnded(ObjectIdentifier(utterance))
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        utteranceEnded(ObjectIdentifier(utterance))
    }
}
