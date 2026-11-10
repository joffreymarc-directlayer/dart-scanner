import Foundation
import simd
import CoreGraphics
import CoreVideo
import DartCore

/// The canonical top-down image of the board. Constants, not tuning parameters.
public enum BoardCanvas {
    /// 2 px/mm.
    public static let pixelsPerMillimetre: Double = 2
    /// 320 mm from the bull to each edge.
    public static let halfExtent: Double = 320
    /// 1280 px.
    public static let side: Int = 1280
    /// Metric board point of a canvas position: `x = -320 + (px + 0.5) / 2`, `y = 320 - (py + 0.5) / 2`.
    public static func boardPoint(x: Double, y: Double) -> BoardPoint {
        BoardPoint(x: -halfExtent + (x + 0.5) / pixelsPerMillimetre, y: halfExtent - (y + 0.5) / pixelsPerMillimetre)
    }
    public static func pixel(for point: BoardPoint) -> SIMD2<Double> {
        SIMD2((point.x + halfExtent) * pixelsPerMillimetre - 0.5, (halfExtent - point.y) * pixelsPerMillimetre - 0.5)
    }
}

/// A rectified frame: `side x side` RGB plus a validity mask.
public struct CanvasImage: Sendable {
    public var rgb: RGBImage
    /// 255 where the pixel is inside the region of interest and inside the camera frame.
    public var valid: GrayImage
    public init(rgb: RGBImage, valid: GrayImage) {
        self.rgb = rgb
        self.valid = valid
    }
    /// Square crop centred on a metric board point, `span` mm wide, upscaled by `scale` (bilinear).
    ///
    /// The result has `round(span * 2 * scale)` pixels on each side (at least 1, at most 8192). What lies outside the canvas is black.
    public func crop(centre: BoardPoint, span: Double, scale: Double) -> RGBImage {
        let window = span * BoardCanvas.pixelsPerMillimetre
        guard window.isFinite, scale.isFinite, window > 0, scale > 0, centre.x.isFinite, centre.y.isFinite else {
            return RGBImage(width: 1, height: 1, fill: SIMD3(0, 0, 0))
        }
        let side = Int(min(8192, max(1, (window * scale).rounded())))
        let middle = BoardCanvas.pixel(for: centre)
        let step = window / Double(side)
        var pixels = [UInt8](repeating: 0, count: side * side * 3)
        let w = rgb.width, h = rgb.height
        guard w > 0, h > 0, rgb.pixels.count == w * h * 3 else {
            return RGBImage(width: side, height: side, pixels: pixels)
        }
        let maxX = Double(w) - 0.5, maxY = Double(h) - 0.5
        let lastColumn = Double(w - 1), lastRow = Double(h - 1)
        rgb.pixels.withUnsafeBufferPointer { source in
            pixels.withUnsafeMutableBufferPointer { out in
                var j = 0
                while j < side {
                    var y = middle.y - window / 2 + (Double(j) + 0.5) * step
                    var i = 0
                    var index = j * side * 3
                    j += 1
                    // Rows outside the canvas stay black.
                    if !(y >= -0.5 && y <= maxY) { continue }
                    if y < 0 { y = 0 } else if y > lastRow { y = lastRow }
                    let row0 = Int(y), row1 = row0 + 1 < h ? row0 + 1 : row0
                    let fy = y - Double(row0)
                    while i < side {
                        var x = middle.x - window / 2 + (Double(i) + 0.5) * step
                        i += 1
                        if x >= -0.5 && x <= maxX {
                            if x < 0 { x = 0 } else if x > lastColumn { x = lastColumn }
                            let column0 = Int(x), column1 = column0 + 1 < w ? column0 + 1 : column0
                            let fx = x - Double(column0)
                            var channel = 0
                            while channel < 3 {
                                let a = Double(source[(row0 * w + column0) * 3 + channel])
                                let b = Double(source[(row0 * w + column1) * 3 + channel])
                                let c = Double(source[(row1 * w + column0) * 3 + channel])
                                let d = Double(source[(row1 * w + column1) * 3 + channel])
                                let top = a + (b - a) * fx, bottom = c + (d - c) * fx
                                out[index + channel] = UInt8((top + (bottom - top) * fy + 0.5).rounded(.down))
                                channel += 1
                            }
                        }
                        index += 3
                    }
                }
            }
        }
        return RGBImage(width: side, height: side, pixels: pixels)
    }
}
