import Foundation
import Testing
import DartCore
import DartVision

/// Outcomes of an analysis in automatic trigger (VISION.md §6.3, rows A1 to A16): tests S5 to S8, S10 and S19.
@Suite struct ReducerOutcomeTests {
    private typealias H = ReducerHarness

    /// `watching(count)` in visit 1, with darts 1...count on the board.
    private func board(darts count: Int, expected: Int = 3) -> H {
        var h = H()
        h.start()
        h.command(.beginVisit(expectedDarts: expected))
        for number in 0..<count { h.throwDart(H.observation(number + 1)) }
        return h
    }

    // MARK: S5, S6: takeout (A7, A8, A9)

    @Test func s5_handEpisode_everythingRemoved_takeoutCompleted() {
        var h = board(darts: 3)
        #expect(h.state == .awaitingTakeout)
        h.handEpisode()
        let effects = h.settle(.removed([H.id(1), H.id(2), H.id(3)], boardEmpty: true))
        // A7: rolling and empty references retaken, drift check requested last.
        #expect(effects == [.emit(.stateChanged(.watching(dartsOnBoard: 0))),
                            .emit(.dartRemoved(id: H.id(1), reason: .takeout)),
                            .emit(.dartRemoved(id: H.id(2), reason: .takeout)),
                            .emit(.dartRemoved(id: H.id(3), reason: .takeout)),
                            .emit(.takeoutCompleted),
                            .updateReference(.rollingAndEmpty), .setGateReference, .checkCalibration])
        #expect(h.state == .watching(dartsOnBoard: 0) && h.machine.dartsOnBoard == 0)
        // The darts stay counted in the visit: vision never closes a turn.
        #expect(h.machine.dartsInVisit == 3 && h.machine.visit == 1)
    }

    @Test func s6_partialTakeout_thenFiveStillSeconds_takeoutStartedOnce_thenStalled() {
        var h = board(darts: 3)
        var events: [ScanEvent] = []
        // A8: one dart pulled.
        h.handEpisode()
        let first = h.settle(.removed([H.id(2)], boardEmpty: false))
        #expect(first == [.emit(.stateChanged(.takeout)), .emit(.takeoutStarted),
                          .emit(.dartRemoved(id: H.id(2), reason: .takeout)), .updateReference(.rolling), .setGateReference])
        events += H.events(first)
        // A8 again, from `takeout`: an episode started there is hand-like whatever its length; no second `takeoutStarted`.
        h.episode(movingFrames: 3)
        let second = h.settle(.removed([H.id(1)], boardEmpty: false))
        #expect(H.events(second) == [.stateChanged(.takeout), .dartRemoved(id: H.id(1), reason: .takeout)])
        events += H.events(second)
        #expect(h.state == .takeout && h.machine.dartsOnBoard == 1)
        // A9: five still seconds.
        let enteredAt = h.frame - 1
        var stalledAt: Int?
        var stalled: [ScanEffect] = []
        for _ in 0..<160 where stalledAt == nil {
            let effects = h.sample(motion: 0.0001)
            if !effects.isEmpty {
                stalledAt = h.frame - 1
                stalled = effects
            }
        }
        #expect(stalled == [.emit(.stateChanged(.awaitingTakeout)), .emit(.takeoutStalled(remaining: [H.id(3)]))])
        #expect(stalledAt.map { abs($0 - (enteredAt + 150)) <= 1 } == true)
        events += H.events(stalled)
        #expect(events.filter { $0 == .takeoutStarted }.count == 1)
        #expect(h.state == .awaitingTakeout)
        // Nothing more while the board stays still.
        #expect(h.quiet(200).flatMap { $0 }.isEmpty)
    }

    @Test func a9_motionRestartsTheStallTimer_andAStallEndsTheTakeout() {
        var h = board(darts: 3)
        h.handEpisode()
        h.settle(.removed([H.id(1)], boardEmpty: false))
        h.quiet(120)
        // A hand comes back after 4 s and takes nothing: back to `takeout`, the five seconds start again.
        h.handEpisode()
        #expect(h.settle(.noChange) == [.emit(.stateChanged(.takeout))])
        #expect(h.quiet(140).flatMap { $0 }.isEmpty && h.state == .takeout)
        #expect(H.facts(h.quiet(15).flatMap { $0 }) == [.takeoutStalled(remaining: [H.id(2), H.id(3)])])
        // After the stall, a new partial takeout announces itself again.
        h.handEpisode()
        #expect(H.facts(h.settle(.removed([H.id(2)], boardEmpty: false)))
                == [.takeoutStarted, .dartRemoved(id: H.id(2), reason: .takeout)])
        // And the last dart completes it (A7 from `takeout`).
        h.episode()
        #expect(H.facts(h.settle(.removed([H.id(3)], boardEmpty: true)))
                == [.dartRemoved(id: H.id(3), reason: .takeout), .takeoutCompleted])
    }

    // MARK: S7, S19: fallen dart before takeout (A10)

    @Test func s7_twoKnownDarts_oneDisappearsAfterThrowLikeEpisode_fellOut() {
        var h = board(darts: 2)
        h.episode()
        let effects = h.settle(.removed([H.id(1)], boardEmpty: false))
        #expect(effects == [.emit(.stateChanged(.watching(dartsOnBoard: 1))),
                            .emit(.dartRemoved(id: H.id(1), reason: .fellOut)), .updateReference(.rolling), .setGateReference])
        #expect(h.state == .watching(dartsOnBoard: 1))
        // A fallen dart is not cancelled by vision: it stays counted in the visit.
        #expect(h.machine.dartsInVisit == 2)
    }

    @Test func s19_onlyDartFallsOut_thenSameOutcomeFromTakeout() {
        // First case: one known dart, 0.2 s episode, the board ends up empty: A10 before A7.
        var h = board(darts: 1)
        h.moving(6)
        h.quiet(6, change: H.dartChange)
        let fell = h.settle(.removed([H.id(1)], boardEmpty: true))
        #expect(fell == [.emit(.stateChanged(.watching(dartsOnBoard: 0))), .emit(.dartRemoved(id: H.id(1), reason: .fellOut)),
                         .updateReference(.rolling), .setGateReference])
        #expect(!fell.contains(.emit(.takeoutCompleted)) && !fell.contains(.updateReference(.rollingAndEmpty)))
        #expect(h.state == .watching(dartsOnBoard: 0))

        // Second case: the same outcome after a 0.2 s episode that started from `takeout`: A7.
        var t = board(darts: 2)
        t.handEpisode()
        t.settle(.removed([H.id(1)], boardEmpty: false))
        #expect(t.state == .takeout)
        t.moving(6)
        t.quiet(6, change: H.dartChange)
        #expect(t.machine.lastEpisode?.isHandLike(ScanParameters()) == false)
        let pulled = t.settle(.removed([H.id(2)], boardEmpty: true))
        #expect(pulled == [.emit(.stateChanged(.watching(dartsOnBoard: 0))),
                           .emit(.dartRemoved(id: H.id(2), reason: .takeout)), .emit(.takeoutCompleted),
                           .updateReference(.rollingAndEmpty), .setGateReference, .checkCalibration])
    }

    @Test func a10_fromAwaitingTakeout_severalDartsFall() {
        var h = board(darts: 3)
        h.episode()
        let effects = h.settle(.removed([H.id(3), H.id(1)], boardEmpty: false))
        #expect(H.events(effects) == [.stateChanged(.watching(dartsOnBoard: 1)),
                                      .dartRemoved(id: H.id(3), reason: .fellOut),
                                      .dartRemoved(id: H.id(1), reason: .fellOut)])
        // The visit is still full: the next dart is beyond its limit (A3).
        let late = h.throwDart(H.observation(4))
        #expect(late.contains(.emit(.dart(H.observation(H.observation(4), flags: .beyondVisitLimit)))))
        #expect(h.state == .awaitingTakeout)
    }

    // MARK: S8: darts beyond the visit (A3)

    @Test func s8_fourthDart_staysAwaitingTakeout_withBeyondVisitLimit() {
        var h = board(darts: 3)
        #expect(h.state == .awaitingTakeout)
        h.episode()
        let fourth = H.observation(4, tier: .medium, flags: [.clutter])
        let effects = h.settle(.darts(new: [fourth], removed: [], disturbed: []))
        // Back to `awaitingTakeout` after the episode; the dart carries the flag of row A3 and keeps its own.
        #expect(effects == [.emit(.stateChanged(.awaitingTakeout)),
                            .emit(.dart(H.observation(fourth, flags: [.clutter, .beyondVisitLimit]))),
                            .updateReference(.rolling), .setGateReference])
        #expect(h.state == .awaitingTakeout && h.machine.dartsOnBoard == 4 && h.machine.dartsInVisit == 4)
        // An observation that already carries the flag is passed through untouched.
        h.episode()
        let fifth = H.observation(5, flags: [.beyondVisitLimit])
        #expect(H.facts(h.settle(.darts(new: [fifth], removed: [], disturbed: []))) == [.dart(fifth)])
    }

    @Test func a3_dartAfterEndVisit_isBeyondTheLimit() {
        var h = board(darts: 1)
        h.command(.endVisit)
        #expect(h.state == .awaitingTakeout)
        let effects = h.throwDart(H.observation(2))
        #expect(H.events(effects) == [.stateChanged(.awaitingTakeout),
                                      .dart(H.observation(H.observation(2), flags: .beyondVisitLimit))])
        #expect(h.state == .awaitingTakeout)
    }

    // MARK: §7.4: a low-confidence dart waits for the player

    @Test func lowConfidenceDart_isPassedOnAsLow_once_andNothingEverAcceptsIt() {
        var h = board(darts: 0)
        let low = H.observation(1, tier: .low)
        // Passed on as it is (tier, confidence, candidates): the game layer holds it until the player answers.
        #expect(H.facts(h.throwDart(low)) == [.dart(low)])
        // Nothing the reducer receives afterwards sends it again or promotes it: a minute of still frames (idle
        // checks, refreshes), another dart, a takeout, a new visit, another half minute.
        var later: [ScanEffect] = []
        later += h.quiet(1800).flatMap { $0 }
        let second = H.observation(2, tier: .medium)
        later += h.throwDart(second)
        h.handEpisode()
        later += h.settle(.removed([H.id(1), H.id(2)], boardEmpty: true))
        later += h.command(.beginVisit(expectedDarts: 3))
        later += h.quiet(900).flatMap { $0 }
        let darts = H.events(later).compactMap { event -> DartObservation? in
            if case .dart(let observation) = event { return observation }
            return nil
        }
        #expect(darts == [second])
        #expect(!H.events(later).contains(.dart(low)))
    }

    // MARK: A4

    @Test func a4_newDartWithAnEarlierOneRemovedAndAnotherDisturbed() {
        var h = board(darts: 2)
        h.episode()
        let third = H.observation(3)
        let effects = h.settle(.darts(new: [third], removed: [H.id(1)], disturbed: [H.id(2)]))
        #expect(effects == [.emit(.stateChanged(.awaitingTakeout)),
                            .emit(.dartRemoved(id: H.id(1), reason: .fellOut)),
                            .emit(.dartDisturbed(id: H.id(2))),
                            .emit(.dart(H.observation(third, flags: .earlierDartDisturbed))),
                            .updateReference(.rolling), .setGateReference])
        #expect(h.machine.dartsOnBoard == 2 && h.machine.dartsInVisit == 3)
    }

    @Test func a4_unknownIdentifiersAndDuplicates_areIgnored() {
        var h = board(darts: 1)
        h.episode()
        let second = H.observation(2)
        // Identifiers the machine does not know, a known dart reported as new, and the same dart twice.
        let effects = h.settle(.darts(new: [second, H.observation(1), second], removed: [H.id(40), H.id(40)],
                                      disturbed: [H.id(41)]))
        #expect(H.events(effects) == [.stateChanged(.watching(dartsOnBoard: 2)), .dart(second)])
        #expect(h.machine.dartsOnBoard == 2 && h.machine.dartsInVisit == 2)
    }

    @Test func dartsOutcomeWithoutANewDart_isReadAsARemovalADisturbanceOrNoChange() {
        // Removed only: A10 after a throw-like episode.
        var h = board(darts: 2)
        h.episode()
        #expect(H.facts(h.settle(.darts(new: [], removed: [H.id(1)], disturbed: [])))
                == [.dartRemoved(id: H.id(1), reason: .fellOut)])
        // Disturbed only: reported and absorbed.
        h.episode()
        #expect(h.settle(.darts(new: [], removed: [], disturbed: [H.id(2)]))
                == [.emit(.stateChanged(.watching(dartsOnBoard: 1))), .emit(.dartDisturbed(id: H.id(2))),
                    .updateReference(.rolling), .setGateReference])
        // Nothing at all: A5.
        h.episode()
        #expect(H.facts(h.settle(.darts(new: [], removed: [], disturbed: []))) == [.possibleMiss(timestamp: h.now)])
    }

    // MARK: S10: lighting (A14)

    @Test func s10_lightingChange_emptyBoard_thenTwoDarts() {
        var h = board(darts: 0)
        h.handEpisode()
        // n = 0: the empty reference is retaken with the rolling one.
        #expect(h.settle(.lightingChanged) == [.emit(.stateChanged(.watching(dartsOnBoard: 0))), .emit(.lightingChanged),
                                               .updateReference(.rollingAndEmpty), .setGateReference])
        h.throwDart(H.observation(1))
        h.throwDart(H.observation(2))
        h.handEpisode()
        // n = 2: `R := S`, the empty reference is marked stale.
        #expect(h.settle(.lightingChanged) == [.emit(.stateChanged(.watching(dartsOnBoard: 2))), .emit(.lightingChanged),
                                               .updateReference(.rolling), .updateReference(.markEmptyStale),
                                               .setGateReference])
        #expect(h.machine.dartsOnBoard == 2 && h.machine.dartsInVisit == 2)
    }

    @Test func a14_aDartAddedByHandKeepsTheEmptyReferenceFromBeingRetaken() {
        // §6.4: `E` is never taken while darts are on the board, and a hand-entered dart is on the board unseen.
        var h = board(darts: 0)
        h.command(.registerManualDart)
        h.handEpisode()
        #expect(H.references(h.settle(.lightingChanged)) == [.updateReference(.rolling), .updateReference(.markEmptyStale)])
    }

    // MARK: A11 to A13: obstruction

    @Test func a11_obstruction_keepsTheReference_a12_thenReevaluates() {
        var h = board(darts: 1)
        h.handEpisode()
        // A11: no reference effect at all.
        #expect(h.settle(.obstruction) == [.emit(.stateChanged(.obstructed))])
        #expect(h.state == .obstructed && h.machine.dartsOnBoard == 1)
        // A12: the hand leaves; a short episode from `obstructed` is still hand-like, so "no change" is silent
        // and the machine returns to the still state it had before the obstruction.
        h.moving(3)
        #expect(h.state == .motion)
        h.quiet(6, change: H.dartChange)
        #expect(h.settle(.noChange) == [.emit(.stateChanged(.watching(dartsOnBoard: 1)))])
    }

    @Test func a12_gateBackOnItsReference_returnsWithoutAnalysis() {
        var h = board(darts: 1)
        h.handEpisode()
        h.settle(.obstruction)
        h.moving(3)
        // Row 7 from `obstructed`: the gate reference is still the one of the last pose.
        #expect(h.quiet(6, change: 0)[5] == [.discardAccumulation, .emit(.stateChanged(.watching(dartsOnBoard: 1)))])
    }

    @Test func a12_obstructionAgain_staysObstructed_andADartIsFoundAfterIt() {
        var h = board(darts: 1)
        h.handEpisode()
        h.settle(.obstruction)
        h.handEpisode()
        // Still obstructed: back to that state, and nothing else is emitted.
        #expect(h.settle(.obstruction) == [.emit(.stateChanged(.obstructed))] && h.state == .obstructed)
        h.episode()
        let second = H.observation(2)
        #expect(H.events(h.settle(.darts(new: [second], removed: [], disturbed: [])))
                == [.stateChanged(.watching(dartsOnBoard: 2)), .dart(second)])
    }

    /// Lets the obstruction stand still until the drift check is requested; returns the frames it took.
    private func waitForObstructionCheck(_ h: inout H) -> (frames: Int, log: [ScanEffect]) {
        var log: [ScanEffect] = []
        for frame in 1...80 {
            let effects = h.sample(motion: 0.0001, change: 0.2)
            log += effects
            if effects.contains(.checkCalibration) { return (frame, log) }
        }
        return (0, log)
    }

    @Test func a13_stillForTwoSeconds_healthyCalibration_unrecognizedChange_backToThePreviousState() {
        var h = board(darts: 3)
        h.handEpisode()
        h.settle(.obstruction)
        let wait = waitForObstructionCheck(&h)
        // Two still seconds, then the drift check on that frame (§4.9), before anything is accumulated.
        #expect(wait.log == [.checkCalibration])
        #expect(abs(wait.frames - 60) <= 1)
        // Healthy: the settled image is taken now, on four quiet frames; no event meanwhile.
        #expect(h.health(.healthy) == [.beginAccumulation] && h.state == .obstructed)
        let pose = h.quiet(4, change: 0.2)
        #expect(pose[0].isEmpty && pose[1].isEmpty && pose[2].isEmpty)
        #expect(pose[3] == [.emit(.stateChanged(.awaitingTakeout)), .emit(.unrecognizedChange), .updateReference(.rolling),
                            .setGateReference])
        // Silhouettes kept.
        #expect(h.machine.dartsOnBoard == 3)
    }

    @Test func a13_driftedAndRealigned_newPoseThenNewAnalysis() {
        var h = board(darts: 1)
        h.handEpisode()
        h.settle(.obstruction)
        _ = waitForObstructionCheck(&h)
        // Realigned: the new analysis runs on frames rectified with the new calibration, accumulated after it.
        #expect(h.health(.drifted, recovered: true) == [.emit(.stateChanged(.settling)), .beginAccumulation])
        let pose = h.quiet(4, change: 0.2)
        #expect(pose[0].isEmpty && pose[1].isEmpty && pose[2].isEmpty)
        #expect(pose[3] == [.emit(.stateChanged(.analysing)), .analyse(maxNewDarts: 1)])
        // Read as after a hand: the known dart was pulled.
        #expect(H.facts(h.settle(.removed([H.id(1)], boardEmpty: true)))
                == [.dartRemoved(id: H.id(1), reason: .takeout), .takeoutCompleted])
    }

    @Test func a13_driftedAndRealigned_noChange_isSilentLikeAfterAHand() {
        var h = board(darts: 1)
        h.handEpisode()
        h.settle(.obstruction)
        _ = waitForObstructionCheck(&h)
        h.health(.drifted, recovered: true)
        h.quiet(4, change: 0.2)
        // No `possibleMiss`: a hand was in view (A6).
        #expect(h.settle(.noChange) == [.emit(.stateChanged(.watching(dartsOnBoard: 1)))])
    }

    @Test func a13_edgesNotVisible_stays_andAdvisesAfterTenSeconds_once() {
        var h = board(darts: 1)
        h.handEpisode()
        h.settle(.obstruction)
        let obstructedAt = h.frame - 1
        var advisedAt: Int?
        var advisories = 0
        var checks = 0
        while h.frame - obstructedAt < 700 {
            let effects = h.sample(motion: 0.0001, change: 0.2)
            guard effects.contains(.checkCalibration) else { continue }
            checks += 1
            let verdict = h.health(.edgesNotVisible)
            #expect(H.work(verdict).isEmpty && h.state == .obstructed)
            if H.events(verdict) == [.advisory(.viewObstructed)] {
                advisories += 1
                if advisedAt == nil { advisedAt = h.frame - 1 }
            } else {
                #expect(H.events(verdict).isEmpty)
            }
        }
        // A check about every two seconds; the advisory once, at the first check after ten seconds.
        #expect(checks >= 9 && checks <= 11)
        #expect(advisories == 1)
        #expect(advisedAt.map { $0 - obstructedAt >= 300 && $0 - obstructedAt <= 330 } == true)
    }

    @Test func a13_aFrameThatIsNotQuietRestartsTheTwoSeconds_andMotionStartsAnEpisode() {
        var h = board(darts: 1)
        h.handEpisode()
        h.settle(.obstruction)
        _ = waitForObstructionCheck(&h)
        h.health(.healthy)
        h.quiet(2, change: 0.2)
        // The settled image is being accumulated: a restless frame drops it, and the two still seconds start again.
        #expect(h.sample(motion: 0.0008, change: 0.2) == [.discardAccumulation] && h.state == .obstructed)
        let wait = waitForObstructionCheck(&h)
        #expect(wait.log == [.checkCalibration] && abs(wait.frames - 60) <= 1)
        // A check that gets no answer is asked again two seconds later, without any other effect.
        #expect(waitForObstructionCheck(&h).log == [.checkCalibration])
        // Motion starts an episode from the state before the obstruction (A12).
        #expect(h.moving(1)[0] == [.discardAccumulation, .emit(.stateChanged(.motion))])
    }

    @Test func a13_lostChecks_countLikeLostPoses() {
        var h = board(darts: 1)
        h.handEpisode()
        h.settle(.obstruction)
        _ = waitForObstructionCheck(&h)
        // First lost check: the obstruction stays, nothing is said.
        #expect(h.health(.lost).isEmpty && h.state == .obstructed)
        _ = waitForObstructionCheck(&h)
        // Second one in a row (K2).
        #expect(h.health(.drifted) == [.emit(.stateChanged(.calibrationLost)), .emit(.calibrationLost)])
    }

    // MARK: A15, A16

    @Test func a15_foreignRemoval_absorbedWithoutAnyDartEvent() {
        var h = board(darts: 2)
        h.episode()
        #expect(h.settle(.foreignRemoval) == [.emit(.stateChanged(.watching(dartsOnBoard: 2))), .updateReference(.rolling),
                                              .setGateReference])
        // The removal of something that is not a known dart is read the same way.
        h.handEpisode()
        #expect(h.settle(.removed([H.id(77)], boardEmpty: false))
                == [.emit(.stateChanged(.watching(dartsOnBoard: 2))), .updateReference(.rolling), .setGateReference])
        #expect(h.machine.dartsOnBoard == 2 && h.machine.dartsInVisit == 2)
    }

    @Test func a16_unrecognizedChange_reportedAndAbsorbed() {
        var h = board(darts: 3)
        h.handEpisode()
        // Back to the previous state: here `awaitingTakeout`, so no `stateChanged(watching)`.
        #expect(h.settle(.unrecognized) == [.emit(.stateChanged(.awaitingTakeout)), .emit(.unrecognizedChange),
                                            .updateReference(.rolling), .setGateReference])
    }

    // MARK: A7 and A8 details

    @Test func a8_fromWatching_goesToTakeout_andA7NeedsTheEngineToSeeAnEmptyBoard() {
        var h = board(darts: 2)
        h.handEpisode()
        #expect(H.events(h.settle(.removed([H.id(2)], boardEmpty: false)))
                == [.stateChanged(.takeout), .takeoutStarted, .dartRemoved(id: H.id(2), reason: .takeout)])
        // The last known dart goes but the engine still sees something on the board: no empty reference.
        h.handEpisode()
        #expect(h.settle(.removed([H.id(1)], boardEmpty: false))
                == [.emit(.stateChanged(.watching(dartsOnBoard: 0))), .emit(.dartRemoved(id: H.id(1), reason: .takeout)),
                    .updateReference(.rolling), .setGateReference])
    }

    @Test func a7_boardEmptyIsAuthoritative_everyKnownDartIsRemoved() {
        var h = board(darts: 3)
        h.handEpisode()
        // The engine lists one dart but states the board is empty: its silhouettes are cleared, so are ours.
        let effects = h.settle(.removed([H.id(2)], boardEmpty: true))
        #expect(H.events(effects) == [.stateChanged(.watching(dartsOnBoard: 0)),
                                      .dartRemoved(id: H.id(2), reason: .takeout),
                                      .dartRemoved(id: H.id(1), reason: .takeout),
                                      .dartRemoved(id: H.id(3), reason: .takeout), .takeoutCompleted])
        #expect(h.machine.dartsOnBoard == 0)
    }

    @Test func settleInput_outsideAnalysing_isIgnored() {
        var h = board(darts: 1)
        let dart = H.observation(9)
        for outcome: SettleOutcome in [.noChange, .darts(new: [dart], removed: [], disturbed: []),
                                        .removed([H.id(1)], boardEmpty: true), .obstruction, .lightingChanged,
                                        .foreignRemoval, .unrecognized] {
            #expect(h.settle(outcome).isEmpty)
        }
        #expect(h.state == .watching(dartsOnBoard: 1))
        h.moving(2)
        #expect(h.settle(.removed([H.id(1)], boardEmpty: true)).isEmpty && h.state == .motion)
        h.quiet(3)
        #expect(h.settle(.unrecognized).isEmpty && h.state == .settling)
    }
}
