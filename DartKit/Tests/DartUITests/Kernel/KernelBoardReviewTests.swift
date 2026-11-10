import Foundation
import CoreGraphics
import SwiftUI
import Testing
import DartCore
@testable import DartUI

/// Independent review of the board conversions and drawing (ARCHITECTURE.md §8.4.3, DESIGN.md §3 and §4):
/// properties over random sizes and points with fixed seeds, exact wires, and the picture against the taps in
/// frames of every aspect ratio.
@MainActor
@Suite struct KernelBoardReviewTests {
    private typealias RGB = KernelBitmap.RGB
    private let geometries: [(name: String, geometry: BoardGeometry)] = [("display", .display), ("standard", .standard)]

    private func square(_ side: CGFloat) -> CGSize { CGSize(width: side, height: side) }

    /// A uniform double in `range`, from the seeded generator (no system randomness in tests).
    private func uniform(_ random: inout SeededRandom, _ range: ClosedRange<Double>) -> Double {
        range.lowerBound + Double(random.nextInt(below: 1_000_000_007)) / 1_000_000_006 * (range.upperBound - range.lowerBound)
    }

    /// The radii of the six ring wires of a geometry.
    private func ringWires(_ geometry: BoardGeometry) -> [Double] {
        [geometry.innerBullRadius, geometry.outerBullRadius, geometry.trebleInnerRadius, geometry.trebleOuterRadius,
         geometry.doubleInnerRadius, geometry.doubleOuterRadius]
    }

    // MARK: Conversions

    @Test func anyTap_atAnySize_scoresWhatItsNominalPositionScores() {
        var random = SeededRandom(seed: 77)
        for (name, geometry) in geometries {
            for _ in 0..<6_000 {
                let side = CGFloat(uniform(&random, 8...2_000))
                let point = CGPoint(x: uniform(&random, -10...Double(side) + 10), y: uniform(&random, -10...Double(side) + 10))
                let tap = DartboardView.tap(at: point, in: square(side), geometry: geometry)
                #expect(BoardGeometry.standard.hit(at: tap.position) == tap.hit, "\(name), side \(side), \(point)")
            }
        }
    }

    @Test func exactRingWires_tapAndNominalPositionAgree_atEverySize() {
        // A point of the view exactly on a drawn ring wire, along the four axes, at sizes from 36 pt to 1 024 pt.
        var mismatches: [String] = []
        for (name, geometry) in geometries {
            for tenths in stride(from: 360, through: 10_240, by: 13) {
                let side = CGFloat(tenths) / 10
                let k = side / 2 / 225.5
                for radius in ringWires(geometry) {
                    for (dx, dy) in [(0.0, 1.0), (1.0, 0.0), (0.0, -1.0), (-1.0, 0.0)] {
                        let point = CGPoint(x: side / 2 + CGFloat(dx * radius) * k, y: side / 2 - CGFloat(dy * radius) * k)
                        let tap = DartboardView.tap(at: point, in: square(side), geometry: geometry)
                        if BoardGeometry.standard.hit(at: tap.position) != tap.hit {
                            mismatches.append("\(name) side \(side) r \(radius) (\(dx), \(dy)): \(tap.hit) vs \(BoardGeometry.standard.hit(at: tap.position))")
                        }
                    }
                }
            }
        }
        #expect(mismatches.isEmpty, "\(mismatches.count) mismatches, first: \(mismatches.prefix(5))")
    }

    @Test func underStandard_thePositionIsTheTouchedPointItself() {
        // §8.4.3: "Avec .standard, la position est le point touché lui-même."
        var random = SeededRandom(seed: 5)
        var different: [String] = []
        for _ in 0..<5_000 {
            let side = CGFloat(uniform(&random, 36...1_200))
            let point = CGPoint(x: uniform(&random, 0...Double(side)), y: uniform(&random, 0...Double(side)))
            let k = Double(side) / 2 / 225.5
            let touched = BoardPoint(x: (Double(point.x) - Double(side) / 2) / k, y: (Double(side) / 2 - Double(point.y)) / k)
            let tap = DartboardView.tap(at: point, in: square(side), geometry: .standard)
            if tap.position != touched && abs(tap.position.x - touched.x) + abs(tap.position.y - touched.y) > 1e-9 {
                different.append("\(side) \(point)")
            }
        }
        #expect(different.isEmpty, "\(different.prefix(5))")
    }

    @Test func anyNominalPoint_drawnThenTapped_comesBackWithItsHit() {
        // A dart reported by the camera at `p`, drawn, then tapped where it is drawn: same hit, same position,
        // in both geometries, at random sizes. Points within 1e-6 mm of a wire are left out.
        var random = SeededRandom(seed: 2026)
        for (name, geometry) in geometries {
            for _ in 0..<6_000 {
                let side = CGFloat(uniform(&random, 36...1_500))
                let p = BoardPoint(x: uniform(&random, -230...230), y: uniform(&random, -230...230))
                let r = p.radius
                let nearRing = ringWires(.standard).contains { abs($0 - r) < 1e-6 }
                let a = (p.clockwiseDegrees + 9).truncatingRemainder(dividingBy: 18)
                let nearRadial = r > BoardGeometry.standard.outerBullRadius - 1e-6 && (a < 1e-6 || a > 18 - 1e-6)
                if nearRing || nearRadial { continue }
                let location = DartboardView.location(of: p, in: square(side), geometry: geometry)
                let tap = DartboardView.tap(at: location, in: square(side), geometry: geometry)
                #expect(tap.hit == BoardGeometry.standard.hit(at: p), "\(name), side \(side), \(p)")
                #expect(abs(tap.position.x - p.x) < 1e-6 && abs(tap.position.y - p.y) < 1e-6, "\(name), side \(side), \(p)")
            }
        }
    }

    @Test func discLength_andLocation_areTheFormulaOfTheDocument() {
        // length = mm × k ; location = (w/2 + q.x k, h/2 − q.y k) with q = standard.remap(p, to: geometry).
        var random = SeededRandom(seed: 9)
        for (name, geometry) in geometries {
            for _ in 0..<1_000 {
                let side = CGFloat(uniform(&random, 1...1_000))
                let k = Double(side) / 2 / 225.5
                let mm = uniform(&random, 0...300)
                #expect(abs(Double(DartboardView.length(of: mm, in: square(side))) - mm * k) < 1e-9)
                let p = BoardPoint(x: uniform(&random, -250...250), y: uniform(&random, -250...250))
                let q = BoardGeometry.standard.remap(p, to: geometry)
                let location = DartboardView.location(of: p, in: square(side), geometry: geometry)
                #expect(abs(Double(location.x) - (Double(side) / 2 + q.x * k)) < 1e-9, "\(name)")
                #expect(abs(Double(location.y) - (Double(side) / 2 - q.y * k)) < 1e-9, "\(name)")
            }
        }
    }

    // MARK: The picture against the taps, in frames of every aspect ratio

    /// Colour of an unhighlighted bed (the 20 is black with red rings, then every other sector).
    private func bedColor(of hit: Hit, geometry: BoardGeometry) -> RGB? {
        let darkNumbers = Set(stride(from: 0, to: 20, by: 2).map { geometry.sectorOrder[$0] })
        switch hit.bed {
        case .miss: return nil
        case .innerBull: return KernelPalette.boardRed
        case .outerBull: return KernelPalette.boardGreen
        case .single: return darkNumbers.contains(hit.number ?? 0) ? KernelPalette.boardBlack : KernelPalette.boardCream
        case .treble, .double: return darkNumbers.contains(hit.number ?? 0) ? KernelPalette.boardRed : KernelPalette.boardGreen
        }
    }

    /// Distance in points from a drawn point to the nearest wire of the drawing (ring or radial), on the scoring area.
    private func distanceToNearestWire(_ drawn: BoardPoint, geometry: BoardGeometry, k: Double) -> Double {
        let r = drawn.radius
        var best = ringWires(geometry).map { abs($0 - r) }.min() ?? .infinity
        if r > geometry.outerBullRadius {
            let a = (drawn.clockwiseDegrees + 9).truncatingRemainder(dividingBy: 18)
            let angular = min(a, 18 - a) * .pi / 180
            best = min(best, r * sin(angular))
        }
        return best * k
    }

    @Test func picture_agreesWithTheTap_inFramesOfEveryAspectRatio() throws {
        var random = SeededRandom(seed: 314)
        let frames = [CGSize(width: 97, height: 151), CGSize(width: 401, height: 263), CGSize(width: 300, height: 300),
                      CGSize(width: 180, height: 640), CGSize(width: 523.5, height: 517.25)]
        for (name, geometry) in geometries {
            for frame in frames {
                let bitmap = try KernelBitmap(DartboardView(geometry: geometry, showsNumbers: false)
                                                .environment(\.horizontalSizeClass, .compact), size: frame)
                let side = min(frame.width, frame.height)
                let origin = CGPoint(x: (frame.width - side) / 2, y: (frame.height - side) / 2)
                let k = Double(side) / 2 / 225.5
                var checked = 0
                for _ in 0..<600 {
                    let local = CGPoint(x: uniform(&random, 0...Double(side)), y: uniform(&random, 0...Double(side)))
                    let tap = DartboardView.tap(at: local, in: square(side), geometry: geometry)
                    guard let expected = bedColor(of: tap.hit, geometry: geometry) else { continue }
                    let drawn = BoardPoint(x: (Double(local.x) - Double(side) / 2) / k, y: (Double(side) / 2 - Double(local.y)) / k)
                    // Two pixels away from any wire: anti-aliasing cannot blur the answer.
                    guard distanceToNearestWire(drawn, geometry: geometry, k: k) > 2 else { continue }
                    let pixel = CGPoint(x: origin.x + local.x, y: origin.y + local.y)
                    #expect(bitmap.has(expected, at: pixel), "\(name), frame \(frame), \(tap.hit) at \(local): \(bitmap.color(at: pixel))")
                    checked += 1
                }
                // The smallest frame (97 pt wide) leaves few points two pixels away from every wire.
                #expect(checked > 40, "\(name), frame \(frame): only \(checked) points checked")
            }
        }
    }

    // MARK: Pure helpers against oracles

    @Test func runs_partitionTheRingIntoMaximalGroups() {
        var random = SeededRandom(seed: 11)
        for _ in 0..<3_000 {
            let n = 1 + random.nextInt(below: 24)
            let values: [Int?] = (0..<n).map { _ in
                let v = random.nextInt(below: 4)
                return v == 0 ? nil : v
            }
            let runs = BoardDrawing.runs(of: values)
            var covered = [Int](repeating: 0, count: n)
            for run in runs {
                #expect(run.count >= 1 && run.count <= n)
                for offset in 0..<run.count {
                    let index = (run.start + offset) % n
                    covered[index] += 1
                    #expect(values[index] == run.value, "\(values)")
                }
                // Maximal: the neighbours outside the run carry another value (unless the run is the whole ring).
                if run.count < n {
                    #expect(values[(run.start + n - 1) % n] != run.value, "\(values) \(runs.map { ($0.start, $0.count) })")
                    #expect(values[(run.start + run.count) % n] != run.value, "\(values) \(runs.map { ($0.start, $0.count) })")
                }
            }
            for index in 0..<n {
                #expect(covered[index] == (values[index] == nil ? 0 : 1), "\(values) \(runs.map { ($0.start, $0.count) })")
            }
        }
    }

    @Test func bedStyles_theNarrowestZoneWins_thenTheLaterOne() {
        func breadth(_ zone: BoardZone) -> Int {
            switch zone {
            case .sector, .bull: return 0
            case .single: return 1
            default: return 2
            }
        }
        var random = SeededRandom(seed: 12)
        let roles: [HighlightRole] = [.target, .secondary, .own, .avoid, .opponent, .inactive]
        for _ in 0..<1_000 {
            let count = 1 + random.nextInt(below: 6)
            let highlights: [BoardHighlight] = (0..<count).map { _ in
                let number = 1 + random.nextInt(below: 20)
                let zones: [BoardZone] = [.sector(number), .single(number), .double(number), .treble(number), .bull, .outerBull, .innerBull]
                return BoardHighlight(zone: zones[random.nextInt(below: zones.count)], role: roles[random.nextInt(below: roles.count)],
                                      owner: random.nextInt(below: 3) == 0 ? nil : random.nextInt(below: 4))
            }
            let styles = BoardDrawing.bedStyles(for: highlights, in: .display)
            for bed in BoardBed.all {
                let holders = highlights.enumerated().filter { BoardBed.beds(of: $0.element.zone, in: .display).contains(bed) }
                let winner = holders.max { a, b in
                    let (x, y) = (breadth(a.element.zone), breadth(b.element.zone))
                    return x != y ? x < y : a.offset < b.offset
                }
                #expect(styles[bed]?.role == winner?.element.role, "\(bed) \(highlights)")
                #expect(styles[bed]?.owner == winner?.element.owner, "\(bed) \(highlights)")
            }
        }
    }
}
