import Testing
import DartCore
import DartGames
import DartTestSupport

/// Radar (GAMES.md §15), the only position-dependent game: the vectors RAD-1 to RAD-7, then the rule paragraphs
/// they do not reach. The placement function itself is tested in `RadarPlacementTests`.
@Suite struct RadarTests {
    private let registry = GameRegistry.standard

    /// The five targets, one row `[x, y, radius, hitPoints]` each.
    private func blobs(_ match: GameMatch) -> [[Int]] {
        guard case .table(let rows)? = match.gameFact("blobs") else {
            Issue.record("the game fact `blobs` is a table")
            return []
        }
        return rows
    }

    private func discs(_ rows: [[Int]]) -> [RadarPlacement.Disc] {
        rows.map { RadarPlacement.Disc(x: $0[0], y: $0[1], radius: $0[2]) }
    }

    /// An integer fact of every player, in playing order.
    private func ints(_ match: GameMatch, _ name: String) -> [Int] {
        match.players.indices.map { player in
            guard case .int(let value)? = match.fact(player, name) else {
                Issue.record("the fact `\(name)` is an integer")
                return .min
            }
            return value
        }
    }

    private func points(_ match: GameMatch) -> [Int] { ints(match, "points") }
    private func destroyed(_ match: GameMatch) -> [Int] { ints(match, "destroyed") }

    /// A dart with a recorded position, in millimetres.
    private func dart(_ hit: Hit, _ x: Double, _ y: Double) -> DartRecord {
        DartRecord(hit: hit, position: BoardPoint(x: x, y: y))
    }

    /// One placement, as GAMES.md prints it: "540 candidats, index 428 → (-110, 0)".
    private struct Draw {
        var radius: Int
        var candidates: Int
        var index: Int
        var x: Int
        var y: Int
    }

    /// Replays `draws` with a generator held by the test: each one sees `obstacles(slot)`, must offer the documented
    /// number of candidates, draw the documented index and land on the documented centre. Consumes exactly one
    /// draw per placement, which is how a test counts the draws of the engine.
    private func check(_ draws: [Draw], random: inout SeededRandom, obstacles: (Int) -> [RadarPlacement.Disc],
                       placed: (Int, RadarPlacement.Point) -> Void) {
        for (slot, draw) in draws.enumerated() {
            let candidates = RadarPlacement.candidates(radius: draw.radius, obstacles: obstacles(slot))
            #expect(candidates.count == draw.candidates, "slot \(slot)")
            var probe = random
            #expect(probe.nextInt(below: max(candidates.count, 1)) == draw.index, "slot \(slot)")
            let centre = RadarPlacement.place(radius: draw.radius, obstacles: obstacles(slot), random: &random)
            #expect(centre == RadarPlacement.Point(x: draw.x, y: draw.y), "slot \(slot)")
            placed(slot, centre)
        }
    }

    private static let seedOneBlobs = [[-80, 95, 40, 3], [70, -65, 40, 3], [110, 65, 28, 2], [25, 15, 28, 2], [140, 0, 16, 1]]

    // MARK: Vectors (GAMES.md §15.9)

    @Test func rad1_initialPlacementTiedToTheSeed() throws {
        let match = try registry.match(.radar, players: 2, seed: 1)
        #expect(blobs(match) == Self.seedOneBlobs)
        #expect(match.gameFact("blobs") == .table(Self.seedOneBlobs))

        // Five draws, one per slot, each against the targets already placed.
        var random = SeededRandom(seed: 1)
        var placed: [RadarPlacement.Disc] = []
        let draws = [Draw(radius: 40, candidates: 2121, index: 1934, x: -80, y: 95),
                     Draw(radius: 40, candidates: 1682, index: 427, x: 70, y: -65),
                     Draw(radius: 28, candidates: 1559, index: 1258, x: 110, y: 65),
                     Draw(radius: 28, candidates: 1267, index: 854, x: 25, y: 15),
                     Draw(radius: 16, candidates: 1598, index: 955, x: 140, y: 0)]
        check(draws, random: &random, obstacles: { _ in placed }) { slot, centre in
            placed.append(RadarPlacement.Disc(x: centre.x, y: centre.y, radius: draws[slot].radius))
        }
        #expect(placed == discs(Self.seedOneBlobs))

        // Five disc highlights of role target, the same for every player.
        let highlights = match.snapshot.highlights
        #expect(highlights.map(\.zone) == [.disc(x: -80, y: 95, radius: 40), .disc(x: 70, y: -65, radius: 40),
                                           .disc(x: 110, y: 65, radius: 28), .disc(x: 25, y: 15, radius: 28),
                                           .disc(x: 140, y: 0, radius: 16)])
        #expect(highlights.allSatisfy { $0.role == .target && $0.owner == nil && $0.marker == nil })
        #expect(highlights.map(\.label) == ["+10", "+10", "+20", "+20", "+50"])
        #expect(highlights.map(\.strength) == [3, 3, 2, 2, 1])

        #expect(try blobs(registry.match(.radar, players: 1, seed: 0))
                == [[45, 85, 40, 3], [-15, -120, 40, 3], [85, -15, 28, 2], [0, 10, 28, 2], [-85, -120, 16, 1]])
        #expect(try blobs(registry.match(.radar, players: 8, seed: 42))
                == [[-60, -100, 40, 3], [-30, 85, 40, 3], [0, -55, 28, 2], [120, -10, 28, 2], [-110, 85, 16, 1]])
    }

    @Test func rad2_dartsWithoutPositionCanonicalPositionDestructionReplacement() throws {
        var match = try registry.match(.radar, players: 2, seed: 1)
        var random = SeededRandom(seed: 1)
        for _ in 0..<5 { _ = random.next() }

        // S9 (-1088, 791) and T12 (-605, 833) are inside target 0; S20 (0, 1345) is inside none.
        var outcomes = match.play("S9, T12, S20")
        #expect(blobs(match)[0] == [-80, 95, 40, 1] && points(match) == [20, 0])
        #expect(outcomes[0].events == [.dartRegistered(player: 0, hit: .single(9)),
                                       .blobDamaged(player: 0, blob: 0, points: 10, hitPointsLeft: 2)])
        #expect(outcomes[1].events == [.dartRegistered(player: 0, hit: .treble(12)),
                                       .blobDamaged(player: 0, blob: 0, points: 10, hitPointsLeft: 1)])
        #expect(outcomes[2].events == [.dartRegistered(player: 0, hit: .single(20)), .noEffect(player: 0),
                                       .turnScored(player: 0, points: 20), .turnCompleted(player: 0)])

        // SB touches target 3 and T4 target 2.
        outcomes = match.play("| SB, T4, MISS")
        #expect(blobs(match)[3] == [25, 15, 28, 1] && blobs(match)[2] == [110, 65, 28, 1] && points(match) == [20, 40])
        #expect(outcomes[1].events == [.dartRegistered(player: 1, hit: .outerBull),
                                       .blobDamaged(player: 1, blob: 3, points: 20, hitPointsLeft: 1)])
        #expect(outcomes[2].events == [.dartRegistered(player: 1, hit: .treble(4)),
                                       .blobDamaged(player: 1, blob: 2, points: 20, hitPointsLeft: 1)])
        #expect(outcomes[3].events == [.dartRegistered(player: 1, hit: .miss), .noEffect(player: 1),
                                       .turnScored(player: 1, points: 40), .turnCompleted(player: 1)])

        // Target 0 destroyed; its replacement is the 6th draw of the game.
        var before = discs(blobs(match))
        outcomes = match.play("| S9")
        #expect(match.fact(0, "points") == 50 && match.fact(0, "destroyed") == 1)
        #expect(outcomes[1].events == [.dartRegistered(player: 0, hit: .single(9)),
                                       .blobDestroyed(player: 0, blob: 0, points: 30)])
        check([Draw(radius: 40, candidates: 540, index: 428, x: -110, y: 0)], random: &random, obstacles: { _ in before }) { _, _ in }
        #expect(blobs(match)[0] == [-110, 0, 40, 3])

        // Target 4 destroyed with a single hit.
        before = discs(blobs(match))
        outcomes = match.play("S6")
        #expect(match.fact(0, "points") == 200 && match.fact(0, "destroyed") == 2)
        #expect(outcomes[0].events == [.dartRegistered(player: 0, hit: .single(6)),
                                       .blobDestroyed(player: 0, blob: 4, points: 150)])
        check([Draw(radius: 16, candidates: 1433, index: 804, x: 0, y: 60)], random: &random, obstacles: { _ in before }) { _, _ in }
        #expect(blobs(match)[4] == [0, 60, 16, 1])

        // No effect: target 0 has moved. 180 points in the turn, but never a oneEighty.
        outcomes = match.play("S9")
        #expect(match.phase == .turnComplete && points(match) == [200, 40])
        #expect(outcomes[0].events == [.dartRegistered(player: 0, hit: .single(9)), .noEffect(player: 0),
                                       .turnScored(player: 0, points: 180), .turnCompleted(player: 0)])
        #expect(blobs(match) == [[-110, 0, 40, 3], [70, -65, 40, 3], [110, 65, 28, 1], [25, 15, 28, 1], [0, 60, 16, 1]])
    }

    // The name and the first assertions are those of the listing of ARCHITECTURE.md §5.7.
    @Test func rad3_sameHitDifferentEffects() throws {
        var match = try registry.match(.radar, players: 1, seed: 1)
        var outcomes = match.play("S6@(123.9, 0.0), S6@(124.0, 0.0), S6")
        // 1st: 0.1 mm outside target 4 (140, 0, 16, 1).
        #expect(outcomes[0].events == [.dartRegistered(player: 0, hit: .single(6)), .noEffect(player: 0)])
        // 2nd: exactly on the edge, which counts.
        #expect(outcomes[1].events == [.dartRegistered(player: 0, hit: .single(6)),
                                       .blobDestroyed(player: 0, blob: 4, points: 150)])
        // 3rd: without a position S6 is (1345, 0), and target 4 is now at (60, 105).
        #expect(outcomes[2].events == [.dartRegistered(player: 0, hit: .single(6)), .noEffect(player: 0),
                                       .turnScored(player: 0, points: 150), .turnCompleted(player: 0)])
        #expect(match.fact(0, "points") == 150 && match.fact(0, "destroyed") == 1 && match.phase == .turnComplete)
        #expect(match.gameFact("blobs") == .table([
            [-80, 95, 40, 3], [70, -65, 40, 3], [110, 65, 28, 2], [25, 15, 28, 2], [60, 105, 16, 1]]))

        outcomes = match.play("| MISS@(25.0, 15.0), T20@(25.0, 15.0)")
        // MISS touches nothing, even with a position at the centre of target 3 (25, 15, 28, 2).
        #expect(outcomes[1].events == [.dartRegistered(player: 0, hit: .miss), .noEffect(player: 0)])
        // T20 with the same position: the position is taken as it is.
        #expect(outcomes[2].events == [.dartRegistered(player: 0, hit: .treble(20)),
                                       .blobDamaged(player: 0, blob: 3, points: 20, hitPointsLeft: 1)])
        #expect(match.fact(0, "points") == 170)

        // Rounding to the tenth: y = 43.06 becomes 431 tenths, outside; y = 43.04 becomes 430, on the edge.
        outcomes = match.play("| S18@(25.0, 43.06), S18@(25.0, 43.04)")
        #expect(outcomes[1].events == [.dartRegistered(player: 0, hit: .single(18)), .noEffect(player: 0)])
        #expect(outcomes[2].events == [.dartRegistered(player: 0, hit: .single(18)),
                                       .blobDestroyed(player: 0, blob: 3, points: 60)])
        #expect(match.fact(0, "points") == 230 && match.fact(0, "destroyed") == 2)

        // A hit picked in a list erases the position: the bed has not changed, the effect has.
        match = try registry.match(.radar, players: 1, seed: 1)
        outcomes = match.play("S6@(123.9, 0.0)")
        #expect(outcomes[0].events.contains(.noEffect(player: 0)) && match.fact(0, "points") == 0)
        #expect(match.replaceDart(at: 0, with: .single(6)).applied)
        #expect(match.currentTurn.map(\.position) == [nil])
        #expect(match.fact(0, "points") == 150 && blobs(match)[4] == [60, 105, 16, 1])

        // Halves round away from zero: x = −1200.5 tenths becomes −1201, 0.1 mm outside target 0 (-80, 95, 40, 3).
        match = try registry.match(.radar, players: 1, seed: 1)
        outcomes = match.play("S12@(-120.05, 95.0), S12@(-120.04, 95.0)")
        #expect(outcomes[0].events == [.dartRegistered(player: 0, hit: .single(12)), .noEffect(player: 0)])
        // x = −1200.4 tenths becomes −1200, on the edge.
        #expect(outcomes[1].events == [.dartRegistered(player: 0, hit: .single(12)),
                                       .blobDamaged(player: 0, blob: 0, points: 10, hitPointsLeft: 2)])
        #expect(match.fact(0, "points") == 10)
    }

    @Test func rad4_movingTargetsDeterministic() throws {
        var match = try registry.match(.radar, ["movingTargets": true], players: 2, seed: 7)
        let initial = [[-120, 50, 40, 3], [80, -50, 40, 3], [-50, 0, 28, 2], [-5, 95, 28, 2], [75, 130, 16, 1]]
        // Nothing moves at creation: the same targets as without the option.
        #expect(blobs(match) == initial)
        #expect(try blobs(registry.match(.radar, players: 2, seed: 7)) == initial)

        var steps = [match.snapshot]
        var outcomes = match.play("S9, MISS, MISS")
        #expect(outcomes[0].events == [.dartRegistered(player: 0, hit: .single(9)),
                                       .blobDamaged(player: 0, blob: 0, points: 10, hitPointsLeft: 2)])
        outcomes += match.play("|")
        #expect(outcomes[3].events == [.blobsMoved, .turnStarted(player: 1, round: 1)])
        // The five targets move at the start of J2's turn and keep their hit points: 10 draws since the start.
        let afterFirstMove = [[-10, -75, 40, 2], [-110, 65, 40, 3], [115, 0, 28, 2], [-105, -20, 28, 2], [45, -45, 16, 1]]
        #expect(blobs(match) == afterFirstMove)

        var random = SeededRandom(seed: 7)
        for _ in 0..<5 { _ = random.next() }
        var current = discs(initial)
        check([Draw(radius: 40, candidates: 348, index: 201, x: -10, y: -75),
               Draw(radius: 40, candidates: 207, index: 160, x: -110, y: 65),
               Draw(radius: 28, candidates: 857, index: 510, x: 115, y: 0),
               Draw(radius: 28, candidates: 678, index: 317, x: -105, y: -20),
               Draw(radius: 16, candidates: 1496, index: 481, x: 45, y: -45)],
              random: &random, obstacles: { _ in current }) { slot, centre in
            current[slot].x = centre.x
            current[slot].y = centre.y
        }

        steps.append(match.snapshot)
        outcomes = match.play("MISS ×3 |")
        #expect(outcomes[3].events == [.roundStarted(round: 2), .blobsMoved, .turnStarted(player: 0, round: 2)])
        let afterSecondMove = [[-25, 115, 40, 2], [-65, -110, 40, 3], [35, 60, 28, 2], [110, 45, 28, 2], [95, -110, 16, 1]]
        #expect(blobs(match) == afterSecondMove && match.snapshot.round == 2)
        // 15 draws: the next five of the test generator give the same places.
        for slot in 0..<5 {
            let centre = RadarPlacement.place(radius: current[slot].radius, obstacles: current, random: &random)
            current[slot].x = centre.x
            current[slot].y = centre.y
        }
        #expect(current == discs(afterSecondMove))
        steps.append(match.snapshot)

        // Undo then endTurn: the same targets.
        #expect(match.undo().applied)
        #expect(blobs(match) == afterFirstMove && match.phase == .turnComplete)
        #expect(match.endTurn().events == [.roundStarted(round: 2), .blobsMoved, .turnStarted(player: 0, round: 2)])
        #expect(match.snapshot == steps[2])

        // Replaying the whole journal gives the same targets at every step.
        var replayed = try registry.match(.radar, ["movingTargets": true], players: 2, seed: 7)
        #expect(replayed.snapshot == steps[0])
        replayed.play("S9, MISS, MISS |")
        #expect(replayed.snapshot == steps[1])
        replayed.play("MISS ×3 |")
        #expect(replayed.snapshot == steps[2])
        #expect(try registry.restoreMatch(match.record).snapshot == steps[2])
    }

    @Test func rad5_endOfGameDestroyedTargetsBreakTheTie() throws {
        var match = try registry.match(.radar, ["rounds": 2], players: 2, seed: 1)
        match.play("S4@(110.0, 65.0), S4@(110.0, 65.0), MISS")
        // J1 destroys target 2: 20 + 60. The new target 2 is at (-70, -90).
        #expect(points(match) == [80, 0] && blobs(match)[2] == [-70, -90, 28, 2])
        match.play("| S12@(-80.0, 95.0), S12@(-80.0, 95.0), S15@(70.0, -65.0) | MISS ×3")
        // J2 touches targets 0, 0, 1, then 1, 3 and the new target 2.
        match.play("| S15@(70.0, -65.0), S4@(25.0, 15.0), S7@(-70.0, -90.0)")
        #expect(points(match) == [80, 80] && destroyed(match) == [1, 0] && match.phase == .turnComplete)
        #expect(blobs(match).map { $0[3] } == [1, 1, 1, 1, 1])
        #expect(match.snapshot.ranks == [1, 2])
        #expect(match.endTurn().events == [.gameFinished(reason: .roundLimit)])
        #expect(match.phase == .finished && match.snapshot.finishReason == .roundLimit && match.snapshot.ranks == [1, 2])
    }

    @Test func rad6_propertiesAndRefusals() throws {
        // Seeds 0 to 199: centres on the 5 mm lattice, discs inside the radius 170, at least 6 mm apart.
        for seed in 0..<200 as Range<UInt64> {
            let rows = try blobs(registry.match(.radar, players: 1, seed: seed))
            #expect(rows.map { $0[2] } == [40, 40, 28, 28, 16] && rows.map { $0[3] } == [3, 3, 2, 2, 1], "seed \(seed)")
            expectWellPlaced(rows, "seed \(seed)")
        }
        #expect(throws: GameConfigurationError.playerCountOutOfRange(allowed: 1...8, actual: 9)) {
            try registry.match(.radar, players: 9)
        }
        #expect(throws: GameConfigurationError.invalidOptionValue(key: "rounds")) {
            try registry.match(.radar, ["rounds": 21], players: 1)
        }
        #expect(throws: GameConfigurationError.invalidOptionValue(key: "rounds")) {
            try registry.match(.radar, ["rounds": 0], players: 1)
        }
        #expect(throws: GameConfigurationError.invalidOptionValue(key: "movingTargets")) {
            try registry.match(.radar, ["movingTargets": 1], players: 1)
        }
        // The two `place` cases of RAD-6 are in RadarPlacementTests.rad6_placeWithoutObstacleAndFallback.
    }

    @Test func rad7_correctingAnEarlierDartReplaysTheFollowingOnes() throws {
        var match = try registry.match(.radar, players: 1, seed: 1)
        let outcomes = match.play("S6@(124.0, 0.0), S6")
        // 1st: target 4 destroyed, replaced at (60, 105); 2nd, without a position: S6 is (1345, 0), no effect.
        #expect(outcomes[0].events.contains(.blobDestroyed(player: 0, blob: 4, points: 150)))
        #expect(outcomes[1].events == [.dartRegistered(player: 0, hit: .single(6)), .noEffect(player: 0)])
        #expect(match.fact(0, "points") == 150 && blobs(match)[4] == [60, 105, 16, 1])

        let edit = match.replaceDart(at: 0, with: .miss)
        #expect(edit.applied && edit.dropped.isEmpty && match.turnNotation == ["MISS", "S6"])
        // The 1st dart touches nothing any more, target 4 stayed at (140, 0), and the 2nd, unchanged, destroys it.
        #expect(match.fact(0, "points") == 150 && match.fact(0, "destroyed") == 1)
        #expect(blobs(match)[4] == [60, 105, 16, 1] && match.phase == .throwing)

        // The same journal played forward: same state, and the events the replay produced.
        var forward = try registry.match(.radar, players: 1, seed: 1)
        let replayed = forward.play("MISS, S6")
        #expect(replayed[0].events == [.dartRegistered(player: 0, hit: .miss), .noEffect(player: 0)])
        #expect(replayed[1].events == [.dartRegistered(player: 0, hit: .single(6)),
                                       .blobDestroyed(player: 0, blob: 4, points: 150)])
        #expect(forward.snapshot == match.snapshot)

        // 6 draws: five placements and one replacement, against the five targets where they were.
        var random = SeededRandom(seed: 1)
        for _ in 0..<5 { _ = random.next() }
        let centre = RadarPlacement.place(radius: 16, obstacles: discs(Self.seedOneBlobs), random: &random)
        #expect(centre == RadarPlacement.Point(x: 60, y: 105))
    }

    // MARK: Darts without a position (GAMES.md §2.13)

    /// The table of GAMES.md §2.13, in tenths of a millimetre, one entry per sector clockwise from the 20.
    private static let ring = [20, 1, 18, 4, 13, 6, 10, 15, 2, 17, 3, 19, 7, 16, 8, 11, 14, 9, 12, 5]
    private static let canonicalSingles = [
        (0, 1345), (416, 1279), (791, 1088), (1088, 791), (1279, 416), (1345, 0), (1279, -416), (1088, -791), (791, -1088),
        (416, -1279), (0, -1345), (-416, -1279), (-791, -1088), (-1088, -791), (-1279, -416), (-1345, 0), (-1279, 416),
        (-1088, 791), (-791, 1088), (-416, 1279)]
    private static let canonicalTrebles = [
        (0, 1030), (318, 980), (605, 833), (833, 605), (980, 318), (1030, 0), (980, -318), (833, -605), (605, -833),
        (318, -980), (0, -1030), (-318, -980), (-605, -833), (-833, -605), (-980, -318), (-1030, 0), (-980, 318),
        (-833, 605), (-605, 833), (-318, 980)]
    private static let canonicalDoubles = [
        (0, 1660), (513, 1579), (976, 1343), (1343, 976), (1579, 513), (1660, 0), (1579, -513), (1343, -976), (976, -1343),
        (513, -1579), (0, -1660), (-513, -1579), (-976, -1343), (-1343, -976), (-1579, -513), (-1660, 0), (-1579, 513),
        (-1343, 976), (-976, 1343), (-513, 1579)]

    /// The 62 beds that have a canonical position, with it.
    private static let canonical: [(hit: Hit, x: Int, y: Int)] = {
        var table: [(hit: Hit, x: Int, y: Int)] = [(.outerBull, 0, 111), (.innerBull, 0, 0)]
        for (index, number) in ring.enumerated() {
            table.append((.single(number), canonicalSingles[index].0, canonicalSingles[index].1))
            table.append((.treble(number), canonicalTrebles[index].0, canonicalTrebles[index].1))
            table.append((.double(number), canonicalDoubles[index].0, canonicalDoubles[index].1))
        }
        return table
    }()

    /// First slot whose disc contains the point given in tenths of a millimetre, edge included (§15.4).
    private func slot(at x: Int, _ y: Int, in rows: [[Int]]) -> Int? {
        rows.firstIndex { row in
            let dx = x - 10 * row[0], dy = y - 10 * row[1]
            return dx * dx + dy * dy <= 100 * row[2] * row[2]
        }
    }

    /// What a dart of `player` must do when its impact point is (`x`, `y`) tenths, given the targets `rows`.
    private func expectedEffect(player: PlayerIndex, x: Int, y: Int, rows: [[Int]]) -> GameEvent {
        guard let slot = slot(at: x, y, in: rows) else { return .noEffect(player: player) }
        let radius = rows[slot][2], hitPoints = rows[slot][3]
        let value = radius == 40 ? 10 : radius == 28 ? 20 : 50
        if hitPoints > 1 { return .blobDamaged(player: player, blob: slot, points: value, hitPointsLeft: hitPoints - 1) }
        return .blobDestroyed(player: player, blob: slot, points: 3 * value)
    }

    @Test func radar_dartWithoutPositionUsesTheCanonicalPositionOfItsBed() throws {
        #expect(Self.canonical.count == 62 && Set(Self.canonical.map(\.hit)).count == 62)
        var touching = 0
        for seed in 0..<40 as Range<UInt64> {
            let match = try registry.match(.radar, players: 1, seed: seed)
            let rows = blobs(match)
            for entry in Self.canonical {
                // The effect is the one of the canonical point of the table, computed here in integers…
                var copy = match
                let events = copy.throwDart(DartRecord(hit: entry.hit)).events
                let expected = expectedEffect(player: 0, x: entry.x, y: entry.y, rows: rows)
                #expect(events == [.dartRegistered(player: 0, hit: entry.hit), expected], "seed \(seed), \(entry.hit)")
                if expected != .noEffect(player: 0) { touching += 1 }
                // …and the same as a dart recorded at that very point, whatever its bed.
                let position = BoardPoint(x: Double(entry.x) / 10, y: Double(entry.y) / 10)
                #expect(match.effectKey(for: entry.hit) == match.effectKey(for: entry.hit, position: position))
                #expect(match.effectKey(for: entry.hit) == match.effectKey(for: .single(1), position: position))
            }
            // MISS has no canonical position: it never touches anything.
            var copy = match
            #expect(copy.throwDart(DartRecord(hit: .miss)).events == [.dartRegistered(player: 0, hit: .miss), .noEffect(player: 0)])
        }
        // The property is not vacuous: many canonical points do lie inside a target.
        #expect(touching > 200)
    }

    /// §15.4: the tip counts, not the bed. At equal position every bed other than MISS has the same effect (§2.13).
    @Test func radar_theTipCountsNotTheBed() throws {
        let match = try registry.match(.radar, players: 1, seed: 1)
        let inside = BoardPoint(x: 140, y: 0)
        let outside = BoardPoint(x: 0, y: -160)
        let keyInside = match.effectKey(for: .single(6), position: inside)
        let keyOutside = match.effectKey(for: .single(3), position: outside)
        #expect(keyInside != keyOutside)
        for hit in Hit.all where !hit.isMiss {
            #expect(match.effectKey(for: hit, position: inside) == keyInside, "\(hit)")
            #expect(match.effectKey(for: hit, position: outside) == keyOutside, "\(hit)")
        }
        #expect(match.effectKey(for: .miss, position: inside) == match.effectKey(for: .miss))
        #expect(match.effectKey(for: .miss, position: inside) != keyInside)
        // A MISS and a dart that touches nothing change the same values, but they are told apart by nothing:
        // both are `noEffect`.
        #expect(match.effectKey(for: .miss) == keyOutside)
    }

    /// §2.13: a non-finite or absurd coordinate is far off the board; it touches nothing and traps nothing.
    @Test func radar_nonFinitePositionsTouchNothing() throws {
        var match = try registry.match(.radar, players: 1, seed: 1)
        let wild: [Double] = [.nan, .infinity, -.infinity, 1e300, -1e300, .greatestFiniteMagnitude, 1e9, -1e9]
        for x in wild {
            for y in wild + [0, 95] {
                let outcome = match.throwDart(dart(.single(20), x, y))
                #expect(outcome.events.contains(.noEffect(player: 0)), "(\(x), \(y))")
                match.undo()
            }
        }
        #expect(match.throwDart(dart(.single(20), -80, .nan)).events.contains(.noEffect(player: 0)))
        #expect(match.fact(0, "points") == 0 && blobs(match) == Self.seedOneBlobs)
    }

    // MARK: Sizes, hit points, replacement (GAMES.md §15.2, §15.4)

    @Test func radar_valuesOfTheThreeSizes() throws {
        var match = try registry.match(.radar, players: 1, seed: 1)
        // Large: 3 hit points, 10 per hit, bonus 20.
        var outcomes = match.play("S12@(-80.0, 95.0), S12@(-80.0, 95.0), S12@(-80.0, 95.0)")
        #expect(outcomes.map { $0.events[1] } == [.blobDamaged(player: 0, blob: 0, points: 10, hitPointsLeft: 2),
                                                  .blobDamaged(player: 0, blob: 0, points: 10, hitPointsLeft: 1),
                                                  .blobDestroyed(player: 0, blob: 0, points: 30)])
        #expect(outcomes[2].events.suffix(2) == [.turnScored(player: 0, points: 50), .turnCompleted(player: 0)])
        // The new target has the same size and all its hit points, and is not where the old one was.
        #expect(blobs(match)[0][2] == 40 && blobs(match)[0][3] == 3 && Array(blobs(match)[0].prefix(2)) != [-80, 95])
        // Medium: 2 hit points, 20 per hit, bonus 40. Small: 1 hit point, 50, bonus 100.
        outcomes = match.play("| S4@(110.0, 65.0), S4@(110.0, 65.0), S6@(140.0, 0.0)")
        #expect(outcomes.dropFirst().map { $0.events[1] } == [.blobDamaged(player: 0, blob: 2, points: 20, hitPointsLeft: 1),
                                                              .blobDestroyed(player: 0, blob: 2, points: 60),
                                                              .blobDestroyed(player: 0, blob: 4, points: 150)])
        #expect(match.fact(0, "points") == 280 && match.fact(0, "destroyed") == 3 && match.fact(0, "dartsThrown") == 6)
        #expect(blobs(match).map { $0[2] } == [40, 40, 28, 28, 16] && blobs(match).map { $0[3] } == [3, 3, 2, 2, 1])
        expectWellPlaced(blobs(match), "after three destructions")
    }

    /// §15.4: one turn may destroy the same slot twice; each replacement is drawn against the five targets,
    /// the destroyed one included, so the new target never appears where the old one was.
    @Test func radar_sameSlotDestroyedTwiceInOneTurn() throws {
        var match = try registry.match(.radar, players: 1, seed: 1)
        var random = SeededRandom(seed: 1)
        for _ in 0..<5 { _ = random.next() }
        var expected = discs(Self.seedOneBlobs)
        for round in 0..<3 {
            let target = blobs(match)[4]
            let outcome = match.throwDart(dart(.single(1), Double(target[0]), Double(target[1])))
            #expect(outcome.events[1] == .blobDestroyed(player: 0, blob: 4, points: 150), "dart \(round)")
            let centre = RadarPlacement.place(radius: 16, obstacles: expected, random: &random)
            // The old disc is an obstacle of its own replacement: the centres are at least 16 + 16 + 6 mm apart.
            let dx = centre.x - expected[4].x, dy = centre.y - expected[4].y
            #expect(dx * dx + dy * dy >= 38 * 38)
            expected[4].x = centre.x
            expected[4].y = centre.y
            #expect(discs(blobs(match)) == expected)
        }
        #expect(match.fact(0, "points") == 450 && match.fact(0, "destroyed") == 3 && match.phase == .turnComplete)
    }

    /// §15.4: a dart already thrown is never evaluated again in forward play, even if a target appears under it.
    @Test func radar_onlyTheCurrentDartIsEvaluated() throws {
        var match = try registry.match(.radar, players: 1, seed: 1)
        // The replacement of target 4 lands at (60, 105): a dart planted there beforehand scored nothing…
        let outcomes = match.play("S1@(60.0, 105.0), S6@(140.0, 0.0)")
        #expect(outcomes[0].events.contains(.noEffect(player: 0)))
        #expect(blobs(match)[4] == [60, 105, 16, 1] && match.fact(0, "points") == 150)
        // …and still scores nothing; only a new dart at that point does.
        #expect(match.play("S1@(60.0, 105.0)")[0].events[1] == .blobDestroyed(player: 0, blob: 4, points: 150))
    }

    // MARK: Moving targets (GAMES.md §15.4)

    @Test func radar_movingTargetsMoveAtEveryTurnStartButTheFirst() throws {
        var match = try registry.match(.radar, ["movingTargets": true, "rounds": 2], players: 2, seed: 3)
        var random = SeededRandom(seed: 3)
        for _ in 0..<5 { _ = random.next() }
        var expected = blobs(match)
        func move() {
            for slot in 0..<5 {
                let centre = RadarPlacement.place(radius: expected[slot][2], obstacles: discs(expected), random: &random)
                // Each target really goes somewhere else: it is an obstacle of its own move.
                #expect([centre.x, centre.y] != Array(expected[slot].prefix(2)))
                expected[slot][0] = centre.x
                expected[slot][1] = centre.y
            }
        }
        // Never during a turn.
        match.play("MISS, MISS")
        #expect(blobs(match) == expected)
        // An early confirmation closes the turn first, then the targets move, just before `turnStarted`.
        #expect(match.endTurn().events == [.turnScored(player: 0, points: 0), .turnCompleted(player: 0), .blobsMoved,
                                           .turnStarted(player: 1, round: 1)])
        move()
        #expect(blobs(match) == expected)
        // Hit points survive the move.
        let large = expected[0]
        match.throwDart(dart(.single(1), Double(large[0]), Double(large[1])))
        expected[0][3] = 2
        #expect(match.endTurn().events == [.turnScored(player: 1, points: 10), .turnCompleted(player: 1),
                                           .roundStarted(round: 2), .blobsMoved, .turnStarted(player: 0, round: 2)])
        move()
        #expect(blobs(match) == expected && expected[0][3] == 2)
        match.play("|")
        move()
        #expect(blobs(match) == expected)
        // Nothing moves when the endTurn ends the game: no draw, no `blobsMoved`.
        #expect(match.endTurn().events == [.turnScored(player: 1, points: 0), .turnCompleted(player: 1),
                                           .gameFinished(reason: .roundLimit)])
        #expect(blobs(match) == expected && match.phase == .finished)
        expectWellPlaced(expected, "after three moves")
    }

    @Test func radar_withoutTheOptionNothingMovesBetweenTurns() throws {
        var match = try registry.match(.radar, players: 3, seed: 5)
        let initial = blobs(match)
        let outcomes = match.play("MISS | | MISS ×3 | MISS |")
        #expect(blobs(match) == initial)
        #expect(!outcomes.contains { $0.events.contains(.blobsMoved) })
        #expect(outcomes[1].events == [.turnScored(player: 0, points: 0), .turnCompleted(player: 0),
                                       .turnStarted(player: 1, round: 1)])
    }

    // MARK: Targets never overlap and stay inside the board

    /// Centres on the 5 mm lattice, discs inside the scoring area, at least 6 mm between two discs (§15.3).
    private func expectWellPlaced(_ rows: [[Int]], _ context: String) {
        #expect(rows.count == 5, "\(context)")
        for row in rows {
            #expect(row[0] % 5 == 0 && row[1] % 5 == 0, "\(context): \(row) is off the lattice")
            let reach = 170 - row[2]
            #expect(row[0] * row[0] + row[1] * row[1] <= reach * reach, "\(context): \(row) leaves the board")
        }
        for first in rows.indices {
            for second in rows.indices where second > first {
                let a = rows[first], b = rows[second]
                let dx = a[0] - b[0], dy = a[1] - b[1]
                let clearance = a[2] + b[2] + 6
                #expect(dx * dx + dy * dy >= clearance * clearance, "\(context): \(a) and \(b) are too close")
            }
        }
    }

    /// Long random games aimed at the targets, with and without moving targets: after every input the five
    /// targets are well placed, whatever the number of replacements and moves.
    @Test func radar_targetsNeverOverlapAndStayInsideTheBoard() throws {
        var replacements = 0, moves = 0
        for seed in 0..<24 as Range<UInt64> {
            let moving = seed % 2 == 1
            var match = try registry.match(.radar, ["movingTargets": .bool(moving), "rounds": 20], players: 1 + Int(seed % 3),
                                           seed: 1000 + seed)
            var random = SeededRandom(seed: seed)
            while match.phase != .finished {
                let outcome: InputOutcome
                if match.phase == .turnComplete || random.nextInt(below: 10) == 0 {
                    outcome = match.endTurn()
                } else if random.nextInt(below: 4) == 0 {
                    // Anywhere in the ±180 mm square, or a bare bed.
                    let hit = Hit.all[random.nextInt(below: Hit.all.count)]
                    let position = BoardPoint(x: Double(random.nextInt(below: 3601)) / 10 - 180,
                                              y: Double(random.nextInt(below: 3601)) / 10 - 180)
                    outcome = match.throwDart(DartRecord(hit: hit, position: random.nextInt(below: 2) == 0 ? position : nil))
                } else {
                    // Aimed at a target, somewhere inside its disc.
                    let target = blobs(match)[random.nextInt(below: 5)]
                    let reach = target[2] * 7
                    let position = BoardPoint(x: Double(target[0]) + Double(random.nextInt(below: 2 * reach + 1) - reach) / 10,
                                              y: Double(target[1]) + Double(random.nextInt(below: 2 * reach + 1) - reach) / 10)
                    outcome = match.throwDart(DartRecord(hit: .single(20), position: position))
                }
                for event in outcome.events {
                    if case .blobDestroyed = event { replacements += 1 }
                    if event == .blobsMoved { moves += 1 }
                }
                let rows = blobs(match)
                expectWellPlaced(rows, "seed \(seed), entry \(match.entries.count)")
                #expect(rows.map { $0[2] } == [40, 40, 28, 28, 16])
                #expect(zip(rows, [3, 3, 2, 2, 1]).allSatisfy { (1...$1).contains($0[3]) })
            }
        }
        // The games above do exercise both kinds of draw.
        #expect(replacements > 300 && moves > 300)
    }

    // MARK: Undo, corrections, replay (GAMES.md §2.5, §15.4)

    /// A random game with destructions and moving targets: the snapshot after every entry is a function of the
    /// journal alone. Undoing gives back each earlier snapshot; replaying, restoring and re-entering the same
    /// darts rebuild the same targets.
    @Test func radar_replayAfterUndoAndReplaceRebuildsTheSameTargets() throws {
        for seed in 0..<6 as Range<UInt64> {
            let options: GameOptions = ["movingTargets": .bool(seed % 2 == 0), "rounds": 4]
            var match = try registry.match(.radar, options, players: 2, seed: 77 + seed)
            var random = SeededRandom(seed: seed)
            var snapshots = [match.snapshot]
            while match.phase != .finished {
                if match.phase == .turnComplete || random.nextInt(below: 12) == 0 {
                    match.endTurn()
                } else {
                    let target = blobs(match)[random.nextInt(below: 5)]
                    let offset = Double(random.nextInt(below: 21) - 10)
                    let hit = Hit.all[random.nextInt(below: Hit.all.count)]
                    match.throwDart(dart(hit, Double(target[0]) + offset, Double(target[1]) - offset))
                }
                snapshots.append(match.snapshot)
                // Editing a dart of the current turn to itself replays the whole journal and changes nothing.
                if let last = match.currentTurn.last, match.phase != .finished {
                    let index = match.currentTurn.count - 1
                    #expect(match.replaceDart(at: index, with: last.hit, position: last.position).applied)
                    #expect(match.snapshot == snapshots[snapshots.count - 1])
                }
            }
            let journal = match.entries
            #expect(try registry.restoreMatch(match.record).snapshot == match.snapshot)

            // Undo everything, entry by entry.
            for expected in snapshots.dropLast().reversed() {
                #expect(match.undo().applied)
                #expect(match.snapshot == expected)
            }
            #expect(match.entries.isEmpty)

            // Play the same journal again, with an undo and a redo of every entry on the way.
            for (index, entry) in journal.enumerated() {
                for attempt in 0..<2 {
                    switch entry {
                    case .dart(let record): match.throwDart(record)
                    case .endTurn: match.endTurn()
                    }
                    #expect(match.snapshot == snapshots[index + 1], "seed \(seed), entry \(index)")
                    if attempt == 0 { match.undo() }
                }
            }
            #expect(match.entries == journal)
        }
    }

    /// §15.4: after a correction the following darts of the turn are evaluated again, and the replacements are
    /// drawn again in the corrected order.
    @Test func radar_correctionsRedrawTheReplacements() throws {
        var match = try registry.match(.radar, players: 1, seed: 1)
        // Two destructions in one turn: target 4 (6th draw), then target 2, hit twice (7th draw).
        match.play("S6@(140.0, 0.0), S4@(110.0, 65.0), S4@(110.0, 65.0)")
        let both = blobs(match)
        #expect(match.fact(0, "destroyed") == 2 && both[4] == [60, 105, 16, 1])

        // Removing the first dart: the turn reopens, target 4 is back at (140, 0) with its place never drawn,
        // and the replacement of target 2 becomes the 6th draw instead of the 7th: it lands elsewhere.
        #expect(match.removeDart(at: 0).applied)
        #expect(match.phase == .throwing && match.fact(0, "destroyed") == 1 && match.fact(0, "points") == 80)
        #expect(blobs(match)[4] == [140, 0, 16, 1])
        var random = SeededRandom(seed: 1)
        for _ in 0..<5 { _ = random.next() }
        let sixth = RadarPlacement.place(radius: 28, obstacles: discs(Self.seedOneBlobs), random: &random)
        #expect(blobs(match)[2] == [sixth.x, sixth.y, 28, 2] && blobs(match)[2] != both[2])

        // Putting the dart back at the end: the same darts in another order are another game.
        match.play("S6@(140.0, 0.0)")
        #expect(match.fact(0, "destroyed") == 2 && match.fact(0, "points") == 230)
        let seventh = RadarPlacement.place(radius: 16, obstacles: discs(blobs(match)).enumerated().map { index, disc in
            index == 4 ? RadarPlacement.Disc(x: 140, y: 0, radius: 16) : disc
        }, random: &random)
        #expect(blobs(match)[4] == [seventh.x, seventh.y, 16, 1])

        // Undo three times: the initial targets, and the generator back at its fifth draw.
        match.undo()
        match.undo()
        match.undo()
        #expect(blobs(match) == Self.seedOneBlobs && !match.canUndo)
        match.play("S6@(140.0, 0.0), S4@(110.0, 65.0), S4@(110.0, 65.0)")
        #expect(blobs(match) == both)
    }

    /// Everything a later dart depends on is in the facts or follows from the events (ARCHITECTURE.md §4.7):
    /// two darts with the same `effectKey` at the same position (or both without one), followed by the same
    /// inputs, lead to the same targets, facts, ranks and events. A hidden difference in the generator would
    /// show in the next replacement.
    @Test func radar_sameEffectKeySameFuture() throws {
        var pairs = 0
        for seed in 0..<40 as Range<UInt64> {
            var random = SeededRandom(seed: seed)
            var match = try registry.match(.radar, ["movingTargets": .bool(seed % 2 == 0), "rounds": 4],
                                           players: 1 + random.nextInt(below: 3), seed: seed)
            func aimed() -> BoardPoint {
                let target = blobs(match)[random.nextInt(below: 5)]
                return BoardPoint(x: Double(target[0]) + Double(random.nextInt(below: 41) - 20),
                                  y: Double(target[1]) + Double(random.nextInt(below: 41) - 20))
            }
            for _ in 0..<random.nextInt(below: 12) where match.phase != .finished {
                if match.phase == .turnComplete || random.nextInt(below: 6) == 0 { match.endTurn() }
                else { match.throwDart(DartRecord(hit: .single(20), position: aimed())) }
            }
            guard match.phase == .throwing else { continue }
            // Once with a shared position, once without any (canonical positions).
            for position in [aimed(), nil] {
                let groups = Dictionary(grouping: Hit.all) { match.effectKey(for: $0, position: position) }
                if position != nil {
                    // At equal position every bed other than MISS has the same effect.
                    #expect(groups.count <= 2 && groups.values.contains { $0.count >= 62 })
                }
                for group in groups.values where group.count > 1 {
                    var first = match, second = match
                    first.throwDart(DartRecord(hit: group[0], position: position))
                    second.throwDart(DartRecord(hit: group[group.count - 1], position: position))
                    pairs += 1
                    for _ in 0..<10 where first.phase != .finished {
                        let target = blobs(first)[random.nextInt(below: 5)]
                        let next = DartRecord(hit: .single(1), position: BoardPoint(x: Double(target[0]), y: Double(target[1])))
                        let confirm = first.phase != .throwing || random.nextInt(below: 5) == 0
                        let a = confirm ? first.endTurn() : first.throwDart(next)
                        let b = confirm ? second.endTurn() : second.throwDart(next)
                        #expect(a == b)
                        #expect(first.snapshot.players.map(\.facts) == second.snapshot.players.map(\.facts))
                        #expect(first.snapshot.facts == second.snapshot.facts)
                        #expect(first.snapshot.ranks == second.snapshot.ranks && first.phase == second.phase)
                    }
                }
            }
        }
        #expect(pairs > 60)
    }

    /// The rule is as strict as the schema when it is built without the kernel, and its initial draw is the
    /// five placements, nothing more: `turnStarted` at creation draws nothing, even with moving targets.
    @Test func radar_ruleBuiltOnItsOwn() throws {
        var random = SeededRandom(seed: 1)
        func configuration(_ options: GameOptions, players: Int = 2) -> GameConfiguration {
            GameConfiguration(gameID: .radar, options: options, players: testPlayers(players), seed: 1)
        }
        #expect(throws: GameConfigurationError.invalidOptionValue(key: "rounds")) {
            _ = try RadarRules(configuration: configuration(["rounds": 0]), random: &random)
        }
        #expect(throws: GameConfigurationError.playerCountOutOfRange(allowed: 1...8, actual: 0)) {
            _ = try RadarRules(configuration: configuration([:], players: 0), random: &random)
        }
        // A refused creation draws nothing.
        #expect(random == SeededRandom(seed: 1))

        var rules = try RadarRules(configuration: configuration(["movingTargets": true]), random: &random)
        var five = SeededRandom(seed: 1)
        for _ in 0..<5 { _ = five.next() }
        #expect(random == five && rules.roundLimit == 8)
        var events: [GameEvent] = []
        let first = TurnContext(players: testPlayers(2), currentPlayer: 0, round: 1, darts: [], phase: .throwing)
        rules.turnStarted(first, random: &random, events: &events)
        #expect(random == five && events.isEmpty)
        #expect(rules.presentation(first).facts["blobs"] == .table(Self.seedOneBlobs))
        // The next turn moves the five targets: five more draws and one event.
        let second = TurnContext(players: testPlayers(2), currentPlayer: 1, round: 1, darts: [], phase: .throwing)
        rules.turnStarted(second, random: &random, events: &events)
        for _ in 0..<5 { _ = five.next() }
        #expect(random == five && events == [.blobsMoved])
    }

    // MARK: Turn flow and end of game (GAMES.md §15.5, §15.6)

    @Test func radar_roundsAndEnd() throws {
        #expect(try registry.match(.radar, players: 1).snapshot.roundLimit == 8)
        #expect(try registry.match(.radar, players: 1).configuration.options == ["movingTargets": false, "rounds": 8])
        var match = try registry.match(.radar, ["rounds": 1], players: 2, seed: 1)
        let outcomes = match.play("S6@(140.0, 0.0) | |")
        #expect(outcomes[1].events == [.turnScored(player: 0, points: 150), .turnCompleted(player: 0),
                                       .turnStarted(player: 1, round: 1)])
        #expect(outcomes[2].events == [.turnScored(player: 1, points: 0), .turnCompleted(player: 1),
                                       .gameFinished(reason: .roundLimit)])
        #expect(match.phase == .finished && match.snapshot.ranks == [1, 2] && match.snapshot.winners == [0])
        // Volley emptied at the round limit; the presentation does not assume otherwise.
        #expect(match.snapshot.turn.darts.isEmpty && match.snapshot.highlights.isEmpty)
        #expect(match.gameFact("blobs") != nil && match.snapshot.turn.summary == nil)
        #expect(!match.throwDart(dart(.single(6), 60, 105)).isAccepted)
    }

    /// §15.6: points first, then destroyed targets, then a tie.
    @Test func radar_ranking() throws {
        var match = try registry.match(.radar, players: 3, seed: 1)
        #expect(match.snapshot.ranks == [1, 1, 1])
        // J1: one small target, 150 and one destroyed.
        match.play("S6@(140.0, 0.0) |")
        #expect(match.snapshot.ranks == [1, 2, 2])
        // J2: 10 points; J3: 10 points too.
        match.play("S12@(-80.0, 95.0) | S12@(-80.0, 95.0) |")
        #expect(points(match) == [150, 10, 10] && match.snapshot.ranks == [1, 2, 2])
        // J3 destroys the large target later: 10 + 30 = 40 and one destroyed.
        match.play("| | S12@(-80.0, 95.0)")
        #expect(points(match) == [150, 10, 40] && destroyed(match) == [1, 0, 1] && match.snapshot.ranks == [1, 3, 2])
    }

    // MARK: Presentation (GAMES.md §15.7, ARCHITECTURE.md §5.6)

    @Test func radar_scoreboard() throws {
        var match = try registry.match(.radar, players: 2, seed: 1)
        #expect(match.snapshot.title == LocalizedText(verbatim: "Radar") && match.snapshot.variant == nil)
        #expect(try registry.match(.radar, ["movingTargets": true], players: 1).snapshot.variant
                == LocalizedText(fr: "Cibles mobiles", en: "Moving targets"))
        #expect(match.snapshot.players[0].detail == LocalizedText(fr: "0 détruite", en: "0 destroyed"))
        #expect(match.snapshot.turn.summary == LocalizedText(fr: "Volée : 0", en: "Turn: 0"))
        #expect(match.snapshot.winnerTitle == nil && match.snapshot.objective == nil)

        match.play("S6@(140.0, 0.0), S12@(-80.0, 95.0), MISS")
        let row = match.snapshot.players[0]
        #expect(row.primary == ScoreValue(160) && row.meter == nil && row.badges.isEmpty)
        #expect(row.detail == LocalizedText(fr: "1 détruite · dernière volée : 160", en: "1 destroyed · last turn: 160"))
        #expect(row.facts == ["points": 160, "destroyed": 1, "dartsThrown": 3])
        #expect(match.snapshot.players[1].facts == ["points": 0, "destroyed": 0, "dartsThrown": 0])
        #expect(Set(match.snapshot.facts.keys) == ["blobs"])
        #expect(match.snapshot.turn.summary == LocalizedText(fr: "Volée : 160", en: "Turn: 160"))
        #expect(match.snapshot.turn.darts.map(\.caption) == [
            DartCaption(LocalizedText(fr: "Détruite +150", en: "Destroyed +150"), tone: .accent),
            DartCaption(LocalizedText(verbatim: "+10"), tone: .positive),
            DartCaption(LocalizedText(fr: "Sans effet", en: "No effect"), tone: .neutral),
        ])
        // The highlights follow the targets: new place for slot 4, one hit point less for slot 0.
        #expect(match.snapshot.highlights.map(\.zone) == [.disc(x: -80, y: 95, radius: 40), .disc(x: 70, y: -65, radius: 40),
                                                          .disc(x: 110, y: 65, radius: 28), .disc(x: 25, y: 15, radius: 28),
                                                          .disc(x: 60, y: 105, radius: 16)])
        #expect(match.snapshot.highlights.map(\.strength) == [2, 3, 2, 2, 1])

        // The same highlights for the next player.
        let before = match.snapshot.highlights
        match.play("|")
        #expect(match.snapshot.highlights == before && match.snapshot.currentPlayer == 1)
        #expect(match.snapshot.turn.summary == LocalizedText(fr: "Volée : 0", en: "Turn: 0"))
    }

    @Test func radar_results() throws {
        var match = try registry.match(.radar, ["rounds": 1], players: 2, seed: 1)
        match.play("S6@(140.0, 0.0), S12@(-80.0, 95.0), MISS | MISS ×3 |")
        #expect(match.snapshot.outcome == LocalizedText(fr: "160 points et 1 cible détruite.", en: "160 points and 1 target destroyed."))
        #expect(match.snapshot.players.map(\.resultLines) == [
            [LocalizedText(fr: "1 cible détruite", en: "1 target destroyed")],
            [LocalizedText(fr: "0 cible détruite", en: "0 targets destroyed")],
        ])
        var tie = try registry.match(.radar, ["rounds": 1], players: 2, seed: 1)
        tie.play("S12@(-80.0, 95.0) | S12@(-80.0, 95.0) |")
        #expect(tie.snapshot.ranks == [1, 1])
        #expect(tie.snapshot.outcome == LocalizedText(fr: "Égalité à 10 points.", en: "A tie at 10 points."))
    }
}
