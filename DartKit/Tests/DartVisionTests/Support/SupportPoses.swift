import Foundation
import simd
import DartCore
@testable import DartVision

/// The reference camera poses of VISION.md §10.2, shared by every vision test (lots V1, V2, V3 and V5).
///
/// | Pose | Lens position (mm) | Image                         |
/// |------|--------------------|-------------------------------|
/// | A    | (150, −450, 1100)  | 4K portrait, 2.1 to 2.5 px/mm |
/// | B    | (0, −400, 1000)    | 1080p landscape               |
/// | C    | (−300, −420, 1050) | 4K portrait (below, left)     |
/// | D    | (450, −100, 1100)  | 4K landscape (side variant)   |
///
/// The document fixes the image size of A and B only; C and D follow its placement rule (portrait under the
/// board, landscape on the side). Every camera looks at the bull with the default 67 degree field of view.
enum SupportPoses: String, CaseIterable, Sendable {
    case a, b, c, d

    /// Lens position in the board frame, mm.
    var position: SIMD3<Double> {
        switch self {
        case .a: return SIMD3(150, -450, 1100)
        case .b: return SIMD3(0, -400, 1000)
        case .c: return SIMD3(-300, -420, 1050)
        case .d: return SIMD3(450, -100, 1100)
        }
    }

    /// Image size of the pose at full resolution.
    var imageSize: PixelSize {
        switch self {
        case .a, .c: return PixelSize(width: 2160, height: 3840)
        case .b: return PixelSize(width: 1920, height: 1080)
        case .d: return PixelSize(width: 3840, height: 2160)
        }
    }

    /// The camera at full resolution.
    var camera: SyntheticCamera {
        SyntheticCamera(imageSize: imageSize, position: position)
    }

    /// The same view on a smaller sensor: the long side has `longSide` pixels, the aspect ratio is kept.
    /// Same position, same field of view, fewer pixels per millimetre: for debug runs of heavy suites
    /// (VISION.md §10.2 uses 1280x720 there).
    func camera(longSide: Int) -> SyntheticCamera {
        let size = imageSize
        let portrait = size.height > size.width
        let short = Int((Double(longSide) * Double(min(size.width, size.height)) / Double(max(size.width, size.height))).rounded())
        return SyntheticCamera(imageSize: portrait ? PixelSize(width: short, height: longSide) : PixelSize(width: longSide, height: short),
                               position: position)
    }

    /// The four cameras at full resolution, A to D.
    static var cameras: [SyntheticCamera] {
        allCases.map(\.camera)
    }

    /// The four cameras with a long side of 1280 pixels (720 on the short side).
    static var smallCameras: [SyntheticCamera] {
        allCases.map { $0.camera(longSide: 1280) }
    }
}

/// Seeded random values for vision tests: every draw comes from DartCore's SplitMix64.
struct SupportRandom: Sendable {
    private var generator: SeededRandom

    init(seed: UInt64) {
        generator = SeededRandom(seed: seed)
    }

    /// Uniform in [0, 1).
    mutating func unit() -> Double {
        Double(generator.next() >> 11) * (1.0 / 9007199254740992.0)
    }

    /// Uniform in `range`.
    mutating func uniform(_ range: ClosedRange<Double>) -> Double {
        range.lowerBound + (range.upperBound - range.lowerBound) * unit()
    }

    /// Uniform integer in `0 ..< bound`.
    mutating func int(below bound: Int) -> Int {
        generator.nextInt(below: bound)
    }

    /// Standard normal value (Box–Muller).
    mutating func gaussian() -> Double {
        let u = max(unit(), 1e-300), v = unit()
        return (-2 * log(u)).squareRoot() * cos(2 * .pi * v)
    }

    /// A point uniform over the disc of radius `radius` centred on the bull.
    mutating func boardPoint(maxRadius radius: Double) -> BoardPoint {
        let r = radius * unit().squareRoot()
        let angle = 2 * Double.pi * unit()
        return BoardPoint(x: r * cos(angle), y: r * sin(angle))
    }

    /// A camera at `distance` mm from the bull, whose optical axis makes `viewAngleDegrees` with the board normal,
    /// placed in the direction `azimuthDegrees` (clockwise from +y, so 180 is under the board), looking at `lookAt`.
    static func camera(distance: Double, viewAngleDegrees: Double, azimuthDegrees: Double, rollDegrees: Double = 0,
                       imageSize: PixelSize = PixelSize(width: 1920, height: 1080),
                       lookAt: BoardPoint = BoardPoint(x: 0, y: 0)) -> SyntheticCamera {
        let tilt = viewAngleDegrees * .pi / 180, azimuth = azimuthDegrees * .pi / 180
        let position = SIMD3(lookAt.x + distance * sin(tilt) * sin(azimuth),
                             lookAt.y + distance * sin(tilt) * cos(azimuth),
                             distance * cos(tilt))
        return SyntheticCamera(imageSize: imageSize, position: position, lookAt: lookAt, rollDegrees: rollDegrees)
    }

    /// A random physical view: 0.9 to 1.5 m from the bull, `viewAngle` degrees off the normal, any side, small roll,
    /// aimed near the bull.
    mutating func camera(viewAngle: ClosedRange<Double> = 5...45, imageSize: PixelSize = PixelSize(width: 1920, height: 1080)) -> SyntheticCamera {
        let lookAt = BoardPoint(x: uniform(-40...40), y: uniform(-40...40))
        return SupportRandom.camera(distance: uniform(900...1500), viewAngleDegrees: uniform(viewAngle),
                                    azimuthDegrees: uniform(0...360), rollDegrees: uniform(-10...10),
                                    imageSize: imageSize, lookAt: lookAt)
    }
}

/// Scene builders shared by the vision tests.
enum SupportScenes {
    /// An empty board without blur, noise, gain change or shift: the exact geometry.
    static func exact() -> SyntheticScene {
        var scene = SyntheticScene()
        scene.noiseSigma = 0
        scene.blurPasses = 0
        return scene
    }

    /// An empty board with the default nuisances (one blur pass, noise of 2 levels) and the given seed.
    static func empty(seed: UInt64 = 1) -> SyntheticScene {
        var scene = SyntheticScene()
        scene.seed = seed
        return scene
    }

    /// The default scene with darts on it.
    static func darts(_ darts: [SyntheticDart], seed: UInt64 = 1) -> SyntheticScene {
        var scene = empty(seed: seed)
        scene.darts = darts
        return scene
    }

    /// A random dart of the default mix (VISION.md §10.1): tip uniform over `maxRadius`, tail up by 0 to 18
    /// degrees, a little sideways lean, one of the three styles (the all-black one included).
    static func randomDart(_ random: inout SupportRandom, maxRadius: Double = 170,
                           leanUp: ClosedRange<Double> = 0...18, leanSide: ClosedRange<Double> = -6...6) -> SyntheticDart {
        let styles: [SyntheticDartStyle] = [.steelTungsten, .brass, .allBlack]
        return SyntheticDart(tip: random.boardPoint(maxRadius: maxRadius), leanUpDegrees: random.uniform(leanUp),
                             leanSideDegrees: random.uniform(leanSide), style: styles[random.int(below: styles.count)])
    }

    /// A lamp above the board and in front of it, on the side opposite to the camera: the shadow of a dart then
    /// runs from its tip towards the camera foot point, the alignment that defeats plain differencing.
    static func lampOpposite(to camera: SyntheticCamera, height: Double = 1500) -> SIMD3<Double> {
        SIMD3(-camera.position.x * 2, -camera.position.y * 2, height)
    }
}

/// Writes an image under the scratch directory named by the environment variable `DART_VISION_TEST_OUTPUT`,
/// for looking at a failing case. Does nothing when the variable is not set.
func supportDump(_ image: RGBImage, named name: String) {
    guard let directory = ProcessInfo.processInfo.environment["DART_VISION_TEST_OUTPUT"], !directory.isEmpty,
          let data = image.pngData() else { return }
    let url = URL(fileURLWithPath: directory).appendingPathComponent(name + ".png")
    try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try? data.write(to: url)
}
