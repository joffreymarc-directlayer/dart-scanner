import Foundation
import Observation
import DartCore
import DartAudio

/// Transient message of the play screen.
enum PlayPrompt: Hashable, Sendable {
    /// A dart arrived while the turn was complete: "Tour terminé, retirez les fléchettes".
    case dartIgnored
    /// "Rebond ? Manqué" shortcut, shown for a few seconds.
    case possibleMiss
    /// "Fléchette tombée : 0 ?" for dart `index` of the current turn.
    case dartFellOut(index: Int)
    /// Fewer than three darts: "Volée incomplète : passer au joueur suivant ?".
    case confirmShortTurn
    /// The camera saw an empty board: the next-player button is emphasised.
    case boardCleared
    case advisory(LocalizedText)
}

/// What the correction sheet edits.
enum CorrectionTarget: Hashable, Sendable, Identifiable {
    /// Dart `index` of the current turn, already in the journal.
    case recorded(index: Int)
    /// Head of the pending queue (not yet sent to the game).
    case pending(id: UUID)

    var id: String {
        switch self {
        case .recorded(let index): return "recorded-\(index)"
        case .pending(let id): return "pending-\(id.uuidString)"
        }
    }
}

/// The ONLY owner of a running game: applies darts, corrections and turn changes, feeds sound and persistence.
@MainActor
@Observable
final class PlayViewModel: Identifiable {
    nonisolated let id = UUID()
    /// The game. Views read `snapshot`; nothing else mutates the match.
    private(set) var match: GameMatch
    var snapshot: GameSnapshot { match.snapshot }
    /// Descriptor of the game: play template, `boardGeometry`, `confirmsShortTurn`.
    var descriptor: GameDescriptor { match.definition.descriptor }
    /// Journal records of the current turn, aligned with `snapshot.turn.darts` (review flag, origin, id).
    var turnRecords: [DartRecord] { match.currentTurn }
    /// Undecided darts, oldest first. While it is not empty, later darts queue behind it (VISION.md §7.4).
    private(set) var pending: [DartProposal] = []
    private(set) var inputStatus: InputStatus = .manualOnly
    var prompt: PlayPrompt?
    var correction: CorrectionTarget?

    private let source: (any DartInputSource)?
    private let sound: any SoundPlaying
    private let storage: AppStorage
    private let endsTurnOnTakeout: Bool

    /// Lot F0 writes this WORKING body (it only stores its parameters): `AppModel.startGame` (lot U1, wave 1)
    /// creates a PlayViewModel before lot U2 delivers the rest of this file. Lot U2 keeps the signature.
    /// `inputStatus` tells whether the game has a source: `.manualOnly` without one.
    init(match: GameMatch, source: (any DartInputSource)?, sound: any SoundPlaying,
         storage: AppStorage, endsTurnOnTakeout: Bool) {
        self.match = match
        self.source = source
        self.sound = sound
        self.storage = storage
        self.endsTurnOnTakeout = endsTurnOnTakeout
        self.inputStatus = source?.status ?? .manualOnly
    }

    /// Subscribes to the source, synchronises it with the phase of the match (new or resumed game), announces
    /// the player to throw. Call from `.task` of the play screen.
    func run(boardConfirmedEmpty: Bool) async { unimplemented() }

    // Darts
    /// Entry point for EVERY dart (camera, scan, photo, manual).
    func receive(_ proposal: DartProposal) { unimplemented() }
    /// Manual input: a tap on the virtual board.
    func tapBoard(_ tap: BoardTap) { unimplemented() }
    /// "Manqué" button and bounce-out shortcut.
    func addMiss() { unimplemented() }

    // Corrections (current turn only)
    /// Answers the head of `pending`: the chosen hit, or nil to discard the detection.
    func resolvePending(with hit: Hit?) { unimplemented() }
    func correctDart(at index: Int, to hit: Hit, position: BoardPoint? = nil) { unimplemented() }
    func removeDart(at index: Int) { unimplemented() }
    /// Accepts a dart shown as "à vérifier" as it is.
    func confirmDart(at index: Int) { unimplemented() }
    func undo() { unimplemented() }

    // Turn
    /// False while `pending` is not empty or the game is finished.
    var canEndTurn: Bool { unimplemented() }
    /// "Fléchettes retirées, suivant": asks for a confirmation when the turn is short and the game wants one
    /// (`descriptor.confirmsShortTurn`), else calls `endTurn`.
    func requestEndTurn() { unimplemented() }
    func endTurn() { unimplemented() }

    // End of the game
    var isFinished: Bool { unimplemented() }
    /// The results screen is left (`AppModel.closeGame` or `rematch`): reports the feedback of the last turn,
    /// tells the source that the game is over, deletes the saved game. Until then a finished game stays saved
    /// and correctable (`undo`, `correctDart`).
    func finishGame() { unimplemented() }
    /// The play screen is left before the end of the game: tells the source to stop watching; the saved game is kept.
    func suspend() { unimplemented() }
    /// Same players, same options, new seed.
    func rematchConfiguration(seed: UInt64) -> GameConfiguration { unimplemented() }
}
