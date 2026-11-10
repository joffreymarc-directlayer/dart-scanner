import DartCore

/// One target of Halve-It: the target of one round (GAMES.md §9.2).
enum HalveItTarget: Hashable, Sendable {
    /// Written `20`: the three beds of the number count, for n × multiplier.
    case number(Int)
    /// Written `D7`: the double of the number only.
    case double(Int)
    /// Written `T10`: the treble of the number only.
    case treble(Int)
    /// D1…D20 and DB.
    case anyDouble
    /// T1…T20. DB is not a treble.
    case anyTreble
    /// Written `BULL`: SB and DB.
    case bull

    /// Reads the notation of the `targets` option (ARCHITECTURE.md §5.3): `"20"`, `"D7"`, `"T10"`, `"anyDouble"`,
    /// `"anyTreble"`, `"BULL"`. Letters are read without regard to case, as dart notations are; nothing else is
    /// tolerated: no space, no sign, no leading zero, no number outside 1...20.
    init?(notation: String) {
        switch notation.lowercased() {
        case "anydouble": self = .anyDouble
        case "anytreble": self = .anyTreble
        case "bull": self = .bull
        default:
            guard let first = notation.first else { return nil }
            let prefixed = "dDtT".contains(first)
            let digits = prefixed ? notation.dropFirst() : Substring(notation)
            guard !digits.isEmpty, digits.first != "0", digits.allSatisfy({ $0.isASCII && $0.isNumber }),
                  let number = Int(digits), (1...20).contains(number) else { return nil }
            if !prefixed {
                self = .number(number)
            } else if first == "d" || first == "D" {
                self = .double(number)
            } else {
                self = .treble(number)
            }
        }
    }

    /// Canonical notation, as in the `targets` option: the game fact `target`.
    var notation: String {
        switch self {
        case .number(let number): return "\(number)"
        case .double(let number): return "D\(number)"
        case .treble(let number): return "T\(number)"
        case .anyDouble: return "anyDouble"
        case .anyTreble: return "anyTreble"
        case .bull: return "BULL"
        }
    }

    /// Points earned by a dart on this target; nil when the dart does not count (table of GAMES.md §9.2).
    /// A dart that counts always earns its own points: n × multiplier, 2n, 3n, 25 or 50.
    func gain(for hit: Hit) -> Int? {
        let counts: Bool
        switch self {
        case .number(let number): counts = hit.number == number
        case .double(let number): counts = hit.bed == .double && hit.number == number
        case .treble(let number): counts = hit.bed == .treble && hit.number == number
        case .anyDouble: counts = hit.isDouble
        case .anyTreble: counts = hit.isTreble
        case .bull: counts = hit.isBull
        }
        return counts ? hit.points : nil
    }

    /// Zones to highlight for this target (GAMES.md §9.7).
    var zones: [BoardZone] {
        switch self {
        case .number(let number): return [.sector(number)]
        case .double(let number): return [.double(number)]
        case .treble(let number): return [.treble(number)]
        case .anyDouble: return (1...20).map { BoardZone.double($0) } + [.innerBull]
        case .anyTreble: return (1...20).map { BoardZone.treble($0) }
        case .bull: return [.bull]
        }
    }

    /// Name shown to the players: "20", "D7", "T10", "un double", "un triple", "Bull".
    var title: LocalizedText {
        switch self {
        case .number, .double, .treble: return LocalizedText(verbatim: notation)
        case .anyDouble: return LocalizedText(fr: "un double", en: "any double")
        case .anyTreble: return LocalizedText(fr: "un triple", en: "any treble")
        case .bull: return LocalizedText(verbatim: "Bull")
        }
    }
}
