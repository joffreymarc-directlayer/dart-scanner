import Foundation
import simd
import Testing
import DartCore
@testable import DartVision

/// The shadow-tolerant evidence map and the mask (VISION.md §5.2, D2 and D3): tests E1 to E4 of §10.2.
@Suite struct DetectionEvidenceTests {
    /// The four board paints of VISION.md §10.1.
    private static let paints: [(name: String, colour: SIMD3<UInt8>)] = [
        ("black", SIMD3(30, 30, 30)), ("cream", SIMD3(225, 205, 165)), ("red", SIMD3(200, 40, 40)), ("green", SIMD3(30, 140, 70)),
    ]
    /// The tint the renderer gives to a shadow, multiplied by its strength (`SyntheticRayCaster.shadowTint`).
    private static let shadowTint = SIMD3<Double>(0.97, 1.0, 1.04)

    /// A whole canvas of one colour, valid everywhere, with the renderer's noise.
    private func canvas(_ colour: SIMD3<UInt8>, noise: Double = 2, seed: UInt64,
                        band: (rows: Range<Int>, colour: SIMD3<UInt8>)? = nil) -> CanvasImage {
        let side = BoardCanvas.side
        var rgb = RGBImage(width: side, height: side, fill: colour)
        if let band {
            for y in band.rows {
                for x in 0..<side {
                    rgb[x, y] = band.colour
                }
            }
        }
        SyntheticNoise.apply(to: &rgb.pixels, bytesPerRow: side * 3, gain: 1, sigma: noise, seed: seed)
        return CanvasImage(rgb: rgb, valid: GrayImage(width: side, height: side, fill: 255))
    }

    private func shadowed(_ colour: SIMD3<UInt8>, strength: Double) -> SIMD3<UInt8> {
        let factor = Self.shadowTint * strength
        func darken(_ value: UInt8, _ k: Double) -> UInt8 { UInt8(min(255, max(0, (Double(value) * k).rounded()))) }
        return SIMD3(darken(colour.x, factor.x), darken(colour.y, factor.y), darken(colour.z, factor.z))
    }

    /// Largest evidence over a band of rows of the canvas.
    private func largest(_ evidence: ChangeEvidence, rows: Range<Int>) -> Float {
        var result: Float = 0
        for y in rows {
            for x in 0..<evidence.side {
                result = max(result, evidence.value(x: x, y: y))
            }
        }
        return result
    }

    // MARK: E1

    /// E1: a shadow of strength 0.6 (with the renderer's tint) over each of the four paints leaves `e < τ`.
    @Test func e1_shadowIsNotEvidence() {
        let parameters = DetectionParameters()
        let tau = DifferencingDartDetector.threshold(noiseSigma: 2, parameters: parameters)
        #expect(tau == 18)
        for (index, paint) in Self.paints.enumerated() {
            let reference = canvas(paint.colour, seed: UInt64(10 + index))
            // A band of 30 mm in shadow; the rest of the canvas is unchanged, so that the gain stays near 1.
            let current = canvas(paint.colour, seed: UInt64(20 + index),
                                 band: (500..<560, shadowed(paint.colour, strength: 0.6)))
            let evidence = ChangeEvidence(reference: reference, current: current, excluded: CanvasMask(), threshold: tau,
                                          parameters: parameters)
            let inShadow = largest(evidence, rows: 500..<560)
            #expect(inShadow < Float(tau), "\(paint.name): e = \(inShadow) in the shadow")
            // The same darkening is evidence when the shadow model is narrowed to [0.7, 1.08]: the test sees the shadow.
            var narrow = parameters
            narrow.shadowLowerBound = 0.7
            let strict = ChangeEvidence(reference: reference, current: current, excluded: CanvasMask(), threshold: tau,
                                        parameters: narrow)
            if paint.name != "black" {
                #expect(largest(strict, rows: 510..<550) >= Float(tau), "\(paint.name): the shadow must be measurable")
            }
        }
    }

    // MARK: E2

    /// E2: a global gain of 0.9 on the rendered board leaves `e < τ` everywhere, and `g` is 0.9 within 1 %.
    @Test func e2_globalGain() {
        let parameters = DetectionParameters()
        for pose in SupportPoses.allCases {
            let camera = pose.camera
            var scene = SupportScenes.empty(seed: 3)
            let reference = scene.renderCanvas(camera: camera)
            scene.seed = 4
            scene.gain = 0.9
            let current = scene.renderCanvas(camera: camera)
            let evidence = ChangeEvidence(reference: reference, current: current, excluded: CanvasMask(), threshold: 18,
                                          parameters: parameters)
            #expect(abs(evidence.gain - 0.9) <= 0.009, "pose \(pose): g = \(evidence.gain)")
            let worst = evidence.values.max() ?? 0
            #expect(worst < 18, "pose \(pose): largest e = \(worst)")
            #expect(evidence.changedBoardFraction < 0.01)
            #expect(evidence.mask(cleared: CanvasMask(), parameters: parameters).pixels.allSatisfy { $0 == 0 })
        }
    }

    // MARK: E3

    /// E3: steel, brass and black pieces on each paint. Every piece is evidence (`e ≥ τ`) except a dark piece on
    /// the black paint (the black shaft of the steel dart, the point, barrel and shaft of the all-black dart), missed
    /// by design, and the red flight of the brass dart on the red paint (same colour). Expected misses, listed:
    /// steel shaft, black point, black barrel, black shaft on black; brass flight on red.
    @Test func e3_piecesOnEachPaint() {
        let parameters = DetectionParameters()
        let styles: [(name: String, style: SyntheticDartStyle)] = [("steel", .steelTungsten), ("brass", .brass), ("black", .allBlack)]
        for (paintIndex, paint) in Self.paints.enumerated() {
            for (styleIndex, style) in styles.enumerated() {
                let pieces: [(name: String, colour: SIMD3<UInt8>)] = [
                    ("point", style.style.point), ("barrel", style.style.barrel), ("shaft", style.style.shaft), ("flight", style.style.flight),
                ]
                for (pieceIndex, piece) in pieces.enumerated() {
                    let seed = UInt64(100 + paintIndex * 100 + styleIndex * 10 + pieceIndex)
                    let reference = canvas(paint.colour, seed: seed)
                    let current = canvas(paint.colour, seed: seed + 1000, band: (600..<620, piece.colour))
                    let evidence = ChangeEvidence(reference: reference, current: current, excluded: CanvasMask(), threshold: 18,
                                                  parameters: parameters)
                    var core: [Float] = []
                    for x in stride(from: 0, to: BoardCanvas.side, by: 7) {
                        core.append(evidence.value(x: x, y: 610))
                    }
                    let seen = (detectionMedian(core.map(Double.init)) ?? 0) >= 18
                    let missed: Set<String> = ["steel shaft black", "black point black", "black barrel black",
                                               "black shaft black", "brass flight red"]
                    let expected = !missed.contains("\(style.name) \(piece.name) \(paint.name)")
                    #expect(seen == expected, "\(style.name) \(piece.name) on \(paint.name): seen \(seen), expected \(expected)")
                }
            }
        }
    }

    // MARK: E4

    /// E4: the whole image shifted by 0.3 px gives an empty mask after D3 with the edge guard; without the guard the
    /// thresholded evidence is not empty (the guard is what removes the wires and colour edges).
    @Test func e4_subPixelShiftWithEdgeGuard() {
        let parameters = DetectionParameters()
        var unguarded = parameters
        unguarded.edgeGuardPixels = 0
        for (index, pose) in SupportPoses.allCases.enumerated() {
            let camera = pose.camera
            var scene = SupportScenes.empty(seed: UInt64(30 + index))
            let reference = scene.renderCanvas(camera: camera)
            scene.seed = UInt64(40 + index)
            scene.shift = index % 2 == 0 ? SIMD2(0.3, 0.3) : SIMD2(-0.3, 0.3)
            let current = scene.renderCanvas(camera: camera)
            let evidence = ChangeEvidence(reference: reference, current: current, excluded: CanvasMask(), threshold: 18,
                                          parameters: parameters)
            let mask = evidence.mask(cleared: CanvasMask(), parameters: parameters)
            #expect(mask.pixels.allSatisfy { $0 == 0 }, "pose \(pose): \(mask.pixels.filter { $0 != 0 }.count) mask pixels")
            let raw = evidence.rawMask(cleared: CanvasMask(), parameters: unguarded)
            #expect(raw.pixels.contains { $0 != 0 }, "pose \(pose): the shift must leave edge residuals without the guard")
            let request = DetectionRequest(current: current, reference: reference, emptyReference: reference, knownDarts: [],
                                           calibration: camera.calibration(), noiseSigma: 2)
            #expect(DifferencingDartDetector().analyse(request).kind == .noChange)
        }
    }
}
