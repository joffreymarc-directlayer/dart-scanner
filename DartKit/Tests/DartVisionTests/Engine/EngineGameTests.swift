import Foundation
import os
import simd
import Testing
import DartCore
@testable import DartVision

/// A game as the game layer drives it, and the seam for absolute detectors (VISION.md §10.2, X14, X15).
@Suite(.serialized, .tags(.heavy)) struct EngineGameTests {
    /// X14: three visits, nine throws of which one bounces out, a 4 px bump between two visits, the light dimmed by
    /// 15 % during a visit. The game layer sends what `PlayViewModel` sends: `beginVisit` at each turn, and
    /// `registerManualDart` for the bounce the player enters as a miss.
    @Test func x14_aGameOfThreeVisits() throws {
        let run = EngineRun(camera: EngineScenes.debugCamera, seed: 141)
        run.calibrate()
        run.send(.arm(boardConfirmedEmpty: true))
        run.wait(20.0 / 30)
        let visit1 = [EngineScenes.steel(-56, 64), EngineScenes.brass(76, 30, lean: 11), EngineScenes.steel(4, -120)]
        let visit2 = [EngineScenes.steel(-120, -40, lean: 12), EngineScenes.brass(40, 140)]
        let visit3 = [EngineScenes.steel(30, 72), EngineScenes.steel(-90, 100, side: -4), EngineScenes.brass(118, -64)]
        for dart in visit1 + visit2 + visit3 {
            #expect(EngineAccuracy.distanceToBoundary(dart.tip) > 3, "\(dart.tip)")
        }

        run.send(.beginVisit(expectedDarts: 3))
        for dart in visit1 {
            run.play([.throwDart(dart), .wait(0.4)])
        }
        run.play([.takeout(duration: 1.2), .wait(1)])

        run.send(.beginVisit(expectedDarts: 3))
        run.shiftBump(by: SIMD2(3.2, 2.4))
        run.wait(1)
        run.play([.throwDart(visit2[0]), .wait(0.4)])
        run.play([.lightRamp(gain: 0.85, duration: 1), .wait(2.5)])
        run.play([.throwDart(visit2[1]), .wait(0.4)])
        run.play([.bounceOut, .wait(0.4)])
        run.send(.registerManualDart)
        run.play([.takeout(duration: 1.2), .wait(1)])

        run.send(.beginVisit(expectedDarts: 3))
        for dart in visit3 {
            run.play([.throwDart(dart), .wait(0.4)])
        }

        let observations = run.observations
        try #require(observations.count == 8, "\(run.summary)")
        let adjusted = run.facts.compactMap { fact -> BoardCalibration? in
            if case .calibrationAdjusted(let calibration) = fact { return calibration }
            return nil
        }
        try #require(adjusted.count == 1, "\(run.summary)")
        let miss = run.facts.compactMap { fact -> TimeInterval? in
            if case .possibleMiss(let time) = fact { return time }
            return nil
        }
        try #require(miss.count == 1, "\(run.summary)")
        var expected: [ScanEvent] = observations[0..<3].map { .dart($0) }
        expected += observations[0..<3].map { .dartRemoved(id: $0.id, reason: .takeout) }
        expected += [.takeoutCompleted, .calibrationAdjusted(adjusted[0]), .dart(observations[3]), .dart(observations[4]),
                     .possibleMiss(timestamp: miss[0])]
        expected += observations[3..<5].map { .dartRemoved(id: $0.id, reason: .takeout) }
        expected.append(.takeoutCompleted)
        expected += observations[5..<8].map { .dart($0) }
        #expect(run.facts == expected, "\(run.summary)")
        for (observation, dart) in zip(observations, visit1 + visit2 + visit3) {
            #expect(observation.best == BoardGeometry.standard.hit(at: dart.tip), "\(observation.tip) for \(dart.tip)")
        }
        #expect(observations.map(\.visit) == [1, 1, 1, 2, 2, 3, 3, 3])
        #expect(observations.map(\.indexInVisit) == [0, 1, 2, 0, 1, 0, 1, 2])
        #expect(run.engine.state == .awaitingTakeout)
    }

    @Test func x15_absoluteDetectorOnlyNewDartsAreEmitted() throws {
        let truth = OSAllocatedUnfairLock(initialState: [BoardPoint]())
        let run = EngineRun(camera: EngineScenes.debugCamera, seed: 151, detector: EngineTruthDetector(truth: truth))
        run.calibrate()
        run.send(.arm(boardConfirmedEmpty: true))
        run.wait(20.0 / 30)
        func throwDart(_ dart: SyntheticDart) {
            truth.withLock { $0.append(dart.tip) }
            run.play([.throwDart(dart), .wait(0.4)])
        }
        let first = EngineScenes.steel(0, 100), second = EngineScenes.steel(60, -10)
        throwDart(first)
        throwDart(second)
        // A dart 5 mm from a known one is taken for it: nothing new.
        throwDart(EngineScenes.brass(3, 104))
        let fourth = EngineScenes.steel(-80, -60)
        throwDart(fourth)
        let observations = run.observations
        try #require(observations.count == 3, "\(run.facts)")
        #expect(observations.map(\.tip) == [first.tip, second.tip, fourth.tip])
        #expect(observations.map(\.indexInVisit) == [0, 1, 2])
        #expect(run.engine.dartsOnBoard.map(\.id) == observations.map(\.id))
        // The stub asks for no reference: it sees every dart in view.
        #expect(run.facts.filter { if case .dartRemoved = $0 { return true } else { return false } }.isEmpty)
        // A known dart the detector no longer sees has left the board.
        truth.withLock { $0.removeAll { $0 == second.tip } }
        run.play([.fallOut(index: 1), .wait(1)])
        #expect(run.facts.last == .dartRemoved(id: observations[1].id, reason: .fellOut), "\(run.facts)")
        #expect(run.engine.dartsOnBoard.map(\.id) == [observations[0].id, observations[2].id])
    }
}

/// An absolute detector that returns the true tips of every dart in view (lot V5 tests).
struct EngineTruthDetector: DartDetecting {
    let truth: OSAllocatedUnfairLock<[BoardPoint]>

    var descriptor: DetectorDescriptor {
        DetectorDescriptor(name: "truth", version: "1", mode: .absolute)
    }

    var needsSourceImage: Bool {
        false
    }

    func analyse(_ request: DetectionRequest) -> SceneAnalysis {
        let tips = truth.withLock { $0 }
        guard request.reference == nil, !tips.isEmpty else { return SceneAnalysis(kind: .noChange) }
        return SceneAnalysis(kind: .darts, darts: tips.map {
            DartCandidate(tip: $0, axis: SIMD2(0, 1), silhouette: CanvasMask(), visibleLength: 120)
        })
    }
}
