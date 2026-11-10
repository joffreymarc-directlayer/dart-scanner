import Foundation
import simd
import Testing
import DartCore
import DartVision

extension Tag {
    /// Heavy vision suites (C2, T, X13): run with `swift test -c release`.
    @Tag static var heavy: Self
}

/// Smoke tests of lot F0 on the DartVision skeleton (ARCHITECTURE.md §6.4, VISION.md §9.4): the plain-data
/// members answer for real, with the values of the listing. No algorithmic member is called here: those trap
/// until lots V1 to V5 write them. Everything asserted here stays true afterwards.
@Suite struct SmokeTests {
    private func observation(id: UUID = UUID(uuidString: "00000000-0000-0000-0000-0000000000AA") ?? UUID(),
                             hit: Hit = .treble(20)) -> DartObservation {
        DartObservation(id: id, visit: 2, indexInVisit: 1, timestamp: 12.5, tip: BoardPoint(x: 0.5, y: 103),
                        uncertainty: TipUncertainty(sigmaAlong: 1.5, sigmaAcross: 0.5, axis: SIMD2(0, 1)),
                        candidates: [HitCandidate(hit: hit, probability: 0.9), HitCandidate(hit: .single(20), probability: 0.1)],
                        nearbyHits: [.single(20), .single(1)], confidence: 0.81, tier: .medium, flags: [.warmUp, .clutter],
                        source: .liveCamera)
    }

    // MARK: Initialisers that store their parameters

    @Test func images_storeTheirParameters() {
        let size = PixelSize(width: 4, height: 2)
        #expect(size.width == 4 && size.height == 2 && size == PixelSize(width: 4, height: 2))
        let point = ImagePoint(x: 1.5, y: -2)
        #expect(point.x == 1.5 && point.y == -2)
        let rgb = RGBImage(width: 2, height: 1, pixels: [1, 2, 3, 4, 5, 6])
        #expect(rgb.width == 2 && rgb.height == 1 && rgb.pixels == [1, 2, 3, 4, 5, 6])
        let gray = GrayImage(width: 2, height: 2, pixels: [0, 255, 7, 9])
        #expect(gray.width == 2 && gray.height == 2 && gray.pixels == [0, 255, 7, 9])
        #expect(rgb == RGBImage(width: 2, height: 1, pixels: [1, 2, 3, 4, 5, 6]))
        #expect(gray != GrayImage(width: 2, height: 2, pixels: [0, 255, 7, 8]))
        let canvas = CanvasImage(rgb: rgb, valid: gray)
        #expect(canvas.rgb == rgb && canvas.valid == gray)
    }

    @Test func geometry_storesItsParameters() {
        let intrinsics = CameraIntrinsics(fx: 1500, fy: 1501, cx: 960, cy: 540, source: .fieldOfView)
        #expect(intrinsics.fx == 1500 && intrinsics.fy == 1501 && intrinsics.cx == 960 && intrinsics.cy == 540)
        #expect(intrinsics.source == .fieldOfView)
        let radii = RingRadii(innerBull: 6, outerBull: 16, trebleInner: 98, trebleOuter: 108, doubleInner: 161, doubleOuter: 170)
        #expect(radii.innerBull == 6 && radii.outerBull == 16 && radii.trebleInner == 98 && radii.trebleOuter == 108)
        #expect(radii.doubleInner == 161 && radii.doubleOuter == 170)
        // `CalibrationHandles(points:)` is how lot V1 builds exact handles; they are read back through `points`.
        let points = [ImagePoint(x: 10, y: 20), ImagePoint(x: 30, y: 40), ImagePoint(x: 50, y: 60), ImagePoint(x: 70, y: 80)]
        let handles = CalibrationHandles(points: points)
        #expect(handles.points == points && handles == CalibrationHandles(points: points))
        let info = FrameSourceInfo(size: PixelSize(width: 3840, height: 2160), nominalFramesPerSecond: 30, rotationDegrees: 90,
                                   intrinsics: intrinsics, isLive: true)
        #expect(info.size == PixelSize(width: 3840, height: 2160) && info.nominalFramesPerSecond == 30)
        #expect(info.rotationDegrees == 90 && info.intrinsics == intrinsics && info.isLive)
    }

    @Test func detectionValues_storeTheirParameters() {
        let descriptor = DetectorDescriptor(name: "differencing", version: "1", mode: .differential)
        #expect(descriptor.name == "differencing" && descriptor.version == "1" && descriptor.mode == .differential)
        let none = SceneAnalysis(kind: .noChange)
        #expect(none.kind == .noChange && none.darts.isEmpty && none.removedDartIDs.isEmpty && none.disturbedDartIDs.isEmpty)
        #expect(none.changedBoardFraction == 0 && none.newObjectArea == 0 && none.gain == 1)
        let id = UUID()
        let removal = SceneAnalysis(kind: .removal, removedDartIDs: [id], disturbedDartIDs: [id], changedBoardFraction: 0.2,
                                    newObjectArea: 12, gain: 0.9)
        #expect(removal.kind == .removal && removal.removedDartIDs == [id] && removal.disturbedDartIDs == [id])
        #expect(removal.changedBoardFraction == 0.2 && removal.newObjectArea == 12 && removal.gain == 0.9)
    }

    @Test func observation_storesItsTwelveParameters() throws {
        let id = try #require(UUID(uuidString: "00000000-0000-0000-0000-0000000000AA"))
        let seen = observation(id: id)
        #expect(seen.id == id && seen.visit == 2 && seen.indexInVisit == 1 && seen.timestamp == 12.5)
        #expect(seen.tip == BoardPoint(x: 0.5, y: 103))
        #expect(seen.uncertainty == TipUncertainty(sigmaAlong: 1.5, sigmaAcross: 0.5, axis: SIMD2(0, 1)))
        #expect(seen.uncertainty.sigmaAlong == 1.5 && seen.uncertainty.sigmaAcross == 0.5 && seen.uncertainty.axis == SIMD2(0, 1))
        #expect(seen.candidates == [HitCandidate(hit: .treble(20), probability: 0.9), HitCandidate(hit: .single(20), probability: 0.1)])
        #expect(seen.candidates[0].hit == .treble(20) && seen.candidates[0].probability == 0.9)
        #expect(seen.nearbyHits == [.single(20), .single(1)] && seen.confidence == 0.81 && seen.tier == .medium)
        #expect(seen.flags == [.warmUp, .clutter] && seen.source == .liveCamera)
        let context = ConfidenceContext(warmUpRemaining: 2, thresholds: .standard, cap: 0.84)
        #expect(context.warmUpRemaining == 2 && context.thresholds == ConfidenceThresholds() && context.cap == 0.84)
        let plain = ConfidenceContext()
        #expect(plain.warmUpRemaining == 0 && plain.cap == 1)
    }

    @Test func scanValues_storeTheirParameters() {
        let sample = GateSample(timestamp: 1, motionFraction: 0.002, changeVsReference: 0.01, borderChange: 0.05, meanLuma: 120)
        #expect(sample.timestamp == 1 && sample.motionFraction == 0.002 && sample.changeVsReference == 0.01)
        #expect(sample.borderChange == 0.05 && sample.meanLuma == 120)
        let episode = EpisodeSummary(duration: 0.4, peakMotionFraction: 0.03, borderIntrusionFrames: 2)
        #expect(episode.duration == 0.4 && episode.peakMotionFraction == 0.03 && episode.borderIntrusionFrames == 2)
        #expect(episode == EpisodeSummary(duration: 0.4, peakMotionFraction: 0.03, borderIntrusionFrames: 2))
    }

    @Test func syntheticValues_storeTheirParameters() {
        let style = SyntheticDartStyle(point: SIMD3(200, 200, 205), barrel: SIMD3(90, 90, 95), shaft: SIMD3(20, 20, 20),
                                       flight: SIMD3(220, 40, 40))
        #expect(style.point == SIMD3(200, 200, 205) && style.barrel == SIMD3(90, 90, 95))
        #expect(style.shaft == SIMD3(20, 20, 20) && style.flight == SIMD3(220, 40, 40))
        let dart = SyntheticDart(tip: BoardPoint(x: 0, y: 103), leanUpDegrees: 10, leanSideDegrees: -3, style: style)
        #expect(dart.tip == BoardPoint(x: 0, y: 103) && dart.leanUpDegrees == 10 && dart.leanSideDegrees == -3 && dart.style == style)
        var scene = SyntheticScene()
        #expect(scene.darts.isEmpty && scene.radii == .nominal && scene.wireHeight == 0 && scene.light == nil)
        #expect(scene.shadowStrength == 1 && scene.gain == 1 && scene.noiseSigma == 2 && scene.blurPasses == 1)
        #expect(scene.shift == .zero && scene.hand == nil && scene.seed == 1)
        scene.darts = [dart]
        #expect(scene.darts == [dart])
    }

    // MARK: `init()` of the parameter structures: the defaults of the listing

    @Test func parameterStructures_haveTheDefaultsOfTheListing() {
        let calibration = CalibrationParameters()
        #expect(calibration.hardMinPixelsPerMillimetre == 0.8 && calibration.dartMargin == 135 && calibration.maxIterations == 6)
        #expect(calibration.fitRingRadii && calibration.wireHeight == 0 && calibration.driftNotVisibleFraction == 0.3)
        let locator = ColourBoardLocator.Parameters()
        #expect(locator.workLongSide == 640 && locator.saturationRange == 0.30...0.55 && locator.maxPhaseDisagreementDegrees == 3)
        let detection = DetectionParameters()
        #expect(detection.blurRadius == 1 && detection.shadowLowerBound == 0.40 && detection.maxDartArea == 4000)
        #expect(detection.usePoseForTipEnd && detection.occlusionProbe == 2)
        let confidence = ConfidenceParameters()
        #expect(confidence.gridSide == 21 && confidence.nearbyRadii == [4, 8, 16] && confidence.thresholds == .standard)
        #expect(confidence.warmUpDarts == 3 && confidence.warmUpCap == 0.84 && confidence.scanSuggestionRate == 0.3)
        let scan = ScanParameters()
        #expect(scan.trigger == .automatic && scan.expectedDartsPerVisit == 3 && scan.settleFrames == 6)
        #expect(scan.captureTimeout == 2 && scan.enableDriftCorrection && scan.absoluteMatchRadius == 8)
        let vision = VisionConfiguration()
        #expect(vision.calibration == calibration && vision.detection == detection && vision.confidence == confidence && vision.scan == scan)
        #expect(vision == VisionConfiguration())
        #if canImport(AVFoundation)
        let camera = CameraConfiguration()
        #expect(camera.preset == .uhd4K && camera.framesPerSecond == 30 && camera.mainsFrequency == nil && camera.lockDelay == 1.5)
        #endif
    }

    @Test func visionConfiguration_roundTripsThroughJSON() throws {
        var configuration = VisionConfiguration()
        configuration.detection.shadowLowerBound = 0.33
        configuration.scan.trigger = .manual
        configuration.confidence.thresholds.high = 0.95
        let decoded = try JSONDecoder().decode(VisionConfiguration.self, from: JSONEncoder().encode(configuration))
        #expect(decoded == configuration && decoded != VisionConfiguration())
    }

    // MARK: Constants

    @Test func constants_haveTheValuesOfTheListing() {
        #expect(BoardCanvas.pixelsPerMillimetre == 2 && BoardCanvas.halfExtent == 320 && BoardCanvas.side == 1280)
        #expect(RingRadii.nominal == RingRadii(innerBull: 6.35, outerBull: 15.9, trebleInner: 99, trebleOuter: 107,
                                               doubleInner: 162, doubleOuter: 170))
        // The nominal radii are those of `BoardGeometry.standard`.
        let board = BoardGeometry.standard
        #expect(RingRadii.nominal.innerBull == board.innerBullRadius && RingRadii.nominal.outerBull == board.outerBullRadius)
        #expect(RingRadii.nominal.trebleInner == board.trebleInnerRadius && RingRadii.nominal.trebleOuter == board.trebleOuterRadius)
        #expect(RingRadii.nominal.doubleInner == board.doubleInnerRadius && RingRadii.nominal.doubleOuter == board.doubleOuterRadius)
        #expect(DetectionParameters.default == DetectionParameters())
        #expect(ConfidenceThresholds.standard == ConfidenceThresholds())
        #expect(ConfidenceThresholds.standard.high == 0.85 && ConfidenceThresholds.standard.medium == 0.50)
    }

    @Test func dartFlags_nineteenOptions_oneBitEachInListingOrder() {
        let flags: [DartFlags] = [
            .pointNotVisible, .lowTipContrast, .implausiblyLong, .lowElongation, .nearEndWide, .tipEndAmbiguous,
            .fewNarrowPixels, .clutter, .tipPossiblyOccluded, .earlierDartDisturbed, .beyondVisitLimit,
            .emptyReferenceStale, .nearCanvasEdge, .afterRelock, .warmUp, .multiDartStill, .crossViewpoint,
            .calibrationFair, .calibrationPoor,
        ]
        #expect(flags.count == 19)
        for (index, flag) in flags.enumerated() {
            #expect(flag.rawValue == UInt32(1) << UInt32(index))
            #expect(flag == DartFlags(rawValue: 1 << index))
        }
        #expect(DartFlags.pointNotVisible.rawValue == 1 && DartFlags.calibrationPoor.rawValue == 1 << 18)
        let both: DartFlags = [.warmUp, .calibrationPoor]
        #expect(both.contains(.warmUp) && both.contains(.calibrationPoor) && !both.contains(.clutter))
        #expect(both.rawValue == (1 << 14) | (1 << 18) && DartFlags().isEmpty)
    }

    // MARK: Constant tables

    @Test func calibrationHandle_boardPointsAndLabels() {
        #expect(CalibrationHandle.allCases == [.wire20_1, .wire6_10, .wire3_19, .wire11_14])
        #expect(CalibrationHandle.allCases.map(\.label) == ["20", "6", "3", "11"])
        // (170 sin a, 170 cos a) for a = 9, 99, 189, 279 degrees.
        let expected: [(x: Double, y: Double)] = [(26.59, 167.91), (167.91, -26.59), (-26.59, -167.91), (-167.91, 26.59)]
        for (handle, point) in zip(CalibrationHandle.allCases, expected) {
            let board = handle.boardPoint
            #expect(abs(board.x - point.x) < 0.005 && abs(board.y - point.y) < 0.005, "\(handle)")
            // On the outer double wire, on a radial wire between two sectors.
            #expect(abs((board.x * board.x + board.y * board.y).squareRoot() - 170) < 1e-9)
        }
        let degrees = [9.0, 99, 189, 279]
        for (handle, a) in zip(CalibrationHandle.allCases, degrees) {
            #expect(abs(handle.boardPoint.x - 170 * sin(a * .pi / 180)) < 1e-9)
            #expect(abs(handle.boardPoint.y - 170 * cos(a * .pi / 180)) < 1e-9)
        }
    }

    @Test func calibrationIssue_theFirstFiveAreBlocking() {
        let blocking: [CalibrationIssue] = [.handlesMirrored, .quadNotConvex, .horizonCrossesBoard, .boardOutOfFrame, .resolutionTooLow]
        #expect(CalibrationIssue.allCases.count == 13)
        #expect(CalibrationIssue.allCases.filter(\.isBlocking) == blocking)
        #expect(Array(CalibrationIssue.allCases.prefix(5)) == blocking)
    }

    // MARK: Comparable

    @Test func gradesAndTiers_areOrdered() {
        #expect(CalibrationQuality.Grade.poor < .fair && CalibrationQuality.Grade.fair < .good)
        #expect(!(CalibrationQuality.Grade.good < .good) && [CalibrationQuality.Grade.good, .poor, .fair].sorted() == [.poor, .fair, .good])
        #expect(ConfidenceTier.low < .medium && ConfidenceTier.medium < .high)
        #expect([ConfidenceTier.high, .low, .medium].max() == .high && [ConfidenceTier.high, .low, .medium].min() == .low)
    }

    // MARK: Values that tests compare with `==`

    @Test func scanCommands_compareByValue() {
        let id = UUID()
        let commands: [ScanCommand] = [.setTrigger(.automatic), .arm(boardConfirmedEmpty: true), .beginVisit(expectedDarts: 3),
                                       .discardDart(id), .pause(.background), .resume]
        #expect(commands == [.setTrigger(.automatic), .arm(boardConfirmedEmpty: true), .beginVisit(expectedDarts: 3),
                             .discardDart(id), .pause(.background), .resume])
        #expect(ScanCommand.arm(boardConfirmedEmpty: true) != .arm(boardConfirmedEmpty: false))
        #expect(ScanCommand.pause(.user) != .pause(.background) && ScanCommand.pause(.thermal) != .pause(.background))
        #expect(ScanCommand.captureNow(maxDarts: 3) != .captureNow(maxDarts: 2) && ScanCommand.endVisit != .rebaseline)
        #expect(ScanCommand.setTrigger(.manual) != .setTrigger(.automatic))
        #expect(Set<ScanCommand>([.resume, .resume, .confirmBoardEmpty, .registerManualDart, .captureReference]).count == 4)
    }

    @Test func scanStates_carryTheReasonOfAPause() {
        #expect(ScanState.paused(.user) != .paused(.background) && ScanState.paused(.background) != .paused(.thermal))
        #expect(ScanState.paused(.user) == .paused(.user))
        #expect(ScanState.watching(dartsOnBoard: 2) != .watching(dartsOnBoard: 3) && ScanState.idle != .arming)
    }

    @Test func observationsEventsInputsAndEffects_compareByValue() {
        let id = UUID()
        let seen = observation(id: id)
        #expect(seen == observation(id: id))
        #expect(seen != observation(id: id, hit: .treble(5)) && seen != observation(id: UUID()))
        // ScanEvent
        #expect(ScanEvent.dart(seen) == .dart(observation(id: id)) && ScanEvent.dart(seen) != .dart(observation(id: UUID())))
        #expect(ScanEvent.stateChanged(.paused(.user)) != .stateChanged(.paused(.background)))
        #expect(ScanEvent.dartRemoved(id: id, reason: .fellOut) != .dartRemoved(id: id, reason: .takeout))
        #expect(ScanEvent.scanCompleted([seen]) != .scanCompleted([]) && ScanEvent.takeoutStalled(remaining: [id]) == .takeoutStalled(remaining: [id]))
        #expect(ScanEvent.advisory(.lowLight) != .advisory(.flicker) && ScanEvent.possibleMiss(timestamp: 1) != .possibleMiss(timestamp: 2))
        // SettleOutcome
        #expect(SettleOutcome.darts(new: [seen], removed: [], disturbed: [id]) == .darts(new: [seen], removed: [], disturbed: [id]))
        #expect(SettleOutcome.removed([id], boardEmpty: true) != .removed([id], boardEmpty: false) && SettleOutcome.noChange != .obstruction)
        // ScanInput
        let sample = GateSample(timestamp: 1, motionFraction: 0, changeVsReference: 0, borderChange: 0, meanLuma: 100)
        #expect(ScanInput.gate(sample) == .gate(sample) && ScanInput.command(.resume) != .command(.pause(.user)))
        #expect(ScanInput.settle(.noChange, timestamp: 1) != .settle(.noChange, timestamp: 2))
        #expect(ScanInput.calibrationHealth(.drifted, recovered: true, timestamp: 3) != .calibrationHealth(.lost, recovered: true, timestamp: 3))
        #expect(ScanInput.armed != .calibrationSet)
        // ScanEffect
        #expect(ScanEffect.emit(.dart(seen)) == .emit(.dart(seen)) && ScanEffect.emit(.takeoutCompleted) != .emit(.takeoutStarted))
        #expect(ScanEffect.analyse(maxNewDarts: 1) != .analyse(maxNewDarts: 3))
        #expect(ScanEffect.updateReference(.rolling) != .updateReference(.rollingAndEmpty) && ScanEffect.beginAccumulation != .discardAccumulation)
        #expect(Set<ScanEffect>([.setGateReference, .setGateReference, .checkCalibration]).count == 2)
    }

    /// Proves only that the tag of the heavy suites exists under this name, which is what lots V2, V3 and V5
    /// write. That it is declared ONCE is checked by the compiler: a second declaration stops the build.
    @Test func heavyTag_isDeclared() {
        let tags: Set<Tag> = [.heavy, .heavy]
        #expect(tags.count == 1 && tags.contains(.heavy))
    }
}
