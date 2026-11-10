import DartCore

/// GAMES.md §12 Conquérant. Every player starts with a home sector worth three lives. A dart on a neutral sector
/// next to your territory claims it, a dart on your own sector strengthens it, a dart on an opponent's sector next
/// to yours (or anywhere while you are King of the Hill, the last player who hit the bull) takes lives from it and
/// conquers it at zero. Losing your home eliminates you, and your territory goes to the conqueror.
/// The descriptor is the final one written by lot F0 (ARCHITECTURE.md §5.3).
public struct ConquerorRules: TurnBasedRules {
    public static let descriptor = GameDescriptor(
        id: .conqueror,
        name: LocalizedText(fr: "Conquérant", en: "Conqueror"),
        shortName: LocalizedText(fr: "Conquérant", en: "Conqueror"),
        summary: LocalizedText(fr: "Conquérir la cible", en: "Conquer the board"),
        pitch: LocalizedText(fr: "Étendez votre territoire de secteur en secteur, fortifiez-le et prenez la maison des autres.",
                             en: "Grow your territory sector by sector, fortify it and take the others' home."),
        players: 2...8,
        options: [
            OptionDescriptor(key: "multipliersCount", label: LocalizedText(fr: "Doubles et triples comptent", en: "Doubles and trebles count"),
                             kind: .toggle,
                             defaultValue: false),
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
        case crowned
        case strengthened(sector: Int)
        case claimed(sector: Int)
        case damaged(owner: PlayerIndex, amount: Int)
        case conquered(sector: Int)
        case eliminated(owner: PlayerIndex)
    }

    /// Lives of a sector at most, and lives of a home at the start.
    static let maximumLives = 3

    let multipliersCount: Bool
    let maxRounds: Int?
    /// `homeSector[player]`, as drawn at creation. It stays the number the home had once the player is eliminated;
    /// the sector itself then belongs to the conqueror as an ordinary sector.
    let homeSector: [Int]
    /// `owner[n]` for the sector number `n` in 1...20 (index 0 is unused); nil = neutral.
    var owner: [PlayerIndex?]
    /// `sectorLives[n]`: 0 for a neutral sector, 1...3 otherwise.
    var sectorLives: [Int]
    /// King of the Hill: the last player who hit the bull; nil = nobody.
    var king: PlayerIndex?
    /// Eliminated players, first out first.
    var eliminationOrder: [PlayerIndex] = []
    /// Round in which each eliminated player lost his home.
    var eliminationRound: [Int?]
    // Per-turn scratch state, reset by `turnStarted`.
    var turnEffects: [DartEffect] = []

    public init(configuration: GameConfiguration, random: inout SeededRandom) throws {
        let count = configuration.players.count
        // Two ring numbers per player must fit on the ring (GAMES.md §2.8): never more than eight players.
        guard Self.descriptor.players.contains(count) else {
            throw GameConfigurationError.playerCountOutOfRange(allowed: Self.descriptor.players, actual: count)
        }
        multipliersCount = configuration.options.bool("multipliersCount") ?? false
        maxRounds = configuration.options.int("maxRounds")
        // GAMES.md §12.3: blocks of two consecutive numbers; the home is the FIRST number of the block, so that two
        // homes are never adjacent and both neighbours of a home are free at the start.
        homeSector = ringLayout(playerCount: count, width: 2, rng: &random).map { $0[0] }
        owner = Array(repeating: nil, count: 21)
        sectorLives = Array(repeating: 0, count: 21)
        for (player, home) in homeSector.enumerated() {
            owner[home] = player
            sectorLives[home] = Self.maximumLives
        }
        eliminationRound = Array(repeating: nil, count: count)
    }

    public var roundLimit: Int? { maxRounds }
    public func isEliminated(_ player: PlayerIndex) -> Bool { eliminationOrder.contains(player) }

    public mutating func turnStarted(_ context: TurnContext, random: inout SeededRandom, events: inout [GameEvent]) {
        turnEffects = []
    }

    /// "`sector` is adjacent to `player`": at least one of its two ring neighbours belongs to the player right now.
    func isAdjacent(_ sector: Int, to player: PlayerIndex) -> Bool {
        let around = BoardGeometry.standard.neighbours(of: sector)
        return owner[around.anticlockwise] == player || owner[around.clockwise] == player
    }

    /// An opponent's sector can be attacked from a neighbouring sector, or from anywhere by the King.
    func canAttack(_ sector: Int, as player: PlayerIndex) -> Bool {
        king == player || isAdjacent(sector, to: player)
    }

    public mutating func dartThrown(_ hit: Hit, _ context: TurnContext, random: inout SeededRandom,
                                    events: inout [GameEvent]) -> DartVerdict {
        let p = context.currentPlayer
        if hit.isMiss { return noEffect(p, &events) }
        guard let sector = hit.number else {
            // SB or DB: the player becomes King and stays so until another player hits the bull.
            if king == p { return noEffect(p, &events) }
            king = p
            turnEffects.append(.crowned)
            events.append(.kingOfTheHill(player: p))
            return .turnContinues
        }
        let force = multipliersCount ? hit.multiplier : 1

        guard let holder = owner[sector] else {
            // Neutral: claimed by adjacency only, even for the King.
            guard isAdjacent(sector, to: p) else { return noEffect(p, &events) }
            owner[sector] = p
            sectorLives[sector] = min(Self.maximumLives, force)
            turnEffects.append(.claimed(sector: sector))
            events.append(.sectorClaimed(player: p, sector: sector))
            return .turnContinues
        }

        if holder == p {
            guard sectorLives[sector] < Self.maximumLives else { return noEffect(p, &events) }
            sectorLives[sector] = min(Self.maximumLives, sectorLives[sector] + force)
            turnEffects.append(.strengthened(sector: sector))
            events.append(.sectorStrengthened(player: p, sector: sector, lives: sectorLives[sector]))
            return .turnContinues
        }

        guard canAttack(sector, as: p) else { return noEffect(p, &events) }
        let left = sectorLives[sector] - force
        if left > 0 {
            sectorLives[sector] = left
            turnEffects.append(.damaged(owner: holder, amount: force))
            events.append(.sectorDamaged(player: p, sector: sector, livesLeft: left))
            return .turnContinues
        }
        // Conquest: the sector changes hands with one life; the excess of force is lost.
        owner[sector] = p
        sectorLives[sector] = 1
        events.append(.sectorConquered(player: p, sector: sector, from: holder))
        guard sector == homeSector[holder] else {
            turnEffects.append(.conquered(sector: sector))
            return .turnContinues
        }
        // The home falls: its owner is out, the rest of his territory passes to the conqueror with its lives,
        // and his crown, if he had it, is vacant.
        for other in 1...20 where owner[other] == holder {
            owner[other] = p
        }
        if king == holder { king = nil }
        eliminationOrder.append(holder)
        eliminationRound[holder] = context.round
        turnEffects.append(.eliminated(owner: holder))
        events.append(.playerEliminated(player: holder, by: p))
        return eliminationOrder.count == homeSector.count - 1 ? .gameFinished(.lastPlayerStanding) : .turnContinues
    }

    private mutating func noEffect(_ player: PlayerIndex, _ events: inout [GameEvent]) -> DartVerdict {
        turnEffects.append(.none)
        events.append(.noEffect(player: player))
        return .turnContinues
    }

    /// Nothing happens at the close of a turn: no bust, no turn total (GAMES.md §12.5).
    public mutating func turnClosed(_ context: TurnContext, events: inout [GameEvent]) {}

    /// Sectors of a player, in ascending number.
    func sectors(of player: PlayerIndex) -> [Int] {
        (1...20).filter { owner[$0] == player }
    }

    /// Total of the lives of a player's sectors.
    func totalLives(of player: PlayerIndex) -> Int {
        sectors(of: player).reduce(0) { $0 + sectorLives[$1] }
    }

    /// Players in play by (1) total lives, (2) number of sectors, both descending; then the eliminated ones,
    /// last out first (GAMES.md §12.6).
    public func ranks() -> [Int] {
        Ranking.ranks(keys: homeSector.indices.map { player in
            if let order = eliminationOrder.firstIndex(of: player) { return [1, -order] }
            return [0, -totalLives(of: player), -sectors(of: player).count]
        })
    }
}
