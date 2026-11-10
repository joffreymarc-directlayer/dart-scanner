import Foundation
import Testing
import DartCore
import DartVision

/// Pause rows of the reducer (VISION.md §6.3, P1 to P3) and the rule of `arm` in `paused`: tests S16, S17, S18.
@Suite struct ReducerPauseTests {
    private typealias H = ReducerHarness

    private static let systemReasons: [PauseReason] = [.background, .thermal]

    private func board(darts count: Int, expected: Int = 3) -> H {
        var h = H()
        h.start()
        h.command(.beginVisit(expectedDarts: expected))
        for number in 0..<count { h.throwDart(H.observation(number + 1)) }
        return h
    }

    /// `calibrationLost`, reached from `watching(0)` by two lost poses.
    private func lostBoard() -> H {
        var h = board(darts: 0)
        for _ in 0..<2 {
            h.moving(3)
            h.quiet(2, change: H.dartChange)
            h.health(.lost)
            if h.state == .settling {
                h.quiet(4, change: H.dartChange)
                h.settle(.noChange)
            }
        }
        return h
    }

    /// `idle` after `needsEmptyBoard`: a resume on a changed scene.
    private func idleNeedingAnEmptyBoard() -> H {
        var h = board(darts: 1)
        h.command(.pause(.background))
        h.command(.resume)
        h.quiet(12)
        h.settle(.unrecognized)
        return h
    }

    /// Rows P1 and P2 as in S16 (a), starting in `watching(1)` and paused with `reason`.
    private func expectPauseAndResume(_ h: inout H, reason: PauseReason, pauseEffects: [ScanEffect]? = nil) {
        if let pauseEffects {
            #expect(pauseEffects == [.emit(.stateChanged(.paused(reason)))])
        }
        #expect(h.state == .paused(reason))
        // Paused: frames are ignored.
        #expect(h.moving(5).flatMap { $0 }.isEmpty && h.quiet(20).flatMap { $0 }.isEmpty)
        #expect(h.command(.resume) == [.emit(.stateChanged(.arming))])
        let arming = h.quiet(12)
        for (index, step) in arming.enumerated() where index != 7 && index != 11 { #expect(step.isEmpty) }
        #expect(arming[7] == [.beginAccumulation])
        // Twelve quiet frames, then the settled image is analysed against the rolling reference.
        #expect(arming[11] == [.emit(.stateChanged(.analysing)), .analyse(maxNewDarts: 1)])
        // "No change": back to the state before the pause, `R := S` and the gate reference.
        #expect(h.settle(.noChange) == [.emit(.stateChanged(.watching(dartsOnBoard: 1))), .updateReference(.rolling),
                                        .setGateReference])
        #expect(h.machine.dartsOnBoard == 1 && h.machine.dartsInVisit == 1 && h.machine.visit == 1)
    }

    // MARK: S16

    @Test(arguments: systemReasons)
    func s16a_pauseThenResume_fromWatching_armingAnalysisAndReturn(reason: PauseReason) {
        var h = board(darts: 1)
        let paused = h.command(.pause(reason))
        expectPauseAndResume(&h, reason: reason, pauseEffects: paused)
    }

    @Test(arguments: systemReasons)
    func s16b_pauseThenResume_outsideStillStates_returnsToTheSameState(reason: PauseReason) {
        // needsCalibration.
        var h = H()
        #expect(h.command(.pause(reason)) == [.emit(.stateChanged(.paused(reason)))])
        #expect(h.command(.resume) == [.emit(.stateChanged(.needsCalibration))])

        // idle after `setCalibration`.
        h.send(.calibrationSet)
        #expect(h.command(.pause(reason)) == [.emit(.stateChanged(.paused(reason)))])
        #expect(h.command(.resume) == [.emit(.stateChanged(.idle))])
        // No arming: frames are still ignored.
        #expect(h.quiet(20).flatMap { $0 }.isEmpty && h.state == .idle)

        // idle after `needsEmptyBoard`: the request is emitted again, here and only here.
        var needing = idleNeedingAnEmptyBoard()
        #expect(needing.state == .idle)
        #expect(needing.command(.pause(reason)) == [.emit(.stateChanged(.paused(reason)))])
        #expect(needing.command(.resume) == [.emit(.stateChanged(.idle)), .emit(.needsEmptyBoard)])
        #expect(needing.quiet(20).flatMap { $0 }.isEmpty && needing.state == .idle)

        // calibrationLost.
        var lost = lostBoard()
        #expect(lost.state == .calibrationLost)
        #expect(lost.command(.pause(reason)) == [.emit(.stateChanged(.paused(reason)))])
        #expect(lost.command(.resume) == [.emit(.stateChanged(.calibrationLost))])
        // Still lost: the gate runs again for row K3, and a recovery works as before the pause.
        #expect(lost.quiet(40).flatMap { $0 } == [.checkCalibration])
        #expect(lost.health(.healthy) == [.emit(.stateChanged(.arming))])
    }

    @Test(arguments: systemReasons)
    func s16c_pauseDuringAnArming_theArmingStartsAgainFromZero(reason: PauseReason) {
        var h = H()
        h.send(.calibrationSet)
        h.command(.arm(boardConfirmedEmpty: true))
        h.quiet(5)
        #expect(h.command(.pause(reason)) == [.emit(.stateChanged(.paused(reason)))])
        #expect(h.command(.resume) == [.emit(.stateChanged(.arming))])
        // The five frames before the pause no longer count.
        let arming = h.quiet(12)
        #expect(arming[6].isEmpty && H.events(arming.prefix(11).flatMap { $0 }).isEmpty && arming[7] == [.beginAccumulation])
        // The row that opened the arming (row 3) ends as planned.
        #expect(arming[11] == [.emit(.stateChanged(.watching(dartsOnBoard: 0))), .updateReference(.rollingAndEmpty),
                               .setGateReference, .checkCalibration])
    }

    @Test(arguments: systemReasons)
    func s16c_pauseLateInAnArming_dropsItsAccumulation(reason: PauseReason) {
        var h = H()
        h.send(.calibrationSet)
        h.command(.arm(boardConfirmedEmpty: false))
        h.quiet(10)
        #expect(h.command(.pause(reason)) == [.discardAccumulation, .emit(.stateChanged(.paused(reason)))])
        h.command(.resume)
        #expect(H.references(h.quiet(12)[11]) == [.updateReference(.rolling)])
    }

    @Test(arguments: systemReasons)
    func s16d_secondPause_hasNoEffectAndNoEvent(reason: PauseReason) {
        var h = board(darts: 1)
        h.command(.pause(reason))
        #expect(h.command(.pause(reason)).isEmpty && h.state == .paused(reason))
        // Another system reason does not replace the first one either.
        let other: PauseReason = reason == .background ? .thermal : .background
        #expect(h.command(.pause(other)).isEmpty && h.state == .paused(reason))
        expectPauseAndResume(&h, reason: reason)
    }

    @Test func s16e_userPauseThenSystemPause_resumeIsIgnored_armLeaves() {
        var h = board(darts: 1)
        #expect(h.command(.pause(.user)) == [.emit(.stateChanged(.paused(.user)))])
        #expect(h.command(.pause(.background)).isEmpty && h.state == .paused(.user))
        #expect(h.command(.pause(.thermal)).isEmpty && h.command(.pause(.user)).isEmpty && h.state == .paused(.user))
        #expect(h.command(.resume).isEmpty && h.state == .paused(.user))
        #expect(h.quiet(40).flatMap { $0 }.isEmpty && h.state == .paused(.user))
        #expect(h.command(.arm(boardConfirmedEmpty: true)) == [.emit(.stateChanged(.arming))])
    }

    @Test(arguments: systemReasons)
    func s16f_systemPauseThenUserPause_theReasonChanges_resumeIsIgnored(reason: PauseReason) {
        var h = board(darts: 1)
        h.command(.pause(reason))
        // The only case where a second pause says anything.
        #expect(h.command(.pause(.user)) == [.emit(.stateChanged(.paused(.user)))])
        #expect(h.command(.resume).isEmpty && h.state == .paused(.user))
        #expect(h.command(.pause(reason)).isEmpty && h.command(.resume).isEmpty && h.state == .paused(.user))
        // The state kept is still the one of the first pause: `arm` then starts a game as usual.
        #expect(h.command(.arm(boardConfirmedEmpty: true)) == [.emit(.stateChanged(.arming))])
    }

    @Test func s16g_userPause_fromNeedsCalibrationAndFromIdle_resumeIsIgnored() {
        var h = H()
        #expect(h.command(.pause(.user)) == [.emit(.stateChanged(.paused(.user)))])
        #expect(h.command(.resume).isEmpty && h.state == .paused(.user))
        // From idle.
        h.send(.calibrationSet)
        #expect(h.state == .idle)
        #expect(h.command(.pause(.user)) == [.emit(.stateChanged(.paused(.user)))])
        #expect(h.command(.resume).isEmpty && h.state == .paused(.user))
    }

    // MARK: S17

    /// `arm` followed by twelve quiet samples, as in S1.
    private func expectArmLikeS1(_ h: inout H, trigger: ScanTrigger = .automatic) {
        #expect(h.command(.arm(boardConfirmedEmpty: true)) == [.emit(.stateChanged(.arming))])
        #expect(h.machine.visit == 0 && h.machine.dartsInVisit == 0 && h.machine.dartsOnBoard == 0)
        let arming = h.quiet(12)
        #expect(arming[7] == [.beginAccumulation])
        #expect(arming[11] == [.emit(.stateChanged(.watching(dartsOnBoard: 0))), .updateReference(.rollingAndEmpty),
                               .setGateReference, .checkCalibration])
        #expect(H.analyses(arming.flatMap { $0 }).isEmpty)
        #expect(h.machine.visit == 0 && h.machine.dartsInVisit == 0 && h.machine.dartsOnBoard == 0)
        #expect(h.machine.trigger == trigger)
    }

    @Test func s17_arm_fromUserPause_fromSystemPause_fromAwaitingTakeout_thenWithoutCalibration() {
        // paused(.user), pause taken in watching(1).
        var user = board(darts: 1)
        user.command(.pause(.user))
        expectArmLikeS1(&user)

        // paused(.background), pause taken in watching(1).
        var background = board(darts: 1)
        background.command(.pause(.background))
        expectArmLikeS1(&background)

        // awaitingTakeout with three known darts and visit = 2: the darts of the win are still on the board.
        var won = board(darts: 0)
        won.command(.beginVisit(expectedDarts: 3))
        for number in 1...3 { won.throwDart(H.observation(number)) }
        #expect(won.state == .awaitingTakeout && won.machine.visit == 2 && won.machine.dartsOnBoard == 3)
        expectArmLikeS1(&won)

        // The trigger survives `arm`.
        var manual = board(darts: 1)
        manual.command(.setTrigger(.manual))
        manual.command(.pause(.user))
        expectArmLikeS1(&manual, trigger: .manual)

        // Last case: paused(.user), pause taken in needsCalibration. `arm` never arms without a calibration.
        var bare = H()
        bare.command(.pause(.user))
        #expect(bare.command(.arm(boardConfirmedEmpty: true)) == [.emit(.stateChanged(.needsCalibration))])
        #expect(bare.state == .needsCalibration)
        #expect(bare.quiet(20).flatMap { $0 }.isEmpty && bare.state == .needsCalibration)
    }

    @Test func arm_fromAPauseTakenInCalibrationLost_returnsThere_thenKeepsBoardConfirmedEmpty() {
        var h = lostBoard()
        h.command(.beginVisit(expectedDarts: 3))
        h.command(.pause(.user))
        // Back to `calibrationLost` like row P2b, then the effect of `arm` there: counters cleared, no arming.
        #expect(h.command(.arm(boardConfirmedEmpty: true)) == [.emit(.stateChanged(.calibrationLost))])
        #expect(h.state == .calibrationLost && h.machine.visit == 0)
        h.health(.lost, recovered: true)
        #expect(H.references(h.quiet(12)[11]) == [.updateReference(.rollingAndEmpty)])
        #expect(h.state == .watching(dartsOnBoard: 0))
    }

    // MARK: S18

    @Test func s18_resumeOnAChangedScene_needsEmptyBoard_thenConfirmBoardEmpty() {
        var h = board(darts: 1)
        h.command(.beginVisit(expectedDarts: 3))
        h.throwDart(H.observation(2))
        #expect(h.state == .watching(dartsOnBoard: 2) && h.machine.visit == 2 && h.machine.dartsInVisit == 1)
        h.command(.pause(.background))
        h.command(.resume)
        h.quiet(12)
        #expect(h.state == .analysing)
        // `stateChanged(.idle)` first, then `needsEmptyBoard`: no dart event, no reference update.
        #expect(h.settle(.unrecognized) == [.emit(.stateChanged(.idle)), .emit(.needsEmptyBoard)])
        #expect(h.state == .idle)
        // Frames are ignored until the player confirms.
        #expect(h.moving(10).flatMap { $0 }.isEmpty && h.quiet(40).flatMap { $0 }.isEmpty)
        // P3.
        #expect(h.command(.confirmBoardEmpty) == [.emit(.stateChanged(.arming))])
        let arming = h.quiet(12)
        #expect(arming[7] == [.beginAccumulation])
        #expect(arming[11] == [.emit(.stateChanged(.watching(dartsOnBoard: 0))), .updateReference(.rollingAndEmpty),
                               .setGateReference, .checkCalibration])
        // The visit counters are kept: the game layer has no `beginVisit` to send again.
        #expect(h.machine.visit == 2 && h.machine.dartsInVisit == 1 && h.machine.dartsOnBoard == 0)
    }

    @Test func p2_everyOutcomeButNoChange_goesToIdleWithoutAnyDartEvent() {
        let dart = H.observation(7, tier: .low)
        let outcomes: [SettleOutcome] = [.darts(new: [dart], removed: [], disturbed: []),
                                         .removed([H.id(1)], boardEmpty: true), .obstruction, .lightingChanged,
                                         .foreignRemoval, .unrecognized]
        for outcome in outcomes {
            var h = board(darts: 1)
            h.command(.pause(.thermal))
            h.command(.resume)
            h.quiet(12)
            #expect(h.settle(outcome) == [.emit(.stateChanged(.idle)), .emit(.needsEmptyBoard)], "\(outcome)")
            #expect(h.machine.dartsInVisit == 1)
        }
    }

    @Test func p3_confirmBoardEmpty_fromIdleAfterANewCalibration_keepsTheVisitCounters() {
        var h = board(darts: 2)
        h.send(.calibrationSet)
        #expect(h.command(.confirmBoardEmpty) == [.emit(.stateChanged(.arming))])
        #expect(H.references(h.quiet(12)[11]) == [.updateReference(.rollingAndEmpty)])
        #expect(h.state == .watching(dartsOnBoard: 0) && h.machine.visit == 1 && h.machine.dartsInVisit == 2)
    }

    // MARK: P1 and P2 from other states

    @Test func p1_pauseDuringAnEpisode_abandonsIt_andResumeComesBackToTheStillStateItLeft() {
        for stage in 0..<3 {
            var h = board(darts: 3)
            h.moving(3)
            if stage >= 1 { h.quiet(3, change: H.dartChange) }
            if stage == 2 { h.quiet(3, change: H.dartChange) }
            #expect(h.state == [.motion, .settling, .analysing][stage])
            #expect(h.command(.pause(.background)) == [.discardAccumulation, .emit(.stateChanged(.paused(.background)))])
            // The outcome of an abandoned analysis is ignored.
            #expect(h.settle(.darts(new: [H.observation(8)], removed: [], disturbed: [])).isEmpty)
            h.command(.resume)
            h.quiet(12)
            #expect(H.events(h.settle(.noChange)) == [.stateChanged(.awaitingTakeout)])
            #expect(h.machine.dartsOnBoard == 3 && h.machine.dartsInVisit == 3)
        }
    }

    @Test func p1_pauseFromTakeoutAndFromObstructed() {
        var h = board(darts: 2)
        h.handEpisode()
        h.settle(.removed([H.id(1)], boardEmpty: false))
        #expect(h.state == .takeout)
        h.command(.pause(.background))
        h.command(.resume)
        h.quiet(12)
        #expect(H.events(h.settle(.noChange)) == [.stateChanged(.takeout)])
        // From `obstructed`: what comes back is the still state before the obstruction.
        h.handEpisode()
        h.settle(.obstruction)
        h.command(.pause(.thermal))
        h.command(.resume)
        h.quiet(12)
        #expect(H.events(h.settle(.noChange)) == [.stateChanged(.takeout)])
    }

    @Test func p2b_pauseDuringTheArmingOfAResume_orDuringItsAnalysis_startsItAgain() {
        var h = board(darts: 1)
        h.command(.pause(.background))
        h.command(.resume)
        h.quiet(9)
        // Paused again during the arming of row P2.
        #expect(h.command(.pause(.background)) == [.discardAccumulation, .emit(.stateChanged(.paused(.background)))])
        #expect(h.command(.resume) == [.emit(.stateChanged(.arming))])
        #expect(h.quiet(11).last == [] && h.state == .arming)
        #expect(h.quiet(1)[0] == [.emit(.stateChanged(.analysing)), .analyse(maxNewDarts: 1)])
        // Paused during the analysis itself.
        #expect(h.command(.pause(.thermal)) == [.discardAccumulation, .emit(.stateChanged(.paused(.thermal)))])
        h.command(.resume)
        #expect(h.quiet(12)[11] == [.emit(.stateChanged(.analysing)), .analyse(maxNewDarts: 1)])
        #expect(H.events(h.settle(.noChange)) == [.stateChanged(.watching(dartsOnBoard: 1))])
    }

    @Test func p2b_pauseDuringTheArmingOfP3_endsInWatchingZero() {
        var h = idleNeedingAnEmptyBoard()
        h.command(.confirmBoardEmpty)
        h.quiet(4)
        h.command(.pause(.background))
        h.command(.resume)
        #expect(H.references(h.quiet(12)[11]) == [.updateReference(.rollingAndEmpty)])
        #expect(h.state == .watching(dartsOnBoard: 0))
    }

    @Test func pause_countersCommandsDuringThePause_areHonouredAtTheReturn() {
        var h = board(darts: 3)
        #expect(h.state == .awaitingTakeout)
        h.command(.pause(.background))
        // The next visit begins while the application is in the background.
        h.command(.beginVisit(expectedDarts: 3))
        h.command(.resume)
        h.quiet(12)
        #expect(H.events(h.settle(.noChange)) == [.stateChanged(.watching(dartsOnBoard: 3))])
    }
}
