import SwiftUI
import DartCore
#if os(iOS)
import UIKit
import AVFoundation
#endif

/// What the camera shows (ARCHITECTURE.md §8.7, "Aperçu"). One of the three files of DartUI allowed to contain
/// `#if os(iOS)` (§8.8): on iOS a live session is an `AVCaptureVideoPreviewLayer`; a still, a synthetic frame
/// (Simulator, macOS, SnapshotTool) or a photo is an `Image`. Overlays are drawn in image pixels and placed with
/// `CameraImageFit`, which reproduces the gravity of the layer.
///
/// The layer keeps the rotation of the delivered frames (`FrameSourceInfo.rotationDegrees`): the frames, the
/// calibration and the overlays then share one orientation. A turn of the device while the session runs pauses
/// the vision and asks for a new calibration anyway (§6.5, point 1).
struct CameraPreviewView: View {
    let content: PreviewContent
    /// Rotation of the delivered frames, degrees.
    var rotationDegrees: Int = 0
    /// Aspect fill (live scan, thumbnail) or aspect fit (calibration, taps on a photo).
    var fills: Bool = true

    var body: some View {
        switch content {
        case .image(let image):
            Image(decorative: image, scale: 1)
                .resizable()
                .interpolation(.medium)
                .aspectRatio(contentMode: fills ? .fill : .fit)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                .accessibilityHidden(true)
        #if canImport(AVFoundation)
        #if os(iOS)
        case .captureSession(let session):
            CameraCaptureLayerView(session: session, rotationDegrees: rotationDegrees, fills: fills)
                .accessibilityHidden(true)
        #else
        case .captureSession:
            // No capture layer outside iOS: the demonstration source gives `.image` there.
            Theme.Palette.surface
                .accessibilityHidden(true)
        #endif
        #endif
        case .none:
            Theme.Palette.surface
                .accessibilityHidden(true)
        }
    }
}

#if os(iOS)
/// A view whose layer is the preview layer of the capture session.
private final class CameraCaptureLayerHost: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

    var previewLayer: AVCaptureVideoPreviewLayer? { layer as? AVCaptureVideoPreviewLayer }
}

private struct CameraCaptureLayerView: UIViewRepresentable {
    let session: AVCaptureSession
    let rotationDegrees: Int
    let fills: Bool

    func makeUIView(context: Context) -> CameraCaptureLayerHost {
        let host = CameraCaptureLayerHost()
        host.backgroundColor = .clear
        host.previewLayer?.session = session
        apply(to: host)
        return host
    }

    func updateUIView(_ host: CameraCaptureLayerHost, context: Context) {
        if host.previewLayer?.session !== session { host.previewLayer?.session = session }
        apply(to: host)
    }

    private func apply(to host: CameraCaptureLayerHost) {
        guard let layer = host.previewLayer else { return }
        layer.videoGravity = fills ? .resizeAspectFill : .resizeAspect
        let angle = CGFloat(rotationDegrees)
        if let connection = layer.connection, connection.isVideoRotationAngleSupported(angle),
           connection.videoRotationAngle != angle {
            connection.videoRotationAngle = angle
        }
    }
}
#endif
