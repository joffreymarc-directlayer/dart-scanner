import SwiftUI
import DartCore
import DartVision

/// Calibration flow, including the camera-denied screen (ARCHITECTURE.md §8.7, table "Calibrage"). The shell of
/// `CalibrationContent`: it owns the flow, starts it when it appears, and closes it, which deposits
/// `pause(.user)` when the one-dart check armed the vision.
struct CalibrationFlowView: View {
    private let onFinish: () -> Void
    @State private var flow: CalibrationFlowModel
    @Environment(AppModel.self) private var app

    init(camera: CameraModel, onFinish: @escaping () -> Void) {
        self.onFinish = onFinish
        _flow = State(initialValue: CalibrationFlowModel(camera: camera))
    }

    var body: some View {
        CalibrationContent(model: CalibrationContentModel(flow: flow), actions: actions)
            .background(Theme.Palette.background.ignoresSafeArea())
            .task {
                flow.sound = app.environment.sound
                guard flow.stage == .starting else { return }
                await flow.start()
            }
            .keepsScreenAwake(true)
    }

    private var actions: CalibrationContentActions {
        let flow = flow
        return CalibrationContentActions(
            close: finish,
            openSettings: { SystemSettings.open() },
            continuePlacement: { Task { await flow.continueAfterPlacement() } },
            locate: { Task { await flow.locateAutomatically() } },
            validate: { Task { await flow.validate() } },
            moveHandle: { handle, point in flow.moveHandle(handle, to: point) },
            tapImage: { point in
                switch flow.stage {
                case .touchTwenty: Task { await flow.touchTwenty(at: point) }
                case .checkTap: Task { await flow.confirmTip(at: point) }
                default: flow.tapTest(at: point)
                }
            },
            adjustAgain: { flow.adjustAgain() },
            adopt: { Task { await flow.adopt() } },
            startCheck: { flow.startLightingCheck() },
            dartPlanted: { Task { await flow.captureCheckStill() } })
    }

    private func finish() {
        flow.close()
        onFinish()
    }
}

extension CalibrationContentModel {
    /// The content of a running flow.
    @MainActor
    init(flow: CalibrationFlowModel) {
        let checking: Bool
        switch flow.stage {
        case .checkTap, .checking, .checkResult: checking = true
        default: checking = false
        }
        let picture = checking ? flow.checkPicture : flow.picture
        let stillBased: Bool
        switch flow.stage {
        case .adjusting, .validating, .touchTwenty, .proof, .adopted, .checkTap, .checking, .checkResult: stillBased = true
        default: stillBased = false
        }
        let shownCalibration = flow.result ?? flow.preview
        self.init(stage: flow.stage,
                  picture: stillBased ? picture : nil,
                  imageSize: flow.still?.size,
                  preview: flow.camera.service.preview,
                  rotationDegrees: flow.camera.service.frameInfo?.rotationDegrees ?? 0,
                  handles: flow.handles,
                  wireframe: shownCalibration?.wireframe(ringSegments: 96),
                  issues: flow.issues,
                  canValidate: flow.canValidate,
                  quality: flow.result?.quality,
                  rectified: flow.rectified,
                  tappedHit: flow.tappedHit,
                  checkTip: flow.checkTip)
    }
}
