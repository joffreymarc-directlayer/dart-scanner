import DartCore

/// GAMES.md §15. Five round targets lie on the board; a dart touches the one that contains its impact point.
/// The only position-dependent game (GAMES.md §2.13): it reads `context.impact`, never the bed, and computes in
/// integers only. It is also the only game that draws while a dart is applied (the replacement of a destroyed
/// target). The descriptor is the one written by lot F0, word for word.
public struct RadarRules: TurnBasedRules {
    public static let descriptor = GameDescriptor(
        id: .radar,
        name: LocalizedText(verbatim: "Radar"),
        shortName: LocalizedText(verbatim: "Radar"),
        summary: LocalizedText(fr: "Cibles rondes à détruire", en: "Round targets to destroy"),
        pitch: LocalizedText(fr: "Cinq cibles rondes sont posées sur le plateau : chaque touche rapporte des points, chaque cible détruite un bonus, et une nouvelle prend sa place.",
                             en: "Five round targets sit on the board: every hit scores, every target destroyed pays a bonus, and a new one takes its place."),
        players: 1...8,
        options: [
            OptionDescriptor(key: "movingTargets", label: LocalizedText(fr: "Cibles mobiles", en: "Moving targets"),
                             kind: .toggle,
                             defaultValue: false),
            OptionDescriptor(key: "rounds", label: LocalizedText(fr: "Manches", en: "Rounds"),
                             kind: .stepper(1...20),
                             defaultValue: 8),
        ],
        playStyle: .board,
        origin: .dartsee,
        priority: 1, dependsOnPosition: true)

    /// The three sizes of a target (GAMES.md §15.2).
    enum Size: Hashable, Sendable {
        case large, medium, small

        /// Millimetres.
        var radius: Int {
            switch self {
            case .large: return 40
            case .medium: return 28
            case .small: return 16
            }
        }

        /// Hit points of a new target.
        var hitPoints: Int {
            switch self {
            case .large: return 3
            case .medium: return 2
            case .small: return 1
            }
        }

        /// Points of one hit.
        var hitValue: Int {
            switch self {
            case .large: return 10
            case .medium: return 20
            case .small: return 50
            }
        }

        /// Bonus of the hit that destroys the target.
        var bonus: Int {
            switch self {
            case .large: return 20
            case .medium: return 40
            case .small: return 100
            }
        }
    }

    /// The board always carries five targets; a slot keeps its size for the whole game.
    static let slots: [Size] = [.large, .large, .medium, .medium, .small]

    /// One target: its centre in whole millimetres and its hit points left. Its size is the one of its slot.
    struct Blob: Hashable, Sendable {
        var x: Int
        var y: Int
        var hitPoints: Int
    }

    /// What one dart of the current turn did, for its caption.
    enum DartEffect: Hashable, Sendable {
        case none
        case damaged(points: Int)
        case destroyed(points: Int)
    }

    let movingTargets: Bool
    let rounds: Int
    /// The five targets, by slot.
    var blobs: [Blob]
    var points: [Int]
    var destroyed: [Int]
    var dartsThrown: [Int]
    /// Points of each player's last closed turn, for the scoreboard only.
    var lastTurn: [Int?]
    /// Per-turn scratch state, reset by `turnStarted`.
    var turnPoints = 0
    var turnEffects: [DartEffect] = []

    public init(configuration: GameConfiguration, random: inout SeededRandom) throws {
        // The kernel has validated the configuration already; a rule built on its own is as strict.
        let descriptor = Self.descriptor
        let count = configuration.players.count
        if let issue = descriptor.validate(options: configuration.options, playerCount: count).first { throw issue }
        let options = descriptor.normalized(configuration.options)
        guard let movingTargets = options.bool("movingTargets") else {
            throw GameConfigurationError.invalidOptionValue(key: "movingTargets")
        }
        guard let rounds = options.int("rounds") else { throw GameConfigurationError.invalidOptionValue(key: "rounds") }
        self.movingTargets = movingTargets
        self.rounds = rounds
        points = Array(repeating: 0, count: count)
        destroyed = Array(repeating: 0, count: count)
        dartsThrown = Array(repeating: 0, count: count)
        lastTurn = Array(repeating: nil, count: count)

        // Initial draw: slots 0 to 4 in order, each against the targets already placed. Five draws.
        var placed: [Blob] = []
        for size in Self.slots {
            let obstacles = zip(placed, Self.slots).map { RadarPlacement.Disc(x: $0.x, y: $0.y, radius: $1.radius) }
            let centre = RadarPlacement.place(radius: size.radius, obstacles: obstacles, random: &random)
            placed.append(Blob(x: centre.x, y: centre.y, hitPoints: size.hitPoints))
        }
        blobs = placed
    }

    public var roundLimit: Int? { rounds }
    public func isEliminated(_ player: PlayerIndex) -> Bool { false }

    public mutating func turnStarted(_ context: TurnContext, random: inout SeededRandom, events: inout [GameEvent]) {
        turnPoints = 0
        turnEffects = []
        // Moving targets: at the start of every turn but the first of the game, never during a turn.
        guard movingTargets, !context.isFirstTurnOfGame else { return }
        // Slots 0 to 4 in order, each against the five targets where they are now, itself included: every target
        // really goes somewhere else, and the ones already moved count at their new place. Five draws.
        // Size and hit points are kept.
        for slot in blobs.indices {
            let centre = RadarPlacement.place(radius: Self.slots[slot].radius, obstacles: discs, random: &random)
            blobs[slot].x = centre.x
            blobs[slot].y = centre.y
        }
        events.append(.blobsMoved)
    }

    public mutating func dartThrown(_ hit: Hit, _ context: TurnContext, random: inout SeededRandom,
                                    events: inout [GameEvent]) -> DartVerdict {
        let p = context.currentPlayer
        dartsThrown[p] += 1
        // The tip counts, not the bed: MISS has no impact point, a recorded position is taken as it is, and a
        // dart without one stands at the canonical position of its bed (GAMES.md §2.13).
        guard let impact = context.impact, let slot = slot(at: impact) else {
            turnEffects.append(.none)
            events.append(.noEffect(player: p))
            return .turnContinues
        }
        let size = Self.slots[slot]
        if blobs[slot].hitPoints > 1 {
            blobs[slot].hitPoints -= 1
            points[p] += size.hitValue
            turnPoints += size.hitValue
            turnEffects.append(.damaged(points: size.hitValue))
            events.append(.blobDamaged(player: p, blob: slot, points: size.hitValue, hitPointsLeft: blobs[slot].hitPoints))
            return .turnContinues
        }
        // Destruction, then immediate replacement: a new target of the same size with all its hit points,
        // placed against the five targets where they are now, the destroyed one included. One draw.
        let gain = size.hitValue + size.bonus
        points[p] += gain
        turnPoints += gain
        destroyed[p] += 1
        turnEffects.append(.destroyed(points: gain))
        events.append(.blobDestroyed(player: p, blob: slot, points: gain))
        let centre = RadarPlacement.place(radius: size.radius, obstacles: discs, random: &random)
        blobs[slot] = Blob(x: centre.x, y: centre.y, hitPoints: size.hitPoints)
        return .turnContinues
    }

    public mutating func turnClosed(_ context: TurnContext, events: inout [GameEvent]) {
        let p = context.currentPlayer
        lastTurn[p] = turnPoints
        // The points are not those of the beds: never `oneEighty` nor `highTurn` (GAMES.md §2.10).
        events.append(.turnScored(player: p, points: turnPoints))
    }

    public func ranks() -> [Int] {
        Ranking.ranks(keys: points.indices.map { [-points[$0], -destroyed[$0]] })
    }

    public func presentation(_ context: TurnContext) -> RulesPresentation {
        // After the round limit the volley is empty and no turn is in progress (ARCHITECTURE.md §4.7).
        let noTurn = context.phase == .finished && context.darts.isEmpty
        return RulesPresentation(
            title: Self.descriptor.name,
            variant: movingTargets ? Self.descriptor.option("movingTargets")?.label : nil,
            rows: points.indices.map { row($0) },
            dartCaptions: zip(context.darts, turnEffects).map { _, effect in Self.caption(effect) },
            turnSummary: noTurn ? nil : LocalizedText(fr: "Volée : \(turnPoints)", en: "Turn: \(turnPoints)"),
            // The same highlights for every player: one disc per target.
            highlights: zip(blobs, Self.slots).map { blob, size in
                BoardHighlight(zone: .disc(x: Double(blob.x), y: Double(blob.y), radius: Double(size.radius)),
                               role: .target, label: "+\(size.hitValue)", strength: blob.hitPoints)
            },
            outcome: outcome(),
            facts: ["blobs": .table(zip(blobs, Self.slots).map { [$0.x, $0.y, $1.radius, $0.hitPoints] })])
    }

    // MARK: Private

    /// The five targets as obstacles of a placement, where they are now.
    private var discs: [RadarPlacement.Disc] {
        zip(blobs, Self.slots).map { RadarPlacement.Disc(x: $0.x, y: $0.y, radius: $1.radius) }
    }

    /// First slot, in the order 0 to 4, whose disc contains the impact point; the edge counts.
    /// Integers only, in tenths of a millimetre: an impact point is bounded by ±1 000 000 (GAMES.md §2.13).
    private func slot(at impact: ImpactPoint) -> Int? {
        blobs.indices.first { slot in
            let dx = impact.x - 10 * blobs[slot].x, dy = impact.y - 10 * blobs[slot].y
            let radius = 10 * Self.slots[slot].radius
            return dx * dx + dy * dy <= radius * radius
        }
    }

    private func row(_ player: PlayerIndex) -> PlayerRow {
        let count = destroyed[player]
        var detail = LocalizedText(fr: "\(count) \(count <= 1 ? "détruite" : "détruites")", en: "\(count) destroyed")
        if let last = lastTurn[player] {
            detail = LocalizedText(fr: "\(detail.fr) · dernière volée : \(last)", en: "\(detail.en) · last turn: \(last)")
        }
        return PlayerRow(
            player: player,
            primary: ScoreValue(points[player]),
            detail: detail,
            resultLines: [Self.targetsDestroyed(count)],
            facts: ["points": .int(points[player]), "destroyed": .int(count), "dartsThrown": .int(dartsThrown[player])])
    }

    private static func targetsDestroyed(_ count: Int) -> LocalizedText {
        .counted(count, fr: (one: "cible détruite", other: "cibles détruites"), en: (one: "target destroyed", other: "targets destroyed"))
    }

    private static func caption(_ effect: DartEffect) -> DartCaption {
        switch effect {
        case .none:
            return DartCaption(LocalizedText(fr: "Sans effet", en: "No effect"))
        case .damaged(let points):
            return DartCaption(LocalizedText(verbatim: "+\(points)"), tone: .positive)
        case .destroyed(let points):
            return DartCaption(LocalizedText(fr: "Détruite +\(points)", en: "Destroyed +\(points)"), tone: .accent)
        }
    }

    /// Results sentence about the winner; the kernel only lets it out once the game is finished.
    private func outcome() -> LocalizedText {
        let ranking = ranks()
        let winners = ranking.indices.filter { ranking[$0] == 1 }
        let best = LocalizedText.counted(points.max() ?? 0, fr: (one: "point", other: "points"), en: (one: "point", other: "points"))
        guard winners.count == 1, let winner = winners.first else {
            return LocalizedText(fr: "Égalité à \(best.fr).", en: "A tie at \(best.en).")
        }
        let targets = Self.targetsDestroyed(destroyed[winner])
        return LocalizedText(fr: "\(best.fr) et \(targets.fr).", en: "\(best.en) and \(targets.en).")
    }
}
