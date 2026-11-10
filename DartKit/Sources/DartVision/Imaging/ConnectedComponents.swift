import Foundation

/// Connected components of a binary mask: two passes with a union-find, 8-connectivity (VISION.md §5.2, D4).
/// Internal to DartVision.
///
/// Labels are 1...count in raster order of the first pixel of each component (top row first, then left to right),
/// so the numbering does not depend on how the provisional labels were merged. 0 is the background.
struct ConnectedComponents: Sendable {
    /// One component of the mask.
    struct Component: Hashable, Sendable {
        /// 1-based label, equal to its index in `components` plus one.
        var label: Int32
        /// Number of pixels.
        var pixelCount: Int
        /// Bounding box, inclusive.
        var minX: Int
        var minY: Int
        var maxX: Int
        var maxY: Int
        /// Sums of the pixel coordinates (centroid = sum / pixelCount).
        var sumX: Double
        var sumY: Double

        /// Centroid in pixel coordinates.
        var centroid: SIMD2<Double> {
            SIMD2(sumX / Double(max(1, pixelCount)), sumY / Double(max(1, pixelCount)))
        }
        var width: Int { maxX - minX + 1 }
        var height: Int { maxY - minY + 1 }
    }

    let width: Int
    let height: Int
    /// `width * height` labels, row-major: 0 for the background, otherwise the label of the component.
    let labels: [Int32]
    /// Components in label order.
    let components: [Component]

    /// Labels the non-zero pixels of `mask`.
    init(_ mask: GrayImage) {
        let w = max(0, mask.width), h = max(0, mask.height)
        width = w
        height = h
        guard w > 0, h > 0, mask.pixels.count == w * h else {
            labels = [Int32](repeating: 0, count: w * h)
            components = []
            return
        }

        var labelling = [Int32](repeating: 0, count: w * h)
        // A pixel opens a provisional label only when none of its W, NW, N, NE neighbours is set: two such pixels
        // are never 8-neighbours, so there are at most ceil(w / 2) * ceil(h / 2) of them. Entry 0 is the background.
        var parentStorage = [Int32](repeating: 0, count: ((w + 1) / 2) * ((h + 1) / 2) + 2)
        var found: [Component] = []

        mask.pixels.withUnsafeBufferPointer { source in
            labelling.withUnsafeMutableBufferPointer { out in
                parentStorage.withUnsafeMutableBufferPointer { parent in
                    func find(_ label: Int32) -> Int32 {
                        var root = label
                        while parent[Int(root)] != root {
                            root = parent[Int(root)]
                        }
                        // Path compression.
                        var current = label
                        while parent[Int(current)] != root {
                            let next = parent[Int(current)]
                            parent[Int(current)] = root
                            current = next
                        }
                        return root
                    }
                    // Merges the set of `label` into the running root of the current pixel.
                    func merge(_ label: Int32, into root: inout Int32) {
                        guard label != 0 else { return }
                        let other = find(label)
                        if root == 0 {
                            root = other
                        } else if other < root {
                            parent[Int(root)] = other
                            root = other
                        } else if other > root {
                            parent[Int(other)] = root
                        }
                    }

                    // First pass: provisional labels from the four neighbours already visited (W, NW, N, NE).
                    var nextLabel: Int32 = 1
                    var y = 0
                    while y < h {
                        let row = y * w
                        var x = 0
                        while x < w {
                            if source[row + x] != 0 {
                                var root: Int32 = 0
                                if x > 0 { merge(out[row + x - 1], into: &root) }
                                if y > 0 {
                                    let above = row - w
                                    if x > 0 { merge(out[above + x - 1], into: &root) }
                                    merge(out[above + x], into: &root)
                                    if x + 1 < w { merge(out[above + x + 1], into: &root) }
                                }
                                if root == 0 {
                                    root = nextLabel
                                    parent[Int(root)] = root
                                    nextLabel += 1
                                }
                                out[row + x] = root
                            }
                            x += 1
                        }
                        y += 1
                    }

                    // Second pass: final labels in raster order of first appearance, and the statistics.
                    var finalLabel = [Int32](repeating: 0, count: Int(nextLabel))
                    y = 0
                    while y < h {
                        let row = y * w
                        var x = 0
                        while x < w {
                            if out[row + x] != 0 {
                                let root = find(out[row + x])
                                var label = finalLabel[Int(root)]
                                if label == 0 {
                                    label = Int32(found.count + 1)
                                    finalLabel[Int(root)] = label
                                    found.append(Component(label: label, pixelCount: 0, minX: x, minY: y, maxX: x, maxY: y,
                                                           sumX: 0, sumY: 0))
                                }
                                out[row + x] = label
                                let index = Int(label) - 1
                                found[index].pixelCount += 1
                                if x < found[index].minX { found[index].minX = x }
                                if x > found[index].maxX { found[index].maxX = x }
                                if y > found[index].maxY { found[index].maxY = y }
                                found[index].sumX += Double(x)
                                found[index].sumY += Double(y)
                            }
                            x += 1
                        }
                        y += 1
                    }
                }
            }
        }
        labels = labelling
        components = found
    }

    /// Label at a pixel; 0 outside the image.
    func label(x: Int, y: Int) -> Int32 {
        guard x >= 0, x < width, y >= 0, y < height else { return 0 }
        return labels[y * width + x]
    }

    /// Mask (0 / 255) of the components for which `keep` is true.
    func mask(keeping keep: (Component) -> Bool) -> GrayImage {
        var kept = [Bool](repeating: false, count: components.count + 1)
        for component in components where keep(component) {
            kept[Int(component.label)] = true
        }
        var pixels = [UInt8](repeating: 0, count: width * height)
        labels.withUnsafeBufferPointer { source in
            pixels.withUnsafeMutableBufferPointer { out in
                let count = source.count
                var index = 0
                while index < count {
                    if kept[Int(source[index])] { out[index] = 255 }
                    index += 1
                }
            }
        }
        return GrayImage(width: width, height: height, pixels: pixels)
    }

    /// Mask (0 / 255) of one component.
    func mask(of label: Int32) -> GrayImage {
        mask { $0.label == label }
    }
}
