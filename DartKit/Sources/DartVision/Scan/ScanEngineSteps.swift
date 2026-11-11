import Foundation
import simd
import DartCore

// Frames, commands and the effects of the reducer (lot V5, VISION.md §6).
extension ScanEngine {
    /// Records kept for corrections and feedback.
    static let recordLimit = 64
    /// Most recent darts whose settled image is kept for the evidence crop.
    static let evidenceLimit = 6
    /// Gate samples kept for the recorder between two analyses.
    static let gateHistoryLimit = 300
    /// Ripple of the arming `meanLuma`, after removing its linear trend, that reveals flicker (VISION.md §2.4: 1 %).
    static let flickerRipple = 0.01

    // MARK: Frames

    func processFrame(_ frame: Frame) -> [ScanEvent] {
        guard let calibration = currentCalibration, frame.size == calibration.imageSize, var gate else { return [] }
        lastTime = frame.timestamp
        guard gateIsNeeded else {
            gateRunning = false
            return []
        }
        if !gateRunning { gate.restart() }
        let sample = gate.ingest(frame)
        self.gate = gate
        lastGate = sample
        guard gateRunning else {
            // "Porte relancée": the first sample compares with an old frame (or none) and is dropped.
            gateRunning = true
            return []
        }
        gateSinceAnalysis.append(sample)
        if gateSinceAnalysis.count > ScanEngine.gateHistoryLimit {
            gateSinceAnalysis.removeFirst(gateSinceAnalysis.count - ScanEngine.gateHistoryLimit)
        }
        var events: [ScanEvent] = []
        if pendingCheck {
            pendingCheck = false
            events += checkCalibration(frame: frame, time: sample.timestamp)
        }
        switch machine.state {
        case .watching, .awaitingTakeout, .takeout, .obstructed: episodeMotionFrames = 0
        default: break
        }
        if sample.motionFraction > settings.scan.motionOnFraction { episodeMotionFrames += 1 }
        let wasArming = machine.state == .arming
        if wasArming {
            if sample.motionFraction < settings.scan.quietFraction { armingLuma.append(sample.meanLuma) } else { armingLuma = [] }
        }
        pendingFrame = machine.accumulating ? frame : nil
        let effects = machine.handle(.gate(sample))
        // The noise is measured before the effects read the settled image; the flicker advisory follows the
        // events of the transition (`stateChanged` first).
        let flicker = wasArming && machine.state != .arming ? armingCompleted() : []
        events += execute(effects, frame: frame, time: sample.timestamp)
        events += flicker
        // A frame of an accumulation that goes on is added now; one whose accumulation ended unread is not needed.
        if machine.accumulating { flushPendingFrame() }
        pendingFrame = nil
        settleGate()
        return events
    }

    /// The reducer reads gate samples in this state.
    var gateIsNeeded: Bool {
        switch machine.state {
        case .needsCalibration, .idle, .paused, .analysing:
            return false
        case .watching, .awaitingTakeout, .takeout:
            return machine.trigger == .automatic
        case .arming, .motion, .settling, .obstructed, .calibrationLost:
            return true
        }
    }

    /// The source (re)started: the next frame restarts the gate instead of comparing with an old one.
    func restartGate() {
        gateRunning = false
    }

    /// Stops the gate as soon as the reducer stops reading it, so that it restarts on a fresh frame.
    func settleGate() {
        if !gateIsNeeded { gateRunning = false }
    }

    /// The last arming frame was just handled: the accumulator holds its last frames.
    private func armingCompleted() -> [ScanEvent] {
        flushPendingFrame()
        if let sigma = accumulator.noiseSigma(), sigma.isFinite { detectionNoise = sigma }
        gate?.commitNoise(frames: settings.scan.armingFrames)
        var events: [ScanEvent] = []
        if !flickerChecked, armingLuma.count >= 4 {
            flickerChecked = true
            if ScanEngine.ripple(of: armingLuma) > ScanEngine.flickerRipple {
                events.append(.advisory(.flicker))
                recorder?.record(event: .advisory(.flicker), at: lastTime)
            }
        }
        armingLuma = []
        return events
    }

    /// Peak-to-peak of the residuals of a least-squares line through `values`, relative to their mean.
    static func ripple(of values: [Double]) -> Double {
        let count = Double(values.count)
        guard values.count >= 2 else { return 0 }
        var sumX = 0.0, sumY = 0.0, sumXX = 0.0, sumXY = 0.0
        for (index, value) in values.enumerated() {
            let x = Double(index)
            sumX += x
            sumY += value
            sumXX += x * x
            sumXY += x * value
        }
        let mean = sumY / count
        guard mean > 0 else { return 0 }
        let denominator = count * sumXX - sumX * sumX
        let slope = denominator != 0 ? (count * sumXY - sumX * sumY) / denominator : 0
        let intercept = (sumY - slope * sumX) / count
        var low = Double.infinity, high = -Double.infinity
        for (index, value) in values.enumerated() {
            let residual = value - (intercept + slope * Double(index))
            low = min(low, residual)
            high = max(high, residual)
        }
        return (high - low) / mean
    }

    // MARK: Commands

    func handleCommand(_ command: ScanCommand) -> [ScanEvent] {
        switch command {
        case .discardDart(let id):
            // A false positive: its footprint stays in `R`, the vision forgets it.
            giveFeedback(id, wasCorrected: true, correctedTip: nil, phantom: true)
            known.removeAll { $0.id == id }
        case .arm:
            flickerChecked = false
        default:
            break
        }
        let effects = machine.handle(.command(command))
        if case .arm = command, machine.state == .arming || machine.state == .calibrationLost {
            // Row 2: references, silhouettes and gate reference cleared, gate restarted.
            clearReferences()
            gate?.clearReference()
            gateRunning = false
            armingLuma = []
        }
        let events = execute(effects, frame: nil, time: lastTime)
        settleGate()
        return events
    }

    // MARK: Calibration

    func installCalibration(_ calibration: BoardCalibration) {
        currentCalibration = calibration
        rectifier = BoardRectifier(calibration: calibration)
        let previousNoise = gate?.noiseSigma
        var newGate = MotionGate(calibration: calibration, parameters: settings.scan)
        if let previousNoise, previousNoise > 0 { newGate.adoptNoise(previousNoise) }
        gate = newGate
        gateRunning = false
        clearReferences()
        pendingCheck = false
        relockedForNextEvent = false
        skipNextDetection = false
        warmUpRemaining = calibration.id == verifiedCalibrationID ? 0 : max(0, settings.confidence.warmUpDarts)
        recorder?.record(calibration: calibration)
    }

    /// A calibration found by the drift check or the recovery replaces the current one (§4.9).
    ///
    /// A relock (K1, A13) keeps the gate on its region, which only needs to cover the board for motion, and clears
    /// its reference: the gate image of the last settle no longer lines up with the board, so the pose in progress is
    /// analysed instead of being read as "no lasting change" (row 7). A recovery (K3) moves the gate to the new region
    /// and restarts it; the arming of row K4 takes its reference.
    func adopt(_ calibration: BoardCalibration, relock: Bool) {
        currentCalibration = calibration
        rectifier = BoardRectifier(calibration: calibration)
        if relock {
            gate?.clearReference()
            relockedForNextEvent = true
        } else {
            gate = gate?.rebased(on: calibration) ?? MotionGate(calibration: calibration, parameters: settings.scan)
            gate?.clearReference()
            gateRunning = false
        }
        for index in known.indices {
            known[index].predatesRelock = true
        }
        recorder?.record(calibration: calibration)
    }

    /// References, silhouettes and the accumulation of the previous game or calibration.
    func clearReferences() {
        rolling = nil
        empty = nil
        emptyIsFresh = false
        known = []
        accumulator.reset()
        settledCache = nil
        pendingFrame = nil
        pendingSilhouettes = []
        analysisScene = nil
        relockedForNextEvent = false
        skipNextDetection = false
    }

    // MARK: Effects

    /// Feeds one input to the reducer and executes its effects.
    func feed(_ input: ScanInput, frame: Frame?, time: TimeInterval) -> [ScanEvent] {
        let effects = machine.handle(input)
        return execute(effects, frame: frame, time: time)
    }

    func execute(_ effects: [ScanEffect], frame: Frame?, time: TimeInterval) -> [ScanEvent] {
        var events: [ScanEvent] = []
        for effect in effects {
            switch effect {
            case .discardAccumulation, .beginAccumulation:
                accumulator.reset()
                settledCache = nil
                pendingFrame = nil
            case .analyse(let maxNewDarts):
                flushPendingFrame()
                events += analyse(maxNewDarts: maxNewDarts, frame: frame, time: time)
            case .checkCalibration:
                if let frame {
                    events += checkCalibration(frame: frame, time: time)
                } else {
                    pendingCheck = true
                }
            case .updateReference(let update):
                flushPendingFrame()
                applyReferenceUpdate(update)
            case .setGateReference:
                gate?.setReferenceToCurrent()
            case .emit(let event):
                events.append(event)
                remember(event)
                recorder?.record(event: event, at: time)
            }
        }
        return events
    }

    /// Adds the frame of the current call to the accumulator, once.
    func flushPendingFrame() {
        guard let frame = pendingFrame, let rectifier else { return }
        pendingFrame = nil
        accumulator.add(rectifier.rectify(frame))
        settledCache = nil
    }

    /// The settled image `S`: the mean of the accumulated frames.
    func settledImage() -> CanvasImage? {
        if let settledCache { return settledCache }
        settledCache = accumulator.mean()
        return settledCache
    }

    func applyReferenceUpdate(_ update: ReferenceUpdate) {
        switch update {
        case .rolling:
            if let settled = settledImage() { rolling = settled }
        case .rollingAndEmpty:
            if let settled = settledImage() {
                rolling = settled
                empty = settled
                emptyIsFresh = true
            }
            known = []
        case .rollingFromEmpty:
            if let empty { rolling = empty }
            known = []
        case .markEmptyStale:
            emptyIsFresh = false
        }
    }

    /// Bookkeeping of an emitted event: silhouettes of new darts, forgotten silhouettes.
    func remember(_ event: ScanEvent) {
        switch event {
        case .dart(let observation):
            commit(observation)
        case .scanCompleted(let observations):
            for observation in observations {
                commit(observation)
            }
        case .dartRemoved(let id, _):
            known.removeAll { $0.id == id }
        default:
            break
        }
    }

    private func commit(_ observation: DartObservation) {
        let silhouette = pendingSilhouettes.first { $0.id == observation.id }?.silhouette ?? CanvasMask()
        known.removeAll { $0.id == observation.id }
        known.append(ScanEngineDart(id: observation.id, observation: observation, tip: observation.tip,
                                    silhouette: silhouette, predatesRelock: false))
        records.append(ScanEngineRecord(observation: observation, scene: analysisScene?.current))
        if records.count > ScanEngine.recordLimit { records.removeFirst(records.count - ScanEngine.recordLimit) }
        // The settled images of older darts are released.
        var withScene = 0
        for index in records.indices.reversed() where records[index].scene != nil {
            withScene += 1
            if withScene > ScanEngine.evidenceLimit { records[index].scene = nil }
        }
        if let analysisScene { lastDartScene = analysisScene }
    }

    // MARK: Feedback

    func giveFeedback(_ id: UUID, wasCorrected: Bool, correctedTip: BoardPoint?, phantom: Bool) {
        guard let index = records.lastIndex(where: { $0.observation.id == id }), !records[index].fedBack else { return }
        records[index].fedBack = true
        let observation = records[index].observation
        let degraded = trust.accuracyDegraded
        let lighting = trust.shouldSuggestLightingCheck
        let scanMode = trust.shouldSuggestScanMode
        trust.record(tier: observation.tier, wasCorrected: wasCorrected)
        if !degraded, trust.accuracyDegraded { pendingEvents.append(.advisory(.accuracyDegraded)) }
        if !lighting, trust.shouldSuggestLightingCheck { pendingEvents.append(.advisory(.suggestLightingCheck)) }
        if !scanMode, trust.shouldSuggestScanMode { pendingEvents.append(.advisory(.suggestScanMode)) }
        if wasCorrected {
            recorder?.record(correctionOf: observation, correctedTip: phantom ? nil : (correctedTip ?? records[index].correctedTip))
        }
    }

    func takePendingEvents() -> [ScanEvent] {
        let events = pendingEvents
        pendingEvents = []
        for event in events {
            recorder?.record(event: event, at: lastTime)
        }
        return events
    }

    // MARK: Configuration

    func applyConfiguration(_ newValue: VisionConfiguration) {
        let old = settings
        settings = newValue
        if newValue.calibration != old.calibration { calibrator = BoardCalibrator(parameters: newValue.calibration) }
        if newValue.confidence != old.confidence {
            confidenceModel = ConfidenceModel(board: board, parameters: newValue.confidence)
            trust = TrustTracker(parameters: newValue.confidence)
        }
        guard newValue.scan != old.scan else { return }
        // The reducer keeps its constants for life: a new one starts from the current calibration, in `idle`
        // (row 1), with the current trigger. A capture in progress is closed by the old one.
        let trigger = machine.trigger
        if currentCalibration != nil {
            pendingEvents += feed(.calibrationSet, frame: nil, time: lastTime)
        }
        machine = ScanStateMachine(parameters: newValue.scan)
        if trigger != machine.trigger { _ = machine.handle(.command(.setTrigger(trigger))) }
        if currentCalibration != nil {
            _ = machine.handle(.calibrationSet)
            clearReferences()
        }
        gate = gate?.reparameterised(newValue.scan)
        gateRunning = false
    }
}
