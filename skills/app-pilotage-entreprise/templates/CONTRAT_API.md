# Contrat de l’API du PC — {{ENTREPRISE}} — `/app/api/v1`

Authentification : `Authorization: Bearer <jeton>` (jeton propre à chaque appareil). Hôte : adresse du réseau privé
`https://<machine>.<réseau>`, fournie par le lien d’accès `…/app/acces/<secret>` et **jamais écrite dans le code**.

L’app décode de façon tolérante (champs absents, nuls ou d’un autre type acceptés ; clés inconnues ignorées ;
éléments illisibles d’un tableau ignorés). Fixtures **fictives** : `{{PREFIXE}}Kit/Sources/{{PREFIXE}}Kit/Resources/Fixtures/`.

Conventions : JSON UTF-8, dates ISO 8601, montants en nombre, erreurs `{erreur: "<code>", message: "<phrase>"}`
(l’app affiche `message` tel quel). Toute nouveauté est **optionnelle à la lecture**.

## v1.0 — socle

**Session et appareils**
- `POST /session {acces, appareil: {nom, modele}}` → `{jeton, appareil_id, valable_jours, entreprise, role, nom}`.
- `GET /appareils` → `[{id, nom, modele, cree, vu, actuel}]` ; `DELETE /appareils/{id}` → `{ok}` (401 ensuite).
- `POST /appareils {jeton_apns, nom, environnement}` : notifications.

**Poste de pilotage**
- `GET /accueil` → `{resume_jour, encaisser: {total, factures[{numero, client, montant, echeance, retard_jours}],
  anciennete: {a_echoir, jours_0_30, jours_31_60, plus_60}}, payer: {total, factures[]}, offres: {total, offres[]},
  semaine[], chantiers_7_jours[{id, client, date_debut, date_fin, etape}]}`.

**Décisions**
- `GET /decisions` → `[{id, type, titre, resume, envoi_tiers, modifiable?, pieces[{nom, url}], chantier_id?}]`.
- `POST /decisions/{id} {reponse: "oui"|"non"|"corriger", texte?}` → `{ok, message}` ; double traitement refusé (409).
- `envoi_tiers: true` pour tout ce qui sort de l’entreprise : l’app exige un **glissement**, jamais depuis une notification.
- Interdits : {{INTERDITS}}.

**Dossiers et finances**
- `GET /chantiers` → `[{id, client, titre, etape, montant, date_debut?, date_fin?}]` ; `GET /chantiers/{id}`.
- `GET /argent` → encaisser, payer, à refacturer, offres.
- `POST /actualiser` → relit l’ERP ; `503 {erreur: "erp_indisponible", message}`.

**Bureau (agents)**
- `GET /agents` → `[{id, nom, role, etat: occupe|libre|pause|erreur|hors_horaires, tache, file, traitees_jour, resume_jour}]`.
- `GET /journal?limite=50` → `[{quand, agent, texte, decision_reference?}]`.

**Saisie terrain**
- `POST /saisie` (multipart `texte`, `photos[]` JPEG, `agent?`) → `{ok, message, saisie_id}` ; renvoi identique
  dans les 15 min → même `saisie_id`.

## v1.1 — conversation quasi instantanée

- `POST /assistant/question {question, agent?, contexte?}` → `202 {statut: "en_cours", question_id, agent, message?}`
  (`message` hors horaires). Questions exécutées **en lecture seule**.
- `GET /questions/{id}?attendre=20` → long-poll : répond dès que c’est prêt, au plus 20 s ;
  `{statut: en_cours|repondu|erreur, question_id, agent, reponse?, message?, documents?}`.
- `GET /evenements` (SSE, `text/event-stream`, **sans tampon**, `: ping` toutes les 15 s) :
  - `event: maj` `{quoi: "decisions"|"accueil"|"agents"|…}` → l’app recharge l’écran (coalescé) ;
  - `event: reponse` `{question_id, statut, agent, reponse, documents?}` → affichée sans autre requête ;
  - `event: reponse_partielle` `{question_id, texte}` → texte cumulé, affiché au fil de l’écriture.
- Agent en process chaud : pas de démarrage à froid pour une question.

## v1.2 — documents dans les réponses

- `reponse.documents[] = {nom, url, type?, taille?}` (alias `pieces`, `fichiers`) ; liens Markdown du texte
  vers `/app/doc/…` également reconnus.
- **Toute pièce annoncée est servie** par `GET /app/doc/<type>/<id>` avec le jeton de l’appareil, avec le bon
  `Content-Type` et `Content-Disposition: inline; filename="<nom>"`. Un 404/410 est un défaut du PC.
- Échec de génération : `503 {erreur: "pdf_indisponible", message}` en JSON.

## Demandé au PC (pas encore implémenté)

- …
