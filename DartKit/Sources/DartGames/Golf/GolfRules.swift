import DartCore

/// GAMES.md §16. Traditional darts golf: hole r is played on the number r; the double is worth 1 stroke, the
/// treble 2, the single 3 and anything else 5. Fewest strokes wins. Stopping before the third dart is a move of
/// the game. The descriptor is the one written by lot F0, word for word.
public struct GolfRules: TurnBasedRules {
    public static let descriptor = GameDescriptor(
        id: .golf,
        name: LocalizedText(verbatim: "Golf"),
        shortName: LocalizedText(verbatim: "Golf"),
        summary: LocalizedText(fr: "Le moins de coups", en: "Fewest strokes"),
        pitch: LocalizedText(fr: "Un numéro par trou : 1 coup pour le double, 2 pour le triple, 3 pour le simple, 5 si vous le manquez. Le moins de coups gagne.",
                             en: "One number per hole: 1 stroke for the double, 2 for the treble, 3 for the single, 5 if you miss it. Fewest strokes wins."),
        players: 1...8,
        options: [
            OptionDescriptor(key: "holes", label: LocalizedText(fr: "Trous", en: "Holes"),
                             kind: .choice([OptionChoice(9, label: LocalizedText(verbatim: "9")), OptionChoice(18, label: LocalizedText(verbatim: "18"))]),
                             defaultValue: 9, allowsCustomValue: true),
            OptionDescriptor(key: "countedDart", label: LocalizedText(fr: "Fléchette comptée", en: "Counted dart"),
                             kind: .choice([OptionChoice("last", label: LocalizedText(fr: "La dernière fléchette", en: "Last dart")), OptionChoice("best", label: LocalizedText(fr: "La meilleure fléchette", en: "Best dart"))]),
                             defaultValue: "last"),
        ],
        playStyle: .board,
        origin: .dartsee,
        priority: 1, confirmsShortTurn: false)

    /// Par of every hole.
    static let par = 3
    /// Value of a dart that misses the number of the hole, and score of a hole played without a dart.
    static let missValue = 5
    /// Holes the engine accepts; the setup screen offers 9 and 18.
    static let allowedHoles = 1...18

    let holes: Int
    /// `countedDart == best`: the best dart of the turn counts; otherwise the last one (the traditional rule).
    let bestDartCounts: Bool
    /// Total strokes of each player.
    var strokes: [Int]
    /// Score of every hole played, by player.
    var holeScores: [[Int]]

    public init(configuration: GameConfiguration, random: inout SeededRandom) throws {
        // The kernel has validated the configuration already; a rule built on its own is as strict.
        let descriptor = Self.descriptor
        let count = configuration.players.count
        if let issue = descriptor.validate(options: configuration.options, playerCount: count).first { throw issue }
        let options = descriptor.normalized(configuration.options)
        // `holes` accepts a custom value: the engine validates it (ARCHITECTURE.md §5.3).
        guard let holes = options.int("holes"), Self.allowedHoles.contains(holes) else {
            throw GameConfigurationError.invalidOptionValue(key: "holes")
        }
        guard let counted = options.string("countedDart") else {
            throw GameConfigurationError.invalidOptionValue(key: "countedDart")
        }
        self.holes = holes
        bestDartCounts = counted == "best"
        strokes = Array(repeating: 0, count: count)
        holeScores = Array(repeating: [], count: count)
    }

    /// Value of a dart during hole `hole`: 1 for its double, 2 for its treble, 3 for its single, 5 for anything else.
    static func value(of hit: Hit, hole: Int) -> Int {
        guard hit.number == hole else { return missValue }
        switch hit.bed {
        case .double: return 1
        case .treble: return 2
        case .single: return 3
        case .miss, .outerBull, .innerBull: return missValue
        }
    }

    /// Provisional score of the hole for the darts thrown so far: the value of the last dart (`last`) or the
    /// smallest value of the turn (`best`); 5 as long as no dart is thrown.
    func provisional(_ darts: [Hit], hole: Int) -> Int {
        let values = darts.map { Self.value(of: $0, hole: hole) }
        return (bestDartCounts ? values.min() : values.last) ?? Self.missValue
    }

    func toPar(_ player: PlayerIndex) -> Int { strokes[player] - Self.par * holeScores[player].count }

    public var roundLimit: Int? { holes }
    public func isEliminated(_ player: PlayerIndex) -> Bool { false }

    // No per-turn state: the hole is the round (a player's k-th turn is always in round k) and the score of the
    // hole is a function of the darts of the turn.
    public mutating func turnStarted(_ context: TurnContext, random: inout SeededRandom, events: inout [GameEvent]) {}

    public mutating func dartThrown(_ hit: Hit, _ context: TurnContext, random: inout SeededRandom,
                                    events: inout [GameEvent]) -> DartVerdict {
        let value = Self.value(of: hit, hole: context.round)
        // Never `noEffect`: every dart sets or confirms the score of the hole.
        events.append(.shotPlayed(player: context.currentPlayer, strokes: value))
        // The double of the hole closes the turn: nothing better exists, and in `last` one more dart could only cost.
        return value == 1 ? .turnClosed : .turnContinues
    }

    public mutating func turnClosed(_ context: TurnContext, events: inout [GameEvent]) {
        let p = context.currentPlayer
        // Nothing is added to `strokes` before the close; a turn confirmed without a dart is worth 5.
        let score = provisional(context.darts, hole: context.round)
        strokes[p] += score
        holeScores[p].append(score)
        events.append(.holeCompleted(player: p, hole: context.round, strokes: score, total: strokes[p]))
        if score == 1 { events.append(.holeInOne(player: p, hole: context.round)) }
    }

    /// By `toPar`, ascending: fair between a player who has played the hole in progress and one who has not.
    public func ranks() -> [Int] { Ranking.ranks(keys: strokes.indices.map { [toPar($0)] }) }

    public func presentation(_ context: TurnContext) -> RulesPresentation {
        let hole = context.round
        // After the round limit the volley is empty and no turn is in progress (ARCHITECTURE.md §4.7).
        let noTurn = context.phase == .finished && context.darts.isEmpty
        let provisional = provisional(context.darts, hole: hole)
        return RulesPresentation(
            title: Self.descriptor.name,
            variant: bestDartCounts ? LocalizedText(fr: "Meilleure fléchette", en: "Best dart") : nil,
            objective: LocalizedText(fr: "Trou \(hole) / \(holes) · par \(Self.par)", en: "Hole \(hole) / \(holes) · par \(Self.par)"),
            rows: strokes.indices.map { row($0) },
            dartCaptions: context.darts.map { Self.caption(Self.value(of: $0, hole: hole)) },
            turnSummary: noTurn ? nil : LocalizedText(fr: "Ce trou : \(provisional)", en: "This hole: \(provisional)"),
            highlights: [
                BoardHighlight(zone: .double(hole), role: .target, label: "1"),
                BoardHighlight(zone: .treble(hole), role: .target, label: "2"),
                BoardHighlight(zone: .single(hole), role: .secondary, label: "3"),
            ],
            outcome: outcome(),
            facts: ["provisional": .int(provisional)])
    }

    // MARK: Private

    /// "−2", "Par", "+3": the gap to par, with a true minus sign.
    private static func parText(_ toPar: Int) -> String {
        if toPar == 0 { return "Par" }
        return toPar < 0 ? "−\(-toPar)" : "+\(toPar)"
    }

    private static func strokesText(_ count: Int) -> LocalizedText {
        .counted(count, fr: (one: "coup", other: "coups"), en: (one: "stroke", other: "strokes"))
    }

    private static func caption(_ value: Int) -> DartCaption {
        DartCaption(strokesText(value), tone: value < par ? .positive : value == par ? .neutral : .negative)
    }

    private func row(_ player: PlayerIndex) -> PlayerRow {
        let total = strokes[player], gap = toPar(player), scores = holeScores[player]
        var lines = [LocalizedText(fr: "Écart au par : \(Self.parText(gap))", en: "To par: \(Self.parText(gap))")]
        let aces = scores.filter { $0 == 1 }.count
        if aces > 0 {
            lines.append(.counted(aces, fr: (one: "trou en un", other: "trous en un"), en: (one: "hole in one", other: "holes in one")))
        }
        return PlayerRow(
            player: player,
            primary: ScoreValue(total, unit: LocalizedText(fr: total <= 1 ? "coup" : "coups", en: total == 1 ? "stroke" : "strokes")),
            detail: scores.isEmpty ? nil : LocalizedText(verbatim: scores.map(String.init).joined(separator: " · ")),
            badges: [Badge(LocalizedText(verbatim: Self.parText(gap)), tone: gap < 0 ? .positive : gap == 0 ? .neutral : .negative)],
            resultLines: lines,
            facts: ["strokes": .int(total), "holesPlayed": .int(scores.count), "holeScores": .ints(scores), "toPar": .int(gap)])
    }

    /// Results sentence about the winner; the kernel only lets it out once the game is finished.
    private func outcome() -> LocalizedText {
        let ranking = ranks()
        let winners = ranking.indices.filter { ranking[$0] == 1 }
        guard let winner = winners.first else { return LocalizedText(verbatim: "") }
        let total = Self.strokesText(strokes[winner]), gap = Self.parText(toPar(winner))
        if winners.count > 1 {
            return LocalizedText(fr: "Égalité à \(total.fr) (\(gap)).", en: "A tie at \(total.en) (\(gap)).")
        }
        let played = LocalizedText.counted(holeScores[winner].count, fr: (one: "trou", other: "trous"), en: (one: "hole", other: "holes"))
        return LocalizedText(fr: "\(total.fr) sur \(played.fr) (\(gap)).", en: "\(total.en) over \(played.en) (\(gap)).")
    }
}
