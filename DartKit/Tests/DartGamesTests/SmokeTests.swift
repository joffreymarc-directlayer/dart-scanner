import Testing
import DartCore
import DartGames
import DartTestSupport

/// Smoke tests of lot F0 on DartGames (ARCHITECTURE.md §13.2): the registry and its fourteen final descriptors
/// (§5.2, §5.3), the refusals decided by the schema, and the one game that F0 delivers, High Score (§5.4).
/// Everything asserted here stays true when the rules of the other games are delivered.
@Suite struct SmokeTests {
    private let registry = GameRegistry.standard

    // MARK: Registry (ARCHITECTURE.md §5.2)

    @Test func registry_fourteenGames_inTheOrderOfTheCatalogue() {
        #expect(registry.descriptors.map(\.id) == [
            .x01, .cricket, .killer, .shanghai, .moonLanding, .fight, .conqueror,
            .beerTap, .football, .radar, .golf,
            .aroundTheClock, .highScore, .halveIt,
        ])
        #expect(Set(registry.definitions.map(\.id)).count == 14)
        // Dartsee games first: tiers P0, P1, P2 in this order.
        #expect(registry.descriptors.map(\.priority) == [0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2])
        #expect(registry.descriptors.map(\.origin) == Array(repeating: GameOrigin.dartsee, count: 11) + [.classic, .classic, .classic])
        for descriptor in registry.descriptors {
            #expect(registry.definition(for: descriptor.id)?.descriptor == descriptor)
        }
        #expect(registry.definition(for: GameID("castleCrushers")) == nil)
    }

    // MARK: Descriptors (ARCHITECTURE.md §5.3)

    /// One row of the descriptor table of §5.3, transcribed from the document, with the pitch of the game:
    /// the "En une ligne" sentence of GAMES.md §n.1, in both languages.
    private struct Row {
        var id: GameID
        var name: LocalizedText
        var shortName: LocalizedText
        var summary: LocalizedText
        var players: ClosedRange<Int>
        var style: PlayStyle
        var pitch: LocalizedText
    }

    private static func both(_ text: String) -> LocalizedText { LocalizedText(verbatim: text) }

    private static let table: [Row] = [
        Row(id: .x01, name: both("X01"), shortName: both("X01"), summary: both("301 · 501 · 701"), players: 1...8, style: .score,
            pitch: LocalizedText(fr: "Partez de 301, 501 ou 701 et descendez exactement à zéro avant les autres.",
                                 en: "Start from 301, 501 or 701 and be the first to hit exactly zero.")),
        Row(id: .cricket, name: both("Cricket"), shortName: both("Cricket"),
            summary: LocalizedText(fr: "Fermer 15 à 20 et le bull", en: "Close 15 to 20 and the bull"), players: 1...8, style: .score,
            pitch: LocalizedText(fr: "Fermez les numéros 15 à 20 et le bull en les touchant trois fois, puis marquez des points sur ceux que les autres n'ont pas fermés.",
                                 en: "Close 15 to 20 and the bull with three marks each, then score on what the others left open.")),
        Row(id: .killer, name: both("Killer"), shortName: both("Killer"),
            summary: LocalizedText(fr: "4 niveaux · 2 à 8 joueurs", en: "4 levels · 2 to 8 players"), players: 2...8, style: .board,
            pitch: LocalizedText(fr: "Touchez votre zone pour devenir Killer, puis visez celles des autres : le dernier en vie gagne.",
                                 en: "Hit your own zone to become a Killer, then take the others out: last one alive wins.")),
        Row(id: .shanghai, name: both("Shanghai"), shortName: both("Shanghai"),
            summary: LocalizedText(fr: "Un numéro par manche", en: "One number per round"), players: 1...8, style: .board,
            pitch: LocalizedText(fr: "Une manche par numéro : marquez un maximum sur le numéro du moment, ou gagnez d'un coup avec simple + double + triple.",
                                 en: "One number per round: score big on it, or win at once with single + double + treble.")),
        Row(id: .moonLanding, name: LocalizedText(fr: "Alunissage", en: "Moon Landing"),
            shortName: LocalizedText(fr: "Alunissage", en: "Moon Landing"),
            summary: LocalizedText(fr: "De 200 à zéro", en: "From 200 down to zero"), players: 1...8, style: .score,
            pitch: LocalizedText(fr: "Partez à 200 de la Lune : chaque point vous rapproche, le premier posé gagne.",
                                 en: "Start 200 away from the Moon: every point brings you closer, first to land wins.")),
        Row(id: .fight, name: LocalizedText(fr: "Combat", en: "Fight"), shortName: LocalizedText(fr: "Combat", en: "Fight"),
            summary: LocalizedText(fr: "9 vies, blesser ou soigner", en: "9 lives, hurt or heal"), players: 2...6, style: .board,
            pitch: LocalizedText(fr: "Neuf vies chacun : frappez les points faibles des autres, soignez-vous sur votre numéro. Le dernier debout gagne.",
                                 en: "Nine lives each: hit the others' weak spots, heal on your own number. Last one standing wins.")),
        Row(id: .conqueror, name: LocalizedText(fr: "Conquérant", en: "Conqueror"),
            shortName: LocalizedText(fr: "Conquérant", en: "Conqueror"),
            summary: LocalizedText(fr: "Conquérir la cible", en: "Conquer the board"), players: 2...8, style: .board,
            pitch: LocalizedText(fr: "Étendez votre territoire de secteur en secteur, fortifiez-le et prenez la maison des autres.",
                                 en: "Grow your territory sector by sector, fortify it and take the others' home.")),
        Row(id: .beerTap, name: LocalizedText(fr: "Tireuse", en: "Beer Tap"), shortName: LocalizedText(fr: "Tireuse", en: "Beer Tap"),
            summary: LocalizedText(fr: "Remplir des verres", en: "Fill the glasses"), players: 1...8, style: .score,
            pitch: LocalizedText(fr: "Chaque point verse un centilitre de bière : remplissez plus de verres que les autres. Une volée de 100 points, et un verre vous est offert.",
                                 en: "Every point pours a centilitre of beer: fill more glasses than the others. Score 100 in a turn and a glass is on the house.")),
        Row(id: .football, name: both("Football"), shortName: both("Football"),
            summary: LocalizedText(fr: "Deux camps, un ballon", en: "Two sides, one ball"), players: 2...8, style: .board,
            pitch: LocalizedText(fr: "Deux camps, un ballon : chaque fléchette pousse le ballon du côté de la cible où elle se plante. Amenez-le dans le but d'en face.",
                                 en: "Two sides, one ball: every dart pushes the ball towards the side of the board it lands on. Get it into the opposite goal.")),
        Row(id: .radar, name: both("Radar"), shortName: both("Radar"),
            summary: LocalizedText(fr: "Cibles rondes à détruire", en: "Round targets to destroy"), players: 1...8, style: .board,
            pitch: LocalizedText(fr: "Cinq cibles rondes sont posées sur le plateau : chaque touche rapporte des points, chaque cible détruite un bonus, et une nouvelle prend sa place.",
                                 en: "Five round targets sit on the board: every hit scores, every target destroyed pays a bonus, and a new one takes its place.")),
        Row(id: .golf, name: both("Golf"), shortName: both("Golf"),
            summary: LocalizedText(fr: "Le moins de coups", en: "Fewest strokes"), players: 1...8, style: .board,
            pitch: LocalizedText(fr: "Un numéro par trou : 1 coup pour le double, 2 pour le triple, 3 pour le simple, 5 si vous le manquez. Le moins de coups gagne.",
                                 en: "One number per hole: 1 stroke for the double, 2 for the treble, 3 for the single, 5 if you miss it. Fewest strokes wins.")),
        Row(id: .aroundTheClock, name: LocalizedText(fr: "Tour de l'horloge", en: "Around the Clock"),
            shortName: LocalizedText(fr: "Horloge", en: "Clock"),
            summary: LocalizedText(fr: "De 1 à 20 dans l'ordre", en: "1 to 20 in order"), players: 1...8, style: .board,
            pitch: LocalizedText(fr: "Touchez les numéros de 1 à 20 dans l'ordre : le premier arrivé au bout gagne.",
                                 en: "Hit 1 to 20 in order: first to the end wins.")),
        Row(id: .highScore, name: LocalizedText(fr: "Meilleur score", en: "High Score"),
            shortName: LocalizedText(fr: "Meilleur score", en: "High Score"),
            summary: LocalizedText(fr: "Le plus de points", en: "Most points"), players: 1...8, style: .score,
            pitch: LocalizedText(fr: "Un nombre de manches fixe, tout compte : le plus gros total gagne.",
                                 en: "A fixed number of rounds, everything counts: highest total wins.")),
        Row(id: .halveIt, name: LocalizedText(fr: "La Moitié", en: "Halve-It"), shortName: LocalizedText(fr: "La Moitié", en: "Halve-It"),
            summary: LocalizedText(fr: "Raté : score divisé par 2", en: "Miss it: score halved"), players: 1...8, style: .board,
            pitch: LocalizedText(fr: "Une cible imposée par manche : ratez-la avec vos trois fléchettes et votre score est divisé par deux.",
                                 en: "One set target per round: miss it with all three darts and your score is halved.")),
    ]

    @Test func descriptors_namesSummariesPlayersAndTemplate() {
        #expect(Self.table.map(\.id) == registry.descriptors.map(\.id))
        for (row, descriptor) in zip(Self.table, registry.descriptors) {
            #expect(descriptor.name == row.name, "\(row.id)")
            #expect(descriptor.shortName == row.shortName, "\(row.id)")
            #expect(descriptor.summary == row.summary, "\(row.id)")
            #expect(descriptor.players == row.players, "\(row.id)")
            #expect(descriptor.playStyle == row.style, "\(row.id)")
            // The descriptors are final (§5.3): a lot that writes the rules of a game keeps its pitch word for word.
            #expect(descriptor.pitch == row.pitch, "\(row.id)")
        }
        // What a game has of its own is data: one position-dependent game, one game without short-turn confirmation.
        #expect(registry.descriptors.filter(\.dependsOnPosition).map(\.id) == [.radar])
        #expect(registry.descriptors.filter { !$0.confirmsShortTurn }.map(\.id) == [.golf])
    }

    /// Shape of an option, without its texts: what §5.3 puts in the columns `kind`, values, default, advanced.
    private enum Shape: Equatable {
        case toggle
        case stepper(ClosedRange<Int>)
        case optionalStepper(ClosedRange<Int>)
        case choice([OptionValue], custom: Bool)
    }

    private struct Option {
        var key: String
        var shape: Shape
        var value: OptionValue
        var advanced = false
        var label: LocalizedText
    }

    private static let maxRoundsLabel = LocalizedText(fr: "Manches maximum", en: "Round limit")
    private static let halveItShort = OptionValue.strings(["20", "16", "D7", "14", "T10", "BULL"])
    private static let halveItLong = OptionValue.strings(["15", "16", "anyDouble", "17", "18", "anyTreble", "19", "20", "BULL"])

    private static func maxRounds(_ value: OptionValue) -> Option {
        Option(key: "maxRounds", shape: .optionalStepper(1...99), value: value, advanced: true, label: maxRoundsLabel)
    }

    /// The option table of §5.3, transcribed from the document, in the order of the registry.
    private static let options: [GameID: [Option]] = [
        .x01: [
            Option(key: "startScore", shape: .choice([301, 501, 701], custom: false), value: 301,
                   label: LocalizedText(fr: "Score de départ", en: "Start score")),
            Option(key: "inRule", shape: .choice(["straight", "double"], custom: false), value: "straight",
                   label: LocalizedText(fr: "Entrée", en: "In")),
            Option(key: "outRule", shape: .choice(["straight", "double"], custom: false), value: "straight",
                   label: LocalizedText(fr: "Sortie", en: "Out")),
            maxRounds(20),
        ],
        .cricket: [
            Option(key: "scoring", shape: .choice(["cutThroat", "standard"], custom: false), value: "cutThroat",
                   label: LocalizedText(fr: "Score", en: "Scoring")),
            Option(key: "targets", shape: .choice(["normal", "light"], custom: false), value: "normal",
                   label: LocalizedText(fr: "Cibles", en: "Targets")),
            maxRounds(20),
        ],
        .killer: [
            Option(key: "level", shape: .choice(["easy", "medium", "hard", "expert"], custom: false), value: "easy",
                   label: LocalizedText(fr: "Niveau", en: "Level")),
            Option(key: "lives", shape: .stepper(1...9), value: 3, label: LocalizedText(fr: "Vies", en: "Lives")),
            Option(key: "armingHits", shape: .stepper(1...5), value: 3,
                   label: LocalizedText(fr: "Touches pour devenir Killer", en: "Hits to become a Killer")),
            Option(key: "selfHitPenalty", shape: .toggle, value: false, advanced: true,
                   label: LocalizedText(fr: "Pénalité sur sa propre zone", en: "Penalty on your own zone")),
            maxRounds(15),
        ],
        .shanghai: [
            Option(key: "rounds", shape: .choice([7, 20], custom: true), value: 7, label: LocalizedText(fr: "Manches", en: "Rounds")),
            Option(key: "variant", shape: .choice(["traditional", "lite"], custom: false), value: "traditional",
                   label: LocalizedText(fr: "Variante", en: "Variant")),
        ],
        .moonLanding: [
            Option(key: "distance", shape: .choice([200, 300, 500], custom: true), value: 200, label: both("Distance")),
            Option(key: "exactLanding", shape: .toggle, value: false,
                   label: LocalizedText(fr: "Alunissage exact (Pro)", en: "Exact landing (Pro)")),
            maxRounds(15),
        ],
        .fight: [
            Option(key: "lives", shape: .stepper(1...20), value: 9, label: LocalizedText(fr: "Vies", en: "Lives")),
            maxRounds(15),
        ],
        .conqueror: [
            Option(key: "multipliersCount", shape: .toggle, value: false,
                   label: LocalizedText(fr: "Doubles et triples comptent", en: "Doubles and trebles count")),
            maxRounds(15),
        ],
        .beerTap: [
            Option(key: "glassSize", shape: .choice([25, 50, 100], custom: false), value: 50, label: LocalizedText(fr: "Verre", en: "Glass")),
            Option(key: "rounds", shape: .stepper(1...20), value: 5, label: LocalizedText(fr: "Manches", en: "Rounds")),
        ],
        .football: [
            Option(key: "fieldLength", shape: .stepper(3...8), value: 4,
                   label: LocalizedText(fr: "Longueur du terrain", en: "Field length")),
            Option(key: "goalsToWin", shape: .stepper(1...9), value: 3, label: LocalizedText(fr: "Buts pour gagner", en: "Goals to win")),
            maxRounds(10),
        ],
        .radar: [
            Option(key: "movingTargets", shape: .toggle, value: false, label: LocalizedText(fr: "Cibles mobiles", en: "Moving targets")),
            Option(key: "rounds", shape: .stepper(1...20), value: 8, label: LocalizedText(fr: "Manches", en: "Rounds")),
        ],
        .golf: [
            Option(key: "holes", shape: .choice([9, 18], custom: true), value: 9, label: LocalizedText(fr: "Trous", en: "Holes")),
            Option(key: "countedDart", shape: .choice(["last", "best"], custom: false), value: "last",
                   label: LocalizedText(fr: "Fléchette comptée", en: "Counted dart")),
        ],
        .aroundTheClock: [
            Option(key: "finishOnBull", shape: .toggle, value: false,
                   label: LocalizedText(fr: "Finir sur le bull", en: "Finish on the bull")),
            Option(key: "multiplierJump", shape: .toggle, value: false,
                   label: LocalizedText(fr: "Doubles et triples avancent plus", en: "Doubles and trebles jump")),
            maxRounds(.null),
        ],
        .highScore: [
            Option(key: "rounds", shape: .stepper(1...20), value: 8, label: LocalizedText(fr: "Manches", en: "Rounds")),
        ],
        .halveIt: [
            Option(key: "targets", shape: .choice([halveItShort, halveItLong], custom: true), value: halveItShort,
                   label: LocalizedText(fr: "Cibles", en: "Targets")),
            Option(key: "startingScore", shape: .choice([0, 40], custom: false), value: 0,
                   label: LocalizedText(fr: "Score de départ", en: "Starting score")),
        ],
    ]

    private func shape(of option: OptionDescriptor) -> Shape {
        switch option.kind {
        case .toggle: return .toggle
        case .stepper(let range): return .stepper(range)
        case .optionalStepper(let range, _): return .optionalStepper(range)
        case .choice(let choices): return .choice(choices.map(\.value), custom: option.allowsCustomValue)
        }
    }

    @Test func options_keysKindsValuesDefaultsAndLabels() throws {
        #expect(Self.options.count == 14)
        for descriptor in registry.descriptors {
            let expected = try #require(Self.options[descriptor.id])
            #expect(descriptor.options.map(\.key) == expected.map(\.key), "\(descriptor.id)")
            for (option, row) in zip(descriptor.options, expected) {
                let name = "\(descriptor.id).\(row.key)"
                #expect(shape(of: option) == row.shape, "\(name)")
                #expect(option.defaultValue == row.value, "\(name)")
                #expect(option.isAdvanced == row.advanced, "\(name)")
                #expect(option.label == row.label, "\(name)")
                if case .optionalStepper(_, let nullLabel) = option.kind {
                    #expect(nullLabel == LocalizedText(fr: "Sans limite", en: "No limit"), "\(name)")
                }
                if case .choice = option.kind {} else {
                    // Only a choice can accept a custom value.
                    #expect(!option.allowsCustomValue, "\(name)")
                }
            }
        }
    }

    /// Labels of the choices that §5.3 writes out; a numeric choice has its number as label.
    @Test func options_choiceLabels() throws {
        func labels(_ game: GameID, _ key: String) throws -> [LocalizedText] {
            let option = try #require(registry.definition(for: game)?.descriptor.option(key))
            guard case .choice(let choices) = option.kind else {
                Issue.record("\(game).\(key) is not a choice")
                return []
            }
            return choices.map(\.label)
        }
        #expect(try labels(.x01, "startScore") == ["301", "501", "701"].map(Self.both))
        #expect(try labels(.x01, "inRule") == [LocalizedText(fr: "Entrée libre", en: "Straight in"),
                                               LocalizedText(fr: "Entrée en double", en: "Double in")])
        #expect(try labels(.x01, "outRule") == [LocalizedText(fr: "Sortie libre", en: "Straight out"),
                                                LocalizedText(fr: "Sortie en double", en: "Double out")])
        #expect(try labels(.cricket, "scoring") == [Self.both("Cut-throat"), Self.both("Standard")])
        #expect(try labels(.cricket, "targets") == [Self.both("Normal"), LocalizedText(fr: "Léger", en: "Light")])
        #expect(try labels(.killer, "level") == [LocalizedText(fr: "Facile", en: "Easy"), LocalizedText(fr: "Intermédiaire", en: "Medium"),
                                                 LocalizedText(fr: "Difficile", en: "Hard"), Self.both("Expert")])
        #expect(try labels(.shanghai, "rounds") == ["7", "20"].map(Self.both))
        #expect(try labels(.shanghai, "variant") == [LocalizedText(fr: "Traditionnel", en: "Traditional"), Self.both("Lite")])
        #expect(try labels(.moonLanding, "distance") == ["200", "300", "500"].map(Self.both))
        #expect(try labels(.beerTap, "glassSize") == [LocalizedText(fr: "Demi", en: "Half"), LocalizedText(fr: "Pinte", en: "Pint"),
                                                      Self.both("Litre")])
        #expect(try labels(.golf, "holes") == ["9", "18"].map(Self.both))
        #expect(try labels(.golf, "countedDart") == [LocalizedText(fr: "La dernière fléchette", en: "Last dart"),
                                                     LocalizedText(fr: "La meilleure fléchette", en: "Best dart")])
        #expect(try labels(.halveIt, "targets") == [LocalizedText(fr: "Courte", en: "Short"), LocalizedText(fr: "Longue", en: "Long")])
        #expect(try labels(.halveIt, "startingScore") == ["0", "40"].map(Self.both))
    }

    @Test func killerLevels_easyIsLimitedToSixPlayers() throws {
        let killer = try #require(registry.definition(for: .killer)?.descriptor)
        guard case .choice(let levels)? = killer.option("level")?.kind else {
            Issue.record("level is not a choice")
            return
        }
        #expect(levels.map(\.players) == [2...6, nil, nil, nil])
        #expect(levels[0].unavailableNote == LocalizedText(fr: "6 joueurs maximum en Facile", en: "6 players maximum in Easy"))
        #expect(levels.map(\.illustration) == [.sectors(count: 3, moving: false), .sectors(count: 2, moving: false),
                                               .sectors(count: 1, moving: false), .sectors(count: 1, moving: true)])
        #expect(killer.playerRange(for: [:]) == 2...6 && killer.playerRange(for: ["level": "expert"]) == 2...8)
        // Setup screen: Easy with 7 players becomes Medium (GAMES.md §5.2).
        #expect(killer.adjusted([:], playerCount: 7)["level"] == .string("medium"))
        #expect(killer.validate(options: [:], playerCount: 7) == [.choiceUnavailable(key: "level", note: levels[0].unavailableNote)])
    }

    @Test func defaultOptions_areValidForEveryAllowedNumberOfPlayers() {
        for descriptor in registry.descriptors {
            let range = descriptor.playerRange(for: descriptor.defaultOptions)
            #expect(descriptor.players.contains(range.lowerBound) && descriptor.players.contains(range.upperBound))
            for count in range {
                #expect(descriptor.validate(options: [:], playerCount: count).isEmpty, "\(descriptor.id) with \(count) players")
                #expect(descriptor.validate(options: descriptor.defaultOptions, playerCount: count).isEmpty)
            }
            #expect(!descriptor.validate(options: [:], playerCount: descriptor.players.upperBound + 1).isEmpty)
            #expect(!descriptor.validate(options: [:], playerCount: descriptor.players.lowerBound - 1).isEmpty)
        }
    }

    // MARK: Creation

    /// Decided by the schema, before any rule runs: true on the skeleton and once the rules are delivered.
    @Test func schemaRefusals_holdWhateverTheStateOfTheRules() {
        #expect(throws: GameConfigurationError.invalidOptionValue(key: "glassSize")) {
            try registry.match(.beerTap, ["glassSize": 40], players: 2)
        }
        #expect(throws: GameConfigurationError.invalidOptionValue(key: "rounds")) {
            try registry.match(.radar, ["rounds": 21], players: 2)
        }
        #expect(throws: GameConfigurationError.playerCountOutOfRange(allowed: 2...8, actual: 1)) {
            try registry.match(.football, players: 1)
        }
        #expect(throws: GameConfigurationError.playerCountOutOfRange(allowed: 2...6, actual: 7)) {
            try registry.match(.fight, players: 7)
        }
        #expect(throws: GameConfigurationError.choiceUnavailable(
            key: "level", note: LocalizedText(fr: "6 joueurs maximum en Facile", en: "6 players maximum in Easy"))) {
            try registry.match(.killer, ["level": "easy"], players: 7)
        }
        #expect(throws: GameConfigurationError.unknownOption(key: "legs")) {
            try registry.match(.x01, ["legs": 3], players: 2)
        }
        #expect(throws: GameConfigurationError.invalidOptionValue(key: "startScore")) {
            try registry.match(.x01, ["startScore": 1001], players: 2)
        }
        #expect(throws: GameConfigurationError.unknownGame(GameID("darts501"))) {
            try registry.match(GameID("darts501"), players: 2)
        }
    }

    /// A game either starts or, while its rules are still a skeleton, refuses cleanly with `.unknownGame`.
    /// It never traps, and no game is in both lists.
    @Test func everyGame_startsOrRefusesCleanly() throws {
        let skeletons = registry.skeletonGames
        let delivered = registry.deliveredDefinitions.map(\.id)
        #expect(Set(skeletons).isDisjoint(with: delivered))
        #expect(Set(skeletons + delivered) == Set(registry.descriptors.map(\.id)))
        // High Score is delivered by lot F0.
        #expect(delivered.contains(.highScore) && !skeletons.contains(.highScore))
        for id in skeletons {
            let descriptor = try #require(registry.definition(for: id)?.descriptor)
            #expect(throws: GameConfigurationError.unknownGame(id)) {
                try registry.match(id, players: descriptor.playerRange(for: [:]).lowerBound)
            }
        }
        for definition in registry.deliveredDefinitions {
            let descriptor = definition.descriptor
            for count in descriptor.playerRange(for: [:]) {
                let match = try registry.match(descriptor.id, players: count, seed: 1)
                #expect(match.snapshot.gameID == descriptor.id && match.phase == .throwing)
                #expect(match.snapshot.players.count == count && match.snapshot.ranks.count == count)
                #expect(match.snapshot.currentPlayer == 0 && match.snapshot.round == 1 && match.snapshot.turn.darts.isEmpty)
                #expect(match.configuration.options == descriptor.defaultOptions)
            }
        }
    }

    // MARK: High Score (GAMES.md §8.9), the game delivered by lot F0

    @Test func his1_simpleAdditionAnd180() throws {
        var match = try registry.match(.highScore, ["rounds": 2], players: 2)
        let outcomes = match.play("T20, T20, T20 | S5, S1, MISS | DB, SB, S20 | T19, D16, S7")
        #expect(match.fact(0, "points") == 275 && match.fact(1, "points") == 102)
        #expect(match.phase == .turnComplete && match.snapshot.round == 2)
        #expect(outcomes[2].events == [.dartRegistered(player: 0, hit: .treble(20)), .turnScored(player: 0, points: 180),
                                       .oneEighty(player: 0), .turnCompleted(player: 0)])
        #expect(match.endTurn().events == [.gameFinished(reason: .roundLimit)])
        #expect(match.phase == .finished && match.snapshot.finishReason == .roundLimit && match.snapshot.ranks == [1, 2])
    }

    @Test func his2_tie() throws {
        var match = try registry.match(.highScore, ["rounds": 1], players: 3)
        match.play("S20, S20, S20 | T20, MISS, MISS | S19, S1, MISS |")
        #expect(match.fact(0, "points") == 60 && match.fact(1, "points") == 60 && match.fact(2, "points") == 20)
        #expect(match.snapshot.ranks == [1, 1, 3] && match.snapshot.winners == [0, 1])
        #expect(match.phase == .finished)
    }

    @Test func his3_shortTurn() throws {
        var match = try registry.match(.highScore, ["rounds": 1], players: 1)
        match.play("S20 |")
        #expect(match.phase == .finished && match.fact(0, "points") == 20 && match.fact(0, "dartsThrown") == 1)
        // A game ended at the round limit has an empty volley, in the snapshot as in the journal (GAMES.md §2.4).
        #expect(match.snapshot.turn.darts.isEmpty && match.currentTurn.isEmpty)
        #expect(!match.replaceDart(at: 0, with: .treble(20)).applied)
    }

    @Test func his4_highTurn() throws {
        var match = try registry.match(.highScore, players: 1)
        let outcomes = match.play("T20, T20, S20")
        #expect(match.fact(0, "points") == 140)
        #expect(outcomes[2].events == [.dartRegistered(player: 0, hit: .single(20)), .turnScored(player: 0, points: 140),
                                       .highTurn(player: 0, points: 140), .turnCompleted(player: 0)])
        // A MISS changes nothing and says so; High Score has no highlight and reads on a big number.
        var other = try registry.match(.highScore, players: 2)
        #expect(other.play("MISS")[0].events == [.dartRegistered(player: 0, hit: .miss), .noEffect(player: 0)])
        #expect(other.snapshot.highlights.isEmpty && other.snapshot.roundLimit == 8)
        #expect(other.snapshot.title == LocalizedText(fr: "Meilleur score", en: "High Score"))
    }
}
