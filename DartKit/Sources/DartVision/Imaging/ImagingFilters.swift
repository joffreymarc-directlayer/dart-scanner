import Foundation

// Whole-image filters shared by the synthetic renderer and by later stages (lot V1, internal).

extension RGBImage {
    /// `passes` box blurs of 3x3 pixels, edges replicated. Each pass rounds to the nearest level.
    /// `columns` and `rows` restrict the work to a rectangle (the rest of the image is copied unchanged);
    /// the blur still reads the pixels around the rectangle.
    func boxBlurred(passes: Int, columns: Range<Int>? = nil, rows: Range<Int>? = nil) -> RGBImage {
        guard passes > 0, width > 0, height > 0, pixels.count == width * height * 3 else { return self }
        let xRange = (columns ?? 0..<width).clamped(to: 0..<width)
        let yRange = (rows ?? 0..<height).clamped(to: 0..<height)
        guard !xRange.isEmpty, !yRange.isEmpty else { return self }
        var current = self
        for _ in 0..<passes {
            current = current.boxBlurredOnce(columns: xRange, rows: yRange)
        }
        return current
    }

    private func boxBlurredOnce(columns: Range<Int>, rows: Range<Int>) -> RGBImage {
        let w = width, h = height
        let first = columns.lowerBound, span = columns.count
        let spanBytes = span * 3
        let image = self
        let bands = ImagingParallel.bands(of: rows, minimumBand: 32)
        let parts = ImagingParallel.map(bands) { band -> [UInt8] in
            var part = [UInt8](repeating: 0, count: band.count * spanBytes)
            // Horizontal sums of three consecutive rows, kept in a ring: row y lives in slot y mod 3.
            var sums = [UInt16](repeating: 0, count: spanBytes * 3)
            image.pixels.withUnsafeBufferPointer { source in
                part.withUnsafeMutableBufferPointer { output in
                    sums.withUnsafeMutableBufferPointer { ring in
                        guard let src = source.baseAddress, let dst = output.baseAddress, let ringBase = ring.baseAddress else { return }
                        func horizontal(_ y: Int, into slot: Int) {
                            let row = src + (y < 0 ? 0 : (y > h - 1 ? h - 1 : y)) * w * 3
                            let out = ringBase + slot * spanBytes
                            var o = 0
                            var x = first
                            let stop = first + span
                            while x < stop {
                                let left = (x > 0 ? x - 1 : 0) * 3, centre = x * 3, right = (x + 1 < w ? x + 1 : w - 1) * 3
                                out[o] = UInt16(row[left]) + UInt16(row[centre]) + UInt16(row[right])
                                out[o + 1] = UInt16(row[left + 1]) + UInt16(row[centre + 1]) + UInt16(row[right + 1])
                                out[o + 2] = UInt16(row[left + 2]) + UInt16(row[centre + 2]) + UInt16(row[right + 2])
                                o += 3
                                x += 1
                            }
                        }
                        horizontal(band.lowerBound - 1, into: (band.lowerBound + 2) % 3)
                        horizontal(band.lowerBound, into: band.lowerBound % 3)
                        var y = band.lowerBound
                        while y < band.upperBound {
                            horizontal(y + 1, into: (y + 1) % 3)
                            let a = ringBase, b = ringBase + spanBytes, c = ringBase + 2 * spanBytes
                            let out = dst + (y - band.lowerBound) * spanBytes
                            var i = 0
                            while i < spanBytes {
                                let sum = UInt32(a[i]) + UInt32(b[i]) + UInt32(c[i])
                                // (sum + 4) / 9 by multiplication: exact for sums up to 9 * 255.
                                out[i] = UInt8(((sum + 4) * 7282) >> 16)
                                i += 1
                            }
                            y += 1
                        }
                    }
                }
            }
            return part
        }
        var output = pixels
        for (band, part) in zip(bands, parts) {
            ImagingParallel.place(part, band: band, partRowBytes: spanBytes, into: &output, rowBytes: w * 3, firstByte: first * 3)
        }
        return RGBImage(width: w, height: h, pixels: output)
    }

    /// The image moved by `(dx, dy)` pixels (the content moves right and down for positive values), resampled
    /// bilinearly with replicated edges. `columns` and `rows` restrict the work to a rectangle.
    func shifted(dx: Double, dy: Double, columns: Range<Int>? = nil, rows: Range<Int>? = nil) -> RGBImage {
        guard dx != 0 || dy != 0, dx.isFinite, dy.isFinite, width > 0, height > 0,
              pixels.count == width * height * 3 else { return self }
        let xRange = (columns ?? 0..<width).clamped(to: 0..<width)
        let yRange = (rows ?? 0..<height).clamped(to: 0..<height)
        guard !xRange.isEmpty, !yRange.isEmpty else { return self }
        let w = width, h = height
        // Output pixel (x, y) reads the source at (x - dx, y - dy): a whole offset plus a fixed fraction.
        let wholeX = (-dx).rounded(.down), wholeY = (-dy).rounded(.down)
        let offsetX = Int(max(-1e9, min(1e9, wholeX))), offsetY = Int(max(-1e9, min(1e9, wholeY)))
        let fx = Int(((-dx - wholeX) * 256).rounded()), fy = Int(((-dy - wholeY) * 256).rounded())
        let firstColumn = xRange.lowerBound, afterLastColumn = xRange.upperBound
        let spanBytes = xRange.count * 3
        let image = self
        let bands = ImagingParallel.bands(of: yRange, minimumBand: 32)
        let parts = ImagingParallel.map(bands) { band -> [UInt8] in
            var part = [UInt8](repeating: 0, count: band.count * spanBytes)
            image.pixels.withUnsafeBufferPointer { source in
                part.withUnsafeMutableBufferPointer { output in
                    guard let src = source.baseAddress, let dst = output.baseAddress else { return }
                    func clamped(_ value: Int, _ limit: Int) -> Int {
                        value < 0 ? 0 : (value > limit ? limit : value)
                    }
                    var y = band.lowerBound
                    while y < band.upperBound {
                        let top = src + clamped(y + offsetY, h - 1) * w * 3
                        let bottom = src + clamped(y + offsetY + 1, h - 1) * w * 3
                        var out = dst + (y - band.lowerBound) * spanBytes
                        var x = firstColumn
                        while x < afterLastColumn {
                            let x0 = clamped(x + offsetX, w - 1) * 3, x1 = clamped(x + offsetX + 1, w - 1) * 3
                            var channel = 0
                            while channel < 3 {
                                let a = Int(top[x0 + channel]), b = Int(top[x1 + channel])
                                let c = Int(bottom[x0 + channel]), d = Int(bottom[x1 + channel])
                                let upper = a * (256 - fx) + b * fx
                                let lower = c * (256 - fx) + d * fx
                                out[channel] = UInt8((upper * (256 - fy) + lower * fy + 32768) >> 16)
                                channel += 1
                            }
                            out += 3
                            x += 1
                        }
                        y += 1
                    }
                }
            }
            return part
        }
        var output = pixels
        for (band, part) in zip(bands, parts) {
            ImagingParallel.place(part, band: band, partRowBytes: spanBytes, into: &output, rowBytes: w * 3,
                                  firstByte: firstColumn * 3)
        }
        return RGBImage(width: w, height: h, pixels: output)
    }

    /// Mean of the absolute differences of the three channels over the pixels where `mask` is non-zero
    /// (every pixel when `mask` is nil). Nil when the sizes differ or no pixel is selected.
    func meanAbsoluteDifference(to other: RGBImage, where mask: GrayImage? = nil) -> Double? {
        guard width == other.width, height == other.height, pixels.count == other.pixels.count,
              pixels.count == width * height * 3 else { return nil }
        if let mask, mask.width != width || mask.height != height || mask.pixels.count != width * height { return nil }
        var total = 0
        var count = 0
        let pixelCount = width * height
        let selection = mask?.pixels ?? []
        pixels.withUnsafeBufferPointer { a in
            other.pixels.withUnsafeBufferPointer { b in
                selection.withUnsafeBufferPointer { selected in
                    let everything = selected.count != pixelCount
                    var index = 0
                    while index < pixelCount {
                        if everything || selected[index] != 0 {
                            var i = index * 3
                            let stop = i + 3
                            while i < stop {
                                let difference = Int(a[i]) - Int(b[i])
                                total += difference < 0 ? -difference : difference
                                i += 1
                            }
                            count += 3
                        }
                        index += 1
                    }
                }
            }
        }
        return count > 0 ? Double(total) / Double(count) : nil
    }
}
