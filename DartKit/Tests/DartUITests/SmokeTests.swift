import Foundation
import CoreGraphics
import SwiftUI
import Testing
import DartCore
import DartGames
import DartVision
import DartAudio
import DartTestSupport
@testable import DartUI

/// A store for these tests: `InMemoryStore` is written by lot U1.
private final class SmokeMemoryStore: KeyValueStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Data] = [:]

    func data(forKey key: String) -> Data? {
        lock.lock()
        defer { lock.unlock() }
        return values[key]
    }

    func set(_ data: Data?, forKey key: String) {
        lock.lock()
        defer { lock.unlock() }
        values[key] = data
    }
}

/// A dart source that does nothing: enough to give a game a source.
@MainActor
private final class SmokeInputSource: DartInputSource {
    var status: InputStatus = .live
    func events() -> AsyncStream<DartInputEvent> { AsyncStream { $0.finish() } }
    func gameStarted(boardConfirmedEmpty: Bool) {}
    func turnBegan(expectedDarts: Int) {}
    func turnClosed() {}
    func dartDiscarded(_ id: UUID) {}
    func manualDartAdded() {}
    func turnConfirmed(_ feedback: [DartFeedback]) {}
    func boardConfirmedEmpty() {}
    func gameEnded() {}
    func evidenceImage(for id: UUID) async -> CGImage? { nil }
    func rescore(_ id: UUID, tip point: BoardPoint) async -> DartProposal? { nil }
}

/// Smoke tests of lot F0 on the DartUI skeleton (ARCHITECTURE.md §8.4, §13.2): what is complete from the first
/// day answers without trapping. The bodies that lots U1 to U3 wrote later are not called here: everything
/// asserted here stays true after them.
@MainActor
@Suite struct SmokeTests {
    private func storage() -> DartUI.AppStorage {
        DartUI.AppStorage(store: SmokeMemoryStore())
    }

    private func observation(_ id: UUID) -> DartObservation {
        DartObservation(id: id, visit: 1, indexInVisit: 0, timestamp: 3, tip: BoardPoint(x: 0, y: 103),
                        uncertainty: TipUncertainty(sigmaAlong: 1, sigmaAcross: 0.5, axis: SIMD2(0, 1)),
                        candidates: [HitCandidate(hit: .treble(20), probability: 1)], nearbyHits: [.single(20)],
                        confidence: 0.9, tier: .high, flags: [], source: .liveCamera)
    }

    // MARK: FakeScanService (complete from lot F0 on, §8.4.8)

    @Test func fakeScanService_recordsWhatItReceives_inOrder() async {
        let service = FakeScanService()
        #expect(service.cameraID == "fake" && service.issue == nil && !service.isRunning && service.frameInfo == nil)
        if case .none = service.preview {} else { Issue.record("the fake has no preview") }
        await service.send(.setTrigger(.automatic))
        await service.send(.arm(boardConfirmedEmpty: true))
        await service.send(.pause(.background))
        await service.send(.resume)
        // Whole lists compare with `==`: the vision values are Hashable.
        #expect(service.commands == [.setTrigger(.automatic), .arm(boardConfirmedEmpty: true), .pause(.background), .resume])
        var configuration = VisionConfiguration()
        configuration.detection.shadowLowerBound = 0.3
        await service.updateConfiguration(configuration)
        #expect(service.configurations == [configuration] && service.calibrations.isEmpty)
        let id = UUID(), other = UUID()
        await service.recordFeedback(id, wasCorrected: true)
        await service.recordFeedback(other, wasCorrected: false)
        #expect(service.feedback.map(\.id) == [id, other] && service.feedback.map(\.wasCorrected) == [true, false])
        // Scripted answers.
        #expect(await service.correct(id, tip: BoardPoint(x: 1, y: 2)) == nil)
        service.correctionResult = observation(id)
        #expect(await service.correct(id, tip: BoardPoint(x: 3, y: 4)) == observation(id))
        #expect(service.corrections.map(\.id) == [id, id])
        #expect(service.corrections.map(\.tip) == [BoardPoint(x: 1, y: 2), BoardPoint(x: 3, y: 4)])
        #expect(await service.evidenceCrop(for: id) == nil)
        #expect(await service.runLightingCheck(confirmedTip: BoardPoint(x: 0, y: 0)) == nil)
        #expect(await service.currentState() == .needsCalibration)
    }

    @Test func fakeScanService_scriptedStartAndStills() async throws {
        let noCamera = FakeScanService(issue: .noCamera)
        await #expect(throws: ScanServiceError(issue: .noCamera)) { try await noCamera.start() }
        await #expect(throws: ScanServiceError(issue: .noCamera)) { try await noCamera.captureStill(averaging: 8) }
        #expect(!noCamera.isRunning && noCamera.stillRequests == [8])
        // Without a still, a capture fails as on a device without a camera.
        let empty = FakeScanService()
        try await empty.start()
        #expect(empty.isRunning && empty.frameInfo == nil)
        await #expect(throws: ScanServiceError(issue: .noCamera)) { try await empty.captureStill(averaging: 1) }
        // With a still: `frameInfo` describes it once the service runs.
        let still = RGBImage(width: 2, height: 1, pixels: [1, 2, 3, 4, 5, 6])
        let service = FakeScanService(still: still)
        #expect(service.frameInfo == nil)
        try await service.start()
        #expect(service.frameInfo == FrameSourceInfo(size: PixelSize(width: 2, height: 1), nominalFramesPerSecond: 30,
                                                     rotationDegrees: 0, intrinsics: nil, isLive: false))
        #expect(try await service.captureStill(averaging: 8) == still)
        #expect(try await service.captureStill(averaging: 1) == still)
        #expect(service.stillRequests == [8, 1])
        await service.stop()
        #expect(!service.isRunning && service.frameInfo == nil)
    }

    @Test func fakeScanService_pushesEventsToEveryOpenStream() async {
        let service = FakeScanService()
        let first = service.events(), second = service.events()
        let id = UUID()
        let events: [ScanEvent] = [.stateChanged(.idle), .dart(observation(id)), .dartDisturbed(id: id), .takeoutCompleted,
                                   .stateChanged(.paused(.user))]
        for event in events { service.emit(event) }
        // `stateChanged` also updates what `currentState()` answers.
        #expect(await service.currentState() == .paused(.user))
        // Stopping finishes the streams; what was emitted before is still delivered, in order.
        await service.stop()
        var seenByFirst: [ScanEvent] = [], seenBySecond: [ScanEvent] = []
        for await event in first { seenByFirst.append(event) }
        for await event in second { seenBySecond.append(event) }
        #expect(seenByFirst == events && seenBySecond == events)
    }

    // MARK: CameraModel (minimal body written by lot F0, §8.4.8)

    @Test func cameraModel_withoutACamera_everyGameIsPlayedByHand() {
        let service = FakeScanService(issue: .noCamera)
        let camera = CameraModel(service: service, storage: storage())
        #expect(camera.readiness == .unknown && camera.calibration == nil)
        #expect(camera.scanState == .needsCalibration && !camera.lightingCheckPassed)
        #expect(camera.service === service)
        // No source while the camera is known to be unavailable.
        #expect(camera.makeInputSource(mode: .live) == nil && camera.makeInputSource(mode: .photo) == nil)
        #expect(CameraModel.Readiness.ready(grade: .good) != .ready(grade: .fair))
        #expect(CameraModel.Readiness.unavailable(.noCamera) != .unavailable(.accessDenied))
    }

    // MARK: PlayViewModel (initialiser written by lot F0, §8.4.7)

    @Test func playViewModel_initStoresItsParameters() throws {
        var match = try GameRegistry.standard.match(.highScore, players: 2, seed: 1)
        let fresh = PlayViewModel(match: match, source: nil, sound: SilentSoundPlayer(), storage: storage(), endsTurnOnTakeout: false)
        #expect(fresh.snapshot.gameID == .highScore && fresh.snapshot == match.snapshot)
        #expect(fresh.descriptor.id == .highScore && fresh.descriptor.playStyle == .score)
        #expect(fresh.turnRecords.isEmpty && fresh.pending.isEmpty)
        // Without a source the game is played by hand.
        #expect(fresh.inputStatus == .manualOnly && fresh.prompt == nil && fresh.correction == nil)
        // A game resumed in the middle of a turn shows the darts of that turn.
        match.play("T20, S5")
        let resumed = PlayViewModel(match: match, source: SmokeInputSource(), sound: SilentSoundPlayer(), storage: storage(),
                                    endsTurnOnTakeout: true)
        #expect(resumed.turnRecords.map(\.hit) == [.treble(20), .single(5)] && resumed.snapshot.turn.darts.count == 2)
        #expect(resumed.inputStatus != .manualOnly && resumed.id != fresh.id)
        resumed.prompt = .confirmShortTurn
        resumed.correction = .recorded(index: 1)
        #expect(resumed.prompt == .confirmShortTurn && resumed.correction?.id == "recorded-1")
        let pending = UUID()
        #expect(CorrectionTarget.pending(id: pending).id == "pending-\(pending.uuidString)")
        // A game ended at the round limit has no dart left in its turn, in the journal as in the snapshot:
        // the records stay aligned with the slots on the results screen too.
        var ended = try GameRegistry.standard.match(.highScore, ["rounds": 1], players: 1, seed: 1)
        ended.play("T20, T20, T20 |")
        let results = PlayViewModel(match: ended, source: nil, sound: SilentSoundPlayer(), storage: storage(), endsTurnOnTakeout: false)
        #expect(results.snapshot.phase == .finished && results.snapshot.finishReason == .roundLimit)
        #expect(results.turnRecords.isEmpty && results.snapshot.turn.darts.isEmpty)
    }

    // MARK: Entry views (§8.4.10)

    @Test func theElevenEntryViews_areBuiltWithoutTrapping() throws {
        let match = try GameRegistry.standard.match(.highScore, players: 1)
        let game = PlayViewModel(match: match, source: nil, sound: SilentSoundPlayer(), storage: storage(), endsTurnOnTakeout: false)
        let camera = CameraModel(service: FakeScanService(issue: .noCamera), storage: storage())
        let views: [any View] = [
            HomeScreen(),
            SetupScreen(game: .killer),
            PlayersScreen(),
            SettingsScreen(),
            PlayScreen(game: game),
            CorrectionSheet(game: game, target: .recorded(index: 0)),
            CalibrationFlowView(camera: camera, onFinish: {}),
            PlacementGuideView(),
            LiveScanView(game: game, camera: camera),
            ScanThumbnail(camera: camera, onExpand: {}),
            PhotoModeView(game: game, camera: camera),
        ]
        // The test passes when the eleven initialisers return without trapping. The one thing left to compare:
        // the list names eleven DIFFERENT views, none of them twice.
        #expect(Set(views.map { ObjectIdentifier(type(of: $0)) }).count == 11)
    }

    // MARK: Darts entering the game (§8.4.6)

    @Test func manualProposal_isCertain_andBecomesAJournalRecord() throws {
        let match = try GameRegistry.standard.match(.highScore, players: 1)
        let tap = DartProposal.manual(.treble(20), position: BoardPoint(x: 0, y: 103))
        #expect(tap.hit == .treble(20) && tap.position == BoardPoint(x: 0, y: 103) && tap.origin == .manual)
        #expect(tap.choices == [.treble(20)] && tap.certainty(match) == .certain)
        let record = tap.record(needsReview: true)
        #expect(record.id == tap.id && record.hit == .treble(20) && record.position == BoardPoint(x: 0, y: 103))
        #expect(record.origin == .manual && record.needsReview && !record.corrected)
        // A hit picked in a list has no position.
        #expect(DartProposal.manual(.miss).position == nil && !DartProposal.manual(.miss).record(needsReview: false).needsReview)
    }

    // MARK: Layout, theme, settings (complete listings)

    @Test func playLayout_followsTheSizeOfTheContainer() {
        #expect(PlayLayout.resolve(for: CGSize(width: 393, height: 852)) == .stacked)
        #expect(PlayLayout.resolve(for: CGSize(width: 852, height: 393)) == .sideBySide)
        #expect(PlayLayout.resolve(for: CGSize(width: 1194, height: 834)) == .sideBySide)
        #expect(PlayLayout.resolve(for: CGSize(width: 600, height: 600)) == .stacked)
    }

    @Test func theme_metricsAndPlayerColours() {
        #expect(Theme.Metrics(.regular) == .regular && Theme.Metrics(.compact) == .compact && Theme.Metrics(nil) == .compact)
        #expect(Theme.Metrics.compact.buttonHeight == 52 && Theme.Metrics.regular.buttonHeight == 56)
        #expect(Theme.Palette.players.count == 8)
        // The colour of a player is the colour of their place in the game, modulo eight.
        #expect(Theme.playerColor(0) == Theme.Palette.players[0] && Theme.playerColor(8) == Theme.Palette.players[0])
        #expect(Theme.playerColor(-1) == Theme.Palette.players[7])
        #expect(Theme.color(for: .accent) == Theme.Palette.accent && Theme.color(for: .negative) == Theme.Palette.boardRed)
    }

    @Test func settings_defaults_andStorageKeys() throws {
        let settings = AppSettings()
        #expect(settings.audio == AudioSettings() && settings.inputMode == .manual && settings.scanMode == .live)
        #expect(settings.language == nil && !settings.endsTurnOnTakeout)
        #expect(try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings)) == settings)
        #expect(StorageKey.settings == "settings.v1" && StorageKey.roster == "roster.v1")
        #expect(StorageKey.calibrations == "calibrations.v1" && StorageKey.currentMatch == "match.current.v1")
        #expect(StorageKey.setup(.killer) == "setup.killer.v1")
        // The drawing geometry of a game is data: regulation proportions for a position-dependent game only.
        for descriptor in GameRegistry.standard.descriptors {
            #expect(descriptor.boardGeometry == (descriptor.dependsOnPosition ? BoardGeometry.standard : BoardGeometry.display))
        }
    }

    // MARK: String tables (§8.9)

    @Test func stringTables_existInBothLanguages_withTheSameKeys() throws {
        #expect(L10nTable.allCases.map(\.rawValue) == ["Common", "Game", "Camera"])
        for table in L10nTable.allCases {
            var keys: [Set<String>] = []
            for language in AppLanguage.allCases {
                let url = try #require(L10n.bundle.url(forResource: table.rawValue, withExtension: "strings", subdirectory: nil,
                                                       localization: language.rawValue), "\(table.rawValue) (\(language.rawValue))")
                let entries = try #require(NSDictionary(contentsOf: url) as? [String: String])
                #expect(!entries.isEmpty, "\(table.rawValue) (\(language.rawValue)) is empty")
                #expect(entries.values.allSatisfy { !$0.isEmpty })
                keys.append(Set(entries.keys))
            }
            #expect(keys.count == 2 && keys[0] == keys[1], "\(table.rawValue): fr and en keys differ")
        }
    }

    // MARK: Snapshots (§8.11)

    @Test func snapshotCatalog_hasScreens_withUniqueFileNames() {
        #expect(SnapshotDevice.allCases.map(\.size) == [CGSize(width: 393, height: 852), CGSize(width: 852, height: 393),
                                                        CGSize(width: 834, height: 1194), CGSize(width: 1194, height: 834)])
        let screens = SnapshotCatalog.all
        #expect(!screens.isEmpty)
        #expect(screens.allSatisfy { !$0.id.isEmpty && !$0.devices.isEmpty })
        // SnapshotTool writes `<id>@<device>.png`: two screens must not write the same file.
        let files = screens.flatMap { screen in screen.devices.map { "\(screen.id)@\($0.rawValue)" } }
        #expect(Set(files).count == files.count)
    }

    @Test func framedView_rendersToAnImageOfTheDeviceSize_inBothLanguages() throws {
        var rendered: [AppLanguage: CGImage] = [:]
        for language in AppLanguage.allCases {
            let content = AnyView(LocalizedTextView(LocalizedText(fr: "Squelette", en: "Skeleton")).font(Theme.Typography.screenTitle))
            let renderer = ImageRenderer(content: SnapshotCatalog.framed(content, device: .phonePortrait, language: language))
            renderer.proposedSize = ProposedViewSize(SnapshotDevice.phonePortrait.size)
            renderer.scale = 1
            let image = try #require(renderer.cgImage)
            #expect(image.width == 393 && image.height == 852)
            rendered[language] = image
        }
        // The text follows the language of the frame: the two images differ.
        let french = try #require(rendered[.fr]?.dataProvider?.data as Data?)
        let english = try #require(rendered[.en]?.dataProvider?.data as Data?)
        #expect(french != english)
    }
}
