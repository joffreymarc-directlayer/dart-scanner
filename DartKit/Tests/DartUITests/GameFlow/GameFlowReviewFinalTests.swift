import Foundation
import Testing
import SwiftUI
import DartCore
import DartGames
import DartAudio
import DartTestSupport
@testable import DartUI
#if os(macOS)
import AppKit
#endif

/// Final review of the game flow (lots U1 and U2): screens that must work on every screen size the app allows,
/// iPhone in landscape included, and the way back to the home screen.
@MainActor
@Suite struct GameFlowReviewFinalTests {
    /// A finished Killer (Intermédiaire, 1 life, 1 arming hit) between `count` players.
    private static func finishedKiller(_ count: Int) throws -> GameMatch {
        var match = try GameRegistry.standard.match(.killer, ["level": "medium", "lives": 1, "armingHits": 1], players: count, seed: 3)
        var guardCount = 0
        while match.phase != .finished, guardCount < 2_000 {
            guardCount += 1
            if match.phase == .turnComplete { match.endTurn(); continue }
            let player = match.snapshot.currentPlayer
            let aims = match.snapshot.highlights.filter { $0.role == .target }
            if let aim = aims.first(where: { $0.owner != player }) ?? aims.first, case .sector(let number) = aim.zone {
                match.throwDart(DartRecord(hit: .single(number)))
            } else {
                match.throwDart(DartRecord(hit: .miss))
            }
        }
        return match
    }

    // MARK: Leaving the game

    /// "Changer de jeu" (and × on the play screen) leave the game for the home screen, where the player picks
    /// another game and finds the resume card; never for the set-up of the game just left.
    @Test func changeGame_afterAGameStartedFromItsSetUp_landsOnTheHomeScreen() throws {
        let app = AppModel(environment: .preview())
        app.roster = testPlayers(2)
        HomeScreen.actions(app: app).openGame(.highScore)
        #expect(app.path == [.setup(.highScore)])
        let descriptor = try #require(app.environment.registry.definition(for: .highScore)?.descriptor)
        var state = SetupState(descriptor: descriptor, roster: app.roster, memory: nil)
        state.set(.int(1), for: try #require(descriptor.option("rounds")))
        #expect(SetupScreen.start(state, app: app, language: .fr) == nil)
        let game = try #require(app.game)
        game.tapBoard(BoardTap(hit: .treble(20), position: .centre))
        game.endTurn()
        game.tapBoard(BoardTap(hit: .single(1), position: .centre))
        game.endTurn()
        #expect(game.isFinished)
        app.closeGame(discard: false) // "Changer de jeu"
        #expect(app.game == nil)
        #expect(app.path.isEmpty, "after 'Changer de jeu' the player is on \(app.path), not on the home screen")
    }

    @Test func leavingAnUnfinishedGame_keptOrAbandoned_landsOnTheHomeScreen() throws {
        for discard in [false, true] {
            let app = AppModel(environment: .preview())
            app.roster = testPlayers(2)
            HomeScreen.actions(app: app).openGame(.highScore)
            let descriptor = try #require(app.environment.registry.definition(for: .highScore)?.descriptor)
            let state = SetupState(descriptor: descriptor, roster: app.roster, memory: nil)
            #expect(SetupScreen.start(state, app: app, language: .fr) == nil)
            let game = try #require(app.game)
            game.tapBoard(BoardTap(hit: .treble(20), position: .centre))
            app.closeGame(discard: discard) // × then "Garder pour plus tard" or "Abandonner"
            #expect(app.path.isEmpty, "discard \(discard): the player is on \(app.path)")
            #expect((app.resumableMatch != nil) == !discard)
        }
    }

    // MARK: Play screen, iPhone in landscape

    /// The play screen of a game, as the app lays it out at `size` (compact width).
    private func render(_ model: PlayContentModel, size: CGSize) -> CGImage? {
        let renderer = ImageRenderer(content: PlayContent(model: model)
            .frame(width: size.width, height: size.height)
            .background(Theme.Palette.background)
            .foregroundStyle(Theme.Palette.textPrimary)
            .environment(\.colorScheme, .dark)
            .environment(\.horizontalSizeClass, .compact)
            .appLanguage(.fr))
        renderer.proposedSize = ProposedViewSize(size)
        renderer.scale = 1
        return renderer.cgImage
    }

    private func pixels(_ image: CGImage) -> [UInt8] {
        let width = image.width, height = image.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        bytes.withUnsafeMutableBytes { buffer in
            guard let space = CGColorSpace(name: CGColorSpace.sRGB),
                  let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width * 4, space: space,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        return bytes
    }

    /// Number of pixels of the colour of player 2 (`Theme.Palette.players[1]`, 0x5CB2FF) right of `minX`.
    private func secondPlayerPixels(_ image: CGImage, minX: Int) -> Int {
        let bytes = pixels(image)
        var count = 0
        for y in 0..<image.height {
            for x in minX..<image.width {
                let p = (y * image.width + x) * 4
                if abs(Int(bytes[p]) - 0x5C) < 10 && abs(Int(bytes[p + 1]) - 0xB2) < 10 && abs(Int(bytes[p + 2]) - 0xFF) < 10 {
                    count += 1
                }
            }
        }
        return count
    }

    private func model(_ id: GameID, _ options: GameOptions = [:], players: Int, play darts: String) throws -> PlayContentModel {
        var match = try GameRegistry.standard.match(id, options, players: players, seed: 1)
        match.play(darts)
        let game = PlayViewModel(match: match, source: nil, sound: SilentSoundPlayer(),
                                 storage: DartUI.AppStorage(store: InMemoryStore()), endsTurnOnTakeout: false)
        return PlayContentModel(game: game)
    }

    /// iPhone 16 in landscape: 852 × 393, safe area 734 × 372; iPhone SE in landscape: 667 × 375.
    private static let landscapeSizes = [CGSize(width: 734, height: 372), CGSize(width: 852, height: 393),
                                         CGSize(width: 667, height: 375)]

    /// Where the right column starts: after the margin (20), the board and the gap (20). On a short screen the
    /// board leaves the height of the action bar (52) and a gap (12) under it.
    private static func rightColumn(_ size: CGSize) -> Int {
        Int(20 + min(size.height - 40 - 52 - 12, (size.width - 40) * 0.6) + 20)
    }

    /// The second player's row (score template) and the second row of the Cricket grid are visible while the
    /// first player throws: the opponents' scores never disappear on an iPhone in landscape.
    @Test func landscapeIPhone_scoreTemplateAndGrid_showTheOtherPlayers() throws {
        let games: [(String, PlayContentModel)] = [
            ("x01", try model(.x01, ["startScore": 501, "outRule": "double"], players: 2, play: "T20, T19, S18 | T20, D19 | T20, S17")),
            ("cricket", try model(.cricket, players: 2, play: "T20, T19, S18 | T20, D19 | T20, S17")),
            ("highScore", try model(.highScore, players: 3, play: "T20, T19, S18 | T20, D19, S1 | T5, S3, S4 | S20")),
        ]
        for (label, model) in games {
            #expect(model.snapshot.currentPlayer == 0, "\(label): the first player throws")
            for size in Self.landscapeSizes {
                let image = try #require(render(model, size: size))
                let blue = secondPlayerPixels(image, minX: Self.rightColumn(size))
                #expect(blue > 40, "\(label) at \(size): the second player's row is not visible (\(blue) px)")
            }
        }
    }

    /// A prompt ("Volée incomplète : passer au joueur suivant ?") never covers the current card nor the list of
    /// players: with or without it, the right column is drawn the same.
    @Test func landscapeIPhone_aPromptLeavesTheRightColumnAsItIs() throws {
        let cases: [(String, PlayContentModel)] = [
            ("x01", try model(.x01, ["startScore": 501, "outRule": "double"], players: 2, play: "T20, T19, S18 | T20, D19 | T20, S17")),
            ("killer", try model(.killer, ["level": "easy"], players: 3, play: "S1, S2")),
        ]
        for (label, plain) in cases {
            var prompted = plain
            prompted.prompt = .confirmShortTurn
            for size in Self.landscapeSizes {
                let a = try #require(render(plain, size: size)), b = try #require(render(prompted, size: size))
                let pa = pixels(a), pb = pixels(b)
                let minX = Self.rightColumn(size)
                var differing = 0
                for y in 0..<a.height {
                    for x in minX..<a.width {
                        let p = (y * a.width + x) * 4
                        if pa[p] != pb[p] || pa[p + 1] != pb[p + 1] || pa[p + 2] != pb[p + 2] { differing += 1 }
                    }
                }
                #expect(differing == 0, "\(label) at \(size): the prompt changed \(differing) px of the right column")
                // The prompt is drawn somewhere: over the board.
                #expect(pa != pb, "\(label) at \(size): the prompt is not shown")
            }
        }
    }

    // MARK: Results and correction, reachable on every screen

    #if os(macOS)
    private func wait(_ seconds: Double) {
        RunLoop.main.run(until: Date(timeIntervalSinceNow: seconds))
    }

    private func host(_ view: some View, size: CGSize, vertical: UserInterfaceSizeClass) -> NSWindow {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: -30_000, y: -30_000, width: size.width, height: size.height),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: view
            .frame(width: size.width, height: size.height)
            .background(Theme.Palette.background)
            .foregroundStyle(Theme.Palette.textPrimary)
            .environment(\.colorScheme, .dark)
            .environment(\.horizontalSizeClass, .compact)
            .environment(\.verticalSizeClass, vertical)
            .appLanguage(.fr))
        window.orderFrontRegardless()
        wait(0.3)
        return window
    }

    private func click(_ window: NSWindow, at point: CGPoint) {
        let location = CGPoint(x: point.x, y: window.frame.height - point.y)
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            if let event = NSEvent.mouseEvent(with: type, location: location, modifierFlags: [],
                                              timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                                              context: nil, eventNumber: 0, clickCount: 1, pressure: 1) {
                window.sendEvent(event)
            }
            wait(0.03)
        }
        wait(0.3)
    }

    /// The results as the play screen shows them: the undo of the top row and "Changer de jeu" stay reachable,
    /// whatever the number of players and the orientation.
    @Test func results_undoAndChangeGame_areReachableOnEveryScreen() throws {
        let cases: [(String, GameMatch, CGSize, UserInterfaceSizeClass)] = [
            ("killer 8, iPhone portrait", try Self.finishedKiller(8), CGSize(width: 393, height: 759), .regular),
            ("killer 2, iPhone landscape", try Self.finishedKiller(2), CGSize(width: 734, height: 372), .compact),
            ("killer 7, iPhone SE", try Self.finishedKiller(7), CGSize(width: 375, height: 647), .regular),
        ]
        for (label, match, size, vertical) in cases {
            #expect(match.phase == .finished, "\(label)")
            var undone = 0, changed = 0, rematched = 0
            let window = host(ResultsContent(snapshot: match.snapshot, players: match.players, canUndo: true,
                                             rematch: { rematched += 1 }, changeGame: { changed += 1 }, undo: { undone += 1 },
                                             scrolls: true),
                              size: size, vertical: vertical)
            defer { window.close() }
            // Undo: 44 pt square at the right of the first row, under the top margin (16 pt).
            click(window, at: CGPoint(x: size.width - 20 - 22, y: 16 + 22))
            // "Changer de jeu": the last button, above the bottom margin (16 pt).
            click(window, at: CGPoint(x: size.width / 2, y: size.height - 16 - 26))
            #expect(undone == 1, "\(label): the undo button is not reachable")
            #expect(changed == 1, "\(label): 'Changer de jeu' is not reachable")
            #expect(rematched == 0, "\(label)")
        }
    }

    /// The correction sheet in a sheet of an iPhone in landscape (about 734 × 372) and of an iPhone SE (375 × 600):
    /// its × and "Valider" stay reachable.
    @Test func correction_closeAndConfirm_areReachableInEverySheet() throws {
        var match = try GameRegistry.standard.match(.x01, ["startScore": 501, "outRule": "double"], players: 2, seed: 1)
        match.play("T20, T19")
        let game = PlayViewModel(match: match, source: nil, sound: SilentSoundPlayer(),
                                 storage: DartUI.AppStorage(store: InMemoryStore()), endsTurnOnTakeout: false)
        let model = try #require(PlayCorrectionModel(game: game, target: .recorded(index: 1), choice: nil, evidence: nil,
                                                     reticle: .zero))
        for (size, vertical) in [(CGSize(width: 734, height: 372), UserInterfaceSizeClass.compact),
                                 (CGSize(width: 375, height: 600), .regular)] {
            var closed = 0, confirmed = 0
            let actions = PlayCorrectionActions(close: { closed += 1 }, confirm: { confirmed += 1 })
            let window = host(PlayCorrectionContent(model: model, actions: actions, scrolls: true), size: size, vertical: vertical)
            defer { window.close() }
            // ×: 44 pt square, 10 pt into the left margin, under the top margin (16 pt).
            click(window, at: CGPoint(x: 20 - 10 + 22, y: 16 + 22))
            // "Valider": the primary button above the bottom margin.
            click(window, at: CGPoint(x: size.width / 2, y: size.height - 16 - 26))
            #expect(closed == 1, "\(size): × is not reachable")
            #expect(confirmed == 1, "\(size): 'Valider' is not reachable")
        }
    }
    #endif
}
