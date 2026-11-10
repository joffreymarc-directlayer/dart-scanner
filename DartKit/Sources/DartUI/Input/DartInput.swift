import Foundation
import CoreGraphics
import DartCore

/// How sure the application is about a proposed dart, FOR THE CURRENT GAME (VISION.md §7.4).
enum Certainty: Hashable, Sendable {
    /// Sent to the game.
    case certain
    /// Sent to the game and shown as "à vérifier".
    case needsReview
    /// Not sent: the player must answer first.
    case undecided
}

/// One dart proposed to the play screen, whatever its origin. Knows nothing about DartVision.
struct DartProposal: Identifiable, Sendable {
    /// For camera darts: `DartObservation.id`. It becomes `DartRecord.id`.
    let id: UUID
    /// Best hypothesis.
    var hit: Hit
    /// Nominal board millimetres, when known.
    var position: BoardPoint?
    var origin: DartOrigin
    /// Hits offered on the correction card, best first (at least 4 when the source has them).
    var choices: [Hit]
    /// Certainty of this dart for a given state of the game. Camera sources compute it with
    /// `DartObservation.tier(collapsingBy: { match.effectKey(for: $0, position: tip) })`, so that a doubt between
    /// two hits of equal effect does not bother the player (VISION.md §7.4). The measured tip is passed with every
    /// candidate hit: a position-dependent game is keyed on (hit, position) (GAMES.md §2.13). In such a game a
    /// certain dart is lowered to `needsReview` when its tip lies within its own uncertainty of a change of
    /// effect, e.g. the edge of a Radar target (ARCHITECTURE.md §8.4.8).
    var certainty: @Sendable (GameMatch) -> Certainty

    init(id: UUID, hit: Hit, position: BoardPoint?, origin: DartOrigin, choices: [Hit],
         certainty: @escaping @Sendable (GameMatch) -> Certainty) {
        self.id = id
        self.hit = hit
        self.position = position
        self.origin = origin
        self.choices = choices
        self.certainty = certainty
    }

    /// A tap on the virtual board (`position` = the tapped point, `BoardTap.position`), "Manqué", or a hit picked
    /// in a list (no position: a position-dependent game then uses the canonical position of the bed): always certain.
    static func manual(_ hit: Hit, position: BoardPoint? = nil) -> DartProposal {
        DartProposal(id: UUID(), hit: hit, position: position, origin: .manual, choices: [hit]) { _ in .certain }
    }

    /// The journal record for this proposal.
    func record(needsReview: Bool) -> DartRecord {
        DartRecord(id: id, hit: hit, position: position, origin: origin, needsReview: needsReview)
    }
}

/// What the header pill shows about the automatic input.
enum InputStatus: Hashable, Sendable {
    /// No automatic source: taps on the virtual board only.
    case manualOnly
    /// The source is starting or taking its references ("Ne bougez plus…").
    case preparing
    /// Darts are detected as they land.
    case live
    /// Waiting for a manual capture (photo mode).
    case awaitingCapture
    /// Hand or person in front of the board.
    case obstructed
    /// Paused (background, heat, user).
    case paused
    /// The references are unusable: clear the board and confirm.
    case needsEmptyBoard
    /// Calibration lost or missing: manual input until it is redone.
    case needsCalibration
    /// Camera refused, absent (Simulator) or taken by another foreground app.
    case unavailable
}

enum DartRetraction: Hashable, Sendable {
    /// The dart left the board without a hand in view: "Fléchette tombée : 0 ?".
    case fellOut
    /// The dart was pulled.
    case takeout
}

enum DartInputEvent: Sendable {
    case dart(DartProposal)
    /// An earlier dart moved when a new one landed: mark it "à vérifier".
    case dartDisturbed(id: UUID)
    case dartRemoved(id: UUID, reason: DartRetraction)
    /// Throw-like motion and nothing stuck: offer "Rebond ? Manqué".
    case possibleMiss
    /// The board is empty again: PROPOSES the end of the turn.
    case boardCleared
    case statusChanged(InputStatus)
    /// One-line advice for the player (localised by the source).
    case advisory(LocalizedText)
}

/// Feedback for one camera dart when its turn is confirmed.
struct DartFeedback: Hashable, Sendable {
    var id: UUID
    var wasCorrected: Bool
}

/// An automatic provider of darts: the live camera, the manual-trigger scan, a scripted fake.
/// The play screen talks to this protocol only; it never sees `ScanSession`.
@MainActor
protocol DartInputSource: AnyObject {
    var status: InputStatus { get }
    /// A NEW stream per call; finishes when the source stops.
    func events() -> AsyncStream<DartInputEvent>

    // Commands. They are SYNCHRONOUS: the game never awaits the source and never starts a task per command.
    // The source forwards them to the vision layer strictly in the order of the calls (ARCHITECTURE.md §8.7, §11).

    /// A game starts or is resumed. `boardConfirmedEmpty`: the player confirmed that no dart is on the board.
    func gameStarted(boardConfirmedEmpty: Bool)
    /// A turn begins or is reopened (undo, correction, resumed game): `expectedDarts` darts may still come.
    func turnBegan(expectedDarts: Int)
    /// The rules closed the turn (third dart, bust, win): further darts are suspicious.
    func turnClosed()
    /// The player removed a phantom detection.
    func dartDiscarded(_ id: UUID)
    /// The player added by hand a dart that the source missed.
    func manualDartAdded()
    /// The turn was confirmed: one feedback per dart of this source. A dart is reported once: the source
    /// ignores an id it has already reported (a turn confirmed again after an undo).
    func turnConfirmed(_ feedback: [DartFeedback])
    /// The player states that the board is empty now (answer to `needsEmptyBoard`).
    func boardConfirmedEmpty()
    /// The play screen is left, the game being finished or not: the source stops watching.
    func gameEnded()

    // Queries: the only asynchronous calls.

    /// Magnified real image around a dart, for the correction screen; nil when the source has none.
    func evidenceImage(for id: UUID) async -> CGImage?
    /// The player moved the tip on the evidence image (`point` in nominal mm): the dart re-scored from there.
    func rescore(_ id: UUID, tip point: BoardPoint) async -> DartProposal?
}
