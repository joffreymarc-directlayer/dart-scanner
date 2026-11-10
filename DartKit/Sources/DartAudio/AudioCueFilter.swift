// DartAudio — what the settings let through, and when it plays (ARCHITECTURE.md §7.3: the settings filter at play
// time, not in the table). Pure values: no audio API in here.
import Foundation

enum AudioCueFilter {
    /// Longest delay honoured, in seconds. A batch lasts a second or two; anything longer is brought back to this.
    static let maximumDelay: TimeInterval = 10

    /// The part of `cues` that the settings allow, in the same order.
    ///
    /// - `isMuted`: nothing at all.
    /// - `effectsEnabled`, `callerEnabled`, `hapticsEnabled`: each removes its own part of every cue.
    /// - A device without a Taptic Engine plays no haptic, whatever the setting says.
    /// - A cue with nothing left is dropped; a delay that is negative, not finite or absurdly long is brought back
    ///   into 0...`maximumDelay`.
    static func playable(_ cues: [AudioCue], settings: AudioSettings, supportsHaptics: Bool) -> [AudioCue] {
        guard !settings.isMuted else { return [] }
        return cues.compactMap { cue in
            var cue = cue
            if !settings.effectsEnabled { cue.effect = nil }
            if !settings.callerEnabled { cue.announcement = nil }
            if !settings.hapticsEnabled || !supportsHaptics { cue.haptic = nil }
            guard cue.effect != nil || cue.announcement != nil || cue.haptic != nil else { return nil }
            cue.delay = playableDelay(cue.delay)
            return cue
        }
    }

    /// A `low` sentence is not started when a `high` sentence of the same batch comes less than this many
    /// seconds after it.
    static let cutHorizon: TimeInterval = 0.5

    /// A batch is weighed as a whole before the voice is touched. A `high` sentence interrupts everything: a
    /// `low` sentence that it would cut a fraction of a second later ("Tri… Cent quatre-vingts !") is left out.
    /// A `low` sentence with enough time ahead of it (the winning dart, 0.6 s before the winner's name) is kept.
    static func withoutSentencesAboutToBeCut(_ cues: [AudioCue]) -> [AudioCue] {
        let interruptions = cues.filter { $0.announcement?.priority == .high }.map { playableDelay($0.delay) }
        guard !interruptions.isEmpty else { return cues }
        return cues.compactMap { cue in
            guard cue.announcement?.priority == .low else { return cue }
            let start = playableDelay(cue.delay)
            guard interruptions.contains(where: { $0 >= start && $0 - start < cutHorizon }) else { return cue }
            var cue = cue
            cue.announcement = nil
            return cue.effect == nil && cue.haptic == nil ? nil : cue
        }
    }

    /// `delay` inside 0...`maximumDelay`; 0 when it is not a number.
    static func playableDelay(_ delay: TimeInterval) -> TimeInterval {
        guard !delay.isNaN else { return 0 }
        return min(max(delay, 0), maximumDelay)
    }

    /// `volume` as the mixer and the voice take it: inside 0...1; 0 when it is not a number.
    static func playableVolume(_ volume: Double) -> Float {
        guard !volume.isNaN else { return 0 }
        return Float(min(max(volume, 0), 1))
    }

    /// The cues that play at one instant, in the order of the batch.
    struct Moment: Equatable {
        var delay: TimeInterval
        var cues: [AudioCue]
    }

    /// `cues` grouped by delay, earliest first. Cues of the same delay keep the order of the batch: it is the
    /// order in which their sentences reach the caller.
    static func timeline(_ cues: [AudioCue]) -> [Moment] {
        let ordered = cues.enumerated().sorted { first, second in
            let (a, b) = (playableDelay(first.element.delay), playableDelay(second.element.delay))
            return a == b ? first.offset < second.offset : a < b
        }
        var moments: [Moment] = []
        for (_, cue) in ordered {
            let delay = playableDelay(cue.delay)
            if let last = moments.indices.last, moments[last].delay == delay {
                moments[last].cues.append(cue)
            } else {
                moments.append(Moment(delay: delay, cues: [cue]))
            }
        }
        return moments
    }
}
