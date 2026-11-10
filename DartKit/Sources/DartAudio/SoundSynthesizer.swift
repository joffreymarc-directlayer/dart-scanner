// DartAudio — the recipes of the effects: pure computation, no audio API (ARCHITECTURE.md §7.7).
import Foundation
import DartCore

public enum SoundSynthesizer {
    /// Mono samples in -1...1 for one effect. Deterministic: same input, same samples. 0.05 s to 1.5 s long.
    ///
    /// Every buffer peaks at 0.9 or less and starts and ends with a linear fade of 4 ms, so it never clicks.
    /// A sample rate outside 8 000...192 000 Hz (or not finite) cannot carry the recipes: the result is empty.
    public static func samples(for effect: SoundEffect, sampleRate: Double) -> [Float] {
        guard sampleRate.isFinite, sampleRate >= minimumSampleRate, sampleRate <= maximumSampleRate else { return [] }
        var track = Track(duration: duration(of: effect), sampleRate: sampleRate)
        render(effect, into: &track)
        return track.finished(level: level(of: effect))
    }

    // MARK: - Constraints (ARCHITECTURE.md §7.7)

    static let minimumSampleRate = 8_000.0
    static let maximumSampleRate = 192_000.0
    fileprivate static let shortestDuration = 0.05
    fileprivate static let longestDuration = 1.5
    /// Linear fade at both ends of every buffer. The contract asks for 3 ms at least.
    fileprivate static let edgeFade = 0.004

    // MARK: - The table of §7.7

    /// Nominal length of each effect, in seconds.
    private static func duration(of effect: SoundEffect) -> TimeInterval {
        switch effect {
        case .dartImpact: return 0.12
        case .dartDull: return 0.10
        case .scoreUp: return 0.18
        case .tick: return 0.05
        case .lock: return 0.15
        case .powerUp: return 0.45
        case .damage: return 0.25
        case .heal: return 0.35
        case .claim: return 0.30
        case .eliminated: return 0.60
        case .bust: return 0.45
        case .halved: return 0.40
        case .highTurn: return 0.35
        case .fanfare: return 1.10
        case .victory: return 1.50
        case .turnChange: return 0.20
        case .zoneMove: return 0.30
        case .needsReview: return 0.22
        case .rejected: return 0.18
        case .shutter: return 0.12
        case .confirm: return 0.15
        case .alert: return 0.50
        }
    }

    /// Peak of each buffer: the mix of the effects, set once here. A sound that holds its level (a buzzer, a glide,
    /// a beep) is much louder at the same peak than one that dies away (a dart, a chord), so it peaks lower.
    private static func level(of effect: SoundEffect) -> Double {
        switch effect {
        case .dartImpact: return 0.80
        case .dartDull: return 0.65
        case .scoreUp: return 0.60
        case .tick: return 0.50
        case .lock: return 0.70
        case .powerUp: return 0.38
        case .damage: return 0.75
        case .heal: return 0.50
        case .claim: return 0.55
        case .eliminated: return 0.65
        case .bust: return 0.45
        case .halved: return 0.38
        case .highTurn: return 0.80
        case .fanfare: return 0.80
        case .victory: return 0.85
        case .turnChange: return 0.45
        case .zoneMove: return 0.32
        case .needsReview: return 0.30
        case .rejected: return 0.42
        case .shutter: return 0.80
        case .confirm: return 0.50
        case .alert: return 0.45
        }
    }

    /// The recipe of each effect. Times in seconds, pitches in hertz; gains are relative inside one effect.
    private static func render(_ effect: SoundEffect, into track: inout Track) {
        switch effect {
        case .dartImpact:
            // A short burst of filtered noise (the point entering the sisal) over a damped 160 Hz thud.
            // The partials of the thud carry it on a phone speaker, which plays next to nothing under 300 Hz.
            track.noise(at: 0, for: 0.10, gain: 1, envelope: .struck(decay: 0.020), lowpass: 3_500, seed: 0xDA27_0001)
            track.tone(at: 0, for: 0.12, pitch: .steady(160), gain: 0.45, envelope: .struck(decay: 0.034), partials: Partial.thud)

        case .dartDull:
            // The same thud, lower and without the noise.
            track.tone(at: 0, for: 0.10, pitch: .steady(110), gain: 1, envelope: .struck(decay: 0.030), partials: Partial.thud)

        case .scoreUp:
            // Two rising notes.
            track.tone(at: 0, for: 0.09, pitch: .steady(660), gain: 0.9, envelope: .struck(decay: 0.05), partials: Partial.soft)
            track.tone(at: 0.08, for: 0.10, pitch: .steady(880), gain: 1, envelope: .struck(decay: 0.06), partials: Partial.soft)

        case .tick:
            track.tone(at: 0, for: 0.05, pitch: .steady(1_800), gain: 1, envelope: .struck(decay: 0.009))

        case .lock:
            // Two low clicks close together: a latch that falls, then holds.
            track.noise(at: 0, for: 0.02, gain: 0.35, envelope: .struck(decay: 0.004), lowpass: 1_500, seed: 0x10CC_0001)
            track.tone(at: 0, for: 0.06, pitch: .steady(300), gain: 0.9, envelope: .struck(decay: 0.012), partials: Partial.metal)
            track.noise(at: 0.065, for: 0.02, gain: 0.35, envelope: .struck(decay: 0.005), lowpass: 1_500, seed: 0x10CC_0002)
            track.tone(at: 0.065, for: 0.085, pitch: .steady(220), gain: 1, envelope: .struck(decay: 0.020), partials: Partial.metal)

        case .powerUp:
            track.tone(at: 0, for: 0.45, pitch: .glide(from: 300, to: 1_200), gain: 1,
                       envelope: .held(attack: 0.012, release: 0.08), partials: Partial.bright)

        case .damage:
            track.noise(at: 0, for: 0.20, gain: 0.6, envelope: .struck(decay: 0.05), lowpass: 1_800, seed: 0xDA3A_6E01)
            track.tone(at: 0, for: 0.25, pitch: .glide(from: 220, to: 110), gain: 1, envelope: .struck(decay: 0.09),
                       partials: [Partial(1, 1), Partial(2, 0.45), Partial(3, 0.2)])

        case .heal:
            // A soft rising arpeggio whose three notes ring together.
            track.tone(at: 0, for: 0.35, pitch: .steady(Note.c5), gain: 0.8, envelope: .bell(decay: 0.11), partials: Partial.soft)
            track.tone(at: 0.09, for: 0.26, pitch: .steady(Note.e5), gain: 0.85, envelope: .bell(decay: 0.11), partials: Partial.soft)
            track.tone(at: 0.18, for: 0.17, pitch: .steady(Note.g5), gain: 0.9, envelope: .bell(decay: 0.11), partials: Partial.soft)

        case .claim:
            // A held note and its fifth.
            let envelope = Envelope(attack: 0.008, release: 0.09, decay: 0.30)
            track.tone(at: 0, for: 0.30, pitch: .steady(520), gain: 1, envelope: envelope, partials: Partial.soft)
            track.tone(at: 0, for: 0.30, pitch: .steady(780), gain: 0.6, envelope: envelope, partials: Partial.soft)

        case .eliminated:
            // Three falling notes.
            let envelope = Envelope(attack: 0.006, release: 0.03, decay: 0.13)
            track.tone(at: 0, for: 0.20, pitch: .steady(Note.a4), gain: 1, envelope: envelope, partials: Partial.reed)
            track.tone(at: 0.20, for: 0.20, pitch: .steady(Note.f4), gain: 1, envelope: envelope, partials: Partial.reed)
            track.tone(at: 0.40, for: 0.20, pitch: .steady(Note.c4), gain: 1, envelope: envelope, partials: Partial.reed)

        case .bust:
            // The buzzer: a 140 Hz square wave, built from its odd harmonics so that it does not alias.
            track.tone(at: 0, for: 0.45, pitch: .steady(140), gain: 1, envelope: .held(attack: 0.006, release: 0.05),
                       partials: Partial.square(harmonics: 18))

        case .halved:
            track.tone(at: 0, for: 0.40, pitch: .glide(from: 600, to: 300), gain: 1,
                       envelope: .held(attack: 0.008, release: 0.10), partials: Partial.bright)

        case .highTurn:
            // A short major chord.
            let envelope = Envelope(attack: 0.004, release: 0.04, decay: 0.13)
            for (pitch, gain) in [(Note.c5, 1.0), (Note.e5, 0.9), (Note.g5, 0.9), (Note.c6, 0.5)] {
                track.tone(at: 0, for: 0.35, pitch: .steady(pitch), gain: gain, envelope: envelope, partials: Partial.bright)
            }

        case .fanfare:
            // A major arpeggio of four notes, then the chord, held.
            let short = Envelope(attack: 0.005, release: 0.02, decay: 0.09)
            for (index, pitch) in [Note.c5, Note.e5, Note.g5, Note.c6].enumerated() {
                track.tone(at: 0.1 * Double(index), for: 0.13, pitch: .steady(pitch), gain: 1, envelope: short, partials: Partial.brass)
            }
            let held = Envelope(attack: 0.010, release: 0.25, decay: 0.8)
            for (pitch, gain) in [(Note.c5, 0.7), (Note.e5, 0.6), (Note.g5, 0.6), (Note.c6, 0.8)] {
                track.tone(at: 0.40, for: 0.70, pitch: .steady(pitch), gain: gain, envelope: held, partials: Partial.brass)
            }

        case .victory:
            // A long fanfare of six notes: four rising, a step back, and the top note held over its chord.
            let short = Envelope(attack: 0.005, release: 0.02, decay: 0.10)
            track.tone(at: 0, for: 0.13, pitch: .steady(Note.g4), gain: 1, envelope: short, partials: Partial.brass)
            track.tone(at: 0.13, for: 0.13, pitch: .steady(Note.c5), gain: 1, envelope: short, partials: Partial.brass)
            track.tone(at: 0.26, for: 0.13, pitch: .steady(Note.e5), gain: 1, envelope: short, partials: Partial.brass)
            track.tone(at: 0.39, for: 0.17, pitch: .steady(Note.g5), gain: 1, envelope: short, partials: Partial.brass)
            track.tone(at: 0.56, for: 0.13, pitch: .steady(Note.e5), gain: 1, envelope: short, partials: Partial.brass)
            let held = Envelope(attack: 0.010, release: 0.30, decay: 1.0)
            track.tone(at: 0.69, for: 0.81, pitch: .steady(Note.c6), gain: 1, envelope: held, partials: Partial.brass)
            for (pitch, gain) in [(Note.c5, 0.45), (Note.e5, 0.5), (Note.g5, 0.5)] {
                track.tone(at: 0.69, for: 0.81, pitch: .steady(pitch), gain: gain, envelope: held, partials: Partial.brass)
            }

        case .turnChange:
            // Two neutral notes.
            let envelope = Envelope(attack: 0.005, release: 0.02, decay: 0.06)
            track.tone(at: 0, for: 0.10, pitch: .steady(440), gain: 1, envelope: envelope, partials: Partial.soft)
            track.tone(at: 0.10, for: 0.10, pitch: .steady(550), gain: 1, envelope: envelope, partials: Partial.soft)

        case .zoneMove:
            // A sweep up and back down.
            track.tone(at: 0, for: 0.30, pitch: .thereAndBack(low: 500, high: 1_000), gain: 1,
                       envelope: .held(attack: 0.010, release: 0.05), partials: Partial.soft)

        case .needsReview:
            // Two identical beeps.
            let envelope = Envelope.held(attack: 0.004, release: 0.015)
            track.tone(at: 0, for: 0.08, pitch: .steady(700), gain: 1, envelope: envelope, partials: Partial.hollow)
            track.tone(at: 0.14, for: 0.08, pitch: .steady(700), gain: 1, envelope: envelope, partials: Partial.hollow)

        case .rejected:
            // One low beep, slightly buzzy so that a phone speaker carries it.
            track.tone(at: 0, for: 0.18, pitch: .steady(196), gain: 1, envelope: .held(attack: 0.004, release: 0.03),
                       partials: Partial.square(harmonics: 4))

        case .shutter:
            // Two clicks of noise: the curtain opens, then closes.
            track.noise(at: 0, for: 0.045, gain: 1, envelope: .struck(decay: 0.006), lowpass: 3_500, highpass: 800, seed: 0x5C07_0001)
            track.noise(at: 0.055, for: 0.065, gain: 0.9, envelope: .struck(decay: 0.010), lowpass: 3_500, highpass: 800, seed: 0x5C07_0002)

        case .confirm:
            track.tone(at: 0, for: 0.15, pitch: .steady(880), gain: 1, envelope: Envelope(attack: 0.004, release: 0.02, decay: 0.06),
                       partials: Partial.bright)

        case .alert:
            // Three falling beeps.
            let envelope = Envelope(attack: 0.004, release: 0.02, decay: 0.25)
            track.tone(at: 0, for: 0.13, pitch: .steady(880), gain: 1, envelope: envelope, partials: Partial.hollow)
            track.tone(at: 0.17, for: 0.13, pitch: .steady(740), gain: 1, envelope: envelope, partials: Partial.hollow)
            track.tone(at: 0.34, for: 0.16, pitch: .steady(622.25), gain: 1, envelope: envelope, partials: Partial.hollow)
        }
    }
}

// MARK: - Building blocks

/// Equal-tempered pitches used by the recipes, in hertz.
private enum Note {
    static let c4 = 261.63
    static let f4 = 349.23
    static let g4 = 392.00
    static let a4 = 440.00
    static let c5 = 523.25
    static let e5 = 659.25
    static let g5 = 783.99
    static let c6 = 1_046.50
}

/// One sine component of a tone: `ratio` times the fundamental, at a relative `gain`.
private struct Partial: Sendable {
    var ratio: Double
    var gain: Double

    init(_ ratio: Double, _ gain: Double) {
        self.ratio = ratio
        self.gain = gain
    }

    static let pure = [Partial(1, 1)]
    /// A low, woody knock.
    static let thud = [Partial(1, 1), Partial(2, 0.6), Partial(3, 0.4), Partial(4, 0.2), Partial(5, 0.08)]
    static let soft = [Partial(1, 1), Partial(2, 0.15)]
    static let bright = [Partial(1, 1), Partial(2, 0.25), Partial(3, 0.08)]
    static let reed = [Partial(1, 1), Partial(2, 0.4), Partial(3, 0.2), Partial(4, 0.08)]
    static let brass = [Partial(1, 1), Partial(2, 0.5), Partial(3, 0.3), Partial(4, 0.12)]
    /// Odd harmonics only: a clarinet-like, insistent colour.
    static let hollow = [Partial(1, 1), Partial(3, 0.3), Partial(5, 0.1)]
    /// An inharmonic partial gives the clink of metal.
    static let metal = [Partial(1, 1), Partial(2.4, 0.35)]

    /// The first `harmonics` odd harmonics of a square wave (1, 3, 5… at 1, 1/3, 1/5…).
    static func square(harmonics: Int) -> [Partial] {
        (0..<max(harmonics, 1)).map { index in
            let order = Double(2 * index + 1)
            return Partial(order, 1 / order)
        }
    }
}

/// The pitch of a tone along its length.
private enum Pitch {
    case steady(Double)
    /// Exponential glide: equal musical intervals in equal times.
    case glide(from: Double, to: Double)
    /// Glides from `low` to `high` in the first half and back in the second.
    case thereAndBack(low: Double, high: Double)

    /// Frequency at `progress` in 0...1 of the tone.
    func frequency(at progress: Double) -> Double {
        switch self {
        case .steady(let frequency):
            return frequency
        case .glide(let from, let to):
            return from * pow(to / from, progress)
        case .thereAndBack(let low, let high):
            let climb = progress < 0.5 ? 2 * progress : 2 * (1 - progress)
            return low * pow(high / low, climb)
        }
    }

    var highest: Double {
        switch self {
        case .steady(let frequency): return frequency
        case .glide(let from, let to): return max(from, to)
        case .thereAndBack(let low, let high): return max(low, high)
        }
    }
}

/// Loudness of a sound along its length: a smooth rise, an optional exponential decay, a smooth fall.
private struct Envelope {
    /// Seconds from silence to full level.
    var attack: TimeInterval
    /// Seconds from full level to silence, counted back from the end.
    var release: TimeInterval
    /// Time constant of the exponential decay, in seconds; nil for a level that holds.
    var decay: TimeInterval?

    /// A percussive sound: it starts at once and dies away.
    static func struck(decay: TimeInterval) -> Envelope {
        Envelope(attack: 0.004, release: 0.012, decay: decay)
    }

    /// A softer percussive sound, for notes that ring.
    static func bell(decay: TimeInterval) -> Envelope {
        Envelope(attack: 0.012, release: 0.05, decay: decay)
    }

    /// A sound that holds its level between its two ramps.
    static func held(attack: TimeInterval, release: TimeInterval) -> Envelope {
        Envelope(attack: attack, release: release, decay: nil)
    }

    func value(at time: TimeInterval, of length: TimeInterval) -> Double {
        let rise = attack > 0 ? Self.ramp(time / attack) : 1
        let fall = release > 0 ? Self.ramp((length - time) / release) : 1
        let body = decay.map { exp(-time / $0) } ?? 1
        return rise * fall * body
    }

    /// Raised cosine from 0 to 1.
    private static func ramp(_ progress: Double) -> Double {
        if progress <= 0 { return 0 }
        if progress >= 1 { return 1 }
        return 0.5 - 0.5 * cos(.pi * progress)
    }
}

/// The buffer of one effect while its recipe is played into it.
private struct Track {
    let sampleRate: Double
    private var samples: [Double]

    init(duration: TimeInterval, sampleRate: Double) {
        self.sampleRate = sampleRate
        // The nominal length, kept inside the contract (0.05 s to 1.5 s) whatever the rounding at this sample rate.
        let wanted = (duration * sampleRate).rounded()
        let shortest = (SoundSynthesizer.shortestDuration * sampleRate - 1e-6).rounded(.up)
        let longest = (SoundSynthesizer.longestDuration * sampleRate + 1e-6).rounded(.down)
        samples = [Double](repeating: 0, count: Int(min(max(wanted, shortest), longest)))
    }

    /// The sample range of a sound that starts at `start` and lasts `length`, clipped to the buffer.
    private func span(at start: TimeInterval, for length: TimeInterval) -> Range<Int> {
        let first = min(max(Int((start * sampleRate).rounded()), 0), samples.count)
        let count = max(Int((length * sampleRate).rounded()), 0)
        return first..<min(first + count, samples.count)
    }

    /// Adds a pitched sound: a sum of sine partials that follow `pitch`, shaped by `envelope`.
    mutating func tone(at start: TimeInterval, for length: TimeInterval, pitch: Pitch, gain: Double,
                       envelope: Envelope, partials: [Partial] = Partial.pure) {
        let range = span(at: start, for: length)
        guard !range.isEmpty else { return }
        // A partial above the band of this sample rate would alias: it is left out.
        let audible = partials.filter { $0.ratio * pitch.highest < 0.45 * sampleRate }
        let count = Double(range.count)
        let duration = count / sampleRate
        var phase = 0.0
        for (offset, index) in range.enumerated() {
            let time = Double(offset) / sampleRate
            var value = 0.0
            for partial in audible {
                value += partial.gain * sin(partial.ratio * phase)
            }
            samples[index] += gain * envelope.value(at: time, of: duration) * value
            phase += 2 * .pi * pitch.frequency(at: Double(offset) / count) / sampleRate
        }
    }

    /// Adds a burst of noise, band-limited by a two-pole low-pass and an optional high-pass, shaped by `envelope`.
    /// The noise comes from `SeededRandom` with a fixed seed: the same samples at every call.
    mutating func noise(at start: TimeInterval, for length: TimeInterval, gain: Double, envelope: Envelope,
                        lowpass: Double, highpass: Double = 0, seed: UInt64) {
        let range = span(at: start, for: length)
        guard !range.isEmpty else { return }
        var random = SeededRandom(seed: seed)
        let lowCoefficient = 1 - exp(-2 * .pi * min(lowpass, 0.45 * sampleRate) / sampleRate)
        let highCoefficient = highpass > 0 ? 1 - exp(-2 * .pi * highpass / sampleRate) : 0
        var first = 0.0
        var second = 0.0
        var rumble = 0.0
        var burst = [Double](repeating: 0, count: range.count)
        for offset in burst.indices {
            // 53 random bits mapped to -1..<1.
            let white = Double(random.next() >> 11) / 9_007_199_254_740_992 * 2 - 1
            first += lowCoefficient * (white - first)
            second += lowCoefficient * (first - second)
            rumble += highCoefficient * (second - rumble)
            burst[offset] = second - rumble
        }
        // Filtering changes the level with the sample rate: bring the burst back to a peak of 1 before mixing.
        let peak = burst.reduce(0) { max($0, abs($1)) }
        guard peak > 0 else { return }
        let duration = Double(range.count) / sampleRate
        for (offset, index) in range.enumerated() {
            let time = Double(offset) / sampleRate
            samples[index] += gain * envelope.value(at: time, of: duration) * burst[offset] / peak
        }
    }

    /// The finished buffer: peak at `level`, then a linear fade at both ends.
    func finished(level: Double) -> [Float] {
        let clean = samples.map { $0.isFinite ? $0 : 0 }
        let peak = clean.reduce(0) { max($0, abs($1)) }
        guard peak > 0 else { return [Float](repeating: 0, count: clean.count) }
        let scale = level / peak
        let fade = max(Int((SoundSynthesizer.edgeFade * sampleRate).rounded(.up)), 1)
        let last = clean.count - 1
        return clean.enumerated().map { index, sample in
            let fromEdge = min(index, last - index)
            let gain = fromEdge < fade ? Double(fromEdge) / Double(fade) : 1
            return Float(sample * scale * gain)
        }
    }
}
