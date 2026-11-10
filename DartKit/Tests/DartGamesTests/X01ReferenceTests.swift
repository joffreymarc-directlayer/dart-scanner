import Testing
import DartCore
import DartGames
import DartTestSupport

/// X01 against the reference implementation that computed the vectors of GAMES.md (§2.11): sixty random
/// games (every start score, both in rules, both out rules, with and without a round limit, one to four
/// players) played by that reference, with the state it reached. The games were generated once with a fixed
/// seed; the script of a line is the journal, in the notation of the vectors.
///
/// A line is `startScore,inRule,outRule,maxRounds ; players ; seed ; journal ; expected state`.
@Suite struct X01ReferenceTests {
    @Test(arguments: X01ReferenceTests.games)
    func theGameReachesTheStateOfTheReference(_ line: String) throws {
        let (options, players, seed, script, expected) = try Self.parts(line)
        try #require(options.count == 4)
        let startScore = try #require(Int(options[0]))
        let maxRounds: OptionValue = options[3] == "nil" ? .null : .int(try #require(Int(options[3])))
        var match = try GameRegistry.standard.match(
            .x01, ["startScore": .int(startScore), "inRule": .string(options[1]), "outRule": .string(options[2]), "maxRounds": maxRounds],
            players: players, seed: seed)
        let outcomes = match.play(script)
        // The reference only writes the inputs it accepts.
        let allAccepted = outcomes.allSatisfy { $0.isAccepted }
        #expect(allAccepted, "\(line)")
        Self.expectCommon(match, expected, line)
        let rows = match.snapshot.players.indices
        #expect(rows.map { match.fact($0, "remaining") } == Self.numbers(expected["remaining"]).map { .int($0) }, "\(line)")
        #expect(rows.map { match.fact($0, "isOpen") } == Self.numbers(expected["open"]).map { .bool($0 == 1) }, "\(line)")
        #expect(rows.map { match.fact($0, "dartsThrown") } == Self.numbers(expected["darts"]).map { .int($0) }, "\(line)")
        #expect(rows.map { match.fact($0, "busts") } == Self.numbers(expected["busts"]).map { .int($0) }, "\(line)")
    }

    /// The sample covers the three ways a game can stand: won, ended at the round limit, still running.
    @Test func theSampleCoversEveryEnding() {
        let reasons = Set(Self.games.compactMap { $0.components(separatedBy: " ; ").last.flatMap { Self.fields($0)["reason"] } })
        #expect(reasons == ["victory", "roundLimit", "-"] && Self.games.count == 60)
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
        "301,double,double,20 ; 3 ; 0 ; S20, D1, S5 | S20, S20, T20 | SB, D1, T19 | T20, T20, S10 | S20, D20, DB | S1, DB, S20 | D1 | DB, D4, T1 |  | D2, T10, S18 | S18, D10, S5 | S19, S10, S4 | D19, S17, D2 | S19 | T11, SB, S14 | D1, S11, D20 | S1, S4, D17 | D3, T17, T19 | D5, D19, T7 | S9, S18 | D13, T18 | D9, D2, T20 | D11 ; phase=finished current=1 round=8 reason=victory ranks=2,1,3 remaining=51,0,66 open=1,1,1 darts=22,19,17 busts=3,0,2",
        "701,straight,double,23 ; 4 ; 0 ; D20, MISS | S1, MISS | S5, SB, T17 | T18, T17, T20 | S1, S1 | S20, S20, S1 | T20, MISS, DB | T19, T20, T19 |  | S20, T19, T20 | T17, DB, S5 | T20, DB, MISS | SB, T19, T20 | SB, S5, T18 | S1, D20, D20 | T17, S1, T20 | SB, T20, S5 | D20 | T17 | T1, T19, T3 | S5 | DB, MISS, DB | MISS, SB, SB | D1, D4, S16 | T20, T20, S5 | MISS, S5, MISS | SB, T17, DB | SB, T1, S17 | T17, S20, D20 | T20, S5, DB |  | S18, T5, S12 | T19, DB, S6 | T9, T6, T5 | D16, D7, DB ; phase=finished current=2 round=9 reason=victory ranks=3,4,1,2 remaining=73,118,0,45 open=1,1,1,1 darts=20,24,22,24 busts=0,0,0,2",
        "301,straight,double,20 ; 3 ; 0 ; MISS, T19, D20 | T17, T17, S5 | MISS, S20, T18 | S20, S20, T18 | T20, S6, S6 | DB, D5, T6 | S17, D12, D14 | S3, T4, D6 | S10, S2 | T2, SB, S10 | D10 | T13, T5, T17 | S9, D16 ; phase=finished current=0 round=5 reason=victory ranks=1,3,2 remaining=0,75,32 open=1,1,1 darts=14,10,11 busts=1,0,0",
        "501,straight,double,5 ; 3 ; 0 ; D20, S5, T20 | DB, SB, S20 | T20, S5, S5 | MISS, D20, S20 | MISS | S1, D20, D20 | S5 | T19 | DB, S5, SB |  | S20 | D20 | D20, S20, S5 | S1, S5, S1 |  | ; phase=finished current=2 round=5 reason=roundLimit ranks=2,3,1 remaining=266,322,230 open=1,1,1 darts=10,9,10 busts=0,0,0",
        "501,straight,straight,2 ; 4 ; 0 ; DB, T18, S1 | T18, SB, S1 | S20, D20, S1 | D20, D20, T19 | T19, MISS, T18 | S1, T18, SB |  | T18, T17, SB | ; phase=finished current=3 round=2 reason=roundLimit ranks=2,3,4,1 remaining=285,341,440,234 open=1,1,1,1 darts=6,6,3,6 busts=0,0,0,0",
        "501,straight,double,nil ; 2 ; 0 ; SB, T19, MISS | SB, T18, T18 | D20, S1, T20 | T19, D20, S20 | SB, SB, S20 | S1, T18, SB | T19, T20, DB | D10, T13, S8 | T6, D2, S2 |  |  | D10, D9, S4 | S13, D10, D12 ; phase=finished current=0 round=7 reason=victory ranks=1,2 remaining=0,62 open=1,1 darts=18,15 busts=0,0",
        "701,double,straight,25 ; 4 ; 0 ; S20, D16, T17 | D20, S5 | D16, D20 | DB, D20, S20 | D20, T20, S20 | D20, T18, D20 | S20, T17, T19 |  | MISS, DB, SB | SB, T19, D20 | S5, T19, DB | SB, S20, MISS | T18, S1, T19 | S20, SB, T20 | S20, T19, T20 | D20, D20, S5 | S20, SB, S1 | T20, T18, D20 | T18, DB, D1 |  |  | S2, MISS, D2 | S5, S11, S9 | T20, T20 | DB, T20, T1 | S17 | S13, S3 | S20, SB, SB | D16, T3, MISS | T8, S18, S3 | S20, T6, S9 | S5, T19, SB | T18, S8, T7 | S14, S16, D8 | D15, D10 | MISS, S5, S14 | S20, D20 | D13 | T5 | D17, DB, D13 | T18 ; phase=turnComplete current=0 round=11 reason=- ranks=3,1,2,4 remaining=28,1,8,55 open=1,1,1,1 darts=27,25,25,23 busts=2,0,1,0",
        "301,straight,double,20 ; 4 ; 0 ; DB, MISS, T18 |  | S20, S1, MISS | T20, SB, T17 |  | S5, S1, T19 | S20, S5, S1 | D7, T17, S9 | ; phase=throwing current=0 round=3 reason=- ranks=2,3,4,1 remaining=197,238,254,91 open=1,1,1,1 darts=3,3,6,6 busts=0,0,0,0",
        "501,straight,straight,8 ; 3 ; 0 ; T18, MISS, S5 | T19, T17, T20 | T18, SB, T18 |  | D20, D20, D20 | T18, DB, T20 |  | DB, S11, D18 | S5, T19, S15 | T20, S1, MISS | T8, T20 |  | T19, S5, T17 | D16 ; phase=finished current=1 round=5 reason=victory ranks=3,1,2 remaining=268,0,127 open=1,1,1 darts=9,12,9 busts=0,0,0",
        "301,straight,straight,20 ; 3 ; 0 ; | DB, S1, S20 | T17, T20, MISS | T17 | SB, S1, T17 | D20, S19, D1 | S1, T20, T19 | T1, T9, S6 | SB, S15, T19 | T17, S18, MISS | T19, T4, T18 |  | T10 | S8, T12, T1 | D16 ; phase=finished current=2 round=5 reason=victory ranks=2,3,1 remaining=33,70,0 open=1,1,1 darts=8,15,10 busts=0,1,0",
        "701,double,double,20 ; 1 ; 0 ; D20, SB, T20 | SB, T19, S1 | S20, T20, MISS | MISS, DB, MISS | T20, DB, T19 | SB, T8, T1 | D10, D16, T7 | S1, T11, D20 | D14, T15 | D12, D14, S19 | T10, T19 |  | S11, S9, T12 | S4, S11 | S1, S16 | T8 | T12 | S15 | D1 |  | ; phase=finished current=0 round=20 reason=roundLimit ranks=1 remaining=13 open=1 darts=42 busts=9",
        "501,straight,straight,nil ; 4 ; 0 ; T20, T19, DB | S20 | T17, T19, T18 | T20, S20, T17 | T18, SB, T18 |  | D20, T19, S20 | T20, DB, D20 | S5, T19, D5 | S20, S20, S5 | D20, T20, T18 | S1, T20, D13 | T13, S7, T5 | S20, T19, MISS | S11, D10, T1 | T1, S2, T14 | T4 | T20, T17, T20 | S1, S4, S2 | S5 | D9, D19 ; phase=finished current=0 round=6 reason=victory ranks=1,4,2,3 remaining=0,188,27,81 open=1,1,1,1 darts=15,10,15,13 busts=0,0,0,0",
        "501,straight,double,5 ; 4 ; 0 ; T20, D20, T20 | S20, SB, T19 | S20, S20, S20 | S1, T18, T19 | D20, T20, T17 | S5 | T20, S20, MISS | S5, T20, DB | T17, S3, S11 | T20 | T17, MISS, S1 |  | T3, D5, D2 | MISS, T20, D20 | MISS, T20, T17 | T17, T20, T11 | D5, T18, D14 | T18, S17, T13 | D20, T1, S14 | D18 | ; phase=finished current=3 round=5 reason=roundLimit ranks=1,3,4,2 remaining=10,124,141,94 open=1,1,1,1 darts=15,11,15,10 busts=0,0,0,0",
        "301,straight,straight,20 ; 4 ; 0 ; T20, DB, DB | T17, S20 | S20, DB, T20 | T18, S5, T19 |  | D20, DB, S17 | S13, S1, S14 | S5, D5, D9 | T14 | D7, T7, S19 | T16, S6, S4 | T3, D8, T15 | D19, S16, T1 | S12, D5, D13 | D10, S6, D5 |  | S1, D12, S17 ; phase=finished current=0 round=5 reason=victory ranks=1,2,3,4 remaining=0,21,49,82 open=1,1,1,1 darts=10,11,12,9 busts=0,0,0,0",
        "701,double,straight,3 ; 3 ; 0 ; D1, S1, T20 | MISS, D16, T20 | S20, MISS, SB | DB, D20, T19 | S5, T17 | D16, T17, T18 | T19, T20, SB | D20, T18, D20 | S5, T17, S5 | ; phase=finished current=2 round=3 reason=roundLimit ranks=1,2,3 remaining=349,419,503 open=1,1,1 darts=9,8,9 busts=0,0,0",
        "501,straight,double,3 ; 1 ; 0 ; T19, T20, D20 | S5, T18, SB | MISS, S20 | ; phase=finished current=0 round=3 reason=roundLimit ranks=1 remaining=240 open=1 darts=8 busts=0",
        "301,straight,double,20 ; 1 ; 0 ; T18, SB, T20 | T15, S12, D6 | SB, S8 | S4, D12, D16 ; phase=finished current=0 round=4 reason=victory ranks=1 remaining=0 open=1 darts=11 busts=0",
        "301,straight,straight,20 ; 4 ; 0 ; T20, DB, T20 | S5, T18, S20 | T18, T17, T18 | S20, S20, T20 | S2, S16, S1 | MISS, T20, T12 | S3 | S5, S1, DB | D13, T15, S2 | T20, T14 | S15, S1 ; phase=throwing current=2 round=3 reason=- ranks=2,1,3,4 remaining=39,24,123,145 open=1,1,1,1 darts=9,8,6,6 busts=0,0,0,0",
        "301,straight,straight,1 ; 2 ; 0 ; SB, S20, T18 | DB, T18, S1 | ; phase=finished current=1 round=1 reason=roundLimit ranks=2,1 remaining=202,196 open=1,1 darts=3,3 busts=0,0",
        "301,straight,double,20 ; 3 ; 0 ; T18, S5, D20 | T17, S1, T19 | T17, S5, T20 | S5, DB, MISS |  | S1, DB | T12, D7, T5 |  | S15, S1, D1 | D6, T14, D5 | T17, T20, D9 | T17, D7, D15 | D11 | SB, S1, D11 | D4, S13 | SB | D13 | S12, T7 | D9 ; phase=finished current=0 round=7 reason=victory ranks=1,2,3 remaining=0,15,21 open=1,1,1 darts=15,10,15 busts=2,1,2",
        "301,straight,double,20 ; 1 ; 0 ; T18 | T20, T17, S17 | T16, S1, D14 | T19 | T2, T20 |  | T6, T17 | S12, S16, D13 | T16 | T20 |  | D2, D19 ; phase=finished current=0 round=12 reason=victory ranks=1 remaining=0 open=1 darts=19 busts=6",
        "301,straight,double,20 ; 3 ; 0 ; S5 | T18, S5, T20 | T18, D20, T19 | SB, SB, T20 | T17 |  | S5, S20, S12 | T15, T16, T19 | D1, D11, D2 | T20, T18, T10 | DB, T18, T5 | D7, S12, MISS | S5 | S12 | S3 | D13 | D16 | D12, T15, D12 ; phase=finished current=2 round=6 reason=victory ranks=2,3,1 remaining=5,12,0 open=1,1,1 darts=12,12,13 busts=2,3,0",
        "501,straight,double,20 ; 4 ; 0 ; S20, T19, T18 | MISS, T17, T17 | S5, D20, S20 | T17, S20, S1 |  |  | T20, T20, S5 |  | T20, D20, T18 | D20, T20, T19 | DB, MISS, T20 | MISS, T20, DB | T20, S13, T14 | S5, S1 ; phase=throwing current=1 round=4 reason=- ranks=1,3,2,4 remaining=101,236,201,319 open=1,1,1,1 darts=9,8,9,6 busts=0,0,0,0",
        "501,straight,double,20 ; 4 ; 0 ; T20 | T17, DB, T19 | MISS, MISS | SB, S1, T18 | T18, T18, DB | D20, S1, DB | S20, T17, S20 |  | MISS, MISS, SB | SB | T18, SB | T17, T20, S20 |  | D20, T20, D2 | MISS, MISS, T20 | T18 | T20, T19, D11 | T11, T10, S11 | T18, T20, S12 | T18, T18, MISS | T10, T10 | T19 | T4, MISS, D8 | D18, D2, S5 | D16, T4, S15 | D20, T3 | D3, T15, T10 | S3, D2, T5 | D14, MISS, S14 | D7 | T19 | D3, D19, S3 | S17 | S13, D11 ; phase=finished current=1 round=9 reason=victory ranks=3,1,4,2 remaining=17,0,36,14 open=1,1,1,1 darts=19,19,20,19 busts=2,2,1,0",
        "701,double,double,nil ; 4 ; 0 ; S20, SB, DB | MISS, MISS, D20 | S20, DB, S5 | MISS, S20, T20 |  | T18, T17, T19 | T17, T18, T18 | T20, D1, S20 | T20, S5, T17 | S20, T17, T18 | S20, S1, S1 | T17, T19, S1 | S1, T17, MISS | MISS | S5, T19, T20 | MISS, S5, T17 | D20, T19 |  | SB, T20, S5 | D20, DB, S5 | T18, T17, T20 | S5, S5, DB | D20, S1, S1 |  | T18, D2, D20 | S1, S1 | S20, T20, T11 | T19, T17, DB | S2, S19, D1 | T19, S5 | D7, S6, D4 | MISS, SB ; phase=throwing current=3 round=8 reason=- ranks=2,4,1,3 remaining=100,250,70,236 open=1,1,1,1 darts=20,17,24,20 busts=0,0,0,0",
        "701,straight,straight,5 ; 3 ; 0 ; S1, MISS, S20 | T18, T20, T20 |  | SB | T19, S20, T20 | D20, T20, S5 | T19, T18, S20 | T20, S20 | T20, D20, T20 | T19, D20, T18 | S5, S1, T18 | SB, SB, T20 | S20, T20, T17 | T19, S20, D14 | T20, D20, T18 | ; phase=finished current=2 round=5 reason=roundLimit ranks=3,1,2 remaining=242,145,172 open=1,1,1 darts=13,14,12 busts=0,0,0",
        "301,double,straight,6 ; 1 ; 0 ; D1, S1, D20 | SB, T20, D1 | S16, S3, D12 | D5 ; phase=throwing current=0 round=4 reason=- ranks=1 remaining=118 open=1 darts=10 busts=0",
        "501,double,straight,4 ; 1 ; 0 ; D20 | T17, S20, D20 | D20, S5 | S5, T20, T19 | ; phase=finished current=0 round=4 reason=roundLimit ranks=1 remaining=183 open=1 darts=9 busts=0",
        "301,double,straight,20 ; 2 ; 0 ; MISS, SB, D20 | D16, S20 | D20, S5, DB | SB, T20, S20 | T7, D13, S12 | S3, D8, D2 | D13, D18, T10 | T8, T9, D1 | T3, D3 ; phase=finished current=0 round=5 reason=victory ranks=1,2 remaining=0,68 open=1,1 darts=14,11 busts=0,0",
        "301,straight,straight,20 ; 3 ; 0 ; SB, D20, S5 | T17, MISS, DB | DB, T20, T17 | SB, DB, D12 | T19, D8, S19 | S11, S17, T7 | S9, MISS | S12, D13, T3 |  | D17, D19, S2 | D1, T5, S9 | D12, T5, D8 | S17, DB | D9, S17 ; phase=finished current=1 round=5 reason=victory ranks=3,1,2 remaining=49,0,36 open=1,1,1 darts=13,14,9 busts=1,0,0",
        "301,double,double,21 ; 2 ; 0 ; D16, D20, T17 | D20, S20, T20 | S2, S2, S9 | T20, S2, SB | T11, S15, T5 | S6, S3 | D15, D1, S15 |  | DB, S5 | SB, S20, S10 | S17 | D15 ; phase=finished current=1 round=6 reason=victory ranks=2,1 remaining=38,0 open=1,1 darts=15,12 busts=1,0",
        "301,double,double,4 ; 2 ; 0 ; SB, D20, S5 | S20, MISS, D16 | S5, S1, SB | S5, T19, D20 | T20, S13, S19 | D17, T1, DB | T11, T2, T12 | T6, S2, D6 | ; phase=finished current=1 round=4 reason=roundLimit ranks=2,1 remaining=58,48 open=1,1 darts=12,12 busts=0,0",
        "301,straight,straight,nil ; 3 ; 0 ; D20, S5, DB | T20, S5, T18 | T18, T20, T19 |  | T20, T14, S13 | D12, S7, D10 | S1, MISS, MISS | T2, T7, S2 | S19, T16, T5 |  | S5, D2, MISS | D16, S2, D15 | SB, D12, T15 |  | S1, T11 | D15, D7, T5 | S8, MISS, D7 |  | S9, D1, S3 | S7 ; phase=finished current=1 round=7 reason=victory ranks=3,1,2 remaining=38,0,15 open=1,1,1 darts=15,16,14 busts=0,0,2",
        "301,double,double,2 ; 1 ; 0 ; MISS, DB, T17 | T20, S13, D13 | ; phase=finished current=0 round=2 reason=roundLimit ranks=1 remaining=101 open=1 darts=6 busts=0",
        "501,double,double,20 ; 1 ; 0 ; D20, T19 | T20, D20, SB | D20, T20, S18 | T9, S14, T10 | S18, S11, T5 | S13, S2, D8 | S15 |  | D6, T19 | S12, S3 ; phase=turnComplete current=0 round=10 reason=- ranks=1 remaining=15 open=1 darts=22 busts=3",
        "301,double,double,nil ; 2 ; 0 ; D1, D20, T19 |  | T20, D20, S6 | S20, DB, D20 | T3, D7, D18 | T17, D11, S19 | S20, S17 | S2, S2, T16 | T9, D5 ; phase=finished current=0 round=5 reason=victory ranks=1,2 remaining=0,67 open=1,1 darts=13,9 busts=1,0",
        "301,double,straight,5 ; 1 ; 0 ; S20, SB, MISS | S20 | D1, MISS, SB | SB, SB, S5 | T17, D20, T19 | ; phase=finished current=0 round=5 reason=roundLimit ranks=1 remaining=71 open=1 darts=13 busts=0",
        "501,double,double,20 ; 4 ; 0 ; SB, D1, SB | T20, S20, SB | SB | D1, DB, DB | T20, MISS, MISS | D1 | T20, D16, S5 | MISS, T18, S5 | D20, S1, SB | S5, T17, D20 | T20, DB, T20 |  | T18, T18, T19 | MISS, MISS, T17 |  | T17, MISS, T20 | D20, T11, D15 | T20, T17, DB | SB, S5, DB | T17, S3, S16 | MISS, MISS, D8 | T17, S1, T3 | S1, T19, S7 | S2, S1, D11 | T5, D1, T10 | DB, MISS, T2 |  | S19, D12, D16 | S17 | T13, S18 | D18, D11, S11 | T20 | T13 | T7 | T2 ; phase=throwing current=2 round=9 reason=- ranks=1,1,4,3 remaining=17,17,74,59 open=1,1,1,1 darts=23,22,17,19 busts=2,1,0,1",
        "301,double,straight,29 ; 2 ; 0 ; | D1, S1, S1 | S20, MISS, S20 | S5, T17, S5 | DB, SB, S20 | DB, DB, D18 |  | T20, S5, D17 | T19, D3, D8 | T9 | S2, D20, T17 | S1 ; phase=finished current=1 round=6 reason=victory ranks=2,1 remaining=34,0 open=1,1 darts=12,14 busts=0,1",
        "701,straight,straight,13 ; 3 ; 0 ; S1, S20, T20 | S5, S1, SB | D20, T20, T19 | DB, T18, T18 | S5, S1 ; phase=throwing current=1 round=2 reason=- ranks=1,3,2 remaining=462,664,544 open=1,1,1 darts=6,5,3 busts=0,0,0",
        "501,double,double,20 ; 1 ; 0 ; D16, S5, T19 | S5, T20, SB | MISS, D20, S1 | MISS, T20, T19 | D15, T10, S13 | D20, S3, T7 | D11 ; phase=finished current=0 round=7 reason=victory ranks=1 remaining=0 open=1 darts=19 busts=0",
        "301,double,straight,20 ; 3 ; 0 ; SB, D1, T20 | DB | DB, MISS, T20 | DB, T19, D4 | T19, T20, D4 | T20, D18, D4 | T4, S1, D1 | T16, D3, S3 | D11, T17, D7 ; phase=finished current=2 round=3 reason=victory ranks=3,2,1 remaining=109,69,0 open=1,1,1 darts=9,7,9 busts=0,0,0",
        "501,double,double,29 ; 3 ; 0 ; DB, DB, D20 | D20, DB, T20 | SB, T20, D20 | D20, T20, D20 | D20, T18, T19 | DB, D20, DB | S1, T20, SB | SB, T20, S2 | T17, T18, D20 | D17, D8, S2 | T8 | T12, SB, S3 | S1, D12, S13 | T7, D1, D1 | S1, S16, T2 | D2, T7, D10 ; phase=finished current=0 round=6 reason=victory ranks=1,2,3 remaining=0,64,89 open=1,1,1 darts=18,13,15 busts=0,0,0",
        "701,straight,straight,29 ; 4 ; 0 ; DB, SB, T17 | T20, T17, D20 | T20, T17, S20 | T20, T20, SB | T20, T18, T18 |  |  | S5, D20 | T20, DB, DB | DB, S5, D20 | SB, S5, T19 |  |  | S1, S5, T17 | T19, MISS, T17 | SB, D20, D20 | T17, D20, S15 | MISS, S1, S5 | S1 | T19, D20, T19 | T12, D11 | T20, S20, T18 | T20, T20, DB | T18, S20, S5 | T10, T17, D1 ; phase=finished current=0 round=7 reason=victory ranks=1,4,3,2 remaining=0,258,204,173 open=1,1,1,1 darts=17,15,13,14 busts=0,0,0,0",
        "701,double,straight,20 ; 4 ; 0 ; SB, MISS, MISS | D16, DB, T20 | DB, T18, D20 | S20, S20, D1 | D16, DB, S5 | S1, T18, MISS | T20, DB, S5 | T18, MISS, MISS | S20, MISS, T19 | D20 | T20, DB, SB | D20, T18, T18 | DB, T19, MISS | T19, MISS, T18 | D20, T20, T18 | T20, T18, T18 |  | T19 | T16, S15, S1 | S5, T17, DB | D20, S1, S5 | T19, T17, S1 | D11, T7, T12 | DB, T2, S7 | MISS | T19, S7, S7 | D5 ; phase=finished current=2 round=7 reason=victory ranks=4,2,1,3 remaining=384,116,0,160 open=1,1,1,1 darts=16,17,19,18 busts=0,0,0,0",
        "501,double,straight,20 ; 3 ; 0 ; SB, S20, MISS | T20, T20, D1 | MISS, D16, SB | T20, D1, S1 | SB, SB, S20 | T17, SB, T17 | DB, T20, S20 | T18, S1, SB | MISS, T20, S5 | MISS, DB, D20 | D20, T19, S1 | T18, T20, T3 | S20, DB, T18 | T17, SB, T10 | T4, T4, D15 | T14, T18, T2 | S7, S12, T16 | T3, S1, T6 | S10, T6, D12 ; phase=finished current=0 round=7 reason=victory ranks=1,3,2 remaining=0,78,47 open=1,1,1 darts=21,18,18 busts=0,0,0",
        "301,straight,double,4 ; 1 ; 0 ; D20, T17, T17 | T8, S15, S13 | S16, T15, S6 | D20 ; phase=finished current=0 round=4 reason=victory ranks=1 remaining=0 open=1 darts=10 busts=0",
        "501,straight,straight,20 ; 2 ; 0 ; T20, T18, T17 | DB, T18, S20 | T20, T19, T18 | SB, SB, MISS |  | MISS, D20, DB | S11, S15, S3 | S5 | S16, D10, T6 | S5, T17, S14 | T14, S14, T11 | D2, D7, T17 | S2, D2, S12 | S13, D9, D4 | D12, D20 ; phase=finished current=0 round=8 reason=victory ranks=1,2 remaining=0,54 open=1,1 darts=20,19 busts=1,0",
        "301,straight,double,20 ; 1 ; 0 ; DB, T19, T19 | D2, D2, DB | D15, S16, T11 |  | S12, T2, T6 | T8, S19 | D7, S2, T1 | D12 ; phase=finished current=0 round=8 reason=victory ranks=1 remaining=0 open=1 darts=18 busts=2",
        "301,straight,double,13 ; 2 ; 0 ; MISS, MISS, T20 | DB, SB, D20 | D20, T20, T10 | T20, S6, D1 | T19, D5, T10 | SB, D6, T6 | D9 | D9, T18 |  | D14, T15 | D18 | T7 | T5 | S12, D15 ; phase=finished current=1 round=7 reason=victory ranks=2,1 remaining=14,0 open=1,1 darts=12,16 busts=3,2",
        "701,double,straight,20 ; 1 ; 0 ; SB, D16, S5 | T20, SB | T18, T19, S5 | T20, T17, DB | S20, T20, D20 | T19, D6, S16 | T11, S15, D11 | MISS, T5, T15 |  | D8, S11 ; phase=finished current=0 round=10 reason=victory ranks=1 remaining=0 open=1 darts=25 busts=1",
        "301,straight,straight,20 ; 1 ; 0 ; S20 | S1, T20, S1 | T18, D8, T18 | D15, S3, D12 | D15, T11 | T20 | S7, S7, D12 ; phase=finished current=0 round=7 reason=victory ranks=1 remaining=0 open=1 darts=16 busts=2",
        "501,double,straight,23 ; 1 ; 0 ; S20 | D1, T20, SB | S1, T20, T20 | D20, T19, D20 | D15, S14, T6 | S2, S4, D1 | D17, T14, D5 ; phase=finished current=0 round=7 reason=victory ranks=1 remaining=0 open=1 darts=19 busts=0",
        "301,double,straight,20 ; 2 ; 0 ; D20, T17, S5 | T20, T20, D1 | D20, MISS, D7 | T20, T20, T12 | D9, D10, D11 | D12, D20, T6 | S15, D15, T17 | D8 ; phase=throwing current=1 round=4 reason=- ranks=2,1 remaining=91,45 open=1,1 darts=12,10 busts=1,0",
        "301,straight,straight,20 ; 4 ; 0 ; SB, MISS, DB | D20, D20, S5 | DB, D20, T19 | S1, D20, D20 | D20, S1, S1 | DB, T10, D2 | D7 | T17, S9, D15 | S1, SB, D6 | T4, S2, S20 | T9, MISS, DB | T4, T13, S9 | S3 | S11 | D6, T15, D3 ; phase=finished current=2 round=4 reason=victory ranks=4,3,1,2 remaining=143,87,0,70 open=1,1,1,1 darts=10,10,10,9 busts=0,0,0,0",
        "301,straight,straight,nil ; 1 ; 0 ; S5, T20, T20 | S3, D2, D16 | T10, D1 | S11, S1, T20 | DB | S18, S15 ; phase=finished current=0 round=6 reason=victory ranks=1 remaining=0 open=1 darts=14 busts=1",
        "501,double,double,1 ; 2 ; 0 ; DB, T19, S1 | D20, DB, S20 | ; phase=finished current=1 round=1 reason=roundLimit ranks=2,1 remaining=393,391 open=1,1 darts=3,3 busts=0,0",
        "301,double,straight,7 ; 1 ; 0 ; D20, T20, T18 | DB, MISS, S5 | T16, D13, D9 ; phase=finished current=0 round=3 reason=victory ranks=1 remaining=0 open=1 darts=9 busts=0",
        "301,straight,straight,20 ; 3 ; 0 ; T20, T17, DB | DB, MISS, D20 | S1, D20 | S6, MISS, T11 |  | SB, DB, T20 | D9, T9, T1 | DB, MISS, T20 | S6, S19, S2 | T19 | T16, D17, S15 | D7, S8 | S3, T18 | T1, S13 | S13, SB, T4 | MISS, S1, T3 | S2, T16 | D2, D11 ; phase=finished current=2 round=6 reason=victory ranks=3,2,1 remaining=43,4,0 open=1,1,1 darts=15,13,15 busts=2,2,0",
        "701,straight,double,29 ; 4 ; 0 ; D20, MISS, S5 | D20, S5, DB |  |  | S5, T19, D20 | D20, SB, D20 | T20, SB, SB | T19, S1, S20 | S5, T19, S1 ; phase=turnComplete current=0 round=3 reason=- ranks=1,2,3,4 remaining=491,501,591,623 open=1,1,1,1 darts=9,6,3,3 busts=0,0,0,0",
    ]
}
