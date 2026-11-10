# VISION.md — Lecture du score par la caméra (cible `DartVision`)

Version 1.1 — 2026-11-10 — Statut : **normatif** pour la cible `DartVision`.

Ce document est la référence unique de la chaîne « caméra → score ». Trois conceptions indépendantes ont été comparées ; celle décrite ici les remplace. Le code de `DartVision` et ses tests sont écrits d'après ce fichier.

Changements de la version 1.1 (revue croisée des documents) : cycle de vie des commandes `arm`, `resume` et `confirmBoardEmpty` (6.3, 6.5) ; table normative du déclenchement manuel (6.3, 8.1) ; priorité entre fléchette tombée et retrait (6.3) ; sens de la correction de hauteur des fils (4.6) ; formule de la confiance regroupée (7.4) ; initialiseur public de `DartObservation`, répartition des types par fichier et membres de simple donnée (9.2 à 9.4) ; `SyntheticCamera.calibration(grade:)` (10.1) ; identifiants de tests révisés (10.2).

Précisions apportées après l'audit de la version 1.1 : `pause` et `resume` sont définis dans tous les états (ligne P2b, test S16) ; `captureNow` sans fléchette attendue est ignorée (ligne DM3, test S22) ; le réglage `endsTurnOnTakeout` de l'interface est nommé (6.4) ; `Photo/PhotoScorer.swift` et les tests P3 et P4 passent du lot V5 au lot V3 (9.3, 10.2, 12).

Corrections de la dernière relecture avant réalisation : `SyntheticCamera.exactHandles()` se calcule avec les seuls membres de simple donnée, sans appeler le lot V2 (9.2, 9.3, 10.1) ; `paused` porte la raison de la pause, et une pause de fin de partie ne se lève que par `arm` (6.3, lignes P1b et P2c ; tests S16 et S17) ; `DartObservation`, `ScanEvent`, `ScanCommand`, `SettleOutcome`, `ScanInput` et `ScanEffect` sont `Hashable`, pour que les tests les comparent par `==` (9.2, 9.4) ; les lots de la vision suivent la règle de noms d'un module partagé, et l'étiquette des suites lourdes est déclarée une seule fois (9.3, 10.2).

Précision apportée après la vérification de la fondation (lot F0) : `BoardGeometry.hit(at:)` est une fonction totale, qui rend `MISS` pour un point dont une coordonnée n'est pas finie au lieu de planter (9.1 ; `ARCHITECTURE.md` §4.2). Rien d'autre ne change dans ce document.

Précisions apportées à l'intégration de la vague 1 (lots V1 et V4 livrés), sans changement d'API publique :

- lot V1 : le seuil de l'inverse d'une homographie s'applique après équilibrage, sans quoi les vues réelles étaient refusées (4.2, 9.2) ; `Homography(from:to:)` refuse aussi quatre points dont trois sont alignés (4.2, M3) ; le repli de l'auto-calibrage sous 3° (4.2, M5) ; ce que « exact » veut dire en M11 ; taille d'image des poses C et D (10.2) ; occultation exacte des pièces d'une fléchette et chronologie de `SyntheticScript` (10.1) ;
- lot V4 : ce que le moteur fait seul, faute d'effet du réducteur (références et silhouettes, entrée `.armed`) ; les lignes DM1, DM2, A3, A13, A14 et K2 précisées là où le texte laissait deux lectures (6.3).

- Les identifiants, noms de paramètres et commentaires de code sont en anglais et font foi tels quels. L'API de la section 9 a été vérifiée par le compilateur (iOS 17 et macOS 14, mode Swift 5, contrôle de concurrence complet) avec des corps vides.
- « DOIT » / « NE DOIT PAS » marquent une exigence testable.
- Provenance des chiffres :
  - **[sonde]** : vérifié numériquement par un programme Swift jetable, sur image synthétique uniquement ;
  - **[art antérieur]** : valeur utilisée par un projet existant (dartVision, OpenDarts, DeepDarts, etc.) ;
  - **[estimation]** : valeur de départ jamais mesurée.
- **Aucune image réelle n'est passée dans cette chaîne.** Tous les seuils sont des valeurs de départ à régler sur des enregistrements faits sur une vraie cible (section 11).
- Les règles de jeu sont dans `GAMES.md`. `DartVision` ne touche jamais à l'état d'une partie : il **propose** des fléchettes, la couche jeu dispose.

## Sommaire

1. [Verdict](#1-verdict)
2. [Guide d'installation pour le joueur](#2-guide-dinstallation-pour-le-joueur)
3. [Repères et conventions](#3-repères-et-conventions)
4. [Calibrage](#4-calibrage)
5. [Détection : des pixels aux millimètres](#5-détection--des-pixels-aux-millimètres)
6. [Machine à états temporelle](#6-machine-à-états-temporelle)
7. [Confiance et correction](#7-confiance-et-correction)
8. [Mode photo](#8-mode-photo)
9. [API publique de `DartVision`](#9-api-publique-de-dartvision)
10. [Banc d'essai synthétique et tests](#10-banc-dessai-synthétique-et-tests)
11. [Limites connues et paramètres à régler](#11-limites-connues-et-paramètres-à-régler)
12. [Ordre de réalisation](#12-ordre-de-réalisation)
13. [Questions ouvertes pour le propriétaire](#13-questions-ouvertes-pour-le-propriétaire)

---

## 1. Verdict

### 1.1 Notes

Chaque conception est notée de 1 à 5 sur les quatre critères demandés.

| Critère | Conception 1 « robustesse » | Conception 2 « géométrie » | Conception 3 « parcours joueur » |
|---|---|---|---|
| (a) Chances de marcher sur une vraie cible, sans données d'entraînement | **4** : seule chaîne essayée de bout en bout en synthétique ; ses deux pièges (ombre alignée, tige noire sur secteur noir) ont été trouvés et corrigés | 3 : géométrie exacte, mais détecteur non essayé de bout en bout et beaucoup de pièces fragiles | 3,5 : chaîne raisonnable, non essayée de bout en bout |
| (b) Réalisable à la main en Swift | **5** : un solveur 8×8, pas de valeurs propres, pas de RANSAC | 2,5 : solveur de valeurs propres 3×3, RANSAC, ZNCC, Gauss-Newton 14×14, distorsion | 4 |
| (c) Testable sur macOS en synthétique | **5** : rendu direct dans l'espace redressé, étapes testables une à une | 3,5 : lanceur de rayons lourd, plusieurs pièces spéculatives | 4,5 : réducteur pur piloté par des entrées en conserve |
| (d) Expérience quand la détection est imparfaite | 3,5 : bandes de confiance et vérification à une fléchette, mais pas de candidats classés ni de localisation automatique | 4 : probabilité par segment, guide de placement, vue de preuve | **5** : trois paliers, candidats classés, image de preuve, regroupement selon le jeu, suivi de la confiance |

### 1.2 Ossature : la conception 1

La conception 1 est retenue comme ossature parce qu'elle garantit un socle qui ne dépend d'aucune automatisation :

- **quatre poignées** posées par le joueur sur des jonctions de fils, une homographie en forme close, et un affinage **gardé** qui est rejeté s'il ne prouve pas qu'il améliore ;
- **une seule image de travail**, la cible redressée vue de face à 2 px/mm, où tous les seuils sont en millimètres ;
- **une carte de preuve tolérante aux ombres**, un seuil, une droite robuste sur tous les pixels nouveaux ;
- **une confiance par fléchette** et une correction manuelle toujours disponible.

Deux résultats de sa sonde justifient ce choix : une différence d'images ordinaire place la pointe au bout de l'ombre quand l'ombre prolonge la fléchette (0 segment correct sur 40), et « prendre la plus grande composante » place la pointe sur l'empennage quand une tige noire passe sur un secteur noir (erreur médiane 52 mm). Les conceptions 2 et 3 prévoient des parades (étiquette d'ombre, fusion de fragments) mais ne les ont pas essayées de bout en bout.

### 1.3 Greffes

**De la conception 3 :**

- le **réducteur pur** `(état, entrée) → (état, effets)` séparé du moteur, testable sans image ;
- la **postérieure par segment** sur une grille 21×21, les **candidats classés**, les trois paliers et le **regroupement selon le jeu** (`tier(collapsingBy:)`) ;
- l'**image de preuve** (vrai recadrage redressé) et le déplacement de la pointe au doigt ;
- le **suivi de la confiance** (`TrustTracker`) et le plafond d'échauffement des trois premières fléchettes ;
- la **localisation automatique** simple (masque de couleur, ellipse, bull), ramenée au rôle de couche optionnelle qui ne fait que pré-placer les poignées ;
- les **rayons d'anneaux ajustés par cible**, le contrôle de dérive à chaque pose et l'échelle de recalage ;
- les commandes `discardDart` / `registerManualDart`, la distinction épisode « lancer » / épisode « main », la gestion thermique, le mode « Scanner la volée » comme repli automatique.

**De la conception 2 :**

- la **correction de calotte** : le bout visible d'une pointe cylindrique est à un rayon de la vraie entrée, du côté de la caméra [sonde] ;
- la **phase de rotation par la 10e harmonique** du rouge/vert (forme close) et l'idée de contrôles d'identité (« est-ce bien une cible ? ») ;
- le **terme de gradient** dans le seuil, simplifié en « garde d'arêtes » contre les tremblements sous-pixel ;
- le **changement de repère vers les coordonnées nominales**, qui laisse `DartCore` classer avec la géométrie standard ;
- la **compensation de la hauteur des fils** (couche optionnelle, désactivée par défaut) ;
- l'argument géométrique du placement **sous la cible**, la vue de preuve redressée et le test « toucher pour entendre le segment ».

### 1.4 Rejets

| Idée rejetée | Origine | Raison |
|---|---|---|
| Recalage par ancres ZNCC à chaque événement | 2 | Second mécanisme à maintenir ; la mesure d'arêtes sert déjà à l'affinage, à la qualité et à la dérive |
| Centre projeté par deux coniques concentriques (valeurs propres) | 2 | Exige un solveur de valeurs propres et un RANSAC pour une couche optionnelle ; l'affinage corrige de toute façon l'estimation plus simple « ellipse + bull » |
| Intersection de l'ombre et de l'axe ; extrapolation d'une pointe cachée par le rapport du fût | 2 | Suppositions présentées comme des mesures ; invérifiables sans ombres et fléchettes réelles |
| Distorsion radiale `k1`, gravité CoreMotion | 2 | Hors v1. La caméra 1x est déjà corrigée ; la gravité est remplacée par un paramètre `upDirection` que la couche de capture pourra alimenter plus tard |
| Détection sans référence (plateau modèle), `CompositeDetector` | 2, 3 | Phase 2 ; le protocole `DartDetecting` les permet sans changer l'API |
| Cases vides converties en « Manqué » au retrait ; tour clos par la caméra | 3 | Contraire à `GAMES.md` §2.4 : une fléchette non lancée n'existe pas, et seul `endTurn` passe au joueur suivant |
| Chaîne en Y/Cb/Cr 4:2:0 | 3 | Le modèle d'ombre retenu travaille en RGB et les images de test sont en RGB |
| Référence « plateau vide » enregistrée entre deux sessions | 3 | La lumière change d'une session à l'autre et l'application demande déjà de confirmer le plateau vide au lancement d'une partie |
| Table de redressement de 13 Mo ; confiance sur la seule frontière la plus proche | 1 | Remplacées par un calcul incrémental par ligne et par la postérieure par segment |
| Masque à hystérésis | 2 | La droite unique sur tous les pixels et la marche à `0,5·τ` couvrent déjà le fût sombre sur secteur sombre |

### 1.5 Socle garanti et couches optionnelles

Le socle fonctionne seul. Chaque couche a un interrupteur et un repli ; aucune n'est nécessaire pour jouer.

| Couche | Rôle | Interrupteur | Si elle échoue ou est coupée |
|---|---|---|---|
| **Socle** | 4 poignées + affinage gardé ; différence d'images dans le canevas ; correction manuelle | — | Saisie manuelle sur la cible virtuelle |
| Localisation automatique | Pré-place les poignées | passer un `BoardLocating` (ou `nil`) | Le joueur place les poignées |
| Rayons par cible | Absorbe les fils ronds et les cibles hors cotes | `fitRingRadii` | Rayons nominaux |
| Désambiguïsation par la pose | Vote « la pointe est du côté de la caméra » | `usePoseForTipEnd` | Profil de largeur seul |
| Recalage (dérive, choc du trépied) | Ré-affine le calibrage à chaque pose | `enableDriftCorrection` | Calibrage fixe ; `calibrationLost` puis saisie manuelle |
| Garde d'arêtes | Ignore les résidus de tremblement sur les fils | `edgeGuardPixels` (0 = coupé) | Ouverture 3×3 seule |
| Hauteur des fils | Corrige la parallaxe des fils en relief | `wireHeight` (0 = coupé, défaut) | — |
| Photo à main levée différenciée | Propose les pointes sur une paire de photos | `PhotoScorer.score` | Le joueur touche les pointes |
| Détecteur Core ML | Détecteur de remplacement ou d'appoint | protocole `DartDetecting` | Détecteur par différence |

---

## 2. Guide d'installation pour le joueur

### 2.1 Placement

Affiché comme une fiche illustrée, français d'abord.

| Élément | Consigne | Pourquoi |
|---|---|---|
| Support | Trépied ou support posé au sol, appareil branché. Jamais tenu en main pendant le scan | La différence d'images exige une vue fixe |
| Position | Objectif **40 à 60 cm sous le centre** de la cible (centre à 1,73 m du sol, donc objectif entre 1,13 et 1,33 m), centré ou décalé de 30 cm au plus. Variante admise : sur le côté, à hauteur du centre ou plus bas, à 40–60 cm de l'axe | Les fléchettes pendent queue vers le haut : vue d'en bas, l'inclinaison et la parallaxe s'ajoutent, la silhouette est longue et l'empennage ne couvre jamais la pointe. L'appareil reste hors de la trajectoire |
| Distance | 1,0 à 1,3 m du mur en 4K. Appareil limité au 1080p : 0,75 à 0,95 m | Donne au moins 1,5 px/mm [sonde : 2,1 à 2,5 px/mm en 4K à 1,1 m]. L'application mesure cette valeur, elle ne la suppose pas |
| Cadrage | Toute la cible, couronne des numéros comprise, plus de la marge du côté opposé à l'appareil (au-dessus de la cible si l'appareil est en bas). Portrait si l'appareil est sous la cible, paysage s'il est sur le côté | Les corps des fléchettes apparaissent décalés à l'opposé de l'appareil, jusqu'à 135 mm au-delà de la pointe [sonde] |
| Angle de vue | 20 à 30° par rapport à la normale de la cible (c'est la conséquence des lignes précédentes) | Sous 12° la fléchette est vue en bout. Au-delà de 40° chaque millimètre de pointe caché coûte plus de 0,8 mm |
| Objectif | Caméra arrière principale 1x. Jamais l'ultra grand-angle | Distorsion |
| À proscrire | Au-dessus de la cible ; de face depuis la ligne de tir | Au-dessus : les fléchettes masquent la vue et sont vues en bout. De face : aucune silhouette à mesurer et le lanceur masque la vue |

Exemple vérifié [sonde] : objectif 45 cm sous le centre, 15 cm sur le côté, à 1,10 m du mur. Angle de vue au centre 23°, 2,1 à 2,5 px/mm en 4K portrait, parallaxe de 0,28 à 0,59 mm par millimètre de pointe caché selon l'endroit de la cible.

### 2.2 Lumière et fléchettes

- Lumière **diffuse** ou anneau lumineux. Pas de spot unique : une ombre dure qui prolonge la fléchette est la pire nuisance (section 11).
- Pas de lampe dans le champ, pas de contre-jour.
- Pointes argentées de préférence. Une pointe noire sur un secteur noir est invisible pour une différence d'images.
- Ne plus toucher au trépied une fois le calibrage validé.

Messages : « Placez l'appareil sous la cible, à environ 1 m », « La cible entière doit être visible, avec de la marge au-dessus », « Retirez toutes les fléchettes », « Ne touchez plus au trépied ».

### 2.3 Ce que l'application mesure pendant l'installation

Dès que quatre poignées existent (posées par la localisation automatique ou par le joueur), l'application dessine le fil de fer de la cible sur l'aperçu et affiche **un** conseil à la fois, le plus utile d'abord. Les conditions exactes sont celles du grade de calibrage (section 4.7).

| `CalibrationIssue` | Condition | Message | Bloquant |
|---|---|---|---|
| `boardOutOfFrame` | le disque r ≤ 180 mm sort de l'image | « Cible coupée » | oui |
| `resolutionTooLow` | moins de 0,8 px/mm | « Beaucoup trop loin » | oui |
| `handlesMirrored`, `quadNotConvex`, `horizonCrossesBoard` | poignées incohérentes | « Replacez les repères dans l'ordre 20, 6, 3, 11 » | oui |
| `resolutionLow` | moins de 1,5 px/mm | « Rapprochez l'appareil » | non |
| `viewTooFrontal` | `minTanObliquity < 0,21` | « Baissez l'appareil ou décalez-le » | non |
| `viewTooOblique` | `maxTanObliquity > 0,84` | « Trop de biais : reculez ou recentrez » | non |
| `dartMarginCutOff` | moins de 90 % de la zone des fléchettes dans l'image | « Laissez de la marge au-dessus de la cible » | non |
| `sectorPhaseMismatch` | les secteurs clairs et sombres sont inversés | « Le 20 n'est pas au bon endroit : touchez le 20 » | non |
| `edgesNotFound`, `refinementRejected` | arêtes introuvables ou affinage refusé | « Ajustez les repères » ou « Lumière insuffisante » | non |
| `intrinsicsApproximate` | focale estimée | aucun message | non |

### 2.4 Configuration de capture (couche iOS, fichier `CameraFrameSource`)

- Caméra arrière `.builtInWideAngleCamera`. Préréglage `.hd4K3840x2160` s'il est disponible, sinon `.hd1920x1080`. 30 images/s fixes.
- Format `kCVPixelFormatType_32BGRA`. `alwaysDiscardsLateVideoFrames = true`.
- Stabilisation coupée, HDR coupé, correction de distorsion géométrique laissée active, livraison de la matrice intrinsèque activée quand elle est disponible.
- `videoRotationAngle` fixé **une fois** avant `startRunning()` ; l'orientation de l'interface est verrouillée pendant le scan. Un calibrage ne vaut que pour son `imageSize` et son `rotationDegrees`.
- À l'armement : 1,5 s de convergence automatique, puis verrouillage de la mise au point, de la balance des blancs et de l'exposition.
  - Durée d'exposition 1/100 s (secteur 50 Hz) ou 1/120 s (60 Hz), choisie d'après la région de l'appareil ; ISO recalculé pour garder la luminosité. Si l'ISO dépasse le maximum du format : 1/50 ou 1/60 s.
  - Vérification : si la luminosité moyenne de la porte ondule de plus de 1 % sur 30 images, essayer l'autre fréquence, puis émettre `advisory(.flicker)`.
- `DartUI` désactive la mise en veille. `ScanSession` observe `ProcessInfo.thermalState` : à `.serious` une image sur deux est traitée et `advisory(.thermalThrottling)` est émis ; à `.critical` la session envoie `pause(.thermal)` et l'interface propose le mode « Scanner la volée ».
- Tout ce qui précède est derrière `#if os(iOS)`. Sur macOS la même classe compile comme une simple source webcam. Dans le Simulateur (pas de caméra) l'application utilise `SyntheticFrameSource`.

---

## 3. Repères et conventions

### 3.1 Image (pixels)

- Origine en haut à gauche, `+x` vers la droite, `+y` vers le bas.
- Coordonnées continues ; **les valeurs entières tombent au centre des pixels**. Le pixel `(i, j)` couvre `[i − 0,5 ; i + 0,5] × [j − 0,5 ; j + 0,5]`.
- L'image est le tampon tel qu'il est livré après rotation (`rotationDegrees`), donc « à l'endroit » pour l'utilisateur.
- Type : `ImagePoint`. Point principal par défaut : `((W − 1)/2, (H − 1)/2)`.

### 3.2 Coordonnées normalisées

- `(u, v) ∈ [0, 1]²`, origine en haut à gauche, `v` vers le bas : `u = (x + 0,5)/W`, `v = (y + 0,5)/H`.
- Servent uniquement à la frontière avec `DartUI` (position d'un toucher dans l'aperçu, dessin du fil de fer). Les algorithmes travaillent en pixels.
- La normalisation de Hartley (centroïde à l'origine, distance moyenne √2) est interne à la DLT et n'apparaît nulle part ailleurs.

### 3.3 Cible (millimètres)

- Origine au centre du bull. **`+x` vers le 6** (à droite quand on regarde la cible), **`+y` vers le 20** (en haut), `+z` sort de la cible vers le joueur.
- Angle `α` mesuré **dans le sens horaire à partir de `+y`** : le 20 est à 0°, le 6 à 90°, le 3 à 180°, le 11 à 270°. `X = (r·sin α, r·cos α)` et `α = atan2(x, y)`.
- Index de secteur : `k = floor(((α + 9°) mod 360°) / 18°)` dans `[20, 1, 18, 4, 13, 6, 10, 15, 2, 17, 3, 19, 7, 16, 8, 11, 14, 9, 12, 5]`.
- Fil radial `m` (0 à 19) : `α_m = 9° + 18°·m`. Distance signée d'un point au fil `m` : `x·cos α_m − y·sin α_m`.
- Couleurs : `k` pair = simple noir, double et triple rouges (le 20 est noir et rouge) ; `k` impair = simple crème, double et triple verts.
- Rayons nominaux depuis le centre : bull intérieur 6,35 ; bull extérieur 15,9 ; triple 99 à 107 ; double 162 à 170 ; diamètre hors tout 451.
- **Deux variantes du même repère** :
  - coordonnées **métriques** : millimètres réels de cette cible ; ce sont celles du canevas et de l'homographie ;
  - coordonnées **nominales** : les mêmes, après la correction de hauteur des fils quand cette couche est active (C6, section 4.6), puis un étirement radial qui amène les rayons mesurés de cette cible sur les rayons nominaux (`RingRadii.toNominal`). **Tout point qui sort de l'API publique est en coordonnées nominales**, pour que `DartCore` classe avec sa géométrie standard. Sans ajustement des rayons et sans hauteur de fils, les deux coïncident.

[sonde] Ces conventions donnent bien 20 en haut, 6 à droite, 3 en bas, 11 à gauche, et les frontières 20/1 à 9° et 5/20 à 351°.

### 3.4 Canevas (cible redressée)

- Image carrée de côté `N = 1280` px, échelle `s = 2` px/mm, demi-étendue `E = 320` mm, bull au centre. Ce sont des constantes (`BoardCanvas`), pas des réglages.
- Le pixel `(i, j)` correspond au point métrique `x = −E + (i + 0,5)/s`, `y = E − (j + 0,5)/s`. Le 20 est en haut.

### 3.5 Homographie

- `H` va de la cible (mm métriques) vers l'image (px) : `(a, b, w)ᵀ = H·(x, y, 1)ᵀ`, `u = a/w`, `v = b/w`.
- `G = H⁻¹` va de l'image vers la cible.
- Une vue physique (non inversée) a un jacobien de déterminant **négatif**, car `y` monte sur la cible et descend dans l'image [sonde].

### 3.6 Caméra

- Repère caméra : `x` à droite, `y` en bas, `z` vers l'avant. `K = [[fx, 0, cx], [0, fy, cy], [0, 0, 1]]`.
- `C` : centre optique dans le repère de la cible. **Pied de la caméra** `F = (C.x, C.y)` ; **distance** `D = C.z > 0`.
- `tan θ(X) = ‖X − F‖ / D` : millimètres d'erreur sur la cible par millimètre de hauteur au point `X`.

---

## 4. Calibrage

### 4.1 Entrées et sorties

**Entrées**

- Une image figée de la cible, de préférence vide : moyenne de 8 images après le verrouillage de l'exposition (`ScanSession.captureStill`).
- Quatre poignées en pixels image, sur les jonctions du **fil extérieur du double** avec les fils radiaux **20/1, 6/10, 3/19 et 11/14**. En millimètres (r = 170, α = 9°, 99°, 189°, 279°) : `(26,59 ; 167,91)`, `(167,91 ; −26,59)`, `(−26,59 ; −167,91)`, `(−167,91 ; 26,59)`.
- Les intrinsèques si la source les fournit.

**Sortie** : `BoardCalibration` (poignées du joueur, poignées affinées, `H`, `G`, rayons, intrinsèques, pose, qualité).

**Étapes**

| Étape | Rôle | Couche |
|---|---|---|
| L1–L8 | Localisation automatique : poignées initiales | optionnelle |
| C1 | Homographie en forme close et garde de cohérence | socle |
| C2 | Mesure des arêtes | socle |
| C3 | Affinage gardé | socle |
| C4 | Rayons d'anneaux de cette cible | optionnelle (`fitRingRadii`) |
| C5 | Contrôle de phase des secteurs | socle |
| C6 | Hauteur des fils | optionnelle (`wireHeight`) |
| C7 | Intrinsèques et pose | socle |
| C8 | Grade de qualité | socle |

### 4.2 Outils mathématiques

**Homographie par 4 points (Heckbert).** Du carré unité `(0,0), (1,0), (1,1), (0,1)` vers le quadrilatère `p0..p3` :

```
dx1 = x1 − x2    dx2 = x3 − x2    sx = x0 − x1 + x2 − x3      (idem pour y)
den = dx1·dy2 − dy1·dx2
g = (sx·dy2 − sy·dx2) / den        h = (dx1·sy − dy1·sx) / den
S = [[x1 − x0 + g·x1,  x3 − x0 + h·x3,  x0],
     [y1 − y0 + g·y1,  y3 − y0 + h·y3,  y0],
     [g,               h,               1 ]]
H = S(dst) · S(src)⁻¹
```

[sonde] Exact à 1,4e-12 px contre la projection vraie.

**Homographie par N ≥ 4 points (DLT normalisée).**

1. Normaliser chaque jeu de points : `T = [[σ, 0, −σ·cx], [0, σ, −σ·cy], [0, 0, 1]]`, `c` le centroïde, `σ = √2 / moyenne‖p − c‖`.
2. Chaque paire normalisée `(X, Y) → (u, v)` donne deux lignes, avec `h33 = 1` :
   ```
   [X Y 1 0 0 0 −uX −uY] · h = u
   [0 0 0 X Y 1 −vX −vY] · h = v
   ```
3. Résoudre les équations normales 8×8 par élimination de Gauss à pivot partiel. Pivot inférieur à 1e-12 : entrée dégénérée, retour `nil`. Ce test ne suffit pas pour quatre points dont trois sont alignés (le système a alors une solution unique, mais singulière) : les points normalisés sont d'abord contrôlés en position générale (aucun triplet aligné parmi quatre), et le résultat doit être inversible ; sinon `nil`.
4. `H = T_image⁻¹ · Ĥ · T_cible`, mise à l'échelle pour `h33 = 1`.

Pour N = 4 la DLT est exacte et sert de contre-épreuve à la forme close dans les tests.

**Inverse.** `G = adj(H)/det(H)`. Rejet si `|det| < 1e-9` après **équilibrage** de `H` : chaque colonne, puis chaque ligne, ramenée à la longueur 1. Une seule mise à l'échelle globale (norme de Frobenius 1) ne convient pas : une homographie cible → image mêle millimètres, pixels et ligne de perspective, et son déterminant ainsi normalisé vaut 5e-10 pour la pose A de 10.2, une vue parfaitement régulière. L'équilibrage ne dépend pas des unités ; une matrice singulière est toujours refusée.

**Échelle locale.** Avec `(a, b, w) = H·(x, y, 1)` :

```
J = (1/w) · [[h11 − u·h31,  h12 − u·h32],
             [h21 − v·h31,  h22 − v·h32]]
```

Les valeurs singulières de `J` sont `√λ±`, où `λ± = (tr ± √(tr² − 4·det)) / 2` pour `JᵀJ`. La plus petite est l'échelle en px/mm dans la pire direction.

**Intrinsèques**, dans l'ordre de préférence :

1. matrice livrée avec le tampon (iOS) ;
2. `f = (max(W, H)/2) / tan(FOV/2)` avec le champ du format actif, mesuré sur le **grand côté** ; point principal au centre ;
3. auto-calibrage sur un plan (Zhang), point principal ramené à l'origine : `H̃ = T·H` avec `T = [[1, 0, −cx], [0, 1, −cy], [0, 0, 1]]`, puis
   `f² = −(h̃11·h̃12 + h̃21·h̃22) / (h̃31·h̃32)` ou `f² = (h̃11² + h̃21² − h̃12² − h̃22²) / (h̃32² − h̃31²)`.
   Prendre la forme au plus grand dénominateur ; accepter si `f ∈ [0,5 ; 3]·max(W, H)`. Les deux dénominateurs s'annulent quand l'axe optique est perpendiculaire à la cible : sous 3° d'inclinaison (mesurée sans unité par le sin² de l'inclinaison), l'auto-calibrage rend `nil` et le repli 4 s'applique ; de 3° à 10° l'estimation est rendue (exacte sur des données exactes) ;
4. repli : champ de 67° sur le grand côté.

Les cas 3 et 4 donnent une pose « approximative ». Seuls `F` et `tan θ` servent en aval ; une erreur de focale de 10 à 20 % est tolérable. [sonde] Les deux formes de Zhang retrouvent la focale exactement sans bruit.

**Pose depuis `H` et `K`.**

```
B = K⁻¹·H = [b1 b2 b3]
λ = ±2 / (‖b1‖ + ‖b2‖), signe tel que (λ·b3).z > 0
r1 = normaliser(λ·b1)
r2 = normaliser(λ·b2 − (r1·λb2)·r1)
r3 = r1 × r2        R = [r1 r2 r3]        t = λ·b3
C = −Rᵀ·t           F = (C.x, C.y)        D = C.z
```

`D ≤ 0` signifie des poignées en miroir. [sonde] Centre optique retrouvé à 3e-12 mm.

**Parallaxe.** Un point à la hauteur `s` au-dessus du point `X` de la cible apparaît, à travers `G`, en

```
X' = X + (X − F) · s / (D − s)
```

[sonde] Exact à 5e-13 mm. Deux conséquences qui gouvernent la détection :

- tout ce qui est au-dessus de la cible est repoussé **à l'opposé de `F`** ; le point d'entrée d'une fléchette (hauteur 0) n'a aucun biais, quelle que soit son inclinaison ;
- chaque millimètre de pointe non vu coûte `tan θ(X)` millimètres.

### 4.3 Localisation automatique (couche optionnelle, `ColourBoardLocator`)

Elle ne produit que des **poignées initiales**. Le calibrage se poursuit ensuite exactement comme avec des poignées posées à la main (C1 à C8), et le joueur valide toujours le fil de fer.

- **L1. Masque de couleur.** Image de travail : moyenne par blocs pour un grand côté de 640 px. Par pixel : `mx = max(R, G, B)`, `mn = min(R, G, B)`, `sat = (mx − mn)/max(mx, 1)`, `o = (R − G)/(R + G + B + 1)`. Un pixel est « coloré » si `mx ≥ 48` et `sat ≥ Ts`, où `Ts` est le seuil d'Otsu de `sat`, borné à `[0,30 ; 0,55]`. Fermeture 3×3.
- **L2. Bord extérieur du double.** Composantes connexes du masque. Garder celles dont la boîte englobante fait au moins 12 % du petit côté de l'image et dont le rapport d'aspect est dans `[0,45 ; 2,2]` ; essayer au plus les 4 plus grandes. Depuis le centre de la boîte, lancer 360 rayons ; sur chacun garder le pixel coloré le plus éloigné appartenant à une suite d'au moins 3.
- **L3. Ellipse.** Ajustement linéaire de la conique avec la normalisation `A + C = 1` : après normalisation des points, résoudre par élimination de Gauss les équations normales 5×5 de `A(x² − y²) + B·xy + D·x + E·y + F = −y²`. Exiger `B² − 4AC < 0`. Écarter les points dont la distance de Sampson `|pᵀQp| / (2·‖(Qp)xy‖)` dépasse 1,5 px et réajuster, deux fois. Exiger au moins 60 % des rayons conservés et un rapport d'axes d'au moins 0,45.
- **L4. Bull.** La composante colorée la plus proche du centre de l'ellipse dont l'aire vaut 0,4 à 2,5 fois l'aire attendue du bull extérieur, soit `(15,9/170)²` fois l'aire de l'ellipse. Son centroïde est l'image `c` du centre de la cible. **Ne jamais utiliser le centre de l'ellipse** : il est à 23 px du centre projeté dans la pose d'exemple [sonde].
- **L5. Homographie à une rotation près.** Avec la conique `Q` et `c` en coordonnées homogènes :
  ```
  l  = Q·c                                  (ligne de fuite du plan)
  A, B = intersections de Q avec la droite horizontale passant par c
  V1 = (A × B) × l
  V2 = l × (Q·V1)
  D, E = intersections de Q avec la droite c–V2
  ```
  Les intersections d'une droite `p + τ·d` avec `Q` sont les racines de `τ²·dᵀQd + 2τ·dᵀQp + pᵀQp = 0`. Envoyer `(170, 0), (0, 170), (−170, 0), (0, −170)` sur `A, D, B, E` par la formule à 4 points. Si le déterminant du jacobien à l'origine est positif, échanger `D` et `E`. Résultat : `H0`. [sonde] `H0⁻¹·H` est une rotation pure à 3e-13 mm.
- **L6. Contrôle de structure.** À travers `H0`, au moins 70 % des échantillons à r = 166 et r = 103 doivent être colorés et au moins 80 % des échantillons à r = 60 et r = 135 ne doivent pas l'être. Sinon : pas de cible.
- **L7. Phase des fils.** Échantillonner `o` à travers `H0` aux points `(r·sin φ_j, r·cos φ_j)` du repère provisoire, pour 720 angles `φ_j`, sur r = 166 puis sur r = 103. `s_j = o_j − médiane(o)`, `z = Σ s_j·e^(−i·10·φ_j)`, **`β = −arg(z)/10 (mod 36°)`**. Exiger un contraste `|z| / Σ|s_j| ≥ 0,35` sur chaque anneau (0,64 pour un créneau parfait) et deux phases à moins de 3° l'une de l'autre. Les candidats sont `H_k = H0·Rot(β + 36°·k)`, k = 0 à 9, avec
  ```
  Rot(β) = [[cos β, sin β, 0], [−sin β, cos β, 0], [0, 0, 1]]      (Homography.boardRotation)
  ```
  [sonde] Phase retrouvée à 0,13° près ; le candidat choisi est à moins de 1 px de la vraie homographie.
- **L8. Orientation.** Choisir le candidat dont la direction `+y` de la cible, `J(0, 0)·(0, 1)`, est la plus proche de `upDirection` (par défaut le haut de l'image). Une cible est toujours accrochée 20 en haut et l'appareil est sur un support : c'est juste tant que l'appareil n'est pas incliné de plus de 18°. Les poignées sont `H_k·(points des jonctions)`, ramenées à la résolution d'origine par `x = (x_travail + 0,5)·facteur − 0,5`. Les neuf autres orientations sont rendues dans `alternatives` ; si les numéros affichés sont faux, le joueur touche le vrai 20 (`reoriented(twentyAt:parityPreserving:)`).

[sonde] Avec 1,5 px de bruit sur les points du bord et sur le bull (pleine résolution, 200 essais), L3 à L5 laissent sur le fil du double une erreur radiale maximale de 0,13 mm en moyenne et de 0,28 mm dans le pire essai, bien à l'intérieur de la fenêtre de ±4 mm de l'affinage. Sur une image de travail à 0,4 px/mm la conception 3 mesure 1,2 à 1,8 mm au 95e centile.

### 4.4 C1 — Homographie en forme close et garde de cohérence

Calculée à chaque déplacement de poignée (quelques microsecondes) ; elle alimente le fil de fer en direct. L'interface offre une loupe 4x au-dessus du doigt, le déplacement et le pincement du fil de fer entier. Les poignées partent du calibrage précédent, de la localisation automatique, ou d'un cercle de rayon `0,3·min(W, H)` au centre.

Garde ; tout échec désactive « Valider » avec un message précis :

- somme du lacet `Σ(x_i·y_(i+1) − x_(i+1)·y_i) > 0` sur les poignées dans l'ordre (sens horaire à l'écran [sonde]) ; sinon `handlesMirrored` ;
- quadrilatère convexe ; sinon `quadNotConvex` ;
- `w` garde le même signe pour tous les points de la cible avec r ≤ 230 ; sinon `horizonCrossesBoard` ;
- le disque r ≤ 180 est dans l'image ; sinon `boardOutOfFrame` ;
- échelle dans la pire direction, au bull et en 8 points de r = 170, d'au moins 0,8 px/mm ; sinon `resolutionTooLow`.

### 4.5 C2 — Mesure des arêtes

Un seul mécanisme sert à l'affinage, au chiffre de qualité et au contrôle de dérive.

- **Jeu d'échantillons (388) :**
  - anneaux `R ∈ {170, 162, 107, 99}` aux angles `α = 18°·k ± 4,5°` (40 chacun) ; `R = 15,9` à 16 angles ; `R = 6,35` à 12 angles. Normale radiale ;
  - fils `m = 0…19` aux rayons `{35, 55, 75, 90, 103, 116, 130, 144, 155, 166}` mm. Normale tangentielle.
- Pour chaque échantillon de position `X0` et de normale `n̂` : lire le RGB en bilinéaire à `H·(X0 + j·δ·n̂)`, `δ = 0,25` mm, `j = −16…16` (fenêtre de ±4 mm).
- Énergie de gradient de couleur `g_j = ‖c_(j+2) − c_(j−2)‖₂` pour `|j| ≤ 14`. Elle est **non signée** exprès : toute frontière d'anneau ou de fil est un changement de couleur dans au moins un canal.
- Pic `j* = argmax g`. Accepté si `g_(j*) ≥ 20` et `g_(j*) ≥ 2,5·médiane(g)`.
- Décalage `o` = centroïde de `j·δ` pondéré par l'énergie sur `|j − j*| ≤ 4`. Le centroïde se centre sur un fil qui montre deux flancs.
- Observation `q = H·(X0 + o·n̂)` en pixels image.

### 4.6 C3 à C6 — Affinage gardé

**C3. Affinage paramétré par les poignées.** Les 8 inconnues sont les positions `u` des 4 poignées ; `H(u)` est la forme close de C1. Le problème reste en pixels, la région de confiance est évidente et l'interface peut montrer les poignées qui s'aimantent.

- Résidus en mm, avec `(x, y) = G(u)·q_i` :
  - échantillon d'anneau : `√(x² + y²) − R_i` ;
  - échantillon de fil : `x·cos α_m − y·sin α_m` ;
  - rappel vers les poignées du joueur : `0,3·(u_k − u_k^joueur)/ρ`, `ρ` = px/mm au bull.
- Poids de Huber, `k = 0,75` mm ; poids nul au-delà de 3 mm.
- Jacobien par différences avant, pas de 0,25 px. Résoudre `(JᵀWJ + λ·diag(JᵀWJ))·δ = −JᵀW·r` (8×8, `λ = 1e-3`). Six itérations, ou arrêt quand `‖δ‖∞ < 0,01` px.
- Deux passes : mesurer, résoudre, re-mesurer avec une fenêtre de ±2 mm, résoudre.
- **Garde d'acceptation.** Les poignées affinées ne sont gardées que si : au moins 50 % des échantillons sont mesurés ; au moins 60 % de ceux-ci sont à moins de 1,0 mm ; la RMS des conformes est ≤ 0,5 mm ; aucune poignée n'a bougé de plus de l'équivalent de 4 mm. Sinon on garde les poignées du joueur et on signale `refinementRejected`.

[sonde, conception 1] 300 essais à 1,17 px/mm, erreur sur toute la cible :

| Bruit des poignées | Bruit des arêtes | Aberrants | RMS avant → après | p95 avant → après |
|---|---|---|---|---|
| σ = 1 px | 0,5 px | 0 % | 0,83 → 0,07 mm | 1,38 → 0,13 mm |
| σ = 2 px | 0,5 px | 0 % | 1,66 → 0,07 mm | 2,75 → 0,13 mm |
| σ = 3 px | 0,7 px | 0 % | 2,50 → 0,10 mm | 4,13 → 0,18 mm |
| σ = 2 px | 0,7 px | 15 % | 1,75 → 0,12 mm | 2,87 → 0,22 mm |

Ces chiffres supposent que la recherche trouve les vraies arêtes. Une vraie cible fera moins bien (les fils ne sont pas exactement sur les limites de couleur imprimées) ; c'est la raison d'être de la garde et du fil de fer.

**C4. Rayons de cette cible** (`fitRingRadii`, actif par défaut). Les fils ronds (1,2 à 1,6 mm) et certaines cibles déplacent les frontières de 1 à 2 mm par rapport aux cotes nominales.

- Après convergence de C3, pour chacun des cinq rayons autres que 170 : `R_k :=` médiane de `‖G·q‖` sur les échantillons conformes de cet anneau, bornée à nominal ±2 mm (±1 mm pour les deux bulls).
- Le rayon extérieur du double reste à 170,0 : c'est la jauge d'échelle, et c'est le rayon des poignées.
- Deux itérations de C3 de plus avec ces rayons. Un rayon n'est conservé que si au moins 60 % des échantillons de son anneau sont conformes ; sinon il revient au nominal.
- `RingRadii.toNominal` : étirement radial linéaire par morceaux, de nœuds `(0, 0)`, `(R̂_bull int., 6,35)`, `(R̂_bull ext., 15,9)`, `(R̂_triple int., 99)`, `(R̂_triple ext., 107)`, `(R̂_double int., 162)`, `(170, 170)` ; identité au-delà de 170.

**C5. Contrôle de phase des secteurs.** Luminance moyenne des simples à r = 130 mm : les secteurs impairs (crème) doivent être plus clairs que les pairs (noirs) d'au moins 25 niveaux. Sinon le fil de fer est tourné d'un nombre impair de secteurs : `sectorPhaseMismatch`. Une rotation de deux secteurs n'est pas détectable automatiquement ; le fil de fer affiche donc 20, 6, 3 et 11 près des poignées pour que le joueur compare avec les vrais numéros.

**C6. Hauteur des fils** (`wireHeight`, 0 par défaut = coupé). Les fils dépassent du sisal d'environ 0,7 mm ; l'affinage cale donc `H` et `G` sur le **plan des fils**, à la hauteur `s = wireHeight` au-dessus de la surface où entrent les pointes. Une pointe qui entre dans le sisal au point `X` est vue à travers `G` en `G(p) = F + (X − F)·D/(D + s)` : **plus près de `F`** que `X`, de `s·tan θ(X)` (c'est la formule de parallaxe de la section 4.2 pour une hauteur de `−s`). La correction éloigne donc le point de `F` ; c'est une homothétie de centre `F` et de rapport supérieur à 1 :

```
G'(p) = F + (G(p) − F)·(D + s)/D          soit  pose.removingParallax(from: G(p), height: −s)
```

- `F` et `D` sont ceux de la pose (C7). Elle est calculée depuis `H` : `D` est donc la distance de la caméra au plan des fils. Avec `D_s = D + s`, la distance de la caméra au sisal, le même rapport s'écrit `D_s/(D_s − s)`.
- Effet : `s·tan θ`, soit 0,2 à 0,5 mm selon l'endroit pour des fils de 0,7 mm. [sonde] En pose A avec `s = 0,7` : sans correction, décalage de 0,20 à 0,41 mm vers `F` ; avec, résidu inférieur à 1e-12 mm. Le rapport inverse `(D − s)/D` double l'erreur (0,82 mm au pire).
- La correction ne modifie ni `H`, ni `G`, ni le canevas, ni le fil de fer, ni la mesure des arêtes : tous restent sur le plan des fils. Elle intervient à un seul moment, quand un point métrique devient un point nominal, juste avant `ringRadii.toNominal` : dans `BoardCalibration.boardPoint(for:)` (donc dans `hit(at:board:)`), en sens inverse dans `imagePoint(for:)`, et à la sortie du détecteur (D10).
- Le calibrage porte sa hauteur de fils : `preview` et `calibrate` recopient `CalibrationParameters.wireHeight` dans `BoardCalibration.wireHeight` ; `recover` garde celle du calibrage qu'il affine.
- À n'activer qu'après mesure sur une vraie cible.

### 4.7 C7, C8 — Pose, qualité, et ce que voit le joueur

**C7.** Calculer `K`, la pose, `F` et `D` (section 4.2).

**C8. Grade.**

| Grade | Condition | Comportement |
|---|---|---|
| `good` | affinage accepté, RMS des arêtes ≤ 0,35 mm, au moins 1,5 px/mm, `minTanObliquity ≥ 0,21`, `maxTanObliquity ≤ 0,84` | Pastille verte « Calibrage précis » |
| `fair` | affinage accepté, RMS ≤ 0,7 mm, au moins 1,2 px/mm, `minTanObliquity ≥ 0,16`, `maxTanObliquity ≤ 1,2` | Pastille orange avec le conseil ; confiance × 0,9 |
| `poor` | tout le reste qui passe C1 | Pastille rouge ; le scan reste possible mais toute fléchette est « à vérifier » (confiance plafonnée à 0,80) |

- `minTanObliquity = (‖F‖ − 170)/D` : en dessous de 0,16 (9°) une fléchette perpendiculaire proche de la caméra est vue en bout et son propre empennage cache sa pointe.
- `maxTanObliquity = (‖F‖ + 170)/D` : coût maximal d'un millimètre de pointe caché.

**Ce que voit le joueur :**

1. le fil de fer (6 anneaux, 20 fils, 4 numéros) sur l'image figée, puis sur la vidéo en direct après « Valider » ;
2. la loupe ;
3. la pastille, avec « Précision estimée ± x mm » (`estimatedAccuracy`) et **un** conseil ;
4. une **vue de preuve** : la cible redressée (`BoardRectifier`) avec le fil de fer idéal par-dessus, où un défaut d'alignement saute aux yeux ;
5. un **test au toucher** : toucher l'aperçu annonce le segment sous le doigt (`BoardCalibration.hit(at:board:)`).

### 4.8 Vérification à une fléchette (facultative, environ 10 secondes, recommandée)

Le joueur plante une fléchette n'importe où puis touche sa pointe dans la loupe. L'application (`ScanEngine.runLightingCheck`) :

1. compare la pointe détectée au toucher. À moins de 2 mm : « Détection vérifiée » ;
2. mesure la profondeur des ombres : 5e centile du rapport de luminosité `α*` sur les pixels modifiés qui sont hors du couloir de la fléchette et dont la couleur n'a pas changé ;
3. fixe la borne basse du modèle d'ombre une fois pour toutes : `shadowLowerBound = clamp(q05 − 0,08 ; 0,2 ; 0,5)` ; 0,5 s'il y a moins de 50 pixels d'ombre ; puis refait l'étape 1 ;
4. en cas d'échec, nomme la cause : ombre trop dure, pointe invisible, vue trop frontale.

Cette étape valide toute la chaîne avec les fléchettes et la lumière du joueur. Si elle est sautée, `shadowLowerBound = 0,40` et les **trois premières fléchettes** après le calibrage sont plafonnées au palier moyen (`warmUpDarts`), ce qui revient à faire vérifier le calibrage sur de vraies fléchettes.

Pour cette vérification, l'interface arme la vision (`arm`) le temps de voir la fléchette, puis l'arrête par `pause(.user)` à la fermeture du calibrage (`ARCHITECTURE.md` §8.7). La machine ne surveille donc pas la cible entre le calibrage et la première partie, et seul le `arm` de cette partie la relance (section 6.3, ligne P2c).

### 4.9 Dérive et recalage (couche optionnelle `enableDriftCorrection`)

`BoardCalibrator.assess` refait C2 avec le calibrage courant et rend la médiane des résidus absolus et la fraction de conformes.

| Statut | Condition | Suite |
|---|---|---|
| `healthy` | médiane ≤ 0,5 mm et conformes ≥ 0,6 (≥ 0,5 avec des fléchettes sur la cible) | rien |
| `drifted` | pas sain, mais `recover` (C3 depuis les poignées courantes, borne de 6 mm) passe la garde | adopter le nouveau calibrage, émettre `calibrationAdjusted` |
| `lost` | ni l'un ni l'autre | localisation automatique si elle est fournie, sinon `calibrationLost` |
| `edgesNotVisible` | moins de 30 % d'échantillons mesurables (main, obscurité, cible aux couleurs inhabituelles) | continuer avec le calibrage courant |

- Le contrôle a lieu sur la 2e image calme de chaque épisode, **avant** l'accumulation (section 6.3, ligne 5), à chaque nouvelle référence vide, et après 2 s d'obstruction immobile. En déclenchement manuel, il a lieu de la même façon à chaque pose de capture.
- **Les références survivent à un recalage** : elles sont dans l'espace de la cible et le plan de la cible se recale exactement par la nouvelle `H`. Deux précautions : les silhouettes des fléchettes déjà plantées sont dilatées de 3 mm de plus (leur parallaxe a changé) et les fléchettes de cet événement portent `afterRelock`. Si le centre optique a bougé de plus de 30 mm, la référence courante est reprise sur l'image posée et aucune fléchette n'est cherchée dans cet événement.
- Après `calibrationLost`, la partie continue en saisie manuelle ; le moteur retente un recalage à chaque seconde calme.

### 4.10 Persistance

- `BoardCalibration` est `Codable` (JSON). L'application l'enregistre par couple (caméra, `rotationDegrees`, `imageSize`).
- Au lancement suivant : une image figée, puis `assess`. Sain : le calibrage est repris tel quel (retour en quelques secondes). Dérivé : `recover`. Sinon : écran de calibrage avec les poignées pré-placées aux anciennes positions.
- La borne d'ombre issue de la vérification à une fléchette est enregistrée avec le calibrage, dans `VisionConfiguration` (lui aussi `Codable`).
- Les références d'image (`R`, `E`) ne sont **pas** enregistrées : elles sont reprises à chaque armement, après que le joueur a confirmé que le plateau est vide (`GAMES.md` §2.4).

---

## 5. Détection : des pixels aux millimètres

La détection tourne **une fois par événement « la scène est redevenue immobile »**, jamais à chaque image. Hypothèse du mode direct : **une fléchette nouvelle par événement**.

### 5.1 Données et tailles

| Objet | Type | Taille |
|---|---|---|
| Image source | `Frame` (BGRA8, sans copie) | 3840×2160 ou 1920×1080 |
| Image de porte | `GrayImage` (canal vert moyenné par blocs) | grand côté ≤ 320 px |
| Accumulateur | `FrameAccumulator` (3 × UInt16 par pixel) | 1280×1280 |
| Canevas `S`, `R`, `E` | `CanvasImage` (RGB8 + masque de validité) | 1280×1280, 6,5 Mo chacun |
| Carte de preuve `e` | `GrayImage` | 1280×1280 |
| Masque | `GrayImage` 0/255, puis `CanvasMask` (plages) | — |
| Étiquettes | `[Int32]` | 1280×1280 |
| Résultat | `SceneAnalysis` contenant des `DartCandidate` | — |

- `R` : **référence courante** (cible plus fléchettes déjà comptées). `E` : **référence vide** (cible au début de la volée). `S` : image posée courante.
- Mémoire totale : environ 40 Mo.
- Le cœur n'utilise que des tableaux Swift et des boucles écrites à la main : ni Vision, ni Core Image, ni Accelerate. Les tests sont ainsi identiques au bit près d'une exécution à l'autre.

### 5.2 Étapes

**Entrées** (`DetectionRequest`) : `S`, `R`, `E` (ou `nil` si elle est périmée), les silhouettes des fléchettes connues, le calibrage (donc `F` et `D`), le bruit `σ̂`, `maxNewDarts`, les paramètres.

#### D1. Redressement — `Frame` → `CanvasImage`

- Pour chaque pixel du canevas dans la région d'intérêt : point métrique, `p = H·(x, y, 1)`, lecture bilinéaire. Le long d'une ligne les trois coordonnées homogènes sont affines : 3 additions et 1 inverse par pixel, sans table.
- **Région d'intérêt** : le point `q` en fait partie si `‖q‖ ≤ 190` mm, ou si le segment `{q − λ·unité(q − F), 0 ≤ λ ≤ 135 mm}` passe à moins de 175 mm du centre. C'est la cible plus la zone où les corps des fléchettes peuvent apparaître. Avec une pose approximative : le disque `‖q‖ ≤ 320`.
- Un pixel dont la source tombe hors de l'image est invalide. Si l'échelle source dépasse 3 px/mm, moyenner 4 lectures à ±0,25 px de canevas.
- Les 4 images calmes n° 3 à 6 sont redressées et moyennées (`FrameAccumulator`).

*Pourquoi redresser d'abord :* aires, largeurs et écarts deviennent des constantes en millimètres ; la pointe sort directement en millimètres ; les références restent valables après un recalage ; deux photos prises de deux endroits s'alignent sur le plan de la cible ; un futur modèle Core ML reçoit une entrée normalisée.

#### D2. Carte de preuve tolérante aux ombres — (`R`, `S`) → `e`, `g`

1. Flou boîte 3×3 sur `R` et `S` (le flou de `R` est mis en cache).
2. Par pixel, avec la couleur de référence `r` et la couleur courante `c` vues comme vecteurs RGB : `α* = (c·r) / (r·r + 1)`.
3. Gain global `g` = médiane de `α*` sur une grille de pas 16 px à l'intérieur de r ≤ 170 mm, là où `‖r‖ ≥ 60`, hors silhouettes.
4. **Preuve** `e = ‖c − clamp(α*, α_lo·g, α_hi·g)·r‖₂`, bornée à 255.

`e` est la distance entre la nouvelle couleur et le segment « même couleur, plus sombre », c'est-à-dire une ombre. Défauts : `α_lo = shadowLowerBound = 0,40`, `α_hi = shadowUpperBound = 1,08`. Un pur changement de luminosité dans la bande vaut environ 0 ; un changement de couleur ou un éclaircissement vaut sa distance entière.

Sortie annexe : `changedBoardFraction`, la fraction du disque r ≤ 170 où `‖c − g·r‖ ≥ τ`.

*Pourquoi pas une différence ordinaire :* caméra en bas et lumière en haut, l'ombre prolonge la fléchette au-delà de la pointe, vers `F`. [sonde] Différence ordinaire avec une ombre à 0,65 : 0 segment correct sur 40, parfois avec une confiance haute. Avec ce modèle : 100 % des fléchettes à confiance haute sont correctes.

#### D3. Masque — `e` → masque binaire

- `τ = max(18, 6·σ̂)` en unités RGB L2 sur 8 bits. `σ̂` est mesuré à l'armement : `médiane|a − b| / 0,954` entre deux images consécutives.
- **Garde d'arêtes** : `e' = e − edgeGuardPixels·‖∇R‖`, où `‖∇R‖` est le plus grand gradient (différences centrées, en niveaux par pixel) des trois canaux de `R` flouté. C'est la différence que produit un décalage de `edgeGuardPixels` (0,25 px) sur un fil ou une limite de couleur. La garde ne s'applique qu'au masque, jamais à la marche vers la pointe (D8).
- `masque = (e' ≥ τ)`, effacé sur les pixels invalides et à l'intérieur des silhouettes connues dilatées de 2 mm.
- Ouverture 3×3 (retire les résidus d'arête de 1 mm de large au plus ; une pointe de 2,3 mm fait 4,6 px et survit), puis fermeture 7×7 (comble les trous de 3 mm).

Les seuils de l'art antérieur vont de 11 à 60 sur des métriques différentes ; 18 est une valeur de départ.

#### D4. Composantes et classement de la scène

Union-find en deux passes, 8-connexité. Écarter les composantes de moins de 15 mm² (60 px). Soit `A` l'aire restante. Dans cet ordre :

| Test | Résultat (`SceneAnalysis.Kind`) |
|---|---|
| `changedBoardFraction ≥ 0,35` | `lightingChange` |
| `A > 4000 mm² × maxNewDarts` | `obstruction` (main, bras, personne) |
| état des fléchettes connues (ci-dessous) | listes `removedDartIDs`, `disturbedDartIDs` |
| `A < 60 mm²` | `removal` si une fléchette est retirée, sinon `noChange` |
| garde-fantôme en échec | `foreignRemoval` |
| sinon | `darts` (D5 à D10) ; `unrecognized` si aucune droite exploitable n'en sort |

**État de chaque fléchette connue**, sur sa silhouette non dilatée et sur la preuve non masquée :

- **retirée** : au moins 50 % de la silhouette a changé par rapport à `R` et, si `E` est disponible, au moins 50 % de la silhouette ressemble de nouveau à `E` (`e(E, S) < τ`) ;
- **dérangée** : entre 15 % et 50 % de la silhouette a changé.

**Garde-fantôme.** Un candidat doit aussi différer du plateau vide : au moins 50 % de ses pixels vérifient `e(E, S) ≥ τ`. Sinon quelque chose a *quitté* la cible (par exemple une fléchette restée dans `R` par erreur) : aucun événement de fléchette. Sans `E` fraîche, le test est sauté et le candidat porte `emptyReferenceStale`.

#### D5. Regroupement et axe — une droite robuste sur tous les pixels nouveaux

Tous les pixels restants, en millimètres, entrent dans **un seul** ajustement. Choisir la plus grande composante échoue [sonde : une tige noire sur un secteur noir sépare l'empennage du fût].

1. ACP : moyenne `m`, covariances `σxx, σyy, σxy`, `θ = ½·atan2(2σxy, σxx − σyy)`, `u = (cos θ, sin θ)`, `λ1,2 = (σxx + σyy ± √((σxx − σyy)² + 4σxy²)) / 2`.
2. Quatre passes repondérées sur la distance latérale `d` : poids 1 pour `d ≤ 4` mm, `4/d` jusqu'à 25 mm, 0 au-delà.
3. Les pixels à moins de 20 mm de la droite forment l'ensemble `P` de la fléchette. Si `P` contient moins de 80 % des pixels : `clutter`.
4. Découper `P` en tranches de 1 mm le long de `u` ; largeur d'une tranche = étendue latérale + 0,5 mm.

**Images fixes (`maxNewDarts > 1`)** : épluchage. Ajuster la droite, prendre son couloir comme fléchette n° 1, retirer ces pixels, recommencer tant qu'il reste au moins 60 mm², trois fois au plus. Chaque fléchette porte `multiDartStill`.

#### D6. Quelle extrémité est la pointe

Largeur moyenne des 20 % de tranches à chaque bout. Règles, dans l'ordre :

1. **Empennage identifié** : un bout fait au moins 12 mm de large et au moins 2 fois l'autre. La pointe est l'autre bout.
2. **Pose** (couche `usePoseForTipEnd`) : si `tan θ ≥ 0,15` au centroïde, la pointe est le bout le plus proche de `F`.
3. **Sur la cible** : si un seul bout est à r ≤ 180 mm, c'est la pointe.
4. À défaut : le bout le plus proche du centre, avec `tipEndAmbiguous`.

Drapeaux : `tipEndAmbiguous` si les règles 1 et 2 désignent des bouts différents (la règle 1 l'emporte) ; `nearEndWide` si le bout retenu par la règle 2 ou 3 fait plus de 12 mm de large.

`u` est ensuite orienté **vers la pointe**.

*Pourquoi cet ordre :* l'empennage (35 à 40 mm de large) est le repère le plus sûr quand il est visible ; la règle de la pose le confirme, ou décide seule quand l'empennage est coupé ou caché. La règle de la pose est exacte pour une fléchette perpendiculaire et reste vraie tant que la fléchette ne penche pas vers la caméra de plus que l'angle de vue local, ce que le placement sous la cible rend rare.

#### D7. Réajustement sur la partie étroite

N'utiliser que les pixels des 60 % de la longueur les plus proches de la pointe et des tranches d'au plus 12 mm de large (pointe, fût, tige ; pas l'empennage, qui tire la droite de plusieurs millimètres [art antérieur]). ACP avec 3 passes de Huber, `k = 1,5` mm. Moins de 40 pixels : garder la droite de D5 et lever `fewNarrowPixels`.

#### D8. Marche vers la pointe sur la carte de preuve

Les derniers millimètres d'une pointe sont fins et peu contrastés : on utilise la carte continue `e`, pas le masque.

1. Le long de la droite réajustée, abscisse `t` croissante vers la pointe, depuis 8 mm avant la fin du masque jusqu'à 25 mm après, pas de 0,25 mm : `P(t)` = maximum de `e` (bilinéaire) sur les décalages latéraux de −1,5 à +1,5 mm.
2. Fin = dernier `t` où `P ≥ 0,5·τ`, en franchissant les trous de 2 mm au plus. Si la marche entre dans la silhouette dilatée d'une fléchette connue : arrêt, `tipPossiblyOccluded`, et `occlusionSpan` = longueur de la corde de cette silhouette le long de l'axe.
3. Niveau = `max(0,5·τ ; 0,5·médiane(P sur les 3 derniers mm))`. `t*` = franchissement de ce niveau, interpolé linéairement.
4. Correction latérale `w̄` = centroïde de `e` sur ±2,5 mm en travers, pris 1 mm avant `t*`.
5. **Correction de calotte** : la pointe est un cylindre de rayon `r` ≈ 1,15 mm ; le bord de sa silhouette côté caméra est à `r` du vrai point d'entrée [sonde]. La pointe est donc reculée vers l'empennage de `tipCapCorrection = 0,8` mm :

   `X̂ = m + (t* − 0,8)·u + w̄·n`, en millimètres métriques.

#### D9. Drapeaux de plausibilité

| Drapeau | Test | Ce qu'il attrape |
|---|---|---|
| `pointNotVisible` | largeur moyenne des 6 derniers mm avant la pointe > 4 mm | pointe noire sur noir ; fléchette vue en bout ; pointe cachée |
| `lowTipContrast` | médiane de `P` sur les 3 derniers mm < 1,5·τ | visibilité limite |
| `implausiblyLong` | longueur visible > `‖X̂ − F‖·L/(D − L) + L·tan 20°·D/(D − L)`, `L = 170` mm | ombre prise pour la fléchette ; deux objets alignés |
| `lowElongation` | longueur < 25 mm ou `λ1/λ2 < 4` | fléchette vue en bout ; objet qui n'est pas une fléchette |
| `tipPossiblyOccluded` | le point à 2 mm au-delà de `X̂`, vers la pointe, est dans une silhouette connue, ou la marche s'y est arrêtée | pointe derrière une fléchette antérieure |
| `earlierDartDisturbed` | une fléchette connue est changée de 15 à 50 % | déviation |
| `nearCanvasEdge` | `P` touche le bord de la région d'intérêt | cadrage trop serré |
| `clutter`, `fewNarrowPixels`, `tipEndAmbiguous`, `nearEndWide` | voir D5 à D7 | — |

#### D10. Sortie — `DartCandidate`

- `tip` : `ringRadii.toNominal(X̂')`, où `X̂' = pose.removingParallax(from: X̂, height: −wireHeight)` est `X̂` corrigé de la hauteur des fils (C6 ; `X̂' = X̂` quand `wireHeight = 0`). Le détecteur ne lit que des champs stockés du calibrage (`ringRadii`, `pose`, `wireHeight`, `boardToImage`) et n'appelle aucune de ses méthodes.
- `axis` : `−u` (de la pointe vers l'empennage). `silhouette` : `P` plus le couloir parcouru, non dilaté. `visibleLength`, `occlusionSpan`, `flags`.
- Aucune confiance ici : elle est calculée par `ConfidenceModel` (section 7), identique pour tous les détecteurs.

Les fonctions d'étape (`ChangeEvidence`, `BlobAnalysis`, `TipEstimator`) sont `internal` et testées une à une avec `@testable import`. `DifferencingDartDetector.analyseWithDebug` expose la carte de preuve, le masque, l'axe et la pointe pour `SnapshotTool`.

### 5.3 Paramètres

Tous les paramètres de la détection sont dans **une** structure, `DetectionParameters` (`Codable`), elle-même rangée dans `VisionConfiguration`. Longueurs en mm, aires en mm², seuils en niveaux sur 8 bits.

| Étape | Paramètre | Défaut | Origine |
|---|---|---|---|
| D2 | `blurRadius` | 1 (boîte 3×3) | conception 1 |
| D2 | `shadowLowerBound` / `shadowUpperBound` | 0,40 / 1,08 | [sonde] ; borne basse réglée par la vérification à une fléchette dans [0,2 ; 0,5] |
| D2 | `gainGridStep`, `gainMinReferenceNorm` | 16 px, 60 | conception 1 |
| D3 | `evidenceThresholdFloor`, `noiseMultiplier` | 18, 6 | [sonde] ; art antérieur 11 à 60 |
| D3 | `edgeGuardPixels` | 0,25 px | [estimation] |
| D3 | `silhouetteDilation`, `relockExtraDilation` | 2 mm, 3 mm | conceptions 1 et 3 |
| D3 | `openRadius`, `closeRadius` | 1 px, 3 px (3×3, 7×7) | [art antérieur] |
| D4 | `speckArea` | 15 mm² | [estimation] |
| D4 | `minChangeArea`, `maxDartArea` | 60, 4000 mm² | [estimation] |
| D4 | `lightingChangeFraction` | 0,35 | [art antérieur] |
| D4 | `removedFraction`, `disturbedFraction` | 0,5 / 0,15 | [estimation] |
| D4 | `ghostGuardFraction` | 0,5 | [estimation] |
| D5 | `lineFullWeightDistance`, `lineZeroWeightDistance`, `lineIterations` | 4 mm, 25 mm, 4 | [sonde] |
| D5 | `corridorHalfWidth`, `clutterFraction`, `peelMinArea` | 20 mm, 0,8, 60 mm² | [sonde] |
| D6 | `usePoseForTipEnd` | `true` | couche optionnelle |
| D6 | `endFraction`, `flightMinWidth`, `flightWidthRatio` | 0,2, 12 mm, 2 | [sonde] |
| D6 | `poseMinTanObliquity`, `onBoardRadius` | 0,15, 180 mm | [estimation] |
| D7 | `narrowPartFraction`, `narrowMaxWidth`, `narrowHuberK`, `narrowMinPixels` | 0,6, 12 mm, 1,5 mm, 40 | [art antérieur] |
| D8 | `walkThresholdRatio`, `walkCorridorHalfWidth`, `walkStep` | 0,5, 1,5 mm, 0,25 mm | [art antérieur] |
| D8 | `walkBack`, `walkAhead`, `walkGap`, `lateralHalfWidth` | 8, 25, 2, 2,5 mm | [sonde] |
| D8 | `tipCapCorrection` | 0,8 mm | [sonde, cylindre synthétique] |
| D9 | `pointMaxWidth`, `pointCheckLength` | 4 mm, 6 mm | [sonde] |
| D9 | `lowContrastRatio`, `minVisibleLength`, `minElongation` | 1,5, 25 mm, 4 | [sonde] |
| D9 | `maxDartLength`, `maxLeanDegrees`, `occlusionProbe` | 170 mm, 20°, 2 mm | [estimation] |

Deux paramètres seulement concernent le joueur, et tous deux se règlent seuls : `τ` (d'après le bruit) et `shadowLowerBound` (d'après la vérification à une fléchette).

### 5.4 Résultats de la sonde et budget

[sonde, conception 1] 120 fléchettes aléatoires par scénario, réparties sur toute la cible, inclinaison queue en haut de 0 à 18°, 3 couleurs de fût, 20 % de pointes noires, bruit et flou. « Haute » = confiance ≥ 0,85.

| Scénario | Erreur de pointe médiane / p95 | Segments corrects | Part à confiance haute | Corrects parmi les hautes |
|---|---|---|---|---|
| Sans ombre | 1,03 / 1,29 mm | 100 % | 75 % | 100 % |
| Ombre 0,65 alignée avec la fléchette | 1,02 / 1,50 mm | 100 % | 75 % | 100 % |
| Ombre dure 0,35, borne basse 0,3 | 1,05 / 3,61 mm | 94,2 % | 65 % | 100 % |
| Ombre très dure 0,20 (hors modèle) | 103 / 155 mm | 3,3 % | 2,5 % | 0 % (3 fléchettes) |
| Fléchettes tombantes, queue en bas de 0 à 18° | 1,11 / 9,88 mm | 94,1 % | 53 % | 98,4 % |

La médiane d'environ 1 mm contient un artefact du moteur de rendu (la calotte de la pointe), que la correction de calotte doit retirer ; ce n'est pas une promesse de précision sous le millimètre. Dans le cas de l'ombre très dure, 116 fléchettes sur 120 sont signalées basses au lieu d'être mal comptées ; les 3 qui ne le sont pas justifient la vérification à une fléchette et le suivi des corrections.

**Budget par événement, source 4K** : porte 0,1 ms par image ; redressement de 4 images, environ 6 ms chacune sur ce Mac [sonde, conception 3], le double attendu sur un téléphone ; D2 à D10 de 15 à 30 ms [estimation] ; confiance moins de 0,1 ms ; contrôle de dérive 1 à 2 ms. Objectif : moins de 150 ms sur une puce de classe A14 [estimation, non mesuré]. Au repos, seule la porte tourne.

---

## 6. Machine à états temporelle

Trois faits physiques portent la logique : quelque chose bouge, l'image est immobile, le plateau est de nouveau vide.

- `ScanStateMachine` est un **réducteur pur** : `(état, entrée) → (état, effets)`. Il ne lit jamais d'horloge ; le temps arrive dans les entrées (horodatage des images).
- `ScanEngine` exécute les effets (accumuler, analyser, mettre à jour les références) et renvoie les événements. Il est synchrone et déterministe.
- `ScanSession` ajoute une file série, la source d'images et un `AsyncStream<ScanEvent>`.
- Le réducteur ne manipule que des valeurs de simple donnée (section 9.4) et ne fabrique jamais de `BoardCalibration`. Les deux événements qui en transportent un, `calibrationAdjusted` et `calibrationRecovered`, sont émis par `ScanEngine` lui-même, au moment où il adopte le nouveau calibrage et juste avant de transmettre `calibrationHealth(status, recovered:, timestamp:)` au réducteur. Le réducteur n'en tire que les transitions des lignes K et l'événement `calibrationLost`.
- **Ordre des événements** : dans une même transition, `stateChanged(nouvel état)` sort en premier, puis les événements dans l'ordre où la ligne de la table les cite.

### 6.1 La porte de mouvement (chaque image, 30 images/s)

Image de porte : la boîte englobante de la région d'intérêt dans l'image source, canal vert, moyennée par blocs d'un facteur entier pour que son grand côté fasse au plus 320 px. Seuil par pixel `T_g = max(12, 5·σ_porte)`.

| Signal (`GateSample`) | Définition |
|---|---|
| `motionFraction` | fraction des pixels changés par rapport à l'image précédente |
| `changeVsReference` | fraction changée par rapport à l'image de porte mémorisée à la dernière pose |
| `borderChange` | idem, limitée à la bande de 6 px le long du bord de la région |
| `meanLuma` | moyenne sur la région |

Ordres de grandeur [estimation] : une fléchette ≈ 0,5 à 0,7 % de la porte ; une main et un avant-bras ≈ 10 à 15 %. L'impact fait vibrer toute la cible pendant quelques images : l'amplitude du mouvement ne distingue donc pas un lancer d'une main, sa **durée** et l'**entrée par le bord** le font.

**Épisode** : de la première image en mouvement à la pose. Il est « de type main » si sa durée dépasse 0,6 s ou si `borderChange > 4 %` pendant au moins 5 images de suite ; sinon il est « de type lancer ». Un épisode parti de l'état `takeout` ou `obstructed` est toujours de type main (section 6.3).

### 6.2 Constantes (`ScanParameters`)

| Constante | Valeur | Origine |
|---|---|---|
| Début de mouvement (`motionOnFraction`) | `motionFraction > 0,12 %` sur 1 image | [art antérieur] |
| Calme (`quietFraction`) | `motionFraction < 0,05 %` | [art antérieur] |
| Pose (`settleFrames`) | 6 images calmes de suite (200 ms) | [art antérieur], trois projets s'accordent sur 0,2 s |
| Accumulation (`skipFrames`) | images calmes n° 3 à 6 | 2 images de vibration résiduelle sautées |
| Aucun changement durable (`noLastingChangeFraction`) | `changeVsReference < 0,04 %` à la pose | saute l'analyse complète |
| Armement (`armingFrames`) | 12 images calmes | conceptions 1 et 3 |
| Épisode de type lancer (`throwMaxDuration`) | moins de 0,6 s | [estimation] |
| Main par le bord (`handBorderFraction`, `handSustainFrames`) | 4 % pendant 5 images | [estimation] |
| Contrôle au repos (`idleCheckInterval`) | toutes les 2 s | conception 1 |
| Rafraîchissement de `R` au repos (`idleRefreshInterval`) | toutes les 10 s si rien n'a changé | conception 1 |
| Escalade d'obstruction (`obstructionEscalation`, `obstructionAdvisoryDelay`) | 2 s, puis conseil à 10 s | conception 1 |
| Mouvement sans fin (`motionTimeout`) | 8 s | conception 2 |
| Retrait qui s'éternise (`takeoutStallInterval`) | 5 s | conceptions 1 et 3 |
| Nouvelle tentative de recalage (`relockRetryInterval`) | 1 s calme | conception 3 |
| Capture manuelle sans image posée (`captureTimeout`) | 2 s | [estimation] |

Latence : le mouvement est vu 33 ms après l'impact, la pose prend 200 ms, l'analyse moins de 150 ms. L'événement sort **0,3 à 0,45 s** après l'arrêt des vibrations.

### 6.3 États et transitions

États (`ScanState`) : `needsCalibration`, `idle`, `arming`, `watching(dartsOnBoard:)`, `motion`, `settling`, `analysing`, `awaitingTakeout`, `takeout`, `obstructed`, `calibrationLost`, `paused(raison)`.

- « État immobile » désigne `watching`, `awaitingTakeout`, `takeout` ou `obstructed`.
- « État calibré » désigne tout état sauf `needsCalibration` et `calibrationLost`. `paused` est calibré quand la pause a été prise dans un état calibré, et ne l'est pas sinon.
- « État précédent » est l'état immobile d'où l'épisode est parti. Pour une pause ou une perte de calibrage prise dans `obstructed`, c'est l'état immobile d'avant l'obstruction : `R` exclut l'obstruction, si bien qu'une analyse « aucun changement » contre `R` dit que la main est partie. Pour une pause, c'est l'état où se trouvait la machine quand la **première** `pause` est arrivée : l'état immobile, ou celui d'où partait l'épisode ou la capture interrompus (lignes P2 et DM7) ; ou bien `needsCalibration`, `idle`, `arming` ou `calibrationLost` (ligne P2b).
- `paused` porte une raison (`PauseReason`) : `.user` pour une pause de l'application (fin de partie), `.background` ou `.thermal` pour une pause du système. Elle décide de ce qui lève la pause (lignes P1 à P2c).
- `n` est le nombre de fléchettes connues sur la cible.
- Les lignes 4 à 10 et la table « Issues de l'analyse » décrivent le déclenchement automatique. Le déclenchement manuel a sa propre table, plus bas.

**Cycle de base**

| # | Depuis | Déclencheur | Vers | Effets |
|---|---|---|---|---|
| 1 | tout état | `setCalibration` | `idle` | références et silhouettes effacées ; redresseur et porte reconstruits |
| 2 | tout état calibré | commande `arm(boardConfirmedEmpty:)` | `arming` | références, silhouettes et compteurs (`visit`, `dartsInVisit`, fléchettes connues) remis à zéro ; épisode ou capture en cours abandonné (`discardAccumulation`) ; porte relancée ; la session a verrouillé mise au point, exposition et balance des blancs |
| 3 | `arming` (après `arm`) | 12 images calmes | `watching(0)` | `R :=` moyenne des 4 dernières ; `E := R` si le plateau est confirmé vide, sinon `E` inconnue ; mesure de `σ̂` et du bruit de porte ; contrôle de dérive ; référence de porte |
| 4 | état immobile | début de mouvement | `motion` | accumulation jetée ; début d'épisode |
| 5 | `motion` | 2 images calmes de suite | `settling` | contrôle de dérive sur cette image (lignes K) ; début d'accumulation |
| 6 | `settling` | mouvement | `motion` | accumulation jetée |
| 7 | `settling` | 6e image calme | `analysing` | si aucun changement durable : issue « aucun changement » sans analyse ; sinon analyse (section 5) |
| 8 | `motion` | mouvement continu pendant plus de 8 s | `obstructed` | `advisory(.viewObstructed)` |
| 9 | état immobile | toutes les 2 s, si la porte diffère de sa référence | `settling` | accumulation de 4 images puis analyse |
| 10 | `watching` | toutes les 10 s, analyse « aucun changement » | inchangé | `R := S` (absorbe la lente dérive du jour) |

**`arm` est la commande de début de partie** : première partie, partie suivante ou revanche. Elle est donc acceptée depuis `idle`, depuis `paused` (la couche jeu envoie `pause(.user)` en fin de partie), depuis `watching`, `awaitingTakeout` (fléchettes de la victoire encore plantées), `takeout` et `obstructed`, et aussi depuis `motion`, `settling` et `arming`, où elle repart de zéro.

- Dans `needsCalibration`, `arm` est ignorée.
- Dans `calibrationLost`, elle remet compteurs, références et silhouettes à zéro et retient `boardConfirmedEmpty`, sans changer d'état : la récupération (ligne K4) se termine alors comme la ligne 3, dans `watching(0)`.
- Dans `paused`, `arm` lève la pause, **quelle qu'en soit la raison**. Pause prise dans un état calibré : ligne 2. Pause prise dans `needsCalibration` ou dans `calibrationLost` : la machine revient d'abord à cet état, comme le ferait `resume` à la ligne P2b (`stateChanged`, porte relancée dans `calibrationLost`), puis `arm` y a l'effet des deux lignes ci-dessus. `arm` n'arme donc jamais sans calibrage, et une machine en pause n'y reste jamais bloquée.
- `arm` ne modifie pas le déclencheur (`trigger`).

**Issues de l'analyse** (depuis `analysing`)

| # | Issue | Vers | Effets |
|---|---|---|---|
| A1 | fléchette, volée non pleine | `watching(n+1)` | `dart` ; `R := S` ; silhouette mémorisée ; référence de porte |
| A2 | fléchette qui complète la volée | `awaitingTakeout` | idem |
| A3 | fléchette alors que la volée est pleine ou close | `awaitingTakeout` | `dart` avec `beyondVisitLimit` ; `R := S` ; silhouette mémorisée ; référence de porte. Comme en A1, la fléchette compte dans `n` et son retrait émet `dartRemoved` : sans cela, son retrait passerait pour celui d'un objet inconnu, et le contrôle de la ligne 9 se déclencherait toutes les 2 s |
| A4 | forme nouvelle **et** fléchette connue retirée ou dérangée | comme A1 à A3 | `dartRemoved(id, .fellOut)` pour chaque retirée, `dartDisturbed(id)` pour chaque dérangée, puis `dart` avec `earlierDartDisturbed` ; `R := S` |
| A5 | aucun changement après un épisode de type lancer | état précédent | `possibleMiss` |
| A6 | aucun changement après un épisode de type main | état précédent | — |
| A7 | toutes les fléchettes connues retirées, rien d'autre, après un épisode de type main ou au contrôle au repos (ligne 9) | `watching(0)` | `dartRemoved(id, .takeout)` pour chacune, puis `takeoutCompleted` ; `E := R := S` ; silhouettes effacées ; contrôle de dérive |
| A8 | une partie des fléchettes retirée, rien d'autre, après un épisode de type main ou au contrôle au repos | `takeout` | `takeoutStarted` (une fois), `dartRemoved(id, .takeout)` ; `R := S` |
| A9 | `takeout`, immobile depuis 5 s, il reste des fléchettes | `awaitingTakeout` | `takeoutStalled(remaining)` |
| A10 | `k` fléchette(s) retirée(s) après un épisode de type lancer, aucune forme nouvelle ; **évaluée avant A7 et A8** | `watching(n−k)`, y compris `watching(0)` | `dartRemoved(id, .fellOut)` pour chacune ; `R := S` ; `E` inchangée ; jamais de `takeoutCompleted` |
| A11 | obstruction | `obstructed` | `R` conservée |
| A12 | `obstructed`, pose sans obstruction | — | l'issue est réévaluée (A1 à A10) |
| A13 | `obstructed`, immobile depuis 2 s | selon la dérive | contrôle de dérive sur l'image courante, avant toute accumulation. Saine : 4 images accumulées, puis `unrecognizedChange`, `R := S`, silhouettes conservées, retour à l'état précédent ; dérivée : recalage, puis 4 images nouvelles accumulées et analysées comme après une main (jamais d'image redressée avec le calibrage dérivé) ; arêtes invisibles : on reste, `advisory(.viewObstructed)` après 10 s ; sans réponse, le contrôle est redemandé toutes les 2 s |
| A14 | changement d'éclairage | état précédent | `R := S`, silhouettes conservées ; `E := S` si `n = 0` et qu'aucune fléchette saisie à la main n'est sur la cible, sinon `E` périmée (6.4 : `E` n'est jamais prise avec des fléchettes sur la cible) ; `lightingChanged` |
| A15 | retrait d'un objet inconnu (garde-fantôme) | état précédent | `R := S` ; aucune fléchette |
| A16 | changement non reconnu | état précédent | `unrecognizedChange` ; `R := S` |

**Fléchette tombée ou retrait : ordre d'évaluation.** Quand des fléchettes connues ont disparu sans forme nouvelle, le type de l'épisode décide, et A10 passe avant A7 et A8.

- Après un épisode de **type lancer**, les fléchettes disparues sont *tombées* (A10), même si la cible se retrouve vide : `dartRemoved(id, .fellOut)`, `watching(n−k)`, pas de `takeoutCompleted`. Sans cette priorité, la seule fléchette de la cible qui tombe passerait pour un retrait : le joueur ne verrait pas « Fléchette tombée : 0 ? », la fléchette garderait son score et la couche jeu recevrait un faux « cible vidée ».
- A7 et A8 exigent un épisode de **type main**, ou une cible immobile sans épisode (contrôle au repos, ligne 9).
- Un épisode parti de `takeout` ou de `obstructed` est toujours de type main, quelle que soit sa durée : une main a déjà été vue. Le réducteur ajoute cette condition à `EpisodeSummary.isHandLike`.

**Calibrage**

| # | Situation | Vers | Effets |
|---|---|---|---|
| K1 | contrôle de la ligne 5 : dérivé, `recover` réussit | inchangé | nouveau calibrage adopté, redresseur et porte reconstruits, `calibrationAdjusted` ; précautions de la section 4.9 |
| K2 | perdu sur 2 contrôles consécutifs | `calibrationLost` | `calibrationLost` ; plus aucun événement de fléchette. « Perdu » : `lost`, ou `drifted` sans recalage réussi ; un recalage réussi (`recovered`) remet le compte à zéro ; `edgesNotVisible` (K5) ne compte pas et n'interrompt pas la suite. Le contrôle de fin d'armement et ceux de A13 comptent comme des poses |
| K3 | `calibrationLost`, chaque seconde calme | — | `recover`, puis localisation automatique si un `BoardLocating` est fourni |
| K4 | `calibrationLost`, récupération réussie | `arming`, puis l'état précédent | `calibrationRecovered` ; `R := S` ; `E` périmée si `n > 0` |
| K5 | arêtes non mesurables | inchangé | on continue avec le calibrage courant |

**Pause**

| # | Depuis | Déclencheur | Vers | Effets |
|---|---|---|---|---|
| P1 | tout état sauf `paused` | `pause(raison)` : `.user`, `.background` ou `.thermal` | `paused(raison)` | porte arrêtée ; épisode ou capture en cours abandonné (`discardAccumulation`) ; références, silhouettes et compteurs conservés ; l'état précédent est retenu. `paused` porte la raison de cette première pause |
| P1b | `paused(r)` | `pause(raison)` | `paused(.user)` si `raison` est `.user` et que `r` ne l'est pas ; sinon inchangé | l'état retenu reste celui de la première pause, et rien d'autre ne change. Une pause de fin de partie l'emporte sur une pause du système, dans quelque ordre qu'elles arrivent : dans ce seul cas la raison change, et `stateChanged(.paused(.user))` est émis. Dans tous les autres cas la seconde pause est sans effet et sans événement |
| P2 | `paused(.background)` ou `paused(.thermal)`, pause prise dans un état immobile ou pendant un épisode | `resume` | `arming` | 12 images calmes, puis analyse de l'image posée `S` contre `R`. Issue « aucun changement » : retour à l'état précédent, `R := S` et référence de porte. Toute autre issue : `idle`, puis `needsEmptyBoard` ; aucun événement de fléchette, références inchangées. En déclenchement manuel : ligne DM7 |
| P2b | `paused(.background)` ou `paused(.thermal)`, pause prise dans `needsCalibration`, `idle`, `arming` ou `calibrationLost` (dans les deux modes de déclenchement) | `resume` | l'état d'avant la pause | `needsCalibration`, `idle`, `calibrationLost` : retour à cet état, sans armement ni analyse, et sans lire ni modifier aucune référence ; la porte est relancée dans `calibrationLost`, pour la ligne K3 ; `needsEmptyBoard` est réémis si `idle` l'avait levé. `arming` : l'armement repart de zéro (12 images calmes), puis la ligne qui l'avait ouvert se termine comme prévu (3, P2, P3, K4, DM7 ou DM8) |
| P2c | `paused(.user)`, où que la pause ait été prise (dans les deux modes de déclenchement) | `resume` | inchangé | ignorée, sans événement : une pause de fin de partie ne se lève que par `arm` (ligne 2 et règles de `arm` ci-dessus). Un nouveau calibrage (ligne 1) mène à `idle`, où les images sont ignorées elles aussi |
| P3 | `idle` | `confirmBoardEmpty` | `arming`, puis `watching(0)` | 12 images calmes, puis `E := R := S`, silhouettes effacées, mesure du bruit, référence de porte ; les compteurs de volée (`visit`, `dartsInVisit`) sont conservés |

`pause` et `resume` peuvent arriver dans n'importe quel état : la couche jeu les envoie quand l'application quitte le premier plan ou quand une partie se termine, et la couche de capture sur une interruption du système, sans connaître l'état de la machine. Les lignes P2, P2b, P2c et DM7 couvrent tous les cas : `resume` ne compare jamais l'image à une référence qui n'existe pas, n'arme jamais sans calibrage, et ne réveille jamais la vision quand aucune partie n'est en cours.

**La raison de la pause décide de ce qui la lève.**

- `pause(.user)` vient de l'application : une partie se termine ou est quittée, la vérification à une fléchette du calibrage est finie, ou l'appareil a été déplacé pendant un scan (`ARCHITECTURE.md` §6.5, §8.7). Plus rien ne doit être regardé jusqu'à la partie suivante : seule `arm` lève cette pause.
- `pause(.background)` et `pause(.thermal)` viennent du système (arrière-plan, interruption de capture, chaleur) : `resume` les lève.
- Les deux se croisent sans ordre défini : une partie peut finir pendant une interruption de capture, et l'application peut passer en arrière-plan après la fin d'une partie. Dans les deux cas la machine se trouve dans `paused(.user)` (lignes P1 et P1b), et le `resume` qui suit est ignoré (ligne P2c). Sans cette règle, un aller-retour en arrière-plan sur l'écran d'accueil réarmerait la vision, qui surveillerait la cible sans partie.

Après `needsEmptyBoard`, la machine reste dans `idle`, où les images sont ignorées, jusqu'à `confirmBoardEmpty` (P3) ou jusqu'à un nouvel `arm` (ligne 2). P3 est la seule sortie en cours de partie : sans elle, une reprise sur une scène changée arrêterait la détection jusqu'à la partie suivante. Comme les compteurs sont conservés, la couche jeu n'a pas à renvoyer `beginVisit`.

**Déclenchement manuel** (`trigger = .manual`, mode « Scanner la volée » de la section 8.1)

- Le déclencheur courant est `ScanStateMachine.trigger`. Il vaut `ScanParameters.trigger` au départ, ne change que par `setTrigger`, et survit à `setCalibration`, `arm`, `pause` et `resume`.
- **Repos.** Dans ce mode la machine se repose dans `watching(n)`, ou dans `awaitingTakeout` quand la volée est pleine ou close. Au repos, les lignes 4 à 10 sont désactivées : pas d'épisode, pas de contrôle au repos, pas de rafraîchissement de `R`. Le réducteur ignore les échantillons de porte et le moteur ne les calcule pas : rien n'est traité entre deux commandes.
- **Pose de capture.** Une commande de capture fait passer dans `settling`. Le moteur relance la porte et jette son premier échantillon, qui compare à une image ancienne. Le réducteur compte ensuite les images calmes consécutives (`quietFraction`) : à la 2e, contrôle de dérive et `beginAccumulation`, comme à la ligne 5 ; à la 6e (`settleFrames`), la capture aboutit sur la moyenne des images calmes n° 3 à 6. Une image en mouvement jette l'accumulation et remet le compte à zéro, sans changer d'état. La porte ne sert qu'à cela.
- Les lignes 1 à 3, K, P1 et P3 valent dans les deux modes ; dans `calibrationLost` la porte tourne de nouveau, pour la ligne K3. L'armement (ligne 3) prend `R`, et `E` si le plateau est confirmé vide, exactement comme en déclenchement automatique : « Cible vide » n'est alors pas nécessaire avant le premier scan.
- Ce mode ne produit aucun événement d'épisode : ni `possibleMiss`, ni `takeoutStarted`, `takeoutStalled` ou `takeoutCompleted`, ni `dartRemoved(.fellOut)`.
- `captureReference` et `captureNow` ne sont acceptées qu'au repos et en déclenchement manuel. Ailleurs (déclenchement automatique, capture déjà en cours, `idle`, `arming`, `paused`, `calibrationLost`) elles sont ignorées, sans événement. `captureNow(maxDarts: k)` avec `k ≤ 0` est ignorée elle aussi, sans événement et sans `scanCompleted` : il n'y a aucune fléchette à chercher.
- `endVisit`, `discardDart` et `registerManualDart` agissent comme en déclenchement automatique (section 6.5) : `endVisit` clôt la volée, et le repos devient `awaitingTakeout`.

| # | Depuis | Déclencheur | Vers | Effets |
|---|---|---|---|---|
| DM1 | tout état, déclencheur automatique | `setTrigger(.manual)` | repos si l'état était immobile, `motion`, `settling` ou `analysing` (traité comme `settling` : la réponse tardive de l'analyse est ignorée) ; sinon inchangé | épisode en cours abandonné (`discardAccumulation`) ; références, silhouettes et compteurs conservés. Sans effet si le déclencheur était déjà manuel |
| DM2 | repos | `captureReference` ou `confirmBoardEmpty` | `settling`, puis le repos : `watching(0)`, ou `awaitingTakeout` si la volée est pleine ou close (règle « Repos », qui vaut pour tout retour au repos de ce mode : DM2, P3, K4, DM7) | pose de capture, sans analyse ; `E := R := S`, silhouettes effacées, référence de porte |
| DM3 | repos | `captureNow(maxDarts: k)`, `k ≥ 1` | `settling`, `analysing`, puis repos | pose de capture, puis `analyse(maxNewDarts: k)` contre `R` ; la suite est dans la table des issues d'un scan |
| DM4 | repos | `beginVisit(expectedDarts: k)` | `watching(0)` si `k = expectedDartsPerVisit` et si `E` est connue ; sinon `watching(n)` | compteurs comme en automatique (volée + 1, `dartsInVisit = 0`) ; `E` est **toujours conservée**. `k = expectedDartsPerVisit` annonce une volée entière sur une cible que le joueur a vidée : `R := E` (`updateReference(.rollingFromEmpty)`) et silhouettes effacées, sans analyse et sans `dartRemoved`. Un `k` plus petit reprend une volée dont des fléchettes sont déjà plantées (resynchronisation après une correction) : références et silhouettes conservées |
| DM5 | repos | `rebaseline` | `settling`, puis le repos précédent | pose de capture, sans analyse ; `R := S`, silhouettes conservées |
| DM6 | `settling` (capture en cours) | pas de 6e image calme `captureTimeout` (2 s) après le premier échantillon transmis | repos précédent | `discardAccumulation` ; `advisory(.viewObstructed)` ; pour `captureNow`, `scanCompleted([])` ensuite ; aucune analyse, aucune référence modifiée |
| DM7 | `paused(.background)` ou `paused(.thermal)`, pause prise au repos ou pendant une capture | `resume` | `arming`, puis l'état précédent | 12 images calmes, mesure du bruit et contrôle de dérive ; pas de comparaison avec `R`, puisque la cible n'est pas surveillée dans ce mode ; références conservées |
| DM8 | tout état, déclencheur manuel | `setTrigger(.automatic)` | `arming` si l'état était un repos ou une capture en cours ; sinon inchangé | capture en cours abandonnée ; puis suite identique à la ligne P2 : retour au repos précédent si la scène n'a pas changé, sinon `idle` puis `needsEmptyBoard`. Sans effet si le déclencheur était déjà automatique |

**Issues d'un scan** (suite de la ligne DM3, depuis `analysing`). Toute commande `captureNow` acceptée se termine par **exactement un** `scanCompleted`, éventuellement vide, émis en dernier. La règle n'a pas d'exception : si la capture est interrompue avant son analyse (par `arm`, `pause`, `setTrigger`, un nouveau calibrage ou la perte du calibrage), `scanCompleted([])` est émis à ce moment. « Repos » désigne ici `watching(n)` avec le nouveau `n`, ou `awaitingTakeout` si la volée est pleine ou close.

| # | Issue | Vers | Effets |
|---|---|---|---|
| DM3a | fléchettes nouvelles | repos | `dartRemoved(id, .takeout)` pour chaque fléchette connue retirée, `dartDisturbed(id)` pour chaque dérangée, puis `scanCompleted(observations)` ; `R := S` ; silhouettes mémorisées ; compteurs augmentés ; une fléchette au-delà de la volée porte `beyondVisitLimit`, comme en A3 |
| DM3b | aucun changement | repos précédent | `scanCompleted([])` |
| DM3c | fléchettes connues retirées, rien de nouveau | repos | `dartRemoved(id, .takeout)` pour chacune, puis `scanCompleted([])` ; `R := S` ; leurs silhouettes sont oubliées ; `E` inchangée |
| DM3d | obstruction ; changement d'éclairage ; retrait d'un objet inconnu ; changement non reconnu | repos précédent | respectivement `advisory(.viewObstructed)`, `lightingChanged`, rien, `unrecognizedChange` ; puis `scanCompleted([])` ; **aucune référence modifiée** |

Dans ce mode, `E` ne change que par `arm`, `captureReference` et `confirmBoardEmpty` : une fléchette plantée ne peut donc jamais être absorbée par la référence vide. Après `lightingChanged`, l'interface demande de vider la cible et de refaire « Cible vide ».

Côté moteur (`ScanEngine`) :

- la requête d'analyse d'un scan est construite comme en automatique : `current = S`, `reference = R`, `emptyReference = E`, silhouettes connues, `maxNewDarts = k`. En début de volée `R = E` : le scan compare donc à la cible vide. Après un scan, `R` contient les fléchettes rendues, si bien qu'un second scan dans la même volée ne rend que les nouvelles ;
- les observations portent la source `.scan`, et `multiDartStill` quand `k > 1` (D5) ;
- une fléchette saisie à la main avant le scan (`registerManualDart`) est sur la cible sans être dans `R` : le scan la propose de nouveau, et l'écran de revue permet de l'écarter (`discardDart`).

**Ce que le moteur fait sans effet du réducteur** (deux modes de déclenchement). Aucun `ScanEffect` n'efface les références ni ne mémorise une silhouette, et l'entrée `ScanInput.armed` n'est décrite nulle part ailleurs. Le contrat, écrit aussi en commentaire de `ScanStateMachine`, est le suivant :

- le moteur efface `R`, `E`, les silhouettes et la référence de porte sur `setCalibration` (ligne 1), et sur un `arm` après lequel l'état est `arming` ou `calibrationLost` (un `arm` ignoré faute de calibrage n'efface rien). `E` reste alors inconnue jusqu'à un `updateReference(.rollingAndEmpty)` (ligne 3 avec `boardConfirmedEmpty`, A7, A14 avec `n = 0`, P3, DM2) ;
- il mémorise une silhouette pour chaque observation que le réducteur émet (`dart`, `scanCompleted`) et l'oublie sur `dartRemoved`, sur `discardDart` et sur toute mise à jour qui efface les silhouettes (`.rollingAndEmpty`, `.rollingFromEmpty`) ;
- `ScanInput.armed` signifie « la pose d'armement est complète » : dans `arming`, elle termine l'armement comme la dernière image calme ; ailleurs elle est ignorée. Le réducteur compte lui-même les images calmes : un moteur n'a jamais besoin de l'envoyer.

Ces règles laissent l'API de 9.2 telle quelle ; des effets explicites (« effacer », « mémoriser ») l'auraient changée.

### 6.4 Règles tirées des erreurs de l'art antérieur

- Une fléchette n'est comptée que sur une **scène immobile**. Une fléchette en vol qui croise une fléchette plantée pendant une image ne peut pas passer pour un retrait.
- Un retrait n'est cru qu'après un épisode de type main, ou quand aucune forme nouvelle n'apparaît.
- `E` est reprise après chaque retrait complet et **jamais** quand des fléchettes sont sur la cible.
- Un rebond n'est **jamais** compté automatiquement. La vision émet `possibleMiss` ; l'interface montre pendant quelques secondes un raccourci « Rebond ? Manqué », et le bouton « Manqué » reste toujours visible. `GAMES.md` §2.2 : un rebond vaut `MISS` et compte comme une fléchette lancée.
- **La vision ne clôt jamais un tour.** `takeoutCompleted` est une proposition : `GAMES.md` §2.4 exige un `endTurn` explicite. L'interface peut mettre en avant le bouton « Joueur suivant » à ce moment-là. Si le réglage `endsTurnOnTakeout` de `DartUI` est activé (désactivé par défaut, `GAMES.md` §2.4, `ARCHITECTURE.md` §8.6), c'est l'interface, et non la vision, qui produit alors `endTurn` : la vision n'émet toujours que `takeoutCompleted`.
- Une fléchette tombée (`dartRemoved(.fellOut)`) n'est pas annulée d'office : l'interface propose « Fléchette tombée : 0 ? » en un toucher (règle officielle : une fléchette tombée avant le retrait ne compte pas).
- Une fléchette qui se plante pendant un changement d'éclairage ou pendant une obstruction est absorbée par la référence et manquée. Le joueur l'ajoute à la main.
- Les corrections du joueur ne modifient jamais les références.

### 6.5 Commandes de la couche jeu (`ScanCommand`)

| Commande | Effet |
|---|---|
| `arm(boardConfirmedEmpty:)` | début de partie, depuis tout état calibré : lignes 2 et 3 |
| `beginVisit(expectedDarts:)` | compteur de volée + 1, `dartsInVisit = 0`, `expectedDarts` fléchettes attendues ; depuis `awaitingTakeout`, retour à `watching(n)`. Si des fléchettes de la volée précédente sont encore sur la cible, elles restent masquées et leur retrait ultérieur n'émet que `dartRemoved`. En déclenchement manuel : ligne DM4 |
| `endVisit` | tour clos par la règle du jeu (bust, victoire) : passe à `awaitingTakeout` |
| `confirmBoardEmpty` | la prochaine image posée devient `E` et `R`, sans analyse ; silhouettes effacées ; `watching(0)`. Depuis un état immobile, la pose est forcée tout de suite, comme à la ligne 9 ; pendant un épisode (`motion`, `settling`), c'est la pose de l'épisode qui sert. Depuis `idle` : ligne P3. En déclenchement manuel : ligne DM2 |
| `rebaseline` | « Continuer » : la prochaine image posée devient `R`, obtenue de la même façon ; silhouettes et état conservés. En déclenchement manuel : ligne DM5 |
| `discardDart(id)` | fausse détection : la forme reste dans `R`, les compteurs baissent. Son retrait ultérieur est absorbé par la garde-fantôme |
| `registerManualDart` | le joueur a ajouté une fléchette que la vision a manquée : `dartsInVisit + 1` ; si elle complète la volée, `watching` passe à `awaitingTakeout` (comme en A2) |
| `setTrigger(_:)` | lignes DM1 et DM8 |
| `captureReference`, `captureNow(maxDarts:)` | lignes DM2 et DM3 ; acceptées seulement au repos en déclenchement manuel ; `captureNow` avec `maxDarts ≤ 0` est ignorée |
| `pause(raison)`, `resume` | lignes P1, P1b, P2, P2b, P2c et DM7 ; acceptées dans tout état. `resume` lève une pause du système (`.background`, `.thermal`) et jamais une pause de la couche jeu (`.user`), que seule `arm` lève |

Une commande reçue dans un état où aucune ligne ne la prévoit est ignorée, sans événement. Seule exception : les commandes de compteur (`beginVisit`, `endVisit`, `discardDart`, `registerManualDart`) mettent toujours les compteurs à jour, y compris dans `idle`, `arming`, `paused` et `calibrationLost` ; seul leur changement d'état est alors omis.

---

## 7. Confiance et correction

**Confiance = probabilité du meilleur segment × qualité des indices.** Le modèle est le même pour tous les détecteurs (`ConfidenceModel`).

### 7.1 Incertitude de la pointe

Une gaussienne anisotrope alignée sur l'axe de la fléchette (`TipUncertainty`) :

```
σ_cal    = max(0,3 ; RMS des arêtes du calibrage)                    mm
σ_across = √(σ_cal² + (0,5/ppm)²)
σ_along  = √(σ_cal² + (1,0/ppm)² + (h·tan θ)²)
```

- `ppm` : px/mm de la source à la pointe, dans la pire direction (`boardToImage.localScale(at:).min`). Comme le détecteur, le modèle de confiance ne lit que des champs stockés du calibrage (`quality.edgeResidualRMS`, `boardToImage`, `pose`, `ringRadii`).
- `h = hiddenTipLength` : longueur de pointe supposée non vue, 1,5 mm ; 3,0 mm avec `lowTipContrast`.
- `tan θ = ‖pointe − F‖ / D`.
- Un détecteur peut fournir ses propres sigmas (`DartCandidate.sigmaAlong`, `sigmaAcross`). S'il ne fournit pas d'axe, l'axe est la direction qui s'éloigne de `F`.

Valeurs typiques au placement recommandé : `σ_along` ≈ 0,85 mm et `σ_across` ≈ 0,37 mm à 2,3 px/mm ; 1,1 et 0,5 mm à 1,2 px/mm [sonde].

**Pointe peut-être cachée.** La pointe peut se trouver n'importe où le long de `occlusionSpan` derrière la fléchette antérieure : la distribution devient la moyenne de 5 gaussiennes réparties uniformément sur cette longueur. Aucune pointe n'est inventée.

### 7.2 Postérieure par segment

Règle du point milieu sur une grille 21×21 couvrant ±3σ dans le repère (le long, en travers) :

```
a_i = ((i + 0,5)/21 · 2 − 1) · 3          poids = exp(−(a_i² + b_j²)/2)
position = pointe + axe·(a_i·σ_along) + normale·(b_j·σ_across)
```

Chaque position est ramenée en coordonnées nominales puis classée par `BoardGeometry.hit(at:)` ; les poids sont sommés par `Hit`. Garder au plus 6 candidats de probabilité ≥ 0,01 et renormaliser.

[sonde, conception 3] Contre un Monte-Carlo de 100 000 tirages sur 300 fléchettes, l'erreur de probabilité est de 0,023 au pire et 0,0012 en moyenne. Une grille 9×9 fait moins bien (0,044).

### 7.3 Qualité des indices

`q` = produit des facteurs des drapeaux présents, multiplié par `score` du détecteur.

| Drapeaux | Facteur | Paramètre |
|---|---|---|
| `pointNotVisible`, `implausiblyLong` | 0,4 | `severeFlagFactor` |
| `nearEndWide`, `tipEndAmbiguous`, `lowElongation` | 0,5 | `majorFlagFactor` |
| `tipPossiblyOccluded` | 0,6 | `occlusionFactor` |
| `beyondVisitLimit` | 0,6 | `visitLimitFactor` |
| `fewNarrowPixels`, `clutter`, `earlierDartDisturbed`, `multiDartStill` | 0,7 | `moderateFlagFactor` |
| `lowTipContrast`, `calibrationFair`, `afterRelock`, `nearCanvasEdge`, `emptyReferenceStale` | 0,9 | `minorFlagFactor` |

`confidence = P(meilleur segment) · q`, puis plafonds :

| Situation | Plafond |
|---|---|
| calibrage `poor` (`calibrationPoor`) | 0,80 |
| échauffement : 3 premières fléchettes après un calibrage sans vérification à une fléchette (`warmUp`) | 0,84 |
| paire de photos prises de deux endroits (`crossViewpoint`) | 0,80 |

### 7.4 Paliers et comportement

| Palier | Règle | Jeu | Son | Interface |
|---|---|---|---|---|
| `high` | confiance ≥ 0,85 | fléchette envoyée au moteur de jeu | impact et annonce vocale | pastille verte, modifiable d'un toucher |
| `medium` | 0,50 à 0,85 | envoyée, marquée « À vérifier » | impact et annonce | pastille orange ; le second candidat est proposé en un toucher ; confirmée d'office à la fin du tour |
| `low` | moins de 0,50 | **pas envoyée** ; en attente | son neutre et « À vérifier », aucun score annoncé | carte « ? » : 3 meilleurs candidats, « Autre… », « Manqué », et l'image de preuve |

Parts attendues dans le cas idéal (`q = 1`, fléchettes uniformes sur la cible) [sonde] :

| Conditions | `σ_along` / `σ_across` moyens | Haute | Moyenne | Basse |
|---|---|---|---|---|
| 2,3 px/mm, `σ_cal` 0,3 | 0,85 / 0,37 mm | 91 % | 9 % | < 1 % |
| 1,2 px/mm, `σ_cal` 0,3 | 1,11 / 0,51 mm | 89 % | 11 % | < 1 % |
| 1,2 px/mm, `σ_cal` 0,5 | 1,18 / 0,65 mm | 87 % | 13 % | < 1 % |
| 1,2 px/mm, `σ_cal` 0,7, contraste faible | 1,71 / 0,81 mm | 82 % | 17 % | < 1 % |

Environ une fléchette sur dix est donc orange par simple proximité d'un fil. Les drapeaux s'y ajoutent : la sonde de bout en bout de la conception 1 donne 65 à 75 % de fléchettes hautes en scène nominale. C'est une propriété du modèle, pas une précision mesurée.

**Les fléchettes en attente ne bloquent jamais le lancer.** La détection continue. Comme le moteur de jeu reçoit les fléchettes dans l'ordre, les fléchettes suivantes sont affichées mais retenues derrière celle qui attend ; le joueur répond quand il veut avant de confirmer le tour, typiquement devant la cible au moment du retrait. Politique de l'appelant : attendre la réponse (défaut), ou accepter la meilleure hypothèse après un délai (question ouverte pour le propriétaire).

**Regroupement selon le jeu.** `DartObservation.tier(collapsingBy:)` additionne les probabilités des candidats qui ont le même effet dans la partie en cours. Au Killer, hésiter entre S11 et S14 n'a d'importance que si l'un des deux est le numéro de quelqu'un ; sinon la fléchette est traitée comme haute et le joueur n'est pas dérangé.

Le calcul n'utilise que des champs stockés de l'observation (`candidates`, `confidence`, `flags`), pour qu'une observation fabriquée à la main (tests, service factice, mode démonstration) se comporte comme une vraie. Avec `outcome` la fonction passée par l'appelant :

```
key        = outcome(candidates[0].hit)
P_group    = somme des probability des candidats dont outcome(hit) == key
collapsed  = min(confidence · P_group / candidates[0].probability, cap(flags))
tier       = thresholds.tier(for: collapsed)
```

- `cap(flags)` vaut 0,80 si les drapeaux contiennent `calibrationPoor` ou `crossViewpoint`, 0,84 s'ils contiennent `warmUp` (le plus petit des deux quand les deux cas se présentent), et 1 sinon. Ce sont les plafonds par défaut de la section 7.3 ; le regroupement ne lit pas `ConfidenceParameters`.
- Sans plafond actif, `confidence = P(meilleur segment) · q` et `collapsed = P_group · q` : la qualité des indices continue de compter.
- Avec un plafond actif, il est réappliqué : une fléchette plafonnée par ses drapeaux reste sous le palier haut même quand tous ses candidats se regroupent.
- Pour une observation produite par `ConfidenceModel`, `collapsed ≥ confidence` : à seuils égaux, le regroupement ne fait jamais descendre un palier.
- Un plafond passé par `ConfidenceContext.cap` sans drapeau correspondant n'est pas mémorisé dans l'observation et n'est donc pas réappliqué. Les trois plafonds de ce document ont chacun leur drapeau.
- Si `candidates[0].probability` est nulle (observation fabriquée), `collapsed = confidence`.

Dans un jeu qui dépend de la position de l'impact (Radar, `GAMES.md` §2.13), la couche jeu ajoute un contrôle sur la pointe elle-même : elle rejoue la meilleure case aux quatre points `tip ± sigmaAlong·axis` et `tip ± sigmaAcross·normale`, et marque la fléchette « à vérifier » si l'effet change (`ARCHITECTURE.md` §8.4.8). `uncertainty` DOIT donc être renseignée pour toute observation, y compris fabriquée : des sigmas nuls désactivent ce contrôle.

Exemple : candidats S11 à 0,6 et S14 à 0,4, `confidence = 0,6`, aucun drapeau. Si S11 et S14 ont le même effet, `collapsed = 0,6 · 1,0 / 0,6 = 1,0` : palier haut. La même fléchette avec `warmUp` donne `min(1,0 ; 0,84) = 0,84`, avec `calibrationPoor` 0,80 : palier moyen dans les deux cas.

### 7.5 Crochets de correction

Toute fléchette détectée reste modifiable jusqu'à la confirmation du tour (`GAMES.md` §2.5).

| Besoin | Côté `DartVision` | Côté jeu (`GAMES.md` §2.5) |
|---|---|---|
| Choisir un autre segment en un toucher | `DartObservation.candidates`, `correctionChoices(minimum:)` | `replaceDart(index, hit)` |
| Voir la vraie image | `ScanEngine.evidenceCrop(for:span:scale:)` : fenêtre de 50 mm du canevas, agrandie 6 fois ; l'interface y dessine les fils et la pointe estimée | — |
| Déplacer la pointe au doigt | `ScanEngine.correct(_:tip:)` rend une nouvelle observation (confiance 1, source `tappedOnPhoto`) | `replaceDart(index, hit)` |
| Supprimer une détection fantôme | commande `discardDart(id)` | `removeDart(index)` |
| Ajouter une fléchette manquée | commande `registerManualDart` | entrée `dart(hit)` ordinaire |
| Choisir sur la cible virtuelle (« Autre… ») | aucun : c'est une saisie manuelle | `replaceDart` ou `dart(hit)` |
| Informer la vision du résultat | `ScanEngine.recordFeedback(_:wasCorrected:)`, une fois par fléchette caméra à la confirmation du tour | — |

Les corrections sont écrites dans l'enregistreur (`ScanRecording.record(correctionOf:correctedTip:)`) : ce sont les meilleures données de réglage.

### 7.6 Suivi de la confiance (`TrustTracker`)

- Si le joueur corrige au moins 2 fléchettes **hautes** parmi les 15 dernières : le seuil haut monte à 0,95 et `advisory(.accuracyDegraded)` propose de recalibrer ou de vérifier la lumière. Retour à 0,85 après 15 fléchettes non corrigées.
- Si plus de 30 % des 12 dernières fléchettes caméra ont été basses ou corrigées : `advisory(.suggestLightingCheck)`, puis `advisory(.suggestScanMode)` si cela persiste.

---

## 8. Mode photo

Trois modes, aucun nouveau pipeline.

### 8.1 « Scanner la volée » — appareil sur son support, déclenchement manuel (socle)

- Même moteur, `trigger = .manual`. **Les transitions sont celles de la table « Déclenchement manuel » de la section 6.3, qui fait foi.** Une « photo » est la moyenne de 4 images du flux vidéo : calibrage et géométrie identiques au mode direct, pas d'`AVCapturePhotoOutput`.
- La couche jeu envoie `setTrigger(.manual)` avant `arm`, puis `beginVisit` et `endVisit` comme en mode direct. Le déclencheur survit à `arm` : une partie en mode direct envoie donc `setTrigger(.automatic)` de la même façon.
- « Cible vide » envoie `captureReference` (prend `E` et `R`). Une fois suffit : `E` est conservée d'une volée à l'autre, et elle est déjà prise par l'armement quand le plateau a été confirmé vide. Le bouton sert ensuite après un changement de lumière.
- « Scanner » envoie `captureNow(maxDarts:)` avec le nombre de fléchettes encore attendues dans la volée (3 en début de volée, moins celles déjà comptées ou en attente de réponse) ; le bouton est inactif quand ce nombre est nul ou que la volée est close, et la machine ignore de toute façon une commande à `maxDarts ≤ 0` : analyse de la section 5 contre la référence courante, avec épluchage (D5). En début de volée la référence courante est `E` ; après un scan elle contient les fléchettes rendues, et un second scan dans la même volée ne rend que les nouvelles.
- Résultat : exactement un événement `scanCompleted` par commande acceptée, éventuellement vide (rien de nouveau, vue qui ne se pose pas en 2 s, lumière changée). Les observations sont de source `.scan` ; quand plus d'une fléchette est demandée, chacune porte `multiDartStill` (leur ordre est inconnu). L'écran de revue est toujours montré et permet de réordonner.
- Entre deux commandes la vision ne regarde pas la cible : elle ne voit ni retrait, ni rebond, ni fléchette tombée. Les deux boutons ne sont actifs qu'au repos (`watching` ou `awaitingTakeout`).
- Des fléchettes croisées lèvent `clutter` ou `implausiblyLong` et passent en confirmation.
- À utiliser quand le déclenchement automatique se comporte mal ou quand l'appareil chauffe : rien n'est traité entre deux prises. C'est aussi le repli proposé par `advisory(.suggestScanMode)`.

### 8.2 Photo unique, à main levée ou importée (socle, chemin garanti)

Pas de référence, donc pas de différence d'images.

1. Calibrer **cette photo** : localisation automatique ou quatre poignées, puis affinage. Les fléchettes cachent quelques échantillons d'arêtes, que les poids de Huber absorbent.
2. Afficher la photo redressée et zoomable (`PhotoScorer.rectified`).
3. Le joueur touche chaque pointe dans la loupe ; `PhotoScorer.observation(forTappedTip:…)` donne le score immédiatement, sans aucun risque de détection.

Intrinsèques : auto-calibrage de Zhang ou champ supposé ; ici la pose ne sert qu'à l'affichage.

Quand l'application prend elle-même la photo, appareil tenu en main, c'est une seule image : `ScanSession.captureStill(averaging: 1)`. La moyenne de 8 images, utilisée pour le calibrage sur support, rendrait floue une photo à main levée.

### 8.3 Paire de photos à main levée (couche optionnelle, phase 2)

Une photo du plateau vide prise une fois, puis une photo avec les fléchettes prise d'un autre endroit. Chaque photo est calibrée seule et redressée ; les deux canevas s'alignent sur le plan de la cible sans recalage d'image. `PhotoScorer.score(photo:calibration:emptyReference:…)` applique la section 5 avec un flou plus large. Les sources de bruit sont la parallaxe des fils et la différence de lumière ; chaque proposition porte donc `crossViewpoint` et reste plafonnée à 0,80 : rien n'est compté sans revue.

Chaque observation porte sa `source` : `liveCamera`, `scan`, `handheldPhoto` ou `tappedOnPhoto`.

---

## 9. API publique de `DartVision`

### 9.1 Ce que `DartVision` attend de `DartCore`

Exactement trois symboles. Si `DartCore` les nomme autrement, l'adaptation se fait dans un seul fichier (`DartCoreBridge.swift`, des `typealias` et une extension).

```swift
// Required from DartCore.

/// A point of the board plane in millimetres. Origin at the bull centre, +x towards the 6, +y towards the 20.
public struct BoardPoint: Hashable, Codable, Sendable {
    public var x: Double
    public var y: Double
    public init(x: Double, y: Double)
}

/// One of the 63 values of GAMES.md §2.2 (S1...S20, D1...D20, T1...T20, SB, DB, MISS).
public struct Hit: Hashable, Codable, Sendable

/// Nominal board dimensions and the conversion from a board point to a scored hit.
public struct BoardGeometry: Sendable {
    public static let standard: BoardGeometry
    public var sectorOrder: [Int] { get }            // 20, 1, 18, 4, 13, 6, 10, 15, 2, 17, 3, 19, 7, 16, 8, 11, 14, 9, 12, 5
    public var innerBullRadius: Double { get }       // 6.35
    public var outerBullRadius: Double { get }       // 15.9
    public var trebleInnerRadius: Double { get }     // 99
    public var trebleOuterRadius: Double { get }     // 107
    public var doubleInnerRadius: Double { get }     // 162
    public var doubleOuterRadius: Double { get }     // 170
    /// Scored hit of a point in NOMINAL coordinates; MISS beyond the outer double radius, and for a point with a
    /// non-finite coordinate (the function is total: it never traps).
    public func hit(at point: BoardPoint) -> Hit
}
```

`DartVision` n'a besoin ni des voisins d'un segment ni de la distance à une frontière : les choix de correction viennent de la postérieure et de `nearbyHits`, obtenus en appelant `hit(at:)` autour de la pointe (cercles de 4, 8 et 16 mm).

### 9.2 Listing

Signatures seules. Ce listing compile tel quel (avec des corps vides) pour `arm64-apple-ios17.0` et `arm64-apple-macos14.0`, en mode Swift 5 avec `-strict-concurrency=complete`, et en mode Swift 6. La section 9.3 dit dans quel fichier va chaque type, la section 9.4 quels membres reçoivent un vrai corps dès le squelette.

- `Homography` range sa matrice en trois `SIMD3<Double>` pour que `Codable`, `Hashable` et `Sendable` soient synthétisés (`simd_double3x3` n'est pas `Codable`).
- `Frame` est `@unchecked Sendable` : il enveloppe un `CVPixelBuffer` sans copie et n'est garanti valide que pendant l'appel qui le livre.
- Le champ de vision est toujours celui du **grand côté** de l'image (`longSideFieldOfViewDegrees`), pour rester juste en portrait.

```swift
// DartVision — public API (signatures only).
// Package DartKit, target DartVision. Platforms: iOS 17, macOS 14. Swift 5 language mode.
// Depends on DartCore for exactly three symbols: BoardPoint, Hit, BoardGeometry (see section 9.1).

import Foundation
import simd
import CoreGraphics
import CoreVideo
import DartCore
#if canImport(AVFoundation)
import AVFoundation
#endif

// MARK: - 1. Pixels and frames

/// Size of an image in pixels.
public struct PixelSize: Hashable, Codable, Sendable {
    public var width: Int
    public var height: Int
    public init(width: Int, height: Int)
}

/// A point in image pixels: origin top-left, +x right, +y down, integer values at pixel centres.
public struct ImagePoint: Hashable, Codable, Sendable {
    public var x: Double
    public var y: Double
    public init(x: Double, y: Double)
    /// Builds a point from normalised coordinates in [0, 1]² (origin top-left): x = u * width - 0.5.
    public init(normalized: SIMD2<Double>, in size: PixelSize)
    /// Normalised coordinates in [0, 1]²: ((x + 0.5) / width, (y + 0.5) / height).
    public func normalized(in size: PixelSize) -> SIMD2<Double>
}

/// 8-bit interleaved RGB, row-major, no padding. The only image type the algorithms read.
public struct RGBImage: Equatable, Sendable {
    public let width: Int
    public let height: Int
    /// `count == width * height * 3`, order R, G, B.
    public var pixels: [UInt8]
    public init(width: Int, height: Int, pixels: [UInt8])
    public init(width: Int, height: Int, fill: SIMD3<UInt8>)
    /// Converts any CGImage (sRGB, alpha ignored). Nil when the bitmap context cannot be created.
    public init?(cgImage: CGImage)
    public init?(pngData: Data)
    public var size: PixelSize { get }
    public subscript(x: Int, y: Int) -> SIMD3<UInt8> { get set }
    /// Bilinear sample at a sub-pixel position; nil outside the image.
    public func sample(x: Double, y: Double) -> SIMD3<Float>?
    public func makeCGImage() -> CGImage?
    public func pngData() -> Data?
}

/// 8-bit single-channel image, row-major. Used for masks, evidence maps and gate images.
public struct GrayImage: Equatable, Sendable {
    public let width: Int
    public let height: Int
    public var pixels: [UInt8]
    public init(width: Int, height: Int, pixels: [UInt8])
    public init(width: Int, height: Int, fill: UInt8)
    public subscript(x: Int, y: Int) -> UInt8 { get set }
    public func makeCGImage() -> CGImage?
}

/// Memory layout of a `Frame`.
public enum FramePixelFormat: Sendable {
    /// 4 bytes per pixel, order B, G, R, A (kCVPixelFormatType_32BGRA).
    case bgra8
    /// 3 bytes per pixel, order R, G, B (an `RGBImage`).
    case rgb8
}

/// One video frame. Wraps a CVPixelBuffer (capture) or an RGBImage (tests, replay) without copying.
/// A frame handed to a consumer is only guaranteed valid during that call.
public struct Frame: @unchecked Sendable {
    public let timestamp: TimeInterval
    public let size: PixelSize
    public let format: FramePixelFormat
    public init(image: RGBImage, timestamp: TimeInterval)
    /// Nil unless the buffer is kCVPixelFormatType_32BGRA.
    public init?(pixelBuffer: CVPixelBuffer, timestamp: TimeInterval)
    /// Gives read access to the pixel bytes (the buffer is locked read-only for the duration of `body`).
    public func withUnsafeBytes<R>(_ body: (UnsafeRawBufferPointer, _ bytesPerRow: Int) throws -> R) rethrows -> R
    /// Full copy as RGB. Used for calibration stills and recordings, never per frame.
    public func makeRGBImage() -> RGBImage
}

// MARK: - 2. Geometry

/// A plane projective transform `p' ~ M * (x, y, 1)`. Stored as three rows.
public struct Homography: Hashable, Codable, Sendable {
    public var row0: SIMD3<Double>
    public var row1: SIMD3<Double>
    public var row2: SIMD3<Double>
    public init(_ matrix: simd_double3x3)
    /// Normalised DLT with h33 = 1 (8x8 normal equations, Gaussian elimination with partial pivoting).
    /// Requires at least 4 pairs. Nil when the input is degenerate (pivot below 1e-12).
    public init?(from source: [SIMD2<Double>], to destination: [SIMD2<Double>])
    /// Heckbert closed form: unit square (0,0),(1,0),(1,1),(0,1) to `quad`. Nil when degenerate.
    public static func unitSquare(to quad: [SIMD2<Double>]) -> Homography?
    /// Rotation of the board frame by a clockwise angle (see section 4.3, step L7).
    public static func boardRotation(clockwiseDegrees: Double) -> Homography
    public static let identity: Homography
    public var matrix: simd_double3x3 { get }
    /// Adjugate divided by the determinant; nil when |det| < 1e-9 after equilibration (columns, then rows, scaled to unit length).
    public var inverse: Homography? { get }
    public func apply(_ p: SIMD2<Double>) -> SIMD2<Double>
    /// Jacobian of `apply` at `p` (output units per input unit).
    public func jacobian(at p: SIMD2<Double>) -> simd_double2x2
    /// Singular values of the Jacobian at `p`: worst- and best-direction scale.
    public func localScale(at p: SIMD2<Double>) -> (min: Double, max: Double)
    /// Returns `self ∘ first` (apply `first`, then `self`).
    public func concatenating(_ first: Homography) -> Homography
}

/// Pinhole intrinsics in pixels, origin top-left.
public struct CameraIntrinsics: Hashable, Codable, Sendable {
    public enum Source: String, Codable, Sendable {
        /// Intrinsic matrix delivered with the sample buffer.
        case sampleBuffer
        /// Derived from the active format's field of view.
        case fieldOfView
        /// Single-plane self-calibration from the homography.
        case selfCalibrated
        /// Fallback: 67 degrees along the long side.
        case assumed
    }
    public var fx: Double
    public var fy: Double
    public var cx: Double
    public var cy: Double
    public var source: Source
    public init(fx: Double, fy: Double, cx: Double, cy: Double, source: Source)
    /// `f = (max(width, height) / 2) / tan(fov / 2)`, principal point at the image centre.
    public init(longSideFieldOfViewDegrees: Double, imageSize: PixelSize)
    /// Zhang single-plane formula with the principal point at the image centre.
    /// Nil when both denominators are ill-conditioned or f is outside [0.5, 3] * max(width, height).
    public static func selfCalibrated(boardToImage: Homography, imageSize: PixelSize) -> CameraIntrinsics?
    public static func assumed(imageSize: PixelSize) -> CameraIntrinsics
    public var matrix: simd_double3x3 { get }
    /// True for `.selfCalibrated` and `.assumed`.
    public var isApproximate: Bool { get }
}

/// Camera pose relative to the board, recovered from the homography and the intrinsics.
public struct CameraPose: Hashable, Codable, Sendable {
    /// Camera centre in the board frame, mm. `center.z > 0` in front of the board.
    public let center: SIMD3<Double>
    /// Rows of the board-to-camera rotation (camera x right, y down, z forward).
    public let rotationRows: [SIMD3<Double>]
    /// True when the intrinsics were self-calibrated or assumed.
    public let isApproximate: Bool
    /// Nil when the recovered camera centre is behind the board plane (mirrored handles).
    public init?(boardToImage: Homography, intrinsics: CameraIntrinsics)
    /// F: orthogonal projection of the camera centre on the board plane.
    public var footPoint: BoardPoint { get }
    /// D: distance from the camera centre to the board plane, mm.
    public var distance: Double { get }
    /// `|point - F| / D`: board millimetres of error per hidden millimetre of height at `point`.
    public func tanObliquity(at point: BoardPoint) -> Double
    /// Where a point at `height` mm above `point` appears in the board plane: `X + (X - F) * s / (D - s)`.
    public func apparentPosition(of point: BoardPoint, height: Double) -> BoardPoint
    /// Inverse of `apparentPosition`.
    public func removingParallax(from apparent: BoardPoint, height: Double) -> BoardPoint
}

/// Ring radii of one physical board in mm. The outer double radius is the scale gauge and stays at its nominal value.
public struct RingRadii: Hashable, Codable, Sendable {
    public var innerBull: Double
    public var outerBull: Double
    public var trebleInner: Double
    public var trebleOuter: Double
    public var doubleInner: Double
    public var doubleOuter: Double
    public init(innerBull: Double, outerBull: Double, trebleInner: Double, trebleOuter: Double, doubleInner: Double, doubleOuter: Double)
    /// The radii of `BoardGeometry.standard`.
    public static let nominal: RingRadii
    /// Piecewise-linear radial remap from this board's metric coordinates to nominal coordinates,
    /// so that DartCore classifies with the nominal geometry.
    public func toNominal(_ point: BoardPoint) -> BoardPoint
    /// Inverse of `toNominal`.
    public func fromNominal(_ point: BoardPoint) -> BoardPoint
}

// MARK: - 3. Calibration

/// The four draggable calibration points: junctions of the outer double wire (r = 170 mm) with four radial wires.
public enum CalibrationHandle: Int, CaseIterable, Codable, Sendable {
    case wire20_1, wire6_10, wire3_19, wire11_14
    /// `(170 sin a, 170 cos a)` for a = 9, 99, 189, 279 degrees:
    /// about (26.59, 167.91), (167.91, -26.59), (-26.59, -167.91), (-167.91, 26.59).
    public var boardPoint: BoardPoint { get }
    /// Number printed next to the handle in the overlay: "20", "6", "3", "11".
    public var label: String { get }
}

/// Image positions of the four handles, in `CalibrationHandle` order.
public struct CalibrationHandles: Hashable, Codable, Sendable {
    public var points: [ImagePoint]
    public init(points: [ImagePoint])
    /// Handles of a known homography (used by the locator). Lot V2; `SyntheticCamera.exactHandles()` does not call it.
    public init(projecting boardToImage: Homography)
    public subscript(handle: CalibrationHandle) -> ImagePoint { get set }
    /// Starting position: a circle of radius `0.3 * min(width, height)` at the image centre.
    public static func centredDefault(in size: PixelSize) -> CalibrationHandles
    public func translated(dx: Double, dy: Double) -> CalibrationHandles
    public func scaledAndRotated(about centre: ImagePoint, scale: Double, radians: Double) -> CalibrationHandles
    /// Rotates the wireframe by `count` sectors clockwise (18 degrees each). Nil when the handles are degenerate.
    public func rotated(bySectors count: Int) -> CalibrationHandles?
    /// Rotates the wireframe so that the middle of the 20 sector is as close as possible to `point`.
    /// With `parityPreserving`, only multiples of 36 degrees are tried (the red/green phase is kept).
    public func reoriented(twentyAt point: ImagePoint, parityPreserving: Bool) -> CalibrationHandles?
}

public enum CalibrationIssue: String, Codable, Sendable, CaseIterable {
    // Blocking: "Valider" is disabled.
    case handlesMirrored, quadNotConvex, horizonCrossesBoard, boardOutOfFrame, resolutionTooLow
    // Advisory: lowers the grade, scanning stays possible.
    case resolutionLow, viewTooFrontal, viewTooOblique, dartMarginCutOff
    case sectorPhaseMismatch, edgesNotFound, refinementRejected, intrinsicsApproximate
    public var isBlocking: Bool { get }
}

public struct CalibrationQuality: Hashable, Codable, Sendable {
    public enum Grade: Int, Codable, Sendable, Comparable {
        case poor, fair, good
        public static func < (lhs: Grade, rhs: Grade) -> Bool
    }
    public var grade: Grade
    /// RMS of inlier edge residuals in mm; nil when no still was assessed (`preview`).
    public var edgeResidualRMS: Double?
    public var edgeInlierFraction: Double?
    public var measuredFraction: Double?
    public var refinementApplied: Bool
    /// Largest handle move made by the refinement, px.
    public var maxHandleShift: Double
    /// Worst-direction scale over the bull and 8 points on r = 170, px/mm.
    public var minPixelsPerMillimetre: Double
    /// Angle between the board normal and the ray to the bull, degrees.
    public var viewAngleDegrees: Double
    /// `(|F| - 170) / D`: below 0.16 darts near the camera side are seen end-on.
    public var minTanObliquity: Double
    /// `(|F| + 170) / D`: above 0.84 a hidden millimetre of point costs almost a millimetre.
    public var maxTanObliquity: Double
    /// Most actionable first.
    public var issues: [CalibrationIssue]
    /// `max(0.3, edgeResidualRMS)`, shown as "Précision estimée ± x mm".
    public var estimatedAccuracy: Double { get }
}

/// Overlay geometry in image pixels; DartUI maps it into the preview.
public struct BoardWireframe: Sendable {
    /// Six closed polylines (ring radii), innermost first.
    public var rings: [[ImagePoint]]
    /// Twenty segments from the outer bull to the outer double wire.
    public var wires: [[ImagePoint]]
    public var numberAnchors: [(number: Int, point: ImagePoint)]
    /// Closed polyline of the region that must stay in view (board disc plus the dart margin).
    public var safeFrame: [ImagePoint]
}

/// The result of calibration. Valid only for frames of `imageSize` delivered with `rotationDegrees`.
public struct BoardCalibration: Hashable, Codable, Sendable, Identifiable {
    public let id: UUID
    public let createdAt: Date
    public let imageSize: PixelSize
    public let rotationDegrees: Int
    /// Handles as the user (or the locator) placed them.
    public let userHandles: CalibrationHandles
    /// Handles after refinement; equal to `userHandles` when the refinement was rejected.
    public let handles: CalibrationHandles
    /// H: metric board mm to image px.
    public let boardToImage: Homography
    /// G = H⁻¹.
    public let imageToBoard: Homography
    public let ringRadii: RingRadii
    /// Height of the wires above the sisal that this calibration compensates, mm (section 4.6, C6). 0 = no compensation.
    public let wireHeight: Double
    public let intrinsics: CameraIntrinsics
    public let pose: CameraPose
    public let quality: CalibrationQuality
    /// Nominal board coordinates of an image point: G, then the wire-height correction
    /// `pose.removingParallax(from:height: -wireHeight)`, then `ringRadii.toNominal`.
    public func boardPoint(for point: ImagePoint) -> BoardPoint
    /// Image position of a nominal board point (exact inverse of `boardPoint(for:)`).
    public func imagePoint(for point: BoardPoint) -> ImagePoint
    /// Scored hit under an image point: the tap test of the setup screen and tap-the-tips in photo mode.
    public func hit(at point: ImagePoint, board: BoardGeometry) -> Hit
    /// Source px/mm at a nominal board point (worst and best direction).
    public func localScale(at point: BoardPoint) -> (min: Double, max: Double)
    public func wireframe(ringSegments: Int) -> BoardWireframe
}

/// Every calibration constant. Defaults are starting values (section 11).
public struct CalibrationParameters: Hashable, Codable, Sendable {
    // C1 gate
    public var hardMinPixelsPerMillimetre: Double = 0.8
    public var dartMargin: Double = 135
    // C2 edge measurement
    public var profileStep: Double = 0.25
    public var profileHalfWindow: Double = 4.0
    public var secondPassHalfWindow: Double = 2.0
    public var gradientSpan: Int = 2
    public var minEdgeEnergy: Double = 20
    public var edgePeakRatio: Double = 2.5
    public var centroidHalfWidth: Int = 4
    // C3 refinement
    public var huberK: Double = 0.75
    public var outlierCutoff: Double = 3.0
    public var jacobianStep: Double = 0.25
    public var damping: Double = 1e-3
    public var maxIterations: Int = 6
    public var convergence: Double = 0.01
    public var handleTetherWeight: Double = 0.3
    public var minMeasuredFraction: Double = 0.5
    public var minInlierFraction: Double = 0.6
    public var inlierDistance: Double = 1.0
    public var maxInlierRMS: Double = 0.5
    public var maxHandleShift: Double = 4.0
    public var recoverMaxHandleShift: Double = 6.0
    // C4 ring radii, C5 sector phase, C6 wire height
    public var fitRingRadii: Bool = true
    public var ringRadiusTolerance: Double = 2.0
    public var bullRadiusTolerance: Double = 1.0
    public var minSectorLumaContrast: Double = 25
    public var wireHeight: Double = 0
    // Grades
    public var goodRMS: Double = 0.35
    public var fairRMS: Double = 0.7
    public var goodPixelsPerMillimetre: Double = 1.5
    public var fairPixelsPerMillimetre: Double = 1.2
    public var goodMinTan: Double = 0.21
    public var fairMinTan: Double = 0.16
    public var goodMaxTan: Double = 0.84
    public var fairMaxTan: Double = 1.2
    // Drift
    public var driftHealthyMedian: Double = 0.5
    public var driftHealthyInliers: Double = 0.6
    public var driftHealthyInliersWithDarts: Double = 0.5
    public var driftNotVisibleFraction: Double = 0.3
    public init()
}

public enum CalibrationError: Error, Equatable, Sendable {
    /// Fewer than four distinct handles, or three of them collinear.
    case degenerateHandles
    /// At least one blocking issue.
    case rejected([CalibrationIssue])
}

/// Result of the drift check (section 4.9).
public struct CalibrationHealth: Hashable, Sendable {
    public enum Status: Sendable { case healthy, drifted, lost, edgesNotVisible }
    public var status: Status
    /// Median absolute edge residual, mm.
    public var medianResidual: Double
    public var inlierFraction: Double
    public var measuredFraction: Double
}

public struct BoardCalibrator: Sendable {
    public init(parameters: CalibrationParameters = .init())
    /// Closed-form H plus the sanity gate (C1) and pose (C7). Runs on every handle drag for the live wireframe.
    public func preview(handles: CalibrationHandles, imageSize: PixelSize, rotationDegrees: Int,
                        intrinsics: CameraIntrinsics?) -> Result<BoardCalibration, CalibrationError>
    /// Full calibration (C1 to C8) on a frozen still of the board.
    public func calibrate(handles: CalibrationHandles, still: RGBImage, rotationDegrees: Int,
                          intrinsics: CameraIntrinsics?) -> Result<BoardCalibration, CalibrationError>
    /// Drift check on any still or frame; darts may be on the board.
    public func assess(_ calibration: BoardCalibration, on still: RGBImage, dartsOnBoard: Bool) -> CalibrationHealth
    public func assess(_ calibration: BoardCalibration, on frame: Frame, dartsOnBoard: Bool) -> CalibrationHealth
    /// Bounded re-refinement starting from the current handles (`recoverMaxHandleShift`). Nil when the gate fails.
    public func recover(_ calibration: BoardCalibration, on still: RGBImage) -> BoardCalibration?
    public func recover(_ calibration: BoardCalibration, on frame: Frame) -> BoardCalibration?
}

/// Output of automatic board finding: initial handles only. Calibration then runs exactly as with manual handles.
public struct BoardLocation: Sendable {
    /// Handles for the orientation whose 20 is closest to `upDirection`.
    public var handles: CalibrationHandles
    /// The nine other orientations, 36 degrees apart.
    public var alternatives: [CalibrationHandles]
    /// Phase contrast of the red/green alternation, 0...0.64 (identity check).
    public var phaseContrast: Double
}

/// Optional layer: automatic board finding.
public protocol BoardLocating: Sendable {
    /// `upDirection` is the image direction of "up" (default (0, -1)); it picks one of the ten orientations.
    func locate(in still: RGBImage, upDirection: SIMD2<Double>) -> BoardLocation?
}

/// Colour mask, outer ellipse, bull, circle-point construction, 10th-harmonic phase (section 4.3).
public struct ColourBoardLocator: BoardLocating {
    public struct Parameters: Hashable, Codable, Sendable {
        public var workLongSide: Int = 640
        public var minBrightness: Int = 48
        public var saturationRange: ClosedRange<Double> = 0.30...0.55
        public var rayCount: Int = 360
        public var minRunLength: Int = 3
        public var sampsonTolerance: Double = 1.5
        public var bullAreaRange: ClosedRange<Double> = 0.4...2.5
        public var minColouredFraction: Double = 0.7
        public var minUncolouredFraction: Double = 0.8
        public var minPhaseContrast: Double = 0.35
        public var maxPhaseDisagreementDegrees: Double = 3
        public init()
    }
    public init(parameters: Parameters = .init())
    public func locate(in still: RGBImage, upDirection: SIMD2<Double>) -> BoardLocation?
}

// MARK: - 4. Canvas (rectified board image)

/// The canonical top-down image of the board. Constants, not tuning parameters.
public enum BoardCanvas {
    /// 2 px/mm.
    public static let pixelsPerMillimetre: Double = 2
    /// 320 mm from the bull to each edge.
    public static let halfExtent: Double = 320
    /// 1280 px.
    public static let side: Int = 1280
    /// Metric board point of a canvas position: `x = -320 + (px + 0.5) / 2`, `y = 320 - (py + 0.5) / 2`.
    public static func boardPoint(x: Double, y: Double) -> BoardPoint
    public static func pixel(for point: BoardPoint) -> SIMD2<Double>
}

/// A rectified frame: `side x side` RGB plus a validity mask.
public struct CanvasImage: Sendable {
    public var rgb: RGBImage
    /// 255 where the pixel is inside the region of interest and inside the camera frame.
    public var valid: GrayImage
    public init(rgb: RGBImage, valid: GrayImage)
    /// Square crop centred on a metric board point, `span` mm wide, upscaled by `scale` (bilinear).
    public func crop(centre: BoardPoint, span: Double, scale: Double) -> RGBImage
}

/// Run-length mask in canvas pixels (board space, so it survives a re-calibration).
public struct CanvasMask: Hashable, Codable, Sendable {
    public init()
    public init(_ image: GrayImage)
    public var isEmpty: Bool { get }
    /// Area in mm².
    public var area: Double { get }
    public func contains(_ point: BoardPoint) -> Bool
    public func dilated(by millimetres: Double) -> CanvasMask
    public func union(_ other: CanvasMask) -> CanvasMask
    public func intersects(_ other: CanvasMask) -> Bool
    public func makeImage() -> GrayImage
}

/// Warps camera frames into the canvas through `calibration.boardToImage`.
public struct BoardRectifier: Sendable {
    public init(calibration: BoardCalibration)
    /// Bounding box in the camera image of the canvas region of interest (also the gate region).
    public var imageRegionOfInterest: (x: Int, y: Int, width: Int, height: Int) { get }
    /// Region of interest: board disc r <= 190 mm plus the area where dart bodies can appear.
    public var regionOfInterest: CanvasMask { get }
    public func rectify(_ frame: Frame) -> CanvasImage
    public func rectify(_ image: RGBImage) -> CanvasImage
}

/// Averages rectified frames (UInt16 sums).
public struct FrameAccumulator: Sendable {
    public init()
    public var count: Int { get }
    public mutating func add(_ image: CanvasImage)
    public mutating func reset()
    public func mean() -> CanvasImage?
    /// Per-frame noise estimate from the last two frames added: `median|a - b| / 0.954`.
    public func noiseSigma() -> Double?
}

// MARK: - 5. Detection

/// Every constant of the detection pipeline (section 5). Lengths in mm, areas in mm², thresholds in 8-bit levels.
public struct DetectionParameters: Hashable, Codable, Sendable {
    // D2 evidence
    public var blurRadius: Int = 1
    public var shadowLowerBound: Double = 0.40
    public var shadowUpperBound: Double = 1.08
    public var gainGridStep: Int = 16
    public var gainMinReferenceNorm: Double = 60
    // D3 mask
    public var evidenceThresholdFloor: Double = 18
    public var noiseMultiplier: Double = 6
    public var edgeGuardPixels: Double = 0.25
    public var silhouetteDilation: Double = 2.0
    public var relockExtraDilation: Double = 3.0
    public var openRadius: Int = 1
    public var closeRadius: Int = 3
    // D4 components and scene classification
    public var speckArea: Double = 15
    public var minChangeArea: Double = 60
    public var maxDartArea: Double = 4000
    public var lightingChangeFraction: Double = 0.35
    public var removedFraction: Double = 0.5
    public var disturbedFraction: Double = 0.15
    public var ghostGuardFraction: Double = 0.5
    // D5 grouping and axis
    public var lineFullWeightDistance: Double = 4
    public var lineZeroWeightDistance: Double = 25
    public var lineIterations: Int = 4
    public var corridorHalfWidth: Double = 20
    public var clutterFraction: Double = 0.8
    public var peelMinArea: Double = 60
    // D6 tip end
    public var usePoseForTipEnd: Bool = true
    public var endFraction: Double = 0.2
    public var flightMinWidth: Double = 12
    public var flightWidthRatio: Double = 2
    public var poseMinTanObliquity: Double = 0.15
    public var onBoardRadius: Double = 180
    // D7 refit on the narrow part
    public var narrowPartFraction: Double = 0.6
    public var narrowMaxWidth: Double = 12
    public var narrowHuberK: Double = 1.5
    public var narrowMinPixels: Int = 40
    // D8 tip walk
    public var walkThresholdRatio: Double = 0.5
    public var walkCorridorHalfWidth: Double = 1.5
    public var walkStep: Double = 0.25
    public var walkBack: Double = 8
    public var walkAhead: Double = 25
    public var walkGap: Double = 2
    public var lateralHalfWidth: Double = 2.5
    public var tipCapCorrection: Double = 0.8
    // D9 plausibility
    public var pointMaxWidth: Double = 4
    public var pointCheckLength: Double = 6
    public var lowContrastRatio: Double = 1.5
    public var minVisibleLength: Double = 25
    public var minElongation: Double = 4
    public var maxDartLength: Double = 170
    public var maxLeanDegrees: Double = 20
    public var occlusionProbe: Double = 2
    public init()
    public static let `default`: DetectionParameters
}

/// Reasons to doubt a detected dart. Each one lowers the confidence (section 7.3).
/// Bit positions follow the order of this list: `pointNotVisible` is `1 << 0`, `calibrationPoor` is `1 << 18`.
public struct DartFlags: OptionSet, Hashable, Codable, Sendable {
    public let rawValue: UInt32
    public init(rawValue: UInt32)
    /// The last millimetres before the tip are wider than a point: black point, end-on dart or hidden tip.
    public static let pointNotVisible: DartFlags
    public static let lowTipContrast: DartFlags
    /// Longer than any dart can appear: a shadow or two objects in line.
    public static let implausiblyLong: DartFlags
    public static let lowElongation: DartFlags
    public static let nearEndWide: DartFlags
    /// The width profile and the camera foot point disagree about which end is the tip.
    public static let tipEndAmbiguous: DartFlags
    public static let fewNarrowPixels: DartFlags
    /// More than 20 % of the changed pixels are outside the dart corridor.
    public static let clutter: DartFlags
    /// The tip walk ran into the silhouette of an earlier dart.
    public static let tipPossiblyOccluded: DartFlags
    public static let earlierDartDisturbed: DartFlags
    public static let beyondVisitLimit: DartFlags
    public static let emptyReferenceStale: DartFlags
    public static let nearCanvasEdge: DartFlags
    public static let afterRelock: DartFlags
    public static let warmUp: DartFlags
    /// Several darts found in one still: their order is unknown.
    public static let multiDartStill: DartFlags
    /// Reference and current image were taken from different viewpoints (hand-held photo pair).
    public static let crossViewpoint: DartFlags
    public static let calibrationFair: DartFlags
    public static let calibrationPoor: DartFlags
}

/// What a detector returns for one dart, before the confidence model.
public struct DartCandidate: Sendable {
    /// Tip in nominal board mm.
    public var tip: BoardPoint
    /// Unit vector from the tip towards the flight in the board plane; zero when unknown.
    public var axis: SIMD2<Double>
    /// Footprint of the dart in the canvas (not dilated).
    public var silhouette: CanvasMask
    /// Detector-supplied sigmas in mm; nil lets `ConfidenceModel` compute them.
    public var sigmaAlong: Double?
    public var sigmaAcross: Double?
    /// Length of the axis hidden behind earlier darts just before the tip, mm; 0 when none.
    public var occlusionSpan: Double
    /// Apparent length in the canvas, mm.
    public var visibleLength: Double
    /// Belief in 0...1 that this is a dart (1 for the differencing detector; a model can return less).
    public var score: Double
    public var flags: DartFlags
    public init(tip: BoardPoint, axis: SIMD2<Double>, silhouette: CanvasMask, sigmaAlong: Double? = nil,
                sigmaAcross: Double? = nil, occlusionSpan: Double = 0, visibleLength: Double = 0,
                score: Double = 1, flags: DartFlags = [])
}

/// A dart already committed on the board.
public struct KnownDart: Identifiable, Sendable {
    public let id: UUID
    public var tip: BoardPoint
    public var silhouette: CanvasMask
    public init(id: UUID, tip: BoardPoint, silhouette: CanvasMask)
}

public struct DetectorDescriptor: Hashable, Sendable {
    public enum Mode: Sendable {
        /// Needs a reference and returns only NEW darts (the differencing detector).
        case differential
        /// Returns ALL darts in view (a Core ML detector); the engine matches them to known darts.
        case absolute
    }
    public var name: String
    public var version: String
    public var mode: Mode
    public init(name: String, version: String, mode: Mode)
}

/// Everything a detector may use for one settled scene.
public struct DetectionRequest: Sendable {
    /// Mean of the settled frames, rectified.
    public var current: CanvasImage
    /// Rolling reference: board plus the darts already committed. Nil for `.absolute` detectors or single photos.
    public var reference: CanvasImage?
    /// Board at the start of the visit; nil when stale or unknown.
    public var emptyReference: CanvasImage?
    public var knownDarts: [KnownDart]
    public var calibration: BoardCalibration
    /// Per-frame noise sigma in 8-bit levels, measured at arming.
    public var noiseSigma: Double
    /// 1 in live mode, up to 3 for stills.
    public var maxNewDarts: Int
    /// Extra dilation of known silhouettes in mm (after a relock).
    public var extraSilhouetteDilation: Double
    /// Un-rectified source image for image-space detectors; nil in live mode unless the detector asks for it.
    public var sourceImage: RGBImage?
    public var parameters: DetectionParameters
    public init(current: CanvasImage, reference: CanvasImage?, emptyReference: CanvasImage?, knownDarts: [KnownDart],
                calibration: BoardCalibration, noiseSigma: Double, maxNewDarts: Int = 1,
                extraSilhouetteDilation: Double = 0, sourceImage: RGBImage? = nil,
                parameters: DetectionParameters = .default)
}

/// The detector's reading of one settled scene.
public struct SceneAnalysis: Sendable {
    public enum Kind: Sendable {
        case noChange
        /// One or more dart candidates (possibly with removed or disturbed darts in the same event).
        case darts
        /// Committed darts left the board and nothing new appeared.
        case removal
        /// A hand, an arm or a person covers part of the view.
        case obstruction
        case lightingChange
        /// Something that was baked into the rolling reference left the board: no dart.
        case foreignRemoval
        /// A change that is neither a dart, a hand nor light.
        case unrecognized
    }
    public var kind: Kind
    /// New darts (differential) or all darts in view (absolute), best first.
    public var darts: [DartCandidate]
    public var removedDartIDs: [UUID]
    public var disturbedDartIDs: [UUID]
    /// Fraction of the board disc whose colour changed after gain normalisation.
    public var changedBoardFraction: Double
    /// Area of the new object in mm².
    public var newObjectArea: Double
    /// Global brightness gain between reference and current.
    public var gain: Double
    public init(kind: Kind, darts: [DartCandidate] = [], removedDartIDs: [UUID] = [], disturbedDartIDs: [UUID] = [],
                changedBoardFraction: Double = 0, newObjectArea: Double = 0, gain: Double = 1)
}

/// The seam for detectors: the differencing detector today, a Core ML detector later.
public protocol DartDetecting: Sendable {
    var descriptor: DetectorDescriptor { get }
    /// True when the detector reads `DetectionRequest.sourceImage`.
    var needsSourceImage: Bool { get }
    func analyse(_ request: DetectionRequest) -> SceneAnalysis
}

/// Intermediate images of the differencing detector, for SnapshotTool and the debug overlay.
public struct DetectionDebug: Sendable {
    /// Shadow-tolerant evidence map (D2).
    public var evidence: GrayImage
    /// Binary mask after morphology (D3).
    public var mask: GrayImage
    /// Fitted axis segments in canvas pixels, one per candidate.
    public var axes: [(from: SIMD2<Double>, to: SIMD2<Double>)]
    /// Tips in canvas pixels, one per candidate.
    public var tips: [SIMD2<Double>]
    public var threshold: Double
}

/// Reference differencing in the canvas (section 5). The v1 detector.
public struct DifferencingDartDetector: DartDetecting {
    public init()
    public var descriptor: DetectorDescriptor { get }
    public var needsSourceImage: Bool { get }
    public func analyse(_ request: DetectionRequest) -> SceneAnalysis
    public func analyseWithDebug(_ request: DetectionRequest) -> (analysis: SceneAnalysis, debug: DetectionDebug)
}

/// One-dart check at setup (section 4.8): validates the chain with the player's darts and light, and sets the shadow bound.
public struct LightingCheckResult: Hashable, Sendable {
    public enum Verdict: Sendable { case verified, shadowTooHard, pointNotVisible, viewTooFrontal, failed }
    public var verdict: Verdict
    /// Distance between the detected tip and the tip the user tapped, mm.
    public var tipError: Double
    /// 5th percentile of the brightness ratio over shadow pixels; nil when fewer than 50 were found.
    public var shadowDepth: Double?
    public var recommendedShadowLowerBound: Double
}

public enum LightingCheck {
    public static func run(reference: CanvasImage, current: CanvasImage, confirmedTip: BoardPoint,
                           calibration: BoardCalibration, noiseSigma: Double,
                           parameters: DetectionParameters) -> LightingCheckResult
}

// MARK: - 6. Confidence and observations

public enum ConfidenceTier: Int, Codable, Sendable, Comparable {
    case low, medium, high
    public static func < (lhs: ConfidenceTier, rhs: ConfidenceTier) -> Bool
}

public struct ConfidenceThresholds: Hashable, Codable, Sendable {
    public var high: Double = 0.85
    public var medium: Double = 0.50
    public init()
    public static let standard: ConfidenceThresholds
    public func tier(for confidence: Double) -> ConfidenceTier
}

/// One scored hit and its probability.
public struct HitCandidate: Hashable, Sendable {
    public let hit: Hit
    public let probability: Double
    public init(hit: Hit, probability: Double)
}

/// Anisotropic Gaussian error of a tip, aligned with the dart axis.
public struct TipUncertainty: Hashable, Codable, Sendable {
    public var sigmaAlong: Double
    public var sigmaAcross: Double
    /// Unit vector along the dart axis in the board plane.
    public var axis: SIMD2<Double>
    public init(sigmaAlong: Double, sigmaAcross: Double, axis: SIMD2<Double>)
}

public enum ObservationSource: String, Codable, Sendable {
    /// Automatic trigger on live video.
    case liveCamera
    /// Manual trigger on the tripod ("Scanner la volée").
    case scan
    /// Hand-held photo pair, differenced in board space.
    case handheldPhoto
    /// The player tapped the tip on a rectified photo or on the evidence crop.
    case tappedOnPhoto
}

/// What DartVision hands to the game layer for one dart. Vision never touches game state.
public struct DartObservation: Identifiable, Hashable, Sendable {
    public let id: UUID
    /// Visit counter since arming.
    public let visit: Int
    /// 0-based index of the dart in its visit.
    public let indexInVisit: Int
    public let timestamp: TimeInterval
    /// Tip in nominal board mm.
    public let tip: BoardPoint
    public let uncertainty: TipUncertainty
    /// Descending probability, sums to 1, at most 6 entries, never empty.
    public let candidates: [HitCandidate]
    /// Distinct hits found around the tip, nearest first; completes the correction list.
    public let nearbyHits: [Hit]
    /// `P(best) * quality`, after caps.
    public let confidence: Double
    public let tier: ConfidenceTier
    public let flags: DartFlags
    public let source: ObservationSource
    /// Memberwise: stores its twelve parameters and nothing else. Used by `ConfidenceModel`, by tests,
    /// by fakes and by the Simulator demo. Declared in the struct body, never in an extension.
    public init(id: UUID, visit: Int, indexInVisit: Int, timestamp: TimeInterval, tip: BoardPoint,
                uncertainty: TipUncertainty, candidates: [HitCandidate], nearbyHits: [Hit], confidence: Double,
                tier: ConfidenceTier, flags: DartFlags, source: ObservationSource)
    /// `candidates[0].hit`.
    public var best: Hit { get }
    /// Candidates first, then `nearbyHits`, without duplicates, at least `minimum` entries when available.
    public func correctionChoices(minimum: Int = 4) -> [Hit]
    /// Game-aware tier, computed from stored fields only (section 7.4):
    /// `min(confidence * P(candidates with the outcome of the best) / P(best), cap(flags))`, then `thresholds.tier(for:)`.
    public func tier<Key: Hashable>(collapsingBy outcome: (Hit) -> Key,
                                    thresholds: ConfidenceThresholds = .standard) -> ConfidenceTier
}

/// Every constant of the confidence model (section 7).
public struct ConfidenceParameters: Hashable, Codable, Sendable {
    public var gridSide: Int = 21
    public var gridSpanSigmas: Double = 3
    public var minCalibrationSigma: Double = 0.3
    public var acrossPixelSigma: Double = 0.5
    public var alongPixelSigma: Double = 1.0
    public var hiddenTipLength: Double = 1.5
    public var hiddenTipLengthLowContrast: Double = 3.0
    public var occlusionSamples: Int = 5
    public var maxCandidates: Int = 6
    public var minCandidateProbability: Double = 0.01
    public var nearbyRadii: [Double] = [4, 8, 16]
    public var thresholds: ConfidenceThresholds = .init()
    public var severeFlagFactor: Double = 0.4
    public var occlusionFactor: Double = 0.6
    public var majorFlagFactor: Double = 0.5
    public var visitLimitFactor: Double = 0.6
    public var moderateFlagFactor: Double = 0.7
    public var minorFlagFactor: Double = 0.9
    public var poorCalibrationCap: Double = 0.80
    public var warmUpDarts: Int = 3
    public var warmUpCap: Double = 0.84
    public var crossViewpointCap: Double = 0.80
    public var trustWindow: Int = 15
    public var trustCorrectionsToDegrade: Int = 2
    public var degradedHighThreshold: Double = 0.95
    public var scanSuggestionWindow: Int = 12
    public var scanSuggestionRate: Double = 0.3
    public init()
}

/// Situation of the session when a dart is observed.
public struct ConfidenceContext: Sendable {
    /// Darts still to be capped after a calibration (0 once the one-dart check passed).
    public var warmUpRemaining: Int
    public var thresholds: ConfidenceThresholds
    /// Extra cap from the caller (1 = none).
    public var cap: Double
    public init(warmUpRemaining: Int = 0, thresholds: ConfidenceThresholds = .standard, cap: Double = 1)
}

public struct ConfidenceModel: Sendable {
    public init(board: BoardGeometry = .standard, parameters: ConfidenceParameters = .init())
    public func uncertainty(for candidate: DartCandidate, calibration: BoardCalibration) -> TipUncertainty
    /// Probability of each hit: midpoint rule on a `gridSide x gridSide` grid over ±`gridSpanSigmas` sigma.
    public func posterior(tip: BoardPoint, uncertainty: TipUncertainty, occlusionSpan: Double,
                          radii: RingRadii) -> [HitCandidate]
    /// Product of the flag factors and of the detector score (section 7.3), before caps.
    public func quality(flags: DartFlags, score: Double) -> Double
    public func observe(_ candidate: DartCandidate, id: UUID, visit: Int, indexInVisit: Int, timestamp: TimeInterval,
                        source: ObservationSource, calibration: BoardCalibration,
                        context: ConfidenceContext) -> DartObservation
    /// Observation for a tip given by the player (tap or drag): confidence 1, source `.tappedOnPhoto`.
    public func observation(forConfirmedTip tip: BoardPoint, id: UUID, visit: Int, indexInVisit: Int,
                            timestamp: TimeInterval) -> DartObservation
}

/// Tightens the high threshold when the player keeps correcting confident darts (section 7.6).
public struct TrustTracker: Sendable {
    public init(parameters: ConfidenceParameters = .init())
    public mutating func record(tier: ConfidenceTier, wasCorrected: Bool)
    public var thresholds: ConfidenceThresholds { get }
    public var accuracyDegraded: Bool { get }
    public var shouldSuggestScanMode: Bool { get }
}

// MARK: - 7. Gate, state machine, events

public enum ScanTrigger: String, Codable, Sendable {
    /// Darts are detected as they land.
    case automatic
    /// Nothing is processed between capture commands (`.captureReference`, `.captureNow`): section 6.3, rows DM1 to DM8.
    case manual
}

/// Every constant of the motion gate and of the state machine (section 6).
public struct ScanParameters: Hashable, Codable, Sendable {
    /// Trigger of a new state machine; `.setTrigger` changes it afterwards.
    public var trigger: ScanTrigger = .automatic
    public var expectedDartsPerVisit: Int = 3
    // Gate
    public var gateLongSide: Int = 320
    public var gatePixelDeltaFloor: Double = 12
    public var gatePixelDeltaSigmas: Double = 5
    public var gateBorderBand: Int = 6
    public var motionOnFraction: Double = 0.0012
    public var quietFraction: Double = 0.0005
    public var noLastingChangeFraction: Double = 0.0004
    // Settle
    public var skipFrames: Int = 2
    public var settleFrames: Int = 6
    public var armingFrames: Int = 12
    // Episodes
    public var throwMaxDuration: TimeInterval = 0.6
    public var handBorderFraction: Double = 0.04
    public var handSustainFrames: Int = 5
    // Timers (seconds of frame time)
    public var idleCheckInterval: TimeInterval = 2
    public var idleRefreshInterval: TimeInterval = 10
    public var obstructionEscalation: TimeInterval = 2
    public var obstructionAdvisoryDelay: TimeInterval = 10
    public var motionTimeout: TimeInterval = 8
    public var takeoutStallInterval: TimeInterval = 5
    public var relockRetryInterval: TimeInterval = 1
    /// Manual trigger: a capture that has not settled after this long is abandoned (row DM6).
    public var captureTimeout: TimeInterval = 2
    // Optional layers
    public var enableDriftCorrection: Bool = true
    public var relockCameraShiftLimit: Double = 30
    public var absoluteMatchRadius: Double = 8
    public init()
}

/// Per-frame measurements on the gate image (section 6.1).
public struct GateSample: Hashable, Sendable {
    public var timestamp: TimeInterval
    /// Fraction of gate pixels changed against the previous frame.
    public var motionFraction: Double
    /// Fraction changed against the gate image stored at the last settle.
    public var changeVsReference: Double
    /// Same, restricted to the band along the border of the gate region.
    public var borderChange: Double
    public var meanLuma: Double
    public init(timestamp: TimeInterval, motionFraction: Double, changeVsReference: Double, borderChange: Double, meanLuma: Double)
}

/// Cheap per-frame motion measurement on a small green-channel copy of the board region.
public struct MotionGate: Sendable {
    public init(calibration: BoardCalibration, parameters: ScanParameters = .init())
    public mutating func ingest(_ frame: Frame) -> GateSample
    public mutating func setReferenceToCurrent()
    /// Gate noise in levels, measured over the arming frames.
    public var noiseSigma: Double { get }
}

/// Who paused the state machine (section 6.3, rows P1 to P2c).
/// `.user`: the application (end of a game, end of the one-dart check, device moved); only `.arm` leaves that pause.
/// `.background`, `.thermal`: the system (scene phase, capture interruption, heat); `.resume` leaves it.
public enum PauseReason: Sendable { case user, background, thermal }

public enum ScanState: Hashable, Sendable {
    case needsCalibration
    /// Calibrated, not armed: frames are ignored until `.arm`, or until `.confirmBoardEmpty` after `needsEmptyBoard`.
    case idle
    /// Waiting for a still view to take the references and measure the noise.
    case arming
    /// Still view; `dartsOnBoard` darts are committed.
    case watching(dartsOnBoard: Int)
    case motion
    /// Quiet frames are being accumulated.
    case settling
    case analysing
    /// The visit is full or was ended early; waiting for the darts to be pulled.
    case awaitingTakeout
    /// A hand was seen and some darts are gone; waiting for an empty board.
    case takeout
    case obstructed
    case calibrationLost
    /// Carries the reason of the first pause; a later `.pause(.user)` replaces a system reason (rows P1 and P1b).
    case paused(PauseReason)
}

public enum ScanAdvisory: Sendable {
    case viewObstructed, accuracyDegraded, suggestScanMode, suggestLightingCheck, flicker, lowLight, thermalThrottling
}

public enum DartRemovalReason: Sendable {
    /// The dart left the board without a hand in view.
    case fellOut
    /// The dart was pulled.
    case takeout
}

public enum ScanEvent: Hashable, Sendable {
    case stateChanged(ScanState)
    case dart(DartObservation)
    /// An earlier dart moved when a new one landed; its score should be checked.
    case dartDisturbed(id: UUID)
    case dartRemoved(id: UUID, reason: DartRemovalReason)
    /// Throw-like motion and nothing stuck: bounce-out or miss. Never scored automatically.
    case possibleMiss(timestamp: TimeInterval)
    case takeoutStarted
    case takeoutStalled(remaining: [UUID])
    /// The board is empty again. A proposal for the game layer, which still needs its own `endTurn`.
    case takeoutCompleted
    /// Result of `.captureNow` in manual trigger mode: exactly one per accepted command, possibly empty, emitted last.
    case scanCompleted([DartObservation])
    case lightingChanged
    case unrecognizedChange
    /// References are unusable; the player must clear the board and confirm (`.confirmBoardEmpty`).
    /// Emitted right after `stateChanged(.idle)`.
    case needsEmptyBoard
    /// Emitted by `ScanEngine`, never by the reducer.
    case calibrationAdjusted(BoardCalibration)
    case calibrationLost
    /// Emitted by `ScanEngine`, never by the reducer.
    case calibrationRecovered(BoardCalibration)
    case advisory(ScanAdvisory)
}

public enum ScanCommand: Hashable, Sendable {
    /// Start of a game, from any calibrated state: clears references, silhouettes and counters, then takes the
    /// references. With `boardConfirmedEmpty == false` the empty reference stays unknown until `.confirmBoardEmpty`.
    /// The only command that leaves `paused(.user)`.
    case arm(boardConfirmedEmpty: Bool)
    case beginVisit(expectedDarts: Int)
    /// Bust or checkout: wait for the takeout, flag further darts `beyondVisitLimit`.
    case endVisit
    /// The player states that the board is empty now: the next settled frame becomes the empty reference.
    /// From `idle` (after `needsEmptyBoard`) it re-arms and resumes watching, counters kept (row P3).
    case confirmBoardEmpty
    /// Accept the current board as the baseline ("Continuer" after a stalled takeout or an unrecognised change).
    case rebaseline
    /// False positive: the footprint stays in the rolling reference, the count drops.
    case discardDart(UUID)
    /// The player added a dart that vision missed: only raises the count.
    case registerManualDart
    /// Survives `.arm`, `.pause` and `.resume` (rows DM1 and DM8).
    case setTrigger(ScanTrigger)
    /// Manual trigger, at rest: take the empty and rolling references from the next settled frames (row DM2).
    case captureReference
    /// Manual trigger, at rest: analyse the next settled frames for up to `maxDarts` new darts (row DM3).
    /// Ignored, without any event, when `maxDarts <= 0`; otherwise answered by exactly one `scanCompleted`.
    case captureNow(maxDarts: Int)
    /// Accepted in every state (rows P1 and P1b).
    case pause(PauseReason)
    /// Leaves a pause of reason `.background` or `.thermal` (rows P2, P2b, DM7); ignored in `paused(.user)` (row P2c).
    case resume
}

/// Summary of one motion episode, from the first motion frame to the settle.
public struct EpisodeSummary: Hashable, Sendable {
    public var duration: TimeInterval
    public var peakMotionFraction: Double
    /// Longest run of frames with `borderChange` above `handBorderFraction`.
    public var borderIntrusionFrames: Int
    public init(duration: TimeInterval, peakMotionFraction: Double, borderIntrusionFrames: Int)
    /// `duration > throwMaxDuration` or `borderIntrusionFrames >= handSustainFrames`.
    /// The reducer also treats every episode that started from `takeout` or `obstructed` as hand-like.
    public func isHandLike(_ parameters: ScanParameters) -> Bool
}

/// What the engine found on a settled frame, as seen by the reducer.
public enum SettleOutcome: Hashable, Sendable {
    case noChange
    case darts(new: [DartObservation], removed: [UUID], disturbed: [UUID])
    case removed([UUID], boardEmpty: Bool)
    case obstruction
    case lightingChanged
    case foreignRemoval
    case unrecognized
}

public enum ScanInput: Hashable, Sendable {
    case calibrationSet
    case gate(GateSample)
    case armed
    case settle(SettleOutcome, timestamp: TimeInterval)
    case calibrationHealth(CalibrationHealth.Status, recovered: Bool, timestamp: TimeInterval)
    case command(ScanCommand)
}

public enum ReferenceUpdate: Sendable {
    /// Rolling reference := current settled frame.
    case rolling
    /// Rolling and empty references := current settled frame; silhouettes cleared.
    case rollingAndEmpty
    /// Rolling reference := empty reference, no frame involved; silhouettes cleared (manual trigger, row DM4).
    case rollingFromEmpty
    case markEmptyStale
}

public enum ScanEffect: Hashable, Sendable {
    case beginAccumulation
    case discardAccumulation
    case analyse(maxNewDarts: Int)
    case checkCalibration
    case updateReference(ReferenceUpdate)
    case setGateReference
    case emit(ScanEvent)
}

/// Pure reducer: `(state, input) -> (state, effects)`. No clock, no I/O; time arrives in the inputs.
public struct ScanStateMachine: Sendable {
    public init(parameters: ScanParameters = .init())
    public var state: ScanState { get }
    /// Current trigger: `parameters.trigger` at first, then the last `.setTrigger`.
    public var trigger: ScanTrigger { get }
    /// Darts physically on the board (committed silhouettes).
    public var dartsOnBoard: Int { get }
    public var visit: Int { get }
    public var dartsInVisit: Int { get }
    public var lastEpisode: EpisodeSummary? { get }
    public mutating func handle(_ input: ScanInput) -> [ScanEffect]
}

// MARK: - 8. Engine and session

/// Root of all tunables; `Codable` so a tuning session can export and reload it as JSON.
public struct VisionConfiguration: Hashable, Codable, Sendable {
    public var calibration: CalibrationParameters = .init()
    public var detection: DetectionParameters = .init()
    public var confidence: ConfidenceParameters = .init()
    public var scan: ScanParameters = .init()
    public init()
}

/// Debug sink; every analysed scene can be replayed offline from what it stores.
public protocol ScanRecording: AnyObject, Sendable {
    func record(calibration: BoardCalibration)
    func record(reference: CanvasImage?, current: CanvasImage, analysis: SceneAnalysis, gate: [GateSample], at time: TimeInterval)
    func record(event: ScanEvent, at time: TimeInterval)
    /// A player correction: the original observation and the corrected tip (nil when the dart was a phantom).
    func record(correctionOf observation: DartObservation, correctedTip: BoardPoint?)
}

public struct ScanDebugSnapshot: Sendable {
    public var state: ScanState
    public var lastGate: GateSample?
    public var lastAnalysis: SceneAnalysis?
    public var lastHealth: CalibrationHealth?
    public var lastDetectionDebug: DetectionDebug?
    public var noiseSigma: Double
}

/// Synchronous, deterministic core: gate, reducer, rectifier, detector, confidence. Not thread-safe.
/// Time comes only from frame timestamps. This is the type the tests drive.
public final class ScanEngine {
    public init(detector: any DartDetecting = DifferencingDartDetector(), board: BoardGeometry = .standard,
                calibrator: BoardCalibrator = .init(), locator: (any BoardLocating)? = nil,
                configuration: VisionConfiguration = .init(), recorder: (any ScanRecording)? = nil)
    public var state: ScanState { get }
    public var calibration: BoardCalibration? { get }
    /// Darts physically on the board, oldest first.
    public var dartsOnBoard: [DartObservation] { get }
    public var configuration: VisionConfiguration { get set }
    public func setCalibration(_ calibration: BoardCalibration) -> [ScanEvent]
    public func process(_ frame: Frame) -> [ScanEvent]
    public func handle(_ command: ScanCommand) -> [ScanEvent]
    /// The player dragged the tip on the evidence crop: re-scores the dart from the new tip (confidence 1).
    public func correct(_ id: UUID, tip: BoardPoint) -> DartObservation?
    /// Feeds `TrustTracker` and the recorder. Call once per camera dart when its visit is confirmed.
    public func recordFeedback(_ id: UUID, wasCorrected: Bool)
    /// Rectified crop around a dart of the current visit, with nothing drawn on it.
    public func evidenceCrop(for id: UUID, span: Double, scale: Double) -> RGBImage?
    /// One-dart check: compares the latest dart with the tip the player tapped and adopts the recommended shadow bound.
    public func runLightingCheck(confirmedTip: BoardPoint) -> LightingCheckResult?
    public func debugSnapshot() -> ScanDebugSnapshot
}

/// Static description of a frame source.
public struct FrameSourceInfo: Hashable, Sendable {
    public var size: PixelSize
    public var nominalFramesPerSecond: Double
    /// Rotation applied to the delivered buffers: 0, 90, 180 or 270.
    public var rotationDegrees: Int
    public var intrinsics: CameraIntrinsics?
    public var isLive: Bool
    public init(size: PixelSize, nominalFramesPerSecond: Double, rotationDegrees: Int, intrinsics: CameraIntrinsics?, isLive: Bool)
}

/// Anything that delivers frames: the camera, a synthetic script, a recorded sequence.
public protocol FrameSource: AnyObject, Sendable {
    /// Nil until the source has started.
    var info: FrameSourceInfo? { get }
    /// `handler` is called on `queue`; each frame is valid only during the call.
    func start(on queue: DispatchQueue, handler: @escaping @Sendable (Frame) -> Void) async throws
    func stop() async
}

/// Camera controls the session needs; implemented by `CameraFrameSource`, absent on synthetic sources.
public protocol CameraControlling: AnyObject, Sendable {
    /// Lets focus, exposure and white balance converge, then locks all three. Returns false when a lock is unsupported.
    func lockFocusExposureWhiteBalance() async throws -> Bool
    func unlock() async
}

/// Thin concurrency wrapper: one serial queue, one frame source, one engine, one stream of events.
public final class ScanSession: @unchecked Sendable {
    public init(source: any FrameSource, makeEngine: @escaping @Sendable () -> ScanEngine)
    public var events: AsyncStream<ScanEvent> { get }
    public func start() async throws
    public func stop() async
    /// Mean of the next `frames` frames at full resolution: the frozen still for the calibration screen.
    public func captureStill(averaging frames: Int = 8) async throws -> RGBImage
    public func setCalibration(_ calibration: BoardCalibration) async
    public func send(_ command: ScanCommand) async
    public func correct(_ id: UUID, tip: BoardPoint) async -> DartObservation?
    public func recordFeedback(_ id: UUID, wasCorrected: Bool) async
    public func evidenceCrop(for id: UUID, span: Double = 50, scale: Double = 6) async -> CGImage?
    public func runLightingCheck(confirmedTip: BoardPoint) async -> LightingCheckResult?
    public func updateConfiguration(_ configuration: VisionConfiguration) async
    public func currentState() async -> ScanState
    public func debugSnapshot() async -> ScanDebugSnapshot
}

// MARK: - 9. Frame sources

/// A fixed list of images: tests and replay of recorded stills.
public final class SequenceFrameSource: FrameSource, @unchecked Sendable {
    public init(frames: [RGBImage], framesPerSecond: Double = 30, intrinsics: CameraIntrinsics? = nil)
    public var info: FrameSourceInfo? { get }
    /// Synchronous stepping for deterministic tests; nil at the end.
    public func nextFrame() -> Frame?
    public func start(on queue: DispatchQueue, handler: @escaping @Sendable (Frame) -> Void) async throws
    public func stop() async
}

#if canImport(AVFoundation)
public struct CameraConfiguration: Hashable, Sendable {
    public enum Preset: Sendable { case hd1080, uhd4K }
    public enum MainsFrequency: Sendable { case hz50, hz60 }
    public var preset: Preset = .uhd4K
    public var framesPerSecond: Int = 30
    /// Default: from the locale's region.
    public var mainsFrequency: MainsFrequency?
    /// Seconds of auto convergence before the lock.
    public var lockDelay: TimeInterval = 1.5
    public init()
}

/// The only AVFoundation code of the package. iOS-only controls sit behind `#if os(iOS)` inside;
/// on macOS it compiles as a plain webcam source.
public final class CameraFrameSource: NSObject, FrameSource, CameraControlling,
                                      AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    public init(configuration: CameraConfiguration = .init())
    public static func requestAccess() async -> Bool
    /// For `AVCaptureVideoPreviewLayer` in DartUI.
    public var captureSession: AVCaptureSession { get }
    public var info: FrameSourceInfo? { get }
    public func start(on queue: DispatchQueue, handler: @escaping @Sendable (Frame) -> Void) async throws
    public func stop() async
    public func lockFocusExposureWhiteBalance() async throws -> Bool
    public func unlock() async
}
#endif

/// Writes one directory per session: `calibration.json`, `events.jsonl`, `gate.jsonl`, `corrections.jsonl`
/// and, per analysed scene, `NNNN-reference.png`, `NNNN-current.png`, `NNNN-analysis.json`.
public final class DirectoryRecorder: ScanRecording, @unchecked Sendable {
    public init(directory: URL) throws
    public func record(calibration: BoardCalibration)
    public func record(reference: CanvasImage?, current: CanvasImage, analysis: SceneAnalysis, gate: [GateSample], at time: TimeInterval)
    public func record(event: ScanEvent, at time: TimeInterval)
    public func record(correctionOf observation: DartObservation, correctedTip: BoardPoint?)
}

/// Reads a `DirectoryRecorder` directory back for offline tuning on macOS.
public struct RecordedSession: Sendable {
    public struct Scene: Sendable {
        public var time: TimeInterval
        public var reference: CanvasImage?
        public var current: CanvasImage
        public var gate: [GateSample]
    }
    public init(directory: URL) throws
    public var calibration: BoardCalibration { get }
    public var scenes: [Scene] { get }
    /// Runs a detector over every recorded scene with the given parameters.
    public func replay(detector: any DartDetecting, parameters: DetectionParameters, noiseSigma: Double) -> [SceneAnalysis]
}

// MARK: - 10. Photo mode

/// Scoring from stills (section 8). No state, no camera.
public struct PhotoScorer: Sendable {
    public init(detector: any DartDetecting = DifferencingDartDetector(), confidence: ConfidenceModel = .init())
    /// Rectified, zoomable view of a calibrated photo for tap-the-tips.
    public func rectified(_ photo: RGBImage, calibration: BoardCalibration) -> CanvasImage
    /// The player tapped a tip on the photo (image pixels): the guaranteed path.
    public func observation(forTappedTip point: ImagePoint, calibration: BoardCalibration, visit: Int,
                            indexInVisit: Int) -> DartObservation
    /// Optional layer: differences a calibrated photo against an empty-board canvas taken from another viewpoint.
    /// Every result is flagged `crossViewpoint` and capped below the high tier.
    public func score(photo: RGBImage, calibration: BoardCalibration, emptyReference: CanvasImage, maxDarts: Int = 3,
                      parameters: DetectionParameters = .default) -> [DartObservation]
}

// MARK: - 11. Synthetic rendering (tests, SnapshotTool, Simulator demo mode)

/// A pinhole camera placed in the board frame. Ground truth for every synthetic test.
public struct SyntheticCamera: Hashable, Sendable {
    public var imageSize: PixelSize
    public var intrinsics: CameraIntrinsics
    /// Camera centre in the board frame, mm (z > 0).
    public var position: SIMD3<Double>
    public var lookAt: BoardPoint
    public var rollDegrees: Double
    public init(imageSize: PixelSize, longSideFieldOfViewDegrees: Double = 67, position: SIMD3<Double>,
                lookAt: BoardPoint = BoardPoint(x: 0, y: 0), rollDegrees: Double = 0)
    /// H = K [r1 r2 t].
    public var boardToImage: Homography { get }
    public func project(_ point: SIMD3<Double>) -> ImagePoint
    /// Projection of the four handle junctions. Built with `CalibrationHandles(points:)` from
    /// `CalibrationHandle.boardPoint` and `project(_:)`: no call into lot V2 (section 10.1).
    public func exactHandles() -> CalibrationHandles
    /// The exact calibration of this camera, built from the ground truth without any image and without
    /// `BoardCalibrator` (section 10.1). This is how every test gets a `BoardCalibration` when the calibrator
    /// is not what it tests. `grade` is imposed, not derived from the pose.
    public func calibration(grade: CalibrationQuality.Grade = .good) -> BoardCalibration
    /// A bumped tripod: the camera centre moves by `delta` mm and rolls by `rollDegrees` more.
    public func moved(by delta: SIMD3<Double>, rollDegrees: Double) -> SyntheticCamera
}

public struct SyntheticDartStyle: Hashable, Sendable {
    public var point: SIMD3<UInt8>
    public var barrel: SIMD3<UInt8>
    public var shaft: SIMD3<UInt8>
    public var flight: SIMD3<UInt8>
    public init(point: SIMD3<UInt8>, barrel: SIMD3<UInt8>, shaft: SIMD3<UInt8>, flight: SIMD3<UInt8>)
    public static let steelTungsten: SyntheticDartStyle
    public static let brass: SyntheticDartStyle
    /// Black point, barrel and shaft: the case that breaks naive differencing on black sectors.
    public static let allBlack: SyntheticDartStyle
}

public struct SyntheticDart: Hashable, Sendable {
    /// Entry point on the board plane, metric mm.
    public var tip: BoardPoint
    /// Tail-up lean in degrees (positive: the flight is higher than the tip).
    public var leanUpDegrees: Double
    public var leanSideDegrees: Double
    public var style: SyntheticDartStyle
    public init(tip: BoardPoint, leanUpDegrees: Double = 8, leanSideDegrees: Double = 0, style: SyntheticDartStyle = .steelTungsten)
}

public struct SyntheticScene: Sendable {
    public var darts: [SyntheticDart] = []
    public var radii: RingRadii = .nominal
    /// Height of the wires above the board plane, mm: they are rendered as flat ribbons in the plane z = wireHeight.
    public var wireHeight: Double = 0
    /// Point light in the board frame, mm; nil means no cast shadows.
    public var light: SIMD3<Double>?
    /// Brightness ratio inside shadows (1 = no shadow, 0.65 = soft, 0.35 = hard).
    public var shadowStrength: Double = 1
    public var gain: Double = 1
    /// Gaussian noise sigma in levels.
    public var noiseSigma: Double = 2
    /// Number of 3x3 box blur passes.
    public var blurPasses: Int = 1
    /// Whole-image shift in px (sub-pixel jitter).
    public var shift: SIMD2<Double> = .zero
    /// A skin-coloured disc above the board plane: centre and radius in mm.
    public var hand: (centre: BoardPoint, radius: Double)?
    public var seed: UInt64 = 1
    public init()
    /// Camera image (ray caster, 3x3 supersampling).
    public func render(camera: SyntheticCamera) -> RGBImage
    /// The same scene rendered directly in the canvas, for stage tests without a rectifier.
    public func renderCanvas(camera: SyntheticCamera) -> CanvasImage
}

/// A timeline of events rendered at a fixed frame rate.
public struct SyntheticScript: Sendable {
    public enum Step: Sendable {
        case wait(TimeInterval)
        /// Two motion-blurred frames, four frames of decaying vibration, then the dart at rest.
        case throwDart(SyntheticDart)
        /// Three frames of motion, then back to the previous scene.
        case bounceOut
        case handRest(TimeInterval)
        /// A hand covers the board for `duration`, then every dart is gone.
        case takeout(duration: TimeInterval)
        case fallOut(index: Int)
        case bump(delta: SIMD3<Double>, rollDegrees: Double)
        case lightStep(gain: Double)
        case lightRamp(gain: Double, duration: TimeInterval)
    }
    public init(_ steps: [Step], framesPerSecond: Double = 30)
}

public final class SyntheticFrameSource: FrameSource, @unchecked Sendable {
    public init(script: SyntheticScript, camera: SyntheticCamera, scene: SyntheticScene = .init(), realTime: Bool = false)
    public var info: FrameSourceInfo? { get }
    /// Synchronous stepping for deterministic tests; nil at the end of the script.
    public func nextFrame() -> Frame?
    public func start(on queue: DispatchQueue, handler: @escaping @Sendable (Frame) -> Void) async throws
    public func stop() async
}
```

### 9.3 Fichiers et dépendances

Chaque nom ci-dessous est un fichier `.swift`.

```
Sources/DartVision/
  Geometry/     Homography, LinearSolve, CameraIntrinsics, CameraPose, RingRadii, BoardModel
  Imaging/      PixelTypes, Frame, Morphology, ConnectedComponents, CanvasMask
  Calibration/  CalibrationHandles, EdgeSampler, HandleRefiner, BoardCalibration, BoardCalibrator,
                ConicFit, ColourBoardLocator, LightingCheck
  Canvas/       BoardCanvas, BoardRectifier, FrameAccumulator
  Detection/    DetectionParameters, DartDetecting, ChangeEvidence, BlobAnalysis, TipEstimator, DifferencingDartDetector
  Confidence/   ConfidenceModel, DartObservation, TrustTracker
  Scan/         ScanEvents, MotionGate, ScanStateMachine, ScanEngine, ScanSession
  Capture/      FrameSource, SequenceFrameSource, CameraFrameSource (seul fichier AVFoundation),
                DirectoryRecorder, RecordedSession
  Photo/        PhotoScorer
  Synthetic/    SyntheticCamera, SyntheticBoard, SyntheticDart, SyntheticScene, SyntheticScript, SyntheticFrameSource
  DartCoreBridge.swift
```

- Frameworks : Foundation, simd, CoreGraphics et ImageIO (conversion `CGImage`, PNG), CoreVideo (`Frame`), AVFoundation (un fichier).
- Pas de Vision, pas de Core Image, pas d'Accelerate dans le cœur. Une optimisation vImage ou vDSP pourra remplacer une boucle plus tard, à condition que les tests restent identiques.
- `DartVision` n'importe ni `DartGames`, ni `DartAudio`, ni `DartUI`.

**Répartition des types publics.** Chaque type public du listing vit dans le fichier indiqué, avec ses types imbriqués et tous ses membres. La colonne de droite donne le lot de `ARCHITECTURE.md` §13.2 qui possède ce fichier en exclusivité.

| Fichier | Types publics du listing 9.2 | Lot |
|---|---|---|
| `Imaging/PixelTypes.swift` | `PixelSize`, `ImagePoint`, `RGBImage`, `GrayImage` | V1 |
| `Imaging/Frame.swift` | `FramePixelFormat`, `Frame` | V1 |
| `Imaging/CanvasMask.swift` | `CanvasMask` | V1 |
| `Geometry/Homography.swift` | `Homography` | V1 |
| `Geometry/CameraIntrinsics.swift` | `CameraIntrinsics` | V1 |
| `Geometry/CameraPose.swift` | `CameraPose` | V1 |
| `Geometry/RingRadii.swift` | `RingRadii` | V1 |
| `Canvas/BoardCanvas.swift` | `BoardCanvas`, `CanvasImage` | V1 |
| `Canvas/BoardRectifier.swift` | `BoardRectifier` | V1 |
| `Canvas/FrameAccumulator.swift` | `FrameAccumulator` | V1 |
| `Synthetic/SyntheticCamera.swift` | `SyntheticCamera`, y compris `calibration(grade:)` | V1 |
| `Synthetic/SyntheticDart.swift` | `SyntheticDartStyle`, `SyntheticDart` | V1 |
| `Synthetic/SyntheticScene.swift` | `SyntheticScene` | V1 |
| `Synthetic/SyntheticScript.swift` | `SyntheticScript` | V1 |
| `Synthetic/SyntheticFrameSource.swift` | `SyntheticFrameSource` | V1 |
| `Calibration/CalibrationHandles.swift` | `CalibrationHandle`, `CalibrationHandles` | V2 |
| `Calibration/BoardCalibration.swift` | `CalibrationIssue`, `CalibrationQuality`, `BoardWireframe`, `BoardCalibration` | V2 |
| `Calibration/BoardCalibrator.swift` | `CalibrationParameters`, `CalibrationError`, `CalibrationHealth`, `BoardCalibrator` | V2 |
| `Calibration/ColourBoardLocator.swift` | `BoardLocation`, `BoardLocating`, `ColourBoardLocator` | V2 |
| `Calibration/LightingCheck.swift` | `LightingCheckResult`, `LightingCheck` | V3 |
| `Detection/DetectionParameters.swift` | `DetectionParameters` | V3 |
| `Detection/DartDetecting.swift` | `DartFlags`, `DartCandidate`, `KnownDart`, `DetectorDescriptor`, `DetectionRequest`, `SceneAnalysis`, `DartDetecting` | V3 |
| `Detection/DifferencingDartDetector.swift` | `DetectionDebug`, `DifferencingDartDetector` | V3 |
| `Confidence/DartObservation.swift` | `ConfidenceTier`, `ConfidenceThresholds`, `HitCandidate`, `TipUncertainty`, `ObservationSource`, `DartObservation` | V3 |
| `Confidence/ConfidenceModel.swift` | `ConfidenceParameters`, `ConfidenceContext`, `ConfidenceModel` | V3 |
| `Confidence/TrustTracker.swift` | `TrustTracker` | V3 |
| `Scan/ScanEvents.swift` | `ScanTrigger`, `ScanParameters`, `GateSample`, `PauseReason`, `ScanState`, `ScanAdvisory`, `DartRemovalReason`, `ScanEvent`, `ScanCommand`, `EpisodeSummary`, `SettleOutcome`, `ScanInput`, `ReferenceUpdate`, `ScanEffect` | V4 |
| `Scan/ScanStateMachine.swift` | `ScanStateMachine` | V4 |
| `Scan/MotionGate.swift` | `MotionGate` | V5 |
| `Scan/ScanEngine.swift` | `VisionConfiguration`, `ScanRecording`, `ScanDebugSnapshot`, `ScanEngine` | V5 |
| `Scan/ScanSession.swift` | `ScanSession` | V5 |
| `Capture/FrameSource.swift` | `FrameSourceInfo`, `FrameSource`, `CameraControlling` | V5 |
| `Capture/SequenceFrameSource.swift` | `SequenceFrameSource` | V5 |
| `Capture/CameraFrameSource.swift` | `CameraConfiguration`, `CameraFrameSource`, tout le fichier sous `#if canImport(AVFoundation)` | V5 |
| `Capture/DirectoryRecorder.swift` | `DirectoryRecorder` | V5 |
| `Capture/RecordedSession.swift` | `RecordedSession` | V5 |
| `Photo/PhotoScorer.swift` | `PhotoScorer` | V3 |

Les autres fichiers ne contiennent que du code `internal` : `Geometry/LinearSolve`, `Geometry/BoardModel`, `Imaging/Morphology`, `Imaging/ConnectedComponents`, `Synthetic/SyntheticBoard` et `DartCoreBridge` (V1) ; `Calibration/EdgeSampler`, `HandleRefiner`, `ConicFit` (V2) ; `Detection/ChangeEvidence`, `BlobAnalysis`, `TipEstimator` (V3).

**Noms.** Les cinq lots de la vision se compilent dans un seul module, et deux lots d'une même vague ne voient pas les fichiers l'un de l'autre. Les fichiers qu'un lot ajoute, les symboles `internal` qu'il déclare, ses extensions et ses tests suivent donc la règle de noms de `ARCHITECTURE.md` §13.4, qui donne le préfixe de chaque lot.

Ce découpage garantit quatre choses aux lots qui travaillent en parallèle :

- **Le réducteur ne dépend d'aucun lot ultérieur.** `ScanEvents.swift` contient tous les types que `ScanStateMachine` et ses tests manipulent, dont `GateSample`, `ScanParameters` et `EpisodeSummary` ; rien ne vient de `MotionGate.swift` ni de `ScanEngine.swift`. Les tests du réducteur fabriquent leurs `DartObservation` par l'initialiseur membre à membre (section 9.4) et n'ont besoin d'aucune valeur de `BoardCalibration`, puisque les deux événements qui en transportent une sont émis par le moteur (section 6). Ils comparent états, commandes, effets et événements par `==` : `ScanState`, `ScanCommand`, `ScanEvent`, `ScanInput`, `SettleOutcome`, `ScanEffect` et `DartObservation` sont `Hashable` dans le listing.
- **Un calibrage existe sans le calibreur.** `SyntheticCamera.calibration(grade:)` (section 10.1) fabrique `BoardCalibration` et `CalibrationQuality` par leur initialiseur membre à membre synthétisé, interne au module. Les structures sans initialiseur public (`BoardCalibration`, `CalibrationQuality`, `BoardWireframe`, `CalibrationHealth`, `BoardLocation`, `DetectionDebug`, `LightingCheckResult`, `ScanDebugSnapshot`, `RecordedSession.Scene`) gardent donc cet initialiseur : aucun lot ne déclare d'`init` dans le corps de ces structures, ce qui le supprimerait. Un `init` déclaré en extension reste permis ; dans un fichier d'un autre lot que celui de la structure, il est `fileprivate` (`ARCHITECTURE.md` §13.4). `exactHandles()` et `calibration(grade:)` n'appellent aucun membre de `Calibration/` hors des membres de simple donnée de 9.4 : les poignées exactes se construisent par `CalibrationHandles(points:)`, jamais par `CalibrationHandles(projecting:)`, dont le corps appartient au lot V2 et plante dans le squelette. Plus généralement, le lot V1 ne lit d'un calibrage que ses champs stockés, `BoardRectifier` compris : ni ses fichiers ni ses tests n'ont besoin d'un corps écrit par un lot ultérieur.
- **La détection et la confiance n'attendent pas le calibrage.** Elles ne lisent que les champs stockés de `BoardCalibration` (`boardToImage`, `imageToBoard`, `ringRadii`, `wireHeight`, `pose`, `quality`) et les types de géométrie ; elles n'appellent aucune de ses méthodes (D10, section 7.1).
- **Le chemin photo garanti n'attend pas le moteur.** `PhotoScorer` appartient au lot V3 : il ne lui faut que le détecteur et `ConfidenceModel` (V3), `BoardRectifier` et les types de géométrie (V1), et les champs stockés du calibrage, lus comme en D10. Il n'utilise ni la porte, ni `ScanEngine`, ni `ScanSession`. Le mode photo de `DartUI`, qui se développe pendant que le lot V5 écrit le moteur, dispose ainsi d'un vrai `PhotoScorer.observation(forTappedTip:…)`.

### 9.4 Membres de simple donnée

Les lots partent d'un squelette du listing où les membres algorithmiques sont des `fatalError`. Ce squelette n'est utilisable que si les valeurs de simple donnée se construisent pour de bon : un test du réducteur fabrique des `GateSample` et des `DartObservation`, et `VisionConfiguration()` sert de valeur par défaut à d'autres cibles. Les membres ci-dessous ne contiennent aucun algorithme. **Leur corps est entièrement déterminé par le listing : le squelette l'écrit tel quel, et aucun lot ne change ensuite leur comportement.**

| Catégorie | Corps | Membres |
|---|---|---|
| Initialiseur qui range ses paramètres | `self.x = x` pour chaque paramètre, rien d'autre (une précondition sur `pixels.count` est admise pour les deux images) | `PixelSize.init(width:height:)` ; `ImagePoint.init(x:y:)` ; `RGBImage.init(width:height:pixels:)` ; `GrayImage.init(width:height:pixels:)` ; `CameraIntrinsics.init(fx:fy:cx:cy:source:)` ; `RingRadii.init(innerBull:outerBull:trebleInner:trebleOuter:doubleInner:doubleOuter:)` ; `CalibrationHandles.init(points:)` ; `CanvasImage.init(rgb:valid:)` ; `DartFlags.init(rawValue:)` ; `DartCandidate.init(tip:axis:silhouette:…)` ; `KnownDart.init(id:tip:silhouette:)` ; `DetectorDescriptor.init(name:version:mode:)` ; `DetectionRequest.init(current:reference:…)` ; `SceneAnalysis.init(kind:…)` ; `HitCandidate.init(hit:probability:)` ; `TipUncertainty.init(sigmaAlong:sigmaAcross:axis:)` ; `DartObservation.init(id:visit:…source:)` ; `ConfidenceContext.init(warmUpRemaining:thresholds:cap:)` ; `GateSample.init(timestamp:…)` ; `EpisodeSummary.init(duration:peakMotionFraction:borderIntrusionFrames:)` ; `FrameSourceInfo.init(size:…)` ; `SyntheticDartStyle.init(point:barrel:shaft:flight:)` ; `SyntheticDart.init(tip:leanUpDegrees:leanSideDegrees:style:)` |
| `init()` d'une structure dont toutes les propriétés stockées ont une valeur par défaut | corps vide | `CalibrationParameters` ; `ColourBoardLocator.Parameters` ; `DetectionParameters` ; `ConfidenceThresholds` ; `ConfidenceParameters` ; `ScanParameters` ; `VisionConfiguration` ; `CameraConfiguration` ; `SyntheticScene` |
| Constante | la valeur indiquée | `BoardCanvas.pixelsPerMillimetre`, `halfExtent` et `side` (valeurs du listing) ; `RingRadii.nominal` = 6,35 / 15,9 / 99 / 107 / 162 / 170 ; `DetectionParameters.default` = `DetectionParameters()` ; `ConfidenceThresholds.standard` = `ConfidenceThresholds()` ; les dix-neuf options de `DartFlags`, chacune `DartFlags(rawValue: 1 << i)` où `i` est son rang dans le listing à partir de 0 |
| Table constante par cas | la valeur du commentaire du listing | `CalibrationHandle.boardPoint` ; `CalibrationHandle.label` ; `CalibrationIssue.isBlocking` (vrai pour les cinq premiers cas) |
| `Comparable` | `lhs.rawValue < rhs.rawValue` | `CalibrationQuality.Grade` ; `ConfidenceTier` |

- `Codable`, `Hashable` et `Equatable` sont synthétisés par le compilateur partout où le listing les déclare sans membre. Une énumération sans valeur associée (`PauseReason`, `ScanAdvisory`, `DartRemovalReason`, `ReferenceUpdate`, `CalibrationHealth.Status`, `SceneAnalysis.Kind`…) est `Hashable` d'office.
- Les valeurs que les tests obligatoires comparent par `==` sont `Hashable` dans le listing : `ScanState`, `ScanCommand`, `ScanEvent`, `ScanInput`, `SettleOutcome`, `ScanEffect`, `DartObservation`, `BoardCalibration`, et `CalibrationError` (`Equatable`). **Aucun lot n'ajoute de conformité à un type du listing**, ni dans les sources ni dans les tests : une conformité vaut pour tout le module, et deux lots qui écriraient la même se heurteraient à la fusion (`ARCHITECTURE.md` §13.4).
- `DartObservation.init` est déclaré **dans le corps** de la structure. Sa liste de paramètres est celle des propriétés stockées : le déclarer en extension entrerait en collision avec l'initialiseur synthétisé et ne compilerait pas.
- Tout autre membre appartient au lot de son fichier, qui en écrit le corps. Ne sont donc **pas** de simple donnée, même courts : les initialiseurs qui calculent (`ImagePoint.init(normalized:in:)`, `RGBImage.init(width:height:fill:)`, `GrayImage.init(width:height:fill:)`, `Homography.init(_:)`, `CameraIntrinsics.init(longSideFieldOfViewDegrees:imageSize:)`, `CalibrationHandles.init(projecting:)`, `CameraPose.init?`, `SyntheticCamera.init`) ; les initialiseurs des types dont l'état est privé (`CanvasMask`, `BoardRectifier`, `FrameAccumulator`, `BoardCalibrator`, `ColourBoardLocator`, `DifferencingDartDetector`, `ConfidenceModel`, `TrustTracker`, `MotionGate`, `ScanStateMachine`, `ScanEngine`, `ScanSession`, `PhotoScorer`, `SyntheticScript`, les sources d'images, l'enregistreur et le rejeu) ; `Homography.identity` et les trois styles de `SyntheticDartStyle`, dont la valeur est écrite par le lot V1 ; et toutes les propriétés calculées qui ne figurent pas dans la table.

---

## 10. Banc d'essai synthétique et tests

Tests en Swift Testing (`import Testing`, `@Test`, `#expect`), exécutés sur macOS par `swift test`. Tout aléa vient d'un générateur SplitMix64 à graine fixe.

### 10.1 Moteur de rendu (`Synthetic/`, public)

Il sert aux tests, à `SnapshotTool` et au mode démonstration du Simulateur. C'est un petit lanceur de rayons analytique, sans Core Graphics, donc déterministe.

- **Caméra** (`SyntheticCamera`) : `K` d'après la taille d'image et le champ du grand côté ; position `C` dans le repère de la cible, point visé, roulis. `avant = normaliser(visé − C)`, `droite = normaliser(avant × (0, 1, 0))`, `bas = avant × droite`, roulis appliqué, `R = [droite ; bas ; avant]` (lignes), `t = −R·C`, `H = K·[r1 r2 t]`. C'est la vérité terrain de tous les tests [sonde : conventions vérifiées].
- **Calibrage exact** (`SyntheticCamera.calibration(grade:)`) : un `BoardCalibration` construit directement depuis cette vérité terrain, sans image et sans `BoardCalibrator`. **C'est par lui que tout test obtient un calibrage quand le calibreur n'est pas ce qu'il teste** : tests R, E, T, F, X et P de ce document, tests et instantanés de `DartUI`. Seuls les tests C et L appellent le calibreur. Ses champs sont fixés ici pour que tous les lots voient la même valeur :
  - `id = UUID(uuidString: "00000000-0000-0000-0000-000000000001")` et `createdAt = Date(timeIntervalSinceReferenceDate: 0)` : deux appels rendent des valeurs égales ;
  - `imageSize` et `intrinsics` de la caméra ; `rotationDegrees = 0` ;
  - `userHandles = handles = exactHandles()` ; `boardToImage` = la vraie `H` ; `imageToBoard` = son inverse ;
  - `exactHandles()` se calcule avec les seuls membres de simple donnée : `CalibrationHandles(points: CalibrationHandle.allCases.map { project(SIMD3($0.boardPoint.x, $0.boardPoint.y, 0)) })`. Il NE DOIT PAS appeler `CalibrationHandles(projecting:)`, dont le corps appartient au lot V2 (vague 2) et plante dans le squelette : les tests M10, M12 et R1 du lot V1 tournent ainsi dès la vague 1. Pour la même raison, le lot V1 et ses tests lisent les poignées par `points`, dans l'ordre de `CalibrationHandle.allCases` : l'indice `handles[.wire20_1]` et les autres méthodes de `CalibrationHandles` sont des corps du lot V2 ;
  - `ringRadii = .nominal` ; `wireHeight = 0` ; `pose = CameraPose(boardToImage:intrinsics:)`, donc exacte ;
  - `quality.grade` = le grade demandé. Il est **imposé**, pas déduit de la pose : une pose quelconque sert ainsi à tester ce qui dépend du grade (drapeaux `calibrationFair` et `calibrationPoor`, plafond de confiance) ;
  - pour `good` / `fair` / `poor` : `edgeResidualRMS` = 0,2 / 0,5 / 0,9 mm (soit `σ_cal` = 0,3 / 0,5 / 0,9), `refinementApplied` = vrai / vrai / faux, `issues` = `[]` / `[]` / `[.refinementRejected]` ;
  - `edgeInlierFraction = measuredFraction = 1` ; `maxHandleShift = 0` ; `minPixelsPerMillimetre` (au bull et aux 8 points de r = 170 d'angle 45°·k), `viewAngleDegrees = atan(‖F‖/D)`, `minTanObliquity` et `maxTanObliquity` calculés sur la vraie géométrie avec les formules de la section 4.7.
- **Cible** : pour chaque rayon de pixel (3×3 suréchantillonnage), intersection avec le plan `z = 0`, puis couleur d'après le modèle analytique.
  - noir (30, 30, 30), crème (225, 205, 165), rouge (200, 40, 40), vert (30, 140, 70) ;
  - fils de 1,4 mm (190, 190, 190) sur les six rayons et les vingt fils radiaux de 15,9 à 170 mm. Ce sont des rubans plats dans le plan `z = SyntheticScene.wireHeight` : le rayon d'un pixel est d'abord coupé avec ce plan, et il ne continue jusqu'à `z = 0` que s'il n'y touche aucun fil. Avec la valeur par défaut 0, les fils sont dans le plan de la cible ; avec une valeur positive ils sont en relief et montrent la parallaxe de la section 4.6 ;
  - couronne des numéros noire (25, 25, 25) jusqu'à 225,5 mm ; mur (120, 120, 125) ;
  - les rayons viennent de `SyntheticScene.radii`, ce qui permet de rendre une cible hors cotes.
- **Fléchettes** : pièces 3D le long d'un axe partant de la pointe, avec inclinaison vers le haut et sur le côté.
  - pointe Ø 2,3 × 22 mm visible (plus 8 mm plantés, coupés par le plan) ; fût Ø 6,8 × 50 ; tige Ø 5,2 × 43 ; empennage : deux plaques perpendiculaires de 40 × 34 mm, épaisses de 0,3 mm ;
  - un pixel est « fléchette » quand son rayon rencontre une pièce : chaque pièce est un cylindre plein à bouts plats (pointe de −8 à 22 mm le long de l'axe, fût de 22 à 72, tige de 72 à 115), l'empennage deux plaques de 110 à 150 mm ; la pièce rencontrée la première sur le rayon gagne, ce qui donne une occultation exacte entre fléchettes, indépendante de leur ordre ; un fil en relief cache le pied d'une fléchette situé derrière lui ;
  - trois styles : acier/tungstène, laiton, **tout noir**.
- **Ombre** : un point de la cible est dans l'ombre quand le segment vers la lampe ponctuelle touche une fléchette ; sa couleur est multipliée par `shadowStrength` avec une légère teinte.
- **Nuisances** : bruit gaussien (σ = 2 niveaux par défaut), passes de flou 3×3, gain global, décalage de toute l'image (rééchantillonnage bilinéaire), main (disque couleur peau à 60 mm au-dessus de la cible), retrait de fléchettes.
- **`renderCanvas`** rend la même scène directement dans le canevas (un rayon par pixel de canevas, depuis le centre optique), pour tester chaque étape sans dépendre du redresseur.
- **`SyntheticScript`** déroule une chronologie à 30 images/s : lancer (2 images floues de mouvement, 4 images de vibration décroissante de ±0,6 px, puis la fléchette au repos), rebond, main posée, retrait, chute, choc du trépied, saut et rampe de lumière. Nombre d'images par étape, fixé par le lot V1 pour que les tests puissent l'attendre : `throwDart` 6 (2 floues de 4 sous-rendus chacune, puis 4 de vibration ; la fléchette est dans la scène dès la première image de vibration) ; `bounceOut` 3 (une fléchette près de r = 110 mm) ; `handRest(T)` et `takeout(T)` 6 + round(30·T) + 6 (entrée, durée, sortie ; la main, un disque qui couvre 10 % de l'image, vient du côté du pied de l'appareil ; `takeout` retire les fléchettes au milieu de la durée) ; `fallOut` 2 (indice hors limites ignoré ; les fléchettes au repos sont indexées de la plus ancienne à la plus récente) ; `bump` 3 (secousse décroissante de 1,5 px) ; `lightStep` 0 ; `lightRamp(T)` round(30·T). Le gain d'une étape de lumière multiplie le gain propre de la scène. Pour une source synthétique, `FrameSourceInfo.isLive` vaut `realTime`.

Le contraste doit rester réaliste : tiges noires et pointes noires font partie du mélange par défaut, parce que ce sont elles qui ont cassé la première version de la conception 1. Des tests qui flattent le détecteur ne valent rien.

`SnapshotTool` produit des PNG de contrôle : fil de fer sur une image synthétique, carte de preuve, masque, axe et pointe.

### 10.2 Cas de test et tolérances

Poses de référence : `A` = objectif en `(150, −450, 1100)` mm, 4K portrait (2,1 à 2,5 px/mm) ; `B` = `(0, −400, 1000)`, 1080p paysage ; `C` = `(−300, −420, 1050)`, 4K portrait ; `D` = `(450, −100, 1100)` (variante sur le côté), 4K paysage. Les tailles de C et D suivent la règle de placement de 2.1.

Chaque groupe appartient au lot qui possède le code testé (`ARCHITECTURE.md` §13.2). Un test ne dépend jamais d'un lot ultérieur : tout calibrage vient de `SyntheticCamera.calibration(grade:)`, sauf dans les groupes C et L. Ces tests partagent une seule cible, `DartVisionTests` : chaque fichier range les siens dans une `@Suite struct` qui porte le nom de son dossier, aucune fonction `@Test` n'est déclarée au niveau fichier, et les aides sont `private` (`ARCHITECTURE.md` §13.4).

| Lot | Code testé | Groupes et identifiants |
|---|---|---|
| V1 | géométrie, images, canevas, rendu synthétique | M1 à M12, R1, B1 |
| V2 | calibrage, localisation automatique | C1 à C12, L1 à L5 |
| V3 | détection, confiance, photo touchée ou différenciée (`PhotoScorer`) | E1 à E4, T1 à T8, F1 à F7, P3, P4 |
| V4 | réducteur | S1 à S23 |
| V5 | porte, moteur, capture, « Scanner la volée » | X1 à X17, P1, P2, P5 |

**M — Mathématiques** (lot V1)

| # | Cas | Tolérance |
|---|---|---|
| M1 | Forme close, DLT et vérité, 200 poses aléatoires | < 1e-6 px |
| M2 | Aller-retour `G(H(x)) = x` | < 1e-9 mm |
| M3 | Points alignés ou confondus, et quatre points dont trois sont alignés, passés à `Homography(from:to:)` et à `unitSquare(to:)` | `nil` |
| M4 | Centre optique depuis `H` et `K` exacts, 50 poses de 5 à 45° | < 1e-6 mm |
| M5 | Focale auto-calibrée, angle de vue ≥ 10° | à 0,1 % ; `nil` sous 3° d'inclinaison (repli de 4.2) |
| M6 | Formule de parallaxe contre la projection | < 1e-6 mm |
| M7 | Échelle locale contre des différences finies | 1e-6 en relatif |
| M8 | Conventions : 20 en haut, 6 à droite, 3 en bas, 11 à gauche ; centre des 82 zones ; ±0,01° autour de chaque fil | exact |
| M9 | `RingRadii.toNominal` / `fromNominal` : aller-retour, nœuds sur les cotes nominales | < 1e-9 mm |
| M10 | Signes d'une vue physique, 50 poses : lacet des poignées de `exactHandles()`, lues par `points` ; déterminant du jacobien de `H` au bull | lacet > 0 ; déterminant < 0 |
| M11 | Aller-retour des coordonnées normalisées ; aller-retour JSON de `Homography` | exact aux points d'ancrage (0, 1/2, 1) et à 1e-12 px ailleurs (les formules de 3.2 ne sont pas exactes en virgule flottante binaire : x = 15 sur W = 3840 revient en 15,000000000000002) ; JSON exact |
| M12 | `SyntheticCamera.calibration(grade:)`, poses A à D et les trois grades : `boardToImage` contre `project` ; `pose.center` contre `position` ; `imageToBoard` appliquée à des points projetés ; champs de `quality` ; deux appels | < 1e-6 px ; < 1e-6 mm ; < 1e-6 mm ; valeurs de la section 10.1 ; valeurs égales |

Les parties de M3, M10 et M11 qui exerçaient le calibreur sont devenues C10, C11 et C12.

**C — Calibrage** (lot V2)

| # | Cas | Tolérance |
|---|---|---|
| C1 | Poignées exactes sur une cible rendue (1,2 à 2,4 px/mm, 0 à 35°, bruit σ 2, gain ±10 %) | RMS des arêtes ≤ 0,3 mm ; poignées déplacées de ≤ 0,5 px |
| C2 | Poignées bruitées σ = 2 px, 200 graines ; erreur mesurée sur 200 points de r ≤ 170 contre la vraie `H` | RMS ≤ 0,35 mm et p95 ≤ 0,8 mm dans ≥ 95 % des graines |
| C3 | Propriété de la garde, sur toutes les graines | affinage accepté ⇒ erreur non augmentée |
| C4 | Poignées décalées de 12 px | `refinementRejected`, grade `poor`, `handles == userHandles` |
| C5 | Fil de fer tourné d'un secteur ; en miroir ; cible hors champ ; 0,7 px/mm ; pose frontale | `sectorPhaseMismatch` ; `handlesMirrored` ; `boardOutOfFrame` ; `resolutionTooLow` ; `viewTooFrontal` |
| C6 | Trois fléchettes sur la cible pendant le calibrage | p95 ≤ 1,0 mm |
| C7 | Cible rendue avec un triple à 98 / 106,5 mm | rayons ajustés à 0,3 mm près ; nominaux si `fitRingRadii = false` |
| C8 | Dérive : 3 fléchettes ; image décalée de (3, −2) px ; décalée de 40 px ; image grise uniforme | `healthy` ; `drifted` puis ≤ 0,4 mm après `recover` ; `lost` ; `edgesNotVisible` |
| C9 | Hauteur des fils, test physique en pose A. (a) Géométrie exacte, `s = 0,7` mm : poignées = projection des quatre jonctions à la hauteur `s`, `preview` avec les vraies intrinsèques ; 200 points du sisal (`z = 0`, r ≤ 170) projetés par `SyntheticCamera.project`, puis relus par `boardPoint(for:)`. (b) Cible rendue avec `SyntheticScene.wireHeight = 1,0` mm, sans bruit, `calibrate` depuis les jonctions projetées à cette hauteur ; erreur moyenne signée sur 200 points du sisal, comptée positive en s'éloignant de `F` | (a) couche active (`wireHeight = s`) : chaque point retrouvé à 1e-6 mm près ; couche coupée : chaque point décalé vers `F` de `s·tan θ(X)`, soit 0,20 à 0,41 mm, à 0,001 mm près. (b) couche active (`wireHeight = 1,0`) : moyenne dans ±0,1 mm ; couche coupée : moyenne de −0,44 mm, à 0,1 mm près |
| C10 | Poignées alignées ou confondues, par `preview` et par `calibrate` | `.failure(.degenerateHandles)` |
| C11 | Poignées exactes données dans l'ordre inverse (20, 11, 3, 6), par `preview` | `.failure(.rejected(…))` contenant `handlesMirrored` |
| C12 | Aller-retour JSON d'un `BoardCalibration` issu de `calibrate`, avec `wireHeight = 0,7` | valeur égale |

**L — Localisation automatique (couche optionnelle)** (lot V2)

| # | Cas | Tolérance |
|---|---|---|
| L1 | Ajustement de conique sans bruit ; avec 0,5 px de bruit à 640 px | rapports à 1e-8 ; erreur radiale p95 ≤ 2 mm après construction |
| L2 | Phase par la 10e harmonique | ≤ 0,5° |
| L3 | 12 poses (0,9 à 1,5 m, 15 à 35°, dessous, dessous-gauche, dessous-droite, roulis ±10°) | ≥ 11 réussites avec la bonne orientation ; après `calibrate`, p95 ≤ 1,0 mm |
| L4 | Faux positifs : texture de bruit, rayures rouges et vertes, un seul anneau rouge | `nil` dans tous les cas |
| L5 | Appareil incliné de 30° | la bonne orientation est dans `alternatives` ; `reoriented(twentyAt:)` la rétablit |

**R, B — Redressement, morphologie et composantes** (lot V1 : `Canvas/`, `Imaging/Morphology`, `Imaging/ConnectedComponents`)

| # | Cas | Tolérance |
|---|---|---|
| R1 | Image caméra redressée contre rendu direct dans le canevas | écart absolu moyen ≤ 6 niveaux hors arêtes ; bull à 0,5 px de canevas |
| B1 | Petits masques connus : étiquettes, aires, ouverture qui retire les lignes de 2 px, fermeture qui comble 6 px | exact |

**E — Carte de preuve** (lot V3)

| # | Cas | Tolérance |
|---|---|---|
| E1 | Ombre 0,6 sur chacune des 4 couleurs | `e < τ` |
| E2 | Gain global 0,9 | `e < τ` partout ; `g` à 1 % près |
| E3 | Pièces acier, laiton, noires sur chaque couleur | table attendue (noir sur noir : manqué, par conception) |
| E4 | Image entière décalée de 0,3 px, garde d'arêtes active | masque vide après D3 |

**T — Pointe (dans le canevas, 500 fléchettes par cas, poses A à D)** (lot V3)

| # | Cas | Tolérance |
|---|---|---|
| T1 | Sans ombre, et ombre 0,65 | médiane ≤ 1,2 mm, p95 ≤ 2,0 mm pour les fléchettes à pointe visible |
| T2 | Erreur signée moyenne le long de l'axe (correction de calotte) | dans ±0,3 mm |
| T3 | Bonne extrémité | ≥ 99 % caméra dessous ; ≥ 95 % avec `usePoseForTipEnd = false` |
| T4 | Segment correct | ≥ 97 % à plus de 2 mm d'un fil ; ≥ 93 % au total |
| T5 | Fléchette toute noire sur secteurs noirs | ≤ 1 % d'erreurs parmi les réponses hautes |
| T6 | Deuxième fléchette dont la pointe est dans la bande cachée par la première | `tipPossiblyOccluded` et pas haute dans ≥ 90 % des cas |
| T7 | Ombre 0,20 (hors modèle) | ≥ 90 % basses ; hautes et fausses ≤ 3 % |
| T8 | Fléchettes tombantes (queue en bas de 0 à 18°) | ≥ 95 % de correctes parmi les hautes |

**F — Confiance** (lot V3)

| # | Cas | Tolérance |
|---|---|---|
| F1 | Postérieure contre Monte-Carlo (100 000 tirages, 300 fléchettes) | écart de probabilité ≤ 0,03 |
| F2 | Honnêteté en scène nominale | ≥ 99 % de correctes parmi les hautes, et ≥ 65 % de hautes |
| F3 | La vérité est dans les 3 premiers candidats | ≥ 99 % des fléchettes dont l'erreur de pointe est < 3 mm |
| F4 | Cas idéal (`q = 1`, pose A) | 88 à 93 % de hautes, moins de 1 % de basses |
| F5 | `tier(collapsingBy:)` sur des observations fabriquées par l'initialiseur membre à membre : candidats S11 à 0,6 et S14 à 0,4, `confidence = 0,6`. (a) même effet, sans drapeau ; (b) effets différents ; (c) même effet avec `warmUp`, puis `calibrationPoor`, puis `crossViewpoint` | (a) `high` ; (b) `medium`, palier inchangé ; (c) `medium` chaque fois (0,84 ; 0,80 ; 0,80) : les drapeaux gardent la fléchette sous le palier haut même quand tous les candidats se regroupent |
| F6 | `TrustTracker` : 2 hautes corrigées sur 15 ; 15 sans correction | seuil 0,95 ; retour à 0,85 |
| F7 | Pointe cachée sur 8 mm à cheval sur un fil | deux candidats, aucun au-dessus de 0,85 |

**S — Réducteur (entrées en conserve, aucune image)** (lot V4)

| # | Séquence | Attendu |
|---|---|---|
| S1 | `arm`, 12 échantillons calmes | `watching(0)` |
| S2 | 3 échantillons de mouvement, 6 calmes, issue « fléchette » | `beginAccumulation` au 2e calme, `analyse` au 6e, `dart`, référence courante mise à jour, `watching(1)` |
| S3 | Trois fléchettes | `watching(1)`, `watching(2)`, `awaitingTakeout` |
| S4 | Aucun changement après un épisode de 0,2 s ; après un épisode de 1,5 s | `possibleMiss` seul ; rien |
| S5 | Épisode de type main, tout retiré | `takeoutCompleted`, références courante et vide mises à jour, `watching(0)` |
| S6 | Retrait partiel, puis 5 s immobiles | `takeoutStarted` une seule fois, puis `takeoutStalled(remaining)` et `awaitingTakeout` |
| S7 | Deux fléchettes connues ; l'une disparaît après un épisode de type lancer | `dartRemoved(.fellOut)`, `watching(1)` |
| S8 | Quatrième fléchette | reste `awaitingTakeout` |
| S9 | Mouvement pendant la pose | `discardAccumulation`, aucun `analyse` |
| S10 | Changement d'éclairage avec `n = 0` puis `n = 2` | `lightingChanged` ; référence vide reprise, puis marquée périmée |
| S11 | Calibrage perdu sur deux poses, puis `calibrationHealth` avec `recovered: true` | à la 2e perte, état et événement `calibrationLost` ; à la récupération, `arming` puis l'état précédent. Le réducteur n'émet ni `calibrationAdjusted` ni `calibrationRecovered` : ils viennent du moteur (X8, X9) |
| S12 | `endVisit` ; `beginVisit` avec 2 fléchettes sur la cible | `awaitingTakeout` ; `watching(2)`, volée + 1 |
| S13 | `discardDart`, `registerManualDart` | compteurs ajustés, aucun effet sur les références |
| S14 | Mouvement continu pendant 9 s | `obstructed` et `advisory(.viewObstructed)` |
| S15 | Latence | `analyse` au plus 6 images après la dernière image en mouvement |
| S16 | Lignes P1, P1b, P2, P2b et P2c. Dans les cas (a) à (d), `pause` s'écrit `pause(.background)` ; ils se déroulent à l'identique avec `pause(.thermal)`. (a) Depuis `watching(1)` : `pause` puis `resume`, 12 échantillons calmes, issue « aucun changement ». (b) `pause` puis `resume` depuis `needsCalibration` ; depuis `idle` après `setCalibration` ; depuis `idle` après `needsEmptyBoard` ; depuis `calibrationLost`. (c) `arm`, 5 échantillons calmes, `pause`, `resume`, 12 échantillons calmes. (d) Depuis `watching(1)` : `pause`, `pause`, `resume`. (e) Depuis `watching(1)` : `pause(.user)`, `pause(.background)`, `resume`, puis `arm`. (f) Depuis `watching(1)` : `pause(.background)`, `pause(.user)`, `resume`. (g) `pause(.user)` puis `resume` depuis `needsCalibration`, puis depuis `idle` | (a) `paused(.background)` ; `arming` ; `analyse` ; retour à l'état d'avant la pause, référence courante mise à jour. (b) chaque fois `paused(.background)` puis retour au même état, sans `arming`, sans `analyse` et sans mise à jour de référence ; `needsEmptyBoard` est réémis dans le troisième cas, et dans lui seul. (c) `paused(.background)`, `arming`, puis `watching(0)` au 12e échantillon calme après `resume` : les 5 premiers ne comptent plus. (d) la seconde `pause` est sans effet et sans événement, et `resume` se déroule comme en (a). (e) la seconde pause est sans effet et sans événement ; `resume` aussi, l'état reste `paused(.user)` ; `arm` donne `arming`. (f) la seconde pause émet `stateChanged(.paused(.user))` et rien d'autre ; `resume` est sans effet et sans événement, l'état reste `paused(.user)`. (g) chaque fois `paused(.user)`, et `resume` est sans effet et sans événement |
| S17 | `arm` depuis `paused(.user)`, depuis `paused(.background)` (pauses prises dans `watching(1)`), puis depuis `awaitingTakeout` avec 3 fléchettes connues et `visit = 2` ; chaque fois 12 échantillons calmes. Puis `arm` depuis `paused(.user)`, pause prise dans `needsCalibration` | `arming` puis `watching(0)` ; `visit`, `dartsInVisit` et `dartsOnBoard` à zéro ; références reprises comme en S1 ; `trigger` inchangé. Dernier cas : `stateChanged(.needsCalibration)` et rien d'autre ; l'état est `needsCalibration`, jamais `arming` |
| S18 | Depuis `watching(1)` : `pause(.background)`, `resume`, 12 échantillons calmes, issue « changement non reconnu » ; puis `confirmBoardEmpty` et 12 échantillons calmes | `stateChanged(.idle)` puis `needsEmptyBoard`, sans événement de fléchette ni mise à jour de référence ; ensuite `arming`, `updateReference(.rollingAndEmpty)`, `watching(0)`, `visit` et `dartsInVisit` inchangés |
| S19 | Une seule fléchette connue, épisode de 0,2 s, issue `removed([id], boardEmpty: true)` ; puis la même issue après un épisode de 0,2 s parti de `takeout` | premier cas : `dartRemoved(id, .fellOut)`, `updateReference(.rolling)`, `watching(0)`, ni `takeoutCompleted` ni mise à jour de la référence vide ; second cas : `dartRemoved(id, .takeout)` puis `takeoutCompleted` (A7) |
| S20 | Lignes DM1 et DM8. `setTrigger(.manual)` depuis `watching(1)`, puis 60 échantillons en mouvement et 90 calmes ; `setTrigger(.manual)` pendant `settling` ; `setTrigger(.automatic)` au repos | aucun effet, état `watching(1)`, `trigger == .manual` ; `discardAccumulation` et retour au repos ; `arming`, puis la suite de S16 |
| S21 | Lignes DM2 et DM5, au repos manuel avec 2 fléchettes connues. `captureReference`, 6 échantillons calmes ; `rebaseline`, 6 calmes ; `captureReference` en déclenchement automatique | `settling`, `beginAccumulation` au 2e calme, `updateReference(.rollingAndEmpty)` au 6e, `watching(0)`, aucun `analyse` ; `updateReference(.rolling)` et retour au même repos ; commande ignorée, aucun effet |
| S22 | Lignes DM3 et DM6, issues d'un scan. `captureNow(maxDarts: 3)`, 6 calmes, issue de 3 fléchettes ; une image en mouvement après 3 calmes ; mouvement continu pendant 2 s ; issue « changement d'éclairage » ; `pause(.background)` pendant la capture ; au repos, `captureNow(maxDarts: 0)` | `analyse(maxNewDarts: 3)` au 6e calme, un seul `scanCompleted` de 3 observations émis en dernier, `updateReference(.rolling)`, `awaitingTakeout` ; `discardAccumulation`, compte repris à zéro, état `settling` ; `advisory(.viewObstructed)` puis `scanCompleted([])`, aucun `analyse`, retour au repos ; `lightingChanged` puis `scanCompleted([])`, aucune mise à jour de référence ; `paused`, `discardAccumulation` et `scanCompleted([])` ; commande ignorée : aucun effet, aucun `scanCompleted`, état inchangé |
| S23 | Lignes DM4 et DM7. Après un scan de 3 fléchettes, `beginVisit(expectedDarts: 3)` ; avec 2 fléchettes connues, `beginVisit(expectedDarts: 1)` ; `pause(.background)` puis `resume` en déclenchement manuel, 12 échantillons calmes | `updateReference(.rollingFromEmpty)`, `watching(0)`, volée + 1, référence vide intacte ; aucune mise à jour de référence, `watching(2)`, volée + 1 ; `arming` puis retour au repos, aucun `analyse` |

**X — Moteur de bout en bout (`SyntheticFrameSource` → `ScanEngine`)** (lot V5)

| # | Scénario | Attendu |
|---|---|---|
| X1 | Cible vide, 40 images | `arming` puis `watching(0)` |
| X2 | Une fléchette | exactement un `dart`, au plus 12 images après la dernière image en mouvement |
| X3 | Trois fléchettes puis retrait par une main (10 % du champ) qui les enlève toutes | `dart` × 3, `awaitingTakeout`, puis `dartRemoved(.takeout)` × 3 et `takeoutCompleted` (ligne A7 ; `takeoutStarted` n'appartient qu'au retrait partiel, A8) ; `E` reprise ; aucune fléchette fantôme |
| X4 | Rebond : 3 images de mouvement, retour à la référence | `possibleMiss` seul |
| X5 | Gain global × 1,3 ; moitié de la cible éclaircie | aucune fléchette ; `lightingChanged` |
| X6 | Main immobile 3 s, puis partie | `obstructed`, puis retour ; aucune fléchette |
| X7 | Une seule fléchette sur la cible ; elle disparaît avec un petit mouvement | `dartRemoved(.fellOut)`, `watching(0)`, aucun `takeoutCompleted` |
| X8 | Choc de 2 px avec une fléchette plantée ; fléchette suivante | `calibrationAdjusted`, aucun fantôme ; fléchette suivante correcte |
| X9 | Choc de 40 px, sans puis avec localisation automatique | `calibrationLost` ; `calibrationRecovered` |
| X10 | Tremblement de ±0,3 px et bruit pendant 600 images | zéro événement |
| X11 | Fléchette présente dans `R`, puis retirée | aucune fléchette fantôme |
| X12 | Quatrième fléchette quand 3 sont attendues | `dart` avec `beyondVisitLimit` |
| X13 | Chaîne complète : rendu caméra, calibrage depuis des poignées bruitées, 200 fléchettes à 1,8 px/mm ; idem à 1,2 px/mm | médiane ≤ 1,5 mm et p95 ≤ 2,5 mm ; p95 ≤ 3,5 mm |
| X14 | Partie de trois volées : 9 lancers dont 1 rebond, choc de 4 px entre deux volées, lumière − 15 % en cours de volée | séquence d'événements exacte ; les 8 fléchettes plantées (à plus de 3 mm de toute frontière) sont justes |
| X15 | Détecteur bouchon de mode `.absolute` qui rend toutes les fléchettes | seules les nouvelles (à plus de 8 mm des connues) sont émises |
| X16 | Même entrée deux fois | sorties identiques au bit près |
| X17 | Deuxième partie : une fléchette, `pause(.user)`, puis `arm(boardConfirmedEmpty: false)`, `beginVisit(expectedDarts: 3)` et une nouvelle fléchette | `arming`, `watching(0)`, puis un seul `dart`, de `visit = 1` et `indexInVisit = 0`, portant `emptyReferenceStale` |

**P — Photo** (P1, P2 et P5 : lot V5, par `ScanEngine` ; P3 et P4 : lot V3, par `PhotoScorer`, avec un calibrage de `SyntheticCamera.calibration(grade:)`)

| # | Cas | Tolérance |
|---|---|---|
| P1 | « Scanner la volée » de bout en bout par `ScanEngine` : `setTrigger(.manual)`, `arm(boardConfirmedEmpty: true)`, `beginVisit(expectedDarts: 3)`, 3 fléchettes séparées, `captureNow(maxDarts: 3)` | aucun événement entre la fin de l'armement et la commande ; un seul `scanCompleted`, de 3 observations `multiDartStill` de source `.scan`, p95 ≤ 2,0 mm |
| P2 | Fléchettes croisées | signalées (`clutter` ou `implausiblyLong`), aucune haute |
| P3 | Toucher les pointes : points connus, dont des points à 0,1 mm de chaque côté d'un fil | `Hit` exact |
| P4 | Couche optionnelle : plateau vide depuis la pose A, fléchettes depuis une pose à 15° et 0,2 m de là | p95 ≤ 2,5 mm ; aucune au-dessus du palier moyen |
| P5 | Scans successifs en déclenchement manuel. Même volée : 2 fléchettes, `captureNow(maxDarts: 3)`, une 3e fléchette, `captureNow(maxDarts: 1)`. Volée suivante : `beginVisit(expectedDarts: 3)`, les 3 fléchettes retirées, 3 nouvelles dont une à la place d'une ancienne, `captureNow(maxDarts: 3)` | le deuxième `scanCompleted` ne contient que la 3e fléchette ; le troisième contient les 3 nouvelles et aucune ancienne |

**Coût.** Une pose sur une source 4K est chronométrée en mode release et le temps est rapporté ; seule une borne large (1 s) est exigée. Les suites lourdes (C2, T, X13) portent l'étiquette `.heavy` (`@Suite(.tags(.heavy))`) et tournent avec `swift test -c release` ; en mode debug elles utilisent des images de 1280×720. Cette étiquette est déclarée **une seule fois**, par le lot F0, dans `DartVisionTests/SmokeTests.swift` (`ARCHITECTURE.md` §13.4) : les lots V2, V3 et V5 s'en servent et n'en déclarent aucune.

### 10.3 Rejeu d'enregistrements réels

`DirectoryRecorder` écrit, par session : le calibrage, les événements, les échantillons de porte, les corrections du joueur et, pour chaque scène analysée, les canevas `R` et `S`. `RecordedSession.replay` repasse ces scènes dans un détecteur sur macOS. C'est **le seul moyen de régler les valeurs de départ** ; il fait partie du livrable, pas des extras. Les enregistrements réels restent hors du dépôt.

---

## 11. Limites connues et paramètres à régler

### 11.1 Limites

1. **Rien n'a été validé sur une vraie cible.** Tous les seuils sont des valeurs de départ. L'estimation de la recherche pour une caméra unique sans apprentissage est de **80 à 90 % de fléchettes justes sans aide, sous une bonne lumière**, moins pour les groupes serrés. Aucun système classique à une caméra n'a publié de chiffre.
2. **Une pointe cachée derrière une fléchette antérieure ne peut pas être mesurée** par une seule caméra. Les groupes serrés (le triple 20 des bons joueurs) seront souvent en « À vérifier ». C'est une limite de l'approche, pas un réglage.
3. **Ombres dures dans l'axe de la fléchette**, plus sombres que la borne du modèle : la pointe est placée au bout de l'ombre. La sonde montre 3 fléchettes fausses à confiance haute sur 120 dans ce cas extrême. Parades : vérification à une fléchette, test de longueur, conseil de lumière, suivi des corrections.
4. **La borne d'ombre échange deux défauts** : basse, elle tolère les ombres dures mais cache une pointe noire fine sur un secteur crème ; haute, c'est l'inverse. La couleur réelle des ombres sous un éclairage mixte est inconnue.
5. **Pointes ou fûts noirs sur secteur noir** : invisibles pour une différence d'images. Le test de largeur en signale la plupart ; la sonde montre encore des erreurs de 5 à 12 mm au-dessus du seuil de 0,5.
6. **Fléchettes qui penchent vers la caméra** (queue en bas) : vues en bout. Dans la sonde où toutes les fléchettes tombent, 1,6 % des réponses hautes sont fausses.
7. **Le calibrage suit les limites de couleur, pas les fils.** Sur une cible dont l'impression est décalée des fils, les scores près des fils peuvent être biaisés d'environ 1 mm. L'ajustement des rayons ne corrige que la direction radiale. Aucun modèle de distorsion de l'objectif.
8. **Une fléchette par événement en mode direct.** Deux fléchettes en moins de 0,3 s environ sont fusionnées ou manquées. Une fléchette plantée pendant une obstruction ou un changement de lumière est absorbée par la référence.
9. **Les rebonds sont invisibles** pour la vision : seul `possibleMiss` est émis.
10. **Une fléchette sur dix environ est orange** par simple proximité d'un fil, et la sonde donne 25 à 35 % de fléchettes sous le palier haut en comptant les drapeaux. Relever les seuils rend l'application moins bavarde au prix d'erreurs silencieuses.
11. **Le placement est contraignant** : un support d'environ 1,2 m de haut, à 1 m de la cible, entre le joueur et le mur. Il peut être touché par un rebond, et le corps du joueur masque la vue pendant le retrait (ce qui retarde `takeoutCompleted`).
12. **Chaleur et batterie** : une capture 4K à 30 images/s chauffe l'appareil même si le traitement lourd ne tourne que sur événement. Les budgets de temps sont des estimations. Un iPad ancien peut exiger le 1080p à 0,9 m ou le mode « Scanner la volée ».
13. **La localisation automatique** dépend d'anneaux rouges et verts saturés, et lève l'ambiguïté des dix orientations en supposant le 20 en haut de l'image. Cible inhabituelle, lumière colorée ou reflets : retour aux poignées.
14. **La pose dépend des intrinsèques.** Pour une photo importée, la focale est estimée ; cela touche la règle de l'extrémité, le test de longueur et le modèle d'incertitude.
15. **Les tests synthétiques peuvent flatter le détecteur** : reflets de l'acier, texture du sisal, ombres réelles ne sont qu'approchés.
16. **La couche de capture n'a jamais tourné sur un appareil.** Xcode, le SDK iOS et XcodeGen sont installés sur cette machine et l'API compile pour iOS, mais le verrouillage de l'exposition, la livraison des intrinsèques, la rotation et le débit 4K restent à vérifier sur un iPhone et un iPad réels.
17. **La paire de photos à main levée** est bruitée (parallaxe des fils, lumière, couronne des numéros) et pourrait ne servir qu'à pré-placer les pointes à toucher.

### 11.2 Paramètres à régler sur une vraie cible

Méthode : enregistrer des séances avec `DirectoryRecorder`, les rejouer sur macOS avec `RecordedSession.replay`, modifier `VisionConfiguration` (JSON) et recharger. Ordre de priorité décroissant.

| Paramètre | Défaut | Comment le régler |
|---|---|---|
| `shadowLowerBound` | 0,40 | vérification à une fléchette ; regarder la carte de preuve sous la lumière du joueur |
| `evidenceThresholdFloor`, `noiseMultiplier` | 18, 6 | scènes vides : aucun fantôme ; scènes avec fléchette : silhouette entière, pointe comprise |
| `tipCapCorrection` | 0,8 mm | erreur signée moyenne le long de l'axe, tirée des corrections « pointe déplacée » : viser zéro |
| `hiddenTipLength` | 1,5 mm | dispersion de la même erreur |
| Seuils de confiance, facteurs des drapeaux | 0,85 / 0,50 | journal des corrections : précision observée par tranche de confiance |
| `motionOnFraction`, `quietFraction`, `settleFrames`, `skipFrames` | 0,12 %, 0,05 %, 6, 2 | séances de lancers : latence contre fausses poses (cible qui vibre encore) |
| `throwMaxDuration`, `handBorderFraction`, `handSustainFrames` | 0,6 s, 4 %, 5 | lancers contre retraits |
| `edgeGuardPixels` | 0,25 px | scènes vides pendant que quelqu'un marche près du trépied |
| `minChangeArea`, `maxDartArea`, `speckArea` | 60, 4000, 15 mm² | histogramme des aires de silhouettes réelles |
| `removedFraction`, `disturbedFraction`, `ghostGuardFraction` | 0,5 / 0,15 / 0,5 | séances de retrait, fléchettes qui se touchent |
| `minEdgeEnergy`, `edgePeakRatio`, `huberK`, garde d'acceptation | 20, 2,5, 0,75 mm | images figées de la cible du joueur : comparer le fil de fer aux fils à fort zoom |
| `fitRingRadii`, `ringRadiusTolerance`, `wireHeight` | actif, 2 mm, 0 | toucher un fil avec une pointe et lire la distance annoncée par le test au toucher |
| `flightMinWidth`, `flightWidthRatio`, `narrowMaxWidth`, `pointMaxWidth` | 12 mm, 2, 12 mm, 4 mm | profils de largeur des fléchettes du joueur |
| `ColourBoardLocator.Parameters` (`saturationRange`, `minBrightness`, `minPhaseContrast`) | 0,30–0,55, 48, 0,35 | images figées sous lumière chaude et froide |
| Durée d'exposition, seuil d'ondulation | 1/100 s, 1 % | ondulation de `meanLuma` à l'armement |
| `warmUpDarts`, fenêtres de `TrustTracker` | 3, 15, 12 | ressenti en partie réelle |

---

## 12. Ordre de réalisation

Chaque étape est vérifiable seule par `swift test`. Les lots et leurs vagues sont ceux de `ARCHITECTURE.md` §13 ; la liste donne l'ordre logique à l'intérieur de la vision, et la table de la section 10.2 la répartition des tests par lot.

1. Géométrie, modèle de cible, types de pixels, morphologie et composantes — tests M1 à M11 et B1 (lot V1).
2. Moteur de rendu synthétique et `SyntheticCamera.calibration(grade:)` — test M12 (lot V1).
3. Redresseur — test R1 (lot V1) ; carte de preuve — tests E (lot V3).
4. Pointe et confiance — tests T, F ; toucher les pointes sur une photo (`PhotoScorer`) — test P3 (lot V3).
5. Calibrage par poignées, affinage, dérive — tests C (lot V2).
6. Réducteur — tests S (lot V4 ; il ne dépend d'aucune des étapes 1 à 5) ; porte et moteur — tests X (lot V5).
7. « Scanner la volée » — tests P1, P2 et P5 (lot V5).
8. Enregistreur, rejeu, `CameraFrameSource` (lot V5 ; compilé pour macOS et iOS ; essayé sur appareil).
9. Couches optionnelles : `ColourBoardLocator` (tests L, lot V2), paire de photos (P4, lot V3).

Les étapes 1 à 7 livrent le socle garanti. Tant que l'étape 8 n'a pas produit d'enregistrements réels, aucun chiffre de ce document ne doit être présenté au joueur comme une précision mesurée.

---

## 13. Questions ouvertes pour le propriétaire

1. **Emplacement de l'appareil.** Pouvez-vous laisser, pendant toute une partie, un support d'environ 1,2 m de haut à 1 m de la cible, sous elle ou sur le côté (section 2.1) ? Si le seul emplacement possible est de face depuis la ligne de tir, ou au-dessus de la cible, la lecture automatique sera médiocre et les modes « Scanner la volée » et « toucher les pointes » deviendront le chemin principal.
2. **Fléchette incertaine.** Quand la caméra n'est pas sûre (palier bas), l'application attend la réponse du joueur avant de compter la fléchette (choix par défaut). Préférez-vous qu'elle accepte seule sa meilleure hypothèse après quelques secondes, au risque d'erreurs silencieuses ?
3. **Appareils visés.** Quels modèles d'iPhone et d'iPad doivent être pris en charge ? Un appareil sans vidéo 4K doit être placé à moins de 0,95 m, où le cadrage est serré ; cela décide si ce cas est un chemin de premier rang.
4. **Enregistrements de réglage.** Les seuils ne peuvent être réglés que sur des séances filmées avec votre cible, vos fléchettes et votre lumière (section 10.3). Acceptez-vous d'enregistrer quelques volées en mode débogage et de garder ces images en local sur le Mac ?

