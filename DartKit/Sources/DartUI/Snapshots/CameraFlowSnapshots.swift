import SwiftUI
import DartCore
import DartVision

extension SnapshotCatalog {
    /// Lot U3: the screens of the camera flow (ARCHITECTURE.md §8.11), with synthetic frames for the camera.
    @MainActor static var cameraFlowScreens: [SnapshotScreen] {
        typealias Fixtures = CameraFlowFixtures
        let phoneAndPad: [SnapshotDevice] = [.phonePortrait, .padLandscape]
        return [
            SnapshotScreen(id: "placement-guide", devices: [.phonePortrait, .padPortrait]) { device in
                CameraFlowFrame.framed(CameraPlacementContent().padding(.top, CameraFlowFrame.insets(device).top), device,
                                       fullBleed: false)
            },
            SnapshotScreen(id: "camera-denied", devices: phoneAndPad) { device in
                CameraFlowFrame.framed(CameraDeniedContent(issue: .accessDenied), device, fullBleed: false)
            },
            SnapshotScreen(id: "camera-unavailable", devices: phoneAndPad) { device in
                CameraFlowFrame.framed(CameraDeniedContent(issue: .noCamera), device, fullBleed: false)
            },
            SnapshotScreen(id: "calibration", devices: phoneAndPad) { device in
                CameraFlowFrame.framed(CalibrationContent(model: Fixtures.calibrationAdjusting(device),
                                                          insets: CameraFlowFrame.insets(device)), device)
            },
            SnapshotScreen(id: "calibration-proof", devices: phoneAndPad) { device in
                CameraFlowFrame.framed(CalibrationContent(model: Fixtures.calibrationProof(device),
                                                          insets: CameraFlowFrame.insets(device)), device)
            },
            SnapshotScreen(id: "live-scan", devices: phoneAndPad) { device in
                CameraFlowFrame.framed(ScanLiveContent(model: Fixtures.liveScan(device), insets: CameraFlowFrame.insets(device)),
                                       device)
            },
            SnapshotScreen(id: "photo-mode", devices: phoneAndPad) { device in
                CameraFlowFrame.framed(PhotoModeContent(model: Fixtures.photoMode(device),
                                                        actions: PhotoModeActions(correctLast: {}),
                                                        insets: CameraFlowFrame.insets(device)), device)
            },
            SnapshotScreen(id: "photo-mode-no-camera", devices: phoneAndPad) { device in
                CameraFlowFrame.framed(PhotoModeContent(model: Fixtures.photoModeWithoutCamera,
                                                        insets: CameraFlowFrame.insets(device)), device)
            },
            SnapshotScreen(id: "photo-review-empty", devices: phoneAndPad) { device in
                CameraFlowFrame.framed(PhotoModeContent(model: Fixtures.photoReviewEmpty(device),
                                                        insets: CameraFlowFrame.insets(device)), device)
            },
            SnapshotScreen(id: "photo-tips", devices: phoneAndPad) { device in
                CameraFlowFrame.framed(PhotoModeContent(model: Fixtures.photoTips(device), insets: CameraFlowFrame.insets(device)),
                                       device)
            },
            // The thumbnail in the column of the iPad play screen (mock-up `PadPlayKiller`).
            SnapshotScreen(id: "scan-thumbnail", devices: [.padLandscape, .phoneLandscape]) { device in
                CameraFlowFrame.playWithThumbnail(device)
            },
        ]
    }
}

/// How a camera-flow content is laid in the frame of a device. A camera screen runs under the status bar: its
/// content receives the insets of the system bars and places its own top bar and panel with them.
@MainActor
enum CameraFlowFrame {
    static func insets(_ device: SnapshotDevice) -> EdgeInsets {
        switch device {
        case .phonePortrait: return EdgeInsets(top: 44, leading: 0, bottom: 18, trailing: 0)
        case .phoneLandscape: return EdgeInsets(top: 0, leading: 0, bottom: 5, trailing: 0)
        case .padPortrait: return EdgeInsets(top: 24, leading: 0, bottom: 4, trailing: 0)
        case .padLandscape: return EdgeInsets(top: 24, leading: 0, bottom: 4, trailing: 0)
        }
    }

    static func framed(_ view: some View, _ device: SnapshotDevice, fullBleed: Bool = true) -> AnyView {
        let insets = insets(device)
        return AnyView(view
            .padding(.bottom, fullBleed ? 0 : insets.bottom)
            .frame(width: device.size.width, height: device.size.height, alignment: .top)
            .clipped())
    }

    /// The Killer of the play screen on a large screen, with the camera thumbnail in its column.
    static func playWithThumbnail(_ device: SnapshotDevice) -> AnyView {
        guard let match = GameFlowFixtures.killerInRound4() else { return AnyView(EmptyView()) }
        let frame = CameraFlowFixtures.twoDarts(device)
        let thumbnail = ScanThumbnailContent(preview: frame.cameraPicture.map(PreviewContent.image) ?? .none,
                                             state: .watching(dartsOnBoard: 2), readiness: .ready(grade: .good))
        let content = PlayContent(model: GameFlowFixtures.model(match, status: .live), thumbnail: AnyView(thumbnail))
        return AnyView(content
            .padding(.top, insets(device).top)
            .frame(width: device.size.width, height: device.size.height, alignment: .top)
            .clipped())
    }
}
