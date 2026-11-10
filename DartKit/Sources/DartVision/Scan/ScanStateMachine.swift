import Foundation
import simd
import CoreGraphics
import CoreVideo
import DartCore

/// Pure reducer: `(state, input) -> (state, effects)`. No clock, no I/O; time arrives in the inputs.
///
/// Contract with the engine that drives it (VISION.md §6):
///
/// **Inputs.**
/// - `.calibrationSet`: a calibration was installed (row 1).
/// - `.gate(sample)`: one per frame while the gate runs. The reducer ignores samples in `needsCalibration`, `idle`,
///   `analysing`, `paused`, and at rest in manual trigger. "Quiet" is `motionFraction < quietFraction`, "moving" is
///   `motionFraction > motionOnFraction`. All timers read `sample.timestamp`.
/// - `.settle(outcome, timestamp:)`: the answer to `.analyse`. Accepted in `analysing` only.
/// - `.calibrationHealth(status, recovered:, timestamp:)`: the answer to `.checkCalibration` (rows K1 to K5, A13).
///   `recovered` is true when a new calibration was adopted (the engine emits `calibrationAdjusted` or
///   `calibrationRecovered` itself, just before this input). Two consecutive answers that are neither `healthy`
///   nor `recovered` (`lost`, or `drifted` without a recovery) lose the calibration (K2); `edgesNotVisible` neither
///   counts nor breaks the run (K5). Every check runs on the current frame before any frame of `S` is accumulated:
///   at row 5, at a capture pose, and after two still seconds of an obstruction (A13), whose verdict then asks
///   for the four frames of `S`.
/// - `.armed`: the engine states that the arming pose is complete; in `arming` it ends the arming exactly like the
///   last quiet sample would. Ignored elsewhere. The reducer counts the quiet samples itself, so an engine never
///   needs to send it.
/// - `.command`: a `ScanCommand` (§6.5).
///
/// **Effects**, in the order of the returned list:
/// 1. `.discardAccumulation` when an episode, a capture or an accumulation is abandoned;
/// 2. `.emit(.stateChanged)` when `state` changed, then the other events in the order of the transition tables;
/// 3. `.updateReference`, `.setGateReference`, `.beginAccumulation`;
/// 4. at most one request, which the engine answers with an input: `.checkCalibration` or `.analyse`;
/// 5. `.emit(.scanCompleted)`, always last.
///
/// `.beginAccumulation` means "reset the accumulator and add every frame from the NEXT one". The frames added
/// until the reference update or the analysis are the settled image `S`: quiet frames 3 to 6 of a pose, the last
/// four frames of an arming. `.updateReference(.rolling)` and `.rollingAndEmpty` read that `S`. When `state`
/// leaves `arming` for a still state the accumulator holds the last arming frames: that is when the engine
/// measures the noise. No effect clears the references: the engine clears references and silhouettes itself on
/// `.calibrationSet`, and on an `.arm` after which `state` is `arming` or `calibrationLost` (an `.arm` without a
/// calibration is ignored); the empty reference is then unknown until an `.updateReference(.rollingAndEmpty)`
/// (row 3 with `boardConfirmedEmpty`, A7, A14 with `n = 0`, P3, DM2) takes it. A silhouette is
/// memorised for every observation the reducer emits (`dart`, `scanCompleted`), and forgotten on `dartRemoved`,
/// on `.discardDart` and on every update that clears them (`.rollingAndEmpty`, `.rollingFromEmpty`).
///
/// Observations are built by the engine with `visit`, `dartsInVisit` and `isBeyondVisitLimit(newDartOffset:)`
/// read BEFORE the settle input. The reducer never changes what an observation says (id, hit candidates,
/// confidence, tier); it only guarantees the two flags of rows A3 and A4 (`beyondVisitLimit`,
/// `earlierDartDisturbed`) on the darts it emits.
public struct ScanStateMachine: Sendable {
    public init(parameters: ScanParameters = .init()) {
        self.parameters = parameters
        self.currentTrigger = parameters.trigger
        self.expectedDarts = max(0, parameters.expectedDartsPerVisit)
    }

    public var state: ScanState {
        switch phase {
        case .needsCalibration: return .needsCalibration
        case .idle: return .idle
        case .arming: return .arming
        case .rest(.watching): return .watching(dartsOnBoard: known.count)
        case .rest(.awaitingTakeout): return .awaitingTakeout
        case .rest(.takeout): return .takeout
        case .motion: return .motion
        case .settling: return .settling
        case .analysing: return .analysing
        case .obstructed: return .obstructed
        case .calibrationLost: return .calibrationLost
        case .paused(let reason): return .paused(reason)
        }
    }

    /// Current trigger: `parameters.trigger` at first, then the last `.setTrigger`.
    public var trigger: ScanTrigger { currentTrigger }
    /// Darts physically on the board (committed silhouettes).
    public var dartsOnBoard: Int { known.count }
    public var visit: Int { visitCounter }
    public var dartsInVisit: Int { visitDarts }
    public var lastEpisode: EpisodeSummary? { episodeSummary }

    public mutating func handle(_ input: ScanInput) -> [ScanEffect] {
        let before = state
        var out = Output()
        switch input {
        case .calibrationSet:
            calibrationWasSet(&out)
        case .gate(let sample):
            gate(sample, &out)
        case .armed:
            if phase == .arming { completeArming(at: nil, &out) }
        case .settle(let outcome, let timestamp):
            settle(outcome, at: timestamp, &out)
        case .calibrationHealth(let status, let recovered, let timestamp):
            health(status, recovered: recovered, at: timestamp, &out)
        case .command(let command):
            self.command(command, &out)
        }
        return out.effects(stateBefore: before, stateAfter: state)
    }

    // MARK: - Helpers for the engine (not part of the printed contract)

    /// True when the visit accepts no more darts: it was closed by `.endVisit`, or it already has its expected darts.
    var isVisitFullOrClosed: Bool { visitClosed || visitDarts >= expectedDarts }

    /// Whether the new dart number `newDartOffset` (0-based) of the settle being analysed lands beyond the visit
    /// limit and must carry `beyondVisitLimit` (rows A3 and DM3a). Read before feeding the `.settle` input; the
    /// reducer applies this same rule to the darts it emits.
    func isBeyondVisitLimit(newDartOffset: Int) -> Bool {
        visitClosed || newDartOffset >= expectedDarts - visitDarts
    }

    // MARK: - Internal vocabulary

    /// The three still states a transition can come back to. `obstructed` is never one of them: what the machine
    /// returns to after an obstruction is the still state it had left.
    enum Rest: Hashable, Sendable { case watching, awaitingTakeout, takeout }

    enum Phase: Hashable, Sendable {
        case needsCalibration, idle, arming
        case rest(Rest)
        case motion, settling, analysing, obstructed, calibrationLost
        case paused(PauseReason)
    }

    /// Which row opened the arming, hence how it ends.
    enum ArmingPurpose: Hashable, Sendable {
        /// Row 3.
        case start(boardConfirmedEmpty: Bool)
        /// Row P3.
        case confirmEmpty
        /// Rows P2 and DM8 (automatic trigger at the end of the arming: compare with `R`) and DM7 (manual: no comparison).
        case resume(returnTo: Rest)
        /// Row K4.
        case recovery(returnTo: Rest)

        func mapping(_ transform: (Rest) -> Rest) -> ArmingPurpose {
            switch self {
            case .start, .confirmEmpty: return self
            case .resume(let rest): return .resume(returnTo: transform(rest))
            case .recovery(let rest): return .recovery(returnTo: transform(rest))
            }
        }
    }

    /// The "previous state" of §6.3, kept across a pause or a calibration loss.
    enum Anchor: Hashable, Sendable {
        case needsCalibration
        case idle(needsEmptyBoard: Bool)
        case arming(ArmingPurpose)
        case rest(Rest)
        case calibrationLost

        func mapping(_ transform: (Rest) -> Rest) -> Anchor {
            switch self {
            case .needsCalibration, .idle, .calibrationLost: return self
            case .arming(let purpose): return .arming(purpose.mapping(transform))
            case .rest(let rest): return .rest(transform(rest))
            }
        }
    }

    /// What the pose of an automatic episode is for (§6.5: `confirmBoardEmpty` and `rebaseline` reuse it).
    enum SettleIntent: Hashable, Sendable { case analyse, rebaseline, takeEmpty }

    enum CaptureKind: Hashable, Sendable {
        case reference, rebaseline
        case scan(maxDarts: Int)
    }

    /// A capture pose of the manual trigger (rows DM2, DM3, DM5, DM6).
    struct Capture: Hashable, Sendable {
        var kind: CaptureKind
        /// Timestamp of the first sample received for this capture; `captureTimeout` runs from it.
        var firstSample: TimeInterval?
    }

    enum EpisodeKind: Hashable, Sendable {
        case throwLike, handLike
        /// No motion episode: idle check (row 9) or a pose forced by a command.
        case none
    }

    /// Why the machine is in `analysing`, hence which table reads the outcome.
    enum Analysis: Hashable, Sendable {
        case episode(EpisodeKind)
        case resume(returnTo: Rest)
        case scan(maxDarts: Int)
    }

    struct Episode: Hashable, Sendable {
        var start: TimeInterval
        /// First quiet frame of the current quiet run: the episode lasts from `start` to it.
        var quietRunStart: TimeInterval
        var peak: Double
        var borderRun: Int
        var borderMax: Int
        /// Started from `takeout` or `obstructed`, or timed out (row 8): always hand-like.
        var forcedHand: Bool
    }

    struct Committed: Hashable, Sendable {
        var id: UUID
        /// Value of the visit counter when the dart was committed.
        var visit: Int
    }

    enum EmptyReference: Hashable, Sendable { case unknown, fresh, stale }

    /// Drift check of a still obstruction (row A13). As at row 5 the check runs on one frame BEFORE any
    /// accumulation, so that the frames accumulated afterwards are rectified with the calibration it settled on.
    enum Probe: Hashable, Sendable {
        case idle
        /// `.checkCalibration` was requested; its answer is awaited.
        case awaitingHealth
        /// Healthy calibration: `n` quiet frames accumulated so far; four of them become `R`.
        case absorbing(Int)
    }

    /// Effects of one `handle` call, assembled in the documented order.
    struct Output {
        var discard = false
        var events: [ScanEvent] = []
        var work: [ScanEffect] = []
        var request: ScanEffect?
        var closing: ScanEvent?

        func effects(stateBefore: ScanState, stateAfter: ScanState) -> [ScanEffect] {
            var effects: [ScanEffect] = []
            if discard { effects.append(.discardAccumulation) }
            if stateAfter != stateBefore { effects.append(.emit(.stateChanged(stateAfter))) }
            effects.append(contentsOf: events.map { ScanEffect.emit($0) })
            effects.append(contentsOf: work)
            if let request { effects.append(request) }
            if let closing { effects.append(.emit(closing)) }
            return effects
        }
    }

    // MARK: - Stored state

    let parameters: ScanParameters
    var phase: Phase = .needsCalibration
    var currentTrigger: ScanTrigger

    // Counters.
    var known: [Committed] = []
    var visitCounter = 0
    var visitDarts = 0
    var expectedDarts: Int
    var visitClosed = false
    /// Camera darts counted in the current visit, on the board or not.
    var visitDartIDs: Set<UUID> = []
    /// A dart added by hand may be on the board without a silhouette: the empty reference is not retaken on a
    /// lighting change while this is set (§6.4: `E` is never taken with darts on the board).
    var unseenDartOnBoard = false
    var emptyReference: EmptyReference = .unknown
    var episodeSummary: EpisodeSummary?

    // idle
    var idleNeedsEmptyBoard = false

    // arming, motion, settling
    var armingPurpose: ArmingPurpose = .start(boardConfirmedEmpty: false)
    /// Consecutive quiet frames of the current arming, motion or pose.
    var quietCount = 0
    /// True between `.beginAccumulation` and the effect that reads or discards the accumulated frames.
    var accumulating = false
    /// Still state the episode, the pose or the capture started from.
    var origin: Rest = .watching
    /// The episode or the pose started from `obstructed`.
    var originObstructed = false
    var episode: Episode?
    var settleIntent: SettleIntent = .analyse
    /// How the outcome of a pose without an episode is read: `.none` for row 9 and the commands, `.handLike` for
    /// the new analysis of row A13 after a realignment. Set by every `forcePose`.
    var poseKind: EpisodeKind = .none
    var capture: Capture?
    var analysis: Analysis = .episode(.none)

    // still states
    var stillSince: TimeInterval?
    var lastIdleCheck: TimeInterval?
    var lastRefresh: TimeInterval?
    /// Quiet frames accumulated by the silent refresh of row 10, nil when none is running.
    var refreshCount: Int?

    // obstructed
    var obstructionOrigin: Rest = .watching
    /// Entered by row 8: motion is still running, the machine waits for it to calm down.
    var obstructionMoving = false
    var obstructedSince: TimeInterval?
    var escalationAnchor: TimeInterval?
    var obstructionAdvised = false
    var probe: Probe = .idle

    // calibration
    var lostStreak = 0
    var lostReturn: Anchor = .rest(.watching)
    /// `boardConfirmedEmpty` of an `.arm` received in `calibrationLost`.
    var armedWhileLost: Bool?
    var relockQuietSince: TimeInterval?

    // pause
    var pausedFrom: Anchor = .needsCalibration

    // MARK: - Derived constants

    /// Frame counts are read through these bounds, so that no value of `ScanParameters` can trap or overflow.
    private static let frameCountLimit = 100_000

    /// Quiet frames before a pose starts accumulating (2).
    var settleStart: Int { min(max(1, parameters.skipFrames), Self.frameCountLimit) }
    /// Quiet frames that complete a pose (6): always at least one accumulated frame.
    var settleTarget: Int { max(min(parameters.settleFrames, Self.frameCountLimit), settleStart + 1) }
    /// Frames averaged into a settled image (4).
    var accumulationFrames: Int { settleTarget - settleStart }
    var armingTarget: Int { min(max(1, parameters.armingFrames), Self.frameCountLimit) }
    /// Quiet frames of an arming after which the accumulation starts (8).
    var armingBegin: Int { max(0, armingTarget - accumulationFrames) }

    // MARK: - Small helpers

    func isQuiet(_ sample: GateSample) -> Bool { sample.motionFraction < parameters.quietFraction }
    func isMoving(_ sample: GateSample) -> Bool { sample.motionFraction > parameters.motionOnFraction }
    func hasNoLastingChange(_ sample: GateSample) -> Bool { sample.changeVsReference < parameters.noLastingChangeFraction }

    /// Rest state decided by the counters alone: the rule of the manual trigger (§6.3, "Repos").
    var countersRest: Rest { isVisitFullOrClosed ? .awaitingTakeout : .watching }

    /// A `captureNow` was accepted and its `scanCompleted` is still owed.
    var scanIsPending: Bool {
        if phase == .settling, case .scan? = capture?.kind { return true }
        if phase == .analysing, case .scan = analysis { return true }
        return false
    }

    mutating func begin(_ out: inout Output) {
        accumulating = true
        out.work.append(.beginAccumulation)
    }

    mutating func discard(_ out: inout Output) {
        accumulating = false
        out.discard = true
    }

    /// Enters a still state at `time` (nil when unknown: the first gate sample anchors the timers).
    /// In manual trigger the rest state is always the one the counters give.
    mutating func enterRest(_ rest: Rest, at time: TimeInterval?) {
        phase = .rest(currentTrigger == .manual ? countersRest : rest)
        accumulating = false
        episode = nil
        capture = nil
        settleIntent = .analyse
        quietCount = 0
        refreshCount = nil
        probe = .idle
        obstructionMoving = false
        stillSince = time
        lastIdleCheck = time
        lastRefresh = time
    }

    mutating func startArming(_ purpose: ArmingPurpose, _ out: inout Output) {
        if accumulating { discard(&out) }
        phase = .arming
        armingPurpose = purpose
        quietCount = 0
        episode = nil
        capture = nil
        refreshCount = nil
        probe = .idle
        obstructionMoving = false
        if armingBegin == 0 { begin(&out) }
    }

    /// What an interruption (pause, calibration loss) must come back to.
    var interruptionAnchor: Anchor {
        switch phase {
        case .needsCalibration: return .needsCalibration
        case .idle: return .idle(needsEmptyBoard: idleNeedsEmptyBoard)
        case .arming: return .arming(armingPurpose)
        case .rest(let rest): return .rest(rest)
        case .obstructed: return .rest(obstructionOrigin)
        case .motion, .settling: return .rest(origin)
        case .analysing:
            if case .resume(let rest) = analysis { return .arming(.resume(returnTo: rest)) }
            return .rest(origin)
        case .calibrationLost: return .calibrationLost
        case .paused: return pausedFrom
        }
    }

    /// Abandons the episode, the pose, the capture or the accumulation in progress.
    mutating func abandon(_ out: inout Output) {
        switch phase {
        case .motion, .settling, .analysing: discard(&out)
        default: if accumulating { discard(&out) }
        }
        episode = nil
        capture = nil
        settleIntent = .analyse
        quietCount = 0
        refreshCount = nil
        probe = .idle
        obstructionMoving = false
    }

    /// Applies `transform` to every remembered still state, so that a counter command received during an episode,
    /// an arming, a pause or a calibration loss is honoured when the machine comes back.
    mutating func mapRests(_ transform: (Rest) -> Rest) {
        if case .rest(let rest) = phase {
            phase = .rest(currentTrigger == .manual ? countersRest : transform(rest))
        }
        origin = transform(origin)
        obstructionOrigin = transform(obstructionOrigin)
        armingPurpose = armingPurpose.mapping(transform)
        pausedFrom = pausedFrom.mapping(transform)
        lostReturn = lostReturn.mapping(transform)
        if case .resume(let rest) = analysis { analysis = .resume(returnTo: transform(rest)) }
    }
}
