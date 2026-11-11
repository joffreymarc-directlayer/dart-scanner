import Foundation
import Testing
import DartCore
import DartGames
import DartTestSupport

/// Shared by the test files of `Integration/` (lot I1, ARCHITECTURE.md §12.1, §13.2): games created through
/// `GameRegistry.standard` and driven through `GameMatch`, as the application does, and the replay checks that
/// every whole game ends with.
///
/// No test reads the clock: every game starts at a fixed date (ARCHITECTURE.md §4.8).
enum IntegrationSupport {
    static let registry = GameRegistry.standard
    static let startedAt = Date(timeIntervalSinceReferenceDate: 0)

    /// A new game of the registry, with players J1…Jn, started at the fixed date.
    static func match(_ game: GameID, _ options: GameOptions = [:], players: Int, seed: UInt64 = 0) throws -> GameMatch {
        let definition = try #require(registry.definition(for: game))
        let configuration = GameConfiguration(gameID: game, options: options, players: testPlayers(players), seed: seed)
        return try GameMatch(definition: definition, configuration: configuration, startedAt: startedAt)
    }

    // MARK: Facts

    static func int(_ value: FactValue?) -> Int? {
        if case .int(let number)? = value { return number }
        return nil
    }

    static func bool(_ value: FactValue?) -> Bool? {
        if case .bool(let flag)? = value { return flag }
        return nil
    }

    static func ints(_ value: FactValue?) -> [Int]? {
        if case .ints(let numbers)? = value { return numbers }
        return nil
    }

    static func table(_ value: FactValue?) -> [[Int]]? {
        if case .table(let rows)? = value { return rows }
        return nil
    }

    // MARK: Darts

    /// Throws one dart and requires the game to accept it.
    @discardableResult
    static func dart(_ hit: Hit, position: BoardPoint? = nil, needsReview: Bool = false, on match: inout GameMatch,
                     sourceLocation: SourceLocation = #_sourceLocation) -> [GameEvent] {
        let outcome = match.throwDart(DartRecord(hit: hit, position: position, needsReview: needsReview))
        #expect(outcome.isAccepted, "\(hit.notation) refused", sourceLocation: sourceLocation)
        return outcome.events
    }

    /// Requires a correction or a removal to apply without dropping any later dart.
    static func expectClean(_ outcome: EditOutcome, sourceLocation: SourceLocation = #_sourceLocation) {
        #expect(outcome.applied, sourceLocation: sourceLocation)
        #expect(outcome.dropped.isEmpty, sourceLocation: sourceLocation)
    }

    // MARK: Replay

    /// What GAMES.md §2.4 and §2.5 promise for any game, checked at the end of a whole game:
    /// - the registry rebuilds the same game from its record, and from the JSON of its record;
    /// - every prefix of the journal replays without dropping an entry;
    /// - undoing every entry gives back the initial state, and entering the journal again, input by input,
    ///   gives back the same state and the same journal;
    /// - a finished game refuses every input.
    static func checkReplay(_ match: GameMatch, sourceLocation: SourceLocation = #_sourceLocation) throws {
        let restored = try registry.restoreMatch(match.record)
        #expect(restored.entries == match.entries, sourceLocation: sourceLocation)
        #expect(restored.snapshot == match.snapshot, sourceLocation: sourceLocation)
        #expect(restored.currentTurn == match.currentTurn, sourceLocation: sourceLocation)

        let data = try JSONEncoder().encode(match.record)
        let decoded = try JSONDecoder().decode(MatchRecord.self, from: data)
        #expect(decoded == match.record, sourceLocation: sourceLocation)
        #expect(try registry.restoreMatch(decoded).snapshot == match.snapshot, sourceLocation: sourceLocation)

        for count in 0...match.entries.count {
            let prefix = Array(match.entries.prefix(count))
            let record = MatchRecord(configuration: match.configuration, entries: prefix, startedAt: match.startedAt)
            #expect(try registry.restoreMatch(record).entries == prefix, "prefix \(count)", sourceLocation: sourceLocation)
        }

        let fresh = try GameMatch(definition: match.definition, configuration: match.configuration, startedAt: match.startedAt)
        var undone = match
        while undone.canUndo {
            #expect(undone.undo().applied, sourceLocation: sourceLocation)
        }
        #expect(undone.entries.isEmpty, sourceLocation: sourceLocation)
        #expect(undone.snapshot == fresh.snapshot, sourceLocation: sourceLocation)

        var again = fresh
        for entry in match.entries {
            switch entry {
            case .dart(let record):
                #expect(again.throwDart(record).isAccepted, sourceLocation: sourceLocation)
            case .endTurn:
                #expect(again.endTurn().isAccepted, sourceLocation: sourceLocation)
            }
        }
        #expect(again.entries == match.entries, sourceLocation: sourceLocation)
        #expect(again.snapshot == match.snapshot, sourceLocation: sourceLocation)

        if match.phase == .finished {
            var closed = match
            #expect(!closed.throwDart(DartRecord(hit: .single(20))).isAccepted, sourceLocation: sourceLocation)
            #expect(!closed.endTurn().isAccepted, sourceLocation: sourceLocation)
            #expect(closed.entries == match.entries, sourceLocation: sourceLocation)
        }
    }
}
