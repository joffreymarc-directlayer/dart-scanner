import Foundation
import simd
import Testing
import DartCore
@testable import DartVision

/// The whole chain on many darts, and end-to-end scenarios with their accuracy and latency (VISION.md §10.2, X13;
/// heavy: run with `swift test -c release`; debug builds run fewer darts and the 1080p pose only).
@Suite(.serialized, .tags(.heavy)) struct EngineHeavyTests {
    enum Resolution: String, CaseIterable, Sendable {
        /// Pose A on a sensor of 3456 × 1944: about 1.8 px/mm in the worst direction.
        case fine
        /// Pose A on a sensor of 2304 × 1296: about 1.2 px/mm.
        case coarse

        var camera: SyntheticCamera {
            SupportPoses.a.camera(longSide: self == .fine ? 3456 : 2304)
        }
    }

    #if DEBUG
    static let chainDarts = 8
    static let volleyCount = 1
    #else
    static let chainDarts = 200
    static let volleyCount = 3
    #endif

    /// X13: rendered camera images, a calibration made by `BoardCalibrator` from noisy handles on a still, then darts
    /// one at a time through `ScanEngine` (gate, settle, rectifier, detector, confidence). The darts appear between
    /// two frames with a short vibration (no flight: what is measured is the chain, not the gate). The tolerance
    /// applies to the darts with a visible point (steel), as in T1; the whole mix is reported.
    @Test(arguments: Resolution.allCases) func x13_fullChain(_ resolution: Resolution) throws {
        let camera = resolution.camera
        var random = SupportRandom(seed: resolution == .fine ? 1301 : 1302)
        var handles = camera.exactHandles().points
        for index in handles.indices {
            handles[index].x += 1.5 * random.gaussian()
            handles[index].y += 1.5 * random.gaussian()
        }
        let still = SupportScenes.empty(seed: 1303).render(camera: camera)
        let calibration = try BoardCalibrator().calibrate(handles: CalibrationHandles(points: handles), still: still,
                                                         rotationDegrees: 0, intrinsics: camera.intrinsics).get()
        let run = EngineRun(camera: camera, scene: SupportScenes.empty(seed: 1304), engine: ScanEngine(), seed: 1305)
        run.install(calibration)
        run.send(.arm(boardConfirmedEmpty: true))
        run.wait(20.0 / 30)

        var visible: [Double] = [], all: [Double] = [], latencies: [Int] = [], correct = 0
        for _ in 0..<EngineHeavyTests.chainDarts {
            let dart = SupportScenes.randomDart(&random)
            let before = run.observations.count
            let landing = run.frameCount
            run.teleport(adding: [dart])
            let found = run.observations.dropFirst(before)
            let error = found.first.map { EngineAccuracy.error($0, dart) } ?? .infinity
            all.append(error)
            if dart.style != .allBlack { visible.append(error) }
            if let frame = run.dartFrames.last, !found.isEmpty { latencies.append(frame - landing) }
            if found.first?.best == BoardGeometry.standard.hit(at: dart.tip) { correct += 1 }
            run.teleport(removingAll: true)
        }
        let median = try #require(EngineAccuracy.quantile(visible, 0.5))
        let p95 = try #require(EngineAccuracy.quantile(visible, 0.95))
        let ppm = calibration.quality.minPixelsPerMillimetre
        print("X13 \(resolution.rawValue) (\(String(format: "%.2f", ppm)) px/mm, calibration \(calibration.quality.grade), "
              + "RMS \(String(format: "%.2f", calibration.quality.edgeResidualRMS ?? .nan)) mm): \(visible.count) visible darts, "
              + "median \(String(format: "%.2f", median)) mm, p95 \(String(format: "%.2f", p95)) mm; whole mix of \(all.count): "
              + "median \(String(format: "%.2f", EngineAccuracy.quantile(all, 0.5) ?? .nan)) mm, "
              + "\(correct) right segments, \(all.filter { !$0.isFinite }.count) missed; latency frames "
              + "\(latencies.min() ?? -1)...\(latencies.max() ?? -1)")
        if resolution == .fine {
            #expect(median <= 1.5 && p95 <= 2.5, "median \(median), p95 \(p95)")
        } else {
            #expect(p95 <= 3.5, "p95 \(p95)")
        }
    }

    // MARK: Scenario report

    /// Accuracy and latency of one scenario.
    struct Report: Sendable {
        var name: String
        var planted = 0
        var observed = 0
        var correct = 0
        var errors: [Double] = []
        /// Frames from the landing (or the scan command) to the event.
        var latencyFrames: [Int] = []
        /// Processing time of the frame that emitted the observation, ms.
        var processingMilliseconds: [Double] = []
        var events = ""

        var line: String {
            let latency = latencyFrames.sorted()
            let median = latency.isEmpty ? -1 : latency[latency.count / 2]
            let worst = latency.max() ?? -1
            let processing = processingMilliseconds.sorted()
            let processingMedian = processing.isEmpty ? 0 : processing[processing.count / 2]
            return "\(name): \(observed)/\(planted) darts, \(correct) right segments, tip error median "
                + "\(String(format: "%.2f", EngineAccuracy.quantile(errors, 0.5) ?? .nan)) mm, max "
                + "\(String(format: "%.2f", errors.max() ?? .nan)) mm; latency median \(median) frames "
                + "(\(String(format: "%.0f", Double(median) * 1000 / 30)) ms), worst \(worst) frames "
                + "(\(String(format: "%.0f", Double(worst) * 1000 / 30)) ms); processing of that frame median "
                + "\(String(format: "%.0f", processingMedian)) ms, worst \(String(format: "%.0f", processing.max() ?? 0)) ms"
        }
    }

    /// Matches every `dart` event of the run with the dart that landed last before it.
    private static func score(_ run: EngineRun, name: String) -> Report {
        var report = Report(name: name)
        report.planted = run.landings.count
        for entry in run.log {
            guard case .dart(let observation) = entry.event,
                  let landing = run.landings.last(where: { $0.frame <= entry.frame }) else { continue }
            report.observed += 1
            report.errors.append(EngineAccuracy.error(observation, landing.dart))
            if observation.best == BoardGeometry.standard.hit(at: landing.dart.tip) { report.correct += 1 }
            report.latencyFrames.append(entry.frame - landing.frame)
            if let time = run.processingTimes.first(where: { $0.frame == entry.frame }) {
                report.processingMilliseconds.append(Double(time.duration.components.attoseconds) / 1e15
                                                     + Double(time.duration.components.seconds) * 1000)
            }
        }
        report.events = run.facts.map { fact -> String in
            switch fact {
            case .dart(let observation): return "dart \(observation.best.notation)"
            case .dartRemoved(_, let reason): return "removed(\(reason))"
            case .calibrationAdjusted: return "calibrationAdjusted"
            case .calibrationRecovered: return "calibrationRecovered"
            default: return "\(fact)"
            }
        }.joined(separator: ", ")
        return report
    }

    private static var reportCameras: [(String, SyntheticCamera)] {
        #if DEBUG
        return [("B 1080p", SupportPoses.b.camera)]
        #else
        return [("A 4K", SupportPoses.a.camera), ("B 1080p", SupportPoses.b.camera)]
        #endif
    }

    private static let volley = [EngineScenes.steel(-56, 64), EngineScenes.brass(76, 30, lean: 11), EngineScenes.steel(4, -120),
                                 EngineScenes.brass(30, 72, lean: 14), EngineScenes.steel(-90, 100, side: -4),
                                 EngineScenes.steel(118, -64), EngineScenes.brass(-120, -40, lean: 12),
                                 EngineScenes.steel(40, 140), EngineScenes.steel(-20, 30, side: 5)]

    private static func armed(_ camera: SyntheticCamera, seed: UInt64) -> EngineRun {
        let run = EngineRun(camera: camera, seed: seed)
        run.calibrate()
        run.send(.arm(boardConfirmedEmpty: true))
        run.wait(20.0 / 30)
        return run
    }

    /// End-to-end scenarios: volleys of three darts thrown one by one, hands in front, takeouts, light changes, a
    /// bumped device, a dart that falls out, and « Scanner la volée ». Every dart that lands must be reported once,
    /// on the right segment; the report gives the accuracy and the latency of each scenario.
    @Test func scenarios_accuracyAndLatency() throws {
        var lines: [String] = []
        for (label, camera) in EngineHeavyTests.reportCameras {
            let darts = EngineHeavyTests.volley
            var reports: [Report] = []

            // 1. Volleys, takeout by hand between them (three in release, one in debug, where X3 and X14 cover more).
            let volleys = EngineHeavyTests.armed(camera, seed: 501)
            for visit in 0..<EngineHeavyTests.volleyCount {
                volleys.send(.beginVisit(expectedDarts: 3))
                for dart in darts[(visit * 3)..<(visit * 3 + 3)] {
                    volleys.play([.throwDart(dart), .wait(0.7)])
                }
                volleys.play([.takeout(duration: 1.2), .wait(1)])
            }
            reports.append(EngineHeavyTests.score(volleys, name: "\(label) volleys"))
            #expect(volleys.facts.filter { $0 == .takeoutCompleted }.count == EngineHeavyTests.volleyCount, "\(volleys.summary)")

            // 2. Hands in front: one passing between two darts, one resting a second before the third.
            let hands = EngineHeavyTests.armed(camera, seed: 502)
            hands.send(.beginVisit(expectedDarts: 3))
            hands.play([.throwDart(darts[0]), .wait(0.7), .handRest(0.2), .wait(0.7), .throwDart(darts[1]), .wait(0.7),
                        .handRest(1), .wait(1), .throwDart(darts[2]), .wait(0.7)])
            reports.append(EngineHeavyTests.score(hands, name: "\(label) hands"))

            // 3. Light: a lamp switched on (×1.3) on an empty board, then dimmed by 15 % with darts on the board.
            let light = EngineHeavyTests.armed(camera, seed: 503)
            light.send(.beginVisit(expectedDarts: 3))
            light.play([.lightStep(gain: 1.3), .wait(1), .throwDart(darts[3]), .wait(0.7),
                        .lightRamp(gain: 0.85, duration: 1), .wait(2.5), .throwDart(darts[4]), .wait(0.7)])
            reports.append(EngineHeavyTests.score(light, name: "\(label) light"))
            #expect(light.facts.contains(.lightingChanged), "\(light.summary)")

            // 4. A bumped device (3 px) between two darts.
            let bump = EngineHeavyTests.armed(camera, seed: 504)
            bump.send(.beginVisit(expectedDarts: 3))
            bump.play([.throwDart(darts[5]), .wait(0.7)])
            bump.shiftBump(by: SIMD2(2.4, 1.8))
            bump.wait(1)
            bump.play([.throwDart(darts[6]), .wait(0.7)])
            reports.append(EngineHeavyTests.score(bump, name: "\(label) bump"))
            #expect(bump.facts.contains { if case .calibrationAdjusted = $0 { return true } else { return false } }, "\(bump.summary)")

            // 5. A dart that falls out, then another one.
            let fall = EngineHeavyTests.armed(camera, seed: 505)
            fall.send(.beginVisit(expectedDarts: 3))
            fall.play([.throwDart(darts[7]), .wait(0.7), .fallOut(index: 0), .wait(1), .throwDart(darts[8]), .wait(0.7)])
            reports.append(EngineHeavyTests.score(fall, name: "\(label) fall-out"))
            #expect(fall.facts.contains { if case .dartRemoved(_, .fellOut) = $0 { return true } else { return false } })

            for report in reports {
                lines.append(report.line)
                #expect(report.observed == report.planted, "\(report.name): \(report.events)")
                #expect(report.correct == report.planted, "\(report.name): \(report.events)")
                #expect(report.errors.allSatisfy { $0 < 3 }, "\(report.name): \(report.errors)")
                #expect((report.latencyFrames.max() ?? 0) <= 16, "\(report.name): \(report.latencyFrames)")
            }

            // 6. « Scanner la volée »: three volleys, each scanned once.
            let scan = EngineRun(camera: camera, seed: 506)
            scan.calibrate()
            scan.send(.setTrigger(.manual))
            scan.send(.arm(boardConfirmedEmpty: true))
            scan.wait(20.0 / 30)
            var scanReport = Report(name: "\(label) scan")
            for visit in 0..<3 {
                scan.send(.beginVisit(expectedDarts: 3))
                if visit > 0 { scan.play([.takeout(duration: 0.6), .wait(0.4)]) }
                let thrown = Array(darts[(visit * 3)..<(visit * 3 + 3)])
                for dart in thrown {
                    scan.play([.throwDart(dart), .wait(0.3)])
                }
                let commanded = scan.frameCount
                let mark = scan.log.count
                scan.send(.captureNow(maxDarts: 3))
                scan.wait(0.6)
                scanReport.planted += 3
                for entry in scan.log[mark...] {
                    guard case .scanCompleted(let observations) = entry.event else { continue }
                    scanReport.latencyFrames.append(entry.frame - commanded)
                    if let time = scan.processingTimes.first(where: { $0.frame == entry.frame }) {
                        scanReport.processingMilliseconds.append(Double(time.duration.components.attoseconds) / 1e15
                                                                 + Double(time.duration.components.seconds) * 1000)
                    }
                    for observation in observations {
                        scanReport.observed += 1
                        guard let dart = EngineAccuracy.nearest(observation, among: thrown) else { continue }
                        scanReport.errors.append(EngineAccuracy.error(observation, dart))
                        if observation.best == BoardGeometry.standard.hit(at: dart.tip) { scanReport.correct += 1 }
                    }
                }
            }
            lines.append(scanReport.line)
            #expect(scanReport.observed == 9 && scanReport.correct == 9, "\(scan.summary)")
            #expect(scanReport.errors.allSatisfy { $0 < 3 }, "\(scanReport.errors)")
        }
        print("ENGINE SCENARIOS\n" + lines.joined(separator: "\n"))
    }
}
