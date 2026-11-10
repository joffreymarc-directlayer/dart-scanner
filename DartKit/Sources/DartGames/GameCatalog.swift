import DartCore

extension GameRegistry {
    /// The fourteen games, in the order of the home screen: the order of the catalogue of GAMES.md §1,
    /// Dartsee games first (DESIGN.md §4). The only symbol of DartGames that DartUI needs.
    public static let standard = GameRegistry([
        // P0: the seven Dartsee games with documented rules.
        GameDefinition(rules: X01Rules.self),
        GameDefinition(rules: CricketRules.self),
        GameDefinition(rules: KillerRules.self),
        GameDefinition(rules: ShanghaiRules.self),
        GameDefinition(rules: MoonLandingRules.self),
        GameDefinition(rules: FightRules.self),
        GameDefinition(rules: ConquerorRules.self),
        // P1: the four other games of the Dartsee games page, with rules of our own design (lot G4).
        GameDefinition(rules: BeerTapRules.self),
        GameDefinition(rules: FootballRules.self),
        GameDefinition(rules: RadarRules.self),
        GameDefinition(rules: GolfRules.self),
        // P2: the three classic games.
        GameDefinition(rules: AroundTheClockRules.self),
        GameDefinition(rules: HighScoreRules.self),
        GameDefinition(rules: HalveItRules.self),
    ])
}
