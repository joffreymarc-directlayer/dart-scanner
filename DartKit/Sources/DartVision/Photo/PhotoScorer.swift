import Foundation
import simd
import CoreGraphics
import CoreVideo
import DartCore

/// Scoring from stills (section 8). No state, no camera.
///
/// Reads only stored fields of the calibration (`boardToImage`, `imageToBoard`, `pose`, `ringRadii`, `wireHeight`,
/// `quality`), as the detector does (VISION.md §9.3): it never calls a method of `BoardCalibration`.
public struct PhotoScorer: Sendable {
    private let detector: any DartDetecting
    private let confidence: ConfidenceModel

    public init(detector: any DartDetecting = DifferencingDartDetector(), confidence: ConfidenceModel = .init()) {
        self.detector = detector
        self.confidence = confidence
    }

    /// Rectified, zoomable view of a calibrated photo for tap-the-tips.
    public func rectified(_ photo: RGBImage, calibration: BoardCalibration) -> CanvasImage {
        BoardRectifier(calibration: calibration).rectify(photo)
    }

    /// The player tapped a tip on the photo (image pixels): the guaranteed path.
    ///
    /// The image point goes through `G`, the wire-height correction and the radial stretch, then the observation of
    /// a confirmed tip (confidence 1, source `.tappedOnPhoto`). Its identifier and timestamp are derived from the
    /// inputs, so that the same tap gives the same observation.
    public func observation(forTappedTip point: ImagePoint, calibration: BoardCalibration, visit: Int,
                            indexInVisit: Int) -> DartObservation {
        let tip = PhotoScorer.boardPoint(for: point, calibration: calibration)
        let id = PhotoScorer.identifier(calibration: calibration, visit: visit, index: indexInVisit,
                                        values: [point.x, point.y], tag: 1)
        return confidence.observation(forConfirmedTip: tip, id: id, visit: visit, indexInVisit: indexInVisit, timestamp: 0)
    }

    /// Optional layer: differences a calibrated photo against an empty-board canvas taken from another viewpoint.
    /// Every result is flagged `crossViewpoint` and capped below the high tier.
    ///
    /// Section 8.3: the photo is rectified with its own calibration and differenced against `emptyReference` in
    /// board space, with a wider blur than live (one more pass of the 3x3 box) against the wire parallax and the
    /// resampling of two viewpoints, and the peeling of D5 for up to `maxDarts` darts (at most 3). Observations
    /// have source `.handheldPhoto`, visit 0 and their order of detection. Nothing for `maxDarts <= 0`.
    public func score(photo: RGBImage, calibration: BoardCalibration, emptyReference: CanvasImage, maxDarts: Int = 3,
                      parameters: DetectionParameters = .default) -> [DartObservation] {
        guard maxDarts > 0 else { return [] }
        var wider = parameters
        wider.blurRadius = max(1, parameters.blurRadius) + PhotoScorer.extraBlur
        let current = rectified(photo, calibration: calibration)
        let request = DetectionRequest(current: current, reference: emptyReference, emptyReference: emptyReference,
                                       knownDarts: [], calibration: calibration, noiseSigma: PhotoScorer.assumedNoiseSigma,
                                       maxNewDarts: min(maxDarts, 3), parameters: wider)
        let analysis = detector.analyse(request)
        guard analysis.kind == .darts else { return [] }
        return analysis.darts.prefix(maxDarts).enumerated().map { index, found in
            var candidate = found
            candidate.flags.insert(.crossViewpoint)
            let id = PhotoScorer.identifier(calibration: calibration, visit: 0, index: index,
                                            values: [candidate.tip.x, candidate.tip.y], tag: 2)
            return confidence.observe(candidate, id: id, visit: 0, indexInVisit: index, timestamp: 0, source: .handheldPhoto,
                                      calibration: calibration, context: ConfidenceContext())
        }
    }
}

// MARK: - Helpers (lot V3)

extension PhotoScorer {
    /// Passes of the 3x3 box added to `blurRadius` for a photo pair.
    static let extraBlur = 1
    /// Noise of a single photo, levels: no arming measured it. τ then stays at its floor.
    static let assumedNoiseSigma: Double = 2

    /// Nominal board point of an image point from stored fields only: `G`, `removingParallax(height: −wireHeight)`,
    /// then `ringRadii.toNominal` (the same chain as `BoardCalibration.boardPoint(for:)`).
    static func boardPoint(for point: ImagePoint, calibration: BoardCalibration) -> BoardPoint {
        let metric = calibration.imageToBoard.apply(SIMD2(point.x, point.y))
        var board = BoardPoint(x: metric.x, y: metric.y)
        if calibration.wireHeight != 0, calibration.wireHeight.isFinite {
            board = calibration.pose.removingParallax(from: board, height: -calibration.wireHeight)
        }
        return calibration.ringRadii.toNominal(board)
    }

    /// A UUID that depends only on its inputs (FNV-1a over their bytes): no system randomness.
    static func identifier(calibration: BoardCalibration, visit: Int, index: Int, values: [Double], tag: UInt8) -> UUID {
        var first: UInt64 = 0xcbf2_9ce4_8422_2325
        var second: UInt64 = 0x8422_2325_cbf2_9ce4
        func mix(_ byte: UInt8) {
            first = (first ^ UInt64(byte)) &* 0x0000_0100_0000_01b3
            second = (second ^ UInt64(byte ^ 0x5a)) &* 0x0000_0100_0000_01b3
        }
        func mix(_ word: UInt64) {
            for shift in stride(from: 0, to: 64, by: 8) {
                mix(UInt8(truncatingIfNeeded: word >> UInt64(shift)))
            }
        }
        withUnsafeBytes(of: calibration.id.uuid) { bytes in
            for byte in bytes { mix(byte) }
        }
        mix(tag)
        mix(UInt64(bitPattern: Int64(visit)))
        mix(UInt64(bitPattern: Int64(index)))
        for value in values { mix(value.bitPattern) }
        var bytes = [UInt8](repeating: 0, count: 16)
        for i in 0..<8 {
            bytes[i] = UInt8(truncatingIfNeeded: first >> UInt64(8 * i))
            bytes[8 + i] = UInt8(truncatingIfNeeded: second >> UInt64(8 * i))
        }
        // RFC 4122 variant, version 8 (custom).
        bytes[6] = (bytes[6] & 0x0f) | 0x80
        bytes[8] = (bytes[8] & 0x3f) | 0x80
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }
}
