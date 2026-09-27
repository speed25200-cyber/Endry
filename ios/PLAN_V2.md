# Plan v2 — Endry Pilotage

Branche `claude/code-magic-push-eirhs1` (PR #1). Chaque lot se termine par une CI Codemagic verte
(EndryKit, tests unitaires de l’app, tests UI et tests de contrat) et des captures relues.

| Lot | Contenu | État |
| --- | --- | --- |
| **a** | Corrections de la revue (section 1) : fixtures au contrat réel v1.0/v1.1, tests de contrat, refacturer, heures, versements, `envoi_tiers`, `repondre`, 503 Bexio, détail chantier, Entreprise indépendante du filtre, Planning multi-semaines, pause, rafraîchissement, démo, widget mort, CI « Endry ASC API » + tous les tests avant TestFlight | en cours |
| **b** | Sécurité : confirmation d’hôte pour les liens profonds, purge des PDF, jeton par appareil ; file de saisie hors ligne persistante et historique `GET /saisies` | à faire |
| **c** | Refonte visuelle : palette `#0B0A09` / `#C9A55C`, thème clair ivoire, typographie et échelle fixes, chiffres SF Mono, grain Metal, pile de décisions à balayer, transitions zoom, états soignés, boucle de captures | à faire |
| **d** | Assistant vocal : protocole `MoteurVoix`, `MoteurTempsReel` (session éphémère `POST /voix/session`, Realtime en WebSocket, outils, barge-in), `MoteurLocal` (SpeechAnalyzer / SFSpeechRecognizer fr-CH, synthèse Premium), sphère Metal, transcription en direct, cartes contextuelles | à faire |
| **e** | Notifications riches (catégories, actions VOIR / OUI, `thread-id`), événements SSE `/evenements` avec repli 60 s, pause / reprise, écran Appareils, résumé PR | à faire |

## Principes

- L’app ne décide jamais seule : tout envoi à un tiers exige « Glisser pour envoyer » ; la voix prépare, le geste valide.
- Aucune relance de facture ; « Suivi seulement : aucune relance sans votre demande ».
- Décodage tolérant : l’app fonctionne avec le serveur v1.0 comme v1.1 (`CONTRAT_API.md`).
- Aucun secret ni donnée réelle dans le dépôt public ; fixtures fictives.
- Swift 6 strict, frameworks Apple uniquement (la voix passe par `URLSessionWebSocketTask`, sans WebRTC tiers).
