import Foundation
import simd
import DartCore

/// Steps D2 and D3 of VISION.md §5.2: the shadow-tolerant evidence map of a current canvas against a reference,
/// and the binary mask of what changed. Internal to DartVision (lot V3), tested stage by stage.
///
/// Both canvases are first blurred (`blurRadius` passes of a 3x3 box). Per pixel, with the reference colour `r`
/// and the current colour `c` as RGB vectors, `α* = (c·r) / (r·r + 1)`; the global gain `g` is the median of
/// `α*` on a 16 px grid inside r ≤ 170 mm where `‖r‖ ≥ 60`, away from the known darts; the evidence is the
/// distance from `c` to the segment "same colour, darker or slightly brighter":
/// `e = ‖c − clamp(α*, α_lo·g, α_hi·g)·r‖`, at most 255. A pixel invalid in either canvas has no evidence.
struct ChangeEvidence: Sendable {
    /// Canvas side, pixels.
    let side: Int
    /// `e` per canvas pixel, row-major, 0...255.
    let values: [Float]
    /// 255 where both canvases are valid.
    let valid: [UInt8]
    /// Global brightness gain `g` between the reference and the current canvas.
    let gain: Double
    /// Fraction of the valid part of the disc r ≤ 170 mm where `‖c − g·r‖ ≥ τ`.
    let changedBoardFraction: Double
    /// τ, in 8-bit RGB L2 units.
    let threshold: Double
    /// The blurred canvases the map was computed from.
    let blurredReference: RGBImage
    let blurredCurrent: RGBImage

    /// Computes the map of `current` against `reference`. `excluded` marks the pixels left out of the gain (the
    /// dilated silhouettes of the known darts). `blurredReference` spares the blur of a reference already blurred.
    init(reference: CanvasImage, current: CanvasImage, excluded: CanvasMask, threshold: Double,
         parameters: DetectionParameters, blurredReference cached: RGBImage? = nil) {
        let side = BoardCanvas.side
        self.side = side
        self.threshold = threshold
        let reference = ChangeEvidence.conformed(reference)
        let current = ChangeEvidence.conformed(current)
        var both = [UInt8](repeating: 0, count: side * side)
        reference.valid.pixels.withUnsafeBufferPointer { a in
            current.valid.pixels.withUnsafeBufferPointer { b in
                both.withUnsafeMutableBufferPointer { out in
                    let count = out.count
                    var index = 0
                    while index < count {
                        if a[index] != 0 && b[index] != 0 { out[index] = 255 }
                        index += 1
                    }
                }
            }
        }
        let valid = both
        self.valid = valid
        let blurredReference = cached ?? ChangeEvidence.blurred(reference.rgb, radius: parameters.blurRadius)
        let blurredCurrent = ChangeEvidence.blurred(current.rgb, radius: parameters.blurRadius)
        self.blurredReference = blurredReference
        self.blurredCurrent = blurredCurrent
        let gain = ChangeEvidence.gain(reference: blurredReference, current: blurredCurrent, valid: valid,
                                       excluded: excluded, parameters: parameters)
        self.gain = gain
        let low = Float(parameters.shadowLowerBound * gain), high = Float(parameters.shadowUpperBound * gain)
        let tau = Float(threshold)
        let bands = ImagingParallel.bands(of: 0..<side, minimumBand: 32)
        // Per band: the evidence of its rows, and the counts of the board disc (changed, valid).
        let parts = ImagingParallel.map(bands) { band -> (values: [Float], changed: Int, disc: Int) in
            var values = [Float](repeating: 0, count: band.count * side)
            var changed = 0, disc = 0
            let g = Float(gain)
            blurredReference.pixels.withUnsafeBufferPointer { r in
                blurredCurrent.pixels.withUnsafeBufferPointer { c in
                    valid.withUnsafeBufferPointer { flags in
                        values.withUnsafeMutableBufferPointer { values in
                        for y in band {
                            let discColumns = ChangeEvidence.discColumns(row: y, radius: ChangeEvidence.boardRadius)
                            let discStart = discColumns.lowerBound, discEnd = discColumns.upperBound
                            var x = 0
                            while x < side {
                                defer { x += 1 }
                                let index = y * side + x
                                guard flags[index] != 0 else { continue }
                                let o = index * 3
                                let r0 = Float(r[o]), r1 = Float(r[o + 1]), r2 = Float(r[o + 2])
                                let c0 = Float(c[o]), c1 = Float(c[o + 1]), c2 = Float(c[o + 2])
                                let alpha = (c0 * r0 + c1 * r1 + c2 * r2) / (r0 * r0 + r1 * r1 + r2 * r2 + 1)
                                let a = alpha < low ? low : (alpha > high ? high : alpha)
                                let d0 = c0 - a * r0, d1 = c1 - a * r1, d2 = c2 - a * r2
                                let e = (d0 * d0 + d1 * d1 + d2 * d2).squareRoot()
                                values[(y - band.lowerBound) * side + x] = e < 255 ? e : 255
                                if x >= discStart && x < discEnd {
                                    disc += 1
                                    let n0 = c0 - g * r0, n1 = c1 - g * r1, n2 = c2 - g * r2
                                    if n0 * n0 + n1 * n1 + n2 * n2 >= tau * tau { changed += 1 }
                                }
                            }
                        }
                        }
                    }
                }
            }
            return (values, changed, disc)
        }
        var values = [Float](repeating: 0, count: side * side)
        var changed = 0, disc = 0
        for (band, part) in zip(bands, parts) {
            values.replaceSubrange(band.lowerBound * side..<band.upperBound * side, with: part.values)
            changed += part.changed
            disc += part.disc
        }
        self.values = values
        changedBoardFraction = disc > 0 ? Double(changed) / Double(disc) : 0
    }

    /// Evidence at canvas pixel `(x, y)`; 0 outside the canvas.
    func value(x: Int, y: Int) -> Float {
        guard x >= 0, y >= 0, x < side, y < side else { return 0 }
        return values[y * side + x]
    }

    /// Bilinear evidence at a metric board point; 0 outside the canvas.
    func sample(_ point: SIMD2<Double>) -> Double {
        let pixel = BoardCanvas.pixel(for: BoardPoint(x: point.x, y: point.y))
        guard pixel.x.isFinite, pixel.y.isFinite, pixel.x >= 0, pixel.y >= 0,
              pixel.x <= Double(side - 1), pixel.y <= Double(side - 1) else { return 0 }
        let x0 = min(Int(pixel.x), side - 2), y0 = min(Int(pixel.y), side - 2)
        let fx = pixel.x - Double(x0), fy = pixel.y - Double(y0)
        let a = Double(values[y0 * side + x0]), b = Double(values[y0 * side + x0 + 1])
        let c = Double(values[(y0 + 1) * side + x0]), d = Double(values[(y0 + 1) * side + x0 + 1])
        let top = a + (b - a) * fx, bottom = c + (d - c) * fx
        return top + (bottom - top) * fy
    }

    /// True when canvas pixel `(x, y)` is valid in both canvases.
    func isValid(x: Int, y: Int) -> Bool {
        guard x >= 0, y >= 0, x < side, y < side else { return false }
        return valid[y * side + x] != 0
    }

    /// D3: `(e − edgeGuardPixels·‖∇R‖ ≥ τ)` on the valid pixels outside `cleared`, then an opening and a closing.
    /// `‖∇R‖` is the largest of the three channels' central-difference gradient magnitudes of the blurred reference.
    func mask(cleared: CanvasMask, parameters: DetectionParameters) -> GrayImage {
        let raw = rawMask(cleared: cleared, parameters: parameters)
        let opened = Morphology.open(raw, radius: max(0, parameters.openRadius))
        return Morphology.close(opened, radius: max(0, parameters.closeRadius))
    }

    /// The thresholded, edge-guarded evidence before the morphology.
    func rawMask(cleared: CanvasMask, parameters: DetectionParameters) -> GrayImage {
        let side = self.side
        let tau = Float(threshold)
        let guardFactor = Float(parameters.edgeGuardPixels.isFinite ? max(0, parameters.edgeGuardPixels) : 0)
        var pixels = [UInt8](repeating: 0, count: side * side)
        blurredReference.pixels.withUnsafeBufferPointer { r in
            values.withUnsafeBufferPointer { e in
                valid.withUnsafeBufferPointer { flags in
                    pixels.withUnsafeMutableBufferPointer { out in
                        let count = out.count
                        var index = 0
                        while index < count {
                            defer { index += 1 }
                            let value = e[index]
                            guard value >= tau, flags[index] != 0 else { continue }
                            if guardFactor > 0 {
                                let gradient = ChangeEvidence.gradient(r, side: side, x: index % side, y: index / side)
                                if value - guardFactor * gradient < tau { continue }
                            }
                            out[index] = 255
                        }
                    }
                }
            }
        }
        cleared.forEachRun { y, x0, x1 in
            guard y >= 0, y < side else { return }
            for x in max(0, x0)..<min(side, x1) {
                pixels[y * side + x] = 0
            }
        }
        return GrayImage(width: side, height: side, pixels: pixels)
    }
}

// MARK: - Helpers

extension ChangeEvidence {
    /// Radius of the disc of `changedBoardFraction` and of the gain grid, mm.
    static let boardRadius: Double = 170

    /// `radius` passes of the 3x3 box: the "box 3x3" of `blurRadius = 1`, a wider kernel for larger values.
    static func blurred(_ image: RGBImage, radius: Int) -> RGBImage {
        image.boxBlurred(passes: max(0, min(radius, 16)))
    }

    /// A canvas of the canonical size with consistent buffers; anything else becomes an all-invalid canvas.
    static func conformed(_ image: CanvasImage) -> CanvasImage {
        let side = BoardCanvas.side
        if image.rgb.width == side, image.rgb.height == side, image.rgb.pixels.count == side * side * 3,
           image.valid.width == side, image.valid.height == side, image.valid.pixels.count == side * side {
            return image
        }
        return CanvasImage(rgb: RGBImage(width: side, height: side, fill: SIMD3(0, 0, 0)),
                           valid: GrayImage(width: side, height: side, fill: 0))
    }

    /// Columns of canvas row `row` whose pixel centre lies within `radius` mm of the bull.
    static func discColumns(row: Int, radius: Double) -> Range<Int> {
        let scale = BoardCanvas.pixelsPerMillimetre, extent = BoardCanvas.halfExtent
        let y = extent - (Double(row) + 0.5) / scale
        let reach = radius * radius - y * y
        guard reach >= 0 else { return 0..<0 }
        let limit = reach.squareRoot()
        let first = max(0, Int(((extent - limit) * scale - 0.5).rounded(.up)))
        let last = min(BoardCanvas.side - 1, Int(((extent + limit) * scale - 0.5).rounded(.down)))
        return first <= last ? first..<(last + 1) : 0..<0
    }

    /// D2 step 3: median of `α*` on the grid of `gainGridStep` pixels inside r ≤ 170 mm, where `‖r‖ ≥
    /// gainMinReferenceNorm`, valid, and outside `excluded`. 1 when no grid point qualifies.
    static func gain(reference: RGBImage, current: RGBImage, valid: [UInt8], excluded: CanvasMask,
                     parameters: DetectionParameters) -> Double {
        let side = BoardCanvas.side
        let step = max(1, parameters.gainGridStep)
        let minimumNorm = parameters.gainMinReferenceNorm
        var ratios: [Double] = []
        var y = step / 2
        while y < side {
            let columns = discColumns(row: y, radius: boardRadius)
            var x = step / 2
            while x < side {
                defer { x += step }
                let index = y * side + x
                guard columns.contains(x), valid[index] != 0, !excluded.contains(x: x, y: y) else { continue }
                let o = index * 3
                let r = SIMD3(Double(reference.pixels[o]), Double(reference.pixels[o + 1]), Double(reference.pixels[o + 2]))
                let c = SIMD3(Double(current.pixels[o]), Double(current.pixels[o + 1]), Double(current.pixels[o + 2]))
                let norm = simd_dot(r, r)
                guard norm.squareRoot() >= minimumNorm else { continue }
                ratios.append(simd_dot(c, r) / (norm + 1))
            }
            y += step
        }
        return detectionMedian(ratios) ?? 1
    }

    /// Largest central-difference gradient magnitude of the three channels at `(x, y)`, levels per pixel.
    static func gradient(_ r: UnsafeBufferPointer<UInt8>, side: Int, x: Int, y: Int) -> Float {
        let left = (y * side + max(0, x - 1)) * 3, right = (y * side + min(side - 1, x + 1)) * 3
        let up = (max(0, y - 1) * side + x) * 3, down = (min(side - 1, y + 1) * side + x) * 3
        var largest: Float = 0
        for channel in 0..<3 {
            let gx = (Float(r[right + channel]) - Float(r[left + channel])) / 2
            let gy = (Float(r[down + channel]) - Float(r[up + channel])) / 2
            let magnitude = (gx * gx + gy * gy).squareRoot()
            if magnitude > largest { largest = magnitude }
        }
        return largest
    }
}

/// Median of a list (mean of the two middle values for an even count); nil when empty. Lot V3, internal.
func detectionMedian(_ values: [Double]) -> Double? {
    let sorted = values.filter { $0.isFinite }.sorted()
    guard !sorted.isEmpty else { return nil }
    let middle = sorted.count / 2
    return sorted.count % 2 == 1 ? sorted[middle] : (sorted[middle - 1] + sorted[middle]) / 2
}
