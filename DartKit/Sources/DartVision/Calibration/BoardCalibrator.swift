import Foundation
import simd
import CoreGraphics
import CoreVideo
import DartCore

/// Every calibration constant. Defaults are starting values (section 11).
public struct CalibrationParameters: Hashable, Codable, Sendable {
    // C1 gate
    public var hardMinPixelsPerMillimetre: Double = 0.8
    public var dartMargin: Double = 135
    // C2 edge measurement
    public var profileStep: Double = 0.25
    public var profileHalfWindow: Double = 4.0
    public var secondPassHalfWindow: Double = 2.0
    public var gradientSpan: Int = 2
    public var minEdgeEnergy: Double = 20
    public var edgePeakRatio: Double = 2.5
    public var centroidHalfWidth: Int = 4
    // C3 refinement
    public var huberK: Double = 0.75
    public var outlierCutoff: Double = 3.0
    public var jacobianStep: Double = 0.25
    public var damping: Double = 1e-3
    public var maxIterations: Int = 6
    public var convergence: Double = 0.01
    public var handleTetherWeight: Double = 0.3
    public var minMeasuredFraction: Double = 0.5
    public var minInlierFraction: Double = 0.6
    public var inlierDistance: Double = 1.0
    public var maxInlierRMS: Double = 0.5
    public var maxHandleShift: Double = 4.0
    public var recoverMaxHandleShift: Double = 6.0
    // C4 ring radii, C5 sector phase, C6 wire height
    public var fitRingRadii: Bool = true
    public var ringRadiusTolerance: Double = 2.0
    public var bullRadiusTolerance: Double = 1.0
    public var minSectorLumaContrast: Double = 25
    public var wireHeight: Double = 0
    // Grades
    public var goodRMS: Double = 0.35
    public var fairRMS: Double = 0.7
    public var goodPixelsPerMillimetre: Double = 1.5
    public var fairPixelsPerMillimetre: Double = 1.2
    public var goodMinTan: Double = 0.21
    public var fairMinTan: Double = 0.16
    public var goodMaxTan: Double = 0.84
    public var fairMaxTan: Double = 1.2
    // Drift
    public var driftHealthyMedian: Double = 0.5
    public var driftHealthyInliers: Double = 0.6
    public var driftHealthyInliersWithDarts: Double = 0.5
    public var driftNotVisibleFraction: Double = 0.3
    public init() {}
}

public enum CalibrationError: Error, Equatable, Sendable {
    /// Fewer than four distinct handles, or three of them collinear.
    case degenerateHandles
    /// At least one blocking issue.
    case rejected([CalibrationIssue])
}

/// Result of the drift check (section 4.9).
public struct CalibrationHealth: Hashable, Sendable {
    public enum Status: Sendable { case healthy, drifted, lost, edgesNotVisible }
    public var status: Status
    /// Median absolute edge residual, mm.
    public var medianResidual: Double
    public var inlierFraction: Double
    public var measuredFraction: Double
}

public struct BoardCalibrator: Sendable {
    private let parameters: CalibrationParameters

    public init(parameters: CalibrationParameters = .init()) {
        self.parameters = parameters
    }

    /// Closed-form H plus the sanity gate (C1) and pose (C7). Runs on every handle drag for the live wireframe.
    ///
    /// Without a still nothing is measured: the grade is `poor` (no accepted refinement, VISION.md §4.7), the edge
    /// figures are nil, and the issues are the advisory ones of the geometry alone.
    public func preview(handles: CalibrationHandles, imageSize: PixelSize, rotationDegrees: Int,
                        intrinsics: CameraIntrinsics?) -> Result<BoardCalibration, CalibrationError> {
        switch CalibrationGate.evaluate(handles: handles, imageSize: imageSize, intrinsics: intrinsics,
                                        parameters: parameters) {
        case .failure(let error):
            return .failure(error)
        case .success(let gate):
            let quality = CalibrationQuality(grade: .poor, edgeResidualRMS: nil, edgeInlierFraction: nil,
                                             measuredFraction: nil, refinementApplied: false, maxHandleShift: 0,
                                             minPixelsPerMillimetre: gate.minPixelsPerMillimetre,
                                             viewAngleDegrees: gate.viewAngleDegrees,
                                             minTanObliquity: gate.minTanObliquity,
                                             maxTanObliquity: gate.maxTanObliquity,
                                             issues: CalibrationGate.ordered(gate.advisories))
            return .success(assemble(imageSize: imageSize, rotationDegrees: rotationDegrees, userHandles: handles,
                                     handles: handles, gate: gate, radii: .nominal, wireHeight: parameters.wireHeight,
                                     quality: quality))
        }
    }

    /// Full calibration (C1 to C8) on a frozen still of the board.
    public func calibrate(handles: CalibrationHandles, still: RGBImage, rotationDegrees: Int,
                          intrinsics: CameraIntrinsics?) -> Result<BoardCalibration, CalibrationError> {
        let imageSize = still.size
        let userGate: CalibrationGate
        switch CalibrationGate.evaluate(handles: handles, imageSize: imageSize, intrinsics: intrinsics,
                                        parameters: parameters) {
        case .failure(let error): return .failure(error)
        case .success(let gate): userGate = gate
        }
        let user = handles.points.map { SIMD2($0.x, $0.y) }
        let outcome = EdgeSamplerRaster.with(still) { raster in
            refine(raster, from: user, transform: userGate.boardToImage, radii: .nominal, fitRadii: parameters.fitRingRadii,
                   maxShift: parameters.maxHandleShift, imageSize: imageSize, intrinsics: intrinsics)
        }
        let result: BoardCalibration
        if let accepted = outcome.accepted {
            result = finish(accepted, userHandles: handles, imageSize: imageSize, rotationDegrees: rotationDegrees,
                            wireHeight: parameters.wireHeight, extraIssues: [])
        } else {
            // The refinement is refused: the player's handles stay, with the evidence measured through them.
            var extra: [CalibrationIssue] = [.refinementRejected]
            if outcome.first.measuredFraction < parameters.minMeasuredFraction { extra.append(.edgesNotFound) }
            let kept = CalibrationRefinement(handles: user, gate: userGate, radii: .nominal,
                                             statistics: outcome.first, phaseMatches: outcome.firstPhaseMatches,
                                             applied: false, maxShift: 0)
            result = finish(kept, userHandles: handles, imageSize: imageSize, rotationDegrees: rotationDegrees,
                            wireHeight: parameters.wireHeight, extraIssues: extra)
        }
        return .success(result)
    }

    /// Drift check on any still or frame; darts may be on the board.
    ///
    /// C2 through the current calibration (±`profileHalfWindow`), then VISION.md §4.9: `edgesNotVisible` when fewer
    /// than `driftNotVisibleFraction` of the samples can be measured; `healthy` when the median absolute residual and
    /// the inlier fraction pass; otherwise `drifted` when `recover` passes its gate on the same pixels, `lost` when it
    /// does not. A still of another size than the calibration's is `lost`.
    ///
    /// "Measurable" is read as "the image shows an edge near the sample" (`EdgeSampler.visibleFraction`: some gradient
    /// energy of `minEdgeEnergy` within ±12 mm), not as "the edge was found where the calibration expects it". A hand,
    /// darkness or a board without contrast show no edge; a board that jumped by 20 to 40 mm shows all of them, yet
    /// only about 30 % of its samples, which sit on the edges and now land mostly in uniform beds, pass the acceptance
    /// of C2 (measured on the four reference poses): with that reading such a jolt would be taken for darkness and the
    /// stale calibration kept. The reported `measuredFraction` is still the fraction of accepted observations.
    public func assess(_ calibration: BoardCalibration, on still: RGBImage, dartsOnBoard: Bool) -> CalibrationHealth {
        EdgeSamplerRaster.with(still) { assess(calibration, raster: $0, dartsOnBoard: dartsOnBoard) }
    }

    public func assess(_ calibration: BoardCalibration, on frame: Frame, dartsOnBoard: Bool) -> CalibrationHealth {
        EdgeSamplerRaster.with(frame) { assess(calibration, raster: $0, dartsOnBoard: dartsOnBoard) }
    }

    /// Bounded re-refinement starting from the current handles (`recoverMaxHandleShift`). Nil when the gate fails.
    ///
    /// The result keeps the intrinsics, ring radii and wire height of `calibration`; its `userHandles` are the
    /// handles the refinement started from (`calibration.handles`).
    public func recover(_ calibration: BoardCalibration, on still: RGBImage) -> BoardCalibration? {
        EdgeSamplerRaster.with(still) { recover(calibration, raster: $0) }
    }

    public func recover(_ calibration: BoardCalibration, on frame: Frame) -> BoardCalibration? {
        EdgeSamplerRaster.with(frame) { recover(calibration, raster: $0) }
    }
}

// MARK: - Steps (lot V2, private)

/// The handles a refinement settled on, with what the calibration needs from them.
private struct CalibrationRefinement {
    var handles: [SIMD2<Double>]
    var gate: CalibrationGate
    var radii: RingRadii
    var statistics: HandleRefiner.Statistics
    var phaseMatches: Bool
    var applied: Bool
    /// Largest handle move, px.
    var maxShift: Double
}

extension BoardCalibrator {
    /// C2 to C5 from `start`: two passes of C3, then C4, then the acceptance guard and the phase check.
    /// `accepted` is nil when the guard refuses; `first` is the evidence through the starting handles.
    private func refine(_ raster: EdgeSamplerRaster, from start: [SIMD2<Double>], transform: Homography,
                        radii startRadii: RingRadii, fitRadii: Bool, maxShift: Double, imageSize: PixelSize,
                        intrinsics: CameraIntrinsics?)
        -> (accepted: CalibrationRefinement?, first: HandleRefiner.Statistics, firstPhaseMatches: Bool) {
        let parameters = self.parameters
        let firstMeasurement = EdgeSampler.measure(raster, boardToImage: transform, halfWindow: parameters.profileHalfWindow,
                                                   radii: startRadii, parameters: parameters)
        let startInverse = transform.inverse ?? .identity
        let first = HandleRefiner.statistics(of: firstMeasurement, imageToBoard: startInverse, radii: startRadii,
                                             parameters: parameters)
        let firstPhase = CalibrationPhase.matches(raster, boardToImage: transform, parameters: parameters)
        guard first.measuredFraction >= parameters.minMeasuredFraction else { return (nil, first, firstPhase) }

        // Two passes: measure, solve, measure again with a narrower window, solve.
        let pass1 = HandleRefiner.refine(start: start, tether: start, measurement: firstMeasurement, radii: startRadii,
                                         iterations: parameters.maxIterations, parameters: parameters)
        guard let transform1 = CalibrationGeometry.homography(of: pass1) else { return (nil, first, firstPhase) }
        let secondMeasurement = EdgeSampler.measure(raster, boardToImage: transform1,
                                                    halfWindow: parameters.secondPassHalfWindow, radii: startRadii,
                                                    parameters: parameters)
        let pass2 = HandleRefiner.refine(start: pass1, tether: start, measurement: secondMeasurement, radii: startRadii,
                                         iterations: parameters.maxIterations, parameters: parameters)

        // Candidates, best first: with the ring radii of this board (C4), then with the starting radii.
        var candidates: [(handles: [SIMD2<Double>], radii: RingRadii)] = []
        if fitRadii, let fitted = fitRingRadii(secondMeasurement, handles: pass2, start: start, nominal: startRadii) {
            candidates.append(fitted)
        }
        candidates.append((pass2, startRadii))

        for candidate in candidates {
            guard let finalTransform = CalibrationGeometry.homography(of: candidate.handles),
                  let finalInverse = finalTransform.inverse else { continue }
            let evidence = EdgeSampler.measure(raster, boardToImage: finalTransform,
                                               halfWindow: parameters.secondPassHalfWindow, radii: candidate.radii,
                                               parameters: parameters)
            let statistics = HandleRefiner.statistics(of: evidence, imageToBoard: finalInverse, radii: candidate.radii,
                                                      parameters: parameters)
            // Acceptance guard (VISION.md §4.6).
            guard statistics.measuredFraction >= parameters.minMeasuredFraction,
                  statistics.inlierFraction >= parameters.minInlierFraction,
                  let rms = statistics.inlierRMS, rms <= parameters.maxInlierRMS else { continue }
            // No handle may move by more than the equivalent of `maxShift` mm, read on the board through the
            // starting homography.
            var shiftMillimetres = 0.0
            var shiftPixels = 0.0
            for index in 0..<4 {
                let moved = startInverse.apply(candidate.handles[index])
                shiftMillimetres = max(shiftMillimetres, simd_length(moved - CalibrationGeometry.junctions[index]))
                shiftPixels = max(shiftPixels, simd_length(candidate.handles[index] - start[index]))
            }
            guard shiftMillimetres.isFinite, shiftMillimetres <= maxShift else { continue }
            let refined = CalibrationHandles(points: candidate.handles.map { ImagePoint(x: $0.x, y: $0.y) })
            guard case .success(let gate) = CalibrationGate.evaluate(handles: refined, imageSize: imageSize,
                                                                     intrinsics: intrinsics, parameters: parameters)
            else { continue }
            let phase = CalibrationPhase.matches(raster, boardToImage: finalTransform, parameters: parameters)
            return (CalibrationRefinement(handles: candidate.handles, gate: gate, radii: candidate.radii,
                                          statistics: statistics, phaseMatches: phase, applied: true,
                                          maxShift: shiftPixels), first, firstPhase)
        }
        return (nil, first, firstPhase)
    }

    /// C4 (VISION.md §4.6): the five radii other than the outer double, each the median of `|G·q|` over the
    /// observations of its ring that lie within its tolerance of the starting radius, bounded to that tolerance
    /// (±`ringRadiusTolerance`, ±`bullRadiusTolerance` for the two bulls); two more iterations of C3 with these
    /// radii; a radius whose ring then has fewer than `minInlierFraction` of its samples within `inlierDistance`
    /// goes back to the starting value. Nil when no radius changed.
    ///
    /// The fit and the two iterations are repeated, up to `ringFitRounds` times, until no radius moves by more than
    /// `ringFitSettled`. One round is not enough: the passes of C3 that precede C4 measure every ring against its
    /// nominal radius, so a board whose treble sits 1 mm inside the nominal one biases the scale of `H`, and radii
    /// fitted through that `H` inherit the bias (0.3 mm on the double inner wire, measured). Only the outer double,
    /// the gauge, then pulls the scale back, a part of the way at each round.
    private func fitRingRadii(_ measurement: EdgeSampler.Measurement, handles: [SIMD2<Double>],
                              start: [SIMD2<Double>], nominal: RingRadii)
        -> (handles: [SIMD2<Double>], radii: RingRadii)? {
        let starting = nominal.all
        func tolerance(_ ring: Int) -> Double {
            ring < 2 ? parameters.bullRadiusTolerance : parameters.ringRadiusTolerance
        }
        var current = handles
        var fitted = starting
        for _ in 0..<BoardCalibrator.ringFitRounds {
            guard let transform = CalibrationGeometry.homography(of: current), let inverse = transform.inverse else {
                return nil
            }
            var radiiByRing = [[Double]](repeating: [], count: 6)
            for observation in measurement.observations {
                guard case .ring(let ring) = EdgeSampler.samples[observation.sample].kind, ring < 5 else { continue }
                let radius = simd_length(inverse.apply(observation.point))
                if radius.isFinite, abs(radius - starting[ring]) <= tolerance(ring) {
                    radiiByRing[ring].append(radius)
                }
            }
            var next = starting
            for ring in 0..<5 where !radiiByRing[ring].isEmpty {
                let values = radiiByRing[ring].sorted()
                let median = values.count % 2 == 1
                    ? values[values.count / 2]
                    : (values[values.count / 2 - 1] + values[values.count / 2]) / 2
                next[ring] = min(max(median, starting[ring] - tolerance(ring)), starting[ring] + tolerance(ring))
            }
            let radii = RingRadii(innerBull: next[0], outerBull: next[1], trebleInner: next[2], trebleOuter: next[3],
                                  doubleInner: next[4], doubleOuter: starting[5])
            guard radii.isWellFormed else { return nil }
            let moved = zip(next, fitted).map { abs($0 - $1) }.max() ?? 0
            fitted = next
            current = HandleRefiner.refine(start: current, tether: start, measurement: measurement, radii: radii,
                                           iterations: 2, parameters: parameters)
            if moved < BoardCalibrator.ringFitSettled { break }
        }
        var radii = RingRadii(innerBull: fitted[0], outerBull: fitted[1], trebleInner: fitted[2], trebleOuter: fitted[3],
                              doubleInner: fitted[4], doubleOuter: starting[5])
        guard radii != nominal else { return nil }
        // Keep a radius only when at least `minInlierFraction` of its ring's samples agree with it.
        guard let refinedTransform = CalibrationGeometry.homography(of: current),
              let refinedInverse = refinedTransform.inverse else { return nil }
        var agreeing = [Int](repeating: 0, count: 6)
        var totals = [Int](repeating: 0, count: 6)
        for sample in EdgeSampler.samples {
            if case .ring(let ring) = sample.kind { totals[ring] += 1 }
        }
        for observation in measurement.observations {
            let sample = EdgeSampler.samples[observation.sample]
            guard case .ring(let ring) = sample.kind else { continue }
            let residual = sample.residual(of: refinedInverse.apply(observation.point), radii: radii)
            if abs(residual) < parameters.inlierDistance { agreeing[ring] += 1 }
        }
        var kept = radii.all
        for ring in 0..<5 where totals[ring] > 0 && Double(agreeing[ring]) < parameters.minInlierFraction * Double(totals[ring]) {
            kept[ring] = starting[ring]
        }
        radii = RingRadii(innerBull: kept[0], outerBull: kept[1], trebleInner: kept[2], trebleOuter: kept[3],
                          doubleInner: kept[4], doubleOuter: starting[5])
        guard radii.isWellFormed, radii != nominal else { return nil }
        return (current, radii)
    }

    /// At most this many rounds of C4 (fit, then two iterations of C3).
    static let ringFitRounds = 8
    /// C4 stops when no radius moved by more than this, mm.
    static let ringFitSettled = 0.005

    /// C7 and C8: the calibration of a refinement (accepted or not).
    private func finish(_ refinement: CalibrationRefinement, userHandles: CalibrationHandles, imageSize: PixelSize,
                        rotationDegrees: Int, wireHeight: Double, extraIssues: [CalibrationIssue]) -> BoardCalibration {
        let gate = refinement.gate
        var issues = gate.advisories + extraIssues
        if !refinement.phaseMatches { issues.append(.sectorPhaseMismatch) }
        let statistics = refinement.statistics
        let grade = CalibrationGate.grade(applied: refinement.applied, rms: statistics.inlierRMS,
                                          gate: gate, phaseMatches: refinement.phaseMatches, parameters: parameters)
        let quality = CalibrationQuality(grade: grade,
                                         edgeResidualRMS: statistics.inlierRMS,
                                         edgeInlierFraction: statistics.measured > 0 ? statistics.inlierFraction : nil,
                                         measuredFraction: statistics.measuredFraction,
                                         refinementApplied: refinement.applied,
                                         maxHandleShift: refinement.applied ? refinement.maxShift : 0,
                                         minPixelsPerMillimetre: gate.minPixelsPerMillimetre,
                                         viewAngleDegrees: gate.viewAngleDegrees,
                                         minTanObliquity: gate.minTanObliquity,
                                         maxTanObliquity: gate.maxTanObliquity,
                                         issues: CalibrationGate.ordered(issues))
        let handles = CalibrationHandles(points: refinement.handles.map { ImagePoint(x: $0.x, y: $0.y) })
        return assemble(imageSize: imageSize, rotationDegrees: rotationDegrees, userHandles: userHandles,
                        handles: handles, gate: gate, radii: refinement.radii, wireHeight: wireHeight, quality: quality)
    }

    /// The value, with a deterministic identity: the same inputs give the same calibration, bit for bit
    /// (`id` is a digest of the content, `createdAt` the reference date; see `CalibrationFingerprint`).
    private func assemble(imageSize: PixelSize, rotationDegrees: Int, userHandles: CalibrationHandles,
                          handles: CalibrationHandles, gate: CalibrationGate, radii: RingRadii, wireHeight: Double,
                          quality: CalibrationQuality) -> BoardCalibration {
        var fingerprint = CalibrationFingerprint()
        fingerprint.add(imageSize.width)
        fingerprint.add(imageSize.height)
        fingerprint.add(rotationDegrees)
        for point in userHandles.points + handles.points {
            fingerprint.add(point.x)
            fingerprint.add(point.y)
        }
        for value in radii.all + [wireHeight, gate.intrinsics.fx, gate.intrinsics.fy, gate.intrinsics.cx, gate.intrinsics.cy] {
            fingerprint.add(value)
        }
        fingerprint.add(quality.grade.rawValue)
        return BoardCalibration(id: fingerprint.uuid,
                                createdAt: Date(timeIntervalSinceReferenceDate: 0),
                                imageSize: imageSize,
                                rotationDegrees: rotationDegrees,
                                userHandles: userHandles,
                                handles: handles,
                                boardToImage: gate.boardToImage,
                                imageToBoard: gate.imageToBoard,
                                ringRadii: radii,
                                wireHeight: wireHeight,
                                intrinsics: gate.intrinsics,
                                pose: gate.pose,
                                quality: quality)
    }

    private func assess(_ calibration: BoardCalibration, raster: EdgeSamplerRaster, dartsOnBoard: Bool) -> CalibrationHealth {
        guard raster.size == calibration.imageSize else {
            return CalibrationHealth(status: .lost, medianResidual: .infinity, inlierFraction: 0, measuredFraction: 0)
        }
        let measurement = EdgeSampler.measure(raster, boardToImage: calibration.boardToImage,
                                              halfWindow: parameters.profileHalfWindow, radii: calibration.ringRadii,
                                              parameters: parameters)
        let statistics = HandleRefiner.statistics(of: measurement, imageToBoard: calibration.imageToBoard,
                                                  radii: calibration.ringRadii, parameters: parameters)
        let median = statistics.medianAbsolute ?? .infinity
        func health(_ status: CalibrationHealth.Status) -> CalibrationHealth {
            CalibrationHealth(status: status, medianResidual: median, inlierFraction: statistics.inlierFraction,
                              measuredFraction: statistics.measuredFraction)
        }
        let visible = EdgeSampler.visibleFraction(raster, boardToImage: calibration.boardToImage,
                                                  radii: calibration.ringRadii, parameters: parameters)
        if visible < parameters.driftNotVisibleFraction { return health(.edgesNotVisible) }
        let minimumInliers = dartsOnBoard ? parameters.driftHealthyInliersWithDarts : parameters.driftHealthyInliers
        if median <= parameters.driftHealthyMedian, statistics.inlierFraction >= minimumInliers { return health(.healthy) }
        return health(recover(calibration, raster: raster) == nil ? .lost : .drifted)
    }

    private func recover(_ calibration: BoardCalibration, raster: EdgeSamplerRaster) -> BoardCalibration? {
        guard raster.size == calibration.imageSize else { return nil }
        let start = calibration.handles.points.map { SIMD2($0.x, $0.y) }
        guard let transform = CalibrationGeometry.homography(of: start) else { return nil }
        let outcome = refine(raster, from: start, transform: transform, radii: calibration.ringRadii, fitRadii: false,
                             maxShift: parameters.recoverMaxHandleShift, imageSize: calibration.imageSize,
                             intrinsics: calibration.intrinsics)
        guard let accepted = outcome.accepted else { return nil }
        return finish(accepted, userHandles: calibration.handles, imageSize: calibration.imageSize,
                      rotationDegrees: calibration.rotationDegrees, wireHeight: calibration.wireHeight, extraIssues: [])
    }
}

/// A 128-bit digest of the numbers that make a calibration, written as a UUID (version 8, RFC 9562): the identity
/// of a calibration without a system random source, equal for equal inputs (lot V2, private).
private struct CalibrationFingerprint {
    private var a: UInt64 = 0x6A09_E667_F3BC_C908
    private var b: UInt64 = 0xBB67_AE85_84CA_A73B

    mutating func add(_ value: Double) {
        // +0 and −0, and every NaN, hash alike.
        let canonical = value == 0 ? 0 : (value.isNaN ? Double.nan : value)
        add(word: canonical.bitPattern)
    }

    mutating func add(_ value: Int) {
        add(word: UInt64(bitPattern: Int64(value)))
    }

    private mutating func add(word: UInt64) {
        a = CalibrationFingerprint.mix(a ^ word)
        b = CalibrationFingerprint.mix(b &+ (word ^ 0x9E37_79B9_7F4A_7C15))
    }

    /// SplitMix64 finaliser.
    private static func mix(_ value: UInt64) -> UInt64 {
        var z = value &+ 0x9E37_79B9_7F4A_7C15
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    var uuid: UUID {
        var bytes = [UInt8](repeating: 0, count: 16)
        for index in 0..<8 {
            bytes[index] = UInt8(truncatingIfNeeded: a >> (56 - 8 * UInt64(index)))
            bytes[8 + index] = UInt8(truncatingIfNeeded: b >> (56 - 8 * UInt64(index)))
        }
        bytes[6] = (bytes[6] & 0x0F) | 0x80
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }
}
