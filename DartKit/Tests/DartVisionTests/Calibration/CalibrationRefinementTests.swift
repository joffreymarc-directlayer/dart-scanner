import Foundation
import simd
import Testing
import DartCore
@testable import DartVision

extension CalibrationTests {
    /// `calibrate` on rendered stills (VISION.md §4.5, §4.6, §4.7): edge measurement, guarded refinement, ring radii,
    /// sector phase, wire height, grade, persistence. Cases C1, C4, C5 (phase), C6, C7, C9 and C12.
    @Suite struct CalibrationRefinementTests {
        private let calibrator = BoardCalibrator()

        /// Cameras of C1: 1.2 to 2.4 px/mm, 0 to 35 degrees off the normal, below or beside the board.
        private var c1Cameras: [SyntheticCamera] {
            [
                CalibrationFixtures.camera(pixelsPerMillimetre: 2.4, viewAngle: 0),
                CalibrationFixtures.camera(pixelsPerMillimetre: 1.4, viewAngle: 10, azimuth: 160),
                CalibrationFixtures.camera(pixelsPerMillimetre: 2.0, viewAngle: 20, azimuth: 200, roll: 4),
                CalibrationFixtures.camera(pixelsPerMillimetre: 1.6, viewAngle: 28, azimuth: 180),
                CalibrationFixtures.camera(pixelsPerMillimetre: 2.6, viewAngle: 35, azimuth: 150, roll: -6),
                CalibrationFixtures.camera(pixelsPerMillimetre: 1.7, viewAngle: 35, azimuth: 250,
                                           imageSize: PixelSize(width: 3840, height: 2160)),
            ] + SupportPoses.cameras
        }

        @Test func c1_exactHandlesStayPut() async throws {
            var random = SupportRandom(seed: 11)
            var scales: [Double] = []
            for (index, camera) in c1Cameras.enumerated() {
                await Task.yield()
                let still = CalibrationFixtures.still(camera, seed: UInt64(index + 1), gain: random.uniform(0.9...1.1))
                let calibration = try #require(CalibrationFixtures.calibrate(handles: camera.exactHandles(), still: still,
                                                                             camera: camera))
                let quality = calibration.quality
                scales.append(quality.minPixelsPerMillimetre)
                #expect(quality.refinementApplied)
                #expect((quality.edgeResidualRMS ?? .infinity) <= 0.3)
                #expect(quality.maxHandleShift <= 0.5)
                #expect(zip(calibration.handles.points, camera.exactHandles().points).allSatisfy {
                    simd_length(SIMD2($0.x - $1.x, $0.y - $1.y)) <= 0.5
                })
                #expect(CalibrationFixtures.errors(of: calibration, truth: camera.boardToImage).max < 0.1)
                #expect((quality.measuredFraction ?? 0) >= 0.9 && (quality.edgeInlierFraction ?? 0) >= 0.9)
            }
            // The set spans the documented range of resolutions.
            #expect((scales.min() ?? 0) < 1.3 && (scales.max() ?? 0) > 2.3 && (scales.min() ?? 0) >= 1.1)
        }

        @Test func c4_handlesTwelvePixelsOffAreRefused() async throws {
            for camera in SupportPoses.cameras {
                await Task.yield()
                let still = CalibrationFixtures.still(camera, seed: 4)
                for direction in [SIMD2(1.0, 0), SIMD2(0.6, -0.8)] {
                    await Task.yield()
                    let shifted = camera.exactHandles().translated(dx: 12 * direction.x, dy: 12 * direction.y)
                    let calibration = try #require(CalibrationFixtures.calibrate(handles: shifted, still: still, camera: camera))
                    #expect(calibration.quality.issues.contains(.refinementRejected))
                    #expect(calibration.quality.grade == .poor && !calibration.quality.refinementApplied)
                    #expect(calibration.handles == calibration.userHandles && calibration.userHandles == shifted)
                    #expect(calibration.quality.maxHandleShift == 0 && calibration.ringRadii == .nominal)
                }
                // Each handle off by 12 px in its own direction.
                var spread = camera.exactHandles()
                for handle in CalibrationHandle.allCases {
                    await Task.yield()
                    let a = Double(handle.rawValue) * 2.1
                    spread[handle].x += 12 * cos(a)
                    spread[handle].y += 12 * sin(a)
                }
                let calibration = try #require(CalibrationFixtures.calibrate(handles: spread, still: still, camera: camera))
                #expect(calibration.quality.issues.contains(.refinementRejected))
                #expect(calibration.quality.grade == .poor && calibration.handles == spread)
            }
        }

        @Test func c5_wireframeTurnedByOneSectorIsFlagged() async throws {
            for camera in SupportPoses.cameras {
                await Task.yield()
                let still = CalibrationFixtures.still(camera, seed: 5)
                for count in [1, -1, 3] {
                    await Task.yield()
                    let turned = try #require(camera.exactHandles().rotated(bySectors: count))
                    let calibration = try #require(CalibrationFixtures.calibrate(handles: turned, still: still, camera: camera))
                    #expect(calibration.quality.issues.contains(.sectorPhaseMismatch))
                    #expect(calibration.quality.grade == .poor)
                }
                // Two sectors keep the colours: not detectable, by design (the numbers of the overlay are for that).
                let even = try #require(camera.exactHandles().rotated(bySectors: 2))
                let calibration = try #require(CalibrationFixtures.calibrate(handles: even, still: still, camera: camera))
                #expect(!calibration.quality.issues.contains(.sectorPhaseMismatch))
                let right = try #require(CalibrationFixtures.calibrate(handles: camera.exactHandles(), still: still, camera: camera))
                #expect(!right.quality.issues.contains(.sectorPhaseMismatch))
            }
        }

        @Test func c6_threeDartsOnTheBoard() async throws {
            var random = SupportRandom(seed: 66)
            for seed in 0..<12 {
                await Task.yield()
                let camera = SupportPoses.allCases[seed % 4].camera
                let darts = (0..<3).map { _ in SupportScenes.randomDart(&random) }
                let still = SupportScenes.darts(darts, seed: UInt64(seed + 1)).render(camera: camera)
                let handles = CalibrationFixtures.noisy(camera.exactHandles(), sigma: 1, random: &random)
                let calibration = try #require(CalibrationFixtures.calibrate(handles: handles, still: still, camera: camera))
                let errors = CalibrationFixtures.errors(of: calibration, truth: camera.boardToImage)
                #expect(errors.p95 <= 1.0, "seed \(seed): \(errors)")
                #expect(calibration.quality.refinementApplied, "seed \(seed)")
            }
        }

        @Test func c7_ringRadiiOfThisBoard() async throws {
            var scene = SupportScenes.empty(seed: 7)
            scene.radii = RingRadii(innerBull: 6.35, outerBull: 15.9, trebleInner: 98, trebleOuter: 106.5,
                                    doubleInner: 162, doubleOuter: 170)
            var off = CalibrationParameters()
            off.fitRingRadii = false
            for camera in SupportPoses.cameras {
                await Task.yield()
                let still = scene.render(camera: camera)
                let calibration = try #require(CalibrationFixtures.calibrate(handles: camera.exactHandles(), still: still,
                                                                             camera: camera))
                let fitted = calibration.ringRadii.all
                for (value, expected) in zip(fitted, scene.radii.all) {
                    await Task.yield()
                    #expect(abs(value - expected) <= 0.3, "\(fitted)")
                }
                #expect(calibration.ringRadii.doubleOuter == 170)
                // A point on this board's treble wire reads on the nominal one.
                let onWire = calibration.boardPoint(for: CalibrationFixtures.project(camera, BoardPoint(x: 0, y: 98)))
                #expect(abs(onWire.y - 99) <= 0.3)
                let nominal = try #require(CalibrationFixtures.calibrate(BoardCalibrator(parameters: off),
                                                                         handles: camera.exactHandles(), still: still,
                                                                         camera: camera))
                #expect(nominal.ringRadii == .nominal)
            }
            // On a nominal board the fitted radii stay nominal.
            for camera in SupportPoses.cameras {
                await Task.yield()
                let still = CalibrationFixtures.still(camera, seed: 8)
                let calibration = try #require(CalibrationFixtures.calibrate(handles: camera.exactHandles(), still: still,
                                                                             camera: camera))
                for (value, expected) in zip(calibration.ringRadii.all, RingRadii.nominal.all) {
                    await Task.yield()
                    #expect(abs(value - expected) <= 0.3)
                }
            }
        }

        @Test func c9a_wireHeightExactGeometry() async throws {
            let camera = SupportPoses.a.camera
            let s = 0.7
            let handles = CalibrationFixtures.handles(camera, z: s)
            var parameters = CalibrationParameters()
            parameters.wireHeight = s
            let active = try #require(CalibrationFixtures.preview(BoardCalibrator(parameters: parameters), handles: handles,
                                                                  camera: camera))
            let inactive = try #require(CalibrationFixtures.preview(handles: handles, camera: camera))
            #expect(active.wireHeight == s && inactive.wireHeight == 0)
            let foot = SIMD2(camera.position.x, camera.position.y)
            var shifts: [Double] = []
            for point in CalibrationFixtures.boardPoints(count: 200, seed: 9) {
                await Task.yield()
                let image = CalibrationFixtures.project(camera, point)
                let x = SIMD2(point.x, point.y)
                let corrected = active.boardPoint(for: image)
                #expect(simd_length(SIMD2(corrected.x, corrected.y) - x) < 1e-6)
                let raw = inactive.boardPoint(for: image)
                let displacement = SIMD2(raw.x, raw.y) - x
                // Towards F, by s·tan θ(X).
                let towards = simd_normalize(foot - x)
                let expected = s * inactive.pose.tanObliquity(at: point)
                #expect(abs(simd_dot(displacement, towards) - expected) < 0.001)
                #expect(simd_length(displacement - simd_dot(displacement, towards) * towards) < 1e-6)
                shifts.append(simd_length(displacement))
            }
            #expect((shifts.min() ?? 0) >= 0.19 && (shifts.max() ?? 1) <= 0.42)
        }

        @Test func c9b_wireHeightOnARenderedBoard() async throws {
            let camera = SupportPoses.a.camera
            var scene = SupportScenes.empty(seed: 9)
            scene.noiseSigma = 0
            scene.wireHeight = 1.0
            let still = scene.render(camera: camera)
            let handles = CalibrationFixtures.handles(camera, z: 1.0)
            var parameters = CalibrationParameters()
            parameters.wireHeight = 1.0
            let foot = SIMD2(camera.position.x, camera.position.y)
            func meanSignedError(_ calibration: BoardCalibration) -> Double {
                let points = CalibrationFixtures.boardPoints(count: 200, seed: 10)
                let total = points.reduce(0.0) { sum, point in
                    let x = SIMD2(point.x, point.y)
                    let read = calibration.boardPoint(for: CalibrationFixtures.project(camera, point))
                    return sum + simd_dot(SIMD2(read.x, read.y) - x, simd_normalize(x - foot))
                }
                return total / Double(points.count)
            }
            let active = try #require(CalibrationFixtures.calibrate(BoardCalibrator(parameters: parameters), handles: handles,
                                                                    still: still, camera: camera))
            let inactive = try #require(CalibrationFixtures.calibrate(handles: handles, still: still, camera: camera))
            #expect(active.quality.refinementApplied && inactive.quality.refinementApplied)
            #expect(abs(meanSignedError(active)) <= 0.1)
            #expect(abs(meanSignedError(inactive) + 0.44) <= 0.1)
        }

        @Test func c12_calibrationSurvivesJSON() async throws {
            let camera = SupportPoses.c.camera
            var parameters = CalibrationParameters()
            parameters.wireHeight = 0.7
            var random = SupportRandom(seed: 12)
            let handles = CalibrationFixtures.noisy(camera.exactHandles(), sigma: 1.5, random: &random)
            let calibration = try #require(CalibrationFixtures.calibrate(BoardCalibrator(parameters: parameters), handles: handles,
                                                                         still: CalibrationFixtures.still(camera, seed: 12),
                                                                         camera: camera))
            #expect(calibration.wireHeight == 0.7 && calibration.ringRadii != .nominal)
            let data = try JSONEncoder().encode(calibration)
            let decoded = try JSONDecoder().decode(BoardCalibration.self, from: data)
            #expect(decoded == calibration)
            #expect(decoded.hashValue == calibration.hashValue)
        }

        @Test func calibrate_isDeterministicAndRecordsWhatItDid() async throws {
            let camera = SupportPoses.d.camera
            let still = CalibrationFixtures.still(camera, seed: 13)
            var random = SupportRandom(seed: 13)
            let handles = CalibrationFixtures.noisy(camera.exactHandles(), sigma: 2, random: &random)
            let first = try #require(CalibrationFixtures.calibrate(handles: handles, still: still, camera: camera))
            let second = try #require(CalibrationFixtures.calibrate(handles: handles, still: still, camera: camera))
            #expect(first == second)
            #expect(first.userHandles == handles && first.handles != handles)
            let shifts = zip(first.handles.points, handles.points).map { simd_length(SIMD2($0.x - $1.x, $0.y - $1.y)) }
            #expect(abs(first.quality.maxHandleShift - (shifts.max() ?? 0)) < 1e-9)
            #expect(first.quality.grade == .good && first.quality.issues.isEmpty)
            #expect(first.imageSize == camera.imageSize && first.intrinsics == camera.intrinsics)
            #expect(simd_length(first.pose.center - camera.position) < 1)
            // The pose and H agree, and the inverse is the inverse.
            for point in CalibrationFixtures.boardPoints(count: 20) {
                await Task.yield()
                let p = SIMD2(point.x, point.y)
                #expect(simd_length(first.imageToBoard.apply(first.boardToImage.apply(p)) - p) < 1e-9)
            }
            let other = try #require(CalibrationFixtures.calibrate(handles: handles.translated(dx: 0.5, dy: 0), still: still,
                                                                   camera: camera))
            #expect(other.id != first.id)
        }

        @Test func calibrate_onABlankStillKeepsThePlayersHandles() async throws {
            let camera = SupportPoses.a.camera
            let blank = RGBImage(width: camera.imageSize.width, height: camera.imageSize.height, fill: SIMD3(128, 128, 128))
            let calibration = try #require(CalibrationFixtures.calibrate(handles: camera.exactHandles(), still: blank,
                                                                         camera: camera))
            #expect(calibration.quality.issues.contains(.edgesNotFound) && calibration.quality.issues.contains(.refinementRejected))
            #expect(calibration.quality.measuredFraction == 0 && calibration.quality.edgeResidualRMS == nil)
            #expect(calibration.quality.edgeInlierFraction == nil)
            #expect(calibration.quality.issues.contains(.sectorPhaseMismatch))
            #expect(calibration.handles == calibration.userHandles && calibration.quality.grade == .poor)
        }

        /// The guard (VISION.md §4.6) on calibrations that start good: under nuisances (darts, a hand over the board,
        /// hard shadows, light, blur, noise, sub-pixel shift), the refinement either improves the error or is refused
        /// and leaves the starting handles untouched. It never makes a good calibration worse.
        @Test func guard_neverMakesAGoodCalibrationWorse() async throws {
            var random = SupportRandom(seed: 21)
            var accepted = 0
            for seed in 0..<16 {
                await Task.yield()
                let camera = SupportPoses.allCases[seed % 4].camera
                var scene = SupportScenes.empty(seed: UInt64(100 + seed))
                switch seed % 4 {
                case 0:
                    scene.darts = (0..<3).map { _ in SupportScenes.randomDart(&random) }
                    scene.light = SupportScenes.lampOpposite(to: camera)
                    scene.shadowStrength = 0.35
                case 1:
                    scene.hand = (BoardPoint(x: random.uniform(-80...80), y: random.uniform(-120...0)), 70)
                case 2:
                    scene.gain = random.uniform(0.6...1.4)
                    scene.noiseSigma = 6
                    scene.blurPasses = 3
                default:
                    scene.shift = SIMD2(random.uniform(-0.5...0.5), random.uniform(-0.5...0.5))
                    scene.darts = (0..<3).map { _ in SupportScenes.randomDart(&random) }
                }
                let still = scene.render(camera: camera)
                let truth = CalibrationFixtures.shifted(camera.boardToImage, by: scene.shift)
                let start = CalibrationFixtures.noisy(CalibrationHandles(projecting: truth), sigma: 0.6, random: &random)
                let before = try #require(CalibrationFixtures.preview(handles: start, camera: camera))
                let after = try #require(CalibrationFixtures.calibrate(handles: start, still: still, camera: camera))
                let errorBefore = CalibrationFixtures.errors(of: before, truth: truth)
                let errorAfter = CalibrationFixtures.errors(of: after, truth: truth)
                if after.quality.refinementApplied {
                    accepted += 1
                    #expect(errorAfter.rms <= errorBefore.rms, "seed \(seed): \(errorBefore) → \(errorAfter)")
                    #expect(errorAfter.max <= max(errorBefore.max, 0.3), "seed \(seed)")
                } else {
                    #expect(after.handles == start && after.boardToImage == before.boardToImage, "seed \(seed)")
                }
            }
            #expect(accepted >= 12)
        }

        /// The grade of C8 (VISION.md §4.7) from the figures the calibration reports, for views that reach all three.
        @Test func grade_followsTheTableOfC8() async throws {
            func expected(_ quality: CalibrationQuality) -> CalibrationQuality.Grade {
                guard quality.refinementApplied, let rms = quality.edgeResidualRMS,
                      !quality.issues.contains(.sectorPhaseMismatch) else { return .poor }
                let scale = quality.minPixelsPerMillimetre
                if rms <= 0.35, scale >= 1.5, quality.minTanObliquity >= 0.21, quality.maxTanObliquity <= 0.84 { return .good }
                if rms <= 0.7, scale >= 1.2, quality.minTanObliquity >= 0.16, quality.maxTanObliquity <= 1.2 { return .fair }
                return .poor
            }
            let cameras = SupportPoses.cameras + [
                CalibrationFixtures.camera(pixelsPerMillimetre: 1.45, viewAngle: 22),   // resolution of "fair"
                CalibrationFixtures.camera(pixelsPerMillimetre: 2.2, viewAngle: 44),    // obliquity of "fair"
                CalibrationFixtures.camera(pixelsPerMillimetre: 2.2, viewAngle: 4),     // too frontal
                CalibrationFixtures.camera(pixelsPerMillimetre: 2.2, viewAngle: 60),    // too oblique
            ]
            var grades: Set<CalibrationQuality.Grade> = []
            for (index, camera) in cameras.enumerated() {
                await Task.yield()
                let calibration = try #require(CalibrationFixtures.calibrate(handles: camera.exactHandles(),
                                                                             still: CalibrationFixtures.still(camera, seed: UInt64(index)),
                                                                             camera: camera))
                #expect(calibration.quality.grade == expected(calibration.quality), "camera \(index): \(calibration.quality)")
                grades.insert(calibration.quality.grade)
            }
            #expect(grades == [.good, .fair, .poor])
            // Boundaries of the table, on the figures alone.
            let gate = try #require({ () -> CalibrationGate? in
                if case .success(let gate) = CalibrationGate.evaluate(handles: SupportPoses.a.camera.exactHandles(),
                                                                      imageSize: SupportPoses.a.camera.imageSize,
                                                                      intrinsics: SupportPoses.a.camera.intrinsics,
                                                                      parameters: .init()) { return gate }
                return nil
            }())
            let parameters = CalibrationParameters()
            #expect(CalibrationGate.grade(applied: true, rms: 0.35, gate: gate, phaseMatches: true, parameters: parameters) == .good)
            #expect(CalibrationGate.grade(applied: true, rms: 0.351, gate: gate, phaseMatches: true, parameters: parameters) == .fair)
            #expect(CalibrationGate.grade(applied: true, rms: 0.7, gate: gate, phaseMatches: true, parameters: parameters) == .fair)
            #expect(CalibrationGate.grade(applied: true, rms: 0.701, gate: gate, phaseMatches: true, parameters: parameters) == .poor)
            #expect(CalibrationGate.grade(applied: false, rms: 0.1, gate: gate, phaseMatches: true, parameters: parameters) == .poor)
            #expect(CalibrationGate.grade(applied: true, rms: nil, gate: gate, phaseMatches: true, parameters: parameters) == .poor)
            #expect(CalibrationGate.grade(applied: true, rms: 0.1, gate: gate, phaseMatches: false, parameters: parameters) == .poor)
            var low = gate
            low.minPixelsPerMillimetre = 1.2
            #expect(CalibrationGate.grade(applied: true, rms: 0.1, gate: low, phaseMatches: true, parameters: parameters) == .fair)
            low.minPixelsPerMillimetre = 1.19
            #expect(CalibrationGate.grade(applied: true, rms: 0.1, gate: low, phaseMatches: true, parameters: parameters) == .poor)
            var tilted = gate
            tilted.minTanObliquity = 0.2
            #expect(CalibrationGate.grade(applied: true, rms: 0.1, gate: tilted, phaseMatches: true, parameters: parameters) == .fair)
            tilted.maxTanObliquity = 1.21
            #expect(CalibrationGate.grade(applied: true, rms: 0.1, gate: tilted, phaseMatches: true, parameters: parameters) == .poor)
        }
    }
}
