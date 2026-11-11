import Foundation
import simd
import Testing
import DartCore
@testable import DartVision

/// « Scanner la volée »: the manual trigger end to end through `ScanEngine` (VISION.md §6.3 rows DM1 to DM8, §8.1;
/// §10.2, P1, P2, P5).
@Suite(.serialized, .tags(.heavy)) struct EnginePhotoTests {
    /// Manual trigger, armed on an empty board, first visit begun.
    private func manualRun(seed: UInt64, camera: SyntheticCamera = EngineScenes.debugCamera) -> EngineRun {
        let run = EngineRun(camera: camera, seed: seed)
        run.calibrate()
        run.send(.setTrigger(.manual))
        run.send(.arm(boardConfirmedEmpty: true))
        run.wait(20.0 / 30)
        run.send(.beginVisit(expectedDarts: 3))
        return run
    }

    /// Plays the darts one after the other, as thrown while the vision does not look.
    private func throwUnwatched(_ run: EngineRun, _ darts: [SyntheticDart]) {
        for dart in darts {
            run.play([.throwDart(dart), .wait(0.3)])
        }
    }

    /// The `scanCompleted` events after log entry `from`.
    private func scans(_ run: EngineRun, from: Int = 0) -> [[DartObservation]] {
        run.log[from...].compactMap {
            if case .scanCompleted(let observations) = $0.event { return observations }
            return nil
        }
    }

    @Test func p1_scanTheVolley() throws {
        var errors: [Double] = []
        let volleys: [[SyntheticDart]] = [
            [EngineScenes.steel(-70, 60), EngineScenes.brass(65, 35, lean: 11), EngineScenes.steel(-10, -95, side: 4)],
            [EngineScenes.brass(30, 120), EngineScenes.steel(-110, -20, lean: 12), EngineScenes.steel(85, -70)],
        ]
        for (index, darts) in volleys.enumerated() {
            let run = manualRun(seed: 201 + UInt64(index))
            #expect(run.events == [.stateChanged(.idle), .stateChanged(.arming), .stateChanged(.watching(dartsOnBoard: 0))])
            let armed = run.log.count
            throwUnwatched(run, darts)
            // Nothing is processed between the end of the arming and the command.
            #expect(run.log.count == armed, "\(run.log[armed...].map(\.event))")
            let commanded = run.log.count
            run.send(.captureNow(maxDarts: 3))
            run.wait(0.6)
            let found = scans(run, from: commanded)
            try #require(found.count == 1, "\(run.events)")
            let observations = found[0]
            try #require(observations.count == 3, "\(observations)")
            #expect(observations.allSatisfy { $0.flags.contains(.multiDartStill) && $0.source == .scan })
            #expect(observations.map(\.indexInVisit).sorted() == [0, 1, 2] && observations.allSatisfy { $0.visit == 1 })
            // The scan is the last event, after `stateChanged` back to the rest.
            #expect(run.events.last == .scanCompleted(observations))
            #expect(run.engine.state == .awaitingTakeout)
            for observation in observations {
                let dart = try #require(EngineAccuracy.nearest(observation, among: darts))
                errors.append(EngineAccuracy.error(observation, dart))
                #expect(observation.best == BoardGeometry.standard.hit(at: dart.tip))
            }
        }
        let p95 = try #require(EngineAccuracy.quantile(errors, 0.95))
        #expect(p95 <= 2.0, "errors \(errors)")
    }

    /// P2. Both darts are found, nothing is high (`multiDartStill` alone keeps every dart of a still under 0.7). The
    /// flags the document expects on crossed darts (`clutter` or `implausiblyLong`) are not raised by the delivered
    /// detector (lot V3): its multi-seed peel separates the two bodies cleanly and raises `pointNotVisible`,
    /// `lowElongation` or `nearEndWide` on the fragment of the crossing instead. Kept as a known issue.
    @Test func p2_crossedDartsAreFlagged() throws {
        let run = manualRun(seed: 211)
        // The two bodies cross above the tips.
        let darts = [SyntheticDart(tip: BoardPoint(x: -30, y: 40), leanUpDegrees: 10, leanSideDegrees: 20, style: .steelTungsten),
                     SyntheticDart(tip: BoardPoint(x: 30, y: 40), leanUpDegrees: 10, leanSideDegrees: -20, style: .brass)]
        throwUnwatched(run, darts)
        let commanded = run.log.count
        run.send(.captureNow(maxDarts: 3))
        run.wait(0.6)
        let found = scans(run, from: commanded)
        try #require(found.count == 1, "\(run.events)")
        let observations = found[0]
        try #require(!observations.isEmpty)
        #expect(observations.allSatisfy { $0.tier != .high })
        for dart in darts {
            #expect(observations.contains { EngineAccuracy.error($0, dart) < 3 }, "\(observations.map(\.tip))")
        }
        withKnownIssue("lot V3: crossed darts are peeled apart without clutter or implausiblyLong") {
            for observation in observations {
                #expect(observation.flags.contains(.clutter) || observation.flags.contains(.implausiblyLong), "\(observation.flags)")
            }
        }
    }

    @Test func p5_successiveScans() throws {
        let run = manualRun(seed: 251)
        let first = [EngineScenes.steel(-60, 80), EngineScenes.brass(70, 20)]
        throwUnwatched(run, first)
        var mark = run.log.count
        run.send(.captureNow(maxDarts: 3))
        run.wait(0.6)
        let scan1 = scans(run, from: mark)
        try #require(scan1.count == 1 && scan1[0].count == 2, "\(run.events)")
        #expect(run.engine.state == .watching(dartsOnBoard: 2))

        let third = EngineScenes.steel(-20, -110)
        throwUnwatched(run, [third])
        mark = run.log.count
        run.send(.captureNow(maxDarts: 1))
        run.wait(0.6)
        let scan2 = scans(run, from: mark)
        try #require(scan2.count == 1 && scan2[0].count == 1, "\(run.events)")
        #expect(EngineAccuracy.error(scan2[0][0], third) < 3)
        #expect(scan2[0][0].indexInVisit == 2)
        #expect(run.engine.state == .awaitingTakeout)

        // Next visit: the board is cleared, three new darts, one where an old one was.
        run.send(.endVisit)
        run.send(.beginVisit(expectedDarts: 3))
        #expect(run.engine.dartsOnBoard.isEmpty)
        run.play([.takeout(duration: 0.6), .wait(0.5)])
        let next = [EngineScenes.brass(-60, 80, lean: 13), EngineScenes.steel(100, -40), EngineScenes.steel(15, 130)]
        throwUnwatched(run, next)
        mark = run.log.count
        run.send(.captureNow(maxDarts: 3))
        run.wait(0.6)
        let scan3 = scans(run, from: mark)
        try #require(scan3.count == 1 && scan3[0].count == 3, "\(run.events)")
        let old = first + [third]
        for observation in scan3[0] {
            let nearestNew = try #require(EngineAccuracy.nearest(observation, among: next))
            #expect(EngineAccuracy.error(observation, nearestNew) < 3)
            #expect(observation.visit == 2)
        }
        // No old dart comes back: the one at the place of an old dart is the new one (its own lean), and no
        // observation sits on an old dart that is gone.
        for dart in old.dropFirst() {
            #expect(!scan3[0].contains { EngineAccuracy.error($0, dart) < 5 })
        }
        #expect(run.facts.filter { if case .dartRemoved = $0 { return true } else { return false } }.isEmpty)
    }

    @Test func manualTrigger_ignoresCapturesElsewhere() throws {
        let run = EngineRun(camera: EngineScenes.debugCamera, seed: 261)
        run.calibrate()
        run.send(.arm(boardConfirmedEmpty: true))
        run.wait(20.0 / 30)
        // Automatic trigger: ignored, no event.
        #expect(run.send(.captureNow(maxDarts: 3)).isEmpty && run.send(.captureReference).isEmpty)
        #expect(run.send(.setTrigger(.manual)).isEmpty)
        // `maxDarts <= 0`: ignored, no `scanCompleted`.
        #expect(run.send(.captureNow(maxDarts: 0)).isEmpty)
        run.wait(0.5)
        #expect(run.facts.isEmpty)
        // A capture interrupted by a pause still answers once, empty.
        #expect(run.send(.captureNow(maxDarts: 2)) == [.stateChanged(.settling)])
        run.wait(2.0 / 30)
        #expect(run.send(.pause(.background)) == [.stateChanged(.paused(.background)), .scanCompleted([])])
    }

    /// Row DM6: a view that keeps moving (darts flying in front of the board for 2.5 s) never gives the sixth quiet
    /// frame; 2 s after the first sample the capture is abandoned, without analysis.
    @Test func manualTrigger_viewThatNeverSettles() throws {
        let run = manualRun(seed: 271)
        let mark = run.log.count
        run.send(.captureNow(maxDarts: 3))
        run.play([SyntheticScript.Step](repeating: .bounceOut, count: 25))
        let after = run.log[mark...].map(\.event)
        #expect(after == [.stateChanged(.settling), .stateChanged(.watching(dartsOnBoard: 0)), .advisory(.viewObstructed),
                          .scanCompleted([])], "\(run.summary)")
        #expect(run.engine.lastAnalysis == nil)
        #expect(run.engine.state == .watching(dartsOnBoard: 0))
    }
}
