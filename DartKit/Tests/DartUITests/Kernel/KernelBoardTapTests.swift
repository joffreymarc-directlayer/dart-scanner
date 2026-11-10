import Foundation
import CoreGraphics
import Testing
import DartCore
@testable import DartUI

/// Conversion between the view and the board (ARCHITECTURE.md §8.4.3): a tap becomes a hit and a nominal
/// position, a nominal position becomes a point of the view, in both drawing geometries.
@MainActor
@Suite struct KernelBoardTapTests {
    private let geometries: [(name: String, geometry: BoardGeometry)] = [("display", .display), ("standard", .standard)]
    /// Board sizes of the mock-ups (300, 260, 720), of the phone snapshot (353) and of an option pictogram (36).
    private let sides: [CGFloat] = [36, 260, 300, 353, 720]

    private func square(_ side: CGFloat) -> CGSize { CGSize(width: side, height: side) }

    /// The point of the view where a point of the DRAWN geometry is: the formula of §8.4.3, written out here.
    private func viewPoint(radius: Double, degrees: Double, side: CGFloat) -> CGPoint {
        let k = Double(side) / 2 / 225.5
        let a = degrees * .pi / 180
        return CGPoint(x: Double(side) / 2 + radius * sin(a) * k, y: Double(side) / 2 - radius * cos(a) * k)
    }

    private func distance(_ a: BoardPoint, _ b: BoardPoint) -> Double {
        ((a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y)).squareRoot()
    }

    // MARK: Scale and orientation

    @Test func scale_theBoardRadiusFillsHalfTheWidth() {
        #expect(DartboardView.length(of: 225.5, in: square(300)) == 150)
        #expect(DartboardView.length(of: 0, in: square(300)) == 0)
        #expect(abs(DartboardView.length(of: 40, in: square(353)) - 40 * 176.5 / 225.5) < 1e-9)
        // Twice the view, twice the length.
        #expect(abs(DartboardView.length(of: 16, in: square(720)) - 2 * DartboardView.length(of: 16, in: square(360))) < 1e-9)
        // The scale follows the width.
        #expect(DartboardView.length(of: 225.5, in: CGSize(width: 300, height: 500)) == 150)
    }

    @Test func orientation_twentyIsUp_sixIsRight_threeIsDown_elevenIsLeft() {
        let size = square(300)
        for (name, geometry) in geometries {
            #expect(DartboardView.location(of: .centre, in: size, geometry: geometry) == CGPoint(x: 150, y: 150), "\(name)")
            let up = DartboardView.location(of: BoardPoint(x: 0, y: 134.5), in: size, geometry: geometry)
            let right = DartboardView.location(of: BoardPoint(x: 134.5, y: 0), in: size, geometry: geometry)
            let down = DartboardView.location(of: BoardPoint(x: 0, y: -134.5), in: size, geometry: geometry)
            let left = DartboardView.location(of: BoardPoint(x: -134.5, y: 0), in: size, geometry: geometry)
            #expect(abs(up.x - 150) < 1e-9 && up.y < 150, "\(name)")
            #expect(right.x > 150 && abs(right.y - 150) < 1e-9, "\(name)")
            #expect(abs(down.x - 150) < 1e-9 && down.y > 150, "\(name)")
            #expect(left.x < 150 && abs(left.y - 150) < 1e-9, "\(name)")
            #expect(DartboardView.tap(at: up, in: size, geometry: geometry).hit == .single(20), "\(name)")
            #expect(DartboardView.tap(at: right, in: size, geometry: geometry).hit == .single(6), "\(name)")
            #expect(DartboardView.tap(at: down, in: size, geometry: geometry).hit == .single(3), "\(name)")
            #expect(DartboardView.tap(at: left, in: size, geometry: geometry).hit == .single(11), "\(name)")
            #expect(DartboardView.tap(at: CGPoint(x: 150, y: 150), in: size, geometry: geometry).hit == .innerBull, "\(name)")
        }
    }

    @Test func geometryParameter_defaultsToTheThickRings() {
        let size = square(300)
        let point = CGPoint(x: 150, y: 150 - 98 * 150 / 225.5)
        #expect(DartboardView.tap(at: point, in: size) == DartboardView.tap(at: point, in: size, geometry: .display))
        let nominal = BoardPoint(x: 30, y: 100)
        #expect(DartboardView.location(of: nominal, in: size) == DartboardView.location(of: nominal, in: size, geometry: .display))
    }

    // MARK: A tap on the drawn ring (§8.4.3, DESIGN.md §3)

    @Test func tapOnTheDrawnTrebleRing_isATreble_underDisplay() {
        for side in sides {
            let size = square(side)
            // 98 mm and 110 mm of the drawing are inside the drawn treble (97–110.5) but outside the regulation
            // one (99–107): only the geometry of the drawing can call them trebles.
            for radius in [97.5, 98, 103.75, 108, 110] {
                let point = viewPoint(radius: radius, degrees: 0, side: side)
                let tap = DartboardView.tap(at: point, in: size, geometry: .display)
                #expect(tap.hit == .treble(20), "radius \(radius), side \(side)")
                // Its position falls inside the regulation treble ring.
                #expect((99.0...107.0).contains(tap.position.radius), "radius \(radius): \(tap.position.radius)")
                #expect(BoardGeometry.standard.hit(at: tap.position) == .treble(20))
            }
            // The same points on a board drawn at regulation proportions are singles.
            #expect(DartboardView.tap(at: viewPoint(radius: 98, degrees: 0, side: side), in: size, geometry: .standard).hit == .single(20))
            #expect(DartboardView.tap(at: viewPoint(radius: 110, degrees: 0, side: side), in: size, geometry: .standard).hit == .single(20))
        }
    }

    @Test func tapOnTheDrawnDoubleRing_isADouble_underDisplay() {
        let side: CGFloat = 300
        for degrees in stride(from: 0.0, to: 360, by: 18) {
            let number = BoardGeometry.standardSectorOrder[Int(degrees / 18)]
            for radius in [160.5, 161, 166.85, 172, 173.5] {
                let tap = DartboardView.tap(at: viewPoint(radius: radius, degrees: degrees, side: side), in: square(side), geometry: .display)
                #expect(tap.hit == .double(number), "radius \(radius), \(degrees)°")
                #expect((162.0...170.0).contains(tap.position.radius))
                #expect(BoardGeometry.standard.hit(at: tap.position) == .double(number))
            }
        }
        // 161 mm is a single on a regulation drawing, and 173 mm is off the scoring area.
        #expect(DartboardView.tap(at: viewPoint(radius: 161, degrees: 0, side: side), in: square(side), geometry: .standard).hit == .single(20))
        #expect(DartboardView.tap(at: viewPoint(radius: 173, degrees: 0, side: side), in: square(side), geometry: .standard).hit == .miss)
    }

    // MARK: Round trip over the 82 beds

    @Test func roundTrip_locationThenTap_givesBackEveryBed_inBothGeometries() {
        #expect(BoardBed.all.count == 82)
        #expect(Set(BoardBed.all).count == 82)
        // 82 beds, 62 hits: the two singles of a number are one hit.
        #expect(Set(BoardBed.all.map { $0.hit(in: .standard) }).count == 62)
        for (name, geometry) in geometries {
            for side in sides {
                let size = square(side)
                for bed in BoardBed.all {
                    // The centre of the bed on a regulation board, as a detected dart would be reported.
                    let nominal = bed.centre(in: .standard)
                    let expected = bed.hit(in: .standard)
                    #expect(BoardGeometry.standard.hit(at: nominal) == expected)
                    let location = DartboardView.location(of: nominal, in: size, geometry: geometry)
                    let tap = DartboardView.tap(at: location, in: size, geometry: geometry)
                    #expect(tap.hit == expected, "\(name), side \(side), \(bed)")
                    #expect(distance(tap.position, nominal) < 1e-6, "\(name), side \(side), \(bed)")
                    // The marker is drawn in the middle of the DRAWN bed.
                    let drawn = bed.centre(in: geometry)
                    let scale = Double(side) / 2 / 225.5
                    #expect(abs(Double(location.x) - (Double(side) / 2 + drawn.x * scale)) < 1e-6, "\(name), \(bed)")
                    #expect(abs(Double(location.y) - (Double(side) / 2 - drawn.y * scale)) < 1e-6, "\(name), \(bed)")
                }
            }
        }
    }

    @Test func bedCentres_areTheCanonicalPositionsOfDartCore() {
        // The middle of a bed is the point DartCore gives for its hit (outer single for a single).
        for bed in BoardBed.all where bed.band != .innerSingle {
            let hit = bed.hit(in: .standard)
            let centre = bed.centre(in: .standard)
            let canonical = BoardGeometry.standard.centre(of: hit)
            #expect(canonical.map { distance($0, centre) < 1e-9 } == true, "\(bed)")
        }
        // The inner single has no canonical position of its own: it is between the bull and the treble.
        let inner = BoardBed(band: .innerSingle, sector: 5).centre(in: .standard)
        #expect(abs(inner.radius - (15.9 + 99) / 2) < 1e-9)
        #expect(BoardGeometry.standard.hit(at: inner) == .single(6))
    }

    // MARK: Wires

    @Test func tapAgreesWithBoardGeometry_onBothSidesOfEveryRadialWire() {
        for (name, geometry) in geometries {
            for side in sides {
                let size = square(side)
                for wire in 0..<20 {
                    // The wire between sector `wire` and the next one clockwise.
                    let angle = Double(wire) * 18 + 9
                    let before = geometry.sectorOrder[wire], after = geometry.sectorOrder[(wire + 1) % 20]
                    for band in BoardBed.sectorBands {
                        let range = geometry.radialRange(of: band)
                        let radius = (range.lowerBound + range.upperBound) / 2
                        let bed = BoardBed(band: band, sector: wire)
                        for (offset, number) in [(-0.01, before), (0.01, after), (-0.5, before), (0.5, after)] {
                            let tap = DartboardView.tap(at: viewPoint(radius: radius, degrees: angle + offset, side: side), in: size,
                                                        geometry: geometry)
                            let expected = BoardBed(band: band, sector: geometry.sectorOrder.firstIndex(of: number) ?? 0).hit(in: geometry)
                            #expect(tap.hit == expected, "\(name), side \(side), \(bed), \(offset)°")
                            #expect(tap.hit == geometry.hit(at: BoardPoint(radius: radius, clockwiseDegrees: angle + offset)))
                            // The nominal position stays on the same side of the regulation wire.
                            #expect(BoardGeometry.standard.hit(at: tap.position) == expected, "\(name), \(bed), \(offset)°")
                        }
                    }
                }
            }
        }
    }

    @Test func tapAgreesWithBoardGeometry_onBothSidesOfEveryRingWire() {
        for (name, geometry) in geometries {
            // Each wire with the bed just inside and the bed just outside it, for the 20.
            let wires: [(radius: Double, inside: Hit, outside: Hit)] = [
                (geometry.innerBullRadius, .innerBull, .outerBull),
                (geometry.outerBullRadius, .outerBull, .single(20)),
                (geometry.trebleInnerRadius, .single(20), .treble(20)),
                (geometry.trebleOuterRadius, .treble(20), .single(20)),
                (geometry.doubleInnerRadius, .single(20), .double(20)),
                (geometry.doubleOuterRadius, .double(20), .miss),
            ]
            for side in sides {
                let size = square(side)
                for wire in wires {
                    for index in 0..<20 {
                        let number = geometry.sectorOrder[index]
                        func hit(_ twenty: Hit) -> Hit {
                            // The same bed in the sector under test.
                            switch twenty.bed {
                            case .single: return .single(number)
                            case .treble: return .treble(number)
                            case .double: return .double(number)
                            default: return twenty
                            }
                        }
                        let angle = Double(index) * 18
                        let inside = DartboardView.tap(at: viewPoint(radius: wire.radius - 0.01, degrees: angle, side: side), in: size,
                                                       geometry: geometry)
                        let outside = DartboardView.tap(at: viewPoint(radius: wire.radius + 0.01, degrees: angle, side: side), in: size,
                                                        geometry: geometry)
                        #expect(inside.hit == hit(wire.inside), "\(name), side \(side), r \(wire.radius), sector \(number)")
                        #expect(outside.hit == hit(wire.outside), "\(name), side \(side), r \(wire.radius), sector \(number)")
                        // And the nominal positions are on the same sides of the regulation wire.
                        #expect(BoardGeometry.standard.hit(at: inside.position) == hit(wire.inside), "\(name), r \(wire.radius)")
                        #expect(BoardGeometry.standard.hit(at: outside.position) == hit(wire.outside), "\(name), r \(wire.radius)")
                    }
                }
            }
        }
    }

    @Test func anyTap_scoresWhatItsNominalPositionScores() {
        // 4 000 points drawn with a fixed seed over the whole view, corners included.
        var random = SeededRandom(seed: 20261110)
        for (name, geometry) in geometries {
            let side: CGFloat = 353
            for _ in 0..<2_000 {
                let point = CGPoint(x: Double(random.nextInt(below: 353_000)) / 1_000, y: Double(random.nextInt(below: 353_000)) / 1_000)
                let tap = DartboardView.tap(at: point, in: square(side), geometry: geometry)
                #expect(BoardGeometry.standard.hit(at: tap.position) == tap.hit, "\(name), \(point)")
                // Drawing the nominal position gives back the tapped point.
                let back = DartboardView.location(of: tap.position, in: square(side), geometry: geometry)
                #expect(abs(back.x - point.x) < 1e-6 && abs(back.y - point.y) < 1e-6, "\(name), \(point)")
            }
        }
    }

    // MARK: Off the scoring area

    @Test func tapOutsideTheDouble_isAMiss_andKeepsItsPosition() {
        let side: CGFloat = 300
        // Between the double and the edge of the board: the number ring.
        let ring = DartboardView.tap(at: viewPoint(radius: 180, degrees: 90, side: side), in: square(side), geometry: .display)
        #expect(ring.hit == .miss)
        // 173.6…225.5 of the drawing is 170…225.5 of the regulation board.
        let expected = 170 + (180 - 173.6) / (225.5 - 173.6) * (225.5 - 170)
        #expect(abs(ring.position.radius - expected) < 1e-9 && abs(ring.position.y) < 1e-9 && ring.position.x > 0)
        let same = DartboardView.tap(at: viewPoint(radius: 180, degrees: 90, side: side), in: square(side), geometry: .standard)
        #expect(same.hit == .miss && abs(same.position.radius - 180) < 1e-9)
        // The corners of the view are beyond the board.
        for corner in [CGPoint(x: 0, y: 0), CGPoint(x: 300, y: 0), CGPoint(x: 0, y: 300), CGPoint(x: 300, y: 300)] {
            for (name, geometry) in geometries {
                let tap = DartboardView.tap(at: corner, in: square(side), geometry: geometry)
                #expect(tap.hit == .miss, "\(name)")
                #expect(abs(tap.position.radius - 225.5 * 2.0.squareRoot()) < 1e-6, "\(name)")
            }
        }
    }

    // MARK: Discs under `.standard` (Radar)

    @Test func discEdge_underStandard_onePointInsideIsInside_onePointOutsideIsOutside() {
        // The five targets of RAD-1 (GAMES.md §15.9): (x, y, radius) in nominal millimetres.
        let discs: [(x: Double, y: Double, radius: Double)] = [(-80, 95, 40), (70, -65, 40), (110, 65, 28), (25, 15, 28), (140, 0, 16)]
        for side in [300, 353, 720] as [CGFloat] {
            let size = square(side)
            for disc in discs {
                let middle = DartboardView.location(of: BoardPoint(x: disc.x, y: disc.y), in: size, geometry: .standard)
                let radius = DartboardView.length(of: disc.radius, in: size)
                for step in 0..<24 {
                    let angle = Double(step) * 15 * .pi / 180
                    func tap(_ distance: CGFloat) -> BoardTap {
                        DartboardView.tap(at: CGPoint(x: middle.x + distance * cos(angle), y: middle.y + distance * sin(angle)), in: size,
                                          geometry: .standard)
                    }
                    let inside = tap(radius - 1).position, outside = tap(radius + 1).position
                    let centre = BoardPoint(x: disc.x, y: disc.y)
                    #expect(distance(inside, centre) < disc.radius, "disc \(disc), side \(side), step \(step)")
                    #expect(distance(outside, centre) > disc.radius, "disc \(disc), side \(side), step \(step)")
                    // Exactly one point of view: 1 pt is `1 / k` millimetres.
                    let millimetre = 225.5 / (Double(side) / 2)
                    #expect(abs(distance(inside, centre) - (disc.radius - millimetre)) < 1e-6)
                    #expect(abs(distance(outside, centre) - (disc.radius + millimetre)) < 1e-6)
                }
                // Under `.standard` the position is the tapped point itself: the centre of the drawn disc is its centre.
                #expect(distance(DartboardView.tap(at: middle, in: size, geometry: .standard).position, BoardPoint(x: disc.x, y: disc.y)) < 1e-9)
            }
        }
    }

    // MARK: Unusual input

    @Test func viewWithoutASize_orAPointThatIsNotANumber_isAMissAtTheCentre() {
        for (name, geometry) in geometries {
            let nowhere = BoardTap(hit: .miss, position: .centre)
            #expect(DartboardView.tap(at: CGPoint(x: 10, y: 10), in: .zero, geometry: geometry) == nowhere, "\(name)")
            #expect(DartboardView.tap(at: CGPoint(x: CGFloat.nan, y: 10), in: square(300), geometry: geometry) == nowhere, "\(name)")
            #expect(DartboardView.tap(at: CGPoint(x: 10, y: CGFloat.infinity), in: square(300), geometry: geometry) == nowhere, "\(name)")
            #expect(DartboardView.tap(at: CGPoint(x: 10, y: 10), in: CGSize(width: CGFloat.infinity, height: 300), geometry: geometry).hit == .miss)
            #expect(DartboardView.tap(at: CGPoint(x: 10, y: 10), in: CGSize(width: -300, height: -300), geometry: geometry) == nowhere, "\(name)")
            // A position that cannot be drawn does not trap either.
            let lost = DartboardView.location(of: BoardPoint(x: .nan, y: 0), in: square(300), geometry: geometry)
            #expect(lost.x.isNaN)
            #expect(DartboardView.location(of: BoardPoint(x: 10, y: 10), in: .zero, geometry: geometry) == .zero)
        }
    }
}
