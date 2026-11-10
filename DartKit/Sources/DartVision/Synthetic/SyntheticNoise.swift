import Foundation

/// Seeded gain and Gaussian noise for rendered images (VISION.md §10.1). Internal to DartVision.
///
/// Every row draws from its own SplitMix64 stream, derived from the seed and the row number: the result is the
/// same, bit for bit, whatever the number of cores, and two images of different widths share nothing.
enum SyntheticNoise {
    /// Number of equally likely values of the Gaussian table.
    private static let tableSize = 4096

    /// Standard normal quantiles at the middle of `tableSize` equal bins, rescaled to unit variance.
    private static let unitTable: [Double] = {
        var values = [Double](repeating: 0, count: tableSize)
        var sumOfSquares = 0.0
        for index in 0..<tableSize {
            let z = inverseNormal((Double(index) + 0.5) / Double(tableSize))
            values[index] = z
            sumOfSquares += z * z
        }
        let scale = (Double(tableSize) / sumOfSquares).squareRoot()
        return values.map { $0 * scale }
    }()

    /// One SplitMix64 step: the finaliser of GAMES.md §2.8 applied to `x + γ`.
    @inline(__always)
    static func mix(_ x: UInt64) -> UInt64 {
        var z = x &+ 0x9E37_79B9_7F4A_7C15
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Multiplies every channel by `gain`, adds Gaussian noise of standard deviation `sigma` levels and clamps.
    /// `bytesPerRow` values per row. Row `r` draws from a stream seeded by `seed` and `r` alone.
    static func apply(to pixels: inout [UInt8], bytesPerRow: Int, gain: Double, sigma: Double, seed: UInt64) {
        let usesGain = gain.isFinite && gain != 1
        let usesNoise = sigma.isFinite && sigma > 0
        guard usesGain || usesNoise, bytesPerRow > 0, !pixels.isEmpty else { return }
        let rows = pixels.count / bytesPerRow

        // Fixed point with 8 fractional bits.
        var gainTable = [Int32](repeating: 0, count: 256)
        let factor = usesGain ? max(0, gain) : 1
        for level in 0..<256 {
            gainTable[level] = Int32(min(255 * 256, (Double(level) * factor * 256).rounded()))
        }
        var noiseTable = [Int32](repeating: 0, count: tableSize)
        if usesNoise {
            let limited = min(sigma, 1e6)
            for index in 0..<tableSize {
                noiseTable[index] = Int32((unitTable[index] * limited * 256).rounded())
            }
        }
        let mask = UInt64(tableSize - 1)
        let source = pixels
        let gains = gainTable, noise = noiseTable
        let bands = ImagingParallel.bands(of: 0..<rows, minimumBand: 16)
        let parts = ImagingParallel.map(bands) { band -> [UInt8] in
            var part = Array(source[(band.lowerBound * bytesPerRow)..<(band.upperBound * bytesPerRow)])
            part.withUnsafeMutableBufferPointer { buffer in
                gains.withUnsafeBufferPointer { gainBuffer in
                    noise.withUnsafeBufferPointer { noiseBuffer in
                        guard let out = buffer.baseAddress, let gainBase = gainBuffer.baseAddress,
                              let noiseBase = noiseBuffer.baseAddress else { return }
                        var row = band.lowerBound
                        while row < band.upperBound {
                            let line = out + (row - band.lowerBound) * bytesPerRow
                            var index = 0
                            if !usesNoise {
                                while index < bytesPerRow {
                                    line[index] = UInt8((gainBase[Int(line[index])] + 128) >> 8)
                                    index += 1
                                }
                                row += 1
                                continue
                            }
                            var state = mix(seed ^ mix(UInt64(row)))
                            var bits: UInt64 = 0
                            var available = 0
                            while index < bytesPerRow {
                                if available == 0 {
                                    state &+= 0x9E37_79B9_7F4A_7C15
                                    var z = state
                                    z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
                                    z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
                                    bits = z ^ (z >> 31)
                                    // Five 12-bit values per draw.
                                    available = 5
                                }
                                let value = gainBase[Int(line[index])] + noiseBase[Int(bits & mask)] + 128
                                bits >>= 12
                                available -= 1
                                line[index] = value <= 0 ? 0 : (value >= 255 * 256 + 128 ? 255 : UInt8(value >> 8))
                                index += 1
                            }
                            row += 1
                        }
                    }
                }
            }
            return part
        }
        for (band, part) in zip(bands, parts) {
            ImagingParallel.place(part, band: band, partRowBytes: bytesPerRow, into: &pixels, rowBytes: bytesPerRow, firstByte: 0)
        }
    }

    /// Inverse of the standard normal distribution function (Acklam's rational approximation, relative error 1e-9).
    static func inverseNormal(_ p: Double) -> Double {
        guard p > 0 else { return -Double.infinity }
        guard p < 1 else { return Double.infinity }
        let a = [-3.969683028665376e+01, 2.209460984245205e+02, -2.759285104469687e+02,
                 1.383577518672690e+02, -3.066479806614716e+01, 2.506628277459239e+00]
        let b = [-5.447609879822406e+01, 1.615858368580409e+02, -1.556989798598866e+02,
                 6.680131188771972e+01, -1.328068155288572e+01]
        let c = [-7.784894002430293e-03, -3.223964580411365e-01, -2.400758277161838e+00,
                 -2.549732539343734e+00, 4.374664141464968e+00, 2.938163982698783e+00]
        let d = [7.784695709041462e-03, 3.224671290700398e-01, 2.445134137142996e+00, 3.754408661907416e+00]
        let low = 0.02425
        if p < low {
            let q = (-2 * log(p)).squareRoot()
            return (((((c[0] * q + c[1]) * q + c[2]) * q + c[3]) * q + c[4]) * q + c[5])
                / ((((d[0] * q + d[1]) * q + d[2]) * q + d[3]) * q + 1)
        }
        if p <= 1 - low {
            let q = p - 0.5
            let r = q * q
            return (((((a[0] * r + a[1]) * r + a[2]) * r + a[3]) * r + a[4]) * r + a[5]) * q
                / (((((b[0] * r + b[1]) * r + b[2]) * r + b[3]) * r + b[4]) * r + 1)
        }
        let q = (-2 * log(1 - p)).squareRoot()
        return -(((((c[0] * q + c[1]) * q + c[2]) * q + c[3]) * q + c[4]) * q + c[5])
            / ((((d[0] * q + d[1]) * q + d[2]) * q + d[3]) * q + 1)
    }
}
