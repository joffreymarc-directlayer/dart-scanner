import Foundation
import simd
import DartCore

/// Steps D4 and D5 of VISION.md §5.2: components of the mask, state of the known darts, the ghost guard, and the
/// robust line through every new pixel (with peeling for stills). Internal to DartVision (lot V3).
///
/// Every length is in metric board millimetres: canvas pixel `(i, j)` is the point
/// `(−320 + (i + 0.5)/2, 320 − (j + 0.5)/2)`.
enum BlobAnalysis {
    /// Canvas pixels with their metric positions.
    struct Pixels: Sendable {
        /// Row-major canvas indices `y * side + x`.
        var indices: [Int]
        /// Metric board points of the same pixels, mm.
        var points: [SIMD2<Double>]
        /// Label of the connected component of the mask each pixel belongs to (0 when unknown).
        var labels: [Int32]

        init() {
            indices = []
            points = []
            labels = []
        }

        init(indices: [Int], labels: [Int32]? = nil) {
            self.indices = indices
            points = indices.map(BlobAnalysis.point(ofIndex:))
            self.labels = labels ?? [Int32](repeating: 0, count: indices.count)
        }

        var count: Int { indices.count }
        /// Area in mm².
        var area: Double { Double(indices.count) / (BoardCanvas.pixelsPerMillimetre * BoardCanvas.pixelsPerMillimetre) }

        /// The pixels at `positions` (indices into this set).
        func subset(_ positions: [Int]) -> Pixels {
            var result = Pixels()
            result.indices = positions.map { indices[$0] }
            result.points = positions.map { points[$0] }
            result.labels = positions.map { labels[$0] }
            return result
        }
    }

    /// A line through the pixels: weighted mean, unit direction, and the two principal variances (mm²).
    struct Line: Sendable {
        var mean: SIMD2<Double>
        var direction: SIMD2<Double>
        var largeVariance: Double
        var smallVariance: Double

        /// The unit normal, a quarter turn anticlockwise from `direction`.
        var normal: SIMD2<Double> { SIMD2(-direction.y, direction.x) }

        /// Position of `point` along the line from `mean`.
        func along(_ point: SIMD2<Double>) -> Double { simd_dot(point - mean, direction) }
        /// Signed distance of `point` across the line.
        func across(_ point: SIMD2<Double>) -> Double { simd_dot(point - mean, normal) }

        /// The same line with the direction reversed.
        var reversed: Line { Line(mean: mean, direction: -direction, largeVariance: largeVariance, smallVariance: smallVariance) }
    }

    /// One dart found by D5: the pixels of its corridor (`P`) and its line.
    struct DartPixels: Sendable {
        var pixels: Pixels
        var line: Line
        /// More than `1 − clutterFraction` of the new pixels are outside the corridor(s).
        var clutter: Bool
        /// Principal variances of the robust fit (the weighted PCA of D5 step 2): the elongation test of D9. Unweighted,
        /// the variances of a dart are dominated by the flight, whose plates are as wide as a third of its length.
        var elongation: Line
    }

    /// State of the known darts (D4): fractions measured on each silhouette.
    struct KnownState: Sendable {
        var removed: [UUID]
        var disturbed: [UUID]
    }

    static func point(ofIndex index: Int) -> SIMD2<Double> {
        let side = BoardCanvas.side
        let p = BoardCanvas.boardPoint(x: Double(index % side), y: Double(index / side))
        return SIMD2(p.x, p.y)
    }

    // MARK: D4

    /// Pixels of the components of `mask` that are at least `speckArea` mm².
    static func newPixels(of mask: GrayImage, parameters: DetectionParameters) -> Pixels {
        let components = ConnectedComponents(mask)
        let minimumPixels = parameters.speckArea * BoardCanvas.pixelsPerMillimetre * BoardCanvas.pixelsPerMillimetre
        var kept = [Bool](repeating: false, count: components.components.count + 1)
        for component in components.components where Double(component.pixelCount) >= minimumPixels {
            kept[Int(component.label)] = true
        }
        var indices: [Int] = []
        var labels: [Int32] = []
        components.labels.withUnsafeBufferPointer { source in
            kept.withUnsafeBufferPointer { keep in
                let count = source.count
                var index = 0
                while index < count {
                    let label = source[index]
                    if label != 0 && keep[Int(label)] {
                        indices.append(index)
                        labels.append(label)
                    }
                    index += 1
                }
            }
        }
        return Pixels(indices: indices, labels: labels)
    }

    /// Removed and disturbed known darts, on their own (undilated) silhouettes and on the unmasked evidence.
    ///
    /// Removed: at least `removedFraction` of the silhouette changed against R and, when E is known, at least that
    /// fraction looks like E again. Disturbed: between `disturbedFraction` and `removedFraction` changed, or more
    /// changed without looking like E (something new over it). Only valid pixels count.
    static func knownState(of darts: [KnownDart], evidence: ChangeEvidence, emptyEvidence: ChangeEvidence?,
                           parameters: DetectionParameters) -> KnownState {
        var state = KnownState(removed: [], disturbed: [])
        let tau = Float(evidence.threshold)
        let side = evidence.side
        for dart in darts {
            var total = 0, changed = 0, likeEmpty = 0
            dart.silhouette.forEachRun { y, x0, x1 in
                guard y >= 0, y < side else { return }
                for x in max(0, x0)..<min(side, x1) where evidence.isValid(x: x, y: y) {
                    total += 1
                    if evidence.value(x: x, y: y) >= tau { changed += 1 }
                    if let empty = emptyEvidence, empty.isValid(x: x, y: y), empty.value(x: x, y: y) < tau { likeEmpty += 1 }
                }
            }
            guard total > 0 else { continue }
            let fraction = Double(changed) / Double(total)
            if fraction >= parameters.removedFraction {
                if emptyEvidence == nil || Double(likeEmpty) / Double(total) >= parameters.removedFraction {
                    state.removed.append(dart.id)
                } else {
                    state.disturbed.append(dart.id)
                }
            } else if fraction >= parameters.disturbedFraction {
                state.disturbed.append(dart.id)
            }
        }
        return state
    }

    /// Ghost guard: at least `ghostGuardFraction` of the new pixels must differ from the empty board.
    static func passesGhostGuard(_ pixels: Pixels, emptyEvidence: ChangeEvidence, parameters: DetectionParameters) -> Bool {
        let tau = Float(emptyEvidence.threshold)
        var considered = 0, different = 0
        for index in pixels.indices where emptyEvidence.valid[index] != 0 {
            considered += 1
            if emptyEvidence.values[index] >= tau { different += 1 }
        }
        guard considered > 0 else { return true }
        return Double(different) >= parameters.ghostGuardFraction * Double(considered)
    }

    // MARK: D5

    /// Weighted principal axis. Nil without positive weight or when the spread is not finite.
    static func fit(_ points: [SIMD2<Double>], weights: [Double]? = nil) -> Line? {
        var total = 0.0
        var sum = SIMD2<Double>(0, 0)
        for (index, point) in points.enumerated() {
            let w = weights?[index] ?? 1
            guard w > 0 else { continue }
            total += w
            sum += w * point
        }
        guard total > 0 else { return nil }
        let mean = sum / total
        var sxx = 0.0, syy = 0.0, sxy = 0.0
        for (index, point) in points.enumerated() {
            let w = weights?[index] ?? 1
            guard w > 0 else { continue }
            let d = point - mean
            sxx += w * d.x * d.x
            syy += w * d.y * d.y
            sxy += w * d.x * d.y
        }
        sxx /= total
        syy /= total
        sxy /= total
        let theta = 0.5 * atan2(2 * sxy, sxx - syy)
        let root = ((sxx - syy) * (sxx - syy) + 4 * sxy * sxy).squareRoot()
        let large = (sxx + syy + root) / 2, small = max(0, (sxx + syy - root) / 2)
        guard theta.isFinite, large.isFinite, mean.x.isFinite, mean.y.isFinite else { return nil }
        return Line(mean: mean, direction: SIMD2(cos(theta), sin(theta)), largeVariance: large, smallVariance: small)
    }

    /// D5 steps 1 and 2: principal axis, then `lineIterations` passes reweighted on the lateral distance `d`:
    /// 1 up to `lineFullWeightDistance`, `full / d` up to `lineZeroWeightDistance`, 0 beyond.
    static func robustLine(_ points: [SIMD2<Double>], parameters: DetectionParameters) -> Line? {
        guard let start = fit(points) else { return nil }
        return reweighted(start, points: points, parameters: parameters)
    }

    /// D5: one line through every new pixel (`maxDarts == 1`), or peeling for stills: fit, take the corridor as one
    /// dart, remove it, again while at least `peelMinArea` mm² remain, `min(maxDarts, 3)` times at most.
    ///
    /// Peeling needs two precautions that a single dart does not. The principal axis of several separate darts runs
    /// between them, and the reweighting cannot leave it: each peel therefore also starts from the axis of each of
    /// the largest connected components, and keeps the start whose robust line runs along the longest dart. And a
    /// corridor 20 mm wide may cross another dart: a peel takes only the components that reach the core band of its
    /// line (`lineFullWeightDistance`) along the run of the dart, and leaves the others to the following peels.
    static func darts(in pixels: Pixels, maxDarts: Int, parameters: DetectionParameters) -> [DartPixels] {
        let limit = maxDarts > 1 ? min(maxDarts, 3) : 1
        let peeling = limit > 1
        var remaining = pixels
        var found: [(pixels: Pixels, line: Line)] = []
        while found.count < limit, remaining.count > 0 {
            if !found.isEmpty, remaining.area < parameters.peelMinArea { break }
            var extent: ClosedRange<Double>?
            let chosen: Line?
            if peeling {
                let best = bestPeelLine(remaining, parameters: parameters)
                chosen = best?.line
                extent = best.map { ($0.run.lowerBound - parameters.lineZeroWeightDistance)...($0.run.upperBound + parameters.lineZeroWeightDistance) }
            } else {
                chosen = robustLine(remaining.points, parameters: parameters)
            }
            guard let line = chosen else { break }
            var reached = Set<Int32>()
            if peeling {
                for (position, point) in remaining.points.enumerated()
                    where abs(line.across(point)) <= parameters.lineFullWeightDistance && extent?.contains(line.along(point)) != false {
                    reached.insert(remaining.labels[position])
                }
            }
            var inside: [Int] = [], outside: [Int] = []
            for (position, point) in remaining.points.enumerated() {
                let near = abs(line.across(point)) <= parameters.corridorHalfWidth
                let member = !peeling || (reached.contains(remaining.labels[position]) && extent?.contains(line.along(point)) != false)
                if near, member {
                    inside.append(position)
                } else {
                    outside.append(position)
                }
            }
            guard !inside.isEmpty else { break }
            found.append((remaining.subset(inside), line))
            remaining = remaining.subset(outside)
        }
        let assigned = found.reduce(0) { $0 + $1.pixels.count }
        let clutter = pixels.count > 0 && Double(assigned) < parameters.clutterFraction * Double(pixels.count)
        return found.map { entry in
            DartPixels(pixels: entry.pixels, line: entry.line, clutter: clutter, elongation: fit(entry.pixels.points) ?? entry.line)
        }
    }

    /// Robust weight of a lateral distance (D5 step 2).
    static func weight(_ distance: Double, parameters: DetectionParameters) -> Double {
        let full = max(1e-6, parameters.lineFullWeightDistance)
        let d = abs(distance)
        if d <= full { return 1 }
        if d <= parameters.lineZeroWeightDistance { return full / d }
        return 0
    }

    /// Number of seeds tried by a peel besides the principal axis of all its pixels.
    static let peelSeeds = 4

    /// The robust line of a peel: started from the principal axis of all the pixels and from that of each of the
    /// `peelSeeds` largest components, reweighted over all the pixels, and kept for the longest contiguous run of
    /// pixels within `lineFullWeightDistance` of it, gaps up to `lineZeroWeightDistance` bridged (ties: the first
    /// start). A dart's axis holds its whole length in that band; a line across two flights that happen to be
    /// aligned holds two short runs far apart, although their wide plates would give it more weight in all.
    /// Returns the line and the extent of its run along it; nil without any line.
    static func bestPeelLine(_ pixels: Pixels, parameters: DetectionParameters) -> (line: Line, run: ClosedRange<Double>)? {
        var sizes: [Int32: Int] = [:]
        for label in pixels.labels { sizes[label, default: 0] += 1 }
        let largest = sizes.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }.prefix(peelSeeds).map(\.key)
        var starts: [Line] = []
        if let all = fit(pixels.points) { starts.append(all) }
        for label in largest {
            let members = pixels.points.indices.filter { pixels.labels[$0] == label }.map { pixels.points[$0] }
            if members.count >= 2, let seed = fit(members) { starts.append(seed) }
        }
        var best: (line: Line, run: ClosedRange<Double>, count: Int)?
        for start in starts {
            let line = reweighted(start, points: pixels.points, parameters: parameters)
            let along = pixels.points.filter { abs(line.across($0)) <= parameters.lineFullWeightDistance }.map(line.along).sorted()
            guard let first = along.first else { continue }
            // Longest run of positions whose consecutive gaps are at most lineZeroWeightDistance.
            var runStart = 0, bestStart = 0, bestEnd = 0
            for index in 1..<max(1, along.count) where along[index] - along[index - 1] > parameters.lineZeroWeightDistance {
                if index - runStart > bestEnd - bestStart + 1 { bestStart = runStart; bestEnd = index - 1 }
                runStart = index
            }
            if along.count - runStart > bestEnd - bestStart + 1 { bestStart = runStart; bestEnd = along.count - 1 }
            let count = bestEnd - bestStart + 1
            _ = first
            if best == nil || count > (best?.count ?? 0) { best = (line, along[bestStart]...along[bestEnd], count) }
        }
        return best.map { ($0.line, $0.run) }
    }

    /// `lineIterations` passes of the robust reweighting from `start`.
    static func reweighted(_ start: Line, points: [SIMD2<Double>], parameters: DetectionParameters) -> Line {
        var line = start
        for _ in 0..<max(0, parameters.lineIterations) {
            let weights = points.map { weight(line.across($0), parameters: parameters) }
            guard let refined = fit(points, weights: weights) else { break }
            line = refined
        }
        return line
    }
}
