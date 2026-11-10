import Foundation
import Testing
import DartCore
import DartVision

/// Thousands of random input sequences, fixed seed: the reducer never traps, never emits an effect the tables of
/// VISION.md §6.3 forbid in the current state, and never changes what an observation says about its confidence.
@Suite struct ReducerRandomTests {
    private typealias H = ReducerHarness

    // MARK: Random inputs

    private struct Generator {
        var random: SeededRandom
        var frame = 0
        var nextDart = 1
        /// Identifiers handed to the machine so far, to build removals and discards that hit.
        var issued: [UUID] = []

        mutating func chance(_ percent: Int) -> Bool { random.nextInt(below: 100) < percent }

        mutating func pick<T>(_ values: [T]) -> T { values[random.nextInt(below: values.count)] }

        mutating func sample(motion: Double, change: Double, border: Double) -> ScanInput {
            var timestamp = Double(frame) / 30
            frame += 1
            // Rarely, a broken clock or a broken measurement: the reducer must not trap on it.
            if chance(1) { timestamp = pick([-1, .nan, .infinity, timestamp - 5, timestamp + 1000]) }
            var motionFraction = motion
            if chance(1) { motionFraction = pick([.nan, -1, .infinity, 1]) }
            return .gate(GateSample(timestamp: timestamp, motionFraction: motionFraction, changeVsReference: change,
                                    borderChange: border, meanLuma: 120))
        }

        mutating func observation() -> DartObservation {
            let tier = pick([ConfidenceTier.high, .high, .medium, .low])
            let flags = pick([DartFlags(), [.clutter], [.multiDartStill], [.warmUp, .tipEndAmbiguous], [.beyondVisitLimit]])
            let number = chance(8) && nextDart > 1 ? 1 + random.nextInt(below: nextDart - 1) : nextDart
            if number == nextDart { nextDart += 1 }
            let made = H.observation(number, tier: tier, flags: flags, source: pick([.liveCamera, .scan]))
            issued.append(made.id)
            return made
        }

        mutating func someIDs() -> [UUID] {
            var ids: [UUID] = []
            for _ in 0..<random.nextInt(below: 4) {
                if !issued.isEmpty, chance(85) { ids.append(pick(issued)) } else { ids.append(H.id(900 + random.nextInt(below: 5))) }
            }
            return ids
        }

        mutating func outcome() -> SettleOutcome {
            switch random.nextInt(below: 12) {
            case 0, 1: return .noChange
            case 2, 3, 4:
                let count = pick([1, 1, 1, 2, 3, 0])
                return .darts(new: (0..<count).map { _ in observation() }, removed: chance(20) ? someIDs() : [],
                              disturbed: chance(20) ? someIDs() : [])
            case 5, 6: return .removed(someIDs(), boardEmpty: chance(50))
            case 7: return .removed(issued, boardEmpty: true)
            case 8: return .obstruction
            case 9: return .lightingChanged
            case 10: return .foreignRemoval
            default: return .unrecognized
            }
        }

        mutating func command() -> ScanCommand {
            switch random.nextInt(below: 26) {
            case 0, 1: return .arm(boardConfirmedEmpty: chance(70))
            case 2, 3, 4: return .beginVisit(expectedDarts: pick([3, 3, 3, 1, 2, 0, -1]))
            case 5: return .endVisit
            case 6, 7: return .confirmBoardEmpty
            case 8: return .rebaseline
            case 9: return .discardDart(issued.isEmpty || chance(20) ? H.id(950) : pick(issued))
            case 10: return .registerManualDart
            case 11, 12: return .setTrigger(pick([.automatic, .manual]))
            case 13, 14: return .captureReference
            case 15, 16, 17, 18: return .captureNow(maxDarts: pick([3, 3, 2, 1, 0, -2]))
            case 19, 20: return .pause(pick([.user, .background, .thermal]))
            case 21, 22, 23: return .resume
            default: return .arm(boardConfirmedEmpty: true)
            }
        }

        mutating func quiet(_ count: Int, change: Double) -> [ScanInput] {
            (0..<count).map { _ in sample(motion: 0.0001, change: change, border: 0) }
        }

        mutating func moving(_ count: Int, border: Double = 0) -> [ScanInput] {
            (0..<count).map { _ in sample(motion: 0.02, change: 0.05, border: border) }
        }

        mutating func settle() -> ScanInput { .settle(outcome(), timestamp: Double(frame) / 30) }

        /// A plausible piece of a game: it makes the walk reach the deep states. Sometimes cut short, so that
        /// the next step falls in the middle of it.
        mutating func scenario() -> [ScanInput] {
            var inputs: [ScanInput]
            switch random.nextInt(below: 14) {
            case 0:
                // Start of a game.
                inputs = chance(40) ? [.calibrationSet] : []
                inputs.append(.command(.setTrigger(chance(65) ? .automatic : .manual)))
                inputs.append(.command(.arm(boardConfirmedEmpty: chance(75))))
                inputs += quiet(12, change: 0)
                inputs.append(.command(.beginVisit(expectedDarts: 3)))
            case 1, 2, 3:
                // A throw.
                inputs = moving(2 + random.nextInt(below: 7)) + quiet(6, change: 0.006) + [settle()]
            case 4, 5:
                // A hand.
                inputs = moving(25 + random.nextInt(below: 40), border: pick([0, 0.06])) + quiet(6, change: 0.01) + [settle()]
            case 6, 7:
                // A scan.
                inputs = [.command(pick([.captureNow(maxDarts: 3), .captureNow(maxDarts: 1), .captureReference, .rebaseline]))]
                inputs += quiet(6, change: 0) + [settle()]
            case 8:
                // Next visit.
                inputs = [.command(chance(30) ? .endVisit : .registerManualDart), .command(.beginVisit(expectedDarts: 3))]
            case 9:
                // Background and back.
                inputs = [.command(.pause(pick([.background, .thermal]))), .command(.resume)] + quiet(12, change: 0) + [settle()]
            case 10:
                // A pose whose drift check answers.
                inputs = moving(3) + quiet(2, change: 0.006)
                inputs.append(.calibrationHealth(pick([.lost, .lost, .healthy, .drifted, .edgesNotVisible]),
                                                 recovered: chance(25), timestamp: Double(frame) / 30))
                inputs += quiet(4, change: 0.006) + [settle()]
            case 11:
                // A hand that stays in view more than ten seconds, its edges hidden: every check answers so.
                inputs = moving(30 + random.nextInt(below: 20)) + quiet(6, change: 0.2)
                inputs.append(.settle(.obstruction, timestamp: Double(frame) / 30))
                for _ in 0..<(4 + random.nextInt(below: 4)) {
                    inputs += quiet(61, change: 0.2)
                    inputs.append(.calibrationHealth(.edgesNotVisible, recovered: false, timestamp: Double(frame) / 30))
                }
            case 12:
                // A hand pulls one dart, then nothing moves for more than five seconds.
                inputs = moving(30 + random.nextInt(below: 20)) + quiet(6, change: 0.01)
                let pulled = issued.isEmpty ? [] : [pick(issued)]
                inputs.append(.settle(.removed(pulled, boardEmpty: false), timestamp: Double(frame) / 30))
                inputs += quiet(160 + random.nextInt(below: 40), change: 0)
            default:
                // A still obstruction, long enough for its drift check, then the frames its verdict asks for.
                inputs = quiet(70, change: 0.2)
                inputs.append(.calibrationHealth(pick([.healthy, .healthy, .drifted, .lost, .edgesNotVisible]),
                                                 recovered: chance(40), timestamp: Double(frame) / 30))
                inputs += quiet(6, change: 0.2)
                if chance(50) { inputs.append(settle()) }
            }
            if chance(12), inputs.count > 1 { inputs.removeLast(1 + random.nextInt(below: inputs.count - 1)) }
            return inputs
        }

        /// One step of the walk: a scenario, a burst of frames, or one other input.
        mutating func burst() -> [ScanInput] {
            switch random.nextInt(below: 100) {
            case 0..<12:
                let change = pick([0, 0.0001, 0.006, 0.006, 0.2])
                return quiet(1 + random.nextInt(below: 14), change: change)
            case 12..<20:
                return moving(1 + random.nextInt(below: 8), border: pick([0, 0, 0.06]))
            case 20..<23:
                return (0..<(40 + random.nextInt(below: 260))).map { _ in sample(motion: 0.03, change: 0.2, border: 0.06) }
            case 23..<29:
                return quiet(60 + random.nextInt(below: 280), change: pick([0, 0.001, 0.2]))
            case 29..<31:
                return [sample(motion: 0.0008, change: 0.001, border: 0)]
            case 31..<37:
                return [settle()]
            case 37..<42:
                return [.calibrationHealth(pick([.healthy, .drifted, .lost, .lost, .edgesNotVisible]), recovered: chance(35),
                                           timestamp: Double(frame) / 30)]
            case 42..<43:
                return [.calibrationSet]
            case 43..<44:
                return [.armed]
            case 44..<56:
                return [.command(command())]
            default:
                return scenario()
            }
        }
    }

    // MARK: Oracle

    private enum Kind: Hashable {
        case needsCalibration, idle, arming, watching, motion, settling, analysing, awaitingTakeout, takeout, obstructed,
             calibrationLost, paused
    }

    private static func kind(_ state: ScanState) -> Kind {
        switch state {
        case .needsCalibration: return .needsCalibration
        case .idle: return .idle
        case .arming: return .arming
        case .watching: return .watching
        case .motion: return .motion
        case .settling: return .settling
        case .analysing: return .analysing
        case .awaitingTakeout: return .awaitingTakeout
        case .takeout: return .takeout
        case .obstructed: return .obstructed
        case .calibrationLost: return .calibrationLost
        case .paused: return .paused
        }
    }

    private static func eventName(_ event: ScanEvent) -> String {
        switch event {
        case .stateChanged: return "stateChanged"
        case .dart: return "dart"
        case .dartDisturbed: return "dartDisturbed"
        case .dartRemoved(_, let reason): return reason == .fellOut ? "dartRemoved.fellOut" : "dartRemoved.takeout"
        case .possibleMiss: return "possibleMiss"
        case .takeoutStarted: return "takeoutStarted"
        case .takeoutStalled: return "takeoutStalled"
        case .takeoutCompleted: return "takeoutCompleted"
        case .scanCompleted(let observations): return observations.isEmpty ? "scanCompleted.empty" : "scanCompleted.darts"
        case .lightingChanged: return "lightingChanged"
        case .unrecognizedChange: return "unrecognizedChange"
        case .needsEmptyBoard: return "needsEmptyBoard"
        case .calibrationAdjusted: return "calibrationAdjusted"
        case .calibrationLost: return "calibrationLost"
        case .calibrationRecovered: return "calibrationRecovered"
        case .advisory(let advisory): return "advisory.\(advisory)"
        }
    }

    /// Events each kind of input may produce besides `stateChanged`, whatever the state.
    private static let gateEvents: Set<String> = ["possibleMiss", "takeoutStalled", "advisory.viewObstructed", "scanCompleted.empty",
                                                  "unrecognizedChange"]
    private static let healthEvents: Set<String> = ["calibrationLost", "unrecognizedChange", "advisory.viewObstructed",
                                                    "needsEmptyBoard", "scanCompleted.empty"]
    private static let commandEvents: Set<String> = ["needsEmptyBoard", "scanCompleted.empty"]
    private static let episodeEvents: Set<String> = ["possibleMiss", "takeoutStarted", "takeoutStalled", "takeoutCompleted",
                                                     "dartRemoved.fellOut", "dart"]

    /// The same observation up to the two flags the reducer may add (rows A3 and A4).
    private static func sameReading(_ emitted: DartObservation, _ supplied: DartObservation) -> Bool {
        emitted.id == supplied.id && emitted.tier == supplied.tier && emitted.confidence == supplied.confidence
            && emitted.candidates == supplied.candidates && emitted.nearbyHits == supplied.nearbyHits
            && emitted.tip == supplied.tip && emitted.uncertainty == supplied.uncertainty && emitted.source == supplied.source
            && emitted.visit == supplied.visit && emitted.indexInVisit == supplied.indexInVisit
            && emitted.timestamp == supplied.timestamp && emitted.flags.isSuperset(of: supplied.flags)
            && emitted.flags.subtracting(supplied.flags).isSubset(of: [.beyondVisitLimit, .earlierDartDisturbed])
    }

    /// Checks one transition against the rules of §6 and §6.3. Returns the rules it breaks.
    private static func violations(before: ScanState, triggerBefore: ScanTrigger, input: ScanInput, effects: [ScanEffect],
                                   after machine: ScanStateMachine) -> [String] {
        var broken: [String] = []
        let after = machine.state
        if effects.isEmpty {
            // Nothing was said: only the state and the counters can be wrong.
            if after != before { broken.append("state changed without stateChanged") }
            if machine.dartsOnBoard < 0 || machine.dartsInVisit < 0 || machine.visit < 0 { broken.append("negative counter") }
            if case .command(.pause(let reason)) = input, kind(before) != .paused, after != .paused(reason) {
                broken.append("pause(\(reason)) gave \(after)")
            }
            return broken
        }
        let events = H.events(effects)
        let names = events.map(eventName)
        let work = H.work(effects)
        let from = kind(before)

        // Shape of the list (§6: `stateChanged` first; one request at most; `scanCompleted` last).
        let changes = events.filter { if case .stateChanged = $0 { return true } else { return false } }
        if after != before {
            if changes != [.stateChanged(after)] { broken.append("state changed without exactly one stateChanged(new)") }
            if events.first != .stateChanged(after) { broken.append("stateChanged is not the first event") }
        } else if !changes.isEmpty {
            broken.append("stateChanged without a state change")
        }
        if work.filter({ $0 == .discardAccumulation }).count > 1 || (work.contains(.discardAccumulation) && effects.first != .discardAccumulation) {
            broken.append("discardAccumulation not first or repeated")
        }
        let requests = work.filter { effect in
            if case .analyse = effect { return true }
            return effect == .checkCalibration
        }
        if requests.count > 1 { broken.append("more than one request") }
        let scans = names.filter { $0.hasPrefix("scanCompleted") }
        if scans.count > 1 { broken.append("more than one scanCompleted") }
        if let last = effects.last, !scans.isEmpty {
            if case .emit(.scanCompleted) = last {} else { broken.append("scanCompleted is not last") }
        }
        if let request = requests.first, scans.isEmpty, effects.last != request { broken.append("the request is not last") }
        if !H.analyses(effects).isEmpty, after != .analysing { broken.append("analyse outside analysing") }
        if names.contains("calibrationAdjusted") || names.contains("calibrationRecovered") {
            broken.append("the reducer emitted an engine event")
        }

        // Which input may say what.
        let facts = Set(names.filter { $0 != "stateChanged" })
        switch input {
        case .gate:
            if !facts.isSubset(of: gateEvents) { broken.append("gate sample emitted \(facts)") }
            if !H.analyses(effects).isEmpty, ![.settling, .arming].contains(from) { broken.append("analyse from \(from) on a sample") }
        case .calibrationHealth:
            if !facts.isSubset(of: healthEvents) { broken.append("health emitted \(facts)") }
        case .command(let command):
            if !facts.isSubset(of: commandEvents) { broken.append("command emitted \(facts)") }
            if !requests.isEmpty { broken.append("command \(command) made a request") }
        case .calibrationSet:
            if !facts.isSubset(of: ["scanCompleted.empty"]) || after != .idle { broken.append("calibrationSet: \(facts), \(after)") }
        case .armed:
            if from != .arming, !effects.isEmpty { broken.append("armed outside arming had effects") }
        case .settle:
            if from != .analysing, !effects.isEmpty { broken.append("settle outside analysing had effects") }
        }

        // States where frames, outcomes and checks are ignored.
        let passive: Bool
        switch input {
        case .gate, .settle, .calibrationHealth, .armed: passive = true
        case .command, .calibrationSet: passive = false
        }
        if passive, [.needsCalibration, .idle, .paused].contains(from), !effects.isEmpty {
            broken.append("\(from) reacted to \(input)")
        }
        if case .gate = input, triggerBefore == .manual, [.watching, .awaitingTakeout].contains(from), !effects.isEmpty {
            broken.append("a frame was processed at rest in manual trigger")
        }
        // No calibration: nothing but state changes. Lost calibration: no dart event at all (K2).
        if from == .needsCalibration, !facts.isEmpty || !work.isEmpty { broken.append("needsCalibration produced \(effects)") }
        if from == .calibrationLost {
            if !facts.isSubset(of: ["needsEmptyBoard"]) { broken.append("calibrationLost emitted \(facts)") }
            if !H.references(effects).isEmpty || !H.analyses(effects).isEmpty { broken.append("calibrationLost touched references") }
        }
        if from == .paused {
            if !facts.isSubset(of: ["needsEmptyBoard", "scanCompleted.empty"]) { broken.append("paused emitted \(facts)") }
            if !H.references(effects).isEmpty || !requests.isEmpty { broken.append("paused touched references") }
            if before == .paused(.user), input == .command(.resume), !effects.isEmpty || after != before {
                broken.append("resume left paused(.user)")
            }
        }
        if case .paused = after, from != .paused {
            if case .command(.pause) = input {} else { broken.append("paused without a pause command") }
        }
        if from != .paused, case .command(.pause(let reason)) = input, after != .paused(reason) {
            broken.append("pause(\(reason)) gave \(after)")
        }
        // P1b: in a pause, a second pause only ever turns a system pause into `paused(.user)`.
        if from == .paused, case .command(.pause(let reason)) = input {
            let expected: ScanState = reason == .user ? .paused(.user) : before
            if after != expected { broken.append("P1b: pause(\(reason)) in \(before) gave \(after)") }
        }

        // Triggers: no episode event and no `dart` in manual trigger; no scan result in automatic trigger.
        if triggerBefore == .manual, machine.trigger == .manual, !facts.isDisjoint(with: episodeEvents) {
            broken.append("manual trigger emitted \(facts)")
        }
        if triggerBefore == .automatic, !scans.isEmpty { broken.append("automatic trigger emitted a scan result") }
        if case .gate = input, names.contains("scanCompleted.empty"), from != .settling { broken.append("capture timeout outside settling") }
        if case .gate = input, names.contains("unrecognizedChange"), from != .obstructed {
            broken.append("unrecognizedChange on a frame outside obstructed (A13)")
        }

        // References (§6.4): `E` is never taken with darts on the board; a complete takeout retakes it.
        if work.contains(.updateReference(.rollingAndEmpty)) || work.contains(.updateReference(.rollingFromEmpty)) {
            if machine.dartsOnBoard != 0 { broken.append("empty reference used with known darts on the board") }
        }
        if names.contains("takeoutCompleted") {
            if !work.contains(.updateReference(.rollingAndEmpty)) || after != .watching(dartsOnBoard: 0) {
                broken.append("takeoutCompleted without the empty reference")
            }
        }
        if names.contains("needsEmptyBoard") {
            if after != .idle || !H.references(effects).isEmpty { broken.append("needsEmptyBoard outside idle") }
            if after != before, Array(names.prefix(2)) != ["stateChanged", "needsEmptyBoard"] {
                broken.append("needsEmptyBoard does not follow stateChanged(.idle)")
            }
        }
        if names.contains("calibrationLost"), after != .calibrationLost { broken.append("calibrationLost event in \(after)") }
        if names.contains("takeoutStarted"), after != .takeout { broken.append("takeoutStarted in \(after)") }
        if names.contains("takeoutStalled"), from != .takeout || after != .awaitingTakeout { broken.append("takeoutStalled \(from) -> \(after)") }

        // Observations: only an analysis outcome carries them, and the reducer passes them on as they are.
        var supplied: [DartObservation] = []
        if case .settle(.darts(let new, _, _), _) = input, from == .analysing { supplied = new }
        var emitted: [DartObservation] = []
        for event in events {
            switch event {
            case .dart(let observation): emitted.append(observation)
            case .scanCompleted(let observations): emitted.append(contentsOf: observations)
            default: break
            }
        }
        for observation in emitted {
            if !supplied.contains(where: { sameReading(observation, $0) }) {
                broken.append("observation \(observation.id) emitted but not supplied as such (tier \(observation.tier))")
            }
        }
        if Set(emitted.map(\.id)).count != emitted.count { broken.append("an observation was emitted twice") }

        // Counters.
        if machine.dartsOnBoard < 0 || machine.dartsInVisit < 0 || machine.visit < 0 { broken.append("negative counter") }
        if case .watching(let count) = after, count != machine.dartsOnBoard { broken.append("watching(n) differs from dartsOnBoard") }
        if after == .takeout, machine.dartsOnBoard == 0 { broken.append("takeout without a known dart") }
        return broken
    }

    // MARK: Tests

    private static func inputName(_ input: ScanInput) -> String {
        switch input {
        case .calibrationSet: return "calibrationSet"
        case .gate: return "gate"
        case .armed: return "armed"
        case .settle: return "settle"
        case .calibrationHealth: return "health"
        case .command: return "command"
        }
    }

    private struct Run {
        var effects: [[ScanEffect]] = []
        var finalState: ScanState = .needsCalibration
        var states: Set<Kind> = []
        var events: Set<String> = []
        /// `input:event` pairs seen, to show which paths the walk exercised.
        var paths: Set<String> = []
        var broken: [String] = []
        var lowTierDartsEmitted = 0
    }

    private func run(seed: UInt64, steps: Int, parameters: ScanParameters = .init(), keepEffects: Bool = false) -> Run {
        var generator = Generator(random: SeededRandom(seed: seed))
        var machine = ScanStateMachine(parameters: parameters)
        var result = Run()
        /// `captureNow` commands accepted and not answered yet: 0 or 1.
        var owedScans = 0
        /// The last still state the machine was seen in; nil after a command that changes what it means.
        var lastStill: Kind?
        if generator.chance(85) { _ = machine.handle(.calibrationSet) }
        for step in 0..<steps {
            for input in generator.burst() {
                let before = machine.state
                let triggerBefore = machine.trigger
                let effects = machine.handle(input)
                if keepEffects { result.effects.append(effects) }
                let broken = Self.violations(before: before, triggerBefore: triggerBefore, input: input, effects: effects,
                                             after: machine)
                for rule in broken where result.broken.count < 5 {
                    result.broken.append("seed \(seed) step \(step) \(before) + \(input): \(rule)")
                }
                // Exactly one `scanCompleted` per accepted `captureNow`.
                if case .command(.captureNow(let maxDarts)) = input, maxDarts >= 1, triggerBefore == .manual,
                   before != machine.state, machine.state == .settling {
                    owedScans += 1
                }
                for event in H.events(effects) {
                    result.events.insert(Self.eventName(event))
                    result.paths.insert("\(Self.inputName(input)):\(Self.eventName(event))")
                    if case .scanCompleted(let observations) = event {
                        owedScans -= 1
                        result.lowTierDartsEmitted += observations.filter { $0.tier == .low }.count
                    }
                    if case .dart(let observation) = event, observation.tier == .low { result.lowTierDartsEmitted += 1 }
                }
                if owedScans < 0 || owedScans > 1, result.broken.count < 5 {
                    result.broken.append("seed \(seed) step \(step): \(owedScans) scanCompleted owed after \(input)")
                    owedScans = max(0, min(1, owedScans))
                }
                let capturing = machine.state == .settling || machine.state == .analysing
                if owedScans == 1, !capturing, result.broken.count < 5 {
                    result.broken.append("seed \(seed) step \(step): a capture ended without scanCompleted after \(input)")
                    owedScans = 0
                }
                // Manual trigger: the only analysis is the one of an accepted `captureNow` (DM3; DM7 has none).
                if machine.trigger == .manual, !H.analyses(effects).isEmpty, owedScans != 1, result.broken.count < 5 {
                    result.broken.append("seed \(seed) step \(step): analysis in manual trigger without a scan after \(input)")
                }
                // A8: `takeoutStarted` once per takeout; an episode that leaves `takeout` never announces another one.
                if H.facts(effects).contains(.takeoutStarted), lastStill == .takeout, result.broken.count < 5 {
                    result.broken.append("seed \(seed) step \(step): a second takeoutStarted after \(input)")
                }
                switch input {
                case .command(.beginVisit), .command(.discardDart): lastStill = nil
                default: break
                }
                let afterKind = Self.kind(machine.state)
                if [.watching, .awaitingTakeout, .takeout, .obstructed].contains(afterKind) { lastStill = afterKind }
                if machine.state != before { result.states.insert(Self.kind(machine.state)) }
            }
        }
        result.finalState = machine.state
        return result
    }

    @Test func randomSequences_neverTrap_neverBreakTheTables_neverRewriteAnObservation() {
        var states: Set<Kind> = []
        var events: Set<String> = []
        var paths: Set<String> = []
        var broken: [String] = []
        var lowTierDarts = 0
        for seed in 1...2000 {
            let result = run(seed: UInt64(seed), steps: 36)
            states.formUnion(result.states)
            events.formUnion(result.events)
            paths.formUnion(result.paths)
            lowTierDarts += result.lowTierDartsEmitted
            if broken.count < 5 { broken.append(contentsOf: result.broken) }
        }
        #expect(broken.isEmpty, "\(broken.prefix(5).joined(separator: "\n"))")
        // The walk is not vacuous: every state was reached and every event the reducer can emit was seen,
        // low-confidence darts included (they were emitted as low-confidence darts, never promoted).
        #expect(states.count == 12, "\(states)")
        let expected: Set<String> = ["stateChanged", "dart", "dartDisturbed", "dartRemoved.fellOut", "dartRemoved.takeout",
                                     "possibleMiss", "takeoutStarted", "takeoutStalled", "takeoutCompleted",
                                     "scanCompleted.empty", "scanCompleted.darts", "lightingChanged", "unrecognizedChange",
                                     "needsEmptyBoard", "calibrationLost", "advisory.viewObstructed"]
        #expect(events == expected, "\(events.symmetricDifference(expected))")
        // The paths that only a long walk reaches: A9, A13 healthy and edgeless, DM6, captures cut by a command or a
        // loss, K2 from a check, P2 on a changed scene, P2b after `needsEmptyBoard`.
        let deepPaths: Set<String> = ["gate:takeoutStalled", "gate:unrecognizedChange", "gate:advisory.viewObstructed",
                                      "gate:scanCompleted.empty", "command:scanCompleted.empty", "health:calibrationLost",
                                      "health:advisory.viewObstructed", "health:scanCompleted.empty",
                                      "settle:needsEmptyBoard", "command:needsEmptyBoard", "calibrationSet:scanCompleted.empty"]
        #expect(deepPaths.isSubset(of: paths), "\(deepPaths.subtracting(paths))")
        #expect(lowTierDarts > 100)
    }

    @Test func randomSequences_withUnusualParameters_neverTrap() {
        // Degenerate constants must not trap either: zero frames, zero timers, a manual start, no darts expected.
        var variants: [ScanParameters] = []
        var zero = ScanParameters()
        zero.skipFrames = 0
        zero.settleFrames = 0
        zero.armingFrames = 0
        zero.idleCheckInterval = 0
        zero.idleRefreshInterval = 0
        zero.takeoutStallInterval = 0
        zero.obstructionEscalation = 0
        zero.obstructionAdvisoryDelay = 0
        zero.motionTimeout = 0
        zero.relockRetryInterval = 0
        zero.captureTimeout = 0
        zero.expectedDartsPerVisit = 0
        variants.append(zero)
        var odd = ScanParameters()
        odd.trigger = .manual
        odd.skipFrames = 9
        odd.settleFrames = 3
        odd.armingFrames = 2
        odd.expectedDartsPerVisit = -3
        odd.handSustainFrames = 0
        odd.throwMaxDuration = -1
        variants.append(odd)
        var negative = ScanParameters()
        negative.skipFrames = -5
        negative.settleFrames = -5
        negative.armingFrames = -5
        negative.captureTimeout = -1
        negative.quietFraction = .nan
        negative.motionOnFraction = -1
        variants.append(negative)
        for (index, parameters) in variants.enumerated() {
            for seed in 1...150 {
                let result = run(seed: UInt64(1000 * (index + 1) + seed), steps: 40, parameters: parameters)
                #expect(result.broken.filter { $0.contains("negative counter") || $0.contains("watching(n)") }.isEmpty)
            }
        }
    }

    @Test func sameInputsTwice_giveTheSameEffects() {
        for seed: UInt64 in [7, 77, 777] {
            let first = run(seed: seed, steps: 60, keepEffects: true)
            let second = run(seed: seed, steps: 60, keepEffects: true)
            #expect(first.effects == second.effects && first.finalState == second.finalState && !first.effects.isEmpty)
        }
    }
}
