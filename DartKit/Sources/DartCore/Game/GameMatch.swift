import Foundation

/// Where a dart came from.
public enum DartOrigin: String, Codable, Sendable {
    /// Tap on the virtual board.
    case manual
    /// Live camera detection.
    case camera
    /// Manual-trigger scan of a whole turn ("Scanner la volée").
    case scan
    /// Tip tapped on a photo.
    case photo
}

/// One dart of the journal: the scored hit that the engine sees, plus what the UI needs to keep with it.
public struct DartRecord: Identifiable, Hashable, Codable, Sendable {
    /// For a camera dart: the id of its `DartObservation`, so that corrections reach the vision layer.
    public let id: UUID
    public var hit: Hit
    /// Recorded impact in NOMINAL board millimetres, when known: the measured tip (camera) or the tapped point
    /// (virtual board). Nil for a dart entered by its hit only. Passed to the engine with the hit; only a
    /// position-dependent game reads it (GAMES.md §2.13). Also feeds heat maps.
    public var position: BoardPoint?
    public var origin: DartOrigin
    /// Medium-confidence detection: counted, shown as "à vérifier" until corrected or until the turn is confirmed.
    public var needsReview: Bool
    /// The player changed the hit after it was first recorded.
    public var corrected: Bool

    public init(id: UUID = UUID(), hit: Hit, position: BoardPoint? = nil, origin: DartOrigin = .manual,
                needsReview: Bool = false, corrected: Bool = false) {
        self.id = id
        self.hit = hit
        self.position = position
        self.origin = origin
        self.needsReview = needsReview
        self.corrected = corrected
    }
}

/// One entry of the journal.
public enum LogEntry: Hashable, Codable, Sendable {
    case dart(DartRecord)
    case endTurn

    public var input: GameInput {
        switch self {
        case .dart(let record): return .dart(record.hit)
        case .endTurn: return .endTurn
        }
    }

    /// Recorded position that goes to the engine with `input`; nil for `endTurn` and for a dart without one.
    public var position: BoardPoint? {
        switch self {
        case .dart(let record): return record.position
        case .endTurn: return nil
        }
    }
}

/// A game as it is saved: enough to rebuild every state.
public struct MatchRecord: Hashable, Codable, Sendable {
    public var configuration: GameConfiguration
    public var entries: [LogEntry]
    public var startedAt: Date

    public init(configuration: GameConfiguration, entries: [LogEntry] = [], startedAt: Date) {
        self.configuration = configuration
        self.entries = entries
        self.startedAt = startedAt
    }
}

/// Result of an undo or of a correction. Past events are never replayed: the UI resynchronises on `snapshot`.
public struct EditOutcome: Hashable, Sendable {
    /// False when there was nothing to edit (empty journal, index out of the current turn).
    public var applied: Bool
    /// Darts removed from the journal by the replay rule of GAMES.md §2.5 (they arrived outside `throwing`).
    public var dropped: [DartRecord]

    public init(applied: Bool, dropped: [DartRecord] = []) {
        self.applied = applied
        self.dropped = dropped
    }
}

/// Opaque equality key: two darts with the same key would have exactly the same effect if thrown now.
public struct EffectKey: Hashable, Sendable {
    let rejected: Bool
    let events: [GameEvent]
    let phase: GamePhase
    let ranks: [Int]
    let playerFacts: [[String: FactValue]]
    let facts: [String: FactValue]
}

/// A running game: one engine plus its journal. Implements undo and corrections by editing the journal and
/// replaying it from the start (GAMES.md §2.5). A value type: copy it to try something.
public struct GameMatch: Sendable {
    public let definition: GameDefinition
    /// Configuration with the options completed by their defaults.
    public let configuration: GameConfiguration
    public let startedAt: Date
    /// The journal: accepted inputs only, in order.
    public private(set) var entries: [LogEntry]
    /// Presentation of the current state; refreshed by every mutating call.
    public private(set) var snapshot: GameSnapshot
    private var engine: any GameEngine

    /// Throws `GameConfigurationError`.
    public init(definition: GameDefinition, configuration: GameConfiguration, startedAt: Date = Date()) throws {
        let engine = try definition.makeEngine(configuration)
        self.definition = definition
        self.configuration = engine.configuration
        self.startedAt = startedAt
        self.entries = []
        self.snapshot = engine.snapshot
        self.engine = engine
    }

    /// Rebuilds a saved game. Entries that the rules refuse are dropped, as in any replay.
    public init(definition: GameDefinition, record: MatchRecord) throws {
        try self.init(definition: definition, configuration: record.configuration, startedAt: record.startedAt)
        _ = replay(record.entries)
    }

    public var players: [Player] { configuration.players }
    public var phase: GamePhase { snapshot.phase }
    public var canUndo: Bool { !entries.isEmpty }

    public var record: MatchRecord {
        MatchRecord(configuration: configuration, entries: entries, startedAt: startedAt)
    }

    /// Darts of the current turn: the darts after the last `endTurn` of the journal (GAMES.md §2.5).
    /// Still editable in `turnComplete` and `finished`.
    public var currentTurn: [DartRecord] {
        entries[currentTurnStart...].compactMap {
            if case .dart(let record) = $0 { return record }
            return nil
        }
    }

    // MARK: Inputs

    /// Adds one dart, with its recorded position when it has one. Rejected outside `throwing`; a rejected dart
    /// is not logged.
    @discardableResult
    public mutating func throwDart(_ dart: DartRecord) -> InputOutcome {
        let outcome = engine.apply(.dart(dart.hit), position: dart.position)
        if outcome.isAccepted {
            entries.append(.dart(dart))
            snapshot = engine.snapshot
        }
        return outcome
    }

    /// The explicit confirmation. Clears `needsReview` on the darts of the turn that ends.
    @discardableResult
    public mutating func endTurn() -> InputOutcome {
        let outcome = engine.apply(.endTurn)
        if outcome.isAccepted {
            for index in currentTurnStart..<entries.count {
                if case .dart(var record) = entries[index] {
                    record.needsReview = false
                    entries[index] = .dart(record)
                }
            }
            entries.append(.endTurn)
            snapshot = engine.snapshot
        }
        return outcome
    }

    // MARK: Undo and corrections (journal edit + full replay)

    /// Removes the last entry, whatever it is. Unlimited depth; does nothing on an empty journal.
    @discardableResult
    public mutating func undo() -> EditOutcome {
        guard !entries.isEmpty else { return EditOutcome(applied: false) }
        return replay(Array(entries.dropLast()))
    }

    /// Replaces dart `index` (0-based) of the current turn. Keeps its `id`, clears `needsReview`,
    /// sets `corrected` when the hit changes. The whole dart is replaced, position included: `position` is
    /// recorded when the correction gives one (reticle moved, new tap) and the old one is ERASED otherwise
    /// (hit picked in a list), so a position never outlives a change of hit that does not give it again
    /// (GAMES.md §2.5).
    @discardableResult
    public mutating func replaceDart(at index: Int, with hit: Hit, position: BoardPoint? = nil) -> EditOutcome {
        guard let entryIndex = entryIndex(ofCurrentTurnDart: index), case .dart(var record) = entries[entryIndex] else {
            return EditOutcome(applied: false)
        }
        if record.hit != hit { record.corrected = true }
        record.hit = hit
        record.position = position
        record.needsReview = false
        var edited = entries
        edited[entryIndex] = .dart(record)
        return replay(edited)
    }

    /// Removes dart `index` of the current turn (phantom detection); the following darts shift.
    @discardableResult
    public mutating func removeDart(at index: Int) -> EditOutcome {
        guard let entryIndex = entryIndex(ofCurrentTurnDart: index) else { return EditOutcome(applied: false) }
        var edited = entries
        edited.remove(at: entryIndex)
        return replay(edited)
    }

    /// Sets or clears the "à vérifier" mark of dart `index` of the current turn. No replay: the hit is unchanged.
    /// Cleared when the player accepts the dart as it is; set when the camera reports that an earlier dart moved.
    public mutating func setNeedsReview(_ needsReview: Bool, at index: Int) {
        guard let entryIndex = entryIndex(ofCurrentTurnDart: index), case .dart(var record) = entries[entryIndex] else { return }
        record.needsReview = needsReview
        entries[entryIndex] = .dart(record)
    }

    // MARK: Queries

    /// Groups the darts that would have exactly the same effect if thrown now: same events (apart from
    /// `dartRegistered`), same phase, same ranks and same facts afterwards. Feeds `DartObservation.tier(collapsingBy:)`
    /// so that a doubt between two hits of equal effect does not bother the player (VISION.md §7.4).
    /// `position` is the measured tip shared by the candidate hits. A position-dependent game is keyed on
    /// (hit, position): at equal position every candidate other than MISS has the same key (GAMES.md §2.13).
    /// The other games ignore it.
    public func effectKey(for hit: Hit, position: BoardPoint? = nil) -> EffectKey {
        var copy = engine
        guard case .accepted(let events) = copy.apply(.dart(hit), position: position) else {
            return EffectKey(rejected: true, events: [], phase: snapshot.phase, ranks: [], playerFacts: [], facts: [:])
        }
        let after = copy.snapshot
        let effects = events.filter {
            if case .dartRegistered = $0 { return false }
            return true
        }
        return EffectKey(rejected: false, events: effects, phase: after.phase, ranks: after.ranks,
                         playerFacts: after.players.map(\.facts), facts: after.facts)
    }

    // MARK: Private

    private var currentTurnStart: Int {
        (entries.lastIndex { $0 == .endTurn }).map { $0 + 1 } ?? 0
    }

    private func entryIndex(ofCurrentTurnDart index: Int) -> Int? {
        guard index >= 0 else { return nil }
        var seen = 0
        for entryIndex in currentTurnStart..<entries.count {
            if case .dart = entries[entryIndex] {
                if seen == index { return entryIndex }
                seen += 1
            }
        }
        return nil
    }

    /// Replay rule of GAMES.md §2.5: start from a fresh engine, feed every entry, drop the ones that are refused.
    private mutating func replay(_ newEntries: [LogEntry]) -> EditOutcome {
        guard var fresh = try? definition.makeEngine(configuration) else { return EditOutcome(applied: false) }
        var kept: [LogEntry] = []
        var dropped: [DartRecord] = []
        for entry in newEntries {
            if fresh.apply(entry.input, position: entry.position).isAccepted {
                kept.append(entry)
            } else if case .dart(let record) = entry {
                dropped.append(record)
            }
        }
        engine = fresh
        entries = kept
        snapshot = fresh.snapshot
        return EditOutcome(applied: true, dropped: dropped)
    }
}
