import SwiftUI
import DartCore

/// Players and options of one game, driven by its `GameDescriptor`.
struct SetupScreen: View {
    private let game: GameID

    @Environment(AppModel.self) private var app
    @Environment(\.appLanguage) private var language
    @State private var state: SetupState?
    @State private var showsAdvanced = false
    @State private var picksPlayer = false
    @State private var levelsOption: String?
    @State private var error: String?

    init(game: GameID) {
        self.game = game
    }

    var body: some View {
        Group {
            if let state {
                ScrollView {
                    SetupForm(state: state, actions: actions, showsAdvanced: showsAdvanced, showsHeader: false)
                }
                .scrollIndicators(.hidden)
                .safeAreaInset(edge: .bottom) {
                    SetupFooter(state: state, error: error, start: start)
                        .background(Theme.Palette.background)
                }
                .navigationTitle(Text(verbatim: state.descriptor.name[language]))
            } else {
                Color.clear
            }
        }
        .onAppear(perform: load)
        .onChange(of: app.roster) { _, roster in state?.follow(roster: roster) }
        .sheet(isPresented: $picksPlayer) {
            if let state {
                SetupPlayerPicker(available: app.roster.filter { player in !state.players.contains { $0.id == player.id } },
                                  canAdd: state.canAddPlayer,
                                  pick: { player in self.state?.add(player) },
                                  create: create,
                                  manage: {
                                      picksPlayer = false
                                      app.path.append(.players)
                                  },
                                  close: { picksPlayer = false })
                    .appLanguage(app.language)
                    .preferredColorScheme(.dark)
            }
        }
        .sheet(item: Binding(get: { levelsOption.map(SetupLevelsTarget.init) }, set: { levelsOption = $0?.key })) { target in
            if let state, let option = state.descriptor.option(target.key) {
                ScrollView {
                    SetupLevelsContent(descriptor: state.descriptor, option: option, close: { levelsOption = nil })
                }
                .background(Theme.Palette.background.ignoresSafeArea())
                .appLanguage(app.language)
                .preferredColorScheme(.dark)
            }
        }
    }

    private var actions: SetupActions {
        SetupActions(
            back: { if !app.path.isEmpty { app.path.removeLast() } },
            remove: { player in state?.remove(player) },
            addPlayer: { picksPlayer = true },
            set: { value, option in state?.set(value, for: option) },
            toggleAdvanced: { showsAdvanced.toggle() },
            showLevels: { levelsOption = $0.key })
    }

    private func load() {
        guard state == nil, let descriptor = app.environment.registry.definition(for: game)?.descriptor else { return }
        state = SetupState(descriptor: descriptor, roster: app.roster, memory: app.storage.loadSetup(for: game))
    }

    /// A new player joins the roster and the game.
    private func create(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let player = Player(name: trimmed)
        app.roster.append(player)
        state?.add(player)
    }

    private func start() {
        guard let state else { return }
        error = Self.start(state, app: app, language: language)
    }

    /// `AppModel.startGame`, then the choices of this game are remembered (§8.5, §8.10). Returns the sentence to
    /// show when the game cannot start, nil when it started.
    @discardableResult
    static func start(_ state: SetupState, app: AppModel, language: AppLanguage) -> String? {
        guard state.canStart else { return nil }
        do {
            try app.startGame(state.descriptor.id, players: state.players, options: state.options)
            app.storage.save(state.memory, for: state.descriptor.id)
            return nil
        } catch {
            return L10n.message(for: error, language: language)
        }
    }
}

private struct SetupLevelsTarget: Identifiable {
    var key: String
    var id: String { key }
}

struct SetupActions {
    var back: () -> Void = {}
    var remove: (Player) -> Void = { _ in }
    var addPlayer: () -> Void = {}
    var set: (OptionValue, OptionDescriptor) -> Void = { _, _ in }
    var toggleAdvanced: () -> Void = {}
    var showLevels: (OptionDescriptor) -> Void = { _ in }
}

/// The setup screen without its shell (mock-up `KillerOptions`): the form, then the start button at the bottom.
struct SetupContent: View {
    let state: SetupState
    var actions = SetupActions()
    var showsAdvanced = false

    var body: some View {
        // As in the app, the start button stays at the bottom over the form.
        Color.clear
            .overlay(alignment: .top) {
                SetupForm(state: state, actions: actions, showsAdvanced: showsAdvanced, showsHeader: true)
            }
            .overlay(alignment: .bottom) {
                SetupFooter(state: state, error: nil, start: {})
                    .background(Theme.Palette.background)
            }
            .clipped()
    }
}

/// Title, rule in one line, players, options.
struct SetupForm: View {
    let state: SetupState
    let actions: SetupActions
    let showsAdvanced: Bool
    var showsHeader = true

    @Environment(\.appLanguage) private var language
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        let metrics = Theme.Metrics(sizeClass)
        VStack(alignment: .leading, spacing: 14) {
            if showsHeader {
                HStack(spacing: Theme.Spacing.inline) {
                    Button(action: actions.back) {
                        Image(systemName: "chevron.left")
                            .font(SetupFonts.back)
                            .frame(width: Theme.Control.touchTarget, height: Theme.Control.touchTarget)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(DesignRowButtonStyle())
                    .padding(.leading, -10)
                    .accessibilityLabel(L10n.text("common.back", .common))
                    LocalizedTextView(state.descriptor.name)
                        .font(Theme.Typography.screenTitle)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .frame(height: Theme.Control.touchTarget)
            }
            LocalizedTextView(state.descriptor.pitch)
                .font(SetupFonts.pitch)
                .foregroundStyle(Theme.Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            playersSection
            ForEach(state.mainOptions) { option in
                SetupOptionView(state: state, option: option, actions: actions)
            }
            if !state.advancedOptions.isEmpty {
                Button(action: actions.toggleAdvanced) {
                    HStack {
                        L10n.text(showsAdvanced ? "setup.fewerOptions" : "setup.moreOptions", .game)
                            .font(Theme.Typography.body)
                            .foregroundStyle(Theme.Palette.textPrimary)
                        Spacer(minLength: 0)
                        Image(systemName: showsAdvanced ? "chevron.up" : "chevron.down")
                            .foregroundStyle(Theme.Palette.textSecondary)
                    }
                    .frame(minHeight: Theme.Control.touchTarget)
                    .contentShape(Rectangle())
                }
                .buttonStyle(DesignRowButtonStyle())
                if showsAdvanced {
                    ForEach(state.advancedOptions) { option in
                        SetupOptionView(state: state, option: option, actions: actions)
                    }
                }
            }
        }
        .padding(.horizontal, metrics.screenMargin)
        .padding(.vertical, Theme.Spacing.section)
        .frame(maxWidth: sizeClass == .regular ? 640 : .infinity, alignment: .topLeading)
        .frame(maxWidth: .infinity)
    }

    private var playersSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.inline) {
            L10n.text("setup.players", .game)
                .font(SetupFonts.section)
                .foregroundStyle(Theme.Palette.textSecondary)
            SetupFlowLayout(spacing: Theme.Spacing.inline) {
                ForEach(Array(state.players.enumerated()), id: \.element.id) { index, player in
                    Button { actions.remove(player) } label: {
                        HStack(spacing: Theme.Spacing.inline) {
                            Circle().fill(Theme.playerColor(index)).frame(width: 10, height: 10)
                            Text(verbatim: player.name)
                                .font(Theme.Typography.chip)
                                .foregroundStyle(Theme.Palette.textPrimary)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 14)
                        .frame(height: Theme.Control.touchTarget)
                        .background(Theme.Palette.surface, in: Capsule())
                        .overlay { Capsule().strokeBorder(Theme.Palette.line, lineWidth: Theme.Control.border) }
                        .contentShape(Capsule())
                    }
                    .buttonStyle(DesignRowButtonStyle())
                    .accessibilityLabel(L10n.text("setup.removePlayer \(player.name)", .game))
                }
                if state.canAddPlayer {
                    Button(action: actions.addPlayer) {
                        Image(systemName: "plus")
                            .font(SetupFonts.add)
                            .foregroundStyle(Theme.Palette.textSecondary)
                            .frame(width: Theme.Control.touchTarget, height: Theme.Control.touchTarget)
                            .overlay {
                                Circle().strokeBorder(Theme.Palette.lineStrong, style: StrokeStyle(lineWidth: Theme.Control.border, dash: [3, 3]))
                            }
                            .contentShape(Circle())
                    }
                    .buttonStyle(DesignRowButtonStyle())
                    .accessibilityLabel(L10n.text("setup.addPlayer", .game))
                }
            }
        }
    }
}

/// One option, drawn by its kind (table of ARCHITECTURE.md §8.5).
private struct SetupOptionView: View {
    let state: SetupState
    let option: OptionDescriptor
    let actions: SetupActions
    @Environment(\.appLanguage) private var language

    var body: some View {
        switch SetupControl(option.kind) {
        case .toggle:
            ToggleRow(Text(verbatim: option.label[language]), subtitle: option.help.map { Text(verbatim: $0[language]) },
                      isOn: Binding(get: { state.value(of: option) == .bool(true) },
                                    set: { actions.set(.bool($0), option) }))
        case .stepper(let range):
            StepperRow(Text(verbatim: option.label[language]), value: intBinding, range: range)
        case .optionalStepper(let range, let nullLabel):
            StepperRow(Text(verbatim: option.label[language]), value: intBinding, range: range,
                       nullLabel: Text(verbatim: nullLabel[language]))
        case .segmented(let choices):
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Theme.Spacing.row) {
                    Text(verbatim: option.label[language])
                        .font(Theme.Typography.body)
                        .lineLimit(1)
                        .fixedSize()
                    Spacer(minLength: 0)
                    // Inline only when every label fits whole: the ideal width of the segments, at least 94 each.
                    segments(choices)
                        .frame(minWidth: CGFloat(choices.count) * 94)
                        .fixedSize()
                }
                VStack(alignment: .leading, spacing: Theme.Spacing.inline) {
                    Text(verbatim: option.label[language])
                        .font(Theme.Typography.body)
                    segments(choices)
                }
            }
            .frame(minHeight: Theme.Control.touchTarget)
        case .radio(let choices):
            VStack(alignment: .leading, spacing: Theme.Spacing.inline) {
                HStack {
                    Text(verbatim: option.label[language])
                        .font(SetupFonts.section)
                        .foregroundStyle(Theme.Palette.textSecondary)
                    Spacer(minLength: 0)
                    if choices.contains(where: { $0.illustration != nil }) {
                        // 28 pt in the line of the title, 44 pt to the finger (DESIGN.md §1): the button is laid
                        // over a placeholder of the link's size (`PlayTouchTarget`).
                        levelsLink
                            .frame(minHeight: 28)
                            .hidden()
                            .overlay {
                                Button { actions.showLevels(option) } label: {
                                    levelsLink
                                        .frame(minHeight: Theme.Control.touchTarget)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(DesignRowButtonStyle())
                            }
                            .zIndex(1)
                    }
                }
                ForEach(choices, id: \.value) { choice in
                    radioRow(choice)
                }
            }
        }
    }

    private var levelsLink: some View {
        HStack(spacing: 4) {
            Image(systemName: "info.circle")
            L10n.text("setup.levels", .game)
        }
        .font(SetupFonts.link)
        .foregroundStyle(Theme.Palette.accent)
    }

    private var intBinding: Binding<Int?> {
        Binding(get: {
            if case .int(let number) = state.value(of: option) { return number }
            return nil
        }, set: { number in
            actions.set(number.map(OptionValue.int) ?? .null, option)
        })
    }

    private func segments(_ choices: [OptionChoice]) -> some View {
        SegmentedChoice(options: choices.map { (value: $0.value, label: Text(verbatim: $0.label[language])) },
                        selection: Binding(get: { state.value(of: option) }, set: { actions.set($0, option) }))
    }

    private func radioRow(_ choice: OptionChoice) -> some View {
        let available = state.isAvailable(choice)
        return RadioRow(title: Text(verbatim: choice.label[language]),
                        detail: choice.detail.map { Text(verbatim: $0[language]) },
                        note: choice.unavailableNote.map { Text(verbatim: $0[language]) },
                        isSelected: state.value(of: option) == choice.value, isEnabled: available) {
            if case .sectors(let count, let moving)? = choice.illustration {
                SetupPictogram(count: count, moving: moving)
            }
        } action: {
            actions.set(choice.value, option)
        }
    }
}

/// The pictogram of a choice `.sectors(count:moving:)`: a small board that is not interactive, `count` adjacent
/// sectors lit around the 20, and for a moving zone a second, fainter sector (mock-up `KillerOptions`).
struct SetupPictogram: View {
    let count: Int
    let moving: Bool

    var body: some View {
        DartboardView(highlights: Self.highlights(count: count, moving: moving), showsNumbers: false)
            .frame(width: Theme.Control.accessory, height: Theme.Control.accessory)
            .accessibilityHidden(true)
    }

    /// `count` sectors centred on the 20 (5, 20, 1 for three), plus the 10 at half strength when the zone moves.
    static func highlights(count: Int, moving: Bool) -> [BoardHighlight] {
        let order = BoardGeometry.standardSectorOrder
        let width = max(1, min(count, 20))
        let start = (20 - (width - 1) / 2) % 20
        var zones = (0..<width).map { BoardHighlight(zone: .sector(order[(start + $0) % 20]), role: .target) }
        if moving { zones.append(BoardHighlight(zone: .sector(10), role: .secondary)) }
        return zones
    }
}

/// Error, missing players, and "Lancer la partie".
struct SetupFooter: View {
    let state: SetupState
    let error: String?
    let start: () -> Void
    @Environment(\.appLanguage) private var language
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        let metrics = Theme.Metrics(sizeClass)
        VStack(spacing: Theme.Spacing.inline) {
            if let message {
                Text(verbatim: message)
                    .font(Theme.Typography.secondary)
                    .foregroundStyle(error == nil ? Theme.Palette.textSecondary : Theme.Palette.boardRed)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
            PrimaryButton(L10n.text("setup.start", .game), isEnabled: state.canStart, action: start)
        }
        .padding(.horizontal, metrics.screenMargin)
        .padding(.vertical, Theme.Spacing.section)
        .frame(maxWidth: sizeClass == .regular ? 640 : .infinity)
        .frame(maxWidth: .infinity)
    }

    /// Why the game cannot start yet, in words.
    private var message: String? {
        if let error { return error }
        let range = state.descriptor.players
        if state.playerCount < range.lowerBound {
            return range.lowerBound == 1
                ? L10n.string("setup.players.needMore.one", .game, language: language)
                : L10n.string("setup.players.needMore.other \(range.lowerBound)", .game, language: language)
        }
        if let issue = state.issues.first {
            return L10n.message(for: issue, language: language)
        }
        return nil
    }
}

/// Chips that wrap onto as many lines as needed.
struct SetupFlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        let rows = arrange(subviews, width: width)
        let height = rows.last.map { $0.y + $0.height } ?? 0
        let used = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? used, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for row in arrange(subviews, width: bounds.width) {
            var x = bounds.minX
            for index in row.items {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: bounds.minY + row.y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
        }
    }

    private struct Row {
        var items: [Int] = []
        var y: CGFloat = 0
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = current.items.isEmpty ? size.width : current.width + spacing + size.width
            if needed > width, !current.items.isEmpty {
                rows.append(current)
                current = Row(items: [], y: current.y + current.height + spacing)
            }
            current.width = current.items.isEmpty ? size.width : current.width + spacing + size.width
            current.height = max(current.height, size.height)
            current.items.append(index)
        }
        if !current.items.isEmpty { rows.append(current) }
        return rows
    }
}

/// Sizes read on the mock-up `KillerOptions`.
enum SetupFonts {
    static let back = Font.system(size: 20, weight: .semibold)
    static let pitch = Font.system(size: 15, weight: .regular)
    static let section = Font.system(size: 13, weight: .semibold)
    static let link = Font.system(size: 13, weight: .semibold)
    static let add = Font.system(size: 18, weight: .regular)
}
