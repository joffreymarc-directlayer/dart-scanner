import Foundation
import simd
import Testing
import DartCore
@testable import DartVision

/// Record and replay for tuning (VISION.md §10.3, §11.2): `DirectoryRecorder` writes a session, `RecordedSession`
/// reads it back and replays its scenes through a detector.
@Suite(.serialized, .tags(.heavy)) struct EngineRecorderTests {
    private static func directory(_ name: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("EngineRecorderTests-\(ProcessInfo.processInfo.processIdentifier)-\(name)")
    }

    @Test func recordThenReplay() throws {
        let directory = EngineRecorderTests.directory("replay")
        try? FileManager.default.removeItem(at: directory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let recorder = try DirectoryRecorder(directory: directory)
        let run = EngineRun(camera: EngineScenes.debugCamera, seed: 401, recorder: recorder)
        run.calibrate()
        run.send(.arm(boardConfirmedEmpty: true))
        run.wait(20.0 / 30)
        let darts = [EngineScenes.steel(-60, 50), EngineScenes.brass(80, -40)]
        for dart in darts {
            run.play([.throwDart(dart), .wait(0.4)])
        }
        let observations = run.observations
        try #require(observations.count == 2)
        // A correction, reported at the confirmation of the visit.
        _ = run.engine.correct(observations[1].id, tip: BoardPoint(x: 80, y: -42))
        run.engine.recordFeedback(observations[0].id, wasCorrected: false)
        run.engine.recordFeedback(observations[1].id, wasCorrected: true)

        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()
        #expect(names == ["0001-analysis.json", "0001-current.png", "0001-reference.png",
                          "0002-analysis.json", "0002-current.png", "0002-reference.png",
                          "calibration.json", "corrections.jsonl", "events.jsonl", "gate.jsonl"])
        let events = try String(contentsOf: directory.appendingPathComponent("events.jsonl"), encoding: .utf8)
            .split(separator: "\n")
        #expect(events.count == run.events.count)
        let corrections = try String(contentsOf: directory.appendingPathComponent("corrections.jsonl"), encoding: .utf8)
            .split(separator: "\n")
        try #require(corrections.count == 1)
        let correction = try JSONDecoder().decode(CaptureRecordCorrection.self, from: Data(corrections[0].utf8))
        #expect(correction.observation.id == observations[1].id && correction.correctedTip == BoardPoint(x: 80, y: -42))

        let session = try RecordedSession(directory: directory)
        #expect(session.calibration == run.engine.calibration)
        let scenes = session.scenes
        try #require(scenes.count == 2)
        #expect(scenes.allSatisfy { $0.reference != nil && $0.current.rgb.width == BoardCanvas.side && !$0.gate.isEmpty })
        #expect(scenes[0].time == observations[0].timestamp && scenes[1].time == observations[1].timestamp)
        // Lossless canvases: on the first scene (no dart known yet) the replay finds the same tip as the live
        // detector, to the bit. The recorder does not receive the known darts: on the second scene the replay does
        // not clear the first dart's silhouette from the mask, and the tip may move by a fraction of a millimetre.
        let recorded = session.recordedAnalyses
        let replayed = session.replay(detector: DifferencingDartDetector(), parameters: run.engine.configuration.detection,
                                      noiseSigma: run.engine.detectionNoise)
        try #require(replayed.count == 2 && recorded.count == 2)
        for (index, (live, again)) in zip(recorded, replayed).enumerated() {
            #expect(live.kind == .darts && again.kind == .darts)
            let a = try #require(live.darts.first), b = try #require(again.darts.first)
            let gap = hypot(a.tip.x - b.tip.x, a.tip.y - b.tip.y)
            #expect(gap <= (index == 0 ? 0 : 0.5), "scene \(index + 1): \(gap) mm")
            #expect(BoardGeometry.standard.hit(at: a.tip) == BoardGeometry.standard.hit(at: b.tip))
        }
        for (observation, analysis) in zip(observations, recorded) {
            #expect(analysis.darts.first?.tip == observation.tip)
        }
    }

    @Test func missingDirectoryOrCalibrationThrows() throws {
        let directory = EngineRecorderTests.directory("empty")
        try? FileManager.default.removeItem(at: directory)
        defer { try? FileManager.default.removeItem(at: directory) }
        #expect(throws: (any Error).self) { _ = try RecordedSession(directory: directory) }
        _ = try DirectoryRecorder(directory: directory)
        #expect(FileManager.default.fileExists(atPath: directory.path))
        #expect(throws: (any Error).self) { _ = try RecordedSession(directory: directory) }
    }
}
