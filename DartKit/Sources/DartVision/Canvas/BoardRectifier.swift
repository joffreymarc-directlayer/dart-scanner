import Foundation
import simd
import CoreGraphics
import CoreVideo
import DartCore

/// Warps camera frames into the canvas through `calibration.boardToImage`.
public struct BoardRectifier: Sendable {
    /// H, row-major: metric board mm to image px.
    private let h: [Double]
    private let imageSize: PixelSize
    private let roi: CanvasMask
    /// Runs of `roi` as flat triples `(row, first column, column after the last)`.
    private let runs: [Int32]
    /// Index in `runs` (in runs, not in values) of the first run of each canvas row; `side + 1` entries.
    private let rowOffsets: [Int]
    /// True when the source is denser than `supersamplingScale`: four reads per canvas pixel.
    private let supersamples: Bool
    private let imageBox: (x: Int, y: Int, width: Int, height: Int)

    public init(calibration: BoardCalibration) {
        let transform = calibration.boardToImage
        h = [transform.row0.x, transform.row0.y, transform.row0.z,
             transform.row1.x, transform.row1.y, transform.row1.z,
             transform.row2.x, transform.row2.y, transform.row2.z]
        imageSize = calibration.imageSize
        roi = BoardRectifier.makeRegionOfInterest(footPoint: calibration.pose.footPoint,
                                                  poseIsApproximate: calibration.pose.isApproximate)
        var flat: [Int32] = []
        flat.reserveCapacity(roi.runCount * 3)
        roi.forEachRun { y, x0, x1 in
            flat.append(Int32(y))
            flat.append(Int32(x0))
            flat.append(Int32(x1))
        }
        runs = flat
        rowOffsets = roi.rowOffsets
        supersamples = BoardRectifier.sourceScale(of: transform) > BoardRectifier.supersamplingScale
        imageBox = BoardRectifier.imageBox(of: flat, transform: h, imageSize: calibration.imageSize)
    }

    /// Bounding box in the camera image of the canvas region of interest (also the gate region).
    public var imageRegionOfInterest: (x: Int, y: Int, width: Int, height: Int) {
        imageBox
    }

    /// Region of interest: board disc r <= 190 mm plus the area where dart bodies can appear.
    public var regionOfInterest: CanvasMask {
        roi
    }

    public func rectify(_ frame: Frame) -> CanvasImage {
        let format = (bytesPerPixel: frame.bytesPerPixel, redOffset: frame.redOffset)
        let size = frame.size
        return warpEverything { band, rectifier in
            frame.withUnsafeBytes { bytes, bytesPerRow in
                rectifier.warp(rows: band, bytes: bytes, bytesPerRow: bytesPerRow, width: size.width, height: size.height,
                               bytesPerPixel: format.bytesPerPixel, redOffset: format.redOffset)
            }
        }
    }

    public func rectify(_ image: RGBImage) -> CanvasImage {
        warpEverything { band, rectifier in
            image.pixels.withUnsafeBytes { bytes in
                rectifier.warp(rows: band, bytes: bytes, bytesPerRow: image.width * 3, width: image.width, height: image.height,
                               bytesPerPixel: 3, redOffset: 0)
            }
        }
    }
}

// MARK: - Region of interest

extension BoardRectifier {
    /// Radius of the board disc that is always rectified, mm (VISION.md §5.2, D1).
    static let boardDiscRadius: Double = 190
    /// A dart body can appear up to this far beyond its tip, away from the camera foot point, mm.
    static let dartBodyReach: Double = 135
    /// Tips are looked for within this radius, mm.
    static let tipRadius: Double = 175
    /// Region used with an approximate pose: the disc inscribed in the canvas, mm.
    static let approximatePoseRadius: Double = 320
    /// Above this source scale (px/mm) a canvas pixel averages four reads.
    static let supersamplingScale: Double = 3

    /// The region of interest of a camera whose foot point is `footPoint` (VISION.md §5.2, D1): the point `q` is
    /// inside when `|q| <= 190`, or when the segment `{q - λ·unit(q - F), 0 <= λ <= 135}` comes within 175 mm of
    /// the centre. With an approximate pose: the disc `|q| <= 320`.
    static func makeRegionOfInterest(footPoint: BoardPoint, poseIsApproximate: Bool) -> CanvasMask {
        let side = BoardCanvas.side
        let scale = BoardCanvas.pixelsPerMillimetre
        let extent = BoardCanvas.halfExtent
        let usesSweep = !poseIsApproximate && footPoint.x.isFinite && footPoint.y.isFinite
        let outer = usesSweep ? tipRadius + dartBodyReach : approximatePoseRadius
        let discSquared = boardDiscRadius * boardDiscRadius
        let tipSquared = tipRadius * tipRadius
        let footX = footPoint.x, footY = footPoint.y
        var triples: [Int32] = []
        triples.reserveCapacity(side * 3)
        var j = 0
        while j < side {
            let row = j
            j += 1
            let y = extent - (Double(row) + 0.5) / scale
            let reach = outer * outer - y * y
            if reach < 0 { continue }
            let xLimit = reach.squareRoot()
            // Columns whose centre has |x| <= xLimit.
            let first = max(0, Int(((extent - xLimit) * scale - 0.5).rounded(.up)))
            let last = min(side - 1, Int(((extent + xLimit) * scale - 0.5).rounded(.down)))
            if first > last { continue }
            if !usesSweep {
                triples.append(Int32(row))
                triples.append(Int32(first))
                triples.append(Int32(last + 1))
                continue
            }
            var runStart = -1
            var i = first
            while i <= last {
                let x = -extent + (Double(i) + 0.5) / scale
                let radiusSquared = x * x + y * y
                var inside = radiusSquared <= discSquared
                if !inside {
                    let vx = x - footX, vy = y - footY
                    let lengthSquared = vx * vx + vy * vy
                    if lengthSquared > 0 {
                        // Projection of q on the direction away from F, clamped to the reach of a dart body.
                        let along = (x * vx + y * vy) / lengthSquared.squareRoot()
                        let lambda = along < 0 ? 0 : (along > dartBodyReach ? dartBodyReach : along)
                        inside = radiusSquared - 2 * lambda * along + lambda * lambda <= tipSquared
                    }
                }
                if inside {
                    if runStart < 0 { runStart = i }
                } else if runStart >= 0 {
                    triples.append(Int32(row))
                    triples.append(Int32(runStart))
                    triples.append(Int32(i))
                    runStart = -1
                }
                i += 1
            }
            if runStart >= 0 {
                triples.append(Int32(row))
                triples.append(Int32(runStart))
                triples.append(Int32(last + 1))
            }
        }
        return CanvasMask(unsortedSpans: triples)
    }

    /// Largest source scale (px/mm, best direction) over the bull and eight points of the outer double wire.
    private static func sourceScale(of transform: Homography) -> Double {
        var largest = transform.localScale(at: SIMD2(0, 0)).max
        for k in 0..<8 {
            let angle = Double(k) * .pi / 4
            let scale = transform.localScale(at: SIMD2(170 * sin(angle), 170 * cos(angle))).max
            if scale.isFinite, scale > largest { largest = scale }
        }
        return largest.isFinite ? largest : 0
    }

    /// Bounding box, clipped to the image, of the projection of the runs.
    private static func imageBox(of runs: [Int32], transform h: [Double], imageSize: PixelSize)
        -> (x: Int, y: Int, width: Int, height: Int) {
        let scale = BoardCanvas.pixelsPerMillimetre, extent = BoardCanvas.halfExtent
        var minU = Double.infinity, minV = Double.infinity, maxU = -Double.infinity, maxV = -Double.infinity
        // Sign of the homogeneous coordinate at the bull: the board is on that side of the horizon.
        let sign: Double = h[8] < 0 ? -1 : 1
        var index = 0
        while index + 2 < runs.count {
            let row = Double(runs[index])
            // The four corners of the run, half a pixel beyond the centres of its end pixels.
            var corner = 0
            while corner < 4 {
                let px = corner % 2 == 0 ? Double(runs[index + 1]) - 0.5 : Double(runs[index + 2]) - 0.5
                let py = corner < 2 ? row - 0.5 : row + 0.5
                corner += 1
                let x = -extent + (px + 0.5) / scale, y = extent - (py + 0.5) / scale
                let w = h[6] * x + h[7] * y + h[8]
                if !(w * sign > 0) { continue }
                let u = (h[0] * x + h[1] * y + h[2]) / w, v = (h[3] * x + h[4] * y + h[5]) / w
                if !(u.isFinite && v.isFinite) { continue }
                if u < minU { minU = u }
                if u > maxU { maxU = u }
                if v < minV { minV = v }
                if v > maxV { maxV = v }
            }
            index += 3
        }
        guard minU <= maxU, minV <= maxV, imageSize.width > 0, imageSize.height > 0 else { return (0, 0, 0, 0) }
        let widthLimit = Double(imageSize.width - 1), heightLimit = Double(imageSize.height - 1)
        guard maxU >= -0.5, maxV >= -0.5, minU <= widthLimit + 0.5, minV <= heightLimit + 0.5 else { return (0, 0, 0, 0) }
        let x0 = Int(max(0, min(widthLimit, minU.rounded(.down))))
        let y0 = Int(max(0, min(heightLimit, minV.rounded(.down))))
        let x1 = Int(max(0, min(widthLimit, maxU.rounded(.up))))
        let y1 = Int(max(0, min(heightLimit, maxV.rounded(.up))))
        return (x0, y0, x1 - x0 + 1, y1 - y0 + 1)
    }
}

// MARK: - Warp

extension BoardRectifier {
    /// The canvas rows of one band: `count * side * 3` colour bytes and `count * side` validity flags.
    private struct Band: Sendable {
        var rgb: [UInt8]
        var valid: [UInt8]
    }

    /// Warps every band concurrently and puts the canvas together. One canvas row is computed by one band only:
    /// the result does not depend on the number of cores.
    private func warpEverything(_ body: @Sendable (Range<Int>, BoardRectifier) -> Band) -> CanvasImage {
        let side = BoardCanvas.side
        var rgb = [UInt8](repeating: 0, count: side * side * 3)
        var valid = [UInt8](repeating: 0, count: side * side)
        let rectifier = self
        let bands = ImagingParallel.bands(of: 0..<side, minimumBand: 16)
        let parts = ImagingParallel.map(bands) { band in body(band, rectifier) }
        for (band, part) in zip(bands, parts) {
            ImagingParallel.place(part.rgb, band: band, partRowBytes: side * 3, into: &rgb, rowBytes: side * 3, firstByte: 0)
            ImagingParallel.place(part.valid, band: band, partRowBytes: side, into: &valid, rowBytes: side, firstByte: 0)
        }
        return CanvasImage(rgb: RGBImage(width: side, height: side, pixels: rgb),
                           valid: GrayImage(width: side, height: side, pixels: valid))
    }

    /// Fills the canvas rows of `rows`. Along a run the three homogeneous coordinates are affine in the column:
    /// three additions and one division per pixel, then a bilinear read with 8-bit weights.
    private func warp(rows: Range<Int>, bytes: UnsafeRawBufferPointer, bytesPerRow: Int, width: Int, height: Int,
                      bytesPerPixel: Int, redOffset: Int) -> Band {
        let side = BoardCanvas.side
        var band = Band(rgb: [UInt8](repeating: 0, count: rows.count * side * 3), valid: [UInt8](repeating: 0, count: rows.count * side))
        // A calibration only holds for frames of its own size; anything else gives a canvas with no valid pixel.
        guard width == imageSize.width, height == imageSize.height, width > 0, height > 0,
              bytesPerPixel >= 3, redOffset == 0 || redOffset == 2,
              bytesPerRow >= width * bytesPerPixel,
              bytes.count >= bytesPerRow * (height - 1) + width * bytesPerPixel,
              let sourceBase = bytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
              h.count == 9, h[8] != 0, h.allSatisfy({ $0.isFinite }) else { return band }
        band.rgb.withUnsafeMutableBufferPointer { rgbBuffer in
            band.valid.withUnsafeMutableBufferPointer { validBuffer in
                guard let out = rgbBuffer.baseAddress, let mask = validBuffer.baseAddress else { return }
                warp(rows: rows, base: sourceBase, bytesPerRow: bytesPerRow, width: width, height: height,
                     bytesPerPixel: bytesPerPixel, redOffset: redOffset, into: out, valid: mask)
            }
        }
        return band
    }

    /// Writes the canvas rows `rows` into `out` and `mask`, whose first row is `rows.lowerBound`.
    private func warp(rows: Range<Int>, base: UnsafePointer<UInt8>, bytesPerRow: Int, width: Int, height: Int,
                      bytesPerPixel: Int, redOffset: Int, into out: UnsafeMutablePointer<UInt8>,
                      valid mask: UnsafeMutablePointer<UInt8>) {
        let side = BoardCanvas.side
        let extent = BoardCanvas.halfExtent
        let step = 1 / BoardCanvas.pixelsPerMillimetre
        let h11 = h[0], h12 = h[1], h13 = h[2], h21 = h[3], h22 = h[4], h23 = h[5], h31 = h[6], h32 = h[7], h33 = h[8]
        // The board is on the side of the horizon where the homogeneous coordinate has the sign it has at the bull.
        let sign: Double = h33 < 0 ? -1 : 1
        let da = h11 * step, db = h21 * step, dw = h31 * step
        let maxU = Double(width) - 0.5, maxV = Double(height) - 0.5
        let lastColumn = Double(width - 1), lastRow = Double(height - 1)
        let blueOffset = 2 - redOffset
        // Offsets of the four reads, a quarter of a canvas pixel around the centre, in homogeneous coordinates.
        let quarter = 0.25 * step
        let fourReads = supersamples
        let taps = fourReads ? 4 : 1

        runs.withUnsafeBufferPointer { run in
            var index = rowOffsets[rows.lowerBound] * 3
            let end = rowOffsets[rows.upperBound] * 3
            while index < end {
                let row = Int(run[index]), first = Int(run[index + 1]), afterLast = Int(run[index + 2])
                index += 3
                let y = extent - (Double(row) + 0.5) * step
                let x = -extent + (Double(first) + 0.5) * step
                var a = h11 * x + h12 * y + h13
                var b = h21 * x + h22 * y + h23
                var w = h31 * x + h32 * y + h33
                var pixel = out + ((row - rows.lowerBound) * side + first) * 3
                var flag = mask + (row - rows.lowerBound) * side + first
                var column = first
                while column < afterLast {
                    var red = 0, green = 0, blue = 0, reads = 0
                    var tap = 0
                    while tap < taps {
                        var ta = a, tb = b, tw = w
                        if fourReads {
                            // (-,-), (+,-), (-,+), (+,+) quarter-pixel offsets in canvas x and y.
                            let sx: Double = tap & 1 == 0 ? -quarter : quarter
                            let sy: Double = tap & 2 == 0 ? -quarter : quarter
                            ta += h11 * sx + h12 * sy
                            tb += h21 * sx + h22 * sy
                            tw += h31 * sx + h32 * sy
                        }
                        tap += 1
                        if !(tw * sign > 0) { break }
                        let inverse = 1 / tw
                        var u = ta * inverse, v = tb * inverse
                        // The image covers [-0.5, width - 0.5] x [-0.5, height - 0.5]; the edge pixel is replicated.
                        if !(u >= -0.5 && v >= -0.5 && u <= maxU && v <= maxV) { break }
                        if u < 0 { u = 0 } else if u > lastColumn { u = lastColumn }
                        if v < 0 { v = 0 } else if v > lastRow { v = lastRow }
                        let sourceColumn = Int(u), sourceRow = Int(v)
                        let fx = Int((u - Double(sourceColumn)) * 256 + 0.5), fy = Int((v - Double(sourceRow)) * 256 + 0.5)
                        let nextColumn = sourceColumn + 1 < width ? sourceColumn + 1 : sourceColumn
                        let nextRow = sourceRow + 1 < height ? sourceRow + 1 : sourceRow
                        let p00 = base + (sourceRow * bytesPerRow + sourceColumn * bytesPerPixel)
                        let p10 = base + (sourceRow * bytesPerRow + nextColumn * bytesPerPixel)
                        let p01 = base + (nextRow * bytesPerRow + sourceColumn * bytesPerPixel)
                        let p11 = base + (nextRow * bytesPerRow + nextColumn * bytesPerPixel)
                        let wx = 256 - fx, wy = 256 - fy
                        red += ((Int(p00[redOffset]) * wx + Int(p10[redOffset]) * fx) * wy
                            + (Int(p01[redOffset]) * wx + Int(p11[redOffset]) * fx) * fy + 32768) >> 16
                        green += ((Int(p00[1]) * wx + Int(p10[1]) * fx) * wy
                            + (Int(p01[1]) * wx + Int(p11[1]) * fx) * fy + 32768) >> 16
                        blue += ((Int(p00[blueOffset]) * wx + Int(p10[blueOffset]) * fx) * wy
                            + (Int(p01[blueOffset]) * wx + Int(p11[blueOffset]) * fx) * fy + 32768) >> 16
                        reads += 1
                    }
                    if reads == taps {
                        if fourReads {
                            red = (red + 2) >> 2
                            green = (green + 2) >> 2
                            blue = (blue + 2) >> 2
                        }
                        pixel[0] = UInt8(red)
                        pixel[1] = UInt8(green)
                        pixel[2] = UInt8(blue)
                        flag[0] = 255
                    }
                    a += da
                    b += db
                    w += dw
                    pixel += 3
                    flag += 1
                    column += 1
                }
            }
        }
    }
}
