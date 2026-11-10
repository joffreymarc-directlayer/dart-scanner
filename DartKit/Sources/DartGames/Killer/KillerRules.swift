import DartCore

/// GAMES.md §5. Killer in four levels: three, two or one fixed adjacent numbers per player (`easy`, `medium`,
/// `hard`), or one number that is redrawn at the start of each of the player's own turns (`expert`).
/// The scoreboard, the captions and the highlights are in `KillerPresentation.swift`.
public struct KillerRules: TurnBasedRules {
    public static let descriptor = GameDescriptor(
        id: .killer,
        name: LocalizedText(verbatim: "Killer"),
        shortName: LocalizedText(verbatim: "Killer"),
        summary: LocalizedText(fr: "4 niveaux · 2 à 8 joueurs", en: "4 levels · 2 to 8 players"),
        pitch: LocalizedText(fr: "Touchez votre zone pour devenir Killer, puis visez celles des autres : le dernier en vie gagne.",
                             en: "Hit your own zone to become a Killer, then take the others out: last one alive wins."),
        players: 2...8,
        options: [
            OptionDescriptor(
                key: "level",
                label: LocalizedText(fr: "Niveau", en: "Level"),
                kind: .choice([
                    OptionChoice("easy", label: LocalizedText(fr: "Facile", en: "Easy"),
                                 detail: LocalizedText(fr: "3 cases adjacentes · 6 joueurs max", en: "3 adjacent numbers · 6 players max"),
                                 players: 2...6,
                                 unavailableNote: LocalizedText(fr: "6 joueurs maximum en Facile", en: "6 players maximum in Easy"),
                                 illustration: .sectors(count: 3, moving: false)),
                    OptionChoice("medium", label: LocalizedText(fr: "Intermédiaire", en: "Medium"),
                                 detail: LocalizedText(fr: "2 cases adjacentes", en: "2 adjacent numbers"),
                                 illustration: .sectors(count: 2, moving: false)),
                    OptionChoice("hard", label: LocalizedText(fr: "Difficile", en: "Hard"),
                                 detail: LocalizedText(fr: "1 seule case", en: "1 number only"),
                                 illustration: .sectors(count: 1, moving: false)),
                    OptionChoice("expert", label: LocalizedText(verbatim: "Expert"),
                                 detail: LocalizedText(fr: "1 case qui change à chaque tour", en: "1 number that changes every turn"),
                                 illustration: .sectors(count: 1, moving: true)),
                ]),
                defaultValue: "easy"),
            OptionDescriptor(key: "lives", label: LocalizedText(fr: "Vies", en: "Lives"),
                             kind: .stepper(1...9), defaultValue: 3),
            OptionDescriptor(key: "armingHits",
                             label: LocalizedText(fr: "Touches pour devenir Killer", en: "Hits to become a Killer"),
                             kind: .stepper(1...5), defaultValue: 3),
            OptionDescriptor(key: "selfHitPenalty",
                             label: LocalizedText(fr: "Pénalité sur sa propre zone", en: "Penalty on your own zone"),
                             help: LocalizedText(fr: "Un Killer qui touche sa zone perd une vie.", en: "A Killer who hits their own zone loses a life."),
                             kind: .toggle, defaultValue: false, isAdvanced: true),
            OptionDescriptor(key: "maxRounds", label: LocalizedText(fr: "Manches maximum", en: "Round limit"),
                             kind: .optionalStepper(1...99, nullLabel: LocalizedText(fr: "Sans limite", en: "No limit")),
                             defaultValue: 15, isAdvanced: true),
        ],
        playStyle: .board,
        origin: .dartsee,
        priority: 0)

    // MARK: Options

    /// The four levels of GAMES.md §5.2.
    enum Level: String, Sendable {
        case easy, medium, hard, expert

        /// Number of adjacent ring sectors in the zone of a player.
        var width: Int {
            switch self {
            case .easy: return 3
            case .medium: return 2
            case .hard, .expert: return 1
            }
        }
    }

    /// What one dart of the current turn did. It only feeds the dart captions: no rule reads it back.
    enum DartEffect: Hashable, Sendable {
        case none
        case arming(progress: Int)
        case becameKiller
        case lifeTaken(from: PlayerIndex)
        case eliminated(PlayerIndex)
        case ownLifeLost
        case selfEliminated
    }

    let level: Level
    /// Lives of every player at the start (`lives`).
    let startingLives: Int
    /// Hits on one's own zone needed to become a Killer (`armingHits`).
    let armingHits: Int
    /// A Killer who hits their own zone loses a life (`selfHitPenalty`).
    let selfHitPenalty: Bool
    let maxRounds: Int?

    // MARK: State (GAMES.md §5.3)

    /// `zones[player]`: the numbers of the player, clockwise. An eliminated player keeps the last zone they had;
    /// it is inert, and at the `expert` level its number may be drawn again by a player alive.
    var zones: [[Int]]
    var lives: [Int]
    var armingProgress: [Int]
    var kills: [Int]
    /// 0 for the first player eliminated, 1 for the second…; nil while the player is alive.
    var eliminationOrder: [Int?]
    /// Round of the elimination and round of the last arming hit: results screen only.
    var eliminatedInRound: [Int?]
    var becameKillerInRound: [Int?]
    /// Per-turn scratch state: the effect of each dart of the current turn. After a game ended at the round limit
    /// it still holds the last turn while the kernel's volley is empty (ARCHITECTURE.md §4.7).
    var turnEffects: [DartEffect] = []

    public init(configuration: GameConfiguration, random: inout SeededRandom) throws {
        let descriptor = Self.descriptor
        let count = configuration.players.count
        // The kernel has already validated the configuration; a rule built directly gets the same refusals
        // (a player count out of range, `easy` with more than six players) instead of a trap in `ringLayout`.
        if let issue = descriptor.validate(options: configuration.options, playerCount: count).first {
            throw issue
        }
        let options = descriptor.normalized(configuration.options)
        guard let level = options.string("level").flatMap(Level.init(rawValue:)), count * level.width <= 20 else {
            throw GameConfigurationError.invalidOptionValue(key: "level")
        }
        guard let startingLives = options.int("lives") else {
            throw GameConfigurationError.invalidOptionValue(key: "lives")
        }
        guard let armingHits = options.int("armingHits") else {
            throw GameConfigurationError.invalidOptionValue(key: "armingHits")
        }
        guard let selfHitPenalty = options.bool("selfHitPenalty") else {
            throw GameConfigurationError.invalidOptionValue(key: "selfHitPenalty")
        }
        self.level = level
        self.startingLives = startingLives
        self.armingHits = armingHits
        self.selfHitPenalty = selfHitPenalty
        // `.null` is "no limit"; any other value is an integer of the schema's range.
        self.maxRounds = options.int("maxRounds")

        // Initial draw (GAMES.md §5.3): 1 + (20 - players × width) + (players - 1) draws.
        zones = ringLayout(playerCount: count, width: level.width, rng: &random)
        lives = Array(repeating: startingLives, count: count)
        armingProgress = Array(repeating: 0, count: count)
        kills = Array(repeating: 0, count: count)
        eliminationOrder = Array(repeating: nil, count: count)
        eliminatedInRound = Array(repeating: nil, count: count)
        becameKillerInRound = Array(repeating: nil, count: count)
    }

    // MARK: Queries

    public var roundLimit: Int? { maxRounds }

    public func isEliminated(_ player: PlayerIndex) -> Bool {
        eliminationOrder.indices.contains(player) && eliminationOrder[player] != nil
    }

    /// A player is a Killer once `armingProgress == armingHits`, and stays one to the end.
    func isKiller(_ player: PlayerIndex) -> Bool {
        armingProgress[player] >= armingHits
    }

    /// The player ALIVE whose zone holds `number`, if any; there is at most one. Nil for a free number and for
    /// the zone of an eliminated player, which is inert.
    func owner(of number: Int) -> PlayerIndex? {
        zones.indices.first { !isEliminated($0) && zones[$0].contains(number) }
    }

    var aliveCount: Int {
        eliminationOrder.filter { $0 == nil }.count
    }

    // MARK: Turn flow

    public mutating func turnStarted(_ context: TurnContext, random: inout SeededRandom, events: inout [GameEvent]) {
        turnEffects = []
        // Expert redraw (GAMES.md §5.4): at the start of each turn of the player from their second turn on.
        // A player's k-th turn is always in round k, so the first turn is the one of round 1; the creation call
        // is in round 1 too and draws nothing.
        let player = context.currentPlayer
        guard level == .expert, context.round > 1, !isEliminated(player), let previous = zones[player].first else { return }
        var taken: Set<Int> = [previous]
        for other in zones.indices where other != player && !isEliminated(other) {
            taken.formUnion(zones[other])
        }
        // Candidates in ascending order: 1...20 without the numbers of the other players alive and without the
        // number the player had during the previous turn. At least 12 are left.
        let candidates = (1...20).filter { !taken.contains($0) }
        guard !candidates.isEmpty else { return }
        let number = candidates[random.nextInt(below: candidates.count)]
        zones[player] = [number]
        events.append(.zoneChanged(player: player, zone: [number]))
    }

    public mutating func dartThrown(_ hit: Hit, _ context: TurnContext, random: inout SeededRandom,
                                    events: inout [GameEvent]) -> DartVerdict {
        let player = context.currentPlayer
        // The multiplier is ignored: single, double and treble of a number are ONE hit. The bull plays no part.
        guard let number = hit.number, let owner = owner(of: number), !isEliminated(player) else {
            return noEffect(player, &events)
        }

        if owner == player {
            if !isKiller(player) {
                armingProgress[player] += 1
                events.append(.armingHit(player: player, progress: armingProgress[player]))
                if isKiller(player) {
                    // Effective at once, for the next darts of the same turn.
                    becameKillerInRound[player] = context.round
                    events.append(.becameKiller(player: player))
                    turnEffects.append(.becameKiller)
                } else {
                    turnEffects.append(.arming(progress: armingProgress[player]))
                }
                return .turnContinues
            }
            guard selfHitPenalty else { return noEffect(player, &events) }
            lives[player] -= 1
            events.append(.lifeLost(player: player, by: player, livesLeft: lives[player]))
            guard lives[player] == 0 else {
                turnEffects.append(.ownLifeLost)
                return .turnContinues
            }
            // Self-elimination: no kill is counted, and the turn is closed unless the game ends.
            eliminate(player, round: context.round)
            events.append(.playerEliminated(player: player, by: player))
            turnEffects.append(.selfEliminated)
            return aliveCount == 1 ? .gameFinished(.lastPlayerStanding) : .turnClosed
        }

        // The zone of an opponent alive. A Killer may attack any of them, armed or not.
        guard isKiller(player) else { return noEffect(player, &events) }
        lives[owner] -= 1
        events.append(.lifeLost(player: owner, by: player, livesLeft: lives[owner]))
        guard lives[owner] == 0 else {
            turnEffects.append(.lifeTaken(from: owner))
            return .turnContinues
        }
        eliminate(owner, round: context.round)
        kills[player] += 1
        events.append(.playerEliminated(player: owner, by: player))
        turnEffects.append(.eliminated(owner))
        return aliveCount == 1 ? .gameFinished(.lastPlayerStanding) : .turnContinues
    }

    public mutating func turnClosed(_ context: TurnContext, events: inout [GameEvent]) {}

    private mutating func noEffect(_ player: PlayerIndex, _ events: inout [GameEvent]) -> DartVerdict {
        events.append(.noEffect(player: player))
        turnEffects.append(.none)
        return .turnContinues
    }

    /// Immediate, even in the middle of the attacker's turn (GAMES.md §5.6).
    private mutating func eliminate(_ player: PlayerIndex, round: Int) {
        eliminationOrder[player] = eliminationOrder.count - aliveCount
        eliminatedInRound[player] = round
    }

    // MARK: Ranking (GAMES.md §5.6)

    /// Players alive first, by lives, then kills, then arming progress, all descending; then the eliminated
    /// players, the last one eliminated first.
    public func ranks() -> [Int] {
        Ranking.ranks(keys: zones.indices.map { player in
            if let order = eliminationOrder[player] { return [1, -order] }
            return [0, -lives[player], -kills[player], -armingProgress[player]]
        })
    }
}
