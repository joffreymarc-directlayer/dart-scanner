import Testing
import DartCore
import DartGames
import DartTestSupport

/// High Score against the reference implementation that computed the vectors of GAMES.md (§2.11): thirty
/// random games played by that reference, with the state it reached. The games were generated once with a
/// fixed seed; the script of a line is the journal, in the notation of the vectors.
///
/// A line is `rounds ; players ; seed ; journal ; expected state`.
@Suite struct HighScoreReferenceTests {
    @Test(arguments: HighScoreReferenceTests.games)
    func theGameReachesTheStateOfTheReference(_ line: String) throws {
        let (options, players, seed, script, expected) = try Self.parts(line)
        let first = try #require(options.first)
        let rounds = try #require(Int(first))
        var match = try GameRegistry.standard.match(.highScore, ["rounds": .int(rounds)], players: players, seed: seed)
        let outcomes = match.play(script)
        // The reference only writes the inputs it accepts.
        let allAccepted = outcomes.allSatisfy { $0.isAccepted }
        #expect(allAccepted, "\(line)")
        Self.expectCommon(match, expected, line)
        let rows = match.snapshot.players.indices
        #expect(rows.map { match.fact($0, "points") } == Self.numbers(expected["points"]).map { .int($0) }, "\(line)")
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
        "8 ; 3 ; 0 ; SB, D17, T5 | T14, MISS, D3 | T19, S15, T20 |  | T2 | S2, D2, DB | D4 | T19, S18, D1 | D14, S19, S13 |  | S16 ; phase=throwing current=1 round=4 reason=- ranks=3,2,1 points=82,147,248",
        "8 ; 4 ; 0 ; S7, T2, S9 | S16, D20, T3 | S1, D8, D17 | MISS, S10 | S1, S14, S5 | T20, DB, T6 | S16, DB ; phase=throwing current=2 round=2 reason=- ranks=3,1,2,4 points=42,193,117,10",
        "2 ; 4 ; 0 ; T8, D3, D2 | T14, S13, T17 | T14, T13, T7 | D15, D18, T14 | D6 | T20, S15, S11 ; phase=turnComplete current=1 round=2 reason=- ranks=4,1,3,2 points=46,192,102,108",
        "8 ; 1 ; 0 ; MISS, T8, D9 | S10, S6, T13 |  | D5 | D15, SB, S2 | S5, D1, T2 | T3 | D18, S7, T8 | ; phase=finished current=0 round=8 reason=roundLimit ranks=1 points=253",
        "18 ; 2 ; 0 ; T8, MISS, MISS | T18, T9, D4 | T15, S13 | MISS, S7, S10 | D17, D10, T8 | ; phase=throwing current=1 round=3 reason=- ranks=1,2 points=160,106",
        "1 ; 1 ; 0 ; T1, D1, S13 | ; phase=finished current=0 round=1 reason=roundLimit ranks=1 points=18",
        "1 ; 2 ; 0 ; MISS, D4, S16 | D14, MISS, S20 | ; phase=finished current=1 round=1 reason=roundLimit ranks=2,1 points=24,48",
        "1 ; 1 ; 0 ; T20, D12 | ; phase=finished current=0 round=1 reason=roundLimit ranks=1 points=84",
        "2 ; 3 ; 0 ; D1, D9, D17 | S8, D10 | S13, S12, S18 | DB | D8, T6, D14 | T11, D19, T20 | ; phase=finished current=2 round=2 reason=roundLimit ranks=2,3,1 points=104,90,174",
        "20 ; 1 ; 0 ; | T18, S9, T4 | MISS, T20, MISS | T4, S8 | ; phase=throwing current=0 round=5 reason=- ranks=1 points=155",
        "1 ; 1 ; 0 ; D10, T8, S18 | ; phase=finished current=0 round=1 reason=roundLimit ranks=1 points=62",
        "2 ; 4 ; 0 ; S3 | D19, D19 | D4, S6, T8 | T16, S7, T17 | D19, D1, T8 | T17, T20, SB | S10, T6, D18 | T14, T9, T17 | ; phase=finished current=3 round=2 reason=roundLimit ranks=4,2,3,1 points=67,212,102,226",
        "2 ; 1 ; 0 ; T15 | DB, S11, D8 | ; phase=finished current=0 round=2 reason=roundLimit ranks=1 points=122",
        "1 ; 1 ; 0 ; T4, T14, T10 | ; phase=finished current=0 round=1 reason=roundLimit ranks=1 points=84",
        "8 ; 3 ; 0 ; T19, T3, D16 | T13, S3, MISS | D17 | S16, S20, S10 | T1, D15, S1 | T8, S15, T13 | T20, D1, S17 | T20, T7, S14 | DB, D10, S12 | SB | T4, T20, D9 | MISS, T1, T11 | D2, S12, T14 | S9, S18, S10 | S6, S6, D2 | D11, D2, T1 | D3, D14, D12 | D18, S8, T5 | S1, S13, S7 | T20, T14, T7 |  | ; phase=throwing current=0 round=8 reason=- ranks=2,1,3 points=356,479,305",
        "1 ; 2 ; 0 ; S12, T7, T17 | T20, T19, S10 | ; phase=finished current=1 round=1 reason=roundLimit ranks=2,1 points=84,127",
        "4 ; 3 ; 0 ; T16, S18, D20 | S7, S3, S1 | T20, D13, T11 | D4, D17, D17 | S17, T12, T3 | T9, T10, T20 | D18, D12, T17 | D20, D5, MISS | S7, D2, S2 | S10 ; phase=throwing current=0 round=4 reason=- ranks=1,3,2 points=303,123,249",
        "2 ; 4 ; 0 ; S20, S12, MISS | S1, T1, T19 | D9, T7, S2 | D3, D4, T6 | D13 | T6, D2, T14 | S4, D17, D20 | MISS, S5, T14 | ; phase=finished current=3 round=2 reason=roundLimit ranks=4,1,2,3 points=58,125,119,79",
        "3 ; 4 ; 0 ; S13, T17, T5 | S8 ; phase=throwing current=1 round=1 reason=- ranks=1,2,3,3 points=79,8,0,0",
        "1 ; 3 ; 0 ; T20, S1, S9 | S1, T15, S5 | T5, D18, S11 | ; phase=finished current=2 round=1 reason=roundLimit ranks=1,3,2 points=70,51,62",
        "3 ; 4 ; 0 ; T10, D10, S3 | T19, S7, S2 | T15, S16, S3 | MISS, D18, S4 | T14, S1, T3 | D10, S20, D10 | T13, T3 | D18, MISS, S8 | S11, T11, S13 | D19, S15, S4 | T1, S8, D10 | T1, T3, S6 | ; phase=finished current=3 round=3 reason=roundLimit ranks=2,1,3,4 points=162,183,143,102",
        "8 ; 3 ; 0 ; D4 | DB, D6, MISS | T13, D12, D1 | D1 | D8, D9, S17 | S4, D17, T9 | S17 | T11, T20, D12 | D4, D16, S15 | S17, MISS, D1 | T5, S2 | T3 ; phase=throwing current=2 round=4 reason=- ranks=3,1,2 points=46,247,194",
        "2 ; 3 ; 0 ; D9, T5, D3 | S5, D10, S10 | T20, T14, T20 | S19, SB, S15 | S1, T18, S13 | S13, S7, D6 | ; phase=finished current=2 round=2 reason=roundLimit ranks=3,2,1 points=98,103,194",
        "2 ; 2 ; 0 ; | T20, S19, D12 | D6, T20, S15 | D2, S7, S4 ; phase=turnComplete current=1 round=2 reason=- ranks=2,1 points=87,118",
        "17 ; 2 ; 0 ; D18 | S19, T9, S9 | S13, S6, D3 | D6, T20, T20 | D8, MISS, D15 | D2, T19 | D4, D16, S11 | T11, DB, T12 | D18, S17, D18 | T9, D10, S20 | T15, D12 | S5, DB, D10 | D1, T20 |  | S2, T14, T5 | T6 | T6, T16, T11 | T5, D2, D6 | S12, T11, T20 | T11, T2, T1 | S8, T3, D13 | T13, T11, T20 | S17, T8, D8 | S10, D9 | D16, T12, D5 | ; phase=throwing current=1 round=13 reason=- ranks=1,2 points=819,760",
        "2 ; 2 ; 0 ; T20, D20, D13 | S18, T6, D13 | S14 | T19, S15, S2 | ; phase=finished current=1 round=2 reason=roundLimit ranks=1,2 points=140,136",
        "16 ; 1 ; 0 ; S11, T2, S3 | D3, D13, S16 | T16, S20, S8 | S14, T20, D18 | ; phase=throwing current=0 round=5 reason=- ranks=1 points=254",
        "2 ; 1 ; 0 ; T20, T8, D2 |  | ; phase=finished current=0 round=2 reason=roundLimit ranks=1 points=88",
        "3 ; 2 ; 0 ; S18, S18, T14 | S5, D20, S2 | D16, T11, T5 | S9, S16, D12 | T19, T19, T5 | S4, D7, S19 | ; phase=finished current=1 round=3 reason=roundLimit ranks=1,2 points=287,133",
        "2 ; 2 ; 0 ; D5, T4, T16 | MISS, D20, T8 | D10, S10, T20 | MISS | ; phase=finished current=1 round=2 reason=roundLimit ranks=1,2 points=160,64",
    ]
}
