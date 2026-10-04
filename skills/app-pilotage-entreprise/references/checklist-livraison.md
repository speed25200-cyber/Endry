# Checklist avant chaque push

## Compilation Swift 6 (à vérifier à la main quand on n'a pas Xcode)
- [ ] Aucun `#Preview` ne référence une vue/un type supprimé ou renommé.
- [ ] Les API `@MainActor` (UIKit, `ImageRenderer`, `UIGraphicsImageRenderer`, rendu d'une vue,
      types de l'app marqués `@MainActor`) ne sont **pas** appelées depuis `Task.detached`.
- [ ] Les valeurs non-`Sendable` capturées par une tâche détachée passent par `nonisolated(unsafe) let`.
- [ ] Les `static var` mutables sont isolées (`@MainActor enum Cache`) ou protégées (`Mutex`/`OSAllocatedUnfairLock`).
- [ ] Les fonctions `throws(ErreurAPI)` ne laissent pas échapper une autre erreur (`do/catch` qui convertit).
- [ ] Les nouveaux fichiers sont dans un dossier couvert par `project.yml` (XcodeGen ajoute tout le dossier).
- [ ] Les signatures modifiées sont mises à jour à **tous** les sites d'appel (`grep -rn "nomFonction("`).
- [ ] Pas de `#available(iOS 26)` sans `#if compiler(>=6.2)` autour des API iOS 26.

## Interface
- [ ] Une seule hiérarchie par écran ; aucune transition entre deux arbres de vues.
- [ ] Pas de `containerRelativeFrame` hors `ScrollView`, pas de largeur mémorisée.
- [ ] Textes longs : `lineLimit`/`truncationMode` ou `fixedSize(vertical)` dans une ScrollView.
- [ ] Chiffres : `monospacedDigit`, `minimumScaleFactor`, `contentTransition(.numericText())`.
- [ ] Boutons ≥ 44 pt, libellés VoiceOver, `accessibilityIdentifier` pour les tests UI.
- [ ] Clair **et** sombre ; SE en XXL ; iPad portrait et paysage ; Split View.
- [ ] Toute feuille / plein écran qui peut montrer un document a `.apercuDocuments()`.
- [ ] Rien de lourd dans `body` ; pas de tâche audio/image/PDF sur le fil principal.

## Règles métier
- [ ] Aucun « Oui » par tap ; envoi à un tiers seulement par glissement.
- [ ] Aucun secret, aucune donnée réelle ajoutés (fixtures fictives).
- [ ] Les textes visibles sont dans la langue de l'entreprise, sans jargon technique.
- [ ] Si le PC doit changer : contrat mis à jour (nouvelle version), l'app tolère l'ancien serveur.

## Tests
- [ ] `cd ios/{{PREFIXE}}Kit && swift test` vert (ajouter un test pour chaque règle nouvelle du Kit).
- [ ] Fixtures nouvelles décodées par un test de contrat.

## Livraison
- [ ] Commit : message qui explique le pourquoi ; `[skip ci]` si TestFlight est lancé à la main.
- [ ] Push sur la branche de travail.
- [ ] `scripts/codemagic.sh lancer ios-testflight` puis `suivre <id>` jusqu'à `finished`.
- [ ] En cas d'échec : journal de l'étape, cause racine, correctif, relance.
- [ ] Annoncer à l'utilisateur : ce qui a changé, le n° de build, ce qu'il doit vérifier sur l'appareil,
      et ce qui dépend encore du PC.
