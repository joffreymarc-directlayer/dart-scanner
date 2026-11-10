import Foundation
import Testing
import DartCore
import DartGames
import DartTestSupport

// Adversarial review of lot G3 (Moon Landing, Fight, Conqueror, Halve-It).
//
// Every game is modelled again here, from the text of GAMES.md §2, §9 to §12 and ARCHITECTURE.md §5.5, §5.6
// alone, with a turn machine of its own (GAMES.md §2.4, §2.5) that shares no code with `TurnBasedEngine` nor
// with the rules under review. Long random journals (darts, confirmations, undo, corrections, removals) are fed
// to the real game and to the model, and after EVERY operation the two must agree on: acceptance and events of
// the input, journal kept by the replay and darts it dropped, phase, current player, round, round limit, finish
// reason, ranks, every fact, elimination, and the highlights.

// MARK: - Reference turn machine

private enum ReviewVerdict {
    case goOn
    case close
    case finish(FinishReason)
}

/// The rules of one game, written from GAMES.md alone.
private protocol ReviewModel {
    var roundLimit: Int? { get }
    func isOut(_ player: Int) -> Bool
    mutating func startTurn(player: Int, round: Int, events: inout [GameEvent])
    mutating func dart(_ hit: Hit, player: Int, round: Int, volley: [Hit], events: inout [GameEvent]) -> ReviewVerdict
    mutating func closeTurn(player: Int, round: Int, volley: [Hit], events: inout [GameEvent])
    func ranks() -> [Int]
    func playerFacts(_ player: Int, current: Int, phase: GamePhase) -> [String: FactValue]
    func gameFacts(round: Int) -> [String: FactValue]
    func highlights(current: Int, round: Int) -> Set<BoardHighlight>
    /// True when the game captions a dart without effect « Sans effet » / "No effect", and no other dart so.
    var captionsNoEffect: Bool { get }
}

/// Competition ranking of GAMES.md §2.7: `1 + number of players strictly better`.
private func reviewRanks(_ keys: [[Int]]) -> [Int] {
    keys.map { key in 1 + keys.filter { $0.lexicographicallyPrecedes(key) }.count }
}

/// Ranking of an elimination game (GAMES.md §2.7): the players in play by their key, then the eliminated ones,
/// the last one out first.
private func reviewEliminationRanks(_ alive: [[Int]?], order: [Int]) -> [Int] {
    reviewRanks(alive.indices.map { player in
        if let key = alive[player] { return [0] + key }
        return [1, -(order.firstIndex(of: player) ?? 0)]
    })
}

/// GAMES.md §2.4, read literally.
private struct ReviewGame<Model: ReviewModel> {
    var model: Model
    let players: Int
    var phase = GamePhase.throwing
    var current = 0
    var round = 1
    var volley: [Hit] = []
    /// Events of each dart of the volley, `dartRegistered` included.
    var volleyEvents: [[GameEvent]] = []
    var finishReason: FinishReason?

    init(players: Int, model: Model) {
        var model = model
        var ignored: [GameEvent] = []
        model.startTurn(player: 0, round: 1, events: &ignored)
        self.model = model
        self.players = players
    }

    /// Events of an accepted input (`nil` hit = endTurn); nil when the input is refused.
    mutating func apply(_ hit: Hit?) -> [GameEvent]? {
        guard let hit else { return endTurn() }
        guard phase == .throwing else { return nil }
        volley.append(hit)
        var events: [GameEvent] = [.dartRegistered(player: current, hit: hit)]
        switch model.dart(hit, player: current, round: round, volley: volley, events: &events) {
        case .finish(let reason):
            phase = .finished
            finishReason = reason
            events.append(.gameFinished(reason: reason))
        case .close:
            close(&events)
        case .goOn:
            if volley.count == 3 { close(&events) }
        }
        volleyEvents.append(events)
        return events
    }

    private mutating func close(_ events: inout [GameEvent]) {
        model.closeTurn(player: current, round: round, volley: volley, events: &events)
        events.append(.turnCompleted(player: current))
        phase = .turnComplete
    }

    private mutating func endTurn() -> [GameEvent]? {
        guard phase != .finished else { return nil }
        var events: [GameEvent] = []
        if phase == .throwing { close(&events) }
        var next = current
        repeat {
            next = (next + 1) % players
        } while model.isOut(next) && next != current
        if next <= current {
            if let limit = model.roundLimit, round == limit {
                volley = []
                volleyEvents = []
                phase = .finished
                finishReason = .roundLimit
                events.append(.gameFinished(reason: .roundLimit))
                return events
            }
            round += 1
            events.append(.roundStarted(round: round))
        }
        current = next
        volley = []
        volleyEvents = []
        phase = .throwing
        model.startTurn(player: current, round: round, events: &events)
        events.append(.turnStarted(player: current, round: round))
        return events
    }
}

private enum ReviewFuzz {
    /// Plays `steps` random operations on the real game and on the model; see the head of this file.
    static func run<Model: ReviewModel>(
        _ game: GameID, _ options: GameOptions, players: Int, seed: UInt64, fuzzSeed: UInt64, steps: Int,
        model initial: Model, dart: (inout SeededRandom, GameMatch) -> Hit
    ) throws -> (inputs: Int, edits: Int, finished: Int) {
        let label = "\(game) \(options) players \(players) seed \(seed) fuzz \(fuzzSeed)"
        var match = try GameRegistry.standard.match(game, options, players: players, seed: seed)
        var model = ReviewGame(players: players, model: initial)
        var journal: [Hit?] = []
        var random = SeededRandom(seed: fuzzSeed)
        var inputs = 0, edits = 0, finished = 0
        func replay(_ entries: [Hit?]) -> (ReviewGame<Model>, kept: [Hit?], dropped: [Hit]) {
            var fresh = ReviewGame(players: players, model: initial)
            var kept: [Hit?] = [], dropped: [Hit] = []
            for entry in entries {
                if fresh.apply(entry) != nil {
                    kept.append(entry)
                } else if let hit = entry {
                    dropped.append(hit)
                }
            }
            return (fresh, kept, dropped)
        }
        func entryIndex(_ index: Int) -> Int? {
            let start = (journal.lastIndex { $0 == nil }).map { $0 + 1 } ?? 0
            let darts = (start..<journal.count).filter { journal[$0] != nil }
            return darts.indices.contains(index) ? darts[index] : nil
        }

        for step in 0..<steps {
            let where_ = "\(label) step \(step)"
            let choice = random.nextInt(below: 20)
            if match.phase == .finished && choice < 15 {
                finished += 1
                let refused = match.endTurn()
                let modelRefused = model.apply(nil)
                #expect(!refused.isAccepted && modelRefused == nil, "\(where_)")
                match.undo()
                journal.removeLast()
                model = replay(journal).0
            } else if choice < 15 {
                let hit = choice < 11 ? dart(&random, match) : nil
                let outcome = hit.map { match.throwDart(DartRecord(hit: $0)) } ?? match.endTurn()
                let events = model.apply(hit)
                inputs += 1
                #expect(outcome.isAccepted == (events != nil), "\(where_): \(String(describing: hit)) accepted")
                if let events {
                    #expect(outcome.events == events, "\(where_): events of \(String(describing: hit))")
                    journal.append(hit)
                }
            } else {
                edits += 1
                var edited = journal
                let result: EditOutcome
                switch choice {
                case 15, 16:
                    result = match.undo()
                    if !edited.isEmpty { edited.removeLast() }
                case 17, 18:
                    let index = random.nextInt(below: 3)
                    let hit = dart(&random, match)
                    result = match.replaceDart(at: index, with: hit)
                    if let entry = entryIndex(index) { edited[entry] = hit }
                default:
                    let index = random.nextInt(below: 3)
                    result = match.removeDart(at: index)
                    if let entry = entryIndex(index) { edited.remove(at: entry) }
                }
                let (fresh, kept, dropped) = replay(edited)
                #expect(result.dropped.map(\.hit) == dropped, "\(where_): dropped darts")
                model = fresh
                journal = kept
            }
            compare(match, model, journal, where_)
        }
        return (inputs, edits, finished)
    }

    /// Plays a script written as in GAMES.md §2.11 ("T3, T19 | MISS ×3 |") on the real game and on the model,
    /// comparing them after every input as `run` does.
    static func script<Model: ReviewModel>(_ game: GameID, _ options: GameOptions, players: Int, seed: UInt64,
                                           model initial: Model, _ text: String) throws -> GameMatch {
        var match = try GameRegistry.standard.match(game, options, players: players, seed: seed)
        var model = ReviewGame(players: players, model: initial)
        var journal: [Hit?] = []
        var inputs: [Hit?] = []
        for (index, turn) in text.components(separatedBy: "|").enumerated() {
            if index > 0 { inputs.append(nil) }
            for token in turn.components(separatedBy: ",") where !token.trimmingCharacters(in: .whitespaces).isEmpty {
                let parts = token.components(separatedBy: "×")
                let times = parts.count > 1 ? Int(parts[1].trimmingCharacters(in: .whitespaces)) ?? 1 : 1
                let hit = Hit(notation: parts[0].trimmingCharacters(in: .whitespaces))
                #expect(hit != nil, "notation \(token)")
                inputs += Array(repeating: hit, count: hit == nil ? 0 : times)
            }
        }
        for (step, hit) in inputs.enumerated() {
            let outcome = hit.map { match.throwDart(DartRecord(hit: $0)) } ?? match.endTurn()
            let events = model.apply(hit)
            #expect(outcome.isAccepted && outcome.events == events, "\(game) script, input \(step)")
            journal.append(hit)
            compare(match, model, journal, "\(game) script, input \(step)")
        }
        return match
    }

    static func compare<Model: ReviewModel>(_ match: GameMatch, _ model: ReviewGame<Model>, _ journal: [Hit?], _ where_: String) {
        let snapshot = match.snapshot
        let entries: [Hit?] = match.entries.map { entry in
            if case .dart(let record) = entry { return record.hit }
            return nil
        }
        #expect(entries == journal, "\(where_): journal")
        #expect(snapshot.phase == model.phase, "\(where_): phase")
        #expect(snapshot.currentPlayer == model.current && snapshot.round == model.round, "\(where_): turn")
        #expect(snapshot.roundLimit == model.model.roundLimit, "\(where_): round limit")
        #expect(snapshot.finishReason == model.finishReason, "\(where_): finish reason")
        #expect(snapshot.turn.darts.map(\.hit) == model.volley, "\(where_): volley")
        // One caption per dart; « Sans effet » exactly for the darts whose events say `noEffect`.
        #expect(snapshot.turn.darts.allSatisfy { $0.caption != nil }, "\(where_): every dart has a caption")
        if model.model.captionsNoEffect {
            for (index, slot) in snapshot.turn.darts.enumerated() where index < model.volleyEvents.count {
                let silent = model.volleyEvents[index].contains { if case .noEffect = $0 { return true } else { return false } }
                #expect((slot.caption?.text == LocalizedText(fr: "Sans effet", en: "No effect")) == silent,
                        "\(where_): caption of dart \(index)")
            }
        }
        let ranks = model.model.ranks()
        #expect(snapshot.ranks == ranks, "\(where_): ranks")
        for player in 0..<model.players {
            #expect(snapshot.players[player].facts == model.model.playerFacts(player, current: model.current, phase: model.phase),
                    "\(where_): facts of J\(player + 1)")
            #expect(snapshot.players[player].isEliminated == model.model.isOut(player), "\(where_): J\(player + 1) out")
        }
        #expect(snapshot.facts == model.model.gameFacts(round: model.round), "\(where_): game facts")
        let highlights = model.phase == .finished ? [] : model.model.highlights(current: model.current, round: model.round)
        #expect(Set(snapshot.highlights) == highlights, "\(where_): highlights")
        #expect(snapshot.highlights.count == highlights.count, "\(where_): no highlight twice")
        #expect(snapshot.winnerTitle == nil, "\(where_): the winners are players")
        #expect((snapshot.outcome != nil) == (model.phase == .finished), "\(where_): outcome only once finished")
    }
}

/// The smallest zone of a bed (GAMES.md §2.9).
private func reviewZone(_ hit: Hit) -> BoardZone? {
    switch hit.bed {
    case .miss: return nil
    case .single: return hit.number.map(BoardZone.single)
    case .double: return hit.number.map(BoardZone.double)
    case .treble: return hit.number.map(BoardZone.treble)
    case .outerBull: return .outerBull
    case .innerBull: return .innerBull
    }
}

private func reviewAnyHit(_ random: inout SeededRandom) -> Hit {
    Hit.all[random.nextInt(below: Hit.all.count)]
}

/// A dart on `number`, single, double or treble.
private func reviewDart(on number: Int, _ random: inout SeededRandom) -> Hit {
    switch random.nextInt(below: 3) {
    case 0: return .single(number)
    case 1: return .double(number)
    default: return .treble(number)
    }
}

private let reviewRing = [20, 1, 18, 4, 13, 6, 10, 15, 2, 17, 3, 19, 7, 16, 8, 11, 14, 9, 12, 5]

/// The two neighbours of a number on the ring (GAMES.md §2.1).
private func reviewNeighbours(_ number: Int) -> [Int] {
    let index = reviewRing.firstIndex(of: number) ?? 0
    return [reviewRing[(index + 19) % 20], reviewRing[(index + 1) % 20]]
}

// MARK: - Halve-It (GAMES.md §9)

private struct ReviewHalveIt: ReviewModel {
    var captionsNoEffect: Bool { true }
    enum Target: Equatable {
        case number(Int), double(Int), treble(Int), anyDouble, anyTreble, bull

        init(_ text: String) {
            switch text {
            case "anyDouble": self = .anyDouble
            case "anyTreble": self = .anyTreble
            case "BULL": self = .bull
            default:
                if text.hasPrefix("D") { self = .double(Int(text.dropFirst()) ?? 0) }
                else if text.hasPrefix("T") { self = .treble(Int(text.dropFirst()) ?? 0) }
                else { self = .number(Int(text) ?? 0) }
            }
        }

        var notation: String {
            switch self {
            case .number(let n): return "\(n)"
            case .double(let n): return "D\(n)"
            case .treble(let n): return "T\(n)"
            case .anyDouble: return "anyDouble"
            case .anyTreble: return "anyTreble"
            case .bull: return "BULL"
            }
        }

        /// Table of GAMES.md §9.2.
        func counts(_ hit: Hit) -> Bool {
            switch self {
            case .number(let n): return hit.number == n
            case .double(let n): return hit.number == n && hit.multiplier == 2
            case .treble(let n): return hit.number == n && hit.multiplier == 3
            case .anyDouble: return hit.bed == .double || hit.bed == .innerBull
            case .anyTreble: return hit.bed == .treble
            case .bull: return hit.bed == .outerBull || hit.bed == .innerBull
            }
        }

        /// GAMES.md §9.7.
        var zones: [BoardZone] {
            switch self {
            case .number(let n): return [.sector(n)]
            case .double(let n): return [.double(n)]
            case .treble(let n): return [.treble(n)]
            case .anyDouble: return (1...20).map(BoardZone.double) + [.innerBull]
            case .anyTreble: return (1...20).map(BoardZone.treble)
            case .bull: return [.bull]
            }
        }
    }

    let targets: [Target]
    var points: [Int]
    var hitThisTurn = false

    init(players: Int, targets: [String], start: Int) {
        self.targets = targets.map(Target.init)
        points = Array(repeating: start, count: players)
    }

    var roundLimit: Int? { targets.count }
    func isOut(_ player: Int) -> Bool { false }
    mutating func startTurn(player: Int, round: Int, events: inout [GameEvent]) { hitThisTurn = false }

    mutating func dart(_ hit: Hit, player: Int, round: Int, volley: [Hit], events: inout [GameEvent]) -> ReviewVerdict {
        if targets[round - 1].counts(hit) {
            points[player] += hit.points
            hitThisTurn = true
            events.append(.targetScored(player: player, points: hit.points))
        } else {
            events.append(.noEffect(player: player))
        }
        return .goOn
    }

    mutating func closeTurn(player: Int, round: Int, volley: [Hit], events: inout [GameEvent]) {
        guard !hitThisTurn else { return }
        points[player] = (points[player] + 1) / 2
        events.append(.halved(player: player, points: points[player]))
    }

    func ranks() -> [Int] { reviewRanks(points.map { [-$0] }) }

    func playerFacts(_ player: Int, current: Int, phase: GamePhase) -> [String: FactValue] {
        // "Cible touchée" is about the turn in progress: there is none once the game is over.
        ["points": .int(points[player]), "hitThisTurn": .bool(player == current && phase != .finished && hitThisTurn)]
    }

    func gameFacts(round: Int) -> [String: FactValue] { ["target": .text(targets[round - 1].notation)] }

    func highlights(current: Int, round: Int) -> Set<BoardHighlight> {
        Set(targets[round - 1].zones.map { BoardHighlight(zone: $0, role: .target) })
    }
}

// MARK: - Moon Landing (GAMES.md §10)

private struct ReviewMoonLanding: ReviewModel {
    var captionsNoEffect: Bool { false }
    let exact: Bool
    let limit: Int?
    var remaining: [Int]
    var darts: [Int]
    var busts: [Int]
    var start = 0
    var busted = false
    var counted = 0

    init(players: Int, distance: Int, exact: Bool, maxRounds: Int?) {
        self.exact = exact
        limit = maxRounds
        remaining = Array(repeating: distance, count: players)
        darts = Array(repeating: 0, count: players)
        busts = darts
    }

    var roundLimit: Int? { limit }
    func isOut(_ player: Int) -> Bool { false }

    mutating func startTurn(player: Int, round: Int, events: inout [GameEvent]) {
        start = remaining[player]
        busted = false
        counted = 0
    }

    mutating func dart(_ hit: Hit, player: Int, round: Int, volley: [Hit], events: inout [GameEvent]) -> ReviewVerdict {
        darts[player] += 1
        if hit.isMiss {
            events.append(.noEffect(player: player))
            return .goOn
        }
        let left = remaining[player] - hit.points
        if exact && left < 0 {
            remaining[player] = start
            busts[player] += 1
            busted = true
            events.append(.bust(player: player, reason: .belowZero))
            return .close
        }
        remaining[player] = max(0, left)
        counted += hit.points
        if remaining[player] == 0 {
            events.append(.landed(player: player))
            return .finish(.victory)
        }
        return .goOn
    }

    mutating func closeTurn(player: Int, round: Int, volley: [Hit], events: inout [GameEvent]) {
        guard !busted else { return }
        events.append(.turnScored(player: player, points: counted))
        if counted == 180 {
            events.append(.oneEighty(player: player))
        } else if counted >= 100 {
            events.append(.highTurn(player: player, points: counted))
        }
    }

    func ranks() -> [Int] { reviewRanks(remaining.map { [$0] }) }

    func playerFacts(_ player: Int, current: Int, phase: GamePhase) -> [String: FactValue] {
        ["remaining": .int(remaining[player]), "dartsThrown": .int(darts[player]), "busts": .int(busts[player])]
    }

    func gameFacts(round: Int) -> [String: FactValue] { [:] }

    /// GAMES.md §10.7: in Pro mode, every bed worth exactly the distance left.
    func highlights(current: Int, round: Int) -> Set<BoardHighlight> {
        guard exact else { return [] }
        return Set(Hit.all.filter { !$0.isMiss && $0.points == remaining[current] }.compactMap(reviewZone).map {
            BoardHighlight(zone: $0, role: .target)
        })
    }
}

// MARK: - Fight (GAMES.md §11)

private struct ReviewFight: ReviewModel {
    var captionsNoEffect: Bool { true }
    let maximum: Int
    let limit: Int?
    let heal: [Int]
    let weak: [[Int]]
    var lives: [Int]
    var kills: [Int]
    var order: [Int] = []

    init(players: Int, lives: Int, maxRounds: Int?, seed: UInt64) {
        var random = SeededRandom(seed: seed)
        let s = random.shuffled(Array(1...20))
        heal = (0..<players).map { s[3 * $0] }
        weak = (0..<players).map { [s[3 * $0 + 1], s[3 * $0 + 2]] }
        maximum = lives
        limit = maxRounds
        self.lives = Array(repeating: lives, count: players)
        kills = Array(repeating: 0, count: players)
    }

    var roundLimit: Int? { limit }
    func isOut(_ player: Int) -> Bool { order.contains(player) }
    mutating func startTurn(player: Int, round: Int, events: inout [GameEvent]) {}

    mutating func dart(_ hit: Hit, player: Int, round: Int, volley: [Hit], events: inout [GameEvent]) -> ReviewVerdict {
        guard let number = hit.number else {
            events.append(.noEffect(player: player))
            return .goOn
        }
        let m = hit.multiplier
        if number == heal[player] {
            if lives[player] == maximum {
                events.append(.healWasted(player: player))
            } else {
                let gain = min(maximum, lives[player] + m) - lives[player]
                lives[player] += gain
                events.append(.healed(player: player, amount: gain, lives: lives[player]))
            }
            return .goOn
        }
        guard let victim = lives.indices.first(where: { $0 != player && !isOut($0) && weak[$0].contains(number) }) else {
            events.append(.noEffect(player: player))
            return .goOn
        }
        let loss = min(m, lives[victim])
        lives[victim] -= loss
        events.append(.damaged(player: victim, by: player, amount: loss, livesLeft: lives[victim]))
        guard lives[victim] == 0 else { return .goOn }
        order.append(victim)
        kills[player] += 1
        events.append(.playerEliminated(player: victim, by: player))
        return lives.indices.filter { !isOut($0) }.count == 1 ? .finish(.lastPlayerStanding) : .goOn
    }

    mutating func closeTurn(player: Int, round: Int, volley: [Hit], events: inout [GameEvent]) {}

    func ranks() -> [Int] {
        reviewEliminationRanks(lives.indices.map { isOut($0) ? nil : [-lives[$0], -kills[$0]] }, order: order)
    }

    func playerFacts(_ player: Int, current: Int, phase: GamePhase) -> [String: FactValue] {
        ["lives": .int(lives[player]), "healNumber": .int(heal[player]), "kills": .int(kills[player]),
         "weakNumbers": .ints(weak[player]), "eliminated": .bool(isOut(player))]
    }

    func gameFacts(round: Int) -> [String: FactValue] { [:] }

    /// GAMES.md §11.7 and ARCHITECTURE.md §5.6.
    func highlights(current: Int, round: Int) -> Set<BoardHighlight> {
        var set: Set<BoardHighlight> = [BoardHighlight(zone: .sector(heal[current]), role: lives[current] < maximum ? .secondary : .own,
                                                       owner: current, marker: .heal)]
        for opponent in lives.indices where opponent != current && !isOut(opponent) {
            for number in weak[opponent] { set.insert(BoardHighlight(zone: .sector(number), role: .target, owner: opponent)) }
        }
        return set
    }
}

// MARK: - Conqueror (GAMES.md §12)

private struct ReviewConqueror: ReviewModel {
    var captionsNoEffect: Bool { true }
    let multipliers: Bool
    let limit: Int?
    let home: [Int]
    /// Owner and lives of the sector `n`, by number.
    var owner: [Int: Int] = [:]
    var lives: [Int: Int] = [:]
    var king: Int?
    var order: [Int] = []

    init(players: Int, multipliers: Bool, maxRounds: Int?, seed: UInt64) {
        var random = SeededRandom(seed: seed)
        home = ringLayout(playerCount: players, width: 2, rng: &random).map { $0[0] }
        self.multipliers = multipliers
        limit = maxRounds
        for (player, sector) in home.enumerated() {
            owner[sector] = player
            lives[sector] = 3
        }
    }

    var roundLimit: Int? { limit }
    func isOut(_ player: Int) -> Bool { order.contains(player) }
    mutating func startTurn(player: Int, round: Int, events: inout [GameEvent]) {}

    func adjacent(_ sector: Int, _ player: Int) -> Bool { reviewNeighbours(sector).contains { owner[$0] == player } }

    mutating func dart(_ hit: Hit, player: Int, round: Int, volley: [Hit], events: inout [GameEvent]) -> ReviewVerdict {
        if hit.isMiss {
            events.append(.noEffect(player: player))
            return .goOn
        }
        guard let s = hit.number else {
            if king == player {
                events.append(.noEffect(player: player))
            } else {
                king = player
                events.append(.kingOfTheHill(player: player))
            }
            return .goOn
        }
        let m = multipliers ? hit.multiplier : 1
        switch owner[s] {
        case player?:
            let before = lives[s] ?? 0
            if before == 3 {
                events.append(.noEffect(player: player))
            } else {
                lives[s] = min(3, before + m)
                events.append(.sectorStrengthened(player: player, sector: s, lives: lives[s] ?? 0))
            }
        case nil:
            if adjacent(s, player) {
                owner[s] = player
                lives[s] = min(3, m)
                events.append(.sectorClaimed(player: player, sector: s))
            } else {
                events.append(.noEffect(player: player))
            }
        case let q?:
            guard adjacent(s, player) || king == player else {
                events.append(.noEffect(player: player))
                return .goOn
            }
            let left = (lives[s] ?? 0) - m
            if left > 0 {
                lives[s] = left
                events.append(.sectorDamaged(player: player, sector: s, livesLeft: left))
                return .goOn
            }
            owner[s] = player
            lives[s] = 1
            events.append(.sectorConquered(player: player, sector: s, from: q))
            if home[q] == s {
                for (sector, holder) in owner where holder == q { owner[sector] = player }
                if king == q { king = nil }
                order.append(q)
                events.append(.playerEliminated(player: q, by: player))
                if home.indices.filter({ !isOut($0) }).count == 1 { return .finish(.lastPlayerStanding) }
            }
        }
        return .goOn
    }

    mutating func closeTurn(player: Int, round: Int, volley: [Hit], events: inout [GameEvent]) {}

    func sectors(_ player: Int) -> [Int: Int] {
        var map: [Int: Int] = [:]
        for (sector, holder) in owner where holder == player { map[sector] = lives[sector] ?? 0 }
        return map
    }

    func ranks() -> [Int] {
        reviewEliminationRanks(home.indices.map { player in
            let mine = sectors(player)
            return isOut(player) ? nil : [-mine.values.reduce(0, +), -mine.count]
        }, order: order)
    }

    func playerFacts(_ player: Int, current: Int, phase: GamePhase) -> [String: FactValue] {
        let mine = sectors(player)
        return ["sectors": .map(mine), "totalLives": .int(mine.values.reduce(0, +)), "sectorCount": .int(mine.count),
                "homeSector": .int(home[player]), "eliminated": .bool(isOut(player))]
    }

    func gameFacts(round: Int) -> [String: FactValue] { ["king": .int(king ?? -1)] }

    /// GAMES.md §12.7 and ARCHITECTURE.md §5.6: roles, owner colours, shields (`strength`), home and crown markers.
    func highlights(current p: Int, round: Int) -> Set<BoardHighlight> {
        var set: Set<BoardHighlight> = []
        for s in 1...20 {
            guard let q = owner[s] else {
                if adjacent(s, p) { set.insert(BoardHighlight(zone: .sector(s), role: .target)) }
                continue
            }
            let role: HighlightRole = q == p ? ((lives[s] ?? 0) < 3 ? .secondary : .own)
                                             : (adjacent(s, p) || king == p ? .target : .opponent)
            let standingHome = home[q] == s && !isOut(q)
            set.insert(BoardHighlight(zone: .sector(s), role: role, owner: q, strength: lives[s],
                                      marker: standingHome ? .home : nil))
        }
        set.insert(BoardHighlight(zone: .bull, role: king == p ? .own : .secondary, owner: king, marker: king == nil ? nil : .crown))
        return set
    }
}

// MARK: - Suites

@Suite struct FightReviewTests {
    /// Darts on the numbers that matter (heal numbers, weak spots) most of the time.
    private static func pick(_ random: inout SeededRandom, _ match: GameMatch) -> Hit {
        guard random.nextInt(below: 4) != 0 else { return reviewAnyHit(&random) }
        let player = random.nextInt(below: match.players.count)
        var numbers: [Int] = []
        if case .int(let heal)? = match.fact(player, "healNumber") { numbers.append(heal) }
        if case .ints(let weak)? = match.fact(player, "weakNumbers") { numbers += weak }
        guard !numbers.isEmpty else { return reviewAnyHit(&random) }
        return reviewDart(on: numbers[random.nextInt(below: numbers.count)], &random)
    }

    @Test(arguments: [(2, 9, 15, UInt64(1)), (3, 3, 99, UInt64(2)), (4, 2, 4, UInt64(42)), (6, 1, 3, UInt64(7)),
                      (5, 20, 2, UInt64(0)), (2, 1, 99, UInt64(9))])
    func review_fightAgreesWithTheModelOnRandomJournals(players: Int, lives: Int, rounds: Int, seed: UInt64) throws {
        let limit: Int? = rounds == 99 ? nil : rounds
        let options: GameOptions = ["lives": .int(lives), "maxRounds": limit.map(OptionValue.int) ?? .null]
        let totals = try ReviewFuzz.run(.fight, options, players: players, seed: seed, fuzzSeed: seed &+ 500, steps: 500,
                                        model: ReviewFight(players: players, lives: lives, maxRounds: limit, seed: seed),
                                        dart: Self.pick)
        #expect(totals.inputs > 250 && totals.edits > 60 && totals.finished > 0)
    }
}

@Suite struct ConquerorReviewTests {
    /// Darts on owned sectors, their neighbours and the bull most of the time.
    private static func pick(_ random: inout SeededRandom, _ match: GameMatch) -> Hit {
        switch random.nextInt(below: 9) {
        case 0: return reviewAnyHit(&random)
        case 1: return random.nextInt(below: 2) == 0 ? .outerBull : .innerBull
        case 2:
            // A home, as a treble: with multipliers, one dart takes a home that has three lives.
            let player = random.nextInt(below: match.players.count)
            guard case .int(let home)? = match.fact(player, "homeSector") else { return reviewAnyHit(&random) }
            return .treble(home)
        default:
            let player = random.nextInt(below: match.players.count)
            guard case .map(let sectors)? = match.fact(player, "sectors"), !sectors.isEmpty else { return reviewAnyHit(&random) }
            let owned = sectors.keys.sorted()
            let sector = owned[random.nextInt(below: owned.count)]
            let around = [sector] + reviewNeighbours(sector)
            return reviewDart(on: around[random.nextInt(below: 3)], &random)
        }
    }

    @Test(arguments: [(2, false, 15, UInt64(1)), (3, true, 99, UInt64(1)), (4, false, 6, UInt64(42)), (8, true, 4, UInt64(1)),
                      (5, true, 99, UInt64(13)), (2, true, 2, UInt64(3))])
    func review_conquerorAgreesWithTheModelOnRandomJournals(players: Int, multipliers: Bool, rounds: Int, seed: UInt64) throws {
        let limit: Int? = rounds == 99 ? nil : rounds
        let options: GameOptions = ["multipliersCount": .bool(multipliers), "maxRounds": limit.map(OptionValue.int) ?? .null]
        let totals = try ReviewFuzz.run(.conqueror, options, players: players, seed: seed, fuzzSeed: seed &+ 900, steps: 600,
                                        model: ReviewConqueror(players: players, multipliers: multipliers, maxRounds: limit, seed: seed),
                                        dart: Self.pick)
        #expect(totals.inputs > 300 && totals.edits > 70)
    }

    /// GAMES.md §12.4: when the King loses his home, the crown is vacant. Seed 42, four players: homes 9, 16, 1, 17
    /// (CON-7). J2 takes the crown, J4 claims 3, 19 and 7 towards J2's home with trebles, then takes it in one dart.
    @Test func review_aKingWhoLosesHisHomeLeavesTheCrownVacant() throws {
        var match = try ReviewFuzz.script(.conqueror, ["multipliersCount": true], players: 4, seed: 42,
                                          model: ReviewConqueror(players: 4, multipliers: true, maxRounds: 15, seed: 42),
                                          "MISS ×3 | SB, MISS, MISS | MISS ×3 | T3, T19, T7 | MISS ×3 | MISS ×3 | MISS ×3 |")
        #expect((0..<4).map { match.fact($0, "homeSector") } == [9, 16, 1, 17])
        #expect(match.gameFact("king") == 1 && match.fact(3, "sectors") == [17: 3, 3: 3, 19: 3, 7: 3])
        let events = match.throwDart(DartRecord(hit: .treble(16))).events
        #expect(events == [.dartRegistered(player: 3, hit: .treble(16)), .sectorConquered(player: 3, sector: 16, from: 1),
                           .playerEliminated(player: 1, by: 3)])
        #expect(match.gameFact("king") == -1 && match.fact(1, "eliminated") == true && match.phase == .throwing)
        // Nobody wears the crown any more: the bull has no owner and no crown, for every player.
        #expect(match.snapshot.highlights.contains(BoardHighlight(zone: .bull, role: .secondary)))
        // The model agrees on the whole state after the capture.
        _ = try ReviewFuzz.script(.conqueror, ["multipliersCount": true], players: 4, seed: 42,
                                  model: ReviewConqueror(players: 4, multipliers: true, maxRounds: 15, seed: 42),
                                  "MISS ×3 | SB, MISS, MISS | MISS ×3 | T3, T19, T7 | MISS ×3 | MISS ×3 | MISS ×3 | T16")
    }
}

@Suite struct MoonLandingReviewTests {
    @Test(arguments: [(1, 200, false, 15), (2, 100, true, 99), (3, 150, true, 4), (8, 999, false, 2), (4, 100, false, 1)])
    func review_moonLandingAgreesWithTheModelOnRandomJournals(players: Int, distance: Int, exact: Bool, rounds: Int) throws {
        let limit: Int? = rounds == 99 ? nil : rounds
        let options: GameOptions = ["distance": .int(distance), "exactLanding": .bool(exact),
                                    "maxRounds": limit.map(OptionValue.int) ?? .null]
        let totals = try ReviewFuzz.run(.moonLanding, options, players: players, seed: 0, fuzzSeed: UInt64(distance + players),
                                        steps: 500, model: ReviewMoonLanding(players: players, distance: distance, exact: exact, maxRounds: limit),
                                        dart: { random, _ in reviewAnyHit(&random) })
        #expect(totals.inputs > 150 && totals.edits > 60)
    }

    /// GAMES.md §10.7 at every distance left from 1 to 99: in Pro mode the highlights are exactly the beds worth the
    /// distance (the bulls included, at 25 and 50), and each of them lands.
    @Test func review_proHighlightsAtEveryDistanceLeft() throws {
        for left in 1...99 {
            var match = try GameRegistry.standard.match(.moonLanding, ["distance": .int(100 + left), "exactLanding": true], players: 1)
            match.play("T20, D20")
            #expect(match.fact(0, "remaining") == .int(left) && match.phase == .throwing, "left \(left)")
            let beds = Hit.all.filter { !$0.isMiss && $0.points == left }
            #expect(Set(match.snapshot.highlights) == Set(beds.compactMap(reviewZone).map { BoardHighlight(zone: $0, role: .target) }),
                    "left \(left)")
            #expect(match.snapshot.highlights.count == beds.count, "left \(left)")
            for bed in beds {
                var copy = match
                #expect(copy.throwDart(DartRecord(hit: bed)).events.last == .gameFinished(reason: .victory), "left \(left), \(bed)")
            }
        }
    }
}

@Suite struct HalveItReviewTests {
    @Test(arguments: [
        (1, ["20", "16", "D7", "14", "T10", "BULL"], 0),
        (3, ["15", "16", "anyDouble", "17", "18", "anyTreble", "19", "20", "BULL"], 40),
        (2, ["anyDouble", "anyTreble"], 0),
        (8, ["BULL", "D20", "T1", "1", "anyDouble", "anyTreble", "D25", "5", "T20", "D1", "BULL", "2"].filter { $0 != "D25" }, 40),
        (4, ["D1"], 0),
    ])
    func review_halveItAgreesWithTheModelOnRandomJournals(players: Int, targets: [String], start: Int) throws {
        let options: GameOptions = ["targets": .strings(targets), "startingScore": .int(start)]
        let totals = try ReviewFuzz.run(.halveIt, options, players: players, seed: 0, fuzzSeed: UInt64(targets.count * 10 + players),
                                        steps: 500, model: ReviewHalveIt(players: players, targets: targets, start: start),
                                        dart: { random, _ in
            // Bulls, doubles and trebles often, so that every kind of target is hit.
            switch random.nextInt(below: 4) {
            case 0: return random.nextInt(below: 2) == 0 ? .outerBull : .innerBull
            case 1: return .double(1 + random.nextInt(below: 20))
            case 2: return .treble(1 + random.nextInt(below: 20))
            default: return reviewAnyHit(&random)
            }
        })
        #expect(totals.inputs > 250 && totals.edits > 60)
    }
}
