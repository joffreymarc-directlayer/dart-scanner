import Foundation
import Testing
import DartCore
import DartVision

/// Calibration rows of the reducer (VISION.md §6.3, K1 to K5): test S11.
@Suite struct ReducerCalibrationTests {
    private typealias H = ReducerHarness

    private func board(darts count: Int) -> H {
        var h = H()
        h.start()
        h.command(.beginVisit(expectedDarts: 3))
        for number in 0..<count { h.throwDart(H.observation(number + 1)) }
        return h
    }

    /// An episode up to the drift check of its second quiet frame (row 5), answered with `status`.
    private func poseCheck(_ h: inout H, _ status: CalibrationHealth.Status, recovered: Bool = false) -> [ScanEffect] {
        h.moving(3)
        let quiet = h.quiet(2, change: H.dartChange)
        #expect(quiet[1].last == .checkCalibration)
        return h.health(status, recovered: recovered)
    }

    /// Ends the episode opened by `poseCheck` with "no change".
    private func finishPose(_ h: inout H) {
        h.quiet(4, change: H.dartChange)
        h.settle(.noChange)
    }

    private func isCalibrationEvent(_ event: ScanEvent) -> Bool {
        switch event {
        case .calibrationAdjusted, .calibrationRecovered: return true
        default: return false
        }
    }

    @Test func s11_lostOnTwoPoses_thenRecovered_armingThenThePreviousState() {
        var h = board(darts: 1)
        var log: [ScanEffect] = []
        // First lost pose: nothing yet, the episode goes on.
        let first = poseCheck(&h, .lost)
        #expect(first.isEmpty && h.state == .settling)
        log += first
        finishPose(&h)
        #expect(h.state == .watching(dartsOnBoard: 1))
        // Second lost pose in a row (K2): state and event `calibrationLost`.
        let second = poseCheck(&h, .lost)
        #expect(second == [.discardAccumulation, .emit(.stateChanged(.calibrationLost)), .emit(.calibrationLost)])
        log += second
        #expect(h.state == .calibrationLost)
        // No dart event any more: frames and outcomes are ignored.
        log += h.quiet(10, change: H.dartChange).flatMap { $0 }
        log += h.moving(10).flatMap { $0 }
        log += h.settle(.darts(new: [H.observation(5)], removed: [], disturbed: []))
        #expect(h.state == .calibrationLost && h.machine.dartsOnBoard == 1)
        // K4: recovery reported by the engine.
        let recovered = h.health(.lost, recovered: true)
        #expect(recovered == [.emit(.stateChanged(.arming))])
        log += recovered
        let arming = h.quiet(12)
        #expect(arming[7] == [.beginAccumulation])
        // `R := S`; the empty reference is stale because a dart is on the board; back to the previous state.
        #expect(arming[11] == [.emit(.stateChanged(.watching(dartsOnBoard: 1))), .updateReference(.rolling),
                               .updateReference(.markEmptyStale), .setGateReference])
        log += arming.flatMap { $0 }
        // The two events that carry a calibration come from the engine, never from the reducer.
        #expect(!H.events(log).contains(where: isCalibrationEvent))
        #expect(H.events(log).filter { $0 == .calibrationLost }.count == 1)
        #expect(h.machine.dartsInVisit == 1 && h.machine.visit == 1)
    }

    @Test func k4_emptyBoard_keepsTheEmptyReference_andReturnsToAwaitingTakeout() {
        var h = board(darts: 0)
        _ = poseCheck(&h, .lost)
        finishPose(&h)
        _ = poseCheck(&h, .lost)
        h.health(.drifted, recovered: true)
        #expect(h.quiet(12)[11] == [.emit(.stateChanged(.watching(dartsOnBoard: 0))), .updateReference(.rolling),
                                    .setGateReference])

        var full = board(darts: 3)
        _ = poseCheck(&full, .lost)
        finishPose(&full)
        _ = poseCheck(&full, .lost)
        // A healthy assessment while lost is a recovery too.
        #expect(full.health(.healthy) == [.emit(.stateChanged(.arming))])
        #expect(H.events(full.quiet(12)[11]) == [.stateChanged(.awaitingTakeout)])
    }

    @Test func k1_k2_k5_onlyTwoConsecutiveLostPosesLoseTheCalibration() {
        // K1: drifted and realigned; the engine adopted the new calibration, the reducer has nothing to do.
        var h = board(darts: 1)
        #expect(poseCheck(&h, .drifted, recovered: true).isEmpty && h.state == .settling)
        finishPose(&h)
        // lost, healthy, lost: not consecutive.
        #expect(poseCheck(&h, .lost).isEmpty)
        finishPose(&h)
        #expect(poseCheck(&h, .healthy).isEmpty)
        finishPose(&h)
        #expect(poseCheck(&h, .lost).isEmpty)
        finishPose(&h)
        // lost, realigned, lost: not consecutive either.
        #expect(poseCheck(&h, .drifted, recovered: true).isEmpty)
        finishPose(&h)
        #expect(poseCheck(&h, .lost).isEmpty && h.state == .settling)
        finishPose(&h)
        // K5: edges that cannot be measured say nothing; the pose before and the pose after are both lost.
        #expect(poseCheck(&h, .edgesNotVisible).isEmpty && h.state == .settling)
        finishPose(&h)
        #expect(H.facts(poseCheck(&h, .lost)) == [.calibrationLost])
        #expect(h.state == .calibrationLost)
    }

    @Test func k2_driftedWithoutRecovery_countsAsLost_andLocatorRecoveryDoesNot() {
        var h = board(darts: 0)
        #expect(poseCheck(&h, .drifted).isEmpty)
        finishPose(&h)
        // `lost` with `recovered`: the automatic locator found the board again at once.
        #expect(poseCheck(&h, .lost, recovered: true).isEmpty)
        finishPose(&h)
        #expect(poseCheck(&h, .drifted).isEmpty)
        finishPose(&h)
        #expect(H.facts(poseCheck(&h, .drifted)) == [.calibrationLost])
    }

    @Test func k2_checkAtTheEndOfTheArming_countsAsAPose() {
        var h = H()
        h.start()
        // The check of row 3 answers `lost`, then the first episode too.
        #expect(h.health(.lost).isEmpty && h.state == .watching(dartsOnBoard: 0))
        #expect(poseCheck(&h, .lost) == [.discardAccumulation, .emit(.stateChanged(.calibrationLost)), .emit(.calibrationLost)])
    }

    @Test func k3_everyQuietSecond_asksForARecovery() {
        var h = board(darts: 1)
        _ = poseCheck(&h, .lost)
        finishPose(&h)
        _ = poseCheck(&h, .lost)
        var requests: [Int] = []
        let start = h.frame
        for _ in 0..<95 {
            if h.sample(motion: 0.0001) == [.checkCalibration] { requests.append(h.frame - 1 - start) }
        }
        // One second after the first quiet frame, then every second.
        #expect(requests.count == 3)
        #expect(requests.first.map { abs($0 - 30) <= 1 } == true)
        // Failed attempts change nothing.
        #expect(h.health(.lost).isEmpty && h.health(.edgesNotVisible).isEmpty && h.state == .calibrationLost)
        // Motion restarts the quiet second.
        h.quiet(20)
        #expect(h.moving(1)[0].isEmpty)
        #expect(h.quiet(29).flatMap { $0 }.isEmpty)
        #expect(h.quiet(3).flatMap { $0 } == [.checkCalibration])
    }

    @Test func armWhileLost_keepsBoardConfirmedEmpty_recoveryEndsLikeRow3() {
        var h = board(darts: 2)
        _ = poseCheck(&h, .lost)
        finishPose(&h)
        _ = poseCheck(&h, .lost)
        #expect(h.machine.dartsOnBoard == 2 && h.machine.visit == 1)
        // No state change, no event: counters, references and silhouettes are cleared.
        #expect(h.command(.arm(boardConfirmedEmpty: true)).isEmpty && h.state == .calibrationLost)
        #expect(h.machine.dartsOnBoard == 0 && h.machine.visit == 0 && h.machine.dartsInVisit == 0)
        h.health(.lost, recovered: true)
        #expect(h.state == .arming)
        #expect(h.quiet(12)[11] == [.emit(.stateChanged(.watching(dartsOnBoard: 0))), .updateReference(.rollingAndEmpty),
                                    .setGateReference, .checkCalibration])
    }

    @Test func k2_lostDuringAnArming_theRecoveryRestartsThatArming() {
        var h = H()
        h.start()
        // Unsolicited checks during an arming: the second lost one loses the calibration.
        h.command(.arm(boardConfirmedEmpty: true))
        h.quiet(9)
        #expect(h.health(.lost).isEmpty)
        #expect(h.health(.lost) == [.discardAccumulation, .emit(.stateChanged(.calibrationLost)), .emit(.calibrationLost)])
        h.health(.healthy)
        #expect(h.state == .arming)
        #expect(h.quiet(11).last == [] && h.state == .arming)
        #expect(h.quiet(1)[0].contains(.updateReference(.rollingAndEmpty)) && h.state == .watching(dartsOnBoard: 0))
    }

    @Test func k2_lostWhileObstructed_returnsToTheStateBeforeTheObstruction() {
        var h = board(darts: 1)
        h.handEpisode()
        h.settle(.obstruction)
        var lost: [ScanEffect] = []
        for _ in 0..<200 where h.state == .obstructed {
            if h.sample(motion: 0.0001, change: 0.2).contains(.checkCalibration) { lost = h.health(.lost) }
        }
        // The first lost check leaves the obstruction alone; the second one, two seconds later, loses the calibration.
        #expect(lost == [.emit(.stateChanged(.calibrationLost)), .emit(.calibrationLost)])
        h.health(.lost, recovered: true)
        #expect(H.events(h.quiet(12)[11]) == [.stateChanged(.watching(dartsOnBoard: 1))])
    }

    @Test func health_isIgnoredWithoutCalibration_inIdle_andInPause() {
        var h = H()
        #expect(h.health(.lost).isEmpty && h.health(.lost).isEmpty && h.state == .needsCalibration)
        h.send(.calibrationSet)
        #expect(h.health(.lost).isEmpty && h.health(.lost).isEmpty && h.state == .idle)
        h.start()
        h.command(.pause(.background))
        #expect(h.health(.lost).isEmpty && h.health(.lost).isEmpty && h.state == .paused(.background))
        // Nothing was counted meanwhile: one lost pose after the pause is still the first.
        h.command(.resume)
        h.quiet(12)
        h.settle(.noChange)
        #expect(poseCheck(&h, .lost).isEmpty && h.state == .settling)
    }

    @Test func counterCommands_whileLost_updateCountersOnly() {
        var h = board(darts: 3)
        _ = poseCheck(&h, .lost)
        finishPose(&h)
        _ = poseCheck(&h, .lost)
        // The state before the loss was `awaitingTakeout`; a new visit begins while the calibration is lost.
        #expect(h.command(.beginVisit(expectedDarts: 3)).isEmpty && h.state == .calibrationLost)
        #expect(h.machine.visit == 2 && h.machine.dartsInVisit == 0)
        h.health(.healthy)
        #expect(H.events(h.quiet(12)[11]) == [.stateChanged(.watching(dartsOnBoard: 3))])
    }
}
