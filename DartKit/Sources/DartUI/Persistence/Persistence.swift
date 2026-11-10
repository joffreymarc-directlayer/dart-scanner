import Foundation
import DartCore
import DartAudio
import DartVision

/// Smallest possible storage seam: named blobs. JSON goes in, JSON comes out.
public protocol KeyValueStoring: Sendable {
    func data(forKey key: String) -> Data?
    func set(_ data: Data?, forKey key: String)
}

/// `UserDefaults.standard` (or a suite).
public struct UserDefaultsStore: KeyValueStoring, @unchecked Sendable {
    private let defaults: UserDefaults

    public init(suiteName: String? = nil) {
        // A suite that cannot be opened (the name of the main bundle, the global domain) falls back to `standard`.
        defaults = suiteName.flatMap { UserDefaults(suiteName: $0) } ?? .standard
    }

    public func data(forKey key: String) -> Data? {
        defaults.data(forKey: key)
    }

    public func set(_ data: Data?, forKey key: String) {
        if let data {
            defaults.set(data, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }
}

/// Volatile store for tests, previews and SnapshotTool.
public final class InMemoryStore: KeyValueStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Data]

    public init(_ initial: [String: Data] = [:]) {
        values = initial
    }

    public func data(forKey key: String) -> Data? {
        lock.lock()
        defer { lock.unlock() }
        return values[key]
    }

    public func set(_ data: Data?, forKey key: String) {
        lock.lock()
        defer { lock.unlock() }
        values[key] = data
    }
}

/// How darts enter the game by default.
enum InputMode: String, Codable, Sendable {
    case camera, manual
}

/// Camera mode (settings screen: "En direct" / "Photo").
enum ScanMode: String, Codable, Sendable {
    /// Automatic trigger on live video.
    case live
    /// One manual capture per turn ("Scanner la volée").
    case photo
}

/// Everything the settings screen edits. Stored under `StorageKey.settings`.
struct AppSettings: Hashable, Codable, Sendable {
    var audio = AudioSettings()
    var inputMode: InputMode = .manual
    var scanMode: ScanMode = .live
    /// Nil follows the system language.
    var language: AppLanguage?
    /// false (default): only the button ends a turn. true: an empty board detected by the camera ends a turn that is
    /// already closed, when no dart waits for an answer (GAMES.md §2.4, ARCHITECTURE.md §8.6).
    var endsTurnOnTakeout: Bool = false
}

/// A calibration as it is saved: valid for one camera, one rotation and one image size (VISION.md §4.10).
struct StoredCalibration: Hashable, Codable, Sendable {
    var cameraID: String
    var calibration: BoardCalibration
    /// Carries the shadow bound measured by the one-dart check.
    var configuration: VisionConfiguration
    var lightingCheckPassed: Bool
}

/// Last choices of the setup screen, per game.
struct SetupMemory: Hashable, Codable, Sendable {
    var playerIDs: [UUID]
    var options: GameOptions
}

enum StorageKey {
    static let settings = "settings.v1"
    static let roster = "roster.v1"
    static let calibrations = "calibrations.v1"
    static let currentMatch = "match.current.v1"
    static func setup(_ game: GameID) -> String { "setup.\(game.rawValue).v1" }
}

/// Typed access to the store. Decoding failures return the default value: a corrupted blob never blocks the app.
struct AppStorage: Sendable {
    let store: any KeyValueStoring
    init(store: any KeyValueStoring) { self.store = store }

    func loadSettings() -> AppSettings {
        load(AppSettings.self, forKey: StorageKey.settings) ?? AppSettings()
    }

    func save(_ settings: AppSettings) {
        write(settings, forKey: StorageKey.settings)
    }

    func loadRoster() -> [Player] {
        load([Player].self, forKey: StorageKey.roster) ?? []
    }

    func save(roster: [Player]) {
        write(roster, forKey: StorageKey.roster)
    }

    func loadSetup(for game: GameID) -> SetupMemory? {
        load(SetupMemory.self, forKey: StorageKey.setup(game))
    }

    func save(_ setup: SetupMemory, for game: GameID) {
        write(setup, forKey: StorageKey.setup(game))
    }

    /// Calibration saved for this camera, rotation and image size.
    func loadCalibration(cameraID: String, rotationDegrees: Int, imageSize: PixelSize) -> StoredCalibration? {
        loadCalibrations().first {
            $0.cameraID == cameraID && $0.calibration.rotationDegrees == rotationDegrees && $0.calibration.imageSize == imageSize
        }
    }

    /// One calibration per (camera, rotation, image size): a new one replaces the one saved for the same key
    /// (ARCHITECTURE.md §8.10).
    func save(_ calibration: StoredCalibration) {
        var all = loadCalibrations().filter {
            !($0.cameraID == calibration.cameraID
              && $0.calibration.rotationDegrees == calibration.calibration.rotationDegrees
              && $0.calibration.imageSize == calibration.calibration.imageSize)
        }
        all.append(calibration)
        write(all, forKey: StorageKey.calibrations)
    }

    /// Game in progress, saved after every accepted input; nil when none.
    func loadCurrentMatch() -> MatchRecord? {
        load(MatchRecord.self, forKey: StorageKey.currentMatch)
    }

    func saveCurrentMatch(_ record: MatchRecord?) {
        guard let record else {
            store.set(nil, forKey: StorageKey.currentMatch)
            return
        }
        write(record, forKey: StorageKey.currentMatch)
    }

    // MARK: Private

    private func loadCalibrations() -> [StoredCalibration] {
        load([StoredCalibration].self, forKey: StorageKey.calibrations) ?? []
    }

    /// Nil for a missing blob and for one that does not decode.
    private func load<Value: Decodable>(_ type: Value.Type, forKey key: String) -> Value? {
        guard let data = store.data(forKey: key) else { return nil }
        let decoder = JSONDecoder()
        decoder.nonConformingFloatDecodingStrategy = .convertFromString(
            positiveInfinity: Self.positiveInfinity, negativeInfinity: Self.negativeInfinity, nan: Self.notANumber)
        return try? decoder.decode(type, from: data)
    }

    /// Plain JSON. A non-finite number (a dart position that the vision layer could not measure) is written as a
    /// string instead of failing the whole save: a game is never lost for one coordinate.
    private func write<Value: Encodable>(_ value: Value, forKey key: String) {
        let encoder = JSONEncoder()
        encoder.nonConformingFloatEncodingStrategy = .convertToString(
            positiveInfinity: Self.positiveInfinity, negativeInfinity: Self.negativeInfinity, nan: Self.notANumber)
        guard let data = try? encoder.encode(value) else { return }
        store.set(data, forKey: key)
    }

    private static let positiveInfinity = "inf"
    private static let negativeInfinity = "-inf"
    private static let notANumber = "nan"
}
