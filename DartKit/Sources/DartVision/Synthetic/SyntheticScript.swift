import Foundation
import simd
import CoreGraphics
import CoreVideo
import DartCore

/// A timeline of events rendered at a fixed frame rate.
public struct SyntheticScript: Sendable {
    public enum Step: Sendable {
        case wait(TimeInterval)
        /// Two motion-blurred frames, four frames of decaying vibration, then the dart at rest.
        case throwDart(SyntheticDart)
        /// Three frames of motion, then back to the previous scene.
        case bounceOut
        case handRest(TimeInterval)
        /// A hand covers the board for `duration`, then every dart is gone.
        case takeout(duration: TimeInterval)
        case fallOut(index: Int)
        case bump(delta: SIMD3<Double>, rollDegrees: Double)
        case lightStep(gain: Double)
        case lightRamp(gain: Double, duration: TimeInterval)
    }

    /// The steps, in order.
    let steps: [Step]
    /// Frames per second: the given rate, or 30 when it is not finite and positive.
    let framesPerSecond: Double

    public init(_ steps: [Step], framesPerSecond: Double = 30) {
        self.steps = steps
        self.framesPerSecond = framesPerSecond.isFinite && framesPerSecond > 0 ? framesPerSecond : 30
    }
}

// MARK: - Frames of a script (lot V1, internal)

extension SyntheticScript {
    /// A skin-coloured disc 60 mm above the board (`SyntheticScene.hand`).
    struct Hand: Hashable, Sendable {
        var centre: BoardPoint
        var radius: Double
    }

    /// A dart in motion during one frame: rendered at each offset (board frame, mm) and averaged (motion blur).
    struct Motion: Hashable, Sendable {
        var dart: SyntheticDart
        var offsets: [SIMD3<Double>]
    }

    /// Everything that one frame shows. Frames whose `geometry` is equal share the same rays.
    struct Shot: Hashable, Sendable {
        struct Geometry: Hashable, Sendable {
            /// Darts at rest on the board, oldest first.
            var darts: [SyntheticDart]
            var motion: Motion?
            var hand: Hand?
            var camera: SyntheticCamera
        }
        var geometry: Geometry
        /// Multiplies the gain of the scene (1 = unchanged).
        var gain: Double
        /// Whole-image shift added to the scene's own, px: the vibration after an impact or a bump.
        var jitter: SIMD2<Double>
    }

    /// Hand radius of a takeout or a resting hand, as a fraction of the frame it covers (VISION.md §10.2, X3).
    static let handFieldFraction = 0.10
    /// Frames for a hand to come in from outside the view, or to leave.
    static let handTravelFrames = 6
    /// Amplitude of the first frame of vibration after an impact, px (VISION.md §10.1: ±0.6 px).
    static let impactVibration = 0.6
    /// Ratio between two successive frames of vibration (the sign alternates).
    static let vibrationDecay = -0.67

    /// Number of frames of `duration` seconds: rounded to the nearest frame, none for a negative or non-finite
    /// value, at most a million (more than nine hours at 30 frames per second).
    func frames(_ duration: TimeInterval) -> Int {
        guard duration.isFinite, duration > 0 else { return 0 }
        return Int(min(1_000_000, (duration * framesPerSecond).rounded()))
    }

    /// The frames of the script for a camera, in order. The scene gives the darts present at the start.
    func shots(camera: SyntheticCamera, scene: SyntheticScene) -> [Shot] {
        var darts = scene.darts
        var currentCamera = camera
        var gain = 1.0
        var result: [Shot] = []

        func still(_ count: Int, hand: Hand? = nil) {
            for _ in 0..<count {
                result.append(Shot(geometry: .init(darts: darts, motion: nil, hand: hand, camera: currentCamera), gain: gain, jitter: .zero))
            }
        }
        func vibration(_ count: Int, amplitude: Double) {
            var size = amplitude
            // Along a fixed oblique direction, so that both image axes move.
            let direction = SIMD2(0.8, 0.6)
            for _ in 0..<count {
                result.append(Shot(geometry: .init(darts: darts, motion: nil, hand: nil, camera: currentCamera), gain: gain,
                                   jitter: direction * size))
                size *= SyntheticScript.vibrationDecay
            }
        }
        func moving(_ dart: SyntheticDart, _ offsets: [SIMD3<Double>], jitter: SIMD2<Double> = .zero) {
            result.append(Shot(geometry: .init(darts: darts, motion: Motion(dart: dart, offsets: offsets), hand: nil,
                                               camera: currentCamera), gain: gain, jitter: jitter))
        }
        func handPath(rest: BoardPoint, radius: Double, entering: Bool) {
            // The hand comes from outside the view, on the side of the camera's foot point.
            let foot = SIMD2(currentCamera.position.x, currentCamera.position.y)
            var away = foot - SIMD2(rest.x, rest.y)
            let length = simd_length(away)
            away = length > 1e-9 ? away / length : SIMD2(0, -1)
            let travel = 2 * radius + 600
            let count = SyntheticScript.handTravelFrames
            for step in 0..<count {
                let fraction = entering ? Double(count - step) / Double(count) : Double(step + 1) / Double(count)
                let centre = SIMD2(rest.x, rest.y) + away * (travel * fraction)
                result.append(Shot(geometry: .init(darts: darts, motion: nil, hand: Hand(centre: BoardPoint(x: centre.x, y: centre.y), radius: radius),
                                                   camera: currentCamera), gain: gain, jitter: .zero))
            }
        }

        for (stepIndex, step) in steps.enumerated() {
            switch step {
            case .wait(let duration):
                still(frames(duration))

            case .throwDart(let dart):
                // In flight, tip first along its own axis: about half a metre per frame, landing at the end of the
                // second frame. Four positions per frame for the motion blur.
                let axis = dart.axis
                moving(dart, [400, 330, 260, 190].map { axis * $0 })
                moving(dart, [120, 70, 30, 0].map { axis * $0 })
                darts.append(dart)
                vibration(4, amplitude: SyntheticScript.impactVibration)

            case .bounceOut:
                // A dart hits a wire near the treble ring and falls out: in, at the board, then away and down.
                let angle = 37 * Double(stepIndex + 1) * .pi / 180
                let dart = SyntheticDart(tip: BoardPoint(x: 110 * sin(angle), y: 110 * cos(angle)), leanUpDegrees: 10)
                let axis = dart.axis
                moving(dart, [300, 220, 140].map { axis * $0 })
                moving(dart, [40, 4, 12].map { axis * $0 }, jitter: SIMD2(0.8, 0.6) * SyntheticScript.impactVibration)
                moving(dart, [SIMD3(0, -10, 25), SIMD3(0, -35, 45), SIMD3(0, -70, 60)])

            case .handRest(let duration):
                let radius = handRadius(for: currentCamera)
                let rest = BoardPoint(x: 70, y: -60)
                handPath(rest: rest, radius: radius, entering: true)
                still(frames(duration), hand: Hand(centre: rest, radius: radius))
                handPath(rest: rest, radius: radius, entering: false)

            case .takeout(let duration):
                let radius = handRadius(for: currentCamera)
                var rest = BoardPoint(x: 0, y: 40)
                if !darts.isEmpty {
                    rest = BoardPoint(x: darts.map(\.tip.x).reduce(0, +) / Double(darts.count),
                                      y: darts.map(\.tip.y).reduce(0, +) / Double(darts.count))
                }
                handPath(rest: rest, radius: radius, entering: true)
                let covered = frames(duration)
                // The darts go while the hand covers them, half-way through.
                still(covered / 2, hand: Hand(centre: rest, radius: radius))
                darts.removeAll()
                still(covered - covered / 2, hand: Hand(centre: rest, radius: radius))
                handPath(rest: rest, radius: radius, entering: false)

            case .fallOut(let index):
                guard darts.indices.contains(index) else { continue }
                let dart = darts.remove(at: index)
                // It slides down and away from the board.
                moving(dart, [SIMD3(0, -2, 1), SIMD3(0, -8, 3), SIMD3(0, -18, 6)])
                moving(dart, [SIMD3(0, -40, 12), SIMD3(0, -70, 20), SIMD3(0, -110, 30)])

            case .bump(let delta, let rollDegrees):
                guard delta.x.isFinite, delta.y.isFinite, delta.z.isFinite, rollDegrees.isFinite else { continue }
                currentCamera = currentCamera.moved(by: delta, rollDegrees: rollDegrees)
                vibration(3, amplitude: 1.5)

            case .lightStep(let newGain):
                if newGain.isFinite, newGain >= 0 { gain = newGain }

            case .lightRamp(let target, let duration):
                guard target.isFinite, target >= 0 else { continue }
                let count = frames(duration)
                let start = gain
                for frame in 0..<count {
                    gain = start + (target - start) * Double(frame + 1) / Double(count)
                    still(1)
                }
                gain = target
            }
        }
        return result
    }

    /// Radius of a hand disc that covers `handFieldFraction` of the image, mm (at the hand's height above the bull).
    func handRadius(for camera: SyntheticCamera) -> Double {
        let scale = camera.boardToImage.localScale(at: SIMD2(0, 0))
        let pixelsPerMillimetre = (scale.min * scale.max).squareRoot()
        let distance = simd_length(camera.position)
        guard pixelsPerMillimetre.isFinite, pixelsPerMillimetre > 0, distance > SyntheticRayCaster.handHeight else { return 100 }
        // A disc 60 mm nearer to the camera looks larger by D / (D − 60).
        let atHand = pixelsPerMillimetre * distance / (distance - SyntheticRayCaster.handHeight)
        let area = SyntheticScript.handFieldFraction * Double(camera.imageSize.width) * Double(camera.imageSize.height)
        return min(400, max(40, (area / Double.pi).squareRoot() / atHand))
    }
}
