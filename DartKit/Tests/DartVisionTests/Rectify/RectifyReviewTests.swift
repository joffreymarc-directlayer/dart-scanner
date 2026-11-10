import Foundation
import simd
import Testing
import DartCore
@testable import DartVision

/// Adversarial review of lot V1 (renderer and rectifier): the wires of the rendered board are found where
/// DartCore's `BoardGeometry` puts them, first in the camera image through a pinhole written from VISION.md §10.1,
/// then in the canvas that `BoardRectifier` makes of that image (VISION.md §3.4, R1: half a canvas pixel).
@Suite struct RectifyReviewTests {
    /// Image position of a board point (z = 0), from the formulas of VISION.md §3.1 and §10.1 only.
    private static func project(_ point: SIMD2<Double>, camera: SyntheticCamera) -> SIMD2<Double> {
        project(SIMD3(point.x, point.y, 0), camera: camera)
    }

    /// Image position of a point of the board frame, from the formulas of VISION.md §3.1 and §10.1 only.
    private static func project(_ point: SIMD3<Double>, camera: SyntheticCamera) -> SIMD2<Double> {
        let size = camera.imageSize
        let c = camera.position
        let forward = simd_normalize(SIMD3(camera.lookAt.x, camera.lookAt.y, 0) - c)
        let right = simd_normalize(simd_cross(forward, SIMD3(0, 1, 0)))
        let down = simd_cross(forward, right)
        let f = Double(max(size.width, size.height)) / 2 / tan(67.0 / 2 * .pi / 180)
        let q = point - c
        let z = simd_dot(forward, q)
        return SIMD2(f * simd_dot(right, q) / z + Double(size.width - 1) / 2, f * simd_dot(down, q) / z + Double(size.height - 1) / 2)
    }

    /// Smallest channel: the grey wire (190) stands out of the dark sectors (black 30, red 40, number ring 25).
    private static func level(_ colour: SIMD3<Float>?) -> Double? {
        guard let colour else { return nil }
        return Double(min(colour.x, colour.y, colour.z))
    }

    /// The two edges of the wire of radius `radius` along the ray at `angle` (radians, clockwise from +y), each
    /// where the profile crosses half-way between the wire and the bed on its side. Nil when the profile is unreadable.
    private static func wireEdges(radius: Double, angle: Double, read: (BoardPoint) -> Double?) -> (inner: Double, outer: Double)? {
        let step = 0.01, half = 2.5
        var profile: [(r: Double, v: Double)] = []
        var r = radius - half
        while r <= radius + half + 1e-9 {
            guard let v = read(BoardPoint(x: r * sin(angle), y: r * cos(angle))) else { return nil }
            profile.append((r, v))
            r += step
        }
        guard let first = profile.first, let last = profile.last else { return nil }
        let peak = profile.map(\.v).max() ?? 0
        guard peak > max(first.v, last.v) + 60 else { return nil }
        let innerLevel = (first.v + peak) / 2, outerLevel = (last.v + peak) / 2
        var inner: Double?
        for i in 1..<profile.count where profile[i - 1].v < innerLevel && profile[i].v >= innerLevel {
            let t = (innerLevel - profile[i - 1].v) / (profile[i].v - profile[i - 1].v)
            inner = profile[i - 1].r + t * step
            break
        }
        var outer: Double?
        for i in stride(from: profile.count - 1, to: 0, by: -1) where profile[i].v < outerLevel && profile[i - 1].v >= outerLevel {
            let t = (profile[i - 1].v - outerLevel) / (profile[i - 1].v - profile[i].v)
            outer = profile[i - 1].r + t * step
            break
        }
        guard let inner, let outer else { return nil }
        return (inner, outer)
    }

    private struct Errors {
        var centres: [Double] = []
        var widths: [Double] = []
        var mean: Double { centres.reduce(0, +) / Double(max(1, centres.count)) }
        var worst: Double { centres.map(abs).max() ?? .infinity }
        var rms: Double { (centres.map { $0 * $0 }.reduce(0, +) / Double(max(1, centres.count))).squareRoot() }
    }

    /// The four ring wires of the trebles and doubles, at the middle of the ten dark sectors (20, 18, 13, 10, 2, 3,
    /// 7, 8, 14, 12): the nearest radial wire is 9 degrees away.
    private static func measure(radii: RingRadii = .nominal, read: (BoardPoint) -> Double?) -> Errors {
        var errors = Errors()
        for k in stride(from: 0, to: 20, by: 2) {
            let angle = Double(k) * 18 * .pi / 180
            for radius in [radii.trebleInner, radii.trebleOuter, radii.doubleInner, radii.doubleOuter] {
                guard let edges = wireEdges(radius: radius, angle: angle, read: read) else {
                    errors.centres.append(.infinity)
                    continue
                }
                errors.centres.append((edges.inner + edges.outer) / 2 - radius)
                errors.widths.append(edges.outer - edges.inner)
            }
        }
        return errors
    }

    @Test func renderedWires_areWhereTheBoardGeometryPutsThem_inTheImageAndInTheCanvas() throws {
        for pose in SupportPoses.allCases {
            let camera = pose.camera
            let image = SupportScenes.exact().render(camera: camera)
            let inImage = Self.measure { point in
                let p = Self.project(SIMD2(point.x, point.y), camera: camera)
                return Self.level(image.sample(x: p.x, y: p.y))
            }
            // Tolerances in source pixels: a quarter of a pixel at worst, a tenth in RMS.
            let pixel = 1 / camera.calibration().quality.minPixelsPerMillimetre
            #expect(abs(inImage.mean) < 0.03 && inImage.rms < 0.1 * pixel && inImage.worst < 0.25 * pixel,
                    "\(pose) image: mean \(inImage.mean), rms \(inImage.rms), worst \(inImage.worst)")
            #expect(inImage.widths.allSatisfy { abs($0 - 1.4) < 0.25 }, "\(pose) widths \(inImage.widths)")

            let canvas = BoardRectifier(calibration: camera.calibration()).rectify(image)
            let inCanvas = Self.measure { point in
                // Canvas pixel of a metric point (VISION.md §3.4): i = (x + 320)·2 − 0.5, j = (320 − y)·2 − 0.5.
                let i = (point.x + 320) * 2 - 0.5, j = (320 - point.y) * 2 - 0.5
                guard canvas.valid[Int(i.rounded()), Int(j.rounded())] != 0 else { return nil }
                return Self.level(canvas.rgb.sample(x: i, y: j))
            }
            // R1: the board lands within half a canvas pixel (0.25 mm).
            #expect(abs(inCanvas.mean) < 0.05 && inCanvas.rms < max(0.05, 0.1 * pixel) && inCanvas.worst < 0.25,
                    "\(pose) canvas: mean \(inCanvas.mean), rms \(inCanvas.rms), worst \(inCanvas.worst)")
        }
    }

    @Test func renderedWires_offNominalRadiiAndRaisedWires() {
        // A board with its own radii (C7), and wires raised 1 mm above the sisal (C9): the wires are found where the
        // scene puts them, the raised ones in the plane z = 1 mm.
        let camera = SupportPoses.a.camera
        let pixel = 1 / camera.calibration().quality.minPixelsPerMillimetre
        var offNominal = SupportScenes.exact()
        offNominal.radii = RingRadii(innerBull: 6.35, outerBull: 15.9, trebleInner: 98, trebleOuter: 106.5, doubleInner: 161.5, doubleOuter: 170)
        let image = offNominal.render(camera: camera)
        let measured = Self.measure(radii: offNominal.radii) { point in
            let p = Self.project(SIMD2(point.x, point.y), camera: camera)
            return Self.level(image.sample(x: p.x, y: p.y))
        }
        #expect(abs(measured.mean) < 0.03 && measured.worst < 0.25 * pixel, "off-nominal: \(measured.centres)")
        var raised = SupportScenes.exact()
        raised.wireHeight = 1
        let raisedImage = raised.render(camera: camera)
        let inWirePlane = Self.measure { point in
            let p = Self.project(SIMD3(point.x, point.y, 1), camera: camera)
            return Self.level(raisedImage.sample(x: p.x, y: p.y))
        }
        #expect(abs(inWirePlane.mean) < 0.03 && inWirePlane.worst < 0.25 * pixel, "raised: \(inWirePlane.centres)")
        // Read in the board plane instead, the raised wires look pushed away from the camera foot point by
        // s·tan θ (VISION.md §4.2): 0.2 to 0.6 mm in pose A, never zero on average.
        let inBoardPlane = Self.measure { point in
            let p = Self.project(SIMD2(point.x, point.y), camera: camera)
            return Self.level(raisedImage.sample(x: p.x, y: p.y))
        }
        #expect(inBoardPlane.centres.map(abs).reduce(0, +) / Double(inBoardPlane.centres.count) > 0.15)
    }

    @Test func renderedDart_partsAlongItsAxis() {
        // Pose A, a dart tail-up by 8 degrees: along its axis the point (−8 to 22 mm), the barrel (to 72), the shaft
        // (to 115) and the flight (110 to 150), then the board again (VISION.md §10.1). Seen from below, the wider
        // barrel hides the last millimetres of the point (from about 16 mm on): exact occlusion, not an error.
        let camera = SupportPoses.a.camera
        var scene = SupportScenes.exact()
        let dart = SyntheticDart(tip: BoardPoint(x: 40, y: 60), leanUpDegrees: 8, style: .steelTungsten)
        scene.darts = [dart]
        let image = scene.render(camera: camera)
        let empty = SupportScenes.exact().render(camera: camera)
        let axis = simd_normalize(SIMD3(0, tan(8 * Double.pi / 180), 1))
        let style = SyntheticDartStyle.steelTungsten
        let expected: [(Double, SIMD3<UInt8>?)] = [(4, style.point), (9, style.point), (14, style.point), (19, style.barrel), (30, style.barrel),
                                                   (50, style.barrel), (66, style.barrel), (80, style.shaft), (100, style.shaft),
                                                   (125, style.flight), (145, style.flight), (165, nil), (190, nil)]
        for (distance, colour) in expected {
            let p = Self.project(SIMD3(40, 60, 0) + distance * axis, camera: camera)
            let x = Int(p.x.rounded()), y = Int(p.y.rounded())
            if let colour {
                #expect(image[x, y] == colour, "\(distance) mm: \(image[x, y])")
            } else {
                #expect(image[x, y] == empty[x, y], "\(distance) mm: \(image[x, y]) over \(empty[x, y])")
            }
        }
    }

    @Test func rectifier_invertsTheRendererAtTheBullAndAtTheHandles() throws {
        // The red inner bull, read back in the canvas: its centroid is the canvas centre.
        for pose in SupportPoses.allCases {
            let camera = pose.camera
            let canvas = BoardRectifier(calibration: camera.calibration()).rectify(SupportScenes.exact().render(camera: camera))
            var sum = SIMD2<Double>(0, 0), weight = 0.0
            for j in 620..<660 {
                for i in 620..<660 {
                    let c = canvas.rgb[i, j]
                    // Redness: red (200, 40, 40) against green (30, 140, 70) and the grey wire.
                    let w = max(0, Double(c.x) - Double(c.y) - 60)
                    sum += w * SIMD2(Double(i), Double(j))
                    weight += w
                }
            }
            let centroid = sum / weight
            // The bull centre is canvas position (639.5, 639.5).
            #expect(simd_length(centroid - SIMD2(639.5, 639.5)) < 0.5, "\(pose): \(centroid)")
        }
    }
}
