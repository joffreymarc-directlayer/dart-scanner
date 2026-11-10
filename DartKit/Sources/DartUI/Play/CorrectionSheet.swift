import SwiftUI
import DartCore

/// Correction of one dart (mock-up `Correction`, ARCHITECTURE.md §8.6 "Écran de correction", §10.2): the hits
/// of the proposal (or the current hit and its neighbours), "Hors cible", "Retirer la fléchette", a selector on
/// the virtual board, and the evidence image when the source has one.
struct CorrectionSheet: View {
    private let game: PlayViewModel
    private let target: CorrectionTarget

    /// What the player chose and has not applied yet: a hit of the list (no position) or a point of the board.
    @State private var choice: PlayCorrectionChoice?
    @State private var evidence: CGImage?
    @State private var reticle: CGSize = .zero
    @State private var rescoring = false

    init(game: PlayViewModel, target: CorrectionTarget) {
        self.game = game
        self.target = target
    }

    var body: some View {
        Group {
            if let model {
                PlayCorrectionContent(model: model, actions: actions(for: model))
            } else {
                // The dart is gone (undone meanwhile): nothing left to correct.
                Color.clear.onAppear { close() }
            }
        }
        .background(Theme.Palette.background.ignoresSafeArea())
        .task(id: target) {
            evidence = nil
            if let id = model?.dartID {
                evidence = await game.evidenceImage(for: id)
            }
        }
    }

    // MARK: Model

    private var model: PlayCorrectionModel? {
        PlayCorrectionModel(game: game, target: target, choice: choice, evidence: evidence, reticle: reticle)
    }

    private func actions(for model: PlayCorrectionModel) -> PlayCorrectionActions {
        PlayCorrectionActions(
            close: close,
            pick: { hit in choice = PlayCorrectionChoice(hit: hit, position: nil); reticle = .zero },
            tapBoard: { tap in choice = PlayCorrectionChoice(hit: tap.hit, position: tap.position) },
            moveReticle: { offset in reticle = offset },
            dropReticle: { offset in rescore(model: model, offset: offset) },
            miss: { apply(PlayCorrectionChoice(hit: .miss, position: nil)) },
            remove: remove,
            confirm: { apply(choice ?? PlayCorrectionChoice(hit: model.detected, position: nil, keepsPosition: true)) })
    }

    // MARK: Actions

    private func close() {
        if game.correction == target { game.correction = nil }
    }

    private func remove() {
        switch target {
        case .recorded(let index): game.removeDart(at: index)
        case .pending: game.resolvePending(with: nil as Hit?)
        }
        close()
    }

    /// Applies the choice: the same hit unchanged accepts a dart "à vérifier"; another hit or a new point
    /// replaces it (§8.6, table "Corrections"); a waiting dart is answered.
    private func apply(_ choice: PlayCorrectionChoice) {
        switch target {
        case .recorded(let index):
            guard game.turnRecords.indices.contains(index) else { break }
            let record = game.turnRecords[index]
            if choice.keepsPosition || (choice.hit == record.hit && choice.position == nil) {
                // The same hit from the list: the dart is accepted as it is, its position kept.
                if record.needsReview { game.confirmDart(at: index) }
            } else {
                game.correctDart(at: index, to: choice.hit, position: choice.position)
            }
        case .pending:
            if let position = choice.position {
                game.resolvePending(with: BoardTap(hit: choice.hit, position: position))
            } else {
                game.resolvePending(with: choice.hit)
            }
        }
        close()
    }

    /// The tip moved on the evidence image: the source scores the dart again from there (§8.6). 600 px for 50 mm:
    /// a move of (dx, dy) image pixels gives the tip (x + dx / 12, y − dy / 12).
    private func rescore(model: PlayCorrectionModel, offset: CGSize) {
        guard let id = model.dartID, let image = model.evidence, let tip = model.tip, !rescoring else { return }
        let pixelsPerPoint = CGFloat(image.width) / PlayCorrectionContent.evidenceSide
        let moved = BoardPoint(x: tip.x + Double(offset.width * pixelsPerPoint) / 12,
                               y: tip.y - Double(offset.height * pixelsPerPoint) / 12)
        rescoring = true
        Task { @MainActor in
            defer { rescoring = false }
            if let proposal = await game.rescore(id, tip: moved) {
                choice = PlayCorrectionChoice(hit: proposal.hit, position: proposal.position ?? moved)
            }
        }
    }
}

/// A choice of the correction sheet, not applied yet.
struct PlayCorrectionChoice: Hashable {
    var hit: Hit
    var position: BoardPoint?
    /// "Valider" without any choice: the dart is accepted as it is.
    var keepsPosition = false
}

/// What the correction sheet shows, as values.
struct PlayCorrectionModel {
    /// Index of the dart in the turn, 0-based: "Corriger la 2e fléchette".
    var index: Int
    var isPending: Bool
    var needsReview: Bool
    /// The hit counted or proposed.
    var detected: Hit
    var choices: [Hit]
    var choice: PlayCorrectionChoice?
    /// Where the dart is, in nominal millimetres: the recorded tip, else the centre of its bed.
    var tip: BoardPoint?
    var dartID: UUID?
    var evidence: CGImage?
    var reticle: CGSize = .zero
    var boardGeometry: BoardGeometry
    var highlights: [BoardHighlight] = []

    /// Id of the marker drawn when the dart has none (a snapshot).
    static let placeholderID = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))

    /// The selected hit: the choice of the player, else the detected one.
    var selected: Hit { choice?.hit ?? detected }

    init(index: Int, isPending: Bool, needsReview: Bool, detected: Hit, choices: [Hit], choice: PlayCorrectionChoice?,
         tip: BoardPoint?, dartID: UUID?, evidence: CGImage?, reticle: CGSize = .zero, boardGeometry: BoardGeometry,
         highlights: [BoardHighlight] = []) {
        self.index = index
        self.isPending = isPending
        self.needsReview = needsReview
        self.detected = detected
        self.choices = choices
        self.choice = choice
        self.tip = tip
        self.dartID = dartID
        self.evidence = evidence
        self.reticle = reticle
        self.boardGeometry = boardGeometry
        self.highlights = highlights
    }

    /// The model of a target of a running game; nil when the target no longer exists.
    @MainActor
    init?(game: PlayViewModel, target: CorrectionTarget, choice: PlayCorrectionChoice?, evidence: CGImage?, reticle: CGSize) {
        let geometry = game.descriptor.boardGeometry
        switch target {
        case .recorded(let index):
            guard game.turnRecords.indices.contains(index) else { return nil }
            let record = game.turnRecords[index]
            self.init(index: index, isPending: false, needsReview: record.needsReview, detected: record.hit,
                      choices: PlayCorrectionChoices.around(record.hit), choice: choice,
                      tip: record.position ?? BoardGeometry.standard.centre(of: record.hit), dartID: record.id,
                      evidence: evidence, reticle: reticle, boardGeometry: geometry, highlights: game.snapshot.highlights)
        case .pending(let id):
            guard let position = game.pending.firstIndex(where: { $0.id == id }) else { return nil }
            let proposal = game.pending[position]
            let choices = proposal.choices.isEmpty ? PlayCorrectionChoices.around(proposal.hit) : proposal.choices
            self.init(index: game.turnRecords.count + position, isPending: true, needsReview: false, detected: proposal.hit,
                      choices: Array(choices.prefix(6)), choice: choice,
                      tip: proposal.position ?? BoardGeometry.standard.centre(of: proposal.hit), dartID: proposal.id,
                      evidence: evidence, reticle: reticle, boardGeometry: geometry, highlights: game.snapshot.highlights)
        }
    }
}

/// Hits offered for a dart already counted: the hit, another bed of its number, the same bed of its two
/// neighbours (clockwise first), then their singles (mock-up `Correction`: T19, S19, T7, T3, S7, S3).
enum PlayCorrectionChoices {
    static func around(_ hit: Hit) -> [Hit] {
        var list: [Hit] = [hit]
        func add(_ candidate: Hit?) {
            if let candidate, !list.contains(candidate) { list.append(candidate) }
        }
        switch hit.bed {
        case .miss:
            return []
        case .outerBull, .innerBull:
            add(.outerBull)
            add(.innerBull)
        case .single, .double, .treble:
            guard let number = hit.number else { return list }
            let neighbours = BoardGeometry.standard.neighbours(of: number)
            add(hit.bed == .single ? Hit(bed: .treble, number: number) : Hit(bed: .single, number: number))
            add(Hit(bed: hit.bed, number: neighbours.clockwise))
            add(Hit(bed: hit.bed, number: neighbours.anticlockwise))
            add(Hit(bed: .single, number: neighbours.clockwise))
            add(Hit(bed: .single, number: neighbours.anticlockwise))
            add(Hit(bed: .double, number: number))
        }
        return Array(list.prefix(6))
    }
}

struct PlayCorrectionActions {
    var close: () -> Void = {}
    var pick: (Hit) -> Void = { _ in }
    var tapBoard: (BoardTap) -> Void = { _ in }
    var moveReticle: (CGSize) -> Void = { _ in }
    var dropReticle: (CGSize) -> Void = { _ in }
    var miss: () -> Void = {}
    var remove: () -> Void = {}
    var confirm: () -> Void = {}
}

/// The correction sheet without its shell (snapshot `correction`).
struct PlayCorrectionContent: View {
    let model: PlayCorrectionModel
    var actions = PlayCorrectionActions()

    /// Side, in points, of the square in which the evidence image is drawn.
    static let evidenceSide: CGFloat = 350

    @Environment(\.appLanguage) private var language
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        let metrics = Theme.Metrics(sizeClass)
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: Theme.Spacing.inline) {
                Button(action: actions.close) {
                    Image(systemName: "xmark")
                        .font(PlayCorrectionFonts.close)
                        .frame(width: Theme.Control.touchTarget, height: Theme.Control.touchTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(DesignRowButtonStyle())
                .padding(.leading, -10)
                .accessibilityLabel(L10n.text("common.close", .common))
                L10n.text(titleKey, .game)
                    .font(PlayCorrectionFonts.title)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            HStack(spacing: Theme.Spacing.inline) {
                if model.needsReview || model.isPending {
                    L10n.text(model.isPending ? "correction.undecided" : "correction.review", .game)
                        .font(PlayCorrectionFonts.badge)
                        .foregroundStyle(Theme.Palette.accent)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 3)
                        .overlay {
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .strokeBorder(Theme.Palette.accent, lineWidth: Theme.Control.borderBadge)
                        }
                        .fixedSize()
                }
                L10n.text(model.isPending || model.needsReview ? "correction.detected \(model.detected.notation)"
                                                                 : "correction.counted \(model.detected.notation)", .game)
                    .font(PlayCorrectionFonts.status)
                    .foregroundStyle(Theme.Palette.textSecondary)
            }
            magnifier
            L10n.text(model.evidence == nil ? "correction.hint.board" : "correction.hint.image", .game)
                .font(Theme.Typography.secondary)
                .foregroundStyle(Theme.Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                ForEach(model.choices, id: \.self) { hit in
                    choiceButton(hit)
                }
            }
            HStack(spacing: 8) {
                secondary(L10n.text("correction.miss", .game), action: actions.miss)
                secondary(L10n.text("correction.remove", .game), action: actions.remove)
            }
            Spacer(minLength: 0)
            PrimaryButton(L10n.text("correction.confirm \(model.selected.notation)", .game), action: actions.confirm)
        }
        .padding(.horizontal, metrics.screenMargin)
        .padding(.vertical, Theme.Spacing.section)
        .frame(maxWidth: sizeClass == .regular ? 560 : .infinity, maxHeight: .infinity, alignment: .top)
        .frame(maxWidth: .infinity)
    }

    private var titleKey: LocalizedStringKey {
        switch model.index {
        case 0: return "correction.title.1"
        case 1: return "correction.title.2"
        default: return "correction.title.3"
        }
    }

    /// The evidence image with its reticle, or a magnified virtual board centred on the dart: a tap gives the
    /// hit and the position together (§8.6).
    private var magnifier: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
        return GeometryReader { proxy in
            let size = proxy.size
            ZStack(alignment: .topLeading) {
                Theme.Palette.boardSurround
                if let evidence = model.evidence {
                    let side = max(size.width, size.height)
                    Image(decorative: evidence, scale: 1)
                        .resizable()
                        .interpolation(.medium)
                        .frame(width: side, height: side)
                        .position(x: size.width / 2, y: size.height / 2)
                    PlayCorrectionReticle()
                        .position(x: size.width / 2 + model.reticle.width, y: size.height / 2 + model.reticle.height)
                        .gesture(DragGesture(minimumDistance: 1)
                            .onChanged { actions.moveReticle($0.translation) }
                            .onEnded { actions.dropReticle($0.translation) })
                } else {
                    magnifiedBoard(in: size)
                }
            }
            .frame(width: size.width, height: size.height)
        }
        .frame(height: 280)
        .clipShape(shape)
        .overlay { shape.strokeBorder(Theme.Palette.line, lineWidth: Theme.Control.border) }
    }

    /// The board drawn 900 pt wide (2 pt per millimetre), the detected dart in the middle of the frame; the
    /// marker and the reticle follow the point the player touched.
    private func magnifiedBoard(in size: CGSize) -> some View {
        let boardSide: CGFloat = 900
        let board = CGSize(width: boardSide, height: boardSide)
        let tip = model.tip ?? .centre
        let chosen = model.choice?.position ?? tip
        let location = DartboardView.location(of: tip, in: board, geometry: model.boardGeometry)
        let chosenLocation = DartboardView.location(of: chosen, in: board, geometry: model.boardGeometry)
        let marker = BoardDartMarker(id: model.dartID ?? PlayCorrectionModel.placeholderID, position: chosen, label: nil,
                                     style: model.needsReview || model.isPending ? .review : .neutral)
        return ZStack {
            DartboardView(highlights: [], darts: [marker], geometry: model.boardGeometry, dimsUnhighlighted: false,
                          showsNumbers: false, onTap: actions.tapBoard)
                .frame(width: boardSide, height: boardSide)
                .position(x: size.width / 2 + boardSide / 2 - location.x, y: size.height / 2 + boardSide / 2 - location.y)
            PlayCorrectionReticle()
                .position(x: size.width / 2 + chosenLocation.x - location.x, y: size.height / 2 + chosenLocation.y - location.y)
                .allowsHitTesting(false)
        }
        .frame(width: size.width, height: size.height)
    }

    private func choiceButton(_ hit: Hit) -> some View {
        let isSelected = hit == model.selected
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
        return Button { actions.pick(hit) } label: {
            Text(verbatim: hit.notation)
                .font(isSelected ? PlayCorrectionFonts.choiceSelected : PlayCorrectionFonts.choice)
                .foregroundStyle(isSelected ? Theme.Palette.background : Theme.Palette.textPrimary)
                .frame(maxWidth: .infinity, minHeight: Theme.Control.touchTarget)
                .background(isSelected ? Theme.Palette.textPrimary : Theme.Palette.surface, in: shape)
                .overlay { if !isSelected { shape.strokeBorder(Theme.Palette.line, lineWidth: Theme.Control.border) } }
                .contentShape(shape)
        }
        .buttonStyle(DesignRowButtonStyle())
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private func secondary(_ title: Text, action: @escaping () -> Void) -> some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
        return Button(action: action) {
            title
                .font(PlayCorrectionFonts.secondary)
                .foregroundStyle(Theme.Palette.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, minHeight: 48)
                .overlay { shape.strokeBorder(Theme.Palette.line, lineWidth: Theme.Control.border) }
                .contentShape(shape)
        }
        .buttonStyle(DesignRowButtonStyle())
    }
}

/// Cross-hair and amber ring of the correction sheet.
private struct PlayCorrectionReticle: View {
    var body: some View {
        ZStack {
            Rectangle().fill(Theme.Palette.textPrimary.opacity(0.7)).frame(width: 2, height: 88)
            Rectangle().fill(Theme.Palette.textPrimary.opacity(0.7)).frame(width: 88, height: 2)
            Circle()
                .fill(Theme.Palette.background.opacity(0.25))
                .overlay { Circle().strokeBorder(Theme.Palette.accent, lineWidth: 3) }
                .frame(width: 36, height: 36)
            Circle().fill(Theme.Palette.accent).frame(width: 8, height: 8)
        }
        .frame(width: 88, height: 88)
        .contentShape(Rectangle())
    }
}

/// Sizes read on the mock-up `Correction`.
enum PlayCorrectionFonts {
    static let close = Font.system(size: 20, weight: .semibold)
    static let title = Font.system(size: 22, weight: .heavy)
    static let badge = Font.system(size: 13, weight: .bold)
    static let status = Font.system(size: 14, weight: .regular)
    static let choice = Font.system(size: 16, weight: .semibold)
    static let choiceSelected = Font.system(size: 16, weight: .heavy)
    static let secondary = Font.system(size: 15, weight: .semibold)
}
