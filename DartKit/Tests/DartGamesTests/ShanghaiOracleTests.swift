import Testing
import DartCore
import DartGames
import DartTestSupport

/// Cross-check of Shanghai against the Python reference that computed the vectors of GAMES.md: 50 random journals,
/// 1 to 8 players, both variants, 1 to 20 rounds. The reference recorded a hash of the state after every input
/// (points, ranks, phase, current player, round) and the final state; 14 games end on a Shanghai.
@Suite struct ShanghaiOracleTests {
    private let registry = GameRegistry.standard

    /// "FR|2|2|0|5/13/8|3.1.2": turn state, points, ranks.
    private func state(_ match: GameMatch) -> String {
        let points = match.snapshot.players.map { row -> String in
            if case .int(let value)? = row.facts["points"] { return String(value) }
            return "?"
        }
        return "\(KillerTestOracle.turnState(match))|\(points.joined(separator: "/"))|\(KillerTestOracle.ranks(match))"
    }

    @Test func referenceJournals_sameStateAfterEveryInput() throws {
        let lines = Self.journals.split(separator: "\n")
        #expect(lines.count == 50)
        var shanghais = 0
        for (index, line) in lines.enumerated() {
            let fields = line.split(separator: ";", omittingEmptySubsequences: false).map(String.init)
            try #require(fields.count == 6, "line \(index)")
            let options: GameOptions = ["rounds": .int(try #require(Int(fields[1]))), "variant": .string(fields[2])]
            var match = try registry.match(.shanghai, options, players: try #require(Int(fields[0])))
            var states = KillerTestOracle.emptyHash
            for input in try KillerTestOracle.inputs(fields[3]) {
                let outcome: InputOutcome
                switch input {
                case .dart(let hit): outcome = match.throwDart(DartRecord(hit: hit))
                case .endTurn: outcome = match.endTurn()
                }
                #expect(outcome.isAccepted, "line \(index): the reference only recorded accepted inputs")
                KillerTestOracle.mix(&states, state(match) + ";")
            }
            #expect(state(match) == fields[5], "line \(index): final state")
            #expect(String(states, radix: 16) == fields[4].drop { $0 == "0" }, "line \(index): a state differs on the way")
            if match.snapshot.finishReason == .victory { shanghais += 1 }
        }
        #expect(shanghais == 14)
    }

    /// players;rounds;variant;journal;states;final state
    private static let journals = """
8;7;lite;T1,S6,S18|SB,T1,T1|T1,SB,D20|D8,D1,D1|T20,D1,D1|S14,S20,D1|D1,T1,S18|T1,S1,D1;16e196b282842600;FV|7|1|3|4/6/4/4/5/3/6/6|5.2.5.5.4.8.2.1
7;7;traditional;S18,D1|S1,D20,T18|D1,S1,MISS|T20,DB,D20|D6,S1,D6|T1,D1,DB;211bf95d04cca246;C-|5|1|3|2/1/3/0/1/5/0|3.4.2.6.4.1.6
7;3;lite;S1,T20,S1||S18,T1|T1,D1,T3|D1,T1,S20|DB,D1,S1|D1,D1,T1|T2,D15,T2|T1,S2|D2,D2,T1|S2,S2,D2|T2,S2,T2|D2,S15|S17,T2,S2|D15,T19,S17|S3,D3,D3|T3,S3,D3;5d7f0cdd7c440877;FV|2|3|3|23/17/30/13/20/9/17|2.4.1.6.3.7.4
5;20;lite;T20,T1,S1|S1,DB,T1|T1,S18,T1|T18,S19,T2|T1,S1,T1|S2,S15,D2|D2,T17,T17|T2,S17,D17|S17,T2,D15|DB,T15,S5|D3,MISS,T19|S3,T9,DB|S17,S3,D10|T19,S3,S3|T3,S19,D3|S13,S4,D13|MISS,T4,S13|T13,SB,S4|D4,S4,T7|D18,T4|T5|D1,S5,T16|T5,S5,S5|T5,S12,D5|S20,D12,T5;41629ea0c21d52e0;C-|4|5|3|49/36/56/62/68|4.5.3.2.1
2;3;traditional;T1,S18,S18|D1,D1,T18|D2,S17,S17|T2,SB,T2|S20,T19,T3|T3,MISS,S18|;aa600bdd9c205819;FR|1|3|0|16/25|2.1
4;2;traditional;S18,S18,S20|T1,T1,D1|S20,D1,S1|T19,D18,S7|MISS,S14,D7|T2,D2|D15,MISS,D2|T2|;c4a46a53eb931ef2;FR|3|2|0|0/18/7/6|4.1.2.3
3;1;traditional;S7|D18,D10,D1|T1,SB,T1|;9e37bfe5d600176f;FR|2|1|0|0/2/6|3.2.1
4;2;lite;MISS,SB,T1|DB,D8,D1|D20,SB,T1||DB,S2,S2|S2,D2,S15|T2,T2,T9;d53aeaa5c2fdfb0c;C-|2|2|3|7/10/16/0|3.2.1.4
1;5;lite;S1,S1,T18|T17,T15,T2|T1,D4,D3|SB|D5,S20,D5|;d84dcb8457e49eb0;FR|0|5|0|44|1
8;7;traditional;D1,D1,T1||D20,T20,T1|S1,D1,S1|D1,D1,D1|SB,T18,T1|S18,D1,D1|S1,T1|T2,S2,D2;da94f20e51a6ba6f;FV|0|2|3|19/0/3/4/6/3/4/4|1.8.6.3.2.6.3.3
4;7;traditional;D4,D1,D1|T1,T15,S20|S1,S1,MISS|D1,D1,S7|S20,S15,S2|D17,D2,D15|MISS;4fa604e6c06db7ab;T-|2|2|1|6/7/2/4|2.1.4.3
7;12;lite;T1,MISS,MISS|T1,DB,T18|D19,SB,T20|T8,MISS,T1|S20,T18,D3|MISS,T1,S20|T1,D1|S17,D15|S17|D15,T17,T11|DB,T2,T2|T2,D13,S2||S17,S9,DB|D3,T19,S3|T11,SB,S12|D3,S3,T3;73bab5100d5f1ae6;FV|2|3|3|19/6/23/15/10/4/7|2.6.1.3.4.7.5
8;2;traditional;D20,D18,S3|SB,T1,D3|T1,D1,S1;97a199ad1d5609d5;FV|2|1|3|0/3/6/0/0/0/0/0|3.2.1.3.3.3.3.3
2;7;lite;D1,T20,S1|D1,S1,T1;0eeb3197f0ab62f2;FV|1|1|3|4/6|2.1
1;7;lite;MISS|T17,D2,D20|D19,T3,S3|S5,D5,S18|T20,D5,D13|S6,D6,S6|T16,DB,D7|;1cb2f6362f250cd5;FR|0|7|0|85|1
8;20;traditional;S1,T1,S1|S18|D1,S1,SB|S1,S18|T20,S20,T1|T16,S16,T18|S1,D20,D18|D2,S13,D1|T2,D15,S17|S15,T15,T17|S2,S17,D2|D2,S15,T15|S2,T18,S2|DB,S15,T2|S2,S2,D15|S15,DB,T2|D3;53a50325853f28d2;T-|0|3|1|17/0/9/5/7/6/5/8|1.8.2.6.4.5.6.3
6;20;traditional;T20,S8,T1|T1,S1,D1;2b3780a71ac62597;FV|1|1|3|3/6/0/0/0/0|2.1.3.3.3.3
5;1;lite;T1,S20,S1|D18,MISS,D18|D18,DB,S18|D18|D1,D18|;498aceaf2cf90b8f;FR|4|1|0|5/2/2/1/3|1.3.3.5.2
6;5;traditional;T1,S1,S1|D18,T1,SB|S1,D1,D5|S20,T1,T1|D1,D1,S1|S18,D6|S2,T2,D12|D14,D10|D2,D2,S2|S2,T2,D17|T2,D3,S2|D2,S15,D17|D3,D16,T9|D19,D2,D3|S3,S3,S19|S17,S3,S3|SB,S3,D19|T17,S3,T3|T15,D4,S4|S4,S18,T4|MISS,D4,MISS|D4,S19,S4|S18,S4,T18|D4,D11,T4|T20,T5,S5|D5,S1,D12|S5,S15,S3|T5,D5,T5|S5;f38780ac902a1e94;T-|4|5|1|51/35/32/72/25/36|2.4.5.1.6.3
6;1;lite;D18,D1||T18,T1,T11||T1,T20,D1|T10|;a902af23af2e75b9;FR|5|1|0|3/0/4/0/6/0|3.4.2.4.1.4
7;5;lite;D18,D1,D1|T19,D1,T18|S20,SB,SB|T1,S1,T1|S1,T1,D1;f54176e9a535f113;FV|4|1|3|5/3/1/7/6/0/0|3.4.5.2.1.6.6
6;1;traditional;D18,T1,T20|D18,DB,S1|D1,T1,D1|D10,S19,D18|T1,S1,D16|S20,T1,T20|;0973b2aabbcf2791;FR|5|1|0|3/1/7/0/4/3|3.5.1.6.2.3
6;7;lite;DB,T1,S16||S1,S18|S20,S7,D18|S1,S18,T1|S1,T18,D18|D15,T2,S13|S15,D2,T17|S2,S2,MISS|D2,S2,SB|S13,S2,MISS|T17,T4,T15|T3,T3,D15|T19,S19,D3|T3,D17,S3|D3,T19,S3|S3,SB,S17|D3,D3,T3|S4,T4,T4|S4,S4,D4|D13,S18|T4,T4,D13|D13,D17,DB|T4,D13,T4|SB,T5,D18|S5,S5,S5|D10,S11;0c81ae1f2e78a4c7;T-|2|5|2|72/51/29/48/17/56|1.3.5.4.6.2
8;7;lite;SB,T1,S20|T1,S1,D1;b16959fa19936d52;FV|1|1|3|4/6/0/0/0/0/0/0|2.1.3.3.3.3.3.3
2;5;lite;S1,T1,D7|S18,D1,T18|D15,D2,D17|D2,S17,S2|T3,D17,S3||D4|SB,T4,D4|T5,D5,T20|T12,D5,D12|;165e01838c66a461;FR|1|5|0|65/52|1.2
2;5;traditional;D1,D1,S1|D12,T1,S18|D2|S2,D17,S15|S18,S3|T3,T3|S18,T18,S18|S18,DB,S4|D20,S5,T12|S5,T12,S12|;a21eca7b50f2f572;FR|1|5|0|17/32|2.1
6;7;traditional;D4,T1,S1|S12,T20,D9|S18,T1,T3|MISS,D19,T1|S1,T20,DB||T15,D2,D2|T19,T2,S17|S2,D2,T19|D17,T2,D15|S14,D8,S2|D2,S2,D2|S3,S3,T3|S3,D3,D4|S17|S19,T17,D3|MISS,D3,S19|MISS,S17,S7|DB,S4,D4|D18,S4,S4|T17,S4,T4|T1,T4,D4|||S15,D12,S12|S20,D5,SB|D16,S5,D5|D20,D20,T17|T5;76b190d1875b7c76;T-|4|5|1|39/33/40/35/24/10|2.4.1.3.5.6
3;5;lite;S1,S1,D18|T1,SB,S18|D3,T10,D1|T2,T2,T17|S2,S2,D17|T17,MISS|T3|D3,D3,T17|T3,D17,S3|S4,S4,T4|S4|DB,T18|D20,T5,S5|D20,D5,T5|;ee15a5a97a803166;T-|2|5|0|71/59/23|1.2.3
8;7;lite;T1,S1,S1|T1,S20,T17|S18,S1,T1|T1,T18,D1|S1,D1|S19,D20,DB||D18,T3,S20|S2|SB,D2,T2|D2,S15,S17|D2,S17,D15|T2,T2,MISS|S2,S7,D17|D6,S2,T2|S5,D2,D4|D3,D17,S17|T19,S20,S3|S1,MISS,T3|T19,S3,SB|T19,DB,D3|D17,D3,D19|S3,T3,MISS|T19,SB,T3|S4,T18,S4|T4,S11||S13,T18,SB|T20,D4,T4|D4,T4|T4,T4,T18|;3e7b0c4a23276831;T-|7|4|0|31/32/22/28/44/37/48/18|5.4.7.6.2.3.1.8
7;7;lite;D6,S20,T11|T13,S1|T18,T1,D1|T1,S18,D20|T1,S11,T1|D18,S1,S1|SB,S9,S1|D2,D2|T16,T15,T15|D17,T2,MISS|T2,SB,D2|;ed5b56c060b460b2;T-|4|2|0|9/5/14/15/6/3/1|3.5.2.1.4.6.7
1;2;traditional;T18,DB,MISS|T4,MISS,D2|;e51ee315f7b32a17;FR|0|2|0|4|1
8;20;lite;T1,D1,T1|D20,MISS,T6|D1,T1|S1,D14,S6|D1,T20,SB|S1,S20,T6|D20,SB,S20|T1,D1,D20|T17,S2,D2|D2|T2,T6,S2|T15,MISS,T2|D3,D2,D2|D15,S2,T2|D2,D14,S2|D17,T2,S17|;3387bfb418e66c4b;T-|0|3|0|16/5/13/9/11/12/8/16|1.8.3.6.5.4.7.1
1;7;lite;S16|MISS,T9,SB|DB,D16,T19|T4,D13,S13|SB,D5,D12||S7,D7,SB|;aa06652f5d30a34c;FR|0|7|0|59|1
8;2;lite;D19,T1,D4|S20,D1,T1|S14,S1,DB|DB,S1,D1|S1,D1,SB|MISS|S9,S1,S1|T1,D1,S17|MISS,T2,S2|S2,D5,T15|T5,S15,D17|D2,T15,D15|D13|;b10852b819327fa7;T-|5|2|0|11/10/5/11/3/0/2/5|1.3.4.1.6.8.7.4
5;2;lite;SB,T1,T11|S1,D1,D1|T17,D1,D1|D1,S20,D1|S18|S2,S12,D2|S2,S2,S13|D4||D17,D2,D2|;65c40f22ab8759d4;FR|4|2|0|9/9/4/5/11|2.2.5.4.1
8;2;traditional;D20,S1,D1|DB,SB,T1|D8,D19,MISS|T1,T1,T18|S1,S1,S20||D20,D1,T20|D5,T7,DB|T7,D1,T2|T2,T12|S2,S15,D2|D2,D2,D2|D2,S2|S2,DB,T10|D17,S18,T8|S2,D2,SB|;75bbf84b96555f84;FR|7|2|0|9/9/6/18/8/2/2/6|2.2.5.1.4.7.7.5
1;7;traditional;T1,T1,T8|T2,MISS,S2||T13,S4,T18|T5,D1,T20|D6,D6,T6|S7,T7,D7;d91a4ce54660eae9;FV|0|7|3|117|1
1;5;traditional;SB,S1,T1|S17,T5,T2|S3,S3,T19|S4,MISS,SB|S5,MISS,D5|;902f87e2cef96315;FR|0|5|0|35|1
5;2;traditional;T1,T1,T1|MISS,D1|D12|S1,T1,S1|D14,T1,T1||S2,T2,S2|T2,D2,S2;297ff995d5cb15d4;FV|2|2|3|9/12/12/5/6|3.2.1.5.4
5;7;lite;D1,D12,S1|MISS,D1,D1|SB,S1,MISS|T1,D2,D1|S1,D1,S20|T2,D2|S2,T17,S2|T3,S2,S2|D2,S19,SB||D20,S3|S17,T3,D3|D3,D3,S19|T3,T3,T17|S19,T3,D3||D13,S4,T4|T13,S18|S4,S4,D4|T4,S13,D4|D20,T12,D12|T5,DB,T5|T20,S20|S5|S1,D5,MISS|S13,D2,D11|S11,S10,D6|T3,D6,SB|D10,T6,T13|S10,D16,DB;e0c0e8b653c566b6;C-|4|6|3|37/96/50/81/62|5.1.4.2.3
8;2;lite;S20,T1,D1|S20,D1,D20|D18,S1|D1,DB,S1|S20,D1,T20|T1,T1,D1|D20,T1,T11|DB,S20|D2,T2,D2|T2,SB,SB|S2,S2,D15|T2,S2|S2,S2,D16|T17,S2,SB|T2,S2,S17|S2,T2,D15|;439e057d03ccdb6e;FR|7|2|0|20/10/8/11/8/12/14/11|1.6.7.4.7.3.2.4
2;12;lite;|D1,T18,D1|S2,T12,T2|T2,S2,D2;b579f716e895af7c;FV|1|2|3|8/17|2.1
5;3;traditional;D1,D1,D18|D1|D1,S20,T1|S20,D1,S2|T1,S18,T1|S2,T2,S14|S2,S2,D2|S12,T17,T2|T2,T2,D15;80f2a9dae586c7bd;C-|3|2|3|12/10/11/14/6|2.4.3.1.5
3;7;lite;D1,D1,S1|S1,S18,SB|S1,T1,S18|T2,D17,MISS|S15,D17,T2|T17,D12,T2|T3,D3,T3|T14,S3,S3|D19,S3,DB|MISS,S18,S4|S4,S4,D12|T8,T4,S4|S5,D20,DB|DB,T5,D12|D20,D5,MISS|S13,T10,S10||D6,D6,S6|D14,D16,S16|SB,T16,S16|S16,D7,S19|;9d493c51564a3b94;FR|2|7|0|87/60/108|2.3.1
6;20;lite;S4,T18,T1|T20,S18,S1|D12,D20,T1|S1,MISS,D18|SB,T1,S9|T1,S20,D1|T2,S2,S15|T2,S2,T2|S17,SB,S2|S2,D2,D2|D15,S2,T2|D2,T2,D2|S3,SB,D17|T3,MISS|D6,D3,T17|S3,D17,S3||S19,D3||S15,T4,T13|T13,D3,T18|S4,T4,D18|T15,T4,T6|T4,SB,S13|D12;ce37df1428b9fa50;T-|0|5|1|25/42/25/41/25/45|4.2.4.3.4.1
4;2;lite;T18,T10,T1|S18,S1|S1,T20,T20|T1,D1,T1|D2,D2,D2|T2,T2,T2|D2,S2,T2;9e3c3eeedf11643f;FV|2|2|3|16/20/15/8|3.2.1.4
3;1;traditional;D1,S18,S1|D20,S5,D1|S6,S1,S1|;0791e1d0b3a75a52;FR|2|1|0|3/2/2|1.2.2
4;5;traditional;D1,S18,D1|S20,D1,T1|D20,D20,S20|S1,DB,D3|T2,DB,S2|T2,T2,D2|D2,D2|T18,D2,T2|D9,T19,S3|D3,S17,T18|D17,SB,S19|S19,T11,D3|T13,DB,D4|S4;3270be4fd8c087f2;T-|1|4|1|23/31/8/17|2.1.4.3
8;5;lite;T18,D20,T20|D20,D1,S20|T1|D18,S1,SB|T1,T1,T5|T1,S1,T20|MISS,T5,T15|D1|T17,D2,S8|D17,S17,T2|S17,S2,D2|T2,MISS,D2|D20,D2,DB|S15,S2,S2|S15,S18,SB|S2,S2|T14,S3,MISS|T3,D19,D3|S3,D3,D3|T3,S14,D3|T3,D15,DB|T3,D3,MISS||DB,T3,T3|S18,S4,S14|T4,D4,SB|S4,D4,D20|;617eb3070e4b7fa9;T-|3|4|0|20/52/38/27/19/26/2/24|6.1.2.3.7.4.8.5
8;7;lite;D1,T1,S1;a2558628e378e1aa;FV|0|1|3|6/0/0/0/0/0/0/0|1.2.2.2.2.2.2.2
"""
}
