# DESIGN.md — Direction visuelle validée

Direction validée par le propriétaire le 10 novembre 2026. Les maquettes de référence sont dans
`docs/design/mockups/*.dc.html` (HTML à styles en ligne : ouvrir le fichier pour lire les tailles,
couleurs et espacements exacts). Le canevas publié : <https://claude.ai/artifact/VzhiCFYKDuMbNJGosEtFQr>.

Ce document fait autorité pour `DartUI`. En cas de doute entre ce texte et une maquette, la maquette gagne.

## 1. Parti pris

- **Tableau de pub nocturne** : thème sombre unique (pas de thème clair), fonds presque noirs, texte blanc cassé,
  un accent ambre pour l'action principale, une couleur par joueur.
- **Polices système iOS** (SF Pro). Chiffres en `monospacedDigit()`. Titres en graisse `.heavy`/`.bold`.
- **Aucun emoji**, aucune barre d'état dessinée, pas de dégradés décoratifs. Icônes : SF Symbols.
- Cibles tactiles d'au moins 44 pt. Contraste texte d'au moins 4,5:1.
- Une information portée par la couleur est toujours doublée par un texte ou une forme (nom du joueur,
  numéros de zone, libellé « à vérifier »).

## 2. Jetons

### Couleurs

| Jeton | Hex | Usage |
|---|---|---|
| `background` | `#0E1114` | fond d'écran |
| `surface` | `#171C21` | cartes, lignes de joueur, panneaux bas |
| `surfaceRaised` | `#212830` | pastilles, badges neutres |
| `line` | `#2E3640` | bordures de 1 pt, séparateurs |
| `lineStrong` | `#5A6470` | bordures en pointillés, contours secondaires |
| `textPrimary` | `#F3F1EA` | texte principal |
| `textSecondary` | `#A9B1BA` | texte secondaire |
| `textTertiary` | `#8A939D` | numéros de cible inactifs, emplacements vides |
| `accent` | `#FFA630` | bouton principal, sélection, « à vérifier » |
| `onAccent` | `#1A1206` | texte sur l'accent |
| `info` | `#5CB2FF` | état caméra, origine Dartsee |
| `boardRed` | `#D8413A` | double/triple des secteurs noirs, bull intérieur |
| `boardGreen` | `#2F9E5B` | double/triple des secteurs clairs, bull extérieur |
| `boardCream` | `#E9DFC7` | simples clairs |
| `boardBlack` | `#1B1F23` | simples sombres |
| `boardSurround` | `#0A0C0E` | couronne des numéros |
| `cameraScrim` | `#0E1114` à 78 % | bulles et boutons posés sur l'image caméra |

### Couleurs des joueurs (dans l'ordre d'inscription)

`#FFA630` (ambre), `#5CB2FF` (bleu), `#B79CFF` (violet), `#FF8FB8` (rose), puis `#6FE0C8` (turquoise),
`#F2E26B` (jaune), `#FF8A5C` (corail), `#C8D0D8` (gris clair) pour les joueurs 5 à 8.
Le joueur 1 partage volontairement l'ambre de l'accent.

### Rayons, espacements, tailles

- Rayons : 16 (cartes, boutons principaux), 12 (lignes, cases de fléchette), 8 (badges), cercle complet (pastilles).
- Marges d'écran iPhone : 20 pt à gauche et à droite. iPad : 32 pt.
- Espacement vertical courant : 12 pt entre blocs d'un écran de jeu, 14 à 16 pt ailleurs.
- Bouton principal : hauteur 52 pt (56 sur iPad), fond `accent`, texte `onAccent`, 16 à 17 pt gras.
- Bouton secondaire : même hauteur, bordure 1 pt `line`, fond transparent.
- Ligne de joueur : 44 pt (56 sur iPad). La ligne du joueur courant a une bordure de 2 pt à sa couleur.

### Typographie (taille / graisse)

| Rôle | iPhone | iPad |
|---|---|---|
| Titre d'écran | 28–30 / heavy | 28 / heavy |
| Titre de jeu en partie | 20 / heavy | 28 / heavy |
| Score X01 restant | 64 / heavy, chiffres tabulaires | plus grand si la place le permet |
| Nom du vainqueur (résultats) | 88 / heavy, couleur du joueur | idem |
| Corps | 15–17 / regular ou semibold | 15–20 |
| Secondaire | 13 / regular | 13–15 |
| Case de fléchette | 17 / bold + 11 en dessous | 22 / bold + 13 |

## 3. La cible à l'écran (`DartboardView`)

Même dessin partout : partie, saisie manuelle, correction, niveaux du Killer.

- Couronne noire des numéros, anneaux double et triple rouge/vert alternés, simples noir/crème, bull vert et rouge.
  Le secteur 20 est en haut, noir avec double et triple rouges.
- Pour la lisibilité, les anneaux double et triple sont dessinés **un peu plus épais** que sur une vraie cible
  (maquette : double de 38,5 % à 35,5 % du diamètre en rayon, triple de 24,5 % à 21,5 %). Cet épaississement
  est purement visuel : le calcul du score à partir d'un tap utilise la géométrie officielle remise à l'échelle
  de ce dessin, de sorte qu'un tap sur l'anneau dessiné donne bien un double ou un triple. Les deux bulls, eux,
  gardent leurs rayons réglementaires (15,9 et 6,35 mm) : ils sont plus petits que sur les maquettes, pour
  qu'un tap marque ce qui est dessiné (`ARCHITECTURE.md` §8.4.3).
- Numéros inactifs en `textTertiary` ; numéros d'une zone ou d'une cible à viser dans la couleur concernée, en gras.
- **Surbrillances** (Killer, cible à viser) : le secteur est teinté à environ 60 % de la couleur du joueur,
  le reste de la cible est assombri à environ 62 % de `background`, et un arc plein de la même couleur court
  juste à l'extérieur du double. Une cible à viser sur un seul anneau (par exemple D12 pour finir) colore cet
  anneau en `accent`. La maquette `PlayX01` n'assombrit pas le reste de la cible autour de cet anneau ;
  `DartboardView` assombrit par défaut et l'écran de jeu peut s'en dispenser (`dimsUnhighlighted`).
- En dessous de 64 pt (pictogramme d'une option, maquette `KillerOptions`), la cible est un disque plat :
  secteurs entiers, sans numéros, sans anneaux, sans assombrissement.
- Fléchettes posées : disque de 14 pt (26 sur iPad), blanc cassé ou couleur du joueur, bordure sombre.
- Une surbrillance peut aussi être un **disque** posé sur la cible, à cheval sur plusieurs cases : c'est le cas
  des cibles de Radar, dessinées en `accent` (§4, « Disques de Radar »).

## 4. Écrans

| Écran | Maquette | Points clés |
|---|---|---|
| Accueil | `Main.dc.html` | Titre, bouton réglages, carte d'état de la caméra avec bascule « Scan caméra / Saisie manuelle », grille de jeux sur 2 colonnes (nom + phrase courte). |
| Préparation du Killer | `KillerOptions.dc.html` | Joueurs en pastilles, 4 niveaux en boutons radio avec pictogramme de zone, pas-à-pas pour les vies et les touches d'armement, bouton « Lancer la partie ». « Facile » est grisé au-delà de 6 joueurs avec l'explication. |
| Partie de Killer | `PlayKiller.dc.html` | En-tête (jeu, niveau, manche, état du scan, action « Photo » : §5), carte du joueur courant avec ses 3 cases de fléchette et l'effet de chacune, cible avec zones, liste des joueurs (zone, pastilles d'armement ou badge Killer, vies), annuler + « Fléchettes retirées, suivant ». |
| Partie de X01 | `PlayX01.dc.html` | Même en-tête, avec l'action « Photo ». Score restant en très grand, total de la volée, suggestion de finition, cases de fléchette avec leurs points, cible avec la case à viser, liste des joueurs avec leur reste. |
| Correction | `Correction.dc.html` | Vue agrandie de la cible centrée sur la pointe détectée, réticule déplaçable, propositions de cases voisines, « Hors cible », « Retirer la fléchette », « Valider ». |
| Résultats | `Results.dc.html` | Nom du vainqueur en très grand dans sa couleur, classement, « Revanche », « Changer de jeu ». Quand le jeu donne un titre de résultats (`winnerTitle` : au Football, « Le camp A gagne », « Match nul »), ce titre remplace le nom, en `textPrimary`, sur deux lignes au plus et réduit si besoin ; le classement dessous garde les couleurs des joueurs. |
| Réglages | `Settings.dc.html` | Son : effets, annonce vocale, voix FR/EN, volume, son en mode silencieux, baisse de la musique, vibrations (iPhone seulement). Caméra : mode direct/photo, recalibrer. |
| Calibrage | `Calibration.dc.html` | Image caméra plein écran, grille de la cible en `accent`, 4 repères déplaçables, consigne en bulle, panneau bas avec qualité d'alignement, « Détection auto », « Valider ». |
| Scan en direct | `LiveScan.dc.html` | Image caméra, pointe cerclée et étiquette par fléchette (blanche si sûre, ambre avec « ? » si à vérifier), état en bulle, panneau bas avec joueur, reste, cases, « Vérifier », « Fléchettes retirées ». |
| Mode photo | `PhotoMode.dc.html` | Image caméra, déclencheur, « Cible vide » pour la référence, résultat de la dernière photo, « Corriger », retour au direct. S'y ajoutent, hors maquette : « Importer une photo » et « Prendre une photo » (boutons secondaires du panneau bas), et un écran de revue qui s'affiche aussi quand le scan ne trouve rien (« Aucune nouvelle fléchette », avec la cause). Sans caméra, l'image est remplacée par un fond `surface` et seul « Importer une photo » est actif (§5). |
| iPad, partie | `PadPlayKiller.dc.html` | Paysage : cible à gauche sur toute la hauteur, colonne de droite avec en-tête, joueur courant, joueurs, vignette caméra « Agrandir », actions. |

Écrans sans maquette (suivre les mêmes jetons et composants) : gestion des joueurs, options des autres jeux,
parties des autres jeux (même gabarit que Killer ou X01 selon que le jeu se lit sur la cible ou sur un score),
aide au placement de l'appareil, autorisation caméra refusée.

### Accueil : une grille pilotée par les données, quatorze jeux

La grille de l'accueil n'est pas une liste dessinée à la main : elle affiche **une carte par jeu du registre**
(`GameRegistry.standard`), dans l'ordre du registre, et défile. La maquette `Main.dc.html` montre dix cartes ;
l'application en liste **quatorze** (`GAMES.md` §1), dans cet ordre :

1. les sept jeux Dartsee documentés : X01, Cricket, Killer, Shanghai, Alunissage, Combat, Conquérant ;
2. les quatre jeux Dartsee de conception propre : Tireuse, Football, Radar, Golf ;
3. les trois jeux classiques : Tour de l'horloge, Meilleur score, La Moitié.

Sur le nombre et l'ordre des cartes, ce paragraphe l'emporte sur la maquette ; le dessin d'une carte (nom,
phrase courte, tailles, espacements) reste celui de la maquette. Ajouter un jeu au registre ajoute une carte,
sans retoucher l'écran. Phrases courtes des quatre nouvelles cartes : « Remplir des verres » (Tireuse),
« Deux camps, un ballon » (Football), « Cibles rondes à détruire » (Radar), « Le moins de coups » (Golf).

### Les quatre nouveaux jeux : mêmes gabarits, aucun écran nouveau

Tireuse, Football, Radar et Golf se jouent sur l'écran de jeu commun, avec les deux gabarits existants. Leurs
options passent par l'écran de préparation commun (boutons radio, pas-à-pas, bascules).

| Jeu | Gabarit | Valeur principale d'une ligne de joueur | Ce qui change sur l'écran |
|---|---|---|---|
| Tireuse (`beerTap`) | score, comme `PlayX01.dc.html` | verres pleins, en très grand pour le joueur courant | Une jauge du verre entamé sous le grand nombre (même barre que la jauge de vie de Combat). Aucune surbrillance : la cible reste neutre. |
| Football (`football`) | cible, comme `PlayKiller.dc.html` | buts du camp, avec un badge « A » ou « B » | La moitié à viser est teintée comme une zone à viser, l'autre moitié comme une zone à éviter ; le bull est à viser. Score « A 2 – 1 B » dans l'en-tête. Chaque ligne de joueur porte une jauge d'avancée du ballon vers le but que son camp attaque. |
| Radar (`radar`) | cible | points | Les cibles du jeu sont des **disques** posés sur la cible (voir ci-dessous). Aucun secteur n'est teinté. |
| Golf (`golf`) | cible | coups, avec un badge d'écart au par (« −2 », « Par », « +3 ») | Le double et le triple du numéro du trou sont colorés en `accent` et portent « 1 » et « 2 » ; le simple est en surbrillance secondaire et porte « 3 ». « Trou 4 / 9 · par 3 » dans l'en-tête. |

**Disques de Radar.** Une surbrillance de Radar n'est pas un secteur mais un disque (`GAMES.md` §2.9, zone
`disc`), donné par son centre et son rayon en millimètres du plateau.

- Chaque disque est dessiné **dans la couleur des cibles à viser**, `accent` : remplissage `accent` à environ
  60 %, contour plein `accent` de 2 pt. Le reste de la cible est assombri comme pour toute surbrillance ; la
  surface sous le disque ne l'est pas.
- Au centre du disque, une pastille `accent` pleine porte les points par touche (« +10 », « +20 », « +50 ») en
  `onAccent`, gras. Quand le disque est trop petit pour la contenir, la pastille se place juste à côté.
- Les points de vie restants (1 à 3) sont des pastilles de 4 pt sous l'étiquette, pleines pour les points
  restants, vides pour les points perdus : la couleur n'est jamais seule à porter l'information.
- Dans ce jeu, la cible est dessinée **aux proportions réglementaires**, sans l'épaississement des anneaux du
  §3 : un disque à l'écran recouvre alors exactement le disque du jeu, et un tap dedans compte comme une touche.
- Une cible détruite s'efface en 200 ms ; sa remplaçante apparaît en fondu au nouvel endroit. Avec l'option
  « cibles mobiles », les disques glissent vers leur nouvelle place entre deux tours, jamais pendant un tour.

## 5. Comportements à respecter

- Le tour ne passe au joueur suivant que sur « Fléchettes retirées, suivant » ou, si le réglage est activé, sur
  le retrait détecté par la caméra. Ce réglage (`endsTurnOnTakeout`, « Passer au joueur suivant quand les
  fléchettes sont retirées », section Caméra des réglages) est **désactivé par défaut** ; il n'agit que si le
  tour est déjà clos et qu'aucune fléchette n'attend de réponse (`GAMES.md` §2.4, `ARCHITECTURE.md` §8.6).
  Sans lui, le retrait détecté met seulement le bouton en avant.
- Une volée incomplète demande une confirmation avant de passer au joueur suivant, sauf au Golf, où s'arrêter
  après une ou deux fléchettes est un coup normal (`GAMES.md` §16.5).
- Une fléchette de confiance moyenne est comptée mais marquée « à vérifier » en `accent` ; un tap ouvre la correction.
- Une fléchette de confiance basse n'est pas comptée : l'écran de correction s'ouvre avec les cases possibles.
- L'écran de jeu porte **toujours** une action « Photo » (SF Symbol `camera`, bouton secondaire de l'en-tête, à côté de l'état du scan ; cible tactile de 44 pt), même en saisie manuelle et sans caméra. Elle ouvre le mode photo, où « Importer une photo » est toujours actif, « Prendre une photo » quand la caméra délivre des images, « Cible vide » et « Scanner » seulement en déclenchement manuel, la vision au repos, et « Scanner » seulement tant que la volée attend encore une fléchette (`ARCHITECTURE.md` §8.6, §8.7). Sur ce point le texte l'emporte sur les maquettes `PlayKiller`, `PlayX01`, `PadPlayKiller` et `PhotoMode`, qui ne montrent ni cette action ni ces deux boutons.
- En saisie manuelle, un tap sur la cible pose la fléchette ; un appui long ouvre la vue agrandie. Dans Radar, où l'effet dépend du point touché, la correction passe d'abord par un point sur la cible ; la liste de cases reste un raccourci (`GAMES.md` §15.4).
- iPhone : portrait pour jouer. iPad : paysage (cible à gauche) et portrait (cible en haut), mêmes composants.
