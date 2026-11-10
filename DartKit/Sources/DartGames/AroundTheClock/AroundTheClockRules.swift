import DartCore

/// GAMES.md §6. Hit the numbers 1 to 20 in order, then the bull with `finishOnBull`: the first player at the end
/// wins. With `multiplierJump` a double advances by two numbers and a treble by three, never past the 20.
public struct AroundTheClockRules: TurnBasedRules {
    public static let descriptor = GameDescriptor(
        id: .aroundTheClock,
        name: LocalizedText(fr: "Tour de l'horloge", en: "Around the Clock"),
        shortName: LocalizedText(fr: "Horloge", en: "Clock"),
        summary: LocalizedText(fr: "De 1 à 20 dans l'ordre", en: "1 to 20 in order"),
        pitch: LocalizedText(fr: "Touchez les numéros de 1 à 20 dans l'ordre : le premier arrivé au bout gagne.",
                             en: "Hit 1 to 20 in order: first to the end wins."),
        players: 1...8,
        options: [
            OptionDescriptor(key: "finishOnBull", label: LocalizedText(fr: "Finir sur le bull", en: "Finish on the bull"),
                             kind: .toggle,
                             defaultValue: false),
            OptionDescriptor(key: "multiplierJump", label: LocalizedText(fr: "Doubles et triples avancent plus", en: "Doubles and trebles jump"),
                             kind: .toggle,
                             defaultValue: false),
            OptionDescriptor(key: "maxRounds", label: LocalizedText(fr: "Manches maximum", en: "Round limit"),
                             kind: .optionalStepper(1...99, nullLabel: LocalizedText(fr: "Sans limite", en: "No limit")),
                             defaultValue: .null, isAdvanced: true),
        ],
        playStyle: .board,
        origin: .classic,
        priority: 2)

    // MARK: Options

    /// After the 20, a bull is still needed.
    let finishOnBull: Bool
    /// A double advances by 2 and a treble by 3; otherwise any bed of the target advances by 1.
    let multiplierJump: Bool
    let maxRounds: Int?

    // MARK: State (GAMES.md §6.3)

    /// What one dart of the current turn did. It only feeds the dart captions: no rule reads it back.
    enum DartEffect: Hashable, Sendable {
        case none
        /// `number` was the target (25 = bull) and the dart validated `advancedBy` targets.
        case advanced(number: Int, advancedBy: Int)
    }

    /// Number of targets validated: 0...20, and 21 once the bull is hit with `finishOnBull`.
    var progress: [Int]
    var dartsThrown: [Int]
    /// Per-turn scratch state: the effect of each dart of the current turn. After a game ended at the round limit
    /// it still holds the last turn while the kernel's volley is empty (ARCHITECTURE.md §4.7).
    var turnEffects: [DartEffect] = []

    public init(configuration: GameConfiguration, random: inout SeededRandom) throws {
        let descriptor = Self.descriptor
        let count = configuration.players.count
        if let issue = descriptor.validate(options: configuration.options, playerCount: count).first {
            throw issue
        }
        let options = descriptor.normalized(configuration.options)
        guard let finishOnBull = options.bool("finishOnBull") else {
            throw GameConfigurationError.invalidOptionValue(key: "finishOnBull")
        }
        guard let multiplierJump = options.bool("multiplierJump") else {
            throw GameConfigurationError.invalidOptionValue(key: "multiplierJump")
        }
        self.finishOnBull = finishOnBull
        self.multiplierJump = multiplierJump
        // `.null` is "no limit", the default: the classic game has none.
        self.maxRounds = options.int("maxRounds")
        progress = Array(repeating: 0, count: count)
        dartsThrown = Array(repeating: 0, count: count)
    }

    // MARK: Queries

    /// The bull as a target is written 25 (ARCHITECTURE.md §4.5).
    static let bullTarget = 25

    public var roundLimit: Int? { maxRounds }

    public func isEliminated(_ player: PlayerIndex) -> Bool { false }

    /// `progress` to reach: 20, or 21 with `finishOnBull`.
    var goal: Int { finishOnBull ? 21 : 20 }

    /// Derived target of a player: `progress + 1` while `progress < 20`, the bull (25) when `progress == 20`
    /// with `finishOnBull`, and 0 when no target is left.
    func target(of player: PlayerIndex) -> Int {
        let done = progress[player]
        if done < 20 { return done + 1 }
        if done == 20 && finishOnBull { return Self.bullTarget }
        return 0
    }

    // MARK: Turn flow

    public mutating func turnStarted(_ context: TurnContext, random: inout SeededRandom, events: inout [GameEvent]) {
        turnEffects = []
    }

    public mutating func dartThrown(_ hit: Hit, _ context: TurnContext, random: inout SeededRandom,
                                    events: inout [GameEvent]) -> DartVerdict {
        let player = context.currentPlayer
        dartsThrown[player] += 1
        let target = target(of: player)
        let before = progress[player]
        if target == Self.bullTarget {
            // Either bull finishes; it never counts before the 20 is done.
            guard hit.isBull else { return noEffect(player, &events) }
            progress[player] = 21
        } else if let number = hit.number, number == target {
            // The jumped numbers are validated too; the cap at 20 means the bull is never jumped.
            let step = multiplierJump ? hit.multiplier : 1
            progress[player] = min(20, before + step)
        } else {
            return noEffect(player, &events)
        }
        let advancedBy = progress[player] - before
        events.append(.targetHit(player: player, number: target, advancedBy: advancedBy))
        turnEffects.append(.advanced(number: target, advancedBy: advancedBy))
        // The target moves at once: several numbers can fall in one turn, and the game stops on the winning dart.
        return progress[player] >= goal ? .gameFinished(.victory) : .turnContinues
    }

    public mutating func turnClosed(_ context: TurnContext, events: inout [GameEvent]) {}

    private mutating func noEffect(_ player: PlayerIndex, _ events: inout [GameEvent]) -> DartVerdict {
        events.append(.noEffect(player: player))
        turnEffects.append(.none)
        return .turnContinues
    }

    // MARK: Ranking (GAMES.md §6.6)

    public func ranks() -> [Int] {
        Ranking.ranks(keys: progress.map { [-$0] })
    }

    // MARK: Presentation (GAMES.md §6.7)

    public func presentation(_ context: TurnContext) -> RulesPresentation {
        let current = context.currentPlayer
        let currentTarget = progress.indices.contains(current) ? target(of: current) : 0
        return RulesPresentation(
            title: Self.descriptor.name,
            objective: currentTarget == 0 ? nil
                : LocalizedText(fr: "Cible : \(Self.name(ofTarget: currentTarget).fr)", en: "Target: \(Self.name(ofTarget: currentTarget).en)"),
            rows: progress.indices.map { player in
                let target = target(of: player)
                let darts = LocalizedText.counted(dartsThrown[player], fr: (one: "fléchette", other: "fléchettes"),
                                                  en: (one: "dart", other: "darts"))
                return PlayerRow(
                    player: player,
                    // The current target is the main value; a tick once the player has no target left.
                    primary: target == 0 ? ScoreValue("✓")
                        : ScoreValue(target == Self.bullTarget ? "Bull" : "\(target)",
                                     unit: LocalizedText(fr: "cible", en: "target")),
                    detail: darts,
                    meter: Meter(value: progress[player], maximum: goal, style: .bar),
                    resultLines: [LocalizedText(verbatim: "\(progress[player]) / \(goal)"), darts],
                    facts: ["progress": .int(progress[player]), "target": .int(target), "dartsThrown": .int(dartsThrown[player])])
            },
            // Never more captions than darts: the volley is empty after a game ended at the round limit.
            dartCaptions: turnEffects.prefix(context.darts.count).map(Self.caption),
            highlights: Self.highlights(forTarget: currentTarget),
            outcome: outcome())
    }

    /// "7", or "bull" for the target 25.
    private static func name(ofTarget target: Int) -> LocalizedText {
        target == bullTarget ? LocalizedText(verbatim: "bull") : LocalizedText(verbatim: "\(target)")
    }

    /// `target` on the sector of the number to hit, or on the bull; nothing once no target is left.
    static func highlights(forTarget target: Int) -> [BoardHighlight] {
        if target == bullTarget { return [BoardHighlight(zone: .bull, role: .target)] }
        guard (1...20).contains(target) else { return [] }
        return [BoardHighlight(zone: .sector(target), role: .target)]
    }

    /// The effect of a dart in three words at most: "7 validé", "+3 numéros", "Bull validé", "Sans effet".
    private static func caption(for effect: DartEffect) -> DartCaption {
        switch effect {
        case .none:
            return DartCaption(LocalizedText(fr: "Sans effet", en: "No effect"))
        case .advanced(let number, _) where number == bullTarget:
            return DartCaption(LocalizedText(fr: "Bull validé", en: "Bull done"), tone: .positive)
        case .advanced(let number, let advancedBy) where advancedBy <= 1:
            return DartCaption(LocalizedText(fr: "\(number) validé", en: "\(number) done"), tone: .positive)
        case .advanced(_, let advancedBy):
            return DartCaption(LocalizedText(fr: "+\(advancedBy) numéros", en: "+\(advancedBy) numbers"), tone: .positive)
        }
    }

    /// Sentence about the winner; the kernel only lets it out once the game is finished.
    private func outcome() -> LocalizedText? {
        let ranks = ranks()
        let winners = ranks.indices.filter { ranks[$0] == 1 }
        guard let best = winners.first else { return nil }
        if progress[best] >= goal {
            let darts = LocalizedText.counted(dartsThrown[best], fr: (one: "fléchette", other: "fléchettes"),
                                              en: (one: "dart", other: "darts"))
            return LocalizedText(fr: "Premier arrivé au bout, en \(darts.fr).", en: "First to the end, in \(darts.en).")
        }
        let done = "\(progress[best]) / \(goal)"
        if winners.count == 1 {
            return LocalizedText(fr: "Le plus avancé à la limite de manches : \(done).",
                                 en: "Furthest at the round limit: \(done).")
        }
        return LocalizedText(fr: "Égalité à la limite de manches : \(done).", en: "Tie at the round limit: \(done).")
    }
}
