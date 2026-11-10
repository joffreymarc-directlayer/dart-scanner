import SwiftUI
import DartCore

/// Canvas sizes used by SnapshotTool, in points.
public enum SnapshotDevice: String, CaseIterable, Sendable {
    case phonePortrait, phoneLandscape, padPortrait, padLandscape

    public var size: CGSize {
        switch self {
        case .phonePortrait: return CGSize(width: 393, height: 852)
        case .phoneLandscape: return CGSize(width: 852, height: 393)
        case .padPortrait: return CGSize(width: 834, height: 1194)
        case .padLandscape: return CGSize(width: 1194, height: 834)
        }
    }
}

/// One screen that SnapshotTool renders: a pure-SwiftUI content view fed with fixture data.
public struct SnapshotScreen: Identifiable {
    /// File name stem: "home", "play-killer", "calibration".
    public let id: String
    public let devices: [SnapshotDevice]
    public let make: @MainActor (SnapshotDevice) -> AnyView

    public init(id: String, devices: [SnapshotDevice] = [.phonePortrait], make: @escaping @MainActor (SnapshotDevice) -> AnyView) {
        self.id = id
        self.devices = devices
        self.make = make
    }
}

public enum SnapshotCatalog {
    /// Every screen, in the order of ARCHITECTURE.md §8.11: kernel, then game flow, then camera flow.
    @MainActor public static var all: [SnapshotScreen] {
        kernelScreens + gameFlowScreens + cameraFlowScreens
    }

    /// Wraps a view the way the app does: size, dark theme, language, background.
    @MainActor public static func framed(_ view: AnyView, device: SnapshotDevice, language: AppLanguage) -> AnyView {
        AnyView(
            view
                .frame(width: device.size.width, height: device.size.height)
                .background(Theme.Palette.background)
                .foregroundStyle(Theme.Palette.textPrimary)
                .environment(\.horizontalSizeClass, device == .padPortrait || device == .padLandscape ? .regular : .compact)
                .environment(\.colorScheme, .dark)
                .appLanguage(language)
        )
    }
}
