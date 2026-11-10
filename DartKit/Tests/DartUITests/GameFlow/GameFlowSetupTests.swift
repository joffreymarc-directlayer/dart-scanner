import Foundation
import CoreGraphics
import Testing
import DartCore
import DartGames
import DartTestSupport
@testable import DartUI

/// The setup screen driven by the descriptor (§8.5), and the small pure rules of the other screens.
@MainActor
@Suite struct GameFlowSetupTests {
    private func descriptor(_ id: GameID) throws -> GameDescriptor {
        try #require(GameRegistry.standard.definition(for: id)?.descriptor)
    }

    @Test func killerEasy_atSevenPlayers_isGreyed_andMediumIsChosen() throws {
        let killer = try descriptor(.killer)
        let roster = testPlayers(8)
        var state = SetupState(descriptor: killer, roster: roster,
                               memory: SetupMemory(playerIDs: roster.prefix(6).map(\.id), options: ["level": "easy"]))
        let level = try #require(killer.option("level"))
        guard case .choice(let choices) = level.kind else { Issue.record("level is a choice"); return }
        let easy = try #require(choices.first { $0.value == "easy" })
        #expect(state.value(of: level) == "easy" && state.isAvailable(easy) && state.canStart)
        state.add(roster[6])
        #expect(state.playerCount == 7 && state.value(of: level) == "medium")
        #expect(!state.isAvailable(easy) && easy.unavailableNote?.fr == "6 joueurs maximum en Facile")
        #expect(state.canStart && state.issues.isEmpty)
        // Back to six: "Facile" is offered again, the choice made is kept.
        state.remove(roster[6])
        #expect(state.isAvailable(easy) && state.value(of: level) == "medium")
        // Eight is the maximum of the game: no ninth player.
        state.add(roster[6])
        state.add(roster[7])
        #expect(!state.canAddPlayer && state.playerCount == 8)
        state.add(Player(id: gameFlowID(9), name: "J9"))
        #expect(state.playerCount == 8)
    }

    @Test func setupState_withoutMemory_takesTheFirstPlayersAndTheDefaults() throws {
        let x01 = try descriptor(.x01)
        let state = SetupState(descriptor: x01, roster: testPlayers(5), memory: nil)
        #expect(state.players == Array(testPlayers(5).prefix(2)) && state.options == x01.defaultOptions)
        #expect(state.canStart)
        // A one-player game is offered with one player only when the roster has only one.
        let solo = SetupState(descriptor: x01, roster: testPlayers(1), memory: nil)
        #expect(solo.playerCount == 1 && solo.canStart)
        let empty = SetupState(descriptor: x01, roster: [], memory: nil)
        #expect(empty.playerCount == 0 && !empty.canStart)
    }

    @Test func setupState_memory_dropsWhatTheGameNoLongerAccepts() throws {
        let killer = try descriptor(.killer)
        let roster = testPlayers(3)
        let memory = SetupMemory(playerIDs: [roster[2].id, gameFlowID(77), roster[0].id],
                                 options: ["level": "legendary", "lives": 4, "colour": "red", "maxRounds": .null])
        let state = SetupState(descriptor: killer, roster: roster, memory: memory)
        // A player deleted since is dropped; the order of the memory is kept.
        #expect(state.players == [roster[2], roster[0]])
        #expect(state.options.string("level") == "easy" && state.options.int("lives") == 4)
        #expect(state.options["maxRounds"] == .null && state.options["colour"] == nil)
        #expect(state.issues.isEmpty)
    }

    @Test func everyGameOfTheRegistry_hasASetupThatCanStart() throws {
        for descriptor in GameRegistry.standard.descriptors {
            let state = SetupState(descriptor: descriptor, roster: testPlayers(8), memory: nil)
            #expect(state.canStart, "\(descriptor.id)")
            #expect(state.mainOptions.count + state.advancedOptions.count == descriptor.options.count)
            let match = try GameRegistry.standard.makeMatch(GameConfiguration(gameID: descriptor.id, options: state.options,
                                                                              players: state.players, seed: 1))
            #expect(match.players.count == state.playerCount)
        }
    }

    @Test func controls_followTheTableOfTheDocument() throws {
        let x01 = try descriptor(.x01), killer = try descriptor(.killer), halveIt = try descriptor(.halveIt)
        func control(_ descriptor: GameDescriptor, _ key: String) throws -> SetupControl {
            SetupControl(try #require(descriptor.option(key)).kind)
        }
        guard case .segmented(let scores) = try control(x01, "startScore") else { Issue.record("301/501/701"); return }
        #expect(scores.count == 3)
        if case .optionalStepper(let range, let null) = try control(x01, "maxRounds") {
            #expect(range == 1...99 && null.fr == "Sans limite")
        } else {
            Issue.record("maxRounds is an optional stepper")
        }
        guard case .radio(let levels) = try control(killer, "level") else { Issue.record("levels"); return }
        #expect(levels.count == 4)
        #expect(try control(killer, "lives") == .stepper(1...9))
        #expect(try control(killer, "selfHitPenalty") == .toggle)
        guard case .segmented = try control(halveIt, "targets") else { Issue.record("two choices without detail"); return }
        #expect(try descriptor(.killer).option("selfHitPenalty")?.isAdvanced == true)
    }

    @Test func pictograms_ofTheKillerLevels() {
        #expect(SetupPictogram.highlights(count: 3, moving: false).map(\.zone) == [.sector(5), .sector(20), .sector(1)])
        #expect(SetupPictogram.highlights(count: 2, moving: false).map(\.zone) == [.sector(20), .sector(1)])
        let expert = SetupPictogram.highlights(count: 1, moving: true)
        #expect(expert.map(\.zone) == [.sector(20), .sector(10)] && expert.map(\.role) == [.target, .secondary])
        // The levels sheet (mock-up `KillerLevels`): four players from the 20, the 6, the 3 and the 11.
        let easy = SetupLevelsContent.example(count: 3, moving: false)
        #expect(easy.filter { $0.owner == 0 }.map(\.zone) == [.sector(20), .sector(1), .sector(18)])
        #expect(easy.filter { $0.owner == 2 }.map(\.zone) == [.sector(3), .sector(19), .sector(7)])
        #expect(easy.filter { $0.owner == 3 }.map(\.zone) == [.sector(11), .sector(14), .sector(9)])
        let moving = SetupLevelsContent.example(count: 1, moving: true)
        #expect(moving.filter { $0.owner == 0 }.map(\.zone) == [.sector(20), .sector(4)])
        #expect(moving.filter { $0.owner == 0 }.map(\.role) == [.secondary, .target])
    }

    // MARK: Small rules of the other screens

    @Test func roster_moveAndRename() {
        let roster = testPlayers(3)
        #expect(PlayersRoster.moving(roster[2], by: -1, in: roster) == [roster[0], roster[2], roster[1]])
        #expect(PlayersRoster.moving(roster[0], by: -1, in: roster) == roster)
        #expect(PlayersRoster.moving(roster[2], by: 1, in: roster) == roster)
        let renamed = PlayersRoster.renaming(roster[1], to: "  Tom ", in: roster)
        #expect(renamed[1] == Player(id: roster[1].id, name: "Tom") && renamed[0] == roster[0])
        #expect(PlayersRoster.renaming(roster[1], to: "   ", in: roster) == roster)
    }

    @Test func correctionChoices_areTheNeighboursOfTheMockUp() {
        #expect(PlayCorrectionChoices.around(.treble(19)) == [.treble(19), .single(19), .treble(7), .treble(3), .single(7), .single(3)])
        #expect(PlayCorrectionChoices.around(.single(20)) == [.single(20), .treble(20), .single(1), .single(5), .double(20)])
        #expect(PlayCorrectionChoices.around(.innerBull) == [.innerBull, .outerBull])
        #expect(PlayCorrectionChoices.around(.miss).isEmpty)
    }

    @Test func resultsRanking_sharesTheRanksOfATie() throws {
        // HIS-2: 60 / 60 / 20 gives ranks 1, 1, 3.
        var match = try GameRegistry.standard.match(.highScore, ["rounds": 1], players: 3)
        match.play("S20, S20, S20 | T20, MISS, MISS | S19, S1, MISS |")
        #expect(match.snapshot.ranks == [1, 1, 3] && match.snapshot.winners == [0, 1])
        #expect(ResultsRanking.order(match.snapshot) == [0, 1, 2])
        var reversed = try GameRegistry.standard.match(.highScore, ["rounds": 1], players: 3)
        reversed.play("S1, MISS, MISS | T20, MISS, MISS | S20, S20, MISS |")
        #expect(ResultsRanking.order(reversed.snapshot) == [1, 2, 0])
    }

    @Test func homeCameraCard_followsTheModeAndTheReadiness() {
        #expect(HomeCameraState(inputMode: .manual, readiness: .ready(grade: .good)) == .manual)
        #expect(HomeCameraState(inputMode: .camera, readiness: .ready(grade: .fair)) == .ready(.fair))
        #expect(HomeCameraState(inputMode: .camera, readiness: .needsCalibration) == .needsCalibration)
        #expect(HomeCameraState(inputMode: .camera, readiness: .unknown) == .unavailable)
        #expect(HomeCameraState(inputMode: .camera, readiness: .unavailable(.accessDenied)) == .unavailable)
    }

    @Test func settingsLanguage_roundTrip() {
        for language in [nil, AppLanguage.fr, .en] {
            #expect(SettingsLanguageChoice(language).language == language)
        }
    }

    @Test func playLayout_andTheDrawnDarts() throws {
        #expect(PlayLayout.resolve(for: SnapshotDevice.phonePortrait.size) == .stacked)
        #expect(PlayLayout.resolve(for: SnapshotDevice.padPortrait.size) == .stacked)
        #expect(PlayLayout.resolve(for: SnapshotDevice.padLandscape.size) == .sideBySide)
        #expect(PlayLayout.resolve(for: SnapshotDevice.phoneLandscape.size) == .sideBySide)
        // Markers: the recorded position, else the centre of the bed; none for a miss; "?" for a dart to check.
        var match = try GameRegistry.standard.match(.x01, players: 2)
        match.throwDart(DartRecord(id: gameFlowID(1), hit: .treble(20), position: BoardPoint(x: 1, y: 104)))
        match.throwDart(DartRecord(id: gameFlowID(2), hit: .single(5), needsReview: true))
        match.throwDart(DartRecord(id: gameFlowID(3), hit: .miss))
        let model = GameFlowFixtures.model(match)
        #expect(model.markers.map(\.position) == [BoardPoint(x: 1, y: 104), BoardGeometry.standard.centre(of: .single(5))])
        #expect(model.markers.map(\.style) == [.player(0), .review])
        // The score template leaves the board bright around a checkout ring (mock-up `PlayX01`).
        #expect(!model.dimsBoard && model.boardGeometry == .display)
        let killer = GameFlowFixtures.model(try GameRegistry.standard.match(.killer, players: 2))
        #expect(killer.dimsBoard && killer.markers.isEmpty)
        let radar = GameFlowFixtures.model(try GameRegistry.standard.match(.radar, players: 2))
        #expect(radar.boardGeometry == .standard)
    }

    @Test func correctionModel_ofARunningGame() throws {
        let rig = try GameFlowRig(.highScore, players: 1)
        let tip = BoardPoint(x: -20, y: -100)
        rig.game.receive(gameFlowProposal("T3", id: 1, certainty: .needsReview, position: tip))
        rig.game.receive(gameFlowProposal("S7", id: 2, certainty: .undecided, choices: ["S16", "S19"]))
        let recorded = try #require(PlayCorrectionModel(game: rig.game, target: .recorded(index: 0), choice: nil,
                                                        evidence: nil, reticle: .zero))
        #expect(recorded.index == 0 && recorded.needsReview && recorded.detected == .treble(3) && recorded.tip == tip)
        #expect(recorded.choices.first == .treble(3) && recorded.dartID == gameFlowID(1))
        let pending = try #require(PlayCorrectionModel(game: rig.game, target: .pending(id: gameFlowID(2)), choice: nil,
                                                       evidence: nil, reticle: .zero))
        #expect(pending.index == 1 && pending.isPending && pending.choices == [.single(7), .single(16), .single(19)])
        #expect(PlayCorrectionModel(game: rig.game, target: .recorded(index: 5), choice: nil, evidence: nil, reticle: .zero) == nil)
        #expect(PlayCorrectionModel(game: rig.game, target: .pending(id: gameFlowID(9)), choice: nil, evidence: nil, reticle: .zero) == nil)
    }

    @Test func photoAction_isAlwaysThere_theScanOnlyWithASource() throws {
        // §8.6: "Photo" is present in manual input, without a camera; the live scan needs a source.
        let manual = try GameFlowRig(.highScore, players: 1, withSource: false)
        #expect(PlayContentModel(game: manual.game).headerActions == [.photo])
        let camera = try GameFlowRig(.highScore, players: 1)
        #expect(PlayContentModel(game: camera.game).headerActions == [.scanView, .photo])
        for status in [InputStatus.preparing, .live, .awaitingCapture, .obstructed, .paused, .needsEmptyBoard,
                       .needsCalibration, .unavailable, .manualOnly] {
            var model = PlayContentModel(game: camera.game)
            model.inputStatus = status
            #expect(model.headerActions.contains(.photo), "\(status)")
        }
    }

    @Test func resultsHeadline_isTheTitleOfTheGame_elseTheWinners() throws {
        let football = try #require(GameFlowFixtures.footballFinished())
        #expect(ResultsHeadline(football.snapshot) == .title(LocalizedText(fr: "Le camp A gagne", en: "Side A wins")))
        let killer = try #require(GameFlowFixtures.killerFinished())
        #expect(ResultsHeadline(killer.snapshot) == .winners([0]))
        var tie = try GameRegistry.standard.match(.highScore, ["rounds": 1], players: 3)
        tie.play("S20, S20, S20 | T20, MISS, MISS | S19, S1, MISS |")
        #expect(ResultsHeadline(tie.snapshot) == .winners([0, 1]))
    }

    @Test func gameStrings_areFoundInBothLanguages_withTheirArguments() {
        func both(_ key: String.LocalizationValue) -> [String] {
            AppLanguage.allCases.map { L10n.string(key, .game, language: $0) }
        }
        #expect(both("play.round.limit \(4) \(15)") == ["manche 4 sur 15", "round 4 of 15"])
        #expect(both("play.round \(3)") == ["manche 3", "round 3"])
        #expect(both("play.turnOf \("Léa")") == ["Au tour de Léa", "Léa to throw"])
        #expect(both("correction.confirm \("T19")") == ["Valider T19", "Confirm T19"])
        #expect(both("results.rounds.other \(9)") == ["9 manches", "9 rounds"])
        #expect(both("setup.levels.players \(2) \(6)") == ["2 à 6 joueurs.", "2 to 6 players."])
        #expect(both("play.nextPlayer") == ["Fléchettes retirées, suivant", "Darts removed, next"])
        #expect(both("play.photo") == ["Photo", "Photo"])
    }
}
