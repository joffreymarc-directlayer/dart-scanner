import DartCore

/// GAMES.md §10 Alunissage. Every player starts `distance` away from the Moon; each point brings them closer and
/// the first to land wins. "Débutant": reaching or passing the distance is enough. "Pro" (`exactLanding`): the
/// player must land on exactly 0, and a dart that goes beyond is a bust that cancels the whole turn.
/// The descriptor is the final one written by lot F0 (ARCHITECTURE.md §5.3).
public struct MoonLandingRules: TurnBasedRules {
    public static let descriptor = GameDescriptor(
        id: .moonLanding,
        name: LocalizedText(fr: "Alunissage", en: "Moon Landing"),
        shortName: LocalizedText(fr: "Alunissage", en: "Moon Landing"),
        summary: LocalizedText(fr: "De 200 à zéro", en: "From 200 down to zero"),
        pitch: LocalizedText(fr: "Partez à 200 de la Lune : chaque point vous rapproche, le premier posé gagne.",
                             en: "Start 200 away from the Moon: every point brings you closer, first to land wins."),
        players: 1...8,
        options: [
            OptionDescriptor(key: "distance", label: LocalizedText(verbatim: "Distance"),
                             kind: .choice([OptionChoice(200, label: LocalizedText(verbatim: "200")), OptionChoice(300, label: LocalizedText(verbatim: "300")), OptionChoice(500, label: LocalizedText(verbatim: "500"))]),
                             defaultValue: 200, allowsCustomValue: true),
            OptionDescriptor(key: "exactLanding", label: LocalizedText(fr: "Alunissage exact (Pro)", en: "Exact landing (Pro)"),
                             kind: .toggle,
                             defaultValue: false),
            OptionDescriptor(key: "maxRounds", label: LocalizedText(fr: "Manches maximum", en: "Round limit"),
                             kind: .optionalStepper(1...99, nullLabel: LocalizedText(fr: "Sans limite", en: "No limit")),
                             defaultValue: 15, isAdvanced: true),
        ],
        playStyle: .score,
        origin: .dartsee,
        priority: 0)

    /// How a player's last closed turn ended, for the scoreboard line.
    enum LastTurn: Hashable, Sendable {
        case scored(Int)
        case bust
    }

    let distance: Int
    let exactLanding: Bool
    let maxRounds: Int?
    var remaining: [Int]
    var dartsThrown: [Int]
    var busts: [Int]
    var lastTurn: [LastTurn?]
    // Per-turn scratch state, reset by `turnStarted`.
    /// `remaining` of the current player when the turn began: a bust goes back to it.
    var turnStartRemaining = 0
    /// Points counted so far in the current turn.
    var turnTotal = 0
    /// Index, in the turn, of the dart that went bust.
    var bustDart: Int?
    /// Index, in the turn, of the dart that landed.
    var landingDart: Int?

    public init(configuration: GameConfiguration, random: inout SeededRandom) throws {
        let options = configuration.options
        // `distance` accepts a custom value (ARCHITECTURE.md §5.3): the schema lets anything through and the
        // rule keeps 100...999 (GAMES.md §10.2).
        guard case .int(let distance) = options["distance"] ?? 200, (100...999).contains(distance) else {
            throw GameConfigurationError.invalidOptionValue(key: "distance")
        }
        self.distance = distance
        exactLanding = options.bool("exactLanding") ?? false
        maxRounds = options.int("maxRounds")
        let count = configuration.players.count
        remaining = Array(repeating: distance, count: count)
        dartsThrown = Array(repeating: 0, count: count)
        busts = Array(repeating: 0, count: count)
        lastTurn = Array(repeating: nil, count: count)
    }

    public var roundLimit: Int? { maxRounds }
    public func isEliminated(_ player: PlayerIndex) -> Bool { false }

    public mutating func turnStarted(_ context: TurnContext, random: inout SeededRandom, events: inout [GameEvent]) {
        turnStartRemaining = remaining[context.currentPlayer]
        turnTotal = 0
        bustDart = nil
        landingDart = nil
    }

    public mutating func dartThrown(_ hit: Hit, _ context: TurnContext, random: inout SeededRandom,
                                    events: inout [GameEvent]) -> DartVerdict {
        let p = context.currentPlayer
        dartsThrown[p] += 1
        if hit.isMiss {
            events.append(.noEffect(player: p))
            return .turnContinues
        }
        let left = remaining[p] - hit.points
        if exactLanding && left < 0 {
            // Bust: the turn closes now and none of its darts counts (GAMES.md §10.5).
            remaining[p] = turnStartRemaining
            busts[p] += 1
            bustDart = context.darts.count - 1
            events.append(.bust(player: p, reason: .belowZero))
            return .turnClosed
        }
        remaining[p] = max(0, left)
        turnTotal += hit.points
        if remaining[p] == 0 {
            landingDart = context.darts.count - 1
            events.append(.landed(player: p))
            return .gameFinished(.victory)
        }
        return .turnContinues
    }

    public mutating func turnClosed(_ context: TurnContext, events: inout [GameEvent]) {
        let p = context.currentPlayer
        guard bustDart == nil else {
            lastTurn[p] = .bust
            return
        }
        lastTurn[p] = .scored(turnTotal)
        events.append(.turnScored(player: p, points: turnTotal))
        if turnTotal == 180 { events.append(.oneEighty(player: p)) }
        else if turnTotal >= 100 { events.append(.highTurn(player: p, points: turnTotal)) }
    }

    /// (1) `remaining` ascending; (2) tie (GAMES.md §10.6).
    public func ranks() -> [Int] { Ranking.ranks(keys: remaining.map { [$0] }) }

    public func presentation(_ context: TurnContext) -> RulesPresentation {
        let p = context.currentPlayer
        let finished = context.phase == .finished
        let rows = remaining.indices.map { i in
            PlayerRow(player: i, primary: ScoreValue(remaining[i]),
                      detail: lastTurn[i].map(Self.lastTurnText),
                      resultLines: resultLines(for: i),
                      facts: ["remaining": .int(remaining[i]), "dartsThrown": .int(dartsThrown[i]), "busts": .int(busts[i])])
        }
        let captions: [DartCaption?] = context.darts.enumerated().map { index, hit in
            if index == bustDart { return DartCaption(Self.bustText, tone: .negative) }
            if index == landingDart { return DartCaption(LocalizedText(fr: "Posé !", en: "Landed!"), tone: .positive) }
            return DartCaption(LocalizedText(verbatim: "\(hit.points)"))
        }
        // After a finish at the round limit the volley is empty while the scratch state is still that of the last
        // turn (ARCHITECTURE.md §4.7): no summary of a turn that is not shown any more.
        var summary: LocalizedText?
        if !(finished && context.darts.isEmpty) {
            summary = bustDart != nil ? Self.bustText : LocalizedText(fr: "Volée : \(turnTotal)", en: "Turn: \(turnTotal)")
        }
        return RulesPresentation(
            title: Self.descriptor.name,
            variant: exactLanding ? LocalizedText(verbatim: "Pro") : LocalizedText(fr: "Débutant", en: "Beginner"),
            rows: rows,
            dartCaptions: captions,
            turnSummary: summary,
            highlights: landingHighlights(for: p),
            outcome: finished ? outcome() : nil,
            facts: [:])
    }

    // MARK: Presentation helpers

    private static let bustText = LocalizedText(verbatim: "BUST")

    private static func lastTurnText(_ turn: LastTurn) -> LocalizedText {
        switch turn {
        case .scored(let points): return LocalizedText(fr: "Dernière volée : \(points)", en: "Last turn: \(points)")
        case .bust: return bustText
        }
    }

    /// Pro mode only: `target` on every bed worth exactly the remaining distance (GAMES.md §10.7).
    private func landingHighlights(for player: PlayerIndex) -> [BoardHighlight] {
        guard exactLanding else { return [] }
        return Hit.all.compactMap { hit in
            guard !hit.isMiss, hit.points == remaining[player], let zone = BoardZone(hit) else { return nil }
            return BoardHighlight(zone: zone, role: .target)
        }
    }

    private func resultLines(for player: PlayerIndex) -> [LocalizedText] {
        var lines = [LocalizedText.counted(dartsThrown[player], fr: ("fléchette", "fléchettes"), en: ("dart", "darts"))]
        if busts[player] > 0 {
            lines.append(LocalizedText.counted(busts[player], fr: ("bust", "busts"), en: ("bust", "busts")))
        }
        return lines
    }

    /// Sentence of the results screen: about the player who landed, or about the closest ones at the round limit.
    private func outcome() -> LocalizedText {
        if let winner = remaining.firstIndex(of: 0) {
            let darts = LocalizedText.counted(dartsThrown[winner], fr: ("fléchette", "fléchettes"), en: ("dart", "darts"))
            return LocalizedText(fr: "Posé sur la Lune en \(darts.fr).", en: "Landed on the Moon in \(darts.en).")
        }
        let best = remaining.min() ?? 0
        if remaining.filter({ $0 == best }).count > 1 {
            return LocalizedText(fr: "Égalité à \(best) de la Lune.", en: "Tied, \(best) away from the Moon.")
        }
        return LocalizedText(fr: "Le plus proche de la Lune : encore \(best).", en: "Closest to the Moon: \(best) to go.")
    }
}
