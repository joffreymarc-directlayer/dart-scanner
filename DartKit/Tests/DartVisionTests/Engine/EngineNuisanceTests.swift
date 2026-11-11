import Foundation
import simd
import Testing
import DartCore
@testable import DartVision

/// What must not become a dart: light, hands, fallen darts, tremor, ghosts (VISION.md §10.2, X5, X6, X7, X10, X11).
@Suite(.serialized, .tags(.heavy)) struct EngineNuisanceTests {
    private func armedRun(seed: UInt64) -> EngineRun {
        let run = EngineRun(camera: EngineScenes.debugCamera, seed: seed)
        run.calibrate()
        run.send(.arm(boardConfirmedEmpty: true))
        run.wait(20.0 / 30)
        return run
    }

    @Test func x5_globalGainIsALightingChange() throws {
        let run = armedRun(seed: 51)
        run.play([.lightStep(gain: 1.3), .wait(1.5)])
        #expect(run.facts == [.lightingChanged], "\(run.events)")
        #expect(run.observations.isEmpty)
        // A14 with `n = 0`: the empty reference is retaken under the new light.
        #expect(run.engine.emptyIsFresh)
        #expect(run.engine.state == .watching(dartsOnBoard: 0))
    }

    @Test func x5_halfTheBoardBrightenedIsALightingChange() throws {
        let run = armedRun(seed: 52)
        run.imageFilter = EngineScenes.brightenLeftHalf(1.3)
        run.wait(1.5)
        #expect(run.facts == [.lightingChanged], "\(run.events)")
        #expect(run.observations.isEmpty)
        #expect(run.engine.state == .watching(dartsOnBoard: 0))
    }

    @Test func x6_handAtRestObstructsThenLeaves() throws {
        let run = armedRun(seed: 61)
        run.play([.handRest(3), .wait(3)])
        #expect(run.states.contains(.obstructed), "\(run.events)")
        #expect(run.observations.isEmpty)
        for fact in run.facts {
            switch fact {
            case .unrecognizedChange, .advisory(.viewObstructed): break
            default: Issue.record("unexpected \(fact)")
            }
        }
        #expect(run.engine.state == .watching(dartsOnBoard: 0))
        // Back to normal: a dart after the hand is seen.
        let dart = EngineScenes.steel(-35, 85)
        run.play([.throwDart(dart), .wait(0.4)])
        try #require(run.observations.count == 1)
        #expect(run.observations[0].best == BoardGeometry.standard.hit(at: dart.tip))
    }

    @Test func x7_aDartThatFallsOut() throws {
        let run = armedRun(seed: 71)
        run.play([.throwDart(EngineScenes.steel(45, 40)), .wait(0.4)])
        let observations = run.observations
        try #require(observations.count == 1)
        run.play([.fallOut(index: 0), .wait(1)])
        #expect(run.facts == [.dart(observations[0]), .dartRemoved(id: observations[0].id, reason: .fellOut)], "\(run.events)")
        #expect(run.engine.state == .watching(dartsOnBoard: 0))
        #expect(!run.facts.contains(.takeoutCompleted))
    }

    @Test func x10_tremorAndNoiseGiveNothing() throws {
        let run = armedRun(seed: 101)
        let armed = run.log.count
        run.sway(frames: 600, amplitude: 0.3)
        let after = run.log[armed...].map(\.event)
        #expect(after.isEmpty, "\(after)")
        #expect(run.engine.state == .watching(dartsOnBoard: 0))
        #expect(run.motionFrames.isEmpty)
    }

    @Test func x11_aShapeLeftInTheReferenceIsNoGhost() throws {
        let run = armedRun(seed: 111)
        run.play([.throwDart(EngineScenes.brass(-70, -20)), .wait(0.4)])
        let observations = run.observations
        try #require(observations.count == 1)
        // The player says it was no dart: its footprint stays in R.
        run.send(.discardDart(observations[0].id))
        #expect(run.engine.dartsOnBoard.isEmpty)
        let before = run.log.count
        run.play([.fallOut(index: 0), .wait(1.2)])
        let facts = run.log[before...].map(\.event).filter {
            if case .stateChanged = $0 { return false }
            return true
        }
        #expect(facts.isEmpty, "\(facts)")
        #expect(run.engine.state == .watching(dartsOnBoard: 0))
        // The next dart is seen normally.
        let dart = EngineScenes.steel(20, -95)
        run.play([.throwDart(dart), .wait(0.4)])
        #expect(run.observations.count == 2)
        #expect(run.observations.last?.best == BoardGeometry.standard.hit(at: dart.tip))
    }
}
