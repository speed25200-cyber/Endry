# Design system — « poste de pilotage » haut de gamme

Objectif : une app qui se lit comme un **instrument de bord** — sobre, dense en information, futuriste
sans gadget. Le patron doit comprendre l'état de son entreprise en 3 secondes et agir en un geste.

## 1. Palette (tokens)
Toujours des tokens nommés, avec variante claire et sombre (`Color(clair:sombre:)`), jamais de couleur
en dur dans un écran. Modèle : `templates/swift/App/Palette.swift`.

| Token | Rôle |
|---|---|
| `fond`, `surface`, `surfaceCreuse` | fond d'écran, tuile pleine, zone en creux |
| `encre`, `encreDouce`, `encrePale` | texte principal, secondaire, tertiaire (contraste AA minimum) |
| `filet`, `filetFort` | séparateurs, bords (opacité 0,10–0,30) |
| `signal`, `signalHalo` | **une seule** couleur d'accent de la marque (ex. crème/or 0xF9DBA3 en sombre) |
| `sauge` / `rouille` | sain / alerte (jamais rouge et vert criards) |
| `tuileHaut`, `tuileTeinte`, `verreTeinte` | dégradé des tuiles, teinte du verre |
| `etiquette` | petites capitales de section |

Le **mode sombre** est la vitrine : fond presque noir légèrement teinté (brun 0x0B0907 ou bleu nuit),
jamais `#000`. L'accent est désaturé, lumineux, rare.

## 2. Typographie
- Chiffres et grands titres : **SF Pro Display**, fin (`.light`) au-delà de 34 pt, `.monospacedDigit()`
  partout où un nombre change (montants, compteurs, heures) + `.contentTransition(.numericText())`.
- Libellés : SF Pro 13 pt `.medium`, `encreDouce`. Étiquettes de section : 11,5 pt semibold,
  majuscules, `tracking(taille * 0.1)`.
- Toujours `UIFontMetrics(forTextStyle:).scaledValue(for:)` : Dynamic Type respecté, testé en XXL.
- Une police de marque (serif élégante) est possible pour le logo/les titres courts, **jamais** pour
  des chiffres elzéviriens illisibles ; si on en utilise une, activer les chiffres alignés.

## 3. Briques (voir `templates/swift/App/Instruments.swift`)
- `tuileMaison(rayon:)` : dégradé `tuileHaut → tuileTeinte`, filet 0,5 pt, reflet sur le bord haut,
  **ombre portée par le style de remplissage** (`.fill(… .shadow(.drop(…)))`) — pas de `.shadow()`
  sur la vue (passe hors écran), pas de flou d'arrière-plan sur les tuiles qui défilent.
- `GlypheInstrument` (SF Symbol dans un carré arrondi teinté), `LibelleInstrument`,
  `ChiffreInstrument` (grand chiffre + unité/préfixe), `Indicateur` (tuile-bouton complète).
- `BarreParts` (proportions, ex. encaisser vs payer, ancienneté), `SegmentsAvancement` (4 sur 7),
  `BandeChiffres` (3–4 valeurs séparées d'un filet), `EntonnoirChantiers` (une colonne par étape).
- `TitreSection` (étiquette + lien « Voir tout ›» ou repère « maj 10:42 »).
- `ActionPressee` : le bouton se tasse à 0,92 avec un ressort court.
- `GlisserPourValider` : piste + pouce, crans haptiques, seuil 0,94, retour élastique ; le seul moyen
  de dire « Oui » à un envoi.

Règle : **chaque chiffre est un bouton** vers l'espace qui l'explique. Accessibilité : un libellé
combiné (« En retard, 3 factures, CHF 12’400 · 45 j »), un `accessibilityIdentifier` stable pour les
tests UI.

## 4. Disposition du poste de pilotage
```
Bonjour, <prénom>                       ← salutation + résumé du jour (1 phrase)
POULS DE L'ENTREPRISE        maj 10:42
┌ Trésorerie · factures ouvertes ─ Solde positif ┐
│ CHF 35’589                                      │
│ ███████████████████░░░░░░░                      │
│ À encaisser 48’210          À payer 12’621      │
└─────────────────────────────────────────────────┘
┌ En retard ┐ ┌ À décider ┐                         grille 2 colonnes (4 sur iPad large)
┌ Chantiers ┐ ┌ Offres    ┐
À DÉCIDER (tuile)  ·  BUREAU EN DIRECT (lignes d'agents)  ·  SEMAINE  ·  TERRAIN  ·  FAIT RÉCEMMENT
```
iPad : largeur de lecture bornée (≈ 760 pt) pour le texte, grille plus large pour les instruments ;
Split View et Stage Manager pris en charge ; jamais de contenu coupé en paysage.

## 5. Fond « haut de gamme »
Ce qui marche : une **image calculée une seule fois** (via `ImageRenderer`, échelle 2, ~900×1300),
p. ex. le bord lumineux d'une **éclipse** dans un coin (disque sombre, arc en `AngularGradient`,
halo flouté, grain fin de ~18 000 points), puis une **dérive très lente** de cette image par
transformations GPU (`TimelineView(.animation(minimumInterval: 1/30))` → `offset`/`scaleEffect`),
en pause sous un écran plein, avec « Réduire les animations » et pendant les tests UI. Par-dessus :
une trame de points discrète et un dégradé vers le fond en bas.

Règles apprises :
- **La zone derrière la salutation reste sombre** (contraste du texte avant tout) ; la lumière est
  dans un coin, jamais au centre.
- Pas de photo réduite à 24 px puis agrandie (flou), pas d'image qui ne couvre pas l'iPad paysage
  (calculer pour le plus grand côté, `aspectRatio(.fill)` + `clipped()` sur le conteneur, pas sur l'image).
- Pas d'aurore claire en plein écran : illisible.
- Écrans secondaires : même fond, version « discrète ».

## 6. Verre (iOS 26 Liquid Glass)
- Seulement pour ce qui **flotte** : barre d'onglets, boutons ronds, pastilles, barre de saisie.
- `glassEffect(.regular.tint(verreTeinte).interactive(), in: forme)` sous `#if compiler(>=6.2)` +
  `if #available(iOS 26, *)`, repli : remplissage teinté + filet. Grouper avec `GlassEffectContainer`.
- Jamais d'ombre sur du verre, jamais de verre sur une tuile qui défile en liste.

## 7. Mouvement
- Une seule courbe maison (`Animation.maison = .spring(response: 0.42, dampingFraction: 0.86)`).
- Animer une **valeur**, pas un changement de hiérarchie. Transitions d'opacité seulement pour un bloc
  qui apparaît/disparaît à la même place.
- Haptique : `sensoryFeedback` sur validation, crans du glissement, erreur.

## 8. Anti-motifs (refusés en revue)
- Texte qui se chevauche, qui sort de l'écran, troncature d'un montant.
- Deux dispositions en fondu l'une sur l'autre (compacte/étendue) ; une vue par mot qui « apparaît ».
- `containerRelativeFrame` hors d'une `ScrollView` ; largeur « verrouillée » à une mesure précédente.
- Ombres et flous sur des vues qui défilent ; `drawingGroup` sur du texte.
- Couleurs en dur, chiffres non tabulaires, emojis dans l'interface.
- Cartes « héros » décoratives sans information.
