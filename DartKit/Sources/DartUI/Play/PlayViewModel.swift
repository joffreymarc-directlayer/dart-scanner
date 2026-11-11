import Foundation
import CoreGraphics
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
/// Behaviour: ARCHITECTURE.md §8.6. Every command to the source is synchronous and made in the order written
/// there; nothing here awaits anything but the events of the source, in `run`.
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

    /// True once `run` has sent the start-up commands (`gameStarted`, the first synchronisation, the first
    /// announcement). A later `run` (the screen appeared again) only subscribes to the source again.
    private(set) var hasStarted = false
    /// True once `finishGame()` or `suspend()` told the source that the game is over: both happen once.
    private(set) var hasEnded = false

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
    func run(boardConfirmedEmpty: Bool) async {
        // The stream is opened BEFORE any command, so that no event of the source is lost (§8.6, step 1).
        let events = source?.events()
        if !hasStarted {
            hasStarted = true
            source?.gameStarted(boardConfirmedEmpty: boardConfirmedEmpty)
            synchroniseSource()
            if !isFinished {
                sound.play(CueMapping.cues(for: .gameStarted(firstPlayer: snapshot.currentPlayer), context: cueContext))
            }
        }
        guard let events else { return }
        for await event in events {
            handle(event)
        }
    }

    /// Reaction to one event of the source (table "Événements de la source", §8.6). `run` calls it for every
    /// event of the stream, one at a time, on the main actor.
    func handle(_ event: DartInputEvent) {
        switch event {
        case .dart(let proposal):
            receive(proposal)
        case .dartDisturbed(let id):
            guard let index = turnRecords.firstIndex(where: { $0.id == id }) else { return }
            match.setNeedsReview(true, at: index)
            save()
        case .dartRemoved(let id, let reason):
            guard reason == .fellOut, let index = turnRecords.firstIndex(where: { $0.id == id }) else { return }
            prompt = .dartFellOut(index: index)
        case .possibleMiss:
            prompt = .possibleMiss
            play(.possibleMiss)
        case .boardCleared:
            if endsTurnOnTakeout && match.phase == .turnComplete && pending.isEmpty {
                endTurn()
            } else {
                prompt = .boardCleared
                play(.boardCleared)
            }
        case .statusChanged(let status):
            let previous = inputStatus
            inputStatus = status
            if status == .needsCalibration && previous != .needsCalibration {
                play(.calibrationLost)
            }
        case .advisory(let text):
            prompt = .advisory(text)
        }
    }

    // Darts
    /// Entry point for EVERY dart (camera, scan, photo, manual).
    func receive(_ proposal: DartProposal) {
        // 1. Outside `throwing` the dart is dropped.
        guard match.phase == .throwing else {
            prompt = .dartIgnored
            play(.dartIgnored)
            return
        }
        // The player throws again instead of answering "Volée incomplète : passer au joueur suivant ?": the turn
        // changed, the question no longer applies (it would stay on a full turn, or while a dart waits).
        if prompt == .confirmShortTurn { prompt = nil }
        // 2. Behind an undecided dart: queued, the order of the darts is kept.
        guard pending.isEmpty else {
            pending.append(proposal)
            return
        }
        // 3. By certainty for the current state of the game.
        switch proposal.certainty(match) {
        case .undecided:
            pending.append(proposal)
            play(.dartUndecided)
            correction = .pending(id: proposal.id)
        case .needsReview:
            accept(proposal.record(needsReview: true), needsReview: true)
        case .certain:
            accept(proposal.record(needsReview: false), needsReview: false)
        }
    }

    /// Manual input: a tap on the virtual board.
    func tapBoard(_ tap: BoardTap) {
        receive(.manual(tap.hit, position: tap.position))
    }

    /// "Manqué" button and bounce-out shortcut.
    func addMiss() {
        if prompt == .possibleMiss { prompt = nil }
        receive(.manual(.miss))
    }

    // Corrections (current turn only)
    /// Answers the head of `pending`: the chosen hit, or nil to discard the detection.
    func resolvePending(with hit: Hit?) {
        guard let head = pending.first else { return }
        guard let hit else {
            resolveHead(with: nil)
            return
        }
        // The same hit keeps the detected position; another hit leaves without one (GAMES.md §2.5).
        resolveHead(with: (hit, hit == head.hit ? head.position : nil))
    }

    /// Answers the head of `pending` with a point of the virtual board of the correction sheet: the hit AND the
    /// position under the finger are applied together (§8.6, "Écran de correction").
    func resolvePending(with tap: BoardTap) {
        guard !pending.isEmpty else { return }
        resolveHead(with: (tap.hit, tap.position))
    }

    func correctDart(at index: Int, to hit: Hit, position: BoardPoint? = nil) {
        guard match.replaceDart(at: index, with: hit, position: position).applied else { return }
        play(.correctionApplied)
        afterEdit()
    }

    func removeDart(at index: Int) {
        guard turnRecords.indices.contains(index) else { return }
        let record = turnRecords[index]
        guard match.removeDart(at: index).applied else { return }
        if Self.comesFromTheSource(record) {
            source?.dartDiscarded(record.id)
        }
        play(.correctionApplied)
        afterEdit()
    }

    /// Accepts a dart shown as "à vérifier" as it is.
    func confirmDart(at index: Int) {
        guard turnRecords.indices.contains(index) else { return }
        match.setNeedsReview(false, at: index)
        afterEdit()
    }

    func undo() {
        guard match.undo().applied else { return }
        play(.undo)
        afterEdit()
    }

    // Turn
    /// False while `pending` is not empty or the game is finished.
    var canEndTurn: Bool {
        pending.isEmpty && !isFinished
    }

    /// "Fléchettes retirées, suivant": asks for a confirmation when the turn is short and the game wants one
    /// (`descriptor.confirmsShortTurn`), else calls `endTurn`.
    func requestEndTurn() {
        guard canEndTurn else { return }
        if match.phase == .throwing && turnRecords.count < 3 && descriptor.confirmsShortTurn {
            prompt = .confirmShortTurn
        } else {
            endTurn()
        }
    }

    func endTurn() {
        guard canEndTurn else { return }
        let feedback = sourceFeedback()
        if !feedback.isEmpty {
            source?.turnConfirmed(feedback)
        }
        let outcome = match.endTurn()
        guard outcome.isAccepted else { return }
        prompt = nil
        sound.play(CueMapping.cues(for: outcome.events, context: cueContext))
        save()
        switch match.phase {
        case .throwing: source?.turnBegan(expectedDarts: 3)
        case .turnComplete, .finished: source?.turnClosed()
        }
    }

    /// The player answers the status `needsEmptyBoard`: the board is empty now (§8.7). The only call of
    /// `source.boardConfirmedEmpty()`: the next-player button never sends it.
    func confirmBoardEmpty() {
        source?.boardConfirmedEmpty()
    }

    // End of the game
    var isFinished: Bool {
        match.phase == .finished
    }

    /// The results screen is left (`AppModel.closeGame` or `rematch`): reports the feedback of the last turn,
    /// tells the source that the game is over, deletes the saved game. Until then a finished game stays saved
    /// and correctable (`undo`, `correctDart`).
    func finishGame() {
        guard !hasEnded else { return }
        hasEnded = true
        let feedback = sourceFeedback()
        if !feedback.isEmpty {
            source?.turnConfirmed(feedback)
        }
        source?.gameEnded()
        storage.saveCurrentMatch(nil)
    }

    /// The play screen is left before the end of the game: tells the source to stop watching; the saved game is kept.
    func suspend() {
        guard !hasEnded else { return }
        hasEnded = true
        source?.gameEnded()
    }

    /// Same players, same options, new seed.
    func rematchConfiguration(seed: UInt64) -> GameConfiguration {
        var configuration = match.configuration
        configuration.seed = seed
        return configuration
    }

    // MARK: Queries of the correction sheet (the source stays private)

    /// Magnified real image around a dart of the source; nil without a source or without an image.
    func evidenceImage(for id: UUID) async -> CGImage? {
        await source?.evidenceImage(for: id)
    }

    /// The dart re-scored from a tip moved on the evidence image; nil without a source.
    func rescore(_ id: UUID, tip point: BoardPoint) async -> DartProposal? {
        await source?.rescore(id, tip: point)
    }

    /// True when the game has an automatic source (camera or scan): the scan pill and the live view exist.
    var hasSource: Bool {
        source != nil
    }

    // MARK: Private

    /// Sends a dart to the game and does what follows an accepted dart (§8.6, steps 3 and 4).
    private func accept(_ record: DartRecord, needsReview: Bool) {
        let outcome = match.throwDart(record)
        guard outcome.isAccepted else {
            prompt = .dartIgnored
            play(.dartIgnored)
            return
        }
        if let current = prompt, Self.endsWithADart(current) { prompt = nil }
        // The context is taken from the snapshot AFTER the input.
        sound.play(CueMapping.cues(for: outcome.events, context: cueContext))
        if needsReview { play(.dartNeedsReview) }
        save()
        if record.origin == .manual {
            source?.manualDartAdded()
        }
        if match.phase != .throwing {
            source?.turnClosed()
        }
    }

    /// Removes the head of `pending` and answers it: `answer` nil discards it, otherwise it goes to the game as a
    /// certain dart with that hit and position (`corrected` when the hit changed). The darts queued behind it
    /// are then received again, in order, up to the next undecided one.
    private func resolveHead(with answer: (hit: Hit, position: BoardPoint?)?) {
        guard !pending.isEmpty else { return }
        let head = pending.removeFirst()
        if correction == .pending(id: head.id) { correction = nil }
        if let answer {
            let record = DartRecord(id: head.id, hit: answer.hit, position: answer.position, origin: head.origin,
                                    needsReview: false, corrected: answer.hit != head.hit)
            if match.phase == .throwing {
                accept(record, needsReview: false)
            } else {
                prompt = .dartIgnored
                play(.dartIgnored)
            }
        } else {
            source?.dartDiscarded(head.id)
            play(.correctionApplied)
        }
        let queued = pending
        pending = []
        for proposal in queued {
            receive(proposal)
        }
    }

    /// After a correction or an undo: no past event is replayed, the game is saved, and the source is
    /// resynchronised on the phase obtained (§8.6, "Corrections").
    private func afterEdit() {
        // A question about a dart or about the turn no longer applies once the turn changed.
        switch prompt {
        case .dartFellOut?, .confirmShortTurn?: prompt = nil
        default: break
        }
        save()
        synchroniseSource()
    }

    /// `turnBegan(3 − n)` while the turn is open, `turnClosed()` once it is closed or the game is finished.
    private func synchroniseSource() {
        switch match.phase {
        case .throwing: source?.turnBegan(expectedDarts: max(0, 3 - match.currentTurn.count))
        case .turnComplete, .finished: source?.turnClosed()
        }
    }

    /// One feedback per dart of the current turn that came from the source (origin camera or scan).
    private func sourceFeedback() -> [DartFeedback] {
        turnRecords.filter(Self.comesFromTheSource).map { DartFeedback(id: $0.id, wasCorrected: $0.corrected) }
    }

    private static func comesFromTheSource(_ record: DartRecord) -> Bool {
        record.origin == .camera || record.origin == .scan
    }

    /// Prompts that a newly accepted dart makes obsolete.
    private static func endsWithADart(_ prompt: PlayPrompt) -> Bool {
        switch prompt {
        case .dartIgnored, .possibleMiss, .boardCleared, .advisory: return true
        case .dartFellOut, .confirmShortTurn: return false
        }
    }

    private func save() {
        storage.saveCurrentMatch(match.record)
    }

    private func play(_ cue: InterfaceCue) {
        sound.play(CueMapping.cues(for: cue, context: cueContext))
    }

    /// Taken from the snapshot of the moment: winners and title only once the game is finished.
    private var cueContext: CueContext {
        let snapshot = match.snapshot
        let finished = snapshot.phase == .finished
        return CueContext(gameID: snapshot.gameID, players: match.players,
                          winners: finished ? snapshot.winners : [],
                          winnerTitle: finished ? snapshot.winnerTitle : nil)
    }
}
