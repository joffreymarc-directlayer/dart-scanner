import Foundation
import Testing
import DartCore
import DartVision

/// Commands of the game layer in automatic trigger (VISION.md §6.5): tests S12 and S13.
@Suite struct ReducerCommandTests {
    private typealias H = ReducerHarness

    private func board(darts count: Int, expected: Int = 3) -> H {
        var h = H()
        h.start()
        h.command(.beginVisit(expectedDarts: expected))
        for number in 0..<count { h.throwDart(H.observation(number + 1)) }
        return h
    }

    // MARK: S12: beginVisit, endVisit

    @Test func s12_endVisit_awaitingTakeout_beginVisitWithTwoDartsOnTheBoard_watchingTwo() {
        var h = board(darts: 2)
        #expect(h.state == .watching(dartsOnBoard: 2) && h.machine.visit == 1)
        #expect(h.command(.endVisit) == [.emit(.stateChanged(.awaitingTakeout))])
        #expect(h.state == .awaitingTakeout)
        // Already closed: nothing more.
        #expect(h.command(.endVisit).isEmpty)
        #expect(h.command(.beginVisit(expectedDarts: 3)) == [.emit(.stateChanged(.watching(dartsOnBoard: 2)))])
        #expect(h.state == .watching(dartsOnBoard: 2) && h.machine.visit == 2 && h.machine.dartsInVisit == 0)
        #expect(h.machine.dartsOnBoard == 2)
    }

    @Test func beginVisit_dartsOfTheEarlierVisit_arePulledWithDartRemovedOnly() {
        var h = board(darts: 3)
        h.command(.beginVisit(expectedDarts: 3))
        #expect(h.state == .watching(dartsOnBoard: 3))
        // The previous player pulls two of his darts: no `takeoutStarted`, and the state is not `takeout`.
        h.handEpisode()
        #expect(h.settle(.removed([H.id(1), H.id(2)], boardEmpty: false))
                == [.emit(.stateChanged(.watching(dartsOnBoard: 1))), .emit(.dartRemoved(id: H.id(1), reason: .takeout)),
                    .emit(.dartRemoved(id: H.id(2), reason: .takeout)), .updateReference(.rolling), .setGateReference])
        // Then the last one: the board is empty and both references are retaken, but no `takeoutCompleted`,
        // which would propose to end the turn of the player who has not thrown yet.
        h.handEpisode()
        #expect(h.settle(.removed([H.id(3)], boardEmpty: true))
                == [.emit(.stateChanged(.watching(dartsOnBoard: 0))), .emit(.dartRemoved(id: H.id(3), reason: .takeout)),
                    .updateReference(.rollingAndEmpty), .setGateReference, .checkCalibration])
        #expect(h.machine.dartsInVisit == 0 && h.machine.visit == 2)
    }

    @Test func beginVisit_aDartOfTheCurrentVisitMakesTheTakeoutAnnounced() {
        var h = board(darts: 2)
        h.command(.beginVisit(expectedDarts: 3))
        h.throwDart(H.observation(3))
        // One old dart and the new one are pulled together.
        h.handEpisode()
        #expect(H.events(h.settle(.removed([H.id(1), H.id(3)], boardEmpty: false)))
                == [.stateChanged(.takeout), .takeoutStarted, .dartRemoved(id: H.id(1), reason: .takeout),
                    .dartRemoved(id: H.id(3), reason: .takeout)])
        // A takeout that has started completes, even when only an old dart is left.
        h.episode()
        #expect(H.facts(h.settle(.removed([H.id(2)], boardEmpty: true)))
                == [.dartRemoved(id: H.id(2), reason: .takeout), .takeoutCompleted])
    }

    @Test func beginVisit_fromTakeout_backToWatching_andNoStallForOldDarts() {
        var h = board(darts: 3)
        h.handEpisode()
        h.settle(.removed([H.id(1)], boardEmpty: false))
        #expect(h.state == .takeout)
        #expect(h.command(.beginVisit(expectedDarts: 3)) == [.emit(.stateChanged(.watching(dartsOnBoard: 2)))])
        #expect(H.events(h.quiet(200).flatMap { $0 }).isEmpty && h.state == .watching(dartsOnBoard: 2))
    }

    @Test func beginVisit_duringAnEpisode_changesCountersNow_andTheStateWhenTheEpisodeEnds() {
        var h = board(darts: 3)
        h.moving(3)
        #expect(h.command(.beginVisit(expectedDarts: 3)).isEmpty && h.state == .motion)
        #expect(h.machine.visit == 2 && h.machine.dartsInVisit == 0)
        h.quiet(6, change: H.dartChange)
        // Back to `watching(3)`, not to the `awaitingTakeout` the episode started from.
        #expect(h.settle(.noChange) == [.emit(.stateChanged(.watching(dartsOnBoard: 3))), .emit(.possibleMiss(timestamp: h.now))])
        // And `endVisit` during an episode closes the visit the same way.
        h.moving(3)
        #expect(h.command(.endVisit).isEmpty)
        h.quiet(6, change: H.dartChange)
        #expect(H.events(h.settle(.noChange)).first == .stateChanged(.awaitingTakeout))
    }

    @Test func beginVisit_expectedDarts_zeroOrNegative_isAFullVisit() {
        var h = board(darts: 0)
        #expect(h.command(.beginVisit(expectedDarts: 0)) == [.emit(.stateChanged(.awaitingTakeout))])
        // Any dart now is beyond the visit.
        let first = H.observation(1)
        #expect(H.facts(h.throwDart(first)) == [.dart(H.observation(first, flags: .beyondVisitLimit))])
        #expect(h.command(.beginVisit(expectedDarts: -4)).isEmpty && h.state == .awaitingTakeout)
        #expect(h.command(.beginVisit(expectedDarts: 2)) == [.emit(.stateChanged(.watching(dartsOnBoard: 1)))])
        // Three darts found in one pose with two places left: only the third is beyond.
        h.episode()
        let darts = [H.observation(2), H.observation(3), H.observation(4)]
        #expect(H.facts(h.settle(.darts(new: darts, removed: [], disturbed: [])))
                == [.dart(darts[0]), .dart(darts[1]), .dart(H.observation(darts[2], flags: .beyondVisitLimit))])
        #expect(h.state == .awaitingTakeout && h.machine.dartsInVisit == 3)
    }

    // MARK: S13: discardDart, registerManualDart

    @Test func s13_discardDart_registerManualDart_adjustCounters_withoutTouchingReferences() {
        var h = board(darts: 2)
        // A false detection: the count drops, the footprint stays in the rolling reference.
        #expect(h.command(.discardDart(H.id(1))) == [.emit(.stateChanged(.watching(dartsOnBoard: 1)))])
        #expect(h.machine.dartsOnBoard == 1 && h.machine.dartsInVisit == 1)
        // A dart vision missed: only the count of the visit rises.
        #expect(h.command(.registerManualDart).isEmpty)
        #expect(h.machine.dartsOnBoard == 1 && h.machine.dartsInVisit == 2 && h.state == .watching(dartsOnBoard: 1))
        // The third dart of the visit, added by hand, fills it.
        #expect(h.command(.registerManualDart) == [.emit(.stateChanged(.awaitingTakeout))])
        #expect(h.machine.dartsInVisit == 3)
        // An identifier that was never counted changes nothing.
        #expect(h.command(.discardDart(H.id(50))).isEmpty && h.machine.dartsInVisit == 3)
        // Discarding a counted dart reopens the visit.
        #expect(h.command(.discardDart(H.id(2))) == [.emit(.stateChanged(.watching(dartsOnBoard: 0)))])
        #expect(h.machine.dartsOnBoard == 0 && h.machine.dartsInVisit == 2)
        // Twice the same identifier: counted once.
        #expect(h.command(.discardDart(H.id(2))).isEmpty && h.machine.dartsInVisit == 2)
    }

    @Test func discardDart_ofAnEarlierVisit_leavesTheVisitCountAlone_andAFallenDartCanStillBeDiscarded() {
        var h = board(darts: 1)
        h.command(.beginVisit(expectedDarts: 3))
        h.throwDart(H.observation(2))
        // Dart 1 belongs to the earlier visit.
        h.command(.discardDart(H.id(1)))
        #expect(h.machine.dartsOnBoard == 1 && h.machine.dartsInVisit == 1)
        // Dart 2 falls out, then the player discards it: it is no longer on the board but still counted.
        h.episode()
        h.settle(.removed([H.id(2)], boardEmpty: true))
        #expect(h.machine.dartsOnBoard == 0 && h.machine.dartsInVisit == 1)
        #expect(h.command(.discardDart(H.id(2))).isEmpty)
        #expect(h.machine.dartsInVisit == 0)
    }

    @Test func discardDart_lastDartOfATakeout_endsTheTakeout() {
        var h = board(darts: 2)
        h.handEpisode()
        h.settle(.removed([H.id(1)], boardEmpty: false))
        #expect(h.state == .takeout)
        #expect(h.command(.discardDart(H.id(2))) == [.emit(.stateChanged(.watching(dartsOnBoard: 0)))])
        // No stall for a takeout with nothing left.
        #expect(H.events(h.quiet(200).flatMap { $0 }).isEmpty)
    }

    @Test func counterCommands_inIdleArmingAndPause_updateCountersWithoutAStateChange() {
        var h = H()
        // Even without a calibration.
        #expect(h.command(.beginVisit(expectedDarts: 3)).isEmpty && h.machine.visit == 1 && h.state == .needsCalibration)
        h.send(.calibrationSet)
        #expect(h.command(.registerManualDart).isEmpty && h.machine.dartsInVisit == 1 && h.state == .idle)
        #expect(h.command(.endVisit).isEmpty && h.state == .idle)
        h.command(.arm(boardConfirmedEmpty: true))
        #expect(h.machine.visit == 0 && h.machine.dartsInVisit == 0)
        #expect(h.command(.beginVisit(expectedDarts: 3)).isEmpty && h.command(.registerManualDart).isEmpty)
        #expect(h.state == .arming && h.machine.visit == 1 && h.machine.dartsInVisit == 1)
        h.quiet(12)
        #expect(h.state == .watching(dartsOnBoard: 0))
        h.command(.pause(.background))
        #expect(h.command(.registerManualDart).isEmpty && h.command(.beginVisit(expectedDarts: 3)).isEmpty)
        #expect(h.command(.discardDart(H.id(1))).isEmpty && h.command(.endVisit).isEmpty)
        #expect(h.state == .paused(.background) && h.machine.visit == 2 && h.machine.dartsInVisit == 0)
    }

    // MARK: confirmBoardEmpty and rebaseline in automatic trigger

    @Test func confirmBoardEmpty_fromAStillState_forcesAPoseAtOnce() {
        var h = board(darts: 2)
        // Like row 9: four frames, no analysis.
        #expect(h.command(.confirmBoardEmpty) == [.emit(.stateChanged(.settling)), .beginAccumulation])
        let pose = h.quiet(4, change: H.dartChange)
        #expect(pose[0].isEmpty && pose[1].isEmpty && pose[2].isEmpty)
        // `E := R := S`, silhouettes cleared, `watching(0)`; a new empty reference is checked for drift (§4.9).
        #expect(pose[3] == [.emit(.stateChanged(.watching(dartsOnBoard: 0))), .updateReference(.rollingAndEmpty),
                            .setGateReference, .checkCalibration])
        #expect(h.machine.dartsOnBoard == 0 && h.machine.dartsInVisit == 2 && h.machine.visit == 1)
    }

    @Test func confirmBoardEmpty_duringAnEpisode_usesThePoseOfTheEpisode() {
        var h = board(darts: 1)
        h.moving(3)
        #expect(h.command(.confirmBoardEmpty).isEmpty && h.state == .motion)
        let pose = h.quiet(6, change: H.dartChange)
        #expect(pose[1] == [.emit(.stateChanged(.settling)), .beginAccumulation, .checkCalibration])
        // No analysis; the drift check already ran on the second quiet frame.
        #expect(pose[5] == [.emit(.stateChanged(.watching(dartsOnBoard: 0))), .updateReference(.rollingAndEmpty),
                            .setGateReference])
        // Received during `settling`: same thing.
        h.throwDart(H.observation(2))
        h.moving(3)
        h.quiet(3, change: H.dartChange)
        #expect(h.command(.confirmBoardEmpty).isEmpty && h.state == .settling)
        #expect(H.references(h.quiet(3, change: H.dartChange)[2]) == [.updateReference(.rollingAndEmpty)])
        #expect(h.state == .watching(dartsOnBoard: 0))
    }

    @Test func confirmBoardEmpty_motionDuringTheForcedPose_keepsTheIntent() {
        var h = board(darts: 1)
        h.command(.confirmBoardEmpty)
        #expect(h.moving(1)[0] == [.discardAccumulation, .emit(.stateChanged(.motion))])
        h.moving(2)
        let pose = h.quiet(6, change: H.dartChange)
        #expect(H.analyses(pose.flatMap { $0 }).isEmpty)
        #expect(H.references(pose[5]) == [.updateReference(.rollingAndEmpty)] && h.state == .watching(dartsOnBoard: 0))
    }

    @Test func confirmBoardEmpty_fromObstructed_andFromAwaitingTakeout() {
        var h = board(darts: 3)
        #expect(h.state == .awaitingTakeout)
        h.command(.confirmBoardEmpty)
        #expect(H.events(h.quiet(4)[3]) == [.stateChanged(.watching(dartsOnBoard: 0))])
        h.handEpisode()
        h.settle(.obstruction)
        #expect(h.command(.confirmBoardEmpty) == [.emit(.stateChanged(.settling)), .beginAccumulation])
        #expect(h.quiet(4, change: 0.2)[3].contains(.updateReference(.rollingAndEmpty)))
        #expect(h.state == .watching(dartsOnBoard: 0))
    }

    @Test func rebaseline_fromAStillState_takesTheRollingReference_stateAndSilhouettesKept() {
        var h = board(darts: 3)
        #expect(h.command(.rebaseline) == [.emit(.stateChanged(.settling)), .beginAccumulation])
        let pose = h.quiet(4, change: H.dartChange)
        #expect(pose[3] == [.emit(.stateChanged(.awaitingTakeout)), .updateReference(.rolling), .setGateReference])
        #expect(h.machine.dartsOnBoard == 3 && h.machine.dartsInVisit == 3)
        // From `obstructed` ("Continuer"): the board as it is becomes the baseline, back to the state before.
        h.handEpisode()
        h.settle(.obstruction)
        h.command(.rebaseline)
        #expect(h.quiet(4, change: 0.2)[3] == [.emit(.stateChanged(.awaitingTakeout)), .updateReference(.rolling),
                                               .setGateReference])
    }

    @Test func rebaseline_duringAnEpisode_usesItsPose_andNeverReplacesAConfirmedEmptyBoard() {
        var h = board(darts: 1)
        h.moving(3)
        #expect(h.command(.rebaseline).isEmpty)
        let pose = h.quiet(6, change: H.dartChange)
        #expect(pose[5] == [.emit(.stateChanged(.watching(dartsOnBoard: 1))), .updateReference(.rolling), .setGateReference])
        h.moving(3)
        h.command(.confirmBoardEmpty)
        h.command(.rebaseline)
        #expect(H.references(h.quiet(6, change: H.dartChange)[5]) == [.updateReference(.rollingAndEmpty)])
    }

    // MARK: Commands no row provides for are ignored, without any event

    @Test func commandsWithoutARow_areIgnored() {
        // needsCalibration: only counters and pause do anything.
        var h = H()
        for command: ScanCommand in [.arm(boardConfirmedEmpty: true), .confirmBoardEmpty, .rebaseline, .captureReference,
                                     .captureNow(maxDarts: 3), .resume] {
            #expect(h.command(command).isEmpty && h.state == .needsCalibration, "\(command)")
        }
        // idle.
        h.send(.calibrationSet)
        for command: ScanCommand in [.rebaseline, .captureReference, .captureNow(maxDarts: 3), .resume] {
            #expect(h.command(command).isEmpty && h.state == .idle, "\(command)")
        }
        // arming.
        h.command(.arm(boardConfirmedEmpty: false))
        for command: ScanCommand in [.confirmBoardEmpty, .rebaseline, .captureReference, .captureNow(maxDarts: 3), .resume] {
            #expect(h.command(command).isEmpty && h.state == .arming, "\(command)")
        }
        // The board was not confirmed empty: the command ignored above did not change that.
        #expect(H.references(h.quiet(12)[11]) == [.updateReference(.rolling)])
        // watching, automatic trigger: capture commands and `resume`.
        for command: ScanCommand in [.captureReference, .captureNow(maxDarts: 3), .resume, .setTrigger(.automatic)] {
            #expect(h.command(command).isEmpty && h.state == .watching(dartsOnBoard: 0), "\(command)")
        }
        // analysing.
        h.episode()
        for command: ScanCommand in [.confirmBoardEmpty, .rebaseline, .captureReference, .captureNow(maxDarts: 3), .resume] {
            #expect(h.command(command).isEmpty && h.state == .analysing, "\(command)")
        }
        // paused.
        h.command(.pause(.background))
        for command: ScanCommand in [.confirmBoardEmpty, .rebaseline, .captureReference, .captureNow(maxDarts: 3)] {
            #expect(h.command(command).isEmpty && h.state == .paused(.background), "\(command)")
        }
    }

    @Test func beyondVisitLimit_followsTheCountersOfTheVisit() {
        // Four darts in the first pose of a visit of three: the fourth is beyond.
        var h = board(darts: 0)
        h.episode()
        let four = (1...4).map { H.observation($0) }
        #expect(H.facts(h.settle(.darts(new: four, removed: [], disturbed: [])))
                == [.dart(four[0]), .dart(four[1]), .dart(four[2]), .dart(H.observation(four[3], flags: .beyondVisitLimit))])
        // A dart added by hand takes a place: one camera dart and one manual dart leave one place.
        var manual = board(darts: 1)
        manual.command(.registerManualDart)
        manual.episode()
        let pair = [H.observation(5), H.observation(6)]
        #expect(H.facts(manual.settle(.darts(new: pair, removed: [], disturbed: [])))
                == [.dart(pair[0]), .dart(H.observation(pair[1], flags: .beyondVisitLimit))])
        // A closed visit puts every dart beyond, even when it is not full.
        var closed = board(darts: 1)
        closed.command(.endVisit)
        closed.episode()
        let late = H.observation(7)
        #expect(H.facts(closed.settle(.darts(new: [late], removed: [], disturbed: [])))
                == [.dart(H.observation(late, flags: .beyondVisitLimit))])
        // Two darts found in one pose with one place left: the second is beyond the limit.
        var two = board(darts: 2)
        two.episode()
        let third = H.observation(3)
        let fourth = H.observation(4)
        #expect(H.facts(two.settle(.darts(new: [third, fourth], removed: [], disturbed: [])))
                == [.dart(third), .dart(H.observation(fourth, flags: .beyondVisitLimit))])
    }
}
