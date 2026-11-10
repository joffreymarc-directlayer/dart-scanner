import Foundation
import simd
import Testing
import DartCore
import DartVision

/// Adversarial review of lot V4: rows that the model-based test does not reach (the idle check of row 9 and the
/// rules that hang on it), each written from VISION.md §4.9 and §6.3.
@Suite struct ReducerReviewTests {
    private typealias H = ReducerHarness

    private static func requests(_ effects: [ScanEffect]) -> Int {
        effects.filter { $0 == .checkCalibration }.count
    }

    /// Two still seconds with the gate away from its reference: the idle check of row 9 forces a pose.
    private static func idleCheckPose(_ h: inout H) -> [ScanEffect] {
        var effects: [ScanEffect] = []
        for _ in 0..<61 { effects += h.quiet(1, change: H.dartChange).flatMap { $0 } }
        // Four quiet frames are accumulated, then the analysis is asked for.
        for _ in 0..<4 { effects += h.quiet(1, change: H.dartChange).flatMap { $0 } }
        return effects
    }

    @Test func a14_aNewEmptyReferenceFromTheIdleCheck_isCheckedForDrift() {
        // VISION.md §4.9: the drift check runs "à chaque nouvelle référence vide". After an episode it ran on the
        // pose itself (row 5); a lighting change found by the idle check of row 9 had no episode, hence no check.
        var h = H()
        h.start()
        #expect(h.state == .watching(dartsOnBoard: 0))
        let pose = Self.idleCheckPose(&h)
        #expect(H.analyses(pose) == [.analyse(maxNewDarts: 1)])
        #expect(Self.requests(pose) == 0)
        let effects = h.settle(.lightingChanged)
        #expect(H.facts(effects) == [.lightingChanged])
        #expect(H.references(effects) == [.updateReference(.rollingAndEmpty)])
        #expect(Self.requests(effects) == 1, "a new empty reference without any drift check: \(effects)")
        #expect(h.state == .watching(dartsOnBoard: 0))
        // The check counts like a pose (K2).
        h.health(.lost)
        #expect(h.state == .watching(dartsOnBoard: 0))
    }

    @Test func a14_afterAnEpisode_theCheckOfRow5IsTheOnlyOne() {
        var h = H()
        h.start()
        h.moving(3)
        let checks = h.quiet(6, change: H.dartChange).flatMap { $0 }
        #expect(Self.requests(checks) == 1)
        let effects = h.settle(.lightingChanged)
        #expect(H.references(effects) == [.updateReference(.rollingAndEmpty)])
        #expect(Self.requests(effects) == 0)
    }

    @Test func a14_withDartsOnTheBoard_theEmptyReferenceIsStale_andNothingIsChecked() {
        var h = H()
        h.start()
        h.throwDart(H.observation(1))
        h.send(.calibrationHealth(.healthy, recovered: false, timestamp: h.now))
        _ = Self.idleCheckPose(&h)
        let effects = h.settle(.lightingChanged)
        #expect(H.references(effects) == [.updateReference(.rolling), .updateReference(.markEmptyStale)])
        #expect(Self.requests(effects) == 0)
        #expect(h.state == .watching(dartsOnBoard: 1))
    }

    @Test func a7_fromTheIdleCheck_takesTheEmptyReferenceAndChecksIt() {
        var h = H()
        h.start()
        h.throwDart(H.observation(1))
        _ = Self.idleCheckPose(&h)
        let effects = h.settle(.removed([H.id(1)], boardEmpty: true))
        // Row 9 counts as a hand (A7 and A8 "au contrôle au repos").
        #expect(H.facts(effects) == [.dartRemoved(id: H.id(1), reason: .takeout), .takeoutCompleted])
        #expect(H.references(effects) == [.updateReference(.rollingAndEmpty)])
        #expect(Self.requests(effects) == 1)
        #expect(h.state == .watching(dartsOnBoard: 0))
    }

    @Test func lowConfidenceDarts_reachTheGameOnce_withTheirTier_inBothTriggers() {
        // The reducer never decides for the player (§7.4): a low dart is passed on as low, once.
        var h = H()
        h.start()
        let low = H.observation(7, tier: .low)
        let first = h.throwDart(low)
        #expect(H.facts(first) == [.dart(low)])
        var later: [ScanEvent] = []
        later += H.facts(h.command(.endVisit))
        later += H.facts(h.command(.beginVisit(expectedDarts: 3)))
        h.handEpisode()
        later += H.facts(h.settle(.darts(new: [low], removed: [], disturbed: [])))
        #expect(!later.contains { if case .dart = $0 { return true } else { return false } })

        var manual = H()
        manual.start(trigger: .manual)
        let lowScan = H.observation(8, tier: .low)
        manual.command(.captureNow(maxDarts: 3))
        manual.quiet(6, change: H.dartChange)
        let scan = manual.settle(.darts(new: [lowScan, lowScan], removed: [], disturbed: []))
        #expect(H.facts(scan) == [.scanCompleted([lowScan])])
    }
}
