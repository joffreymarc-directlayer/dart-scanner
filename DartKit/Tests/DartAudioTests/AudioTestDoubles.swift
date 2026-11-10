import Foundation
import DartCore
@testable import DartAudio

// Stand-ins for the outputs of `AudioDirector`, shared by `ScoreCallerTests` and `AudioDirectorTests`.
// They play nothing and remember what they were asked, so that every test runs without audio hardware.

/// A speech engine that records its orders. A sentence "ends" when the test says so.
@MainActor
final class AudioTestVoice: ScoreCallerVoice {
    struct Sentence: Equatable {
        var text: String
        var id: Int
        var language: AppLanguage
        var volume: Float
        var ducksOthers: Bool
    }

    enum Order: Equatable {
        case warmUp(language: AppLanguage, ducksOthers: Bool)
        case speak(Sentence)
        case stop
        case reset
    }

    var onEnd: ((Int) -> Void)?
    private(set) var orders: [Order] = []

    /// The sentences asked for, in order.
    var sentences: [Sentence] {
        orders.compactMap { if case .speak(let sentence) = $0 { return sentence } else { return nil } }
    }

    /// The texts asked for, in order.
    var spoken: [String] { sentences.map(\.text) }

    /// Number of `stop()` so far.
    var stops: Int { orders.filter { $0 == .stop }.count }

    func warmUp(language: AppLanguage, ducksOthers: Bool) {
        orders.append(.warmUp(language: language, ducksOthers: ducksOthers))
    }

    func speak(_ text: String, id: Int, language: AppLanguage, volume: Float, ducksOthers: Bool) {
        orders.append(.speak(Sentence(text: text, id: id, language: language, volume: volume, ducksOthers: ducksOthers)))
    }

    func stop() {
        orders.append(.stop)
    }

    func reset() {
        orders.append(.reset)
    }

    /// The last sentence asked for has been said to its end.
    func finishLast() {
        guard let last = sentences.last else { return }
        onEnd?(last.id)
    }

    /// Reports the end of the sentence said `index`-th, as a late or duplicated callback would.
    func finish(at index: Int) {
        onEnd?(sentences[index].id)
    }
}

/// A clock driven by hand: actions wait until the test advances the time.
@MainActor
final class AudioTestClock {
    private(set) var now: TimeInterval = 0
    private var waiting: [(due: TimeInterval, order: Int, action: @MainActor () -> Void)] = []
    private var scheduled = 0

    /// Number of actions still waiting.
    var pending: Int { waiting.count }

    /// Delays of the actions still waiting, from now, earliest first.
    var pendingDelays: [TimeInterval] {
        waiting.map { $0.due - now }.sorted()
    }

    var scheduler: AudioScheduler {
        { [self] delay, action in
            scheduled += 1
            waiting.append((now + delay, scheduled, action))
        }
    }

    /// Moves the time forward and runs what became due, earliest first, in scheduling order on a tie.
    func advance(by seconds: TimeInterval) {
        let target = now + seconds
        while let next = waiting.filter({ $0.due <= target + 1e-9 }).min(by: { ($0.due, $0.order) < ($1.due, $1.order) }) {
            waiting.removeAll { $0.order == next.order }
            now = max(now, next.due)
            next.action()
        }
        now = target
    }
}

/// Haptics that record the patterns played.
@MainActor
final class AudioTestHaptics: HapticsPlaying {
    var isSupported: Bool
    private(set) var prepared = 0
    private(set) var played: [HapticPattern] = []

    init(isSupported: Bool = true) {
        self.isSupported = isSupported
    }

    func prepare() {
        prepared += 1
    }

    func play(_ pattern: HapticPattern) {
        played.append(pattern)
    }
}

/// The commands sent to the effects player, in a form that compares.
@MainActor
final class AudioTestEffects {
    enum Order: Equatable {
        case prepare(playsInSilentMode: Bool, volume: Float)
        case configure(playsInSilentMode: Bool, volume: Float)
        case play(SoundEffect, after: TimeInterval)
        case stopAll
        case setActive(Bool)
        case other
    }

    private(set) var orders: [Order] = []

    /// The effects asked for, with their delays.
    var played: [Order] {
        orders.filter { if case .play = $0 { return true } else { return false } }
    }

    func receive(_ command: EffectsPlayer.Command) {
        switch command {
        case .prepare(let configuration):
            orders.append(.prepare(playsInSilentMode: configuration.playsInSilentMode, volume: configuration.volume))
        case .configure(let configuration):
            orders.append(.configure(playsInSilentMode: configuration.playsInSilentMode, volume: configuration.volume))
        case .play(let effect, let delay):
            orders.append(.play(effect, after: delay))
        case .stopAll:
            orders.append(.stopAll)
        case .setActive(let active):
            orders.append(.setActive(active))
        case .report(let continuation):
            continuation.resume(returning: EffectsPlayer.Status(isPrepared: false, isActive: true, bufferCount: 0,
                                                                hasEngine: false, isRunning: false, volume: 0))
            orders.append(.other)
        case .reportDueEffects(let continuation):
            continuation.resume(returning: 0)
            orders.append(.other)
        case .engineConfigurationChanged, .session:
            orders.append(.other)
        }
    }

    func forget() {
        orders.removeAll()
    }
}
