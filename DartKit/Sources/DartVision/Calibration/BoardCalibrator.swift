import Foundation
import simd
import CoreGraphics
import CoreVideo
import DartCore

/// Every calibration constant. Defaults are starting values (section 11).
public struct CalibrationParameters: Hashable, Codable, Sendable {
    // C1 gate
    public var hardMinPixelsPerMillimetre: Double = 0.8
    public var dartMargin: Double = 135
    // C2 edge measurement
    public var profileStep: Double = 0.25
    public var profileHalfWindow: Double = 4.0
    public var secondPassHalfWindow: Double = 2.0
    public var gradientSpan: Int = 2
    public var minEdgeEnergy: Double = 20
    public var edgePeakRatio: Double = 2.5
    public var centroidHalfWidth: Int = 4
    // C3 refinement
    public var huberK: Double = 0.75
    public var outlierCutoff: Double = 3.0
    public var jacobianStep: Double = 0.25
    public var damping: Double = 1e-3
    public var maxIterations: Int = 6
    public var convergence: Double = 0.01
    public var handleTetherWeight: Double = 0.3
    public var minMeasuredFraction: Double = 0.5
    public var minInlierFraction: Double = 0.6
    public var inlierDistance: Double = 1.0
    public var maxInlierRMS: Double = 0.5
    public var maxHandleShift: Double = 4.0
    public var recoverMaxHandleShift: Double = 6.0
    // C4 ring radii, C5 sector phase, C6 wire height
    public var fitRingRadii: Bool = true
    public var ringRadiusTolerance: Double = 2.0
    public var bullRadiusTolerance: Double = 1.0
    public var minSectorLumaContrast: Double = 25
    public var wireHeight: Double = 0
    // Grades
    public var goodRMS: Double = 0.35
    public var fairRMS: Double = 0.7
    public var goodPixelsPerMillimetre: Double = 1.5
    public var fairPixelsPerMillimetre: Double = 1.2
    public var goodMinTan: Double = 0.21
    public var fairMinTan: Double = 0.16
    public var goodMaxTan: Double = 0.84
    public var fairMaxTan: Double = 1.2
    // Drift
    public var driftHealthyMedian: Double = 0.5
    public var driftHealthyInliers: Double = 0.6
    public var driftHealthyInliersWithDarts: Double = 0.5
    public var driftNotVisibleFraction: Double = 0.3
    public init() {}
}

public enum CalibrationError: Error, Equatable, Sendable {
    /// Fewer than four distinct handles, or three of them collinear.
    case degenerateHandles
    /// At least one blocking issue.
    case rejected([CalibrationIssue])
}

/// Result of the drift check (section 4.9).
public struct CalibrationHealth: Hashable, Sendable {
    public enum Status: Sendable { case healthy, drifted, lost, edgesNotVisible }
    public var status: Status
    /// Median absolute edge residual, mm.
    public var medianResidual: Double
    public var inlierFraction: Double
    public var measuredFraction: Double
}

public struct BoardCalibrator: Sendable {
    public init(parameters: CalibrationParameters = .init()) { fatalError("unimplemented") }
    /// Closed-form H plus the sanity gate (C1) and pose (C7). Runs on every handle drag for the live wireframe.
    public func preview(handles: CalibrationHandles, imageSize: PixelSize, rotationDegrees: Int,
                        intrinsics: CameraIntrinsics?) -> Result<BoardCalibration, CalibrationError> { fatalError("unimplemented") }
    /// Full calibration (C1 to C8) on a frozen still of the board.
    public func calibrate(handles: CalibrationHandles, still: RGBImage, rotationDegrees: Int,
                          intrinsics: CameraIntrinsics?) -> Result<BoardCalibration, CalibrationError> { fatalError("unimplemented") }
    /// Drift check on any still or frame; darts may be on the board.
    public func assess(_ calibration: BoardCalibration, on still: RGBImage, dartsOnBoard: Bool) -> CalibrationHealth { fatalError("unimplemented") }
    public func assess(_ calibration: BoardCalibration, on frame: Frame, dartsOnBoard: Bool) -> CalibrationHealth { fatalError("unimplemented") }
    /// Bounded re-refinement starting from the current handles (`recoverMaxHandleShift`). Nil when the gate fails.
    public func recover(_ calibration: BoardCalibration, on still: RGBImage) -> BoardCalibration? { fatalError("unimplemented") }
    public func recover(_ calibration: BoardCalibration, on frame: Frame) -> BoardCalibration? { fatalError("unimplemented") }
}
