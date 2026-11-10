import Foundation
import simd
import CoreGraphics
import CoreVideo
import DartCore

/// Output of automatic board finding: initial handles only. Calibration then runs exactly as with manual handles.
public struct BoardLocation: Sendable {
    /// Handles for the orientation whose 20 is closest to `upDirection`.
    public var handles: CalibrationHandles
    /// The nine other orientations, 36 degrees apart.
    public var alternatives: [CalibrationHandles]
    /// Phase contrast of the red/green alternation, 0...0.64 (identity check).
    public var phaseContrast: Double
}

/// Optional layer: automatic board finding.
public protocol BoardLocating: Sendable {
    /// `upDirection` is the image direction of "up" (default (0, -1)); it picks one of the ten orientations.
    func locate(in still: RGBImage, upDirection: SIMD2<Double>) -> BoardLocation?
}

/// Colour mask, outer ellipse, bull, circle-point construction, 10th-harmonic phase (section 4.3).
public struct ColourBoardLocator: BoardLocating {
    public struct Parameters: Hashable, Codable, Sendable {
        public var workLongSide: Int = 640
        public var minBrightness: Int = 48
        public var saturationRange: ClosedRange<Double> = 0.30...0.55
        public var rayCount: Int = 360
        public var minRunLength: Int = 3
        public var sampsonTolerance: Double = 1.5
        public var bullAreaRange: ClosedRange<Double> = 0.4...2.5
        public var minColouredFraction: Double = 0.7
        public var minUncolouredFraction: Double = 0.8
        public var minPhaseContrast: Double = 0.35
        public var maxPhaseDisagreementDegrees: Double = 3
        public init() {}
    }
    private let parameters: Parameters

    public init(parameters: Parameters = .init()) {
        self.parameters = parameters
    }

    /// L1 to L8 (VISION.md §4.3). Nil when no candidate passes every check: the player places the handles.
    ///
    /// Up to four coloured components are tried, largest first; the first one that gives an ellipse, a bull, a
    /// board structure and a clear red/green phase wins. The handles come back at the resolution of `still`.
    public func locate(in still: RGBImage, upDirection: SIMD2<Double>) -> BoardLocation? {
        guard let work = WorkImage(still, longSide: parameters.workLongSide, parameters: parameters) else { return nil }
        let up = simd_length(upDirection) > 0 && upDirection.x.isFinite && upDirection.y.isFinite
            ? simd_normalize(upDirection) : SIMD2<Double>(0, -1)
        let components = ConnectedComponents(work.coloured)
        let shortSide = Double(min(work.width, work.height))
        let candidates = components.components
            .filter { component in
                let w = Double(component.width), h = Double(component.height)
                return min(w, h) >= 0.12 * shortSide && w / h >= 0.45 && w / h <= 2.2
            }
            .sorted { $0.pixelCount != $1.pixelCount ? $0.pixelCount > $1.pixelCount : $0.label < $1.label }
            .prefix(4)
        for candidate in candidates {
            if let location = locate(candidate, in: work, components: components, up: up) {
                return location
            }
        }
        return nil
    }
}

// MARK: - Steps (lot V2, internal)

extension ColourBoardLocator {
    /// L1: the still averaged by square blocks to a long side of about `workLongSide` px, with the colour mask.
    struct WorkImage: Sendable {
        let width: Int
        let height: Int
        /// Side of the averaged blocks, source px: work pixel `i` covers source pixels `[i·factor, (i + 1)·factor)`.
        let factor: Int
        /// Mean RGB of each block, row-major.
        let rgb: [SIMD3<Float>]
        /// Redness `o = (R − G) / (R + G + B + 1)` of each block.
        let redness: [Float]
        /// Saturation threshold `Ts` that was used (Otsu, clamped to `saturationRange`).
        let saturationThreshold: Double
        /// 255 where the block is coloured (`max ≥ minBrightness` and saturation `≥ Ts`), after a 3×3 closing.
        let coloured: GrayImage

        init?(_ still: RGBImage, longSide: Int, parameters: Parameters) {
            let sourceLong = max(still.width, still.height)
            guard still.width > 0, still.height > 0, still.pixels.count == still.width * still.height * 3, longSide > 0
            else { return nil }
            let factor = max(1, Int((Double(sourceLong) / Double(longSide)).rounded()))
            let w = still.width / factor, h = still.height / factor
            guard w >= 8, h >= 8 else { return nil }
            var rgb = [SIMD3<Float>](repeating: .zero, count: w * h)
            let sourceWidth = still.width
            let area = Float(factor * factor)
            // Integer sums per block, one work row at a time.
            var sums = [UInt32](repeating: 0, count: w * 3)
            still.pixels.withUnsafeBufferPointer { source in
                sums.withUnsafeMutableBufferPointer { sum in
                    rgb.withUnsafeMutableBufferPointer { out in
                        for j in 0..<h {
                            for k in 0..<(w * 3) { sum[k] = 0 }
                            for y in (j * factor)..<((j + 1) * factor) {
                                var index = y * sourceWidth * 3
                                for i in 0..<w {
                                    var red: UInt32 = 0, green: UInt32 = 0, blue: UInt32 = 0
                                    for _ in 0..<factor {
                                        red += UInt32(source[index])
                                        green += UInt32(source[index + 1])
                                        blue += UInt32(source[index + 2])
                                        index += 3
                                    }
                                    sum[3 * i] += red
                                    sum[3 * i + 1] += green
                                    sum[3 * i + 2] += blue
                                }
                            }
                            for i in 0..<w {
                                out[j * w + i] = SIMD3(Float(sum[3 * i]), Float(sum[3 * i + 1]), Float(sum[3 * i + 2])) / area
                            }
                        }
                    }
                }
            }
            var redness = [Float](repeating: 0, count: w * h)
            var saturation = [Float](repeating: 0, count: w * h)
            var bright = [Bool](repeating: false, count: w * h)
            var histogram = [Int](repeating: 0, count: 256)
            for index in 0..<(w * h) {
                let p = rgb[index]
                let mx = max(p.x, max(p.y, p.z)), mn = min(p.x, min(p.y, p.z))
                let sat = (mx - mn) / max(mx, 1)
                saturation[index] = sat
                redness[index] = (p.x - p.y) / (p.x + p.y + p.z + 1)
                if mx >= Float(parameters.minBrightness) {
                    bright[index] = true
                    histogram[min(255, max(0, Int(sat * 256)))] += 1
                }
            }
            let otsu = WorkImage.otsuThreshold(histogram)
            let threshold = min(max(otsu, parameters.saturationRange.lowerBound), parameters.saturationRange.upperBound)
            var mask = GrayImage(width: w, height: h, fill: 0)
            for index in 0..<(w * h) where bright[index] && Double(saturation[index]) >= threshold {
                mask.pixels[index] = 255
            }
            self.width = w
            self.height = h
            self.factor = factor
            self.rgb = rgb
            self.redness = redness
            self.saturationThreshold = threshold
            self.coloured = Morphology.close(mask, radius: 1)
        }

        /// Otsu's threshold of a 256-bin histogram of values in [0, 1]: the bin boundary that maximises the
        /// between-class variance. 0.5 for an empty or single-valued histogram.
        static func otsuThreshold(_ histogram: [Int]) -> Double {
            let total = histogram.reduce(0, +)
            guard total > 0 else { return 0.5 }
            var sumAll = 0.0
            for (bin, count) in histogram.enumerated() { sumAll += Double(bin) * Double(count) }
            var weightBelow = 0.0, sumBelow = 0.0
            var best = -1.0, bestBin = 128
            for bin in 0..<255 {
                weightBelow += Double(histogram[bin])
                sumBelow += Double(bin) * Double(histogram[bin])
                let weightAbove = Double(total) - weightBelow
                guard weightBelow > 0, weightAbove > 0 else { continue }
                let meanBelow = sumBelow / weightBelow, meanAbove = (sumAll - sumBelow) / weightAbove
                let between = weightBelow * weightAbove * (meanBelow - meanAbove) * (meanBelow - meanAbove)
                if between > best {
                    best = between
                    bestBin = bin
                }
            }
            return Double(bestBin + 1) / 256
        }

        /// True when the work pixel nearest to `p` is coloured; false outside the image.
        func isColoured(_ p: SIMD2<Double>) -> Bool {
            guard p.x.isFinite, p.y.isFinite else { return false }
            let x = Int(p.x.rounded()), y = Int(p.y.rounded())
            guard x >= 0, y >= 0, x < width, y < height else { return false }
            return coloured.pixels[y * width + x] != 0
        }

        /// Bilinear redness at a work position; nil outside.
        func redness(at p: SIMD2<Double>) -> Double? {
            guard p.x.isFinite, p.y.isFinite, p.x >= 0, p.y >= 0, p.x <= Double(width - 1), p.y <= Double(height - 1)
            else { return nil }
            let x0 = min(Int(p.x), width - 2), y0 = min(Int(p.y), height - 2)
            let fx = p.x - Double(x0), fy = p.y - Double(y0)
            func o(_ x: Int, _ y: Int) -> Double { Double(redness[y * width + x]) }
            let top = o(x0, y0) + (o(x0 + 1, y0) - o(x0, y0)) * fx
            let bottom = o(x0, y0 + 1) + (o(x0 + 1, y0 + 1) - o(x0, y0 + 1)) * fx
            return top + (bottom - top) * fy
        }

        /// A work position at the source resolution: `x = (x_work + 0.5)·factor − 0.5`.
        func sourcePoint(_ p: SIMD2<Double>) -> ImagePoint {
            ImagePoint(x: (p.x + 0.5) * Double(factor) - 0.5, y: (p.y + 0.5) * Double(factor) - 0.5)
        }
    }

    /// L2 to L8 on one candidate component.
    private func locate(_ candidate: ConnectedComponents.Component, in work: WorkImage,
                        components: ConnectedComponents, up: SIMD2<Double>) -> BoardLocation? {
        // L2: the farthest coloured pixel of a run of at least `minRunLength` along each ray from the box centre.
        let points = ColourBoardLocator.rayPoints(of: candidate, components: components, rayCount: parameters.rayCount,
                                                  minRunLength: parameters.minRunLength)
        // L3: ellipse, robust to the points that are not on the outer edge.
        guard points.count >= 5,
              let fitted = ConicFit.robustFit(points, tolerance: parameters.sampsonTolerance),
              Double(fitted.kept.filter { $0 }.count) >= 0.6 * Double(max(1, parameters.rayCount)),
              let ellipse = fitted.conic.ellipse, ellipse.minor / ellipse.major >= 0.45 else { return nil }
        // L4: the bull, never the centre of the ellipse.
        let expected = (RingRadii.nominal.outerBull / 170) * (RingRadii.nominal.outerBull / 170) * ellipse.area
        var bull: (centre: SIMD2<Double>, distance: Double)?
        for component in components.components {
            let area = Double(component.pixelCount)
            guard area >= parameters.bullAreaRange.lowerBound * expected,
                  area <= parameters.bullAreaRange.upperBound * expected else { continue }
            let centre = component.centroid
            let distance = simd_length(centre - ellipse.centre)
            guard distance <= 0.3 * ellipse.minor else { continue }
            if bull == nil || distance < (bull?.distance ?? .infinity) { bull = (centre, distance) }
        }
        guard let centre = bull?.centre,
              let provisional = ColourBoardLocator.provisionalHomography(conic: fitted.conic, centre: centre) else {
            return nil
        }
        // L6: the rings are coloured, the singles are not.
        guard ColourBoardLocator.hasBoardStructure(work, through: provisional, parameters: parameters) else { return nil }
        // L7: phase of the red/green alternation on the double and on the treble.
        guard let outer = ColourBoardLocator.phase(of: work, through: provisional, radius: 166),
              let inner = ColourBoardLocator.phase(of: work, through: provisional, radius: 103),
              outer.contrast >= parameters.minPhaseContrast, inner.contrast >= parameters.minPhaseContrast,
              ColourBoardLocator.angularDistance(outer.beta, inner.beta, period: 36) <= parameters.maxPhaseDisagreementDegrees
        else { return nil }
        let beta = ColourBoardLocator.meanPhase(outer.beta, inner.beta)
        // L8: the ten orientations; the one whose +y is closest to `up` comes first.
        let orientations = (0..<10).map { k in
            provisional.concatenating(.boardRotation(clockwiseDegrees: beta + 36 * Double(k)))
        }
        var chosen = 0
        var bestCosine = -Double.infinity
        for (k, transform) in orientations.enumerated() {
            let column = transform.jacobian(at: SIMD2(0, 0)).columns.1
            let length = simd_length(column)
            guard length > 0, length.isFinite else { continue }
            let cosine = simd_dot(column / length, up)
            if cosine > bestCosine {
                bestCosine = cosine
                chosen = k
            }
        }
        func handles(_ transform: Homography) -> CalibrationHandles {
            CalibrationHandles(points: CalibrationGeometry.junctions.map { work.sourcePoint(transform.apply($0)) })
        }
        let alternatives = (1..<10).map { handles(orientations[(chosen + $0) % 10]) }
        let result = handles(orientations[chosen])
        let finite = ([result] + alternatives).allSatisfy { $0.points.allSatisfy { $0.x.isFinite && $0.y.isFinite } }
        guard finite else { return nil }
        return BoardLocation(handles: result, alternatives: alternatives,
                             phaseContrast: min(outer.contrast, inner.contrast))
    }

    /// L2: one edge point per ray (work px), the farthest coloured pixel of `component` belonging to a run of at
    /// least `minRunLength` consecutive coloured samples, pushed half a step outwards.
    ///
    /// The rays are walked in steps of `rayStep` (half a pixel), not of one pixel: at 1.5 m from a 4K camera the
    /// coloured band of the double ring is only about 2 work pixels wide, and with one-pixel steps fewer than 60 % of
    /// the rays would find a run of three. A run of three half steps still rejects an isolated speck.
    static func rayPoints(of component: ConnectedComponents.Component, components: ConnectedComponents,
                          rayCount: Int, minRunLength: Int) -> [SIMD2<Double>] {
        let centre = SIMD2(Double(component.minX + component.maxX) / 2, Double(component.minY + component.maxY) / 2)
        let width = components.width, height = components.height
        var points: [SIMD2<Double>] = []
        let count = max(0, rayCount)
        points.reserveCapacity(count)
        for ray in 0..<count {
            let angle = 2 * Double.pi * Double(ray) / Double(count)
            let direction = SIMD2(cos(angle), sin(angle))
            var run = 0
            var farthest: Int?
            var t = 0
            while true {
                let p = centre + Double(t) * rayStep * direction
                let x = Int(p.x.rounded()), y = Int(p.y.rounded())
                guard x >= 0, y >= 0, x < width, y < height else { break }
                if components.labels[y * width + x] == component.label {
                    run += 1
                    if run >= max(1, minRunLength) { farthest = t }
                } else {
                    run = 0
                }
                t += 1
            }
            if let farthest {
                points.append(centre + (Double(farthest) + 0.5) * rayStep * direction)
            }
        }
        return points
    }

    /// Step of the rays of L2, work px.
    static let rayStep = 0.5

    /// L5: a homography that sends the board circle r = 170 onto `conic` and the bull onto `centre`, exact up to a
    /// rotation of the board (VISION.md §4.3). Nil when a construction step is degenerate.
    static func provisionalHomography(conic: ConicFit, centre: SIMD2<Double>) -> Homography? {
        let q = conic.matrix
        let c = SIMD3(centre.x, centre.y, 1)
        let vanishing = q * c
        guard let (ha, hb) = ConicFit.intersections(q, point: c, direction: SIMD3(1, 0, 0)) else { return nil }
        let v1 = simd_cross(simd_cross(ha, hb), vanishing)
        let v2 = simd_cross(vanishing, q * v1)
        guard let (hd, he) = ConicFit.intersections(q, point: c, direction: v2),
              let a = ConicFit.point(ha), let b = ConicFit.point(hb),
              var d = ConicFit.point(hd), var e = ConicFit.point(he) else { return nil }
        let board: [SIMD2<Double>] = [SIMD2(170, 0), SIMD2(0, 170), SIMD2(-170, 0), SIMD2(0, -170)]
        guard var transform = Homography.mapping(from: board, to: [a, d, b, e]) else { return nil }
        // A physical view has a negative Jacobian determinant (VISION.md §3.5).
        if simd_determinant(transform.jacobian(at: SIMD2(0, 0))) > 0 {
            swap(&d, &e)
            guard let swapped = Homography.mapping(from: board, to: [a, d, b, e]) else { return nil }
            transform = swapped
        }
        return transform
    }

    /// L6: at least `minColouredFraction` of 180 samples coloured on r = 166 and on r = 103, and at least
    /// `minUncolouredFraction` uncoloured on r = 60 and on r = 135, each radius on its own.
    static func hasBoardStructure(_ work: WorkImage, through transform: Homography, parameters: Parameters) -> Bool {
        func fraction(radius: Double, coloured: Bool) -> Double {
            let count = 180
            var hits = 0
            for k in 0..<count {
                let a = 2 * Double.pi * Double(k) / Double(count)
                let p = transform.apply(SIMD2(radius * sin(a), radius * cos(a)))
                let inside = p.x >= 0 && p.y >= 0 && p.x <= Double(work.width - 1) && p.y <= Double(work.height - 1)
                if inside && work.isColoured(p) == coloured { hits += 1 }
            }
            return Double(hits) / Double(count)
        }
        return fraction(radius: 166, coloured: true) >= parameters.minColouredFraction
            && fraction(radius: 103, coloured: true) >= parameters.minColouredFraction
            && fraction(radius: 60, coloured: false) >= parameters.minUncolouredFraction
            && fraction(radius: 135, coloured: false) >= parameters.minUncolouredFraction
    }

    /// L7 on one ring: redness at 720 angles `φ_j` of the provisional board frame, `s_j = o_j − median(o)`,
    /// `z = Σ s_j·e^(−i·10·φ_j)`, `β = −arg(z) / 10` in [0, 36) degrees, contrast `|z| / Σ|s_j|`. Nil when fewer than
    /// half of the samples fall in the image.
    static func phase(of work: WorkImage, through transform: Homography, radius: Double, count: Int = 720)
        -> (beta: Double, contrast: Double)? {
        var angles: [Double] = []
        var values: [Double] = []
        angles.reserveCapacity(count)
        values.reserveCapacity(count)
        for j in 0..<count {
            let phi = 2 * Double.pi * Double(j) / Double(count)
            let p = transform.apply(SIMD2(radius * sin(phi), radius * cos(phi)))
            guard let o = work.redness(at: p) else { continue }
            angles.append(phi)
            values.append(o)
        }
        guard values.count * 2 >= count else { return nil }
        let sorted = values.sorted()
        let median = sorted.count % 2 == 1 ? sorted[sorted.count / 2] : (sorted[sorted.count / 2 - 1] + sorted[sorted.count / 2]) / 2
        var real = 0.0, imaginary = 0.0, total = 0.0
        for (phi, o) in zip(angles, values) {
            let s = o - median
            real += s * cos(10 * phi)
            imaginary -= s * sin(10 * phi)
            total += abs(s)
        }
        guard total > 0 else { return nil }
        var beta = -atan2(imaginary, real) * 180 / .pi / 10
        beta = beta.truncatingRemainder(dividingBy: 36)
        if beta < 0 { beta += 36 }
        return (beta, (real * real + imaginary * imaginary).squareRoot() / total)
    }

    /// Distance between two angles on a circle of `period` degrees.
    static func angularDistance(_ a: Double, _ b: Double, period: Double) -> Double {
        var difference = (a - b).truncatingRemainder(dividingBy: period)
        if difference < 0 { difference += period }
        return min(difference, period - difference)
    }

    /// Circular mean of two phases of period 36 degrees, in [0, 36).
    static func meanPhase(_ a: Double, _ b: Double) -> Double {
        let x = cos(a * 10 * .pi / 180) + cos(b * 10 * .pi / 180)
        let y = sin(a * 10 * .pi / 180) + sin(b * 10 * .pi / 180)
        var mean = atan2(y, x) * 180 / .pi / 10
        if mean < 0 { mean += 36 }
        return mean
    }
}
