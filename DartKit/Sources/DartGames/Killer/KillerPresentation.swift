import DartCore

/// Scoreboard, captions, highlights and results of Killer (GAMES.md §5.7, ARCHITECTURE.md §5.5 and §5.6).
/// A pure function of the state: nothing here changes the game.
extension KillerRules {
    public func presentation(_ context: TurnContext) -> RulesPresentation {
        RulesPresentation(
            title: Self.descriptor.name,
            variant: levelName,
            rows: zones.indices.map { row(for: $0) },
            // The volley is empty after a game ended at the round limit while `turnEffects` still holds the last
            // turn: never more captions than darts.
            dartCaptions: turnEffects.prefix(context.darts.count).map { caption(for: $0, in: context) },
            turnHint: hint(in: context),
            highlights: highlights(for: context.currentPlayer),
            outcome: outcome())
    }

    /// Name of the level, as on the setup screen.
    var levelName: LocalizedText {
        switch level {
        case .easy: return LocalizedText(fr: "Facile", en: "Easy")
        case .medium: return LocalizedText(fr: "Intermédiaire", en: "Medium")
        case .hard: return LocalizedText(fr: "Difficile", en: "Hard")
        case .expert: return LocalizedText(verbatim: "Expert")
        }
    }

    // MARK: Highlights (GAMES.md §5.7)

    /// What the current player must see: their own zone, whether they are armed, and their targets.
    ///
    /// | current player            | own zone | zones of the opponents alive | eliminated |
    /// |---------------------------|----------|------------------------------|------------|
    /// | not a Killer yet          | target   | opponent                     | none       |
    /// | Killer, no self-hit rule  | own      | target                       | none       |
    /// | Killer, self-hit penalty  | avoid    | target                       | none       |
    ///
    /// One highlight per sector, in player order then clockwise, each in the colour of its owner. A current
    /// player who has just eliminated themselves has no zone any more and attacks nobody: the zones of the
    /// others are shown as `opponent`.
    func highlights(for current: PlayerIndex) -> [BoardHighlight] {
        let attacks = !isEliminated(current) && isKiller(current)
        var result: [BoardHighlight] = []
        for player in zones.indices where !isEliminated(player) {
            let role: HighlightRole
            if player != current {
                role = attacks ? .target : .opponent
            } else if !attacks {
                role = .target
            } else {
                role = selfHitPenalty ? .avoid : .own
            }
            for number in zones[player] {
                result.append(BoardHighlight(zone: .sector(number), role: role, owner: player))
            }
        }
        return result
    }

    // MARK: Scoreboard

    private func row(for player: PlayerIndex) -> PlayerRow {
        let eliminated = isEliminated(player)
        let killer = isKiller(player)
        var badges: [Badge] = []
        if eliminated {
            badges.append(Badge(LocalizedText(fr: "Éliminé", en: "Out"), tone: .negative))
        } else if killer {
            badges.append(Badge(LocalizedText(verbatim: "Killer"), tone: .accent))
        }
        return PlayerRow(
            player: player,
            primary: ScoreValue(lives[player], unit: LocalizedText(fr: lives[player] <= 1 ? "vie" : "vies",
                                                                   en: lives[player] == 1 ? "life" : "lives")),
            detail: LocalizedText(verbatim: zones[player].map(String.init).joined(separator: " · ")),
            badges: badges,
            // Arming pips until the player is a Killer.
            meter: killer ? nil : Meter(value: armingProgress[player], maximum: armingHits, style: .pips),
            isEliminated: eliminated,
            resultLines: resultLines(for: player),
            facts: [
                "zone": .ints(zones[player]),
                "lives": .int(lives[player]),
                "armingProgress": .int(armingProgress[player]),
                "kills": .int(kills[player]),
                "isKiller": .bool(killer),
                "eliminated": .bool(eliminated),
            ])
    }

    /// Two lines per player on the results screen: "2 éliminations" / "Devenu Killer manche 6" / "Jamais Killer",
    /// then "2 vies" / "Éliminé manche 7".
    private func resultLines(for player: PlayerIndex) -> [LocalizedText] {
        let first: LocalizedText
        if kills[player] > 0 {
            first = .counted(kills[player], fr: (one: "élimination", other: "éliminations"),
                             en: (one: "elimination", other: "eliminations"))
        } else if let round = becameKillerInRound[player] {
            first = LocalizedText(fr: "Devenu Killer manche \(round)", en: "Became a Killer in round \(round)")
        } else {
            first = LocalizedText(fr: "Jamais Killer", en: "Never a Killer")
        }
        let second: LocalizedText
        if let round = eliminatedInRound[player] {
            second = LocalizedText(fr: "Éliminé manche \(round)", en: "Out in round \(round)")
        } else {
            second = .counted(lives[player], fr: (one: "vie", other: "vies"), en: (one: "life", other: "lives"))
        }
        return [first, second]
    }

    // MARK: Current turn

    /// The effect of a dart in three words at most: "Armement 2/3", "Tom −1 vie", "Sans effet".
    private func caption(for effect: DartEffect, in context: TurnContext) -> DartCaption {
        func name(_ player: PlayerIndex) -> String {
            context.players.indices.contains(player) ? context.players[player].name : "J\(player + 1)"
        }
        switch effect {
        case .none:
            return DartCaption(LocalizedText(fr: "Sans effet", en: "No effect"))
        case .arming(let progress):
            return DartCaption(LocalizedText(fr: "Armement \(progress)/\(armingHits)", en: "Arming \(progress)/\(armingHits)"),
                               tone: .positive)
        case .becameKiller:
            return DartCaption(LocalizedText(fr: "Killer !", en: "Killer!"), tone: .accent)
        case .lifeTaken(let victim):
            return DartCaption(LocalizedText(fr: "\(name(victim)) −1 vie", en: "\(name(victim)) −1 life"), tone: .positive)
        case .eliminated(let victim):
            return DartCaption(LocalizedText(fr: "\(name(victim)) éliminé", en: "\(name(victim)) out"), tone: .positive)
        case .ownLifeLost:
            return DartCaption(LocalizedText(fr: "−1 vie", en: "−1 life"), tone: .negative)
        case .selfEliminated:
            return DartCaption(LocalizedText(fr: "Éliminé", en: "Out"), tone: .negative)
        }
    }

    /// Advice for the next dart of the current player.
    private func hint(in context: TurnContext) -> LocalizedText? {
        let player = context.currentPlayer
        guard context.phase != .finished, !isEliminated(player) else { return nil }
        if !isKiller(player) {
            let left = armingHits - armingProgress[player]
            return LocalizedText(fr: left <= 1 ? "Encore 1 touche sur votre zone" : "Encore \(left) touches sur votre zone",
                                 en: left == 1 ? "1 more hit on your zone" : "\(left) more hits on your zone")
        }
        return selfHitPenalty
            ? LocalizedText(fr: "Visez les autres zones, évitez la vôtre", en: "Aim at the other zones, avoid your own")
            : LocalizedText(fr: "Visez les zones des autres", en: "Aim at the other zones")
    }

    // MARK: Results

    /// Sentence about the winner; the kernel only lets it out once the game is finished.
    private func outcome() -> LocalizedText? {
        let ranks = ranks()
        let winners = ranks.indices.filter { ranks[$0] == 1 }
        guard let best = winners.first else { return nil }
        let count = lives[best]
        let left = LocalizedText(fr: count <= 1 ? "\(count) vie restante" : "\(count) vies restantes",
                                 en: count == 1 ? "\(count) life left" : "\(count) lives left")
        if aliveCount <= 1 {
            return LocalizedText(fr: "Dernier joueur en vie, avec \(left.fr).", en: "Last player alive, with \(left.en).")
        }
        if winners.count == 1 {
            return LocalizedText(fr: "Vainqueur à la limite de manches, avec \(left.fr).",
                                 en: "Winner at the round limit, with \(left.en).")
        }
        return LocalizedText(fr: "Égalité à la limite de manches, avec \(left.fr) chacun.",
                             en: "Tie at the round limit, with \(left.en) each.")
    }
}
