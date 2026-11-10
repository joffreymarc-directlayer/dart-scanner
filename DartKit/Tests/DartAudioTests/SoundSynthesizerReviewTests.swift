import Foundation
import Testing
import DartAudio

/// Adversarial review of the synthesised effects (ARCHITECTURE.md §7.7), measured on the samples: every usable
/// sample rate up to 192 kHz, the limits of the range, DC offset, the end points of the glides, and how loud the
/// effects are next to each other once weighted as the ear hears them (ITU-R BS.1770 K-weighting).
@Suite struct SoundSynthesizerReviewTests {
    /// The "Durée" column of §7.7.
    private static let durations: [SoundEffect: Double] = [
        .dartImpact: 0.12, .dartDull: 0.10, .scoreUp: 0.18, .tick: 0.05, .lock: 0.15, .powerUp: 0.45, .damage: 0.25,
        .heal: 0.35, .claim: 0.30, .eliminated: 0.60, .bust: 0.45, .halved: 0.40, .highTurn: 0.35, .fanfare: 1.10,
        .victory: 1.50, .turnChange: 0.20, .zoneMove: 0.30, .needsReview: 0.22, .rejected: 0.18, .shutter: 0.12,
        .confirm: 0.15, .alert: 0.50,
    ]

    @Test(arguments: [8_000.0, 11_025, 16_000, 22_050, 32_000, 44_100, 48_000, 88_200, 96_000, 176_400, 192_000])
    func everyUsableRate_keepsEveryConstraint(_ sampleRate: Double) {
        for effect in SoundEffect.allCases {
            let samples = SoundSynthesizer.samples(for: effect, sampleRate: sampleRate)
            let expected = Self.durations[effect] ?? 0
            let seconds = Double(samples.count) / sampleRate
            #expect(abs(seconds - expected) <= 1 / sampleRate && seconds >= 0.05 && seconds <= 1.5, "\(effect) @ \(sampleRate)")
            #expect(samples.allSatisfy { $0.isFinite }, "\(effect) @ \(sampleRate)")
            let peak = samples.reduce(Float(0)) { max($0, abs($1)) }
            #expect(peak <= 0.9 && peak >= 0.25, "\(effect) @ \(sampleRate): peak \(peak)")
            // No click: silence at both ends, and nothing faster than a straight 3 ms ramp to the allowed peak.
            #expect(samples.first == 0 && samples.last == 0, "\(effect) @ \(sampleRate)")
            let fade = Int((0.003 * sampleRate).rounded(.up))
            for index in 0..<fade {
                let ceiling = 0.9 * Float(index) / Float(fade) + 1e-6
                #expect(abs(samples[index]) <= ceiling && abs(samples[samples.count - 1 - index]) <= ceiling, "\(effect) @ \(sampleRate)")
            }
            // No DC offset to push the speaker off its rest position.
            let mean = samples.reduce(0.0) { $0 + Double($1) } / Double(samples.count)
            #expect(abs(mean) < 0.01, "\(effect) @ \(sampleRate): mean \(mean)")
        }
    }

    @Test func rangeOfSampleRates_isClosed_andNothingOutsideItTraps() {
        for sampleRate in [8_000.0, 192_000.0] {
            #expect(!SoundSynthesizer.samples(for: .victory, sampleRate: sampleRate).isEmpty)
        }
        let outside = [7_999.999, 192_000.001, 0, -0.0, .leastNonzeroMagnitude, -8_000, .greatestFiniteMagnitude, .nan, .signalingNaN, .infinity]
        for sampleRate in outside {
            for effect in SoundEffect.allCases {
                #expect(SoundSynthesizer.samples(for: effect, sampleRate: sampleRate).isEmpty, "\(sampleRate)")
            }
        }
    }

    @Test func synthesis_isTheSameFromSeveralTasksAtOnce() async {
        // A pure function: no shared state, so concurrent calls give the very same samples.
        let reference = SoundEffect.allCases.map { SoundSynthesizer.samples(for: $0, sampleRate: 44_100) }
        let results = await withTaskGroup(of: [[Float]].self) { group in
            for _ in 0..<6 {
                group.addTask { SoundEffect.allCases.map { SoundSynthesizer.samples(for: $0, sampleRate: 44_100) } }
            }
            var all: [[[Float]]] = []
            for await result in group { all.append(result) }
            return all
        }
        #expect(results.count == 6 && results.allSatisfy { $0 == reference })
    }

    // MARK: - Glides end where the recipe says

    /// Frequency of the part `range` (fractions of the buffer), from its zero crossings.
    private func pitch(_ samples: [Float], _ range: ClosedRange<Double>, sampleRate: Double) -> Double {
        let first = Int(Double(samples.count) * range.lowerBound)
        let last = Int(Double(samples.count) * range.upperBound) - 1
        var crossings = 0
        for index in (first + 1)...last where (samples[index - 1] < 0) != (samples[index] < 0) {
            crossings += 1
        }
        return Double(crossings) / 2 / (Double(last - first) / sampleRate)
    }

    @Test(arguments: [22_050.0, 44_100, 48_000])
    func glides_startAndEndOnTheirPitches(_ sampleRate: Double) {
        // Exponential glides: at a fraction p of the tone, from · (to / from)^p.
        let glides: [(SoundEffect, from: Double, to: Double)] = [(.powerUp, 300, 1_200), (.halved, 600, 300)]
        for (effect, from, to) in glides {
            let samples = SoundSynthesizer.samples(for: effect, sampleRate: sampleRate)
            for (range, p) in [(0.04...0.10, 0.07), (0.47...0.53, 0.5), (0.74...0.80, 0.77)] {
                let expected = from * pow(to / from, p)
                let measured = pitch(samples, range, sampleRate: sampleRate)
                #expect(abs(measured - expected) < 0.12 * expected, "\(effect) @ \(sampleRate): \(measured) Hz at \(p), expected \(expected)")
            }
        }
    }

    // MARK: - Balance

    private struct Biquad {
        var b0, b1, b2, a1, a2: Double
        var z1 = 0.0, z2 = 0.0

        mutating func callAsFunction(_ x: Double) -> Double {
            let y = b0 * x + z1
            z1 = b1 * x - a1 * y + z2
            z2 = b2 * x - a2 * y
            return y
        }
    }

    /// The two stages of the K-weighting of ITU-R BS.1770, at any sample rate.
    private func kWeighting(_ fs: Double) -> [Biquad] {
        let gain = 3.999843853973347, shelfFrequency = 1_681.974450955533, shelfQ = 0.7071752369554196
        let a = pow(10, gain / 40), w = 2 * Double.pi * shelfFrequency / fs, alpha = sin(w) / (2 * shelfQ)
        let a0 = (a + 1) - (a - 1) * cos(w) + 2 * a.squareRoot() * alpha
        let shelf = Biquad(b0: a * ((a + 1) + (a - 1) * cos(w) + 2 * a.squareRoot() * alpha) / a0,
                           b1: -2 * a * ((a - 1) + (a + 1) * cos(w)) / a0,
                           b2: a * ((a + 1) + (a - 1) * cos(w) - 2 * a.squareRoot() * alpha) / a0,
                           a1: 2 * ((a - 1) - (a + 1) * cos(w)) / a0,
                           a2: ((a + 1) - (a - 1) * cos(w) - 2 * a.squareRoot() * alpha) / a0)
        let highFrequency = 38.13547087602444, highQ = 0.5003270373238773
        let w2 = 2 * Double.pi * highFrequency / fs, alpha2 = sin(w2) / (2 * highQ), b0 = 1 + alpha2
        let highPass = Biquad(b0: (1 + cos(w2)) / 2 / b0, b1: -(1 + cos(w2)) / b0, b2: (1 + cos(w2)) / 2 / b0,
                              a1: -2 * cos(w2) / b0, a2: (1 - alpha2) / b0)
        return [shelf, highPass]
    }

    /// Loudest K-weighted level over a sliding window of 100 ms, about the time the ear takes to sum a short sound.
    private func loudness(_ samples: [Float], sampleRate: Double) -> Double {
        var filters = kWeighting(sampleRate)
        let window = Int(0.1 * sampleRate)
        let padded = samples.map(Double.init) + [Double](repeating: 0, count: window)
        let weighted = padded.map { sample in
            var value = sample
            for index in filters.indices { value = filters[index](value) }
            return value * value
        }
        var sum = weighted.prefix(window).reduce(0, +)
        var loudest = sum
        for index in window..<weighted.count {
            sum += weighted[index] - weighted[index - window]
            loudest = max(loudest, sum)
        }
        return -0.691 + 10 * log10(max(loudest / Double(window), 1e-12))
    }

    @Test func effects_areWithinTwelveDecibelsOfEachOther_asTheEarWeighsThem() {
        let levels = SoundEffect.allCases.map { ($0, loudness(SoundSynthesizer.samples(for: $0, sampleRate: 48_000), sampleRate: 48_000)) }
        let quietest = levels.min { $0.1 < $1.1 }
        let loudest = levels.max { $0.1 < $1.1 }
        #expect((loudest?.1 ?? 0) - (quietest?.1 ?? 0) < 12, "\(levels)")
        // Loud enough to be heard over a game, never at full scale.
        #expect(levels.allSatisfy { $0.1 > -24 && $0.1 < -6 }, "\(levels)")
        // The end of a game is never quieter than the sound of a dart.
        let level = Dictionary(uniqueKeysWithValues: levels)
        #expect((level[.victory] ?? 0) > (level[.dartImpact] ?? 0) && (level[.fanfare] ?? 0) > (level[.dartImpact] ?? 0))
    }
}
