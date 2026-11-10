import SwiftUI
import DartCore

extension BoardGeometry {
    /// Geometry of the DRAWN board (DESIGN.md §3): same bulls, thicker rings. Radii in the millimetre frame of
    /// `standard`: treble 97.0–110.5 (21.5 %–24.5 % of 451), double 160.1–173.6 (35.5 %–38.5 %).
    static let display = BoardGeometry(innerBullRadius: 6.35, outerBullRadius: 15.9,
                                       trebleInnerRadius: 97.0, trebleOuterRadius: 110.5,
                                       doubleInnerRadius: 160.1, doubleOuterRadius: 173.6, boardRadius: 225.5)
}

extension GameDescriptor {
    /// Geometry of the board drawn for this game: thick rings, except for a position-dependent game, whose board
    /// is drawn at regulation proportions so that a drawn disc covers exactly the disc of the game (DESIGN.md §4).
    var boardGeometry: BoardGeometry {
        dependsOnPosition ? .standard : .display
    }
}

/// A dart drawn on the board.
struct BoardDartMarker: Identifiable, Hashable {
    let id: UUID
    /// NOMINAL board millimetres (the view remaps to the display geometry).
    var position: BoardPoint
    var label: String?
    var style: Style

    enum Style: Hashable {
        /// Off-white disc.
        case neutral
        /// Disc in the colour of a player.
        case player(PlayerIndex)
        /// Amber disc with "?": to be checked.
        case review
    }
}

/// A tap on the drawn board, already converted.
struct BoardTap: Hashable {
    /// Hit under the finger, computed with the geometry of the DRAWING (a tap on the drawn treble ring is a treble).
    var hit: Hit
    /// The same point in NOMINAL millimetres: it becomes `DartRecord.position`.
    var position: BoardPoint
}

/// The one and only board drawing: play, manual input, correction, Killer levels, option pictograms.
/// Pure SwiftUI (`Canvas`), so it renders under `ImageRenderer`.
struct DartboardView: View {
    private let highlights: [BoardHighlight]
    private let darts: [BoardDartMarker]
    private let geometry: BoardGeometry
    private let dimsUnhighlighted: Bool
    private let showsNumbers: Bool
    private let onTap: ((BoardTap) -> Void)?
    private let onLongPress: ((BoardTap) -> Void)?

    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.appLanguage) private var language
    /// Where the long press already reported during the current touch began: a press is reported once.
    @State private var reportedPress: CGPoint?

    /// - Parameters:
    ///   - highlights: zones to tint (GAMES.md §2.9); a zone with an owner uses that player's colour. A `.disc`
    ///     zone is a circle drawn over the beds, with its label and its hit-point pips (DESIGN.md §4).
    ///   - darts: markers, in nominal millimetres.
    ///   - geometry: geometry of the drawing: `.display` (thick rings) or `.standard` (regulation proportions).
    ///     Pass `descriptor.boardGeometry`: a position-dependent game is always drawn with `.standard`.
    ///   - dimsUnhighlighted: darkens the rest of the board when at least one highlight exists (DESIGN.md §3).
    ///   - showsNumbers: number ring around the board.
    ///   - onTap: tap (manual input). Nil makes the board non-interactive.
    ///   - onLongPress: long press (opens the magnified view).
    init(highlights: [BoardHighlight] = [], darts: [BoardDartMarker] = [], geometry: BoardGeometry = .display,
         dimsUnhighlighted: Bool = true, showsNumbers: Bool = true,
         onTap: ((BoardTap) -> Void)? = nil, onLongPress: ((BoardTap) -> Void)? = nil) {
        self.highlights = highlights
        self.darts = darts
        self.geometry = geometry
        self.dimsUnhighlighted = dimsUnhighlighted
        self.showsNumbers = showsNumbers
        self.onTap = onTap
        self.onLongPress = onLongPress
    }

    var body: some View {
        GeometryReader { proxy in
            // The board is the largest square that fits, centred: the conversions below are written for a square.
            let side = min(proxy.size.width, proxy.size.height)
            let square = CGSize(width: side, height: side)
            interactive(board(square), in: square)
                .frame(width: side, height: side)
                .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: L10n.string("board.label", .common, language: language)))
        .accessibilityValue(Text(verbatim: accessibilityValue))
        .accessibilityAddTraits(isInteractive ? [.isImage, .allowsDirectInteraction] : .isImage)
    }

    private var isInteractive: Bool {
        onTap != nil || onLongPress != nil
    }

    private func board(_ size: CGSize) -> some View {
        let drawing = BoardDrawing(highlights: highlights, darts: darts, geometry: geometry,
                                   dimsUnhighlighted: dimsUnhighlighted, showsNumbers: showsNumbers,
                                   markerDiameter: Theme.Metrics(sizeClass).dartMarker, size: size)
        return Canvas { context, _ in
            drawing.draw(in: &context)
        }
    }

    /// Adds the gestures. A tap gives `onTap`; a press held for half a second gives `onLongPress` and no tap.
    @ViewBuilder
    private func interactive(_ board: some View, in size: CGSize) -> some View {
        if !isInteractive {
            board.allowsHitTesting(false)
        } else {
            let tap = SpatialTapGesture(coordinateSpace: .local).onEnded { value in
                onTap?(Self.tap(at: value.location, in: size, geometry: geometry))
            }
            if let onLongPress {
                // The press itself has no location: the drag that follows it gives the point under the finger,
                // at the first movement or, at the latest, when the finger lifts.
                let press = LongPressGesture(minimumDuration: 0.5)
                    .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .local))
                    .onChanged { value in
                        guard case .second(true, let drag?) = value, reportedPress != drag.startLocation else { return }
                        reportedPress = drag.startLocation
                        onLongPress(Self.tap(at: drag.startLocation, in: size, geometry: geometry))
                    }
                    .onEnded { value in
                        defer { reportedPress = nil }
                        guard case .second(true, let drag?) = value, reportedPress != drag.startLocation else { return }
                        onLongPress(Self.tap(at: drag.startLocation, in: size, geometry: geometry))
                    }
                board
                    .contentShape(Circle())
                    .gesture(press.exclusively(before: tap))
            } else {
                board
                    .contentShape(Circle())
                    .gesture(tap)
            }
        }
    }

    /// What VoiceOver reads after "Cible": the numbers to aim at, then the darts on the board.
    private var accessibilityValue: String {
        var parts: [String] = []
        let targets = BoardDrawing.targetNumbers(in: highlights)
        if !targets.isEmpty {
            let list = targets.map(String.init).joined(separator: ", ")
            parts.append(L10n.string("board.targets \(list)", .common, language: language))
        }
        if darts.count == 1 {
            parts.append(L10n.string("board.darts.one", .common, language: language))
        } else if darts.count > 1 {
            parts.append(L10n.string("board.darts.other \(darts.count)", .common, language: language))
        }
        let labels = darts.compactMap(\.label)
        if !labels.isEmpty {
            parts.append(labels.joined(separator: ", "))
        }
        return parts.joined(separator: ". ")
    }

    /// Conversion used by the view and by tests: a point of the view (origin top-left, `size` square) to a tap
    /// on a board drawn with `geometry`.
    static func tap(at location: CGPoint, in size: CGSize, geometry: BoardGeometry = .display) -> BoardTap {
        BoardDrawing.tap(at: location, in: size, geometry: geometry)
    }

    /// Position in the view of a nominal board point, on a board drawn with `geometry`.
    static func location(of position: BoardPoint, in size: CGSize, geometry: BoardGeometry = .display) -> CGPoint {
        BoardDrawing.location(of: position, in: size, geometry: geometry)
    }

    /// Length in the view, in points, of `millimetres` of board: the radius of a drawn disc.
    static func length(of millimetres: Double, in size: CGSize) -> CGFloat {
        CGFloat(millimetres) * BoardDrawing.scale(in: size)
    }
}
