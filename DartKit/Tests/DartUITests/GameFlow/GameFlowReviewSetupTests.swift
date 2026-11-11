import Foundation
import Testing
import DartCore
import DartGames
import DartAudio
import DartTestSupport
@testable import DartUI

/// Review of lot U2, setup screen and settings (ARCHITECTURE.md §8.5, §8.10): every value of every option of
/// every game, for every number of players, can be chosen on the setup screen when it is not greyed out, and
/// reaches the engine unchanged; a state the screen lets the player reach always starts.
@MainActor
@Suite struct GameFlowReviewSetupTests {
    /// The values the control of an option can give (table of §8.5): both states of a toggle, the bounds and the
    /// middle of a stepper, "no limit" and the bounds of an optional stepper, every listed choice.
    private func domain(of option: OptionDescriptor) -> [OptionValue] {
        switch SetupControl(option.kind) {
        case .toggle: return [.bool(true), .bool(false)]
        case .stepper(let range):
            return [range.lowerBound, (range.lowerBound + range.upperBound) / 2, range.upperBound].map(OptionValue.int)
        case .optionalStepper(let range, _):
            return [.null] + [range.lowerBound, range.upperBound].map(OptionValue.int)
        case .segmented(let choices), .radio(let choices):
            return choices.map(\.value)
        }
    }

    private func state(_ descriptor: GameDescriptor, players count: Int, roster: [Player]) -> SetupState {
        var state = SetupState(descriptor: descriptor, roster: roster, memory: nil)
        for player in state.players { state.remove(player) }
        for player in roster.prefix(count) { state.add(player) }
        return state
    }

    @Test func everyOptionValue_isReachable_andReachesTheEngine() throws {
        let roster = testPlayers(8)
        var started = 0
        for descriptor in GameRegistry.standard.descriptors {
            for count in descriptor.players {
                for option in descriptor.options {
                    for value in domain(of: option) {
                        var state = state(descriptor, players: count, roster: roster)
                        #expect(state.playerCount == count, "\(descriptor.id.rawValue): \(count) players")
                        if case .choice(let choices) = option.kind, let choice = choices.first(where: { $0.value == value }),
                           !state.isAvailable(choice) {
                            // Greyed out with its reason: not reachable, and said why.
                            #expect(choice.unavailableNote != nil, "\(descriptor.id.rawValue).\(option.key) greyed without a note")
                            continue
                        }
                        state.set(value, for: option)
                        let where_ = "\(descriptor.id.rawValue) \(count)p \(option.key)=\(value)"
                        #expect(state.canStart, "\(where_): the screen cannot start: \(state.issues)")
                        guard state.canStart else { continue }
                        let app = AppModel(environment: .preview())
                        app.roster = roster
                        #expect(SetupScreen.start(state, app: app, language: .fr) == nil, "\(where_): refused")
                        let game = try #require(app.game, "\(where_): no game")
                        #expect(game.match.configuration.options[option.key] == value, "\(where_): option lost")
                        #expect(game.match.players == Array(roster.prefix(count)), "\(where_): players or order changed")
                        // Remembered for next time, and read back the same.
                        let memory = try #require(app.storage.loadSetup(for: descriptor.id))
                        let again = SetupState(descriptor: descriptor, roster: roster, memory: memory)
                        #expect(again.players == state.players && again.options == state.options, "\(where_): memory")
                        started += 1
                    }
                }
            }
        }
        #expect(started >= 600, "\(started)")
    }

    @Test func killer_fourLevels_andPlayerCounts() throws {
        let killer = try #require(GameRegistry.standard.definition(for: .killer)?.descriptor)
        let level = try #require(killer.option("level"))
        guard case .choice(let choices) = level.kind else { Issue.record("level is a choice"); return }
        #expect(choices.map(\.value) == ["easy", "medium", "hard", "expert"])
        // Four radio rows with their pictogram (§8.5: a choice with details is a list of radio rows).
        #expect(SetupControl(level.kind) == .radio(choices) && choices.allSatisfy { $0.illustration != nil })
        let roster = testPlayers(8)
        for count in 1...8 {
            let state = state(killer, players: count, roster: roster)
            let available = choices.filter(state.isAvailable).map(\.value)
            switch count {
            case 1: #expect(!state.canStart)
            case 2...6: #expect(available == ["easy", "medium", "hard", "expert"] && state.canStart)
            default: #expect(available == ["medium", "hard", "expert"] && state.canStart && state.options.string("level") == "medium")
            }
        }
    }

    @Test func playerColours_followThePlaceInTheGame() throws {
        // Colour = place in the game (DESIGN.md §2): the setup chips, the scoreboard, the results all use the
        // index of the player in the game, not in the roster.
        let roster = testPlayers(4)
        let x01 = try #require(GameRegistry.standard.definition(for: .x01)?.descriptor)
        var state = SetupState(descriptor: x01, roster: roster, memory: nil)
        for player in state.players { state.remove(player) }
        state.add(roster[3])
        state.add(roster[1])
        let app = AppModel(environment: .preview())
        app.roster = roster
        #expect(SetupScreen.start(state, app: app, language: .fr) == nil)
        let game = try #require(app.game)
        #expect(game.match.players == [roster[3], roster[1]])
        let model = PlayContentModel(game: game)
        #expect(model.name(of: 0) == "J4" && model.name(of: 1) == "J2")
        #expect(game.snapshot.players.map(\.player) == [0, 1])
    }

    @Test func settings_arePersisted_andPushedToTheSoundService() throws {
        let store = InMemoryStore()
        let sound = SilentSoundPlayer()
        let environment = AppEnvironment(registry: .standard, sound: sound, store: store, makeSeed: { 1 },
                                         now: { Date(timeIntervalSinceReferenceDate: 0) },
                                         scanService: FakeScanService(issue: .noCamera))
        let app = AppModel(environment: environment)
        app.settings.audio.callerLanguage = .en
        app.settings.audio.hapticsEnabled = false
        app.settings.audio.playsInSilentMode = false
        app.settings.audio.callerEnabled = false
        app.settings.audio.volume = 0.3
        app.settings.scanMode = .photo
        app.settings.endsTurnOnTakeout = true
        app.settings.language = .en
        #expect(sound.settings == app.settings.audio)
        #expect(app.language == .en)
        let relaunched = AppModel(environment: environment)
        #expect(relaunched.settings == app.settings && relaunched.language == .en)
        // The automatic end of turn reaches the next game.
        relaunched.roster = testPlayers(2)
        try relaunched.startGame(.highScore, players: relaunched.roster, options: [:])
        let game = try #require(relaunched.game)
        game.receive(gameFlowManual("T20", id: 1))
        game.receive(gameFlowManual("T20", id: 2))
        game.receive(gameFlowManual("T20", id: 3))
        game.handle(.boardCleared)
        #expect(game.snapshot.currentPlayer == 1)
    }
}
