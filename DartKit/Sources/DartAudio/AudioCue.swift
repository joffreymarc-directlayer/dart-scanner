// DartAudio — the values that travel between DartUI and the sound service (ARCHITECTURE.md §7.2).
import Foundation
import DartCore

/// One sentence for the score caller, in both languages (the caller's language may differ from the UI's).
public struct Announcement: Hashable, Sendable {
    public enum Priority: Int, Comparable, Sendable {
        /// Per-dart call ("Triple 20"): replaced by any newer sentence, dropped while a `normal` or `high` one is spoken or queued.
        case low
        /// Turn total, next player: queued after what is being said.
        case normal
        /// 180, bust, victory: interrupts everything.
        case high

        public static func < (lhs: Priority, rhs: Priority) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    public var text: LocalizedText
    public var priority: Priority

    public init(_ text: LocalizedText, priority: Priority = .normal) {
        self.text = text
        self.priority = priority
    }
}

/// One thing to play: a sound, a sentence, a haptic, or any combination, `delay` seconds after the batch starts.
public struct AudioCue: Hashable, Sendable {
    public var effect: SoundEffect?
    public var announcement: Announcement?
    public var haptic: HapticPattern?
    public var delay: TimeInterval

    public init(effect: SoundEffect? = nil, announcement: Announcement? = nil, haptic: HapticPattern? = nil,
                delay: TimeInterval = 0) {
        self.effect = effect
        self.announcement = announcement
        self.haptic = haptic
        self.delay = delay
    }
}

/// The sound settings of DESIGN.md §4 ("Réglages"). Persisted by DartUI.
public struct AudioSettings: Hashable, Codable, Sendable {
    /// Master mute: nothing is played, spoken or vibrated.
    public var isMuted: Bool = false
    public var effectsEnabled: Bool = true
    /// Spoken score caller.
    public var callerEnabled: Bool = true
    public var callerLanguage: AppLanguage = .fr
    /// 0...1, applied to effects and voice.
    public var volume: Double = 0.8
    /// true: `.playback` (audible with the Silent switch on). false: `.ambient`.
    public var playsInSilentMode: Bool = true
    /// Lowers other apps' audio while a score is spoken (speech uses its own, system-managed session).
    public var ducksMusicWhileSpeaking: Bool = true
    /// iPhone only; ignored where there is no Taptic Engine.
    public var hapticsEnabled: Bool = true

    public init() {}
}

/// What the mapping needs to know about the game, taken from the snapshot AFTER the input.
public struct CueContext: Sendable {
    /// For logs only. The mapping NEVER branches on it: what a game has of its own arrives as data (`winnerTitle`).
    public var gameID: GameID
    public var players: [Player]
    /// `snapshot.winners` once the game is finished, empty before.
    public var winners: [PlayerIndex]
    /// `snapshot.winnerTitle`: the headline said at `gameFinished` in place of the winners' names
    /// ("Le camp A gagne", "Match nul"). Nil: the winners are announced by `CallerPhrases.winners`.
    public var winnerTitle: LocalizedText?

    public init(gameID: GameID, players: [Player], winners: [PlayerIndex] = [], winnerTitle: LocalizedText? = nil) {
        self.gameID = gameID
        self.players = players
        self.winners = winners
        self.winnerTitle = winnerTitle
    }
}

/// Things worth a sound that are not game events: interface actions and scan-pipeline events.
/// DartUI translates `ScanEvent` into these; DartAudio does not import DartVision.
public enum InterfaceCue: Hashable, Sendable {
    /// First turn of a game: "Au tour de Léa".
    case gameStarted(firstPlayer: PlayerIndex)
    /// Medium-confidence dart: played after the dart's own cues.
    case dartNeedsReview
    /// Low-confidence dart: not sent to the game, nothing is announced.
    case dartUndecided
    /// A dart arrived while the turn was complete.
    case dartIgnored
    /// Throw-like motion and nothing stuck.
    case possibleMiss
    /// The board is empty again: the "next player" button is ready.
    case boardCleared
    case undo
    case correctionApplied
    case shutter
    case calibrationValidated
    case calibrationLost
    case buttonTap
}
