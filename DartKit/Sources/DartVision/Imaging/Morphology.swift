import Foundation

/// Binary morphology with a square structuring element of side `2 * radius + 1` (VISION.md §5.2, D3).
/// Internal to DartVision.
///
/// A mask is a `GrayImage` whose non-zero pixels are set; every result holds only 0 and 255. Outside the image
/// nothing is set for a dilation and everything is set for an erosion, so that an opening never adds a pixel and
/// a closing never removes one, even along the border.
enum Morphology {
    /// Sets every pixel that has a set pixel within `radius` (Chebyshev distance).
    static func dilate(_ mask: GrayImage, radius: Int) -> GrayImage {
        transform(mask, radius: radius, erode: false)
    }

    /// Keeps the pixels whose whole `(2r + 1)²` neighbourhood inside the image is set.
    static func erode(_ mask: GrayImage, radius: Int) -> GrayImage {
        transform(mask, radius: radius, erode: true)
    }

    /// Erosion then dilation: removes what is thinner than the structuring element (`radius` 1: lines of 1 or 2 px).
    static func open(_ mask: GrayImage, radius: Int) -> GrayImage {
        dilate(erode(mask, radius: radius), radius: radius)
    }

    /// Dilation then erosion: fills holes and gaps up to `2 * radius` px wide (`radius` 3: 6 px).
    static func close(_ mask: GrayImage, radius: Int) -> GrayImage {
        erode(dilate(mask, radius: radius), radius: radius)
    }

    /// The mask with only 0 and 255: non-zero pixels become 255.
    static func binarised(_ mask: GrayImage) -> GrayImage {
        var pixels = mask.pixels
        pixels.withUnsafeMutableBufferPointer { buffer in
            let count = buffer.count
            var index = 0
            while index < count {
                if buffer[index] != 0 { buffer[index] = 255 }
                index += 1
            }
        }
        return GrayImage(width: mask.width, height: mask.height, pixels: pixels)
    }

    // The square element is separable: one pass along the rows, one along the columns, each with a sliding count
    // of the pixels that decide the outcome (set pixels for a dilation, unset pixels for an erosion).
    private static func transform(_ mask: GrayImage, radius: Int, erode: Bool) -> GrayImage {
        let w = mask.width, h = mask.height
        guard w > 0, h > 0, mask.pixels.count == w * h else { return mask }
        guard radius > 0 else { return binarised(mask) }

        var horizontal = [UInt8](repeating: 0, count: w * h)
        var output = [UInt8](repeating: 0, count: w * h)
        var counts = [Int32](repeating: 0, count: w)
        mask.pixels.withUnsafeBufferPointer { source in
            horizontal.withUnsafeMutableBufferPointer { rowPass in
                // Row pass: 1 where the window [x - radius, x + radius], clipped to the row, holds a decisive pixel.
                var y = 0
                while y < h {
                    let base = y * w
                    var count = 0
                    var x = 0
                    let lead = radius < w ? radius : w
                    while x < lead {
                        if (source[base + x] != 0) != erode { count += 1 }
                        x += 1
                    }
                    x = 0
                    while x < w {
                        let entering = x + radius
                        if entering < w, (source[base + entering] != 0) != erode { count += 1 }
                        rowPass[base + x] = count > 0 ? 1 : 0
                        let leaving = x - radius
                        if leaving >= 0, (source[base + leaving] != 0) != erode { count -= 1 }
                        x += 1
                    }
                    y += 1
                }
            }
        }
        horizontal.withUnsafeBufferPointer { rowPass in
            output.withUnsafeMutableBufferPointer { out in
                counts.withUnsafeMutableBufferPointer { count in
                    // Column pass on the result of the row pass, all columns at once.
                    var y = 0
                    let lead = radius < h ? radius : h
                    while y < lead {
                        let base = y * w
                        var x = 0
                        while x < w {
                            count[x] += Int32(rowPass[base + x])
                            x += 1
                        }
                        y += 1
                    }
                    // A decisive pixel in the window sets the result of a dilation and clears that of an erosion.
                    let hit: UInt8 = erode ? 0 : 255
                    let miss: UInt8 = erode ? 255 : 0
                    y = 0
                    while y < h {
                        let entering = y + radius
                        if entering < h {
                            let base = entering * w
                            var x = 0
                            while x < w {
                                count[x] += Int32(rowPass[base + x])
                                x += 1
                            }
                        }
                        let base = y * w
                        var x = 0
                        while x < w {
                            out[base + x] = count[x] > 0 ? hit : miss
                            x += 1
                        }
                        let leaving = y - radius
                        if leaving >= 0 {
                            let leavingBase = leaving * w
                            x = 0
                            while x < w {
                                count[x] -= Int32(rowPass[leavingBase + x])
                                x += 1
                            }
                        }
                        y += 1
                    }
                }
            }
        }
        return GrayImage(width: w, height: h, pixels: output)
    }
}
