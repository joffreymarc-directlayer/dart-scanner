import Foundation
import simd
import CoreGraphics
import CoreVideo
import ImageIO
import DartCore

/// Size of an image in pixels.
public struct PixelSize: Hashable, Codable, Sendable {
    public var width: Int
    public var height: Int
    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }
}

/// A point in image pixels: origin top-left, +x right, +y down, integer values at pixel centres.
public struct ImagePoint: Hashable, Codable, Sendable {
    public var x: Double
    public var y: Double
    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
    /// Builds a point from normalised coordinates in [0, 1]² (origin top-left): x = u * width - 0.5.
    public init(normalized: SIMD2<Double>, in size: PixelSize) {
        self.init(x: normalized.x * Double(size.width) - 0.5, y: normalized.y * Double(size.height) - 0.5)
    }
    /// Normalised coordinates in [0, 1]²: ((x + 0.5) / width, (y + 0.5) / height).
    public func normalized(in size: PixelSize) -> SIMD2<Double> {
        SIMD2((x + 0.5) / Double(size.width), (y + 0.5) / Double(size.height))
    }
}

/// 8-bit interleaved RGB, row-major, no padding. The only image type the algorithms read.
public struct RGBImage: Equatable, Sendable {
    public let width: Int
    public let height: Int
    /// `count == width * height * 3`, order R, G, B.
    public var pixels: [UInt8]
    public init(width: Int, height: Int, pixels: [UInt8]) {
        self.width = width
        self.height = height
        self.pixels = pixels
    }
    public init(width: Int, height: Int, fill: SIMD3<UInt8>) {
        let w = max(0, width), h = max(0, height)
        var pixels = [UInt8](repeating: fill.x, count: w * h * 3)
        if fill.y != fill.x || fill.z != fill.x {
            pixels.withUnsafeMutableBufferPointer { buffer in
                guard let base = buffer.baseAddress, buffer.count >= 3 else { return }
                // One pixel, then doubling copies.
                base[1] = fill.y
                base[2] = fill.z
                var filled = 3
                let count = buffer.count
                while filled < count {
                    let chunk = filled < count - filled ? filled : count - filled
                    (base + filled).update(from: base, count: chunk)
                    filled += chunk
                }
            }
        }
        self.init(width: w, height: h, pixels: pixels)
    }
    /// Converts any CGImage (sRGB, alpha ignored). Nil when the bitmap context cannot be created.
    public init?(cgImage: CGImage) {
        let w = cgImage.width, h = cgImage.height
        guard w > 0, h > 0, let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        let bytesPerRow = w * 4
        var rgbx = [UInt8](repeating: 0, count: bytesPerRow * h)
        let drawn: Bool = rgbx.withUnsafeMutableBytes { raw in
            guard let context = CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8,
                                          bytesPerRow: bytesPerRow, space: space,
                                          bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return false }
            context.interpolationQuality = .none
            context.setBlendMode(.copy)
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard drawn else { return nil }
        var pixels = [UInt8](repeating: 0, count: w * h * 3)
        pixels.withUnsafeMutableBufferPointer { out in
            rgbx.withUnsafeBufferPointer { source in
                var s = 0, d = 0
                let count = w * h * 3
                while d < count {
                    out[d] = source[s]
                    out[d + 1] = source[s + 1]
                    out[d + 2] = source[s + 2]
                    s += 4
                    d += 3
                }
            }
        }
        self.init(width: w, height: h, pixels: pixels)
    }
    public init?(pngData: Data) {
        guard let source = CGImageSourceCreateWithData(pngData as CFData, nil),
              CGImageSourceGetCount(source) > 0,
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        self.init(cgImage: image)
    }
    public var size: PixelSize {
        PixelSize(width: width, height: height)
    }
    public subscript(x: Int, y: Int) -> SIMD3<UInt8> {
        get {
            precondition(x >= 0 && x < width && y >= 0 && y < height, "pixel out of range")
            let index = (y * width + x) * 3
            return SIMD3(pixels[index], pixels[index + 1], pixels[index + 2])
        }
        set {
            precondition(x >= 0 && x < width && y >= 0 && y < height, "pixel out of range")
            let index = (y * width + x) * 3
            pixels[index] = newValue.x
            pixels[index + 1] = newValue.y
            pixels[index + 2] = newValue.z
        }
    }
    /// Bilinear sample at a sub-pixel position; nil outside the image.
    ///
    /// The image covers `[-0.5, width - 0.5] x [-0.5, height - 0.5]` (VISION.md §3.1); in the half-pixel border
    /// the edge pixel is replicated.
    public func sample(x: Double, y: Double) -> SIMD3<Float>? {
        guard width > 0, height > 0, pixels.count >= width * height * 3,
              x >= -0.5, y >= -0.5, x <= Double(width) - 0.5, y <= Double(height) - 0.5 else { return nil }
        let cx = min(max(x, 0), Double(width - 1))
        let cy = min(max(y, 0), Double(height - 1))
        let x0 = min(Int(cx), max(0, width - 2)), y0 = min(Int(cy), max(0, height - 2))
        let x1 = min(x0 + 1, width - 1), y1 = min(y0 + 1, height - 1)
        let fx = Float(cx - Double(x0)), fy = Float(cy - Double(y0))
        return pixels.withUnsafeBufferPointer { p in
            func pixel(_ px: Int, _ py: Int) -> SIMD3<Float> {
                let index = (py * width + px) * 3
                return SIMD3(Float(p[index]), Float(p[index + 1]), Float(p[index + 2]))
            }
            let top = pixel(x0, y0) + (pixel(x1, y0) - pixel(x0, y0)) * fx
            let bottom = pixel(x0, y1) + (pixel(x1, y1) - pixel(x0, y1)) * fx
            return top + (bottom - top) * fy
        }
    }
    public func makeCGImage() -> CGImage? {
        guard width > 0, height > 0, pixels.count == width * height * 3,
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 24, bytesPerRow: width * 3,
                       space: space, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }
    public func pngData() -> Data? {
        guard let image = makeCGImage() else { return nil }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data as CFMutableData, "public.png" as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }
}

/// 8-bit single-channel image, row-major. Used for masks, evidence maps and gate images.
public struct GrayImage: Equatable, Sendable {
    public let width: Int
    public let height: Int
    public var pixels: [UInt8]
    public init(width: Int, height: Int, pixels: [UInt8]) {
        self.width = width
        self.height = height
        self.pixels = pixels
    }
    public init(width: Int, height: Int, fill: UInt8) {
        let w = max(0, width), h = max(0, height)
        self.init(width: w, height: h, pixels: [UInt8](repeating: fill, count: w * h))
    }
    public subscript(x: Int, y: Int) -> UInt8 {
        get {
            precondition(x >= 0 && x < width && y >= 0 && y < height, "pixel out of range")
            return pixels[y * width + x]
        }
        set {
            precondition(x >= 0 && x < width && y >= 0 && y < height, "pixel out of range")
            pixels[y * width + x] = newValue
        }
    }
    public func makeCGImage() -> CGImage? {
        guard width > 0, height > 0, pixels.count == width * height,
              let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: width,
                       space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }
}
