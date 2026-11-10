import Foundation
import simd
import CoreGraphics
import CoreVideo
import DartCore

/// Reasons to doubt a detected dart. Each one lowers the confidence (section 7.3).
/// Bit positions follow the order of this list: `pointNotVisible` is `1 << 0`, `calibrationPoor` is `1 << 18`.
public struct DartFlags: OptionSet, Hashable, Codable, Sendable {
    public let rawValue: UInt32
    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }
    /// The last millimetres before the tip are wider than a point: black point, end-on dart or hidden tip.
    public static let pointNotVisible: DartFlags = DartFlags(rawValue: 1 << 0)
    public static let lowTipContrast: DartFlags = DartFlags(rawValue: 1 << 1)
    /// Longer than any dart can appear: a shadow or two objects in line.
    public static let implausiblyLong: DartFlags = DartFlags(rawValue: 1 << 2)
    public static let lowElongation: DartFlags = DartFlags(rawValue: 1 << 3)
    public static let nearEndWide: DartFlags = DartFlags(rawValue: 1 << 4)
    /// The width profile and the camera foot point disagree about which end is the tip.
    public static let tipEndAmbiguous: DartFlags = DartFlags(rawValue: 1 << 5)
    public static let fewNarrowPixels: DartFlags = DartFlags(rawValue: 1 << 6)
    /// More than 20 % of the changed pixels are outside the dart corridor.
    public static let clutter: DartFlags = DartFlags(rawValue: 1 << 7)
    /// The tip walk ran into the silhouette of an earlier dart.
    public static let tipPossiblyOccluded: DartFlags = DartFlags(rawValue: 1 << 8)
    public static let earlierDartDisturbed: DartFlags = DartFlags(rawValue: 1 << 9)
    public static let beyondVisitLimit: DartFlags = DartFlags(rawValue: 1 << 10)
    public static let emptyReferenceStale: DartFlags = DartFlags(rawValue: 1 << 11)
    public static let nearCanvasEdge: DartFlags = DartFlags(rawValue: 1 << 12)
    public static let afterRelock: DartFlags = DartFlags(rawValue: 1 << 13)
    public static let warmUp: DartFlags = DartFlags(rawValue: 1 << 14)
    /// Several darts found in one still: their order is unknown.
    public static let multiDartStill: DartFlags = DartFlags(rawValue: 1 << 15)
    /// Reference and current image were taken from different viewpoints (hand-held photo pair).
    public static let crossViewpoint: DartFlags = DartFlags(rawValue: 1 << 16)
    public static let calibrationFair: DartFlags = DartFlags(rawValue: 1 << 17)
    public static let calibrationPoor: DartFlags = DartFlags(rawValue: 1 << 18)
}

/// What a detector returns for one dart, before the confidence model.
public struct DartCandidate: Sendable {
    /// Tip in nominal board mm.
    public var tip: BoardPoint
    /// Unit vector from the tip towards the flight in the board plane; zero when unknown.
    public var axis: SIMD2<Double>
    /// Footprint of the dart in the canvas (not dilated).
    public var silhouette: CanvasMask
    /// Detector-supplied sigmas in mm; nil lets `ConfidenceModel` compute them.
    public var sigmaAlong: Double?
    public var sigmaAcross: Double?
    /// Length of the axis hidden behind earlier darts just before the tip, mm; 0 when none.
    public var occlusionSpan: Double
    /// Apparent length in the canvas, mm.
    public var visibleLength: Double
    /// Belief in 0...1 that this is a dart (1 for the differencing detector; a model can return less).
    public var score: Double
    public var flags: DartFlags
    public init(tip: BoardPoint, axis: SIMD2<Double>, silhouette: CanvasMask, sigmaAlong: Double? = nil,
                sigmaAcross: Double? = nil, occlusionSpan: Double = 0, visibleLength: Double = 0,
                score: Double = 1, flags: DartFlags = []) {
        self.tip = tip
        self.axis = axis
        self.silhouette = silhouette
        self.sigmaAlong = sigmaAlong
        self.sigmaAcross = sigmaAcross
        self.occlusionSpan = occlusionSpan
        self.visibleLength = visibleLength
        self.score = score
        self.flags = flags
    }
}

/// A dart already committed on the board.
public struct KnownDart: Identifiable, Sendable {
    public let id: UUID
    public var tip: BoardPoint
    public var silhouette: CanvasMask
    public init(id: UUID, tip: BoardPoint, silhouette: CanvasMask) {
        self.id = id
        self.tip = tip
        self.silhouette = silhouette
    }
}

public struct DetectorDescriptor: Hashable, Sendable {
    public enum Mode: Sendable {
        /// Needs a reference and returns only NEW darts (the differencing detector).
        case differential
        /// Returns ALL darts in view (a Core ML detector); the engine matches them to known darts.
        case absolute
    }
    public var name: String
    public var version: String
    public var mode: Mode
    public init(name: String, version: String, mode: Mode) {
        self.name = name
        self.version = version
        self.mode = mode
    }
}

/// Everything a detector may use for one settled scene.
public struct DetectionRequest: Sendable {
    /// Mean of the settled frames, rectified.
    public var current: CanvasImage
    /// Rolling reference: board plus the darts already committed. Nil for `.absolute` detectors or single photos.
    public var reference: CanvasImage?
    /// Board at the start of the visit; nil when stale or unknown.
    public var emptyReference: CanvasImage?
    public var knownDarts: [KnownDart]
    public var calibration: BoardCalibration
    /// Per-frame noise sigma in 8-bit levels, measured at arming.
    public var noiseSigma: Double
    /// 1 in live mode, up to 3 for stills.
    public var maxNewDarts: Int
    /// Extra dilation of known silhouettes in mm (after a relock).
    public var extraSilhouetteDilation: Double
    /// Un-rectified source image for image-space detectors; nil in live mode unless the detector asks for it.
    public var sourceImage: RGBImage?
    public var parameters: DetectionParameters
    public init(current: CanvasImage, reference: CanvasImage?, emptyReference: CanvasImage?, knownDarts: [KnownDart],
                calibration: BoardCalibration, noiseSigma: Double, maxNewDarts: Int = 1,
                extraSilhouetteDilation: Double = 0, sourceImage: RGBImage? = nil,
                parameters: DetectionParameters = .default) {
        self.current = current
        self.reference = reference
        self.emptyReference = emptyReference
        self.knownDarts = knownDarts
        self.calibration = calibration
        self.noiseSigma = noiseSigma
        self.maxNewDarts = maxNewDarts
        self.extraSilhouetteDilation = extraSilhouetteDilation
        self.sourceImage = sourceImage
        self.parameters = parameters
    }
}

/// The detector's reading of one settled scene.
public struct SceneAnalysis: Sendable {
    public enum Kind: Sendable {
        case noChange
        /// One or more dart candidates (possibly with removed or disturbed darts in the same event).
        case darts
        /// Committed darts left the board and nothing new appeared.
        case removal
        /// A hand, an arm or a person covers part of the view.
        case obstruction
        case lightingChange
        /// Something that was baked into the rolling reference left the board: no dart.
        case foreignRemoval
        /// A change that is neither a dart, a hand nor light.
        case unrecognized
    }
    public var kind: Kind
    /// New darts (differential) or all darts in view (absolute), best first.
    public var darts: [DartCandidate]
    public var removedDartIDs: [UUID]
    public var disturbedDartIDs: [UUID]
    /// Fraction of the board disc whose colour changed after gain normalisation.
    public var changedBoardFraction: Double
    /// Area of the new object in mm².
    public var newObjectArea: Double
    /// Global brightness gain between reference and current.
    public var gain: Double
    public init(kind: Kind, darts: [DartCandidate] = [], removedDartIDs: [UUID] = [], disturbedDartIDs: [UUID] = [],
                changedBoardFraction: Double = 0, newObjectArea: Double = 0, gain: Double = 1) {
        self.kind = kind
        self.darts = darts
        self.removedDartIDs = removedDartIDs
        self.disturbedDartIDs = disturbedDartIDs
        self.changedBoardFraction = changedBoardFraction
        self.newObjectArea = newObjectArea
        self.gain = gain
    }
}

/// The seam for detectors: the differencing detector today, a Core ML detector later.
public protocol DartDetecting: Sendable {
    var descriptor: DetectorDescriptor { get }
    /// True when the detector reads `DetectionRequest.sourceImage`.
    var needsSourceImage: Bool { get }
    func analyse(_ request: DetectionRequest) -> SceneAnalysis
}
