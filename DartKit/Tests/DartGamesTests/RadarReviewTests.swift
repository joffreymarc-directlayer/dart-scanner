import Foundation
import Testing
import DartCore
import DartGames
import DartTestSupport

// Adversarial review of lot G4 (Beer Tap, Football, Radar, Golf).
//
// Every game is modelled again here, from the text of GAMES.md §2, §13 to §16 and ARCHITECTURE.md §5.5 alone,
// with a turn machine of its own (GAMES.md §2.4, §2.5) that shares no code with `TurnBasedEngine` nor with the
// rules under review. Long random journals (darts, confirmations, undo, corrections with and without a
// position, removals) are then fed to the real game and to the model, and after EVERY operation the two must
// agree on: acceptance and events of the input, journal kept by the replay and darts it dropped, phase,
// current player, round, round limit, finish reason, ranks, every fact, the highlights, and `winnerTitle`.

// MARK: - Reference turn machine

/// What a reference rule says about one dart.
private enum ReviewVerdict {
    case goOn
    case close
    case finish(FinishReason)
}

/// The rules of one game, written from GAMES.md alone.
private protocol ReviewModel {
    var roundLimit: Int? { get }
    func isOut(_ player: Int) -> Bool
    /// Effects of the start of a turn; `first` only for the call made at creation.
    mutating func startTurn(player: Int, round: Int, first: Bool, random: inout SeededRandom, events: inout [GameEvent])
    mutating func dart(_ hit: Hit, position: BoardPoint?, player: Int, round: Int, volley: [Hit],
                       random: inout SeededRandom, events: inout [GameEvent]) -> ReviewVerdict
    mutating func closeTurn(player: Int, round: Int, volley: [Hit], events: inout [GameEvent])
    func ranks() -> [Int]
    func playerFacts(_ player: Int) -> [String: FactValue]
    func gameFacts(current: Int, volley: [Hit]) -> [String: FactValue]
    func highlights(current: Int, round: Int) -> Set<BoardHighlight>
    /// True when the game captions a dart without effect « Sans effet » / "No effect", and no other dart so.
    var captionsNoEffect: Bool { get }
    /// Results headline when the winner is not a player (Football only).
    func winnerTitle(ranks: [Int]) -> LocalizedText?
}

extension ReviewModel {
    func winnerTitle(ranks: [Int]) -> LocalizedText? { nil }
}

/// Shared competition ranking of GAMES.md §2.7: `1 + number of players strictly better`.
private func reviewRanks(_ keys: [[Int]]) -> [Int] {
    keys.map { key in 1 + keys.filter { $0.lexicographicallyPrecedes(key) }.count }
}

/// GAMES.md §2.4, read literally.
private struct ReviewGame<Model: ReviewModel> {
    var model: Model
    var random: SeededRandom
    let players: Int
    var phase = GamePhase.throwing
    var current = 0
    var round = 1
    var volley: [Hit] = []
    /// Events of each dart of the volley, `dartRegistered` included.
    var volleyEvents: [[GameEvent]] = []
    var finishReason: FinishReason?

    init(players: Int, seed: UInt64, make: (inout SeededRandom) -> Model) {
        var random = SeededRandom(seed: seed)
        var model = make(&random)
        var ignored: [GameEvent] = []
        model.startTurn(player: 0, round: 1, first: true, random: &random, events: &ignored)
        self.model = model
        self.random = random
        self.players = players
    }

    /// Events of an accepted input; nil when it is refused.
    mutating func apply(_ hit: Hit?, position: BoardPoint?) -> [GameEvent]? {
        guard let hit else { return endTurn() }
        guard phase == .throwing else { return nil }
        volley.append(hit)
        var events: [GameEvent] = [.dartRegistered(player: current, hit: hit)]
        let verdict = model.dart(hit, position: position, player: current, round: round, volley: volley,
                                 random: &random, events: &events)
        switch verdict {
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
        model.startTurn(player: current, round: round, first: false, random: &random, events: &events)
        events.append(.turnStarted(player: current, round: round))
        return events
    }
}

// MARK: - Random journals against the model

/// One dart or one confirmation of the journal, without the identity of the record.
private struct ReviewEntry: Equatable {
    var hit: Hit?
    var position: BoardPoint?

    init(_ entry: LogEntry) {
        switch entry {
        case .dart(let record): hit = record.hit; position = record.position
        case .endTurn: hit = nil; position = nil
        }
    }

    init(hit: Hit?, position: BoardPoint?) {
        self.hit = hit
        self.position = position
    }

    /// Positions are compared bit for bit: a NaN coordinate is a legal input and must survive the journal.
    static func == (a: ReviewEntry, b: ReviewEntry) -> Bool {
        a.hit == b.hit && a.position?.x.bitPattern == b.position?.x.bitPattern
            && a.position?.y.bitPattern == b.position?.y.bitPattern
    }
}

private enum ReviewFuzz {
    /// Plays `steps` random operations on the real game and on the model; see the head of this file.
    /// `dart` draws the next dart (hit and optional position) from the state shown by the real game.
    static func run<Model: ReviewModel>(
        _ game: GameID, _ options: GameOptions, players: Int, seed: UInt64, fuzzSeed: UInt64, steps: Int,
        make: @escaping (inout SeededRandom) -> Model,
        dart: (inout SeededRandom, GameMatch) -> (Hit, BoardPoint?)
    ) throws -> (inputs: Int, edits: Int, finished: Int) {
        let label = "\(game) \(options) players \(players) seed \(seed) fuzz \(fuzzSeed)"
        var match = try GameRegistry.standard.match(game, options, players: players, seed: seed)
        var model = ReviewGame(players: players, seed: seed, make: make)
        var journal: [ReviewEntry] = []
        // `states[k]` is the model after the first `k` entries of `journal`: the model is a pure function of the
        // journal, so a replay after an edit starts from the last state the edit leaves untouched.
        var states = [model]
        var random = SeededRandom(seed: fuzzSeed)
        var inputs = 0, edits = 0, finished = 0
        func replay(_ entries: [ReviewEntry]) -> (kept: [ReviewEntry], dropped: [ReviewEntry], states: [ReviewGame<Model>]) {
            var start = 0
            while start < min(entries.count, journal.count) && entries[start] == journal[start] { start += 1 }
            var fresh = states[start]
            var kept = Array(journal.prefix(start)), dropped: [ReviewEntry] = []
            var replayed = Array(states.prefix(start + 1))
            for entry in entries.dropFirst(start) {
                if fresh.apply(entry.hit, position: entry.position) != nil {
                    kept.append(entry)
                    replayed.append(fresh)
                } else if entry.hit != nil {
                    dropped.append(entry)
                }
            }
            return (kept, dropped, replayed)
        }
        /// Index in `journal` of dart `index` of the current turn: the darts after the last confirmation.
        func entryIndex(_ index: Int) -> Int? {
            let start = (journal.lastIndex { $0.hit == nil }).map { $0 + 1 } ?? 0
            let darts = (start..<journal.count).filter { journal[$0].hit != nil }
            return darts.indices.contains(index) ? darts[index] : nil
        }

        for step in 0..<steps {
            let where_ = "\(label) step \(step)"
            let choice = random.nextInt(below: 20)
            if match.phase == .finished && choice < 15 {
                // Most of the time a finished game is undone, so that the walk goes on.
                finished += 1
                let refused = match.endTurn()
                let modelRefused = model.apply(nil, position: nil)
                #expect(!refused.isAccepted && modelRefused == nil, "\(where_)")
                match.undo()
                journal.removeLast()
                states.removeLast()
                model = states[states.count - 1]
            } else if choice < 11 {
                let (hit, position) = dart(&random, match)
                let outcome = match.throwDart(DartRecord(hit: hit, position: position))
                let events = model.apply(hit, position: position)
                inputs += 1
                #expect(outcome.isAccepted == (events != nil), "\(where_): \(hit) accepted")
                if let events {
                    #expect(outcome.events == events, "\(where_): events of \(hit) at \(String(describing: position))")
                    journal.append(ReviewEntry(hit: hit, position: position))
                    states.append(model)
                }
            } else if choice < 15 {
                let outcome = match.endTurn()
                let events = model.apply(nil, position: nil)
                inputs += 1
                #expect(outcome.isAccepted == (events != nil), "\(where_): endTurn accepted")
                if let events {
                    #expect(outcome.events == events, "\(where_): events of endTurn")
                    journal.append(ReviewEntry(hit: nil, position: nil))
                    states.append(model)
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
                    let (hit, position) = dart(&random, match)
                    result = match.replaceDart(at: index, with: hit, position: position)
                    if let entry = entryIndex(index) { edited[entry] = ReviewEntry(hit: hit, position: position) }
                default:
                    let index = random.nextInt(below: 3)
                    result = match.removeDart(at: index)
                    if let entry = entryIndex(index) { edited.remove(at: entry) }
                }
                let (kept, dropped, replayed) = replay(edited)
                #expect(result.dropped.map { ReviewEntry(.dart($0)) } == dropped, "\(where_): dropped darts")
                states = replayed
                model = replayed[replayed.count - 1]
                journal = kept
            }
            compare(match, model, journal, where_)
        }
        return (inputs, edits, finished)
    }

    static func compare<Model: ReviewModel>(_ match: GameMatch, _ model: ReviewGame<Model>, _ journal: [ReviewEntry],
                                            _ where_: String) {
        let snapshot = match.snapshot
        #expect(match.entries.map(ReviewEntry.init) == journal, "\(where_): journal")
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
        #expect(snapshot.players.map(\.rank) == ranks, "\(where_): row ranks")
        for player in 0..<model.players {
            #expect(snapshot.players[player].facts == model.model.playerFacts(player), "\(where_): facts of J\(player + 1)")
            #expect(snapshot.players[player].isEliminated == model.model.isOut(player), "\(where_): J\(player + 1) out")
        }
        #expect(snapshot.facts == model.model.gameFacts(current: model.current, volley: model.volley), "\(where_): game facts")
        let highlights = model.phase == .finished ? [] : model.model.highlights(current: model.current, round: model.round)
        #expect(Set(snapshot.highlights) == highlights, "\(where_): highlights")
        #expect(snapshot.highlights.count == highlights.count, "\(where_): no highlight twice")
        let title = model.phase == .finished ? model.model.winnerTitle(ranks: ranks) : nil
        #expect(snapshot.winnerTitle == title, "\(where_): winnerTitle")
        #expect((snapshot.outcome != nil) == (model.phase == .finished), "\(where_): outcome only once finished")
    }
}

// MARK: - Beer Tap (GAMES.md §13)

private struct ReviewBeerTap: ReviewModel {
    var captionsNoEffect: Bool { false }
    let glass: Int
    let rounds: Int
    var poured: [Int]
    var bonus: [Int]
    var darts: [Int]

    init(players: Int, glass: Int, rounds: Int) {
        self.glass = glass
        self.rounds = rounds
        poured = Array(repeating: 0, count: players)
        bonus = poured
        darts = poured
    }

    var roundLimit: Int? { rounds }
    func isOut(_ player: Int) -> Bool { false }
    mutating func startTurn(player: Int, round: Int, first: Bool, random: inout SeededRandom, events: inout [GameEvent]) {}

    mutating func dart(_ hit: Hit, position: BoardPoint?, player: Int, round: Int, volley: [Hit],
                       random: inout SeededRandom, events: inout [GameEvent]) -> ReviewVerdict {
        darts[player] += 1
        if hit.isMiss {
            events.append(.noEffect(player: player))
            return .goOn
        }
        let before = poured[player] / glass
        poured[player] += hit.points
        let after = poured[player] / glass
        if after > before { events.append(.glassFilled(player: player, count: after - before, glasses: after)) }
        return .goOn
    }

    mutating func closeTurn(player: Int, round: Int, volley: [Hit], events: inout [GameEvent]) {
        let total = volley.map(\.points).reduce(0, +)
        events.append(.turnScored(player: player, points: total))
        if total == 180 {
            events.append(.oneEighty(player: player))
        } else if total >= 100 {
            events.append(.highTurn(player: player, points: total))
        }
        if total >= 100 {
            poured[player] += glass
            bonus[player] += 1
            events.append(.bonusGlass(player: player, glasses: poured[player] / glass))
        }
    }

    func ranks() -> [Int] { reviewRanks(poured.map { [-$0] }) }

    func playerFacts(_ player: Int) -> [String: FactValue] {
        ["poured": .int(poured[player]), "glasses": .int(poured[player] / glass), "level": .int(poured[player] % glass),
         "bonusGlasses": .int(bonus[player]), "dartsThrown": .int(darts[player])]
    }

    func gameFacts(current: Int, volley: [Hit]) -> [String: FactValue] { [:] }
    func highlights(current: Int, round: Int) -> Set<BoardHighlight> { [] }
}

// MARK: - Football (GAMES.md §14)

private struct ReviewFootball: ReviewModel {
    var captionsNoEffect: Bool { true }
    static let right = [1, 18, 4, 13, 6, 10, 15, 2, 17]
    static let left = [19, 7, 16, 8, 11, 14, 9, 12, 5]
    let players: Int
    let goalsToWin: Int
    let limit: Int?
    let step: [Int]
    let distance: Int
    var ball = 0
    var goals = [0, 0]
    var scored: [Int]

    init(players: Int, fieldLength: Int, goalsToWin: Int, maxRounds: Int?) {
        self.players = players
        self.goalsToWin = goalsToWin
        limit = maxRounds
        let sizeA = (players + 1) / 2, sizeB = players / 2
        var g = sizeA, h = sizeB
        while h > 0 { (g, h) = (h, g % h) }
        step = [sizeB / g, sizeA / g]
        distance = fieldLength * step[1]
        scored = Array(repeating: 0, count: players)
    }

    var roundLimit: Int? { limit }
    func isOut(_ player: Int) -> Bool { false }
    mutating func startTurn(player: Int, round: Int, first: Bool, random: inout SeededRandom, events: inout [GameEvent]) {}

    mutating func dart(_ hit: Hit, position: BoardPoint?, player: Int, round: Int, volley: [Hit],
                       random: inout SeededRandom, events: inout [GameEvent]) -> ReviewVerdict {
        let side = player % 2
        let s = step[side]
        var move = 0
        if hit.bed == .innerBull {
            return goal(side, player, &events)
        } else if hit.bed == .outerBull {
            move = side == 0 ? 2 * s : -2 * s
        } else if let n = hit.number, Self.right.contains(n) {
            move = hit.multiplier * s
        } else if let n = hit.number, Self.left.contains(n) {
            move = -hit.multiplier * s
        } else {
            // MISS, the 20 and the 3.
            events.append(.noEffect(player: player))
            return .goOn
        }
        ball = min(distance, max(-distance, ball + move))
        events.append(.ballMoved(player: player, by: move, ball: ball))
        if ball == distance { return goal(0, player, &events) }
        if ball == -distance { return goal(1, player, &events) }
        return .goOn
    }

    private mutating func goal(_ credited: Int, _ player: Int, _ events: inout [GameEvent]) -> ReviewVerdict {
        goals[credited] += 1
        let own = credited != player % 2
        if !own { scored[player] += 1 }
        ball = 0
        events.append(.goalScored(player: player, side: credited, goals: goals[credited], ownGoal: own))
        return goals[credited] == goalsToWin ? .finish(.victory) : .goOn
    }

    mutating func closeTurn(player: Int, round: Int, volley: [Hit], events: inout [GameEvent]) {}

    func ranks() -> [Int] {
        reviewRanks((0..<players).map { p in p % 2 == 0 ? [-goals[0], -ball] : [-goals[1], ball] })
    }

    func playerFacts(_ player: Int) -> [String: FactValue] {
        ["side": .int(player % 2), "goalsScored": .int(scored[player])]
    }

    func gameFacts(current: Int, volley: [Hit]) -> [String: FactValue] {
        ["ball": .int(ball), "sideGoals": .ints(goals), "goalDistance": .int(distance), "step": .ints(step)]
    }

    func highlights(current: Int, round: Int) -> Set<BoardHighlight> {
        let (attacked, defended) = current % 2 == 0 ? (Self.right, Self.left) : (Self.left, Self.right)
        return Set(attacked.map { BoardHighlight(zone: .sector($0), role: .target) }
                   + defended.map { BoardHighlight(zone: .sector($0), role: .avoid) }
                   + [BoardHighlight(zone: .bull, role: .target)])
    }

    /// GAMES.md §14.7: the side whose players are ranked first; a draw when every player is.
    func winnerTitle(ranks: [Int]) -> LocalizedText? {
        if ranks.allSatisfy({ $0 == 1 }) { return LocalizedText(fr: "Match nul", en: "It's a draw") }
        return ranks[0] == 1 ? LocalizedText(fr: "Le camp A gagne", en: "Side A wins")
                             : LocalizedText(fr: "Le camp B gagne", en: "Side B wins")
    }
}

// MARK: - Radar (GAMES.md §15)

private struct ReviewRadar: ReviewModel {
    var captionsNoEffect: Bool { true }
    /// Radius, hit points, points per hit, bonus of the five slots.
    static let slots: [(radius: Int, hitPoints: Int, value: Int, bonus: Int)] =
        [(40, 3, 10, 20), (40, 3, 10, 20), (28, 2, 20, 40), (28, 2, 20, 40), (16, 1, 50, 100)]

    struct Blob: Hashable {
        var x: Int
        var y: Int
        var hitPoints: Int
    }

    let moving: Bool
    let rounds: Int
    var blobs: [Blob] = []
    var points: [Int]
    var destroyed: [Int]
    var darts: [Int]
    var turnPoints = 0

    /// The lattice of §15.3, step 1, in drawing order: rows by `y` rising, `x` rising inside a row.
    static func inside(radius: Int) -> [(Int, Int)] {
        var list: [(Int, Int)] = []
        for y in stride(from: -170, through: 170, by: 5) {
            for x in stride(from: -170, through: 170, by: 5) where x * x + y * y <= (170 - radius) * (170 - radius) {
                list.append((x, y))
            }
        }
        return list
    }

    /// The three radii of the game, computed once (the model replays a whole game at every correction).
    static let gameLattice: [Int: [(Int, Int)]] = [16: inside(radius: 16), 28: inside(radius: 28), 40: inside(radius: 40)]

    /// GAMES.md §15.3, steps 1 and 2, point by point.
    static func candidates(radius: Int, obstacles: [(x: Int, y: Int, r: Int)]) -> [(Int, Int)] {
        let lattice = gameLattice[radius] ?? inside(radius: radius)
        let free = lattice.filter { x, y in
            !obstacles.contains { o in
                (x - o.x) * (x - o.x) + (y - o.y) * (y - o.y) < (radius + o.r + 6) * (radius + o.r + 6)
            }
        }
        return free.isEmpty ? lattice : free
    }

    static func place(radius: Int, obstacles: [(x: Int, y: Int, r: Int)], random: inout SeededRandom) -> (Int, Int) {
        let list = candidates(radius: radius, obstacles: obstacles)
        return list[random.nextInt(below: list.count)]
    }

    private var obstacles: [(x: Int, y: Int, r: Int)] {
        blobs.indices.map { (blobs[$0].x, blobs[$0].y, Self.slots[$0].radius) }
    }

    init(players: Int, moving: Bool, rounds: Int, random: inout SeededRandom) {
        self.moving = moving
        self.rounds = rounds
        points = Array(repeating: 0, count: players)
        destroyed = points
        darts = points
        for slot in Self.slots {
            let centre = Self.place(radius: slot.radius, obstacles: obstacles, random: &random)
            blobs.append(Blob(x: centre.0, y: centre.1, hitPoints: slot.hitPoints))
        }
    }

    var roundLimit: Int? { rounds }
    func isOut(_ player: Int) -> Bool { false }

    mutating func startTurn(player: Int, round: Int, first: Bool, random: inout SeededRandom, events: inout [GameEvent]) {
        turnPoints = 0
        guard moving && !first else { return }
        for slot in 0..<5 {
            let centre = Self.place(radius: Self.slots[slot].radius, obstacles: obstacles, random: &random)
            blobs[slot].x = centre.0
            blobs[slot].y = centre.1
        }
        events.append(.blobsMoved)
    }

    /// GAMES.md §2.13: tenths, halves away from zero, non-finite pushed to 1 000 000, bounded by ±1 000 000.
    private static func tenths(_ millimetres: Double) -> Int {
        let value = (10 * millimetres).rounded(.toNearestOrAwayFromZero)
        if !value.isFinite { return 1_000_000 }
        return Int(min(1_000_000, max(-1_000_000, value)))
    }

    mutating func dart(_ hit: Hit, position: BoardPoint?, player: Int, round: Int, volley: [Hit],
                       random: inout SeededRandom, events: inout [GameEvent]) -> ReviewVerdict {
        darts[player] += 1
        var impact: (Int, Int)?
        if !hit.isMiss {
            if let position {
                impact = (Self.tenths(position.x), Self.tenths(position.y))
            } else if let canonical = ImpactPoint.canonical(of: hit) {
                impact = (canonical.x, canonical.y)
            }
        }
        guard let (x, y) = impact, let slot = blobs.indices.first(where: { k in
            let dx = x - 10 * blobs[k].x, dy = y - 10 * blobs[k].y, r = 10 * Self.slots[k].radius
            return dx * dx + dy * dy <= r * r
        }) else {
            events.append(.noEffect(player: player))
            return .goOn
        }
        let size = Self.slots[slot]
        if blobs[slot].hitPoints > 1 {
            blobs[slot].hitPoints -= 1
            points[player] += size.value
            turnPoints += size.value
            events.append(.blobDamaged(player: player, blob: slot, points: size.value, hitPointsLeft: blobs[slot].hitPoints))
            return .goOn
        }
        points[player] += size.value + size.bonus
        turnPoints += size.value + size.bonus
        destroyed[player] += 1
        events.append(.blobDestroyed(player: player, blob: slot, points: size.value + size.bonus))
        let centre = Self.place(radius: size.radius, obstacles: obstacles, random: &random)
        blobs[slot] = Blob(x: centre.0, y: centre.1, hitPoints: size.hitPoints)
        return .goOn
    }

    mutating func closeTurn(player: Int, round: Int, volley: [Hit], events: inout [GameEvent]) {
        events.append(.turnScored(player: player, points: turnPoints))
    }

    func ranks() -> [Int] { reviewRanks(points.indices.map { [-points[$0], -destroyed[$0]] }) }

    func playerFacts(_ player: Int) -> [String: FactValue] {
        ["points": .int(points[player]), "destroyed": .int(destroyed[player]), "dartsThrown": .int(darts[player])]
    }

    func gameFacts(current: Int, volley: [Hit]) -> [String: FactValue] {
        ["blobs": .table(blobs.indices.map { [blobs[$0].x, blobs[$0].y, Self.slots[$0].radius, blobs[$0].hitPoints] })]
    }

    func highlights(current: Int, round: Int) -> Set<BoardHighlight> {
        Set(blobs.indices.map { k in
            BoardHighlight(zone: .disc(x: Double(blobs[k].x), y: Double(blobs[k].y), radius: Double(Self.slots[k].radius)),
                           role: .target, label: "+\(Self.slots[k].value)", strength: blobs[k].hitPoints)
        })
    }
}

// MARK: - Golf (GAMES.md §16)

private struct ReviewGolf: ReviewModel {
    var captionsNoEffect: Bool { false }
    let holes: Int
    let best: Bool
    var strokes: [Int]
    var scores: [[Int]]

    init(players: Int, holes: Int, best: Bool) {
        self.holes = holes
        self.best = best
        strokes = Array(repeating: 0, count: players)
        scores = Array(repeating: [], count: players)
    }

    static func value(_ hit: Hit, hole: Int) -> Int {
        guard hit.number == hole else { return 5 }
        return hit.bed == .double ? 1 : hit.bed == .treble ? 2 : 3
    }

    func provisional(_ volley: [Hit], hole: Int) -> Int {
        let values = volley.map { Self.value($0, hole: hole) }
        guard let last = values.last else { return 5 }
        return best ? (values.min() ?? 5) : last
    }

    var roundLimit: Int? { holes }
    func isOut(_ player: Int) -> Bool { false }
    mutating func startTurn(player: Int, round: Int, first: Bool, random: inout SeededRandom, events: inout [GameEvent]) {}

    mutating func dart(_ hit: Hit, position: BoardPoint?, player: Int, round: Int, volley: [Hit],
                       random: inout SeededRandom, events: inout [GameEvent]) -> ReviewVerdict {
        let value = Self.value(hit, hole: round)
        events.append(.shotPlayed(player: player, strokes: value))
        return value == 1 ? .close : .goOn
    }

    mutating func closeTurn(player: Int, round: Int, volley: [Hit], events: inout [GameEvent]) {
        let score = provisional(volley, hole: round)
        strokes[player] += score
        scores[player].append(score)
        events.append(.holeCompleted(player: player, hole: round, strokes: score, total: strokes[player]))
        if score == 1 { events.append(.holeInOne(player: player, hole: round)) }
    }

    func toPar(_ player: Int) -> Int { strokes[player] - 3 * scores[player].count }
    func ranks() -> [Int] { reviewRanks(strokes.indices.map { [toPar($0)] }) }

    func playerFacts(_ player: Int) -> [String: FactValue] {
        ["strokes": .int(strokes[player]), "holesPlayed": .int(scores[player].count), "holeScores": .ints(scores[player]),
         "toPar": .int(toPar(player))]
    }

    /// The hole of the volley is the round; the model reads it back from the closed holes of the current player.
    var currentHole = 1
    func gameFacts(current: Int, volley: [Hit]) -> [String: FactValue] {
        ["provisional": .int(provisional(volley, hole: currentHole))]
    }

    func highlights(current: Int, round: Int) -> Set<BoardHighlight> {
        [BoardHighlight(zone: .double(round), role: .target, label: "1"),
         BoardHighlight(zone: .treble(round), role: .target, label: "2"),
         BoardHighlight(zone: .single(round), role: .secondary, label: "3")]
    }
}

/// Golf needs the hole in `gameFacts`: the model keeps it up to date at every start of turn.
private struct ReviewGolfTracked: ReviewModel {
    var captionsNoEffect: Bool { false }
    var golf: ReviewGolf
    var roundLimit: Int? { golf.roundLimit }
    func isOut(_ player: Int) -> Bool { false }
    mutating func startTurn(player: Int, round: Int, first: Bool, random: inout SeededRandom, events: inout [GameEvent]) {
        golf.currentHole = round
    }
    mutating func dart(_ hit: Hit, position: BoardPoint?, player: Int, round: Int, volley: [Hit],
                       random: inout SeededRandom, events: inout [GameEvent]) -> ReviewVerdict {
        golf.dart(hit, position: position, player: player, round: round, volley: volley, random: &random, events: &events)
    }
    mutating func closeTurn(player: Int, round: Int, volley: [Hit], events: inout [GameEvent]) {
        golf.closeTurn(player: player, round: round, volley: volley, events: &events)
    }
    func ranks() -> [Int] { golf.ranks() }
    func playerFacts(_ player: Int) -> [String: FactValue] { golf.playerFacts(player) }
    func gameFacts(current: Int, volley: [Hit]) -> [String: FactValue] { golf.gameFacts(current: current, volley: volley) }
    func highlights(current: Int, round: Int) -> Set<BoardHighlight> { golf.highlights(current: current, round: round) }
}

// MARK: - Dart pickers

/// A dart drawn uniformly from the 63 beds.
private func reviewAnyHit(_ random: inout SeededRandom) -> Hit {
    Hit.all[random.nextInt(below: Hit.all.count)]
}

// MARK: - Suites

@Suite struct RadarReviewTests {
    /// The tip of a dart: aimed at a target (inside, on the edge, just outside), anywhere in the ±180 mm square,
    /// at a canonical point, not finite, or absent.
    private static func tip(_ random: inout SeededRandom, _ match: GameMatch) -> (Hit, BoardPoint?) {
        let hit = random.nextInt(below: 12) == 0 ? Hit.miss : reviewAnyHit(&random)
        guard case .table(let rows)? = match.gameFact("blobs"), rows.count == 5 else { return (hit, nil) }
        switch random.nextInt(below: 10) {
        case 0, 1:
            return (hit, nil)
        case 2:
            let wild: [Double] = [.nan, .infinity, -.infinity, 1e300, 99_999.95, -100_000.05]
            return (hit, BoardPoint(x: wild[random.nextInt(below: wild.count)], y: Double(random.nextInt(below: 341) - 170)))
        case 3:
            return (hit, BoardPoint(x: Double(random.nextInt(below: 3601) - 1800) / 10,
                                    y: Double(random.nextInt(below: 3601) - 1800) / 10))
        case 4, 5:
            // On the edge of a target, on an axis, or 0.05 mm on either side of it (halves away from zero).
            let row = rows[random.nextInt(below: 5)]
            let nudge = [0.0, 0.05, -0.05, 0.04, -0.06][random.nextInt(below: 5)]
            let sign = random.nextInt(below: 2) == 0 ? 1.0 : -1.0
            return random.nextInt(below: 2) == 0
                ? (hit, BoardPoint(x: Double(row[0]) + sign * (Double(row[2]) + nudge), y: Double(row[1])))
                : (hit, BoardPoint(x: Double(row[0]), y: Double(row[1]) + sign * (Double(row[2]) + nudge)))
        default:
            let row = rows[random.nextInt(below: 5)]
            let reach = 10 * row[2]
            return (hit, BoardPoint(x: Double(10 * row[0] + random.nextInt(below: 2 * reach + 1) - reach) / 10,
                                    y: Double(10 * row[1] + random.nextInt(below: 2 * reach + 1) - reach) / 10))
        }
    }

    @Test(arguments: [(false, 1, UInt64(1)), (true, 2, UInt64(7)), (false, 3, UInt64(42)), (true, 1, UInt64(0)),
                      (true, 4, UInt64(99)), (false, 8, UInt64(5))])
    func review_radarAgreesWithTheModelOnRandomJournals(moving: Bool, players: Int, seed: UInt64) throws {
        let rounds = 1 + Int(seed % 5)
        let options: GameOptions = ["movingTargets": .bool(moving), "rounds": .int(rounds)]
        let totals = try ReviewFuzz.run(.radar, options, players: players, seed: seed, fuzzSeed: seed &+ 1000, steps: 600,
                                        make: { ReviewRadar(players: players, moving: moving, rounds: rounds, random: &$0) },
                                        dart: Self.tip)
        #expect(totals.inputs > 200 && totals.edits > 50)
    }

    /// The fallback of §15.3 never shows in a game; the model and the placement agree on it all the same.
    @Test func review_placementFallbackAgreesWithTheModel() {
        var random = SeededRandom(seed: 3)
        for _ in 0..<40 {
            let radius = [16, 28, 40, 90, 150][random.nextInt(below: 5)]
            let obstacles = (0..<random.nextInt(below: 6)).map { _ in
                (x: random.nextInt(below: 341) - 170, y: random.nextInt(below: 341) - 170, r: random.nextInt(below: 140))
            }
            let expected = ReviewRadar.candidates(radius: radius, obstacles: obstacles).map { RadarPlacement.Point(x: $0.0, y: $0.1) }
            let discs = obstacles.map { RadarPlacement.Disc(x: $0.x, y: $0.y, radius: $0.r) }
            #expect(RadarPlacement.candidates(radius: radius, obstacles: discs) == expected)
            var one = random, two = random
            let centre = ReviewRadar.place(radius: radius, obstacles: obstacles, random: &one)
            #expect(RadarPlacement.place(radius: radius, obstacles: discs, random: &two) == RadarPlacement.Point(x: centre.0, y: centre.1))
            #expect(one == two)
        }
    }
}

@Suite struct BeerTapReviewTests {
    @Test(arguments: [(25, 1, 1), (50, 3, 2), (100, 5, 3), (50, 8, 4)])
    func review_beerTapAgreesWithTheModelOnRandomJournals(glass: Int, players: Int, rounds: Int) throws {
        let options: GameOptions = ["glassSize": .int(glass), "rounds": .int(rounds)]
        // High beds often, so that free glasses and several glasses per dart happen.
        let high: [Hit] = [.treble(20), .treble(19), .treble(18), .innerBull, .outerBull, .double(20), .miss]
        let totals = try ReviewFuzz.run(.beerTap, options, players: players, seed: 0, fuzzSeed: UInt64(glass * 10 + players),
                                        steps: 400, make: { _ in ReviewBeerTap(players: players, glass: glass, rounds: rounds) },
                                        dart: { random, _ in
            (random.nextInt(below: 2) == 0 ? high[random.nextInt(below: high.count)] : reviewAnyHit(&random), nil)
        })
        #expect(totals.inputs > 200 && totals.edits > 50)
    }
}

@Suite struct FootballReviewTests {
    @Test(arguments: [(2, 4, 3, 10), (3, 3, 2, 6), (5, 3, 1, 4), (7, 3, 9, 3), (8, 8, 2, 2), (4, 5, 3, 99)])
    func review_footballAgreesWithTheModelOnRandomJournals(players: Int, field: Int, goals: Int, rounds: Int) throws {
        let options: GameOptions = ["fieldLength": .int(field), "goalsToWin": .int(goals),
                                    "maxRounds": rounds == 99 ? .null : .int(rounds)]
        let totals = try ReviewFuzz.run(.football, options, players: players, seed: 0, fuzzSeed: UInt64(players * 100 + field),
                                        steps: 500, make: { _ in
            ReviewFootball(players: players, fieldLength: field, goalsToWin: goals, maxRounds: rounds == 99 ? nil : rounds)
        }, dart: { random, _ in (reviewAnyHit(&random), nil) })
        #expect(totals.inputs > 250 && totals.edits > 60)
    }
}

@Suite struct GolfReviewTests {
    @Test(arguments: [(1, 9, false), (2, 18, true), (3, 1, false), (4, 3, true), (8, 2, false)])
    func review_golfAgreesWithTheModelOnRandomJournals(players: Int, holes: Int, best: Bool) throws {
        let options: GameOptions = ["holes": .int(holes), "countedDart": best ? "best" : "last"]
        let totals = try ReviewFuzz.run(.golf, options, players: players, seed: 0, fuzzSeed: UInt64(players * 31 + holes),
                                        steps: 500, make: { _ in
            ReviewGolfTracked(golf: ReviewGolf(players: players, holes: holes, best: best))
        }, dart: { random, match in
            // The number of the hole most of the time: doubles close the turn, singles and trebles score.
            let hole = match.snapshot.round
            switch random.nextInt(below: 4) {
            case 0: return (.double(hole), nil)
            case 1: return (.treble(hole), nil)
            case 2: return (.single(hole), nil)
            default: return (reviewAnyHit(&random), nil)
            }
        })
        #expect(totals.inputs > 250 && totals.edits > 60)
    }
}
