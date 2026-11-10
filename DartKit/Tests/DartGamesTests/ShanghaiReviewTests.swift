import Testing
import DartCore
import DartGames
import DartTestSupport

/// Shanghai rewritten from GAMES.md §7 alone, as an oracle: the number of the round, the neighbours of `lite`,
/// the Shanghai, the end at the round limit, the ranking, and the highlights of §7.7.
private struct ReviewShanghai: KillerReviewRules {
    static let ring = [20, 1, 18, 4, 13, 6, 10, 15, 2, 17, 3, 19, 7, 16, 8, 11, 14, 9, 12, 5]

    let rounds: Int
    let lite: Bool
    var points: [Int]
    var shanghaiBy: Int?

    var roundLimit: Int? { rounds }
    func isOut(_ player: Int) -> Bool { false }

    /// GAMES.md §2.1: (anticlockwise, clockwise).
    static func neighbours(_ number: Int) -> [Int] {
        guard let index = ring.firstIndex(of: number) else { return [] }
        return [ring[(index + 19) % 20], ring[(index + 1) % 20]]
    }

    /// Points of one dart in round `r`.
    func gain(_ hit: Hit, round r: Int) -> Int {
        guard let number = hit.number else { return 0 }
        if number == r { return r * hit.multiplier }
        return lite && Self.neighbours(r).contains(number) ? r : 0
    }

    mutating func turnBegins(player: Int, round: Int, random: inout SeededRandom, events: inout [GameEvent]) {}

    mutating func dart(_ hit: Hit, player p: Int, round r: Int, volley: [Hit], events: inout [GameEvent]) -> KillerReviewVerdict {
        let points = gain(hit, round: r)
        self.points[p] += points
        if hit.number == r {
            events.append(.targetScored(player: p, points: points))
        } else if points > 0 {
            events.append(.neighbourHit(player: p, points: points))
        } else {
            events.append(.noEffect(player: p))
        }
        let beds = Set(volley.filter { $0.number == r }.map(\.multiplier))
        if beds == [1, 2, 3] {
            shanghaiBy = p
            events.append(.shanghai(player: p))
            return .finish(.victory)
        }
        return .goOn
    }

    mutating func turnEnds(player: Int, volley: [Hit], events: inout [GameEvent]) {}

    var ranks: [Int] {
        KillerReviewMachine<ReviewShanghai>.ranks(points.indices.map { [shanghaiBy == $0 ? 0 : 1, -points[$0]] })
    }

    func highlights(round r: Int) -> Set<BoardHighlight> {
        var result: Set<BoardHighlight> = [
            BoardHighlight(zone: .single(r), role: .target, label: "+\(r)"),
            BoardHighlight(zone: .double(r), role: .target, label: "+\(2 * r)"),
            BoardHighlight(zone: .treble(r), role: .target, label: "+\(3 * r)"),
        ]
        if lite {
            for neighbour in Self.neighbours(r) {
                result.insert(BoardHighlight(zone: .sector(neighbour), role: .secondary, label: "+\(r)"))
            }
        }
        return result
    }
}

@Suite struct ShanghaiReviewTests {
    private func difference(_ match: GameMatch, _ machine: KillerReviewMachine<ReviewShanghai>) -> String? {
        let snapshot = match.snapshot
        let model = machine.rules
        if snapshot.phase != machine.phase || snapshot.finishReason != machine.finishReason {
            return "phase \(snapshot.phase) \(String(describing: snapshot.finishReason)), expected \(machine.phase)"
        }
        if snapshot.currentPlayer != machine.current || snapshot.round != machine.round {
            return "player \(snapshot.currentPlayer) round \(snapshot.round), expected \(machine.current) round \(machine.round)"
        }
        if snapshot.turn.darts.map(\.hit) != machine.volley { return "volley \(snapshot.turn.darts.map(\.hit))" }
        if snapshot.roundLimit != model.rounds { return "roundLimit \(String(describing: snapshot.roundLimit))" }
        if snapshot.players.map(\.facts) != model.points.map({ ["points": .int($0)] }) { return "facts \(snapshot.players.map(\.facts))" }
        if snapshot.ranks != model.ranks { return "ranks \(snapshot.ranks), expected \(model.ranks)" }
        let highlights: Set<BoardHighlight> = machine.phase == .finished ? [] : model.highlights(round: machine.round)
        if Set(snapshot.highlights) != highlights || snapshot.highlights.count != highlights.count {
            return "highlights \(snapshot.highlights)"
        }
        if machine.phase != .finished && snapshot.objective != LocalizedText(fr: "Numéro \(machine.round)", en: "Number \(machine.round)") {
            return "objective \(String(describing: snapshot.objective))"
        }
        // ARCHITECTURE.md §5.6: the points of the current volley; nothing once a game ended at the round limit.
        let total = machine.volley.map { model.gain($0, round: machine.round) }.reduce(0, +)
        let summary = machine.finishReason == .roundLimit ? nil : LocalizedText(fr: "Volée : \(total)", en: "Turn: \(total)")
        if snapshot.turn.summary != summary { return "summary \(String(describing: snapshot.turn.summary)), expected \(String(describing: summary))" }
        let captions = machine.volley.map { hit -> DartCaption in
            let gain = model.gain(hit, round: machine.round)
            return gain > 0 ? DartCaption(LocalizedText(verbatim: "+\(gain)"), tone: .positive) : DartCaption(LocalizedText(verbatim: "0"))
        }
        if snapshot.turn.darts.map(\.caption) != captions { return "captions \(snapshot.turn.darts.map(\.caption))" }
        return nil
    }

    /// 300 random games, every number of rounds from 1 to 20 (custom values included), both variants, with
    /// refused inputs, undo and corrections: after every operation the engine agrees with the oracle.
    @Test func independentModel_randomGamesWithEdits_agreeAfterEveryOperation() throws {
        var random = SeededRandom(seed: 0x5A_4E_6A_1)
        var failures: [String] = []
        var endings: [FinishReason: Int] = [:]
        var victories = 0
        for _ in 0..<300 where failures.isEmpty {
            let rounds = random.nextInt(below: 2) == 0 ? 1 + random.nextInt(below: 4) : 1 + random.nextInt(below: 20)
            let lite = random.nextInt(below: 2) == 0
            let players = 1 + random.nextInt(below: 8)
            let make: (inout SeededRandom) -> ReviewShanghai = { _ in
                ReviewShanghai(rounds: rounds, lite: lite, points: Array(repeating: 0, count: players))
            }
            var match = try GameRegistry.standard.match(.shanghai, ["rounds": .int(rounds), "variant": lite ? "lite" : "traditional"],
                                                        players: players)
            var machine = KillerReviewMachine(players: players, seed: 0, make: make)
            let text = "shanghai {rounds: \(rounds), lite: \(lite)}, \(players) players"
            for _ in 0..<(30 + random.nextInt(below: 150)) {
                let round = match.snapshot.round
                // The beds of the number of the round still missing for a Shanghai in this volley.
                let missing = [1, 2, 3].filter { bed in !machine.volley.contains { $0.number == round && $0.multiplier == bed } }
                let operation = KillerReviewOperation.random(match.phase, &random) { random in
                    let roll = random.nextInt(below: 10)
                    if roll < 4 && !missing.isEmpty {
                        let bed = missing[random.nextInt(below: missing.count)]
                        return bed == 1 ? .single(round) : (bed == 2 ? .double(round) : .treble(round))
                    }
                    let number = roll < 6 ? round : (roll < 8 ? ReviewShanghai.neighbours(round)[random.nextInt(below: 2)]
                                                              : 1 + random.nextInt(below: 20))
                    switch random.nextInt(below: 4) {
                    case 0: return .single(number)
                    case 1: return .double(number)
                    case 2: return .treble(number)
                    default: return [Hit.miss, .outerBull, .innerBull][random.nextInt(below: 3)]
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
        #expect(victories > 10 && endings[.roundLimit, default: 0] > 30, "\(victories) victories, \(endings)")
    }

    /// GAMES.md §7.2 and ARCHITECTURE.md §5.3: the engine accepts 1 to 20 rounds, custom values included, and
    /// refuses anything else with `invalidOptionValue(key: "rounds")`.
    @Test func rounds_customValuesFromOneToTwenty_andNothingElse() throws {
        for rounds in 1...20 {
            let match = try GameRegistry.standard.match(.shanghai, ["rounds": .int(rounds)], players: 2)
            #expect(match.snapshot.roundLimit == rounds)
        }
        for value: OptionValue in [0, -1, 21, 25, .string("7"), .null, .bool(true)] {
            #expect(throws: GameConfigurationError.invalidOptionValue(key: "rounds")) {
                try GameRegistry.standard.match(.shanghai, ["rounds": value], players: 2)
            }
        }
    }
}
