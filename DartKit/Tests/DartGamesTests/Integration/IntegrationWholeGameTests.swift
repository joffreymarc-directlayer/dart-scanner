import Foundation
import Testing
import DartCore
import DartGames
import DartTestSupport

/// One whole game of each of the fourteen games, created through `GameRegistry.standard` and played through
/// `GameMatch` as the play screen does: darts, confirmations, undo, the correction of a dart the camera read
/// wrong (`replaceDart`), the removal of a phantom (`removeDart`), then the replay checks of
/// `IntegrationSupport.checkReplay`. Every expected value is worked out by hand from GAMES.md (sections 3 to 16)
/// and written next to the script.
@Suite struct IntegrationWholeGameTests {
    private typealias Support = IntegrationSupport

    // MARK: X01 (GAMES.md §3)

    /// 301 double out. J1 leaves 1 (bust), the busting dart is undone and thrown again, then J1 checks out on the
    /// bull after a correction of the second dart (S14 read, S11 thrown).
    @Test func x01_doubleOut_bustUndoAndCorrectedCheckout() throws {
        var match = try Support.match(.x01, ["startScore": 301, "outRule": "double"], players: 2)
        match.play("T20, T20, T20 | S20, S20, S20 |")
        #expect(match.fact(0, "remaining") == 121)
        #expect(match.fact(1, "remaining") == 241)

        let bust = match.play("T20, T20")
        #expect(bust.last?.events.contains(.bust(player: 0, reason: .oneLeft)) == true)
        #expect(match.phase == .turnComplete)
        #expect(match.fact(0, "remaining") == 121)
        #expect(match.fact(0, "busts") == 1)

        // Undoing the busting dart reopens the turn.
        #expect(match.undo().applied)
        #expect(match.phase == .throwing)
        #expect(match.fact(0, "remaining") == 61)
        #expect(match.fact(0, "busts") == 0)
        match.play("T20 | T20, T20, T20 |")
        #expect(match.fact(0, "remaining") == 121)
        #expect(match.fact(1, "remaining") == 61)

        match.play("T20, S14")
        #expect(match.fact(0, "remaining") == 47)
        Support.expectClean(match.replaceDart(at: 1, with: .single(11)))
        #expect(match.fact(0, "remaining") == 50)
        #expect(match.currentTurn[1].corrected)
        let checkout = match.play("DB")
        #expect(checkout.first?.events.contains(.gameFinished(reason: .victory)) == true)

        #expect(match.phase == .finished)
        #expect(match.snapshot.finishReason == .victory)
        #expect(match.snapshot.ranks == [1, 2])
        #expect(match.fact(0, "remaining") == 0)
        #expect(match.turnNotation == ["T20", "S11", "DB"])
        try Support.checkReplay(match)
    }

    // MARK: Cricket (GAMES.md §4)

    /// Standard scoring. J2 scores 30 on the 15 before J1 closes it; J1 closes every target but trails, so the
    /// game goes on, and J1 wins on T20 (60 points). A phantom S20 in J2's turn is removed.
    @Test func cricket_standard_closedButBehind_thenWinsOnPoints() throws {
        var match = try Support.match(.cricket, ["scoring": "standard", "maxRounds": .null], players: 2)
        match.play("T20, T19, T18 | T15, S15, S15 |")
        #expect(match.fact(1, "points") == 30)
        match.play("T17, T16, T15 |")

        match.play("S20")
        #expect(match.fact(1, "marks").flatMap { if case .map(let marks) = $0 { return marks[20] } else { return nil } } == 1)
        Support.expectClean(match.removeDart(at: 0))
        #expect(match.fact(1, "marks").flatMap { if case .map(let marks) = $0 { return marks[20] } else { return nil } } == 0)
        match.play("MISS ×3 |")

        match.play("DB, SB")
        #expect(match.fact(0, "closedCount") == 7)
        #expect(match.phase == .throwing, "every target closed, but 0 points against 30: the game goes on")
        match.play("T20")

        #expect(match.phase == .finished)
        #expect(match.snapshot.finishReason == .victory)
        #expect(match.fact(0, "points") == 60)
        #expect(match.fact(1, "points") == 30)
        #expect(match.snapshot.ranks == [1, 2])
        try Support.checkReplay(match)
    }

    // MARK: Killer (GAMES.md §5)

    /// Hard level, three players, one life, one arming hit: J1 becomes Killer and eliminates J2; J3 becomes
    /// Killer, aims at J1, and the camera reads J2's (dead) zone; the correction ends the game.
    @Test func killer_hard_threePlayers_correctionGivesTheLastKill() throws {
        var match = try Support.match(.killer, ["level": "hard", "lives": 1, "armingHits": 1], players: 3, seed: 5)
        let zones = try (0..<3).map { try #require(Support.ints(match.fact($0, "zone"))) }
        #expect(zones.allSatisfy { $0.count == 1 })
        #expect(Set(zones.flatMap { $0 }).count == 3)

        Support.dart(.single(zones[0][0]), on: &match)
        #expect(match.fact(0, "isKiller") == true)
        Support.dart(.treble(zones[1][0]), on: &match)
        #expect(match.fact(1, "eliminated") == true)
        Support.dart(.miss, on: &match)
        #expect(match.endTurn().isAccepted)
        #expect(match.snapshot.currentPlayer == 2, "J2 is out: J3 plays")

        Support.dart(.double(zones[2][0]), on: &match)
        Support.dart(.single(zones[1][0]), needsReview: true, on: &match)
        #expect(match.phase == .throwing, "J2's zone is inert")
        Support.expectClean(match.replaceDart(at: 1, with: .single(zones[0][0])))

        #expect(match.phase == .finished)
        #expect(match.snapshot.finishReason == .lastPlayerStanding)
        #expect(match.snapshot.ranks == [2, 3, 1])
        #expect(match.fact(0, "kills") == 1)
        #expect(match.fact(2, "kills") == 1)
        try Support.checkReplay(match)
    }

    // MARK: Shanghai (GAMES.md §7)

    /// Three rounds. J1 has 48 points, but J2's third dart, read S3 and corrected to T3, is a Shanghai: J2 wins.
    @Test func shanghai_correctedThirdDartIsAShanghai() throws {
        var match = try Support.match(.shanghai, ["rounds": 3], players: 2)
        match.play("S1, D1, MISS | T1, S5, MISS | T2, T2, T2 | S2, MISS, MISS | T3, T3, T3 |")
        #expect(match.fact(0, "points") == 48)
        #expect(match.fact(1, "points") == 5)

        match.play("S3, D3, S3")
        #expect(match.phase == .turnComplete)
        #expect(match.fact(1, "points") == 17)
        Support.expectClean(match.replaceDart(at: 2, with: .treble(3)))

        #expect(match.phase == .finished)
        #expect(match.snapshot.finishReason == .victory)
        #expect(match.fact(1, "points") == 23)
        #expect(match.snapshot.ranks == [2, 1], "a Shanghai ranks first whatever the points")
        try Support.checkReplay(match)
    }

    // MARK: Moon Landing (GAMES.md §10)

    /// Pro (exact landing), 100 away. J1 bounces; J2's S19 is read S20, which lands at once; the correction
    /// reopens the game and J2 lands on S1.
    @Test func moonLanding_pro_bounceThenACorrectedLanding() throws {
        var match = try Support.match(.moonLanding, ["distance": 100, "exactLanding": true], players: 2)
        match.play("T20, T20")
        #expect(match.phase == .turnComplete)
        #expect(match.fact(0, "remaining") == 100)
        #expect(match.fact(0, "busts") == 1)
        match.play("| T20, S20 | T20, S10, MISS |")
        #expect(match.fact(0, "remaining") == 30)
        #expect(match.fact(1, "remaining") == 20)

        match.play("S20")
        #expect(match.phase == .finished)
        Support.expectClean(match.replaceDart(at: 0, with: .single(19)))
        #expect(match.phase == .throwing, "correcting the landing dart reopens the game")
        #expect(match.fact(1, "remaining") == 1)
        match.play("S1")

        #expect(match.phase == .finished)
        #expect(match.snapshot.finishReason == .victory)
        #expect(match.fact(1, "remaining") == 0)
        #expect(match.snapshot.ranks == [2, 1])
        try Support.checkReplay(match)
    }

    // MARK: Fight (GAMES.md §11)

    /// Five lives. The numbers come from the seed and are read from the facts. J1's last hit, read as a single
    /// and corrected to a treble, knocks J2 out.
    @Test func fight_fiveLives_correctedTrebleKnocksOut() throws {
        var match = try Support.match(.fight, ["lives": 5], players: 2, seed: 7)
        let heal1 = try #require(Support.int(match.fact(0, "healNumber")))
        let weak1 = try #require(Support.ints(match.fact(0, "weakNumbers")))
        let heal2 = try #require(Support.int(match.fact(1, "healNumber")))
        let weak2 = try #require(Support.ints(match.fact(1, "weakNumbers")))
        #expect(Set([heal1, heal2] + weak1 + weak2).count == 6)

        Support.dart(.double(weak2[0]), on: &match)
        Support.dart(.single(weak2[1]), on: &match)
        Support.dart(.miss, on: &match)
        #expect(match.fact(1, "lives") == 2)
        #expect(match.endTurn().isAccepted)

        Support.dart(.treble(weak1[0]), on: &match)
        Support.dart(.single(heal2), on: &match)
        Support.dart(.miss, on: &match)
        #expect(match.fact(0, "lives") == 2)
        #expect(match.fact(1, "lives") == 3)
        #expect(match.endTurn().isAccepted)

        Support.dart(.single(heal1), on: &match)
        #expect(match.fact(0, "lives") == 3)
        Support.dart(.single(weak2[0]), needsReview: true, on: &match)
        #expect(match.fact(1, "lives") == 2)
        Support.expectClean(match.replaceDart(at: 1, with: .treble(weak2[0])))

        #expect(match.phase == .finished)
        #expect(match.snapshot.finishReason == .lastPlayerStanding)
        #expect(match.fact(1, "lives") == 0)
        #expect(match.fact(1, "eliminated") == true)
        #expect(match.fact(0, "kills") == 1)
        #expect(match.snapshot.ranks == [1, 2])
        try Support.checkReplay(match)
    }

    // MARK: Conqueror (GAMES.md §12)

    /// J1 takes the bull (King) and attacks J2's home from afar; J2's bull is a phantom, removed; J2 claims a
    /// neighbour of its home; J1 takes the home, and with it every sector of J2.
    @Test func conqueror_theKingTakesTheHome() throws {
        var match = try Support.match(.conqueror, players: 2, seed: 3)
        let home1 = try #require(Support.int(match.fact(0, "homeSector")))
        let home2 = try #require(Support.int(match.fact(1, "homeSector")))
        let neighbour = BoardGeometry.standard.neighbours(of: home2).clockwise

        Support.dart(.outerBull, on: &match)
        #expect(match.gameFact("king") == 0)
        Support.dart(.single(home2), on: &match)
        Support.dart(.treble(home2), on: &match)
        #expect(match.fact(1, "sectors") == .map([home2: 1]))
        #expect(match.endTurn().isAccepted)

        Support.dart(.innerBull, on: &match)
        #expect(match.gameFact("king") == 1)
        Support.expectClean(match.removeDart(at: 0))
        #expect(match.gameFact("king") == 0)
        Support.dart(.single(neighbour), on: &match)
        Support.dart(.miss, on: &match)
        Support.dart(.miss, on: &match)
        #expect(match.fact(1, "sectors") == .map([home2: 1, neighbour: 1]))
        #expect(match.endTurn().isAccepted)

        Support.dart(.double(home2), on: &match)

        #expect(match.phase == .finished)
        #expect(match.snapshot.finishReason == .lastPlayerStanding)
        #expect(match.fact(1, "eliminated") == true)
        #expect(match.fact(0, "sectors") == .map([home1: 3, home2: 1, neighbour: 1]))
        #expect(match.fact(0, "totalLives") == 5)
        #expect(match.fact(0, "sectorCount") == 3)
        #expect(match.snapshot.ranks == [1, 2])
        try Support.checkReplay(match)
    }

    // MARK: Beer Tap (GAMES.md §13)

    /// Pint glasses, two rounds. Both players earn a free glass for a turn of 100 or more; J2's last turn is
    /// short (two darts), its first dart corrected (T5 read, T20 thrown); undoing the final confirmation takes
    /// the free glass back, and confirming again gives it.
    @Test func beerTap_pint_freeGlassesAndAShortLastTurn() throws {
        var match = try Support.match(.beerTap, ["glassSize": 50, "rounds": 2], players: 2)
        match.play("T20, T20, S10 | S20, S20, S5 |")
        #expect(match.fact(0, "poured") == 180)
        #expect(match.fact(0, "glasses") == 3)
        #expect(match.fact(0, "level") == 30)
        #expect(match.fact(0, "bonusGlasses") == 1)
        #expect(match.fact(1, "poured") == 45)

        match.play("MISS ×3 | T5")
        Support.expectClean(match.replaceDart(at: 0, with: .treble(20)))
        match.play("T20 |")
        #expect(match.phase == .finished)
        #expect(match.snapshot.finishReason == .roundLimit)
        #expect(match.fact(1, "poured") == 215)

        #expect(match.undo().applied)
        #expect(match.phase == .throwing)
        #expect(match.fact(1, "poured") == 165, "the free glass comes at the closure of the turn")
        #expect(match.endTurn().isAccepted)

        #expect(match.phase == .finished)
        #expect(match.fact(1, "poured") == 215)
        #expect(match.fact(1, "glasses") == 4)
        #expect(match.fact(1, "level") == 15)
        #expect(match.currentTurn.isEmpty, "a game ended at the round limit has an empty turn")
        #expect(match.snapshot.ranks == [2, 1])
        try Support.checkReplay(match)
    }

    // MARK: Football (GAMES.md §14)

    /// Field of 3, two goals to win. A scores, B equalises; the camera reads A's double bull as a single bull,
    /// and the correction is the winning goal: "Le camp A gagne".
    @Test func football_correctedDoubleBullWins() throws {
        var match = try Support.match(.football, ["fieldLength": 3, "goalsToWin": 2], players: 2)
        match.play("S1, D6, S5 | S5, S5, MISS |")
        #expect(match.gameFact("sideGoals") == [1, 1])
        #expect(match.gameFact("ball") == 0)

        match.play("SB")
        #expect(match.gameFact("ball") == 2)
        Support.expectClean(match.replaceDart(at: 0, with: .innerBull))

        #expect(match.phase == .finished)
        #expect(match.snapshot.finishReason == .victory)
        #expect(match.gameFact("sideGoals") == [2, 1])
        #expect(match.fact(0, "goalsScored") == 2)
        #expect(match.fact(1, "goalsScored") == 1)
        #expect(match.snapshot.ranks == [1, 2])
        #expect(match.snapshot.winnerTitle?.fr == "Le camp A gagne")
        try Support.checkReplay(match)
    }

    // MARK: Radar (GAMES.md §15)

    /// One round, seed 1 (the targets of RAD-1). J1 destroys the small target (150) and hits the first large
    /// one twice (2 × 10); the middle dart was recorded without a position and is corrected by a tap on the
    /// target, which gives the position the game reads.
    @Test func radar_destroyAndDamage_withAPositionGivenByTheCorrection() throws {
        var match = try Support.match(.radar, ["rounds": 1], players: 2, seed: 1)
        let blobs = try #require(Support.table(match.gameFact("blobs")))
        #expect(blobs.count == 5)
        func centre(_ slot: Int) -> BoardPoint { BoardPoint(x: Double(blobs[slot][0]), y: Double(blobs[slot][1])) }
        let geometry = BoardGeometry.standard

        Support.dart(geometry.hit(at: centre(4)), position: centre(4), on: &match)
        #expect(match.fact(0, "points") == 150)
        #expect(match.fact(0, "destroyed") == 1)
        Support.dart(.miss, on: &match)
        #expect(match.fact(0, "points") == 150)
        Support.expectClean(match.replaceDart(at: 1, with: geometry.hit(at: centre(0)), position: centre(0)))
        #expect(match.fact(0, "points") == 160)
        #expect(match.currentTurn[1].position == centre(0))
        Support.dart(geometry.hit(at: centre(0)), position: centre(0), on: &match)
        #expect(match.fact(0, "points") == 170)
        let after = try #require(Support.table(match.gameFact("blobs")))
        #expect(after[0] == [blobs[0][0], blobs[0][1], 40, 1])
        #expect(after[4][2] == 16 && after[4][3] == 1)
        #expect(after[4][0] != blobs[4][0] || after[4][1] != blobs[4][1], "a new small target takes another place")

        match.play("| MISS ×3 |")
        #expect(match.phase == .finished)
        #expect(match.snapshot.finishReason == .roundLimit)
        #expect(match.snapshot.ranks == [1, 2])
        try Support.checkReplay(match)
    }

    // MARK: Golf (GAMES.md §16)

    /// Two holes, the last dart counts. J1: hole in one, then a single (4 strokes). J2: 2, then a third dart read
    /// MISS and corrected to the double of the hole (1): J2 wins with 3 strokes.
    @Test func golf_twoHoles_correctedLastDartWins() throws {
        var match = try Support.match(.golf, ["holes": 2], players: 2)
        let holeInOne = match.play("D1")
        #expect(holeInOne.first?.events.contains(.shotPlayed(player: 0, strokes: 1)) == true)
        #expect(match.phase == .turnComplete, "a double of the hole closes the turn")
        match.play("| S1, T1 | S2 | T2, S5, MISS")
        #expect(match.gameFact("provisional") == 5)
        Support.expectClean(match.replaceDart(at: 2, with: .double(2)))
        #expect(match.gameFact("provisional") == 1)
        #expect(match.endTurn().isAccepted)

        #expect(match.phase == .finished)
        #expect(match.snapshot.finishReason == .roundLimit)
        #expect(match.fact(0, "strokes") == 4)
        #expect(match.fact(0, "holeScores") == [1, 3])
        #expect(match.fact(0, "toPar") == -2)
        #expect(match.fact(1, "strokes") == 3)
        #expect(match.fact(1, "holeScores") == [2, 1])
        #expect(match.fact(1, "toPar") == -3)
        #expect(match.snapshot.ranks == [2, 1])
        try Support.checkReplay(match)
    }

    // MARK: Around the Clock (GAMES.md §6)

    /// Multipliers jump. J1 runs 1 → 18 with trebles; the S19 read for a D19 is corrected and wins on 20.
    @Test func aroundTheClock_multiplierJump_correctedDoubleFinishes() throws {
        var match = try Support.match(.aroundTheClock, ["multiplierJump": true], players: 2)
        match.play("T1, T4, T7 | S1, S2, S3 | T10, T13, T16 | MISS ×3 | S19")
        #expect(match.fact(0, "progress") == 19)
        #expect(match.phase == .throwing)
        Support.expectClean(match.replaceDart(at: 0, with: .double(19)))

        #expect(match.phase == .finished)
        #expect(match.snapshot.finishReason == .victory)
        #expect(match.fact(0, "progress") == 20)
        #expect(match.fact(1, "progress") == 3)
        #expect(match.snapshot.ranks == [1, 2])
        try Support.checkReplay(match)
    }

    // MARK: High Score (GAMES.md §8)

    /// Two rounds. A phantom S5 is removed from J1's second turn; its confirmation is undone and given again.
    @Test func highScore_twoRounds_phantomAndUndoneConfirmation() throws {
        var match = try Support.match(.highScore, ["rounds": 2], players: 2)
        match.play("T20, T20, T20 | DB, SB, S1 |")
        #expect(match.fact(0, "points") == 180)
        #expect(match.fact(1, "points") == 76)

        match.play("S5")
        Support.expectClean(match.removeDart(at: 0))
        match.play("MISS ×3 |")
        #expect(match.snapshot.currentPlayer == 1)
        #expect(match.undo().applied)
        #expect(match.snapshot.currentPlayer == 0)
        #expect(match.phase == .turnComplete)
        #expect(match.endTurn().isAccepted)
        match.play("T20, T20, T19 |")

        #expect(match.phase == .finished)
        #expect(match.snapshot.finishReason == .roundLimit)
        #expect(match.fact(0, "points") == 180)
        #expect(match.fact(1, "points") == 253)
        #expect(match.snapshot.ranks == [2, 1])
        try Support.checkReplay(match)
    }

    // MARK: Halve-It (GAMES.md §9)

    /// The default targets 20, 16, D7, 14, T10, BULL. Missed targets halve the score, rounded up; a short turn
    /// without a hit halves too. J2's last dart, read S20, is corrected to the bull.
    @Test func halveIt_defaultTargets_halvingAndACorrectedBull() throws {
        var match = try Support.match(.halveIt, players: 2)
        match.play("S20, T20, MISS | S5 |")
        #expect(match.fact(0, "points") == 80)
        #expect(match.fact(1, "points") == 0)
        match.play("MISS ×3 | S16, D16, T16 |")
        #expect(match.fact(0, "points") == 40)
        #expect(match.fact(1, "points") == 96)
        match.play("D7, MISS, MISS | MISS ×3 |")
        #expect(match.fact(0, "points") == 54)
        #expect(match.fact(1, "points") == 48)
        match.play("S14 | T14 | MISS ×3 | T10 |")
        #expect(match.fact(0, "points") == 34)
        #expect(match.fact(1, "points") == 120)
        match.play("DB | S20")
        #expect(match.fact(0, "points") == 84)
        Support.expectClean(match.replaceDart(at: 0, with: .outerBull))
        #expect(match.endTurn().isAccepted)

        #expect(match.phase == .finished)
        #expect(match.snapshot.finishReason == .roundLimit)
        #expect(match.fact(1, "points") == 145)
        #expect(match.snapshot.ranks == [2, 1])
        try Support.checkReplay(match)
    }

    // MARK: Coverage

    /// Each id of the registry has its whole game in this suite.
    @Test func everyGameOfTheRegistry_hasAWholeGameHere() {
        let covered: Set<GameID> = [
            .x01, .cricket, .killer, .shanghai, .moonLanding, .fight, .conqueror,
            .beerTap, .football, .radar, .golf, .aroundTheClock, .highScore, .halveIt,
        ]
        #expect(Set(GameRegistry.standard.definitions.map(\.id)) == covered)
    }
}
