import Foundation
#if os(iOS)
import AVFoundation
#endif

/// The third and last file of DartUI allowed to contain `#if os(iOS)` (ARCHITECTURE.md §8.8):
/// `AVCaptureSession.InterruptionReason` and `AVCaptureSessionInterruptionReasonKey` do not exist on macOS.
enum CaptureInterruptionObserver {
    /// Cause of an `AVCaptureSession.wasInterruptedNotification`, read from its user info.
    /// iOS: `videoDeviceNotAvailableWithMultipleForegroundApps` → `.notFullScreen`,
    /// `videoDeviceNotAvailableDueToSystemPressure` → `.systemPressure`, any other reason → `.failed(reason)`.
    /// Other platforms: always `.failed`.
    static func issue(for notification: Notification) -> CameraIssue {
        #if os(iOS)
        guard let value = notification.userInfo?[AVCaptureSessionInterruptionReasonKey] as? Int,
              let reason = AVCaptureSession.InterruptionReason(rawValue: value) else {
            return .failed("interrupted")
        }
        switch reason {
        case .videoDeviceNotAvailableWithMultipleForegroundApps:
            return .notFullScreen
        case .videoDeviceNotAvailableDueToSystemPressure:
            return .systemPressure
        default:
            return .failed("reason \(value)")
        }
        #else
        return .failed(notification.name.rawValue)
        #endif
    }
}
