import SwiftUI
import DartCore

extension SnapshotCatalog {
    /// Lot U1: "board-plain", "board-zones", "board-discs", "components".
    /// Pure contents fed with fixture data: no model, no navigation, no scrolling (ARCHITECTURE.md §8.11).
    @MainActor static var kernelScreens: [SnapshotScreen] {
        [
            SnapshotScreen(id: "board-plain") { _ in AnyView(KernelBoardPlainContent()) },
            SnapshotScreen(id: "board-zones") { _ in AnyView(KernelBoardZonesContent()) },
            SnapshotScreen(id: "board-discs") { _ in AnyView(KernelBoardDiscsContent()) },
            SnapshotScreen(id: "components") { _ in AnyView(KernelComponentsContent()) },
        ]
    }
}

// MARK: - Fixtures

/// Data of the kernel snapshots. The Killer zones and the two darts are those of the mock-up `PlayKiller`;
/// the discs are the five Radar targets of the vector RAD-1 (GAMES.md §15.9, seed 1).
enum KernelSnapshotFixtures {
    /// Killer at four: Léa (player 0) is the Killer and throws, so her zone is her `own` and the three others
    /// are targets in the colour of their owner.
    static let killerZones: [BoardHighlight] =
        [17, 3, 19].map { BoardHighlight(zone: .sector($0), role: .own, owner: 0) }
        + [20, 1, 18].map { BoardHighlight(zone: .sector($0), role: .target, owner: 1) }
        + [6, 10, 15].map { BoardHighlight(zone: .sector($0), role: .target, owner: 2) }
        + [8, 11, 14].map { BoardHighlight(zone: .sector($0), role: .target, owner: 3) }

    /// S20 and T6, at their nominal positions.
    static let killerDarts: [BoardDartMarker] = [
        BoardDartMarker(id: uuid(1), position: BoardPoint(radius: 134.5, clockwiseDegrees: 0), label: nil, style: .neutral),
        BoardDartMarker(id: uuid(2), position: BoardPoint(radius: 103, clockwiseDegrees: 90), label: nil, style: .neutral),
    ]

    /// One zone of each role and of each kind, with the labels, pips and markers a game can ask for.
    static let everyRole: [BoardHighlight] = [
        BoardHighlight(zone: .double(12), role: .target),
        BoardHighlight(zone: .treble(4), role: .target, label: "2"),
        BoardHighlight(zone: .single(4), role: .secondary, label: "3"),
        BoardHighlight(zone: .sector(20), role: .secondary),
        BoardHighlight(zone: .sector(6), role: .opponent, owner: 1),
        BoardHighlight(zone: .sector(10), role: .opponent, owner: 1),
        BoardHighlight(zone: .sector(3), role: .avoid),
        BoardHighlight(zone: .sector(19), role: .avoid),
        BoardHighlight(zone: .sector(16), role: .target, owner: 2, label: "+3", strength: 2, marker: .home),
        BoardHighlight(zone: .sector(11), role: .inactive),
        BoardHighlight(zone: .sector(14), role: .own, owner: 3, marker: .heal),
        BoardHighlight(zone: .bull, role: .target, marker: .crown),
    ]

    /// A dart of each style, two of them labelled.
    static let everyDart: [BoardDartMarker] = [
        BoardDartMarker(id: uuid(3), position: BoardPoint(radius: 60, clockwiseDegrees: 144), label: "S2", style: .neutral),
        BoardDartMarker(id: uuid(4), position: BoardPoint(radius: 103, clockwiseDegrees: 198), label: "T19", style: .review),
        BoardDartMarker(id: uuid(5), position: BoardPoint(radius: 134.5, clockwiseDegrees: 306), label: nil, style: .player(1)),
    ]

    /// (x, y, radius) in nominal millimetres, label, hit points left.
    static let radarDiscs: [BoardHighlight] = [
        BoardHighlight(zone: .disc(x: -80, y: 95, radius: 40), role: .target, label: "+10", strength: 3),
        BoardHighlight(zone: .disc(x: 70, y: -65, radius: 40), role: .target, label: "+10", strength: 3),
        BoardHighlight(zone: .disc(x: 110, y: 65, radius: 28), role: .target, label: "+20", strength: 2),
        BoardHighlight(zone: .disc(x: 25, y: 15, radius: 28), role: .target, label: "+20", strength: 2),
        BoardHighlight(zone: .disc(x: 140, y: 0, radius: 16), role: .target, label: "+50", strength: 1),
    ]

    static let players = ["Léa", "Tom", "Inès", "Marc"]

    private static func uuid(_ n: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", n)) ?? UUID()
    }
}

// MARK: - Contents

/// Title and caption above a kernel snapshot.
private struct KernelHeading: View {
    let title: LocalizedText
    var caption: LocalizedText?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lines) {
            LocalizedTextView(title)
                .font(Theme.Typography.gameTitle)
                .foregroundStyle(Theme.Palette.textPrimary)
            if let caption {
                LocalizedTextView(caption)
                    .font(Theme.Typography.secondary)
                    .foregroundStyle(Theme.Palette.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Common frame of the kernel snapshots: screen margins, blocks from the top.
private struct KernelPage<Content: View>: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.section) {
            content
        }
        .padding(.horizontal, Theme.Metrics(sizeClass).screenMargin)
        .padding(.vertical, Theme.Spacing.section)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

/// "board-plain": the bare board with its thick rings, then the same board at regulation proportions and at
/// the size of an option pictogram.
private struct KernelBoardPlainContent: View {
    var body: some View {
        KernelPage {
            KernelHeading(title: LocalizedText(fr: "Cible", en: "Board"),
                          caption: LocalizedText(fr: "Anneaux épaissis pour la lisibilité", en: "Rings thickened for legibility"))
            DartboardView()
            HStack(alignment: .top, spacing: Theme.Spacing.section) {
                VStack(spacing: Theme.Spacing.inline) {
                    DartboardView(geometry: .standard)
                    LocalizedTextView(LocalizedText(fr: "Proportions réglementaires", en: "Regulation proportions"))
                }
                VStack(spacing: Theme.Spacing.inline) {
                    DartboardView(darts: KernelSnapshotFixtures.killerDarts, showsNumbers: false)
                    LocalizedTextView(LocalizedText(fr: "Sans numéros, deux fléchettes", en: "No numbers, two darts"))
                }
            }
            .font(Theme.Typography.secondary)
            .foregroundStyle(Theme.Palette.textSecondary)
            HStack(spacing: Theme.Spacing.row) {
                // Option pictograms (setup screen): a small board that is not interactive.
                ForEach([1, 2, 3], id: \.self) { count in
                    DartboardView(highlights: [20, 1, 18].prefix(count).map { BoardHighlight(zone: .sector($0), role: .target) },
                                  showsNumbers: false)
                        .frame(width: Theme.Control.accessory, height: Theme.Control.accessory)
                }
                LocalizedTextView(LocalizedText(fr: "Pictogrammes d'option", en: "Option pictograms"))
                    .font(Theme.Typography.secondary)
                    .foregroundStyle(Theme.Palette.textSecondary)
            }
        }
    }
}

/// "board-zones": Killer zones at four players, then one zone of every role.
private struct KernelBoardZonesContent: View {
    var body: some View {
        KernelPage {
            KernelHeading(title: LocalizedText(fr: "Zones du Killer", en: "Killer zones"),
                          caption: LocalizedText(fr: "Léa est Killer : sa zone en contour, les autres à viser",
                                                 en: "Léa is the Killer: her zone outlined, the others to aim at"))
            DartboardView(highlights: KernelSnapshotFixtures.killerZones, darts: KernelSnapshotFixtures.killerDarts)
            KernelHeading(title: LocalizedText(fr: "Tous les rôles", en: "Every role"),
                          caption: LocalizedText(fr: "À viser, secondaire, adverse, à éviter, inactive, à soi",
                                                 en: "Target, secondary, opponent, avoid, inactive, own"))
            DartboardView(highlights: KernelSnapshotFixtures.everyRole, darts: KernelSnapshotFixtures.everyDart)
        }
    }
}

/// "board-discs": the five Radar targets of RAD-1 on a board at regulation proportions.
private struct KernelBoardDiscsContent: View {
    var body: some View {
        KernelPage {
            KernelHeading(title: LocalizedText(fr: "Disques de Radar", en: "Radar discs"),
                          caption: LocalizedText(fr: "Cible aux proportions réglementaires, cinq cibles",
                                                 en: "Board at regulation proportions, five targets"))
            DartboardView(highlights: KernelSnapshotFixtures.radarDiscs, geometry: .standard)
            KernelHeading(title: LocalizedText(fr: "Sans assombrissement", en: "Without dimming"),
                          caption: LocalizedText(fr: "Les mêmes disques, cible laissée claire",
                                                 en: "The same discs, board left bright"))
            DartboardView(highlights: KernelSnapshotFixtures.radarDiscs, geometry: .standard, dimsUnhighlighted: false)
        }
    }
}

/// "components": every component of `Components.swift`, in its states.
private struct KernelComponentsContent: View {
    @Environment(\.appLanguage) private var language

    private func text(_ fr: String, _ en: String) -> Text {
        Text(verbatim: LocalizedText(fr: fr, en: en)[language])
    }

    var body: some View {
        KernelPage {
            HStack(spacing: Theme.Spacing.row) {
                PrimaryButton(text("Lancer la partie", "Start game")) {}
                SecondaryButton(text("Changer de jeu", "Change game")) {}
            }
            HStack(spacing: Theme.Spacing.row) {
                PrimaryButton(text("Scanner", "Scan"), systemImage: "camera", isEnabled: false) {}
                SecondaryButton(text("Photo", "Photo"), systemImage: "camera") {}
            }
            HStack(spacing: Theme.Spacing.inline) {
                BadgeView(Text(verbatim: "Killer"), color: Theme.Palette.accent, filled: true)
                BadgeView(text("À vérifier", "To check"), color: Theme.Palette.accent)
                BadgeView(Text(verbatim: "Killer"), color: Theme.Palette.surfaceRaised, filled: true)
                BadgeView(text("Scan en direct", "Live scan"), color: Theme.Palette.info)
                Spacer(minLength: 0)
                PlayerChip(name: KernelSnapshotFixtures.players[3], index: 3, showsName: false)
            }
            HStack(spacing: Theme.Spacing.row) {
                ForEach(0..<3, id: \.self) { index in
                    PlayerChip(name: KernelSnapshotFixtures.players[index], index: index)
                }
            }
            Card {
                VStack(spacing: 0) {
                    ToggleRow(text("Annonce vocale des scores", "Spoken score caller"),
                              subtitle: text("« Triple vingt », « Cent quatre-vingts »", "\"Treble twenty\", \"One hundred and eighty\""),
                              isOn: .constant(true))
                    separator
                    ToggleRow(text("Vibrations", "Haptics"), isOn: .constant(false))
                    separator
                    HStack(spacing: Theme.Spacing.row) {
                        text("Voix", "Voice").font(Theme.Typography.body)
                        Spacer(minLength: 0)
                        SegmentedChoice(options: [(AppLanguage.fr, Text(verbatim: "Français")), (AppLanguage.en, Text(verbatim: "English"))],
                                        selection: .constant(language))
                            .frame(width: 188)
                    }
                    .frame(minHeight: Theme.Control.rowHeight)
                    separator
                    HStack(spacing: Theme.Spacing.row) {
                        text("Volume", "Volume").font(Theme.Typography.body)
                        LevelSlider(value: .constant(0.7))
                    }
                    .frame(minHeight: Theme.Control.rowHeight)
                }
                .padding(.horizontal, Theme.Spacing.cardInset)
            }
            StepperRow(text("Vies", "Lives"), value: .constant(3), range: 1...9)
            StepperRow(text("Limite de manches", "Round limit"), value: .constant(nil), range: 5...30,
                       nullLabel: text("Sans limite", "No limit"))
            RadioRow(title: text("Intermédiaire", "Intermediate"), detail: text("2 cases adjacentes", "2 adjacent sectors"),
                     isSelected: true) {
                DartboardView(highlights: [20, 1].map { BoardHighlight(zone: .sector($0), role: .target) }, showsNumbers: false)
                    .frame(width: Theme.Control.accessory, height: Theme.Control.accessory)
            } action: {}
            RadioRow(title: text("Facile", "Easy"), detail: text("3 cases adjacentes", "3 adjacent sectors"),
                     note: text("6 joueurs maximum en Facile", "6 players at most in Easy"), isSelected: false, isEnabled: false) {
                DartboardView(highlights: [20, 1, 18].map { BoardHighlight(zone: .sector($0), role: .target) }, showsNumbers: false)
                    .frame(width: Theme.Control.accessory, height: Theme.Control.accessory)
            } action: {}
            ScrimBubble {
                text("Ne bougez plus…", "Hold still…")
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Theme.Spacing.inline)
            .background(Theme.Palette.lineStrong, in: RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous))
        }
    }

    private var separator: some View {
        Rectangle()
            .fill(Theme.Palette.line)
            .frame(height: Theme.Control.border)
    }
}
