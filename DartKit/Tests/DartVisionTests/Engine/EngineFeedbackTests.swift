import Foundation
import simd
import Testing
import DartCore
@testable import DartVision

/// The correction hooks of the engine (VISION.md §4.8, §7.5, §7.6): tip moved by the player, feedback and the
/// trust tracker, evidence crop, one-dart lighting check, new configuration, debug snapshot.
@Suite(.serialized, .tags(.heavy)) struct EngineFeedbackTests {
    @Test func oneDartCheck_correction_evidence_snapshot() throws {
        let run = EngineRun(camera: EngineScenes.debugCamera, seed: 301)
        run.engine.collectsDetectionDebug = true
        run.calibrate()
        #expect(run.engine.warmUpRemaining == 3)
        run.send(.arm(boardConfirmedEmpty: true))
        run.wait(20.0 / 30)
        let dart = EngineScenes.steel(-25, 64)
        run.play([.throwDart(dart), .wait(0.4)])
        let observation = try #require(run.observations.first)
        #expect(observation.flags.contains(.warmUp))

        // Debug snapshot of the analysis.
        let snapshot = run.engine.debugSnapshot()
        #expect(snapshot.state == .watching(dartsOnBoard: 1) && snapshot.lastAnalysis?.kind == .darts)
        #expect(snapshot.lastGate != nil && snapshot.lastHealth?.status == .healthy && snapshot.noiseSigma > 0)
        #expect(snapshot.lastDetectionDebug?.tips.count == 1)

        // Evidence crop: 50 mm around the tip, scaled 6 times.
        let crop = try #require(run.engine.evidenceCrop(for: observation.id, span: 50, scale: 6))
        #expect(crop.width == crop.height && crop.width >= 500)
        #expect(run.engine.evidenceCrop(for: UUID(uuidString: "00000000-0000-0000-0000-0000000000F0") ?? UUID(), span: 50, scale: 6) == nil)

        // One-dart check on the true tip: verified, the warm-up is over and the shadow bound is adopted.
        let check = try #require(run.engine.runLightingCheck(confirmedTip: dart.tip))
        #expect(check.verdict == .verified, "\(check)")
        #expect(run.engine.configuration.detection.shadowLowerBound == check.recommendedShadowLowerBound)
        #expect(run.engine.warmUpRemaining == 0)
        let next = EngineScenes.brass(70, -30)
        run.play([.throwDart(next), .wait(0.4)])
        #expect(run.observations.count == 2 && !(run.observations.last?.flags.contains(.warmUp) ?? true))
        // The same calibration installed again keeps the check.
        run.calibrate()
        #expect(run.engine.warmUpRemaining == 0)

        // The player drags the tip: a confirmed observation, same identity.
        let corrected = try #require(run.engine.correct(observation.id, tip: BoardPoint(x: -25, y: 66)))
        #expect(corrected.id == observation.id && corrected.visit == observation.visit && corrected.indexInVisit == observation.indexInVisit)
        #expect(corrected.source == .tappedOnPhoto && corrected.confidence == 1 && corrected.tier == .high)
        #expect(corrected.best == BoardGeometry.standard.hit(at: BoardPoint(x: -25, y: 66)))
    }

    @Test func feedback_degradesTheThresholdOnce() throws {
        let engine = ScanEngine()
        let ids = (1...4).map { UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", $0)) ?? UUID() }
        for id in ids {
            let observation = DartObservation(id: id, visit: 1, indexInVisit: 0, timestamp: 0, tip: BoardPoint(x: 0, y: 103),
                                              uncertainty: TipUncertainty(sigmaAlong: 1, sigmaAcross: 0.5, axis: SIMD2(0, 1)),
                                              candidates: [HitCandidate(hit: .treble(20), probability: 1)], nearbyHits: [],
                                              confidence: 0.97, tier: .high, flags: [], source: .liveCamera)
            engine.records.append(ScanEngineRecord(observation: observation))
        }
        engine.recordFeedback(ids[0], wasCorrected: true)
        #expect(engine.handle(.registerManualDart).isEmpty)
        engine.recordFeedback(ids[1], wasCorrected: true)
        // Feedback returns nothing: the advisory leads the next list of events.
        #expect(engine.handle(.registerManualDart) == [.advisory(.accuracyDegraded)])
        #expect(engine.trust.thresholds.high == 0.95)
        // Once per dart: a second feedback for the same dart is ignored.
        engine.recordFeedback(ids[1], wasCorrected: true)
        engine.recordFeedback(ids[2], wasCorrected: true)
        #expect(engine.handle(.registerManualDart).isEmpty)
        // A phantom discarded by the player counts as a correction.
        #expect(engine.records.filter(\.fedBack).count == 3)
        _ = engine.handle(.discardDart(ids[3]))
        #expect(engine.records.allSatisfy { $0.fedBack })
    }

    @Test func newScanParameters_restartFromIdle() throws {
        let run = EngineRun(camera: EngineScenes.debugCamera, seed: 311)
        run.calibrate()
        run.send(.setTrigger(.manual))
        run.send(.arm(boardConfirmedEmpty: true))
        run.wait(20.0 / 30)
        #expect(run.engine.state == .watching(dartsOnBoard: 0))
        var configuration = run.engine.configuration
        configuration.detection.shadowLowerBound = 0.3
        run.engine.configuration = configuration
        // Detection parameters only: nothing restarts.
        #expect(run.engine.state == .watching(dartsOnBoard: 0) && run.engine.rolling != nil)
        configuration.scan.settleFrames = 7
        run.engine.configuration = configuration
        #expect(run.engine.state == .idle && run.engine.machine.trigger == .manual)
        #expect(run.send(.registerManualDart) == [.stateChanged(.idle)])
        #expect(run.engine.configuration == configuration)
    }

    /// VISION.md §2.4: a mean brightness of the gate that ripples by more than 1 % over the arming frames, around
    /// its trend, is flicker. A slow ramp of light is not.
    @Test func flicker_duringTheArmingIsAdvised() throws {
        func arming(gain: (Int) -> Double) -> [ScanEvent] {
            let camera = EngineScenes.debugCamera
            let engine = ScanEngine()
            _ = engine.setCalibration(camera.calibration())
            _ = engine.handle(.arm(boardConfirmedEmpty: true))
            let scene = SupportScenes.empty(seed: 321)
            let base = scene.baseImage(camera: camera)
            var events: [ScanEvent] = []
            for index in 0..<20 {
                var frameScene = scene
                frameScene.gain = gain(index)
                frameScene.seed = SyntheticNoise.mix(UInt64(index + 1))
                events += engine.process(Frame(image: frameScene.finished(base), timestamp: Double(index) / 30))
            }
            return events
        }
        // 100 Hz light seen at 30 frames per second: the brightness beats from frame to frame.
        let flickering = arming { $0 % 2 == 0 ? 1.015 : 0.985 }
        #expect(flickering == [.stateChanged(.watching(dartsOnBoard: 0)), .advisory(.flicker)])
        let ramp = arming { 1 + 0.002 * Double($0) }
        #expect(ramp == [.stateChanged(.watching(dartsOnBoard: 0))])
    }
}
