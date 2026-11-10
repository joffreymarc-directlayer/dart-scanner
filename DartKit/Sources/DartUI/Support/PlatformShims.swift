import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// Platform shims. Only three files of DartUI contain `#if os(iOS)`: this one, `Camera/CameraPreviewView.swift`
// and `Camera/CaptureInterruptionObserver.swift`. Everything else uses cross-platform SwiftUI (ARCHITECTURE.md §8.8).

extension View {
    /// Full-screen cover on iOS, sheet on macOS.
    @ViewBuilder
    func gameCover<Item: Identifiable, Content: View>(item: Binding<Item?>,
                                                      @ViewBuilder content: @escaping (Item) -> Content) -> some View {
        #if os(iOS)
        fullScreenCover(item: item, content: content)
        #else
        sheet(item: item, content: content)
        #endif
    }

    /// Keeps the screen awake while `active` and the view is on screen (scan screens). No-op on macOS.
    @ViewBuilder
    func keepsScreenAwake(_ active: Bool) -> some View {
        #if os(iOS)
        self
            .onAppear { UIApplication.shared.isIdleTimerDisabled = active }
            .onChange(of: active) { _, isActive in UIApplication.shared.isIdleTimerDisabled = isActive }
            .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
        #else
        self
        #endif
    }
}

extension ToolbarItemPlacement {
    static var barLeading: ToolbarItemPlacement {
        #if os(iOS)
        .topBarLeading
        #else
        .navigation
        #endif
    }

    static var barTrailing: ToolbarItemPlacement {
        #if os(iOS)
        .topBarTrailing
        #else
        .primaryAction
        #endif
    }
}

enum SystemSettings {
    /// Opens the page of the app in the Settings app (camera permission). No-op on macOS.
    @MainActor
    static func open() {
        #if os(iOS)
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
        #endif
    }
}
