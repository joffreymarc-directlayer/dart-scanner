import Foundation
import Testing
import DartCore

/// Impact point and canonical positions (GAMES.md §2.13, ARCHITECTURE.md §4.2 and §4.7).
@Suite struct SmokePositionTests {
    /// The table of GAMES.md §2.13, copied as it is printed: number, then S, T and D in tenths of a millimetre.
    private static let printedTable = """
          20     (    0,  1345)    (    0,  1030)    (    0,  1660)
           1     (  416,  1279)    (  318,   980)    (  513,  1579)
          18     (  791,  1088)    (  605,   833)    (  976,  1343)
           4     ( 1088,   791)    (  833,   605)    ( 1343,   976)
          13     ( 1279,   416)    (  980,   318)    ( 1579,   513)
           6     ( 1345,     0)    ( 1030,     0)    ( 1660,     0)
          10     ( 1279,  -416)    (  980,  -318)    ( 1579,  -513)
          15     ( 1088,  -791)    (  833,  -605)    ( 1343,  -976)
           2     (  791, -1088)    (  605,  -833)    (  976, -1343)
          17     (  416, -1279)    (  318,  -980)    (  513, -1579)
           3     (    0, -1345)    (    0, -1030)    (    0, -1660)
          19     ( -416, -1279)    ( -318,  -980)    ( -513, -1579)
           7     ( -791, -1088)    ( -605,  -833)    ( -976, -1343)
          16     (-1088,  -791)    ( -833,  -605)    (-1343,  -976)
           8     (-1279,  -416)    ( -980,  -318)    (-1579,  -513)
          11     (-1345,     0)    (-1030,     0)    (-1660,     0)
          14     (-1279,   416)    ( -980,   318)    (-1579,   513)
           9     (-1088,   791)    ( -833,   605)    (-1343,   976)
          12     ( -791,  1088)    ( -605,   833)    ( -976,  1343)
           5     ( -416,  1279)    ( -318,   980)    ( -513,  1579)
        """

    /// One row per number: `[number, Sx, Sy, Tx, Ty, Dx, Dy]`.
    private static func tableRows() -> [[Int]] {
        printedTable.split(separator: "\n").map { line in
            line.split(whereSeparator: { !($0.isNumber || $0 == "-") }).compactMap { Int($0) }
        }
    }

    // MARK: Canonical positions

    @Test func the62CanonicalPositions_matchTheTableOfGames2_13() {
        let rows = Self.tableRows()
        #expect(rows.count == 20)
        #expect(rows.map { $0.first ?? 0 } == BoardGeometry.standardSectorOrder)
        var checked = 0
        for row in rows {
            guard row.count == 7 else {
                Issue.record("unreadable row \(row)")
                continue
            }
            let number = row[0]
            #expect(ImpactPoint.canonical(of: .single(number)) == ImpactPoint(x: row[1], y: row[2]))
            #expect(ImpactPoint.canonical(of: .treble(number)) == ImpactPoint(x: row[3], y: row[4]))
            #expect(ImpactPoint.canonical(of: .double(number)) == ImpactPoint(x: row[5], y: row[6]))
            checked += 3
        }
        #expect(ImpactPoint.canonical(of: .outerBull) == ImpactPoint(x: 0, y: 111))
        #expect(ImpactPoint.canonical(of: .innerBull) == ImpactPoint(x: 0, y: 0))
        #expect(ImpactPoint.canonical(of: .miss) == nil)
        #expect(checked + 2 == 62)
    }

    @Test func the62CanonicalPositions_areTheBedCentresRoundedToTheTenth() {
        let board = BoardGeometry.standard
        for hit in Hit.all {
            let centre = board.centre(of: hit)
            #expect(ImpactPoint.canonical(of: hit) == centre.map { ImpactPoint($0) }, "\(hit)")
            if let canonical = ImpactPoint.canonical(of: hit) {
                // A canonical position lies in its own bed.
                #expect(board.hit(at: canonical.boardPoint) == hit)
            }
        }
        #expect(Set(Hit.all.compactMap { ImpactPoint.canonical(of: $0) }).count == 62)
    }

    // MARK: Conversion of a recorded position

    @Test func rounding_nearestTenth_halvesAwayFromZero() {
        #expect(ImpactPoint(BoardPoint(x: 0.05, y: -0.05)) == ImpactPoint(x: 1, y: -1))
        #expect(ImpactPoint(BoardPoint(x: 43.04, y: 43.06)) == ImpactPoint(x: 430, y: 431))
        #expect(ImpactPoint(BoardPoint(x: -120.05, y: 120.05)) == ImpactPoint(x: -1201, y: 1201))
        #expect(ImpactPoint(BoardPoint(x: 0, y: 0)) == ImpactPoint(x: 0, y: 0))
        #expect(ImpactPoint(BoardPoint(x: 124.0, y: -0.04)) == ImpactPoint(x: 1240, y: 0))
        #expect(ImpactPoint(BoardPoint(x: 12.34, y: -56.78)) == ImpactPoint(x: 123, y: -568))
    }

    @Test func nonFiniteOrHugeCoordinate_doesNotTrap_andIsPushedOffTheBoard() {
        // Not a finite number once multiplied by ten: 1 000 000 tenths, whatever the sign.
        #expect(ImpactPoint(BoardPoint(x: .nan, y: .infinity)) == ImpactPoint(x: 1_000_000, y: 1_000_000))
        #expect(ImpactPoint(BoardPoint(x: -.infinity, y: .greatestFiniteMagnitude)) == ImpactPoint(x: 1_000_000, y: 1_000_000))
        #expect(ImpactPoint(BoardPoint(x: -.greatestFiniteMagnitude, y: 0)) == ImpactPoint(x: 1_000_000, y: 0))
        // Finite but oversized: clamped to ±1 000 000 tenths.
        #expect(ImpactPoint(BoardPoint(x: 1e300, y: -1e300)) == ImpactPoint(x: 1_000_000, y: -1_000_000))
        #expect(ImpactPoint(BoardPoint(x: 100_000, y: -100_000)) == ImpactPoint(x: 1_000_000, y: -1_000_000))
        #expect(ImpactPoint(BoardPoint(x: 100_000.1, y: -100_000.1)) == ImpactPoint(x: 1_000_000, y: -1_000_000))
        #expect(ImpactPoint(BoardPoint(x: 99_999.9, y: -99_999.9)) == ImpactPoint(x: 999_999, y: -999_999))
        // Through the total function too.
        #expect(ImpactPoint(hit: .single(20), position: BoardPoint(x: .nan, y: .nan)) == ImpactPoint(x: 1_000_000, y: 1_000_000))
    }

    @Test func boardPoint_isTheSamePointInMillimetres() {
        #expect(ImpactPoint(x: 1240, y: -5).boardPoint == BoardPoint(x: 124, y: -0.5))
        #expect(ImpactPoint(ImpactPoint(x: -1088, y: 791).boardPoint) == ImpactPoint(x: -1088, y: 791))
    }

    // MARK: The three rules of the impact point

    @Test func rule1_aMissHasNoImpactPoint_evenWithAPosition() {
        #expect(ImpactPoint(hit: .miss, position: nil) == nil)
        #expect(ImpactPoint(hit: .miss, position: BoardPoint(x: 0, y: 0)) == nil)
        #expect(ImpactPoint(hit: .miss, position: BoardPoint(x: 10, y: 134.5)) == nil)
    }

    @Test func rule2_aRecordedPositionIsTakenAsItIs() {
        // It is not checked against the hit: (124, 0) is in the single 6, the hit says treble 20.
        let recorded = BoardPoint(x: 124.0, y: 0.0)
        for hit in Hit.all where !hit.isMiss {
            #expect(ImpactPoint(hit: hit, position: recorded) == ImpactPoint(x: 1240, y: 0))
        }
        #expect(ImpactPoint(hit: .innerBull, position: BoardPoint(x: 500, y: -500)) == ImpactPoint(x: 5000, y: -5000))
    }

    @Test func rule3_withoutAPosition_theCanonicalPositionOfTheBed() {
        for hit in Hit.all where !hit.isMiss {
            #expect(ImpactPoint(hit: hit, position: nil) == ImpactPoint.canonical(of: hit))
        }
        #expect(ImpactPoint(hit: .single(6), position: nil) == ImpactPoint(x: 1345, y: 0))
        #expect(ImpactPoint(hit: .treble(20), position: nil) == ImpactPoint(x: 0, y: 1030))
        #expect(ImpactPoint(hit: .double(3), position: nil) == ImpactPoint(x: 0, y: -1660))
    }

    // MARK: TurnContext

    @Test func turnContext_positionsAreAlignedWithTheDarts() {
        let players = [Player(name: "A"), Player(name: "B")]
        let recorded = BoardPoint(x: 124, y: 0)
        let context = TurnContext(players: players, currentPlayer: 1, round: 3,
                                  darts: [.single(6), .treble(20), .miss], positions: [recorded], phase: .throwing)
        // `positions` may be shorter than `darts`: the missing entries are nil.
        #expect(context.positions == [recorded, nil, nil])
        #expect(context.impact(ofDart: 0) == ImpactPoint(x: 1240, y: 0))
        #expect(context.impact(ofDart: 1) == ImpactPoint(x: 0, y: 1030))
        #expect(context.impact(ofDart: 2) == nil)
        #expect(context.impact(ofDart: 3) == nil && context.impact(ofDart: -1) == nil)
        // `impact` is the impact point of the last dart.
        #expect(context.impact == nil)
        let two = TurnContext(players: players, currentPlayer: 0, round: 1, darts: [.miss, .double(3)],
                              positions: [nil, BoardPoint(x: -1, y: -165.04)], phase: .throwing)
        #expect(two.impact == ImpactPoint(x: -10, y: -1650))
        // Longer than `darts`: the extra positions are ignored.
        let long = TurnContext(players: players, currentPlayer: 0, round: 1, darts: [.single(1)],
                               positions: [nil, recorded, recorded], phase: .throwing)
        #expect(long.positions == [nil])
        #expect(long.impact == ImpactPoint.canonical(of: .single(1)))
        let empty = TurnContext(players: players, currentPlayer: 0, round: 1, darts: [], phase: .throwing)
        #expect(empty.positions.isEmpty && empty.impact == nil)
    }

    @Test func turnContext_isFirstTurnOfGame_onlyForRoundOnePlayerOne() {
        let players = [Player(name: "A"), Player(name: "B")]
        func first(_ player: PlayerIndex, _ round: Int) -> Bool {
            TurnContext(players: players, currentPlayer: player, round: round, darts: [], phase: .throwing).isFirstTurnOfGame
        }
        #expect(first(0, 1))
        #expect(!first(1, 1) && !first(0, 2) && !first(1, 2))
    }

    // MARK: Disc zone

    @Test func discZone_containsNoHit_andHasNoNumber() {
        let disc = BoardZone.disc(x: -80, y: 95, radius: 40)
        #expect(Hit.all.allSatisfy { !disc.contains($0) })
        #expect(disc.number == nil)
        #expect(disc == BoardZone.disc(x: -80, y: 95, radius: 40))
        #expect(disc != BoardZone.disc(x: -80, y: 95, radius: 28))
        // Even a disc laid on the bull contains no hit: only the game knows what a dart touches.
        #expect(!BoardZone.disc(x: 0, y: 0, radius: 16).contains(.innerBull))
    }

    @Test func zones_roundTripThroughJSON_discIncluded() throws {
        let zones: [BoardZone] = [.sector(20), .single(5), .double(16), .treble(19), .outerBull, .innerBull, .bull,
                                  .disc(x: -80, y: 95, radius: 40), .disc(x: 140.5, y: -0.25, radius: 16)]
        let data = try JSONEncoder().encode(zones)
        #expect(try JSONDecoder().decode([BoardZone].self, from: data) == zones)
        let highlight = BoardHighlight(zone: .disc(x: 25, y: 15, radius: 28), role: .target, label: "+20", strength: 2)
        #expect(highlight.zone == .disc(x: 25, y: 15, radius: 28) && highlight.owner == nil && highlight.marker == nil)
    }
}
