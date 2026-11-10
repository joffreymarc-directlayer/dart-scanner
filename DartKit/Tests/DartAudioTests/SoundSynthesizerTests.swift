import Foundation
import Testing
import DartAudio

/// The synthesised effects, checked numerically (ARCHITECTURE.md §7.7): length, peak, fades, determinism.
/// No audio hardware is involved: `SoundSynthesizer` is a pure computation.
@Suite struct SoundSynthesizerTests {
    /// The format of the engine: mono, 44 100 Hz.
    private static let sampleRate = 44_100.0

    /// The "Durée" column of the table of §7.7, in seconds.
    private static let durations: [SoundEffect: Double] = [
        .dartImpact: 0.12, .dartDull: 0.10, .scoreUp: 0.18, .tick: 0.05, .lock: 0.15, .powerUp: 0.45, .damage: 0.25,
        .heal: 0.35, .claim: 0.30, .eliminated: 0.60, .bust: 0.45, .halved: 0.40, .highTurn: 0.35, .fanfare: 1.10,
        .victory: 1.50, .turnChange: 0.20, .zoneMove: 0.30, .needsReview: 0.22, .rejected: 0.18, .shutter: 0.12,
        .confirm: 0.15, .alert: 0.50,
    ]

    private func samples(_ effect: SoundEffect, at sampleRate: Double = SoundSynthesizerTests.sampleRate) -> [Float] {
        SoundSynthesizer.samples(for: effect, sampleRate: sampleRate)
    }

    private func peak(_ samples: [Float]) -> Float {
        samples.reduce(0) { max($0, abs($1)) }
    }

    private func rootMeanSquare(_ samples: some Collection<Float>) -> Double {
        guard !samples.isEmpty else { return 0 }
        return (samples.reduce(0.0) { $0 + Double($1) * Double($1) } / Double(samples.count)).squareRoot()
    }

    /// Pitch of the part `range` (fractions of the buffer), from its zero crossings: two per period.
    private func pitch(_ samples: [Float], in range: ClosedRange<Double>, sampleRate: Double = SoundSynthesizerTests.sampleRate) -> Double {
        let first = Int(Double(samples.count) * range.lowerBound)
        let last = min(Int(Double(samples.count) * range.upperBound), samples.count - 1)
        var crossings = 0
        for index in (first + 1)...last where (samples[index - 1] < 0) != (samples[index] < 0) {
            crossings += 1
        }
        return Double(crossings) / 2 / (Double(last - first) / sampleRate)
    }

    // MARK: - The four constraints of §7.7, for every effect

    @Test func everyEffect_hasItsLineInTheTable() {
        #expect(Set(Self.durations.keys) == Set(SoundEffect.allCases))
    }

    @Test(arguments: SoundEffect.allCases)
    func duration_isTheOneOfTheTable_andStaysBetween50MillisecondsAndOneSecondAndAHalf(_ effect: SoundEffect) throws {
        let samples = samples(effect)
        let expected = try #require(Self.durations[effect])
        #expect(samples.count == Int((expected * Self.sampleRate).rounded()))
        let seconds = Double(samples.count) / Self.sampleRate
        #expect(seconds >= 0.05 && seconds <= 1.5)
    }

    @Test(arguments: SoundEffect.allCases)
    func signal_isFinite_within1_andPeaksAt90PercentAtMost(_ effect: SoundEffect) {
        let samples = samples(effect)
        #expect(samples.allSatisfy { $0.isFinite && $0 >= -1 && $0 <= 1 })
        let peak = peak(samples)
        #expect(peak <= 0.9)
        // Loud enough to be an effect. A sound that holds its level peaks lower than one that dies away.
        #expect(peak >= 0.25)
    }

    @Test func effects_areMixedTogether_noneDrownsTheOthers() {
        // Loudness follows the energy more than the peak: the loudest effect has at most five times the
        // root mean square of the quietest.
        let loudness = SoundEffect.allCases.map { rootMeanSquare(samples($0)) }
        let quietest = loudness.min() ?? 0
        let loudest = loudness.max() ?? 0
        #expect(quietest > 0.05 && loudest < 0.4 && loudest < 5 * quietest)
    }

    @Test(arguments: SoundEffect.allCases)
    func signal_isNotSilent(_ effect: SoundEffect) {
        let samples = samples(effect)
        #expect(rootMeanSquare(samples) > 0.03)
        // Something is heard in the first half, not only at the very end.
        #expect(rootMeanSquare(samples.prefix(samples.count / 2)) > 0.03)
    }

    @Test(arguments: SoundEffect.allCases)
    func ends_fadeOverThreeMillisecondsAtLeast_soThatNothingClicks(_ effect: SoundEffect) {
        let samples = samples(effect)
        let fade = Int((0.003 * Self.sampleRate).rounded(.up))
        #expect(samples.count > 2 * fade)
        #expect(samples.first == 0 && samples.last == 0)
        // Inside the first and the last 3 ms the signal stays under a straight ramp from silence to the allowed peak.
        for index in 0..<fade {
            let ceiling = 0.9 * Float(index) / Float(fade) + 1e-6
            #expect(abs(samples[index]) <= ceiling, "\(effect) rises too fast at sample \(index)")
            #expect(abs(samples[samples.count - 1 - index]) <= ceiling, "\(effect) falls too fast \(index) samples before its end")
        }
    }

    @Test(arguments: SoundEffect.allCases)
    func synthesis_isDeterministic(_ effect: SoundEffect) {
        #expect(samples(effect) == samples(effect))
        #expect(samples(effect, at: 48_000) == samples(effect, at: 48_000))
    }

    @Test func effects_areAllDifferent() {
        let buffers = SoundEffect.allCases.map { samples($0) }
        #expect(Set(buffers).count == SoundEffect.allCases.count)
    }

    // MARK: - Other sample rates

    @Test(arguments: [8_000.0, 11_025.0, 22_050.0, 48_000.0, 96_000.0])
    func otherSampleRates_keepTheConstraints(_ sampleRate: Double) throws {
        for effect in SoundEffect.allCases {
            let samples = samples(effect, at: sampleRate)
            let seconds = Double(samples.count) / sampleRate
            let expected = try #require(Self.durations[effect])
            #expect(seconds >= 0.05 && seconds <= 1.5, "\(effect)")
            #expect(abs(seconds - expected) <= 1 / sampleRate, "\(effect)")
            #expect(samples.allSatisfy { $0.isFinite }, "\(effect)")
            let peak = peak(samples)
            #expect(peak <= 0.9 && peak >= 0.3, "\(effect)")
            #expect(samples.first == 0 && samples.last == 0, "\(effect)")
            let fade = Int((0.003 * sampleRate).rounded(.up))
            for index in 0..<fade {
                let ceiling = 0.9 * Float(index) / Float(fade) + 1e-6
                #expect(abs(samples[index]) <= ceiling && abs(samples[samples.count - 1 - index]) <= ceiling, "\(effect)")
            }
        }
    }

    @Test func unusableSampleRate_givesNoSample_withoutTrapping() {
        for sampleRate in [0, -44_100, 1, 7_999, 192_001, 1e12, Double.infinity, -Double.infinity, Double.nan] {
            for effect in SoundEffect.allCases {
                #expect(samples(effect, at: sampleRate).isEmpty, "\(sampleRate)")
            }
        }
        #expect(!samples(.tick, at: 8_000).isEmpty && !samples(.tick, at: 192_000).isEmpty)
    }

    // MARK: - The recipes sound like what they say

    /// How much of the frequency `frequency` the part `range` (fractions of the buffer) contains: the size of its
    /// projection on a sinusoid of that frequency.
    private func strength(of frequency: Double, in samples: [Float], part range: ClosedRange<Double> = 0...1) -> Double {
        let first = Int(Double(samples.count) * range.lowerBound)
        let last = min(Int(Double(samples.count) * range.upperBound), samples.count)
        var real = 0.0
        var imaginary = 0.0
        for index in first..<last {
            let angle = 2 * Double.pi * frequency * Double(index) / Self.sampleRate
            real += Double(samples[index]) * cos(angle)
            imaginary += Double(samples[index]) * sin(angle)
        }
        return (real * real + imaginary * imaginary).squareRoot() / Double(max(last - first, 1))
    }

    /// The frequency of `candidates` that the part `range` contains most.
    private func strongest(of candidates: [Double], in samples: [Float], part range: ClosedRange<Double> = 0...1) -> Double? {
        candidates.max { strength(of: $0, in: samples, part: range) < strength(of: $1, in: samples, part: range) }
    }

    /// Share of the signal above 1 kHz or so: what makes a sound bright.
    private func brightness(_ samples: [Float]) -> Double {
        let coefficient = 1 - exp(-2 * Double.pi * 1_000 / Self.sampleRate)
        var low = 0.0
        var high: [Float] = []
        for sample in samples {
            low += coefficient * (Double(sample) - low)
            high.append(Float(Double(sample) - low))
        }
        return rootMeanSquare(high) / rootMeanSquare(samples)
    }

    @Test func steadyTones_haveThePitchOfTheirRecipe() {
        // Each tone holds more of its own pitch than of the pitches a tenth below and above.
        let recipes: [(SoundEffect, Double)] = [
            (.tick, 1_800), (.confirm, 880), (.needsReview, 700), (.bust, 140), (.dartDull, 110), (.dartImpact, 160),
            (.rejected, 196), (.claim, 520),
        ]
        for (effect, frequency) in recipes {
            let samples = samples(effect)
            #expect(strongest(of: [frequency * 0.9, frequency, frequency * 1.1], in: samples) == frequency, "\(effect)")
            #expect(strength(of: frequency, in: samples) > 0.01, "\(effect)")
        }
        // The fifth of the claim, the two beeps of the review, the square colour of the buzzer (odd harmonics only).
        #expect(strength(of: 780, in: samples(.claim)) > 5 * strength(of: 650, in: samples(.claim)))
        #expect(strongest(of: [630, 700, 770], in: samples(.needsReview), part: 0.0...0.36) == 700)
        #expect(strongest(of: [630, 700, 770], in: samples(.needsReview), part: 0.64...1.0) == 700)
        let bust = samples(.bust)
        #expect(strength(of: 420, in: bust) > 5 * strength(of: 280, in: bust))
        #expect(strength(of: 700, in: bust) > 5 * strength(of: 560, in: bust))
    }

    @Test func risingEffects_rise() {
        // 660 → 880 Hz, 440 → 550 Hz.
        let scoreUp = samples(.scoreUp)
        #expect(strongest(of: [660, 880], in: scoreUp, part: 0.0...0.4) == 660)
        #expect(strongest(of: [660, 880], in: scoreUp, part: 0.55...1.0) == 880)
        let turnChange = samples(.turnChange)
        #expect(strongest(of: [440, 550], in: turnChange, part: 0.0...0.45) == 440)
        #expect(strongest(of: [440, 550], in: turnChange, part: 0.55...1.0) == 550)
        // 300 → 1 200 Hz, an exponential glide: 300, 600 and 1 200 Hz at the start, the middle and the end.
        let powerUp = samples(.powerUp)
        let climb = [pitch(powerUp, in: 0.05...0.25), pitch(powerUp, in: 0.4...0.6), pitch(powerUp, in: 0.75...0.95)]
        #expect(climb == climb.sorted() && climb[0] < 450 && climb[2] > 800)
        #expect(abs(pitch(powerUp, in: 0.45...0.55) - 600) < 60)
        // Three notes of a rising arpeggio, each one entering after the one below it.
        let heal = samples(.heal)
        #expect(strongest(of: [523.25, 659.25, 783.99], in: heal, part: 0.0...0.2) == 523.25)
        #expect(strength(of: 783.99, in: heal, part: 0.0...0.45) < 0.2 * strength(of: 783.99, in: heal, part: 0.55...1.0))
        #expect(strength(of: 659.25, in: heal, part: 0.0...0.2) < 0.2 * strength(of: 659.25, in: heal, part: 0.3...0.5))
    }

    @Test func fallingEffects_fall() {
        // 600 → 300 Hz.
        let halved = samples(.halved)
        let slide = [pitch(halved, in: 0.05...0.25), pitch(halved, in: 0.4...0.6), pitch(halved, in: 0.75...0.95)]
        #expect(slide == slide.sorted(by: >) && slide[0] > 480 && slide[2] < 370)
        // Three falling notes: A, F, C.
        let eliminated = samples(.eliminated)
        let notes = [440.0, 349.23, 261.63]
        #expect(strongest(of: notes, in: eliminated, part: 0.02...0.31) == 440)
        #expect(strongest(of: notes, in: eliminated, part: 0.35...0.64) == 349.23)
        #expect(strongest(of: notes, in: eliminated, part: 0.68...0.98) == 261.63)
        // Three falling beeps.
        let alert = samples(.alert)
        let beeps = [880.0, 740, 622.25]
        #expect(strongest(of: beeps, in: alert, part: 0.0...0.26) == 880)
        #expect(strongest(of: beeps, in: alert, part: 0.34...0.60) == 740)
        #expect(strongest(of: beeps, in: alert, part: 0.68...1.0) == 622.25)
        // 220 → 110 Hz under its noise.
        let damage = samples(.damage)
        #expect(strength(of: 200, in: damage, part: 0.0...0.3) > strength(of: 120, in: damage, part: 0.0...0.3))
        #expect(strength(of: 120, in: damage, part: 0.6...1.0) > strength(of: 200, in: damage, part: 0.6...1.0))
    }

    @Test func zoneMove_sweepsUpAndBack() {
        let sweep = samples(.zoneMove)
        let start = pitch(sweep, in: 0.03...0.13)
        let middle = pitch(sweep, in: 0.45...0.55)
        let end = pitch(sweep, in: 0.87...0.97)
        #expect(middle > 1.5 * start && middle > 1.5 * end)
        #expect(abs(start - end) < 80)
    }

    @Test func dartThatDoesNothing_soundsDullerThanOneThatScores() {
        // The impact carries a burst of noise; the dull dart is a bare, lower thud.
        #expect(brightness(samples(.dartImpact)) > 2 * brightness(samples(.dartDull)))
        #expect(strength(of: 110, in: samples(.dartDull)) > 3 * strength(of: 110, in: samples(.dartImpact)))
    }

    @Test func longFanfares_areMadeOfTheNotesOfTheirChord() {
        // Fanfare: C5, E5, G5, C6 one after the other, then held together.
        let fanfare = samples(.fanfare)
        let chord = [523.25, 659.25, 783.99, 1_046.5]
        for (index, note) in chord.enumerated() {
            let from = 0.1 * Double(index) / 1.1
            #expect(strongest(of: chord, in: fanfare, part: from...(from + 0.09 / 1.1)) == note, "note \(index + 1)")
        }
        for note in chord {
            #expect(strength(of: note, in: fanfare, part: 0.45...0.9) > 4 * strength(of: note * 1.09, in: fanfare, part: 0.45...0.9))
        }
        // Victory: six notes, G4 C5 E5 G5 E5 C6, the last one held.
        let victory = samples(.victory)
        let melody: [(start: Double, note: Double)] = [(0, 392), (0.13, 523.25), (0.26, 659.25), (0.39, 783.99), (0.56, 659.25), (0.69, 1_046.5)]
        let pitches = [392, 523.25, 659.25, 783.99, 1_046.5]
        for (start, note) in melody.dropLast() {
            #expect(strongest(of: pitches, in: victory, part: (start / 1.5)...((start + 0.11) / 1.5)) == note, "note at \(start) s")
        }
        #expect(strongest(of: [880, 987.77, 1_046.5, 1_174.66], in: victory, part: 0.5...0.95) == 1_046.5)
    }

    @Test func noiseEffects_areBrighterThanTheTones() {
        // Two clicks of noise: many crossings, and a gap between the two clicks.
        let shutter = samples(.shutter)
        #expect(pitch(shutter, in: 0.0...0.2) > 1_000)
        #expect(brightness(shutter) > 3 * brightness(samples(.dartDull)))
        let gap = shutter[Int(0.036 * Self.sampleRate)..<Int(0.052 * Self.sampleRate)]
        #expect(rootMeanSquare(gap) < 0.25 * rootMeanSquare(shutter))
    }

    @Test func twoPartEffects_haveTheirSilenceBetweenTheParts() {
        // Two identical beeps, three falling beeps: the pauses are really there.
        let review = samples(.needsReview)
        let pause = review[Int(0.09 * Self.sampleRate)..<Int(0.13 * Self.sampleRate)]
        #expect(rootMeanSquare(pause) < 0.01)
        let first = Array(review[0..<Int(0.08 * Self.sampleRate)])
        let second = Array(review[Int(0.14 * Self.sampleRate)..<Int(0.22 * Self.sampleRate)])
        #expect(abs(rootMeanSquare(first) - rootMeanSquare(second)) < 0.02)
        let alert = samples(.alert)
        #expect(rootMeanSquare(alert[Int(0.14 * Self.sampleRate)..<Int(0.165 * Self.sampleRate)]) < 0.01)
        #expect(rootMeanSquare(alert[Int(0.31 * Self.sampleRate)..<Int(0.335 * Self.sampleRate)]) < 0.01)
    }

    @Test func longEffects_holdTheirLastChord() {
        // The fanfare and the victory end on a held chord, not on a short note: there is still sound late.
        let fanfare = samples(.fanfare)
        #expect(rootMeanSquare(fanfare[Int(0.6 * Self.sampleRate)..<Int(0.9 * Self.sampleRate)]) > 0.05)
        let victory = samples(.victory)
        #expect(rootMeanSquare(victory[Int(0.9 * Self.sampleRate)..<Int(1.2 * Self.sampleRate)]) > 0.05)
    }
}
