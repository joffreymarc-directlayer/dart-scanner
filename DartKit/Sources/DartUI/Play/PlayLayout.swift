import CoreGraphics

/// Layout of the play screen for a container size (never for a device idiom).
enum PlayLayout: Equatable {
    /// Header, current player, board, players, actions: one column (portrait).
    case stacked
    /// Board on the left over the full height, scrollable column on the right (landscape).
    case sideBySide

    static func resolve(for size: CGSize) -> PlayLayout {
        size.width > size.height ? .sideBySide : .stacked
    }
}
