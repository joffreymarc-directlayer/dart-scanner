import Testing
import DartCore
import DartGames
import DartTestSupport

/// Review of lot G1: the turn machine of GAMES.md §2.4 written again from the text alone, without `DartCore`'s
/// kernel, so that the oracles of `X01ReviewTests`, `CricketReviewTests` and `HighScoreReviewTests` check the
/// rules AND the way they drive the turns (verdicts, bust, victory, round limit).
/// Shared by the review files of the lot (ARCHITECTURE.md §13.4, rule 6: prefix `Common` in `Common/`).
protocol CommonReviewRules {
    /// Round limit of the game; nil = none.
    var roundLimit: Int? { get }
    func isOut(_ player: Int) -> Bool
    /// Start of a turn (GAMES.md §2.4 step 4); also called once at creation for J1 in round 1, events discarded.
    mutating func turnBegins(player: Int, round: Int, random: inout SeededRandom, events: inout [GameEvent])
    /// Effect of one dart; `volley` already holds it.
    mutating func dart(_ hit: Hit, player: Int, round: Int, volley: [Hit], events: inout [GameEvent]) -> CommonReviewVerdict
    /// Turn-closing effects, once per closed turn.
    mutating func turnEnds(player: Int, volley: [Hit], events: inout [GameEvent])
}

enum CommonReviewVerdict {
    case goOn, close, finish(FinishReason)
}

/// GAMES.md §2.4: phases, three darts, `endTurn`, next player not eliminated, rounds and round limit.
struct CommonReviewMachine<Rules: CommonReviewRules> {
    var rules: Rules
    var random: SeededRandom
    let players: Int
    var phase = GamePhase.throwing
    var current = 0
    var round = 1
    var volley: [Hit] = []
    var finishReason: FinishReason?

    init(players: Int, seed: UInt64, make: (inout SeededRandom) -> Rules) {
        var random = SeededRandom(seed: seed)
        var rules = make(&random)
        var discarded: [GameEvent] = []
        rules.turnBegins(player: 0, round: 1, random: &random, events: &discarded)
        self.rules = rules
        self.random = random
        self.players = players
    }

    /// The events of an accepted input; nil when the input is refused (nothing changes then).
    mutating func apply(_ input: GameInput) -> [GameEvent]? {
        switch (phase, input) {
        case (.finished, _), (.turnComplete, .dart):
            return nil
        case (.throwing, .dart(let hit)):
            volley.append(hit)
            var events: [GameEvent] = [.dartRegistered(player: current, hit: hit)]
            switch rules.dart(hit, player: current, round: round, volley: volley, events: &events) {
            case .finish(let reason):
                phase = .finished
                finishReason = reason
                events.append(.gameFinished(reason: reason))
            case .close:
                close(&events)
            case .goOn:
                if volley.count == 3 { close(&events) }
            }
            return events
        case (_, .endTurn):
            var events: [GameEvent] = []
            if phase == .throwing { close(&events) }
            var next = current
            repeat { next = (next + 1) % players } while rules.isOut(next) && next != current
            if next <= current {
                if let limit = rules.roundLimit, round >= limit {
                    volley = []
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
            phase = .throwing
            rules.turnBegins(player: current, round: round, random: &random, events: &events)
            events.append(.turnStarted(player: current, round: round))
            return events
        }
    }

    private mutating func close(_ events: inout [GameEvent]) {
        rules.turnEnds(player: current, volley: volley, events: &events)
        events.append(.turnCompleted(player: current))
        phase = .turnComplete
    }

    /// Plays a whole journal; nil when an entry is refused (a journal only holds accepted inputs).
    static func replay(_ entries: [LogEntry], players: Int, seed: UInt64,
                       make: (inout SeededRandom) -> Rules) -> CommonReviewMachine? {
        var machine = CommonReviewMachine(players: players, seed: seed, make: make)
        for entry in entries where machine.apply(entry.input) == nil {
            return nil
        }
        return machine
    }

    /// Shared ranks (GAMES.md §2.7) of keys where smaller is better, computed without `Ranking`.
    static func ranks(_ keys: [[Int]]) -> [Int] {
        keys.map { key in
            1 + keys.filter { other in
                for (a, b) in zip(other, key) where a != b { return a < b }
                return other.count < key.count
            }.count
        }
    }
}

/// One operation of a random game with edits, as the review oracles drive a `GameMatch`.
enum CommonReviewOperation {
    case dart(Hit), endTurn, undo, replace(Int, Hit), remove(Int)

    /// A random operation: mostly darts while throwing and confirmations once the turn is closed, with refused
    /// inputs, undo and corrections in every phase. `aim` picks the hit of a dart.
    static func random(_ phase: GamePhase, _ random: inout SeededRandom, aim: (inout SeededRandom) -> Hit) -> CommonReviewOperation {
        let roll = random.nextInt(below: 100)
        switch phase {
        case .throwing:
            if roll < 80 { return .dart(aim(&random)) }
            if roll < 89 { return .endTurn }
        case .turnComplete:
            if roll < 82 { return .endTurn }
            if roll < 86 { return .dart(aim(&random)) }
        case .finished:
            if roll < 15 { return .dart(aim(&random)) }
            if roll < 25 { return .endTurn }
        }
        switch random.nextInt(below: 3) {
        case 0: return .undo
        case 1: return .replace(random.nextInt(below: 4), aim(&random))
        default: return .remove(random.nextInt(below: 4))
        }
    }

    /// Applies the operation; returns the outcome of a dart or a confirmation, nil for an edit.
    @discardableResult
    func apply(to match: inout GameMatch) -> InputOutcome? {
        switch self {
        case .dart(let hit): return match.throwDart(DartRecord(hit: hit))
        case .endTurn: return match.endTurn()
        case .undo: match.undo()
        case .replace(let index, let hit): match.replaceDart(at: index, with: hit)
        case .remove(let index): match.removeDart(at: index)
        }
        return nil
    }
}
