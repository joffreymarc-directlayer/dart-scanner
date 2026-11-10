import Foundation

/// Value of one game option. Option names and enum values are those of GAMES.md ("level": "easy", "maxRounds": 15).
public enum OptionValue: Hashable, Codable, Sendable {
    case bool(Bool)
    case int(Int)
    /// An enum case by its GAMES.md name: "cutThroat", "easy", "double".
    case string(String)
    /// A list, e.g. the Halve-It targets: ["20", "16", "D7", "14", "T10", "BULL"].
    case strings([String])
    /// The `nil` of an optional option (`maxRounds: nil` = no round limit).
    case null
}

extension OptionValue: ExpressibleByBooleanLiteral, ExpressibleByIntegerLiteral, ExpressibleByStringLiteral {
    public init(booleanLiteral value: Bool) { self = .bool(value) }
    public init(integerLiteral value: Int) { self = .int(value) }
    public init(stringLiteral value: String) { self = .string(value) }
}

/// The options chosen for one game, by option key. Missing keys take the descriptor's defaults.
public struct GameOptions: Hashable, Codable, Sendable, ExpressibleByDictionaryLiteral {
    public var values: [String: OptionValue]

    public init(_ values: [String: OptionValue] = [:]) {
        self.values = values
    }

    public init(dictionaryLiteral elements: (String, OptionValue)...) {
        self.values = Dictionary(elements, uniquingKeysWith: { _, last in last })
    }

    public subscript(key: String) -> OptionValue? {
        get { values[key] }
        set { values[key] = newValue }
    }

    public func bool(_ key: String) -> Bool? {
        if case .bool(let value)? = values[key] { return value }
        return nil
    }

    /// Nil when the key is missing, is `.null`, or is not an integer.
    public func int(_ key: String) -> Int? {
        if case .int(let value)? = values[key] { return value }
        return nil
    }

    public func string(_ key: String) -> String? {
        if case .string(let value)? = values[key] { return value }
        return nil
    }

    public func strings(_ key: String) -> [String]? {
        if case .strings(let value)? = values[key] { return value }
        return nil
    }
}

// MARK: - Options schema (drives the setup screen)

/// Pictogram shown next to a choice on the setup screen.
public enum ChoiceIllustration: Hashable, Sendable {
    /// `count` adjacent sectors lit on a small board; `moving` adds the "changes every turn" mark (Killer levels).
    case sectors(count: Int, moving: Bool)
}

/// One selectable value of a `.choice` option.
public struct OptionChoice: Hashable, Sendable {
    public var value: OptionValue
    public var label: LocalizedText
    public var detail: LocalizedText?
    /// Player counts for which the choice is allowed; nil = the whole range of the game.
    public var players: ClosedRange<Int>?
    /// Shown when the choice is greyed out: "6 joueurs maximum en Facile".
    public var unavailableNote: LocalizedText?
    public var illustration: ChoiceIllustration?

    public init(_ value: OptionValue, label: LocalizedText, detail: LocalizedText? = nil,
                players: ClosedRange<Int>? = nil, unavailableNote: LocalizedText? = nil,
                illustration: ChoiceIllustration? = nil) {
        self.value = value
        self.label = label
        self.detail = detail
        self.players = players
        self.unavailableNote = unavailableNote
        self.illustration = illustration
    }
}

/// How an option is edited and which values it accepts.
public enum OptionKind: Hashable, Sendable {
    /// `.bool`.
    case toggle
    /// `.int` inside the range, edited with − / +.
    case stepper(ClosedRange<Int>)
    /// `.int` inside the range, or `.null`; `nullLabel` names the null value ("Sans limite").
    case optionalStepper(ClosedRange<Int>, nullLabel: LocalizedText)
    /// One value among the choices (radio buttons or a segmented control).
    case choice([OptionChoice])
}

/// Description of one option of a game.
public struct OptionDescriptor: Hashable, Sendable, Identifiable {
    /// Option name of GAMES.md: "startScore", "level", "maxRounds".
    public var key: String
    public var label: LocalizedText
    public var help: LocalizedText?
    public var kind: OptionKind
    public var defaultValue: OptionValue
    /// Folded under "Plus d'options" on the setup screen.
    public var isAdvanced: Bool
    /// For `.choice`: a value outside the listed choices is left to the engine to validate (custom Halve-It lists).
    public var allowsCustomValue: Bool

    public var id: String { key }

    public init(key: String, label: LocalizedText, help: LocalizedText? = nil, kind: OptionKind,
                defaultValue: OptionValue, isAdvanced: Bool = false, allowsCustomValue: Bool = false) {
        self.key = key
        self.label = label
        self.help = help
        self.kind = kind
        self.defaultValue = defaultValue
        self.isAdvanced = isAdvanced
        self.allowsCustomValue = allowsCustomValue
    }
}
