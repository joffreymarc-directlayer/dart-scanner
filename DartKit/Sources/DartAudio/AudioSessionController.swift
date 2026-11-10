// DartAudio — the audio session of the application (ARCHITECTURE.md §7.4). With HapticsPlayer.swift, the only file
// of the target that contains `#if os(iOS)`: every call to an API that macOS does not have goes through here.
import Foundation
import AVFoundation

/// Keeps notification observers registered for as long as it lives.
final class AudioNotificationObservation {
    private let tokens: [any NSObjectProtocol]

    init(_ tokens: [any NSObjectProtocol] = []) {
        self.tokens = tokens
    }

    deinit {
        for token in tokens {
            NotificationCenter.default.removeObserver(token)
        }
    }
}

/// The shared `AVAudioSession` on iPhone and iPad. On other platforms there is no session to manage: the
/// functions succeed without doing anything.
///
/// `configure` and `activate` block: they are called on the private serial queue of `AudioDirector` only, never
/// on the main thread (ARCHITECTURE.md §11).
enum AudioSessionController {
    /// What happens to the session behind the application's back.
    enum Event: Hashable, Sendable {
        /// A call, an alarm: the system stopped the audio.
        case interruptionBegan
        /// The interruption is over: the session can be activated again and the engine restarted.
        case interruptionEnded
        /// The media server restarted: every audio object must be rebuilt.
        case mediaServicesWereReset
    }

    /// iOS: `synthesizer.usesApplicationAudioSession = uses`. Other platforms: does nothing.
    static func setSpeechUsesApplicationSession(_ uses: Bool, on synthesizer: AVSpeechSynthesizer) {
        #if os(iOS)
        synthesizer.usesApplicationAudioSession = uses
        #endif
    }

    /// Sets the category: `.playback` mixed with the other apps when `playsInSilentMode` (audible with the Silent
    /// switch on), `.ambient` otherwise. `.duckOthers` is never set: only the voice lowers the music (§7.5).
    /// False when the system refuses.
    static func configure(playsInSilentMode: Bool) -> Bool {
        #if os(iOS)
        do {
            if playsInSilentMode {
                try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
            } else {
                try AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default, options: [])
            }
            return true
        } catch {
            return false
        }
        #else
        return true
        #endif
    }

    /// Activates the session, just before the engine starts. False when the system refuses (a call in progress).
    static func activate() -> Bool {
        #if os(iOS)
        do {
            try AVAudioSession.sharedInstance().setActive(true)
            return true
        } catch {
            return false
        }
        #else
        return true
        #endif
    }

    /// Reports interruptions and media-server resets to `handler`, on whatever thread the system posts them:
    /// the handler only forwards the event to the audio queue. Other platforms: nothing is observed.
    static func observe(_ handler: @escaping @Sendable (Event) -> Void) -> AudioNotificationObservation {
        #if os(iOS)
        let center = NotificationCenter.default
        var tokens: [any NSObjectProtocol] = []
        if #available(iOS 27, *) {
            tokens.append(center.addObserver(forName: AVAudioSession.didBecomeInactiveNotification, object: nil, queue: nil) { _ in
                handler(.interruptionBegan)
            })
            // Short effects have nothing to resume: whatever the recommendation says, the engine is made ready again.
            tokens.append(center.addObserver(forName: AVAudioSession.resumptionRecommendationNotification, object: nil, queue: nil) { _ in
                handler(.interruptionEnded)
            })
        } else {
            tokens.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: nil) { notification in
                let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
                // At the end the session is activated again without looking at `shouldResume`.
                switch raw.flatMap(AVAudioSession.InterruptionType.init(rawValue:)) {
                case .began: handler(.interruptionBegan)
                case .ended: handler(.interruptionEnded)
                case nil: break
                @unknown default: break
                }
            })
        }
        tokens.append(center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: nil) { _ in
            handler(.mediaServicesWereReset)
        })
        return AudioNotificationObservation(tokens)
        #else
        return AudioNotificationObservation()
        #endif
    }
}
