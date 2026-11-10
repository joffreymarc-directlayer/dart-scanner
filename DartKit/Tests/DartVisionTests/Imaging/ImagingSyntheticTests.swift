import Foundation
import simd
import Testing
import DartCore
@testable import DartVision

/// The synthetic renderer of VISION.md §10.1 against an independent reference built on DartCore's
/// `BoardGeometry` and on the calibration's homography: the only ground truth of the camera pipeline.
@Suite struct ImagingSyntheticTests {
    /// Colours of VISION.md §10.1.
    private static let wall = SIMD3<UInt8>(120, 120, 125), numberRing = SIMD3<UInt8>(25, 25, 25)
    private static let black = SIMD3<UInt8>(30, 30, 30), cream = SIMD3<UInt8>(225, 205, 165)
    private static let red = SIMD3<UInt8>(200, 40, 40), green = SIMD3<UInt8>(30, 140, 70)
    private static let wire = SIMD3<UInt8>(190, 190, 190)

    /// The colour of a board point, written from VISION.md §3.3 and §10.1 with DartCore's scoring: a point on one of
    /// the six ring wires or the twenty radial wires (1.4 mm wide) is grey; otherwise the bed that
    /// `BoardGeometry.standard.hit(at:)` gives, coloured by the parity of its sector; off the scoring area the number
    /// ring up to 225.5 mm, then the wall. `wirePoint` is where the ray crosses the wire plane (the same point when
    /// the wires lie in the board plane). Also returns the distance to the nearest place where the answer changes.
    private static func reference(board point: BoardPoint, wirePoint: BoardPoint? = nil,
                                  radii: RingRadii = .nominal) -> (colour: SIMD3<UInt8>, margin: Double) {
        let onWires = wirePoint ?? point
        let rw = hypot(onWires.x, onWires.y)
        var margin = Double.infinity
        var isWire = false
        for radius in [radii.innerBull, radii.outerBull, radii.trebleInner, radii.trebleOuter, radii.doubleInner, radii.doubleOuter] {
            let distance = abs(rw - radius)
            margin = min(margin, abs(distance - 0.7))
            if distance <= 0.7 { isWire = true }
        }
        if rw >= radii.outerBull && rw <= radii.doubleOuter {
            for m in 0..<10 {
                let distance = abs(BoardModel.signedDistanceToWire(m, onWires))
                margin = min(margin, abs(distance - 0.7))
                if distance <= 0.7 { isWire = true }
            }
        }
        let r = hypot(point.x, point.y)
        margin = min(margin, abs(r - 225.5))
        if isWire { return (wire, margin) }
        let nominal = radii.toNominal(point)
        let hit = BoardGeometry.standard.hit(at: nominal)
        if hit == .miss { return (r <= 225.5 ? numberRing : wall, margin) }
        let light = BoardGeometry.standard.sectorIndex(at: nominal) % 2 == 1
        switch hit.bed {
        case .innerBull: return (red, margin)
        case .outerBull: return (green, margin)
        case .single: return (light ? cream : black, margin)
        case .double, .treble: return (light ? green : red, margin)
        case .miss: return (wall, margin)
        }
    }

    /// Reference value of camera pixel `(x, y)`: the nine rays at ±1/3 px, each read back on the board through
    /// G = H⁻¹, averaged and rounded like the renderer. Nil when a sample lies within 1e-6 mm of an edge.
    private static func referencePixel(x: Int, y: Int, imageToBoard g: Homography) -> SIMD3<UInt8>? {
        var sum = SIMD3<Int>(0, 0, 0)
        for j in -1...1 {
            for i in -1...1 {
                let p = g.apply(SIMD2(Double(x) + Double(i) / 3, Double(y) + Double(j) / 3))
                let sample = reference(board: BoardPoint(x: p.x, y: p.y))
                guard sample.margin > 1e-6 else { return nil }
                sum &+= SIMD3<Int>(Int(sample.colour.x), Int(sample.colour.y), Int(sample.colour.z))
            }
        }
        return SIMD3(UInt8((sum.x + 4) / 9), UInt8((sum.y + 4) / 9), UInt8((sum.z + 4) / 9))
    }

    // MARK: Board geometry

    @Test func renderer_cameraImageMatchesTheReferencePixelForPixel() throws {
        for pose in [SupportPoses.b, .a, .d] {
            let camera = pose.camera
            let image = SupportScenes.exact().render(camera: camera)
            let g = camera.calibration().imageToBoard
            let bull = camera.project(SIMD3(0, 0, 0))
            let t20 = camera.project(SIMD3(0, 103, 0)), d6 = camera.project(SIMD3(166, 0, 0)), edge = camera.project(SIMD3(-160, -160, 0))
            var pixels: [(Int, Int)] = []
            // Every pixel of four windows: the bulls, the treble 20, the double 6, the board edge.
            for centre in [bull, t20, d6, edge] {
                for y in (Int(centre.y) - 25)...(Int(centre.y) + 25) {
                    for x in (Int(centre.x) - 25)...(Int(centre.x) + 25) {
                        pixels.append((x, y))
                    }
                }
            }
            // And a sparse grid over the whole board.
            for y in stride(from: Int(bull.y) - 700, to: Int(bull.y) + 700, by: 7) {
                for x in stride(from: Int(bull.x) - 700, to: Int(bull.x) + 700, by: 7) {
                    pixels.append((x, y))
                }
            }
            var compared = 0, mismatches = 0
            for (x, y) in pixels where x >= 0 && y >= 0 && x < camera.imageSize.width && y < camera.imageSize.height {
                guard let expected = Self.referencePixel(x: x, y: y, imageToBoard: g) else { continue }
                compared += 1
                if image[x, y] != expected {
                    mismatches += 1
                    if mismatches <= 5 {
                        Issue.record("\(pose) pixel (\(x), \(y)): rendered \(image[x, y]), reference \(expected)")
                    }
                }
            }
            #expect(compared > 15_000, "\(pose): \(compared) pixels compared")
            #expect(mismatches == 0, "\(pose): \(mismatches) of \(compared) pixels differ")
        }
    }

    @Test func renderer_canvasMatchesBoardGeometryEverywhere() {
        for camera in [SupportPoses.a.camera, SupportPoses.d.camera] {
            let canvas = SupportScenes.exact().renderCanvas(camera: camera)
            var compared = 0, mismatches = 0
            for y in stride(from: 0, to: BoardCanvas.side, by: 2) {
                for x in stride(from: 1, to: BoardCanvas.side, by: 2) where canvas.valid[x, y] != 0 {
                    let expected = Self.reference(board: BoardCanvas.boardPoint(x: Double(x), y: Double(y)))
                    guard expected.margin > 1e-6 else { continue }
                    compared += 1
                    if canvas.rgb[x, y] != expected.colour {
                        mismatches += 1
                        if mismatches <= 5 { Issue.record("canvas (\(x), \(y)): \(canvas.rgb[x, y]) instead of \(expected.colour)") }
                    }
                }
            }
            #expect(compared > 150_000 && mismatches == 0, "\(mismatches) of \(compared)")
            // Outside the region of interest the canvas is black and invalid; the rectifier's mask decides.
            var invalidColoured = 0
            for index in 0..<canvas.valid.pixels.count where canvas.valid.pixels[index] == 0 {
                if canvas.rgb.pixels[index * 3] != 0 || canvas.rgb.pixels[index * 3 + 1] != 0 || canvas.rgb.pixels[index * 3 + 2] != 0 {
                    invalidColoured += 1
                }
            }
            #expect(invalidColoured == 0)
            let rectifierMask = BoardRectifier(calibration: camera.calibration()).regionOfInterest.makeImage()
            let sameMask = canvas.valid == rectifierMask
            #expect(sameMask)
        }
    }

    @Test func renderer_wirePositionsToAFractionOfAPixel() throws {
        // Down image columns through the top of the board, the grey of the outer double wire (r = 170 ± 0.7 mm)
        // covers the fraction of each pixel that the projection predicts. Below the wire is the red double of the
        // 20 (green channel 40), above it the black number ring (25); the wire is 190.
        let camera = SupportPoses.a.camera
        let image = SupportScenes.exact().render(camera: camera)
        let g = camera.calibration().imageToBoard
        let top = camera.project(SIMD3(0, 170, 0))
        var widthErrors: [Double] = [], centreErrors: [Double] = []
        for column in (Int(top.x) - 30)...(Int(top.x) + 30) {
            func boardRadius(atRow y: Double) -> Double {
                let p = g.apply(SIMD2(Double(column), y))
                return hypot(p.x, p.y)
            }
            // Rows where this column crosses r = 170.7 and r = 169.3 (the radius falls as the row grows).
            func row(ofRadius target: Double) -> Double {
                var low = top.y - 20, high = top.y + 20
                for _ in 0..<60 {
                    let middle = (low + high) / 2
                    if boardRadius(atRow: middle) > target { low = middle } else { high = middle }
                }
                return (low + high) / 2
            }
            let outer = row(ofRadius: 170.7), inner = row(ofRadius: 169.3)
            var covered = 0.0, moment = 0.0
            for y in (Int(top.y) - 10)...(Int(top.y) + 10) {
                let green = Double(image[column, y].y)
                let outside = boardRadius(atRow: Double(y)) > 170 ? 25.0 : 40.0
                let coverage = max(0, min(1, (green - outside) / (190 - outside)))
                covered += coverage
                moment += coverage * Double(y)
            }
            widthErrors.append(covered - (inner - outer))
            centreErrors.append(moment / covered - (inner + outer) / 2)
        }
        // Three rows of samples per pixel: one column is right to a third of a pixel; the mean over 61 columns,
        // whose sampling phases differ, is right to a few hundredths.
        let meanWidth = widthErrors.reduce(0, +) / Double(widthErrors.count)
        let meanCentre = centreErrors.reduce(0, +) / Double(centreErrors.count)
        #expect(widthErrors.allSatisfy { abs($0) <= 0.34 } && centreErrors.allSatisfy { abs($0) <= 0.17 })
        #expect(abs(meanWidth) < 0.05 && abs(meanCentre) < 0.05, "mean width error \(meanWidth), mean centre error \(meanCentre)")
    }

    @Test func renderer_offNominalRadiiAndRaisedWires() {
        let camera = SupportPoses.a.camera
        // A board whose treble is at 98 / 106.5 mm.
        var scene = SupportScenes.exact()
        scene.radii = RingRadii(innerBull: 6.35, outerBull: 15.9, trebleInner: 98, trebleOuter: 106.5, doubleInner: 162, doubleOuter: 170)
        let canvas = scene.renderCanvas(camera: camera)
        var mismatches = 0, compared = 0
        for y in stride(from: 300, to: 980, by: 3) {
            for x in stride(from: 300, to: 980, by: 3) where canvas.valid[x, y] != 0 {
                let expected = Self.reference(board: BoardCanvas.boardPoint(x: Double(x), y: Double(y)), radii: scene.radii)
                guard expected.margin > 1e-6 else { continue }
                compared += 1
                if canvas.rgb[x, y] != expected.colour { mismatches += 1 }
            }
        }
        #expect(compared > 30_000 && mismatches == 0, "\(mismatches) of \(compared)")
        // At r = 98.85 on the 20: treble red on this board, single black on a nominal one.
        let pixel = BoardCanvas.pixel(for: BoardPoint(x: 0, y: 98.85))
        #expect(canvas.rgb[Int(pixel.x), Int(pixel.y.rounded())] == Self.red)
        // On a nominal board the same point is under the treble wire (99 ± 0.7 mm).
        #expect(SupportScenes.exact().renderCanvas(camera: camera).rgb[Int(pixel.x), Int(pixel.y.rounded())] == Self.wire)

        // Wires raised by 1 mm: a ray meets them at the wire plane, where it is closer to the camera foot point.
        var raised = SupportScenes.exact()
        raised.wireHeight = 1
        let lifted = raised.renderCanvas(camera: camera)
        let c = camera.position
        mismatches = 0
        compared = 0
        for y in stride(from: 300, to: 980, by: 3) {
            for x in stride(from: 300, to: 980, by: 3) where lifted.valid[x, y] != 0 {
                let p = BoardCanvas.boardPoint(x: Double(x), y: Double(y))
                // The ray from the camera centre to p crosses z = 1 at p + (C − p)·(1 / C.z).
                let crossing = BoardPoint(x: p.x + (c.x - p.x) / c.z, y: p.y + (c.y - p.y) / c.z)
                let expected = Self.reference(board: p, wirePoint: crossing)
                guard expected.margin > 1e-6 else { continue }
                compared += 1
                if lifted.rgb[x, y] != expected.colour { mismatches += 1 }
            }
        }
        #expect(compared > 30_000 && mismatches == 0, "raised wires: \(mismatches) of \(compared)")
    }

    @Test func renderer_raisedWiresHideTheFootOfADart() {
        // A dart planted just outside the treble wire (107 ± 0.7 mm), the wires 1 mm above the board. Seen from
        // below, the foot of the point is behind the raised wire: a ray that meets the wire before the point shows
        // the wire, one that meets the point first shows the point.
        let camera = SupportPoses.a.camera
        var scene = SupportScenes.exact()
        scene.wireHeight = 1
        let dart = SyntheticDart(tip: BoardPoint(x: 0, y: 108.2), leanUpDegrees: 0)
        scene.darts = [dart]
        let canvas = scene.renderCanvas(camera: camera)
        let solid = dart.solid()
        let c = camera.position
        var wiresInFront = 0, pointInFront = 0, mismatches = 0
        let centre = BoardCanvas.pixel(for: dart.tip)
        for y in (Int(centre.y) - 8)...(Int(centre.y) + 8) {
            for x in (Int(centre.x) - 8)...(Int(centre.x) + 8) where canvas.valid[x, y] != 0 {
                let p = BoardCanvas.boardPoint(x: Double(x), y: Double(y))
                let d = SIMD3(p.x - c.x, p.y - c.y, -c.z)
                var part: UInt32 = 0
                let dartHit = solid.hitBody(px: c.x, py: c.y, pz: c.z, dx: d.x, dy: d.y, dz: d.z, limit: 1, colour: &part)
                let tWire = (1 - c.z) / d.z
                let crossing = BoardPoint(x: c.x + tWire * d.x, y: c.y + tWire * d.y)
                let wire = Self.reference(board: p, wirePoint: crossing)
                guard wire.margin > 1e-6, dartHit < 0 || abs(dartHit - tWire) > 1e-9 else { continue }
                let expected: SIMD3<UInt8>
                if wire.colour == Self.wire && (dartHit < 0 || tWire < dartHit) {
                    expected = Self.wire
                    if dartHit >= 0 { wiresInFront += 1 }
                } else if dartHit >= 0 {
                    expected = SyntheticDartStyle.steelTungsten.point
                    if wire.colour == Self.wire { pointInFront += 1 }
                } else {
                    expected = wire.colour
                }
                if canvas.rgb[x, y] != expected { mismatches += 1 }
            }
        }
        #expect(wiresInFront > 0 && pointInFront > 0 && mismatches == 0,
                "wire in front \(wiresInFront), point in front \(pointInFront), mismatches \(mismatches)")
    }

    // MARK: Darts, shadows, hand

    @Test func renderer_dartPartsOcclusionAndShadow() throws {
        let camera = SupportPoses.a.camera
        let style = SyntheticDartStyle.brass
        let dart = SyntheticDart(tip: BoardPoint(x: -40, y: 60), leanUpDegrees: 8, leanSideDegrees: 0, style: style)
        var scene = SupportScenes.exact()
        scene.darts = [dart]
        let image = scene.render(camera: camera)
        let axis = simd_normalize(SIMD3(0, tan(8 * Double.pi / 180), 1))
        let tip = SIMD3(-40.0, 60, 0)
        func pixel(along s: Double) -> SIMD3<UInt8> {
            let p = camera.project(tip + s * axis)
            return image[Int(p.x.rounded()), Int(p.y.rounded())]
        }
        // On the axis: the point (0 to 22 mm), the barrel (22 to 72), the shaft (72 to 115), the flight (110 to 150).
        #expect(pixel(along: 0.5) == style.point && pixel(along: 12) == style.point)
        #expect(pixel(along: 30) == style.barrel && pixel(along: 60) == style.barrel)
        #expect(pixel(along: 90) == style.shaft)
        #expect(pixel(along: 135) == style.flight)
        // Beside the point, outside its radius: the board.
        let beside = camera.project(tip + 10 * axis + SIMD3(4, 0, 0))
        #expect(image[Int(beside.x.rounded()), Int(beside.y.rounded())] != style.point)
        // The empty board is unchanged far from the dart.
        let empty = SupportScenes.exact().render(camera: camera)
        let far = camera.project(SIMD3(100, -100, 0))
        #expect(image[Int(far.x), Int(far.y)] == empty[Int(far.x), Int(far.y)])

        // Occlusion: a second dart in front of the first, nearer the camera, hides it where they overlap.
        let front = SyntheticDart(tip: BoardPoint(x: -40, y: 20), leanUpDegrees: 30, leanSideDegrees: 0, style: .allBlack)
        scene.darts = [dart, front]
        let both = scene.render(camera: camera)
        // The rays to the first dart's barrel cross the second dart (its barrel or its shaft) on the way.
        let black = SyntheticDartStyle.allBlack
        var hidden = 0, seenFirst = 0
        for s in stride(from: 25.0, through: 70, by: 1) {
            let p = camera.project(tip + s * axis)
            let x = Int(p.x.rounded()), y = Int(p.y.rounded())
            if both[x, y] == black.barrel || both[x, y] == black.shaft { hidden += 1 }
            if both[x, y] == style.barrel { seenFirst += 1 }
        }
        // About s = 60 to 70 behind the second dart, 25 to 57 in view (the rest are mixed pixels at the transitions).
        #expect(hidden >= 8 && seenFirst >= 25, "hidden \(hidden), seen \(seenFirst)")
        #expect(image[Int(camera.project(tip + 50 * axis).x.rounded()), Int(camera.project(tip + 50 * axis).y.rounded())] == style.barrel)
        // The order of the darts in the scene does not matter, even where they interpenetrate.
        scene.darts = [front, dart]
        let swapped = scene.render(camera: camera) == both
        #expect(swapped)

        // Shadow: the board point behind the barrel, seen from the lamp, is darkened by the shadow strength.
        var shaded = SupportScenes.exact()
        shaded.darts = [dart]
        let lamp = SIMD3(300.0, 900, 1400)
        shaded.light = lamp
        shaded.shadowStrength = 0.5
        let canvas = shaded.renderCanvas(camera: camera)
        let plain = SupportScenes.exact().renderCanvas(camera: camera)
        let onAxis = tip + 50 * axis
        let ground = lamp + (onAxis - lamp) * (lamp.z / (lamp.z - onAxis.z))
        let spot = BoardCanvas.pixel(for: BoardPoint(x: ground.x, y: ground.y))
        let lit = plain.rgb[Int(spot.x.rounded()), Int(spot.y.rounded())]
        let dark = canvas.rgb[Int(spot.x.rounded()), Int(spot.y.rounded())]
        for (l, d, tint) in [(lit.x, dark.x, 0.97), (lit.y, dark.y, 1.0), (lit.z, dark.z, 1.04)] {
            #expect(Int(d) == Int((Double(l) * 0.5 * tint).rounded()), "lit \(lit), shadow \(dark)")
        }
        // No lamp, or a strength of 1: no shadow at all.
        shaded.shadowStrength = 1
        let noShadow = shaded.renderCanvas(camera: camera)
        #expect(noShadow.rgb[Int(spot.x.rounded()), Int(spot.y.rounded())] == lit)
    }

    @Test func renderer_handAboveTheBoard() {
        let camera = SupportPoses.b.camera
        var scene = SupportScenes.exact()
        scene.hand = (centre: BoardPoint(x: 30, y: -20), radius: 50)
        let image = scene.render(camera: camera)
        let skin = SIMD3<UInt8>(210, 160, 130)
        // The disc is 60 mm above the board: its centre is where (30, −20, 60) projects.
        let centre = camera.project(SIMD3(30, -20, 60))
        #expect(image[Int(centre.x), Int(centre.y)] == skin)
        let rim = camera.project(SIMD3(30 + 45, -20, 60)), outside = camera.project(SIMD3(30 + 56, -20, 60))
        #expect(image[Int(rim.x), Int(rim.y)] == skin && image[Int(outside.x), Int(outside.y)] != skin)
        let canvas = scene.renderCanvas(camera: camera)
        // In the canvas the hand appears enlarged and pushed away from the camera foot point.
        let c = camera.position
        let k = c.z / (c.z - 60)
        let seen = BoardPoint(x: c.x + (30 - c.x) * k, y: c.y + (-20 - c.y) * k)
        let p = BoardCanvas.pixel(for: seen)
        #expect(canvas.rgb[Int(p.x.rounded()), Int(p.y.rounded())] == skin)
    }

    // MARK: Nuisances

    @Test func renderer_noiseGainBlurAndShift() throws {
        let camera = SupportPoses.b.camera
        let exact = SupportScenes.exact().render(camera: camera)
        // Noise: σ = 2 levels, zero mean, seeded.
        var noisy = SupportScenes.exact()
        noisy.noiseSigma = 2
        noisy.seed = 99
        let a = noisy.render(camera: camera)
        let repeated = a == noisy.render(camera: camera)
        #expect(repeated)
        noisy.seed = 100
        let b = noisy.render(camera: camera)
        let differs = a != b
        #expect(differs)
        var sum = 0.0, squares = 0.0
        for index in stride(from: 0, to: a.pixels.count, by: 7) {
            let difference = Double(a.pixels[index]) - Double(exact.pixels[index])
            sum += difference
            squares += difference * difference
        }
        let count = Double((a.pixels.count + 6) / 7)
        #expect(abs(sum / count) < 0.05 && abs((squares / count).squareRoot() - 2) < 0.1)
        // Gain: every level multiplied, then rounded.
        var darker = SupportScenes.exact()
        darker.gain = 0.9
        let dim = darker.render(camera: camera)
        #expect(dim[0, 0] == SIMD3(108, 108, 113) && exact[0, 0] == Self.wall)
        darker.gain = 1.5
        #expect(darker.render(camera: camera)[0, 0] == SIMD3(180, 180, 188))
        // A blur pass mixes the colours across an edge, and leaves flat areas alone.
        var blurred = SupportScenes.exact()
        blurred.blurPasses = 1
        let soft = blurred.render(camera: camera)
        #expect(soft[0, 0] == exact[0, 0])
        var mixed = 0
        for index in 0..<soft.pixels.count where soft.pixels[index] != exact.pixels[index] {
            mixed += 1
        }
        #expect(mixed > 1000)
        // A whole-pixel shift moves the content.
        var moved = SupportScenes.exact()
        moved.shift = SIMD2(3, -2)
        let shifted = moved.render(camera: camera)
        let bull = camera.project(SIMD3(0, 0, 0))
        for (x, y) in [(Int(bull.x), Int(bull.y)), (Int(bull.x) + 40, Int(bull.y) - 13), (Int(bull.x) - 200, Int(bull.y) + 77)] {
            #expect(shifted[x + 3, y - 2] == exact[x, y])
        }
        // A half-pixel shift averages two neighbours.
        moved.shift = SIMD2(0.5, 0)
        let half = moved.render(camera: camera)
        let x = Int(bull.x) + 100, y = Int(bull.y)
        let expected = (Int(exact[x - 1, y].x) + Int(exact[x, y].x) + 1) / 2
        #expect(abs(Int(half[x, y].x) - expected) <= 1)
    }

    @Test func renderer_isDeterministicAndHandlesOddCameras() {
        let camera = SupportPoses.c.camera(longSide: 1280)
        var random = SupportRandom(seed: 0x5EED)
        var scene = SupportScenes.darts([SupportScenes.randomDart(&random), SupportScenes.randomDart(&random)], seed: 5)
        scene.light = SupportScenes.lampOpposite(to: camera)
        scene.shadowStrength = 0.6
        scene.shift = SIMD2(0.3, -0.4)
        scene.gain = 1.05
        scene.hand = (centre: BoardPoint(x: 120, y: 160), radius: 40)
        let sameImage = scene.render(camera: camera) == scene.render(camera: camera)
        let sameCanvas = scene.renderCanvas(camera: camera).rgb == scene.renderCanvas(camera: camera).rgb
        #expect(sameImage && sameCanvas)
        // Looking away from the board: wall only. A zero-sized image: no pixel. A camera behind the board: wall.
        let away = SyntheticCamera(imageSize: PixelSize(width: 64, height: 48), position: SIMD3(0, 0, 1000), lookAt: BoardPoint(x: 5000, y: 0))
        let wallOnly = SupportScenes.exact().render(camera: away)
        #expect(wallOnly.pixels.count == 64 * 48 * 3 && Set(stride(from: 0, to: wallOnly.pixels.count, by: 3).map { wallOnly.pixels[$0] }) == [120])
        #expect(SupportScenes.exact().render(camera: SyntheticCamera(imageSize: PixelSize(width: 0, height: 0), position: SIMD3(0, 0, 1000))).pixels.isEmpty)
        let behind = SyntheticCamera(imageSize: PixelSize(width: 32, height: 32), position: SIMD3(0, 0, -500), lookAt: BoardPoint(x: 0, y: 0))
        let back = SupportScenes.exact().render(camera: behind)
        #expect(back.pixels.count == 32 * 32 * 3)
        // Non-finite settings are ignored rather than trapping.
        var odd = SupportScenes.empty()
        odd.shift = SIMD2(.nan, 1)
        odd.gain = .infinity
        odd.noiseSigma = -3
        odd.blurPasses = -2
        odd.shadowStrength = .nan
        odd.light = SIMD3(.nan, 0, 1000)
        odd.wireHeight = .infinity
        odd.hand = (centre: BoardPoint(x: .nan, y: 0), radius: 10)
        let small = SupportPoses.b.camera(longSide: 320)
        #expect(odd.render(camera: small).pixels.count == small.imageSize.width * small.imageSize.height * 3)
        #expect(odd.renderCanvas(camera: small).rgb.width == BoardCanvas.side)
    }
}
