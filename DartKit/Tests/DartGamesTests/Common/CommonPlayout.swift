import Foundation
import Testing
import DartCore
import DartGames
import DartTestSupport

/// Shared by the test files of `Common/` (lot G1): reproducible random games on the games of
/// `GameRegistry.standard`, and the checks of the rules that are common to every game (GAMES.md §2).
///
/// Nothing here knows a game: configurations are drawn from the schema of the descriptor, darts from the 63
/// hits, and every check is one that GAMES.md §2 or ARCHITECTURE.md §4 states for all the games. A game whose
/// rules are still a skeleton is not in `deliveredGames`, so these tests pass while other lots are at work and
/// start checking a game the day its rules are delivered (ARCHITECTURE.md §12.1).
///
/// All randomness comes from `SeededRandom` with fixed seeds (ARCHITECTURE.md §12).
enum CommonPlayout {
    static let registry = GameRegistry.standard

    /// Ids of the games whose rules are delivered, in registry order: the arguments of every "on each game" test.
    static var deliveredGames: [GameID] {
        registry.deliveredDefinitions.map(\.id)
    }

    static func descriptor(of game: GameID) throws -> GameDescriptor {
        try #require(registry.definition(for: game)).descriptor
    }

    /// A seed that depends on the game and on `salt` only (FNV-1a of the id): the journals of a game do not
    /// change when other games are delivered, and `Hasher` is not used because it changes with every process.
    static func seed(_ game: GameID, _ salt: UInt64) -> UInt64 {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in game.rawValue.utf8 {
            hash = (hash ^ UInt64(byte)) &* 0x0000_0100_0000_01B3
        }
        return hash ^ (salt &* 0x9E37_79B9_7F4A_7C15)
    }

    // MARK: Random configurations, from the schema of the descriptor

    /// A value of `range`, small half of the time: a low round limit lets a short journal reach the end of a game.
    private static func randomInt(in range: ClosedRange<Int>, _ random: inout SeededRandom) -> Int {
        if random.nextInt(below: 2) == 0 {
            return range.lowerBound + random.nextInt(below: min(3, range.count))
        }
        return range.lowerBound + random.nextInt(below: range.count)
    }

    /// A valid configuration: a number of players in the range of the game, and for each option either its
    /// default or a value its schema allows (a listed choice, a number of its range, `.null` where it may be).
    /// A choice that this number of players does not allow is replaced as the setup screen does (`adjusted`).
    static func randomConfiguration(_ descriptor: GameDescriptor, _ random: inout SeededRandom) -> GameConfiguration {
        let count = descriptor.players.lowerBound + random.nextInt(below: descriptor.players.count)
        var options = GameOptions()
        for option in descriptor.options where random.nextInt(below: 4) != 0 {
            switch option.kind {
            case .toggle:
                options[option.key] = .bool(random.nextInt(below: 2) == 0)
            case .stepper(let range):
                options[option.key] = .int(randomInt(in: range, &random))
            case .optionalStepper(let range, _):
                options[option.key] = random.nextInt(below: 4) == 0 ? .null : .int(randomInt(in: range, &random))
            case .choice(let choices):
                if !choices.isEmpty { options[option.key] = choices[random.nextInt(below: choices.count)].value }
            }
        }
        options = descriptor.adjusted(options, playerCount: count)
        return GameConfiguration(gameID: descriptor.id, options: options, players: testPlayers(count), seed: random.next())
    }

    /// Start date of every random game: a fixed one, so that no test reads the clock (ARCHITECTURE.md §4.8).
    static let startedAt = Date(timeIntervalSinceReferenceDate: 0)

    /// A new game of `configuration`, started at the fixed date.
    static func makeMatch(_ configuration: GameConfiguration) throws -> GameMatch {
        let definition = try #require(registry.definition(for: configuration.gameID))
        return try GameMatch(definition: definition, configuration: configuration, startedAt: startedAt)
    }

    static func randomMatch(_ descriptor: GameDescriptor, _ random: inout SeededRandom) throws -> GameMatch {
        try makeMatch(randomConfiguration(descriptor, &random))
    }

    // MARK: Random inputs

    /// One of the 63 hits; MISS about one time in nine.
    static func randomHit(_ random: inout SeededRandom) -> Hit {
        let roll = random.nextInt(below: Hit.all.count + 7)
        return roll < Hit.all.count ? Hit.all[roll] : .miss
    }

    /// For a position-dependent game, one time out of two, a position drawn in the square of ±180 mm, on the
    /// grid of the tenth of a millimetre (ARCHITECTURE.md §12.1). Nil for every other game.
    static func randomPosition(_ descriptor: GameDescriptor, _ random: inout SeededRandom) -> BoardPoint? {
        guard descriptor.dependsOnPosition, random.nextInt(below: 2) == 0 else { return nil }
        let x = Double(random.nextInt(below: 3601) - 1800) / 10
        let y = Double(random.nextInt(below: 3601) - 1800) / 10
        return BoardPoint(x: x, y: y)
    }

    static func randomDart(_ descriptor: GameDescriptor, _ random: inout SeededRandom) -> DartRecord {
        let hit = randomHit(&random)
        return DartRecord(hit: hit, position: randomPosition(descriptor, &random))
    }

    /// One operation of a random game, with what the match answered.
    enum Step {
        case dart(DartRecord, InputOutcome)
        case endTurn(InputOutcome)
        case undo(EditOutcome)
        case replace(EditOutcome)
        case remove(EditOutcome)
    }

    /// Applies one random operation of GAMES.md §2.4 and §2.5 to `match`. The mix follows the phase, so that a
    /// game moves on (darts while throwing, confirmations once the turn is closed) and still meets refused
    /// inputs, early confirmations, undo and corrections in every phase.
    static func step(_ match: inout GameMatch, _ descriptor: GameDescriptor, _ random: inout SeededRandom) -> Step {
        let dartChance: Int, endChance: Int
        switch match.phase {
        case .throwing: (dartChance, endChance) = (78, 10)
        case .turnComplete: (dartChance, endChance) = (6, 80)
        case .finished: (dartChance, endChance) = (20, 20)
        }
        let roll = random.nextInt(below: 100)
        if roll < dartChance {
            let dart = randomDart(descriptor, &random)
            return .dart(dart, match.throwDart(dart))
        }
        if roll < dartChance + endChance {
            return .endTurn(match.endTurn())
        }
        switch random.nextInt(below: 3) {
        case 0:
            return .undo(match.undo())
        case 1:
            let dart = randomDart(descriptor, &random)
            return .replace(match.replaceDart(at: random.nextInt(below: dartsPerTurn), with: dart.hit, position: dart.position))
        default:
            return .remove(match.removeDart(at: random.nextInt(below: dartsPerTurn)))
        }
    }

    /// A game that only moves forward: a dart while the player may throw, the confirmation once the turn is
    /// closed. Stops when the game is finished or after `limit` inputs; returns the number of inputs applied.
    @discardableResult
    static func playForward(_ match: inout GameMatch, _ descriptor: GameDescriptor, _ random: inout SeededRandom,
                            limit: Int) -> Int {
        var inputs = 0
        while match.phase != .finished && inputs < limit {
            if match.phase == .throwing {
                match.throwDart(randomDart(descriptor, &random))
            } else {
                match.endTurn()
            }
            inputs += 1
        }
        return inputs
    }

    /// What `playForward(engine:)` saw.
    struct Playout {
        /// Inputs applied, all accepted.
        var inputs = 0
        /// Phase after the last input, followed from the events of the kernel.
        var phase = GamePhase.throwing
        /// Reason carried by the `gameFinished` event, when the game ended.
        var reason: FinishReason?
        /// The input that ended the game was a dart (and not a confirmation).
        var endedOnADart = false
        /// An input was refused although the phase followed from the events allowed it.
        var refused = false
    }

    /// The same forward game on a bare engine: no journal and no snapshot per input, so that hundreds of long
    /// games stay cheap. The phase is followed from the events of the kernel (GAMES.md §2.10): `gameFinished`
    /// last ends the game, `turnCompleted` last closes the turn, anything else leaves the player throwing.
    static func playForward(engine: inout any GameEngine, _ descriptor: GameDescriptor, _ random: inout SeededRandom,
                            limit: Int) -> Playout {
        var playout = Playout()
        playout.phase = engine.snapshot.phase
        while playout.phase != .finished && playout.inputs < limit {
            let outcome: InputOutcome
            let isDart = playout.phase == .throwing
            if isDart {
                let dart = randomDart(descriptor, &random)
                outcome = engine.apply(.dart(dart.hit), position: dart.position)
            } else {
                outcome = engine.apply(.endTurn)
            }
            guard case .accepted(let events) = outcome else {
                playout.refused = true
                break
            }
            playout.inputs += 1
            switch events.last {
            case .gameFinished(let reason)?:
                playout.phase = .finished
                playout.reason = reason
                playout.endedOnADart = isDart
            case .turnCompleted?:
                playout.phase = .turnComplete
            default:
                playout.phase = .throwing
            }
        }
        return playout
    }

    // MARK: Failures

    /// The failures of one test, reported once at its end. A game that breaks a common rule breaks it in almost
    /// every journal: hundreds of identical issues would hide the first one, which is the one to replay.
    struct Failures {
        private(set) var count = 0
        private(set) var first: [String] = []

        /// Records `message` when `condition` is false. The message is only built for the first failures.
        mutating func check(_ condition: Bool, _ message: @autoclosure () -> String) {
            guard !condition else { return }
            count += 1
            if first.count < 3 { first.append(message()) }
        }

        mutating func record(_ violations: [String], _ context: @autoclosure () -> String) {
            check(violations.isEmpty, "\(violations.joined(separator: "; ")) — \(context())")
        }

        var isEmpty: Bool { count == 0 }

        /// For the comment of the final `#expect(failures.isEmpty, …)`.
        var report: String {
            "\(count) failure(s), the first ones:\n" + first.joined(separator: "\n")
        }
    }

    // MARK: Descriptions, for the failure messages

    /// The journal as a vector of GAMES.md §2.11 writes it: "T20, S5 | MISS".
    static func journal(_ match: GameMatch) -> String {
        var text = ""
        var needsComma = false
        for entry in match.entries {
            switch entry {
            case .dart(let record):
                text += needsComma ? ", " : ""
                text += record.hit.notation
                if let position = record.position { text += "@(\(position.x), \(position.y))" }
                needsComma = true
            case .endTurn:
                text += " | "
                needsComma = false
            }
        }
        return text
    }

    /// Game, options, players, seed and journal: enough to replay a failing game by hand.
    static func describe(_ match: GameMatch) -> String {
        let options = match.configuration.options.values.sorted { $0.key < $1.key }.map { "\($0.key): \($0.value)" }
        return "\(match.configuration.gameID) {\(options.joined(separator: ", "))}, \(match.players.count) players, "
            + "seed \(match.configuration.seed), journal: \(journal(match))"
    }

    // MARK: Checks of the common rules

    /// What a snapshot must respect at any time, in any game (GAMES.md §2.4, §2.6, §2.7, §2.9; ARCHITECTURE.md
    /// §4.6 to §4.8), the journal included: the current turn of the journal is the volley of the snapshot, in
    /// every phase (§2.5, §2.6). Returns the violations, empty when there is none.
    static func snapshotViolations(_ match: GameMatch) -> [String] {
        var violations = snapshotViolations(match.snapshot, of: match.configuration)
        if match.currentTurn.map(\.hit) != match.snapshot.turn.darts.map(\.hit) {
            violations.append("currentTurn \(match.turnNotation) differs from the volley of the snapshot")
        }
        return violations
    }

    /// The same checks on a bare snapshot of a game created with `configuration`.
    static func snapshotViolations(_ snapshot: GameSnapshot, of configuration: GameConfiguration) -> [String] {
        let count = configuration.players.count
        var violations: [String] = []

        if snapshot.gameID != configuration.gameID { violations.append("gameID is \(snapshot.gameID)") }
        if snapshot.players.count != count { violations.append("\(snapshot.players.count) rows for \(count) players") }
        if snapshot.ranks.count != count { violations.append("\(snapshot.ranks.count) ranks for \(count) players") }
        for (index, row) in snapshot.players.enumerated() {
            if row.player != index { violations.append("row \(index) is for player \(row.player)") }
            if index < snapshot.ranks.count, row.rank != snapshot.ranks[index] {
                violations.append("row \(index) has rank \(row.rank), ranks are \(snapshot.ranks)")
            }
        }
        // §2.7: ranks start at 1, players tied share a rank and the next rank is skipped ("1, 1, 3").
        for rank in snapshot.ranks where rank != 1 + snapshot.ranks.filter({ $0 < rank }).count {
            violations.append("ranks \(snapshot.ranks) are not shared ranks starting at 1")
            break
        }
        // §2.7: eliminated players always rank after every player still in the game, and someone always is.
        let alive = snapshot.players.filter { !$0.isEliminated }.map(\.rank)
        let eliminated = snapshot.players.filter(\.isEliminated).map(\.rank)
        if alive.isEmpty { violations.append("every player is eliminated") }
        if let worstAlive = alive.max(), let bestEliminated = eliminated.min(), bestEliminated <= worstAlive {
            violations.append("an eliminated player ranks before a player alive: \(snapshot.ranks)")
        }
        if snapshot.finishReason == .lastPlayerStanding && alive.count != 1 {
            violations.append("lastPlayerStanding with \(alive.count) players alive")
        }

        // §2.4: phases, current player, round, volley.
        if (snapshot.phase == .finished) != (snapshot.finishReason != nil) {
            violations.append("phase \(snapshot.phase) with finishReason \(String(describing: snapshot.finishReason))")
        }
        if !(0..<count).contains(snapshot.currentPlayer) { violations.append("currentPlayer \(snapshot.currentPlayer)") }
        if snapshot.round < 1 { violations.append("round \(snapshot.round)") }
        if let limit = snapshot.roundLimit, snapshot.round > limit {
            violations.append("round \(snapshot.round) beyond the limit \(limit)")
        }
        if snapshot.turn.capacity != dartsPerTurn { violations.append("turn capacity \(snapshot.turn.capacity)") }
        if snapshot.turn.darts.count > dartsPerTurn { violations.append("\(snapshot.turn.darts.count) darts in the volley") }
        if snapshot.phase == .throwing && snapshot.turn.darts.count >= dartsPerTurn {
            violations.append("still throwing after \(snapshot.turn.darts.count) darts")
        }
        if snapshot.finishReason == .roundLimit {
            if !snapshot.turn.darts.isEmpty { violations.append("volley not empty after the round limit") }
            if snapshot.roundLimit == nil { violations.append("finished at a round limit that does not exist") }
        }
        // §2.9 and ARCHITECTURE.md §4.7: no highlight once finished; results only once finished.
        if snapshot.phase == .finished {
            if !snapshot.highlights.isEmpty { violations.append("highlights in a finished game") }
        } else {
            if snapshot.outcome != nil { violations.append("outcome before the end") }
            if snapshot.winnerTitle != nil { violations.append("winnerTitle before the end") }
        }
        // §2.7: the winners are the players ranked first.
        if snapshot.winners.isEmpty { violations.append("nobody is ranked first") }
        return violations
    }

    private static func count(_ events: [GameEvent], where isKind: (GameEvent) -> Bool) -> Int {
        events.filter(isKind).count
    }

    private static func isDartRegistered(_ event: GameEvent) -> Bool {
        if case .dartRegistered = event { return true }
        return false
    }

    private static func isTurnCompleted(_ event: GameEvent) -> Bool {
        if case .turnCompleted = event { return true }
        return false
    }

    private static func isRoundStarted(_ event: GameEvent) -> Bool {
        if case .roundStarted = event { return true }
        return false
    }

    private static func isTurnStarted(_ event: GameEvent) -> Bool {
        if case .turnStarted = event { return true }
        return false
    }

    private static func isGameFinished(_ event: GameEvent) -> Bool {
        if case .gameFinished = event { return true }
        return false
    }

    /// What one input must respect in any game: who refuses what, and the place of the five events of the
    /// kernel among those of the rule (GAMES.md §2.4, §2.6, §2.10). `before` and `after` are the snapshots
    /// around the input. Returns the violations, empty when there is none.
    static func inputViolations(_ input: GameInput, _ outcome: InputOutcome,
                                before: GameSnapshot, after: GameSnapshot) -> [String] {
        var violations: [String] = []
        guard case .accepted(let events) = outcome else {
            // §2.4: a dart is refused once the turn is closed, everything is refused once the game is over,
            // and a refused input changes nothing.
            let expected: InputOutcome?
            switch (before.phase, input) {
            case (.finished, _): expected = .rejected(.gameFinished)
            case (.turnComplete, .dart): expected = .rejected(.turnComplete)
            default: expected = nil
            }
            if outcome != expected { violations.append("\(input) in phase \(before.phase) answered \(outcome)") }
            if after != before { violations.append("a refused input changed the state") }
            return violations
        }
        let registered = count(events, where: isDartRegistered)
        let completed = count(events, where: isTurnCompleted)
        let roundsStarted = count(events, where: isRoundStarted)
        let turnsStarted = count(events, where: isTurnStarted)
        let finished = count(events, where: isGameFinished)
        let player = before.currentPlayer

        switch input {
        case .dart(let hit):
            if before.phase != .throwing { violations.append("dart accepted in phase \(before.phase)") }
            if events.first != .dartRegistered(player: player, hit: hit) || registered != 1 {
                violations.append("dartRegistered is not first, or not unique")
            }
            if roundsStarted != 0 || turnsStarted != 0 { violations.append("a dart started a round or a turn") }
            if after.currentPlayer != player || after.round != before.round {
                violations.append("a dart changed the current player or the round")
            }
            if after.turn.darts.map(\.hit) != before.turn.darts.map(\.hit) + [hit] {
                violations.append("the dart was not added to the volley")
            }
            switch after.phase {
            case .finished:
                // The game ends on the dart: `gameFinished` last, no `turnCompleted`, never the round limit.
                guard let reason = after.finishReason, events.last == .gameFinished(reason: reason), finished == 1 else {
                    violations.append("gameFinished is not last, or not unique")
                    break
                }
                if reason == .roundLimit { violations.append("a dart ended the game at the round limit") }
                if completed != 0 { violations.append("turnCompleted on the dart that ends the game") }
            case .turnComplete:
                if events.last != .turnCompleted(player: player) || completed != 1 {
                    violations.append("turnCompleted is not last, or not unique")
                }
                if finished != 0 { violations.append("gameFinished without the phase finished") }
            case .throwing:
                if completed != 0 || finished != 0 { violations.append("a turn or a game closed while still throwing") }
            }

        case .endTurn:
            if before.phase == .finished { violations.append("endTurn accepted in a finished game") }
            if registered != 0 { violations.append("dartRegistered on endTurn") }
            // The turn is closed first when it was still open, once.
            let expectedCompleted = before.phase == .throwing ? 1 : 0
            if completed != expectedCompleted || (completed == 1 && !events.contains(.turnCompleted(player: player))) {
                violations.append("\(completed) turnCompleted for an endTurn in phase \(before.phase)")
            }
            if !after.turn.darts.isEmpty { violations.append("the volley is not empty after endTurn") }
            if after.phase == .finished {
                if events.last != .gameFinished(reason: .roundLimit) || finished != 1 || after.finishReason != .roundLimit {
                    violations.append("endTurn ended the game otherwise than at the round limit")
                }
                if roundsStarted != 0 || turnsStarted != 0 { violations.append("a turn started in a finished game") }
                if before.roundLimit != before.round || after.round != before.round {
                    violations.append("round limit \(String(describing: before.roundLimit)) applied in round \(before.round)")
                }
            } else {
                if after.phase != .throwing { violations.append("phase \(after.phase) after endTurn") }
                if events.last != .turnStarted(player: after.currentPlayer, round: after.round) || turnsStarted != 1 {
                    violations.append("turnStarted is not last, or not unique")
                }
                if finished != 0 { violations.append("gameFinished without the phase finished") }
                // Next player: the first one not eliminated, going round from the player after the current one.
                let players = after.players.count
                let next = (1...max(players, 1)).map { (player + $0) % max(players, 1) }
                    .first { !after.players[$0].isEliminated }
                if next != after.currentPlayer { violations.append("next player is \(after.currentPlayer), expected \(String(describing: next))") }
                // A round ends when the walk passes the end of the list.
                let wrapped = after.currentPlayer <= player
                if after.round != before.round + (wrapped ? 1 : 0) {
                    violations.append("round \(before.round) became \(after.round)")
                }
                let expectedRounds = wrapped ? 1 : 0
                if roundsStarted != expectedRounds || (wrapped && !events.contains(.roundStarted(round: after.round))) {
                    violations.append("\(roundsStarted) roundStarted")
                }
                // Order: [turnCompleted], [roundStarted], …, turnStarted.
                if let closing = events.firstIndex(where: isTurnCompleted), let opening = events.firstIndex(where: isRoundStarted),
                   closing > opening {
                    violations.append("roundStarted before turnCompleted")
                }
            }
        }
        return violations
    }
}
