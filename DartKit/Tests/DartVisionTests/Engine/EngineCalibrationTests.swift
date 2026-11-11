import Foundation
import simd
import Testing
import DartCore
@testable import DartVision

/// A bumped device: relock, loss and recovery of the calibration through the engine (VISION.md §4.9, §6.3 rows K1
/// to K5; §10.2, X8, X9).
@Suite(.serialized, .tags(.heavy)) struct EngineCalibrationTests {
    private func armedRun(seed: UInt64, locator: (any BoardLocating)? = nil) -> EngineRun {
        let run = EngineRun(camera: EngineScenes.debugCamera, seed: seed, locator: locator)
        run.calibrate()
        run.send(.arm(boardConfirmedEmpty: true))
        run.wait(20.0 / 30)
        return run
    }

    @Test func x8_smallBumpIsRealigned() throws {
        let run = armedRun(seed: 81)
        let first = EngineScenes.steel(-50, 70)
        run.play([.throwDart(first), .wait(0.4)])
        let before = try #require(run.engine.calibration)
        run.shiftBump(by: SIMD2(1.6, 1.2))
        run.wait(1)
        let adjusted = run.facts.compactMap { fact -> BoardCalibration? in
            if case .calibrationAdjusted(let calibration) = fact { return calibration }
            return nil
        }
        try #require(adjusted.count == 1, "\(run.events)")
        #expect(adjusted[0] != before && run.engine.calibration == adjusted[0])
        // The realigned homography follows the shifted image: the bull moved by the bump.
        let bull = adjusted[0].boardToImage.apply(SIMD2(0, 0)) - before.boardToImage.apply(SIMD2(0, 0))
        #expect(abs(bull.x - 1.6) < 0.5 && abs(bull.y - 1.2) < 0.5, "\(bull)")
        let second = EngineScenes.brass(60, -45)
        run.play([.throwDart(second), .wait(0.4)])
        let observations = run.observations
        try #require(observations.count == 2, "\(run.events)")
        #expect(run.facts == [.dart(observations[0]), .calibrationAdjusted(adjusted[0]), .dart(observations[1])])
        #expect(observations[1].best == BoardGeometry.standard.hit(at: second.tip))
        #expect(EngineAccuracy.error(observations[1], second) < 3)
        #expect(run.engine.state == .watching(dartsOnBoard: 2))
    }

    /// A bump of 40 px, then the next dart: two poses whose drift check is `lost` (row K2). The dart of the second
    /// pose is never reported, and nothing is reported after it.
    @Test func x9_largeBumpLosesTheCalibration() throws {
        let run = armedRun(seed: 91)
        run.play([.throwDart(EngineScenes.steel(30, 30)), .wait(0.4)])
        let observed = run.observations.count
        run.shiftBump(by: SIMD2(32, 24))
        run.wait(2)
        #expect(!run.facts.contains(.calibrationLost))
        run.play([.throwDart(EngineScenes.steel(-60, -60)), .wait(2)])
        #expect(run.facts.contains(.calibrationLost), "\(run.events)")
        #expect(run.engine.state == .calibrationLost)
        #expect(run.engine.lastHealth?.status == .lost)
        #expect(run.observations.count == observed)
        run.play([.throwDart(EngineScenes.steel(70, -20)), .wait(2)])
        #expect(run.observations.count == observed)
        #expect(!run.facts.contains { if case .calibrationRecovered = $0 { return true } else { return false } })
        #expect(run.engine.state == .calibrationLost)
    }

    /// The same with the automatic locator: in `calibrationLost` each quiet second tries `recover`, then the locator
    /// (row K3); the recovery re-arms and comes back to the state before the loss (row K4).
    @Test func x9_largeBumpIsRecoveredByTheLocator() throws {
        let run = armedRun(seed: 92, locator: ColourBoardLocator())
        run.play([.throwDart(EngineScenes.steel(30, 30)), .wait(0.4)])
        let before = try #require(run.engine.calibration)
        run.shiftBump(by: SIMD2(32, 24))
        run.wait(2)
        run.play([.throwDart(EngineScenes.steel(-60, -60)), .wait(4)])
        let facts = run.facts
        let lost = try #require(facts.firstIndex(of: .calibrationLost), "\(run.events)")
        let recovered = try #require(facts.firstIndex { if case .calibrationRecovered = $0 { return true } else { return false } },
                                     "\(run.events)")
        #expect(lost < recovered)
        let calibration = try #require(run.engine.calibration)
        #expect(calibration != before)
        if case .calibrationRecovered(let found) = facts[recovered] { #expect(found == calibration) }
        let bull = calibration.boardToImage.apply(SIMD2(0, 0)) - before.boardToImage.apply(SIMD2(0, 0))
        #expect(abs(bull.x - 32) < 1.5 && abs(bull.y - 24) < 1.5, "\(bull)")
        #expect(run.engine.state == .watching(dartsOnBoard: 1), "\(run.events)")
        // With darts on the board the empty reference is stale after the recovery (row K4).
        #expect(!run.engine.emptyIsFresh)
        // Detection works again on the recovered calibration.
        let dart = EngineScenes.steel(-55, -75)
        run.play([.throwDart(dart), .wait(0.4)])
        let last = try #require(run.observations.last)
        #expect(last.best == BoardGeometry.standard.hit(at: dart.tip))
        #expect(EngineAccuracy.error(last, dart) < 3)
        #expect(last.flags.contains(.emptyReferenceStale))
    }

    @Test func setCalibration_clearsReferencesAndKeepsTheVisit() throws {
        let run = armedRun(seed: 93)
        run.send(.beginVisit(expectedDarts: 3))
        run.play([.throwDart(EngineScenes.steel(10, 60)), .wait(0.4)])
        #expect(run.engine.dartsOnBoard.count == 1 && run.engine.rolling != nil)
        #expect(run.calibrate(grade: .fair) == [.stateChanged(.idle)])
        #expect(run.engine.dartsOnBoard.isEmpty && run.engine.rolling == nil && run.engine.empty == nil)
        #expect(run.engine.machine.visit == 1 && run.engine.machine.dartsInVisit == 1)
        // In `idle` frames are ignored and the gate is stopped.
        run.wait(0.5)
        #expect(!run.engine.gateRunning && run.engine.state == .idle)
    }

    @Test func arm_withoutCalibrationIsIgnored() {
        let engine = ScanEngine()
        #expect(engine.handle(.arm(boardConfirmedEmpty: true)).isEmpty)
        #expect(engine.state == .needsCalibration && engine.calibration == nil)
        let frame = Frame(image: RGBImage(width: 8, height: 8, fill: SIMD3(10, 10, 10)), timestamp: 0)
        #expect(engine.process(frame).isEmpty)
    }

    @Test func warmUp_capsTheFirstDartsAfterACalibration() throws {
        var configuration = VisionConfiguration()
        configuration.confidence.warmUpDarts = 2
        let run = EngineRun(camera: EngineScenes.debugCamera, seed: 94, configuration: configuration)
        run.calibrate()
        run.send(.arm(boardConfirmedEmpty: true))
        run.wait(20.0 / 30)
        for dart in [EngineScenes.steel(-30, 40), EngineScenes.steel(70, -10), EngineScenes.steel(0, -120)] {
            run.play([.throwDart(dart), .wait(0.4)])
        }
        let observations = run.observations
        try #require(observations.count == 3)
        #expect(observations[0].flags.contains(.warmUp) && observations[1].flags.contains(.warmUp))
        #expect(!observations[2].flags.contains(.warmUp))
        #expect(observations.prefix(2).allSatisfy { $0.confidence <= 0.84 + 1e-12 })
    }
}
