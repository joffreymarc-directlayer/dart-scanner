import Foundation
import simd
import Testing
import DartCore
@testable import DartVision

/// The automatic cycle end to end, `SyntheticFrameSource` → `ScanEngine` (VISION.md §10.2, X1 to X4, X12, X16, X17).
@Suite(.serialized, .tags(.heavy)) struct EngineCycleTests {
    /// Calibrated and armed on an empty board, 40 frames played.
    private func armedRun(seed: UInt64) -> EngineRun {
        let run = EngineRun(camera: EngineScenes.debugCamera, seed: seed)
        run.calibrate()
        run.send(.arm(boardConfirmedEmpty: true))
        run.wait(20.0 / 30)
        return run
    }

    @Test func x1_emptyBoardArmsThenWatches() throws {
        let run = EngineRun(camera: EngineScenes.debugCamera, seed: 11)
        #expect(run.calibrate() == [.stateChanged(.idle)])
        #expect(run.send(.arm(boardConfirmedEmpty: true)) == [.stateChanged(.arming)])
        run.wait(40.0 / 30)
        #expect(run.events == [.stateChanged(.idle), .stateChanged(.arming), .stateChanged(.watching(dartsOnBoard: 0))])
        // The first frame restarts the gate and is dropped; the twelfth quiet frame after it ends the arming.
        let watching = try #require(run.log.last)
        #expect(watching.frame == 12)
        #expect(run.engine.state == .watching(dartsOnBoard: 0))
        #expect(run.engine.rolling != nil && run.engine.empty != nil && run.engine.emptyIsFresh)
        #expect(run.engine.lastHealth?.status == .healthy)
        #expect(run.engine.detectionNoise > 0.5 && run.engine.detectionNoise < 3)
    }

    @Test func x2_oneDartGivesOneObservationQuickly() throws {
        let run = armedRun(seed: 12)
        let dart = EngineScenes.steel(30, 75)
        run.play([.throwDart(dart), .wait(1)])
        let observations = run.observations
        try #require(observations.count == 1)
        #expect(run.facts == [.dart(observations[0])])
        #expect(observations[0].best == BoardGeometry.standard.hit(at: dart.tip))
        #expect(observations[0].source == .liveCamera && observations[0].visit == 0 && observations[0].indexInVisit == 0)
        #expect(EngineAccuracy.error(observations[0], dart) < 3)
        let dartFrame = try #require(run.dartFrames.first)
        let lastMotion = try #require(run.lastMotion(before: dartFrame))
        #expect(dartFrame - lastMotion <= 12, "dart at \(dartFrame), last motion at \(lastMotion)")
        #expect(run.engine.state == .watching(dartsOnBoard: 1))
        #expect(run.engine.dartsOnBoard.map(\.id) == [observations[0].id])
    }

    @Test func x3_threeDartsThenATakeoutByHand() throws {
        let run = armedRun(seed: 13)
        let darts = [EngineScenes.steel(-40, 60), EngineScenes.brass(55, -20, lean: 12), EngineScenes.steel(10, 120, side: 4)]
        for dart in darts {
            run.play([.throwDart(dart), .wait(0.4)])
        }
        #expect(run.engine.state == .awaitingTakeout)
        let observations = run.observations
        try #require(observations.count == 3)
        run.play([.takeout(duration: 1.5), .wait(2.5)])
        var expected = observations.map { ScanEvent.dart($0) }
        expected += observations.map { ScanEvent.dartRemoved(id: $0.id, reason: .takeout) }
        expected.append(.takeoutCompleted)
        #expect(run.facts == expected)
        #expect(run.engine.state == .watching(dartsOnBoard: 0))
        #expect(run.engine.dartsOnBoard.isEmpty)
        // A7: E retaken on the empty board.
        #expect(run.engine.emptyIsFresh)
        for (observation, dart) in zip(observations, darts) {
            #expect(observation.best == BoardGeometry.standard.hit(at: dart.tip))
        }
    }

    @Test func x4_bounceOutIsAPossibleMissOnly() throws {
        let run = armedRun(seed: 14)
        run.play([.bounceOut, .wait(1)])
        let facts = run.facts
        try #require(facts.count == 1)
        guard case .possibleMiss = facts[0] else {
            Issue.record("expected possibleMiss, got \(facts)")
            return
        }
        #expect(run.engine.state == .watching(dartsOnBoard: 0))
    }

    @Test func x12_fourthDartIsBeyondTheVisit() throws {
        let run = armedRun(seed: 15)
        let darts = [EngineScenes.steel(-60, 30), EngineScenes.steel(70, 50), EngineScenes.brass(-20, -70), EngineScenes.steel(40, -110)]
        for dart in darts {
            run.play([.throwDart(dart), .wait(0.4)])
        }
        let observations = run.observations
        try #require(observations.count == 4)
        #expect(observations.prefix(3).allSatisfy { !$0.flags.contains(.beyondVisitLimit) })
        #expect(observations[3].flags.contains(.beyondVisitLimit))
        // The factor of the flag is in the confidence (applied before `ConfidenceModel.observe`).
        #expect(observations[3].confidence <= 0.6 + 1e-9)
        #expect(observations[3].tier != .high)
        #expect(observations[3].indexInVisit == 3)
        #expect(run.engine.state == .awaitingTakeout)
        #expect(run.engine.dartsOnBoard.count == 4)
    }

    @Test func x16_sameInputSameOutputBitForBit() throws {
        func once() -> (events: [ScanEvent], noise: Double, onBoard: [DartObservation]) {
            let run = armedRun(seed: 16)
            run.play([.throwDart(EngineScenes.steel(25, 90)), .wait(0.4), .bounceOut, .wait(0.4),
                      .throwDart(EngineScenes.brass(-80, -40, lean: 14)), .wait(0.4)])
            run.send(.endVisit)
            run.send(.beginVisit(expectedDarts: 3))
            run.play([.throwDart(EngineScenes.steel(100, 10)), .wait(0.4)])
            return (run.events, run.engine.detectionNoise, run.engine.dartsOnBoard)
        }
        let first = once()
        let second = once()
        #expect(first.events.count > 6)
        #expect(first.events == second.events)
        #expect(first.noise.bitPattern == second.noise.bitPattern)
        #expect(first.onBoard == second.onBoard)
        let ids = first.onBoard.map(\.id)
        #expect(Set(ids).count == ids.count && ids.count == 3)
        // Every confidence is equal bit for bit, not only to the last digit.
        for (a, b) in zip(first.onBoard, second.onBoard) {
            #expect(a.confidence.bitPattern == b.confidence.bitPattern && a.tip.x.bitPattern == b.tip.x.bitPattern)
        }
    }

    @Test func x17_secondGameStartsAgainFromZero() throws {
        let run = armedRun(seed: 17)
        run.play([.throwDart(EngineScenes.steel(-30, -50)), .wait(0.4)])
        #expect(run.observations.count == 1)
        run.send(.pause(.user))
        #expect(run.engine.state == .paused(.user))
        run.wait(0.5)
        let before = run.log.count
        run.send(.arm(boardConfirmedEmpty: false))
        run.send(.beginVisit(expectedDarts: 3))
        run.wait(1)
        run.play([.throwDart(EngineScenes.steel(60, 95)), .wait(0.4)])
        let second = Array(run.log[before...].map(\.event))
        let observations = second.compactMap { event -> DartObservation? in
            if case .dart(let observation) = event { return observation }
            return nil
        }
        try #require(observations.count == 1)
        let states = second.compactMap { event -> ScanState? in
            if case .stateChanged(let state) = event { return state }
            return nil
        }
        #expect(states.prefix(2) == [.arming, .watching(dartsOnBoard: 0)])
        #expect(observations[0].visit == 1 && observations[0].indexInVisit == 0)
        #expect(observations[0].flags.contains(.emptyReferenceStale))
        #expect(second.filter { if case .dart = $0 { return true } else { return false } }.count == 1)
        #expect(run.engine.state == .watching(dartsOnBoard: 1))
    }
}
