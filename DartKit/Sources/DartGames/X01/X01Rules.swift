import DartCore

/// GAMES.md §3: start from 301, 501 or 701 and reach exactly zero.
/// The descriptor is the final one written by lot F0 (ARCHITECTURE.md §5.3).
public struct X01Rules: TurnBasedRules {
    public static let descriptor = GameDescriptor(
        id: .x01,
        name: LocalizedText(verbatim: "X01"),
        shortName: LocalizedText(verbatim: "X01"),
        summary: LocalizedText(verbatim: "301 · 501 · 701"),
        pitch: LocalizedText(fr: "Partez de 301, 501 ou 701 et descendez exactement à zéro avant les autres.",
                             en: "Start from 301, 501 or 701 and be the first to hit exactly zero."),
        players: 1...8,
        options: [
            OptionDescriptor(key: "startScore", label: LocalizedText(fr: "Score de départ", en: "Start score"),
                             kind: .choice([OptionChoice(301, label: LocalizedText(verbatim: "301")), OptionChoice(501, label: LocalizedText(verbatim: "501")), OptionChoice(701, label: LocalizedText(verbatim: "701"))]),
                             defaultValue: 301),
            OptionDescriptor(key: "inRule", label: LocalizedText(fr: "Entrée", en: "In"),
                             kind: .choice([OptionChoice("straight", label: LocalizedText(fr: "Entrée libre", en: "Straight in")), OptionChoice("double", label: LocalizedText(fr: "Entrée en double", en: "Double in"))]),
                             defaultValue: "straight"),
            OptionDescriptor(key: "outRule", label: LocalizedText(fr: "Sortie", en: "Out"),
                             kind: .choice([OptionChoice("straight", label: LocalizedText(fr: "Sortie libre", en: "Straight out")), OptionChoice("double", label: LocalizedText(fr: "Sortie en double", en: "Double out"))]),
                             defaultValue: "straight"),
            OptionDescriptor(key: "maxRounds", label: LocalizedText(fr: "Manches maximum", en: "Round limit"),
                             kind: .optionalStepper(1...99, nullLabel: LocalizedText(fr: "Sans limite", en: "No limit")),
                             defaultValue: 20, isAdvanced: true),
        ],
        playStyle: .score,
        origin: .dartsee,
        priority: 0)

    /// How a player's last closed turn ended: the scoreboard line "Dernière volée : 45" or "BUST".
    enum TurnResult: Hashable, Sendable {
        case scored(Int)
        case bust
    }

    /// What one dart of the current turn did, kept for its caption.
    enum DartEffect: Hashable, Sendable {
        case miss
        /// Double in: the dart came before the opening double and is not counted.
        case notOpen
        /// The points subtracted.
        case scored(Int)
        case bust
        /// The winning dart, with its points.
        case checkout(Int)
    }

    let startScore: Int
    let doubleIn: Bool
    let doubleOut: Bool
    let maxRounds: Int?
    var remaining: [Int]
    var isOpen: [Bool]
    var dartsThrown: [Int]
    var busts: [Int]
    var lastTurn: [TurnResult?]
    // Per-turn scratch state, reset by `turnStarted`. After a game ended at the round limit it still describes
    // the last turn while the kernel's volley is empty (ARCHITECTURE.md §4.7).
    var turnStartRemaining = 0
    var turnStartOpen = true
    var turnTotal = 0
    var turnBusted = false
    var turnEffects: [DartEffect] = []

    public init(configuration: GameConfiguration, random: inout SeededRandom) throws {
        // The kernel hands over validated options completed with their defaults; a rule created directly gets the
        // same treatment, and a value it cannot read is refused rather than replaced (ARCHITECTURE.md §4.4).
        let options = Self.descriptor.normalized(configuration.options)
        guard let start = options.int("startScore"), [301, 501, 701].contains(start) else {
            throw GameConfigurationError.invalidOptionValue(key: "startScore")
        }
        startScore = start
        doubleIn = try Self.isDouble(options, key: "inRule")
        doubleOut = try Self.isDouble(options, key: "outRule")
        switch options["maxRounds"] {
        case .null?: maxRounds = nil
        case .int(let rounds)? where (1...99).contains(rounds): maxRounds = rounds
        default: throw GameConfigurationError.invalidOptionValue(key: "maxRounds")
        }
        // GAMES.md §2.3: a number of players outside the range is refused.
        let count = configuration.players.count
        guard Self.descriptor.players.contains(count) else {
            throw GameConfigurationError.playerCountOutOfRange(allowed: Self.descriptor.players, actual: count)
        }
        remaining = Array(repeating: start, count: count)
        isOpen = Array(repeating: !doubleIn, count: count)
        dartsThrown = Array(repeating: 0, count: count)
        busts = Array(repeating: 0, count: count)
        lastTurn = Array(repeating: nil, count: count)
    }

    private static func isDouble(_ options: GameOptions, key: String) throws -> Bool {
        switch options.string(key) {
        case "straight"?: return false
        case "double"?: return true
        default: throw GameConfigurationError.invalidOptionValue(key: key)
        }
    }

    public var roundLimit: Int? { maxRounds }
    public func isEliminated(_ player: PlayerIndex) -> Bool { false }

    public mutating func turnStarted(_ context: TurnContext, random: inout SeededRandom, events: inout [GameEvent]) {
        let p = context.currentPlayer
        turnStartRemaining = remaining[p]
        turnStartOpen = isOpen[p]
        turnTotal = 0
        turnBusted = false
        turnEffects = []
    }

    /// GAMES.md §3.4, the cases in the order of the table.
    public mutating func dartThrown(_ hit: Hit, _ context: TurnContext, random: inout SeededRandom,
                                    events: inout [GameEvent]) -> DartVerdict {
        let p = context.currentPlayer
        dartsThrown[p] += 1
        if hit.isMiss {
            events.append(.noEffect(player: p))
            turnEffects.append(.miss)
            return .turnContinues
        }
        if !isOpen[p] {
            guard hit.isDouble else {
                events.append(.doubleInRequired(player: p))
                turnEffects.append(.notOpen)
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
            turnEffects.append(.checkout(hit.points))
            // The winning turn is never closed: its total is recorded here.
            lastTurn[p] = .scored(turnTotal)
            events.append(.checkout(player: p, points: turnTotal, darts: context.darts.count))
            return .gameFinished(.victory)
        }
        if left == 1 && doubleOut { return bust(p, .oneLeft, &events) }
        remaining[p] = left
        turnTotal += hit.points
        turnEffects.append(.scored(hit.points))
        return .turnContinues
    }

    /// GAMES.md §3.5: no dart of the turn counts. The score and the opening go back to the start of the turn;
    /// the darts stay counted in `dartsThrown`.
    private mutating func bust(_ p: PlayerIndex, _ reason: BustReason, _ events: inout [GameEvent]) -> DartVerdict {
        remaining[p] = turnStartRemaining
        isOpen[p] = turnStartOpen
        busts[p] += 1
        turnBusted = true
        turnEffects.append(.bust)
        events.append(.bust(player: p, reason: reason))
        return .turnClosed
    }

    public mutating func turnClosed(_ context: TurnContext, events: inout [GameEvent]) {
        let p = context.currentPlayer
        guard !turnBusted else {
            // A busted turn emits neither `turnScored` nor `oneEighty` (GAMES.md §3.8).
            lastTurn[p] = .bust
            return
        }
        lastTurn[p] = .scored(turnTotal)
        events.append(.turnScored(player: p, points: turnTotal))
        if turnTotal == 180 {
            events.append(.oneEighty(player: p))
        } else if turnTotal >= 100 {
            events.append(.highTurn(player: p, points: turnTotal))
        }
    }

    /// GAMES.md §3.6: lowest `remaining` first, in every case.
    public func ranks() -> [Int] { Ranking.ranks(keys: remaining.map { [$0] }) }

    // MARK: Presentation (GAMES.md §3.7, ARCHITECTURE.md §5.6)

    public func presentation(_ context: TurnContext) -> RulesPresentation {
        let p = context.currentPlayer
        // The kernel's volley may be shorter than the scratch state (game ended at the round limit).
        let shown = min(context.darts.count, turnEffects.count)
        let turnIsOver = context.phase == .finished && context.darts.isEmpty
        var summary: LocalizedText?
        if !turnIsOver {
            summary = turnBusted ? Self.bustText : LocalizedText(fr: "Volée : \(turnTotal)", en: "Turn: \(turnTotal)")
        }
        return RulesPresentation(
            title: LocalizedText(verbatim: "\(startScore)"),
            variant: variant,
            rows: remaining.indices.map { row($0, finished: context.phase == .finished) },
            dartCaptions: turnEffects.prefix(shown).map(Self.caption),
            turnSummary: summary,
            turnHint: hint(context),
            highlights: highlights(for: p),
            outcome: context.phase == .finished ? outcome : nil)
    }

    private static let bustText = LocalizedText(verbatim: "BUST")

    /// "Double in · Double out"; nil for the plain game.
    private var variant: LocalizedText? {
        let parts = (doubleIn ? ["Double in"] : []) + (doubleOut ? ["Double out"] : [])
        return parts.isEmpty ? nil : LocalizedText(verbatim: parts.joined(separator: " · "))
    }

    private func row(_ i: PlayerIndex, finished: Bool) -> PlayerRow {
        var detail: LocalizedText?
        switch lastTurn[i] {
        case .scored(let points)?: detail = LocalizedText(fr: "Dernière volée : \(points)", en: "Last turn: \(points)")
        case .bust?: detail = Self.bustText
        case nil: detail = nil
        }
        return PlayerRow(
            player: i,
            primary: ScoreValue(remaining[i]),
            detail: detail,
            badges: isOpen[i] ? [] : [Badge(LocalizedText(fr: "À ouvrir", en: "To open"))],
            // Lines of the results screen: only read once the game is finished, like `outcome`.
            resultLines: finished ? resultLines(i) : [],
            facts: ["remaining": .int(remaining[i]), "isOpen": .bool(isOpen[i]),
                    "dartsThrown": .int(dartsThrown[i]), "busts": .int(busts[i])])
    }

    /// Average per turn, `3 × (startScore − remaining) / dartsThrown` (0 without a dart), then the darts and busts.
    private func resultLines(_ i: PlayerIndex) -> [LocalizedText] {
        let darts = dartsThrown[i]
        // In tenths, rounded to the nearest: integer arithmetic, the same text on every machine.
        let tenths = darts == 0 ? 0 : (60 * (startScore - remaining[i]) + darts) / (2 * darts)
        let average = LocalizedText(fr: "Moyenne par volée : \(tenths / 10),\(tenths % 10)",
                                    en: "Average per turn: \(tenths / 10).\(tenths % 10)")
        var thrown = LocalizedText.counted(darts, fr: (one: "fléchette", other: "fléchettes"), en: (one: "dart", other: "darts"))
        if busts[i] > 0 {
            let busted = LocalizedText.counted(busts[i], fr: (one: "bust", other: "busts"), en: (one: "bust", other: "busts"))
            thrown = LocalizedText(fr: "\(thrown.fr) · \(busted.fr)", en: "\(thrown.en) · \(busted.en)")
        }
        return [average, thrown]
    }

    private static func caption(_ effect: DartEffect) -> DartCaption? {
        switch effect {
        case .miss: return DartCaption(LocalizedText(verbatim: "0"))
        case .notOpen: return DartCaption(LocalizedText(fr: "Double requis", en: "Double needed"))
        case .scored(let points): return DartCaption(LocalizedText(verbatim: "\(points)"))
        case .bust: return DartCaption(bustText, tone: .negative)
        case .checkout(let points): return DartCaption(LocalizedText(verbatim: "\(points)"), tone: .positive)
        }
    }

    /// Advice for the next dart, while the player may still throw: the opening double, or a finish within the
    /// darts left in the turn (`X01Checkout`).
    private func hint(_ context: TurnContext) -> LocalizedText? {
        guard context.phase == .throwing else { return nil }
        let p = context.currentPlayer
        guard isOpen[p] else { return LocalizedText(fr: "Ouvrir sur un double", en: "Open on a double") }
        let dartsLeft = dartsPerTurn - context.darts.count
        guard let route = X01Checkout.route(remaining: remaining[p], darts: dartsLeft, doubleOut: doubleOut) else { return nil }
        let notation = route.map(\.notation).joined(separator: " ")
        return LocalizedText(fr: "Pour finir : \(notation)", en: "To finish: \(notation)")
    }

    /// GAMES.md §3.7: the 21 doubles while the player has to open; otherwise the beds that finish directly.
    private func highlights(for p: PlayerIndex) -> [BoardHighlight] {
        if !isOpen[p] {
            return (1...20).map { BoardHighlight(zone: .double($0), role: .target) }
                + [BoardHighlight(zone: .innerBull, role: .target)]
        }
        return Hit.all
            .filter { !$0.isMiss && $0.points == remaining[p] && (!doubleOut || $0.isDouble) }
            .compactMap { BoardZone($0) }
            .map { BoardHighlight(zone: $0, role: .target) }
    }

    /// Results sentence. A player at zero means a victory; otherwise the game ended at the round limit.
    private var outcome: LocalizedText {
        if let winner = remaining.firstIndex(of: 0) {
            let darts = dartsThrown[winner]
            return LocalizedText(fr: "Zéro atteint en \(darts) fléchettes.", en: "Reached zero in \(darts) darts.")
        }
        let best = remaining.min() ?? startScore
        if remaining.filter({ $0 == best }).count > 1 {
            return LocalizedText(fr: "Égalité à la limite de manches : \(best) restants.",
                                 en: "Tied at the round limit with \(best) left.")
        }
        return LocalizedText(fr: "Plus petit reste à la limite de manches : \(best).",
                             en: "Lowest score left at the round limit: \(best).")
    }
}
