# Architecture

## Dépôt

```
codemagic.yaml                 CI (tests à chaque push, TestFlight à la demande / sur tag)
ios/
  project.yml                  XcodeGen — fait foi ; le .xcodeproj n'est PAS versionné
  CONTRAT_API.md               contrat avec le PC du bureau (versions v1.0, v1.1, …)
  {{PREFIXE}}Kit/              paquet Swift pur, testable sur Linux (swift test)
    Package.swift
    Sources/{{PREFIXE}}Kit/
      API/        ClientAPI (transport, erreurs typées), Requete (routes)
      Acces/      LienAcces (lien …/app/acces/<secret>), Identifiants (trousseau)
      Cache/      CacheHorsLigne (dernière réponse de chaque GET)
      Demo/       APIDemo (même protocole que ClientAPI), Fixtures, PDFDemo
      Format/     FormatSuisse / FormatLocal (montants, dates, parseur rapide avec cache)
      Modeles/    DecodageTolerant, Modeles (v1.0), ModelesV11, ModelesV12…
      Pilotage/   Evenements (SSE), Horaires, ModelePilotage
      Stores/     modèles d'écran @Observable (Planning, Recherche, Session…)
      Terrain/    bons, relevés, saisies, file hors ligne
      Voix/       BureauClaude (questions aux agents), ConversationBureau, FluiditeVoix…
      Resources/Fixtures/   JSON fictifs (*-v10.json = format exact v1.0)
    Tests/{{PREFIXE}}KitTests/
  {{PREFIXE}}Pilotage/         l'app
    App/        point d'entrée, ModeleApp (@Observable, état global), ContenuPrincipal (onglets)
    Design/     Palette, Maison (tuiles, fond, typo), Instruments, Verre, GlisserPourValider…
    Fonctions/  un dossier par espace : Decisions (accueil), Chantiers, Argent, Bureau,
                Conversation, Recherche, Saisie, Terrain, Planning, Equipe, Suivi, Reglages
    Services/   FluxEvenements (SSE), Documents (QuickLook), ImagePourPC, Dictee, Notifications
    Voix/       FileAudio, MoteurTempsReel, TranscripteurAnalyseur, MoteurVoix, AnneauVoix, VueAssistantVocal
    Ressources/ Assets.xcassets (AppIcon, couleurs), polices
  {{PREFIXE}}Widgets/          extension facultative (project-widgets.yml)
  Tests/{{PREFIXE}}PilotageTests, Tests/{{PREFIXE}}PilotageUITests (captures clair/sombre)
```

## Principes

### Le Kit d'abord
Toute logique non visuelle va dans le Kit : décodage, formats, règles métier (qui peut glisser quoi),
cadence de sondage, fusion des réponses partielles, extraction des documents d'une réponse. Le Kit ne
dépend que de `Foundation` (avec `#if canImport(FoundationNetworking)` pour Linux). Résultat : la
majeure partie se teste dans un conteneur Linux :

```bash
export PATH=/opt/swift/<toolchain>/usr/bin:$PATH   # si besoin
cd ios/{{PREFIXE}}Kit && swift test
```

### Décodage tolérant
Le serveur est un assistant (souvent Python) qui évolue vite. Règle : **un champ absent, nul ou d'un
type inattendu ne casse jamais le décodage**, et un élément illisible ne fait jamais tomber le tableau.
Voir `templates/swift/Kit/DecodageTolerant.swift` : `CleJSON`, `texte()`, `nombre()` (accepte `"1'250.50"`),
`entier()`, `booleen()`, `date()`, `liste()` qui ignore les éléments invalides. Chaque modèle a un
`init(from:)` écrit à la main avec ces lecteurs et des valeurs par défaut. Accepter les alias de champs
(`documents` / `pieces` / `fichiers`).

Tests de contrat : pour chaque version (`ContratV10Tests`, `ContratV11Tests`…), décoder les fixtures
exactes de cette version et vérifier les valeurs.

### Client et transport
- `protocol API: Sendable { func envoyer(_: Requete) async throws(ErreurAPI) -> Data }` —
  implémenté par `ClientAPI` (réseau) et `APIDemo` (fixtures). Les écrans ne voient que le protocole.
- `Requete` : méthode, chemin, paramètres, corps (`json` / `multipart`), **délai par requête**
  (20 s lecture, 45 s pour les agrégats lents, 90 s pour « actualiser »).
- **Une seule `URLSession` partagée** (`ephemeral`, sans cache ni cookies, `timeoutIntervalForResource`
  long pour le flux SSE) : la connexion TLS reste chaude, aucune poignée de main avant une question.
- Erreurs **typées** (`throws(ErreurAPI)`) avec un message humain par cas : lien invalide, non
  authentifié, refus (400), injoignable, hors ligne, délai dépassé (« l'action a peut-être abouti »),
  serveur (statut, message), ERP indisponible, document indisponible.
- Le jeton n'est envoyé **qu'à l'hôte du lien d'accès** (`memeServeur(url)`), jamais à un autre domaine.
- `CapacitesServeur` : une route facultative qui a répondu 404/405 n'est plus rappelée pendant la session.

### Accès par lien (pas de compte, pas de mot de passe)
Le PC génère un lien `https://<machine>.<réseau-privé>/app/acces/<secret>` (QR code ou copier-coller).
L'app échange le secret contre un **jeton propre à l'appareil** (`POST /session` avec `appareil`),
stocké dans le **trousseau**. Révocation : `DELETE /appareils/{id}`. L'adresse n'est **jamais** écrite
dans le code. Face ID optionnel à l'ouverture.

### État de l'app
- `@Observable final class ModeleApp` (MainActor) : onglet courant, sous-vue de chaque espace
  (`vueFinances`, `vueChantiers` — pour que l'accueil puisse ouvrir « Finances › À encaisser »),
  écran plein par-dessus (`ecranParDessus` → met les animations de fond en pause), assistant ouvert…
- Un modèle `@Observable` par écran (dans le Kit quand il n'a pas besoin d'UIKit), rechargé par :
  pull-to-refresh, retour au premier plan, et **événements SSE** (coalescés).
- `CacheHorsLigne` : chaque GET réussi est gardé ; hors ligne, l'écran affiche la dernière version
  avec « maj 10:42 ».
- File de saisies hors ligne : renvoi identique dans les 15 min → même `saisie_id` côté PC (idempotent).

### Démo
`APIDemo` répond aux mêmes `Requete` avec les fixtures, simule les latences et les questions
(« Qui me doit de l'argent ? » → réponse plausible ; « pdf / offre » → lien vers un PDF fictif généré
par `PDFDemo`). Toutes les données sont inventées (noms, adresses, montants).

### Concurrence Swift 6
- Isolation par défaut : **nonisolated** ; les `View` sont `@MainActor` par inférence ; les modèles
  d'écran `@MainActor @Observable`.
- Travail lourd : `Task.detached(priority: .userInitiated)` puis retour au MainActor.
- Capturer une valeur non-`Sendable` dans une tâche détachée : `nonisolated(unsafe) let copie = valeur`.
- Caches statiques touchés par des vues : `@MainActor enum Cache { static var … }`.
- Annulation : `withTaskCancellationHandler`, `Task.checkCancellation()` dans les boucles.
