import Foundation
import simd
import DartCore

// The two requests of the reducer: `.analyse` (VISION.md §5, §7) and `.checkCalibration` (§4.9, rows K1 to K5).
extension ScanEngine {
    /// A "lighting change" read after an episode that moved during at least this many frames is something that came
    /// in front of the board (a hand), not light: a light switched on or off changes the view in one frame, and a
    /// slow change of light makes no episode at all.
    static let handMotionFrames = 2

    // MARK: Analysis

    func analyse(maxNewDarts: Int, frame: Frame?, time: TimeInterval) -> [ScanEvent] {
        let purpose = machine.analysis
        guard let calibration = currentCalibration, let current = settledImage() else {
            return feed(.settle(.unrecognized, timestamp: time), frame: frame, time: time)
        }
        let reference = rolling
        let isRelockEvent = relockedForNextEvent
        relockedForNextEvent = false

        if skipNextDetection {
            // §4.9: the camera centre moved too far; the rolling reference is retaken and no dart is looked for.
            skipNextDetection = false
            rolling = current
            gate?.setReferenceToCurrent()
            let outcome: SettleOutcome
            if case .episode = purpose { outcome = .foreignRemoval } else { outcome = .noChange }
            return feed(.settle(outcome, timestamp: time), frame: frame, time: time)
        }

        let absolute = detector.descriptor.mode == .absolute
        let extraDilation = known.contains(where: \.predatesRelock) ? max(0, settings.detection.relockExtraDilation) : 0
        let request = DetectionRequest(current: current, reference: absolute ? nil : reference,
                                       emptyReference: absolute || !emptyIsFresh ? nil : empty,
                                       knownDarts: known.map { KnownDart(id: $0.id, tip: $0.tip, silhouette: $0.silhouette) },
                                       calibration: calibration, noiseSigma: detectionNoise, maxNewDarts: max(1, maxNewDarts),
                                       extraSilhouetteDilation: extraDilation,
                                       sourceImage: detector.needsSourceImage ? frame?.makeRGBImage() : nil,
                                       parameters: settings.detection)
        let analysis: SceneAnalysis
        if collectsDetectionDebug, let differencing = detector as? DifferencingDartDetector {
            let result = differencing.analyseWithDebug(request)
            analysis = result.analysis
            lastDetectionDebug = result.debug
        } else {
            analysis = detector.analyse(request)
        }
        lastAnalysis = analysis
        recorder?.record(reference: reference, current: current, analysis: analysis, gate: gateSinceAnalysis, at: time)
        gateSinceAnalysis = []

        var outcome = settleOutcome(of: analysis, purpose: purpose, maxNewDarts: max(1, maxNewDarts), absolute: absolute,
                                    calibration: calibration, afterRelock: isRelockEvent, time: time)
        if isRelockEvent, outcome == .noChange, case .episode = purpose {
            // The motion was the bump that moved the camera: `R := S` with the new calibration, no `possibleMiss`.
            outcome = .foreignRemoval
        }
        analysisScene = (reference ?? current, current)
        let events = feed(.settle(outcome, timestamp: time), frame: frame, time: time)
        pendingSilhouettes = []
        analysisScene = nil
        return events
    }

    /// What the reducer reads from an analysis. New darts become observations here, with the counters the reducer
    /// has before the `.settle` input.
    private func settleOutcome(of analysis: SceneAnalysis, purpose: ScanStateMachine.Analysis, maxNewDarts: Int,
                               absolute: Bool, calibration: BoardCalibration, afterRelock: Bool,
                               time: TimeInterval) -> SettleOutcome {
        var candidates = analysis.darts
        var removed = analysis.removedDartIDs
        var disturbed = analysis.disturbedDartIDs
        var kind = analysis.kind
        if absolute, kind == .darts || kind == .noChange {
            // An absolute detector returns every dart in view: the known ones are matched by their tips.
            let matched = matchAbsolute(analysis.darts)
            candidates = matched.new
            removed = matched.removed
            disturbed = []
            if !candidates.isEmpty {
                kind = .darts
            } else if !removed.isEmpty {
                kind = .removal
            } else {
                kind = .noChange
            }
        }
        switch kind {
        case .noChange:
            return .noChange
        case .obstruction:
            return .obstruction
        case .lightingChange:
            // D4 tests the light before the size of the change: a hand or an arm that covers a third of the board
            // reads as a lighting change. A hand needs several frames to come in, and one that was already in front
            // (an episode that started from `obstructed`) is still there; light changes in one frame, or in none.
            // Such a change is an obstruction (A11), so that the hand is never absorbed into `R`.
            if case .episode(let kind) = purpose, kind != .none,
               episodeMotionFrames >= ScanEngine.handMotionFrames || machine.originObstructed {
                return .obstruction
            }
            return .lightingChanged
        case .foreignRemoval:
            return .foreignRemoval
        case .unrecognized:
            return .unrecognized
        case .removal:
            let knownIDs = known.map(\.id)
            let everything = !knownIDs.isEmpty && knownIDs.allSatisfy { removed.contains($0) }
            var boardEmpty = everything && !machine.unseenDartOnBoard
            if everything, machine.unseenDartOnBoard, !absolute {
                // A dart entered by hand may be on the board where the camera never saw it, or may be the bounce
                // the player entered as a miss: the settled image says which, against the empty reference.
                boardEmpty = looksEmpty(settledImage(), calibration: calibration)
            }
            return .removed(removed, boardEmpty: boardEmpty)
        case .darts:
            if case .resume = purpose {
                // Rows P2 and DM8 only ask whether the scene is unchanged; no dart is ever reported there.
                return .unrecognized
            }
            let source: ObservationSource = machine.trigger == .manual ? .scan : .liveCamera
            var observations: [DartObservation] = []
            for (offset, candidate) in candidates.prefix(maxNewDarts).enumerated() {
                var adjusted = candidate
                if machine.isBeyondVisitLimit(newDartOffset: offset) { adjusted.flags.insert(.beyondVisitLimit) }
                if afterRelock { adjusted.flags.insert(.afterRelock) }
                let id = nextObservationID(time: time)
                let context = ConfidenceContext(warmUpRemaining: warmUpRemaining, thresholds: trust.thresholds, cap: 1)
                if warmUpRemaining > 0 { warmUpRemaining -= 1 }
                let observation = confidenceModel.observe(adjusted, id: id, visit: machine.visit,
                                                          indexInVisit: machine.dartsInVisit + offset, timestamp: time,
                                                          source: source, calibration: calibration, context: context)
                pendingSilhouettes.append((id, candidate.silhouette))
                observations.append(observation)
            }
            if observations.isEmpty {
                return removed.isEmpty ? .unrecognized : .removed(removed, boardEmpty: false)
            }
            return .darts(new: observations, removed: removed, disturbed: disturbed)
        }
    }

    /// The settled image shows the board of the fresh empty reference: the detector finds no change between them.
    private func looksEmpty(_ current: CanvasImage?, calibration: BoardCalibration) -> Bool {
        guard let current, emptyIsFresh, let empty else { return false }
        let request = DetectionRequest(current: current, reference: empty, emptyReference: empty, knownDarts: [],
                                       calibration: calibration, noiseSigma: detectionNoise, maxNewDarts: 1,
                                       parameters: settings.detection)
        return detector.analyse(request).kind == .noChange
    }

    /// Absolute detections against the known darts (§10.2, X15): a detection within `absoluteMatchRadius` of a known
    /// tip is a dart already counted; the others are new. A known dart with no detection within that radius left
    /// the board.
    private func matchAbsolute(_ detections: [DartCandidate]) -> (new: [DartCandidate], removed: [UUID]) {
        let radius = settings.scan.absoluteMatchRadius
        func near(_ a: BoardPoint, _ b: BoardPoint) -> Bool {
            hypot(a.x - b.x, a.y - b.y) <= radius
        }
        let fresh = detections.filter { detection in !known.contains { near($0.tip, detection.tip) } }
        let removed = known.filter { dart in !detections.contains { near($0.tip, dart.tip) } }.map(\.id)
        return (fresh, removed)
    }

    /// A deterministic identifier: a digest of a counter and of the frame time, written as a UUID of version 8.
    /// The same input gives the same identifiers; frames of two sessions never share a timestamp.
    func nextObservationID(time: TimeInterval) -> UUID {
        observationSerial &+= 1
        let a = ScanEngine.mix(observationSerial ^ 0x5DEE_CE66_D1CE_4E5B)
        let b = ScanEngine.mix(time.bitPattern ^ ScanEngine.mix(a))
        var bytes = [UInt8](repeating: 0, count: 16)
        for index in 0..<8 {
            bytes[index] = UInt8(truncatingIfNeeded: a >> (8 * UInt64(index)))
            bytes[index + 8] = UInt8(truncatingIfNeeded: b >> (8 * UInt64(index)))
        }
        bytes[6] = (bytes[6] & 0x0F) | 0x80
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }

    /// SplitMix64 finaliser.
    static func mix(_ x: UInt64) -> UInt64 {
        var z = x &+ 0x9E37_79B9_7F4A_7C15
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    // MARK: Calibration check

    func checkCalibration(frame: Frame, time: TimeInterval) -> [ScanEvent] {
        guard let calibration = currentCalibration else { return [] }
        let dartsOnBoard = !known.isEmpty || machine.dartsOnBoard > 0 || machine.unseenDartOnBoard
        var events: [ScanEvent] = []
        if machine.state == .calibrationLost {
            // Row K3: the current calibration again, then `recover`, then the automatic locator.
            let health = calibrator.assess(calibration, on: frame, dartsOnBoard: dartsOnBoard)
            lastHealth = health
            var found: BoardCalibration?
            if health.status == .healthy {
                found = calibration
            } else if let recovered = calibrator.recover(calibration, on: frame) {
                found = recovered
            } else if let located = locate(on: frame, replacing: calibration) {
                found = located
            }
            guard let found else {
                return feed(.calibrationHealth(health.status, recovered: false, timestamp: time), frame: frame, time: time)
            }
            if found != calibration { adopt(found, relock: false) }
            let event = ScanEvent.calibrationRecovered(found)
            events.append(event)
            recorder?.record(event: event, at: time)
            events += feed(.calibrationHealth(health.status, recovered: true, timestamp: time), frame: frame, time: time)
            return events
        }
        let health = calibrator.assess(calibration, on: frame, dartsOnBoard: dartsOnBoard)
        lastHealth = health
        if health.status == .drifted, settings.scan.enableDriftCorrection,
           let recovered = calibrator.recover(calibration, on: frame) {
            // Row K1.
            let shift = simd_distance(calibration.pose.center, recovered.pose.center)
            adopt(recovered, relock: true)
            if shift.isFinite, shift > settings.scan.relockCameraShiftLimit { skipNextDetection = true }
            let event = ScanEvent.calibrationAdjusted(recovered)
            events.append(event)
            recorder?.record(event: event, at: time)
            events += feed(.calibrationHealth(.drifted, recovered: true, timestamp: time), frame: frame, time: time)
            return events
        }
        return feed(.calibrationHealth(health.status, recovered: false, timestamp: time), frame: frame, time: time)
    }

    /// Optional layer: the automatic locator on the current frame, then a full calibration from its handles. Of
    /// the ten orientations it returns, the one closest to the lost calibration's handles is taken (the board did not
    /// turn on its wall). Nil without a locator or when the calibration fails.
    private func locate(on frame: Frame, replacing calibration: BoardCalibration) -> BoardCalibration? {
        guard let locator else { return nil }
        let still = frame.makeRGBImage()
        guard let location = locator.locate(in: still, upDirection: SIMD2(0, -1)) else { return nil }
        let old = calibration.handles.points
        func distance(_ handles: CalibrationHandles) -> Double {
            guard handles.points.count == old.count else { return .infinity }
            var total = 0.0
            for (a, b) in zip(handles.points, old) {
                total += hypot(a.x - b.x, a.y - b.y)
            }
            return total
        }
        var best = location.handles
        var bestDistance = distance(best)
        for alternative in location.alternatives {
            let value = distance(alternative)
            if value < bestDistance {
                best = alternative
                bestDistance = value
            }
        }
        switch calibrator.calibrate(handles: best, still: still, rotationDegrees: calibration.rotationDegrees,
                                    intrinsics: calibration.intrinsics) {
        case .success(let found):
            return found
        case .failure:
            return nil
        }
    }
}
