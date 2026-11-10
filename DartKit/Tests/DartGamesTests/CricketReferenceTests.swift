import Testing
import DartCore
import DartGames
import DartTestSupport

/// Cricket against the reference implementation that computed the vectors of GAMES.md (§2.11): sixty random
/// games (both scorings, normal and light targets with several seeds, with and without a round limit, one to
/// four players) played by that reference, with the state it reached. The games were generated once with a
/// fixed seed; the script of a line is the journal, in the notation of the vectors.
///
/// A line is `scoring,targets,maxRounds ; players ; seed ; journal ; expected state`. In `marks` the players
/// are separated by "/", and the marks of a player follow the order of `targets` (the bull is written 25).
@Suite struct CricketReferenceTests {
    @Test(arguments: CricketReferenceTests.games)
    func theGameReachesTheStateOfTheReference(_ line: String) throws {
        let (options, players, seed, script, expected) = try Self.parts(line)
        try #require(options.count == 3)
        let maxRounds: OptionValue = options[2] == "nil" ? .null : .int(try #require(Int(options[2])))
        var match = try GameRegistry.standard.match(
            .cricket, ["scoring": .string(options[0]), "targets": .string(options[1]), "maxRounds": maxRounds],
            players: players, seed: seed)
        let targets = Self.numbers(expected["targets"])
        // The drawn targets, before the first dart.
        #expect(match.gameFact("targets") == .ints(targets), "\(line)")
        let outcomes = match.play(script)
        // The reference only writes the inputs it accepts.
        let allAccepted = outcomes.allSatisfy { $0.isAccepted }
        #expect(allAccepted, "\(line)")
        Self.expectCommon(match, expected, line)
        let rows = match.snapshot.players.indices
        #expect(rows.map { match.fact($0, "points") } == Self.numbers(expected["points"]).map { .int($0) }, "\(line)")
        let marks = (expected["marks"] ?? "").split(separator: "/").map { Self.numbers(String($0)) }
        try #require(marks.count == players)
        for player in rows {
            let byTarget = Dictionary(uniqueKeysWithValues: zip(targets, marks[player]))
            #expect(match.fact(player, "marks") == .map(byTarget), "player \(player) of \(line)")
            #expect(match.fact(player, "closedCount") == .int(marks[player].filter { $0 == 3 }.count), "\(line)")
        }
    }

    /// The sample covers the three ways a game can stand: won, ended at the round limit, still running.
    @Test func theSampleCoversEveryEnding() {
        let reasons = Set(Self.games.compactMap { $0.components(separatedBy: " ; ").last.flatMap { Self.fields($0)["reason"] } })
        #expect(reasons == ["victory", "roundLimit", "-"] && Self.games.count == 60)
        #expect(Self.games.contains { $0.hasPrefix("cutThroat,light") } && Self.games.contains { $0.hasPrefix("standard,light") })
    }

    /// "key=value key=value" of a case line.
    private static func fields(_ text: String) -> [String: String] {
        var result: [String: String] = [:]
        for pair in text.split(separator: " ") {
            let parts = pair.split(separator: "=", maxSplits: 1).map(String.init)
            if parts.count == 2 { result[parts[0]] = parts[1] }
        }
        return result
    }

    private static func numbers(_ text: String?) -> [Int] {
        (text ?? "").split(separator: ",").compactMap { Int($0) }
    }

    /// The four parts of a case line after the options: players, seed, script, expected values.
    private static func parts(_ line: String) throws -> (options: [String], players: Int, seed: UInt64, script: String, expected: [String: String]) {
        let parts = line.components(separatedBy: " ; ")
        try #require(parts.count == 5, "malformed case: \(line)")
        let players = try #require(Int(parts[1]))
        let seed = try #require(UInt64(parts[2]))
        return (parts[0].components(separatedBy: ","), players, seed, parts[3], fields(parts[4]))
    }

    /// Phase, current player, round, finish reason and ranks: the fields every game shares.
    private static func expectCommon(_ match: GameMatch, _ expected: [String: String], _ line: String) {
        #expect(match.phase.rawValue == expected["phase"], "\(line)")
        #expect(String(match.snapshot.currentPlayer) == expected["current"], "\(line)")
        #expect(String(match.snapshot.round) == expected["round"], "\(line)")
        #expect((match.snapshot.finishReason?.rawValue ?? "-") == expected["reason"], "\(line)")
        #expect(match.snapshot.ranks == numbers(expected["ranks"]), "\(line)")
    }

    static let games: [String] = [
        "standard,light,nil ; 4 ; 1798726085184616171 ; S15, S16, D17 | S15 | D18 | S18, T17 | D20, D15, D20 | S20 | T20, T15, S17 | S17, S9, D18 | S20, T18, T17 ; phase=finished current=0 round=3 reason=victory ranks=1,4,3,2 targets=20,18,17,15 points=74,0,0,17 marks=3,3,3,3/1,0,0,1/3,2,1,3/0,3,3,0",
        "cutThroat,light,20 ; 1 ; 42 ; D15 | T19, S17 | T17, T19, D19 | S15, S5, D18 | T18 ; phase=finished current=0 round=5 reason=victory ranks=1 targets=19,18,17,15 points=0 marks=3,3,3,3",
        "cutThroat,normal,nil ; 4 ; 7934842359764217282 ; D6, D17, T12 | T6, S17, SB | T18, S19, T18 | S14, D17, S16 | D17, D16, S19 |  | D17, DB, T17 |  | D15, S20, S19 | D18, D17, S17 | T15, D11, SB | D20, S20, T2 | T16, D15, S19 | T20, S17, T18 | T16, T15, D19 | D20, T15, T19 | D6, SB, D17 | SB, T19, DB | S2, D18, S19 | S20, T20, D5 |  | D16, D9, D10 | D18, S15, D18 | DB, S17, S15 | T15, S4, S17 | D20, S17, T20 | T15, S19, T9 | DB, T19, T19 | T18, D20, S17 | D20, S18, D17 | D15, S16 | S17, D18, DB | DB, T15, S20 | D17 ; phase=throwing current=1 round=9 reason=- ranks=4,2,1,3 targets=20,19,18,17,16,15,25 points=518,408,329,468 marks=3,3,3,3,3,3,3/3,3,3,3,2,0,3/0,3,3,3,3,3,3/3,3,2,3,1,3,3",
        "cutThroat,normal,17 ; 4 ; 1 ; T19, S16, SB | D17, D8, T18 | D17, D19, D16 | D20, T15, SB | DB, T1, D18 | T17, S19, S17 | DB, D20, S18 | DB, T18, T20 | T15, S11, D15 | T17, DB | S9, S19, S19 | D18, S18, T18 | T20, S15, T20 | D15, D20, D20 |  |  | D15, T7, T18 | S15, D19, DB |  | SB, T18, D16 | S17, T19, D17 | SB, T18, D18 |  | D18, S19, S15 | D15, SB, S17 | DB, SB, S19 | D20, D18, D20 | T20, D19, D18 | D18, S2, T17 | T18, D19, D16 | D17, S17, T16 | S17, D2 ; phase=throwing current=3 round=8 reason=- ranks=2,1,4,3 targets=20,19,18,17,16,15,25 points=282,226,909,331 marks=3,3,3,3,1,3,3/3,3,3,3,2,3,3/3,3,3,3,3,0,2/3,3,3,1,2,3,3",
        "standard,normal,30 ; 3 ; 1 ; D17, S20 | SB, SB, D17 | S15, S18, S16 | S16, S15, SB | T16, D20 | T11, T18 | D15, S19, S16 |  | S9, T18, DB | D17, T19 | D16, S15, D19 | S16 | D17, T20, SB | T20, D9 | T18, D16, T19 | S4, S16, D20 | T15, S17, D17 | T15, S19, T16 | DB, S15, D15 | SB, S18, D16 | D17 | SB | SB, D18, DB | D16, S16 | D15, T12, T17 | D15, S18, T14 | D20 | D17, D16, SB | SB, S17, D17 |  | T15, T17, S19 |  | S17, T17, D20 | T20 | ; phase=throwing current=1 round=12 reason=- ranks=1,2,3 targets=20,19,18,17,16,15,25 points=360,290,161 marks=3,3,0,3,3,3,3/3,2,3,3,3,3,3/3,3,3,3,3,3,2",
        "cutThroat,normal,20 ; 1 ; 1 ; D18, S19, D16 | D15, T17, SB | D18, SB, D19 | T18, D15, D20 | ; phase=throwing current=0 round=5 reason=- ranks=1 targets=20,19,18,17,16,15,25 points=0 marks=2,3,3,3,2,3,2",
        "cutThroat,light,20 ; 4 ; 5759663329681139982 ; T15, T20, S15 | S15, S20, T20 | D15, S19, S17 | S15, T19, T19 | T14, T17, T19 | T19, D17, T15 |  | S17, S15, D20 | S19, T20 ; phase=finished current=0 round=3 reason=victory ranks=1,2,4,3 targets=20,19,17,15 points=57,72,186,110 marks=3,3,3,3/3,3,2,3/0,1,1,2/2,3,1,2",
        "cutThroat,light,10 ; 2 ; 3103896387990931161 ; S20, S15 | S19 | S15, T20, D18 | S15, S19, D15 | T19, S15, T18 ; phase=finished current=0 round=3 reason=victory ranks=1,2 targets=20,19,18,15 points=0,56 marks=3,3,3,3/0,2,0,3",
        "standard,normal,20 ; 4 ; 0 ; S20, D12, S13 | T19, DB, T16 | D18, T20, S18 | D13, D15, T18 | T16, S15, S19 | S18, S17, SB | T15 | T17, D15, S13 | D19, T17, D15 | D18, T20, S15 | T20, D20 | D19, D15, S17 | S16, DB, S5 | T18, S2, S15 | T17, S16, T7 | SB, S16, SB | D18, T7, DB | S6, T19, T15 | S20, D15, T20 | T15 | SB, S16 | D16, T19, D16 | S4, T16, D17 | S8, S17, S19 | S18, S15, S18 | DB, D16, S20 | S19, T3, D6 | D10, S20, DB | SB, T15, S18 | D5, T3, S19 | D18, D16 ; phase=throwing current=2 round=8 reason=- ranks=3,1,2,4 targets=20,19,18,17,16,15,25 points=107,353,262,104 marks=1,3,3,3,3,3,3/3,3,3,1,3,3,3/3,1,3,3,3,3,0/1,3,3,3,1,3,3",
        "cutThroat,normal,2 ; 3 ; 1 ; D15, T20, D9 | T15, S16, T16 | S18, S19 | S19, D17, D19 | S18, T15, D15 | T9, S20, S19 | ; phase=finished current=2 round=2 reason=roundLimit ranks=2,1,3 targets=20,19,18,17,16,15,25 points=91,0,91 marks=3,3,0,2,0,2,0/0,0,1,0,3,3,0/1,2,1,0,0,0,0",
        "standard,normal,22 ; 3 ; 42 ; S17, S20, DB | D20, T16, D18 | S19, T20, T18 | S13, S18, T16 | SB, S17, S15 | D6, D19, S18 | T20, S20, T3 | T20, S16, T20 | S18, T19, D2 |  | SB, S15, S20 | DB, S19, T18 | S18, S3, DB | T19, T16, S19 | T20, T20, DB | D16 | S16, T14, D1 | S6, S18, SB | D1, D20, DB | T20, S16, S20 | D5, S20, D7 |  | D17, T15, S20 | D15, D18, T19 | D3, T11, S15 |  | DB, D16, T19 |  | S15, T20, T3 | ; phase=throwing current=2 round=10 reason=- ranks=3,2,1 targets=20,19,18,17,16,15,25 points=147,160,434 marks=3,0,2,1,3,1,3/3,3,2,3,3,3,2/3,3,3,0,2,2,3",
        "cutThroat,normal,3 ; 2 ; 1 ; S17, SB, S17 | S20, T20, D17 | D17, T19 | S16, D18, D15 | S15 | T19, D19, D17 | ; phase=finished current=1 round=3 reason=roundLimit ranks=2,1 targets=20,19,18,17,16,15,25 points=20,17 marks=0,3,0,3,0,1,1/3,3,2,3,1,2,0",
        "cutThroat,light,20 ; 4 ; 1 ; T15, S15, D17 | D9, D2 | S18 | T18, T18, T17 | T18, T16, D17 | D16, T15, S15 | T16, D17, T15 | D17, S15, S1 | D15 ; phase=finished current=0 round=3 reason=victory ranks=1,3,4,2 targets=18,17,16,15 points=54,120,135,60 marks=3,3,3,3/0,0,2,3/1,2,3,3/3,3,0,1",
        "standard,normal,20 ; 4 ; 1 ; T16, T17, D19 | T17, DB, T1 | T19, T20, S17 | D8, D20, D20 | T17 | S19 |  | S19, T16, D18 | D19, T15 ; phase=throwing current=0 round=3 reason=- ranks=1,4,3,2 targets=20,19,18,17,16,15,25 points=70,0,0,20 marks=0,3,0,3,3,3,0/0,1,0,3,0,0,2/3,3,0,1,0,0,0/3,1,2,0,3,0,0",
        "cutThroat,normal,nil ; 1 ; 0 ; D18 |  | S17, D17, DB | D18, T15, SB | S1, SB, S16 | S7, D17, D20 | T20, S6, D15 | DB, T20, S19 | S12, DB, S19 | T16, SB, S20 | D12, S17, DB | S19 ; phase=finished current=0 round=12 reason=victory ranks=1 targets=20,19,18,17,16,15,25 points=0 marks=3,3,3,3,3,3,3",
        "standard,light,5 ; 2 ; 15685216071236931422 ; | S20, D16, D20 | T20 | D13, D15, S20 | D17, S16, D17 | D10 | T20, S15, S20 | S20, S20, T16 | D19 | D20, T20, D17 | ; phase=finished current=1 round=5 reason=roundLimit ranks=2,1 targets=20,17,16,15 points=17,32 marks=3,3,1,1/3,2,3,2",
        "standard,light,4 ; 2 ; 42 ; T15, D17, D15 | S20, D19, T19 | D18, S19 | MISS, S19, D15 | D17 | S17, D15, T17 | T19, D19, S19 | S17, T17, S8 | ; phase=finished current=1 round=4 reason=roundLimit ranks=2,1 targets=19,18,17,15 points=47,57 marks=3,2,3,3/3,0,3,3",
        "standard,normal,20 ; 1 ; 1 ; D20, S18, T15 |  | SB, S15 | D3 | D20, T20, T18 | T16 | T16, SB, S16 | D15, S20, SB | S18, T18, S16 | T17, S19, S16 |  |  | SB, D18, DB | T18, S15 ; phase=throwing current=0 round=14 reason=- ranks=1 targets=20,19,18,17,16,15,25 points=0 marks=3,1,3,3,3,3,3",
        "standard,light,3 ; 1 ; 0 ; T9, T16, S18 | D20, S19, D19 | D7, DB, D17 | ; phase=finished current=0 round=3 reason=roundLimit ranks=1 targets=20,19,18,17 points=0 marks=2,3,1,2",
        "cutThroat,light,3 ; 1 ; 1 ; T17, S16, T7 | T17 | S7 | ; phase=finished current=0 round=3 reason=roundLimit ranks=1 targets=18,17,16,15 points=0 marks=0,3,1,0",
        "cutThroat,normal,16 ; 3 ; 9969828383573910487 ; T15, D17, DB | S17, S4, D15 | D6, T15, S2 | D19, S18, T15 | S19, D19, T15 | SB, S19, S11 | T20, S12, S16 | SB, T16, S2 | S16, S16, T15 | T17, D20, T16 | S16, D19, S10 | T20, S15, T17 | S15, SB, DB | T17, T17, T20 | T19, S19, D6 |  | S17, S20, T16 | S18, D15 | T18, DB, D17 | T17, T19, S20 |  | T19 ; phase=finished current=0 round=8 reason=victory ranks=1,2,3 targets=20,19,18,17,16,15,25 points=133,237,310 marks=3,3,3,3,3,3,3/3,3,0,3,3,3,1/3,3,1,3,2,3,1",
        "cutThroat,normal,20 ; 3 ; 42 ; D18, S16, D16 | T19, SB, D18 | T16, S15, D18 | T15, SB, S19 | T19, T19, T16 | SB, T19, T15 |  |  | T6, D19, S15 | S20, SB, T1 | T19, D19, D20 | T15, S17, S17 | T19 | S20, MISS, S20 | DB, D15, S19 | D19, T18, D17 | D19, T20, S15 | SB, SB ; phase=throwing current=2 round=6 reason=- ranks=3,1,2 targets=20,19,18,17,16,15,25 points=377,191,230 marks=1,3,3,2,3,3,2/3,3,2,0,3,1,1/0,3,2,2,3,3,3",
        "cutThroat,normal,1 ; 1 ; 0 ; SB, SB, S15 | ; phase=finished current=0 round=1 reason=roundLimit ranks=1 targets=20,19,18,17,16,15,25 points=0 marks=0,0,0,0,0,1,2",
        "standard,normal,18 ; 2 ; 42 ; T16, T19, T17 | S20, D4, T3 | T18, S4, S17 | T18 ; phase=throwing current=1 round=2 reason=- ranks=1,2 targets=20,19,18,17,16,15,25 points=17,0 marks=0,3,3,3,3,0,0/1,0,3,0,0,0,0",
        "cutThroat,normal,20 ; 3 ; 0 ; D17, D8, DB | S16, S15, S19 | D17, T15, S17 | D18, D12, D18 | S3, T16, T16 | D18, D19, S20 | S16 | T2 | D16, D19, T3 | S16, T20, D15 | SB, DB, SB | T20, S17, D18 | T3, S17, T15 |  | D18, T17, D17 | D18, D19, D16 | S15, T20, T17 | S17, T17, S16 | S19, S16, D19 | DB ; phase=throwing current=1 round=7 reason=- ranks=2,3,1 targets=20,19,18,17,16,15,25 points=175,317,173 marks=3,3,3,3,3,3,2/3,1,0,3,3,2,3/3,3,3,3,3,3,0",
        "cutThroat,normal,nil ; 1 ; 0 ; T17, T17, T9 | D17, T19 |  | S5, T16 | D19, D19 | T20, D18, D15 | T18, D7, DB | D20, SB | S17, S18, T15 ; phase=finished current=0 round=9 reason=victory ranks=1 targets=20,19,18,17,16,15,25 points=0 marks=3,3,3,3,3,3,3",
        "cutThroat,normal,15 ; 3 ; 986671023903405819 ; S15, D20, S20 | S20, D15, D15 | T17, D16, DB | S20 | T17, S12 | S20, S17, S20 | D15, S20, D18 | T14, S14, SB | T15, S20, S19 | S20 |  | D18 | D19, T16 | T9, D16, D16 | T18, S18 | D18, T7, T15 |  | T16, T8, T15 | D17, T11, S20 | T15, T20, T17 | D18 | D19, S16, S17 | ; phase=throwing current=1 round=8 reason=- ranks=2,3,1 targets=20,19,18,17,16,15,25 points=137,207,90 marks=3,3,3,3,3,3,0/3,0,0,3,3,3,1/3,1,3,3,3,3,2",
        "standard,normal,nil ; 1 ; 0 ; D18, SB, D15 | DB, S20, S18 | D18, S17, S8 | MISS, S15, D20 | D20, S19, D16 | D19, S12, S7 | D10, S16, S18 | D19, S20, S20 | SB, D19, D20 | S16, D10, T18 |  |  | S17 | DB, T5 | S18 | S19, S16, D16 | D11, S15, SB | S17 ; phase=finished current=0 round=18 reason=victory ranks=1 targets=20,19,18,17,16,15,25 points=0 marks=3,3,3,3,3,3,3",
        "cutThroat,normal,nil ; 4 ; 42 ; S10, D18, T19 | T14, S4, DB | T18, D12, T18 | D13, DB, S9 | S15, S16 | D18, D16, D18 | S17, SB | S10, SB, S18 | D15, D18, D20 | T18, DB, T16 | D14, T18, D16 |  | T16, D11, S17 | T20, D20, S5 | S16, T16, S10 |  | S18, DB, S18 | D20 | T10, T15, D17 |  | T10, T18 | T20, S18, DB | D18, T15, S15 |  |  | SB, S18, T19 | S19, T20 | T19, SB, T15 | D17, S19, T15 |  | D15, D16, S17 | S18, S2, S15 | S15, S18, MISS | T16, D17, DB | D17, S15, S18 | T18, T16, SB |  | D17, S17, SB | D19, S19, D16 | SB, T16, D16 | S19, D16, S18 | T20, D13, S15 | T18, S20, D16 | D16, T15, T15 | T15, T6 | SB, T17, S18 ; phase=turnComplete current=1 round=12 reason=- ranks=3,1,2,4 targets=20,19,18,17,16,15,25 points=599,420,482,988 marks=2,3,3,3,3,3,2/3,3,3,3,3,1,3/3,3,3,3,3,3,1/0,3,3,0,3,3,3",
        "standard,light,1 ; 3 ; 42 ; T17, S18 | T17, D15, S15 | S17, D15, T18 | ; phase=finished current=2 round=1 reason=roundLimit ranks=3,1,1 targets=19,18,17,15 points=0,0,0 marks=0,1,3,0/0,0,3,3/0,3,1,2",
        "cutThroat,normal,20 ; 3 ; 1 ; T20 | S20, D6, S12 | D11, S19, S17 | D20, S20 | DB, T14, S15 | T16, D20, SB | T17, S3, D15 | T12, D18, T20 | S11, SB, T18 | T18, T16, SB | S15, S15, S16 | S15, D3, D15 | D17, D4, T20 |  | D19, T20, D16 | S15, T15, DB | S16, DB, SB | S4, S18, T15 | D16, S18, T16 | S17, T17, S19 | S17, T18, T20 | S16, D15, T17 | T19, T19, S17 | S6, DB, SB | S3, S18, S17 | D17, SB, D18 | S1, T17, D1 | D9, S1, T19 ; phase=finished current=0 round=10 reason=victory ranks=1,2,3 targets=20,19,18,17,16,15,25 points=76,330,360 marks=3,3,3,3,3,3,3/3,3,3,3,2,3,3/3,3,3,3,3,3,3",
        "cutThroat,normal,nil ; 4 ; 42 ; T20, D17, DB |  | D16, T7, T17 | S17, D16, DB | S2, T17, S19 | T19, D20, SB | DB |  | D5, T15 | SB, T16, D19 | T20, D18, S17 | S20, D18, SB | S17, D17, T16 | S15, D4, T16 | S20, T15, S17 | S17, S19 | DB, S20, D17 | T19, DB, D16 | MISS, S18, T8 | S15, S15, S20 | DB, T20, D20 | S1, MISS | S16, SB | S11, S15, S17 | S16, D17, D15 |  | D19, D19, S10 |  | T15 | S13, T19, T20 | D1, T17, S16 | DB, T1, D18 | T18, S9, D20 | S19, T20, T20 | D16, D10, SB | S15, T4, T18 | T18, D18, S15 | T19, T1, DB | T17, S20, T16 | S9, S19, S20 | S18, DB | D17, T18 | D17, D16, T11 | ; phase=throwing current=3 round=11 reason=- ranks=1,3,2,4 targets=20,19,18,17,16,15,25 points=265,773,275,984 marks=3,1,3,3,3,3,3/3,3,3,2,3,1,3/3,3,3,3,3,3,3/3,2,3,3,2,3,3",
        "standard,normal,1 ; 2 ; 1 ; S15, DB | D19, S18, T19 | ; phase=finished current=1 round=1 reason=roundLimit ranks=2,1 targets=20,19,18,17,16,15,25 points=0,38 marks=0,0,0,0,0,1,2/0,3,1,0,0,0,0",
        "standard,normal,nil ; 3 ; 1 ; D16, SB, D19 | S18, T18, S20 | T17, S17, D11 | T15, S18, S19 | T19, S9, S15 | S18, S19, D19 | D16, D6, SB | DB, D17, S5 |  | T16, D17, D16 | D7, D6, S18 | T18, D3, D17 | D19, T16, S17 | T16, D16, T17 | S20, D19, SB | S17, T20, SB | S17, T6, T15 | D20, DB, SB | SB, S18, S16 | S17, SB, T2 | T19, T15, T17 | T20 | S20, S18 | T18, S17, T19 | T4, SB, DB | D20 | T15, S16, D19 | S15, T11, D17 | T10, T16, D18 | D20, T18, S18 | T18 ; phase=finished current=0 round=11 reason=victory ranks=1,3,2 targets=20,19,18,17,16,15,25 points=245,185,220 marks=3,3,3,3,3,3,3/3,3,3,3,3,3,3/3,3,3,3,1,3,3",
        "cutThroat,light,2 ; 3 ; 1 ; S15, T17, D16 | S16, S16, S15 | D18, T18, S16 |  | D16, S17, T18 | S17, T15, D16 | ; phase=finished current=2 round=2 reason=roundLimit ranks=3,2,1 targets=18,17,16,15 points=52,36,16 marks=0,3,2,1/3,1,3,1/3,1,3,3",
        "standard,light,20 ; 1 ; 0 ; D20, D12, S2 |  | T9, D19, T17 | T19 | S18, D20, D18 ; phase=finished current=0 round=5 reason=victory ranks=1 targets=20,19,18,17 points=0 marks=3,3,3,3",
        "cutThroat,light,20 ; 2 ; 0 ; S20, S19, D20 | D19, T20, T18 | D18, D19, D19 | T19 | S19, S17, D20 | S20, D18, D20 | S18, S17, T18 | T18, D18, S3 | S19, T18, S17 ; phase=finished current=0 round=5 reason=victory ranks=1,2 targets=20,19,18,17 points=36,38 marks=3,3,3,3/3,3,3,0",
        "standard,normal,25 ; 4 ; 1 ; T16, T9, D18 | D15, T13, D19 | DB | T20, D18, D8 | D15 | DB, S15, D8 | ; phase=throwing current=2 round=2 reason=- ranks=1,1,4,3 targets=20,19,18,17,16,15,25 points=0,0,0,0 marks=0,0,2,0,3,2,0/0,2,0,0,0,3,2/0,0,0,0,0,0,2/3,0,2,0,0,0,0",
        "cutThroat,normal,13 ; 4 ; 12272598242627031951 ; S20 | T16, D15, S4 | T15, D16 | T4, D20, D19 |  | T16, T16, D19 | D3, T20, D16 | D18, D20 | T17, T20, S17 | SB, D16, T19 | D17, T2, D19 | S17, S19, D18 | D17, DB | D19, D17, S18 | S18, S5, S15 | DB, S19, S15 | T15 ; phase=throwing current=0 round=5 reason=- ranks=4,1,3,2 targets=20,19,18,17,16,15,25 points=292,124,260,248 marks=3,0,0,3,0,3,2/0,3,1,2,3,2,1/3,2,1,2,3,3,0/3,3,3,1,0,1,2",
        "cutThroat,normal,20 ; 3 ; 42 ; D19, T17, T17 | S20, D20, D20 | T15, T17, S19 |  | S19, T15, T20 | ; phase=throwing current=2 round=2 reason=- ranks=2,1,3 targets=20,19,18,17,16,15,25 points=100,51,151 marks=0,2,0,3,0,0,0/3,1,0,0,0,3,0/0,1,0,3,0,3,0",
        "cutThroat,normal,20 ; 3 ; 12533007356004162327 ; S17, D15, T18 | T15, D1, S5 | D18, D4 | S16, S20, S17 |  | S4, S17, S15 | D15, DB, T6 | T19, SB, T20 | D20, T18, SB | D15, D17, D11 | T19, T8, SB | T19, D17, D18 | DB, D20, T17 | T20, DB, SB | D11, D7, S18 | SB, D20, S18 | D20, T18, S16 | S20, D15, T16 | D17, T18 | S18 ; phase=throwing current=1 round=7 reason=- ranks=1,2,3 targets=20,19,18,17,16,15,25 points=57,235,359 marks=3,0,3,3,1,3,3/3,3,3,0,1,3,3/3,3,3,3,3,3,1",
        "standard,light,nil ; 3 ; 42 ; S18, D16, S19 | S15, S14, S19 | D18 | S8, D19, D18 |  | T17, T17, D15 | T19, S19, T19 | S18, T14, T18 | D11, D15, T19 | D19, S17, S18 | T17, S19 | S19, T18, T17 | S18, D18 | D18, S19 ; phase=throwing current=1 round=5 reason=- ranks=1,3,2 targets=19,18,17,15 points=189,18,136 marks=3,3,1,0/3,3,3,1/3,3,3,3",
        "standard,normal,19 ; 2 ; 1 ; D16, S19, T17 | D15, S15, T17 | S16, DB, T19 | T13, T1, DB | S17, T19, S19 | S19, D15, DB | S16, S18 | T20, S20, S16 | D18, D16, S17 | D15, S18, D15 | T20, D16, T15 | D17, S19 | SB ; phase=finished current=0 round=7 reason=victory ranks=1,2 targets=20,19,18,17,16,15,25 points=175,135 marks=3,3,3,3,3,3,3/3,2,1,3,1,3,3",
        "standard,normal,nil ; 3 ; 42 ; D16, S15, T20 | T18, S17, D18 | T16, S17, MISS | D20 | S15, D20, T17 |  | S15, SB, S15 | D17, S19, S18 |  | S16, S16, S19 | D15, DB, D16 | T18, T20 | T15, S19, S19 | SB, T17, D15 | D18, S18, T2 | S16, SB, T11 | T16, S19, S17 | D17, D20, T17 |  | T19 | S18, DB, D19 | T19, S18, D8 | T13, S9, D17 | T19, D16, DB | D15, D18, T16 |  | S19, D19, S17 | D19, D18, S17 | D17 | D16, T17, D12 | D15, S16, D15 | S19, T18, T19 | S16, D19, S8 | ; phase=throwing current=0 round=12 reason=- ranks=2,1,3 targets=20,19,18,17,16,15,25 points=264,309,256 marks=3,3,3,1,3,3,2/2,3,3,3,3,3,3/3,3,3,3,3,0,3",
        "cutThroat,normal,20 ; 1 ; 0 ; T15 | D15, T17, S9 |  | S5, S19, D15 |  | S18, D18, SB | D6, T16, T16 | D20, D16, T20 | D15, T17 | S10, D19, S19 | S15, DB ; phase=finished current=0 round=11 reason=victory ranks=1 targets=20,19,18,17,16,15,25 points=0 marks=3,3,3,3,3,3,3",
        "standard,light,28 ; 3 ; 0 ; T19, T20, S20 | D17, S20, S19 | S19, T17, T17 | T17, S17, T19 | S18 |  | D19, D18 | D19, T18, S20 |  | T18 ; phase=finished current=0 round=4 reason=victory ranks=1,3,2 targets=20,19,18,17 points=168,18,51 marks=3,3,3,3/2,3,3,2/0,1,0,3",
        "standard,light,20 ; 3 ; 2775903128247237095 ; | T19, D20, S20 | T16, S19, S17 | T17, T19, T17 | T19, S19, T16 ; phase=turnComplete current=1 round=2 reason=- ranks=2,1,3 targets=20,19,17,16 points=51,76,0 marks=0,3,3,0/3,3,0,3/0,1,1,3",
        "standard,normal,20 ; 1 ; 42 ; T18, S20, T19 | T16, D19, T20 | T20, D15, T17 | T19, D17 | D15, S18, T20 | D13, S15, T15 | T19, T15 | S17, D18, D20 | D15, D15, S18 | DB, D18, DB ; phase=finished current=0 round=10 reason=victory ranks=1 targets=20,19,18,17,16,15,25 points=0 marks=3,3,3,3,3,3,3",
        "cutThroat,light,6 ; 4 ; 9429913610083229843 ; T15, T15 | T10, T20, S18 |  | S1, D15, D17 | T15, S20, D17 | S20, D17, S15 | S17, T17, T18 | T17, S18, T20 | D20, S20, T18 | S20, S18, D18 | S18, T18, T16 | T3, D17, D15 | S18, T20, S20 | D15, T15, D20 | T16, T17, T8 | D18, D17, S17 | T15, S20, D20 | D18, T13, S18 | T18, D17 ; phase=finished current=2 round=5 reason=victory ranks=2,3,4,1 targets=20,18,17,15 points=241,326,435,235 marks=3,3,2,3/3,3,2,3/0,3,3,0/3,3,3,3",
        "cutThroat,normal,5 ; 1 ; 1 ; S2, D20, T17 | S17, D20, T17 | S17, D19 |  | D17, T19, S16 | ; phase=finished current=0 round=5 reason=roundLimit ranks=1 targets=20,19,18,17,16,15,25 points=0 marks=3,3,0,3,1,0,0",
        "cutThroat,normal,3 ; 1 ; 0 ; S18, D7, S18 | D16, SB, T20 | S15, T19, T17 | ; phase=finished current=0 round=3 reason=roundLimit ranks=1 targets=20,19,18,17,16,15,25 points=0 marks=3,3,2,3,2,1,1",
        "cutThroat,light,nil ; 3 ; 1 ; T18, D18, D16 | T17, T17, S16 | S15, D16, S16 | S16, D13, T17 | S15, D11, T9 | D18, D16, T5 | D15, D17, S15 ; phase=finished current=0 round=3 reason=victory ranks=1,2,3 targets=18,17,16,15 points=51,68,121 marks=3,3,3,3/0,3,1,1/2,0,3,1",
        "standard,light,20 ; 4 ; 42 ; T19, T1, T15 | S19, D19, D19 | T17, T17, T19 | T15, T2, D19 | D18, D19, S18 | D15 | S18, D13, D18 | S11, D15, T18 | S20 | S15, D15, D17 |  | S1, S19, D18 | S18, S17, S19 | S19 |  |  | D18, S17, T17 ; phase=finished current=0 round=5 reason=victory ranks=1,2,4,3 targets=19,18,17,15 points=126,68,51,66 marks=3,3,3,3/3,0,2,3/3,3,3,0/3,3,0,3",
        "cutThroat,normal,27 ; 1 ; 2275576865775306099 ; S20, D20, D17 | D15, DB, DB | D20, D20 | D16, D16, D20 | D17, S20, D15 | T20, SB, D15 | SB ; phase=throwing current=0 round=7 reason=- ranks=1 targets=20,19,18,17,16,15,25 points=0 marks=3,0,0,3,3,3,3",
        "cutThroat,normal,20 ; 2 ; 6498774700197638243 ; D19, T16, S16 | D18 | D16, D17, D18 | S20, D19, DB | S17, DB, T9 | S19, D17, D10 | D19, T17, T2 |  | S17, T20, D20 | D18 | D20, S20, T15 | T14, S18, T18 | D13 | S20, D16, D17 | T9, DB, T19 | D17, T4, S15 |  | T16, D4, D18 | D17 | ; phase=throwing current=1 round=10 reason=- ranks=1,2 targets=20,19,18,17,16,15,25 points=126,241 marks=3,3,2,3,3,3,3/2,3,3,3,3,1,2",
        "cutThroat,normal,20 ; 3 ; 12776182002784584951 ; S15, D20, S19 | D18, SB, D17 | T17, D6, T16 | D18, S17, D20 | S20, T20, DB | S16, T17, S20 | T16, S19, S19 | S15, S18, T16 | S15 | T15, T19, T18 |  | D5 | S18, T15 |  | D18, SB, S16 | D18 | D17, DB, D18 | D16, S16, DB | DB, T20, T15 | T17, S5, D16 | DB, SB, S20 | D19, DB, D20 | S19, D17, D3 | D20, DB, T20 |  | T15, D15, S18 | S15, T19, D16 | DB, T19, T15 | S16 | S16 ; phase=throwing current=2 round=10 reason=- ranks=1,2,3 targets=20,19,18,17,16,15,25 points=294,344,624 marks=3,3,3,1,3,3,3/3,1,3,3,3,3,3/3,3,2,3,3,2,3",
        "standard,light,20 ; 1 ; 1344014226245651549 ; S20, S18, T18 | D18, D18, T17 | D20, S19, T20 | T19 ; phase=finished current=0 round=4 reason=victory ranks=1 targets=20,19,18,17 points=0 marks=3,3,3,3",
        "standard,normal,nil ; 3 ; 1 ; | D17, D15, SB | S5 | D16, S20, D18 | D18, D15, DB | D16, D19, T19 | T3, MISS, D15 | D20, S16, S19 | SB, D15, SB | D2, S19, D18 | D19, T19, S20 | S16, D15, T18 |  | S12 | D20, D15, S9 | T19, DB, T4 | D1, S20, DB |  | S20, T17, S19 | D18, D18, S20 | ; phase=throwing current=2 round=7 reason=- ranks=3,1,2 targets=20,19,18,17,16,15,25 points=18,162,83 marks=2,3,3,3,2,2,2/3,3,3,2,1,3,3/2,3,3,0,3,3,2",
        "cutThroat,normal,nil ; 2 ; 0 ; DB, T20, DB | SB, S19, S16 | S17, SB, S18 | S16 |  | T18, S15, T20 |  | S16, T18, T17 |  | D19, D15, S19 | S7 | SB, S16, T18 | S16, D16, D20 | SB ; phase=finished current=1 round=7 reason=victory ranks=2,1 targets=20,19,18,17,16,15,25 points=143,50 marks=3,0,1,1,3,0,3/3,3,3,3,3,3,3",
        "standard,normal,20 ; 3 ; 1 ; S16, S16, T15 | T16, D17, SB | SB, DB | T18, T19, D20 | T15, S5, T9 | S15, S2, D4 | S19, S14, S18 | T17, S19, S15 | T15, DB, D16 | D17, SB, T20 | DB, S18, S16 | D15, T7, D18 | SB, S17, D19 | D15, D1, T19 | S17 |  |  | S20, D18, S15 | T17, S15, S20 | T19, T19, DB | S16, D17, S20 | D2 | SB, S19, T18 | S15, S5, SB | S15, D19, D16 | D15, S19, S19 | SB, D19, T16 |  | D16, S20 | T11, T20, T15 | S16, D16, D20 | T18, T13, DB | S19, SB, D17 | T14, S17, S18 |  | S17, D15, S16 | D15, D15, S20 | S11, T18 | S18 ; phase=throwing current=2 round=13 reason=- ranks=2,1,3 targets=20,19,18,17,16,15,25 points=284,380,183 marks=3,3,3,3,3,3,2/1,3,3,3,3,3,3/3,3,3,3,3,3,3",
    ]
}
