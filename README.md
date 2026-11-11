# Dart Scanner

Application iPhone et iPad (SwiftUI, iOS et iPadOS 17 ou plus récent) qui compte les points d'une vraie cible de fléchettes. Le score vient de la caméra, posée sur un support face à la cible, ou d'un tap sur la cible dessinée à l'écran. L'application fait aussi l'arbitre de quatorze jeux. Elle annonce les scores à voix haute en français ou en anglais et accompagne chaque fléchette d'effets sonores synthétisés et de vibrations. Elle n'a aucune dépendance tierce.

Spécification : dossier `docs/`, en français ; le code et ses commentaires sont en anglais.

## Les quatorze jeux

Dans l'ordre de l'écran d'accueil (`GAMES.md` §1) :

| Jeu | En une ligne |
|---|---|
| X01 (301 / 501 / 701) | Partez de 301, 501 ou 701 et descendez exactement à zéro avant les autres. |
| Cricket | Fermez les numéros 15 à 20 et le bull en les touchant trois fois, puis marquez des points sur ceux que les autres n'ont pas fermés. |
| Killer, en quatre niveaux | Touchez votre zone pour devenir Killer, puis visez celles des autres : le dernier en vie gagne. Facile (3 cases, 2 à 6 joueurs), Intermédiaire (2 cases), Difficile (1 case), Expert (1 case qui change à chaque tour), 2 à 8 joueurs. |
| Shanghai | Une manche par numéro : marquez un maximum sur le numéro du moment, ou gagnez d'un coup avec simple + double + triple. |
| Alunissage | Partez à 200 de la Lune : chaque point vous rapproche, le premier posé gagne. |
| Combat | Neuf vies chacun : frappez les points faibles des autres, soignez-vous sur votre numéro. |
| Conquérant | Étendez votre territoire de secteur en secteur, fortifiez-le et prenez la maison des autres. |
| Tireuse | Chaque point verse un centilitre de bière : remplissez plus de verres que les autres. |
| Football | Deux camps, un ballon : chaque fléchette pousse le ballon du côté de la cible où elle se plante. |
| Radar | Cinq cibles rondes posées sur le plateau : chaque touche rapporte, chaque cible détruite est remplacée. |
| Golf | Un numéro par trou : 1 coup pour le double, 2 pour le triple, 3 pour le simple, 5 si vous le manquez. |
| Tour de l'horloge | Touchez les numéros de 1 à 20 dans l'ordre. |
| Meilleur score | Un nombre de manches fixe, tout compte : le plus gros total gagne. |
| La Moitié | Une cible imposée par manche : ratez-la avec vos trois fléchettes et votre score est divisé par deux. |

Dans tous les jeux, on peut annuler sans limite et corriger une fléchette mal lue, et une partie interrompue reprend où elle s'était arrêtée.

## Prérequis

- Un Mac avec **Xcode 27** (27.2 utilisé pour le développement, Swift 6) et son Simulateur iOS.
- **XcodeGen** (2.46 utilisé), pour produire `DartScanner.xcodeproj` à partir de `project.yml`.
- Pour l'application : iPhone ou iPad sous **iOS / iPadOS 17 ou plus récent**.

## Lancer l'application dans le Simulateur

Le projet Xcode n'est pas suivi par git ; on le génère :

```sh
xcodegen generate
open DartScanner.xcodeproj        # puis schéma « DartScanner », un simulateur, ⌘R
```

Ou en ligne de commande, depuis la racine du dépôt :

```sh
xcodebuild -project DartScanner.xcodeproj -scheme DartScanner \
  -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath build/dd build
xcrun simctl boot "iPhone 17"
xcrun simctl install "iPhone 17" build/dd/Build/Products/Debug-iphonesimulator/DartScanner.app
xcrun simctl launch "iPhone 17" com.example.dartscanner
```

Même chose avec `name=iPad Pro 13-inch (M5)` pour l'iPad. Le Simulateur n'a pas de caméra arrière : la saisie au doigt marche normalement, et le mode caméra montre une cible de synthèse de démonstration (question 4 ci-dessous).

## Installer l'application sur un iPhone ou un iPad

1. Créez `Config/Local.xcconfig` (fichier ignoré par git) avec votre identifiant d'équipe Apple Developer et un identifiant d'application à vous :

   ```
   DEVELOPMENT_TEAM = ABCDE12345
   DART_SCANNER_BUNDLE_ID = fr.votrenom.dartscanner
   ```

2. Régénérez le projet (`xcodegen generate`), branchez l'appareil, choisissez-le dans Xcode et lancez (⌘R). L'appareil doit avoir le mode développeur activé (Réglages › Confidentialité et sécurité › Mode développeur). Avec un compte Apple gratuit, il faut en plus approuver le développeur dans Réglages › Général › VPN et gestion de l'appareil.

`Config/Base.xcconfig` donne `com.example.dartscanner` par défaut et inclut `Local.xcconfig`, dont les lignes l'emportent. Il n'y a rien à changer dans `project.yml`.

## Tests et instantanés

Tout se lance depuis `DartKit/`, le paquet Swift qui contient tout le code de l'application (`App/` ne contient que le point d'entrée) :

```sh
cd DartKit
swift build                                       # tout le paquet, pour macOS
swift test                                        # tous les tests (Swift Testing)
swift test --filter DartGamesTests                # une cible de test
swift test --filter KillerTests                   # une suite
swift test -c release --filter DartVisionTests    # vision, suites lourdes comprises
xcodebuild -scheme DartUI -destination 'generic/platform=iOS Simulator' build   # branches iOS du paquet
swift run SnapshotTool --out ../build/snapshots   # tous les écrans en PNG
```

- **Tests** : environ 1 600 tests Swift Testing. Il y a une cible de test par module : règles et vecteurs de chaque jeu, vision sur images de synthèse, sons, écrans et modèles de vue. Les tests d'intégration (`DartGamesTests/Integration/`) jouent une partie entière de chacun des quatorze jeux, puis le Killer à ses quatre niveaux de 2 à 8 joueurs, avec corrections et rejeu.
- **SnapshotTool** dessine chaque écran en PNG, en français et en anglais, sur téléphone en portrait et sur iPad (et le jeu du Killer sur téléphone en paysage), dans `<sortie>/fr/` et `<sortie>/en/`. Il ne tourne que sur macOS. Les parties affichées sont jouées par les vrais moteurs avec des graines fixes, et les écrans caméra montrent des images de synthèse. `--lang fr` et `--only <id>` restreignent le rendu, par exemple `--only play-killer`.
- Ne lancez pas `xcodebuild -scheme DartKit-Package` pour iOS : ce schéma construirait aussi `SnapshotTool`.

## La lecture par caméra

L'appareil reste immobile sur un support, à environ 1 m de la cible, un peu en dessous et décalé de 20 à 30° de l'axe. Au **calibrage**, on place quatre repères sur le bord extérieur du double ; on peut aussi laisser la détection automatique les placer. On en tire une homographie qui envoie chaque pixel dans le repère de la cible, en millimètres. Pendant la partie, une **porte de mouvement** attend que l'image se stabilise après un lancer. La nouvelle fléchette apparaît alors comme une différence avec l'image de référence. On cherche la **pointe** au bout de la silhouette qui touche la cible, on la ramène en millimètres par le calibrage, puis on en tire la case (`T20`, `S5`…). Une **confiance** accompagne chaque lecture. Une fléchette sûre est comptée seule. Une fléchette douteuse est comptée mais marquée « à vérifier ». En dessous, l'application attend la réponse du joueur. Le retrait des fléchettes est détecté aussi. Sans caméra, ou en cas de doute, le mode photo et le tap sur la cible à l'écran restent toujours disponibles. Le détail est dans `docs/VISION.md`.

**Limites actuelles.**

- La lecture n'a été validée que sur des **images de synthèse**. Sur ces images, la pointe tombe à 0,1 à 0,3 mm près en médiane, et 54 fléchettes sur 54 sont lues dans la bonne case dans les scénarios du moteur.
- **Rien n'a encore tourné sur un vrai iPhone ni sur un vrai iPad.** Ces points ne sont donc pas vérifiés : l'autorisation de la caméra, le verrouillage de l'exposition, la rotation, la capture 4K à 30 images/s, les interruptions et la chaleur.
- Tous les **seuils** sont des valeurs de départ, à régler sur une vraie cible sous une vraie lumière (`VISION.md` §11.2). La recherche estime qu'une caméra unique, sans apprentissage, lit 80 à 90 % des fléchettes sans aide sous une bonne lumière.
- Certains cas restent difficiles, et l'application les marque le plus souvent « à vérifier » :
  - une pointe cachée derrière une autre fléchette, fréquente dans les groupes serrés ;
  - une ombre dure et longue ;
  - une fléchette toute noire sur un secteur noir ;
  - des fléchettes croisées sur une image figée.

  La liste complète est dans `VISION.md` §11.1.

## Où sont les documents

| Document | Contenu |
|---|---|
| `docs/ARCHITECTURE.md` | Cibles du paquet, contrats en Swift, plan de réalisation par lots, journal des intégrations, arbitrages (§14), questions ouvertes (§15) |
| `docs/GAMES.md` | Règles des quatorze jeux, options, événements, vecteurs de test |
| `docs/VISION.md` | Calibrage, détection, confiance, machine à états, mode photo, limites et paramètres à régler |
| `docs/DESIGN.md` | Couleurs, typographie, cible à l'écran, écrans, sons et vibrations |
| `docs/design/mockups/*.dc.html` | Maquettes validées (s'ouvrent dans un navigateur) |

## Questions ouvertes pour le propriétaire

1. **Passage automatique au joueur suivant** (`ARCHITECTURE.md` §15, q1). Le réglage « Passer au joueur suivant quand les fléchettes sont retirées » est désactivé par défaut. Faut-il l'activer par défaut ?
2. **Installation sur vos appareils** (§15, q2). Quel identifiant d'équipe Apple et quel identifiant d'application faut-il utiliser ? Ces deux valeurs vont dans `Config/Local.xcconfig`, et l'essai sur appareil est le seul moyen qui reste de vérifier la caméra.
3. **Taille du texte du système** (Dynamic Type, §15, q3). Toutes les polices ont une taille fixe. Faut-il suivre la taille choisie dans les réglages de l'iPhone, quitte à revoir certains écrans ?
4. **Démonstration dans le Simulateur** (§15, q4). Sans caméra arrière, le mode caméra montre une cible de synthèse sans dire que c'est une démonstration. Faut-il l'annoncer, ou montrer plutôt l'écran « Pas de caméra disponible » ?
5. **Accès à la caméra restreint** (contrôle parental, gestion de l'appareil). Il montre aujourd'hui le même écran que l'accès refusé, avec le texte « refusé ou limité ». Voulez-vous un écran distinct ?
6. **Écarts avec les maquettes laissés en l'état**, à accepter ou à faire changer :
   - les légendes des fléchettes au Killer suivent la couleur de l'effet, pas celle de la victime ;
   - une case « à vérifier » affiche « À vérifier » au lieu de l'effet de la fléchette ;
   - au X01, la ligne du joueur dit « Dernière volée » et le score n'a pas l'unité « restants » ;
   - la loupe de correction n'a pas de numéros ;
   - les lignes de l'écran des résultats diffèrent de la maquette ;
   - la zone du Killer lui-même est dessinée en contour (rôle `own`), là où la maquette la teinte de sa couleur.

7. **iPhone en paysage** (§15, q5). En paysage sur iPhone, l'écran de jeu met la barre d'actions sous la cible et retire le très grand nombre de la carte du joueur courant, pour que les autres joueurs restent visibles. Les maquettes ne dessinent pas ce cas. Cette disposition vous convient-elle ?

Les questions de règles (`GAMES.md` §19) et de vision (`VISION.md` §13) restent elles aussi ouvertes.
