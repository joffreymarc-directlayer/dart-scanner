// DartAudio — haptics, on iPhone only (ARCHITECTURE.md §7.6). With AudioSessionController.swift, the only file of
// the target that contains `#if os(iOS)`.
import Foundation
#if os(iOS)
import CoreHaptics
import UIKit
#endif

/// What `AudioDirector` asks of the haptics. Main thread only.
@MainActor
protocol HapticsPlaying: AnyObject {
    /// True on a device with a Taptic Engine. Never a test on the kind of device.
    var isSupported: Bool { get }
    /// Wakes the Taptic Engine so that the next haptic comes without latency.
    func prepare()
    func play(_ pattern: HapticPattern)
}

/// The feedback generators of UIKit. An iPad and a Mac have no Taptic Engine: `isSupported` is false there and
/// nothing is played, which is why every event also has a sound and a visual sign.
@MainActor
final class HapticsPlayer: HapticsPlaying {
    #if os(iOS)
    let isSupported = CHHapticEngine.capabilitiesForHardware().supportsHaptics
    private lazy var light = UIImpactFeedbackGenerator(style: .light)
    private lazy var medium = UIImpactFeedbackGenerator(style: .medium)
    private lazy var heavy = UIImpactFeedbackGenerator(style: .heavy)
    private lazy var notification = UINotificationFeedbackGenerator()

    func prepare() {
        guard isSupported else { return }
        light.prepare()
        medium.prepare()
        heavy.prepare()
        notification.prepare()
    }

    func play(_ pattern: HapticPattern) {
        guard isSupported else { return }
        switch pattern {
        case .light: light.impactOccurred()
        case .medium: medium.impactOccurred()
        case .heavy: heavy.impactOccurred()
        case .success: notification.notificationOccurred(.success)
        case .warning: notification.notificationOccurred(.warning)
        case .failure: notification.notificationOccurred(.error)
        }
    }
    #else
    let isSupported = false

    func prepare() {}

    func play(_ pattern: HapticPattern) {}
    #endif
}
