import Foundation
import simd
import CoreGraphics
import CoreVideo
import DartCore

/// Averages rectified frames (UInt16 sums).
public struct FrameAccumulator: Sendable {
    /// Per-channel sums, `width * height * 3` values; empty until the first frame.
    private var sums: [UInt16]
    /// 255 where every frame added so far was valid.
    private var validity: [UInt8]
    private var width: Int
    private var height: Int
    private var frames: Int
    /// The last two frames added, for the noise estimate (arrays are shared, not copied).
    private var latest: CanvasImage?
    private var previous: CanvasImage?

    public init() {
        sums = []
        validity = []
        width = 0
        height = 0
        frames = 0
        latest = nil
        previous = nil
    }

    public var count: Int {
        frames
    }

    /// Adds one frame. A frame whose size differs from the frames already added starts a new average.
    /// The sums hold at most 257 frames; later frames only feed the noise estimate.
    public mutating func add(_ image: CanvasImage) {
        let w = image.rgb.width, h = image.rgb.height
        guard w > 0, h > 0, image.rgb.pixels.count == w * h * 3,
              image.valid.width == w, image.valid.height == h, image.valid.pixels.count == w * h else { return }
        if frames > 0, w != width || h != height {
            reset()
        }
        if frames == 0 {
            width = w
            height = h
            sums = [UInt16](repeating: 0, count: w * h * 3)
            validity = [UInt8](repeating: 255, count: w * h)
        }
        previous = latest
        latest = image
        guard frames < FrameAccumulator.capacity else { return }
        frames += 1
        image.rgb.pixels.withUnsafeBufferPointer { source in
            sums.withUnsafeMutableBufferPointer { total in
                let count = total.count
                var index = 0
                while index < count {
                    total[index] &+= UInt16(source[index])
                    index += 1
                }
            }
        }
        image.valid.pixels.withUnsafeBufferPointer { source in
            validity.withUnsafeMutableBufferPointer { flags in
                let count = flags.count
                var index = 0
                while index < count {
                    if source[index] == 0 { flags[index] = 0 }
                    index += 1
                }
            }
        }
    }

    public mutating func reset() {
        sums = []
        validity = []
        width = 0
        height = 0
        frames = 0
        latest = nil
        previous = nil
    }

    /// Mean of the frames added, rounded to the nearest level; a pixel is valid when it was valid in every frame.
    /// Nil when no frame was added.
    public func mean() -> CanvasImage? {
        guard frames > 0 else { return nil }
        if frames == 1, let latest { return latest }
        var pixels = [UInt8](repeating: 0, count: sums.count)
        let divisor = UInt32(frames), half = UInt32(frames / 2)
        sums.withUnsafeBufferPointer { total in
            pixels.withUnsafeMutableBufferPointer { out in
                let count = out.count
                var index = 0
                while index < count {
                    out[index] = UInt8((UInt32(total[index]) + half) / divisor)
                    index += 1
                }
            }
        }
        return CanvasImage(rgb: RGBImage(width: width, height: height, pixels: pixels),
                           valid: GrayImage(width: width, height: height, pixels: validity))
    }

    /// Per-frame noise estimate from the last two frames added: `median|a - b| / 0.954`.
    ///
    /// The median is taken over the three channels of the pixels that are valid in both frames. The differences
    /// are whole levels: the median is interpolated inside its histogram bin, which keeps the estimate usable
    /// for a noise of one or two levels. Nil with fewer than two frames or when no pixel is valid in both.
    public func noiseSigma() -> Double? {
        guard let a = previous, let b = latest,
              a.rgb.width == b.rgb.width, a.rgb.height == b.rgb.height,
              a.rgb.pixels.count == b.rgb.pixels.count, a.valid.pixels.count == b.valid.pixels.count,
              a.rgb.pixels.count == a.valid.pixels.count * 3 else { return nil }
        var histogram = [Int](repeating: 0, count: 256)
        let pixelCount = a.valid.pixels.count
        a.rgb.pixels.withUnsafeBufferPointer { first in
            b.rgb.pixels.withUnsafeBufferPointer { second in
                a.valid.pixels.withUnsafeBufferPointer { firstValid in
                    b.valid.pixels.withUnsafeBufferPointer { secondValid in
                        histogram.withUnsafeMutableBufferPointer { bins in
                            var pixel = 0
                            while pixel < pixelCount {
                                if firstValid[pixel] != 0 && secondValid[pixel] != 0 {
                                    var index = pixel * 3
                                    let stop = index + 3
                                    while index < stop {
                                        let difference = Int(first[index]) - Int(second[index])
                                        bins[difference < 0 ? -difference : difference] += 1
                                        index += 1
                                    }
                                }
                                pixel += 1
                            }
                        }
                    }
                }
            }
        }
        var total = 0
        for bin in histogram {
            total += bin
        }
        guard total > 0 else { return nil }
        // A difference of k levels stands for the interval [k - 0.5, k + 0.5] of the underlying value
        // ([0, 0.5] for k = 0): the median is interpolated linearly inside the bin that holds it.
        let half = Double(total) / 2
        var below = 0.0
        for (level, bin) in histogram.enumerated() where bin > 0 {
            let upTo = below + Double(bin)
            if upTo >= half {
                let lower = level == 0 ? 0 : Double(level) - 0.5
                let upper = Double(level) + 0.5
                let median = lower + (upper - lower) * (half - below) / Double(bin)
                return median / 0.954
            }
            below = upTo
        }
        return nil
    }
}

extension FrameAccumulator {
    /// Largest number of frames the 16-bit sums can hold: 257 * 255 = 65535.
    static let capacity = 257
}
