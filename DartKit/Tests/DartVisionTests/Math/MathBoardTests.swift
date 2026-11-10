import Foundation
import simd
import Testing
import DartCore
@testable import DartVision

/// Board conventions of VISION.md §3.3 and the ring-radius remap of §4.6 (M8, M9).
@Suite struct MathBoardTests {
    /// Clockwise angle from +y, degrees, to a board point.
    private func point(radius: Double, degrees: Double) -> BoardPoint {
        BoardPoint(x: radius * sin(degrees * .pi / 180), y: radius * cos(degrees * .pi / 180))
    }

    /// One zone of the board: a representative point in its middle, its hit and the colour of VISION.md §3.3.
    private struct Zone {
        var name: String
        var centre: BoardPoint
        var hit: Hit
        var surface: BoardModel.Surface
    }

    /// The 82 zones: inner bull, outer bull, and for each of the 20 sectors the inner single, the treble, the
    /// outer single and the double.
    private var zones: [Zone] {
        let order = BoardGeometry.standard.sectorOrder
        var result = [Zone(name: "DB", centre: BoardPoint(x: 0, y: 0), hit: .innerBull, surface: .red),
                      Zone(name: "SB", centre: point(radius: (6.35 + 15.9) / 2, degrees: 0), hit: .outerBull, surface: .green)]
        for k in 0..<20 {
            let number = order[k], degrees = 18 * Double(k), light = k % 2 == 1
            result.append(Zone(name: "inner S\(number)", centre: point(radius: (15.9 + 99) / 2, degrees: degrees),
                               hit: .single(number), surface: light ? .cream : .black))
            result.append(Zone(name: "T\(number)", centre: point(radius: 103, degrees: degrees),
                               hit: .treble(number), surface: light ? .green : .red))
            result.append(Zone(name: "outer S\(number)", centre: point(radius: (107 + 162) / 2, degrees: degrees),
                               hit: .single(number), surface: light ? .cream : .black))
            result.append(Zone(name: "D\(number)", centre: point(radius: 166, degrees: degrees),
                               hit: .double(number), surface: light ? .green : .red))
        }
        return result
    }

    // MARK: M8

    @Test func m8_twentyUpSixRightThreeDownElevenLeft() {
        let board = BoardGeometry.standard
        #expect(board.hit(at: BoardPoint(x: 0, y: 130)) == .single(20))
        #expect(board.hit(at: BoardPoint(x: 130, y: 0)) == .single(6))
        #expect(board.hit(at: BoardPoint(x: 0, y: -130)) == .single(3))
        #expect(board.hit(at: BoardPoint(x: -130, y: 0)) == .single(11))
        #expect(BoardModel.sectorIndex(at: BoardPoint(x: 0, y: 130)) == 0)
        #expect(BoardModel.sectorIndex(at: BoardPoint(x: 130, y: 0)) == 5)
        #expect(BoardModel.sectorIndex(at: BoardPoint(x: 0, y: -130)) == 10)
        #expect(BoardModel.sectorIndex(at: BoardPoint(x: -130, y: 0)) == 15)
        // The 20 is black and red, its neighbour the 1 is cream and green (VISION.md §3.3).
        #expect(BoardModel.surface(at: BoardPoint(x: 0, y: 130)) == .black && BoardModel.surface(at: BoardPoint(x: 0, y: 103)) == .red)
        #expect(BoardModel.surface(at: point(radius: 130, degrees: 18)) == .cream && BoardModel.surface(at: point(radius: 103, degrees: 18)) == .green)
        // Boundaries 20/1 at 9 degrees and 5/20 at 351 degrees.
        #expect(board.hit(at: point(radius: 130, degrees: 8.99)) == .single(20) && board.hit(at: point(radius: 130, degrees: 9.01)) == .single(1))
        #expect(board.hit(at: point(radius: 130, degrees: 350.99)) == .single(5) && board.hit(at: point(radius: 130, degrees: 351.01)) == .single(20))
        // In a physical view from below, the 20 is at the top of the image, the 6 on the right, the 3 at the
        // bottom and the 11 on the left, for every reference pose.
        for camera in SupportPoses.cameras {
            let bull = camera.project(SIMD3(0, 0, 0))
            let twenty = camera.project(SIMD3(0, 140, 0)), six = camera.project(SIMD3(140, 0, 0))
            let three = camera.project(SIMD3(0, -140, 0)), eleven = camera.project(SIMD3(-140, 0, 0))
            #expect(twenty.y < bull.y && abs(twenty.x - bull.x) < abs(twenty.y - bull.y), "20 up, \(camera.position)")
            #expect(six.x > bull.x && abs(six.y - bull.y) < abs(six.x - bull.x), "6 right, \(camera.position)")
            #expect(three.y > bull.y && abs(three.x - bull.x) < abs(three.y - bull.y), "3 down, \(camera.position)")
            #expect(eleven.x < bull.x && abs(eleven.y - bull.y) < abs(eleven.x - bull.x), "11 left, \(camera.position)")
        }
        // The canvas has the 20 at the top too: row 0 is y = +320 mm, column 0 is x = −320 mm.
        #expect(BoardCanvas.boardPoint(x: 0, y: 0) == BoardPoint(x: -319.75, y: 319.75))
        #expect(BoardCanvas.boardPoint(x: 639.5, y: 639.5) == BoardPoint(x: 0, y: 0))
        #expect(BoardCanvas.pixel(for: BoardPoint(x: 0, y: 140)) == SIMD2(639.5, 359.5))
        #expect(BoardCanvas.pixel(for: BoardPoint(x: 140, y: 0)) == SIMD2(919.5, 639.5))
    }

    @Test func m8_theCentresOfThe82Zones() {
        let board = BoardGeometry.standard
        let model = SyntheticBoard(radii: .nominal)
        let all = zones
        #expect(all.count == 82)
        for zone in all {
            #expect(board.hit(at: zone.centre) == zone.hit, "\(zone.name)")
            #expect(BoardModel.surface(at: zone.centre) == zone.surface, "\(zone.name)")
            #expect(BoardModel.surface(of: zone.hit, sectorIndex: BoardModel.sectorIndex(at: zone.centre)) == zone.surface, "\(zone.name)")
            // The renderer's colour model gives the same paint, and no wire is there.
            #expect(model.surface(x: zone.centre.x, y: zone.centre.y) == SyntheticBoard.Paint(zone.surface), "\(zone.name)")
            #expect(model.paint(x: zone.centre.x, y: zone.centre.y) == SyntheticBoard.Paint(zone.surface), "\(zone.name)")
        }
        // Off the board: the number ring, then the wall.
        #expect(board.hit(at: BoardPoint(x: 0, y: 200)) == .miss && BoardModel.surface(at: BoardPoint(x: 0, y: 200)) == .numberRing)
        #expect(BoardModel.surface(at: BoardPoint(x: 0, y: 230)) == .wall && model.paint(x: 0, y: 230) == .wall)
        #expect(model.paint(x: 0, y: 200) == .numberRing)
    }

    @Test func m8_aHundredthOfADegreeAroundEachWire() {
        let board = BoardGeometry.standard
        let model = SyntheticBoard(radii: .nominal)
        let order = board.sectorOrder
        for m in 0..<20 {
            let wire = 9 + 18 * Double(m)
            // Sector k is anticlockwise of wire m, sector k + 1 clockwise of it.
            let before = order[m], after = order[(m + 1) % 20]
            for radius in [40.0, 103, 130, 166] {
                let left = point(radius: radius, degrees: wire - 0.01), right = point(radius: radius, degrees: wire + 0.01)
                let leftHit = board.hit(at: left), rightHit = board.hit(at: right)
                #expect(leftHit.number == before && rightHit.number == after, "wire \(m) at r = \(radius)")
                #expect(BoardModel.sectorIndex(at: left) == m && BoardModel.sectorIndex(at: right) == (m + 1) % 20)
                // The signed distance to the wire changes sign across it: negative on the anticlockwise side.
                #expect(BoardModel.signedDistanceToWire(m, left) < 0 && BoardModel.signedDistanceToWire(m, right) > 0)
                // The colour model flips between the two sides (a light and a dark sector meet on every wire).
                #expect(model.surface(x: left.x, y: left.y) != model.surface(x: right.x, y: right.y), "wire \(m) at r = \(radius)")
                #expect(model.surface(x: left.x, y: left.y) == SyntheticBoard.Paint(BoardModel.surface(at: left)))
                #expect(model.surface(x: right.x, y: right.y) == SyntheticBoard.Paint(BoardModel.surface(at: right)))
                // Both points are under the 1.4 mm wire.
                #expect(model.isWire(x: left.x, y: left.y) && model.isWire(x: right.x, y: right.y))
            }
            // The wire direction is (sin α, cos α).
            let direction = BoardModel.wireDirection(m)
            #expect(abs(direction.x - sin(wire * .pi / 180)) < 1e-15 && abs(direction.y - cos(wire * .pi / 180)) < 1e-15)
        }
    }

    // MARK: M9

    @Test func m9_ringRadiiRemap() {
        let measured = RingRadii(innerBull: 6.0, outerBull: 16.5, trebleInner: 98, trebleOuter: 106.5, doubleInner: 161.2, doubleOuter: 170)
        // The knots land on the nominal radii.
        let pairs: [(Double, Double)] = [(measured.innerBull, 6.35), (measured.outerBull, 15.9), (measured.trebleInner, 99),
                                         (measured.trebleOuter, 107), (measured.doubleInner, 162), (170, 170)]
        for degrees in stride(from: 0.0, to: 360, by: 37) {
            for (radius, nominal) in pairs {
                let mapped = measured.toNominal(point(radius: radius, degrees: degrees))
                let expected = point(radius: nominal, degrees: degrees)
                #expect(abs(mapped.x - expected.x) < 1e-9 && abs(mapped.y - expected.y) < 1e-9, "r = \(radius) at \(degrees)")
                let back = measured.fromNominal(expected)
                let original = point(radius: radius, degrees: degrees)
                #expect(abs(back.x - original.x) < 1e-9 && abs(back.y - original.y) < 1e-9)
            }
        }
        // Round trips anywhere, the angle unchanged; the identity beyond 170 mm.
        var random = SupportRandom(seed: 0x4D39)
        var worst = 0.0
        for _ in 0..<2000 {
            let p = random.boardPoint(maxRadius: 260)
            let there = measured.toNominal(p)
            let back = measured.fromNominal(there)
            worst = max(worst, hypot(back.x - p.x, back.y - p.y))
            let other = measured.toNominal(measured.fromNominal(p))
            worst = max(worst, hypot(other.x - p.x, other.y - p.y))
            #expect(abs(atan2(there.x, there.y) - atan2(p.x, p.y)) < 1e-12 || hypot(p.x, p.y) < 1e-9)
            if hypot(p.x, p.y) >= 170 {
                #expect(abs(there.x - p.x) < 1e-12 && abs(there.y - p.y) < 1e-12)
            }
        }
        #expect(worst < 1e-9, "round trip \(worst) mm")
        // Linear between the knots: half-way between the measured trebles is half-way between the nominal ones.
        let middle = measured.toNominal(BoardPoint(x: 0, y: (98 + 106.5) / 2))
        #expect(abs(middle.y - 103) < 1e-12 && middle.x == 0)
        // The nominal radii remap nothing; the centre and a non-finite point stay where they are.
        for _ in 0..<200 {
            let p = random.boardPoint(maxRadius: 250)
            let same = RingRadii.nominal.toNominal(p)
            #expect(abs(same.x - p.x) < 1e-12 && abs(same.y - p.y) < 1e-12)
        }
        #expect(measured.toNominal(BoardPoint(x: 0, y: 0)) == BoardPoint(x: 0, y: 0))
        #expect(measured.toNominal(BoardPoint(x: .nan, y: 1)).x.isNaN)
        // A point that DartCore scores on the measured board scores the same after the remap: a dart in the
        // measured treble (98 to 106.5) is a treble on the nominal geometry, one just outside it is not.
        #expect(BoardGeometry.standard.hit(at: measured.toNominal(point(radius: 98.2, degrees: 0))) == .treble(20))
        #expect(BoardGeometry.standard.hit(at: measured.toNominal(point(radius: 97.8, degrees: 0))) == .single(20))
        #expect(BoardGeometry.standard.hit(at: measured.toNominal(point(radius: 106.4, degrees: 0))) == .treble(20))
        #expect(BoardGeometry.standard.hit(at: measured.toNominal(point(radius: 106.6, degrees: 0))) == .single(20))
    }
}
