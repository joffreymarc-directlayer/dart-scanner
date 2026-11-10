import Foundation
import Testing
import DartCore
import DartGames
import DartTestSupport

/// Journal checks shared by the four suites of lot G3 (Moon Landing, Fight, Conqueror, Halve-It). The file and
/// the type carry the prefix of one game of the lot, as ARCHITECTURE.md §13.4 asks for code shared inside a lot.
///
/// A game is a pure function of (configuration, seed, journal): GAMES.md §2.4 and §2.5. These helpers play
/// random operations and verify that the journal alone always rebuilds the same snapshot and the same events.
enum MoonLandingReplayChecks {
    /// Feeds the journal of `record` to a brand-new game, entry by entry.
    /// Returns that game and the events of every entry.
    static func replay(_ record: MatchRecord, in registry: GameRegistry = .standard) throws -> (match: GameMatch, events: [[GameEvent]]) {
        var fresh = try registry.makeMatch(record.configuration)
        let events = record.entries.map { entry -> [GameEvent] in
            switch entry {
            case .dart(let dart): return fresh.throwDart(dart).events
            case .endTurn: return fresh.endTurn().events
            }
        }
        return (fresh, events)
    }

    /// The game as the application saves it and reads it back: the record through JSON, then `restoreMatch`.
    static func restoredFromJSON(_ match: GameMatch, in registry: GameRegistry = .standard) throws -> GameMatch {
        let data = try JSONEncoder().encode(match.record)
        return try registry.restoreMatch(try JSONDecoder().decode(MatchRecord.self, from: data))
    }

    /// `ranks` follows GAMES.md §2.7: ranks start at 1, ties share a rank, and the next rank is skipped.
    static func ranksAreWellFormed(_ ranks: [Int]) -> Bool {
        ranks.allSatisfy { rank in rank == 1 + ranks.filter { $0 < rank }.count }
    }

    /// Plays `steps` random operations on a new game (darts chosen by `pick`, confirmations, undo, corrections,
    /// removals) and checks after each one that:
    /// - a brand-new game fed with the journal has the same snapshot, the same journal, and gives to the last
    ///   entry the events that the input returned; every sixteenth step, the same through `restoreMatch`;
    /// - the turn shown by the snapshot is the current turn of the journal, and the ranks are well formed;
    /// - `invariant` holds on the snapshot.
    /// At the end, the game saved as JSON is read back identical, and undoing everything gives the initial state back.
    /// All randomness comes from `SeededRandom(seed: fuzzSeed)`: a failure is reproducible.
    static func fuzz(_ game: GameID, _ options: GameOptions = [:], players: Int, seed: UInt64, fuzzSeed: UInt64,
                     steps: Int, pick: (GameSnapshot, inout SeededRandom) -> Hit,
                     invariant: (GameSnapshot) -> Void = { _ in }) throws {
        let registry = GameRegistry.standard
        var match = try registry.match(game, options, players: players, seed: seed)
        let initial = match.snapshot
        var random = SeededRandom(seed: fuzzSeed)
        for step in 0..<steps {
            var returned: [GameEvent]?
            switch random.nextInt(below: 20) {
            case 0..<11:
                let outcome = match.throwDart(DartRecord(hit: pick(match.snapshot, &random)))
                if outcome.isAccepted { returned = outcome.events }
            case 11..<15:
                let outcome = match.endTurn()
                if outcome.isAccepted { returned = outcome.events }
            case 15..<17:
                match.undo()
            case 17..<19:
                match.replaceDart(at: random.nextInt(below: 3), with: pick(match.snapshot, &random))
            default:
                match.removeDart(at: random.nextInt(below: 3))
            }
            let label: Comment = "\(game) seed \(seed) fuzz \(fuzzSeed) step \(step)"
            let snapshot = match.snapshot
            let rebuilt = try replay(match.record)
            #expect(rebuilt.match.snapshot == snapshot, label)
            #expect(rebuilt.match.entries == match.entries, label)
            if let returned {
                #expect(rebuilt.events.last == returned, label)
            }
            if step % 16 == 15 {
                #expect(try registry.restoreMatch(match.record).snapshot == snapshot, label)
            }
            #expect(snapshot.turn.darts.map(\.hit) == match.currentTurn.map(\.hit), label)
            #expect(snapshot.ranks.count == players && ranksAreWellFormed(snapshot.ranks), label)
            #expect(snapshot.players.map(\.rank) == snapshot.ranks, label)
            #expect((snapshot.phase == .finished) == (snapshot.finishReason != nil), label)
            #expect(snapshot.phase != .finished || snapshot.highlights.isEmpty, label)
            #expect(snapshot.turn.darts.count <= 3 && snapshot.players.count == players, label)
            invariant(snapshot)
        }
        let saved = try restoredFromJSON(match)
        #expect(saved.snapshot == match.snapshot && saved.entries == match.entries)
        // Undoing everything gives the initial state back (GAMES.md §2.5).
        while match.canUndo { match.undo() }
        #expect(match.snapshot == initial, "\(game) seed \(seed) fuzz \(fuzzSeed): undo to the start")
    }

    /// True when the two snapshots agree on everything the rest of a game can depend on: all of a snapshot but
    /// the darts of the turn and the texts.
    private static func sameObservableState(_ a: GameSnapshot, _ b: GameSnapshot) -> Bool {
        a.phase == b.phase && a.currentPlayer == b.currentPlayer && a.round == b.round && a.ranks == b.ranks
            && a.finishReason == b.finishReason && a.turn.darts.count == b.turn.darts.count
            && a.players.map(\.facts) == b.players.map(\.facts) && a.facts == b.facts
            && a.players.map(\.isEliminated) == b.players.map(\.isEliminated)
    }

    /// GAMES.md §2.2 and ARCHITECTURE.md §4.8: two darts with the same `effectKey` have exactly the same effect.
    /// Walks through `states` states of random games; in each one, groups the 63 darts by key, throws two darts of
    /// every group on two copies of the game, then feeds both copies the same random inputs: the events and the
    /// facts must stay equal all along. Returns the number of pairs compared.
    static func equalKeysHaveEqualFutures(_ game: GameID, _ options: GameOptions = [:], players: Int, seed: UInt64,
                                          fuzzSeed: UInt64, states: Int, hits: [Hit]) throws -> Int {
        let registry = GameRegistry.standard
        var random = SeededRandom(seed: fuzzSeed)
        var gameSeed = seed
        var match = try registry.match(game, options, players: players, seed: gameSeed)
        var pairs = 0
        for state in 0..<states {
            for _ in 0...random.nextInt(below: 4) {
                if match.phase == .turnComplete || random.nextInt(below: 6) == 0 {
                    match.endTurn()
                } else {
                    match.throwDart(DartRecord(hit: hits[random.nextInt(below: hits.count)]))
                }
            }
            if match.phase == .finished {
                gameSeed &+= 1
                match = try registry.match(game, options, players: players, seed: gameSeed)
            }
            guard match.phase == .throwing else { continue }
            // Groups in the order of `Hit.all`, so that the walk does not depend on a dictionary order.
            var groups: [(key: EffectKey, hits: [Hit])] = []
            for hit in Hit.all {
                let key = match.effectKey(for: hit)
                if let index = groups.firstIndex(where: { $0.key == key }) {
                    groups[index].hits.append(hit)
                } else {
                    groups.append((key, [hit]))
                }
            }
            let future: [GameInput] = (0..<9).map { _ in
                random.nextInt(below: 4) == 0 ? .endTurn : .dart(hits[random.nextInt(below: hits.count)])
            }
            for group in groups where group.hits.count > 1 {
                let first = group.hits[random.nextInt(below: group.hits.count)]
                let second = group.hits[random.nextInt(below: group.hits.count)]
                guard first != second else { continue }
                var one = match, other = match
                let label: Comment = "\(game) seed \(gameSeed) fuzz \(fuzzSeed) state \(state): \(first) and \(second)"
                let effects = [one.throwDart(DartRecord(hit: first)), other.throwDart(DartRecord(hit: second))].map { outcome in
                    outcome.events.filter { if case .dartRegistered = $0 { return false } else { return true } }
                }
                #expect(effects[0] == effects[1], label)
                #expect(sameObservableState(one.snapshot, other.snapshot), label)
                for input in future {
                    switch input {
                    case .dart(let hit): #expect(one.throwDart(DartRecord(hit: hit)) == other.throwDart(DartRecord(hit: hit)), label)
                    case .endTurn: #expect(one.endTurn() == other.endTurn(), label)
                    }
                    #expect(sameObservableState(one.snapshot, other.snapshot), label)
                }
                pairs += 1
            }
        }
        return pairs
    }

    /// Same, with every dart drawn uniformly from `hits`.
    static func fuzz(_ game: GameID, _ options: GameOptions = [:], players: Int, seed: UInt64, fuzzSeed: UInt64,
                     steps: Int, hits: [Hit], invariant: (GameSnapshot) -> Void = { _ in }) throws {
        try fuzz(game, options, players: players, seed: seed, fuzzSeed: fuzzSeed, steps: steps,
                 pick: { _, random in hits[random.nextInt(below: hits.count)] }, invariant: invariant)
    }
}
