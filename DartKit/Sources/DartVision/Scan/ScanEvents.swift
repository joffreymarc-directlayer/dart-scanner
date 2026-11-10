import Foundation
import simd
import CoreGraphics
import CoreVideo
import DartCore

public enum ScanTrigger: String, Codable, Sendable {
    /// Darts are detected as they land.
    case automatic
    /// Nothing is processed between capture commands (`.captureReference`, `.captureNow`): section 6.3, rows DM1 to DM8.
    case manual
}

/// Every constant of the motion gate and of the state machine (section 6).
public struct ScanParameters: Hashable, Codable, Sendable {
    /// Trigger of a new state machine; `.setTrigger` changes it afterwards.
    public var trigger: ScanTrigger = .automatic
    public var expectedDartsPerVisit: Int = 3
    // Gate
    public var gateLongSide: Int = 320
    public var gatePixelDeltaFloor: Double = 12
    public var gatePixelDeltaSigmas: Double = 5
    public var gateBorderBand: Int = 6
    public var motionOnFraction: Double = 0.0012
    public var quietFraction: Double = 0.0005
    public var noLastingChangeFraction: Double = 0.0004
    // Settle
    public var skipFrames: Int = 2
    public var settleFrames: Int = 6
    public var armingFrames: Int = 12
    // Episodes
    public var throwMaxDuration: TimeInterval = 0.6
    public var handBorderFraction: Double = 0.04
    public var handSustainFrames: Int = 5
    // Timers (seconds of frame time)
    public var idleCheckInterval: TimeInterval = 2
    public var idleRefreshInterval: TimeInterval = 10
    public var obstructionEscalation: TimeInterval = 2
    public var obstructionAdvisoryDelay: TimeInterval = 10
    public var motionTimeout: TimeInterval = 8
    public var takeoutStallInterval: TimeInterval = 5
    public var relockRetryInterval: TimeInterval = 1
    /// Manual trigger: a capture that has not settled after this long is abandoned (row DM6).
    public var captureTimeout: TimeInterval = 2
    // Optional layers
    public var enableDriftCorrection: Bool = true
    public var relockCameraShiftLimit: Double = 30
    public var absoluteMatchRadius: Double = 8
    public init() {}
}

/// Per-frame measurements on the gate image (section 6.1).
public struct GateSample: Hashable, Sendable {
    public var timestamp: TimeInterval
    /// Fraction of gate pixels changed against the previous frame.
    public var motionFraction: Double
    /// Fraction changed against the gate image stored at the last settle.
    public var changeVsReference: Double
    /// Same, restricted to the band along the border of the gate region.
    public var borderChange: Double
    public var meanLuma: Double
    public init(timestamp: TimeInterval, motionFraction: Double, changeVsReference: Double, borderChange: Double, meanLuma: Double) {
        self.timestamp = timestamp
        self.motionFraction = motionFraction
        self.changeVsReference = changeVsReference
        self.borderChange = borderChange
        self.meanLuma = meanLuma
    }
}

/// Who paused the state machine (section 6.3, rows P1 to P2c).
/// `.user`: the application (end of a game, end of the one-dart check, device moved); only `.arm` leaves that pause.
/// `.background`, `.thermal`: the system (scene phase, capture interruption, heat); `.resume` leaves it.
public enum PauseReason: Sendable { case user, background, thermal }

public enum ScanState: Hashable, Sendable {
    case needsCalibration
    /// Calibrated, not armed: frames are ignored until `.arm`, or until `.confirmBoardEmpty` after `needsEmptyBoard`.
    case idle
    /// Waiting for a still view to take the references and measure the noise.
    case arming
    /// Still view; `dartsOnBoard` darts are committed.
    case watching(dartsOnBoard: Int)
    case motion
    /// Quiet frames are being accumulated.
    case settling
    case analysing
    /// The visit is full or was ended early; waiting for the darts to be pulled.
    case awaitingTakeout
    /// A hand was seen and some darts are gone; waiting for an empty board.
    case takeout
    case obstructed
    case calibrationLost
    /// Carries the reason of the first pause; a later `.pause(.user)` replaces a system reason (rows P1 and P1b).
    case paused(PauseReason)
}

public enum ScanAdvisory: Sendable {
    case viewObstructed, accuracyDegraded, suggestScanMode, suggestLightingCheck, flicker, lowLight, thermalThrottling
}

public enum DartRemovalReason: Sendable {
    /// The dart left the board without a hand in view.
    case fellOut
    /// The dart was pulled.
    case takeout
}

public enum ScanEvent: Hashable, Sendable {
    case stateChanged(ScanState)
    case dart(DartObservation)
    /// An earlier dart moved when a new one landed; its score should be checked.
    case dartDisturbed(id: UUID)
    case dartRemoved(id: UUID, reason: DartRemovalReason)
    /// Throw-like motion and nothing stuck: bounce-out or miss. Never scored automatically.
    case possibleMiss(timestamp: TimeInterval)
    case takeoutStarted
    case takeoutStalled(remaining: [UUID])
    /// The board is empty again. A proposal for the game layer, which still needs its own `endTurn`.
    case takeoutCompleted
    /// Result of `.captureNow` in manual trigger mode: exactly one per accepted command, possibly empty, emitted last.
    case scanCompleted([DartObservation])
    case lightingChanged
    case unrecognizedChange
    /// References are unusable; the player must clear the board and confirm (`.confirmBoardEmpty`).
    /// Emitted right after `stateChanged(.idle)`.
    case needsEmptyBoard
    /// Emitted by `ScanEngine`, never by the reducer.
    case calibrationAdjusted(BoardCalibration)
    case calibrationLost
    /// Emitted by `ScanEngine`, never by the reducer.
    case calibrationRecovered(BoardCalibration)
    case advisory(ScanAdvisory)
}

public enum ScanCommand: Hashable, Sendable {
    /// Start of a game, from any calibrated state: clears references, silhouettes and counters, then takes the
    /// references. With `boardConfirmedEmpty == false` the empty reference stays unknown until `.confirmBoardEmpty`.
    /// The only command that leaves `paused(.user)`.
    case arm(boardConfirmedEmpty: Bool)
    case beginVisit(expectedDarts: Int)
    /// Bust or checkout: wait for the takeout, flag further darts `beyondVisitLimit`.
    case endVisit
    /// The player states that the board is empty now: the next settled frame becomes the empty reference.
    /// From `idle` (after `needsEmptyBoard`) it re-arms and resumes watching, counters kept (row P3).
    case confirmBoardEmpty
    /// Accept the current board as the baseline ("Continuer" after a stalled takeout or an unrecognised change).
    case rebaseline
    /// False positive: the footprint stays in the rolling reference, the count drops.
    case discardDart(UUID)
    /// The player added a dart that vision missed: only raises the count.
    case registerManualDart
    /// Survives `.arm`, `.pause` and `.resume` (rows DM1 and DM8).
    case setTrigger(ScanTrigger)
    /// Manual trigger, at rest: take the empty and rolling references from the next settled frames (row DM2).
    case captureReference
    /// Manual trigger, at rest: analyse the next settled frames for up to `maxDarts` new darts (row DM3).
    /// Ignored, without any event, when `maxDarts <= 0`; otherwise answered by exactly one `scanCompleted`.
    case captureNow(maxDarts: Int)
    /// Accepted in every state (rows P1 and P1b).
    case pause(PauseReason)
    /// Leaves a pause of reason `.background` or `.thermal` (rows P2, P2b, DM7); ignored in `paused(.user)` (row P2c).
    case resume
}

/// Summary of one motion episode, from the first motion frame to the settle.
public struct EpisodeSummary: Hashable, Sendable {
    public var duration: TimeInterval
    public var peakMotionFraction: Double
    /// Longest run of frames with `borderChange` above `handBorderFraction`.
    public var borderIntrusionFrames: Int
    public init(duration: TimeInterval, peakMotionFraction: Double, borderIntrusionFrames: Int) {
        self.duration = duration
        self.peakMotionFraction = peakMotionFraction
        self.borderIntrusionFrames = borderIntrusionFrames
    }
    /// `duration > throwMaxDuration` or `borderIntrusionFrames >= handSustainFrames`.
    /// The reducer also treats every episode that started from `takeout` or `obstructed` as hand-like.
    public func isHandLike(_ parameters: ScanParameters) -> Bool {
        duration > parameters.throwMaxDuration || borderIntrusionFrames >= parameters.handSustainFrames
    }
}

/// What the engine found on a settled frame, as seen by the reducer.
public enum SettleOutcome: Hashable, Sendable {
    case noChange
    case darts(new: [DartObservation], removed: [UUID], disturbed: [UUID])
    case removed([UUID], boardEmpty: Bool)
    case obstruction
    case lightingChanged
    case foreignRemoval
    case unrecognized
}

public enum ScanInput: Hashable, Sendable {
    case calibrationSet
    case gate(GateSample)
    case armed
    case settle(SettleOutcome, timestamp: TimeInterval)
    case calibrationHealth(CalibrationHealth.Status, recovered: Bool, timestamp: TimeInterval)
    case command(ScanCommand)
}

public enum ReferenceUpdate: Sendable {
    /// Rolling reference := current settled frame.
    case rolling
    /// Rolling and empty references := current settled frame; silhouettes cleared.
    case rollingAndEmpty
    /// Rolling reference := empty reference, no frame involved; silhouettes cleared (manual trigger, row DM4).
    case rollingFromEmpty
    case markEmptyStale
}

public enum ScanEffect: Hashable, Sendable {
    case beginAccumulation
    case discardAccumulation
    case analyse(maxNewDarts: Int)
    case checkCalibration
    case updateReference(ReferenceUpdate)
    case setGateReference
    case emit(ScanEvent)
}
