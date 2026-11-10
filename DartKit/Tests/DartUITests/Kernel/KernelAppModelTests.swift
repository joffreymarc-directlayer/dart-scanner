import Foundation
import Testing
import DartCore
import DartGames
import DartAudio
import DartVision
import DartTestSupport
@testable import DartUI

/// A sound service that records what the root model tells it.
@MainActor
private final class KernelSoundProbe: SoundPlaying {
    var settings = AudioSettings() {
        didSet { settingsHistory.append(settings) }
    }
    var supportsHaptics = false
    private(set) var settingsHistory: [AudioSettings] = []
    private(set) var activations: [Bool] = []
    private(set) var prepareCount = 0
    func prepare() { prepareCount += 1 }
    func play(_ cues: [AudioCue]) {}
    func stopAll() {}
    func setActive(_ active: Bool) { activations.append(active) }
}

/// Root model of lot U1 (ARCHITECTURE.md §8.4.9, §8.5, §12.1). Nothing is played here, and neither `closeGame`
/// nor `rematch` is called: they go through `PlayViewModel` methods that lot U2 writes.
@MainActor
@Suite struct KernelAppModelTests {
    private let players = testPlayers(2)

    // MARK: Environment

    @Test func previewEnvironment_isDeterministic() {
        let environment = AppEnvironment.preview()
        #expect(environment.makeSeed() == 1 && environment.makeSeed() == 1)
        #expect(environment.now() == Date(timeIntervalSinceReferenceDate: 0))
        #expect(environment.now() == environment.now())
        #expect(environment.registry.descriptors.map(\.id) == GameRegistry.standard.descriptors.map(\.id))
        #expect(environment.sound is SilentSoundPlayer)
        #expect(environment.store is InMemoryStore)
        #expect(environment.scanService is FakeScanService && environment.scanService.issue == .noCamera)
        // Each preview environment has its own store: two tests never share state.
        let other = AppEnvironment.preview()
        environment.store.set(Data([1]), forKey: "probe")
        #expect(other.store.data(forKey: "probe") == nil)
        // The registry is the one that is asked for.
        #expect(AppEnvironment.preview(registry: GameRegistry([])).registry.definitions.isEmpty)
    }

    // MARK: Construction

    @Test func appModel_isBuiltWithoutTheCameraLot() {
        let app = AppModel(environment: .preview())
        #expect(app.game == nil)
        #expect(app.camera.readiness == .unknown)
        #expect(app.camera.makeInputSource(mode: .live) == nil && app.camera.makeInputSource(mode: .photo) == nil)
        #expect(app.settings == AppSettings() && app.roster.isEmpty)
        #expect(app.path.isEmpty && app.cameraFlow == nil && app.resumableMatch == nil)
        // The camera model talks to the service of the environment, and the storage to its store.
        #expect(app.camera.service === app.environment.scanService)
        app.storage.save(roster: players)
        #expect(DartUI.AppStorage(store: app.environment.store).loadRoster() == players)
    }

    @Test func appModel_readsWhatWasSaved_andPushesTheAudioSettingsToTheSound() throws {
        var environment = AppEnvironment.preview()
        let probe = KernelSoundProbe()
        environment.sound = probe
        let storage = DartUI.AppStorage(store: environment.store)
        var settings = AppSettings()
        settings.audio.volume = 0.3
        settings.audio.callerLanguage = .en
        settings.inputMode = .camera
        settings.language = .en
        storage.save(settings)
        storage.save(roster: players)

        let app = AppModel(environment: environment)
        #expect(app.settings == settings && app.roster == players && app.language == .en)
        // The sound service starts with the saved settings, not with its own defaults.
        #expect(probe.settings == settings.audio && probe.settingsHistory == [settings.audio])
        // Building the model does not start the audio engine; `prepare()` does, once per call.
        #expect(probe.prepareCount == 0 && probe.activations.isEmpty)
        app.prepare()
        #expect(probe.prepareCount == 1)
    }

    // MARK: Settings and roster

    @Test func settings_arePersistedAndPushedToTheSound_onEveryChange() {
        var environment = AppEnvironment.preview()
        let probe = KernelSoundProbe()
        environment.sound = probe
        let app = AppModel(environment: environment)
        #expect(probe.settingsHistory == [AudioSettings()])

        app.settings.audio.volume = 0.5
        #expect(app.storage.loadSettings().audio.volume == 0.5 && probe.settings.volume == 0.5)
        app.settings.audio.callerEnabled = false
        #expect(app.storage.loadSettings() == app.settings && probe.settings == app.settings.audio)
        #expect(probe.settingsHistory.count == 3)
        // A setting outside the audio part is saved as well.
        app.settings.inputMode = .camera
        app.settings.endsTurnOnTakeout = true
        app.settings.scanMode = .photo
        #expect(app.storage.loadSettings() == app.settings)
        #expect(app.storage.loadSettings().inputMode == .camera && app.storage.loadSettings().endsTurnOnTakeout)
        // Writing the same value again changes nothing.
        let before = probe.settingsHistory.count
        app.settings = app.settings
        #expect(probe.settingsHistory.count == before)
        // A model built later over the same store starts from the saved settings.
        #expect(AppModel(environment: environment).settings == app.settings)
    }

    @Test func roster_isPersisted_onEveryChange() {
        let environment = AppEnvironment.preview()
        let app = AppModel(environment: environment)
        app.roster.append(Player(id: players[0].id, name: "Léa"))
        #expect(app.storage.loadRoster().map(\.name) == ["Léa"])
        app.roster.append(players[1])
        app.roster[0].name = "Léa B."
        #expect(app.storage.loadRoster() == app.roster && app.roster.map(\.name) == ["Léa B.", "J2"])
        app.roster.removeAll()
        #expect(app.storage.loadRoster().isEmpty)
        #expect(AppModel(environment: environment).roster.isEmpty)
    }

    // MARK: Language (§8.9)

    @Test func language_isTheSettingElseTheFirstFrenchOrEnglishPreference() {
        // The setting wins over the device.
        #expect(AppModel.language(setting: .en, preferredLanguages: ["fr-FR"]) == .en)
        #expect(AppModel.language(setting: .fr, preferredLanguages: ["en-US"]) == .fr)
        // Without a setting: the first French or English tag, most preferred first.
        #expect(AppModel.language(setting: nil, preferredLanguages: ["en-GB", "fr-FR"]) == .en)
        #expect(AppModel.language(setting: nil, preferredLanguages: ["fr-CA", "en-US"]) == .fr)
        #expect(AppModel.language(setting: nil, preferredLanguages: ["de-DE", "en-US", "fr-FR"]) == .en)
        // Neither French nor English, or nothing at all: French.
        #expect(AppModel.language(setting: nil, preferredLanguages: ["de-DE", "es-ES"]) == .fr)
        #expect(AppModel.language(setting: nil, preferredLanguages: []) == .fr)

        let app = AppModel(environment: .preview())
        // Nil follows the device: whatever it is, it is the rule above.
        #expect(app.language == AppModel.language(setting: nil, preferredLanguages: Locale.preferredLanguages))
        app.settings.language = .en
        #expect(app.language == .en)
        app.settings.language = .fr
        #expect(app.language == .fr)
        // The language of the voice is a separate setting.
        app.settings.audio.callerLanguage = .en
        #expect(app.language == .fr)
    }

    // MARK: Starting a game (§8.5)

    @Test func startGame_highScore_createsTheGame_withTheSeedAndTheDateOfTheEnvironment() throws {
        let app = AppModel(environment: .preview())
        try app.startGame(.highScore, players: players, options: [:])
        let game = try #require(app.game)
        #expect(game.snapshot.gameID == .highScore)
        #expect(game.snapshot.turn.darts.isEmpty && game.turnRecords.isEmpty && game.pending.isEmpty)
        #expect(game.snapshot.phase == .throwing && game.snapshot.currentPlayer == 0 && game.snapshot.round == 1)
        #expect(game.match.record.configuration.seed == 1)
        #expect(game.match.record.startedAt == Date(timeIntervalSinceReferenceDate: 0))
        #expect(game.match.record.configuration.players == players)
        #expect(game.match.record.entries.isEmpty)
        // No source without the camera lot: the game is played by hand.
        #expect(game.inputStatus == .manualOnly)
        // Starting a game saves nothing by itself: the journal is saved on the first accepted input (§8.10).
        #expect(app.storage.loadCurrentMatch() == nil)
    }

    @Test func startGame_twice_givesTheSameRecord() throws {
        let first = AppModel(environment: .preview())
        let second = AppModel(environment: .preview())
        try first.startGame(.highScore, players: players, options: ["rounds": 5])
        try second.startGame(.highScore, players: players, options: ["rounds": 5])
        let a = try #require(first.game?.match.record), b = try #require(second.game?.match.record)
        #expect(a == b)
        // The options are completed by the defaults of the descriptor, as in any match.
        #expect(a.configuration.options.int("rounds") == 5)
        // Byte for byte once encoded with sorted keys: nothing of the clock or of the random source leaks in.
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        #expect(try encoder.encode(a) == encoder.encode(b))
    }

    @Test func startGame_takesSeedAndDateFromTheEnvironment_notFromTheClock() throws {
        var environment = AppEnvironment.preview()
        environment.makeSeed = { 0xDEAD_BEEF_0000_0042 }
        environment.now = { Date(timeIntervalSinceReferenceDate: 123_456) }
        let app = AppModel(environment: environment)
        try app.startGame(.highScore, players: players, options: [:])
        let record = try #require(app.game?.match.record)
        #expect(record.configuration.seed == 0xDEAD_BEEF_0000_0042)
        #expect(record.startedAt == Date(timeIntervalSinceReferenceDate: 123_456))
    }

    @Test func startGame_ofAGameMissingFromTheRegistry_throwsUnknownGame() {
        let app = AppModel(environment: .preview())
        let missing = GameID("noSuchGame")
        #expect(throws: GameConfigurationError.unknownGame(missing)) {
            try app.startGame(missing, players: players, options: [:])
        }
        #expect(app.game == nil)
        // An empty registry knows no game at all, not even a real one.
        let empty = AppModel(environment: .preview(registry: GameRegistry([])))
        #expect(throws: GameConfigurationError.unknownGame(.highScore)) {
            try empty.startGame(.highScore, players: players, options: [:])
        }
        #expect(empty.game == nil)
    }

    @Test func startGame_refusedByTheRules_presentsNothing() {
        let app = AppModel(environment: .preview())
        // No silent fallback: the error of the engine comes out as it is, and no game is presented.
        #expect(throws: GameConfigurationError.self) {
            try app.startGame(.highScore, players: [], options: [:])
        }
        #expect(throws: GameConfigurationError.self) {
            try app.startGame(.highScore, players: players, options: ["noSuchOption": 1])
        }
        #expect(app.game == nil)
    }

    @Test func startGame_inCameraMode_withoutACamera_isPlayedByHand() throws {
        let app = AppModel(environment: .preview())
        app.settings.inputMode = .camera
        app.settings.scanMode = .photo
        app.settings.endsTurnOnTakeout = true
        try app.startGame(.highScore, players: players, options: [:])
        #expect(app.game?.inputStatus == .manualOnly)
        #expect(app.game?.snapshot.gameID == .highScore)
    }

    @Test func startGame_again_presentsANewGame() throws {
        let app = AppModel(environment: .preview())
        try app.startGame(.highScore, players: players, options: [:])
        let first = try #require(app.game)
        try app.startGame(.highScore, players: testPlayers(3), options: [:])
        let second = try #require(app.game)
        // `gameCover(item:)` follows the identity of the item.
        #expect(first.id != second.id && second.snapshot.players.count == 3)
    }

    // MARK: Saved game (§8.5, §8.10)

    private func savedRecord(finished: Bool) throws -> MatchRecord {
        let definition = try #require(GameRegistry.standard.definition(for: .highScore))
        let configuration = GameConfiguration(gameID: .highScore, options: ["rounds": 1], players: testPlayers(1), seed: 99)
        var match = try GameMatch(definition: definition, configuration: configuration,
                                  startedAt: Date(timeIntervalSinceReferenceDate: 5_000))
        match.play(finished ? "T20, T20, T20 |" : "T20, S5")
        return match.record
    }

    @Test func savedGame_isOfferedAndResumed_withItsOwnStartDate() throws {
        let environment = AppEnvironment.preview()
        let record = try savedRecord(finished: false)
        DartUI.AppStorage(store: environment.store).saveCurrentMatch(record)

        let app = AppModel(environment: environment)
        #expect(app.resumableMatch == record && app.game == nil)
        app.resumeSavedGame()
        let game = try #require(app.game)
        // The saved date and seed are kept: neither `environment.now()` nor `makeSeed()` is used.
        #expect(game.match.record == record)
        #expect(game.match.record.startedAt == Date(timeIntervalSinceReferenceDate: 5_000))
        #expect(game.match.record.configuration.seed == 99)
        // Resumed in the middle of a turn: the two darts are there.
        #expect(game.turnRecords.map(\.hit) == [.treble(20), .single(5)] && game.snapshot.phase == .throwing)
        #expect(game.inputStatus == .manualOnly)
    }

    @Test func savedGame_inPhaseFinished_isResumableToo() throws {
        let environment = AppEnvironment.preview()
        let record = try savedRecord(finished: true)
        DartUI.AppStorage(store: environment.store).saveCurrentMatch(record)
        let app = AppModel(environment: environment)
        #expect(app.resumableMatch == record)
        app.resumeSavedGame()
        // It reopens straight on its results.
        #expect(app.game?.snapshot.phase == .finished && app.game?.match.record == record)
    }

    @Test func resumeSavedGame_withoutASavedGame_doesNothing() {
        let app = AppModel(environment: .preview())
        app.resumeSavedGame()
        #expect(app.game == nil && app.resumableMatch == nil)
    }

    @Test func savedGame_thatTheRegistryCannotRebuild_isNotOffered() throws {
        // A game unknown to the registry (renamed, or its rules not delivered yet).
        let unknown = AppEnvironment.preview(registry: GameRegistry([]))
        DartUI.AppStorage(store: unknown.store).saveCurrentMatch(try savedRecord(finished: false))
        let app = AppModel(environment: unknown)
        #expect(app.resumableMatch == nil)
        app.resumeSavedGame()
        #expect(app.game == nil)
        // The blob itself is left alone: nothing is destroyed at launch.
        #expect(app.storage.loadCurrentMatch() != nil)
        // An unreadable blob never blocks the launch.
        let corrupted = AppEnvironment.preview()
        corrupted.store.set(Data("{".utf8), forKey: StorageKey.currentMatch)
        #expect(AppModel(environment: corrupted).resumableMatch == nil)
    }

    @Test func discardingAGame_deletesOnlyItsOwnSave() throws {
        // `closeGame(discard: true)` itself calls `suspend()`, written by lot U2: the rule behind it is tested here.
        let environment = AppEnvironment.preview()
        let older = try savedRecord(finished: false)
        environment.store.set(nil, forKey: StorageKey.currentMatch)
        let app = AppModel(environment: environment)
        try app.startGame(.highScore, players: players, options: [:])
        let current = try #require(app.game?.match.record)
        // Nothing saved: nothing to delete.
        #expect(!AppModel.savedGame(in: app.storage, isTheGameOf: current))
        // The save of an older game that the new one has not replaced yet (no dart thrown) is not its save.
        app.storage.saveCurrentMatch(older)
        #expect(!AppModel.savedGame(in: app.storage, isTheGameOf: current))
        // Once the new game has saved its journal, it is.
        var played = current
        played.entries.append(.dart(DartRecord(hit: .treble(20))))
        app.storage.saveCurrentMatch(played)
        #expect(AppModel.savedGame(in: app.storage, isTheGameOf: current))
        // Same game with another start date, or another seed: another game.
        var later = played
        later.startedAt = Date(timeIntervalSinceReferenceDate: 1)
        app.storage.saveCurrentMatch(later)
        #expect(!AppModel.savedGame(in: app.storage, isTheGameOf: current))
        var reseeded = played
        reseeded.configuration.seed = 2
        app.storage.saveCurrentMatch(reseeded)
        #expect(!AppModel.savedGame(in: app.storage, isTheGameOf: current))
    }

    // MARK: Scene phase and camera flow

    @Test func setForeground_reachesTheSoundService() {
        var environment = AppEnvironment.preview()
        let probe = KernelSoundProbe()
        environment.sound = probe
        let app = AppModel(environment: environment)
        app.setForeground(false)
        app.setForeground(true)
        #expect(probe.activations == [false, true])
        // With the minimal camera model nothing is sent to the scan service.
        #expect((environment.scanService as? FakeScanService)?.commands.isEmpty == true)
    }

    @Test func finishCameraFlow_closesTheFlow_inBothInputModes() async {
        let app = AppModel(environment: .preview())
        app.cameraFlow = .calibration
        app.finishCameraFlow()
        #expect(app.cameraFlow == nil)
        app.settings.inputMode = .camera
        app.cameraFlow = .calibration
        app.finishCameraFlow()
        #expect(app.cameraFlow == nil)
        // Navigation state is plain data.
        app.path = [.setup(.killer), .players]
        #expect(app.path.count == 2 && app.path.last == .players)
        #expect(CameraFlow.calibration.id == "calibration")
    }
}
