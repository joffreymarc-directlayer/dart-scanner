import Foundation
import simd
import CoreGraphics
import CoreVideo
import DartCore

public enum ConfidenceTier: Int, Codable, Sendable, Comparable {
    case low, medium, high
    public static func < (lhs: ConfidenceTier, rhs: ConfidenceTier) -> Bool { lhs.rawValue < rhs.rawValue }
}

public struct ConfidenceThresholds: Hashable, Codable, Sendable {
    public var high: Double = 0.85
    public var medium: Double = 0.50
    public init() {}
    public static let standard: ConfidenceThresholds = ConfidenceThresholds()
    /// `high` from `high` up, `medium` from `medium` up, `low` below (and for a value that is not a number).
    public func tier(for confidence: Double) -> ConfidenceTier {
        if confidence >= high { return .high }
        if confidence >= medium { return .medium }
        return .low
    }
}

/// One scored hit and its probability.
public struct HitCandidate: Hashable, Sendable {
    public let hit: Hit
    public let probability: Double
    public init(hit: Hit, probability: Double) {
        self.hit = hit
        self.probability = probability
    }
}

/// Anisotropic Gaussian error of a tip, aligned with the dart axis.
public struct TipUncertainty: Hashable, Codable, Sendable {
    public var sigmaAlong: Double
    public var sigmaAcross: Double
    /// Unit vector along the dart axis in the board plane.
    public var axis: SIMD2<Double>
    public init(sigmaAlong: Double, sigmaAcross: Double, axis: SIMD2<Double>) {
        self.sigmaAlong = sigmaAlong
        self.sigmaAcross = sigmaAcross
        self.axis = axis
    }
}

public enum ObservationSource: String, Codable, Sendable {
    /// Automatic trigger on live video.
    case liveCamera
    /// Manual trigger on the tripod ("Scanner la volée").
    case scan
    /// Hand-held photo pair, differenced in board space.
    case handheldPhoto
    /// The player tapped the tip on a rectified photo or on the evidence crop.
    case tappedOnPhoto
}

/// What DartVision hands to the game layer for one dart. Vision never touches game state.
public struct DartObservation: Identifiable, Hashable, Sendable {
    public let id: UUID
    /// Visit counter since arming.
    public let visit: Int
    /// 0-based index of the dart in its visit.
    public let indexInVisit: Int
    public let timestamp: TimeInterval
    /// Tip in nominal board mm.
    public let tip: BoardPoint
    public let uncertainty: TipUncertainty
    /// Descending probability, sums to 1, at most 6 entries, never empty.
    public let candidates: [HitCandidate]
    /// Distinct hits found around the tip, nearest first; completes the correction list.
    public let nearbyHits: [Hit]
    /// `P(best) * quality`, after caps.
    public let confidence: Double
    public let tier: ConfidenceTier
    public let flags: DartFlags
    public let source: ObservationSource
    /// Memberwise: stores its twelve parameters and nothing else. Used by `ConfidenceModel`, by tests,
    /// by fakes and by the Simulator demo. Declared in the struct body, never in an extension.
    public init(id: UUID, visit: Int, indexInVisit: Int, timestamp: TimeInterval, tip: BoardPoint,
                uncertainty: TipUncertainty, candidates: [HitCandidate], nearbyHits: [Hit], confidence: Double,
                tier: ConfidenceTier, flags: DartFlags, source: ObservationSource) {
        self.id = id
        self.visit = visit
        self.indexInVisit = indexInVisit
        self.timestamp = timestamp
        self.tip = tip
        self.uncertainty = uncertainty
        self.candidates = candidates
        self.nearbyHits = nearbyHits
        self.confidence = confidence
        self.tier = tier
        self.flags = flags
        self.source = source
    }
    /// `candidates[0].hit`.
    ///
    /// An observation built by hand with no candidate (which the contract forbids) answers `MISS` instead of trapping.
    public var best: Hit {
        candidates.first?.hit ?? .miss
    }
    /// Candidates first, then `nearbyHits`, without duplicates, at least `minimum` entries when available.
    ///
    /// Every candidate is listed; nearby hits are appended, nearest first, only until the list holds `minimum`
    /// entries (VISION.md §7.5: the second candidate in one touch, then "Autre…" on the virtual board).
    public func correctionChoices(minimum: Int = 4) -> [Hit] {
        var choices: [Hit] = []
        for candidate in candidates where !choices.contains(candidate.hit) {
            choices.append(candidate.hit)
        }
        for hit in nearbyHits where choices.count < minimum && !choices.contains(hit) {
            choices.append(hit)
        }
        return choices
    }
    /// Game-aware tier, computed from stored fields only (section 7.4):
    /// `min(confidence * P(candidates with the outcome of the best) / P(best), cap(flags))`, then `thresholds.tier(for:)`.
    ///
    /// `cap(flags)` is 0.80 with `calibrationPoor` or `crossViewpoint`, 0.84 with `warmUp`, 1 otherwise: the default
    /// caps of section 7.3, re-applied so that a capped dart stays below the high tier however its candidates
    /// collapse. When `candidates[0].probability` is not positive (a hand-made observation), the collapsed value is
    /// `confidence` itself, still under the cap. A value that is not a number gives `low`.
    public func tier<Key: Hashable>(collapsingBy outcome: (Hit) -> Key,
                                    thresholds: ConfidenceThresholds = .standard) -> ConfidenceTier {
        var cap = 1.0
        if flags.contains(.calibrationPoor) || flags.contains(.crossViewpoint) { cap = min(cap, 0.80) }
        if flags.contains(.warmUp) { cap = min(cap, 0.84) }
        guard let first = candidates.first, first.probability > 0, first.probability.isFinite else {
            return thresholds.tier(for: min(confidence, cap))
        }
        let key = outcome(first.hit)
        var group = 0.0
        for candidate in candidates where outcome(candidate.hit) == key {
            group += candidate.probability
        }
        let collapsed = min(confidence * group / first.probability, cap)
        return thresholds.tier(for: collapsed)
    }
}
