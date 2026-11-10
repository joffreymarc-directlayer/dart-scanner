import DartCore

/// GAMES.md §11 Combat. Every player gets three distinct numbers: one heal number and two weak spots. A dart on
/// your heal number gives you lives back, a dart on a weak spot of a living opponent takes lives from him; singles,
/// doubles and trebles count 1, 2 and 3. The last player standing wins.
/// The descriptor is the final one written by lot F0 (ARCHITECTURE.md §5.3).
public struct FightRules: TurnBasedRules {
    public static let descriptor = GameDescriptor(
        id: .fight,
        name: LocalizedText(fr: "Combat", en: "Fight"),
        shortName: LocalizedText(fr: "Combat", en: "Fight"),
        summary: LocalizedText(fr: "9 vies, blesser ou soigner", en: "9 lives, hurt or heal"),
        pitch: LocalizedText(fr: "Neuf vies chacun : frappez les points faibles des autres, soignez-vous sur votre numéro. Le dernier debout gagne.",
                             en: "Nine lives each: hit the others' weak spots, heal on your own number. Last one standing wins."),
        players: 2...6,
        options: [
            OptionDescriptor(key: "lives", label: LocalizedText(fr: "Vies", en: "Lives"),
                             kind: .stepper(1...20),
                             defaultValue: 9),
            OptionDescriptor(key: "maxRounds", label: LocalizedText(fr: "Manches maximum", en: "Round limit"),
                             kind: .optionalStepper(1...99, nullLabel: LocalizedText(fr: "Sans limite", en: "No limit")),
                             defaultValue: 15, isAdvanced: true),
        ],
        playStyle: .board,
        origin: .dartsee,
        priority: 0)

    /// What one dart of the current turn did: kept for its caption (the state alone cannot tell it afterwards).
    enum DartEffect: Hashable, Sendable {
        case none
        case healed(amount: Int)
        case healWasted
        case damaged(victim: PlayerIndex, amount: Int, knockedOut: Bool)
    }

    /// Starting lives, which is also the ceiling of a heal.
    let maxLives: Int
    let maxRounds: Int?
    /// `healNumber[player]`: fixed for the whole game.
    let healNumber: [Int]
    /// `weakNumbers[player]`: two numbers, fixed for the whole game.
    let weakNumbers: [[Int]]
    /// A player is eliminated when, and only when, his lives are at 0.
    var lives: [Int]
    var kills: [Int]
    /// Eliminated players, first out first.
    var eliminationOrder: [PlayerIndex] = []
    /// Round in which each eliminated player went out.
    var eliminationRound: [Int?]
    // Per-turn scratch state, reset by `turnStarted`.
    var turnEffects: [DartEffect] = []

    public init(configuration: GameConfiguration, random: inout SeededRandom) throws {
        let count = configuration.players.count
        // Three numbers per player: more than six players do not fit on twenty numbers (GAMES.md §11.1).
        guard Self.descriptor.players.contains(count) else {
            throw GameConfigurationError.playerCountOutOfRange(allowed: Self.descriptor.players, actual: count)
        }
        maxLives = configuration.options.int("lives") ?? 9
        maxRounds = configuration.options.int("maxRounds")
        // The draw of GAMES.md §11.3: one shuffle of 1...20 (19 draws), read three by three.
        let shuffled = random.shuffled(Array(1...20))
        healNumber = (0..<count).map { shuffled[3 * $0] }
        weakNumbers = (0..<count).map { [shuffled[3 * $0 + 1], shuffled[3 * $0 + 2]] }
        lives = Array(repeating: maxLives, count: count)
        kills = Array(repeating: 0, count: count)
        eliminationRound = Array(repeating: nil, count: count)
    }

    public var roundLimit: Int? { maxRounds }
    public func isEliminated(_ player: PlayerIndex) -> Bool { lives[player] <= 0 }

    public mutating func turnStarted(_ context: TurnContext, random: inout SeededRandom, events: inout [GameEvent]) {
        turnEffects = []
    }

    public mutating func dartThrown(_ hit: Hit, _ context: TurnContext, random: inout SeededRandom,
                                    events: inout [GameEvent]) -> DartVerdict {
        let p = context.currentPlayer
        // MISS and both bulls have no number: no effect (GAMES.md §11.4).
        guard let number = hit.number else { return noEffect(p, &events) }
        let force = hit.multiplier

        if number == healNumber[p] {
            let gain = min(maxLives, lives[p] + force) - lives[p]
            guard gain > 0 else {
                turnEffects.append(.healWasted)
                events.append(.healWasted(player: p))
                return .turnContinues
            }
            lives[p] += gain
            turnEffects.append(.healed(amount: gain))
            events.append(.healed(player: p, amount: gain, lives: lives[p]))
            return .turnContinues
        }

        // A weak spot of a LIVING opponent. The numbers of an eliminated player are inert, the player's own weak
        // spots too, and so are the heal numbers of the others and the numbers nobody received.
        guard let victim = lives.indices.first(where: { $0 != p && lives[$0] > 0 && weakNumbers[$0].contains(number) }) else {
            return noEffect(p, &events)
        }
        let loss = min(lives[victim], force)
        lives[victim] -= loss
        events.append(.damaged(player: victim, by: p, amount: loss, livesLeft: lives[victim]))
        guard lives[victim] == 0 else {
            turnEffects.append(.damaged(victim: victim, amount: loss, knockedOut: false))
            return .turnContinues
        }
        kills[p] += 1
        eliminationOrder.append(victim)
        eliminationRound[victim] = context.round
        turnEffects.append(.damaged(victim: victim, amount: loss, knockedOut: true))
        events.append(.playerEliminated(player: victim, by: p))
        return lives.filter { $0 > 0 }.count == 1 ? .gameFinished(.lastPlayerStanding) : .turnContinues
    }

    private mutating func noEffect(_ player: PlayerIndex, _ events: inout [GameEvent]) -> DartVerdict {
        turnEffects.append(.none)
        events.append(.noEffect(player: player))
        return .turnContinues
    }

    /// Nothing happens at the close of a turn: no bust, no turn total (GAMES.md §11.5).
    public mutating func turnClosed(_ context: TurnContext, events: inout [GameEvent]) {}

    /// Players alive by (1) lives, (2) kills, both descending; then the eliminated ones, last out first
    /// (GAMES.md §11.6).
    public func ranks() -> [Int] {
        Ranking.ranks(keys: lives.indices.map { player in
            if let order = eliminationOrder.firstIndex(of: player) { return [1, -order] }
            return [0, -lives[player], -kills[player]]
        })
    }
}
