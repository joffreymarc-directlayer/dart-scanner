import Foundation
import Testing
import DartCore
@testable import DartAudio

/// The score caller (ARCHITECTURE.md §7.5): the priority rules as a value, then the caller that applies them
/// to a speech engine, then the choice of the voice. No speech is produced: the engine is a recording stand-in.
@Suite struct ScoreCallerTests {
    private static func low(_ text: String) -> Announcement { Announcement(LocalizedText(verbatim: text), priority: .low) }
    private static func normal(_ text: String) -> Announcement { Announcement(LocalizedText(verbatim: text), priority: .normal) }
    private static func high(_ text: String) -> Announcement { Announcement(LocalizedText(verbatim: text), priority: .high) }

    private func texts(_ queue: ScoreCallerQueue) -> (current: String?, waiting: [String]) {
        (queue.current?.announcement.text.fr, queue.waiting.map(\.announcement.text.fr))
    }

    // MARK: - Priority rules (the table of §7.5)

    @Test func queue_startsEmpty_andSpeaksTheFirstSentenceWhateverItsPriority() {
        for sentence in [Self.low("a"), Self.normal("a"), Self.high("a")] {
            var queue = ScoreCallerQueue()
            #expect(queue.isEmpty && queue.current == nil && queue.waiting.isEmpty)
            queue.add(sentence)
            #expect(queue.current?.announcement == sentence && queue.waiting.isEmpty && !queue.isEmpty)
        }
    }

    @Test func low_isDropped_whileANormalOrHighSentenceIsSpoken() {
        for busy in [Self.normal("140"), Self.high("Bust")] {
            var queue = ScoreCallerQueue()
            queue.add(busy)
            queue.add(Self.low("Triple 20"))
            #expect(queue.current?.announcement == busy && queue.waiting.isEmpty)
        }
    }

    @Test func low_isDropped_whileANormalSentenceWaits() {
        var queue = ScoreCallerQueue()
        queue.add(Self.low("Triple 20"))
        queue.add(Self.normal("140"))
        queue.add(Self.low("Triple 19"))
        #expect(texts(queue).current == "Triple 20" && texts(queue).waiting == ["140"])
    }

    @Test func low_replacesTheLowSentenceBeingSpoken() {
        // "If the next dart arrives during « Triple 20 », its sentence replaces it."
        var queue = ScoreCallerQueue()
        queue.add(Self.low("Triple 20"))
        let first = queue.current
        queue.add(Self.low("Triple 19"))
        #expect(texts(queue).current == "Triple 19" && queue.waiting.isEmpty)
        #expect(queue.current?.id != first?.id)
    }

    @Test func normal_queuesBehindTheSentenceBeingSpoken() {
        // "On a third dart, « Triple 20 » (low) is said, then « 140 » (normal) follows."
        var queue = ScoreCallerQueue()
        queue.add(Self.low("Triple 20"))
        queue.add(Self.normal("140"))
        #expect(texts(queue).current == "Triple 20" && texts(queue).waiting == ["140"])
        queue.add(Self.normal("Au tour de Tom"))
        #expect(texts(queue).current == "Triple 20" && texts(queue).waiting == ["140", "Au tour de Tom"])
        // Behind a normal or a high sentence too.
        var busy = ScoreCallerQueue()
        busy.add(Self.high("Bust"))
        busy.add(Self.normal("Au tour de Tom"))
        #expect(texts(busy).current == "Bust" && texts(busy).waiting == ["Au tour de Tom"])
    }

    @Test func high_interruptsEverything_andEmptiesTheQueue() {
        var queue = ScoreCallerQueue()
        queue.add(Self.low("Triple 20"))
        queue.add(Self.normal("140"))
        queue.add(Self.normal("Au tour de Tom"))
        let interrupted = queue.current
        queue.add(Self.high("Cent quatre-vingts !"))
        #expect(texts(queue).current == "Cent quatre-vingts !" && queue.waiting.isEmpty)
        #expect(queue.current?.id != interrupted?.id)
        // A high sentence interrupts a high sentence as well.
        queue.add(Self.high("Léa gagne la partie"))
        #expect(texts(queue).current == "Léa gagne la partie" && queue.waiting.isEmpty)
    }

    @Test func finish_movesToTheNextSentence_inOrder() throws {
        var queue = ScoreCallerQueue()
        queue.add(Self.low("Triple 20"))
        queue.add(Self.normal("140"))
        queue.add(Self.normal("Au tour de Tom"))
        queue.finish(try #require(queue.current?.id))
        #expect(texts(queue).current == "140" && texts(queue).waiting == ["Au tour de Tom"])
        queue.finish(try #require(queue.current?.id))
        #expect(texts(queue).current == "Au tour de Tom" && queue.waiting.isEmpty)
        queue.finish(try #require(queue.current?.id))
        #expect(queue.isEmpty)
    }

    @Test func finish_ofASentenceThatIsNoLongerCurrent_changesNothing() throws {
        var queue = ScoreCallerQueue()
        queue.add(Self.low("Triple 20"))
        let replaced = try #require(queue.current?.id)
        queue.add(Self.high("Bust"))
        queue.add(Self.normal("Au tour de Tom"))
        // The late report of the interrupted sentence must not skip "Bust".
        queue.finish(replaced)
        #expect(texts(queue).current == "Bust" && texts(queue).waiting == ["Au tour de Tom"])
        queue.finish(-1)
        queue.finish(Int.max)
        #expect(texts(queue).current == "Bust")
        var empty = ScoreCallerQueue()
        empty.finish(1)
        #expect(empty.isEmpty)
    }

    @Test func removeAll_forgetsEverything() {
        var queue = ScoreCallerQueue()
        queue.add(Self.normal("140"))
        queue.add(Self.normal("Au tour de Tom"))
        queue.removeAll()
        #expect(queue.isEmpty)
        queue.add(Self.low("5"))
        #expect(texts(queue).current == "5")
    }

    @Test func equalSentences_stayDistinct() throws {
        var queue = ScoreCallerQueue()
        queue.add(Self.normal("Au tour de Tom"))
        queue.add(Self.normal("Au tour de Tom"))
        let first = try #require(queue.current?.id)
        #expect(queue.waiting.count == 1 && queue.waiting[0].id != first)
        queue.finish(first)
        #expect(queue.current != nil && queue.current?.id != first && queue.waiting.isEmpty)
    }

    @Test func waitingSentences_areCapped_theOldestGoesFirst() {
        var queue = ScoreCallerQueue()
        queue.add(Self.normal("spoken"))
        for index in 1...7 {
            queue.add(Self.normal("\(index)"))
        }
        #expect(ScoreCallerQueue.capacity == 4)
        #expect(texts(queue).current == "spoken" && texts(queue).waiting == ["4", "5", "6", "7"])
    }

    @Test func randomSequences_keepTheInvariantsOfTheTable() {
        var random = SeededRandom(seed: 75)
        var queue = ScoreCallerQueue()
        var seen: Set<Int> = []
        for step in 0..<2_000 {
            let before = queue
            switch random.nextInt(below: 5) {
            case 0:
                queue.add(Self.low("low \(step)"))
                // A low sentence is spoken at once or dropped: it never waits.
                let spoken = queue.current?.announcement.text.fr == "low \(step)"
                let busy = (before.current?.announcement.priority ?? .low) > .low || !before.waiting.isEmpty
                #expect(spoken == !busy)
                if !spoken { #expect(queue.current == before.current && queue.waiting == before.waiting) }
            case 1:
                queue.add(Self.normal("normal \(step)"))
                if before.current == nil {
                    #expect(queue.current?.announcement.text.fr == "normal \(step)")
                } else {
                    #expect(queue.current == before.current && queue.waiting.last?.announcement.text.fr == "normal \(step)")
                }
            case 2:
                queue.add(Self.high("high \(step)"))
                #expect(queue.current?.announcement.text.fr == "high \(step)" && queue.waiting.isEmpty)
            case 3:
                if let current = queue.current { queue.finish(current.id) }
                #expect(queue.current == before.waiting.first && queue.waiting == Array(before.waiting.dropFirst()))
            default:
                queue.finish(random.nextInt(below: 50))
            }
            // Nothing waits behind silence; no low sentence waits; ids are never reused.
            #expect(queue.current != nil || queue.waiting.isEmpty)
            #expect(queue.waiting.allSatisfy { $0.announcement.priority == .normal })
            #expect(queue.waiting.count <= ScoreCallerQueue.capacity)
            if let current = queue.current, current != before.current, !before.waiting.contains(current) {
                #expect(seen.insert(current.id).inserted)
            }
        }
    }

    // MARK: - The caller and its voice

    @MainActor private func makeCaller(_ change: (inout AudioSettings) -> Void = { _ in })
        -> (caller: ScoreCaller, voice: AudioTestVoice, clock: AudioTestClock) {
        var settings = AudioSettings()
        change(&settings)
        let voice = AudioTestVoice()
        let clock = AudioTestClock()
        return (ScoreCaller(settings: settings, voice: voice, schedule: clock.scheduler), voice, clock)
    }

    @MainActor @Test func caller_prepare_warmsTheVoice_withTheLanguageAndTheDucking() {
        let (caller, voice, _) = makeCaller { $0.callerLanguage = .en; $0.ducksMusicWhileSpeaking = false }
        caller.prepare()
        #expect(voice.orders == [.warmUp(language: .en, ducksOthers: false)])
    }

    @MainActor @Test func caller_saysTheTextOfTheCallerLanguage_atTheVolumeOfTheSettings() {
        let sentence = Announcement(LocalizedText(fr: "Au tour de Léa", en: "Léa to throw"))
        let (french, frenchVoice, _) = makeCaller()
        french.say([sentence])
        #expect(frenchVoice.sentences == [
            AudioTestVoice.Sentence(text: "Au tour de Léa", id: frenchVoice.sentences[0].id, language: .fr, volume: 0.8, ducksOthers: true),
        ])
        let (english, englishVoice, _) = makeCaller { $0.callerLanguage = .en; $0.volume = 0.25; $0.ducksMusicWhileSpeaking = false }
        english.say([sentence])
        #expect(englishVoice.spoken == ["Léa to throw"])
        #expect(englishVoice.sentences[0].language == .en && englishVoice.sentences[0].volume == 0.25)
        #expect(!englishVoice.sentences[0].ducksOthers)
    }

    @MainActor @Test func caller_thirdDart_saysTheDartThenTheTotal() {
        let (caller, voice, _) = makeCaller()
        caller.say([Self.low("Triple 20"), Self.normal("140")])
        #expect(voice.spoken == ["Triple 20"] && voice.stops == 0)
        voice.finishLast()
        #expect(voice.spoken == ["Triple 20", "140"] && voice.stops == 0)
        voice.finishLast()
        #expect(voice.spoken == ["Triple 20", "140"])
    }

    @MainActor @Test func caller_nextDartDuringTheCall_replacesIt() {
        let (caller, voice, _) = makeCaller()
        caller.say([Self.low("Triple 20")])
        caller.say([Self.low("Triple 19")])
        #expect(voice.orders.map(orderName) == ["speak Triple 20", "stop", "speak Triple 19"])
    }

    @MainActor @Test func caller_highSentence_cutsTheVoice_andDropsWhatWaited() {
        let (caller, voice, _) = makeCaller()
        caller.say([Self.normal("140"), Self.normal("Au tour de Tom")])
        caller.say([Self.high("Calibrage perdu")])
        #expect(voice.orders.map(orderName) == ["speak 140", "stop", "speak Calibrage perdu"])
        voice.finishLast()
        // "Au tour de Tom" was dropped by the high sentence.
        #expect(voice.spoken == ["140", "Calibrage perdu"])
    }

    @MainActor @Test func caller_sentenceReplacedInsideOneCall_isNeverStarted() {
        // A 180 on the third dart: "Triple 20" (low) and the exclamation (high) arrive together.
        let (caller, voice, _) = makeCaller()
        caller.say([Self.low("Triple 20"), Self.high("Cent quatre-vingts !")])
        #expect(voice.orders.map(orderName) == ["speak Cent quatre-vingts !"])
    }

    @MainActor @Test func caller_lowSentence_isDroppedWhileANormalOneIsSpoken() {
        let (caller, voice, _) = makeCaller()
        caller.say([Self.normal("Au tour de Tom")])
        caller.say([Self.low("Triple 20")])
        #expect(voice.spoken == ["Au tour de Tom"] && voice.stops == 0)
        voice.finishLast()
        #expect(voice.spoken == ["Au tour de Tom"])
    }

    @MainActor @Test func caller_lateReportOfACutSentence_doesNotSkipTheNewOne() {
        let (caller, voice, _) = makeCaller()
        caller.say([Self.low("Triple 20")])
        caller.say([Self.high("Bust"), Self.normal("Au tour de Tom")])
        // The engine reports the end of the sentence it was told to cut, after the new one started.
        voice.finish(at: 0)
        #expect(voice.spoken == ["Triple 20", "Bust"])
        voice.finish(at: 1)
        #expect(voice.spoken == ["Triple 20", "Bust", "Au tour de Tom"])
        // A duplicated report changes nothing either.
        voice.finish(at: 1)
        #expect(voice.spoken == ["Triple 20", "Bust", "Au tour de Tom"])
    }

    @MainActor @Test func caller_stopAll_cutsTheVoice_andForgetsTheQueue() {
        let (caller, voice, _) = makeCaller()
        caller.say([Self.normal("140"), Self.normal("Au tour de Tom")])
        caller.stopAll()
        #expect(voice.orders.map(orderName) == ["speak 140", "stop"])
        voice.finishLast()
        #expect(voice.spoken == ["140"])
        // Stopping when nothing is said does not touch the voice.
        caller.stopAll()
        #expect(voice.stops == 1)
        // And the caller speaks again afterwards.
        caller.say([Self.normal("Au tour de Léa")])
        #expect(voice.spoken == ["140", "Au tour de Léa"])
    }

    @MainActor @Test func caller_sentenceWithoutTextInTheLanguage_isSkipped() {
        let (caller, voice, _) = makeCaller()
        let onlyEnglish = Announcement(LocalizedText(fr: "  ", en: "Hello"))
        caller.say([onlyEnglish, Self.normal("Au tour de Tom")])
        #expect(voice.spoken == ["Au tour de Tom"])
        caller.say([Announcement(LocalizedText(verbatim: ""), priority: .high)])
        #expect(voice.orders.map(orderName) == ["speak Au tour de Tom", "stop"])
    }

    @MainActor @Test func caller_settingsChange_appliesToTheNextSentence() {
        let (caller, voice, _) = makeCaller()
        let sentence = Announcement(LocalizedText(fr: "Au tour de Léa", en: "Léa to throw"))
        caller.say([sentence, sentence])
        caller.settings.callerLanguage = .en
        caller.settings.volume = 2
        voice.finishLast()
        #expect(voice.spoken == ["Au tour de Léa", "Léa to throw"])
        #expect(voice.sentences.map(\.volume) == [0.8, 1])
    }

    @MainActor @Test func caller_sentenceThatNeverEnds_isGivenUpAfterTheTimeout() {
        let (caller, voice, clock) = makeCaller()
        caller.say([Self.normal("140"), Self.normal("Au tour de Tom")])
        clock.advance(by: ScoreCaller.sentenceTimeout - 0.1)
        #expect(voice.spoken == ["140"] && voice.stops == 0)
        clock.advance(by: 0.2)
        #expect(voice.orders.map(orderName) == ["speak 140", "stop", "speak Au tour de Tom"])
    }

    @MainActor @Test func caller_timeoutOfASentenceThatEndedInTime_doesNothing() {
        let (caller, voice, clock) = makeCaller()
        caller.say([Self.normal("140")])
        voice.finishLast()
        clock.advance(by: 5)
        caller.say([Self.normal("Au tour de Tom")])
        // The timeout of "140" comes while "Au tour de Tom" is said: it must not cut it.
        clock.advance(by: ScoreCaller.sentenceTimeout - 4)
        #expect(voice.spoken == ["140", "Au tour de Tom"] && voice.stops == 0)
        // Its own timeout does, later.
        clock.advance(by: 5)
        #expect(voice.stops == 1)
    }

    @MainActor @Test func caller_reset_rebuildsTheVoice_andStartsAfresh() {
        let (caller, voice, _) = makeCaller()
        caller.say([Self.normal("140"), Self.normal("Au tour de Tom")])
        caller.reset()
        #expect(voice.orders.map(orderName) == ["speak 140", "reset"])
        // The old sentence is forgotten: its late report starts nothing.
        voice.finish(at: 0)
        #expect(voice.spoken == ["140"])
        caller.say([Self.normal("Au tour de Léa")])
        #expect(voice.spoken == ["140", "Au tour de Léa"])
    }

    private func orderName(_ order: AudioTestVoice.Order) -> String {
        switch order {
        case .warmUp: return "warmUp"
        case .speak(let sentence): return "speak \(sentence.text)"
        case .stop: return "stop"
        case .reset: return "reset"
        }
    }

    // MARK: - Choice of the voice

    private typealias Candidate = ScoreCallerVoiceChoice.Candidate

    private func preferred(_ candidates: [ScoreCallerVoiceChoice.Candidate], _ languageCode: String = "fr-FR",
                           systemDefault: String? = nil) -> String? {
        ScoreCallerVoiceChoice.preferred(among: candidates, languageCode: languageCode, systemDefault: systemDefault)
    }

    @Test func voice_prefersPremium_thenEnhanced_thenDefault() {
        let compact = Candidate(identifier: "fr.compact", language: "fr-FR", quality: 1)
        let enhanced = Candidate(identifier: "fr.enhanced", language: "fr-FR", quality: 2)
        let premium = Candidate(identifier: "fr.premium", language: "fr-FR", quality: 3)
        #expect(preferred([compact, enhanced, premium]) == "fr.premium")
        #expect(preferred([premium, compact, enhanced]) == "fr.premium")
        #expect(preferred([compact, enhanced]) == "fr.enhanced")
        #expect(preferred([compact]) == "fr.compact")
        // Quality wins over the system's own default.
        #expect(preferred([compact, enhanced, premium], systemDefault: "fr.compact") == "fr.premium")
    }

    @Test func voice_neverPicksANoveltyOrAPersonalVoice() {
        let novelty = Candidate(identifier: "en.bells", language: "en-US", quality: 3, isNovelty: true)
        let personal = Candidate(identifier: "en.me", language: "en-US", quality: 3, isPersonal: true)
        let plain = Candidate(identifier: "en.samantha", language: "en-US", quality: 1)
        #expect(preferred([novelty, personal, plain], "en-US") == "en.samantha")
        #expect(preferred([novelty, personal], "en-US") == nil)
    }

    @Test func voice_keepsToTheLanguageAsked() {
        let french = Candidate(identifier: "fr.thomas", language: "fr-FR", quality: 1)
        let canadian = Candidate(identifier: "fr.amelie", language: "fr-CA", quality: 3)
        let english = Candidate(identifier: "en.samantha", language: "en-US", quality: 3)
        let british = Candidate(identifier: "en.daniel", language: "en-GB", quality: 3)
        // The exact language first, even against a better voice of another region.
        #expect(preferred([canadian, french, english]) == "fr.thomas")
        #expect(preferred([british, english, french], "en-US") == "en.samantha")
        // No voice of the exact region: the same language elsewhere.
        #expect(preferred([canadian, english]) == "fr.amelie")
        #expect(preferred([british, french], "en-US") == "en.daniel")
        // No voice of the language at all: nothing, and the system falls back on its own.
        #expect(preferred([english, british]) == nil)
        #expect(preferred([]) == nil)
        // Tags are compared whatever their case and separator.
        #expect(preferred([Candidate(identifier: "fr.x", language: "fr_fr", quality: 1)], "FR-FR") == "fr.x")
    }

    @Test func voice_atEqualQuality_keepsTheSystemDefault_elseTheFirstIdentifier() {
        let voices = ["fr.c", "fr.a", "fr.b"].map { Candidate(identifier: $0, language: "fr-FR", quality: 2) }
        #expect(preferred(voices, systemDefault: "fr.b") == "fr.b")
        #expect(preferred(voices, systemDefault: nil) == "fr.a")
        #expect(preferred(voices.reversed(), systemDefault: "fr.unknown") == "fr.a")
        // The order of the list never matters.
        #expect(preferred(voices.shuffledForTest(), systemDefault: nil) == "fr.a")
    }
}

private extension Array {
    /// A fixed permutation: last element first.
    func shuffledForTest() -> [Element] {
        guard let last else { return self }
        return [last] + dropLast()
    }
}
