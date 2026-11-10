import Foundation
import DartCore

/// The choices of the setup screen for one game, driven by its descriptor alone (ARCHITECTURE.md §8.5, §4.4):
/// the players in playing order and the options. A value: the screen keeps it in `@State`, the tests drive it.
struct SetupState: Hashable {
    let descriptor: GameDescriptor
    /// Players of the game, in playing order (colour = place).
    private(set) var players: [Player]
    /// Every option of the descriptor, completed by the defaults, kept valid for the number of players.
    private(set) var options: GameOptions

    /// Last choices of this game (`AppStorage.loadSetup(for:)`), else the first players of the roster.
    init(descriptor: GameDescriptor, roster: [Player], memory: SetupMemory?) {
        self.descriptor = descriptor
        let known = Set(descriptor.options.map(\.key))
        if let memory {
            let byID = Dictionary(roster.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            players = Array(memory.playerIDs.compactMap { byID[$0] }.prefix(descriptor.players.upperBound))
            // A key the game no longer has is dropped; a value it no longer accepts falls back to its default.
            var remembered = GameOptions(memory.options.values.filter { known.contains($0.key) })
            for option in descriptor.options {
                let alone = GameOptions([option.key: remembered[option.key] ?? option.defaultValue])
                if descriptor.validate(options: alone, playerCount: descriptor.players.lowerBound)
                    .contains(.invalidOptionValue(key: option.key)) {
                    remembered[option.key] = option.defaultValue
                }
            }
            options = descriptor.normalized(remembered)
        } else {
            let count = min(roster.count, max(descriptor.players.lowerBound, min(2, descriptor.players.upperBound)))
            players = Array(roster.prefix(count))
            options = descriptor.defaultOptions
        }
        options = descriptor.adjusted(options, playerCount: max(players.count, descriptor.players.lowerBound))
    }

    var playerCount: Int { players.count }

    /// Player counts allowed by the game with the options chosen.
    var allowedPlayers: ClosedRange<Int> { descriptor.playerRange(for: options) }

    /// Schema problems of the current choices; empty when the game can start.
    var issues: [GameConfigurationError] {
        descriptor.validate(options: options, playerCount: playerCount)
    }

    var canStart: Bool {
        issues.isEmpty && descriptor.players.contains(playerCount)
    }

    /// True while another player can join (the overall maximum of the game).
    var canAddPlayer: Bool { playerCount < descriptor.players.upperBound }

    // MARK: Players

    mutating func add(_ player: Player) {
        guard canAddPlayer, !players.contains(where: { $0.id == player.id }) else { return }
        players.append(player)
        adjustOptions()
    }

    mutating func remove(_ player: Player) {
        players.removeAll { $0.id == player.id }
        adjustOptions()
    }

    /// Follows the roster: renamed players are renamed here, deleted ones leave the game.
    mutating func follow(roster: [Player]) {
        let byID = Dictionary(roster.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        players = players.compactMap { byID[$0.id] }
        adjustOptions()
    }

    // MARK: Options

    func value(of option: OptionDescriptor) -> OptionValue {
        options[option.key] ?? option.defaultValue
    }

    mutating func set(_ value: OptionValue, for option: OptionDescriptor) {
        options[option.key] = value
    }

    /// A choice the number of players makes unavailable ("Facile" with 7 players) is greyed out with its note.
    func isAvailable(_ choice: OptionChoice) -> Bool {
        choice.players?.contains(max(playerCount, descriptor.players.lowerBound)) ?? true
    }

    /// The options shown at once, and those folded under "Plus d'options".
    var mainOptions: [OptionDescriptor] { descriptor.options.filter { !$0.isAdvanced } }
    var advancedOptions: [OptionDescriptor] { descriptor.options.filter(\.isAdvanced) }

    /// The configuration that `AppModel.startGame` receives, and what is remembered for next time.
    var memory: SetupMemory {
        SetupMemory(playerIDs: players.map(\.id), options: options)
    }

    /// GAMES.md §5.2: a choice that the new number of players forbids is replaced by the next available one
    /// ("Facile" with 7 players becomes "Intermédiaire").
    private mutating func adjustOptions() {
        options = descriptor.adjusted(options, playerCount: max(playerCount, descriptor.players.lowerBound))
    }
}

/// How the setup screen edits one option (table of ARCHITECTURE.md §8.5).
enum SetupControl: Equatable {
    case toggle
    case stepper(ClosedRange<Int>)
    case optionalStepper(ClosedRange<Int>, nullLabel: LocalizedText)
    /// Two or three choices without detail.
    case segmented([OptionChoice])
    /// Any other choice list: one radio row per choice.
    case radio([OptionChoice])

    init(_ kind: OptionKind) {
        switch kind {
        case .toggle: self = .toggle
        case .stepper(let range): self = .stepper(range)
        case .optionalStepper(let range, let nullLabel): self = .optionalStepper(range, nullLabel: nullLabel)
        case .choice(let choices):
            if (2...3).contains(choices.count) && choices.allSatisfy({ $0.detail == nil }) {
                self = .segmented(choices)
            } else {
                self = .radio(choices)
            }
        }
    }
}
