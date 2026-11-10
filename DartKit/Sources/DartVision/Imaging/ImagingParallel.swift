import Foundation
import os

/// Splits a range of rows into bands processed concurrently (lot V1, internal).
///
/// Used by the loops that touch every pixel of a frame: the rectifier, the synthetic renderer, its blur and its
/// noise. A band reads shared immutable values (arrays, images) and RETURNS what it computed for its own rows;
/// the caller then copies the parts into place. Nothing is shared for writing, so the compiler checks the whole
/// scheme, and the result is the same, bit for bit, whatever the number of cores and the order of the bands.
enum ImagingParallel {
    /// The bands of `rows`: at least `minimumBand` rows tall and, apart from the last one, a multiple of
    /// `alignment` rows counted from `rows.lowerBound`. About two bands per core; one band for a short range.
    static func bands(of rows: Range<Int>, minimumBand: Int, alignment: Int = 1) -> [Range<Int>] {
        let count = rows.count
        guard count > 0 else { return [] }
        let cores = max(1, ProcessInfo.processInfo.activeProcessorCount)
        let step = max(1, alignment)
        let wanted = max(max(1, minimumBand), (count + cores * 2 - 1) / (cores * 2))
        let bandSize = (wanted + step - 1) / step * step
        var result: [Range<Int>] = []
        var start = rows.lowerBound
        while start < rows.upperBound {
            let end = min(rows.upperBound, start + bandSize)
            result.append(start..<end)
            start = end
        }
        return result
    }

    /// Calls `body` once per band, on several threads, and returns the results in band order.
    static func map<T: Sendable>(_ bands: [Range<Int>], _ body: @Sendable (Range<Int>) -> T) -> [T] {
        if bands.count <= 1 {
            return bands.map { body($0) }
        }
        let results = OSAllocatedUnfairLock(initialState: [T?](repeating: nil, count: bands.count))
        DispatchQueue.concurrentPerform(iterations: bands.count) { index in
            let value = body(bands[index])
            results.withLock { $0[index] = value }
        }
        // `concurrentPerform` returns once every iteration has run: every slot is filled.
        return results.withLock { $0 }.compactMap { $0 }
    }

    /// Copies the rows of `part`, computed for `band`, into `pixels`: row `y` of the band goes to row `y` of an
    /// image of `rowBytes` bytes per row, starting at byte `firstByte` of that row. `part` holds `band.count` rows of
    /// `partRowBytes` bytes each.
    static func place(_ part: [UInt8], band: Range<Int>, partRowBytes: Int, into pixels: inout [UInt8], rowBytes: Int,
                      firstByte: Int) {
        guard partRowBytes > 0, part.count >= band.count * partRowBytes,
              firstByte >= 0, firstByte + partRowBytes <= rowBytes, band.lowerBound >= 0,
              band.upperBound * rowBytes <= pixels.count else { return }
        part.withUnsafeBufferPointer { source in
            pixels.withUnsafeMutableBufferPointer { destination in
                guard let from = source.baseAddress, let to = destination.baseAddress else { return }
                var row = 0
                while row < band.count {
                    (to + (band.lowerBound + row) * rowBytes + firstByte).update(from: from + row * partRowBytes, count: partRowBytes)
                    row += 1
                }
            }
        }
    }
}
