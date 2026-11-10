// DartAudio — playback of the synthesised effects: AVAudioEngine and its player nodes (ARCHITECTURE.md §7.4).
import Foundation
import AVFoundation

/// One `AVAudioEngine` and four player nodes used in turn, all connected to the main mixer in one fixed format
/// (mono, 44 100 Hz, float); the mixer converts to whatever the output wants.
///
/// The engine and the audio session are only ever touched on the private serial queue of this actor, which is
/// the private serial queue of `AudioDirector` (ARCHITECTURE.md §11): activating a session blocks, and must
/// never do so on the main thread. Everything arrives as a `Command` through one stream, read by `run(_:)`, so
/// the commands of the main thread and the notifications of the system are handled one at a time, in order.
///
/// Nothing here throws or waits: when the engine cannot start (no audio output, session error), the effects
/// are skipped until the next `prepare` or `setActive(true)`.
actor EffectsPlayer {
    /// The two settings the engine depends on.
    struct Configuration: Hashable, Sendable {
        /// true: `.playback` (audible with the Silent switch on). false: `.ambient`.
        var playsInSilentMode: Bool
        /// 0...1, the output volume of the main mixer.
        var volume: Float
    }

    enum Command: Sendable {
        /// Session category, buffers, engine, start. Idempotent; also retries an engine that could not start.
        case prepare(Configuration)
        /// The settings changed.
        case configure(Configuration)
        /// Plays `effect` after `delay` seconds, unless a `stopAll` comes first.
        case play(SoundEffect, after: TimeInterval)
        case stopAll
        /// false: the app leaves the foreground, the engine is paused. true: it is started again.
        case setActive(Bool)
        /// The output changed and the engine stopped itself (`AVAudioEngineConfigurationChange`).
        case engineConfigurationChanged
        case session(AudioSessionController.Event)
        /// Answered once every command sent before it has been handled. For the tests.
        case report(CheckedContinuation<Status, Never>)
        /// Answered with `dueEffects`, once every command sent before it has been handled. For the tests.
        case reportDueEffects(CheckedContinuation<Int, Never>)
    }

    /// Where the player stands. Nothing in the service reads it: it lets the tests check the real engine.
    struct Status: Hashable, Sendable {
        var isPrepared: Bool
        var isActive: Bool
        /// Number of effects synthesised and kept as buffers.
        var bufferCount: Int
        /// False while there is no audio output to build an engine on.
        var hasEngine: Bool
        var isRunning: Bool
        var volume: Float
    }

    static let sampleRate = 44_100.0
    static let voiceCount = 4

    private let queue = DispatchSerialQueue(label: "DartAudio.EffectsPlayer")
    nonisolated var unownedExecutor: UnownedSerialExecutor { queue.asUnownedSerialExecutor() }

    /// Where the notification observers put their commands: the same stream as everybody else.
    private let mailbox: AsyncStream<Command>.Continuation

    private var configuration = Configuration(playsInSilentMode: true, volume: 0.8)
    private var isPrepared = false
    private var isActive = true
    /// Bumped by everything that silences the player: a delayed effect of an older epoch is not played.
    private var epoch = 0
    /// Effects whose time came while the app was in the foreground and that nothing cancelled: those that a
    /// running engine plays. Nothing in the service reads it: it lets the tests see the delays and their
    /// cancellation on any machine, with or without an audio output.
    private var dueEffects = 0

    private var engine: AVAudioEngine?
    private var nodes: [AVAudioPlayerNode] = []
    private var buffers: [SoundEffect: AVAudioPCMBuffer] = [:]
    private var nextNode = 0
    private var configurationObservation: AudioNotificationObservation?

    init(mailbox: AsyncStream<Command>.Continuation) {
        self.mailbox = mailbox
    }

    /// Handles the commands one by one until the stream ends, then lets go of the engine.
    func run(_ commands: AsyncStream<Command>) async {
        for await command in commands {
            handle(command)
        }
        dismantleEngine()
    }

    private func handle(_ command: Command) {
        switch command {
        case .prepare(let configuration):
            prepare(configuration)
        case .configure(let configuration):
            configure(configuration)
        case .play(let effect, let delay):
            play(effect, after: delay)
        case .stopAll:
            stopAll()
        case .setActive(let active):
            setActive(active)
        case .engineConfigurationChanged:
            reconnectAndRestart()
        case .session(.interruptionBegan):
            // The system stopped the engine. What was still to come is forgotten.
            stopAll()
        case .session(.interruptionEnded):
            startEngine()
        case .session(.mediaServicesWereReset):
            // Every audio object is stale: engine, nodes and buffers are rebuilt.
            dismantleEngine()
            buffers.removeAll()
            if isPrepared { prepare(configuration) }
        case .report(let continuation):
            continuation.resume(returning: Status(isPrepared: isPrepared, isActive: isActive, bufferCount: buffers.count,
                                                  hasEngine: engine != nil, isRunning: engine?.isRunning ?? false,
                                                  volume: engine?.mainMixerNode.outputVolume ?? configuration.volume))
        case .reportDueEffects(let continuation):
            continuation.resume(returning: dueEffects)
        }
    }

    // MARK: - Commands

    private func prepare(_ configuration: Configuration) {
        self.configuration = configuration
        isPrepared = true
        if buffers.isEmpty { synthesizeBuffers() }
        _ = AudioSessionController.configure(playsInSilentMode: configuration.playsInSilentMode)
        engine?.mainMixerNode.outputVolume = configuration.volume
        // Builds the engine if needed (with the volume above) and starts it.
        startEngine()
    }

    private func configure(_ configuration: Configuration) {
        let previous = self.configuration
        self.configuration = configuration
        engine?.mainMixerNode.outputVolume = configuration.volume
        guard isPrepared, previous.playsInSilentMode != configuration.playsInSilentMode else { return }
        // Same sequence as `prepare`: new category, then the engine is restarted.
        engine?.stop()
        _ = AudioSessionController.configure(playsInSilentMode: configuration.playsInSilentMode)
        startEngine()
    }

    private func play(_ effect: SoundEffect, after delay: TimeInterval) {
        guard delay > 0 else {
            playNow(effect)
            return
        }
        let epoch = self.epoch
        Task {
            try? await Task.sleep(nanoseconds: UInt64(min(delay, AudioCueFilter.maximumDelay) * 1_000_000_000))
            guard epoch == self.epoch else { return }
            self.playNow(effect)
        }
    }

    /// `scheduleBuffer` on the next node with `.interrupts`, then `play()`.
    private func playNow(_ effect: SoundEffect) {
        guard isActive else { return }
        dueEffects += 1
        // A node started while the engine is stopped raises an exception: the effect is skipped instead.
        guard let engine, engine.isRunning, !nodes.isEmpty, let buffer = buffers[effect] else { return }
        let node = nodes[nextNode % nodes.count]
        nextNode = (nextNode + 1) % nodes.count
        node.scheduleBuffer(buffer, at: nil, options: .interrupts, completionHandler: nil)
        node.play()
    }

    private func stopAll() {
        epoch += 1
        for node in nodes {
            node.stop()
        }
    }

    private func setActive(_ active: Bool) {
        isActive = active
        if active {
            startEngine()
        } else {
            stopAll()
            engine?.pause()
        }
    }

    // MARK: - Engine

    /// The one format of every buffer and every player node. A buffer whose format differs from its node's fails.
    private static var format: AVAudioFormat? {
        AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false)
    }

    /// Without an output device the hardware format has no channel or no sample rate, and connecting to it
    /// raises an exception: the engine is not built, nor started, on such a format.
    static func canPlay(sampleRate: Double, channelCount: Int) -> Bool {
        sampleRate.isFinite && sampleRate > 0 && channelCount > 0
    }

    private static func canPlay(through engine: AVAudioEngine) -> Bool {
        let output = engine.outputNode.outputFormat(forBus: 0)
        return canPlay(sampleRate: output.sampleRate, channelCount: Int(output.channelCount))
    }

    /// Every effect, synthesised once and kept as a PCM buffer.
    private func synthesizeBuffers() {
        guard let format = Self.format else { return }
        for effect in SoundEffect.allCases {
            let samples = SoundSynthesizer.samples(for: effect, sampleRate: Self.sampleRate)
            guard !samples.isEmpty,
                  let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
                  let channel = buffer.floatChannelData?[0] else { continue }
            for (index, sample) in samples.enumerated() {
                channel[index] = sample
            }
            buffer.frameLength = AVAudioFrameCount(samples.count)
            buffers[effect] = buffer
        }
    }

    private func buildEngineIfNeeded() {
        guard engine == nil, let format = Self.format else { return }
        let engine = AVAudioEngine()
        // No audio output: nothing is built, and the next `prepare` or `setActive(true)` tries again.
        guard Self.canPlay(through: engine) else { return }
        let mixer = engine.mainMixerNode
        let nodes = (0..<Self.voiceCount).map { _ in AVAudioPlayerNode() }
        for node in nodes {
            engine.attach(node)
            engine.connect(node, to: mixer, format: format)
        }
        mixer.outputVolume = configuration.volume
        // The handler never touches the engine, and never releases it: it only posts a command to this queue.
        let token = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil
        ) { [mailbox] _ in
            mailbox.yield(.engineConfigurationChanged)
        }
        configurationObservation = AudioNotificationObservation([token])
        self.engine = engine
        self.nodes = nodes
        nextNode = 0
    }

    /// Activates the session, builds the engine if there is none yet, then starts it. Does nothing while the app
    /// is in the background or before `prepare`; an engine that already runs is left alone. A failure leaves the
    /// engine stopped (or unbuilt): effects are skipped until the next `prepare` or `setActive(true)`.
    private func startEngine() {
        guard isPrepared, isActive else { return }
        // The session first, even for an engine that says it runs: after an interruption the session is the
        // part that the system switched off. Activating an active session changes nothing. The engine is built
        // after it, on the output format of the active session's route.
        guard AudioSessionController.activate() else { return }
        buildEngineIfNeeded()
        guard let engine, !engine.isRunning, Self.canPlay(through: engine) else { return }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            // Skipped until the next `prepare` or `setActive(true)`.
        }
    }

    /// The output changed (headphones, Bluetooth, AirPlay) and the engine stopped itself: the connections are
    /// made again for the new output, and the engine is restarted.
    private func reconnectAndRestart() {
        // An engine that still runs did not lose its output: there is nothing to connect again.
        guard let engine, !engine.isRunning, let format = Self.format else { return }
        epoch += 1
        guard Self.canPlay(through: engine) else { return }
        let mixer = engine.mainMixerNode
        engine.connect(mixer, to: engine.outputNode, format: nil)
        for node in nodes {
            engine.connect(node, to: mixer, format: format)
        }
        mixer.outputVolume = configuration.volume
        startEngine()
    }

    private func dismantleEngine() {
        epoch += 1
        configurationObservation = nil
        engine?.stop()
        engine = nil
        nodes = []
    }
}
