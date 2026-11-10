import SwiftUI
import DartCore

// Tokens of the hand-drawn controls, read on the approved mock-ups (Settings, KillerOptions, Main, Results,
// PlayKiller, LiveScan). `Theme.swift` is the printed listing of ARCHITECTURE.md §8.4.1 and stays as it is; what
// the components need on top of it lives here, so that no view writes a colour, a radius or a font size literally.

extension Theme.Radius {
    /// Radio rows, text bubbles over the camera image.
    static let control: CGFloat = 14
    /// Track of a segmented choice.
    static let segmentTrack: CGFloat = 11
}

extension Theme.Spacing {
    /// Between an icon or a mark and its text.
    static let inline: CGFloat = 8
    /// Between two text lines of one row.
    static let lines: CGFloat = 2
    /// Between the parts of a row.
    static let row: CGFloat = 12
    /// Side inset of the rows inside a settings card (mock-up `Settings`).
    static let cardInset: CGFloat = 14
}

extension Theme.Typography {
    /// Secondary button: 17 semibold (mock-up `Results`).
    static let buttonSecondary = Font.system(size: 17, weight: .semibold)
    /// Title of a radio row: 16 bold.
    static let rowTitle = Font.system(size: 16, weight: .bold)
    /// Player name in a chip, text of a bubble: 15 semibold.
    static let chip = Font.system(size: 15, weight: .semibold)
    /// Selected and unselected segment: 14 bold / 14 semibold.
    static let segmentSelected = Font.system(size: 14, weight: .bold)
    static let segment = Font.system(size: 14, weight: .semibold)
    /// Badge: 12 bold.
    static let badge = Font.system(size: 12, weight: .bold)
    /// Value of a stepper row: 18 bold, tabular digits.
    static let stepperValue = Font.system(size: 18, weight: .bold).monospacedDigit()
    /// "−" and "+" of a stepper row, the mark of a radio row.
    static let controlSymbol = Font.system(size: 17, weight: .semibold)
    /// Initial inside the disc of a player chip.
    static let initial = Font.system(size: 13, weight: .heavy)
}

extension Theme {
    /// Sizes of the controls (DESIGN.md §1: touch targets of at least 44 pt).
    enum Control {
        /// Smallest touch target.
        static let touchTarget: CGFloat = 44
        /// Row with one text line, with two.
        static let rowHeight: CGFloat = 52
        static let tallRowHeight: CGFloat = 60
        static let radioRowHeight: CGFloat = 62
        /// Switch: 52 × 32 track, 26 pt knob, 3 pt from the edge.
        static let switchSize = CGSize(width: 52, height: 32)
        static let switchKnob: CGFloat = 26
        static let switchInset: CGFloat = 3
        /// Segmented choice: 38 pt segments inside a 3 pt padded track.
        static let segmentHeight: CGFloat = 38
        static let segmentInset: CGFloat = 3
        static let segmentGap: CGFloat = 4
        /// Radio mark.
        static let radioMark: CGFloat = 20
        static let radioDot: CGFloat = 10
        /// Pictogram at the end of a radio row.
        static let accessory: CGFloat = 36
        /// Disc of a player chip.
        static let chipDisc: CGFloat = 28
        /// Level slider: 6 pt track, 26 pt thumb.
        static let sliderTrack: CGFloat = 6
        static let sliderThumb: CGFloat = 26
        /// Borders: hairline, emphasised (selection, current player), badge outline.
        static let border: CGFloat = 1
        static let borderStrong: CGFloat = 2
        static let borderBadge: CGFloat = 1.5
        /// Opacity of a pressed control, of the content of a disabled one.
        static let pressedOpacity: Double = 0.75
        static let disabledOpacity: Double = 0.45
    }
}
