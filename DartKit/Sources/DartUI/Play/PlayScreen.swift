import SwiftUI
import DartCore

/// The running game: scoreboard, board, current turn, actions; the results once the game is finished.
/// The shell of `PlayContent` and `ResultsContent` (ARCHITECTURE.md §8.5, §8.6): start-up of the game, sheets,
/// the two camera covers of lot U3, the questions, leaving.
struct PlayScreen: View {
    private let game: PlayViewModel

    @Environment(AppModel.self) private var app
    /// Answer to "La cible est-elle vide ?" (§8.6, step 1); nil until asked and answered.
    @State private var boardAnswer: Bool?
    @State private var asksBoardQuestion = false
    @State private var cover: PlayCover?
    @State private var magnifier: PlayMagnifierTarget?
    @State private var asksToLeave = false

    init(game: PlayViewModel) {
        self.game = game
    }

    var body: some View {
        @Bindable var game = game
        let language = app.language
        content
            .overlay {
                if asksBoardQuestion {
                    PlayBoardQuestion { empty in
                        asksBoardQuestion = false
                        boardAnswer = empty
                    }
                }
            }
            // While a camera cover is shown, the cover presents the correction itself (lot U3): the play screen
            // under it must not try to present the same item a second time.
            .sheet(item: cover == nil ? $game.correction : .constant(nil)) { target in
                CorrectionSheet(game: game, target: target)
                    .environment(app)
                    .appLanguage(language)
                    .preferredColorScheme(.dark)
            }
            .sheet(item: $magnifier) { target in
                PlayMagnifier(target: target, geometry: game.descriptor.boardGeometry) { tap in
                    magnifier = nil
                    game.tapBoard(tap)
                } close: {
                    magnifier = nil
                }
                .appLanguage(language)
                .preferredColorScheme(.dark)
            }
            .gameCover(item: $cover) { cover in
                coverView(cover)
                    .environment(app)
                    .appLanguage(language)
                    .preferredColorScheme(.dark)
                    .tint(Theme.Palette.accent)
            }
            .onChange(of: cover) { old, new in
                // A camera screen opened from a game played by hand stops the camera when it closes (§8.7).
                if old != nil, new == nil, app.settings.inputMode == .manual {
                    let camera = app.camera
                    Task { await camera.deactivate() }
                }
            }
            .confirmationDialog(Text(L10n.string("play.quit", .game, language: language)), isPresented: $asksToLeave,
                                titleVisibility: .visible) {
                Button(L10n.string("play.quit.keep", .game, language: language)) { app.closeGame(discard: false) }
                Button(L10n.string("play.quit.discard", .game, language: language), role: .destructive) {
                    app.closeGame(discard: true)
                }
                Button(L10n.string("common.cancel", .common, language: language), role: .cancel) {}
            } message: {
                Text(L10n.string("play.quit.message", .game, language: language))
            }
            // Step 0 then step 1 of §8.6: the camera is activated BEFORE `run`, in the same task.
            .task(id: boardAnswer) { await start() }
            .task(id: game.prompt) { await expirePrompt() }
            .keepsScreenAwake(game.hasSource)
    }

    @ViewBuilder
    private var content: some View {
        if game.snapshot.phase == .finished {
            ResultsContent(snapshot: game.snapshot, players: game.match.players, canUndo: game.match.canUndo,
                           rematch: { app.rematch() }, changeGame: { app.closeGame(discard: false) },
                           undo: { game.undo() }, scrolls: true)
        } else {
            PlayContent(model: PlayContentModel(game: game), actions: actions, scrollsPlayers: true,
                        thumbnail: game.hasSource ? AnyView(ScanThumbnail(camera: app.camera) { cover = .scan }) : nil)
        }
    }

    private var actions: PlayContentActions {
        PlayContentActions(
            tapBoard: { game.tapBoard($0) },
            longPressBoard: { magnifier = PlayMagnifierTarget(point: $0.position) },
            openDart: { game.correction = .recorded(index: $0) },
            openPending: { _ in
                // Only the oldest waiting dart can be answered: the others queue behind it.
                if let head = game.pending.first { game.correction = .pending(id: head.id) }
            },
            miss: { game.addMiss() },
            undo: { game.undo() },
            nextPlayer: { game.requestEndTurn() },
            photo: { cover = .photo },
            scanView: { if game.hasSource { cover = .scan } },
            quit: leave,
            acceptPrompt: acceptPrompt,
            dismissPrompt: { game.prompt = nil },
            confirmBoardEmpty: { game.confirmBoardEmpty() })
    }

    @ViewBuilder
    private func coverView(_ cover: PlayCover) -> some View {
        switch cover {
        case .photo: PhotoModeView(game: game, camera: app.camera)
        case .scan: LiveScanView(game: game, camera: app.camera)
        }
    }

    // MARK: Start-up

    private func start() async {
        // Step 0: with a source, the session is started and the saved calibration installed before `arm`.
        if game.hasSource {
            await app.camera.activate()
        }
        // Step 1: with a valid calibration, the player says whether the board is empty, once.
        if !game.hasStarted, boardAnswer == nil, game.hasSource, !game.isFinished, case .ready = app.camera.readiness {
            asksBoardQuestion = true
            return
        }
        await game.run(boardConfirmedEmpty: boardAnswer ?? false)
    }

    // MARK: Prompts

    private func acceptPrompt() {
        switch game.prompt {
        case .possibleMiss?: game.addMiss()
        case .dartFellOut(let index)?: game.correctDart(at: index, to: .miss)
        case .confirmShortTurn?: game.endTurn()
        default: game.prompt = nil
        }
    }

    /// "Rebond ? Manqué" stays five seconds (§8.6); a dart ignored and an advice a little longer.
    private func expirePrompt() async {
        let prompt = game.prompt
        let seconds: Int
        switch prompt {
        case .possibleMiss?: seconds = 5
        case .dartIgnored?: seconds = 4
        case .advisory?: seconds = 8
        default: return
        }
        try? await Task.sleep(for: .seconds(seconds))
        if !Task.isCancelled, game.prompt == prompt { game.prompt = nil }
    }

    private func leave() {
        if game.match.canUndo {
            asksToLeave = true
        } else {
            app.closeGame(discard: false)
        }
    }
}

extension PlayContentModel {
    /// The content model of a running game.
    @MainActor
    init(game: PlayViewModel) {
        self.init(snapshot: game.snapshot, players: game.match.players, playStyle: game.descriptor.playStyle,
                  boardGeometry: game.descriptor.boardGeometry, records: game.turnRecords,
                  pending: game.pending.map(\.hit), inputStatus: game.inputStatus, prompt: game.prompt,
                  canEndTurn: game.canEndTurn, canUndo: game.match.canUndo)
    }
}

/// The two covers of the play screen, whose contents belong to lot U3 (§8.6).
private enum PlayCover: String, Identifiable {
    case photo, scan
    var id: String { rawValue }
}

struct PlayMagnifierTarget: Identifiable, Hashable {
    var point: BoardPoint
    var id: String { "\(point.x),\(point.y)" }
}

/// "La cible est-elle vide ?" (GAMES.md §2.4), asked once before the first command to the camera.
private struct PlayBoardQuestion: View {
    let answer: (Bool) -> Void

    var body: some View {
        ZStack {
            Theme.Palette.cameraScrim.ignoresSafeArea()
            VStack(alignment: .leading, spacing: Theme.Spacing.section) {
                L10n.text("play.start.question", .game)
                    .font(Theme.Typography.gameTitle)
                L10n.text("play.start.detail", .game)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Palette.textSecondary)
                PrimaryButton(L10n.text("play.start.empty", .game)) { answer(true) }
                SecondaryButton(L10n.text("play.start.notEmpty", .game)) { answer(false) }
            }
            .padding(Theme.Spacing.section + 4)
            .background(Theme.Palette.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .strokeBorder(Theme.Palette.line, lineWidth: Theme.Control.border)
            }
            .frame(maxWidth: 420)
            .padding(Theme.Metrics.compact.screenMargin)
        }
    }
}

/// The magnified view of a long press (DESIGN.md §5): the board drawn 2 pt per millimetre around the point,
/// for a precise tap.
struct PlayMagnifier: View {
    let target: PlayMagnifierTarget
    let geometry: BoardGeometry
    let tap: (BoardTap) -> Void
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.section) {
            HStack {
                Button(action: close) {
                    Image(systemName: "xmark")
                        .font(PlayCorrectionFonts.close)
                        .frame(width: Theme.Control.touchTarget, height: Theme.Control.touchTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(DesignRowButtonStyle())
                .accessibilityLabel(L10n.text("common.close", .common))
                Spacer()
            }
            GeometryReader { proxy in
                let side: CGFloat = 900
                let frame = proxy.size
                let location = DartboardView.location(of: target.point, in: CGSize(width: side, height: side), geometry: geometry)
                // Only the visible frame takes taps: the board, far larger than the frame, is not hit-testable (a
                // clip does not limit hit testing, and the board would take the tap of the "×" above it).
                DartboardView(geometry: geometry, dimsUnhighlighted: false)
                    .frame(width: side, height: side)
                    .position(x: frame.width / 2 + side / 2 - location.x, y: frame.height / 2 + side / 2 - location.y)
                    .allowsHitTesting(false)
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(SpatialTapGesture(coordinateSpace: .local).onEnded { value in
                        tap(PlayCorrectionModel.boardTap(at: value.location, frame: frame, tipLocation: location,
                                                         boardSide: side, geometry: geometry))
                    })
            }
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            L10n.text("correction.hint.board", .game)
                .font(Theme.Typography.secondary)
                .foregroundStyle(Theme.Palette.textSecondary)
        }
        .padding(Theme.Metrics.compact.screenMargin)
        .background(Theme.Palette.background.ignoresSafeArea())
    }
}
