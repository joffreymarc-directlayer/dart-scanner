import Foundation
import simd
import Testing
import DartCore
import DartVision

/// Adversarial review of lot V4: a model-based random test. The reference below is a transcription of the tables of
/// VISION.md §6.3 and §6.5 at the level of whole steps (a command, an arming, an episode with its analysis, a
/// capture), written without reading the reducer. A driver plays each step on `ScanStateMachine` frame by frame,
/// answers every `.checkCalibration` and `.analyse` request from a list planned in advance, and the two must agree on
/// the state, the counters, the events, the reference updates and the number of requests. Thousands of sequences,
/// fixed seeds.
@Suite struct ReducerModelReviewTests {
    // MARK: Reference model

    private enum Rest: Hashable { case watching, awaitingTakeout, takeout }

    private enum Purpose: Hashable {
        case start(Bool), confirmEmpty, resume(Rest), recovery(Rest)
        func mapped(_ f: (Rest) -> Rest) -> Purpose {
            switch self {
            case .resume(let r): return .resume(f(r))
            case .recovery(let r): return .recovery(f(r))
            default: return self
            }
        }
    }

    private indirect enum Anchor: Hashable {
        case needsCalibration, idle(Bool), arming(Purpose), rest(Rest), lost(Anchor)
        func mapped(_ f: (Rest) -> Rest) -> Anchor {
            switch self {
            case .arming(let p): return .arming(p.mapped(f))
            case .rest(let r): return .rest(f(r))
            case .lost(let a): return .lost(a.mapped(f))
            default: return self
            }
        }
    }

    private enum Capture: Hashable { case reference, rebaseline, scan(Int) }
    private enum PoseIntent: Hashable { case takeEmpty, rebaseline }

    private enum Phase: Hashable {
        case needsCalibration
        case idle(needsEmpty: Bool)
        case arming(Purpose)
        case rest(Rest)
        case obstructed(Rest)
        /// A pose forced by a command in automatic trigger.
        case pose(PoseIntent, origin: Rest)
        case capturing(Capture, origin: Rest)
        case lost(returnTo: Anchor)
        case paused(PauseReason, from: Anchor)
    }

    private enum EmptyRef { case unknown, fresh, stale }

    private struct Model {
        var phase: Phase = .needsCalibration
        var trigger: ScanTrigger = .automatic
        var known: [(id: UUID, visit: Int)] = []
        var visit = 0, inVisit = 0, expected = 3, closed = false
        var visitIDs: Set<UUID> = []
        var emptyRef: EmptyRef = .unknown
        var unseen = false
        var streak = 0
        var armedWhileLost: Bool?

        // What one step produced.
        var events: [ScanEvent] = []
        var references: [ReferenceUpdate] = []
        var checks = 0
        var analyses: [Int] = []
        var health: [Health] = []
        var outcomes: [SettleOutcome] = []

        var countersRest: Rest { closed || inVisit >= expected ? .awaitingTakeout : .watching }

        var state: ScanState {
            switch phase {
            case .needsCalibration: return .needsCalibration
            case .idle: return .idle
            case .arming: return .arming
            case .rest(.watching): return .watching(dartsOnBoard: known.count)
            case .rest(.awaitingTakeout): return .awaitingTakeout
            case .rest(.takeout): return .takeout
            case .obstructed: return .obstructed
            case .pose, .capturing: return .settling
            case .lost: return .calibrationLost
            case .paused(let r, _): return .paused(r)
            }
        }

        var anchor: Anchor {
            switch phase {
            case .needsCalibration: return .needsCalibration
            case .idle(let n): return .idle(n)
            case .arming(let p): return .arming(p)
            case .rest(let r), .obstructed(let r), .pose(_, let r), .capturing(_, let r): return .rest(r)
            case .lost(let a): return .lost(a)
            case .paused(_, let a): return a
            }
        }

        var scanPending: Bool {
            if case .capturing(.scan, _) = phase { return true }
            return false
        }

        mutating func enterRest(_ r: Rest) {
            phase = .rest(trigger == .manual ? countersRest : r)
        }

        /// Every remembered still state goes through `f` (a counter command, §6.5).
        mutating func mapRests(_ f: (Rest) -> Rest) {
            switch phase {
            case .rest(let r): phase = .rest(trigger == .manual ? countersRest : f(r))
            case .obstructed(let r): phase = .obstructed(f(r))
            case .pose(let i, let r): phase = .pose(i, origin: f(r))
            case .capturing(let c, let r): phase = .capturing(c, origin: f(r))
            case .arming(let p): phase = .arming(p.mapped(f))
            case .lost(let a): phase = .lost(returnTo: a.mapped(f))
            case .paused(let reason, let a): phase = .paused(reason, from: a.mapped(f))
            case .needsCalibration, .idle: break
            }
        }

        mutating func resetGame() {
            known = []; visit = 0; inVisit = 0; expected = 3; closed = false; visitIDs = []
            unseen = false; emptyRef = .unknown; streak = 0
        }

        mutating func takeEmpty() {
            known = []; unseen = false; emptyRef = .fresh
            references.append(.rollingAndEmpty)
        }

        // MARK: Requests answered by the plan

        mutating func check() {
            checks += 1
            let answer = health.isEmpty ? Health(status: .healthy, recovered: false) : health.removeFirst()
            if answer.status == .healthy || answer.recovered {
                streak = 0
            } else if answer.status != .edgesNotVisible {
                streak += 1
                if streak >= 2 { lose() }
            }
        }

        mutating func analyse(_ k: Int) -> SettleOutcome {
            analyses.append(k)
            return outcomes.isEmpty ? .noChange : outcomes.removeFirst()
        }

        /// K2.
        mutating func lose() {
            let pending = scanPending
            phase = .lost(returnTo: anchor)
            streak = 0
            armedWhileLost = nil
            events.append(.calibrationLost)
            if pending { events.append(.scanCompleted([])) }
        }

        // MARK: Commands (§6.5)

        mutating func command(_ command: ScanCommand) {
            switch command {
            case .arm(let e):
                if case .paused(_, let from) = phase {
                    switch from {
                    case .needsCalibration: phase = .needsCalibration; return
                    case .lost(let a): phase = .lost(returnTo: a)
                    default: break
                    }
                }
                switch phase {
                case .needsCalibration: return
                case .lost:
                    resetGame()
                    armedWhileLost = e
                default:
                    let pending = scanPending
                    resetGame()
                    phase = .arming(.start(e))
                    if pending { events.append(.scanCompleted([])) }
                }
            case .beginVisit(let k):
                visit += 1; inVisit = 0; expected = max(0, k); closed = false; visitIDs = []
                if trigger == .manual, case .rest = phase, k == 3, emptyRef != .unknown {
                    known = []; unseen = false
                    references.append(.rollingFromEmpty)
                }
                let r = countersRest
                mapRests { _ in r }
            case .endVisit:
                closed = true
                mapRests { $0 == .takeout ? .takeout : .awaitingTakeout }
            case .discardDart(let id):
                known.removeAll { $0.id == id }
                if visitIDs.remove(id) != nil, inVisit > 0 { inVisit -= 1 }
                let r = countersRest, bare = known.isEmpty
                mapRests { current in
                    switch current {
                    case .watching: return .watching
                    case .awaitingTakeout: return r
                    case .takeout: return bare ? r : .takeout
                    }
                }
            case .registerManualDart:
                inVisit += 1; unseen = true
                let full = closed || inVisit >= expected
                mapRests { $0 == .watching && full ? .awaitingTakeout : $0 }
            case .confirmBoardEmpty:
                switch phase {
                case .idle: phase = .arming(.confirmEmpty)
                case .rest(let r): phase = trigger == .manual ? .capturing(.reference, origin: r) : .pose(.takeEmpty, origin: r)
                case .obstructed(let o): phase = .pose(.takeEmpty, origin: o)
                case .pose(_, let o): phase = .pose(.takeEmpty, origin: o)
                default: break
                }
            case .rebaseline:
                switch phase {
                case .rest(let r): phase = trigger == .manual ? .capturing(.rebaseline, origin: r) : .pose(.rebaseline, origin: r)
                case .obstructed(let o): phase = .pose(.rebaseline, origin: o)
                default: break
                }
            case .captureReference:
                if trigger == .manual, case .rest(let r) = phase { phase = .capturing(.reference, origin: r) }
            case .captureNow(let k):
                if k >= 1, trigger == .manual, case .rest(let r) = phase { phase = .capturing(.scan(k), origin: r) }
            case .setTrigger(let t):
                guard t != trigger else { return }
                trigger = t
                if t == .manual {
                    switch phase {
                    case .rest, .obstructed, .pose: enterRest(countersRest)
                    default: break
                    }
                } else {
                    switch phase {
                    case .rest(let r): phase = .arming(.resume(r))
                    case .capturing(let c, let r):
                        phase = .arming(.resume(r))
                        if case .scan = c { events.append(.scanCompleted([])) }
                    default: break
                    }
                }
            case .pause(let reason):
                if case .paused(let current, let from) = phase {
                    if reason == .user, current != .user { phase = .paused(.user, from: from) }
                    return
                }
                let pending = scanPending
                phase = .paused(reason, from: anchor)
                if pending { events.append(.scanCompleted([])) }
            case .resume:
                guard case .paused(let reason, let from) = phase, reason != .user else { return }
                switch from {
                case .needsCalibration: phase = .needsCalibration
                case .idle(let n):
                    phase = .idle(needsEmpty: n)
                    if n { events.append(.needsEmptyBoard) }
                case .lost(let a): phase = .lost(returnTo: a)
                case .arming(let p): phase = .arming(p)
                case .rest(let r): phase = .arming(.resume(r))
                }
            }
        }

        mutating func calibrationSet() {
            let pending = scanPending
            known = []; unseen = false; emptyRef = .unknown; streak = 0; armedWhileLost = nil
            phase = .idle(needsEmpty: false)
            if pending { events.append(.scanCompleted([])) }
        }

        // MARK: Analyses (tables "Issues de l'analyse" and "Issues d'un scan")

        private func knownIDs(_ ids: [UUID], excluding: [UUID] = []) -> [UUID] {
            var result: [UUID] = []
            for id in ids where !result.contains(id) && !excluding.contains(id) && known.contains(where: { $0.id == id }) {
                result.append(id)
            }
            return result
        }

        private func freshDarts(_ observations: [DartObservation]) -> [DartObservation] {
            var result: [DartObservation] = []
            for o in observations where !known.contains(where: { $0.id == o.id }) && !result.contains(where: { $0.id == o.id }) {
                result.append(o)
            }
            return result
        }

        private mutating func commit(_ fresh: [DartObservation], disturbed: Bool) -> [DartObservation] {
            let room = expected - inVisit
            var emitted: [DartObservation] = []
            for (offset, o) in fresh.enumerated() {
                var flags = o.flags
                if closed || offset >= room { flags.insert(.beyondVisitLimit) }
                if disturbed { flags.insert(.earlierDartDisturbed) }
                known.append((o.id, visit))
                visitIDs.insert(o.id)
                inVisit += 1
                emitted.append(DartObservation(id: o.id, visit: o.visit, indexInVisit: o.indexInVisit, timestamp: o.timestamp,
                                               tip: o.tip, uncertainty: o.uncertainty, candidates: o.candidates,
                                               nearbyHits: o.nearbyHits, confidence: o.confidence, tier: o.tier,
                                               flags: flags, source: o.source))
            }
            return emitted
        }

        /// A1 to A16 after an episode of `kind` from the still state `origin`.
        mutating func episodeOutcome(_ outcome: SettleOutcome, handLike: Bool, origin: Rest) {
            switch outcome {
            case .noChange:
                if !handLike { events.append(.possibleMiss(timestamp: now)) }
                enterRest(origin)
            case .darts(let new, let removed, let disturbed):
                let gone = knownIDs(removed), moved = knownIDs(disturbed, excluding: gone), fresh = freshDarts(new)
                if fresh.isEmpty {
                    if !gone.isEmpty {
                        removal(gone, boardEmpty: gone.count == known.count, moved: moved, handLike: handLike, origin: origin)
                    } else if !moved.isEmpty {
                        events += moved.map { .dartDisturbed(id: $0) }
                        references.append(.rolling)
                        enterRest(origin)
                    } else {
                        episodeOutcome(.noChange, handLike: handLike, origin: origin)
                    }
                    return
                }
                known.removeAll { gone.contains($0.id) }
                events += gone.map { .dartRemoved(id: $0, reason: .fellOut) }
                events += moved.map { .dartDisturbed(id: $0) }
                events += commit(fresh, disturbed: !gone.isEmpty || !moved.isEmpty).map { .dart($0) }
                references.append(.rolling)
                enterRest(countersRest)
            case .removed(let ids, let boardEmpty):
                var gone = knownIDs(ids)
                if boardEmpty { gone += known.map(\.id).filter { !gone.contains($0) } }
                if gone.isEmpty {
                    references.append(.rolling)
                    enterRest(origin)
                } else {
                    removal(gone, boardEmpty: boardEmpty, moved: [], handLike: handLike, origin: origin)
                }
            case .obstruction:
                phase = .obstructed(origin)
            case .lightingChanged:
                events.append(.lightingChanged)
                if known.isEmpty && !unseen {
                    emptyRef = .fresh
                    references.append(.rollingAndEmpty)
                } else {
                    if emptyRef == .fresh { emptyRef = .stale }
                    references += [.rolling, .markEmptyStale]
                }
                enterRest(origin)
            case .foreignRemoval:
                references.append(.rolling)
                enterRest(origin)
            case .unrecognized:
                events.append(.unrecognizedChange)
                references.append(.rolling)
                enterRest(origin)
            }
        }

        /// A10 first, then A7 and A8; darts of an earlier visit are pulled with `dartRemoved` only (§6.5).
        private mutating func removal(_ gone: [UUID], boardEmpty: Bool, moved: [UUID], handLike: Bool, origin: Rest) {
            let announced = origin == .takeout || known.contains { gone.contains($0.id) && $0.visit == visit }
            known.removeAll { gone.contains($0.id) }
            if !handLike {
                events += gone.map { .dartRemoved(id: $0, reason: .fellOut) }
                events += moved.map { .dartDisturbed(id: $0) }
                references.append(.rolling)
                enterRest(.watching)
                return
            }
            events += gone.map { .dartRemoved(id: $0, reason: .takeout) }
            if known.isEmpty {
                events += moved.map { .dartDisturbed(id: $0) }
                if boardEmpty {
                    if announced { events.append(.takeoutCompleted) }
                    takeEmpty()
                    enterRest(.watching)
                    check()
                } else {
                    references.append(.rolling)
                    enterRest(.watching)
                }
            } else if announced {
                if origin != .takeout { events.insert(.takeoutStarted, at: events.count - gone.count) }
                events += moved.map { .dartDisturbed(id: $0) }
                references.append(.rolling)
                enterRest(.takeout)
            } else {
                events += moved.map { .dartDisturbed(id: $0) }
                references.append(.rolling)
                enterRest(origin)
            }
        }

        /// DM3a to DM3d.
        mutating func scanOutcome(_ outcome: SettleOutcome, origin: Rest) {
            var observations: [DartObservation] = []
            switch outcome {
            case .noChange, .foreignRemoval: break
            case .obstruction: events.append(.advisory(.viewObstructed))
            case .lightingChanged: events.append(.lightingChanged)
            case .unrecognized: events.append(.unrecognizedChange)
            case .removed(let ids, let boardEmpty):
                var gone = knownIDs(ids)
                if boardEmpty { gone += known.map(\.id).filter { !gone.contains($0) } }
                if !gone.isEmpty {
                    known.removeAll { gone.contains($0.id) }
                    events += gone.map { .dartRemoved(id: $0, reason: .takeout) }
                    references.append(.rolling)
                }
            case .darts(let new, let removed, let disturbed):
                let gone = knownIDs(removed), moved = knownIDs(disturbed, excluding: gone), fresh = freshDarts(new)
                known.removeAll { gone.contains($0.id) }
                events += gone.map { .dartRemoved(id: $0, reason: .takeout) }
                events += moved.map { .dartDisturbed(id: $0) }
                observations = commit(fresh, disturbed: false)
                if !fresh.isEmpty || !gone.isEmpty { references.append(.rolling) }
            }
            events.append(.scanCompleted(observations))
            enterRest(origin)
        }

        /// Time of the step's settle input, for `possibleMiss`.
        var now: TimeInterval = 0
    }

    private struct Health { var status: CalibrationHealth.Status; var recovered: Bool }

    // MARK: Driver

    private struct Driver {
        var machine = ScanStateMachine()
        var frame = 0
        var health: [Health] = []
        var outcomes: [SettleOutcome] = []
        var checks = 0
        var analyses: [Int] = []
        var events: [ScanEvent] = []
        var references: [ReferenceUpdate] = []
        var problems: [String] = []
        /// Timestamp of the last gate sample sent.
        var lastTimestamp: TimeInterval = 0

        mutating func send(_ input: ScanInput) {
            let before = machine.state
            let effects = machine.handle(input)
            let after = machine.state
            // stateChanged first, exactly once, and only when the state changed (§6, order of events).
            let changes = effects.filter { if case .emit(.stateChanged) = $0 { return true } else { return false } }
            if before != after {
                if changes != [.emit(.stateChanged(after))] { problems.append("stateChanged \(changes) for \(before) -> \(after) on \(input)") }
                if let firstEmit = effects.first(where: { if case .emit = $0 { return true } else { return false } }),
                   firstEmit != .emit(.stateChanged(after)) {
                    problems.append("stateChanged is not the first event on \(input)")
                }
            } else if !changes.isEmpty {
                problems.append("stateChanged without a change on \(input)")
            }
            // scanCompleted is always the last effect.
            if let index = effects.firstIndex(where: { if case .emit(.scanCompleted) = $0 { return true } else { return false } }),
               index != effects.count - 1 {
                problems.append("scanCompleted is not last on \(input)")
            }
            var requests: [ScanEffect] = []
            for effect in effects {
                switch effect {
                case .emit(.stateChanged): break
                case .emit(let event): events.append(event)
                case .updateReference(let update): references.append(update)
                case .checkCalibration, .analyse: requests.append(effect)
                default: break
                }
            }
            if requests.count > 1 { problems.append("two requests in one transition: \(requests)") }
            for request in requests {
                if case .analyse(let k) = request {
                    analyses.append(k)
                    let outcome = outcomes.isEmpty ? SettleOutcome.noChange : outcomes.removeFirst()
                    send(.settle(outcome, timestamp: lastTimestamp))
                } else {
                    checks += 1
                    let answer = health.isEmpty ? Health(status: .healthy, recovered: false) : health.removeFirst()
                    send(.calibrationHealth(answer.status, recovered: answer.recovered, timestamp: lastTimestamp))
                }
            }
        }

        mutating func sample(motion: Double, change: Double) {
            lastTimestamp = Double(frame) / 30
            frame += 1
            send(.gate(GateSample(timestamp: lastTimestamp, motionFraction: motion, changeVsReference: change, borderChange: 0,
                                  meanLuma: 120)))
        }
        /// Quiet frames until the reducer asks for a drift check (row K3), at most `limit`.
        mutating func quietUntilCheck(limit: Int) {
            let before = checks
            for _ in 0..<limit where checks == before { sample(motion: 0.0001, change: 0) }
        }
        mutating func quiet(_ count: Int, change: Double = 0) { for _ in 0..<count { sample(motion: 0.0001, change: change) } }
        mutating func moving(_ count: Int) { for _ in 0..<count { sample(motion: 0.02, change: 0.02) } }
    }

    // MARK: Steps

    private enum Step {
        case calibrationSet
        case command(ScanCommand)
        /// Frames, whose meaning depends on the state: the end of an arming, an episode, a pose, a capture, a relock.
        case advance(episode: Episode, captureTimesOut: Bool)
    }

    private enum Episode { case throwDart, hand, bounce }

    /// Plays the frames of `.advance` on the model, consuming the planned answers like the driver.
    private static func advanceModel(_ m: inout Model, episode: Episode, captureTimesOut: Bool, settleTime: () -> TimeInterval) {
        switch m.phase {
        case .needsCalibration, .idle, .paused:
            break
        case .arming(let purpose):
            switch purpose {
            case .start(let e):
                m.emptyRef = e ? .fresh : .unknown
                m.references.append(e ? .rollingAndEmpty : .rolling)
                m.enterRest(.watching)
                m.check()
            case .confirmEmpty:
                m.takeEmpty()
                m.enterRest(.watching)
                m.check()
            case .resume(let r):
                if m.trigger == .automatic {
                    let outcome = m.analyse(1)
                    if outcome == .noChange {
                        m.references.append(.rolling)
                        m.enterRest(r)
                    } else {
                        m.phase = .idle(needsEmpty: true)
                        m.events.append(.needsEmptyBoard)
                    }
                } else {
                    m.enterRest(r)
                    m.check()
                }
            case .recovery(let r):
                m.references.append(.rolling)
                if !m.known.isEmpty {
                    m.references.append(.markEmptyStale)
                    if m.emptyRef == .fresh { m.emptyRef = .stale }
                }
                m.enterRest(r)
            }
        case .rest(let r), .obstructed(let r):
            var obstructed = false
            if case .obstructed = m.phase { obstructed = true }
            guard m.trigger == .automatic else { return }
            let handLike = episode == .hand || r == .takeout || obstructed
            m.check()
            if case .lost = m.phase { return }
            if episode == .bounce {
                m.now = settleTime()
                m.episodeOutcome(.noChange, handLike: handLike, origin: r)
                return
            }
            let outcome = m.analyse(1)
            m.now = settleTime()
            m.episodeOutcome(outcome, handLike: handLike, origin: r)
        case .pose(let intent, let origin):
            switch intent {
            case .takeEmpty:
                m.takeEmpty()
                m.enterRest(.watching)
                m.check()
            case .rebaseline:
                m.references.append(.rolling)
                m.enterRest(origin)
            }
        case .capturing(let kind, let origin):
            if captureTimesOut {
                m.events.append(.advisory(.viewObstructed))
                if case .scan = kind { m.events.append(.scanCompleted([])) }
                m.enterRest(origin)
                return
            }
            m.check()
            if case .lost = m.phase { return }
            switch kind {
            case .reference:
                m.takeEmpty()
                m.enterRest(origin)
            case .rebaseline:
                m.references.append(.rolling)
                m.enterRest(origin)
            case .scan(let k):
                let outcome = m.analyse(k)
                m.scanOutcome(outcome, origin: origin)
            }
        case .lost(let returnTo):
            m.checks += 1
            let answer = m.health.isEmpty ? Health(status: .healthy, recovered: false) : m.health.removeFirst()
            guard answer.status == .healthy || answer.recovered else { return }
            m.streak = 0
            if let e = m.armedWhileLost {
                m.armedWhileLost = nil
                m.phase = .arming(.start(e))
                return
            }
            switch returnTo {
            case .rest(let r): m.phase = .arming(.recovery(r))
            case .arming(let p): m.phase = .arming(p)
            case .idle(let n):
                m.phase = .idle(needsEmpty: n)
                if n { m.events.append(.needsEmptyBoard) }
            case .needsCalibration, .lost: m.phase = .idle(needsEmpty: false)
            }
        }
    }

    /// The same frames on the reducer.
    private static func advanceDriver(_ d: inout Driver, model: Model, episode: Episode, captureTimesOut: Bool) {
        switch model.phase {
        case .needsCalibration, .idle, .paused:
            d.quiet(3, change: 0.006)
        case .arming:
            d.quiet(12)
        case .rest, .obstructed:
            guard model.trigger == .automatic else { return }
            var hand = episode == .hand
            if case .obstructed = model.phase { hand = true }
            d.moving(hand ? 45 : 3)
            d.quiet(6, change: episode == .bounce ? 0 : 0.006)
        case .pose:
            d.quiet(4)
        case .capturing:
            if captureTimesOut {
                d.moving(70)
            } else {
                d.quiet(6, change: 0.006)
            }
        case .lost:
            d.quietUntilCheck(limit: 40)
        }
    }

    // MARK: Random plans

    private struct Generator {
        var random: SeededRandom
        var nextID = 1

        mutating func chance(_ p: Double) -> Bool { Double(random.next() >> 11) / 9007199254740992.0 < p }
        mutating func pick<T>(_ items: [T]) -> T { items[random.nextInt(below: items.count)] }

        mutating func id() -> UUID {
            defer { nextID += 1 }
            return UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", nextID)) ?? UUID()
        }

        mutating func observation() -> DartObservation {
            let tier: ConfidenceTier = pick([.low, .medium, .high])
            let confidence = tier == .high ? 0.9 : (tier == .medium ? 0.6 : 0.3)
            let flags: DartFlags = pick([[], [.clutter], [.warmUp, .lowTipContrast], [.beyondVisitLimit], [.earlierDartDisturbed]])
            return DartObservation(id: id(), visit: random.nextInt(below: 4), indexInVisit: random.nextInt(below: 3),
                                   timestamp: 1, tip: BoardPoint(x: 1, y: 60),
                                   uncertainty: TipUncertainty(sigmaAlong: 1, sigmaAcross: 0.5, axis: SIMD2(0, 1)),
                                   candidates: [HitCandidate(hit: .single(20), probability: confidence),
                                                HitCandidate(hit: .single(1), probability: 1 - confidence)],
                                   nearbyHits: [.single(5)], confidence: confidence, tier: tier, flags: flags, source: .liveCamera)
        }

        mutating func health() -> Health {
            switch random.nextInt(below: 20) {
            case 0, 1: return Health(status: .lost, recovered: false)
            case 2: return Health(status: .drifted, recovered: false)
            case 3: return Health(status: .drifted, recovered: true)
            case 4, 5: return Health(status: .edgesNotVisible, recovered: false)
            default: return Health(status: .healthy, recovered: false)
            }
        }

        mutating func subset(_ ids: [UUID]) -> [UUID] { ids.filter { _ in chance(0.4) } }

        mutating func outcome(known: [UUID], maxDarts: Int) -> SettleOutcome {
            switch random.nextInt(below: 20) {
            case 0, 1, 2: return .noChange
            case 3, 4, 5, 6, 7, 8, 9:
                let count = chance(0.8) ? 1 : 1 + random.nextInt(below: max(1, maxDarts + 1))
                var new = (0..<count).map { _ in observation() }
                if chance(0.1), let first = new.first { new.append(first) }
                var removed = chance(0.25) ? subset(known) : []
                if chance(0.1) { removed.append(id()) }
                let disturbed = chance(0.2) ? subset(known) : []
                if chance(0.1), let k = known.first { new.append(DartObservation(id: k, visit: 0, indexInVisit: 0, timestamp: 0,
                    tip: BoardPoint(x: 0, y: 0), uncertainty: TipUncertainty(sigmaAlong: 1, sigmaAcross: 1, axis: SIMD2(1, 0)),
                    candidates: [HitCandidate(hit: .miss, probability: 1)], nearbyHits: [], confidence: 1, tier: .high, flags: [],
                    source: .liveCamera)) }
                return .darts(new: chance(0.1) ? [] : new, removed: removed, disturbed: disturbed)
            case 10, 11, 12:
                let gone = subset(known)
                return .removed(gone + (chance(0.1) ? [id()] : []), boardEmpty: gone.count == known.count ? chance(0.8) : chance(0.1))
            case 13: return .obstruction
            case 14, 15: return .lightingChanged
            case 16: return .foreignRemoval
            default: return .unrecognized
            }
        }

        mutating func step(model: Model) -> Step {
            let knownIDs = model.known.map(\.id)
            switch random.nextInt(below: 40) {
            case 0: return .calibrationSet
            case 1, 2: return .command(.arm(boardConfirmedEmpty: chance(0.6)))
            case 3, 4: return .command(.beginVisit(expectedDarts: chance(0.8) ? 3 : random.nextInt(below: 5)))
            case 5: return .command(.endVisit)
            case 6: return .command(.discardDart(chance(0.7) && !knownIDs.isEmpty ? pick(knownIDs) : id()))
            case 7: return .command(.registerManualDart)
            case 8: return .command(.confirmBoardEmpty)
            case 9: return .command(.rebaseline)
            case 10, 11: return .command(.setTrigger(pick([.manual, .automatic])))
            case 12: return .command(.captureReference)
            case 13, 14: return .command(.captureNow(maxDarts: random.nextInt(below: 5) - 1))
            case 15, 16: return .command(.pause(pick([.user, .background, .thermal])))
            case 17, 18: return .command(.resume)
            default:
                return .advance(episode: pick([.throwDart, .throwDart, .hand, .bounce]), captureTimesOut: chance(0.1))
            }
        }
    }

    private static func describe(_ step: Step) -> String {
        switch step {
        case .calibrationSet: return "calibrationSet"
        case .command(let c): return "\(c)"
        case .advance(let e, let t): return "advance(\(e)\(t ? ", timeout" : ""))"
        }
    }

    /// What the random sequences reached, so that the test cannot pass by staying in one corner.
    private struct Coverage {
        var states: [String: Int] = [:]
        var events: [String: Int] = [:]

        mutating func note(_ state: ScanState, _ events: [ScanEvent]) {
            let name: String
            switch state {
            case .watching(let n): name = "watching(\(min(n, 3)))"
            case .paused(let r): name = "paused(\(r))"
            default: name = "\(state)"
            }
            states[name, default: 0] += 1
            for event in events {
                let key: String
                switch event {
                case .dart(let o): key = o.flags.contains(.beyondVisitLimit) ? "dart beyond" : "dart \(o.tier)"
                case .dartRemoved(_, let reason): key = "dartRemoved(\(reason))"
                case .dartDisturbed: key = "dartDisturbed"
                case .possibleMiss: key = "possibleMiss"
                case .scanCompleted(let list): key = list.isEmpty ? "scanCompleted(empty)" : "scanCompleted(darts)"
                case .advisory(let a): key = "advisory(\(a))"
                default: key = "\(event)"
                }
                self.events[key, default: 0] += 1
            }
        }
    }

    /// Plays `steps` random steps from seed `seed`; returns the first disagreement.
    private static func run(seed: UInt64, steps: Int, coverage: inout Coverage) -> String? {
        var generator = Generator(random: SeededRandom(seed: seed))
        var model = Model()
        var driver = Driver()
        var history: [String] = []
        var emittedIDs: [UUID: DartObservation] = [:]
        var injected: [UUID: DartObservation] = [:]
        for index in 0..<steps {
            // A calibration and an arming come early (after six random steps without calibration for one seed in
            // three), then everything is random.
            let opening: [Step] = [.calibrationSet, .command(.arm(boardConfirmedEmpty: true)),
                                   .advance(episode: .throwDart, captureTimesOut: false)]
            let start = seed % 3 == 0 ? 6 : 0
            let step = index >= start && index < start + opening.count ? opening[index - start] : generator.step(model: model)
            history.append(describe(step))
            // The plan: answers to every request this step may make.
            let health = (0..<4).map { _ in generator.health() }
            var maxDarts = 1
            if case .capturing(.scan(let k), _) = model.phase { maxDarts = k }
            let outcomes = (0..<3).map { _ in generator.outcome(known: model.known.map(\.id), maxDarts: maxDarts) }
            for outcome in outcomes {
                if case .darts(let new, _, _) = outcome { for o in new where injected[o.id] == nil { injected[o.id] = o } }
            }
            model.events = []; model.references = []; model.checks = 0; model.analyses = []
            model.health = health; model.outcomes = outcomes
            driver.events = []; driver.references = []; driver.checks = 0; driver.analyses = []
            driver.health = health; driver.outcomes = outcomes

            switch step {
            case .calibrationSet:
                model.calibrationSet()
                driver.send(.calibrationSet)
            case .command(let command):
                model.command(command)
                driver.send(.command(command))
            case .advance(let episode, let timeout):
                let before = model
                advanceDriver(&driver, model: before, episode: episode, captureTimesOut: timeout)
                let time = driver.lastTimestamp
                advanceModel(&model, episode: episode, captureTimesOut: timeout, settleTime: { time })
            }

            let machine = driver.machine
            coverage.note(machine.state, driver.events)
            var mismatch: [String] = driver.problems
            if machine.state != model.state { mismatch.append("state \(machine.state) instead of \(model.state)") }
            if machine.trigger != model.trigger { mismatch.append("trigger \(machine.trigger) instead of \(model.trigger)") }
            if machine.visit != model.visit || machine.dartsInVisit != model.inVisit || machine.dartsOnBoard != model.known.count {
                mismatch.append("counters \(machine.visit)/\(machine.dartsInVisit)/\(machine.dartsOnBoard) instead of \(model.visit)/\(model.inVisit)/\(model.known.count)")
            }
            if driver.events != model.events { mismatch.append("events \(driver.events) instead of \(model.events)") }
            if driver.references != model.references { mismatch.append("references \(driver.references) instead of \(model.references)") }
            if driver.checks != model.checks { mismatch.append("\(driver.checks) drift checks instead of \(model.checks)") }
            if driver.analyses != model.analyses { mismatch.append("analyses \(driver.analyses) instead of \(model.analyses)") }

            // A dart reaches the game once, with what the engine said about it: never a better tier, never twice.
            for event in driver.events {
                var observations: [DartObservation] = []
                if case .dart(let o) = event { observations = [o] }
                if case .scanCompleted(let list) = event { observations = list }
                for o in observations {
                    guard let original = injected[o.id] else { mismatch.append("dart \(o.id) was never found by the engine"); continue }
                    if emittedIDs[o.id] != nil { mismatch.append("dart \(o.id) emitted twice") }
                    emittedIDs[o.id] = o
                    if o.tier != original.tier || o.confidence != original.confidence || o.candidates != original.candidates
                        || !o.flags.isSuperset(of: original.flags)
                        || !o.flags.subtracting(original.flags).isSubset(of: [.beyondVisitLimit, .earlierDartDisturbed]) {
                        mismatch.append("dart \(o.id) rewritten: \(o) from \(original)")
                    }
                }
            }
            if !mismatch.isEmpty {
                return "seed \(seed), after \(history.suffix(8).joined(separator: " | ")): " + mismatch.joined(separator: "; ")
            }
        }
        return nil
    }

    @Test func modelBased_randomSequencesAgreeWithTheTables() {
        var failures: [String] = []
        var coverage = Coverage()
        for seed in UInt64(1)...3000 {
            if let failure = Self.run(seed: 0xBEEF_0000 &+ seed, steps: 60, coverage: &coverage) {
                failures.append(failure)
                if failures.count >= 3 { break }
            }
        }
        #expect(failures.isEmpty, "\(failures.joined(separator: "\n\n"))")
        // Every state of §6.3 and every event of the reducer is reached many times.
        let states = ["needsCalibration", "idle", "arming", "watching(0)", "watching(1)", "watching(2)", "watching(3)", "settling",
                      "awaitingTakeout", "takeout", "obstructed", "calibrationLost", "paused(user)", "paused(background)",
                      "paused(thermal)"]
        for state in states {
            #expect(coverage.states[state, default: 0] >= 50, "state \(state) reached \(coverage.states[state, default: 0]) times")
        }
        let events = ["dart low", "dart medium", "dart high", "dart beyond", "dartRemoved(fellOut)", "dartRemoved(takeout)",
                      "dartDisturbed", "possibleMiss", "takeoutStarted", "takeoutCompleted", "scanCompleted(empty)",
                      "scanCompleted(darts)", "lightingChanged", "unrecognizedChange", "needsEmptyBoard", "calibrationLost",
                      "advisory(viewObstructed)"]
        for event in events {
            #expect(coverage.events[event, default: 0] >= 50, "event \(event) seen \(coverage.events[event, default: 0]) times")
        }
    }
}
