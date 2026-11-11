import CoreVideo
import Foundation
import simd
import Testing
import DartCore
@testable import DartVision

/// The motion gate (VISION.md §6.1) on small hand-made frames and on synthetic ones.
@Suite struct EngineGateTests {
    /// A grey frame with an optional bright square, `size` pixels, no noise.
    private func frame(width: Int = 400, height: Int = 300, square: (x: Int, y: Int, side: Int)? = nil, level: UInt8 = 100,
                       time: TimeInterval = 0) -> Frame {
        var image = RGBImage(width: width, height: height, fill: SIMD3(level, level, level))
        if let square {
            for y in square.y..<min(height, square.y + square.side) {
                for x in square.x..<min(width, square.x + square.side) {
                    image[x, y] = SIMD3(250, 250, 250)
                }
            }
        }
        return Frame(image: image, timestamp: time)
    }

    private func gate(width: Int = 400, height: Int = 300) -> MotionGate {
        MotionGate(region: MotionGateRegion(x: 0, y: 0, width: width, height: height), parameters: ScanParameters())
    }

    @Test func gateImage_longSideAtMost320() {
        #expect(MotionGate.blockFactor(width: 2000, height: 2700, longSide: 320) == 9)
        #expect(MotionGate.blockFactor(width: 640, height: 480, longSide: 320) == 2)
        #expect(MotionGate.blockFactor(width: 320, height: 100, longSide: 320) == 1)
        let layout = gate(width: 1000, height: 700).layout(for: PixelSize(width: 1000, height: 700))
        #expect(layout?.factor == 4 && layout?.width == 250 && layout?.height == 175)
        // A region partly outside the frame is clipped to it.
        let clipped = MotionGate(region: MotionGateRegion(x: -50, y: 100, width: 500, height: 500), parameters: ScanParameters())
            .layout(for: PixelSize(width: 300, height: 400))
        #expect(clipped == MotionGate.Layout(x0: 0, y0: 100, factor: 1, width: 300, height: 300))
    }

    @Test func samples_motionReferenceBorderAndLuma() {
        var gate = gate()
        let first = gate.ingest(frame(time: 0))
        // The first frame compares with nothing; without a reference everything counts as changed.
        #expect(first.motionFraction == 0 && first.changeVsReference == 1 && first.borderChange == 0)
        #expect(first.timestamp == 0 && abs(first.meanLuma - 100) < 1e-9 && !gate.hadPrevious)
        gate.setReferenceToCurrent()
        let still = gate.ingest(frame(time: 1.0 / 30))
        #expect(still.motionFraction == 0 && still.changeVsReference == 0 && gate.hadPrevious)
        // A 40 px square in the middle: 1600 / 30000 of the gate (factor 2, 200 × 150 gate pixels, 20 × 20 changed).
        let middle = gate.ingest(frame(square: (180, 130, 40), time: 2.0 / 30))
        #expect(abs(middle.motionFraction - 400.0 / 30_000) < 1e-12)
        // Against a flat reference the range of every neighbourhood is one level: the whole square has changed.
        #expect(abs(middle.changeVsReference - 400.0 / 30_000) < 1e-12)
        #expect(middle.borderChange == 0)
        #expect(middle.meanLuma > 100)
        // A square on the border of the region shows in `borderChange`.
        let border = gate.ingest(frame(square: (0, 0, 60), time: 3.0 / 30))
        #expect(border.borderChange > 0.04 && border.motionFraction > 0)
    }

    /// The reference is compared with the range of its 3 × 3 neighbourhood: an edge that moves by less than a gate
    /// pixel is no lasting change, a new object is.
    @Test func reference_toleratesASubPixelShiftOfAnEdge() {
        var gate = gate()
        // A vertical edge between 60 and 200 at x = 200 (gate column 100).
        func edge(at position: Int, square: Bool = false) -> Frame {
            var image = RGBImage(width: 400, height: 300, fill: SIMD3(60, 60, 60))
            for y in 0..<300 {
                for x in position..<400 { image[x, y] = SIMD3(200, 200, 200) }
            }
            if square {
                for y in 20..<40 {
                    for x in 20..<40 { image[x, y] = SIMD3(250, 250, 250) }
                }
            }
            return Frame(image: image, timestamp: 0)
        }
        _ = gate.ingest(edge(at: 200))
        gate.setReferenceToCurrent()
        let shifted = gate.ingest(edge(at: 201))
        #expect(shifted.motionFraction > 0, "the edge moved: motion against the previous frame")
        #expect(shifted.changeVsReference == 0, "but no lasting change against the reference")
        let object = gate.ingest(edge(at: 201, square: true))
        #expect(abs(object.changeVsReference - 100.0 / 30_000) < 1e-12)
    }

    @Test func threshold_followsTheCommittedNoise() {
        var gate = gate()
        #expect(gate.currentThreshold == 12 && gate.noiseSigma == 0)
        var random = SupportRandom(seed: 5)
        for index in 0..<14 {
            var image = RGBImage(width: 400, height: 300, fill: SIMD3(100, 100, 100))
            for i in 0..<image.pixels.count {
                image.pixels[i] = UInt8(max(0, min(255, 100 + (random.gaussian() * 12).rounded())))
            }
            _ = gate.ingest(Frame(image: image, timestamp: Double(index) / 30))
        }
        gate.commitNoise(frames: 12)
        // Noise of 12 levels per pixel, block means of 2 × 2: about 6 levels in the gate.
        #expect(gate.noiseSigma > 4.5 && gate.noiseSigma < 7.5, "\(gate.noiseSigma)")
        #expect(abs(gate.currentThreshold - 5 * gate.noiseSigma) < 1e-12)
        gate.restart()
        #expect(gate.ingest(frame()).motionFraction == 0 && !gate.hadPrevious)
    }

    /// The camera delivers 32BGRA buffers: the same image gives the same samples as an RGB frame.
    @Test func bgraFrames_readLikeRGBFrames() throws {
        let camera = EngineScenes.debugCamera
        let calibration = camera.calibration()
        let images = [SupportScenes.empty(seed: 3).render(camera: camera),
                      SupportScenes.darts([EngineScenes.steel(20, 60)], seed: 4).render(camera: camera)]
        var fromRGB = MotionGate(calibration: calibration)
        var fromBGRA = MotionGate(calibration: calibration)
        for (index, image) in images.enumerated() {
            let buffer = try #require(EngineGateTests.pixelBuffer(image))
            let bgra = try #require(Frame(pixelBuffer: buffer, timestamp: Double(index)))
            #expect(bgra.format == .bgra8 && bgra.makeRGBImage() == image)
            let a = fromRGB.ingest(Frame(image: image, timestamp: Double(index)))
            let b = fromBGRA.ingest(bgra)
            #expect(a == b)
            if index == 0 {
                fromRGB.setReferenceToCurrent()
                fromBGRA.setReferenceToCurrent()
            } else {
                #expect(a.motionFraction > 0.001)
            }
        }
    }

    /// The region is the bounding box of the rectifier's region of interest, and the gate image's long side is at
    /// most 320 pixels.
    @Test func region_isTheRectifiersBox() throws {
        for camera in SupportPoses.cameras {
            let calibration = camera.calibration()
            let box = BoardRectifier(calibration: calibration).imageRegionOfInterest
            let gate = MotionGate(calibration: calibration)
            #expect(gate.region == MotionGateRegion(x: box.x, y: box.y, width: box.width, height: box.height))
            let layout = try #require(gate.layout(for: calibration.imageSize))
            #expect(max(layout.width, layout.height) <= 320 && max(layout.width, layout.height) > 160)
        }
    }

    /// A 32BGRA pixel buffer with the pixels of `image` (rows may be padded).
    static func pixelBuffer(_ image: RGBImage) -> CVPixelBuffer? {
        var created: CVPixelBuffer?
        guard CVPixelBufferCreate(kCFAllocatorDefault, image.width, image.height, kCVPixelFormatType_32BGRA, nil, &created)
                == kCVReturnSuccess, let buffer = created,
              CVPixelBufferLockBaseAddress(buffer, []) == kCVReturnSuccess else { return nil }
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        let out = base.assumingMemoryBound(to: UInt8.self)
        for y in 0..<image.height {
            for x in 0..<image.width {
                let source = (y * image.width + x) * 3
                let target = y * bytesPerRow + x * 4
                out[target] = image.pixels[source + 2]
                out[target + 1] = image.pixels[source + 1]
                out[target + 2] = image.pixels[source]
                out[target + 3] = 255
            }
        }
        return buffer
    }
}
