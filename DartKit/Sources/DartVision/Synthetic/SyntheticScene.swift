import Foundation
import simd
import CoreGraphics
import CoreVideo
import DartCore

public struct SyntheticScene: Sendable {
    public var darts: [SyntheticDart] = []
    public var radii: RingRadii = .nominal
    /// Height of the wires above the board plane, mm: they are rendered as flat ribbons in the plane z = wireHeight.
    public var wireHeight: Double = 0
    /// Point light in the board frame, mm; nil means no cast shadows.
    public var light: SIMD3<Double>?
    /// Brightness ratio inside shadows (1 = no shadow, 0.65 = soft, 0.35 = hard).
    public var shadowStrength: Double = 1
    public var gain: Double = 1
    /// Gaussian noise sigma in levels.
    public var noiseSigma: Double = 2
    /// Number of 3x3 box blur passes.
    public var blurPasses: Int = 1
    /// Whole-image shift in px (sub-pixel jitter).
    public var shift: SIMD2<Double> = .zero
    /// A skin-coloured disc above the board plane: centre and radius in mm.
    public var hand: (centre: BoardPoint, radius: Double)?
    public var seed: UInt64 = 1
    public init() {}

    /// Camera image (ray caster, 3x3 supersampling).
    ///
    /// Order of the steps: rays, box blur, whole-image shift, gain, noise.
    public func render(camera: SyntheticCamera) -> RGBImage {
        finished(baseImage(camera: camera))
    }

    /// The same scene rendered directly in the canvas, for stage tests without a rectifier.
    ///
    /// One ray per canvas pixel, then the same blur, shift, gain and noise, in canvas pixels. A pixel is valid
    /// where `BoardRectifier` would give a valid pixel for the exact calibration of `camera`: inside its region
    /// of interest and inside the camera frame. Invalid pixels are black.
    public func renderCanvas(camera: SyntheticCamera) -> CanvasImage {
        let side = BoardCanvas.side
        // Validity is the rectifier's own: a black frame of the camera's size, rectified through the exact
        // calibration, is valid exactly where any frame would be.
        let rectifier = BoardRectifier(calibration: camera.calibration())
        let width = max(0, camera.imageSize.width), height = max(0, camera.imageSize.height)
        let valid = rectifier.rectify(RGBImage(width: width, height: height, pixels: [UInt8](repeating: 0, count: width * height * 3))).valid
        // Rays are cast a little beyond the region, so that the blur and the shift read real colours at its edge.
        let blur = max(0, min(blurPasses, 64))
        let slide = shift.x.isFinite && shift.y.isFinite ? min(64, max(abs(shift.x), abs(shift.y)).rounded(.up)) : 0
        let margin = blur + Int(slide) + 2
        var box = SyntheticPixelBox(x0: 0, y0: 0, x1: 0, y1: 0)
        if let bounds = rectifier.regionOfInterest.boundingBox {
            box = SyntheticPixelBox(x0: bounds.minX, y0: bounds.minY, x1: bounds.maxX + 1, y1: bounds.maxY + 1)
                .expanded(by: margin, within: side, side)
        }
        var image = SyntheticRayCaster(scene: self, camera: camera).canvasImage(box: box)
        if !box.isEmpty {
            image = image.boxBlurred(passes: blur, columns: box.x0..<box.x1, rows: box.y0..<box.y1)
        }
        image = finished(SyntheticBaseImage(image: image, content: box))
        // Invalid pixels are black.
        var pixels = image.pixels
        valid.pixels.withUnsafeBufferPointer { flags in
            pixels.withUnsafeMutableBufferPointer { out in
                var index = 0
                let count = flags.count
                while index < count {
                    if flags[index] == 0 {
                        out[index * 3] = 0
                        out[index * 3 + 1] = 0
                        out[index * 3 + 2] = 0
                    }
                    index += 1
                }
            }
        }
        return CanvasImage(rgb: RGBImage(width: side, height: side, pixels: pixels), valid: valid)
    }
}

// MARK: - Rendering in two stages (lot V1, internal)

extension SyntheticScene {
    /// Rays and blur: everything that stays the same while only the shift, the gain and the noise change.
    /// `solids` replaces the darts of the scene (a dart in flight, for the script).
    func baseImage(camera: SyntheticCamera, solids: [SyntheticDartSolid]? = nil) -> SyntheticBaseImage {
        var base = SyntheticRayCaster(scene: self, camera: camera, solids: solids).cameraImage()
        let passes = max(0, min(blurPasses, 64))
        if passes > 0, !base.content.isEmpty {
            let width = base.image.width, height = base.image.height
            let box = base.content.expanded(by: passes, within: width, height)
            base.image = base.image.boxBlurred(passes: passes, columns: box.x0..<box.x1, rows: box.y0..<box.y1)
            base.content = box
        }
        return base
    }

    /// Shift, gain and noise of this scene applied to a base image.
    func finished(_ base: SyntheticBaseImage) -> RGBImage {
        var image = base.image
        if (shift.x != 0 || shift.y != 0), shift.x.isFinite, shift.y.isFinite, !base.content.isEmpty {
            let reach = Int(min(4096, max(abs(shift.x), abs(shift.y)).rounded(.up))) + 1
            let box = base.content.expanded(by: reach, within: image.width, image.height)
            image = image.shifted(dx: shift.x, dy: shift.y, columns: box.x0..<box.x1, rows: box.y0..<box.y1)
        }
        var pixels = image.pixels
        SyntheticNoise.apply(to: &pixels, bytesPerRow: image.width * 3, gain: gain, sigma: noiseSigma, seed: seed)
        return RGBImage(width: image.width, height: image.height, pixels: pixels)
    }

    /// The scene without blur, shift, gain change or noise: the exact geometry.
    var withoutNuisances: SyntheticScene {
        var scene = self
        scene.gain = 1
        scene.noiseSigma = 0
        scene.blurPasses = 0
        scene.shift = .zero
        return scene
    }
}
