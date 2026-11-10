import Foundation
import simd
import CoreGraphics
import CoreVideo
import DartCore

/// The four draggable calibration points: junctions of the outer double wire (r = 170 mm) with four radial wires.
public enum CalibrationHandle: Int, CaseIterable, Codable, Sendable {
    case wire20_1, wire6_10, wire3_19, wire11_14
    /// `(170 sin a, 170 cos a)` for a = 9, 99, 189, 279 degrees:
    /// about (26.59, 167.91), (167.91, -26.59), (-26.59, -167.91), (-167.91, 26.59).
    public var boardPoint: BoardPoint {
        let degrees: Double
        switch self {
        case .wire20_1: degrees = 9
        case .wire6_10: degrees = 99
        case .wire3_19: degrees = 189
        case .wire11_14: degrees = 279
        }
        let a = degrees * .pi / 180
        return BoardPoint(x: 170 * sin(a), y: 170 * cos(a))
    }
    /// Number printed next to the handle in the overlay: "20", "6", "3", "11".
    public var label: String {
        switch self {
        case .wire20_1: return "20"
        case .wire6_10: return "6"
        case .wire3_19: return "3"
        case .wire11_14: return "11"
        }
    }
}

/// Image positions of the four handles, in `CalibrationHandle` order.
public struct CalibrationHandles: Hashable, Codable, Sendable {
    public var points: [ImagePoint]
    public init(points: [ImagePoint]) {
        self.points = points
    }
    /// Handles of a known homography (used by the locator). Lot V2; `SyntheticCamera.exactHandles()` does not call it.
    public init(projecting boardToImage: Homography) { fatalError("unimplemented") }
    public subscript(handle: CalibrationHandle) -> ImagePoint { get { fatalError("unimplemented") } set { fatalError("unimplemented") } }
    /// Starting position: a circle of radius `0.3 * min(width, height)` at the image centre.
    public static func centredDefault(in size: PixelSize) -> CalibrationHandles { fatalError("unimplemented") }
    public func translated(dx: Double, dy: Double) -> CalibrationHandles { fatalError("unimplemented") }
    public func scaledAndRotated(about centre: ImagePoint, scale: Double, radians: Double) -> CalibrationHandles { fatalError("unimplemented") }
    /// Rotates the wireframe by `count` sectors clockwise (18 degrees each). Nil when the handles are degenerate.
    public func rotated(bySectors count: Int) -> CalibrationHandles? { fatalError("unimplemented") }
    /// Rotates the wireframe so that the middle of the 20 sector is as close as possible to `point`.
    /// With `parityPreserving`, only multiples of 36 degrees are tried (the red/green phase is kept).
    public func reoriented(twentyAt point: ImagePoint, parityPreserving: Bool) -> CalibrationHandles? { fatalError("unimplemented") }
}
