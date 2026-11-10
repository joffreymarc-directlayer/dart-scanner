import Foundation
import simd
import CoreGraphics
import CoreVideo
import DartCore

/// Static description of a frame source.
public struct FrameSourceInfo: Hashable, Sendable {
    public var size: PixelSize
    public var nominalFramesPerSecond: Double
    /// Rotation applied to the delivered buffers: 0, 90, 180 or 270.
    public var rotationDegrees: Int
    public var intrinsics: CameraIntrinsics?
    public var isLive: Bool
    public init(size: PixelSize, nominalFramesPerSecond: Double, rotationDegrees: Int, intrinsics: CameraIntrinsics?, isLive: Bool) {
        self.size = size
        self.nominalFramesPerSecond = nominalFramesPerSecond
        self.rotationDegrees = rotationDegrees
        self.intrinsics = intrinsics
        self.isLive = isLive
    }
}

/// Anything that delivers frames: the camera, a synthetic script, a recorded sequence.
public protocol FrameSource: AnyObject, Sendable {
    /// Nil until the source has started.
    var info: FrameSourceInfo? { get }
    /// `handler` is called on `queue`; each frame is valid only during the call.
    func start(on queue: DispatchQueue, handler: @escaping @Sendable (Frame) -> Void) async throws
    func stop() async
}

/// Camera controls the session needs; implemented by `CameraFrameSource`, absent on synthetic sources.
public protocol CameraControlling: AnyObject, Sendable {
    /// Lets focus, exposure and white balance converge, then locks all three. Returns false when a lock is unsupported.
    func lockFocusExposureWhiteBalance() async throws -> Bool
    func unlock() async
}
