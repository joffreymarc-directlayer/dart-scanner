import SwiftUI
import DartCore

/// One of the 82 beds of a board: a band of a sector, or one of the two bulls.
struct BoardBed: Hashable {
    var band: BoardGeometry.Band
    /// Index 0...19 in `sectorOrder`, clockwise from the 20; 0 for the two bulls.
    var sector: Int

    /// The four bands of a sector, innermost first.
    static let sectorBands: [BoardGeometry.Band] = [.innerSingle, .treble, .outerSingle, .double]

    /// The 82 beds: inner bull, outer bull, then the four bands of each of the twenty sectors.
    static let all: [BoardBed] = [BoardBed(band: .innerBull, sector: 0), BoardBed(band: .outerBull, sector: 0)]
        + (0..<20).flatMap { sector in sectorBands.map { BoardBed(band: $0, sector: sector) } }

    /// The hit that a dart in this bed scores on a board of `geometry`.
    func hit(in geometry: BoardGeometry) -> Hit {
        let number = geometry.sectorOrder[min(19, max(0, sector))]
        switch band {
        case .innerBull: return .innerBull
        case .outerBull: return .outerBull
        case .innerSingle, .outerSingle: return .single(number)
        case .treble: return .treble(number)
        case .double: return .double(number)
        }
    }

    /// Middle of the bed in the coordinates of `geometry`: the middle of its band, on the axis of its sector
    /// (towards the 20 for the outer bull, the very centre for the inner bull).
    func centre(in geometry: BoardGeometry) -> BoardPoint {
        if band == .innerBull { return .centre }
        let range = geometry.radialRange(of: band)
        return BoardPoint(radius: (range.lowerBound + range.upperBound) / 2,
                          clockwiseDegrees: Double(sector) * BoardGeometry.sectorWidthDegrees)
    }

    /// The beds of a highlighted zone; none for a disc, and none for a number that is not on the board.
    static func beds(of zone: BoardZone, in geometry: BoardGeometry) -> [BoardBed] {
        func sector(_ number: Int) -> Int? { geometry.sectorOrder.firstIndex(of: number) }
        switch zone {
        case .sector(let number):
            return sector(number).map { index in sectorBands.map { BoardBed(band: $0, sector: index) } } ?? []
        case .single(let number):
            return sector(number).map { [BoardBed(band: .innerSingle, sector: $0), BoardBed(band: .outerSingle, sector: $0)] } ?? []
        case .double(let number):
            return sector(number).map { [BoardBed(band: .double, sector: $0)] } ?? []
        case .treble(let number):
            return sector(number).map { [BoardBed(band: .treble, sector: $0)] } ?? []
        case .outerBull:
            return [BoardBed(band: .outerBull, sector: 0)]
        case .innerBull:
            return [BoardBed(band: .innerBull, sector: 0)]
        case .bull:
            return [BoardBed(band: .innerBull, sector: 0), BoardBed(band: .outerBull, sector: 0)]
        case .disc:
            return []
        }
    }
}

/// The drawing of one board (DESIGN.md §3 and §4), written for a `GraphicsContext`. A value without any state:
/// the same inputs always give the same picture. Not bound to the main actor, so that `Canvas` can call it.
struct BoardDrawing {
    var highlights: [BoardHighlight]
    var darts: [BoardDartMarker]
    var geometry: BoardGeometry
    var dimsUnhighlighted: Bool
    var showsNumbers: Bool
    /// Diameter of a dart marker on a board that is large enough: 14 pt, 26 pt in regular width.
    var markerDiameter: CGFloat
    /// Size of the square view.
    var size: CGSize

    // MARK: Conversions (the single definition; `DartboardView` exposes them)

    /// Points per millimetre: the board radius (225.5 mm, the same in both geometries) fills half the width.
    static func scale(in size: CGSize) -> CGFloat {
        (size.width / 2) / CGFloat(BoardGeometry.standard.boardRadius)
    }

    /// Position in the view of a point given in the coordinates of the DRAWN geometry.
    static func location(ofDrawn point: BoardPoint, in size: CGSize) -> CGPoint {
        let scale = scale(in: size)
        return CGPoint(x: size.width / 2 + CGFloat(point.x) * scale, y: size.height / 2 - CGFloat(point.y) * scale)
    }

    /// Position in the view of a NOMINAL board point, on a board drawn with `geometry`.
    static func location(of position: BoardPoint, in size: CGSize, geometry: BoardGeometry) -> CGPoint {
        location(ofDrawn: BoardGeometry.standard.remap(position, to: geometry), in: size)
    }

    /// The point of the DRAWN geometry under a point of the view; nil when the view has no size or the point
    /// is not a finite one.
    static func drawnPoint(at location: CGPoint, in size: CGSize) -> BoardPoint? {
        let scale = scale(in: size)
        guard scale > 0, scale.isFinite, size.height.isFinite, location.x.isFinite, location.y.isFinite else { return nil }
        return BoardPoint(x: Double((location.x - size.width / 2) / scale),
                          y: Double((size.height / 2 - location.y) / scale))
    }

    /// A point of the view as a tap on a board drawn with `geometry` (ARCHITECTURE.md §8.4.3): the hit is read
    /// on the drawing, the position is brought back to nominal millimetres.
    static func tap(at location: CGPoint, in size: CGSize, geometry: BoardGeometry) -> BoardTap {
        // A view without a size cannot be touched: nothing is hit, and no position is invented.
        guard let drawn = drawnPoint(at: location, in: size) else { return BoardTap(hit: .miss, position: .centre) }
        return BoardTap(hit: geometry.hit(at: drawn), position: geometry.remap(drawn, to: .standard))
    }

    // MARK: Reading the highlights

    /// How a bed, an arc or a number is drawn: the role of its highlight and the colour it takes.
    struct Style: Hashable {
        var role: HighlightRole
        var owner: PlayerIndex?
        /// True for a zone of one ring or of the bull (D12 to finish): it is coloured almost solid, where a whole
        /// sector is tinted (DESIGN.md §3).
        var isOneRing: Bool

        /// Colour of the zone: its owner's, else `accent`; red for a zone to avoid; grey for a dead one.
        var color: Color {
            if role == .inactive { return Theme.Palette.textTertiary }
            if let owner { return Theme.playerColor(owner) }
            return role == .avoid ? Theme.Palette.boardRed : Theme.Palette.accent
        }

        /// Which highlight speaks for a sector that has several: the one the player must see first.
        var rank: Int {
            switch role {
            case .target: return 5
            case .avoid: return 4
            case .own: return 3
            case .secondary: return 2
            case .opponent: return 1
            case .inactive: return 0
            }
        }
    }

    /// The style of every highlighted bed. Where two zones overlap, the narrower one wins on its beds (a treble
    /// to aim at inside a sector shown as secondary); between two zones of the same kind, the later one.
    static func bedStyles(for highlights: [BoardHighlight], in geometry: BoardGeometry) -> [BoardBed: Style] {
        func breadth(_ zone: BoardZone) -> Int {
            switch zone {
            case .sector, .bull: return 0
            case .single: return 1
            case .double, .treble, .outerBull, .innerBull, .disc: return 2
            }
        }
        var styles: [BoardBed: Style] = [:]
        let ordered = highlights.enumerated().sorted { a, b in
            let (x, y) = (breadth(a.element.zone), breadth(b.element.zone))
            return x != y ? x < y : a.offset < b.offset
        }
        for (_, highlight) in ordered {
            let style = Style(role: highlight.role, owner: highlight.owner, isOneRing: breadth(highlight.zone) > 0)
            for bed in BoardBed.beds(of: highlight.zone, in: geometry) { styles[bed] = style }
        }
        return styles
    }

    /// The style that speaks for each sector (index 0...19): arc outside the double, colour of the number.
    static func sectorStyles(for highlights: [BoardHighlight], in geometry: BoardGeometry) -> [Style?] {
        var styles = [Style?](repeating: nil, count: 20)
        for highlight in highlights {
            guard let number = highlight.zone.number, let index = geometry.sectorOrder.firstIndex(of: number) else { continue }
            let style = Style(role: highlight.role, owner: highlight.owner, isOneRing: false)
            if let current = styles[index], current.rank >= style.rank { continue }
            styles[index] = style
        }
        return styles
    }

    /// Numbers of the zones to aim at, clockwise from the 20, each once (accessibility value of the board).
    static func targetNumbers(in highlights: [BoardHighlight]) -> [Int] {
        let numbers = Set(highlights.filter { $0.role == .target }.compactMap(\.zone.number))
        return BoardGeometry.standardSectorOrder.filter(numbers.contains)
    }

    /// Maximal groups of consecutive positions around the ring (wrapping after the last one) that carry the same
    /// non-nil value: a zone of three adjacent sectors is one group, drawn in one piece.
    static func runs<Value: Equatable>(of values: [Value?]) -> [(start: Int, count: Int, value: Value)] {
        let n = values.count
        guard n > 0 else { return [] }
        // Start at a boundary, so that a group that wraps past the 20 is not cut in two.
        guard let origin = (0..<n).first(where: { values[$0] != values[($0 + n - 1) % n] }) else {
            return values[0].map { [(start: 0, count: n, value: $0)] } ?? []
        }
        var result: [(start: Int, count: Int, value: Value)] = []
        var offset = 0
        while offset < n {
            let start = (origin + offset) % n
            var count = 1
            while offset + count < n, values[(origin + offset + count) % n] == values[start] { count += 1 }
            if let value = values[start] { result.append((start: start, count: count, value: value)) }
            offset += count
        }
        return result
    }

    // MARK: Drawing

    func draw(in context: inout GraphicsContext) {
        guard size.width > 0, size.height > 0, size.width.isFinite, size.height.isFinite else { return }
        let bedStyles = Self.bedStyles(for: highlights, in: geometry)
        if side < Measure.pictogram {
            // An option pictogram (36 pt on the mock-up `KillerOptions`): rings of one or two points would only be
            // noise. The board is a flat `line` disc and its zones are drawn in their colour, as on the mock-up.
            drawPictogram(bedStyles, in: &context)
            drawDiscs(in: &context)
            drawDarts(in: &context)
            return
        }
        let sectorStyles = Self.sectorStyles(for: highlights, in: geometry)
        drawSurround(in: &context)
        drawArcs(sectorStyles, in: &context)
        drawBeds(in: &context)
        drawHighlights(bedStyles, in: &context)
        drawDiscs(in: &context)
        if showsNumbers { drawNumbers(sectorStyles, in: &context) }
        drawAnnotations(in: &context)
        drawDarts(in: &context)
    }

    // MARK: Measures of the drawing

    private enum Measure {
        /// Arc that marks a highlighted sector: it starts 2.3 mm outside the double and is 9 mm thick
        /// (mock-up `PlayKiller`: from 39 % to 41 % of the diameter).
        static let arcGap = 2.3
        static let arcThickness = 9.0
        /// Radius of the number ring: 88.7 % of the board radius.
        static let numberRadius = 200.0
        /// Unhighlighted beds: `background` at 62 %. A tinted sector: its colour at 60 %.
        static let dim = 0.62
        static let tint = 0.6
        /// A single ring to aim at is coloured almost solid; so is a sector on a board too small for a tint to read.
        static let solid = 0.92
        /// A zone shown for information: darkened like the rest, with a light veil of its colour and a faint arc.
        static let faint = 0.3
        static let faintArc = 0.4
        /// A dead zone: a grey veil.
        static let dead = 0.78
        /// Below this side a tinted sector is drawn almost solid.
        static let smallBoard: CGFloat = 90
        /// Below this side the board is drawn as a pictogram: a flat disc with its zones (mock-up `KillerOptions`).
        static let pictogram: CGFloat = 64
        /// A zone shown for information on a pictogram (mock-up `KillerOptions`, level "Expert": 40 %).
        static let pictogramFaint = 0.4
    }

    private var side: CGFloat { size.width }
    private var centre: CGPoint { CGPoint(x: size.width / 2, y: size.height / 2) }

    private func points(_ millimetres: Double) -> CGFloat {
        CGFloat(millimetres) * Self.scale(in: size)
    }

    /// Size of a text or of a mark that follows the size of the board, inside limits that keep it readable.
    private func scaled(_ fraction: CGFloat, min lower: CGFloat, max upper: CGFloat) -> CGFloat {
        Swift.min(upper, Swift.max(lower, side * fraction))
    }

    private func disc(radius: Double) -> Path {
        circle(at: centre, radius: points(radius))
    }

    private func circle(at point: CGPoint, radius: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: point.x - radius, y: point.y - radius, width: 2 * radius, height: 2 * radius))
    }

    /// Part of a ring between two radii (drawn millimetres) and two clockwise angles from the top (degrees).
    private func wedge(from inner: Double, to outer: Double, startDegrees: Double, endDegrees: Double) -> Path {
        var path = Path()
        if endDegrees - startDegrees >= 360 {
            // A whole ring: two circles of opposite direction leave the hole open under the non-zero rule.
            for (radius, clockwise) in [(outer, false), (inner, true)] {
                let turn: [Double] = clockwise ? [360, 180, 0] : [0, 180, 360]
                path.move(to: CGPoint(x: centre.x + points(radius), y: centre.y))
                path.addArc(center: centre, radius: points(radius), startAngle: .degrees(turn[0]), endAngle: .degrees(turn[1]),
                            clockwise: clockwise)
                path.addArc(center: centre, radius: points(radius), startAngle: .degrees(turn[1]), endAngle: .degrees(turn[2]),
                            clockwise: clockwise)
                path.closeSubpath()
            }
            return path
        }
        // SwiftUI measures angles from +x, growing towards +y (down): a clockwise board angle α is α − 90°.
        let start = Angle.degrees(startDegrees - 90), end = Angle.degrees(endDegrees - 90)
        path.addArc(center: centre, radius: points(outer), startAngle: start, endAngle: end, clockwise: false)
        path.addArc(center: centre, radius: points(inner), startAngle: end, endAngle: start, clockwise: true)
        path.closeSubpath()
        return path
    }

    /// Clockwise angles of a group of `count` sectors that starts at sector index `start`.
    private func angles(start: Int, count: Int) -> (start: Double, end: Double) {
        let width = BoardGeometry.sectorWidthDegrees
        let first = Double(start) * width - width / 2
        return (first, first + Double(count) * width)
    }

    /// The fewest pieces that cover a set of beds: adjacent sectors that hold the same bands are joined, and so
    /// are adjacent bands, so that a zone has no seam and one outline.
    private func paths(for beds: Set<BoardBed>) -> [Path] {
        var result: [Path] = []
        let bands: [[BoardGeometry.Band]?] = (0..<20).map { sector in
            let held = BoardBed.sectorBands.filter { beds.contains(BoardBed(band: $0, sector: sector)) }
            return held.isEmpty ? nil : held
        }
        for run in Self.runs(of: bands) {
            let span = angles(start: run.start, count: run.count)
            var index = 0
            while index < run.value.count {
                var last = index
                while last + 1 < run.value.count, run.value[last + 1].rawValue == run.value[last].rawValue + 1 { last += 1 }
                result.append(wedge(from: geometry.radialRange(of: run.value[index]).lowerBound,
                                    to: geometry.radialRange(of: run.value[last]).upperBound,
                                    startDegrees: span.start, endDegrees: span.end))
                index = last + 1
            }
        }
        let inner = beds.contains(BoardBed(band: .innerBull, sector: 0))
        let outer = beds.contains(BoardBed(band: .outerBull, sector: 0))
        if inner && outer {
            result.append(disc(radius: geometry.outerBullRadius))
        } else if inner {
            result.append(disc(radius: geometry.innerBullRadius))
        } else if outer {
            result.append(wedge(from: geometry.innerBullRadius, to: geometry.outerBullRadius, startDegrees: 0, endDegrees: 360))
        }
        return result
    }

    /// Fills several pieces as ONE translucent shape: where two pieces touch, no seam shows.
    private func fill(_ paths: [Path], with color: Color, opacity: Double, in context: inout GraphicsContext) {
        var translucent = context
        translucent.opacity = opacity
        translucent.drawLayer { layer in
            for path in paths { layer.fill(path, with: .color(color)) }
        }
    }

    // MARK: Layers, back to front

    /// Number ring: `boardSurround` disc with a hairline.
    private func drawSurround(in context: inout GraphicsContext) {
        let hairline = Theme.Control.border
        context.fill(disc(radius: geometry.boardRadius), with: .color(Theme.Palette.boardSurround))
        context.stroke(circle(at: centre, radius: points(geometry.boardRadius) - hairline / 2),
                       with: .color(Theme.Palette.line), lineWidth: hairline)
    }

    /// Beds, as on the mock-ups: for each ring a disc in the colour of the 20, then every other sector in the
    /// other colour. The 20 is black with red double and treble.
    private func drawBeds(in context: inout GraphicsContext) {
        let rings: [(radius: Double, first: Color, second: Color)] = [
            (geometry.doubleOuterRadius, Theme.Palette.boardRed, Theme.Palette.boardGreen),
            (geometry.doubleInnerRadius, Theme.Palette.boardBlack, Theme.Palette.boardCream),
            (geometry.trebleOuterRadius, Theme.Palette.boardRed, Theme.Palette.boardGreen),
            (geometry.trebleInnerRadius, Theme.Palette.boardBlack, Theme.Palette.boardCream),
        ]
        for ring in rings {
            context.fill(disc(radius: ring.radius), with: .color(ring.first))
            var others = Path()
            for sector in stride(from: 1, to: 20, by: 2) {
                let span = angles(start: sector, count: 1)
                others.addPath(wedge(from: 0, to: ring.radius, startDegrees: span.start, endDegrees: span.end))
            }
            context.fill(others, with: .color(ring.second))
        }
        context.fill(disc(radius: geometry.outerBullRadius), with: .color(Theme.Palette.boardGreen))
        context.fill(disc(radius: geometry.innerBullRadius), with: .color(Theme.Palette.boardRed))
    }

    /// A solid arc just outside the double, in the colour of each highlighted sector.
    private func drawArcs(_ styles: [Style?], in context: inout GraphicsContext) {
        struct Arc: Equatable {
            var owner: PlayerIndex?
            var isAvoided: Bool
            var opacity: Double
        }
        let arcs: [Arc?] = styles.map { style in
            guard let style, style.role != .inactive else { return nil }
            let opacity: Double
            switch style.role {
            case .target, .own, .avoid: opacity = 1
            case .secondary: opacity = 0.5
            case .opponent: opacity = Measure.faintArc
            case .inactive: opacity = 0
            }
            return Arc(owner: style.owner, isAvoided: style.role == .avoid, opacity: opacity)
        }
        let inner = geometry.doubleOuterRadius + Measure.arcGap
        for run in Self.runs(of: arcs) {
            let span = angles(start: run.start, count: run.count)
            let style = Style(role: run.value.isAvoided ? .avoid : .target, owner: run.value.owner, isOneRing: false)
            let band = wedge(from: inner, to: inner + Measure.arcThickness, startDegrees: span.start, endDegrees: span.end)
            context.fill(band, with: .color(style.color.opacity(run.value.opacity)))
        }
    }

    /// The highlighted beds grouped by style, in a fixed order: the picture does not depend on the order of a
    /// dictionary. Groups that matter more are painted later, over the others.
    private static func groups(of styles: [BoardBed: Style]) -> [(style: Style, beds: Set<BoardBed>)] {
        var beds: [Style: Set<BoardBed>] = [:]
        for (bed, style) in styles { beds[style, default: []].insert(bed) }
        return beds.sorted { a, b in
            if a.key.rank != b.key.rank { return a.key.rank < b.key.rank }
            if a.key.owner != b.key.owner { return (a.key.owner ?? -1) < (b.key.owner ?? -1) }
            return !a.key.isOneRing && b.key.isOneRing
        }.map { (style: $0.key, beds: $0.value) }
    }

    /// Centre and radius, in points, of a `disc` zone that can be drawn; nil for any other zone and for a disc
    /// whose numbers are not finite or whose radius is not positive.
    private func discCircle(of zone: BoardZone) -> (middle: CGPoint, extent: CGFloat)? {
        guard case .disc(let x, let y, let radius) = zone, radius > 0, radius.isFinite, x.isFinite, y.isFinite else {
            return nil
        }
        return (Self.location(of: BoardPoint(x: x, y: y), in: size, geometry: geometry), points(radius))
    }

    /// Tints, outlines and hatching of the highlighted beds, and the darkening of all the others.
    private func drawHighlights(_ styles: [BoardBed: Style], in context: inout GraphicsContext) {
        let groups = Self.groups(of: styles).map { (style: $0.style, paths: paths(for: $0.beds)) }

        if dimsUnhighlighted && !highlights.isEmpty {
            // Everything inside the double, minus the highlighted beds (even-odd: they are counted twice) and
            // minus the discs: as for a sector, "the rest of the board" is darkened, not the zone (DESIGN.md §4).
            var rest = disc(radius: geometry.doubleOuterRadius)
            for group in groups { for path in group.paths { rest.addPath(path) } }
            let discs = highlights.compactMap { discCircle(of: $0.zone) }
            context.drawLayer { layer in
                for disc in discs { layer.clip(to: circle(at: disc.middle, radius: disc.extent), options: .inverse) }
                layer.fill(rest, with: .color(Theme.Palette.background.opacity(Measure.dim)), style: FillStyle(eoFill: true))
            }
        }

        let outline = scaled(0.006, min: 1.5, max: 3)
        for group in groups {
            let color = group.style.color
            let full = group.style.isOneRing || side < Measure.smallBoard ? Measure.solid : Measure.tint
            switch group.style.role {
            case .target:
                fill(group.paths, with: color, opacity: full, in: &context)
            case .secondary:
                fill(group.paths, with: color, opacity: full / 2, in: &context)
            case .opponent:
                fill(group.paths, with: Theme.Palette.background, opacity: Measure.dim / 2, in: &context)
                fill(group.paths, with: color, opacity: Measure.faint, in: &context)
            case .own:
                strokeInside(group.paths, with: color, lineWidth: outline, in: &context)
            case .avoid:
                hatch(group.paths, in: &context)
                strokeInside(group.paths, with: Theme.Palette.boardRed, lineWidth: outline, in: &context)
            case .inactive:
                fill(group.paths, with: Theme.Palette.lineStrong, opacity: Measure.dead, in: &context)
            }
        }
    }

    /// The board of an option pictogram (mock-up `KillerOptions`: a 36 pt disc, amber sectors on `line`). A whole
    /// sector is coloured from the centre to the edge, a ring or a bull on its own band, a zone shown for
    /// information at 40 %. No surround, no numbers, no darkening.
    private func drawPictogram(_ styles: [BoardBed: Style], in context: inout GraphicsContext) {
        context.fill(disc(radius: geometry.boardRadius), with: .color(Theme.Palette.line))
        for group in Self.groups(of: styles) {
            var paths: [Path]
            if group.style.isOneRing {
                paths = self.paths(for: group.beds)
            } else {
                let sectors: [Bool?] = (0..<20).map { index in
                    group.beds.contains { $0.sector == index && BoardBed.sectorBands.contains($0.band) } ? true : nil
                }
                paths = Self.runs(of: sectors).map { run in
                    let span = angles(start: run.start, count: run.count)
                    return wedge(from: 0, to: geometry.boardRadius, startDegrees: span.start, endDegrees: span.end)
                }
                paths += self.paths(for: group.beds.filter { $0.band == .innerBull || $0.band == .outerBull })
            }
            let opacity: Double
            switch group.style.role {
            case .target, .own, .avoid: opacity = 1
            case .secondary, .opponent, .inactive: opacity = Measure.pictogramFaint
            }
            fill(paths, with: group.style.color, opacity: opacity, in: &context)
        }
    }

    /// An outline that stays inside the zone, whatever is next to it.
    private func strokeInside(_ paths: [Path], with color: Color, lineWidth: CGFloat, in context: inout GraphicsContext) {
        for path in paths {
            context.drawLayer { layer in
                layer.clip(to: path)
                layer.stroke(path, with: .color(color), lineWidth: 2 * lineWidth)
            }
        }
    }

    /// Red hatching of a zone to avoid, over a darkened ground so that it reads on red and green beds too.
    private func hatch(_ paths: [Path], in context: inout GraphicsContext) {
        fill(paths, with: Theme.Palette.background, opacity: 0.5, in: &context)
        var zone = Path()
        for path in paths { zone.addPath(path) }
        let spacing = scaled(0.024, min: 4, max: 12)
        var stripes = Path()
        var x = -side
        while x < side {
            stripes.move(to: CGPoint(x: x, y: side))
            stripes.addLine(to: CGPoint(x: x + side, y: 0))
            x += spacing
        }
        context.drawLayer { layer in
            layer.clip(to: zone)
            layer.stroke(stripes, with: .color(Theme.Palette.boardRed), lineWidth: spacing * 0.4)
        }
    }

    /// Discs laid over the beds (Radar targets, DESIGN.md §4): 60 % fill, solid 2 pt outline, a solid pill with
    /// the label at the centre and three hit-point pips under it. A disc too small for them has them just below.
    private func drawDiscs(in context: inout GraphicsContext) {
        for highlight in highlights {
            guard let drawn = discCircle(of: highlight.zone) else { continue }
            let middle = drawn.middle, extent = drawn.extent
            let style = Style(role: highlight.role, owner: highlight.owner, isOneRing: true)
            let shape = circle(at: middle, radius: extent)
            context.fill(shape, with: .color(style.color.opacity(Measure.tint)))
            strokeInside([shape], with: style.color, lineWidth: Theme.Control.borderStrong, in: &context)
            // A pictogram shows where the disc is, not what it is worth.
            if side < Measure.pictogram { continue }

            // Label and pips form one block, centred in the disc when it fits.
            let pip = scaled(0.011, min: 4, max: 8)
            let gap = pip * 0.75
            let label = highlight.label.map { pill(for: $0, style: style, in: context) }
            let pips = highlight.strength.map { _ in CGSize(width: 3 * pip + 2 * gap, height: pip) }
            let spacing: CGFloat = label != nil && pips != nil ? gap : 0
            let block = CGSize(width: max(label?.size.width ?? 0, pips?.width ?? 0),
                               height: (label?.size.height ?? 0) + spacing + (pips?.height ?? 0))
            guard block.height > 0 else { continue }
            // The label is a capsule: its farthest points are on its round ends. The pips are a row under it.
            let room = extent - Theme.Control.borderStrong
            var fits = true
            if let label {
                let half = label.size.height / 2
                let middleY = block.height / 2 - half
                fits = hypot(max(0, label.size.width / 2 - half), middleY) + half <= room
            }
            if let pips, fits {
                fits = hypot(pips.width / 2, block.height / 2) <= room
            }
            var top = middle.y - block.height / 2
            if !fits {
                // Just below the disc, or just above when the bottom of the view is too close.
                let below = middle.y + extent + gap
                top = below + block.height <= size.height - gap ? below : middle.y - extent - gap - block.height
            }
            if let label {
                draw(label, at: CGPoint(x: middle.x, y: top + label.size.height / 2), in: &context)
                top += label.size.height + spacing
            }
            if let strength = highlight.strength {
                drawPips(filled: strength, at: CGPoint(x: middle.x, y: top + pip / 2), diameter: pip, gap: gap,
                         color: fits ? Theme.Palette.textPrimary : style.color, in: &context)
            }
        }
    }

    /// The twenty numbers: grey, or bold in the colour of the zone they belong to.
    private func drawNumbers(_ styles: [Style?], in context: inout GraphicsContext) {
        let fontSize = scaled(0.04, min: 6, max: 22)
        for (index, number) in geometry.sectorOrder.enumerated() {
            let angle = Double(index) * BoardGeometry.sectorWidthDegrees
            let position = Self.location(ofDrawn: BoardPoint(radius: Measure.numberRadius, clockwiseDegrees: angle), in: size)
            let text: Text
            if let style = styles[index], style.role != .inactive {
                text = Text(verbatim: String(number)).font(.system(size: fontSize, weight: .heavy)).foregroundStyle(style.color)
            } else {
                text = Text(verbatim: String(number)).font(.system(size: fontSize, weight: .semibold))
                    .foregroundStyle(Theme.Palette.textTertiary)
            }
            context.draw(text, at: position, anchor: .center)
        }
    }

    /// Label, hit-point pips and marker of the highlighted zones of beds.
    private func drawAnnotations(in context: inout GraphicsContext) {
        let pip = scaled(0.011, min: 3, max: 8)
        let gap = pip * 0.75
        for highlight in highlights {
            guard highlight.label != nil || highlight.strength != nil || highlight.marker != nil else { continue }
            guard let anchors = anchors(of: highlight.zone) else { continue }
            let style = Style(role: highlight.role, owner: highlight.owner, isOneRing: false)
            var top = anchors.label.y
            let label = highlight.label.map { pill(for: $0, style: style, in: context) }
            let height = (label?.size.height ?? 0) + (highlight.strength != nil ? pip : 0)
                + (label != nil && highlight.strength != nil ? gap : 0)
            top -= height / 2
            if let marker = highlight.marker {
                let diameter = scaled(0.062, min: 10, max: 30)
                drawMarker(marker, at: anchors.marker, diameter: diameter, in: &context)
                // On the bull the marker takes the centre: label and pips go just under it.
                if anchors.marker == anchors.label { top = anchors.marker.y + diameter / 2 + gap }
            }
            if let label {
                draw(label, at: CGPoint(x: anchors.label.x, y: top + label.size.height / 2), in: &context)
                top += label.size.height + gap
            }
            if let strength = highlight.strength {
                drawPips(filled: strength, at: CGPoint(x: anchors.label.x, y: top + pip / 2), diameter: pip, gap: gap,
                         color: Theme.Palette.textPrimary, in: &context)
            }
        }
    }

    /// Where the label and the marker of a zone go: the label in the middle of the zone (the outer single of a
    /// sector), the marker in the inner single; both at the centre for the bull. Nil for a disc and for a number
    /// that is not on the board.
    private func anchors(of zone: BoardZone) -> (label: CGPoint, marker: CGPoint)? {
        func middle(_ band: BoardGeometry.Band) -> Double {
            let range = geometry.radialRange(of: band)
            return (range.lowerBound + range.upperBound) / 2
        }
        let band: BoardGeometry.Band
        switch zone {
        case .sector, .single: band = .outerSingle
        case .double: band = .double
        case .treble: band = .treble
        case .outerBull, .innerBull, .bull: return (centre, centre)
        case .disc: return nil
        }
        guard let number = zone.number, let index = geometry.sectorOrder.firstIndex(of: number) else { return nil }
        let angle = Double(index) * BoardGeometry.sectorWidthDegrees
        return (Self.location(ofDrawn: BoardPoint(radius: middle(band), clockwiseDegrees: angle), in: size),
                Self.location(ofDrawn: BoardPoint(radius: middle(.innerSingle), clockwiseDegrees: angle), in: size))
    }

    /// Darts: a disc with a dark border; amber with "?" for a dart to check; an optional label beside it.
    private func drawDarts(in context: inout GraphicsContext) {
        let diameter = min(markerDiameter, max(6, side / 12))
        for dart in darts {
            let position = Self.location(of: dart.position, in: size, geometry: geometry)
            guard position.x.isFinite, position.y.isFinite else { continue }
            let color: Color
            var extent = diameter
            switch dart.style {
            case .neutral: color = Theme.Palette.textPrimary
            case .player(let index): color = Theme.playerColor(index)
            case .review:
                color = Theme.Palette.accent
                // Room for the question mark.
                extent = diameter * 1.4
            }
            // Mock-ups: a 3 pt border on a 14 pt disc, 5 pt on a 26 pt one.
            let border = dart.style == .review ? extent * 0.12 : extent * 0.2
            context.fill(circle(at: position, radius: extent / 2), with: .color(Theme.Palette.background))
            context.fill(circle(at: position, radius: extent / 2 - border), with: .color(color))
            if dart.style == .review {
                let mark = Text(verbatim: "?").font(.system(size: extent * 0.62, weight: .heavy))
                    .foregroundStyle(Theme.Palette.onAccent)
                context.draw(mark, at: position, anchor: .center)
            }
            if let text = dart.label, !text.isEmpty {
                let fontSize = scaled(0.034, min: 9, max: 16)
                let fill = dart.style == .review ? Theme.Palette.accent : Theme.Palette.background.opacity(0.85)
                let foreground = dart.style == .review ? Theme.Palette.onAccent : Theme.Palette.textPrimary
                let label = pill(text: text, fontSize: fontSize, fill: fill, foreground: foreground, in: context)
                // Beside the dart, on the side where there is room.
                let offset = extent / 2 + 3 + label.size.width / 2
                let x = position.x + offset + label.size.width / 2 <= size.width ? position.x + offset : position.x - offset
                let y = min(size.height - label.size.height / 2, max(label.size.height / 2, position.y - extent / 2))
                draw(label, at: CGPoint(x: x, y: y), in: &context)
            }
        }
    }

    // MARK: Small parts

    /// A solid rounded label, measured before it is placed.
    private struct Pill {
        var text: GraphicsContext.ResolvedText
        var size: CGSize
        var fill: Color
    }

    private func pill(for label: String, style: Style, in context: GraphicsContext) -> Pill {
        let inactive = style.role == .inactive
        return pill(text: label, fontSize: scaled(0.034, min: 8, max: 17),
                    fill: inactive ? Theme.Palette.surfaceRaised : style.color,
                    foreground: inactive ? Theme.Palette.textSecondary : Theme.Palette.onAccent, in: context)
    }

    private func pill(text: String, fontSize: CGFloat, fill: Color, foreground: Color, in context: GraphicsContext) -> Pill {
        let resolved = context.resolve(Text(verbatim: text).font(.system(size: fontSize, weight: .bold).monospacedDigit())
            .foregroundStyle(foreground))
        let measured = resolved.measure(in: CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude))
        let size = CGSize(width: max(measured.width + fontSize * 0.7, measured.height + 2), height: measured.height + 2)
        return Pill(text: resolved, size: size, fill: fill)
    }

    private func draw(_ pill: Pill, at point: CGPoint, in context: inout GraphicsContext) {
        let rect = CGRect(x: point.x - pill.size.width / 2, y: point.y - pill.size.height / 2,
                          width: pill.size.width, height: pill.size.height)
        context.fill(Path(roundedRect: rect, cornerRadius: pill.size.height / 2), with: .color(pill.fill))
        context.draw(pill.text, at: point, anchor: .center)
    }

    /// Three pips in a row: `filled` solid ones, the others hollow, so that colour is never the only carrier.
    private func drawPips(filled: Int, at point: CGPoint, diameter: CGFloat, gap: CGFloat, color: Color,
                          in context: inout GraphicsContext) {
        let total = 3
        let width = CGFloat(total) * diameter + CGFloat(total - 1) * gap
        for index in 0..<total {
            let middle = CGPoint(x: point.x - width / 2 + diameter / 2 + CGFloat(index) * (diameter + gap), y: point.y)
            // A dark rim keeps a pip readable on any bed.
            context.fill(circle(at: middle, radius: diameter / 2 + 0.75), with: .color(Theme.Palette.background.opacity(0.7)))
            if index < filled {
                context.fill(circle(at: middle, radius: diameter / 2), with: .color(color))
            } else {
                let line = max(1, diameter * 0.22)
                context.stroke(circle(at: middle, radius: diameter / 2 - line / 2), with: .color(color), lineWidth: line)
            }
        }
    }

    /// Conqueror home sector, King of the Hill, Fight heal number: an SF Symbol on a dark disc.
    private func drawMarker(_ marker: BoardMarker, at point: CGPoint, diameter: CGFloat, in context: inout GraphicsContext) {
        let name: String
        switch marker {
        case .home: name = "house.fill"
        case .crown: name = "crown.fill"
        case .heal: name = "cross.fill"
        }
        context.fill(circle(at: point, radius: diameter / 2), with: .color(Theme.Palette.background.opacity(0.85)))
        var symbol = context.resolve(Image(systemName: name))
        symbol.shading = .color(Theme.Palette.textPrimary)
        guard symbol.size.width > 0, symbol.size.height > 0 else { return }
        let scale = diameter * 0.6 / max(symbol.size.width, symbol.size.height)
        let rect = CGRect(x: point.x - symbol.size.width * scale / 2, y: point.y - symbol.size.height * scale / 2,
                          width: symbol.size.width * scale, height: symbol.size.height * scale)
        context.draw(symbol, in: rect)
    }
}
