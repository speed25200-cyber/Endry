# CI et TestFlight (XcodeGen + Codemagic)

On peut développer **sans Mac** : le Kit se teste sur Linux, l'app se compile et part sur TestFlight
via Codemagic. Modèles : `templates/project.yml`, `templates/codemagic.yaml`.

## Projet Xcode
- `ios/project.yml` (XcodeGen) fait foi ; `.xcodeproj` ignoré par git.
- iOS 18, Swift 6, `SWIFT_STRICT_CONCURRENCY: complete`, app universelle (`TARGETED_DEVICE_FAMILY "1,2"`),
  `CADisableMinimumFrameDurationOnPhone: true` (120 Hz), `ITSAppUsesNonExemptEncryption: false`.
- `NSAppTransportSecurity.NSAllowsLocalNetworking: true` pour un réseau privé (Tailscale) en HTTP.
- Toutes les chaînes d'usage (micro, reconnaissance vocale, caméra, photos, Face ID, position) en
  langue de l'utilisateur, qui disent **pourquoi**.
- Frameworks récents liés faiblement (`-weak_framework FoundationModels`) pour rester lançable sur iOS 18.

## Codemagic : préparation (une fois, par l'utilisateur, dans l'interface Codemagic)
1. Ajouter l'app (dépôt GitHub) → récupérer l'**appId**.
2. Teams › Integrations › **App Store Connect** : clé API (fichier `.p8`, Issuer ID, Key ID) — nommer
   l'intégration (ex. `Dev`). La clé n'est **jamais** dans le dépôt.
3. Code signing identities : certificat de **distribution** Apple ; Codemagic récupère/crée le profil
   App Store du bundle id (`ios_signing`).
4. Créer l'app dans App Store Connect (bundle id, nom) → noter l'**Apple ID numérique** (public).
5. Jeton API Codemagic personnel (User settings › Integrations › Codemagic API) → à garder **hors dépôt**
   (`CM_TOKEN` en variable d'environnement ou fichier ignoré dans un dossier temporaire).

## Workflows
- `ios-tests` : à chaque push/PR touchant `ios/` : outils (XcodeGen, Metal si shaders), génération,
  `swift test` du Kit, `xcodebuild test` sur le dernier iPhone simulé (UI tests + captures clair/sombre),
  captures SE XXL / Pro Max / iPad (non bloquantes), export des pièces jointes `.xcresult`.
- `ios-testflight` : sur tag `ios-v*` ou lancé par l'API : tests du Kit + tests unitaires, signature
  (`xcode-project use-profiles`), **numéro de build** = max(dernier TestFlight + 1, `BUILD_NUMBER`,
  `BUILD_MINIMUM`), `xcode-project build-ipa`, publication `submit_to_testflight: true`.
- `cancel_previous_builds: true` ; concurrence souvent limitée à 1 : un build `ios-tests` déclenché par
  un push retarde TestFlight → mettre `[skip ci]` dans le message de commit quand on lance TestFlight soi-même.

## API Codemagic (voir `scripts/codemagic.sh`)
```bash
# Lancer
curl -sS -X POST https://api.codemagic.io/builds -H "x-auth-token: $CM_TOKEN" \
  -H 'Content-Type: application/json' \
  -d '{"appId":"<APP_ID>","workflowId":"ios-testflight","branch":"<branche>"}'
# État
curl -sS https://api.codemagic.io/builds/<id> -H "x-auth-token: $CM_TOKEN"
# Journal d'une étape (ids dans build.buildActions[]._id)
curl -sS https://api.codemagic.io/builds/<id>/step/<stepId> -H "x-auth-token: $CM_TOKEN"
# Annuler
curl -sS -X POST https://api.codemagic.io/builds/<id>/cancel -H "x-auth-token: $CM_TOKEN"
```
États terminaux : `finished`, `failed`, `canceled`, `timeout`, `skipped`. En cas d'échec : lire le
journal de l'étape en échec (chercher `error:`), corriger, relancer. Ne jamais annoncer « sur
TestFlight » avant `finished` ; le traitement Apple prend ensuite 5–15 min.

## Pièges rencontrés
- Xcode 26 : le compilateur Metal est un composant séparé → `xcodebuild -downloadComponent MetalToolchain`.
- Numéro de build déjà utilisé (ancien compte) → plancher `BUILD_MINIMUM`.
- Tests UI fragiles sur simulateur : ils tournent dans `ios-tests`, pas en bloquant TestFlight.
- Un `#Preview` qui référence une vue supprimée casse la compilation (exit 65) : supprimer les aperçus
  obsolètes avec la vue.
- Widgets : extension compilée en CI, embarquée sur TestFlight seulement une fois son profil créé.
