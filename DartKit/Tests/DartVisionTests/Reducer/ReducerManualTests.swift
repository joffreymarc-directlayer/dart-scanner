import Foundation
import Testing
import DartCore
import DartVision

/// Manual trigger, "Scanner la volée" (VISION.md §6.3, rows DM1 to DM8 and DM3a to DM3d): tests S20 to S23.
@Suite struct ReducerManualTests {
    private typealias H = ReducerHarness

    private func scanned(_ number: Int, flags: DartFlags = [.multiDartStill]) -> DartObservation {
        H.observation(number, flags: flags, source: .scan)
    }

    /// Manual trigger at rest in visit 1, with darts 1...count scanned in one capture.
    private func manualBoard(darts count: Int, boardConfirmedEmpty: Bool = true) -> H {
        var h = H()
        h.start(boardConfirmedEmpty: boardConfirmedEmpty, trigger: .manual)
        h.command(.beginVisit(expectedDarts: 3))
        if count > 0 {
            h.command(.captureNow(maxDarts: 3))
            h.quiet(6)
            h.settle(.darts(new: (1...count).map { scanned($0) }, removed: [], disturbed: []))
        }
        return h
    }

    private func scanResults(_ effects: [ScanEffect]) -> [[DartObservation]] {
        H.events(effects).compactMap { event in
            if case .scanCompleted(let observations) = event { return observations }
            return nil
        }
    }

    // MARK: S20: DM1 and DM8

    @Test func s20_setTriggerManual_fromWatching_thenFramesAreIgnored() {
        var h = H()
        h.start()
        h.command(.beginVisit(expectedDarts: 3))
        h.throwDart(H.observation(1))
        // DM1 from a still state: no effect at all.
        #expect(h.command(.setTrigger(.manual)).isEmpty)
        #expect(h.state == .watching(dartsOnBoard: 1) && h.machine.trigger == .manual)
        // Nothing is processed at rest: no episode, no idle check, no refresh.
        var effects: [ScanEffect] = []
        effects += h.moving(60).flatMap { $0 }
        effects += h.quiet(90, change: 0.01).flatMap { $0 }
        #expect(effects.isEmpty && h.state == .watching(dartsOnBoard: 1) && h.machine.trigger == .manual)
        #expect(h.machine.dartsOnBoard == 1 && h.machine.dartsInVisit == 1)
        // Already manual: no effect.
        #expect(h.command(.setTrigger(.manual)).isEmpty)
    }

    @Test func s20_setTriggerManual_duringSettling_discardsAndRests() {
        var h = H()
        h.start()
        h.command(.beginVisit(expectedDarts: 3))
        h.throwDart(H.observation(1))
        h.moving(3)
        h.quiet(3, change: H.dartChange)
        #expect(h.state == .settling)
        #expect(h.command(.setTrigger(.manual)) == [.discardAccumulation, .emit(.stateChanged(.watching(dartsOnBoard: 1)))])
        // The episode is gone: its frames do nothing more.
        #expect(h.quiet(10, change: H.dartChange).flatMap { $0 }.isEmpty && h.state == .watching(dartsOnBoard: 1))
    }

    @Test func s20_setTriggerAutomatic_atRest_armsThenContinuesLikeS16() {
        var h = manualBoard(darts: 1)
        #expect(h.state == .watching(dartsOnBoard: 1))
        // DM8.
        #expect(h.command(.setTrigger(.automatic)) == [.emit(.stateChanged(.arming))])
        #expect(h.machine.trigger == .automatic)
        let arming = h.quiet(12)
        #expect(arming[7] == [.beginAccumulation])
        #expect(arming[11] == [.emit(.stateChanged(.analysing)), .analyse(maxNewDarts: 1)])
        // Unchanged scene: back to the rest it left, as in S16 (a).
        #expect(h.settle(.noChange) == [.emit(.stateChanged(.watching(dartsOnBoard: 1))), .updateReference(.rolling),
                                        .setGateReference])
        // Already automatic: no effect.
        #expect(h.command(.setTrigger(.automatic)).isEmpty)

        // Changed scene: `idle`, then `needsEmptyBoard`, as in S18.
        var changed = manualBoard(darts: 2)
        changed.command(.setTrigger(.automatic))
        changed.quiet(12)
        #expect(changed.settle(.removed([H.id(1)], boardEmpty: false)) == [.emit(.stateChanged(.idle)), .emit(.needsEmptyBoard)])
        #expect(changed.machine.dartsOnBoard == 2)
    }

    @Test func dm1_fromTakeoutObstructedMotionAndAnalysing_restsByTheCounters() {
        // takeout: the rest of the manual trigger is `watching(n)` or `awaitingTakeout`.
        var h = H()
        h.start()
        h.command(.beginVisit(expectedDarts: 3))
        for number in 1...3 { h.throwDart(H.observation(number)) }
        h.handEpisode()
        h.settle(.removed([H.id(1)], boardEmpty: false))
        #expect(h.state == .takeout)
        #expect(h.command(.setTrigger(.manual)) == [.emit(.stateChanged(.awaitingTakeout))])

        // obstructed.
        var obstructed = H()
        obstructed.start()
        obstructed.handEpisode()
        obstructed.settle(.obstruction)
        #expect(obstructed.command(.setTrigger(.manual)) == [.emit(.stateChanged(.watching(dartsOnBoard: 0)))])

        // motion and analysing.
        var moving = H()
        moving.start()
        moving.moving(2)
        #expect(moving.command(.setTrigger(.manual)) == [.discardAccumulation, .emit(.stateChanged(.watching(dartsOnBoard: 0)))])
        var analysing = H()
        analysing.start()
        analysing.episode()
        #expect(analysing.command(.setTrigger(.manual)) == [.discardAccumulation, .emit(.stateChanged(.watching(dartsOnBoard: 0)))])
        #expect(analysing.settle(.darts(new: [H.observation(1)], removed: [], disturbed: [])).isEmpty)
    }

    @Test func dm1_dm8_inOtherStates_changeTheTriggerOnly() {
        var h = H()
        #expect(h.command(.setTrigger(.manual)).isEmpty && h.machine.trigger == .manual && h.state == .needsCalibration)
        h.send(.calibrationSet)
        #expect(h.command(.setTrigger(.automatic)).isEmpty && h.machine.trigger == .automatic && h.state == .idle)
        h.command(.arm(boardConfirmedEmpty: true))
        #expect(h.command(.setTrigger(.manual)).isEmpty && h.state == .arming)
        // The trigger survives `arm`, `pause`, `resume` and a new calibration.
        h.quiet(12)
        h.command(.pause(.background))
        #expect(h.command(.setTrigger(.automatic)).isEmpty && h.state == .paused(.background))
        h.command(.setTrigger(.manual))
        h.command(.resume)
        h.send(.calibrationSet)
        h.command(.arm(boardConfirmedEmpty: true))
        #expect(h.machine.trigger == .manual)
    }

    // MARK: S21: DM2 and DM5

    @Test func s21_captureReference_thenRebaseline_atManualRestWithTwoKnownDarts() {
        var h = manualBoard(darts: 2)
        #expect(h.state == .watching(dartsOnBoard: 2))
        // DM2.
        #expect(h.command(.captureReference) == [.emit(.stateChanged(.settling))])
        var pose = h.quiet(6)
        #expect(pose[0].isEmpty)
        #expect(pose[1] == [.beginAccumulation, .checkCalibration])
        #expect(pose[2].isEmpty && pose[3].isEmpty && pose[4].isEmpty)
        #expect(pose[5] == [.emit(.stateChanged(.watching(dartsOnBoard: 0))), .updateReference(.rollingAndEmpty),
                            .setGateReference])
        #expect(H.analyses(pose.flatMap { $0 }).isEmpty && scanResults(pose.flatMap { $0 }).isEmpty)
        #expect(h.machine.dartsOnBoard == 0 && h.machine.dartsInVisit == 2)

        // DM5, from a rest with two known darts again.
        h = manualBoard(darts: 2)
        #expect(h.command(.rebaseline) == [.emit(.stateChanged(.settling))])
        pose = h.quiet(6)
        #expect(pose[1] == [.beginAccumulation, .checkCalibration])
        #expect(pose[5] == [.emit(.stateChanged(.watching(dartsOnBoard: 2))), .updateReference(.rolling), .setGateReference])
        #expect(H.analyses(pose.flatMap { $0 }).isEmpty && h.machine.dartsOnBoard == 2)

        // `captureReference` in automatic trigger: ignored, no effect.
        var automatic = H()
        automatic.start()
        #expect(automatic.command(.captureReference).isEmpty && automatic.state == .watching(dartsOnBoard: 0))
    }

    @Test func dm2_confirmBoardEmpty_atManualRest_isACaptureOfTheReference() {
        var h = manualBoard(darts: 3)
        #expect(h.state == .awaitingTakeout)
        #expect(h.command(.confirmBoardEmpty) == [.emit(.stateChanged(.settling))])
        let pose = h.quiet(6)
        #expect(H.references(pose[5]) == [.updateReference(.rollingAndEmpty)] && h.machine.dartsOnBoard == 0)
        // The visit is still full: the rest of this mode is `awaitingTakeout`.
        #expect(h.state == .awaitingTakeout)
    }

    // MARK: S22: DM3, DM6 and the outcomes of a scan

    @Test func s22_captureNow_threeDarts_oneScanCompletedLast() {
        var h = manualBoard(darts: 0)
        #expect(h.command(.captureNow(maxDarts: 3)) == [.emit(.stateChanged(.settling))])
        let pose = h.quiet(6)
        #expect(pose[1] == [.beginAccumulation, .checkCalibration])
        #expect(pose[5] == [.emit(.stateChanged(.analysing)), .analyse(maxNewDarts: 3)])
        #expect(H.analyses(pose.prefix(5).flatMap { $0 }).isEmpty)
        let darts = [scanned(1), scanned(2), scanned(3)]
        let effects = h.settle(.darts(new: darts, removed: [], disturbed: []))
        // DM3a: one `scanCompleted`, with the three observations, emitted last.
        #expect(effects == [.emit(.stateChanged(.awaitingTakeout)), .updateReference(.rolling), .setGateReference,
                            .emit(.scanCompleted(darts))])
        #expect(h.state == .awaitingTakeout && h.machine.dartsOnBoard == 3 && h.machine.dartsInVisit == 3)
        // No `dart` event in this mode: the review screen gets the list.
        #expect(!H.events(effects).contains { if case .dart = $0 { return true } else { return false } })
    }

    @Test func s22_aMovingFrameAfterThreeQuietOnes_restartsTheCount_stateSettling() {
        var h = manualBoard(darts: 0)
        h.command(.captureNow(maxDarts: 3))
        h.quiet(3)
        #expect(h.moving(1)[0] == [.discardAccumulation] && h.state == .settling)
        // The count starts again from zero: second quiet frame begins, sixth completes.
        let pose = h.quiet(6)
        #expect(pose[0].isEmpty && pose[1] == [.beginAccumulation, .checkCalibration])
        #expect(pose[4].isEmpty && pose[5] == [.emit(.stateChanged(.analysing)), .analyse(maxNewDarts: 3)])
        // A moving frame before any accumulation has nothing to discard.
        h.settle(.noChange)
        h.command(.captureNow(maxDarts: 3))
        h.quiet(1)
        #expect(h.moving(1)[0].isEmpty && h.state == .settling)
    }

    @Test func s22_continuousMotionForTwoSeconds_advisoryThenEmptyScan_noAnalysis() {
        var h = manualBoard(darts: 1)
        h.command(.captureNow(maxDarts: 2))
        var log: [ScanEffect] = []
        var frames = 0
        while h.state == .settling, frames < 100 {
            log += h.moving(1)[0]
            frames += 1
        }
        // DM6: 2 s after the first sample (the 61st frame).
        #expect(frames == 61)
        #expect(log == [.discardAccumulation, .emit(.stateChanged(.watching(dartsOnBoard: 1))),
                        .emit(.advisory(.viewObstructed)), .emit(.scanCompleted([]))])
        #expect(H.analyses(log).isEmpty && H.references(log).isEmpty && h.machine.dartsOnBoard == 1)
    }

    @Test func dm6_captureThatNeverSettles_forAReference_hasNoScanCompleted() {
        var h = manualBoard(darts: 1)
        h.command(.captureReference)
        var log: [ScanEffect] = []
        // Five quiet frames, one restless frame, again and again: never six in a row.
        for _ in 0..<12 where h.state == .settling {
            log += h.quiet(5).flatMap { $0 }
            if h.state == .settling { log += h.sample(motion: 0.0008) }
        }
        #expect(h.state == .watching(dartsOnBoard: 1))
        #expect(H.events(log) == [.stateChanged(.watching(dartsOnBoard: 1)), .advisory(.viewObstructed)])
        #expect(H.references(log).isEmpty && scanResults(log).isEmpty && log.last != .beginAccumulation)
        #expect(Array(log.suffix(3)) == [.discardAccumulation, .emit(.stateChanged(.watching(dartsOnBoard: 1))),
                                         .emit(.advisory(.viewObstructed))])
    }

    @Test func dm6_theSixthQuietFrameWinsOverTheTimeout() {
        var parameters = ScanParameters()
        parameters.trigger = .manual
        parameters.captureTimeout = 5.0 / 30
        var h = H(parameters: parameters)
        h.start(trigger: .manual)
        h.command(.captureNow(maxDarts: 1))
        // The sixth quiet frame arrives exactly when the timeout expires: the capture succeeds.
        #expect(h.quiet(6)[5] == [.emit(.stateChanged(.analysing)), .analyse(maxNewDarts: 1)])
    }

    @Test func s22_lightingChange_thenEmptyScan_noReferenceUpdate() {
        var h = manualBoard(darts: 1)
        h.command(.captureNow(maxDarts: 2))
        h.quiet(6)
        // DM3d.
        #expect(h.settle(.lightingChanged) == [.emit(.stateChanged(.watching(dartsOnBoard: 1))), .emit(.lightingChanged),
                                               .emit(.scanCompleted([]))])
    }

    @Test func s22_pauseDuringTheCapture_pausedDiscardAndEmptyScan() {
        var h = manualBoard(darts: 1)
        h.command(.captureNow(maxDarts: 2))
        h.quiet(3)
        #expect(h.command(.pause(.background)) == [.discardAccumulation, .emit(.stateChanged(.paused(.background))),
                                                   .emit(.scanCompleted([]))])
        // Nothing is owed any more.
        #expect(h.command(.resume) == [.emit(.stateChanged(.arming))])
        #expect(scanResults(h.quiet(12).flatMap { $0 }).isEmpty)
    }

    @Test func s22_captureNowWithoutAnyDartToFind_isIgnored() {
        var h = manualBoard(darts: 1)
        for maxDarts in [0, -1, Int.min] {
            #expect(h.command(.captureNow(maxDarts: maxDarts)).isEmpty && h.state == .watching(dartsOnBoard: 1))
        }
        #expect(h.quiet(10).flatMap { $0 }.isEmpty)
    }

    @Test func dm3b_dm3c_dm3d_everyScanEndsWithExactlyOneScanCompleted() {
        // DM3b: nothing new.
        var h = manualBoard(darts: 2)
        h.command(.captureNow(maxDarts: 1))
        h.quiet(6)
        #expect(h.settle(.noChange) == [.emit(.stateChanged(.watching(dartsOnBoard: 2))), .emit(.scanCompleted([]))])
        // DM3c: known darts pulled, nothing new. `E` is untouched even on an empty board.
        h.command(.captureNow(maxDarts: 1))
        h.quiet(6)
        #expect(h.settle(.removed([H.id(1), H.id(2)], boardEmpty: true))
                == [.emit(.stateChanged(.watching(dartsOnBoard: 0))), .emit(.dartRemoved(id: H.id(1), reason: .takeout)),
                    .emit(.dartRemoved(id: H.id(2), reason: .takeout)), .updateReference(.rolling), .setGateReference,
                    .emit(.scanCompleted([]))])
        // DM3d, the three other cases: no reference is modified.
        let cases: [(SettleOutcome, [ScanEvent])] = [(.obstruction, [.advisory(.viewObstructed)]), (.foreignRemoval, []),
                                                     (.unrecognized, [.unrecognizedChange])]
        for (outcome, expected) in cases {
            var d = manualBoard(darts: 2)
            d.command(.captureNow(maxDarts: 1))
            d.quiet(6)
            let effects = d.settle(outcome)
            #expect(H.facts(effects) == expected + [.scanCompleted([])], "\(outcome)")
            #expect(H.work(effects).isEmpty && d.state == .watching(dartsOnBoard: 2), "\(outcome)")
        }
    }

    @Test func dm3a_secondScan_removedAndDisturbedDarts_andADartBeyondTheVisit() {
        var h = manualBoard(darts: 2)
        h.command(.captureNow(maxDarts: 1))
        h.quiet(6)
        // One known dart was pulled, one moved, and two new ones are found although one was asked for.
        let third = scanned(3, flags: [])
        let fourth = scanned(4, flags: [])
        let effects = h.settle(.darts(new: [third, fourth], removed: [H.id(1)], disturbed: [H.id(2)]))
        #expect(effects == [.emit(.stateChanged(.awaitingTakeout)), .emit(.dartRemoved(id: H.id(1), reason: .takeout)),
                            .emit(.dartDisturbed(id: H.id(2))), .updateReference(.rolling), .setGateReference,
                            .emit(.scanCompleted([third, H.observation(fourth, flags: .beyondVisitLimit)]))])
        #expect(h.machine.dartsOnBoard == 3 && h.machine.dartsInVisit == 4)
    }

    @Test func dm3_noEpisodeEventInThisMode() {
        var h = manualBoard(darts: 3)
        // Darts pulled by hand, with a lot of motion: the machine sees nothing between two commands.
        var effects: [ScanEffect] = []
        effects += h.moving(90).flatMap { $0 }
        effects += h.quiet(400, change: 0.02).flatMap { $0 }
        #expect(effects.isEmpty && h.state == .awaitingTakeout)
    }

    @Test func captureInterrupted_emitsTheEmptyScanAtThatMoment_once() {
        // By `arm`.
        var h = manualBoard(darts: 1)
        h.command(.captureNow(maxDarts: 2))
        h.quiet(3)
        #expect(h.command(.arm(boardConfirmedEmpty: true)) == [.discardAccumulation, .emit(.stateChanged(.arming)),
                                                              .emit(.scanCompleted([]))])
        // By `setTrigger(.automatic)` (DM8), here after the analysis was requested.
        h = manualBoard(darts: 1)
        h.command(.captureNow(maxDarts: 2))
        h.quiet(6)
        #expect(h.state == .analysing)
        #expect(h.command(.setTrigger(.automatic)) == [.discardAccumulation, .emit(.stateChanged(.arming)),
                                                       .emit(.scanCompleted([]))])
        // The late answer of the engine is ignored: no second `scanCompleted`.
        #expect(h.settle(.darts(new: [scanned(5)], removed: [], disturbed: [])).isEmpty)
        // By a new calibration.
        h = manualBoard(darts: 1)
        h.command(.captureNow(maxDarts: 2))
        h.quiet(1)
        #expect(h.send(.calibrationSet) == [.discardAccumulation, .emit(.stateChanged(.idle)), .emit(.scanCompleted([]))])
        // By the loss of the calibration (K2): two lost poses in a row.
        h = manualBoard(darts: 1)
        h.command(.captureNow(maxDarts: 2))
        h.quiet(2)
        h.health(.lost)
        h.quiet(4)
        h.settle(.noChange)
        h.command(.captureNow(maxDarts: 2))
        h.quiet(2)
        #expect(h.health(.lost) == [.discardAccumulation, .emit(.stateChanged(.calibrationLost)), .emit(.calibrationLost),
                                    .emit(.scanCompleted([]))])
        // A reference capture owes no `scanCompleted`.
        h = manualBoard(darts: 1)
        h.command(.captureReference)
        h.quiet(3)
        #expect(h.command(.pause(.thermal)) == [.discardAccumulation, .emit(.stateChanged(.paused(.thermal)))])
    }

    @Test func captureCommands_areAcceptedAtRestOnly() {
        var h = manualBoard(darts: 1)
        // A capture is already running.
        h.command(.captureNow(maxDarts: 2))
        for command: ScanCommand in [.captureNow(maxDarts: 1), .captureReference, .rebaseline, .confirmBoardEmpty] {
            #expect(h.command(command).isEmpty && h.state == .settling, "\(command)")
        }
        // The running capture is still the scan of two darts.
        #expect(h.quiet(6)[5] == [.emit(.stateChanged(.analysing)), .analyse(maxNewDarts: 2)])
        #expect(h.command(.captureNow(maxDarts: 1)).isEmpty && h.command(.captureReference).isEmpty)
        #expect(scanResults(h.settle(.noChange)) == [[]])
        // paused, idle, arming, calibrationLost.
        h.command(.pause(.background))
        #expect(h.command(.captureNow(maxDarts: 1)).isEmpty && h.command(.captureReference).isEmpty)
        h.send(.calibrationSet)
        #expect(h.command(.captureNow(maxDarts: 1)).isEmpty && h.command(.captureReference).isEmpty && h.state == .idle)
        h.command(.arm(boardConfirmedEmpty: true))
        #expect(h.command(.captureNow(maxDarts: 1)).isEmpty && h.command(.captureReference).isEmpty && h.state == .arming)
    }

    // MARK: S23: DM4 and DM7

    @Test func s23_beginVisit_afterAScanOfThreeDarts_startsAgainFromTheEmptyReference() {
        var h = manualBoard(darts: 3)
        #expect(h.state == .awaitingTakeout && h.machine.visit == 1)
        // DM4, `k = expectedDartsPerVisit` and `E` known: `R := E`, silhouettes cleared, no analysis, no `dartRemoved`.
        #expect(h.command(.beginVisit(expectedDarts: 3)) == [.emit(.stateChanged(.watching(dartsOnBoard: 0))),
                                                             .updateReference(.rollingFromEmpty)])
        #expect(h.machine.visit == 2 && h.machine.dartsInVisit == 0 && h.machine.dartsOnBoard == 0)
        // The empty reference is intact: the next whole visit starts from it again.
        #expect(h.command(.beginVisit(expectedDarts: 3)) == [.updateReference(.rollingFromEmpty)])
        #expect(h.machine.visit == 3)
    }

    @Test func s23_beginVisit_withFewerExpectedDarts_keepsReferencesAndSilhouettes() {
        var h = manualBoard(darts: 2)
        #expect(h.command(.beginVisit(expectedDarts: 1)).isEmpty)
        #expect(h.state == .watching(dartsOnBoard: 2) && h.machine.visit == 2 && h.machine.dartsInVisit == 0)
        // The next scan asks for the one dart still expected.
        h.command(.captureNow(maxDarts: 1))
        h.quiet(6)
        let third = scanned(3, flags: [])
        #expect(h.settle(.darts(new: [third], removed: [], disturbed: [])).last == .emit(.scanCompleted([third])))
        #expect(h.state == .awaitingTakeout)
    }

    @Test func dm4_withoutAnEmptyReference_keepsTheKnownDarts() {
        // Armed without a confirmed empty board: `E` is unknown until « Cible vide ».
        var h = manualBoard(darts: 2, boardConfirmedEmpty: false)
        #expect(h.command(.beginVisit(expectedDarts: 3)).isEmpty)
        #expect(h.state == .watching(dartsOnBoard: 2) && h.machine.visit == 2)
        // After « Cible vide » the empty reference is known.
        h.command(.captureReference)
        h.quiet(6)
        h.command(.captureNow(maxDarts: 3))
        h.quiet(6)
        h.settle(.darts(new: [scanned(7)], removed: [], disturbed: []))
        #expect(H.references(h.command(.beginVisit(expectedDarts: 3))) == [.updateReference(.rollingFromEmpty)])
    }

    @Test func s23_pauseThenResume_inManualTrigger_armsAndReturnsWithoutAnalysis() {
        var h = manualBoard(darts: 2)
        #expect(h.command(.pause(.background)) == [.emit(.stateChanged(.paused(.background)))])
        #expect(h.command(.resume) == [.emit(.stateChanged(.arming))])
        let arming = h.quiet(12)
        // DM7: noise and drift are measured again; no comparison with `R`, references kept.
        #expect(arming[11] == [.emit(.stateChanged(.watching(dartsOnBoard: 2))), .checkCalibration])
        #expect(H.analyses(arming.flatMap { $0 }).isEmpty && H.references(arming.flatMap { $0 }).isEmpty)
        #expect(!H.events(arming.flatMap { $0 }).contains(.needsEmptyBoard))
        // From a full visit, and from a capture in progress: back to the rest.
        var full = manualBoard(darts: 3)
        full.command(.captureReference)
        full.quiet(2)
        full.command(.pause(.thermal))
        full.command(.resume)
        #expect(full.quiet(12)[11] == [.emit(.stateChanged(.awaitingTakeout)), .checkCalibration])
    }

    // MARK: Counter commands in manual trigger

    @Test func endVisit_registerManualDart_discardDart_moveTheRestOfTheManualTrigger() {
        var h = manualBoard(darts: 1)
        #expect(h.command(.endVisit) == [.emit(.stateChanged(.awaitingTakeout))])
        h.command(.beginVisit(expectedDarts: 2))
        #expect(h.state == .watching(dartsOnBoard: 1))
        h.command(.registerManualDart)
        #expect(h.command(.registerManualDart) == [.emit(.stateChanged(.awaitingTakeout))])
        // A scan now would find a dart beyond the visit.
        h.command(.captureNow(maxDarts: 1))
        h.quiet(6)
        let extra = scanned(9, flags: [])
        #expect(scanResults(h.settle(.darts(new: [extra], removed: [], disturbed: [])))
                == [[H.observation(extra, flags: .beyondVisitLimit)]])
        // Discarding it leaves a full visit; discarding nothing more, a shorter new visit keeps the known dart.
        #expect(h.command(.discardDart(H.id(9))).isEmpty && h.state == .awaitingTakeout && h.machine.dartsInVisit == 2)
        #expect(h.command(.beginVisit(expectedDarts: 2)) == [.emit(.stateChanged(.watching(dartsOnBoard: 1)))])
        // A hand-entered dart that turns out wrong is not a camera dart: the count is the game layer's business.
        h.command(.registerManualDart)
        h.command(.discardDart(H.id(1)))
        #expect(h.state == .watching(dartsOnBoard: 0) && h.machine.dartsInVisit == 1)
    }

    @Test func armingInManualTrigger_takesTheReferencesLikeTheAutomaticOne() {
        var h = H()
        h.send(.calibrationSet)
        h.command(.setTrigger(.manual))
        h.command(.arm(boardConfirmedEmpty: true))
        // « Cible vide » is not needed before the first scan.
        #expect(h.quiet(12)[11] == [.emit(.stateChanged(.watching(dartsOnBoard: 0))), .updateReference(.rollingAndEmpty),
                                    .setGateReference, .checkCalibration])
    }
}
