import DartCore

/// GAMES.md §8. The simplest game: the reference implementation of `TurnBasedRules` (ARCHITECTURE.md §5.4),
/// completed by lot G1 with the results of the game: sentence, lines per player, and no stale turn summary.
public struct HighScoreRules: TurnBasedRules {
    public static let descriptor = GameDescriptor(
        id: .highScore,
        name: LocalizedText(fr: "Meilleur score", en: "High Score"),
        shortName: LocalizedText(fr: "Meilleur score", en: "High Score"),
        summary: LocalizedText(fr: "Le plus de points", en: "Most points"),
        pitch: LocalizedText(fr: "Un nombre de manches fixe, tout compte : le plus gros total gagne.",
                             en: "A fixed number of rounds, everything counts: highest total wins."),
        players: 1...8,
        options: [OptionDescriptor(key: "rounds", label: LocalizedText(fr: "Manches", en: "Rounds"),
                                   kind: .stepper(1...20), defaultValue: 8)],
        playStyle: .score, origin: .classic, priority: 2)

    let rounds: Int
    var points: [Int]
    var dartsThrown: [Int]
    var lastTurn: [Int?]
    var turnTotal = 0

    public init(configuration: GameConfiguration, random: inout SeededRandom) throws {
        rounds = configuration.options.int("rounds") ?? 8
        let count = configuration.players.count
        points = Array(repeating: 0, count: count)
        dartsThrown = Array(repeating: 0, count: count)
        lastTurn = Array(repeating: nil, count: count)
    }

    public var roundLimit: Int? { rounds }
    public func isEliminated(_ player: PlayerIndex) -> Bool { false }

    public mutating func turnStarted(_ context: TurnContext, random: inout SeededRandom, events: inout [GameEvent]) {
        turnTotal = 0
    }

    public mutating func dartThrown(_ hit: Hit, _ context: TurnContext, random: inout SeededRandom,
                                    events: inout [GameEvent]) -> DartVerdict {
        let p = context.currentPlayer
        dartsThrown[p] += 1
        if hit.isMiss { events.append(.noEffect(player: p)) }
        points[p] += hit.points
        turnTotal += hit.points
        return .turnContinues
    }

    public mutating func turnClosed(_ context: TurnContext, events: inout [GameEvent]) {
        let p = context.currentPlayer
        lastTurn[p] = turnTotal
        events.append(.turnScored(player: p, points: turnTotal))
        if turnTotal == 180 { events.append(.oneEighty(player: p)) }
        else if turnTotal >= 100 { events.append(.highTurn(player: p, points: turnTotal)) }
    }

    public func ranks() -> [Int] { Ranking.ranks(keys: points.map { [-$0] }) }

    // MARK: Presentation (GAMES.md §8.7, ARCHITECTURE.md §5.6)

    public func presentation(_ context: TurnContext) -> RulesPresentation {
        // After a game ended at the round limit the kernel's volley is empty while `turnTotal` is still that of
        // the last turn (ARCHITECTURE.md §4.7): there is no current turn left to sum up.
        let turnIsOver = context.phase == .finished && context.darts.isEmpty
        return RulesPresentation(
            title: Self.descriptor.name,
            rows: points.indices.map { i in
                PlayerRow(player: i, primary: ScoreValue(points[i]),
                          detail: lastTurn[i].map { LocalizedText(fr: "Dernière volée : \($0)", en: "Last turn: \($0)") },
                          // Lines of the results screen: only read once the game is finished, like `outcome`.
                          resultLines: context.phase == .finished ? resultLines(i) : [],
                          facts: ["points": .int(points[i]), "dartsThrown": .int(dartsThrown[i])])
            },
            dartCaptions: context.darts.map { DartCaption(LocalizedText(verbatim: "\($0.points)")) },
            turnSummary: turnIsOver ? nil : LocalizedText(fr: "Volée : \(turnTotal)", en: "Turn: \(turnTotal)"),
            outcome: context.phase == .finished ? outcome : nil)
    }

    /// Average per turn, `3 × points / dartsThrown` (0 without a dart), then the darts thrown.
    private func resultLines(_ i: PlayerIndex) -> [LocalizedText] {
        let darts = dartsThrown[i]
        // In tenths, rounded to the nearest: integer arithmetic, the same text on every machine.
        let tenths = darts == 0 ? 0 : (60 * points[i] + darts) / (2 * darts)
        return [
            LocalizedText(fr: "Moyenne par volée : \(tenths / 10),\(tenths % 10)",
                          en: "Average per turn: \(tenths / 10).\(tenths % 10)"),
            .counted(darts, fr: (one: "fléchette", other: "fléchettes"), en: (one: "dart", other: "darts")),
        ]
    }

    /// Results sentence: the game only ends at the round limit, and the highest total wins.
    private var outcome: LocalizedText {
        let best = points.max() ?? 0
        let total = LocalizedText.counted(best, fr: (one: "point", other: "points"), en: (one: "point", other: "points"))
        if points.filter({ $0 == best }).count > 1 {
            return LocalizedText(fr: "Égalité à \(total.fr).", en: "Tied on \(total.en).")
        }
        return LocalizedText(fr: "Plus gros total : \(total.fr).", en: "Highest total: \(total.en).")
    }
}
