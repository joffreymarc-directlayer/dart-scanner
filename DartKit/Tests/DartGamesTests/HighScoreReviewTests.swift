import Testing
import DartCore
import DartGames
import DartTestSupport

/// High Score rewritten from GAMES.md §8 alone, as an oracle: points of every bed, the turn total and its events
/// (§2.10), the end at the round limit only, the ranking with ties.
private struct ReviewHighScore: CommonReviewRules {
    let roundLimit: Int?
    var points: [Int]
    var darts: [Int]

    func isOut(_ player: Int) -> Bool { false }

    mutating func turnBegins(player: Int, round: Int, random: inout SeededRandom, events: inout [GameEvent]) {}

    mutating func dart(_ hit: Hit, player p: Int, round: Int, volley: [Hit], events: inout [GameEvent]) -> CommonReviewVerdict {
        darts[p] += 1
        points[p] += hit.points
        if hit == .miss { events.append(.noEffect(player: p)) }
        return .goOn
    }

    mutating func turnEnds(player p: Int, volley: [Hit], events: inout [GameEvent]) {
        let total = volley.map(\.points).reduce(0, +)
        events.append(.turnScored(player: p, points: total))
        if total == 180 { events.append(.oneEighty(player: p)) }
        if (100...179).contains(total) { events.append(.highTurn(player: p, points: total)) }
    }
}

@Suite struct HighScoreReviewTests {
    /// 300 random games of 1 to 20 rounds, with refused inputs, undo and corrections: after every operation the
    /// engine agrees with the oracle on the facts, ranks, turn, captions and summary, and on every event.
    @Test func independentModel_randomGamesWithEdits_agreeAfterEveryOperation() throws {
        var random = SeededRandom(seed: 0x415C)
        var failures: [String] = []
        var finished = 0
        for _ in 0..<300 where failures.isEmpty {
            let rounds = random.nextInt(below: 2) == 0 ? 1 + random.nextInt(below: 3) : 1 + random.nextInt(below: 20)
            let players = 1 + random.nextInt(below: 8)
            let make: (inout SeededRandom) -> ReviewHighScore = { _ in
                ReviewHighScore(roundLimit: rounds, points: Array(repeating: 0, count: players), darts: Array(repeating: 0, count: players))
            }
            var match = try GameRegistry.standard.match(.highScore, ["rounds": .int(rounds)], players: players)
            var machine = CommonReviewMachine(players: players, seed: 0, make: make)
            for _ in 0..<(30 + random.nextInt(below: 200)) {
                let operation = CommonReviewOperation.random(match.phase, &random) { random in
                    random.nextInt(below: 3) == 0 ? .treble(20) : Hit.all[random.nextInt(below: Hit.all.count)]
                }
                let outcome = operation.apply(to: &match)
                switch operation {
                case .dart(let hit):
                    let events = machine.apply(.dart(hit))
                    if outcome?.isAccepted != (events != nil) || (events.map { outcome?.events == $0 } == false) {
                        failures.append("\(hit): \(String(describing: outcome)), expected \(String(describing: events))")
                    }
                case .endTurn:
                    let events = machine.apply(.endTurn)
                    if outcome?.isAccepted != (events != nil) || (events.map { outcome?.events == $0 } == false) {
                        failures.append("endTurn: \(String(describing: outcome)), expected \(String(describing: events))")
                    }
                case .undo, .replace, .remove:
                    guard let replayed = CommonReviewMachine.replay(match.entries, players: players, seed: 0, make: make) else {
                        failures.append("the journal holds an entry the oracle refuses")
                        break
                    }
                    machine = replayed
                }
                let snapshot = match.snapshot
                let model = machine.rules
                let total = machine.volley.map(\.points).reduce(0, +)
                let ranks = CommonReviewMachine<ReviewHighScore>.ranks(model.points.map { [-$0] })
                if snapshot.phase != machine.phase || snapshot.finishReason != machine.finishReason
                    || snapshot.currentPlayer != machine.current || snapshot.round != machine.round
                    || snapshot.turn.darts.map(\.hit) != machine.volley {
                    failures.append("turn \(snapshot.phase) J\(snapshot.currentPlayer + 1) round \(snapshot.round)")
                } else if snapshot.players.map(\.facts) != model.points.indices.map({ ["points": .int(model.points[$0]), "dartsThrown": .int(model.darts[$0])] }) {
                    failures.append("facts \(snapshot.players.map(\.facts))")
                } else if snapshot.ranks != ranks || !snapshot.highlights.isEmpty {
                    failures.append("ranks \(snapshot.ranks), expected \(ranks)")
                } else if snapshot.turn.summary != (machine.phase == .finished ? nil : LocalizedText(fr: "Volée : \(total)", en: "Turn: \(total)"))
                    || snapshot.turn.darts.map(\.caption) != machine.volley.map({ DartCaption(LocalizedText(verbatim: "\($0.points)")) }) {
                    failures.append("summary \(String(describing: snapshot.turn.summary)) or captions")
                }
                if !failures.isEmpty {
                    failures[failures.count - 1] += " — highScore {rounds: \(rounds)}, \(players) players: \(CommonReviewTests.journal(match))"
                    break
                }
            }
            if machine.phase == .finished { finished += 1 }
        }
        #expect(failures.isEmpty, "\(failures.joined(separator: "\n"))")
        #expect(finished > 50)
    }
}
