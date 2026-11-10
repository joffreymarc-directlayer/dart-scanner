import SwiftUI
import DartCore

/// Design tokens of DESIGN.md §2. Dark theme only. Views never write a colour, a radius or a font size literally.
enum Theme {
    enum Palette {
        static let background = Color(hex: 0x0E1114)
        static let surface = Color(hex: 0x171C21)
        static let surfaceRaised = Color(hex: 0x212830)
        static let line = Color(hex: 0x2E3640)
        static let lineStrong = Color(hex: 0x5A6470)
        static let textPrimary = Color(hex: 0xF3F1EA)
        static let textSecondary = Color(hex: 0xA9B1BA)
        static let textTertiary = Color(hex: 0x8A939D)
        static let accent = Color(hex: 0xFFA630)
        static let onAccent = Color(hex: 0x1A1206)
        static let info = Color(hex: 0x5CB2FF)
        static let boardRed = Color(hex: 0xD8413A)
        static let boardGreen = Color(hex: 0x2F9E5B)
        static let boardCream = Color(hex: 0xE9DFC7)
        static let boardBlack = Color(hex: 0x1B1F23)
        static let boardSurround = Color(hex: 0x0A0C0E)
        static let cameraScrim = Color(hex: 0x0E1114).opacity(0.78)
        /// Colours of players 1 to 8, by player index.
        static let players: [Color] = [0xFFA630, 0x5CB2FF, 0xB79CFF, 0xFF8FB8, 0x6FE0C8, 0xF2E26B, 0xFF8A5C, 0xC8D0D8].map { Color(hex: $0) }
    }

    static func playerColor(_ index: PlayerIndex) -> Color {
        Palette.players[((index % Palette.players.count) + Palette.players.count) % Palette.players.count]
    }

    static func color(for tone: Tone) -> Color {
        switch tone {
        case .neutral: return Palette.textSecondary
        case .positive: return Palette.boardGreen
        case .negative: return Palette.boardRed
        case .accent: return Palette.accent
        }
    }

    enum Radius {
        static let card: CGFloat = 16
        static let row: CGFloat = 12
        static let badge: CGFloat = 8
    }

    enum Spacing {
        /// Space between blocks of a game screen.
        static let block: CGFloat = 12
        static let section: CGFloat = 16
    }

    /// Values that differ between a compact and a regular width (iPhone vs iPad column).
    struct Metrics: Equatable {
        var screenMargin: CGFloat
        var buttonHeight: CGFloat
        var playerRowHeight: CGFloat
        var dartMarker: CGFloat
        var slotTitle: CGFloat
        var slotCaption: CGFloat

        static let compact = Metrics(screenMargin: 20, buttonHeight: 52, playerRowHeight: 44, dartMarker: 14, slotTitle: 17, slotCaption: 11)
        static let regular = Metrics(screenMargin: 32, buttonHeight: 56, playerRowHeight: 56, dartMarker: 26, slotTitle: 22, slotCaption: 13)

        init(screenMargin: CGFloat, buttonHeight: CGFloat, playerRowHeight: CGFloat, dartMarker: CGFloat, slotTitle: CGFloat, slotCaption: CGFloat) {
            self.screenMargin = screenMargin
            self.buttonHeight = buttonHeight
            self.playerRowHeight = playerRowHeight
            self.dartMarker = dartMarker
            self.slotTitle = slotTitle
            self.slotCaption = slotCaption
        }

        init(_ sizeClass: UserInterfaceSizeClass?) {
            self = sizeClass == .regular ? .regular : .compact
        }
    }

    enum Typography {
        static let screenTitle = Font.system(size: 28, weight: .heavy)
        static let gameTitle = Font.system(size: 20, weight: .heavy)
        static let bigScore = Font.system(size: 64, weight: .heavy).monospacedDigit()
        static let winner = Font.system(size: 88, weight: .heavy)
        static let body = Font.system(size: 16, weight: .regular)
        static let bodyStrong = Font.system(size: 16, weight: .semibold)
        static let secondary = Font.system(size: 13, weight: .regular)
        static let button = Font.system(size: 17, weight: .bold)
    }
}

extension Color {
    /// 0xRRGGBB in sRGB.
    init(hex: UInt32) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255, opacity: 1)
    }
}
