import Testing
import DartCore
import DartGames
import DartTestSupport

/// X01 rewritten from GAMES.md §3 alone, as an oracle: the cases of §3.4 in their order, the bust of §3.5 (score
/// AND opening back to the start of the turn), the events of §3.8, the ranking and the highlights of §3.7.
private struct ReviewX01: CommonReviewRules {
    enum Last: Equatable { case points(Int), bust }

    let doubleIn: Bool
    let doubleOut: Bool
    let roundLimit: Int?
    var remaining: [Int]
    var open: [Bool]
    var darts: [Int]
    var busts: [Int]
    var last: [Last?]
    var startRemaining = 0
    var startOpen = true
    var points = 0
    var busted = false

    init(start: Int, doubleIn: Bool, doubleOut: Bool, maxRounds: Int?, players: Int) {
        self.doubleIn = doubleIn
        self.doubleOut = doubleOut
        roundLimit = maxRounds
        remaining = Array(repeating: start, count: players)
        open = Array(repeating: !doubleIn, count: players)
        darts = Array(repeating: 0, count: players)
        busts = Array(repeating: 0, count: players)
        last = Array(repeating: nil, count: players)
    }

    func isOut(_ player: Int) -> Bool { false }

    mutating func turnBegins(player: Int, round: Int, random: inout SeededRandom, events: inout [GameEvent]) {
        startRemaining = remaining[player]
        startOpen = open[player]
        points = 0
        busted = false
    }

    mutating func dart(_ hit: Hit, player p: Int, round: Int, volley: [Hit], events: inout [GameEvent]) -> CommonReviewVerdict {
        darts[p] += 1
        let double = hit.bed == .double || hit.bed == .innerBull
        if hit == .miss {
            events.append(.noEffect(player: p))
            return .goOn
        }
        if !open[p] {
            guard double else {
                events.append(.doubleInRequired(player: p))
                return .goOn
            }
            open[p] = true
            events.append(.doubleInOpened(player: p))
        }
        let left = remaining[p] - hit.points
        let reason: BustReason?
        if left < 0 {
            reason = .belowZero
        } else if left == 0 && doubleOut && !double {
            reason = .notADouble
        } else if left == 1 && doubleOut {
            reason = .oneLeft
        } else {
            reason = nil
        }
        if let reason {
            remaining[p] = startRemaining
            open[p] = startOpen
            busts[p] += 1
            busted = true
            events.append(.bust(player: p, reason: reason))
            return .close
        }
        remaining[p] = left
        points += hit.points
        if left == 0 {
            last[p] = .points(points)
            events.append(.checkout(player: p, points: points, darts: volley.count))
            return .finish(.victory)
        }
        return .goOn
    }

    mutating func turnEnds(player p: Int, volley: [Hit], events: inout [GameEvent]) {
        guard !busted else {
            last[p] = .bust
            return
        }
        last[p] = .points(points)
        events.append(.turnScored(player: p, points: points))
        if points == 180 { events.append(.oneEighty(player: p)) }
        if (100...179).contains(points) { events.append(.highTurn(player: p, points: points)) }
    }

    var ranks: [Int] { CommonReviewMachine<ReviewX01>.ranks(remaining.map { [$0] }) }

    func facts(_ p: Int) -> [String: FactValue] {
        ["remaining": .int(remaining[p]), "isOpen": .bool(open[p]), "dartsThrown": .int(darts[p]), "busts": .int(busts[p])]
    }

    /// §3.7: the 21 doubles before the opening, then the beds that finish at once.
    func highlights(for p: Int) -> Set<BoardHighlight> {
        if !open[p] {
            return Set((1...20).map { BoardHighlight(zone: .double($0), role: .target) } + [BoardHighlight(zone: .innerBull, role: .target)])
        }
        var zones: [BoardZone] = []
        for number in 1...20 {
            if number == remaining[p] && !doubleOut { zones.append(.single(number)) }
            if 2 * number == remaining[p] { zones.append(.double(number)) }
            if 3 * number == remaining[p] && !doubleOut { zones.append(.treble(number)) }
        }
        if remaining[p] == 25 && !doubleOut { zones.append(.outerBull) }
        if remaining[p] == 50 { zones.append(.innerBull) }
        return Set(zones.map { BoardHighlight(zone: $0, role: .target) })
    }
}

@Suite struct X01ReviewTests {
    /// Smallest number of darts that finishes `remaining` (nil: none within three), by brute force over every
    /// volley; computed once per out rule.
    private static func fewest(_ remaining: Int, doubleOut: Bool) -> Int? {
        (doubleOut ? fewestDoubleOut : fewestStraightOut)[remaining]
    }

    private static let fewestStraightOut = fewestTable(doubleOut: false)
    private static let fewestDoubleOut = fewestTable(doubleOut: true)

    private static func fewestTable(doubleOut: Bool) -> [Int: Int] {
        let beds = Hit.all.filter { $0 != .miss }
        let last = beds.filter { !doubleOut || $0.isDouble }
        var table: [Int: Int] = [:]
        for end in last {
            table[end.points] = 1
            for first in beds {
                table[first.points + end.points] = min(table[first.points + end.points] ?? 2, 2)
                for second in beds {
                    let total = first.points + second.points + end.points
                    table[total] = min(table[total] ?? 3, 3)
                }
            }
        }
        return table
    }

    private func difference(_ match: GameMatch, _ machine: CommonReviewMachine<ReviewX01>) -> String? {
        let snapshot = match.snapshot
        let model = machine.rules
        let p = machine.current
        if snapshot.phase != machine.phase || snapshot.finishReason != machine.finishReason {
            return "phase \(snapshot.phase) \(String(describing: snapshot.finishReason)), expected \(machine.phase)"
        }
        if snapshot.currentPlayer != p || snapshot.round != machine.round {
            return "player \(snapshot.currentPlayer) round \(snapshot.round), expected \(p) round \(machine.round)"
        }
        if snapshot.turn.darts.map(\.hit) != machine.volley { return "volley \(snapshot.turn.darts.map(\.hit))" }
        if snapshot.roundLimit != model.roundLimit { return "roundLimit \(String(describing: snapshot.roundLimit))" }
        for player in snapshot.players.indices {
            let row = snapshot.players[player]
            if row.facts != model.facts(player) { return "facts of J\(player + 1): \(row.facts), expected \(model.facts(player))" }
            if row.primary.text != "\(model.remaining[player])" { return "primary of J\(player + 1)" }
            // §3.7: "à ouvrir" while the player has not opened.
            if row.badges.isEmpty == !model.open[player] { return "badges of J\(player + 1): \(row.badges)" }
            let detail: LocalizedText?
            switch model.last[player] {
            case .points(let points)?: detail = LocalizedText(fr: "Dernière volée : \(points)", en: "Last turn: \(points)")
            case .bust?: detail = LocalizedText(verbatim: "BUST")
            case nil: detail = nil
            }
            if row.detail != detail { return "detail of J\(player + 1): \(String(describing: row.detail))" }
        }
        if snapshot.ranks != model.ranks { return "ranks \(snapshot.ranks), expected \(model.ranks)" }
        let highlights: Set<BoardHighlight> = machine.phase == .finished ? [] : model.highlights(for: p)
        if Set(snapshot.highlights) != highlights || snapshot.highlights.count != highlights.count {
            return "highlights \(snapshot.highlights), expected \(highlights)"
        }
        let summary: LocalizedText?
        if machine.finishReason == .roundLimit {
            summary = nil
        } else {
            summary = model.busted ? LocalizedText(verbatim: "BUST") : LocalizedText(fr: "Volée : \(model.points)", en: "Turn: \(model.points)")
        }
        if snapshot.turn.summary != summary { return "summary \(String(describing: snapshot.turn.summary)), expected \(String(describing: summary))" }
        // The finishing advice (ARCHITECTURE.md §5.6): only while throwing; once open, a real finish of what is
        // left with the fewest darts among those left in the turn, and an advice whenever such a finish exists.
        let hint = snapshot.turn.hint
        if machine.phase != .throwing {
            if hint != nil { return "an advice outside the throwing phase" }
        } else if model.open[p] {
            let left = 3 - machine.volley.count
            let needed = Self.fewest(model.remaining[p], doubleOut: model.doubleOut).flatMap { $0 <= left ? $0 : nil }
            guard let needed else { return hint == nil ? nil : "an advice without a finish: \(String(describing: hint))" }
            guard let text = hint?.fr, text.hasPrefix("Pour finir : ") else { return "no advice for \(model.remaining[p]) in \(left)" }
            let route = text.dropFirst("Pour finir : ".count).split(separator: " ").compactMap { Hit(notation: String($0)) }
            if route.count != needed || route.map(\.points).reduce(0, +) != model.remaining[p]
                || (model.doubleOut && route.last?.isDouble != true) {
                return "advice \(text) for \(model.remaining[p]) in \(left) darts"
            }
        } else if hint == nil {
            return "no advice before the opening"
        }
        if snapshot.turn.darts.contains(where: { $0.caption == nil }) { return "a dart without caption" }
        return nil
    }

    /// 400 random games, every option, aiming at what is left so that games finish and bust in every way, with
    /// refused inputs, undo and corrections: after every operation the engine agrees with the oracle, events
    /// included.
    @Test func independentModel_randomGamesWithEdits_agreeAfterEveryOperation() throws {
        var random = SeededRandom(seed: 0x01_501)
        var failures: [String] = []
        var endings: [FinishReason: Int] = [:]
        var victories = 0
        var reasons: Set<BustReason> = []
        for _ in 0..<400 where failures.isEmpty {
            let start = [301, 501, 701][random.nextInt(below: 3)]
            let doubleIn = random.nextInt(below: 2) == 0
            let doubleOut = random.nextInt(below: 2) == 0
            let maxRounds: Int? = [nil, 1 + random.nextInt(below: 3), 10 + random.nextInt(below: 16)][random.nextInt(below: 3)]
            let players = 1 + random.nextInt(below: 3)
            let make: (inout SeededRandom) -> ReviewX01 = { _ in
                ReviewX01(start: start, doubleIn: doubleIn, doubleOut: doubleOut, maxRounds: maxRounds, players: players)
            }
            let options: GameOptions = ["startScore": .int(start), "inRule": doubleIn ? "double" : "straight",
                                        "outRule": doubleOut ? "double" : "straight", "maxRounds": maxRounds.map { .int($0) } ?? .null]
            var match = try GameRegistry.standard.match(.x01, options, players: players)
            var machine = CommonReviewMachine(players: players, seed: 0, make: make)
            let text = "x01 \(options.values.sorted { $0.key < $1.key }), \(players) players"
            for _ in 0..<(60 + random.nextInt(below: 240)) {
                let left = machine.rules.remaining[machine.current]
                let opened = machine.rules.open[machine.current]
                let operation = CommonReviewOperation.random(match.phase, &random) { random in
                    let roll = random.nextInt(below: 10)
                    if !opened && roll < 5 { return random.nextInt(below: 5) == 0 ? .innerBull : .double(1 + random.nextInt(below: 20)) }
                    if left <= 60 && roll < 6 {
                        // Near the end: what is left, its half, or a little less or more.
                        let near = max(1, min(20, left / (1 + random.nextInt(below: 3)) + random.nextInt(below: 3) - 1))
                        return [Hit.single(near), .double(near), .treble(near), .outerBull, .innerBull][random.nextInt(below: 5)]
                    }
                    if roll < 8 { return [Hit.treble(20), .treble(19), .single(20), .double(16)][random.nextInt(below: 4)] }
                    return Hit.all[random.nextInt(below: Hit.all.count)]
                }
                let outcome = operation.apply(to: &match)
                switch operation {
                case .dart(let hit):
                    let events = machine.apply(.dart(hit))
                    if events?.last == .gameFinished(reason: .victory) { victories += 1 }
                    if outcome?.isAccepted != (events != nil) || (events.map { outcome?.events == $0 } == false) {
                        failures.append("\(hit): \(String(describing: outcome)), expected \(String(describing: events))")
                    }
                    for case .bust(_, let reason) in outcome?.events ?? [] { reasons.insert(reason) }
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
        #expect(reasons == [.belowZero, .notADouble, .oneLeft])
    }

    /// GAMES.md §3.4, the order of the cases: a MISS before the opening is `noEffect`, not `doubleInRequired`;
    /// the opening double is counted at once; and a later bust gives back the score of the start of the turn.
    @Test func doubleIn_missBeforeTheOpening_isNoEffect_theOpeningDoubleCounts() throws {
        var match = try GameRegistry.standard.match(.x01, ["inRule": "double", "outRule": "double"], players: 1)
        #expect(match.play("MISS")[0].events == [.dartRegistered(player: 0, hit: .miss), .noEffect(player: 0)])
        #expect(match.play("S20")[0].events == [.dartRegistered(player: 0, hit: .single(20)), .doubleInRequired(player: 0)])
        #expect(match.play("D20")[0].events == [.dartRegistered(player: 0, hit: .double(20)), .doubleInOpened(player: 0),
                                                .turnScored(player: 0, points: 40), .turnCompleted(player: 0)])
        match.play("| T20, T20, T20 | T17, MISS, MISS |")
        #expect(match.fact(0, "remaining") == 30 && match.fact(0, "isOpen") == true)
        #expect(match.play("D20")[0].events == [.dartRegistered(player: 0, hit: .double(20)), .bust(player: 0, reason: .belowZero),
                                                .turnCompleted(player: 0)])
        #expect(match.fact(0, "remaining") == 30 && match.fact(0, "busts") == 1 && match.phase == .turnComplete)
    }
}
