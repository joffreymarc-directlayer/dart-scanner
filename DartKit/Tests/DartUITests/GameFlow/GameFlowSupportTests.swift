import Foundation
import CoreGraphics
import Testing
import DartCore
import DartGames
import DartAudio
import DartTestSupport
@testable import DartUI

/// Shared helpers of the `GameFlow` tests (lot U2): a source that records every command it receives, fixed
/// identifiers, proposals of each certainty, and a play view model wired to an in-memory store.

/// One command of `DartInputSource`, as the fake source records it.
enum GameFlowCommand: Hashable {
    case gameStarted(boardConfirmedEmpty: Bool)
    case turnBegan(expectedDarts: Int)
    case turnClosed
    case dartDiscarded(UUID)
    case manualDartAdded
    case turnConfirmed([DartFeedback])
    case boardConfirmedEmpty
    case gameEnded
}

/// A scripted automatic source: it records the commands in order and pushes the events the test gives it to
/// the stream opened by `run`.
@MainActor
final class GameFlowRecordingSource: DartInputSource {
    var status: InputStatus
    private(set) var commands: [GameFlowCommand] = []
    private(set) var streamsOpened = 0
    var evidence: CGImage?
    var rescored: DartProposal?
    private var continuations: [AsyncStream<DartInputEvent>.Continuation] = []

    init(status: InputStatus = .preparing) {
        self.status = status
    }

    func events() -> AsyncStream<DartInputEvent> {
        streamsOpened += 1
        let (stream, continuation) = AsyncStream.makeStream(of: DartInputEvent.self)
        continuations.append(continuation)
        return stream
    }

    /// Pushes an event to every open stream.
    func emit(_ event: DartInputEvent) {
        for continuation in continuations { continuation.yield(event) }
    }

    /// Ends every stream: `run` returns.
    func finish() {
        for continuation in continuations { continuation.finish() }
        continuations = []
    }

    func clearCommands() { commands = [] }

    func gameStarted(boardConfirmedEmpty: Bool) { commands.append(.gameStarted(boardConfirmedEmpty: boardConfirmedEmpty)) }
    func turnBegan(expectedDarts: Int) { commands.append(.turnBegan(expectedDarts: expectedDarts)) }
    func turnClosed() { commands.append(.turnClosed) }
    func dartDiscarded(_ id: UUID) { commands.append(.dartDiscarded(id)) }
    func manualDartAdded() { commands.append(.manualDartAdded) }
    func turnConfirmed(_ feedback: [DartFeedback]) { commands.append(.turnConfirmed(feedback)) }
    func boardConfirmedEmpty() { commands.append(.boardConfirmedEmpty) }
    func gameEnded() { commands.append(.gameEnded) }
    func evidenceImage(for id: UUID) async -> CGImage? { evidence }
    func rescore(_ id: UUID, tip point: BoardPoint) async -> DartProposal? { rescored }
}

/// Fixed identifiers: `gameFlowID(7)` is 00000000-0000-0000-0000-000000000007.
func gameFlowID(_ n: Int) -> UUID {
    UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", n)) ?? UUID()
}

/// A proposal of a fixed id and certainty, as a camera source would make it.
func gameFlowProposal(_ notation: String, id: Int, certainty: Certainty = .certain, origin: DartOrigin = .camera,
                      position: BoardPoint? = nil, choices: [String] = []) -> DartProposal {
    let hit = Hit(notation: notation) ?? .miss
    return DartProposal(id: gameFlowID(id), hit: hit, position: position, origin: origin,
                        choices: [hit] + choices.compactMap { Hit(notation: $0) }) { _ in certainty }
}

/// A manual proposal of a fixed id (a tap without position, "Manqué", a hit picked in a list).
func gameFlowManual(_ notation: String, id: Int, position: BoardPoint? = nil) -> DartProposal {
    gameFlowProposal(notation, id: id, certainty: .certain, origin: .manual, position: position)
}

/// Everything a play-screen scenario needs.
@MainActor
struct GameFlowRig {
    let game: PlayViewModel
    let source: GameFlowRecordingSource?
    let sound: SilentSoundPlayer
    let store: InMemoryStore
    var storage: DartUI.AppStorage { DartUI.AppStorage(store: store) }

    init(_ id: GameID, _ options: GameOptions = [:], players: Int, seed: UInt64 = 0, withSource: Bool = true,
         endsTurnOnTakeout: Bool = false, script: String? = nil) throws {
        var match = try GameRegistry.standard.match(id, options, players: players, seed: seed)
        if let script { match.play(script) }
        try self.init(match: match, withSource: withSource, endsTurnOnTakeout: endsTurnOnTakeout)
    }

    init(match: GameMatch, withSource: Bool = true, endsTurnOnTakeout: Bool = false,
         store: InMemoryStore = InMemoryStore()) throws {
        let source = withSource ? GameFlowRecordingSource() : nil
        let sound = SilentSoundPlayer()
        self.source = source
        self.sound = sound
        self.store = store
        self.game = PlayViewModel(match: match, source: source, sound: sound, storage: DartUI.AppStorage(store: store),
                                  endsTurnOnTakeout: endsTurnOnTakeout)
    }

    var commands: [GameFlowCommand] { source?.commands ?? [] }

    /// Every sentence the sound service was asked to say, in French.
    var spoken: [String] { sound.played.compactMap { $0.announcement?.text.fr } }

    /// Every effect the sound service was asked to play.
    var effects: [SoundEffect] { sound.played.compactMap(\.effect) }

    /// Runs the start-up of `run` (the source has no event yet): returns once the stream is open and the
    /// start-up commands are sent, leaving the loop running in a task that `finish()` ends.
    func start(boardConfirmedEmpty: Bool = false) async -> Task<Void, Never> {
        let game = game
        let task = Task { @MainActor in await game.run(boardConfirmedEmpty: boardConfirmedEmpty) }
        // `run` sends its start-up commands synchronously once it is scheduled.
        while !game.hasStarted { await Task.yield() }
        return task
    }

    /// Lets the main actor process the events already pushed to the stream.
    func settle() async {
        for _ in 0..<20 { await Task.yield() }
    }

    func savedRecord() -> MatchRecord? { storage.loadCurrentMatch() }

    func notations() -> [String] { game.turnRecords.map(\.hit.notation) }
}

/// The helpers themselves: the fake source keeps the order of the calls and the fixed ids are stable.
@MainActor
@Suite struct GameFlowSupportTests {
    @Test func recordingSource_keepsTheOrderOfTheCommands() {
        let source = GameFlowRecordingSource()
        source.gameStarted(boardConfirmedEmpty: true)
        source.turnBegan(expectedDarts: 3)
        source.manualDartAdded()
        source.turnClosed()
        source.gameEnded()
        #expect(source.commands == [.gameStarted(boardConfirmedEmpty: true), .turnBegan(expectedDarts: 3), .manualDartAdded,
                                    .turnClosed, .gameEnded])
        #expect(gameFlowID(7) == UUID(uuidString: "00000000-0000-0000-0000-000000000007"))
        #expect(gameFlowProposal("T20", id: 1, certainty: .needsReview).choices == [.treble(20)])
    }
}
