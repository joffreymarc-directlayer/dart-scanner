import Foundation
import simd
import CoreGraphics
import CoreVideo
import DartCore

/// Run-length mask in canvas pixels (board space, so it survives a re-calibration).
public struct CanvasMask: Hashable, Codable, Sendable {
    /// Runs as flat triples `(row, first column, column after the last)`, sorted by row then by column.
    /// Canonical form: inside a row the runs neither overlap nor touch, and every run lies inside the canvas.
    /// Two masks that cover the same pixels are therefore equal.
    private var spans: [Int32]

    public init() {
        spans = []
    }

    private enum CodingKeys: String, CodingKey {
        case spans
    }

    /// Decodes the runs and brings them back to the canonical form, so that a damaged file cannot produce a
    /// mask that reaches outside the canvas.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(unsortedSpans: try container.decode([Int32].self, forKey: .spans))
    }

    /// Mask of the non-zero pixels of `image`. Pixel `(x, y)` of the image is canvas pixel `(x, y)`;
    /// whatever lies beyond the canvas (`BoardCanvas.side`) is dropped.
    public init(_ image: GrayImage) {
        let side = BoardCanvas.side
        let w = min(max(0, image.width), side), h = min(max(0, image.height), side)
        var result: [Int32] = []
        if w > 0, h > 0, image.pixels.count >= image.width * image.height {
            let stride = image.width
            image.pixels.withUnsafeBufferPointer { source in
                var y = 0
                while y < h {
                    defer { y += 1 }
                    let row = y * stride
                    var x = 0
                    while x < w {
                        if source[row + x] == 0 {
                            x += 1
                            continue
                        }
                        let start = x
                        while x < w, source[row + x] != 0 {
                            x += 1
                        }
                        result.append(Int32(y))
                        result.append(Int32(start))
                        result.append(Int32(x))
                    }
                }
            }
        }
        spans = result
    }

    public var isEmpty: Bool {
        spans.isEmpty
    }

    /// Area in mm².
    public var area: Double {
        Double(pixelCount) / (BoardCanvas.pixelsPerMillimetre * BoardCanvas.pixelsPerMillimetre)
    }

    public func contains(_ point: BoardPoint) -> Bool {
        let pixel = BoardCanvas.pixel(for: point)
        guard pixel.x.isFinite, pixel.y.isFinite else { return false }
        let x = pixel.x.rounded(), y = pixel.y.rounded()
        let side = Double(BoardCanvas.side)
        guard x >= 0, y >= 0, x < side, y < side else { return false }
        return contains(x: Int(x), y: Int(y))
    }

    /// Every canvas pixel whose centre is within `millimetres` of the centre of a pixel of the mask.
    public func dilated(by millimetres: Double) -> CanvasMask {
        let radius = millimetres * BoardCanvas.pixelsPerMillimetre
        guard radius.isFinite, radius > 0, !spans.isEmpty else { return self }
        let side = Int32(BoardCanvas.side)
        let reach = Int32(min(radius.rounded(.down), Double(BoardCanvas.side)))
        // Half-width of the disc at each row offset, never wider than the canvas.
        var halfWidths: [Int32] = []
        halfWidths.reserveCapacity(Int(reach) + 1)
        for dy in 0...reach {
            let remaining = radius * radius - Double(dy) * Double(dy)
            let half = min(Double(BoardCanvas.side), max(0, remaining).squareRoot().rounded(.down))
            halfWidths.append(Int32(half))
        }
        var grown: [Int32] = []
        grown.reserveCapacity(spans.count * Int(2 * reach + 1))
        var index = 0
        while index < spans.count {
            let y = spans[index], x0 = spans[index + 1], x1 = spans[index + 2]
            index += 3
            for dy in -reach...reach {
                let row = y + dy
                guard row >= 0, row < side else { continue }
                let half = halfWidths[Int(abs(dy))]
                let start = max(0, x0 - half), end = min(side, x1 + half)
                if start < end {
                    grown.append(row)
                    grown.append(start)
                    grown.append(end)
                }
            }
        }
        return CanvasMask(unsortedSpans: grown)
    }

    public func union(_ other: CanvasMask) -> CanvasMask {
        if other.spans.isEmpty { return self }
        if spans.isEmpty { return other }
        return CanvasMask(unsortedSpans: spans + other.spans)
    }

    public func intersects(_ other: CanvasMask) -> Bool {
        var i = 0, j = 0
        let a = spans, b = other.spans
        while i < a.count, j < b.count {
            if a[i] != b[j] {
                if a[i] < b[j] { i += 3 } else { j += 3 }
                continue
            }
            // Same row: the runs overlap when each starts before the other ends.
            if a[i + 1] < b[j + 2], b[j + 1] < a[i + 2] { return true }
            if a[i + 2] <= b[j + 2] { i += 3 } else { j += 3 }
        }
        return false
    }

    public func makeImage() -> GrayImage {
        let side = BoardCanvas.side
        var pixels = [UInt8](repeating: 0, count: side * side)
        pixels.withUnsafeMutableBufferPointer { out in
            var index = 0
            while index < spans.count {
                let first = Int(spans[index]) * side + Int(spans[index + 1])
                let count = Int(spans[index + 2] - spans[index + 1])
                if let start = out.baseAddress, count > 0 {
                    (start + first).update(repeating: 255, count: count)
                }
                index += 3
            }
        }
        return GrayImage(width: side, height: side, pixels: pixels)
    }
}

// MARK: - Internal helpers (lot V1)

extension CanvasMask {
    /// One horizontal run: canvas row `y`, columns `x0 ..< x1`.
    struct Run: Hashable, Sendable {
        var y: Int
        var x0: Int
        var x1: Int
    }

    /// Builds the canonical form from runs in any order, possibly overlapping or outside the canvas.
    init(unsortedSpans triples: [Int32]) {
        let side = Int32(BoardCanvas.side)
        var runs: [(y: Int32, x0: Int32, x1: Int32)] = []
        runs.reserveCapacity(triples.count / 3)
        var index = 0
        while index + 2 < triples.count {
            let y = triples[index], x0 = max(0, triples[index + 1]), x1 = min(side, triples[index + 2])
            index += 3
            if y >= 0, y < side, x0 < x1 {
                runs.append((y, x0, x1))
            }
        }
        runs.sort { $0.y != $1.y ? $0.y < $1.y : $0.x0 < $1.x0 }
        var merged: [Int32] = []
        merged.reserveCapacity(runs.count * 3)
        for run in runs {
            let count = merged.count
            if count >= 3, merged[count - 3] == run.y, merged[count - 1] >= run.x0 {
                // Overlaps or touches the previous run of the row.
                if run.x1 > merged[count - 1] { merged[count - 1] = run.x1 }
            } else {
                merged.append(run.y)
                merged.append(run.x0)
                merged.append(run.x1)
            }
        }
        spans = merged
    }

    /// Builds a mask from runs in any order.
    init(runs: [Run]) {
        var triples: [Int32] = []
        triples.reserveCapacity(runs.count * 3)
        let limit = Int(Int32.max)
        for run in runs {
            triples.append(Int32(min(max(run.y, -1), limit)))
            triples.append(Int32(min(max(run.x0, 0), limit)))
            triples.append(Int32(min(max(run.x1, 0), limit)))
        }
        self.init(unsortedSpans: triples)
    }

    /// Number of canvas pixels in the mask.
    var pixelCount: Int {
        var count = 0
        var index = 0
        while index < spans.count {
            count += Int(spans[index + 2] - spans[index + 1])
            index += 3
        }
        return count
    }

    /// Number of runs.
    var runCount: Int {
        spans.count / 3
    }

    /// The runs, sorted by row then by column.
    var runs: [Run] {
        var result: [Run] = []
        result.reserveCapacity(spans.count / 3)
        var index = 0
        while index < spans.count {
            result.append(Run(y: Int(spans[index]), x0: Int(spans[index + 1]), x1: Int(spans[index + 2])))
            index += 3
        }
        return result
    }

    /// Calls `body(y, x0, x1)` for every run, in order, without building an array.
    func forEachRun(_ body: (_ y: Int, _ x0: Int, _ x1: Int) -> Void) {
        var index = 0
        while index < spans.count {
            body(Int(spans[index]), Int(spans[index + 1]), Int(spans[index + 2]))
            index += 3
        }
    }

    /// True when canvas pixel `(x, y)` is in the mask.
    func contains(x: Int, y: Int) -> Bool {
        // Binary search of the last run that starts at or before (y, x).
        var low = 0, high = spans.count / 3
        while low < high {
            let middle = (low + high) / 2
            let row = Int(spans[middle * 3]), start = Int(spans[middle * 3 + 1])
            if row < y || (row == y && start <= x) {
                low = middle + 1
            } else {
                high = middle
            }
        }
        guard low > 0 else { return false }
        let run = (low - 1) * 3
        return Int(spans[run]) == y && x >= Int(spans[run + 1]) && x < Int(spans[run + 2])
    }

    /// Bounding box in canvas pixels, inclusive; nil for an empty mask.
    var boundingBox: (minX: Int, minY: Int, maxX: Int, maxY: Int)? {
        guard spans.count >= 3 else { return nil }
        var minX = Int.max, maxX = Int.min
        var index = 0
        while index < spans.count {
            minX = min(minX, Int(spans[index + 1]))
            maxX = max(maxX, Int(spans[index + 2]) - 1)
            index += 3
        }
        return (minX, Int(spans[0]), maxX, Int(spans[spans.count - 3]))
    }

    /// Pixels that belong to both masks.
    func intersection(_ other: CanvasMask) -> CanvasMask {
        var result: [Int32] = []
        var i = 0, j = 0
        let a = spans, b = other.spans
        while i < a.count, j < b.count {
            if a[i] != b[j] {
                if a[i] < b[j] { i += 3 } else { j += 3 }
                continue
            }
            let start = max(a[i + 1], b[j + 1]), end = min(a[i + 2], b[j + 2])
            if start < end {
                result.append(a[i])
                result.append(start)
                result.append(end)
            }
            if a[i + 2] <= b[j + 2] { i += 3 } else { j += 3 }
        }
        var mask = CanvasMask()
        mask.spans = result
        return mask
    }

    /// Pixels of this mask that are not in `other`.
    func subtracting(_ other: CanvasMask) -> CanvasMask {
        guard !spans.isEmpty, !other.spans.isEmpty else { return self }
        var result: [Int32] = []
        let b = other.spans
        var j = 0
        var index = 0
        while index < spans.count {
            let y = spans[index]
            var start = spans[index + 1]
            let end = spans[index + 2]
            index += 3
            // Skip the runs of `other` that end before this run starts.
            while j < b.count, b[j] < y || (b[j] == y && b[j + 2] <= start) {
                j += 3
            }
            var k = j
            while k < b.count, b[k] == y, b[k + 1] < end {
                if b[k + 1] > start {
                    result.append(y)
                    result.append(start)
                    result.append(b[k + 1])
                }
                start = max(start, b[k + 2])
                k += 3
            }
            if start < end {
                result.append(y)
                result.append(start)
                result.append(end)
            }
        }
        var mask = CanvasMask()
        mask.spans = result
        return mask
    }

    /// Offsets of the first run of every canvas row in `runs` order: `side + 1` entries, the last one `runCount`.
    var rowOffsets: [Int] {
        let side = BoardCanvas.side
        var offsets = [Int](repeating: 0, count: side + 1)
        var index = 0
        var row = 0
        let count = spans.count / 3
        while row <= side {
            while index < count, Int(spans[index * 3]) < row {
                index += 1
            }
            offsets[row] = index
            row += 1
        }
        return offsets
    }
}
