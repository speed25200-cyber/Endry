---
name: app-pilotage-entreprise
description: Concevoir, coder et livrer sur TestFlight une app iPhone/iPad native (SwiftUI, Swift 6) de pilotage d'entreprise pour un patron de PME — poste de pilotage chiffré, décisions validées d'un geste, conversation et voix quasi instantanées avec l'agent IA qui tourne sur le PC du bureau, documents PDF, terrain. À utiliser dès qu'on demande « une app comme Endry pour l'entreprise X », une app de supervision/pilotage pour un dirigeant, ou une app mobile reliée à un assistant IA installé chez le client.
---

# App de pilotage d'entreprise (modèle « Endry »)

Ce skill reproduit, pour une autre entreprise, une app native de **supervision et de pilotage** :
le patron voit l'état de son entreprise d'un coup d'œil, valide d'un geste ce que l'assistant IA du bureau
a préparé, parle à cet assistant (texte ou voix) et reçoit ses réponses presque instantanément, avec les
documents (PDF) en pièce jointe.

L'app est un **client** : toute l'intelligence et toutes les données vivent sur le PC du bureau
(un assistant/agent qui parle à l'ERP, à la messagerie, au planning). L'app lit un **contrat d'API**
et n'invente jamais un chiffre.

> Langue : tout ce que voit l'utilisateur, le code (noms de types et de fonctions) et les commits sont
> rédigés dans la langue de l'entreprise (ici français ; adapter : français de Suisse, de France, etc.).

---

## 0. Règles d'or (non négociables)

1. **Dépôt public possible : zéro secret, zéro donnée réelle.** Aucune clé, aucun jeton, aucune URL
   d'accès, aucun nom de client, montant, adresse, IBAN réels dans le dépôt. Fixtures et mode démo :
   données **fictives crédibles** uniquement. Jetons d'API (Codemagic, App Store Connect) : hors dépôt,
   dans un fichier ignoré ou une variable d'environnement. Jamais de fichier `.p8` commité.
2. **Rien ne part sans le geste du patron.** Toute action qui sort de l'entreprise (e-mail, facture,
   offre, paiement) est préparée par l'agent puis **validée par un glissement** (« Glisser pour envoyer »),
   jamais par un simple tap, jamais depuis une notification.
3. **Les interdits métier de l'entreprise** sont écrits dans la fiche (§1) et respectés partout
   (ex. Endry : « aucune relance de facture automatique »).
4. **Le serveur ne se modifie pas depuis l'app.** On ne touche qu'au **contrat** (`CONTRAT_API.md`) :
   l'équipe du PC l'implémente. L'app décode de façon tolérante et vit avec un serveur plus ancien.
5. **Natif pur.** SwiftUI, Swift 6 en concurrence stricte, iOS 18 minimum, **aucune dépendance tierce**.
6. **Le fil principal ne bloque jamais** (son, réseau, images, PDF, JSON : hors du fil principal).
7. **Une disposition unique et déterministe par écran** : jamais deux hiérarchies qui se croisent en fondu,
   jamais une vue par mot, jamais de texte qui se chevauche (voir `references/performance-swiftui.md`).
8. **Chaque modification part sur TestFlight** une fois les tests verts (si le client le demande, ce qui
   est la norme sur ce type de projet).
9. Aucun identifiant de modèle d'IA dans les commits, les PR ou le code.

---

## 1. Démarrage : la fiche entreprise

Avant toute ligne de code, remplir `templates/fiche-entreprise.md` (avec l'utilisateur si des infos
manquent ; sinon, valeurs par défaut raisonnables et signalées). Elle fixe :

- nom commercial, nom de l'app, préfixe (`{{PREFIXE}}`, ex. `Endry`), bundle id (`{{BUNDLE_ID}}`),
  langue/région, devise et format des montants (`CHF 35’589`, `35 589 €`) ;
- le métier (sanitaire, menuiserie, fiduciaire, cabinet, garage…) et son **pipeline**
  (ex. demande → offre → acceptée → planifiée → réalisée → facturée → payée) ;
- l'ERP / la compta (Bexio, Abacus, Sage, Odoo, Pennylane…) et la messagerie (Outlook, Gmail) que
  l'agent du PC utilise — l'app ne leur parle **jamais** directement ;
- les **agents** du bureau (secrétariat, comptabilité, chantiers, commercial…) et leurs horaires ;
- les actions qui exigent le glissement, les interdits, le vocabulaire métier (pour la dictée) ;
- la palette (une couleur signal + neutres chauds ou froids), la police des chiffres.

---

## 2. Déroulé du projet (phases)

| Phase | Livrable | Référence |
|---|---|---|
| 1. Cadrage | `fiche-entreprise.md` rempli, liste des écrans | §1 |
| 2. Contrat d'API | `ios/CONTRAT_API.md` : routes, formats, SSE, erreurs, versions | `references/contrat-api.md` |
| 3. Paquet Kit | `{{PREFIXE}}Kit` : modèles tolérants, client HTTP, démo, stores, tests Linux | `references/architecture.md` |
| 4. App | Écrans SwiftUI, navigation, mode démo, accès par lien | `references/architecture.md` |
| 5. Design | Palette, tuiles, instruments, fond, verre, poste de pilotage | `references/design-system.md` |
| 6. Conversation et voix | Chat + PDF, voix temps réel, latence minimale | `references/voix-et-conversation.md` |
| 7. CI / TestFlight | XcodeGen, Codemagic, signature, numéros de build | `references/ci-testflight.md` |
| 8. Itérations | Chaque retour → correctif minimal, tests, TestFlight | `references/checklist-livraison.md` |

Ordre impératif : **contrat → Kit (testé sur Linux) → app**. Le Kit compile et se teste sans Xcode
(`swift test`), ce qui permet de valider 80 % de la logique dans un conteneur Linux.

---

## 3. Écrans types (à adapter au métier)

1. **Accueil = poste de pilotage** : salutation + résumé du jour en une phrase ;
   « Pouls de l'entreprise » (trésorerie des factures ouvertes avec barre à encaisser / à payer, puis
   4 instruments : en retard, à décider, travaux en cours, offres ouvertes) ; tuile « À décider » ;
   « Bureau en direct » (chaque agent : point d'état, tâche en cours, charge du jour) ; frise de la
   semaine ; terrain ; briefing ; « Fait récemment ». Chaque chiffre est un bouton vers son espace.
2. **Décisions** : cartes préparées par l'agent, Oui (glisser) / Non / Corriger, pièces jointes en aperçu.
3. **Chantiers / dossiers** : entonnoir du pipeline (une colonne par étape, toucher = filtrer), liste,
   fiche dossier.
4. **Finances** : à encaisser (ancienneté), à payer, à refacturer, offres ; bandes de chiffres.
5. **Le bureau** : les agents, leur journal, leur file ; poser une question à un agent.
6. **Conversation** : fil avec l'assistant, réponses en flux, cartes PDF (aperçu + enregistrer).
7. **Assistant vocal** : plein écran, sphère animée, transcription et réponse en deux blocs, fermeture
   par bouton **et** par glissement vers le bas.
8. **Terrain / saisie** : photo, scan, dictée, bons de régie/livraison, relevé ; file hors ligne.
9. **Recherche globale**, **Planning**, **Équipe**, **Réglages** (appareils, mode « devant le client »
   qui masque tout ce qui est à payer et les marges).

Mode **démo** (`-demo` ou bouton « Essayer sans connexion ») alimenté par les fixtures fictives :
indispensable pour la revue App Store, les captures et les tests UI.

---

## 4. Comment travailler (boucle de chaque demande)

1. Comprendre la demande ; si c'est un bug visuel signalé par capture, **trouver la cause racine**
   (disposition, fondu entre hiérarchies, largeur verrouillée…) — pas un rustine.
2. Modifier au plus juste ; respecter le style du code (noms français, commentaires de la même densité).
3. Kit : `swift test` sur Linux. App : relire le diff contre `references/checklist-livraison.md`
   (pièges de compilation Swift 6 qu'on ne peut pas attraper sans Xcode).
4. Commit clair (le message dit le *pourquoi*), `[skip ci]` si on lance soi-même TestFlight, push.
5. Lancer `ios-testflight` via l'API Codemagic (`scripts/codemagic.sh`), suivre le build, corriger
   jusqu'au vert. Annoncer « sur TestFlight » seulement quand le build est `finished`.
6. Si le correctif dépend du PC (route manquante, 404 sur une pièce annoncée), afficher un message
   clair côté app **et** ajouter la règle au contrat — ne jamais « réparer » le serveur depuis l'app.

---

## 5. Nouveau projet en une commande

```bash
scripts/nouveau-projet.sh --dossier ../MonApp --prefixe Atelier --bundle ch.atelier-sa.pilotage \
  --nom "Atelier Pilotage" --entreprise "Atelier SA"
```

Le script copie `templates/` (project.yml, codemagic.yaml, Package.swift, fichiers Swift de base,
contrat d'API, fiche entreprise) en remplaçant les `{{…}}`. Ensuite : remplir la fiche, écrire le
contrat, coder le Kit, puis l'app.

---

## 6. Fichiers du skill

- `references/architecture.md` — dépôt, Kit, décodage tolérant, client, démo, stores, accès par lien.
- `references/contrat-api.md` — modèle de contrat (routes, SSE, questions, décisions, documents, latence).
- `references/design-system.md` — palette, typographie, tuiles, instruments, fond baked, verre, anti-motifs.
- `references/performance-swiftui.md` — règles SOTA de performance et de mise en page SwiftUI.
- `references/voix-et-conversation.md` — file audio, délais bornés, SSE, long-poll, flux partiel, PDF.
- `references/ci-testflight.md` — XcodeGen, Codemagic, signature, build number, API, captures.
- `references/securite-et-regles.md` — dépôt public, secrets, geste de validation, accès, mode client.
- `references/checklist-livraison.md` — avant chaque push : compilation Swift 6, UI, tests, TestFlight.
- `templates/` — `fiche-entreprise.md`, `project.yml`, `codemagic.yaml`, `Package.swift`, `CONTRAT_API.md` ;
  `swift/Kit/` (`DecodageTolerant`, `Modeles` : étapes, décisions, réponses avec documents, `ClientAPI`) ;
  `swift/App/` (`App`, `Palette`, `Instruments`, `GlisserPourValider`, `FileAudio`, `ApercuDocuments`) ;
  `swift/Tests/ContratTests.swift`. Le Kit modèle compile et ses tests passent sous Linux.
- `scripts/nouveau-projet.sh`, `scripts/codemagic.sh`.

---

## Installation du skill

- Pour tous vos projets : copier le dossier `app-pilotage-entreprise/` dans `~/.claude/skills/`.
- Pour un seul dépôt : le copier dans `<dépôt>/.claude/skills/`.
- Claude Code le charge automatiquement quand la demande correspond à la description (ou `/app-pilotage-entreprise`).
