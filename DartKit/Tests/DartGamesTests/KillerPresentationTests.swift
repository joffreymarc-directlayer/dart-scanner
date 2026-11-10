import Testing
import DartCore
import DartGames
import DartTestSupport

/// What Killer shows (GAMES.md §5.7, ARCHITECTURE.md §5.5 and §5.6): the highlights each player must see (own
/// zone, armed state, targets), the scoreboard rows, the dart captions and the results.
@Suite struct KillerPresentationTests {
    private let registry = GameRegistry.standard

    private func sectors(_ numbers: [Int], _ role: HighlightRole, owner: PlayerIndex) -> [BoardHighlight] {
        numbers.map { BoardHighlight(zone: .sector($0), role: role, owner: owner) }
    }

    /// Easy game of three with seed 1: J1 [8, 11, 14], J2 [6, 10, 15], J3 [20, 1, 18].
    private func easyTrio(_ options: GameOptions = [:]) throws -> GameMatch {
        let match = try registry.match(.killer, options, players: 3, seed: 1)
        #expect(match.killerZones == [[8, 11, 14], [6, 10, 15], [20, 1, 18]])
        return match
    }

    /// Hard game of three with seed 2: J1 [3], J2 [12], J3 [18].
    private func hardTrio(_ options: [String: OptionValue]) throws -> GameMatch {
        var values = options
        values["level"] = "hard"
        let match = try registry.match(.killer, GameOptions(values), players: 3, seed: 2)
        #expect(match.killerZones == [[3], [12], [18]])
        return match
    }

    private func captions(_ match: GameMatch) -> [DartCaption?] {
        match.snapshot.turn.darts.map(\.caption)
    }

    // MARK: Highlights (GAMES.md §5.7)

    @Test func highlights_notArmed_ownZoneIsTheTarget_opponentsAreShownButNotAttackable() throws {
        var match = try easyTrio()
        #expect(match.snapshot.highlights == sectors([8, 11, 14], .target, owner: 0)
                + sectors([6, 10, 15], .opponent, owner: 1) + sectors([20, 1, 18], .opponent, owner: 2))
        // Two arming hits out of three: still not a Killer, the picture is the same, also once the turn is closed.
        match.play("S8, S11, MISS")
        #expect(match.phase == .turnComplete)
        #expect(match.snapshot.highlights == sectors([8, 11, 14], .target, owner: 0)
                + sectors([6, 10, 15], .opponent, owner: 1) + sectors([20, 1, 18], .opponent, owner: 2))
        // The highlights are always those of the current player.
        match.endTurn()
        #expect(match.snapshot.highlights == sectors([8, 11, 14], .opponent, owner: 0)
                + sectors([6, 10, 15], .target, owner: 1) + sectors([20, 1, 18], .opponent, owner: 2))
        match.endTurn()
        #expect(match.snapshot.highlights == sectors([8, 11, 14], .opponent, owner: 0)
                + sectors([6, 10, 15], .opponent, owner: 1) + sectors([20, 1, 18], .target, owner: 2))
    }

    @Test func highlights_armed_ownZoneIsOwn_everyOpponentAliveIsATarget() throws {
        var match = try easyTrio(["armingHits": 2])
        match.play("S8")
        #expect(match.snapshot.highlights.first == BoardHighlight(zone: .sector(8), role: .target, owner: 0))
        // The second arming hit makes J1 a Killer at once: the highlights switch in the middle of the turn.
        match.play("D14")
        #expect(match.phase == .throwing)
        let armed = sectors([8, 11, 14], .own, owner: 0) + sectors([6, 10, 15], .target, owner: 1)
            + sectors([20, 1, 18], .target, owner: 2)
        #expect(match.snapshot.highlights == armed)
        match.play("MISS")
        #expect(match.phase == .turnComplete && match.snapshot.highlights == armed)
        // J2 is not armed: J1's zone, although a Killer's, is only shown.
        match.endTurn()
        #expect(match.snapshot.highlights == sectors([8, 11, 14], .opponent, owner: 0)
                + sectors([6, 10, 15], .target, owner: 1) + sectors([20, 1, 18], .opponent, owner: 2))
        // Back to J1, still a Killer.
        match.play("| |")
        #expect(match.snapshot.currentPlayer == 0 && match.snapshot.highlights == armed)
    }

    @Test func highlights_armedWithSelfHitPenalty_ownZoneIsToAvoid() throws {
        var match = try easyTrio(["armingHits": 1, "selfHitPenalty": true])
        // Before being a Killer the own zone is a target, penalty or not.
        #expect(match.snapshot.highlights.prefix(3) == sectors([8, 11, 14], .target, owner: 0)[...])
        match.play("T11")
        #expect(match.snapshot.highlights == sectors([8, 11, 14], .avoid, owner: 0)
                + sectors([6, 10, 15], .target, owner: 1) + sectors([20, 1, 18], .target, owner: 2))
    }

    @Test func highlights_eliminatedPlayersHaveNone_andNothingOnceFinished() throws {
        var match = try hardTrio(["lives": 1, "armingHits": 1])
        match.play("S3, S12")
        #expect(match.killerAlive == [0, 2])
        #expect(match.snapshot.highlights == sectors([3], .own, owner: 0) + sectors([18], .target, owner: 2))
        match.play("| MISS")
        // J3's view: the 12 of the eliminated player is not drawn either.
        #expect(match.snapshot.highlights == sectors([3], .opponent, owner: 0) + sectors([18], .target, owner: 2))
        match.play("| S18")
        #expect(match.phase == .finished && match.snapshot.highlights.isEmpty)
    }

    @Test func highlights_currentPlayerWhoEliminatedThemselves_hasNoZoneAndNoTarget() throws {
        var match = try hardTrio(["lives": 1, "armingHits": 1, "selfHitPenalty": true])
        match.play("S3")
        #expect(match.snapshot.highlights == sectors([3], .avoid, owner: 0) + sectors([12], .target, owner: 1)
                + sectors([18], .target, owner: 2))
        match.play("S3")
        #expect(match.phase == .turnComplete && match.snapshot.currentPlayer == 0 && match.snapshot.players[0].isEliminated)
        #expect(match.snapshot.highlights == sectors([12], .opponent, owner: 1) + sectors([18], .opponent, owner: 2))
        #expect(match.snapshot.turn.hint == nil)
    }

    @Test func highlights_expert_followTheRedraw() throws {
        var match = try registry.match(.killer, ["level": "expert"], players: 3, seed: 7)
        #expect(match.snapshot.highlights == sectors([14], .target, owner: 0) + sectors([15], .opponent, owner: 1)
                + sectors([4], .opponent, owner: 2))
        match.play("| | |")
        // J1 moved from the 14 to the 16: the 14 is a free number again.
        #expect(match.snapshot.highlights == sectors([16], .target, owner: 0) + sectors([15], .opponent, owner: 1)
                + sectors([4], .opponent, owner: 2))
        #expect(match.snapshot.players[0].detail == LocalizedText(verbatim: "16"))
    }

    /// Every level, every number of players: each player in turn sees their own zone as the target, then, once
    /// armed, every opponent alive as a target and their own zone as `own`.
    @Test(arguments: ["easy", "medium", "hard", "expert"])
    func highlights_everyPlayerInTurn_seesOwnZoneArmedStateAndTargets(level: String) throws {
        let width = ["easy": 3, "medium": 2][level] ?? 1
        for players in 2...(level == "easy" ? 6 : 8) {
            var match = try registry.match(.killer, ["level": .string(level), "armingHits": 1], players: players, seed: 8)
            for current in 0..<players {
                #expect(match.snapshot.currentPlayer == current)
                let zones = match.killerZones
                for armed in [false, true] {
                    let highlights = match.snapshot.highlights
                    #expect(highlights.count == players * width)
                    for player in 0..<players {
                        let mine = highlights.filter { $0.owner == player }
                        #expect(mine.map(\.zone) == zones[player].map { BoardZone.sector($0) })
                        let role: HighlightRole = player == current ? (armed ? .own : .target) : (armed ? .target : .opponent)
                        #expect(mine.allSatisfy { $0.role == role }, "\(level), \(players) players, J\(current + 1) sees J\(player + 1)")
                        #expect(mine.allSatisfy { $0.label == nil && $0.strength == nil && $0.marker == nil })
                    }
                    if !armed { match.killerThrow(at: current, number: width - 1) }
                }
                #expect(match.fact(current, "isKiller") == true)
                match.endTurn()
            }
        }
    }

    // MARK: Scoreboard rows (ARCHITECTURE.md §5.5, §5.6)

    @Test func scoreboard_titleVariantAndRows() throws {
        var match = try easyTrio()
        #expect(match.snapshot.title == LocalizedText(verbatim: "Killer"))
        #expect(match.snapshot.variant == LocalizedText(fr: "Facile", en: "Easy"))
        #expect(match.snapshot.gameID == .killer && match.snapshot.winnerTitle == nil && match.snapshot.grid == nil)
        #expect(match.snapshot.facts.isEmpty)

        let row = match.snapshot.players[1]
        #expect(row.player == 1 && row.rank == 1 && !row.isEliminated)
        #expect(row.primary == ScoreValue(3, unit: LocalizedText(fr: "vies", en: "lives")))
        #expect(row.detail == LocalizedText(verbatim: "6 · 10 · 15"))
        #expect(row.badges.isEmpty)
        #expect(row.meter == Meter(value: 0, maximum: 3, style: .pips))
        #expect(row.facts == ["zone": [6, 10, 15], "lives": 3, "armingProgress": 0, "kills": 0, "isKiller": false,
                              "eliminated": false])

        // KIL-2 up to the elimination of J2.
        match.play("S8, T14, S6 | S11, DB, S20 | S19, MISS, S20 | D11")
        #expect(match.snapshot.players[0].meter == nil)
        #expect(match.snapshot.players[0].badges == [Badge(LocalizedText(verbatim: "Killer"), tone: .accent)])
        #expect(match.snapshot.players[2].meter == Meter(value: 1, maximum: 3, style: .pips))
        match.play("S10, S15")
        #expect(match.snapshot.players[1].primary == ScoreValue(1, unit: LocalizedText(fr: "vie", en: "life")))
        match.play("| S6, S6, S6 | MISS ×3 | S6")
        let dead = match.snapshot.players[1]
        #expect(dead.isEliminated && dead.rank == 3)
        #expect(dead.primary == ScoreValue(0, unit: LocalizedText(fr: "vie", en: "lives")))
        // Eliminated: one badge says it; the zone stays written, it is just inert.
        #expect(dead.badges == [Badge(LocalizedText(fr: "Éliminé", en: "Out"), tone: .negative)])
        #expect(dead.detail == LocalizedText(verbatim: "6 · 10 · 15"))
        #expect(dead.facts == ["zone": [6, 10, 15], "lives": 0, "armingProgress": 3, "kills": 0, "isKiller": true,
                               "eliminated": true])
        #expect(match.snapshot.players[0].facts["kills"] == 1 && match.snapshot.players[0].rank == 1)
    }

    @Test func variant_isTheNameOfTheLevelOnTheSetupScreen() throws {
        guard case .choice(let choices)? = KillerRules.descriptor.option("level")?.kind else {
            Issue.record("level is not a choice")
            return
        }
        #expect(choices.count == 4)
        for choice in choices {
            let match = try registry.match(.killer, ["level": choice.value], players: 2, seed: 1)
            #expect(match.snapshot.variant == choice.label)
        }
    }

    // MARK: Dart captions and hint

    @Test func captions_sayTheEffectOfEachDart() throws {
        var match = try registry.match(.killer, ["level": "hard"], players: 2, seed: 1)
        #expect(captions(match).isEmpty)
        match.play("S11, S6, MISS")
        let nothing = DartCaption(LocalizedText(fr: "Sans effet", en: "No effect"), tone: .neutral)
        #expect(captions(match) == [DartCaption(LocalizedText(fr: "Armement 1/3", en: "Arming 1/3"), tone: .positive), nothing, nothing])
        match.play("| MISS | D11, T11, S6")
        #expect(captions(match) == [DartCaption(LocalizedText(fr: "Armement 2/3", en: "Arming 2/3"), tone: .positive),
                                    DartCaption(LocalizedText(fr: "Killer !", en: "Killer!"), tone: .accent),
                                    DartCaption(LocalizedText(fr: "J2 −1 vie", en: "J2 −1 life"), tone: .positive)])
        // A new turn starts with no caption.
        match.play("|")
        #expect(captions(match).isEmpty)
        match.play("MISS | S6, S6")
        #expect(captions(match)[1] == DartCaption(LocalizedText(fr: "J2 éliminé", en: "J2 out"), tone: .positive))
        #expect(match.phase == .finished)
    }

    @Test func captions_selfHitPenalty() throws {
        var match = try hardTrio(["lives": 2, "armingHits": 1, "selfHitPenalty": true])
        match.play("S3, S3")
        #expect(captions(match)[1] == DartCaption(LocalizedText(fr: "−1 vie", en: "−1 life"), tone: .negative))
        match.play("S3")
        #expect(captions(match)[2] == DartCaption(LocalizedText(fr: "Éliminé", en: "Out"), tone: .negative))
    }

    @Test func hint_saysWhatToAimAt() throws {
        var match = try registry.match(.killer, ["level": "hard", "armingHits": 2], players: 2, seed: 1)
        #expect(match.snapshot.turn.hint == LocalizedText(fr: "Encore 2 touches sur votre zone", en: "2 more hits on your zone"))
        match.play("S11")
        #expect(match.snapshot.turn.hint == LocalizedText(fr: "Encore 1 touche sur votre zone", en: "1 more hit on your zone"))
        match.play("S11")
        #expect(match.snapshot.turn.hint == LocalizedText(fr: "Visez les zones des autres", en: "Aim at the other zones"))
        var penalty = try registry.match(.killer, ["level": "hard", "armingHits": 1, "selfHitPenalty": true], players: 2, seed: 1)
        penalty.play("S11")
        #expect(penalty.snapshot.turn.hint == LocalizedText(fr: "Visez les autres zones, évitez la vôtre",
                                                            en: "Aim at the other zones, avoid your own"))
    }

    /// After a game ended at the round limit the kernel's volley is empty while the rule's per-turn state is still
    /// that of the last turn (ARCHITECTURE.md §4.7): the snapshot has no dart, no caption, and undo restores both.
    @Test func roundLimitFinish_emptyVolley_thenUndoRestoresTheCaptions() throws {
        var match = try registry.match(.killer, ["level": "hard", "maxRounds": 1], players: 2, seed: 1)
        match.play("S11, S11, MISS | S6, MISS, MISS")
        let closing = captions(match)
        #expect(closing.count == 3 && closing[0] == DartCaption(LocalizedText(fr: "Armement 1/3", en: "Arming 1/3"), tone: .positive))
        #expect(match.snapshot.outcome == nil)
        match.endTurn()
        #expect(match.phase == .finished && match.snapshot.finishReason == .roundLimit)
        #expect(match.snapshot.turn.darts.isEmpty && match.currentTurn.isEmpty && match.snapshot.highlights.isEmpty)
        #expect(match.snapshot.turn.hint == nil)
        #expect(match.snapshot.outcome == LocalizedText(fr: "Vainqueur à la limite de manches, avec 3 vies restantes.",
                                                        en: "Winner at the round limit, with 3 lives left."))
        #expect(match.snapshot.ranks == [1, 2])
        match.undo()
        #expect(match.phase == .turnComplete && captions(match) == closing)
    }

    // MARK: Results (ARCHITECTURE.md §5.6)

    @Test func results_lastPlayerStanding() throws {
        var match = try easyTrio()
        match.play("S8, T14, S6 | S11, DB, S20 | S19, MISS, S20 | D11, S10, S15 | S6, S6, S6 | MISS ×3 | S6, S14, S1 |")
        // While the game runs the kernel keeps the results sentence back.
        #expect(match.snapshot.outcome == nil)
        match.play("S10, S18, S18 | T20, S1")
        #expect(match.phase == .finished)
        #expect(match.snapshot.outcome == LocalizedText(fr: "Dernier joueur en vie, avec 3 vies restantes.",
                                                        en: "Last player alive, with 3 lives left."))
        #expect(match.snapshot.players[0].resultLines == [LocalizedText(fr: "2 éliminations", en: "2 eliminations"),
                                                          LocalizedText(fr: "3 vies", en: "3 lives")])
        #expect(match.snapshot.players[1].resultLines == [LocalizedText(fr: "Devenu Killer manche 2", en: "Became a Killer in round 2"),
                                                          LocalizedText(fr: "Éliminé manche 3", en: "Out in round 3")])
        #expect(match.snapshot.players[2].resultLines == [LocalizedText(fr: "Devenu Killer manche 3", en: "Became a Killer in round 3"),
                                                          LocalizedText(fr: "Éliminé manche 4", en: "Out in round 4")])
        #expect(match.snapshot.winnerTitle == nil)
    }

    @Test func results_oneLifeLeft_oneKill_neverKiller() throws {
        var match = try hardTrio(["lives": 2, "armingHits": 1, "selfHitPenalty": true])
        // J1 arms, takes a life from himself and one from J2; one round later he eliminates J2, then J3.
        match.play("S3, S3, S12 | MISS | MISS | S12, S18, S18")
        #expect(match.phase == .finished && match.snapshot.ranks == [1, 3, 2])
        #expect(match.snapshot.outcome == LocalizedText(fr: "Dernier joueur en vie, avec 1 vie restante.",
                                                        en: "Last player alive, with 1 life left."))
        #expect(match.snapshot.players[0].resultLines == [LocalizedText(fr: "2 éliminations", en: "2 eliminations"),
                                                          LocalizedText(fr: "1 vie", en: "1 life")])
        #expect(match.snapshot.players[1].resultLines == [LocalizedText(fr: "Jamais Killer", en: "Never a Killer"),
                                                          LocalizedText(fr: "Éliminé manche 2", en: "Out in round 2")])
    }

    @Test func results_roundLimit_tie() throws {
        var match = try registry.match(.killer, ["level": "hard", "maxRounds": 1], players: 2, seed: 1)
        match.play("S11 | S6 |")
        #expect(match.phase == .finished && match.snapshot.ranks == [1, 1])
        #expect(match.snapshot.outcome == LocalizedText(fr: "Égalité à la limite de manches, avec 3 vies restantes chacun.",
                                                        en: "Tie at the round limit, with 3 lives left each."))
        var one = try registry.match(.killer, ["level": "hard", "maxRounds": 1, "armingHits": 1], players: 2, seed: 1)
        one.play("S11, S6 | S6 |")
        #expect(one.snapshot.ranks == [1, 2])
        #expect(one.snapshot.players[0].resultLines == [LocalizedText(fr: "Devenu Killer manche 1", en: "Became a Killer in round 1"),
                                                        LocalizedText(fr: "3 vies", en: "3 lives")])
        #expect(one.snapshot.players[1].resultLines.last == LocalizedText(fr: "2 vies", en: "2 lives"))
    }
}
