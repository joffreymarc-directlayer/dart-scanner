import Foundation
import Testing
import DartCore
import DartGames
import DartAudio
import DartVision
import DartTestSupport
@testable import DartUI

/// Independent review of the persistence of lot U1 (ARCHITECTURE.md §8.4.5, §8.10): exact round trips of what a
/// real game saves (64-bit seeds, clock dates), one calibration per key, and corrupted blobs that never trap.
@MainActor
@Suite struct KernelStorageReviewTests {
    private static func uuid(_ n: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", n)) ?? UUID()
    }

    /// A Killer game (seeded zones) with darts and positions, as the live environment would save it.
    private func liveRecord(seed: UInt64, startedAt: Date) throws -> MatchRecord {
        let configuration = GameConfiguration(gameID: .killer, options: [:], players: testPlayers(4), seed: seed)
        let definition = try #require(GameRegistry.standard.definition(for: .killer))
        var match = try GameMatch(definition: definition, configuration: configuration, startedAt: startedAt)
        match.throwDart(DartRecord(id: Self.uuid(1), hit: .treble(20), position: BoardPoint(x: 0.123456789, y: 103.987654321),
                                   origin: .camera, needsReview: true))
        match.throwDart(DartRecord(id: Self.uuid(2), hit: .double(6), origin: .manual))
        return match.record
    }

    // MARK: What a real game saves comes back exactly

    @Test func matchRecord_withA64BitSeedAndAClockDate_comesBackExactly() throws {
        let seeds: [UInt64] = [0, 1, 1 << 53, (1 << 53) + 1, 0x910A_2DEC_8902_5CC1, UInt64.max - 12_345, UInt64.max]
        let dates = [Date(timeIntervalSinceReferenceDate: 0), Date(timeIntervalSinceReferenceDate: 784_123_456.789_012_3),
                     Date(timeIntervalSinceReferenceDate: -1.000_000_1), Date(timeIntervalSince1970: 1_794_000_000.5)]
        for seed in seeds {
            for date in dates {
                let store = InMemoryStore()
                let storage = DartUI.AppStorage(store: store)
                let record = try liveRecord(seed: seed, startedAt: date)
                storage.saveCurrentMatch(record)
                let loaded = try #require(storage.loadCurrentMatch())
                #expect(loaded == record, "seed \(seed), date \(date.timeIntervalSinceReferenceDate)")
                #expect(loaded.configuration.seed == seed)
                // The rule that `closeGame(discard: true)` relies on recognises the game after the round trip.
                #expect(AppModel.savedGame(in: storage, isTheGameOf: record), "seed \(seed)")
                // The resumed game is the same game: same zones, same journal, same picture.
                let original = try GameRegistry.standard.restoreMatch(record)
                let resumed = try GameRegistry.standard.restoreMatch(loaded)
                #expect(resumed.snapshot == original.snapshot, "seed \(seed)")
            }
        }
    }

    @Test func settings_everyFieldComesBack() {
        let storage = DartUI.AppStorage(store: InMemoryStore())
        var settings = AppSettings()
        settings.inputMode = .camera
        settings.scanMode = .photo
        settings.language = .en
        settings.endsTurnOnTakeout = true
        settings.audio.callerLanguage = .en
        storage.save(settings)
        #expect(storage.loadSettings() == settings)
        settings.language = nil
        storage.save(settings)
        #expect(storage.loadSettings() == settings && storage.loadSettings().language == nil)
    }

    // MARK: Calibrations: one per (camera, rotation, image size)

    private func calibration(width: Int, height: Int) -> BoardCalibration {
        SyntheticCamera(imageSize: PixelSize(width: width, height: height), position: SIMD3(0, -400, 1_000)).calibration(grade: .good)
    }

    @Test func calibration_oneIsKeptPerKey_andTheNewOneReplacesTheOld() throws {
        let storage = DartUI.AppStorage(store: InMemoryStore())
        let small = calibration(width: 1_920, height: 1_080), large = calibration(width: 3_840, height: 2_160)
        let first = StoredCalibration(cameraID: "back-wide", calibration: small, configuration: VisionConfiguration(),
                                      lightingCheckPassed: false)
        storage.save(first)
        #expect(storage.loadCalibration(cameraID: "back-wide", rotationDegrees: 0, imageSize: small.imageSize) == first)
        // Another camera, another image size: kept side by side.
        let other = StoredCalibration(cameraID: "synthetic", calibration: small, configuration: VisionConfiguration(),
                                      lightingCheckPassed: true)
        let bigger = StoredCalibration(cameraID: "back-wide", calibration: large, configuration: VisionConfiguration(),
                                       lightingCheckPassed: false)
        storage.save(other)
        storage.save(bigger)
        #expect(storage.loadCalibration(cameraID: "back-wide", rotationDegrees: 0, imageSize: small.imageSize) == first)
        #expect(storage.loadCalibration(cameraID: "synthetic", rotationDegrees: 0, imageSize: small.imageSize) == other)
        #expect(storage.loadCalibration(cameraID: "back-wide", rotationDegrees: 0, imageSize: large.imageSize) == bigger)
        // Same key: the one-dart check passed, the new value replaces the old one instead of adding a second one.
        var checked = first
        checked.lightingCheckPassed = true
        storage.save(checked)
        #expect(storage.loadCalibration(cameraID: "back-wide", rotationDegrees: 0, imageSize: small.imageSize) == checked)
        let all = try #require(storage.store.data(forKey: StorageKey.calibrations))
        let decoded = try JSONDecoder().decode([StoredCalibration].self, from: all)
        #expect(decoded.count == 3)
        // Nothing for a rotation or a size that was never calibrated.
        #expect(storage.loadCalibration(cameraID: "back-wide", rotationDegrees: 90, imageSize: small.imageSize) == nil)
        #expect(storage.loadCalibration(cameraID: "front", rotationDegrees: 0, imageSize: small.imageSize) == nil)
    }

    // MARK: Corrupted blobs never trap

    /// Every way a blob can go wrong: truncated, bytes flipped, numbers replaced, fields of another type.
    private func corruptions(of data: Data, random: inout SeededRandom) -> [Data] {
        var result: [Data] = [Data(), Data("null".utf8), Data("[]".utf8), Data("{}".utf8), Data([0xFF, 0xFE, 0x00])]
        let bytes = [UInt8](data)
        for _ in 0..<40 {
            var copy = bytes
            switch random.nextInt(below: 4) {
            case 0:
                copy = Array(copy.prefix(random.nextInt(below: max(1, copy.count))))
            case 1:
                for _ in 0..<(1 + random.nextInt(below: 4)) where !copy.isEmpty {
                    copy[random.nextInt(below: copy.count)] = UInt8(random.nextInt(below: 256))
                }
            case 2:
                // Every digit of the blob replaced, keeping the JSON readable: absurd numbers everywhere.
                let digits = "0123456789"
                copy = copy.map { byte in
                    digits.utf8.contains(byte) ? digits.utf8[digits.utf8.index(digits.utf8.startIndex, offsetBy: random.nextInt(below: 10))] : byte
                }
            default:
                let text = String(decoding: copy, as: UTF8.self)
                let replaced = text.replacingOccurrences(of: "\"T20\"", with: "\"T25\"")
                    .replacingOccurrences(of: "true", with: "1")
                    .replacingOccurrences(of: ":[", with: ":{\"a\":[")
                copy = Array(replaced.utf8)
            }
            result.append(Data(copy))
        }
        return result
    }

    @Test func corruptedBlobs_neverTrap_andNeverBlockTheLaunch() throws {
        var random = SeededRandom(seed: 404)
        let valid = DartUI.AppStorage(store: InMemoryStore())
        var settings = AppSettings()
        settings.inputMode = .camera
        valid.save(settings)
        valid.save(roster: testPlayers(3))
        valid.save(SetupMemory(playerIDs: testPlayers(2).map(\.id), options: ["lives": 3]), for: .killer)
        valid.saveCurrentMatch(try liveRecord(seed: 99, startedAt: Date(timeIntervalSinceReferenceDate: 12)))
        let keys = [StorageKey.settings, StorageKey.roster, StorageKey.setup(.killer), StorageKey.currentMatch, StorageKey.calibrations]
        for key in keys {
            let original = valid.store.data(forKey: key) ?? Data("[]".utf8)
            for blob in corruptions(of: original, random: &random) {
                let environment = AppEnvironment.preview()
                for other in keys where other != key {
                    environment.store.set(valid.store.data(forKey: other), forKey: other)
                }
                environment.store.set(blob, forKey: key)
                let app = AppModel(environment: environment)
                _ = app.storage.loadSettings()
                _ = app.storage.loadRoster()
                _ = app.storage.loadSetup(for: .killer)
                _ = app.storage.loadCalibration(cameraID: "fake", rotationDegrees: 0, imageSize: PixelSize(width: 1, height: 1))
                if app.resumableMatch != nil {
                    app.resumeSavedGame()
                    #expect(app.game != nil)
                }
            }
        }
    }
}
