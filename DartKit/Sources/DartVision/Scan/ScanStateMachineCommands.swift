import Foundation
import DartCore

// Commands of the game layer (VISION.md §6.5) and the new-calibration input (row 1).
extension ScanStateMachine {
    /// Row 1: any state to `idle`. The visit counters are kept; references and silhouettes are gone.
    mutating func calibrationWasSet(_ out: inout Output) {
        let scanWasPending = scanIsPending
        abandon(&out)
        known = []
        unseenDartOnBoard = false
        emptyReference = .unknown
        lostStreak = 0
        armedWhileLost = nil
        relockQuietSince = nil
        idleNeedsEmptyBoard = false
        phase = .idle
        if scanWasPending { out.closing = .scanCompleted([]) }
    }

    mutating func command(_ command: ScanCommand, _ out: inout Output) {
        switch command {
        case .arm(let boardConfirmedEmpty):
            arm(boardConfirmedEmpty: boardConfirmedEmpty, &out)
        case .beginVisit(let expected):
            beginVisit(expectedDarts: expected, &out)
        case .endVisit:
            visitClosed = true
            mapRests { $0 == .takeout ? .takeout : .awaitingTakeout }
        case .confirmBoardEmpty:
            confirmBoardEmpty(&out)
        case .rebaseline:
            rebaseline(&out)
        case .discardDart(let id):
            discardDart(id)
        case .registerManualDart:
            if visitDarts < Int.max { visitDarts += 1 }
            unseenDartOnBoard = true
            let full = isVisitFullOrClosed
            mapRests { $0 == .watching && full ? .awaitingTakeout : $0 }
        case .setTrigger(let trigger):
            setTrigger(trigger, &out)
        case .captureReference:
            startCapture(.reference)
        case .captureNow(let maxDarts):
            // Nothing to look for: ignored, without `scanCompleted` (row DM3).
            if maxDarts >= 1 { startCapture(.scan(maxDarts: maxDarts)) }
        case .pause(let reason):
            pause(reason, &out)
        case .resume:
            resume(&out)
        }
    }

    // MARK: Start of a game (row 2)

    private mutating func arm(boardConfirmedEmpty: Bool, _ out: inout Output) {
        if case .paused = phase {
            // `arm` leaves every pause. A pause taken without a calibration first returns there, like row P2b.
            switch pausedFrom {
            case .needsCalibration:
                phase = .needsCalibration
            case .calibrationLost:
                phase = .calibrationLost
                relockQuietSince = nil
            case .idle, .arming, .rest:
                break
            }
        }
        switch phase {
        case .needsCalibration:
            // Never arms without a calibration.
            return
        case .calibrationLost:
            // Counters cleared and `boardConfirmedEmpty` kept: the recovery (K4) then ends like row 3.
            resetGame()
            armedWhileLost = boardConfirmedEmpty
        default:
            let scanWasPending = scanIsPending
            abandon(&out)
            resetGame()
            startArming(.start(boardConfirmedEmpty: boardConfirmedEmpty), &out)
            if scanWasPending { out.closing = .scanCompleted([]) }
        }
    }

    private mutating func resetGame() {
        known = []
        visitCounter = 0
        visitDarts = 0
        expectedDarts = max(0, parameters.expectedDartsPerVisit)
        visitClosed = false
        visitDartIDs = []
        unseenDartOnBoard = false
        emptyReference = .unknown
        episodeSummary = nil
        lostStreak = 0
        idleNeedsEmptyBoard = false
    }

    // MARK: Counters

    private mutating func beginVisit(expectedDarts expected: Int, _ out: inout Output) {
        if visitCounter < Int.max { visitCounter += 1 }
        visitDarts = 0
        expectedDarts = max(0, expected)
        visitClosed = false
        visitDartIDs = []
        if currentTrigger == .manual, case .rest = phase {
            // Row DM4: a whole visit on a board the player cleared starts again from the empty reference.
            if expected == parameters.expectedDartsPerVisit, emptyReference != .unknown {
                known = []
                unseenDartOnBoard = false
                out.work.append(.updateReference(.rollingFromEmpty))
            }
        }
        // From `awaitingTakeout` (and from a takeout the next player interrupts) back to `watching(n)`: the darts
        // still on the board belong to an earlier visit, and pulling them only emits `dartRemoved`.
        let rest = countersRest
        mapRests { _ in rest }
    }

    private mutating func discardDart(_ id: UUID) {
        known.removeAll { $0.id == id }
        if visitDartIDs.remove(id) != nil, visitDarts > 0 { visitDarts -= 1 }
        let rest = countersRest
        let boardIsBare = known.isEmpty
        mapRests { current in
            switch current {
            case .watching: return .watching
            case .awaitingTakeout: return rest
            case .takeout: return boardIsBare ? rest : .takeout
            }
        }
    }

    // MARK: References

    private mutating func confirmBoardEmpty(_ out: inout Output) {
        switch phase {
        case .idle:
            // Row P3.
            idleNeedsEmptyBoard = false
            startArming(.confirmEmpty, &out)
        case .rest(let rest):
            if currentTrigger == .manual {
                startCapture(.reference)
            } else {
                forcePose(.takeEmpty, from: rest, obstructed: false, &out)
            }
        case .obstructed:
            if obstructionMoving {
                settleIntent = .takeEmpty
            } else {
                forcePose(.takeEmpty, from: obstructionOrigin, obstructed: true, &out)
            }
        case .motion:
            settleIntent = .takeEmpty
        case .settling:
            // The pose of the running episode serves. A manual capture in progress is not replaced.
            if capture == nil { settleIntent = .takeEmpty }
        case .needsCalibration, .arming, .analysing, .calibrationLost, .paused:
            return
        }
    }

    private mutating func rebaseline(_ out: inout Output) {
        switch phase {
        case .rest(let rest):
            if currentTrigger == .manual {
                startCapture(.rebaseline)
            } else {
                forcePose(.rebaseline, from: rest, obstructed: false, &out)
            }
        case .obstructed:
            if obstructionMoving {
                if settleIntent == .analyse { settleIntent = .rebaseline }
            } else {
                forcePose(.rebaseline, from: obstructionOrigin, obstructed: true, &out)
            }
        case .motion:
            if settleIntent == .analyse { settleIntent = .rebaseline }
        case .settling:
            if capture == nil, settleIntent == .analyse { settleIntent = .rebaseline }
        case .needsCalibration, .idle, .arming, .analysing, .calibrationLost, .paused:
            return
        }
    }

    // MARK: Manual trigger (rows DM1 to DM8)

    /// Rows DM2, DM3 and DM5: accepted at rest in manual trigger only.
    private mutating func startCapture(_ kind: CaptureKind) {
        guard currentTrigger == .manual, case .rest(let rest) = phase else { return }
        origin = rest
        originObstructed = false
        episode = nil
        settleIntent = .analyse
        quietCount = 0
        capture = Capture(kind: kind, firstSample: nil)
        phase = .settling
    }

    private mutating func setTrigger(_ trigger: ScanTrigger, _ out: inout Output) {
        guard trigger != currentTrigger else { return }
        currentTrigger = trigger
        switch trigger {
        case .manual:
            // Row DM1: a still state or an episode becomes the rest of the manual trigger.
            switch phase {
            case .rest, .obstructed, .motion, .settling, .analysing:
                abandon(&out)
                enterRest(countersRest, at: nil)
            case .needsCalibration, .idle, .arming, .calibrationLost, .paused:
                break
            }
        case .automatic:
            // Row DM8: the board was not watched; re-arm and compare, like row P2.
            switch phase {
            case .rest(let rest):
                startArming(.resume(returnTo: rest), &out)
            case .settling, .analysing:
                let scanWasPending = scanIsPending
                var back = origin
                if phase == .analysing, case .resume(let rest) = analysis { back = rest }
                abandon(&out)
                startArming(.resume(returnTo: back), &out)
                if scanWasPending { out.closing = .scanCompleted([]) }
            case .needsCalibration, .idle, .arming, .motion, .obstructed, .calibrationLost, .paused:
                break
            }
        }
    }

    // MARK: Pause (rows P1 to P2c, DM7)

    private mutating func pause(_ reason: PauseReason, _ out: inout Output) {
        if case .paused(let current) = phase {
            // Row P1b: an end-of-game pause wins over a system pause; nothing else changes.
            if reason == .user, current != .user { phase = .paused(.user) }
            return
        }
        // Row P1.
        pausedFrom = interruptionAnchor
        let scanWasPending = scanIsPending
        abandon(&out)
        phase = .paused(reason)
        if scanWasPending { out.closing = .scanCompleted([]) }
    }

    private mutating func resume(_ out: inout Output) {
        // Row P2c: only `arm` leaves an end-of-game pause.
        guard case .paused(let reason) = phase, reason != .user else { return }
        switch pausedFrom {
        case .needsCalibration:
            phase = .needsCalibration
        case .idle(let needsEmptyBoard):
            // Row P2b.
            phase = .idle
            idleNeedsEmptyBoard = needsEmptyBoard
            if needsEmptyBoard { out.events.append(.needsEmptyBoard) }
        case .calibrationLost:
            phase = .calibrationLost
            relockQuietSince = nil
        case .arming(let purpose):
            // Row P2b: the arming starts again from zero, then ends as the row that opened it says.
            startArming(purpose, &out)
        case .rest(let rest):
            // Rows P2 and DM7.
            startArming(.resume(returnTo: rest), &out)
        }
    }
}
