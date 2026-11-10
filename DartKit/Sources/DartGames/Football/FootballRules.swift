import DartCore

/// GAMES.md §14. Two sides and one ball on a one-dimensional pitch: the half of the board that a dart hits
/// pushes the ball that way. Side A (players of even index) defends the left goal and attacks to the right.
/// The descriptor is the one written by lot F0, word for word.
public struct FootballRules: TurnBasedRules {
    public static let descriptor = GameDescriptor(
        id: .football,
        name: LocalizedText(verbatim: "Football"),
        shortName: LocalizedText(verbatim: "Football"),
        summary: LocalizedText(fr: "Deux camps, un ballon", en: "Two sides, one ball"),
        pitch: LocalizedText(fr: "Deux camps, un ballon : chaque fléchette pousse le ballon du côté de la cible où elle se plante. Amenez-le dans le but d'en face.",
                             en: "Two sides, one ball: every dart pushes the ball towards the side of the board it lands on. Get it into the opposite goal."),
        players: 2...8,
        options: [
            OptionDescriptor(key: "fieldLength", label: LocalizedText(fr: "Longueur du terrain", en: "Field length"),
                             kind: .stepper(3...8),
                             defaultValue: 4),
            OptionDescriptor(key: "goalsToWin", label: LocalizedText(fr: "Buts pour gagner", en: "Goals to win"),
                             kind: .stepper(1...9),
                             defaultValue: 3),
            OptionDescriptor(key: "maxRounds", label: LocalizedText(fr: "Manches maximum", en: "Round limit"),
                             kind: .optionalStepper(1...99, nullLabel: LocalizedText(fr: "Sans limite", en: "No limit")),
                             defaultValue: 10, isAdvanced: true),
        ],
        playStyle: .board,
        origin: .dartsee,
        priority: 1)

    /// The nine sectors of each half of the board, clockwise (GAMES.md §2.1). The 20 and the 3 straddle the
    /// vertical axis and belong to neither half.
    static let rightHalf = [1, 18, 4, 13, 6, 10, 15, 2, 17]
    static let leftHalf = [19, 7, 16, 8, 11, 14, 9, 12, 5]

    /// What one dart of the current turn did, for its caption.
    enum DartEffect: Hashable, Sendable {
        case none
        /// The requested move, signed (positive = towards the right).
        case moved(Int)
        case goal(ownGoal: Bool)
    }

    let goalsToWin: Int
    let maxRounds: Int?
    /// Steps of one push of a single, by side `[A, B]`: proportional to the size of the other side.
    let step: [Int]
    /// The goal line that B defends is at `+goalDistance`, the one that A defends at `−goalDistance`.
    let goalDistance: Int
    /// Position of the ball, from `−goalDistance` to `+goalDistance`; 0 is the centre spot.
    var ball = 0
    /// Goals of side A and of side B.
    var sideGoals = [0, 0]
    /// Goals each player scored for their own side (own goals are credited to nobody).
    var goalsScored: [Int]
    /// Per-turn scratch state, reset by `turnStarted`.
    var turnEffects: [DartEffect] = []

    public init(configuration: GameConfiguration, random: inout SeededRandom) throws {
        // The kernel has validated the configuration already; a rule built on its own is as strict.
        let descriptor = Self.descriptor
        let count = configuration.players.count
        if let issue = descriptor.validate(options: configuration.options, playerCount: count).first { throw issue }
        let options = descriptor.normalized(configuration.options)
        guard let fieldLength = options.int("fieldLength") else { throw GameConfigurationError.invalidOptionValue(key: "fieldLength") }
        guard let goalsToWin = options.int("goalsToWin") else { throw GameConfigurationError.invalidOptionValue(key: "goalsToWin") }
        self.goalsToWin = goalsToWin
        // `.null` means no round limit.
        maxRounds = options.int("maxRounds")
        // Side A has the extra player when the count is odd.
        let sizeA = (count + 1) / 2, sizeB = count / 2
        let divisor = Self.greatestCommonDivisor(sizeA, sizeB)
        step = [sizeB / divisor, sizeA / divisor]
        goalDistance = fieldLength * step[1]
        goalsScored = Array(repeating: 0, count: count)
    }

    /// Side of a player: 0 = A (even index), 1 = B (odd index).
    static func side(of player: PlayerIndex) -> Int { player % 2 }

    public var roundLimit: Int? { maxRounds }
    public func isEliminated(_ player: PlayerIndex) -> Bool { false }

    public mutating func turnStarted(_ context: TurnContext, random: inout SeededRandom, events: inout [GameEvent]) {
        turnEffects = []
    }

    public mutating func dartThrown(_ hit: Hit, _ context: TurnContext, random: inout SeededRandom,
                                    events: inout [GameEvent]) -> DartVerdict {
        let p = context.currentPlayer
        let side = Self.side(of: p)
        let unit = step[side]
        // Side A attacks to the right, side B to the left.
        let attack = side == 0 ? 1 : -1

        let move: Int
        switch hit.bed {
        case .miss:
            return noEffect(p, &events)
        case .innerBull:
            // A goal at once for the thrower's side, wherever the ball is; the ball does not "move".
            return goal(for: side, by: p, &events)
        case .outerBull:
            move = 2 * unit * attack
        case .single, .double, .treble:
            // The half that is hit gives the direction, whoever throws.
            if let number = hit.number, Self.rightHalf.contains(number) {
                move = hit.multiplier * unit
            } else if let number = hit.number, Self.leftHalf.contains(number) {
                move = -hit.multiplier * unit
            } else {
                // The 20 and the 3: the halfway line.
                return noEffect(p, &events)
            }
        }

        // The ball stops on the line.
        ball = max(-goalDistance, min(goalDistance, ball + move))
        events.append(.ballMoved(player: p, by: move, ball: ball))
        if ball == goalDistance { return goal(for: 0, by: p, &events) }
        if ball == -goalDistance { return goal(for: 1, by: p, &events) }
        turnEffects.append(.moved(move))
        return .turnContinues
    }

    public mutating func turnClosed(_ context: TurnContext, events: inout [GameEvent]) {}

    /// The same rank for every player of a side: goals, then how far the ball is in the opposite half.
    public func ranks() -> [Int] {
        Ranking.ranks(keys: goalsScored.indices.map { player in
            let side = Self.side(of: player)
            return [-sideGoals[side], -advantage(of: side)]
        })
    }

    public func presentation(_ context: TurnContext) -> RulesPresentation {
        let side = Self.side(of: context.currentPlayer)
        let attacked = side == 0 ? Self.rightHalf : Self.leftHalf
        let defended = side == 0 ? Self.leftHalf : Self.rightHalf
        let highlights = attacked.map { BoardHighlight(zone: .sector($0), role: .target) }
            + defended.map { BoardHighlight(zone: .sector($0), role: .avoid) }
            + [BoardHighlight(zone: .bull, role: .target)]
        return RulesPresentation(
            title: Self.descriptor.name,
            objective: LocalizedText(verbatim: score),
            rows: goalsScored.indices.map { row($0) },
            dartCaptions: zip(context.darts, turnEffects).map { _, effect in caption(effect, side: side) },
            highlights: highlights,
            outcome: outcome(),
            winnerTitle: winnerTitle(),
            facts: ["ball": .int(ball), "sideGoals": .ints(sideGoals), "goalDistance": .int(goalDistance), "step": .ints(step)])
    }

    // MARK: Private

    private static func greatestCommonDivisor(_ a: Int, _ b: Int) -> Int {
        var (a, b) = (a, b)
        while b != 0 { (a, b) = (b, a % b) }
        return max(a, 1)
    }

    private mutating func noEffect(_ player: PlayerIndex, _ events: inout [GameEvent]) -> DartVerdict {
        turnEffects.append(.none)
        events.append(.noEffect(player: player))
        return .turnContinues
    }

    /// Side `scoring` scores, on a dart of `player`: kick-off from the centre spot, and victory at `goalsToWin`.
    private mutating func goal(for scoring: Int, by player: PlayerIndex, _ events: inout [GameEvent]) -> DartVerdict {
        let ownGoal = scoring != Self.side(of: player)
        sideGoals[scoring] += 1
        if !ownGoal { goalsScored[player] += 1 }
        ball = 0
        turnEffects.append(.goal(ownGoal: ownGoal))
        events.append(.goalScored(player: player, side: scoring, goals: sideGoals[scoring], ownGoal: ownGoal))
        return sideGoals[scoring] >= goalsToWin ? .gameFinished(.victory) : .turnContinues
    }

    /// Territorial advantage of a side: `ball` for A, `−ball` for B.
    private func advantage(of side: Int) -> Int { side == 0 ? ball : -ball }

    /// "A 2 – 1 B".
    private var score: String { "A \(sideGoals[0]) – \(sideGoals[1]) B" }

    /// Side ranked first: 0 or 1; nil on a draw.
    private var leadingSide: Int? {
        let keys = [0, 1].map { [-sideGoals[$0], -advantage(of: $0)] }
        if keys[0] == keys[1] { return nil }
        return keys[0].lexicographicallyPrecedes(keys[1]) ? 0 : 1
    }

    private func row(_ player: PlayerIndex) -> PlayerRow {
        let side = Self.side(of: player)
        let goals = sideGoals[side]
        let scored = LocalizedText.counted(goalsScored[player], fr: (one: "but marqué", other: "buts marqués"),
                                           en: (one: "goal scored", other: "goals scored"))
        return PlayerRow(
            player: player,
            primary: ScoreValue(goals, unit: LocalizedText(fr: goals <= 1 ? "but" : "buts", en: goals == 1 ? "goal" : "goals")),
            detail: scored,
            badges: [Badge(LocalizedText(verbatim: side == 0 ? "A" : "B"))],
            // Progress of the ball towards the goal this player attacks.
            meter: Meter(value: goalDistance + advantage(of: side), maximum: 2 * goalDistance, style: .bar),
            resultLines: [scored],
            facts: ["side": .int(side), "goalsScored": .int(goalsScored[player])])
    }

    /// Caption of a dart, as the thrower of side `side` sees it.
    private func caption(_ effect: DartEffect, side: Int) -> DartCaption {
        switch effect {
        case .none:
            return DartCaption(LocalizedText(fr: "Sans effet", en: "No effect"))
        case .moved(let move):
            let towardsAttackedGoal = (move > 0) == (side == 0)
            return DartCaption(LocalizedText(verbatim: "\(move > 0 ? "→" : "←") \(abs(move))"),
                               tone: towardsAttackedGoal ? .positive : .negative)
        case .goal(ownGoal: false):
            return DartCaption(LocalizedText(fr: "But !", en: "Goal!"), tone: .positive)
        case .goal(ownGoal: true):
            return DartCaption(LocalizedText(fr: "Contre son camp", en: "Own goal"), tone: .negative)
        }
    }

    /// The winner is a side, not a player (GAMES.md §14.7). The kernel only lets it out once the game is finished.
    private func winnerTitle() -> LocalizedText {
        switch leadingSide {
        case 0?: return LocalizedText(fr: "Le camp A gagne", en: "Side A wins")
        case 1?: return LocalizedText(fr: "Le camp B gagne", en: "Side B wins")
        default: return LocalizedText(fr: "Match nul", en: "It's a draw")
        }
    }

    private func outcome() -> LocalizedText {
        if sideGoals[0] != sideGoals[1] {
            return LocalizedText(fr: "Score final : \(score).", en: "Final score: \(score).")
        }
        guard let leader = leadingSide else {
            return LocalizedText(fr: "\(score), ballon au centre.", en: "\(score), ball on the centre spot.")
        }
        let name = leader == 0 ? "A" : "B"
        return LocalizedText(fr: "\(score) : le camp \(name) tient le ballon dans la moitié adverse.",
                             en: "\(score): side \(name) holds the ball in the opposite half.")
    }
}
