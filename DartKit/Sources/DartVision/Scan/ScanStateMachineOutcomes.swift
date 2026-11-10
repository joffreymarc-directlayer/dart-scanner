import Foundation
import DartCore

// Outcomes of an analysis (tables "Issues de l'analyse" and "Issues d'un scan") and calibration rows K1 to K5.
extension ScanStateMachine {
    mutating func settle(_ outcome: SettleOutcome, at time: TimeInterval, _ out: inout Output) {
        guard phase == .analysing else { return }
        accumulating = false
        switch analysis {
        case .episode(let kind):
            episodeOutcome(outcome, kind: kind, at: time, analysed: true, &out)
        case .resume(let rest):
            resumeOutcome(outcome, returnTo: rest, at: time, &out)
        case .scan:
            scanOutcome(outcome, at: time, &out)
        }
    }

    // MARK: Automatic trigger (rows A1 to A16)

    /// `analysed` is false when the gate already showed that nothing lasting changed (row 7) and no analysis ran.
    mutating func episodeOutcome(_ outcome: SettleOutcome, kind: EpisodeKind, at time: TimeInterval, analysed: Bool,
                                 _ out: inout Output) {
        switch outcome {
        case .noChange:
            switch kind {
            case .throwLike:
                // A5.
                out.events.append(.possibleMiss(timestamp: time))
                if !analysed { discard(&out) }
            case .handLike:
                // A6.
                if !analysed { discard(&out) }
            case .none:
                // Rows 9 and 10: an unchanged still board is absorbed by the rolling reference.
                out.work.append(.updateReference(.rolling))
                out.work.append(.setGateReference)
            }
            enterRest(origin, at: time)

        case .darts(let new, let removed, let disturbed):
            let gone = knownIDs(in: removed, excluding: [])
            let moved = knownIDs(in: disturbed, excluding: gone)
            let fresh = newDarts(in: new)
            if fresh.isEmpty {
                if !gone.isEmpty {
                    removal(of: gone, boardEmpty: gone.count == known.count, disturbed: moved, kind: kind, at: time, &out)
                } else if !moved.isEmpty {
                    out.events.append(contentsOf: moved.map { ScanEvent.dartDisturbed(id: $0) })
                    absorb(&out)
                    enterRest(origin, at: time)
                } else {
                    episodeOutcome(.noChange, kind: kind, at: time, analysed: analysed, &out)
                }
                return
            }
            // A4: with a new shape, darts that left the board fell out.
            forget(gone)
            out.events.append(contentsOf: gone.map { ScanEvent.dartRemoved(id: $0, reason: .fellOut) })
            out.events.append(contentsOf: moved.map { ScanEvent.dartDisturbed(id: $0) })
            let earlierDisturbed = !gone.isEmpty || !moved.isEmpty
            // The rule the engine reads before the settle input (A3), applied to the counters before any commit.
            let beyond = fresh.indices.map { isBeyondVisitLimit(newDartOffset: $0) }
            for (index, observation) in fresh.enumerated() {
                var flags = observation.flags
                if beyond[index] { flags.insert(.beyondVisitLimit) }
                if earlierDisturbed { flags.insert(.earlierDartDisturbed) }
                out.events.append(.dart(commit(observation, flags: flags)))
            }
            absorb(&out)
            // A1, A2, A3.
            enterRest(countersRest, at: time)

        case .removed(let ids, let boardEmpty):
            var gone = knownIDs(in: ids, excluding: [])
            if boardEmpty { gone.append(contentsOf: known.map(\.id).filter { !gone.contains($0) }) }
            if gone.isEmpty {
                // Nothing known left the board: handled like the ghost guard (A15).
                absorb(&out)
                enterRest(origin, at: time)
            } else {
                removal(of: gone, boardEmpty: boardEmpty, disturbed: [], kind: kind, at: time, &out)
            }

        case .obstruction:
            // A11: `R` is kept.
            if !originObstructed {
                obstructedSince = time
                obstructionAdvised = false
            }
            obstructionOrigin = origin
            obstructionMoving = false
            probe = .idle
            escalationAnchor = time
            refreshCount = nil
            episode = nil
            phase = .obstructed

        case .lightingChanged:
            // A14.
            out.events.append(.lightingChanged)
            if known.isEmpty, !unseenDartOnBoard {
                emptyReference = .fresh
                out.work.append(.updateReference(.rollingAndEmpty))
            } else {
                if emptyReference == .fresh { emptyReference = .stale }
                out.work.append(.updateReference(.rolling))
                out.work.append(.updateReference(.markEmptyStale))
            }
            out.work.append(.setGateReference)
            enterRest(origin, at: time)

        case .foreignRemoval:
            // A15.
            absorb(&out)
            enterRest(origin, at: time)

        case .unrecognized:
            // A16.
            out.events.append(.unrecognizedChange)
            absorb(&out)
            enterRest(origin, at: time)
        }
    }

    /// Known darts left the board and nothing new appeared: A10 first, then A7 and A8.
    private mutating func removal(of gone: [UUID], boardEmpty: Bool, disturbed: [UUID], kind: EpisodeKind,
                                  at time: TimeInterval, _ out: inout Output) {
        // Darts left over from an earlier visit are pulled without any takeout event (§6.5, `beginVisit`).
        let announced = origin == .takeout || known.contains { gone.contains($0.id) && $0.visit == visitCounter }
        forget(gone)
        let moved = disturbed.map { ScanEvent.dartDisturbed(id: $0) }

        if kind == .throwLike {
            // A10: the darts fell out, even when the board ends up empty. `E` is untouched.
            out.events.append(contentsOf: gone.map { ScanEvent.dartRemoved(id: $0, reason: .fellOut) })
            out.events.append(contentsOf: moved)
            absorb(&out)
            enterRest(.watching, at: time)
            return
        }

        let pulled = gone.map { ScanEvent.dartRemoved(id: $0, reason: .takeout) }
        if known.isEmpty {
            out.events.append(contentsOf: pulled)
            out.events.append(contentsOf: moved)
            if boardEmpty {
                // A7.
                if announced { out.events.append(.takeoutCompleted) }
                takeEmptyReference(&out)
                out.request = .checkCalibration
            } else {
                // Every known dart is gone but the engine still sees something: no empty reference.
                absorb(&out)
            }
            enterRest(.watching, at: time)
        } else if announced {
            // A8.
            if origin != .takeout { out.events.append(.takeoutStarted) }
            out.events.append(contentsOf: pulled)
            out.events.append(contentsOf: moved)
            absorb(&out)
            enterRest(.takeout, at: time)
        } else {
            out.events.append(contentsOf: pulled)
            out.events.append(contentsOf: moved)
            absorb(&out)
            enterRest(origin, at: time)
        }
    }

    // MARK: After a pause or a trigger change (rows P2 and DM8)

    private mutating func resumeOutcome(_ outcome: SettleOutcome, returnTo rest: Rest, at time: TimeInterval,
                                        _ out: inout Output) {
        if outcome == .noChange {
            absorb(&out)
            enterRest(rest, at: time)
        } else {
            // The scene changed while nobody watched: no dart event, references untouched.
            phase = .idle
            idleNeedsEmptyBoard = true
            out.events.append(.needsEmptyBoard)
        }
    }

    // MARK: Manual trigger (rows DM3a to DM3d)

    private mutating func scanOutcome(_ outcome: SettleOutcome, at time: TimeInterval, _ out: inout Output) {
        var observations: [DartObservation] = []
        switch outcome {
        case .noChange, .foreignRemoval:
            break
        case .obstruction:
            out.events.append(.advisory(.viewObstructed))
        case .lightingChanged:
            out.events.append(.lightingChanged)
        case .unrecognized:
            out.events.append(.unrecognizedChange)
        case .removed(let ids, let boardEmpty):
            var gone = knownIDs(in: ids, excluding: [])
            if boardEmpty { gone.append(contentsOf: known.map(\.id).filter { !gone.contains($0) }) }
            if !gone.isEmpty {
                // DM3c: `E` is untouched, even on an empty board.
                forget(gone)
                out.events.append(contentsOf: gone.map { ScanEvent.dartRemoved(id: $0, reason: .takeout) })
                absorb(&out)
            }
        case .darts(let new, let removed, let disturbed):
            let gone = knownIDs(in: removed, excluding: [])
            let moved = knownIDs(in: disturbed, excluding: gone)
            let fresh = newDarts(in: new)
            forget(gone)
            out.events.append(contentsOf: gone.map { ScanEvent.dartRemoved(id: $0, reason: .takeout) })
            out.events.append(contentsOf: moved.map { ScanEvent.dartDisturbed(id: $0) })
            // A dart beyond the visit carries `beyondVisitLimit`, as in A3.
            let beyond = fresh.indices.map { isBeyondVisitLimit(newDartOffset: $0) }
            for (index, observation) in fresh.enumerated() {
                var flags = observation.flags
                if beyond[index] { flags.insert(.beyondVisitLimit) }
                observations.append(commit(observation, flags: flags))
            }
            // DM3a and DM3c move the rolling reference; a scan that only saw a disturbed dart changes nothing.
            if !fresh.isEmpty || !gone.isEmpty { absorb(&out) }
        }
        out.closing = .scanCompleted(observations)
        enterRest(origin, at: time)
    }

    // MARK: Calibration (rows K1 to K5, A13)

    mutating func health(_ status: CalibrationHealth.Status, recovered: Bool, at time: TimeInterval, _ out: inout Output) {
        let usable = status == .healthy || recovered
        switch phase {
        case .needsCalibration, .idle, .paused:
            return
        case .calibrationLost:
            if usable { recoverCalibration(&out) }
            return
        case .obstructed where probe == .awaitingHealth:
            obstructionVerdict(status, recovered: recovered, at: time, &out)
            return
        default:
            break
        }
        if usable {
            // Healthy, or K1: the engine adopted the corrected calibration.
            lostStreak = 0
        } else if status != .edgesNotVisible {
            // K2. `edgesNotVisible` (K5) says nothing either way.
            lostStreak += 1
            if lostStreak >= 2 { loseCalibration(&out) }
        }
    }

    /// Row A13: the obstruction has been still for 2 s and the drift check answered. Nothing is accumulated yet:
    /// the settled image `S` is taken after the verdict, with the calibration the verdict settled on.
    private mutating func obstructionVerdict(_ status: CalibrationHealth.Status, recovered: Bool, at time: TimeInterval,
                                             _ out: inout Output) {
        probe = .idle
        escalationAnchor = time
        if status == .healthy {
            // Healthy: four quiet frames, then `unrecognizedChange` and `R := S` (see `obstructionSample`).
            lostStreak = 0
            probe = .absorbing(0)
            begin(&out)
        } else if recovered {
            // Drifted and realigned: a new pose on the realigned view, then a new analysis, read as after a hand.
            lostStreak = 0
            forcePose(.analyse, from: obstructionOrigin, obstructed: true, kind: .handLike, &out)
        } else if status == .edgesNotVisible {
            // Stay; advise once the obstruction has lasted `obstructionAdvisoryDelay`.
            if !obstructionAdvised, let since = obstructedSince, time - since >= parameters.obstructionAdvisoryDelay {
                obstructionAdvised = true
                out.events.append(.advisory(.viewObstructed))
            }
        } else {
            // K2: a lost check here counts like a lost pose.
            lostStreak += 1
            if lostStreak >= 2 { loseCalibration(&out) }
        }
    }

    /// Row K2.
    private mutating func loseCalibration(_ out: inout Output) {
        lostReturn = interruptionAnchor
        let scanWasPending = scanIsPending
        abandon(&out)
        lostStreak = 0
        armedWhileLost = nil
        relockQuietSince = nil
        phase = .calibrationLost
        out.events.append(.calibrationLost)
        if scanWasPending { out.closing = .scanCompleted([]) }
    }

    /// Row K4.
    private mutating func recoverCalibration(_ out: inout Output) {
        relockQuietSince = nil
        lostStreak = 0
        if let boardConfirmedEmpty = armedWhileLost {
            // `arm` was received while the calibration was lost: the recovery ends like row 3.
            armedWhileLost = nil
            startArming(.start(boardConfirmedEmpty: boardConfirmedEmpty), &out)
            return
        }
        switch lostReturn {
        case .rest(let rest):
            startArming(.recovery(returnTo: rest), &out)
        case .arming(let purpose):
            startArming(purpose, &out)
        case .idle(let needsEmptyBoard):
            phase = .idle
            idleNeedsEmptyBoard = needsEmptyBoard
            if needsEmptyBoard { out.events.append(.needsEmptyBoard) }
        case .needsCalibration, .calibrationLost:
            phase = .idle
            idleNeedsEmptyBoard = false
        }
    }

    // MARK: Bookkeeping

    /// `R := S` and the gate reference.
    mutating func absorb(_ out: inout Output) {
        accumulating = false
        out.work.append(.updateReference(.rolling))
        out.work.append(.setGateReference)
    }

    /// Identifiers of `ids` that are known darts, without duplicates, in the given order.
    private func knownIDs(in ids: [UUID], excluding excluded: [UUID]) -> [UUID] {
        var result: [UUID] = []
        for id in ids where !result.contains(id) && !excluded.contains(id) && known.contains(where: { $0.id == id }) {
            result.append(id)
        }
        return result
    }

    /// New observations whose identifier is neither known nor repeated.
    private func newDarts(in observations: [DartObservation]) -> [DartObservation] {
        var result: [DartObservation] = []
        for observation in observations
        where !known.contains(where: { $0.id == observation.id }) && !result.contains(where: { $0.id == observation.id }) {
            result.append(observation)
        }
        return result
    }

    private mutating func forget(_ ids: [UUID]) {
        known.removeAll { ids.contains($0.id) }
    }

    /// Counts a new dart and returns the observation to emit: the one received, with `flags`.
    private mutating func commit(_ observation: DartObservation, flags: DartFlags) -> DartObservation {
        known.append(Committed(id: observation.id, visit: visitCounter))
        visitDartIDs.insert(observation.id)
        if visitDarts < Int.max { visitDarts += 1 }
        guard flags != observation.flags else { return observation }
        return DartObservation(id: observation.id, visit: observation.visit, indexInVisit: observation.indexInVisit,
                               timestamp: observation.timestamp, tip: observation.tip, uncertainty: observation.uncertainty,
                               candidates: observation.candidates, nearbyHits: observation.nearbyHits,
                               confidence: observation.confidence, tier: observation.tier, flags: flags,
                               source: observation.source)
    }
}
