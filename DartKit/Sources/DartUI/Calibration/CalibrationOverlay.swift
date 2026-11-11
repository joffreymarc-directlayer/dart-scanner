import SwiftUI
import DartCore
import DartVision

/// The wireframe of a calibration over its image, the four handles and the 4× loupe (VISION.md §4.4, §4.7):
/// shared by the calibration flow and by the calibration of a single photo. Everything is in image pixels and
/// placed with `fit`. Drawn with `Canvas` and shapes, so it renders under `ImageRenderer`.
struct CalibrationOverlay: View {
    let wireframe: BoardWireframe?
    let handles: CalibrationHandles?
    let fit: CameraImageFit
    /// The image under the overlay, magnified in the loupe while a handle moves.
    var still: CGImage?
    /// Draws the region that must stay in view (board and dart margin), dashed.
    var showsSafeFrame = false
    /// Moves a handle (the finger keeps its offset to the handle it grabbed).
    var onMove: ((CalibrationHandle, ImagePoint) -> Void)?
    /// A touch that grabbed no handle (touch the 20, tap test, tap a tip).
    var onTap: ((ImagePoint) -> Void)?

    @State private var isDragging = false
    @State private var grabbed: CalibrationHandle?
    @State private var grabOffset: CGSize = .zero
    @State private var loupeCentre: ImagePoint?

    var body: some View {
        ZStack(alignment: .topLeading) {
            Canvas { context, _ in
                draw(in: &context)
            }
            .frame(width: fit.viewSize.width, height: fit.viewSize.height)
            numberLabels
            handleRings
            if let loupeCentre, let still {
                CalibrationLoupe(still: still, centre: loupeCentre, fit: fit)
            }
        }
        .frame(width: fit.viewSize.width, height: fit.viewSize.height)
        .contentShape(Rectangle())
        .gesture(drag, including: onMove == nil && onTap == nil ? .none : .all)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.text("calibration.overlay.label", .camera))
    }

    // MARK: Drawing

    private func draw(in context: inout GraphicsContext) {
        guard let wireframe else { return }
        let accent = Theme.Palette.accent
        if showsSafeFrame, wireframe.safeFrame.count > 2 {
            context.stroke(path(wireframe.safeFrame), with: .color(Theme.Palette.textPrimary.opacity(0.7)),
                           style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
        }
        for (index, ring) in wireframe.rings.enumerated() {
            let outer = index == wireframe.rings.count - 1
            context.stroke(path(ring), with: .color(accent), lineWidth: outer ? 2 : 1.5)
        }
        for wire in wireframe.wires where wire.count == 2 {
            context.stroke(path(wire), with: .color(accent), lineWidth: 1)
        }
    }

    private func path(_ points: [ImagePoint]) -> Path {
        var path = Path()
        for (index, point) in points.enumerated() where point.x.isFinite && point.y.isFinite {
            let p = fit.viewPoint(point)
            if index == 0 { path.move(to: p) } else { path.addLine(to: p) }
        }
        return path
    }

    @ViewBuilder
    private var numberLabels: some View {
        if let wireframe {
            ForEach(wireframe.numberAnchors.indices, id: \.self) { index in
                let anchor = wireframe.numberAnchors[index]
                if anchor.point.x.isFinite, anchor.point.y.isFinite {
                    Text(verbatim: "\(anchor.number)")
                        .font(CameraStyle.wireNumber)
                        .foregroundStyle(Theme.Palette.onAccent)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Theme.Palette.accent, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .fixedSize()
                        .position(fit.viewPoint(anchor.point))
                }
            }
        }
    }

    @ViewBuilder
    private var handleRings: some View {
        if let handles {
            ForEach(CalibrationHandle.allCases, id: \.rawValue) { handle in
                let point = handles[handle]
                if point.x.isFinite, point.y.isFinite {
                    Circle()
                        .fill(Theme.Palette.background.opacity(grabbed == handle ? 0.2 : 0.5))
                        .overlay {
                            Circle().strokeBorder(grabbed == handle ? Theme.Palette.accent : Theme.Palette.textPrimary,
                                                  lineWidth: 3)
                        }
                        .frame(width: CameraStyle.handle, height: CameraStyle.handle)
                        .position(fit.viewPoint(point))
                }
            }
        }
    }

    // MARK: Gestures

    private var drag: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                if !isDragging {
                    // The handle is chosen once, where the finger came down.
                    isDragging = true
                    if onMove != nil, let (handle, point) = nearestHandle(to: value.startLocation) {
                        grabbed = handle
                        grabOffset = CGSize(width: point.x - value.startLocation.x, height: point.y - value.startLocation.y)
                    }
                }
                guard let handle = grabbed, let onMove else { return }
                let location = CGPoint(x: value.location.x + grabOffset.width, y: value.location.y + grabOffset.height)
                let point = fit.imagePoint(location)
                loupeCentre = point
                onMove(handle, point)
            }
            .onEnded { value in
                defer {
                    grabbed = nil
                    loupeCentre = nil
                    isDragging = false
                }
                guard grabbed == nil else { return }
                let moved = hypot(value.translation.width, value.translation.height)
                if moved < 12, let onTap {
                    onTap(fit.imagePoint(value.location))
                }
            }
    }

    /// The handle under the finger: the nearest one within a touch target.
    private func nearestHandle(to location: CGPoint) -> (CalibrationHandle, CGPoint)? {
        guard let handles else { return nil }
        var best: (CalibrationHandle, CGPoint, CGFloat)?
        for handle in CalibrationHandle.allCases {
            let point = handles[handle]
            guard point.x.isFinite, point.y.isFinite else { continue }
            let view = fit.viewPoint(point)
            let distance = hypot(view.x - location.x, view.y - location.y)
            if distance <= Theme.Control.touchTarget, distance < (best?.2 ?? .infinity) {
                best = (handle, view, distance)
            }
        }
        return best.map { ($0.0, $0.1) }
    }
}

/// The 4× loupe above the finger: the still around `centre`, with a cross on the exact point.
private struct CalibrationLoupe: View {
    let still: CGImage
    let centre: ImagePoint
    let fit: CameraImageFit

    var body: some View {
        let side = CameraStyle.loupe
        let zoom = fit.scale * CameraStyle.loupeZoom
        let width = CGFloat(still.width) * zoom, height = CGFloat(still.height) * zoom
        // The centre of the loupe shows `centre`: the image is shifted so that this point lands in the middle.
        let dx = side / 2 - (CGFloat(centre.x) + 0.5) * zoom
        let dy = side / 2 - (CGFloat(centre.y) + 0.5) * zoom
        let anchor = fit.viewPoint(centre)
        let above = anchor.y - side / 2 - 48
        let y = above < side / 2 ? anchor.y + side / 2 + 48 : above
        let x = min(max(anchor.x, side / 2), max(side / 2, fit.viewSize.width - side / 2))
        ZStack(alignment: .topLeading) {
            Image(decorative: still, scale: 1)
                .resizable()
                .interpolation(.none)
                .frame(width: width, height: height)
                .offset(x: dx, y: dy)
            Path { path in
                path.move(to: CGPoint(x: side / 2 - 12, y: side / 2))
                path.addLine(to: CGPoint(x: side / 2 + 12, y: side / 2))
                path.move(to: CGPoint(x: side / 2, y: side / 2 - 12))
                path.addLine(to: CGPoint(x: side / 2, y: side / 2 + 12))
            }
            .stroke(Theme.Palette.accent, lineWidth: 1.5)
        }
        .frame(width: side, height: side, alignment: .topLeading)
        .clipShape(Circle())
        .overlay { Circle().strokeBorder(Theme.Palette.textPrimary, lineWidth: 3) }
        .position(x: x, y: y)
        .allowsHitTesting(false)
    }
}
