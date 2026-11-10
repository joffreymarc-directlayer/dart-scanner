import Foundation
import simd
import DartCore
@testable import DartVision

/// Helpers shared by the calibration tests (lot V2): ground-truth errors, noisy handles, cameras of a chosen
/// resolution. Poses, random values and scenes come from `Support/` (lot V1).
enum CalibrationFixtures {
    /// Distances from the bull of the 200 board points of the error measure, mm.
    static let errorRadius: Double = 170

    /// The `count` board points (r ≤ 170) on which a calibration is compared with the truth; fixed by `seed`.
    static func boardPoints(count: Int = 200, seed: UInt64 = 99) -> [BoardPoint] {
        var random = SupportRandom(seed: seed)
        return (0..<count).map { _ in random.boardPoint(maxRadius: errorRadius) }
    }

    /// Error of a calibration on the board, mm: for each of 200 points `X` (r ≤ 170) imaged by the true `H`,
    /// `|G_cal(H(X)) − X|` (VISION.md §10.2, C2). RMS, 95th percentile and maximum.
    static func errors(of calibration: BoardCalibration, truth: Homography, count: Int = 200)
        -> (rms: Double, p95: Double, max: Double) {
        summary(boardPoints(count: count).map { point in
            let image = truth.apply(SIMD2(point.x, point.y))
            return simd_length(calibration.imageToBoard.apply(image) - SIMD2(point.x, point.y))
        })
    }

    /// RMS, 95th percentile (the value below which 95 % of them lie) and maximum of non-negative values.
    static func summary(_ values: [Double]) -> (rms: Double, p95: Double, max: Double) {
        guard !values.isEmpty else { return (0, 0, 0) }
        let sorted = values.sorted()
        let rms = (sorted.reduce(0) { $0 + $1 * $1 } / Double(sorted.count)).squareRoot()
        let index = max(0, Int((0.95 * Double(sorted.count)).rounded(.up)) - 1)
        return (rms, sorted[index], sorted[sorted.count - 1])
    }

    /// The handles with Gaussian noise of `sigma` px on every coordinate.
    static func noisy(_ handles: CalibrationHandles, sigma: Double, random: inout SupportRandom) -> CalibrationHandles {
        CalibrationHandles(points: handles.points.map {
            ImagePoint(x: $0.x + sigma * random.gaussian(), y: $0.y + sigma * random.gaussian())
        })
    }

    /// A 4K portrait camera below the board (`azimuth` 180 is straight below), aimed at the bull, `viewAngle`
    /// degrees off the board normal, at the distance that gives about `pixelsPerMillimetre` at the bull.
    static func camera(pixelsPerMillimetre: Double, viewAngle: Double, azimuth: Double = 180, roll: Double = 0,
                       imageSize: PixelSize = PixelSize(width: 2160, height: 3840)) -> SyntheticCamera {
        let probe = SyntheticCamera(imageSize: imageSize, position: SIMD3(0, 0, 1000))
        let distance = probe.intrinsics.fx / pixelsPerMillimetre
        return SupportRandom.camera(distance: distance, viewAngleDegrees: viewAngle, azimuthDegrees: azimuth,
                                    rollDegrees: roll, imageSize: imageSize)
    }

    /// The image of a board point of height `z` mm.
    static func project(_ camera: SyntheticCamera, _ point: BoardPoint, z: Double = 0) -> ImagePoint {
        camera.project(SIMD3(point.x, point.y, z))
    }

    /// Handles at the four junctions lifted to the height `z` (the plane of the wires).
    static func handles(_ camera: SyntheticCamera, z: Double) -> CalibrationHandles {
        CalibrationHandles(points: CalibrationHandle.allCases.map { project(camera, $0.boardPoint, z: z) })
    }

    /// The board-to-image homography of a scene whose whole image was shifted by `shift` px.
    static func shifted(_ transform: Homography, by shift: SIMD2<Double>) -> Homography {
        Homography(row0: transform.row0 + shift.x * transform.row2,
                   row1: transform.row1 + shift.y * transform.row2,
                   row2: transform.row2)
    }

    /// A still of `camera` with the default nuisances.
    static func still(_ camera: SyntheticCamera, seed: UInt64 = 1, gain: Double = 1) -> RGBImage {
        var scene = SupportScenes.empty(seed: seed)
        scene.gain = gain
        return scene.render(camera: camera)
    }

    /// `calibrate` with the true intrinsics of `camera`; nil on failure.
    static func calibrate(_ calibrator: BoardCalibrator = BoardCalibrator(), handles: CalibrationHandles,
                          still: RGBImage, camera: SyntheticCamera) -> BoardCalibration? {
        guard case .success(let calibration) = calibrator.calibrate(handles: handles, still: still, rotationDegrees: 0,
                                                                     intrinsics: camera.intrinsics) else { return nil }
        return calibration
    }

    /// `preview` with the true intrinsics of `camera`; nil on failure.
    static func preview(_ calibrator: BoardCalibrator = BoardCalibrator(), handles: CalibrationHandles,
                        camera: SyntheticCamera) -> BoardCalibration? {
        guard case .success(let calibration) = calibrator.preview(handles: handles, imageSize: camera.imageSize,
                                                                   rotationDegrees: 0, intrinsics: camera.intrinsics)
        else { return nil }
        return calibration
    }
}
