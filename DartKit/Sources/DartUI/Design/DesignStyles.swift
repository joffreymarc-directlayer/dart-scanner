import SwiftUI
import DartCore

// Button styles and small drawn parts behind the components of `Components.swift`. Everything here is pure
// SwiftUI (shapes and text), so it renders under `ImageRenderer` (ARCHITECTURE.md §8.11). A screen that needs a
// button of its own takes one of these styles or `.plain`: a Button never keeps the default style.

extension Theme {
    /// `onAccent` or `textPrimary`, whichever reads best on `background` (WCAG contrast). Used where a fill
    /// colour is a parameter: a filled badge is amber, a player colour, or a neutral surface.
    static func readableForeground(on background: Color) -> Color {
        let fill = luminance(of: background)
        let dark = contrast(fill, luminance(of: Palette.onAccent))
        let light = contrast(fill, luminance(of: Palette.textPrimary))
        return dark >= light ? Palette.onAccent : Palette.textPrimary
    }

    /// Relative luminance of a colour of the palette (the theme is dark only: the environment does not matter).
    static func luminance(of color: Color) -> Double {
        let resolved = color.resolve(in: EnvironmentValues())
        return 0.2126 * Double(resolved.linearRed) + 0.7152 * Double(resolved.linearGreen)
            + 0.0722 * Double(resolved.linearBlue)
    }

    /// WCAG contrast ratio of two relative luminances, 1...21.
    static func contrast(_ a: Double, _ b: Double) -> Double {
        (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }
}

/// Icon and title of an action button.
struct DesignButtonLabel: View {
    let title: Text
    let systemImage: String?

    var body: some View {
        HStack(spacing: Theme.Spacing.inline) {
            if let systemImage {
                Image(systemName: systemImage)
            }
            title
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
    }
}

/// The two full-width actions of DESIGN.md §2: filled `accent`, or outlined.
struct DesignActionButtonStyle: ButtonStyle {
    enum Kind {
        case primary, secondary
    }

    let kind: Kind

    func makeBody(configuration: Configuration) -> some View {
        DesignActionButtonBody(kind: kind, configuration: configuration)
    }
}

private struct DesignActionButtonBody: View {
    let kind: DesignActionButtonStyle.Kind
    let configuration: ButtonStyle.Configuration
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
        configuration.label
            .font(kind == .primary ? Theme.Typography.button : Theme.Typography.buttonSecondary)
            .foregroundStyle(foreground)
            .padding(.horizontal, Theme.Spacing.section)
            .frame(maxWidth: .infinity, minHeight: Theme.Metrics(sizeClass).buttonHeight)
            .background(fill, in: shape)
            .overlay {
                if kind == .secondary {
                    shape.strokeBorder(Theme.Palette.line, lineWidth: Theme.Control.border)
                }
            }
            .contentShape(shape)
            .opacity(configuration.isPressed ? Theme.Control.pressedOpacity : 1)
    }

    private var foreground: Color {
        guard isEnabled else { return Theme.Palette.textTertiary }
        return kind == .primary ? Theme.Palette.onAccent : Theme.Palette.textPrimary
    }

    private var fill: Color {
        switch kind {
        case .primary: return isEnabled ? Theme.Palette.accent : Theme.Palette.surfaceRaised
        case .secondary: return .clear
        }
    }
}

/// A row or a segment that is itself the button: the label is drawn as it is, dimmed while pressed, and dimmed
/// when disabled unless the row draws its own disabled state.
struct DesignRowButtonStyle: ButtonStyle {
    var dimsWhenDisabled = true

    func makeBody(configuration: Configuration) -> some View {
        DesignRowButtonBody(dimsWhenDisabled: dimsWhenDisabled, configuration: configuration)
    }
}

private struct DesignRowButtonBody: View {
    let dimsWhenDisabled: Bool
    let configuration: ButtonStyle.Configuration
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        configuration.label
            .opacity(opacity)
    }

    private var opacity: Double {
        if !isEnabled { return dimsWhenDisabled ? Theme.Control.disabledOpacity : 1 }
        return configuration.isPressed ? Theme.Control.pressedOpacity : 1
    }
}

/// A 44 pt square key: `surface` background, 1 pt `line` border, radius 12 ("−" and "+" of a stepper row, an
/// icon-only action such as undo).
struct DesignSquareButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        DesignSquareButtonBody(configuration: configuration)
    }
}

private struct DesignSquareButtonBody: View {
    let configuration: ButtonStyle.Configuration
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
        configuration.label
            .foregroundStyle(isEnabled ? Theme.Palette.textPrimary : Theme.Palette.textTertiary)
            .opacity(isEnabled ? 1 : Theme.Control.disabledOpacity)
            .frame(minWidth: Theme.Control.touchTarget, minHeight: Theme.Control.touchTarget)
            .background(Theme.Palette.surface, in: shape)
            .overlay { shape.strokeBorder(Theme.Palette.line, lineWidth: Theme.Control.border) }
            .contentShape(shape)
            .opacity(configuration.isPressed ? Theme.Control.pressedOpacity : 1)
    }
}

/// The drawn switch of a toggle row (mock-up `Settings`): amber track and dark knob when on, `line` track and
/// grey knob when off. Not a control by itself: the row is the button.
struct DesignSwitch: View {
    let isOn: Bool

    var body: some View {
        Capsule()
            .fill(isOn ? Theme.Palette.accent : Theme.Palette.line)
            .frame(width: Theme.Control.switchSize.width, height: Theme.Control.switchSize.height)
            .overlay(alignment: isOn ? .trailing : .leading) {
                Circle()
                    .fill(isOn ? Theme.Palette.background : Theme.Palette.textSecondary)
                    .frame(width: Theme.Control.switchKnob, height: Theme.Control.switchKnob)
                    .padding(.horizontal, Theme.Control.switchInset)
            }
            .animation(.easeOut(duration: 0.15), value: isOn)
            .accessibilityHidden(true)
    }
}

/// The mark of a radio row: a ring, filled with an `accent` dot when selected.
struct DesignRadioMark: View {
    let isSelected: Bool

    var body: some View {
        Circle()
            .strokeBorder(isSelected ? Theme.Palette.accent : Theme.Palette.lineStrong,
                          lineWidth: Theme.Control.borderStrong)
            .frame(width: Theme.Control.radioMark, height: Theme.Control.radioMark)
            .overlay {
                if isSelected {
                    Circle()
                        .fill(Theme.Palette.accent)
                        .frame(width: Theme.Control.radioDot, height: Theme.Control.radioDot)
                }
            }
            .accessibilityHidden(true)
    }
}

/// Shape of a bubble over the camera image: a pill while it holds one line, a box of radius 14 once it is taller.
struct DesignBubbleShape: Shape {
    func path(in rect: CGRect) -> Path {
        let isOneLine = rect.height <= Theme.Control.touchTarget + Theme.Spacing.inline
        let radius = isOneLine ? rect.height / 2 : Theme.Radius.control
        return Path(roundedRect: rect, cornerRadius: min(radius, rect.width / 2), style: .continuous)
    }
}
