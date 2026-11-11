import Foundation
import simd
import DartCore

/// C3 — refinement parametrised by the four handles (VISION.md §4.6). Internal to DartVision (lot V2).
///
/// The eight unknowns are the image positions of the handles; `H(u)` is the closed form of C1. The residuals are
/// in board millimetres, the observed edge points `q` stay fixed during a solve, and the step is a damped
/// Gauss–Newton (Levenberg–Marquardt with a fixed `λ`) on Huber-weighted residuals with a forward-difference Jacobian.
enum HandleRefiner {
    /// Residual statistics of a measurement read through one homography.
    struct Statistics: Hashable, Sendable {
        /// Number of samples of the sample set.
        var sampleCount: Int
        /// Number of samples that gave an observation.
        var measured: Int
        /// Observations within `inlierDistance` of the model.
        var inliers: Int
        /// RMS of the inlier residuals, mm; nil without inliers.
        var inlierRMS: Double?
        /// Median of the absolute residuals of every observation, mm; nil without observations.
        var medianAbsolute: Double?

        var measuredFraction: Double {
            sampleCount > 0 ? Double(measured) / Double(sampleCount) : 0
        }
        /// Inliers among the measured samples.
        var inlierFraction: Double {
            measured > 0 ? Double(inliers) / Double(measured) : 0
        }
    }

    /// The residuals of every observation of `measurement`, read through `imageToBoard` (mm).
    static func residuals(of measurement: EdgeSampler.Measurement, imageToBoard: Homography, radii: RingRadii) -> [Double] {
        measurement.observations.map { observation in
            let sample = EdgeSampler.samples[observation.sample]
            return sample.residual(of: imageToBoard.apply(observation.point), radii: radii)
        }
    }

    /// Statistics of `measurement` read through `imageToBoard`.
    static func statistics(of measurement: EdgeSampler.Measurement, imageToBoard: Homography, radii: RingRadii,
                           parameters: CalibrationParameters) -> Statistics {
        let values = residuals(of: measurement, imageToBoard: imageToBoard, radii: radii).map { abs($0) }
        var inliers = 0
        var squares = 0.0
        for value in values where value.isFinite && value < parameters.inlierDistance {
            inliers += 1
            squares += value * value
        }
        let sorted = values.map { $0.isFinite ? $0 : .infinity }.sorted()
        var median: Double?
        if !sorted.isEmpty {
            median = sorted.count % 2 == 1
                ? sorted[sorted.count / 2]
                : (sorted[sorted.count / 2 - 1] + sorted[sorted.count / 2]) / 2
        }
        return Statistics(sampleCount: EdgeSampler.samples.count, measured: values.count, inliers: inliers,
                          inlierRMS: inliers > 0 ? (squares / Double(inliers)).squareRoot() : nil,
                          medianAbsolute: median)
    }

    /// Inliers of each family of samples over all the samples of that family (measured or not): rings, then wires.
    ///
    /// Review RV2: only the radial wires see a turn of the board about its centre (a ring is round), and a wire
    /// sample whose wire left its ±4 mm window is not measured at all. Counted among the measured samples only, a
    /// board turned by 3 to 9 degrees on its bracket kept every ring sample as an inlier and passed the drift check.
    static func familyInlierFractions(of measurement: EdgeSampler.Measurement, imageToBoard: Homography,
                                      radii: RingRadii, parameters: CalibrationParameters) -> (rings: Double, wires: Double) {
        var totals = (rings: 0, wires: 0), inliers = (rings: 0, wires: 0)
        for sample in EdgeSampler.samples {
            if case .ring = sample.kind { totals.rings += 1 } else { totals.wires += 1 }
        }
        for observation in measurement.observations {
            let sample = EdgeSampler.samples[observation.sample]
            let residual = abs(sample.residual(of: imageToBoard.apply(observation.point), radii: radii))
            guard residual.isFinite, residual < parameters.inlierDistance else { continue }
            if case .ring = sample.kind { inliers.rings += 1 } else { inliers.wires += 1 }
        }
        return (totals.rings > 0 ? Double(inliers.rings) / Double(totals.rings) : 0,
                totals.wires > 0 ? Double(inliers.wires) / Double(totals.wires) : 0)
    }

    /// Huber weight with a hard cutoff: 1 up to `huberK`, `huberK / |r|` up to `outlierCutoff`, 0 beyond.
    static func weight(of residual: Double, parameters: CalibrationParameters) -> Double {
        let magnitude = abs(residual)
        guard magnitude.isFinite, magnitude <= parameters.outlierCutoff else { return 0 }
        return magnitude <= parameters.huberK ? 1 : parameters.huberK / magnitude
    }

    /// Refines the handles against one measurement.
    ///
    /// - `start`: the handles the solve starts from.
    /// - `tether`: the handles of the player, which a weak spring holds the solution to:
    ///   `handleTetherWeight · (u_k − u_k^tether) / ρ`, with `ρ` the px/mm at the bull of the tethered homography.
    /// - `iterations`: at most this many steps; the solve also stops when `‖δ‖∞ < convergence` px.
    ///
    /// Returns the last handles whose homography is valid (the start when no step could be taken).
    static func refine(start: [SIMD2<Double>], tether: [SIMD2<Double>], measurement: EdgeSampler.Measurement,
                       radii: RingRadii, iterations: Int, parameters: CalibrationParameters) -> [SIMD2<Double>] {
        guard start.count == 4, tether.count == 4, !measurement.observations.isEmpty,
              let tetherTransform = CalibrationGeometry.homography(of: tether) else { return start }
        let bull = tetherTransform.localScale(at: SIMD2(0, 0))
        let rho = (bull.min * bull.max).squareRoot()
        guard rho.isFinite, rho > 0 else { return start }
        let tetherFactor = parameters.handleTetherWeight / rho
        let step = parameters.jacobianStep
        guard step > 0, step.isFinite else { return start }

        let observations = measurement.observations
        let samples = observations.map { EdgeSampler.samples[$0.sample] }
        let points = observations.map(\.point)

        /// Edge residuals for the handles `u` (flattened x0, y0, …, x3, y3); nil when `H(u)` is degenerate.
        func edgeResiduals(_ u: [Double]) -> [Double]? {
            let handles = (0..<4).map { SIMD2(u[2 * $0], u[2 * $0 + 1]) }
            guard let transform = CalibrationGeometry.homography(of: handles), let inverse = transform.inverse else {
                return nil
            }
            var values = [Double](repeating: 0, count: points.count)
            for index in points.indices {
                values[index] = samples[index].residual(of: inverse.apply(points[index]), radii: radii)
            }
            return values.allSatisfy(\.isFinite) ? values : nil
        }

        let anchor = tether.flatMap { [$0.x, $0.y] }
        var u = start.flatMap { [$0.x, $0.y] }
        guard var current = edgeResiduals(u) else { return start }
        for _ in 0..<max(0, iterations) {
            let weights = current.map { weight(of: $0, parameters: parameters) }
            // Forward-difference Jacobian of the edge residuals, one column per handle coordinate.
            var columns: [[Double]] = []
            columns.reserveCapacity(8)
            for k in 0..<8 {
                var shifted = u
                shifted[k] += step
                guard let moved = edgeResiduals(shifted) else { return pairs(u) }
                columns.append(zip(moved, current).map { ($0 - $1) / step })
            }
            // Normal equations JᵀWJ and JᵀW·r; the tether rows are diagonal with slope `tetherFactor`.
            var normal = [Double](repeating: 0, count: 64)
            var gradient = [Double](repeating: 0, count: 8)
            for i in current.indices where weights[i] > 0 {
                let w = weights[i]
                for a in 0..<8 {
                    let ja = columns[a][i]
                    if ja == 0 { continue }
                    gradient[a] += w * ja * current[i]
                    for b in a..<8 {
                        normal[a * 8 + b] += w * ja * columns[b][i]
                    }
                }
            }
            for a in 0..<8 {
                for b in 0..<a {
                    normal[a * 8 + b] = normal[b * 8 + a]
                }
                normal[a * 8 + a] += tetherFactor * tetherFactor
                gradient[a] += tetherFactor * tetherFactor * (u[a] - anchor[a])
            }
            // (JᵀWJ + λ·diag(JᵀWJ))·δ = −JᵀW·r.
            var damped = normal
            for a in 0..<8 {
                damped[a * 8 + a] += parameters.damping * normal[a * 8 + a]
            }
            guard let delta = LinearSolve.solve(damped, gradient.map { -$0 }, minPivot: 1e-15) else { break }
            let next = zip(u, delta).map { $0 + $1 }
            guard let residuals = edgeResiduals(next) else { break }
            u = next
            current = residuals
            if delta.map({ abs($0) }).max() ?? 0 < parameters.convergence { break }
        }
        return pairs(u)
    }

    private static func pairs(_ u: [Double]) -> [SIMD2<Double>] {
        (0..<4).map { SIMD2(u[2 * $0], u[2 * $0 + 1]) }
    }
}
