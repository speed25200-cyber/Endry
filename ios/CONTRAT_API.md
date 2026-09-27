# Contrat de l’API du PC — `/app/api/v1`

Authentification : `Authorization: Bearer <jeton>`. Hôte : adresse Tailscale privée `https://<machine>.<tailnet>.ts.net`,
fournie par le lien d’accès `…/app/acces/<secret>` et **jamais écrite dans le code**.

L’app décode de façon tolérante (`decodeIfPresent`, valeurs par défaut, clés inconnues ignorées) : elle fonctionne
avec le serveur **v1.0** (production) et **v1.1** (champs et routes ajoutés, tous optionnels à la lecture).

Fixtures fictives : `EndryKit/Sources/EndryKit/Resources/Fixtures/` — `*-v10.json` = réponses v1.0 exactes,
les autres = v1.1 (mode démo). Tests : `EndryKitTests/DecodageTests.swift` (`ContratV10Tests`, `ContratV11Tests`).

## Implémenté sur le PC (27.09.2026) — contrat réel, fait foi

Préfixe `/app/api/v1`, `Authorization: Bearer <jeton>`. Ce qui suit est ce que le PC du bureau fait en production depuis
le 27.09.2026 au soir ; l'app s'y conforme exactement (fixtures fictives au même format dans `Resources/Fixtures`).

**Session et appareils**
- `POST /session {acces, appareil: {nom, modele}}` → `{jeton, appareil_id, valable_jours, entreprise}` : jeton propre à
  l'appareil ; sans `appareil`, l'ancien jeton commun.
- `POST /session/appareil {appareil: {nom, modele}}` (appelé avec l'ancien jeton commun) → `{jeton, appareil_id, …}` :
  migration sans nouveau lien. **App** : au lancement, si le jeton n'a pas d'`appareil_id`, une seule fois ; le jeton
  est remplacé dans le trousseau. `409 deja_par_appareil` si c'est déjà fait (l'app ne réessaie plus).
- `GET /appareils` → `[{id, nom, modele, cree, vu, actuel}]` ; `DELETE /appareils/{id}` → `{ok}` : jeton révoqué
  immédiatement, 401 ensuite sur cet appareil. **App** : « Déconnecter cet iPhone » ; 405 (serveur trop ancien) :
  l'app explique que la révocation à distance n'est pas encore possible.
- `POST /appareils {jeton_apns, nom, environnement}` : jeton APNs rattaché à l'appareil connecté.

**Décisions**
- `Decision.envoi_tiers: bool` (fait foi) ; `true` pour `mail_envoyer`, `mail_repondre`, `mail_transferer`,
  `envoyer_facture`, `envoyer_offre`, `envoyer_rappel`, `rappel_courrier`, `relances_reactiver` (liste de repli de
  l'app identique). Les questions `Q-…` ont `envoi_tiers: false`. `Decision.chantier_id: number|null`.
- Un « Oui » est exécuté **même quand l'assistant est en pause** (la pause n'arrête que son travail). **App** : Oui,
  Non, Corriger restent possibles en pause ; bandeau « Assistant en pause : vos décisions s'exécutent, il ne prépare
  rien de nouveau » avec « Reprendre ». Jamais de « Oui » dans une notification `DECISION_ENVOI` ni pour une carte
  `envoi_tiers`. « Corriger » sur toute validation (`modifiable` pré-remplit seulement le texte).
- « Oui » plus long que le délai : l'app affiche « L'envoi prend plus de temps que prévu : vérifiez dans un instant »
  et relit `/decisions` (le PC refuse un double traitement).

**Argent et chantiers**
- `a_refacturer.achats[]` : `id` unique (`achat:12`), `libelle`, `fournisseur`, `chantier`, en plus des anciens champs.
- `heures_secretariat.heures_decimal: number`. `elements[].numero` (« RE-00036 », vide pour les achats).
- `semaine[]` et `chantiers_7_jours[]` : `client`, `date_debut`, `date_fin`, `etape`.
- `POST /actualiser` en échec → `503 {ok:false, erreur:"bexio_indisponible", message}`.
- `GET /app/doc/offre/{id}` en échec → `503 {erreur:"pdf_indisponible", message}` en JSON (pas un PDF) ; l'aperçu
  affiche ce message. **App** : un 503 avec corps JSON n'est jamais pris pour un tunnel mort ; l'extension réelle des
  fichiers est gardée. Délais : 45 s pour `/accueil` et `/argent`.

**Saisies et questions**
- `POST /saisie` (multipart `texte`, `photos[]`, champ facultatif `agent`) → `{ok, message, saisie_id}`. Renvoi
  identique dans les 15 minutes (file hors ligne) → **le même** `saisie_id`, « Déjà transmis. ». Un texte qui commence
  par « Question du patron » est une question (lecture seule) ; `[Pour l'agent X]` oriente vers le domaine.
  **App** : photos toujours en JPEG (qualité 0,85, grand côté 2560 px).
- `GET /saisies?limite=30` → `[{id, cree, texte, photos, statut: transmis|en_cours|traite|erreur, resume,
  decision_reference, question: bool, agent, tache_id}]`, la plus récente d'abord.
- `POST /assistant/question {question, agent?, contexte?}` et `POST /agents/{id}/question {question}` →
  `202 {statut:"en_cours", question_id, agent, message?}` ; `message` hors des horaires de l'assistant (« L'assistant
  répondra à son prochain passage (du lundi au vendredi, de 7 h à 18 h). »).
- `GET /questions/{question_id}` → `{statut: en_cours|repondu|erreur, question_id, agent, reponse?, message?,
  decision_reference?}`.
- Une question est exécutée **en lecture seule** (outils d'écriture bloqués par le PC). La réponse arrive quand
  l'assistant passe : du lundi au vendredi, de 7 h à 18 h, toutes les 20 min environ — **pas instantané**.
  **App** : la voix ne transmet rien sans geste (question ou demande affichée, « Envoyer » / « Transmettre ») ;
  `GET /questions/{id}` toutes les 2 s pendant 60 s, puis à chaque `maj saisies` ; avec `message`, l'app l'affiche,
  le dit, et n'interroge plus (la réponse arrivera par notification `SAISIE_TRAITEE` et dans l'historique).

**Assistant et bureau**
- `GET /assistant/etat` → `{pause, file, en_cours, derniere_activite, en_service: bool, horaires: "du lundi au
  vendredi, de 7 h à 18 h"}` ; `POST /assistant/pause`, `/assistant/reprise` → `{ok, …etat}`.
- `GET /agents` → `{agents: [Agent], assistant: {…etat}}`, `Agent = {id, nom, role, icone, etat: libre|occupe|pause|
  erreur|hors_horaires, tache, depuis, file, traitees_jour, derniere_activite, resume_jour, horaires}`. Ids fixes :
  `secretariat`, `comptabilite`, `offres`, `chantiers`, `achats` — **domaines d'un seul assistant**, présentés ainsi
  (« L'assistant, côté Comptabilité »). **App** : jamais « Disponible » hors des horaires (« Repasse lundi à 7 h »).
- `GET /journal?limite=30`, `GET /agents/{id}/journal` → `{entrees: [{id, horodatage, agent, type: action|decision|
  erreur|email_prepare|question|info, titre, detail, decision_reference}]}` ; agent inconnu → 404.

**Événements et voix**
- `GET /evenements` (SSE) : `retry: 5000`, puis `event: maj` avec `data: {"quoi": "decisions"|"saisies"|"chantiers"|
  "argent"|"agents"}` ; commentaire `: ping` toutes les 15 s. **Pas encore** d'événements `agent`, `journal`,
  `reponse` : sur `maj saisies`, l'app recharge `/saisies` et vérifie les questions en attente.
- `POST /voix/session` → `{disponible: false, message}` : le moteur local reste le moteur par défaut (pas de voix
  temps réel payante tant que la direction ne l'a pas activée).

**Push APNs** (prêt côté PC, actif dès que la clé Apple .p8 y est déposée)
- Catégories `DECISION`, `DECISION_ENVOI`, `INFO` (question de l'assistant, `reference` = `Q-…`), `SAISIE_TRAITEE`
  (`reference` = décision préparée, sinon id de la saisie) ; `thread-id` : `decisions`, `chantier-<id>` ou `saisies`.

**Routes facultatives** : après un 404 ou un 405, l'app ne rappelle plus la route pendant la session (mémoire par hôte,
remise à zéro au lancement).

## v1.0 — en production

```
GET  /accueil      → {salut, date, pause: bool, decisions: [Decision], encaisser, offres, payer, chantiers_7_jours: [ChantierResume]}
       encaisser = {factures: [{facture_id: number, numero, titre, contact_id: number, montant: number, echeance,
                                retard_jours: number, relance: string, client}],
                    total: number, anciennete: {a_echoir, "0_30", "31_60", plus_60: number}}
       offres    = {offres: [{offre_id: number, numero, titre, contact_id: number, montant: number, emise_le,
                              valable_jusqu_au, relances: number, client}], total: number}
       payer     = {factures: [Achat], total: number, cette_semaine: [Achat], total_semaine: number}
Decision       = {type: "validation"|"question", reference: "V-XXXXXX"|"Q-XXXXXX", genre, titre, motif, cree,
                  controle: null|{ok, resume, points_a_verifier: [{controle, detail, document}]},
                  texte: string, destinataires: [string], objet: string, documents: [string],
                  pieces: [{nom, url}], outil: string, modifiable: bool}
Achat          = {id: number, fournisseur, numero, montant: number, echeance, objet, reference: null|string,
                  dossier_id: null|number, statut, source, created_at, paid_at: null|string, jours_restants: number}
GET  /decisions    → {decisions: [Decision], decisions_autorisees: bool}
POST /decisions/{reference}/{oui|non|corriger|repondre}  {consignes?: string} → {ok: bool, message: string}   (400 si refus)
GET  /chantiers?etape=tous|demande|offre|acceptee|planifie|realise|facture|paye
                   → {etapes: [{cle, libelle, nombre: number}], chantiers: [ChantierResume], semaine: [ChantierResume], calendrier_ics}
ChantierResume = {id: number, titre, client, lieu, etape, etape_libelle, etape_index: number, statut, montant: number,
                  note: null|string, mis_a_jour, date_debut: null|string, date_fin: null|string, dates: string,
                  decision_en_attente: bool}
GET  /chantiers/{id} → ChantierResume + {elements: [{type, ref, libelle, montant: number, date, statut, echeance, pdf}],
                                         factures_fournisseurs: [Achat]}
GET  /argent       → {encaisser, payer, offres,
                      a_refacturer: {achats: [{dossier_id, dossier, achat, montant, date}], total: number},
                      versements_non_identifies: [{cle, date, montant: number, contrepartie, texte, reference}],
                      heures_secretariat: {heures: string ("31 h 30"), montant: number, mois: string}}
POST /saisie       (multipart : texte, photos[]) → {ok, message}
POST /actualiser   → {ok} | 502
POST /session      {acces} → {jeton, valable_jours, entreprise}
POST /appareils    {jeton_apns, nom, environnement: "sandbox"|"production"} → {ok}
GET  /app/doc/{kind}/{ref} → PDF        GET /app/planning.ics?jeton=… → calendrier
Erreurs : 401 {erreur: "non_authentifie"|"lien_invalide", message}
```

## v1.1 — ajouts (tous optionnels à la lecture)

| Élément | Ajout | Usage dans l’app |
| --- | --- | --- |
| `Decision` | `envoi_tiers: bool`, `chantier_id: number\|null` | `envoi_tiers` fait foi pour « Glisser pour envoyer » ; sinon liste d’outils (`mail_envoyer`, `mail_repondre`, `mail_transferer`, `envoyer_facture`, `envoyer_offre`, `envoyer_rappel`) |
| `a_refacturer.achats[]` | `id, libelle, fournisseur, chantier` | sinon `achat`, `dossier`, `dossier_id` |
| `heures_secretariat` | `heures_decimal: number` | sinon conversion de `heures` (« 31 h 30 ») |
| `elements[]` | `numero: string` (« RE-00036 ») | affiché à la place de `ref` (clé interne « offre:37 ») |
| `POST /actualiser` | échec : `503 {erreur: "bexio_indisponible", message}` | « Bexio ne répond pas, réessayez dans un instant » (502 v1.0 idem) |
| `POST /session` | `{acces, appareil: {nom, modele}}` → `{jeton, appareil_id, valable_jours, entreprise}` | jeton par appareil ; l’ancien jeton commun reste accepté |
| `GET /appareils` | `[{id, nom, modele, cree, vu, actuel: bool}]` | Réglages › Appareils |
| `DELETE /appareils/{id}` | | « Déconnecter cet appareil » |
| `POST /saisie` | `→ {ok, message, saisie_id}` | historique |
| `GET /saisies` | `[{id, cree, texte, photos: number, statut: transmis\|en_cours\|traite\|erreur, resume, decision_reference}]` | Transmis → En cours → Traité → Décision prête |
| `GET /evenements` | SSE `event: maj`, `data: {quoi: decisions\|chantiers\|argent\|saisies}` | rechargement ciblé ; repli : interrogation toutes les 60 s |
| `POST /assistant/pause`, `/assistant/reprise`, `GET /assistant/etat` | `→ {pause, file: number, derniere_activite}` | Entreprise › Assistant |
| Push APNs | `aps.alert`, `aps.thread-id` = chantier, `category` = `DECISION`\|`DECISION_ENVOI`\|`SAISIE_TRAITEE`\|`INFO`, `reference` | actions `VOIR`, et `OUI` pour `DECISION` seulement |
| `POST /voix/session` | `→ {disponible: bool, fournisseur, client_secret, modele, voix, expire, instructions, outils: [...]}` | assistant vocal en direct ; `disponible: false` → moteur local |

### Champ facultatif lu par l'app (toute version)

| Champ | Où | Usage |
| --- | --- | --- |
| `telephone` (ou `fournisseur_telephone`) | `payer.factures[]` | bouton « Appeler » sur la fiche fournisseur ; sinon, le patron saisit le numéro, gardé sur l'iPhone |

## v1.2 — l’écosystème : agents du bureau ↔ app (ajouts, tous optionnels à la lecture)

But : l’app Endry voit **chaque agent** du PC (Secrétariat, Comptabilité, Chantiers, Offres, Achats… la liste vient
du PC), sait **ce qu’il fait en ce moment**, lit **son journal**, lui **pose une question** et reçoit **sa réponse**,
et lui **confie un travail**. Rien ne change pour v1.0 / v1.1 : chaque route ci-dessous est un ajout. Tant qu’une
route répond 404, l’app se replie sur v1.1 (question déposée comme saisie, voir plus bas).

Règles inchangées, et à respecter par chaque agent :
- **Aucun envoi à un tiers sans geste du patron** : un agent prépare (e-mail, facture, offre) et crée une
  `Decision` ; l’envoi part seulement après `POST /decisions/{ref}/oui`.
- **Une question n’agit jamais** : `POST …/question` ne prépare rien, n’envoie rien, ne modifie rien ; elle répond.
- **Pas de relances de factures** sans demande explicite : « Suivi seulement : aucune relance sans votre demande ».
- Jeton par appareil (v1.1) sur toutes les routes ; aucune donnée ne sort du PC hors de ces réponses.

### Routes

| Route | Réponse | Écran de l’app |
| --- | --- | --- |
| `GET /agents` | `{agents: [Agent]}` (ou tableau nu) | Entreprise › Le bureau, Aujourd’hui, pastille de l’assistant vocal |
| `GET /agents/{id}/journal?limite=30` | `{entrees: [Entree]}` (ou tableau nu), la plus récente d’abord | fiche d’un agent |
| `GET /journal?limite=30` | idem, tous agents confondus (`Entree.agent` renseigné) | « Que se passe-t-il au bureau ? » |
| `POST /agents/{id}/question` | corps `{question, contexte?}` → `Reponse` | fiche agent, assistant vocal |
| `POST /assistant/question` | corps `{question, agent?, contexte?}` → `Reponse` ; le PC choisit l’agent si `agent` absent | assistant vocal |
| `GET /questions/{question_id}` | `Reponse` | suivi d’une réponse longue |
| `POST /saisie` (multipart) | champ facultatif `agent` = id de l’agent qui doit traiter la saisie | « Confier à… » |

```
Agent   = {id: "secretariat", nom: "Secrétariat", role: "E-mails, courrier, téléphone, rendez-vous",
           icone?: "envelope.fill" (SF Symbol), etat: "libre"|"occupe"|"pause"|"erreur",
           tache: null|"Répond à Mme Rey (variante WC)", depuis: null|ISO-8601,
           file: number (demandes en attente), traitees_jour: number, derniere_activite: null|ISO-8601,
           resume_jour: null|"12 e-mails triés, 3 réponses préparées"}
Entree  = {id, horodatage: ISO-8601, agent: "secretariat",
           type: "action"|"email_recu"|"email_prepare"|"decision"|"question"|"reponse"|"erreur"|"info",
           titre: "Réponse préparée pour Mme Rey", detail?: string,
           decision_reference?: "V-XXXXXX", saisie_id?: string, chantier_id?: string}
Reponse = {statut: "repondu"|"en_cours"|"erreur", question_id?: string, agent?: "secretariat",
           reponse?: "Mme Gander a rappelé hier à 16 h…" (2 à 4 phrases, à dire à voix haute),
           sources?: [{type: "email"|"facture"|"offre"|"chantier"|"document"|"bexio", libelle, reference?}],
           decision_reference?: string (si l’agent a préparé une décision liée, jamais envoyée), message?: string}
contexte = {ecran?: "aujourdhui"|"chantier"|"facture"|"decision", reference?: string}   (facultatif)
```

- Réponse immédiate : `200 {statut: "repondu", reponse, agent}`. Réponse longue : `200` ou `202`
  `{statut: "en_cours", question_id}`, puis l’app interroge `GET /questions/{question_id}` toutes les 2 s
  (ou reçoit l’événement `reponse`, ci-dessous) jusqu’à `repondu` ou `erreur`. Délai conseillé : < 60 s.
- `id` d’agent : minuscules sans accents, stable (`secretariat`, `comptabilite`, `chantiers`, `offres`, `achats`…).
  L’app reconnaît aussi un agent à son `nom` quand le patron le cite (« demande au secrétariat »).

### Événements en direct (`GET /evenements`, SSE)

Proposés ; **pas encore émis par le PC au 27.09.2026** (seul `maj` l'est). L'app les accepte déjà.

```
event: agent     data: Agent            (changement d’état ou de tâche)
event: journal   data: Entree           (nouvelle entrée)
event: reponse   data: Reponse          (réponse prête, avec question_id)
event: maj       data: {quoi: "agents"} (équivalent : recharger GET /agents)
```

### Assistant vocal temps réel (`POST /voix/session`)

Le PC peut ajouter ses propres outils ; l’app ajoute toujours `bureau` (état des agents) et `demander_claude`
(`{question, agent?}`), qu’elle exécute avec les routes ci-dessus.

### Repli v1.1 (tant que les routes v1.2 répondent 404)

Question déposée comme saisie (`POST /saisie`) avec le texte
`Question du patron (depuis l’assistant vocal de l’iPhone). Réponds-lui dans le résumé, en deux ou trois phrases
à dire à voix haute ; ne prépare et n’envoie rien : [Pour l’agent Secrétariat] « … »` ; la réponse est lue dans
`GET /saisies[].resume`. Le PC doit donc, dès v1.1, **répondre dans `resume`** à toute saisie qui commence par
`Question du patron`, et confier la question à l’agent indiqué entre crochets.

Fixtures fictives v1.2 : `agents.json`, `journal.json`, `question-*.json` ; l’`APIDemo` implémente tout v1.2.
