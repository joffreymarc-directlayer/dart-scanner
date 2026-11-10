import Foundation

public enum BustReason: String, Codable, Sendable {
    case belowZero, notADouble, oneLeft
}

/// Everything a game can announce, for sound, voice and animation. Part of the deterministic result of an input.
/// Case names and field order are those of the event catalogue of GAMES.md §2.10 and of each §n.8.
/// A target or sector is a number 1...20; the bull as a target is written 25.
public enum GameEvent: Hashable, Sendable {
    // Common (GAMES.md §2.10)
    /// Every accepted dart, always first.
    case dartRegistered(player: PlayerIndex, hit: Hit)
    /// The dart changed no game value (MISS included).
    case noEffect(player: PlayerIndex)
    /// Turn closed: third dart, bust, self-elimination or early confirmation.
    case turnCompleted(player: PlayerIndex)
    case roundStarted(round: Int)
    /// A turn begins, after `endTurn`.
    case turnStarted(player: PlayerIndex, round: Int)
    case playerEliminated(player: PlayerIndex, by: PlayerIndex)
    /// Always last.
    case gameFinished(reason: FinishReason)

    // Raw-points games (x01, highScore, moonLanding, beerTap), when a turn closes without a bust.
    // radar also emits `turnScored` at every turn close, but never `oneEighty` nor `highTurn`.
    case turnScored(player: PlayerIndex, points: Int)
    case oneEighty(player: PlayerIndex)
    /// Turn total between 100 and 179.
    case highTurn(player: PlayerIndex, points: Int)

    // x01, moonLanding
    case bust(player: PlayerIndex, reason: BustReason)
    case doubleInOpened(player: PlayerIndex)
    case doubleInRequired(player: PlayerIndex)
    /// Winning dart of X01; `points` is the total of the winning turn, `darts` its number of darts.
    case checkout(player: PlayerIndex, points: Int, darts: Int)
    case landed(player: PlayerIndex)

    // cricket
    case marksScored(player: PlayerIndex, target: Int, count: Int)
    case targetClosed(player: PlayerIndex, target: Int)
    case targetDead(target: Int)
    case pointsScored(player: PlayerIndex, points: Int)
    case pointsGiven(player: PlayerIndex, to: [PlayerIndex], pointsEach: Int)

    // killer
    case armingHit(player: PlayerIndex, progress: Int)
    case becameKiller(player: PlayerIndex)
    case lifeLost(player: PlayerIndex, by: PlayerIndex, livesLeft: Int)
    case zoneChanged(player: PlayerIndex, zone: [Int])

    // aroundTheClock
    case targetHit(player: PlayerIndex, number: Int, advancedBy: Int)

    // shanghai, halveIt
    case targetScored(player: PlayerIndex, points: Int)
    case neighbourHit(player: PlayerIndex, points: Int)
    case shanghai(player: PlayerIndex)
    /// `points` is the new total.
    case halved(player: PlayerIndex, points: Int)

    // fight
    case damaged(player: PlayerIndex, by: PlayerIndex, amount: Int, livesLeft: Int)
    case healed(player: PlayerIndex, amount: Int, lives: Int)
    case healWasted(player: PlayerIndex)

    // conqueror
    case sectorClaimed(player: PlayerIndex, sector: Int)
    case sectorStrengthened(player: PlayerIndex, sector: Int, lives: Int)
    case sectorDamaged(player: PlayerIndex, sector: Int, livesLeft: Int)
    case sectorConquered(player: PlayerIndex, sector: Int, from: PlayerIndex)
    case kingOfTheHill(player: PlayerIndex)

    // beerTap
    /// One dart filled `count` glasses; `glasses` is the new number of full glasses.
    case glassFilled(player: PlayerIndex, count: Int, glasses: Int)
    /// Free glass at the close of a turn of 100 points or more; `glasses` is the new number of full glasses.
    case bonusGlass(player: PlayerIndex, glasses: Int)

    // football
    /// `by` is the requested move, signed (positive = towards the right); `ball` is the position after clamping.
    case ballMoved(player: PlayerIndex, by: Int, ball: Int)
    /// `side` is the side credited (0 = A, 1 = B), `goals` its new total; `ownGoal` when `player` is on the other side.
    case goalScored(player: PlayerIndex, side: Int, goals: Int, ownGoal: Bool)

    // radar
    /// `blob` is the slot 0...4, `points` the points gained.
    case blobDamaged(player: PlayerIndex, blob: Int, points: Int, hitPointsLeft: Int)
    /// `points` is the hit value plus the destruction bonus.
    case blobDestroyed(player: PlayerIndex, blob: Int, points: Int)
    /// Moving targets: emitted by `turnStarted`, just before the kernel's `turnStarted` event.
    case blobsMoved

    // golf
    /// Every dart; `strokes` is its value (1, 2, 3 or 5).
    case shotPlayed(player: PlayerIndex, strokes: Int)
    /// Turn close; `strokes` is the score of the hole, `total` the player's new total.
    case holeCompleted(player: PlayerIndex, hole: Int, strokes: Int, total: Int)
    case holeInOne(player: PlayerIndex, hole: Int)
}
