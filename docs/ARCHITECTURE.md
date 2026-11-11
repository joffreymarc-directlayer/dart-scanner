# ARCHITECTURE.md — Architecture de l'application Dart Scanner

Version 1.1 — 2026-11-10 — Statut : **normatif**.

Ce document est le contrat entre les cibles du paquet `DartKit`. Plusieurs ingénieurs le réalisent **en parallèle, sans se parler** : toute interface entre deux cibles ou entre deux lots est donc écrite ici en Swift exact.

- Les règles de jeu sont dans `GAMES.md`, la lecture par caméra dans `VISION.md`, l'apparence dans `DESIGN.md` et ses maquettes. Ce document ne les répète pas : il dit **où** chaque chose vit et **par quelle interface** elle se parle.
- Identifiants, code et commentaires de code sont en anglais et font foi tels quels. L'interface de l'application est en français d'abord, en anglais ensuite.
- « DOIT » / « NE DOIT PAS » marquent une exigence testable.
- **Convention des listings.** Un bloc précédé de « Fichier `chemin` » est le contenu exact de ce fichier : il se colle tel quel. Dans les listings de `DartAudio` et de `DartUI`, un corps `{ unimplemented() }` (ou `{ StubView() }` pour une vue) marque ce que le lot propriétaire doit écrire ; la signature, elle, est figée. Les listings de `DartCore` sont complets : ils n'ont aucun corps à écrire. Deux listings de `DartUI` sont eux aussi livrés avec leurs vrais corps : `Camera/ScanServicing.swift` et `Camera/CameraModel.swift` (§8.4.8). Deux initialiseurs le sont aussi, pour qu'un lot puisse exécuter son code avant la livraison de ses voisins : celui de `PlayViewModel`, qui range ses paramètres (§8.4.7), et celui de chaque vue d'entrée, qui ne fait rien et ne plante pas (§8.4.10).

Changements de la version 1.1 (revue croisée des quatre documents, et décision du propriétaire sur le périmètre des jeux) :

- **quatorze jeux** : Tireuse, Football, Radar et Golf entrent dans le périmètre et forment le lot **G4** (§5, §13) ; l'ordre du registre est celui du catalogue de `GAMES.md` §1, les jeux Dartsee d'abord ;
- la **position de l'impact** atteint les moteurs (`GameEngine.apply(_:position:)`, `TurnContext.positions`, `ImpactPoint`), une règle peut tirer au sort pendant une fléchette, une surbrillance peut être un **disque** (`BoardZone.disc`), un fait peut être une table (§4) ;
- deux réglages par jeu dans le descripteur : `dependsOnPosition` et `confirmsShortTurn` (§4.4) ;
- le squelette de `DartVision` donne un vrai corps aux membres de simple donnée, et l'initialiseur de `DartObservation` est désormais dans `VISION.md` (§6.3, §6.4) ;
- la façade caméra est découpée pour que l'application démarre sans attendre le lot U3 (§8.4.8) ; les commandes de `DartInputSource` sont synchrones et ordonnées (§8.4.6, §11) ;
- fin de partie en deux temps avec `PlayViewModel.finishGame()`, cycle de vie des commandes de scan, mode photo toujours accessible, `captureStill(averaging:)` (§8.6, §8.7) ;
- dix événements nouveaux dans la table des sons (§7.3) ; tests communs qui sautent les jeux encore en squelette (§12.1) ; commandes de construction simples (§12.2).

Corrections apportées après l'audit de la version 1.1 (trois relectures indépendantes) :

- **aucun lot n'attend plus un lot de sa vague** : l'initialiseur de `PlayViewModel` est écrit par F0 (§8.4.7), les vues d'entrée des autres lots s'affichent vides au lieu de planter (§8.4.10), `PhotoScorer` passe au lot V3 (§13), et les tests qui demandaient une valeur d'un autre lot ont changé de lot (§12.1) ;
- **une partie en mode caméra a une source dès le lancement à froid** : `makeInputSource` ne dépend plus de `readiness`, et `PlayScreen` attend `camera.activate()` avant de démarrer la partie (§8.5 à §8.7) ;
- **une seule file de commandes**, tenue par `CameraModel` (`enqueue`), pour les sources, le mode photo, le calibrage et l'arrière-plan (§8.4.8, §8.7, §11) ;
- le vainqueur d'un jeu de camps est une donnée, `winnerTitle`, et non plus un test sur l'identifiant du jeu (§4.6, §7.2, §7.3, §8.6) ;
- une pointe au bord d'une cible de Radar est marquée « à vérifier » (§8.4.8) ; « Scanner » est inactif quand la volée est pleine ou close (§8.7) ;
- le squelette ne laisse plus de choix à F0 : formes exactes des corps de `DartVision` et imports (§6.4), libellés de toutes les options (§5.3), fichiers créés (§2, §8.3, §13.2), lectures du lot F0 (guide ci-dessous).

Corrections de la dernière relecture avant réalisation (cinq points, dont un seul bloquait un lot) :

- **le lot V1 n'appelle plus un corps du lot V2** : les poignées du calibrage exact se construisent avec les seuls membres de simple donnée (§6.4, §13.3 ; `VISION.md` §9.3, §10.1) ;
- **une pause de fin de partie ne se lève que par `arm`** : `paused` porte sa raison, un `resume` venu de l'arrière-plan ou d'une interruption de capture ne réveille plus la vision sans partie, et le calibrage arrête la vision à sa fermeture (§6.5, §8.7 ; `VISION.md` §6.3) ;
- **règle de noms dans un module partagé**, avec le préfixe de chaque lot, les tests rangés en `@Suite struct` et une seule étiquette de test (§13.1, §13.4 ; §5.2, §5.7, §12.1) ;
- **la date de début d'une partie vient de `environment.now()`**, et `AppEnvironment.preview()` a une graine et une date fixes (§4.8, §8.4.9, §8.5) ;
- **les valeurs que les tests comparent sont `Hashable`** : `ScanCommand`, `ScanEvent`, `ScanEffect`, `ScanInput`, `SettleOutcome`, `DartObservation` (`VISION.md` §9.2 ; §6.4, §8.4.8, §8.7).

Fichiers imprimés touchés par ces corrections : dans ce document, le seul listing `App/AppModel.swift` (§8.4.9, commentaires seulement, aucune signature) ; dans `VISION.md` §9.2, les types de `Confidence/DartObservation.swift`, `Scan/ScanEvents.swift`, `Calibration/CalibrationHandles.swift` et `Synthetic/SyntheticCamera.swift` (six conformités `Hashable` et des commentaires).

Corrections apportées par le lot F0 pendant la réalisation (trois points que le texte laissait ouverts ; le dépôt et ce document disent la même chose) :

- **`SnapshotTool` écrit un PNG dès la fondation** : la liste d'instantanés du socle est livrée avec un écran d'essai, `skeleton`, au lieu d'être vide ; le lot U1 le remplace par les siens (§8.4.10, §8.11, §13.2). Seul listing imprimé touché : `Snapshots/KernelSnapshots.swift` ;
- **les clés des tables de chaînes du squelette sont nommées** : une par table, `"common.ok"`, `"play.nextPlayer"`, `"calibration.validate"` (§8.9) ;
- **les tests de `DartCoreTests` portent le préfixe `Smoke`**, comme tout test du lot F0 : une suite par sujet de §12.1 et les règles d'essai dans `SmokeFixtures.swift` (§13.4).

Corrections apportées après la vérification du lot F0 (deux relectures indépendantes du dépôt ; le dépôt et ce document disent de nouveau la même chose) :

- **une partie finie à la limite de manches a une volée vide** : le noyau vide la volée et ses positions quand `endTurn` termine la partie, comme à toute autre confirmation. `snapshot.turn.darts` et `GameMatch.currentTurn` sont ainsi alignés dans toutes les phases, ce que promet `PlayViewModel.turnRecords` ; avant, une vue qui aurait indexé l'un par l'autre serait sortie des bornes sur l'écran des résultats, dans les cinq jeux qui ne finissent qu'à la limite de manches (§4.7, §8.4.7, §12.1 ; `GAMES.md` §2.4, §2.6, COM-7) ;
- **`BoardGeometry.hit(at:)` est une fonction totale** : un point dont une coordonnée n'est pas finie rend `MISS` au lieu d'arrêter le programme, par `hit(at:)`, par `sectorIndex(at:)` et après `remap(_:to:)` ; `BoardPoint.clockwiseDegrees` reste dans [0, 360) (§4.2, §4.9, §12.1 ; `VISION.md` §9.1) ;
- **`Hit(notation:)` refuse un zéro en tête** (`S05`, `020`), une lecture que le contrat n'accordait pas (§4.2, §14) ;
- quatre points de texte : `.swiftpm/` est ignoré par git (§2) ; le lot U1 DOIT supprimer l'écran d'essai `skeleton` en vague 1 (§8.4.10, §8.11, §13.2) ; son test de parité des chaînes s'appelle `KernelL10nParityTests` (§8.9) ; la liste des suites de `DartCoreTests` nomme `SmokeRankingTests` (§13.4).

Listings imprimés touchés : `Board/BoardPoint.swift`, `Board/Hit.swift`, `Board/BoardGeometry.swift` et `Game/GameEngine.swift` (des corps et des commentaires, aucune signature), et `.gitignore`.

**Ce qui a été vérifié** pour cette version 1.1 (le 2026-11-10, dans un paquet d'essai neuf, hors du dépôt, avec Xcode 27.2, Swift 6.4.2, le Simulateur iOS 27.2 et XcodeGen 2.46) :

- les 45 fichiers imprimés ici ont été extraits de ce document par un script, puis complétés comme le fera le lot F0 : squelette de `DartVision` produit depuis le listing de `VISION.md` §9.2 selon la règle de §6.4 (86 types dans les 37 fichiers de la table de `VISION.md` §9.3, vrais corps pour les membres de simple donnée de §9.4), douze règles de jeu en squelette en plus de celle du Killer, points d'entrée des écrans, tables de chaînes. L'ensemble (103 fichiers Swift, quatorze jeux au registre) se construit **sans erreur ni avertissement** pour macOS (`swift build`) et pour le Simulateur iOS (`xcodebuild -scheme DartUI -destination 'generic/platform=iOS Simulator'`), en mode Swift 5 avec le contrôle de concurrence strict ;
- les signatures imposées au lot U3 (§8.4.8), ajoutées à ce squelette, compilent elles aussi sans avertissement sur les deux plateformes ;
- `swift test` passe 75 tests Swift Testing dans les cinq cibles de test (48, 6, 7, 11 et 3) ;
- les 48 tests de `DartCoreTests` éprouvent `DartCore` tel qu'il est imprimé ici : les vecteurs COM-1 à COM-7, X01-1, X01-3, HIS-2, HIS-3, KIL-1 et KIL-3 de `GAMES.md`, et, pour les quatre jeux du lot G4, **tous** les vecteurs BEE-1 à 6, FOO-1 à 7, RAD-1 à 7 et GOL-1 à 7, joués par des règles d'essai écrites contre le contrat de §4, corrections et rejeux compris ; le titre des résultats `winnerTitle`, qui ne sort qu'en phase `finished` ; les 62 positions canoniques de `GAMES.md` §2.13, l'arrondi au dixième, demis compris, et le bornage d'une coordonnée non finie ; la clé d'effet sur le couple (case, position) ; le rejeu et la restauration JSON d'une partie avec positions ; les valeurs de contrôle de SplitMix64 et de `ringLayout` ; les conventions géométriques et la notation ;
- les autres tests vérifient, sur le squelette : l'ordre et les paliers des quatorze jeux du registre, le saut des treize jeux en squelette, les refus décidés par le schéma des quatre nouveaux jeux, « Meilleur score » ; les membres de simple donnée de `DartVision` (ils répondent sans planter) ; `FakeScanService`, le corps minimal de `CameraModel` et de sa file (`enqueue`), la parité des tables de chaînes ; l'initialiseur de `PlayViewModel` écrit par F0 (la partie répond à `snapshot`, `descriptor`, `turnRecords`, `inputStatus`) ; les onze vues d'entrée, qui se construisent sans planter ; `CueContext` avec `winnerTitle` ;
- `SnapshotTool` rend un écran d'essai en PNG, en français et en anglais, avec la méthode de localisation retenue ; cet écran contient deux vues d'entrée encore vides (`HomeScreen`, `SetupScreen`), qui ne l'arrêtent pas ;
- la coquille iOS générée par XcodeGen se construit pour les simulateurs iPhone 17 et iPad Pro 13 pouces (M5) ;
- avec la seule chaîne des Command Line Tools, le paquet se construit et les 75 tests passent, par les commandes de repli de §12.2.

**Vérification refaite après les corrections de la dernière relecture** (même machine, même jour, paquet d'essai neuf) :

- les 45 fichiers imprimés ont été extraits de nouveau et le squelette refait selon §6.4. Cinq fichiers diffèrent de l'extraction précédente, ceux que nomme la liste des corrections ci-dessus ; les 103 fichiers Swift se construisent **sans erreur ni avertissement** par `swift build` et par `xcodebuild -scheme DartUI -destination 'generic/platform=iOS Simulator'`, et la coquille iOS se construit pour les simulateurs iPhone 17 et iPad Pro 13 pouces (M5) ;
- les 75 tests de la vérification précédente passent sans changement sur ce nouveau contrat ;
- 32 tests rangés en `@Suite struct` selon §13.4 passent sur le squelette (11, 8, 7, 4 et 2 dans les cinq cibles). Ceux qui sont neufs éprouvent : l'égalité par `==` de `ScanCommand`, `ScanEvent`, `ScanEffect`, `ScanInput`, `SettleOutcome` et `DartObservation` ; `paused(.user)` distinct de `paused(.background)` ; listes de commandes de `FakeScanService` comparées en entier ; étiquette `heavy` déclarée une fois et employée depuis un autre fichier ; deux suites d'une même cible qui portent une méthode de même nom ;
- dans une copie où seuls des corps des lots V1 et U1 sont écrits (tout membre du lot V2 y plante encore), `SyntheticCamera.exactHandles()` rend les quatre jonctions projetées pour les poses A à D, et `AppModel.startGame` sous `AppEnvironment.preview()` donne deux fois le même `MatchRecord`, à la date et à la graine de l'environnement ; un modèle jetable des seules lignes de pause de `VISION.md` §6.3 donne les résultats attendus des tests S16 et S17 ;
- les quatre collisions que §13.4 interdit ont été reproduites dans un paquet d'essai : deux fichiers de même nom, deux fonctions `@Test` libres de même nom, deux déclarations de la même étiquette, deux conformités identiques. Chacune arrête la construction.

Ces corrections n'ont, comme le reste de §8.5 à §8.7 et de `VISION.md` §6.3, pas d'autre preuve que ces essais : ni le réducteur ni la file de commandes n'existent encore.

**Réalisation du lot F0 dans le dépôt** (même machine, même jour) :

- le squelette a été refait à partir des documents, par script : les 42 fichiers imprimés du paquet sont dans le dépôt octet pour octet (les trois de la coquille iOS, `App/DartScannerApp.swift`, `project.yml` et `Config/Base.xcconfig`, restent au lot X1). Avec les 37 fichiers de `DartVision`, les douze règles en squelette, les onze vues d'entrée et les deux listes d'instantanés vides, cela fait 103 fichiers Swift et six tables de chaînes. Un contrôle indépendant du générateur retire du squelette de `DartVision` les corps de §6.4 et retrouve le listing de `VISION.md` §9.2 ligne pour ligne ;
- `swift build`, `swift test` et `xcodebuild -scheme DartUI -destination 'generic/platform=iOS Simulator' build` passent sans erreur ni avertissement ; `swift run SnapshotTool` écrit `skeleton@phonePortrait.png` en français et en anglais ;
- `swift test` passe 179 tests Swift Testing, tous rangés en `@Suite struct` : 130 dans `DartCoreTests` (dix suites), 12 dans `DartGamesTests`, 17 dans `DartVisionTests`, 7 dans `DartAudioTests` et 13 dans `DartUITests`. Les 130 éprouvent `DartCore` selon la liste de §12.1, avec cinq règles d'essai écrites contre le contrat de §4 : un X01 conforme à `GAMES.md` §3 (COM-1 à COM-7, X01-1, X01-3), un jeu à élimination, un jeu dépendant de la position, et deux jeux qui refusent de se créer (un squelette et une erreur d'option). 56 altérations d'une ligne de `DartCore` ou de `DartTestSupport` ont été essayées une à une : ces tests en détectent 55, et la dernière ne change aucun comportement ;
- les tests de fumée des quatre autres cibles n'affirment que ce qui reste vrai quand les autres lots livrent : ils ne comptent pas les jeux en squelette et n'appellent aucun corps `unimplemented()`.

**Vérification refaite après les corrections de la vérification du lot F0** (même machine, même jour, dossier de construction neuf) :

- chaque défaut de code a d'abord été reproduit par un test écrit avant la correction : sur l'ancien code, la volée d'une partie finie à la limite de manches n'était pas vide (sur les règles d'essai comme sur « Meilleur score »), `hit(at:)` arrêtait le processus de test sur une coordonnée `NaN`, `clockwiseDegrees` rendait 360 pour quatre points voisins de l'axe du 20, et `S05`, `T020`, `D007`, `005` et `020` étaient lus ;
- `swift build`, `swift test` et `xcodebuild -scheme DartUI -destination 'generic/platform=iOS Simulator' build` passent sans erreur ni avertissement ; `swift run SnapshotTool` écrit `skeleton@phonePortrait.png` en français et en anglais ;
- `swift test` passe 183 tests Swift Testing : 134 dans `DartCoreTests` (dix suites), 12 dans `DartGamesTests`, 17 dans `DartVisionTests`, 7 dans `DartAudioTests` et 13 dans `DartUITests`. Les quatre tests neufs de `DartCoreTests` éprouvent la volée vidée à la limite de manches, l'alignement de `currentTurn` sur `snapshot.turn.darts` après chacune de 4 800 opérations tirées au sort (lancers, confirmations, annulations, corrections, suppressions) sur quatre configurations des règles d'essai, les coordonnées non finies et l'intervalle de `clockwiseDegrees`. Sept altérations, une pour chaque ligne ou condition corrigée, ont été essayées une à une dans une copie : ces tests les détectent toutes ;
- le test des descripteurs de `DartGamesTests` compare maintenant les quatorze phrases `pitch` mot pour mot à `GAMES.md` §n.1 : un lot de jeux qui reprend un fichier de règles ne peut plus en changer une sans qu'un test échoue ;
- les 43 fichiers imprimés présents dans le dépôt (les 42 du paquet et `.gitignore`) sont de nouveau identiques à ce document, octet pour octet.

**Ce qui n'avait pas été vérifié à la fin du lot F0** : aucun moteur de jeu n'existe hormis l'exemple « Meilleur score » (les règles d'essai des tests ne sont pas une livraison) ; `DartAudio` et `DartUI` sont pour l'essentiel des signatures : seuls les listings donnés comme complets ont un vrai corps (thème, localisation, adaptations, `SilentSoundPlayer`, `FakeScanService`, corps minimal de `CameraModel`, initialiseur de `PlayViewModel`) ; le comportement décrit en §8.5 à §8.7 (source d'une partie, file de commandes, certitude au bord d'une cible) n'existe qu'en texte, aucun code ne l'éprouve encore ; les membres algorithmiques de `DartVision` sont des corps qui plantent ; l'application construite n'a pas été lancée, et rien n'a tourné sur un appareil réel.

**Intégration de la vague 1** (lots G1, G2, G3, G4, V1, V4, A1, U1 et X1 ; même machine, même jour). Les neuf lots sont fusionnés dans le dépôt ; aucun n'a touché un fichier hors de ses chemins (§13.2), et la fusion n'a produit aucune collision de noms (§13.4). Corrections apportées à la fusion, le dépôt et les documents disant de nouveau la même chose :

- **une seule ligne de code** : `ShanghaiRules` donnait encore un résumé de volée (« Volée : 3 ») après une fin à la limite de manches, dont la volée est vide ; c'était le seul des quatorze jeux. Il rend maintenant `nil`, comme les treize autres et comme le dit désormais §5.6 ;
- §5.4 : le listing de `HighScoreRules.swift` est la version terminée par le lot G1 (phrase et lignes des résultats, pas de résumé de volée après une fin à la limite de manches) ; c'est le seul listing imprimé touché ;
- §5.5 et §5.6 : ce que les moteurs livrés font là où le texte se taisait (détail du Tour de l'horloge, cibles à venir de La Moitié, étiquettes de Shanghai sur les cases, unités accordées au nombre, masculin générique des résultats, présentation après une fin à la limite de manches) ;
- §7.3, §7.5 et §7.7 : les phrases anglaises que la table ne donnait pas, et les règles ajoutées par le lot A1 (phrase `low` jamais commencée si une phrase `high` du lot la couperait, délai de 12 s, quatre phrases en attente au plus, élision, préchauffage seulement quand l'annonce s'entend, fréquence d'échantillonnage hors limites) ;
- §8.4.3 : bulls aux rayons de la géométrie, pictogramme plat sous 64 pt, surface d'un disque non assombrie, choix laissé à l'écran de jeu pour l'assombrissement autour d'un anneau de finition ; §8.9 et §9.3 : la raison donnée à `CFBundleLocalizations` était inexacte ;
- `GAMES.md`, `VISION.md` et `DESIGN.md` reçoivent les précisions de leurs lots, sans changement de règle, de vecteur ni d'API (journal en tête de chacun) ; dans `VISION.md`, le seuil de l'inverse d'une homographie s'applique après équilibrage (§14), et le contrat du réducteur avec le moteur est écrit (6.3, §14).

Vérifié après la fusion et ces corrections : `swift build` sans avertissement ; `swift test` passe 1 136 tests Swift Testing, 134 dans `DartCoreTests`, 480 dans `DartGamesTests`, 208 dans `DartVisionTests`, 195 dans `DartAudioTests` et 119 dans `DartUITests` ; les tests communs du lot G1 tournent sur les quatorze jeux, aucun n'est sauté ; `xcodebuild -scheme DartUI -destination 'generic/platform=iOS Simulator' build` passe sans avertissement ; `swift run SnapshotTool` écrit les quatre écrans du socle, en français et en anglais ; la coquille iOS se construit pour les simulateurs iPhone 17 et iPad Pro 13 pouces (M5), et l'application, lancée dans les deux, reste en vie sur un écran d'accueil encore vide (`HomeScreen` est au lot U2). Des 46 fichiers imprimés, les 38 listings complets sont identiques au dépôt octet pour octet ; les huit autres sont des squelettes de F0 que leur lot a remplis (`KillerRules.swift`, `Components.swift`, `DartboardView.swift`, `Persistence.swift`, `AppModel.swift`, `KernelSnapshots.swift`) ou supprimés (`DartAudioAPI.swift`, réparti dans les fichiers de §7.4, et `Unimplemented.swift` de `DartAudio`), signatures inchangées, comme le prévoit la convention des listings.

Toujours pas vérifié : les lots des vagues 2 à 4 (calibrage, détection, moteur de scan, écrans de jeu et de caméra) ; ce que l'on entend et ce que l'on sent (effets, voix, vibrations, session audio en mode silencieux, interruptions) ; rien n'a tourné sur un appareil réel.

**Intégration de la vague 2** (lots V2, V3 et U2 ; revues indépendantes des neuf lots de la vague 1, notées RG1, RG2, RV, RA et RU ; même machine, même jour). Les huit unités sont fusionnées ; aucune n'a touché un fichier hors de ses chemins (§13.2), et la fusion n'a produit aucune collision de noms (§13.4). Les revues ont trouvé et corrigé quatre défauts dans le code de la vague 1, chacun d'abord reproduit par un test : sur la cible de l'écran, avec `onTap` **et** `onLongPress`, aucun tap ne posait de fléchette (lot U1, `DartboardView`) ; la ligne A14 du réducteur reprenait une référence vide sans contrôle de dérive (lot V4) ; « Au tour de Yves » n'était pas élidé (lot A1) ; un test en temps réel de `SyntheticFrameSource` échouait sous charge (lot V1, test seul). Corrections et précisions de la fusion, le dépôt et les documents disant de nouveau la même chose :

- §8.4.7 : le listing de `PlayViewModel` imprime six membres ajoutés par le lot U2 et dont le lot U3 a besoin (`handle(_:)`, `resolvePending(with: BoardTap)`, `confirmBoardEmpty()`, `evidenceImage(for:)`, `rescore(_:tip:)`, `hasSource`) ; aucune signature imprimée ne change ;
- §8.6, §8.8, §8.10 : ce que le lot U2 a fait là où le texte se taisait ou ne se réalisait pas tel quel (démarrage idempotent, partie reprise finie, `confirmDart` resynchronise, un seul `Layout` pour l'écran de jeu, barre de navigation du système), l'appui long signalé au relâcher, et l'ajout d'un champ à un réglage, qui est un changement incompatible ;
- deux lignes de code à la fusion : un sous-titre de `ToggleRow` passe à la ligne au lieu d'être coupé (lot U1) ; « Au tour de … » sur l'écran de jeu est la phrase de l'annonce, qui élide (« Au tour d'Alice »), au lieu d'une chaîne qui n'élidait jamais (lot U2) ;
- §7.2, §7.5 : le commentaire de `InterfaceCue.dartUndecided` dit ce que la table de §7.3 fait (« À vérifier » est dit, le score ne l'est pas) ; règle d'élision devant Y ;
- `VISION.md` reçoit les recettes que les lots V2 et V3 ont dû remplacer, deux valeurs par défaut (`tipCapCorrection` 1,1 mm ; quatre points par case dans la postérieure) et des commentaires de son listing, et les lignes 1 et A14 et `beginVisit` précisées par la revue du réducteur (journal en tête) ; `GAMES.md` précise le `player` de `lifeLost` au Killer et les couleurs du Combat (journal en tête).

Vérifié après la fusion et ces corrections : `swift build` sans avertissement, construction propre comprise ; `swift test` passe 1 421 tests Swift Testing, 134 dans `DartCoreTests`, 506 dans `DartGamesTests`, 336 dans `DartVisionTests`, 239 dans `DartAudioTests` et 206 dans `DartUITests` ; `swift test -c release --filter DartVisionTests` passe ses 336 tests, suites lourdes comprises ; `xcodebuild -scheme DartUI -destination 'generic/platform=iOS Simulator' build` passe sans avertissement ; `swift run SnapshotTool` écrit 33 écrans en français et en anglais, comparés aux maquettes pour l'accueil, la préparation du Killer, le jeu du Killer sur iPhone et iPad, le X01, la correction et les résultats ; la coquille iOS se construit pour les simulateurs iPhone 17 et iPad Pro 13 pouces (M5), et l'application, lancée dans les deux, reste en vie sur l'accueil et ses quatorze jeux, en thème sombre. Des 46 fichiers imprimés, 37 sont identiques au dépôt ; les neuf autres sont les huit squelettes de la vague 1 et `PlayViewModel.swift`, rempli par le lot U2, signatures inchangées.

Toujours pas vérifié : les lots de la vague 3 (moteur de scan, écrans de caméra) ; aucune image réelle n'est passée dans le calibrage ni dans la détection, et tous les seuils restent synthétiques ; le parcours de jeu n'a été joué que par les tests et les instantanés, pas au doigt dans le Simulateur (tap, appui long, feuilles, alertes) ; ce que l'on entend et ce que l'on sent ; rien n'a tourné sur un appareil réel.

**Intégration de la vague 3** (lots V5 et U3 ; revues indépendantes des lots V2 et V3, notée RV2, et du lot U2, notée RU2 ; même machine, 2026-11-11). Les quatre unités sont fusionnées ; aucune n'a touché un fichier hors de ses chemins (§13.2), et la fusion n'a produit ni collision de noms (§13.4) ni erreur de construction : `LiveScanService`, écrit contre le squelette de `ScanSession`, se construit et tourne tel quel sur la vraie session du lot V5. Les revues ont trouvé et corrigé dix défauts dans le code de la vague 2, chacun d'abord reproduit par un test. Trois dans la vision : une ombre dure au-delà de la pointe prise pour la pointe à confiance haute ; un plateau tourné sur son support déclaré sain ; une pointe non finie comptée `MISS` certain. Sept dans le parcours de jeu : fermer la vue agrandie posait une fléchette ; le « × » de la correction déplaçait la sélection ; l'image de preuve couvrait ce « × » ; le réticule convertissait ses déplacements avec un côté fixe de 350 pt (41 % trop long sur iPad) ; un tap sur l'image de preuve ne faisait rien ; la question de la volée courte restait affichée ; des boutons faisaient moins de 44 pt. Corrections et précisions de la fusion, le dépôt et les documents disant de nouveau la même chose :

- **une sonde de bout en bout**, hors dépôt, relie pour la première fois les quatre couches : `ScanSession` sur un film de synthèse, calibrage par `CalibrationFlowModel` et `BoardCalibrator`, `LiveScanService`, `CameraModel`, `CameraInputSource`, puis le `PlayViewModel` d'un Killer. Ce qu'elle montre est en §8.7 ;
- **un défaut entre deux lots, trouvé par la sonde** : `CameraModel` (lot U3) envoyait un calibrage avant sa configuration, alors que le moteur (lot V5) fixe le rodage au moment où il installe le calibrage. Après un redémarrage, un calibrage vérifié plafonnait de nouveau ses trois premières fléchettes à 0,84. La configuration part maintenant en premier, à la revalidation comme à l'adoption, et `CameraFlowInstallOrderTests` le garde (§8.7 ; `VISION.md` §6.5) ;
- `PlayScreen` ne lie plus sa feuille de correction pendant qu'une couverture caméra est affichée : la couverture présente la sienne (§8.6 ; correction faite à la lecture du code, non essayée au doigt) ;
- le test T7 du lot V3 compte les fausses parmi les hautes, au plus 1 % (`VISION.md` §10.2) : resserré, il passe sans aucune haute fausse ;
- §6.5, §8.3, §8.4.8 (commentaire du listing des signatures du lot U3, aucune signature), §8.6, §8.7, §8.11, §13.4 (règle 7) et §14 : ce que les lots V5, U3 et les deux revues ont fait là où le texte se taisait ou ne se réalisait pas tel quel ; deux questions nouvelles en §15 ;
- `VISION.md` reçoit les recettes que le lot V5 a dû remplacer, les deux règles changées par la revue des lots V2 et V3, et quatre limites (journal en tête). `GAMES.md` et `DESIGN.md` ne changent pas.

Vérifié après la fusion et ces corrections : `swift build` sans avertissement, construction propre comprise ; `swift test` passe 1 566 tests Swift Testing, 134 dans `DartCoreTests`, 506 dans `DartGamesTests`, 396 dans `DartVisionTests`, 239 dans `DartAudioTests` et 291 dans `DartUITests`, avec trois problèmes connus déclarés par `withKnownIssue` (P2, fléchettes croisées, `VISION.md` §11.1) ; `swift test -c release --filter DartVisionTests` passe ses 396 tests, suites lourdes comprises (X13 : médiane 0,11 mm et p95 1,24 mm à 1,8 px/mm, médiane 0,31 mm et p95 0,66 mm à 1,2 px/mm ; une fléchette sort 9 images, 300 ms, après son arrêt) ; `xcodebuild -scheme DartUI -destination 'generic/platform=iOS Simulator' build` passe sans avertissement ; `swift run SnapshotTool` écrit 51 écrans par langue, dont les 18 du parcours caméra ; la coquille iOS se construit pour les simulateurs iPhone 17 et iPad Pro 13 pouces (M5), et l'application, lancée dans les deux, reste en vie sur l'accueil et ses quatorze jeux, en saisie manuelle comme en mode caméra (« Cible à calibrer » : sans caméra arrière, le Simulateur passe par la source de démonstration, §8.7) ; le journal unifié ne montre aucune faute du code de l'application : deux fautes du cadre d'accessibilité du système (`unsafeForcedSync`), déjà présentes en vague 2, et des erreurs du système (audio, voix, capture simulée du Simulateur). Des 46 fichiers imprimés, 36 sont identiques au dépôt ; les dix autres sont les huit squelettes de la vague 1, `PlayViewModel.swift` et `CameraModel.swift`, remplis par leur lot, signatures inchangées.

Toujours pas vérifié : rien n'a tourné sur un appareil réel (`CameraFrameSource` n'a jamais livré une image : autorisation, verrouillage de l'exposition, rotation, 4K à 30 images/s, interruptions, deux aperçus sur une session) ; aucune image réelle n'est passée dans le calibrage ni dans la détection, et tous les seuils restent synthétiques ; les écrans caméra n'ont été joués que par les tests, la sonde et les instantanés, pas au doigt dans le Simulateur (poignées et loupe, « touchez le 20 », scan en direct, mode photo, feuilles présentées depuis une couverture) ; ce que l'on entend et ce que l'on sent. Reste le lot I1.

**Lot I1, intégration finale** (même machine, 2026-11-11). Le lot a livré ce que §13.2 lui demande et a corrigé ce que ses contrôles ont trouvé :

- **Tests d'intégration** (`DartGamesTests/Integration/`, 21 tests) :
  - `GameRegistry.standard.skeletonGames` est vide, et le registre a les quatorze ids dans l'ordre ;
  - une partie entière de chacun des quatorze jeux passe par le registre et `GameMatch`, avec annulation, une correction et souvent un fantôme retiré. Chaque valeur attendue est calculée à la main depuis `GAMES.md` ;
  - 26 parties entières de Killer, aux quatre niveaux, de 2 joueurs au maximum du niveau. Chaque fléchette est comparée à `GAMES.md` §5.4, le classement à §5.6, et chaque journal est rejoué de quatre façons : par le registre, en JSON, préfixe par préfixe, et en annulant tout puis en rejouant tout ;
  - une modification de la règle d'armement dans le modèle du test fait échouer 244 vérifications.
- **Instantanés** (§8.11) : six écrans de partie ajoutés, et tous les écrans de l'application rendus sur téléphone en portrait et sur iPad. Le scan en direct est alimenté par le moteur du X01. Les fichiers touchés sont `GameFlowSnapshots.swift` et `GameFlowFixtures.swift` (lot U2), `CameraFlowSnapshots.swift` et `CameraFlowFixtures.swift` (lot U3). `SnapshotTool.swift` ne change pas.
- **Comparaison aux maquettes** : les PNG ont été regardés à côté des maquettes rendues par Chrome sans interface. Un défaut net est corrigé dans `HomeScreen.swift` (lot U2) : le titre de la carte caméra de l'accueil (« Cible calibrée ») tombait à environ 12 pt, plus petit que sa ligne de détail, à cause d'un `minimumScaleFactor`. Il est maintenant à 15 pt, et il passe à la ligne au lieu de rétrécir. Dans le Simulateur, le titre s'affiche à sa taille, en anglais comme en français. Les écarts qui relèvent du propriétaire sont laissés tels quels (§15 et `README.md`).
- **Fichiers supprimés** : `DartUI/Support/Unimplemented.swift`. Le paquet ne contient plus aucun `unimplemented()` ni `StubView`, pas même dans un commentaire (deux commentaires de tests reformulés, lots F0 et U1).
- **Identifiant d'application** : `project.yml` et `Config/Base.xcconfig` (lot X1) le lisent dans `DART_SCANNER_BUNDLE_ID`, pour que `Config/Local.xcconfig` puisse le changer (§9.3, §9.4). Essai : avec un `Local.xcconfig` temporaire, `xcodebuild -showBuildSettings` donne l'identifiant et l'équipe du fichier. Sans lui, il donne `com.example.dartscanner`.
- **`README.md`** à la racine, en français.

Vérifié après ces changements :

- `swift build` sans avertissement, construction propre des tests comprise ;
- `swift test` passe 1 587 tests Swift Testing, avec les trois problèmes connus de P2 :

  | Cible | Tests |
  |---|---|
  | `DartCoreTests` | 134 |
  | `DartGamesTests` | 527 |
  | `DartVisionTests` | 396 |
  | `DartAudioTests` | 239 |
  | `DartUITests` | 291 |

- `swift test -c release --filter DartVisionTests` passe ses 396 tests ;
- `xcodebuild -scheme DartUI -destination 'generic/platform=iOS Simulator'` passe sans avertissement ;
- `swift run SnapshotTool` écrit 78 PNG par langue ;
- l'application se construit pour les simulateurs iPhone 17 et iPad Pro 13 pouces (M5). Lancée par `xcrun simctl` dans les deux, elle reste en vie sur l'accueil et ses quatorze jeux, en saisie manuelle. Sur iPhone, elle a aussi été lancée en mode caméra (« Board not calibrated / Calibrate », puis « Cible à calibrer » en français) ;
- le journal unifié ne montre que les deux fautes du cadre d'accessibilité déjà vues (`unsafeForcedSync`) et des erreurs du système.

Des 46 fichiers imprimés : 35 sont identiques ; 8 sont des squelettes remplis par leur lot ; 3 sont absents, à savoir les deux fichiers de `DartAudio` et `DartUI/Support/Unimplemented.swift`, supprimé par I1.

Toujours pas vérifié :

- rien n'a tourné sur un iPhone ni sur un iPad réels, et aucune image réelle n'est passée dans la vision ;
- aucun écran n'a été joué au doigt dans le Simulateur, car seul `xcrun simctl` a servi : lancement, réglages écrits dans les préférences, langue, captures d'écran et journal ;
- ce que l'on entend et ce que l'on sent.

**Corrections de la revue finale** (deux relectures adverses, l'une du parcours de jeu, l'autre du parcours caméra ; même machine, 2026-11-11). Neuf défauts, chacun d'abord reproduit par un test qui échouait sur l'ancien code (`GameFlowReviewFinalTests`, 6 tests, et `CameraFlowReviewFinalTests`, 8 tests) :

- **Résultats sans défilement** (lot U2) : un Killer à 8 joueurs, ou toute partie sur un iPhone en paysage, coupait la ligne d'annulation et « Changer de jeu ». Le haut défile, les deux boutons restent fixés (§8.6, §8.11) ;
- **iPhone en paysage** (lot U2) : la colonne de droite ne laissait aucune place aux joueurs des jeux à gabarit « score », et un bandeau couvrait la carte du joueur courant ou la liste. Sous 560 pt de haut, les actions passent sous la cible, la carte perd son très grand nombre et le bandeau se pose sur la cible (§8.8) ;
- **Feuille de correction** (lot U2) : 690 pt sans défilement, son « × » et « Valider » sortaient d'une feuille d'iPhone en paysage. Elle défile, « Valider » reste fixé, la loupe passe à 150 pt sous 500 pt de haut (§8.6) ;
- **« Changer de jeu »** (lot U1) : `closeGame` vide `app.path` ; on revenait à la préparation du même jeu (§8.5) ;
- **« Pas encore »** (lot U3) : la vision n'est plus armée sur une cible qui porte encore des fléchettes ; elle l'est à la confirmation « Elle est vide ». La table « Commandes » change (§8.7, §14). La sonde de bout en bout de la revue (vraie `ScanSession` sur un film de synthèse, deux fléchettes retirées après « Pas encore ») ne donne plus aucune fléchette ;
- **Photo unique** (lot U3) : un fil de fer tourné d'un secteur demande de toucher le vrai 20, comme le calibrage ; un calibrage `poor` donne des fléchettes « à vérifier » (§8.7) ;
- **Revue d'un scan** (lot U3) : le retour est inactif pendant le scan et sur la revue, avec une attente de 8 s au plus ; « Scanner » demande les fléchettes que la vision n'a pas rendues ; la revue compte avec les seuils de la source (`CameraModel.inputSource`, §8.4.8, §8.7, §14).

Quatre tests existants changent avec le comportement qu'ils décrivaient, et rien d'autre : la commande `arm(boardConfirmedEmpty: false)` n'est plus déposée (`CameraFlowCommandTests`, `CameraFlowColdStartTests`), « Cible vide » est actif sous `.needsEmptyBoard` et « Scanner » demande 2 fléchettes et non 1 quand une fléchette saisie au doigt et une en attente sont dans la volée (`CameraFlowPhotoTests`).

Vérifié après ces corrections : `swift build` sans avertissement, construction propre des tests comprise ; `swift test` passe 134 tests dans `DartCoreTests`, 527 dans `DartGamesTests`, 396 dans `DartVisionTests` (les trois problèmes connus de P2) et 305 dans `DartUITests` ; `swift test -c release --filter DartVisionTests` passe ses 396 tests ; `xcodebuild -scheme DartUI -destination 'generic/platform=iOS Simulator'` passe sans avertissement ; `swift run SnapshotTool` écrit 78 PNG par langue ; l'application se construit pour les simulateurs iPhone 17 et iPad Pro 13 pouces (M5) et s'ouvre sur l'accueil.

Non vérifié, à cause de la machine et non du code : ce jour-là, le service audio du Mac ne répondait plus (« Cleanup: RPC timeout. Apparently deadlocked. Aborting now. »). L'application s'arrêtait environ 12 s après son lancement, dans `EffectsPlayer` (`AVAudioEngine.outputNode`), et la version d'avant ces corrections, qui restait en vie à 02 h 13, s'arrêtait exactement de la même façon. `DartAudioTests` s'arrêtait aussi, dans `AVAudioPlayerNode.play()`, sans qu'aucun fichier de `DartAudio` ait changé. Reste à refaire sur une machine dont le son répond : ces tests, et le lancement de l'application.

## Sommaire

1. [Vue d'ensemble](#1-vue-densemble)
2. [Arborescence du dépôt](#2-arborescence-du-dépôt)
3. [Package.swift](#3-packageswift)
4. [DartCore](#4-dartcore)
5. [DartGames](#5-dartgames)
6. [DartVision](#6-dartvision)
7. [DartAudio](#7-dartaudio)
8. [DartUI](#8-dartui)
9. [Coquille iOS (`App/`)](#9-coquille-ios-app)
10. [Flux de données](#10-flux-de-données)
11. [Règles de concurrence](#11-règles-de-concurrence)
12. [Stratégie de test et commandes](#12-stratégie-de-test-et-commandes)
13. [Plan de réalisation](#13-plan-de-réalisation)
14. [Arbitrages et écarts avec les autres documents](#14-arbitrages-et-écarts-avec-les-autres-documents)
15. [Questions ouvertes pour le propriétaire](#15-questions-ouvertes-pour-le-propriétaire)

**Guide de lecture par lot** (les lots sont définis en §13) :

| Lot | À lire ici | À lire ailleurs |
|---|---|---|
| F0 | §2, §3, §4, §5.2 à §5.4, §6.3, §6.4, §7.2, §8.4, §8.8 (listing `PlayLayout.swift`), §8.11, §12, §13 | `VISION.md` §9.2 à §9.4 ; `GAMES.md` §1, §2, §3 (X01 : règle d'essai des vecteurs COM-1 à COM-7 dans `DartCoreTests`) et, pour chacun des treize jeux en squelette, §n.1 (« En une ligne ») et §n.2 (options) |
| G1 à G4 | §4.2 (`ImpactPoint`), §4.3, §4.5 à §4.8, §5, §12.1 | `GAMES.md` §2 et la section de chaque jeu ; pour Radar, §2.13 |
| V1 à V5 | §4.2, §4.9, §6, §11, §12 | `VISION.md` en entier |
| A1 | §4.5, §7, §11, §12.1 | `GAMES.md` §2.10 et les tables d'événements §n.8 |
| U1 | §4, §8.1 à §8.5, §8.8 à §8.11, §11 | `DESIGN.md` et les maquettes |
| U2 | §4.4 à §4.8, §7.2, §7.3, §8.1 à §8.6, §8.7 (« Cycle de vie » seulement : quand appeler `camera.activate()`), §8.8 à §8.11, §10, §11 | `DESIGN.md`, maquettes, `GAMES.md` §2 (dont §2.13) |
| U3 | §6, §8.3, §8.4, §8.7 à §8.9, §8.11, §10, §11 | `VISION.md` §2, §4.7 à §4.10, §6.3 (table du déclenchement manuel), §6.5, §7.4, §7.5, §8, §9.2 ; `DESIGN.md` |
| X1 | §9, §12.2 | — |
| I1 | §8.11, §12, §13 | maquettes |

Tous les lots lisent en plus §13.1 et §13.4 : la règle de noms d'un module partagé, et le préfixe de leur lot.

---

## 1. Vue d'ensemble

### 1.1 Cibles et dépendances

```
   App/  (coquille iOS, projet généré par XcodeGen)        SnapshotTool  (exécutable macOS)
     │  importe uniquement DartUI                               │  importe DartUI et DartCore
     ▼                                                          ▼
   ┌──────────────────────────────── DartUI ────────────────────────────────┐
   │  écrans SwiftUI, modèles de vue, navigation, persistance, localisation │
   └───────┬──────────────────────┬──────────────────────┬──────────────────┘
           ▼                      ▼                      ▼
       DartGames              DartVision             DartAudio
   (règles des 14 jeux)   (calibrage, détection)   (sons, voix, vibrations)
           └──────────────────────┼──────────────────────┘
                                  ▼
                              DartCore
        (cible, Hit, joueurs, aléatoire, contrat de jeu, journal, événements)
```

| Cible | Rôle | Dépend de | Frameworks Apple | Ressources |
|---|---|---|---|---|
| `DartCore` | Géométrie de la cible, `Hit` et sa notation, point d'impact, joueurs, générateur aléatoire, contrat de jeu générique, noyau des tours, journal avec annulation et correction, événements | — | Foundation | aucune |
| `DartGames` | Les règles des quatorze jeux de `GAMES.md` et le registre | `DartCore` | Foundation | aucune |
| `DartVision` | Calibrage, détection, confiance, machine à états, capture (`VISION.md`) | `DartCore` | Foundation, simd, CoreGraphics, ImageIO, CoreVideo, AVFoundation (un fichier) | aucune |
| `DartAudio` | Effets synthétisés, annonce vocale, vibrations, session audio ; la table événement → son | `DartCore` | AVFoundation, CoreHaptics, UIKit (iOS) | aucune |
| `DartUI` | Tous les écrans, les modèles de vue, la navigation, l'abstraction d'entrée, la persistance, la localisation | les quatre autres | SwiftUI, Observation, PhotosUI, AVFoundation, UIKit (iOS) | tables `.strings` fr et en |
| `SnapshotTool` | Rend les écrans clés en PNG avec `ImageRenderer` (macOS seulement) | `DartUI`, `DartCore` | SwiftUI, AppKit | aucune |
| `DartTestSupport` | Aide de test : le petit langage des vecteurs de `GAMES.md` §2.11 | `DartCore` | Foundation | aucune |

Règles de dépendance, vérifiées par le compilateur puisqu'elles sont dans `Package.swift` :

- `DartGames`, `DartVision` et `DartAudio` ne se connaissent pas. Tout ce qu'ils partagent est dans `DartCore`.
- `DartUI` est le **seul** endroit qui relie un jeu, la caméra et le son.
- `App/` n'importe que `DartUI` et ne contient aucune logique.
- Aucune dépendance tierce.

### 1.2 Principes

1. **Une partie est une donnée.** Une partie est le triplet (configuration avec sa graine, joueurs, journal des entrées). Son état est une fonction pure de ce triplet (`GAMES.md` §2.4). Annuler ou corriger, c'est modifier le journal puis tout rejouer. Ce mécanisme est écrit une seule fois, dans `DartCore` (`GameMatch`), pour tous les jeux.
2. **Un seul contrat pour tous les jeux.** `DartUI` affiche et pilote n'importe quel jeu à travers `GameDescriptor` (accueil, préparation), `GameMatch` (entrées) et `GameSnapshot` (affichage), sans jamais connaître son type. Ajouter un jeu ne touche ni `DartUI` ni `DartAudio`, sauf s'il apporte un nouvel événement. Ce qu'un jeu a de particulier passe par une donnée du contrat, jamais par un test sur son identifiant : `dependsOnPosition` (Radar), `confirmsShortTurn` (Golf), la zone `disc`, `winnerTitle` (Football).
3. **Les règles communes vivent une seule fois.** Phases, trois fléchettes, confirmation du tour, joueurs éliminés sautés, manches, limite de manches : c'est le noyau `TurnBasedEngine` de `DartCore`. Un jeu n'écrit que ses règles propres (`TurnBasedRules`).
4. **La vision propose, le jeu dispose.** `DartVision` émet des observations ; `DartUI` décide de les envoyer au jeu, de les marquer « à vérifier » ou d'attendre la réponse du joueur. Une fléchette venue de la caméra et une fléchette saisie au doigt entrent par la même porte (`PlayViewModel.receive`). Aucun jeu ne dépend de la caméra.
5. **Les événements font le son.** Chaque entrée acceptée produit une liste d'événements ; une seule table (`CueMapping`, dans `DartAudio`) les transforme en sons, phrases et vibrations.
6. **Tout se vérifie sur macOS.** Tout le paquet compile pour macOS ; les API propres à iOS sont derrière `#if os(iOS)` dans des fichiers nommés (§8.8, §7.4, `VISION.md` §2.4).

### 1.3 Vocabulaire

| Terme | Sens | Nom dans le code |
|---|---|---|
| fléchette | un lancer | `Hit` (la case), `DartRecord` (l'entrée du journal) |
| tour, volée | le passage d'un joueur, 3 fléchettes au plus | *turn* ; *visit* dans `DartVision` |
| manche | un tour de chaque joueur encore en jeu | *round* |
| journal | la liste ordonnée des entrées acceptées | `GameMatch.entries` |
| position enregistrée | l'endroit où la pointe est plantée, en millimètres nominaux, quand il est connu | `DartRecord.position` |
| point d'impact | ce qu'un jeu dépendant de la position lit : la position enregistrée ou, à défaut, la position canonique de la case | `ImpactPoint`, `TurnContext.impact` |
| lot | un paquet de travail du plan (§13) | F0, G1, V3, U2… |

---

## 2. Arborescence du dépôt

La colonne de droite donne le lot propriétaire (§13). **Règle de propriété** : le lot F0 crée tous les fichiers de squelette ; ensuite chaque fichier ou dossier appartient au lot indiqué, et aucun autre lot ne le modifie.

```
dart-scanner/
├── .gitignore                                        F0
├── README.md                                         I1
├── project.yml                                       X1
├── Config/
│   ├── Base.xcconfig                                 X1
│   └── Local.xcconfig                                non suivi par git (équipe de signature, §9.4)
├── App/                                              X1
│   ├── DartScannerApp.swift
│   ├── Info.plist                                    généré par XcodeGen, non suivi par git
│   ├── Assets.xcassets/
│   │   ├── Contents.json
│   │   ├── AppIcon.appiconset/   Contents.json, AppIcon-1024.png
│   │   └── AccentColor.colorset/ Contents.json
│   └── en.lproj/InfoPlist.strings
├── docs/                                             GAMES.md, VISION.md, DESIGN.md, ARCHITECTURE.md, design/mockups/
└── DartKit/
    ├── Package.swift                                 F0 (figé)
    ├── Sources/
    │   ├── DartCore/                                 F0 (figé, §4)
    │   │   ├── Board/      BoardPoint.swift  Hit.swift  BoardZone.swift  BoardGeometry.swift  ImpactPoint.swift
    │   │   ├── Players/    Player.swift
    │   │   ├── Random/     SeededRandom.swift
    │   │   ├── Text/       LocalizedText.swift
    │   │   └── Game/       GameID.swift  GameOptions.swift  GameDescriptor.swift  GameConfiguration.swift
    │   │                   GameInput.swift  GameEvent.swift  GameSnapshot.swift  Ranking.swift
    │   │                   GameEngine.swift  GameRegistry.swift  GameMatch.swift
    │   ├── DartTestSupport/
    │   │   └── VectorDSL.swift                       F0 (figé, §12.1)
    │   ├── DartGames/
    │   │   ├── GameCatalog.swift                     F0 (figé, §5.2)
    │   │   ├── X01/  Cricket/  HighScore/            G1
    │   │   ├── Killer/  AroundTheClock/  Shanghai/   G2
    │   │   ├── HalveIt/  MoonLanding/  Fight/  Conqueror/    G3
    │   │   └── BeerTap/  Football/  Radar/  Golf/    G4
    │   ├── DartVision/                               répartition des types par fichier : VISION.md §9.3
    │   │   ├── DartCoreBridge.swift                  V1
    │   │   ├── Geometry/  Imaging/  Canvas/  Synthetic/      V1
    │   │   ├── Calibration/                          V2, sauf LightingCheck.swift : V3
    │   │   ├── Detection/  Confidence/  Photo/       V3
    │   │   ├── Scan/       ScanEvents.swift  ScanStateMachine.swift          V4
    │   │   ├── Scan/       MotionGate.swift  ScanEngine.swift  ScanSession.swift   V5
    │   │   └── Capture/                              V5
    │   ├── DartAudio/                                A1 (§7)
    │   │   ├── DartAudioAPI.swift                    l'API publique de §7.2 ; A1 la répartit ensuite en fichiers
    │   │   └── Unimplemented.swift                   supprimé par A1
    │   ├── DartUI/
    │   │   ├── App/          AppModel.swift                                  U1
    │   │   ├── Design/       Theme.swift  Components.swift                   U1
    │   │   ├── Board/        DartboardView.swift                             U1
    │   │   ├── Support/      L10n.swift  PlatformShims.swift  Unimplemented.swift   U1
    │   │   ├── Persistence/  Persistence.swift                               U1
    │   │   ├── Input/        DartInput.swift                                 U1 (figé, §8.4.6)
    │   │   ├── Camera/       ScanServicing.swift                             U1 (figé, complet dès F0, §8.4.8)
    │   │   ├── Snapshots/    SnapshotCatalog.swift  KernelSnapshots.swift    U1
    │   │   ├── Home/  Setup/  Players/  Settings/  Play/  Results/           U2
    │   │   ├── Snapshots/    GameFlowSnapshots.swift                         U2
    │   │   ├── Camera/       CameraModel.swift                               U3 (corps minimal écrit par F0, §8.4.8)
    │   │   ├── Camera/       PlacementGuideView.swift (point d'entrée créé par F0, §8.4.10) ;
    │   │   │                 les autres fichiers sont créés par U3           U3
    │   │   ├── Calibration/  Scan/  Photo/                                   U3
    │   │   ├── Snapshots/    CameraFlowSnapshots.swift                       U3
    │   │   └── Resources/
    │   │       ├── fr.lproj/ Common.strings (U1)  Game.strings (U2)  Camera.strings (U3)
    │   │       └── en.lproj/ Common.strings (U1)  Game.strings (U2)  Camera.strings (U3)
    │   └── SnapshotTool/
    │       └── SnapshotTool.swift                    F0, puis I1 (§8.11)
    └── Tests/
        ├── DartCoreTests/                            F0
        ├── DartGamesTests/                           un fichier par jeu, au lot du jeu ; Common/ au lot G1 ;
        │                                             Integration/ au lot I1
        ├── DartVisionTests/                          des dossiers par lot : Math/ Rectify/ Imaging/ Support/ (V1),
        │                                             Calibration/ (V2), Detection/ Confidence/ Photo/ (V3),
        │                                             Reducer/ (V4), Engine/ (V5)
        ├── DartAudioTests/                           A1 (SmokeTests.swift créé par F0)
        └── DartUITests/                              Kernel/ (U1), GameFlow/ (U2), CameraFlow/ (U3)
```

`.gitignore` (lot F0) :

```
.build/
.swiftpm/
build/
DerivedData/
*.xcodeproj
App/Info.plist
Config/Local.xcconfig
.DS_Store
xcuserdata/
```

---

## 3. Package.swift

Fichier `DartKit/Package.swift` :

```swift
// swift-tools-version: 6.0
import PackageDescription

/// Warnings (not errors) for data races while the package stays in Swift 5 language mode.
let strict: [SwiftSetting] = [.enableExperimentalFeature("StrictConcurrency")]

let package = Package(
    name: "DartKit",
    defaultLocalization: "fr",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "DartCore", targets: ["DartCore"]),
        .library(name: "DartGames", targets: ["DartGames"]),
        .library(name: "DartVision", targets: ["DartVision"]),
        .library(name: "DartAudio", targets: ["DartAudio"]),
        .library(name: "DartUI", targets: ["DartUI"]),
        .executable(name: "SnapshotTool", targets: ["SnapshotTool"]),
    ],
    targets: [
        .target(name: "DartCore", swiftSettings: strict),
        .target(name: "DartGames", dependencies: ["DartCore"], swiftSettings: strict),
        .target(name: "DartVision", dependencies: ["DartCore"], swiftSettings: strict),
        .target(name: "DartAudio", dependencies: ["DartCore"], swiftSettings: strict),
        .target(
            name: "DartUI",
            dependencies: ["DartCore", "DartGames", "DartVision", "DartAudio"],
            resources: [.process("Resources")],
            swiftSettings: strict
        ),
        .executableTarget(name: "SnapshotTool", dependencies: ["DartUI", "DartCore"], swiftSettings: strict),

        // Test-only helpers (GAMES.md §2.11 vector DSL). Not a product: never linked into the app.
        .target(name: "DartTestSupport", dependencies: ["DartCore"], swiftSettings: strict),

        .testTarget(name: "DartCoreTests", dependencies: ["DartCore", "DartTestSupport"]),
        .testTarget(name: "DartGamesTests", dependencies: ["DartGames", "DartCore", "DartTestSupport"]),
        .testTarget(name: "DartVisionTests", dependencies: ["DartVision", "DartCore"]),
        .testTarget(name: "DartAudioTests", dependencies: ["DartAudio", "DartCore"]),
        .testTarget(
            name: "DartUITests",
            dependencies: ["DartUI", "DartGames", "DartVision", "DartAudio", "DartCore", "DartTestSupport"]
        ),
    ],
    swiftLanguageModes: [.v5]
)
```

- `swiftLanguageModes: [.v5]` au niveau du paquet : toutes les cibles sont en mode Swift 5. Le réglage `StrictConcurrency` fait remonter les fautes de concurrence comme **avertissements** ; chaque lot livre sans aucun avertissement.
- `defaultLocalization: "fr"` : un appareil qui n'est ni en français ni en anglais reçoit le français.
- `SnapshotTool` n'est construit que pour macOS : son fichier est entouré de `#if os(macOS)` et laisse un `main` vide ailleurs. Pour compiler les branches iOS du paquet, on construit le schéma `DartUI` (§12.2), jamais `DartKit-Package`.
- Schémas visibles par `xcodebuild -list` dans `DartKit/` : `DartCore`, `DartGames`, `DartVision`, `DartAudio`, `DartUI`, `SnapshotTool`, `DartKit-Package`.
- Aucune cible n'a de ressources hormis `DartUI`. Pas de String Catalog (`.xcstrings`) : il casse la construction avec les seuls Command Line Tools ; les tables sont des `.strings` simples (§8.9).

---

## 4. DartCore

### 4.1 Rôle et dépendances

`DartCore` possède tout ce que `GAMES.md` §2 appelle « règles communes » et tout ce que les autres cibles partagent :

- la cible en millimètres, l'ordre des secteurs, la conversion d'un point du plan en case (`BoardGeometry`) ;
- la case touchée et sa notation (`Hit`), les zones surlignables, cases ou disque (`BoardZone`) ;
- le point d'impact d'une fléchette pour un jeu qui dépend de la position, et la position canonique de chaque case (`ImpactPoint`) ;
- les joueurs (`Player`), le générateur aléatoire à graine (`SeededRandom`, `ringLayout`) ;
- les textes bilingues portés comme données (`LocalizedText`) ;
- le contrat de jeu : descripteur et schéma d'options, configuration, entrées, événements, instantané de présentation ;
- le noyau des tours (`TurnBasedRules`, `TurnBasedEngine`), le registre (`GameRegistry`) et la partie avec son journal (`GameMatch`).

Dépendance : Foundation seulement. `DartCore` ne contient ni SwiftUI, ni horloge, ni accès disque, ni état global modifiable. Tous ses types sont des valeurs `Sendable`.

Les dix-neuf fichiers ci-dessous sont **complets**. Le lot F0 les colle, écrit leurs tests (§12.1) et n'y ajoute rien. Après F0, `DartCore` est figé : un besoin nouveau passe par une modification de ce document.

### 4.2 Cible, cases et points

Repère, angles et rayons sont ceux de `VISION.md` §3.3 : origine au centre du bull, `+x` vers le 6, `+y` vers le 20, angle mesuré dans le sens horaire à partir de `+y`.

Fichier `DartKit/Sources/DartCore/Board/BoardPoint.swift` :

```swift
import Foundation

/// A point of the board plane in millimetres.
/// Origin at the bull centre, +x towards the 6 (right when facing the board), +y towards the 20 (up).
/// Same frame as VISION.md §3.3. Points that cross a module boundary are in NOMINAL coordinates.
public struct BoardPoint: Hashable, Codable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    /// Polar constructor: `x = r·sin α`, `y = r·cos α`, with α measured clockwise from +y (the middle of the 20).
    public init(radius: Double, clockwiseDegrees: Double) {
        let a = clockwiseDegrees * .pi / 180
        self.init(x: radius * sin(a), y: radius * cos(a))
    }

    public static let centre = BoardPoint(x: 0, y: 0)

    /// Distance from the bull centre, mm.
    public var radius: Double { (x * x + y * y).squareRoot() }

    /// Clockwise angle from +y in degrees, in [0, 360). 20 = 0°, 6 = 90°, 3 = 180°, 11 = 270°.
    public var clockwiseDegrees: Double {
        let a = atan2(x, y) * 180 / .pi
        guard a < 0 else { return a }
        // A tiny negative angle plus 360 rounds to 360 exactly: that point is on the +y axis.
        let turned = a + 360
        return turned < 360 ? turned : 0
    }
}
```

Fichier `DartKit/Sources/DartCore/Board/Hit.swift` :

```swift
import Foundation

/// One of the 63 values of GAMES.md §2.2: S1…S20, D1…D20, T1…T20, SB, DB, MISS.
/// Inner and outer single are the same value. Two darts with the same `Hit` have exactly the same effect.
public struct Hit: Hashable, Sendable, CustomStringConvertible {
    public enum Bed: Int, Sendable, CaseIterable {
        case miss, single, double, treble, outerBull, innerBull
    }

    public let bed: Bed
    /// Sector number 1...20 for single, double and treble; nil for the bulls and MISS.
    public let number: Int?

    private init(_ bed: Bed, _ number: Int?) {
        self.bed = bed
        self.number = number
    }

    /// Validating initialiser: nil when `number` does not fit `bed`.
    public init?(bed: Bed, number: Int?) {
        switch bed {
        case .single, .double, .treble:
            guard let n = number, (1...20).contains(n) else { return nil }
            self.init(bed, n)
        case .miss, .outerBull, .innerBull:
            guard number == nil else { return nil }
            self.init(bed, nil)
        }
    }

    /// MISS: off the scoring area, or a bounce-out.
    public static let miss = Hit(.miss, nil)
    /// SB: outer bull, 25.
    public static let outerBull = Hit(.outerBull, nil)
    /// DB: inner bull, 50. Counts as a double.
    public static let innerBull = Hit(.innerBull, nil)

    /// Precondition: `number` in 1...20.
    public static func single(_ number: Int) -> Hit {
        precondition((1...20).contains(number), "sector number out of range")
        return Hit(.single, number)
    }

    public static func double(_ number: Int) -> Hit {
        precondition((1...20).contains(number), "sector number out of range")
        return Hit(.double, number)
    }

    public static func treble(_ number: Int) -> Hit {
        precondition((1...20).contains(number), "sector number out of range")
        return Hit(.treble, number)
    }

    /// The 63 values in canonical order: S1…S20, D1…D20, T1…T20, SB, DB, MISS.
    public static let all: [Hit] =
        (1...20).map(Hit.single) + (1...20).map(Hit.double) + (1...20).map(Hit.treble) + [.outerBull, .innerBull, .miss]

    /// Points of GAMES.md §2.2: n, 2n, 3n, 25, 50, 0.
    public var points: Int {
        switch bed {
        case .miss: return 0
        case .single: return number ?? 0
        case .double: return 2 * (number ?? 0)
        case .treble: return 3 * (number ?? 0)
        case .outerBull: return 25
        case .innerBull: return 50
        }
    }

    /// 1 for singles and SB, 2 for doubles and DB, 3 for trebles, 0 for MISS.
    public var multiplier: Int {
        switch bed {
        case .miss: return 0
        case .single, .outerBull: return 1
        case .double, .innerBull: return 2
        case .treble: return 3
        }
    }

    /// D1…D20 and DB.
    public var isDouble: Bool { bed == .double || bed == .innerBull }
    /// T1…T20.
    public var isTreble: Bool { bed == .treble }
    /// SB and DB.
    public var isBull: Bool { bed == .outerBull || bed == .innerBull }
    public var isMiss: Bool { bed == .miss }

    // MARK: Notation

    public enum NotationStyle: Sendable {
        /// "S5", "D16", "T20", "SB", "DB", "MISS": tests, logs, persistence (GAMES.md §2.2).
        case canonical
        /// "S5", "D16", "T20", "25", "50", "miss": compact display of the bulls by their points.
        case points
    }

    /// Canonical notation: upper case, no space.
    public var notation: String { formatted(.canonical) }

    public func formatted(_ style: NotationStyle) -> String {
        switch bed {
        case .single: return "S\(number ?? 0)"
        case .double: return "D\(number ?? 0)"
        case .treble: return "T\(number ?? 0)"
        case .outerBull: return style == .canonical ? "SB" : "25"
        case .innerBull: return style == .canonical ? "DB" : "50"
        case .miss: return style == .canonical ? "MISS" : "miss"
        }
    }

    /// Case-insensitive parser. Accepts both styles: "t20", "D16", "S5", "SB", "25", "DB", "50", "MISS", "miss".
    /// A bare number 1...20 is a single ("5" = S5). Anything else is nil.
    public init?(notation: String) {
        let text = notation.trimmingCharacters(in: .whitespaces).uppercased()
        switch text {
        case "MISS": self = .miss
        case "SB", "25": self = .outerBull
        case "DB", "50": self = .innerBull
        default:
            guard let first = text.first else { return nil }
            let bed: Bed
            let digits: Substring
            switch first {
            case "S": bed = .single; digits = text.dropFirst()
            case "D": bed = .double; digits = text.dropFirst()
            case "T": bed = .treble; digits = text.dropFirst()
            default: bed = .single; digits = Substring(text)
            }
            guard !digits.isEmpty, digits.first != "0", digits.allSatisfy(\.isASCII), digits.allSatisfy(\.isNumber),
                  let n = Int(digits), (1...20).contains(n) else { return nil }
            self.init(bed, n)
        }
    }

    public var description: String { notation }
}

/// Encoded as its canonical notation (a JSON string such as "T20").
extension Hit: Codable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let text = try container.decode(String.self)
        guard let hit = Hit(notation: text) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unknown dart notation: \(text)")
        }
        self = hit
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(notation)
    }
}
```

Notation, en résumé :

| Valeur | `notation` (canonique) | `formatted(.points)` | Lectures acceptées par `Hit(notation:)` |
|---|---|---|---|
| simple 5 | `S5` | `S5` | `S5`, `s5`, `5` |
| double 16 | `D16` | `D16` | `D16`, `d16` |
| triple 20 | `T20` | `T20` | `T20`, `t20` |
| bull extérieur | `SB` | `25` | `SB`, `25` |
| bull intérieur | `DB` | `50` | `DB`, `50` |
| manqué | `MISS` | `miss` | `MISS`, `miss` |

- La forme canonique est celle de `GAMES.md` §2.2. C'est elle qui est écrite dans le JSON (`"T20"`), dans les tests et dans les journaux.
- Les lectures de la table sont les seules, à la casse et aux espaces de bord près. Un zéro en tête n'est pas une notation : `S05`, `T020`, `005` et `020` sont refusés, comme `025` et `050`.
- L'affichage à l'écran (« Manqué », « Bull ») et la forme parlée (« Triple vingt ») ne sont pas ici : ils relèvent de `DartUI` et de `DartAudio`.

Fichier `DartKit/Sources/DartCore/Board/BoardZone.swift` :

```swift
import Foundation

/// A part of the board that a game can highlight (GAMES.md §2.9): a zone made of beds, or a free disc.
public enum BoardZone: Hashable, Codable, Sendable {
    /// The whole wedge of a number: inner single, treble, outer single and double.
    case sector(Int)
    /// Both single beds of a number.
    case single(Int)
    case double(Int)
    case treble(Int)
    case outerBull
    case innerBull
    /// Outer and inner bull together.
    case bull
    /// A disc laid over the beds, which it overlaps freely: centre (`x`, `y`) and `radius` in NOMINAL board
    /// millimetres, in the frame of `BoardPoint`. It corresponds to no dart notation. Radar targets (GAMES.md §15.7).
    case disc(x: Double, y: Double, radius: Double)

    /// Sector number of the zone; nil for the three bull zones and for a disc.
    public var number: Int? {
        switch self {
        case .sector(let n), .single(let n), .double(let n), .treble(let n): return n
        case .outerBull, .innerBull, .bull, .disc: return nil
        }
    }

    /// True when a dart scored as `hit` lies in this zone. MISS is in no zone, and no hit is "in" a disc:
    /// whether a dart touches a disc depends on its impact point, which only the game knows (GAMES.md §2.13).
    public func contains(_ hit: Hit) -> Bool {
        switch self {
        case .sector(let n): return hit.number == n
        case .single(let n): return hit.bed == .single && hit.number == n
        case .double(let n): return hit.bed == .double && hit.number == n
        case .treble(let n): return hit.bed == .treble && hit.number == n
        case .outerBull: return hit.bed == .outerBull
        case .innerBull: return hit.bed == .innerBull
        case .bull: return hit.isBull
        case .disc: return false
        }
    }

    /// The smallest zone that contains exactly this hit; nil for MISS.
    public init?(_ hit: Hit) {
        switch hit.bed {
        case .miss: return nil
        case .single: self = .single(hit.number ?? 0)
        case .double: self = .double(hit.number ?? 0)
        case .treble: self = .treble(hit.number ?? 0)
        case .outerBull: self = .outerBull
        case .innerBull: self = .innerBull
        }
    }
}
```

Fichier `DartKit/Sources/DartCore/Board/BoardGeometry.swift` :

```swift
import Foundation

/// Board dimensions in millimetres and the conversion from a board point to a scored hit.
/// `standard` is the regulation steel-tip board. DartUI builds a second value with thicker rings for drawing
/// (DESIGN.md §3) and uses `remap(_:to:)` to move points between the two.
public struct BoardGeometry: Hashable, Sendable {
    /// Numbers clockwise from the top: 20, 1, 18, 4, 13, 6, 10, 15, 2, 17, 3, 19, 7, 16, 8, 11, 14, 9, 12, 5.
    public var sectorOrder: [Int]
    public var innerBullRadius: Double
    public var outerBullRadius: Double
    public var trebleInnerRadius: Double
    public var trebleOuterRadius: Double
    public var doubleInnerRadius: Double
    public var doubleOuterRadius: Double
    /// Outer radius of the number ring (overall diameter 451 mm).
    public var boardRadius: Double

    public init(sectorOrder: [Int] = BoardGeometry.standardSectorOrder,
                innerBullRadius: Double, outerBullRadius: Double,
                trebleInnerRadius: Double, trebleOuterRadius: Double,
                doubleInnerRadius: Double, doubleOuterRadius: Double,
                boardRadius: Double) {
        precondition(sectorOrder.count == 20 && Set(sectorOrder) == Set(1...20), "sectorOrder must be a permutation of 1...20")
        self.sectorOrder = sectorOrder
        self.innerBullRadius = innerBullRadius
        self.outerBullRadius = outerBullRadius
        self.trebleInnerRadius = trebleInnerRadius
        self.trebleOuterRadius = trebleOuterRadius
        self.doubleInnerRadius = doubleInnerRadius
        self.doubleOuterRadius = doubleOuterRadius
        self.boardRadius = boardRadius
    }

    public static let standardSectorOrder = [20, 1, 18, 4, 13, 6, 10, 15, 2, 17, 3, 19, 7, 16, 8, 11, 14, 9, 12, 5]

    /// Regulation board: bulls 6.35 / 15.9, treble 99–107, double 162–170, overall diameter 451.
    public static let standard = BoardGeometry(
        innerBullRadius: 6.35, outerBullRadius: 15.9,
        trebleInnerRadius: 99, trebleOuterRadius: 107,
        doubleInnerRadius: 162, doubleOuterRadius: 170,
        boardRadius: 225.5
    )

    /// Angular width of a sector, degrees.
    public static let sectorWidthDegrees: Double = 18

    // MARK: Scoring

    /// Scored hit of a point in the coordinates of THIS geometry; MISS beyond the outer double radius, and for a
    /// point with a non-finite coordinate.
    /// A point exactly on a ring boundary goes to the higher-scoring bed (bull, treble, double);
    /// a point exactly on a radial boundary goes to the clockwise sector.
    public func hit(at point: BoardPoint) -> Hit {
        let r = point.radius
        // Also false for a NaN or infinite radius (a non-finite coordinate): such a point is off the board.
        guard r <= doubleOuterRadius else { return .miss }
        if r <= innerBullRadius { return .innerBull }
        if r <= outerBullRadius { return .outerBull }
        let number = sectorOrder[sectorIndex(at: point)]
        if r >= trebleInnerRadius && r <= trebleOuterRadius { return .treble(number) }
        if r >= doubleInnerRadius { return .double(number) }
        return .single(number)
    }

    /// Index 0...19 in `sectorOrder` of the wedge that contains `point`: `floor(((α + 9°) mod 360°) / 18°)`.
    /// 0 for a point without an angle (a NaN coordinate).
    public func sectorIndex(at point: BoardPoint) -> Int {
        let shifted = (point.clockwiseDegrees + 9).truncatingRemainder(dividingBy: 360)
        guard shifted.isFinite else { return 0 }
        return min(19, max(0, Int(shifted / 18)))
    }

    // MARK: Sectors

    /// Index 0...19 of a number in `sectorOrder`. Precondition: `number` in 1...20.
    public func sectorIndex(of number: Int) -> Int {
        guard let index = sectorOrder.firstIndex(of: number) else { preconditionFailure("sector number out of range") }
        return index
    }

    /// The two adjacent numbers on the ring (GAMES.md §2.1). `neighbours(of: 20) == (5, 1)`.
    public func neighbours(of number: Int) -> (anticlockwise: Int, clockwise: Int) {
        let i = sectorIndex(of: number)
        return (sectorOrder[(i + 19) % 20], sectorOrder[(i + 1) % 20])
    }

    public func areAdjacent(_ a: Int, _ b: Int) -> Bool {
        let n = neighbours(of: a)
        return n.anticlockwise == b || n.clockwise == b
    }

    /// Clockwise angle of the middle of a sector, degrees from +y: 0 for the 20, 18 for the 1, …, 342 for the 5.
    public func centreAngle(of number: Int) -> Double {
        Double(sectorIndex(of: number)) * Self.sectorWidthDegrees
    }

    /// Angular extent of a sector, clockwise degrees from +y: `centre − 9 ... centre + 9` (−9...9 for the 20).
    public func angularRange(of number: Int) -> ClosedRange<Double> {
        let c = centreAngle(of: number)
        return (c - 9)...(c + 9)
    }

    // MARK: Bands

    /// The six radial bands of the scoring area, innermost first.
    public enum Band: Int, CaseIterable, Sendable {
        case innerBull, outerBull, innerSingle, treble, outerSingle, double
    }

    public func radialRange(of band: Band) -> ClosedRange<Double> {
        switch band {
        case .innerBull: return 0...innerBullRadius
        case .outerBull: return innerBullRadius...outerBullRadius
        case .innerSingle: return outerBullRadius...trebleInnerRadius
        case .treble: return trebleInnerRadius...trebleOuterRadius
        case .outerSingle: return trebleOuterRadius...doubleInnerRadius
        case .double: return doubleInnerRadius...doubleOuterRadius
        }
    }

    /// A representative point in the middle of a bed, in the coordinates of this geometry; nil for MISS.
    /// Singles use the outer single band; SB uses the middle of the outer bull ring, towards the 20.
    public func centre(of hit: Hit) -> BoardPoint? {
        func mid(_ band: Band) -> Double {
            let range = radialRange(of: band)
            return (range.lowerBound + range.upperBound) / 2
        }
        switch hit.bed {
        case .miss: return nil
        case .innerBull: return .centre
        case .outerBull: return BoardPoint(radius: mid(.outerBull), clockwiseDegrees: 0)
        case .single: return BoardPoint(radius: mid(.outerSingle), clockwiseDegrees: centreAngle(of: hit.number ?? 20))
        case .treble: return BoardPoint(radius: mid(.treble), clockwiseDegrees: centreAngle(of: hit.number ?? 20))
        case .double: return BoardPoint(radius: mid(.double), clockwiseDegrees: centreAngle(of: hit.number ?? 20))
        }
    }

    // MARK: Remapping

    /// Piecewise-linear radial remap from this geometry to `other`: every ring boundary of `self` lands on the same
    /// boundary of `other`, angles are unchanged. Beyond the outer double the scale is that of the number ring.
    /// `standard.remap(p, to: display)` draws a nominal point on the thick-ring board; the reverse call turns a tap
    /// on that drawing into a nominal position. `other.hit(at: remap(p, to: other)) == hit(at: p)` away from boundaries.
    /// The centre, and a point whose radius is not finite (a NaN or infinite coordinate), are returned unchanged.
    public func remap(_ point: BoardPoint, to other: BoardGeometry) -> BoardPoint {
        let r = point.radius
        guard r > 0, r.isFinite else { return point }
        let from = knots, to = other.knots
        var mapped = r * to[to.count - 1] / from[from.count - 1]
        for i in 1..<from.count where r <= from[i] {
            let span = from[i] - from[i - 1]
            let t = span > 0 ? (r - from[i - 1]) / span : 0
            mapped = to[i - 1] + t * (to[i] - to[i - 1])
            break
        }
        let scale = mapped / r
        return BoardPoint(x: point.x * scale, y: point.y * scale)
    }

    private var knots: [Double] {
        [0, innerBullRadius, outerBullRadius, trebleInnerRadius, trebleOuterRadius, doubleInnerRadius, doubleOuterRadius, boardRadius]
    }
}
```

- `BoardGeometry.standard` sert au score. `DartUI` définit une seconde valeur, `BoardGeometry.display`, aux anneaux épaissis pour le dessin (`DESIGN.md` §3), et passe de l'une à l'autre par `remap(_:to:)`. Un jeu qui dépend de la position se dessine avec `standard` (§8.4.3).
- Règle des frontières (déterministe, testée) : sur un cercle limite, la case la mieux payée l'emporte ; sur un fil radial, le secteur horaire l'emporte.
- `hit(at:)` est une fonction totale : un point dont une coordonnée n'est pas finie (`NaN`, infini), ou si grande que le rayon déborde, rend `MISS`, sans planter. `sectorIndex(at:)` rend alors un indice valide (0 pour un point sans angle) et `remap(_:to:)` rend le point inchangé. `DartVision` appelle `hit(at:)` sur des positions calculées (`VISION.md` §7.2, §9.1) : une projection dégénérée ne doit pas arrêter une partie. C'est la même règle que pour `ImpactPoint` (`GAMES.md` §2.13).
- `clockwiseDegrees` est dans [0, 360), bornes comprises à gauche seulement : un point si près de l'axe du 20, côté gauche, que son angle s'arrondirait à 360° vaut 0°.

**Point d'impact** (`GAMES.md` §2.13). Chaque fléchette du journal porte sa case et, quand elle est connue, la position enregistrée de sa pointe en millimètres nominaux (`DartRecord.position`, §4.8). Treize jeux sur quatorze ne la lisent jamais. Radar, seul jeu dépendant de la position, raisonne sur le **point d'impact** de la fléchette, que `ImpactPoint` calcule une fois pour toutes, en entiers :

Fichier `DartKit/Sources/DartCore/Board/ImpactPoint.swift` :

```swift
import Foundation

/// Impact point of a dart for a POSITION-DEPENDENT game (GAMES.md §2.13), in integer TENTHS of a millimetre,
/// in the frame of `BoardPoint` (origin at the bull centre, +x towards the 6, +y towards the 20).
/// Such a game computes in integers only: no sine, no square root, no floating-point comparison.
/// The thirteen games that do not depend on the position never build this type.
public struct ImpactPoint: Hashable, Sendable {
    public var x: Int
    public var y: Int

    public init(x: Int, y: Int) {
        self.x = x
        self.y = y
    }

    /// Converts a recorded position once: `Int((10 * x).rounded())`, nearest tenth, halves away from zero.
    /// A non-finite coordinate is pushed far off the board instead of trapping.
    public init(_ position: BoardPoint) {
        self.init(x: ImpactPoint.tenths(position.x), y: ImpactPoint.tenths(position.y))
    }

    /// The impact point of an input (GAMES.md §2.13), a total function of (hit, recorded position):
    /// 1. MISS has NO impact point, even when a position was recorded;
    /// 2. otherwise the recorded position, as it is (it is not checked against `hit`);
    /// 3. otherwise the canonical position of the bed.
    public init?(hit: Hit, position: BoardPoint?) {
        if hit.isMiss { return nil }
        if let position {
            self.init(position)
        } else if let canonical = ImpactPoint.canonical(of: hit) {
            self = canonical
        } else {
            return nil
        }
    }

    /// Canonical position of a bed: its middle, i.e. `BoardGeometry.standard.centre(of:)` rounded to the tenth.
    /// DB (0, 0); SB (0, 111); Sn on the OUTER single band (radius 134.5); Tn at radius 103; Dn at radius 166.
    /// Nil for MISS. The table of GAMES.md §2.13 is normative and embedded below: nothing is recomputed.
    public static func canonical(of hit: Hit) -> ImpactPoint? {
        switch hit.bed {
        case .miss: return nil
        case .innerBull: return ImpactPoint(x: 0, y: 0)
        case .outerBull: return ImpactPoint(x: 0, y: 111)
        case .single: return point(in: singles, hit)
        case .treble: return point(in: trebles, hit)
        case .double: return point(in: doubles, hit)
        }
    }

    /// The same point in millimetres.
    public var boardPoint: BoardPoint {
        BoardPoint(x: Double(x) / 10, y: Double(y) / 10)
    }

    // MARK: Private

    private static func tenths(_ millimetres: Double) -> Int {
        let value = (10 * millimetres).rounded()
        guard value.isFinite else { return 1_000_000 }
        return Int(max(-1_000_000, min(1_000_000, value)))
    }

    private static func point(in table: [(x: Int, y: Int)], _ hit: Hit) -> ImpactPoint? {
        guard let number = hit.number, let index = BoardGeometry.standardSectorOrder.firstIndex(of: number) else { return nil }
        return ImpactPoint(x: table[index].x, y: table[index].y)
    }

    // One entry per sector, clockwise from the top: 20, 1, 18, 4, 13, 6, 10, 15, 2, 17, 3, 19, 7, 16, 8, 11, 14, 9, 12, 5.
    private static let singles: [(x: Int, y: Int)] = [
        (0, 1345), (416, 1279), (791, 1088), (1088, 791), (1279, 416),
        (1345, 0), (1279, -416), (1088, -791), (791, -1088), (416, -1279),
        (0, -1345), (-416, -1279), (-791, -1088), (-1088, -791), (-1279, -416),
        (-1345, 0), (-1279, 416), (-1088, 791), (-791, 1088), (-416, 1279),
    ]
    private static let trebles: [(x: Int, y: Int)] = [
        (0, 1030), (318, 980), (605, 833), (833, 605), (980, 318),
        (1030, 0), (980, -318), (833, -605), (605, -833), (318, -980),
        (0, -1030), (-318, -980), (-605, -833), (-833, -605), (-980, -318),
        (-1030, 0), (-980, 318), (-833, 605), (-605, 833), (-318, 980),
    ]
    private static let doubles: [(x: Int, y: Int)] = [
        (0, 1660), (513, 1579), (976, 1343), (1343, 976), (1579, 513),
        (1660, 0), (1579, -513), (1343, -976), (976, -1343), (513, -1579),
        (0, -1660), (-513, -1579), (-976, -1343), (-1343, -976), (-1579, -513),
        (-1660, 0), (-1579, 513), (-1343, 976), (-976, 1343), (-513, 1579),
    ]
}
```

| Entrée | Point d'impact |
|---|---|
| `hit == MISS`, avec ou sans position enregistrée | aucun : la fléchette ne touche rien |
| autre case, position enregistrée | cette position, **telle quelle**, convertie en dixièmes par `Int((10 * x).rounded())` ; elle n'est pas confrontée à la case |
| autre case, pas de position (case choisie dans une liste, vecteur de test sans `@`) | la position canonique de la case : `ImpactPoint.canonical(of:)` |

- La table des 62 positions canoniques est celle de `GAMES.md` §2.13, embarquée telle quelle. Un test de `DartCoreTests` vérifie qu'elle vaut `BoardGeometry.standard.centre(of:)` arrondi au dixième, pour les 62 cases.
- Une règle n'appelle pas `ImpactPoint` elle-même : elle lit `TurnContext.impact` (§4.7), qui applique les trois lignes ci-dessus à la fléchette en cours.
- D'où vient la position : la pointe mesurée par la caméra (`DartObservation.tip`), ou le point touché sur la cible virtuelle ramené en coordonnées nominales (`BoardTap.position`, §8.4.3). Une correction la remplace ou l'efface (`GameMatch.replaceDart`, §4.8).

### 4.3 Joueurs, aléatoire, textes

Fichier `DartKit/Sources/DartCore/Players/Player.swift` :

```swift
import Foundation

/// Position of a player in `GameConfiguration.players`: J1 = 0, J2 = 1, … (GAMES.md §2.3).
/// It is also the index of the player's colour in the palette of DESIGN.md §2.
public typealias PlayerIndex = Int

/// A person who plays. Kept in the roster between sessions.
public struct Player: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public var name: String

    public init(id: UUID = UUID(), name: String) {
        self.id = id
        self.name = name
    }
}
```

La couleur d'un joueur n'est pas enregistrée : c'est celle de sa place dans la partie (`PlayerIndex`), dans l'ordre de `DESIGN.md` §2.

Fichier `DartKit/Sources/DartCore/Random/SeededRandom.swift` :

```swift
import Foundation

/// SplitMix64. The ONLY source of randomness of the game engines (GAMES.md §2.8).
/// Engines must not use `SystemRandomNumberGenerator`, `Int.random(in:)`, `shuffled()` or their `using:` variants.
public struct SeededRandom: Hashable, Sendable {
    public private(set) var state: UInt64

    public init(seed: UInt64) {
        state = seed
    }

    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// `next() % bound`. Uniform enough for bound <= 20; exactly reproducible. Precondition: bound >= 1.
    public mutating func nextInt(below bound: Int) -> Int {
        precondition(bound >= 1, "bound must be positive")
        return Int(next() % UInt64(bound))
    }

    /// Fisher–Yates, from the last index down to 1 (`count - 1` draws).
    public mutating func shuffled<T>(_ items: [T]) -> [T] {
        var a = items
        var i = a.count - 1
        while i >= 1 {
            a.swapAt(i, nextInt(below: i + 1))
            i -= 1
        }
        return a
    }
}

/// Places, for each player, a block of `width` consecutive ring numbers (clockwise), without overlap (GAMES.md §2.8).
/// Used by Killer and Conqueror. Draws: 1 (offset) + `20 - p·k` (gaps) + `p - 1` (order).
/// Precondition: `playerCount * width <= 20`.
public func ringLayout(playerCount p: Int, width k: Int, rng: inout SeededRandom) -> [[Int]] {
    precondition(p >= 1 && k >= 1 && p * k <= 20, "zones do not fit on the ring")
    let ring = BoardGeometry.standardSectorOrder
    let offset = rng.nextInt(below: 20)
    var gaps = [Int](repeating: 0, count: p)
    for _ in 0..<(20 - p * k) {
        gaps[rng.nextInt(below: p)] += 1
    }
    let order = rng.shuffled(Array(0..<p))
    var zones = [[Int]](repeating: [], count: p)
    var cursor = offset
    for slot in 0..<p {
        zones[order[slot]] = (0..<k).map { ring[(cursor + $0) % 20] }
        cursor += k + gaps[slot]
    }
    return zones
}
```

Ce code est celui de `GAMES.md` §2.8, rendu public. Les valeurs de contrôle de ce paragraphe sont des tests obligatoires de `DartCoreTests`.

Fichier `DartKit/Sources/DartCore/Text/LocalizedText.swift` :

```swift
import Foundation

/// The two languages of the application. French first.
public enum AppLanguage: String, Codable, Sendable, CaseIterable {
    case fr, en

    /// Language to use for a list of preferred language tags (most preferred first):
    /// the first tag that starts with "fr" or "en"; French when none does.
    public init(preferredLanguages: [String]) {
        for tag in preferredLanguages {
            let lower = tag.lowercased()
            if lower.hasPrefix("fr") { self = .fr; return }
            if lower.hasPrefix("en") { self = .en; return }
        }
        self = .fr
    }

    /// BCP 47 tag of the matching speech voice: "fr-FR" or "en-US".
    public var voiceLanguageCode: String {
        switch self {
        case .fr: return "fr-FR"
        case .en: return "en-US"
        }
    }
}

/// A user-facing text carried in both languages. Engines and descriptors produce it; the UI picks one.
/// No bundle and no key: DartCore, DartGames and DartAudio need no string resources.
public struct LocalizedText: Hashable, Codable, Sendable {
    public var fr: String
    public var en: String

    public init(fr: String, en: String) {
        self.fr = fr
        self.en = en
    }

    /// The same text in both languages: numbers, player names, dart notations.
    public init(verbatim text: String) {
        self.init(fr: text, en: text)
    }

    public subscript(language: AppLanguage) -> String {
        switch language {
        case .fr: return fr
        case .en: return en
        }
    }

    /// Singular/plural pair: `count == 1` (and 0 in French) takes the singular. "1 vie", "3 vies", "0 vie" / "0 lives".
    public static func counted(_ count: Int, fr: (one: String, other: String), en: (one: String, other: String)) -> LocalizedText {
        LocalizedText(fr: "\(count) \(count <= 1 ? fr.one : fr.other)",
                      en: "\(count) \(count == 1 ? en.one : en.other)")
    }
}
```

Pourquoi des textes portés comme données : un moteur doit pouvoir dire « Tom −1 vie » ou « Dernière volée : 45 » sans que `DartUI` connaisse le jeu. Le moteur fournit donc la phrase dans les deux langues, et l'interface choisit. `DartCore`, `DartGames` et `DartAudio` n'ont ainsi aucun fichier de chaînes ; seul `DartUI` en a, pour ses propres libellés (§8.9).

### 4.4 Identité, options, descripteur, configuration

Fichier `DartKit/Sources/DartCore/Game/GameID.swift` :

```swift
import Foundation

/// Stable identifier of a game: the `id` column of GAMES.md §1. Used in persistence; never rename one.
public struct GameID: RawRepresentable, Hashable, Codable, Sendable, CustomStringConvertible {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public var description: String { rawValue }

    public static let x01 = GameID("x01")
    public static let cricket = GameID("cricket")
    public static let killer = GameID("killer")
    public static let aroundTheClock = GameID("aroundTheClock")
    public static let shanghai = GameID("shanghai")
    public static let highScore = GameID("highScore")
    public static let halveIt = GameID("halveIt")
    public static let moonLanding = GameID("moonLanding")
    public static let fight = GameID("fight")
    public static let conqueror = GameID("conqueror")
    public static let beerTap = GameID("beerTap")
    public static let football = GameID("football")
    public static let radar = GameID("radar")
    public static let golf = GameID("golf")
}
```

Fichier `DartKit/Sources/DartCore/Game/GameOptions.swift` :

```swift
import Foundation

/// Value of one game option. Option names and enum values are those of GAMES.md ("level": "easy", "maxRounds": 15).
public enum OptionValue: Hashable, Codable, Sendable {
    case bool(Bool)
    case int(Int)
    /// An enum case by its GAMES.md name: "cutThroat", "easy", "double".
    case string(String)
    /// A list, e.g. the Halve-It targets: ["20", "16", "D7", "14", "T10", "BULL"].
    case strings([String])
    /// The `nil` of an optional option (`maxRounds: nil` = no round limit).
    case null
}

extension OptionValue: ExpressibleByBooleanLiteral, ExpressibleByIntegerLiteral, ExpressibleByStringLiteral {
    public init(booleanLiteral value: Bool) { self = .bool(value) }
    public init(integerLiteral value: Int) { self = .int(value) }
    public init(stringLiteral value: String) { self = .string(value) }
}

/// The options chosen for one game, by option key. Missing keys take the descriptor's defaults.
public struct GameOptions: Hashable, Codable, Sendable, ExpressibleByDictionaryLiteral {
    public var values: [String: OptionValue]

    public init(_ values: [String: OptionValue] = [:]) {
        self.values = values
    }

    public init(dictionaryLiteral elements: (String, OptionValue)...) {
        self.values = Dictionary(elements, uniquingKeysWith: { _, last in last })
    }

    public subscript(key: String) -> OptionValue? {
        get { values[key] }
        set { values[key] = newValue }
    }

    public func bool(_ key: String) -> Bool? {
        if case .bool(let value)? = values[key] { return value }
        return nil
    }

    /// Nil when the key is missing, is `.null`, or is not an integer.
    public func int(_ key: String) -> Int? {
        if case .int(let value)? = values[key] { return value }
        return nil
    }

    public func string(_ key: String) -> String? {
        if case .string(let value)? = values[key] { return value }
        return nil
    }

    public func strings(_ key: String) -> [String]? {
        if case .strings(let value)? = values[key] { return value }
        return nil
    }
}

// MARK: - Options schema (drives the setup screen)

/// Pictogram shown next to a choice on the setup screen.
public enum ChoiceIllustration: Hashable, Sendable {
    /// `count` adjacent sectors lit on a small board; `moving` adds the "changes every turn" mark (Killer levels).
    case sectors(count: Int, moving: Bool)
}

/// One selectable value of a `.choice` option.
public struct OptionChoice: Hashable, Sendable {
    public var value: OptionValue
    public var label: LocalizedText
    public var detail: LocalizedText?
    /// Player counts for which the choice is allowed; nil = the whole range of the game.
    public var players: ClosedRange<Int>?
    /// Shown when the choice is greyed out: "6 joueurs maximum en Facile".
    public var unavailableNote: LocalizedText?
    public var illustration: ChoiceIllustration?

    public init(_ value: OptionValue, label: LocalizedText, detail: LocalizedText? = nil,
                players: ClosedRange<Int>? = nil, unavailableNote: LocalizedText? = nil,
                illustration: ChoiceIllustration? = nil) {
        self.value = value
        self.label = label
        self.detail = detail
        self.players = players
        self.unavailableNote = unavailableNote
        self.illustration = illustration
    }
}

/// How an option is edited and which values it accepts.
public enum OptionKind: Hashable, Sendable {
    /// `.bool`.
    case toggle
    /// `.int` inside the range, edited with − / +.
    case stepper(ClosedRange<Int>)
    /// `.int` inside the range, or `.null`; `nullLabel` names the null value ("Sans limite").
    case optionalStepper(ClosedRange<Int>, nullLabel: LocalizedText)
    /// One value among the choices (radio buttons or a segmented control).
    case choice([OptionChoice])
}

/// Description of one option of a game.
public struct OptionDescriptor: Hashable, Sendable, Identifiable {
    /// Option name of GAMES.md: "startScore", "level", "maxRounds".
    public var key: String
    public var label: LocalizedText
    public var help: LocalizedText?
    public var kind: OptionKind
    public var defaultValue: OptionValue
    /// Folded under "Plus d'options" on the setup screen.
    public var isAdvanced: Bool
    /// For `.choice`: a value outside the listed choices is left to the engine to validate (custom Halve-It lists).
    public var allowsCustomValue: Bool

    public var id: String { key }

    public init(key: String, label: LocalizedText, help: LocalizedText? = nil, kind: OptionKind,
                defaultValue: OptionValue, isAdvanced: Bool = false, allowsCustomValue: Bool = false) {
        self.key = key
        self.label = label
        self.help = help
        self.kind = kind
        self.defaultValue = defaultValue
        self.isAdvanced = isAdvanced
        self.allowsCustomValue = allowsCustomValue
    }
}
```

Fichier `DartKit/Sources/DartCore/Game/GameDescriptor.swift` :

```swift
import Foundation

/// Which template the play screen uses (DESIGN.md §4).
public enum PlayStyle: String, Codable, Sendable {
    /// The game is read on the board (zones, targets): Killer template.
    case board
    /// The game is read on a big number: X01 template.
    case score
}

public enum GameOrigin: String, Codable, Sendable {
    case dartsee, classic
}

/// Everything the application knows about a game without creating one: the home card, the setup screen, validation.
public struct GameDescriptor: Hashable, Sendable, Identifiable {
    public var id: GameID
    /// Full name: "Tour de l'horloge" / "Around the Clock".
    public var name: LocalizedText
    /// Name on the home card: "Horloge" / "Clock".
    public var shortName: LocalizedText
    /// Second line of the home card: "4 niveaux · 2 à 8 joueurs".
    public var summary: LocalizedText
    /// One-sentence rule shown on the setup screen (GAMES.md §n.1, "En une ligne").
    public var pitch: LocalizedText
    /// Overall player range; a choice may narrow it (`OptionChoice.players`).
    public var players: ClosedRange<Int>
    public var options: [OptionDescriptor]
    public var playStyle: PlayStyle
    public var origin: GameOrigin
    /// 0 = P0, 1 = P1, 2 = P2 (GAMES.md §1).
    public var priority: Int
    /// "Dépend de la position : oui" in the game's sheet (GAMES.md §2.13): the engine reads the impact point of a
    /// dart, not only its hit. The UI then draws the board at regulation proportions and groups doubtful
    /// detections on (hit, position). True for Radar only.
    public var dependsOnPosition: Bool
    /// True (default): the UI asks for a confirmation before ending a turn of fewer than three darts.
    /// False when stopping early is a normal move of the game (Golf, GAMES.md §16.5).
    public var confirmsShortTurn: Bool

    public init(id: GameID, name: LocalizedText, shortName: LocalizedText, summary: LocalizedText, pitch: LocalizedText,
                players: ClosedRange<Int>, options: [OptionDescriptor], playStyle: PlayStyle,
                origin: GameOrigin, priority: Int, dependsOnPosition: Bool = false, confirmsShortTurn: Bool = true) {
        self.id = id
        self.name = name
        self.shortName = shortName
        self.summary = summary
        self.pitch = pitch
        self.players = players
        self.options = options
        self.playStyle = playStyle
        self.origin = origin
        self.priority = priority
        self.dependsOnPosition = dependsOnPosition
        self.confirmsShortTurn = confirmsShortTurn
    }

    public func option(_ key: String) -> OptionDescriptor? {
        options.first { $0.key == key }
    }

    /// Every option at its default value.
    public var defaultOptions: GameOptions {
        GameOptions(Dictionary(uniqueKeysWithValues: options.map { ($0.key, $0.defaultValue) }))
    }

    /// `options` completed with the defaults of the missing keys. Unknown keys are kept (and reported by `validate`).
    public func normalized(_ options: GameOptions) -> GameOptions {
        var result = defaultOptions
        for (key, value) in options.values { result[key] = value }
        return result
    }

    /// Player counts allowed with these options: the game range narrowed by the selected choices.
    public func playerRange(for options: GameOptions) -> ClosedRange<Int> {
        let chosen = normalized(options)
        var lower = players.lowerBound, upper = players.upperBound
        for option in self.options {
            guard case .choice(let choices) = option.kind,
                  let choice = choices.first(where: { $0.value == chosen[option.key] }),
                  let range = choice.players else { continue }
            lower = max(lower, range.lowerBound)
            upper = min(upper, range.upperBound)
        }
        return lower...max(lower, upper)
    }

    /// Schema validation, in a stable order: player count, then options in descriptor order, then unknown keys (sorted).
    /// An empty result means the engine may still refuse a custom value (`allowsCustomValue`).
    public func validate(options: GameOptions, playerCount: Int) -> [GameConfigurationError] {
        var issues: [GameConfigurationError] = []
        if !players.contains(playerCount) {
            issues.append(.playerCountOutOfRange(allowed: players, actual: playerCount))
        }
        let chosen = normalized(options)
        for option in self.options {
            let value = chosen[option.key] ?? option.defaultValue
            switch option.kind {
            case .toggle:
                if case .bool = value {} else { issues.append(.invalidOptionValue(key: option.key)) }
            case .stepper(let range):
                if case .int(let n) = value, range.contains(n) {} else { issues.append(.invalidOptionValue(key: option.key)) }
            case .optionalStepper(let range, _):
                switch value {
                case .null: break
                case .int(let n) where range.contains(n): break
                default: issues.append(.invalidOptionValue(key: option.key))
                }
            case .choice(let choices):
                if let choice = choices.first(where: { $0.value == value }) {
                    if let range = choice.players, !range.contains(playerCount), players.contains(playerCount) {
                        issues.append(.choiceUnavailable(key: option.key, note: choice.unavailableNote))
                    }
                } else if !option.allowsCustomValue {
                    issues.append(.invalidOptionValue(key: option.key))
                }
            }
        }
        let known = Set(self.options.map(\.key))
        for key in options.values.keys.sorted() where !known.contains(key) {
            issues.append(.unknownOption(key: key))
        }
        return issues
    }

    /// Setup-screen helper: replaces every choice that `playerCount` makes unavailable by the next available choice
    /// in list order (wrapping). Killer `easy` with 7 players becomes `medium` (GAMES.md §5.2).
    public func adjusted(_ options: GameOptions, playerCount: Int) -> GameOptions {
        var result = normalized(options)
        for option in self.options {
            guard case .choice(let choices) = option.kind,
                  let index = choices.firstIndex(where: { $0.value == result[option.key] }) else { continue }
            func available(_ choice: OptionChoice) -> Bool { choice.players?.contains(playerCount) ?? true }
            if available(choices[index]) { continue }
            for step in 1..<max(choices.count, 2) {
                let candidate = choices[(index + step) % choices.count]
                if available(candidate) {
                    result[option.key] = candidate.value
                    break
                }
            }
        }
        return result
    }
}
```

Fichier `DartKit/Sources/DartCore/Game/GameConfiguration.swift` :

```swift
import Foundation

/// Everything that defines a game before the first dart (GAMES.md §2.4): `state = reduce(configuration, inputs)`.
public struct GameConfiguration: Hashable, Codable, Sendable {
    public var gameID: GameID
    public var options: GameOptions
    /// Playing order; fixed for the whole game. Shuffling is the setup screen's job.
    public var players: [Player]
    /// Drawn by the application when the game is created and saved with it (GAMES.md §2.8).
    public var seed: UInt64

    public init(gameID: GameID, options: GameOptions = [:], players: [Player], seed: UInt64) {
        self.gameID = gameID
        self.options = options
        self.players = players
        self.seed = seed
    }
}

/// Why a game cannot be created. There is never a silent fallback.
public enum GameConfigurationError: Error, Hashable, Sendable {
    case unknownGame(GameID)
    case playerCountOutOfRange(allowed: ClosedRange<Int>, actual: Int)
    case unknownOption(key: String)
    /// Wrong type, out of range, or a custom value the engine cannot read.
    case invalidOptionValue(key: String)
    /// The selected choice does not allow this number of players (Killer `easy` with 7 or 8 players).
    case choiceUnavailable(key: String, note: LocalizedText?)
}
```

Comment l'écran de préparation s'en sert, sans connaître le jeu :

- il dessine un contrôle par `OptionDescriptor` selon son `kind` (§8.5) ;
- il borne le nombre de joueurs par `playerRange(for:)` ;
- quand le nombre de joueurs change, il appelle `adjusted(_:playerCount:)` : un choix devenu indisponible est remplacé par le suivant dans la liste. C'est ainsi que Killer « Facile » devient « Intermédiaire » à 7 joueurs (`GAMES.md` §5.2), sans code propre au Killer ;
- il grise un choix dont `players` exclut le nombre de joueurs courant et affiche son `unavailableNote` ;
- il active « Lancer la partie » quand `validate(options:playerCount:)` est vide.

Un moteur refuse toujours une configuration invalide à la création (`GameConfigurationError`) : il n'y a jamais de repli silencieux.

Deux champs du descripteur règlent le comportement de l'interface sans qu'elle connaisse le jeu. Ils ont une valeur par défaut : douze descripteurs ne les écrivent pas.

| Champ | Défaut | Jeu qui le change | Effet dans `DartUI` |
|---|---|---|---|
| `dependsOnPosition` | `false` | `radar` : `true` | la cible est dessinée aux proportions réglementaires (§8.4.3) ; le regroupement « même effet » se fait sur le couple (case, position) (§4.8) ; les tests de propriétés tirent des positions (§12.1) |
| `confirmsShortTurn` | `true` | `golf` : `false` | `PlayViewModel.requestEndTurn()` ne demande pas de confirmation pour une volée de moins de trois fléchettes (§8.6) |

### 4.5 Entrées, phases, événements

Fichier `DartKit/Sources/DartCore/Game/GameInput.swift` :

```swift
import Foundation

/// The only two inputs of an engine (GAMES.md §2.4).
/// A dart may come with the recorded position of its impact; the position travels beside the input
/// (`GameEngine.apply(_:position:)`) and only a position-dependent game reads it (GAMES.md §2.13).
public enum GameInput: Hashable, Codable, Sendable {
    /// One dart, wherever it comes from (camera or manual input).
    case dart(Hit)
    /// The explicit "darts pulled / next player" confirmation.
    case endTurn
}

public enum GamePhase: String, Codable, Sendable {
    /// The current player may throw. `dart` and `endTurn` are accepted.
    case throwing
    /// The turn is closed and waits for the confirmation. `dart` is refused, `endTurn` is accepted.
    case turnComplete
    /// The game is over. Every input is refused.
    case finished
}

public enum FinishReason: String, Codable, Sendable {
    /// A player met the winning condition on a dart.
    case victory
    /// Only one player is left (elimination games).
    case lastPlayerStanding
    /// The round limit was reached; decided when `endTurn` is processed.
    case roundLimit
}

public enum InputRejection: String, Codable, Sendable {
    /// A dart arrived while the turn waits for `endTurn`: "Tour terminé, retirez les fléchettes".
    case turnComplete
    case gameFinished
}

/// Result of applying one input. A rejected input changes nothing and is not logged.
public enum InputOutcome: Hashable, Sendable {
    case accepted([GameEvent])
    case rejected(InputRejection)

    public var isAccepted: Bool {
        if case .accepted = self { return true }
        return false
    }

    /// Events of an accepted input, in order; empty when rejected.
    public var events: [GameEvent] {
        if case .accepted(let events) = self { return events }
        return []
    }
}
```

Fichier `DartKit/Sources/DartCore/Game/GameEvent.swift` :

```swift
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
```

Correspondance avec le catalogue d'événements de `GAMES.md` §2.10 : chaque événement porte le même nom et les mêmes champs, dans le même ordre, sans exception. Trois précisions de forme :

| `GAMES.md` | `GameEvent` |
|---|---|
| cible ou secteur « bull » | le nombre `25` |
| camp du Football (`side`) | `0` pour le camp A, `1` pour le camp B |
| `blobsMoved`, sans champ | `.blobsMoved` |

- `targetHit(player:number:advancedBy:)` n'existe que pour le Tour de l'horloge ; Shanghai et La Moitié émettent `targetScored(player:points:)`.
- La position enregistrée d'une fléchette ne fait pas partie de `GameInput` : elle voyage à côté de l'entrée (`GameEngine.apply(_:position:)`, §4.7). `GameInput` garde ainsi sa forme et son JSON, et les treize jeux qui ignorent la position n'ont rien à écrire.
- Un jeu futur qui apporte un événement nouveau ajoute un cas à cette énumération ; le compilateur signale alors la table de sons (`CueMapping`, §7.3), qui est un `switch` exhaustif. C'est ce qui s'est passé pour les dix événements des quatre jeux du lot G4.

### 4.6 Instantané de présentation

`GameSnapshot` est tout ce que `DartUI` lit d'un jeu. Il contient deux sortes de données :

- des données **d'affichage** (`PlayerRow.primary`, `detail`, `badges`, `DartCaption`, `outcome`…), déjà rédigées dans les deux langues ;
- des **faits** (`facts`), qui sont les champs logiques de `GAMES.md` sous leur nom exact (`remaining`, `lives`, `zone`, `marks`…). Les vecteurs de test s'écrivent sur les faits, jamais sur les textes.

Fichier `DartKit/Sources/DartCore/Game/GameSnapshot.swift` :

```swift
import Foundation

/// A logical field of a game, named as in GAMES.md ("remaining", "lives", "zone", "marks").
/// Used by the test vectors, by `GameMatch.effectKey(for:)` and by statistics. Never shown as is.
public enum FactValue: Hashable, Sendable {
    case int(Int)
    case bool(Bool)
    case text(String)
    /// A list of numbers in a meaningful order: a Killer zone, the Cricket targets.
    case ints([Int])
    /// Number → value: Cricket marks by target (bull = 25), Conqueror lives by sector.
    case map([Int: Int])
    /// Rows of numbers in a meaningful order: the five Radar targets, one row `[x, y, radius, hitPoints]` each.
    /// No literal syntax: write `.table([[...], [...]])`.
    case table([[Int]])
}

extension FactValue: ExpressibleByIntegerLiteral, ExpressibleByBooleanLiteral, ExpressibleByStringLiteral,
                     ExpressibleByArrayLiteral, ExpressibleByDictionaryLiteral {
    public init(integerLiteral value: Int) { self = .int(value) }
    public init(booleanLiteral value: Bool) { self = .bool(value) }
    public init(stringLiteral value: String) { self = .text(value) }
    public init(arrayLiteral elements: Int...) { self = .ints(elements) }
    public init(dictionaryLiteral elements: (Int, Int)...) {
        self = .map(Dictionary(elements, uniquingKeysWith: { _, last in last }))
    }
}

/// Meaning of a highlighted zone for the CURRENT player (GAMES.md §2.9).
public enum HighlightRole: String, Codable, Sendable {
    /// Aim here: it makes the player progress, score or attack.
    case target
    /// Useful, but less than a target.
    case secondary
    /// Belongs to the player, no useful effect right now.
    case own
    /// Hitting it costs the player something.
    case avoid
    /// Belongs to an opponent, shown for information.
    case opponent
    /// Dead zone: no effect for anyone.
    case inactive
}

/// Small symbol drawn on a highlighted zone.
public enum BoardMarker: String, Codable, Sendable {
    /// Conqueror home sector.
    case home
    /// Conqueror King of the Hill (on the bull).
    case crown
    /// Fight heal number.
    case heal
}

/// One highlighted zone: (zone, role, optional owner), plus an optional label, strength and marker (GAMES.md §2.9).
/// The zone is a set of beds or a free disc (`BoardZone.disc`, Radar targets).
public struct BoardHighlight: Hashable, Sendable {
    public var zone: BoardZone
    public var role: HighlightRole
    /// Owner of the zone, when it has one: the zone is drawn in that player's colour.
    public var owner: PlayerIndex?
    /// Short label drawn on the zone: "+3", "+2r", "+10" (Radar), "1" (Golf).
    public var label: String?
    /// Hit points 1...3 drawn as pips in the zone: Conqueror sector lives, hit points left of a Radar target.
    public var strength: Int?
    public var marker: BoardMarker?

    public init(zone: BoardZone, role: HighlightRole, owner: PlayerIndex? = nil, label: String? = nil,
                strength: Int? = nil, marker: BoardMarker? = nil) {
        self.zone = zone
        self.role = role
        self.owner = owner
        self.label = label
        self.strength = strength
        self.marker = marker
    }
}

/// Colour intent of a caption or a badge. The UI maps it to DESIGN.md tokens.
public enum Tone: String, Codable, Sendable {
    case neutral, positive, negative, accent
}

/// The big value of a scoreboard row: "187", or "3" with the unit "vies".
public struct ScoreValue: Hashable, Sendable {
    public var text: String
    public var unit: LocalizedText?

    public init(_ text: String, unit: LocalizedText? = nil) {
        self.text = text
        self.unit = unit
    }

    public init(_ value: Int, unit: LocalizedText? = nil) {
        self.init(String(value), unit: unit)
    }
}

public struct Badge: Hashable, Sendable {
    public var text: LocalizedText
    public var tone: Tone

    public init(_ text: LocalizedText, tone: Tone = .neutral) {
        self.text = text
        self.tone = tone
    }
}

/// A small gauge on a scoreboard row.
public struct Meter: Hashable, Sendable {
    public enum Style: String, Codable, Sendable {
        /// Discrete dots: Killer arming hits, lives up to 9.
        case pips
        /// Continuous bar: Around-the-Clock progress, Fight life bar.
        case bar
    }
    public var value: Int
    public var maximum: Int
    public var style: Style

    public init(value: Int, maximum: Int, style: Style) {
        self.value = value
        self.maximum = maximum
        self.style = style
    }
}

/// One line of the scoreboard. `rows[i]` is the player of index `i`.
public struct PlayerRow: Hashable, Sendable {
    public var player: PlayerIndex
    /// Main value: remaining score, lives, points.
    public var primary: ScoreValue
    /// Secondary line: "Dernière volée : 45", "17 · 3 · 19".
    public var detail: LocalizedText?
    /// Short labels: "Killer", "À ouvrir", "Roi".
    public var badges: [Badge]
    public var meter: Meter?
    /// Provisional rank during the game, final rank once finished (GAMES.md §2.7). Filled by the engine.
    public var rank: Int
    public var isEliminated: Bool
    /// Lines of the results screen for this player: "2 éliminations", "Éliminée manche 9".
    public var resultLines: [LocalizedText]
    /// Logical fields of GAMES.md for this player.
    public var facts: [String: FactValue]

    public init(player: PlayerIndex, primary: ScoreValue, detail: LocalizedText? = nil, badges: [Badge] = [],
                meter: Meter? = nil, rank: Int = 1, isEliminated: Bool = false,
                resultLines: [LocalizedText] = [], facts: [String: FactValue] = [:]) {
        self.player = player
        self.primary = primary
        self.detail = detail
        self.badges = badges
        self.meter = meter
        self.rank = rank
        self.isEliminated = isEliminated
        self.resultLines = resultLines
        self.facts = facts
    }
}

/// What the game says about one dart of the current turn: "60", "Tom −1 vie", "BUST".
public struct DartCaption: Hashable, Sendable {
    public var text: LocalizedText
    public var tone: Tone

    public init(_ text: LocalizedText, tone: Tone = .neutral) {
        self.text = text
        self.tone = tone
    }
}

/// One thrown dart of the current turn.
public struct DartSlot: Hashable, Sendable {
    public var hit: Hit
    public var caption: DartCaption?

    public init(hit: Hit, caption: DartCaption? = nil) {
        self.hit = hit
        self.caption = caption
    }
}

/// The current turn.
public struct TurnSnapshot: Hashable, Sendable {
    /// Darts thrown so far, in order (0...capacity).
    public var darts: [DartSlot]
    /// Darts per turn: 3.
    public var capacity: Int
    /// "Volée : 117", "BUST".
    public var summary: LocalizedText?
    /// Advice for the next dart: "Pour finir : D12".
    public var hint: LocalizedText?

    public init(darts: [DartSlot] = [], capacity: Int = 3, summary: LocalizedText? = nil, hint: LocalizedText? = nil) {
        self.darts = darts
        self.capacity = capacity
        self.summary = summary
        self.hint = hint
    }
}

/// Marks table of Cricket: one column per target, one row per player.
public struct ScoreGrid: Hashable, Sendable {
    /// Column titles: "20", "19", …, "B".
    public var columns: [String]
    /// `marks[player][column]`, 0...3.
    public var marks: [[Int]]
    /// True for the columns closed by every player.
    public var dead: [Bool]

    public init(columns: [String], marks: [[Int]], dead: [Bool]) {
        self.columns = columns
        self.marks = marks
        self.dead = dead
    }
}

/// Everything the UI needs to draw ANY game, without knowing which one it is.
/// A pure function of (configuration, journal); recomputed after every input.
public struct GameSnapshot: Hashable, Sendable {
    public var gameID: GameID
    /// Title of the play screen: "Killer", "501".
    public var title: LocalizedText
    /// Variant shown next to the round counter: "Facile", "Double out".
    public var variant: LocalizedText?
    /// Objective of the round, when the game has one: "Cible : D7", "Numéro 4".
    public var objective: LocalizedText?
    public var phase: GamePhase
    public var currentPlayer: PlayerIndex
    /// 1-based.
    public var round: Int
    /// For the "4 / 15" header; nil = no limit.
    public var roundLimit: Int?
    public var turn: TurnSnapshot
    /// One row per player, in playing order.
    public var players: [PlayerRow]
    /// Zones to draw for the current player. Empty once finished.
    public var highlights: [BoardHighlight]
    public var grid: ScoreGrid?
    public var finishReason: FinishReason?
    /// Rank of each player, by player index, starting at 1, shared on ties ("1, 1, 3"). Valid at any time.
    public var ranks: [Int]
    /// Sentence of the results screen: "Dernière en vie, avec 2 vies restantes."
    public var outcome: LocalizedText?
    /// Headline naming the winner when it is NOT a player (GAMES.md §2.7): "Le camp A gagne", "Match nul"
    /// (Football). The results screen shows it in place of the winners' names and the score caller says it as
    /// it is. Nil for every game whose winners are the players ranked first, and nil before the game is finished.
    public var winnerTitle: LocalizedText?
    /// Game-level logical fields of GAMES.md: "targets", "king".
    public var facts: [String: FactValue]

    public init(gameID: GameID, title: LocalizedText, variant: LocalizedText? = nil, objective: LocalizedText? = nil,
                phase: GamePhase, currentPlayer: PlayerIndex, round: Int, roundLimit: Int?, turn: TurnSnapshot,
                players: [PlayerRow], highlights: [BoardHighlight] = [], grid: ScoreGrid? = nil,
                finishReason: FinishReason? = nil, ranks: [Int], outcome: LocalizedText? = nil,
                winnerTitle: LocalizedText? = nil, facts: [String: FactValue] = [:]) {
        self.gameID = gameID
        self.title = title
        self.variant = variant
        self.objective = objective
        self.phase = phase
        self.currentPlayer = currentPlayer
        self.round = round
        self.roundLimit = roundLimit
        self.turn = turn
        self.players = players
        self.highlights = highlights
        self.grid = grid
        self.finishReason = finishReason
        self.ranks = ranks
        self.outcome = outcome
        self.winnerTitle = winnerTitle
        self.facts = facts
    }

    /// Players ranked first; several on a tie. Meaningful once `phase == .finished`.
    public var winners: [PlayerIndex] {
        ranks.indices.filter { ranks[$0] == 1 }
    }
}
```

Trois formes ajoutées pour les jeux du lot G4, toutes additives :

- **Surbrillance en disque.** `BoardHighlight.zone` peut valoir `BoardZone.disc(x:y:radius:)` (§4.2) : un disque de centre et de rayon donnés en millimètres nominaux, posé par-dessus les cases (`GAMES.md` §2.9). Il porte comme toute surbrillance un rôle et un propriétaire facultatif, plus l'étiquette (`label` : « +10 ») et le nombre de points de vie (`strength` : 1 à 3). Il ne correspond à aucune case : `contains(_:)` rend `false` pour toute fléchette. Seul Radar s'en sert (une surbrillance `target`, sans propriétaire, par cible). Son dessin est décrit en §8.4.3.
- **Fait en table.** `FactValue.table([[Int]])` porte des lignes d'entiers, négatifs compris : les cinq cibles de Radar, `blobs`, une ligne `[x, y, radius, hitPoints]` par emplacement.
- **Titre des résultats.** `GameSnapshot.winnerTitle` nomme le vainqueur quand ce n'est pas un joueur (`GAMES.md` §2.7, §14.7). Seul le Football le renseigne : « Le camp A gagne » / "Side A wins", « Le camp B gagne » / "Side B wins", « Match nul » / "It's a draw". C'est une phrase complète, la même à l'écran et à la voix : l'écran des résultats l'affiche à la place des noms des vainqueurs (§8.6) et l'annonce la dit telle quelle (§7.3). Ni `DartUI` ni `DartAudio` ne testent l'identifiant du jeu pour cela. Le noyau ne le laisse sortir qu'en phase `finished`, comme `outcome`.

Fichier `DartKit/Sources/DartCore/Game/Ranking.swift` :

```swift
import Foundation

/// Shared-rank computation of GAMES.md §2.7.
public enum Ranking {
    /// `keys[player]` is compared lexicographically and SMALLER IS BETTER (negate a value to rank it descending).
    /// Players with equal keys share a rank and the next rank is skipped: keys [[1], [1], [5]] give [1, 1, 3].
    /// Elimination games prefix the key with 0 for players alive and 1 for eliminated ones, followed for the
    /// latter by minus their elimination order (the last eliminated ranks best).
    public static func ranks(keys: [[Int]]) -> [Int] {
        keys.map { key in
            1 + keys.filter { $0.lexicographicallyPrecedes(key) }.count
        }
    }
}
```

Exemple de clés de classement, pour le Killer à la limite de manches (`GAMES.md` §5.6) : un joueur en vie a la clé `[0, -lives, -kills, -armingProgress]`, un joueur éliminé la clé `[1, -ordreÉlimination]`.

Clés des quatre jeux du lot G4 (la plus petite clé est la meilleure) :

| Jeu | Clé d'un joueur | Remarque |
|---|---|---|
| `beerTap` | `[-poured]` | |
| `football` | `[-sideGoals[side], -advance]`, avec `advance = ball` pour le camp A et `-ball` pour le camp B | les joueurs d'un camp ont la même clé, donc le même rang : `[1, 3, 1, 3]` |
| `radar` | `[-points, -destroyed]` | |
| `golf` | `[toPar]`, avec `toPar = strokes - 3 × holesPlayed` | le moins de coups gagne : pas de signe moins |

### 4.7 Moteur et noyau des tours

Fichier `DartKit/Sources/DartCore/Game/GameEngine.swift` :

```swift
import Foundation

/// A game as a deterministic reducer (GAMES.md §2.4): same configuration and same inputs give the same snapshots
/// and the same events, on every machine and every version.
/// Implementations MUST be value types (a copy is an independent game) and MUST NOT read a clock, the system random
/// generator or any global state.
public protocol GameEngine: Sendable {
    /// Validates the configuration and performs the initial draws. Throws `GameConfigurationError`.
    init(configuration: GameConfiguration) throws
    /// The configuration, with the options completed by their defaults.
    var configuration: GameConfiguration { get }
    /// Applies one input. A refused input changes nothing.
    /// `position` is the recorded impact of a dart in NOMINAL board millimetres, when known (GAMES.md §2.13).
    /// It is part of the input for a position-dependent game, and is ignored by every other game and for `endTurn`.
    mutating func apply(_ input: GameInput, position: BoardPoint?) -> InputOutcome
    /// Presentation of the current state.
    var snapshot: GameSnapshot { get }
}

extension GameEngine {
    /// An input without a recorded position.
    public mutating func apply(_ input: GameInput) -> InputOutcome {
        apply(input, position: nil)
    }
}

// MARK: - Turn-based kernel (GAMES.md §2.4 to §2.10 and §2.13, shared by every v1 game)

/// Number of darts of a full turn.
public let dartsPerTurn = 3

/// What a rule sees when something happens in a turn.
public struct TurnContext: Sendable {
    public let players: [Player]
    public let currentPlayer: PlayerIndex
    /// 1-based.
    public let round: Int
    /// Darts of the current turn in order; in `dartThrown`, the dart being applied is the last one.
    public let darts: [Hit]
    /// Recorded positions of those darts, aligned with `darts`: nominal board millimetres, nil when a dart has none.
    /// Read ONLY by a position-dependent game (GAMES.md §2.13), and then through `impact` or `impact(ofDart:)`.
    public let positions: [BoardPoint?]
    public let phase: GamePhase

    /// `positions` may be shorter than `darts`: the missing entries are nil.
    public init(players: [Player], currentPlayer: PlayerIndex, round: Int, darts: [Hit],
                positions: [BoardPoint?] = [], phase: GamePhase) {
        self.players = players
        self.currentPlayer = currentPlayer
        self.round = round
        self.darts = darts
        self.positions = darts.indices.map { $0 < positions.count ? positions[$0] : nil }
        self.phase = phase
    }

    /// Impact point of dart `index` of the turn, by the three rules of GAMES.md §2.13: none for MISS, else the
    /// recorded position, else the canonical position of the bed. Nil also when `index` is out of range.
    public func impact(ofDart index: Int) -> ImpactPoint? {
        guard darts.indices.contains(index) else { return nil }
        return ImpactPoint(hit: darts[index], position: positions[index])
    }

    /// Impact point of the last dart of the turn: in `dartThrown`, the dart being applied.
    public var impact: ImpactPoint? {
        impact(ofDart: darts.count - 1)
    }

    /// True during the first turn of the game (round 1, first player). In `turnStarted` it singles out the call
    /// made at creation: every later call has `round > 1` or `currentPlayer > 0`.
    public var isFirstTurnOfGame: Bool {
        round == 1 && currentPlayer == 0
    }
}

/// What a dart does to the flow of the turn.
public enum DartVerdict: Hashable, Sendable {
    /// Nothing special: the turn closes by itself after the third dart.
    case turnContinues
    /// The rule closes the turn now (bust, self-elimination, the double of the hole at Golf).
    case turnClosed
    /// The game ends on this dart.
    case gameFinished(FinishReason)
}

/// Game-specific part of a snapshot. The kernel adds phase, current player, round, darts and ranks.
public struct RulesPresentation: Hashable, Sendable {
    public var title: LocalizedText
    public var variant: LocalizedText?
    public var objective: LocalizedText?
    /// One row per player in playing order. `rank` is overwritten by the kernel with `ranks()`.
    public var rows: [PlayerRow]
    /// Captions of the darts of the current turn, aligned with `TurnContext.darts`; may be shorter.
    public var dartCaptions: [DartCaption?]
    public var turnSummary: LocalizedText?
    public var turnHint: LocalizedText?
    /// Highlights for the current player. The kernel clears them once the game is finished.
    public var highlights: [BoardHighlight]
    public var grid: ScoreGrid?
    /// Results sentence; only read once the game is finished.
    public var outcome: LocalizedText?
    /// Headline naming the winner when it is not a player (Football: a side, or a draw); only read once the
    /// game is finished. Nil when the winners are the players ranked first.
    public var winnerTitle: LocalizedText?
    public var facts: [String: FactValue]

    public init(title: LocalizedText, variant: LocalizedText? = nil, objective: LocalizedText? = nil,
                rows: [PlayerRow], dartCaptions: [DartCaption?] = [], turnSummary: LocalizedText? = nil,
                turnHint: LocalizedText? = nil, highlights: [BoardHighlight] = [], grid: ScoreGrid? = nil,
                outcome: LocalizedText? = nil, winnerTitle: LocalizedText? = nil,
                facts: [String: FactValue] = [:]) {
        self.title = title
        self.variant = variant
        self.objective = objective
        self.rows = rows
        self.dartCaptions = dartCaptions
        self.turnSummary = turnSummary
        self.turnHint = turnHint
        self.highlights = highlights
        self.grid = grid
        self.outcome = outcome
        self.winnerTitle = winnerTitle
        self.facts = facts
    }
}

/// The rules of ONE game (GAMES.md §3 to §16). The kernel `TurnBasedEngine` owns everything that is common:
/// phases, the three darts, `endTurn`, skipping eliminated players, rounds, the round limit, `dartRegistered`,
/// `turnCompleted`, `roundStarted`, `turnStarted` and `gameFinished`. A rule never emits those five events.
/// Implementations are value types holding the whole game-specific state.
public protocol TurnBasedRules: Sendable {
    static var descriptor: GameDescriptor { get }

    /// Initial state (GAMES.md §n.3). `configuration.options` is already validated against the descriptor and
    /// completed with defaults. Initial draws consume `random` in the order given by GAMES.md.
    /// Throws `GameConfigurationError.invalidOptionValue` for a custom value it cannot read.
    init(configuration: GameConfiguration, random: inout SeededRandom) throws

    /// Round limit of this game (`maxRounds`, `rounds`, `targets.count`); nil = none.
    var roundLimit: Int? { get }

    func isEliminated(_ player: PlayerIndex) -> Bool

    /// Start-of-turn effects (Killer expert redraw, Radar moving targets) and reset of per-turn scratch state
    /// (turn-start score for a bust). Called once at creation for the first turn of the game (its events are
    /// discarded; `context.isFirstTurnOfGame` is true for that call only), then at step 4 of every `endTurn`
    /// that starts a turn. A player's k-th turn is always in round k.
    /// Events appended here come just before `turnStarted`.
    mutating func turnStarted(_ context: TurnContext, random: inout SeededRandom, events: inout [GameEvent])

    /// Effect of one accepted dart of `context.currentPlayer` (GAMES.md §n.4). `dartRegistered` is already in `events`.
    /// Append the effects in the order they happen. When returning `.gameFinished`, append nothing after the
    /// winning effects: the kernel adds `gameFinished` and no `turnCompleted`.
    /// `random` is the generator of the game, for a rule that draws while a dart is applied (Radar replaces a
    /// destroyed target); most rules never touch it. A position-dependent rule reads `context.impact`, never `hit`,
    /// to decide what the dart touches.
    mutating func dartThrown(_ hit: Hit, _ context: TurnContext, random: inout SeededRandom,
                             events: inout [GameEvent]) -> DartVerdict

    /// Turn-closing effects, exactly once per turn (GAMES.md §2.4): `turnScored`, `oneEighty`, `highTurn`, `halved`…
    /// Called after the third dart, after `.turnClosed`, or on an early `endTurn` (possibly with zero darts).
    /// NOT called when the game finishes on a dart. The kernel appends `turnCompleted` afterwards.
    mutating func turnClosed(_ context: TurnContext, events: inout [GameEvent])

    /// Rank of every player, by player index (GAMES.md §2.7). Valid at any time. Use `Ranking.ranks(keys:)`.
    func ranks() -> [Int]

    /// Scoreboard, captions, highlights and facts (GAMES.md §n.7), for `context.currentPlayer`.
    func presentation(_ context: TurnContext) -> RulesPresentation
}

/// The common turn machine of GAMES.md §2.4, generic over the rules of a game.
public struct TurnBasedEngine<Rules: TurnBasedRules>: GameEngine {
    public let configuration: GameConfiguration
    public private(set) var rules: Rules
    public private(set) var phase: GamePhase
    public private(set) var currentPlayer: PlayerIndex
    public private(set) var round: Int
    /// Darts of the current turn.
    public private(set) var darts: [Hit]
    /// Recorded positions of the darts of the current turn, aligned with `darts`.
    public private(set) var positions: [BoardPoint?]
    public private(set) var finishReason: FinishReason?
    private var random: SeededRandom

    public init(configuration: GameConfiguration) throws {
        let descriptor = Rules.descriptor
        guard configuration.gameID == descriptor.id else {
            throw GameConfigurationError.unknownGame(configuration.gameID)
        }
        if let issue = descriptor.validate(options: configuration.options, playerCount: configuration.players.count).first {
            throw issue
        }
        var normalised = configuration
        normalised.options = descriptor.normalized(configuration.options)
        var random = SeededRandom(seed: configuration.seed)
        var rules = try Rules(configuration: normalised, random: &random)
        var discarded: [GameEvent] = []
        let first = TurnContext(players: normalised.players, currentPlayer: 0, round: 1, darts: [], phase: .throwing)
        rules.turnStarted(first, random: &random, events: &discarded)
        self.configuration = normalised
        self.rules = rules
        self.phase = .throwing
        self.currentPlayer = 0
        self.round = 1
        self.darts = []
        self.positions = []
        self.finishReason = nil
        self.random = random
    }

    private var context: TurnContext {
        TurnContext(players: configuration.players, currentPlayer: currentPlayer, round: round, darts: darts,
                    positions: positions, phase: phase)
    }

    public mutating func apply(_ input: GameInput, position: BoardPoint?) -> InputOutcome {
        switch (phase, input) {
        case (.finished, _):
            return .rejected(.gameFinished)
        case (.turnComplete, .dart):
            return .rejected(.turnComplete)
        case (.throwing, .dart(let hit)):
            return .accepted(applyDart(hit, position: position))
        case (.throwing, .endTurn), (.turnComplete, .endTurn):
            return .accepted(applyEndTurn())
        }
    }

    private mutating func applyDart(_ hit: Hit, position: BoardPoint?) -> [GameEvent] {
        darts.append(hit)
        positions.append(position)
        var events: [GameEvent] = [.dartRegistered(player: currentPlayer, hit: hit)]
        switch rules.dartThrown(hit, context, random: &random, events: &events) {
        case .gameFinished(let reason):
            phase = .finished
            finishReason = reason
            events.append(.gameFinished(reason: reason))
        case .turnClosed:
            closeTurn(&events)
        case .turnContinues:
            if darts.count >= dartsPerTurn { closeTurn(&events) }
        }
        return events
    }

    private mutating func closeTurn(_ events: inout [GameEvent]) {
        rules.turnClosed(context, events: &events)
        events.append(.turnCompleted(player: currentPlayer))
        phase = .turnComplete
    }

    private mutating func applyEndTurn() -> [GameEvent] {
        var events: [GameEvent] = []
        if phase == .throwing { closeTurn(&events) }
        let count = configuration.players.count
        var next = currentPlayer
        for step in 1...count {
            let candidate = (currentPlayer + step) % count
            if !rules.isEliminated(candidate) {
                next = candidate
                break
            }
        }
        if next <= currentPlayer {
            if let limit = rules.roundLimit, round >= limit {
                // The confirmed turn is over and no turn starts: the volley is emptied (GAMES.md §2.4, step 3).
                darts = []
                positions = []
                phase = .finished
                finishReason = .roundLimit
                events.append(.gameFinished(reason: .roundLimit))
                return events
            }
            round += 1
            events.append(.roundStarted(round: round))
        }
        currentPlayer = next
        darts = []
        positions = []
        phase = .throwing
        rules.turnStarted(context, random: &random, events: &events)
        events.append(.turnStarted(player: currentPlayer, round: round))
        return events
    }

    public var snapshot: GameSnapshot {
        let presentation = rules.presentation(context)
        let ranks = rules.ranks()
        var rows = presentation.rows
        for index in rows.indices where index < ranks.count {
            rows[index].rank = ranks[index]
        }
        let slots = darts.enumerated().map { index, hit in
            DartSlot(hit: hit, caption: index < presentation.dartCaptions.count ? presentation.dartCaptions[index] : nil)
        }
        return GameSnapshot(
            gameID: configuration.gameID,
            title: presentation.title,
            variant: presentation.variant,
            objective: presentation.objective,
            phase: phase,
            currentPlayer: currentPlayer,
            round: round,
            roundLimit: rules.roundLimit,
            turn: TurnSnapshot(darts: slots, capacity: dartsPerTurn, summary: presentation.turnSummary, hint: presentation.turnHint),
            players: rows,
            highlights: phase == .finished ? [] : presentation.highlights,
            grid: presentation.grid,
            finishReason: finishReason,
            ranks: ranks,
            outcome: phase == .finished ? presentation.outcome : nil,
            winnerTitle: phase == .finished ? presentation.winnerTitle : nil,
            facts: presentation.facts
        )
    }
}
```

Ce que fait le noyau, et donc ce qu'une règle ne refait jamais :

| Étape de `GAMES.md` §2.4 | Noyau `TurnBasedEngine` | Règle `TurnBasedRules` |
|---|---|---|
| Refus d'une entrée hors phase | `.rejected(.turnComplete)` ou `.rejected(.gameFinished)`, état inchangé | — |
| `dart` : ajout à la volée, `dartRegistered` | oui ; range aussi la position enregistrée, alignée sur la volée (`TurnContext.positions`) | — |
| Effet de la fléchette | appelle `dartThrown` avec le générateur de la partie | applique §n.4, ajoute ses événements, rend un `DartVerdict` ; un jeu dépendant de la position lit `context.impact` ; Radar tire le remplacement d'une cible détruite |
| Fin de partie sur une fléchette | `phase = finished`, `gameFinished(reason)` en dernier, pas de `turnCompleted` | rend `.gameFinished(reason)` |
| Clôture du tour (3e fléchette, verdict `.turnClosed`, ou `endTurn` anticipé) | appelle `turnClosed`, puis `turnCompleted`, `phase = turnComplete` | effets de clôture : `turnScored`, `oneEighty`, `highTurn`, `halved` |
| `endTurn` : joueur suivant non éliminé | parcours circulaire avec `isEliminated` | dit qui est éliminé |
| Fin de manche, limite de manches | compare `round` à `roundLimit` ; à la limite, vide la volée et ses positions, `phase = finished`, `gameFinished(.roundLimit)` ; sinon `round += 1` et `roundStarted` | donne `roundLimit` |
| Début du tour | volée et positions vidées, `phase = throwing`, appelle `turnStarted`, puis `turnStarted(player, round)` | retirage du Killer expert, déplacement des cibles de Radar (`blobsMoved`), remise à zéro de son état de tour |
| Classement | lit `ranks()` à chaque instantané | critères du jeu, avec `Ranking.ranks(keys:)` |
| Aucune surbrillance une fois la partie finie | efface `highlights` | — |
| Phrase et titre des résultats | ne laisse sortir `outcome` et `winnerTitle` qu'en phase `finished` | les donne dans `presentation` ; `winnerTitle` seulement si le vainqueur n'est pas un joueur |

Obligations d'une règle :

- c'est un `struct` dont **tout** l'état est dans ses propriétés stockées ; pas de classe, pas de variable globale ;
- elle n'utilise que le `SeededRandom` qu'on lui passe, dans l'ordre de tirage fixé par `GAMES.md` ; jamais `Int.random`, `shuffled()`, `Date()` ;
- elle n'émet aucun des cinq événements du noyau : `dartRegistered`, `turnCompleted`, `roundStarted`, `turnStarted`, `gameFinished` ;
- elle expose dans `facts` **toute valeur qu'une règle relit plus tard** (score, vies, marques, zones, progression, propriétaires, cibles). C'est ce qui rend `GameMatch.effectKey(for:position:)` juste (§4.8) ;
- elle ne lit la position que si son descripteur déclare `dependsOnPosition`, et seulement par `context.impact` ou `context.impact(ofDart:)` ; elle ne calcule alors qu'en entiers (`GAMES.md` §2.13). Une règle qui ne dépend pas de la position ne touche ni à `positions` ni à `impact` : deux fléchettes de même case y ont le même effet (`GAMES.md` §2.2) ;
- `presentation` est une fonction pure de l'état : l'appeler ne change rien.

**Les trois moments où une règle peut tirer au sort.** Le générateur de la partie est unique et vit dans le noyau ; il est passé à la règle à trois endroits, et l'ordre des tirages est celui du journal :

| Moment | Appel | Exemples |
|---|---|---|
| création | `init(configuration:random:)` | zones du Killer, maisons de Conquérant, les cinq cibles de Radar |
| début d'un tour | `turnStarted(_:random:events:)` | retirage du Killer expert ; cibles mobiles de Radar |
| pendant une fléchette | `dartThrown(_:_:random:events:)` | remplacement d'une cible de Radar détruite |

`turnStarted` est aussi appelé une fois à la création, pour le premier tour ; `context.isFirstTurnOfGame` n'est vrai dans `turnStarted` que pour cet appel. Les cibles mobiles de Radar ne bougent pas à cet appel (`GAMES.md` §15.4) : la règle écrit `guard moving, !context.isFirstTurnOfGame`. Quand un `endTurn` termine la partie à la limite de manches, `turnStarted` n'est pas appelé : rien n'est tiré. La volée, elle, est vidée comme à toute confirmation : le tour confirmé est fini, et `snapshot.turn.darts` reste aligné sur `GameMatch.currentTurn`, qui ne compte que les fléchettes situées après le dernier `endTurn` du journal (§4.8). Une partie finie **sur une fléchette** garde sa volée, celle du tour gagnant, qu'aucun `endTurn` n'a confirmé. Conséquence pour une règle : après une fin à la limite de manches, `presentation` reçoit un contexte sans fléchette alors que l'état de tour de la règle est encore celui du dernier tour ; elle ne suppose donc pas que les deux ont la même longueur (le noyau ignore les légendes en trop de `dartCaptions`).

L'exemple complet d'une règle est en §5.4.

### 4.8 Registre et partie

Fichier `DartKit/Sources/DartCore/Game/GameRegistry.swift` :

```swift
import Foundation

/// A game the application can offer: its descriptor and the way to create its engine.
public struct GameDefinition: Sendable, Identifiable {
    public let descriptor: GameDescriptor
    private let make: @Sendable (GameConfiguration) throws -> any GameEngine

    public var id: GameID { descriptor.id }

    public init(descriptor: GameDescriptor, makeEngine: @escaping @Sendable (GameConfiguration) throws -> any GameEngine) {
        self.descriptor = descriptor
        self.make = makeEngine
    }

    /// A game written as `TurnBasedRules`: `GameDefinition(rules: X01Rules.self)`.
    public init<Rules: TurnBasedRules>(rules: Rules.Type) {
        self.init(descriptor: Rules.descriptor) { try TurnBasedEngine<Rules>(configuration: $0) }
    }

    /// Throws `GameConfigurationError`.
    public func makeEngine(_ configuration: GameConfiguration) throws -> any GameEngine {
        guard configuration.gameID == descriptor.id else {
            throw GameConfigurationError.unknownGame(configuration.gameID)
        }
        return try make(configuration)
    }
}

/// The list of games, in display order. The home screen, the setup screen and the play screen are driven by it.
/// DartGames provides the populated value (`GameRegistry.standard`).
public struct GameRegistry: Sendable {
    public let definitions: [GameDefinition]

    public init(_ definitions: [GameDefinition]) {
        self.definitions = definitions
    }

    public var descriptors: [GameDescriptor] {
        definitions.map(\.descriptor)
    }

    public func definition(for id: GameID) -> GameDefinition? {
        definitions.first { $0.id == id }
    }

    /// Creates a new game. Throws `GameConfigurationError`.
    public func makeMatch(_ configuration: GameConfiguration) throws -> GameMatch {
        guard let definition = definition(for: configuration.gameID) else {
            throw GameConfigurationError.unknownGame(configuration.gameID)
        }
        return try GameMatch(definition: definition, configuration: configuration)
    }

    /// Rebuilds a saved game by replaying its journal. Throws `GameConfigurationError`.
    public func restoreMatch(_ record: MatchRecord) throws -> GameMatch {
        guard let definition = definition(for: record.configuration.gameID) else {
            throw GameConfigurationError.unknownGame(record.configuration.gameID)
        }
        return try GameMatch(definition: definition, record: record)
    }
}
```

Fichier `DartKit/Sources/DartCore/Game/GameMatch.swift` :

```swift
import Foundation

/// Where a dart came from.
public enum DartOrigin: String, Codable, Sendable {
    /// Tap on the virtual board.
    case manual
    /// Live camera detection.
    case camera
    /// Manual-trigger scan of a whole turn ("Scanner la volée").
    case scan
    /// Tip tapped on a photo.
    case photo
}

/// One dart of the journal: the scored hit that the engine sees, plus what the UI needs to keep with it.
public struct DartRecord: Identifiable, Hashable, Codable, Sendable {
    /// For a camera dart: the id of its `DartObservation`, so that corrections reach the vision layer.
    public let id: UUID
    public var hit: Hit
    /// Recorded impact in NOMINAL board millimetres, when known: the measured tip (camera) or the tapped point
    /// (virtual board). Nil for a dart entered by its hit only. Passed to the engine with the hit; only a
    /// position-dependent game reads it (GAMES.md §2.13). Also feeds heat maps.
    public var position: BoardPoint?
    public var origin: DartOrigin
    /// Medium-confidence detection: counted, shown as "à vérifier" until corrected or until the turn is confirmed.
    public var needsReview: Bool
    /// The player changed the hit after it was first recorded.
    public var corrected: Bool

    public init(id: UUID = UUID(), hit: Hit, position: BoardPoint? = nil, origin: DartOrigin = .manual,
                needsReview: Bool = false, corrected: Bool = false) {
        self.id = id
        self.hit = hit
        self.position = position
        self.origin = origin
        self.needsReview = needsReview
        self.corrected = corrected
    }
}

/// One entry of the journal.
public enum LogEntry: Hashable, Codable, Sendable {
    case dart(DartRecord)
    case endTurn

    public var input: GameInput {
        switch self {
        case .dart(let record): return .dart(record.hit)
        case .endTurn: return .endTurn
        }
    }

    /// Recorded position that goes to the engine with `input`; nil for `endTurn` and for a dart without one.
    public var position: BoardPoint? {
        switch self {
        case .dart(let record): return record.position
        case .endTurn: return nil
        }
    }
}

/// A game as it is saved: enough to rebuild every state.
public struct MatchRecord: Hashable, Codable, Sendable {
    public var configuration: GameConfiguration
    public var entries: [LogEntry]
    public var startedAt: Date

    public init(configuration: GameConfiguration, entries: [LogEntry] = [], startedAt: Date) {
        self.configuration = configuration
        self.entries = entries
        self.startedAt = startedAt
    }
}

/// Result of an undo or of a correction. Past events are never replayed: the UI resynchronises on `snapshot`.
public struct EditOutcome: Hashable, Sendable {
    /// False when there was nothing to edit (empty journal, index out of the current turn).
    public var applied: Bool
    /// Darts removed from the journal by the replay rule of GAMES.md §2.5 (they arrived outside `throwing`).
    public var dropped: [DartRecord]

    public init(applied: Bool, dropped: [DartRecord] = []) {
        self.applied = applied
        self.dropped = dropped
    }
}

/// Opaque equality key: two darts with the same key would have exactly the same effect if thrown now.
public struct EffectKey: Hashable, Sendable {
    let rejected: Bool
    let events: [GameEvent]
    let phase: GamePhase
    let ranks: [Int]
    let playerFacts: [[String: FactValue]]
    let facts: [String: FactValue]
}

/// A running game: one engine plus its journal. Implements undo and corrections by editing the journal and
/// replaying it from the start (GAMES.md §2.5). A value type: copy it to try something.
public struct GameMatch: Sendable {
    public let definition: GameDefinition
    /// Configuration with the options completed by their defaults.
    public let configuration: GameConfiguration
    public let startedAt: Date
    /// The journal: accepted inputs only, in order.
    public private(set) var entries: [LogEntry]
    /// Presentation of the current state; refreshed by every mutating call.
    public private(set) var snapshot: GameSnapshot
    private var engine: any GameEngine

    /// Throws `GameConfigurationError`.
    public init(definition: GameDefinition, configuration: GameConfiguration, startedAt: Date = Date()) throws {
        let engine = try definition.makeEngine(configuration)
        self.definition = definition
        self.configuration = engine.configuration
        self.startedAt = startedAt
        self.entries = []
        self.snapshot = engine.snapshot
        self.engine = engine
    }

    /// Rebuilds a saved game. Entries that the rules refuse are dropped, as in any replay.
    public init(definition: GameDefinition, record: MatchRecord) throws {
        try self.init(definition: definition, configuration: record.configuration, startedAt: record.startedAt)
        _ = replay(record.entries)
    }

    public var players: [Player] { configuration.players }
    public var phase: GamePhase { snapshot.phase }
    public var canUndo: Bool { !entries.isEmpty }

    public var record: MatchRecord {
        MatchRecord(configuration: configuration, entries: entries, startedAt: startedAt)
    }

    /// Darts of the current turn: the darts after the last `endTurn` of the journal (GAMES.md §2.5).
    /// Still editable in `turnComplete` and `finished`.
    public var currentTurn: [DartRecord] {
        entries[currentTurnStart...].compactMap {
            if case .dart(let record) = $0 { return record }
            return nil
        }
    }

    // MARK: Inputs

    /// Adds one dart, with its recorded position when it has one. Rejected outside `throwing`; a rejected dart
    /// is not logged.
    @discardableResult
    public mutating func throwDart(_ dart: DartRecord) -> InputOutcome {
        let outcome = engine.apply(.dart(dart.hit), position: dart.position)
        if outcome.isAccepted {
            entries.append(.dart(dart))
            snapshot = engine.snapshot
        }
        return outcome
    }

    /// The explicit confirmation. Clears `needsReview` on the darts of the turn that ends.
    @discardableResult
    public mutating func endTurn() -> InputOutcome {
        let outcome = engine.apply(.endTurn)
        if outcome.isAccepted {
            for index in currentTurnStart..<entries.count {
                if case .dart(var record) = entries[index] {
                    record.needsReview = false
                    entries[index] = .dart(record)
                }
            }
            entries.append(.endTurn)
            snapshot = engine.snapshot
        }
        return outcome
    }

    // MARK: Undo and corrections (journal edit + full replay)

    /// Removes the last entry, whatever it is. Unlimited depth; does nothing on an empty journal.
    @discardableResult
    public mutating func undo() -> EditOutcome {
        guard !entries.isEmpty else { return EditOutcome(applied: false) }
        return replay(Array(entries.dropLast()))
    }

    /// Replaces dart `index` (0-based) of the current turn. Keeps its `id`, clears `needsReview`,
    /// sets `corrected` when the hit changes. The whole dart is replaced, position included: `position` is
    /// recorded when the correction gives one (reticle moved, new tap) and the old one is ERASED otherwise
    /// (hit picked in a list), so a position never outlives a change of hit that does not give it again
    /// (GAMES.md §2.5).
    @discardableResult
    public mutating func replaceDart(at index: Int, with hit: Hit, position: BoardPoint? = nil) -> EditOutcome {
        guard let entryIndex = entryIndex(ofCurrentTurnDart: index), case .dart(var record) = entries[entryIndex] else {
            return EditOutcome(applied: false)
        }
        if record.hit != hit { record.corrected = true }
        record.hit = hit
        record.position = position
        record.needsReview = false
        var edited = entries
        edited[entryIndex] = .dart(record)
        return replay(edited)
    }

    /// Removes dart `index` of the current turn (phantom detection); the following darts shift.
    @discardableResult
    public mutating func removeDart(at index: Int) -> EditOutcome {
        guard let entryIndex = entryIndex(ofCurrentTurnDart: index) else { return EditOutcome(applied: false) }
        var edited = entries
        edited.remove(at: entryIndex)
        return replay(edited)
    }

    /// Sets or clears the "à vérifier" mark of dart `index` of the current turn. No replay: the hit is unchanged.
    /// Cleared when the player accepts the dart as it is; set when the camera reports that an earlier dart moved.
    public mutating func setNeedsReview(_ needsReview: Bool, at index: Int) {
        guard let entryIndex = entryIndex(ofCurrentTurnDart: index), case .dart(var record) = entries[entryIndex] else { return }
        record.needsReview = needsReview
        entries[entryIndex] = .dart(record)
    }

    // MARK: Queries

    /// Groups the darts that would have exactly the same effect if thrown now: same events (apart from
    /// `dartRegistered`), same phase, same ranks and same facts afterwards. Feeds `DartObservation.tier(collapsingBy:)`
    /// so that a doubt between two hits of equal effect does not bother the player (VISION.md §7.4).
    /// `position` is the measured tip shared by the candidate hits. A position-dependent game is keyed on
    /// (hit, position): at equal position every candidate other than MISS has the same key (GAMES.md §2.13).
    /// The other games ignore it.
    public func effectKey(for hit: Hit, position: BoardPoint? = nil) -> EffectKey {
        var copy = engine
        guard case .accepted(let events) = copy.apply(.dart(hit), position: position) else {
            return EffectKey(rejected: true, events: [], phase: snapshot.phase, ranks: [], playerFacts: [], facts: [:])
        }
        let after = copy.snapshot
        let effects = events.filter {
            if case .dartRegistered = $0 { return false }
            return true
        }
        return EffectKey(rejected: false, events: effects, phase: after.phase, ranks: after.ranks,
                         playerFacts: after.players.map(\.facts), facts: after.facts)
    }

    // MARK: Private

    private var currentTurnStart: Int {
        (entries.lastIndex { $0 == .endTurn }).map { $0 + 1 } ?? 0
    }

    private func entryIndex(ofCurrentTurnDart index: Int) -> Int? {
        guard index >= 0 else { return nil }
        var seen = 0
        for entryIndex in currentTurnStart..<entries.count {
            if case .dart = entries[entryIndex] {
                if seen == index { return entryIndex }
                seen += 1
            }
        }
        return nil
    }

    /// Replay rule of GAMES.md §2.5: start from a fresh engine, feed every entry, drop the ones that are refused.
    private mutating func replay(_ newEntries: [LogEntry]) -> EditOutcome {
        guard var fresh = try? definition.makeEngine(configuration) else { return EditOutcome(applied: false) }
        var kept: [LogEntry] = []
        var dropped: [DartRecord] = []
        for entry in newEntries {
            if fresh.apply(entry.input, position: entry.position).isAccepted {
                kept.append(entry)
            } else if case .dart(let record) = entry {
                dropped.append(record)
            }
        }
        engine = fresh
        entries = kept
        snapshot = fresh.snapshot
        return EditOutcome(applied: true, dropped: dropped)
    }
}
```

Sémantique de `GameMatch`, à connaître par `DartUI` :

| Opération | Effet sur le journal | Événements rendus |
|---|---|---|
| `throwDart` | passe au moteur la case et la position enregistrée (`record.position`) ; ajoute l'entrée si le moteur l'accepte | ceux de l'entrée ; rien si elle est refusée |
| `endTurn` | ajoute `endTurn` ; efface `needsReview` sur les fléchettes du tour confirmé | ceux de l'entrée |
| `undo` | retire la dernière entrée, rejoue tout | aucun : l'interface se resynchronise sur `snapshot` |
| `replaceDart` | remplace la fléchette **entière** : la case, et la position, qui est enregistrée si la correction en donne une et effacée sinon ; rejoue tout | aucun |
| `removeDart` | retire la fléchette, position comprise ; rejoue tout | aucun |
| `setNeedsReview` | change une marque, sans rejeu | aucun |

Le rejeu (`replay`) repasse chaque entrée au moteur avec sa position. Les fléchettes que le rejeu refuse sont retirées du journal et rendues dans `EditOutcome.dropped`.

- Le « tour courant » est l'ensemble des fléchettes situées après le dernier `endTurn` du journal. Il reste modifiable en phase `turnComplete` et `finished` (`GAMES.md` §2.5).
- `DartRecord.id` survit aux corrections : c'est le lien avec l'observation de la caméra (§8.6).
- `MatchRecord` est `Codable` : c'est la sauvegarde d'une partie, positions comprises. `GameRegistry.restoreMatch` la rejoue ; une partie de Radar se rejoue donc à l'identique.
- **Date de début.** `startedAt` est une donnée de la partie, enregistrée dans `MatchRecord`. La valeur par défaut `Date()` de `GameMatch.init(definition:configuration:startedAt:)` est la seule lecture d'horloge possible dans `DartCore`, et elle ne sert qu'aux tests et aux vecteurs, qui ne comparent pas cette date : `GameRegistry.makeMatch(_:)` et `DartTestSupport` passent par elle. L'application ne la laisse jamais jouer : `AppModel` crée toute partie neuve avec `startedAt: environment.now()` (§8.4.9, §8.5), et une partie de test ou d'aperçu a ainsi la même date à chaque exécution.
- `effectKey(for:position:)` essaie la fléchette sur une **copie** du moteur. Deux fléchettes de même clé ont le même effet immédiat et laissent les mêmes faits : au Killer, `S11`, `D11` et `T11` ont la même clé ; au X01 avec entrée en double, tant que le joueur n'a pas ouvert, `S5` et `T6` aussi. `DartUI` passe cette fonction à `DartObservation.tier(collapsingBy:)` (`VISION.md` §7.4), **avec la pointe mesurée** : `{ match.effectKey(for: $0, position: observation.tip) }`.
- Pour un jeu dépendant de la position, la clé porte ainsi sur le couple (case, position) : à position égale, toutes les cases candidates autres que `MISS` ont la même clé, et un doute entre deux cases voisines ne dérange pas le joueur (`GAMES.md` §2.13). Le doute qui reste, celui d'une pointe à moins de son incertitude du bord d'une cible, se traite en appelant cette même fonction en quatre points voisins de la pointe (§8.4.8). Les autres jeux ignorent la position : leur clé ne dépend que de la case.
- Aucune vérification de cohérence n'est faite entre la case et la position : le moteur prend la position telle quelle (`GAMES.md` §2.13). C'est l'interface qui garantit qu'une position ne survit pas à un changement de case qui ne la redonne pas, en passant `position: nil` à `replaceDart` quand la case est choisie dans une liste (§8.6).

### 4.9 Ce que `DartCore` fournit à `DartVision`

`VISION.md` §9.1 demande exactement trois symboles. Ils existent sous les noms demandés ; le fichier `DartCoreBridge.swift` de `DartVision` n'a donc rien à contenir : le squelette de F0 ne le crée pas, et le lot V1 peut s'en passer.

| Demandé par `VISION.md` §9.1 | Fourni par |
|---|---|
| `BoardPoint` : `Hashable, Codable, Sendable`, `x`, `y`, `init(x:y:)` | `Board/BoardPoint.swift` |
| `Hit` : `Hashable, Codable, Sendable`, 63 valeurs | `Board/Hit.swift` |
| `BoardGeometry.standard`, `sectorOrder`, `innerBullRadius`, `outerBullRadius`, `trebleInnerRadius`, `trebleOuterRadius`, `doubleInnerRadius`, `doubleOuterRadius`, `hit(at:)` | `Board/BoardGeometry.swift` |

`hit(at:)` attend un point en coordonnées **nominales** et rend `MISS` au-delà du rayon extérieur du double, comme l'exige `VISION.md`, ainsi que pour un point dont une coordonnée n'est pas finie (§4.2).

---

## 5. DartGames

### 5.1 Rôle et dépendances

`DartGames` contient les règles des quatorze jeux de `GAMES.md` §3 à §16 et le registre. Il dépend de `DartCore` seulement. Chaque jeu est **un `struct` conforme à `TurnBasedRules`**, dans son propre dossier ; il n'y a aucun fichier partagé entre deux lots de jeux.

### 5.2 API publique

`DartUI` n'utilise qu'un symbole : `GameRegistry.standard`. Les types de règles sont publics pour le registre et pour les tests.

Fichier `DartKit/Sources/DartGames/GameCatalog.swift` (écrit par F0, figé) :

```swift
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
```

L'ordre du registre est l'ordre d'affichage de l'accueil. C'est celui du catalogue de `GAMES.md` §1, repris par `DESIGN.md` §4 : les sept jeux Dartsee documentés, les quatre jeux Dartsee de conception propre, puis les trois jeux classiques. La maquette `Main` ne montre que dix cartes, dans un ordre plus ancien ; sur le nombre et l'ordre des cartes, `DESIGN.md` §4 l'emporte sur elle.

| Jeu (`GameID`) | Type | Fichier principal | Lot | `GAMES.md` | Palier |
|---|---|---|---|---|---|
| `x01` | `X01Rules` | `X01/X01Rules.swift` | G1 | §3 | P0 |
| `cricket` | `CricketRules` | `Cricket/CricketRules.swift` | G1 | §4 | P0 |
| `highScore` | `HighScoreRules` | `HighScore/HighScoreRules.swift` | G1 | §8 | P2 |
| `killer` | `KillerRules` | `Killer/KillerRules.swift` | G2 | §5 | P0 |
| `shanghai` | `ShanghaiRules` | `Shanghai/ShanghaiRules.swift` | G2 | §7 | P0 |
| `aroundTheClock` | `AroundTheClockRules` | `AroundTheClock/AroundTheClockRules.swift` | G2 | §6 | P2 |
| `moonLanding` | `MoonLandingRules` | `MoonLanding/MoonLandingRules.swift` | G3 | §10 | P0 |
| `fight` | `FightRules` | `Fight/FightRules.swift` | G3 | §11 | P0 |
| `conqueror` | `ConquerorRules` | `Conqueror/ConquerorRules.swift` | G3 | §12 | P0 |
| `halveIt` | `HalveItRules` | `HalveIt/HalveItRules.swift` | G3 | §9 | P2 |
| `beerTap` | `BeerTapRules` | `BeerTap/BeerTapRules.swift` | G4 | §13 | P1 |
| `football` | `FootballRules` | `Football/FootballRules.swift` | G4 | §14 | P1 |
| `radar` | `RadarRules` | `Radar/RadarRules.swift` | G4 | §15 | P1 |
| `golf` | `GolfRules` | `Golf/GolfRules.swift` | G4 | §16 | P1 |

Un lot peut ajouter d'autres fichiers dans le dossier de son jeu (table de finitions du X01, placement des cibles de Radar, textes). Les signatures de tous ces types sont celles du protocole `TurnBasedRules` (§4.7) : il n'y a rien d'autre à convenir entre lots, hormis les noms. Les quatorze jeux se compilent dans **un seul module**, et quatre lots y écrivent sans se voir : tout fichier ajouté et tout symbole déclaré au niveau fichier portent donc le nom du jeu en préfixe (`Killer/KillerZones.swift`, `KillerPlayerState` ; jamais `Zones.swift` ni `PlayerState`), ou sont imbriqués dans le type de la règle, ou sont `private`. La règle complète est en §13.4. Dans un lot, les jeux Dartsee (P0, P1) passent avant le jeu classique (P2).

### 5.3 Descripteurs

Le lot F0 écrit les quatorze descripteurs **définitifs** (ils alimentent l'accueil et l'écran de préparation dès le premier jour) ; les règles suivent dans les lots G1 à G4. Les lignes sont dans l'ordre du registre.

| `id` | `name` fr / en | `shortName` fr / en | `summary` fr / en | Joueurs | `playStyle` | `origin` | `priority` |
|---|---|---|---|---|---|---|---|
| `x01` | X01 / X01 | X01 / X01 | 301 · 501 · 701 / 301 · 501 · 701 | 1–8 | `score` | `dartsee` | 0 |
| `cricket` | Cricket / Cricket | Cricket / Cricket | Fermer 15 à 20 et le bull / Close 15 to 20 and the bull | 1–8 | `score` | `dartsee` | 0 |
| `killer` | Killer / Killer | Killer / Killer | 4 niveaux · 2 à 8 joueurs / 4 levels · 2 to 8 players | 2–8 | `board` | `dartsee` | 0 |
| `shanghai` | Shanghai / Shanghai | Shanghai / Shanghai | Un numéro par manche / One number per round | 1–8 | `board` | `dartsee` | 0 |
| `moonLanding` | Alunissage / Moon Landing | Alunissage / Moon Landing | De 200 à zéro / From 200 down to zero | 1–8 | `score` | `dartsee` | 0 |
| `fight` | Combat / Fight | Combat / Fight | 9 vies, blesser ou soigner / 9 lives, hurt or heal | 2–6 | `board` | `dartsee` | 0 |
| `conqueror` | Conquérant / Conqueror | Conquérant / Conqueror | Conquérir la cible / Conquer the board | 2–8 | `board` | `dartsee` | 0 |
| `beerTap` | Tireuse / Beer Tap | Tireuse / Beer Tap | Remplir des verres / Fill the glasses | 1–8 | `score` | `dartsee` | 1 |
| `football` | Football / Football | Football / Football | Deux camps, un ballon / Two sides, one ball | 2–8 | `board` | `dartsee` | 1 |
| `radar` | Radar / Radar | Radar / Radar | Cibles rondes à détruire / Round targets to destroy | 1–8 | `board` | `dartsee` | 1 |
| `golf` | Golf / Golf | Golf / Golf | Le moins de coups / Fewest strokes | 1–8 | `board` | `dartsee` | 1 |
| `aroundTheClock` | Tour de l'horloge / Around the Clock | Horloge / Clock | De 1 à 20 dans l'ordre / 1 to 20 in order | 1–8 | `board` | `classic` | 2 |
| `highScore` | Meilleur score / High Score | Meilleur score / High Score | Le plus de points / Most points | 1–8 | `score` | `classic` | 2 |
| `halveIt` | La Moitié / Halve-It | La Moitié / Halve-It | Raté : score divisé par 2 / Miss it: score halved | 1–8 | `board` | `classic` | 2 |

- `pitch` est la phrase « En une ligne » de la fiche du jeu dans `GAMES.md` (§n.1), dans les deux langues.
- `priority` est le palier de `GAMES.md` §1 : 0 pour les sept jeux Dartsee documentés, 1 pour les quatre du lot G4, 2 pour les trois jeux classiques.
- `dependsOnPosition: true` pour `radar` seulement ; `confirmsShortTurn: false` pour `golf` seulement (§4.4). Les douze autres descripteurs gardent les valeurs par défaut.
- Les quatre jeux du lot G4 sont d'origine `dartsee` : ils figurent sur la page des jeux de Dartsee, même si leurs règles de score sont de notre conception (`GAMES.md` §13 à §16).

**Options.** Clés, valeurs et défauts sont ceux de `GAMES.md` §n.2. Traduction dans le schéma :

| Jeu | Clé | `kind` | Valeurs (`OptionValue`) | Défaut | Avancée |
|---|---|---|---|---|---|
| `x01` | `startScore` | `choice` | `301`, `501`, `701` | `301` | non |
| | `inRule` | `choice` | `"straight"` (Entrée libre / Straight in), `"double"` (Entrée en double / Double in) | `"straight"` | non |
| | `outRule` | `choice` | `"straight"` (Sortie libre / Straight out), `"double"` (Sortie en double / Double out) | `"straight"` | non |
| | `maxRounds` | `optionalStepper(1...99)` | entier ou `.null` | `20` | oui |
| `cricket` | `scoring` | `choice` | `"cutThroat"`, `"standard"` | `"cutThroat"` | non |
| | `targets` | `choice` | `"normal"`, `"light"` | `"normal"` | non |
| | `maxRounds` | `optionalStepper(1...99)` | | `20` | oui |
| `killer` | `level` | `choice` | `"easy"` (`players: 2...6`), `"medium"`, `"hard"`, `"expert"` | `"easy"` | non |
| | `lives` | `stepper(1...9)` | | `3` | non |
| | `armingHits` | `stepper(1...5)` | | `3` | non |
| | `selfHitPenalty` | `toggle` | | `false` | oui |
| | `maxRounds` | `optionalStepper(1...99)` | | `15` | oui |
| `aroundTheClock` | `finishOnBull` | `toggle` | | `false` | non |
| | `multiplierJump` | `toggle` | | `false` | non |
| | `maxRounds` | `optionalStepper(1...99)` | | `.null` | oui |
| `shanghai` | `rounds` | `choice`, `allowsCustomValue` | `7`, `20` proposés ; le moteur accepte 1 à 20 | `7` | non |
| | `variant` | `choice` | `"traditional"`, `"lite"` | `"traditional"` | non |
| `highScore` | `rounds` | `stepper(1...20)` | | `8` | non |
| `halveIt` | `targets` | `choice`, `allowsCustomValue` | `.strings(["20", "16", "D7", "14", "T10", "BULL"])` (courte), `.strings(["15", "16", "anyDouble", "17", "18", "anyTreble", "19", "20", "BULL"])` (longue) ; le moteur accepte 1 à 12 cibles | la liste courte | non |
| | `startingScore` | `choice` | `0`, `40` | `0` | non |
| `moonLanding` | `distance` | `choice`, `allowsCustomValue` | `200`, `300`, `500` proposés ; le moteur accepte 100 à 999 | `200` | non |
| | `exactLanding` | `toggle` | | `false` | non |
| | `maxRounds` | `optionalStepper(1...99)` | | `15` | oui |
| `fight` | `lives` | `stepper(1...20)` | | `9` | non |
| | `maxRounds` | `optionalStepper(1...99)` | | `15` | oui |
| `conqueror` | `multipliersCount` | `toggle` | | `false` | non |
| | `maxRounds` | `optionalStepper(1...99)` | | `15` | oui |
| `beerTap` | `glassSize` | `choice` | `25` (Demi / Half), `50` (Pinte / Pint), `100` (Litre / Litre) ; toute autre valeur est refusée par le schéma | `50` | non |
| | `rounds` | `stepper(1...20)` | | `5` | non |
| `football` | `fieldLength` | `stepper(3...8)` | | `4` | non |
| | `goalsToWin` | `stepper(1...9)` | | `3` | non |
| | `maxRounds` | `optionalStepper(1...99)` | | `10` | oui |
| `radar` | `movingTargets` | `toggle` | | `false` | non |
| | `rounds` | `stepper(1...20)` | | `8` | non |
| `golf` | `holes` | `choice`, `allowsCustomValue` | `9`, `18` proposés ; le moteur accepte 1 à 18 | `9` | non |
| | `countedDart` | `choice` | `"last"` (La dernière fléchette / Last dart), `"best"` (La meilleure fléchette / Best dart) | `"last"` | non |

- Notation d'une cible de La Moitié dans l'option `targets` : `"20"` = `number(20)`, `"D7"` = `double(7)`, `"T10"` = `treble(10)`, `"anyDouble"`, `"anyTreble"`, `"BULL"`.
- Pour une option `allowsCustomValue`, c'est le moteur qui valide la valeur libre et lève `GameConfigurationError.invalidOptionValue(key:)`.
- Le libellé nul de `maxRounds` est « Sans limite » / "No limit".
- `beerTap`, `radar` et `golf` n'ont pas d'option `maxRounds` : leur limite de manches (`roundLimit`) est `rounds`, `rounds` et `holes`.
- Libellés des options du lot G4, fr / en : `glassSize` Verre / Glass ; `rounds` Manches / Rounds ; `fieldLength` Longueur du terrain / Field length ; `goalsToWin` Buts pour gagner / Goals to win ; `movingTargets` Cibles mobiles / Moving targets ; `holes` Trous / Holes ; `countedDart` Fléchette comptée / Counted dart.
- Libellés des options des autres jeux, fr / en. X01 : `startScore` Score de départ / Start score ; `inRule` Entrée / In ; `outRule` Sortie / Out. Cricket : `scoring` Score / Scoring (choix `cutThroat` Cut-throat, `standard` Standard, les mêmes dans les deux langues) ; `targets` Cibles / Targets (choix `normal` Normal, `light` Léger / Light). Tour de l'horloge : `finishOnBull` Finir sur le bull / Finish on the bull ; `multiplierJump` Doubles et triples avancent plus / Doubles and trebles jump. Shanghai : `rounds` Manches / Rounds ; `variant` Variante / Variant (choix `traditional` Traditionnel / Traditional, `lite` Lite). La Moitié : `targets` Cibles / Targets (choix Courte / Short pour la liste par défaut, Longue / Long pour l'autre) ; `startingScore` Score de départ / Starting score. Alunissage : `distance` Distance / Distance ; `exactLanding` Alunissage exact (Pro) / Exact landing (Pro). Combat : `lives` Vies / Lives. Conquérant : `multipliersCount` Doubles et triples comptent / Doubles and trebles count. `maxRounds` porte partout le libellé et le libellé nul du Killer (listing ci-dessous).
- Un choix numérique (301, 501, 701 ; 7, 20 ; 200, 300, 500 ; 0, 40 ; 9, 18) a pour libellé son nombre : `LocalizedText(verbatim: "301")`. Avec ces deux lignes, le listing du Killer et celui de Meilleur score, les libellés des quatorze descripteurs sont tous fixés : F0 n'en invente aucun.
- Les refus décidés par le schéma valent dès le squelette, avant que les règles existent : `beerTap { glassSize: 40 }`, `radar { rounds: 21 }`, `football` à un joueur. Le noyau valide le descripteur avant d'appeler la règle (§4.7).

Squelette type, écrit par F0 pour chaque jeu qui n'a pas encore ses règles. Celui du Killer sert de modèle : son descripteur est définitif et montre comment la table ci-dessus devient du code.

Fichier `DartKit/Sources/DartGames/Killer/KillerRules.swift` (squelette F0, remplacé par G2) :

```swift
import DartCore

/// GAMES.md §5. Skeleton written by lot F0: the descriptor is final, the rules are written by lot G2.
public struct KillerRules: TurnBasedRules {
    public static let descriptor = GameDescriptor(
        id: .killer,
        name: LocalizedText(verbatim: "Killer"),
        shortName: LocalizedText(verbatim: "Killer"),
        summary: LocalizedText(fr: "4 niveaux · 2 à 8 joueurs", en: "4 levels · 2 to 8 players"),
        pitch: LocalizedText(fr: "Touchez votre zone pour devenir Killer, puis visez celles des autres : le dernier en vie gagne.",
                             en: "Hit your own zone to become a Killer, then take the others out: last one alive wins."),
        players: 2...8,
        options: [
            OptionDescriptor(
                key: "level",
                label: LocalizedText(fr: "Niveau", en: "Level"),
                kind: .choice([
                    OptionChoice("easy", label: LocalizedText(fr: "Facile", en: "Easy"),
                                 detail: LocalizedText(fr: "3 cases adjacentes · 6 joueurs max", en: "3 adjacent numbers · 6 players max"),
                                 players: 2...6,
                                 unavailableNote: LocalizedText(fr: "6 joueurs maximum en Facile", en: "6 players maximum in Easy"),
                                 illustration: .sectors(count: 3, moving: false)),
                    OptionChoice("medium", label: LocalizedText(fr: "Intermédiaire", en: "Medium"),
                                 detail: LocalizedText(fr: "2 cases adjacentes", en: "2 adjacent numbers"),
                                 illustration: .sectors(count: 2, moving: false)),
                    OptionChoice("hard", label: LocalizedText(fr: "Difficile", en: "Hard"),
                                 detail: LocalizedText(fr: "1 seule case", en: "1 number only"),
                                 illustration: .sectors(count: 1, moving: false)),
                    OptionChoice("expert", label: LocalizedText(verbatim: "Expert"),
                                 detail: LocalizedText(fr: "1 case qui change à chaque tour", en: "1 number that changes every turn"),
                                 illustration: .sectors(count: 1, moving: true)),
                ]),
                defaultValue: "easy"),
            OptionDescriptor(key: "lives", label: LocalizedText(fr: "Vies", en: "Lives"),
                             kind: .stepper(1...9), defaultValue: 3),
            OptionDescriptor(key: "armingHits",
                             label: LocalizedText(fr: "Touches pour devenir Killer", en: "Hits to become a Killer"),
                             kind: .stepper(1...5), defaultValue: 3),
            OptionDescriptor(key: "selfHitPenalty",
                             label: LocalizedText(fr: "Pénalité sur sa propre zone", en: "Penalty on your own zone"),
                             help: LocalizedText(fr: "Un Killer qui touche sa zone perd une vie.", en: "A Killer who hits their own zone loses a life."),
                             kind: .toggle, defaultValue: false, isAdvanced: true),
            OptionDescriptor(key: "maxRounds", label: LocalizedText(fr: "Manches maximum", en: "Round limit"),
                             kind: .optionalStepper(1...99, nullLabel: LocalizedText(fr: "Sans limite", en: "No limit")),
                             defaultValue: 15, isAdvanced: true),
        ],
        playStyle: .board,
        origin: .dartsee,
        priority: 0)

    public init(configuration: GameConfiguration, random: inout SeededRandom) throws {
        // Not written yet: creating the game fails cleanly instead of crashing.
        throw GameConfigurationError.unknownGame(configuration.gameID)
    }

    public var roundLimit: Int? { nil }
    public func isEliminated(_ player: PlayerIndex) -> Bool { false }
    public mutating func turnStarted(_ context: TurnContext, random: inout SeededRandom, events: inout [GameEvent]) {}
    public mutating func dartThrown(_ hit: Hit, _ context: TurnContext, random: inout SeededRandom,
                                    events: inout [GameEvent]) -> DartVerdict { .turnContinues }
    public mutating func turnClosed(_ context: TurnContext, events: inout [GameEvent]) {}
    public func ranks() -> [Int] { [] }
    public func presentation(_ context: TurnContext) -> RulesPresentation {
        RulesPresentation(title: Self.descriptor.name, rows: [])
    }
}
```

Un jeu en squelette refuse de démarrer (`unknownGame`) au lieu de planter ; l'écran de préparation affiche alors « Bientôt disponible ». F0 écrit ce squelette pour treize jeux : tous sauf Meilleur score. Les tests qui portent « sur chaque jeu du registre » sautent les jeux en squelette (`GameRegistry.deliveredDefinitions`, §12.1) : un lot de jeux n'attend donc jamais les autres.

### 5.4 Exemple complet : Meilleur score

C'est la règle la plus simple (`GAMES.md` §8) et l'implémentation de référence du protocole. Le lot F0 l'a livrée sans ses finitions : `DartUI` a ainsi eu un vrai jeu jouable dès le premier jour, bien que ce jeu classique soit au dernier palier. Le lot G1 en est devenu propriétaire et l'a terminée en vague 1 : phrase et lignes des résultats (`outcome`, `resultLines`, lues en phase `finished` seulement), et plus de résumé de volée après une fin à la limite de manches, où la volée du noyau est vide (§4.7). Le listing ci-dessous est cette version livrée. Elle ne tire rien et ne lit pas la position : elle reçoit `random` dans `dartThrown` sans s'en servir.

Fichier `DartKit/Sources/DartGames/HighScore/HighScoreRules.swift` :

```swift
import DartCore

/// GAMES.md §8. The simplest game: the reference implementation of `TurnBasedRules` (ARCHITECTURE.md §5.4),
/// completed by lot G1 with the results of the game: sentence, lines per player, and no stale turn summary.
public struct HighScoreRules: TurnBasedRules {
    public static let descriptor = GameDescriptor(
        id: .highScore,
        name: LocalizedText(fr: "Meilleur score", en: "High Score"),
        shortName: LocalizedText(fr: "Meilleur score", en: "High Score"),
        summary: LocalizedText(fr: "Le plus de points", en: "Most points"),
        pitch: LocalizedText(fr: "Un nombre de manches fixe, tout compte : le plus gros total gagne.",
                             en: "A fixed number of rounds, everything counts: highest total wins."),
        players: 1...8,
        options: [OptionDescriptor(key: "rounds", label: LocalizedText(fr: "Manches", en: "Rounds"),
                                   kind: .stepper(1...20), defaultValue: 8)],
        playStyle: .score, origin: .classic, priority: 2)

    let rounds: Int
    var points: [Int]
    var dartsThrown: [Int]
    var lastTurn: [Int?]
    var turnTotal = 0

    public init(configuration: GameConfiguration, random: inout SeededRandom) throws {
        rounds = configuration.options.int("rounds") ?? 8
        let count = configuration.players.count
        points = Array(repeating: 0, count: count)
        dartsThrown = Array(repeating: 0, count: count)
        lastTurn = Array(repeating: nil, count: count)
    }

    public var roundLimit: Int? { rounds }
    public func isEliminated(_ player: PlayerIndex) -> Bool { false }

    public mutating func turnStarted(_ context: TurnContext, random: inout SeededRandom, events: inout [GameEvent]) {
        turnTotal = 0
    }

    public mutating func dartThrown(_ hit: Hit, _ context: TurnContext, random: inout SeededRandom,
                                    events: inout [GameEvent]) -> DartVerdict {
        let p = context.currentPlayer
        dartsThrown[p] += 1
        if hit.isMiss { events.append(.noEffect(player: p)) }
        points[p] += hit.points
        turnTotal += hit.points
        return .turnContinues
    }

    public mutating func turnClosed(_ context: TurnContext, events: inout [GameEvent]) {
        let p = context.currentPlayer
        lastTurn[p] = turnTotal
        events.append(.turnScored(player: p, points: turnTotal))
        if turnTotal == 180 { events.append(.oneEighty(player: p)) }
        else if turnTotal >= 100 { events.append(.highTurn(player: p, points: turnTotal)) }
    }

    public func ranks() -> [Int] { Ranking.ranks(keys: points.map { [-$0] }) }

    // MARK: Presentation (GAMES.md §8.7, ARCHITECTURE.md §5.6)

    public func presentation(_ context: TurnContext) -> RulesPresentation {
        // After a game ended at the round limit the kernel's volley is empty while `turnTotal` is still that of
        // the last turn (ARCHITECTURE.md §4.7): there is no current turn left to sum up.
        let turnIsOver = context.phase == .finished && context.darts.isEmpty
        return RulesPresentation(
            title: Self.descriptor.name,
            rows: points.indices.map { i in
                PlayerRow(player: i, primary: ScoreValue(points[i]),
                          detail: lastTurn[i].map { LocalizedText(fr: "Dernière volée : \($0)", en: "Last turn: \($0)") },
                          // Lines of the results screen: only read once the game is finished, like `outcome`.
                          resultLines: context.phase == .finished ? resultLines(i) : [],
                          facts: ["points": .int(points[i]), "dartsThrown": .int(dartsThrown[i])])
            },
            dartCaptions: context.darts.map { DartCaption(LocalizedText(verbatim: "\($0.points)")) },
            turnSummary: turnIsOver ? nil : LocalizedText(fr: "Volée : \(turnTotal)", en: "Turn: \(turnTotal)"),
            outcome: context.phase == .finished ? outcome : nil)
    }

    /// Average per turn, `3 × points / dartsThrown` (0 without a dart), then the darts thrown.
    private func resultLines(_ i: PlayerIndex) -> [LocalizedText] {
        let darts = dartsThrown[i]
        // In tenths, rounded to the nearest: integer arithmetic, the same text on every machine.
        let tenths = darts == 0 ? 0 : (60 * points[i] + darts) / (2 * darts)
        return [
            LocalizedText(fr: "Moyenne par volée : \(tenths / 10),\(tenths % 10)",
                          en: "Average per turn: \(tenths / 10).\(tenths % 10)"),
            .counted(darts, fr: (one: "fléchette", other: "fléchettes"), en: (one: "dart", other: "darts")),
        ]
    }

    /// Results sentence: the game only ends at the round limit, and the highest total wins.
    private var outcome: LocalizedText {
        let best = points.max() ?? 0
        let total = LocalizedText.counted(best, fr: (one: "point", other: "points"), en: (one: "point", other: "points"))
        if points.filter({ $0 == best }).count > 1 {
            return LocalizedText(fr: "Égalité à \(total.fr).", en: "Tied on \(total.en).")
        }
        return LocalizedText(fr: "Plus gros total : \(total.fr).", en: "Highest total: \(total.en).")
    }
}
```

### 5.5 Faits exposés

Noms et types des faits (`facts`), tels que les tests les lisent. « Par joueur » va dans `PlayerRow.facts`, « partie » dans `RulesPresentation.facts`. Le bull comme cible s'écrit `25`.

| Jeu | Par joueur | Partie |
|---|---|---|
| `x01` | `remaining` (int), `isOpen` (bool), `dartsThrown` (int), `busts` (int) | — |
| `cricket` | `points` (int), `marks` (map cible → 0…3), `closedCount` (int) | `targets` (ints) |
| `killer` | `zone` (ints, sens horaire), `lives`, `armingProgress`, `kills` (int), `isKiller`, `eliminated` (bool) | — |
| `aroundTheClock` | `progress` (int), `target` (int ; `25` = bull, `0` = plus de cible), `dartsThrown` | — |
| `shanghai` | `points` (int) | — |
| `highScore` | `points`, `dartsThrown` (int) | — |
| `halveIt` | `points` (int), `hitThisTurn` (bool) | `target` (text, notation de §5.3) |
| `moonLanding` | `remaining`, `dartsThrown`, `busts` (int) | — |
| `fight` | `lives`, `healNumber`, `kills` (int), `weakNumbers` (ints), `eliminated` (bool) | — |
| `conqueror` | `sectors` (map secteur → vies), `totalLives`, `sectorCount`, `homeSector` (int), `eliminated` (bool) | `king` (int : index du joueur, `-1` = personne) |
| `beerTap` | `poured`, `glasses`, `level`, `bonusGlasses`, `dartsThrown` (int) | — |
| `football` | `side` (int : `0` = camp A, `1` = camp B), `goalsScored` (int) | `ball` (int, signé), `sideGoals` (ints : `[A, B]`), `goalDistance` (int), `step` (ints : `[A, B]`) |
| `radar` | `points`, `destroyed`, `dartsThrown` (int) | `blobs` (table : cinq lignes `[x, y, radius, hitPoints]`, dans l'ordre des emplacements, en millimètres entiers) |
| `golf` | `strokes`, `holesPlayed` (int), `holeScores` (ints), `toPar` (int, signé) | `provisional` (int : score provisoire du trou en cours pour le joueur courant ; `5` tant qu'aucune fléchette n'est lancée, et après une fin à la limite de manches, dont la volée est vide) |

- Rappel de §4.7 : toute valeur qu'une règle relit plus tard DOIT figurer dans les faits.
- Les valeurs dérivées de `GAMES.md` sont exposées telles qu'il les définit : `glasses = poured / glassSize`, `level = poured % glassSize`, `toPar = strokes − 3 × holesPlayed`.
- `provisional` est le seul nom de cette table que `GAMES.md` ne fixe pas (il parle du « score provisoire », §16.4) ; il est fixé ici.
- Les vecteurs de `GAMES.md` écrivent `camps = A, B, A` et `step = 1 / 2` : dans un test, ce sont les faits `side` (`0, 1, 0`) et `step` (`[1, 2]`). Un champ de partie se lit avec `match.gameFact("ball")` (§12.1).

### 5.6 Présentation attendue

Présentation minimale de chaque jeu (`GAMES.md` §n.7). Les libellés sont donnés en français ; chaque `LocalizedText` porte aussi l'anglais.

| Jeu | `title` / `variant` | `primary` (unité) | `detail` | `badges` | `meter` | Autres |
|---|---|---|---|---|---|---|
| `x01` | « 501 » / « Double out » | `remaining` | « Dernière volée : 45 » ou « BUST » | « À ouvrir » tant que `isOpen == false` | — | `turnSummary` « Volée : 117 » ; `turnHint` « Pour finir : D12 » |
| `cricket` | « Cricket » / « Cut-throat » | `points` | « 3 cibles fermées » | — | — | `grid` : une colonne par cible |
| `killer` | « Killer » / « Facile » | `lives` (« vies ») | zone « 17 · 3 · 19 » | « Killer » (`accent`), « Éliminé » (`negative`) | pastilles `armingProgress` / `armingHits` tant que le joueur n'est pas Killer | légende de fléchette « Tom −1 vie » |
| `aroundTheClock` | « Tour de l'horloge » | cible courante (« cible ») | « 12 fléchettes » (`dartsThrown`) | — | barre `progress` / `goal` | — |
| `shanghai` | « Shanghai » / « Lite » | `points` | « Volée : 12 » | — | — | `objective` « Numéro 4 » ; étiquettes `+r`, `+2r`, `+3r` sur les surbrillances `single(r)`, `double(r)`, `treble(r)`, et `+r` sur les secteurs voisins en `lite` (`GAMES.md` §7.7) |
| `highScore` | « Meilleur score » | `points` | « Dernière volée : 45 » | — | — | `turnSummary` |
| `halveIt` | « La Moitié » | `points` | — | « Cible touchée » (`positive`) | — | `objective` « Cible : D7 » ; `turnHint` « Ensuite : 16 · D7 · 14 · T10 · Bull », les cibles à venir (`nil` à la dernière manche) |
| `moonLanding` | « Alunissage » / « Pro » | `remaining` | « Dernière volée : 45 » ou « BUST » | — | — | `turnSummary` |
| `fight` | « Combat » | `lives` (« vies ») | « Soin 2 · Faibles 15, 11 » | « K.-O. » (`negative`) | barre `lives` / maximum | marqueur `heal` sur le numéro de soin |
| `conqueror` | « Conquérant » | `totalLives` (« vies ») | « 4 secteurs · maison 6 » | « Roi » (`accent`), « Éliminé » | — | `strength` 1…3 par secteur, marqueur `home` sur la maison |
| `beerTap` | « Tireuse » / « Pinte » | `glasses` (« verres ») | « Dernière volée : 60 », suivi de « · 2 offerts » quand `bonusGlasses > 0` | — | barre `level` / `glassSize` (le verre entamé) | `turnSummary` « Volée : 60 » ; aucune surbrillance |
| `football` | « Football » | buts du camp (« buts ») | « 1 but marqué » | « A » ou « B » (le camp) | barre d'avancée du ballon vers le but attaqué : `goalDistance + ball` (camp A) ou `goalDistance − ball` (camp B), sur `2 × goalDistance` | `objective` « A 2 – 1 B » ; surbrillances `target` (moitié attaquée et `bull`) et `avoid` (autre moitié) ; en fin de partie, `winnerTitle` « Le camp A gagne », « Le camp B gagne » ou « Match nul » |
| `radar` | « Radar » / « Cibles mobiles » si l'option est active | `points` | « 2 détruites · dernière volée : 60 » | — | — | cinq surbrillances `disc` de rôle `target`, étiquette « +10 », « +20 » ou « +50 », `strength` = `hitPoints` ; `turnSummary` « Volée : 60 » |
| `golf` | « Golf » / « Meilleure fléchette » si `countedDart == best` | `strokes` (« coups ») | scores des trous joués : « 3 · 5 · 2 » | écart au par : « −2 » (`positive`), « Par », « +3 » (`negative`) | — | `objective` « Trou 4 / 9 · par 3 » ; `turnSummary` « Ce trou : 3 » ; `double(r)` et `treble(r)` en `target` avec les étiquettes « 1 » et « 2 », `single(r)` en `secondary` avec « 3 » |

Règles d'écriture communes :

- **Surbrillances** : exactement celles de `GAMES.md` §n.7, avec `owner` renseigné chaque fois que la zone appartient à un joueur.
- **Gabarit** : `beerTap` se lit sur un grand nombre (`playStyle: .score`) ; `football`, `radar` et `golf` se lisent sur la cible (`.board`). Aucun de ces quatre jeux n'a d'écran propre (`DESIGN.md` §4).
- **Légende d'une fléchette** (`dartCaptions`) : l'effet en trois mots au plus. Points pour les jeux à points (« 60 »), effet pour les autres (« Tom −1 vie », « Armement 2/3 », « Sans effet »). Ton `positive` pour un gain, `negative` pour une perte, `neutral` sinon.
- **Résultats** : `outcome` est une phrase sur le vainqueur (« Dernier joueur en vie, avec 2 vies restantes. ») ; `resultLines` donne au plus deux lignes par joueur (« 2 éliminations », « Éliminé manche 9 »). Un moteur ne connaît pas le genre d'un joueur : il écrit au masculin générique, comme le badge « Éliminé », là où la maquette `Results` accorde au féminin. `winnerTitle` reste `nil`, sauf dans un jeu dont le vainqueur n'est pas un joueur : le Football y met le camp vainqueur ou le match nul (§4.6).
- **Unités** : l'unité de `primary` s'accorde au nombre, comme `LocalizedText.counted` (« 1 verre », « 2 verres » ; en français le singulier vaut pour 0 et 1, en anglais pour 1 seulement). La table ci-dessus les donne au pluriel.
- **Fin à la limite de manches** : la volée du noyau est vide (§4.7) alors que la règle garde l'état de son dernier tour. `turnSummary` vaut alors `nil`, et les légendes se coupent à `min(context.darts.count, …)` : une vue ne montre jamais le résumé d'un tour qui n'est plus en cours.
- **Conseil de finition du X01** (`turnHint`) : hors règles (`GAMES.md` §3.7) ; une table simple de finitions en une à trois fléchettes suffit.

### 5.7 Tests

Voir §12.1. Chaque vecteur de `GAMES.md` devient un test Swift Testing écrit avec `DartTestSupport`. Les tests d'un jeu sont les méthodes d'une `@Suite struct` qui porte le nom de son fichier (`KillerTests` dans `KillerTests.swift`), et chaque méthode porte l'identifiant de son vecteur. **Aucune fonction `@Test` n'est déclarée au niveau fichier** : les quatorze fichiers partagent un module, et deux `roundTrip()` libres ne compileraient pas ensemble (§13.4).

```swift
import Testing
import DartCore
import DartGames
import DartTestSupport

// KillerTests.swift (lot G2)
@Suite struct KillerTests {
    @Test func kil1_hardDuel() throws {
        var match = try GameRegistry.standard.match(.killer, ["level": "hard"], players: 2, seed: 1)
        #expect(match.fact(0, "zone") == [11] && match.fact(1, "zone") == [6])
        let outcomes = match.play("S11, D11, T11")
        #expect(match.fact(0, "armingProgress") == 3 && match.phase == .turnComplete)
        #expect(outcomes[2].events == [.dartRegistered(player: 0, hit: .treble(11)), .armingHit(player: 0, progress: 3),
                                       .becameKiller(player: 0), .turnCompleted(player: 0)])
        match.play("| MISS ×3 | S6, T6, D6")
        #expect(match.phase == .finished && match.snapshot.finishReason == .lastPlayerStanding)
        #expect(match.snapshot.ranks == [1, 2])
    }
}

// RadarTests.swift (lot G4)
@Suite struct RadarTests {
    // RAD-3: a dart written `S6@(124.0, 0.0)` carries a recorded position; without "@" it has none.
    @Test func rad3_sameHitDifferentEffects() throws {
        var match = try GameRegistry.standard.match(.radar, players: 1, seed: 1)
        let outcomes = match.play("S6@(123.9, 0.0), S6@(124.0, 0.0), S6")
        #expect(outcomes[0].events.contains(.noEffect(player: 0)))
        #expect(outcomes[1].events.contains(.blobDestroyed(player: 0, blob: 4, points: 150)))
        #expect(match.fact(0, "points") == 150 && match.gameFact("blobs") == .table([
            [-80, 95, 40, 3], [70, -65, 40, 3], [110, 65, 28, 2], [25, 15, 28, 2], [60, 105, 16, 1]]))
    }
}
```

Les règles des quatre jeux du lot G4 ont été écrites à l'essai contre le contrat de §4, dans le paquet de vérification de ce document, et passent les vecteurs BEE-1 à 6, FOO-1 à 7, RAD-1 à 7 et GOL-1 à 7 de `GAMES.md`. Ce sont des règles d'essai, pas une livraison : le lot G4 écrit les siennes. Elles prouvent seulement que le contrat porte tout ce dont ces jeux ont besoin.

---

## 6. DartVision

### 6.1 Rôle et dépendances

`DartVision` transforme des images en propositions de fléchettes. Sa conception, ses algorithmes, ses paramètres et ses tests sont dans `VISION.md`, qui fait foi. Il dépend de `DartCore` seulement, pour trois symboles (§4.9). Il n'importe ni `DartGames`, ni `DartAudio`, ni `DartUI`.

### 6.2 API publique

**L'API publique de `DartVision` est le listing de `VISION.md` §9.2**, découpé en fichiers selon `VISION.md` §9.3. Elle n'est pas recopiée ici. Les types que `DartUI` utilise sont :

| Besoin de `DartUI` | Symboles de `VISION.md` §9.2 |
|---|---|
| Calibrage | `CalibrationHandles`, `BoardCalibrator` (`preview`, `calibrate`, `assess`, `recover`), `BoardCalibration`, `CalibrationQuality`, `CalibrationIssue`, `BoardWireframe`, `BoardLocating`, `ColourBoardLocator`, `BoardRectifier` |
| Scan | `ScanSession`, `ScanEvent`, `ScanCommand`, `ScanState`, `ScanAdvisory`, `DartObservation`, `ConfidenceTier`, `ConfidenceThresholds`, `VisionConfiguration` |
| Correction | `ScanSession.evidenceCrop(for:)`, `correct(_:tip:)`, `recordFeedback(_:wasCorrected:)`, `DartObservation.correctionChoices()` |
| Photo | `PhotoScorer`, `RGBImage`, `ImagePoint` |
| Sources d'images | `CameraFrameSource`, `SyntheticFrameSource`, `FrameSourceInfo`, `CameraConfiguration` |
| Vérification à une fléchette | `ScanSession.runLightingCheck(confirmedTip:)`, `LightingCheckResult` |

`DartUI` n'accède à `ScanSession` qu'à travers une façade (`ScanServicing`, §8.4.8), pour pouvoir être testé sans caméra. Le cycle de vie des commandes (`arm`, `setTrigger`, `beginVisit`, `pause`, `resume`, `confirmBoardEmpty`, `captureNow`) est celui de `VISION.md` §6.3 et §6.5 ; la façon dont le jeu s'en sert est en §8.7.

### 6.3 Observations fabriquées à la main

Ce document n'ajoute plus rien au listing de `VISION.md` §9.2. L'initialiseur public de `DartObservation`, dont les tests de `DartUI`, le service factice et le mode démonstration du Simulateur ont besoin, y est maintenant déclaré **dans le corps** de la structure :

```swift
public init(id: UUID, visit: Int, indexInVisit: Int, timestamp: TimeInterval, tip: BoardPoint,
            uncertainty: TipUncertainty, candidates: [HitCandidate], nearbyHits: [Hit], confidence: Double,
            tier: ConfidenceTier, flags: DartFlags, source: ObservationSource)
```

- Il NE DOIT PAS être redéclaré dans une extension : sa liste de paramètres est celle des propriétés stockées, et le compilateur refuse la collision avec l'initialiseur synthétisé (« invalid redeclaration of synthesized memberwise init », constaté avec Swift 6.4.2).
- C'est un membre de simple donnée : F0 écrit son vrai corps (`self.id = id` … `self.source = source`), et aucun lot ne le change (§6.4).

Conséquence pour V3, inchangée : `best`, `correctionChoices(minimum:)` et `tier(collapsingBy:thresholds:)` DOIVENT se calculer à partir des seuls champs stockés de l'observation (`candidates`, `nearbyHits`, `confidence`, `flags`), sans état caché, pour qu'une observation fabriquée à la main se comporte comme une vraie. La formule de la confiance regroupée est fixée par `VISION.md` §7.4 :

```
collapsed = min(confidence · ΣP(candidats de même clé que candidates[0]) / candidates[0].probability, cap(flags))
cap(flags) = 0,80 avec calibrationPoor ou crossViewpoint ; 0,84 avec warmUp ; 1 sinon
```

La clé est celle que `DartUI` fournit : `match.effectKey(for: hit, position: observation.tip)` (§4.8).

### 6.4 Squelette

Le lot F0 crée le squelette de `DartVision` à partir du listing de `VISION.md` §9.2. Quatre règles, qui remplacent l'ancienne règle « tout membre plante » et ne laissent aucun choix de forme à F0 :

1. **Un fichier par ligne de la table de `VISION.md` §9.3** (« Répartition des types publics » : 86 types publics dans 37 fichiers). Chaque type public va dans le fichier que la table lui donne, avec ses types imbriqués et tous ses membres. La table donne aussi le lot propriétaire de chaque fichier ; elle est cohérente avec §13.2. Les fichiers de code interne cités sous la table ne sont pas créés par F0 : leur lot les crée.
2. **Les membres de simple donnée reçoivent leur vrai corps.** La liste normative est `VISION.md` §9.4. F0 écrit donc pour de bon :

   | Catégorie (`VISION.md` §9.4) | Nombre | Corps |
   |---|---|---|
   | initialiseur qui range ses paramètres | 23 | `self.x = x` pour chaque paramètre |
   | `init()` d'une structure dont toutes les propriétés ont une valeur par défaut : `CalibrationParameters`, `ColourBoardLocator.Parameters`, `DetectionParameters`, `ConfidenceThresholds`, `ConfidenceParameters`, `ScanParameters`, `VisionConfiguration`, `CameraConfiguration`, `SyntheticScene` | 9 | vide |
   | constantes : `BoardCanvas.pixelsPerMillimetre`, `halfExtent`, `side` ; `RingRadii.nominal` ; `DetectionParameters.default` ; `ConfidenceThresholds.standard` ; les dix-neuf options de `DartFlags` | | la valeur du listing ; pour `DartFlags`, `DartFlags(rawValue: 1 << i)` dans l'ordre du listing |
   | tables constantes : `CalibrationHandle.boardPoint` (les points `(170 sin a, 170 cos a)` pour `a` = 9°, 99°, 189°, 279°), `CalibrationHandle.label`, `CalibrationIssue.isBlocking` | | la valeur du commentaire du listing |
   | `<` de `CalibrationQuality.Grade` et de `ConfidenceTier` | 2 | `lhs.rawValue < rhs.rawValue` |

3. **Tout le reste plante proprement**, sous quatre formes exactes :

   | Membre du listing | Corps écrit par F0 |
   |---|---|
   | fonction ou initialiseur algorithmique | `{ fatalError("unimplemented") }` |
   | propriété calculée en lecture seule (`{ get }`) | `{ get { fatalError("unimplemented") } }` |
   | les quatre membres `{ get set }` : `RGBImage.subscript`, `GrayImage.subscript`, `CalibrationHandles.subscript`, `ScanEngine.configuration` | `{ get { fatalError("unimplemented") } set { fatalError("unimplemented") } }` |
   | `Homography.identity` et les trois constantes de `SyntheticDartStyle` (`steelTungsten`, `brass`, `allBlack`) | `= { fatalError("unimplemented") }()` : elles restent des `static let`, ne plantent qu'au premier accès, et le lot V1 écrit leur valeur |

   Un `static let` ne peut pas recevoir de corps `{ get { … } }` : c'est pourquoi ces quatre constantes ont leur propre forme, et que leur signature ne devient pas `static var`. Les lots V1 à V5 remplacent ensuite ces corps, fichier par fichier.
4. **Mêmes imports partout.** Chaque fichier du squelette commence par `import Foundation`, `import simd`, `import CoreGraphics`, `import CoreVideo`, `import DartCore`. Seul `Capture/CameraFrameSource.swift` ajoute `import AVFoundation`, et tout son contenu, imports compris, est sous `#if canImport(AVFoundation)`.

Ce que cette règle garantit aux lots qui démarrent sur le squelette :

- `VisionConfiguration()`, `ScanParameters()`, `ConfidenceThresholds.standard` et `DartObservation(…)` fonctionnent dès F0. `FakeScanService` (§8.4.8), les sources factices des tests de `DartUI` et l'argument par défaut `LiveScanService(configuration: VisionConfiguration = VisionConfiguration())` sont donc sûrs avant toute livraison de la vision.
- Le lot V4 (réducteur, vague 1) fabrique ses `GateSample`, `EpisodeSummary` et `DartObservation` sans attendre personne, et tous ses types sont dans son propre fichier `Scan/ScanEvents.swift`.
- **Aucun lot ne déclare d'`init` dans le corps** de `BoardCalibration`, `CalibrationQuality`, `BoardWireframe`, `CalibrationHealth`, `BoardLocation`, `DetectionDebug`, `LightingCheckResult`, `ScanDebugSnapshot` ni `RecordedSession.Scene` : cela supprimerait leur initialiseur membre à membre synthétisé, interne au module, dont les autres lots se servent. Un `init` déclaré en extension reste permis.
- **Un calibrage existe sans le calibreur.** `SyntheticCamera.calibration(grade:)` (lot V1, `VISION.md` §10.1) construit un `BoardCalibration` exact par ces initialiseurs synthétisés. Tous les tests et tous les factices qui ont besoin d'un calibrage le prennent là, sauf les tests du calibreur lui-même (groupes C et L). Les lots V2 et V3 ne dépendent ainsi que de V1, et les tests de `DartUI` n'appellent jamais `BoardCalibrator` pour obtenir une valeur.
- **Le lot V1 n'appelle aucun corps du lot V2.** Les poignées de ce calibrage exact (`SyntheticCamera.exactHandles()`) se construisent par `CalibrationHandles(points:)`, membre de simple donnée, à partir de `CalibrationHandle.boardPoint` et de `project(_:)` ; jamais par `CalibrationHandles(projecting:)`, que le lot V2 écrit en vague 2 et qui plante dans le squelette (`VISION.md` §9.3, §10.1). Les tests M10, M12 et R1 tournent donc dès la vague 1.
- **Les valeurs se comparent par `==`.** `ScanCommand`, `ScanEvent`, `ScanEffect`, `ScanInput`, `SettleOutcome` et `DartObservation` sont `Hashable` dans le listing, comme `ScanState` et `BoardCalibration` : un test écrit `service.commands == [.setTrigger(.automatic), .arm(boardConfirmedEmpty: true)]`. Aucun lot n'ajoute de conformité à un type du listing (§13.4).

Le squelette ainsi construit, sous ces formes exactes, a été vérifié : il compile sans avertissement contre le `DartCore` de ce document pour macOS et pour le Simulateur iOS, et les membres de simple donnée répondent sans planter.

### 6.5 Précisions de plateforme pour la capture

`VISION.md` §2.4 fixe la configuration de capture. Trois précisions issues de l'étude de la plateforme (SDK iOS 27.2) s'y ajoutent ; elles ne changent pas l'API.

1. **Pas de verrouillage d'orientation.** SwiftUI n'offre aucun moyen fiable de verrouiller l'orientation de l'interface, et iOS 27 ignore les orientations déclarées dans un environnement redimensionnable. La règle est donc :
   - l'angle de `AVCaptureVideoDataOutput` est fixé **une fois** avant `startRunning()`, par `AVCaptureDevice.RotationCoordinator.videoRotationAngleForHorizonLevelCapture` (jamais par l'orientation de l'interface), et il devient `FrameSourceInfo.rotationDegrees` ;
   - la couche d'aperçu suit `videoRotationAngleForHorizonLevelPreview` ;
   - si l'angle de capture change pendant un scan, l'appareil a été déplacé : `LiveScanService` (lot U3), qui observe son propre `RotationCoordinator` créé à partir de l'entrée vidéo de `captureSession`, met le scan en pause par `ScanCommand.pause(.user)` et l'interface demande un recalibrage (un calibrage ne vaut que pour son `rotationDegrees`). La raison `.user` est voulue : `resume` ne lève pas cette pause (`VISION.md` §6.3, ligne P2c), si bien qu'un retour au premier plan ne relance pas la vision sur un calibrage qui ne vaut plus.
   - *Réalisation (lot U3) :* `ScanServicing` n'a aucun canal pour dire « l'appareil a bougé ». `LiveScanService` envoie `pause(.user)` puis remet lui-même un `ScanEvent.calibrationLost` à ses abonnés : la source de la partie passe à `.needsCalibration`, `CameraModel` aussi, et la partie continue au doigt. Le joueur recalibre hors de la partie ; à la reprise, le `arm` de `gameStarted` relance la vision. La couche d'aperçu, elle, reste à l'angle `rotationDegrees` des images au lieu de suivre `videoRotationAngleForHorizonLevelPreview` : les tracés en pixels image (fil de fer, pointes) restent ainsi alignés, et un changement d'angle impose de toute façon un recalibrage.
2. **iPad en multitâche.** Avant `startRunning()`, `CameraFrameSource` écrit `if session.isMultitaskingCameraAccessSupported { session.isMultitaskingCameraAccessEnabled = true }`. La caméra n'est normalement disponible qu'en plein écran. `LiveScanService` (lot U3) observe lui-même `AVCaptureSession.wasInterruptedNotification`, `interruptionEndedNotification` et `runtimeErrorNotification` sur `CameraFrameSource.captureSession`, qui est public : aucune API n'est à ajouter à `DartVision`. Sur une interruption il envoie `ScanCommand.pause(.background)` et publie la cause (`CameraIssue`, §8.4.8) ; à la fin de l'interruption il envoie `.resume`. Il les envoie sans connaître l'état de la partie : c'est la machine qui ignore ce `.resume` quand une partie s'est terminée entre-temps (`VISION.md` §6.3, lignes P1b et P2c). La cause est lue par `CaptureInterruptionObserver` (§8.8) : `AVCaptureSession.InterruptionReason` n'existe pas sur macOS, et ce fichier est le seul à le nommer, derrière `#if os(iOS)`. Pour la cause `videoDeviceNotAvailableWithMultipleForegroundApps`, l'interface affiche « Passez l'application en plein écran » et la saisie manuelle continue.
3. **Fil d'exécution.** `startRunning()` est bloquant : `CameraFrameSource.start` l'appelle sur la file passée en paramètre, jamais sur le fil principal. Les changements de configuration sont encadrés par `beginConfiguration()` / `commitConfiguration()`.

Info.plist : seule la clé `NSCameraUsageDescription` est nécessaire (§9.3). Pas de microphone.

---

## 7. DartAudio

### 7.1 Rôle et dépendances

`DartAudio` fait entendre et sentir la partie : effets sonores **synthétisés** (aucun fichier audio), annonce vocale des scores en français ou en anglais, vibrations sur iPhone, gestion de la session audio sur iPhone et iPad, coupure du son et volume. Il dépend de `DartCore` seulement. Il compile sur macOS : `AVAudioSession`, les générateurs de vibration et le réglage `usesApplicationAudioSession` de la voix, qui n'existent pas sur macOS, sont derrière `#if os(iOS)` dans deux fichiers et deux seulement (§7.4).

Deux règles de conception :

- **Une seule table.** La correspondance entre un événement et ce qu'on entend est dans `CueMapping`, nulle part ailleurs. `DartUI` ne choisit jamais un son lui-même : il passe des `GameEvent` ou des `InterfaceCue`.
- **Le son ne bloque jamais le jeu.** Aucune méthode ne lève d'erreur ni n'attend ; un son impossible à jouer est ignoré. La logique de jeu ne dépend d'aucun retour du service (latence Bluetooth de 100 à 300 ms).

### 7.2 API publique

Fichier `DartKit/Sources/DartAudio/DartAudioAPI.swift` (squelette F0 ; le lot A1 répartit ensuite ces déclarations dans les fichiers de §7.4 sans changer une signature) :

```swift
// DartAudio — public API. Depends on DartCore only (GameEvent, Hit, Player, GameID, LocalizedText, AppLanguage).
import Foundation
import DartCore

// MARK: - 1. Vocabulary

/// Every synthesised sound of the application. No audio file ships with the app.
public enum SoundEffect: String, CaseIterable, Codable, Sendable {
    /// A dart that scores or changes something.
    case dartImpact
    /// MISS, or a dart without any effect in the game.
    case dartDull
    /// Points gained, a glass filled.
    case scoreUp
    /// One Cricket mark, one arming hit, the football moving.
    case tick
    /// A Cricket target closed.
    case lock
    /// A player becomes Killer or King; a free glass; a Radar target destroyed.
    case powerUp
    /// A life lost, a sector damaged, a Radar target hit.
    case damage
    /// A heal, a sector strengthened.
    case heal
    /// A sector claimed or conquered.
    case claim
    /// A player is out.
    case eliminated
    /// Bust buzzer.
    case bust
    /// Halve-It division, own goal: falling tone.
    case halved
    /// Turn of 100 to 179.
    case highTurn
    /// 180, Shanghai, a goal, a hole in one.
    case fanfare
    /// Winning dart or end of game.
    case victory
    /// Next player.
    case turnChange
    /// Killer expert: the zone moved. Radar: the targets moved.
    case zoneMove
    /// A detected dart waits for the player's answer.
    case needsReview
    /// A dart was ignored (turn already complete) or an action is impossible.
    case rejected
    /// Photo or scan capture.
    case shutter
    /// Calibration validated, correction applied.
    case confirm
    /// Calibration lost, camera unavailable.
    case alert
}

public enum HapticPattern: String, CaseIterable, Codable, Sendable {
    case light, medium, heavy, success, warning, failure
}

/// One sentence for the score caller, in both languages (the caller's language may differ from the UI's).
public struct Announcement: Hashable, Sendable {
    public enum Priority: Int, Comparable, Sendable {
        /// Per-dart call ("Triple 20"): replaced by any newer sentence, dropped while a `normal` or `high` one is spoken or queued.
        case low
        /// Turn total, next player: queued after what is being said.
        case normal
        /// 180, bust, victory: interrupts everything.
        case high

        public static func < (lhs: Priority, rhs: Priority) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    public var text: LocalizedText
    public var priority: Priority

    public init(_ text: LocalizedText, priority: Priority = .normal) {
        self.text = text
        self.priority = priority
    }
}

/// One thing to play: a sound, a sentence, a haptic, or any combination, `delay` seconds after the batch starts.
public struct AudioCue: Hashable, Sendable {
    public var effect: SoundEffect?
    public var announcement: Announcement?
    public var haptic: HapticPattern?
    public var delay: TimeInterval

    public init(effect: SoundEffect? = nil, announcement: Announcement? = nil, haptic: HapticPattern? = nil,
                delay: TimeInterval = 0) {
        self.effect = effect
        self.announcement = announcement
        self.haptic = haptic
        self.delay = delay
    }
}

/// The sound settings of DESIGN.md §4 ("Réglages"). Persisted by DartUI.
public struct AudioSettings: Hashable, Codable, Sendable {
    /// Master mute: nothing is played, spoken or vibrated.
    public var isMuted: Bool = false
    public var effectsEnabled: Bool = true
    /// Spoken score caller.
    public var callerEnabled: Bool = true
    public var callerLanguage: AppLanguage = .fr
    /// 0...1, applied to effects and voice.
    public var volume: Double = 0.8
    /// true: `.playback` (audible with the Silent switch on). false: `.ambient`.
    public var playsInSilentMode: Bool = true
    /// Lowers other apps' audio while a score is spoken (speech uses its own, system-managed session).
    public var ducksMusicWhileSpeaking: Bool = true
    /// iPhone only; ignored where there is no Taptic Engine.
    public var hapticsEnabled: Bool = true

    public init() {}
}

// MARK: - 2. Mapping (the ONLY place where events become sounds)

/// What the mapping needs to know about the game, taken from the snapshot AFTER the input.
public struct CueContext: Sendable {
    /// For logs only. The mapping NEVER branches on it: what a game has of its own arrives as data (`winnerTitle`).
    public var gameID: GameID
    public var players: [Player]
    /// `snapshot.winners` once the game is finished, empty before.
    public var winners: [PlayerIndex]
    /// `snapshot.winnerTitle`: the headline said at `gameFinished` in place of the winners' names
    /// ("Le camp A gagne", "Match nul"). Nil: the winners are announced by `CallerPhrases.winners`.
    public var winnerTitle: LocalizedText?

    public init(gameID: GameID, players: [Player], winners: [PlayerIndex] = [], winnerTitle: LocalizedText? = nil) {
        self.gameID = gameID
        self.players = players
        self.winners = winners
        self.winnerTitle = winnerTitle
    }
}

/// Things worth a sound that are not game events: interface actions and scan-pipeline events.
/// DartUI translates `ScanEvent` into these; DartAudio does not import DartVision.
public enum InterfaceCue: Hashable, Sendable {
    /// First turn of a game: "Au tour de Léa".
    case gameStarted(firstPlayer: PlayerIndex)
    /// Medium-confidence dart: played after the dart's own cues.
    case dartNeedsReview
    /// Low-confidence dart: not sent to the game; its score is not announced, only "Please check" (§7.3).
    case dartUndecided
    /// A dart arrived while the turn was complete.
    case dartIgnored
    /// Throw-like motion and nothing stuck.
    case possibleMiss
    /// The board is empty again: the "next player" button is ready.
    case boardCleared
    case undo
    case correctionApplied
    case shutter
    case calibrationValidated
    case calibrationLost
    case buttonTap
}

public enum CueMapping {
    /// Cues for the events of ONE accepted input, in order (table of ARCHITECTURE.md §7.3).
    public static func cues(for events: [GameEvent], context: CueContext) -> [AudioCue] { unimplemented() }
    public static func cues(for cue: InterfaceCue, context: CueContext) -> [AudioCue] { unimplemented() }
}

/// Sentences of the score caller. Numbers stay in digits: the voice reads "180" as "cent quatre-vingts".
public enum CallerPhrases {
    /// "Triple 20" / "Treble 20", "Double 16", "20", "Bull" (SB), "Double bull" / "Bullseye" (DB), "Manqué" / "Miss".
    public static func hit(_ hit: Hit) -> LocalizedText { unimplemented() }
    /// The total in digits, the same in both languages: "140", "180". The exclamation of a 180 belongs to the
    /// `oneEighty` event (`phrase(for:context:)`), which Radar never emits.
    public static func turnTotal(_ points: Int) -> LocalizedText { unimplemented() }
    /// "Au tour de Léa" / "Léa to throw".
    public static func nextPlayer(_ name: String) -> LocalizedText { unimplemented() }
    /// "Léa gagne la partie" / "Léa wins"; "Égalité entre Léa et Tom" / "Léa and Tom tie" for several names.
    /// Not called when `CueContext.winnerTitle` is set: that headline is said instead.
    public static func winners(_ names: [String]) -> LocalizedText { unimplemented() }
    /// The sentence of one event, by the table of ARCHITECTURE.md §7.3: "Léa est Killer", "Tom est éliminé",
    /// "Nouveau numéro : 16", "Cent quatre-vingts !", "But !", "Trou en un !", "3 coups"… Nil for an event without one.
    public static func phrase(for event: GameEvent, context: CueContext) -> LocalizedText? { unimplemented() }
}

// MARK: - 3. Synthesis (pure, testable without audio hardware)

public enum SoundSynthesizer {
    /// Mono samples in -1...1 for one effect. Deterministic: same input, same samples. 0.05 s to 1.5 s long.
    public static func samples(for effect: SoundEffect, sampleRate: Double) -> [Float] { unimplemented() }
}

// MARK: - 4. Service

/// The sound service seen by DartUI. Main-actor API; never blocks, never throws: a sound that cannot be played is skipped.
@MainActor
public protocol SoundPlaying: AnyObject {
    /// Applied immediately (session category, volumes, voice).
    var settings: AudioSettings { get set }
    /// True on devices with a Taptic Engine (iPhone). The settings screen disables the haptics row otherwise.
    var supportsHaptics: Bool { get }
    /// Configures the audio session, builds the engine and its buffers, pre-warms the voice. Idempotent.
    func prepare()
    /// Plays a batch: effects and haptics at their `delay`, announcements by priority.
    func play(_ cues: [AudioCue])
    /// Stops every sound and the voice.
    func stopAll()
    /// false when the app leaves the foreground (engine paused), true when it comes back.
    func setActive(_ active: Bool)
}

extension SoundPlaying {
    public func play(_ effect: SoundEffect) { play([AudioCue(effect: effect)]) }
    public func say(_ text: LocalizedText, priority: Announcement.Priority = .normal) {
        play([AudioCue(announcement: Announcement(text, priority: priority))])
    }
}

/// The real service: AVAudioEngine + player-node pool, AVSpeechSynthesizer, haptics, audio session.
@MainActor
public final class AudioDirector: SoundPlaying {
    public var settings: AudioSettings { get { unimplemented() } set { unimplemented() } }
    public var supportsHaptics: Bool { unimplemented() }
    public init(settings: AudioSettings = AudioSettings()) { unimplemented() }
    public func prepare() { unimplemented() }
    public func play(_ cues: [AudioCue]) { unimplemented() }
    public func stopAll() { unimplemented() }
    public func setActive(_ active: Bool) { unimplemented() }
}

/// Plays nothing and remembers what it was asked: tests, previews, SnapshotTool.
@MainActor
public final class SilentSoundPlayer: SoundPlaying {
    public var settings: AudioSettings
    public var supportsHaptics: Bool
    public private(set) var played: [AudioCue] = []
    public init(settings: AudioSettings = AudioSettings(), supportsHaptics: Bool = false) {
        self.settings = settings
        self.supportsHaptics = supportsHaptics
    }
    public func prepare() {}
    public func play(_ cues: [AudioCue]) { played += cues }
    public func stopAll() {}
    public func setActive(_ active: Bool) {}
}
```

Fichier `DartKit/Sources/DartAudio/Unimplemented.swift` (squelette F0, supprimé par A1) :

```swift
func unimplemented(_ function: StaticString = #function) -> Never {
    fatalError("unimplemented: \(function)")
}
```

Réglages de l'écran « Réglages » (`DESIGN.md` §4) et champs de `AudioSettings` :

| Réglage affiché | Champ |
|---|---|
| Effets sonores | `effectsEnabled` |
| Annonce vocale des scores | `callerEnabled` |
| Voix : Français / English | `callerLanguage` |
| Volume | `volume` |
| Son en mode silencieux | `playsInSilentMode` |
| Baisser la musique pendant l'annonce | `ducksMusicWhileSpeaking` |
| Vibrations (iPhone seulement) | `hapticsEnabled`, grisé quand `supportsHaptics == false` |
| Bouton « muet » de l'écran de jeu | `isMuted` |

### 7.3 Table événement → son

Cette table est la spécification de `CueMapping.cues(for:context:)`. Elle se lit pour **un lot d'événements**, c'est-à-dire les événements d'une seule entrée acceptée, dans leur ordre.

| `GameEvent` | Effet | Phrase (priorité) | Vibration |
|---|---|---|---|
| `dartRegistered(hit)` | `dartImpact` ; `dartDull` si la case est `MISS` ou si le lot contient `noEffect`, `doubleInRequired`, `healWasted` ou `shotPlayed(strokes: 5)` | `CallerPhrases.hit(hit)` (`low`) | `light` |
| `noEffect`, `doubleInRequired`, `healWasted`, `shotPlayed` | — (voir ligne précédente) | — | — |
| `turnCompleted`, `roundStarted`, `targetDead` | — | — | — |
| `turnStarted(player)` | `turnChange` | « Au tour de Léa » (`normal`) ; rien en solo | — |
| `turnScored(points)` | — | `CallerPhrases.turnTotal(points)` (`normal`), le total en chiffres ; rien si le lot contient `oneEighty` | — |
| `highTurn` | `highTurn` | — | `medium` |
| `oneEighty` | `fanfare` | « Cent quatre-vingts ! » / "One hundred and eighty!" (`high`) | `success` |
| `bust` | `bust` | « Bust » / "Bust" (`high`) | `failure` |
| `doubleInOpened` | `scoreUp` | — | — |
| `checkout`, `landed` | — (le son de victoire vient de `gameFinished`) | — | — |
| `marksScored(count)` | `tick`, `count` fois (au plus 9), espacés de 0,09 s | — | — |
| `targetClosed` | `lock` | — | `medium` |
| `pointsScored`, `pointsGiven`, `targetScored`, `neighbourHit`, `targetHit` | `scoreUp` | — | — |
| `armingHit` | `tick` | — | — |
| `becameKiller` | `powerUp` | « Léa est Killer » / "Léa is a Killer" (`normal`) | `medium` |
| `lifeLost`, `damaged`, `sectorDamaged` | `damage` | — | `medium` |
| `healed`, `sectorStrengthened` | `heal` | — | — |
| `sectorClaimed`, `sectorConquered` | `claim` | — | — |
| `kingOfTheHill` | `powerUp` | « Léa est Roi » / "Léa is King" (`normal`) | `medium` |
| `zoneChanged(zone)` | `zoneMove` | « Nouveau numéro : 16 » / "New number: 16" (`normal`), après « Au tour de… » ; pour une zone de plusieurs numéros, « Nouveaux numéros : 17, 3, 19 » / "New numbers: 17, 3, 19" | — |
| `shanghai` | `fanfare` | « Shanghai ! » / "Shanghai!" (`high`) | `success` |
| `halved` | `halved` | « Score divisé par deux » / "Score halved" (`normal`) | `warning` |
| `glassFilled(count)` | `scoreUp` | — | `medium` |
| `bonusGlass` | `powerUp` | « Tournée offerte ! » / "This one's on the house!" (`normal`) | `success` |
| `ballMoved` | `tick` | — | — |
| `goalScored(ownGoal)` | `fanfare` ; `halved` si `ownGoal` | « But ! » / "Goal!" (`high`) ; « Contre son camp ! » / "Own goal!" si `ownGoal` | `success` ; `warning` si `ownGoal` |
| `blobDamaged` | `damage` | — | `medium` |
| `blobDestroyed` | `powerUp` | — | `heavy` |
| `blobsMoved` | `zoneMove` | — | — |
| `holeCompleted(strokes)` | — | « 3 coups » / "3 strokes", « 1 coup » / "1 stroke" (`normal`) ; rien si le lot contient `holeInOne` | — |
| `holeInOne` | `fanfare` | « Trou en un ! » / "Hole in one!" (`high`) | `success` |
| `playerEliminated(player)` | `eliminated` | « Tom est éliminé » / "Tom is out" (`high`) | `heavy` |
| `gameFinished` | `victory` | `context.winnerTitle` s'il est renseigné, dit tel quel ; sinon `CallerPhrases.winners(…)` d'après `context.winners` ; priorité `high`, 0,6 s plus tard | `success` |

Précisions pour les quatre jeux du lot G4 :

- Les dix événements nouveaux ont chacun leur ligne ; le `switch` de `CueMapping` reste exhaustif, sans cas `default`.
- **Aucun effet sonore nouveau** : ces événements réutilisent les vingt-deux effets existants.
- **Radar** émet `turnScored` sans jamais émettre `oneEighty` : une volée de 180 points s'y annonce « 180 », comme tout autre total. C'est pourquoi `CallerPhrases.turnTotal` rend toujours les chiffres, et que l'exclamation « Cent quatre-vingts ! » appartient à l'événement `oneEighty`.
- **Golf** n'émet ni `noEffect` ni `turnScored` : `shotPlayed` porte la valeur de chaque fléchette (une fléchette à 5 coups sonne creux, `dartDull`), `holeCompleted` annonce le score du trou.
- **Football**, à `gameFinished` : les vainqueurs de `context.winners` sont les joueurs d'un camp, pas des ex æquo. Le jeu le dit par une donnée : `GameSnapshot.winnerTitle` (§4.6), que `DartUI` recopie dans `context.winnerTitle`, vaut « Le camp A gagne » / "Side A wins", « Le camp B gagne » / "Side B wins" ou « Match nul » / "It's a draw". `CueMapping` dit ce titre tel quel et n'appelle pas `CallerPhrases.winners`. Il ne lit jamais `context.gameID` : la règle vaut pour tout jeu qui renseignerait `winnerTitle` (principe 2 de §1.2).

| `InterfaceCue` | Effet | Phrase (priorité) | Vibration |
|---|---|---|---|
| `gameStarted(firstPlayer)` | `turnChange` | « Au tour de Léa » (`normal`) ; rien en solo | — |
| `dartNeedsReview` | `needsReview` | — | `light` |
| `dartUndecided` | `needsReview` | « À vérifier » / "Please check" (`normal`) | `warning` |
| `dartIgnored` | `rejected` | — | `warning` |
| `possibleMiss`, `boardCleared` | — | — | `light` |
| `undo` | `tick` | — | `light` |
| `correctionApplied` | `confirm` | — | `light` |
| `shutter` | `shutter` | — | `medium` |
| `calibrationValidated` | `confirm` | — | `success` |
| `calibrationLost` | `alert` | « Calibrage perdu » / "Calibration lost" (`high`) | `failure` |
| `buttonTap` | — | — | `light` |

Règles de mise en séquence :

- les effets d'un lot partent dans l'ordre des événements, espacés de 0,12 s, le premier à 0 s (`AudioCue.delay`) ;
- une seule vibration par lot : la plus forte (`failure` > `success` > `warning` > `heavy` > `medium` > `light`) ;
- les réglages filtrent à la lecture, pas dans la table : `effectsEnabled`, `callerEnabled`, `hapticsEnabled`, `isMuted`.

### 7.4 Architecture interne

```
Sources/DartAudio/
  SoundEffect.swift            SoundEffect, HapticPattern
  AudioCue.swift               Announcement, AudioCue, AudioSettings, CueContext, InterfaceCue
  CueMapping.swift             la table de §7.3
  CallerPhrases.swift          phrases de l'annonce, dans les deux langues
  SoundSynthesizer.swift       recettes des effets (calcul pur)
  SoundPlaying.swift           protocole, SilentSoundPlayer
  AudioDirector.swift          façade @MainActor
  EffectsPlayer.swift          AVAudioEngine et nœuds (interne)
  ScoreCaller.swift            AVSpeechSynthesizer (interne) ; aucun #if : voir setSpeechUsesApplicationSession
  HapticsPlayer.swift          #if os(iOS)
  AudioSessionController.swift #if os(iOS) ; porte aussi setSpeechUsesApplicationSession(_:on:)
```

Seuls `HapticsPlayer.swift` et `AudioSessionController.swift` contiennent `#if os(iOS)`. Tout appel à une API absente de macOS passe par eux. En particulier `AVSpeechSynthesizer.usesApplicationAudioSession` est indisponible sur macOS (vérifié avec le SDK macOS 27.2) : `ScoreCaller` ne l'écrit jamais lui-même, il appelle

```swift
enum AudioSessionController {
    /// iOS: `synthesizer.usesApplicationAudioSession = uses`. Other platforms: does nothing.
    static func setSpeechUsesApplicationSession(_ uses: Bool, on synthesizer: AVSpeechSynthesizer)
}
```

La forme interne d'`AudioSessionController` (énumération sans cas, classe ou structure) est libre ; cette fonction et son comportement sur macOS sont imposés.

**Lecture des effets** (`EffectsPlayer`)

- Un `AVAudioEngine`, quatre `AVAudioPlayerNode` utilisés à tour de rôle (polyphonie), tous reliés au mélangeur principal dans un format fixe : mono, 44 100 Hz, flottant.
- À `prepare()`, chaque `SoundEffect` est synthétisé une fois dans ce format (`SoundSynthesizer`) et gardé en `AVAudioPCMBuffer`. Un tampon dont le format diffère de celui du nœud échoue : c'est pourquoi le format est fixe et le mélangeur fait la conversion vers la sortie.
- Lecture : `scheduleBuffer` sur le nœud suivant avec l'option `.interrupts`, puis `play()`.
- Volume : `mainMixerNode.outputVolume = settings.volume`.
- Si le moteur ne démarre pas (pas de sortie audio, erreur de session), les effets sont ignorés jusqu'au prochain `prepare()` ou `setActive(true)`.

**Session audio** (`AudioSessionController`, iOS seulement)

| Situation | Action |
|---|---|
| `prepare()` | catégorie `.playback` avec `.mixWithOthers` si `playsInSilentMode`, sinon `.ambient` ; puis `setActive(true)` juste avant le démarrage du moteur |
| Changement de `playsInSilentMode` | même séquence ; le moteur est redémarré |
| Interruption (appel, alarme), iOS 17 à 26 | `AVAudioSession.interruptionNotification` : à la fin, réactiver la session et redémarrer le moteur, sans consulter `shouldResume` |
| Interruption, iOS 27 et plus | `didBecomeInactiveNotification` et `resumptionRecommendationNotification`, derrière `if #available(iOS 27, *)` |
| `AVAudioEngineConfigurationChange` (changement de sortie) | le moteur s'est arrêté seul : refaire les connexions et le redémarrer ; ne jamais libérer le moteur dans ce gestionnaire |
| `mediaServicesWereResetNotification` | tout reconstruire (moteur, nœuds, tampons, synthétiseur vocal) |
| `setActive(false)` (arrière-plan) | `engine.pause()` ; `setActive(true)` le relance |

- Les noms des notifications d'iOS 27 viennent de l'étude du SDK 27.2 ; le lot A1 les confirme à la compilation pour iOS.
- `.duckOthers` n'est **jamais** posé sur la session de l'application : la baisse de la musique ne passe que par la voix (§7.5).
- `setActive` est bloquant : toute la séquence session + moteur s'exécute sur la file série privée d'`AudioDirector`, jamais sur le fil principal (§11).

### 7.5 Annonce vocale

- Un seul `AVSpeechSynthesizer`, gardé par `ScoreCaller` (le système ne le retient pas). Un `AVSpeechUtterance` neuf par phrase.
- Texte : `announcement.text[settings.callerLanguage]`. Les nombres restent en chiffres ; la voix les lit.
- Voix : parmi `AVSpeechSynthesisVoice.speechVoices()` de la langue voulue, écarter les voix fantaisie et les voix personnelles, préférer `premium`, puis `enhanced`, puis `default` ; à défaut `AVSpeechSynthesisVoice(language: callerLanguage.voiceLanguageCode)`. Réévaluer sur `availableVoicesDidChangeNotification`.
- Volume : `utterance.volume = Float(settings.volume)`. Débit par défaut.
- Baisse de la musique : `AudioSessionController.setSpeechUsesApplicationSession(!settings.ducksMusicWhileSpeaking, on: synthesizer)` (§7.4 ; sans effet sur macOS). À `false`, la voix utilise une session gérée par le système, qui baisse les autres sons **seulement pendant la phrase**. On ne reconfigure jamais la catégorie autour d'une phrase.
- Préchauffage : une phrase d'un espace, volume 0 (la première phrase est lente sinon). Il a lieu une fois, au premier `prepare()` où l'annonce peut s'entendre (`callerEnabled` et pas `isMuted`), sinon au premier réglage qui la rend audible : la phrase de préchauffage baisse brièvement la musique de l'utilisateur, elle n'est donc jamais dite pour rien.
- Priorités :

| Priorité | Arrivée d'une phrase |
|---|---|
| `low` | abandonnée si une phrase `normal` ou `high` est en cours ou en attente ; sinon elle remplace toute phrase `low` en cours ou en attente |
| `normal` | se met en file derrière la phrase en cours ; retire les phrases `low` qui n'ont pas commencé |
| `high` | `stopSpeaking(at: .immediate)`, vide la file, parle |

Exemple : sur une troisième fléchette, « Triple 20 » (`low`) est dit, puis « 140 » (`normal`) suit. Si la fléchette suivante arrive pendant « Triple 20 », sa phrase le remplace.

Précisions de la réalisation (lot A1) :

- dans **un même lot**, une phrase `low` qu'une phrase `high` du lot couperait moins de 0,5 s après son début n'est pas commencée : sur un 180 ou un bust, seule l'exclamation s'entend, jamais « Tri— Cent quatre-vingts ! ». Appliquée à la lettre, la règle « `high` interrompt tout » laisse aussi une phrase `high` couper une phrase `high` plus ancienne du même lot (« Tom est éliminé » coupé 0,7 s plus tard par le nom du vainqueur) : c'est le comportement livré ;
- une phrase dont la voix ne signale jamais la fin est abandonnée au bout de 12 s, pour que l'annonce ne se bloque pas ; au plus 4 phrases attendent, les plus anciennes sont retirées ;
- en français, « de » s'élide devant une voyelle (« Au tour d'Alice »), y compris un Y suivi d'une consonne (« Au tour d'Yves » ; mais « de Yann », « de Hugo ») ; `winners([])` rend « Partie terminée » / "Game over".

Point non vérifié, à essayer sur un appareil : le comportement de la session vocale séparée quand le commutateur Silence est actif. Repli sans changement d'API : régler `ducksMusicWhileSpeaking` à `false`, la voix suit alors la session de l'application.

Phrases (`CallerPhrases`) :

| Appel | Français | Anglais |
|---|---|---|
| `hit(.treble(20))` | « Triple 20 » | "Treble 20" |
| `hit(.double(16))` | « Double 16 » | "Double 16" |
| `hit(.single(5))` | « 5 » | "5" |
| `hit(.outerBull)` | « Bull » | "Bull" |
| `hit(.innerBull)` | « Double bull » | "Bullseye" |
| `hit(.miss)` | « Manqué » | "Miss" |
| `turnTotal(140)` | « 140 » | "140" |
| `turnTotal(180)` | « 180 » | "180" |
| `nextPlayer("Léa")` | « Au tour de Léa » | "Léa to throw" |
| `winners(["Léa"])` | « Léa gagne la partie » | "Léa wins" |
| `winners(["Léa", "Tom"])` | « Égalité entre Léa et Tom » | "Léa and Tom tie" |
| `phrase(for: .oneEighty)` | « Cent quatre-vingts ! » | "One hundred and eighty!" |
| `phrase(for: .bonusGlass)` | « Tournée offerte ! » | "This one's on the house!" |
| `phrase(for: .goalScored)`, `ownGoal == false` | « But ! » | "Goal!" |
| `phrase(for: .goalScored)`, `ownGoal == true` | « Contre son camp ! » | "Own goal!" |
| `phrase(for: .holeCompleted)`, 3 coups, 1 coup | « 3 coups », « 1 coup » | "3 strokes", "1 stroke" |
| `phrase(for: .holeInOne)` | « Trou en un ! » | "Hole in one!" |
| `gameFinished` avec `context.winnerTitle` renseigné (Football) | le titre tel quel : « Le camp A gagne », « Match nul » | "Side A wins", "It's a draw" |

`phrase(for:context:)` rend `nil` pour un événement sans phrase dans la table de §7.3 (`glassFilled`, `ballMoved`, `blobDamaged`, `blobDestroyed`, `blobsMoved`, `shotPlayed`…).

### 7.6 Vibrations

- `HapticsPlayer` (iOS) : `UIImpactFeedbackGenerator` pour `light`, `medium`, `heavy` ; `UINotificationFeedbackGenerator` pour `success`, `warning`, `failure`. Fil principal.
- `supportsHaptics` vaut `CHHapticEngine.capabilitiesForHardware().supportsHaptics`. On ne teste jamais le type d'appareil.
- Un iPad n'a pas de vibreur : tout événement a donc aussi un son **et** un signe visuel (`DartUI`).

### 7.7 Synthèse des effets

`SoundSynthesizer.samples(for:sampleRate:)` est un calcul pur ; il rend un tableau vide, sans planter, pour une fréquence d'échantillonnage non finie ou hors de 8 à 192 kHz : sinusoïdes, bruit pseudo-aléatoire (`SeededRandom` à graine fixe, pour rester déterministe), enveloppes. Contraintes testées : durée de 0,05 à 1,5 s, crête ≤ 0,9, fondu d'entrée et de sortie d'au moins 3 ms (pas de clic), signal non nul. Point de départ des recettes, à régler à l'oreille :

| Effet | Recette | Durée |
|---|---|---|
| `dartImpact` | bruit bref filtré + sinus 160 Hz amorti | 0,12 s |
| `dartDull` | sinus 110 Hz amorti, sans bruit | 0,10 s |
| `scoreUp` | deux notes montantes (660 → 880 Hz) | 0,18 s |
| `tick` | clic à 1 800 Hz | 0,05 s |
| `lock` | deux clics graves rapprochés | 0,15 s |
| `powerUp` | glissando montant 300 → 1 200 Hz | 0,45 s |
| `damage` | bruit + sinus descendant 220 → 110 Hz | 0,25 s |
| `heal` | arpège doux montant (3 notes) | 0,35 s |
| `claim` | note tenue 520 Hz + quinte | 0,30 s |
| `eliminated` | trois notes descendantes | 0,60 s |
| `bust` | onde carrée 140 Hz | 0,45 s |
| `halved` | glissando descendant 600 → 300 Hz | 0,40 s |
| `highTurn` | accord majeur bref | 0,35 s |
| `fanfare` | arpège majeur de 4 notes + accord tenu | 1,10 s |
| `victory` | fanfare longue, 6 notes | 1,50 s |
| `turnChange` | deux notes neutres (440, 550 Hz) | 0,20 s |
| `zoneMove` | balayage aller-retour | 0,30 s |
| `needsReview` | deux bips identiques (700 Hz) | 0,22 s |
| `rejected` | bip grave unique | 0,18 s |
| `shutter` | deux clics de bruit | 0,12 s |
| `confirm` | note claire 880 Hz | 0,15 s |
| `alert` | trois bips descendants | 0,50 s |

---

## 8. DartUI

### 8.1 Rôle et dépendances

`DartUI` contient tous les écrans SwiftUI, leurs modèles de vue (framework Observation, `@MainActor`), la navigation, l'abstraction d'entrée des fléchettes, la persistance et la localisation. Il dépend des quatre autres cibles. C'est le seul endroit où une observation de la caméra devient une fléchette du jeu, puis un son.

L'apparence suit `DESIGN.md` et ses maquettes (`docs/design/mockups/*.dc.html`) : thème sombre unique, jetons de `Theme`, une seule vue de cible (`DartboardView`). En cas de doute entre ce document et une maquette sur l'apparence, la maquette gagne ; sur une interface de code, ce document gagne.

### 8.2 API publique

Trois choses seulement sont publiques :

| Symbole | Utilisé par | Fichier |
|---|---|---|
| `DartScannerRootView`, `AppEnvironment` | la coquille `App/` | `App/AppModel.swift` |
| `KeyValueStoring`, `UserDefaultsStore`, `InMemoryStore` | `AppEnvironment` | `Persistence/Persistence.swift` |
| `SnapshotCatalog`, `SnapshotScreen`, `SnapshotDevice` | `SnapshotTool` | `Snapshots/SnapshotCatalog.swift` |

Tout le reste est `internal` : les lots U1, U2 et U3 travaillent dans le même module et se parlent par les contrats de §8.4.

### 8.3 Écrans

Chaque écran a deux vues :

- `XxxScreen` : la coquille (navigation, barre d'outils, feuilles, défilement, tâches asynchrones). Elle lit les modèles de vue.
- `XxxContent` : la mise en page pure, alimentée par des valeurs simples. C'est elle que `SnapshotTool` rend, avec des données d'exemple.

| Écran | Vue d'entrée | Dossier | Lot | Maquette | Id d'instantané |
|---|---|---|---|---|---|
| Accueil : état de la caméra, bascule scan / manuel, grille des jeux | `HomeScreen` | `Home/` | U2 | `Main` | `home` |
| Préparation : joueurs et options d'un jeu | `SetupScreen` | `Setup/` | U2 | `KillerOptions` | `setup-killer`, `setup-x01` |
| Gestion des joueurs | `PlayersScreen` | `Players/` | U2 | — | `players` |
| Partie : tableau de score, cible, volée, actions | `PlayScreen` | `Play/` | U2 | `PlayKiller`, `PlayX01`, `PadPlayKiller` | `play-killer`, `play-x01`, `play-cricket`, `play-highscore`, `play-beertap`, `play-football`, `play-radar`, `play-golf` |
| Correction d'une fléchette | `CorrectionSheet` | `Play/` | U2 | `Correction` | `correction` |
| Résultats (dans `PlayScreen` quand la partie est finie) | `ResultsContent` (interne au lot U2 : pas de point d'entrée dans §8.4.10, F0 ne crée aucun fichier dans `Results/`) | `Results/` | U2 | `Results` | `results` |
| Réglages | `SettingsScreen` | `Settings/` | U2 | `Settings` | `settings` |
| Aide au placement | `PlacementGuideView` | `Camera/` | U3 | — | `placement-guide` |
| Caméra refusée ou absente | dans `CalibrationFlowView` | `Camera/` | U3 | — | `camera-denied`, `camera-unavailable` |
| Calibrage | `CalibrationFlowView` | `Calibration/` | U3 | `Calibration` | `calibration` (poignées), `calibration-proof` (vue de preuve) |
| Scan en direct | `LiveScanView` | `Scan/` | U3 | `LiveScan` | `live-scan` |
| Vignette caméra (colonne iPad) | `ScanThumbnail` | `Scan/` | U3 | `PadPlayKiller` | `scan-thumbnail` (l'écran de jeu du Killer avec sa vignette) |
| Mode photo, toujours accessible depuis l'écran de jeu (§8.6) | `PhotoModeView` | `Photo/` | U3 | `PhotoMode` | `photo-mode`, `photo-mode-no-camera`, `photo-review-empty`, `photo-tips` |

Instantanés du socle (lot U1) : `board-plain`, `board-zones`, `board-discs`, `components`.

Les quatre jeux du lot G4 n'ont ni écran ni maquette propres : ils passent par `SetupScreen` et `PlayScreen`, avec les deux gabarits existants (`DESIGN.md` §4).

### 8.4 Contrats internes

Les fichiers de ce paragraphe sont créés par F0 tels qu'ils sont imprimés. Ils sont la frontière entre les lots U1, U2 et U3 : un lot remplit les corps des fichiers qui lui appartiennent et **ne change aucune signature**.

#### 8.4.1 Thème

Fichier `DartKit/Sources/DartUI/Design/Theme.swift` (complet) :

```swift
import SwiftUI
import DartCore

/// Design tokens of DESIGN.md §2. Dark theme only. Views never write a colour, a radius or a font size literally.
enum Theme {
    enum Palette {
        static let background = Color(hex: 0x0E1114)
        static let surface = Color(hex: 0x171C21)
        static let surfaceRaised = Color(hex: 0x212830)
        static let line = Color(hex: 0x2E3640)
        static let lineStrong = Color(hex: 0x5A6470)
        static let textPrimary = Color(hex: 0xF3F1EA)
        static let textSecondary = Color(hex: 0xA9B1BA)
        static let textTertiary = Color(hex: 0x8A939D)
        static let accent = Color(hex: 0xFFA630)
        static let onAccent = Color(hex: 0x1A1206)
        static let info = Color(hex: 0x5CB2FF)
        static let boardRed = Color(hex: 0xD8413A)
        static let boardGreen = Color(hex: 0x2F9E5B)
        static let boardCream = Color(hex: 0xE9DFC7)
        static let boardBlack = Color(hex: 0x1B1F23)
        static let boardSurround = Color(hex: 0x0A0C0E)
        static let cameraScrim = Color(hex: 0x0E1114).opacity(0.78)
        /// Colours of players 1 to 8, by player index.
        static let players: [Color] = [0xFFA630, 0x5CB2FF, 0xB79CFF, 0xFF8FB8, 0x6FE0C8, 0xF2E26B, 0xFF8A5C, 0xC8D0D8].map { Color(hex: $0) }
    }

    static func playerColor(_ index: PlayerIndex) -> Color {
        Palette.players[((index % Palette.players.count) + Palette.players.count) % Palette.players.count]
    }

    static func color(for tone: Tone) -> Color {
        switch tone {
        case .neutral: return Palette.textSecondary
        case .positive: return Palette.boardGreen
        case .negative: return Palette.boardRed
        case .accent: return Palette.accent
        }
    }

    enum Radius {
        static let card: CGFloat = 16
        static let row: CGFloat = 12
        static let badge: CGFloat = 8
    }

    enum Spacing {
        /// Space between blocks of a game screen.
        static let block: CGFloat = 12
        static let section: CGFloat = 16
    }

    /// Values that differ between a compact and a regular width (iPhone vs iPad column).
    struct Metrics: Equatable {
        var screenMargin: CGFloat
        var buttonHeight: CGFloat
        var playerRowHeight: CGFloat
        var dartMarker: CGFloat
        var slotTitle: CGFloat
        var slotCaption: CGFloat

        static let compact = Metrics(screenMargin: 20, buttonHeight: 52, playerRowHeight: 44, dartMarker: 14, slotTitle: 17, slotCaption: 11)
        static let regular = Metrics(screenMargin: 32, buttonHeight: 56, playerRowHeight: 56, dartMarker: 26, slotTitle: 22, slotCaption: 13)

        init(screenMargin: CGFloat, buttonHeight: CGFloat, playerRowHeight: CGFloat, dartMarker: CGFloat, slotTitle: CGFloat, slotCaption: CGFloat) {
            self.screenMargin = screenMargin
            self.buttonHeight = buttonHeight
            self.playerRowHeight = playerRowHeight
            self.dartMarker = dartMarker
            self.slotTitle = slotTitle
            self.slotCaption = slotCaption
        }

        init(_ sizeClass: UserInterfaceSizeClass?) {
            self = sizeClass == .regular ? .regular : .compact
        }
    }

    enum Typography {
        static let screenTitle = Font.system(size: 28, weight: .heavy)
        static let gameTitle = Font.system(size: 20, weight: .heavy)
        static let bigScore = Font.system(size: 64, weight: .heavy).monospacedDigit()
        static let winner = Font.system(size: 88, weight: .heavy)
        static let body = Font.system(size: 16, weight: .regular)
        static let bodyStrong = Font.system(size: 16, weight: .semibold)
        static let secondary = Font.system(size: 13, weight: .regular)
        static let button = Font.system(size: 17, weight: .bold)
    }
}

extension Color {
    /// 0xRRGGBB in sRGB.
    init(hex: UInt32) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255, opacity: 1)
    }
}
```

#### 8.4.2 Composants

Fichier `DartKit/Sources/DartUI/Design/Components.swift` :

```swift
import SwiftUI
import DartCore

// Shared components (DESIGN.md §2). All of them are drawn with SwiftUI shapes and text only. System controls
// (Toggle, Slider, Picker, Stepper, TextField, a Button with the default style) are not used in screen contents:
// `ImageRenderer` draws a placeholder instead of them, and they do not match the dark theme.
// Every Button carries a ButtonStyle written in SwiftUI (or `.plain`).

/// Main action: `accent` background, `onAccent` text, 52 pt high (56 in regular width), radius 16.
struct PrimaryButton: View {
    init(_ title: Text, systemImage: String? = nil, isEnabled: Bool = true, action: @escaping () -> Void) { unimplemented() }
    var body: some View { StubView() }
}

/// Secondary action: same height, 1 pt `line` border, transparent background.
struct SecondaryButton: View {
    init(_ title: Text, systemImage: String? = nil, isEnabled: Bool = true, action: @escaping () -> Void) { unimplemented() }
    var body: some View { StubView() }
}

/// `surface` background, radius 16, optional border (current player: 2 pt in the player's colour).
struct Card<Content: View>: View {
    init(border: Color? = nil, @ViewBuilder content: () -> Content) { unimplemented() }
    var body: some View { StubView() }
}

/// Small capsule, radius 8: "Killer", "À vérifier", "Scan en direct".
struct BadgeView: View {
    init(_ text: Text, color: Color, filled: Bool = false) { unimplemented() }
    var body: some View { StubView() }
}

/// Coloured disc with the player's initial, optionally followed by the name.
struct PlayerChip: View {
    init(name: String, index: PlayerIndex, showsName: Bool = true) { unimplemented() }
    var body: some View { StubView() }
}

/// Bubble laid over the camera image (`cameraScrim` background).
struct ScrimBubble<Content: View>: View {
    init(@ViewBuilder content: () -> Content) { unimplemented() }
    var body: some View { StubView() }
}

/// Settings row with a switch.
struct ToggleRow: View {
    init(_ title: Text, subtitle: Text? = nil, isOn: Binding<Bool>, isEnabled: Bool = true) { unimplemented() }
    var body: some View { StubView() }
}

/// "−  3  +" row (lives, arming hits, rounds). `nullLabel` adds a value below the range that maps to nil.
struct StepperRow: View {
    init(_ title: Text, value: Binding<Int?>, range: ClosedRange<Int>, nullLabel: Text? = nil) { unimplemented() }
    var body: some View { StubView() }
}

/// Two to four mutually exclusive segments ("Français | English", "En direct | Photo").
struct SegmentedChoice<Value: Hashable>: View {
    init(options: [(value: Value, label: Text)], selection: Binding<Value>) { unimplemented() }
    var body: some View { StubView() }
}

/// Radio row with a detail line, an optional pictogram and the note shown when it is unavailable (Killer levels).
struct RadioRow<Accessory: View>: View {
    init(title: Text, detail: Text? = nil, note: Text? = nil, isSelected: Bool, isEnabled: Bool = true,
         @ViewBuilder accessory: () -> Accessory, action: @escaping () -> Void) { unimplemented() }
    var body: some View { StubView() }
}

/// Horizontal level 0...1 (volume).
struct LevelSlider: View {
    init(value: Binding<Double>) { unimplemented() }
    var body: some View { StubView() }
}
```

#### 8.4.3 Cible

Fichier `DartKit/Sources/DartUI/Board/DartboardView.swift` :

```swift
import SwiftUI
import DartCore

extension BoardGeometry {
    /// Geometry of the DRAWN board (DESIGN.md §3): same bulls, thicker rings. Radii in the millimetre frame of
    /// `standard`: treble 97.0–110.5 (21.5 %–24.5 % of 451), double 160.1–173.6 (35.5 %–38.5 %).
    static let display = BoardGeometry(innerBullRadius: 6.35, outerBullRadius: 15.9,
                                       trebleInnerRadius: 97.0, trebleOuterRadius: 110.5,
                                       doubleInnerRadius: 160.1, doubleOuterRadius: 173.6, boardRadius: 225.5)
}

extension GameDescriptor {
    /// Geometry of the board drawn for this game: thick rings, except for a position-dependent game, whose board
    /// is drawn at regulation proportions so that a drawn disc covers exactly the disc of the game (DESIGN.md §4).
    var boardGeometry: BoardGeometry {
        dependsOnPosition ? .standard : .display
    }
}

/// A dart drawn on the board.
struct BoardDartMarker: Identifiable, Hashable {
    let id: UUID
    /// NOMINAL board millimetres (the view remaps to the display geometry).
    var position: BoardPoint
    var label: String?
    var style: Style

    enum Style: Hashable {
        /// Off-white disc.
        case neutral
        /// Disc in the colour of a player.
        case player(PlayerIndex)
        /// Amber disc with "?": to be checked.
        case review
    }
}

/// A tap on the drawn board, already converted.
struct BoardTap: Hashable {
    /// Hit under the finger, computed with the geometry of the DRAWING (a tap on the drawn treble ring is a treble).
    var hit: Hit
    /// The same point in NOMINAL millimetres: it becomes `DartRecord.position`.
    var position: BoardPoint
}

/// The one and only board drawing: play, manual input, correction, Killer levels, option pictograms.
/// Pure SwiftUI (`Canvas`), so it renders under `ImageRenderer`.
struct DartboardView: View {
    /// - Parameters:
    ///   - highlights: zones to tint (GAMES.md §2.9); a zone with an owner uses that player's colour. A `.disc`
    ///     zone is a circle drawn over the beds, with its label and its hit-point pips (DESIGN.md §4).
    ///   - darts: markers, in nominal millimetres.
    ///   - geometry: geometry of the drawing: `.display` (thick rings) or `.standard` (regulation proportions).
    ///     Pass `descriptor.boardGeometry`: a position-dependent game is always drawn with `.standard`.
    ///   - dimsUnhighlighted: darkens the rest of the board when at least one highlight exists (DESIGN.md §3).
    ///   - showsNumbers: number ring around the board.
    ///   - onTap: tap (manual input). Nil makes the board non-interactive.
    ///   - onLongPress: long press (opens the magnified view).
    init(highlights: [BoardHighlight] = [], darts: [BoardDartMarker] = [], geometry: BoardGeometry = .display,
         dimsUnhighlighted: Bool = true, showsNumbers: Bool = true,
         onTap: ((BoardTap) -> Void)? = nil, onLongPress: ((BoardTap) -> Void)? = nil) { unimplemented() }
    var body: some View { StubView() }

    /// Conversion used by the view and by tests: a point of the view (origin top-left, `size` square) to a tap
    /// on a board drawn with `geometry`.
    static func tap(at location: CGPoint, in size: CGSize, geometry: BoardGeometry = .display) -> BoardTap { unimplemented() }
    /// Position in the view of a nominal board point, on a board drawn with `geometry`.
    static func location(of position: BoardPoint, in size: CGSize, geometry: BoardGeometry = .display) -> CGPoint { unimplemented() }
    /// Length in the view, in points, of `millimetres` of board: the radius of a drawn disc.
    static func length(of millimetres: Double, in size: CGSize) -> CGFloat { unimplemented() }
}
```

- La vue est carrée ; le rayon `boardRadius` (225,5 mm, le même dans les deux géométries) occupe la demi-largeur. L'échelle vaut donc `k = (size.width / 2) / 225,5` points par millimètre, et `length(of: mm, in: size) = mm × k`.
- **Deux géométries de dessin.** `geometry` vaut `.display` (anneaux épaissis, `DESIGN.md` §3) ou `.standard` (proportions réglementaires). L'appelant passe `descriptor.boardGeometry` : `.standard` pour un jeu dépendant de la position, `.display` pour tous les autres. Hors d'une partie (pictogrammes des options, instantanés de la cible nue), la valeur par défaut `.display` convient.
- **Un point nominal vers la vue** (`location(of:in:geometry:)`) : `q = BoardGeometry.standard.remap(p, to: geometry)`, puis `(size.width / 2 + q.x × k, size.height / 2 − q.y × k)`. Avec `.standard`, `q = p`. C'est ainsi qu'une fléchette détectée ou posée se dessine.
- **Un tap vers une fléchette** (`tap(at:in:geometry:)`) : le point du dessin `q = ((location.x − size.width / 2) / k, (size.height / 2 − location.y) / k)` ; la case est `geometry.hit(at: q)` ; la position nominale est `geometry.remap(q, to: .standard)`. Un tap sur l'anneau dessiné du triple donne donc bien un triple (`DESIGN.md` §3), et sa position tombe dans l'anneau réglementaire du triple. Avec `.standard`, la position est le point touché lui-même.
- **La position suit la fléchette.** `PlayViewModel.tapBoard(_:)` crée `DartProposal.manual(tap.hit, position: tap.position)` ; la position entre dans `DartRecord.position` et arrive au moteur (§4.8). Pour une fléchette de la caméra, c'est `DartObservation.tip`, déjà en millimètres nominaux, sans conversion.
- **Rendu des surbrillances de cases** : `DESIGN.md` §3. Rôle → aspect : `target` teinte pleine (couleur du propriétaire, sinon `accent`) ; `secondary` teinte à moitié ; `own` contour ; `avoid` hachures rouges ; `opponent` teinte faible ; `inactive` grisé. `label` s'écrit sur la zone, `strength` en pastilles.
- **Rendu d'une surbrillance `disc(x:y:radius:)`** (`DESIGN.md` §4, « Disques de Radar ») : un cercle de centre `location(of: BoardPoint(x: x, y: y), in: size, geometry: geometry)` et de rayon `length(of: radius, in: size)`, dessiné par-dessus les cases après elles. Remplissage à environ 60 % de la couleur du rôle (`accent` pour `target` sans propriétaire, la couleur du propriétaire sinon), contour plein de 2 pt ; au centre, une pastille pleine porte `label` ; dessous, trois pastilles de 4 pt, pleines pour les `strength` points de vie restants, vides pour les autres. Le reste de la cible est assombri comme pour toute surbrillance ; la surface sous le disque ne l'est pas, comme une case teintée (le remplissage à 60 % se pose sur les cases brutes).
- **Pourquoi `.standard` pour Radar.** Avec `.display`, les anneaux sont déformés : un cercle de la cible réelle n'y est plus un cercle. Avec `.standard`, le disque dessiné recouvre exactement le disque du jeu, et un tap dedans donne une position dedans : il compte comme une touche. `DartboardView` dessine quand même un disque sous `.display` (centre déplacé par `remap`, rayon inchangé), mais c'est une approximation qu'aucun écran de jeu n'utilise.
- **Bull.** Les deux bulls se dessinent aux rayons de la géométrie (15,9 et 6,35 mm dans les deux), plus petits que sur les maquettes (4,5 % et 2 % du diamètre) : ce qu'un tap marque est ce qui est dessiné.
- **Pictogramme.** En dessous de 64 pt de côté (pictogramme d'une option, `Theme.Control.accessory` = 36 pt, maquette `KillerOptions`), la vue dessine un disque plat de couleur `line` : secteurs entiers du centre au bord, sans numéros, sans anneaux, sans assombrissement ; zones `secondary`, `opponent` et `inactive` à 40 % ; disques sans étiquette ni pastilles.
- **Assombrissement.** `dimsUnhighlighted` vaut `true` par défaut, comme le veulent `DESIGN.md` §3 et le paragraphe ci-dessus ; une cible à viser sur un seul anneau est colorée à 92 % et porte son arc. La maquette `PlayX01`, elle, n'assombrit pas la cible autour de l'anneau de finition : l'écran de jeu peut passer `false`.
- **Tests** (lot U1) : un tap sur l'anneau dessiné du triple donne un triple sous `.display` ; aller-retour `location` puis `tap` pour le centre des 82 zones dans les deux géométries ; sous `.standard`, un tap à 1 pt à l'intérieur du bord d'un disque dessiné rend une position à l'intérieur du disque, et à 1 pt à l'extérieur une position à l'extérieur.

#### 8.4.4 Localisation et adaptations de plateforme

Fichier `DartKit/Sources/DartUI/Support/L10n.swift` (complet) :

```swift
import SwiftUI
import DartCore

// Localisation helpers (ARCHITECTURE.md §8.9).

/// String tables of DartUI. One table per work item, so that no two items edit the same file.
enum L10nTable: String, CaseIterable {
    /// Buttons, generic words, errors (lot U1).
    case common = "Common"
    /// Home, setup, play, correction, results, settings (lot U2).
    case game = "Game"
    /// Permission, placement guide, calibration, live scan, photo mode (lot U3).
    case camera = "Camera"
}

enum L10n {
    /// Resource bundle of DartUI (the `.strings` tables).
    static var bundle: Bundle { .module }

    /// SwiftUI text for a key of a table of `Bundle.module`. Follows `\.locale` (set at the root by `appLanguage(_:)`).
    static func text(_ key: LocalizedStringKey, _ table: L10nTable) -> Text {
        Text(key, tableName: table.rawValue, bundle: .module)
    }

    /// Plain string in an explicit language (accessibility labels built in code, tests, SnapshotTool).
    /// Interpolations follow the String Catalog rules: "turn.total \(n)" looks up the key "turn.total %lld".
    static func string(_ key: String.LocalizationValue, _ table: L10nTable, language: AppLanguage) -> String {
        var resource = LocalizedStringResource(key, table: table.rawValue, bundle: .atURL(Bundle.module.bundleURL))
        resource.locale = Locale(identifier: language.rawValue)
        return String(localized: resource)
    }
}

private struct AppLanguageKey: EnvironmentKey {
    static let defaultValue: AppLanguage = .fr
}

extension EnvironmentValues {
    /// Language of the interface. Set once at the root together with `\.locale`.
    var appLanguage: AppLanguage {
        get { self[AppLanguageKey.self] }
        set { self[AppLanguageKey.self] = newValue }
    }
}

extension View {
    /// Sets `\.appLanguage` and `\.locale` together, so that `Text(_:bundle:)` and `LocalizedText` agree.
    func appLanguage(_ language: AppLanguage) -> some View {
        environment(\.appLanguage, language).environment(\.locale, Locale(identifier: language.rawValue))
    }
}

/// Displays a `LocalizedText` in the language of the environment.
struct LocalizedTextView: View {
    let text: LocalizedText
    @Environment(\.appLanguage) private var language

    init(_ text: LocalizedText) {
        self.text = text
    }

    var body: some View {
        Text(verbatim: text[language])
    }
}
```

Fichier `DartKit/Sources/DartUI/Support/PlatformShims.swift` (complet) :

```swift
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// Platform shims. Only three files of DartUI contain `#if os(iOS)`: this one, `Camera/CameraPreviewView.swift`
// and `Camera/CaptureInterruptionObserver.swift`. Everything else uses cross-platform SwiftUI (ARCHITECTURE.md §8.8).

extension View {
    /// Full-screen cover on iOS, sheet on macOS.
    @ViewBuilder
    func gameCover<Item: Identifiable, Content: View>(item: Binding<Item?>,
                                                      @ViewBuilder content: @escaping (Item) -> Content) -> some View {
        #if os(iOS)
        fullScreenCover(item: item, content: content)
        #else
        sheet(item: item, content: content)
        #endif
    }

    /// Keeps the screen awake while `active` and the view is on screen (scan screens). No-op on macOS.
    @ViewBuilder
    func keepsScreenAwake(_ active: Bool) -> some View {
        #if os(iOS)
        self
            .onAppear { UIApplication.shared.isIdleTimerDisabled = active }
            .onChange(of: active) { _, isActive in UIApplication.shared.isIdleTimerDisabled = isActive }
            .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
        #else
        self
        #endif
    }
}

extension ToolbarItemPlacement {
    static var barLeading: ToolbarItemPlacement {
        #if os(iOS)
        .topBarLeading
        #else
        .navigation
        #endif
    }

    static var barTrailing: ToolbarItemPlacement {
        #if os(iOS)
        .topBarTrailing
        #else
        .primaryAction
        #endif
    }
}

enum SystemSettings {
    /// Opens the page of the app in the Settings app (camera permission). No-op on macOS.
    @MainActor
    static func open() {
        #if os(iOS)
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
        #endif
    }
}
```

Fichier `DartKit/Sources/DartUI/Support/Unimplemented.swift` (squelette ; supprimé par le lot I1 quand plus rien ne l'appelle) :

```swift
func unimplemented(_ function: StaticString = #function) -> Never {
    fatalError("unimplemented: \(function)")
}

import SwiftUI

/// Placeholder body of a view that is not written yet.
struct StubView: View {
    var body: some View { EmptyView() }
}
```

#### 8.4.5 Persistance

Fichier `DartKit/Sources/DartUI/Persistence/Persistence.swift` :

```swift
import Foundation
import DartCore
import DartAudio
import DartVision

/// Smallest possible storage seam: named blobs. JSON goes in, JSON comes out.
public protocol KeyValueStoring: Sendable {
    func data(forKey key: String) -> Data?
    func set(_ data: Data?, forKey key: String)
}

/// `UserDefaults.standard` (or a suite).
public struct UserDefaultsStore: KeyValueStoring, @unchecked Sendable {
    public init(suiteName: String? = nil) { unimplemented() }
    public func data(forKey key: String) -> Data? { unimplemented() }
    public func set(_ data: Data?, forKey key: String) { unimplemented() }
}

/// Volatile store for tests, previews and SnapshotTool.
public final class InMemoryStore: KeyValueStoring, @unchecked Sendable {
    public init(_ initial: [String: Data] = [:]) { unimplemented() }
    public func data(forKey key: String) -> Data? { unimplemented() }
    public func set(_ data: Data?, forKey key: String) { unimplemented() }
}

/// How darts enter the game by default.
enum InputMode: String, Codable, Sendable {
    case camera, manual
}

/// Camera mode (settings screen: "En direct" / "Photo").
enum ScanMode: String, Codable, Sendable {
    /// Automatic trigger on live video.
    case live
    /// One manual capture per turn ("Scanner la volée").
    case photo
}

/// Everything the settings screen edits. Stored under `StorageKey.settings`.
struct AppSettings: Hashable, Codable, Sendable {
    var audio = AudioSettings()
    var inputMode: InputMode = .manual
    var scanMode: ScanMode = .live
    /// Nil follows the system language.
    var language: AppLanguage?
    /// false (default): only the button ends a turn. true: an empty board detected by the camera ends a turn that is
    /// already closed, when no dart waits for an answer (GAMES.md §2.4, ARCHITECTURE.md §8.6).
    var endsTurnOnTakeout: Bool = false
}

/// A calibration as it is saved: valid for one camera, one rotation and one image size (VISION.md §4.10).
struct StoredCalibration: Hashable, Codable, Sendable {
    var cameraID: String
    var calibration: BoardCalibration
    /// Carries the shadow bound measured by the one-dart check.
    var configuration: VisionConfiguration
    var lightingCheckPassed: Bool
}

/// Last choices of the setup screen, per game.
struct SetupMemory: Hashable, Codable, Sendable {
    var playerIDs: [UUID]
    var options: GameOptions
}

enum StorageKey {
    static let settings = "settings.v1"
    static let roster = "roster.v1"
    static let calibrations = "calibrations.v1"
    static let currentMatch = "match.current.v1"
    static func setup(_ game: GameID) -> String { "setup.\(game.rawValue).v1" }
}

/// Typed access to the store. Decoding failures return the default value: a corrupted blob never blocks the app.
struct AppStorage: Sendable {
    let store: any KeyValueStoring
    init(store: any KeyValueStoring) { self.store = store }

    func loadSettings() -> AppSettings { unimplemented() }
    func save(_ settings: AppSettings) { unimplemented() }
    func loadRoster() -> [Player] { unimplemented() }
    func save(roster: [Player]) { unimplemented() }
    func loadSetup(for game: GameID) -> SetupMemory? { unimplemented() }
    func save(_ setup: SetupMemory, for game: GameID) { unimplemented() }
    /// Calibration saved for this camera, rotation and image size.
    func loadCalibration(cameraID: String, rotationDegrees: Int, imageSize: PixelSize) -> StoredCalibration? { unimplemented() }
    func save(_ calibration: StoredCalibration) { unimplemented() }
    /// Game in progress, saved after every accepted input; nil when none.
    func loadCurrentMatch() -> MatchRecord? { unimplemented() }
    func saveCurrentMatch(_ record: MatchRecord?) { unimplemented() }
}
```

#### 8.4.6 Entrée des fléchettes

C'est l'abstraction demandée : l'écran de jeu reçoit des `DartProposal`, qu'elles viennent de la caméra, d'un scan déclenché à la main, d'une photo ou d'un tap sur la cible virtuelle.

Les **commandes** que le jeu adresse à la source (`gameStarted`, `turnBegan`, `turnClosed`, `dartDiscarded`, `manualDartAdded`, `turnConfirmed`, `boardConfirmedEmpty`, `gameEnded`) sont **synchrones**. `PlayViewModel` est lui-même synchrone : il les appelle dans l'ordre et n'attend rien. C'est la source qui garantit que la vision les reçoit dans ce même ordre (§8.7, §11). Seules les deux **requêtes** qui rendent une valeur, `evidenceImage(for:)` et `rescore(_:tip:)`, sont `async`.

Fichier `DartKit/Sources/DartUI/Input/DartInput.swift` (figé) :

```swift
import Foundation
import CoreGraphics
import DartCore

/// How sure the application is about a proposed dart, FOR THE CURRENT GAME (VISION.md §7.4).
enum Certainty: Hashable, Sendable {
    /// Sent to the game.
    case certain
    /// Sent to the game and shown as "à vérifier".
    case needsReview
    /// Not sent: the player must answer first.
    case undecided
}

/// One dart proposed to the play screen, whatever its origin. Knows nothing about DartVision.
struct DartProposal: Identifiable, Sendable {
    /// For camera darts: `DartObservation.id`. It becomes `DartRecord.id`.
    let id: UUID
    /// Best hypothesis.
    var hit: Hit
    /// Nominal board millimetres, when known.
    var position: BoardPoint?
    var origin: DartOrigin
    /// Hits offered on the correction card, best first (at least 4 when the source has them).
    var choices: [Hit]
    /// Certainty of this dart for a given state of the game. Camera sources compute it with
    /// `DartObservation.tier(collapsingBy: { match.effectKey(for: $0, position: tip) })`, so that a doubt between
    /// two hits of equal effect does not bother the player (VISION.md §7.4). The measured tip is passed with every
    /// candidate hit: a position-dependent game is keyed on (hit, position) (GAMES.md §2.13). In such a game a
    /// certain dart is lowered to `needsReview` when its tip lies within its own uncertainty of a change of
    /// effect, e.g. the edge of a Radar target (ARCHITECTURE.md §8.4.8).
    var certainty: @Sendable (GameMatch) -> Certainty

    init(id: UUID, hit: Hit, position: BoardPoint?, origin: DartOrigin, choices: [Hit],
         certainty: @escaping @Sendable (GameMatch) -> Certainty) {
        self.id = id
        self.hit = hit
        self.position = position
        self.origin = origin
        self.choices = choices
        self.certainty = certainty
    }

    /// A tap on the virtual board (`position` = the tapped point, `BoardTap.position`), "Manqué", or a hit picked
    /// in a list (no position: a position-dependent game then uses the canonical position of the bed): always certain.
    static func manual(_ hit: Hit, position: BoardPoint? = nil) -> DartProposal {
        DartProposal(id: UUID(), hit: hit, position: position, origin: .manual, choices: [hit]) { _ in .certain }
    }

    /// The journal record for this proposal.
    func record(needsReview: Bool) -> DartRecord {
        DartRecord(id: id, hit: hit, position: position, origin: origin, needsReview: needsReview)
    }
}

/// What the header pill shows about the automatic input.
enum InputStatus: Hashable, Sendable {
    /// No automatic source: taps on the virtual board only.
    case manualOnly
    /// The source is starting or taking its references ("Ne bougez plus…").
    case preparing
    /// Darts are detected as they land.
    case live
    /// Waiting for a manual capture (photo mode).
    case awaitingCapture
    /// Hand or person in front of the board.
    case obstructed
    /// Paused (background, heat, user).
    case paused
    /// The references are unusable: clear the board and confirm.
    case needsEmptyBoard
    /// Calibration lost or missing: manual input until it is redone.
    case needsCalibration
    /// Camera refused, absent (Simulator) or taken by another foreground app.
    case unavailable
}

enum DartRetraction: Hashable, Sendable {
    /// The dart left the board without a hand in view: "Fléchette tombée : 0 ?".
    case fellOut
    /// The dart was pulled.
    case takeout
}

enum DartInputEvent: Sendable {
    case dart(DartProposal)
    /// An earlier dart moved when a new one landed: mark it "à vérifier".
    case dartDisturbed(id: UUID)
    case dartRemoved(id: UUID, reason: DartRetraction)
    /// Throw-like motion and nothing stuck: offer "Rebond ? Manqué".
    case possibleMiss
    /// The board is empty again: PROPOSES the end of the turn.
    case boardCleared
    case statusChanged(InputStatus)
    /// One-line advice for the player (localised by the source).
    case advisory(LocalizedText)
}

/// Feedback for one camera dart when its turn is confirmed.
struct DartFeedback: Hashable, Sendable {
    var id: UUID
    var wasCorrected: Bool
}

/// An automatic provider of darts: the live camera, the manual-trigger scan, a scripted fake.
/// The play screen talks to this protocol only; it never sees `ScanSession`.
@MainActor
protocol DartInputSource: AnyObject {
    var status: InputStatus { get }
    /// A NEW stream per call; finishes when the source stops.
    func events() -> AsyncStream<DartInputEvent>

    // Commands. They are SYNCHRONOUS: the game never awaits the source and never starts a task per command.
    // The source forwards them to the vision layer strictly in the order of the calls (ARCHITECTURE.md §8.7, §11).

    /// A game starts or is resumed. `boardConfirmedEmpty`: the player confirmed that no dart is on the board.
    func gameStarted(boardConfirmedEmpty: Bool)
    /// A turn begins or is reopened (undo, correction, resumed game): `expectedDarts` darts may still come.
    func turnBegan(expectedDarts: Int)
    /// The rules closed the turn (third dart, bust, win): further darts are suspicious.
    func turnClosed()
    /// The player removed a phantom detection.
    func dartDiscarded(_ id: UUID)
    /// The player added by hand a dart that the source missed.
    func manualDartAdded()
    /// The turn was confirmed: one feedback per dart of this source. A dart is reported once: the source
    /// ignores an id it has already reported (a turn confirmed again after an undo).
    func turnConfirmed(_ feedback: [DartFeedback])
    /// The player states that the board is empty now (answer to `needsEmptyBoard`).
    func boardConfirmedEmpty()
    /// The play screen is left, the game being finished or not: the source stops watching.
    func gameEnded()

    // Queries: the only asynchronous calls.

    /// Magnified real image around a dart, for the correction screen; nil when the source has none.
    func evidenceImage(for id: UUID) async -> CGImage?
    /// The player moved the tip on the evidence image (`point` in nominal mm): the dart re-scored from there.
    func rescore(_ id: UUID, tip point: BoardPoint) async -> DartProposal?
}
```

#### 8.4.7 Partie en cours

Fichier `DartKit/Sources/DartUI/Play/PlayViewModel.swift` (lot U2 ; initialiseur écrit par F0 ; comportement normatif en §8.6) :

```swift
import Foundation
import CoreGraphics
import Observation
import DartCore
import DartAudio

/// Transient message of the play screen.
enum PlayPrompt: Hashable, Sendable {
    /// A dart arrived while the turn was complete: "Tour terminé, retirez les fléchettes".
    case dartIgnored
    /// "Rebond ? Manqué" shortcut, shown for a few seconds.
    case possibleMiss
    /// "Fléchette tombée : 0 ?" for dart `index` of the current turn.
    case dartFellOut(index: Int)
    /// Fewer than three darts: "Volée incomplète : passer au joueur suivant ?".
    case confirmShortTurn
    /// The camera saw an empty board: the next-player button is emphasised.
    case boardCleared
    case advisory(LocalizedText)
}

/// What the correction sheet edits.
enum CorrectionTarget: Hashable, Sendable, Identifiable {
    /// Dart `index` of the current turn, already in the journal.
    case recorded(index: Int)
    /// Head of the pending queue (not yet sent to the game).
    case pending(id: UUID)

    var id: String {
        switch self {
        case .recorded(let index): return "recorded-\(index)"
        case .pending(let id): return "pending-\(id.uuidString)"
        }
    }
}

/// The ONLY owner of a running game: applies darts, corrections and turn changes, feeds sound and persistence.
@MainActor
@Observable
final class PlayViewModel: Identifiable {
    nonisolated let id = UUID()
    /// The game. Views read `snapshot`; nothing else mutates the match.
    private(set) var match: GameMatch
    var snapshot: GameSnapshot { match.snapshot }
    /// Descriptor of the game: play template, `boardGeometry`, `confirmsShortTurn`.
    var descriptor: GameDescriptor { match.definition.descriptor }
    /// Journal records of the current turn, aligned with `snapshot.turn.darts` (review flag, origin, id).
    var turnRecords: [DartRecord] { match.currentTurn }
    /// Undecided darts, oldest first. While it is not empty, later darts queue behind it (VISION.md §7.4).
    private(set) var pending: [DartProposal] = []
    private(set) var inputStatus: InputStatus = .manualOnly
    var prompt: PlayPrompt?
    var correction: CorrectionTarget?

    private let source: (any DartInputSource)?
    private let sound: any SoundPlaying
    private let storage: AppStorage
    private let endsTurnOnTakeout: Bool

    /// Lot F0 writes this WORKING body (it only stores its parameters): `AppModel.startGame` (lot U1, wave 1)
    /// creates a PlayViewModel before lot U2 delivers the rest of this file. Lot U2 keeps the signature.
    /// `inputStatus` tells whether the game has a source: `.manualOnly` without one.
    init(match: GameMatch, source: (any DartInputSource)?, sound: any SoundPlaying,
         storage: AppStorage, endsTurnOnTakeout: Bool) {
        self.match = match
        self.source = source
        self.sound = sound
        self.storage = storage
        self.endsTurnOnTakeout = endsTurnOnTakeout
        self.inputStatus = source?.status ?? .manualOnly
    }

    /// Subscribes to the source, synchronises it with the phase of the match (new or resumed game), announces
    /// the player to throw. Call from `.task` of the play screen.
    func run(boardConfirmedEmpty: Bool) async { unimplemented() }
    /// Reaction to one event of the source (table "Événements de la source", §8.6). `run` calls it for every
    /// event of the stream, one at a time, on the main actor.
    func handle(_ event: DartInputEvent) { unimplemented() }

    // Darts
    /// Entry point for EVERY dart (camera, scan, photo, manual).
    func receive(_ proposal: DartProposal) { unimplemented() }
    /// Manual input: a tap on the virtual board.
    func tapBoard(_ tap: BoardTap) { unimplemented() }
    /// "Manqué" button and bounce-out shortcut.
    func addMiss() { unimplemented() }

    // Corrections (current turn only)
    /// Answers the head of `pending`: the chosen hit, or nil to discard the detection.
    func resolvePending(with hit: Hit?) { unimplemented() }
    /// Answers the head of `pending` with a point of the virtual board of the correction sheet: the hit AND the
    /// position under the finger are applied together (§8.6, "Écran de correction").
    func resolvePending(with tap: BoardTap) { unimplemented() }
    func correctDart(at index: Int, to hit: Hit, position: BoardPoint? = nil) { unimplemented() }
    func removeDart(at index: Int) { unimplemented() }
    /// Accepts a dart shown as "à vérifier" as it is.
    func confirmDart(at index: Int) { unimplemented() }
    func undo() { unimplemented() }

    // Turn
    /// False while `pending` is not empty or the game is finished.
    var canEndTurn: Bool { unimplemented() }
    /// "Fléchettes retirées, suivant": asks for a confirmation when the turn is short and the game wants one
    /// (`descriptor.confirmsShortTurn`), else calls `endTurn`.
    func requestEndTurn() { unimplemented() }
    func endTurn() { unimplemented() }
    /// The player answers the status `needsEmptyBoard`: the board is empty now (§8.7). The only call of
    /// `source.boardConfirmedEmpty()`: the next-player button never sends it.
    func confirmBoardEmpty() { unimplemented() }

    // End of the game
    var isFinished: Bool { unimplemented() }
    /// The results screen is left (`AppModel.closeGame` or `rematch`): reports the feedback of the last turn,
    /// tells the source that the game is over, deletes the saved game. Until then a finished game stays saved
    /// and correctable (`undo`, `correctDart`).
    func finishGame() { unimplemented() }
    /// The play screen is left before the end of the game: tells the source to stop watching; the saved game is kept.
    func suspend() { unimplemented() }
    /// Same players, same options, new seed.
    func rematchConfiguration(seed: UInt64) -> GameConfiguration { unimplemented() }

    // Queries of the correction sheet and of the camera screens (the source stays private)
    /// Magnified real image around a dart of the source; nil without a source or without an image.
    func evidenceImage(for id: UUID) async -> CGImage? { unimplemented() }
    /// The dart re-scored from a tip moved on the evidence image; nil without a source.
    func rescore(_ id: UUID, tip point: BoardPoint) async -> DartProposal? { unimplemented() }
    /// True when the game has an automatic source (camera or scan): the scan pill and the live view exist.
    var hasSource: Bool { unimplemented() }
}
```

Ce que l'initialiseur écrit par F0 garantit, de F0 à la livraison de U2 : `PlayViewModel(match:source:sound:storage:endsTurnOnTakeout:)` ne plante pas, et `snapshot`, `descriptor`, `turnRecords`, `pending`, `inputStatus`, `prompt` et `correction` répondent. `AppModel.startGame` et `resumeSavedGame` (lot U1, vague 1) s'exécutent donc, et `app.game` peut être présenté : `PlayScreen` s'affiche vide (§8.4.10). Tout le reste (`run`, `receive`, les corrections, `endTurn`, `isFinished`, `finishGame`, `suspend`) plante jusqu'à U2 : le lot U1 n'appelle donc ni `closeGame` ni `rematch` dans ses tests, et c'est le lot U2 qui les éprouve (§12.1).

#### 8.4.8 Caméra

La façade caméra tient en deux fichiers du squelette, écrits pour que la racine de l'application ne dépende pas du lot U3. `AppModel` (lot U1, vague 1) garde un `CameraModel` et `AppEnvironment` fournit un `ScanServicing` : si ces types plantaient jusqu'à la vague 3, ni le lot U1 ni le lot U2 ne pourraient exécuter leur code.

| Fichier | Contenu | État dans le squelette F0 | Propriétaire |
|---|---|---|---|
| `Camera/ScanServicing.swift` | `PreviewContent`, `CameraIssue`, `ScanServicing`, `ScanServiceError`, `FakeScanService` | **complet** : aucun corps à écrire | U1, figé |
| `Camera/CameraModel.swift` | `CameraModel`, `ScanServiceFactory` | corps **minimal qui fonctionne** : pas de caméra, rien ne plante | U3, qui le reprend en vague 3 ; personne d'autre ne le modifie |
| `Camera/LiveScanService.swift`, `Camera/CameraInputSource.swift`, `Camera/DartProposal+Observation.swift`, `Camera/CaptureInterruptionObserver.swift` | le vrai service, l'adaptateur vers `DartInputSource`, la conversion d'une observation, la cause d'une interruption | **absents** : créés par U3 | U3 |

Fichier `DartKit/Sources/DartUI/Camera/ScanServicing.swift` (complet ; comportement du vrai service en §8.7) :

```swift
import Foundation
import CoreGraphics
import DartCore
import DartVision
#if canImport(AVFoundation)
import AVFoundation
#endif

/// What a preview view can show.
enum PreviewContent: @unchecked Sendable {
    #if canImport(AVFoundation)
    /// Live capture session (iOS: `AVCaptureVideoPreviewLayer`).
    case captureSession(AVCaptureSession)
    #endif
    /// A still or a synthetic frame (Simulator, macOS, SnapshotTool).
    case image(CGImage)
    case none
}

/// Why the camera cannot deliver frames.
enum CameraIssue: Hashable, Sendable {
    case accessDenied
    /// Simulator or device without a back camera.
    case noCamera
    /// iPad multitasking: the camera only runs when the app fills the screen.
    case notFullScreen
    case systemPressure
    case failed(String)
}

/// The camera-side seam of DartUI: a thin main-actor facade over `ScanSession` (VISION.md §9.2, section 8).
/// Calibration, live scan and photo mode talk to this protocol; tests, previews and SnapshotTool use `FakeScanService`.
@MainActor
protocol ScanServicing: AnyObject {
    /// Stable identifier of the frame source ("back-wide", "synthetic"): part of the calibration key.
    var cameraID: String { get }
    var frameInfo: FrameSourceInfo? { get }
    var preview: PreviewContent { get }
    var issue: CameraIssue? { get }
    /// A NEW stream per call.
    func events() -> AsyncStream<ScanEvent>

    /// Asks for camera access if needed, starts the source and the session. Throws `ScanServiceError`.
    func start() async throws
    func stop() async
    /// Mean of the next `frames` frames at full resolution (`ScanSession.captureStill(averaging:)`):
    /// 8 for the frozen still of the calibration screen (device on its stand), 1 for a hand-held photo,
    /// which averaging would blur (VISION.md §8.2). Throws `ScanServiceError`.
    func captureStill(averaging frames: Int) async throws -> RGBImage
    func setCalibration(_ calibration: BoardCalibration) async
    func updateConfiguration(_ configuration: VisionConfiguration) async
    func send(_ command: ScanCommand) async
    func correct(_ id: UUID, tip: BoardPoint) async -> DartObservation?
    func recordFeedback(_ id: UUID, wasCorrected: Bool) async
    func evidenceCrop(for id: UUID) async -> CGImage?
    func runLightingCheck(confirmedTip: BoardPoint) async -> LightingCheckResult?
    func currentState() async -> ScanState
}

struct ScanServiceError: Error, Hashable, Sendable {
    var issue: CameraIssue
}

/// Scripted service, COMPLETE from lot F0 on: it emits the events it is given and records what it receives.
/// `FakeScanService(issue: .noCamera)` is the service of previews, of tests, and of the real application until
/// lot U3 delivers `LiveScanService` (see `ScanServiceFactory`).
@MainActor
final class FakeScanService: ScanServicing {
    // MARK: Script (set by the test)

    /// Still returned by `captureStill`; nil makes it throw.
    var still: RGBImage?
    /// When set, `start()` and `captureStill` throw it.
    var issue: CameraIssue?
    /// Value of `currentState()`; `emit(.stateChanged(_))` updates it.
    var state: ScanState = .needsCalibration
    /// Value returned by `correct(_:tip:)`.
    var correctionResult: DartObservation?
    /// Value returned by `evidenceCrop(for:)`.
    var evidence: CGImage?
    /// Value returned by `runLightingCheck(confirmedTip:)`.
    var lightingCheckResult: LightingCheckResult?

    // MARK: Record (read by the test)

    /// Every command received by `send`, in order.
    private(set) var commands: [ScanCommand] = []
    private(set) var isRunning = false
    /// The `frames` argument of every `captureStill(averaging:)` call.
    private(set) var stillRequests: [Int] = []
    private(set) var calibrations: [BoardCalibration] = []
    private(set) var configurations: [VisionConfiguration] = []
    private(set) var feedback: [(id: UUID, wasCorrected: Bool)] = []
    private(set) var corrections: [(id: UUID, tip: BoardPoint)] = []

    private var continuations: [UUID: AsyncStream<ScanEvent>.Continuation] = [:]

    init(still: RGBImage? = nil, issue: CameraIssue? = nil) {
        self.still = still
        self.issue = issue
    }

    /// Pushes an event to every open stream.
    func emit(_ event: ScanEvent) {
        if case .stateChanged(let newState) = event { state = newState }
        for continuation in continuations.values { continuation.yield(event) }
    }

    var cameraID: String { "fake" }

    var frameInfo: FrameSourceInfo? {
        guard isRunning, let still else { return nil }
        return FrameSourceInfo(size: PixelSize(width: still.width, height: still.height), nominalFramesPerSecond: 30,
                               rotationDegrees: 0, intrinsics: nil, isLive: false)
    }

    var preview: PreviewContent { .none }

    func events() -> AsyncStream<ScanEvent> {
        let id = UUID()
        let (stream, continuation) = AsyncStream.makeStream(of: ScanEvent.self)
        continuations[id] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { @MainActor in self?.continuations[id] = nil }
        }
        return stream
    }

    func start() async throws {
        if let issue { throw ScanServiceError(issue: issue) }
        isRunning = true
    }

    func stop() async {
        isRunning = false
        for continuation in continuations.values { continuation.finish() }
        continuations = [:]
    }

    func captureStill(averaging frames: Int) async throws -> RGBImage {
        stillRequests.append(frames)
        if let issue { throw ScanServiceError(issue: issue) }
        guard let still else { throw ScanServiceError(issue: .noCamera) }
        return still
    }

    func setCalibration(_ calibration: BoardCalibration) async { calibrations.append(calibration) }
    func updateConfiguration(_ configuration: VisionConfiguration) async { configurations.append(configuration) }
    func send(_ command: ScanCommand) async { commands.append(command) }

    func correct(_ id: UUID, tip: BoardPoint) async -> DartObservation? {
        corrections.append((id, tip))
        return correctionResult
    }

    func recordFeedback(_ id: UUID, wasCorrected: Bool) async { feedback.append((id, wasCorrected)) }
    func evidenceCrop(for id: UUID) async -> CGImage? { evidence }
    func runLightingCheck(confirmedTip: BoardPoint) async -> LightingCheckResult? { lightingCheckResult }
    func currentState() async -> ScanState { state }
}
```

Fichier `DartKit/Sources/DartUI/Camera/CameraModel.swift` (corps minimal écrit par F0 ; le lot U3 remplace les corps sans changer une signature) :

```swift
import Foundation
import Observation
import DartCore
import DartVision

/// State of the camera shared by the home card, the calibration screen, the live scan and the photo mode.
/// Lot F0 writes the WORKING minimal bodies below: no camera, nothing traps, every game plays by manual input.
/// Lot U3 owns this file and replaces the bodies in wave 3; no other lot edits it. Signatures are frozen.
@MainActor
@Observable
final class CameraModel {
    enum Readiness: Hashable, Sendable {
        /// Never asked, or not started yet.
        case unknown
        case unavailable(CameraIssue)
        /// Frames arrive, no valid calibration.
        case needsCalibration
        /// Calibrated; `grade` is shown on the home card.
        case ready(grade: CalibrationQuality.Grade)
    }

    let service: any ScanServicing
    private let storage: AppStorage
    private(set) var readiness: Readiness = .unknown
    private(set) var calibration: BoardCalibration?
    private(set) var scanState: ScanState = .needsCalibration
    private(set) var lightingCheckPassed = false

    init(service: any ScanServicing, storage: AppStorage) {
        self.service = service
        self.storage = storage
    }

    /// Starts the service and, when a calibration is stored for this camera, revalidates it on a fresh still
    /// (`assess`, then `recover`) and installs it in the service: VISION.md §4.10. Idempotent: does nothing when
    /// the service already runs, and a call made while another one is running waits for the same result.
    /// Minimal body: does nothing, `readiness` stays `.unknown`.
    func activate() async {}

    /// Stops the session when the camera is no longer needed (ARCHITECTURE.md §8.7, "Cycle de vie").
    /// Minimal body: does nothing.
    func deactivate() async {}

    /// The ONLY way a `ScanCommand` goes from DartUI to the vision layer: every `CameraInputSource`, the photo
    /// mode, the calibration flow and `setForeground` deposit here, and ONE task of this model awaits
    /// `service.send(_:)` for each command before taking the next. The vision layer therefore receives the
    /// commands in the exact order of the calls, whoever makes them (ARCHITECTURE.md §8.7, §11).
    /// Synchronous: the caller never waits. Minimal body: does nothing.
    func enqueue(_ command: ScanCommand) {}

    /// Same queue, same order: `service.recordFeedback(id, wasCorrected:)`. Minimal body: does nothing.
    func enqueueFeedback(_ id: UUID, wasCorrected: Bool) {}

    /// Scene phase (`AppModel.setForeground`): deposits `.pause(.background)` when the app leaves the foreground
    /// and `.resume` when it comes back, with `enqueue`. Minimal body: does nothing.
    func setForeground(_ active: Bool) {}

    /// Saves and installs a calibration validated by the player. Minimal body: kept in memory only.
    func adopt(_ calibration: BoardCalibration, lightingCheckPassed: Bool) async {
        self.calibration = calibration
        self.lightingCheckPassed = lightingCheckPassed
    }

    func forgetCalibration() {
        calibration = nil
        lightingCheckPassed = false
    }

    /// The automatic dart source for a game, for the given mode (`.live`: automatic trigger; `.photo`: manual
    /// trigger). Returns a source as soon as the camera is not known to be unavailable (`service.issue == nil`),
    /// WHATEVER `readiness`: after a cold start `readiness` is still `.unknown` when the game is created, and
    /// the play screen awaits `activate()` before the game starts (ARCHITECTURE.md §8.6, step 0). Without a
    /// valid calibration the source reports `.needsCalibration`. Nil only when `service.issue != nil`.
    /// Minimal body: always nil, so the game is played by manual input.
    func makeInputSource(mode: ScanMode) -> (any DartInputSource)? { nil }
}

/// Where the real application gets its scan service. `AppEnvironment.live()` calls it and never names a
/// concrete type, so that lot U1 does not wait for lot U3.
enum ScanServiceFactory {
    /// Lot F0: the fake without a camera. Lot U3 changes this single line to `LiveScanService()`.
    @MainActor static func live() -> any ScanServicing { FakeScanService(issue: .noCamera) }
}
```

Ce que le corps minimal garantit, de F0 à la livraison de U3 :

- *Revue finale, membre ajouté par le lot U3 :* `private(set) weak var inputSource: CameraInputSource?`, la dernière source rendue par `makeInputSource(mode:)` tant que sa partie la garde. Le mode photo y lit les seuils de la partie (§8.7). Aucune signature imprimée ne change.
- `CameraModel(service:storage:)` ne plante pas ; `readiness` vaut `.unknown` ; `activate()`, `deactivate()`, `enqueue(_:)`, `enqueueFeedback(_:wasCorrected:)` et `setForeground(_:)` ne font rien ; `makeInputSource(mode:)` rend `nil`. L'application démarre, la carte caméra de l'accueil affiche « saisie manuelle », et toute partie se joue au doigt.
- `AppEnvironment.live()` appelle `ScanServiceFactory.live()` et ne nomme aucun type concret. Dans le squelette, cette fonction rend `FakeScanService(issue: .noCamera)` ; le lot U3 la fait rendre `LiveScanService()`. Le lot U1 n'a donc jamais à rouvrir `AppModel.swift` pour la caméra. `AppEnvironment.preview()` utilise toujours `FakeScanService(issue: .noCamera)`.
- `FakeScanService` enregistre tout ce qu'il reçoit (`commands`, `stillRequests`, `calibrations`, `configurations`, `feedback`, `corrections`) et pousse à tous les flux ouverts les événements qu'on lui donne (`emit`). C'est le service de tous les tests de `DartUI`, des aperçus et de `SnapshotTool`. Il n'appelle que des membres de simple donnée de `DartVision` (§6.4) : il fonctionne avant toute livraison de la vision.
- Ce qu'il enregistre se compare par `==` : `ScanCommand`, `BoardCalibration` et `VisionConfiguration` sont `Hashable` (`VISION.md` §9.2). Un test écrit donc `service.commands == [.setTrigger(.automatic), .arm(boardConfirmedEmpty: true)]`, sans filtrage cas par cas et sans ajouter de conformité (§13.4). `feedback` et `corrections` sont des listes de couples : un test en compare les éléments (`service.feedback.map(\.id)`).
- `captureStill(averaging:)` prend le nombre d'images à moyenner : 8 pour l'image figée du calibrage, appareil sur son support ; 1 pour une photo prise à main levée, que la moyenne rendrait floue (`VISION.md` §8.2).

Signatures du lot U3 (ces types ne font pas partie du squelette F0 ; le lot U3 crée leurs fichiers en vague 3, avec exactement ces signatures) :

```swift
// Types written by lot U3 in wave 3, in the files named below. They are NOT in the F0 skeleton, and nothing
// outside lot U3 names them: the rest of DartUI only sees `ScanServicing`, `DartInputSource` and `CameraModel`.
import Foundation
import CoreGraphics
import DartCore
import DartVision

/// `Camera/LiveScanService.swift`. Real service over `ScanSession`: `CameraFrameSource` on a device, a looping
/// synthetic demonstration source (`CameraDemoFrameSource`) without a back camera (Simulator).
/// `ScanServiceFactory.live()` returns it once it exists.
@MainActor
final class LiveScanService: ScanServicing {
    init(configuration: VisionConfiguration = VisionConfiguration()) { unimplemented() }
    var cameraID: String { unimplemented() }
    var frameInfo: FrameSourceInfo? { unimplemented() }
    var preview: PreviewContent { unimplemented() }
    var issue: CameraIssue? { unimplemented() }
    func events() -> AsyncStream<ScanEvent> { unimplemented() }
    func start() async throws { unimplemented() }
    func stop() async { unimplemented() }
    func captureStill(averaging frames: Int) async throws -> RGBImage { unimplemented() }
    func setCalibration(_ calibration: BoardCalibration) async { unimplemented() }
    func updateConfiguration(_ configuration: VisionConfiguration) async { unimplemented() }
    func send(_ command: ScanCommand) async { unimplemented() }
    func correct(_ id: UUID, tip: BoardPoint) async -> DartObservation? { unimplemented() }
    func recordFeedback(_ id: UUID, wasCorrected: Bool) async { unimplemented() }
    func evidenceCrop(for id: UUID) async -> CGImage? { unimplemented() }
    func runLightingCheck(confirmedTip: BoardPoint) async -> LightingCheckResult? { unimplemented() }
    func currentState() async -> ScanState { unimplemented() }
}

/// `Camera/CameraInputSource.swift`. Adapts the scan service of a `CameraModel` to `DartInputSource` by the two
/// tables of ARCHITECTURE.md §8.7. `mode` fixes the trigger: `.live` = automatic, `.photo` = manual.
/// Reads `camera.service.events()`. Deposits every command with `camera.enqueue(_:)` and every feedback with
/// `camera.enqueueFeedback(_:wasCorrected:)`: it never calls `service.send` itself and owns no queue.
/// Created by `CameraModel.makeInputSource(mode:)`.
@MainActor
final class CameraInputSource: DartInputSource {
    init(camera: CameraModel, mode: ScanMode, thresholds: ConfidenceThresholds = .standard) { unimplemented() }
    var status: InputStatus { unimplemented() }
    func events() -> AsyncStream<DartInputEvent> { unimplemented() }
    func gameStarted(boardConfirmedEmpty: Bool) { unimplemented() }
    func turnBegan(expectedDarts: Int) { unimplemented() }
    func turnClosed() { unimplemented() }
    func dartDiscarded(_ id: UUID) { unimplemented() }
    func manualDartAdded() { unimplemented() }
    func turnConfirmed(_ feedback: [DartFeedback]) { unimplemented() }
    func boardConfirmedEmpty() { unimplemented() }
    func gameEnded() { unimplemented() }
    func evidenceImage(for id: UUID) async -> CGImage? { unimplemented() }
    func rescore(_ id: UUID, tip point: BoardPoint) async -> DartProposal? { unimplemented() }
}

/// `Camera/DartProposal+Observation.swift`.
extension DartProposal {
    /// A dart seen by DartVision. `hit` is `observation.best`, `position` its tip, `choices` its
    /// `correctionChoices()`; `origin` follows `observation.source` (liveCamera → camera, scan → scan,
    /// handheldPhoto and tappedOnPhoto → photo). Certainty: high → certain, medium → needsReview, low → undecided,
    /// on `observation.tier(collapsingBy: { match.effectKey(for: $0, position: observation.tip) }, thresholds: thresholds)`.
    /// In a game whose descriptor has `dependsOnPosition`, a `certain` dart is lowered to `needsReview` when
    /// `match.effectKey(for: observation.best, position: p)` differs from the key at the tip for one of the four
    /// points `p = tip ± sigmaAlong · axis` and `p = tip ± sigmaAcross · normal` of `observation.uncertainty`
    /// (normal = (-axis.y, axis.x)). Not applied to a `tappedOnPhoto` observation: the player placed that tip.
    init(observation: DartObservation, thresholds: ConfidenceThresholds) { unimplemented() }
}

/// `Camera/CaptureInterruptionObserver.swift`: the third and last file of DartUI allowed to contain `#if os(iOS)`
/// (`AVCaptureSession.InterruptionReason` does not exist on macOS).
enum CaptureInterruptionObserver {
    /// Cause of an `AVCaptureSession.wasInterruptedNotification`, read from its user info.
    /// iOS: `videoDeviceNotAvailableWithMultipleForegroundApps` → `.notFullScreen`,
    /// `videoDeviceNotAvailableDueToSystemPressure` → `.systemPressure`, any other reason → `.failed(reason)`.
    /// Other platforms: always `.failed`.
    static func issue(for notification: Notification) -> CameraIssue { unimplemented() }
}
```

#### 8.4.9 Racine

Fichier `DartKit/Sources/DartUI/App/AppModel.swift` (lot U1) :

```swift
import SwiftUI
import Observation
import DartCore
import DartGames
import DartAudio
import DartVision

/// Everything DartUI takes from outside. `live()` for the app, `preview()` for tests, previews and SnapshotTool.
@MainActor
public struct AppEnvironment {
    public var registry: GameRegistry
    public var sound: any SoundPlaying
    public var store: any KeyValueStoring
    /// Seed of a new game (GAMES.md §2.8). The only use of the system random generator in the application.
    public var makeSeed: @Sendable () -> UInt64
    /// Start date of a new game (`MatchRecord.startedAt`). `AppModel` passes `now()` to
    /// `GameMatch(definition:configuration:startedAt:)` and never relies on the default `Date()` of DartCore.
    public var now: @Sendable () -> Date
    var scanService: any ScanServicing

    /// Real services: `GameRegistry.standard`, `AudioDirector`, `UserDefaultsStore`, `ScanServiceFactory.live()`;
    /// `now` is the system clock (`Date()`).
    public static func live() -> AppEnvironment { unimplemented() }
    /// Silent, in-memory, `FakeScanService(issue: .noCamera)`. Deterministic: `makeSeed` always returns 1 and
    /// `now` always returns `Date(timeIntervalSinceReferenceDate: 0)`, so a test game has the same record every run.
    public static func preview(registry: GameRegistry = .standard) -> AppEnvironment { unimplemented() }
}

/// Root view of the application: the only symbol the app shell uses.
public struct DartScannerRootView: View {
    public init(environment: AppEnvironment) { unimplemented() }
    @MainActor public init() { unimplemented() }
    public var body: some View { StubView() }
}

/// Destinations pushed on the root `NavigationStack`.
enum AppRoute: Hashable {
    /// Players and options of a game.
    case setup(GameID)
    case settings
    /// Roster management.
    case players
    case placementGuide
}

/// Full-screen camera flows presented over the home screen.
enum CameraFlow: String, Identifiable {
    case calibration
    var id: String { rawValue }
}

/// Root state: settings, roster, navigation, the running game.
@MainActor
@Observable
final class AppModel {
    let environment: AppEnvironment
    let storage: AppStorage
    let camera: CameraModel
    /// Persisted and pushed to the sound service on every change.
    var settings: AppSettings
    var roster: [Player]
    var path: [AppRoute] = []
    /// The running game, presented with `gameCover(item:)`.
    var game: PlayViewModel?
    var cameraFlow: CameraFlow?
    /// A saved game exists and can be resumed from the home screen. A game saved in phase `finished` (the app
    /// was closed on the results screen) is resumable too: it reopens straight on its results.
    private(set) var resumableMatch: MatchRecord?

    var language: AppLanguage { unimplemented() }

    init(environment: AppEnvironment) { unimplemented() }

    /// Creates the match (seed from `environment.makeSeed()`, start date from `environment.now()`), the input
    /// source for the current input mode, and presents the play screen. Throws `GameConfigurationError`
    /// (`.unknownGame` when the registry has no such game).
    func startGame(_ game: GameID, players: [Player], options: GameOptions) throws { unimplemented() }
    /// Rebuilds `resumableMatch` with `registry.restoreMatch` (its saved start date is kept) and presents it,
    /// whatever its phase.
    func resumeSavedGame() { unimplemented() }
    /// Same players and options, new seed and new start date, created as in `startGame`.
    /// Calls `game.finishGame()` on the game that ends.
    func rematch() { unimplemented() }
    /// Closes the play screen. Finished game: `game.finishGame()`. Unfinished game: `game.suspend()`, and
    /// `discard` also deletes the saved game.
    func closeGame(discard: Bool) { unimplemented() }
    /// Scene phase changes: `sound.setActive(active)` and `camera.setForeground(active)`.
    func setForeground(_ active: Bool) { unimplemented() }
}
```

#### 8.4.10 Points d'entrée des écrans

F0 crée un fichier par vue d'entrée, sur ce modèle : l'initialiseur ne range rien et **ne plante pas**, le corps rend `StubView()`. Une vue d'un autre lot présentée avant sa livraison s'affiche donc vide, au lieu d'arrêter l'application. Le lot propriétaire la remplit sans changer la signature de l'initialiseur.

```swift
import SwiftUI
import DartCore

/// Players and options of one game, driven by its `GameDescriptor`.
struct SetupScreen: View {
    init(game: GameID) {}
    var body: some View { StubView() }
}
```

Deux cas du plan en dépendent : la racine du lot U1 (vague 1) construit `HomeScreen()`, `SetupScreen(game:)`, `PlayScreen(game:)` et `PlacementGuideView()`, des lots U2 et U3 ; `PlayScreen`, du lot U2 (vague 2), présente `PhotoModeView`, `LiveScanView` et `ScanThumbnail`, du lot U3 (vague 3). Chacun de ces lots peut ainsi exécuter son écran dans le Simulateur et sous `SnapshotTool` sans attendre l'autre.

Les corps `{ unimplemented() }` des listings imprimés de `DartUI` restent, eux, tels quels : pendant une vague, chacun n'est appelé que par le lot qui l'écrit ou par un lot d'une vague ultérieure. Les deux endroits où ce n'était pas vrai sont écrits pour de bon dès F0 : l'initialiseur de `PlayViewModel` (§8.4.7) et `CameraModel` (§8.4.8). Un seul appel croise encore deux lots d'une même vague : `AppEnvironment.live()` (lot U1) crée `AudioDirector` (lot A1). Les tests du lot U1 passent donc par `AppEnvironment.preview()`, dont les services sont ceux du lot U1 lui-même ou sont complets dès F0 (`SilentSoundPlayer`, `FakeScanService`) ; `live()` n'est exécuté qu'une fois A1 livré.

| Vue | Initialiseur | Fichier | Lot |
|---|---|---|---|
| `HomeScreen` | `init()` | `Home/HomeScreen.swift` | U2 |
| `SetupScreen` | `init(game: GameID)` | `Setup/SetupScreen.swift` | U2 |
| `PlayersScreen` | `init()` | `Players/PlayersScreen.swift` | U2 |
| `SettingsScreen` | `init()` | `Settings/SettingsScreen.swift` | U2 |
| `PlayScreen` | `init(game: PlayViewModel)` | `Play/PlayScreen.swift` | U2 |
| `CorrectionSheet` | `init(game: PlayViewModel, target: CorrectionTarget)` | `Play/CorrectionSheet.swift` | U2 |
| `CalibrationFlowView` | `init(camera: CameraModel, onFinish: @escaping () -> Void)` | `Calibration/CalibrationFlowView.swift` | U3 |
| `PlacementGuideView` | `init()` | `Camera/PlacementGuideView.swift` | U3 |
| `LiveScanView` | `init(game: PlayViewModel, camera: CameraModel)` | `Scan/LiveScanView.swift` | U3 |
| `ScanThumbnail` | `init(camera: CameraModel, onExpand: @escaping () -> Void)` | `Scan/ScanThumbnail.swift` | U3 |
| `PhotoModeView` | `init(game: PlayViewModel, camera: CameraModel)` | `Photo/PhotoModeView.swift` | U3 |

Les vues lisent `AppModel` dans l'environnement : `@Environment(AppModel.self) private var app`.

Fichiers d'instantanés, un par lot. F0 crée ceux des lots U2 et U3 avec une liste vide, et celui du lot U1 avec un seul écran d'essai, `skeleton`, pour que `SnapshotTool` écrive un PNG dès la fondation :

Fichier `DartKit/Sources/DartUI/Snapshots/SnapshotCatalog.swift` (lot U1 ; `framed` est complet) :

```swift
import SwiftUI
import DartCore

/// Canvas sizes used by SnapshotTool, in points.
public enum SnapshotDevice: String, CaseIterable, Sendable {
    case phonePortrait, phoneLandscape, padPortrait, padLandscape

    public var size: CGSize {
        switch self {
        case .phonePortrait: return CGSize(width: 393, height: 852)
        case .phoneLandscape: return CGSize(width: 852, height: 393)
        case .padPortrait: return CGSize(width: 834, height: 1194)
        case .padLandscape: return CGSize(width: 1194, height: 834)
        }
    }
}

/// One screen that SnapshotTool renders: a pure-SwiftUI content view fed with fixture data.
public struct SnapshotScreen: Identifiable {
    /// File name stem: "home", "play-killer", "calibration".
    public let id: String
    public let devices: [SnapshotDevice]
    public let make: @MainActor (SnapshotDevice) -> AnyView

    public init(id: String, devices: [SnapshotDevice] = [.phonePortrait], make: @escaping @MainActor (SnapshotDevice) -> AnyView) {
        self.id = id
        self.devices = devices
        self.make = make
    }
}

public enum SnapshotCatalog {
    /// Every screen, in the order of ARCHITECTURE.md §8.11: kernel, then game flow, then camera flow.
    @MainActor public static var all: [SnapshotScreen] {
        kernelScreens + gameFlowScreens + cameraFlowScreens
    }

    /// Wraps a view the way the app does: size, dark theme, language, background.
    @MainActor public static func framed(_ view: AnyView, device: SnapshotDevice, language: AppLanguage) -> AnyView {
        AnyView(
            view
                .frame(width: device.size.width, height: device.size.height)
                .background(Theme.Palette.background)
                .foregroundStyle(Theme.Palette.textPrimary)
                .environment(\.horizontalSizeClass, device == .padPortrait || device == .padLandscape ? .regular : .compact)
                .environment(\.colorScheme, .dark)
                .appLanguage(language)
        )
    }
}
```

Fichier `DartKit/Sources/DartUI/Snapshots/KernelSnapshots.swift` (lot U1 ; l'écran `skeleton` est écrit par F0, et le lot U1 le remplace par les siens) :

```swift
import SwiftUI
import DartCore

extension SnapshotCatalog {
    /// Lot U1: "board-plain", "board-zones", "board-discs", "components".
    /// Lot F0 delivers this list with ONE screen, "skeleton", so that SnapshotTool writes a PNG in both languages
    /// from the first day: a `LocalizedText`, a string of the `Common` table and two entry views of other lots,
    /// which render empty. Lot U1 replaces it with its own screens.
    @MainActor static var kernelScreens: [SnapshotScreen] {
        [SnapshotScreen(id: "skeleton") { _ in
            AnyView(VStack(spacing: Theme.Spacing.section) {
                LocalizedTextView(LocalizedText(fr: "Squelette", en: "Skeleton"))
                    .font(Theme.Typography.screenTitle)
                L10n.text("common.ok", .common)
                    .font(Theme.Typography.button)
                    .foregroundStyle(Theme.Palette.accent)
                HomeScreen()
                SetupScreen(game: .killer)
            })
        }]
    }
}
```

- `GameFlowSnapshots.swift` (lot U2) et `CameraFlowSnapshots.swift` (lot U3) ont la forme la plus simple, avec une liste vide : `extension SnapshotCatalog { @MainActor static var gameFlowScreens: [SnapshotScreen] { [] } }`, et de même `cameraFlowScreens`.
- L'écran `skeleton` n'emploie que ce qui est complet dès F0 (`LocalizedTextView`, `L10n.text`, le thème) et deux vues d'entrée d'autres lots, qui s'affichent vides. Sur le squelette, `swift run SnapshotTool` écrit donc `fr/skeleton@phonePortrait.png` et `en/skeleton@phonePortrait.png` sans appeler aucun corps `unimplemented()`. La clé `"common.ok"` est celle que F0 met dans `Common.strings` (§8.9). Cet écran n'est pas un écran de l'application : le lot U1 DOIT le supprimer en vague 1, en livrant ses quatre instantanés (il peut alors renommer la clé) : dès la vague 2, `HomeScreen` et `SetupScreen` lisent `AppModel` dans l'environnement et planteraient sous `ImageRenderer`, dans `SnapshotTool` comme dans le test du lot U1 qui rend chaque écran du catalogue, et le lot U2 ne possède pas ce fichier pour le corriger.

### 8.5 Navigation et écran de préparation

```
DartScannerRootView                       .environment(app)  .appLanguage(app.language)
│                                         .preferredColorScheme(.dark)  .tint(Theme.Palette.accent)
└─ NavigationStack(path: $app.path)
   ├─ HomeScreen                                    racine
   ├─ AppRoute.setup(game)      → SetupScreen(game:)
   ├─ AppRoute.players          → PlayersScreen()
   ├─ AppRoute.settings         → SettingsScreen()
   └─ AppRoute.placementGuide   → PlacementGuideView()
   .gameCover(item: $app.game)        → PlayScreen(game:)
   │     ├─ .sheet(item: $game.correction)  → CorrectionSheet(game:target:)
   │     ├─ couverture interne « Photo »    → PhotoModeView(game:camera:)   action toujours présente (§8.6)
   │     ├─ couverture interne « Scan »     → LiveScanView(game:camera:)    quand la partie a une source (§8.6)
   │     └─ ResultsContent                  quand `snapshot.phase == .finished`
   └─ .gameCover(item: $app.cameraFlow) → CalibrationFlowView(camera:onFinish:)
```

- `NavigationStack` à la racine sur iPhone comme sur iPad. Pas de `NavigationSplitView`.
- La racine observe `scenePhase` et appelle `app.setForeground(_:)`.
- **Accueil piloté par les données** : la grille vient de `environment.registry.descriptors` (`shortName`, `summary`), en `LazyVGrid` avec `GridItem(.adaptive(minimum: 160))`, dans une coquille qui défile. Aucun nom de jeu n'est écrit dans `DartUI`. Elle affiche les **quatorze** cartes du registre, dans l'ordre du registre (§5.2) ; la maquette `Main` en montre dix, et ne fait foi que pour le dessin d'une carte (`DESIGN.md` §4).
- **Carte caméra de l'accueil** : elle lit `app.camera.readiness`. Pour que cet état soit le vrai dès le lancement, `HomeScreen` appelle `app.camera.activate()` à son apparition quand `settings.inputMode == .camera`, et de nouveau quand la bascule passe sur « Scan caméra » ; il appelle `app.camera.deactivate()` quand elle repasse sur « Saisie manuelle » (§8.7, « Cycle de vie »). `.ready(grade)` : « Cible calibrée » et la qualité ; `.needsCalibration` : bouton « Calibrer », qui ouvre `app.cameraFlow = .calibration` ; `.unavailable` et `.unknown` : caméra indisponible, saisie manuelle. Avec le corps minimal de `CameraModel` (avant le lot U3), ces appels ne font rien et `readiness` reste `.unknown`.
- **Partie pilotée par les données** : `PlayScreen` choisit son gabarit par `descriptor.playStyle`, la géométrie de la cible par `descriptor.boardGeometry` (§8.4.3) et la confirmation d'une volée courte par `descriptor.confirmsShortTurn` (§8.6). Il ne teste jamais l'identifiant du jeu.
- **Préparation pilotée par les données** : `SetupScreen` dessine le descripteur, sans connaître le jeu, d'après la table ci-dessous. Les options `isAdvanced` sont repliées sous « Plus d'options ». Le nombre de joueurs, les choix grisés et le bouton « Lancer la partie » suivent les règles de §4.4. Les derniers choix sont relus et enregistrés par `AppStorage.loadSetup(for:)` et `save(_:for:)`.
- **Lancement** : `try app.startGame(game, players:, options:)`. `AppModel` tire la graine avec `environment.makeSeed()`, crée le `GameMatch` par `GameMatch(definition:configuration:startedAt: environment.now())`, la définition venant de `environment.registry.definition(for: game)` (absente : `GameConfigurationError.unknownGame(game)`), demande une source à `camera.makeInputSource(mode: settings.scanMode)` si `settings.inputMode == .camera` (sinon `nil`), crée le `PlayViewModel` et le présente. `makeInputSource` rend une source dès que la caméra n'est pas connue comme indisponible (`service.issue == nil`), **quel que soit `readiness`** : après un lancement à froid `readiness` vaut encore `.unknown` au moment où la partie est créée, et c'est `PlayScreen` qui attend `camera.activate()` avant de démarrer la partie (§8.6, étape 0). Sans calibrage valide, la source publie `.needsCalibration` (§8.7). Une source `nil` (saisie manuelle, caméra indisponible, ou lot U3 pas encore livré) donne une partie jouée au doigt, avec l'action « Photo » toujours disponible. `resumeSavedGame()` et `rematch()` obtiennent leur source de la même façon.
- **Date de début** : `rematch()` crée sa partie comme `startGame`, avec une graine et une date neuves ; `resumeSavedGame()` garde la date enregistrée (`registry.restoreMatch`). Dans `DartUI`, une partie neuve n'est donc jamais créée avec la valeur par défaut `Date()` de `GameMatch.init`, ni par `registry.makeMatch(_:)`, qui s'en sert (§4.8). Avec `AppEnvironment.preview()`, dont la graine vaut 1 et la date `Date(timeIntervalSinceReferenceDate: 0)` (§8.4.9), `game.match.record` est identique d'une exécution à l'autre tant qu'aucune fléchette n'est jouée. Ensuite, seuls les `id` des fléchettes saisies au doigt changent (`DartProposal.manual` tire un `UUID()`) : un test qui compare une sauvegarde à une valeur attendue passe à `receive` des propositions dont il fixe l'`id`.
- **Sortie** : `app.closeGame(discard:)` et `app.rematch()` appellent `game.finishGame()` si la partie est finie, `game.suspend()` sinon (§8.6), avant de retirer `app.game`. `closeGame` vide aussi `app.path` : « Changer de jeu », « Garder pour plus tard » et « Abandonner » ramènent à l'accueil, où l'on choisit un autre jeu et où se trouve la carte de reprise, et jamais à la préparation du jeu qu'on vient de quitter (revue finale). `rematch` ne touche pas au chemin.

| `OptionKind` | Contrôle |
|---|---|
| `toggle` | `ToggleRow` |
| `stepper(range)` | `StepperRow` |
| `optionalStepper(range, nullLabel)` | `StepperRow` avec `nullLabel` |
| `choice` de 2 ou 3 choix sans `detail` | `SegmentedChoice` |
| `choice` autrement | une `RadioRow` par choix ; `illustration: .sectors(count:moving:)` se dessine avec un petit `DartboardView` non interactif |

### 8.6 Comportement de l'écran de jeu

`PlayViewModel` est le seul propriétaire du `GameMatch`. Les règles ci-dessous sont normatives et testées avec une source factice et `SilentSoundPlayer`. Tous les appels de commande à la source sont synchrones (§8.4.6) : ils sont écrits ici dans l'ordre où ils DOIVENT être faits, et la source les transmet dans cet ordre.

**Démarrage** (`run(boardConfirmedEmpty:)`), pour une partie neuve comme pour une partie reprise

0. Avec une source (`game.inputStatus != .manualOnly`), `PlayScreen` commence par attendre `app.camera.activate()`, dans la tâche même qui lance `run` : `.task { await app.camera.activate() ; … ; await game.run(boardConfirmedEmpty:) }`. La session est ainsi démarrée et le calibrage enregistré réinstallé **avant** que `gameStarted` dépose `setTrigger` puis `arm`. Sans cette étape, après un lancement à froid, `arm` arriverait dans `needsCalibration` et serait ignorée : la première partie en mode caméra n'aurait ni scan en direct ni « Scanner la volée ». `activate()` est idempotent (§8.7) ; sans source, l'étape est sautée.
1. Avec une source et un calibrage valide (`app.camera.readiness` est `.ready` après l'étape 0) : `PlayScreen` demande ensuite « La cible est-elle vide ? » (`GAMES.md` §2.4) ; sans calibrage valide il ne pose pas la question et passe `boardConfirmedEmpty: false`. `run` ouvre alors le flux (`let events = source.events()`) **avant** toute commande, pour ne perdre aucun événement, puis appelle `source.gameStarted(boardConfirmedEmpty:)`.
2. Il synchronise la source sur la phase du match :
   - phase `throwing` : `source.turnBegan(expectedDarts: 3 - match.currentTurn.count)`. Une partie neuve donne 3 ; une partie reprise au milieu d'une volée donne le nombre de fléchettes encore attendues ;
   - phase `turnComplete` ou `finished` : `source.turnClosed()`.
3. Si la partie n'est pas finie : `sound.play(CueMapping.cues(for: .gameStarted(firstPlayer: snapshot.currentPlayer), context:))`.
4. Boucle `for await event in events` (table « Événements de la source »).

**Arrivée d'une fléchette** (`receive`), dans cet ordre :

1. Si `match.phase != .throwing` : la proposition est abandonnée, `prompt = .dartIgnored`, son `dartIgnored`.
2. Si `pending` n'est pas vide : la proposition se range à la fin de `pending` (l'ordre des fléchettes est préservé).
3. Sinon, selon `proposal.certainty(match)` :
   - `undecided` : rangée dans `pending`, son `dartUndecided`, `correction = .pending(id:)`. Elle n'est **pas** envoyée au jeu ;
   - `certain` ou `needsReview` : `match.throwDart(proposal.record(needsReview:))`, qui passe au moteur la case **et la position** de la proposition. Les événements rendus vont à `CueMapping` puis à `sound.play`, avec le contexte `CueContext(gameID:players:winners:winnerTitle:)` pris de l'instantané **après** l'entrée (`snapshot.winners`, `snapshot.winnerTitle`) ; pour `needsReview`, le son `dartNeedsReview` suit.
4. Après une fléchette acceptée : sauvegarde (`storage.saveCurrentMatch(match.record)`) ; si l'origine est `.manual` et qu'une source existe, `source.manualDartAdded()` ; si la phase n'est plus `throwing` (tour clos **ou partie finie**), `source.turnClosed()`. Rien d'autre : une partie finie sur cette fléchette n'est ni effacée, ni annoncée à la source comme terminée (voir « Fin de la partie »).

`tapBoard(_:)` appelle `receive(.manual(tap.hit, position: tap.position))` ; `addMiss()` appelle `receive(.manual(.miss))`.

**Réponse à une fléchette en attente** (`resolvePending(with:)`) : la tête de `pending` est retirée. Avec une case, elle est envoyée au jeu comme certaine : si la case est celle de la proposition, la position détectée est conservée ; si elle diffère, la fléchette est marquée `corrected` et part **sans position** (`GAMES.md` §2.5 : une position ne survit pas à un changement de case qui ne la redonne pas). Avec `nil`, `source.dartDiscarded(id)`. Les suivantes sont ensuite rejouées par `receive`, dans l'ordre, jusqu'à la prochaine indécise.

**Corrections** (tour courant seulement)

| Action | Appel | Suite |
|---|---|---|
| Choisir une autre case dans une liste | `correctDart(at:to:)` → `match.replaceDart(at:with:position: nil)` : l'ancienne position est effacée | son `correctionApplied` |
| Déplacer le réticule sur l'image de preuve, ou toucher la cible virtuelle | `correctDart(at:to:position:)` → `match.replaceDart(at:with:position:)` : la nouvelle position est enregistrée | son `correctionApplied` |
| Retirer une fléchette fantôme | `match.removeDart(at:)` | `source.dartDiscarded(id)` pour une fléchette de la source |
| Accepter une fléchette « à vérifier » | `match.setNeedsReview(false, at:)` | — |
| Annuler | `match.undo()` | son `undo` |

Après chacune : aucun événement n'est rejoué (l'affichage suit `snapshot`), la partie est sauvegardée, et la source est resynchronisée sur la phase obtenue :

- phase `throwing` (le tour est ouvert, ou rouvert par l'annulation d'un `endTurn`, d'un bust ou de la fléchette gagnante) : `source.turnBegan(expectedDarts: 3 - nombre de fléchettes du tour)` ;
- phase `turnComplete` ou `finished` : `source.turnClosed()`.

**Fin du tour**

- Le bouton « Fléchettes retirées, suivant » est actif quand `canEndTurn` (aucune fléchette en attente, partie non finie).
- `requestEndTurn()` : si la phase est `throwing` avec moins de trois fléchettes **et** que `descriptor.confirmsShortTurn` est vrai, `prompt = .confirmShortTurn` ; sinon `endTurn()`. Au Golf, où s'arrêter après une ou deux fléchettes est un coup du jeu (`confirmsShortTurn == false`, `GAMES.md` §16.5), la volée courte passe sans question.
- `endTurn()`, dans cet ordre : `source.turnConfirmed(_:)` avec un `DartFeedback` par fléchette d'origine `camera` ou `scan` du tour (`wasCorrected = record.corrected`), sans appel si la liste est vide ; `match.endTurn()` ; sons ; sauvegarde (`storage.saveCurrentMatch(match.record)`). Puis, selon la phase obtenue : `throwing` → `source.turnBegan(expectedDarts: 3)` ; `finished` (limite de manches) → `source.turnClosed()`.
- `endsTurnOnTakeout` vient de `AppSettings` ; l'écran « Réglages » le propose dans sa section Caméra (« Passer au joueur suivant quand les fléchettes sont retirées »), désactivé par défaut. `GAMES.md` §2.4 et `DESIGN.md` §5 décrivent le même réglage : il n'agit que si le tour est déjà clos et qu'aucune fléchette n'attend de réponse.
- `source.boardConfirmedEmpty()` n'est appelé que sur une action explicite du joueur, en réponse au statut `needsEmptyBoard` (§8.7). Le bouton de fin de tour ne l'envoie pas : le joueur l'appuie souvent avant d'avoir retiré ses fléchettes, et `VISION.md` §6.5 traite ce cas avec `beginVisit` seul.

**Fin de la partie.** Une partie finit de deux façons, et `PlayViewModel` les traite de la même manière : au moment où la phase devient `finished`, il ne fait **que** sauvegarder et fermer la volée côté source.

| Façon de finir | Jeux | Entrée qui finit | À ce moment |
|---|---|---|---|
| sur une fléchette (`victory`, `lastPlayerStanding`) | X01, Cricket, Killer, Shanghai, Alunissage, Combat, Conquérant, Football, Tour de l'horloge | `receive` ou `resolvePending` | étape 4 de `receive` : sauvegarde, `source.turnClosed()` |
| à la limite de manches (`roundLimit`) | tous, et c'est la seule fin de Tireuse, Radar, Golf, Meilleur score et La Moitié | `endTurn()` | `source.turnConfirmed`, `match.endTurn()`, sauvegarde, `source.turnClosed()` |

`ResultsContent` montre en très grand `snapshot.winnerTitle` quand il est renseigné (au Football : « Le camp A gagne », « Match nul »), sinon le nom des joueurs de `snapshot.winners`, dans leur couleur (`DESIGN.md` §4). Comme le reste de l'écran de jeu, il ne teste jamais l'identifiant du jeu.

Tant que l'écran des résultats (`ResultsContent`, affiché quand `snapshot.phase == .finished`) est à l'écran :

- la partie **reste sauvegardée** (`match.current.v1` contient le journal de la partie finie) ;
- elle **reste corrigible** : `undo`, `correctDart` et `removeDart` agissent (`GAMES.md` §2.5 : annuler la fléchette gagnante rouvre la partie ; annuler le dernier `endTurn` rouvre le dernier tour). Si la phase redevient `throwing`, la resynchronisation ci-dessus envoie `source.turnBegan(3 − n)` et la partie reprend ;
- `source.gameEnded()` n'a **pas** été envoyé.

`finishGame()` est appelé une seule fois, par `AppModel.closeGame(discard:)` ou `AppModel.rematch()`, quand le joueur quitte l'écran des résultats (« Revanche », « Changer de jeu ») :

1. `source.turnConfirmed(_:)` pour les fléchettes d'origine `camera` ou `scan` du tour courant : c'est le tour gagnant, qu'aucun `endTurn` n'a confirmé. Après une fin à la limite de manches le tour courant est vide, et l'appel est omis ;
2. `source.gameEnded()` ;
3. `storage.saveCurrentMatch(nil)`.

`suspend()` est appelé par `AppModel.closeGame(discard:)` quand le joueur quitte une partie **non finie** : `source.gameEnded()` seulement. La sauvegarde reste, et la partie se reprend depuis l'accueil ; avec `discard: true`, `AppModel` efface en plus la sauvegarde.

Reprise : `AppModel.resumableMatch` vaut la partie sauvegardée, **quelle que soit sa phase**. `resumeSavedGame()` la reconstruit par `registry.restoreMatch` et la présente. Une partie enregistrée en phase `finished` (application fermée sur l'écran des résultats) se rouvre directement sur ses résultats, et `run` envoie `source.turnClosed()` (étape 2 du démarrage).

Tests obligatoires (lot U2), avec une source factice qui enregistre les commandes :

- fin sur une fléchette : après la fléchette gagnante, `turnClosed` est envoyé, `gameEnded` ne l'est pas, la sauvegarde existe ; `undo` rend la phase `throwing` et envoie `turnBegan(expectedDarts:)` ; rejouer la fléchette gagnante puis `finishGame()` envoie `turnConfirmed` avec les fléchettes du tour gagnant, puis `gameEnded`, et efface la sauvegarde ;
- fin à la limite de manches : `endTurn()` envoie `turnConfirmed` puis `turnClosed`, la sauvegarde existe ; `finishGame()` n'envoie pas de second `turnConfirmed`, envoie `gameEnded` et efface la sauvegarde ;
- reprise d'une partie finie : l'écran des résultats s'affiche, `turnClosed` est envoyé, aucun `turnBegan`.

**Événements de la source**

| `DartInputEvent` | Réaction |
|---|---|
| `dart(proposal)` | `receive(proposal)` |
| `dartDisturbed(id)` | `match.setNeedsReview(true, at:)` sur la fléchette de cet `id` |
| `dartRemoved(id, .fellOut)` | `prompt = .dartFellOut(index:)` ; si le joueur accepte : `correctDart(at:to: .miss)`. Cet événement arrive aussi quand la cible se retrouve **vide** : la seule fléchette plantée qui tombe donne `.fellOut`, pas un retrait (`VISION.md` §6.3, ligne A10), et aucun `boardCleared` ne suit |
| `dartRemoved(id, .takeout)` | rien |
| `possibleMiss` | `prompt = .possibleMiss` pendant 5 s ; si le joueur accepte : `addMiss()` |
| `boardCleared` | si `endsTurnOnTakeout` et phase `turnComplete` et `pending` vide : `endTurn()` ; sinon `prompt = .boardCleared` (le bouton est mis en avant). Jamais reçu en mode photo (§8.7) |
| `statusChanged(status)` | `inputStatus = status` ; au passage à `.needsCalibration`, son `calibrationLost` |
| `advisory(text)` | `prompt = .advisory(text)` |

Le bouton « Manqué » est toujours visible. La saisie manuelle reste possible dans tous les états de la source : un tap sur la cible pose une fléchette, un appui long ouvre la vue agrandie (`DESIGN.md` §5).

**Accès aux écrans caméra depuis la partie.** `PlayScreen` (lot U2) présente deux couvertures internes, dont le contenu appartient au lot U3 :

| Action | Présente quand | Ouvre |
|---|---|---|
| « Photo » | **toujours**, quels que soient `settings.inputMode`, `settings.scanMode` et `camera.readiness`, y compris en saisie manuelle et sans caméra | `PhotoModeView(game: game, camera: app.camera)` |
| pastille d'état du scan, ou « Agrandir » de `ScanThumbnail` | la partie a une source (`game.inputStatus != .manualOnly`) | `LiveScanView(game: game, camera: app.camera)` |

C'est la photo importée ou prise à main levée qui justifie le « toujours » : ce chemin ne demande ni caméra calibrée ni source (`VISION.md` §8.2), et c'est précisément quand la caméra n'est pas prête qu'il sert. Ce que `PhotoModeView` active ou non est décrit en §8.7.

**Écran de correction.** Il affiche les cases de `proposal.choices` (ou, pour une fléchette déjà comptée, la case courante et ses voisines), « Hors cible » (`MISS`), « Retirer la fléchette », un sélecteur sur la cible virtuelle, et l'image de preuve si la source en a une :

- `source.evidenceImage(for:)` rend un carré de 600 px : 50 mm de cible redressée, 20 en haut, centré sur la pointe détectée, soit 12 px par millimètre ;
- déplacer le réticule de `(dx, dy)` pixels donne la pointe `(x + dx / 12, y − dy / 12)` en millimètres nominaux ; `source.rescore(_:tip:)` rend la proposition recalculée, que l'écran applique par `correctDart(at:to:position:)` avec cette pointe ;
- la cible virtuelle de l'écran est dessinée avec `descriptor.boardGeometry` ; un tap y donne une case et une position (`BoardTap`), appliquées ensemble ;
- une case prise dans la liste part sans position. Dans un jeu dépendant de la position, le moteur lui donne alors la position canonique de la case (§4.2) ; l'écran place donc le sélecteur sur la cible avant la liste, et la liste reste un raccourci.
- *Revue finale :* la feuille fait environ 690 pt de haut, et un iPhone en paysage ne lui en donne qu'environ 370. Dans l'application, tout ce qui est au-dessus de « Valider » défile, et « Valider » reste fixé en bas (`PlayCorrectionContent(scrolls: true)`) ; la loupe passe de 280 à 150 pt dans une feuille de moins de 500 pt. Les résultats font de même (`ResultsContent(scrolls: true)`) : la ligne de contexte avec l'annulation, le titre et le classement défilent, « Revanche » et « Changer de jeu » restent fixés en bas. Un Killer à 8 joueurs demande 1 022 pt sur un iPhone, et toute partie dépasse la hauteur d'un iPhone en paysage. Les instantanés gardent `scrolls: false` (§8.11).

**Précisions de la réalisation (lot U2).**

- Membres de `PlayViewModel` ajoutés au listing de §8.4.7 pour que les écrans du lot U3 s'y appuient, la source restant privée : `handle(_:)` (une ligne du tableau « Événements de la source »), `resolvePending(with: BoardTap)` (un tap de la cible virtuelle de l'écran de correction répond à la tête de `pending` avec la case **et** la position), `confirmBoardEmpty()` (seul appel de `source.boardConfirmedEmpty()`, réponse au statut `needsEmptyBoard`), `evidenceImage(for:)`, `rescore(_:tip:)` et `hasSource`.
- `run` est idempotent : les commandes du démarrage (`gameStarted`, première synchronisation, annonce) partent une fois par partie ; un `run` suivant (l'écran réapparaît) n'ouvre qu'un nouveau flux. `finishGame()` et `suspend()` n'agissent qu'une fois, le premier des deux envoie `gameEnded()`.
- Une partie reprise en phase `finished` se rouvre sur ses résultats sans poser « La cible est-elle vide ? » : `run` envoie `gameStarted(boardConfirmedEmpty: false)` puis `turnClosed()`.
- `confirmDart(at:)` est une correction comme les autres : « Après chacune » s'applique (sauvegarde, puis `turnBegan`/`turnClosed`) ; `removeDart` et `resolvePending(with: nil)` jouent aussi `correctionApplied` (§10.2). Le passage à `needsCalibration` joue `calibrationLost` à chaque entrée dans ce statut, démarrage à froid sans calibrage compris.
- L'assombrissement de la cible dépend du gabarit de jeu (`playStyle`), jamais de l'identifiant : jamais sur le gabarit « score » (X01, Cricket, Alunissage, Meilleur score, Tireuse), selon `DESIGN.md` §3 sur le gabarit « cible ».
- L'écran de jeu ajoute ce que le texte demande et que les maquettes ne montrent pas : « Manqué » en bas à droite de la cible, un bouton de sortie (×) avec « Garder pour plus tard » et « Abandonner », l'annulation sur l'écran des résultats (la partie reste corrigeable), une carte de reprise à l'accueil. « Au tour de … » à l'écran est la phrase de l'annonce (`CallerPhrases.nextPlayer`), qui élide comme la voix (§7.5).
- Un appui long sur la cible est signalé **au relâcher**, au point où il a commencé ; la vue agrandie s'ouvre donc au relâcher (revue du lot U1 : avec un rappel pendant l'appui, `exclusively(before:)` ne rendait plus jamais la main au tap, et aucun tap ne posait de fléchette).

**Précisions de la revue du lot U2 et de l'intégration (vague 3).** Chaque défaut a d'abord été reproduit par un test (`GameFlowReview…Tests`) ; aucune signature imprimée ne change.

- **Question de la volée courte.** « Volée incomplète : passer au joueur suivant ? » est retirée dès qu'une fléchette est reçue en phase `throwing` (acceptée, mise en file ou en attente) : le joueur a lancé au lieu de répondre. Elle restait affichée sur une volée pleine, ou pendant qu'une fléchette attendait une réponse, où son « Oui » ne faisait rien.
- **Resynchronisation pendant une attente.** « Après chacune » envoie `turnBegan(expectedDarts: 3 − n)` avec `n` les fléchettes **du journal** ; celles de `pending`, que la source a déjà vues, ne sont pas retranchées. C'est voulu : si la fléchette en attente est ensuite acceptée, la vision attend une fléchette de trop, mais `turnClosed()` ferme la volée dès que la règle la clôt ; si elle était retranchée puis rejetée comme fantôme (`dartDiscarded`, dont l'`id` n'est plus dans la volée rouverte), la vraie dernière fléchette porterait `beyondVisitLimit`. Le mode photo, lui, retranche les fléchettes en attente du nombre qu'il demande à `captureNow` (§8.7), parce qu'une capture ne doit rendre que des fléchettes nouvelles.
- **Image de preuve.** Elle est dessinée au côté de son cadre (`max(largeur, hauteur)`, coupée en haut et en bas), et non à 350 pt fixes : 353 pt sur un iPhone de 393 pt, 496 pt sur iPad. Un déplacement du réticule se convertit avec ce côté dessiné (`PlayCorrectionModel.movedTip(_:by:imageWidth:drawnSide:)`) ; avant, il était trop long de 41 % sur iPad. Les déplacements s'ajoutent d'un glisser au suivant, et un tap sur l'image y place le réticule, comme le promet la ligne d'aide. `rescore` reçoit le déplacement total depuis la pointe détectée.
- **Cibles tactiles.** Une vue dessinée plus grande que son cadre puis coupée reste touchable hors de la coupe, et la zone d'un bouton est son cadre : un `contentShape` plus grand ne l'étend pas. La cible de 900 pt de la vue agrandie et de l'écran de correction, et l'image de preuve, ne prennent donc plus les taps (`allowsHitTesting(false)`) : fermer la vue agrandie posait une fléchette, et le « × » de la correction déplaçait la sélection. Un tap sur le cadre visible est converti par `PlayCorrectionModel.boardTap`. Les boutons de moins de 44 pt (« × » et « Photo » de l'en-tête, « Voir les niveaux », boutons des lignes de joueurs) sont posés en 44 pt sur un emplacement de leur ancienne taille (`PlayTouchTarget`), sans changer la mise en page.
- **Correction depuis une couverture caméra.** `LiveScanView` et `PhotoModeView` couvrent l'écran de jeu et présentent eux-mêmes `CorrectionSheet` sur `game.correction`. Tant qu'une couverture est affichée, `PlayScreen` ne lie pas sa propre feuille de correction (`.constant(nil)`) : deux feuilles ne tentent plus de présenter le même élément. Ce correctif de l'intégration vient de la lecture du code : la présentation des feuilles n'a pas été essayée au doigt dans le Simulateur.

### 8.7 Parcours caméra

`CameraModel` possède le service de scan pour toute l'application. `CameraInputSource` (lot U3, créé par `CameraModel.makeInputSource(mode:)`) adapte ce service au protocole `DartInputSource`. Le mode fixe le déclencheur pour toute la partie : `.live` donne `ScanTrigger.automatic`, `.photo` donne `ScanTrigger.manual`.

**File de commandes.** Une seule file porte toutes les commandes de `DartUI` vers la vision, et elle appartient à `CameraModel` : `enqueue(_:)` y dépose une `ScanCommand`, `enqueueFeedback(_:wasCorrected:)` un retour d'information (§8.4.8). C'est un `AsyncStream` d'une énumération interne à deux cas, lu par **une** tâche du modèle, qui attend `service.send(_:)` ou `service.recordFeedback(_:wasCorrected:)` avant de prendre l'opération suivante. Personne ne lance une tâche par commande.

- **Tous les écrivains passent par elle** : chaque `CameraInputSource` (celle de la partie qui finit comme celle de la revanche), `PhotoModeView` (`captureReference`, `captureNow`), `CameraModel.setForeground` (`pause`, `resume`) et le parcours de calibrage (`arm` de la vérification à une fléchette, puis `pause(.user)` à sa fermeture). **Aucun autre code de `DartUI` n'appelle `service.send` ni `service.recordFeedback`.**
- Chaque méthode synchrone de `DartInputSource` ne fait qu'y déposer ses opérations. La vision reçoit donc les commandes dans l'ordre exact des appels, quel que soit l'écran qui les fait : `endVisit`, `beginVisit` et `discardDart` ne peuvent pas se croiser, un `captureNow` ne passe jamais devant le `beginVisit` qui le précède, le `pause(.user)` d'une partie arrive avant le `setTrigger` de la suivante, et les compteurs de volée de la vision restent justes.
- Deux choses restent hors de la file, sans effet sur cet ordre. `setCalibration` et `updateConfiguration` sont attendus (`await`) par `activate()` et par `adopt` avant que quiconque dépose la commande suivante. Les pauses que `LiveScanService` envoie lui-même à sa session sur une interruption de capture ou un changement d'angle (§6.5) sont des faits du système, sans ordre défini par rapport au jeu : la machine accepte `pause` et `resume` dans tout état (`VISION.md` §6.3, lignes P1 à P2c), et une pause de fin de partie l'emporte sur une pause du système dans quelque ordre qu'elles arrivent (ligne P1b).

**Commandes** (du jeu vers la vision)

| `DartInputSource` | Opérations déposées dans la file, dans cet ordre |
|---|---|
| `gameStarted(boardConfirmedEmpty: true)` | `.setTrigger(.automatic)` ou `.setTrigger(.manual)` selon le mode, **à chaque partie** ; puis `.arm(boardConfirmedEmpty: true)` |
| `gameStarted(boardConfirmedEmpty: false)` | **rien** : la vision n'est pas armée tant que la cible n'est pas confirmée vide (voir « Pas encore » ci-dessous) |
| `turnBegan(expectedDarts:)` | `.beginVisit(expectedDarts:)` |
| `turnClosed()` | `.endVisit` |
| `dartDiscarded(id)` | `.discardDart(id)` |
| `manualDartAdded()` | `.registerManualDart` |
| `turnConfirmed(feedback)` | `recordFeedback(id, wasCorrected:)` pour chaque élément dont l'`id` n'a pas déjà été rapporté |
| `boardConfirmedEmpty()` | `.confirmBoardEmpty` ; après « Pas encore » : `.setTrigger(…)`, `.arm(boardConfirmedEmpty: true)`, puis la dernière volée décrite par le jeu (`.beginVisit(n)` ou `.endVisit`) |
| `gameEnded()` | `.pause(.user)` |

Les deux requêtes ne passent pas par la file : `evidenceImage(for:)` appelle `evidenceCrop(for:)` ; `rescore(_:tip:)` appelle `correct(_:tip:)` puis `DartProposal(observation:thresholds:)`.

Ce que ce tableau doit au cycle de vie de `VISION.md` §6.3 :

- **`setTrigger` avant chaque `arm`.** `arm` ne remet pas le déclencheur à zéro. Sans cette commande, une partie en direct lancée après une partie en mode photo resterait en déclenchement manuel.
- **`pause(.user)` en fin de partie, `arm` au début de la suivante.** `arm` est acceptée depuis tout état calibré : `paused`, mais aussi `awaitingTakeout` quand les fléchettes de la victoire sont encore plantées. Elle remet à zéro références, silhouettes et compteurs (ligne 2). Une revanche détecte donc comme une première partie. Entre les deux, **seule `arm` lève cette pause** : la raison `.user` fait ignorer tout `resume` (ligne P2c), celui d'un retour au premier plan comme celui d'une fin d'interruption de capture. Une application qui passe en arrière-plan sur l'écran d'accueil ou sur les résultats ne réarme donc pas la vision.
- **Statut d'une source avant le premier `stateChanged`.** Une source naît au statut `.preparing`. `gameStarted` commence par lire `camera.service.issue` : s'il n'est pas `nil` (accès refusé ou caméra perdue pendant `activate()`), la source publie `statusChanged(.unavailable)` et ne dépose rien ; la partie se joue au doigt. Sinon elle dépose `setTrigger` puis `arm`, puis lit `await camera.service.currentState()` dans sa tâche d'événements : dans `needsCalibration` et dans `calibrationLost`, où `arm` ne change pas d'état et n'émet rien (`VISION.md` §6.3), elle publie `statusChanged(.needsCalibration)`, et la partie se joue au doigt tant que le calibrage manque. Dans tout autre état, les `stateChanged` qui suivent `arm` portent le statut.
- **« Pas encore »** (revue finale). Armer sur une cible qui porte encore des fléchettes les met dans les références : quand le joueur les retire, ce que la ligne d'armement de la partie demande, la vision voyait une fléchette fantôme à la place d'une ancienne (« T20 ? » avant tout lancer en direct, des fantômes au premier « Scanner la volée », un `dartRemoved(.fellOut)` sur une partie reprise au milieu d'une volée). `gameStarted(boardConfirmedEmpty: false)` ne dépose donc rien : la source publie `.needsEmptyBoard` (`.needsCalibration` tant que la vision n'a pas de calibrage, d'après `currentState()`), garde ce statut à tout `stateChanged`, et aucun `dart`, `dartDisturbed`, `dartRemoved`, `possibleMiss` ni `takeoutCompleted` ne va au jeu. `turnBegan`, `turnClosed` et `manualDartAdded` ne déposent rien non plus : la source retient la volée (`beginVisit(n)` moins les fléchettes saisies au doigt depuis, ou `endVisit`). « Videz la cible, puis confirmez » (bandeau de l'écran de jeu, `LiveScanView`, ou « Cible vide » du mode photo) appelle `boardConfirmedEmpty()`, qui dépose `setTrigger`, `arm(boardConfirmedEmpty: true)` puis cette volée : `arm` remet les compteurs de la vision à zéro. Le statut reste `.needsEmptyBoard` jusqu'au `stateChanged(.arming)`. L'application n'envoie donc jamais `arm(boardConfirmedEmpty: false)`. Le moteur, lui, ne reconnaît toujours pas comme un retrait la disparition d'une silhouette prise dans `R` à un tel `arm` (`VISION.md` §6.3, ligne A15) : ce cas n'est plus atteint depuis l'application.
- **Un seul retour par fléchette.** `ScanEngine.recordFeedback` doit être appelé une fois par fléchette. Un tour confirmé, annulé puis confirmé de nouveau ne rapporte donc pas deux fois les mêmes `id`.

**Événements** (de la vision vers le jeu)

| `ScanEvent` | `DartInputEvent` ou effet |
|---|---|
| `stateChanged(.idle)`, `.arming` | `statusChanged(.preparing)` |
| `stateChanged(.watching)`, `.awaitingTakeout` | `statusChanged(.live)` ; en mode photo, `statusChanged(.awaitingCapture)` : la vision est au repos et attend une capture |
| `stateChanged(.motion)`, `.settling`, `.analysing`, `.takeout` | `statusChanged(.live)` ; en mode photo, `statusChanged(.preparing)` : une capture est en cours |
| `stateChanged(.obstructed)` | `statusChanged(.obstructed)` |
| `stateChanged(.paused)` | `statusChanged(.paused)` |
| `stateChanged(.needsCalibration)`, `stateChanged(.calibrationLost)`, `calibrationLost` | `statusChanged(.needsCalibration)` |
| `dart(observation)` | `dart(DartProposal(observation:thresholds:))` |
| `dartDisturbed(id)` | `dartDisturbed(id)` |
| `dartRemoved(id, reason)` | `dartRemoved(id, reason)` |
| `possibleMiss` | `possibleMiss` |
| `takeoutCompleted` | `boardCleared` |
| `takeoutStarted` | rien |
| `takeoutStalled`, `lightingChanged`, `unrecognizedChange`, `advisory(…)` | `advisory(texte)` ; le texte vient de `Camera.strings` |
| `needsEmptyBoard` | `statusChanged(.needsEmptyBoard)`, **gardé** jusqu'au prochain `stateChanged(.arming)` (voir ci-dessous) |
| `calibrationAdjusted(c)`, `calibrationRecovered(c)` | `CameraModel` enregistre `c` (§8.10) ; pas de changement de statut : les `stateChanged` qui suivent le portent |
| `scanCompleted(observations)` | rien dans `CameraInputSource` : `PhotoModeView` le reçoit par son propre flux (« Mode photo ») |

**Reprise sur une scène changée.** Après une pause (arrière-plan, appel, chaleur), si la cible n'est plus dans l'état où la vision l'a laissée, le réducteur émet `stateChanged(.idle)` **puis** `needsEmptyBoard` : dans une transition, `stateChanged` sort toujours en premier (`VISION.md` §6). Règles :

- `CameraInputSource` passe donc par `.preparing`, puis `.needsEmptyBoard`, et **garde** ce statut. Tant qu'il est levé, aucun `stateChanged` ne le remplace, sauf `stateChanged(.arming)`, qui le lève, et la perte du calibrage, qui donne `.needsCalibration`.
- L'écran de jeu affiche « Videz la cible, puis confirmez ». La confirmation du joueur appelle `source.boardConfirmedEmpty()`, soit `.confirmBoardEmpty`. Depuis `idle`, la vision réarme et revient à `watching(0)` en **conservant ses compteurs de volée** (ligne P3) : le jeu n'a aucun `turnBegan` à renvoyer.
- En mode photo, une reprise ne lève jamais `needsEmptyBoard` (ligne DM7).
- Arrière-plan : `AppModel.setForeground(_:)` appelle `camera.setForeground(_:)`, qui dépose `.pause(.background)` puis, au retour, `.resume`, par `enqueue`. Ces deux commandes partent quel que soit l'état de la vision. Une pause prise hors d'un état immobile (`needsCalibration`, `idle`, `arming`, `calibrationLost` : l'application passe en arrière-plan sur l'écran de calibrage, ou pendant l'armement) se reprend dans ce même état, sans analyse ni `needsEmptyBoard` nouveau (`VISION.md` §6.3, ligne P2b). Après une fin de partie (`pause(.user)`), ce `.resume` est ignoré par la machine (`VISION.md` §6.3, ligne P2c) : la vision reste à l'arrêt jusqu'au prochain `arm`. `CameraModel` ne filtre rien : il dépose toujours les deux commandes, et c'est la machine qui décide.

Seuils de palier : `ScanSession` n'expose pas les seuils courants du `TrustTracker`. `CameraInputSource` utilise `ConfidenceThresholds.standard` ; dès qu'il reçoit `advisory(.accuracyDegraded)`, il passe le seuil haut à `VisionConfiguration().confidence.degradedHighThreshold` jusqu'à la fin de la partie. C'est volontairement prudent.

**Cycle de vie**

- `CameraModel.activate()` démarre le service et réinstalle le calibrage enregistré. Il est idempotent : sans effet quand le service tourne déjà, et un appel fait pendant qu'un autre est en cours attend le même résultat. Il est appelé :
  - par `HomeScreen`, à son apparition et quand la bascule passe sur « Scan caméra », si `settings.inputMode == .camera` : la carte caméra montre ainsi l'état réel (`readiness`) dès le lancement, et non `.unknown` ;
  - par `PlayScreen`, avant `game.run`, quand la partie a une source (§8.6, étape 0) ;
  - par `CalibrationFlowView`, `LiveScanView` et `PhotoModeView`, à leur apparition.
- `deactivate()` est appelé quand la bascule de l'accueil repasse sur « Saisie manuelle », et à la fermeture d'un écran caméra ouvert alors que `settings.inputMode == .manual` (calibrage depuis les réglages, mode photo d'une partie jouée au doigt). En mode caméra, la session reste donc ouverte de l'accueil à la fin de la partie, et une partie démarre sans attendre la caméra ; en saisie manuelle, elle ne tourne que sur un écran caméra. Avant `arm` et après `pause(.user)`, la vision ne traite aucune image (`VISION.md` §6.3) : dans `paused(.user)`, `resume` est ignoré (ligne P2c), et seul le `arm` de la partie suivante la relance.
- `keepsScreenAwake(true)` sur `PlayScreen` en mode caméra, sur `LiveScanView`, `PhotoModeView` et `CalibrationFlowView`.
- À `activate()`, si un calibrage est enregistré pour (`cameraID`, `rotationDegrees`, `imageSize`) : image figée, `BoardCalibrator.assess`, puis `recover` si besoin (`VISION.md` §4.10). Sain : `service.updateConfiguration(_:)` **puis** `setCalibration(_:)` avec les valeurs enregistrées, puis `readiness = .ready`. L'ordre compte : le moteur fixe le plafond de rodage d'un calibrage d'après la configuration en place quand il l'installe, et une configuration reçue ensuite ne le change pas (`VISION.md` §6.5) ; `adopt` suit le même ordre. Sinon : `.needsCalibration` ; la carte caméra de l'accueil propose de calibrer, et l'écran de calibrage part des anciennes poignées. Service qui ne démarre pas : `readiness = .unavailable(issue)`, et `makeInputSource` rend `nil` ensuite.
- Dans le Simulateur, il n'y a pas de caméra arrière : `LiveScanService` utilise une source de démonstration, `CameraDemoFrameSource` (lot U3) : deux rendus `SyntheticScene` de la cible vide, en boucle, à 10 images/s, par une caméra proche de la pose A sur un capteur 1080 × 1920 (environ 1,5 px/mm). Une `SyntheticFrameSource` joue un script fini : après lui la session n'aurait plus d'images et `captureStill` attendrait en vain. Le calibrage se fait donc sur cette cible de synthèse (grade « fair »), et une partie en mode caméra arme la vision, qui ne voit jamais de fléchette ; la saisie au doigt marche dans tous les états. Si la source ne démarre pas, `readiness = .unavailable(.noCamera)` et tout le jeu fonctionne en saisie manuelle. Un Mac qui expose une caméra (`cameraID` « back-wide ») passe par `CameraFrameSource` et par l'autorisation ; refusée, `readiness = .unavailable(.accessDenied)` et `makeInputSource` rend `nil`.
- Avant la livraison du lot U3, `ScanServiceFactory.live()` rend `FakeScanService(issue: .noCamera)` et `CameraModel` a son corps minimal (§8.4.8) : `readiness` reste `.unknown`, que l'interface traite comme « pas de caméra ».
- Aperçu : `Camera/CameraPreviewView.swift` (lot U3) contient `#if os(iOS)`. Sur iOS c'est un `UIViewRepresentable` dont la couche est un `AVCaptureVideoPreviewLayer` ; ailleurs, et pour `PreviewContent.image`, une `Image`. Les tracés (fil de fer, pointes) sont en pixels image et se placent par la conversion de la couche d'aperçu.

**Calibrage** (`CalibrationFlowView`, d'après `VISION.md` §2.3, §4.7 et §4.8)

| Étape | Appels | Fil |
|---|---|---|
| 1. Autorisation et démarrage | `ScanServicing.start()` ; refus : écran « caméra refusée » avec `SystemSettings.open()` et « Continuer en saisie manuelle » | principal |
| 2. Aide au placement (première fois) | `PlacementGuideView` | — |
| 3. Image figée | `captureStill(averaging: 8)` : l'appareil est sur son support | file de la session |
| 4. Poignées initiales | calibrage précédent, sinon `ColourBoardLocator().locate(in:upDirection:)`, sinon `CalibrationHandles.centredDefault(in:)` | tâche détachée |
| 5. Réglage au doigt, loupe 4× | `BoardCalibrator.preview(…)` à chaque déplacement ; fil de fer par `BoardCalibration.wireframe(ringSegments:)` ; un conseil à la fois d'après `quality.issues` | principal (quelques microsecondes) |
| 6. « Valider » | `BoardCalibrator.calibrate(…)` ; `sectorPhaseMismatch` : « touchez le 20 » puis `reoriented(twentyAt:parityPreserving:)` | tâche détachée |
| 7. Vue de preuve et test au toucher | `BoardRectifier.rectify(_:)` ; `calibration.hit(at:board:)` annoncé par `sound.say` | tâche détachée, puis principal |
| 8. Adoption | `camera.adopt(calibration, lightingCheckPassed: false)` ; son `calibrationValidated` | principal |
| 9. Vérification à une fléchette (facultative) | `camera.enqueue(.arm(boardConfirmedEmpty: true))`, une fléchette, toucher sa pointe, `runLightingCheck(confirmedTip:)` ; puis `adopt(…, lightingCheckPassed: true)`. À la fermeture du parcours, s'il a déposé cet `arm` : `camera.enqueue(.pause(.user))`, que la vérification ait abouti ou non | file de la session |

Cette `pause(.user)` arrête la vision que la vérification avait armée : sans elle, la machine surveillerait la cible depuis l'écran d'accueil. Comme en fin de partie, seul le `arm` de la partie suivante la relance.

**Mode photo** (`PhotoModeView` ; `VISION.md` §6.3, table « Déclenchement manuel », et §8)

`PhotoModeView(game:camera:)` s'ouvre par l'action « Photo » de l'écran de jeu, toujours présente (§8.6). Il réunit deux chemins indépendants :

| Chemin | Boutons | Actifs quand |
|---|---|---|
| Scanner la volée : appareil sur son support, déclenchement manuel (`VISION.md` §8.1) | « Cible vide » | `camera.readiness` est `.ready` **et** `game.inputStatus` vaut `.awaitingCapture` (la source de la partie est en déclenchement manuel, et la vision est au repos) ou `.needsEmptyBoard` (« Cible vide » est alors la confirmation `game.confirmBoardEmpty()`) |
| | « Scanner » | `camera.readiness` est `.ready` **et** `game.inputStatus == .awaitingCapture` **et** `game.snapshot.phase == .throwing` **et** `game.turnRecords.count + game.pending.count < 3` : la volée attend encore au moins une fléchette |
| Photo unique (`VISION.md` §8.2, chemin garanti) | « Importer une photo » | **toujours** : sans caméra, sans calibrage, en saisie manuelle |
| | « Prendre une photo » | quand le service délivre des images (`camera.service.issue == nil`) |

*Scanner la volée.*

- « Cible vide » envoie `.captureReference`. « Scanner » envoie `.captureNow(maxDarts: 3 − r)`, avec le son `shutter`, où `r` compte les fléchettes que la vision a déjà rendues : celles du tour d'origine `camera` ou `scan`, et celles qui attendent une réponse. Une fléchette saisie au doigt ou par photo n'est pas déduite (revue finale) : elle est dans la cible mais pas dans `R`, le scan la propose de nouveau et la revue l'écarte ; la déduire laissait ce doublon prendre la place de la vraie dernière fléchette, absorbée dans `R` puis jamais proposée. Les deux commandes passent par `camera.enqueue(_:)`, la file unique.
- Le statut `.awaitingCapture` couvre aussi le repos `awaitingTakeout`, celui d'une volée pleine ou close. « Scanner » y est inactif : avec trois fléchettes il enverrait `captureNow(maxDarts: 0)`, que la vision ignore sans événement (`VISION.md` §6.3, ligne DM3), et après un bust ou une victoire il scannerait des fléchettes que `receive` écarterait. « Cible vide » y reste actif.
- La vision n'accepte ces deux commandes qu'au repos (`watching` ou `awaitingTakeout`, lignes DM2 et DM3) et les ignore ailleurs **sans événement** : c'est la raison de la condition `.awaitingCapture`. « Scanner » reste inactif de l'appui jusqu'au `scanCompleted`.
- Toute commande `captureNow` acceptée est suivie d'**exactement un** `scanCompleted`, **éventuellement vide**. `PhotoModeView` le reçoit par son propre flux `camera.service.events()` (un flux neuf par appel, §11), et montre toujours l'écran de revue :
  - avec des observations : le joueur peut les réordonner (quand plusieurs fléchettes sont demandées, leur ordre est inconnu), puis chacune part par `game.receive(DartProposal(observation:thresholds:))`, dans l'ordre retenu, avec les seuils de la source de la partie (`camera.inputSource?.thresholds`, relevés après `accuracyDegraded`, « Seuils de palier ») ;
  - sans observation : « Aucune nouvelle fléchette », avec la cause si un événement a précédé le résultat : `advisory(.viewObstructed)` (la vue ne s'est pas posée en 2 s), `lightingChanged` (la lumière a changé), ou une capture interrompue par une pause.
- Après `lightingChanged`, l'écran demande de vider la cible et d'appuyer sur « Cible vide ».
- *Revue finale :* la vision compte les fléchettes d'un scan dès qu'elle rend `scanCompleted` (`R := S`), et seule la revue les donne au jeu. Le bouton de retour est donc inactif pendant `.scanning` et sur la revue, que ses propres boutons ferment. Un `captureNow` que la vision n'a pas accepté ne reçoit aucune réponse : après 8 s sans `scanCompleted`, l'écran revient à l'étape caméra (un résultat tardif s'affiche encore).
- « Cible vide » n'est nécessaire qu'**une fois**, pas à chaque volée : la référence vide est conservée d'une volée à l'autre, et l'armement la prend déjà quand le joueur a confirmé la cible vide au début de la partie.
- Volées : `turnBegan(expectedDarts: 3)` annonce une volée entière sur une cible vidée, et la vision repart de la référence vide (ligne DM4). `turnBegan(expectedDarts: k)` avec `k < 3`, envoyé par la resynchronisation après une correction (§8.6), garde les fléchettes déjà scannées : le scan suivant ne rend que les nouvelles.
- Dans ce mode la vision ne regarde pas la cible entre deux commandes. Elle n'émet ni `takeoutCompleted` (donc pas de `boardCleared`, et `endsTurnOnTakeout` n'agit jamais), ni `possibleMiss`, ni `dartRemoved(.fellOut)`. Le tour se termine au bouton.

*Photo unique, importée ou prise à main levée.*

- Import par `PhotosPicker` (aucune autorisation requise), ou prise par `camera.service.captureStill(averaging: 1)` : une seule image, la moyenne de huit rendrait floue une photo tenue en main.
- Calibrage de **cette photo** (étapes 4 à 6 ci-dessus, appliquées à la photo) ; le joueur touche chaque pointe ; `PhotoScorer.observation(forTappedTip:calibration:visit:indexInVisit:)` ; chaque observation devient une proposition **certaine**, avec sa position, envoyée à `game.receive`.
- *Revue finale :* comme le parcours de calibrage, un calibrage de la photo qui porte `sectorPhaseMismatch` (fil de fer tourné d'un nombre entier de secteurs) ne passe pas aux pointes : l'étape `.photoTouchTwenty` demande de toucher le vrai 20, les poignées tournent (`reoriented(twentyAt:parityPreserving: false)`) et la photo est recalibrée. Avant, chaque pointe était comptée certaine dans le mauvais secteur. Un calibrage de grade `poor` donne des fléchettes « à vérifier » (`VISION.md` §4.7).
- Ce chemin ne dépend ni de `camera.readiness`, ni de la source de la partie, ni du calibrage sur support. Il fonctionne dans le Simulateur et avec `FakeScanService(issue: .noCamera)`.

Tests obligatoires (lot U3), avec `FakeScanService`. Les listes de commandes se comparent par `==` à la liste attendue, écrite en entier (`ScanCommand` est `Hashable`, `VISION.md` §9.2) :

- une photo importée (image synthétique), service `FakeScanService(issue: .noCamera)`, partie en saisie manuelle : trois pointes touchées donnent trois propositions certaines reçues par `game.receive`. `PhotoScorer` appartient au lot V3 (vague 2, `VISION.md` §9.3) : ce test ne dépend pas du lot V5, qui travaille dans la même vague que U3 ;
- démarrage à froid : `CameraModel` neuf (`readiness == .unknown`), un calibrage enregistré, `FakeScanService` avec une image et sans `issue`. `makeInputSource` rend une source ; après `activate()`, le service a reçu le calibrage (`calibrations`) ; `gameStarted(boardConfirmedEmpty: true)` d'une source de mode `.live` donne ensuite `commands == [.setTrigger(.automatic), .arm(boardConfirmedEmpty: true)]`. Sans calibrage enregistré, la source publie `.needsCalibration` ; avec `issue` posé avant `gameStarted`, elle publie `.unavailable` et `commands` reste vide ;
- `gameStarted` dépose `setTrigger` puis `arm`, à la première partie et à la suivante ; après « Pas encore » (`boardConfirmedEmpty: false`), rien jusqu'à `boardConfirmedEmpty()` ; cent commandes déposées d'affilée par `camera.enqueue` arrivent au service dans le même ordre ;
- ordre entre écrivains : `turnBegan` déposé par la source puis `captureNow` déposé par `PhotoModeView` arrivent dans cet ordre ; `gameEnded` de l'ancienne source puis `gameStarted` de la nouvelle donnent `pause(.user)`, `setTrigger`, `arm` ; `setForeground(false)` puis `setForeground(true)` donnent `pause(.background)`, `resume`, y compris après `gameEnded` : la file ne filtre pas ce `resume`, c'est la machine qui l'ignore (`VISION.md` §6.3, ligne P2c) ;
- vérification à une fléchette : le parcours de calibrage dépose `.arm(boardConfirmedEmpty: true)`, puis `.pause(.user)` à sa fermeture ; fermé sans vérification, il ne dépose aucune commande ;
- `needsEmptyBoard` : le statut reste `.needsEmptyBoard` malgré un `stateChanged(.paused)`, et tombe à `stateChanged(.arming)` ;
- `scanCompleted([])` : l'écran de revue s'affiche, vide, et rien n'est envoyé au jeu ;
- les boutons « Cible vide » et « Scanner » sont inactifs hors du statut `.awaitingCapture`, sauf « Cible vide » sous `.needsEmptyBoard` ; « Scanner » l'est aussi quand la volée est pleine (trois fléchettes comptées ou en attente) ou close (phase `turnComplete` ou `finished`), et il demande `3 −` les fléchettes que la vision a rendues (origine `camera` ou `scan`, et en attente) ;
- pointe au bord d'une cible, dans un jeu dépendant de la position. Le test définit sa propre règle d'essai à `dependsOnPosition` (un disque fixe ; il ne dépend pas du lot G4). Observation de confiance haute, `sigmaAlong` 0,85 mm, `sigmaAcross` 0,37 mm : pointe à 0,3 mm à l'intérieur du bord, certitude `needsReview` ; même pointe à 5 mm à l'intérieur, `certain` ; même pointe au bord mais de source `tappedOnPhoto`, `certain`.

**Précisions de la réalisation (lot U3) et de l'intégration (vague 3).** Aucune signature imprimée ne change ; `ScanServiceFactory.live()` rend `LiveScanService()`.

- `LiveScanService` ne crée sa `ScanSession` que dans `start()` : construire le service ne touche aucun matériel. Il demande l'autorisation avant de démarrer la session (« non décidée » : une fois ; refusée **ou restreinte** par le contrôle parental ou la gestion de l'appareil : `.accessDenied`, faute d'un cas propre dans `CameraIssue` ; le texte de l'écran « caméra refusée » couvre les deux). Il lit `session.events` **avant** `start`, une seule fois, depuis une seule tâche, et le rediffuse à un flux neuf par appel de `events()`. Une erreur de `captureStill` qui n'est pas une `ScanServiceError` devient `.failed`.
- `CameraInputSource` lit `currentState()` après `arm` dans une tâche à part, lancée par `gameStarted`, et non dans sa tâche d'événements : le résultat est le même, les `stateChanged` qui suivent portent le statut dans un état calibré.
- Calibrage, étape 1 : le parcours appelle `camera.activate()`, qui appelle `start()` et revalide le calibrage enregistré, comme le demande le cycle de vie.
- Calibrage, étape 5 : le grade d'un aperçu est toujours `poor` (`VISION.md` §4.7) ; les barres « Alignement de la grille » de la maquette ne peuvent donc pas venir du grade avant « Valider ». Pendant le réglage, elles comptent les conseils géométriques de C1 (bloquant : 0 barre ; aucun : 3 ; un : 2 ; plus : 1). Après « Valider », le vrai grade s'affiche : « Calibrage précis » en vert, « correct » en ambre, « approximatif » en rouge, avec « Précision estimée ± x mm » et un conseil.
- Adoption : `adopt(_:lightingCheckPassed: true)` enregistre avec le calibrage la borne d'ombre mesurée par la vérification à une fléchette et `confidence.warmUpDarts = 0`, pour que le plafond de rodage ne revienne pas au lancement suivant ; un nouveau calibrage adopté sans vérification remet les deux à leur valeur par défaut. Seul un verdict `.verified` adopte avec `true`. Réinstaller le même calibrage n'appelle pas `setCalibration`, qui remettrait la vision à zéro (`VISION.md` §6.3, ligne 1). *Correction de l'intégration :* `adopt` et la revalidation envoyaient le calibrage avant sa configuration ; la sonde l'a montré sur la vraie session : après un redémarrage, un calibrage vérifié plafonnait de nouveau sa première fléchette à 0,84 (`warmUp`). La configuration part désormais en premier (`CameraFlowInstallOrderTests`, rouge sur l'ancien code).
- Mode photo : le bouton « En direct » de droite de la maquette n'a aucun comportement dans le texte. L'emplacement de droite porte la légende « Scanner » du déclencheur, le bouton de retour ramène au jeu, et « Importer une photo » et « Prendre une photo » sont des boutons secondaires du panneau (`DESIGN.md` §4).
- `CameraPreviewView` et la vignette : quand la vignette (colonne de l'écran de jeu) et `LiveScanView` sont à l'écran ensemble, deux `AVCaptureVideoPreviewLayer` partagent une `AVCaptureSession` ; que les deux montrent l'image dépend de la plateforme et reste à voir sur un appareil.
- Démarrage d'une partie sans calibrage : la source naît `.preparing` puis passe à `.needsCalibration`, et `PlayViewModel` joue `calibrationLost` à cette entrée (§8.6), à chaque partie lancée en mode caméra sans calibrage. Une source déjà à `.needsCalibration` à sa création ne le jouerait pas ; `CameraInputSource` naît toujours `.preparing`.
- Sonde d'intégration de la vague 3 (hors dépôt) : une `ScanSession` du lot V5 sur un film de synthèse, calibrée par `CalibrationFlowModel` et `BoardCalibrator` (grade « fair », 1,46 px/mm), à travers `LiveScanService`, `CameraModel` et `CameraInputSource`, jusqu'au `PlayViewModel` d'un Killer. Trois fléchettes lancées une à une deviennent S6, T10, D15 sur le tableau (« à vérifier » pendant le rodage), le joueur devient Killer ; le retrait passe au joueur suivant avec `endsTurnOnTakeout`, et ne fait que mettre le bouton en avant sans lui ou sur une volée courte ; une fléchette sous une ombre dure (0,20) sort au palier bas, attend la réponse du joueur (`pending`, feuille de correction, image de preuve de 600 px, fin de tour bloquée) puis est comptée ; une seconde partie sur la même caméra (`pause(.user)`, `setTrigger`, `arm`) compte ses trois fléchettes. La source de démonstration, calibrée puis armée, reste 8 s à `watching(0)` sans aucun événement de fléchette.

### 8.8 Mise en page adaptative et SwiftUI multiplateforme

**Mise en page de l'écran de jeu.** Une seule règle, fonction de la taille du conteneur (jamais de l'idiome de l'appareil) :

Fichier `DartKit/Sources/DartUI/Play/PlayLayout.swift` (lot U2, complet) :

```swift
import CoreGraphics

/// Layout of the play screen for a container size (never for a device idiom).
enum PlayLayout: Equatable {
    /// Header, current player, board, players, actions: one column (portrait).
    case stacked
    /// Board on the left over the full height, scrollable column on the right (landscape).
    case sideBySide

    static func resolve(for size: CGSize) -> PlayLayout {
        size.width > size.height ? .sideBySide : .stacked
    }
}
```

- La bascule utilise `AnyLayout(HStackLayout(…))` / `AnyLayout(VStackLayout(…))` pour garder l'identité des vues : la cible et l'aperçu caméra survivent à une rotation. *Réalisation (lot U2) :* l'écran de jeu range ses blocs dans un ordre différent selon la disposition (empilé : en-tête, cible, joueurs ; côte à côte : la cible, puis en-tête et joueurs) ; un seul `Layout` propre à quatre sous-vues (`PlayScreenLayout`) garde la même identité à la rotation, ce que deux `AnyLayout` ne pouvaient pas.
- *Réalisation (lot U2) :* la barre de navigation ne peut pas être masquée sur les deux plateformes (`ToolbarPlacement.navigationBar` n'existe pas sur macOS, et `#if os(iOS)` n'est permis que dans `PlatformShims`). Accueil, préparation, joueurs et réglages utilisent la barre du système (`navigationTitle`, bouton des réglages à l'accueil) ; la ligne d'en-tête des maquettes n'est dessinée que dans les instantanés.
- `stacked` : en-tête, carte du joueur courant avec ses trois cases, cible carrée (au plus 45 % de la hauteur), liste des joueurs défilante, barre d'actions fixée en bas.
- `sideBySide` : cible à gauche sur toute la hauteur ; à droite en-tête, joueur courant, joueurs, vignette caméra, actions (`PadPlayKiller`). C'est aussi la mise en page de l'iPhone en paysage.
- *Revue finale :* sous 560 pt de haut (un iPhone en paysage), la colonne de droite ne laissait aucune place aux joueurs dans les jeux à gabarit « score », et un bandeau de question recouvrait la carte du joueur courant ou la liste. Dans ce cas, `sideBySide` met la barre d'actions sous la cible, la carte du joueur courant perd son très grand nombre (la ligne du joueur le montre ; l'indice de finition ou le résumé de la volée passent sur la ligne « Au tour de »), la vignette caméra passe sous les joueurs, et le bandeau de question s'affiche sur la moitié basse de la cible, au-dessus de « Manqué ». À droite il ne reste que l'en-tête, la carte et les joueurs : deux joueurs, la grille du Cricket à deux ou trois lignes du Killer tiennent sans défiler. La décision se prend sur la taille du conteneur, comme toute la mise en page.
- Dimensions : `Theme.Metrics(horizontalSizeClass)`. Les seules entrées de mise en page sont `horizontalSizeClass` et la taille du conteneur (`GeometryReader` à la racine de l'écran).
- Gabarit : `descriptor.playStyle == .score` affiche `primary` du joueur courant en très grand (`PlayX01`, et la Tireuse avec la jauge `meter` du verre entamé dessous) ; `.board` donne la place à la cible (`PlayKiller`, et Football, Radar, Golf). Si `snapshot.grid` existe, la grille remplace la liste des joueurs (Cricket). `snapshot.objective` s'affiche dans l'en-tête (« Cible : D7 », « A 2 – 1 B », « Trou 4 / 9 · par 3 »).
- Cible : `DartboardView(highlights: snapshot.highlights, darts: …, geometry: game.descriptor.boardGeometry, …)`. Les marqueurs de fléchettes viennent de `game.turnRecords` : la position enregistrée quand elle existe, sinon `BoardGeometry.standard.centre(of: hit)`.
- Une information portée par la couleur est toujours doublée par un texte (`DESIGN.md` §1).

**Ce qui est interdit dans `DartUI`**, parce que cela ne compile pas sur macOS ou n'est plus fiable sur iOS 27 :

| Interdit | À la place |
|---|---|
| `navigationBarTitleDisplayMode`, `navigationBarHidden`, `navigationBarItems` | `.toolbarTitleDisplayMode(.inline)`, `.toolbar` |
| Emplacements `.topBarLeading`, `.topBarTrailing`, `.bottomBar` | `.barLeading`, `.barTrailing` (§8.4.4), `.principal`, `.confirmationAction`, `.cancellationAction` |
| `fullScreenCover` | `gameCover(item:content:)` |
| `Color(.systemBackground)` et tout `UIColor` | `Theme.Palette` |
| `Toggle`, `Slider`, `Stepper`, `Picker`, `List`, `Form`, `EditButton`, `Button` au style par défaut | composants de §8.4.2 ; `ScrollView` + `LazyVStack` dans les coquilles ; `ButtonStyle` écrit en SwiftUI |
| `UIApplication`, `UIScreen`, `UIDevice`, `UIViewRepresentable` hors des fichiers autorisés | adaptations de §8.4.4 |
| `AVCaptureSession.InterruptionReason` et toute API de capture propre à iOS hors des fichiers autorisés | `CaptureInterruptionObserver.issue(for:)` (§8.4.8) |
| Décision de mise en page sur l'idiome ou l'orientation de l'interface | classes de taille et taille du conteneur |
| `UIRequiresFullScreen`, verrouillage d'orientation | aucun : l'application est redimensionnable |
| `presentationSizing` (iOS 18), `navigationSubtitle` (iOS 26) | — |

Fichiers autorisés à contenir `#if os(iOS)` ou `#if canImport(UIKit)`, et eux seuls :

| Fichier | Lot | Ce qu'il isole |
|---|---|---|
| `Support/PlatformShims.swift` | U1 | couverture plein écran, écran maintenu allumé, emplacements de barre d'outils, ouverture des Réglages |
| `Camera/CameraPreviewView.swift` | U3 | `UIViewRepresentable` autour d'`AVCaptureVideoPreviewLayer` |
| `Camera/CaptureInterruptionObserver.swift` | U3 | la cause d'une interruption de capture : `AVCaptureSession.InterruptionReason` et la clé `AVCaptureSessionInterruptionReasonKey` sont indisponibles sur macOS (vérifié avec le SDK macOS 27.2). Sous `#if os(iOS)` il traduit la cause en `CameraIssue` ; ailleurs il rend `.failed` |

`#if canImport(AVFoundation)`, présent dans `Camera/ScanServicing.swift` pour `PreviewContent.captureSession`, n'est pas une condition de plateforme au sens de cette règle : AVFoundation existe sur macOS.

### 8.9 Localisation

- **Deux sources de texte.** Les textes du jeu (noms, options, lignes du tableau, légendes) arrivent en `LocalizedText` depuis `DartGames` ; ils s'affichent avec `LocalizedTextView`. Les textes propres à l'interface sont dans les tables `.strings` de `DartUI` et s'affichent avec `L10n.text(_:_:)`.
- **Trois tables, une par lot** : `Common.strings` (U1), `Game.strings` (U2), `Camera.strings` (U3), en `fr.lproj` et `en.lproj`. Jamais de String Catalog.
- **Contenu du squelette.** F0 crée chaque table avec une seule clé, la même dans les deux langues, pour que les six fichiers existent et que le test de parité passe dès la fondation : `"common.ok"` (« OK » / "OK") dans `Common`, `"play.nextPlayer"` (« Fléchettes retirées, suivant » / "Darts removed, next") dans `Game`, `"calibration.validate"` (« Valider » / "Confirm") dans `Camera`. Chaque fichier tient en une ligne, `"clé" = "valeur";`. Le lot propriétaire garde, renomme ou remplace cette clé ; seule `"common.ok"` est lue par du code du squelette, l'écran d'essai `skeleton` (§8.4.10), que le lot U1 remplace lui aussi.
- **Les jeux n'ajoutent aucune clé.** Tout ce qu'un jeu fait lire, y compris pour les quatre jeux du lot G4, arrive en `LocalizedText` : noms, phrases courtes de l'accueil (« Remplir des verres », « Deux camps, un ballon », « Cibles rondes à détruire », « Le moins de coups »), libellés d'options (§5.3), titres, badges (« A », « Par »), objectifs (« Trou 4 / 9 · par 3 »), légendes. Ces textes sont écrits dans `DartGames`, dans les deux langues. Les trois tables de `DartUI` ne contiennent que les libellés de l'interface elle-même : l'ajout d'un jeu ne les touche pas. Les seuls libellés d'interface que cette version ajoute sont celui de l'action « Photo » de l'écran de jeu (table `Game`, lot U2) et ceux de l'écran de revue vide et de ses causes (table `Camera`, lot U3) ; chaque lot choisit ses clés.
- **Clés symboliques** en anglais, de la forme `écran.élément` : `"play.nextPlayer"`, `"setup.start"`, `"calibration.advice.resolutionLow"`. Pas de phrase utilisée comme clé.
- **Paramètres** : `L10n.text("play.round \(round) \(limit)", .game)` cherche la clé `"play.round %lld %lld"`.
- **Pluriels** : deux clés choisies dans le code (`"players.count.one"`, `"players.count.other"`). Pas de `.stringsdict`.
- **Langue de l'interface** : `app.language` vaut `settings.language`, sinon `AppLanguage(preferredLanguages: Locale.preferredLanguages)`. La racine applique `.appLanguage(_:)`, qui règle ensemble `\.appLanguage` et `\.locale` : les deux sources de texte sont ainsi toujours dans la même langue. Vérifié sous `ImageRenderer`.
- **Langue de la voix** : `settings.audio.callerLanguage`, indépendante de celle de l'interface.
- **Test obligatoire** (lot U1, `KernelL10nParityTests`, dans `Kernel/KernelL10nParityTests.swift`) : pour chaque table, les fichiers `fr` et `en` ont exactement les mêmes clés, et aucune valeur n'est vide. Le test lit les fichiers avec `L10n.bundle.url(forResource:withExtension:subdirectory:localization:)` puis `NSDictionary(contentsOf:)`.
- Côté application : `CFBundleLocalizations: [fr, en]` dans l'Info.plist (§9.3) déclare les deux langues de l'application. Les textes du paquet, eux, suivent `\.locale`, que la racine règle d'après `app.language` : dans un essai du lot X1 (une application en ligne de commande pour macOS avec les mêmes clés, le même `en.lproj` et le même paquet de ressources), retirer la clé ne changeait la langue ni en français, ni en anglais, ni en allemand. La clé est gardée ; son effet sur iOS n'est pas vérifié.

### 8.10 Persistance

Tout passe par `AppStorage` (§8.4.5), en JSON, dans `UserDefaults`. Les volumes sont petits (quelques kilo-octets).

| Clé | Contenu | Écrit quand |
|---|---|---|
| `settings.v1` | `AppSettings` (son, mode d'entrée, mode de scan, langue, fin de tour automatique) | à chaque changement d'un réglage |
| `roster.v1` | `[Player]` | à chaque modification de la liste des joueurs |
| `setup.<gameID>.v1` | `SetupMemory` : derniers joueurs et options de ce jeu | au lancement d'une partie |
| `calibrations.v1` | `[StoredCalibration]`, un par (caméra, rotation, taille d'image) | à l'adoption d'un calibrage, à un recalage, après la vérification à une fléchette |
| `match.current.v1` | `MatchRecord` de la partie en cours ou de la partie finie dont les résultats sont affichés, positions des fléchettes comprises | après chaque entrée acceptée, annulation ou correction ; effacé par `finishGame()` quand l'écran des résultats est quitté, ou par `closeGame(discard: true)` (§8.6) |

- Une partie interrompue (application fermée) se reprend depuis l'accueil : `AppModel.resumableMatch`, puis `registry.restoreMatch`. Une partie finie mais pas encore quittée se rouvre sur ses résultats.
- `StoredCalibration` contient un `BoardCalibration` entier : sa forme `Codable` porte tous ses champs, dont `wireHeight` (`VISION.md` §9.2).
- Les images de référence de la vision ne sont jamais enregistrées (`VISION.md` §4.10).
- Un blob illisible rend la valeur par défaut ; il ne bloque jamais le lancement.
- Le suffixe `.v1` fait partie de la clé : un changement de format incompatible prend un nouveau suffixe. `AppSettings` et les autres valeurs utilisent le `Codable` synthétisé : **ajouter un champ est un changement incompatible** (un blob de l'ancienne forme ne se lit plus et rend la valeur par défaut, `KernelStorageTests`). Une version qui ajoute un réglage prend donc un nouveau suffixe, ou écrit un décodeur tolérant dans le même changement.

### 8.11 SnapshotTool

Fichier `DartKit/Sources/SnapshotTool/SnapshotTool.swift` (complet) :

```swift
#if os(macOS)
import AppKit
import SwiftUI
import DartCore
import DartUI

/// Renders every screen of `SnapshotCatalog` to PNG, in both languages.
/// Usage: swift run SnapshotTool [--out <directory>] [--lang fr|en] [--only <screen id>]
@main
struct SnapshotTool {
    @MainActor
    static func main() throws {
        var output = URL(fileURLWithPath: "build/snapshots")
        var languages = AppLanguage.allCases
        var only: String?
        var arguments = CommandLine.arguments.dropFirst().makeIterator()
        while let argument = arguments.next() {
            switch argument {
            case "--out": if let value = arguments.next() { output = URL(fileURLWithPath: value) }
            case "--lang": if let value = arguments.next(), let language = AppLanguage(rawValue: value) { languages = [language] }
            case "--only": only = arguments.next()
            default: FileHandle.standardError.write(Data("unknown argument: \(argument)\n".utf8)); exit(2)
            }
        }
        var failures = 0
        for language in languages {
            let directory = output.appendingPathComponent(language.rawValue)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            for screen in SnapshotCatalog.all where only == nil || screen.id == only {
                for device in screen.devices {
                    let view = SnapshotCatalog.framed(screen.make(device), device: device, language: language)
                    let renderer = ImageRenderer(content: view)
                    renderer.proposedSize = ProposedViewSize(device.size)
                    renderer.scale = 2
                    let file = directory.appendingPathComponent("\(screen.id)@\(device.rawValue).png")
                    guard let image = renderer.cgImage,
                          let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
                        FileHandle.standardError.write(Data("render failed: \(file.lastPathComponent)\n".utf8))
                        failures += 1
                        continue
                    }
                    try png.write(to: file)
                    print(file.path)
                }
            }
        }
        exit(failures == 0 ? 0 : 1)
    }
}
#else
@main
struct SnapshotTool {
    static func main() {}
}
#endif
```

Usage, depuis `DartKit/` :

```
swift run SnapshotTool --out ../build/snapshots            # tous les écrans, fr et en
swift run SnapshotTool --out ../build/snapshots --lang fr --only play-killer
```

Les fichiers sortent en `build/snapshots/<langue>/<id>@<appareil>.png`, à l'échelle 2.

Contraintes d'`ImageRenderer`, qui dictent la règle « coquille / contenu » de §8.3. Elles ont été constatées sur macOS avec Xcode 27.2, en rendant une vue d'essai :

| Se rend correctement | Ne se rend pas (vide ou pictogramme d'interdiction) |
|---|---|
| `Text`, formes, `Canvas`, `Image(systemName:)`, matériaux | `ScrollView` (son contenu disparaît) |
| piles, `Grid`, `LazyVGrid`, `LazyVStack`, `ViewThatFits`, `GeometryReader` | `Toggle`, `Slider`, `Picker`, `TextField` |
| `Button` avec un `ButtonStyle` écrit en SwiftUI, ou `.buttonStyle(.plain)` | `Button` avec le style par défaut |
| `onTapGesture` | `NavigationStack`, `List` (d'après la documentation d'Apple ; non essayés) |

Conséquences :

- un `XxxContent` ne contient ni défilement, ni navigation, ni contrôle système ; c'est `XxxScreen` qui les ajoute. Trois contenus ont un drapeau que seule l'application lève, faux par défaut : `PlayContent.scrollsPlayers`, `ResultsContent.scrolls` et `PlayCorrectionContent.scrolls` ;
- **tout `Button` de `DartUI` porte un `ButtonStyle` écrit en SwiftUI** (ceux de §8.4.2) ou `.buttonStyle(.plain)` ;
- un champ de saisie (nom d'un joueur) n'existe que dans une coquille ; le contenu affiche le texte ;
- un écran caméra se rend avec `PreviewContent.image` : une image synthétique (`SyntheticScene().render(camera:)`) une fois le lot V1 livré.

Liste des instantanés à produire, avec leurs données d'exemple :

| Id | Appareils | Données d'exemple |
|---|---|---|
| `skeleton` | `phonePortrait` | écran d'essai du lot F0 (§8.4.10), seul instantané du squelette ; il DOIT disparaître en vague 1, quand le lot U1 livre les siens |
| `board-plain`, `board-zones`, `components` | `phonePortrait` | cible nue ; zones de Killer à 4 joueurs ; tous les composants |
| `board-discs` | `phonePortrait` | cible en géométrie `.standard` avec les cinq disques de Radar du vecteur RAD-1 (graine 1) : `(-80, 95, 40)`, `(70, -65, 40)`, `(110, 65, 28)`, `(25, 15, 28)`, `(140, 0, 16)`, étiquettes « +10 », « +10 », « +20 », « +20 », « +50 », points de vie 3, 3, 2, 2, 1 |
| `home` | `phonePortrait`, `padLandscape` | registre complet (quatorze cartes, dans l'ordre du registre), caméra calibrée |
| `setup-killer` | `phonePortrait` | 4 joueurs, niveau Facile ; une variante à 7 joueurs (Facile grisé) |
| `setup-x01` | `phonePortrait` | 2 joueurs |
| `players` | `phonePortrait` | 4 joueurs |
| `play-killer` | les quatre | Killer Facile, 4 joueurs, manche 4, deux fléchettes dont une « à vérifier » |
| `play-x01` | `phonePortrait`, `padLandscape` | 501 double out, 24 restants |
| `play-cricket` | `phonePortrait` | 3 joueurs, grille partiellement fermée |
| `play-highscore` | `phonePortrait` | partie réelle jouée par le moteur |
| `play-beertap` | `phonePortrait` | Tireuse, 2 joueurs, verre de 50 cl : 3 verres pleins, verre entamé à 40 sur 50 (jauge), cible sans surbrillance |
| `play-football` | `phonePortrait` | Football, 4 joueurs, camp A au tir, « A 2 – 1 B », ballon à `+1` : moitié droite et bull à viser, moitié gauche à éviter, badges « A » et « B » |
| `play-radar` | `phonePortrait`, `padLandscape` | Radar, 2 joueurs, les cinq disques de `board-discs` dont un entamé, cible en géométrie `.standard`, deux fléchettes posées à leur position |
| `play-golf` | `phonePortrait` | Golf, 2 joueurs, « Trou 4 / 9 · par 3 » : double et triple du 4 à viser (« 1 », « 2 »), simple en secondaire (« 3 »), badges « −2 » et « +3 » |
| `correction` | `phonePortrait` | fléchette T19 « à vérifier », six propositions |
| `results` | `phonePortrait`, `padLandscape` | Killer à 4 joueurs terminé ; une variante Football à 4 joueurs, avec le titre « Le camp A gagne » à la place du nom |
| `settings` | `phonePortrait` | réglages par défaut |
| `camera-denied`, `placement-guide` | `phonePortrait` ; aussi `padLandscape` (`camera-denied`) et `padPortrait` (`placement-guide`) | — |
| `camera-unavailable` | `phonePortrait` | « Pas de caméra disponible », avec « Continuer en saisie manuelle » |
| `calibration` | `phonePortrait`, `padLandscape` | image synthétique, quatre poignées, alignement « Correct » avec un conseil (avant « Valider » : voir §8.7, étape 5) |
| `calibration-proof` | `phonePortrait`, `padLandscape` | le même calibrage validé : grade « fair » avec un conseil, vue de preuve, test au toucher |
| `live-scan` | `phonePortrait`, `padLandscape` | image synthétique, deux pointes étiquetées dont une « ? » |
| `scan-thumbnail` | `padLandscape`, `phoneLandscape` | l'écran de jeu du Killer (`GameFlowFixtures.killerInRound4()`) avec la vignette caméra ; en largeur compacte, la vignette est une bande de 64 pt |
| `photo-mode` | `phonePortrait`, `padLandscape` | dernière photo : T20, T19, S7 |
| `photo-mode-no-camera` | `phonePortrait` | la variante sans caméra, où seul « Importer une photo » est actif |
| `photo-review-empty`, `photo-tips` | `phonePortrait` | revue d'un scan vide, avec sa cause ; pointes touchées sur une photo importée |

Tant que les règles d'un jeu ne sont pas livrées, son instantané utilise un `GameSnapshot` écrit à la main (c'est une simple valeur). Le lot I1 remplace ces valeurs par des parties réellement jouées par les moteurs. Les quatre instantanés `play-beertap`, `play-football`, `play-radar` et `play-golf` appartiennent au lot U2, comme les autres écrans de partie ; `board-discs` au lot U1.

**État après le lot I1.**

- **Plus aucun `GameSnapshot` écrit à la main.** Chaque partie affichée est jouée par son moteur, avec une graine et des identifiants fixes. Le lot U2 l'avait déjà fait pour ses écrans.
- **Six écrans de partie ajoutés** par le lot I1 dans `GameFlowSnapshots.swift` : `play-shanghai`, `play-moonlanding`, `play-fight`, `play-conqueror`, `play-aroundtheclock` et `play-halveit`. Les quatorze jeux ont donc chacun leur instantané.
- **Le scan en direct** (`live-scan`) prend son joueur, son score et ses cases dans le X01 de `play-x01`. Ses deux fléchettes sont posées aux pointes dessinées sur l'image de synthèse.
- **Appareils.** Tout écran de l'application se rend sur `phonePortrait` et sur au moins un iPad : `padLandscape`, ou `padPortrait` pour `setup-killer`, `settings` et `placement-guide`.
- **Exceptions** :
  - les quatre planches du socle (`board-plain`, `board-zones`, `board-discs`, `components`) ne sont pas des écrans et restent sur `phonePortrait` ;
  - `scan-thumbnail` reste sur `padLandscape` et `phoneLandscape`, car la vignette n'existe que dans la mise en page côte à côte.
- **Total** : `SnapshotTool` écrit 78 PNG par langue, contre 51 en vague 3, soit 156 pour les deux langues.

---

## 9. Coquille iOS (`App/`)

### 9.1 Point d'entrée

Fichier `App/DartScannerApp.swift` (complet) :

```swift
import SwiftUI
import DartUI

@main
struct DartScannerApp: App {
    var body: some Scene {
        WindowGroup {
            DartScannerRootView()
        }
    }
}
```

La coquille ne contient rien d'autre : ni vue, ni logique, ni chaîne.

### 9.2 Catalogue de ressources

- `App/Assets.xcassets/Contents.json` : `{ "info" : { "author" : "xcode", "version" : 1 } }`.
- `AppIcon.appiconset/Contents.json`, une seule image de 1024 px :

```json
{
  "images" : [
    { "filename" : "AppIcon-1024.png", "idiom" : "universal", "platform" : "ios", "size" : "1024x1024" }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
```

- `AppIcon-1024.png` : PNG opaque de 1024 × 1024 (une cible stylisée sur fond `#0E1114`). Le lot X1 le produit.
- `AccentColor.colorset/Contents.json` : la couleur `accent` de `DESIGN.md`, `#FFA630` :

```json
{
  "colors" : [
    { "idiom" : "universal",
      "color" : { "color-space" : "srgb", "components" : { "red" : "1.000", "green" : "0.651", "blue" : "0.188", "alpha" : "1.000" } } }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
```

- `App/en.lproj/InfoPlist.strings` :

```
"NSCameraUsageDescription" = "The camera is used to read where your darts land on the board.";
"CFBundleDisplayName" = "Dart Scanner";
```

### 9.3 Projet XcodeGen et clés d'Info.plist

Fichier `project.yml` (construit avec XcodeGen 2.46 et Xcode 27.2 pour le simulateur iPhone 17) :

```yaml
name: DartScanner
options:
  bundleIdPrefix: com.example
  deploymentTarget:
    iOS: "17.0"
  developmentLanguage: fr
  createIntermediateGroups: true
configFiles:
  Debug: Config/Base.xcconfig
  Release: Config/Base.xcconfig
settings:
  base:
    SWIFT_VERSION: "5.0"
    MARKETING_VERSION: "1.0.0"
    CURRENT_PROJECT_VERSION: "1"
    CODE_SIGN_STYLE: Automatic
packages:
  DartKit:
    path: DartKit
targets:
  DartScanner:
    type: application
    platform: iOS
    sources:
      - path: App
    dependencies:
      - package: DartKit
        product: DartUI
    info:
      path: App/Info.plist
      properties:
        CFBundleDisplayName: Dart Scanner
        CFBundleShortVersionString: $(MARKETING_VERSION)
        CFBundleVersion: $(CURRENT_PROJECT_VERSION)
        CFBundleLocalizations: [fr, en]
        NSCameraUsageDescription: "La caméra sert à lire la position des fléchettes sur la cible."
        UILaunchScreen: {}
        UIApplicationSceneManifest:
          UIApplicationSupportsMultipleScenes: false
        UISupportedInterfaceOrientations:
          - UIInterfaceOrientationPortrait
          - UIInterfaceOrientationLandscapeLeft
          - UIInterfaceOrientationLandscapeRight
        UISupportedInterfaceOrientations~ipad:
          - UIInterfaceOrientationPortrait
          - UIInterfaceOrientationPortraitUpsideDown
          - UIInterfaceOrientationLandscapeLeft
          - UIInterfaceOrientationLandscapeRight
        ITSAppUsesNonExemptEncryption: false
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: $(DART_SCANNER_BUNDLE_ID)
        TARGETED_DEVICE_FAMILY: "1,2"
        ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon
        ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME: AccentColor
        SUPPORTS_MACCATALYST: NO
        SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD: NO
        SUPPORTS_XR_DESIGNED_FOR_IPHONE_IPAD: NO
        ENABLE_PREVIEWS: YES
```

Fichier `Config/Base.xcconfig` :

```
// Shared build settings. Config/Local.xcconfig is optional and git-ignored; for a device it holds:
//   DEVELOPMENT_TEAM = ABCDE12345
//   DART_SCANNER_BUNDLE_ID = fr.yourname.dartscanner
DART_SCANNER_BUNDLE_ID = com.example.dartscanner
#include? "Local.xcconfig"
```

| Clé d'Info.plist | Valeur | Raison |
|---|---|---|
| `NSCameraUsageDescription` | texte français ; l'anglais est dans `InfoPlist.strings` | obligatoire : sans elle, le système ferme l'application au premier accès à la caméra |
| `CFBundleLocalizations` | `fr`, `en` | déclare les deux langues de l'application (§8.9) |
| `UILaunchScreen` | dictionnaire vide | obligatoire pour l'App Store et pour le redimensionnement |
| `UIApplicationSceneManifest` / `UIApplicationSupportsMultipleScenes` | `false` | une seule fenêtre : une seule session de capture |
| `UISupportedInterfaceOrientations` | portrait, paysage gauche, paysage droit | iPhone |
| `UISupportedInterfaceOrientations~ipad` | les quatre | iPad, condition du multitâche |
| `ITSAppUsesNonExemptEncryption` | `false` | évite la question à chaque envoi |

- Pas de clé de microphone, pas de `UIRequiresFullScreen`, pas de mode d'arrière-plan.
- `xcodegen generate` réécrit `App/Info.plist` à chaque fois : ce fichier et `DartScanner.xcodeproj` ne sont pas suivis par git.
- Le mode de langage du paquet vient de son propre manifeste, pas du `SWIFT_VERSION` de l'application.

### 9.4 Signature

- Les constructions pour le Simulateur n'ont besoin d'aucune équipe.
- Pour un appareil réel, le propriétaire crée `Config/Local.xcconfig` (non suivi par git) avec deux lignes, `DEVELOPMENT_TEAM = XXXXXXXXXX` et `DART_SCANNER_BUNDLE_ID = fr.votrenom.dartscanner` (question 2, §15). `project.yml` lit l'identifiant dans la variable `DART_SCANNER_BUNDLE_ID`, que `Config/Base.xcconfig` met à `com.example.dartscanner` avant d'inclure `Local.xcconfig` : la ligne locale l'emporte, sans toucher `project.yml` (lot I1 ; avant, l'identifiant était écrit en dur dans la cible et `Local.xcconfig` ne pouvait pas le changer).
- `DEVELOPMENT_TEAM` et l'identifiant ne doivent pas être écrits en clair dans les réglages de la cible de `project.yml` : un réglage de la cible l'emporte sur le fichier de configuration.

---

## 10. Flux de données

Dans les trois schémas, la colonne de gauche indique le fil d'exécution.

### 10.1 Une fléchette vue par la caméra arrive au tableau de score et au haut-parleur

```
file de capture     AVCaptureVideoDataOutput
(= file série de      │ CMSampleBuffer (32BGRA)
 ScanSession)         ▼
                    CameraFrameSource ── Frame (valide pendant l'appel seulement)
                      ▼
                    ScanEngine.process(frame)
                      ├─ MotionGate            chaque image : y a-t-il du mouvement ?
                      ├─ ScanStateMachine      réducteur pur : motion → settling → analysing
                      └─ sur une scène immobile seulement :
                           BoardRectifier → DifferencingDartDetector → ConfidenceModel
                      ▼
                    [ScanEvent.dart(DartObservation)]  →  ScanSession.events (AsyncStream)
──────────────────────────────────────────────────────────────────────────────────────────
fil principal       CameraInputSource          for await event in service.events()
(@MainActor)          │ DartInputEvent.dart(DartProposal(observation:thresholds:))
                      ▼
                    PlayViewModel.receive(proposal)
                      │ certainty = proposal.certainty(match)
                      │      = observation.tier(collapsingBy: { match.effectKey(for: $0, position: observation.tip) })
                      │        (jeu dépendant de la position : « certain » devient « needsReview » au bord d'une cible, §8.4.8)
                      ├─ undecided ──► pending ; son « à vérifier » ; fiche de correction ; RIEN n'est compté
                      └─ certain / needsReview
                           ▼
                         match.throwDart(DartRecord(id: observation.id, hit, position: observation.tip, origin: .camera, needsReview))
                           │   GameMatch → engine.apply(.dart(hit), position:) → TurnBasedEngine → règles du jeu
                           │   (seul un jeu dépendant de la position lit la position : context.impact)
                           ▼
                         InputOutcome.accepted([GameEvent])   et   match.snapshot mis à jour
                           ├─► SwiftUI (Observation) : tableau de score, cible, cases de la volée
                           ├─► CueMapping.cues(for: events, context:)  ─►  SoundPlaying.play(cues)
                           │        ├─ effets     : AVAudioEngine              (file série audio)
                           │        ├─ annonce    : AVSpeechSynthesizer        (fil principal)
                           │        └─ vibration  : UIFeedbackGenerator, iPhone (fil principal)
                           ├─► AppStorage.saveCurrentMatch(match.record)
                           └─► si le tour est clos par la règle, ou la partie finie sur cette fléchette :
                                 source.turnClosed()  →  file de commandes  →  ScanCommand.endVisit
```

Une fléchette posée au doigt suit le même chemin à partir de `PlayViewModel.receive` : `DartboardView` rend un `BoardTap` (case et position nominale), et `tapBoard` appelle `receive(.manual(tap.hit, position: tap.position))`.

Délai attendu entre l'arrêt des vibrations de la cible et l'annonce : 0,3 à 0,45 s côté vision (`VISION.md` §6.2), plus un cycle d'affichage.

### 10.2 Une correction manuelle

```
fil principal       Le joueur touche une case de la volée, ou la fiche « ? » d'une fléchette en attente
                      ▼
                    CorrectionSheet(game:target:)
                      ├─ propositions : proposal.choices, ou la case courante et ses voisines
                      ├─ image de preuve : source.evidenceImage(for: id)        (file de la session, puis retour)
                      └─ réticule déplacé : source.rescore(id, tip:) → proposition recalculée
                      ▼
          ┌─ fléchette déjà comptée :  PlayViewModel.correctDart(at:to:position:)
          │        ▼
          │     match.replaceDart(at:with:position:)
          │        │  position : celle du réticule ou du tap ; nil pour une case prise dans la liste (l'ancienne est effacée)
          │        │  le journal est modifié, puis TOUTE la partie est rejouée depuis un moteur neuf, positions comprises ;
          │        │  une fléchette qui arrive hors phase « throwing » pendant le rejeu est retirée
          │        ▼
          │     EditOutcome(applied, dropped)   et   match.snapshot mis à jour
          │
          ├─ fléchette fantôme :       PlayViewModel.removeDart(at:)  →  match.removeDart(at:)
          │                            puis source.dartDiscarded(id)  →  ScanCommand.discardDart
          │
          └─ fléchette en attente :    PlayViewModel.resolvePending(with: hit ou nil)
                                       hit : match.throwDart(…) comme en 10.1 ; nil : source.dartDiscarded(id)
                      ▼
                    Dans tous les cas : aucun événement passé n'est rejoué (pas de son de fléchette) ;
                    son « correctionApplied » ; sauvegarde ; resynchronisation de la source :
                      phase throwing               → source.turnBegan(expectedDarts: 3 − n)  →  ScanCommand.beginVisit
                      phase turnComplete, finished → source.turnClosed()                     →  ScanCommand.endVisit
                    À la confirmation du tour, la vision apprend le résultat :
                      source.turnConfirmed([DartFeedback(id, wasCorrected)])  →  ScanSession.recordFeedback
```

### 10.3 La fin d'un tour et la fin de la partie

```
file de la session  (facultatif) les fléchettes sont retirées : ScanEvent.takeoutCompleted
fil principal         ▼
                    DartInputEvent.boardCleared
                      ├─ réglage « fin de tour automatique » actif ET phase turnComplete ET rien en attente → endTurn()
                      └─ sinon : le bouton « Fléchettes retirées, suivant » est mis en avant (une PROPOSITION)

                    Le joueur appuie sur « Fléchettes retirées, suivant »
                      ▼
                    PlayViewModel.requestEndTurn()
                      ├─ une fléchette attend une réponse      → bouton inactif (canEndTurn == false)
                      ├─ volée de moins de 3 fléchettes, et descriptor.confirmsShortTurn
                      │                                         → prompt .confirmShortTurn, puis endTurn()
                      └─ sinon (dont toute volée courte au Golf) → endTurn()
                      ▼
                    PlayViewModel.endTurn()
                      1. source.turnConfirmed(feedback)         une ligne par fléchette de la caméra
                      2. match.endTurn()                        entrée « endTurn » du journal
                           noyau : [clôture du tour si besoin] → joueur suivant non éliminé
                                   → fin de manche ? limite atteinte ? → début du tour
                                     (retirage du Killer expert, cibles mobiles de Radar)
                           ▼
                         accepted([turnCompleted?, roundStarted?, zoneChanged? ou blobsMoved?, turnStarted])
                         ou accepted([…, gameFinished(.roundLimit)])
                      3. match.snapshot → SwiftUI ; CueMapping → « Au tour de Tom »
                      4. AppStorage.saveCurrentMatch(match.record)
                      5. phase throwing : source.turnBegan(expectedDarts: 3)  →  ScanCommand.beginVisit
                         phase finished : source.turnClosed()                 →  ScanCommand.endVisit ; ResultsContent

                    Partie finie (sur une fléchette, 10.1, ou à la limite de manches, ci-dessus) :
                    ResultsContent est affiché ; la partie reste sauvegardée et corrigible (undo, correctDart).

                    Le joueur quitte les résultats : « Revanche » ou « Changer de jeu »
                      ▼
                    AppModel.rematch() ou AppModel.closeGame(discard:)
                      ▼
                    PlayViewModel.finishGame()
                      1. source.turnConfirmed(feedback du tour gagnant)   omis si le tour courant est vide
                      2. source.gameEnded()                               →  ScanCommand.pause(.user)
                      3. AppStorage.saveCurrentMatch(nil)
```

Le tour ne passe jamais au joueur suivant sans l'entrée `endTurn` (`GAMES.md` §2.4). Seul le réglage `endsTurnOnTakeout` permet à la caméra de la produire, quand le tour est déjà clos et qu'aucune fléchette n'attend de réponse ; il est désactivé par défaut (question 1, §15).

---

## 11. Règles de concurrence

Le paquet est en mode Swift 5 avec `StrictConcurrency` : une faute de concurrence est un avertissement, et un lot se livre sans avertissement.

| Zone | Isolation | Règle |
|---|---|---|
| `DartCore`, `DartGames` | aucune : valeurs `Sendable` | Pas d'acteur, pas de verrou, pas d'état global modifiable, pas d'horloge. Un `GameMatch` se copie librement. |
| Cœur de `DartVision` piloté par `ScanEngine` (porte, réducteur, redresseur, détecteur) | confiné à la file série de `ScanSession` | `ScanEngine` n'est pas sûr entre fils. Un `Frame` n'est valide que pendant l'appel qui le livre : il n'est jamais gardé ni envoyé ailleurs. |
| Capture | la file passée à `FrameSource.start(on:handler:)`, qui est celle de la session | `startRunning()`, la configuration de la session et la livraison des images se font sur cette file. Jamais sur le fil principal. |
| `ScanSession` | API `async` appelable de partout | Les événements sortent par `AsyncStream<ScanEvent>`. |
| `DartUI` | `@MainActor` | Tous les modèles de vue sont `@MainActor @Observable final class`. Les façades `ScanServicing`, `DartInputSource` et `SoundPlaying` sont `@MainActor`. |
| Calculs lourds lancés par `DartUI` | `Task.detached(priority: .userInitiated)` | `BoardCalibrator.calibrate`, `ColourBoardLocator.locate`, `BoardRectifier.rectify`, `PhotoScorer` : entrées et sorties `Sendable`. `BoardCalibrator.preview` reste sur le fil principal. |
| `DartAudio` | façade `@MainActor` | `AVAudioEngine` et `AVAudioSession` ne sont touchés que sur la file série privée d'`AudioDirector` (`setActive` est bloquant). `AVSpeechSynthesizer` et les générateurs de vibration sont sur le fil principal. Les observateurs de notifications repassent par cette file. |
| Persistance | `KeyValueStoring` est `Sendable` | Écritures depuis le fil principal ; les blobs sont petits. |

Règles communes :

- **Un flux, une tâche.** Chaque `AsyncStream` est lu par un seul `for await`, dans une tâche liée à la vie de l'écran (`.task { await game.run(…) }`) ou gardée et annulée par le modèle qui l'a créée. `events()` rend un flux neuf à chaque appel.
- **L'ordre des fléchettes est celui du flux.** `PlayViewModel` traite les événements un par un sur le fil principal ; il ne lance pas de tâche par fléchette.
- **Le jeu n'attend jamais, et n'a rien à attendre.** Les commandes de `DartInputSource` (`turnBegan`, `turnClosed`, `dartDiscarded`…) et les appels au son sont **synchrones** : `PlayViewModel`, synchrone lui aussi, les appelle directement et ne crée aucune tâche pour eux.
- **Jamais une tâche par commande.** Envoyer chaque commande dans son propre `Task { await service.send(…) }` laisserait l'ordre de `endVisit`, `beginVisit` et `discardDart` au hasard de l'ordonnanceur, et un croisement désynchroniserait les compteurs de volée de la vision. `CameraModel` tient donc **la** file unique (`enqueue(_:)`, `enqueueFeedback(_:wasCorrected:)`) : un `AsyncStream`, lu par **une** tâche qui attend `service.send` avant de prendre la suivante (§8.7). Tous les écrivains y passent : les `CameraInputSource`, `PhotoModeView`, le parcours de calibrage et `CameraModel.setForeground` (`pause` puis `resume`). Aucun autre code de `DartUI` n'appelle `service.send`.
- **Les requêtes restent `async`.** `evidenceImage(for:)` et `rescore(_:tip:)` rendent une valeur : l'écran de correction les attend dans sa propre tâche, sans effet sur l'ordre des commandes.
- **Interdits** : `DispatchQueue.main.sync`, `Thread.sleep`, sémaphores, `nonisolated(unsafe)`, `Task.detached` qui capture un modèle de vue.
- **`@unchecked Sendable`** n'est admis que pour : les types listés par `VISION.md` §9.2 (`Frame`, `ScanSession`, les sources d'images, `DirectoryRecorder`), `UserDefaultsStore`, `InMemoryStore` (protégé par un verrou) et `PreviewContent`.

Ce qui est `Sendable` par construction : tous les types de `DartCore`, `ImpactPoint` compris ; `DartObservation`, `ScanEvent`, `ScanCommand`, `BoardCalibration`, `RGBImage`, `VisionConfiguration` ; `AudioCue`, `AudioSettings` ; `DartProposal`, `DartInputEvent`, `AppSettings`, `StoredCalibration`.

---

## 12. Stratégie de test et commandes

Tous les tests sont en Swift Testing (`import Testing`, `@Test`, `#expect`, `#require`) et tournent sur macOS par `swift test`. Jamais XCTest. Tout aléa de test vient de `SeededRandom` avec une graine fixe.

### 12.1 Par cible

Fichier `DartKit/Sources/DartTestSupport/VectorDSL.swift` (complet) : le petit langage qui rend les vecteurs de `GAMES.md` §2.11 lisibles tels quels.

```swift
import Foundation
import DartCore

/// `count` players named J1…Jn, with stable identifiers (GAMES.md §2.3).
public func testPlayers(_ count: Int) -> [Player] {
    (0..<count).map { index in
        Player(id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", index + 1)) ?? UUID(), name: "J\(index + 1)")
    }
}

extension GameRegistry {
    /// A game for a test vector: `try registry.match(.x01, ["outRule": "double"], players: 2, seed: 0)`.
    public func match(_ game: GameID, _ options: GameOptions = [:], players: Int, seed: UInt64 = 0) throws -> GameMatch {
        try makeMatch(GameConfiguration(gameID: game, options: options, players: testPlayers(players), seed: seed))
    }

    /// Games of this registry whose rules are not delivered yet: creating one throws `.unknownGame` (the skeleton
    /// of ARCHITECTURE.md §5.3). Probed with the default options and the smallest allowed number of players.
    public var skeletonGames: [GameID] {
        definitions.compactMap { definition in
            let descriptor = definition.descriptor
            let players = descriptor.playerRange(for: descriptor.defaultOptions).lowerBound
            do {
                _ = try match(descriptor.id, players: players)
                return nil
            } catch let error as GameConfigurationError {
                if case .unknownGame = error { return descriptor.id }
                return nil
            } catch {
                return nil
            }
        }
    }

    /// Definitions whose rules are delivered, in registry order. A test that runs "on every game of the registry"
    /// iterates THIS list, so that it passes while the games of other lots are still skeletons.
    public var deliveredDefinitions: [GameDefinition] {
        let skeletons = Set(skeletonGames)
        return definitions.filter { !skeletons.contains($0.id) }
    }
}

extension GameMatch {
    /// Plays a script written as in GAMES.md §2.11: "," separates darts, "|" is an `endTurn`, "×3" repeats a dart,
    /// and `S6@(124.0, 0.0)` is a dart with a recorded position in board millimetres (without "@": no position).
    /// `match.play("T20, S5, MISS | MISS ×3 |")` returns one outcome per input, in order.
    /// Traps on a notation that `Hit(notation:)` cannot read or on an unreadable position: a typo in a vector
    /// must not pass silently. Negative coordinates use the ASCII minus sign.
    @discardableResult
    public mutating func play(_ script: String) -> [InputOutcome] {
        var outcomes: [InputOutcome] = []
        var token = ""
        // Inside "@( … )" the comma separates x from y, not two darts.
        var depth = 0

        func flush(_ match: inout GameMatch) {
            let text = token.trimmingCharacters(in: .whitespacesAndNewlines)
            token = ""
            guard !text.isEmpty else { return }
            let parts = text.components(separatedBy: "×")
            let times = parts.count > 1 ? Int(parts[1].trimmingCharacters(in: .whitespaces)) ?? 1 : 1
            let dart = parts[0].components(separatedBy: "@")
            let name = dart[0].trimmingCharacters(in: .whitespaces)
            guard let hit = Hit(notation: name) else { preconditionFailure("unknown dart notation: \(name)") }
            var position: BoardPoint?
            if dart.count > 1 {
                let numbers = dart[1].trimmingCharacters(in: CharacterSet(charactersIn: " ()"))
                    .components(separatedBy: ",")
                    .map { Double($0.trimmingCharacters(in: .whitespaces)) }
                guard numbers.count == 2, let x = numbers[0], let y = numbers[1] else {
                    preconditionFailure("unreadable position: \(text)")
                }
                position = BoardPoint(x: x, y: y)
            }
            for _ in 0..<times {
                outcomes.append(match.throwDart(DartRecord(hit: hit, position: position)))
            }
        }

        for character in script {
            switch character {
            case "(":
                depth += 1
                token.append(character)
            case ")":
                depth -= 1
                token.append(character)
            case "," where depth == 0:
                flush(&self)
            case "|" where depth == 0:
                flush(&self)
                outcomes.append(endTurn())
            default:
                token.append(character)
            }
        }
        flush(&self)
        return outcomes
    }

    /// `match.fact(0, "remaining")` is the field `J1.remaining` of GAMES.md.
    public func fact(_ player: PlayerIndex, _ name: String) -> FactValue? {
        snapshot.players[player].facts[name]
    }

    /// `match.gameFact("ball")` is a game-level field of GAMES.md (`ball`, `sideGoals`, `blobs`, `targets`, `king`).
    public func gameFact(_ name: String) -> FactValue? {
        snapshot.facts[name]
    }

    /// Notations of the darts of the current turn: ["T20", "S5"].
    public var turnNotation: [String] {
        currentTurn.map(\.hit.notation)
    }
}
```

| Cible | Lot | Ce qui est testé |
|---|---|---|
| `DartCoreTests` | F0 | **Aléatoire** : toutes les valeurs de contrôle de `GAMES.md` §2.8 (SplitMix64, `nextInt`, dont `nextInt(below: 2121)`, `shuffled`, les trois `ringLayout`). **`Hit`** : 63 valeurs distinctes, aller-retour des deux notations, lectures tolérées et refusées (dont un zéro en tête, refusé : `S05`, `020`), points, doubles, JSON `"T20"`. **Géométrie** : 20 en haut, 6 à droite, 3 en bas, 11 à gauche ; le centre des 82 zones ; ±0,01° de chaque fil ; règle des frontières ; `neighbours` (exemples de `GAMES.md` §2.1) ; `remap` (aller-retour, case conservée) ; une coordonnée non finie rend `MISS` sans planter, par `hit(at:)`, par `sectorIndex(at:)` et après `remap` ; `clockwiseDegrees` reste dans [0, 360) tout près de l'axe du 20. **Position** : les 62 positions canoniques contre la table de `GAMES.md` §2.13 et contre `centre(of:)` arrondi au dixième ; l'arrondi (`0,05 → 1`, `−0,05 → −1`, `43,04 → 430`, `43,06 → 431`, `−120,05 → −1201`) ; une coordonnée non finie ou démesurée ne plante pas et vaut `1 000 000` dixièmes, bornée à `±1 000 000` ; les trois règles du point d'impact ; `TurnContext.positions`, `impact`, `isFirstTurnOfGame` ; zone `disc` (aucune case dedans, aller-retour JSON). **Descripteur** : `normalized`, `validate`, `playerRange`, `adjusted` (Killer Facile à 7 joueurs), valeurs par défaut de `dependsOnPosition` et `confirmsShortTurn`. **Classement** : ex æquo « 1, 1, 3 ». **Noyau**, avec des règles d'essai définies dans les tests : refus hors phase, confirmation anticipée, joueurs éliminés sautés, manches, limite évaluée à `endTurn`, ordre des événements, pas de `turnCompleted` sur la fléchette gagnante, surbrillances effacées à la fin, volée vide après une fin à la limite de manches (et conservée après une fin sur une fléchette) ; avec une règle d'essai dépendante de la position : tirage dans `dartThrown` et dans `turnStarted`, aucun tirage à l'appel de création. **`GameMatch`** : COM-1 à COM-7, `currentTurn` aligné sur `snapshot.turn.darts` dans toutes les phases (suite d'opérations tirées au sort, graine fixe), fléchettes retirées par le rejeu, `needsReview` effacé à la confirmation, aller-retour JSON de `MatchRecord` positions comprises, déterminisme ; la position est passée au lancer et au rejeu ; `replaceDart` enregistre ou efface la position ; `effectKey(for:position:)` (à position égale toutes les cases sauf `MISS` ont la même clé ; un jeu qui ne dépend pas de la position l'ignore). **Aide de test** : `play` lit `S6@(124.0, 0.0)` ; `skeletonGames` et `deliveredDefinitions`. |
| `DartGamesTests` | G1 à G4, I1 | **Un fichier par jeu**, soit une `@Suite struct` du nom du fichier (`KillerTests`) et une méthode par vecteur (`kil1_…`, §5.7, §13.4), avec tous les vecteurs de sa section : X01-1 à 5, CRI-1 à 10, KIL-1 à 7, ATC-1 à 7, SHA-1 à 7, HIS-1 à 4, HAL-1 à 5, MOO-1 à 4, FIG-1 à 4, CON-1 à 7, BEE-1 à 6, FOO-1 à 7, RAD-1 à 7, GOL-1 à 7. **`Common/`** (G1) : COM-1 à COM-7 avec le vrai X01 ; registre (quatorze ids uniques dans l'ordre de §5.2, options par défaut valides pour chaque nombre de joueurs permis : vrai dès F0, les descripteurs étant définitifs) ; **propriétés** vérifiées sur chaque jeu **livré** du registre avec 200 journaux aléatoires : rejouer `record` redonne le même instantané ; annuler tout redonne l'état initial ; deux fléchettes de même `effectKey` suivies de la même suite donnent les mêmes faits ; `ranks` est bien formé ; aucune entrée ne fait planter un moteur. **`Integration/`** (I1) : plus aucun jeu en squelette ; une partie entière de chacun des quatorze jeux par `GameRegistry.standard` et `GameMatch`, avec annulation, correction (`replaceDart`), fantôme retiré (`removeDart`) et rejeu (registre, JSON, chaque préfixe du journal, tout annuler puis tout rejouer) ; le Killer à ses quatre niveaux, de 2 joueurs au maximum du niveau, chaque fléchette comparée à `GAMES.md` §5.4 et le classement à §5.6. |
| `DartVisionTests` | V1 à V5 | Les groupes de `VISION.md` §10.2, chacun au lot qui possède le code testé : M, R, B (V1) ; C, L (V2) ; E, T, F et les deux tests de `PhotoScorer`, P3 et P4 (V3) ; S (V4) ; X et les trois tests de « Scanner la volée », P1, P2 et P5 (V5). Soit M1 à M12, R1 et B1 ; C1 à C12 et L1 à L5 ; E1 à E4, T1 à T8, F1 à F7, P3 et P4 ; S1 à S23 ; X1 à X17, P1, P2 et P5. Tout calibrage de test vient de `SyntheticCamera.calibration(grade:)`, sauf dans les groupes C et L. Chaque fichier est une `@Suite struct` préfixée par le nom de son dossier (`ReducerPauseTests` dans `Reducer/`, §13.4). Les suites lourdes portent l'étiquette `.heavy`, déclarée une seule fois par F0 dans `SmokeTests.swift` (§13.4), et tournent en `-c release`. |
| `DartAudioTests` | A1 | Chaque ligne de la table de §7.3, dont les dix événements du lot G4 ; règles de séquence (espacement, une vibration par lot, `dartDull`, y compris pour `shotPlayed(strokes: 5)`) ; phrases dans les deux langues ; `turnTotal(180)` rend « 180 » et `oneEighty` l'exclamation ; phrase de fin quand `context.winnerTitle` est renseigné (camp vainqueur, match nul : le titre est dit tel quel, `CallerPhrases.winners` n'est pas appelé, et le résultat ne dépend pas de `context.gameID`) ; pour chaque `SoundEffect` : durée, crête, fondus, déterminisme ; filtrage par les réglages (fonction pure interne) ; `AudioDirector` : `prepare`, `play`, `stopAll` ne plantent pas, même sans sortie audio. |
| `DartUITests` | U1, U2, U3 | Chaque fichier est une `@Suite struct` préfixée par le nom de son dossier (`KernelStorageTests` dans `Kernel/`, §13.4). **`Kernel/`** (U1) : parité des tables de chaînes ; conversion d'un tap dans les deux géométries (§8.4.3 : un tap sur le triple dessiné donne un triple ; aller-retour pour les 82 zones ; bord d'un disque en géométrie `.standard`) ; `AppStorage` : aller-retour des réglages, des joueurs, de la préparation et de la partie en cours ; blob corrompu (l'aller-retour d'un `StoredCalibration` est testé par le lot U3 dans `CameraFlow/` : en vague 1 aucun lot hors de `DartVision` ne peut obtenir un `BoardCalibration`) ; choix de la langue ; `AppModel(environment: .preview())` se construit sans le lot U3 (`game == nil`, `camera.readiness == .unknown`, `camera.makeInputSource(mode:)` rend `nil`), et `startGame(.highScore, …)` crée la partie sans le lot U2 (`game != nil`, `game.snapshot.gameID == .highScore`, volée vide : l'initialiseur de `PlayViewModel` écrit par F0 range ses paramètres, §8.4.7), avec la graine et la date de l'environnement (`game.match.record.configuration.seed == 1` et `game.match.record.startedAt == Date(timeIntervalSinceReferenceDate: 0)` sous `.preview()` : deux exécutions donnent le même `MatchRecord`, §8.5) ; un jeu absent du registre lève `GameConfigurationError.unknownGame`. Rien n'y est joué, et ni `closeGame` ni `rematch` n'y sont appelés : ils passent par des méthodes de `PlayViewModel` que le lot U2 écrit ; chaque écran de `SnapshotCatalog` se rend en image non vide. **`GameFlow/`** (U2) : `AppModel(environment: .preview()).startGame(.highScore, …)` démarre une partie jouée au doigt (source `nil`) sans le lot U3, puis `closeGame` et `rematch` ; scénarios de `PlayViewModel` avec une source factice qui enregistre les commandes et `SilentSoundPlayer` : les trois certitudes, ordre de la file d'attente, fléchette ignorée, corrections et commandes de resynchronisation, **ordre exact des commandes**, retour d'information à la confirmation, fin de tour automatique, sauvegarde et reprise, démarrage d'une partie reprise au milieu d'une volée (`turnBegan(3 − n)`) ; **les deux fins de partie** et la reprise d'une partie finie (§8.6) ; volée courte sans confirmation quand `confirmsShortTurn` est faux ; position transmise (un tap donne `DartRecord.position`, une case prise dans la liste l'efface) ; action « Photo » présente en saisie manuelle ; contexte sonore et titre des résultats pris de `snapshot.winnerTitle` ; préparation (Killer Facile à 7 joueurs) ; `PlayLayout`. **`CameraFlow/`** (U3) : les deux tables et les tests obligatoires de §8.7 avec `FakeScanService` (dont le démarrage à froid, la file unique et la pointe au bord d'une cible) ; aller-retour d'un `StoredCalibration` par `AppStorage`, avec une valeur de `SyntheticCamera.calibration(grade:)` ; revalidation d'un calibrage enregistré ; calibrage sur une image synthétique. |

**Jeux en squelette et tests communs.** Pendant la vague 1, les jeux des autres lots refusent encore de démarrer (`unknownGame`, §5.3). Pour qu'aucun lot de jeux n'attende les autres :

- les tests de `Common/` (lot G1) qui portent « sur chaque jeu du registre » parcourent `GameRegistry.standard.deliveredDefinitions` (`DartTestSupport`, ci-dessus) : un jeu dont la création lève `.unknownGame` est **sauté**, pas compté comme un échec. Un test de `Common/` écrit la liste `GameRegistry.standard.skeletonGames` dans la sortie, pour que le saut se voie ;
- toute autre erreur à la création (options par défaut refusées, nombre de joueurs refusé) n'est pas un squelette : le jeu reste dans la liste et le test échoue ;
- pour un jeu `dependsOnPosition`, les journaux aléatoires des tests de propriétés donnent à chaque fléchette, une fois sur deux, une position tirée dans le carré de ±180 mm ; « deux fléchettes de même `effectKey` » s'entend alors à position égale ;
- le lot I1 ajoute dans `Integration/` l'assertion finale : `GameRegistry.standard.skeletonGames` est vide, et le registre a les quatorze ids de §5.2 dans l'ordre.

Contrôle visuel : chaque lot d'interface lance `SnapshotTool`, **regarde** ses PNG et les compare aux maquettes de `docs/design/mockups/`. Les PNG ne sont pas suivis par git.

### 12.2 Commandes

Xcode 27.2 est installé et sélectionné sur cette machine, avec le Simulateur iOS 27.2 (iPhone 17, iPhone 18 Pro, iPad Pro 13 pouces (M5), entre autres) et XcodeGen 2.46. Les commandes simples suffisent : aucune variable d'environnement, aucun `SDKROOT`. Toutes se lancent depuis `DartKit/`, sauf mention contraire.

```
swift build                                             # tout le paquet, macOS
swift test                                              # tous les tests (Swift Testing)
swift test --filter DartGamesTests                      # une cible de test
swift test --filter KillerTests                         # une suite
swift test -c release --filter DartVisionTests          # suites lourdes de la vision
swift run SnapshotTool --out ../build/snapshots         # instantanés PNG, fr et en

# Simulateur iOS : compile les branches #if os(iOS) du paquet (aucune équipe de signature requise)
xcodebuild -scheme DartUI -destination 'generic/platform=iOS Simulator' build

# Application : depuis la racine du dépôt
xcodegen generate
xcodebuild -project DartScanner.xcodeproj -scheme DartScanner \
  -destination 'platform=iOS Simulator,name=iPhone 17' build
xcodebuild -project DartScanner.xcodeproj -scheme DartScanner \
  -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)' build
```

Repli sur une machine qui n'a que les Command Line Tools (ni Simulateur, ni `xcodebuild`, ni application) : préfixer `swift build` et `swift run` par `DEVELOPER_DIR=/Library/Developer/CommandLineTools`, et ajouter à `swift test` les options `-Xswiftc -plugin-path -Xswiftc /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing`, sans lesquelles les macros de Swift Testing ne sont pas trouvées (l'éditeur de liens signale alors un chemin de recherche absent, sans conséquence).

Précautions :

- ne jamais coller un journal de construction brut dans un document ou un message : certains échecs d'outil impriment tout l'environnement du processus, secrets compris ;
- ne pas lancer `xcodebuild -scheme DartKit-Package` pour iOS : il construirait aussi `SnapshotTool`.

---

## 13. Plan de réalisation

### 13.1 Principe

- Le lot **F0** pose tout ce qui est partagé : le manifeste, `DartCore` complet, et un squelette compilable de chaque autre cible, fait des listings de ce document. Après F0, `swift build` et `swift test` passent, et le registre compte quatorze jeux, dont un jouable.
- Ensuite chaque lot possède des fichiers **en exclusivité** (colonne de droite de §2). Un lot ne modifie jamais un fichier d'un autre lot, ni un fichier marqué « figé ».
- Un besoin qui touche un contrat (une signature de §4, §7.2 ou §8.4, `Package.swift`, `GameCatalog.swift`) ne se règle pas dans le code : il passe par une modification de ce document.
- **Noms dans un module partagé.** `DartGames`, `DartVision`, `DartUI` et leurs cibles de test réunissent les fichiers de plusieurs lots, qui ne se voient pas. Tout ce qu'un lot ajoute au contrat imprimé (fichier, déclaration de niveau fichier, membre d'extension, suite de tests) DOIT être `private` ou `fileprivate`, ou imbriqué dans un type du lot, ou porter le préfixe du lot (`KillerPlayerState`, jamais `PlayerState`) ; et aucun lot n'ajoute de conformité à un type qu'il ne possède pas. La règle complète et le préfixe de chaque lot sont en §13.4.
- Un lot est terminé quand : ses tests passent, `swift build` et `swift test` passent pour tout le paquet sans avertissement, `xcodebuild -scheme DartUI` passe pour le Simulateur iOS, plus aucun `unimplemented()` ni `StubView()` ne reste dans ses fichiers, et ses noms suivent §13.4.

### 13.2 Lots

| Lot | Contenu | Fichiers possédés | Dépend de |
|---|---|---|---|
| **F0** Fondation | `.gitignore` ; `Package.swift` ; `DartCore` (les dix-neuf fichiers de §4) et ses tests ; `DartTestSupport` ; `GameCatalog.swift` avec ses quatorze jeux, `HighScoreRules.swift`, **treize** règles en squelette avec leurs descripteurs définitifs (§5.3) ; squelette de `DartVision` selon §6.4 : les 37 fichiers de la table de `VISION.md` §9.3, avec un vrai corps pour les membres de simple donnée de `VISION.md` §9.4 ; `DartAudioAPI.swift` ; fichiers de contrat de `DartUI` (§8.4), dont `Camera/ScanServicing.swift` complet, `Camera/CameraModel.swift` avec son corps minimal et l'initialiseur de `PlayViewModel`, qui range ses paramètres (§8.4.7) ; `Play/PlayLayout.swift` (§8.8) ; points d'entrée des écrans, dont l'initialiseur ne plante pas (§8.4.10), trois listes d'instantanés, vides hormis l'écran d'essai `skeleton` de celle du socle (§8.4.10), tables de chaînes avec une clé chacune (§8.9) ; `SnapshotTool.swift` ; un test de fumée par cible de test, dans une `@Suite struct SmokeTests` ; celui de `DartVisionTests` déclare en plus l'étiquette `heavy` des suites lourdes (§13.4) | `.gitignore`, `DartKit/Package.swift`, `DartKit/Sources/DartCore/`, `DartKit/Sources/DartTestSupport/`, `DartKit/Sources/DartGames/GameCatalog.swift`, `DartKit/Tests/DartCoreTests/`, `SmokeTests.swift` dans `DartKit/Tests/DartGamesTests/`, `DartVisionTests/`, `DartAudioTests/` et `DartUITests/` (chaque cible de test DOIT contenir au moins un fichier, sinon SwiftPM refuse le paquet ; le lot A1 reprend ensuite celui de `DartAudioTests/`). Un test qui touche `SoundPlaying`, `FakeScanService` ou `CameraModel` porte `@MainActor` | — |
| **G1** Jeux à points | X01, Cricket, puis Meilleur score (finitions : légendes, résultats) ; tests communs et propriétés, qui sautent les jeux en squelette (§12.1) | `DartKit/Sources/DartGames/X01/`, `Cricket/`, `HighScore/` ; `DartKit/Tests/DartGamesTests/X01Tests.swift`, `CricketTests.swift`, `HighScoreTests.swift`, `Common/` | F0 |
| **G2** Jeux de zones | Killer (quatre niveaux), Shanghai, puis Tour de l'horloge | `DartKit/Sources/DartGames/Killer/`, `AroundTheClock/`, `Shanghai/` ; `KillerTests.swift`, `AroundTheClockTests.swift`, `ShanghaiTests.swift` | F0 |
| **G3** Jeux de vies et de conquête | Alunissage, Combat, Conquérant, puis La Moitié | `DartKit/Sources/DartGames/HalveIt/`, `MoonLanding/`, `Fight/`, `Conqueror/` ; `HalveItTests.swift`, `MoonLandingTests.swift`, `FightTests.swift`, `ConquerorTests.swift` | F0 |
| **G4** Jeux Dartsee de conception propre | Tireuse, Football, Radar, Golf (`GAMES.md` §13 à §16) : les règles et leurs fichiers d'appoint (placement des cibles de Radar), les vecteurs BEE-1 à 6, FOO-1 à 7, RAD-1 à 7, GOL-1 à 7. Radar est le seul jeu qui lit `context.impact` et qui tire dans `dartThrown` (§4.7) | `DartKit/Sources/DartGames/BeerTap/`, `Football/`, `Radar/`, `Golf/` ; `DartKit/Tests/DartGamesTests/BeerTapTests.swift`, `FootballTests.swift`, `RadarTests.swift`, `GolfTests.swift` | F0 |
| **V1** Vision : bases | Géométrie, types d'images, canevas et redresseur, rendu synthétique, `SyntheticCamera.calibration(grade:)` ; tests M1 à M12, R1, B1 (`VISION.md` §12, étapes 1 à 3 en partie) | `DartKit/Sources/DartVision/Geometry/`, `Imaging/`, `Canvas/`, `Synthetic/`, `DartCoreBridge.swift` ; `DartKit/Tests/DartVisionTests/Math/`, `Rectify/`, `Imaging/`, `Support/` | F0 |
| **V4** Vision : réducteur | `ScanEvents.swift`, `ScanStateMachine.swift` ; tests S1 à S23 | ces deux fichiers ; `DartKit/Tests/DartVisionTests/Reducer/` | F0 |
| **A1** Audio | Tout `DartAudio` (§7), dont les lignes des dix événements du lot G4 | `DartKit/Sources/DartAudio/`, `DartKit/Tests/DartAudioTests/` | F0 |
| **U1** Socle d'interface | Thème, composants, `DartboardView` (deux géométries, disques), localisation, adaptations, persistance, `AppModel` et racine, `SnapshotCatalog`, instantanés du socle (ses quatre écrans remplacent l'écran d'essai `skeleton`, qu'il DOIT supprimer, §8.4.10), `Common.strings` | `DartKit/Sources/DartUI/App/`, `Design/`, `Board/`, `Support/`, `Persistence/`, `Input/`, `Camera/ScanServicing.swift` (figé), `Snapshots/SnapshotCatalog.swift`, `Snapshots/KernelSnapshots.swift`, `Resources/*/Common.strings` ; `DartKit/Tests/DartUITests/Kernel/` | F0 |
| **X1** Coquille iOS | `App/`, `project.yml`, `Config/Base.xcconfig`, icône | `App/`, `project.yml`, `Config/` | F0 |
| **V2** Vision : calibrage | Poignées, mesure d'arêtes, affinage gardé, calibreur, localisation automatique ; tests C1 à C12, L1 à L5 | dans `DartKit/Sources/DartVision/Calibration/` : `CalibrationHandles.swift`, `EdgeSampler.swift`, `HandleRefiner.swift`, `BoardCalibration.swift`, `BoardCalibrator.swift`, `ConicFit.swift`, `ColourBoardLocator.swift` ; `DartKit/Tests/DartVisionTests/Calibration/` | V1 |
| **V3** Vision : détection, confiance et photo | Carte de preuve, composantes, pointe, détecteur, modèle de confiance, `TrustTracker`, `LightingCheck`, `PhotoScorer` (pointes touchées sur une photo, paire de photos) ; tests E1 à E4, T1 à T8, F1 à F7, P3, P4 | `DartKit/Sources/DartVision/Detection/`, `Confidence/`, `Photo/`, `Calibration/LightingCheck.swift` ; `DartKit/Tests/DartVisionTests/Detection/`, `Confidence/`, `Photo/` | V1 |
| **U2** Parcours de jeu | Accueil (quatorze cartes), préparation, joueurs, réglages, `PlayViewModel` (dont `finishGame`, `suspend`, les deux réglages du descripteur), écran de jeu avec l'action « Photo » et l'attente de `camera.activate()` avant `run`, correction, résultats (dont `winnerTitle`), `Game.strings`, instantanés | `DartKit/Sources/DartUI/Home/`, `Setup/`, `Players/`, `Settings/`, `Play/`, `Results/`, `Snapshots/GameFlowSnapshots.swift`, `Resources/*/Game.strings` ; `DartKit/Tests/DartUITests/GameFlow/` | U1, A1 |
| **V5** Vision : moteur et capture | `MotionGate`, `ScanEngine`, `ScanSession`, sources d'images, `CameraFrameSource`, enregistreur et rejeu ; tests X1 à X17 et, pour « Scanner la volée », P1, P2 et P5 | `DartKit/Sources/DartVision/Scan/MotionGate.swift`, `ScanEngine.swift`, `ScanSession.swift`, `Capture/` ; `DartKit/Tests/DartVisionTests/Engine/` | V1, V2, V3, V4 |
| **U3** Parcours caméra | `LiveScanService`, `CameraInputSource`, conversion d'une observation, `CaptureInterruptionObserver` ; vrais corps de `CameraModel`, dont la file de commandes unique (`enqueue`), et `ScanServiceFactory.live()` ; aperçu, aide au placement, calibrage, scan en direct, vignette, mode photo, `Camera.strings`, instantanés | `DartKit/Sources/DartUI/Camera/` sauf `ScanServicing.swift`, `Calibration/`, `Scan/`, `Photo/`, `Snapshots/CameraFlowSnapshots.swift`, `Resources/*/Camera.strings` ; `DartKit/Tests/DartUITests/CameraFlow/` | U1, U2, A1, V1, V2, V3 |
| **I1** Intégration | Application complète dans le Simulateur ; `SnapshotTool` sur tous les écrans, comparaison aux maquettes ; instantanés alimentés par les vrais moteurs ; assertion « plus aucun jeu en squelette » ; suppression des `Unimplemented.swift` ; `README.md` avec les commandes ; liste des écarts rendue aux lots concernés | `DartKit/Sources/SnapshotTool/`, `DartKit/Tests/DartGamesTests/Integration/`, `README.md` | tous |

Chaque groupe de tests de la vision appartient au lot qui possède le code testé (`VISION.md` §10.2) : B1 éprouve la morphologie et les composantes connexes de `Imaging/`, qui sont au lot V1 ; C10, C11 et C12 éprouvent le calibreur, qui est au lot V2 ; P3 et P4 éprouvent `PhotoScorer`, qui est au lot V3, tandis que P1, P2 et P5 éprouvent « Scanner la volée » par `ScanEngine`, au lot V5.

### 13.3 Ce qui peut tourner en même temps

```
Vague 0 :  F0
Vague 1 :  G1   G2   G3   G4   V1   V4   A1   U1   X1     (9 lots en parallèle)
Vague 2 :  V2   V3   U2                                    (3 lots en parallèle)
Vague 3 :  V5   U3                                         (2 lots en parallèle)
Vague 4 :  I1
```

Dépendances, et ce qui les rend possibles :

| Lot | Attend | Pourquoi il n'attend rien d'autre |
|---|---|---|
| G1, G2, G3, G4 | F0 | `DartCore` est complet ; les tests communs sautent les jeux encore en squelette (§12.1) ; aucun fichier n'est partagé entre deux lots de jeux, et aucun nom non plus (§13.4) |
| V1 | F0 | son calibrage exact ne se sert que des membres de simple donnée de `Calibration/` : `SyntheticCamera.exactHandles()` passe par `CalibrationHandles(points:)`, jamais par un corps du lot V2 (§6.4, `VISION.md` §10.1) |
| V4 | F0 | tous les types du réducteur sont dans `Scan/ScanEvents.swift`, et les valeurs de simple donnée se construisent sur le squelette (§6.4) ; le réducteur ne manipule aucun `BoardCalibration` |
| A1 | F0 | les dix événements nouveaux sont dans `GameEvent` dès F0 |
| U1 | F0 | `ScanServicing.swift` est complet et `CameraModel` a un corps minimal qui fonctionne : `AppModel` se construit et s'exécute sans le lot U3 (§8.4.8). `PlayViewModel.init` range ses paramètres dès F0 et les vues d'entrée des autres lots s'affichent vides : `startGame` s'exécute et la racine s'affiche sans le lot U2 (§8.4.7, §8.4.10). `closeGame` et `rematch`, qui appellent des méthodes de `PlayViewModel`, sont éprouvés par le lot U2 |
| X1 | F0 | n'importe que `DartUI` |
| V2, V3 | V1 | leur calibrage de test vient de `SyntheticCamera.calibration(grade:)` (V1) ; V3, `PhotoScorer` compris, ne lit que les champs stockés de `BoardCalibration`, il n'attend donc pas V2 |
| U2 | U1, A1 | « Meilleur score » existe dès F0 ; les instantanés des autres jeux partent de `GameSnapshot` écrits à la main ; la source de fléchettes est `nil` ou factice ; les écrans du lot U3 que `PlayScreen` présente (`PhotoModeView`, `LiveScanView`, `ScanThumbnail`) s'affichent vides jusqu'à la vague 3 (§8.4.10) |
| V5 | V1, V2, V3, V4 | — |
| U3 | U1, U2, A1, V1, V2, V3 | il se développe contre `FakeScanService` et des images synthétiques ; `PhotoScorer`, dont son test obligatoire de la photo importée a besoin, est livré par V3 en vague 2 ; `LiveScanService` compile contre le squelette de `ScanSession`, seul code du lot V5 qu'il nomme, et la vraie caméra n'est essayée qu'en I1, puis sur un appareil par le propriétaire |
| I1 | tous | — |

- Deux lots d'une même vague n'ont aucun fichier en commun et aucun n'attend l'autre. Ils n'ont aucun nom en commun non plus : c'est l'objet de §13.4.
- Les lots de jeux ne dépendent que de F0 : ils peuvent aussi glisser dans une vague ultérieure sans rien bloquer, sauf I1.
- **Ordre de priorité si la capacité manque**, les jeux Dartsee d'abord (`GAMES.md` §1) : (1) les sept jeux P0, soit X01 et Cricket (G1), Killer et Shanghai (G2), Alunissage, Combat et Conquérant (G3), le Killer demandé par le propriétaire en tête ; (2) les quatre jeux P1 du lot G4 ; (3) les jeux classiques P2 : Tour de l'horloge (G2), La Moitié (G3) et les finitions de Meilleur score (G1). Un lot peut donc livrer en deux temps, ses jeux Dartsee d'abord.

### 13.4 Noms dans un module partagé

La propriété exclusive des fichiers ne suffit pas. Plusieurs lots se compilent dans **un seul module**, et deux lots d'une même vague ne voient pas les fichiers l'un de l'autre. Chacun construit seul ; c'est la fusion de la vague qui échouerait (« invalid redeclaration », « ambiguous use », « filename used twice », « redundant conformance »), sans qu'aucun lot possède la correction. Les règles ci-dessous rendent cette collision impossible. Elles sont normatives pour tous les lots.

| Module | Lots qui y écrivent |
|---|---|
| `DartGames` et `DartGamesTests` | G1, G2, G3, G4 ; F0 (`GameCatalog.swift`, `SmokeTests.swift`) ; I1 (`Integration/`) |
| `DartVision` et `DartVisionTests` | V1, V2, V3, V4, V5 ; F0 (`SmokeTests.swift`) |
| `DartUI` et `DartUITests` | U1, U2, U3 ; F0 (`SmokeTests.swift`) |

« Symbole du contrat » désigne tout ce qui est imprimé dans ce document ou dans le listing de `VISION.md` §9.2 : il garde son nom imprimé. Un lot « possède » un type quand ce type est déclaré dans un de ses fichiers. Les règles portent sur **ce qu'un lot ajoute au contrat**.

1. **Fichiers.** Le compilateur refuse deux fichiers de même nom dans un module, même rangés dans deux dossiers. Tout fichier qu'un lot crée sans que les documents le nomment porte donc un préfixe du lot en tête de son nom : `Killer/KillerZones.swift`, `Scan/ScanEngineReferences.swift`, `Play/PlayScoreboard.swift` ; jamais `Helpers.swift`, `Extensions.swift` ni `Utilities.swift`.
2. **Déclarations de niveau fichier** (types, protocoles, fonctions libres, constantes et variables globales, `typealias`). Chacune DOIT être, au choix :
   - `private` ou `fileprivate` ;
   - imbriquée dans un type que le lot possède (`KillerRules.PlayerState`, `ScanStateMachine.Timers`) ;
   - nommée avec un préfixe du lot : `KillerPlayerState`, et `killerZone(for:)` pour une fonction libre ; jamais `PlayerState` ni `zone(for:)`.

   Aucun lot ne déclare d'opérateur nouveau (`infix operator`) : un opérateur ne se préfixe pas.
3. **Extensions d'un type que le lot ne possède pas** : un type d'une autre cible ou d'un framework (`Hit`, `BoardPoint`, `GameOptions`, `SIMD2`, `Array`, `Double`, `View`, `Color`…), ou un type du contrat déclaré dans le fichier d'un autre lot (`BoardCalibration` pour le lot V3, `Theme` pour le lot U2). Chaque membre qu'une telle extension déclare est `private` ou `fileprivate`, ou porte un préfixe du lot (`hit.killerZoneIndex`, `view.playCardStyle()`). Un initialiseur ou un indice (`subscript`) ne se préfixe pas : il est `fileprivate`. Les extensions imprimées dans le contrat (`GameRegistry.standard`, `DartProposal.init(observation:thresholds:)`, les listes de `SnapshotCatalog`) gardent leur forme.
4. **Conformités.** Aucun lot n'ajoute une conformité (`Equatable`, `Hashable`, `Codable`, `Comparable`, `CustomStringConvertible`, `Identifiable`…) à un type qu'il ne possède pas, ni dans les sources ni dans les tests : une conformité ne peut pas être privée, et elle vaut pour tout le module. Les valeurs que les tests comparent par `==` sont déjà `Hashable` ou `Equatable` dans le contrat (§6.4, `VISION.md` §9.4) ; un manque passe par une modification de ce document (§13.1).
5. **Pas d'homonyme.** Un nom non privé qu'un lot ajoute n'est jamais celui d'un symbole du contrat, ni celui d'un type public d'une cible importée (`PlayerRow`, `Hit`, `ScanState`…) : un homonyme local masquerait ce type dans tout le module, y compris dans les fichiers des autres lots.
6. **Tests.** Chaque fichier de test déclare une ou plusieurs `@Suite struct` dont le nom commence par un préfixe de test du lot et finit par `Tests` ; le fichier porte le nom de sa première suite. Tous les tests sont des méthodes d'une suite : **aucune fonction `@Test` au niveau fichier**. Une méthode porte l'identifiant de son cas quand il en a un (`kil1_hardDuel`, `s16_pauseAndResume`, `m12_exactCalibration`). Les aides sont des membres de la suite, ou des déclarations `private` ou `fileprivate` du fichier ; une aide partagée par plusieurs fichiers de test du lot suit les règles 1 et 2 avec un préfixe de test. Les règles 3, 4 et 5 valent dans les tests.
7. **Étiquettes de test.** Une étiquette Swift Testing se déclare dans une extension de `Tag`, visible de tout le module. Le projet n'en a qu'une, celle des suites lourdes de la vision (`VISION.md` §10.2). Le lot F0 la déclare dans `DartKit/Tests/DartVisionTests/SmokeTests.swift`, et aucun lot n'en déclare d'autre :

   ```swift
   extension Tag {
       /// Heavy vision suites (C2, T, X13): run with `swift test -c release`.
       @Tag static var heavy: Self
   }
   ```

   Les lots V2, V3 et V5 écrivent `@Suite(.tags(.heavy))`. L'étiquette n'existe que dans `DartVisionTests` : les suites du lot U3 qui font travailler la vision (calibrage et photo sur image de synthèse, environ 4,5 s chacune en debug) sont `@Suite(.serialized)`, sans étiquette.

**Préfixes par lot.** Un préfixe s'écrit tel quel en tête d'un nom de type ou de fichier, et avec une minuscule initiale en tête d'une fonction, d'une constante ou d'un membre d'extension (`killerZone`, `x01Checkouts`, `playCardStyle`). Dans un même module, aucun préfixe d'un lot n'est le début d'un préfixe d'un autre lot.

| Lot | Préfixes dans les sources | Préfixes dans les tests |
|---|---|---|
| G1 | `X01`, `Cricket`, `HighScore` | `X01`, `Cricket`, `HighScore` ; `Common` dans `Common/` |
| G2 | `Killer`, `AroundTheClock`, `Shanghai` | les mêmes |
| G3 | `HalveIt`, `MoonLanding`, `Fight`, `Conqueror` | les mêmes |
| G4 | `BeerTap`, `Football`, `Radar`, `Golf` | les mêmes |
| I1 | aucun (il n'ajoute rien à `DartGames`) | `Integration` |
| V1 | `Geometry`, `Imaging`, `Canvas`, `Synthetic`, `LinearSolve`, `BoardModel`, `Morphology`, `ConnectedComponents`, `DartCoreBridge` | `Math`, `Rectify`, `Imaging`, `Support` |
| V2 | `Calibration`, `EdgeSampler`, `HandleRefiner`, `ConicFit` | `Calibration` |
| V3 | `Detection`, `Confidence`, `Photo`, `LightingCheck`, `ChangeEvidence`, `BlobAnalysis`, `TipEstimator` | `Detection`, `Confidence`, `Photo` |
| V4 | `ScanStateMachine` | `Reducer` |
| V5 | `MotionGate`, `ScanEngine`, `ScanSession`, `Capture` | `Engine` |
| U1 | `App`, `Design`, `Board`, `Support`, `Persistence`, `Input`, `Kernel` | `Kernel` |
| U2 | `Home`, `Setup`, `Players`, `Settings`, `Play`, `Results`, `GameFlow` | `GameFlow` |
| U3 | `Camera`, `Calibration`, `Scan`, `Photo`, `CameraFlow` | `CameraFlow` |
| F0 | aucun (il n'écrit que des symboles du contrat) | `Smoke` : le fichier `SmokeTests.swift` et sa suite `SmokeTests`, dans chaque cible de test. Dans `DartCoreTests`, que F0 possède en entier, les autres fichiers portent le même préfixe : une suite par sujet de §12.1 (`SmokeRandomTests`, `SmokeHitTests`, `SmokeGeometryTests`, `SmokePositionTests`, `SmokeDescriptorTests` et `SmokeRankingTests` (toutes deux dans `SmokeDescriptorTests.swift`), `SmokeKernelTests`, `SmokeMatchTests`, `SmokeSupportTests`) et les règles d'essai dans `SmokeFixtures.swift` (`SmokeX01Rules`…) |
| A1, X1 | libres : chacun est seul dans son module | libres ; A1 reprend `SmokeTests.swift` de `DartAudioTests/` |

- **Jeux.** Le préfixe est le nom du dossier du jeu, c'est-à-dire le nom de sa règle sans `Rules`. Un code commun à deux jeux d'un même lot prend le préfixe de l'un des deux et vit dans son dossier. Le fichier de test d'un jeu est `<Jeu>Tests.swift`, avec la suite `<Jeu>Tests` (`swift test --filter KillerTests`, §12.2).
- **Vision.** Les préfixes sont les noms des dossiers du lot, plus les noms des fichiers internes que `VISION.md` §9.3 lui attribue. Le lot V3 possède `Calibration/LightingCheck.swift` dans le dossier du lot V2 : il n'y crée aucun autre fichier et n'emploie pas le préfixe `Calibration`. Les lots V4 et V5 partagent le dossier `Scan/` : leurs préfixes sont les noms de leurs propres types (`ScanStateMachine` pour V4 ; `MotionGate`, `ScanEngine` et `ScanSession` pour V5), et `Scan` seul n'est le préfixe d'aucun des deux. Les fichiers de test de la vision sont préfixés par leur dossier (`Reducer/ReducerPauseTests.swift`). `DartVisionTests/Support/` (lot V1) contient les aides que les lots suivants réutilisent (les poses A à D de `VISION.md` §10.2) : elles ne sont pas privées et portent le préfixe `Support` ; les lots V2, V3 et V5, qui dépendent de V1, peuvent s'en servir, et le lot V4, de la même vague, ne s'en sert pas.
- **Interface.** Les préfixes sont les noms des dossiers du lot ; `Kernel`, `GameFlow` et `CameraFlow` servent aux fichiers d'instantanés et aux tests. La plupart des sous-vues d'un écran sont simplement `private` dans son fichier.
- **Vérification.** Avant de livrer, un lot relit la liste de ses déclarations de niveau fichier et de ses noms de fichiers : chaque nom non privé commence par un de ses préfixes, ou figure dans le contrat.

---

## 14. Arbitrages et écarts avec les autres documents

Les quatre premiers sujets étaient des désaccords entre documents dans la version 1.0 ; `GAMES.md` 1.1, `VISION.md` 1.1 et `DESIGN.md` disent maintenant la même chose que ce document.

| Sujet | Ce que disent les documents | Décision de ce document |
|---|---|---|
| Fin de tour sur retrait détecté | accord : `GAMES.md` §2.4, `DESIGN.md` §5 et `VISION.md` §6.4 décrivent le réglage `endsTurnOnTakeout`, désactivé par défaut ; la vision n'émet que `takeoutCompleted` | §8.6. Seule reste la question 1 : faut-il l'activer par défaut ? |
| Nom d'événement `targetHit` | accord : `GAMES.md` §2.10 nomme `targetScored(player, points)` pour Shanghai et La Moitié, `targetHit(player, number, advancedBy)` pour le Tour de l'horloge | `GameEvent` reprend le catalogue tel quel (§4.5) |
| Initialiseur de `DartObservation` | accord : déclaré dans le corps de la structure, `VISION.md` §9.2 | plus d'addendum ; ne pas le redéclarer en extension (§6.3) |
| Ordre des jeux à l'accueil | accord : `GAMES.md` §1 et `DESIGN.md` §4 donnent l'ordre du catalogue, quatorze jeux, Dartsee d'abord ; la maquette `Main` n'en montre que dix | ordre du catalogue (§5.2) ; la maquette ne fait foi que pour le dessin d'une carte |
| Périmètre des jeux | décision du propriétaire : les onze jeux de la page des jeux de Dartsee. `GAMES.md` §13 à §16 spécifie Tireuse, Football, Radar, Golf ; Castle Crushers et Darts Class restent reportés (`GAMES.md` §17) | quatre jeux ajoutés au registre, lot G4 (§5, §13) |
| Position de l'impact | `GAMES.md` §2.13 : une entrée `dart` porte une case et, si elle est connue, une position ; seul Radar la lit | la position voyage à côté de `GameInput` : `apply(_:position:)`, `TurnContext.positions`, `ImpactPoint` (§4.2, §4.7, §4.8). `GameInput` et son JSON ne changent pas |
| Tirage pendant une fléchette | `GAMES.md` §15.4 : Radar tire le remplacement d'une cible détruite | `dartThrown` reçoit `random`, comme `init` et `turnStarted` (§4.7) |
| Volée courte au Golf | `GAMES.md` §16.5, `DESIGN.md` §5 : pas de confirmation | `GameDescriptor.confirmsShortTurn` (§4.4) |
| Cible de Radar à l'écran | `DESIGN.md` §4 : proportions réglementaires, disques | `GameDescriptor.dependsOnPosition`, `DartboardView(geometry:)`, `BoardZone.disc` (§4.2, §8.4.3) |
| Score provisoire du Golf | `GAMES.md` §16.4 le décrit sans le nommer | fait de partie `provisional` (§5.5) |
| Annonce d'une volée de 180 | `GAMES.md` §2.10 : Radar émet `turnScored` sans jamais `oneEighty` | `CallerPhrases.turnTotal` rend les chiffres ; l'exclamation appartient à `oneEighty` (§7.3) |
| Vainqueur du Football | `GAMES.md` §14.6 et §14.7 : les joueurs d'un camp partagent le rang, et le jeu donne un titre des résultats | donnée `winnerTitle` de `GameSnapshot`, recopiée dans `CueContext` : « Le camp A gagne » à l'écran et à la voix, pas « Égalité entre… » ; aucun test sur l'identifiant du jeu (§4.6, §7.3, §8.6) |
| File de commandes | audit : une file par source ne couvrait ni le mode photo, ni l'arrière-plan, ni la revanche | une seule file, tenue par `CameraModel` (`enqueue`), partagée par tous les écrivains (§8.4.8, §8.7, §11) |
| Source d'une partie après un lancement à froid | audit : `readiness` n'est connu qu'après `activate()`, appelé trop tard | `makeInputSource` rend une source dès que `service.issue == nil` ; `PlayScreen` attend `activate()` avant `run` ; l'accueil l'appelle en mode caméra (§8.5 à §8.7) |
| Pointe au bord d'une cible de Radar | `GAMES.md` §2.13 : ce doute ne se tranche pas en silence | la certitude tombe à `needsReview` quand un des quatre points à un écart-type change l'effet (§8.4.8) |
| Lot de `PhotoScorer` | `VISION.md` §9.3 : lot V3 | le mode photo du lot U3 n'attend pas le lot V5, qui est dans sa vague (§13) |
| Façade caméra | proposition de la revue : `ScanServicing.swift` et `CameraModel.swift` au lot F0 puis U1, repris par U3 | `ScanServicing.swift` au lot U1, figé ; `CameraModel.swift` au lot U3 dès le départ, avec un corps minimal écrit par F0, et `ScanServiceFactory` pour que U1 ne nomme jamais `LiveScanService` (§8.4.8) |
| Partie quittée avant la fin | non spécifié | `PlayViewModel.suspend()` envoie `gameEnded()` et garde la sauvegarde (§8.6) |
| Seuils courants du `TrustTracker` | non exposés par `ScanSession` | règle prudente côté `DartUI` (§8.7) |
| Orientation pendant le scan | `VISION.md` §2.4 : interface verrouillée | pas de verrouillage (impossible en SwiftUI) ; un changement d'angle de capture impose un recalibrage (§6.5) |
| Préréglage de capture | `VISION.md` §2.4 : 4K à 30 images/s. Étude de la plateforme : 720p et 10 à 15 images/s pour la chaleur | `VISION.md` fait foi ; la chaleur est traitée comme il le prévoit (`thermalState`, mode « Scanner la volée »). `CameraConfiguration` permet de changer sans toucher à l'API |
| Lectures de `Hit(notation:)` | `GAMES.md` §2.2 : forme canonique | accepte aussi `25`, `50` et un nombre nu pour un simple (§4.2), et rien d'autre : un zéro en tête est refusé (`S05`, `020`) ; l'écriture reste canonique |
| Voix et effets | `GAMES.md` §18 : « à concevoir » | table de §7.3 ; chaque fléchette est annoncée (priorité basse), le total de la volée ensuite |
| Fléchette incertaine | `VISION.md` §7.4 et sa question 2 | on attend la réponse du joueur ; aucun délai d'acceptation automatique |
| Contrôles système | `DESIGN.md` : thème sombre sur mesure | aucun contrôle système dans les contenus d'écran (§8.4.2, §8.8) : ils ne se rendent pas sous `ImageRenderer` |
| Persistance | non spécifiée | `UserDefaults`, JSON, clés versionnées (§8.10) ; reprise d'une partie interrompue |
| Raison d'une pause | dernière relecture : `resume` levait toute pause, y compris celle d'une fin de partie, et la vision se réarmait sans partie après un passage en arrière-plan | `paused` porte sa raison ; `pause(.user)` ne se lève que par `arm`, et l'emporte sur une pause du système (`VISION.md` §6.3, lignes P1b et P2c) ; le calibrage dépose `pause(.user)` à sa fermeture (§6.5, §8.7) |
| Poignées du calibrage exact | dernière relecture : `SyntheticCamera.exactHandles()` (lot V1, vague 1) appelait un corps du lot V2 | `CalibrationHandles(points:)`, membre de simple donnée (`VISION.md` §10.1 ; §6.4, §13.3) |
| Égalité des valeurs de la vision | dernière relecture : les tests comparent des listes de commandes, et `ScanCommand` n'était pas `Equatable` | `ScanCommand`, `ScanEvent`, `ScanEffect`, `ScanInput`, `SettleOutcome` et `DartObservation` sont `Hashable` (`VISION.md` §9.2 ; §6.4, §8.4.8) |
| Date de début d'une partie | dernière relecture : `AppEnvironment.now` n'était utilisé par aucune phrase, et la date venait de l'horloge par la valeur par défaut de `GameMatch.init` | `AppModel` crée toute partie neuve avec `startedAt: environment.now()` ; graine et date fixes sous `preview()` (§4.8, §8.4.9, §8.5) |
| Noms dans un module partagé | dernière relecture : la propriété des fichiers n'empêchait pas deux lots de déclarer le même nom dans un module | règle de noms, préfixe de chaque lot, suites de tests, étiquette `heavy` unique (§13.1, §13.4) |
| Contrat du réducteur avec le moteur | lot V4 : aucun `ScanEffect` n'efface les références ni ne mémorise une silhouette, et l'entrée `ScanInput.armed` n'était décrite nulle part | règles écrites dans `VISION.md` §6.3 et dans le commentaire de `ScanStateMachine` : le moteur efface et mémorise seul ; aucun effet ajouté, l'API de `VISION.md` §9.2 ne change pas |
| Inverse d'une homographie | `VISION.md` §4.2 : rejet si le déterminant est inférieur à 1e-9 en valeur absolue après mise à norme de Frobenius 1. Lot V1 : cette règle refuse les poses de référence (5e-10 pour la pose A) | même seuil, appliqué après équilibrage des colonnes puis des lignes (`VISION.md` §4.2, §9.2) |
| Présentation après une fin à la limite de manches | lots G1 et G4 : la volée du noyau est vide (§4.7) alors que la règle garde l'état de son dernier tour | `turnSummary` à `nil`, légendes coupées à la volée, dans les quatorze jeux (§5.6) ; `provisional` du Golf à 5 (§5.5) |
| Événement propre et `noEffect` | `GAMES.md` §2.10 émet `noEffect` pour toute fléchette sans effet ; §3.4 ne donne que `doubleInRequired` (lot G1) | l'événement propre remplace `noEffect` : `doubleInRequired` au X01, `healWasted` au Combat (`GAMES.md` §2.10, §3.4) ; la table de §7.3 les sonne de la même façon |
| Phrases d'un même lot | §7.5 : `high` interrompt tout ; appliqué à la lettre, une phrase `low` serait coupée dès son premier mot (lot A1) | une phrase `low` qu'une phrase `high` du même lot couperait avant 0,5 s n'est pas commencée ; une phrase `high` coupe encore une phrase `high` plus ancienne du lot (§7.5) |
| Membres de `PlayViewModel` pour le lot U3 | lot U2 : la source est privée, et le contrat ne donnait aucun moyen de répondre à `needsEmptyBoard`, de lire l'image de preuve ni de répondre à une fléchette en attente par un tap | six membres imprimés en §8.4.7 (`handle`, `resolvePending(with: BoardTap)`, `confirmBoardEmpty`, `evidenceImage`, `rescore`, `hasSource`) ; comportement en §8.6 |
| Date et identifiant d'un calibrage | lot V2 : l'API ne reçoit aucune horloge et le code testé n'appelle ni `Date()` ni `UUID()` | `createdAt` à la date de référence, `id` empreinte du contenu ; même entrée, même valeur (X16) (`VISION.md` §4.1, §9.2) |
| Correction de calotte | `VISION.md` §5.3 : 0,8 mm ; lot V3 : biais de +0,33 mm, hors de T2 | 1,1 mm (`VISION.md` §5.2, §5.3, §9.2) |
| Suggestion de vérifier la lumière | `VISION.md` §7.6 la demande, §9.2 n'expose que `shouldSuggestScanMode` | `TrustTracker.shouldSuggestLightingCheck`, membre `internal` lu par le moteur (V5) dans le module ; l'API publique ne change pas |
| Appui long sur la cible | `DESIGN.md` §5 et §8.6 ne disent pas quand la vue agrandie s'ouvre ; revue du lot U1 : un rappel pendant l'appui empêchait tout tap | signalé au relâcher (§8.6) |
| Élision de « de » à l'écran | lot A1 élide dans la voix ; la chaîne `play.turnOf` de l'écran n'élidait jamais | l'écran affiche `CallerPhrases.nextPlayer` (§8.6) ; la clé `play.turnOf` reste dans les tables, inutilisée |
| Source du Simulateur | `VISION.md` §2.4 et §8.7 : `SyntheticFrameSource` ; lot U3 : un script fini laisse la session sans images | `CameraDemoFrameSource` (lot U3), deux rendus de la cible vide en boucle à 10 images/s (§8.7 ; `VISION.md` §2.4) |
| Appareil déplacé pendant une partie | §6.5 : « l'interface demande un recalibrage », sans canal dans `ScanServicing` | `LiveScanService` envoie `pause(.user)` et remet un `calibrationLost` de synthèse à ses abonnés ; l'aperçu reste à l'angle des images (§6.5). Aucune API ajoutée |
| Main devant la cible prise pour la lumière | `VISION.md` §5.2 D4 teste la lumière avant l'obstruction ; lot V5 : la main de X3 devenait un `lightingChange`, puis une fléchette fantôme | le détecteur garde son ordre ; le moteur lit `lightingChange` comme `obstruction` après un épisode d'au moins deux images de mouvement ou parti d'`obstructed` (`VISION.md` §5.2, §6.3) |
| Plateau tourné sur son support | `VISION.md` §4.9 : « sain » sur les seuls échantillons mesurés ; revue du lot V2 : une rotation de 9° était saine | les fils doivent s'accorder au moins moitié aussi bien que les anneaux, chaque famille comptée sur tous ses échantillons (`VISION.md` §4.9) |
| Ombre dure au-delà de la pointe | `VISION.md` D9 ne gardait le bout terne que sous `lowTipContrast` ; revue du lot V3 : 3 hautes fausses sur 12 sous une ombre de 0,20 | `implausiblyLong` aussi pour un bout plus sombre que le modèle d'ombre ; T7 compte les fausses parmi les hautes (`VISION.md` D9, §10.2) |
| Nombre attendu après une correction pendant une attente | lot U2 : `turnBegan(3 − n)` ne retranche pas les fléchettes en attente, que la source a déjà vues | gardé tel quel, pour ne jamais pénaliser la vraie dernière fléchette ; `turnClosed` ferme la volée (§8.6) |
| « Pas encore » à « La cible est-elle vide ? » | `GAMES.md` §2.4 : la cible est confirmée vide avant de démarrer ; la table « Commandes » armait pourtant la vision par `arm(boardConfirmedEmpty: false)` sur une cible qui portait encore des fléchettes, et leur retrait se lisait comme des fléchettes (revue finale) | `gameStarted(boardConfirmedEmpty: false)` ne dépose rien ; `boardConfirmedEmpty()` arme alors avec `arm(boardConfirmedEmpty: true)` puis rejoue la volée (§8.7). Aucune signature ne change ; la ligne A15 du moteur reste telle quelle |
| Fléchettes demandées par « Scanner » | §8.7 : `3 − comptées − en attente` ; revue finale : une fléchette saisie au doigt n'est pas dans `R`, son doublon prenait la place de la dernière vraie fléchette | `3 −` les fléchettes rendues par la vision (origine `camera` ou `scan`, et en attente) ; la revue écarte le doublon (§8.7) |
| Seuils de la revue d'un scan | §8.7 « Seuils de palier » : la source relève le seuil haut après `accuracyDegraded` ; le mode photo comptait avec `.standard` | membre `CameraModel.inputSource` (lot U3, §8.4.8) : la revue compte avec les seuils de la source |
| Correction ouverte depuis une couverture caméra | lot U3 : la couverture présente sa propre feuille sur `game.correction`, et `PlayScreen`, couvert, tentait la même | `PlayScreen` ne lie pas sa feuille de correction pendant qu'une couverture est affichée (§8.6) |

---

## 15. Questions ouvertes pour le propriétaire

Seules les questions qui changent le comportement livré ou qui bloquent une étape sont posées ici. Celles de `GAMES.md` §19 et de `VISION.md` §13 restent valables et ne sont pas répétées.

1. **Passage automatique au joueur suivant.** Les maquettes validées disent que le tour passe « sur le bouton ou sur le retrait détecté par la caméra ». L'application est construite avec le bouton seul par défaut, et un réglage qui laisse la caméra passer le tour quand les fléchettes ont été comptées puis retirées et qu'aucune n'attend de réponse ; les règles, les maquettes et la conception de la vision décrivent maintenant ce même réglage. La prudence vient de ce qu'une main devant la cible ou un retrait partiel pourrait changer de joueur à tort. Voulez-vous que ce réglage soit **activé par défaut** ?
2. **Installation sur vos appareils.** Pour installer l'application sur un iPhone ou un iPad réel, il faut votre identifiant d'équipe Apple Developer (dix caractères) et un identifiant d'application à vous, par exemple `fr.votrenom.dartscanner`. Lesquels faut-il utiliser ? Sans eux, l'application ne tourne que dans le Simulateur, où il n'y a pas de caméra.
3. **Taille du texte du système (Dynamic Type).** Toutes les polices sont de taille fixe, comme `DESIGN.md` les donne : un joueur qui agrandit le texte de son iPhone ne voit rien changer. Faut-il suivre la taille choisie dans les réglages du système (avec des écrans à revoir pour les grandes tailles), ou garder les tailles fixes ?
4. **Mode démonstration du Simulateur.** Sans caméra arrière, l'application montre en mode caméra une cible de synthèse comme si la caméra la voyait (« Cible à calibrer », puis un calibrage sur cette image), sans dire que c'est une démonstration. Faut-il l'annoncer (« Démonstration : pas de caméra »), ou la remplacer par l'écran « Pas de caméra disponible » ?
5. **iPhone en paysage.** Les maquettes ne dessinent l'écran de jeu que sur iPhone en portrait et sur iPad. En paysage sur iPhone, l'application met maintenant la barre d'actions sous la cible et retire le très grand nombre de la carte du joueur courant, pour que les autres joueurs restent visibles (§8.8). Cette disposition vous convient-elle ?
