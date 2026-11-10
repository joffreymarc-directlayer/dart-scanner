import DartCore

/// GAMES.md §4: close the targets with three marks each, then score on what the others left open.
/// The descriptor is the final one written by lot F0 (ARCHITECTURE.md §5.3).
public struct CricketRules: TurnBasedRules {
    public static let descriptor = GameDescriptor(
        id: .cricket,
        name: LocalizedText(verbatim: "Cricket"),
        shortName: LocalizedText(verbatim: "Cricket"),
        summary: LocalizedText(fr: "Fermer 15 à 20 et le bull", en: "Close 15 to 20 and the bull"),
        pitch: LocalizedText(fr: "Fermez les numéros 15 à 20 et le bull en les touchant trois fois, puis marquez des points sur ceux que les autres n'ont pas fermés.",
                             en: "Close 15 to 20 and the bull with three marks each, then score on what the others left open."),
        players: 1...8,
        options: [
            OptionDescriptor(key: "scoring", label: LocalizedText(fr: "Score", en: "Scoring"),
                             kind: .choice([OptionChoice("cutThroat", label: LocalizedText(verbatim: "Cut-throat")), OptionChoice("standard", label: LocalizedText(verbatim: "Standard"))]),
                             defaultValue: "cutThroat"),
            OptionDescriptor(key: "targets", label: LocalizedText(fr: "Cibles", en: "Targets"),
                             kind: .choice([OptionChoice("normal", label: LocalizedText(verbatim: "Normal")), OptionChoice("light", label: LocalizedText(fr: "Léger", en: "Light"))]),
                             defaultValue: "normal"),
            OptionDescriptor(key: "maxRounds", label: LocalizedText(fr: "Manches maximum", en: "Round limit"),
                             kind: .optionalStepper(1...99, nullLabel: LocalizedText(fr: "Sans limite", en: "No limit")),
                             defaultValue: 20, isAdvanced: true),
        ],
        playStyle: .score,
        origin: .dartsee,
        priority: 0)

    /// The bull as a target, in facts and events (ARCHITECTURE.md §4.5); also its value per mark.
    static let bull = 25
    /// Marks that close a target.
    static let marksToClose = 3

    /// What one dart of the current turn did, kept for its caption.
    struct DartEffect: Hashable, Sendable {
        /// Target hit; nil when the dart is off target or a MISS.
        var target: Int?
        /// Closing marks laid by the dart (0...3).
        var closing = 0
        /// The dart laid the third mark.
        var closed = false
        /// Points of the scoring marks: gained by the thrower (standard) or given to each open opponent (cut-throat).
        var points = 0
    }

    let cutThroat: Bool
    let light: Bool
    let maxRounds: Int?
    /// Targets in display order; the bull is written 25.
    let targets: [Int]
    /// `marks[player][i]` for `targets[i]`, 0...3.
    var marks: [[Int]]
    var points: [Int]
    // Per-turn scratch state, reset by `turnStarted`. After a game ended at the round limit it still describes
    // the last turn while the kernel's volley is empty (ARCHITECTURE.md §4.7).
    var turnMarks = 0
    var turnEffects: [DartEffect] = []

    public init(configuration: GameConfiguration, random: inout SeededRandom) throws {
        // The kernel hands over validated options completed with their defaults; a rule created directly gets the
        // same treatment, and a value it cannot read is refused rather than replaced (ARCHITECTURE.md §4.4).
        let options = Self.descriptor.normalized(configuration.options)
        switch options.string("scoring") {
        case "cutThroat"?: cutThroat = true
        case "standard"?: cutThroat = false
        default: throw GameConfigurationError.invalidOptionValue(key: "scoring")
        }
        switch options.string("targets") {
        case "normal"?: light = false
        case "light"?: light = true
        default: throw GameConfigurationError.invalidOptionValue(key: "targets")
        }
        switch options["maxRounds"] {
        case .null?: maxRounds = nil
        case .int(let rounds)? where (1...99).contains(rounds): maxRounds = rounds
        default: throw GameConfigurationError.invalidOptionValue(key: "maxRounds")
        }
        // GAMES.md §2.3: a number of players outside the range is refused, before anything is drawn.
        let count = configuration.players.count
        guard Self.descriptor.players.contains(count) else {
            throw GameConfigurationError.playerCountOutOfRange(allowed: Self.descriptor.players, actual: count)
        }
        if light {
            // GAMES.md §4.3: five draws; the first four numbers, in decreasing order; the bull is not a target.
            let shuffled = random.shuffled([15, 16, 17, 18, 19, 20])
            targets = shuffled.prefix(4).sorted(by: >)
        } else {
            targets = [20, 19, 18, 17, 16, 15, Self.bull]
        }
        marks = Array(repeating: Array(repeating: 0, count: targets.count), count: count)
        points = Array(repeating: 0, count: count)
    }

    public var roundLimit: Int? { maxRounds }
    public func isEliminated(_ player: PlayerIndex) -> Bool { false }

    public mutating func turnStarted(_ context: TurnContext, random: inout SeededRandom, events: inout [GameEvent]) {
        turnMarks = 0
        turnEffects = []
    }

    /// GAMES.md §4.4: the marks of a dart are handled one by one, closing marks first, then scoring marks.
    public mutating func dartThrown(_ hit: Hit, _ context: TurnContext, random: inout SeededRandom,
                                    events: inout [GameEvent]) -> DartVerdict {
        let p = context.currentPlayer
        guard let target = hit.isBull ? Self.bull : hit.number, let t = targets.firstIndex(of: target) else {
            // A number outside the targets, the bull when it is not a target, or a MISS.
            events.append(.noEffect(player: p))
            turnEffects.append(DartEffect())
            return .turnContinues
        }
        var effect = DartEffect(target: target)
        var scoringMarks = 0
        // Opponents still open on the target. Scoring marks never change it, so it is the same for the whole dart.
        let open = marks.indices.filter { $0 != p && marks[$0][t] < Self.marksToClose }
        for _ in 0..<hit.multiplier {
            if marks[p][t] < Self.marksToClose {
                marks[p][t] += 1
                effect.closing += 1
                effect.closed = marks[p][t] == Self.marksToClose
            } else if !open.isEmpty {
                scoringMarks += 1
            }
            // Otherwise the mark is lost: the target is dead.
        }
        if effect.closing > 0 {
            events.append(.marksScored(player: p, target: target, count: effect.closing))
        }
        if effect.closed {
            events.append(.targetClosed(player: p, target: target))
            if open.isEmpty { events.append(.targetDead(target: target)) }
        }
        if scoringMarks > 0 {
            effect.points = scoringMarks * target
            if cutThroat {
                for opponent in open { points[opponent] += effect.points }
                events.append(.pointsGiven(player: p, to: open, pointsEach: effect.points))
            } else {
                points[p] += effect.points
                events.append(.pointsScored(player: p, points: effect.points))
            }
        }
        if effect.closing == 0 && scoringMarks == 0 {
            // Every mark was lost on a dead target.
            events.append(.noEffect(player: p))
        }
        turnMarks += effect.closing + scoringMarks
        turnEffects.append(effect)
        return winner == nil ? .turnContinues : .gameFinished(.victory)
    }

    public mutating func turnClosed(_ context: TurnContext, events: inout [GameEvent]) {}

    /// GAMES.md §4.6: (1) best score, (2) most closing marks, (3) tie.
    public func ranks() -> [Int] {
        Ranking.ranks(keys: points.indices.map { [cutThroat ? points[$0] : -points[$0], -totalMarks($0)] })
    }

    // MARK: State queries

    private func hasClosed(_ player: PlayerIndex, _ t: Int) -> Bool { marks[player][t] == Self.marksToClose }

    /// Closed by every player.
    private func isDead(_ t: Int) -> Bool { marks.indices.allSatisfy { hasClosed($0, t) } }

    private func closedCount(_ player: PlayerIndex) -> Int { marks[player].filter { $0 == Self.marksToClose }.count }

    /// Closing marks of a player, three at most per target.
    private func totalMarks(_ player: PlayerIndex) -> Int { marks[player].reduce(0, +) }

    /// "Best score": higher in standard, lower in cut-throat.
    private func isStrictlyBetter(_ a: Int, than b: Int) -> Bool { cutThroat ? a < b : a > b }

    /// GAMES.md §4.6: a player who closed EVERY target while no other player has a strictly better score.
    /// Not necessarily the thrower: in cut-throat the points another player gives can make this player win.
    private var winner: PlayerIndex? {
        points.indices.first { w in
            closedCount(w) == targets.count
                && !points.indices.contains { $0 != w && isStrictlyBetter(points[$0], than: points[w]) }
        }
    }

    // MARK: Presentation (GAMES.md §4.7, ARCHITECTURE.md §5.6)

    public func presentation(_ context: TurnContext) -> RulesPresentation {
        let p = context.currentPlayer
        // The kernel's volley may be shorter than the scratch state (game ended at the round limit).
        let shown = min(context.darts.count, turnEffects.count)
        let turnIsOver = context.phase == .finished && context.darts.isEmpty
        var summary: LocalizedText?
        if !turnIsOver {
            let counted = Self.marksText(turnMarks)
            summary = LocalizedText(fr: "Volée : \(counted.fr)", en: "Turn: \(counted.en)")
        }
        return RulesPresentation(
            title: Self.descriptor.name,
            variant: variant,
            rows: points.indices.map { row($0, finished: context.phase == .finished) },
            dartCaptions: turnEffects.prefix(shown).map(caption),
            turnSummary: summary,
            highlights: targets.indices.map { highlight($0, for: p) },
            grid: ScoreGrid(columns: targets.map { $0 == Self.bull ? "B" : String($0) },
                            marks: marks,
                            dead: targets.indices.map(isDead)),
            outcome: context.phase == .finished ? outcome : nil,
            facts: ["targets": .ints(targets)])
    }

    /// "Cut-throat", "Standard", followed by "Léger" for the light game.
    private var variant: LocalizedText {
        let scoring = cutThroat ? "Cut-throat" : "Standard"
        guard light else { return LocalizedText(verbatim: scoring) }
        return LocalizedText(fr: "\(scoring) · Léger", en: "\(scoring) · Light")
    }

    private static func closedText(_ count: Int) -> LocalizedText {
        .counted(count, fr: (one: "cible fermée", other: "cibles fermées"), en: (one: "target closed", other: "targets closed"))
    }

    private static func marksText(_ count: Int) -> LocalizedText {
        .counted(count, fr: (one: "marque", other: "marques"), en: (one: "mark", other: "marks"))
    }

    private func row(_ i: PlayerIndex, finished: Bool) -> PlayerRow {
        let closed = closedCount(i)
        let byTarget = Dictionary(uniqueKeysWithValues: zip(targets, marks[i]))
        return PlayerRow(
            player: i,
            primary: ScoreValue(points[i]),
            detail: Self.closedText(closed),
            // Lines of the results screen: only read once the game is finished, like `outcome`.
            resultLines: finished ? [Self.closedText(closed), Self.marksText(totalMarks(i))] : [],
            facts: ["points": .int(points[i]), "marks": .map(byTarget), "closedCount": .int(closed)])
    }

    /// The effect of a dart in three words at most.
    private func caption(_ effect: DartEffect) -> DartCaption? {
        guard let target = effect.target, effect.closing > 0 || effect.points > 0 else {
            return DartCaption(LocalizedText(fr: "Sans effet", en: "No effect"))
        }
        let text: LocalizedText
        if effect.closed && effect.points > 0 {
            text = LocalizedText(fr: "Fermé · +\(effect.points)", en: "Closed · +\(effect.points)")
        } else if effect.closed {
            let name = target == Self.bull ? "Bull" : String(target)
            text = LocalizedText(fr: "\(name) fermé", en: "\(name) closed")
        } else if effect.closing > 0 {
            let counted = Self.marksText(effect.closing)
            text = LocalizedText(fr: "+\(counted.fr)", en: "+\(counted.en)")
        } else if cutThroat {
            text = LocalizedText(fr: "+\(effect.points) aux adversaires", en: "+\(effect.points) to opponents")
        } else {
            text = LocalizedText(verbatim: "+\(effect.points)")
        }
        return DartCaption(text, tone: .positive)
    }

    /// GAMES.md §4.7: to close (`target`), closed and still worth points (`secondary`), dead (`inactive`).
    private func highlight(_ t: Int, for p: PlayerIndex) -> BoardHighlight {
        let zone: BoardZone = targets[t] == Self.bull ? .bull : .sector(targets[t])
        let role: HighlightRole
        if !hasClosed(p, t) {
            role = .target
        } else if isDead(t) {
            role = .inactive
        } else {
            role = .secondary
        }
        return BoardHighlight(zone: zone, role: role)
    }

    /// Results sentence. A winner in the sense of §4.6 means a victory; otherwise the game ended at the round limit.
    private var outcome: LocalizedText {
        if let winner {
            guard points.count > 1 else {
                return LocalizedText(fr: "Toutes les cibles fermées.", en: "All targets closed.")
            }
            return LocalizedText(fr: "Toutes les cibles fermées et le meilleur score : \(points[winner]).",
                                 en: "All targets closed, with the best score: \(points[winner]).")
        }
        let ranks = ranks()
        let leaders = ranks.indices.filter { ranks[$0] == 1 }
        let leader = leaders.first ?? 0
        let score = LocalizedText.counted(points[leader], fr: (one: "point", other: "points"), en: (one: "point", other: "points"))
        let closing = Self.marksText(totalMarks(leader))
        if leaders.count > 1 {
            return LocalizedText(fr: "Égalité à la limite de manches : \(score.fr), \(closing.fr).",
                                 en: "Tied at the round limit: \(score.en), \(closing.en).")
        }
        return LocalizedText(fr: "En tête à la limite de manches : \(score.fr), \(closing.fr).",
                             en: "In the lead at the round limit: \(score.en), \(closing.en).")
    }
}
