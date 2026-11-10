import Testing
import DartCore

/// Known-answer values of GAMES.md §2.8: SplitMix64, `nextInt`, `shuffled` and the three `ringLayout`.
@Suite struct SmokeRandomTests {
    /// A generator that has already produced `count` values.
    private func generator(seed: UInt64, after count: Int) -> SeededRandom {
        var rng = SeededRandom(seed: seed)
        for _ in 0..<count { _ = rng.next() }
        return rng
    }

    @Test(arguments: [
        (UInt64(0), [0xE220_A839_7B1D_CDAF, 0x6E78_9E6A_A1B9_65F4, 0x06C4_5D18_8009_454F, 0xF88B_B8A8_724C_81EC] as [UInt64]),
        (UInt64(1), [0x910A_2DEC_8902_5CC1, 0xBEEB_8DA1_658E_EC67, 0xF893_A2EE_FB32_555E, 0x71C1_8690_EE42_C90B] as [UInt64]),
        (UInt64(42), [0xBDD7_3226_2FEB_6E95, 0x28EF_E333_B266_F103, 0x4752_6757_130F_9F52, 0x581C_E1FF_0E4A_E394] as [UInt64]),
    ])
    func splitMix64_firstFourValues(seed: UInt64, expected: [UInt64]) {
        var rng = SeededRandom(seed: seed)
        #expect((0..<4).map { _ in rng.next() } == expected)
    }

    @Test func nextInt_seed42_below20() {
        var rng = SeededRandom(seed: 42)
        #expect((0..<6).map { _ in rng.nextInt(below: 20) } == [13, 11, 18, 4, 10, 2])
    }

    @Test func nextInt_seed1_below2121() {
        var rng = SeededRandom(seed: 1)
        #expect(rng.nextInt(below: 2121) == 1934)
    }

    @Test func nextInt_isNextModuloBound_andBoundOneIsAlwaysZero() {
        var a = SeededRandom(seed: 7), b = SeededRandom(seed: 7)
        for bound in [1, 2, 3, 20, 2121, 1_000_003] {
            let raw = a.next()
            let value = b.nextInt(below: bound)
            #expect(value == Int(raw % UInt64(bound)))
            #expect((0..<bound).contains(value))
        }
        var one = SeededRandom(seed: 99)
        #expect((0..<5).map { _ in one.nextInt(below: 1) } == [0, 0, 0, 0, 0])
    }

    @Test func shuffled_seed1_oneToTwenty() {
        var rng = SeededRandom(seed: 1)
        #expect(rng.shuffled(Array(1...20)) == [2, 15, 11, 4, 20, 5, 7, 17, 16, 14, 3, 1, 12, 8, 19, 10, 18, 13, 9, 6])
        // Fisher–Yates from the last index down to 1: `count - 1` draws.
        #expect(rng == generator(seed: 1, after: 19))
    }

    @Test func shuffled_seed42_sixValues() {
        var rng = SeededRandom(seed: 42)
        #expect(rng.shuffled([15, 16, 17, 18, 19, 20]) == [19, 18, 15, 17, 20, 16])
        #expect(rng == generator(seed: 42, after: 5))
    }

    @Test func shuffled_emptyAndSingle_drawNothing() {
        var rng = SeededRandom(seed: 5)
        #expect(rng.shuffled([Int]()) == [])
        #expect(rng.shuffled([9]) == [9])
        #expect(rng == SeededRandom(seed: 5))
    }

    @Test func ringLayout_threePlayersWidthThree_seed1() {
        var rng = SeededRandom(seed: 1)
        #expect(ringLayout(playerCount: 3, width: 3, rng: &rng) == [[8, 11, 14], [6, 10, 15], [20, 1, 18]])
        // 1 (offset) + 11 (gaps) + 2 (order) = 14 draws.
        #expect(rng == generator(seed: 1, after: 14))
    }

    @Test func ringLayout_fourPlayersWidthTwo_seed42() {
        var rng = SeededRandom(seed: 42)
        #expect(ringLayout(playerCount: 4, width: 2, rng: &rng) == [[9, 12], [16, 8], [1, 18], [17, 3]])
        #expect(rng == generator(seed: 42, after: 16))
    }

    @Test func ringLayout_twoPlayersWidthOne_seed1() {
        var rng = SeededRandom(seed: 1)
        #expect(ringLayout(playerCount: 2, width: 1, rng: &rng) == [[11], [6]])
        #expect(rng == generator(seed: 1, after: 20))
    }

    /// The intermediate values that GAMES.md §2.8 prints for the first layout: offset, gap draws and order.
    @Test func ringLayout_seed1_intermediateDraws() {
        var rng = SeededRandom(seed: 1)
        #expect(rng.nextInt(below: 20) == 5)
        #expect((0..<11).map { _ in rng.nextInt(below: 3) } == [1, 0, 2, 0, 2, 0, 0, 0, 1, 0, 1])
        #expect(rng.shuffled([0, 1, 2]) == [1, 0, 2])
    }

    /// Whatever the seed: every zone is a run of `width` consecutive ring numbers, and no number is used twice.
    @Test func ringLayout_zonesAreConsecutiveAndDisjoint() {
        let ring = BoardGeometry.standardSectorOrder
        for seed in UInt64(0)..<50 {
            for (players, width) in [(2, 3), (6, 3), (8, 2), (8, 1), (4, 5), (1, 20)] {
                var rng = SeededRandom(seed: seed)
                let zones = ringLayout(playerCount: players, width: width, rng: &rng)
                #expect(zones.count == players)
                #expect(Set(zones.joined()).count == players * width)
                for zone in zones {
                    #expect(zone.count == width)
                    guard let first = zone.first, let start = ring.firstIndex(of: first) else {
                        Issue.record("empty zone for seed \(seed)")
                        continue
                    }
                    #expect(zone == (0..<width).map { ring[(start + $0) % 20] })
                }
                #expect(rng == generator(seed: seed, after: 1 + (20 - players * width) + (players - 1)))
            }
        }
    }

    @Test func generatorIsAValue_sameSeedSameSequence() {
        var a = SeededRandom(seed: 123)
        var copy = a
        #expect(a.next() == copy.next())
        _ = a.next()
        #expect(a != copy)
        _ = copy.next()
        #expect(a == copy && a.state == copy.state)
    }
}
