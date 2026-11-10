import Foundation
import DartCore

/// `count` players named J1…Jn, with stable identifiers (GAMES.md §2.3).
public func testPlayers(_ count: Int) -> [Player] {
    (0..<count).map { index in
        Player(id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", index + 1)) ?? UUID(), name: "J\(index + 1)")
    }
}

extension GameRegistry {
    /// A game for a test vector: `try registry.match(.x01, ["outRule": "double"], players: 2, seed: 0)`.
    public func match(_ game: GameID, _ options: GameOptions = [:], players: Int, seed: UInt64 = 0) throws -> GameMatch {
        try makeMatch(GameConfiguration(gameID: game, options: options, players: testPlayers(players), seed: seed))
    }

    /// Games of this registry whose rules are not delivered yet: creating one throws `.unknownGame` (the skeleton
    /// of ARCHITECTURE.md §5.3). Probed with the default options and the smallest allowed number of players.
    public var skeletonGames: [GameID] {
        definitions.compactMap { definition in
            let descriptor = definition.descriptor
            let players = descriptor.playerRange(for: descriptor.defaultOptions).lowerBound
            do {
                _ = try match(descriptor.id, players: players)
                return nil
            } catch let error as GameConfigurationError {
                if case .unknownGame = error { return descriptor.id }
                return nil
            } catch {
                return nil
            }
        }
    }

    /// Definitions whose rules are delivered, in registry order. A test that runs "on every game of the registry"
    /// iterates THIS list, so that it passes while the games of other lots are still skeletons.
    public var deliveredDefinitions: [GameDefinition] {
        let skeletons = Set(skeletonGames)
        return definitions.filter { !skeletons.contains($0.id) }
    }
}

extension GameMatch {
    /// Plays a script written as in GAMES.md §2.11: "," separates darts, "|" is an `endTurn`, "×3" repeats a dart,
    /// and `S6@(124.0, 0.0)` is a dart with a recorded position in board millimetres (without "@": no position).
    /// `match.play("T20, S5, MISS | MISS ×3 |")` returns one outcome per input, in order.
    /// Traps on a notation that `Hit(notation:)` cannot read or on an unreadable position: a typo in a vector
    /// must not pass silently. Negative coordinates use the ASCII minus sign.
    @discardableResult
    public mutating func play(_ script: String) -> [InputOutcome] {
        var outcomes: [InputOutcome] = []
        var token = ""
        // Inside "@( … )" the comma separates x from y, not two darts.
        var depth = 0

        func flush(_ match: inout GameMatch) {
            let text = token.trimmingCharacters(in: .whitespacesAndNewlines)
            token = ""
            guard !text.isEmpty else { return }
            let parts = text.components(separatedBy: "×")
            let times = parts.count > 1 ? Int(parts[1].trimmingCharacters(in: .whitespaces)) ?? 1 : 1
            let dart = parts[0].components(separatedBy: "@")
            let name = dart[0].trimmingCharacters(in: .whitespaces)
            guard let hit = Hit(notation: name) else { preconditionFailure("unknown dart notation: \(name)") }
            var position: BoardPoint?
            if dart.count > 1 {
                let numbers = dart[1].trimmingCharacters(in: CharacterSet(charactersIn: " ()"))
                    .components(separatedBy: ",")
                    .map { Double($0.trimmingCharacters(in: .whitespaces)) }
                guard numbers.count == 2, let x = numbers[0], let y = numbers[1] else {
                    preconditionFailure("unreadable position: \(text)")
                }
                position = BoardPoint(x: x, y: y)
            }
            for _ in 0..<times {
                outcomes.append(match.throwDart(DartRecord(hit: hit, position: position)))
            }
        }

        for character in script {
            switch character {
            case "(":
                depth += 1
                token.append(character)
            case ")":
                depth -= 1
                token.append(character)
            case "," where depth == 0:
                flush(&self)
            case "|" where depth == 0:
                flush(&self)
                outcomes.append(endTurn())
            default:
                token.append(character)
            }
        }
        flush(&self)
        return outcomes
    }

    /// `match.fact(0, "remaining")` is the field `J1.remaining` of GAMES.md.
    public func fact(_ player: PlayerIndex, _ name: String) -> FactValue? {
        snapshot.players[player].facts[name]
    }

    /// `match.gameFact("ball")` is a game-level field of GAMES.md (`ball`, `sideGoals`, `blobs`, `targets`, `king`).
    public func gameFact(_ name: String) -> FactValue? {
        snapshot.facts[name]
    }

    /// Notations of the darts of the current turn: ["T20", "S5"].
    public var turnNotation: [String] {
        currentTurn.map(\.hit.notation)
    }
}
