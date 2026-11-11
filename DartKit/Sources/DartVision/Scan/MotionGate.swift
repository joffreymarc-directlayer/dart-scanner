import Foundation
import simd
import CoreGraphics
import CoreVideo
import DartCore

/// Cheap per-frame motion measurement on a small green-channel copy of the board region.
///
/// VISION.md §6.1. The gate image is the bounding box of the region of interest in the source image
/// (`BoardRectifier.imageRegionOfInterest`), green channel, averaged over square blocks of a whole factor so that its
/// long side is at most `gateLongSide` pixels. A gate pixel has changed when it differs by more than
/// `T_g = max(gatePixelDeltaFloor, gatePixelDeltaSigmas · noiseSigma)` levels:
///
/// - `motionFraction`: against the previous frame (0 for the first frame after a start or a restart);
/// - `changeVsReference`: against the gate image stored by `setReferenceToCurrent()` (1 while there is none). A
///   pixel counts as changed when it leaves the range of the reference over its 3×3 neighbourhood by more than `T_g`:
///   a slow sway of the tripod by a fraction of a gate pixel moves the edges of the board without changing anything
///   that lasts, while a new dart, a hand or a change of light leaves that range (the gate's edge guard);
/// - `borderChange`: the same, over the band of `gateBorderBand` gate pixels along the border of the gate image
///   (0 while there is no reference);
/// - `meanLuma`: mean green level of the gate image.
///
/// `noiseSigma` is the gate noise of the last arming, committed by the engine (`commitNoise`); it is 0 before.
public struct MotionGate: Sendable {
    public init(calibration: BoardCalibration, parameters: ScanParameters = .init()) {
        let box = BoardRectifier(calibration: calibration).imageRegionOfInterest
        self.init(region: MotionGateRegion(x: box.x, y: box.y, width: box.width, height: box.height), parameters: parameters)
    }

    public mutating func ingest(_ frame: Frame) -> GateSample {
        let frameLayout = layout(for: frame.size)
        let image = frameLayout.map { gateImage(of: frame, layout: $0) } ?? []
        let threshold = Float(currentThreshold)
        var motion = 0.0
        var noiseEstimate: Double?
        let comparable = !image.isEmpty && frameLayout == lastLayout
        if comparable, let previous, previous.count == image.count {
            motion = MotionGate.changedFraction(image, previous, threshold: threshold)
            noiseEstimate = MotionGate.pairNoise(image, previous)
        }
        var versusReference = 1.0
        var border = 0.0
        if let frameLayout, !image.isEmpty, frameLayout == referenceLayout, let reference, reference.low.count == image.count {
            versusReference = reference.changedFraction(image, threshold: threshold)
            border = reference.borderFraction(image, width: frameLayout.width, height: frameLayout.height,
                                              band: parameters.gateBorderBand, threshold: threshold)
        }
        var luma = 0.0
        if !image.isEmpty {
            var sum = 0.0
            for value in image {
                sum += Double(value)
            }
            luma = sum / Double(image.count)
        }
        if let noiseEstimate {
            recentNoise.append(noiseEstimate)
            if recentNoise.count > MotionGate.noiseHistory { recentNoise.removeFirst(recentNoise.count - MotionGate.noiseHistory) }
        }
        hadPrevious = comparable && previous?.count == image.count
        previous = image.isEmpty ? nil : image
        current = previous
        lastLayout = frameLayout
        return GateSample(timestamp: frame.timestamp, motionFraction: motion, changeVsReference: versusReference,
                          borderChange: border, meanLuma: luma)
    }

    public mutating func setReferenceToCurrent() {
        guard let current, let lastLayout, current.count == lastLayout.width * lastLayout.height else {
            reference = nil
            referenceLayout = nil
            return
        }
        reference = MotionGateReference(image: current, width: lastLayout.width, height: lastLayout.height)
        referenceLayout = lastLayout
    }

    /// Gate noise in levels, measured over the arming frames.
    public var noiseSigma: Double {
        noise
    }

    // MARK: - Internal state (lot V5)

    /// Bounding box of the region of interest in source pixels.
    let region: MotionGateRegion
    let parameters: ScanParameters
    private var previous: [Float]?
    private var current: [Float]?
    private var reference: MotionGateReference?
    private var lastLayout: Layout?
    private var referenceLayout: Layout?
    private var noise: Double = 0
    /// Per-pair noise estimates of the last frames, oldest first.
    private var recentNoise: [Double] = []
    /// True when the last `ingest` compared its frame with a previous frame of the same layout.
    private(set) var hadPrevious = false
}

/// The gate image stored at the last settle, as the range of each pixel's 3×3 neighbourhood (lot V5).
struct MotionGateReference: Sendable {
    var low: [Float]
    var high: [Float]

    init(image: [Float], width: Int, height: Int) {
        var low = image, high = image
        if width > 0, height > 0, image.count == width * height {
            image.withUnsafeBufferPointer { source in
                low.withUnsafeMutableBufferPointer { lows in
                    high.withUnsafeMutableBufferPointer { highs in
                        for y in 0..<height {
                            for x in 0..<width {
                                var minimum = Float.infinity, maximum = -Float.infinity
                                for dy in max(0, y - 1)...min(height - 1, y + 1) {
                                    for dx in max(0, x - 1)...min(width - 1, x + 1) {
                                        let value = source[dy * width + dx]
                                        minimum = min(minimum, value)
                                        maximum = max(maximum, value)
                                    }
                                }
                                lows[y * width + x] = minimum
                                highs[y * width + x] = maximum
                            }
                        }
                    }
                }
            }
        }
        self.low = low
        self.high = high
    }

    /// Fraction of the pixels of `image` outside their reference range by more than `threshold`.
    func changedFraction(_ image: [Float], threshold: Float) -> Double {
        guard image.count == low.count, !image.isEmpty else { return 0 }
        var changed = 0
        image.withUnsafeBufferPointer { values in
            low.withUnsafeBufferPointer { lows in
                high.withUnsafeBufferPointer { highs in
                    for index in 0..<values.count where values[index] > highs[index] + threshold || values[index] < lows[index] - threshold {
                        changed += 1
                    }
                }
            }
        }
        return Double(changed) / Double(image.count)
    }

    /// The same fraction over the band of `band` pixels along the border of a `width × height` gate image.
    func borderFraction(_ image: [Float], width: Int, height: Int, band: Int, threshold: Float) -> Double {
        guard image.count == low.count, image.count == width * height, width > 0, height > 0 else { return 0 }
        let thickness = max(1, band)
        var considered = 0, changed = 0
        for y in 0..<height {
            let inRowBand = y < thickness || y >= height - thickness
            for x in 0..<width where inRowBand || x < thickness || x >= width - thickness {
                considered += 1
                let index = y * width + x
                if image[index] > high[index] + threshold || image[index] < low[index] - threshold { changed += 1 }
            }
        }
        return considered > 0 ? Double(changed) / Double(considered) : 0
    }
}

/// Bounding box of the gate region in source pixels (lot V5).
struct MotionGateRegion: Hashable, Sendable {
    var x: Int
    var y: Int
    var width: Int
    var height: Int
}

// MARK: - Engine hooks (lot V5)

extension MotionGate {
    /// Per-pair noise estimates kept for the arming measurement.
    static let noiseHistory = 64

    init(region: MotionGateRegion, parameters: ScanParameters) {
        self.region = region
        self.parameters = parameters
    }

    /// Per-pixel change threshold `T_g`, levels.
    var currentThreshold: Double {
        let scaled = parameters.gatePixelDeltaSigmas * noise
        return max(parameters.gatePixelDeltaFloor, scaled.isFinite ? scaled : 0)
    }

    /// True once a reference is stored.
    var hasReference: Bool {
        reference != nil
    }

    /// "Porte relancée": the next frame is not compared with an old one (its `motionFraction` is 0).
    /// The reference is kept.
    mutating func restart() {
        previous = nil
        hadPrevious = false
        recentNoise = []
    }

    /// Forgets the reference: `changeVsReference` is 1 until the next `setReferenceToCurrent()`.
    mutating func clearReference() {
        reference = nil
        referenceLayout = nil
    }

    /// Keeps a noise measured by an earlier gate of the same camera.
    mutating func adoptNoise(_ sigma: Double) {
        if sigma.isFinite, sigma >= 0 { noise = sigma }
    }

    /// Commits the gate noise: the median of the last `frames` per-pair estimates (the quiet frames of an arming).
    mutating func commitNoise(frames: Int) {
        let recent = recentNoise.suffix(max(1, frames)).sorted()
        guard !recent.isEmpty else { return }
        let middle = recent.count / 2
        noise = recent.count % 2 == 1 ? recent[middle] : (recent[middle - 1] + recent[middle]) / 2
    }

    /// The gate of a new calibration (a relock). The images are kept when the gate image keeps its layout for
    /// frames of the calibration's size: the reference then still describes the scene before the move, which is
    /// what `changeVsReference` must compare with. Otherwise the new gate starts without previous frame and
    /// without reference.
    func rebased(on calibration: BoardCalibration) -> MotionGate {
        var gate = MotionGate(calibration: calibration, parameters: parameters)
        gate.noise = noise
        let size = calibration.imageSize
        if let old = layout(for: size), let new = gate.layout(for: size), old.width == new.width, old.height == new.height,
           old.factor == new.factor {
            gate.previous = previous
            gate.current = current
            gate.reference = reference
            gate.recentNoise = recentNoise
            gate.hadPrevious = hadPrevious
            gate.lastLayout = lastLayout == nil ? nil : new
            gate.referenceLayout = referenceLayout == nil ? nil : new
        }
        return gate
    }

    /// The same region with other parameters: a new gate that keeps only the noise (no previous frame, no
    /// reference, since the layout may change with `gateLongSide`).
    func reparameterised(_ newParameters: ScanParameters) -> MotionGate {
        var gate = MotionGate(region: region, parameters: newParameters)
        gate.noise = noise
        return gate
    }
}

// MARK: - Gate image (lot V5)

extension MotionGate {
    /// Block layout of the gate image for one frame size: the region clipped to the frame.
    struct Layout: Hashable, Sendable {
        var x0: Int
        var y0: Int
        var factor: Int
        var width: Int
        var height: Int
    }

    /// Whole block factor so that the long side of the region is at most `longSide` gate pixels.
    static func blockFactor(width: Int, height: Int, longSide: Int) -> Int {
        let side = max(1, longSide)
        let long = max(width, height)
        return max(1, (long + side - 1) / side)
    }

    func layout(for size: PixelSize) -> Layout? {
        let x0 = max(0, region.x), y0 = max(0, region.y)
        let x1 = min(size.width, region.x + region.width), y1 = min(size.height, region.y + region.height)
        guard x1 > x0, y1 > y0 else { return nil }
        let width = x1 - x0, height = y1 - y0
        let factor = MotionGate.blockFactor(width: width, height: height, longSide: parameters.gateLongSide)
        let gateWidth = width / factor, gateHeight = height / factor
        guard gateWidth > 0, gateHeight > 0 else { return nil }
        return Layout(x0: x0, y0: y0, factor: factor, width: gateWidth, height: gateHeight)
    }

    /// Block means of the green channel, row-major, `layout.width × layout.height` values; empty when the frame's
    /// bytes do not cover the layout.
    func gateImage(of frame: Frame, layout: Layout) -> [Float] {
        let bytesPerPixel = frame.bytesPerPixel
        let bands = ImagingParallel.bands(of: 0..<layout.height, minimumBand: 24)
        let parts = ImagingParallel.map(bands) { band in
            frame.withUnsafeBytes { bytes, bytesPerRow in
                MotionGate.blockMeans(bytes, bytesPerRow: bytesPerRow, bytesPerPixel: bytesPerPixel, layout: layout, rows: band)
            }
        }
        var image: [Float] = []
        image.reserveCapacity(layout.width * layout.height)
        for part in parts {
            guard let part else { return [] }
            image.append(contentsOf: part)
        }
        return image.count == layout.width * layout.height ? image : []
    }

    /// Block means of the gate rows `rows`; nil when the bytes do not cover them.
    private static func blockMeans(_ bytes: UnsafeRawBufferPointer, bytesPerRow: Int, bytesPerPixel: Int, layout: Layout,
                                   rows: Range<Int>) -> [Float]? {
        guard let raw = bytes.baseAddress, rows.lowerBound >= 0 else { return nil }
        let factor = layout.factor
        let lastRow = layout.y0 + rows.upperBound * factor - 1
        let lastByte = lastRow * bytesPerRow + (layout.x0 + layout.width * factor) * bytesPerPixel
        guard rows.isEmpty || (lastByte <= bytes.count && bytesPerRow >= (layout.x0 + layout.width * factor) * bytesPerPixel) else {
            return nil
        }
        let base = raw.assumingMemoryBound(to: UInt8.self)
        let scale = 1 / Float(factor * factor)
        var result = [Float](repeating: 0, count: rows.count * layout.width)
        var sums = [UInt32](repeating: 0, count: layout.width)
        result.withUnsafeMutableBufferPointer { out in
            sums.withUnsafeMutableBufferPointer { total in
                var rowIndex = 0
                for gy in rows {
                    for i in 0..<layout.width { total[i] = 0 }
                    let firstSourceRow = layout.y0 + gy * factor
                    for dy in 0..<factor {
                        // The green byte is at offset 1 in both layouts (B, G, R, A and R, G, B).
                        var pointer = base + (firstSourceRow + dy) * bytesPerRow + layout.x0 * bytesPerPixel + 1
                        for gx in 0..<layout.width {
                            var sum: UInt32 = 0
                            for _ in 0..<factor {
                                sum &+= UInt32(pointer.pointee)
                                pointer += bytesPerPixel
                            }
                            total[gx] &+= sum
                        }
                    }
                    let offset = rowIndex * layout.width
                    for gx in 0..<layout.width {
                        out[offset + gx] = Float(total[gx]) * scale
                    }
                    rowIndex += 1
                }
            }
        }
        return result
    }

    /// Fraction of the values of `a` that differ from `b` by more than `threshold`.
    static func changedFraction(_ a: [Float], _ b: [Float], threshold: Float) -> Double {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var changed = 0
        a.withUnsafeBufferPointer { first in
            b.withUnsafeBufferPointer { second in
                for index in 0..<first.count where abs(first[index] - second[index]) > threshold {
                    changed += 1
                }
            }
        }
        return Double(changed) / Double(a.count)
    }

    /// Per-frame noise of a pair of gate images: `median|a − b| / 0.954`, the median read from a histogram of
    /// 1/16-level bins and interpolated inside its bin.
    static func pairNoise(_ a: [Float], _ b: [Float]) -> Double? {
        guard a.count == b.count, !a.isEmpty else { return nil }
        let binsPerLevel: Float = 16
        let binCount = 64 * Int(binsPerLevel)
        var histogram = [Int](repeating: 0, count: binCount + 1)
        a.withUnsafeBufferPointer { first in
            b.withUnsafeBufferPointer { second in
                histogram.withUnsafeMutableBufferPointer { bins in
                    for index in 0..<first.count {
                        let difference = abs(first[index] - second[index]) * binsPerLevel
                        let bin = difference.isFinite ? min(binCount, Int(difference)) : binCount
                        bins[bin] += 1
                    }
                }
            }
        }
        let half = Double(a.count) / 2
        var below = 0.0
        for (bin, count) in histogram.enumerated() where count > 0 {
            let upTo = below + Double(count)
            if upTo >= half {
                let lower = Double(bin) / Double(binsPerLevel)
                let median = lower + (half - below) / Double(count) / Double(binsPerLevel)
                return median / 0.954
            }
            below = upTo
        }
        return nil
    }
}
