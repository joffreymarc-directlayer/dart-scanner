import Foundation
import Testing
import DartCore
@testable import DartAudio

/// The settings filter at play time, not in the table (ARCHITECTURE.md §7.3): `isMuted`, `effectsEnabled`,
/// `callerEnabled`, `hapticsEnabled`. A pure function, tested without any audio object.
@Suite struct AudioCueFilterTests {
    private let said = Announcement(LocalizedText(fr: "Cent quatre-vingts !", en: "One hundred and eighty!"), priority: .high)

    /// A batch with every kind of cue: full, effect only, sentence only, haptic only.
    private var batch: [AudioCue] {
        [
            AudioCue(effect: .dartImpact, announcement: Announcement(LocalizedText(verbatim: "20"), priority: .low), haptic: .light, delay: 0),
            AudioCue(effect: .scoreUp, delay: 0.12),
            AudioCue(announcement: said, delay: 0.12),
            AudioCue(haptic: .success, delay: 0.24),
        ]
    }

    private func settings(_ change: (inout AudioSettings) -> Void) -> AudioSettings {
        var settings = AudioSettings()
        change(&settings)
        return settings
    }

    @Test func defaultSettings_letEverythingThrough_unchanged() {
        #expect(AudioCueFilter.playable(batch, settings: AudioSettings(), supportsHaptics: true) == batch)
        #expect(AudioCueFilter.playable([], settings: AudioSettings(), supportsHaptics: true).isEmpty)
    }

    @Test func muted_nothingIsPlayedSpokenOrVibrated() {
        let muted = settings { $0.isMuted = true }
        #expect(AudioCueFilter.playable(batch, settings: muted, supportsHaptics: true).isEmpty)
        // The master mute wins over everything else being enabled.
        #expect(muted.effectsEnabled && muted.callerEnabled && muted.hapticsEnabled)
    }

    @Test func effectsDisabled_removesTheEffects_andOnlyThem() {
        let filtered = AudioCueFilter.playable(batch, settings: settings { $0.effectsEnabled = false }, supportsHaptics: true)
        #expect(filtered == [
            AudioCue(announcement: Announcement(LocalizedText(verbatim: "20"), priority: .low), haptic: .light, delay: 0),
            AudioCue(announcement: said, delay: 0.12),
            AudioCue(haptic: .success, delay: 0.24),
        ])
    }

    @Test func callerDisabled_removesTheSentences_andOnlyThem() {
        let filtered = AudioCueFilter.playable(batch, settings: settings { $0.callerEnabled = false }, supportsHaptics: true)
        #expect(filtered == [
            AudioCue(effect: .dartImpact, haptic: .light, delay: 0),
            AudioCue(effect: .scoreUp, delay: 0.12),
            AudioCue(haptic: .success, delay: 0.24),
        ])
    }

    @Test func hapticsDisabled_removesTheHaptics_andOnlyThem() {
        let filtered = AudioCueFilter.playable(batch, settings: settings { $0.hapticsEnabled = false }, supportsHaptics: true)
        #expect(filtered == [
            AudioCue(effect: .dartImpact, announcement: Announcement(LocalizedText(verbatim: "20"), priority: .low), delay: 0),
            AudioCue(effect: .scoreUp, delay: 0.12),
            AudioCue(announcement: said, delay: 0.12),
        ])
    }

    @Test func deviceWithoutTapticEngine_playsNoHaptic_whateverTheSetting() {
        // An iPad: `hapticsEnabled` is still true in the settings, and ignored.
        let filtered = AudioCueFilter.playable(batch, settings: AudioSettings(), supportsHaptics: false)
        #expect(filtered.allSatisfy { $0.haptic == nil })
        #expect(filtered.count == 3 && filtered.map(\.effect) == [.dartImpact, .scoreUp, nil])
    }

    @Test func everythingDisabled_isLikeMuted() {
        let off = settings {
            $0.effectsEnabled = false
            $0.callerEnabled = false
            $0.hapticsEnabled = false
        }
        #expect(AudioCueFilter.playable(batch, settings: off, supportsHaptics: true).isEmpty)
    }

    @Test func otherSettings_doNotFilter() {
        let other = settings {
            $0.volume = 0
            $0.callerLanguage = .en
            $0.playsInSilentMode = false
            $0.ducksMusicWhileSpeaking = false
        }
        #expect(AudioCueFilter.playable(batch, settings: other, supportsHaptics: true) == batch)
    }

    @Test func everyCombinationOfTheFourSwitches() {
        for bits in 0..<32 {
            let flags = (0..<5).map { bits & (1 << $0) != 0 }
            let chosen = settings {
                $0.isMuted = flags[0]
                $0.effectsEnabled = flags[1]
                $0.callerEnabled = flags[2]
                $0.hapticsEnabled = flags[3]
            }
            let filtered = AudioCueFilter.playable(batch, settings: chosen, supportsHaptics: flags[4])
            let effects = !flags[0] && flags[1]
            let sentences = !flags[0] && flags[2]
            let haptics = !flags[0] && flags[3] && flags[4]
            #expect(filtered.compactMap(\.effect) == (effects ? [.dartImpact, .scoreUp] : []))
            #expect(filtered.compactMap(\.announcement).count == (sentences ? 2 : 0))
            #expect(filtered.compactMap(\.haptic) == (haptics ? [.light, .success] : []))
            #expect(filtered.allSatisfy { $0.effect != nil || $0.announcement != nil || $0.haptic != nil })
            // What is left keeps the order and the delays of the batch.
            #expect(filtered.map(\.delay) == filtered.map(\.delay).sorted())
        }
    }

    @Test func delays_areBroughtBackToAPlayableRange() {
        #expect(AudioCueFilter.playableDelay(0) == 0)
        #expect(AudioCueFilter.playableDelay(0.6) == 0.6)
        #expect(AudioCueFilter.playableDelay(-1) == 0)
        #expect(AudioCueFilter.playableDelay(.nan) == 0)
        #expect(AudioCueFilter.playableDelay(-.infinity) == 0)
        #expect(AudioCueFilter.playableDelay(.infinity) == AudioCueFilter.maximumDelay)
        #expect(AudioCueFilter.playableDelay(3_600) == AudioCueFilter.maximumDelay)
        let odd = [AudioCue(effect: .tick, delay: -0.5), AudioCue(effect: .lock, delay: .nan), AudioCue(effect: .alert, delay: 1e9)]
        #expect(AudioCueFilter.playable(odd, settings: AudioSettings(), supportsHaptics: true).map(\.delay) == [0, 0, AudioCueFilter.maximumDelay])
    }

    @Test func volume_isBroughtBackTo0To1() {
        #expect(AudioCueFilter.playableVolume(0.8) == 0.8)
        #expect(AudioCueFilter.playableVolume(0) == 0 && AudioCueFilter.playableVolume(1) == 1)
        #expect(AudioCueFilter.playableVolume(-3) == 0 && AudioCueFilter.playableVolume(7) == 1)
        #expect(AudioCueFilter.playableVolume(.nan) == 0)
        #expect(AudioCueFilter.playableVolume(.infinity) == 1 && AudioCueFilter.playableVolume(-.infinity) == 0)
    }

    @Test func lowSentence_isLeftOut_whenAHighSentenceOfTheBatchWouldCutIt() {
        let low = Announcement(LocalizedText(verbatim: "Triple 20"), priority: .low)
        let normal = Announcement(LocalizedText(verbatim: "140"), priority: .normal)
        let dart = AudioCue(effect: .dartImpact, announcement: low, haptic: .light, delay: 0)
        // Third dart of a 180: the dart keeps its sound and its haptic, and loses its sentence.
        let oneEighty = [dart, AudioCue(effect: .fanfare, announcement: said, haptic: .success, delay: 0.12)]
        #expect(AudioCueFilter.withoutSentencesAboutToBeCut(oneEighty) == [
            AudioCue(effect: .dartImpact, haptic: .light, delay: 0), oneEighty[1],
        ])
        // At the same instant too.
        #expect(AudioCueFilter.withoutSentencesAboutToBeCut([dart, AudioCue(announcement: said)])
            == [AudioCue(effect: .dartImpact, haptic: .light), AudioCue(announcement: said)])
        // A cue that was only that sentence disappears.
        #expect(AudioCueFilter.withoutSentencesAboutToBeCut([AudioCue(announcement: low), AudioCue(announcement: said, delay: 0.3)])
            == [AudioCue(announcement: said, delay: 0.3)])
        // Just under the horizon it goes; at the horizon and beyond it stays (the winning dart, 0.72 s before the name).
        #expect(AudioCueFilter.cutHorizon == 0.5)
        #expect(AudioCueFilter.withoutSentencesAboutToBeCut([dart, AudioCue(announcement: said, delay: 0.49)]).first?.announcement == nil)
        #expect(AudioCueFilter.withoutSentencesAboutToBeCut([dart, AudioCue(announcement: said, delay: 0.5)]).first == dart)
        #expect(AudioCueFilter.withoutSentencesAboutToBeCut([dart, AudioCue(announcement: said, delay: 0.72)]).first == dart)
        // A high sentence that came BEFORE the low one does not remove it here: the queue drops it if it must.
        let late = AudioCue(announcement: low, delay: 0.3)
        #expect(AudioCueFilter.withoutSentencesAboutToBeCut([AudioCue(announcement: said), late]) == [AudioCue(announcement: said), late])
        // Normal sentences queue: nothing is cut, nothing is left out.
        let queued = [dart, AudioCue(announcement: normal), AudioCue(effect: .highTurn, delay: 0.12)]
        #expect(AudioCueFilter.withoutSentencesAboutToBeCut(queued) == queued)
        // Only a low sentence is left out: a normal or a high one just before a high one is kept, the priority
        // rules of the caller decide (§7.5).
        let normalThenHigh = [AudioCue(announcement: normal), AudioCue(announcement: said, delay: 0.12)]
        #expect(AudioCueFilter.withoutSentencesAboutToBeCut(normalThenHigh) == normalThenHigh)
        let highThenHigh = [AudioCue(announcement: said), AudioCue(announcement: said, delay: 0.12)]
        #expect(AudioCueFilter.withoutSentencesAboutToBeCut(highThenHigh) == highThenHigh)
        #expect(AudioCueFilter.withoutSentencesAboutToBeCut(batch).map(\.announcement?.priority) == [nil, nil, .high, nil])
        #expect(AudioCueFilter.withoutSentencesAboutToBeCut([]).isEmpty)
    }

    @Test func timeline_groupsByDelay_earliestFirst_keepingTheOrderOfTheBatch() {
        #expect(AudioCueFilter.timeline(batch) == [
            AudioCueFilter.Moment(delay: 0, cues: [batch[0]]),
            AudioCueFilter.Moment(delay: 0.12, cues: [batch[1], batch[2]]),
            AudioCueFilter.Moment(delay: 0.24, cues: [batch[3]]),
        ])
        #expect(AudioCueFilter.timeline([]).isEmpty)
        // Cues given out of order are sorted; equal delays keep the order in which they were given.
        let first = AudioCue(announcement: Announcement(LocalizedText(verbatim: "first"), priority: .normal), delay: 0.3)
        let second = AudioCue(announcement: Announcement(LocalizedText(verbatim: "second"), priority: .normal), delay: 0.3)
        let early = AudioCue(effect: .tick, delay: 0.1)
        #expect(AudioCueFilter.timeline([first, early, second]) == [
            AudioCueFilter.Moment(delay: 0.1, cues: [early]),
            AudioCueFilter.Moment(delay: 0.3, cues: [first, second]),
        ])
    }

    @Test func timeline_ofAMappedBatch_saysTheSentencesInTheOrderOfTheTable() {
        // The winning dart of a Killer game: every sentence in the order it must reach the caller.
        let players = [Player(name: "Léa"), Player(name: "Tom")]
        let cues = CueMapping.cues(
            for: [.dartRegistered(player: 0, hit: .single(5)), .lifeLost(player: 1, by: 0, livesLeft: 0),
                  .playerEliminated(player: 1, by: 0), .gameFinished(reason: .lastPlayerStanding)],
            context: CueContext(gameID: .killer, players: players, winners: [0]))
        let timeline = AudioCueFilter.timeline(cues)
        #expect(timeline.map(\.delay) == [0, 0.12, 0.24, 0.36, 0.96])
        #expect(timeline.flatMap(\.cues).compactMap(\.announcement?.text.fr) == ["5", "Tom est éliminé", "Léa gagne la partie"])
    }
}
