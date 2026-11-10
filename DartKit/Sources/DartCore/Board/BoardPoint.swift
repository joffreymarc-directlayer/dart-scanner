import Foundation

/// A point of the board plane in millimetres.
/// Origin at the bull centre, +x towards the 6 (right when facing the board), +y towards the 20 (up).
/// Same frame as VISION.md §3.3. Points that cross a module boundary are in NOMINAL coordinates.
public struct BoardPoint: Hashable, Codable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    /// Polar constructor: `x = r·sin α`, `y = r·cos α`, with α measured clockwise from +y (the middle of the 20).
    public init(radius: Double, clockwiseDegrees: Double) {
        let a = clockwiseDegrees * .pi / 180
        self.init(x: radius * sin(a), y: radius * cos(a))
    }

    public static let centre = BoardPoint(x: 0, y: 0)

    /// Distance from the bull centre, mm.
    public var radius: Double { (x * x + y * y).squareRoot() }

    /// Clockwise angle from +y in degrees, in [0, 360). 20 = 0°, 6 = 90°, 3 = 180°, 11 = 270°.
    public var clockwiseDegrees: Double {
        let a = atan2(x, y) * 180 / .pi
        guard a < 0 else { return a }
        // A tiny negative angle plus 360 rounds to 360 exactly: that point is on the +y axis.
        let turned = a + 360
        return turned < 360 ? turned : 0
    }
}
