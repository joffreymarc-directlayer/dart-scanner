import Foundation

/// A logical field of a game, named as in GAMES.md ("remaining", "lives", "zone", "marks").
/// Used by the test vectors, by `GameMatch.effectKey(for:)` and by statistics. Never shown as is.
public enum FactValue: Hashable, Sendable {
    case int(Int)
    case bool(Bool)
    case text(String)
    /// A list of numbers in a meaningful order: a Killer zone, the Cricket targets.
    case ints([Int])
    /// Number → value: Cricket marks by target (bull = 25), Conqueror lives by sector.
    case map([Int: Int])
    /// Rows of numbers in a meaningful order: the five Radar targets, one row `[x, y, radius, hitPoints]` each.
    /// No literal syntax: write `.table([[...], [...]])`.
    case table([[Int]])
}

extension FactValue: ExpressibleByIntegerLiteral, ExpressibleByBooleanLiteral, ExpressibleByStringLiteral,
                     ExpressibleByArrayLiteral, ExpressibleByDictionaryLiteral {
    public init(integerLiteral value: Int) { self = .int(value) }
    public init(booleanLiteral value: Bool) { self = .bool(value) }
    public init(stringLiteral value: String) { self = .text(value) }
    public init(arrayLiteral elements: Int...) { self = .ints(elements) }
    public init(dictionaryLiteral elements: (Int, Int)...) {
        self = .map(Dictionary(elements, uniquingKeysWith: { _, last in last }))
    }
}

/// Meaning of a highlighted zone for the CURRENT player (GAMES.md §2.9).
public enum HighlightRole: String, Codable, Sendable {
    /// Aim here: it makes the player progress, score or attack.
    case target
    /// Useful, but less than a target.
    case secondary
    /// Belongs to the player, no useful effect right now.
    case own
    /// Hitting it costs the player something.
    case avoid
    /// Belongs to an opponent, shown for information.
    case opponent
    /// Dead zone: no effect for anyone.
    case inactive
}

/// Small symbol drawn on a highlighted zone.
public enum BoardMarker: String, Codable, Sendable {
    /// Conqueror home sector.
    case home
    /// Conqueror King of the Hill (on the bull).
    case crown
    /// Fight heal number.
    case heal
}

/// One highlighted zone: (zone, role, optional owner), plus an optional label, strength and marker (GAMES.md §2.9).
/// The zone is a set of beds or a free disc (`BoardZone.disc`, Radar targets).
public struct BoardHighlight: Hashable, Sendable {
    public var zone: BoardZone
    public var role: HighlightRole
    /// Owner of the zone, when it has one: the zone is drawn in that player's colour.
    public var owner: PlayerIndex?
    /// Short label drawn on the zone: "+3", "+2r", "+10" (Radar), "1" (Golf).
    public var label: String?
    /// Hit points 1...3 drawn as pips in the zone: Conqueror sector lives, hit points left of a Radar target.
    public var strength: Int?
    public var marker: BoardMarker?

    public init(zone: BoardZone, role: HighlightRole, owner: PlayerIndex? = nil, label: String? = nil,
                strength: Int? = nil, marker: BoardMarker? = nil) {
        self.zone = zone
        self.role = role
        self.owner = owner
        self.label = label
        self.strength = strength
        self.marker = marker
    }
}

/// Colour intent of a caption or a badge. The UI maps it to DESIGN.md tokens.
public enum Tone: String, Codable, Sendable {
    case neutral, positive, negative, accent
}

/// The big value of a scoreboard row: "187", or "3" with the unit "vies".
public struct ScoreValue: Hashable, Sendable {
    public var text: String
    public var unit: LocalizedText?

    public init(_ text: String, unit: LocalizedText? = nil) {
        self.text = text
        self.unit = unit
    }

    public init(_ value: Int, unit: LocalizedText? = nil) {
        self.init(String(value), unit: unit)
    }
}

public struct Badge: Hashable, Sendable {
    public var text: LocalizedText
    public var tone: Tone

    public init(_ text: LocalizedText, tone: Tone = .neutral) {
        self.text = text
        self.tone = tone
    }
}

/// A small gauge on a scoreboard row.
public struct Meter: Hashable, Sendable {
    public enum Style: String, Codable, Sendable {
        /// Discrete dots: Killer arming hits, lives up to 9.
        case pips
        /// Continuous bar: Around-the-Clock progress, Fight life bar.
        case bar
    }
    public var value: Int
    public var maximum: Int
    public var style: Style

    public init(value: Int, maximum: Int, style: Style) {
        self.value = value
        self.maximum = maximum
        self.style = style
    }
}

/// One line of the scoreboard. `rows[i]` is the player of index `i`.
public struct PlayerRow: Hashable, Sendable {
    public var player: PlayerIndex
    /// Main value: remaining score, lives, points.
    public var primary: ScoreValue
    /// Secondary line: "Dernière volée : 45", "17 · 3 · 19".
    public var detail: LocalizedText?
    /// Short labels: "Killer", "À ouvrir", "Roi".
    public var badges: [Badge]
    public var meter: Meter?
    /// Provisional rank during the game, final rank once finished (GAMES.md §2.7). Filled by the engine.
    public var rank: Int
    public var isEliminated: Bool
    /// Lines of the results screen for this player: "2 éliminations", "Éliminée manche 9".
    public var resultLines: [LocalizedText]
    /// Logical fields of GAMES.md for this player.
    public var facts: [String: FactValue]

    public init(player: PlayerIndex, primary: ScoreValue, detail: LocalizedText? = nil, badges: [Badge] = [],
                meter: Meter? = nil, rank: Int = 1, isEliminated: Bool = false,
                resultLines: [LocalizedText] = [], facts: [String: FactValue] = [:]) {
        self.player = player
        self.primary = primary
        self.detail = detail
        self.badges = badges
        self.meter = meter
        self.rank = rank
        self.isEliminated = isEliminated
        self.resultLines = resultLines
        self.facts = facts
    }
}

/// What the game says about one dart of the current turn: "60", "Tom −1 vie", "BUST".
public struct DartCaption: Hashable, Sendable {
    public var text: LocalizedText
    public var tone: Tone

    public init(_ text: LocalizedText, tone: Tone = .neutral) {
        self.text = text
        self.tone = tone
    }
}

/// One thrown dart of the current turn.
public struct DartSlot: Hashable, Sendable {
    public var hit: Hit
    public var caption: DartCaption?

    public init(hit: Hit, caption: DartCaption? = nil) {
        self.hit = hit
        self.caption = caption
    }
}

/// The current turn.
public struct TurnSnapshot: Hashable, Sendable {
    /// Darts thrown so far, in order (0...capacity).
    public var darts: [DartSlot]
    /// Darts per turn: 3.
    public var capacity: Int
    /// "Volée : 117", "BUST".
    public var summary: LocalizedText?
    /// Advice for the next dart: "Pour finir : D12".
    public var hint: LocalizedText?

    public init(darts: [DartSlot] = [], capacity: Int = 3, summary: LocalizedText? = nil, hint: LocalizedText? = nil) {
        self.darts = darts
        self.capacity = capacity
        self.summary = summary
        self.hint = hint
    }
}

/// Marks table of Cricket: one column per target, one row per player.
public struct ScoreGrid: Hashable, Sendable {
    /// Column titles: "20", "19", …, "B".
    public var columns: [String]
    /// `marks[player][column]`, 0...3.
    public var marks: [[Int]]
    /// True for the columns closed by every player.
    public var dead: [Bool]

    public init(columns: [String], marks: [[Int]], dead: [Bool]) {
        self.columns = columns
        self.marks = marks
        self.dead = dead
    }
}

/// Everything the UI needs to draw ANY game, without knowing which one it is.
/// A pure function of (configuration, journal); recomputed after every input.
public struct GameSnapshot: Hashable, Sendable {
    public var gameID: GameID
    /// Title of the play screen: "Killer", "501".
    public var title: LocalizedText
    /// Variant shown next to the round counter: "Facile", "Double out".
    public var variant: LocalizedText?
    /// Objective of the round, when the game has one: "Cible : D7", "Numéro 4".
    public var objective: LocalizedText?
    public var phase: GamePhase
    public var currentPlayer: PlayerIndex
    /// 1-based.
    public var round: Int
    /// For the "4 / 15" header; nil = no limit.
    public var roundLimit: Int?
    public var turn: TurnSnapshot
    /// One row per player, in playing order.
    public var players: [PlayerRow]
    /// Zones to draw for the current player. Empty once finished.
    public var highlights: [BoardHighlight]
    public var grid: ScoreGrid?
    public var finishReason: FinishReason?
    /// Rank of each player, by player index, starting at 1, shared on ties ("1, 1, 3"). Valid at any time.
    public var ranks: [Int]
    /// Sentence of the results screen: "Dernière en vie, avec 2 vies restantes."
    public var outcome: LocalizedText?
    /// Headline naming the winner when it is NOT a player (GAMES.md §2.7): "Le camp A gagne", "Match nul"
    /// (Football). The results screen shows it in place of the winners' names and the score caller says it as
    /// it is. Nil for every game whose winners are the players ranked first, and nil before the game is finished.
    public var winnerTitle: LocalizedText?
    /// Game-level logical fields of GAMES.md: "targets", "king".
    public var facts: [String: FactValue]

    public init(gameID: GameID, title: LocalizedText, variant: LocalizedText? = nil, objective: LocalizedText? = nil,
                phase: GamePhase, currentPlayer: PlayerIndex, round: Int, roundLimit: Int?, turn: TurnSnapshot,
                players: [PlayerRow], highlights: [BoardHighlight] = [], grid: ScoreGrid? = nil,
                finishReason: FinishReason? = nil, ranks: [Int], outcome: LocalizedText? = nil,
                winnerTitle: LocalizedText? = nil, facts: [String: FactValue] = [:]) {
        self.gameID = gameID
        self.title = title
        self.variant = variant
        self.objective = objective
        self.phase = phase
        self.currentPlayer = currentPlayer
        self.round = round
        self.roundLimit = roundLimit
        self.turn = turn
        self.players = players
        self.highlights = highlights
        self.grid = grid
        self.finishReason = finishReason
        self.ranks = ranks
        self.outcome = outcome
        self.winnerTitle = winnerTitle
        self.facts = facts
    }

    /// Players ranked first; several on a tie. Meaningful once `phase == .finished`.
    public var winners: [PlayerIndex] {
        ranks.indices.filter { ranks[$0] == 1 }
    }
}
