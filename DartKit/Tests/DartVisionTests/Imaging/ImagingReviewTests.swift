import Foundation
import simd
import Testing
import DartCore
@testable import DartVision

/// Adversarial review of lot V1 (`Imaging/`): every mask operation against a brute-force oracle written from the
/// definitions alone, on seeded random masks, and the image types on inputs that must never trap.
@Suite struct ImagingReviewTests {
    // MARK: Oracles

    /// A random binary mask: blobs, lines and isolated pixels, so that every neighbourhood case shows up.
    private static func randomMask(width: Int, height: Int, density: Double, random: inout SeededRandom) -> GrayImage {
        var pixels = [UInt8](repeating: 0, count: width * height)
        for index in pixels.indices where Double(random.next() >> 11) / 9007199254740992.0 < density {
            pixels[index] = UInt8(1 + random.nextInt(below: 255))
        }
        return GrayImage(width: width, height: height, pixels: pixels)
    }

    /// Square structuring element of side `2r + 1`: a dilation sets a pixel when any pixel of its window inside
    /// the image is set; an erosion keeps it when every pixel of its window inside the image is set.
    private static func bruteMorphology(_ mask: GrayImage, radius: Int, erode: Bool) -> GrayImage {
        var out = [UInt8](repeating: 0, count: mask.pixels.count)
        for y in 0..<mask.height {
            for x in 0..<mask.width {
                var anySet = false, allSet = true
                for dy in -radius...radius {
                    for dx in -radius...radius {
                        let nx = x + dx, ny = y + dy
                        guard nx >= 0, ny >= 0, nx < mask.width, ny < mask.height else { continue }
                        if mask.pixels[ny * mask.width + nx] != 0 { anySet = true } else { allSet = false }
                    }
                }
                out[y * mask.width + x] = (erode ? allSet : anySet) ? 255 : 0
            }
        }
        return GrayImage(width: mask.width, height: mask.height, pixels: out)
    }

    /// 8-connected flood fill; labels in raster order of each component's first pixel.
    private static func bruteComponents(_ mask: GrayImage) -> (labels: [Int32], counts: [Int]) {
        let w = mask.width, h = mask.height
        var labels = [Int32](repeating: 0, count: w * h)
        var counts: [Int] = []
        for start in 0..<(w * h) where mask.pixels[start] != 0 && labels[start] == 0 {
            let label = Int32(counts.count + 1)
            var stack = [start]
            labels[start] = label
            var count = 0
            while let index = stack.popLast() {
                count += 1
                let x = index % w, y = index / w
                for dy in -1...1 {
                    for dx in -1...1 {
                        let nx = x + dx, ny = y + dy
                        guard nx >= 0, ny >= 0, nx < w, ny < h else { continue }
                        let neighbour = ny * w + nx
                        if mask.pixels[neighbour] != 0 && labels[neighbour] == 0 {
                            labels[neighbour] = label
                            stack.append(neighbour)
                        }
                    }
                }
            }
            counts.append(count)
        }
        return (labels, counts)
    }

    @Test func morphology_matchesTheSquareElementDefinition() {
        var random = SeededRandom(seed: 0x5EED_0001)
        for trial in 0..<60 {
            let width = 1 + random.nextInt(below: 23), height = 1 + random.nextInt(below: 23)
            let density = [0.05, 0.3, 0.6, 0.9][trial % 4]
            let mask = Self.randomMask(width: width, height: height, density: density, random: &random)
            for radius in 0...4 {
                let dilated = Morphology.dilate(mask, radius: radius)
                let eroded = Morphology.erode(mask, radius: radius)
                #expect(dilated == Self.bruteMorphology(mask, radius: radius, erode: false), "dilate \(width)x\(height) r\(radius)")
                #expect(eroded == Self.bruteMorphology(mask, radius: radius, erode: true), "erode \(width)x\(height) r\(radius)")
                let opened = Self.bruteMorphology(Self.bruteMorphology(mask, radius: radius, erode: true), radius: radius, erode: false)
                let closed = Self.bruteMorphology(Self.bruteMorphology(mask, radius: radius, erode: false), radius: radius, erode: true)
                #expect(Morphology.open(mask, radius: radius) == opened)
                #expect(Morphology.close(mask, radius: radius) == closed)
            }
        }
    }

    @Test func connectedComponents_matchAFloodFill() {
        var random = SeededRandom(seed: 0x5EED_0002)
        for trial in 0..<120 {
            let width = 1 + random.nextInt(below: 40), height = 1 + random.nextInt(below: 40)
            let mask = Self.randomMask(width: width, height: height, density: [0.2, 0.45, 0.6][trial % 3], random: &random)
            let components = ConnectedComponents(mask)
            let expected = Self.bruteComponents(mask)
            #expect(components.labels == expected.labels, "\(width)x\(height) trial \(trial)")
            #expect(components.components.map(\.pixelCount) == expected.counts)
            for component in components.components {
                // Bounding box and sums from the labels themselves.
                var minX = Int.max, minY = Int.max, maxX = Int.min, maxY = Int.min, sumX = 0.0
                for index in expected.labels.indices where expected.labels[index] == component.label {
                    minX = min(minX, index % width); maxX = max(maxX, index % width)
                    minY = min(minY, index / width); maxY = max(maxY, index / width)
                    sumX += Double(index % width)
                }
                #expect(component.minX == minX && component.maxX == maxX && component.minY == minY && component.maxY == maxY)
                #expect(component.sumX == sumX)
            }
        }
    }

    /// The pixel set of a canvas mask, by asking `contains(x:y:)` of every pixel of `region`.
    private static func pixelSet(_ mask: CanvasMask) -> Set<Int> {
        var set = Set<Int>()
        let image = mask.makeImage()
        for index in image.pixels.indices where image.pixels[index] != 0 { set.insert(index) }
        return set
    }

    /// A random canvas mask made of a few rectangles and discs, some reaching beyond the canvas.
    private static func randomCanvasMask(_ random: inout SeededRandom) -> CanvasMask {
        var runs: [CanvasMask.Run] = []
        for _ in 0..<(1 + random.nextInt(below: 5)) {
            let cx = random.nextInt(below: 1400) - 60, cy = random.nextInt(below: 1400) - 60
            let r = 1 + random.nextInt(below: 30)
            for dy in -r...r {
                let half = Int((Double(r * r - dy * dy)).squareRoot())
                runs.append(CanvasMask.Run(y: cy + dy, x0: cx - half, x1: cx + half + 1))
            }
        }
        return CanvasMask(runs: runs)
    }

    @Test func canvasMask_operationsMatchPixelSets() throws {
        var random = SeededRandom(seed: 0x5EED_0003)
        let side = BoardCanvas.side
        for _ in 0..<25 {
            let a = Self.randomCanvasMask(&random), b = Self.randomCanvasMask(&random)
            let sa = Self.pixelSet(a), sb = Self.pixelSet(b)
            #expect(a.pixelCount == sa.count)
            #expect(abs(a.area - Double(sa.count) / 4) < 1e-9)
            #expect(Self.pixelSet(a.union(b)) == sa.union(sb))
            #expect(Self.pixelSet(a.intersection(b)) == sa.intersection(sb))
            #expect(Self.pixelSet(a.subtracting(b)) == sa.subtracting(sb))
            #expect(a.intersects(b) == !sa.isDisjoint(with: sb))
            // Results stay in the canonical form: equal pixels, equal values.
            for result in [a.union(b), a.intersection(b), a.subtracting(b), a.dilated(by: 1)] {
                #expect(result == CanvasMask(result.makeImage()))
            }
            // Canonical form: the same pixels, the same value; the image round trip is exact.
            #expect(CanvasMask(a.makeImage()) == a)
            #expect(a.union(b) == b.union(a))
            let decoded = try JSONDecoder().decode(CanvasMask.self, from: JSONEncoder().encode(a))
            #expect(decoded == a)
            // Membership by board point: the pixel whose square holds the point.
            for _ in 0..<50 {
                let x = random.nextInt(below: side), y = random.nextInt(below: side)
                let p = BoardCanvas.boardPoint(x: Double(x) + 0.3, y: Double(y) - 0.4)
                #expect(a.contains(p) == sa.contains(y * side + x))
            }
            // Dilation by a disc: every pixel whose centre is within `mm` of the centre of a pixel of the mask.
            let mm = Double(random.nextInt(below: 7)) / 2 + 0.25
            let grown = Self.pixelSet(a.dilated(by: mm))
            let reach = mm * BoardCanvas.pixelsPerMillimetre
            let r = Int(reach)
            var expected = Set<Int>()
            for index in sa {
                let x = index % side, y = index / side
                for dy in -r...r {
                    for dx in -r...r where Double(dx * dx + dy * dy) <= reach * reach {
                        let nx = x + dx, ny = y + dy
                        if nx >= 0, ny >= 0, nx < side, ny < side { expected.insert(ny * side + nx) }
                    }
                }
            }
            #expect(grown == expected, "dilation by \(mm) mm")
        }
        // Runs that touch without sharing a pixel, and runs that share exactly one.
        let left = CanvasMask(runs: [CanvasMask.Run(y: 10, x0: 0, x1: 5)])
        let touching = CanvasMask(runs: [CanvasMask.Run(y: 10, x0: 5, x1: 9)])
        let sharing = CanvasMask(runs: [CanvasMask.Run(y: 10, x0: 4, x1: 9)])
        #expect(!left.intersects(touching) && !touching.intersects(left))
        #expect(left.intersects(sharing) && sharing.intersects(left))
        #expect(left.intersection(touching).isEmpty && left.subtracting(touching) == left)
        #expect(left.union(touching) == CanvasMask(runs: [CanvasMask.Run(y: 10, x0: 0, x1: 9)]))
        #expect(sharing.subtracting(left) == touching)
    }

    // MARK: Noise

    @Test func noiseEstimate_andRenderedNoise_haveTheDocumentedSigma() {
        // FrameAccumulator.noiseSigma: median|a − b| / 0.954 is the per-frame sigma of Gaussian noise.
        var random = SeededRandom(seed: 0x5EED_0004)
        func gaussian() -> Double {
            let u = max(Double(random.next() >> 11) / 9007199254740992.0, 1e-300)
            let v = Double(random.next() >> 11) / 9007199254740992.0
            return (-2 * log(u)).squareRoot() * cos(2 * .pi * v)
        }
        let side = 200
        let valid = GrayImage(width: side, height: side, fill: 255)
        for sigma in [1.0, 2, 3, 5] {
            var accumulator = FrameAccumulator()
            for _ in 0..<2 {
                let pixels = (0..<(side * side * 3)).map { _ in UInt8(max(0, min(255, (128 + sigma * gaussian()).rounded()))) }
                accumulator.add(CanvasImage(rgb: RGBImage(width: side, height: side, pixels: pixels), valid: valid))
            }
            // Rounding to whole levels adds 1/12 of a level squared.
            let expected = (sigma * sigma + 1.0 / 12).squareRoot()
            let estimate = accumulator.noiseSigma() ?? 0
            #expect(abs(estimate - expected) / expected < 0.05, "sigma \(sigma): \(estimate)")
        }
        // The renderer's noise (VISION.md §10.1, sigma 2 by default) over the plain wall, without blur.
        let camera = SyntheticCamera(imageSize: PixelSize(width: 640, height: 360), position: SIMD3(0, -400, 1000))
        var noisy = SupportScenes.exact()
        noisy.noiseSigma = 2
        let clean = SupportScenes.exact().render(camera: camera), image = noisy.render(camera: camera)
        var sum = 0.0, sumOfSquares = 0.0, count = 0.0
        for index in clean.pixels.indices where clean.pixels[index] == 120 || clean.pixels[index] == 125 {
            let difference = Double(image.pixels[index]) - Double(clean.pixels[index])
            sum += difference
            sumOfSquares += difference * difference
            count += 1
        }
        #expect(count > 20_000)
        let mean = sum / count, deviation = (sumOfSquares / count - mean * mean).squareRoot()
        #expect(abs(mean) < 0.05 && abs(deviation - (4 + 1.0 / 12).squareRoot()) < 0.1, "mean \(mean), sigma \(deviation)")
    }

    // MARK: Inputs that must never trap

    @Test func imagesAndMasks_unusualInputsNeverTrap() {
        // Empty, negative and inconsistent sizes.
        let empty = RGBImage(width: -3, height: 7, fill: SIMD3(1, 2, 3))
        #expect(empty.width == 0 && empty.pixels.isEmpty)
        #expect(empty.sample(x: 0, y: 0) == nil && empty.makeCGImage() == nil && empty.pngData() == nil)
        let short = RGBImage(width: 4, height: 4, pixels: [1, 2, 3])
        #expect(short.sample(x: 1, y: 1) == nil && short.makeCGImage() == nil)
        let image = RGBImage(width: 3, height: 2, fill: SIMD3(10, 20, 30))
        for value in [Double.nan, .infinity, -.infinity, 1e300, -1e300, -0.5000001, 2.5000001] {
            #expect(image.sample(x: value, y: 0) == nil)
            #expect(image.sample(x: 0, y: value) == nil)
        }
        #expect(image.sample(x: -0.5, y: 1.5) == SIMD3<Float>(10, 20, 30))
        #expect(RGBImage(pngData: Data([1, 2, 3])) == nil)
        #expect(GrayImage(width: 0, height: 5, fill: 9).makeCGImage() == nil)
        #expect(GrayImage(width: 2, height: 2, pixels: [1]).makeCGImage() == nil)

        // Morphology and components on degenerate masks.
        let bad = GrayImage(width: 5, height: 5, pixels: [255, 0])
        #expect(Morphology.dilate(bad, radius: 3) == bad)
        #expect(ConnectedComponents(bad).components.isEmpty)
        let small = GrayImage(width: 2, height: 1, pixels: [255, 0])
        #expect(Morphology.dilate(small, radius: 1_000).pixels == [255, 255])
        #expect(Morphology.erode(small, radius: -4).pixels == [255, 0])
        #expect(ConnectedComponents(GrayImage(width: 0, height: 0, pixels: [])).components.isEmpty)

        // Canvas masks.
        let mask = CanvasMask(GrayImage(width: 3000, height: 2, fill: 255))
        #expect(mask.pixelCount == BoardCanvas.side * 2)
        for millimetres in [Double.nan, .infinity, -.infinity, -3, 0, 1e9] {
            _ = mask.dilated(by: millimetres)
        }
        #expect(mask.dilated(by: 1e9).pixelCount == BoardCanvas.side * BoardCanvas.side)
        for point in [BoardPoint(x: .nan, y: 0), BoardPoint(x: .infinity, y: 0), BoardPoint(x: 1e300, y: -1e300)] {
            #expect(!mask.contains(point))
        }
        let damaged = Data(#"{"spans":[5,-100,99999,-4,0,10,1300,0,4,7,9,8,1]}"#.utf8)
        let decoded = try? JSONDecoder().decode(CanvasMask.self, from: damaged)
        #expect(decoded?.pixelCount == BoardCanvas.side)

        // Crops.
        let canvas = CanvasImage(rgb: RGBImage(width: 4, height: 4, fill: SIMD3(9, 9, 9)), valid: GrayImage(width: 4, height: 4, fill: 255))
        for (span, scale) in [(Double.nan, 6.0), (50, .nan), (0, 6), (-1, 6), (50, 0), (1e300, 6), (50, 1e300), (.infinity, 1)] {
            let crop = canvas.crop(centre: BoardPoint(x: 0, y: 0), span: span, scale: scale)
            #expect(crop.width >= 1 && crop.width <= 8192 && crop.pixels.count == crop.width * crop.height * 3)
        }
        _ = canvas.crop(centre: BoardPoint(x: .nan, y: 3), span: 50, scale: 6)

        // Accumulator: more frames than the 16-bit sums hold, and frames of mismatched sizes.
        var accumulator = FrameAccumulator()
        let white = CanvasImage(rgb: RGBImage(width: 2, height: 2, fill: SIMD3(255, 255, 255)), valid: GrayImage(width: 2, height: 2, fill: 255))
        for _ in 0..<300 { accumulator.add(white) }
        #expect(accumulator.mean()?.rgb.pixels.allSatisfy { $0 == 255 } == true)
        accumulator.add(CanvasImage(rgb: RGBImage(width: 2, height: 2, fill: SIMD3(0, 0, 0)), valid: GrayImage(width: 3, height: 2, fill: 255)))
        accumulator.add(canvas)
        #expect(accumulator.count == 1 && accumulator.noiseSigma() == nil)
    }
}
