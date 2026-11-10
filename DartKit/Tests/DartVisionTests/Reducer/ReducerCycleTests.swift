import Foundation
import Testing
import DartCore
import DartVision

/// Base cycle of the reducer (VISION.md §6.3, rows 1 to 10): tests S1 to S4, S9, S14 and S15.
@Suite struct ReducerCycleTests {
    private typealias H = ReducerHarness

    // MARK: S1 and rows 1 to 3

    @Test func initialState_needsCalibration() {
        let machine = ScanStateMachine()
        #expect(machine.state == .needsCalibration && machine.trigger == .automatic)
        #expect(machine.dartsOnBoard == 0 && machine.visit == 0 && machine.dartsInVisit == 0 && machine.lastEpisode == nil)
        var manual = ScanParameters()
        manual.trigger = .manual
        #expect(ScanStateMachine(parameters: manual).trigger == .manual)
    }

    @Test func s1_armThenTwelveQuietSamples_watchingZero() {
        var h = H()
        #expect(h.send(.calibrationSet) == [.emit(.stateChanged(.idle))])
        #expect(h.command(.arm(boardConfirmedEmpty: true)) == [.emit(.stateChanged(.arming))])
        let effects = h.quiet(12)
        // The last four frames of the arming are the references: accumulation starts after the eighth.
        for (index, step) in effects.enumerated() where index != 7 && index != 11 {
            #expect(step.isEmpty, "quiet sample \(index + 1)")
        }
        #expect(effects[7] == [.beginAccumulation])
        #expect(effects[11] == [.emit(.stateChanged(.watching(dartsOnBoard: 0))), .updateReference(.rollingAndEmpty),
                                .setGateReference, .checkCalibration])
        #expect(h.state == .watching(dartsOnBoard: 0))
        #expect(h.machine.visit == 0 && h.machine.dartsInVisit == 0 && h.machine.dartsOnBoard == 0)
    }

    @Test func row3_boardNotConfirmedEmpty_takesTheRollingReferenceOnly() {
        var h = H()
        h.send(.calibrationSet)
        h.command(.arm(boardConfirmedEmpty: false))
        let last = h.quiet(12)[11]
        #expect(last == [.emit(.stateChanged(.watching(dartsOnBoard: 0))), .updateReference(.rolling), .setGateReference,
                         .checkCalibration])
    }

    @Test func row3_aMovingSampleRestartsTheArming() {
        var h = H()
        h.send(.calibrationSet)
        h.command(.arm(boardConfirmedEmpty: true))
        #expect(h.quiet(10).flatMap { $0 } == [.beginAccumulation])
        // Not quiet: the count and the accumulation start again; the state does not change.
        #expect(h.sample(motion: 0.02) == [.discardAccumulation])
        #expect(h.state == .arming)
        #expect(h.quiet(11).flatMap { $0 } == [.beginAccumulation])
        #expect(h.state == .arming)
        #expect(H.events(h.quiet(1)[0]) == [.stateChanged(.watching(dartsOnBoard: 0))])
    }

    @Test func row3_armedInputEndsTheArming_andIsIgnoredElsewhere() {
        var h = H()
        #expect(h.send(.armed).isEmpty && h.state == .needsCalibration)
        h.send(.calibrationSet)
        #expect(h.send(.armed).isEmpty && h.state == .idle)
        h.command(.arm(boardConfirmedEmpty: true))
        #expect(h.send(.armed) == [.emit(.stateChanged(.watching(dartsOnBoard: 0))), .updateReference(.rollingAndEmpty),
                                   .setGateReference, .checkCalibration])
        #expect(h.send(.armed).isEmpty && h.state == .watching(dartsOnBoard: 0))
    }

    @Test func row1_calibrationSet_fromEveryState_goesToIdle() {
        var h = H()
        #expect(h.send(.calibrationSet) == [.emit(.stateChanged(.idle))])
        // Already idle: nothing to say.
        #expect(h.send(.calibrationSet).isEmpty)
        // From a still state with darts: silhouettes are gone, the visit counters stay.
        h.start()
        h.command(.beginVisit(expectedDarts: 3))
        h.throwDart(H.observation(1))
        #expect(h.state == .watching(dartsOnBoard: 1))
        #expect(h.send(.calibrationSet) == [.emit(.stateChanged(.idle))])
        #expect(h.machine.dartsOnBoard == 0 && h.machine.visit == 1 && h.machine.dartsInVisit == 1)
        // Frames are ignored in idle.
        #expect(h.moving(5).flatMap { $0 }.isEmpty && h.quiet(40).flatMap { $0 }.isEmpty && h.state == .idle)
        // During an episode: the accumulation is dropped.
        h.start()
        h.moving(3)
        h.quiet(3)
        #expect(h.state == .settling)
        #expect(h.send(.calibrationSet) == [.discardAccumulation, .emit(.stateChanged(.idle))])
        // From a pause, whatever its reason.
        h.start()
        h.command(.pause(.user))
        #expect(h.send(.calibrationSet) == [.emit(.stateChanged(.idle))])
    }

    @Test func row2_arm_fromEveryCalibratedState_restartsFromZero() {
        // needsCalibration: ignored.
        var h = H()
        #expect(h.command(.arm(boardConfirmedEmpty: true)).isEmpty && h.state == .needsCalibration)

        // watching(1), with counters to clear.
        h.start()
        h.command(.beginVisit(expectedDarts: 3))
        h.command(.beginVisit(expectedDarts: 3))
        h.throwDart(H.observation(1))
        #expect(h.machine.visit == 2 && h.machine.dartsInVisit == 1 && h.machine.dartsOnBoard == 1)
        #expect(h.command(.arm(boardConfirmedEmpty: true)) == [.emit(.stateChanged(.arming))])
        #expect(h.machine.visit == 0 && h.machine.dartsInVisit == 0 && h.machine.dartsOnBoard == 0)
        #expect(h.machine.lastEpisode == nil)

        // arming: starts again from zero, without a state change.
        h.quiet(11)
        #expect(h.command(.arm(boardConfirmedEmpty: true)) == [.discardAccumulation])
        #expect(h.quiet(11).last == [] && h.state == .arming)
        #expect(h.quiet(1)[0].contains(.updateReference(.rollingAndEmpty)) && h.state == .watching(dartsOnBoard: 0))

        // motion, settling, analysing: the episode is abandoned.
        h.moving(2)
        #expect(h.state == .motion)
        #expect(h.command(.arm(boardConfirmedEmpty: false)) == [.discardAccumulation, .emit(.stateChanged(.arming))])
        h.quiet(12)
        h.moving(2)
        h.quiet(2)
        #expect(h.state == .settling)
        #expect(h.command(.arm(boardConfirmedEmpty: false)) == [.discardAccumulation, .emit(.stateChanged(.arming))])
        h.quiet(12)
        h.episode()
        #expect(h.state == .analysing)
        #expect(h.command(.arm(boardConfirmedEmpty: false)) == [.discardAccumulation, .emit(.stateChanged(.arming))])
        // The answer of the abandoned analysis is ignored.
        #expect(h.settle(.darts(new: [H.observation(9)], removed: [], disturbed: [])).isEmpty)
        #expect(h.state == .arming && h.machine.dartsOnBoard == 0)

        // idle.
        h.send(.calibrationSet)
        #expect(h.command(.arm(boardConfirmedEmpty: true)) == [.emit(.stateChanged(.arming))])
    }

    @Test func row2_arm_fromObstructedAndTakeout() {
        var h = H()
        h.start()
        h.handEpisode()
        h.settle(.obstruction)
        #expect(h.state == .obstructed)
        #expect(h.command(.arm(boardConfirmedEmpty: true)) == [.emit(.stateChanged(.arming))])
        h.quiet(12)
        h.command(.beginVisit(expectedDarts: 3))
        h.throwDart(H.observation(1))
        h.throwDart(H.observation(2))
        h.handEpisode()
        h.settle(.removed([H.id(1)], boardEmpty: false))
        #expect(h.state == .takeout)
        #expect(h.command(.arm(boardConfirmedEmpty: true)) == [.emit(.stateChanged(.arming))])
        #expect(h.machine.dartsOnBoard == 0 && h.machine.visit == 0)
    }

    // MARK: S2, S3

    @Test func s2_motionThenPoseThenDart() {
        var h = H()
        h.start()
        let dart = H.observation(1)
        let motion = h.moving(3)
        // Row 4.
        #expect(motion[0] == [.discardAccumulation, .emit(.stateChanged(.motion))])
        #expect(motion[1].isEmpty && motion[2].isEmpty)
        let quiet = h.quiet(6, change: H.dartChange)
        #expect(quiet[0].isEmpty)
        // Row 5: second quiet frame; the drift check is requested last.
        #expect(quiet[1] == [.emit(.stateChanged(.settling)), .beginAccumulation, .checkCalibration])
        #expect(quiet[2].isEmpty && quiet[3].isEmpty && quiet[4].isEmpty)
        // Row 7: sixth quiet frame.
        #expect(quiet[5] == [.emit(.stateChanged(.analysing)), .analyse(maxNewDarts: 1)])
        #expect(h.state == .analysing)
        // A1.
        let outcome = h.settle(.darts(new: [dart], removed: [], disturbed: []))
        #expect(outcome == [.emit(.stateChanged(.watching(dartsOnBoard: 1))), .emit(.dart(dart)), .updateReference(.rolling),
                            .setGateReference])
        #expect(h.state == .watching(dartsOnBoard: 1) && h.machine.dartsOnBoard == 1 && h.machine.dartsInVisit == 1)
    }

    @Test func s3_threeDarts_watching1_watching2_awaitingTakeout() {
        var h = H()
        h.start()
        h.command(.beginVisit(expectedDarts: 3))
        let first = h.throwDart(H.observation(1))
        #expect(h.state == .watching(dartsOnBoard: 1) && H.events(first).first == .stateChanged(.watching(dartsOnBoard: 1)))
        let second = h.throwDart(H.observation(2))
        #expect(h.state == .watching(dartsOnBoard: 2) && H.events(second).first == .stateChanged(.watching(dartsOnBoard: 2)))
        // A2: the dart that fills the visit.
        let third = h.throwDart(H.observation(3))
        #expect(third == [.emit(.stateChanged(.awaitingTakeout)), .emit(.dart(H.observation(3))), .updateReference(.rolling),
                          .setGateReference])
        #expect(h.state == .awaitingTakeout && h.machine.dartsOnBoard == 3 && h.machine.dartsInVisit == 3)
    }

    @Test func a1_visitOfTwoExpectedDarts_isFullAfterTwo() {
        var h = H()
        h.start()
        h.command(.beginVisit(expectedDarts: 2))
        h.throwDart(H.observation(1))
        #expect(h.state == .watching(dartsOnBoard: 1))
        h.throwDart(H.observation(2))
        #expect(h.state == .awaitingTakeout)
    }

    // MARK: S4 and row 7

    @Test func s4_noChange_afterThrowLikeEpisode_possibleMissAlone_afterHandLikeEpisode_nothing() {
        var h = H()
        h.start()
        // 0.2 s of motion, then an analysis that finds nothing (A5).
        h.moving(6)
        h.quiet(6, change: H.dartChange)
        let miss = h.settle(.noChange)
        #expect(miss == [.emit(.stateChanged(.watching(dartsOnBoard: 0))), .emit(.possibleMiss(timestamp: h.now))])
        let throwEpisode = h.machine.lastEpisode
        #expect(throwEpisode.map { abs($0.duration - 0.2) < 1e-9 } == true)
        #expect(throwEpisode?.isHandLike(ScanParameters()) == false)
        #expect(throwEpisode?.peakMotionFraction == 0.02 && throwEpisode?.borderIntrusionFrames == 0)
        // 1.5 s of motion: a hand (A6).
        h.moving(45)
        h.quiet(6, change: H.dartChange)
        #expect(h.settle(.noChange) == [.emit(.stateChanged(.watching(dartsOnBoard: 0)))])
        #expect(h.machine.lastEpisode.map { abs($0.duration - 1.5) < 1e-9 } == true)
        #expect(h.machine.lastEpisode?.isHandLike(ScanParameters()) == true)
        #expect(h.machine.dartsInVisit == 0 && h.machine.dartsOnBoard == 0)
    }

    @Test func row7_noLastingChange_skipsTheAnalysis() {
        var h = H()
        h.start()
        // The gate is back on its reference at the sixth quiet frame: outcome "no change" without `analyse`.
        h.moving(6)
        let quiet = h.quiet(6, change: 0.0001)
        #expect(quiet[1] == [.emit(.stateChanged(.settling)), .beginAccumulation, .checkCalibration])
        #expect(quiet[5] == [.discardAccumulation, .emit(.stateChanged(.watching(dartsOnBoard: 0))),
                             .emit(.possibleMiss(timestamp: h.now))])
        // Hand-like: nothing but the return.
        h.moving(45)
        #expect(h.quiet(6, change: 0.0001)[5] == [.discardAccumulation, .emit(.stateChanged(.watching(dartsOnBoard: 0)))])
        // Exactly at the threshold the change is lasting: the analysis runs.
        h.moving(6)
        #expect(h.quiet(6, change: ScanParameters().noLastingChangeFraction)[5]
                == [.emit(.stateChanged(.analysing)), .analyse(maxNewDarts: 1)])
    }

    @Test func episodeKind_borderIntrusionOfFiveFrames_isAHand() {
        var h = H()
        h.start()
        // Short (0.2 s) but the border was crossed for five frames in a row: hand-like, no `possibleMiss`.
        h.moving(1)
        h.moving(5, border: 0.05)
        h.quiet(6, change: H.dartChange)
        #expect(h.machine.lastEpisode?.borderIntrusionFrames == 5)
        #expect(h.settle(.noChange) == [.emit(.stateChanged(.watching(dartsOnBoard: 0)))])
        // Four frames in a row, twice: the longest run counts, and it is throw-like.
        h.moving(4, border: 0.05)
        h.moving(1)
        h.moving(1, border: 0.05)
        h.quiet(6, change: H.dartChange)
        #expect(h.machine.lastEpisode?.borderIntrusionFrames == 4)
        #expect(H.facts(h.settle(.noChange)) == [.possibleMiss(timestamp: h.now)])
        // Exactly at the border threshold is not an intrusion.
        h.moving(6, border: ScanParameters().handBorderFraction)
        h.quiet(6, change: H.dartChange)
        #expect(h.machine.lastEpisode?.borderIntrusionFrames == 0)
        h.settle(.noChange)
    }

    @Test func episodeSummary_isHandLike_thresholds() {
        let parameters = ScanParameters()
        #expect(!EpisodeSummary(duration: 0.6, peakMotionFraction: 0.5, borderIntrusionFrames: 4).isHandLike(parameters))
        #expect(EpisodeSummary(duration: 0.61, peakMotionFraction: 0, borderIntrusionFrames: 0).isHandLike(parameters))
        #expect(EpisodeSummary(duration: 0.1, peakMotionFraction: 0, borderIntrusionFrames: 5).isHandLike(parameters))
        var strict = ScanParameters()
        strict.throwMaxDuration = 0.05
        #expect(EpisodeSummary(duration: 0.1, peakMotionFraction: 0, borderIntrusionFrames: 0).isHandLike(strict))
    }

    // MARK: S9, S15 and rows 4 to 6

    @Test func s9_motionDuringThePose_discardsTheAccumulation_noAnalysis() {
        var h = H()
        h.start()
        var log: [ScanEffect] = []
        log += h.moving(3).flatMap { $0 }
        log += h.quiet(4, change: H.dartChange).flatMap { $0 }
        #expect(h.state == .settling)
        // Row 6.
        let interrupted = h.moving(1)[0]
        #expect(interrupted == [.discardAccumulation, .emit(.stateChanged(.motion))])
        log += interrupted
        // The quiet count starts again: five quiet frames are not enough.
        log += h.quiet(5, change: H.dartChange).flatMap { $0 }
        #expect(h.state == .settling)
        #expect(H.analyses(log).isEmpty)
        #expect(h.quiet(1, change: H.dartChange)[0] == [.emit(.stateChanged(.analysing)), .analyse(maxNewDarts: 1)])
    }

    @Test func row5_oneQuietFrameIsNotEnough_andAFrameBetweenTheThresholdsIsNotQuiet() {
        var h = H()
        h.start()
        h.moving(2)
        #expect(h.quiet(1)[0].isEmpty && h.state == .motion)
        #expect(h.moving(1)[0].isEmpty && h.state == .motion)
        #expect(h.quiet(1)[0].isEmpty && h.state == .motion)
        // 0.08 % is neither quiet (< 0.05 %) nor a start of motion (> 0.12 %): it breaks the quiet run.
        #expect(h.sample(motion: 0.0008).isEmpty && h.state == .motion)
        #expect(h.quiet(1)[0].isEmpty && h.state == .motion)
        #expect(h.quiet(1)[0].first == .emit(.stateChanged(.settling)))
    }

    @Test func row4_motionStartsAboveTheThresholdOnly() {
        var h = H()
        h.start()
        let parameters = ScanParameters()
        #expect(h.sample(motion: parameters.motionOnFraction).isEmpty && h.state == .watching(dartsOnBoard: 0))
        #expect(h.sample(motion: 0.0008).isEmpty && h.state == .watching(dartsOnBoard: 0))
        #expect(h.sample(motion: 0.0013) == [.discardAccumulation, .emit(.stateChanged(.motion))])
    }

    @Test func s15_latency_analysisAtMostSixFramesAfterTheLastMovingFrame() {
        for movingFrames in [1, 3, 10, 45] {
            var h = H()
            h.start()
            h.moving(movingFrames)
            let lastMoving = h.frame - 1
            var analysedAt: Int?
            for _ in 0..<20 where analysedAt == nil {
                if !H.analyses(h.sample(motion: 0.0001, change: H.dartChange)).isEmpty { analysedAt = h.frame - 1 }
            }
            #expect(analysedAt == lastMoving + 6, "\(movingFrames) moving frames")
        }
    }

    // MARK: S14 and row 8

    @Test func s14_nineSecondsOfMotion_obstructedWithOneAdvisory() {
        var h = H()
        h.start()
        var log: [ScanEffect] = []
        log += h.moving(239).flatMap { $0 }
        // Not yet 8 s.
        #expect(h.state == .motion)
        log += h.moving(31).flatMap { $0 }
        #expect(h.state == .obstructed)
        #expect(H.events(log) == [.stateChanged(.motion), .stateChanged(.obstructed), .advisory(.viewObstructed)])
        #expect(H.work(log) == [.discardAccumulation])
        // Row 8 fired once more than 8 s after the first moving frame.
        let obstructedAt = log.firstIndex(of: .emit(.stateChanged(.obstructed)))
        #expect(obstructedAt != nil)
    }

    @Test func row8_thenTheViewCalmsDown_poseAndAnalysis_handLike() {
        var h = H()
        h.start()
        h.command(.beginVisit(expectedDarts: 3))
        h.throwDart(H.observation(1))
        h.moving(260)
        #expect(h.state == .obstructed)
        // More motion changes nothing; the first quiet frame neither.
        #expect(h.moving(30).flatMap { $0 }.isEmpty && h.quiet(1)[0].isEmpty && h.state == .obstructed)
        // Second quiet frame: the pose starts (A12), then the outcome is read as after a hand.
        #expect(h.quiet(1, change: H.dartChange)[0] == [.emit(.stateChanged(.settling)), .beginAccumulation, .checkCalibration])
        #expect(h.quiet(4, change: H.dartChange)[3] == [.emit(.stateChanged(.analysing)), .analyse(maxNewDarts: 1)])
        #expect(h.machine.lastEpisode?.isHandLike(ScanParameters()) == true)
        let outcome = h.settle(.removed([H.id(1)], boardEmpty: true))
        #expect(H.events(outcome) == [.stateChanged(.watching(dartsOnBoard: 0)),
                                      .dartRemoved(id: H.id(1), reason: .takeout), .takeoutCompleted])
    }

    // MARK: Rows 9 and 10

    @Test func row9_idleCheck_everyTwoSeconds_whenTheGateDiffersFromItsReference() {
        var h = H()
        h.start()
        h.command(.beginVisit(expectedDarts: 3))
        h.throwDart(H.observation(1))
        let enteredAt = h.frame - 1
        // A still board that differs from the gate reference (0.1 %): nothing before 2 s.
        var forcedAt: Int?
        var forced: [ScanEffect] = []
        for _ in 0..<70 where forcedAt == nil {
            let effects = h.sample(motion: 0.0001, change: 0.001)
            if !effects.isEmpty {
                forcedAt = h.frame - 1
                forced = effects
            }
        }
        #expect(forced == [.emit(.stateChanged(.settling)), .beginAccumulation])
        #expect(forcedAt.map { abs($0 - (enteredAt + 60)) <= 1 } == true)
        // Accumulation of four frames, then the analysis.
        let pose = h.quiet(4, change: 0.001)
        #expect(pose[0].isEmpty && pose[1].isEmpty && pose[2].isEmpty)
        #expect(pose[3] == [.emit(.stateChanged(.analysing)), .analyse(maxNewDarts: 1)])
        // "No change" at an idle check: the board is absorbed (row 10) and no miss is announced.
        #expect(h.settle(.noChange) == [.emit(.stateChanged(.watching(dartsOnBoard: 1))), .updateReference(.rolling),
                                        .setGateReference])
    }

    @Test func row9_idleCheck_appliesInAwaitingTakeout_andFindsATakeout() {
        var h = H()
        h.start()
        h.command(.beginVisit(expectedDarts: 1))
        h.throwDart(H.observation(1))
        #expect(h.state == .awaitingTakeout)
        var log: [ScanEffect] = []
        for _ in 0..<62 { log += h.sample(motion: 0.0001, change: 0.004) }
        #expect(h.state == .settling)
        h.quiet(4, change: 0.004)
        #expect(h.state == .analysing)
        // A7 at an idle check: no episode at all, the darts were pulled.
        let outcome = h.settle(.removed([H.id(1)], boardEmpty: true))
        #expect(outcome == [.emit(.stateChanged(.watching(dartsOnBoard: 0))),
                            .emit(.dartRemoved(id: H.id(1), reason: .takeout)), .emit(.takeoutCompleted),
                            .updateReference(.rollingAndEmpty), .setGateReference, .checkCalibration])
    }

    @Test func row9_motionDuringTheForcedPose_startsAnEpisode() {
        var h = H()
        h.start()
        for _ in 0..<62 { h.sample(motion: 0.0001, change: 0.001) }
        #expect(h.state == .settling)
        #expect(h.moving(1)[0] == [.discardAccumulation, .emit(.stateChanged(.motion))])
        h.moving(2)
        h.quiet(6, change: H.dartChange)
        #expect(h.state == .analysing)
        // The episode began with that frame: 0.1 s, throw-like.
        #expect(H.facts(h.settle(.noChange)) == [.possibleMiss(timestamp: h.now)])
    }

    @Test func row10_tenSecondsUnchanged_refreshesTheRollingReference_withoutAnyEvent() {
        var h = H()
        h.start()
        let enteredAt = h.frame - 1
        var log: [(frame: Int, effects: [ScanEffect])] = []
        for _ in 0..<620 {
            let effects = h.sample(motion: 0.0001, change: 0.0001)
            if !effects.isEmpty { log.append((h.frame - 1, effects)) }
        }
        // Twice in 20 s: four frames accumulated, then `R := S` and the gate reference. No event, no state change.
        #expect(log.map(\.effects) == [[.beginAccumulation], [.updateReference(.rolling), .setGateReference],
                                       [.beginAccumulation], [.updateReference(.rolling), .setGateReference]])
        #expect(log.count == 4 && abs(log[0].frame - (enteredAt + 300)) <= 1 && log[1].frame == log[0].frame + 4)
        #expect(log.count == 4 && abs(log[2].frame - (log[1].frame + 300)) <= 1 && log[3].frame == log[2].frame + 4)
        #expect(h.state == .watching(dartsOnBoard: 0))
    }

    @Test func row10_refreshIsAbandonedByMotion_andNeverRunsOutsideWatching() {
        var h = H()
        h.start()
        for _ in 0..<302 { h.sample(motion: 0.0001) }
        // The refresh is accumulating; a frame that is not quiet drops it, a later one starts it again.
        #expect(h.sample(motion: 0.0008) == [.discardAccumulation])
        #expect(h.sample(motion: 0.0001) == [.beginAccumulation])
        // A start of motion drops it too (row 4).
        #expect(h.moving(1)[0] == [.discardAccumulation, .emit(.stateChanged(.motion))])

        // awaitingTakeout: no refresh.
        var full = H()
        full.start()
        full.command(.beginVisit(expectedDarts: 1))
        full.throwDart(H.observation(1))
        #expect(full.state == .awaitingTakeout)
        var effects: [ScanEffect] = []
        for _ in 0..<700 { effects += full.sample(motion: 0.0001) }
        #expect(effects.isEmpty && full.state == .awaitingTakeout)
    }
}
