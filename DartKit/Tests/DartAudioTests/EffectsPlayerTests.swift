import Foundation
import Testing
@testable import DartAudio

/// `EffectsPlayer` (ARCHITECTURE.md §7.4) with the real `AVAudioEngine`, at volume 0. On a machine with an audio
/// output the engine really starts, pauses and restarts; on a machine without one nothing is built. In both
/// cases nothing may trap, and nothing is heard.
@Suite struct EffectsPlayerTests {
    private let silent = EffectsPlayer.Configuration(playsInSilentMode: true, volume: 0)

    /// A player that handles its commands until `mailbox` is finished.
    private func makePlayer() -> (player: EffectsPlayer, mailbox: AsyncStream<EffectsPlayer.Command>.Continuation) {
        let (commands, mailbox) = AsyncStream<EffectsPlayer.Command>.makeStream()
        let player = EffectsPlayer(mailbox: mailbox)
        Task { await player.run(commands) }
        return (player, mailbox)
    }

    /// The status once every command sent so far has been handled.
    private func status(_ mailbox: AsyncStream<EffectsPlayer.Command>.Continuation) async -> EffectsPlayer.Status {
        await withCheckedContinuation { mailbox.yield(.report($0)) }
    }

    @Test func beforePrepare_nothingIsBuilt_andEveryCommandIsHarmless() async {
        let (_, mailbox) = makePlayer()
        defer { mailbox.finish() }
        for command: EffectsPlayer.Command in [
            .play(.fanfare, after: 0), .play(.tick, after: 0.01), .stopAll, .setActive(false), .setActive(true),
            .configure(EffectsPlayer.Configuration(playsInSilentMode: false, volume: 0)), .engineConfigurationChanged,
            .session(.interruptionBegan), .session(.interruptionEnded), .session(.mediaServicesWereReset),
        ] {
            mailbox.yield(command)
        }
        let status = await status(mailbox)
        #expect(!status.isPrepared && status.isActive && !status.hasEngine && !status.isRunning && status.bufferCount == 0)
    }

    @Test func prepare_synthesisesEveryEffect_once_andIsIdempotent() async {
        let (_, mailbox) = makePlayer()
        defer { mailbox.finish() }
        mailbox.yield(.prepare(silent))
        let first = await status(mailbox)
        #expect(first.isPrepared && first.bufferCount == SoundEffect.allCases.count)
        // With an output the engine runs; without one it is not even built.
        #expect(first.isRunning == first.hasEngine && first.volume == 0)
        mailbox.yield(.prepare(silent))
        mailbox.yield(.prepare(silent))
        #expect(await status(mailbox) == first)
    }

    @Test func play_stop_andDelays_neverTrap() async {
        let (_, mailbox) = makePlayer()
        defer { mailbox.finish() }
        mailbox.yield(.prepare(silent))
        let prepared = await status(mailbox)
        // More effects at once than there are player nodes, then delayed ones, then odd delays.
        for effect in SoundEffect.allCases {
            mailbox.yield(.play(effect, after: 0))
        }
        for (index, effect) in SoundEffect.allCases.enumerated() {
            mailbox.yield(.play(effect, after: 0.001 * Double(index)))
        }
        mailbox.yield(.play(.tick, after: -1))
        mailbox.yield(.play(.tick, after: .nan))
        mailbox.yield(.play(.tick, after: .infinity))
        try? await Task.sleep(nanoseconds: 60_000_000)
        mailbox.yield(.stopAll)
        mailbox.yield(.stopAll)
        #expect(await status(mailbox) == prepared)
    }

    /// Effects whose time came and that nothing cancelled, once every command sent so far has been handled.
    private func due(_ mailbox: AsyncStream<EffectsPlayer.Command>.Continuation) async -> Int {
        await withCheckedContinuation { mailbox.yield(.reportDueEffects($0)) }
    }

    /// Waits (5 s at most) until `due` reaches `count`; the count reached.
    private func due(_ mailbox: AsyncStream<EffectsPlayer.Command>.Continuation, reaching count: Int) async -> Int {
        for _ in 0..<500 {
            let now = await due(mailbox)
            if now >= count { return now }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        return await due(mailbox)
    }

    @Test func delayedEffects_comeAtTheirTime_unlessSomethingSilencesThePlayerFirst() async {
        let (_, mailbox) = makePlayer()
        defer { mailbox.finish() }
        mailbox.yield(.prepare(silent))
        // An effect without delay is due at once; a delayed one, at its time.
        mailbox.yield(.play(.dartImpact, after: 0))
        #expect(await due(mailbox) == 1)
        mailbox.yield(.play(.tick, after: 0.02))
        #expect(await due(mailbox, reaching: 2) == 2)

        // Each of these silences what was still to come: stopAll, the background, an interruption, a reset of
        // the media server. One at a time, so that none hides another. After each, a lock asked later and due
        // later is not cancelled: once it is due, the tick's time has long passed, and only the lock counted.
        let silencers: [(name: String, commands: [EffectsPlayer.Command])] = [
            ("stopAll", [.stopAll]),
            ("background", [.setActive(false), .setActive(true)]),
            ("interruption", [.session(.interruptionBegan), .session(.interruptionEnded)]),
            ("media server reset", [.session(.mediaServicesWereReset)]),
        ]
        for (name, commands) in silencers {
            let before = await due(mailbox)
            mailbox.yield(.play(.tick, after: 0.02))
            for command in commands {
                mailbox.yield(command)
            }
            mailbox.yield(.play(.lock, after: 0.08))
            _ = await due(mailbox, reaching: before + 1)
            try? await Task.sleep(nanoseconds: 100_000_000)
            #expect(await due(mailbox) == before + 1, "\(name)")
        }

        // In the background nothing becomes due, not even what was asked before leaving.
        let before = await due(mailbox)
        mailbox.yield(.play(.tick, after: 0.03))
        mailbox.yield(.setActive(false))
        mailbox.yield(.play(.tick, after: 0))
        try? await Task.sleep(nanoseconds: 100_000_000)
        #expect(await due(mailbox) == before)
        mailbox.yield(.setActive(true))
        mailbox.yield(.play(.tick, after: 0))
        #expect(await due(mailbox) == before + 1)
    }

    @Test func background_pausesTheEngine_foreground_restartsIt() async {
        let (_, mailbox) = makePlayer()
        defer { mailbox.finish() }
        mailbox.yield(.prepare(silent))
        let prepared = await status(mailbox)
        mailbox.yield(.setActive(false))
        mailbox.yield(.play(.victory, after: 0))
        let paused = await status(mailbox)
        #expect(!paused.isActive && !paused.isRunning && paused.hasEngine == prepared.hasEngine)
        // `prepare` while in the background does not start the engine behind the user's back.
        mailbox.yield(.prepare(silent))
        #expect(await status(mailbox) == paused)
        mailbox.yield(.setActive(true))
        mailbox.yield(.setActive(true))
        #expect(await status(mailbox) == prepared)
    }

    @Test func settings_changeTheVolume_andRestartTheEngineForANewCategory() async {
        let (_, mailbox) = makePlayer()
        defer { mailbox.finish() }
        mailbox.yield(.prepare(silent))
        let prepared = await status(mailbox)
        mailbox.yield(.configure(EffectsPlayer.Configuration(playsInSilentMode: false, volume: 0)))
        #expect(await status(mailbox) == prepared)
        mailbox.yield(.configure(EffectsPlayer.Configuration(playsInSilentMode: true, volume: 0)))
        mailbox.yield(.play(.confirm, after: 0))
        #expect(await status(mailbox) == prepared)
    }

    @Test func systemEvents_areSurvived_andTheEngineComesBack() async {
        let (_, mailbox) = makePlayer()
        defer { mailbox.finish() }
        mailbox.yield(.prepare(silent))
        let prepared = await status(mailbox)

        // A call interrupts the audio, then ends.
        mailbox.yield(.session(.interruptionBegan))
        mailbox.yield(.session(.interruptionEnded))
        mailbox.yield(.play(.tick, after: 0))
        #expect(await status(mailbox) == prepared)

        // The output changes while the engine runs, then after it stopped (here: paused by the background).
        mailbox.yield(.engineConfigurationChanged)
        #expect(await status(mailbox) == prepared)
        mailbox.yield(.setActive(false))
        mailbox.yield(.engineConfigurationChanged)
        let reconnected = await status(mailbox)
        #expect(!reconnected.isRunning && reconnected.hasEngine == prepared.hasEngine)
        mailbox.yield(.setActive(true))
        mailbox.yield(.play(.tick, after: 0))
        #expect(await status(mailbox) == prepared)

        // The media server restarts: everything is rebuilt, and plays again.
        mailbox.yield(.session(.mediaServicesWereReset))
        mailbox.yield(.play(.fanfare, after: 0))
        #expect(await status(mailbox) == prepared)
    }

    @Test func endOfTheStream_letsGoOfTheEngine() async {
        let (commands, mailbox) = AsyncStream<EffectsPlayer.Command>.makeStream()
        let player = EffectsPlayer(mailbox: mailbox)
        let running = Task { await player.run(commands) }
        mailbox.yield(.prepare(silent))
        _ = await status(mailbox)
        // What `AudioDirector` does when it goes away.
        mailbox.finish()
        await running.value
        // The player is still there (this test holds it), with nothing left running.
        let (more, second) = AsyncStream<EffectsPlayer.Command>.makeStream()
        Task { await player.run(more) }
        let after = await status(second)
        second.finish()
        #expect(after.isPrepared && !after.hasEngine && !after.isRunning)
    }
}
