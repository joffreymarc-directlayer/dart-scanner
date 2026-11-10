import Foundation
import CoreGraphics
import SwiftUI
import Testing
import DartCore
@testable import DartUI

/// Theme tokens (DESIGN.md §2) and the hand-drawn components (ARCHITECTURE.md §8.4.2): their rules as pure
/// functions, and what `ImageRenderer` draws for each of them, since they exist because the system controls
/// do not render there.
@MainActor
@Suite struct KernelDesignTests {
    private typealias RGB = KernelBitmap.RGB

    private func rgb(_ color: Color) -> RGB {
        let resolved = color.resolve(in: EnvironmentValues())
        return RGB(red: Int((resolved.red * 255).rounded()), green: Int((resolved.green * 255).rounded()),
                   blue: Int((resolved.blue * 255).rounded()))
    }

    /// A component as a phone lays it out, in a frame of the given size.
    private func render(_ view: some View, width: CGFloat, height: CGFloat, regular: Bool = false,
                        background: Color = Theme.Palette.background) throws -> KernelBitmap {
        try KernelBitmap(view.environment(\.horizontalSizeClass, regular ? .regular : .compact),
                         size: CGSize(width: width, height: height), background: background)
    }

    /// Height that a component takes by itself when it is given `width`.
    private func height(of view: some View, width: CGFloat = 300, regular: Bool = false) throws -> Int {
        let renderer = ImageRenderer(content: view.frame(width: width).environment(\.horizontalSizeClass, regular ? .regular : .compact))
        renderer.scale = 1
        return try #require(renderer.cgImage).height
    }

    // MARK: Tokens

    @Test func palette_isThePaletteOfDesignMd() {
        let tokens: [(Color, RGB)] = [
            (Theme.Palette.background, KernelPalette.background), (Theme.Palette.surface, KernelPalette.surface),
            (Theme.Palette.surfaceRaised, KernelPalette.surfaceRaised), (Theme.Palette.line, KernelPalette.line),
            (Theme.Palette.lineStrong, KernelPalette.lineStrong), (Theme.Palette.textPrimary, KernelPalette.textPrimary),
            (Theme.Palette.textSecondary, KernelPalette.textSecondary), (Theme.Palette.textTertiary, KernelPalette.textTertiary),
            (Theme.Palette.accent, KernelPalette.accent), (Theme.Palette.onAccent, KernelPalette.onAccent),
            (Theme.Palette.info, KernelPalette.info), (Theme.Palette.boardRed, KernelPalette.boardRed),
            (Theme.Palette.boardGreen, KernelPalette.boardGreen), (Theme.Palette.boardCream, KernelPalette.boardCream),
            (Theme.Palette.boardBlack, KernelPalette.boardBlack), (Theme.Palette.boardSurround, KernelPalette.boardSurround),
        ]
        for (index, token) in tokens.enumerated() {
            #expect(rgb(token.0) == token.1, "token \(index): \(rgb(token.0)) instead of \(token.1)")
        }
        // Eight player colours, in order of registration; player 1 shares the amber of the accent.
        #expect(Theme.Palette.players.map(rgb) == KernelPalette.players)
        #expect(rgb(Theme.playerColor(0)) == KernelPalette.accent)
        // The scrim over the camera image: the background at 78 %.
        let scrim = Theme.Palette.cameraScrim.resolve(in: EnvironmentValues())
        #expect(abs(Double(scrim.opacity) - 0.78) < 0.001)
        #expect(RGB(red: Int((scrim.red * 255).rounded()), green: Int((scrim.green * 255).rounded()), blue: Int((scrim.blue * 255).rounded()))
                == KernelPalette.background)
    }

    @Test func radii_spacings_andSizes_areThoseOfDesignMd() {
        #expect(Theme.Radius.card == 16 && Theme.Radius.row == 12 && Theme.Radius.badge == 8)
        #expect(Theme.Spacing.block == 12 && Theme.Spacing.section == 16)
        // iPhone: 20 pt margins, 52 pt buttons, 44 pt player rows, 14 pt darts, slots 17 + 11.
        #expect(Theme.Metrics.compact == Theme.Metrics(screenMargin: 20, buttonHeight: 52, playerRowHeight: 44, dartMarker: 14,
                                                       slotTitle: 17, slotCaption: 11))
        // iPad: 32, 56, 56, 26, 22 + 13.
        #expect(Theme.Metrics.regular == Theme.Metrics(screenMargin: 32, buttonHeight: 56, playerRowHeight: 56, dartMarker: 26,
                                                       slotTitle: 22, slotCaption: 13))
        // Touch targets of at least 44 pt (DESIGN.md §1).
        #expect(Theme.Control.touchTarget == 44)
        #expect(Theme.Control.segmentHeight + 2 * Theme.Control.segmentInset == 44)
        #expect(Theme.Control.rowHeight >= 44 && Theme.Control.radioRowHeight >= 44)
    }

    @Test func textContrast_isAtLeastFourAndAHalfToOne() {
        // DESIGN.md §1. Text colours on the surfaces they are written on.
        let pairs: [(Color, Color)] = [
            (Theme.Palette.textPrimary, Theme.Palette.background), (Theme.Palette.textPrimary, Theme.Palette.surface),
            (Theme.Palette.textPrimary, Theme.Palette.surfaceRaised), (Theme.Palette.textSecondary, Theme.Palette.background),
            (Theme.Palette.textSecondary, Theme.Palette.surface), (Theme.Palette.textTertiary, Theme.Palette.background),
            (Theme.Palette.textTertiary, Theme.Palette.boardSurround), (Theme.Palette.onAccent, Theme.Palette.accent),
            (Theme.Palette.accent, Theme.Palette.background), (Theme.Palette.info, Theme.Palette.surface),
            (Theme.Palette.background, Theme.Palette.textPrimary),
        ]
        for (index, pair) in pairs.enumerated() {
            let ratio = Theme.contrast(Theme.luminance(of: pair.0), Theme.luminance(of: pair.1))
            #expect(ratio >= 4.5, "pair \(index): \(ratio)")
        }
        // Every player colour carries dark text (the initial of a chip, a label on the board).
        for color in Theme.Palette.players {
            #expect(Theme.contrast(Theme.luminance(of: color), Theme.luminance(of: Theme.Palette.onAccent)) >= 4.5)
        }
        // Known values: white on black is 21, a colour on itself is 1.
        #expect(abs(Theme.contrast(Theme.luminance(of: .white), Theme.luminance(of: .black)) - 21) < 0.01)
        #expect(Theme.contrast(0.3, 0.3) == 1)
    }

    @Test func readableForeground_isDarkOnBrightFills_andLightOnDarkOnes() {
        #expect(Theme.readableForeground(on: Theme.Palette.accent) == Theme.Palette.onAccent)
        #expect(Theme.readableForeground(on: Theme.Palette.textPrimary) == Theme.Palette.onAccent)
        #expect(Theme.readableForeground(on: Theme.Palette.info) == Theme.Palette.onAccent)
        for color in Theme.Palette.players { #expect(Theme.readableForeground(on: color) == Theme.Palette.onAccent) }
        #expect(Theme.readableForeground(on: Theme.Palette.surfaceRaised) == Theme.Palette.textPrimary)
        #expect(Theme.readableForeground(on: Theme.Palette.background) == Theme.Palette.textPrimary)
        #expect(Theme.readableForeground(on: Theme.Palette.line) == Theme.Palette.textPrimary)
    }

    // MARK: Buttons

    @Test func primaryButton_isAmber_52PointsHigh_56InRegularWidth() throws {
        let button = PrimaryButton(Text(verbatim: "Lancer la partie")) {}
        #expect(try height(of: button) == 52)
        #expect(try height(of: button, regular: true) == 56)
        let bitmap = try render(button, width: 300, height: 52)
        // Amber from edge to edge (the corners are rounded: radius 16).
        #expect(bitmap.has(KernelPalette.accent, at: CGPoint(x: 20, y: 26)))
        #expect(bitmap.has(KernelPalette.accent, at: CGPoint(x: 150, y: 1.5)))
        #expect(bitmap.has(KernelPalette.accent, at: CGPoint(x: 298, y: 26)))
        #expect(bitmap.has(KernelPalette.background, at: CGPoint(x: 1.5, y: 1.5)))
        #expect(bitmap.has(KernelPalette.background, at: CGPoint(x: 298.5, y: 50.5)))
        // Dark text on it.
        #expect(bitmap.hasNear(KernelPalette.onAccent, at: CGPoint(x: 150, y: 26), radius: 12, tolerance: 30))
        // Disabled: no amber left, a neutral surface.
        let disabled = try render(PrimaryButton(Text(verbatim: "Scanner"), systemImage: "camera", isEnabled: false) {}, width: 300, height: 52)
        #expect(disabled.has(KernelPalette.surfaceRaised, at: CGPoint(x: 20, y: 26)))
        #expect(disabled.count(differingFrom: KernelPalette.accent, tolerance: 40) == 300 * 52)
    }

    @Test func secondaryButton_isOutlined_sameHeight() throws {
        let button = SecondaryButton(Text(verbatim: "Changer de jeu")) {}
        #expect(try height(of: button) == 52)
        #expect(try height(of: button, regular: true) == 56)
        let bitmap = try render(button, width: 300, height: 52)
        // 1 pt `line` border, transparent inside, light text.
        #expect(bitmap.has(KernelPalette.line, at: CGPoint(x: 150, y: 0.5)))
        #expect(bitmap.has(KernelPalette.line, at: CGPoint(x: 150, y: 51.5)))
        #expect(bitmap.has(KernelPalette.line, at: CGPoint(x: 0.5, y: 26)))
        #expect(bitmap.has(KernelPalette.background, at: CGPoint(x: 150, y: 1.5)))
        #expect(bitmap.has(KernelPalette.background, at: CGPoint(x: 20, y: 26)))
        #expect(bitmap.hasNear(KernelPalette.textPrimary, at: CGPoint(x: 150, y: 26), radius: 12, tolerance: 30))
    }

    @Test func buttons_drawTheirIcon() throws {
        let plain = try render(SecondaryButton(Text(verbatim: "Photo")) {}, width: 300, height: 52)
        let withIcon = try render(SecondaryButton(Text(verbatim: "Photo"), systemImage: "camera") {}, width: 300, height: 52)
        // The icon takes room on the left of the title: more light pixels, and the title starts further right.
        #expect(withIcon.count(differingFrom: KernelPalette.background, tolerance: 60) > plain.count(differingFrom: KernelPalette.background, tolerance: 60))
    }

    // MARK: Card, badge, chip, bubble

    @Test func card_isASurface_withAHairline_orTheBorderItIsGiven() throws {
        let plain = try render(Card { Color.clear.frame(width: 120, height: 80) }, width: 160, height: 120)
        // The card is centred: it spans 20...140 by 20...100.
        #expect(plain.has(KernelPalette.surface, at: CGPoint(x: 80, y: 60)))
        #expect(plain.has(KernelPalette.line, at: CGPoint(x: 80, y: 20.5)))
        #expect(plain.has(KernelPalette.surface, at: CGPoint(x: 80, y: 21.5)))
        #expect(plain.has(KernelPalette.background, at: CGPoint(x: 80, y: 19.5)))
        // Radius 16: the corner of the frame is outside the card.
        #expect(plain.has(KernelPalette.background, at: CGPoint(x: 21.5, y: 21.5)))
        // Current player: 2 pt in the player's colour.
        let bordered = try render(Card(border: Theme.playerColor(1)) { Color.clear.frame(width: 120, height: 80) }, width: 160, height: 120)
        #expect(bordered.has(KernelPalette.players[1], at: CGPoint(x: 80, y: 20.5)))
        #expect(bordered.has(KernelPalette.players[1], at: CGPoint(x: 80, y: 21.5)))
        #expect(bordered.has(KernelPalette.surface, at: CGPoint(x: 80, y: 22.5)))
        // No padding of its own: the card is exactly as large as its content.
        let renderer = ImageRenderer(content: Card { Color.clear.frame(width: 120, height: 80) })
        renderer.scale = 1
        #expect(renderer.cgImage?.width == 120 && renderer.cgImage?.height == 80)
    }

    @Test func badge_filledOrOutlined() throws {
        let filled = try render(BadgeView(Text(verbatim: "Killer"), color: Theme.Palette.accent, filled: true), width: 100, height: 30)
        let outlined = try render(BadgeView(Text(verbatim: "Killer"), color: Theme.Palette.accent), width: 100, height: 30)
        let neutral = try render(BadgeView(Text(verbatim: "Killer"), color: Theme.Palette.surfaceRaised, filled: true), width: 100, height: 30)
        // Filled: amber ground, dark text. Outlined: amber text and border on the screen background.
        #expect(filled.count(differingFrom: KernelPalette.accent) < 100 * 30 - 400)
        #expect(filled.hasNear(KernelPalette.onAccent, at: CGPoint(x: 50, y: 15), radius: 10, tolerance: 30))
        #expect(outlined.has(KernelPalette.background, at: CGPoint(x: 50, y: 6.5)) || outlined.has(KernelPalette.background, at: CGPoint(x: 50, y: 8.5)))
        #expect(outlined.hasNear(KernelPalette.accent, at: CGPoint(x: 50, y: 15), radius: 10, tolerance: 20))
        #expect(outlined.count(differingFrom: KernelPalette.accent) > filled.count(differingFrom: KernelPalette.accent))
        // A neutral fill takes light text.
        #expect(neutral.hasNear(KernelPalette.textPrimary, at: CGPoint(x: 50, y: 15), radius: 10, tolerance: 30))
        #expect(!neutral.hasNear(KernelPalette.accent, at: CGPoint(x: 50, y: 15), radius: 14, tolerance: 20))
    }

    @Test func playerChip_initial() {
        #expect(PlayerChip.initial(of: "Léa") == "L")
        #expect(PlayerChip.initial(of: "tom") == "T")
        #expect(PlayerChip.initial(of: "  émile") == "É")
        #expect(PlayerChip.initial(of: "-zoé") == "Z")
        #expect(PlayerChip.initial(of: "42") == "4")
        #expect(PlayerChip.initial(of: "") == "?")
        #expect(PlayerChip.initial(of: "   ") == "?")
        #expect(PlayerChip.initial(of: "…!") == "?")
    }

    @Test func playerChip_isADiscInThePlayersColour_followedByTheName() throws {
        for index in 0..<8 {
            let chip = try render(PlayerChip(name: "Léa", index: index, showsName: false), width: 40, height: 40)
            // The disc is 28 pt wide, centred: its left part is free of the letter.
            #expect(chip.has(KernelPalette.players[index], at: CGPoint(x: 9, y: 20)), "player \(index)")
            #expect(chip.has(KernelPalette.background, at: CGPoint(x: 3, y: 20)))
        }
        // Player 9 takes the colour of player 1 again.
        #expect(try render(PlayerChip(name: "Léa", index: 8, showsName: false), width: 40, height: 40)
            .has(KernelPalette.players[0], at: CGPoint(x: 9, y: 20)))
        // With the name, the chip is wider and shows light text.
        let named = ImageRenderer(content: PlayerChip(name: "Léa", index: 0))
        let alone = ImageRenderer(content: PlayerChip(name: "Léa", index: 0, showsName: false))
        named.scale = 1
        alone.scale = 1
        #expect(alone.cgImage?.width == 28 && alone.cgImage?.height == 28)
        #expect((named.cgImage?.width ?? 0) > 28 + 8)
    }

    @Test func scrimBubble_isTheBackgroundAt78Percent_overTheImage() throws {
        // Over a white image the scrim is easy to read: 22 % of white under 78 % of the background.
        let expected = RGB(hex: 0xFFFFFF).covered(by: KernelPalette.background, opacity: 0.78)
        let bubble = try render(ScrimBubble { Text(verbatim: "Ne bougez plus…") }, width: 240, height: 60, background: .white)
        #expect(bubble.hasNear(expected, at: CGPoint(x: 60, y: 30), radius: 3, tolerance: 4))
        #expect(bubble.hasNear(KernelPalette.textPrimary, at: CGPoint(x: 120, y: 30), radius: 12, tolerance: 30))
        #expect(bubble.has(RGB(hex: 0xFFFFFF), at: CGPoint(x: 2, y: 2)))
        // One line: at least a 44 pt target.
        let renderer = ImageRenderer(content: ScrimBubble { Text(verbatim: "Mode photo") })
        renderer.scale = 1
        #expect(renderer.cgImage?.height == 44)
    }

    @Test func bubbleShape_isAPillForOneLine_andABoxOfRadius14WhenTaller() {
        let shape = DesignBubbleShape()
        // A pill: the point at 5 pt from the corner along both axes is outside (radius 22).
        let pill = shape.path(in: CGRect(x: 0, y: 0, width: 200, height: 44))
        #expect(!pill.contains(CGPoint(x: 5, y: 5)) && pill.contains(CGPoint(x: 22, y: 22)) && pill.contains(CGPoint(x: 1, y: 22)))
        // A box: radius 14, so that same point is inside… at 5 pt it is just inside, at 2 pt it is outside.
        let box = shape.path(in: CGRect(x: 0, y: 0, width: 200, height: 90))
        #expect(box.contains(CGPoint(x: 5, y: 5)) && !box.contains(CGPoint(x: 2, y: 2)) && box.contains(CGPoint(x: 100, y: 1)))
        // A bubble narrower than it is high never asks for a radius larger than half its width.
        let narrow = shape.path(in: CGRect(x: 0, y: 0, width: 20, height: 44))
        #expect(narrow.contains(CGPoint(x: 10, y: 22)) && narrow.boundingRect == CGRect(x: 0, y: 0, width: 20, height: 44))
    }

    // MARK: Rows

    @Test func toggleRow_drawsItsSwitch_onAndOff() throws {
        #expect(try height(of: ToggleRow(Text(verbatim: "Vibrations"), isOn: .constant(true))) == 52)
        #expect(try height(of: ToggleRow(Text(verbatim: "Annonce"), subtitle: Text(verbatim: "« Triple vingt »"), isOn: .constant(true))) == 60)
        // Switch: 52 × 32 at the right end of the row, 26 pt knob at 3 pt from the edge.
        let on = try render(ToggleRow(Text(verbatim: "Vibrations"), isOn: .constant(true)), width: 300, height: 52)
        #expect(on.has(KernelPalette.accent, at: CGPoint(x: 256, y: 26)))
        #expect(on.has(KernelPalette.background, at: CGPoint(x: 284, y: 26)))
        #expect(on.has(KernelPalette.background, at: CGPoint(x: 240, y: 26)))
        #expect(on.has(KernelPalette.accent, at: CGPoint(x: 284, y: 11.5)))
        #expect(on.has(KernelPalette.background, at: CGPoint(x: 284, y: 8.5)))
        let off = try render(ToggleRow(Text(verbatim: "Vibrations"), isOn: .constant(false)), width: 300, height: 52)
        #expect(off.has(KernelPalette.line, at: CGPoint(x: 290, y: 26)))
        #expect(off.has(KernelPalette.textSecondary, at: CGPoint(x: 264, y: 26)))
        // Disabled: the same drawing, dimmed to 45 %.
        let disabled = try render(ToggleRow(Text(verbatim: "Vibrations"), isOn: .constant(true), isEnabled: false), width: 300, height: 52)
        #expect(disabled.has(KernelPalette.background.covered(by: KernelPalette.accent, opacity: 0.45), at: CGPoint(x: 256, y: 26), tolerance: 6))
        // The title is drawn, and the subtitle under it.
        #expect(on.hasNear(KernelPalette.textPrimary, at: CGPoint(x: 30, y: 26), radius: 14, tolerance: 30))
    }

    @Test func stepperRow_stepRule() {
        typealias Row = StepperRow
        // Inside the range.
        #expect(Row.step(.up, from: 3, in: 1...9, allowsNull: false) == .to(4))
        #expect(Row.step(.down, from: 3, in: 1...9, allowsNull: false) == .to(2))
        // At the bounds: the button is disabled.
        #expect(Row.step(.up, from: 9, in: 1...9, allowsNull: false) == .unavailable)
        #expect(Row.step(.down, from: 1, in: 1...9, allowsNull: false) == .unavailable)
        #expect(Row.step(.up, from: 8, in: 1...9, allowsNull: false) == .to(9))
        #expect(Row.step(.down, from: 2, in: 1...9, allowsNull: false) == .to(1))
        // With a null label: one more value below the range, stored as nil.
        #expect(Row.step(.down, from: 5, in: 5...30, allowsNull: true) == .null)
        #expect(Row.step(.down, from: 6, in: 5...30, allowsNull: true) == .to(5))
        #expect(Row.step(.up, from: nil, in: 5...30, allowsNull: true) == .to(5))
        #expect(Row.step(.down, from: nil, in: 5...30, allowsNull: true) == .unavailable)
        #expect(Row.step(.up, from: 30, in: 5...30, allowsNull: true) == .unavailable)
        // A value that was never set, without a null label: "+" gives the lower bound.
        #expect(Row.step(.up, from: nil, in: 1...9, allowsNull: false) == .to(1))
        #expect(Row.step(.down, from: nil, in: 1...9, allowsNull: false) == .unavailable)
        // A value outside the range comes back to its nearest bound, in one press.
        #expect(Row.step(.down, from: 12, in: 1...9, allowsNull: false) == .to(9))
        #expect(Row.step(.up, from: 12, in: 1...9, allowsNull: false) == .unavailable)
        #expect(Row.step(.up, from: -4, in: 1...9, allowsNull: false) == .to(1))
        #expect(Row.step(.down, from: -4, in: 1...9, allowsNull: false) == .unavailable)
        #expect(Row.step(.down, from: -4, in: 1...9, allowsNull: true) == .null)
        // A range of one value.
        #expect(Row.step(.up, from: 3, in: 3...3, allowsNull: false) == .unavailable)
        #expect(Row.step(.down, from: 3, in: 3...3, allowsNull: false) == .unavailable)
        #expect(Row.step(.down, from: 3, in: 3...3, allowsNull: true) == .null)
        // Walking up from null visits every value once, then stops; walking down comes back to null.
        var value: Int?
        var visited: [Int?] = [value]
        while case .to(let next) = Row.step(.up, from: value, in: 5...8, allowsNull: true) {
            value = next
            visited.append(value)
        }
        #expect(visited == [nil, 5, 6, 7, 8])
        var steps = 0
        loop: while true {
            switch Row.step(.down, from: value, in: 5...8, allowsNull: true) {
            case .to(let next): value = next
            case .null: value = nil
            case .unavailable: break loop
            }
            steps += 1
        }
        #expect(value == nil && steps == 4)
    }

    @Test func stepperRow_drawsTwo44PointKeys_andItsValue() throws {
        let row = StepperRow(Text(verbatim: "Vies"), value: .constant(3), range: 1...9)
        #expect(try height(of: row) == 44)
        let bitmap = try render(row, width: 300, height: 44)
        // "+" key: the last 44 pt, `surface` with a hairline.
        #expect(bitmap.has(KernelPalette.surface, at: CGPoint(x: 262, y: 6)))
        #expect(bitmap.has(KernelPalette.line, at: CGPoint(x: 278, y: 0.5)))
        #expect(bitmap.has(KernelPalette.line, at: CGPoint(x: 299.5, y: 22)))
        #expect(bitmap.hasNear(KernelPalette.textPrimary, at: CGPoint(x: 278, y: 22), radius: 6, tolerance: 30))
        // The value between the keys, then the "−" key: 8 pt gaps, a value at least 28 pt wide.
        #expect(bitmap.hasNear(KernelPalette.textPrimary, at: CGPoint(x: 234, y: 22), radius: 8, tolerance: 30))
        #expect(bitmap.has(KernelPalette.surface, at: CGPoint(x: 172, y: 6)))
        // At the lower bound "−" is dimmed: its mark is no longer light.
        let atBound = try render(StepperRow(Text(verbatim: "Vies"), value: .constant(1), range: 1...9), width: 300, height: 44)
        #expect(!atBound.hasNear(KernelPalette.textPrimary, at: CGPoint(x: 190, y: 22), radius: 6, tolerance: 30))
        #expect(bitmap.hasNear(KernelPalette.textPrimary, at: CGPoint(x: 190, y: 22), radius: 6, tolerance: 30))
        // The null value shows its label instead of a number: a wider value.
        let null = StepperRow(Text(verbatim: "Manches"), value: .constant(nil), range: 5...30, nullLabel: Text(verbatim: "Sans limite"))
        let nullBitmap = try render(null, width: 300, height: 44)
        #expect(nullBitmap.count(differingFrom: KernelPalette.background, tolerance: 60) > bitmap.count(differingFrom: KernelPalette.background, tolerance: 60))
    }

    @Test func segmentedChoice_showsTheSelectedSegment() throws {
        let options: [(value: Int, label: Text)] = [(1, Text(verbatim: "Français")), (2, Text(verbatim: "English"))]
        #expect(try height(of: SegmentedChoice(options: options, selection: .constant(1)), width: 200) == 44)
        // 200 pt wide: 3 pt inset, two segments of 95 pt, 4 pt between them.
        let first = try render(SegmentedChoice(options: options, selection: .constant(1)), width: 200, height: 44)
        #expect(first.has(KernelPalette.textPrimary, at: CGPoint(x: 10, y: 22)))
        #expect(first.has(KernelPalette.textPrimary, at: CGPoint(x: 92, y: 5)))
        #expect(first.has(KernelPalette.background, at: CGPoint(x: 110, y: 5)))
        #expect(first.has(KernelPalette.background, at: CGPoint(x: 50, y: 1.5)))
        let second = try render(SegmentedChoice(options: options, selection: .constant(2)), width: 200, height: 44)
        #expect(second.has(KernelPalette.background, at: CGPoint(x: 10, y: 22)))
        #expect(second.has(KernelPalette.textPrimary, at: CGPoint(x: 108, y: 22)))
        #expect(second.has(KernelPalette.textPrimary, at: CGPoint(x: 190, y: 22)))
        // A selection that is not an option selects nothing; four segments share the width.
        let none = try render(SegmentedChoice(options: options, selection: .constant(7)), width: 200, height: 44)
        #expect(none.count(differingFrom: KernelPalette.textPrimary, tolerance: 8) == 200 * 44)
        let four: [(value: Int, label: Text)] = (1...4).map { ($0, Text(verbatim: "\($0)")) }
        let third = try render(SegmentedChoice(options: four, selection: .constant(3)), width: 200, height: 44)
        // Four segments of 45.5 pt: the third one spans 102...147.5.
        #expect(third.has(KernelPalette.textPrimary, at: CGPoint(x: 106, y: 8)) && third.has(KernelPalette.textPrimary, at: CGPoint(x: 144, y: 8)))
        #expect(third.has(KernelPalette.background, at: CGPoint(x: 96, y: 8)) && third.has(KernelPalette.background, at: CGPoint(x: 152, y: 8)))
    }

    @Test func radioRow_selectedUnselectedAndUnavailable() throws {
        func row(selected: Bool, enabled: Bool = true) -> some View {
            RadioRow(title: Text(verbatim: "Facile"), detail: Text(verbatim: "3 cases adjacentes"),
                     note: Text(verbatim: "6 joueurs maximum en Facile"), isSelected: selected, isEnabled: enabled) {
                Color.clear.frame(width: 36, height: 36)
            } action: {}
        }
        #expect(try height(of: row(selected: true)) == 62)
        // Selected: 2 pt amber border and an amber dot in the mark (20 pt mark, 12 pt from the edge).
        let selected = try render(row(selected: true), width: 300, height: 62)
        #expect(selected.has(KernelPalette.accent, at: CGPoint(x: 150, y: 0.5)))
        #expect(selected.has(KernelPalette.accent, at: CGPoint(x: 150, y: 1.5)))
        #expect(selected.has(KernelPalette.surface, at: CGPoint(x: 150, y: 3.5)))
        #expect(selected.has(KernelPalette.accent, at: CGPoint(x: 22, y: 31)))
        // Unselected: hairline, empty mark with a grey ring.
        let unselected = try render(row(selected: false), width: 300, height: 62)
        #expect(unselected.has(KernelPalette.line, at: CGPoint(x: 150, y: 0.5)))
        #expect(unselected.has(KernelPalette.surface, at: CGPoint(x: 150, y: 1.5)))
        #expect(unselected.has(KernelPalette.surface, at: CGPoint(x: 22, y: 31)))
        #expect(unselected.has(KernelPalette.lineStrong, at: CGPoint(x: 22, y: 22)))
        // Unavailable: one more line, the reason, at full contrast while the rest is dimmed.
        let tall = try height(of: row(selected: false, enabled: false))
        #expect(tall > 62)
        let unavailable = try render(row(selected: false, enabled: false), width: 300, height: CGFloat(tall))
        #expect(unavailable.has(KernelPalette.surface.covered(by: KernelPalette.lineStrong, opacity: 0.45),
                                at: CGPoint(x: 22, y: CGFloat(tall) / 2 - 9), tolerance: 6))
        #expect(unavailable.hasNear(KernelPalette.textSecondary, at: CGPoint(x: 80, y: CGFloat(tall) - 18), radius: 8, tolerance: 20))
        // Available rows do not show the note: the row keeps its 62 pt.
        #expect(try height(of: row(selected: false)) == 62)
        // Without a pictogram the row is the same height.
        let bare = RadioRow(title: Text(verbatim: "Facile"), detail: Text(verbatim: "3 cases adjacentes"), isSelected: false) {}
        #expect(try height(of: bare) == 62)
    }

    @Test func levelSlider_levelUnderATouch_andThumbPosition() {
        // 226 pt wide: the 26 pt thumb travels over 200 pt, its centre from 13 to 213.
        #expect(LevelSlider.level(at: 13, width: 226) == 0)
        #expect(LevelSlider.level(at: 213, width: 226) == 1)
        #expect(abs(LevelSlider.level(at: 113, width: 226) - 0.5) < 1e-12)
        #expect(abs(LevelSlider.level(at: 63, width: 226) - 0.25) < 1e-12)
        // Beyond the ends: clamped.
        #expect(LevelSlider.level(at: 0, width: 226) == 0 && LevelSlider.level(at: -50, width: 226) == 0)
        #expect(LevelSlider.level(at: 226, width: 226) == 1 && LevelSlider.level(at: 900, width: 226) == 1)
        // A slider too narrow to travel, or a touch that is not a number: 0, never a trap.
        #expect(LevelSlider.level(at: 10, width: 26) == 0 && LevelSlider.level(at: 10, width: 0) == 0)
        #expect(LevelSlider.level(at: .nan, width: 226) == 0 && LevelSlider.level(at: .infinity, width: 226) == 0)
        #expect(LevelSlider.level(at: 10, width: .nan) == 0)
        // Thumb centre: the inverse.
        #expect(LevelSlider.thumbCentre(for: 0, width: 226) == 13 && LevelSlider.thumbCentre(for: 1, width: 226) == 213)
        #expect(LevelSlider.thumbCentre(for: 0.7, width: 226) == 13 + 0.7 * 200)
        #expect(LevelSlider.thumbCentre(for: -3, width: 226) == 13 && LevelSlider.thumbCentre(for: 7, width: 226) == 213)
        #expect(LevelSlider.thumbCentre(for: .nan, width: 226) == 13)
        #expect(LevelSlider.thumbCentre(for: 0.5, width: 10) == 13)
        for step in 0...20 {
            let level = Double(step) / 20
            #expect(abs(LevelSlider.level(at: LevelSlider.thumbCentre(for: level, width: 300), width: 300) - level) < 1e-12)
        }
        #expect(LevelSlider.clamped(0.4) == 0.4 && LevelSlider.clamped(-1) == 0 && LevelSlider.clamped(2) == 1 && LevelSlider.clamped(.nan) == 0)
        #expect(LevelSlider.clamped(.infinity) == 1 && LevelSlider.clamped(-.infinity) == 0)
    }

    @Test func levelSlider_drawsItsTrackAndItsThumb() throws {
        #expect(try height(of: LevelSlider(value: .constant(0.5)), width: 226) == 44)
        let half = try render(LevelSlider(value: .constant(0.5)), width: 226, height: 44)
        // Amber up to the thumb, `line` after it, an off-white thumb centred on 113.
        #expect(half.has(KernelPalette.accent, at: CGPoint(x: 40, y: 22)))
        #expect(half.has(KernelPalette.line, at: CGPoint(x: 180, y: 22)))
        #expect(half.has(KernelPalette.textPrimary, at: CGPoint(x: 113, y: 22)))
        #expect(half.has(KernelPalette.textPrimary, at: CGPoint(x: 113, y: 12.5)))
        #expect(half.has(KernelPalette.background, at: CGPoint(x: 40, y: 12)))
        let empty = try render(LevelSlider(value: .constant(0)), width: 226, height: 44)
        #expect(empty.has(KernelPalette.textPrimary, at: CGPoint(x: 13, y: 22)) && empty.has(KernelPalette.line, at: CGPoint(x: 120, y: 22)))
        let full = try render(LevelSlider(value: .constant(1)), width: 226, height: 44)
        #expect(full.has(KernelPalette.textPrimary, at: CGPoint(x: 213, y: 22)) && full.has(KernelPalette.accent, at: CGPoint(x: 120, y: 22)))
        // A level outside 0...1 is drawn at the nearest end.
        let beyond = try render(LevelSlider(value: .constant(4)), width: 226, height: 44)
        #expect(beyond.has(KernelPalette.textPrimary, at: CGPoint(x: 213, y: 22)))
    }
}
