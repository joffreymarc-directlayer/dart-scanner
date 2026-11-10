import Testing
import DartCore
import DartGames
import DartTestSupport

/// Helpers shared by the Killer test files. `GameMatch` belongs to DartCore: every member added here carries the
/// `killer` prefix (ARCHITECTURE.md §13.4, rule 3).
extension GameMatch {
    /// The `zone` fact of every player, in player order.
    var killerZones: [[Int]] {
        snapshot.players.map { row in
            if case .ints(let zone)? = row.facts["zone"] { return zone }
            return []
        }
    }

    /// An integer fact (`lives`, `armingProgress`, `kills`) of every player.
    func killerInts(_ name: String) -> [Int] {
        snapshot.players.map { row in
            if case .int(let value)? = row.facts[name] { return value }
            return Int.min
        }
    }

    /// A boolean fact (`isKiller`, `eliminated`) of every player.
    func killerBools(_ name: String) -> [Bool] {
        snapshot.players.map { row in
            if case .bool(let value)? = row.facts[name] { return value }
            return false
        }
    }

    /// Players alive, in player order.
    var killerAlive: [PlayerIndex] {
        let eliminated = killerBools("eliminated")
        return eliminated.indices.filter { !eliminated[$0] }
    }

    /// Throws a single on number `index` of the CURRENT zone of `player` (read from the facts, so it follows an
    /// expert redraw).
    @discardableResult
    mutating func killerThrow(at player: PlayerIndex, number index: Int = 0, times: Int = 1) -> [InputOutcome] {
        (0..<times).map { _ in throwDart(DartRecord(hit: .single(killerZones[player][index]))) }
    }

    /// Applies one input as a new journal entry.
    @discardableResult
    mutating func killerApply(_ input: GameInput) -> InputOutcome {
        switch input {
        case .dart(let hit): return throwDart(DartRecord(hit: hit))
        case .endTurn: return endTurn()
        }
    }

    /// Structural invariants of GAMES.md §5 that hold after every input, whatever the level.
    func killerExpectInvariants(width: Int, lives startingLives: Int, armingHits: Int,
                                sourceLocation: SourceLocation = #_sourceLocation) {
        let ring = BoardGeometry.standardSectorOrder
        let zones = killerZones
        let lives = killerInts("lives")
        let arming = killerInts("armingProgress")
        let kills = killerInts("kills")
        let eliminated = killerBools("eliminated")
        let killers = killerBools("isKiller")
        let alive = killerAlive
        let ranks = snapshot.ranks

        // Zones: `width` adjacent numbers, clockwise; never shared between two players alive.
        for zone in zones {
            #expect(zone.count == width, sourceLocation: sourceLocation)
            #expect(zone.allSatisfy { (1...20).contains($0) }, sourceLocation: sourceLocation)
            for index in zone.indices.dropFirst() {
                let previous = ring.firstIndex(of: zone[index - 1]) ?? -1
                #expect(ring[(previous + 1) % 20] == zone[index], sourceLocation: sourceLocation)
            }
        }
        let numbersAlive = alive.flatMap { zones[$0] }
        #expect(Set(numbersAlive).count == numbersAlive.count, "two players alive share a number", sourceLocation: sourceLocation)

        for player in zones.indices {
            #expect((0...startingLives).contains(lives[player]), sourceLocation: sourceLocation)
            #expect(eliminated[player] == (lives[player] == 0), sourceLocation: sourceLocation)
            #expect(snapshot.players[player].isEliminated == eliminated[player], sourceLocation: sourceLocation)
            #expect((0...armingHits).contains(arming[player]), sourceLocation: sourceLocation)
            #expect(killers[player] == (arming[player] == armingHits), sourceLocation: sourceLocation)
            #expect(kills[player] >= 0, sourceLocation: sourceLocation)
        }
        #expect(kills.reduce(0, +) <= zones.count - alive.count, sourceLocation: sourceLocation)

        KillerTestProperties.expectWellFormed(ranks: ranks, players: zones.count, sourceLocation: sourceLocation)
        // Ranks: players alive before every eliminated player, who all have distinct ranks after them.
        #expect(ranks.count == zones.count && ranks.min() == 1, sourceLocation: sourceLocation)
        let deadRanks = zones.indices.filter { eliminated[$0] }.map { ranks[$0] }.sorted()
        #expect(deadRanks == Array((alive.count + 1)..<(zones.count + 1)), sourceLocation: sourceLocation)
        for player in alive {
            #expect(ranks[player] <= alive.count, sourceLocation: sourceLocation)
        }

        // End of the game: as soon as one player is left, and only then (or at the round limit).
        #expect(alive.count >= 1, sourceLocation: sourceLocation)
        if alive.count == 1 {
            #expect(phase == .finished && snapshot.finishReason == .lastPlayerStanding, sourceLocation: sourceLocation)
        } else if phase == .finished {
            #expect(snapshot.finishReason == .roundLimit, sourceLocation: sourceLocation)
        }
        if phase == .throwing {
            #expect(!eliminated[snapshot.currentPlayer], sourceLocation: sourceLocation)
        }

        // Highlights: the sectors of the players alive, each in the colour of its owner; none once finished.
        if phase == .finished {
            #expect(snapshot.highlights.isEmpty, sourceLocation: sourceLocation)
        } else {
            let expected = alive.flatMap { player in zones[player].map { [player, $0] } }
            let actual = snapshot.highlights.map { [$0.owner ?? -1, $0.zone.number ?? -1] }
            #expect(actual == expected, sourceLocation: sourceLocation)
        }

        // The volley of the snapshot is the current turn of the journal, with one caption per dart.
        #expect(snapshot.turn.darts.map(\.hit) == currentTurn.map(\.hit), sourceLocation: sourceLocation)
        #expect(snapshot.turn.darts.allSatisfy { $0.caption != nil }, sourceLocation: sourceLocation)
    }
}

/// A pseudo-random Killer player for the property tests: all its randomness comes from a `SeededRandom` with a
/// fixed seed (ARCHITECTURE.md §12). It aims at zones often enough for players to arm, kill and die.
enum KillerTestBot {
    static func input(for match: GameMatch, random: inout SeededRandom) -> GameInput {
        if match.phase == .turnComplete { return .endTurn }
        let roll = random.nextInt(below: 100)
        // An early confirmation now and then, with zero, one or two darts.
        if roll < 5 { return .endTurn }
        if roll < 9 { return .dart(.miss) }
        if roll < 12 { return .dart(roll % 2 == 0 ? .outerBull : .innerBull) }
        let zones = match.killerZones
        let alive = match.killerAlive
        let player = match.snapshot.currentPlayer
        let number: Int
        if roll < 25 {
            number = 1 + random.nextInt(below: 20)
        } else if roll < 55 || alive.isEmpty {
            number = zones[player][random.nextInt(below: zones[player].count)]
        } else {
            let zone = zones[alive[random.nextInt(below: alive.count)]]
            number = zone[random.nextInt(below: zone.count)]
        }
        switch random.nextInt(below: 3) {
        case 0: return .dart(.single(number))
        case 1: return .dart(.double(number))
        default: return .dart(.treble(number))
        }
    }
}

/// Reading of the fixture lines of the reference cross-checks (`KillerOracleTests`, `ShanghaiOracleTests`,
/// `AroundTheClockOracleTests`), shared by the three games of the lot. Each fixture line is a random journal
/// played by the Python reference that computed the vectors of GAMES.md; it carries the journal, an FNV-1a hash
/// of the state after EVERY input and the final state in clear. The reference is an oracle for one more check,
/// never the specification.
enum KillerTestOracle {
    /// FNV-1a 64 offset basis.
    static let emptyHash: UInt64 = 14_695_981_039_346_656_037

    static func mix(_ hash: inout UInt64, _ text: String) {
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 1_099_511_628_211
        }
    }

    /// "S2,T1,D2|D4||T1": "," separates darts and every "|" is an `endTurn`.
    static func inputs(_ script: String) throws -> [GameInput] {
        var inputs: [GameInput] = []
        var token = ""
        for character in script + "," {
            if character == "," || character == "|" {
                if !token.isEmpty {
                    inputs.append(.dart(try #require(Hit(notation: token), "unreadable dart \(token)")))
                    token = ""
                }
                if character == "|" { inputs.append(.endTurn) }
            } else {
                token.append(character)
            }
        }
        return inputs
    }

    /// Phase, finish reason, current player, round and number of darts in the volley: "T-|0|3|2".
    static func turnState(_ match: GameMatch) -> String {
        let snapshot = match.snapshot
        let phase: String
        switch snapshot.phase {
        case .throwing: phase = "T"
        case .turnComplete: phase = "C"
        case .finished: phase = "F"
        }
        return "\(phase)\(reason(snapshot.finishReason))|\(snapshot.currentPlayer)|\(snapshot.round)|\(snapshot.turn.darts.count)"
    }

    static func reason(_ reason: FinishReason?) -> String {
        switch reason {
        case nil: return "-"
        case .victory?: return "V"
        case .lastPlayerStanding?: return "L"
        case .roundLimit?: return "R"
        }
    }

    static func ranks(_ match: GameMatch) -> String {
        match.snapshot.ranks.map(String.init).joined(separator: ".")
    }
}

/// Properties that every game must keep (ARCHITECTURE.md §12.1, "propriétés"), written once for the three games
/// of the lot. The common suite of lot G1 checks them again on every delivered game of the registry.
enum KillerTestProperties {
    /// GAMES.md §2.7: one rank per player, starting at 1; equal players share a rank and the next one is skipped.
    static func expectWellFormed(ranks: [Int], players: Int, sourceLocation: SourceLocation = #_sourceLocation) {
        #expect(ranks.count == players && ranks.contains(1), sourceLocation: sourceLocation)
        for rank in ranks {
            // A rank is one more than the number of players strictly ahead.
            #expect(rank == 1 + ranks.filter { $0 < rank }.count, sourceLocation: sourceLocation)
        }
    }

    /// ARCHITECTURE.md §4.8: two darts with the same effect key have the same immediate effect, and, followed by
    /// the same inputs, leave the same game. `bot` chooses the inputs that follow.
    static func expectSameEffectKeySameFuture(_ match: GameMatch, botSeed: UInt64, steps: Int = 9,
                                              bot: (GameMatch, inout SeededRandom) -> GameInput,
                                              sourceLocation: SourceLocation = #_sourceLocation) {
        guard match.phase == .throwing else { return }
        let groups = Dictionary(grouping: Hit.all, by: { match.effectKey(for: $0) })
        for hits in groups.values {
            guard let first = hits.first, let last = hits.last, first != last else { continue }
            var one = match
            var other = match
            let firstEvents = one.throwDart(DartRecord(hit: first)).events.dropFirst()
            let lastEvents = other.throwDart(DartRecord(hit: last)).events.dropFirst()
            #expect(Array(firstEvents) == Array(lastEvents), "\(first) and \(last)", sourceLocation: sourceLocation)
            var random = SeededRandom(seed: botSeed)
            for _ in 0..<steps {
                let input = bot(one, &random)
                #expect(one.killerApply(input) == other.killerApply(input), "\(first) and \(last), then \(input)",
                        sourceLocation: sourceLocation)
                #expect(one.snapshot.players.map(\.facts) == other.snapshot.players.map(\.facts),
                        "\(first) and \(last), then \(input)", sourceLocation: sourceLocation)
                #expect(one.snapshot.facts == other.snapshot.facts && one.snapshot.ranks == other.snapshot.ranks
                        && one.snapshot.phase == other.snapshot.phase && one.snapshot.round == other.snapshot.round
                        && one.snapshot.currentPlayer == other.snapshot.currentPlayer && one.snapshot.highlights == other.snapshot.highlights,
                        "\(first) and \(last), then \(input)", sourceLocation: sourceLocation)
            }
        }
    }

    /// GAMES.md §2.2 and §2.13: in a game that does not depend on the position, adding, removing or changing a
    /// recorded position changes no state, no event and no rank. `journal` is replayed twice from `fresh`, once
    /// without any position and once with positions that have nothing to do with the hits (some not even finite).
    static func expectPositionsIgnored(from fresh: GameMatch, journal: [LogEntry],
                                       sourceLocation: SourceLocation = #_sourceLocation) {
        let positions = [BoardPoint.centre, BoardPoint(x: 400, y: -400), BoardPoint(x: .nan, y: .infinity),
                         BoardPoint(x: -103, y: 0.5), BoardPoint(x: 0, y: 166)]
        var plain = fresh
        var placed = fresh
        var random = SeededRandom(seed: 31)
        for entry in journal {
            switch entry {
            case .endTurn:
                #expect(plain.endTurn() == placed.endTurn(), sourceLocation: sourceLocation)
            case .dart(let record):
                let position = positions[random.nextInt(below: positions.count)]
                #expect(plain.throwDart(DartRecord(hit: record.hit)) == placed.throwDart(DartRecord(hit: record.hit, position: position)),
                        sourceLocation: sourceLocation)
                #expect(plain.effectKey(for: .single(20)) == placed.effectKey(for: .single(20), position: position),
                        sourceLocation: sourceLocation)
            }
            #expect(plain.snapshot == placed.snapshot, sourceLocation: sourceLocation)
        }
        #expect(plain.entries.count == journal.count, sourceLocation: sourceLocation)
    }
}
