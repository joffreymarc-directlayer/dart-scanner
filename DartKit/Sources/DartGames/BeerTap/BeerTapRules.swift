import DartCore

/// GAMES.md §13. Every point pours a centilitre of beer; a turn of 100 points or more earns a free glass.
/// The descriptor is the one written by lot F0, word for word.
public struct BeerTapRules: TurnBasedRules {
    public static let descriptor = GameDescriptor(
        id: .beerTap,
        name: LocalizedText(fr: "Tireuse", en: "Beer Tap"),
        shortName: LocalizedText(fr: "Tireuse", en: "Beer Tap"),
        summary: LocalizedText(fr: "Remplir des verres", en: "Fill the glasses"),
        pitch: LocalizedText(fr: "Chaque point verse un centilitre de bière : remplissez plus de verres que les autres. Une volée de 100 points, et un verre vous est offert.",
                             en: "Every point pours a centilitre of beer: fill more glasses than the others. Score 100 in a turn and a glass is on the house."),
        players: 1...8,
        options: [
            OptionDescriptor(key: "glassSize", label: LocalizedText(fr: "Verre", en: "Glass"),
                             kind: .choice([OptionChoice(25, label: LocalizedText(fr: "Demi", en: "Half")), OptionChoice(50, label: LocalizedText(fr: "Pinte", en: "Pint")), OptionChoice(100, label: LocalizedText(verbatim: "Litre"))]),
                             defaultValue: 50),
            OptionDescriptor(key: "rounds", label: LocalizedText(fr: "Manches", en: "Rounds"),
                             kind: .stepper(1...20),
                             defaultValue: 5),
        ],
        playStyle: .score,
        origin: .dartsee,
        priority: 1)

    /// A turn worth at least this many points earns a free glass, whatever the glass size (GAMES.md §13.5).
    static let bonusThreshold = 100

    /// Capacity of a glass, in centilitres: 25, 50 or 100.
    let glassSize: Int
    let rounds: Int
    /// Centilitres poured by each player, free glasses included.
    var poured: [Int]
    var bonusGlasses: [Int]
    var dartsThrown: [Int]
    /// Total of each player's last closed turn, for the scoreboard only.
    var lastTurn: [Int?]
    /// Per-turn scratch state, reset by `turnStarted`: the glasses filled by each dart of the turn.
    var turnFills: [Int] = []

    public init(configuration: GameConfiguration, random: inout SeededRandom) throws {
        // The kernel has validated the configuration already; a rule built on its own is as strict.
        let descriptor = Self.descriptor
        let count = configuration.players.count
        if let issue = descriptor.validate(options: configuration.options, playerCount: count).first { throw issue }
        let options = descriptor.normalized(configuration.options)
        guard let glassSize = options.int("glassSize") else { throw GameConfigurationError.invalidOptionValue(key: "glassSize") }
        guard let rounds = options.int("rounds") else { throw GameConfigurationError.invalidOptionValue(key: "rounds") }
        self.glassSize = glassSize
        self.rounds = rounds
        poured = Array(repeating: 0, count: count)
        bonusGlasses = Array(repeating: 0, count: count)
        dartsThrown = Array(repeating: 0, count: count)
        lastTurn = Array(repeating: nil, count: count)
    }

    /// Full glasses of a player.
    func glasses(_ player: PlayerIndex) -> Int { poured[player] / glassSize }
    /// Content of the glass being filled, 0 to `glassSize − 1`.
    func level(_ player: PlayerIndex) -> Int { poured[player] % glassSize }

    public var roundLimit: Int? { rounds }
    public func isEliminated(_ player: PlayerIndex) -> Bool { false }

    public mutating func turnStarted(_ context: TurnContext, random: inout SeededRandom, events: inout [GameEvent]) {
        turnFills = []
    }

    public mutating func dartThrown(_ hit: Hit, _ context: TurnContext, random: inout SeededRandom,
                                    events: inout [GameEvent]) -> DartVerdict {
        let p = context.currentPlayer
        dartsThrown[p] += 1
        guard !hit.isMiss else {
            turnFills.append(0)
            events.append(.noEffect(player: p))
            return .turnContinues
        }
        let before = glasses(p)
        poured[p] += hit.points
        // The overflow is never lost: it goes into the next glass, and one dart may fill several.
        let filled = glasses(p) - before
        turnFills.append(filled)
        if filled >= 1 { events.append(.glassFilled(player: p, count: filled, glasses: glasses(p))) }
        return .turnContinues
    }

    public mutating func turnClosed(_ context: TurnContext, events: inout [GameEvent]) {
        let p = context.currentPlayer
        let total = Self.total(of: context.darts)
        lastTurn[p] = total
        events.append(.turnScored(player: p, points: total))
        if total == 180 { events.append(.oneEighty(player: p)) }
        else if total >= 100 { events.append(.highTurn(player: p, points: total)) }
        if total >= Self.bonusThreshold {
            // A whole glass: the level of the glass being filled does not move.
            poured[p] += glassSize
            bonusGlasses[p] += 1
            events.append(.bonusGlass(player: p, glasses: glasses(p)))
        }
    }

    public func ranks() -> [Int] { Ranking.ranks(keys: poured.map { [-$0] }) }

    public func presentation(_ context: TurnContext) -> RulesPresentation {
        // After the round limit the volley is empty and no turn is in progress (ARCHITECTURE.md §4.7).
        let noTurn = context.phase == .finished && context.darts.isEmpty
        let total = Self.total(of: context.darts)
        return RulesPresentation(
            title: Self.descriptor.name,
            variant: Self.glassName(glassSize),
            rows: poured.indices.map { row($0) },
            dartCaptions: zip(context.darts, turnFills).map { hit, filled in
                DartCaption(LocalizedText(verbatim: "\(hit.points)"), tone: filled >= 1 ? .positive : .neutral)
            },
            turnSummary: noTurn ? nil : LocalizedText(fr: "Volée : \(total)", en: "Turn: \(total)"),
            outcome: outcome())
    }

    // MARK: Private

    private static func total(of darts: [Hit]) -> Int {
        darts.reduce(0) { $0 + $1.points }
    }

    /// Label of the glass size, as the setup screen shows it: "Demi", "Pinte", "Litre".
    private static func glassName(_ size: Int) -> LocalizedText? {
        guard case .choice(let choices)? = descriptor.option("glassSize")?.kind else { return nil }
        return choices.first { $0.value == .int(size) }?.label
    }

    private static func fullGlasses(_ count: Int) -> LocalizedText {
        .counted(count, fr: (one: "verre plein", other: "verres pleins"), en: (one: "full glass", other: "full glasses"))
    }

    private func row(_ player: PlayerIndex) -> PlayerRow {
        let full = glasses(player)
        var detail: LocalizedText?
        if let last = lastTurn[player] {
            let free = bonusGlasses[player]
            detail = LocalizedText(fr: "Dernière volée : \(last)", en: "Last turn: \(last)")
            if free > 0 {
                detail = LocalizedText(fr: "Dernière volée : \(last) · \(free) \(free == 1 ? "offert" : "offerts")",
                                       en: "Last turn: \(last) · \(free) free")
            }
        }
        var lines = [LocalizedText(fr: "\(poured[player]) cl versés", en: "\(poured[player]) cl poured")]
        if bonusGlasses[player] > 0 {
            lines.append(.counted(bonusGlasses[player], fr: (one: "verre offert", other: "verres offerts"),
                                  en: (one: "free glass", other: "free glasses")))
        }
        return PlayerRow(
            player: player,
            primary: ScoreValue(full, unit: LocalizedText(fr: full <= 1 ? "verre" : "verres", en: full == 1 ? "glass" : "glasses")),
            detail: detail,
            meter: Meter(value: level(player), maximum: glassSize, style: .bar),
            resultLines: lines,
            facts: ["poured": .int(poured[player]), "glasses": .int(full), "level": .int(level(player)),
                    "bonusGlasses": .int(bonusGlasses[player]), "dartsThrown": .int(dartsThrown[player])])
    }

    /// Results sentence about the winner; the kernel only lets it out once the game is finished.
    private func outcome() -> LocalizedText {
        let best = poured.max() ?? 0
        let full = Self.fullGlasses(best / glassSize)
        if poured.count > 1 && poured.filter({ $0 == best }).count > 1 {
            return LocalizedText(fr: "Égalité : \(best) cl versés chacun.", en: "A tie: \(best) cl poured each.")
        }
        if poured.count == 1 {
            return LocalizedText(fr: "\(best) cl versés, soit \(full.fr).", en: "\(best) cl poured, that is \(full.en).")
        }
        return LocalizedText(fr: "Le plus de bière versée : \(best) cl, soit \(full.fr).",
                             en: "Most beer poured: \(best) cl, that is \(full.en).")
    }
}
