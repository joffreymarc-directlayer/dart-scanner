import Foundation
import simd
import CoreGraphics
import CoreVideo
import DartCore

/// Writes one directory per session: `calibration.json`, `events.jsonl`, `gate.jsonl`, `corrections.jsonl`
/// and, per analysed scene, `NNNN-reference.png`, `NNNN-current.png`, `NNNN-analysis.json`.
///
/// VISION.md §10.3. Everything is written synchronously, on the caller's thread (the session queue): this is a
/// tuning tool for debug sessions, not something to leave on during a game. `calibration.json` holds the latest
/// calibration (a relock replaces it). `NNNN-analysis.json` holds what the detector returned, the gate samples
/// since the previous scene and the time; the canvases are lossless PNGs. A write that fails is skipped: the
/// recorder never stops the session.
public final class DirectoryRecorder: ScanRecording, @unchecked Sendable {
    public init(directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        self.directory = directory
    }

    public func record(calibration: BoardCalibration) {
        guard let data = try? DirectoryRecorder.encoder.encode(calibration) else { return }
        lock.withLock {
            try? data.write(to: directory.appendingPathComponent(DirectoryRecorder.calibrationFile), options: .atomic)
        }
    }

    public func record(reference: CanvasImage?, current: CanvasImage, analysis: SceneAnalysis, gate: [GateSample], at time: TimeInterval) {
        lock.withLock {
            sceneCount += 1
            let prefix = DirectoryRecorder.scenePrefix(sceneCount)
            if let reference, let png = reference.rgb.pngData() {
                try? png.write(to: directory.appendingPathComponent(prefix + DirectoryRecorder.referenceSuffix), options: .atomic)
            }
            if let png = current.rgb.pngData() {
                try? png.write(to: directory.appendingPathComponent(prefix + DirectoryRecorder.currentSuffix), options: .atomic)
            }
            let scene = CaptureRecordScene(number: sceneCount, time: time, analysis: analysis, gate: gate,
                                               hasReference: reference != nil)
            if let data = try? DirectoryRecorder.encoder.encode(scene) {
                try? data.write(to: directory.appendingPathComponent(prefix + DirectoryRecorder.analysisSuffix), options: .atomic)
            }
            for sample in gate {
                appendLine(CaptureRecordGate(sample, scene: sceneCount), to: DirectoryRecorder.gateFile)
            }
        }
    }

    public func record(event: ScanEvent, at time: TimeInterval) {
        lock.withLock {
            appendLine(CaptureRecordEvent(event, time: time), to: DirectoryRecorder.eventsFile)
        }
    }

    public func record(correctionOf observation: DartObservation, correctedTip: BoardPoint?) {
        lock.withLock {
            appendLine(CaptureRecordCorrection(observation: CaptureRecordObservation(observation), correctedTip: correctedTip),
                       to: DirectoryRecorder.correctionsFile)
        }
    }

    // MARK: - Internal state (lot V5)

    private let directory: URL
    /// Guards `sceneCount` and the files.
    private let lock = NSLock()
    private var sceneCount = 0

    /// Appends one JSON line to `name`. Called with the lock held.
    private func appendLine<T: Encodable>(_ value: T, to name: String) {
        guard var data = try? DirectoryRecorder.lineEncoder.encode(value) else { return }
        data.append(0x0A)
        let url = directory.appendingPathComponent(name)
        if !FileManager.default.fileExists(atPath: url.path) {
            try? data.write(to: url)
            return
        }
        guard let handle = try? FileHandle(forWritingTo: url) else { return }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: data)
    }
}

// MARK: - File layout (lot V5)

extension DirectoryRecorder {
    static let calibrationFile = "calibration.json"
    static let eventsFile = "events.jsonl"
    static let gateFile = "gate.jsonl"
    static let correctionsFile = "corrections.jsonl"
    static let referenceSuffix = "-reference.png"
    static let currentSuffix = "-current.png"
    static let analysisSuffix = "-analysis.json"

    static func scenePrefix(_ number: Int) -> String {
        let digits = String(max(0, number))
        return String(repeating: "0", count: max(0, 4 - digits.count)) + digits
    }

    static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        encoder.nonConformingFloatEncodingStrategy = .convertToString(positiveInfinity: "inf", negativeInfinity: "-inf", nan: "nan")
        return encoder
    }

    static var lineEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.nonConformingFloatEncodingStrategy = .convertToString(positiveInfinity: "inf", negativeInfinity: "-inf", nan: "nan")
        return encoder
    }

    static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.nonConformingFloatDecodingStrategy = .convertFromString(positiveInfinity: "inf", negativeInfinity: "-inf", nan: "nan")
        return decoder
    }
}

/// One gate sample, as written (lot V5).
struct CaptureRecordGate: Codable, Hashable, Sendable {
    var scene: Int?
    var timestamp: Double
    var motionFraction: Double
    var changeVsReference: Double
    var borderChange: Double
    var meanLuma: Double

    init(_ sample: GateSample, scene: Int?) {
        self.scene = scene
        timestamp = sample.timestamp
        motionFraction = sample.motionFraction
        changeVsReference = sample.changeVsReference
        borderChange = sample.borderChange
        meanLuma = sample.meanLuma
    }

    var sample: GateSample {
        GateSample(timestamp: timestamp, motionFraction: motionFraction, changeVsReference: changeVsReference,
                   borderChange: borderChange, meanLuma: meanLuma)
    }
}

/// One detector candidate, as written (lot V5).
struct CaptureRecordCandidate: Codable, Sendable {
    var tip: BoardPoint
    var axis: [Double]
    var silhouette: CanvasMask
    var sigmaAlong: Double?
    var sigmaAcross: Double?
    var occlusionSpan: Double
    var visibleLength: Double
    var score: Double
    var flags: UInt32

    init(_ candidate: DartCandidate) {
        tip = candidate.tip
        axis = [candidate.axis.x, candidate.axis.y]
        silhouette = candidate.silhouette
        sigmaAlong = candidate.sigmaAlong
        sigmaAcross = candidate.sigmaAcross
        occlusionSpan = candidate.occlusionSpan
        visibleLength = candidate.visibleLength
        score = candidate.score
        flags = candidate.flags.rawValue
    }

    var candidate: DartCandidate {
        DartCandidate(tip: tip, axis: axis.count == 2 ? SIMD2(axis[0], axis[1]) : .zero, silhouette: silhouette,
                      sigmaAlong: sigmaAlong, sigmaAcross: sigmaAcross, occlusionSpan: occlusionSpan,
                      visibleLength: visibleLength, score: score, flags: DartFlags(rawValue: flags))
    }
}

/// One analysed scene, as written in `NNNN-analysis.json` (lot V5).
struct CaptureRecordScene: Codable, Sendable {
    var number: Int
    var time: Double
    var kind: String
    var darts: [CaptureRecordCandidate]
    var removed: [UUID]
    var disturbed: [UUID]
    var changedBoardFraction: Double
    var newObjectArea: Double
    var gain: Double
    var hasReference: Bool
    var gate: [CaptureRecordGate]

    init(number: Int, time: Double, analysis: SceneAnalysis, gate: [GateSample], hasReference: Bool) {
        self.number = number
        self.time = time
        kind = CaptureRecordScene.name(of: analysis.kind)
        darts = analysis.darts.map(CaptureRecordCandidate.init)
        removed = analysis.removedDartIDs
        disturbed = analysis.disturbedDartIDs
        changedBoardFraction = analysis.changedBoardFraction
        newObjectArea = analysis.newObjectArea
        self.gain = analysis.gain
        self.hasReference = hasReference
        self.gate = gate.map { CaptureRecordGate($0, scene: nil) }
    }

    static func name(of kind: SceneAnalysis.Kind) -> String {
        switch kind {
        case .noChange: return "noChange"
        case .darts: return "darts"
        case .removal: return "removal"
        case .obstruction: return "obstruction"
        case .lightingChange: return "lightingChange"
        case .foreignRemoval: return "foreignRemoval"
        case .unrecognized: return "unrecognized"
        }
    }

    static func kind(named name: String) -> SceneAnalysis.Kind? {
        let all: [SceneAnalysis.Kind] = [.noChange, .darts, .removal, .obstruction, .lightingChange, .foreignRemoval, .unrecognized]
        return all.first { self.name(of: $0) == name }
    }

    /// The analysis as the detector returned it.
    var analysis: SceneAnalysis {
        SceneAnalysis(kind: CaptureRecordScene.kind(named: kind) ?? .unrecognized, darts: darts.map(\.candidate),
                      removedDartIDs: removed, disturbedDartIDs: disturbed, changedBoardFraction: changedBoardFraction,
                      newObjectArea: newObjectArea, gain: gain)
    }
}

/// An observation, as written in `events.jsonl` and `corrections.jsonl` (lot V5).
struct CaptureRecordObservation: Codable, Sendable {
    var id: UUID
    var visit: Int
    var indexInVisit: Int
    var timestamp: Double
    var tip: BoardPoint
    var sigmaAlong: Double
    var sigmaAcross: Double
    var axis: [Double]
    var candidates: [String]
    var probabilities: [Double]
    var confidence: Double
    var tier: Int
    var flags: UInt32
    var source: String

    init(_ observation: DartObservation) {
        id = observation.id
        visit = observation.visit
        indexInVisit = observation.indexInVisit
        timestamp = observation.timestamp
        tip = observation.tip
        sigmaAlong = observation.uncertainty.sigmaAlong
        sigmaAcross = observation.uncertainty.sigmaAcross
        axis = [observation.uncertainty.axis.x, observation.uncertainty.axis.y]
        candidates = observation.candidates.map(\.hit.notation)
        probabilities = observation.candidates.map(\.probability)
        confidence = observation.confidence
        tier = observation.tier.rawValue
        flags = observation.flags.rawValue
        source = observation.source.rawValue
    }
}

/// One line of `corrections.jsonl` (lot V5).
struct CaptureRecordCorrection: Codable, Sendable {
    var observation: CaptureRecordObservation
    /// Nil when the dart was a phantom, or when the player picked another segment without moving the tip.
    var correctedTip: BoardPoint?
}

/// One line of `events.jsonl` (lot V5).
struct CaptureRecordEvent: Codable, Sendable {
    var time: Double
    var type: String
    var detail: String?
    var ids: [UUID]?
    var observations: [CaptureRecordObservation]?
    var calibration: UUID?

    init(_ event: ScanEvent, time: Double) {
        self.time = time
        switch event {
        case .stateChanged(let state):
            type = "stateChanged"
            detail = String(describing: state)
        case .dart(let observation):
            type = "dart"
            observations = [CaptureRecordObservation(observation)]
        case .dartDisturbed(let id):
            type = "dartDisturbed"
            ids = [id]
        case .dartRemoved(let id, let reason):
            type = "dartRemoved"
            ids = [id]
            detail = String(describing: reason)
        case .possibleMiss(let timestamp):
            type = "possibleMiss"
            detail = String(timestamp)
        case .takeoutStarted:
            type = "takeoutStarted"
        case .takeoutStalled(let remaining):
            type = "takeoutStalled"
            ids = remaining
        case .takeoutCompleted:
            type = "takeoutCompleted"
        case .scanCompleted(let found):
            type = "scanCompleted"
            observations = found.map(CaptureRecordObservation.init)
        case .lightingChanged:
            type = "lightingChanged"
        case .unrecognizedChange:
            type = "unrecognizedChange"
        case .needsEmptyBoard:
            type = "needsEmptyBoard"
        case .calibrationAdjusted(let calibration):
            type = "calibrationAdjusted"
            self.calibration = calibration.id
        case .calibrationLost:
            type = "calibrationLost"
        case .calibrationRecovered(let calibration):
            type = "calibrationRecovered"
            self.calibration = calibration.id
        case .advisory(let advisory):
            type = "advisory"
            detail = String(describing: advisory)
        }
    }
}
