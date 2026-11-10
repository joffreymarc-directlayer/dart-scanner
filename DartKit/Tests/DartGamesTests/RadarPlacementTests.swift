import Testing
import DartCore
import DartGames

/// `place(radius, obstacles)` of GAMES.md §15.3, called directly: the candidate list, its order, the fallback,
/// and the single draw.
@Suite struct RadarPlacementTests {
    private typealias Disc = RadarPlacement.Disc
    private typealias Point = RadarPlacement.Point

    /// The definition of §15.3, step 1, written the slow and obvious way.
    private func reference(radius: Int, obstacles: [Disc]) -> [Point] {
        var points: [Point] = []
        for y in stride(from: -170, through: 170, by: 5) {
            for x in stride(from: -170, through: 170, by: 5) {
                let inside = x * x + y * y <= (170 - radius) * (170 - radius)
                let clear = obstacles.allSatisfy { obstacle in
                    let dx = x - obstacle.x, dy = y - obstacle.y
                    let clearance = radius + obstacle.radius + 6
                    return dx * dx + dy * dy >= clearance * clearance
                }
                if inside && clear { points.append(Point(x: x, y: y)) }
            }
        }
        return points
    }

    /// RAD-6, the two `place` cases.
    @Test func rad6_placeWithoutObstacleAndFallback() {
        let free = RadarPlacement.candidates(radius: 40, obstacles: [])
        #expect(free.count == 2121 && free.first == Point(x: 0, y: -130) && free.last == Point(x: 0, y: 130))

        // No lattice point is 176 mm away from the centre and inside the radius 130: fallback without the
        // second condition, overlap accepted.
        let blocked = [Disc(x: 0, y: 0, radius: 130)]
        #expect(reference(radius: 40, obstacles: blocked).isEmpty)
        let fallback = RadarPlacement.candidates(radius: 40, obstacles: blocked)
        #expect(fallback.count == 2121 && fallback.first == Point(x: 0, y: -130) && fallback.last == Point(x: 0, y: 130))
        #expect(fallback == free)

        // `place` draws exactly once in both cases: seed 1, nextInt(below: 2121) = 1934 (GAMES.md §2.8).
        for obstacles in [[], blocked] {
            var random = SeededRandom(seed: 1)
            var expected = random
            let index = expected.nextInt(below: 2121)
            #expect(index == 1934)
            #expect(RadarPlacement.place(radius: 40, obstacles: obstacles, random: &random) == free[1934])
            #expect(random == expected)
        }
        #expect(free[1934] == Point(x: -80, y: 95))
    }

    /// Row by row, y from −170 up to 170, and x from −170 up to 170 inside a row.
    @Test func radarPlacement_candidatesAreInLatticeOrder() {
        for radius in [40, 28, 16] {
            let list = RadarPlacement.candidates(radius: radius, obstacles: [Disc(x: 70, y: -65, radius: 40)])
            #expect(list == reference(radius: radius, obstacles: [Disc(x: 70, y: -65, radius: 40)]))
            #expect(zip(list, list.dropFirst()).allSatisfy { $0.y < $1.y || ($0.y == $1.y && $0.x < $1.x) })
            #expect(list.allSatisfy { $0.x % 5 == 0 && $0.y % 5 == 0 })
        }
        // Sizes of the free lattice for the three radii.
        #expect([40, 28, 16].map { RadarPlacement.candidates(radius: $0, obstacles: []).count } == [2121, 2537, 2965])
    }

    /// The two conditions are inclusive: the disc may touch the edge of the scoring area, and two discs may be
    /// exactly 6 mm apart.
    @Test func radarPlacement_boundariesAreInclusive() {
        // 170 − 40 = 130: (130, 0) is a candidate, (135, 0) is not; (50, 120) is on the circle (2500 + 14400 = 130²).
        let free = RadarPlacement.candidates(radius: 40, obstacles: [])
        #expect(free.contains(Point(x: 130, y: 0)) && !free.contains(Point(x: 135, y: 0)))
        #expect(free.contains(Point(x: 50, y: 120)) && !free.contains(Point(x: 55, y: 120)))
        #expect(free.contains(Point(x: 0, y: 0)))

        // An obstacle of radius 19 at the centre: clearance 40 + 19 + 6 = 65. (65, 0) and (25, 60) are exactly
        // 65 mm away and stay; (60, 0) and (25, 55) go.
        let list = RadarPlacement.candidates(radius: 40, obstacles: [Disc(x: 0, y: 0, radius: 19)])
        #expect(list.contains(Point(x: 65, y: 0)) && list.contains(Point(x: 25, y: 60)))
        #expect(list.contains(Point(x: 0, y: 65)) && list.contains(Point(x: 0, y: -65)) && list.contains(Point(x: -65, y: 0)))
        #expect(!list.contains(Point(x: 0, y: 60)) && !list.contains(Point(x: 0, y: -60)) && !list.contains(Point(x: -60, y: 0)))
        #expect(!list.contains(Point(x: 60, y: 0)) && !list.contains(Point(x: 25, y: 55)) && !list.contains(Point(x: 0, y: 0)))
        // One millimetre more of obstacle and the points at 65 mm go too.
        let wider = RadarPlacement.candidates(radius: 40, obstacles: [Disc(x: 0, y: 0, radius: 20)])
        #expect(!wider.contains(Point(x: 65, y: 0)) && !wider.contains(Point(x: 25, y: 60)) && wider.contains(Point(x: 70, y: 0)))
    }

    /// Against the slow definition, for obstacle sets as the game builds them.
    @Test func radarPlacement_matchesTheDefinitionOnRandomBoards() {
        var random = SeededRandom(seed: 15)
        for _ in 0..<60 {
            var discs: [Disc] = []
            for radius in [40, 40, 28, 28, 16] {
                let list = RadarPlacement.candidates(radius: radius, obstacles: discs)
                #expect(list == reference(radius: radius, obstacles: discs))
                let centre = list[random.nextInt(below: list.count)]
                discs.append(Disc(x: centre.x, y: centre.y, radius: radius))
            }
            // A move or a replacement: the five discs are obstacles, the moving one included.
            for slot in 0..<5 {
                let list = RadarPlacement.candidates(radius: discs[slot].radius, obstacles: discs)
                let free = reference(radius: discs[slot].radius, obstacles: discs)
                // The fallback is not needed on such boards: the list is the free list, and it never
                // offers the place the disc is leaving.
                #expect(!free.isEmpty && list == free)
                #expect(!list.contains(Point(x: discs[slot].x, y: discs[slot].y)))
                let centre = list[random.nextInt(below: list.count)]
                discs[slot].x = centre.x
                discs[slot].y = centre.y
            }
        }
    }

    /// Against the slow definition again, for discs the game never builds: any radius (beyond the board too),
    /// obstacles off the lattice, outside the board, of any size, in any number.
    @Test func radarPlacement_matchesTheDefinitionForArbitraryDiscs() {
        var random = SeededRandom(seed: 4)
        var fallbacks = 0
        for round in 0..<500 {
            let radius = round < 20 ? 160 + round : random.nextInt(below: 120)
            var obstacles: [Disc] = []
            for _ in 0..<random.nextInt(below: 8) {
                obstacles.append(Disc(x: random.nextInt(below: 421) - 210, y: random.nextInt(below: 421) - 210,
                                      radius: random.nextInt(below: 90)))
            }
            let free = reference(radius: radius, obstacles: obstacles)
            if free.isEmpty { fallbacks += 1 }
            let expected = free.isEmpty ? reference(radius: radius, obstacles: []) : free
            #expect(RadarPlacement.candidates(radius: radius, obstacles: obstacles) == expected,
                    "radius \(radius), obstacles \(obstacles)")
            #expect(!expected.isEmpty)
        }
        // Both branches were met.
        #expect(fallbacks > 10 && fallbacks < 490)
    }

    /// `place` picks `candidates[nextInt(below: count)]` and nothing else.
    @Test func radarPlacement_placeIsOneDrawInTheCandidateList() {
        for seed in 0..<50 as Range<UInt64> {
            let obstacles = [Disc(x: -80, y: 95, radius: 40), Disc(x: 70, y: -65, radius: 40)]
            let list = RadarPlacement.candidates(radius: 28, obstacles: obstacles)
            var random = SeededRandom(seed: seed)
            var expected = SeededRandom(seed: seed)
            let centre = RadarPlacement.place(radius: 28, obstacles: obstacles, random: &random)
            #expect(centre == list[expected.nextInt(below: list.count)])
            #expect(random == expected)
        }
    }
}
