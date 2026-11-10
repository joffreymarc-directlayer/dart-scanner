import Testing
import DartCore
import DartGames
import DartTestSupport

/// Every rule paragraph of GAMES.md §5.4 to §5.6 that the KIL vectors leave aside: the effect of a dart, lives,
/// the self-hit option, eliminations, skipped players, ranking with ties, and corrections.
@Suite struct KillerRulesTests {
    private let registry = GameRegistry.standard

    /// Hard duel with seed 1: J1 owns the 11, J2 the 6.
    private func duel(_ options: [String: OptionValue] = [:]) throws -> GameMatch {
        var values = options
        values["level"] = "hard"
        let match = try registry.match(.killer, GameOptions(values), players: 2, seed: 1)
        #expect(match.killerZones == [[11], [6]])
        return match
    }

    /// Hard game of three with seed 2: J1 owns the 3, J2 the 12, J3 the 18.
    private func trio(_ options: [String: OptionValue] = [:]) throws -> GameMatch {
        var values = options
        values["level"] = "hard"
        let match = try registry.match(.killer, GameOptions(values), players: 3, seed: 2)
        #expect(match.killerZones == [[3], [12], [18]])
        return match
    }

    private static let quick: [String: OptionValue] = ["lives": 1, "armingHits": 1]
    private static let quickPenalty: [String: OptionValue] = ["lives": 1, "armingHits": 1, "selfHitPenalty": true]

    // MARK: Effect of a dart (GAMES.md §5.4)

    @Test func multiplierIsIgnored_singleDoubleAndTrebleHaveTheSameEffect() throws {
        var match = try duel()
        // Not armed: the own zone arms, everything else does nothing. Two effects in all for the 63 hits.
        let nothing = match.effectKey(for: .miss)
        let arming = match.effectKey(for: .single(11))
        #expect(arming != nothing)
        for hit in Hit.all {
            #expect(match.effectKey(for: hit) == (hit.number == 11 ? arming : nothing), "\(hit)")
        }

        match.play("S11, D11, T11 | MISS ×3 |")
        // Armed: the opponent's zone costs them a life, whatever the bed; the own zone is inert now.
        let attack = match.effectKey(for: .single(6))
        #expect(attack != match.effectKey(for: .miss))
        for hit in Hit.all {
            #expect(match.effectKey(for: hit) == (hit.number == 6 ? attack : match.effectKey(for: .miss)), "\(hit)")
        }
        let outcomes = match.play("S6, D6")
        #expect(outcomes[0].events == [.dartRegistered(player: 0, hit: .single(6)), .lifeLost(player: 1, by: 0, livesLeft: 2)])
        #expect(outcomes[1].events == [.dartRegistered(player: 0, hit: .double(6)), .lifeLost(player: 1, by: 0, livesLeft: 1)])
    }

    @Test func effectKeys_easyLevel_oneEffectPerZone() throws {
        var match = try registry.match(.killer, ["armingHits": 1], players: 3, seed: 1)
        #expect(match.killerZones == [[8, 11, 14], [6, 10, 15], [20, 1, 18]])
        #expect(Set(Hit.all.map { match.effectKey(for: $0) }).count == 2)
        match.play("S14")
        // J1 is a Killer: one effect per opponent zone, plus "nothing" (own zone, free numbers, bull, MISS).
        let keys = Dictionary(grouping: Hit.all, by: { match.effectKey(for: $0) })
        #expect(keys.count == 3)
        #expect(keys.values.map(\.count).sorted() == [9, 9, 45])
        #expect(match.effectKey(for: .single(6)) == match.effectKey(for: .treble(15)))
        #expect(match.effectKey(for: .single(20)) == match.effectKey(for: .double(18)))
        #expect(match.effectKey(for: .single(6)) != match.effectKey(for: .single(20)))
    }

    @Test func bullMissAndFreeNumbers_neverDoAnything() throws {
        var match = try duel(Self.quick)
        for armed in [false, true] {
            #expect(match.fact(0, "isKiller") == .bool(armed))
            let before = match.snapshot.players.map(\.facts)
            for hit in [Hit.miss, .outerBull, .innerBull, .single(20), .double(5), .treble(1)] {
                var copy = match
                #expect(copy.throwDart(DartRecord(hit: hit)).events == [.dartRegistered(player: 0, hit: hit), .noEffect(player: 0)])
                #expect(copy.snapshot.players.map(\.facts) == before)
                #expect(copy.snapshot.ranks == match.snapshot.ranks)
            }
            if !armed { match.play("T11") }
        }
    }

    @Test func unarmedPlayer_cannotHurtAnyone() throws {
        var match = try duel()
        let outcomes = match.play("S11, S11, T6")
        // Two arming hits out of three: the opponent's zone still does nothing.
        #expect(outcomes[2].events == [.dartRegistered(player: 0, hit: .treble(6)), .noEffect(player: 0), .turnCompleted(player: 0)])
        #expect(match.killerInts("lives") == [3, 3] && match.killerInts("armingProgress") == [2, 0])
    }

    @Test func armingIsEffectiveAtOnce_andNeverGoesPastArmingHits() throws {
        var match = try duel(["armingHits": 2])
        let outcomes = match.play("S11, D11, S6")
        #expect(outcomes[1].events == [.dartRegistered(player: 0, hit: .double(11)), .armingHit(player: 0, progress: 2),
                                       .becameKiller(player: 0)])
        // The very next dart of the same turn already attacks.
        #expect(outcomes[2].events == [.dartRegistered(player: 0, hit: .single(6)), .lifeLost(player: 1, by: 0, livesLeft: 2),
                                       .turnCompleted(player: 0)])
        // A Killer stays one: more hits on the own zone change nothing (no penalty).
        let more = match.play("| MISS ×3 | S11, T11, D11")
        #expect(more[5].events == [.dartRegistered(player: 0, hit: .single(11)), .noEffect(player: 0)])
        #expect(more[7].events == [.dartRegistered(player: 0, hit: .double(11)), .noEffect(player: 0), .turnCompleted(player: 0)])
        #expect(match.fact(0, "armingProgress") == 2 && match.fact(0, "isKiller") == true)
        #expect(match.killerInts("lives") == [3, 2])
    }

    @Test func killer_mayAttackAnyOpponentAlive_armedOrNot() throws {
        var match = try trio(["armingHits": 1])
        // J1 arms, J2 arms, J3 does not.
        match.play("S3, MISS, MISS | S12, MISS, MISS | MISS ×3 |")
        #expect(match.killerBools("isKiller") == [true, true, false])
        let outcomes = match.play("S12, S18, S18")
        #expect(outcomes[0].events == [.dartRegistered(player: 0, hit: .single(12)), .lifeLost(player: 1, by: 0, livesLeft: 2)])
        #expect(outcomes[1].events == [.dartRegistered(player: 0, hit: .single(18)), .lifeLost(player: 2, by: 0, livesLeft: 2)])
        #expect(match.killerInts("lives") == [3, 2, 1])
    }

    @Test func lives_neverGoBelowZero_theZoneOfAnEliminatedPlayerIsInert() throws {
        var match = try trio(Self.quick)
        let outcomes = match.play("S3, S12, T12")
        #expect(outcomes[1].events == [.dartRegistered(player: 0, hit: .single(12)), .lifeLost(player: 1, by: 0, livesLeft: 0),
                                       .playerEliminated(player: 1, by: 0)])
        // Hitting the same number again does nothing: no negative lives, no second kill.
        #expect(outcomes[2].events == [.dartRegistered(player: 0, hit: .treble(12)), .noEffect(player: 0), .turnCompleted(player: 0)])
        #expect(match.killerInts("lives") == [1, 0, 1] && match.killerInts("kills") == [1, 0, 0])
        #expect(match.phase == .turnComplete)
        // The eliminated player keeps their number on the scoreboard; it is not given to anyone.
        #expect(match.killerZones == [[3], [12], [18]])
        match.killerExpectInvariants(width: 1, lives: 1, armingHits: 1)
    }

    // MARK: Eliminations and turn order (GAMES.md §5.5, §5.6, §2.4)

    @Test func twoEliminationsInOneTurn_areRankedInReverseOrder() throws {
        var match = try registry.match(.killer, ["level": "hard", "lives": 1, "armingHits": 1], players: 4, seed: 9)
        let zones = match.killerZones
        var outcomes = match.killerThrow(at: 0) + match.killerThrow(at: 2) + match.killerThrow(at: 1)
        // The elimination is immediate, in the middle of the attacker's turn, and the turn goes on.
        #expect(outcomes[1].events == [.dartRegistered(player: 0, hit: .single(zones[2][0])),
                                       .lifeLost(player: 2, by: 0, livesLeft: 0), .playerEliminated(player: 2, by: 0)])
        #expect(outcomes[2].events == [.dartRegistered(player: 0, hit: .single(zones[1][0])),
                                       .lifeLost(player: 1, by: 0, livesLeft: 0), .playerEliminated(player: 1, by: 0),
                                       .turnCompleted(player: 0)])
        #expect(match.phase == .turnComplete && match.killerAlive == [0, 3])
        #expect(match.killerInts("kills") == [2, 0, 0, 0])
        // J1 (two kills) leads J4; J2, eliminated last, is ahead of J3.
        #expect(match.snapshot.ranks == [1, 3, 4, 2])

        // J2 and J3 are skipped: J4 plays next, in the same round; then the list wraps and round 2 starts.
        #expect(match.endTurn().events == [.turnStarted(player: 3, round: 1)])
        outcomes = match.play("MISS |")
        #expect(outcomes[1].events == [.turnCompleted(player: 3), .roundStarted(round: 2), .turnStarted(player: 0, round: 2)])
        #expect(match.snapshot.currentPlayer == 0 && match.snapshot.round == 2)
        match.killerExpectInvariants(width: 1, lives: 1, armingHits: 1)
    }

    @Test func playerEliminatedBeforeTheirFirstTurn_neverPlays() throws {
        var match = try trio(Self.quick)
        match.play("S3, S12")
        #expect(match.phase == .throwing && match.killerAlive == [0, 2])
        // An early confirmation: J2 is skipped at once.
        #expect(match.endTurn().events == [.turnCompleted(player: 0), .turnStarted(player: 2, round: 1)])
        #expect(match.play("MISS ×3 |")[3].events == [.roundStarted(round: 2), .turnStarted(player: 0, round: 2)])
        #expect(match.play("MISS ×3 |")[3].events == [.turnStarted(player: 2, round: 2)])
    }

    @Test func lastPlayerStanding_endsTheGameOnTheDart_withoutTurnCompleted() throws {
        var match = try trio(Self.quick)
        let outcomes = match.play("S3, S18, S12")
        #expect(outcomes[2].events == [.dartRegistered(player: 0, hit: .single(12)), .lifeLost(player: 1, by: 0, livesLeft: 0),
                                       .playerEliminated(player: 1, by: 0), .gameFinished(reason: .lastPlayerStanding)])
        #expect(match.phase == .finished && match.snapshot.finishReason == .lastPlayerStanding)
        #expect(match.snapshot.ranks == [1, 2, 3] && match.snapshot.winners == [0])
        #expect(match.killerInts("kills") == [2, 0, 0])
        // The winning volley stays and remains correctable.
        #expect(match.turnNotation == ["S3", "S18", "S12"] && match.snapshot.turn.darts.count == 3)
        match.killerExpectInvariants(width: 1, lives: 1, armingHits: 1)
    }

    // MARK: Self-hit option (GAMES.md §5.4, §5.5)

    @Test func selfHitPenalty_off_isTheDefault() throws {
        var match = try duel(["armingHits": 1])
        let outcomes = match.play("S11, S11, D11")
        #expect(outcomes[1].events == [.dartRegistered(player: 0, hit: .single(11)), .noEffect(player: 0)])
        #expect(match.killerInts("lives") == [3, 3])
    }

    @Test func selfHitPenalty_threeLives_threeHitsOnOneself() throws {
        var match = try duel(["selfHitPenalty": true])
        var outcomes = match.play("S11, S11, S11 | MISS ×3 | S11, D11")
        // While arming there is no penalty; once a Killer, each hit on the own zone costs one life.
        #expect(match.killerInts("lives") == [1, 3] && match.fact(0, "armingProgress") == 3)
        #expect(outcomes[8].events == [.dartRegistered(player: 0, hit: .single(11)), .lifeLost(player: 0, by: 0, livesLeft: 2)])
        #expect(match.phase == .throwing)
        outcomes = match.play("T11")
        #expect(outcomes[0].events == [.dartRegistered(player: 0, hit: .treble(11)), .lifeLost(player: 0, by: 0, livesLeft: 0),
                                       .playerEliminated(player: 0, by: 0), .gameFinished(reason: .lastPlayerStanding)])
        // The winner did not throw the last dart, and nobody scored a kill.
        #expect(match.snapshot.ranks == [2, 1] && match.snapshot.winners == [1])
        #expect(match.killerInts("kills") == [0, 0])
    }

    @Test func selfHitPenalty_easyLevel_anyNumberOfTheOwnZoneCosts() throws {
        var match = try registry.match(.killer, ["armingHits": 1, "selfHitPenalty": true], players: 3, seed: 1)
        let outcomes = match.play("S8, D11, T14")
        #expect(outcomes[1].events == [.dartRegistered(player: 0, hit: .double(11)), .lifeLost(player: 0, by: 0, livesLeft: 2)])
        #expect(outcomes[2].events == [.dartRegistered(player: 0, hit: .treble(14)), .lifeLost(player: 0, by: 0, livesLeft: 1),
                                       .turnCompleted(player: 0)])
        #expect(match.killerInts("lives") == [1, 3, 3])
    }

    @Test func selfElimination_afterAKill_theSurvivorWinsWithoutThrowing() throws {
        var match = try trio(Self.quickPenalty)
        let outcomes = match.play("S3, S12, S3")
        #expect(outcomes[2].events == [.dartRegistered(player: 0, hit: .single(3)), .lifeLost(player: 0, by: 0, livesLeft: 0),
                                       .playerEliminated(player: 0, by: 0), .gameFinished(reason: .lastPlayerStanding)])
        #expect(match.phase == .finished)
        // J3 never threw a dart and wins; J1, eliminated last, is second, with the one kill of the game.
        #expect(match.snapshot.ranks == [2, 3, 1] && match.snapshot.winners == [2])
        #expect(match.killerInts("kills") == [1, 0, 0])
        match.killerExpectInvariants(width: 1, lives: 1, armingHits: 1)
    }

    @Test func selfElimination_onTheThirdDart_closesTheTurnOnce() throws {
        var match = try trio(Self.quickPenalty)
        let outcomes = match.play("MISS, S3, S3")
        #expect(outcomes[2].events == [.dartRegistered(player: 0, hit: .single(3)), .lifeLost(player: 0, by: 0, livesLeft: 0),
                                       .playerEliminated(player: 0, by: 0), .turnCompleted(player: 0)])
        #expect(match.phase == .turnComplete)
        #expect(match.endTurn().events == [.turnStarted(player: 1, round: 1)])
        // J1 is out for good: after J3 the list wraps straight to J2.
        let next = match.play("MISS | MISS |")
        #expect(next[3].events == [.turnCompleted(player: 2), .roundStarted(round: 2), .turnStarted(player: 1, round: 2)])
    }

    @Test func selfElimination_ofTheLastPlayerInOrder_startsANewRound() throws {
        var match = try trio(Self.quickPenalty)
        let outcomes = match.play("MISS | MISS | S18, S18")
        #expect(outcomes.last?.events.last == .turnCompleted(player: 2))
        #expect(match.phase == .turnComplete && match.snapshot.currentPlayer == 2 && match.killerAlive == [0, 1])
        #expect(match.throwDart(DartRecord(hit: .single(3))) == .rejected(.turnComplete))
        #expect(match.endTurn().events == [.roundStarted(round: 2), .turnStarted(player: 0, round: 2)])
        #expect(match.snapshot.ranks == [1, 1, 3])
    }

    // MARK: Ranking (GAMES.md §5.6, §2.7)

    @Test func ranking_isProvisionalDuringTheGame() throws {
        var match = try trio()
        #expect(match.snapshot.ranks == [1, 1, 1])
        match.play("MISS ×3 | S12")
        // One arming hit is enough to lead.
        #expect(match.snapshot.ranks == [2, 1, 2])
        match.play("S12, S12 | MISS ×3 | MISS ×3 | S3")
        // J2 is a Killer and hits J1: lives come first.
        #expect(match.killerInts("lives") == [2, 3, 3])
        #expect(match.snapshot.ranks == [3, 1, 2])
    }

    @Test func ranking_atTheRoundLimit_livesThenKillsThenArming_withTies() throws {
        var match = try registry.match(.killer, ["level": "hard", "maxRounds": 2], players: 5, seed: 1)
        // Round 1: J1, J2 and J3 arm; J4 and J5 do nothing.
        for player in 0..<3 {
            match.killerThrow(at: player, times: 3)
            match.endTurn()
        }
        match.play("MISS ×3 | MISS ×3 |")
        #expect(match.snapshot.round == 2 && match.snapshot.currentPlayer == 0)
        // Round 2: J1 eliminates J5; J2 hits J1 and J3; J3 hits J2; J4 does nothing.
        match.killerThrow(at: 4, times: 3)
        match.endTurn()
        match.killerThrow(at: 0)
        match.killerThrow(at: 2)
        match.play("MISS |")
        match.killerThrow(at: 1)
        match.play("MISS, MISS | MISS ×3")
        #expect(match.phase == .turnComplete && match.snapshot.currentPlayer == 3)
        #expect(match.killerInts("lives") == [2, 2, 2, 3, 0])
        #expect(match.killerInts("kills") == [1, 0, 0, 0, 0])
        #expect(match.killerInts("armingProgress") == [3, 3, 3, 0, 0])
        // J4 has the most lives; J1 has a kill; J2 and J3 are equal on every criterion; J5 is eliminated.
        #expect(match.snapshot.ranks == [2, 3, 3, 1, 5])

        #expect(match.endTurn().events == [.gameFinished(reason: .roundLimit)])
        #expect(match.snapshot.finishReason == .roundLimit && match.snapshot.ranks == [2, 3, 3, 1, 5])
        #expect(match.snapshot.winners == [3])
        match.killerExpectInvariants(width: 1, lives: 3, armingHits: 3)
    }

    @Test func ranking_atTheRoundLimit_aTieInFrontGivesSeveralWinners() throws {
        var match = try registry.match(.killer, ["level": "medium", "maxRounds": 1], players: 4, seed: 42)
        #expect(match.killerZones == [[9, 12], [16, 8], [1, 18], [17, 3]])
        // J1 and J3 score two arming hits each, J2 one, J4 none.
        match.play("S9, S12, MISS | S16, MISS, MISS | T1, D18, MISS | MISS ×3 |")
        #expect(match.phase == .finished && match.snapshot.finishReason == .roundLimit)
        #expect(match.snapshot.ranks == [1, 3, 1, 4] && match.snapshot.winners == [0, 2])
    }

    @Test func ranking_eightPlayers_eliminatedInReverseOrder() throws {
        var match = try registry.match(.killer, ["level": "hard", "lives": 1, "armingHits": 1, "maxRounds": .null],
                                       players: 8, seed: 1)
        #expect(match.killerZones == [[11], [16], [4], [5], [17], [14], [6], [7]])
        // Round 1: J1 arms, then eliminates J8 and J7.
        match.play("S11, S7, S6")
        #expect(match.snapshot.ranks == [1, 2, 2, 2, 2, 2, 7, 8])
        match.play("| MISS | MISS | MISS | MISS | MISS |")
        #expect(match.snapshot.round == 2 && match.snapshot.currentPlayer == 0)
        // Round 2: J6, J5, J4.
        match.play("S14, S17, S5")
        #expect(match.snapshot.ranks == [1, 2, 2, 4, 5, 6, 7, 8])
        match.play("| MISS | MISS |")
        // Round 3: J3, then J2: the game ends on the dart.
        match.play("S4, S16")
        #expect(match.phase == .finished && match.snapshot.finishReason == .lastPlayerStanding)
        #expect(match.snapshot.ranks == [1, 2, 3, 4, 5, 6, 7, 8])
        #expect(match.killerInts("kills") == [7, 0, 0, 0, 0, 0, 0, 0])
        #expect(match.snapshot.round == 3)
    }

    // MARK: Undo and corrections (GAMES.md §2.5)

    @Test func undo_ofTheWinningDart_reopensTheGame() throws {
        var match = try duel(Self.quick)
        match.play("S11, S6")
        #expect(match.phase == .finished)
        let finished = match.snapshot
        #expect(match.undo().applied)
        #expect(match.phase == .throwing && match.killerInts("lives") == [1, 1] && match.snapshot.finishReason == nil)
        #expect(match.killerBools("eliminated") == [false, false] && match.snapshot.ranks == [1, 2])
        match.play("S6")
        #expect(match.snapshot == finished)
        // All the way back to the start.
        while match.canUndo { match.undo() }
        #expect(try match.snapshot == duel(Self.quick).snapshot)
        #expect(!match.undo().applied)
    }

    @Test func replaceDart_canCancelAnElimination_orCauseOne() throws {
        var match = try duel(Self.quick)
        match.play("S11, S6")
        #expect(match.phase == .finished)
        // The winning dart was misread: the game reopens.
        #expect(match.replaceDart(at: 1, with: .miss).applied)
        #expect(match.phase == .throwing && match.turnNotation == ["S11", "MISS"])
        #expect(match.killerInts("lives") == [1, 1] && match.killerInts("kills") == [0, 0])
        // The first dart was not on the own zone: J1 is not armed any more.
        #expect(match.replaceDart(at: 0, with: .single(6)).applied)
        #expect(match.fact(0, "isKiller") == false && match.fact(0, "armingProgress") == 0)
        #expect(match.replaceDart(at: 0, with: .treble(11)).applied)
        match.play("S20")
        #expect(match.phase == .turnComplete && match.turnNotation == ["T11", "MISS", "S20"])

        // A correction that ends the game drops the darts that follow (replay rule).
        let edit = match.replaceDart(at: 1, with: .double(6))
        #expect(edit.applied && edit.dropped.map(\.hit) == [.single(20)])
        #expect(match.phase == .finished && match.turnNotation == ["T11", "D6"])
        #expect(match.snapshot.ranks == [1, 2])
        // Removing the winning dart reopens the turn.
        #expect(match.removeDart(at: 1).applied)
        #expect(match.phase == .throwing && match.turnNotation == ["T11"] && match.killerInts("lives") == [1, 1])
    }

    @Test func replaceDart_intoASelfElimination_closesTheTurnAndDropsTheRest() throws {
        var match = try trio(Self.quickPenalty)
        match.play("S3, MISS, S12")
        #expect(match.phase == .turnComplete && match.killerAlive == [0, 2])
        let edit = match.replaceDart(at: 1, with: .single(3))
        // J1 eliminates himself on the second dart: the third one never happened, J2 is alive again.
        #expect(edit.applied && edit.dropped.map(\.hit) == [.single(12)])
        #expect(match.phase == .turnComplete && match.turnNotation == ["S3", "S3"])
        #expect(match.killerAlive == [1, 2] && match.killerInts("kills") == [0, 0, 0])
        // And back: the correction is undone by another correction, the turn reopens.
        #expect(match.replaceDart(at: 1, with: .miss).applied)
        #expect(match.phase == .throwing && match.killerAlive == [0, 1, 2])
    }

    @Test func removeDart_shiftsTheFollowingDarts() throws {
        var match = try duel(["armingHits": 2])
        match.play("S11, S6, S11")
        // S6 came before the second arming hit: no effect.
        #expect(match.killerInts("lives") == [3, 3] && match.fact(0, "isKiller") == true)
        #expect(match.removeDart(at: 1).applied)
        #expect(match.turnNotation == ["S11", "S11"] && match.phase == .throwing)
        #expect(match.fact(0, "isKiller") == true)
        #expect(!match.removeDart(at: 2).applied)
        // The darts of a confirmed turn are locked.
        match.play("S6 |")
        #expect(!match.replaceDart(at: 0, with: .miss).applied)
        #expect(match.killerInts("lives") == [3, 2])
    }

    // MARK: Properties on random journals (ARCHITECTURE.md §12.1)

    /// Every level and every option: after each input of a random game the invariants of GAMES.md §5 hold, and
    /// two darts with the same effect key, followed by the same inputs, leave the same game.
    @Test(arguments: ["easy", "medium", "hard", "expert"])
    func randomGames_sameEffectKey_sameFuture(level: String) throws {
        let width = ["easy": 3, "medium": 2][level] ?? 1
        var setup = SeededRandom(seed: UInt64(width) &* 1_000 &+ UInt64(level.count))
        var finished = 0
        for game in 0..<12 {
            let players = 2 + setup.nextInt(below: level == "easy" ? 5 : 7)
            let lives = 1 + setup.nextInt(below: 3)
            let armingHits = 1 + setup.nextInt(below: 3)
            let options: GameOptions = [
                "level": .string(level), "lives": .int(lives), "armingHits": .int(armingHits),
                "selfHitPenalty": .bool(setup.nextInt(below: 2) == 0),
                "maxRounds": setup.nextInt(below: 3) == 0 ? .null : .int(2 + setup.nextInt(below: 6)),
            ]
            var match = try registry.match(.killer, options, players: players, seed: setup.next())
            var bot = SeededRandom(seed: setup.next())
            var inputs = 0
            while match.phase != .finished && inputs < 150 {
                inputs += 1
                if inputs % 5 == 1 {
                    KillerTestProperties.expectSameEffectKeySameFuture(match, botSeed: UInt64(game * 1_000 + inputs),
                                                                       bot: KillerTestBot.input)
                }
                #expect(match.killerApply(KillerTestBot.input(for: match, random: &bot)).isAccepted)
                match.killerExpectInvariants(width: width, lives: lives, armingHits: armingHits)
            }
            if match.phase == .finished { finished += 1 }
            // Everything is refused once the game is over, and nothing traps.
            if match.phase == .finished {
                #expect(!match.killerApply(.endTurn).isAccepted && !match.killerApply(.dart(.treble(20))).isAccepted)
            }
            KillerTestProperties.expectPositionsIgnored(from: try registry.match(.killer, options, players: players,
                                                                               seed: match.configuration.seed),
                                                        journal: match.entries)
        }
        #expect(finished >= 6)
    }
}
