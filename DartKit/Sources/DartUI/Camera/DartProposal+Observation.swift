import Foundation
import simd
import DartCore
import DartVision

extension DartProposal {
    /// A dart seen by DartVision. `hit` is `observation.best`, `position` its tip, `choices` its
    /// `correctionChoices()`; `origin` follows `observation.source` (liveCamera → camera, scan → scan,
    /// handheldPhoto and tappedOnPhoto → photo). Certainty: high → certain, medium → needsReview, low → undecided,
    /// on `observation.tier(collapsingBy: { match.effectKey(for: $0, position: observation.tip) }, thresholds: thresholds)`.
    /// In a game whose descriptor has `dependsOnPosition`, a `certain` dart is lowered to `needsReview` when
    /// `match.effectKey(for: observation.best, position: p)` differs from the key at the tip for one of the four
    /// points `p = tip ± sigmaAlong · axis` and `p = tip ± sigmaAcross · normal` of `observation.uncertainty`
    /// (normal = (-axis.y, axis.x)). Not applied to a `tappedOnPhoto` observation: the player placed that tip.
    init(observation: DartObservation, thresholds: ConfidenceThresholds) {
        let origin: DartOrigin
        switch observation.source {
        case .liveCamera: origin = .camera
        case .scan: origin = .scan
        case .handheldPhoto, .tappedOnPhoto: origin = .photo
        }
        self.init(id: observation.id, hit: observation.best, position: observation.tip, origin: origin,
                  choices: observation.correctionChoices()) { match in
            DartProposal.cameraCertainty(of: observation, in: match, thresholds: thresholds)
        }
    }

    /// The certainty rule above, for one state of the game.
    static func cameraCertainty(of observation: DartObservation, in match: GameMatch,
                                thresholds: ConfidenceThresholds) -> Certainty {
        let tip = observation.tip
        let tier = observation.tier(collapsingBy: { match.effectKey(for: $0, position: tip) }, thresholds: thresholds)
        switch tier {
        case .low:
            return .undecided
        case .medium:
            return .needsReview
        case .high:
            guard match.definition.descriptor.dependsOnPosition, observation.source != .tappedOnPhoto else { return .certain }
            return cameraTipIsNearAnEdge(observation, in: match) ? .needsReview : .certain
        }
    }

    /// True when moving the tip by one standard deviation, along or across the dart, changes the effect of the best
    /// hit (GAMES.md §2.13: such a doubt is never settled silently). Zero or non-finite sigmas disable the check.
    private static func cameraTipIsNearAnEdge(_ observation: DartObservation, in match: GameMatch) -> Bool {
        let uncertainty = observation.uncertainty
        let length = simd_length(uncertainty.axis)
        guard length > 0, length.isFinite else { return false }
        let axis = uncertainty.axis / length
        let normal = SIMD2(-axis.y, axis.x)
        let tip = SIMD2(observation.tip.x, observation.tip.y)
        let best = observation.best
        let key = match.effectKey(for: best, position: observation.tip)
        var offsets: [SIMD2<Double>] = []
        if uncertainty.sigmaAlong > 0, uncertainty.sigmaAlong.isFinite {
            offsets += [uncertainty.sigmaAlong * axis, -uncertainty.sigmaAlong * axis]
        }
        if uncertainty.sigmaAcross > 0, uncertainty.sigmaAcross.isFinite {
            offsets += [uncertainty.sigmaAcross * normal, -uncertainty.sigmaAcross * normal]
        }
        return offsets.contains { offset in
            let point = tip + offset
            return match.effectKey(for: best, position: BoardPoint(x: point.x, y: point.y)) != key
        }
    }
}
