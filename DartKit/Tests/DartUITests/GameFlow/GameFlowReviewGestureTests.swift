import Foundation
import Testing
import SwiftUI
import DartCore
import DartAudio
import DartTestSupport
@testable import DartUI
#if os(macOS)
import AppKit
#endif

#if os(macOS)
/// What a screen reported, in order.
@MainActor
private final class GameFlowReviewGestureLog {
    var closes = 0
    var levels = 0
    var quits = 0
    var photos = 0
    var deleted: [String] = []
    var boardTaps: [BoardTap] = []
    var picks: [Hit] = []
}

/// Review of lot U2: the magnified boards of the correction sheet and of the long press draw a board of 900 pt and
/// show a window of it. SwiftUI gestures only run on real events: the view is hosted in a borderless window placed
/// far off every screen and driven with synthesised mouse events (as `KernelGestureReviewTests`).
@MainActor
@Suite(.serialized) struct GameFlowReviewGestureTests {
    nonisolated private static let size = CGSize(width: 393, height: 852)

    private func wait(_ seconds: Double) {
        RunLoop.main.run(until: Date(timeIntervalSinceNow: seconds))
    }

    private func host(_ view: some View, size: CGSize = Self.size, sizeClass: UserInterfaceSizeClass = .compact) -> NSWindow {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: -30_000, y: -30_000, width: size.width, height: size.height),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: view
            .frame(width: size.width, height: size.height)
            .background(Theme.Palette.background)
            .foregroundStyle(Theme.Palette.textPrimary)
            .environment(\.colorScheme, .dark)
            .environment(\.horizontalSizeClass, sizeClass)
            .appLanguage(.fr))
        window.orderFrontRegardless()
        wait(0.3)
        return window
    }

    private func event(_ type: NSEvent.EventType, _ window: NSWindow, at point: CGPoint) -> NSEvent? {
        let location = CGPoint(x: point.x, y: window.frame.height - point.y)
        return NSEvent.mouseEvent(with: type, location: location, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                  windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)
    }

    /// Where `colour` is drawn in `view` (as `host` lays it out), in points from the top-left corner: the box of the
    /// first run of rows, from the top, that has that colour between `xs`.
    private func locate(_ view: some View, colour: (Int, Int, Int), xs: ClosedRange<Int>, size: CGSize = Self.size) -> CGRect? {
        let renderer = ImageRenderer(content: view
            .frame(width: size.width, height: size.height)
            .background(Theme.Palette.background)
            .foregroundStyle(Theme.Palette.textPrimary)
            .environment(\.colorScheme, .dark)
            .environment(\.horizontalSizeClass, .compact)
            .appLanguage(.fr))
        renderer.proposedSize = ProposedViewSize(size)
        renderer.scale = 1
        guard let image = renderer.cgImage, let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        let width = image.width, height = image.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let found: CGRect? = bytes.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width * 4, space: space,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            var box: CGRect?
            var lastRow = -1
            // Rows of the bitmap from the top of the picture (CGContext rows are stored top first).
            for y in 0..<height {
                var hit = false
                for x in xs where x < width {
                    let pixel = (y * width + x) * 4
                    if abs(Int(buffer[pixel]) - colour.0) < 12 && abs(Int(buffer[pixel + 1]) - colour.1) < 12
                        && abs(Int(buffer[pixel + 2]) - colour.2) < 12 {
                        let point = CGRect(x: x, y: y, width: 1, height: 1)
                        box = box.map { $0.union(point) } ?? point
                        hit = true
                    }
                }
                if hit { lastRow = y } else if lastRow >= 0 && y - lastRow > 6 { break }
            }
            return box
        }
        return found
    }

    /// A click at `point`, in points from the top-left corner of the view.
    private func click(_ window: NSWindow, at point: CGPoint) {
        if let down = event(.leftMouseDown, window, at: point) { window.sendEvent(down) }
        wait(0.03)
        if let up = event(.leftMouseUp, window, at: point) { window.sendEvent(up) }
        wait(0.3)
    }

    /// A drag from `start` by `offset`, in ten steps.
    private func drag(_ window: NSWindow, from start: CGPoint, by offset: CGSize) {
        if let down = event(.leftMouseDown, window, at: start) { window.sendEvent(down) }
        wait(0.05)
        for step in 1...10 {
            let point = CGPoint(x: start.x + offset.width * CGFloat(step) / 10, y: start.y + offset.height * CGFloat(step) / 10)
            if let moved = event(.leftMouseDragged, window, at: point) { window.sendEvent(moved) }
            wait(0.02)
        }
        let end = CGPoint(x: start.x + offset.width, y: start.y + offset.height)
        if let up = event(.leftMouseUp, window, at: end) { window.sendEvent(up) }
        wait(0.3)
    }

    /// A grey square of 600 px, as the evidence image of the source (§8.6).
    private func evidence() -> CGImage? {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: 600, height: 600, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.setFillColor(CGColor(red: 0.4, green: 0.4, blue: 0.4, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 600, height: 600))
        return context.makeImage()
    }

    private var correctionModel: PlayCorrectionModel {
        PlayCorrectionModel(index: 1, isPending: false, needsReview: true, detected: .treble(19),
                            choices: PlayCorrectionChoices.around(.treble(19)), choice: nil,
                            tip: BoardGeometry.standard.centre(of: .treble(19)), dartID: gameFlowID(1), evidence: nil,
                            boardGeometry: .display)
    }

    @Test func correctionSheet_theCloseButton_closes_andPutsNoPointOnTheBoard() {
        let log = GameFlowReviewGestureLog()
        let actions = PlayCorrectionActions(close: { log.closes += 1 }, pick: { log.picks.append($0) },
                                            tapBoard: { log.boardTaps.append($0) })
        let window = host(PlayCorrectionContent(model: correctionModel, actions: actions))
        // The "×" of the header: 44 pt square at the left margin (20 − 10), under the 16 pt top padding.
        click(window, at: CGPoint(x: 32, y: 16 + 22))
        #expect(log.closes == 1 && log.boardTaps.isEmpty, "close: \(log.closes), board taps: \(log.boardTaps.map(\.hit))")
        // A tap in the middle of the magnified board is the detected dart's bed (the board is centred on its tip).
        click(window, at: CGPoint(x: Self.size.width / 2, y: 16 + 44 + 14 + 22 + 14 + 140))
        #expect(log.boardTaps.map(\.hit) == [.treble(19)], "\(log.boardTaps.map(\.hit))")
        window.orderOut(nil)
    }

    @Test func correctionSheet_withAnEvidenceImage_closes_andReportsTheDrawnSide() {
        // A wide sheet in regular width (an iPad): the content is 560 pt wide, centred, with 32 pt margins, so the
        // magnifier frame is 496 × 280 and the image, 496 pt square, overflows it by 108 pt above and below, over
        // the header.
        let size = CGSize(width: 600, height: 852)
        var model = correctionModel
        let image = evidence()
        #expect(image != nil)
        model.evidence = image
        let log = GameFlowReviewGestureLog()
        var drops: [(CGSize, CGFloat)] = []
        var places: [(CGSize, CGFloat)] = []
        let actions = PlayCorrectionActions(close: { log.closes += 1 }, dropReticle: { drops.append(($0, $1)) },
                                            placeReticle: { places.append(($0, $1)) })
        let window = host(PlayCorrectionContent(model: model, actions: actions), size: size, sizeClass: .regular)
        // The "×": 20 pt of centring, 32 pt of margin, 10 pt pulled back, 22 pt to its centre.
        click(window, at: CGPoint(x: 20 + 32 - 10 + 22, y: 16 + 22))
        #expect(log.closes == 1, "the image took the tap of the close button")
        // The reticle, in the middle of the 280 pt frame, dragged 100 pt to the right: the move and the side the
        // image is drawn at go together to the conversion (`PlayCorrectionModel.movedTip`).
        drag(window, from: CGPoint(x: size.width / 2, y: 16 + 44 + 14 + 22 + 14 + 140), by: CGSize(width: 100, height: 0))
        #expect(drops.count == 1)
        if let (translation, side) = drops.first {
            #expect(abs(translation.width - 100) < 2 && abs(translation.height) < 2, "\(translation)")
            #expect(side == 496, "drawn side \(side)")
        }
        // "Touchez l'image pour déplacer la pointe": a tap 60 pt right of and 40 pt above the middle of the frame
        // puts the reticle there.
        click(window, at: CGPoint(x: size.width / 2 + 60, y: 16 + 44 + 14 + 22 + 14 + 140 - 40))
        #expect(places.count == 1, "a tap on the image does nothing")
        if let (offset, side) = places.first {
            #expect(abs(offset.width - 60) < 2 && abs(offset.height + 40) < 2 && side == 496, "\(offset), \(side)")
        }
        window.orderOut(nil)
    }

    @Test func magnifier_theCloseButton_closes_andThrowsNoDart() {
        let log = GameFlowReviewGestureLog()
        let target = PlayMagnifierTarget(point: BoardGeometry.standard.centre(of: .treble(19)) ?? .centre)
        let window = host(PlayMagnifier(target: target, geometry: .display, tap: { log.boardTaps.append($0) },
                                        close: { log.closes += 1 }))
        // The "×" of the header: 44 pt square at the 20 pt margin.
        click(window, at: CGPoint(x: 20 + 22, y: 20 + 22))
        #expect(log.closes == 1 && log.boardTaps.isEmpty, "close: \(log.closes), darts: \(log.boardTaps.map(\.hit))")
        // A tap in the middle of the frame is the pressed point (the board is centred on it).
        click(window, at: CGPoint(x: Self.size.width / 2, y: 20 + 44 + 16 + 360))
        #expect(log.boardTaps.map(\.hit) == [.treble(19)], "\(log.boardTaps.map(\.hit))")
        window.orderOut(nil)
    }

    // MARK: Touch targets of 44 pt (DESIGN.md §1)

    @Test func setup_theLevelsLink_takesTapsOver44Points() throws {
        let state = try #require(GameFlowFixtures.setup(.killer, players: 4, options: ["level": "easy"]))
        let log = GameFlowReviewGestureLog()
        let content = SetupContent(state: state, actions: SetupActions(showLevels: { _ in log.levels += 1 }))
        // "Voir les niveaux", in `accent`, right-aligned on the "Niveau" line: the first amber drawing on the right.
        let link = try #require(locate(content, colour: (0xFF, 0xA6, 0x30), xs: 300...372))
        let window = host(content)
        click(window, at: CGPoint(x: link.midX, y: link.midY))
        #expect(log.levels == 1, "the link is not at \(link)")
        // 20 pt above and below its centre is still inside a 44 pt target.
        click(window, at: CGPoint(x: link.midX, y: link.midY - 20))
        click(window, at: CGPoint(x: link.midX, y: link.midY + 20))
        #expect(log.levels == 3, "a target smaller than 44 pt: \(log.levels - 1) of 2 taps")
        window.orderOut(nil)
    }

    @Test func players_theRowButtons_takeTapsOver44Points() throws {
        let log = GameFlowReviewGestureLog()
        let content = PlayersContent(players: testPlayers(2), actions: PlayersActions(delete: { log.deleted.append($0.name) }))
        // The bin of the first row, in `boardRed`, centred in its 36 pt frame.
        let bin = try #require(locate(content, colour: (0xD8, 0x41, 0x3A), xs: 0...392))
        let window = host(content)
        click(window, at: CGPoint(x: bin.midX, y: bin.midY))
        #expect(log.deleted == ["J1"], "the bin is not at \(bin): \(log.deleted)")
        // 21 pt left and right of its centre (outside its 36 pt frame) is still inside a 44 pt target.
        click(window, at: CGPoint(x: bin.midX - 21, y: bin.midY))
        click(window, at: CGPoint(x: bin.midX + 21, y: bin.midY))
        #expect(log.deleted == ["J1", "J1", "J1"], "a target narrower than 44 pt: \(log.deleted)")
        window.orderOut(nil)
    }

    @Test func play_theQuitAndPhotoButtons_takeTapsOver44Points() throws {
        let match = try #require(GameFlowFixtures.killerInRound4())
        let game = PlayViewModel(match: match, source: nil, sound: SilentSoundPlayer(),
                                 storage: DartUI.AppStorage(store: InMemoryStore()), endsTurnOnTakeout: false)
        let log = GameFlowReviewGestureLog()
        let content = PlayContent(model: PlayContentModel(game: game),
                                  actions: PlayContentActions(photo: { log.photos += 1 }, quit: { log.quits += 1 }))
        // The "×" of the header, in `textPrimary`, the first drawing at the left margin.
        let quit = try #require(locate(content, colour: (0xF3, 0xF1, 0xEA), xs: 20...45))
        // "Photo", the camera symbol in `textPrimary`, the first drawing at the right margin.
        let photo = try #require(locate(content, colour: (0xF3, 0xF1, 0xEA), xs: 345...372))
        let window = host(content)
        click(window, at: CGPoint(x: quit.midX, y: quit.midY))
        click(window, at: CGPoint(x: photo.midX, y: photo.midY))
        #expect(log.quits == 1 && log.photos == 1, "not at \(quit), \(photo)")
        // 20 pt left and right of their centres is still inside 44 pt targets.
        click(window, at: CGPoint(x: quit.midX - 20, y: quit.midY))
        click(window, at: CGPoint(x: quit.midX + 20, y: quit.midY))
        click(window, at: CGPoint(x: photo.midX - 20, y: photo.midY))
        click(window, at: CGPoint(x: photo.midX + 20, y: photo.midY))
        #expect(log.quits == 3 && log.photos == 3, "targets narrower than 44 pt: × \(log.quits - 1) of 2, photo \(log.photos - 1) of 2")
        window.orderOut(nil)
    }
}
#endif
