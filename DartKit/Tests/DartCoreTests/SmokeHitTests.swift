import Foundation
import Testing
import DartCore

/// `Hit` and its notation (GAMES.md §2.2, ARCHITECTURE.md §4.2).
@Suite struct SmokeHitTests {
    @Test func sixtyThreeDistinctValues_inCanonicalOrder() {
        #expect(Hit.all.count == 63)
        #expect(Set(Hit.all).count == 63)
        #expect(Array(Hit.all[0..<20]) == (1...20).map { Hit.single($0) })
        #expect(Array(Hit.all[20..<40]) == (1...20).map { Hit.double($0) })
        #expect(Array(Hit.all[40..<60]) == (1...20).map { Hit.treble($0) })
        #expect(Array(Hit.all[60...]) == [.outerBull, .innerBull, .miss])
    }

    @Test func canonicalNotation_roundTripsForEveryValue() {
        for hit in Hit.all {
            #expect(Hit(notation: hit.notation) == hit)
            #expect(hit.formatted(.canonical) == hit.notation)
            #expect(hit.description == hit.notation)
        }
        #expect(Hit.single(5).notation == "S5")
        #expect(Hit.double(16).notation == "D16")
        #expect(Hit.treble(20).notation == "T20")
        #expect(Hit.outerBull.notation == "SB")
        #expect(Hit.innerBull.notation == "DB")
        #expect(Hit.miss.notation == "MISS")
    }

    @Test func pointsNotation_roundTripsForEveryValue() {
        for hit in Hit.all {
            #expect(Hit(notation: hit.formatted(.points)) == hit)
        }
        #expect(Hit.single(5).formatted(.points) == "S5")
        #expect(Hit.double(16).formatted(.points) == "D16")
        #expect(Hit.treble(20).formatted(.points) == "T20")
        #expect(Hit.outerBull.formatted(.points) == "25")
        #expect(Hit.innerBull.formatted(.points) == "50")
        #expect(Hit.miss.formatted(.points) == "miss")
    }

    @Test(arguments: [
        ("t20", "T20"), ("d16", "D16"), ("s5", "S5"), ("5", "S5"), ("20", "S20"), ("1", "S1"),
        ("sb", "SB"), ("25", "SB"), ("db", "DB"), ("50", "DB"), ("miss", "MISS"), ("Miss", "MISS"),
        ("  T20 ", "T20"), ("S10", "S10"), ("d20", "D20"), ("10", "S10"),
    ])
    func toleratedReadings(text: String, canonical: String) {
        #expect(Hit(notation: text)?.notation == canonical)
    }

    @Test(arguments: [
        "", " ", "S", "D", "T", "S0", "S21", "D0", "T21", "T25", "0", "21", "26", "100", "X5", "B", "BULL", "bull",
        "S-1", "S1.5", "S 5", "SB1", "DB2", "MISSED", "T٢", "S٣",
        // A leading zero is not a notation: neither before a sector number nor before a bull value.
        "S05", "T020", "D007", "005", "020", "025", "050", "00", "S00",
    ])
    func refusedReadings(text: String) {
        #expect(Hit(notation: text) == nil)
    }

    @Test func points_multiplier_doubleTrebleBullMiss() {
        for n in 1...20 {
            #expect(Hit.single(n).points == n && Hit.double(n).points == 2 * n && Hit.treble(n).points == 3 * n)
            #expect(Hit.single(n).multiplier == 1 && Hit.double(n).multiplier == 2 && Hit.treble(n).multiplier == 3)
            #expect(Hit.single(n).number == n && Hit.double(n).number == n && Hit.treble(n).number == n)
        }
        #expect(Hit.outerBull.points == 25 && Hit.innerBull.points == 50 && Hit.miss.points == 0)
        #expect(Hit.outerBull.multiplier == 1 && Hit.innerBull.multiplier == 2 && Hit.miss.multiplier == 0)
        #expect(Hit.outerBull.number == nil && Hit.innerBull.number == nil && Hit.miss.number == nil)
        // D1…D20 and DB are doubles; there is no treble of the bull.
        #expect(Hit.all.filter(\.isDouble) == (1...20).map { Hit.double($0) } + [.innerBull])
        #expect(Hit.all.filter(\.isTreble) == (1...20).map { Hit.treble($0) })
        #expect(Hit.all.filter(\.isBull) == [.outerBull, .innerBull])
        #expect(Hit.all.filter(\.isMiss) == [.miss])
        #expect(Hit.all.map(\.points).max() == 60)
    }

    @Test func validatingInitialiser() {
        #expect(Hit(bed: .single, number: 7) == .single(7))
        #expect(Hit(bed: .double, number: 20) == .double(20))
        #expect(Hit(bed: .treble, number: 1) == .treble(1))
        #expect(Hit(bed: .outerBull, number: nil) == .outerBull)
        #expect(Hit(bed: .innerBull, number: nil) == .innerBull)
        #expect(Hit(bed: .miss, number: nil) == .miss)
        #expect(Hit(bed: .single, number: 0) == nil)
        #expect(Hit(bed: .single, number: 21) == nil)
        #expect(Hit(bed: .treble, number: nil) == nil)
        #expect(Hit(bed: .miss, number: 3) == nil)
        #expect(Hit(bed: .innerBull, number: 25) == nil)
        #expect(Hit.Bed.allCases.count == 6)
    }

    @Test func json_isTheCanonicalNotation() throws {
        let encoded = try JSONEncoder().encode([Hit.treble(20), .innerBull, .outerBull, .miss, .single(5)])
        #expect(String(decoding: encoded, as: UTF8.self) == #"["T20","DB","SB","MISS","S5"]"#)
        let single = try JSONEncoder().encode(Hit.treble(20))
        #expect(String(decoding: single, as: UTF8.self) == #""T20""#)
        #expect(try JSONDecoder().decode([Hit].self, from: encoded) == [.treble(20), .innerBull, .outerBull, .miss, .single(5)])
        // Decoding is as tolerant as the parser, and refuses what the parser refuses.
        #expect(try JSONDecoder().decode([Hit].self, from: Data(#"["t20","25","7"]"#.utf8)) == [.treble(20), .outerBull, .single(7)])
        #expect(throws: DecodingError.self) { try JSONDecoder().decode([Hit].self, from: Data(#"["T21"]"#.utf8)) }
        #expect(throws: DecodingError.self) { try JSONDecoder().decode([Hit].self, from: Data("[20]".utf8)) }
        for hit in Hit.all {
            #expect(try JSONDecoder().decode(Hit.self, from: JSONEncoder().encode(hit)) == hit)
        }
    }

    @Test func zoneOfAHit_andContainment() {
        #expect(BoardZone(.miss) == nil)
        #expect(BoardZone(.single(5)) == .single(5))
        #expect(BoardZone(.double(16)) == .double(16))
        #expect(BoardZone(.treble(20)) == .treble(20))
        #expect(BoardZone(.outerBull) == .outerBull)
        #expect(BoardZone(.innerBull) == .innerBull)
        for hit in Hit.all {
            // The smallest zone of a hit contains that hit and no other.
            if let zone = BoardZone(hit) {
                #expect(Hit.all.filter { zone.contains($0) } == [hit])
            }
            #expect(!BoardZone.sector(20).contains(.miss) && !BoardZone.bull.contains(.miss))
        }
        #expect(Hit.all.filter { BoardZone.sector(7).contains($0) } == [.single(7), .double(7), .treble(7)])
        #expect(Hit.all.filter { BoardZone.bull.contains($0) } == [.outerBull, .innerBull])
        #expect(BoardZone.sector(7).number == 7 && BoardZone.treble(3).number == 3)
        #expect(BoardZone.bull.number == nil && BoardZone.outerBull.number == nil && BoardZone.innerBull.number == nil)
    }
}
