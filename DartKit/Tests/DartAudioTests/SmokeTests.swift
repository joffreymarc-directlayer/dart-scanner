import Foundation
import Testing
import DartCore
import DartAudio

/// Smoke tests of the public API of DartAudio (ARCHITECTURE.md §7.2): the vocabulary, the plain values and
/// `SilentSoundPlayer`. Written by lot F0 on the skeleton and kept as they were by lot A1, which owns the target;
/// the mapping, the phrases, the synthesis and the service have their own suites, one file each. The last test
/// only checks that every entry point of the delivered API answers.
@Suite struct SmokeTests {
    @Test func vocabulary_isTheOneOfThePublicAPI() {
        #expect(SoundEffect.allCases.count == 22)
        #expect(Set(SoundEffect.allCases.map(\.rawValue)).count == 22)
        #expect(SoundEffect.allCases.first == .dartImpact && SoundEffect.allCases.last == .alert)
        #expect(HapticPattern.allCases == [.light, .medium, .heavy, .success, .warning, .failure])
        #expect(SoundEffect(rawValue: "zoneMove") == .zoneMove && SoundEffect(rawValue: "nope") == nil)
    }

    @Test func announcementPriorities_areOrdered() {
        #expect(Announcement.Priority.low < .normal && Announcement.Priority.normal < .high)
        let sentence = Announcement(LocalizedText(fr: "Au tour de Léa", en: "Léa to throw"))
        #expect(sentence.priority == .normal && sentence.text[.en] == "Léa to throw")
        #expect(Announcement(sentence.text, priority: .high) != sentence)
    }

    @Test func audioCue_defaultsToNothingAtOnce() {
        let empty = AudioCue()
        #expect(empty.effect == nil && empty.announcement == nil && empty.haptic == nil && empty.delay == 0)
        let cue = AudioCue(effect: .fanfare, announcement: Announcement(LocalizedText(verbatim: "180"), priority: .high),
                           haptic: .success, delay: 0.25)
        #expect(cue.effect == .fanfare && cue.announcement?.priority == .high && cue.haptic == .success && cue.delay == 0.25)
        #expect(cue != empty && cue == AudioCue(effect: .fanfare, announcement: cue.announcement, haptic: .success, delay: 0.25))
    }

    @Test func audioSettings_defaults_andJSON() throws {
        var settings = AudioSettings()
        #expect(!settings.isMuted && settings.effectsEnabled && settings.callerEnabled && settings.callerLanguage == .fr)
        #expect(settings.volume == 0.8 && settings.playsInSilentMode && settings.ducksMusicWhileSpeaking && settings.hapticsEnabled)
        settings.isMuted = true
        settings.callerLanguage = .en
        settings.volume = 0.25
        let decoded = try JSONDecoder().decode(AudioSettings.self, from: JSONEncoder().encode(settings))
        #expect(decoded == settings && decoded != AudioSettings())
    }

    @Test func cueContext_carriesTheWinnerTitle() {
        let players = [Player(name: "Léa"), Player(name: "Tom")]
        let running = CueContext(gameID: .killer, players: players)
        #expect(running.gameID == .killer && running.players == players && running.winners.isEmpty && running.winnerTitle == nil)
        let title = LocalizedText(fr: "Le camp A gagne", en: "Side A wins")
        let finished = CueContext(gameID: .football, players: players, winners: [0], winnerTitle: title)
        #expect(finished.winners == [0] && finished.winnerTitle == title)
    }

    @Test func interfaceCues_compareByValue() {
        #expect(InterfaceCue.gameStarted(firstPlayer: 0) != .gameStarted(firstPlayer: 1))
        #expect(InterfaceCue.dartNeedsReview != .dartUndecided)
        #expect(Set<InterfaceCue>([.undo, .undo, .shutter, .buttonTap]).count == 3)
    }

    @MainActor @Test func silentPlayer_playsNothing_andRemembersWhatItWasAsked() {
        let player = SilentSoundPlayer()
        #expect(player.played.isEmpty && !player.supportsHaptics && player.settings == AudioSettings())
        player.prepare()
        player.setActive(false)
        let batch = [AudioCue(effect: .dartImpact, haptic: .light), AudioCue(effect: .scoreUp, delay: 0.1)]
        player.play(batch)
        // The two conveniences of the protocol go through `play(_:)` too.
        player.play(.victory)
        player.say(LocalizedText(fr: "Léa gagne la partie", en: "Léa wins"), priority: .high)
        player.stopAll()
        #expect(player.played == batch + [
            AudioCue(effect: .victory),
            AudioCue(announcement: Announcement(LocalizedText(fr: "Léa gagne la partie", en: "Léa wins"), priority: .high)),
        ])
        var settings = AudioSettings()
        settings.isMuted = true
        player.settings = settings
        #expect(player.settings.isMuted)
        // Seen through the protocol, as DartUI sees it.
        let service: any SoundPlaying = SilentSoundPlayer(settings: settings, supportsHaptics: true)
        #expect(service.supportsHaptics && service.settings.isMuted)
        service.say(LocalizedText(verbatim: "140"))
        #expect((service as? SilentSoundPlayer)?.played == [AudioCue(announcement: Announcement(LocalizedText(verbatim: "140")))])
    }

    @MainActor @Test func deliveredAPI_answersEverywhere() {
        // What DartUI does with one dart: events in, cues out, cues played.
        let context = CueContext(gameID: .highScore, players: [Player(name: "Léa"), Player(name: "Tom")])
        let events: [GameEvent] = [.dartRegistered(player: 0, hit: .treble(20)), .turnScored(player: 0, points: 60),
                                   .turnCompleted(player: 0)]
        let cues = CueMapping.cues(for: events, context: context)
        #expect(cues.first?.effect == .dartImpact && cues.last?.announcement?.text == LocalizedText(verbatim: "60"))
        #expect(CueMapping.cues(for: .buttonTap, context: context) == [AudioCue(haptic: .light)])
        #expect(CallerPhrases.hit(.treble(20))[.fr] == "Triple 20" && CallerPhrases.turnTotal(180)[.en] == "180")
        #expect(CallerPhrases.nextPlayer("Léa")[.en] == "Léa to throw" && CallerPhrases.winners(["Léa"])[.fr] == "Léa gagne la partie")
        #expect(CallerPhrases.phrase(for: .oneEighty(player: 0), context: context)?[.fr] == "Cent quatre-vingts !")
        #expect(SoundSynthesizer.samples(for: .tick, sampleRate: 44_100).count == 2_205)
        let player = SilentSoundPlayer()
        player.play(cues)
        #expect(player.played == cues)
        // The real service is built without touching any audio hardware; muted, it plays nothing at all.
        var muted = AudioSettings()
        muted.isMuted = true
        let director: any SoundPlaying = AudioDirector(settings: muted)
        #expect(director.settings == muted)
        director.play(cues)
        director.stopAll()
        director.setActive(false)
    }
}
