import Foundation
import Testing
import DartCore
import DartGames
import DartTestSupport

/// The owner's favourite game, played to the end at its four levels and at every number of players the level
/// allows (GAMES.md §5): 2 to 6 in Facile, 2 to 8 in the three others. 26 whole games.
///
/// Each player follows a simple plan read from the facts, as a real player reads the board: arm on its own zone
/// until Killer, then aim at the zone of the next living opponent. A fixed-seed random stream decides, dart by
/// dart, a miss (one in four), a dart the camera read wrong and that is corrected (`replaceDart`), or a phantom
/// that is removed (`removeDart`) before the real dart. After every dart, the facts are compared with what
/// GAMES.md §5.4 says the dart does; at the end, the ranking with §5.6 and the journal with the replay checks.
@Suite struct IntegrationKillerTests {
    private typealias Support = IntegrationSupport

    /// The facts of one player that §5.4 changes.
    private struct State: Equatable, CustomStringConvertible {
        var zone: [Int]
        var lives: Int
        var armingProgress: Int
        var kills: Int
        var isKiller: Bool
        var eliminated: Bool

        var description: String {
            "zone \(zone) lives \(lives) arming \(armingProgress) kills \(kills)\(isKiller ? " killer" : "")\(eliminated ? " out" : "")"
        }
    }

    private static func state(_ match: GameMatch, _ player: Int) throws -> State {
        State(zone: try #require(Support.ints(match.fact(player, "zone"))),
              lives: try #require(Support.int(match.fact(player, "lives"))),
              armingProgress: try #require(Support.int(match.fact(player, "armingProgress"))),
              kills: try #require(Support.int(match.fact(player, "kills"))),
              isKiller: try #require(Support.bool(match.fact(player, "isKiller")) as Bool?),
              eliminated: try #require(Support.bool(match.fact(player, "eliminated")) as Bool?))
    }

    /// What GAMES.md §5.4 does to `states` when `player` throws `hit` (no self-hit penalty).
    private static func expected(after hit: Hit, by player: Int, from states: [State], armingHits: Int) -> [State] {
        var next = states
        guard let number = hit.number, !hit.isBull else { return next }
        guard let owner = states.indices.first(where: { !states[$0].eliminated && states[$0].zone.contains(number) }) else {
            return next
        }
        if owner == player {
            if !states[player].isKiller {
                next[player].armingProgress += 1
                next[player].isKiller = next[player].armingProgress == armingHits
            }
        } else if states[player].isKiller {
            next[owner].lives -= 1
            if next[owner].lives == 0 {
                next[owner].eliminated = true
                next[player].kills += 1
            }
        }
        return next
    }

    private static func randomBed(_ number: Int, _ random: inout SeededRandom) -> Hit {
        switch random.nextInt(below: 3) {
        case 0: return .single(number)
        case 1: return .double(number)
        default: return .treble(number)
        }
    }

    /// Plays one whole game and checks it; returns the number of darts thrown.
    @discardableResult
    private static func playWholeGame(level: String, players count: Int, seed: UInt64) throws -> Int {
        let width = ["easy": 3, "medium": 2, "hard": 1, "expert": 1][level] ?? 0
        var match = try Support.match(.killer, ["level": .string(level)], players: count, seed: seed)
        let armingHits = 3
        var random = SeededRandom(seed: seed &* 0x9E37_79B9_7F4A_7C15)
        var eliminationOrder: [Int] = []
        var lastZone: [Int: [Int]] = [:]
        var darts = 0
        var turns = 0
        let label = "\(level) at \(count), seed \(seed)"

        while match.phase != .finished {
            turns += 1
            try #require(turns < 400, "\(label): the game does not end")
            let player = match.snapshot.currentPlayer
            var states = try (0..<count).map { try state(match, $0) }
            #expect(!states[player].eliminated, "\(label): an eliminated player plays")
            #expect(states[player].zone.count == width, "\(label)")
            // A number never belongs to two living players (GAMES.md §5.3).
            let living = states.indices.filter { !states[$0].eliminated }.flatMap { states[$0].zone }
            #expect(Set(living).count == living.count, "\(label): a shared number")
            if level == "expert" {
                if let previous = lastZone[player] { #expect(previous != states[player].zone, "\(label): no new number") }
                lastZone[player] = states[player].zone
            } else if let previous = lastZone[player] {
                #expect(previous == states[player].zone, "\(label): a fixed zone moved")
            } else {
                lastZone[player] = states[player].zone
            }

            while match.phase == .throwing {
                let me = states[player]
                let intended: Hit
                if random.nextInt(below: 4) == 0 {
                    intended = .miss
                } else if !me.isKiller {
                    intended = randomBed(me.zone[random.nextInt(below: me.zone.count)], &random)
                } else {
                    let victim = (1..<count).map { (player + $0) % count }.first { !states[$0].eliminated } ?? player
                    let zone = states[victim].zone
                    intended = randomBed(zone[random.nextInt(below: zone.count)], &random)
                }
                let index = match.currentTurn.count
                switch random.nextInt(below: 10) {
                case 0:
                    // Read wrong by the camera, then corrected by the player.
                    Support.dart(Hit.all[random.nextInt(below: Hit.all.count)], needsReview: true, on: &match)
                    Support.expectClean(match.replaceDart(at: index, with: intended))
                    #expect(match.currentTurn[index].hit == intended && !match.currentTurn[index].needsReview)
                case 1:
                    // A phantom, removed, then the real dart.
                    Support.dart(Hit.all[random.nextInt(below: Hit.all.count)], on: &match)
                    Support.expectClean(match.removeDart(at: index))
                    #expect(match.currentTurn.count == index)
                    Support.dart(intended, on: &match)
                default:
                    Support.dart(intended, on: &match)
                }
                darts += 1
                let model = expected(after: intended, by: player, from: states, armingHits: armingHits)
                let after = try (0..<count).map { try state(match, $0) }
                #expect(after == model, "\(label): \(intended.notation) by J\(player + 1)")
                for victim in after.indices where after[victim].eliminated && !states[victim].eliminated {
                    eliminationOrder.append(victim)
                }
                states = after
            }
            if match.phase == .turnComplete {
                #expect(match.endTurn().isAccepted)
            }
        }

        #expect(match.snapshot.finishReason == .lastPlayerStanding, "\(label)")
        #expect(eliminationOrder.count == count - 1, "\(label)")
        let winner = try #require((0..<count).first { !eliminationOrder.contains($0) })
        let ranks = match.snapshot.ranks
        #expect(ranks[winner] == 1, "\(label)")
        #expect(match.snapshot.winners == [winner], "\(label)")
        // Eliminated players come after the living, in reverse order of elimination (GAMES.md §2.7).
        for (offset, player) in eliminationOrder.reversed().enumerated() {
            #expect(ranks[player] == offset + 2, "\(label): rank of J\(player + 1)")
        }
        #expect(match.snapshot.highlights.isEmpty, "\(label): highlights are cleared at the end")
        try Support.checkReplay(match)
        return darts
    }

    @Test(arguments: ["easy", "medium", "hard", "expert"])
    func everyLevel_wholeGames_fromTwoPlayersToTheLevelMaximum(level: String) throws {
        let maximum = level == "easy" ? 6 : 8
        var darts = 0
        for count in 2...maximum {
            darts += try Self.playWholeGame(level: level, players: count, seed: UInt64(1_000 * count + level.count))
        }
        print("Integration Killer \(level): \(maximum - 1) whole games, \(darts) darts")
    }

    /// Facile shares 3 numbers per player out of 20: 7 or 8 players are refused, never silently changed
    /// (GAMES.md §5.2).
    @Test func easy_atSevenOrEightPlayers_isRefused() throws {
        for count in [7, 8] {
            #expect(throws: GameConfigurationError.self) {
                try Support.match(.killer, ["level": "easy"], players: count)
            }
            #expect(try Support.match(.killer, ["level": "medium"], players: count).phase == .throwing)
        }
    }

    /// The round limit ranks the living by lives, then kills, then arming (GAMES.md §5.6), at the confirmation of
    /// the last turn of the last round.
    @Test func roundLimit_ranksTheLiving_byLivesKillsAndArming() throws {
        var match = try Support.match(.killer, ["level": "hard", "maxRounds": 2, "armingHits": 2], players: 3, seed: 11)
        let zones = try (0..<3).map { try #require(Support.ints(match.fact($0, "zone"))?.first) }
        // Round 1: J1 arms and takes one life from J2; J2 arms once; J3 misses.
        Support.dart(.single(zones[0]), on: &match)
        Support.dart(.single(zones[0]), on: &match)
        Support.dart(.single(zones[1]), on: &match)
        #expect(match.endTurn().isAccepted)
        Support.dart(.single(zones[1]), on: &match)
        match.play("MISS, MISS | MISS ×3 |")
        // Round 2: nobody scores.
        match.play("MISS ×3 | MISS ×3 | MISS ×3")
        #expect(match.phase == .turnComplete, "the limit is decided at the confirmation")
        #expect(match.endTurn().isAccepted)

        #expect(match.phase == .finished)
        #expect(match.snapshot.finishReason == .roundLimit)
        // J1 3 lives; J3 3 lives, no kill, no arming; J2 2 lives.
        #expect(match.snapshot.ranks == [1, 3, 2])
        try Support.checkReplay(match)
    }
}
