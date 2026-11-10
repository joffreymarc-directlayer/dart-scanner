import DartCore

/// GAMES.md §9 La Moitié. One set target per round: every dart on the target adds its points, and a turn that
/// closes without a single dart on the target halves the player's score, rounded up. Highest score wins after the
/// last target. The descriptor is the final one written by lot F0 (ARCHITECTURE.md §5.3).
public struct HalveItRules: TurnBasedRules {
    public static let descriptor = GameDescriptor(
        id: .halveIt,
        name: LocalizedText(fr: "La Moitié", en: "Halve-It"),
        shortName: LocalizedText(fr: "La Moitié", en: "Halve-It"),
        summary: LocalizedText(fr: "Raté : score divisé par 2", en: "Miss it: score halved"),
        pitch: LocalizedText(fr: "Une cible imposée par manche : ratez-la avec vos trois fléchettes et votre score est divisé par deux.",
                             en: "One set target per round: miss it with all three darts and your score is halved."),
        players: 1...8,
        options: [
            OptionDescriptor(key: "targets", label: LocalizedText(fr: "Cibles", en: "Targets"),
                             kind: .choice([OptionChoice(.strings(["20", "16", "D7", "14", "T10", "BULL"]), label: LocalizedText(fr: "Courte", en: "Short")), OptionChoice(.strings(["15", "16", "anyDouble", "17", "18", "anyTreble", "19", "20", "BULL"]), label: LocalizedText(fr: "Longue", en: "Long"))]),
                             defaultValue: .strings(["20", "16", "D7", "14", "T10", "BULL"]), allowsCustomValue: true),
            OptionDescriptor(key: "startingScore", label: LocalizedText(fr: "Score de départ", en: "Starting score"),
                             kind: .choice([OptionChoice(0, label: LocalizedText(verbatim: "0")), OptionChoice(40, label: LocalizedText(verbatim: "40"))]),
                             defaultValue: 0),
        ],
        playStyle: .board,
        origin: .classic,
        priority: 2)

    /// One target per round: the round limit is `targets.count` (1...12).
    let targets: [HalveItTarget]
    var points: [Int]
    /// Number of times each player was halved, for the results screen.
    var halvings: [Int]
    // Per-turn scratch state, reset by `turnStarted`.
    /// A dart of the current turn hit the target of the round: the turn is "réussi".
    var hitThisTurn = false
    /// Points earned so far in the current turn.
    var turnGain = 0
    /// The current turn closed with a division.
    var halvedThisTurn = false

    public init(configuration: GameConfiguration, random: inout SeededRandom) throws {
        // `targets` accepts a custom list (ARCHITECTURE.md §5.3): the schema lets anything through and the rule
        // keeps 1 to 12 targets it can read (GAMES.md §9.2).
        let option = configuration.options["targets"] ?? Self.descriptor.option("targets")?.defaultValue
        guard case .strings(let list)? = option, (1...12).contains(list.count) else {
            throw GameConfigurationError.invalidOptionValue(key: "targets")
        }
        var parsed: [HalveItTarget] = []
        for notation in list {
            guard let target = HalveItTarget(notation: notation) else {
                throw GameConfigurationError.invalidOptionValue(key: "targets")
            }
            parsed.append(target)
        }
        targets = parsed
        let count = configuration.players.count
        points = Array(repeating: configuration.options.int("startingScore") ?? 0, count: count)
        halvings = Array(repeating: 0, count: count)
    }

    public var roundLimit: Int? { targets.count }
    public func isEliminated(_ player: PlayerIndex) -> Bool { false }

    /// The target of round `round` is `targets[round − 1]` (GAMES.md §9.3). The kernel never goes past the round
    /// limit; the index is clamped all the same, so that no round can trap.
    func target(ofRound round: Int) -> HalveItTarget {
        targets[min(max(round, 1), targets.count) - 1]
    }

    public mutating func turnStarted(_ context: TurnContext, random: inout SeededRandom, events: inout [GameEvent]) {
        hitThisTurn = false
        turnGain = 0
        halvedThisTurn = false
    }

    public mutating func dartThrown(_ hit: Hit, _ context: TurnContext, random: inout SeededRandom,
                                    events: inout [GameEvent]) -> DartVerdict {
        let p = context.currentPlayer
        guard let gain = target(ofRound: context.round).gain(for: hit) else {
            events.append(.noEffect(player: p))
            return .turnContinues
        }
        points[p] += gain
        turnGain += gain
        hitThisTurn = true
        events.append(.targetScored(player: p, points: gain))
        return .turnContinues
    }

    /// GAMES.md §9.5: when no dart of the turn hit the target (also with zero darts), the score is halved, rounded
    /// up: 80 → 40, 5 → 3, 1 → 1, 0 → 0. `halved` carries the new total and comes before `turnCompleted`.
    public mutating func turnClosed(_ context: TurnContext, events: inout [GameEvent]) {
        guard !hitThisTurn else { return }
        let p = context.currentPlayer
        points[p] = (points[p] + 1) / 2
        halvings[p] += 1
        halvedThisTurn = true
        events.append(.halved(player: p, points: points[p]))
    }

    /// (1) `points` descending; (2) tie (GAMES.md §9.6).
    public func ranks() -> [Int] { Ranking.ranks(keys: points.map { [-$0] }) }

    public func presentation(_ context: TurnContext) -> RulesPresentation {
        let p = context.currentPlayer
        let finished = context.phase == .finished
        let target = target(ofRound: context.round)
        let rows = points.indices.map { i -> PlayerRow in
            // "Cible touchée" is about the turn in progress: no turn is in progress once the game is over.
            let hit = i == p && hitThisTurn && !finished
            return PlayerRow(
                player: i, primary: ScoreValue(points[i]),
                badges: hit ? [Badge(LocalizedText(fr: "Cible touchée", en: "Target hit"), tone: .positive)] : [],
                resultLines: halvings[i] > 0
                    ? [LocalizedText.counted(halvings[i], fr: ("division", "divisions"), en: ("halving", "halvings"))] : [],
                facts: ["points": .int(points[i]), "hitThisTurn": .bool(hit)])
        }
        let captions: [DartCaption?] = context.darts.map { hit in
            guard let gain = target.gain(for: hit) else { return DartCaption(LocalizedText(fr: "Sans effet", en: "No effect")) }
            return DartCaption(LocalizedText(verbatim: "+\(gain)"), tone: .positive)
        }
        // After the round limit the volley is empty while the scratch state is still that of the last turn
        // (ARCHITECTURE.md §4.7): no summary of a turn that is not shown any more.
        var summary: LocalizedText?
        if !(finished && context.darts.isEmpty) {
            summary = halvedThisTurn
                ? LocalizedText(fr: "Divisé par deux : \(points[p])", en: "Halved: \(points[p])")
                : LocalizedText(fr: "Volée : +\(turnGain)", en: "Turn: +\(turnGain)")
        }
        // Header: the target of the round, and the targets still to come (GAMES.md §9.7).
        let upcoming = targets.dropFirst(min(max(context.round, 1), targets.count)).map(\.title)
        let next = upcoming.isEmpty ? nil : LocalizedText(fr: "Ensuite : " + upcoming.map(\.fr).joined(separator: " · "),
                                                          en: "Next: " + upcoming.map(\.en).joined(separator: " · "))
        return RulesPresentation(
            title: Self.descriptor.name,
            objective: LocalizedText(fr: "Cible : \(target.title.fr)", en: "Target: \(target.title.en)"),
            rows: rows,
            dartCaptions: captions,
            turnSummary: summary,
            turnHint: next,
            highlights: target.zones.map { BoardHighlight(zone: $0, role: .target) },
            outcome: finished ? outcome() : nil,
            facts: ["target": .text(target.notation)])
    }

    /// Sentence of the results screen about the winner, or the winners on a tie.
    private func outcome() -> LocalizedText {
        let best = points.max() ?? 0
        let score = LocalizedText.counted(best, fr: ("point", "points"), en: ("point", "points"))
        if points.filter({ $0 == best }).count > 1 {
            return LocalizedText(fr: "Égalité à \(score.fr).", en: "Tied at \(score.en).")
        }
        return LocalizedText(fr: "Vainqueur avec \(score.fr).", en: "Winner with \(score.en).")
    }
}
