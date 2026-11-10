import Foundation

/// One of the 63 values of GAMES.md §2.2: S1…S20, D1…D20, T1…T20, SB, DB, MISS.
/// Inner and outer single are the same value. Two darts with the same `Hit` have exactly the same effect.
public struct Hit: Hashable, Sendable, CustomStringConvertible {
    public enum Bed: Int, Sendable, CaseIterable {
        case miss, single, double, treble, outerBull, innerBull
    }

    public let bed: Bed
    /// Sector number 1...20 for single, double and treble; nil for the bulls and MISS.
    public let number: Int?

    private init(_ bed: Bed, _ number: Int?) {
        self.bed = bed
        self.number = number
    }

    /// Validating initialiser: nil when `number` does not fit `bed`.
    public init?(bed: Bed, number: Int?) {
        switch bed {
        case .single, .double, .treble:
            guard let n = number, (1...20).contains(n) else { return nil }
            self.init(bed, n)
        case .miss, .outerBull, .innerBull:
            guard number == nil else { return nil }
            self.init(bed, nil)
        }
    }

    /// MISS: off the scoring area, or a bounce-out.
    public static let miss = Hit(.miss, nil)
    /// SB: outer bull, 25.
    public static let outerBull = Hit(.outerBull, nil)
    /// DB: inner bull, 50. Counts as a double.
    public static let innerBull = Hit(.innerBull, nil)

    /// Precondition: `number` in 1...20.
    public static func single(_ number: Int) -> Hit {
        precondition((1...20).contains(number), "sector number out of range")
        return Hit(.single, number)
    }

    public static func double(_ number: Int) -> Hit {
        precondition((1...20).contains(number), "sector number out of range")
        return Hit(.double, number)
    }

    public static func treble(_ number: Int) -> Hit {
        precondition((1...20).contains(number), "sector number out of range")
        return Hit(.treble, number)
    }

    /// The 63 values in canonical order: S1…S20, D1…D20, T1…T20, SB, DB, MISS.
    public static let all: [Hit] =
        (1...20).map(Hit.single) + (1...20).map(Hit.double) + (1...20).map(Hit.treble) + [.outerBull, .innerBull, .miss]

    /// Points of GAMES.md §2.2: n, 2n, 3n, 25, 50, 0.
    public var points: Int {
        switch bed {
        case .miss: return 0
        case .single: return number ?? 0
        case .double: return 2 * (number ?? 0)
        case .treble: return 3 * (number ?? 0)
        case .outerBull: return 25
        case .innerBull: return 50
        }
    }

    /// 1 for singles and SB, 2 for doubles and DB, 3 for trebles, 0 for MISS.
    public var multiplier: Int {
        switch bed {
        case .miss: return 0
        case .single, .outerBull: return 1
        case .double, .innerBull: return 2
        case .treble: return 3
        }
    }

    /// D1…D20 and DB.
    public var isDouble: Bool { bed == .double || bed == .innerBull }
    /// T1…T20.
    public var isTreble: Bool { bed == .treble }
    /// SB and DB.
    public var isBull: Bool { bed == .outerBull || bed == .innerBull }
    public var isMiss: Bool { bed == .miss }

    // MARK: Notation

    public enum NotationStyle: Sendable {
        /// "S5", "D16", "T20", "SB", "DB", "MISS": tests, logs, persistence (GAMES.md §2.2).
        case canonical
        /// "S5", "D16", "T20", "25", "50", "miss": compact display of the bulls by their points.
        case points
    }

    /// Canonical notation: upper case, no space.
    public var notation: String { formatted(.canonical) }

    public func formatted(_ style: NotationStyle) -> String {
        switch bed {
        case .single: return "S\(number ?? 0)"
        case .double: return "D\(number ?? 0)"
        case .treble: return "T\(number ?? 0)"
        case .outerBull: return style == .canonical ? "SB" : "25"
        case .innerBull: return style == .canonical ? "DB" : "50"
        case .miss: return style == .canonical ? "MISS" : "miss"
        }
    }

    /// Case-insensitive parser. Accepts both styles: "t20", "D16", "S5", "SB", "25", "DB", "50", "MISS", "miss".
    /// A bare number 1...20 is a single ("5" = S5). Anything else is nil.
    public init?(notation: String) {
        let text = notation.trimmingCharacters(in: .whitespaces).uppercased()
        switch text {
        case "MISS": self = .miss
        case "SB", "25": self = .outerBull
        case "DB", "50": self = .innerBull
        default:
            guard let first = text.first else { return nil }
            let bed: Bed
            let digits: Substring
            switch first {
            case "S": bed = .single; digits = text.dropFirst()
            case "D": bed = .double; digits = text.dropFirst()
            case "T": bed = .treble; digits = text.dropFirst()
            default: bed = .single; digits = Substring(text)
            }
            guard !digits.isEmpty, digits.first != "0", digits.allSatisfy(\.isASCII), digits.allSatisfy(\.isNumber),
                  let n = Int(digits), (1...20).contains(n) else { return nil }
            self.init(bed, n)
        }
    }

    public var description: String { notation }
}

/// Encoded as its canonical notation (a JSON string such as "T20").
extension Hit: Codable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let text = try container.decode(String.self)
        guard let hit = Hit(notation: text) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unknown dart notation: \(text)")
        }
        self = hit
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(notation)
    }
}
