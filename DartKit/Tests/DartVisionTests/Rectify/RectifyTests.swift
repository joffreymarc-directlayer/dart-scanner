import Foundation
import simd
import CoreVideo
import Testing
import DartCore
@testable import DartVision

/// The rectifier against the direct canvas rendering (R1), its region of interest, its edge cases and the frame
/// accumulator.
@Suite struct RectifyTests {
    /// Pixels within `radius` canvas pixels of a colour change of `exact` (a canvas rendered without nuisances).
    private func edges(of exact: CanvasImage, radius: Int) -> GrayImage {
        let side = BoardCanvas.side
        var marks = GrayImage(width: side, height: side, fill: 0)
        let rgb = exact.rgb.pixels
        for y in 0..<side {
            for x in 0..<side {
                let index = (y * side + x) * 3
                if x + 1 < side {
                    let right = index + 3
                    if rgb[index] != rgb[right] || rgb[index + 1] != rgb[right + 1] || rgb[index + 2] != rgb[right + 2] {
                        marks[x, y] = 255
                        marks[x + 1, y] = 255
                    }
                }
                if y + 1 < side {
                    let below = index + side * 3
                    if rgb[index] != rgb[below] || rgb[index + 1] != rgb[below + 1] || rgb[index + 2] != rgb[below + 2] {
                        marks[x, y] = 255
                        marks[x, y + 1] = 255
                    }
                }
            }
        }
        return Morphology.dilate(marks, radius: radius)
    }

    /// Mean absolute difference over the pixels valid in both canvases and away from the edges, and their number.
    private func comparison(_ a: CanvasImage, _ b: CanvasImage, excluding edges: GrayImage) -> (mean: Double, pixels: Int) {
        var selection = GrayImage(width: BoardCanvas.side, height: BoardCanvas.side, fill: 0)
        var count = 0
        for index in 0..<selection.pixels.count where a.valid.pixels[index] != 0 && b.valid.pixels[index] != 0 && edges.pixels[index] == 0 {
            selection.pixels[index] = 255
            count += 1
        }
        return (a.rgb.meanAbsoluteDifference(to: b.rgb, where: selection) ?? .infinity, count)
    }

    /// Centre of the inner bull in a canvas, canvas pixels: centroid of the redness `R − G` within 20 px of the
    /// nominal centre (the red disc is 12.7 px in radius, so the window does not bias it).
    private func bullCentre(_ canvas: CanvasImage) -> SIMD2<Double> {
        var sum = SIMD2<Double>(0, 0), weight = 0.0
        for y in 619...660 {
            for x in 619...660 {
                let dx = Double(x) - 639.5, dy = Double(y) - 639.5
                guard dx * dx + dy * dy <= 400 else { continue }
                let p = canvas.rgb[x, y]
                let redness = max(0, Double(p.x) - Double(p.y))
                sum += redness * SIMD2(Double(x), Double(y))
                weight += redness
            }
        }
        return weight > 0 ? sum / weight : SIMD2(.nan, .nan)
    }

    private func scenes(for camera: SyntheticCamera) -> [(name: String, scene: SyntheticScene)] {
        var withDarts = SupportScenes.darts([
            SyntheticDart(tip: BoardPoint(x: 0, y: 103)),
            SyntheticDart(tip: BoardPoint(x: -60, y: -40), leanUpDegrees: 12, leanSideDegrees: 5, style: .brass),
            SyntheticDart(tip: BoardPoint(x: 100, y: 20), leanUpDegrees: 4, style: .allBlack),
        ], seed: 7)
        withDarts.light = SupportScenes.lampOpposite(to: camera)
        withDarts.shadowStrength = 0.65
        return [("empty", SupportScenes.empty(seed: 3)), ("darts", withDarts)]
    }

    // MARK: R1

    @Test func r1_rectifiedCameraImageAgainstDirectCanvas() throws {
        for pose in SupportPoses.allCases {
            let camera = pose.camera
            let rectifier = BoardRectifier(calibration: camera.calibration())
            for (name, scene) in scenes(for: camera) {
                let rectified = rectifier.rectify(scene.render(camera: camera))
                let direct = scene.renderCanvas(camera: camera)
                let exact = scene.withoutNuisances.renderCanvas(camera: camera)
                // Validity: the same pixels, all of them inside the region of interest.
                let sameValidity = rectified.valid == direct.valid
                #expect(sameValidity, "\(pose) \(name): validity")
                let result = comparison(rectified, direct, excluding: edges(of: exact, radius: 3))
                #expect(result.pixels > 400_000, "\(pose) \(name): \(result.pixels) pixels compared")
                #expect(result.mean <= 6, "\(pose) \(name): mean absolute difference \(result.mean)")
                if result.mean > 6 {
                    supportDump(rectified.rgb, named: "r1-\(pose.rawValue)-\(name)-rectified")
                    supportDump(direct.rgb, named: "r1-\(pose.rawValue)-\(name)-direct")
                }
                // The bull lands on the canvas centre, (639.5, 639.5), within half a canvas pixel.
                let bull = bullCentre(rectified)
                #expect(simd_distance(bull, SIMD2(639.5, 639.5)) <= 0.5, "\(pose) \(name): bull at \(bull)")
                #expect(simd_distance(bullCentre(direct), SIMD2(639.5, 639.5)) <= 0.5, "\(pose) \(name): direct bull")
            }
        }
    }

    /// Centroid, in canvas pixels, of `weight` over the canvas pixels whose metric point is in the box.
    private func centroid(_ canvas: CanvasImage, x: ClosedRange<Double>, y: ClosedRange<Double>,
                          weight: (SIMD3<UInt8>) -> Double) -> SIMD2<Double> {
        let first = BoardCanvas.pixel(for: BoardPoint(x: x.lowerBound, y: y.upperBound))
        let last = BoardCanvas.pixel(for: BoardPoint(x: x.upperBound, y: y.lowerBound))
        var sum = SIMD2<Double>(0, 0), total = 0.0
        for row in Int(first.y.rounded())...Int(last.y.rounded()) {
            for column in Int(first.x.rounded())...Int(last.x.rounded()) {
                let w = weight(canvas.rgb[column, row])
                sum += w * SIMD2(Double(column), Double(row))
                total += w
            }
        }
        return sum / total
    }

    @Test func rectify_bedCentroidsAgreeToATenthOfAPixel() throws {
        // Four beds far apart (T20 and T3 red, D6 and D11 green), each alone of its colour in its box: their
        // centroids in the rectified image and in the direct rendering agree to 0.1 canvas pixel, which pins the
        // warp's translation, rotation and scale much more tightly than the bull test of R1.
        let redness: (SIMD3<UInt8>) -> Double = { max(0, Double($0.x) - Double($0.y)) }
        let greenness: (SIMD3<UInt8>) -> Double = { max(0, Double($0.y) - Double($0.x)) }
        let beds: [(name: String, x: ClosedRange<Double>, y: ClosedRange<Double>, weight: (SIMD3<UInt8>) -> Double)] = [
            ("T20", -25...25, 94...112, redness), ("T3", -25...25, -112...(-94), redness),
            ("D6", 157...175, -30...30, greenness), ("D11", -175...(-157), -30...30, greenness),
        ]
        for pose in SupportPoses.allCases {
            let camera = pose.camera
            let scene = SupportScenes.exact()
            let rectified = BoardRectifier(calibration: camera.calibration()).rectify(scene.render(camera: camera))
            let direct = scene.renderCanvas(camera: camera)
            for bed in beds {
                let a = centroid(rectified, x: bed.x, y: bed.y, weight: bed.weight)
                let b = centroid(direct, x: bed.x, y: bed.y, weight: bed.weight)
                #expect(simd_distance(a, b) < 0.1, "\(pose) \(bed.name): rectified \(a), direct \(b)")
            }
            #expect(simd_distance(bullCentre(rectified), SIMD2(639.5, 639.5)) < 0.1, "\(pose): bull")
        }
    }

    @Test func r1_denseSourceAveragesFourReads() throws {
        // 4K at 0.65 m: more than 3 px/mm, so every canvas pixel averages four reads.
        let camera = SyntheticCamera(imageSize: PixelSize(width: 2160, height: 3840), position: SIMD3(60, -250, 600))
        let calibration = camera.calibration()
        #expect(calibration.quality.minPixelsPerMillimetre > 3)
        let scene = SupportScenes.empty(seed: 11)
        let rectified = BoardRectifier(calibration: calibration).rectify(scene.render(camera: camera))
        let direct = scene.renderCanvas(camera: camera)
        let sameValidity = rectified.valid == direct.valid
        #expect(sameValidity)
        let result = comparison(rectified, direct, excluding: edges(of: scene.withoutNuisances.renderCanvas(camera: camera), radius: 3))
        #expect(result.pixels > 100_000 && result.mean <= 6, "dense source: \(result)")
        #expect(simd_distance(bullCentre(rectified), SIMD2(639.5, 639.5)) <= 0.5)
    }

    @Test func rectify_aDenseSourceIsAveraged() {
        // A one-pixel checkerboard of 0 and 255. Above 3 px/mm every canvas pixel averages four reads a quarter of
        // a canvas pixel apart (more than half a camera pixel here): the pattern melts into mid-grey. At 1.3 px/mm
        // one bilinear read per pixel keeps it.
        func checkerboard(_ size: PixelSize) -> RGBImage {
            var pixels = [UInt8](repeating: 0, count: size.width * size.height * 3)
            for y in 0..<size.height {
                for x in 0..<size.width where (x + y) % 2 == 0 {
                    let index = (y * size.width + x) * 3
                    pixels[index] = 255
                    pixels[index + 1] = 255
                    pixels[index + 2] = 255
                }
            }
            return RGBImage(width: size.width, height: size.height, pixels: pixels)
        }
        func spread(_ canvas: CanvasImage) -> Double {
            var sum = 0.0, squares = 0.0, count = 0.0
            for index in stride(from: 0, to: canvas.valid.pixels.count, by: 3) where canvas.valid.pixels[index] != 0 {
                let value = Double(canvas.rgb.pixels[index * 3])
                sum += value
                squares += value * value
                count += 1
            }
            return (squares / count - (sum / count) * (sum / count)).squareRoot()
        }
        let dense = SyntheticCamera(imageSize: PixelSize(width: 2160, height: 3840), position: SIMD3(60, -250, 600))
        let sparse = SupportPoses.b.camera
        let denseSpread = spread(BoardRectifier(calibration: dense.calibration()).rectify(checkerboard(dense.imageSize)))
        let sparseSpread = spread(BoardRectifier(calibration: sparse.calibration()).rectify(checkerboard(sparse.imageSize)))
        #expect(denseSpread < 25 && sparseSpread > 40, "dense \(denseSpread), sparse \(sparseSpread)")
    }

    // MARK: Frames and formats

    @Test func rectify_framesOfEveryFormatGiveTheSameCanvas() throws {
        let camera = SupportPoses.b.camera
        let image = SupportScenes.empty(seed: 5).render(camera: camera)
        let rectifier = BoardRectifier(calibration: camera.calibration())
        let fromImage = rectifier.rectify(image)
        let sameAsImage = rectifier.rectify(Frame(image: image, timestamp: 3)).rgb == fromImage.rgb
        #expect(sameAsImage)
        // The same pixels in a BGRA pixel buffer with padded rows.
        var buffer: CVPixelBuffer?
        let attributes = [kCVPixelBufferBytesPerRowAlignmentKey as String: 256] as CFDictionary
        let status = CVPixelBufferCreate(nil, image.width, image.height, kCVPixelFormatType_32BGRA, attributes, &buffer)
        let pixelBuffer = try #require(status == kCVReturnSuccess ? buffer : nil)
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        let base = try #require(CVPixelBufferGetBaseAddress(pixelBuffer)).assumingMemoryBound(to: UInt8.self)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        for y in 0..<image.height {
            for x in 0..<image.width {
                let p = image[x, y]
                let pixel = base + y * bytesPerRow + x * 4
                pixel[0] = p.z
                pixel[1] = p.y
                pixel[2] = p.x
                pixel[3] = 255
            }
        }
        CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
        let frame = try #require(Frame(pixelBuffer: pixelBuffer, timestamp: 1.5))
        #expect(frame.format == .bgra8 && frame.size == image.size && frame.timestamp == 1.5)
        let copied = frame.makeRGBImage() == image
        #expect(copied)
        let fromFrame = rectifier.rectify(frame)
        let sameCanvas = fromFrame.rgb == fromImage.rgb && fromFrame.valid == fromImage.valid
        #expect(sameCanvas)
        // Other pixel formats are refused.
        var other: CVPixelBuffer?
        CVPixelBufferCreate(nil, 8, 8, kCVPixelFormatType_32ARGB, nil, &other)
        let argb = try #require(other)
        #expect(Frame(pixelBuffer: argb, timestamp: 0) == nil)
    }

    @Test func rectify_aFrameOfAnotherSizeHasNoValidPixel() {
        let camera = SupportPoses.b.camera
        let rectifier = BoardRectifier(calibration: camera.calibration())
        for size in [PixelSize(width: 1080, height: 1920), PixelSize(width: 1919, height: 1080), PixelSize(width: 0, height: 0)] {
            let canvas = rectifier.rectify(RGBImage(width: size.width, height: size.height, fill: SIMD3(200, 0, 0)))
            #expect(canvas.valid.pixels.allSatisfy { $0 == 0 } && canvas.rgb.pixels.allSatisfy { $0 == 0 }, "\(size)")
            #expect(canvas.rgb.width == BoardCanvas.side && canvas.valid.height == BoardCanvas.side)
        }
        // An image whose pixel array is too short is refused as well, without reading past its end.
        let short = RGBImage(width: 1920, height: 1080, pixels: [UInt8](repeating: 9, count: 100))
        #expect(rectifier.rectify(short).valid.pixels.allSatisfy { $0 == 0 })
        // The same input twice gives the same canvas.
        let image = SupportScenes.empty().render(camera: camera)
        let repeatable = rectifier.rectify(image).rgb == rectifier.rectify(image).rgb
        #expect(repeatable)
    }

    // MARK: Region of interest

    @Test func regionOfInterest_boardDiscPlusTheDartBodies() throws {
        let camera = SupportPoses.a.camera
        let rectifier = BoardRectifier(calibration: camera.calibration())
        let roi = rectifier.regionOfInterest
        // Every point of the board disc r <= 190.
        for degrees in stride(from: 0.0, to: 360, by: 7.5) {
            let a = degrees * .pi / 180
            #expect(roi.contains(BoardPoint(x: 189 * sin(a), y: 189 * cos(a))), "r = 189 at \(degrees)")
        }
        // Darts lean away from the camera foot point F = (150, −450): far above the board is inside, far below is not.
        #expect(roi.contains(BoardPoint(x: 0, y: 300)))
        #expect(!roi.contains(BoardPoint(x: 0, y: -300)) && !roi.contains(BoardPoint(x: 0, y: -195)))
        #expect(!roi.contains(BoardPoint(x: 0, y: 315)))
        // The rule of VISION.md §5.2, D1, point by point on a coarse grid.
        let foot = camera.calibration().pose.footPoint
        var checked = 0
        for y in stride(from: 3, to: BoardCanvas.side, by: 17) {
            for x in stride(from: 5, to: BoardCanvas.side, by: 17) {
                let q = BoardCanvas.boardPoint(x: Double(x), y: Double(y))
                let r = hypot(q.x, q.y)
                var inside = r <= 190
                let away = SIMD2(q.x - foot.x, q.y - foot.y) / hypot(q.x - foot.x, q.y - foot.y)
                for step in 0...1350 where !inside {
                    let p = SIMD2(q.x, q.y) - Double(step) / 10 * away
                    inside = simd_length(p) <= 175
                }
                // Points within a sampling step of the boundary may go either way.
                let lambda = min(135, max(0, simd_dot(SIMD2(q.x, q.y), away)))
                let closest = simd_length(SIMD2(q.x, q.y) - lambda * away)
                if abs(closest - 175) > 0.05 && abs(r - 190) > 0.05 {
                    #expect(roi.contains(x: x, y: y) == inside, "(\(x), \(y))")
                    checked += 1
                }
            }
        }
        #expect(checked > 5000)
        // With an approximate pose: the disc r <= 320.
        let approximate = BoardRectifier.makeRegionOfInterest(footPoint: foot, poseIsApproximate: true)
        #expect(approximate.contains(BoardPoint(x: 0, y: -310)) && approximate.contains(BoardPoint(x: 225, y: 225)))
        #expect(!approximate.contains(BoardPoint(x: 230, y: 230)))
        // The box in the camera image holds the projection of every pixel of the region.
        let box = rectifier.imageRegionOfInterest
        #expect(box.x >= 0 && box.y >= 0 && box.x + box.width <= camera.imageSize.width && box.y + box.height <= camera.imageSize.height)
        var outside = 0
        roi.forEachRun { y, x0, x1 in
            for x in [x0, x1 - 1] {
                let p = camera.project(SIMD3(BoardCanvas.boardPoint(x: Double(x), y: Double(y)).x,
                                             BoardCanvas.boardPoint(x: Double(x), y: Double(y)).y, 0))
                if p.x < Double(box.x) - 0.5 || p.x > Double(box.x + box.width) - 0.5
                    || p.y < Double(box.y) - 0.5 || p.y > Double(box.y + box.height) - 0.5 { outside += 1 }
            }
        }
        #expect(outside == 0)
    }

    @Test func regionOfInterest_partlyOutsideTheFrameIsInvalid() {
        // A narrow lens: the top of the region of interest falls outside the frame.
        let camera = SyntheticCamera(imageSize: PixelSize(width: 1920, height: 1080), longSideFieldOfViewDegrees: 40,
                                     position: SIMD3(0, -400, 1000))
        let rectifier = BoardRectifier(calibration: camera.calibration())
        let canvas = rectifier.rectify(RGBImage(width: 1920, height: 1080, fill: SIMD3(10, 20, 30)))
        let roi = rectifier.regionOfInterest.makeImage()
        var inRegion = 0, valid = 0, validOutsideRegion = 0
        for index in 0..<roi.pixels.count {
            if roi.pixels[index] != 0 { inRegion += 1 }
            if canvas.valid.pixels[index] != 0 {
                valid += 1
                if roi.pixels[index] == 0 { validOutsideRegion += 1 }
                #expect(canvas.rgb.pixels[index * 3] == 10 && canvas.rgb.pixels[index * 3 + 2] == 30)
            }
        }
        #expect(validOutsideRegion == 0 && valid > 0 && valid < inRegion)
        // An invalid pixel is black, and every valid one maps inside the frame.
        for y in stride(from: 0, to: BoardCanvas.side, by: 9) {
            for x in stride(from: 0, to: BoardCanvas.side, by: 9) {
                let p = BoardCanvas.boardPoint(x: Double(x), y: Double(y))
                let image = camera.project(SIMD3(p.x, p.y, 0))
                let inFrame = image.x >= -0.5 && image.y >= -0.5 && image.x <= 1919.5 && image.y <= 1079.5
                if canvas.valid[x, y] != 0 {
                    #expect(inFrame)
                } else {
                    #expect(canvas.rgb[x, y] == SIMD3(0, 0, 0))
                    if roi.pixels[y * BoardCanvas.side + x] != 0 && abs(image.y + 0.5) > 0.01 {
                        #expect(!inFrame, "(\(x), \(y))")
                    }
                }
            }
        }
    }

    // MARK: Canvas crop

    @Test func canvasCrop_isCentredAndScaled() {
        var rgb = RGBImage(width: BoardCanvas.side, height: BoardCanvas.side, fill: SIMD3(0, 0, 0))
        // A white square of 10x10 canvas pixels around the bull.
        for y in 635..<645 {
            for x in 635..<645 {
                rgb[x, y] = SIMD3(255, 255, 255)
            }
        }
        let canvas = CanvasImage(rgb: rgb, valid: GrayImage(width: BoardCanvas.side, height: BoardCanvas.side, fill: 255))
        let crop = canvas.crop(centre: BoardPoint(x: 0, y: 0), span: 10, scale: 4)
        // 10 mm = 20 canvas pixels, upscaled 4 times.
        #expect(crop.width == 80 && crop.height == 80)
        #expect(crop[40, 40] == SIMD3(255, 255, 255) && crop[2, 2] == SIMD3(0, 0, 0) && crop[77, 40] == SIMD3(0, 0, 0))
        // Symmetric about the centre.
        #expect(crop[30, 40] == crop[49, 40] && crop[40, 21] == crop[40, 58])
        // Outside the canvas is black; degenerate requests give one black pixel.
        let edge = canvas.crop(centre: BoardPoint(x: 320, y: 320), span: 20, scale: 1)
        #expect(edge.width == 40 && edge[39, 0] == SIMD3(0, 0, 0))
        #expect(canvas.crop(centre: BoardPoint(x: 0, y: 0), span: 0, scale: 2).width == 1)
        #expect(canvas.crop(centre: BoardPoint(x: .nan, y: 0), span: 5, scale: 2).width == 1)
    }

    // MARK: Frame accumulator

    @Test func frameAccumulator_meanValidityAndNoise() throws {
        let side = BoardCanvas.side
        var accumulator = FrameAccumulator()
        #expect(accumulator.count == 0 && accumulator.mean() == nil && accumulator.noiseSigma() == nil)
        func canvas(_ value: UInt8, validFrom: Int = 0) -> CanvasImage {
            var valid = GrayImage(width: side, height: side, fill: 255)
            for index in 0..<(validFrom * side) {
                valid.pixels[index] = 0
            }
            return CanvasImage(rgb: RGBImage(width: side, height: side, fill: SIMD3(value, value / 2, 255 - value)), valid: valid)
        }
        accumulator.add(canvas(10))
        let single = accumulator.mean()?.rgb == canvas(10).rgb
        #expect(accumulator.count == 1 && single && accumulator.noiseSigma() == nil)
        accumulator.add(canvas(11, validFrom: 3))
        accumulator.add(canvas(13))
        accumulator.add(canvas(14))
        #expect(accumulator.count == 4)
        let mean = try #require(accumulator.mean())
        // (10 + 11 + 13 + 14) / 4 = 12; (5 + 5 + 6 + 7) / 4 = 5.75 → 6; (245 + 244 + 242 + 241) / 4 = 243.
        #expect(mean.rgb[0, 0] == SIMD3(12, 6, 243) && mean.rgb[side - 1, side - 1] == SIMD3(12, 6, 243))
        // A pixel is valid only if it was valid in every frame.
        #expect(mean.valid[0, 2] == 0 && mean.valid[0, 3] == 255)
        // Noise of the last two frames: |13 − 14| = 1, |6 − 7| = 1, |242 − 241| = 1 everywhere.
        let sigma = try #require(accumulator.noiseSigma())
        #expect(sigma > 0.5 / 0.954 && sigma < 1.5 / 0.954)
        accumulator.reset()
        #expect(accumulator.count == 0 && accumulator.mean() == nil)
        // A frame of another size starts a new average; a malformed frame is ignored.
        accumulator.add(canvas(50))
        accumulator.add(CanvasImage(rgb: RGBImage(width: 4, height: 4, fill: SIMD3(1, 1, 1)), valid: GrayImage(width: 4, height: 4, fill: 255)))
        #expect(accumulator.count == 1 && accumulator.mean()?.rgb.width == 4)
        accumulator.add(CanvasImage(rgb: RGBImage(width: 4, height: 4, fill: SIMD3(1, 1, 1)), valid: GrayImage(width: 3, height: 4, fill: 255)))
        #expect(accumulator.count == 1)
    }

    @Test func frameAccumulator_noiseOfRenderedFrames() throws {
        // Two renders of the same empty board with different seeds: the per-frame noise is the scene's σ = 2.
        let camera = SupportPoses.b.camera
        let rectifier = BoardRectifier(calibration: camera.calibration())
        var accumulator = FrameAccumulator()
        for seed: UInt64 in [21, 22] {
            var scene = SupportScenes.empty(seed: seed)
            scene.blurPasses = 0
            accumulator.add(rectifier.rectify(scene.render(camera: camera)))
        }
        let sigma = try #require(accumulator.noiseSigma())
        // The rectifier interpolates between camera pixels, which lowers the noise a little.
        #expect(sigma > 1.2 && sigma < 2.2, "σ̂ = \(sigma)")
        // Averaging lowers the noise: the mean of 6 frames is closer to the noiseless canvas than one frame.
        let exact = rectifier.rectify(SupportScenes.exact().render(camera: camera))
        accumulator.reset()
        var single: CanvasImage?
        for seed: UInt64 in 30..<36 {
            let frame = rectifier.rectify(SupportScenes.empty(seed: seed).withoutBlur.render(camera: camera))
            single = single ?? frame
            accumulator.add(frame)
        }
        let mean = try #require(accumulator.mean())
        let first = try #require(single)
        let one = try #require(first.rgb.meanAbsoluteDifference(to: exact.rgb, where: exact.valid))
        let six = try #require(mean.rgb.meanAbsoluteDifference(to: exact.rgb, where: exact.valid))
        #expect(six < one * 0.6, "one frame \(one), six frames \(six)")
    }
}

private extension SyntheticScene {
    var withoutBlur: SyntheticScene {
        var scene = self
        scene.blurPasses = 0
        return scene
    }
}
