# GAMES.md — Spécification des règles de jeu

Version 1.1 — 2026-11-10 — Statut : **normatif**.

Ce document est la référence unique des règles pour les moteurs de jeu (cible `DartGames`) et leurs tests. Le code est écrit et relu d'après ce fichier : en cas de désaccord entre le code et ce document, c'est le code qui a tort (ou alors on corrige d'abord ce document).

- Les identifiants (`lowerCamelCase`), noms d'options, noms d'événements et notations de fléchettes sont en anglais et **font foi tels quels**.
- La forme exacte des types Swift (protocoles, structs) est fixée par `DartCore`. Ce document décrit des champs **logiques** ; un moteur peut les exposer sous une autre forme tant que les valeurs sont identiques.
- « DOIT » / « NE DOIT PAS » marquent une exigence testable.
- Marqueurs de provenance :
  - *(Dartsee)* : règle documentée par Dartsee (manuel d'exploitation, présentation des jeux, site).
  - *(règle standard, non confirmée Dartsee)* : Dartsee ne précise pas ; on applique la règle de fléchettes la plus répandue.
  - *(conception propre, non confirmée Dartsee)* : ni Dartsee ni une règle standard ne tranchent ; choix fait pour cette application.
  - *(conception propre, inspirée de Dartsee)* : Dartsee ne publie qu'une phrase de principe pour ce jeu, sans aucune règle de score ; toutes les règles sont les nôtres (sections 13 à 16).

Changements de la version 1.1 : quatre jeux ajoutés (Tireuse, Football, Radar, Golf : sections 13 à 16) ; priorités revues, les jeux Dartsee d'abord (section 1) ; position de l'impact et jeux dépendants de la position (2.13) ; l'événement de Shanghai et de La Moitié s'appelle `targetScored` ; qui peut terminer un tour (2.4). Les anciennes sections 13, 14 et 15 deviennent 17, 18 et 19. Aucun vecteur de test des sections 2 à 12 ne change, hormis ce renommage dans SHA-1 et une ligne d'événements ajoutée à HAL-1.

Précisions apportées après l'audit de la version 1.1, sans changement de règle : le double du trou au Golf figure parmi ce qui clôt un tour (2.4, 2.5, 2.10) ; une coordonnée non finie est bornée (2.13) ; le doute sur une pointe proche du bord d'une cible de Radar (2.13) ; au Football, « le but que défend un camp » et « le camp marque » ne se confondent plus, et le titre des résultats nomme le camp vainqueur (14.1, 14.4, 14.7) ; à Radar, le rejeu après une correction, les fléchettes sans position et le repli du placement sont explicites (15.3, 15.4). Vecteurs ajoutés : BEE-6, FOO-7, RAD-7, GOL-7, et des cas de plus dans RAD-3 et RAD-6.

Précision apportée après la vérification de la fondation (lot F0), sans changement de règle : une partie finie à la limite de manches a une volée vide, comme après toute confirmation, alors qu'une partie finie sur une fléchette garde la sienne (2.4, 2.6 ; une valeur attendue de plus dans COM-7).

Précisions apportées à l'intégration de la vague 1 (les quatorze moteurs livrés), sans changement de règle ni de vecteur : ce que les moteurs font là où le texte se taisait. Un événement propre remplace `noEffect` (2.10, 3.4) ; les surbrillances de Shanghai sont des cases (2.9, 7.7) ; ce que voit un joueur du Killer qui vient de s'éliminer (5.7) ; `advancedBy` du Tour de l'horloge au plafond et au bull (6.8) ; les cibles à venir de La Moitié (9.7) ; le `player` de `damaged` au Combat est la victime (11.8) ; le bull du Conquérant quand le joueur courant est le Roi (12.7).

Précisions apportées à l'intégration de la vague 2 (revues des lots de jeux), sans changement de règle ni de vecteur : le `player` de `lifeLost` au Killer est la victime, comme le code et KIL-4 le font déjà (5.8) ; au Combat, la case de soin et les points faibles prennent la couleur de leur propriétaire, le vert et le rouge de 11.7 n'étaient qu'une illustration (11.7).

## Sommaire

1. [Catalogue](#1-catalogue)
2. [Règles communes à tous les jeux](#2-règles-communes-à-tous-les-jeux)
3. [X01](#3-x01-x01)
4. [Cricket](#4-cricket-cricket)
5. [Killer](#5-killer-killer)
6. [Tour de l'horloge](#6-tour-de-lhorloge-aroundtheclock)
7. [Shanghai](#7-shanghai-shanghai)
8. [Meilleur score](#8-meilleur-score-highscore)
9. [La Moitié](#9-la-moitié-halveit)
10. [Alunissage](#10-alunissage-moonlanding)
11. [Combat](#11-combat-fight)
12. [Conquérant](#12-conquérant-conqueror)
13. [Tireuse](#13-tireuse-beertap)
14. [Football](#14-football-football)
15. [Radar](#15-radar-radar)
16. [Golf](#16-golf-golf)
17. [Jeux Dartsee reportés](#17-jeux-dartsee-reportés-hors-v1)
18. [Écarts et points non confirmés](#18-écarts-avec-dartsee-et-points-non-confirmés)
19. [Questions ouvertes](#19-questions-ouvertes-pour-le-propriétaire)

---

## 1. Catalogue

Quatorze jeux, en trois paliers de priorité. Le propriétaire a désigné la page des jeux de Dartsee (<https://www.dartsee.com/dartsee-venues/games>, onze jeux) comme périmètre : les onze sont spécifiés ici, et **les jeux Dartsee passent avant les jeux classiques**.

| id | Nom FR | Nom EN | Joueurs | Origine | Palier | Section |
|---|---|---|---|---|---|---|
| `x01` | X01 (301 / 501 / 701) | X01 | 1–8 | Dartsee | P0 | 3 |
| `cricket` | Cricket | Cricket | 1–8 | Dartsee | P0 | 4 |
| `killer` | Killer | Killer | 2–8 (2–6 en Facile) | Dartsee + 2 niveaux propres | P0 | 5 |
| `shanghai` | Shanghai | Shanghai | 1–8 | Dartsee | P0 | 7 |
| `moonLanding` | Alunissage | Moon Landing | 1–8 | Dartsee | P0 | 10 |
| `fight` | Combat | Fight | 2–6 | Dartsee | P0 | 11 |
| `conqueror` | Conquérant | Conqueror | 2–8 | Dartsee (règles complétées) | P0 | 12 |
| `beerTap` | Tireuse | Beer Tap | 1–8 | Dartsee (conception propre) | P1 | 13 |
| `football` | Football | Football | 2–8 | Dartsee (conception propre) | P1 | 14 |
| `radar` | Radar | Radar | 1–8 | Dartsee (conception propre) | P1 | 15 |
| `golf` | Golf | Golf | 1–8 | Dartsee (nom repris ; règles du Golf traditionnel aux fléchettes) | P1 | 16 |
| `aroundTheClock` | Tour de l'horloge | Around the Clock | 1–8 | Classique (hors Dartsee) | P2 | 6 |
| `highScore` | Meilleur score | High Score | 1–8 | Classique (hors Dartsee) | P2 | 8 |
| `halveIt` | La Moitié | Halve-It | 1–8 | Classique (hors Dartsee) | P2 | 9 |

**Paliers.**

- **P0 — les sept jeux Dartsee aux règles documentées.** À livrer en premier ; le Killer et ses quatre niveaux en font partie.
- **P1 — les quatre autres jeux de la page Dartsee** (Tireuse, Football, Radar, Golf), livrés par le lot **G4**. Dartsee n'en publie aucune règle de score : leurs règles sont de notre conception, inspirées de la phrase de description de chaque jeu. Ils se jouent sur l'écran de jeu commun, sans physique, sans chronomètre, avec le même modèle de tour, d'annulation et de correction que les autres (section 2).
- **P2 — les trois jeux classiques absents de Dartsee** (Tour de l'horloge, Meilleur score, La Moitié), en dernier.

L'ordre des lignes du tableau est l'ordre de priorité ; c'est aussi l'ordre d'affichage recommandé sur l'écran d'accueil. Les paliers ordonnent le travail quand la capacité manque ; ils n'empêchent pas un jeu P2 d'exister plus tôt (`highScore`, le plus simple, sert d'exemple et de jeu d'essai de la détection dès le socle).

Deux jeux 3D de Dartsee, absents de cette page (Castle Crushers, Darts Class), restent hors périmètre : [section 17](#17-jeux-dartsee-reportés-hors-v1).

Chaque jeu est décrit avec la même structure : (1) Fiche, (2) Options, (3) État initial, (4) Effet d'une fléchette, (5) Déroulement du tour, (6) Élimination, victoire, classement, (7) Tableau de score et surbrillances, (8) Événements, (9) Vecteurs de test. Un jeu qui **dépend de la position** de l'impact (2.13) le dit dans sa fiche ; sans cette mention, il n'en dépend pas. Un seul jeu est dans ce cas : `radar`.

---

## 2. Règles communes à tous les jeux

### 2.1 Plateau

Ordre des numéros dans le sens horaire en partant du haut (index 0 à 19) :

```
ring = [20, 1, 18, 4, 13, 6, 10, 15, 2, 17, 3, 19, 7, 16, 8, 11, 14, 9, 12, 5]
```

- **Secteur n** : la part de camembert du numéro n (1–20), toutes cases confondues : simple intérieur, triple, simple extérieur, double.
- **Voisins** d'un numéro : les deux numéros adjacents dans `ring` (circulaire). `neighbours(n) = (antihoraire, horaire)`. Exemples : `neighbours(20) = (5, 1)`, `neighbours(1) = (20, 18)`, `neighbours(7) = (19, 16)`, `neighbours(2) = (15, 17)`, `neighbours(5) = (12, 20)`.
- Le bull (centre) n'a pas de voisins et n'appartient à aucun secteur.
- **Moitiés du plateau** (utilisées par `football`) : la **moitié droite** est faite des neuf secteurs d'index 1 à 9 de `ring` (1, 18, 4, 13, 6, 10, 15, 2, 17), la **moitié gauche** des neuf secteurs d'index 11 à 19 (19, 7, 16, 8, 11, 14, 9, 12, 5). Le 20 (index 0) et le 3 (index 10) sont à cheval sur l'axe vertical : ils n'appartiennent à aucune moitié. Le bull non plus.

**Repère et dimensions.** La géométrie en millimètres relève de `DartCore` (`BoardGeometry.standard`) et de `DartVision`. Les moteurs de ce document ne voient que des cases, à une exception près : `radar` (section 15), seul jeu dépendant de la position (2.13). Pour lui, et pour lui seul, ce document utilise :

- le repère du plateau : origine au centre du bull, `+x` vers le 6 (à droite quand on regarde la cible), `+y` vers le 20 (en haut), en millimètres. C'est le repère de `VISION.md` §3.3 et de `BoardPoint` ;
- les rayons réglementaires : bull intérieur 6,35 ; bull extérieur 15,9 ; anneau triple de 99 à 107 ; anneau double de 162 à 170 (bord extérieur de la zone de score) ;
- le centre du secteur d'index `i` dans `ring` est à l'angle `18° × i`, mesuré dans le sens horaire à partir de `+y`.

### 2.2 Notation d'une fléchette (`Hit`)

Une fléchette est toujours l'une de ces 63 valeurs :

| Notation | Case | Points | `number` | `multiplier` | Double ? | Triple ? |
|---|---|---|---|---|---|---|
| `S1` … `S20` | simple du secteur n (intérieur ou extérieur, sans distinction) | n | n | 1 | non | non |
| `D1` … `D20` | double du secteur n | 2n | n | 2 | **oui** | non |
| `T1` … `T20` | triple du secteur n | 3n | n | 3 | non | **oui** |
| `SB` | bull extérieur (vert, « bull », 25) | 25 | aucun | 1 | non | non |
| `DB` | bull intérieur (rouge, « bullseye », 50) | 50 | aucun | 2 | **oui** | non |
| `MISS` | hors des zones de score | 0 | aucun | — | non | non |

Règles :

- `MISS` couvre **tous** les cas sans score : fléchette hors plateau, dans la couronne noire extérieure au double, ou **rebond** (la fléchette retombe). Un rebond NE DOIT PAS être rejoué : il compte comme une fléchette lancée valant `MISS`.
- `DB` est un **double** partout où une règle demande un double *(règle standard, non confirmée Dartsee)*. Il n'existe pas de triple du bull.
- Forme canonique : majuscules, sans espace. L'analyse est insensible à la casse (`t20`, `miss` sont acceptés). Dans les vecteurs de test, `,` sépare les fléchettes.
- **Même case, même effet.** Dans tout jeu qui n'est pas déclaré *dépendant de la position*, deux fléchettes de même notation ont exactement le même effet, quels que soient leur origine et l'endroit exact de l'impact : le moteur NE DOIT PAS lire la position. La règle vaut pour treize des quatorze jeux. L'unique exception est `radar` (section 15), dont la fiche porte la mention « Dépend de la position : oui » ; l'usage qu'un tel jeu fait de la position est fixé en 2.13, et reste déterministe.
- `DartCore` transporte la position de l'impact avec chaque fléchette quand elle est connue (détection caméra, tap sur la cible). Elle sert aux cartes de chaleur et aux jeux dépendants de la position ; elle est absente d'une fléchette saisie par sa seule case.

### 2.3 Joueurs

- 1 à 8 joueurs, sauf mention contraire dans la fiche du jeu. Un moteur DOIT refuser (erreur à la création) un nombre de joueurs hors de ses bornes.
- L'ordre de jeu est l'ordre de la liste des joueurs fournie à la création ; il est fixe pendant toute la partie. Mélanger l'ordre est une fonction de l'écran de préparation, pas du moteur.
- Dans ce document, `J1` désigne le joueur d'index 0, `J2` l'index 1, etc.
- Pas d'équipes en v1 : chaque joueur joue pour lui. Il n'existe ni écran ni réglage d'équipe. Un seul jeu, `football` (section 14), répartit les joueurs en deux camps ; cette répartition est une règle du jeu, calculée à partir de l'index des joueurs, et les joueurs d'un même camp y partagent le même rang.

### 2.4 Entrées, phases, tours et manches

Vocabulaire : une **fléchette** est un lancer ; un **tour** est le passage d'un joueur (3 fléchettes au plus, sa « volée ») ; une **manche** (`round`) est un tour de chaque joueur encore en jeu.

Un moteur est un **réducteur déterministe et pur** :

```
état = reduce(config, seed, entrées)
```

- `config` : id du jeu, options, nombre de joueurs.
- `seed` : `UInt64` tiré par l'application à la création de la partie et enregistré avec elle (voir 2.8).
- `entrées` : journal ordonné de deux sortes d'entrées :
  - `dart(hit)` : une fléchette, d'où qu'elle vienne (détection caméra ou saisie manuelle). L'entrée peut porter en plus la **position** de l'impact (2.13) ; seul un jeu dépendant de la position la lit, et elle fait alors partie de l'entrée au même titre que `hit` ;
  - `endTurn` : la confirmation explicite « Fléchettes retirées / Joueur suivant ».

Mêmes `config`, `seed` et `entrées` DOIVENT produire le même état et les mêmes événements, sur toute machine et toute version.

**Phases**

| `phase` | Signification | `dart` | `endTurn` |
|---|---|---|---|
| `throwing` | le joueur courant peut lancer | acceptée | acceptée (tour écourté) |
| `turnComplete` | tour clos, en attente de confirmation | **refusée** | acceptée |
| `finished` | partie terminée | **refusée** | **refusée** |

Une entrée refusée ne modifie rien et n'est pas ajoutée au journal. L'interface signale la fléchette ignorée (« Tour terminé, retirez les fléchettes »).

**État initial commun** : `phase = throwing`, `currentPlayer = J1`, `round = 1`, volée vide. L'application demande de confirmer que le plateau est vide avant de démarrer *(Dartsee)* ; ce contrôle est hors moteur.

**Traitement de `dart(hit)`** (phase `throwing`) :

1. La fléchette est ajoutée à la volée du joueur courant, puis la règle du jeu s'applique (sections 3 à 16).
2. Si la règle termine la partie : `phase = finished` immédiatement, sans attendre de confirmation.
3. Sinon, si la règle clôt le tour (bust, auto-élimination, double du trou au Golf) ou si c'était la **3e fléchette** : **clôture du tour**, `phase = turnComplete`.
4. Sinon `phase` reste `throwing`.

**Clôture du tour** : moment où s'appliquent les effets de fin de volée propres au jeu (par exemple la division par deux de La Moitié, l'annonce du total de la volée, le verre offert de la Tireuse, le score du trou au Golf). Elle a lieu une seule fois par tour.

**Traitement de `endTurn`** :

1. Si `phase = throwing` (0, 1 ou 2 fléchettes lancées), le tour est d'abord clos comme ci-dessus. Les fléchettes non lancées ne sont **pas** enregistrées comme `MISS` : elles n'existent pas. L'interface demande une confirmation quand la volée est incomplète, sauf dans un jeu où s'arrêter avant la troisième fléchette est un coup normal (`golf`, 16.5).
2. Joueur suivant : le premier joueur **non éliminé** rencontré en parcourant la liste de façon circulaire à partir du joueur qui suit le joueur courant (en solo, c'est le même joueur).
3. Si ce parcours repasse par la fin de la liste (le joueur suivant a un index inférieur ou égal à celui du joueur courant), une manche se termine :
   - si une limite de manches est active et que `round` vaut cette limite : la volée est vidée, `phase = finished`, motif `roundLimit` (voir 2.6) ;
   - sinon `round += 1`.
4. Le nouveau tour commence : volée vide, `phase = throwing`, effets de début de tour propres au jeu (par exemple le retirage du Killer expert, le déplacement des cibles de Radar).

Le passage au joueur suivant ne se fait **jamais** sans `endTurn`. En v1, seule une action de l'utilisateur (bouton, ou geste équivalent) produit `endTurn`, sauf si le réglage `endsTurnOnTakeout` (désactivé par défaut, `ARCHITECTURE.md` §8.6) autorise la caméra à le produire quand le tour est déjà clos et qu'aucune fléchette n'attend de réponse. Hors de ce cas, la détection du retrait des fléchettes par la caméra peut proposer la confirmation, pas la remplacer. Pour le moteur, rien ne change : il reçoit la même entrée `endTurn`, d'où qu'elle vienne.

### 2.5 Annulation et correction

Toutes les opérations ci-dessous modifient le journal puis **rejouent toute la partie** avec `reduce`. Il n'y a pas d'état caché.

- **Annuler** (`undo`) : retire la dernière entrée du journal, quelle qu'elle soit (`dart` ou `endTurn`). Sans limite de profondeur, jusqu'au début de la partie (sur un journal vide, `undo` ne fait rien). Annuler un `endTurn` rouvre le tour précédent ; annuler la fléchette gagnante rouvre la partie.
- **Corriger une fléchette du tour courant** (`replaceDart(index, hit)`) : remplace la fléchette n° `index` (0 à 2) de la volée courante. Le « tour courant » est l'ensemble des fléchettes situées après le dernier `endTurn` du journal ; il reste corrigible même en phase `turnComplete` ou `finished` (cas d'une fléchette gagnante mal détectée).
- **Supprimer une fléchette du tour courant** (`removeDart(index)`) : retire une détection fantôme ; les suivantes se décalent.
- **Ajouter une fléchette manuellement** : c'est une entrée `dart` ordinaire, soumise aux mêmes refus.
- **Position** : une correction remplace la fléchette entière, position comprise. `replaceDart` enregistre la nouvelle position si la correction en donne une (réticule déplacé, nouveau tap sur la cible) et **efface** l'ancienne sinon (case choisie dans une liste). Une position ne survit donc jamais à un changement de case qui ne la redonne pas (2.13).
- Les fléchettes d'un tour déjà confirmé sont **verrouillées** *(Dartsee)* : pour les corriger il faut annuler jusqu'à ce tour.

**Règle de rejeu** : lors du rejeu, une entrée `dart` qui arrive dans une phase autre que `throwing` est **supprimée du journal**. Conséquences :

- si une correction transforme la 1re fléchette en bust, en victoire ou en double du trou (Golf), les fléchettes suivantes du tour disparaissent ;
- si une correction annule un bust, le tour se rouvre (`phase = throwing`) tant que la volée a moins de 3 fléchettes.

Chaque fléchette détectée automatiquement DOIT pouvoir être corrigée, supprimée ou remplacée par une saisie manuelle ; aucun jeu ne dépend de la caméra. Radar se joue lui aussi sans caméra, mais par un tap sur la cible à l'écran, qui donne la position dont il a besoin (2.13, 15.4).

Sons et animations : après une annulation ou une correction, l'interface se resynchronise sur le nouvel état **sans rejouer** les événements passés.

### 2.6 Limite de manches

Chaque jeu a une limite de manches, propre (nombre de manches fixe du jeu : `rounds`, `holes`, nombre de cibles) ou optionnelle (`maxRounds`).

- Option `maxRounds` : `Int?`, de 1 à 99, ou `nil` = pas de limite. La valeur par défaut est donnée dans chaque fiche.
- La fin par limite de manches est évaluée **uniquement au traitement de `endTurn`** (étape 3 de 2.4) : après la dernière fléchette de la dernière manche, la partie reste en `turnComplete` jusqu'à la confirmation, ce qui laisse le temps de corriger.
- À la limite, la partie se termine avec le motif `roundLimit` et le classement du jeu s'applique. La volée est alors vide : le dernier tour est confirmé, donc verrouillé (2.5), et le « tour courant » ne contient plus aucune fléchette. Pour corriger ce dernier tour, on annule ce `endTurn` : la partie revient en `turnComplete` avec sa volée. Une partie finie **sur une fléchette** garde au contraire sa volée, celle du tour gagnant, qui reste corrigible.

### 2.7 Fin de partie et classement

`finishReason` vaut :

- `victory` : un joueur (au Football, un camp) remplit la condition de victoire du jeu, sur une fléchette ;
- `lastPlayerStanding` : il ne reste qu'un joueur non éliminé (jeux à élimination) ;
- `roundLimit` : limite de manches atteinte.

**Classement** (`ranks`) : un rang par joueur, à partir de 1, selon les critères ordonnés donnés dans chaque fiche. Les joueurs à égalité sur **tous** les critères partagent le même rang, et le rang suivant est sauté (« 1, 1, 3 »). Il n'y a pas de mort subite en v1 : une égalité en tête donne plusieurs vainqueurs ex æquo.

Dans les jeux à élimination, les joueurs éliminés sont toujours classés **après** tous les joueurs en vie, dans l'ordre inverse d'élimination (le dernier éliminé est le mieux classé). Deux joueurs ne peuvent jamais être éliminés par la même fléchette.

**Titre des résultats** (`winnerTitle`). Les vainqueurs sont les joueurs de rang 1, et l'application les nomme. Un jeu dont le vainqueur n'est pas un joueur donne en plus, en phase `finished`, le titre à afficher et à annoncer à leur place. Un seul jeu le fait : `football`, où gagne un camp (14.7).

`ranks` est calculable à tout moment avec les mêmes critères : pendant la partie il sert de classement provisoire (badge 1er, 2e…), à la fin il est définitif. Un classement de soirée du type Dartsee (3 points au 1er, 2 au 2e, 1 au 3e) se construit à partir de `ranks`, hors de ce document.

### 2.8 Aléatoire déterministe

Tout tirage (zones du Killer, numéros de Combat, cibles du Cricket Light, maisons de Conquérant, cibles de Radar) DOIT venir du générateur ci-dessous, initialisé avec le `seed` de la partie, et consommé dans l'ordre décrit par chaque jeu. Comme `reduce` rejoue tout depuis le début, le générateur est recréé à chaque rejeu : une partie se rejoue à l'identique.

Les moteurs NE DOIVENT PAS utiliser `SystemRandomNumberGenerator`, `Int.random(in:)`, `shuffled()` ni leurs variantes `using:` (leur algorithme n'est pas garanti stable entre versions de Swift).

```swift
/// SplitMix64. Reference generator for every random draw of the game engines.
struct SeededRandom {
    private(set) var state: UInt64
    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Uniform enough for bound <= 20; exactly reproducible. bound >= 1.
    mutating func nextInt(below bound: Int) -> Int {
        Int(next() % UInt64(bound))
    }

    /// Fisher–Yates, from the last index down to 1.
    mutating func shuffled<T>(_ items: [T]) -> [T] {
        var a = items
        var i = a.count - 1
        while i >= 1 {
            a.swapAt(i, nextInt(below: i + 1))
            i -= 1
        }
        return a
    }
}
```

**Répartition sur l'anneau** (`ringLayout`), utilisée par Killer et Conquérant. Elle place, pour chaque joueur, un bloc de `width` numéros consécutifs dans le sens horaire, sans chevauchement, et réussit toujours tant que `playerCount * width <= 20`.

```swift
/// zones[player] = `width` consecutive ring numbers, clockwise.
func ringLayout(playerCount p: Int, width k: Int, rng: inout SeededRandom) -> [[Int]] {
    precondition(p * k <= 20)
    let offset = rng.nextInt(below: 20)                       // 1 draw
    var gaps = [Int](repeating: 0, count: p)
    for _ in 0..<(20 - p * k) {                               // 20 - p*k draws
        gaps[rng.nextInt(below: p)] += 1
    }
    let order = rng.shuffled(Array(0..<p))                    // p - 1 draws; order[slot] = player
    var zones = [[Int]](repeating: [], count: p)
    var cursor = offset
    for slot in 0..<p {
        zones[order[slot]] = (0..<k).map { ring[(cursor + $0) % 20] }
        cursor += k + gaps[slot]
    }
    return zones
}
```

**Valeurs de contrôle** (à mettre en tests unitaires du générateur) :

```
seed 0  : next() = E220A8397B1DCDAF, 6E789E6AA1B965F4, 06C45D188009454F, F88BB8A8724C81EC
seed 1  : next() = 910A2DEC89025CC1, BEEB8DA1658EEC67, F893A2EEFB32555E, 71C18690EE42C90B
seed 42 : next() = BDD732262FEB6E95, 28EFE333B266F103, 47526757130F9F52, 581CE1FF0E4AE394
seed 42 : nextInt(below: 20) répété 6 fois = 13, 11, 18, 4, 10, 2
seed 1  : nextInt(below: 2121) = 1934      (Radar tire avec des bornes de quelques milliers ; le biais du modulo y reste négligeable)
seed 1  : shuffled([1, 2, …, 20]) = [2, 15, 11, 4, 20, 5, 7, 17, 16, 14, 3, 1, 12, 8, 19, 10, 18, 13, 9, 6]
seed 42 : shuffled([15, 16, 17, 18, 19, 20]) = [19, 18, 15, 17, 20, 16]

ringLayout(playerCount: 3, width: 3), seed 1 :
  offset = 5 ; tirages d'intervalle = 1,0,2,0,2,0,0,0,1,0,1 → gaps = [6, 3, 2] ; order = [1, 0, 2]
  zones = J1 [8, 11, 14], J2 [6, 10, 15], J3 [20, 1, 18]            (14 tirages)
ringLayout(playerCount: 4, width: 2), seed 42 :
  offset = 13 ; gaps = [2, 2, 6, 2] ; order = [1, 0, 2, 3]
  zones = J1 [9, 12], J2 [16, 8], J3 [1, 18], J4 [17, 3]            (16 tirages)
ringLayout(playerCount: 2, width: 1), seed 1 : zones = J1 [11], J2 [6]   (20 tirages)
```

### 2.9 Tableau de score et surbrillances

Chaque moteur expose, pour l'affichage :

- les champs communs : `phase`, `currentPlayer`, `round`, la limite de manches (pour l'en-tête « n / max »), la volée courante (3 emplacements, étiquettes `T20`, `D5`, `MISS`…), `finishReason`, `ranks` ;
- les champs par joueur listés dans la fiche du jeu ;
- les **surbrillances** du plateau pour le joueur courant.

Une surbrillance est un triplet (zone, rôle, joueur propriétaire éventuel). Deux familles de zones :

- les **zones de cases** : `sector(n)` (tout le secteur), `single(n)`, `double(n)`, `treble(n)`, `outerBull`, `innerBull`, `bull` (les deux) ;
- la **zone disque** : `disc(x, y, radius)`, un disque de centre (`x`, `y`) et de rayon `radius`, en millimètres dans le repère du plateau (2.1). Elle se dessine par-dessus les cases, qu'elle chevauche librement, et ne correspond à aucune notation de fléchette. Seul `radar` s'en sert (15.7).

Une surbrillance peut porter en plus, quand la fiche du jeu le demande : une **étiquette** courte (`+r`, `+10`, `2`) et un **nombre de points de vie** de 1 à 3 (boucliers de Conquérant, points de vie d'une cible de Radar).

| Rôle | Sens pour le joueur courant |
|---|---|
| `target` | à viser : la toucher le fait progresser, marquer ou attaquer |
| `secondary` | utile mais moins rentable que `target` |
| `own` | lui appartient, sans effet utile en ce moment |
| `avoid` | à éviter : la toucher le pénalise |
| `opponent` | appartient à un adversaire, affichée pour information (pas attaquable en ce moment) |
| `inactive` | zone morte : plus aucun effet pour personne |

Quand un propriétaire est indiqué, la zone est dessinée dans la couleur de ce joueur. Les surbrillances sont recalculées après chaque entrée, toujours pour le joueur courant (y compris en phase `turnComplete`, d'après l'état après sa volée). En phase `finished`, aucune surbrillance.

Rôles employés par jeu :

| Jeu | Zones | Rôles |
|---|---|---|
| `x01`, `moonLanding` | cases de finition | `target` |
| `cricket` | `sector`, `bull` | `target`, `secondary`, `inactive` |
| `killer` | `sector` | `target`, `own`, `avoid`, `opponent` |
| `aroundTheClock`, `halveIt` | `sector`, `double`, `treble`, `bull`, `innerBull` | `target` |
| `shanghai` | `single`, `double`, `treble` ; `sector` (voisins en `lite`) | `target`, `secondary` |
| `fight` | `sector` | `target`, `secondary`, `own` |
| `conqueror` | `sector`, `bull` | `target`, `secondary`, `own`, `opponent` |
| `football` | `sector`, `bull` | `target`, `avoid` |
| `radar` | `disc` | `target` |
| `golf` | `double`, `treble`, `single` | `target`, `secondary` |
| `highScore`, `beerTap` | aucune | — |

### 2.10 Événements

Chaque entrée appliquée produit une liste ordonnée d'événements, destinée aux sons, à la voix et aux animations. Les événements font partie du résultat déterministe du moteur. Événements communs :

| Événement | Quand |
|---|---|
| `dartRegistered(player, hit)` | toute fléchette acceptée, en premier |
| `noEffect(player)` | la fléchette ne change aucune valeur de jeu (y compris `MISS`). Quand la section du jeu nomme un événement propre pour ce cas (`doubleInRequired` au X01, `healWasted` au Combat), cet événement est émis **à la place** de `noEffect` |
| `turnCompleted(player)` | clôture du tour (3e fléchette, bust, auto-élimination, double du trou au Golf ou confirmation anticipée) |
| `roundStarted(round)` | début d'une nouvelle manche |
| `turnStarted(player, round)` | début d'un tour, après `endTurn` |
| `playerEliminated(player, by)` | élimination ; `by` = joueur responsable |
| `gameFinished(reason)` | fin de partie, toujours **en dernier** |

Jeux à points bruts (`x01`, `highScore`, `moonLanding`, `beerTap`), à la clôture d'un tour sans bust :

| Événement | Quand |
|---|---|
| `turnScored(player, points)` | total réellement compté pour la volée |
| `oneEighty(player)` | ce total vaut 180 |
| `highTurn(player, points)` | ce total est compris entre 100 et 179 |

`radar` émet aussi `turnScored` à chaque clôture de tour (ses points ne sont pas ceux des cases), mais jamais `oneEighty` ni `highTurn`.

Ordre dans une même entrée :

- `dart` : `dartRegistered`, puis les effets de la fléchette dans l'ordre où ils se produisent, puis (si le tour se clôt) les événements de clôture (`turnScored`, `oneEighty`/`highTurn`, `halved`, `bonusGlass`, `holeCompleted`…) et `turnCompleted`. Si la fléchette termine la partie, il n'y a pas de `turnCompleted` : la liste finit par `gameFinished`.
- `endTurn` : [événements de clôture et `turnCompleted` si le tour était encore ouvert], puis soit `gameFinished(roundLimit)`, soit [`roundStarted`], [effets de début de tour : `zoneChanged`, `blobsMoved`], `turnStarted`.

**Catalogue complet des événements.** Chaque nom n'a qu'une forme ; les champs sont dans cet ordre. `player` est toujours le joueur courant, sauf mention contraire dans la section du jeu.

| Jeu | Événements propres |
|---|---|
| tous | `dartRegistered(player, hit)`, `noEffect(player)`, `turnCompleted(player)`, `roundStarted(round)`, `turnStarted(player, round)`, `playerEliminated(player, by)`, `gameFinished(reason)` |
| points bruts | `turnScored(player, points)`, `oneEighty(player)`, `highTurn(player, points)` |
| `x01` | `doubleInOpened(player)`, `doubleInRequired(player)`, `bust(player, reason)`, `checkout(player, points, darts)` |
| `cricket` | `marksScored(player, target, count)`, `targetClosed(player, target)`, `targetDead(target)`, `pointsScored(player, points)`, `pointsGiven(player, to, pointsEach)` |
| `killer` | `armingHit(player, progress)`, `becameKiller(player)`, `lifeLost(player, by, livesLeft)`, `zoneChanged(player, zone)` |
| `aroundTheClock` | `targetHit(player, number, advancedBy)` |
| `shanghai` | `targetScored(player, points)`, `neighbourHit(player, points)`, `shanghai(player)` |
| `halveIt` | `targetScored(player, points)`, `halved(player, points)` |
| `moonLanding` | `bust(player, reason)`, `landed(player)` |
| `fight` | `damaged(player, by, amount, livesLeft)`, `healed(player, amount, lives)`, `healWasted(player)` |
| `conqueror` | `sectorClaimed(player, sector)`, `sectorStrengthened(player, sector, lives)`, `sectorDamaged(player, sector, livesLeft)`, `sectorConquered(player, sector, from)`, `kingOfTheHill(player)` |
| `beerTap` | `glassFilled(player, count, glasses)`, `bonusGlass(player, glasses)` |
| `football` | `ballMoved(player, by, ball)`, `goalScored(player, side, goals, ownGoal)` |
| `radar` | `blobDamaged(player, blob, points, hitPointsLeft)`, `blobDestroyed(player, blob, points)`, `blobsMoved` |
| `golf` | `shotPlayed(player, strokes)`, `holeCompleted(player, hole, strokes, total)`, `holeInOne(player, hole)` |

`targetHit` n'existe que pour le Tour de l'horloge ; Shanghai et La Moitié émettent `targetScored`. Les dix événements des quatre dernières lignes sont nouveaux en version 1.1.

### 2.11 Format des vecteurs de test

```
jeu      id { option: valeur, … }      options absentes = valeurs par défaut
joueurs  nombre
seed     valeur                        absent = 0 (sans effet si le jeu ne tire rien)
entrées  T20, S5, MISS | D16 …         « , » sépare les fléchettes ; « | » est un endTurn
attendu  valeurs exactes après la dernière entrée
```

`J1.remaining = 121` désigne le champ `remaining` du joueur d'index 0. `ranks = [1, 2, 2]` est indexé par joueur. `×3` abrège une répétition (`MISS ×3` = `MISS, MISS, MISS`). Chaque vecteur est un test Swift Testing à écrire tel quel (les suites « a, b, c… » se prêtent aux tests paramétrés). Les tests d'un jeu sont les méthodes d'une `@Suite struct` qui porte le nom de ce jeu (`KillerTests`), une méthode par vecteur (`kil1_…`) : aucune fonction de test n'est déclarée au niveau fichier, parce que les quatorze jeux partagent une cible de test (`ARCHITECTURE.md` §5.7, §13.4).

Une fléchette écrite `S6@(124.0, 0.0)` porte une **position enregistrée** : `x = 124.0`, `y = 0.0`, en millimètres dans le repère du plateau (2.1). Sans `@`, la fléchette n'a pas de position enregistrée. Cette écriture ne sert que dans les vecteurs de `radar` ; dans tous les autres jeux une position, présente ou non, ne change rien. Dans les valeurs attendues, les nombres négatifs s'écrivent avec le signe ASCII (`ball = -1`).

Toutes les valeurs attendues de ce document (y compris les tirages liés à un `seed`) ont été calculées avec une implémentation de référence des règles ci-dessous, écrite séparément : un test qui échoue signale donc un écart du moteur, pas une approximation du document.

### 2.12 Vecteurs de test communs

Ils utilisent `x01` (section 3) mais vérifient le socle commun.

```
COM-1  4e fléchette refusée
jeu      x01 { startScore: 301 }          joueurs 1
entrées  T20, T20, T20
attendu  phase = turnComplete ; J1.remaining = 121
puis     dart(S20) → refusée ; état inchangé ; journal inchangé (3 entrées)

COM-2  confirmation anticipée
jeu      x01 { startScore: 301 }          joueurs 2
entrées  T20 | S5, S5, S5 |
attendu  phase = throwing ; currentPlayer = J1 ; round = 2 ; volée vide
         J1.remaining = 241 ; J1.dartsThrown = 1 ; J2.remaining = 286 ; J2.dartsThrown = 3

COM-3  correction = rejeu
jeu      x01 { startScore: 301 }          joueurs 1
entrées  T20, S1, S5                      → J1.remaining = 235
puis     replaceDart(1, T20)              → journal = T20, T20, S5 ; J1.remaining = 176 ; phase = turnComplete

COM-4  une correction qui provoque un bust supprime les fléchettes suivantes
jeu      x01 { startScore: 301, outRule: double }   joueurs 1
entrées  T20, T20, T20 | T20, T17, MISS | S4, S4, D1
attendu  phase = finished (victory) ; J1.remaining = 0
puis     replaceDart(0, S9)               → volée = [S9] ; bust(oneLeft) ; J1.remaining = 10 ;
                                            phase = turnComplete ; J1.busts = 1

COM-5  une correction qui annule un bust rouvre le tour
jeu      x01 { startScore: 301, outRule: double }   joueurs 1
entrées  T20, T20, T20 | T20, T17, MISS | S9
attendu  phase = turnComplete ; J1.remaining = 10 ; J1.busts = 1
puis     replaceDart(0, S4)               → phase = throwing ; volée = [S4] ; J1.remaining = 6 ; J1.busts = 0

COM-6  annulation à travers une confirmation
jeu      x01 { startScore: 301 }          joueurs 1
entrées  T20, S1, S5 |
attendu  phase = throwing ; round = 2 ; volée vide ; J1.remaining = 235
puis     undo → phase = turnComplete ; round = 1 ; volée = [T20, S1, S5] ; J1.remaining = 235
puis     undo → phase = throwing ; volée = [T20, S1] ; J1.remaining = 240

COM-7  la limite de manches n'agit qu'à la confirmation
jeu      x01 { startScore: 301, maxRounds: 1 }      joueurs 3
entrées  T20, T20, T20 | S20, S20, S20 | S20, S20, S20
attendu  phase = turnComplete ; currentPlayer = J3 ; round = 1
puis     endTurn → phase = finished ; finishReason = roundLimit ; ranks = [1, 2, 2] ; volée vide
         J1.remaining = 121 ; J2.remaining = 241 ; J3.remaining = 241
puis     dart(S1) → refusée ; endTurn → refusée
```

### 2.13 Position de l'impact et jeux dépendants de la position

Une entrée `dart` porte toujours une case (`hit`) et, quand elle est connue, une **position enregistrée** : le point (`x`, `y`) où la pointe est plantée, en millimètres dans le repère du plateau (2.1), en coordonnées nominales (celles d'une cible réglementaire).

**Qui lit la position.** Un jeu **dépendant de la position** le déclare dans sa fiche. Il n'y en a qu'un : `radar`. Les treize autres ne la lisent jamais (2.2).

**Point d'impact.** Pour un jeu dépendant de la position, le point d'impact d'une fléchette est défini pour toute entrée, de sorte que le moteur reste une fonction totale et déterministe :

1. `hit == MISS` : la fléchette n'a **pas** de point d'impact. Elle ne touche rien, même si une position a été enregistrée (rebond, fléchette hors de la zone de score).
2. Sinon, si une position est enregistrée : c'est elle, **telle quelle**. Le moteur ne vérifie pas qu'elle tombe dans la case annoncée par `hit`.
3. Sinon : la **position canonique** de la case, donnée par la table ci-dessous.

**Arithmétique entière.** Un jeu dépendant de la position ne calcule qu'en entiers, en **dixièmes de millimètre**. Une position enregistrée est convertie une fois : `X = arrondi(10 × x)`, `Y = arrondi(10 × y)`, à l'entier le plus proche, les demis s'éloignant de zéro (`Int((10 * x).rounded())` en Swift ; vecteur RAD-3). Pour que la conversion reste totale : quand `10 × x` n'est pas un nombre fini (NaN, infini, dépassement), la coordonnée vaut 1 000 000 dixièmes ; sinon l'arrondi est borné à l'intervalle ±1 000 000 dixièmes. Un tel point est hors du plateau et ne touche aucune cible. Les positions canoniques sont données directement en dixièmes. Aucun sinus, aucune racine carrée, aucune comparaison de nombres à virgule n'entre dans une règle : le résultat est le même sur toute machine.

**Position canonique d'une case.** C'est le milieu de la case, c'est-à-dire `BoardGeometry.standard.centre(of:)` de `DartCore`, arrondi au dixième :

- `DB` : le centre, (0, 0) ;
- `SB` : le milieu de l'anneau du bull extérieur, vers le 20 : rayon 11,125 mm, soit (0, 111) ;
- `Sn` : le milieu du simple **extérieur** (entre le triple et le double), rayon 134,5 mm, sur l'axe du secteur ;
- `Tn` : le milieu de l'anneau triple, rayon 103 mm ;
- `Dn` : le milieu de l'anneau double, rayon 166 mm ;
- `MISS` : aucune.

Pour un secteur d'index `i` dans `ring` et un rayon `ρ` : `X = arrondi(10 × ρ × sin(18° × i))`, `Y = arrondi(10 × ρ × cos(18° × i))`. **La table fait foi** (un moteur l'embarque telle quelle plutôt que de la recalculer) :

```
numéro      S (simple)        T (triple)        D (double)
  20     (    0,  1345)    (    0,  1030)    (    0,  1660)
   1     (  416,  1279)    (  318,   980)    (  513,  1579)
  18     (  791,  1088)    (  605,   833)    (  976,  1343)
   4     ( 1088,   791)    (  833,   605)    ( 1343,   976)
  13     ( 1279,   416)    (  980,   318)    ( 1579,   513)
   6     ( 1345,     0)    ( 1030,     0)    ( 1660,     0)
  10     ( 1279,  -416)    (  980,  -318)    ( 1579,  -513)
  15     ( 1088,  -791)    (  833,  -605)    ( 1343,  -976)
   2     (  791, -1088)    (  605,  -833)    (  976, -1343)
  17     (  416, -1279)    (  318,  -980)    (  513, -1579)
   3     (    0, -1345)    (    0, -1030)    (    0, -1660)
  19     ( -416, -1279)    ( -318,  -980)    ( -513, -1579)
   7     ( -791, -1088)    ( -605,  -833)    ( -976, -1343)
  16     (-1088,  -791)    ( -833,  -605)    (-1343,  -976)
   8     (-1279,  -416)    ( -980,  -318)    (-1579,  -513)
  11     (-1345,     0)    (-1030,     0)    (-1660,     0)
  14     (-1279,   416)    ( -980,   318)    (-1579,   513)
   9     (-1088,   791)    ( -833,   605)    (-1343,   976)
  12     ( -791,  1088)    ( -605,   833)    ( -976,  1343)
   5     ( -416,  1279)    ( -318,   980)    ( -513,  1579)
SB = (0, 111)        DB = (0, 0)        MISS : aucune position
```

**D'où vient la position.**

- Détection par la caméra : la pointe mesurée. Tap sur la cible à l'écran : le point touché, ramené en coordonnées nominales. Dans les deux cas l'application enregistre la position avec la case.
- Case choisie sans geste sur la cible (liste de cases, proposition de case voisine sur l'écran de correction, vecteur de test sans `@`) : pas de position ; la position canonique s'applique.
- Correction : voir 2.5. `replaceDart` remplace la position ou l'efface ; `removeDart` retire la fléchette entière, position comprise ; `undo` retire la dernière entrée. Comme tout est rejoué depuis le journal, l'effet d'une correction de position est déterministe.

**Conséquences.**

- Dans un jeu dépendant de la position, deux fléchettes de même case peuvent avoir des effets différents, et deux fléchettes de cases différentes le même effet. Le regroupement « même effet » utilisé pour les détections douteuses (deux cases candidates pour une même pointe) se calcule donc sur le couple (case, position) : à position égale, toutes les cases candidates autres que `MISS` ont le même effet, et un doute entre deux cases voisines ne mérite pas de question au joueur.
- Le doute qui compte dans un tel jeu porte sur la **pointe elle-même** : mesurée à quelques dixièmes de millimètre près, elle peut être d'un côté ou de l'autre du bord d'une cible. L'application NE DOIT PAS trancher ce cas en silence. Pour une fléchette détectée par la caméra, elle rejoue la meilleure case aux quatre points situés à un écart-type de la pointe mesurée, de part et d'autre, le long de l'axe de la fléchette et en travers ; si l'un d'eux ne donne pas le même effet que la pointe, la fléchette est comptée mais marquée « à vérifier » (`ARCHITECTURE.md` §8.4.8). Le moteur, lui, ne change pas : il prend la position qu'on lui donne.
- Dans tous les autres jeux, retirer, ajouter ou modifier une position ne change aucun état, aucun événement, aucun classement.

---

## 3. X01 (`x01`)

### 3.1 Fiche

- **id** : `x01`
- **Noms** : FR « X01 » (sous-titre « 301 / 501 / 701 ») — EN "X01"
- **En une ligne** : FR « Partez de 301, 501 ou 701 et descendez exactement à zéro avant les autres. » — EN "Start from 301, 501 or 701 and be the first to hit exactly zero."
- **Joueurs** : 1 à 8.

### 3.2 Options

| Option | Type | Valeurs | Défaut |
|---|---|---|---|
| `startScore` | Int | 301, 501, 701 | 301 |
| `inRule` | enum | `straight` (entrée libre), `double` (entrée sur un double) | `straight` |
| `outRule` | enum | `straight` (sortie libre), `double` (sortie sur un double) | `straight` |
| `maxRounds` | Int? | 1–99 ou `nil` | 20 |

Les défauts 301 / entrée libre / sortie libre correspondent à l'écran Dartsee « 301 | Single in | Single out ». Dartsee limite à 15 manches ; 20 laisse finir un 501 ou un 701 entre joueurs occasionnels.

### 3.3 État initial

Par joueur : `remaining = startScore`, `isOpen = (inRule == straight)`, `dartsThrown = 0`, `busts = 0`.

### 3.4 Effet d'une fléchette

Soit `R` le `remaining` du joueur courant et `v` les points de la fléchette (2.2). Dans tous les cas `dartsThrown += 1`.

| Cas (évalués dans cet ordre) | Effet |
|---|---|
| `MISS` | rien d'autre (`noEffect`) |
| `isOpen == false` et la fléchette n'est pas un double | 0 point ; `doubleInRequired`, sans `noEffect` (2.10) |
| `isOpen == false` et la fléchette est un double (`D1`–`D20`, `DB`) | `isOpen = true`, `doubleInOpened`, puis la fléchette est comptée par les lignes suivantes |
| `R − v < 0` | **bust**, motif `belowZero` |
| `R − v == 0`, `outRule == straight` | **victoire** : `remaining = 0` |
| `R − v == 0`, `outRule == double`, fléchette double (`D1`–`D20`, `DB`) | **victoire** : `remaining = 0` |
| `R − v == 0`, `outRule == double`, fléchette non double | **bust**, motif `notADouble` |
| `R − v == 1`, `outRule == double` | **bust**, motif `oneLeft` (on ne peut plus finir sur un double) |
| sinon | `remaining = R − v` |

Valeurs : `Sn` = n, `Dn` = 2n, `Tn` = 3n, `SB` = 25, `DB` = 50. `DB` compte comme double pour l'entrée et la sortie *(règle standard, non confirmée Dartsee)*.

### 3.5 Déroulement du tour

- 3 fléchettes par tour.
- **Bust** *(Dartsee : « aucun lancer du tour ne compte »)* : le tour est clos immédiatement (`phase = turnComplete`, les fléchettes restantes ne se lancent pas), `remaining` et `isOpen` reprennent leur valeur du **début du tour**, `busts += 1`. Les fléchettes du tour restent comptées dans `dartsThrown`.
- **Victoire** : la partie se termine sur la fléchette.
- Remarque : avec `startScore >= 301`, un bust est impossible pendant le tour où un joueur ouvre en double-in (180 points au maximum par tour) ; la restauration de `isOpen` est spécifiée pour rester générale.

### 3.6 Élimination, victoire, classement

- Pas d'élimination.
- **Victoire** : le premier joueur à atteindre exactement 0 selon `outRule` gagne ; la partie s'arrête aussitôt (`victory`), les autres ne finissent pas la manche *(règle standard, non confirmée Dartsee)*.
- **Limite de manches** : `roundLimit` ; le plus petit `remaining` gagne *(règle standard, non confirmée Dartsee)*.
- **Classement** dans tous les cas : (1) `remaining` croissant ; (2) ex æquo.

### 3.7 Tableau de score et surbrillances

Par joueur : `remaining` (valeur principale), total de la dernière volée ou mention « BUST », `dartsThrown`, moyenne par volée `3 × (startScore − remaining) / dartsThrown` (0 sans fléchette), `busts`, badge « à ouvrir » tant que `isOpen == false`, rang.

Surbrillances pour le joueur courant :

- `isOpen == false` : `target` sur les 20 doubles et `innerBull` (21 cases).
- Sinon, **cases de finition directe** : toutes les cases dont les points valent exactement `remaining` et qui respectent `outRule` → `target`. Exemples : 20 restant en sortie libre → `single(20)`, `double(10)` ; 20 restant en sortie double → `double(10)` ; 60 en sortie libre → `treble(20)` ; 50 → `innerBull` ; 25 en sortie libre → `outerBull`.
- Sinon : aucune surbrillance. (Un conseil de finition en plusieurs fléchettes est un plus d'interface, hors moteur.)

### 3.8 Événements

| Événement | Quand | Idée de son / animation |
|---|---|---|
| `doubleInOpened(player)` | premier double en double-in | son d'ouverture |
| `doubleInRequired(player)` | fléchette non comptée avant l'ouverture | son neutre |
| `bust(player, reason)` | bust (`belowZero`, `notADouble`, `oneLeft`) | buzzer, score qui « rebondit » |
| `turnScored`, `highTurn`, `oneEighty` | clôture d'un tour sans bust (2.10) | annonce vocale du total ; « cent quatre-vingts ! » |
| `checkout(player, points, darts)` | fléchette gagnante ; `points` = total de la volée gagnante | fanfare |
| `gameFinished(victory \| roundLimit)` | fin de partie | écran de victoire |

Une volée bustée n'émet ni `turnScored` ni `oneEighty`. En double-in, seuls les points réellement soustraits comptent dans `turnScored`.

### 3.9 Vecteurs de test

```
X01-1  180 puis finition libre
jeu      x01 { startScore: 301 }          joueurs 1
entrées  T20, T20, T20
attendu  phase = turnComplete ; J1.remaining = 121
         événements de la 3e fléchette : dartRegistered, turnScored(180), oneEighty, turnCompleted
entrées  (suite) | T20, S11, DB
attendu  phase = finished ; finishReason = victory ; J1.remaining = 0 ; J1.dartsThrown = 6 ; ranks = [1]
         événements de la dernière fléchette : dartRegistered, checkout(points: 121, darts: 3), gameFinished(victory)

X01-2  sortie en double depuis 10 (cas du manuel Dartsee)
jeu      x01 { startScore: 301, outRule: double }   joueurs 1
entrées  T20, T20, T20 | T20, T17, MISS |
attendu  phase = throwing ; round = 3 ; J1.remaining = 10 ; J1.dartsThrown = 6 ; surbrillance target = [double(5)]
suite a  S15          → bust(belowZero)  ; phase = turnComplete ; remaining = 10 ; busts = 1 ; dartsThrown = 7
suite b  S10          → bust(notADouble) ; phase = turnComplete ; remaining = 10 ; busts = 1
suite c  S9           → bust(oneLeft)    ; phase = turnComplete ; remaining = 10 ; busts = 1
suite d  D5           → phase = finished (victory) ; remaining = 0 ; dartsThrown = 7
suite e  S2, D4       → phase = finished (victory) ; remaining = 0 ; dartsThrown = 8
suite f  S4, S4, S2   → 6, puis 2, puis bust(notADouble) ; remaining = 10 ; busts = 1 ; dartsThrown = 9
suite g  S4, S4, D1   → phase = finished (victory) ; remaining = 0 ; dartsThrown = 9
après a, b, c ou f : dart(D5) est refusée tant que endTurn n'est pas reçu.

X01-3  entrée et sortie en double
jeu      x01 { startScore: 301, inRule: double, outRule: double }   joueurs 2
attendu  (début) surbrillance target = les 20 doubles + innerBull
entrées  S20, T20, D10
attendu  J1.isOpen = true ; J1.remaining = 281 (seul D10 compte) ; J1.dartsThrown = 3
         événements : doubleInRequired, doubleInRequired, doubleInOpened ; turnScored(20)
entrées  (suite) | MISS, DB, T20
attendu  J2.isOpen = true ; J2.remaining = 191 (DB ouvre et compte 50, puis 60) ; phase = turnComplete

X01-4  victoire à deux joueurs et classement
jeu      x01 { startScore: 301 }          joueurs 2
entrées  T20, T20, T20 | S20, S1, MISS | T20, S11, DB
attendu  phase = finished ; finishReason = victory ; J1.remaining = 0 ; J2.remaining = 280 ; ranks = [1, 2]

X01-5  surbrillances de finition
jeu      x01 { startScore: 301 }          joueurs 1
entrées  T20, T20, T20 | T20, S20, S20 | S1
attendu  J1.remaining = 20 ; target = [single(20), double(10)]
         (même partie avec outRule: double → target = [double(10)])
entrées  T20, T20, T20 | T20, S1
attendu  J1.remaining = 60 ; phase = throwing ; target = [treble(20)]
```

Voir aussi COM-1 à COM-7 (2.12), qui couvrent bust après correction, confirmation anticipée et limite de manches.

---

## 4. Cricket (`cricket`)

### 4.1 Fiche

- **id** : `cricket`
- **Noms** : FR « Cricket » — EN "Cricket"
- **En une ligne** : FR « Fermez les numéros 15 à 20 et le bull en les touchant trois fois, puis marquez des points sur ceux que les autres n'ont pas fermés. » — EN "Close 15 to 20 and the bull with three marks each, then score on what the others left open."
- **Joueurs** : 1 à 8.

### 4.2 Options

| Option | Type | Valeurs | Défaut |
|---|---|---|---|
| `scoring` | enum | `cutThroat` (les points vont aux adversaires, le plus petit score gagne), `standard` (on marque pour soi, le plus grand score gagne) | `cutThroat` *(défaut Dartsee)* |
| `targets` | enum | `normal` (20, 19, 18, 17, 16, 15, bull), `light` (4 numéros tirés au sort) | `normal` |
| `maxRounds` | Int? | 1–99 ou `nil` | 20 *(manuel Dartsee)* |

### 4.3 État initial

- Liste des cibles :
  - `normal` : `[20, 19, 18, 17, 16, 15, bull]`.
  - `light` : `s = rng.shuffled([15, 16, 17, 18, 19, 20])` (5 tirages), cibles = les 4 premiers éléments de `s`, triés par ordre décroissant ; le bull n'est pas une cible. Dartsee dit seulement « quatre numéros au hasard » ; le tirage parmi 15–20 est une *(conception propre, non confirmée Dartsee)*.
- Par joueur : `marks[cible] = 0` pour chaque cible, `points = 0`.

Un joueur a **fermé** une cible quand `marks[cible] == 3`. Une cible est **morte** quand tous les joueurs l'ont fermée.

### 4.4 Effet d'une fléchette

Valeur d'une cible : son numéro, ou 25 pour le bull.

| Fléchette | Cible | Nombre de marques |
|---|---|---|
| `Sn`, `Dn`, `Tn` avec n dans les cibles | n | 1, 2, 3 |
| `SB`, si le bull est une cible | bull | 1 *(règle standard, non confirmée Dartsee)* |
| `DB`, si le bull est une cible | bull | 2 *(règle standard, non confirmée Dartsee)* |
| numéro hors cibles, bull hors cibles, `MISS` | — | aucun effet (`noEffect`) |

Les marques d'une fléchette sont traitées **une par une**, dans l'ordre. Pour chaque marque du joueur courant `P` sur la cible `t` :

1. Si `marks[P][t] < 3` : `marks[P][t] += 1` (marque de fermeture). Si elle atteint 3 : `targetClosed`, et `targetDead` si tous les joueurs ont fermé `t`.
2. Sinon (`P` a déjà fermé `t`), soit `O` l'ensemble des **autres** joueurs avec `marks[q][t] < 3` :
   - `O` vide : marque perdue, aucun effet ;
   - `scoring == standard` : `points[P] += valeur(t)` ;
   - `scoring == cutThroat` : `points[q] += valeur(t)` pour chaque `q` de `O`.

Une même fléchette peut donc fermer puis marquer : avec 2 marques sur le 20, un `T20` donne 1 marque de fermeture puis 2 marques à points (40).

Après chaque fléchette, la condition de victoire (4.6) est évaluée.

### 4.5 Déroulement du tour

3 fléchettes par tour. Pas de bust, rien n'est jamais annulé. Seule la fin de partie écourte un tour.

### 4.6 Élimination, victoire, classement

- Pas d'élimination.
- « Meilleur score » signifie : plus **grand** en `standard`, plus **petit** en `cutThroat`.
- **Victoire** (`victory`), évaluée après chaque fléchette : la partie se termine s'il existe un joueur `W` qui a fermé **toutes** les cibles et tel qu'**aucun autre joueur n'a un score strictement meilleur** que le sien. Ce joueur n'est pas forcément celui qui vient de lancer (en `cutThroat`, les points donnés par un autre peuvent faire gagner `W`).
- Un joueur qui a tout fermé mais dont le score est moins bon ne gagne pas : la partie continue *(règle standard, non confirmée Dartsee)*.
- En solo, la partie se termine dès que toutes les cibles sont fermées (aucun point n'est possible).
- **Limite de manches** : `roundLimit`.
- **Classement** dans tous les cas : (1) meilleur score ; (2) nombre total de marques de fermeture (somme des `marks`, 3 au plus par cible) décroissant ; (3) ex æquo. Le joueur `W` est toujours premier avec ces critères.

### 4.7 Tableau de score et surbrillances

Par joueur : `points`, `marks` par cible (0 à 3, dessinées « / », « X », « ⊗ »), nombre de cibles fermées, rang. Grille Dartsee : une colonne par joueur, une ligne par cible.

Surbrillances pour le joueur courant `P`, pour chaque cible `t` (zone `sector(t)` ou `bull`) :

- `marks[P][t] < 3` → `target` (à fermer) ;
- `P` a fermé `t` et au moins un autre joueur ne l'a pas fermée → `secondary` (à marquer) ;
- cible morte → `inactive`.

### 4.8 Événements

| Événement | Quand | Idée de son / animation |
|---|---|---|
| `marksScored(player, target, count)` | la fléchette a posé `count` marques de fermeture (1 à 3) | un « clic » par marque |
| `targetClosed(player, target)` | 3e marque | son de verrou |
| `targetDead(target)` | fermée par tous | la ligne se grise |
| `pointsScored(player, points)` | `standard` : points gagnés par la fléchette | compteur qui monte |
| `pointsGiven(player, to, pointsEach)` | `cutThroat` : points infligés à chaque joueur de `to` | flèche vers les victimes |
| `noEffect(player)` | hors cible, `MISS`, ou marques perdues sur une cible morte | son neutre |
| `gameFinished(victory \| roundLimit)` | fin de partie | écran de victoire |

### 4.9 Vecteurs de test

```
CRI-1  fermer, marquer, cible morte
jeu      cricket { scoring: standard }    joueurs 2
entrées  T20, S20, D20 | T20, T20, S19
attendu  J1.marks[20] = 3 ; J1.points = 60 (20 + 40)
         J2.marks[20] = 3 ; J2.marks[19] = 1 ; J2.points = 0
         le 2e T20 de J2 n'a aucun effet (20 morte) ; phase = turnComplete ; currentPlayer = J2

CRI-2  une fléchette qui ferme puis marque
jeu      cricket { scoring: standard }    joueurs 2
entrées  D20, T20, MISS
attendu  J1.marks[20] = 3 ; J1.points = 40 ; J2.points = 0

CRI-3  cut-throat à trois
jeu      cricket { scoring: cutThroat }   joueurs 3
entrées  T20, T20, MISS | T20, S20, MISS
attendu  marks[20] = J1 3, J2 3, J3 0
         points = J1 0, J2 60, J3 80   (60 à J2 et J3, puis 20 à J3 seul)

CRI-4  bull : SB = 1 marque, DB = 2 marques, 25 points par marque
jeu      cricket { scoring: standard }    joueurs 2
entrées  DB, SB, DB
attendu  J1.marks[bull] = 3 ; J1.points = 50

CRI-5  victoire dès la dernière fermeture
jeu      cricket { scoring: standard }    joueurs 2
entrées  T20, T19, T18 | MISS ×3 | T17, T16, T15 | MISS ×3 | DB, SB
attendu  phase = finished ; finishReason = victory ; J1 a fermé les 7 cibles ; points = 0 / 0 ; ranks = [1, 2]
         la partie finit sur la 2e fléchette du tour ; dart(S20) est ensuite refusée

CRI-6  tout fermé mais en retard : pas de victoire avant d'avoir rattrapé
jeu      cricket { scoring: standard }    joueurs 2
entrées  T20, S20, S20 | T20, T19, T18 | MISS ×3 | T17, T16, T15 | MISS ×3 | DB, SB, MISS
attendu  phase = turnComplete ; J2 a tout fermé ; points = J1 40, J2 0 ; la partie continue
entrées  (suite) | MISS ×3 | T19
attendu  phase = finished ; finishReason = victory ; points = J1 40, J2 57 ; ranks = [2, 1]

CRI-7  cut-throat : le vainqueur n'est pas le lanceur
jeu      cricket { scoring: cutThroat }   joueurs 3
entrées  T20, S20, MISS | T20, T19, T18 | MISS ×3 |
         MISS ×3 | T17, T16, T15 | MISS ×3 |
         MISS ×3 | DB, SB, MISS |
attendu  J2 a tout fermé ; points = J1 0, J2 20, J3 20 ; pas de victoire (J1 est strictement meilleur) ;
         currentPlayer = J3 ; round = 3
entrées  (suite) T19, S19
attendu  points = J1 19, J2 20, J3 20 ; phase = throwing
entrées  (suite) S19
attendu  points = J1 38, J2 20, J3 20 ; phase = finished ; finishReason = victory
         ranks = [3, 1, 2]   (J2 et J3 à 20 points ; J2 a 21 marques, J3 en a 3)

CRI-8  Cricket Light, cibles tirées au sort
jeu      cricket { targets: light }       joueurs 2      seed 42
attendu  (début) cibles = [19, 18, 17, 15]
entrées  T20, T19, S15
attendu  T20 sans effet (20 n'est pas une cible) ; J1.marks = { 19: 3, 18: 0, 17: 0, 15: 1 } ; points = 0 / 0

CRI-9  solo
jeu      cricket { scoring: standard }    joueurs 1
entrées  T20, T20, T19 | T18, T17, T16 | T15, DB, SB
attendu  phase = finished ; finishReason = victory ; J1.points = 0 ; le 2e T20 est une marque perdue ;
         la partie finit sur la 9e fléchette

CRI-10 limite de manches
jeu      cricket { scoring: standard, maxRounds: 1 }   joueurs 2
entrées  T20, S20, MISS | S19, S18, S17 |
attendu  phase = finished ; finishReason = roundLimit ; points = J1 20, J2 0 ; ranks = [1, 2]
         (même journal en cutThroat : points = J1 0, J2 20 ; ranks = [1, 2])
```

---

## 5. Killer (`killer`)

### 5.1 Fiche

- **id** : `killer`
- **Noms** : FR « Killer » — EN "Killer"
- **En une ligne** : FR « Touchez votre zone pour devenir Killer, puis visez celles des autres : le dernier en vie gagne. » — EN "Hit your own zone to become a Killer, then take the others out: last one alive wins."
- **Joueurs** : 2 à 8, selon le niveau (voir 5.2). Dartsee le recommande à partir de 3.

Vocabulaire : un **segment** est ici un **secteur entier** (un numéro de 1 à 20, toutes cases confondues). La **zone** d'un joueur est l'ensemble de ses segments.

### 5.2 Options

| Option | Type | Valeurs | Défaut |
|---|---|---|---|
| `level` | enum | `easy`, `medium`, `hard`, `expert` | `easy` |
| `lives` | Int | 1–9 | 3 *(Dartsee)* |
| `armingHits` | Int | 1–5 | 3 *(Dartsee)* |
| `selfHitPenalty` | Bool | — | `false` |
| `maxRounds` | Int? | 1–99 ou `nil` | 15 *(Dartsee)* |

**Les quatre niveaux**

| `level` | Nom FR | Segments par joueur | Zone | Joueurs | Provenance |
|---|---|---|---|---|---|
| `easy` | Facile | 3 | 3 numéros adjacents, fixes | 2–**6** | Dartsee « Beginner / Killer Lite » : le numéro et ses deux voisins |
| `medium` | Intermédiaire | 2 | 2 numéros adjacents, fixes | 2–8 | *(conception propre, non confirmée Dartsee)* |
| `hard` | Difficile | 1 | 1 numéro, fixe | 2–8 | Dartsee « Pro » |
| `expert` | Expert | 1 | 1 numéro, **retiré au sort à chaque tour du joueur** | 2–8 | *(conception propre, non confirmée Dartsee)* |

**Limite de joueurs.** Les zones ne se partagent jamais : il faut `joueurs × segments ≤ 20`. En `easy`, 7 joueurs demanderaient 21 numéros : le niveau Facile est donc **limité à 6 joueurs**. Il n'y a pas de repli silencieux : créer une partie `easy` à 7 ou 8 joueurs DOIT échouer (configuration invalide), et l'écran de préparation DOIT griser « Facile » à partir de 7 joueurs avec l'explication « 6 joueurs maximum en Facile » et présélectionner « Intermédiaire ».

### 5.3 État initial

**Tirage des zones** : `zones = ringLayout(playerCount, width)` (2.8) avec `width` = 3 (`easy`), 2 (`medium`), 1 (`hard`, `expert`). Propriétés garanties :

- tirage aléatoire, reproductible par le `seed` ; personne ne lance pour obtenir un numéro *(Dartsee)* ;
- les segments d'un même joueur sont **adjacents** sur le plateau (bloc continu, listé dans le sens horaire) ;
- un numéro n'appartient jamais à deux joueurs ; les zones de deux joueurs peuvent se toucher ;
- les numéros non attribués sont libres : les toucher n'a aucun effet.

Par joueur : `zone` (liste de numéros), `lives = lives`, `armingProgress = 0`, `kills = 0`, non éliminé. Un joueur est **Killer** quand `armingProgress == armingHits`.

### 5.4 Effet d'une fléchette

Soit `P` le joueur courant. Le multiplicateur est **ignoré** : simple, double et triple d'un même numéro valent **une seule touche** *(Dartsee)*. Pour un numéro n, on cherche son propriétaire parmi les joueurs **en vie** (il y en a au plus un), puis on applique la ligne correspondante :

| Fléchette | Effet |
|---|---|
| `MISS`, `SB`, `DB` | aucun effet (`noEffect`). Le bull ne joue aucun rôle. |
| `Sn`, `Dn`, `Tn`, n dans la zone d'aucun joueur **en vie** (numéro libre, ou zone d'un joueur éliminé) | aucun effet (`noEffect`) |
| n dans la zone de `P`, `P` pas encore Killer | `armingProgress += 1` (`armingHit`). S'il atteint `armingHits` : `P` devient Killer (`becameKiller`), **avec effet immédiat** pour ses fléchettes suivantes du même tour *(Dartsee)* |
| n dans la zone de `P`, `P` déjà Killer, `selfHitPenalty == false` | aucun effet (`noEffect`) *(conception propre : Dartsee décrit une version « simplifiée » sans pénalité)* |
| n dans la zone de `P`, `P` déjà Killer, `selfHitPenalty == true` | `P.lives −= 1` (`lifeLost`, `by = P`). À 0 : `P` est éliminé (aucun kill n'est compté) et son tour est clos *(règle classique du Killer de pub)* |
| n dans la zone d'un adversaire en vie `X`, `P` pas Killer | aucun effet (`noEffect`) |
| n dans la zone d'un adversaire en vie `X`, `P` Killer | `X.lives −= 1` (`lifeLost`). À 0 : `X` est éliminé, `P.kills += 1` |

Précisions :

- Un Killer peut attaquer **tout** adversaire en vie, armé ou non *(règle standard, non confirmée Dartsee)*.
- Les vies ne remontent jamais ; elles ne descendent pas sous 0.
- La progression d'armement ne redescend jamais ; un Killer le reste jusqu'à la fin.
- **Joueur éliminé** : ses tours sont sautés ; sa zone devient inerte (aucun effet pour personne). En `easy`, `medium`, `hard`, ses numéros ne sont pas redistribués. En `expert`, son numéro redevient tirable.

**Retirage du niveau `expert`**

- **Quand** : au **début de chaque tour du joueur, à partir de son 2e tour**, c'est-à-dire pendant le traitement du `endTurn` qui lui donne la main (étape 4 de 2.4). Au 1er tour de chaque joueur, c'est le numéro du tirage initial qui sert. Un joueur éliminé n'est jamais retiré.
- **Comment** : `candidats` = les numéros de 1 à 20 par ordre croissant, privés (a) des numéros actuels des **autres joueurs en vie** et (b) du numéro que le joueur avait au tour précédent (le segment change donc vraiment). Nouveau numéro = `candidats[rng.nextInt(below: candidats.count)]`, un seul tirage sur le flux `SeededRandom` de la partie, à la suite du tirage initial. Il reste toujours au moins 12 candidats.
- **Ce qui est conservé** : `lives`, `armingProgress`, statut Killer, `kills`. Les touches d'armement comptent quel que soit le numéro qu'avait le joueur au moment de la touche.
- **Conséquence** : le numéro d'un joueur reste le même depuis le début de son tour jusqu'au début de son tour suivant ; chaque adversaire a donc exactement un tour pour l'attaquer sur ce numéro.
- **Déterminisme** : le retirage ne dépend que du `seed` et du journal. Annuler puis refaire un `endTurn` redonne le même numéro ; corriger une fléchette du tour courant ne change pas le numéro du joueur courant.

### 5.5 Déroulement du tour

- 3 fléchettes par tour ; les joueurs éliminés sont sautés.
- Le tour est écourté si la partie se termine, ou si le joueur courant s'élimine lui-même (`selfHitPenalty`) : dans ce cas `phase = turnComplete` (s'il reste au moins deux joueurs en vie).
- Aucun retour en arrière : il n'y a pas de bust.

### 5.6 Élimination, victoire, classement

- **Élimination** : immédiate quand `lives` atteint 0, y compris au milieu du tour de l'attaquant.
- **Victoire** (`lastPlayerStanding`) : dès qu'il ne reste qu'un joueur en vie, la partie se termine sur la fléchette. Avec `selfHitPenalty`, ce vainqueur peut ne pas être le lanceur.
- **Limite de manches** (`roundLimit`) *(conception propre, non confirmée Dartsee)* : les joueurs en vie sont départagés par (1) `lives` décroissant ; (2) `kills` décroissant ; (3) `armingProgress` décroissant ; (4) ex æquo.
- **Classement** : joueurs en vie selon ces critères, puis joueurs éliminés dans l'ordre inverse d'élimination (2.7).
- **À 2 joueurs** : duel, mêmes règles. **De 3 à 8** : mêmes règles ; seule la limite de 6 joueurs en `easy` s'applique.

### 5.7 Tableau de score et surbrillances

Par joueur : `lives` (valeur principale), `zone` (numéros, dans la couleur du joueur), `armingProgress` sur `armingHits` (pastilles), badge Killer, `kills`, état éliminé, rang.

Surbrillances pour le joueur courant `P` :

| Situation | Zone de `P` | Zones des adversaires en vie | Zones des éliminés |
|---|---|---|---|
| `P` pas encore Killer | `target` | `opponent` (visibles, pas attaquables) | aucune |
| `P` Killer, `selfHitPenalty == false` | `own` | `target`, couleur de chaque adversaire | aucune |
| `P` Killer, `selfHitPenalty == true` | `avoid` | `target`, couleur de chaque adversaire | aucune |
| `P` vient de s'éliminer sur sa propre zone (`selfHitPenalty`, phase `turnComplete`) | aucune | `opponent` | aucune |

Dans ce dernier cas, aucun conseil de tour n'est affiché.

Chaque zone est dessinée comme un bloc de secteurs entiers avec ses numéros sur le pourtour.

### 5.8 Événements

| Événement | Quand | Idée de son / animation |
|---|---|---|
| `armingHit(player, progress)` | touche d'armement | une pastille s'allume, la zone se remplit |
| `becameKiller(player)` | dernière touche d'armement | notification « Killer ! », son d'arme |
| `lifeLost(player, by, livesLeft)` | une vie perdue ; `player` est la **victime** et `by` le lanceur (exception à la règle de 2.10, comme `damaged` au Combat, 11.8 ; `by = player` pour une auto-élimination, KIL-4) | impact, vie qui disparaît |
| `playerEliminated(player, by)` | 0 vie | son d'élimination, carte grisée |
| `zoneChanged(player, zone)` | retirage `expert`, pendant `endTurn`, juste avant `turnStarted` | le segment se déplace ; annonce du nouveau numéro |
| `noEffect(player)` | fléchette sans effet | son neutre |
| `gameFinished(lastPlayerStanding \| roundLimit)` | fin de partie | écran de victoire |

### 5.9 Vecteurs de test

```
KIL-1  Difficile, duel : s'armer, tuer le dernier adversaire
jeu      killer { level: hard }           joueurs 2      seed 1
attendu  (début) zones = J1 [11], J2 [6] ; lives = 3 / 3
entrées  S11, D11, T11
attendu  J1.armingProgress = 3 ; J1 est Killer (double et triple = 1 touche) ; phase = turnComplete
         événements de la 3e fléchette : dartRegistered, armingHit(3), becameKiller, turnCompleted
entrées  (suite) | MISS ×3 | S6, T6
attendu  J2.lives = 1 ; phase = throwing
entrées  (suite) D6
attendu  J2.lives = 0 ; J2 éliminé ; J1.kills = 1 ; phase = finished ; finishReason = lastPlayerStanding ; ranks = [1, 2]
         événements : dartRegistered, lifeLost, playerEliminated, gameFinished

KIL-2  Facile à trois : zones de 3 numéros, armement en cours de tour, zone d'un éliminé
jeu      killer { level: easy }           joueurs 3      seed 1
attendu  (début) zones = J1 [8, 11, 14], J2 [6, 10, 15], J3 [20, 1, 18]
entrées  S8, T14, S6
attendu  J1.armingProgress = 2 ; S6 sans effet (J1 pas encore Killer) ; lives = 3 / 3 / 3
entrées  (suite) | S11, DB, S20
attendu  aucun changement (J2 pas Killer ; le bull ne compte pas)
entrées  (suite) | S19, MISS, S20
attendu  J3.armingProgress = 1 (S19 est un numéro libre)
entrées  (suite) | D11, S10, S15
attendu  J1 devient Killer sur D11, puis touche J2 deux fois dans le même tour : lives = 3 / 1 / 3
entrées  (suite) | S6, S6, S6 | MISS ×3 | S6, S14, S1
attendu  J2.armingProgress = 3 puis J2 éliminé par S6 ; S14 sans effet (zone de J1, pas de pénalité) ;
         lives = 3 / 0 / 2 ; J1.kills = 1 ; phase = turnComplete
entrées  (suite) | S10, S18, S18
attendu  currentPlayer = J3 (J2 sauté) ; S10 sans effet (zone d'un éliminé) ; J3.armingProgress = 3
entrées  (suite) | T20, S1
attendu  lives = 3 / 0 / 0 ; phase = finished ; finishReason = lastPlayerStanding ; round = 4
         J1.kills = 2 ; ranks = [1, 3, 2] ; dart(S1) est ensuite refusée

KIL-3  Expert : retirage à chaque tour, déterministe
jeu      killer { level: expert }         joueurs 3      seed 7
attendu  (début) zones = J1 [14], J2 [15], J3 [4]   (20 tirages consommés)
entrées  S14, MISS, MISS | MISS ×3 | MISS ×3 |
attendu  J1.armingProgress = 1 ; pas de retirage au 1er tour de J2 ni de J3
         début du 2e tour de J1 : exclus 15 et 4 (autres) et 14 (ancien) → 17 candidats, index 12 → 16
         zones = J1 [16], J2 [15], J3 [4] ; événements du endTurn : roundStarted(2), zoneChanged(J1, [16]), turnStarted(J1, 2)
entrées  (suite) S14, S16, T16 |
attendu  S14 sans effet (14 n'appartient plus à personne) ; J1.armingProgress = 3, Killer
         retirage de J2 : exclus 16, 4 et 15 → 17 candidats, index 9 → 11 ; zones = [16], [11], [4]
entrées  (suite) MISS ×3 |
attendu  retirage de J3 : exclus 16, 11 et 4 → 17 candidats, index 7 → 9 ; zones = [16], [11], [9]
entrées  (suite) MISS ×3 |
attendu  retirage de J1 : exclus 11, 9 et 16 → 17 candidats, index 10 → 13 ; zones = [13], [11], [9] ; round = 3
entrées  (suite) S11, S11, S11
attendu  J2.lives = 0, éliminé ; J1.kills = 1 ; phase = turnComplete
entrées  (suite) |
attendu  J2 sauté, sans tirage ; retirage de J3 : exclus 13 et 9 → 18 candidats, index 14 → 17
         currentPlayer = J3 ; zones en vie = J1 [13], J3 [17]
entrées  (suite) MISS ×3 |
attendu  retirage de J1 : exclus 17 et 13 → 18 candidats, index 3 → 4 (le 4 et le 11 sont redevenus tirables)
         zones en vie = J1 [4], J3 [17] ; lives = 3 / 0 / 3 ; round = 4 ; currentPlayer = J1 ; 26 tirages au total
puis     undo puis endTurn → même état (J1 [4]) ; rejouer tout le journal → mêmes zones à chaque étape

KIL-4  pénalité sur sa propre zone
jeu      killer { level: hard, lives: 1, armingHits: 1, selfHitPenalty: true }   joueurs 2   seed 2
attendu  (début) zones = J1 [3], J2 [5]
entrées  S3, S3
attendu  J1 devient Killer puis s'élimine ; phase = finished ; finishReason = lastPlayerStanding ; ranks = [2, 1]
         événements de la 2e fléchette : dartRegistered, lifeLost(J1, by: J1, livesLeft: 0), playerEliminated(J1, by: J1), gameFinished

jeu      killer { level: hard, lives: 1, armingHits: 1, selfHitPenalty: true }   joueurs 3   seed 2
attendu  (début) zones = J1 [3], J2 [12], J3 [18]
entrées  S3, S3
attendu  J1 éliminé ; phase = turnComplete (tour clos après 2 fléchettes) ; dart(S12) refusée
entrées  (suite) |
attendu  currentPlayer = J2 ; round = 1

jeu      killer { level: hard, selfHitPenalty: true }   joueurs 2   seed 2
entrées  S3, S3, S3 | MISS ×3 | S3, S5, MISS
attendu  lives = J1 2, J2 2 ; J1.armingProgress = 3

KIL-5  Intermédiaire, limite de manches et classement
jeu      killer { level: medium, maxRounds: 2 }   joueurs 4   seed 42
attendu  (début) zones = J1 [9, 12], J2 [16, 8], J3 [1, 18], J4 [17, 3]
entrées  S9, S12, S9 | S16, S16, MISS | MISS ×3 | S17, S3, S17 |
         S16, S1, S1 | MISS, S8, S9 | S18, MISS, MISS | S9, S16, S16
attendu  phase = turnComplete ; armingProgress = 3 / 3 / 1 / 3 ; lives = 1 / 0 / 1 / 3 ; kills = 0 / 0 / 0 / 1 ; J2 éliminé
entrées  (suite) |
attendu  phase = finished ; finishReason = roundLimit ; ranks = [2, 4, 3, 1]
         (J4 : 3 vies ; J1 et J3 : 1 vie, 0 kill, départagés par l'armement 3 contre 1 ; J2 éliminé)

KIL-6  Intermédiaire, duel
jeu      killer { level: medium }         joueurs 2      seed 1
attendu  (début) zones = J1 [6, 10], J2 [11, 14]
entrées  S6, D10, T6 | S14, S11, MISS | S11, S14, S11
attendu  phase = finished ; lives = 3 / 0 ; armingProgress = 3 / 2 ; ranks = [1, 2]

KIL-7  bornes de joueurs par niveau
killer { level: easy }, 7 ou 8 joueurs            → création refusée (configuration invalide)
killer { level: easy }, 6 joueurs, seed 1         → zones = [14, 9, 12], [5, 20, 1], [6, 10, 15], [16, 8, 11], [17, 3, 19], [18, 4, 13]
                                                    (18 numéros distincts ; 2 et 7 restent libres)
killer { level: medium }, 8 joueurs, seed 1       → zones = [18, 4], [6, 10], [7, 16], [9, 12], [3, 19], [15, 2], [11, 14], [5, 20]
killer { level: hard } ou { level: expert }, 8 joueurs, seed 1 → zones = [11], [16], [4], [5], [17], [14], [6], [7]
killer, 1 joueur                                  → création refusée
```

---

## 6. Tour de l'horloge (`aroundTheClock`)

### 6.1 Fiche

- **id** : `aroundTheClock`
- **Noms** : FR « Tour de l'horloge » — EN "Around the Clock"
- **En une ligne** : FR « Touchez les numéros de 1 à 20 dans l'ordre : le premier arrivé au bout gagne. » — EN "Hit 1 to 20 in order: first to the end wins."
- **Joueurs** : 1 à 8.
- Jeu classique, absent du catalogue Dartsee.

### 6.2 Options

| Option | Type | Valeurs | Défaut |
|---|---|---|---|
| `finishOnBull` | Bool | `false` : on gagne sur le 20. `true` : après le 20 il faut encore un bull | `false` |
| `multiplierJump` | Bool | `false` : toute case de la cible avance de 1. `true` : un double avance de 2, un triple de 3 | `false` |
| `maxRounds` | Int? | 1–99 ou `nil` | `nil` (règle classique : pas de limite) |

### 6.3 État initial

Par joueur : `progress = 0` (nombre de numéros validés), `dartsThrown = 0`.

Cible dérivée (`target`) : `progress + 1` tant que `progress < 20` ; `bull` si `progress == 20` et `finishOnBull` ; aucune ensuite. Objectif (`goal`) : 20, ou 21 avec `finishOnBull`.

### 6.4 Effet d'une fléchette

| Cible du joueur | Fléchette | Effet |
|---|---|---|
| numéro `t` | `St`, `Dt`, `Tt` | `progress = min(20, progress + pas)`, avec `pas` = 1, ou le multiplicateur si `multiplierJump` (`targetHit`). Les numéros sautés sont considérés validés. Le plafond à 20 fait que le bull n'est jamais sauté. |
| numéro `t` | autre numéro, `SB`, `DB`, `MISS` | aucun effet (`noEffect`) |
| bull | `SB` ou `DB` | `progress = 21` (`targetHit`) |
| bull | tout le reste | aucun effet (`noEffect`) |

La cible avance **immédiatement** : un joueur peut valider plusieurs numéros dans le même tour. Quand `progress == goal`, le joueur gagne.

### 6.5 Déroulement du tour

3 fléchettes par tour. Pas de bust. Seule la victoire écourte un tour.

### 6.6 Élimination, victoire, classement

- Pas d'élimination.
- **Victoire** (`victory`) : le premier joueur à atteindre `goal` gagne, la partie s'arrête sur la fléchette.
- **Limite de manches** (si activée) : `roundLimit`.
- **Classement** : (1) `progress` décroissant ; (2) ex æquo.

### 6.7 Tableau de score et surbrillances

Par joueur : cible actuelle (valeur principale), `progress` sur `goal` (barre), `dartsThrown`, rang.

Surbrillance : `target` sur `sector(t)` pour la cible `t` du joueur courant, ou sur `bull`.

### 6.8 Événements

| Événement | Quand | Idée de son / animation |
|---|---|---|
| `targetHit(player, number, advancedBy)` | cible touchée (`number` = 25 pour le bull) ; `advancedBy` = l'avancée réelle de `progress`, donc plafonnée au passage à 20 (`T19` depuis `progress = 18` avance de 2) et égale à 1 pour le bull | son montant, la cible passe au numéro suivant |
| `noEffect(player)` | autre fléchette | son neutre |
| `gameFinished(victory \| roundLimit)` | fin de partie | écran de victoire |

### 6.9 Vecteurs de test

```
ATC-1  toute case de la cible avance de 1
jeu      aroundTheClock                    joueurs 1
entrées  S1, D2, T3
attendu  J1.progress = 3 ; cible = 4 ; phase = turnComplete

ATC-2  dans l'ordre uniquement
jeu      aroundTheClock                    joueurs 1
entrées  S2, S1, S1
attendu  J1.progress = 1 ; cible = 2   (S2 trop tôt, 2e S1 inutile)

ATC-3  sauts avec les multiplicateurs
jeu      aroundTheClock { multiplierJump: true }   joueurs 1
entrées  T1, D4, S6
attendu  J1.progress = 6 ; cible = 7

ATC-4  victoire et classement
jeu      aroundTheClock { multiplierJump: true }   joueurs 2
entrées  T1, T4, T7 | S1, S2, MISS | T10, T13, T16 | S3, MISS, MISS | D19
attendu  phase = finished ; finishReason = victory ; progress = J1 20, J2 3 ; ranks = [1, 2]

ATC-5  finir sur le bull ; le saut ne dépasse pas 20
jeu      aroundTheClock { multiplierJump: true, finishOnBull: true }   joueurs 1
entrées  T1, T4, T7 | T10, T13, T16 | T19, S20
attendu  J1.progress = 20 (18 + 3 plafonné à 20) ; cible = bull ; S20 sans effet ; phase = throwing
entrées  (suite) DB
attendu  J1.progress = 21 ; phase = finished ; finishReason = victory

ATC-6  le bull ne compte pas avant la fin
jeu      aroundTheClock { finishOnBull: true }     joueurs 1
entrées  SB, S1, DB
attendu  J1.progress = 1 ; cible = 2

ATC-7  limite de manches et ex æquo
jeu      aroundTheClock { maxRounds: 1 }   joueurs 3
entrées  S1, S2, S3 | S1, MISS, MISS | S1, S2, S3 |
attendu  phase = finished ; finishReason = roundLimit ; progress = 3 / 1 / 3 ; ranks = [1, 3, 1]
```

---

## 7. Shanghai (`shanghai`)

### 7.1 Fiche

- **id** : `shanghai`
- **Noms** : FR « Shanghai » — EN "Shanghai"
- **En une ligne** : FR « Une manche par numéro : marquez un maximum sur le numéro du moment, ou gagnez d'un coup avec simple + double + triple. » — EN "One number per round: score big on it, or win at once with single + double + treble."
- **Joueurs** : 1 à 8 (Dartsee : 1 à 12).

### 7.2 Options

| Option | Type | Valeurs | Défaut |
|---|---|---|---|
| `rounds` | Int | 1–20 (l'interface propose 7 et 20) | 7 *(Dartsee : numéros 1 à 7)* |
| `variant` | enum | `traditional` (secteur exact), `lite` (les deux secteurs voisins comptent aussi) | `traditional` |

La limite de manches est `rounds` ; il n'y a pas d'option `maxRounds`.

### 7.3 État initial

Par joueur : `points = 0`. Le **numéro de la manche** `r` est égal à `round` (manche 1 → numéro 1, etc.).

### 7.4 Effet d'une fléchette

| Fléchette, pendant la manche `r` | Effet |
|---|---|
| `Sr`, `Dr`, `Tr` | `points += r × multiplicateur` (`targetScored`) |
| `variant == lite` et numéro voisin de `r` (`neighbours(r)`), **quelle que soit la case** | `points += r` (`neighbourHit`). Dartsee affiche « +1 » sur les voisins en manche 1 ; la valeur « simple de la cible » est une *(conception propre, non confirmée Dartsee)* |
| autre numéro, `SB`, `DB`, `MISS` | aucun effet (`noEffect`) |

**Shanghai** *(Dartsee)* : si la volée courante contient un `Sr`, un `Dr` et un `Tr` (dans n'importe quel ordre), le joueur gagne immédiatement. Une touche sur un secteur voisin en `lite` ne remplace jamais le simple : il faut les trois cases du numéro exact.

### 7.5 Déroulement du tour

3 fléchettes par tour. Pas de bust. Seul un Shanghai écourte la partie (il tombe forcément sur la 3e fléchette).

### 7.6 Élimination, victoire, classement

- Pas d'élimination.
- **Victoire immédiate** (`victory`) : Shanghai, quel que soit le score.
- **Fin normale** (`roundLimit`) : après la manche `rounds`, le plus grand total gagne.
- **Classement** : (1) l'auteur d'un Shanghai d'abord ; (2) `points` décroissant ; (3) ex æquo.

### 7.7 Tableau de score et surbrillances

Par joueur : `points`, points de la volée en cours, rang. En-tête : numéro de la manche et « r / rounds ».

Surbrillances : `target` sur `single(r)`, `double(r)` et `treble(r)` (trois zones qui couvrent ensemble le secteur `r`), avec les étiquettes `+r`, `+2r`, `+3r` ; en `lite`, `secondary` sur `sector(v)` pour chacun des deux voisins `v`, avec l'étiquette `+r`.

### 7.8 Événements

| Événement | Quand | Idée de son / animation |
|---|---|---|
| `targetScored(player, points)` | numéro de la manche touché ; `points` = points gagnés par la fléchette | son de gain, étiquette de points |
| `neighbourHit(player, points)` | voisin touché en `lite` | son de gain léger |
| `shanghai(player)` | simple + double + triple | fanfare spéciale « Shanghai ! » |
| `noEffect(player)` | autre fléchette | son neutre |
| `gameFinished(victory \| roundLimit)` | fin de partie | écran de victoire |

### 7.9 Vecteurs de test

```
SHA-1  Shanghai en manche 1
jeu      shanghai                          joueurs 2
entrées  S1, D1, T1                        (même résultat avec T1, D1, S1)
attendu  phase = finished ; finishReason = victory ; points = 6 / 0 ; ranks = [1, 2]
         événements de la 3e fléchette : dartRegistered, targetScored(3), shanghai, gameFinished(victory)

SHA-2  seul le numéro de la manche compte
jeu      shanghai                          joueurs 2
entrées  T1, T1, S1 | S20, S18, MISS
attendu  points = 7 / 0 ; pas de Shanghai ; phase = turnComplete ; currentPlayer = J2 ; round = 1

SHA-3  Lite : les voisins valent le simple de la cible
jeu      shanghai { variant: lite }        joueurs 2
entrées  S20, T18, D1 | S5, S4, MISS
attendu  points = 4 / 0   (voisins de 1 : 20 et 18 ; 1 + 1 + 2)

SHA-4  Lite en manche 7
jeu      shanghai { variant: lite }        joueurs 1
entrées  MISS | MISS | MISS | MISS | MISS | MISS | T19, S7, T7
attendu  round = 7 ; points = 35   (voisins de 7 : 19 et 16 ; 7 + 7 + 21)

SHA-5  Lite : un voisin ne fait pas un Shanghai
jeu      shanghai { variant: lite }        joueurs 1
entrées  MISS | S17, D2, T2
attendu  round = 2 ; points = 12 ; phase = turnComplete (pas de victoire)

SHA-6  fin normale
jeu      shanghai { rounds: 2 }            joueurs 2
entrées  S1, S1, MISS | T1, MISS, MISS | D2, MISS, S2 | S2, S2, MISS
attendu  points = 8 / 7 ; phase = turnComplete
entrées  (suite) |
attendu  phase = finished ; finishReason = roundLimit ; ranks = [1, 2]

SHA-7  un Shanghai gagne même avec moins de points
jeu      shanghai { rounds: 2 }            joueurs 2
entrées  T1, T1, T1 | MISS ×3 | T2, T2, T2 | S2, T2, D2
attendu  points = 27 / 12 ; phase = finished ; finishReason = victory ; ranks = [2, 1]
```

---

## 8. Meilleur score (`highScore`)

### 8.1 Fiche

- **id** : `highScore`
- **Noms** : FR « Meilleur score » — EN "High Score"
- **En une ligne** : FR « Un nombre de manches fixe, tout compte : le plus gros total gagne. » — EN "A fixed number of rounds, everything counts: highest total wins."
- **Joueurs** : 1 à 8.
- Jeu classique (« count-up »), absent du catalogue Dartsee ; c'est le jeu le plus simple pour tester la détection.

### 8.2 Options

| Option | Type | Valeurs | Défaut |
|---|---|---|---|
| `rounds` | Int | 1–20 | 8 |

### 8.3 État initial

Par joueur : `points = 0`, `dartsThrown = 0`.

### 8.4 Effet d'une fléchette

| Fléchette | Effet |
|---|---|
| `Sn`, `Dn`, `Tn` | `points += n`, `2n`, `3n` |
| `SB` | `points += 25` |
| `DB` | `points += 50` |
| `MISS` | aucun effet (`noEffect`) |

### 8.5 Déroulement du tour

3 fléchettes par tour. Rien n'écourte un tour.

### 8.6 Élimination, victoire, classement

- Pas d'élimination, pas de victoire sur une fléchette.
- **Fin** (`roundLimit`) : à la confirmation du dernier tour de la manche `rounds`.
- **Classement** : (1) `points` décroissant ; (2) ex æquo.

### 8.7 Tableau de score et surbrillances

Par joueur : `points`, total de la dernière volée, moyenne par volée, rang. Aucune surbrillance.

### 8.8 Événements

`turnScored`, `highTurn`, `oneEighty` à chaque clôture de tour (2.10) : annonce vocale du total. `gameFinished(roundLimit)`.

### 8.9 Vecteurs de test

```
HIS-1  addition simple et 180
jeu      highScore { rounds: 2 }           joueurs 2
entrées  T20, T20, T20 | S5, S1, MISS | DB, SB, S20 | T19, D16, S7
attendu  points = 275 / 102 ; phase = turnComplete ; round = 2
         la 3e fléchette de la partie émet turnScored(180), oneEighty, turnCompleted
entrées  (suite) |
attendu  phase = finished ; finishReason = roundLimit ; ranks = [1, 2]

HIS-2  ex æquo
jeu      highScore { rounds: 1 }           joueurs 3
entrées  S20, S20, S20 | T20, MISS, MISS | S19, S1, MISS |
attendu  points = 60 / 60 / 20 ; ranks = [1, 1, 3]

HIS-3  volée écourtée
jeu      highScore { rounds: 1 }           joueurs 1
entrées  S20 |
attendu  phase = finished ; points = 20 ; J1.dartsThrown = 1

HIS-4  highTurn
jeu      highScore                         joueurs 1
entrées  T20, T20, S20
attendu  points = 140 ; événements de clôture : turnScored(140), highTurn(140), turnCompleted
```

---

## 9. La Moitié (`halveIt`)

### 9.1 Fiche

- **id** : `halveIt`
- **Noms** : FR « La Moitié » — EN "Halve-It"
- **En une ligne** : FR « Une cible imposée par manche : ratez-la avec vos trois fléchettes et votre score est divisé par deux. » — EN "One set target per round: miss it with all three darts and your score is halved."
- **Joueurs** : 1 à 8.
- Jeu classique, absent du catalogue Dartsee.

### 9.2 Options

| Option | Type | Valeurs | Défaut |
|---|---|---|---|
| `targets` | liste de 1 à 12 cibles | voir ci-dessous | `[20, 16, D7, 14, T10, BULL]` |
| `startingScore` | Int | 0 ou 40 | 0 |

Types de cible :

| Cible (notation) | Fléchettes qui comptent | Points gagnés |
|---|---|---|
| `number(n)` (écrit `20`) | `Sn`, `Dn`, `Tn` | n × multiplicateur |
| `double(n)` (écrit `D7`) | `Dn` uniquement | 2n |
| `treble(n)` (écrit `T10`) | `Tn` uniquement | 3n |
| `anyDouble` | `D1`–`D20`, `DB` | points de la fléchette |
| `anyTreble` | `T1`–`T20` | points de la fléchette |
| `bull` (écrit `BULL`) | `SB`, `DB` | 25, 50 |

Le nombre de manches est `targets.count`. L'interface v1 propose la liste par défaut et la liste longue `[15, 16, anyDouble, 17, 18, anyTreble, 19, 20, BULL]`.

### 9.3 État initial

Par joueur : `points = startingScore`. La cible de la manche `r` est `targets[r − 1]`.

### 9.4 Effet d'une fléchette

- La fléchette correspond à la cible de la manche (tableau 9.2) : `points += gain` (`targetScored`), et le tour est marqué « réussi ».
- Sinon (autre case, `MISS`) : aucun effet (`noEffect`).

### 9.5 Déroulement du tour

- 3 fléchettes par tour ; rien n'écourte un tour.
- **À la clôture du tour** (3e fléchette, ou confirmation anticipée, même avec zéro fléchette) : si aucune fléchette du tour n'a touché la cible, `points = (points + 1) / 2` en division entière, soit la moitié **arrondie au supérieur** (`halved`). Exemples : 80 → 40, 5 → 3, 1 → 1, 0 → 0.

### 9.6 Élimination, victoire, classement

- Pas d'élimination, pas de victoire sur une fléchette.
- **Fin** (`roundLimit`) : à la confirmation du dernier tour de la dernière cible.
- **Classement** : (1) `points` décroissant ; (2) ex æquo.

### 9.7 Tableau de score et surbrillances

Par joueur : `points`, indicateur « cible touchée » pour le tour en cours, rang. En-tête : cible de la manche et liste des cibles à venir, absente à la dernière manche (`ARCHITECTURE.md` §5.6 : `objective` et `turnHint`).

Surbrillances (`target`) : `number(n)` → `sector(n)` ; `double(n)` → `double(n)` ; `treble(n)` → `treble(n)` ; `anyDouble` → les 20 doubles et `innerBull` ; `anyTreble` → les 20 triples ; `bull` → `bull`.

### 9.8 Événements

| Événement | Quand | Idée de son / animation |
|---|---|---|
| `targetScored(player, points)` | cible touchée ; `points` = points gagnés par la fléchette | son de gain |
| `halved(player, points)` | division à la clôture ; `points` = nouveau total | son descendant, score coupé en deux |
| `noEffect(player)` | autre fléchette | son neutre |
| `gameFinished(roundLimit)` | fin de partie | écran de victoire |

`halved` est émis avant `turnCompleted`.

### 9.9 Vecteurs de test

```
HAL-1  partie complète avec la liste par défaut
jeu      halveIt                           joueurs 1
entrées  S20, MISS, T20                    → points = 80
         événements de la 1re fléchette : dartRegistered, targetScored(20)
         | MISS ×3                         → points = 40 (halved)
         | S7, T7, MISS                    → points = 20 (halved : seul D7 compte)
         | D14, S20, MISS                  → points = 48
         | S10, D10, MISS                  → points = 24 (halved : seul T10 compte)
         | SB, DB, MISS                    → points = 99
         |
attendu  phase = finished ; finishReason = roundLimit ; points = 99 ; ranks = [1]

HAL-2  arrondi au supérieur
jeu      halveIt                           joueurs 1
entrées  S20, MISS, MISS | MISS ×3 | MISS ×3 | MISS ×3
attendu  points successifs = 20, 10, 5, 3 ; round = 4 ; phase = turnComplete

HAL-3  la division attend la clôture du tour
jeu      halveIt                           joueurs 1
entrées  T20, S5, S5 | MISS, S16, S1 | MISS, MISS
attendu  points = 76 ; phase = throwing (2 fléchettes, pas encore de division)
entrées  (suite) |
attendu  points = 38 ; round = 4 ; événements du endTurn : halved(38), turnCompleted, roundStarted(4), turnStarted(J1, 4)

HAL-4  score de départ à 40
jeu      halveIt { startingScore: 40 }     joueurs 2
entrées  MISS ×3 | S20, MISS, MISS
attendu  points = 20 / 60

HAL-5  cibles « tout double » et « tout triple »
jeu      halveIt { targets: [anyDouble, anyTreble] }   joueurs 1
entrées  DB, D3, S20 | T1, DB, MISS
attendu  points = 59   (50 + 6, puis 3 ; DB n'est pas un triple)
```

---

## 10. Alunissage (`moonLanding`)

### 10.1 Fiche

- **id** : `moonLanding`
- **Noms** : FR « Alunissage » — EN "Moon Landing"
- **En une ligne** : FR « Partez à 200 de la Lune : chaque point vous rapproche, le premier posé gagne. » — EN "Start 200 away from the Moon: every point brings you closer, first to land wins."
- **Joueurs** : 1 à 8 (Dartsee : 1 à 6). Jeu d'échauffement pour débutants.

### 10.2 Options

| Option | Type | Valeurs | Défaut |
|---|---|---|---|
| `distance` | Int | 100–999 | 200 *(Dartsee)* |
| `exactLanding` | Bool | `false` = « Débutant » : atteindre ou dépasser la distance suffit. `true` = « Pro » : il faut tomber exactement sur 0 | `false` |
| `maxRounds` | Int? | 1–99 ou `nil` | 15 *(Dartsee)* |

### 10.3 État initial

Par joueur : `remaining = distance`, `dartsThrown = 0`, `busts = 0`.

### 10.4 Effet d'une fléchette

Soit `R` le `remaining` du joueur courant et `v` les points de la fléchette (`MISS` = 0, `SB` = 25, `DB` = 50, doubles et triples à leur valeur normale *(Dartsee)*).

| Cas | Effet |
|---|---|
| `MISS` | aucun effet (`noEffect`) |
| `exactLanding == false` | `remaining = max(0, R − v)` ; à 0 : **victoire** (`landed`) |
| `exactLanding == true`, `R − v < 0` | **bust** (`belowZero`) : le vaisseau rebondit |
| `exactLanding == true`, `R − v == 0` | **victoire** (`landed`) |
| `exactLanding == true`, `R − v > 0` | `remaining = R − v` |

### 10.5 Déroulement du tour

- 3 fléchettes par tour.
- **Bust** (mode Pro) : tour clos immédiatement, `remaining` revient à sa valeur du début du tour, `busts += 1`. Le manuel Dartsee dit à la fois « bust, aucun lancer du tour ne compte » et « forfait automatique » ; on retient le bust *(règle standard, non confirmée Dartsee)*.
- **Victoire** : la partie se termine sur la fléchette.

### 10.6 Élimination, victoire, classement

- Pas d'élimination.
- **Victoire** (`victory`) : premier joueur à 0.
- **Limite de manches** : `roundLimit`.
- **Classement** : (1) `remaining` croissant ; (2) ex æquo.

### 10.7 Tableau de score et surbrillances

Par joueur : `remaining` (distance restante, valeur principale), total de la dernière volée ou « BUST », rang. L'habillage Dartsee (vaisseaux classés par distance) est un plus d'interface.

Surbrillances : en mode Pro, `target` sur les cases dont les points valent exactement `remaining` ; sinon aucune.

### 10.8 Événements

| Événement | Quand | Idée de son / animation |
|---|---|---|
| `bust(player, reason)` | dépassement en mode Pro (`belowZero`) | le vaisseau rebondit |
| `landed(player)` | arrivée à 0 | alunissage, fanfare |
| `turnScored`, `highTurn`, `oneEighty` | clôture d'un tour sans bust (2.10) | commentaire de volée |
| `gameFinished(victory \| roundLimit)` | fin de partie | écran de victoire |

### 10.9 Vecteurs de test

```
MOO-1  Débutant : dépasser suffit
jeu      moonLanding                       joueurs 2
entrées  T20, T20, T20 | S20, S20, S20 | T20
attendu  phase = finished ; finishReason = victory ; remaining = 0 / 140 ; ranks = [1, 2]

MOO-2  Pro : dépasser = bust, puis arrivée exacte
jeu      moonLanding { exactLanding: true }   joueurs 1
entrées  T20, T20, T20 | T20
attendu  bust(belowZero) ; J1.remaining = 20 ; J1.busts = 1 ; phase = turnComplete ; dart(S20) refusée
entrées  (suite) | S20
attendu  phase = finished ; finishReason = victory ; J1.remaining = 0

MOO-3  Pro : le bust annule toute la volée
jeu      moonLanding { exactLanding: true }   joueurs 1
entrées  T20, T20, T20 | S10, T20
attendu  J1.remaining = 20 (le S10 est annulé) ; phase = turnComplete ; volée = [S10, T20]

MOO-4  limite de manches et ex æquo
jeu      moonLanding { maxRounds: 1 }      joueurs 2
entrées  T20, MISS, MISS | S20, S20, S20 |
attendu  phase = finished ; finishReason = roundLimit ; remaining = 140 / 140 ; ranks = [1, 1]
```

---

## 11. Combat (`fight`)

### 11.1 Fiche

- **id** : `fight`
- **Noms** : FR « Combat » — EN "Fight"
- **En une ligne** : FR « Neuf vies chacun : frappez les points faibles des autres, soignez-vous sur votre numéro. Le dernier debout gagne. » — EN "Nine lives each: hit the others' weak spots, heal on your own number. Last one standing wins."
- **Joueurs** : 2 à 6 (Dartsee : 2 à 4 ; 3 numéros par joueur limitent à 6).

### 11.2 Options

| Option | Type | Valeurs | Défaut |
|---|---|---|---|
| `lives` | Int | 1–20 | 9 *(Dartsee)* |
| `maxRounds` | Int? | 1–99 ou `nil` | 15 *(manuel Dartsee ; le site indique 25)* |

### 11.3 État initial

Chaque joueur reçoit **trois numéros distincts** : un **numéro de soin** (`healNumber`) et deux **points faibles** (`weakNumbers`). Aucun numéro n'est partagé entre joueurs ; les numéros d'un joueur ne sont pas forcément adjacents. Ce modèle vient d'une capture d'écran Dartsee et d'un exploitant ; le manuel parle seulement de « ton numéro » et « le numéro des autres » *(non confirmé par le manuel Dartsee)*.

Tirage : `s = rng.shuffled([1, 2, …, 20])` (19 tirages) ; pour le joueur d'index `i` : `healNumber = s[3i]`, `weakNumbers = [s[3i + 1], s[3i + 2]]`.

Par joueur : `lives = lives` (c'est aussi son maximum), `kills = 0`, non éliminé. Il n'y a pas de phase d'armement : tout le monde peut attaquer dès la première fléchette.

### 11.4 Effet d'une fléchette

Soit `P` le joueur courant et `m` le multiplicateur : simple = 1, double = 2, triple = 3 *(Dartsee)*.

| Fléchette | Effet |
|---|---|
| `MISS`, `SB`, `DB` | aucun effet (`noEffect`) |
| numéro = `healNumber` de `P` | `P.lives = min(maximum, P.lives + m)` (`healed` avec le gain réel ; `healWasted` si `P` est déjà au maximum). Le plafond est une *(conception propre, non confirmée Dartsee)* |
| numéro dans les `weakNumbers` d'un adversaire **en vie** `X` | `X.lives = max(0, X.lives − m)` (`damaged` avec la perte réelle). À 0 : `X` est éliminé, `P.kills += 1` |
| numéro dans les `weakNumbers` de `P` | aucun effet : on ne se blesse pas soi-même *(conception propre)* |
| `healNumber` d'un autre joueur, numéro d'un joueur éliminé, numéro non attribué | aucun effet (`noEffect`) |

### 11.5 Déroulement du tour

3 fléchettes par tour ; les joueurs éliminés sont sautés. Pas de bust. Seule la fin de partie écourte un tour.

### 11.6 Élimination, victoire, classement

- **Élimination** : immédiate à 0 vie.
- **Victoire** (`lastPlayerStanding`) : dernier joueur en vie.
- **Limite de manches** (`roundLimit`) : joueurs en vie départagés par (1) `lives` décroissant ; (2) `kills` décroissant ; (3) ex æquo.
- **Classement** : joueurs en vie selon ces critères, puis éliminés dans l'ordre inverse d'élimination.

### 11.7 Tableau de score et surbrillances

Par joueur : `lives` sur le maximum (barre de vie, valeur principale), `healNumber`, `weakNumbers`, `kills`, état éliminé, rang.

Surbrillances pour le joueur courant `P` :

- `sector(healNumber de P)` : `secondary` si `P` n'est pas au maximum, `own` sinon, propriétaire `P` ;
- points faibles de chaque adversaire en vie : `target`, propriétaire l'adversaire ;
- les couleurs sont celles des joueurs propriétaires (2.9, `ARCHITECTURE.md` §5.6), pas un vert et un rouge fixes ;
- les points faibles de `P` ne sont pas surlignés pendant son tour (ils restent lisibles sur sa carte).

### 11.8 Événements

| Événement | Quand | Idée de son / animation |
|---|---|---|
| `damaged(player, by, amount, livesLeft)` | point faible touché ; `player` est la **victime** et `by` le lanceur (exception à la règle de 2.10, comme dans FIG-2) | coup porté, barre de vie qui descend |
| `healed(player, amount, lives)` | soin effectif | son de soin, barre qui remonte |
| `healWasted(player)` | soin alors que la vie est au maximum | son neutre |
| `playerEliminated(player, by)` | 0 vie | K.-O. |
| `noEffect(player)` | fléchette sans effet | son neutre |
| `gameFinished(lastPlayerStanding \| roundLimit)` | fin de partie | écran de victoire |

### 11.9 Vecteurs de test

```
FIG-1  dégâts, soin, soin plafonné
jeu      fight                             joueurs 2      seed 1
attendu  (début) J1 : healNumber 2, weakNumbers [15, 11] ; J2 : healNumber 4, weakNumbers [20, 5] ; lives = 9 / 9
entrées  T20, D5, S2
attendu  lives = 9 / 4 ; S2 = healWasted (J1 déjà au maximum)
entrées  (suite) | S4, T15, S11
attendu  lives = 5 / 5   (J2 +1 ; J1 −3 puis −1)
entrées  (suite) | T2, S15, S4
attendu  lives = 8 / 5   (soin +3 ; S15 est un point faible de J1 : sans effet ; S4 est le soin de J2 : sans effet)

FIG-2  K.-O. et dégâts plafonnés
jeu      fight                             joueurs 2      seed 1
entrées  T20, T20, T5
attendu  lives = 9 / 0 ; J2 éliminé ; phase = finished ; finishReason = lastPlayerStanding ; ranks = [1, 2]
jeu      fight { lives: 2 }                joueurs 2      seed 1
entrées  T20
attendu  damaged(J2, by: J1, amount: 2, livesLeft: 0) ; phase = finished

FIG-3  trois joueurs, limite de manches
jeu      fight { maxRounds: 1 }            joueurs 3      seed 1
attendu  (début) J3 : healNumber 7, weakNumbers [17, 16]
entrées  T20, S5, T17 | T2, D4, S17 | S16, MISS, S15
attendu  lives = 8 / 7 / 5 ; phase = turnComplete
         (J1 : J2 −3 −1, J3 −3 ; J2 : T2 sans effet, soin +2, J3 −1 ; J3 : S16 sans effet, J1 −1)
entrées  (suite) |
attendu  phase = finished ; finishReason = roundLimit ; ranks = [1, 2, 3]

FIG-4  joueur éliminé : tours sautés, numéros inertes
jeu      fight                             joueurs 3      seed 1
entrées  T20, T5, T20 |
attendu  lives = 9 / 0 / 9 ; J2 éliminé ; currentPlayer = J3 (J2 sauté) ; round = 1
entrées  (suite) S20, S4, S15
attendu  lives = 8 / 0 / 9   (S20 et S4, numéros de J2 éliminé : sans effet ; S15 : J1 −1)
```

---

## 12. Conquérant (`conqueror`)

### 12.1 Fiche

- **id** : `conqueror`
- **Noms** : FR « Conquérant » — EN "Conqueror"
- **En une ligne** : FR « Étendez votre territoire de secteur en secteur, fortifiez-le et prenez la maison des autres. » — EN "Grow your territory sector by sector, fortify it and take the others' home."
- **Joueurs** : 2 à 8.

Dartsee ne publie que les grandes lignes (conquête par voisinage, 3 vies par secteur, bull = « King of the Hill », prise de la maison). Tout ce qui précise ces lignes ci-dessous est une *(conception propre, non confirmée Dartsee)*.

### 12.2 Options

| Option | Type | Valeurs | Défaut |
|---|---|---|---|
| `multipliersCount` | Bool | `false` : toute case vaut 1 touche. `true` : double = 2 touches, triple = 3 *(option Dartsee)* | `false` |
| `maxRounds` | Int? | 1–99 ou `nil` | 15 *(Dartsee)* |

### 12.3 État initial

- Chaque secteur (1–20) a un propriétaire (un joueur, ou personne) et des vies de 0 à 3.
- Chaque joueur reçoit une **maison** (`homeSector`) : `blocs = ringLayout(playerCount, width: 2)` (2.8), la maison du joueur est le **premier** numéro de son bloc. Deux maisons ne sont donc jamais adjacentes et chaque maison a ses deux voisins libres au départ.
- La maison appartient au joueur avec **3 vies**. Tous les autres secteurs sont neutres (0 vie).
- `king` (Roi de la colline) : personne.

### 12.4 Effet d'une fléchette

Soit `P` le joueur courant, `s` le secteur touché et `m` la force : le multiplicateur si `multipliersCount`, sinon 1. « `s` est **adjacent** à `P` » signifie qu'au moins un des deux voisins de `s` appartient à `P` au moment de la fléchette.

| Fléchette | Effet |
|---|---|
| `MISS` | aucun effet (`noEffect`) |
| `SB` ou `DB` | `P` devient Roi (`kingOfTheHill`) et le reste jusqu'à ce qu'un autre joueur touche le bull. Déjà Roi : `noEffect` |
| `s` appartient à `P` | `vies(s) = min(3, vies(s) + m)` (`sectorStrengthened` ; `noEffect` si déjà à 3) |
| `s` neutre et adjacent à `P` | `P` le revendique : propriétaire `P`, `vies(s) = min(3, m)` (`sectorClaimed`) |
| `s` neutre et non adjacent à `P` | aucun effet, **même pour le Roi** (`noEffect`) |
| `s` appartient à `Q ≠ P`, et (`s` adjacent à `P` **ou** `P` est Roi) | attaque : `vies(s) −= m`. S'il reste des vies : `sectorDamaged`. Sinon **conquête** (`sectorConquered`) : propriétaire `P`, `vies(s) = 1`, l'excédent de force est perdu |
| `s` appartient à `Q ≠ P`, non adjacent, `P` pas Roi | aucun effet (`noEffect`) |

**Prise d'une maison** : si le secteur conquis était la maison de `Q`, alors `Q` est éliminé ; tous ses autres secteurs passent à `P` **avec leurs vies actuelles** ; l'ancienne maison devient un secteur ordinaire de `P` ; si `Q` était Roi, le titre devient vacant.

### 12.5 Déroulement du tour

3 fléchettes par tour ; les joueurs éliminés sont sautés. Pas de bust. Seule la fin de partie écourte un tour.

### 12.6 Élimination, victoire, classement

- **Élimination** : perte de sa maison.
- **Victoire** (`lastPlayerStanding`) : dernier joueur non éliminé.
- **Limite de manches** (`roundLimit`) : joueurs en jeu départagés par (1) total des vies de leurs secteurs (`totalLives`) décroissant *(Dartsee : « le plus de vies »)* ; (2) nombre de secteurs (`sectorCount`) décroissant ; (3) ex æquo.
- **Classement** : joueurs en jeu selon ces critères, puis éliminés dans l'ordre inverse d'élimination.

### 12.7 Tableau de score et surbrillances

Par joueur : `totalLives` (valeur principale), `sectorCount`, `homeSector`, badge Roi, état éliminé, rang. Plateau : chaque secteur possédé est rempli de la couleur de son propriétaire avec 1 à 3 boucliers ; la maison porte une couronne ; le bull prend la couleur du Roi.

Surbrillances pour le joueur courant `P` :

- secteur neutre adjacent à `P` → `target` ;
- secteur adverse attaquable (adjacent à `P`, ou tous si `P` est Roi) → `target`, couleur du propriétaire ;
- secteur de `P` avec moins de 3 vies → `secondary` ; à 3 vies → `own` ;
- secteur adverse non attaquable → `opponent` ;
- `bull` → `secondary` si `P` n'est pas Roi, `own` si `P` est le Roi. Tant qu'il y a un Roi, le bull a ce Roi pour propriétaire (sa couleur) et porte la couronne, pour tous les joueurs.

### 12.8 Événements

| Événement | Quand | Idée de son / animation |
|---|---|---|
| `sectorClaimed(player, sector)` | secteur neutre revendiqué | drapeau planté |
| `sectorStrengthened(player, sector, lives)` | renfort | bouclier ajouté |
| `sectorDamaged(player, sector, livesLeft)` | attaque sans conquête | bouclier brisé |
| `sectorConquered(player, sector, from)` | conquête | changement de couleur |
| `kingOfTheHill(player)` | bull | couronne, fanfare courte |
| `playerEliminated(player, by)` | maison prise | tout le territoire change de couleur |
| `noEffect(player)` | fléchette sans effet | son neutre |
| `gameFinished(lastPlayerStanding \| roundLimit)` | fin de partie | écran de victoire |

### 12.9 Vecteurs de test

Notation : `J1 = { 6: 3, 10: 1 }` signifie que J1 possède le secteur 6 avec 3 vies et le 10 avec 1 vie.

```
CON-1  revendiquer, renforcer, Roi, conquête et reconquête
jeu      conqueror                         joueurs 2      seed 1
attendu  (début) maisons : J1 = 6, J2 = 11 ; J1 = { 6: 3 } ; J2 = { 11: 3 } ; king = personne
         (voisins de 6 : 13 et 10 ; voisins de 11 : 8 et 14)
entrées  S10, S15, S20
attendu  J1 = { 6: 3, 10: 1, 15: 1 } ; S20 sans effet (non adjacent)
entrées  (suite) | S8, S8, T14
attendu  J2 = { 11: 3, 8: 2, 14: 1 }   (sans multipliersCount, T14 vaut 1)
entrées  (suite) | SB, S14, S14
attendu  king = J1 ; S14 conquis par J1 (1 vie) puis renforcé : J1 = { 6: 3, 10: 1, 15: 1, 14: 2 } ; J2 = { 11: 3, 8: 2 }
entrées  (suite) | S14, S14, DB
attendu  14 : 2 → 1 puis conquis par J2 (1 vie) ; king = J2
         J1 = { 6: 3, 10: 1, 15: 1 } ; J2 = { 11: 3, 8: 2, 14: 1 } ; totalLives = 5 / 6 ; phase = turnComplete ; round = 2

CON-2  multiplicateurs, Roi et prise de maison
jeu      conqueror { multipliersCount: true }   joueurs 2   seed 1
entrées  T10, D13, T6
attendu  J1 = { 6: 3, 10: 3, 13: 2 }   (T6 sur la maison déjà à 3 : sans effet)
entrées  (suite) | DB, T6
attendu  king = J2 ; maison de J1 conquise (3 − 3 = 0) ; J1 éliminé
         J2 = { 11: 3, 6: 1, 10: 3, 13: 2 } ; phase = finished ; finishReason = lastPlayerStanding ; ranks = [2, 1]
         événements de la 2e fléchette : dartRegistered, sectorConquered(J2, 6, from: J1), playerEliminated(J1, by: J2), gameFinished

CON-3  trois joueurs : héritage du territoire, ordre d'élimination
jeu      conqueror                         joueurs 3      seed 1
attendu  (début) maisons : J1 = 6, J2 = 16, J3 = 20
entrées  SB, S16, S16 | S8, S7, MISS | MISS ×3 | S16
attendu  maison de J2 conquise ; J2 éliminé ; J1 hérite de 7 et 8 :
         J1 = { 6: 3, 16: 1, 7: 1, 8: 1 } ; J3 = { 20: 3 } ; king = J1 ; phase = throwing (1 fléchette)
entrées  (suite) S20, S20 | MISS ×3 | S20
attendu  currentPlayer passe de J1 à J3 (J2 sauté) puis à J1 ; maison de J3 conquise
         phase = finished ; finishReason = lastPlayerStanding ; round = 3 ; ranks = [1, 3, 2]

CON-4  limite de manches : total des vies
jeu      conqueror { maxRounds: 1 }        joueurs 2      seed 1
entrées  S10, S15, S6 | S8, S8, S14 |
attendu  J1 = { 6: 3, 10: 1, 15: 1 } (5 vies) ; J2 = { 11: 3, 8: 2, 14: 1 } (6 vies)
         phase = finished ; finishReason = roundLimit ; ranks = [2, 1]

CON-5  le Roi attaque partout mais ne revendique que par voisinage
jeu      conqueror                         joueurs 2      seed 1
entrées  SB, S9, S13 | MISS ×3 | S11, S12, MISS
attendu  king = J1 ; S9 sans effet (neutre, non adjacent) ; S13 revendiqué ;
         S11 : maison de J2 3 → 2 (attaque du Roi) ; S12 sans effet
         J1 = { 6: 3, 13: 1 } ; J2 = { 11: 2 }

CON-6  pas d'attaque sans voisinage ni couronne
jeu      conqueror                         joueurs 2      seed 1
entrées  S10, S10, S10 | S10, S6, S14
attendu  J1 = { 6: 3, 10: 3 } ; S10 et S6 de J2 sans effet ; J2 = { 11: 3, 14: 1 }

CON-7  maisons jamais adjacentes
conqueror, 4 joueurs, seed 42 → maisons = 9, 16, 1, 17
conqueror, 8 joueurs, seed 1  → maisons = 18, 6, 7, 9, 3, 15, 11, 5
```

---

## 13. Tireuse (`beerTap`)

### 13.1 Fiche

- **id** : `beerTap`
- **Noms** : FR « Tireuse » — EN "Beer Tap"
- **En une ligne** : FR « Chaque point verse un centilitre de bière : remplissez plus de verres que les autres. Une volée de 100 points, et un verre vous est offert. » — EN "Every point pours a centilitre of beer: fill more glasses than the others. Score 100 in a turn and a glass is on the house."
- **Joueurs** : 1 à 8 (Dartsee : 2 à 10).
- **Provenance** : *(conception propre, inspirée de Dartsee)*. Dartsee dit seulement « plus le score est haut, plus la bière coule ; remplissez le plus de verres possible » et montre un verre avec un pourcentage de remplissage. Toutes les valeurs ci-dessous sont les nôtres.
- **Dépend de la position** : non.

Unité : 1 point = 1 centilitre.

### 13.2 Options

| Option | Type | Valeurs | Défaut |
|---|---|---|---|
| `glassSize` | Int | 25 (« Demi »), 50 (« Pinte »), 100 (« Litre ») : contenance d'un verre, en centilitres | 50 |
| `rounds` | Int | 1–20 | 5 *(capture Dartsee « 1/5 »)* |

La limite de manches est `rounds` ; il n'y a pas d'option `maxRounds`. Toute autre valeur de `glassSize` est refusée à la création.

### 13.3 État initial

Par joueur : `poured = 0` (centilitres versés, verres offerts compris), `bonusGlasses = 0`, `dartsThrown = 0`.

Valeurs dérivées : `glasses = poured / glassSize` en division entière (verres pleins) et `level = poured % glassSize` (contenu du verre entamé, de 0 à `glassSize − 1`).

### 13.4 Effet d'une fléchette

Soit `v` les points de la fléchette (2.2). Dans tous les cas `dartsThrown += 1`.

| Fléchette | Effet |
|---|---|
| `MISS` | aucun effet (`noEffect`) |
| toute autre | `poured += v`. Si `glasses` augmente de `k ≥ 1` : `glassFilled` avec `count = k`. Le trop-plein n'est jamais perdu : il passe dans le verre suivant |

Une seule fléchette peut remplir plusieurs verres (avec `glassSize: 25`, un `T20` en remplit deux ou trois).

### 13.5 Déroulement du tour

- 3 fléchettes par tour. Rien n'écourte un tour.
- **À la clôture du tour** : soit `T` le total des points des fléchettes du tour. Si `T ≥ 100`, **un verre est offert** : `poured += glassSize`, `bonusGlasses += 1` (`bonusGlass`). `level` ne change pas. Le seuil de 100 est celui de `highTurn` (2.10) et ne dépend pas de `glassSize`. Une volée écourtée y a droit aussi, si elle vaut au moins 100 points.

### 13.6 Élimination, victoire, classement

- Pas d'élimination, pas de victoire sur une fléchette.
- **Fin** (`roundLimit`) : à la confirmation du dernier tour de la manche `rounds`.
- **Classement** : (1) `poured` décroissant, ce qui revient à comparer le nombre de verres pleins puis le niveau du verre entamé ; (2) ex æquo.

### 13.7 Tableau de score et surbrillances

Par joueur : `glasses` (valeur principale, unité « verres »), jauge du verre entamé (`level` sur `glassSize`), `poured`, total de la dernière volée, `bonusGlasses`, `dartsThrown`, rang. Aucune surbrillance. L'habillage (verre qui se remplit, mousse) est un plus d'interface.

### 13.8 Événements

| Événement | Quand | Idée de son / animation |
|---|---|---|
| `glassFilled(player, count, glasses)` | une fléchette remplit `count` verres ; `glasses` = nouveau nombre de verres pleins | « Santé ! », le verre plein laisse la place à un verre vide |
| `bonusGlass(player, glasses)` | verre offert, à la clôture d'un tour d'au moins 100 points ; `glasses` = nouveau nombre de verres pleins | « Tournée offerte ! » |
| `turnScored`, `highTurn`, `oneEighty` | clôture de chaque tour (2.10) | annonce vocale du total |
| `noEffect(player)` | `MISS` | son neutre |
| `gameFinished(roundLimit)` | fin de partie | écran de victoire |

Ordre à la clôture : `turnScored`, puis `oneEighty` ou `highTurn`, puis `bonusGlass`, puis `turnCompleted`.

### 13.9 Vecteurs de test

```
BEE-1  verser, remplir un verre, report du trop-plein
jeu      beerTap                           joueurs 2
entrées  S20, S20, S20
attendu  J1.poured = 60 ; J1.glasses = 1 ; J1.level = 10 ; phase = turnComplete
         événements de la 3e fléchette : dartRegistered, glassFilled(count: 1, glasses: 1), turnScored(60), turnCompleted
entrées  (suite) | T20, MISS, S5
attendu  J2.poured = 65 ; J2.glasses = 1 ; J2.level = 15   (le T20 remplit un verre et laisse 10 dans le suivant)
entrées  (suite) | T19, S1, S10
attendu  J1.poured = 128 ; J1.glasses = 2 ; J1.level = 28 ; round = 2

BEE-2  verre offert pour une volée de 100 points ou plus
jeu      beerTap                           joueurs 1
entrées  T20, T20
attendu  poured = 120 ; glasses = 2 ; level = 20 ; bonusGlasses = 0 ; phase = throwing   (rien n'est offert avant la clôture)
entrées  (suite) S20
attendu  poured = 190 (140 versés + 50 offerts) ; glasses = 3 ; level = 40 ; bonusGlasses = 1
         événements de la 3e fléchette : dartRegistered, turnScored(140), highTurn(140), bonusGlass(glasses: 3), turnCompleted
jeu      beerTap                           joueurs 1
entrées  T20, T20, T20
attendu  poured = 230 ; glasses = 4 ; level = 30
         événements de la 3e fléchette : dartRegistered, glassFilled(count: 1, glasses: 3), turnScored(180), oneEighty, bonusGlass(glasses: 4), turnCompleted
jeu      beerTap                           joueurs 1
entrées  T20, T20 |
attendu  poured = 170 ; glasses = 3 ; bonusGlasses = 1 ; round = 2   (volée écourtée de 120 points : le verre est offert à la confirmation)
         événements du endTurn : turnScored(120), highTurn(120), bonusGlass(glasses: 3), turnCompleted, roundStarted(2), turnStarted(J1, 2)
jeu      beerTap                           joueurs 1
entrées  T20, S20, S19
attendu  poured = 99 ; glasses = 1 ; level = 49 ; bonusGlasses = 0   (99 points : pas de verre offert)

BEE-3  taille du verre
jeu      beerTap { glassSize: 25 }         joueurs 1
entrées  S20, T20
attendu  poured = 80 ; glasses = 3 ; level = 5
         événements de la 2e fléchette : dartRegistered, glassFilled(count: 3, glasses: 3)
jeu      beerTap { glassSize: 100 }        joueurs 1
entrées  T20, S20, S19 | S1
attendu  après la 1re volée : poured = 99 ; glasses = 0 ; level = 99
         après S1 : poured = 100 ; glasses = 1 ; level = 0 ; événements : dartRegistered, glassFilled(count: 1, glasses: 1)

BEE-4  fin de partie et classement
jeu      beerTap { rounds: 1 }             joueurs 3
entrées  S20, S20, S10 | DB, MISS, MISS | T20, S20, S19 |
attendu  phase = finished ; finishReason = roundLimit ; poured = 50 / 50 / 99
         glasses = 1 / 1 / 1 ; level = 0 / 0 / 49 ; ranks = [2, 2, 1]
         (un verre plein chacun : le niveau du verre entamé départage ; J1 et J2 ex æquo)

BEE-5  configurations refusées
beerTap { glassSize: 40 }                         → création refusée (valeur hors liste)
beerTap { rounds: 0 } ou { rounds: 21 }           → création refusée
beerTap, 9 joueurs                                → création refusée

BEE-6  une correction retire le verre offert
jeu      beerTap                           joueurs 1
entrées  T20, T20, S20
attendu  poured = 190 (140 versés + 50 offerts) ; bonusGlasses = 1
puis     replaceDart(0, S1)               → volée = [S1, T20, S20] ; poured = 81 ; glasses = 1 ; level = 31 ;
                                            bonusGlasses = 0 ; phase = turnComplete
                                            (la volée ne vaut plus que 81 points : le rejeu ne redonne pas le verre)
```

---

## 14. Football (`football`)

### 14.1 Fiche

- **id** : `football`
- **Noms** : FR « Football » — EN "Football"
- **En une ligne** : FR « Deux camps, un ballon : chaque fléchette pousse le ballon du côté de la cible où elle se plante. Amenez-le dans le but d'en face. » — EN "Two sides, one ball: every dart pushes the ball towards the side of the board it lands on. Get it into the opposite goal."
- **Joueurs** : 2 à 8 (Dartsee : 2 à 10).
- **Provenance** : *(conception propre, inspirée de Dartsee)*. Chez Dartsee, une cible transparente est centrée sur le ballon et l'impact donne l'endroit où il roule, sur un terrain animé ; deux équipes s'affrontent et le plus de buts gagne. La physique et la position exacte ne sont pas reprises : ici le terrain n'a qu'une dimension, et seule compte la **moitié** de cible touchée.
- **Dépend de la position** : non. La moitié se lit sur le numéro du secteur (2.1).

**Le terrain** est une ligne. Le camp A défend le but de gauche, le camp B celui de droite : **le camp A attaque vers la droite, le camp B vers la gauche**. `ball` est la position du ballon, un entier de `−goalDistance` (ligne du but que défend A) à `+goalDistance` (ligne du but que défend B) ; 0 est le centre. Dans toute cette section, « le but de A » ne s'emploie pas : on dit « le but que défend A » pour le filet, et « le camp A marque » pour un but à son crédit.

**Les deux camps.** L'application n'a pas de mode équipe (2.3) ; la répartition est une règle fixe du jeu :

- **camp A** : les joueurs d'index pair, J1, J3, J5, J7 ; **camp B** : les joueurs d'index impair, J2, J4, J6, J8 ;
- l'ordre de jeu reste celui de la liste des joueurs : les camps alternent donc à chaque tour. Avec un nombre impair de joueurs, le camp A a un joueur de plus et joue deux tours de suite à chaque changement de manche ;
- les joueurs d'un camp partagent les buts et le rang.

**Compensation des camps inégaux.** Pour que deux camps d'effectifs différents poussent autant l'un que l'autre sur une manche, le pas d'un camp est proportionnel à l'effectif de l'autre. Avec `sizeA = ⌈n / 2⌉`, `sizeB = ⌊n / 2⌋` et `g = pgcd(sizeA, sizeB)` :

```
step[A] = sizeB / g        step[B] = sizeA / g        goalDistance = fieldLength × step[B]
```

| Joueurs | Camp A | Camp B | `step[A]` | `step[B]` | `goalDistance` |
|---|---|---|---|---|---|
| 2 | J1 | J2 | 1 | 1 | `fieldLength` |
| 3 | J1, J3 | J2 | 1 | 2 | 2 × `fieldLength` |
| 4 | J1, J3 | J2, J4 | 1 | 1 | `fieldLength` |
| 5 | J1, J3, J5 | J2, J4 | 2 | 3 | 3 × `fieldLength` |
| 6 | J1, J3, J5 | J2, J4, J6 | 1 | 1 | `fieldLength` |
| 7 | J1, J3, J5, J7 | J2, J4, J6 | 3 | 4 | 4 × `fieldLength` |
| 8 | J1, J3, J5, J7 | J2, J4, J6, J8 | 1 | 1 | `fieldLength` |

Avec un nombre pair de joueurs rien n'est compensé : chaque pas vaut 1 et chaque ligne de but est à `fieldLength` pas du centre.

### 14.2 Options

| Option | Type | Valeurs | Défaut |
|---|---|---|---|
| `fieldLength` | Int | 3–8 : nombre de pas du centre à une ligne de but, à camps égaux | 4 |
| `goalsToWin` | Int | 1–9 | 3 |
| `maxRounds` | Int? | 1–99 ou `nil` | 10 *(Dartsee : 15 au plus ; capture « 4/7 »)* |

### 14.3 État initial

`ball = 0` ; `sideGoals = [0, 0]` (buts du camp A, buts du camp B). Par joueur : `side` (0 = camp A, 1 = camp B), `goalsScored = 0` (buts que ce joueur a marqués pour son camp). Aucun tirage.

### 14.4 Effet d'une fléchette

Soit `P` le joueur courant, `C` son camp, `s = step[C]` et `m` le multiplicateur (simple 1, double 2, triple 3).

| Fléchette | Effet |
|---|---|
| `MISS` | aucun effet (`noEffect`) |
| numéro 20 ou 3 (ligne médiane) | aucun effet (`noEffect`) |
| numéro de la moitié droite (1, 18, 4, 13, 6, 10, 15, 2, 17) | le ballon va **à droite** : `ball += m × s` (`ballMoved`) |
| numéro de la moitié gauche (19, 7, 16, 8, 11, 14, 9, 12, 5) | le ballon va **à gauche** : `ball −= m × s` (`ballMoved`) |
| `SB` | frappe : le ballon avance de `2 × s` vers le but que `C` attaque (à droite pour A, à gauche pour B) (`ballMoved`) |
| `DB` | **but immédiat** : le camp `C` marque, où que soit le ballon (`goalScored`, sans `ballMoved`) |

- C'est la moitié touchée qui donne le sens, **quel que soit le lanceur** : une fléchette dans la mauvaise moitié pousse le ballon vers son propre but.
- Après un déplacement, `ball` est borné à l'intervalle `[−goalDistance, +goalDistance]` : le ballon s'arrête sur la ligne. `ball == +goalDistance` : **le camp A marque**. `ball == −goalDistance` : **le camp B marque**.
- **But marqué par le camp `K`** : `sideGoals[K] += 1` ; si `K == C`, `P.goalsScored += 1` (un but contre son camp n'est crédité à aucun joueur) ; `ball = 0` (engagement au centre). Si `sideGoals[K] == goalsToWin`, la partie se termine (14.6).

### 14.5 Déroulement du tour

3 fléchettes par tour. Pas de bust. Un but **n'écourte pas** le tour : le joueur continue depuis le centre avec les fléchettes qui lui restent. Seule la victoire écourte un tour.

### 14.6 Élimination, victoire, classement

- Pas d'élimination.
- **Victoire** (`victory`) : le premier camp à `goalsToWin` buts gagne, sur la fléchette. Après un but contre son camp, le camp vainqueur n'est pas celui du lanceur.
- **Limite de manches** : `roundLimit`.
- **Classement**, le même pour tous les joueurs d'un camp : (1) `sideGoals` du camp décroissant ; (2) avantage territorial décroissant, soit `ball` pour le camp A et `−ball` pour le camp B (à égalité de buts, le camp qui tient le ballon dans la moitié adverse est devant) ; (3) ex æquo (match nul : tous les joueurs sont premiers).
- Les joueurs d'un camp ont toujours le même rang, et le rang suivant est sauté (2.7) : à quatre joueurs, `ranks = [1, 3, 1, 3]` quand le camp A gagne.

### 14.7 Tableau de score et surbrillances

Par joueur : buts de son camp (valeur principale), `side` (badge « A » ou « B »), `goalsScored`, jauge d'avancée du ballon vers le but qu'il attaque (`goalDistance + ball` pour le camp A, `goalDistance − ball` pour le camp B, sur `2 × goalDistance`), rang. En-tête : le score, « A 2 – 1 B ».

Champs de partie : `ball`, `sideGoals`, `goalDistance`, `step`.

**Titre des résultats** (`winnerTitle`). Le vainqueur est un camp, pas un joueur : en phase `finished`, le jeu donne le titre à afficher et à annoncer à la place des noms des joueurs classés premiers. FR « Le camp A gagne », « Le camp B gagne », « Match nul » — EN "Side A wins", "Side B wins", "It's a draw". Le camp vainqueur est celui dont les joueurs ont le rang 1 ; le match est nul quand tous l'ont. Aucun autre jeu de ce document ne donne ce titre : leurs vainqueurs sont des joueurs.

Surbrillances pour le joueur courant `P` du camp `C` :

- les neuf secteurs de la moitié qu'il attaque (droite pour A, gauche pour B) → `target` ;
- les neuf secteurs de l'autre moitié → `avoid` ;
- `bull` → `target` ;
- 20 et 3 : aucune.

### 14.8 Événements

| Événement | Quand | Idée de son / animation |
|---|---|---|
| `ballMoved(player, by, ball)` | le ballon se déplace ; `by` = déplacement demandé, signé (positif vers la droite) ; `ball` = position atteinte après bornage | le ballon roule |
| `goalScored(player, side, goals, ownGoal)` | but ; `side` = camp crédité (0 = A, 1 = B), `goals` = son nouveau total, `ownGoal` = vrai si `player` est de l'autre camp | « But ! », filet qui tremble ; « Contre son camp ! » |
| `noEffect(player)` | `MISS`, 20 ou 3 | son neutre |
| `gameFinished(victory \| roundLimit)` | fin de partie | écran de victoire |

Ordre : un déplacement qui amène le ballon sur une ligne de but émet `ballMoved` puis `goalScored`.

### 14.9 Vecteurs de test

`camps` donne le camp de chaque joueur dans l'ordre des joueurs ; `step` s'écrit `step[A] / step[B]` ; `sideGoals = [buts de A, buts de B]`.

```
FOO-1  duel : pousser, être repoussé, marquer, engagement
jeu      football                          joueurs 2
attendu  (début) camps = A, B ; step = 1 / 1 ; goalDistance = 4 ; ball = 0 ; sideGoals = [0, 0]
         surbrillances de J1 : target = secteurs 1, 18, 4, 13, 6, 10, 15, 2, 17 et bull
                               avoid = secteurs 19, 7, 16, 8, 11, 14, 9, 12, 5
entrées  S6, D10, MISS
attendu  ball = 3   (+1 puis +2) ; phase = turnComplete
entrées  (suite) | S11, S20, T14
attendu  ball = -1   (−1 ; S20 sur la ligne médiane : noEffect ; −3) ; ranks = [2, 1]   (ballon dans la moitié que défend A)
         surbrillances de J2 (camp B) : en miroir, target = moitié gauche et bull, avoid = moitié droite
entrées  (suite) | S13, T4
attendu  ball = 3 ; phase = throwing
entrées  (suite) S2
attendu  le camp A marque : sideGoals = [1, 0] ; J1.goalsScored = 1 ; ball = 0 ; phase = turnComplete ; ranks = [1, 2]
         événements : dartRegistered, ballMoved(by: +1, ball: 4), goalScored(J1, side: A, goals: 1, ownGoal: false), turnCompleted

FOO-2  mauvaise moitié et but contre son camp
jeu      football                          joueurs 2
entrées  S11, S9, D14
attendu  J1 (camp A) pousse le ballon vers le but qu'il défend : ball = -2 après deux fléchettes, puis la ligne de ce but : le camp B marque
         sideGoals = [0, 1] ; goalsScored = 0 / 0 ; ball = 0 ; ranks = [2, 1]
         événements de la 3e fléchette : dartRegistered, ballMoved(by: -2, ball: -4), goalScored(J1, side: B, goals: 1, ownGoal: true), turnCompleted

FOO-3  bull, ballon arrêté sur la ligne, victoire au nombre de buts
jeu      football { goalsToWin: 2 }        joueurs 2
entrées  SB, S3, DB
attendu  SB : ball = 2 ; S3 : noEffect ; DB : le camp A marque aussitôt, ball = 0 ; sideGoals = [1, 0]
         événements de la 3e fléchette : dartRegistered, goalScored(J1, side: A, goals: 1, ownGoal: false), turnCompleted
entrées  (suite) | DB, SB, T11
attendu  DB : sideGoals = [1, 1] ; SB : ball = -2 ; T11 : trois pas de plus vers la gauche, le ballon s'arrête sur la ligne (-4) : le camp B marque son 2e but
         phase = finished ; finishReason = victory ; sideGoals = [1, 2] ; goalsScored = 1 / 2 ; ball = 0 ; ranks = [2, 1]
         événements de la dernière fléchette : dartRegistered, ballMoved(by: -3, ball: -4), goalScored(J2, side: B, goals: 2, ownGoal: false), gameFinished(victory)
         dart(S6) est ensuite refusée

FOO-4  camps et compensation selon le nombre de joueurs
football, 2 joueurs → camps = A, B ; step = 1 / 1 ; goalDistance = 4
football, 3 joueurs → camps = A, B, A ; step = 1 / 2 ; goalDistance = 8
football, 4 joueurs → camps = A, B, A, B ; step = 1 / 1 ; goalDistance = 4
football, 5 joueurs → camps = A, B, A, B, A ; step = 2 / 3 ; goalDistance = 12
football, 6 joueurs → camps = A, B, A, B, A, B ; step = 1 / 1 ; goalDistance = 4
football, 7 joueurs → camps = A, B, A, B, A, B, A ; step = 3 / 4 ; goalDistance = 16
football, 8 joueurs → camps = A, B, A, B, A, B, A, B ; step = 1 / 1 ; goalDistance = 4
football { fieldLength: 6 }, 5 joueurs → step = 2 / 3 ; goalDistance = 18
football, 1 joueur ou 9 joueurs → création refusée
football { fieldLength: 2 } ou { goalsToWin: 0 } → création refusée

FOO-5  trois joueurs : le joueur seul pousse deux fois plus fort
jeu      football                          joueurs 3
entrées  S6, S6, S6 | S11, T11, S11
attendu  J1 (A, pas de 1) : ball = 3 ; J2 (B, pas de 2) : −2, −6, −2 → ball = -7 ; ranks = [2, 1, 2]
entrées  (suite) | D6, S6, S1
attendu  currentPlayer = J3 (camp A) ; ball = -3
entrées  (suite) | T6, S6
attendu  currentPlayer = J1 : le camp A joue deux tours de suite ; round = 2 ; ball = 1 ; ranks = [1, 3, 1]

FOO-6  limite de manches : les buts, puis la position du ballon
jeu      football { maxRounds: 1 }         joueurs 4
entrées  T6, S6 | MISS ×3 | DB | S11, S11, MISS |
attendu  phase = finished ; finishReason = roundLimit ; sideGoals = [2, 0] ; goalsScored = 1 / 0 / 1 / 0 ; ball = -2
         ranks = [1, 3, 1, 3]   (les deux joueurs d'un camp partagent le rang)
jeu      football { maxRounds: 1 }         joueurs 2
entrées  S6, MISS, MISS | S11, S11, MISS |
attendu  finishReason = roundLimit ; sideGoals = [0, 0] ; ball = -1 ; ranks = [2, 1]   (égalité de buts : le ballon est dans la moitié que défend A)
jeu      football { maxRounds: 1 }         joueurs 2
entrées  S6, MISS, MISS | S11, MISS, MISS |
attendu  sideGoals = [0, 0] ; ball = 0 ; ranks = [1, 1]   (match nul)

FOO-7  victoire sur un but contre son camp
jeu      football { goalsToWin: 1 }        joueurs 2
entrées  T11, S11
attendu  J1 (camp A) pousse le ballon jusqu'à la ligne du but qu'il défend : le camp B marque et gagne
         phase = finished ; finishReason = victory ; sideGoals = [0, 1] ; goalsScored = 0 / 0 ; ball = 0 ; ranks = [2, 1]
         événements de la 2e fléchette : dartRegistered, ballMoved(by: -1, ball: -4), goalScored(J1, side: B, goals: 1, ownGoal: true), gameFinished(victory)
```

---

## 15. Radar (`radar`)

### 15.1 Fiche

- **id** : `radar`
- **Noms** : FR « Radar » — EN "Radar"
- **En une ligne** : FR « Cinq cibles rondes sont posées sur le plateau : chaque touche rapporte des points, chaque cible détruite un bonus, et une nouvelle prend sa place. » — EN "Five round targets sit on the board: every hit scores, every target destroyed pays a bonus, and a new one takes its place."
- **Joueurs** : 1 à 8 (Dartsee : 1 à 6 ou 1 à 8).
- **Provenance** : *(conception propre, inspirée de Dartsee)*. Dartsee décrit des « blobs » à abîmer puis à détruire, un bonus à la destruction, la victoire au plus grand total et deux options (cibles mobiles, contre-la-montre) ; il ne publie ni taille ni valeur. Le contre-la-montre (« Time Pressure ») **n'est pas repris** : aucun jeu de cette application ne dépend d'une horloge.
- **Dépend de la position : oui.** C'est le seul jeu de ce document dans ce cas. L'effet d'une fléchette dépend de son point d'impact (2.13), pas de sa case.

Une **cible ronde** (`blob` dans les identifiants, pour ne pas la confondre avec les « cibles » des autres jeux) est un disque : un centre (`x`, `y`) en millimètres entiers dans le repère du plateau (2.1), un rayon `radius` et des points de vie `hitPoints`.

### 15.2 Options

| Option | Type | Valeurs | Défaut |
|---|---|---|---|
| `movingTargets` | Bool | `false` : une cible ne bouge que lorsqu'elle est détruite. `true` : toutes les cibles changent de place au début de chaque tour *(option Dartsee « Moving targets »)* | `false` |
| `rounds` | Int | 1–20 | 8 |

La limite de manches est `rounds` ; il n'y a pas d'option `maxRounds`.

**Tailles** (fixes) :

| `size` | Taille | Rayon (mm) | `hitPoints` de départ | Points par touche | Bonus de destruction |
|---|---|---|---|---|---|
| `large` | grande | 40 | 3 | 10 | 20 |
| `medium` | moyenne | 28 | 2 | 20 | 40 |
| `small` | petite | 16 | 1 | 50 | 100 |

**Emplacements.** Le plateau porte toujours cinq cibles, numérotées de 0 à 4, de tailles `large`, `large`, `medium`, `medium`, `small`. Un emplacement garde sa taille toute la partie.

### 15.3 État initial

**Placement d'une cible** : `place(radius, obstacles)`, où `obstacles` est une liste de disques (`ox`, `oy`, `or`).

1. `candidats` = les points (`x`, `y`) de la grille de pas 5 mm (`x` et `y` multiples de 5, de −170 à 170), parcourus rangée par rangée, `y` croissant de −170 à 170 et dans chaque rangée `x` croissant de −170 à 170, en ne gardant que ceux qui vérifient :
   - `x² + y² ≤ (170 − radius)²` : le disque tient entièrement dans la zone de score ;
   - pour chaque obstacle, `(x − ox)² + (y − oy)² ≥ (radius + or + 6)²` : au moins 6 mm entre deux disques.
2. Si `candidats` est vide, on le recalcule sans la seconde condition (chevauchement accepté). Ce cas n'existe que pour rendre la fonction totale : il ne s'est jamais produit sur les quelque 480 000 placements de deux essais de charge, celui de l'implémentation de référence et celui d'une implémentation indépendante (plus petite liste rencontrée : 15 candidats). Aucune graine connue ne le déclenche : le repli se teste en appelant `place` directement (RAD-6).
3. Centre = `candidats[rng.nextInt(below: candidats.count)]` : **un tirage**, exactement.

Tous ces calculs sont entiers.

**Tirage initial** : pour les emplacements 0 à 4 dans l'ordre, centre = `place(rayon de l'emplacement, cibles déjà posées)` ; chaque cible reçoit les points de vie de sa taille. 5 tirages.

Par joueur : `points = 0`, `destroyed = 0`, `dartsThrown = 0`.

### 15.4 Effet d'une fléchette

Soit (`X`, `Y`) le point d'impact de la fléchette, en dixièmes de millimètre (2.13). Dans tous les cas `dartsThrown += 1`.

**Cible touchée** : le premier emplacement, dans l'ordre 0 à 4, tel que `(X − 10·x)² + (Y − 10·y)² ≤ (10·radius)²`. Le bord du disque compte. Tant qu'aucun chevauchement n'existe, il y en a au plus un.

| Cas | Effet |
|---|---|
| pas de point d'impact (`MISS`), ou point dans aucune cible | aucun effet (`noEffect`) |
| cible touchée, `hitPoints > 1` | `hitPoints −= 1` ; `points += points par touche` (`blobDamaged`) |
| cible touchée, `hitPoints == 1` | **destruction** : `points += points par touche + bonus` ; `destroyed += 1` (`blobDestroyed`) ; puis **remplacement immédiat** |

**Remplacement.** L'emplacement reçoit une cible neuve de même taille, avec tous ses points de vie, au centre `place(radius, les cinq cibles à leur place actuelle, y compris celle qui vient d'être détruite)`. La nouvelle cible n'apparaît donc jamais là où était l'ancienne. Un tirage.

Précisions :

- C'est la **pointe** qui compte : une fléchette touche une cible si son point d'impact est dans le disque, quelle que soit sa case.
- Seule la fléchette en cours est évaluée, contre les cibles telles qu'elles sont à cet instant. Une fléchette déjà plantée n'est jamais réévaluée, même si une cible apparaît sous elle. Cette règle vaut pour le jeu en avant. Après une correction ou une suppression (2.5), tout le tour est rejoué : les fléchettes suivantes de la volée sont réévaluées contre les cibles telles que les laisse l'historique corrigé, et les remplacements sont tirés à nouveau dans cet ordre. L'effet d'une fléchette non corrigée peut donc changer (RAD-7).
- Une même volée peut détruire plusieurs cibles, et deux fois le même emplacement.
- **Fléchette sans position.** Sans position enregistrée, une fléchette vaut la position canonique de sa case (2.13) et ne peut toucher qu'une cible qui recouvre l'un des 62 points canoniques. Sur 2000 placements initiaux, environ une petite cible sur deux n'en recouvre aucun (51 %), contre 18 % des moyennes et 11 % des grandes. Dans Radar, l'interface DOIT donc proposer la saisie et la correction par un point sur la cible (tap, réticule). Choisir une case dans une liste reste accepté par le moteur, mais déplace la fléchette au point canonique et peut changer son effet, même quand la case ne change pas (RAD-3).

**Cibles mobiles** (`movingTargets == true`)

- **Quand** : au début de chaque tour sauf le premier de la partie, c'est-à-dire pendant le `endTurn` qui donne la main (étape 4 de 2.4). Jamais pendant un tour. Rien ne bouge quand ce `endTurn` termine la partie.
- **Comment** : pour les emplacements 0 à 4 dans l'ordre, nouveau centre = `place(radius, les cinq cibles à leur place actuelle, y compris elle-même)`. Chaque cible part donc vraiment ailleurs, et les cibles déjà déplacées comptent à leur nouvelle place. 5 tirages par `endTurn`.
- **Ce qui est conservé** : la taille et les `hitPoints` de chaque cible.
- **Déterminisme** : les déplacements ne dépendent que du `seed` et du journal. Annuler puis refaire un `endTurn` redonne les mêmes places.

### 15.5 Déroulement du tour

3 fléchettes par tour. Rien n'écourte un tour. À la clôture, le total des points gagnés pendant le tour est annoncé (`turnScored`).

### 15.6 Élimination, victoire, classement

- Pas d'élimination, pas de victoire sur une fléchette.
- **Fin** (`roundLimit`) : à la confirmation du dernier tour de la manche `rounds`.
- **Classement** : (1) `points` décroissant ; (2) `destroyed` décroissant ; (3) ex æquo.

### 15.7 Tableau de score et surbrillances

Par joueur : `points` (valeur principale), `destroyed` (cibles détruites), total de la dernière volée, `dartsThrown`, rang.

Champ de partie : `blobs`, les cinq cibles dans l'ordre des emplacements, chacune (`x`, `y`, `radius`, `hitPoints`).

Surbrillances, les mêmes pour tous les joueurs : une par cible, zone `disc(x, y, radius)` (2.9), rôle `target`, sans propriétaire, étiquette `+10`, `+20` ou `+50` (les points par touche), points de vie = `hitPoints`.

### 15.8 Événements

| Événement | Quand | Idée de son / animation |
|---|---|---|
| `blobDamaged(player, blob, points, hitPointsLeft)` | touche sans destruction ; `blob` = emplacement 0 à 4, `points` = points gagnés | impact, la cible se fissure |
| `blobDestroyed(player, blob, points)` | destruction ; `points` = points par touche + bonus | explosion, bonus affiché, la nouvelle cible apparaît |
| `blobsMoved` | `movingTargets` : pendant `endTurn`, juste avant `turnStarted` | balayage du radar, les cibles glissent |
| `turnScored(player, points)` | clôture de chaque tour ; total gagné dans le tour | annonce vocale du total |
| `noEffect(player)` | fléchette qui ne touche aucune cible | son neutre |
| `gameFinished(roundLimit)` | fin de partie | écran de victoire |

Radar n'émet jamais `oneEighty` ni `highTurn` (2.10).

### 15.9 Vecteurs de test

`blobs` liste les cinq cibles par emplacement, chacune `(x, y, radius, hitPoints)` ; les positions canoniques citées sont en dixièmes de millimètre (2.13).

```
RAD-1  placement initial, lié au seed
jeu      radar                             joueurs 2      seed 1
attendu  (début) 5 tirages, un par emplacement :
           emplacement 0 (large ) : 2121 candidats, index 1934 → centre (-80, 95)
           emplacement 1 (large ) : 1682 candidats, index  427 → centre (70, -65)
           emplacement 2 (medium) : 1559 candidats, index 1258 → centre (110, 65)
           emplacement 3 (medium) : 1267 candidats, index  854 → centre (25, 15)
           emplacement 4 (small ) : 1598 candidats, index  955 → centre (140, 0)
         blobs = (-80, 95, 40, 3), (70, -65, 40, 3), (110, 65, 28, 2), (25, 15, 28, 2), (140, 0, 16, 1)      (x, y, radius, hitPoints)
         surbrillances : cinq zones disc de rôle target, étiquettes +10, +10, +20, +20, +50, points de vie 3, 3, 2, 2, 1
radar, seed 0  → blobs = (45, 85, 40, 3), (-15, -120, 40, 3), (85, -15, 28, 2), (0, 10, 28, 2), (-85, -120, 16, 1)
radar, seed 42 → blobs = (-60, -100, 40, 3), (-30, 85, 40, 3), (0, -55, 28, 2), (120, -10, 28, 2), (-110, 85, 16, 1)

RAD-2  fléchettes sans position : position canonique, destruction, remplacement
jeu      radar                             joueurs 2      seed 1
entrées  S9, T12, S20
attendu  S9 (-1088, 791) et T12 (-605, 833) sont dans la cible 0 : blobs[0].hitPoints = 1
         S20 (0, 1345) n'est dans aucune cible ; points = 20 / 0
         événements de la 3e fléchette : dartRegistered, noEffect, turnScored(20), turnCompleted
entrées  (suite) | SB, T4, MISS
attendu  SB touche la cible 3 et T4 la cible 2 : blobs[3].hitPoints = 1 ; blobs[2].hitPoints = 1 ; points = 20 / 40
entrées  (suite) | S9
attendu  cible 0 détruite : J1.points = 50 ; J1.destroyed = 1 ; événements : dartRegistered, blobDestroyed(blob: 0, points: 30)
         remplacement : 540 candidats, index 428 → blobs[0] = (-110, 0, 40, 3)   (6e tirage)
entrées  (suite) S6
attendu  cible 4 détruite d'une seule touche : J1.points = 200 ; J1.destroyed = 2 ; événements : dartRegistered, blobDestroyed(blob: 4, points: 150)
         remplacement : 1433 candidats, index 804 → blobs[4] = (0, 60, 16, 1)
entrées  (suite) S9
attendu  noEffect : la cible 0 a changé de place ; phase = turnComplete ; points = 200 / 40
         événements : dartRegistered, noEffect, turnScored(180), turnCompleted   (180 points dans la volée, mais jamais de oneEighty)
         blobs = (-110, 0, 40, 3), (70, -65, 40, 3), (110, 65, 28, 1), (25, 15, 28, 1), (0, 60, 16, 1)

RAD-3  fléchettes avec position : même case, effets différents
jeu      radar                             joueurs 1      seed 1
entrées  S6@(123.9, 0.0), S6@(124.0, 0.0), S6
attendu  1re : à 0,1 mm hors de la cible 4 (140, 0, 16, 1) : noEffect
         2e : exactement sur le bord (bord compris) : cible 4 détruite, points = 150
         3e : sans position, S6 vaut (1345, 0) ; la cible 4 est maintenant en (60, 105, 16, 1) : noEffect
         points = 150 ; destroyed = 1 ; phase = turnComplete
entrées  (suite) | MISS@(25.0, 15.0), T20@(25.0, 15.0) | S18@(25.0, 43.06), S18@(25.0, 43.04)
attendu  MISS ne touche rien, même avec une position au centre de la cible 3 (25, 15, 28, 2)
         T20 avec cette même position : la position est prise telle quelle, cible 3 touchée, points = 170
         arrondi au dixième : y = 43.06 devient 431 dixièmes, hors de la cible ; y = 43.04 devient 430, sur le bord : cible 3 détruite
         points = 230 ; destroyed = 2
jeu      radar                             joueurs 1      seed 1
entrées  S6@(123.9, 0.0)
attendu  noEffect ; points = 0
puis     replaceDart(0, S6) sans position → la position est effacée, S6 vaut (1345, 0) : cible 4 détruite ; points = 150 ;
                                            blobs[4] = (60, 105, 16, 1)   (la case n'a pas changé, l'effet si)
jeu      radar                             joueurs 1      seed 1
entrées  S12@(-120.05, 95.0), S12@(-120.04, 95.0)
attendu  1re : x = −1200,5 dixièmes devient −1201 (le demi s'éloigne de zéro), à 0,1 mm hors de la cible 0 (-80, 95, 40, 3) : noEffect
         2e : x = −1200,4 dixièmes devient −1200, sur le bord : blobDamaged(blob: 0, points: 10, hitPointsLeft: 2) ; points = 10
         (un arrondi « au pair » donnerait −1200 pour la 1re, qui toucherait la cible : ce vecteur fixe la règle des demis)

RAD-4  cibles mobiles, déterministes
jeu      radar { movingTargets: true }     joueurs 2      seed 7
attendu  (début) blobs = (-120, 50, 40, 3), (80, -50, 40, 3), (-50, 0, 28, 2), (-5, 95, 28, 2), (75, 130, 16, 1)   (identiques à la partie sans l'option)
entrées  S9, MISS, MISS |
attendu  S9 touche la cible 0 ; au début du tour de J2 les cinq cibles changent de place et gardent leurs points de vie :
         tirages 0 : 348 candidats, index 201 ; 1 : 207 candidats, index 160 ; 2 : 857 candidats, index 510 ; 3 : 678 candidats, index 317 ; 4 : 1496 candidats, index 481
         blobs = (-10, -75, 40, 2), (-110, 65, 40, 3), (115, 0, 28, 2), (-105, -20, 28, 2), (45, -45, 16, 1)   (10 tirages depuis le début)
         événements du endTurn : blobsMoved, turnStarted(J2, 1)
entrées  (suite) MISS ×3 |
attendu  blobs = (-25, 115, 40, 2), (-65, -110, 40, 3), (35, 60, 28, 2), (110, 45, 28, 2), (95, -110, 16, 1) ; round = 2 ; 15 tirages
         événements du endTurn : roundStarted(2), blobsMoved, turnStarted(J1, 2)
puis     undo puis endTurn → mêmes blobs ; rejouer tout le journal → mêmes blobs à chaque étape

RAD-5  fin de partie : à égalité de points, les cibles détruites départagent
jeu      radar { rounds: 2 }               joueurs 2      seed 1
entrées  S4@(110.0, 65.0), S4@(110.0, 65.0), MISS
         | S12@(-80.0, 95.0), S12@(-80.0, 95.0), S15@(70.0, -65.0)
         | MISS ×3
         | S15@(70.0, -65.0), S4@(25.0, 15.0), S7@(-70.0, -90.0)
attendu  points = 80 / 80 ; destroyed = 1 / 0 ; phase = turnComplete
         (J1 détruit la cible 2 : 20 + 60 ; J2 touche les cibles 0, 0, 1, puis 1, 3 et la nouvelle cible 2 en (-70, -90))
entrées  (suite) |
attendu  phase = finished ; finishReason = roundLimit ; ranks = [1, 2]

RAD-6  propriétés et refus
radar, seeds 0 à 199 → les cinq cibles ont un centre multiple de 5 mm, tiennent dans le rayon 170 et sont
                       séparées d'au moins 6 mm deux à deux
place(40, aucun obstacle) → 2121 candidats ; le premier est (0, -130), le dernier (0, 130)
place(40, [(0, 0, 130)]) → aucun point ne vérifie la seconde condition : repli sans elle, 2121 candidats,
                           le premier (0, -130), le dernier (0, 130)
radar, 9 joueurs ou { rounds: 21 } → création refusée

RAD-7  corriger une fléchette antérieure rejoue les suivantes
jeu      radar                             joueurs 1      seed 1
entrées  S6@(124.0, 0.0), S6
attendu  1re : cible 4 détruite, remplacée en (60, 105) ; 2e, sans position : S6 vaut (1345, 0), noEffect ; points = 150
puis     replaceDart(0, MISS)             → volée = [MISS, S6] ; la 1re ne touche plus rien, la cible 4 est restée en (140, 0)
                                            et la 2e, inchangée, la détruit : blobDestroyed(blob: 4, points: 150)
                                            points = 150 ; destroyed = 1 ; blobs[4] = (60, 105, 16, 1) ; phase = throwing ; 6 tirages
```

---

## 16. Golf (`golf`)

### 16.1 Fiche

- **id** : `golf`
- **Noms** : FR « Golf » — EN "Golf"
- **En une ligne** : FR « Un numéro par trou : 1 coup pour le double, 2 pour le triple, 3 pour le simple, 5 si vous le manquez. Le moins de coups gagne. » — EN "One number per hole: 1 stroke for the double, 2 for the treble, 3 for the single, 5 if you miss it. Fewest strokes wins."
- **Joueurs** : 1 à 8 (Dartsee : 2 à 10).
- **Ce n'est pas le Golf de Dartsee.** Le Golf de Dartsee est un mini-golf animé : l'impact donne la direction et la force d'un putt, avec rebonds, bacs de sable et accélérateurs, sur des parcours dessinés. Cette application ne reproduit ni cette physique ni ces parcours. Sous le même nom et le même identifiant, cette section spécifie le **Golf traditionnel aux fléchettes** : un numéro par trou, un nombre de coups selon l'anneau touché, le moins de coups gagne.
- **Provenance** : *(conception propre, inspirée de Dartsee)* pour le choix du jeu ; les règles elles-mêmes sont la règle de pub la plus répandue, avec une adaptation : elle compte 3 coups pour le simple intérieur et 4 pour le simple extérieur, que la notation de ce document ne distingue pas (2.2). Ici tout simple vaut 3.
- **Dépend de la position** : non.

### 16.2 Options

| Option | Type | Valeurs | Défaut |
|---|---|---|---|
| `holes` | Int | 1–18 (l'interface propose 9 et 18) | 9 |
| `countedDart` | enum | `last` : la **dernière** fléchette lancée compte (règle traditionnelle : on s'arrête quand on est satisfait). `best` : la **meilleure** fléchette du tour compte (plus facile) | `last` |

La limite de manches est `holes` ; il n'y a pas d'option `maxRounds`.

### 16.3 État initial

Par joueur : `strokes = 0` (total des coups), `holesPlayed = 0`, `holeScores = []` (le score de chaque trou joué).

Le trou de la manche `r` se joue sur le **numéro `r`** (trou 1 sur le 1, …, trou 18 sur le 18). Le par de chaque trou est 3. Valeur dérivée : `toPar = strokes − 3 × holesPlayed`.

### 16.4 Effet d'une fléchette

Valeur d'une fléchette pendant le trou `r` :

| Fléchette | Valeur |
|---|---|
| `Dr` | 1 |
| `Tr` | 2 |
| `Sr` | 3 |
| tout le reste : autre numéro, `SB`, `DB`, `MISS` | 5 |

- Chaque fléchette émet `shotPlayed` avec sa valeur.
- **Score provisoire** du trou : la valeur de la dernière fléchette lancée (`last`), ou la plus petite valeur du tour (`best`) ; 5 tant qu'aucune fléchette n'est lancée.
- Un `Dr` **clôt le tour** immédiatement (`phase = turnComplete`) : on ne peut pas faire mieux, et en mode `last` une fléchette de plus ne pourrait que coûter.
- Rien n'est ajouté à `strokes` avant la clôture du tour.

### 16.5 Déroulement du tour

- 3 fléchettes au plus par tour.
- **S'arrêter est un coup du jeu** : le joueur peut confirmer après une ou deux fléchettes (`endTurn`, 2.4) pour garder son score provisoire. En mode `last`, c'est tout l'enjeu : garder un 3, ou risquer une fléchette de plus pour un 2 ou un 1, au risque d'un 5. Dans ce jeu, l'interface NE DOIT PAS demander de confirmation supplémentaire pour une volée incomplète.
- **À la clôture du tour** (double, 3e fléchette ou confirmation) : score du trou = score provisoire ; `strokes += score`, `holesPlayed += 1`, le score est ajouté à `holeScores` (`holeCompleted`, puis `holeInOne` si le score vaut 1). Un tour confirmé sans aucune fléchette vaut 5.

### 16.6 Élimination, victoire, classement

- Pas d'élimination, pas de victoire sur une fléchette.
- **Fin** (`roundLimit`) : à la confirmation du dernier tour du trou `holes`.
- **Classement** : (1) `toPar` croissant ; (2) ex æquo. À la fin de la partie tous les joueurs ont joué le même nombre de trous, et classer par `toPar` revient à classer par `strokes`. Pendant la partie, `toPar` donne un classement provisoire juste entre un joueur qui a déjà joué le trou en cours et un joueur qui ne l'a pas encore joué.

### 16.7 Tableau de score et surbrillances

Par joueur : `strokes` (valeur principale, unité « coups »), `toPar` (badge « −2 », « Par », « +3 »), `holeScores`, `holesPlayed`, score provisoire du trou en cours pour le joueur courant, rang. En-tête : « Trou r / holes · par 3 ».

Surbrillances pour le trou `r` : `double(r)` → `target`, étiquette `1` ; `treble(r)` → `target`, étiquette `2` ; `single(r)` → `secondary`, étiquette `3`.

### 16.8 Événements

| Événement | Quand | Idée de son / animation |
|---|---|---|
| `shotPlayed(player, strokes)` | chaque fléchette ; `strokes` = sa valeur (1, 2, 3 ou 5) | bruit de balle, plus ou moins heureux |
| `holeCompleted(player, hole, strokes, total)` | clôture du tour ; `strokes` = score du trou, `total` = nouveau `strokes` du joueur | annonce « 3 coups » |
| `holeInOne(player, hole)` | le score du trou vaut 1, juste après `holeCompleted` | fanfare « Trou en un ! » |
| `gameFinished(roundLimit)` | fin de partie | écran de victoire |

Le Golf n'émet jamais `noEffect` : toute fléchette fixe ou confirme le score du trou. Ordre à la clôture : `holeCompleted`, `holeInOne` s'il y a lieu, puis `turnCompleted`.

### 16.9 Vecteurs de test

`valeurs` liste la valeur de chaque fléchette du tour ; `toPar` porte son signe.

```
GOL-1  valeur d'une fléchette ; la dernière compte
jeu      golf                              joueurs 1
entrées  S1, T1, S5
attendu  valeurs = 3, 2, 5 ; J1.strokes = 5 ; holeScores = [5] ; toPar = +2 ; phase = turnComplete
         événements de la 3e fléchette : dartRegistered, shotPlayed(5), holeCompleted(hole: 1, strokes: 5, total: 5), turnCompleted

GOL-2  s'arrêter à temps ; trou sans fléchette
jeu      golf                              joueurs 1
entrées  S1 |
attendu  J1.strokes = 3 ; holeScores = [3] ; round = 2
         événements du endTurn : holeCompleted(hole: 1, strokes: 3, total: 3), turnCompleted, roundStarted(2), turnStarted(J1, 2)
entrées  (suite) |
attendu  trou 2 sans fléchette : J1.strokes = 8 ; holeScores = [3, 5] ; toPar = +2 ; round = 3

GOL-3  le double clôt le tour : trou en un
jeu      golf                              joueurs 2
entrées  S20, D1
attendu  valeurs = 5, 1 ; phase = turnComplete après 2 fléchettes ; J1.strokes = 1 ; J1.toPar = -2 ; dart(S1) refusée
         événements de la 2e fléchette : dartRegistered, shotPlayed(1), holeCompleted(hole: 1, strokes: 1, total: 1), holeInOne(hole: 1), turnCompleted
entrées  (suite) | T1, S1, MISS
attendu  J2.strokes = 5 ; ranks = [1, 2]

GOL-4  variante « meilleure fléchette »
jeu      golf { countedDart: best }        joueurs 2
entrées  T1, S1, MISS | MISS, MISS, S1 |
attendu  strokes = 2 / 3 ; ranks = [1, 2]
         (même journal avec countedDart: last : strokes = 5 / 3 ; ranks = [2, 1])

GOL-5  partie complète sur 2 trous, classement par rapport au par
jeu      golf { holes: 2 }                 joueurs 2
entrées  T1 | S1, S1, D1 |
attendu  strokes = 2 / 1 ; toPar = -1 / -2 ; ranks = [2, 1] ; round = 2
         surbrillances : target = [double(2), treble(2)] ; secondary = [single(2)]
entrées  (suite) S2, T2 |
attendu  J1 a joué 2 trous, J2 un seul : strokes = 4 / 1 ; toPar = -2 / -2 ; ranks = [1, 1]
entrées  (suite) SB, DB, S1 |
attendu  phase = finished ; finishReason = roundLimit ; strokes = 4 / 6 ; holeScores = [2, 2] / [1, 5] ; ranks = [1, 2]

GOL-6  configurations refusées
golf { holes: 0 } ou { holes: 19 }                → création refusée
golf, 9 joueurs                                   → création refusée

GOL-7  corrections : vers un double, hors d'un double
jeu      golf                              joueurs 1
entrées  S1, T1, S5                        → strokes = 5
puis     replaceDart(0, D1)               → volée = [D1] ; phase = turnComplete ; strokes = 1 ; holeScores = [1]
                                            (au rejeu le double clôt le tour : T1 et S5 disparaissent du journal)
jeu      golf                              joueurs 1
entrées  S20, D1                           → phase = turnComplete ; strokes = 1
puis     replaceDart(1, S1)               → volée = [S20, S1] ; phase = throwing ; strokes = 0 ; holeScores = []
                                            (le tour se rouvre : rien n'est compté avant la clôture)
```

---

## 17. Jeux Dartsee reportés (hors v1)

Les onze jeux de la page des jeux de Dartsee sont spécifiés dans ce document (sections 3 à 5, 7, 10 à 16). Deux jeux plus récents de Dartsee n'y figurent pas et restent **hors périmètre** : ce sont des jeux en 3D, portés par un moteur physique ou par une progression de zones dont Dartsee ne publie rien. Ils ne sont pas spécifiés ici ; chacun demandera sa propre section s'il est décidé un jour.

| id réservé | Nom | Principe connu *(Dartsee)* | Ce qu'il manque |
|---|---|---|---|
| `castleCrushers` | Castle Crushers | jeu 3D : les fléchettes sont des boulets contre un château ; barils explosifs, réactions en chaîne | moteur physique 3D, niveaux |
| `dartsClass` | Darts Class | entraînement : viser des zones de taille variable, plus ou moins payées selon leur difficulté | tailles, valeurs et progression des zones ; les deux modes et les trois niveaux |

Rien ne ferme la porte à ces jeux : depuis la version 1.1, chaque fléchette transporte la position de son impact quand elle est connue, et un moteur peut la lire s'il se déclare dépendant de la position (2.13) ; les zones disque existent pour les surbrillances (2.9).

---

## 18. Écarts avec Dartsee et points non confirmés

| Jeu | Point | Ce que dit Dartsee | Décision de ce document |
|---|---|---|---|
| Tous | Nombre de joueurs | variable selon les documents (1–6, 2–10, 1–12) | 1–8 partout, sauf Killer Facile (6), Combat (6) et les jeux à 2 joueurs minimum |
| Tous | Égalité finale | « mort subite », mécanique non décrite | ex æquo, pas de mort subite en v1 |
| Tous | Équipes | groupes aléatoires ou composés à la main | pas d'équipes en v1 ; seul Football répartit les joueurs en deux camps, par leur index |
| Tous | Fin du tour | suivi automatique du retrait des fléchettes | confirmation explicite par défaut ; le retrait détecté ne passe le tour que si le réglage `endsTurnOnTakeout` est activé (désactivé par défaut, 2.4) |
| X01 | Limite de manches | 15 | 20 par défaut, réglable |
| X01 | Bull intérieur = double | non précisé | oui |
| X01 | Vainqueur à la limite | non précisé | plus petit reste |
| Cricket | Limite de manches | 20 (manuel) ou 15 (site) | 20 |
| Cricket | Marques du bull | non précisé | `SB` 1 marque, `DB` 2 marques, 25 points |
| Cricket | Fin de partie | « tout fermé avec le plus petit score » (cut-throat) | tout fermé et aucun score strictement meilleur, dans les deux modes |
| Cricket Light | Tirage | « quatre numéros au hasard » | 4 numéros parmi 15–20, sans bull |
| Killer | Niveaux | deux : Beginner (« Killer Lite », numéro + 2 voisins) et Pro (numéro exact) | quatre : Facile = Beginner, Difficile = Pro, Intermédiaire et Expert conçus ici |
| Killer | Joueurs | 2–6 (manuel) ou 2–10 (site) | 2–8 ; 2–6 en Facile |
| Killer | Toucher sa zone une fois Killer | non précisé (version « simplifiée ») | sans effet ; pénalité classique en option (`selfHitPenalty`) |
| Killer | Attaquer un joueur non armé | non précisé | autorisé |
| Killer | Unicité et chevauchement des zones | non précisé | zones toujours disjointes |
| Killer | Fin à la limite de manches | non précisé | vies, puis kills, puis armement |
| Shanghai | Nombre de manches | 7 (manuel) ou 25 (site) | 7 par défaut, 1 à 20 |
| Shanghai Lite | Points des voisins | « +1 » visible en manche 1 seulement | valeur simple du numéro de la manche |
| Alunissage | Dépassement en mode Pro | « forfait » et « bust » dans le même manuel | bust |
| Combat | Numéros par joueur | manuel : « ton numéro » ; capture et exploitant : 1 soin + 2 points faibles | 1 soin + 2 points faibles |
| Combat | Plafond du soin | non précisé | plafonné aux vies de départ |
| Combat | Joueurs et manches | 2–4 ; 15 (manuel) ou 25 (site) | 2–6 ; 15 |
| Conquérant | Maisons, Roi, conquête | grandes lignes seulement ; « le plus de vies » et « le plus de points » | règles complètes de la section 12 ; total des vies |
| Tireuse | Formule de remplissage | « plus le score est haut, plus la bière coule » ; un verre avec un pourcentage ; aucune formule | 1 point = 1 cl ; verre de 50 cl par défaut ; le trop-plein passe au verre suivant ; un verre offert pour une volée de 100 points ou plus |
| Tireuse | Joueurs et manches | 2–10 ; 15 manches au plus, capture « 1/5 » | 1–8 ; 5 manches par défaut |
| Football | Principe | cible transparente centrée sur le ballon ; l'impact donne l'endroit où roule le ballon ; physique ; deux tailles de cible | pas de physique ni de position : terrain à une dimension, la moitié de cible touchée pousse le ballon de 1, 2 ou 3 pas |
| Football | Équipes | deux équipes composées sur la tablette | camp A = joueurs d'index pair (J1, J3…), camp B = index impair ; pas compensés quand les camps sont inégaux |
| Football | Joueurs et manches | 1–8 ou 2–10 ; 15 manches au plus, capture « 4/7 » | 2–8 ; 3 buts pour gagner, 10 manches au plus par défaut |
| Radar | Cibles | « blobs » de trois tailles ; valeurs 1000, 500 et 100 lues sur une capture ; « dégâts max. 90 » ; aucune règle publiée | cinq cibles rondes de trois tailles, 3, 2 ou 1 points de vie ; 10, 20 ou 50 points par touche ; bonus 20, 40 ou 100 |
| Radar | Mode « Time Pressure » | les dégâts baissent avec le temps d'attente | non repris : aucun jeu ne dépend d'une horloge |
| Radar | Mode « Moving Targets » | les cibles bougent à l'écran | les cibles changent de place entre deux tours, jamais pendant un tour |
| Radar | Joueurs et manches | 1–6 ou 1–8 ; 15 manches au plus | 1–8 ; 8 manches par défaut |
| Golf | Principe | mini-golf animé : l'impact donne la direction et la force du putt ; rebonds, sable, accélérateurs ; parcours de trois difficultés | **non reproduit**. À la place, le Golf traditionnel aux fléchettes : un numéro par trou, 1 coup pour le double, 2 pour le triple, 3 pour le simple, 5 sinon |
| Golf | Simple intérieur et extérieur | sans objet | la règle traditionnelle compte 3 et 4 ; la notation ne les distingue pas (2.2) : tout simple vaut 3 |
| Golf | Joueurs et manches | 2–10 ; capture « Hole 1/6 » | 1–8 ; 9 trous par défaut, 18 au plus |
| Sons | Effets, voix | aucune description | à concevoir à partir des événements de ce document |

---

## 19. Questions ouvertes pour le propriétaire

1. **Niveaux du Killer.** Les documents publics de Dartsee ne décrivent que deux niveaux (numéro + 2 voisins, et numéro exact). Les niveaux Intermédiaire (2 numéros adjacents) et Expert ont été conçus ici. Pour l'Expert, nous avons retenu : le numéro de chaque joueur est retiré au sort **au début de chacun de ses propres tours**. Si votre souvenir de Dartsee est différent (par exemple tous les numéros changent en même temps à chaque manche), dites-le : seule la règle de retirage de la section 5.4 change.
2. **Règles des quatre jeux ajoutés.** Tireuse, Football, Radar et Golf sont maintenant dans le périmètre (votre renvoi à la page des jeux de Dartsee a tranché l'ancienne question sur les jeux animés). Dartsee n'en publie aucune règle de score : celles des sections 13 à 16 sont les nôtres. Le Golf, en particulier, est le Golf traditionnel aux fléchettes et non le mini-golf animé de Dartsee. Si l'un de ces jeux doit se jouer autrement d'après votre souvenir, dites-le : chaque règle tient dans sa section et se change sans toucher aux autres jeux.
3. **Jeu en équipes.** Dartsee permet de jouer en groupes. La v1 est individuelle ; seul Football forme deux camps, d'office, d'après l'ordre des joueurs. Faut-il prévoir de vraies équipes composées à la main (cela touche tous les moteurs) ?
