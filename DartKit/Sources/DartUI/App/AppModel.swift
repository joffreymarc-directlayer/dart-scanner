import SwiftUI
import Observation
import DartCore
import DartGames
import DartAudio
import DartVision

/// Everything DartUI takes from outside. `live()` for the app, `preview()` for tests, previews and SnapshotTool.
@MainActor
public struct AppEnvironment {
    public var registry: GameRegistry
    public var sound: any SoundPlaying
    public var store: any KeyValueStoring
    /// Seed of a new game (GAMES.md §2.8). The only use of the system random generator in the application.
    public var makeSeed: @Sendable () -> UInt64
    /// Start date of a new game (`MatchRecord.startedAt`). `AppModel` passes `now()` to
    /// `GameMatch(definition:configuration:startedAt:)` and never relies on the default `Date()` of DartCore.
    public var now: @Sendable () -> Date
    var scanService: any ScanServicing

    /// Real services: `GameRegistry.standard`, `AudioDirector`, `UserDefaultsStore`, `ScanServiceFactory.live()`;
    /// `now` is the system clock (`Date()`).
    public static func live() -> AppEnvironment {
        AppEnvironment(registry: .standard,
                       sound: AudioDirector(),
                       store: UserDefaultsStore(),
                       makeSeed: { UInt64.random(in: UInt64.min...UInt64.max) },
                       now: { Date() },
                       scanService: ScanServiceFactory.live())
    }
    /// Silent, in-memory, `FakeScanService(issue: .noCamera)`. Deterministic: `makeSeed` always returns 1 and
    /// `now` always returns `Date(timeIntervalSinceReferenceDate: 0)`, so a test game has the same record every run.
    public static func preview(registry: GameRegistry = .standard) -> AppEnvironment {
        AppEnvironment(registry: registry,
                       sound: SilentSoundPlayer(),
                       store: InMemoryStore(),
                       makeSeed: { 1 },
                       now: { Date(timeIntervalSinceReferenceDate: 0) },
                       scanService: FakeScanService(issue: .noCamera))
    }
}

/// Root view of the application: the only symbol the app shell uses.
public struct DartScannerRootView: View {
    @State private var app: AppModel
    /// The application starts in the foreground: only a CHANGE of scene phase is reported to the model.
    @State private var isForeground = true
    @Environment(\.scenePhase) private var scenePhase

    public init(environment: AppEnvironment) {
        _app = State(initialValue: AppModel(environment: environment))
    }

    @MainActor public init() {
        self.init(environment: .live())
    }

    public var body: some View {
        @Bindable var app = app
        NavigationStack(path: $app.path) {
            HomeScreen()
                .appScreenBackground()
                .navigationDestination(for: AppRoute.self) { route in
                    destination(for: route)
                        .appScreenBackground()
                }
        }
        .gameCover(item: $app.game) { game in
            PlayScreen(game: game)
                .appScreenBackground()
                .appRootEnvironment(app)
                .interactiveDismissDisabled()
        }
        .gameCover(item: $app.cameraFlow) { flow in
            cameraFlow(flow)
                .appScreenBackground()
                .appRootEnvironment(app)
                .interactiveDismissDisabled()
        }
        .appRootEnvironment(app)
        .task { app.prepare() }
        .onChange(of: scenePhase) { _, phase in
            sceneBecame(phase)
        }
    }

    @ViewBuilder
    private func destination(for route: AppRoute) -> some View {
        switch route {
        case .setup(let game): SetupScreen(game: game)
        case .settings: SettingsScreen()
        case .players: PlayersScreen()
        case .placementGuide: PlacementGuideView()
        }
    }

    @ViewBuilder
    private func cameraFlow(_ flow: CameraFlow) -> some View {
        switch flow {
        case .calibration: CalibrationFlowView(camera: app.camera) { app.finishCameraFlow() }
        }
    }

    /// `.inactive` (a system alert, the app switcher, Control Centre) changes nothing: sound and camera are told
    /// once when the app really leaves the foreground, and once when it comes back.
    private func sceneBecame(_ phase: ScenePhase) {
        let active: Bool
        switch phase {
        case .active: active = true
        case .background: active = false
        default: return
        }
        guard active != isForeground else { return }
        isForeground = active
        app.setForeground(active)
    }
}

private extension View {
    /// What the root and every cover need (ARCHITECTURE.md §8.5). Repeated on the covers: a presented view does
    /// not inherit every modifier of its presenter.
    func appRootEnvironment(_ app: AppModel) -> some View {
        environment(app)
            .appLanguage(app.language)
            .preferredColorScheme(.dark)
            .tint(Theme.Palette.accent)
            .foregroundStyle(Theme.Palette.textPrimary)
    }

    /// The dark background of DESIGN.md §2 behind a whole screen, whatever the screen draws itself.
    func appScreenBackground() -> some View {
        frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.Palette.background.ignoresSafeArea())
    }
}

/// Destinations pushed on the root `NavigationStack`.
enum AppRoute: Hashable {
    /// Players and options of a game.
    case setup(GameID)
    case settings
    /// Roster management.
    case players
    case placementGuide
}

/// Full-screen camera flows presented over the home screen.
enum CameraFlow: String, Identifiable {
    case calibration
    var id: String { rawValue }
}

/// Root state: settings, roster, navigation, the running game.
@MainActor
@Observable
final class AppModel {
    let environment: AppEnvironment
    let storage: AppStorage
    let camera: CameraModel
    /// Persisted and pushed to the sound service on every change.
    var settings: AppSettings {
        didSet {
            guard settings != oldValue else { return }
            storage.save(settings)
            environment.sound.settings = settings.audio
        }
    }
    var roster: [Player] {
        didSet {
            guard roster != oldValue else { return }
            storage.save(roster: roster)
        }
    }
    var path: [AppRoute] = []
    /// The running game, presented with `gameCover(item:)`.
    var game: PlayViewModel?
    var cameraFlow: CameraFlow?
    /// A saved game exists and can be resumed from the home screen. A game saved in phase `finished` (the app
    /// was closed on the results screen) is resumable too: it reopens straight on its results.
    private(set) var resumableMatch: MatchRecord?

    var language: AppLanguage {
        Self.language(setting: settings.language, preferredLanguages: Locale.preferredLanguages)
    }

    /// The rule behind `language` (ARCHITECTURE.md §8.9): the language chosen in the settings, else the first
    /// French or English tag of the preferred languages of the device, else French.
    static func language(setting: AppLanguage?, preferredLanguages: [String]) -> AppLanguage {
        setting ?? AppLanguage(preferredLanguages: preferredLanguages)
    }

    init(environment: AppEnvironment) {
        let storage = AppStorage(store: environment.store)
        let settings = storage.loadSettings()
        self.environment = environment
        self.storage = storage
        self.camera = CameraModel(service: environment.scanService, storage: storage)
        self.settings = settings
        self.roster = storage.loadRoster()
        self.resumableMatch = Self.resumableMatch(in: storage, registry: environment.registry)
        environment.sound.settings = settings.audio
    }

    /// Builds the audio engine and warms the voice up (`SoundPlaying.prepare()` is idempotent). Called once by
    /// the root view when it appears, so that creating an `AppModel` stays cheap.
    func prepare() {
        environment.sound.prepare()
    }

    /// Creates the match (seed from `environment.makeSeed()`, start date from `environment.now()`), the input
    /// source for the current input mode, and presents the play screen. Throws `GameConfigurationError`
    /// (`.unknownGame` when the registry has no such game).
    func startGame(_ game: GameID, players: [Player], options: GameOptions) throws {
        let configuration = GameConfiguration(gameID: game, options: options, players: players,
                                              seed: environment.makeSeed())
        present(try makeMatch(configuration))
    }

    /// Rebuilds `resumableMatch` with `registry.restoreMatch` (its saved start date is kept) and presents it,
    /// whatever its phase.
    func resumeSavedGame() {
        guard let record = resumableMatch else { return }
        guard let match = try? environment.registry.restoreMatch(record) else {
            // The registry no longer knows how to play this record: stop offering it.
            resumableMatch = nil
            return
        }
        present(match)
    }

    /// Same players and options, new seed and new start date, created as in `startGame`.
    /// Calls `game.finishGame()` on the game that ends.
    func rematch() {
        guard let ending = game else { return }
        let configuration = ending.rematchConfiguration(seed: environment.makeSeed())
        // A game that ran can be created again; if it cannot, the game on screen stays as it is.
        guard let match = try? makeMatch(configuration) else { return }
        end(ending, discard: false)
        present(match)
    }

    /// Closes the play screen. Finished game: `game.finishGame()`. Unfinished game: `game.suspend()`, and
    /// `discard` also deletes the saved game. The player lands on the home screen (§8.5, "Sortie"), where another
    /// game is chosen and a kept game is resumed: never on the set-up of the game just left.
    func closeGame(discard: Bool) {
        guard let ending = game else { return }
        end(ending, discard: discard)
        game = nil
        path = []
        resumableMatch = Self.resumableMatch(in: storage, registry: environment.registry)
    }

    /// Scene phase changes: `sound.setActive(active)` and `camera.setForeground(active)`.
    func setForeground(_ active: Bool) {
        environment.sound.setActive(active)
        camera.setForeground(active)
    }

    /// Closes a camera flow presented over the home screen. In manual input mode the camera only runs on a camera
    /// screen (ARCHITECTURE.md §8.7, "Cycle de vie"): it is stopped again here. In camera mode it keeps running.
    func finishCameraFlow() {
        cameraFlow = nil
        guard settings.inputMode == .manual else { return }
        let camera = camera
        Task { await camera.deactivate() }
    }

    // MARK: Private

    /// A NEW game is always created here: the start date is `environment.now()`, never the default `Date()` of
    /// `GameMatch.init`, and never `registry.makeMatch(_:)`, which uses it (ARCHITECTURE.md §8.5).
    private func makeMatch(_ configuration: GameConfiguration) throws -> GameMatch {
        guard let definition = environment.registry.definition(for: configuration.gameID) else {
            throw GameConfigurationError.unknownGame(configuration.gameID)
        }
        return try GameMatch(definition: definition, configuration: configuration, startedAt: environment.now())
    }

    /// The same for a new, a resumed and a rematch game: a source only in camera mode, and only when the camera
    /// gives one (`nil`: the game is played by manual input).
    private func present(_ match: GameMatch) {
        let source = settings.inputMode == .camera ? camera.makeInputSource(mode: settings.scanMode) : nil
        game = PlayViewModel(match: match, source: source, sound: environment.sound, storage: storage,
                             endsTurnOnTakeout: settings.endsTurnOnTakeout)
    }

    /// What leaving a game does to it (ARCHITECTURE.md §8.5, §8.6): a finished game is finished for good
    /// (feedback, source stopped, save deleted); an unfinished one is suspended and stays saved unless discarded.
    private func end(_ ending: PlayViewModel, discard: Bool) {
        if ending.isFinished {
            ending.finishGame()
        } else {
            ending.suspend()
            if discard && Self.savedGame(in: storage, isTheGameOf: ending.match.record) { storage.saveCurrentMatch(nil) }
        }
    }

    /// True when the game saved in `storage` is the game of `record` (same configuration, same start date).
    /// A new game is saved from its first accepted input on (§8.10): until then the save is still the one of an
    /// older game, which discarding the new game must not delete.
    static func savedGame(in storage: AppStorage, isTheGameOf record: MatchRecord) -> Bool {
        guard let saved = storage.loadCurrentMatch() else { return false }
        return saved.configuration == record.configuration && saved.startedAt == record.startedAt
    }

    /// The saved game, when the registry can rebuild it. A record of a game that the registry does not know (or
    /// can no longer create) is not offered: the home screen never shows a "resume" that would do nothing.
    private static func resumableMatch(in storage: AppStorage, registry: GameRegistry) -> MatchRecord? {
        guard let record = storage.loadCurrentMatch(), (try? registry.restoreMatch(record)) != nil else { return nil }
        return record
    }
}
