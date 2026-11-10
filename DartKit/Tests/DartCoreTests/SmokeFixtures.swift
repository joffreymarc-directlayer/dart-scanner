import Foundation
import DartCore
import DartTestSupport

// Fixture rules of lot F0 (ARCHITECTURE.md §12.1): DartCore is tested with rules defined in the tests, written
// against the contract of §4 only. They are NOT a delivery: the real games live in DartGames (lots G1 to G4).
// Shared by several test files of this target, hence the `Smoke` prefix (ARCHITECTURE.md §13.4).

// MARK: - X01 (GAMES.md §3), for the common vectors COM-1 to COM-7

/// X01 as GAMES.md §3 specifies it. Registered under the real id `x01`, so that a vector reads as in GAMES.md §2.12.
struct SmokeX01Rules: TurnBasedRules {
    static let descriptor = GameDescriptor(
        id: .x01,
        name: LocalizedText(verbatim: "X01"),
        shortName: LocalizedText(verbatim: "X01"),
        summary: LocalizedText(verbatim: "301 · 501 · 701"),
        pitch: LocalizedText(verbatim: "X01"),
        players: 1...8,
        options: [
            OptionDescriptor(key: "startScore", label: LocalizedText(verbatim: "startScore"),
                             kind: .choice([301, 501, 701].map { OptionChoice(.int($0), label: LocalizedText(verbatim: "\($0)")) }),
                             defaultValue: 301),
            OptionDescriptor(key: "inRule", label: LocalizedText(verbatim: "inRule"),
                             kind: .choice([OptionChoice("straight", label: LocalizedText(verbatim: "straight")),
                                            OptionChoice("double", label: LocalizedText(verbatim: "double"))]),
                             defaultValue: "straight"),
            OptionDescriptor(key: "outRule", label: LocalizedText(verbatim: "outRule"),
                             kind: .choice([OptionChoice("straight", label: LocalizedText(verbatim: "straight")),
                                            OptionChoice("double", label: LocalizedText(verbatim: "double"))]),
                             defaultValue: "straight"),
            OptionDescriptor(key: "maxRounds", label: LocalizedText(verbatim: "maxRounds"),
                             kind: .optionalStepper(1...99, nullLabel: LocalizedText(verbatim: "none")),
                             defaultValue: 20, isAdvanced: true),
        ],
        playStyle: .score, origin: .dartsee, priority: 0)

    let startScore: Int
    let doubleIn: Bool
    let doubleOut: Bool
    let maxRounds: Int?
    var remaining: [Int]
    var isOpen: [Bool]
    var dartsThrown: [Int]
    var busts: [Int]
    var lastTurn: [Int?]
    // Per-turn scratch state, reset by `turnStarted`.
    var turnStartRemaining = 0
    var turnStartOpen = true
    var turnTotal = 0
    var busted = false

    init(configuration: GameConfiguration, random: inout SeededRandom) throws {
        let options = configuration.options
        startScore = options.int("startScore") ?? 301
        doubleIn = options.string("inRule") == "double"
        doubleOut = options.string("outRule") == "double"
        maxRounds = options.int("maxRounds")
        let count = configuration.players.count
        remaining = Array(repeating: startScore, count: count)
        isOpen = Array(repeating: !doubleIn, count: count)
        dartsThrown = Array(repeating: 0, count: count)
        busts = Array(repeating: 0, count: count)
        lastTurn = Array(repeating: nil, count: count)
    }

    var roundLimit: Int? { maxRounds }
    func isEliminated(_ player: PlayerIndex) -> Bool { false }

    mutating func turnStarted(_ context: TurnContext, random: inout SeededRandom, events: inout [GameEvent]) {
        let p = context.currentPlayer
        turnStartRemaining = remaining[p]
        turnStartOpen = isOpen[p]
        turnTotal = 0
        busted = false
    }

    mutating func dartThrown(_ hit: Hit, _ context: TurnContext, random: inout SeededRandom,
                             events: inout [GameEvent]) -> DartVerdict {
        let p = context.currentPlayer
        dartsThrown[p] += 1
        if hit.isMiss {
            events.append(.noEffect(player: p))
            return .turnContinues
        }
        if !isOpen[p] {
            guard hit.isDouble else {
                events.append(.doubleInRequired(player: p))
                return .turnContinues
            }
            isOpen[p] = true
            events.append(.doubleInOpened(player: p))
        }
        let left = remaining[p] - hit.points
        if left < 0 { return bust(p, .belowZero, &events) }
        if left == 0 {
            if doubleOut && !hit.isDouble { return bust(p, .notADouble, &events) }
            remaining[p] = 0
            turnTotal += hit.points
            events.append(.checkout(player: p, points: turnTotal, darts: context.darts.count))
            return .gameFinished(.victory)
        }
        if left == 1 && doubleOut { return bust(p, .oneLeft, &events) }
        remaining[p] = left
        turnTotal += hit.points
        return .turnContinues
    }

    private mutating func bust(_ p: PlayerIndex, _ reason: BustReason, _ events: inout [GameEvent]) -> DartVerdict {
        remaining[p] = turnStartRemaining
        isOpen[p] = turnStartOpen
        busts[p] += 1
        busted = true
        events.append(.bust(player: p, reason: reason))
        return .turnClosed
    }

    mutating func turnClosed(_ context: TurnContext, events: inout [GameEvent]) {
        let p = context.currentPlayer
        guard !busted else {
            lastTurn[p] = nil
            return
        }
        lastTurn[p] = turnTotal
        events.append(.turnScored(player: p, points: turnTotal))
        if turnTotal == 180 { events.append(.oneEighty(player: p)) }
        else if turnTotal >= 100 { events.append(.highTurn(player: p, points: turnTotal)) }
    }

    func ranks() -> [Int] { Ranking.ranks(keys: remaining.map { [$0] }) }

    func presentation(_ context: TurnContext) -> RulesPresentation {
        let p = context.currentPlayer
        var highlights: [BoardHighlight] = []
        if !isOpen[p] {
            highlights = (1...20).map { BoardHighlight(zone: .double($0), role: .target) }
                + [BoardHighlight(zone: .innerBull, role: .target)]
        } else {
            for hit in Hit.all where !hit.isMiss && hit.points == remaining[p] && (!doubleOut || hit.isDouble) {
                if let zone = BoardZone(hit) { highlights.append(BoardHighlight(zone: zone, role: .target)) }
            }
        }
        return RulesPresentation(
            title: LocalizedText(verbatim: "\(startScore)"),
            rows: remaining.indices.map { i in
                PlayerRow(player: i, primary: ScoreValue(remaining[i]),
                          facts: ["remaining": .int(remaining[i]), "isOpen": .bool(isOpen[i]),
                                  "dartsThrown": .int(dartsThrown[i]), "busts": .int(busts[i])])
            },
            dartCaptions: context.darts.map { DartCaption(LocalizedText(verbatim: "\($0.points)")) },
            turnSummary: LocalizedText(verbatim: "\(turnTotal)"),
            highlights: highlights,
            outcome: LocalizedText(verbatim: "outcome"))
    }
}

// MARK: - Elimination probe (kernel: eliminated players, rounds, order of events, end of the game)

/// A tiny elimination game. `Sn` (n = 1...players) costs one life to player n, the thrower included; a player
/// without lives is eliminated; a self-elimination closes the turn; the last player alive wins; `DB` wins at once.
/// Every hook leaves a trace, so that a test can see when and how often the kernel calls it.
struct SmokeElimRules: TurnBasedRules {
    static let id = GameID("smokeElim")

    static let descriptor = GameDescriptor(
        id: id,
        name: LocalizedText(verbatim: "Elim"),
        shortName: LocalizedText(verbatim: "Elim"),
        summary: LocalizedText(verbatim: "Elim"),
        pitch: LocalizedText(verbatim: "Elim"),
        players: 2...4,
        options: [
            OptionDescriptor(key: "lives", label: LocalizedText(verbatim: "lives"), kind: .stepper(1...3), defaultValue: 1),
            OptionDescriptor(key: "maxRounds", label: LocalizedText(verbatim: "maxRounds"),
                             kind: .optionalStepper(1...99, nullLabel: LocalizedText(verbatim: "none")),
                             defaultValue: .null),
        ],
        playStyle: .board, origin: .classic, priority: 2)

    let maxRounds: Int?
    var lives: [Int]
    /// 1 for the first player eliminated, 2 for the second…; 0 while alive.
    var eliminationOrder: [Int]
    var eliminatedCount = 0
    var bullWinner: PlayerIndex?
    /// Number of `turnClosed` calls, per player.
    var closes: [Int]
    /// One row `[round, player, isFirstTurnOfGame]` per `turnStarted` call, the creation call included.
    var turnStarts: [[Int]] = []

    init(configuration: GameConfiguration, random: inout SeededRandom) throws {
        let count = configuration.players.count
        maxRounds = configuration.options.int("maxRounds")
        lives = Array(repeating: configuration.options.int("lives") ?? 1, count: count)
        eliminationOrder = Array(repeating: 0, count: count)
        closes = Array(repeating: 0, count: count)
    }

    var roundLimit: Int? { maxRounds }
    func isEliminated(_ player: PlayerIndex) -> Bool { eliminationOrder[player] > 0 }

    mutating func turnStarted(_ context: TurnContext, random: inout SeededRandom, events: inout [GameEvent]) {
        turnStarts.append([context.round, context.currentPlayer, context.isFirstTurnOfGame ? 1 : 0])
        // A start-of-turn effect: the kernel must place it just before its own `turnStarted` event,
        // and must discard the one of the creation call.
        events.append(.zoneChanged(player: context.currentPlayer, zone: [context.round]))
    }

    mutating func dartThrown(_ hit: Hit, _ context: TurnContext, random: inout SeededRandom,
                             events: inout [GameEvent]) -> DartVerdict {
        let p = context.currentPlayer
        if hit == .innerBull {
            bullWinner = p
            return .gameFinished(.victory)
        }
        guard hit.bed == .single, let number = hit.number, number <= lives.count, !isEliminated(number - 1) else {
            events.append(.noEffect(player: p))
            return .turnContinues
        }
        let victim = number - 1
        lives[victim] -= 1
        events.append(.lifeLost(player: victim, by: p, livesLeft: lives[victim]))
        guard lives[victim] == 0 else { return .turnContinues }
        eliminatedCount += 1
        eliminationOrder[victim] = eliminatedCount
        events.append(.playerEliminated(player: victim, by: p))
        if lives.count - eliminatedCount == 1 { return .gameFinished(.lastPlayerStanding) }
        return victim == p ? .turnClosed : .turnContinues
    }

    mutating func turnClosed(_ context: TurnContext, events: inout [GameEvent]) {
        closes[context.currentPlayer] += 1
        // A turn-closing effect carrying the number of darts of the turn: the kernel adds `turnCompleted` after it.
        events.append(.turnScored(player: context.currentPlayer, points: context.darts.count))
    }

    func ranks() -> [Int] {
        Ranking.ranks(keys: lives.indices.map { i in
            if bullWinner == i { return [-1] }
            return isEliminated(i) ? [1, -eliminationOrder[i]] : [0, -lives[i]]
        })
    }

    func presentation(_ context: TurnContext) -> RulesPresentation {
        RulesPresentation(
            title: LocalizedText(verbatim: "Elim"),
            rows: lives.indices.map { i in
                PlayerRow(player: i, primary: ScoreValue(lives[i]), isEliminated: isEliminated(i),
                          facts: ["lives": .int(lives[i]), "eliminated": .bool(isEliminated(i)), "closes": .int(closes[i])])
            },
            highlights: lives.indices.filter { $0 != context.currentPlayer && !isEliminated($0) }.map {
                BoardHighlight(zone: .sector($0 + 1), role: .target, owner: $0)
            },
            // Given at any time: the kernel only lets them out once the game is finished.
            outcome: LocalizedText(verbatim: "outcome"),
            winnerTitle: LocalizedText(verbatim: "winner title"),
            facts: ["turnStarts": .table(turnStarts)])
    }
}

// MARK: - Position-dependent probe (GAMES.md §2.13, ARCHITECTURE.md §4.7: the three moments of a draw)

/// One round target of radius 30 mm. A dart whose IMPACT POINT lies in the disc scores 10 points and destroys it;
/// a new one is drawn at once, in `dartThrown`. With `moving`, the target is redrawn at the start of every turn
/// but the first. Integer arithmetic in tenths of a millimetre, as a position-dependent game must do.
struct SmokeDiscRules: TurnBasedRules {
    static let id = GameID("smokeDisc")
    /// Radius of the target, tenths of a millimetre.
    static let radius = 300
    /// Bound of every draw: a coordinate is `draw - 1000` tenths.
    static let drawBound = 2001

    static let descriptor = GameDescriptor(
        id: id,
        name: LocalizedText(verbatim: "Disc"),
        shortName: LocalizedText(verbatim: "Disc"),
        summary: LocalizedText(verbatim: "Disc"),
        pitch: LocalizedText(verbatim: "Disc"),
        players: 1...2,
        options: [
            OptionDescriptor(key: "moving", label: LocalizedText(verbatim: "moving"), kind: .toggle, defaultValue: false),
            OptionDescriptor(key: "rounds", label: LocalizedText(verbatim: "rounds"), kind: .stepper(1...20), defaultValue: 3),
        ],
        playStyle: .board, origin: .dartsee, priority: 1, dependsOnPosition: true)

    let moving: Bool
    let rounds: Int
    var x = 0
    var y = 0
    var points: [Int]
    var turnPoints = 0
    /// Number of values taken from the generator of the game so far.
    var draws = 0

    init(configuration: GameConfiguration, random: inout SeededRandom) throws {
        moving = configuration.options.bool("moving") ?? false
        rounds = configuration.options.int("rounds") ?? 3
        points = Array(repeating: 0, count: configuration.players.count)
        place(&random)
    }

    private mutating func place(_ random: inout SeededRandom) {
        x = random.nextInt(below: Self.drawBound) - 1000
        y = random.nextInt(below: Self.drawBound) - 1000
        draws += 2
    }

    var roundLimit: Int? { rounds }
    func isEliminated(_ player: PlayerIndex) -> Bool { false }

    mutating func turnStarted(_ context: TurnContext, random: inout SeededRandom, events: inout [GameEvent]) {
        turnPoints = 0
        guard moving, !context.isFirstTurnOfGame else { return }
        place(&random)
        events.append(.blobsMoved)
    }

    mutating func dartThrown(_ hit: Hit, _ context: TurnContext, random: inout SeededRandom,
                             events: inout [GameEvent]) -> DartVerdict {
        let p = context.currentPlayer
        guard let impact = context.impact, Self.touches(impact, x: x, y: y) else {
            events.append(.noEffect(player: p))
            return .turnContinues
        }
        points[p] += 10
        turnPoints += 10
        events.append(.blobDestroyed(player: p, blob: 0, points: 10))
        place(&random)
        return .turnContinues
    }

    /// True when `impact` is inside or on the disc of centre (`x`, `y`).
    static func touches(_ impact: ImpactPoint, x: Int, y: Int) -> Bool {
        let dx = impact.x - x, dy = impact.y - y
        return dx * dx + dy * dy <= radius * radius
    }

    mutating func turnClosed(_ context: TurnContext, events: inout [GameEvent]) {
        events.append(.turnScored(player: context.currentPlayer, points: turnPoints))
    }

    func ranks() -> [Int] { Ranking.ranks(keys: points.map { [-$0] }) }

    func presentation(_ context: TurnContext) -> RulesPresentation {
        RulesPresentation(
            title: LocalizedText(verbatim: "Disc"),
            rows: points.indices.map { PlayerRow(player: $0, primary: ScoreValue(points[$0]), facts: ["points": .int(points[$0])]) },
            highlights: [BoardHighlight(zone: .disc(x: Double(x) / 10, y: Double(y) / 10, radius: Double(Self.radius) / 10),
                                        role: .target, label: "+10", strength: 1)],
            facts: ["disc": .ints([x, y]), "draws": .int(draws)])
    }
}

// MARK: - Games that cannot be created

/// A game whose rules are not delivered: creating it throws `.unknownGame`, as the skeletons of DartGames do.
struct SmokeSkeletonRules: TurnBasedRules {
    static let id = GameID("smokeSkeleton")
    static let descriptor = GameDescriptor(
        id: id, name: LocalizedText(verbatim: "Skeleton"), shortName: LocalizedText(verbatim: "Skeleton"),
        summary: LocalizedText(verbatim: "Skeleton"), pitch: LocalizedText(verbatim: "Skeleton"),
        players: 2...4, options: [], playStyle: .board, origin: .classic, priority: 2)

    init(configuration: GameConfiguration, random: inout SeededRandom) throws {
        throw GameConfigurationError.unknownGame(configuration.gameID)
    }

    var roundLimit: Int? { nil }
    func isEliminated(_ player: PlayerIndex) -> Bool { false }
    mutating func turnStarted(_ context: TurnContext, random: inout SeededRandom, events: inout [GameEvent]) {}
    mutating func dartThrown(_ hit: Hit, _ context: TurnContext, random: inout SeededRandom,
                             events: inout [GameEvent]) -> DartVerdict { .turnContinues }
    mutating func turnClosed(_ context: TurnContext, events: inout [GameEvent]) {}
    func ranks() -> [Int] { [] }
    func presentation(_ context: TurnContext) -> RulesPresentation {
        RulesPresentation(title: Self.descriptor.name, rows: [])
    }
}

/// A game whose creation fails for another reason than "not delivered": it is NOT a skeleton.
struct SmokeBrokenRules: TurnBasedRules {
    static let id = GameID("smokeBroken")
    static let descriptor = GameDescriptor(
        id: id, name: LocalizedText(verbatim: "Broken"), shortName: LocalizedText(verbatim: "Broken"),
        summary: LocalizedText(verbatim: "Broken"), pitch: LocalizedText(verbatim: "Broken"),
        players: 1...2, options: [], playStyle: .board, origin: .classic, priority: 2)

    init(configuration: GameConfiguration, random: inout SeededRandom) throws {
        throw GameConfigurationError.invalidOptionValue(key: "broken")
    }

    var roundLimit: Int? { nil }
    func isEliminated(_ player: PlayerIndex) -> Bool { false }
    mutating func turnStarted(_ context: TurnContext, random: inout SeededRandom, events: inout [GameEvent]) {}
    mutating func dartThrown(_ hit: Hit, _ context: TurnContext, random: inout SeededRandom,
                             events: inout [GameEvent]) -> DartVerdict { .turnContinues }
    mutating func turnClosed(_ context: TurnContext, events: inout [GameEvent]) {}
    func ranks() -> [Int] { [] }
    func presentation(_ context: TurnContext) -> RulesPresentation {
        RulesPresentation(title: Self.descriptor.name, rows: [])
    }
}

// MARK: - Registry of the fixtures

enum SmokeFixtures {
    /// The fixture games, in this order: X01, the elimination probe, the position-dependent probe,
    /// a skeleton, a game that cannot be created.
    static let registry = GameRegistry([
        GameDefinition(rules: SmokeX01Rules.self),
        GameDefinition(rules: SmokeElimRules.self),
        GameDefinition(rules: SmokeDiscRules.self),
        GameDefinition(rules: SmokeSkeletonRules.self),
        GameDefinition(rules: SmokeBrokenRules.self),
    ])

    /// Notations of the journal, as a vector of GAMES.md §2.11 writes them: ["T20", "S1", "|", "S5"].
    static func journal(_ match: GameMatch) -> [String] {
        match.entries.map { entry in
            switch entry {
            case .dart(let record): return record.hit.notation
            case .endTurn: return "|"
            }
        }
    }

    /// Zones highlighted with the role `target`, in the order of the snapshot.
    static func targets(_ match: GameMatch) -> [BoardZone] {
        match.snapshot.highlights.filter { $0.role == .target }.map(\.zone)
    }
}
