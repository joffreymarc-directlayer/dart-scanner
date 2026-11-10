import Foundation
import CoreGraphics
import Testing
import DartCore
@testable import DartVision

/// Pixel types of VISION.md §9.2: fills, subscripts, bilinear samples, CGImage and PNG conversions.
@Suite struct ImagingPixelTests {
    @Test func rgbImage_fillSubscriptAndSize() {
        let image = RGBImage(width: 5, height: 3, fill: SIMD3(10, 20, 30))
        #expect(image.pixels.count == 45 && image.size == PixelSize(width: 5, height: 3))
        #expect((0..<15).allSatisfy { image.pixels[$0 * 3] == 10 && image.pixels[$0 * 3 + 1] == 20 && image.pixels[$0 * 3 + 2] == 30 })
        var copy = image
        copy[4, 2] = SIMD3(1, 2, 3)
        #expect(copy[4, 2] == SIMD3(1, 2, 3) && copy.pixels[42...44] == [1, 2, 3] && copy[3, 2] == SIMD3(10, 20, 30))
        #expect(RGBImage(width: 1, height: 1, fill: SIMD3(7, 7, 7)).pixels == [7, 7, 7])
        #expect(RGBImage(width: 0, height: 4, fill: SIMD3(1, 2, 3)).pixels.isEmpty)
        #expect(RGBImage(width: -2, height: 4, fill: SIMD3(1, 2, 3)).width == 0)
        var gray = GrayImage(width: 3, height: 2, fill: 9)
        #expect(gray.pixels == [9, 9, 9, 9, 9, 9])
        gray[2, 1] = 200
        #expect(gray[2, 1] == 200 && gray.pixels[5] == 200)
        #expect(GrayImage(width: -1, height: 3, fill: 1).pixels.isEmpty)
    }

    @Test func rgbImage_bilinearSample() throws {
        // Two pixels: (0, 0, 0) and (100, 200, 40).
        let image = RGBImage(width: 2, height: 1, pixels: [0, 0, 0, 100, 200, 40])
        #expect(image.sample(x: 0, y: 0) == SIMD3(0, 0, 0))
        #expect(image.sample(x: 1, y: 0) == SIMD3(100, 200, 40))
        let middle = try #require(image.sample(x: 0.25, y: 0))
        #expect(abs(middle.x - 25) < 1e-4 && abs(middle.y - 50) < 1e-4 && abs(middle.z - 10) < 1e-4)
        // The image covers [-0.5, width - 0.5] x [-0.5, height - 0.5]; edge pixels are replicated there.
        #expect(image.sample(x: -0.5, y: -0.5) == SIMD3(0, 0, 0) && image.sample(x: 1.5, y: 0.5) == SIMD3(100, 200, 40))
        #expect(image.sample(x: -0.51, y: 0) == nil && image.sample(x: 1.51, y: 0) == nil && image.sample(x: 0, y: 0.6) == nil)
        #expect(image.sample(x: .nan, y: 0) == nil)
        // Vertical interpolation as well.
        let column = RGBImage(width: 1, height: 2, pixels: [10, 10, 10, 30, 50, 70])
        let between = try #require(column.sample(x: 0, y: 0.5))
        #expect(abs(between.x - 20) < 1e-4 && abs(between.y - 30) < 1e-4 && abs(between.z - 40) < 1e-4)
        #expect(RGBImage(width: 0, height: 0, pixels: []).sample(x: 0, y: 0) == nil)
    }

    @Test func rgbImage_pngAndCGImageRoundTrips() throws {
        var random = SupportRandom(seed: 0x9126)
        var pixels: [UInt8] = []
        for _ in 0..<(37 * 23 * 3) {
            pixels.append(UInt8(random.int(below: 256)))
        }
        let image = RGBImage(width: 37, height: 23, pixels: pixels)
        let cg = try #require(image.makeCGImage())
        #expect(cg.width == 37 && cg.height == 23)
        #expect(RGBImage(cgImage: cg) == image)
        let png = try #require(image.pngData())
        #expect(png.starts(with: [0x89, 0x50, 0x4E, 0x47]))
        #expect(RGBImage(pngData: png) == image)
        #expect(RGBImage(pngData: Data([1, 2, 3])) == nil)
        // A rendered frame survives the trip, which recordings rely on.
        let rendered = SupportScenes.empty().render(camera: SupportPoses.b.camera(longSide: 320))
        let back = try #require(rendered.pngData().flatMap { RGBImage(pngData: $0) })
        #expect(back == rendered)
        // Gray images become 8-bit gray CGImages; empty or malformed images have none.
        let gray = GrayImage(width: 4, height: 2, pixels: [0, 50, 100, 150, 200, 250, 255, 1])
        let grayImage = try #require(gray.makeCGImage())
        #expect(grayImage.bitsPerPixel == 8 && grayImage.width == 4 && grayImage.height == 2)
        #expect(GrayImage(width: 0, height: 0, pixels: []).makeCGImage() == nil)
        #expect(RGBImage(width: 2, height: 2, pixels: [1, 2, 3]).makeCGImage() == nil)
    }

    @Test func frame_wrapsAnImageWithoutCopying() {
        let image = RGBImage(width: 3, height: 2, pixels: Array(0..<18))
        let frame = Frame(image: image, timestamp: 4.25)
        #expect(frame.timestamp == 4.25 && frame.size == PixelSize(width: 3, height: 2) && frame.format == .rgb8)
        #expect(frame.makeRGBImage() == image)
        let bytes = frame.withUnsafeBytes { buffer, bytesPerRow in (Array(buffer), bytesPerRow) }
        #expect(bytes.0 == image.pixels && bytes.1 == 9)
        #expect(frame.bytesPerPixel == 3 && frame.redOffset == 0)
    }
}
