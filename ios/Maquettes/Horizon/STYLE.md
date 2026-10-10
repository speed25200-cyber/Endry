# Style « Horizon » — Endry Pilotage

Direction D de la refonte Liquid Glass (01.10.2026). L’app est pensée comme un **tableau de bord de précision** :
verre clair, typographie nette, mouvement rare et physique, aucun effet brillant (pas de dorure, de reflet qui balaie,
de lueur ni de pulsation décorative).

Maquette interactive (privée, à partager depuis son menu) : https://claude.ai/artifact/6onrFu5iviz9kTHV3N9dMa — page
« D — Horizon ». Les fichiers `*.dc.html` de ce dossier sont ses écrans (format Design Component) ; les images
`/_blob/…` ne s’affichent que dans la maquette (ce sont les photos `PhotoChauffageSol`, `PhotoReseaux`,
`PhotoHydraulique`, `PhotoSanitaire` et `MonogrammeEndry` de `Assets.xcassets`).

## Écrans
| Fichier | Contenu |
| --- | --- |
| `D-Accueil` | Statut du bureau, salutation, frise de la journée (06–20 h, repère « maintenant »), tuiles : À décider (curseur à glisser), Chantiers, À payer, Bureau ; barre d’onglets à loupe liquide et bille « Parler à Endry ». |
| `D-Decision` | Fiche : tableau À / Objet / Pièce, trois contrôles qui se cochent, message, panneau « Glisser pour envoyer », Non / Corriger. |
| `D-Voix` | Égaliseur circulaire (96 traits) autour du chrono, transcription mot à mot, « transmis mot pour mot ». |
| `D-Conversation` | Fil chronologique sur un rail : repère, heure, type (dicté, écrit, question, fait) ; compte rendu structuré du bureau. |

Chaque écran existe en sombre et en clair (`-Clair`).

## Couleurs (jetons)
| Jeton | Sombre | Clair | Usage |
| --- | --- | --- | --- |
| `fond` | `#0D0C0A` | `#F2F0EB` | Fond de l’écran |
| `surface` | `rgba(255,255,255,.045)` | `rgba(255,255,255,.62)` | Tuiles |
| `verre` | `rgba(255,255,255,.06)` | `rgba(255,255,255,.55)` | Commandes flottantes (barre, boutons, panneaux) |
| `encre` | `#ECE7DF` | `#141210` | Texte, traits actifs |
| `doux` | `#958D81` | `#6B655C` | Étiquettes, texte secondaire (≥ 4,5:1) |
| `filet` / `filet-fort` | `rgba(236,231,223,.10/.28)` | `rgba(20,18,16,.09/.26)` | Bordures 0,5 pt, graduations |
| `reflet` | `rgba(255,255,255,.16)` | `#FFFFFF` | Liseré de lumière en haut à gauche du verre |
| `signal` | `#E7C88F` | `#9A6E2C` | Seule couleur d’accent : « maintenant », « en cours » |
| `vert` / `rouge` | `#8FD1A0` / `#F08F75` | `#2F7A47` / `#B4492E` | Vérifié / Non — jamais décoratifs |

Lumière d’ambiance : la photo du contexte, floutée à 70–90 px, opacité 0,30–0,38 (sombre) ou 0,18–0,22 (clair).

## Typographie
- **Geist** (300 pour les titres et grands chiffres, 400–500 pour le texte), chiffres tabulaires, interlettrage −0,04 em
  sur les grands chiffres.
- **Geist Mono** en capitales 10,5 pt (+0,04 em) pour les étiquettes, heures, références (`V-7K3F9Q`).
- Dans l’app : Geist n’étant pas une police système, l’équivalent natif est SF Pro (titres en `.light`) et
  SF Mono pour les étiquettes.

## Verre
- Commandes : fond `verre`, flou 26 px, saturation 160 %, bordure intérieure 0,5 pt `filet`, liseré `reflet`
  (1 px en haut à gauche), ombre portée longue et douce (0 18 40 −16). En SwiftUI : `.glassEffect()` (iOS 26)
  avec repli `.ultraThinMaterial` + liseré.
- Tuiles : même recette avec `surface`, flou 30 px, rayon 22–26 pt.
- Formes : capsules pour les commandes, rayons 26 / 22 / 16 pour les tuiles ; cibles ≥ 44 pt.

## Mouvement
- Entrée : montée de 16 pt + fondu, 1,1 s, `cubic-bezier(.16,1,.3,1)`, en cascade de 0,1 s.
- Chiffres qui défilent jusqu’à leur valeur (1,6 s, sortie quartique) ; barres et courbes qui se tracent.
- Loupe d’onglet liquide : s’étire de l’onglet de départ à l’onglet d’arrivée puis se rétracte (0,36 s).
- Curseur « Glisser pour valider » : disque de verre sur un filet, trait d’encre qui suit le doigt, retour à ressort
  (`cubic-bezier(.34,1.45,.5,1)`, 0,75 s) ; validé à 90 % de la course.
- Repère « en direct » : simple variation d’opacité (2,8 s). Rien d’autre ne bouge en continu.
- « Réduire les animations » : tout s’affiche directement, sans mouvement.
