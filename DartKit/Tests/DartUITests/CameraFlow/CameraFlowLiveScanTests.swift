import Foundation
import Testing
import DartCore
import DartVision
@testable import DartUI

/// The live scan and its thumbnail as a running game shows them (ARCHITECTURE.md §8.6, "Accès aux écrans caméra";
/// mock-ups `LiveScan`, `PadPlayKiller`): the darts of the turn drawn on the camera image through the installed
/// calibration, the slots, the dart to check, the state of the scan.
@MainActor
@Suite struct CameraFlowLiveScanTests {
    private typealias Support = CameraFlowSupport

    @Test func theDartsOfTheTurn_areDrawnWhereTheCalibrationSeesThem() async throws {
        let service = FakeScanService(still: Support.emptyBoard)
        let camera = Support.camera(service)
        let calibration = Support.syntheticCamera.calibration(grade: .good)
        await camera.adopt(calibration, lightingCheckPassed: false)
        let source = CameraInputSource(camera: camera, mode: .live)
        let game = try Support.game(source: source)
        game.handle(.statusChanged(.live))
        let sure = Support.observation(Support.id(1), .treble(20), tip: BoardPoint(x: 0, y: 103), confidence: 0.97)
        let doubtful = Support.observation(Support.id(2), .single(19), tip: Support.tips[1], confidence: 0.7)
        let unknown = Support.observation(Support.id(3), .single(7), tip: Support.tips[2], confidence: 0.2)
        for observation in [sure, doubtful, unknown] {
            game.handle(.dart(DartProposal(observation: observation, thresholds: .standard)))
        }
        #expect(game.turnRecords.count == 2 && game.pending.count == 1)
        let model = ScanLiveContentModel(game: game, camera: camera)
        #expect(model.marks.map(\.label) == ["T20", "S19 ?", "S7 ?"] && model.marks.map(\.needsReview) == [false, true, true])
        for (mark, observation) in zip(model.marks, [sure, doubtful, unknown]) {
            let expected = Support.project(observation.tip)
            #expect(hypot(mark.point.x - expected.x, mark.point.y - expected.y) < 0.01)
        }
        #expect(model.slots.map(\.kind) == [.counted(review: false), .counted(review: true), .pending])
        #expect(model.review?.label == "S19" && model.review?.target == .recorded(index: 1))
        #expect(model.imageSize == calibration.imageSize && model.status == .live && model.dartsInTurn == 3)
        #expect(model.playerName == "J1" && model.subtitle.fr.isEmpty == false)
        // Every slot is said in both languages.
        let empty = try Support.game(source: source)
        let start = ScanLiveContentModel(game: empty, camera: camera)
        #expect(start.slots.map(\.kind) == [.empty, .empty, .empty] && start.review == nil && start.marks.isEmpty)
        #expect(start.slots.map(\.text.fr) == ["1re fléchette", "2e fléchette", "3e fléchette"])
        #expect(start.slots.map(\.text.en) == ["1st dart", "2nd dart", "3rd dart"])
    }

    @Test func withoutACalibration_nothingIsDrawnOnTheImage() throws {
        let camera = Support.camera(FakeScanService())
        let game = try Support.game(source: CameraInputSource(camera: camera, mode: .live))
        game.handle(.dart(DartProposal(observation: Support.observation(Support.id(1), .treble(20)), thresholds: .standard)))
        let model = ScanLiveContentModel(game: game, camera: camera)
        #expect(model.marks.isEmpty && model.slots.first?.kind == .counted(review: false))
    }

    @Test func statusLine_followsTheSourceAndTheTurn() throws {
        let camera = Support.camera(FakeScanService())
        let game = try Support.game(source: CameraInputSource(camera: camera, mode: .live))
        func status(_ input: InputStatus, issue: CameraIssue? = nil) -> ScanLiveContentModel {
            game.handle(.statusChanged(input))
            var model = ScanLiveContentModel(game: game, camera: camera)
            model.issue = issue
            return model
        }
        #expect(ScanText.dot(status(.live)) == Theme.Palette.info)
        #expect(ScanText.dot(status(.needsEmptyBoard)) == Theme.Palette.accent)
        #expect(ScanText.dot(status(.needsCalibration)) == Theme.Palette.boardRed)
        #expect(ScanText.dot(status(.live, issue: .notFullScreen)) == Theme.Palette.boardRed)
        #expect(ScanText.asks(.possibleMiss) && ScanText.asks(.dartFellOut(index: 0)) && !ScanText.asks(.boardCleared))
        #expect(ScanText.prompt(.advisory(LocalizedText(fr: "Lumière", en: "Light")), language: .en) == "Light")
        #expect(ScanText.prompt(.possibleMiss, language: .fr) == "Rebond ? Manqué")
    }
}
