import Foundation

/// A game as a deterministic reducer (GAMES.md §2.4): same configuration and same inputs give the same snapshots
/// and the same events, on every machine and every version.
/// Implementations MUST be value types (a copy is an independent game) and MUST NOT read a clock, the system random
/// generator or any global state.
public protocol GameEngine: Sendable {
    /// Validates the configuration and performs the initial draws. Throws `GameConfigurationError`.
    init(configuration: GameConfiguration) throws
    /// The configuration, with the options completed by their defaults.
    var configuration: GameConfiguration { get }
    /// Applies one input. A refused input changes nothing.
    /// `position` is the recorded impact of a dart in NOMINAL board millimetres, when known (GAMES.md §2.13).
    /// It is part of the input for a position-dependent game, and is ignored by every other game and for `endTurn`.
    mutating func apply(_ input: GameInput, position: BoardPoint?) -> InputOutcome
    /// Presentation of the current state.
    var snapshot: GameSnapshot { get }
}

extension GameEngine {
    /// An input without a recorded position.
    public mutating func apply(_ input: GameInput) -> InputOutcome {
        apply(input, position: nil)
    }
}

// MARK: - Turn-based kernel (GAMES.md §2.4 to §2.10 and §2.13, shared by every v1 game)

/// Number of darts of a full turn.
public let dartsPerTurn = 3

/// What a rule sees when something happens in a turn.
public struct TurnContext: Sendable {
    public let players: [Player]
    public let currentPlayer: PlayerIndex
    /// 1-based.
    public let round: Int
    /// Darts of the current turn in order; in `dartThrown`, the dart being applied is the last one.
    public let darts: [Hit]
    /// Recorded positions of those darts, aligned with `darts`: nominal board millimetres, nil when a dart has none.
    /// Read ONLY by a position-dependent game (GAMES.md §2.13), and then through `impact` or `impact(ofDart:)`.
    public let positions: [BoardPoint?]
    public let phase: GamePhase

    /// `positions` may be shorter than `darts`: the missing entries are nil.
    public init(players: [Player], currentPlayer: PlayerIndex, round: Int, darts: [Hit],
                positions: [BoardPoint?] = [], phase: GamePhase) {
        self.players = players
        self.currentPlayer = currentPlayer
        self.round = round
        self.darts = darts
        self.positions = darts.indices.map { $0 < positions.count ? positions[$0] : nil }
        self.phase = phase
    }

    /// Impact point of dart `index` of the turn, by the three rules of GAMES.md §2.13: none for MISS, else the
    /// recorded position, else the canonical position of the bed. Nil also when `index` is out of range.
    public func impact(ofDart index: Int) -> ImpactPoint? {
        guard darts.indices.contains(index) else { return nil }
        return ImpactPoint(hit: darts[index], position: positions[index])
    }

    /// Impact point of the last dart of the turn: in `dartThrown`, the dart being applied.
    public var impact: ImpactPoint? {
        impact(ofDart: darts.count - 1)
    }

    /// True during the first turn of the game (round 1, first player). In `turnStarted` it singles out the call
    /// made at creation: every later call has `round > 1` or `currentPlayer > 0`.
    public var isFirstTurnOfGame: Bool {
        round == 1 && currentPlayer == 0
    }
}

/// What a dart does to the flow of the turn.
public enum DartVerdict: Hashable, Sendable {
    /// Nothing special: the turn closes by itself after the third dart.
    case turnContinues
    /// The rule closes the turn now (bust, self-elimination, the double of the hole at Golf).
    case turnClosed
    /// The game ends on this dart.
    case gameFinished(FinishReason)
}

/// Game-specific part of a snapshot. The kernel adds phase, current player, round, darts and ranks.
public struct RulesPresentation: Hashable, Sendable {
    public var title: LocalizedText
    public var variant: LocalizedText?
    public var objective: LocalizedText?
    /// One row per player in playing order. `rank` is overwritten by the kernel with `ranks()`.
    public var rows: [PlayerRow]
    /// Captions of the darts of the current turn, aligned with `TurnContext.darts`; may be shorter.
    public var dartCaptions: [DartCaption?]
    public var turnSummary: LocalizedText?
    public var turnHint: LocalizedText?
    /// Highlights for the current player. The kernel clears them once the game is finished.
    public var highlights: [BoardHighlight]
    public var grid: ScoreGrid?
    /// Results sentence; only read once the game is finished.
    public var outcome: LocalizedText?
    /// Headline naming the winner when it is not a player (Football: a side, or a draw); only read once the
    /// game is finished. Nil when the winners are the players ranked first.
    public var winnerTitle: LocalizedText?
    public var facts: [String: FactValue]

    public init(title: LocalizedText, variant: LocalizedText? = nil, objective: LocalizedText? = nil,
                rows: [PlayerRow], dartCaptions: [DartCaption?] = [], turnSummary: LocalizedText? = nil,
                turnHint: LocalizedText? = nil, highlights: [BoardHighlight] = [], grid: ScoreGrid? = nil,
                outcome: LocalizedText? = nil, winnerTitle: LocalizedText? = nil,
                facts: [String: FactValue] = [:]) {
        self.title = title
        self.variant = variant
        self.objective = objective
        self.rows = rows
        self.dartCaptions = dartCaptions
        self.turnSummary = turnSummary
        self.turnHint = turnHint
        self.highlights = highlights
        self.grid = grid
        self.outcome = outcome
        self.winnerTitle = winnerTitle
        self.facts = facts
    }
}

/// The rules of ONE game (GAMES.md §3 to §16). The kernel `TurnBasedEngine` owns everything that is common:
/// phases, the three darts, `endTurn`, skipping eliminated players, rounds, the round limit, `dartRegistered`,
/// `turnCompleted`, `roundStarted`, `turnStarted` and `gameFinished`. A rule never emits those five events.
/// Implementations are value types holding the whole game-specific state.
public protocol TurnBasedRules: Sendable {
    static var descriptor: GameDescriptor { get }

    /// Initial state (GAMES.md §n.3). `configuration.options` is already validated against the descriptor and
    /// completed with defaults. Initial draws consume `random` in the order given by GAMES.md.
    /// Throws `GameConfigurationError.invalidOptionValue` for a custom value it cannot read.
    init(configuration: GameConfiguration, random: inout SeededRandom) throws

    /// Round limit of this game (`maxRounds`, `rounds`, `targets.count`); nil = none.
    var roundLimit: Int? { get }

    func isEliminated(_ player: PlayerIndex) -> Bool

    /// Start-of-turn effects (Killer expert redraw, Radar moving targets) and reset of per-turn scratch state
    /// (turn-start score for a bust). Called once at creation for the first turn of the game (its events are
    /// discarded; `context.isFirstTurnOfGame` is true for that call only), then at step 4 of every `endTurn`
    /// that starts a turn. A player's k-th turn is always in round k.
    /// Events appended here come just before `turnStarted`.
    mutating func turnStarted(_ context: TurnContext, random: inout SeededRandom, events: inout [GameEvent])

    /// Effect of one accepted dart of `context.currentPlayer` (GAMES.md §n.4). `dartRegistered` is already in `events`.
    /// Append the effects in the order they happen. When returning `.gameFinished`, append nothing after the
    /// winning effects: the kernel adds `gameFinished` and no `turnCompleted`.
    /// `random` is the generator of the game, for a rule that draws while a dart is applied (Radar replaces a
    /// destroyed target); most rules never touch it. A position-dependent rule reads `context.impact`, never `hit`,
    /// to decide what the dart touches.
    mutating func dartThrown(_ hit: Hit, _ context: TurnContext, random: inout SeededRandom,
                             events: inout [GameEvent]) -> DartVerdict

    /// Turn-closing effects, exactly once per turn (GAMES.md §2.4): `turnScored`, `oneEighty`, `highTurn`, `halved`…
    /// Called after the third dart, after `.turnClosed`, or on an early `endTurn` (possibly with zero darts).
    /// NOT called when the game finishes on a dart. The kernel appends `turnCompleted` afterwards.
    mutating func turnClosed(_ context: TurnContext, events: inout [GameEvent])

    /// Rank of every player, by player index (GAMES.md §2.7). Valid at any time. Use `Ranking.ranks(keys:)`.
    func ranks() -> [Int]

    /// Scoreboard, captions, highlights and facts (GAMES.md §n.7), for `context.currentPlayer`.
    func presentation(_ context: TurnContext) -> RulesPresentation
}

/// The common turn machine of GAMES.md §2.4, generic over the rules of a game.
public struct TurnBasedEngine<Rules: TurnBasedRules>: GameEngine {
    public let configuration: GameConfiguration
    public private(set) var rules: Rules
    public private(set) var phase: GamePhase
    public private(set) var currentPlayer: PlayerIndex
    public private(set) var round: Int
    /// Darts of the current turn.
    public private(set) var darts: [Hit]
    /// Recorded positions of the darts of the current turn, aligned with `darts`.
    public private(set) var positions: [BoardPoint?]
    public private(set) var finishReason: FinishReason?
    private var random: SeededRandom

    public init(configuration: GameConfiguration) throws {
        let descriptor = Rules.descriptor
        guard configuration.gameID == descriptor.id else {
            throw GameConfigurationError.unknownGame(configuration.gameID)
        }
        if let issue = descriptor.validate(options: configuration.options, playerCount: configuration.players.count).first {
            throw issue
        }
        var normalised = configuration
        normalised.options = descriptor.normalized(configuration.options)
        var random = SeededRandom(seed: configuration.seed)
        var rules = try Rules(configuration: normalised, random: &random)
        var discarded: [GameEvent] = []
        let first = TurnContext(players: normalised.players, currentPlayer: 0, round: 1, darts: [], phase: .throwing)
        rules.turnStarted(first, random: &random, events: &discarded)
        self.configuration = normalised
        self.rules = rules
        self.phase = .throwing
        self.currentPlayer = 0
        self.round = 1
        self.darts = []
        self.positions = []
        self.finishReason = nil
        self.random = random
    }

    private var context: TurnContext {
        TurnContext(players: configuration.players, currentPlayer: currentPlayer, round: round, darts: darts,
                    positions: positions, phase: phase)
    }

    public mutating func apply(_ input: GameInput, position: BoardPoint?) -> InputOutcome {
        switch (phase, input) {
        case (.finished, _):
            return .rejected(.gameFinished)
        case (.turnComplete, .dart):
            return .rejected(.turnComplete)
        case (.throwing, .dart(let hit)):
            return .accepted(applyDart(hit, position: position))
        case (.throwing, .endTurn), (.turnComplete, .endTurn):
            return .accepted(applyEndTurn())
        }
    }

    private mutating func applyDart(_ hit: Hit, position: BoardPoint?) -> [GameEvent] {
        darts.append(hit)
        positions.append(position)
        var events: [GameEvent] = [.dartRegistered(player: currentPlayer, hit: hit)]
        switch rules.dartThrown(hit, context, random: &random, events: &events) {
        case .gameFinished(let reason):
            phase = .finished
            finishReason = reason
            events.append(.gameFinished(reason: reason))
        case .turnClosed:
            closeTurn(&events)
        case .turnContinues:
            if darts.count >= dartsPerTurn { closeTurn(&events) }
        }
        return events
    }

    private mutating func closeTurn(_ events: inout [GameEvent]) {
        rules.turnClosed(context, events: &events)
        events.append(.turnCompleted(player: currentPlayer))
        phase = .turnComplete
    }

    private mutating func applyEndTurn() -> [GameEvent] {
        var events: [GameEvent] = []
        if phase == .throwing { closeTurn(&events) }
        let count = configuration.players.count
        var next = currentPlayer
        for step in 1...count {
            let candidate = (currentPlayer + step) % count
            if !rules.isEliminated(candidate) {
                next = candidate
                break
            }
        }
        if next <= currentPlayer {
            if let limit = rules.roundLimit, round >= limit {
                // The confirmed turn is over and no turn starts: the volley is emptied (GAMES.md §2.4, step 3).
                darts = []
                positions = []
                phase = .finished
                finishReason = .roundLimit
                events.append(.gameFinished(reason: .roundLimit))
                return events
            }
            round += 1
            events.append(.roundStarted(round: round))
        }
        currentPlayer = next
        darts = []
        positions = []
        phase = .throwing
        rules.turnStarted(context, random: &random, events: &events)
        events.append(.turnStarted(player: currentPlayer, round: round))
        return events
    }

    public var snapshot: GameSnapshot {
        let presentation = rules.presentation(context)
        let ranks = rules.ranks()
        var rows = presentation.rows
        for index in rows.indices where index < ranks.count {
            rows[index].rank = ranks[index]
        }
        let slots = darts.enumerated().map { index, hit in
            DartSlot(hit: hit, caption: index < presentation.dartCaptions.count ? presentation.dartCaptions[index] : nil)
        }
        return GameSnapshot(
            gameID: configuration.gameID,
            title: presentation.title,
            variant: presentation.variant,
            objective: presentation.objective,
            phase: phase,
            currentPlayer: currentPlayer,
            round: round,
            roundLimit: rules.roundLimit,
            turn: TurnSnapshot(darts: slots, capacity: dartsPerTurn, summary: presentation.turnSummary, hint: presentation.turnHint),
            players: rows,
            highlights: phase == .finished ? [] : presentation.highlights,
            grid: presentation.grid,
            finishReason: finishReason,
            ranks: ranks,
            outcome: phase == .finished ? presentation.outcome : nil,
            winnerTitle: phase == .finished ? presentation.winnerTitle : nil,
            facts: presentation.facts
        )
    }
}
