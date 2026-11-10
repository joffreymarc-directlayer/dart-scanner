import Foundation
import simd
import Testing
import DartCore
@testable import DartVision

/// Homography tools of VISION.md §4.2 and §4.4: closed form, normalised DLT, inverse, local scale (M1, M2, M3, M7, M11).
@Suite struct MathHomographyTests {
    /// The four handle junctions (r = 170 mm on the radial wires 20/1, 6/10, 3/19, 11/14), in handle order.
    private var junctions: [SIMD2<Double>] {
        CalibrationHandle.allCases.map { SIMD2($0.boardPoint.x, $0.boardPoint.y) }
    }

    /// `count` board points spread over the disc of radius `radius`, centre included.
    private func boardSamples(_ random: inout SupportRandom, count: Int, radius: Double = 170) -> [SIMD2<Double>] {
        [SIMD2(0, 0)] + (1..<count).map { _ in
            let p = random.boardPoint(maxRadius: radius)
            return SIMD2(p.x, p.y)
        }
    }

    private func project(_ camera: SyntheticCamera, _ p: SIMD2<Double>) -> SIMD2<Double> {
        let image = camera.project(SIMD3(p.x, p.y, 0))
        return SIMD2(image.x, image.y)
    }

    // MARK: M1

    @Test func m1_closedFormDLTAndTruthAgree() throws {
        var random = SupportRandom(seed: 0x4D31)
        var worstClosed = 0.0, worstDLT4 = 0.0, worstDLTMany = 0.0, worstTruth = 0.0
        for _ in 0..<200 {
            let camera = random.camera(viewAngle: 0...50)
            let truth = camera.boardToImage
            let handles = camera.exactHandles().points.map { SIMD2($0.x, $0.y) }
            let closed = try #require(Homography.mapping(from: junctions, to: handles))
            let dlt4 = try #require(Homography(from: junctions, to: handles))
            let many = boardSamples(&random, count: 40)
            let dltMany = try #require(Homography(from: many, to: many.map { project(camera, $0) }))
            for p in boardSamples(&random, count: 60, radius: 225) {
                let expected = project(camera, p)
                worstTruth = max(worstTruth, simd_distance(truth.apply(p), expected))
                worstClosed = max(worstClosed, simd_distance(closed.apply(p), expected))
                worstDLT4 = max(worstDLT4, simd_distance(dlt4.apply(p), expected))
                worstDLTMany = max(worstDLTMany, simd_distance(dltMany.apply(p), expected))
            }
        }
        #expect(worstTruth < 1e-6, "H = K[r1 r2 t] against the pinhole projection: \(worstTruth) px")
        #expect(worstClosed < 1e-6, "closed form: \(worstClosed) px")
        #expect(worstDLT4 < 1e-6, "DLT on the four handles: \(worstDLT4) px")
        #expect(worstDLTMany < 1e-6, "DLT on 40 points: \(worstDLTMany) px")
    }

    @Test func m1_unitSquareSendsTheCornersOntoTheQuad() throws {
        let quad: [SIMD2<Double>] = [SIMD2(100, 200), SIMD2(900, 180), SIMD2(1000, 1100), SIMD2(50, 950)]
        let square: [SIMD2<Double>] = [SIMD2(0, 0), SIMD2(1, 0), SIMD2(1, 1), SIMD2(0, 1)]
        let h = try #require(Homography.unitSquare(to: quad))
        for (corner, target) in zip(square, quad) {
            #expect(simd_distance(h.apply(corner), target) < 1e-9)
        }
        // The documented normalisation: h33 = 1.
        #expect(h.row2.z == 1)
        // The DLT through the same four pairs is the same transform.
        let dlt = try #require(Homography(from: square, to: quad))
        for p in [SIMD2(0.5, 0.5), SIMD2(0.25, 0.8), SIMD2(-0.3, 1.4)] {
            #expect(simd_distance(dlt.apply(p), h.apply(p)) < 1e-9)
        }
    }

    // MARK: M2

    @Test func m2_inverseRoundTrip() throws {
        var random = SupportRandom(seed: 0x4D32)
        var cameras = SupportPoses.cameras
        for _ in 0..<100 {
            cameras.append(random.camera(viewAngle: 0...50))
        }
        var worst = 0.0, worstImage = 0.0
        for camera in cameras {
            let h = camera.boardToImage
            let g = try #require(h.inverse, "pose \(camera.position)")
            for p in boardSamples(&random, count: 50, radius: 230) {
                worst = max(worst, simd_distance(g.apply(h.apply(p)), p))
            }
            // And the other way: image points of the board come back to themselves.
            let back = try #require(g.inverse)
            for p in boardSamples(&random, count: 20) {
                let image = h.apply(p)
                worstImage = max(worstImage, simd_distance(back.apply(g.apply(image)), image))
            }
            // H·G is the identity up to scale.
            let product = h.concatenating(g).matrix * (1 / h.concatenating(g).row2.z)
            let identity = matrix_identity_double3x3
            for column in 0..<3 {
                #expect(simd_distance(product[column], identity[column]) < 1e-9)
            }
        }
        #expect(worst < 1e-9, "G(H(x)) − x: \(worst) mm")
        #expect(worstImage < 1e-6, "H(G(p)) − p: \(worstImage) px")
    }

    @Test func m2_concatenationAppliesTheFirstTransformFirst() {
        let rotate = Homography.boardRotation(clockwiseDegrees: 90)
        let shift = Homography(simd_double3x3(rows: [SIMD3(1, 0, 10), SIMD3(0, 1, 0), SIMD3(0, 0, 1)]))
        // Rotation clockwise by 90 degrees: the 20 (+y) goes to the 6 (+x).
        #expect(simd_distance(rotate.apply(SIMD2(0, 1)), SIMD2(1, 0)) < 1e-15)
        // shift ∘ rotate: rotate (0, 1) to (1, 0), then shift to (11, 0).
        #expect(simd_distance(shift.concatenating(rotate).apply(SIMD2(0, 1)), SIMD2(11, 0)) < 1e-12)
        #expect(simd_distance(rotate.concatenating(shift).apply(SIMD2(0, 1)), SIMD2(1, -10)) < 1e-12)
        #expect(Homography.identity.apply(SIMD2(3, -4)) == SIMD2(3, -4))
        #expect(Homography.identity.matrix == matrix_identity_double3x3)
        #expect(Homography(rotate.matrix) == rotate)
        // L7 of VISION.md §4.3: Rot(β) = [[cos β, sin β, 0], [−sin β, cos β, 0], [0, 0, 1]].
        let beta = 36.0 * .pi / 180
        let rot = Homography.boardRotation(clockwiseDegrees: 36)
        #expect(rot.row0 == SIMD3(cos(beta), sin(beta), 0) && rot.row1 == SIMD3(-sin(beta), cos(beta), 0) && rot.row2 == SIMD3(0, 0, 1))
    }

    // MARK: M3

    @Test func m3_collinearOrCoincidentPointsGiveNil() {
        let square: [SIMD2<Double>] = [SIMD2(0, 0), SIMD2(1, 0), SIMD2(1, 1), SIMD2(0, 1)]
        let degenerate: [String: [SIMD2<Double>]] = [
            "four collinear": [SIMD2(0, 0), SIMD2(1, 1), SIMD2(2, 2), SIMD2(3, 3)],
            "three collinear (first three)": [SIMD2(0, 0), SIMD2(1, 0), SIMD2(2, 0), SIMD2(0, 1)],
            "three collinear (last three)": [SIMD2(0, 0), SIMD2(1, 0), SIMD2(1, 1), SIMD2(1, 2)],
            "two coincident": [SIMD2(0, 0), SIMD2(1, 0), SIMD2(1, 0), SIMD2(0, 1)],
            "first and last coincident": [SIMD2(5, 5), SIMD2(9, 5), SIMD2(9, 9), SIMD2(5, 5)],
            "all coincident": [SIMD2(3, 4), SIMD2(3, 4), SIMD2(3, 4), SIMD2(3, 4)],
            "handles on one line": [SIMD2(100, 500), SIMD2(400, 500), SIMD2(700, 500), SIMD2(1000, 500)],
        ]
        for (name, points) in degenerate {
            #expect(Homography.unitSquare(to: points) == nil, "unitSquare: \(name)")
            #expect(Homography(from: square, to: points) == nil, "DLT, destination: \(name)")
            #expect(Homography(from: points, to: square) == nil, "DLT, source: \(name)")
            #expect(Homography.mapping(from: square, to: points) == nil, "closed form: \(name)")
        }
        // More than four points, all on one line.
        let line = (0..<8).map { SIMD2(Double($0), 2 * Double($0) + 1) }
        let spread = (0..<8).map { SIMD2(Double($0 % 3), Double($0 / 3)) }
        #expect(Homography(from: line, to: spread) == nil)
        #expect(Homography(from: spread, to: line) == nil)
        // Fewer than four pairs, mismatched counts, a non-finite coordinate.
        #expect(Homography(from: Array(square.prefix(3)), to: Array(square.prefix(3))) == nil)
        #expect(Homography(from: square, to: Array(square.prefix(3))) == nil)
        #expect(Homography.unitSquare(to: Array(square.prefix(3))) == nil)
        #expect(Homography(from: square, to: [SIMD2(0, 0), SIMD2(1, .nan), SIMD2(1, 1), SIMD2(0, 1)]) == nil)
        #expect(Homography.unitSquare(to: [SIMD2(0, 0), SIMD2(.infinity, 0), SIMD2(1, 1), SIMD2(0, 1)]) == nil)
        // A singular matrix has no inverse.
        #expect(Homography(simd_double3x3(rows: [SIMD3(1, 2, 3), SIMD3(2, 4, 6), SIMD3(0, 0, 1)])).inverse == nil)
        #expect(Homography(simd_double3x3(rows: [SIMD3(0, 0, 0), SIMD3(0, 0, 0), SIMD3(0, 0, 0)])).inverse == nil)
        // A regular quad is accepted by all three.
        let quad: [SIMD2<Double>] = [SIMD2(10, 10), SIMD2(90, 12), SIMD2(95, 80), SIMD2(5, 85)]
        #expect(Homography.unitSquare(to: quad) != nil && Homography(from: square, to: quad) != nil)
    }

    // MARK: M7

    @Test func m7_localScaleAgainstFiniteDifferences() throws {
        var random = SupportRandom(seed: 0x4D37)
        var worstJacobian = 0.0, worstSingular = 0.0
        for _ in 0..<50 {
            let camera = random.camera(viewAngle: 0...50)
            let h = camera.boardToImage
            for p in boardSamples(&random, count: 12) {
                let step = 1e-3
                let dx = (h.apply(p + SIMD2(step, 0)) - h.apply(p - SIMD2(step, 0))) / (2 * step)
                let dy = (h.apply(p + SIMD2(0, step)) - h.apply(p - SIMD2(0, step))) / (2 * step)
                let j = h.jacobian(at: p)
                // Columns of the Jacobian: derivatives along x and along y.
                let scale = max(simd_length(dx), simd_length(dy))
                worstJacobian = max(worstJacobian, simd_distance(j.columns.0, dx) / scale, simd_distance(j.columns.1, dy) / scale)
                // Singular values of the finite-difference Jacobian, by the eigenvalues of JᵀJ.
                let aa = simd_dot(dx, dx), bb = simd_dot(dy, dy), ab = simd_dot(dx, dy)
                let root = ((aa - bb) * (aa - bb) + 4 * ab * ab).squareRoot()
                let expectedMax = ((aa + bb + root) / 2).squareRoot(), expectedMin = ((aa + bb - root) / 2).squareRoot()
                let scales = h.localScale(at: p)
                worstSingular = max(worstSingular, abs(scales.max - expectedMax) / expectedMax, abs(scales.min - expectedMin) / expectedMin)
                #expect(scales.min <= scales.max)
            }
        }
        #expect(worstJacobian < 1e-6, "Jacobian: \(worstJacobian)")
        #expect(worstSingular < 1e-6, "singular values: \(worstSingular)")
    }

    @Test func m7_localScaleOfKnownTransforms() {
        // A pure scaling by 2 and 3: singular values 2 and 3 everywhere.
        let scaling = Homography(simd_double3x3(rows: [SIMD3(2, 0, 5), SIMD3(0, 3, -1), SIMD3(0, 0, 1)]))
        let s = scaling.localScale(at: SIMD2(10, -4))
        #expect(abs(s.min - 2) < 1e-12 && abs(s.max - 3) < 1e-12)
        // A rotation keeps lengths.
        let r = Homography.boardRotation(clockwiseDegrees: 33).localScale(at: SIMD2(7, 8))
        #expect(abs(r.min - 1) < 1e-12 && abs(r.max - 1) < 1e-12)
        // A view at 2.4 px/mm (pose A): the worst direction over the board is between 2.0 and 2.5 px/mm.
        let a = SupportPoses.a.camera.boardToImage
        let bull = a.localScale(at: SIMD2(0, 0))
        #expect(bull.min > 2.0 && bull.max < 2.6, "pose A at the bull: \(bull)")
    }

    // MARK: M11

    @Test func m11_normalisedCoordinatesRoundTrip() {
        var random = SupportRandom(seed: 0x4D3B)
        for size in [PixelSize(width: 3840, height: 2160), PixelSize(width: 2160, height: 3840), PixelSize(width: 1920, height: 1080),
                     PixelSize(width: 1280, height: 720), PixelSize(width: 7, height: 3)] {
            let w = Double(size.width), h = Double(size.height)
            // The anchors of VISION.md §3.2 are exact: the outer corners of the image are 0 and 1, the centre is 1/2.
            #expect(ImagePoint(x: -0.5, y: -0.5).normalized(in: size) == SIMD2(0, 0))
            #expect(ImagePoint(x: w - 0.5, y: h - 0.5).normalized(in: size) == SIMD2(1, 1))
            #expect(ImagePoint(x: (w - 1) / 2, y: (h - 1) / 2).normalized(in: size) == SIMD2(0.5, 0.5))
            #expect(ImagePoint(normalized: SIMD2(0, 0), in: size) == ImagePoint(x: -0.5, y: -0.5))
            #expect(ImagePoint(normalized: SIMD2(1, 1), in: size) == ImagePoint(x: w - 0.5, y: h - 0.5))
            #expect(ImagePoint(normalized: SIMD2(0.5, 0.5), in: size) == ImagePoint(x: (w - 1) / 2, y: (h - 1) / 2))
            // Pixel centres and random points come back to themselves. Exact in real arithmetic; in binary floating
            // point `(a / w) * w` may differ from `a` by one unit in the last place (specIssues), hence 1e-12 px.
            var worst = 0.0, worstNormalised = 0.0
            for _ in 0..<2000 {
                let point = ImagePoint(x: random.uniform(-0.5...(w - 0.5)), y: random.uniform(-0.5...(h - 0.5)))
                let centre = ImagePoint(x: Double(random.int(below: size.width)), y: Double(random.int(below: size.height)))
                for p in [point, centre] {
                    let back = ImagePoint(normalized: p.normalized(in: size), in: size)
                    worst = max(worst, abs(back.x - p.x), abs(back.y - p.y))
                }
                let u = SIMD2(random.unit(), random.unit())
                worstNormalised = max(worstNormalised, simd_distance(ImagePoint(normalized: u, in: size).normalized(in: size), u))
            }
            #expect(worst < 1e-12, "\(size): \(worst) px")
            #expect(worstNormalised < 1e-15, "\(size): \(worstNormalised)")
        }
    }

    @Test func m11_homographyRoundTripsThroughJSONExactly() throws {
        var random = SupportRandom(seed: 0x4D3C)
        var transforms = SupportPoses.cameras.map(\.boardToImage) + [.identity, Homography.boardRotation(clockwiseDegrees: 17.3)]
        for _ in 0..<20 {
            let camera = random.camera()
            transforms.append(camera.boardToImage)
            transforms.append(try #require(camera.boardToImage.inverse))
        }
        for transform in transforms {
            let data = try JSONEncoder().encode(transform)
            let decoded = try JSONDecoder().decode(Homography.self, from: data)
            #expect(decoded == transform)
            #expect(decoded.row0 == transform.row0 && decoded.row1 == transform.row1 && decoded.row2 == transform.row2)
        }
        // The matrix form is the same three rows.
        let h = SupportPoses.b.camera.boardToImage
        #expect(Homography(h.matrix) == h)
        #expect(h.matrix[0][1] == h.row1.x && h.matrix[1][0] == h.row0.y && h.matrix[2][2] == h.row2.z)
    }
}
