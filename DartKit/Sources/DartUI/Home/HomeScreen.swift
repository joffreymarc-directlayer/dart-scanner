import SwiftUI
import DartCore
import DartVision

/// Home: camera state, scan / manual switch, grid of the games of the registry.
/// Data-driven (ARCHITECTURE.md §8.5): one card per game of `environment.registry`, in registry order; no game
/// name is written in DartUI.
struct HomeScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(\.appLanguage) private var language

    init() {}

    var body: some View {
        ScrollView {
            HomeContent(model: model, actions: actions, showsHeader: false)
        }
        .scrollIndicators(.hidden)
        .navigationTitle(Text(verbatim: L10n.string("home.title", .game, language: language)))
        .toolbar {
            ToolbarItem(placement: .barTrailing) {
                Button { app.path.append(.settings) } label: {
                    Image(systemName: "slider.horizontal.3")
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.text("home.settings", .game))
            }
        }
        // The camera card shows the real state from the launch on (§8.5, §8.7 "Cycle de vie").
        .task {
            if app.settings.inputMode == .camera { await app.camera.activate() }
        }
    }

    private var model: HomeContentModel { Self.model(app: app) }
    private var actions: HomeContentActions { Self.actions(app: app) }

    /// The content of the home screen for the state of the app.
    static func model(app: AppModel) -> HomeContentModel {
        HomeContentModel(descriptors: app.environment.registry.descriptors,
                         camera: HomeCameraState(inputMode: app.settings.inputMode, readiness: app.camera.readiness),
                         inputMode: app.settings.inputMode, scanMode: app.settings.scanMode,
                         resume: HomeResume(record: app.resumableMatch, registry: app.environment.registry))
    }

    /// Where the home screen leads (§8.5): a game's setup, the settings, the calibration, the saved game.
    static func actions(app: AppModel) -> HomeContentActions {
        HomeContentActions(
            openGame: { app.path.append(.setup($0)) },
            settings: { app.path.append(.settings) },
            calibrate: { app.cameraFlow = .calibration },
            setInputMode: { setInputMode($0, app: app) },
            resume: { app.resumeSavedGame() })
    }

    /// The switch "Scan caméra / Saisie manuelle": the camera runs from the home screen in camera mode only.
    static func setInputMode(_ mode: InputMode, app: AppModel) {
        guard mode != app.settings.inputMode else { return }
        app.settings.inputMode = mode
        let camera = app.camera
        Task {
            switch mode {
            case .camera: await camera.activate()
            case .manual: await camera.deactivate()
            }
        }
    }
}

/// What the camera card says.
enum HomeCameraState: Hashable {
    /// Manual input chosen on the switch.
    case manual
    case ready(CalibrationQuality.Grade)
    case needsCalibration
    /// Unavailable, or not known yet (`.unknown`, the minimal camera of wave 1): manual input.
    case unavailable

    init(inputMode: InputMode, readiness: CameraModel.Readiness) {
        guard inputMode == .camera else { self = .manual; return }
        switch readiness {
        case .ready(let grade): self = .ready(grade)
        case .needsCalibration: self = .needsCalibration
        case .unavailable, .unknown: self = .unavailable
        }
    }
}

/// The saved game offered on the home screen.
struct HomeResume: Hashable {
    var gameName: LocalizedText
    var round: Int
    var isFinished: Bool
    var players: [String]

    /// Nil without a saved game, or when the registry cannot rebuild it.
    init?(record: MatchRecord?, registry: GameRegistry) {
        guard let record, let match = try? registry.restoreMatch(record) else { return nil }
        self.init(gameName: match.definition.descriptor.name, round: match.snapshot.round,
                  isFinished: match.phase == .finished, players: match.players.map(\.name))
    }

    init(gameName: LocalizedText, round: Int, isFinished: Bool, players: [String]) {
        self.gameName = gameName
        self.round = round
        self.isFinished = isFinished
        self.players = players
    }
}

struct HomeContentModel {
    var descriptors: [GameDescriptor]
    var camera: HomeCameraState
    var inputMode: InputMode
    var scanMode: ScanMode
    var resume: HomeResume?
}

struct HomeContentActions {
    var openGame: (GameID) -> Void = { _ in }
    var settings: () -> Void = {}
    var calibrate: () -> Void = {}
    var setInputMode: (InputMode) -> Void = { _ in }
    var resume: () -> Void = {}
}

/// The home screen without its shell (mock-up `Main`).
struct HomeContent: View {
    let model: HomeContentModel
    var actions = HomeContentActions()
    /// The title row of the mock-up; in the app the navigation bar carries the title and the settings button.
    var showsHeader = true

    @Environment(\.appLanguage) private var language
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        let metrics = Theme.Metrics(sizeClass)
        VStack(alignment: .leading, spacing: Theme.Spacing.section) {
            if showsHeader {
                HStack(spacing: Theme.Spacing.row) {
                    L10n.text("home.title", .game)
                        .font(HomeFonts.title)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Button(action: actions.settings) {
                        Image(systemName: "slider.horizontal.3")
                            .font(HomeFonts.icon)
                            .foregroundStyle(Theme.Palette.textPrimary)
                            .frame(width: Theme.Control.touchTarget, height: Theme.Control.touchTarget)
                            .background(Theme.Palette.surface, in: Circle())
                            .overlay { Circle().strokeBorder(Theme.Palette.line, lineWidth: Theme.Control.border) }
                    }
                    .buttonStyle(DesignRowButtonStyle())
                    .accessibilityLabel(L10n.text("home.settings", .game))
                }
                .frame(height: Theme.Control.touchTarget)
            }
            cameraCard
            if let resume = model.resume {
                resumeCard(resume)
            }
            L10n.text("home.chooseGame", .game)
                .font(HomeFonts.section)
                .foregroundStyle(Theme.Palette.textSecondary)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 10)], spacing: 10) {
                ForEach(model.descriptors) { descriptor in
                    gameCard(descriptor)
                }
            }
        }
        .padding(.horizontal, metrics.screenMargin)
        .padding(.vertical, Theme.Spacing.section)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    // MARK: Camera

    private var cameraCard: some View {
        VStack(spacing: Theme.Spacing.row) {
            HStack(spacing: Theme.Spacing.row) {
                Image(systemName: cameraIcon)
                    .font(HomeFonts.icon)
                    .foregroundStyle(cameraTint)
                    .frame(width: 40, height: 40)
                    .background(Theme.Palette.surfaceRaised, in: Circle())
                VStack(alignment: .leading, spacing: Theme.Spacing.lines) {
                    // No `minimumScaleFactor`: beside the detail line it shrank the title to about 12 pt even
                    // with room to spare (lot I1). A title too long for a narrow screen wraps instead.
                    L10n.text(cameraTitle, .game)
                        .font(HomeFonts.cardTitle)
                        .fixedSize(horizontal: false, vertical: true)
                    cameraDetailText
                        .font(Theme.Typography.secondary)
                        .foregroundStyle(Theme.Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if let action = cameraAction {
                    Button(action: actions.calibrate) {
                        L10n.text(action, .game)
                            .font(HomeFonts.link)
                            .foregroundStyle(Theme.Palette.accent)
                            .padding(.horizontal, 4)
                            .frame(minHeight: Theme.Control.touchTarget)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(DesignRowButtonStyle())
                }
            }
            .frame(minHeight: Theme.Control.touchTarget)
            HomeModeSwitch(selection: model.inputMode, select: actions.setInputMode)
        }
        .padding(14)
        .background(Theme.Palette.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .strokeBorder(Theme.Palette.line, lineWidth: Theme.Control.border)
        }
    }

    private var cameraIcon: String {
        switch model.camera {
        case .manual: return "hand.tap"
        case .ready, .needsCalibration: return "camera"
        case .unavailable: return "video.slash"
        }
    }

    private var cameraTint: Color {
        switch model.camera {
        case .ready, .manual: return Theme.Palette.info
        case .needsCalibration: return Theme.Palette.accent
        case .unavailable: return Theme.Palette.textTertiary
        }
    }

    private var cameraTitle: LocalizedStringKey {
        switch model.camera {
        case .manual: return "home.camera.manual"
        case .ready: return "home.camera.ready"
        case .needsCalibration: return "home.camera.needsCalibration"
        case .unavailable: return "home.camera.unavailable"
        }
    }

    private var cameraDetail: LocalizedStringKey {
        switch model.camera {
        case .manual: return "home.camera.manual.detail"
        case .ready: return model.scanMode == .live ? "home.camera.ready.live" : "home.camera.ready.photo"
        case .needsCalibration: return "home.camera.needsCalibration.detail"
        case .unavailable: return "home.camera.unavailable.detail"
        }
    }

    private var cameraAction: LocalizedStringKey? {
        switch model.camera {
        case .ready: return "home.camera.recalibrate"
        case .needsCalibration: return "home.camera.calibrate"
        case .manual, .unavailable: return nil
        }
    }

    /// "Le scan en direct est prêt · alignement bon": the state, and the quality of a calibration (§8.5).
    private var cameraDetailText: Text {
        guard case .ready(let grade) = model.camera else { return L10n.text(cameraDetail, .game) }
        let key: LocalizedStringKey
        switch grade {
        case .good: key = "home.grade.good"
        case .fair: key = "home.grade.fair"
        case .poor: key = "home.grade.poor"
        }
        return L10n.text(cameraDetail, .game) + Text(verbatim: " · ") + L10n.text(key, .game)
    }

    // MARK: Resume

    private func resumeCard(_ resume: HomeResume) -> some View {
        Button(action: actions.resume) {
            HStack(spacing: Theme.Spacing.row) {
                Image(systemName: resume.isFinished ? "flag.checkered" : "play.fill")
                    .font(HomeFonts.icon)
                    .foregroundStyle(Theme.Palette.onAccent)
                    .frame(width: 40, height: 40)
                    .background(Theme.Palette.accent, in: Circle())
                VStack(alignment: .leading, spacing: Theme.Spacing.lines) {
                    L10n.text("home.resume", .game)
                        .font(HomeFonts.cardTitle)
                    Text(verbatim: resumeDetail(resume))
                        .font(Theme.Typography.secondary)
                        .foregroundStyle(Theme.Palette.textSecondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right")
                    .foregroundStyle(Theme.Palette.textSecondary)
            }
            .padding(14)
            .background(Theme.Palette.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .strokeBorder(Theme.Palette.accent, lineWidth: Theme.Control.borderStrong)
            }
            .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        }
        .buttonStyle(DesignRowButtonStyle())
    }

    /// "Killer · Manche 4 · Léa, Tom, Inès".
    private func resumeDetail(_ resume: HomeResume) -> String {
        let state = resume.isFinished ? L10n.string("home.resume.results", .game, language: language)
                                      : L10n.string("home.resume.round \(resume.round)", .game, language: language)
        return ([resume.gameName[language], state] + [resume.players.joined(separator: ", ")]).joined(separator: " · ")
    }

    // MARK: Games

    private func gameCard(_ descriptor: GameDescriptor) -> some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
        return Button { actions.openGame(descriptor.id) } label: {
            VStack(alignment: .leading, spacing: 6) {
                LocalizedTextView(descriptor.shortName)
                    .font(HomeFonts.cardTitle17)
                    .foregroundStyle(Theme.Palette.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                LocalizedTextView(descriptor.summary)
                    .font(Theme.Typography.secondary)
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 86, alignment: .topLeading)
            .background(Theme.Palette.surface, in: shape)
            .overlay { shape.strokeBorder(Theme.Palette.line, lineWidth: Theme.Control.border) }
            .contentShape(shape)
        }
        .buttonStyle(DesignRowButtonStyle())
    }
}

/// "Scan caméra | Saisie manuelle" (mock-up `Main`: 44 pt segments in a 4 pt padded track).
private struct HomeModeSwitch: View {
    let selection: InputMode
    let select: (InputMode) -> Void

    var body: some View {
        HStack(spacing: 4) {
            segment(.camera, "home.mode.camera")
            segment(.manual, "home.mode.manual")
        }
        .padding(4)
        .background(Theme.Palette.background, in: RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous))
    }

    private func segment(_ mode: InputMode, _ key: LocalizedStringKey) -> some View {
        let isSelected = mode == selection
        return Button { select(mode) } label: {
            L10n.text(key, .game)
                .font(isSelected ? HomeFonts.segmentSelected : HomeFonts.segment)
                .foregroundStyle(isSelected ? Theme.Palette.background : Theme.Palette.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)
                .frame(height: Theme.Control.touchTarget)
                .background(isSelected ? Theme.Palette.textPrimary : Color.clear,
                            in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(DesignRowButtonStyle())
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

/// Sizes read on the mock-up `Main`.
enum HomeFonts {
    static let title = Font.system(size: 30, weight: .heavy)
    static let icon = Font.system(size: 19, weight: .semibold)
    static let cardTitle = Font.system(size: 15, weight: .bold)
    static let cardTitle17 = Font.system(size: 17, weight: .bold)
    static let link = Font.system(size: 15, weight: .semibold)
    static let section = Font.system(size: 15, weight: .semibold)
    static let segment = Font.system(size: 15, weight: .semibold)
    static let segmentSelected = Font.system(size: 15, weight: .bold)
}
