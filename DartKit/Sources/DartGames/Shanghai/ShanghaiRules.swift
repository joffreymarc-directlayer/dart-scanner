import DartCore

/// GAMES.md §7. One number per round: the number of the round scores its value times the multiplier, and a single,
/// a double and a treble of it in the same turn win at once. In the `lite` variant the two neighbouring sectors
/// are worth the single of the target.
public struct ShanghaiRules: TurnBasedRules {
    public static let descriptor = GameDescriptor(
        id: .shanghai,
        name: LocalizedText(verbatim: "Shanghai"),
        shortName: LocalizedText(verbatim: "Shanghai"),
        summary: LocalizedText(fr: "Un numéro par manche", en: "One number per round"),
        pitch: LocalizedText(fr: "Une manche par numéro : marquez un maximum sur le numéro du moment, ou gagnez d'un coup avec simple + double + triple.",
                             en: "One number per round: score big on it, or win at once with single + double + treble."),
        players: 1...8,
        options: [
            OptionDescriptor(key: "rounds", label: LocalizedText(fr: "Manches", en: "Rounds"),
                             kind: .choice([OptionChoice(7, label: LocalizedText(verbatim: "7")), OptionChoice(20, label: LocalizedText(verbatim: "20"))]),
                             defaultValue: 7, allowsCustomValue: true),
            OptionDescriptor(key: "variant", label: LocalizedText(fr: "Variante", en: "Variant"),
                             kind: .choice([OptionChoice("traditional", label: LocalizedText(fr: "Traditionnel", en: "Traditional")), OptionChoice("lite", label: LocalizedText(verbatim: "Lite"))]),
                             defaultValue: "traditional"),
        ],
        playStyle: .board,
        origin: .dartsee,
        priority: 0)

    // MARK: Options

    enum Variant: String, Sendable {
        /// Only the sector of the round scores.
        case traditional
        /// The two neighbouring sectors score the single of the target, whatever the bed.
        case lite
    }

    /// Number of rounds, 1...20: it is the round limit, and round `r` plays the number `r`.
    let rounds: Int
    let variant: Variant

    // MARK: State (GAMES.md §7.3)

    var points: [Int]
    /// The author of a Shanghai, ranked first whatever the points; the game ends on that dart.
    var shanghaiBy: PlayerIndex?
    /// Points of the latest turn of each player (the running total for the current player); nil before their first turn.
    var lastTurn: [Int?]
    /// Best turn of each player: results screen only.
    var bestTurn: [Int]
    /// Per-turn scratch state: points gained by each dart of the current turn. After a game ended at the round
    /// limit it still holds the last turn while the kernel's volley is empty (ARCHITECTURE.md §4.7).
    var turnGains: [Int] = []

    public init(configuration: GameConfiguration, random: inout SeededRandom) throws {
        let descriptor = Self.descriptor
        let count = configuration.players.count
        if let issue = descriptor.validate(options: configuration.options, playerCount: count).first {
            throw issue
        }
        let options = descriptor.normalized(configuration.options)
        // `rounds` accepts a custom value: the schema lets anything through, the engine accepts 1 to 20.
        guard let rounds = options.int("rounds"), (1...20).contains(rounds) else {
            throw GameConfigurationError.invalidOptionValue(key: "rounds")
        }
        guard let variant = options.string("variant").flatMap(Variant.init(rawValue:)) else {
            throw GameConfigurationError.invalidOptionValue(key: "variant")
        }
        self.rounds = rounds
        self.variant = variant
        points = Array(repeating: 0, count: count)
        lastTurn = Array(repeating: nil, count: count)
        bestTurn = Array(repeating: 0, count: count)
    }

    // MARK: Queries

    /// There is no `maxRounds` option: the limit is `rounds`.
    public var roundLimit: Int? { rounds }

    public func isEliminated(_ player: PlayerIndex) -> Bool { false }

    /// The two sectors next to `number` on the ring (anticlockwise, clockwise); empty outside 1...20.
    static func neighbours(of number: Int) -> [Int] {
        guard (1...20).contains(number) else { return [] }
        let pair = BoardGeometry.standard.neighbours(of: number)
        return [pair.anticlockwise, pair.clockwise]
    }

    // MARK: Turn flow

    public mutating func turnStarted(_ context: TurnContext, random: inout SeededRandom, events: inout [GameEvent]) {
        turnGains = []
        if lastTurn.indices.contains(context.currentPlayer) {
            lastTurn[context.currentPlayer] = 0
        }
    }

    public mutating func dartThrown(_ hit: Hit, _ context: TurnContext, random: inout SeededRandom,
                                    events: inout [GameEvent]) -> DartVerdict {
        let player = context.currentPlayer
        // The number of the round is the round itself: round 1 plays the 1, round 2 the 2…
        let target = context.round
        var gain = 0
        if let number = hit.number, number == target {
            gain = target * hit.multiplier
            events.append(.targetScored(player: player, points: gain))
        } else if variant == .lite, let number = hit.number, Self.neighbours(of: target).contains(number) {
            // Whatever the bed, a neighbour is worth the single of the target.
            gain = target
            events.append(.neighbourHit(player: player, points: gain))
        } else {
            events.append(.noEffect(player: player))
        }
        points[player] += gain
        let turnTotal = (lastTurn[player] ?? 0) + gain
        lastTurn[player] = turnTotal
        bestTurn[player] = max(bestTurn[player], turnTotal)
        turnGains.append(gain)

        // Shanghai: a single, a double and a treble of the exact number in the current volley, in any order.
        // A neighbour never stands for one of them.
        let beds = Set(context.darts.filter { $0.number == target }.map(\.bed))
        if beds.isSuperset(of: [.single, .double, .treble]) {
            shanghaiBy = player
            events.append(.shanghai(player: player))
            return .gameFinished(.victory)
        }
        return .turnContinues
    }

    public mutating func turnClosed(_ context: TurnContext, events: inout [GameEvent]) {}

    // MARK: Ranking (GAMES.md §7.6)

    /// The author of a Shanghai first, then the points, descending.
    public func ranks() -> [Int] {
        Ranking.ranks(keys: points.indices.map { [shanghaiBy == $0 ? 0 : 1, -points[$0]] })
    }

    // MARK: Presentation (GAMES.md §7.7)

    public func presentation(_ context: TurnContext) -> RulesPresentation {
        let target = context.round
        let turnTotal = turnGains.reduce(0, +)
        return RulesPresentation(
            title: Self.descriptor.name,
            variant: variant == .lite ? LocalizedText(verbatim: "Lite") : LocalizedText(fr: "Traditionnel", en: "Traditional"),
            objective: LocalizedText(fr: "Numéro \(target)", en: "Number \(target)"),
            rows: points.indices.map { player in
                PlayerRow(player: player, primary: ScoreValue(points[player]),
                          detail: lastTurn[player].map { LocalizedText(fr: "Volée : \($0)", en: "Turn: \($0)") },
                          badges: shanghaiBy == player ? [Badge(LocalizedText(verbatim: "Shanghai"), tone: .accent)] : [],
                          resultLines: resultLines(for: player, round: target),
                          facts: ["points": .int(points[player])])
            },
            // Never more captions than darts: the volley is empty after a game ended at the round limit.
            dartCaptions: turnGains.prefix(context.darts.count).map { gain in
                gain > 0 ? DartCaption(LocalizedText(verbatim: "+\(gain)"), tone: .positive)
                         : DartCaption(LocalizedText(verbatim: "0"))
            },
            // No current turn left to sum up after a game ended at the round limit (ARCHITECTURE.md §5.6).
            turnSummary: context.phase == .finished && context.darts.isEmpty
                ? nil : LocalizedText(fr: "Volée : \(turnTotal)", en: "Turn: \(turnTotal)"),
            highlights: highlights(forRound: target),
            outcome: outcome(round: target))
    }

    /// The sector of the round as a target, bed by bed, with what each bed is worth: `+r` on the singles, `+2r`
    /// on the double and `+3r` on the treble (a highlight carries one label, so the sector takes three). In
    /// `lite`, the two neighbouring sectors are `secondary` and worth `+r`.
    func highlights(forRound round: Int) -> [BoardHighlight] {
        guard (1...20).contains(round) else { return [] }
        var result = [
            BoardHighlight(zone: .single(round), role: .target, label: "+\(round)"),
            BoardHighlight(zone: .double(round), role: .target, label: "+\(2 * round)"),
            BoardHighlight(zone: .treble(round), role: .target, label: "+\(3 * round)"),
        ]
        if variant == .lite {
            for neighbour in Self.neighbours(of: round) {
                result.append(BoardHighlight(zone: .sector(neighbour), role: .secondary, label: "+\(round)"))
            }
        }
        return result
    }

    private func resultLines(for player: PlayerIndex, round: Int) -> [LocalizedText] {
        var lines = [LocalizedText(fr: "Meilleure volée : \(bestTurn[player])", en: "Best turn: \(bestTurn[player])")]
        if shanghaiBy == player {
            lines.append(LocalizedText(fr: "Shanghai manche \(round)", en: "Shanghai in round \(round)"))
        }
        return lines
    }

    /// Sentence about the winner; the kernel only lets it out once the game is finished.
    private func outcome(round: Int) -> LocalizedText? {
        if shanghaiBy != nil {
            return LocalizedText(fr: "Shanghai en manche \(round) : simple, double et triple du \(round).",
                                 en: "Shanghai in round \(round): single, double and treble of \(round).")
        }
        let ranks = ranks()
        let winners = ranks.indices.filter { ranks[$0] == 1 }
        guard let best = winners.first else { return nil }
        let total = LocalizedText.counted(points[best], fr: (one: "point", other: "points"), en: (one: "point", other: "points"))
        let played = LocalizedText.counted(rounds, fr: (one: "manche", other: "manches"), en: (one: "round", other: "rounds"))
        if winners.count == 1 {
            return LocalizedText(fr: "Meilleur total après \(played.fr) : \(total.fr).",
                                 en: "Highest total after \(played.en): \(total.en).")
        }
        return LocalizedText(fr: "Égalité à \(total.fr) après \(played.fr).", en: "Tie at \(total.en) after \(played.en).")
    }
}
