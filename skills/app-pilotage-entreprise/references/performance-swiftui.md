# Performance et mise en page SwiftUI — règles SOTA

Issues de l'audit complet d'Endry (gels du vocal, défilement saccadé, texte qui se chevauche).

## Fil principal
1. **Aucun appel bloquant** sur le MainActor : `AVAudioSession.setActive/setCategory`,
   `AVAudioEngine.start/stop`, installation de modèles de reconnaissance, décodage JPEG/HEIC, rendu PDF,
   génération de QR, `JSONDecoder` sur de gros corps, `DateFormatter()` créé à la volée.
2. Son : une **file série unique** (`FileAudio`, `templates/swift/App/FileAudio.swift`) pour tout ce qui
   touche à la session et aux moteurs, dans l'ordre (l'arrêt précédent est fini avant le démarrage suivant).
3. Toute attente externe est **bornée** (`dansLeDelai(.seconds(4)) { … }`) : l'écran ne reste jamais
   sur « Un instant ». L'opération n'est pas annulée, elle servira la fois suivante.
4. Images : `jpegHorsEcran`, `vignette(maxPixel:)` via `CGImageSourceCreateThumbnailAtIndex` dans
   `Task.detached`, cache `@MainActor` des vignettes ; jamais `UIImage(data:)` dans un `body`.
5. Formateurs : `static let` (ou cache) ; parseur de dates ISO rapide avec mémoïsation.

## `body` léger
- Aucun tri, filtre, `reduce`, formatage coûteux dans `body` : précalculer dans le modèle ou dans un
  `struct Chiffres` construit **une fois par rendu** et passé aux sous-vues.
- Lier une liste filtrée à une `let` en tête de `body`, pas un calcul par ligne.
- Découper les gros écrans en sous-vues `struct` avec des entrées `Equatable` simples ; le composeur de
  message est sa propre vue (taper ne réévalue pas le fil entier).
- Recherche : résultats dans `@State`, `.task(id: requete)` avec **anti-rebond 120 ms** et calcul détaché.
- Brouillons : sauvegarde par `.task(id: brouillon)` + `Task.sleep(600 ms)` (annulé à chaque frappe).

## Dessin
- Ombres via `ShapeStyle.shadow(.drop…)` sur le remplissage, pas `.shadow()` sur une vue composée.
- Pas de `.blur` ni `.ultraThinMaterial` sur des éléments qui défilent ; fond = image figée.
- Visualisations : un seul `Canvas` plutôt que 96 vues (ex. anneau vocal en 6 niveaux de traits ;
  forme d'onde en un `Canvas`).
- `TimelineView` à la cadence utile (`.periodic(by: 1)` pour un chronomètre, 1/30 s pour une dérive),
  en pause (`paused:`) quand l'écran est couvert, en arrière-plan, ou « Réduire les animations ».
- Environnement `animationsEnPause` propagé depuis l'écran racine quand une feuille/plein écran est ouvert.
- Shaders Metal : seulement s'ils apportent vraiment quelque chose ; sinon image précalculée.

## Mise en page déterministe (zéro chevauchement)
1. **Une seule hiérarchie par écran.** Les variantes (compacte, clavier ouvert, réponse longue) changent
   des *valeurs* (hauteur de la sphère, opacité d'un bloc), jamais tout l'arbre en fondu.
2. Texte qui grandit (transcription, réponse en flux) : **un seul `Text` par bloc** dans une
   `ScrollView`, `.fixedSize(horizontal: false, vertical: true)`, `.transaction { $0.animation = nil }`
   pour que le texte n'interpole pas sa mise en page à chaque fragment ; défilement automatique vers le
   bas avec `ScrollViewReader`.
3. Jamais `containerRelativeFrame` hors d'une `ScrollView`, jamais de largeur mémorisée d'une mesure
   précédente : la largeur vient de la proposition du parent.
4. Éléments graphiques carrés : `.aspectRatio(1, contentMode: .fit)` + une hauteur maximale.
5. `lineLimit` + `minimumScaleFactor` sur les chiffres et libellés courts ; `truncationMode(.tail)`
   sur les descriptions ; tester **iPhone SE en Dynamic Type XXL** et **iPad paysage**.
6. Bouton de fermeture : toujours visible, zone de toucher ≥ 44 pt, `highPriorityGesture` s'il est au-dessus
   d'une zone qui capte des gestes ; fermer **d'abord** l'écran (état de l'app), **ensuite** arrêter les
   moteurs (en arrière-plan) — l'utilisateur ne doit jamais attendre l'arrêt du son.
7. Glisser vers le bas pour fermer un plein écran : `simultaneousGesture(DragGesture)` limité au haut
   de l'écran (départ y < 320, déplacement vertical > 90).

## Réseau
- Une `URLSession` partagée ; préchauffage de la connexion à l'ouverture de la conversation et à la
  première frappe (`HEAD`/`GET` léger).
- SSE lu hors du fil principal (`Task.detached` → `AsyncStream`), rechargements **coalescés**
  (une rafale de 10 `maj` = 1 rechargement).
- Sondage adaptatif : 0,4 s les premières secondes, 0,8 s jusqu'à 30 s, puis 1,5 s ; long-poll
  `?attendre=20` quand le serveur le permet.

## Mesure
- Instruments « SwiftUI » et « Hangs » sur un appareil réel ; objectif : aucun hang > 100 ms à
  l'ouverture du vocal, défilement à 120 Hz (`CADisableMinimumFrameDurationOnPhone`).
- Captures automatiques (tests UI) clair/sombre, SE XXL, Pro Max, iPad : relues à chaque refonte.
