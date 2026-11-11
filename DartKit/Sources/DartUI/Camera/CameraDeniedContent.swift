import SwiftUI
import DartCore

/// The camera cannot deliver frames (ARCHITECTURE.md §8.3, `camera-denied`; §8.7, step 1): access refused or
/// restricted, no back camera, the camera taken by another app or stopped by heat. One clear sentence, the way
/// out, and manual input, which always works.
struct CameraDeniedContent: View {
    let issue: CameraIssue
    var openSettings: () -> Void = {}
    var continueManually: () -> Void = {}

    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        let margin = Theme.Metrics(sizeClass).screenMargin
        VStack(alignment: .leading, spacing: Theme.Spacing.section) {
            Spacer(minLength: 0)
            Image(systemName: symbol)
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(Theme.Palette.accent)
                .frame(width: 64, height: 64)
                .background(Theme.Palette.surfaceRaised, in: Circle())
                .accessibilityHidden(true)
            L10n.text(titleKey, .camera)
                .font(CameraStyle.pageTitle)
                .foregroundStyle(Theme.Palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            L10n.text(detailKey, .camera)
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Palette.textSecondary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
            if issue == .accessDenied {
                Card {
                    HStack(alignment: .top, spacing: Theme.Spacing.row) {
                        Image(systemName: "gearshape")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Theme.Palette.info)
                        L10n.text("camera.denied.path", .camera)
                            .font(Theme.Typography.body)
                            .foregroundStyle(Theme.Palette.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(Theme.Spacing.cardInset)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            HStack(alignment: .top, spacing: Theme.Spacing.row) {
                Image(systemName: "hand.tap")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.Palette.textSecondary)
                L10n.text("camera.denied.manual", .camera)
                    .font(Theme.Typography.secondary)
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            VStack(spacing: Theme.Spacing.block) {
                if issue == .accessDenied {
                    PrimaryButton(L10n.text("camera.denied.openSettings", .camera), systemImage: "gearshape",
                                  action: openSettings)
                    SecondaryButton(L10n.text("camera.denied.continueManually", .camera), action: continueManually)
                } else {
                    PrimaryButton(L10n.text("camera.denied.continueManually", .camera), action: continueManually)
                }
            }
        }
        .frame(maxWidth: 560, alignment: .leading)
        .padding(.horizontal, margin)
        .padding(.vertical, Theme.Spacing.section + 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Palette.background)
    }

    private var symbol: String {
        switch issue {
        case .accessDenied: return "video.slash.fill"
        case .noCamera: return "video.slash"
        case .notFullScreen: return "rectangle.split.2x1"
        case .systemPressure: return "thermometer.high"
        case .failed: return "exclamationmark.triangle"
        }
    }

    private var titleKey: LocalizedStringKey {
        switch issue {
        case .accessDenied: return "camera.denied.title"
        case .noCamera: return "camera.unavailable.noCamera.title"
        case .notFullScreen: return "camera.unavailable.notFullScreen.title"
        case .systemPressure: return "camera.unavailable.systemPressure.title"
        case .failed: return "camera.unavailable.failed.title"
        }
    }

    private var detailKey: LocalizedStringKey {
        switch issue {
        case .accessDenied: return "camera.denied.detail"
        case .noCamera: return "camera.unavailable.noCamera.detail"
        case .notFullScreen: return "camera.unavailable.notFullScreen.detail"
        case .systemPressure: return "camera.unavailable.systemPressure.detail"
        case .failed: return "camera.unavailable.failed.detail"
        }
    }
}
