import SwiftUI
import DartCore
import DartGames

/// Data of the game-flow snapshots (ARCHITECTURE.md §8.11). Every game is played by its real engine, with fixed
/// seeds, fixed dart ids and a fixed start date, so that two runs draw the same pictures. The Killer seed gives
/// the zones of the mock-up `PlayKiller` (Léa 17 · 3 · 19, Tom 20 · 1 · 18, Inès 6 · 10 · 15, Marc 8 · 11 · 14).
enum GameFlowFixtures {
    static let names = ["Léa", "Tom", "Inès", "Marc", "Hugo", "Zoé", "Sam"]

    static func players(_ count: Int) -> [Player] {
        (0..<count).map { Player(id: id(1_000 + $0), name: names[$0 % names.count]) }
    }

    /// Seed of the Killer fixtures: `ringLayout` gives the zones of the mock-up for four players in Facile.
    static let killerSeed: UInt64 = 3438
    static let startDate = Date(timeIntervalSinceReferenceDate: 0)

    static func id(_ n: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", n)) ?? UUID()
    }

    /// A game of the registry, or nil when its rules refuse the options (never for these fixtures).
    static func match(_ game: GameID, _ options: GameOptions = [:], players count: Int, seed: UInt64 = 1) -> GameMatch? {
        guard let definition = GameRegistry.standard.definition(for: game) else { return nil }
        let configuration = GameConfiguration(gameID: game, options: options, players: players(count), seed: seed)
        return try? GameMatch(definition: definition, configuration: configuration, startedAt: startDate)
    }

    /// Plays a script of GAMES.md §2.11 ("," between darts, "|" for the next player, "×3" to repeat), with fixed
    /// ids from `firstID` on.
    static func play(_ script: String, on match: inout GameMatch, firstID: Int = 1, origin: DartOrigin = .manual) {
        var next = firstID
        let turns = script.components(separatedBy: "|")
        for (index, turn) in turns.enumerated() {
            for token in turn.components(separatedBy: ",") {
                let text = token.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { continue }
                let parts = text.components(separatedBy: "×")
                let times = parts.count > 1 ? Int(parts[1].trimmingCharacters(in: .whitespaces)) ?? 1 : 1
                guard let hit = Hit(notation: parts[0].trimmingCharacters(in: .whitespaces)) else { continue }
                for _ in 0..<times {
                    match.throwDart(DartRecord(id: id(next), hit: hit, origin: origin))
                    next += 1
                }
            }
            if index < turns.count - 1 { match.endTurn() }
        }
    }

    /// The content model of a match as the play screen would show it.
    static func model(_ match: GameMatch, status: InputStatus = .manualOnly, pending: [Hit] = [],
                      prompt: PlayPrompt? = nil) -> PlayContentModel {
        let descriptor = match.definition.descriptor
        return PlayContentModel(snapshot: match.snapshot, players: match.players, playStyle: descriptor.playStyle,
                                boardGeometry: descriptor.boardGeometry, records: match.currentTurn,
                                pending: pending, inputStatus: status, prompt: prompt,
                                canEndTurn: pending.isEmpty && match.phase != .finished, canUndo: match.canUndo)
    }

    // MARK: Games

    /// Killer Facile, four players, round 4: Léa (Killer, 3 lives) has thrown S20 (Tom −1) and T6 (Inès −1,
    /// "à vérifier"); Tom is arming (2 of 3, 2 lives), Inès is a Killer with 1 life, Marc arming (1 of 3).
    static func killerInRound4() -> GameMatch? {
        guard var match = match(.killer, ["level": "easy"], players: 4, seed: killerSeed) else { return nil }
        play("""
             S17, S3, S19 | S20, S1, MISS | S6, S10, S15 | S8, MISS, MISS |
             S6, MISS, MISS | MISS ×3 | MISS ×3 | MISS ×3 |
             MISS ×3 | MISS ×3 | MISS ×3 | MISS ×3 |
             """, on: &match)
        match.throwDart(DartRecord(id: id(901), hit: .single(20), position: BoardPoint(radius: 134.5, clockwiseDegrees: 0),
                                   origin: .camera))
        match.throwDart(DartRecord(id: id(902), hit: .treble(6), position: BoardPoint(radius: 103, clockwiseDegrees: 90),
                                   origin: .camera, needsReview: true))
        return match
    }

    /// 501 double out, three players, round 6: Tom has 24 left after T20 and T19.
    static func x01InRound6() -> GameMatch? {
        guard var match = match(.x01, ["startScore": 501, "outRule": "double"], players: 3) else { return nil }
        play("""
             T20, S20, S20 | T20, S20, S5 | S20, S20, S20 |
             S20, S20, S1 | S20, S20, S20 | S15, S15, S15 |
             S15, S15, S15 | T20, S20, S20 | T20, MISS, MISS |
             S18, S18, S2 | T20, MISS, MISS | S16, S16, S16 |
             S15, S15, S15 | S20, S20, S15 | S20, S5, S1 |
             S5, S20, S20 |
             """, on: &match)
        match.throwDart(DartRecord(id: id(901), hit: .treble(20), position: BoardPoint(radius: 103.5, clockwiseDegrees: 1),
                                   origin: .camera))
        match.throwDart(DartRecord(id: id(902), hit: .treble(19), position: BoardPoint(radius: 104, clockwiseDegrees: 197),
                                   origin: .camera))
        return match
    }

    /// Cricket, three players, the grid partly closed.
    static func cricketInRound3() -> GameMatch? {
        guard var match = match(.cricket, players: 3) else { return nil }
        play("""
             T20, S19, S19 | T20, MISS, S18 | S17, S17, S17 |
             S20, T19, S16 | S15, D18, MISS | SB, S20, MISS |
             S20
             """, on: &match)
        return match
    }

    /// High Score, three players, round 3.
    static func highScoreInRound3() -> GameMatch? {
        guard var match = match(.highScore, players: 3) else { return nil }
        play("""
             T20, S20, S5 | S19, S19, T19 | S1, S20, S5 |
             T20, T20, S1 | S12, S5, S20 | D16, S8, MISS |
             S20, T5
             """, on: &match)
        return match
    }

    /// Beer Tap, two players, glass of 50 cl: J1 has 3 full glasses and a glass at 40 (130 points and a free
    /// glass in round 1, then S10).
    static func beerTapInRound2() -> GameMatch? {
        guard var match = match(.beerTap, ["glassSize": 50], players: 2) else { return nil }
        play("T20, T20, S10 | S20, S20, S5 | S10", on: &match)
        return match
    }

    /// Football, four players: side A to throw, "A 2 – 1 B", the ball on +1.
    static func footballInRound2() -> GameMatch? {
        guard var match = match(.football, players: 4) else { return nil }
        play("DB | DB | DB | MISS ×3 | S6", on: &match)
        return match
    }

    /// Radar, two players, the five targets of RAD-1 (seed 1); J1 has damaged the first one and missed.
    static func radarInRound1() -> GameMatch? {
        guard var match = match(.radar, players: 2, seed: 1) else { return nil }
        for (offset, point) in [BoardPoint(x: -80, y: 95), BoardPoint(x: 0, y: -150)].enumerated() {
            match.throwDart(DartRecord(id: id(901 + offset), hit: BoardGeometry.standard.hit(at: point), position: point))
        }
        return match
    }

    /// Golf, two players, hole 4 of 9: J1 at −2 (2, 2, 3), J2 at +3 (5, 5, 2); J1 has thrown S4.
    static func golfOnHole4() -> GameMatch? {
        guard var match = match(.golf, players: 2) else { return nil }
        play("T1 | S5, S5, S5 | T2 | MISS, MISS, MISS | S3 | T3 | S4", on: &match)
        return match
    }

    // MARK: The six other games (lot I1)

    /// Shanghai, three players, round 4 (number 4): Léa has thrown S4 and T4.
    static func shanghaiInRound4() -> GameMatch? {
        guard var match = match(.shanghai, players: 3) else { return nil }
        play("""
             S1, D1, MISS | T1, MISS, MISS | S1, S1, S1 |
             S2, S2, MISS | D2, D2, S5 | T2, MISS, MISS |
             T3, S3, MISS | S3, MISS, MISS | D3, MISS, S3 |
             S4, T4
             """, on: &match)
        return match
    }

    /// Moon Landing (Débutant, 200), three players, round 3: Léa has thrown S20.
    static func moonLandingInRound3() -> GameMatch? {
        guard var match = match(.moonLanding, players: 3) else { return nil }
        play("""
             T20, S20, S5 | S19, S7, T19 | S1, S5, S20 |
             S20, S20, S5 | T20, MISS, S12 | D20, S18, S1 |
             S20
             """, on: &match)
        return match
    }

    /// Fight, three players, nine lives, round 2: Léa heals on her number after a round of blows. The numbers
    /// come from the seed, so the script reads them from the facts.
    static func fightInRound2() -> GameMatch? {
        guard var match = match(.fight, players: 3, seed: 7) else { return nil }
        func number(_ player: Int, _ name: String) -> [Int] {
            switch match.snapshot.players[player].facts[name] {
            case .int(let value)?: return [value]
            case .ints(let values)?: return values
            default: return [1, 1]
            }
        }
        let heal = (0..<3).map { number($0, "healNumber")[0] }
        let weak = (0..<3).map { number($0, "weakNumbers") }
        play("""
             D\(weak[1][0]), S\(weak[2][1]), MISS | T\(weak[0][0]), S\(heal[1]), MISS | S\(weak[1][1]), S\(weak[0][1]), MISS |
             S\(heal[0])
             """, on: &match)
        return match
    }

    /// Conqueror, four players, round 2: every player has grown from its home; Tom took the bull, then Léa took
    /// it back and attacks Tom's home. The homes come from the seed, so the script reads them from the facts.
    static func conquerorInRound2() -> GameMatch? {
        guard var match = match(.conqueror, players: 4, seed: 3) else { return nil }
        let homes = (0..<4).map { player -> Int in
            if case .int(let home)? = match.snapshot.players[player].facts["homeSector"] { return home }
            return 1
        }
        let next = homes.map { BoardGeometry.standard.neighbours(of: $0).clockwise }
        let previous = homes.map { BoardGeometry.standard.neighbours(of: $0).anticlockwise }
        play("""
             S\(next[0]), S\(next[0]), MISS | S\(next[1]), SB, MISS | S\(next[2]), S\(previous[2]), MISS | S\(previous[3]), MISS, MISS |
             DB, S\(homes[1])
             """, on: &match)
        return match
    }

    /// Around the Clock, three players, round 3: Léa is on the 6 after S6.
    static func aroundTheClockInRound3() -> GameMatch? {
        guard var match = match(.aroundTheClock, players: 3) else { return nil }
        play("""
             S1, S2, MISS | S1, MISS, MISS | S1, S2, S3 |
             S3, S4, S5 | S2, S3, MISS | S4, MISS, S5 |
             S6
             """, on: &match)
        return match
    }

    /// Halve-It, three players, default targets, round 3 (D7): Léa has hit D7; Tom was halved in round 1.
    static func halveItInRound3() -> GameMatch? {
        guard var match = match(.halveIt, players: 3) else { return nil }
        play("""
             S20, T20, MISS | MISS, MISS, MISS | S20, S20, S20 |
             S16, MISS, MISS | D16, MISS, MISS | MISS, MISS, MISS |
             D7
             """, on: &match)
        return match
    }

    /// Killer Facile at four, finished in round 3: Léa wins with 2 lives, then Inès, Tom and Marc.
    static func killerFinished() -> GameMatch? {
        guard var match = match(.killer, ["level": "easy"], players: 4, seed: killerSeed) else { return nil }
        play("""
             S17, S3, S19 | S20, S1, S18 | S6, S10, S15 | S8, S11, MISS |
             S8, S8, S8 | S6, S6, MISS | S17, S20, S20 |
             S20, S6
             """, on: &match)
        return match
    }

    /// Football at four, won by side A on a double bull.
    static func footballFinished() -> GameMatch? {
        guard var match = footballInRound2() else { return nil }
        play("DB", on: &match, firstID: 500)
        return match
    }

    /// The correction sheet of the mock-up: the second dart, T19 "à vérifier", six hits offered.
    static var correction: PlayCorrectionModel {
        PlayCorrectionModel(index: 1, isPending: false, needsReview: true, detected: .treble(19),
                            choices: PlayCorrectionChoices.around(.treble(19)), choice: nil,
                            tip: BoardPoint(radius: 100, clockwiseDegrees: 203), dartID: id(902), evidence: nil,
                            boardGeometry: .display)
    }

    // MARK: Screens other than the game

    static var home: HomeContentModel {
        HomeContentModel(descriptors: GameRegistry.standard.descriptors, camera: .ready(.good), inputMode: .camera,
                         scanMode: .live, resume: nil)
    }

    static func setup(_ game: GameID, players count: Int, options: GameOptions = [:]) -> SetupState? {
        guard let descriptor = GameRegistry.standard.definition(for: game)?.descriptor else { return nil }
        let roster = players(count)
        return SetupState(descriptor: descriptor, roster: roster,
                          memory: SetupMemory(playerIDs: roster.map(\.id), options: options))
    }
}
