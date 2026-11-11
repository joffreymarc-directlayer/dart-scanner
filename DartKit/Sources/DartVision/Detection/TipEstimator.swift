import Foundation
import simd
import DartCore

/// Steps D6 to D9 of VISION.md §5.2: which end is the tip, the refit on the narrow part, the walk towards the tip
/// on the evidence map, and the plausibility flags. Internal to DartVision (lot V3).
enum TipEstimator {
    /// What the steps give for one dart, in metric board millimetres.
    struct Estimate: Sendable {
        /// X̂, after the cap correction and the lateral correction.
        var tip: SIMD2<Double>
        /// Unit vector from the flight towards the tip (the refit line, oriented).
        var towardsTip: SIMD2<Double>
        /// Far end of the silhouette, on the refit line (the flight side).
        var tail: SIMD2<Double>
        var visibleLength: Double
        var occlusionSpan: Double
        var flags: DartFlags
        /// Canvas indices crossed by the walk between the end of the mask and the tip (the walked corridor).
        var corridor: [Int]
    }

    /// Everything the steps read besides the dart's own pixels.
    struct Context {
        var evidence: ChangeEvidence
        /// Union of the known silhouettes, dilated as in D3.
        var knownSilhouettes: CanvasMask
        var footPoint: BoardPoint
        var cameraDistance: Double
        var parameters: DetectionParameters
    }

    // MARK: D6

    /// Which end of the D5 line is the tip, and the flags of D6. Returns the line oriented towards the tip.
    static func orient(_ line: BlobAnalysis.Line, pixels: BlobAnalysis.Pixels, context: Context)
        -> (line: BlobAnalysis.Line, flags: DartFlags) {
        let parameters = context.parameters
        let profile = WidthProfile(points: pixels.points, line: line)
        let count = profile.widths.count
        let endSlices = max(1, Int((parameters.endFraction * Double(count)).rounded()))
        // Width of an end: its widest part, a running mean over three slices. The mean of all the end's slices
        // (the literal reading of D6) misses the flight whenever its edge-on plate projects beyond the broad plate
        // as a 2 mm sliver along the axis, which in the synthetic views runs up to 17 slices past the flight.
        let lowWidth = profile.widestPart(of: 0..<min(count, endSlices))
        let highWidth = profile.widestPart(of: max(0, count - endSlices)..<count)
        let lowEnd = line.mean + profile.minimum * line.direction
        let highEnd = line.mean + profile.maximum * line.direction

        // Rule 1: an identified flight.
        var byWidth: Bool?   // true: the tip is the high end
        if highWidth >= parameters.flightMinWidth, highWidth >= parameters.flightWidthRatio * lowWidth {
            byWidth = false
        } else if lowWidth >= parameters.flightMinWidth, lowWidth >= parameters.flightWidthRatio * highWidth {
            byWidth = true
        }
        // Rule 2: the end nearer to the camera foot point, when the view is oblique enough at the centroid.
        var byPose: Bool?
        if parameters.usePoseForTipEnd, context.cameraDistance > 0 {
            let foot = SIMD2(context.footPoint.x, context.footPoint.y)
            let tan = simd_length(line.mean - foot) / context.cameraDistance
            if tan >= parameters.poseMinTanObliquity {
                byPose = simd_length(highEnd - foot) < simd_length(lowEnd - foot)
            }
        }
        var flags: DartFlags = []
        let tipIsHigh: Bool
        if let byWidth {
            tipIsHigh = byWidth
            if let byPose, byPose != byWidth { flags.insert(.tipEndAmbiguous) }
        } else {
            if let byPose {
                tipIsHigh = byPose
            } else {
                // Rule 3: only one end on the board. Rule 4: the end nearer to the centre, flagged.
                let highOn = simd_length(highEnd) <= parameters.onBoardRadius
                let lowOn = simd_length(lowEnd) <= parameters.onBoardRadius
                if highOn != lowOn {
                    tipIsHigh = highOn
                } else {
                    tipIsHigh = simd_length(highEnd) <= simd_length(lowEnd)
                    flags.insert(.tipEndAmbiguous)
                }
            }
            if (tipIsHigh ? highWidth : lowWidth) > parameters.flightMinWidth { flags.insert(.nearEndWide) }
        }
        return (tipIsHigh ? line : line.reversed, flags)
    }

    // MARK: D7

    /// The line through the narrow part near the tip: the pixels of the `narrowPartFraction` of the length nearest
    /// to the tip whose slice is at most `narrowMaxWidth` wide, principal axis, then three Huber passes. Nil (and the
    /// flag `fewNarrowPixels`) below `narrowMinPixels` pixels. The result keeps the orientation of `line`.
    static func narrowLine(_ line: BlobAnalysis.Line, pixels: BlobAnalysis.Pixels,
                           parameters: DetectionParameters) -> BlobAnalysis.Line? {
        let profile = WidthProfile(points: pixels.points, line: line)
        let length = profile.maximum - profile.minimum
        let start = profile.maximum - parameters.narrowPartFraction * length
        var narrow: [SIMD2<Double>] = []
        for (position, point) in pixels.points.enumerated() {
            let t = profile.along[position]
            guard t >= start else { continue }
            if profile.widths[profile.slice(of: t)] <= parameters.narrowMaxWidth {
                narrow.append(point)
            }
        }
        guard narrow.count >= max(2, parameters.narrowMinPixels), var refit = BlobAnalysis.fit(narrow) else { return nil }
        let k = max(1e-6, parameters.narrowHuberK)
        for _ in 0..<3 {
            let weights = narrow.map { point -> Double in
                let d = abs(refit.across(point))
                return d <= k ? 1 : k / d
            }
            guard let next = BlobAnalysis.fit(narrow, weights: weights) else { break }
            refit = next
        }
        if simd_dot(refit.direction, line.direction) < 0 { refit = refit.reversed }
        return refit
    }

    // MARK: D8 and D9

    /// The walk towards the tip on the evidence map, the cap correction, the lateral correction and the flags of
    /// D9 that need the tip. `line` is the refit line oriented towards the tip; `orientedLine` the D5 line.
    static func estimate(pixels: BlobAnalysis.Pixels, line: BlobAnalysis.Line, elongation: BlobAnalysis.Line,
                         context: Context) -> Estimate {
        let parameters = context.parameters
        let evidence = context.evidence
        let tau = evidence.threshold
        let u = line.direction, n = line.normal
        var flags: DartFlags = []

        // End of the mask on the axis: the farthest pixel towards the tip close to the line.
        let near = parameters.walkCorridorHalfWidth + 1
        var maskEnd = -Double.infinity, maskStart = Double.infinity
        var anyEnd = -Double.infinity
        for point in pixels.points {
            let t = line.along(point)
            maskStart = min(maskStart, t)
            anyEnd = max(anyEnd, t)
            if abs(line.across(point)) <= near { maskEnd = max(maskEnd, t) }
        }
        if !maskEnd.isFinite { maskEnd = anyEnd }
        if !maskEnd.isFinite { maskEnd = 0 }
        if !maskStart.isFinite { maskStart = maskEnd }

        // 1. P(t): the largest evidence across ±walkCorridorHalfWidth, every walkStep mm.
        let step = max(0.01, parameters.walkStep)
        let first = maskEnd - parameters.walkBack
        let sampleCount = max(1, Int(((parameters.walkBack + parameters.walkAhead) / step).rounded()) + 1)
        let lateralCount = max(1, Int((2 * parameters.walkCorridorHalfWidth / step).rounded()) + 1)
        let lateralStep = lateralCount > 1 ? 2 * parameters.walkCorridorHalfWidth / Double(lateralCount - 1) : 0
        let half = 0.5 * tau
        var profile: [Double] = []
        profile.reserveCapacity(sampleCount)
        var lastAbove: Int?
        var stopIndex = sampleCount
        var occluded = false
        var occlusionSpan = 0.0
        var wasInside = context.knownSilhouettes.contains(BoardPoint(x: (line.mean + first * u).x, y: (line.mean + first * u).y))
        var touchesEdge = false
        for index in 0..<sampleCount {
            let t = first + Double(index) * step
            let centre = line.mean + t * u
            var value = 0.0
            for lateral in 0..<lateralCount {
                let s = -parameters.walkCorridorHalfWidth + Double(lateral) * lateralStep
                value = max(value, evidence.sample(centre + s * n))
            }
            // 2. Stop after a gap longer than walkGap.
            if value < half, let last = lastAbove, Double(index - last) * step > parameters.walkGap {
                stopIndex = index
                break
            }
            // Stop where the walk enters the dilated silhouette of a known dart.
            let inside = context.knownSilhouettes.contains(BoardPoint(x: centre.x, y: centre.y))
            if inside, !wasInside, index > 0 {
                occluded = true
                occlusionSpan = chord(from: t, line: line, silhouettes: context.knownSilhouettes, step: step)
                stopIndex = index
                break
            }
            wasInside = inside
            if !isValidCanvas(centre, evidence: evidence) { touchesEdge = true }
            profile.append(value)
            if value >= half { lastAbove = index }
        }
        let endIndex = lastAbove ?? min(profile.count - 1, max(0, Int((parameters.walkBack / step).rounded())))
        let tEnd = first + Double(max(0, endIndex)) * step

        // 3. Level and crossing.
        let window = max(1, Int((Lengths.tipContrastLength / step).rounded()))
        let tail = profile.isEmpty ? [] : Array(profile[max(0, endIndex - window)...max(0, min(endIndex, profile.count - 1))])
        let contrast = detectionMedian(tail) ?? 0
        let level = max(half, 0.5 * contrast)
        var crossing = tEnd
        if !profile.isEmpty {
            var index = min(endIndex, profile.count - 1)
            while index > 0, profile[index] < level { index -= 1 }
            crossing = first + Double(index) * step
            if index + 1 < profile.count, profile[index] >= level, profile[index + 1] < level {
                crossing += (profile[index] - level) / (profile[index] - profile[index + 1]) * step
            }
        }

        // 4. Lateral correction: centroid of e across ±lateralHalfWidth, 1 mm before the crossing. The refit line can
        // pass a millimetre or two beside the point (a few degrees of tilt over the length of the barrel); a single
        // window centred on the line then cuts the point's profile and under-corrects. The centroid is therefore
        // iterated with the window re-centred on it (a mean shift), and the noise floor (half of τ) is left out of
        // the weights so that it does not pull the result back towards the line.
        let probe = line.mean + (crossing - 1) * u
        let lateralSamples = max(1, Int((2 * parameters.lateralHalfWidth / step).rounded()) + 1)
        let lateralSpacing = lateralSamples > 1 ? 2 * parameters.lateralHalfWidth / Double(lateralSamples - 1) : 0
        var lateral = 0.0
        for _ in 0..<Lengths.lateralIterations {
            var weighted = 0.0, total = 0.0
            for index in 0..<lateralSamples {
                let s = lateral - parameters.lateralHalfWidth + Double(index) * lateralSpacing
                let e = max(0, evidence.sample(probe + s * n) - half)
                weighted += s * e
                total += e
            }
            guard total > 0 else { break }
            let next = weighted / total
            let moved = abs(next - lateral)
            lateral = next
            if moved < Lengths.lateralTolerance { break }
        }
        if abs(lateral) > Lengths.lateralLimit { lateral = 0 }

        // 5. Cap correction.
        let tip = line.mean + (crossing - parameters.tipCapCorrection) * u + lateral * n

        // D9.
        if occluded { flags.insert(.tipPossiblyOccluded) }
        // The visible part of the dart ends against an earlier dart on its tip side: whichever way the walk went,
        // the tip may be behind it.
        if TipEstimator.tipSideTouches(pixels, line: line, end: maskEnd, reach: parameters.walkBack,
                                       silhouettes: context.knownSilhouettes) {
            flags.insert(.tipPossiblyOccluded)
        }
        let beyond = tip + parameters.occlusionProbe * u
        if context.knownSilhouettes.contains(BoardPoint(x: beyond.x, y: beyond.y)) { flags.insert(.tipPossiblyOccluded) }
        if contrast < parameters.lowContrastRatio * tau { flags.insert(.lowTipContrast) }

        // Camouflage: just beyond the end, would the point itself still be visible against the board? A steel point
        // over a steel-coloured wire, or a black point over a black bed, leaves no evidence: the walk stops there
        // although the tip may go on. The posterior is then spread over the camouflaged stretch, exactly as over a
        // stretch hidden by an earlier dart (section 7.1), and the tip counts as one of limited visibility (without
        // the flag, eight hard-shadow ends of 500 were high and wrong instead of three).
        var hiddenSpan = occluded ? occlusionSpan : 0
        var corrected = line
        corrected.mean += lateral * n
        let camouflage = TipEstimator.camouflagedLength(beyond: crossing, line: corrected, evidence: evidence, parameters: parameters)
        if camouflage > 0 {
            flags.insert(.lowTipContrast)
            hiddenSpan = max(hiddenSpan, camouflage + Lengths.camouflageMargin)
        }

        // A dim end made of pure darkening, deeper than the shadow model allows, is the end of a hard shadow and not a
        // point: the "dart" is a dart plus its shadow. That is the case `implausiblyLong` stands for.
        if contrast < parameters.lowContrastRatio * tau,
           TipEstimator.endIsShadow(from: tEnd - Lengths.tipContrastLength, to: tEnd, line: line, evidence: evidence,
                                    parameters: parameters) {
            flags.insert(.implausiblyLong)
        }
        // The same end on a bright bed (review RV2): a hard shadow there keeps its full contrast, so the test above
        // never runs, and the walk follows the shadow of the point (or a piece of shadow detached from the dart) to its
        // far end. Under a 0.20 shadow, 3 to 5 darts of 18 that came out high were wrong by 2 to 66 mm this way.
        if TipEstimator.endIsForeignDarkening(crossing: crossing, start: maskStart, line: corrected, evidence: evidence,
                                              parameters: parameters) {
            flags.insert(.implausiblyLong)
        }

        // Width of the last `pointCheckLength` mm before the tip, on 1 mm slices of P along the refit line. In each
        // slice only the pixels whose evidence reaches half the slice's peak count: τ is a small fraction of the
        // contrast of a steel point, so the bare mask also holds the blurred fringe, which is wider along a diagonal
        // of the pixel grid than along its rows (2.0 to 4.6 mm for the same 2.3 mm point). At half the peak the
        // width is that of the object: about 2.5 mm for a point, 7 mm for a barrel.
        let tipAlong = crossing - parameters.tipCapCorrection
        let pointWidth = TipEstimator.coreWidth(of: pixels, line: line, from: tipAlong - parameters.pointCheckLength,
                                                to: tipAlong, evidence: evidence)
        if let pointWidth, pointWidth > parameters.pointMaxWidth { flags.insert(.pointNotVisible) }

        let visibleLength = max(0, maskEnd - maskStart) + 1 / BoardCanvas.pixelsPerMillimetre
        if context.cameraDistance > parameters.maxDartLength {
            let foot = SIMD2(context.footPoint.x, context.footPoint.y)
            let l = parameters.maxDartLength, d = context.cameraDistance
            let longest = simd_length(tip - foot) * l / (d - l) + l * tan(parameters.maxLeanDegrees * .pi / 180) * d / (d - l)
            if visibleLength > longest { flags.insert(.implausiblyLong) }
        }
        let ratio = elongation.smallVariance > 0 ? elongation.largeVariance / elongation.smallVariance : .infinity
        if visibleLength < parameters.minVisibleLength || ratio < parameters.minElongation { flags.insert(.lowElongation) }

        // nearCanvasEdge: P or the walk up to the tip touches an invalid pixel.
        if touchesEdge || touchesInvalid(pixels.indices, evidence: evidence) { flags.insert(.nearCanvasEdge) }

        // The walked corridor, from the end of the mask to the tip.
        var corridor: [Int] = []
        if crossing > maskEnd {
            var t = maskEnd
            while t <= crossing {
                var s = -parameters.walkCorridorHalfWidth
                while s <= parameters.walkCorridorHalfWidth {
                    if let index = canvasIndex(of: line.mean + t * u + s * n) { corridor.append(index) }
                    s += 1 / BoardCanvas.pixelsPerMillimetre
                }
                t += 1 / BoardCanvas.pixelsPerMillimetre
            }
        }
        _ = stopIndex
        return Estimate(tip: tip, towardsTip: u, tail: line.mean + maskStart * u, visibleLength: visibleLength,
                        occlusionSpan: hiddenSpan, flags: flags, corridor: corridor)
    }

    // MARK: Helpers

    /// Lengths used by the walk.
    enum Lengths {
        /// The last millimetres before the end over which the tip contrast is measured (D8 step 3, D9).
        static let tipContrastLength: Double = 3
        /// Longest chord measured through a known silhouette, mm.
        static let longestChord: Double = 60
        /// Passes of the lateral mean shift (D8 step 4), and the move below which it stops, mm.
        static let lateralIterations = 4
        static let lateralTolerance: Double = 0.05
        /// A lateral correction larger than this left the dart: it is not applied, mm.
        static let lateralLimit: Double = 5
        /// Point colour is read this far before the crossing, mm (the core of the point, away from its blurred end).
        static let pointColourOffsets: [Double] = [1.0, 1.5, 2.0]
        /// A camouflaged stretch must start within the reach of the walk's gap bridging (`walkGap`) of the crossing:
        /// after two blurs a 1.4 mm wire between a black and a cream bed is a ramp of about 4 mm, and the point
        /// becomes indistinguishable from it only part of the way along.
        /// Allowance, beyond `walkGap`, for the blurred ramp of a wire between the end of the walk and a camouflaging
        /// bed (a black point over a wire, then a black bed), mm.
        static let camouflageRamp: Double = 2
        /// Longest camouflaged stretch measured, mm: the visible length of a point.
        static let longestCamouflage: Double = 22
        /// Added to a camouflaged stretch: the radius of a point, whose end disc is not seen either, mm.
        static let camouflageMargin: Double = 1.15
        /// A dark end at least this long behind the crossing is not the blurred end of a silver point, mm (review
        /// RV2: under 0.5 mm for every dart without a hard shadow, 1 mm and more for the shadows of points).
        static let minimumDarkEnd: Double = 0.75
        /// A coloured part that starts within this fraction of the silhouette behind the tip is the point or the
        /// barrel of a coloured dart; the first colour of a black dart is its flight, further back (review RV2,
        /// measured: no dart without a hard shadow lost the high tier, 7 of 8 high and wrong darts under one did).
        static let colourOnsetFraction: Double = 0.4
        /// Half-width of the search for the coloured part behind a dark end, mm (review RV2).
        static let onsetHalfWidth: Double = 4
    }

    /// Distance of `c` to the shadow segment of `r` (D2): `‖c − clamp(α*, lo·g, hi·g)·r‖`.
    static func shadowModelDistance(_ c: SIMD3<Float>, _ r: SIMD3<Float>, gain: Double, parameters: DetectionParameters) -> Float {
        let alpha = simd_dot(c, r) / (simd_dot(r, r) + 1)
        let low = Float(parameters.shadowLowerBound * gain), high = Float(parameters.shadowUpperBound * gain)
        let a = alpha < low ? low : (alpha > high ? high : alpha)
        return simd_length(c - a * r)
    }

    /// Bilinear colour of a canvas image at a metric point; nil outside.
    static func colour(_ image: RGBImage, at point: SIMD2<Double>) -> SIMD3<Float>? {
        let pixel = BoardCanvas.pixel(for: BoardPoint(x: point.x, y: point.y))
        guard pixel.x.isFinite, pixel.y.isFinite else { return nil }
        return image.sample(x: pixel.x, y: pixel.y)
    }

    /// Length of the stretch of the axis, starting within `walkGap + camouflageRamp` of `crossing`, over which the
    /// colour of the point (read on the current canvas just before the crossing) is within τ of the reference under
    /// the shadow model: where the point would leave no evidence. 0 when the point stays visible.
    ///
    /// Stopping the search at the first position where the point would have been seen (the stricter reading) was
    /// tried: the hidden stretches it drops are mostly real (all-black darts on black beds fell from 90 % to 79 % of
    /// right beds), so the reach is kept.
    static func camouflagedLength(beyond crossing: Double, line: BlobAnalysis.Line, evidence: ChangeEvidence,
                                  parameters: DetectionParameters) -> Double {
        let u = line.direction
        var samples: [SIMD3<Float>] = []
        for offset in Lengths.pointColourOffsets {
            let position = line.mean + (crossing - offset) * u
            // Only a pixel that changed shows the point; anything else is the board beside it.
            guard evidence.sample(position) >= evidence.threshold,
                  let c = colour(evidence.blurredCurrent, at: position) else { continue }
            samples.append(c)
        }
        guard !samples.isEmpty else { return 0 }
        // Channel-wise median of the samples.
        func median(_ values: [Float]) -> Float { values.sorted()[values.count / 2] }
        let point = SIMD3(median(samples.map(\.x)), median(samples.map(\.y)), median(samples.map(\.z)))
        let step = max(0.05, parameters.walkStep)
        let tau = Float(evidence.threshold)
        let reach = parameters.walkGap + Lengths.camouflageRamp
        var start: Double?
        var end = 0.0
        var delta = step
        while delta <= Lengths.longestCamouflage {
            defer { delta += step }
            guard let r = colour(evidence.blurredReference, at: line.mean + (crossing + delta) * u) else { break }
            if shadowModelDistance(point, r, gain: evidence.gain, parameters: parameters) < tau {
                if start == nil {
                    guard delta <= reach else { break }
                    start = delta
                }
                end = delta
            } else if start != nil || delta > reach {
                break
            }
        }
        guard let start else { return 0 }
        return end - start + step
    }

    /// True when most of the evidence on the axis over `[from, to]` is a pure darkening deeper than the shadow
    /// model: `α* < shadowLowerBound·g` with the colour otherwise unchanged (`‖c − α*·r‖ < τ`).
    static func endIsShadow(from start: Double, to end: Double, line: BlobAnalysis.Line, evidence: ChangeEvidence,
                            parameters: DetectionParameters) -> Bool {
        let step = max(0.05, parameters.walkStep)
        let tau = Float(evidence.threshold)
        let low = Float(parameters.shadowLowerBound * evidence.gain)
        let lateralCount = max(1, Int((2 * parameters.walkCorridorHalfWidth / step).rounded()) + 1)
        let lateralStep = lateralCount > 1 ? 2 * parameters.walkCorridorHalfWidth / Double(lateralCount - 1) : 0
        var counted = 0, shadows = 0
        var t = start
        while t <= end {
            defer { t += step }
            // The sample the walk followed: the strongest evidence across the corridor.
            let centre = line.mean + t * line.direction
            var best = centre, strongest = -1.0
            for lateral in 0..<lateralCount {
                let point = centre + (-parameters.walkCorridorHalfWidth + Double(lateral) * lateralStep) * line.normal
                let e = evidence.sample(point)
                if e > strongest {
                    strongest = e
                    best = point
                }
            }
            guard strongest >= 0.5 * evidence.threshold,
                  let c = colour(evidence.blurredCurrent, at: best), let r = colour(evidence.blurredReference, at: best) else { continue }
            counted += 1
            let alpha = simd_dot(c, r) / (simd_dot(r, r) + 1)
            if alpha < low, simd_length(c - alpha * r) < tau { shadows += 1 }
        }
        return counted > 0 && 2 * shadows >= counted
    }

    /// True when the end of the walk is a darkening deeper than the shadow model that is not the point of the dart
    /// (review RV2): a hard shadow cast beyond the tip, or a piece of it lying further along the axis, taken for the
    /// point.
    ///
    /// From `crossing` towards the flight, each `walkStep` reads the strongest evidence across the walk corridor, as
    /// the walk does. The dark end is the stretch, from the crossing, of evidence of at least half of τ whose colour
    /// is darker than `shadowLowerBound·g` times the reference (`α* < α_lo·g`), gaps up to `walkGap` bridged. A dart
    /// whose point is silver shows its own colour there (`α*` of 0.9 or more on every bed): the stretch is empty.
    /// When it is at least `Lengths.minimumDarkEnd` long, the first evidence of at least τ that is not such a
    /// darkening is looked for behind it, across the wider `Lengths.onsetHalfWidth` (the refit line may pass a few
    /// millimetres beside the body far from the point) and over gaps of any length. Found within the tip-side
    /// `Lengths.colourOnsetFraction` of the silhouette (`crossing − start`), it is the point or the barrel of a
    /// coloured dart, and the dark end ahead of it a shadow (or a black point on a coloured barrel, never scored high
    /// anyway: section 11.1, limit 5). Further back it is the flight of a black dart, dark over its point, barrel and
    /// shaft, which is not flagged.
    static func endIsForeignDarkening(crossing: Double, start: Double, line: BlobAnalysis.Line, evidence: ChangeEvidence,
                                      parameters: DetectionParameters) -> Bool {
        let total = crossing - start
        guard total.isFinite, total > 0 else { return false }
        let step = max(0.05, parameters.walkStep)
        let tau = evidence.threshold
        let half = 0.5 * tau
        let low = Float(parameters.shadowLowerBound * evidence.gain)
        /// The strongest evidence across `±halfWidth` at `distance` behind the crossing, and whether it is a darkening
        /// deeper than the shadow model; nil when it is under half of τ.
        func reading(at distance: Double, halfWidth: Double) -> (evidence: Double, dark: Bool)? {
            let count = max(1, Int((2 * halfWidth / step).rounded()) + 1)
            let spacing = count > 1 ? 2 * halfWidth / Double(count - 1) : 0
            let centre = line.mean + (crossing - distance) * line.direction
            var best = centre, strongest = -1.0
            for lateral in 0..<count {
                let point = centre + (-halfWidth + Double(lateral) * spacing) * line.normal
                let e = evidence.sample(point)
                if e > strongest {
                    strongest = e
                    best = point
                }
            }
            guard strongest >= half, let c = colour(evidence.blurredCurrent, at: best),
                  let r = colour(evidence.blurredReference, at: best) else { return nil }
            return (strongest, simd_dot(c, r) / (simd_dot(r, r) + 1) < low)
        }
        // The dark end.
        var darkEnd = 0.0
        var gap = 0.0
        var distance = 0.0
        while distance <= total {
            if let sample = reading(at: distance, halfWidth: parameters.walkCorridorHalfWidth) {
                guard sample.dark else { break }
                darkEnd = distance
                gap = 0
            } else {
                gap += step
                if gap > parameters.walkGap { break }
            }
            distance += step
        }
        guard darkEnd >= Lengths.minimumDarkEnd else { return false }
        // The first coloured evidence behind it, in the tip-side part of the silhouette.
        distance = darkEnd + step
        while distance < Lengths.colourOnsetFraction * total {
            if let sample = reading(at: distance, halfWidth: Lengths.onsetHalfWidth), !sample.dark, sample.evidence >= tau {
                return true
            }
            distance += step
        }
        return false
    }

    /// True when, on the tip side, the dart's own pixels (the last `walkBack` mm before the end of the mask) touch the
    /// dilated silhouette of a known dart: the visible part is cut short by an earlier dart, which may hide the tip.
    static func tipSideTouches(_ pixels: BlobAnalysis.Pixels, line: BlobAnalysis.Line, end: Double, reach: Double,
                               silhouettes: CanvasMask) -> Bool {
        guard !silhouettes.isEmpty else { return false }
        let side = BoardCanvas.side
        for (position, point) in pixels.points.enumerated() where line.along(point) >= end - reach {
            let index = pixels.indices[position]
            let x = index % side, y = index / side
            for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                let nx = x + dx, ny = y + dy
                guard nx >= 0, ny >= 0, nx < side, ny < side else { continue }
                if silhouettes.contains(x: nx, y: ny) { return true }
            }
        }
        return false
    }

    /// Mean width, over the occupied 1 mm slices of `[start, end)` along `line`, of the pixels of the set whose
    /// evidence is at least half the largest evidence of their slice (lateral extent plus one pixel). Nil when no
    /// slice is occupied.
    static func coreWidth(of pixels: BlobAnalysis.Pixels, line: BlobAnalysis.Line, from start: Double, to end: Double,
                          evidence: ChangeEvidence) -> Double? {
        let count = max(1, Int((end - start).rounded(.up)))
        var members: [[(across: Double, value: Float)]] = Array(repeating: [], count: count)
        for (position, point) in pixels.points.enumerated() {
            let t = line.along(point)
            guard t >= start, t < end else { continue }
            let slice = min(count - 1, Int(t - start))
            members[slice].append((line.across(point), evidence.values[pixels.indices[position]]))
        }
        var sum = 0.0, occupied = 0
        for slice in members where !slice.isEmpty {
            let peak = slice.reduce(Float(0)) { max($0, $1.value) }
            var low = Double.infinity, high = -Double.infinity
            for member in slice where member.value >= peak / 2 {
                low = min(low, member.across)
                high = max(high, member.across)
            }
            guard low <= high else { continue }
            sum += high - low + 1 / BoardCanvas.pixelsPerMillimetre
            occupied += 1
        }
        return occupied > 0 ? sum / Double(occupied) : nil
    }

    /// Length along the line, from `t`, that stays inside the silhouettes.
    static func chord(from t: Double, line: BlobAnalysis.Line, silhouettes: CanvasMask, step: Double) -> Double {
        var length = 0.0
        while length < Lengths.longestChord {
            let point = line.mean + (t + length + step) * line.direction
            if !silhouettes.contains(BoardPoint(x: point.x, y: point.y)) { break }
            length += step
        }
        return length + step
    }

    static func canvasIndex(of point: SIMD2<Double>) -> Int? {
        let pixel = BoardCanvas.pixel(for: BoardPoint(x: point.x, y: point.y))
        guard pixel.x.isFinite, pixel.y.isFinite else { return nil }
        let x = Int(pixel.x.rounded()), y = Int(pixel.y.rounded())
        let side = BoardCanvas.side
        guard x >= 0, y >= 0, x < side, y < side else { return nil }
        return y * side + x
    }

    static func isValidCanvas(_ point: SIMD2<Double>, evidence: ChangeEvidence) -> Bool {
        guard let index = canvasIndex(of: point) else { return false }
        return evidence.valid[index] != 0
    }

    /// True when a pixel of the set has a 4-neighbour that is invalid or outside the canvas.
    static func touchesInvalid(_ indices: [Int], evidence: ChangeEvidence) -> Bool {
        let side = evidence.side
        for index in indices {
            let x = index % side, y = index / side
            if !evidence.isValid(x: x - 1, y: y) || !evidence.isValid(x: x + 1, y: y)
                || !evidence.isValid(x: x, y: y - 1) || !evidence.isValid(x: x, y: y + 1) { return true }
        }
        return false
    }

    /// Widths of 1 mm slices along a line (D5 step 4): lateral extent plus one pixel.
    struct WidthProfile {
        /// Position of each point along the line.
        var along: [Double]
        var minimum: Double
        var maximum: Double
        /// Width of each slice, mm; 0 for an empty slice.
        var widths: [Double]
        var occupied: [Bool]

        init(points: [SIMD2<Double>], line: BlobAnalysis.Line) {
            along = points.map(line.along)
            minimum = along.min() ?? 0
            maximum = along.max() ?? 0
            let count = max(1, Int((maximum - minimum).rounded(.down)) + 1)
            var low = [Double](repeating: .infinity, count: count), high = [Double](repeating: -.infinity, count: count)
            for (position, point) in points.enumerated() {
                let slice = min(count - 1, max(0, Int(along[position] - minimum)))
                let d = line.across(point)
                low[slice] = min(low[slice], d)
                high[slice] = max(high[slice], d)
            }
            occupied = (0..<count).map { low[$0] <= high[$0] }
            widths = (0..<count).map { low[$0] <= high[$0] ? high[$0] - low[$0] + 1 / BoardCanvas.pixelsPerMillimetre : 0 }
        }

        func slice(of t: Double) -> Int {
            min(widths.count - 1, max(0, Int(t - minimum)))
        }

        /// Largest mean width over three consecutive occupied slices of `range` (fewer at its ends); 0 when none is
        /// occupied.
        func widestPart(of range: Range<Int>) -> Double {
            var widest = 0.0
            for slice in range where occupied[slice] {
                let window = max(range.lowerBound, slice - 1)..<min(range.upperBound, slice + 2)
                widest = max(widest, meanWidth(of: window))
            }
            return widest
        }

        /// Mean width of the occupied slices of `range`; 0 when none is occupied.
        func meanWidth(of range: Range<Int>) -> Double {
            var sum = 0.0, count = 0
            for slice in range where occupied[slice] {
                sum += widths[slice]
                count += 1
            }
            return count > 0 ? sum / Double(count) : 0
        }
    }
}
