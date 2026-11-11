import Foundation
import simd
import CoreGraphics
import CoreVideo
import DartCore

/// Reads a `DirectoryRecorder` directory back for offline tuning on macOS.
///
/// The directory is indexed when the session is opened; the canvases are read from their PNG files only when
/// `scenes` is read or `replay` runs, one scene at a time for `replay`. The validity mask of a canvas is not
/// stored: it is the region of interest of the recorded calibration inside the camera frame, rebuilt from
/// `calibration` exactly as the rectifier made it.
public struct RecordedSession: Sendable {
    public struct Scene: Sendable {
        public var time: TimeInterval
        public var reference: CanvasImage?
        public var current: CanvasImage
        public var gate: [GateSample]
    }

    public init(directory: URL) throws {
        let data = try Data(contentsOf: directory.appendingPathComponent(DirectoryRecorder.calibrationFile))
        recordedCalibration = try DirectoryRecorder.decoder.decode(BoardCalibration.self, from: data)
        self.directory = directory
        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .filter { $0.hasSuffix(DirectoryRecorder.analysisSuffix) }
        var entries: [CaptureRecordScene] = []
        for name in names {
            let data = try Data(contentsOf: directory.appendingPathComponent(name))
            entries.append(try DirectoryRecorder.decoder.decode(CaptureRecordScene.self, from: data))
        }
        index = entries.sorted { $0.number < $1.number }
    }

    public var calibration: BoardCalibration {
        recordedCalibration
    }

    public var scenes: [Scene] {
        let valid = validity()
        return index.compactMap { load($0, valid: valid) }
    }

    /// Runs a detector over every recorded scene with the given parameters.
    ///
    /// Each request is the recorded pair `R`, `S` with the recorded calibration: no empty reference and no known
    /// darts (the recorder does not receive them), as many new darts as the recorded analysis found (at least one).
    /// A scene whose canvas cannot be read gives `.unrecognized`.
    public func replay(detector: any DartDetecting, parameters: DetectionParameters, noiseSigma: Double) -> [SceneAnalysis] {
        let valid = validity()
        let absolute = detector.descriptor.mode == .absolute
        return index.map { entry in
            guard let scene = load(entry, valid: valid) else { return SceneAnalysis(kind: .unrecognized) }
            let request = DetectionRequest(current: scene.current, reference: absolute ? nil : scene.reference,
                                           emptyReference: nil, knownDarts: [], calibration: recordedCalibration,
                                           noiseSigma: noiseSigma, maxNewDarts: max(1, entry.darts.count),
                                           parameters: parameters)
            return detector.analyse(request)
        }
    }

    // MARK: - Internal state (lot V5)

    private let directory: URL
    private let recordedCalibration: BoardCalibration
    private let index: [CaptureRecordScene]

    /// The analyses as they were recorded, in scene order.
    var recordedAnalyses: [SceneAnalysis] {
        index.map(\.analysis)
    }

    /// Valid canvas pixels of the recorded calibration: its region of interest inside the camera frame.
    private func validity() -> GrayImage {
        let size = recordedCalibration.imageSize
        let width = max(0, size.width), height = max(0, size.height)
        let black = RGBImage(width: width, height: height, pixels: [UInt8](repeating: 0, count: width * height * 3))
        return BoardRectifier(calibration: recordedCalibration).rectify(black).valid
    }

    private func load(_ entry: CaptureRecordScene, valid: GrayImage) -> Scene? {
        let prefix = DirectoryRecorder.scenePrefix(entry.number)
        guard let current = canvas(named: prefix + DirectoryRecorder.currentSuffix, valid: valid) else { return nil }
        let reference = entry.hasReference ? canvas(named: prefix + DirectoryRecorder.referenceSuffix, valid: valid) : nil
        return Scene(time: entry.time, reference: reference, current: current, gate: entry.gate.map(\.sample))
    }

    private func canvas(named name: String, valid: GrayImage) -> CanvasImage? {
        guard let data = try? Data(contentsOf: directory.appendingPathComponent(name)),
              let image = RGBImage(pngData: data), image.width == valid.width, image.height == valid.height else { return nil }
        return CanvasImage(rgb: image, valid: valid)
    }
}
