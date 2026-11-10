import Foundation
import simd
import DartCore

/// C2 — edge measurement (VISION.md §4.5). Internal to DartVision (lot V2).
///
/// One mechanism serves the refinement (C3), the ring radii (C4), the quality figure (C8) and the drift check (4.9):
/// 388 short profiles across the ring and wire boundaries of the board, read in the camera image through a
/// board-to-image homography, each giving at most one observed edge point in image pixels.
enum EdgeSampler {
    /// Where a sample sits.
    enum Kind: Hashable, Sendable {
        /// On ring `ring` (0 = inner bull … 5 = outer double, the order of `RingRadii`), radial normal.
        case ring(Int)
        /// On radial wire `wire` (0…19, at `9° + 18°·wire`), tangential normal.
        case wire(Int)
    }

    /// One profile of the sample set: a board position given by a clockwise angle and, for a wire sample, a radius.
    struct Sample: Hashable, Sendable {
        var kind: Kind
        /// Clockwise angle from +y, radians: the angle of the sample on its ring, or of its wire.
        var angle: Double
        /// Radius of a wire sample, mm (a ring sample takes the radius of its ring).
        var radius: Double

        /// Position `X0` and unit normal `n̂` of the sample on a board with the given (metric) ring radii.
        func frame(radii: RingRadii) -> (position: SIMD2<Double>, normal: SIMD2<Double>) {
            let direction = SIMD2(sin(angle), cos(angle))
            switch kind {
            case .ring(let ring):
                return (EdgeSampler.radius(of: ring, in: radii) * direction, direction)
            case .wire:
                // Normal of the signed distance `x·cos α − y·sin α` (VISION.md §3.3).
                return (radius * direction, SIMD2(cos(angle), -sin(angle)))
            }
        }

        /// Residual of a metric board point, mm (VISION.md §4.6, C3): `|X| − R` on a ring, the signed distance to
        /// the wire on a wire.
        func residual(of point: SIMD2<Double>, radii: RingRadii) -> Double {
            switch kind {
            case .ring(let ring):
                return simd_length(point) - EdgeSampler.radius(of: ring, in: radii)
            case .wire:
                return point.x * cos(angle) - point.y * sin(angle)
            }
        }
    }

    /// One accepted edge: the observed point `q` in image pixels.
    struct Observation: Hashable, Sendable {
        /// Index in `samples`.
        var sample: Int
        /// `q = H·(X0 + o·n̂)`, image px.
        var point: SIMD2<Double>
        /// Offset `o` along the normal, mm, as measured through the homography of the measurement.
        var offset: Double
    }

    /// The outcome of one measurement: the accepted observations, in sample order.
    struct Measurement: Sendable {
        var observations: [Observation]
        /// Fraction of the 388 samples that gave an observation.
        var measuredFraction: Double {
            Double(observations.count) / Double(EdgeSampler.samples.count)
        }
    }

    /// Ring radii of the sample set: 170, 162, 107 and 99 mm at 40 angles each, 15.9 at 16, 6.35 at 12.
    /// Wire radii: 35, 55, 75, 90, 103, 116, 130, 144, 155, 166 mm on each of the 20 wires.
    static let wireRadii: [Double] = [35, 55, 75, 90, 103, 116, 130, 144, 155, 166]

    /// The 388 samples of VISION.md §4.5, rings first (outer double to inner bull), then wires.
    ///
    /// The four outer rings are read at `18°·k ± 4.5°`, half-way between a sector centre and its wires. The
    /// document leaves the angles of the two bull rings open: the outer bull is read at the middle of sixteen of the
    /// twenty sectors (all but every fifth), 9 degrees from the radial wires that start on it; the inner bull, which no
    /// wire touches, at twelve angles 30 degrees apart.
    static let samples: [Sample] = {
        var result: [Sample] = []
        let degree = Double.pi / 180
        for ring in [5, 4, 3, 2] {
            for k in 0..<20 {
                for side in [-4.5, 4.5] {
                    result.append(Sample(kind: .ring(ring), angle: (18 * Double(k) + side) * degree, radius: 0))
                }
            }
        }
        for k in 0..<20 where k % 5 != 4 {
            result.append(Sample(kind: .ring(1), angle: 18 * Double(k) * degree, radius: 0))
        }
        for k in 0..<12 {
            result.append(Sample(kind: .ring(0), angle: 30 * Double(k) * degree, radius: 0))
        }
        for wire in 0..<20 {
            for radius in wireRadii {
                result.append(Sample(kind: .wire(wire), angle: (9 + 18 * Double(wire)) * degree, radius: radius))
            }
        }
        return result
    }()

    /// Radius of ring `index` (0 = inner bull … 5 = outer double) of `radii`.
    static func radius(of index: Int, in radii: RingRadii) -> Double {
        switch index {
        case 0: return radii.innerBull
        case 1: return radii.outerBull
        case 2: return radii.trebleInner
        case 3: return radii.trebleOuter
        case 4: return radii.doubleInner
        default: return radii.doubleOuter
        }
    }

    /// Measures every sample through `boardToImage` (VISION.md §4.5).
    ///
    /// - `halfWindow`: how far from the sample the edge may be found, mm (`profileHalfWindow`, 4, for a first pass;
    ///   `secondPassHalfWindow`, 2, for a second pass).
    /// - `radii`: the metric ring radii the ring samples are placed on.
    ///
    /// Every profile is read over at least ±`profileHalfWindow`, whatever the search window: a blurred wire is 3 to
    /// 4 mm wide in energy, so a ±2 mm profile holds nothing else, and neither its beds nor its noise level could be
    /// read from it. A sample whose profile leaves the image is not measured.
    static func measure(_ raster: EdgeSamplerRaster, boardToImage: Homography, halfWindow: Double,
                        radii: RingRadii, parameters: CalibrationParameters) -> Measurement {
        let step = parameters.profileStep
        guard step > 0, step.isFinite, halfWindow.isFinite, halfWindow > 0,
              parameters.profileHalfWindow.isFinite else { return Measurement(observations: []) }
        let span = max(1, parameters.gradientSpan)
        let reach = Int((max(halfWindow, parameters.profileHalfWindow) / step).rounded())
        let search = min(reach - span, Int((halfWindow / step).rounded()) - span)
        guard reach > span + endSamples, search >= 0, reach <= 4096 else { return Measurement(observations: []) }
        var observations: [Observation] = []
        observations.reserveCapacity(samples.count)
        var colours = [SIMD3<Float>](repeating: .zero, count: 2 * reach + 1)
        for (index, sample) in samples.enumerated() {
            let frame = sample.frame(radii: radii)
            var complete = true
            for j in -reach...reach {
                let board = frame.position + Double(j) * step * frame.normal
                let image = boardToImage.apply(board)
                guard let colour = raster.sample(x: image.x, y: image.y) else {
                    complete = false
                    break
                }
                colours[j + reach] = colour
            }
            guard complete else { continue }
            guard let offset = edgeOffset(colours: colours, search: search, step: step, span: span, parameters: parameters)
            else { continue }
            let point = boardToImage.apply(frame.position + offset * frame.normal)
            guard point.x.isFinite, point.y.isFinite else { continue }
            observations.append(Observation(sample: index, point: point, offset: offset))
        }
        return Measurement(observations: observations)
    }

    /// Reach of the visibility check, in profile half-windows: ±12 mm with the default ±4 mm.
    static let visibilityReach = 3.0

    /// Fraction of the samples near which the image shows an edge at all: within ±`visibilityReach` half-windows
    /// across the sample, some `g_j = ‖c_(j+s) − c_(j−s)‖ ≥ minEdgeEnergy` between two positions inside the image.
    ///
    /// This is what the drift check calls "measurable" (VISION.md §4.9, `edgesNotVisible`). A hand, darkness or a board
    /// without contrast show no such energy anywhere. A board that jumped by 20 to 40 mm still does, but its samples,
    /// which sit on the edges of the board, now land mostly in uniform beds: only about 30 % of them find an edge
    /// within their own ±4 mm profile, which would make a jolt look like darkness.
    static func visibleFraction(_ raster: EdgeSamplerRaster, boardToImage: Homography, radii: RingRadii,
                                parameters: CalibrationParameters) -> Double {
        let step = parameters.profileStep
        let span = max(1, parameters.gradientSpan)
        let halfWindow = parameters.profileHalfWindow * visibilityReach
        guard step > 0, step.isFinite, halfWindow.isFinite, halfWindow > 0 else { return 0 }
        let reach = Int((halfWindow / step).rounded())
        guard reach > span, reach <= 4096 else { return 0 }
        let threshold = Float(parameters.minEdgeEnergy)
        var colours = [SIMD3<Float>?](repeating: nil, count: 2 * reach + 1)
        var visible = 0
        for sample in samples {
            let frame = sample.frame(radii: radii)
            for j in -reach...reach {
                let image = boardToImage.apply(frame.position + Double(j) * step * frame.normal)
                colours[j + reach] = raster.sample(x: image.x, y: image.y)
            }
            for j in span..<(colours.count - span) {
                guard let after = colours[j + span], let before = colours[j - span] else { continue }
                if simd_length(after - before) >= threshold {
                    visible += 1
                    break
                }
            }
        }
        return Double(visible) / Double(samples.count)
    }

    /// Number of samples at each end of a profile that give the colours on either side of the edge.
    static let endSamples = 3

    /// Offset of the edge along a profile, mm, or nil when the profile shows no edge.
    ///
    /// `colours[j + reach]` is the colour at `X0 + j·δ·n̂`, `|j| ≤ reach`. The unsigned colour gradient energy
    /// `g_j = ‖c_(j+s) − c_(j−s)‖` is computed for `|j| ≤ reach − s`; its peak `j*` is searched for `|j| ≤ search`
    /// and accepted when `g(j*) ≥ minEdgeEnergy` and `g(j*) ≥ edgePeakRatio · median(g)` (VISION.md §4.5).
    ///
    /// The median is taken over the profile away from the edge, `|j − j*| > 2 · centroidHalfWidth` (over the whole
    /// profile when fewer than four values remain): at 1.2 px/mm the energy of a blurred wire covers more than half of
    /// a ±4 mm profile, and a median that includes it rejects most of the true edges.
    ///
    /// Locating the edge. Every boundary of a board is a wire, a band about 1.4 mm wide, and the two flanks of the
    /// band often differ a lot in contrast (a cream single meets a light wire with little, the wire meets a black
    /// single with a lot). The energy centroid over `|j − j*| ≤ centroidHalfWidth` that the document prints follows
    /// the stronger flank: measured on the synthetic board it sits 0.25 to 0.3 mm from the centre of every wire
    /// between a black and a cream single, with a sign alternating from wire to wire. The offset is therefore taken
    /// from a measure that does not depend on the contrasts:
    /// - `A` and `B` are the mean colours of the `endSamples` samples at each end of the profile (the two beds);
    /// - `d_j` is the distance of `c_j` from the straight line through `A` and `B` in RGB. A blurred profile
    ///   `A → W → B` with flanks at `e1` and `e2` gives `d(x) = ‖P⊥(W − A)‖ · |S(x − e1) − S(x − e2)|` (`S` the blurred
    ///   step, `P⊥` the projection across the line), a bump exactly symmetric about the wire centre `(e1 + e2) / 2`;
    /// - when the bump peaks within `2 · centroidHalfWidth` samples of `j*` and reaches `minEdgeEnergy / 2`, the edge
    ///   is the middle of its half-maximum run (ends interpolated); otherwise (a plain step, or a wire whose colour lies
    ///   on the path between its beds) the edge is the middle of the half-maximum run of `g` around `j*`.
    static func edgeOffset(colours: [SIMD3<Float>], search: Int, step: Double, span: Int,
                           parameters: CalibrationParameters) -> Double? {
        let reach = (colours.count - 1) / 2
        let low = -reach + span, high = reach - span
        let searchLow = max(low, -search), searchHigh = min(high, search)
        guard high > low, reach >= endSamples, searchHigh >= searchLow else { return nil }
        func c(_ j: Int) -> SIMD3<Float> { colours[j + reach] }
        var energy = [Double](repeating: 0, count: colours.count)
        for j in low...high {
            energy[j + reach] = Double(simd_length(c(j + span) - c(j - span)))
        }
        func g(_ j: Int) -> Double { energy[j + reach] }
        var peak = searchLow
        var peakEnergy = g(searchLow)
        for j in searchLow...searchHigh where g(j) > peakEnergy {
            peak = j
            peakEnergy = g(j)
        }
        let pairReach = 2 * max(1, parameters.centroidHalfWidth)
        var background = (low...high).filter { abs($0 - peak) > pairReach }.map(g)
        if background.count < 4 { background = (low...high).map(g) }
        let sorted = background.sorted()
        let median = sorted.count % 2 == 1
            ? sorted[sorted.count / 2]
            : (sorted[sorted.count / 2 - 1] + sorted[sorted.count / 2]) / 2
        guard peakEnergy >= parameters.minEdgeEnergy, peakEnergy >= parameters.edgePeakRatio * median else { return nil }

        // Distance of every colour from the line through the two beds.
        var a = SIMD3<Double>(0, 0, 0), b = SIMD3<Double>(0, 0, 0)
        for k in 0..<endSamples {
            a += SIMD3<Double>(c(-reach + k))
            b += SIMD3<Double>(c(reach - k))
        }
        a /= Double(endSamples)
        b /= Double(endSamples)
        let path = b - a
        let length = simd_length(path)
        let direction = length > 1e-9 ? path / length : SIMD3<Double>(0, 0, 0)
        var distance = [Double](repeating: 0, count: colours.count)
        for j in -reach...reach {
            let v = SIMD3<Double>(c(j)) - a
            distance[j + reach] = simd_length(v - simd_dot(v, direction) * direction)
        }
        func d(_ j: Int) -> Double { distance[j + reach] }

        var bump = peak
        for j in max(-reach, peak - pairReach)...min(reach, peak + pairReach) where d(j) > d(bump) {
            bump = j
        }
        let centre: Double
        if d(bump) >= parameters.minEdgeEnergy / 2 {
            centre = halfMaximumMiddle(of: d, around: bump, in: -reach...reach)
        } else {
            centre = halfMaximumMiddle(of: g, around: peak, in: low...high)
        }
        let offset = centre * step
        return offset.isFinite ? offset : nil
    }

    /// Middle of the run of `f ≥ f(top) / 2` around `top` within `range`, its ends interpolated at the half maximum.
    private static func halfMaximumMiddle(of f: (Int) -> Double, around top: Int, in range: ClosedRange<Int>) -> Double {
        let level = f(top) / 2
        var first = top, last = top
        while first - 1 >= range.lowerBound, f(first - 1) >= level { first -= 1 }
        while last + 1 <= range.upperBound, f(last + 1) >= level { last += 1 }
        func crossing(_ inside: Int, _ outside: Int) -> Double {
            guard range.contains(outside) else { return Double(inside) }
            let a = f(inside), b = f(outside)
            let t = a > b ? (a - level) / (a - b) : 0
            return Double(inside) + Double(outside - inside) * min(1, max(0, t))
        }
        return (crossing(first, first - 1) + crossing(last, last + 1)) / 2
    }
}

/// Read access to the pixels of a still or of a frame, for the duration of one measurement (lot V2, internal).
///
/// Bilinear sampling with exactly the semantics of `RGBImage.sample(x:y:)`: the image covers
/// `[-0.5, width - 0.5] × [-0.5, height - 0.5]`, the edge pixels are replicated in the half-pixel border, and
/// a position outside gives nil. The bytes are borrowed: a raster never outlives the closure that made it.
struct EdgeSamplerRaster {
    let bytes: UnsafeRawBufferPointer
    let bytesPerRow: Int
    let bytesPerPixel: Int
    let redOffset: Int
    let width: Int
    let height: Int

    /// Calls `body` with a raster over the pixels of `image`.
    static func with<R>(_ image: RGBImage, _ body: (EdgeSamplerRaster) -> R) -> R {
        image.pixels.withUnsafeBytes { bytes in
            let usable = image.width > 0 && image.height > 0 && bytes.count >= image.width * image.height * 3
            return body(EdgeSamplerRaster(bytes: bytes, bytesPerRow: image.width * 3, bytesPerPixel: 3, redOffset: 0,
                                          width: usable ? image.width : 0, height: usable ? image.height : 0))
        }
    }

    /// Calls `body` with a raster over the pixels of `frame` (BGRA or RGB), without copying them.
    static func with<R>(_ frame: Frame, _ body: (EdgeSamplerRaster) -> R) -> R {
        let size = frame.size
        let bytesPerPixel = frame.bytesPerPixel
        let redOffset = frame.redOffset
        return frame.withUnsafeBytes { bytes, bytesPerRow in
            let usable = size.width > 0 && size.height > 0 && bytes.baseAddress != nil
                && bytesPerRow >= size.width * bytesPerPixel && bytes.count >= bytesPerRow * size.height
            return body(EdgeSamplerRaster(bytes: bytes, bytesPerRow: bytesPerRow, bytesPerPixel: bytesPerPixel,
                                          redOffset: redOffset, width: usable ? size.width : 0,
                                          height: usable ? size.height : 0))
        }
    }

    var size: PixelSize {
        PixelSize(width: width, height: height)
    }

    /// Bilinear RGB sample at a sub-pixel position; nil outside the image.
    func sample(x: Double, y: Double) -> SIMD3<Float>? {
        guard width > 0, height > 0, x >= -0.5, y >= -0.5, x <= Double(width) - 0.5, y <= Double(height) - 0.5
        else { return nil }
        let cx = min(max(x, 0), Double(width - 1))
        let cy = min(max(y, 0), Double(height - 1))
        let x0 = min(Int(cx), max(0, width - 2)), y0 = min(Int(cy), max(0, height - 2))
        let x1 = min(x0 + 1, width - 1), y1 = min(y0 + 1, height - 1)
        let fx = Float(cx - Double(x0)), fy = Float(cy - Double(y0))
        let p00 = pixel(x0, y0), p10 = pixel(x1, y0), p01 = pixel(x0, y1), p11 = pixel(x1, y1)
        let top = p00 + (p10 - p00) * fx
        let bottom = p01 + (p11 - p01) * fx
        return top + (bottom - top) * fy
    }

    /// The RGB value of pixel `(x, y)`, which must be inside the image.
    func pixel(_ x: Int, _ y: Int) -> SIMD3<Float> {
        let index = y * bytesPerRow + x * bytesPerPixel
        let red = bytes[index + redOffset]
        let green = bytes[index + 1]
        let blue = bytes[index + 2 - redOffset]
        return SIMD3(Float(red), Float(green), Float(blue))
    }
}
