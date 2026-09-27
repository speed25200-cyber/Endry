# Contrat de l’API du PC — `/app/api/v1`

Authentification : `Authorization: Bearer <jeton>`. Hôte : adresse Tailscale privée `https://<machine>.<tailnet>.ts.net`,
fournie par le lien d’accès `…/app/acces/<secret>` et **jamais écrite dans le code**.

L’app décode de façon tolérante (`decodeIfPresent`, valeurs par défaut, clés inconnues ignorées) : elle fonctionne
avec le serveur **v1.0** (production) et **v1.1** (champs et routes ajoutés, tous optionnels à la lecture).

Fixtures fictives : `EndryKit/Sources/EndryKit/Resources/Fixtures/` — `*-v10.json` = réponses v1.0 exactes,
les autres = v1.1 (mode démo). Tests : `EndryKitTests/DecodageTests.swift` (`ContratV10Tests`, `ContratV11Tests`).

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
