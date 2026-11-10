import Foundation
import CoreGraphics
import SwiftUI
import Testing
import DartCore
@testable import DartUI

/// The drawing of the board (DESIGN.md §3 and §4, ARCHITECTURE.md §8.4.3), checked on the pixels that
/// `ImageRenderer` produces: what is drawn under a point is what a tap on that point scores.
@MainActor
@Suite struct KernelBoardDrawingTests {
    private typealias RGB = KernelBitmap.RGB
    private let size = CGSize(width: 400, height: 400)

    /// The board as a phone draws it (compact width: 14 pt dart markers).
    private func render(_ board: DartboardView, size: CGSize? = nil) throws -> KernelBitmap {
        try KernelBitmap(board.environment(\.horizontalSizeClass, .compact), size: size ?? self.size)
    }

    /// Colour of an unhighlighted bed on the mock-ups: the 20 is black with red rings, then every other sector.
    private func bedColor(_ bed: BoardBed) -> RGB {
        let dark = bed.sector % 2 == 0
        switch bed.band {
        case .innerBull: return KernelPalette.boardRed
        case .outerBull: return KernelPalette.boardGreen
        case .innerSingle, .outerSingle: return dark ? KernelPalette.boardBlack : KernelPalette.boardCream
        case .treble, .double: return dark ? KernelPalette.boardRed : KernelPalette.boardGreen
        }
    }

    /// Where the middle of a bed is drawn.
    private func middle(_ bed: BoardBed, geometry: BoardGeometry, size: CGSize? = nil) -> CGPoint {
        DartboardView.location(of: bed.centre(in: .standard), in: size ?? self.size, geometry: geometry)
    }

    private func dimmed(_ color: RGB) -> RGB {
        color.covered(by: KernelPalette.background, opacity: 0.62)
    }

    private func sector(_ number: Int) -> Int {
        BoardGeometry.standardSectorOrder.firstIndex(of: number) ?? 0
    }

    // MARK: The bare board

    @Test func everyBed_isDrawnInItsColour_whereATapScoresIt_inBothGeometries() throws {
        for geometry in [BoardGeometry.display, .standard] {
            let bitmap = try render(DartboardView(geometry: geometry))
            for bed in BoardBed.all {
                let point = middle(bed, geometry: geometry)
                #expect(bitmap.has(bedColor(bed), at: point), "\(bed): \(bitmap.color(at: point)) instead of \(bedColor(bed))")
                // The same point, tapped, scores this bed.
                #expect(DartboardView.tap(at: point, in: size, geometry: geometry).hit == bed.hit(in: geometry))
            }
        }
    }

    @Test func twenty_isOnTop_blackWithRedDoubleAndTreble() throws {
        let bitmap = try render(DartboardView())
        // On the vertical axis above the centre, from the outside in (thick rings: 160.1–173.6 and 97–110.5 mm).
        func up(_ millimetres: Double) -> CGPoint { CGPoint(x: 200, y: 200 - millimetres * 200 / 225.5) }
        #expect(bitmap.has(KernelPalette.boardRed, at: up(167)))
        #expect(bitmap.has(KernelPalette.boardBlack, at: up(135)))
        #expect(bitmap.has(KernelPalette.boardRed, at: up(104)))
        #expect(bitmap.has(KernelPalette.boardBlack, at: up(60)))
        #expect(bitmap.has(KernelPalette.boardGreen, at: up(11)))
        #expect(bitmap.has(KernelPalette.boardRed, at: up(0)))
        // The 1, clockwise next to it, is cream with green rings.
        let one = BoardBed(band: .outerSingle, sector: 1), oneDouble = BoardBed(band: .double, sector: 1)
        #expect(bitmap.has(KernelPalette.boardCream, at: middle(one, geometry: .display)))
        #expect(bitmap.has(KernelPalette.boardGreen, at: middle(oneDouble, geometry: .display)))
    }

    @Test func thickRings_areDrawnThicker_thanRegulationOnes() throws {
        let display = try render(DartboardView(geometry: .display))
        let standard = try render(DartboardView(geometry: .standard))
        func up(_ millimetres: Double) -> CGPoint { CGPoint(x: 200, y: 200 - millimetres * 200 / 225.5) }
        // 98 mm and 161 mm: ring on the thick drawing, single on the regulation one. 172 mm: ring, then number ring.
        #expect(display.has(KernelPalette.boardRed, at: up(98.5)) && standard.has(KernelPalette.boardBlack, at: up(97.5)))
        #expect(display.has(KernelPalette.boardRed, at: up(161.5)) && standard.has(KernelPalette.boardBlack, at: up(160.5)))
        #expect(display.has(KernelPalette.boardRed, at: up(172)) && standard.has(KernelPalette.boardSurround, at: up(172)))
        // Same bulls in both.
        #expect(display.has(KernelPalette.boardGreen, at: up(11)) && standard.has(KernelPalette.boardGreen, at: up(11)))
        #expect(display.has(KernelPalette.boardBlack, at: up(18)) && standard.has(KernelPalette.boardBlack, at: up(18)))
    }

    @Test func numberRing_isTheDarkSurround_andTheCornersAreTheScreenBackground() throws {
        let bitmap = try render(DartboardView(showsNumbers: false))
        // Between the double and the edge, on a wire angle (no number there anyway).
        let ring = DartboardView.location(of: BoardPoint(radius: 215, clockwiseDegrees: 9), in: size, geometry: .standard)
        #expect(bitmap.has(KernelPalette.boardSurround, at: ring))
        #expect(bitmap.has(KernelPalette.background, at: CGPoint(x: 3, y: 3)))
        #expect(bitmap.has(KernelPalette.background, at: CGPoint(x: 396, y: 396)))
        // The numbers are drawn on that ring: with them, some pixels of it are lighter.
        let numbered = try render(DartboardView())
        let twenty = DartboardView.location(of: BoardPoint(radius: 200, clockwiseDegrees: 0), in: size, geometry: .standard)
        #expect(numbered.hasNear(KernelPalette.textTertiary, at: twenty, radius: 8, tolerance: 12))
        #expect(!bitmap.hasNear(KernelPalette.textTertiary, at: twenty, radius: 8, tolerance: 12))
    }

    @Test func aNonSquareFrame_drawsTheBoardInTheLargestCentredSquare() throws {
        let wide = CGSize(width: 500, height: 300)
        let bitmap = try render(DartboardView(), size: wide)
        // Centre of the frame: the bull. 150 pt left of it: outside the board (its radius is 150).
        #expect(bitmap.has(KernelPalette.boardRed, at: CGPoint(x: 250, y: 150)))
        #expect(bitmap.has(KernelPalette.background, at: CGPoint(x: 80, y: 150)))
        // The 6, on the right: outer single at 134.5 mm of 225.5, on a board of radius 150.
        #expect(bitmap.has(KernelPalette.boardCream, at: CGPoint(x: 250 + 134.5 * 150 / 225.5, y: 150)))
    }

    @Test func aPictogram_isAFlatDisc_withItsZonesInColour() throws {
        // Option pictogram of the mock-up `KillerOptions` (radio rows of the levels): 36 pt, amber sectors on a
        // `line` disc, from the centre to the edge.
        let small = CGSize(width: 36, height: 36)
        let three = [20, 1, 18].map { BoardHighlight(zone: .sector($0), role: .target) }
        let bitmap = try render(DartboardView(highlights: three, showsNumbers: false), size: small)
        func at(_ radius: Double, _ degrees: Double, in size: CGSize = small) -> CGPoint {
            DartboardView.location(of: BoardPoint(radius: radius, clockwiseDegrees: degrees), in: size, geometry: .standard)
        }
        for degrees in [0.0, 18, 36] {
            for radius in [120.0, 190] {
                #expect(bitmap.has(KernelPalette.accent, at: at(radius, degrees), tolerance: 6), "\(radius) mm, \(degrees)°: \(bitmap.color(at: at(radius, degrees)))")
            }
        }
        for degrees in [90.0, 180, 270] {
            #expect(bitmap.has(KernelPalette.line, at: at(150, degrees), tolerance: 6), "\(degrees)°: \(bitmap.color(at: at(150, degrees)))")
        }
        // None of the bed colours of the full drawing, and no number.
        for bed in [KernelPalette.boardCream, KernelPalette.boardGreen, KernelPalette.boardRed, KernelPalette.textTertiary] {
            #expect(bitmap.count(differingFrom: bed, tolerance: 20) == 36 * 36, "\(bed)")
        }
        // A zone shown for information is lighter: 40 % of its colour over `line` (level "Expert" of the mock-up).
        let faint = try render(DartboardView(highlights: [BoardHighlight(zone: .sector(20), role: .target),
                                                          BoardHighlight(zone: .sector(6), role: .secondary)], showsNumbers: false),
                               size: small)
        #expect(faint.has(KernelPalette.line.covered(by: KernelPalette.accent, opacity: 0.4), at: at(150, 90), tolerance: 8),
                "\(faint.color(at: at(150, 90)))")
        // A ring is drawn on its band only (about one point wide here), in the colour of its owner.
        let ring = try render(DartboardView(highlights: [BoardHighlight(zone: .double(6), role: .target, owner: 1)], showsNumbers: false),
                              size: small)
        let band = at(166.85, 90)
        let around = (-1...1).flatMap { dx in (-1...1).map { dy in ring.color(at: CGPoint(x: band.x + CGFloat(dx), y: band.y + CGFloat(dy))) } }
        #expect(around.contains { $0.distance(to: KernelPalette.players[1]) < $0.distance(to: KernelPalette.line) }, "\(around)")
        #expect(ring.has(KernelPalette.line, at: at(100, 90), tolerance: 6))
        #expect(ring.has(KernelPalette.line, at: at(166.85, 270), tolerance: 6))
        // A disc on a pictogram shows where it is, not what it is worth: no label pill, no pips.
        let plainDisc = BoardHighlight(zone: .disc(x: 60, y: 60, radius: 60), role: .target)
        let labelledDisc = BoardHighlight(zone: .disc(x: 60, y: 60, radius: 60), role: .target, label: "+10", strength: 2)
        let plainPicture = try render(DartboardView(highlights: [plainDisc], geometry: .standard), size: small)
        let labelledPicture = try render(DartboardView(highlights: [labelledDisc], geometry: .standard), size: small)
        var differing = 0
        for y in 0..<36 {
            for x in 0..<36 where plainPicture.color(at: CGPoint(x: x, y: y)).distance(to: labelledPicture.color(at: CGPoint(x: x, y: y))) > 16 {
                differing += 1
            }
        }
        #expect(differing == 0)
        #expect(plainPicture.hasNear(KernelPalette.accent, at: DartboardView.location(of: BoardPoint(x: 120, y: 60), in: small, geometry: .standard),
                                     radius: 1, tolerance: 12))
        // The same discs on a full board carry their label.
        let plainLarge = try render(DartboardView(highlights: [plainDisc], geometry: .standard))
        let labelledLarge = try render(DartboardView(highlights: [labelledDisc], geometry: .standard))
        #expect(plainLarge.count(differingFrom: KernelPalette.onAccent, tolerance: 30) > labelledLarge.count(differingFrom: KernelPalette.onAccent, tolerance: 30))
        // From 64 pt on, the full board is drawn: number ring, darkened cream beds.
        let large = CGSize(width: 64, height: 64)
        let full = try render(DartboardView(highlights: three, showsNumbers: false), size: large)
        #expect(full.has(KernelPalette.boardSurround, at: at(215, 90, in: large), tolerance: 6))
        #expect(full.count(differingFrom: dimmed(KernelPalette.boardCream), tolerance: 12) < 64 * 64 - 20)
    }

    // MARK: Highlighted zones

    @Test func highlightedSector_isTintedInItsOwnersColour_andTheRestIsDimmed() throws {
        let blue = KernelPalette.players[1]
        let highlights = [20, 1, 18].map { BoardHighlight(zone: .sector($0), role: .target, owner: 1) }
        let bitmap = try render(DartboardView(highlights: highlights))
        for number in [20, 1, 18] {
            for band in BoardBed.sectorBands {
                let bed = BoardBed(band: band, sector: sector(number))
                let expected = bedColor(bed).covered(by: blue, opacity: 0.6)
                let point = middle(bed, geometry: .display)
                #expect(bitmap.has(expected, at: point, tolerance: 8), "\(bed): \(bitmap.color(at: point)) instead of \(expected)")
            }
        }
        // Every other bed, bulls included, is darkened to 62 % of the background.
        let tinted = Set([20, 1, 18].map(sector))
        for bed in BoardBed.all where bed.band == .innerBull || bed.band == .outerBull || !tinted.contains(bed.sector) {
            let point = middle(bed, geometry: .display)
            #expect(bitmap.has(dimmed(bedColor(bed)), at: point, tolerance: 8), "\(bed): \(bitmap.color(at: point))")
        }
        // A solid arc of the same colour runs just outside the double, over the three sectors and no further.
        func arc(_ degrees: Double) -> CGPoint {
            DartboardView.location(of: BoardPoint(radius: 173.6 + 2.3 + 4.5, clockwiseDegrees: degrees), in: size, geometry: .standard)
        }
        for degrees in [-8.0, 0, 18, 36, 44] { #expect(bitmap.has(blue, at: arc(degrees)), "\(degrees)°") }
        for degrees in [-11.0, 47, 90, 180, 270] { #expect(bitmap.has(KernelPalette.boardSurround, at: arc(degrees)), "\(degrees)°") }
        // The numbers of the zone take its colour; the others stay grey.
        let twenty = DartboardView.location(of: BoardPoint(radius: 200, clockwiseDegrees: 0), in: size, geometry: .standard)
        let six = DartboardView.location(of: BoardPoint(radius: 200, clockwiseDegrees: 90), in: size, geometry: .standard)
        #expect(bitmap.hasNear(blue, at: twenty, radius: 8, tolerance: 12))
        #expect(!bitmap.hasNear(blue, at: six, radius: 8, tolerance: 12))
        #expect(bitmap.hasNear(KernelPalette.textTertiary, at: six, radius: 8, tolerance: 12))
    }

    @Test func withoutAnOwner_aTargetIsAmber() throws {
        let bitmap = try render(DartboardView(highlights: [BoardHighlight(zone: .sector(6), role: .target)]))
        let bed = BoardBed(band: .outerSingle, sector: sector(6))
        #expect(bitmap.has(bedColor(bed).covered(by: KernelPalette.accent, opacity: 0.6), at: middle(bed, geometry: .display), tolerance: 8))
    }

    @Test func dimming_onlyWithAHighlight_andOnlyWhenAsked() throws {
        let cream = BoardBed(band: .outerSingle, sector: 1)
        let point = middle(cream, geometry: .display)
        let highlight = [BoardHighlight(zone: .sector(3), role: .target)]
        #expect(try render(DartboardView()).has(KernelPalette.boardCream, at: point))
        #expect(try render(DartboardView(dimsUnhighlighted: true)).has(KernelPalette.boardCream, at: point))
        #expect(try render(DartboardView(highlights: highlight)).has(dimmed(KernelPalette.boardCream), at: point, tolerance: 8))
        #expect(try render(DartboardView(highlights: highlight, dimsUnhighlighted: false)).has(KernelPalette.boardCream, at: point))
        // A highlight that draws nothing (a number that is not on the board) still counts as "at least one".
        #expect(try render(DartboardView(highlights: [BoardHighlight(zone: .sector(21), role: .target)]))
            .has(dimmed(KernelPalette.boardCream), at: point, tolerance: 8))
    }

    @Test func aSingleRingToAimAt_isColouredAlmostSolid_andTheSectorAroundItIsNot() throws {
        // D12 to finish (mock-up `PlayX01`).
        let bitmap = try render(DartboardView(highlights: [BoardHighlight(zone: .double(12), role: .target)]))
        let ring = BoardBed(band: .double, sector: sector(12))
        #expect(bitmap.has(bedColor(ring).covered(by: KernelPalette.accent, opacity: 0.92), at: middle(ring, geometry: .display), tolerance: 8))
        for band in [BoardGeometry.Band.innerSingle, .treble, .outerSingle] {
            let bed = BoardBed(band: band, sector: sector(12))
            #expect(bitmap.has(dimmed(bedColor(bed)), at: middle(bed, geometry: .display), tolerance: 8), "\(bed)")
        }
        // The double of the next sector is not coloured.
        let next = BoardBed(band: .double, sector: sector(5))
        #expect(bitmap.has(dimmed(bedColor(next)), at: middle(next, geometry: .display), tolerance: 8))
    }

    @Test func everyKindOfZone_coversExactlyItsBeds() throws {
        let zones: [BoardZone] = [.sector(7), .single(7), .double(7), .treble(7), .outerBull, .innerBull, .bull]
        for zone in zones {
            let bitmap = try render(DartboardView(highlights: [BoardHighlight(zone: zone, role: .target)]))
            for bed in BoardBed.all {
                let inZone = zone.contains(bed.hit(in: .display))
                let point = middle(bed, geometry: .display)
                let untouched = dimmed(bedColor(bed))
                // A highlighted bed is not the darkened one; every other bed is.
                #expect(bitmap.has(untouched, at: point, tolerance: 8) == !inZone, "\(zone), \(bed): \(bitmap.color(at: point))")
            }
        }
    }

    @Test func roles_areDrawnDifferently() throws {
        func picture(_ role: HighlightRole, owner: PlayerIndex? = nil) throws -> KernelBitmap {
            try render(DartboardView(highlights: [BoardHighlight(zone: .sector(6), role: role, owner: owner)]))
        }
        let bed = BoardBed(band: .outerSingle, sector: sector(6))
        let point = middle(bed, geometry: .display)
        let cream = KernelPalette.boardCream
        // target: full tint; secondary: half of it.
        #expect(try picture(.target).has(cream.covered(by: KernelPalette.accent, opacity: 0.6), at: point, tolerance: 8))
        #expect(try picture(.secondary).has(cream.covered(by: KernelPalette.accent, opacity: 0.3), at: point, tolerance: 8))
        // own: the bed keeps its colour (it is not darkened) and gets an outline in the player's colour.
        let own = try picture(.own, owner: 2)
        #expect(own.has(cream, at: point))
        let edge = DartboardView.location(of: BoardPoint(radius: 134.5, clockwiseDegrees: 90 - 8.6), in: size, geometry: .standard)
        #expect(own.hasNear(KernelPalette.players[2], at: edge, radius: 2, tolerance: 12))
        #expect(try !picture(.target, owner: 2).hasNear(KernelPalette.players[2], at: edge, radius: 2, tolerance: 12))
        // avoid: red stripes over a darkened ground.
        let avoid = try picture(.avoid)
        var reds = 0, darks = 0
        for step in -20...20 {
            let sample = DartboardView.location(of: BoardPoint(radius: 134.5 + Double(step), clockwiseDegrees: 90), in: size, geometry: .standard)
            if avoid.has(KernelPalette.boardRed, at: sample, tolerance: 12) { reds += 1 }
            if avoid.has(cream.covered(by: KernelPalette.background, opacity: 0.5), at: sample, tolerance: 12) { darks += 1 }
        }
        #expect(reds >= 5 && darks >= 5, "reds \(reds), darks \(darks)")
        // opponent: darker than a target, still veiled with the owner's colour.
        let opponent = try picture(.opponent, owner: 1)
        let veiled = cream.covered(by: KernelPalette.background, opacity: 0.31).covered(by: KernelPalette.players[1], opacity: 0.3)
        #expect(opponent.has(veiled, at: point, tolerance: 8), "\(opponent.color(at: point)) instead of \(veiled)")
        // inactive: greyed, and its number stays grey.
        let inactive = try picture(.inactive, owner: 1)
        #expect(inactive.has(cream.covered(by: KernelPalette.lineStrong, opacity: 0.78), at: point, tolerance: 8))
        let six = DartboardView.location(of: BoardPoint(radius: 200, clockwiseDegrees: 90), in: size, geometry: .standard)
        #expect(!inactive.hasNear(KernelPalette.players[1], at: six, radius: 8, tolerance: 12))
        // The six pictures are six different drawings of the same bed.
        let colours = try [HighlightRole.target, .secondary, .own, .opponent, .inactive].map { try picture($0).color(at: point) }
        for (index, colour) in colours.enumerated() {
            for other in colours[(index + 1)...] { #expect(colour.distance(to: other) > 12) }
        }
    }

    @Test func aZoneOfAdjacentSectors_isOnePiece_withoutSeams() throws {
        // Killer zone 5-20-1, which wraps past the 20: its arc outside the double is one colour from end to
        // end, and no pixel of the surround shows at the two joints between its sectors.
        let zone = [5, 20, 1].map { BoardHighlight(zone: .sector($0), role: .target, owner: 1) }
        let bitmap = try render(DartboardView(highlights: zone))
        let blue = KernelPalette.players[1]
        for degrees in stride(from: -26.0, through: 26, by: 0.5) {
            let point = DartboardView.location(of: BoardPoint(radius: 173.6 + 2.3 + 4.5, clockwiseDegrees: degrees), in: size,
                                               geometry: .standard)
            #expect(bitmap.has(blue, at: point, tolerance: 4), "\(degrees)°: \(bitmap.color(at: point))")
        }
        // Inside the zone too: along the middle of the inner single, the two cream sectors (5 and 1) and the
        // black one (20) are tinted up to the wires, without a darker line between them.
        for degrees in stride(from: -26.0, through: 26, by: 0.5) {
            let point = DartboardView.location(of: BoardPoint(radius: 56, clockwiseDegrees: degrees), in: size, geometry: .standard)
            let pixel = bitmap.color(at: point)
            let cream = KernelPalette.boardCream.covered(by: blue, opacity: 0.6)
            let black = KernelPalette.boardBlack.covered(by: blue, opacity: 0.6)
            // On a wire the pixel is between the two tinted colours, never darker than the darker one.
            #expect(pixel.red >= black.red - 8 && pixel.red <= cream.red + 8, "\(degrees)°: \(pixel)")
            #expect(pixel.blue >= black.blue - 8, "\(degrees)°: \(pixel)")
        }
    }

    // MARK: Discs (Radar)

    @Test func disc_isDrawnExactlyWhereTheGamePutsIt_underStandard() throws {
        let disc = BoardHighlight(zone: .disc(x: -80, y: 95, radius: 40), role: .target)
        let bitmap = try render(DartboardView(highlights: [disc], geometry: .standard))
        let centre = DartboardView.location(of: BoardPoint(x: -80, y: 95), in: size, geometry: .standard)
        let radius = DartboardView.length(of: 40, in: size)
        // Inside: the bed seen through 60 % of amber. As for a tinted sector, the disc is the zone and only the
        // rest of the board is darkened (DESIGN.md §4).
        let under = DartboardView.tap(at: centre, in: size, geometry: .standard).hit
        #expect(under == .single(12))
        #expect(bitmap.has(KernelPalette.boardBlack.covered(by: KernelPalette.accent, opacity: 0.6), at: centre, tolerance: 8),
                "\(bitmap.color(at: centre))")
        // Cream under the disc too, not darkened.
        let cream = DartboardView.location(of: BoardPoint(radius: 124.6, clockwiseDegrees: 306), in: size, geometry: .standard)
        #expect(DartboardView.tap(at: cream, in: size, geometry: .standard).hit == .single(9))
        #expect(bitmap.has(KernelPalette.boardCream.covered(by: KernelPalette.accent, opacity: 0.6), at: cream, tolerance: 8),
                "\(bitmap.color(at: cream))")
        // The rest of the board is darkened: the 20 and the 6, far from the disc.
        let twenty = DartboardView.location(of: BoardPoint(radius: 134.5, clockwiseDegrees: 0), in: size, geometry: .standard)
        let six = DartboardView.location(of: BoardPoint(radius: 134.5, clockwiseDegrees: 90), in: size, geometry: .standard)
        #expect(bitmap.has(dimmed(KernelPalette.boardBlack), at: twenty, tolerance: 8))
        #expect(bitmap.has(dimmed(KernelPalette.boardCream), at: six, tolerance: 8))
        for step in 0..<12 {
            let angle = Double(step) * 30 * .pi / 180
            func at(_ distance: CGFloat) -> CGPoint { CGPoint(x: centre.x + distance * cos(angle), y: centre.y + distance * sin(angle)) }
            // The outline is solid amber, drawn INSIDE the edge: a tap on it is in the disc of the game.
            #expect(bitmap.hasNear(KernelPalette.accent, at: at(radius - 1), radius: 1, tolerance: 12), "step \(step)")
            // Nothing of the disc is drawn beyond its edge.
            let outside = at(radius + 2)
            let amberish = bitmap.color(at: outside)
            #expect(amberish.red < 150 || amberish.distance(to: KernelPalette.accent) > 60, "step \(step): \(amberish)")
        }
    }

    @Test func disc_carriesItsLabelAndItsHitPoints() throws {
        let plain = BoardHighlight(zone: .disc(x: 0, y: 0, radius: 40), role: .target)
        let labelled = BoardHighlight(zone: .disc(x: 0, y: 0, radius: 40), role: .target, label: "+10", strength: 2)
        let without = try render(DartboardView(highlights: [plain], geometry: .standard))
        let with = try render(DartboardView(highlights: [labelled], geometry: .standard))
        // A solid amber pill with dark text at the centre, and pips under it.
        let centre = CGPoint(x: 200, y: 200)
        #expect(with.hasNear(KernelPalette.accent, at: CGPoint(x: 200, y: 194), radius: 12, tolerance: 6))
        #expect(with.hasNear(KernelPalette.onAccent, at: CGPoint(x: 200, y: 194), radius: 12, tolerance: 40))
        #expect(with.hasNear(KernelPalette.textPrimary, at: CGPoint(x: 200, y: 208), radius: 12, tolerance: 20))
        #expect(!without.hasNear(KernelPalette.textPrimary, at: centre, radius: 20, tolerance: 20))
        #expect(!without.hasNear(KernelPalette.accent, at: centre, radius: 12, tolerance: 6))
    }

    @Test func aDiscWithAnOwner_takesThePlayersColour() throws {
        let disc = BoardHighlight(zone: .disc(x: 60, y: 60, radius: 30), role: .target, owner: 3)
        let bitmap = try render(DartboardView(highlights: [disc], geometry: .standard))
        let centre = DartboardView.location(of: BoardPoint(x: 60, y: 60), in: size, geometry: .standard)
        let edge = CGPoint(x: centre.x + DartboardView.length(of: 30, in: size) - 1, y: centre.y)
        #expect(bitmap.hasNear(KernelPalette.players[3], at: edge, radius: 1, tolerance: 12))
    }

    // MARK: Darts

    @Test func dart_isDrawnAtItsNominalPosition_inBothGeometries() throws {
        // A treble 20 measured by the camera at its regulation position.
        let nominal = BoardPoint(x: 0, y: 103)
        let dart = BoardDartMarker(id: UUID(), position: nominal, label: nil, style: .neutral)
        for geometry in [BoardGeometry.display, .standard] {
            let bitmap = try render(DartboardView(darts: [dart], geometry: geometry))
            let point = DartboardView.location(of: nominal, in: size, geometry: geometry)
            #expect(bitmap.has(KernelPalette.textPrimary, at: point))
            // It sits on the treble that a tap there scores.
            #expect(DartboardView.tap(at: point, in: size, geometry: geometry).hit == .treble(20))
            // Dark border around the off-white disc (14 pt marker, 3 pt border).
            #expect(bitmap.has(KernelPalette.background, at: CGPoint(x: point.x + 5.5, y: point.y), tolerance: 6))
            #expect(bitmap.has(KernelPalette.boardRed, at: CGPoint(x: point.x + 9.5, y: point.y), tolerance: 6))
        }
    }

    @Test func dartStyles_playerColour_andAmberToCheck() throws {
        let position = BoardPoint(x: 60, y: 0)
        func picture(_ style: BoardDartMarker.Style) throws -> KernelBitmap {
            try render(DartboardView(darts: [BoardDartMarker(id: UUID(), position: position, label: nil, style: style)]))
        }
        let point = DartboardView.location(of: position, in: size, geometry: .display)
        #expect(try picture(.neutral).has(KernelPalette.textPrimary, at: point))
        #expect(try picture(.player(2)).has(KernelPalette.players[2], at: point))
        #expect(try picture(.player(9)).has(KernelPalette.players[1], at: point))
        // To check: amber, larger, with a dark question mark.
        let review = try picture(.review)
        #expect(review.hasNear(KernelPalette.accent, at: CGPoint(x: point.x + 6, y: point.y), radius: 1, tolerance: 6))
        #expect(review.hasNear(KernelPalette.onAccent, at: point, radius: 3, tolerance: 40))
    }

    @Test func markerSize_followsTheWidthClass_andShrinksOnASmallBoard() throws {
        let dart = BoardDartMarker(id: UUID(), position: .centre, label: nil, style: .player(1))
        let blue = KernelPalette.players[1]
        func blueWidth(_ view: some View, side: CGFloat) throws -> Int {
            let bitmap = try KernelBitmap(view, size: CGSize(width: side, height: side))
            return (0..<Int(side)).filter { bitmap.has(blue, at: CGPoint(x: CGFloat($0) + 0.5, y: side / 2), tolerance: 6) }.count
        }
        // 14 pt marker with a 20 % border: about 8 pt of colour. 26 pt in regular width: about 15 pt.
        let compact = try blueWidth(DartboardView(darts: [dart]).environment(\.horizontalSizeClass, .compact), side: 400)
        let regular = try blueWidth(DartboardView(darts: [dart]).environment(\.horizontalSizeClass, .regular), side: 400)
        #expect((7...9).contains(compact), "\(compact)")
        #expect((14...16).contains(regular), "\(regular)")
        // On a board of 96 pt the marker is 8 pt: about 5 pt of colour.
        let small = try blueWidth(DartboardView(darts: [dart]).environment(\.horizontalSizeClass, .regular), side: 96)
        #expect((3...6).contains(small), "\(small)")
    }

    // MARK: Reading the highlights

    @Test func bedsOfAZone() {
        let display = BoardGeometry.display
        #expect(BoardBed.beds(of: .sector(20), in: display).map(\.band) == [.innerSingle, .treble, .outerSingle, .double])
        #expect(BoardBed.beds(of: .sector(6), in: display).allSatisfy { $0.sector == 5 })
        #expect(BoardBed.beds(of: .single(3), in: display) == [BoardBed(band: .innerSingle, sector: 10), BoardBed(band: .outerSingle, sector: 10)])
        #expect(BoardBed.beds(of: .double(11), in: display) == [BoardBed(band: .double, sector: 15)])
        #expect(BoardBed.beds(of: .treble(5), in: display) == [BoardBed(band: .treble, sector: 19)])
        #expect(BoardBed.beds(of: .outerBull, in: display) == [BoardBed(band: .outerBull, sector: 0)])
        #expect(BoardBed.beds(of: .innerBull, in: display) == [BoardBed(band: .innerBull, sector: 0)])
        #expect(Set(BoardBed.beds(of: .bull, in: display)) == [BoardBed(band: .innerBull, sector: 0), BoardBed(band: .outerBull, sector: 0)])
        // A disc is not made of beds, and a number that is not on the board has none.
        #expect(BoardBed.beds(of: .disc(x: 0, y: 0, radius: 40), in: display).isEmpty)
        for number in [0, 21, -3, Int.max] {
            #expect(BoardBed.beds(of: .sector(number), in: display).isEmpty)
            #expect(BoardBed.beds(of: .single(number), in: display).isEmpty)
            #expect(BoardBed.beds(of: .double(number), in: display).isEmpty)
            #expect(BoardBed.beds(of: .treble(number), in: display).isEmpty)
        }
        // Every zone holds exactly the beds whose hit it contains.
        for number in 1...20 {
            for zone in [BoardZone.sector(number), .single(number), .double(number), .treble(number)] {
                let beds = Set(BoardBed.beds(of: zone, in: display))
                #expect(beds == Set(BoardBed.all.filter { zone.contains($0.hit(in: display)) }), "\(zone)")
            }
        }
    }

    @Test func overlappingZones_theNarrowerOneWinsOnItsBeds() {
        let display = BoardGeometry.display
        let index = sector(4)
        // Golf, hole 4: double and treble to aim at, single as secondary; and a whole sector given first or last.
        for highlights in [
            [BoardHighlight(zone: .sector(4), role: .secondary), BoardHighlight(zone: .treble(4), role: .target),
             BoardHighlight(zone: .double(4), role: .target)],
            [BoardHighlight(zone: .treble(4), role: .target), BoardHighlight(zone: .double(4), role: .target),
             BoardHighlight(zone: .sector(4), role: .secondary)],
        ] {
            let styles = BoardDrawing.bedStyles(for: highlights, in: display)
            #expect(styles.count == 4)
            #expect(styles[BoardBed(band: .treble, sector: index)]?.role == .target)
            #expect(styles[BoardBed(band: .double, sector: index)]?.role == .target)
            #expect(styles[BoardBed(band: .treble, sector: index)]?.isOneRing == true)
            #expect(styles[BoardBed(band: .innerSingle, sector: index)]?.role == .secondary)
            #expect(styles[BoardBed(band: .outerSingle, sector: index)]?.role == .secondary)
            #expect(styles[BoardBed(band: .outerSingle, sector: index)]?.isOneRing == false)
            // The arc and the number of the sector follow the role the player must see first.
            #expect(BoardDrawing.sectorStyles(for: highlights, in: display)[index]?.role == .target)
        }
        // Two zones of the same kind on one bed: the later one.
        let twice = [BoardHighlight(zone: .sector(4), role: .target, owner: 0), BoardHighlight(zone: .sector(4), role: .avoid, owner: 1)]
        #expect(BoardDrawing.bedStyles(for: twice, in: display)[BoardBed(band: .double, sector: index)]?.owner == 1)
        // Nothing for a disc, and nothing for the sectors nobody highlighted.
        let disc = [BoardHighlight(zone: .disc(x: 0, y: 0, radius: 10), role: .target)]
        #expect(BoardDrawing.bedStyles(for: disc, in: display).isEmpty)
        #expect(BoardDrawing.sectorStyles(for: disc, in: display).allSatisfy { $0 == nil })
        #expect(BoardDrawing.sectorStyles(for: twice, in: display).filter { $0 != nil }.count == 1)
    }

    @Test func runs_groupNeighbours_andWrapPastTheTwenty() {
        func runs(_ values: [String?]) -> [String] {
            BoardDrawing.runs(of: values).map { "\($0.value)@\($0.start)x\($0.count)" }
        }
        #expect(runs([]).isEmpty)
        #expect(runs([nil, nil, nil]).isEmpty)
        #expect(runs(["a", "a", "a"]) == ["a@0x3"])
        #expect(runs(["a", nil, nil]) == ["a@0x1"])
        #expect(runs([nil, "a", "a", nil]) == ["a@1x2"])
        // Killer zone 5-20-1: indices 19, 0, 1 are ONE group that starts at 19.
        var ring = [String?](repeating: nil, count: 20)
        ring[19] = "z"; ring[0] = "z"; ring[1] = "z"
        #expect(runs(ring) == ["z@19x3"])
        // Two neighbours of different values are two groups.
        ring[2] = "y"
        #expect(Set(runs(ring)) == ["z@19x3", "y@2x1"])
        #expect(Set(runs(["a", "b", "a", "a"])) == ["a@2x3", "b@1x1"])
        // The groups cover every non-nil position exactly once.
        var random = SeededRandom(seed: 7)
        for _ in 0..<200 {
            let values: [Int?] = (0..<20).map { _ in
                let draw = random.nextInt(below: 3)
                return draw == 0 ? nil : draw
            }
            let groups = BoardDrawing.runs(of: values)
            var covered = [Int](repeating: 0, count: 20)
            for group in groups {
                for step in 0..<group.count {
                    let position = (group.start + step) % 20
                    covered[position] += 1
                    #expect(values[position] == group.value)
                }
                // A group is maximal: the positions around it carry another value (unless it is the whole ring).
                if group.count < 20 {
                    #expect(values[(group.start + 19) % 20] != group.value)
                    #expect(values[(group.start + group.count) % 20] != group.value)
                }
            }
            #expect(covered == values.map { $0 == nil ? 0 : 1 })
        }
    }

    @Test func targetNumbers_areReadClockwiseFromTheTwenty_eachOnce() {
        let highlights = [
            BoardHighlight(zone: .sector(18), role: .target), BoardHighlight(zone: .double(20), role: .target),
            BoardHighlight(zone: .treble(20), role: .target), BoardHighlight(zone: .sector(5), role: .target),
            BoardHighlight(zone: .sector(1), role: .secondary), BoardHighlight(zone: .bull, role: .target),
            BoardHighlight(zone: .disc(x: 0, y: 0, radius: 5), role: .target),
        ]
        #expect(BoardDrawing.targetNumbers(in: highlights) == [20, 18, 5])
        #expect(BoardDrawing.targetNumbers(in: []).isEmpty)
    }

    // MARK: Unusual input

    @Test func unusualInput_isDrawnWithoutTrapping() throws {
        let highlights = [
            BoardHighlight(zone: .sector(0), role: .target), BoardHighlight(zone: .double(21), role: .avoid),
            BoardHighlight(zone: .treble(-1), role: .own, label: "x", strength: 9, marker: .home),
            BoardHighlight(zone: .disc(x: .nan, y: 0, radius: 10), role: .target, label: "+1"),
            BoardHighlight(zone: .disc(x: 0, y: 0, radius: -5), role: .target),
            BoardHighlight(zone: .disc(x: 0, y: 0, radius: .infinity), role: .target),
            BoardHighlight(zone: .disc(x: 500, y: 500, radius: 20), role: .target, label: "+50", strength: -2),
            BoardHighlight(zone: .sector(20), role: .target, owner: -4, label: "", strength: 0),
            BoardHighlight(zone: .bull, role: .inactive, owner: 99, label: "a very long label that does not fit", marker: .crown),
        ]
        let darts = [
            BoardDartMarker(id: UUID(), position: BoardPoint(x: .nan, y: .nan), label: "?", style: .review),
            BoardDartMarker(id: UUID(), position: BoardPoint(x: .infinity, y: 0), label: nil, style: .player(-1)),
            BoardDartMarker(id: UUID(), position: BoardPoint(x: 1_000, y: 1_000), label: "far", style: .neutral),
            BoardDartMarker(id: UUID(), position: .centre, label: "", style: .neutral),
        ]
        for geometry in [BoardGeometry.display, .standard] {
            for side in [1, 7, 36, 400] as [CGFloat] {
                let bitmap = try render(DartboardView(highlights: highlights, darts: darts, geometry: geometry),
                                        size: CGSize(width: side, height: side))
                #expect(bitmap.width == Int(side) && bitmap.height == Int(side))
            }
        }
        // A geometry of another board (rings elsewhere, numbers in another order) is drawn too.
        let other = BoardGeometry(sectorOrder: Array((1...20).reversed()), innerBullRadius: 5, outerBullRadius: 20,
                                  trebleInnerRadius: 80, trebleOuterRadius: 100, doubleInnerRadius: 150, doubleOuterRadius: 180,
                                  boardRadius: 225.5)
        let bitmap = try render(DartboardView(highlights: [BoardHighlight(zone: .sector(20), role: .target)], geometry: other))
        #expect(bitmap.count(differingFrom: KernelPalette.background) > 10_000)
    }

    @Test func theDrawing_isTheSameEveryTime() throws {
        // Same inputs, same picture: nothing in the drawing depends on the order of a dictionary or on a clock.
        // The renderer itself rounds a translucent pixel up or down by one level from one run to the next
        // (seen on a handful of pixels): the comparison allows that, and nothing more.
        let board = DartboardView(highlights: KernelSnapshotFixtures.everyRole + KernelSnapshotFixtures.radarDiscs,
                                  darts: KernelSnapshotFixtures.everyDart)
        let first = try render(board)
        for _ in 0..<3 {
            let again = try render(board)
            var different = 0
            for y in stride(from: 0, to: 400, by: 2) {
                for x in stride(from: 0, to: 400, by: 2)
                where first.color(at: CGPoint(x: x, y: y)).distance(to: again.color(at: CGPoint(x: x, y: y))) > 2 {
                    different += 1
                }
            }
            #expect(different == 0)
        }
        // The order in which unrelated zones are given does not change the picture either.
        let shuffled = try render(DartboardView(highlights: (KernelSnapshotFixtures.everyRole + KernelSnapshotFixtures.radarDiscs).reversed(),
                                                darts: KernelSnapshotFixtures.everyDart))
        var different = 0
        for y in stride(from: 0, to: 400, by: 2) {
            for x in stride(from: 0, to: 400, by: 2)
            where first.color(at: CGPoint(x: x, y: y)).distance(to: shuffled.color(at: CGPoint(x: x, y: y))) > 2 {
                different += 1
            }
        }
        // Only where two discs or two labels overlap can the stacking order show: a small part of the picture.
        #expect(different < 400)
    }
}
