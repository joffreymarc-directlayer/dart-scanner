import Testing
import DartCore
import DartGames
import DartTestSupport

/// Killer rewritten from GAMES.md §5 alone, as an oracle: draw of the zones (§2.8, §5.3), effect of a dart (§5.4),
/// expert redraw, eliminations, end of the game and ranking (§5.6), highlights of §5.7, facts of ARCHITECTURE.md §5.5.
private struct ReviewKiller: KillerReviewRules {
    static let ring = [20, 1, 18, 4, 13, 6, 10, 15, 2, 17, 3, 19, 7, 16, 8, 11, 14, 9, 12, 5]

    let width: Int
    let expert: Bool
    let armingHits: Int
    let penalty: Bool
    let roundLimit: Int?
    var zones: [[Int]]
    var lives: [Int]
    var arming: [Int]
    var kills: [Int]
    /// Elimination order, 0 for the first player out.
    var out: [Int?]
    /// Draws made by the expert redraws, for the reports.
    var redraws = 0

    init(level: String, players: Int, lives: Int, armingHits: Int, penalty: Bool, maxRounds: Int?,
         random: inout SeededRandom) {
        width = ["easy": 3, "medium": 2][level] ?? 1
        expert = level == "expert"
        self.armingHits = armingHits
        self.penalty = penalty
        roundLimit = maxRounds
        zones = Self.layout(players: players, width: width, random: &random)
        self.lives = Array(repeating: lives, count: players)
        arming = Array(repeating: 0, count: players)
        kills = Array(repeating: 0, count: players)
        out = Array(repeating: nil, count: players)
    }

    /// `ringLayout` of GAMES.md §2.8, written again from the listing of the document.
    static func layout(players p: Int, width k: Int, random: inout SeededRandom) -> [[Int]] {
        let offset = random.nextInt(below: 20)
        var gaps = Array(repeating: 0, count: p)
        for _ in 0..<(20 - p * k) { gaps[random.nextInt(below: p)] += 1 }
        var order = Array(0..<p)
        var i = p - 1
        while i >= 1 {
            order.swapAt(i, random.nextInt(below: i + 1))
            i -= 1
        }
        var zones = Array(repeating: [Int](), count: p)
        var cursor = offset
        for slot in 0..<p {
            zones[order[slot]] = (0..<k).map { ring[(cursor + $0) % 20] }
            cursor += k + gaps[slot]
        }
        return zones
    }

    func isOut(_ player: Int) -> Bool { out[player] != nil }
    func isKiller(_ player: Int) -> Bool { arming[player] == armingHits }
    var alive: [Int] { zones.indices.filter { !isOut($0) } }

    mutating func turnBegins(player: Int, round: Int, random: inout SeededRandom, events: inout [GameEvent]) {
        // §5.4: from the player's second turn on (a player's k-th turn is in round k), never for a player out.
        guard expert, round >= 2, !isOut(player) else { return }
        let others = Set(alive.filter { $0 != player }.flatMap { zones[$0] })
        let candidates = (1...20).filter { !others.contains($0) && $0 != zones[player][0] }
        let number = candidates[random.nextInt(below: candidates.count)]
        redraws += 1
        zones[player] = [number]
        events.append(.zoneChanged(player: player, zone: [number]))
    }

    mutating func dart(_ hit: Hit, player p: Int, round: Int, volley: [Hit], events: inout [GameEvent]) -> KillerReviewVerdict {
        guard let number = hit.number, let owner = alive.first(where: { zones[$0].contains(number) }) else {
            events.append(.noEffect(player: p))
            return .goOn
        }
        if owner == p {
            if !isKiller(p) {
                arming[p] += 1
                events.append(.armingHit(player: p, progress: arming[p]))
                if isKiller(p) { events.append(.becameKiller(player: p)) }
                return .goOn
            }
            guard penalty else {
                events.append(.noEffect(player: p))
                return .goOn
            }
            lives[p] -= 1
            events.append(.lifeLost(player: p, by: p, livesLeft: lives[p]))
            guard lives[p] == 0 else { return .goOn }
            out[p] = out.compactMap { $0 }.count
            events.append(.playerEliminated(player: p, by: p))
            return alive.count == 1 ? .finish(.lastPlayerStanding) : .close
        }
        guard isKiller(p) else {
            events.append(.noEffect(player: p))
            return .goOn
        }
        lives[owner] -= 1
        events.append(.lifeLost(player: owner, by: p, livesLeft: lives[owner]))
        guard lives[owner] == 0 else { return .goOn }
        out[owner] = out.compactMap { $0 }.count
        kills[p] += 1
        events.append(.playerEliminated(player: owner, by: p))
        return alive.count == 1 ? .finish(.lastPlayerStanding) : .goOn
    }

    mutating func turnEnds(player: Int, volley: [Hit], events: inout [GameEvent]) {}

    /// §5.6 and §2.7: players alive by lives, kills, arming progress; then the players out, the last one first.
    var ranks: [Int] {
        KillerReviewMachine<ReviewKiller>.ranks(zones.indices.map { player in
            out[player].map { [1, -$0] } ?? [0, -lives[player], -kills[player], -arming[player]]
        })
    }

    /// ARCHITECTURE.md §5.5: exactly these six facts.
    func facts(_ player: Int) -> [String: FactValue] {
        ["zone": .ints(zones[player]), "lives": .int(lives[player]), "armingProgress": .int(arming[player]),
         "kills": .int(kills[player]), "isKiller": .bool(isKiller(player)), "eliminated": .bool(isOut(player))]
    }

    /// §5.7, for the current player `p`: one sector per number, in the colour of its owner.
    func highlights(for p: Int) -> Set<BoardHighlight> {
        var result: Set<BoardHighlight> = []
        for player in alive {
            let role: HighlightRole
            if isOut(p) {
                role = .opponent
            } else if player == p {
                role = !isKiller(p) ? .target : (penalty ? .avoid : .own)
            } else {
                role = isKiller(p) ? .target : .opponent
            }
            for number in zones[player] {
                result.insert(BoardHighlight(zone: .sector(number), role: role, owner: player))
            }
        }
        return result
    }
}

@Suite struct KillerReviewTests {
    private let levels = ["easy", "medium", "hard", "expert"]

    private struct Setup {
        var level: String
        var players: Int
        var lives: Int
        var armingHits: Int
        var penalty: Bool
        var maxRounds: Int?
        var seed: UInt64

        var options: GameOptions {
            ["level": .string(level), "lives": .int(lives), "armingHits": .int(armingHits),
             "selfHitPenalty": .bool(penalty), "maxRounds": maxRounds.map { .int($0) } ?? .null]
        }

        func model(_ random: inout SeededRandom) -> ReviewKiller {
            ReviewKiller(level: level, players: players, lives: lives, armingHits: armingHits, penalty: penalty,
                         maxRounds: maxRounds, random: &random)
        }

        var text: String {
            "killer {level: \(level), lives: \(lives), armingHits: \(armingHits), selfHitPenalty: \(penalty), "
                + "maxRounds: \(maxRounds.map(String.init) ?? "nil")}, \(players) players, seed \(seed)"
        }
    }

    private func randomSetup(_ random: inout SeededRandom) -> Setup {
        let level = levels[random.nextInt(below: 4)]
        let most = level == "easy" ? 6 : 8
        let maxRounds: Int?
        switch random.nextInt(below: 4) {
        case 0: maxRounds = nil
        case 1: maxRounds = 15
        default: maxRounds = 1 + random.nextInt(below: 6)
        }
        return Setup(level: level, players: 2 + random.nextInt(below: most - 1),
                     lives: random.nextInt(below: 3) == 0 ? 1 + random.nextInt(below: 9) : 1 + random.nextInt(below: 3),
                     armingHits: random.nextInt(below: 3) == 0 ? 1 + random.nextInt(below: 5) : 1 + random.nextInt(below: 2),
                     penalty: random.nextInt(below: 2) == 0, maxRounds: maxRounds, seed: random.next())
    }

    /// A player who aims: often at their own zone or at an opponent alive, sometimes anywhere.
    private func aim(_ match: GameMatch, _ random: inout SeededRandom) -> Hit {
        let roll = random.nextInt(below: 100)
        if roll < 5 { return .miss }
        if roll < 9 { return roll % 2 == 0 ? .outerBull : .innerBull }
        let rows = match.snapshot.players
        let zones = rows.map { row -> [Int] in
            if case .ints(let zone)? = row.facts["zone"] { return zone }
            return [1]
        }
        let alive = rows.indices.filter { rows[$0].facts["eliminated"] != .bool(true) }
        let number: Int
        if roll < 25 || alive.isEmpty {
            number = 1 + random.nextInt(below: 20)
        } else if roll < 55 {
            let own = zones[match.snapshot.currentPlayer]
            number = own[random.nextInt(below: own.count)]
        } else {
            let zone = zones[alive[random.nextInt(below: alive.count)]]
            number = zone[random.nextInt(below: zone.count)]
        }
        switch random.nextInt(below: 3) {
        case 0: return .single(number)
        case 1: return .double(number)
        default: return .treble(number)
        }
    }

    /// Everything the oracle knows, compared with the snapshot. Returns the first difference, nil when none.
    private func difference(_ match: GameMatch, _ machine: KillerReviewMachine<ReviewKiller>) -> String? {
        let snapshot = match.snapshot
        let model = machine.rules
        if snapshot.phase != machine.phase { return "phase \(snapshot.phase), expected \(machine.phase)" }
        if snapshot.finishReason != machine.finishReason { return "finishReason \(String(describing: snapshot.finishReason))" }
        if snapshot.currentPlayer != machine.current || snapshot.round != machine.round {
            return "player \(snapshot.currentPlayer) round \(snapshot.round), expected \(machine.current) round \(machine.round)"
        }
        if snapshot.turn.darts.map(\.hit) != machine.volley { return "volley \(snapshot.turn.darts.map(\.hit))" }
        if snapshot.roundLimit != model.roundLimit { return "roundLimit \(String(describing: snapshot.roundLimit))" }
        for player in snapshot.players.indices {
            let row = snapshot.players[player]
            if row.facts != model.facts(player) { return "facts of J\(player + 1): \(row.facts), expected \(model.facts(player))" }
            if row.isEliminated != model.isOut(player) { return "isEliminated of J\(player + 1)" }
            if row.primary.text != "\(model.lives[player])" { return "primary of J\(player + 1): \(row.primary.text)" }
        }
        if snapshot.ranks != model.ranks { return "ranks \(snapshot.ranks), expected \(model.ranks)" }
        let expected: Set<BoardHighlight> = machine.phase == .finished ? [] : model.highlights(for: machine.current)
        if Set(snapshot.highlights) != expected || snapshot.highlights.count != expected.count {
            return "highlights \(snapshot.highlights), expected \(expected)"
        }
        // §5.7: no advice for a player who has just eliminated themselves, nor once the game is over.
        if (machine.phase == .finished || model.isOut(machine.current)) && snapshot.turn.hint != nil {
            return "a hint for a player who cannot play: \(String(describing: snapshot.turn.hint))"
        }
        if snapshot.turn.darts.contains(where: { $0.caption == nil }) { return "a dart without caption" }
        return nil
    }

    /// 360 random games of every level and every option, with refused inputs, undo, corrections and removals:
    /// after every operation the engine agrees with the oracle on the facts, ranks, turn, phase and highlights,
    /// and on the events of every accepted input. After an edit the whole journal is played again by the oracle.
    @Test func independentModel_randomGamesWithEdits_agreeAfterEveryOperation() throws {
        var random = SeededRandom(seed: 0x5EED_4B11)
        var failures: [String] = []
        var finished: [FinishReason: Int] = [:]
        var redraws = 0, selfEliminations = 0, edits = 0
        for _ in 0..<360 where failures.count < 3 {
            let setup = randomSetup(&random)
            var match = try GameRegistry.standard.match(.killer, setup.options, players: setup.players, seed: setup.seed)
            var machine = KillerReviewMachine(players: setup.players, seed: setup.seed) { setup.model(&$0) }
            if let issue = difference(match, machine) {
                failures.append("at creation: \(issue) — \(setup.text)")
                continue
            }
            for _ in 0..<(40 + random.nextInt(below: 160)) {
                let operation = KillerReviewOperation.random(match.phase, &random) { aim(match, &$0) }
                let outcome = operation.apply(to: &match)
                switch operation {
                case .dart(let hit):
                    let events = machine.apply(.dart(hit))
                    if outcome?.isAccepted != (events != nil) || (events.map { outcome?.events == $0 } == false) {
                        failures.append("\(hit): \(String(describing: outcome)), expected \(String(describing: events))")
                    }
                    let thrower = match.snapshot.currentPlayer
                    if outcome?.events.contains(.playerEliminated(player: thrower, by: thrower)) == true { selfEliminations += 1 }
                case .endTurn:
                    let events = machine.apply(.endTurn)
                    if outcome?.isAccepted != (events != nil) || (events.map { outcome?.events == $0 } == false) {
                        failures.append("endTurn: \(String(describing: outcome)), expected \(String(describing: events))")
                    }
                case .undo, .replace, .remove:
                    edits += 1
                    guard let replayed = KillerReviewMachine.replay(match.entries, players: setup.players, seed: setup.seed,
                                                                    make: { setup.model(&$0) }) else {
                        failures.append("the journal holds an entry the oracle refuses")
                        break
                    }
                    machine = replayed
                }
                if let issue = difference(match, machine) { failures.append(issue) }
                if !failures.isEmpty {
                    failures[failures.count - 1] += " — \(setup.text), journal \(match.entries.count) entries: \(KillerReviewTests.journal(match))"
                    break
                }
            }
            if let reason = machine.finishReason { finished[reason, default: 0] += 1 }
            redraws += machine.rules.redraws
        }
        #expect(failures.isEmpty, "\(failures.joined(separator: "\n"))")
        // The walk reached every ending and exercised the redraws and the corrections.
        #expect(finished[.lastPlayerStanding, default: 0] > 50 && finished[.roundLimit, default: 0] > 20)
        #expect(redraws > 500 && edits > 1_000 && selfEliminations > 10)
    }

    static func journal(_ match: GameMatch) -> String {
        match.entries.map { entry in
            if case .dart(let record) = entry { return record.hit.notation }
            return "|"
        }.joined(separator: " ")
    }

    /// GAMES.md §5.4, determinism of the expert redraw: correcting or removing a dart of the current turn never
    /// changes the number of the current player (drawn before the darts), and undoing the confirmation that
    /// gave the turn then confirming again draws the same number.
    @Test(arguments: [2, 3, 5, 8])
    func expert_correctionsOfTheCurrentTurnKeepTheNumber_andUndoRedoDrawsItAgain(_ players: Int) throws {
        var random = SeededRandom(seed: UInt64(900 + players))
        var checked = 0
        for game in 0..<12 {
            var match = try GameRegistry.standard.match(.killer, ["level": "expert", "lives": 2, "armingHits": 1,
                                                                   "maxRounds": .null],
                                                        players: players, seed: UInt64(game * 31 + players))
            for _ in 0..<120 where match.phase != .finished {
                let zones = match.snapshot.players.map { $0.facts["zone"] }
                let current = match.snapshot.currentPlayer
                if !match.currentTurn.isEmpty && match.snapshot.round > 1 {
                    for index in match.currentTurn.indices {
                        for hit in [Hit.miss, .single(1 + random.nextInt(below: 20)), .treble(1 + random.nextInt(below: 20))] {
                            var corrected = match
                            corrected.replaceDart(at: index, with: hit)
                            #expect(corrected.snapshot.players[current].facts["zone"] == zones[current])
                            #expect(corrected.snapshot.currentPlayer == current)
                        }
                        var removed = match
                        removed.removeDart(at: index)
                        #expect(removed.snapshot.players.map { $0.facts["zone"] } == zones)
                        checked += 1
                    }
                }
                if match.phase == .turnComplete || random.nextInt(below: 6) == 0 {
                    let before = match.snapshot
                    let outcome = match.endTurn()
                    guard outcome.isAccepted, match.phase != .finished else { continue }
                    let after = match.snapshot
                    match.undo()
                    #expect(match.snapshot == before)
                    #expect(match.endTurn() == outcome && match.snapshot == after)
                } else {
                    let row = match.snapshot.players[match.snapshot.currentPlayer]
                    let own: Int = { if case .ints(let zone)? = row.facts["zone"] { return zone[0] }; return 1 }()
                    let target = random.nextInt(below: 3) == 0 ? own : 1 + random.nextInt(below: 20)
                    match.throwDart(DartRecord(hit: .single(target)))
                }
            }
        }
        #expect(checked > 100)
    }

    /// GAMES.md §5.4: "il reste toujours au moins 12 candidats" and the zone of an eliminated player becomes
    /// drawable. Eight expert players with one life: the redraw never takes a number of another player alive,
    /// nor the previous number, and a number freed by an elimination is drawn again in some game.
    @Test func expert_redrawsAvoidTheNumbersAlive_andReuseTheNumbersOfThePlayersOut() throws {
        var random = SeededRandom(seed: 77)
        var reused = 0
        for seed in 0..<60 {
            var match = try GameRegistry.standard.match(.killer, ["level": "expert", "lives": 1, "armingHits": 1],
                                                        players: 8, seed: UInt64(seed))
            var outNumbers: Set<Int> = []
            for _ in 0..<200 where match.phase != .finished {
                let before = match.snapshot.players
                if match.phase == .turnComplete || random.nextInt(below: 4) == 0 {
                    let outcome = match.endTurn()
                    for case .zoneChanged(let player, let zone) in outcome.events {
                        let previous = before[player].facts["zone"]
                        #expect(.ints(zone) != previous, "the number did not change")
                        let others = before.indices.filter { $0 != player && before[$0].facts["eliminated"] == .bool(false) }
                        #expect(others.allSatisfy { before[$0].facts["zone"] != .ints(zone) }, "a number alive was drawn")
                        if let number = zone.first, outNumbers.contains(number) { reused += 1 }
                    }
                } else {
                    match.throwDart(DartRecord(hit: .single(1 + random.nextInt(below: 20))))
                }
                for row in match.snapshot.players where row.facts["eliminated"] == .bool(true) {
                    if case .ints(let zone)? = row.facts["zone"] { outNumbers.formUnion(zone) }
                }
            }
        }
        #expect(reused > 0)
    }

    /// GAMES.md §5.5 to §5.7 at the edges: a self-elimination with two players left ends the game in favour of the
    /// other player; with three, the turn closes, the eliminated player sees no zone of their own, no advice, and the
    /// players alive as `opponent`; the next confirmation passes the turn, and the player out is never seen again.
    @Test func selfElimination_endsOrClosesTheTurn_andTheOneOutSeesOnlyOpponents() throws {
        // KIL-4 setups: zones J1 [3], J2 [12], J3 [18] with seed 2 and three players.
        var three = try GameRegistry.standard.match(.killer, ["level": "hard", "lives": 1, "armingHits": 1, "selfHitPenalty": true],
                                                    players: 3, seed: 2)
        three.play("S3, T3")
        #expect(three.phase == .turnComplete && three.snapshot.currentPlayer == 0)
        #expect(Set(three.snapshot.highlights) == [BoardHighlight(zone: .sector(12), role: .opponent, owner: 1),
                                                    BoardHighlight(zone: .sector(18), role: .opponent, owner: 2)])
        #expect(three.snapshot.turn.hint == nil)
        #expect(three.snapshot.ranks == [3, 1, 1])
        three.play("|")
        #expect(three.snapshot.currentPlayer == 1 && three.snapshot.round == 1)
        three.play("MISS ×3 | MISS ×3 |")
        // J1 is skipped: round 2 starts with J2.
        #expect(three.snapshot.currentPlayer == 1 && three.snapshot.round == 2)

        var two = try GameRegistry.standard.match(.killer, ["level": "hard", "lives": 1, "armingHits": 1, "selfHitPenalty": true],
                                                  players: 2, seed: 2)
        let outcomes = two.play("S3, D3")
        #expect(outcomes[1].events == [.dartRegistered(player: 0, hit: .double(3)), .lifeLost(player: 0, by: 0, livesLeft: 0),
                                       .playerEliminated(player: 0, by: 0), .gameFinished(reason: .lastPlayerStanding)])
        #expect(two.snapshot.winners == [1] && two.snapshot.highlights.isEmpty && two.snapshot.outcome != nil)
    }
}
