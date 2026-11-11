import Foundation
import CoreGraphics
import Testing
import DartCore
import DartGames
import DartAudio
import DartTestSupport
@testable import DartUI

/// Review of lot U2: `PlayViewModel` and the correction sheet against ARCHITECTURE.md §8.6, on the cases the lot's
/// own tests leave out.
@MainActor
@Suite struct GameFlowReviewPlayViewModelTests {
    // MARK: The short-turn question (§8.6, "Fin du tour")

    @Test func shortTurnQuestion_isWithdrawn_whenThePlayerThrowsAgain() throws {
        let rig = try GameFlowRig(.highScore, players: 2)
        rig.game.receive(gameFlowManual("T20", id: 1))
        rig.game.requestEndTurn()
        #expect(rig.game.prompt == .confirmShortTurn)
        // The player throws the two other darts instead of answering: the turn is no longer short, and
        // "Volée incomplète : passer au joueur suivant ?" must not stay on screen.
        rig.game.receive(gameFlowManual("T20", id: 2))
        rig.game.receive(gameFlowManual("T20", id: 3))
        #expect(rig.game.match.phase == .turnComplete)
        #expect(rig.game.prompt != .confirmShortTurn, "stale question: \(String(describing: rig.game.prompt))")
        // The button still ends the turn, without a question.
        rig.game.requestEndTurn()
        #expect(rig.game.snapshot.currentPlayer == 1 && rig.game.prompt == nil)
    }

    @Test func shortTurnQuestion_isWithdrawn_byADartThatWaitsForAnAnswer() throws {
        let rig = try GameFlowRig(.highScore, players: 2)
        rig.game.receive(gameFlowManual("T20", id: 1))
        rig.game.requestEndTurn()
        rig.game.receive(gameFlowProposal("S5", id: 2, certainty: .undecided))
        // The question could not be answered any more (the button is off while a dart waits).
        #expect(!rig.game.canEndTurn && rig.game.prompt != .confirmShortTurn)
    }

    // MARK: Correction sheet: the tip under the reticle (§8.6, "Écran de correction")

    @Test func reticle_isConvertedWithTheSideTheImageIsDrawnAt() {
        let tip = BoardPoint(x: 10, y: 100)
        // The 600 px image (50 mm) drawn 496 pt wide, as on an iPad: half the drawn width is half the image,
        // 300 px, 25 mm.
        let moved = PlayCorrectionModel.movedTip(tip, by: CGSize(width: 248, height: -124), imageWidth: 600, drawnSide: 496)
        #expect(abs(moved.x - 35) < 1e-6 && abs(moved.y - 112.5) < 1e-6, "\(moved)")
        // The same move on a phone, where the image is drawn 353 pt wide.
        let phone = PlayCorrectionModel.movedTip(tip, by: CGSize(width: 176.5, height: 0), imageWidth: 600, drawnSide: 353)
        #expect(abs(phone.x - 35) < 1e-6 && phone.y == 100, "\(phone)")
        // The content draws the image over the width of its frame, and passes that side with the move.
        #expect(PlayCorrectionContent.evidenceDrawnSide(in: CGSize(width: 496, height: 280)) == 496)
        #expect(PlayCorrectionContent.evidenceDrawnSide(in: CGSize(width: 353, height: 280)) == 353)
    }

    @Test func reticle_aSecondDrag_goesOnFromWhereTheFirstLeftIt() {
        let first = PlayCorrectionModel.reticle(.zero, moved: CGSize(width: 30, height: -10))
        let second = PlayCorrectionModel.reticle(first, moved: CGSize(width: 5, height: 4))
        #expect(second == CGSize(width: 35, height: -6))
    }

    @Test func magnifiedBoard_aTapInTheMiddle_isTheDartItIsCentredOn() {
        let side: CGFloat = 900
        for hit in [Hit.treble(19), .double(6), .single(3), .outerBull] {
            guard let tip = BoardGeometry.standard.centre(of: hit) else { continue }
            for geometry in [BoardGeometry.display, .standard] {
                let location = DartboardView.location(of: tip, in: CGSize(width: side, height: side), geometry: geometry)
                let frame = CGSize(width: 353, height: 280)
                let tap = PlayCorrectionModel.boardTap(at: CGPoint(x: frame.width / 2, y: frame.height / 2), frame: frame,
                                                       tipLocation: location, boardSide: side, geometry: geometry)
                #expect(tap.hit == hit && abs(tap.position.x - tip.x) < 1e-6 && abs(tap.position.y - tip.y) < 1e-6)
                // 2 pt per millimetre: 20 pt to the right is 10 mm to the right.
                let right = PlayCorrectionModel.boardTap(at: CGPoint(x: frame.width / 2 + 20, y: frame.height / 2), frame: frame,
                                                         tipLocation: location, boardSide: side, geometry: .standard)
                if geometry == .standard {
                    #expect(abs(right.position.x - (tip.x + 20 * 451 / 900)) < 1e-6 && abs(right.position.y - tip.y) < 1e-6)
                }
            }
        }
    }
}
