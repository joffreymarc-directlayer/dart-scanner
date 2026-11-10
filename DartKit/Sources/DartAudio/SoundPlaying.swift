// DartAudio — the sound service seen by DartUI, and its silent stand-in (ARCHITECTURE.md §7.2).
import Foundation
import DartCore

/// The sound service seen by DartUI. Main-actor API; never blocks, never throws: a sound that cannot be played is skipped.
@MainActor
public protocol SoundPlaying: AnyObject {
    /// Applied immediately (session category, volumes, voice).
    var settings: AudioSettings { get set }
    /// True on devices with a Taptic Engine (iPhone). The settings screen disables the haptics row otherwise.
    var supportsHaptics: Bool { get }
    /// Configures the audio session, builds the engine and its buffers, pre-warms the voice. Idempotent.
    func prepare()
    /// Plays a batch: effects and haptics at their `delay`, announcements by priority.
    func play(_ cues: [AudioCue])
    /// Stops every sound and the voice.
    func stopAll()
    /// false when the app leaves the foreground (engine paused), true when it comes back.
    func setActive(_ active: Bool)
}

extension SoundPlaying {
    public func play(_ effect: SoundEffect) { play([AudioCue(effect: effect)]) }
    public func say(_ text: LocalizedText, priority: Announcement.Priority = .normal) {
        play([AudioCue(announcement: Announcement(text, priority: priority))])
    }
}

/// Plays nothing and remembers what it was asked: tests, previews, SnapshotTool.
@MainActor
public final class SilentSoundPlayer: SoundPlaying {
    public var settings: AudioSettings
    public var supportsHaptics: Bool
    public private(set) var played: [AudioCue] = []
    public init(settings: AudioSettings = AudioSettings(), supportsHaptics: Bool = false) {
        self.settings = settings
        self.supportsHaptics = supportsHaptics
    }
    public func prepare() {}
    public func play(_ cues: [AudioCue]) { played += cues }
    public func stopAll() {}
    public func setActive(_ active: Bool) {}
}
