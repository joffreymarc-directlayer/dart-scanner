import Foundation
import Testing
import DartCore
import DartGames
import DartAudio
import DartVision
import DartTestSupport
@testable import DartUI

/// Persistence of lot U1 (ARCHITECTURE.md §8.4.5, §8.10): the two stores and the typed access of `AppStorage`.
/// The round trip of a `StoredCalibration` belongs to lot U3 (§12.1): no lot outside DartVision can build a
/// `BoardCalibration` in wave 1.
@Suite struct KernelStorageTests {
    private func storage(_ store: InMemoryStore = InMemoryStore()) -> DartUI.AppStorage {
        DartUI.AppStorage(store: store)
    }

    /// A game with darts, positions and an `endTurn`, built without any clock or random source.
    private func playedRecord() throws -> MatchRecord {
        let configuration = GameConfiguration(gameID: .highScore, options: ["rounds": 3], players: testPlayers(2), seed: 7)
        let definition = try #require(GameRegistry.standard.definition(for: .highScore))
        var match = try GameMatch(definition: definition, configuration: configuration,
                                  startedAt: Date(timeIntervalSinceReferenceDate: 1_000))
        match.throwDart(DartRecord(id: Self.uuid(1), hit: .treble(20), position: BoardPoint(x: 0.5, y: 103.25), origin: .camera,
                                   needsReview: true))
        match.throwDart(DartRecord(id: Self.uuid(2), hit: .single(5), origin: .manual))
        match.throwDart(DartRecord(id: Self.uuid(3), hit: .miss, position: BoardPoint(x: -200, y: 12), origin: .photo))
        match.endTurn()
        match.throwDart(DartRecord(id: Self.uuid(4), hit: .innerBull, position: .centre, origin: .scan))
        return match.record
    }

    private static func uuid(_ n: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", n)) ?? UUID()
    }

    // MARK: Stores

    @Test func inMemoryStore_startsWithItsInitialValues_writesAndRemoves() {
        // The initialiser of the skeleton trapped: an empty store and a seeded one are both built.
        let empty = InMemoryStore()
        #expect(empty.data(forKey: "a") == nil)
        let store = InMemoryStore(["a": Data([1, 2]), "b": Data()])
        #expect(store.data(forKey: "a") == Data([1, 2]))
        #expect(store.data(forKey: "b") == Data())
        #expect(store.data(forKey: "c") == nil)
        store.set(Data([3]), forKey: "a")
        store.set(Data([4]), forKey: "c")
        #expect(store.data(forKey: "a") == Data([3]) && store.data(forKey: "c") == Data([4]))
        // Nil removes the blob, and only that one.
        store.set(nil, forKey: "a")
        #expect(store.data(forKey: "a") == nil && store.data(forKey: "c") == Data([4]) && store.data(forKey: "b") == Data())
        // Removing a missing key is not an error.
        store.set(nil, forKey: "missing")
        #expect(store.data(forKey: "missing") == nil)
    }

    @Test func inMemoryStore_isSafeFromSeveralThreads() async {
        let store = InMemoryStore()
        await withTaskGroup(of: Void.self) { group in
            for writer in 0..<8 {
                group.addTask {
                    for index in 0..<200 {
                        store.set(Data([UInt8(writer)]), forKey: "key-\(writer)-\(index)")
                        _ = store.data(forKey: "key-\(writer)-\(index / 2)")
                    }
                }
            }
        }
        for writer in 0..<8 {
            for index in 0..<200 {
                #expect(store.data(forKey: "key-\(writer)-\(index)") == Data([UInt8(writer)]))
            }
        }
    }

    @Test func userDefaultsStore_writesReadsAndRemoves_inItsSuite() throws {
        let suite = "DartUITests.KernelStorageTests.suite"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = UserDefaultsStore(suiteName: suite)
        #expect(store.data(forKey: StorageKey.settings) == nil)
        store.set(Data([9, 8, 7]), forKey: StorageKey.settings)
        #expect(store.data(forKey: StorageKey.settings) == Data([9, 8, 7]))
        // The blob is in the suite, under the key, as data: a second store on the same suite reads it.
        #expect(defaults.data(forKey: StorageKey.settings) == Data([9, 8, 7]))
        #expect(UserDefaultsStore(suiteName: suite).data(forKey: StorageKey.settings) == Data([9, 8, 7]))
        // The suite is separate from the standard defaults.
        #expect(UserDefaultsStore().data(forKey: StorageKey.settings) != Data([9, 8, 7]))
        store.set(nil, forKey: StorageKey.settings)
        #expect(store.data(forKey: StorageKey.settings) == nil && defaults.object(forKey: StorageKey.settings) == nil)

        // The typed access works over it as over any store.
        let typed = DartUI.AppStorage(store: store)
        var settings = AppSettings()
        settings.inputMode = .camera
        typed.save(settings)
        #expect(typed.loadSettings() == settings)
        typed.saveCurrentMatch(nil)
    }

    // MARK: Typed access: round trips

    @Test func settings_roundTrip_andDefaultsWhenNothingIsStored() throws {
        let store = InMemoryStore()
        let storage = storage(store)
        #expect(storage.loadSettings() == AppSettings())

        var settings = AppSettings()
        settings.audio.isMuted = true
        settings.audio.effectsEnabled = false
        settings.audio.callerEnabled = false
        settings.audio.callerLanguage = .en
        settings.audio.volume = 0.25
        settings.audio.playsInSilentMode = false
        settings.audio.ducksMusicWhileSpeaking = false
        settings.audio.hapticsEnabled = false
        settings.inputMode = .camera
        settings.scanMode = .photo
        settings.language = .en
        settings.endsTurnOnTakeout = true
        storage.save(settings)
        #expect(storage.loadSettings() == settings)
        // Stored under the versioned key of §8.10, as plain JSON.
        let blob = try #require(store.data(forKey: "settings.v1"))
        let json = try #require(JSONSerialization.jsonObject(with: blob) as? [String: Any])
        #expect(json["inputMode"] as? String == "camera" && json["scanMode"] as? String == "photo")
        #expect(json["language"] as? String == "en" && json["endsTurnOnTakeout"] as? Bool == true)
        // A second storage over the same store reads the same value: nothing is cached.
        #expect(self.storage(store).loadSettings() == settings)
        // "Follow the system language" (nil) survives the round trip too.
        settings.language = nil
        storage.save(settings)
        #expect(storage.loadSettings().language == nil && storage.loadSettings() == settings)
    }

    @Test func roster_roundTrip_keepsOrderIdentifiersAndNames() throws {
        let store = InMemoryStore()
        let storage = storage(store)
        #expect(storage.loadRoster().isEmpty)
        let roster = [Player(id: Self.uuid(3), name: "Léa"), Player(id: Self.uuid(1), name: "Tom"),
                      Player(id: Self.uuid(2), name: "Inès \"la flèche\"")]
        storage.save(roster: roster)
        #expect(storage.loadRoster() == roster)
        #expect(store.data(forKey: "roster.v1") != nil)
        storage.save(roster: [])
        #expect(storage.loadRoster().isEmpty)
    }

    @Test func setup_roundTrip_isKeptPerGame() throws {
        let store = InMemoryStore()
        let storage = storage(store)
        #expect(storage.loadSetup(for: .killer) == nil)
        let killer = SetupMemory(playerIDs: [Self.uuid(2), Self.uuid(1)],
                                 options: ["level": "easy", "lives": 3, "maxRounds": .null, "selfHitPenalty": true])
        let halveIt = SetupMemory(playerIDs: [Self.uuid(1)], options: ["targets": .strings(["20", "D7", "BULL"])])
        storage.save(killer, for: .killer)
        storage.save(halveIt, for: .halveIt)
        #expect(storage.loadSetup(for: .killer) == killer)
        #expect(storage.loadSetup(for: .halveIt) == halveIt)
        // One blob per game, under its own key; a game never set up has none.
        #expect(store.data(forKey: "setup.killer.v1") != nil && store.data(forKey: "setup.halveIt.v1") != nil)
        #expect(storage.loadSetup(for: .x01) == nil)
        // Saving again replaces the choices of that game only.
        let changed = SetupMemory(playerIDs: [], options: [:])
        storage.save(changed, for: .killer)
        #expect(storage.loadSetup(for: .killer) == changed && storage.loadSetup(for: .halveIt) == halveIt)
    }

    @Test func currentMatch_roundTrip_withPositions_thenDeleted() throws {
        let store = InMemoryStore()
        let storage = storage(store)
        #expect(storage.loadCurrentMatch() == nil)
        let record = try playedRecord()
        #expect(record.entries.count == 5)
        storage.saveCurrentMatch(record)
        let loaded = try #require(storage.loadCurrentMatch())
        #expect(loaded == record)
        #expect(loaded.startedAt == Date(timeIntervalSinceReferenceDate: 1_000) && loaded.configuration.seed == 7)
        #expect(loaded.entries.first?.position == BoardPoint(x: 0.5, y: 103.25))
        #expect(store.data(forKey: "match.current.v1") != nil)
        // The saved record rebuilds the very same game.
        let restored = try GameRegistry.standard.restoreMatch(loaded)
        #expect(restored.record == record && restored.currentTurn.map(\.hit) == [.innerBull])
        // Nil deletes the saved game.
        storage.saveCurrentMatch(nil)
        #expect(storage.loadCurrentMatch() == nil && store.data(forKey: "match.current.v1") == nil)
    }

    @Test func currentMatch_withANonFinitePosition_isStillSaved() throws {
        // A coordinate that is not a number must not make the whole save fail silently: the game would be lost.
        let storage = storage()
        var record = try playedRecord()
        record.entries.append(.dart(DartRecord(id: Self.uuid(5), hit: .miss, position: BoardPoint(x: .infinity, y: -.infinity))))
        storage.saveCurrentMatch(record)
        let loaded = try #require(storage.loadCurrentMatch())
        #expect(loaded == record)
        // NaN is not equal to itself: compare the parts.
        record.entries.append(.dart(DartRecord(id: Self.uuid(6), hit: .miss, position: BoardPoint(x: .nan, y: 1))))
        storage.saveCurrentMatch(record)
        let withNaN = try #require(storage.loadCurrentMatch())
        #expect(withNaN.entries.count == record.entries.count)
        let last = try #require(withNaN.entries.last?.position)
        #expect(last.x.isNaN && last.y == 1)
    }

    // MARK: Corrupted blobs (§8.10: "un blob illisible rend la valeur par défaut")

    @Test func corruptedBlob_returnsTheDefaultValue_forEveryKey() throws {
        let garbage: [Data] = [Data(), Data("not json".utf8), Data("{".utf8), Data("[1, 2, 3]".utf8), Data("{\"inputMode\": 3}".utf8),
                               Data("null".utf8), Data([0xFF, 0xFE, 0x00])]
        for blob in garbage {
            let store = InMemoryStore([
                StorageKey.settings: blob, StorageKey.roster: blob, StorageKey.calibrations: blob,
                StorageKey.currentMatch: blob, StorageKey.setup(.killer): blob,
            ])
            let storage = storage(store)
            #expect(storage.loadSettings() == AppSettings())
            #expect(storage.loadRoster().isEmpty)
            #expect(storage.loadSetup(for: .killer) == nil)
            #expect(storage.loadCurrentMatch() == nil)
            #expect(storage.loadCalibration(cameraID: "fake", rotationDegrees: 0, imageSize: PixelSize(width: 2, height: 1)) == nil)
            // A corrupted blob does not stop the next save either.
            var settings = AppSettings()
            settings.scanMode = .photo
            storage.save(settings)
            storage.save(roster: testPlayers(2))
            #expect(storage.loadSettings() == settings && storage.loadRoster() == testPlayers(2))
        }
    }

    @Test func blobOfAnotherShape_fallsBackToTheDefault() throws {
        // A blob that is valid JSON but lacks a field of this version is unreadable as a whole (§8.10).
        let store = InMemoryStore([StorageKey.settings: Data("{\"inputMode\":\"camera\"}".utf8)])
        #expect(storage(store).loadSettings() == AppSettings())
        // A saved game whose journal holds an unknown dart notation is unreadable too: it is not half-loaded.
        let other = InMemoryStore()
        storage(other).saveCurrentMatch(try playedRecord())
        let blob = try #require(other.data(forKey: StorageKey.currentMatch))
        let text = try #require(String(data: blob, encoding: .utf8))
        #expect(text.contains("\"T20\""))
        other.set(Data(text.replacingOccurrences(of: "\"T20\"", with: "\"Z99\"").utf8), forKey: StorageKey.currentMatch)
        #expect(storage(other).loadCurrentMatch() == nil)
    }

    @Test func calibration_isNilWhenNothingIsStored() {
        let storage = storage()
        #expect(storage.loadCalibration(cameraID: "back-wide", rotationDegrees: 90, imageSize: PixelSize(width: 3840, height: 2160)) == nil)
        // An empty list is a valid blob without any match.
        let store = InMemoryStore([StorageKey.calibrations: Data("[]".utf8)])
        #expect(self.storage(store).loadCalibration(cameraID: "back-wide", rotationDegrees: 90,
                                                    imageSize: PixelSize(width: 3840, height: 2160)) == nil)
    }

    @Test func keys_doNotCollide() {
        // Every game has its own setup key, and none of them is one of the four fixed keys.
        let fixed = [StorageKey.settings, StorageKey.roster, StorageKey.calibrations, StorageKey.currentMatch]
        let setups = GameRegistry.standard.descriptors.map { StorageKey.setup($0.id) }
        #expect(Set(fixed + setups).count == fixed.count + setups.count)
        #expect(setups.count == 14)
    }
}
