import Testing
import DartCore
import DartGames
import DartTestSupport

/// Cricket rewritten from GAMES.md §4 alone, as an oracle: the targets (light ones drawn as §4.3 says), the
/// marks handled one by one (§4.4), both scorings, the victory checked after every dart for ANY player (§4.6),
/// the ranking, the events of §4.8 and the highlights of §4.7.
private struct ReviewCricket: CommonReviewRules {
    let cutThroat: Bool
    let roundLimit: Int?
    let targets: [Int]
    var marks: [[Int: Int]]
    var points: [Int]

    init(cutThroat: Bool, light: Bool, maxRounds: Int?, players: Int, random: inout SeededRandom) {
        self.cutThroat = cutThroat
        roundLimit = maxRounds
        if light {
            // Fisher–Yates of §2.8 on [15…20], from the last index down to 1: five draws.
            var numbers = [15, 16, 17, 18, 19, 20]
            for i in stride(from: 5, through: 1, by: -1) { numbers.swapAt(i, random.nextInt(below: i + 1)) }
            targets = numbers.prefix(4).sorted(by: >)
        } else {
            targets = [20, 19, 18, 17, 16, 15, 25]
        }
        marks = Array(repeating: Dictionary(uniqueKeysWithValues: targets.map { ($0, 0) }), count: players)
        points = Array(repeating: 0, count: players)
    }

    func isOut(_ player: Int) -> Bool { false }
    func closed(_ player: Int, _ target: Int) -> Bool { marks[player][target] == 3 }
    func dead(_ target: Int) -> Bool { marks.indices.allSatisfy { closed($0, target) } }
    func better(_ a: Int, _ b: Int) -> Bool { cutThroat ? a < b : a > b }

    mutating func turnBegins(player: Int, round: Int, random: inout SeededRandom, events: inout [GameEvent]) {}

    mutating func dart(_ hit: Hit, player p: Int, round: Int, volley: [Hit], events: inout [GameEvent]) -> CommonReviewVerdict {
        let target = hit.bed == .outerBull || hit.bed == .innerBull ? 25 : hit.number
        guard let target, targets.contains(target) else {
            events.append(.noEffect(player: p))
            return .goOn
        }
        var closing = 0, scoring = 0
        var others: [Int] = []
        for _ in 0..<hit.multiplier {
            others = marks.indices.filter { $0 != p && !closed($0, target) }
            if !closed(p, target) {
                marks[p][target, default: 0] += 1
                closing += 1
            } else if !others.isEmpty {
                scoring += 1
            }
        }
        if closing > 0 { events.append(.marksScored(player: p, target: target, count: closing)) }
        if closing > 0 && closed(p, target) {
            events.append(.targetClosed(player: p, target: target))
            if dead(target) { events.append(.targetDead(target: target)) }
        }
        if scoring > 0 {
            if cutThroat {
                for q in others { points[q] += scoring * target }
                events.append(.pointsGiven(player: p, to: others, pointsEach: scoring * target))
            } else {
                points[p] += scoring * target
                events.append(.pointsScored(player: p, points: scoring * target))
            }
        }
        if closing == 0 && scoring == 0 { events.append(.noEffect(player: p)) }
        let winner = marks.indices.contains { w in
            targets.allSatisfy { closed(w, $0) } && !points.indices.contains { $0 != w && better(points[$0], points[w]) }
        }
        return winner ? .finish(.victory) : .goOn
    }

    mutating func turnEnds(player: Int, volley: [Hit], events: inout [GameEvent]) {}

    var ranks: [Int] {
        CommonReviewMachine<ReviewCricket>.ranks(points.indices.map { p in
            [cutThroat ? points[p] : -points[p], -marks[p].values.reduce(0, +)]
        })
    }

    func highlights(for p: Int) -> Set<BoardHighlight> {
        Set(targets.map { target in
            let role: HighlightRole = !closed(p, target) ? .target : (dead(target) ? .inactive : .secondary)
            return BoardHighlight(zone: target == 25 ? .bull : .sector(target), role: role)
        })
    }
}

@Suite struct CricketReviewTests {
    private func difference(_ match: GameMatch, _ machine: CommonReviewMachine<ReviewCricket>) -> String? {
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
        if snapshot.facts != ["targets": .ints(model.targets)] { return "game facts \(snapshot.facts)" }
        for p in snapshot.players.indices {
            let expected: [String: FactValue] = ["points": .int(model.points[p]), "marks": .map(model.marks[p]),
                                                 "closedCount": .int(model.targets.filter { model.closed(p, $0) }.count)]
            if snapshot.players[p].facts != expected { return "facts of J\(p + 1): \(snapshot.players[p].facts), expected \(expected)" }
            if snapshot.players[p].primary.text != "\(model.points[p])" { return "primary of J\(p + 1)" }
        }
        if snapshot.ranks != model.ranks { return "ranks \(snapshot.ranks), expected \(model.ranks)" }
        let highlights: Set<BoardHighlight> = machine.phase == .finished ? [] : model.highlights(for: machine.current)
        if Set(snapshot.highlights) != highlights || snapshot.highlights.count != highlights.count {
            return "highlights \(snapshot.highlights), expected \(highlights)"
        }
        let grid = ScoreGrid(columns: model.targets.map { $0 == 25 ? "B" : "\($0)" },
                             marks: model.marks.map { row in model.targets.map { row[$0] ?? -1 } },
                             dead: model.targets.map(model.dead))
        if snapshot.grid != grid { return "grid \(String(describing: snapshot.grid)), expected \(grid)" }
        if machine.finishReason == .roundLimit && snapshot.turn.summary != nil { return "a turn summary after the round limit" }
        if snapshot.turn.darts.contains(where: { $0.caption == nil }) { return "a dart without caption" }
        return nil
    }

    /// 400 random games, both scorings, normal and light targets, 1 to 5 players, with refused inputs, undo and
    /// corrections: after every operation the engine agrees with the oracle, events included.
    @Test func independentModel_randomGamesWithEdits_agreeAfterEveryOperation() throws {
        var random = SeededRandom(seed: 0xC41C)
        var failures: [String] = []
        var endings: [FinishReason: Int] = [:]
        var victories = 0
        var thrownWins = 0
        for _ in 0..<400 where failures.isEmpty {
            let cutThroat = random.nextInt(below: 2) == 0
            let light = random.nextInt(below: 3) == 0
            let maxRounds: Int? = [nil, 1 + random.nextInt(below: 3), 8 + random.nextInt(below: 12)][random.nextInt(below: 3)]
            let players = 1 + random.nextInt(below: 4)
            let seed = random.next()
            let make: (inout SeededRandom) -> ReviewCricket = {
                ReviewCricket(cutThroat: cutThroat, light: light, maxRounds: maxRounds, players: players, random: &$0)
            }
            let options: GameOptions = ["scoring": cutThroat ? "cutThroat" : "standard", "targets": light ? "light" : "normal",
                                        "maxRounds": maxRounds.map { .int($0) } ?? .null]
            var match = try GameRegistry.standard.match(.cricket, options, players: players, seed: seed)
            var machine = CommonReviewMachine(players: players, seed: seed, make: make)
            let text = "cricket \(options.values.sorted { $0.key < $1.key }), \(players) players, seed \(seed)"
            for _ in 0..<(40 + random.nextInt(below: 200)) {
                let targets = machine.rules.targets
                let operation = CommonReviewOperation.random(match.phase, &random) { random in
                    let roll = random.nextInt(below: 10)
                    if roll < 1 { return [Hit.miss, .outerBull, .innerBull, .single(1 + random.nextInt(below: 14))][random.nextInt(below: 4)] }
                    let target = targets[random.nextInt(below: targets.count)]
                    if target == 25 { return random.nextInt(below: 2) == 0 ? .outerBull : .innerBull }
                    return [Hit.single(target), .double(target), .treble(target)][random.nextInt(below: 3)]
                }
                let outcome = operation.apply(to: &match)
                switch operation {
                case .dart(let hit):
                    let thrower = machine.current
                    let events = machine.apply(.dart(hit))
                    if events?.last == .gameFinished(reason: .victory) { victories += 1 }
                    if outcome?.isAccepted != (events != nil) || (events.map { outcome?.events == $0 } == false) {
                        failures.append("\(hit): \(String(describing: outcome)), expected \(String(describing: events))")
                    }
                    if events != nil && machine.finishReason == .victory && !match.snapshot.winners.contains(thrower) { thrownWins += 1 }
                case .endTurn:
                    let events = machine.apply(.endTurn)
                    if outcome?.isAccepted != (events != nil) || (events.map { outcome?.events == $0 } == false) {
                        failures.append("endTurn: \(String(describing: outcome)), expected \(String(describing: events))")
                    }
                case .undo, .replace, .remove:
                    guard let replayed = CommonReviewMachine.replay(match.entries, players: players, seed: seed, make: make) else {
                        failures.append("the journal holds an entry the oracle refuses")
                        break
                    }
                    machine = replayed
                }
                if let issue = difference(match, machine) { failures.append(issue) }
                if !failures.isEmpty {
                    failures[failures.count - 1] += " — \(text): \(CommonReviewTests.journal(match))"
                    break
                }
            }
            if let reason = machine.finishReason { endings[reason, default: 0] += 1 }
        }
        #expect(failures.isEmpty, "\(failures.joined(separator: "\n"))")
        // Games end in both ways (victories counted on the dart that wins, even when undone later).
        #expect(victories > 30 && endings[.roundLimit, default: 0] > 30, "\(victories) victories, \(endings)")
        // §4.6: in cut-throat the winner may be another player than the thrower; the walk met that case.
        #expect(thrownWins > 0)
    }
}
