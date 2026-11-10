import Foundation

/// Which template the play screen uses (DESIGN.md §4).
public enum PlayStyle: String, Codable, Sendable {
    /// The game is read on the board (zones, targets): Killer template.
    case board
    /// The game is read on a big number: X01 template.
    case score
}

public enum GameOrigin: String, Codable, Sendable {
    case dartsee, classic
}

/// Everything the application knows about a game without creating one: the home card, the setup screen, validation.
public struct GameDescriptor: Hashable, Sendable, Identifiable {
    public var id: GameID
    /// Full name: "Tour de l'horloge" / "Around the Clock".
    public var name: LocalizedText
    /// Name on the home card: "Horloge" / "Clock".
    public var shortName: LocalizedText
    /// Second line of the home card: "4 niveaux · 2 à 8 joueurs".
    public var summary: LocalizedText
    /// One-sentence rule shown on the setup screen (GAMES.md §n.1, "En une ligne").
    public var pitch: LocalizedText
    /// Overall player range; a choice may narrow it (`OptionChoice.players`).
    public var players: ClosedRange<Int>
    public var options: [OptionDescriptor]
    public var playStyle: PlayStyle
    public var origin: GameOrigin
    /// 0 = P0, 1 = P1, 2 = P2 (GAMES.md §1).
    public var priority: Int
    /// "Dépend de la position : oui" in the game's sheet (GAMES.md §2.13): the engine reads the impact point of a
    /// dart, not only its hit. The UI then draws the board at regulation proportions and groups doubtful
    /// detections on (hit, position). True for Radar only.
    public var dependsOnPosition: Bool
    /// True (default): the UI asks for a confirmation before ending a turn of fewer than three darts.
    /// False when stopping early is a normal move of the game (Golf, GAMES.md §16.5).
    public var confirmsShortTurn: Bool

    public init(id: GameID, name: LocalizedText, shortName: LocalizedText, summary: LocalizedText, pitch: LocalizedText,
                players: ClosedRange<Int>, options: [OptionDescriptor], playStyle: PlayStyle,
                origin: GameOrigin, priority: Int, dependsOnPosition: Bool = false, confirmsShortTurn: Bool = true) {
        self.id = id
        self.name = name
        self.shortName = shortName
        self.summary = summary
        self.pitch = pitch
        self.players = players
        self.options = options
        self.playStyle = playStyle
        self.origin = origin
        self.priority = priority
        self.dependsOnPosition = dependsOnPosition
        self.confirmsShortTurn = confirmsShortTurn
    }

    public func option(_ key: String) -> OptionDescriptor? {
        options.first { $0.key == key }
    }

    /// Every option at its default value.
    public var defaultOptions: GameOptions {
        GameOptions(Dictionary(uniqueKeysWithValues: options.map { ($0.key, $0.defaultValue) }))
    }

    /// `options` completed with the defaults of the missing keys. Unknown keys are kept (and reported by `validate`).
    public func normalized(_ options: GameOptions) -> GameOptions {
        var result = defaultOptions
        for (key, value) in options.values { result[key] = value }
        return result
    }

    /// Player counts allowed with these options: the game range narrowed by the selected choices.
    public func playerRange(for options: GameOptions) -> ClosedRange<Int> {
        let chosen = normalized(options)
        var lower = players.lowerBound, upper = players.upperBound
        for option in self.options {
            guard case .choice(let choices) = option.kind,
                  let choice = choices.first(where: { $0.value == chosen[option.key] }),
                  let range = choice.players else { continue }
            lower = max(lower, range.lowerBound)
            upper = min(upper, range.upperBound)
        }
        return lower...max(lower, upper)
    }

    /// Schema validation, in a stable order: player count, then options in descriptor order, then unknown keys (sorted).
    /// An empty result means the engine may still refuse a custom value (`allowsCustomValue`).
    public func validate(options: GameOptions, playerCount: Int) -> [GameConfigurationError] {
        var issues: [GameConfigurationError] = []
        if !players.contains(playerCount) {
            issues.append(.playerCountOutOfRange(allowed: players, actual: playerCount))
        }
        let chosen = normalized(options)
        for option in self.options {
            let value = chosen[option.key] ?? option.defaultValue
            switch option.kind {
            case .toggle:
                if case .bool = value {} else { issues.append(.invalidOptionValue(key: option.key)) }
            case .stepper(let range):
                if case .int(let n) = value, range.contains(n) {} else { issues.append(.invalidOptionValue(key: option.key)) }
            case .optionalStepper(let range, _):
                switch value {
                case .null: break
                case .int(let n) where range.contains(n): break
                default: issues.append(.invalidOptionValue(key: option.key))
                }
            case .choice(let choices):
                if let choice = choices.first(where: { $0.value == value }) {
                    if let range = choice.players, !range.contains(playerCount), players.contains(playerCount) {
                        issues.append(.choiceUnavailable(key: option.key, note: choice.unavailableNote))
                    }
                } else if !option.allowsCustomValue {
                    issues.append(.invalidOptionValue(key: option.key))
                }
            }
        }
        let known = Set(self.options.map(\.key))
        for key in options.values.keys.sorted() where !known.contains(key) {
            issues.append(.unknownOption(key: key))
        }
        return issues
    }

    /// Setup-screen helper: replaces every choice that `playerCount` makes unavailable by the next available choice
    /// in list order (wrapping). Killer `easy` with 7 players becomes `medium` (GAMES.md §5.2).
    public func adjusted(_ options: GameOptions, playerCount: Int) -> GameOptions {
        var result = normalized(options)
        for option in self.options {
            guard case .choice(let choices) = option.kind,
                  let index = choices.firstIndex(where: { $0.value == result[option.key] }) else { continue }
            func available(_ choice: OptionChoice) -> Bool { choice.players?.contains(playerCount) ?? true }
            if available(choices[index]) { continue }
            for step in 1..<max(choices.count, 2) {
                let candidate = choices[(index + step) % choices.count]
                if available(candidate) {
                    result[option.key] = candidate.value
                    break
                }
            }
        }
        return result
    }
}
