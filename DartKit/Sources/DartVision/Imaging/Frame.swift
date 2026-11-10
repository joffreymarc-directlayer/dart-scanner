import Foundation
import simd
import CoreGraphics
import CoreVideo
import DartCore

/// Memory layout of a `Frame`.
public enum FramePixelFormat: Sendable {
    /// 4 bytes per pixel, order B, G, R, A (kCVPixelFormatType_32BGRA).
    case bgra8
    /// 3 bytes per pixel, order R, G, B (an `RGBImage`).
    case rgb8
}

/// One video frame. Wraps a CVPixelBuffer (capture) or an RGBImage (tests, replay) without copying.
/// A frame handed to a consumer is only guaranteed valid during that call.
public struct Frame: @unchecked Sendable {
    public let timestamp: TimeInterval
    public let size: PixelSize
    public let format: FramePixelFormat

    private enum Storage {
        case image(RGBImage)
        case pixelBuffer(CVPixelBuffer)
    }
    private let storage: Storage

    public init(image: RGBImage, timestamp: TimeInterval) {
        self.timestamp = timestamp
        self.size = PixelSize(width: image.width, height: image.height)
        self.format = .rgb8
        self.storage = .image(image)
    }

    /// Nil unless the buffer is kCVPixelFormatType_32BGRA.
    public init?(pixelBuffer: CVPixelBuffer, timestamp: TimeInterval) {
        guard CVPixelBufferGetPixelFormatType(pixelBuffer) == kCVPixelFormatType_32BGRA,
              !CVPixelBufferIsPlanar(pixelBuffer) else { return nil }
        self.timestamp = timestamp
        self.size = PixelSize(width: CVPixelBufferGetWidth(pixelBuffer), height: CVPixelBufferGetHeight(pixelBuffer))
        self.format = .bgra8
        self.storage = .pixelBuffer(pixelBuffer)
    }

    /// Gives read access to the pixel bytes (the buffer is locked read-only for the duration of `body`).
    ///
    /// The buffer holds `bytesPerRow * size.height` bytes. When the pixel buffer cannot be locked, `body`
    /// receives an empty buffer: a reader checks `count` before it indexes.
    public func withUnsafeBytes<R>(_ body: (UnsafeRawBufferPointer, _ bytesPerRow: Int) throws -> R) rethrows -> R {
        switch storage {
        case .image(let image):
            return try image.pixels.withUnsafeBytes { bytes in
                try body(bytes, image.width * 3)
            }
        case .pixelBuffer(let buffer):
            let locked = CVPixelBufferLockBaseAddress(buffer, .readOnly) == kCVReturnSuccess
            defer {
                if locked { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
            }
            let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
            guard locked, let base = CVPixelBufferGetBaseAddress(buffer) else {
                return try body(UnsafeRawBufferPointer(start: nil, count: 0), bytesPerRow)
            }
            return try body(UnsafeRawBufferPointer(start: base, count: bytesPerRow * size.height), bytesPerRow)
        }
    }

    /// Full copy as RGB. Used for calibration stills and recordings, never per frame.
    public func makeRGBImage() -> RGBImage {
        switch storage {
        case .image(let image):
            return image
        case .pixelBuffer:
            let width = max(0, size.width), height = max(0, size.height)
            var pixels = [UInt8](repeating: 0, count: width * height * 3)
            withUnsafeBytes { bytes, bytesPerRow in
                guard let base = bytes.baseAddress, bytesPerRow >= width * 4, bytes.count >= bytesPerRow * height else { return }
                pixels.withUnsafeMutableBufferPointer { out in
                    guard let destination = out.baseAddress else { return }
                    var y = 0
                    while y < height {
                        let row = base.advanced(by: y * bytesPerRow).assumingMemoryBound(to: UInt8.self)
                        var d = destination + y * width * 3
                        var s = 0
                        let stop = width * 4
                        while s < stop {
                            d[0] = row[s + 2]
                            d[1] = row[s + 1]
                            d[2] = row[s]
                            d += 3
                            s += 4
                        }
                        y += 1
                    }
                }
            }
            return RGBImage(width: width, height: height, pixels: pixels)
        }
    }
}

extension Frame {
    /// Bytes per pixel of the layout: 4 for `.bgra8`, 3 for `.rgb8`.
    var bytesPerPixel: Int {
        switch format {
        case .bgra8: return 4
        case .rgb8: return 3
        }
    }

    /// Offset of the red byte inside a pixel (the green byte is always at 1, the blue byte at `2 - redOffset`).
    var redOffset: Int {
        switch format {
        case .bgra8: return 2
        case .rgb8: return 0
        }
    }
}
