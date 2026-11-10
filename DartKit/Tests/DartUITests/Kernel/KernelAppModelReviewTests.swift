import Foundation
import Testing
import DartCore
import DartGames
import DartAudio
import DartVision
import DartTestSupport
@testable import DartUI

/// Independent review of the root model of lot U1 (ARCHITECTURE.md §8.4.9, §8.5, §8.10): every game of the
/// registry starts with the seed and the date of the environment, a resumed game is the game that was saved, and
/// the settings reach the sound service.
@MainActor
@Suite struct KernelAppModelReviewTests {
    @Test func everyGameOfTheRegistry_startsWithTheSeedAndTheDateOfTheEnvironment() throws {
        var environment = AppEnvironment.preview()
        environment.makeSeed = { 0xDEAD_BEEF_0123_4567 }
        environment.now = { Date(timeIntervalSinceReferenceDate: 784_000_000.25) }
        for descriptor in GameRegistry.standard.descriptors {
            let allowed = descriptor.playerRange(for: descriptor.defaultOptions)
            for count in Set([allowed.lowerBound, allowed.upperBound]) {
                let app = AppModel(environment: environment)
                try app.startGame(descriptor.id, players: testPlayers(count), options: [:])
                let game = try #require(app.game, "\(descriptor.id) with \(count)")
                #expect(game.snapshot.gameID == descriptor.id)
                #expect(game.match.record.configuration.seed == 0xDEAD_BEEF_0123_4567)
                #expect(game.match.record.startedAt == Date(timeIntervalSinceReferenceDate: 784_000_000.25))
                #expect(game.match.record.entries.isEmpty && game.turnRecords.isEmpty)
                #expect(game.inputStatus == .manualOnly)
                // A new game is not saved before its first accepted input (§8.10).
                #expect(app.storage.loadCurrentMatch() == nil)
            }
        }
    }

    @Test func aResumedGame_isTheGameThatWasSaved() throws {
        let environment = AppEnvironment.preview()
        let configuration = GameConfiguration(gameID: .killer, options: [:], players: testPlayers(4), seed: UInt64.max - 7)
        let definition = try #require(GameRegistry.standard.definition(for: .killer))
        var match = try GameMatch(definition: definition, configuration: configuration,
                                  startedAt: Date(timeIntervalSinceReferenceDate: 12_345.678_9))
        match.throwDart(DartRecord(hit: .single(20), position: BoardPoint(x: 1.5, y: 140.25), origin: .manual))
        match.throwDart(DartRecord(hit: .treble(6), origin: .camera, needsReview: true))
        DartUI.AppStorage(store: environment.store).saveCurrentMatch(match.record)
        let app = AppModel(environment: environment)
        #expect(app.resumableMatch == match.record)
        app.resumeSavedGame()
        let game = try #require(app.game)
        #expect(game.match.record == match.record)
        #expect(game.snapshot == match.snapshot)
        #expect(game.turnRecords == match.currentTurn)
    }

    @Test func aSettingChange_isSavedAndReachesTheSound_once() {
        let environment = AppEnvironment.preview()
        let app = AppModel(environment: environment)
        app.settings.audio.callerLanguage = .en
        #expect(environment.sound.settings.callerLanguage == .en)
        #expect(DartUI.AppStorage(store: environment.store).loadSettings().audio.callerLanguage == .en)
        // A model built on the same store reads it back and pushes it to its sound service.
        let again = AppModel(environment: environment)
        #expect(again.settings.audio.callerLanguage == .en)
    }

    @Test func language_followsTheSetting_elseTheDevice() {
        #expect(AppModel.language(setting: .en, preferredLanguages: ["fr-FR"]) == .en)
        #expect(AppModel.language(setting: .fr, preferredLanguages: ["en-GB"]) == .fr)
        #expect(AppModel.language(setting: nil, preferredLanguages: ["de-DE", "en-GB", "fr-FR"]) == .en)
        #expect(AppModel.language(setting: nil, preferredLanguages: ["fr-CA", "en-US"]) == .fr)
        #expect(AppModel.language(setting: nil, preferredLanguages: ["de-DE", "it-IT"]) == .fr)
        #expect(AppModel.language(setting: nil, preferredLanguages: []) == .fr)
        let app = AppModel(environment: .preview())
        app.settings.language = .en
        #expect(app.language == .en)
        app.settings.language = .fr
        #expect(app.language == .fr)
    }
}
