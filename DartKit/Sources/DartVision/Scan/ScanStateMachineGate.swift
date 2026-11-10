import Foundation
import DartCore

// Gate samples: every timer and every frame counter of the reducer (VISION.md §6.1 to §6.3).
extension ScanStateMachine {
    mutating func gate(_ sample: GateSample, _ out: inout Output) {
        switch phase {
        case .needsCalibration, .idle, .analysing, .paused:
            return
        case .arming:
            armingSample(sample, &out)
        case .rest(let rest):
            // Manual trigger: nothing is processed between two capture commands.
            if currentTrigger == .automatic { restSample(rest, sample, &out) }
        case .motion:
            motionSample(sample, &out)
        case .settling:
            if capture != nil { captureSample(sample, &out) } else { settlingSample(sample, &out) }
        case .obstructed:
            if obstructionMoving { obstructionMotionSample(sample, &out) } else { obstructionSample(sample, &out) }
        case .calibrationLost:
            relockSample(sample, &out)
        }
    }

    // MARK: Arming (rows 3, P2, P3, K4, DM7, DM8)

    private mutating func armingSample(_ sample: GateSample, _ out: inout Output) {
        guard isQuiet(sample) else {
            if accumulating { discard(&out) }
            quietCount = 0
            if armingBegin == 0 { begin(&out) }
            return
        }
        quietCount += 1
        if quietCount >= armingTarget {
            completeArming(at: sample.timestamp, &out)
        } else if quietCount == armingBegin {
            begin(&out)
        }
    }

    mutating func completeArming(at time: TimeInterval?, _ out: inout Output) {
        accumulating = false
        quietCount = 0
        switch armingPurpose {
        case .start(let boardConfirmedEmpty):
            // Row 3. `arm` already cleared the counters and the known darts.
            emptyReference = boardConfirmedEmpty ? .fresh : .unknown
            out.work.append(.updateReference(boardConfirmedEmpty ? .rollingAndEmpty : .rolling))
            out.work.append(.setGateReference)
            out.request = .checkCalibration
            enterRest(.watching, at: time)
        case .confirmEmpty:
            // Row P3: the visit counters are kept.
            takeEmptyReference(&out)
            out.request = .checkCalibration
            enterRest(.watching, at: time)
        case .resume(let rest):
            if currentTrigger == .automatic {
                // Rows P2 and DM8: compare the settled image with the rolling reference.
                phase = .analysing
                analysis = .resume(returnTo: rest)
                out.request = .analyse(maxNewDarts: 1)
            } else {
                // Row DM7: the board is not watched in this mode, nothing to compare; references kept.
                out.request = .checkCalibration
                enterRest(rest, at: time)
            }
        case .recovery(let rest):
            // Row K4.
            out.work.append(.updateReference(.rolling))
            if !known.isEmpty {
                out.work.append(.updateReference(.markEmptyStale))
                if emptyReference == .fresh { emptyReference = .stale }
            }
            out.work.append(.setGateReference)
            enterRest(rest, at: time)
        }
    }

    /// `E := R := S`, silhouettes cleared: the board is empty by the player's word or by a complete takeout.
    mutating func takeEmptyReference(_ out: inout Output) {
        known = []
        unseenDartOnBoard = false
        emptyReference = .fresh
        accumulating = false
        out.work.append(.updateReference(.rollingAndEmpty))
        out.work.append(.setGateReference)
    }

    // MARK: Still states (rows 4, 9, 10, A9)

    private mutating func restSample(_ rest: Rest, _ sample: GateSample, _ out: inout Output) {
        if isMoving(sample) {
            startEpisode(from: rest, obstructed: false, sample, &out)
            return
        }
        let now = sample.timestamp
        let since = stillSince ?? now
        let idleCheck = lastIdleCheck ?? now
        let refresh = lastRefresh ?? now
        stillSince = since
        lastIdleCheck = idleCheck
        lastRefresh = refresh

        // Row A9.
        if rest == .takeout, now - since >= parameters.takeoutStallInterval {
            if !known.isEmpty { out.events.append(.takeoutStalled(remaining: known.map(\.id))) }
            if accumulating { discard(&out) }
            enterRest(known.isEmpty ? countersRest : .awaitingTakeout, at: now)
            return
        }

        // Row 10, in progress: four quiet, unchanged frames become the rolling reference, without any event.
        if let count = refreshCount {
            if isQuiet(sample), hasNoLastingChange(sample) {
                if count + 1 >= accumulationFrames {
                    refreshCount = nil
                    accumulating = false
                    lastRefresh = now
                    lastIdleCheck = now
                    out.work.append(.updateReference(.rolling))
                    out.work.append(.setGateReference)
                } else {
                    refreshCount = count + 1
                }
            } else {
                refreshCount = nil
                discard(&out)
            }
            return
        }

        // Row 9.
        if now - idleCheck >= parameters.idleCheckInterval {
            lastIdleCheck = now
            if sample.changeVsReference >= parameters.noLastingChangeFraction {
                forcePose(.analyse, from: rest, obstructed: false, &out)
                return
            }
        }

        // Row 10, start.
        if rest == .watching, now - refresh >= parameters.idleRefreshInterval, isQuiet(sample), hasNoLastingChange(sample) {
            refreshCount = 0
            begin(&out)
        }
    }

    /// Row 4: start of an episode from a still state.
    private mutating func startEpisode(from rest: Rest, obstructed: Bool, _ sample: GateSample, _ out: inout Output) {
        discard(&out)
        refreshCount = nil
        probe = .idle
        origin = rest
        originObstructed = obstructed
        if !obstructed {
            obstructedSince = nil
            obstructionAdvised = false
        }
        settleIntent = .analyse
        quietCount = 0
        phase = .motion
        openEpisode(sample)
    }

    private mutating func openEpisode(_ sample: GateSample) {
        episode = Episode(start: sample.timestamp, quietRunStart: sample.timestamp, peak: sample.motionFraction,
                          borderRun: 0, borderMax: 0, forcedHand: originObstructed || origin == .takeout)
        track(sample)
    }

    private mutating func track(_ sample: GateSample) {
        guard var current = episode else { return }
        if sample.motionFraction > current.peak { current.peak = sample.motionFraction }
        if sample.borderChange > parameters.handBorderFraction {
            current.borderRun += 1
            current.borderMax = max(current.borderMax, current.borderRun)
        } else {
            current.borderRun = 0
        }
        episode = current
    }

    /// A pose without an episode: idle check (row 9), `confirmBoardEmpty` or `rebaseline` from a still state, new
    /// analysis after a realignment (row A13, `kind: .handLike`). The view is already still, so the frames to skip
    /// are counted as seen.
    mutating func forcePose(_ intent: SettleIntent, from rest: Rest, obstructed: Bool, kind: EpisodeKind = .none,
                            _ out: inout Output) {
        if accumulating { discard(&out) }
        poseKind = kind
        refreshCount = nil
        probe = .idle
        obstructionMoving = false
        origin = rest
        originObstructed = obstructed
        if !obstructed {
            obstructedSince = nil
            obstructionAdvised = false
        }
        episode = nil
        capture = nil
        settleIntent = intent
        quietCount = settleStart
        phase = .settling
        begin(&out)
    }

    // MARK: Episodes (rows 5 to 8)

    /// Counts the quiet run of a moving view. True when the pose can start (row 5).
    private mutating func countQuiet(_ sample: GateSample) -> Bool {
        guard isQuiet(sample) else {
            quietCount = 0
            return false
        }
        quietCount += 1
        if quietCount == 1 { episode?.quietRunStart = sample.timestamp }
        return quietCount >= settleStart
    }

    private mutating func motionSample(_ sample: GateSample, _ out: inout Output) {
        track(sample)
        if countQuiet(sample) {
            // Row 5.
            phase = .settling
            begin(&out)
            out.request = .checkCalibration
            return
        }
        // Row 8.
        if quietCount == 0, let start = episode?.start, sample.timestamp - start > parameters.motionTimeout {
            phase = .obstructed
            obstructionMoving = true
            obstructionOrigin = origin
            originObstructed = true
            episode?.forcedHand = true
            probe = .idle
            escalationAnchor = nil
            if obstructedSince == nil { obstructedSince = sample.timestamp }
            if !obstructionAdvised {
                obstructionAdvised = true
                out.events.append(.advisory(.viewObstructed))
            }
        }
    }

    private mutating func settlingSample(_ sample: GateSample, _ out: inout Output) {
        guard isQuiet(sample) else {
            // Row 6.
            discard(&out)
            quietCount = 0
            phase = .motion
            if episode == nil { openEpisode(sample) } else { track(sample) }
            return
        }
        track(sample)
        quietCount += 1
        if quietCount >= settleTarget { completePose(sample, &out) }
    }

    /// Row 7: the sixth quiet frame.
    private mutating func completePose(_ sample: GateSample, _ out: inout Output) {
        let kind: EpisodeKind
        if let finished = episode {
            let summary = EpisodeSummary(duration: max(0, finished.quietRunStart - finished.start),
                                         peakMotionFraction: finished.peak, borderIntrusionFrames: finished.borderMax)
            episodeSummary = summary
            kind = finished.forcedHand || summary.isHandLike(parameters) ? .handLike : .throwLike
        } else {
            kind = poseKind
        }
        episode = nil
        quietCount = 0
        switch settleIntent {
        case .takeEmpty:
            takeEmptyReference(&out)
            // The pose of an episode was already checked at its second quiet frame (row 5).
            if kind == .none { out.request = .checkCalibration }
            enterRest(.watching, at: sample.timestamp)
        case .rebaseline:
            accumulating = false
            out.work.append(.updateReference(.rolling))
            out.work.append(.setGateReference)
            enterRest(origin, at: sample.timestamp)
        case .analyse:
            if hasNoLastingChange(sample) {
                episodeOutcome(.noChange, kind: kind, at: sample.timestamp, analysed: false, &out)
            } else {
                phase = .analysing
                analysis = .episode(kind)
                out.request = .analyse(maxNewDarts: 1)
            }
        }
    }

    // MARK: Obstruction (rows 8, A12, A13)

    /// Entered by row 8 while the view still moves: wait for it to calm down, then pose and analyse (A12).
    private mutating func obstructionMotionSample(_ sample: GateSample, _ out: inout Output) {
        track(sample)
        if countQuiet(sample) {
            obstructionMoving = false
            origin = obstructionOrigin
            originObstructed = true
            phase = .settling
            begin(&out)
            out.request = .checkCalibration
        }
    }

    private mutating func obstructionSample(_ sample: GateSample, _ out: inout Output) {
        if isMoving(sample) {
            startEpisode(from: obstructionOrigin, obstructed: true, sample, &out)
            return
        }
        let now = sample.timestamp
        let anchor = escalationAnchor ?? now
        escalationAnchor = anchor
        if obstructedSince == nil { obstructedSince = now }
        switch probe {
        case .idle:
            // Row A13: still for 2 s. The drift check decides (`obstructionVerdict`).
            if now - anchor >= parameters.obstructionEscalation {
                probe = .awaitingHealth
                escalationAnchor = now
                out.request = .checkCalibration
            }
        case .awaitingHealth:
            // The engine answers at once; if it never does, ask again two seconds later instead of waiting for ever.
            if now - anchor >= parameters.obstructionEscalation {
                escalationAnchor = now
                out.request = .checkCalibration
            }
        case .absorbing(let count):
            if !isQuiet(sample) {
                // Not still any more: start the two seconds again.
                probe = .idle
                escalationAnchor = now
                discard(&out)
            } else if count + 1 >= accumulationFrames {
                // A13, healthy: `unrecognizedChange`, `R := S`, silhouettes kept, back to the previous state.
                probe = .idle
                out.events.append(.unrecognizedChange)
                absorb(&out)
                enterRest(obstructionOrigin, at: now)
            } else {
                probe = .absorbing(count + 1)
            }
        }
    }

    // MARK: Manual capture (rows DM2, DM3, DM5, DM6)

    private mutating func captureSample(_ sample: GateSample, _ out: inout Output) {
        guard var current = capture else { return }
        let first = current.firstSample ?? sample.timestamp
        current.firstSample = first
        capture = current
        let quiet = isQuiet(sample)
        if quiet, quietCount + 1 >= settleTarget {
            completeCapture(current.kind, at: sample.timestamp, &out)
            return
        }
        // Row DM6: no sixth quiet frame `captureTimeout` after the first sample.
        if sample.timestamp - first >= parameters.captureTimeout {
            discard(&out)
            out.events.append(.advisory(.viewObstructed))
            if case .scan = current.kind { out.closing = .scanCompleted([]) }
            enterRest(origin, at: sample.timestamp)
            return
        }
        if quiet {
            quietCount += 1
            if quietCount == settleStart {
                begin(&out)
                out.request = .checkCalibration
            }
        } else {
            // A moving frame throws the accumulation away and restarts the count; the state does not change.
            if accumulating { discard(&out) }
            quietCount = 0
        }
    }

    private mutating func completeCapture(_ kind: CaptureKind, at time: TimeInterval, _ out: inout Output) {
        quietCount = 0
        capture = nil
        switch kind {
        case .reference:
            takeEmptyReference(&out)
            enterRest(origin, at: time)
        case .rebaseline:
            accumulating = false
            out.work.append(.updateReference(.rolling))
            out.work.append(.setGateReference)
            enterRest(origin, at: time)
        case .scan(let maxDarts):
            phase = .analysing
            analysis = .scan(maxDarts: maxDarts)
            out.request = .analyse(maxNewDarts: maxDarts)
        }
    }

    // MARK: Calibration lost (row K3)

    private mutating func relockSample(_ sample: GateSample, _ out: inout Output) {
        guard isQuiet(sample) else {
            relockQuietSince = nil
            return
        }
        guard let since = relockQuietSince else {
            relockQuietSince = sample.timestamp
            return
        }
        if sample.timestamp - since >= parameters.relockRetryInterval {
            relockQuietSince = sample.timestamp
            out.request = .checkCalibration
        }
    }
}
