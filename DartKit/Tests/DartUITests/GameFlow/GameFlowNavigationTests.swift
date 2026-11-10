import Foundation
import Testing
import DartCore
import DartGames
import DartAudio
import DartTestSupport
@testable import DartUI

/// The navigation of ARCHITECTURE.md §8.5 under `AppEnvironment.preview()`: home, setup, settings, roster, the
/// play screen, the results, leaving, resuming, the rematch. The game is played by hand (source `nil`) before
/// lot U3: the minimal camera never gives a source.
@MainActor
@Suite struct GameFlowNavigationTests {
    private func app() -> AppModel {
        let app = AppModel(environment: .preview())
        app.roster = testPlayers(4)
        return app
    }

    private func throwDarts(_ game: PlayViewModel, _ notations: [String], firstID: Int) {
        for (offset, notation) in notations.enumerated() {
            game.receive(gameFlowManual(notation, id: firstID + offset))
        }
    }

    @Test func home_leadsToSetupSettingsCalibrationAndTheSavedGame() throws {
        let app = app()
        let actions = HomeScreen.actions(app: app)
        actions.openGame(.killer)
        #expect(app.path == [.setup(.killer)])
        actions.settings()
        #expect(app.path == [.setup(.killer), .settings])
        actions.calibrate()
        #expect(app.cameraFlow == .calibration)
        app.finishCameraFlow()
        #expect(app.cameraFlow == nil)
        // No saved game: nothing to resume, the home screen offers none.
        actions.resume()
        #expect(app.game == nil && HomeScreen.model(app: app).resume == nil)
        // The grid is the registry, in its order.
        #expect(HomeScreen.model(app: app).descriptors.map(\.id) == GameRegistry.standard.descriptors.map(\.id))
        #expect(HomeScreen.model(app: app).descriptors.count == 14)
    }

    @Test func home_switchCameraOrManual_isSaved() async throws {
        let app = app()
        #expect(HomeScreen.model(app: app).camera == .manual)
        HomeScreen.setInputMode(.camera, app: app)
        #expect(app.settings.inputMode == .camera && app.storage.loadSettings().inputMode == .camera)
        // The minimal camera (before lot U3) stays `.unknown`: "caméra indisponible".
        #expect(HomeScreen.model(app: app).camera == .unavailable)
        HomeScreen.setInputMode(.manual, app: app)
        #expect(app.settings.inputMode == .manual && HomeScreen.model(app: app).camera == .manual)
    }

    @Test func settings_leadToCalibrationAndTheRoster() {
        let app = app()
        app.path = [.settings]
        let actions = SettingsScreen.actions(app: app)
        actions.players()
        #expect(app.path == [.settings, .players])
        actions.back()
        #expect(app.path == [.settings])
        actions.recalibrate()
        #expect(app.cameraFlow == .calibration)
    }

    @Test func setup_startsTheGame_andRemembersTheChoices() throws {
        let app = app()
        app.path = [.setup(.killer)]
        let descriptor = try #require(app.environment.registry.definition(for: .killer)?.descriptor)
        var state = SetupState(descriptor: descriptor, roster: app.roster, memory: app.storage.loadSetup(for: .killer))
        state.add(app.roster[2])
        state.set(.int(5), for: try #require(descriptor.option("lives")))
        #expect(SetupScreen.start(state, app: app, language: .fr) == nil)
        let game = try #require(app.game)
        #expect(game.snapshot.gameID == .killer && game.match.players == Array(app.roster.prefix(3)))
        #expect(game.match.configuration.options.int("lives") == 5)
        // Played by hand: no source before lot U3, the "Photo" action stays available (§8.6).
        #expect(game.inputStatus == .manualOnly && !game.hasSource)
        // Seed and date of the environment (§8.5).
        #expect(game.match.record.configuration.seed == 1 && game.match.record.startedAt == Date(timeIntervalSinceReferenceDate: 0))
        let memory = try #require(app.storage.loadSetup(for: .killer))
        #expect(memory.playerIDs == Array(app.roster.prefix(3)).map(\.id) && memory.options.int("lives") == 5)
        // Next time, the setup screen starts from these choices.
        let again = SetupState(descriptor: descriptor, roster: app.roster, memory: memory)
        #expect(again.players == state.players && again.options == state.options)
    }

    @Test func setup_refusesAGameThatCannotStart() throws {
        let app = app()
        let descriptor = try #require(app.environment.registry.definition(for: .killer)?.descriptor)
        let alone = SetupState(descriptor: descriptor, roster: [app.roster[0]], memory: nil)
        #expect(!alone.canStart)
        #expect(SetupScreen.start(alone, app: app, language: .fr) == nil && app.game == nil)
        // A game the registry does not have: the error is said in words.
        let empty = AppModel(environment: .preview(registry: GameRegistry([])))
        let state = SetupState(descriptor: descriptor, roster: testPlayers(2), memory: nil)
        #expect(SetupScreen.start(state, app: empty, language: .fr) == L10n.string("error.unknownGame", .common, language: .fr))
        #expect(empty.game == nil)
    }

    @Test func leavingAnUnfinishedGame_keepsIt_andTheHomeScreenResumesIt() throws {
        let app = app()
        try app.startGame(.highScore, players: Array(app.roster.prefix(2)), options: [:])
        let game = try #require(app.game)
        throwDarts(game, ["T20", "S5"], firstID: 1)
        let saved = game.match.record
        app.closeGame(discard: false)
        #expect(app.game == nil && game.hasEnded)
        #expect(app.resumableMatch == saved && app.storage.loadCurrentMatch() == saved)
        let resume = try #require(HomeScreen.model(app: app).resume)
        #expect(resume.round == 1 && !resume.isFinished && resume.players == ["J1", "J2"])

        HomeScreen.actions(app: app).resume()
        let resumed = try #require(app.game)
        #expect(resumed !== game && resumed.match.record == saved)
        #expect(resumed.turnRecords.map(\.id) == [gameFlowID(1), gameFlowID(2)])
        // Abandoning it deletes the save.
        app.closeGame(discard: true)
        #expect(app.game == nil && app.resumableMatch == nil && app.storage.loadCurrentMatch() == nil)
    }

    @Test func leavingTheResults_finishesTheGame_andDeletesTheSave() throws {
        let app = app()
        try app.startGame(.highScore, players: [app.roster[0]], options: ["rounds": 1])
        let game = try #require(app.game)
        throwDarts(game, ["T20", "T20", "T20"], firstID: 1)
        game.endTurn()
        #expect(game.isFinished && app.storage.loadCurrentMatch() == game.match.record)
        app.closeGame(discard: false)
        #expect(app.game == nil && game.hasEnded)
        #expect(app.storage.loadCurrentMatch() == nil && app.resumableMatch == nil)
    }

    @Test func aFinishedGameSaved_reopensOnItsResults() throws {
        let app = app()
        try app.startGame(.highScore, players: [app.roster[0]], options: ["rounds": 1])
        let game = try #require(app.game)
        throwDarts(game, ["S20"], firstID: 1)
        game.endTurn()
        // The app is closed on the results: a new model reads the store.
        let relaunched = AppModel(environment: AppEnvironment(registry: .standard, sound: SilentSoundPlayer(),
                                                              store: app.environment.store, makeSeed: { 1 },
                                                              now: { Date(timeIntervalSinceReferenceDate: 0) },
                                                              scanService: FakeScanService(issue: .noCamera)))
        #expect(relaunched.resumableMatch == game.match.record)
        #expect(HomeScreen.model(app: relaunched).resume?.isFinished == true)
        relaunched.resumeSavedGame()
        #expect(relaunched.game?.isFinished == true && relaunched.game?.snapshot.phase == .finished)
    }

    @Test func rematch_samePlayersAndOptions_newGame() throws {
        let app = app()
        let players = Array(app.roster.prefix(2))
        try app.startGame(.killer, players: players, options: ["level": "hard"])
        let first = try #require(app.game)
        // KIL-1 does not apply (seed 1 of the preview gives other zones): J1 kills J2 by hand on his zone.
        let zones = first.snapshot.players.map { $0.facts["zone"] }
        guard case .ints(let own)? = zones[0], case .ints(let other)? = zones[1] else {
            Issue.record("Killer zones are missing")
            return
        }
        throwDarts(first, ["S\(own[0])", "S\(own[0])", "S\(own[0])"], firstID: 1)
        first.endTurn()
        throwDarts(first, ["MISS", "MISS", "MISS"], firstID: 4)
        first.endTurn()
        throwDarts(first, ["S\(other[0])", "S\(other[0])", "S\(other[0])"], firstID: 7)
        #expect(first.isFinished)
        app.rematch()
        let second = try #require(app.game)
        #expect(second !== first && first.hasEnded)
        #expect(second.match.players == players && second.match.configuration.options == first.match.configuration.options)
        #expect(second.match.entries.isEmpty && second.snapshot.round == 1)
        // The finished game was finished for good: its save is gone.
        #expect(app.storage.loadCurrentMatch() == nil)
    }

    @Test func rematchOfAnUnfinishedGame_suspendsIt() throws {
        let app = app()
        try app.startGame(.highScore, players: Array(app.roster.prefix(2)), options: [:])
        let first = try #require(app.game)
        throwDarts(first, ["T20"], firstID: 1)
        app.rematch()
        #expect(first.hasEnded && !first.isFinished && app.game !== first)
        #expect(app.storage.loadCurrentMatch() == first.match.record)
    }

    @Test func roster_editsFollowTheSetup() throws {
        let app = app()
        let descriptor = try #require(app.environment.registry.definition(for: .x01)?.descriptor)
        var state = SetupState(descriptor: descriptor, roster: app.roster, memory: nil)
        #expect(state.players == Array(app.roster.prefix(2)))
        app.roster = PlayersRoster.renaming(app.roster[0], to: "  Léa ", in: app.roster)
        app.roster = PlayersRoster.moving(app.roster[3], by: -1, in: app.roster)
        app.roster.removeAll { $0.id == app.roster[1].id }
        state.follow(roster: app.roster)
        #expect(state.players.map(\.name) == ["Léa"])
        #expect(app.roster.map(\.name) == ["Léa", "J4", "J3"] && app.storage.loadRoster() == app.roster)
    }
}
