#if canImport(AVFoundation)
import Foundation
import simd
import CoreGraphics
import CoreVideo
import DartCore
import AVFoundation

public struct CameraConfiguration: Hashable, Sendable {
    public enum Preset: Sendable { case hd1080, uhd4K }
    public enum MainsFrequency: Sendable { case hz50, hz60 }
    public var preset: Preset = .uhd4K
    public var framesPerSecond: Int = 30
    /// Default: from the locale's region.
    public var mainsFrequency: MainsFrequency?
    /// Seconds of auto convergence before the lock.
    public var lockDelay: TimeInterval = 1.5
    public init() {}
}

/// The only AVFoundation code of the package. iOS-only controls sit behind `#if os(iOS)` inside;
/// on macOS it compiles as a plain webcam source.
public final class CameraFrameSource: NSObject, FrameSource, CameraControlling,
                                      AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    public init(configuration: CameraConfiguration = .init()) { fatalError("unimplemented") }
    public static func requestAccess() async -> Bool { fatalError("unimplemented") }
    /// For `AVCaptureVideoPreviewLayer` in DartUI.
    public var captureSession: AVCaptureSession { get { fatalError("unimplemented") } }
    public var info: FrameSourceInfo? { get { fatalError("unimplemented") } }
    public func start(on queue: DispatchQueue, handler: @escaping @Sendable (Frame) -> Void) async throws { fatalError("unimplemented") }
    public func stop() async { fatalError("unimplemented") }
    public func lockFocusExposureWhiteBalance() async throws -> Bool { fatalError("unimplemented") }
    public func unlock() async { fatalError("unimplemented") }
}
#endif
