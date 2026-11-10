import Foundation
import Testing
import DartCore

/// `BoardPoint` and `BoardGeometry` (ARCHITECTURE.md §4.2, GAMES.md §2.1, VISION.md §3.3).
@Suite struct SmokeGeometryTests {
    private let board = BoardGeometry.standard
    /// A drawing geometry with thicker rings, as DartUI builds one (DESIGN.md §3).
    private let thick = BoardGeometry(innerBullRadius: 6.35, outerBullRadius: 15.9,
                                      trebleInnerRadius: 97.0, trebleOuterRadius: 110.5,
                                      doubleInnerRadius: 160.1, doubleOuterRadius: 173.6, boardRadius: 225.5)

    /// The 82 zones of the scoring area with a point in their middle: 20 sectors x 4 bands, and the two bulls.
    private func zoneCentres(of geometry: BoardGeometry) -> [(point: BoardPoint, hit: Hit)] {
        func mid(_ band: BoardGeometry.Band) -> Double {
            let range = geometry.radialRange(of: band)
            return (range.lowerBound + range.upperBound) / 2
        }
        var zones: [(point: BoardPoint, hit: Hit)] = [
            (BoardPoint.centre, .innerBull),
            (BoardPoint(radius: mid(.outerBull), clockwiseDegrees: 123), .outerBull),
        ]
        for number in 1...20 {
            let angle = geometry.centreAngle(of: number)
            zones.append((BoardPoint(radius: mid(.innerSingle), clockwiseDegrees: angle), .single(number)))
            zones.append((BoardPoint(radius: mid(.treble), clockwiseDegrees: angle), .treble(number)))
            zones.append((BoardPoint(radius: mid(.outerSingle), clockwiseDegrees: angle), .single(number)))
            zones.append((BoardPoint(radius: mid(.double), clockwiseDegrees: angle), .double(number)))
        }
        return zones
    }

    // MARK: Frame

    @Test func frame_twentyUp_sixRight_threeDown_elevenLeft() {
        #expect(board.hit(at: BoardPoint(x: 0, y: 134.5)) == .single(20))
        #expect(board.hit(at: BoardPoint(x: 134.5, y: 0)) == .single(6))
        #expect(board.hit(at: BoardPoint(x: 0, y: -134.5)) == .single(3))
        #expect(board.hit(at: BoardPoint(x: -134.5, y: 0)) == .single(11))
        #expect(BoardPoint(x: 0, y: 10).clockwiseDegrees == 0)
        #expect(BoardPoint(x: 10, y: 0).clockwiseDegrees == 90)
        #expect(BoardPoint(x: 0, y: -10).clockwiseDegrees == 180)
        #expect(BoardPoint(x: -10, y: 0).clockwiseDegrees == 270)
        #expect(BoardPoint.centre == BoardPoint(x: 0, y: 0) && BoardPoint.centre.radius == 0)
        #expect(BoardPoint(x: 3, y: 4).radius == 5)
    }

    /// The angle is in [0, 360): a point a hair to the left of the +y axis is on the axis, it is not at 360°.
    @Test func clockwiseDegrees_neverReaches360() {
        for x in [-1e-13, -1e-15, -1e-17, -1e-20, -1e-300, -Double.leastNonzeroMagnitude] {
            let degrees = BoardPoint(x: x, y: 1).clockwiseDegrees
            #expect(degrees >= 0 && degrees < 360, "x = \(x)")
            // What any caller may compute from the documented range.
            #expect(Int(degrees / BoardGeometry.sectorWidthDegrees) < 20, "x = \(x)")
        }
        // Too close to the axis to be told from it: 0°, the middle of the 20.
        #expect(BoardPoint(x: -1e-17, y: 1).clockwiseDegrees == 0)
        #expect(BoardPoint(x: -Double.leastNonzeroMagnitude, y: 1).clockwiseDegrees == 0)
        #expect(board.hit(at: BoardPoint(x: -1e-17, y: 134.5)) == .single(20))
        // An angle that a Double can tell from a full turn is returned as it is.
        let justBelow = BoardPoint(x: -1e-9, y: 1).clockwiseDegrees
        #expect(justBelow > 359.9999999 && justBelow < 360)
    }

    @Test func polarConstructor_isClockwiseFromTheTwenty() {
        let up = BoardPoint(radius: 100, clockwiseDegrees: 0)
        #expect(abs(up.x) < 1e-9 && abs(up.y - 100) < 1e-9)
        let right = BoardPoint(radius: 100, clockwiseDegrees: 90)
        #expect(abs(right.x - 100) < 1e-9 && abs(right.y) < 1e-9)
        for degrees in stride(from: 0.5, to: 360, by: 7.25) {
            let point = BoardPoint(radius: 55, clockwiseDegrees: degrees)
            #expect(abs(point.radius - 55) < 1e-9)
            #expect(abs(point.clockwiseDegrees - degrees) < 1e-9)
        }
    }

    @Test func standardDimensions() {
        #expect(BoardGeometry.standardSectorOrder == [20, 1, 18, 4, 13, 6, 10, 15, 2, 17, 3, 19, 7, 16, 8, 11, 14, 9, 12, 5])
        #expect(board.sectorOrder == BoardGeometry.standardSectorOrder)
        #expect(board.innerBullRadius == 6.35 && board.outerBullRadius == 15.9)
        #expect(board.trebleInnerRadius == 99 && board.trebleOuterRadius == 107)
        #expect(board.doubleInnerRadius == 162 && board.doubleOuterRadius == 170)
        #expect(board.boardRadius == 225.5)
        #expect(BoardGeometry.sectorWidthDegrees == 18)
        #expect(BoardGeometry.Band.allCases == [.innerBull, .outerBull, .innerSingle, .treble, .outerSingle, .double])
        #expect(board.radialRange(of: .innerBull) == 0...6.35)
        #expect(board.radialRange(of: .outerBull) == 6.35...15.9)
        #expect(board.radialRange(of: .innerSingle) == 15.9...99)
        #expect(board.radialRange(of: .treble) == 99...107)
        #expect(board.radialRange(of: .outerSingle) == 107...162)
        #expect(board.radialRange(of: .double) == 162...170)
    }

    // MARK: Scoring

    @Test func centreOfThe82Zones() {
        let zones = zoneCentres(of: board)
        #expect(zones.count == 82)
        for zone in zones {
            #expect(board.hit(at: zone.point) == zone.hit, "at \(zone.point)")
        }
        // Every one of the 62 scoring hits is reached, and nothing else.
        #expect(Set(zones.map(\.hit)) == Set(Hit.all.filter { !$0.isMiss }))
    }

    @Test func beyondTheOuterDoubleIsAMiss() {
        for degrees in stride(from: 0.0, to: 360, by: 4.5) {
            #expect(board.hit(at: BoardPoint(radius: 170.01, clockwiseDegrees: degrees)) == .miss)
            #expect(board.hit(at: BoardPoint(radius: 225.5, clockwiseDegrees: degrees)) == .miss)
            #expect(board.hit(at: BoardPoint(radius: 1000, clockwiseDegrees: degrees)) == .miss)
        }
    }

    /// A point with a coordinate that is not finite (a degenerate projection) is off the board: MISS, never a trap.
    /// The same goes for a finite coordinate so large that the radius overflows.
    @Test func aNonFiniteCoordinate_isAMiss_andNeverTraps() {
        let values: [Double] = [.nan, .signalingNaN, .infinity, -.infinity, 1e200, -1e200, .greatestFiniteMagnitude]
        for value in values {
            let points = [BoardPoint(x: value, y: 0), BoardPoint(x: 0, y: value), BoardPoint(x: value, y: value),
                          BoardPoint(x: value, y: -value), BoardPoint(x: 12, y: value), BoardPoint(x: value, y: -150)]
            for point in points {
                #expect(board.hit(at: point) == .miss, "at \(point)")
                #expect(thick.hit(at: point) == .miss, "at \(point)")
                #expect((0...19).contains(board.sectorIndex(at: point)), "at \(point)")
                // Remapping does not bring such a point back onto the board, in either direction.
                #expect(thick.hit(at: board.remap(point, to: thick)) == .miss, "at \(point)")
                #expect(board.hit(at: thick.remap(point, to: board)) == .miss, "at \(point)")
            }
        }
        // No wedge contains a point without an angle: index 0, by convention.
        #expect(board.sectorIndex(at: BoardPoint(x: .nan, y: 100)) == 0)
        #expect(board.sectorIndex(at: BoardPoint(x: 100, y: .nan)) == 0)
        // An infinite point keeps its angle: it is on the side of the 6, and it is returned as it is by `remap`.
        let far = BoardPoint(x: .infinity, y: 0)
        #expect(board.sectorIndex(at: far) == board.sectorIndex(of: 6))
        #expect(board.remap(far, to: thick) == far)
    }

    /// 0.01° on each side of the twenty radial wires (9°, 27°, …, 351°), in every band.
    @Test func hundredthOfADegreeFromEachWire() {
        let order = board.sectorOrder
        for index in 0..<20 {
            let wire = 9 + 18 * Double(index)
            let before = order[index], after = order[(index + 1) % 20]
            for (radius, bed) in [(57.0, Hit.Bed.single), (103.0, .treble), (134.5, .single), (166.0, .double)] {
                let anticlockwise = board.hit(at: BoardPoint(radius: radius, clockwiseDegrees: wire - 0.01))
                let clockwise = board.hit(at: BoardPoint(radius: radius, clockwiseDegrees: wire + 0.01))
                #expect(anticlockwise == Hit(bed: bed, number: before), "wire \(wire), radius \(radius)")
                #expect(clockwise == Hit(bed: bed, number: after), "wire \(wire), radius \(radius)")
            }
        }
    }

    /// On a ring boundary the higher-scoring bed wins (bull, treble, double).
    @Test func boundaryRule_rings() {
        func hit(_ radius: Double) -> Hit { board.hit(at: BoardPoint(x: 0, y: radius)) }
        #expect(hit(6.35) == .innerBull)
        #expect(hit(6.35.nextUp) == .outerBull)
        #expect(hit(15.9) == .outerBull)
        #expect(hit(15.9.nextUp) == .single(20))
        #expect(hit(99.0.nextDown) == .single(20))
        #expect(hit(99) == .treble(20))
        #expect(hit(107) == .treble(20))
        #expect(hit(107.0.nextUp) == .single(20))
        #expect(hit(162.0.nextDown) == .single(20))
        #expect(hit(162) == .double(20))
        #expect(hit(170) == .double(20))
        #expect(hit(170.0.nextUp) == .miss)
    }

    /// On a radial wire the clockwise sector wins. The four diagonal wires (45°, 135°, 225°, 315°) are exact in
    /// floating point: |x| == |y|.
    @Test func boundaryRule_radialWires() {
        let cases: [(x: Double, y: Double, anticlockwise: Int, clockwise: Int)] = [
            (1, 1, 18, 4), (1, -1, 15, 2), (-1, -1, 7, 16), (-1, 1, 9, 12),
        ]
        for wire in cases {
            let point = BoardPoint(x: 80 * wire.x, y: 80 * wire.y)
            #expect(board.areAdjacent(wire.anticlockwise, wire.clockwise))
            #expect(board.neighbours(of: wire.anticlockwise).clockwise == wire.clockwise)
            #expect(board.hit(at: point) == .single(wire.clockwise))
            #expect(board.sectorIndex(at: point) == board.sectorIndex(of: wire.clockwise))
            // The same wire in the treble and double rings.
            #expect(board.hit(at: BoardPoint(x: 72.5 * wire.x, y: 72.5 * wire.y)) == .treble(wire.clockwise))
            #expect(board.hit(at: BoardPoint(x: 117 * wire.x, y: 117 * wire.y)) == .double(wire.clockwise))
        }
    }

    @Test func sectorIndex_followsTheFormula() {
        for tenth in 0..<3600 {
            let degrees = Double(tenth) / 10 + 0.05
            let expected = Int(((degrees + 9).truncatingRemainder(dividingBy: 360)) / 18)
            #expect(board.sectorIndex(at: BoardPoint(radius: 120, clockwiseDegrees: degrees)) == expected)
        }
        // The 20 straddles the top: -9°...+9°.
        #expect(board.sectorIndex(at: BoardPoint(radius: 120, clockwiseDegrees: 355)) == 0)
        #expect(board.sectorIndex(at: BoardPoint(radius: 120, clockwiseDegrees: 5)) == 0)
    }

    // MARK: Sectors

    @Test func neighbours_examplesOfGames2_1() {
        #expect(board.neighbours(of: 20) == (5, 1))
        #expect(board.neighbours(of: 1) == (20, 18))
        #expect(board.neighbours(of: 7) == (19, 16))
        #expect(board.neighbours(of: 2) == (15, 17))
        #expect(board.neighbours(of: 5) == (12, 20))
        for number in 1...20 {
            let both = board.neighbours(of: number)
            #expect(board.areAdjacent(number, both.anticlockwise) && board.areAdjacent(number, both.clockwise))
            #expect(board.areAdjacent(both.clockwise, number))
            #expect(board.neighbours(of: both.clockwise).anticlockwise == number)
            #expect(!board.areAdjacent(number, number))
            #expect((1...20).filter { board.areAdjacent(number, $0) }.count == 2)
        }
        #expect(!board.areAdjacent(20, 3) && !board.areAdjacent(6, 11))
    }

    @Test func sectorAngles() {
        #expect(board.centreAngle(of: 20) == 0)
        #expect(board.centreAngle(of: 1) == 18)
        #expect(board.centreAngle(of: 6) == 90)
        #expect(board.centreAngle(of: 3) == 180)
        #expect(board.centreAngle(of: 11) == 270)
        #expect(board.centreAngle(of: 5) == 342)
        #expect(board.angularRange(of: 20) == -9...9)
        #expect(board.angularRange(of: 6) == 81...99)
        for (index, number) in board.sectorOrder.enumerated() {
            #expect(board.sectorIndex(of: number) == index)
            #expect(board.centreAngle(of: number) == Double(index) * 18)
        }
    }

    // MARK: Representative points

    @Test func centreOfAHit_isInTheMiddleOfItsBed() {
        #expect(board.centre(of: .miss) == nil)
        #expect(board.centre(of: .innerBull) == .centre)
        // SB: the middle of the outer bull ring, towards the 20.
        let outerBull = board.centre(of: .outerBull)
        #expect(abs((outerBull?.x ?? 1)) < 1e-9 && abs((outerBull?.y ?? 0) - 11.125) < 1e-9)
        for hit in Hit.all where !hit.isMiss {
            guard let centre = board.centre(of: hit) else {
                Issue.record("no centre for \(hit)")
                continue
            }
            #expect(board.hit(at: centre) == hit)
        }
        // Singles use the OUTER single band; trebles and doubles the middle of their ring.
        for number in 1...20 {
            #expect(abs((board.centre(of: .single(number))?.radius ?? 0) - 134.5) < 1e-9)
            #expect(abs((board.centre(of: .treble(number))?.radius ?? 0) - 103) < 1e-9)
            #expect(abs((board.centre(of: .double(number))?.radius ?? 0) - 166) < 1e-9)
        }
    }

    // MARK: Remapping

    @Test func remap_keepsTheBed_inBothDirections() {
        for zone in zoneCentres(of: board) {
            #expect(thick.hit(at: board.remap(zone.point, to: thick)) == zone.hit)
        }
        for zone in zoneCentres(of: thick) {
            #expect(board.hit(at: thick.remap(zone.point, to: board)) == zone.hit)
        }
        // A tap in the middle of the DRAWN treble ring lands in the regulation treble ring.
        let drawn = BoardPoint(radius: 109, clockwiseDegrees: 0)
        #expect(board.hit(at: drawn) == .single(20))
        #expect(thick.hit(at: drawn) == .treble(20))
        #expect(board.hit(at: thick.remap(drawn, to: board)) == .treble(20))
    }

    @Test func remap_roundTrip_keepsAnglesAndBoundaries() {
        for radius in stride(from: 0.5, through: 260, by: 3.7) {
            for degrees in [0.0, 13, 90, 187.3, 270, 351] {
                let point = BoardPoint(radius: radius, clockwiseDegrees: degrees)
                let there = board.remap(point, to: thick)
                let back = thick.remap(there, to: board)
                #expect(abs(back.x - point.x) < 1e-9 && abs(back.y - point.y) < 1e-9)
                // Angles are unchanged.
                #expect(abs(there.x * point.y - there.y * point.x) < 1e-6)
            }
        }
        // Every ring boundary lands on the same boundary of the other geometry.
        let pairs: [(Double, Double)] = [(6.35, 6.35), (15.9, 15.9), (99, 97.0), (107, 110.5), (162, 160.1), (170, 173.6), (225.5, 225.5)]
        for (from, to) in pairs {
            let mapped = board.remap(BoardPoint(x: 0, y: from), to: thick)
            #expect(abs(mapped.radius - to) < 1e-9)
            #expect(mapped.x == 0)
        }
        // Beyond the board the scale is that of the number ring (the same radius in both geometries).
        #expect(abs(board.remap(BoardPoint(x: 300, y: 0), to: thick).x - 300) < 1e-9)
        // The centre stays where it is, and a geometry maps onto itself.
        #expect(board.remap(.centre, to: thick) == .centre)
        let any = BoardPoint(x: 41.5, y: -77.25)
        let same = board.remap(any, to: board)
        #expect(abs(same.x - any.x) < 1e-9 && abs(same.y - any.y) < 1e-9)
    }

    @Test func geometryIsAValue_withACustomSectorOrder() {
        var mirrored = board
        mirrored.sectorOrder = Array(board.sectorOrder.reversed())
        #expect(mirrored != board)
        #expect(mirrored.hit(at: BoardPoint(x: 0, y: 134.5)) == .single(5))
        #expect(board.hit(at: BoardPoint(x: 0, y: 134.5)) == .single(20))
        #expect(BoardGeometry(innerBullRadius: 6.35, outerBullRadius: 15.9, trebleInnerRadius: 99, trebleOuterRadius: 107,
                              doubleInnerRadius: 162, doubleOuterRadius: 170, boardRadius: 225.5) == board)
    }
}
