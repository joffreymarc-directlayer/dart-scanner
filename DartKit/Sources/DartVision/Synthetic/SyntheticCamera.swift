import Foundation
import simd
import CoreGraphics
import CoreVideo
import DartCore

/// A pinhole camera placed in the board frame. Ground truth for every synthetic test.
public struct SyntheticCamera: Hashable, Sendable {
    public var imageSize: PixelSize
    public var intrinsics: CameraIntrinsics
    /// Camera centre in the board frame, mm (z > 0).
    public var position: SIMD3<Double>
    public var lookAt: BoardPoint
    public var rollDegrees: Double
    public init(imageSize: PixelSize, longSideFieldOfViewDegrees: Double = 67, position: SIMD3<Double>,
                lookAt: BoardPoint = BoardPoint(x: 0, y: 0), rollDegrees: Double = 0) {
        self.imageSize = imageSize
        self.intrinsics = CameraIntrinsics(longSideFieldOfViewDegrees: longSideFieldOfViewDegrees, imageSize: imageSize)
        self.position = position
        self.lookAt = lookAt
        self.rollDegrees = rollDegrees
    }

    /// H = K [r1 r2 t].
    public var boardToImage: Homography {
        let rows = rotationRows
        let right = rows.right, down = rows.down, forward = rows.forward
        // t = −R·C.
        let t = -SIMD3(simd_dot(right, position), simd_dot(down, position), simd_dot(forward, position))
        // [r1 r2 t]: the first two columns of R, then t.
        let m0 = SIMD3(right.x, right.y, t.x)
        let m1 = SIMD3(down.x, down.y, t.y)
        let m2 = SIMD3(forward.x, forward.y, t.z)
        return Homography(row0: intrinsics.fx * m0 + intrinsics.cx * m2,
                          row1: intrinsics.fy * m1 + intrinsics.cy * m2,
                          row2: m2)
    }

    /// Image of a point of the board frame (mm). A point at or behind the plane of the camera centre has no
    /// image: both coordinates are NaN.
    public func project(_ point: SIMD3<Double>) -> ImagePoint {
        let rows = rotationRows
        let relative = point - position
        let depth = simd_dot(rows.forward, relative)
        guard depth > 0 else { return ImagePoint(x: .nan, y: .nan) }
        return ImagePoint(x: intrinsics.fx * simd_dot(rows.right, relative) / depth + intrinsics.cx,
                          y: intrinsics.fy * simd_dot(rows.down, relative) / depth + intrinsics.cy)
    }

    /// Projection of the four handle junctions. Built with `CalibrationHandles(points:)` from
    /// `CalibrationHandle.boardPoint` and `project(_:)`: no call into lot V2 (section 10.1).
    public func exactHandles() -> CalibrationHandles {
        CalibrationHandles(points: CalibrationHandle.allCases.map { handle in
            let junction = handle.boardPoint
            return project(SIMD3(junction.x, junction.y, 0))
        })
    }

    /// The exact calibration of this camera, built from the ground truth without any image and without
    /// `BoardCalibrator` (section 10.1). This is how every test gets a `BoardCalibration` when the calibrator
    /// is not what it tests. `grade` is imposed, not derived from the pose.
    public func calibration(grade: CalibrationQuality.Grade = .good) -> BoardCalibration {
        let transform = boardToImage
        let handles = exactHandles()
        let pose = CameraPose(boardToImage: transform, intrinsics: intrinsics) ?? groundTruthPose
        let foot = pose.footPoint
        let footDistance = (foot.x * foot.x + foot.y * foot.y).squareRoot()

        // Worst-direction scale over the bull and the eight points of r = 170 at multiples of 45 degrees.
        var minimumScale = transform.localScale(at: SIMD2(0, 0)).min
        for k in 0..<8 {
            let angle = Double(k) * .pi / 4
            minimumScale = min(minimumScale, transform.localScale(at: SIMD2(170 * sin(angle), 170 * cos(angle))).min)
        }

        let residual: Double
        let refined: Bool
        let issues: [CalibrationIssue]
        switch grade {
        case .good:
            residual = 0.2; refined = true; issues = []
        case .fair:
            residual = 0.5; refined = true; issues = []
        case .poor:
            residual = 0.9; refined = false; issues = [.refinementRejected]
        }
        let quality = CalibrationQuality(grade: grade,
                                         edgeResidualRMS: residual,
                                         edgeInlierFraction: 1,
                                         measuredFraction: 1,
                                         refinementApplied: refined,
                                         maxHandleShift: 0,
                                         minPixelsPerMillimetre: minimumScale,
                                         viewAngleDegrees: atan(footDistance / pose.distance) * 180 / .pi,
                                         minTanObliquity: (footDistance - 170) / pose.distance,
                                         maxTanObliquity: (footDistance + 170) / pose.distance,
                                         issues: issues)
        return BoardCalibration(id: SyntheticCamera.calibrationID,
                                createdAt: Date(timeIntervalSinceReferenceDate: 0),
                                imageSize: imageSize,
                                rotationDegrees: 0,
                                userHandles: handles,
                                handles: handles,
                                boardToImage: transform,
                                imageToBoard: transform.inverse ?? .identity,
                                ringRadii: .nominal,
                                wireHeight: 0,
                                intrinsics: intrinsics,
                                pose: pose,
                                quality: quality)
    }

    /// A bumped tripod: the camera centre moves by `delta` mm and rolls by `rollDegrees` more.
    ///
    /// The camera keeps its orientation: the aim point slides with the centre, so that a move parallel to the
    /// board shifts the whole image (about `f / distance` pixels per millimetre) instead of re-aiming at the board.
    public func moved(by delta: SIMD3<Double>, rollDegrees: Double) -> SyntheticCamera {
        var camera = self
        let newPosition = position + delta
        camera.position = newPosition
        // Same viewing direction: the new aim point is where the old direction, from the new centre, meets the board.
        if position.z != 0 {
            let ratio = newPosition.z / position.z
            camera.lookAt = BoardPoint(x: newPosition.x + (lookAt.x - position.x) * ratio,
                                       y: newPosition.y + (lookAt.y - position.y) * ratio)
        } else {
            camera.lookAt = BoardPoint(x: lookAt.x + delta.x, y: lookAt.y + delta.y)
        }
        camera.rollDegrees = self.rollDegrees + rollDegrees
        return camera
    }
}

extension SyntheticCamera {
    /// Identifier of every exact calibration (VISION.md §10.1): two calls return equal values.
    static let calibrationID = UUID(uuidString: "00000000-0000-0000-0000-000000000001") ?? UUID()

    /// Rows of the board-to-camera rotation: `forward = normalise(lookAt − C)`,
    /// `right = normalise(forward × (0, 1, 0))`, `down = forward × right`, then the roll about `forward`.
    /// A positive roll turns the camera clockwise as seen from behind it.
    var rotationRows: (right: SIMD3<Double>, down: SIMD3<Double>, forward: SIMD3<Double>) {
        var forward = SIMD3(lookAt.x, lookAt.y, 0) - position
        let length = simd_length(forward)
        forward = length > 0 && length.isFinite ? forward / length : SIMD3(0, 0, -1)
        var right = simd_cross(forward, SIMD3(0, 1, 0))
        let rightLength = simd_length(right)
        // Looking straight along the board's y axis leaves no horizontal reference: use the board's x axis.
        right = rightLength > 1e-12 ? right / rightLength : SIMD3(1, 0, 0)
        let down = simd_cross(forward, right)
        let roll = rollDegrees * .pi / 180
        let c = cos(roll), s = sin(roll)
        return (c * right + s * down, c * down - s * right, forward)
    }

    /// The pose read from the camera itself.
    var groundTruthPose: CameraPose {
        let rows = rotationRows
        return CameraPose(center: position, rotationRows: [rows.right, rows.down, rows.forward],
                          isApproximate: intrinsics.isApproximate)
    }
}
