import Foundation
import CoreGraphics
import SwiftUI
import Testing
@testable import DartUI

/// Shared helper of the `Kernel` tests: a view rendered by `ImageRenderer` (the renderer of SnapshotTool), read
/// back pixel by pixel in sRGB. One pixel per point, origin at the top-left corner, as in the view.
struct KernelBitmap {
    struct RGB: Equatable, CustomStringConvertible {
        var red: Int
        var green: Int
        var blue: Int

        /// 0xRRGGBB, as the tokens of DESIGN.md are written.
        init(hex: UInt32) {
            red = Int((hex >> 16) & 0xFF)
            green = Int((hex >> 8) & 0xFF)
            blue = Int(hex & 0xFF)
        }

        init(red: Int, green: Int, blue: Int) {
            self.red = red
            self.green = green
            self.blue = blue
        }

        var description: String { String(format: "#%02X%02X%02X", red, green, blue) }

        /// `self` seen through `top` laid over it at `opacity` (source-over, in sRGB).
        func covered(by top: RGB, opacity: Double) -> RGB {
            func mix(_ under: Int, _ over: Int) -> Int { Int((Double(under) * (1 - opacity) + Double(over) * opacity).rounded()) }
            return RGB(red: mix(red, top.red), green: mix(green, top.green), blue: mix(blue, top.blue))
        }

        /// Largest difference on one channel.
        func distance(to other: RGB) -> Int {
            max(abs(red - other.red), abs(green - other.green), abs(blue - other.blue))
        }
    }

    let width: Int
    let height: Int
    private let bytes: [UInt8]

    /// Renders `view` in a frame of `size` points over `background`, at one pixel per point.
    @MainActor
    init(_ view: some View, size: CGSize, background: Color = Theme.Palette.background) throws {
        let renderer = ImageRenderer(content: view.frame(width: size.width, height: size.height).background(background))
        renderer.proposedSize = ProposedViewSize(size)
        renderer.scale = 1
        try self.init(#require(renderer.cgImage, "ImageRenderer gave no image"))
    }

    init(_ image: CGImage) throws {
        width = image.width
        height = image.height
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                             bytesPerRow: width * 4, space: space,
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let data = try #require(context.data)
        bytes = Array(UnsafeBufferPointer(start: data.assumingMemoryBound(to: UInt8.self), count: width * height * 4))
    }

    /// Colour of the pixel that contains the point (x, y) of the view.
    func color(at point: CGPoint) -> RGB {
        let x = min(width - 1, max(0, Int(point.x.rounded(.down))))
        let y = min(height - 1, max(0, Int(point.y.rounded(.down))))
        let offset = (y * width + x) * 4
        return RGB(red: Int(bytes[offset]), green: Int(bytes[offset + 1]), blue: Int(bytes[offset + 2]))
    }

    /// True when the pixel under `point` is `expected`, each channel within `tolerance`.
    func has(_ expected: RGB, at point: CGPoint, tolerance: Int = 3) -> Bool {
        color(at: point).distance(to: expected) <= tolerance
    }

    /// Number of pixels that differ from `color` by more than `tolerance` on a channel.
    func count(differingFrom color: RGB, tolerance: Int = 3) -> Int {
        var count = 0
        for index in stride(from: 0, to: bytes.count, by: 4) {
            let pixel = RGB(red: Int(bytes[index]), green: Int(bytes[index + 1]), blue: Int(bytes[index + 2]))
            if pixel.distance(to: color) > tolerance { count += 1 }
        }
        return count
    }

    /// True when a pixel within `radius` pixels of `point` is `expected`.
    func hasNear(_ expected: RGB, at point: CGPoint, radius: Int, tolerance: Int = 3) -> Bool {
        for dy in -radius...radius {
            for dx in -radius...radius where has(expected, at: CGPoint(x: point.x + CGFloat(dx), y: point.y + CGFloat(dy)), tolerance: tolerance) {
                return true
            }
        }
        return false
    }
}

/// The colour tokens of DESIGN.md §2, written here a second time on purpose: the tests compare the drawing with
/// the document, not with `Theme` itself.
enum KernelPalette {
    static let background = KernelBitmap.RGB(hex: 0x0E1114)
    static let surface = KernelBitmap.RGB(hex: 0x171C21)
    static let surfaceRaised = KernelBitmap.RGB(hex: 0x212830)
    static let line = KernelBitmap.RGB(hex: 0x2E3640)
    static let lineStrong = KernelBitmap.RGB(hex: 0x5A6470)
    static let textPrimary = KernelBitmap.RGB(hex: 0xF3F1EA)
    static let textSecondary = KernelBitmap.RGB(hex: 0xA9B1BA)
    static let textTertiary = KernelBitmap.RGB(hex: 0x8A939D)
    static let accent = KernelBitmap.RGB(hex: 0xFFA630)
    static let onAccent = KernelBitmap.RGB(hex: 0x1A1206)
    static let info = KernelBitmap.RGB(hex: 0x5CB2FF)
    static let boardRed = KernelBitmap.RGB(hex: 0xD8413A)
    static let boardGreen = KernelBitmap.RGB(hex: 0x2F9E5B)
    static let boardCream = KernelBitmap.RGB(hex: 0xE9DFC7)
    static let boardBlack = KernelBitmap.RGB(hex: 0x1B1F23)
    static let boardSurround = KernelBitmap.RGB(hex: 0x0A0C0E)
    static let players: [KernelBitmap.RGB] =
        [0xFFA630, 0x5CB2FF, 0xB79CFF, 0xFF8FB8, 0x6FE0C8, 0xF2E26B, 0xFF8A5C, 0xC8D0D8].map { KernelBitmap.RGB(hex: $0) }
}
