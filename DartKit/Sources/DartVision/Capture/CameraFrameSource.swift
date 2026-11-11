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
///
/// Capture configuration (VISION.md §2.4, ARCHITECTURE.md §6.5), applied once, inside `beginConfiguration()` /
/// `commitConfiguration()`, on the queue given to `start`, before `startRunning()`:
/// - back `.builtInWideAngleCamera` (macOS: the default video device); preset 4K when available, else 1080p; a fixed
///   frame rate of `framesPerSecond`; 32BGRA buffers; `alwaysDiscardsLateVideoFrames`;
/// - iOS: stabilisation and HDR off, geometric distortion correction left as it is, delivery of the intrinsic matrix
///   when supported, multitasking camera access when supported, and the rotation angle set ONCE from
///   `AVCaptureDevice.RotationCoordinator.videoRotationAngleForHorizonLevelCapture`; it becomes
///   `FrameSourceInfo.rotationDegrees`.
///
/// `lockFocusExposureWhiteBalance()` lets focus, exposure and white balance converge for `lockDelay`, then locks
/// them, with an exposure of 1/100 s (50 Hz mains) or 1/120 s (60 Hz) at the ISO that keeps the brightness, or
/// 1/50 or 1/60 s when that ISO is above the format's maximum (iOS only; macOS returns false).
public final class CameraFrameSource: NSObject, FrameSource, CameraControlling,
                                      AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    public init(configuration: CameraConfiguration = .init()) {
        self.configuration = configuration
        session = AVCaptureSession()
        output = AVCaptureVideoDataOutput()
        super.init()
    }

    public static func requestAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .video)
        default:
            return false
        }
    }

    /// For `AVCaptureVideoPreviewLayer` in DartUI.
    public var captureSession: AVCaptureSession {
        session
    }

    public var info: FrameSourceInfo? {
        lock.withLock { currentInfo }
    }

    public func start(on queue: DispatchQueue, handler: @escaping @Sendable (Frame) -> Void) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            queue.async { [self] in
                do {
                    try configureIfNeeded(queue: queue)
                    lock.withLock {
                        self.handler = handler
                        self.queue = queue
                    }
                    if !session.isRunning { session.startRunning() }
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    public func stop() async {
        guard let queue = lock.withLock({ self.queue }) else { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queue.async { [self] in
                lock.withLock { handler = nil }
                if session.isRunning { session.stopRunning() }
                continuation.resume()
            }
        }
    }

    public func lockFocusExposureWhiteBalance() async throws -> Bool {
        guard let device = lock.withLock({ self.device }) else { return false }
        #if os(iOS)
        try CameraFrameSource.converge(device)
        let delay = configuration.lockDelay.isFinite ? max(0, configuration.lockDelay) : 1.5
        try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        return try CameraFrameSource.lock(device, mains: mainsFrequency)
        #else
        _ = device
        return false
        #endif
    }

    public func unlock() async {
        guard let device = lock.withLock({ self.device }) else { return }
        #if os(iOS)
        try? CameraFrameSource.converge(device)
        #else
        _ = device
        #endif
    }

    // MARK: - Sample buffers

    public func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let time = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        let seconds = time.isValid ? time.seconds : 0
        guard let frame = Frame(pixelBuffer: pixelBuffer, timestamp: seconds.isFinite ? seconds : 0) else { return }
        let deliver = lock.withLock { () -> (@Sendable (Frame) -> Void)? in
            if let info = currentInfo, info.size != frame.size {
                currentInfo = FrameSourceInfo(size: frame.size, nominalFramesPerSecond: info.nominalFramesPerSecond,
                                              rotationDegrees: info.rotationDegrees, intrinsics: info.intrinsics,
                                              isLive: true)
            }
            return handler
        }
        deliver?(frame)
    }

    // MARK: - Internal state (lot V5)

    private let configuration: CameraConfiguration
    private let session: AVCaptureSession
    private let output: AVCaptureVideoDataOutput
    /// Guards every `var` below.
    private let lock = NSLock()
    private var device: AVCaptureDevice?
    private var currentInfo: FrameSourceInfo?
    private var handler: (@Sendable (Frame) -> Void)?
    private var queue: DispatchQueue?
    private var configured = false

    /// Mains frequency of the exposure lock: the configured one, or the region's.
    var mainsFrequency: CameraConfiguration.MainsFrequency {
        configuration.mainsFrequency ?? CameraFrameSource.mainsFrequency(forRegion: Locale.current.region?.identifier)
    }
}

/// Why the camera cannot start (lot V5).
enum CaptureCameraError: Error, Sendable {
    case noCamera
    case cannotAddInput
    case cannotAddOutput
}

// MARK: - Configuration (lot V5)

extension CameraFrameSource {
    /// Regions on 60 Hz mains; every other region is taken as 50 Hz.
    static let sixtyHertzRegions: Set<String> = [
        "US", "CA", "MX", "BR", "CO", "VE", "EC", "PE", "PA", "CR", "NI", "HN", "SV", "GT", "BZ", "CU", "DO", "PR", "HT",
        "JM", "BS", "TT", "SR", "GY", "TW", "KR", "PH", "SA", "LR", "AS", "GU", "MP", "VI", "BM", "KY", "AW", "MS", "FM",
        "MH", "PW", "JP",
    ]

    static func mainsFrequency(forRegion region: String?) -> CameraConfiguration.MainsFrequency {
        guard let region else { return .hz50 }
        return sixtyHertzRegions.contains(region.uppercased()) ? .hz60 : .hz50
    }

    /// Configures the session once. Called on the session queue.
    private func configureIfNeeded(queue: DispatchQueue) throws {
        if lock.withLock({ configured }) { return }
        #if os(iOS)
        let found = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
        #else
        let found = AVCaptureDevice.default(for: .video)
        #endif
        guard let device = found else { throw CaptureCameraError.noCamera }
        let input = try AVCaptureDeviceInput(device: device)

        session.beginConfiguration()
        defer { session.commitConfiguration() }
        if configuration.preset == .uhd4K, session.canSetSessionPreset(.hd4K3840x2160) {
            session.sessionPreset = .hd4K3840x2160
        } else if session.canSetSessionPreset(.hd1920x1080) {
            session.sessionPreset = .hd1920x1080
        }
        guard session.canAddInput(input) else { throw CaptureCameraError.cannotAddInput }
        session.addInput(input)
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: queue)
        guard session.canAddOutput(output) else { throw CaptureCameraError.cannotAddOutput }
        session.addOutput(output)

        CameraFrameSource.fixFrameRate(device, framesPerSecond: configuration.framesPerSecond)
        var rotation = 0
        #if os(iOS)
        if session.isMultitaskingCameraAccessSupported { session.isMultitaskingCameraAccessEnabled = true }
        if device.activeFormat.isVideoHDRSupported {
            if (try? device.lockForConfiguration()) != nil {
                device.automaticallyAdjustsVideoHDREnabled = false
                device.isVideoHDREnabled = false
                device.unlockForConfiguration()
            }
        }
        if let connection = output.connection(with: .video) {
            if connection.isVideoStabilizationSupported { connection.preferredVideoStabilizationMode = .off }
            if connection.isCameraIntrinsicMatrixDeliverySupported { connection.isCameraIntrinsicMatrixDeliveryEnabled = true }
            // Once, before `startRunning()`: never from the interface orientation (ARCHITECTURE.md §6.5).
            let coordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: nil)
            let angle = coordinator.videoRotationAngleForHorizonLevelCapture
            if connection.isVideoRotationAngleSupported(angle) {
                connection.videoRotationAngle = angle
                rotation = CameraFrameSource.quarterTurns(angle)
            }
        }
        #endif

        let dimensions = CMVideoFormatDescriptionGetDimensions(device.activeFormat.formatDescription)
        let landscape = PixelSize(width: Int(dimensions.width), height: Int(dimensions.height))
        let size = rotation == 90 || rotation == 270 ? PixelSize(width: landscape.height, height: landscape.width) : landscape
        #if os(iOS)
        // The field of view of the active format is that of its long side (VISION.md §4.2, case 2).
        let fieldOfView = Double(device.activeFormat.videoFieldOfView)
        #else
        // A webcam does not tell: the calibration falls back to self-calibration or the assumed field of view.
        let fieldOfView = 0.0
        #endif
        let intrinsics = fieldOfView.isFinite && fieldOfView > 0 && size.width > 0
            ? CameraIntrinsics(longSideFieldOfViewDegrees: fieldOfView, imageSize: size) : nil
        lock.withLock {
            self.device = device
            currentInfo = FrameSourceInfo(size: size, nominalFramesPerSecond: Double(max(1, configuration.framesPerSecond)),
                                          rotationDegrees: rotation, intrinsics: intrinsics, isLive: true)
            configured = true
        }
    }

    /// 0, 90, 180 or 270 for a rotation angle in degrees.
    static func quarterTurns(_ angle: CGFloat) -> Int {
        let rounded = Int((Double(angle) / 90).rounded()) * 90
        return ((rounded % 360) + 360) % 360
    }

    /// A fixed frame rate, when the active format supports it.
    private static func fixFrameRate(_ device: AVCaptureDevice, framesPerSecond: Int) {
        let rate = Double(max(1, framesPerSecond))
        let supported = device.activeFormat.videoSupportedFrameRateRanges.contains {
            $0.minFrameRate <= rate && rate <= $0.maxFrameRate
        }
        guard supported, (try? device.lockForConfiguration()) != nil else { return }
        let duration = CMTime(value: 1, timescale: CMTimeScale(max(1, framesPerSecond)))
        device.activeVideoMinFrameDuration = duration
        device.activeVideoMaxFrameDuration = duration
        device.unlockForConfiguration()
    }

    #if os(iOS)
    /// Continuous focus, exposure and white balance.
    private static func converge(_ device: AVCaptureDevice) throws {
        try device.lockForConfiguration()
        defer { device.unlockForConfiguration() }
        if device.isFocusModeSupported(.continuousAutoFocus) { device.focusMode = .continuousAutoFocus }
        if device.isExposureModeSupported(.continuousAutoExposure) { device.exposureMode = .continuousAutoExposure }
        if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
            device.whiteBalanceMode = .continuousAutoWhiteBalance
        }
    }

    /// Locks focus and white balance, and the exposure at a duration in phase with the mains. False when one of
    /// the three cannot be locked.
    private static func lock(_ device: AVCaptureDevice, mains: CameraConfiguration.MainsFrequency) throws -> Bool {
        try device.lockForConfiguration()
        defer { device.unlockForConfiguration() }
        var complete = true
        if device.isFocusModeSupported(.locked) { device.focusMode = .locked } else { complete = false }
        if device.isWhiteBalanceModeSupported(.locked) { device.whiteBalanceMode = .locked } else { complete = false }
        if device.isExposureModeSupported(.custom) {
            let format = device.activeFormat
            let current = device.exposureDuration.seconds
            let iso = Double(device.iso)
            let preferred = mains == .hz50 ? 1.0 / 100 : 1.0 / 120
            let fallback = mains == .hz50 ? 1.0 / 50 : 1.0 / 60
            var duration = preferred
            var target = current.isFinite && current > 0 ? iso * current / duration : iso
            if target > Double(format.maxISO) {
                duration = fallback
                target = current.isFinite && current > 0 ? iso * current / duration : iso
            }
            let minimum = format.minExposureDuration.seconds, maximum = format.maxExposureDuration.seconds
            if minimum.isFinite, maximum.isFinite { duration = min(max(duration, minimum), maximum) }
            let clampedISO = Float(min(max(target, Double(format.minISO)), Double(format.maxISO)))
            device.setExposureModeCustom(duration: CMTime(seconds: duration, preferredTimescale: 1_000_000), iso: clampedISO,
                                         completionHandler: nil)
        } else if device.isExposureModeSupported(.locked) {
            device.exposureMode = .locked
        } else {
            complete = false
        }
        return complete
    }
    #endif
}
#endif
