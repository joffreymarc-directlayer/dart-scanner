import DartCore

/// GAMES.md §12.7 and ARCHITECTURE.md §5.5, §5.6: scoreboard, captions, highlights and facts of Conqueror.
extension ConquerorRules {
    public func presentation(_ context: TurnContext) -> RulesPresentation {
        let rows = homeSector.indices.map { i -> PlayerRow in
            let owned = sectors(of: i)
            let total = totalLives(of: i)
            let out = isEliminated(i)
            var badges: [Badge] = []
            if king == i { badges.append(Badge(LocalizedText(fr: "Roi", en: "King"), tone: .accent)) }
            if out { badges.append(Badge(LocalizedText(fr: "Éliminé", en: "Eliminated"), tone: .negative)) }
            let count = LocalizedText.counted(owned.count, fr: ("secteur", "secteurs"), en: ("sector", "sectors"))
            return PlayerRow(
                player: i,
                primary: ScoreValue(total, unit: LocalizedText(fr: total <= 1 ? "vie" : "vies", en: total == 1 ? "life" : "lives")),
                detail: out
                    ? LocalizedText(fr: "Maison \(homeSector[i]) perdue", en: "Home \(homeSector[i]) lost")
                    : LocalizedText(fr: "\(count.fr) · maison \(homeSector[i])", en: "\(count.en) · home \(homeSector[i])"),
                badges: badges,
                isEliminated: out,
                resultLines: eliminationRound[i].map { [LocalizedText(fr: "Éliminé manche \($0)", en: "Eliminated in round \($0)")] } ?? [count],
                facts: [
                    "sectors": .map(Dictionary(uniqueKeysWithValues: owned.map { ($0, sectorLives[$0]) })),
                    "totalLives": .int(total),
                    "sectorCount": .int(owned.count),
                    "homeSector": .int(homeSector[i]),
                    "eliminated": .bool(out),
                ])
        }
        // After a finish at the round limit the volley is empty while `turnEffects` is still the last turn
        // (ARCHITECTURE.md §4.7): one caption per dart of the context, never more.
        let captions: [DartCaption?] = turnEffects.prefix(context.darts.count).map { caption(for: $0, players: context.players) }
        return RulesPresentation(
            title: Self.descriptor.name,
            variant: multipliersCount ? LocalizedText(fr: "Multiplicateurs", en: "Multipliers") : nil,
            rows: rows,
            dartCaptions: captions,
            highlights: highlights(for: context.currentPlayer),
            outcome: context.phase == .finished ? outcome() : nil,
            facts: ["king": .int(king ?? -1)])
    }

    /// GAMES.md §12.7, for the current player `player`, in ascending sector number, the bull last:
    /// - a neutral sector next to his territory: `target`;
    /// - an opponent's sector he can attack (next to his territory, or any when he is King): `target`, in the
    ///   owner's colour; one he cannot attack: `opponent`;
    /// - his own sector: `secondary` below three lives, `own` at three;
    /// - the bull: `secondary` while he is not King. It carries the King's colour and the crown whenever there is
    ///   a King; for the King himself it is `own`: his, and of no use right now.
    /// Every owned sector carries its lives (`strength`) and a home its marker.
    private func highlights(for player: PlayerIndex) -> [BoardHighlight] {
        var result: [BoardHighlight] = []
        for sector in 1...20 {
            guard let holder = owner[sector] else {
                if isAdjacent(sector, to: player) { result.append(BoardHighlight(zone: .sector(sector), role: .target)) }
                continue
            }
            let role: HighlightRole
            if holder == player {
                role = sectorLives[sector] < Self.maximumLives ? .secondary : .own
            } else {
                role = canAttack(sector, as: player) ? .target : .opponent
            }
            result.append(BoardHighlight(zone: .sector(sector), role: role, owner: holder, strength: sectorLives[sector],
                                         marker: sector == homeSector[holder] ? .home : nil))
        }
        result.append(BoardHighlight(zone: .bull, role: king == player ? .own : .secondary, owner: king,
                                     marker: king == nil ? nil : .crown))
        return result
    }

    private func caption(for effect: DartEffect, players: [Player]) -> DartCaption {
        func name(_ player: PlayerIndex) -> String {
            players.indices.contains(player) ? players[player].name : "J\(player + 1)"
        }
        switch effect {
        case .none:
            return DartCaption(LocalizedText(fr: "Sans effet", en: "No effect"))
        case .crowned:
            return DartCaption(LocalizedText(fr: "Roi !", en: "King!"), tone: .positive)
        case .strengthened(let sector):
            return DartCaption(LocalizedText(fr: "\(sector) renforcé", en: "\(sector) fortified"), tone: .positive)
        case .claimed(let sector):
            return DartCaption(LocalizedText(fr: "\(sector) revendiqué", en: "\(sector) claimed"), tone: .positive)
        case .damaged(let holder, let amount):
            return DartCaption(LocalizedText(fr: "\(name(holder)) −\(amount) \(amount <= 1 ? "vie" : "vies")",
                                             en: "\(name(holder)) −\(amount) \(amount == 1 ? "life" : "lives")"), tone: .negative)
        case .conquered(let sector):
            return DartCaption(LocalizedText(fr: "\(sector) conquis", en: "\(sector) conquered"), tone: .positive)
        case .eliminated(let holder):
            return DartCaption(LocalizedText(fr: "\(name(holder)) éliminé", en: "\(name(holder)) eliminated"), tone: .negative)
        }
    }

    /// Sentence of the results screen about the winner, or the winners on a tie at the round limit.
    private func outcome() -> LocalizedText {
        let ranks = ranks()
        let winners = ranks.indices.filter { ranks[$0] == 1 }
        guard let first = winners.first else { return LocalizedText(verbatim: "") }
        if eliminationOrder.count == homeSector.count - 1 {
            let count = LocalizedText.counted(sectors(of: first).count, fr: ("secteur", "secteurs"), en: ("sector", "sectors"))
            return LocalizedText(fr: "Dernier en jeu, maître de \(count.fr).", en: "Last one in play, holding \(count.en).")
        }
        let lives = LocalizedText.counted(totalLives(of: first), fr: ("vie", "vies"), en: ("life", "lives"))
        if winners.count > 1 {
            return LocalizedText(fr: "Égalité à la limite de manches, avec \(lives.fr).",
                                 en: "Tied at the round limit, with \(lives.en).")
        }
        return LocalizedText(fr: "En tête à la limite de manches, avec \(lives.fr).",
                             en: "Ahead at the round limit, with \(lives.en).")
    }
}
