import Foundation
import CoreGraphics
import SwiftUI
import Testing
import DartCore
import DartGames
import DartAudio
import DartTestSupport
@testable import DartUI

/// Review of lot U2: every game of the registry played to its end through `PlayViewModel` with random input
/// (fixed seeds): taps, camera darts of the three certainties, answers to waiting darts, corrections, removals,
/// "à vérifier" accepted, undo (also from the results), short turns, events of the source, the game left and
/// resumed in the middle of a turn. After every step the screen state, the sounds asked for, the saved game and
/// the commands of the source must agree with the engine (ARCHITECTURE.md §8.6, §8.10).
@MainActor
@Suite struct GameFlowReviewWholeGamesTests {
    /// Short games: the round limits are lowered so that a game ends both ways within the step budget.
    private static func options(for descriptor: GameDescriptor, variant: Int) -> GameOptions {
        var options = GameOptions()
        for option in descriptor.options {
            switch (option.key, option.kind) {
            case ("maxRounds", _): options[option.key] = variant.isMultiple(of: 2) ? .int(3) : .int(6)
            case ("rounds", .stepper): options[option.key] = .int(variant.isMultiple(of: 2) ? 2 : 3)
            case ("lives", .stepper): options[option.key] = .int(2)
            case ("goalsToWin", _): options[option.key] = .int(1)
            case ("fieldLength", _): options[option.key] = .int(3)
            case ("armingHits", _): options[option.key] = .int(1)
            case ("level", .choice(let choices)):
                options[option.key] = choices[variant % choices.count].value
            default: break
            }
        }
        return options
    }

    @Test func everyGame_playedToTheEnd_withRandomInput_staysConsistent() async throws {
        var finishedReasons: [GameID: Set<String>] = [:]
        for descriptor in GameRegistry.standard.descriptors {
            for variant in 0..<6 {
                let seed = UInt64(1 + variant * 7919) &+ UInt64(descriptor.id.rawValue.count)
                let options = Self.options(for: descriptor, variant: variant)
                let range = descriptor.playerRange(for: descriptor.normalized(options))
                var pick = SeededRandom(seed: seed)
                let players = range.lowerBound + pick.nextInt(below: min(4, range.count))
                let configuration = GameConfiguration(gameID: descriptor.id, options: options, players: testPlayers(players),
                                                      seed: seed)
                let match = try GameRegistry.standard.makeMatch(configuration)
                let driver = GameFlowReviewDriver(match: match, seed: seed &* 31, endsTurnOnTakeout: variant >= 2)
                await driver.start()
                let reason = await driver.playToTheEnd(maxSteps: 2_500)
                finishedReasons[descriptor.id, default: []].insert(reason)
                await driver.stop()
            }
        }
        for descriptor in GameRegistry.standard.descriptors {
            let reasons = finishedReasons[descriptor.id] ?? []
            #expect(!reasons.contains("unfinished"), "\(descriptor.id.rawValue) did not finish: \(reasons)")
        }
        // Both ways of finishing were reached (§8.6, "Fin de la partie").
        let all = finishedReasons.values.reduce(into: Set<String>()) { $0.formUnion($1) }
        #expect(all.contains("roundLimit") && (all.contains("victory") || all.contains("lastPlayerStanding")), "\(all)")
    }
}

/// Drives one game with random input and checks the invariants after every step.
@MainActor
private final class GameFlowReviewDriver {
    private var rng: SeededRandom
    private let registry = GameRegistry.standard
    private let store = InMemoryStore()
    private var storage: DartUI.AppStorage { DartUI.AppStorage(store: store) }
    private var source = GameFlowRecordingSource()
    private var sound = SilentSoundPlayer()
    private(set) var game: PlayViewModel
    private let endsTurnOnTakeout: Bool
    private var task: Task<Void, Never>?
    private var nextID = 10_000
    private var step = 0
    private var label: String

    init(match: GameMatch, seed: UInt64, endsTurnOnTakeout: Bool) {
        rng = SeededRandom(seed: seed)
        self.endsTurnOnTakeout = endsTurnOnTakeout
        label = "\(match.snapshot.gameID.rawValue)/\(match.players.count)p/seed \(match.configuration.seed)"
        game = PlayViewModel(match: match, source: source, sound: sound, storage: DartUI.AppStorage(store: store),
                             endsTurnOnTakeout: endsTurnOnTakeout)
    }

    func start() async {
        let game = game
        task = Task { @MainActor in await game.run(boardConfirmedEmpty: true) }
        while !game.hasStarted { await Task.yield() }
        let n = game.turnRecords.count
        let sync: GameFlowCommand = game.match.phase == .throwing ? .turnBegan(expectedDarts: 3 - n) : .turnClosed
        #expect(source.commands.prefix(2) == [.gameStarted(boardConfirmedEmpty: true), sync] ||
                source.commands.prefix(2) == [.gameStarted(boardConfirmedEmpty: false), sync], "\(label): start \(source.commands)")
    }

    func stop() async {
        source.finish()
        await task?.value
    }

    // MARK: Random input

    private func roll(_ percent: Int) -> Bool { rng.nextInt(below: 100) < percent }
    private func pick<T>(_ items: [T]) -> T { items[rng.nextInt(below: items.count)] }

    private func newID() -> UUID {
        nextID += 1
        return gameFlowID(nextID)
    }

    /// A hit and a position: often one of the zones to aim at (a point inside a disc for Radar), else any bed.
    private func randomDart() -> (hit: Hit, position: BoardPoint?) {
        let aims = game.snapshot.highlights.filter { $0.role == .target || $0.role == .secondary }
        if !aims.isEmpty, roll(60) {
            let aim = pick(aims)
            if case .disc(let x, let y, let radius) = aim.zone {
                let angle = Double(rng.nextInt(below: 360)) * .pi / 180
                let distance = radius * Double(rng.nextInt(below: 90)) / 100
                let point = BoardPoint(x: x + distance * cos(angle), y: y + distance * sin(angle))
                return (BoardGeometry.standard.hit(at: point), point)
            }
            let candidates = Hit.all.filter { aim.zone.contains($0) }
            if !candidates.isEmpty {
                let hit = pick(candidates)
                return (hit, roll(50) ? BoardGeometry.standard.centre(of: hit) : nil)
            }
        }
        let hit = pick(Hit.all)
        return (hit, roll(50) ? BoardGeometry.standard.centre(of: hit) : nil)
    }

    // MARK: Expected values

    private func context(of match: GameMatch) -> CueContext {
        let snapshot = match.snapshot
        let finished = snapshot.phase == .finished
        return CueContext(gameID: snapshot.gameID, players: match.players, winners: finished ? snapshot.winners : [],
                          winnerTitle: finished ? snapshot.winnerTitle : nil)
    }

    private func cues(_ cue: InterfaceCue) -> [AudioCue] {
        CueMapping.cues(for: cue, context: context(of: game.match))
    }

    private var lastSync: GameFlowCommand? {
        source.commands.last {
            switch $0 {
            case .turnBegan, .turnClosed: return true
            default: return false
            }
        }
    }

    // MARK: Invariants

    private func check(_ op: String) {
        let where_ = "\(label) step \(step) \(op)"
        let snapshot = game.snapshot
        #expect(game.turnRecords.map(\.hit) == snapshot.turn.darts.map(\.hit), "\(where_): records and slots differ")
        #expect(game.canEndTurn == (game.pending.isEmpty && snapshot.phase != .finished), "\(where_): canEndTurn")
        // The engine replayed from the journal gives the same screen (the save is a faithful journal).
        let replayed = try? registry.restoreMatch(game.match.record)
        #expect(replayed?.snapshot == snapshot, "\(where_): replay of the journal differs")
        // The save follows every accepted input, undo and correction.
        if let saved = storage.loadCurrentMatch() {
            #expect(saved == game.match.record, "\(where_): stale save")
        } else {
            #expect(game.match.entries.isEmpty, "\(where_): no save but a journal")
        }
        // The source always knows whether the turn is open.
        switch snapshot.phase {
        case .throwing:
            if case .turnBegan? = lastSync {} else { Issue.record("\(where_): turn open, last sync \(String(describing: lastSync))") }
        case .turnComplete, .finished:
            #expect(lastSync == .turnClosed, "\(where_): turn closed, last sync \(String(describing: lastSync))")
        }
        #expect(!source.commands.contains(.gameEnded), "\(where_): gameEnded before the results are left")
        if step.isMultiple(of: 97) { render(where_) }
    }

    /// The edit of §8.6, "Après chacune": saved, and the source told the phase obtained, last.
    private func checkResync(_ op: String, commandsBefore: Int) {
        let expected: GameFlowCommand = game.match.phase == .throwing
            ? .turnBegan(expectedDarts: 3 - game.turnRecords.count) : .turnClosed
        #expect(source.commands.count > commandsBefore && source.commands.last == expected,
                "\(label) step \(step) \(op): resync \(Array(source.commands.dropFirst(commandsBefore)))")
    }

    /// Renders the screen the player sees, to catch a trap in the views.
    private func render(_ where_: String) {
        let view: AnyView
        if game.snapshot.phase == .finished {
            view = AnyView(ResultsContent(snapshot: game.snapshot, players: game.match.players, canUndo: game.match.canUndo))
        } else {
            view = AnyView(PlayContent(model: PlayContentModel(game: game)))
        }
        for device in [SnapshotDevice.phonePortrait, .padLandscape] {
            let renderer = ImageRenderer(content: SnapshotCatalog.framed(view, device: device, language: .fr))
            renderer.proposedSize = ProposedViewSize(device.size)
            renderer.scale = 1
            #expect(renderer.cgImage != nil, "\(where_): render failed")
        }
        // The correction sheet of every dart of the turn, and of the dart that waits for an answer.
        var targets: [CorrectionTarget] = game.turnRecords.indices.map { .recorded(index: $0) }
        if let head = game.pending.first { targets.append(.pending(id: head.id)) }
        for target in targets {
            guard let model = PlayCorrectionModel(game: game, target: target, choice: nil, evidence: nil, reticle: .zero) else {
                Issue.record("\(where_): no correction for \(target)")
                continue
            }
            let renderer = ImageRenderer(content: SnapshotCatalog.framed(AnyView(PlayCorrectionContent(model: model)),
                                                                         device: .phonePortrait, language: .en))
            renderer.proposedSize = ProposedViewSize(SnapshotDevice.phonePortrait.size)
            renderer.scale = 1
            #expect(renderer.cgImage != nil, "\(where_): correction render failed")
        }
    }

    // MARK: Steps

    /// Plays until the game is left from its results; returns how it finished.
    func playToTheEnd(maxSteps: Int) async -> String {
        var reason = "unfinished"
        while step < maxSteps {
            step += 1
            if game.isFinished {
                reason = game.snapshot.finishReason.map { "\($0)" } ?? "?"
                check("finished")
                let headline = ResultsHeadline(game.snapshot)
                if case .winners(let winners) = headline {
                    #expect(!winners.isEmpty, "\(label): nobody wins")
                }
                render("\(label) results")
                // From the results the game stays correctable: undo sometimes, else leave.
                if roll(25) {
                    let before = source.commands.count
                    let played = sound.played.count
                    game.undo()
                    #expect(Array(sound.played.dropFirst(played)) == cues(.undo), "\(label): undo sound")
                    checkResync("undo from the results", commandsBefore: before)
                    check("undo from the results")
                    continue
                }
                let feedback = game.turnRecords.filter { $0.origin == .camera || $0.origin == .scan }
                    .map { DartFeedback(id: $0.id, wasCorrected: $0.corrected) }
                let before = source.commands.count
                game.finishGame()
                let expected: [GameFlowCommand] = (feedback.isEmpty ? [] : [.turnConfirmed(feedback)]) + [.gameEnded]
                #expect(Array(source.commands.dropFirst(before)) == expected, "\(label): finishGame")
                #expect(storage.loadCurrentMatch() == nil, "\(label): save kept after finishGame")
                // A rematch: same players and options, new seed.
                let rematch = game.rematchConfiguration(seed: 77)
                #expect(rematch.players == game.match.players && rematch.options == game.match.configuration.options)
                #expect(rematch.seed == 77 && rematch.gameID == game.snapshot.gameID)
                return reason
            }
            await randomStep()
        }
        return reason
    }

    private func randomStep() async {
        if !game.pending.isEmpty, roll(65) {
            answerPending()
            return
        }
        switch rng.nextInt(below: 100) {
        case 0..<42: throwDart()
        case 42..<50: correct()
        case 50..<53: remove()
        case 53..<56: confirm()
        case 56..<62: undo()
        case 62..<82: nextPlayer()
        case 82..<95: sourceEvent()
        default: await suspendAndResume()
        }
    }

    private func throwDart() {
        let dart = randomDart()
        let before = game.match
        let pendingBefore = game.pending.count
        let played = sound.played.count
        let commands = source.commands.count
        if roll(40) {
            // A tap on the virtual board (or "Manqué").
            let proposal = DartProposal(id: newID(), hit: dart.hit, position: dart.position, origin: .manual,
                                        choices: [dart.hit]) { _ in .certain }
            game.receive(proposal)
            expectArrival(proposal, certainty: .certain, before: before, pendingBefore: pendingBefore, played: played,
                          commands: commands)
            check("manual \(dart.hit.notation)")
        } else {
            let certainty: Certainty = roll(60) ? .certain : (roll(50) ? .needsReview : .undecided)
            let origin: DartOrigin = roll(80) ? .camera : .scan
            let around = PlayCorrectionChoices.around(dart.hit)
            let proposal = DartProposal(id: newID(), hit: dart.hit, position: dart.position, origin: origin,
                                        choices: around.isEmpty ? [dart.hit] : around) { _ in certainty }
            game.receive(proposal)
            expectArrival(proposal, certainty: certainty, before: before, pendingBefore: pendingBefore, played: played,
                          commands: commands)
            check("\(origin) \(dart.hit.notation) \(certainty)")
        }
    }

    /// Steps 1 to 4 of "Arrivée d'une fléchette" (§8.6), against the engine.
    private func expectArrival(_ proposal: DartProposal, certainty: Certainty, before: GameMatch, pendingBefore: Int,
                               played: Int, commands: Int) {
        let where_ = "\(label) step \(step) receive \(proposal.hit.notation)"
        let newSounds = Array(sound.played.dropFirst(played))
        let newCommands = Array(source.commands.dropFirst(commands))
        guard before.phase == .throwing else {
            #expect(game.prompt == .dartIgnored && game.match.entries == before.entries, "\(where_): not ignored")
            #expect(newSounds == CueMapping.cues(for: .dartIgnored, context: context(of: before)), "\(where_): ignored sound")
            #expect(newCommands.isEmpty, "\(where_): \(newCommands)")
            return
        }
        guard pendingBefore == 0 else {
            #expect(game.pending.last?.id == proposal.id && game.match.entries == before.entries, "\(where_): not queued")
            #expect(newSounds.isEmpty && newCommands.isEmpty, "\(where_): queued with effects")
            return
        }
        if certainty == .undecided {
            #expect(game.pending.map(\.id) == [proposal.id] && game.correction == .pending(id: proposal.id), "\(where_)")
            #expect(newSounds == CueMapping.cues(for: .dartUndecided, context: context(of: before)), "\(where_): sound")
            return
        }
        var reference = before
        let outcome = reference.throwDart(proposal.record(needsReview: certainty == .needsReview))
        #expect(game.match.entries == reference.entries && game.snapshot == reference.snapshot, "\(where_): engine differs")
        var expectedSounds = CueMapping.cues(for: outcome.events, context: context(of: reference))
        if certainty == .needsReview { expectedSounds += CueMapping.cues(for: .dartNeedsReview, context: context(of: reference)) }
        #expect(newSounds == expectedSounds, "\(where_): sounds")
        var expectedCommands: [GameFlowCommand] = []
        if proposal.origin == .manual { expectedCommands.append(.manualDartAdded) }
        if reference.phase != .throwing { expectedCommands.append(.turnClosed) }
        #expect(newCommands == expectedCommands, "\(where_): commands \(newCommands)")
        #expect(game.prompt != .confirmShortTurn, "\(where_): short-turn question kept after a dart")
    }

    private func answerPending() {
        guard let head = game.pending.first else { return }
        let commands = source.commands.count
        let entries = game.match.entries
        switch rng.nextInt(below: 4) {
        case 0:
            game.resolvePending(with: head.hit)
            check("answer same \(head.hit.notation)")
        case 1:
            let other = randomDart().hit
            game.resolvePending(with: other)
            if game.match.entries.count > entries.count, case .dart(let record)? = game.match.entries.first(where: {
                if case .dart(let r) = $0 { return r.id == head.id } else { return false }
            }) {
                #expect(record.hit == other && record.corrected == (other != head.hit), "\(label): answer")
                #expect(record.position == (other == head.hit ? head.position : nil), "\(label): answer position")
            }
            check("answer other \(other.notation)")
        case 2:
            let dart = randomDart()
            game.resolvePending(with: BoardTap(hit: dart.hit, position: dart.position ?? .centre))
            check("answer tap \(dart.hit.notation)")
        default:
            game.resolvePending(with: nil as Hit?)
            #expect(source.commands.dropFirst(commands).first == .dartDiscarded(head.id), "\(label): discard")
            check("answer discard")
        }
        #expect(!game.pending.contains { $0.id == head.id }, "\(label): head still waiting")
    }

    private func correct() {
        guard !game.turnRecords.isEmpty else { return }
        let index = rng.nextInt(below: game.turnRecords.count)
        let dart = randomDart()
        let position = roll(50) ? dart.position : nil
        let commands = source.commands.count
        let played = sound.played.count
        game.correctDart(at: index, to: dart.hit, position: position)
        #expect(Array(sound.played.dropFirst(played)) == cues(.correctionApplied), "\(label): correction sound")
        checkResync("correct", commandsBefore: commands)
        check("correct \(index) → \(dart.hit.notation)")
    }

    private func remove() {
        guard !game.turnRecords.isEmpty else { return }
        let index = rng.nextInt(below: game.turnRecords.count)
        let record = game.turnRecords[index]
        let commands = source.commands.count
        game.removeDart(at: index)
        let new = Array(source.commands.dropFirst(commands))
        if record.origin == .camera || record.origin == .scan {
            #expect(new.first == .dartDiscarded(record.id), "\(label): removal not reported")
        } else {
            #expect(!new.contains(.dartDiscarded(record.id)), "\(label): manual removal reported")
        }
        checkResync("remove", commandsBefore: commands)
        check("remove \(index)")
    }

    private func confirm() {
        guard let index = game.turnRecords.firstIndex(where: \.needsReview) else { return }
        let commands = source.commands.count
        game.confirmDart(at: index)
        #expect(!game.turnRecords[index].needsReview)
        checkResync("confirm", commandsBefore: commands)
        check("confirm \(index)")
    }

    private func undo() {
        guard game.match.canUndo else { return }
        let commands = source.commands.count
        let played = sound.played.count
        game.undo()
        #expect(Array(sound.played.dropFirst(played)) == cues(.undo), "\(label): undo sound")
        checkResync("undo", commandsBefore: commands)
        check("undo")
    }

    private func nextPlayer() {
        let before = game.match
        let commands = source.commands.count
        let played = sound.played.count
        game.requestEndTurn()
        if game.prompt == .confirmShortTurn {
            #expect(before.phase == .throwing && game.turnRecords.count < 3 && game.descriptor.confirmsShortTurn,
                    "\(label): short-turn question on a full turn")
            #expect(game.match.entries == before.entries)
            if roll(75) { game.endTurn() } else { game.prompt = nil; check("short turn declined"); return }
        }
        guard game.match.entries != before.entries else {
            #expect(!game.pending.isEmpty || before.phase == .finished, "\(label): next player refused")
            check("next player refused")
            return
        }
        var reference = before
        let feedback = reference.currentTurn.filter { $0.origin == .camera || $0.origin == .scan }
            .map { DartFeedback(id: $0.id, wasCorrected: $0.corrected) }
        let outcome = reference.endTurn()
        #expect(game.match.entries == reference.entries && game.snapshot == reference.snapshot, "\(label): endTurn differs")
        #expect(Array(sound.played.dropFirst(played)) == CueMapping.cues(for: outcome.events, context: context(of: reference)),
                "\(label) step \(step): endTurn sounds")
        let sync: GameFlowCommand = reference.phase == .throwing ? .turnBegan(expectedDarts: 3) : .turnClosed
        let expected: [GameFlowCommand] = (feedback.isEmpty ? [] : [.turnConfirmed(feedback)]) + [sync]
        #expect(Array(source.commands.dropFirst(commands)) == expected, "\(label) step \(step): endTurn commands")
        #expect(game.prompt == nil)
        check("next player")
    }

    private func sourceEvent() {
        switch rng.nextInt(below: 6) {
        case 0:
            guard !game.turnRecords.isEmpty else { return }
            let record = pick(game.turnRecords)
            game.handle(.dartDisturbed(id: record.id))
            #expect(game.turnRecords.first { $0.id == record.id }?.needsReview == true)
            check("disturbed")
        case 1:
            guard !game.turnRecords.isEmpty else { return }
            let index = rng.nextInt(below: game.turnRecords.count)
            game.handle(.dartRemoved(id: game.turnRecords[index].id, reason: .fellOut))
            #expect(game.prompt == .dartFellOut(index: index))
            if roll(70) {
                // PlayScreen.acceptPrompt: "0 ?" accepted.
                let commands = source.commands.count
                game.correctDart(at: index, to: .miss)
                checkResync("fell out", commandsBefore: commands)
                #expect(game.prompt == nil)
            } else {
                game.prompt = nil
            }
            check("fell out")
        case 2:
            let before = game.match
            let pendingWasEmpty = game.pending.isEmpty
            game.handle(.boardCleared)
            if endsTurnOnTakeout && before.phase == .turnComplete && pendingWasEmpty {
                #expect(game.match.entries.last == .endTurn && game.match.entries.count == before.entries.count + 1,
                        "\(label): takeout did not end the turn")
            } else {
                #expect(game.match.entries == before.entries && game.prompt == .boardCleared, "\(label): takeout")
            }
            check("board cleared")
        case 3:
            game.handle(.possibleMiss)
            #expect(game.prompt == .possibleMiss)
            if roll(60) {
                let count = game.match.entries.count
                let open = game.match.phase == .throwing && game.pending.isEmpty
                game.addMiss()
                if open { #expect(game.match.entries.count == count + 1) }
            }
            check("possible miss")
        case 4:
            let status: InputStatus = pick([.live, .preparing, .obstructed, .needsEmptyBoard, .needsCalibration, .paused])
            game.handle(.statusChanged(status))
            #expect(game.inputStatus == status)
            check("status \(status)")
        default:
            game.handle(.advisory(LocalizedText(fr: "Conseil", en: "Advice")))
            check("advisory")
        }
    }

    /// The play screen is left and the game resumed from the home screen (§8.6, "Reprise"): the waiting darts
    /// are lost, the journal is not; the new source is told the phase.
    private func suspendAndResume() async {
        guard !game.isFinished, let saved = storage.loadCurrentMatch() else { return }
        let commands = source.commands.count
        game.suspend()
        #expect(Array(source.commands.dropFirst(commands)) == [.gameEnded], "\(label): suspend")
        #expect(storage.loadCurrentMatch() == saved)
        await stop()
        guard let match = try? registry.restoreMatch(saved) else {
            Issue.record("\(label): saved game cannot be restored")
            return
        }
        #expect(match.snapshot == game.snapshot, "\(label): resumed game differs")
        source = GameFlowRecordingSource()
        sound = SilentSoundPlayer()
        game = PlayViewModel(match: match, source: source, sound: sound, storage: DartUI.AppStorage(store: store),
                             endsTurnOnTakeout: endsTurnOnTakeout)
        let resumed = game
        task = Task { @MainActor in await resumed.run(boardConfirmedEmpty: false) }
        while !resumed.hasStarted { await Task.yield() }
        let n = resumed.turnRecords.count
        let sync: GameFlowCommand = resumed.match.phase == .throwing ? .turnBegan(expectedDarts: 3 - n) : .turnClosed
        #expect(source.commands == [.gameStarted(boardConfirmedEmpty: false), sync], "\(label): resume \(source.commands)")
        #expect(sound.played == CueMapping.cues(for: .gameStarted(firstPlayer: resumed.snapshot.currentPlayer),
                                                context: context(of: resumed.match)), "\(label): resume announcement")
        check("resumed")
    }
}
