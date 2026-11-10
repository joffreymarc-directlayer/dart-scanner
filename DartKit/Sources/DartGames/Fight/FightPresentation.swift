import DartCore

/// GAMES.md §11.7 and ARCHITECTURE.md §5.5, §5.6: scoreboard, captions, highlights and facts of Fight.
extension FightRules {
    public func presentation(_ context: TurnContext) -> RulesPresentation {
        let p = context.currentPlayer
        let rows = lives.indices.map { i in
            PlayerRow(
                player: i,
                primary: ScoreValue(lives[i], unit: LocalizedText(fr: lives[i] <= 1 ? "vie" : "vies", en: lives[i] == 1 ? "life" : "lives")),
                detail: LocalizedText(fr: "Soin \(healNumber[i]) · Faibles \(weakNumbers[i].map(String.init).joined(separator: ", "))",
                                      en: "Heal \(healNumber[i]) · Weak \(weakNumbers[i].map(String.init).joined(separator: ", "))"),
                badges: isEliminated(i) ? [Badge(LocalizedText(fr: "K.-O.", en: "K.O."), tone: .negative)] : [],
                meter: Meter(value: lives[i], maximum: maxLives, style: .bar),
                isEliminated: isEliminated(i),
                resultLines: resultLines(for: i),
                facts: [
                    "lives": .int(lives[i]),
                    "healNumber": .int(healNumber[i]),
                    "weakNumbers": .ints(weakNumbers[i]),
                    "kills": .int(kills[i]),
                    "eliminated": .bool(isEliminated(i)),
                ])
        }
        // After a finish at the round limit the volley is empty while `turnEffects` is still the last turn
        // (ARCHITECTURE.md §4.7): one caption per dart of the context, never more.
        let captions: [DartCaption?] = turnEffects.prefix(context.darts.count).map { caption(for: $0, players: context.players) }
        return RulesPresentation(
            title: Self.descriptor.name,
            rows: rows,
            dartCaptions: captions,
            highlights: highlights(for: p),
            outcome: context.phase == .finished ? outcome() : nil)
    }

    /// GAMES.md §11.7: the heal number of the current player, and the weak spots of every living opponent in
    /// the opponent's colour. The player's own weak spots are not highlighted during his turn.
    private func highlights(for player: PlayerIndex) -> [BoardHighlight] {
        var result = [BoardHighlight(zone: .sector(healNumber[player]),
                                     role: lives[player] < maxLives ? .secondary : .own,
                                     owner: player, marker: .heal)]
        for opponent in lives.indices where opponent != player && !isEliminated(opponent) {
            for number in weakNumbers[opponent] {
                result.append(BoardHighlight(zone: .sector(number), role: .target, owner: opponent))
            }
        }
        return result
    }

    private func caption(for effect: DartEffect, players: [Player]) -> DartCaption {
        switch effect {
        case .none:
            return DartCaption(LocalizedText(fr: "Sans effet", en: "No effect"))
        case .healWasted:
            return DartCaption(LocalizedText(fr: "Soin inutile", en: "Heal wasted"))
        case .healed(let amount):
            return DartCaption(LocalizedText(fr: "+\(amount) \(amount <= 1 ? "vie" : "vies")",
                                             en: "+\(amount) \(amount == 1 ? "life" : "lives")"), tone: .positive)
        case .damaged(let victim, let amount, let knockedOut):
            let name = players.indices.contains(victim) ? players[victim].name : "J\(victim + 1)"
            if knockedOut {
                return DartCaption(LocalizedText(fr: "\(name) K.-O.", en: "\(name) K.O."), tone: .negative)
            }
            return DartCaption(LocalizedText(fr: "\(name) −\(amount) \(amount <= 1 ? "vie" : "vies")",
                                             en: "\(name) −\(amount) \(amount == 1 ? "life" : "lives")"), tone: .negative)
        }
    }

    /// At most two lines per player on the results screen: the knock-outs given, and the round of the knock-out taken.
    private func resultLines(for player: PlayerIndex) -> [LocalizedText] {
        var lines: [LocalizedText] = []
        if kills[player] > 0 {
            lines.append(LocalizedText.counted(kills[player], fr: ("K.-O.", "K.-O."), en: ("knockout", "knockouts")))
        }
        if let round = eliminationRound[player] {
            lines.append(LocalizedText(fr: "K.-O. manche \(round)", en: "Knocked out in round \(round)"))
        }
        return lines
    }

    /// Sentence of the results screen about the winner, or the winners on a tie at the round limit.
    private func outcome() -> LocalizedText {
        let ranks = ranks()
        let winners = ranks.indices.filter { ranks[$0] == 1 }
        let best = winners.first.map { lives[$0] } ?? 0
        if lives.filter({ $0 > 0 }).count == 1 {
            let left = LocalizedText.counted(best, fr: ("vie restante", "vies restantes"), en: ("life left", "lives left"))
            return LocalizedText(fr: "Dernier debout, avec \(left.fr).", en: "Last one standing, with \(left.en).")
        }
        let count = LocalizedText.counted(best, fr: ("vie", "vies"), en: ("life", "lives"))
        if winners.count > 1 {
            return LocalizedText(fr: "Égalité à la limite de manches, avec \(count.fr).",
                                 en: "Tied at the round limit, with \(count.en).")
        }
        return LocalizedText(fr: "En tête à la limite de manches, avec \(count.fr).",
                             en: "Ahead at the round limit, with \(count.en).")
    }
}
