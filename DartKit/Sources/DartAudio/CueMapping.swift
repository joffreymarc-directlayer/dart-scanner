// DartAudio — the table of ARCHITECTURE.md §7.3: the ONLY place where events become sounds.
import Foundation
import DartCore

public enum CueMapping {
    /// Cues for the events of ONE accepted input, in order (table of ARCHITECTURE.md §7.3).
    ///
    /// Shape of the result, which the tests and the player rely on:
    /// - one cue per effect, in event order, 0.12 s apart, the first at 0 s; the sentence and the haptic of an
    ///   event ride on the cue of its effect;
    /// - an event with a sentence and no effect gives a cue of its own, at the time of the effect before it;
    /// - `delay` never decreases along the list;
    /// - at most one cue carries a haptic: the strongest of the batch.
    public static func cues(for events: [GameEvent], context: CueContext) -> [AudioCue] {
        let batch = Batch(events)
        var cues: [AudioCue] = []
        /// Start of the next effect, in milliseconds. Whole milliseconds keep the delays exact (0.36, not 0.36000000000000004).
        var nextEffect = 0
        /// Start of the last effect scheduled so far.
        var lastEffect = 0
        /// Sentences that wait for "Au tour de…" (the new number of Killer expert).
        var afterTurnAnnouncement: [Announcement] = []

        for event in events {
            let row = row(for: event, batch: batch, context: context)
            let sentence = row.sentence.map { Announcement($0, priority: row.priority) }
            let spoken = row.saidAfterTurnAnnouncement ? nil : sentence
            if row.saidAfterTurnAnnouncement, let sentence { afterTurnAnnouncement.append(sentence) }

            if let effect = row.effect, row.repeats > 0 {
                for repeatIndex in 0..<row.repeats {
                    let start = nextEffect + repeatIndex * Timing.repeatSpacing
                    let isFirst = repeatIndex == 0
                    cues.append(AudioCue(effect: effect,
                                         announcement: isFirst && row.sentenceLag == 0 ? spoken : nil,
                                         haptic: isFirst ? row.haptic : nil,
                                         delay: seconds(start)))
                    lastEffect = start
                }
                nextEffect = lastEffect + Timing.effectSpacing
                if row.sentenceLag > 0, let spoken {
                    cues.append(AudioCue(announcement: spoken, delay: seconds(lastEffect + row.sentenceLag)))
                }
            } else if spoken != nil || row.haptic != nil {
                cues.append(AudioCue(announcement: spoken, haptic: row.haptic,
                                     delay: seconds(lastEffect + (spoken == nil ? 0 : row.sentenceLag))))
            }

            if case .turnStarted = event {
                for sentence in afterTurnAnnouncement {
                    cues.append(AudioCue(announcement: sentence, delay: seconds(lastEffect)))
                }
                afterTurnAnnouncement.removeAll()
            }
        }
        // No "Au tour de…" in this batch: the waiting sentences are simply said last.
        for sentence in afterTurnAnnouncement {
            cues.append(AudioCue(announcement: sentence, delay: seconds(lastEffect)))
        }
        return keepingStrongestHaptic(inPlayingOrder(cues))
    }

    public static func cues(for cue: InterfaceCue, context: CueContext) -> [AudioCue] {
        switch cue {
        case .gameStarted(let firstPlayer):
            let sentence = CallerPhrases.phrase(for: .turnStarted(player: firstPlayer, round: 1), context: context)
            return [AudioCue(effect: .turnChange, announcement: sentence.map { Announcement($0, priority: .normal) })]
        case .dartNeedsReview:
            return [AudioCue(effect: .needsReview, haptic: .light)]
        case .dartUndecided:
            return [AudioCue(effect: .needsReview,
                             announcement: Announcement(LocalizedText(fr: "À vérifier", en: "Please check"), priority: .normal),
                             haptic: .warning)]
        case .dartIgnored:
            return [AudioCue(effect: .rejected, haptic: .warning)]
        case .possibleMiss, .boardCleared:
            return [AudioCue(haptic: .light)]
        case .undo:
            return [AudioCue(effect: .tick, haptic: .light)]
        case .correctionApplied:
            return [AudioCue(effect: .confirm, haptic: .light)]
        case .shutter:
            return [AudioCue(effect: .shutter, haptic: .medium)]
        case .calibrationValidated:
            return [AudioCue(effect: .confirm, haptic: .success)]
        case .calibrationLost:
            return [AudioCue(effect: .alert,
                             announcement: Announcement(LocalizedText(fr: "Calibrage perdu", en: "Calibration lost"), priority: .high),
                             haptic: .failure)]
        case .buttonTap:
            return [AudioCue(haptic: .light)]
        }
    }

    // MARK: - The table

    /// Sequencing constants of §7.3, in milliseconds.
    private enum Timing {
        /// Between two effects of a batch.
        static let effectSpacing = 120
        /// Between two ticks of one `marksScored`.
        static let repeatSpacing = 90
        /// Between the victory effect and the sentence that names the winner.
        static let winnerLag = 600
        /// A `marksScored` never ticks more than this, whatever `count` says (a Cricket dart gives 1 to 3 marks).
        static let maximumRepeats = 9
    }

    /// What the mapping needs to know about the whole batch before it reads one event.
    private struct Batch {
        /// The dart changed nothing, or is the worst shot of Golf: it sounds hollow.
        var soundsDull = false
        var hasOneEighty = false
        var hasHoleInOne = false

        init(_ events: [GameEvent]) {
            for event in events {
                if case .noEffect = event { soundsDull = true }
                if case .doubleInRequired = event { soundsDull = true }
                if case .healWasted = event { soundsDull = true }
                if case .shotPlayed(_, strokes: 5) = event { soundsDull = true }
                if case .oneEighty = event { hasOneEighty = true }
                if case .holeInOne = event { hasHoleInOne = true }
            }
        }
    }

    /// One line of the table of §7.3.
    private struct Row: Sendable {
        var effect: SoundEffect?
        /// How many times the effect is played (`marksScored`: one tick per mark).
        var repeats = 1
        var sentence: LocalizedText?
        var priority: Announcement.Priority = .normal
        var haptic: HapticPattern?
        /// Milliseconds between the effect and the sentence (`gameFinished`).
        var sentenceLag = 0
        /// The sentence waits for the "Au tour de…" of the same batch (`zoneChanged`).
        var saidAfterTurnAnnouncement = false

        static let silent = Row()
    }

    /// The line of one event. Exhaustive, without `default`: a new `GameEvent` case does not compile until it has its line.
    private static func row(for event: GameEvent, batch: Batch, context: CueContext) -> Row {
        let sentence = CallerPhrases.phrase(for: event, context: context)
        switch event {
        case .dartRegistered(_, let hit):
            return Row(effect: hit.isMiss || batch.soundsDull ? .dartDull : .dartImpact,
                       sentence: sentence, priority: .low, haptic: .light)
        case .noEffect, .doubleInRequired, .healWasted, .shotPlayed:
            // Heard through the dart itself: see `Batch.soundsDull`.
            return .silent
        case .turnCompleted, .roundStarted, .targetDead:
            return .silent
        case .turnStarted:
            return Row(effect: .turnChange, sentence: sentence, priority: .normal)
        case .turnScored:
            // A 180 is announced by its own event.
            return Row(sentence: batch.hasOneEighty ? nil : sentence, priority: .normal)
        case .highTurn:
            return Row(effect: .highTurn, haptic: .medium)
        case .oneEighty:
            return Row(effect: .fanfare, sentence: sentence, priority: .high, haptic: .success)
        case .bust:
            return Row(effect: .bust, sentence: sentence, priority: .high, haptic: .failure)
        case .doubleInOpened:
            return Row(effect: .scoreUp)
        case .checkout, .landed:
            // The victory sound comes from `gameFinished`.
            return .silent
        case .marksScored(_, _, let count):
            return Row(effect: .tick, repeats: min(max(count, 0), Timing.maximumRepeats))
        case .targetClosed:
            return Row(effect: .lock, haptic: .medium)
        case .pointsScored, .pointsGiven, .targetScored, .neighbourHit, .targetHit:
            return Row(effect: .scoreUp)
        case .armingHit:
            return Row(effect: .tick)
        case .becameKiller:
            return Row(effect: .powerUp, sentence: sentence, priority: .normal, haptic: .medium)
        case .lifeLost, .damaged, .sectorDamaged:
            return Row(effect: .damage, haptic: .medium)
        case .healed, .sectorStrengthened:
            return Row(effect: .heal)
        case .sectorClaimed, .sectorConquered:
            return Row(effect: .claim)
        case .kingOfTheHill:
            return Row(effect: .powerUp, sentence: sentence, priority: .normal, haptic: .medium)
        case .zoneChanged:
            return Row(effect: .zoneMove, sentence: sentence, priority: .normal, saidAfterTurnAnnouncement: true)
        case .shanghai:
            return Row(effect: .fanfare, sentence: sentence, priority: .high, haptic: .success)
        case .halved:
            return Row(effect: .halved, sentence: sentence, priority: .normal, haptic: .warning)
        case .glassFilled:
            return Row(effect: .scoreUp, haptic: .medium)
        case .bonusGlass:
            return Row(effect: .powerUp, sentence: sentence, priority: .normal, haptic: .success)
        case .ballMoved:
            return Row(effect: .tick)
        case .goalScored(_, _, _, let ownGoal):
            return Row(effect: ownGoal ? .halved : .fanfare, sentence: sentence, priority: .high,
                       haptic: ownGoal ? .warning : .success)
        case .blobDamaged:
            return Row(effect: .damage, haptic: .medium)
        case .blobDestroyed:
            return Row(effect: .powerUp, haptic: .heavy)
        case .blobsMoved:
            return Row(effect: .zoneMove)
        case .holeCompleted:
            // A hole in one is announced by its own event.
            return Row(sentence: batch.hasHoleInOne ? nil : sentence, priority: .normal)
        case .holeInOne:
            return Row(effect: .fanfare, sentence: sentence, priority: .high, haptic: .success)
        case .playerEliminated:
            return Row(effect: .eliminated, sentence: sentence, priority: .high, haptic: .heavy)
        case .gameFinished:
            return Row(effect: .victory, sentence: sentence, priority: .high, haptic: .success, sentenceLag: Timing.winnerLag)
        }
    }

    // MARK: - Sequencing

    private static func seconds(_ milliseconds: Int) -> TimeInterval {
        Double(milliseconds) / 1000
    }

    /// The cues by delay, those of one instant in the order they were made. Only the winner's name, said 0.6 s
    /// after its effect, can have been made before a cue that plays earlier, and only in a batch where
    /// `gameFinished` is not the last event, which no game produces.
    private static func inPlayingOrder(_ cues: [AudioCue]) -> [AudioCue] {
        cues.enumerated()
            .sorted { $0.element.delay == $1.element.delay ? $0.offset < $1.offset : $0.element.delay < $1.element.delay }
            .map(\.element)
    }

    /// One haptic per batch: the strongest one stays where it is (the first one on a tie), the others go.
    private static func keepingStrongestHaptic(_ cues: [AudioCue]) -> [AudioCue] {
        var strongest: (index: Int, strength: Int)?
        for (index, cue) in cues.enumerated() {
            guard let haptic = cue.haptic else { continue }
            let strength = strength(of: haptic)
            if strongest.map({ strength > $0.strength }) ?? true {
                strongest = (index, strength)
            }
        }
        var result = cues
        for index in result.indices where index != strongest?.index {
            result[index].haptic = nil
        }
        // A cue that only carried a weaker haptic has nothing left to play.
        return result.filter { $0.effect != nil || $0.announcement != nil || $0.haptic != nil }
    }

    /// `failure` > `success` > `warning` > `heavy` > `medium` > `light`.
    private static func strength(of haptic: HapticPattern) -> Int {
        switch haptic {
        case .light: return 0
        case .medium: return 1
        case .heavy: return 2
        case .warning: return 3
        case .success: return 4
        case .failure: return 5
        }
    }
}
