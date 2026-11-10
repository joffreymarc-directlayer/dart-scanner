import Testing
import DartCore
import DartGames
import DartTestSupport

/// Around the Clock rewritten from GAMES.md §6 alone, as an oracle: target, jumps capped at 20, the bull with
/// `finishOnBull`, `advancedBy` of §6.8, the victory, the optional round limit and the highlights of §6.7.
private struct ReviewClock: KillerReviewRules {
    let finishOnBull: Bool
    let jump: Bool
    let roundLimit: Int?
    var progress: [Int]
    var darts: [Int]

    var goal: Int { finishOnBull ? 21 : 20 }
    func isOut(_ player: Int) -> Bool { false }

    /// §6.3 and ARCHITECTURE.md §5.5: `progress + 1`, 25 for the bull, 0 when no target is left.
    func target(_ player: Int) -> Int {
        if progress[player] < 20 { return progress[player] + 1 }
        return progress[player] == 20 && finishOnBull ? 25 : 0
    }

    mutating func turnBegins(player: Int, round: Int, random: inout SeededRandom, events: inout [GameEvent]) {}

    mutating func dart(_ hit: Hit, player p: Int, round: Int, volley: [Hit], events: inout [GameEvent]) -> KillerReviewVerdict {
        darts[p] += 1
        let target = target(p)
        let before = progress[p]
        if target == 25, hit == .outerBull || hit == .innerBull {
            progress[p] = 21
        } else if target != 25, hit.number == target {
            progress[p] = min(20, before + (jump ? hit.multiplier : 1))
        } else {
            events.append(.noEffect(player: p))
            return .goOn
        }
        events.append(.targetHit(player: p, number: target, advancedBy: progress[p] - before))
        return progress[p] == goal ? .finish(.victory) : .goOn
    }

    mutating func turnEnds(player: Int, volley: [Hit], events: inout [GameEvent]) {}

    var ranks: [Int] { KillerReviewMachine<ReviewClock>.ranks(progress.map { [-$0] }) }

    func highlights(for player: Int) -> Set<BoardHighlight> {
        switch target(player) {
        case 0: return []
        case 25: return [BoardHighlight(zone: .bull, role: .target)]
        case let number: return [BoardHighlight(zone: .sector(number), role: .target)]
        }
    }
}

@Suite struct AroundTheClockReviewTests {
    private func difference(_ match: GameMatch, _ machine: KillerReviewMachine<ReviewClock>) -> String? {
        let snapshot = match.snapshot
        let model = machine.rules
        if snapshot.phase != machine.phase || snapshot.finishReason != machine.finishReason {
            return "phase \(snapshot.phase) \(String(describing: snapshot.finishReason)), expected \(machine.phase)"
        }
        if snapshot.currentPlayer != machine.current || snapshot.round != machine.round {
            return "player \(snapshot.currentPlayer) round \(snapshot.round), expected \(machine.current) round \(machine.round)"
        }
        if snapshot.turn.darts.map(\.hit) != machine.volley { return "volley \(snapshot.turn.darts.map(\.hit))" }
        if snapshot.roundLimit != model.roundLimit { return "roundLimit \(String(describing: snapshot.roundLimit))" }
        let facts = model.progress.indices.map { player -> [String: FactValue] in
            ["progress": .int(model.progress[player]), "target": .int(model.target(player)), "dartsThrown": .int(model.darts[player])]
        }
        if snapshot.players.map(\.facts) != facts { return "facts \(snapshot.players.map(\.facts)), expected \(facts)" }
        if snapshot.ranks != model.ranks { return "ranks \(snapshot.ranks), expected \(model.ranks)" }
        let highlights: Set<BoardHighlight> = machine.phase == .finished ? [] : model.highlights(for: machine.current)
        if Set(snapshot.highlights) != highlights || snapshot.highlights.count != highlights.count {
            return "highlights \(snapshot.highlights)"
        }
        // ARCHITECTURE.md §5.6: a progress bar on `goal`.
        if snapshot.players.contains(where: { $0.meter?.maximum != model.goal || $0.meter?.value != model.progress[$0.player] }) {
            return "meters \(snapshot.players.map(\.meter))"
        }
        if snapshot.turn.darts.contains(where: { $0.caption == nil }) { return "a dart without caption" }
        return nil
    }

    /// 300 random games with every option, refused inputs, undo and corrections: after every operation the engine
    /// agrees with the oracle, events included (`advancedBy` capped at 20, 1 for the bull).
    @Test func independentModel_randomGamesWithEdits_agreeAfterEveryOperation() throws {
        var random = SeededRandom(seed: 0xC10C)
        var failures: [String] = []
        var endings: [FinishReason: Int] = [:]
        var victories = 0
        for _ in 0..<300 where failures.isEmpty {
            let finishOnBull = random.nextInt(below: 2) == 0
            let jump = random.nextInt(below: 2) == 0
            let maxRounds: Int? = [nil, 1 + random.nextInt(below: 3), 8 + random.nextInt(below: 10)][random.nextInt(below: 3)]
            let players = 1 + random.nextInt(below: 4)
            let make: (inout SeededRandom) -> ReviewClock = { _ in
                ReviewClock(finishOnBull: finishOnBull, jump: jump, roundLimit: maxRounds,
                            progress: Array(repeating: 0, count: players), darts: Array(repeating: 0, count: players))
            }
            let options: GameOptions = ["finishOnBull": .bool(finishOnBull), "multiplierJump": .bool(jump),
                                        "maxRounds": maxRounds.map { .int($0) } ?? .null]
            var match = try GameRegistry.standard.match(.aroundTheClock, options, players: players)
            var machine = KillerReviewMachine(players: players, seed: 0, make: make)
            let text = "aroundTheClock \(options.values), \(players) players"
            for _ in 0..<(30 + random.nextInt(below: 170)) {
                let target = machine.rules.target(machine.current)
                let operation = KillerReviewOperation.random(match.phase, &random) { random in
                    let roll = random.nextInt(below: 10)
                    if roll < 1 || target == 25 && roll < 6 { return roll % 2 == 0 ? .outerBull : .innerBull }
                    let number = roll < 7 && (1...20).contains(target) ? target : 1 + random.nextInt(below: 20)
                    switch random.nextInt(below: 4) {
                    case 0: return .double(number)
                    case 1: return .treble(number)
                    case 2: return .miss
                    default: return .single(number)
                    }
                }
                let outcome = operation.apply(to: &match)
                switch operation {
                case .dart(let hit):
                    let events = machine.apply(.dart(hit))
                    if events?.last == .gameFinished(reason: .victory) { victories += 1 }
                    if outcome?.isAccepted != (events != nil) || (events.map { outcome?.events == $0 } == false) {
                        failures.append("\(hit): \(String(describing: outcome)), expected \(String(describing: events))")
                    }
                case .endTurn:
                    let events = machine.apply(.endTurn)
                    if outcome?.isAccepted != (events != nil) || (events.map { outcome?.events == $0 } == false) {
                        failures.append("endTurn: \(String(describing: outcome)), expected \(String(describing: events))")
                    }
                case .undo, .replace, .remove:
                    guard let replayed = KillerReviewMachine.replay(match.entries, players: players, seed: 0, make: make) else {
                        failures.append("the journal holds an entry the oracle refuses")
                        break
                    }
                    machine = replayed
                }
                if let issue = difference(match, machine) { failures.append(issue) }
                if !failures.isEmpty {
                    failures[failures.count - 1] += " — \(text): \(KillerReviewTests.journal(match))"
                    break
                }
            }
            if let reason = machine.finishReason { endings[reason, default: 0] += 1 }
        }
        #expect(failures.isEmpty, "\(failures.joined(separator: "\n"))")
        // Games end in both ways (victories counted on the dart that wins, even when undone later).
        #expect(victories > 20 && endings[.roundLimit, default: 0] > 20, "\(victories) victories, \(endings)")
    }
}
