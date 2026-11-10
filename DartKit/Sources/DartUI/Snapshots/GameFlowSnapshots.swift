import SwiftUI
import DartCore
import DartGames

extension SnapshotCatalog {
    /// Lot U2: the screens of the game flow (ARCHITECTURE.md §8.11), fed by real games of the registry.
    @MainActor static var gameFlowScreens: [SnapshotScreen] {
        typealias Frame = GameFlowSnapshotFrame
        typealias Fixtures = GameFlowFixtures
        let pads: [SnapshotDevice] = [.phonePortrait, .padLandscape]
        return [
            SnapshotScreen(id: "home", devices: pads) { device in
                Frame.framed(HomeContent(model: Fixtures.home), device)
            },
            SnapshotScreen(id: "setup-killer", devices: [.phonePortrait, .padPortrait]) { device in
                Frame.setup(Fixtures.setup(.killer, players: 4, options: ["level": "easy"]), device)
            },
            // The same screen at seven players: "Facile" is greyed with its note, "Intermédiaire" chosen.
            SnapshotScreen(id: "setup-killer-seven") { device in
                Frame.setup(Fixtures.setup(.killer, players: 7, options: ["level": "easy"]), device)
            },
            SnapshotScreen(id: "setup-killer-levels", devices: pads) { device in
                Frame.levels(Fixtures.setup(.killer, players: 4), device)
            },
            SnapshotScreen(id: "setup-x01") { device in
                Frame.setup(Fixtures.setup(.x01, players: 2), device)
            },
            SnapshotScreen(id: "players") { device in
                Frame.framed(PlayersContent(players: Fixtures.players(4)), device)
            },
            SnapshotScreen(id: "play-killer", devices: SnapshotDevice.allCases) { device in
                Frame.play(Fixtures.killerInRound4(), status: .live, device: device)
            },
            SnapshotScreen(id: "play-x01", devices: pads) { device in
                Frame.play(Fixtures.x01InRound6(), status: .live, device: device)
            },
            SnapshotScreen(id: "play-cricket") { device in
                Frame.play(Fixtures.cricketInRound3(), status: .manualOnly, device: device)
            },
            SnapshotScreen(id: "play-highscore") { device in
                Frame.play(Fixtures.highScoreInRound3(), status: .manualOnly, device: device)
            },
            SnapshotScreen(id: "play-beertap") { device in
                Frame.play(Fixtures.beerTapInRound2(), status: .manualOnly, device: device)
            },
            SnapshotScreen(id: "play-football") { device in
                Frame.play(Fixtures.footballInRound2(), status: .manualOnly, device: device)
            },
            SnapshotScreen(id: "play-radar", devices: pads) { device in
                Frame.play(Fixtures.radarInRound1(), status: .manualOnly, device: device)
            },
            SnapshotScreen(id: "play-golf") { device in
                Frame.play(Fixtures.golfOnHole4(), status: .manualOnly, device: device)
            },
            // A dart waiting for an answer and the question of a short turn.
            SnapshotScreen(id: "play-prompts") { device in
                Frame.play(Fixtures.highScoreInRound3(), status: .needsEmptyBoard, pending: [.single(7)],
                           prompt: .confirmShortTurn, device: device)
            },
            SnapshotScreen(id: "correction") { device in
                Frame.framed(PlayCorrectionContent(model: Fixtures.correction), device)
            },
            SnapshotScreen(id: "results", devices: pads) { device in
                Frame.results(Fixtures.killerFinished(), device)
            },
            SnapshotScreen(id: "results-football") { device in
                Frame.results(Fixtures.footballFinished(), device)
            },
            SnapshotScreen(id: "settings", devices: [.phonePortrait, .padPortrait]) { device in
                Frame.framed(SettingsContent(settings: .constant(AppSettings()), supportsHaptics: device == .phonePortrait), device)
            },
        ]
    }
}

/// How a game-flow content is laid in the frame of a device: the insets that the system bars take in the app
/// (the status bar and the home indicator of an iPhone), which a snapshot has not.
@MainActor
enum GameFlowSnapshotFrame {
    static func insets(_ device: SnapshotDevice) -> EdgeInsets {
        switch device {
        case .phonePortrait: return EdgeInsets(top: 44, leading: 0, bottom: 18, trailing: 0)
        case .phoneLandscape: return EdgeInsets(top: 0, leading: 44, bottom: 5, trailing: 44)
        case .padPortrait: return EdgeInsets(top: 24, leading: 0, bottom: 4, trailing: 0)
        case .padLandscape: return EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0)
        }
    }

    static func framed(_ view: some View, _ device: SnapshotDevice) -> AnyView {
        // A content taller than the screen is cut at the bottom, as the scroll view of the app shows its top.
        AnyView(view.padding(insets(device))
            .frame(width: device.size.width, height: device.size.height, alignment: .top)
            .clipped())
    }

    static func play(_ match: GameMatch?, status: InputStatus, pending: [Hit] = [], prompt: PlayPrompt? = nil,
                     device: SnapshotDevice) -> AnyView {
        guard let match else { return AnyView(EmptyView()) }
        return framed(PlayContent(model: GameFlowFixtures.model(match, status: status, pending: pending, prompt: prompt)), device)
    }

    static func results(_ match: GameMatch?, _ device: SnapshotDevice) -> AnyView {
        guard let match else { return AnyView(EmptyView()) }
        return framed(ResultsContent(snapshot: match.snapshot, players: match.players, canUndo: true), device)
    }

    static func setup(_ state: SetupState?, _ device: SnapshotDevice) -> AnyView {
        guard let state else { return AnyView(EmptyView()) }
        return framed(SetupContent(state: state), device)
    }

    static func levels(_ state: SetupState?, _ device: SnapshotDevice) -> AnyView {
        let illustrated = state?.descriptor.options.first { option in
            if case .choice(let choices) = option.kind { return choices.contains { $0.illustration != nil } }
            return false
        }
        guard let state, let option = illustrated else { return AnyView(EmptyView()) }
        return framed(SetupLevelsContent(descriptor: state.descriptor, option: option), device)
    }
}
