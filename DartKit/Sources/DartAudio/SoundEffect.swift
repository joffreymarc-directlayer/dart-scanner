// DartAudio — vocabulary: every synthesised sound and every haptic of the application (ARCHITECTURE.md §7.2).
import Foundation

/// Every synthesised sound of the application. No audio file ships with the app.
public enum SoundEffect: String, CaseIterable, Codable, Sendable {
    /// A dart that scores or changes something.
    case dartImpact
    /// MISS, or a dart without any effect in the game.
    case dartDull
    /// Points gained, a glass filled.
    case scoreUp
    /// One Cricket mark, one arming hit, the football moving.
    case tick
    /// A Cricket target closed.
    case lock
    /// A player becomes Killer or King; a free glass; a Radar target destroyed.
    case powerUp
    /// A life lost, a sector damaged, a Radar target hit.
    case damage
    /// A heal, a sector strengthened.
    case heal
    /// A sector claimed or conquered.
    case claim
    /// A player is out.
    case eliminated
    /// Bust buzzer.
    case bust
    /// Halve-It division, own goal: falling tone.
    case halved
    /// Turn of 100 to 179.
    case highTurn
    /// 180, Shanghai, a goal, a hole in one.
    case fanfare
    /// Winning dart or end of game.
    case victory
    /// Next player.
    case turnChange
    /// Killer expert: the zone moved. Radar: the targets moved.
    case zoneMove
    /// A detected dart waits for the player's answer.
    case needsReview
    /// A dart was ignored (turn already complete) or an action is impossible.
    case rejected
    /// Photo or scan capture.
    case shutter
    /// Calibration validated, correction applied.
    case confirm
    /// Calibration lost, camera unavailable.
    case alert
}

public enum HapticPattern: String, CaseIterable, Codable, Sendable {
    case light, medium, heavy, success, warning, failure
}
