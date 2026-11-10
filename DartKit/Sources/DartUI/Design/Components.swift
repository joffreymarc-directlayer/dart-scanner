import SwiftUI
import DartCore

// Shared components (DESIGN.md §2). All of them are drawn with SwiftUI shapes and text only. System controls
// (Toggle, Slider, Picker, Stepper, TextField, a Button with the default style) are not used in screen contents:
// `ImageRenderer` draws a placeholder instead of them, and they do not match the dark theme.
// Every Button carries a ButtonStyle written in SwiftUI (or `.plain`).

/// Main action: `accent` background, `onAccent` text, 52 pt high (56 in regular width), radius 16.
struct PrimaryButton: View {
    private let title: Text
    private let systemImage: String?
    private let isEnabled: Bool
    private let action: () -> Void

    init(_ title: Text, systemImage: String? = nil, isEnabled: Bool = true, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.isEnabled = isEnabled
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            DesignButtonLabel(title: title, systemImage: systemImage)
        }
        .buttonStyle(DesignActionButtonStyle(kind: .primary))
        .disabled(!isEnabled)
    }
}

/// Secondary action: same height, 1 pt `line` border, transparent background.
struct SecondaryButton: View {
    private let title: Text
    private let systemImage: String?
    private let isEnabled: Bool
    private let action: () -> Void

    init(_ title: Text, systemImage: String? = nil, isEnabled: Bool = true, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.isEnabled = isEnabled
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            DesignButtonLabel(title: title, systemImage: systemImage)
        }
        .buttonStyle(DesignActionButtonStyle(kind: .secondary))
        .disabled(!isEnabled)
    }
}

/// `surface` background, radius 16, optional border (current player: 2 pt in the player's colour).
/// Without a border colour the card has the 1 pt `line` hairline of the mock-ups. The card adds NO padding: the
/// mock-ups use 12, 14 or none (rows separated by hairlines), so the content brings its own.
struct Card<Content: View>: View {
    private let border: Color?
    private let content: Content

    init(border: Color? = nil, @ViewBuilder content: () -> Content) {
        self.border = border
        self.content = content()
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
        content
            .background(Theme.Palette.surface, in: shape)
            .overlay {
                shape.strokeBorder(border ?? Theme.Palette.line,
                                   lineWidth: border == nil ? Theme.Control.border : Theme.Control.borderStrong)
            }
    }
}

/// Small capsule, radius 8: "Killer", "À vérifier", "Scan en direct".
/// Filled: `color` background and the readable text colour on it. Not filled: `color` outline and text.
struct BadgeView: View {
    private let text: Text
    private let color: Color
    private let filled: Bool

    init(_ text: Text, color: Color, filled: Bool = false) {
        self.text = text
        self.color = color
        self.filled = filled
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.badge, style: .continuous)
        text
            .font(Theme.Typography.badge)
            .foregroundStyle(filled ? Theme.readableForeground(on: color) : color)
            .lineLimit(1)
            .padding(.horizontal, Theme.Spacing.inline)
            .padding(.vertical, Theme.Spacing.lines)
            .background(filled ? color : Color.clear, in: shape)
            .overlay {
                if !filled {
                    shape.strokeBorder(color, lineWidth: Theme.Control.borderBadge)
                }
            }
    }
}

/// Coloured disc with the player's initial, optionally followed by the name.
struct PlayerChip: View {
    private let name: String
    private let index: PlayerIndex
    private let showsName: Bool

    init(name: String, index: PlayerIndex, showsName: Bool = true) {
        self.name = name
        self.index = index
        self.showsName = showsName
    }

    var body: some View {
        HStack(spacing: Theme.Spacing.inline) {
            Text(verbatim: Self.initial(of: name))
                .font(Theme.Typography.initial)
                .foregroundStyle(Theme.Palette.onAccent)
                .frame(width: Theme.Control.chipDisc, height: Theme.Control.chipDisc)
                .background(Theme.playerColor(index), in: Circle())
            if showsName {
                Text(verbatim: name)
                    .font(Theme.Typography.chip)
                    .foregroundStyle(Theme.Palette.textPrimary)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: name))
    }

    /// First letter or digit of the name, upper case; "?" for a name without any.
    static func initial(of name: String) -> String {
        guard let first = name.first(where: { $0.isLetter || $0.isNumber }) else { return "?" }
        return String(first).uppercased()
    }
}

/// Bubble laid over the camera image (`cameraScrim` background).
/// One line gives a 44 pt pill; several lines give a rounded box (mock-ups `LiveScan`, `Calibration`).
struct ScrimBubble<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .font(Theme.Typography.chip)
            .foregroundStyle(Theme.Palette.textPrimary)
            .padding(.horizontal, Theme.Spacing.section)
            .padding(.vertical, Theme.Spacing.block)
            .frame(minHeight: Theme.Control.touchTarget)
            .background(Theme.Palette.cameraScrim, in: DesignBubbleShape())
    }
}

/// Settings row with a switch.
/// The whole row is the touch target. Disabled, it keeps its value and is dimmed.
struct ToggleRow: View {
    private let title: Text
    private let subtitle: Text?
    private let isOn: Binding<Bool>
    private let isEnabled: Bool

    init(_ title: Text, subtitle: Text? = nil, isOn: Binding<Bool>, isEnabled: Bool = true) {
        self.title = title
        self.subtitle = subtitle
        self.isOn = isOn
        self.isEnabled = isEnabled
    }

    var body: some View {
        Button {
            isOn.wrappedValue.toggle()
        } label: {
            HStack(spacing: Theme.Spacing.row) {
                VStack(alignment: .leading, spacing: Theme.Spacing.lines) {
                    title
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Palette.textPrimary)
                    if let subtitle {
                        subtitle
                            .font(Theme.Typography.secondary)
                            .foregroundStyle(Theme.Palette.textSecondary)
                    }
                }
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                DesignSwitch(isOn: isOn.wrappedValue)
            }
            .frame(minHeight: subtitle == nil ? Theme.Control.rowHeight : Theme.Control.tallRowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(DesignRowButtonStyle())
        .disabled(!isEnabled)
        // The button stays the accessibility element (its label reads the title, then the subtitle).
        .accessibilityValue(L10n.text(isOn.wrappedValue ? "control.on" : "control.off", .common))
        .accessibilityAddTraits(.isToggle)
    }
}

/// "−  3  +" row (lives, arming hits, rounds). `nullLabel` adds a value below the range that maps to nil.
struct StepperRow: View {
    private let title: Text
    private let value: Binding<Int?>
    private let range: ClosedRange<Int>
    private let nullLabel: Text?

    init(_ title: Text, value: Binding<Int?>, range: ClosedRange<Int>, nullLabel: Text? = nil) {
        self.title = title
        self.value = value
        self.range = range
        self.nullLabel = nullLabel
    }

    var body: some View {
        let down = Self.step(.down, from: value.wrappedValue, in: range, allowsNull: nullLabel != nil)
        let up = Self.step(.up, from: value.wrappedValue, in: range, allowsNull: nullLabel != nil)
        HStack(spacing: Theme.Spacing.inline) {
            title
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Palette.textPrimary)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            stepButton(systemImage: "minus", label: "control.decrease", move: down)
            valueLabel
                .foregroundStyle(Theme.Palette.textPrimary)
                .lineLimit(1)
                .frame(minWidth: Theme.Control.chipDisc)
            stepButton(systemImage: "plus", label: "control.increase", move: up)
        }
        .frame(minHeight: Theme.Control.touchTarget)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(valueLabel)
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: apply(up)
            case .decrement: apply(down)
            @unknown default: break
            }
        }
    }

    private var valueLabel: Text {
        if let number = value.wrappedValue {
            return Text(verbatim: String(number)).font(Theme.Typography.stepperValue)
        }
        return (nullLabel ?? Text(verbatim: "–")).font(Theme.Typography.bodyStrong)
    }

    private func stepButton(systemImage: String, label: LocalizedStringKey, move: Move) -> some View {
        Button {
            apply(move)
        } label: {
            Image(systemName: systemImage)
                .font(Theme.Typography.controlSymbol)
                .frame(width: Theme.Control.touchTarget, height: Theme.Control.touchTarget)
        }
        .buttonStyle(DesignSquareButtonStyle())
        .disabled(move == .unavailable)
        .accessibilityLabel(L10n.text(label, .common))
    }

    private func apply(_ move: Move) {
        switch move {
        case .unavailable: break
        case .null: value.wrappedValue = nil
        case .to(let number): value.wrappedValue = number
        }
    }

    enum Direction {
        case down, up
    }

    /// Where a press on "−" or "+" leads.
    enum Move: Equatable {
        /// The button is disabled.
        case unavailable
        /// The value below the range, stored as nil (`nullLabel`).
        case null
        case to(Int)
    }

    /// The step rule, a pure function. The values are ordered `null < range.lowerBound < … < range.upperBound`,
    /// `null` existing only when `allowsNull`. A value outside the range comes back to its nearest bound; nil
    /// without `allowsNull` (a value that was never set) is below everything, and "+" gives the lower bound.
    static func step(_ direction: Direction, from value: Int?, in range: ClosedRange<Int>, allowsNull: Bool) -> Move {
        guard let value else {
            return direction == .up ? .to(range.lowerBound) : .unavailable
        }
        switch direction {
        case .up:
            if value < range.lowerBound { return .to(range.lowerBound) }
            return value < range.upperBound ? .to(value + 1) : .unavailable
        case .down:
            if value > range.upperBound { return .to(range.upperBound) }
            if value > range.lowerBound { return .to(value - 1) }
            return allowsNull ? .null : .unavailable
        }
    }
}

/// Two to four mutually exclusive segments ("Français | English", "En direct | Photo").
/// Takes the width it is given; every segment has the same width and a 44 pt high touch target.
struct SegmentedChoice<Value: Hashable>: View {
    private let options: [(value: Value, label: Text)]
    private let selection: Binding<Value>

    init(options: [(value: Value, label: Text)], selection: Binding<Value>) {
        self.options = options
        self.selection = selection
    }

    var body: some View {
        HStack(spacing: Theme.Control.segmentGap) {
            ForEach(options.indices, id: \.self) { index in
                segment(options[index])
            }
        }
        .padding(.horizontal, Theme.Control.segmentInset)
        .background(Theme.Palette.background,
                    in: RoundedRectangle(cornerRadius: Theme.Radius.segmentTrack, style: .continuous))
    }

    private func segment(_ option: (value: Value, label: Text)) -> some View {
        let isSelected = option.value == selection.wrappedValue
        return Button {
            selection.wrappedValue = option.value
        } label: {
            option.label
                .font(isSelected ? Theme.Typography.segmentSelected : Theme.Typography.segment)
                .foregroundStyle(isSelected ? Theme.Palette.background : Theme.Palette.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.horizontal, Theme.Spacing.inline)
                .frame(maxWidth: .infinity)
                .frame(height: Theme.Control.segmentHeight)
                .background(isSelected ? Theme.Palette.textPrimary : Color.clear,
                            in: RoundedRectangle(cornerRadius: Theme.Radius.badge, style: .continuous))
                // The pill is 38 pt high; the touch target is the full 44 pt of the track.
                .padding(.vertical, Theme.Control.segmentInset)
                .contentShape(Rectangle())
        }
        .buttonStyle(DesignRowButtonStyle())
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

/// Radio row with a detail line, an optional pictogram and the note shown when it is unavailable (Killer levels).
/// Selected: 2 pt `accent` border. Unavailable (`isEnabled == false`): dimmed, not tappable, and `note` says why.
struct RadioRow<Accessory: View>: View {
    private let title: Text
    private let detail: Text?
    private let note: Text?
    private let isSelected: Bool
    private let isEnabled: Bool
    private let accessory: Accessory
    private let action: () -> Void

    init(title: Text, detail: Text? = nil, note: Text? = nil, isSelected: Bool, isEnabled: Bool = true,
         @ViewBuilder accessory: () -> Accessory, action: @escaping () -> Void) {
        self.title = title
        self.detail = detail
        self.note = note
        self.isSelected = isSelected
        self.isEnabled = isEnabled
        self.accessory = accessory()
        self.action = action
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
        Button(action: action) {
            HStack(spacing: Theme.Spacing.row) {
                DesignRadioMark(isSelected: isSelected)
                    .opacity(isEnabled ? 1 : Theme.Control.disabledOpacity)
                VStack(alignment: .leading, spacing: Theme.Spacing.lines) {
                    title
                        .font(Theme.Typography.rowTitle)
                        .foregroundStyle(Theme.Palette.textPrimary)
                        .opacity(isEnabled ? 1 : Theme.Control.disabledOpacity)
                    if let detail {
                        detail
                            .font(Theme.Typography.secondary)
                            .foregroundStyle(Theme.Palette.textSecondary)
                            .opacity(isEnabled ? 1 : Theme.Control.disabledOpacity)
                    }
                    if !isEnabled, let note {
                        // The reason stays at full contrast: it is the one thing to read on a greyed row.
                        note
                            .font(Theme.Typography.secondary)
                            .foregroundStyle(Theme.Palette.textSecondary)
                    }
                }
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                accessory
                    .opacity(isEnabled ? 1 : Theme.Control.disabledOpacity)
            }
            .padding(.horizontal, Theme.Spacing.row)
            .padding(.vertical, Theme.Spacing.inline)
            .frame(minHeight: Theme.Control.radioRowHeight)
            .background(Theme.Palette.surface, in: shape)
            .overlay {
                shape.strokeBorder(isSelected ? Theme.Palette.accent : Theme.Palette.line,
                                   lineWidth: isSelected ? Theme.Control.borderStrong : Theme.Control.border)
            }
            .contentShape(shape)
        }
        .buttonStyle(DesignRowButtonStyle(dimsWhenDisabled: false))
        .disabled(!isEnabled)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

extension RadioRow where Accessory == EmptyView {
    /// A radio row without a pictogram.
    init(title: Text, detail: Text? = nil, note: Text? = nil, isSelected: Bool, isEnabled: Bool = true,
         action: @escaping () -> Void) {
        self.init(title: title, detail: detail, note: note, isSelected: isSelected, isEnabled: isEnabled,
                  accessory: { EmptyView() }, action: action)
    }
}

/// Horizontal level 0...1 (volume).
/// 44 pt high, as wide as it is given. A tap or a drag sets the level; VoiceOver adjusts it by tenths.
struct LevelSlider: View {
    private let value: Binding<Double>

    init(value: Binding<Double>) {
        self.value = value
    }

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let centre = Self.thumbCentre(for: value.wrappedValue, width: width)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Theme.Palette.line)
                    .frame(height: Theme.Control.sliderTrack)
                Capsule()
                    .fill(Theme.Palette.accent)
                    .frame(width: max(0, centre), height: Theme.Control.sliderTrack)
                Circle()
                    .fill(Theme.Palette.textPrimary)
                    .overlay { Circle().strokeBorder(Theme.Palette.background, lineWidth: Theme.Control.borderStrong) }
                    .frame(width: Theme.Control.sliderThumb, height: Theme.Control.sliderThumb)
                    .offset(x: centre - Theme.Control.sliderThumb / 2)
            }
            .frame(width: width, height: proxy.size.height, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture { location in
                value.wrappedValue = Self.level(at: location.x, width: width)
            }
            .gesture(DragGesture(minimumDistance: 2).onChanged { drag in
                value.wrappedValue = Self.level(at: drag.location.x, width: width)
            })
        }
        .frame(height: Theme.Control.touchTarget)
        .accessibilityElement(children: .ignore)
        .accessibilityValue(Text(verbatim: "\(Int((Self.clamped(value.wrappedValue) * 100).rounded())) %"))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: value.wrappedValue = Self.clamped(Self.clamped(value.wrappedValue) + Self.accessibilityStep)
            case .decrement: value.wrappedValue = Self.clamped(Self.clamped(value.wrappedValue) - Self.accessibilityStep)
            @unknown default: break
            }
        }
    }

    private static let accessibilityStep = 0.1

    /// A level in 0...1; a value that is not a number counts as 0.
    static func clamped(_ level: Double) -> Double {
        guard !level.isNaN else { return 0 }
        return min(1, max(0, level))
    }

    /// Level under a touch at `x` in a slider `width` wide: the thumb centre travels from half a thumb to
    /// `width` minus half a thumb, so that the thumb never leaves the track.
    static func level(at x: CGFloat, width: CGFloat) -> Double {
        let travel = width - Theme.Control.sliderThumb
        guard travel > 0, x.isFinite else { return 0 }
        return clamped(Double((x - Theme.Control.sliderThumb / 2) / travel))
    }

    /// Centre of the thumb for a level, the inverse of `level(at:width:)`.
    static func thumbCentre(for level: Double, width: CGFloat) -> CGFloat {
        let travel = max(0, width - Theme.Control.sliderThumb)
        return Theme.Control.sliderThumb / 2 + CGFloat(clamped(level)) * travel
    }
}
