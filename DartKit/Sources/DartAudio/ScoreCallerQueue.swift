// DartAudio — the priority rules of the score caller (ARCHITECTURE.md §7.5), as a value. No speech API in here.
import Foundation

/// Which sentence is being said and which ones wait.
///
/// | Priority | When a sentence arrives |
/// |---|---|
/// | `low` | dropped if a `normal` or `high` sentence is spoken or waits; otherwise it replaces every `low` one |
/// | `normal` | queued behind the sentence being spoken; removes the `low` ones that have not started |
/// | `high` | interrupts the sentence being spoken, empties the queue, speaks |
struct ScoreCallerQueue {
    /// One accepted sentence. `id` is unique in the life of the queue: two equal sentences stay distinct.
    struct Entry: Equatable {
        let id: Int
        let announcement: Announcement
    }

    /// At most this many sentences wait. Beyond it the oldest one goes: a score heard several seconds late is
    /// worse than a score not heard.
    static let capacity = 4

    /// The sentence being said: the driver speaks exactly this one, and interrupts whatever else it was saying.
    private(set) var current: Entry?
    /// The sentences that follow, in order.
    private(set) var waiting: [Entry] = []
    private var lastID = 0

    var isEmpty: Bool { current == nil && waiting.isEmpty }

    /// Applies the rule of the sentence's priority.
    mutating func add(_ announcement: Announcement) {
        switch announcement.priority {
        case .low:
            let isBusy = (current.map { $0.announcement.priority > .low } ?? false)
                || waiting.contains { $0.announcement.priority > .low }
            guard !isBusy else { return }
            waiting.removeAll()
            current = entry(announcement)
        case .normal:
            waiting.removeAll { $0.announcement.priority == .low }
            if current == nil {
                current = entry(announcement)
            } else {
                waiting.append(entry(announcement))
                if waiting.count > Self.capacity {
                    waiting.removeFirst(waiting.count - Self.capacity)
                }
            }
        case .high:
            waiting.removeAll()
            current = entry(announcement)
        }
    }

    /// The sentence `id` is over (said to the end, or cut): the next one becomes current.
    /// Does nothing when `id` is not the current sentence, which happens when it was replaced meanwhile.
    mutating func finish(_ id: Int) {
        guard current?.id == id else { return }
        current = waiting.isEmpty ? nil : waiting.removeFirst()
    }

    /// Forgets everything.
    mutating func removeAll() {
        current = nil
        waiting.removeAll()
    }

    private mutating func entry(_ announcement: Announcement) -> Entry {
        lastID += 1
        return Entry(id: lastID, announcement: announcement)
    }
}
