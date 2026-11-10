import Foundation
import Testing
import DartCore

/// `GameDescriptor`, its option schema and `GameOptions` (ARCHITECTURE.md §4.4).
@Suite struct SmokeDescriptorTests {
    private static let easyNote = LocalizedText(fr: "6 joueurs maximum en Facile", en: "6 players maximum in Easy")

    /// A descriptor shaped like the Killer one (GAMES.md §5.2): a choice narrowed by the number of players, two
    /// steppers, a toggle, an optional stepper, and a choice that accepts custom values.
    private static let descriptor = GameDescriptor(
        id: GameID("smokeLevels"),
        name: LocalizedText(verbatim: "Levels"),
        shortName: LocalizedText(verbatim: "Levels"),
        summary: LocalizedText(verbatim: "Levels"),
        pitch: LocalizedText(verbatim: "Levels"),
        players: 2...8,
        options: [
            OptionDescriptor(
                key: "level", label: LocalizedText(fr: "Niveau", en: "Level"),
                kind: .choice([
                    OptionChoice("easy", label: LocalizedText(fr: "Facile", en: "Easy"), players: 2...6,
                                 unavailableNote: easyNote, illustration: .sectors(count: 3, moving: false)),
                    OptionChoice("medium", label: LocalizedText(fr: "Intermédiaire", en: "Medium")),
                    OptionChoice("hard", label: LocalizedText(fr: "Difficile", en: "Hard")),
                    OptionChoice("expert", label: LocalizedText(verbatim: "Expert")),
                ]),
                defaultValue: "easy"),
            OptionDescriptor(key: "lives", label: LocalizedText(fr: "Vies", en: "Lives"), kind: .stepper(1...9), defaultValue: 3),
            OptionDescriptor(key: "selfHitPenalty", label: LocalizedText(verbatim: "Penalty"), kind: .toggle,
                             defaultValue: false, isAdvanced: true),
            OptionDescriptor(key: "maxRounds", label: LocalizedText(verbatim: "Rounds"),
                             kind: .optionalStepper(1...99, nullLabel: LocalizedText(fr: "Sans limite", en: "No limit")),
                             defaultValue: 15, isAdvanced: true),
            OptionDescriptor(key: "rounds", label: LocalizedText(verbatim: "Rounds"),
                             kind: .choice([OptionChoice(7, label: LocalizedText(verbatim: "7")),
                                            OptionChoice(20, label: LocalizedText(verbatim: "20"))]),
                             defaultValue: 7, allowsCustomValue: true),
        ],
        playStyle: .board, origin: .dartsee, priority: 0)

    private var descriptor: GameDescriptor { Self.descriptor }

    // MARK: Defaults

    @Test func defaults_ofTheTwoBehaviourFlags() {
        #expect(descriptor.dependsOnPosition == false)
        #expect(descriptor.confirmsShortTurn == true)
        let radarLike = GameDescriptor(id: GameID("p"), name: LocalizedText(verbatim: "p"), shortName: LocalizedText(verbatim: "p"),
                                       summary: LocalizedText(verbatim: "p"), pitch: LocalizedText(verbatim: "p"),
                                       players: 1...8, options: [], playStyle: .board, origin: .dartsee, priority: 1,
                                       dependsOnPosition: true, confirmsShortTurn: false)
        #expect(radarLike.dependsOnPosition && !radarLike.confirmsShortTurn)
        #expect(radarLike.defaultOptions == GameOptions() && radarLike.id == GameID("p"))
        #expect(descriptor.options.map(\.isAdvanced) == [false, false, true, true, false])
        #expect(descriptor.options.map(\.allowsCustomValue) == [false, false, false, false, true])
        #expect(descriptor.options.map(\.id) == ["level", "lives", "selfHitPenalty", "maxRounds", "rounds"])
    }

    @Test func defaultOptions_andOptionLookup() {
        #expect(descriptor.defaultOptions == ["level": "easy", "lives": 3, "selfHitPenalty": false, "maxRounds": 15, "rounds": 7])
        #expect(descriptor.option("lives")?.kind == .stepper(1...9))
        #expect(descriptor.option("level")?.defaultValue == .string("easy"))
        #expect(descriptor.option("nope") == nil)
    }

    // MARK: normalized

    @Test func normalized_completesWithDefaults_andKeepsUnknownKeys() {
        let chosen = descriptor.normalized(["level": "hard", "maxRounds": .null, "bogus": 1])
        #expect(chosen == ["level": "hard", "lives": 3, "selfHitPenalty": false, "maxRounds": .null, "rounds": 7, "bogus": 1])
        #expect(descriptor.normalized([:]) == descriptor.defaultOptions)
        // Normalising twice changes nothing.
        #expect(descriptor.normalized(chosen) == chosen)
    }

    // MARK: validate

    @Test func validate_acceptsTheDefaultsForEveryAllowedCount() {
        for count in 2...6 {
            #expect(descriptor.validate(options: [:], playerCount: count).isEmpty)
        }
        #expect(descriptor.validate(options: ["level": "medium", "lives": 9, "selfHitPenalty": true, "maxRounds": .null, "rounds": 20],
                                    playerCount: 8).isEmpty)
        #expect(descriptor.validate(options: ["maxRounds": 1], playerCount: 2).isEmpty)
        #expect(descriptor.validate(options: ["maxRounds": 99], playerCount: 2).isEmpty)
    }

    @Test func validate_playerCountOutOfRange() {
        #expect(descriptor.validate(options: [:], playerCount: 1) == [.playerCountOutOfRange(allowed: 2...8, actual: 1)])
        #expect(descriptor.validate(options: [:], playerCount: 9) == [.playerCountOutOfRange(allowed: 2...8, actual: 9)])
        #expect(descriptor.validate(options: [:], playerCount: 0) == [.playerCountOutOfRange(allowed: 2...8, actual: 0)])
    }

    @Test func validate_choiceUnavailableForThisNumberOfPlayers() {
        #expect(descriptor.validate(options: ["level": "easy"], playerCount: 7)
                == [.choiceUnavailable(key: "level", note: Self.easyNote)])
        #expect(descriptor.validate(options: [:], playerCount: 8) == [.choiceUnavailable(key: "level", note: Self.easyNote)])
        #expect(descriptor.validate(options: ["level": "medium"], playerCount: 7).isEmpty)
        // Outside the range of the game, only the player count is reported: no second message for the choice.
        #expect(descriptor.validate(options: ["level": "easy"], playerCount: 9) == [.playerCountOutOfRange(allowed: 2...8, actual: 9)])
    }

    @Test func validate_wrongTypeOrOutOfRange() {
        func issues(_ options: GameOptions) -> [GameConfigurationError] { descriptor.validate(options: options, playerCount: 4) }
        #expect(issues(["level": "nightmare"]) == [.invalidOptionValue(key: "level")])
        #expect(issues(["level": 3]) == [.invalidOptionValue(key: "level")])
        #expect(issues(["lives": 0]) == [.invalidOptionValue(key: "lives")])
        #expect(issues(["lives": 10]) == [.invalidOptionValue(key: "lives")])
        #expect(issues(["lives": "3"]) == [.invalidOptionValue(key: "lives")])
        #expect(issues(["lives": .null]) == [.invalidOptionValue(key: "lives")])
        #expect(issues(["selfHitPenalty": 1]) == [.invalidOptionValue(key: "selfHitPenalty")])
        #expect(issues(["maxRounds": 0]) == [.invalidOptionValue(key: "maxRounds")])
        #expect(issues(["maxRounds": 100]) == [.invalidOptionValue(key: "maxRounds")])
        #expect(issues(["maxRounds": true]) == [.invalidOptionValue(key: "maxRounds")])
        // A custom value of an `allowsCustomValue` choice is left to the engine.
        #expect(issues(["rounds": 12]).isEmpty)
        #expect(issues(["rounds": "twelve"]).isEmpty)
    }

    @Test func validate_stableOrder_playerCount_thenOptionsInDescriptorOrder_thenUnknownKeysSorted() {
        let issues = descriptor.validate(options: ["zeta": 1, "maxRounds": 0, "alpha": true, "lives": 12, "level": "nope"],
                                         playerCount: 12)
        #expect(issues == [
            .playerCountOutOfRange(allowed: 2...8, actual: 12),
            .invalidOptionValue(key: "level"),
            .invalidOptionValue(key: "lives"),
            .invalidOptionValue(key: "maxRounds"),
            .unknownOption(key: "alpha"),
            .unknownOption(key: "zeta"),
        ])
    }

    // MARK: playerRange

    @Test func playerRange_isNarrowedByTheSelectedChoices() {
        #expect(descriptor.playerRange(for: [:]) == 2...6)
        #expect(descriptor.playerRange(for: ["level": "easy"]) == 2...6)
        #expect(descriptor.playerRange(for: ["level": "medium"]) == 2...8)
        #expect(descriptor.playerRange(for: ["level": "expert"]) == 2...8)
        // A value that is no listed choice does not narrow anything.
        #expect(descriptor.playerRange(for: ["level": "nope"]) == 2...8)
    }

    // MARK: adjusted

    @Test func adjusted_easyWithSevenPlayersBecomesMedium() {
        #expect(descriptor.adjusted(["level": "easy"], playerCount: 7)["level"] == .string("medium"))
        #expect(descriptor.adjusted([:], playerCount: 8)["level"] == .string("medium"))
        // Still available: untouched.
        #expect(descriptor.adjusted(["level": "easy"], playerCount: 6)["level"] == .string("easy"))
        #expect(descriptor.adjusted(["level": "expert"], playerCount: 8)["level"] == .string("expert"))
        // The other options are kept, completed with their defaults.
        #expect(descriptor.adjusted(["level": "easy", "lives": 5], playerCount: 7)
                == ["level": "medium", "lives": 5, "selfHitPenalty": false, "maxRounds": 15, "rounds": 7])
        // The result is valid for that number of players.
        #expect(descriptor.validate(options: descriptor.adjusted([:], playerCount: 7), playerCount: 7).isEmpty)
    }

    @Test func adjusted_wrapsAroundTheList_andGivesUpWhenNothingIsAvailable() {
        func descriptor(_ choices: [OptionChoice]) -> GameDescriptor {
            GameDescriptor(id: GameID("w"), name: LocalizedText(verbatim: "w"), shortName: LocalizedText(verbatim: "w"),
                           summary: LocalizedText(verbatim: "w"), pitch: LocalizedText(verbatim: "w"), players: 1...8,
                           options: [OptionDescriptor(key: "size", label: LocalizedText(verbatim: "size"),
                                                      kind: .choice(choices), defaultValue: "big")],
                           playStyle: .score, origin: .classic, priority: 2)
        }
        let wrapping = descriptor([
            OptionChoice("small", label: LocalizedText(verbatim: "small")),
            OptionChoice("medium", label: LocalizedText(verbatim: "medium"), players: 1...2),
            OptionChoice("big", label: LocalizedText(verbatim: "big"), players: 1...4),
        ])
        // "big" is the last of the list: the next available choice is found by wrapping to the first.
        #expect(wrapping.adjusted([:], playerCount: 5)["size"] == .string("small"))
        #expect(wrapping.adjusted(["size": "medium"], playerCount: 3)["size"] == .string("big"))
        #expect(wrapping.playerRange(for: ["size": "medium"]) == 1...2)
        let stuck = descriptor([OptionChoice("big", label: LocalizedText(verbatim: "big"), players: 1...4)])
        #expect(stuck.adjusted([:], playerCount: 5)["size"] == .string("big"))
    }

    // MARK: GameOptions

    @Test func gameOptions_typedAccessors_andLiterals() {
        var options: GameOptions = ["flag": true, "count": 3, "name": "easy", "none": .null,
                                    "list": .strings(["20", "D7", "BULL"])]
        #expect(options.bool("flag") == true && options.int("count") == 3 && options.string("name") == "easy")
        #expect(options.strings("list") == ["20", "D7", "BULL"])
        // Nil when the key is missing, is `.null`, or has another type.
        #expect(options.int("none") == nil && options.int("missing") == nil && options.int("name") == nil)
        #expect(options.bool("count") == nil && options.string("flag") == nil && options.strings("name") == nil)
        #expect(options["none"] == .null && options["missing"] == nil)
        options["count"] = 4
        options["flag"] = nil
        #expect(options.int("count") == 4 && options["flag"] == nil)
        // The last value wins when a literal repeats a key.
        let repeated: GameOptions = ["a": 1, "a": 2]
        #expect(repeated.int("a") == 2)
        #expect(GameOptions() == [:] && GameOptions(["a": .int(1)]) == ["a": 1])
    }

    @Test func gameConfiguration_roundTripsThroughJSON() throws {
        let configuration = GameConfiguration(
            gameID: .killer,
            options: ["level": "hard", "lives": 3, "selfHitPenalty": true, "maxRounds": .null, "targets": .strings(["20", "BULL"])],
            players: [Player(name: "Léa"), Player(name: "Tom")],
            seed: 0xFFFF_FFFF_FFFF_FFFF)
        let decoded = try JSONDecoder().decode(GameConfiguration.self, from: JSONEncoder().encode(configuration))
        #expect(decoded == configuration)
        #expect(decoded.seed == UInt64.max && decoded.players.map(\.name) == ["Léa", "Tom"])
        // A game id is saved as its raw string.
        let identifiers = try JSONEncoder().encode([GameID.aroundTheClock])
        #expect(String(decoding: identifiers, as: UTF8.self) == #"["aroundTheClock"]"#)
        #expect(GameID("x01") == .x01 && GameID(rawValue: "golf") == .golf && GameID.radar.description == "radar")
    }
}

/// Shared ranks (GAMES.md §2.7) and the two-language texts (ARCHITECTURE.md §4.3, §4.6).
@Suite struct SmokeRankingTests {
    @Test func ties_shareARank_andTheNextRankIsSkipped() {
        #expect(Ranking.ranks(keys: [[1], [1], [5]]) == [1, 1, 3])
        #expect(Ranking.ranks(keys: [[5], [1], [1]]) == [3, 1, 1])
        #expect(Ranking.ranks(keys: [[2], [2], [2]]) == [1, 1, 1])
        #expect(Ranking.ranks(keys: [[3], [1], [2]]) == [3, 1, 2])
        #expect(Ranking.ranks(keys: [[1], [2], [2], [4]]) == [1, 2, 2, 4])
        #expect(Ranking.ranks(keys: []) == [])
        #expect(Ranking.ranks(keys: [[7]]) == [1])
    }

    @Test func keys_areComparedLexicographically_smallerIsBetter() {
        // Descending points: negate. Second criterion breaks the tie.
        #expect(Ranking.ranks(keys: [[-60, 0], [-60, -1], [-20, -9]]) == [2, 1, 3])
        // Elimination games: alive (0) before eliminated (1); the last eliminated ranks best.
        #expect(Ranking.ranks(keys: [[1, -1], [0, -2], [1, -2], [0, -3]]) == [4, 2, 3, 1])
        // A shorter key that is a prefix of a longer one comes first.
        #expect(Ranking.ranks(keys: [[1, 0], [1]]) == [2, 1])
    }

    @Test func winners_areThePlayersRankedFirst() {
        func snapshot(_ ranks: [Int]) -> GameSnapshot {
            GameSnapshot(gameID: .highScore, title: LocalizedText(verbatim: "t"), phase: .finished, currentPlayer: 0, round: 1,
                         roundLimit: nil, turn: TurnSnapshot(), players: [], ranks: ranks)
        }
        #expect(snapshot([1, 1, 3]).winners == [0, 1])
        #expect(snapshot([2, 1]).winners == [1])
        #expect(snapshot([]).winners.isEmpty)
        #expect(snapshot([1]).winnerTitle == nil && snapshot([1]).turn.capacity == 3)
    }

    @Test func localizedText_picksALanguage_andCounts() {
        let text = LocalizedText(fr: "Vies", en: "Lives")
        #expect(text[.fr] == "Vies" && text[.en] == "Lives")
        #expect(LocalizedText(verbatim: "T20") == LocalizedText(fr: "T20", en: "T20"))
        func lives(_ count: Int) -> LocalizedText {
            .counted(count, fr: (one: "vie", other: "vies"), en: (one: "life", other: "lives"))
        }
        // French takes the singular for 0 and 1, English for 1 only.
        #expect(lives(0) == LocalizedText(fr: "0 vie", en: "0 lives"))
        #expect(lives(1) == LocalizedText(fr: "1 vie", en: "1 life"))
        #expect(lives(3) == LocalizedText(fr: "3 vies", en: "3 lives"))
    }

    @Test func appLanguage_firstFrenchOrEnglishTag_frenchOtherwise() {
        #expect(AppLanguage(preferredLanguages: ["en-GB", "fr-FR"]) == .en)
        #expect(AppLanguage(preferredLanguages: ["de-DE", "fr-CA", "en-US"]) == .fr)
        #expect(AppLanguage(preferredLanguages: ["es-ES", "EN"]) == .en)
        #expect(AppLanguage(preferredLanguages: ["de-DE", "it-IT"]) == .fr)
        #expect(AppLanguage(preferredLanguages: []) == .fr)
        #expect(AppLanguage.fr.voiceLanguageCode == "fr-FR" && AppLanguage.en.voiceLanguageCode == "en-US")
        #expect(AppLanguage.allCases == [.fr, .en])
    }

    @Test func factValue_literals() {
        #expect(FactValue.int(3) == 3 && FactValue.bool(true) == true && FactValue.text("D7") == "D7")
        #expect(FactValue.ints([17, 3, 19]) == [17, 3, 19])
        #expect(FactValue.map([20: 3, 25: 1]) == [20: 3, 25: 1])
        #expect(FactValue.table([[-80, 95, 40, 3], [70, -65, 40, 3]]) != FactValue.table([[70, -65, 40, 3], [-80, 95, 40, 3]]))
        #expect(FactValue.int(1) != FactValue.bool(true))
    }
}
