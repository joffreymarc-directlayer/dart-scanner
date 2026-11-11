import SwiftUI
import DartCore
import DartVision

/// Live scan (ARCHITECTURE.md §8.6, "Accès aux écrans caméra"; mock-up `LiveScan`): the camera over the whole
/// screen, the darts of the turn on the image, the state of the scan, and the actions of the turn. Opened from
/// the scan pill or from "Agrandir" of the thumbnail when the game has a source.
struct LiveScanView: View {
    private let game: PlayViewModel
    private let camera: CameraModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appLanguage) private var language

    init(game: PlayViewModel, camera: CameraModel) {
        self.game = game
        self.camera = camera
    }

    var body: some View {
        @Bindable var game = game
        ScanLiveContent(model: ScanLiveContentModel(game: game, camera: camera), actions: actions)
            .background(Theme.Palette.background.ignoresSafeArea())
            // The play screen sits under this cover and cannot present its own sheet: the correction of a dart
            // seen here is presented here.
            .sheet(item: $game.correction) { target in
                CorrectionSheet(game: game, target: target)
                    .appLanguage(language)
                    .preferredColorScheme(.dark)
            }
            .task { await camera.activate() }
            .keepsScreenAwake(true)
    }

    private var actions: ScanLiveActions {
        let game = game
        return ScanLiveActions(
            close: { dismiss() },
            review: { game.correction = $0 },
            miss: { game.addMiss() },
            nextPlayer: { game.requestEndTurn() },
            confirmBoardEmpty: { game.confirmBoardEmpty() },
            acceptPrompt: {
                switch game.prompt {
                case .possibleMiss?: game.addMiss()
                case .dartFellOut(let index)?: game.correctDart(at: index, to: .miss)
                case .confirmShortTurn?: game.endTurn()
                default: game.prompt = nil
                }
            },
            dismissPrompt: { game.prompt = nil })
    }
}

extension ScanLiveContentModel {
    /// The live scan of a running game: the darts of the turn placed on the camera image through the installed
    /// calibration (`imagePoint(for:)`, the exact inverse of the scoring), the current player and the slots.
    @MainActor
    init(game: PlayViewModel, camera: CameraModel) {
        let snapshot = game.snapshot
        let player = snapshot.currentPlayer
        let players = game.match.players
        let row = snapshot.players.first { $0.player == player }
        let records = game.turnRecords
        var marks: [CameraTipMark] = []
        var slots: [ScanSlot] = []
        var review: (label: String, target: CorrectionTarget)?
        for (index, slot) in snapshot.turn.darts.enumerated() {
            let record = records.indices.contains(index) ? records[index] : nil
            let needsReview = record?.needsReview ?? false
            let label = slot.hit.notation
            slots.append(ScanSlot(text: LocalizedText(verbatim: label),
                                  caption: needsReview ? CameraText.localized("scan.slot.review") : slot.caption?.text,
                                  kind: .counted(review: needsReview)))
            if needsReview, review == nil { review = (label, .recorded(index: index)) }
            if let record, let position = record.position, let calibration = camera.calibration {
                marks.append(CameraTipMark(id: record.id, point: calibration.imagePoint(for: position),
                                           label: needsReview ? "\(label) ?" : label, needsReview: needsReview))
            }
        }
        for proposal in game.pending {
            let label = proposal.hit.notation
            slots.append(ScanSlot(text: LocalizedText(verbatim: "\(label) ?"), caption: CameraText.localized("scan.slot.pending"),
                                  kind: .pending))
            if review == nil { review = (label, .pending(id: proposal.id)) }
            if let position = proposal.position, let calibration = camera.calibration {
                marks.append(CameraTipMark(id: proposal.id, point: calibration.imagePoint(for: position),
                                           label: "\(label) ?", needsReview: true))
            }
        }
        let capacity = max(snapshot.turn.capacity, 3)
        while slots.count < capacity {
            slots.append(ScanSlot(text: ScanText.emptySlot(slots.count), caption: nil, kind: .empty))
        }
        self.init(preview: camera.service.preview,
                  imageSize: camera.service.frameInfo?.size ?? camera.calibration?.imageSize,
                  rotationDegrees: camera.service.frameInfo?.rotationDegrees ?? 0,
                  marks: marks,
                  status: game.inputStatus,
                  issue: camera.service.issue,
                  phase: snapshot.phase,
                  playerName: players.indices.contains(player) ? players[player].name : "?",
                  playerIndex: player,
                  subtitle: ScanText.subtitle(snapshot),
                  score: row?.primary,
                  slots: slots,
                  review: review,
                  canEndTurn: game.canEndTurn,
                  prompt: game.prompt)
    }
}

extension ScanText {
    /// "1re fléchette", "2e fléchette", "3e fléchette": the empty slots.
    static func emptySlot(_ index: Int) -> LocalizedText {
        switch index {
        case 0: return CameraText.localized("scan.slot.empty.1")
        case 1: return CameraText.localized("scan.slot.empty.2")
        default: return CameraText.localized("scan.slot.empty.3")
        }
    }

    /// "Killer · Facile": the game and its variant.
    static func subtitle(_ snapshot: GameSnapshot) -> LocalizedText {
        let parts = [snapshot.title, snapshot.variant].compactMap { $0 }
        return LocalizedText(fr: parts.map(\.fr).joined(separator: " · "), en: parts.map(\.en).joined(separator: " · "))
    }
}
