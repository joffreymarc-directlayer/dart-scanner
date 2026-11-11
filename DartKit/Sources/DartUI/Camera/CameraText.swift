import Foundation
import DartCore
import DartVision

/// Texts of the camera flow that leave the views: the advice a `CameraInputSource` hands to the play screen
/// (`DartInputEvent.advisory`, a `LocalizedText`), read from the table `Camera` in both languages (§8.7, §8.9).
enum CameraText {
    /// A key of the table `Camera`, in French and in English.
    static func localized(_ key: String.LocalizationValue) -> LocalizedText {
        LocalizedText(fr: L10n.string(key, .camera, language: .fr), en: L10n.string(key, .camera, language: .en))
    }

    /// The one-line advice for an event of the table "Événements" of ARCHITECTURE.md §8.7, nil for an event that
    /// gives none. In photo mode the light advice asks for a new empty reference (§8.7, "Scanner la volée").
    static func advice(for event: ScanEvent, mode: ScanMode) -> LocalizedText? {
        switch event {
        case .takeoutStalled:
            return localized("scan.advice.takeoutStalled")
        case .lightingChanged:
            return mode == .photo ? localized("scan.advice.lightingChanged.photo") : localized("scan.advice.lightingChanged")
        case .unrecognizedChange:
            return localized("scan.advice.unrecognizedChange")
        case .advisory(let advisory):
            return advice(for: advisory)
        default:
            return nil
        }
    }

    static func advice(for advisory: ScanAdvisory) -> LocalizedText {
        switch advisory {
        case .viewObstructed: return localized("scan.advice.viewObstructed")
        case .accuracyDegraded: return localized("scan.advice.accuracyDegraded")
        case .suggestScanMode: return localized("scan.advice.suggestScanMode")
        case .suggestLightingCheck: return localized("scan.advice.suggestLightingCheck")
        case .flicker: return localized("scan.advice.flicker")
        case .lowLight: return localized("scan.advice.lowLight")
        case .thermalThrottling: return localized("scan.advice.thermalThrottling")
        }
    }

    /// What the player reads about a camera that cannot deliver frames.
    static func issueKey(_ issue: CameraIssue) -> String.LocalizationValue {
        switch issue {
        case .accessDenied: return "camera.issue.accessDenied"
        case .noCamera: return "camera.issue.noCamera"
        case .notFullScreen: return "camera.issue.notFullScreen"
        case .systemPressure: return "camera.issue.systemPressure"
        case .failed: return "camera.issue.failed"
        }
    }
}
