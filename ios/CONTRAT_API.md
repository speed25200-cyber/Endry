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
- `heures_secretariat.heures_decimal: number`. `elements[].numero` (« RE-00990 », vide pour les achats).
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
                      heures_secretariat: {heures: string ("31 h 30"), montant: number, mois: string},
                      comptabilite (v1.10, facultatif): {a_payer_chf, a_payer_en_retard_chf, a_encaisser_chf,
                        a_facturer_chf, nous_doit_chf: number, etat_au: "AAAA-MM-JJ",
                        a_facturer: [{dossier_id, client, chantier, devis, facture, reste: number,
                          tranches: [{libelle, montant: number, etat: "payée"|"facturée"|"à facturer", facture: null|string}]}],
                        comptes: [{numero, libelle, factures: int, total_chf, ouvert_chf: number}],
                        documents: [{nom, url}]}}
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
| `elements[]` | `numero: string` (« RE-00990 ») | affiché à la place de `ref` (clé interne « offre:37 ») |
| `POST /actualiser` | échec : `503 {erreur: "bexio_indisponible", message}` | « Bexio ne répond pas, réessayez dans un instant » (502 v1.0 idem) |
| `POST /session` | `{acces, appareil: {nom, modele}}` → `{jeton, appareil_id, valable_jours, entreprise}` | jeton par appareil ; l’ancien jeton commun reste accepté |
| `GET /appareils` | `[{id, nom, modele, cree, vu, actuel: bool}]` | Réglages › Appareils |
| `DELETE /appareils/{id}` | | « Déconnecter cet appareil » |
| `POST /saisie` | `→ {ok, message, saisie_id}` | historique |
| `GET /saisies` | `[{id, cree, texte, photos: number, statut: transmis\|en_cours\|traite\|erreur, resume, decision_reference}]` | Transmis → En cours → Traité → Décision prête |
| `GET /evenements` | SSE `event: maj`, `data: {quoi: decisions\|chantiers\|argent\|saisies}` | rechargement ciblé ; repli : interrogation toutes les 60 s |
| `POST /assistant/pause`, `/assistant/reprise`, `GET /assistant/etat` | `→ {pause, file: number, derniere_activite}` | Entreprise › Assistant |
| Push APNs | `aps.alert`, `aps.thread-id` = chantier, `category` = `DECISION`\|`DECISION_ENVOI`\|`SAISIE_TRAITEE`\|`INFO`, `reference` | action `VOIR` seulement (plus aucun `OUI` depuis v1.7) |
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

## v1.3 — terrain, suivi commercial, équipe (ajouts, tous optionnels ; à appliquer par le PC)

But : ce qui se passe sur le chantier arrive au bureau structuré, et le bureau prépare la suite (facture de régie,
matériel à refacturer, offre, entretien, suivi d’offre). **Rien ne part chez un tiers sans le « Oui » du patron** :
chaque route ci-dessous **prépare** et crée au besoin une `Decision` (`envoi_tiers: true` pour tout e-mail ou
facture) ; elle n’envoie jamais rien. Tant qu’une route répond 404/405, l’app passe par `POST /saisie` (repli
décrit pour chaque route) : tout fonctionne déjà avec le PC actuel, en moins structuré.

### Documents terrain — `POST /terrain` (multipart)

| Champ | Contenu |
| --- | --- |
| `type` | `regie` \| `bon_livraison` \| `releve` \| `journee` |
| `cle` | clé d’idempotence (ex. `RG-20260928-1432`) : **un renvoi de la même clé ne crée rien de plus** (file hors ligne) → `{ok:true, message:"Déjà reçu."}` |
| `resume` | résumé en français, lisible tel quel |
| `donnees` | JSON structuré (formes ci-dessous), clés en `snake_case`, dates `AAAA-MM-JJ`, horodatages `AAAA-MM-JJTHH:MM:SS` (heure suisse) |
| `chantier_id` | facultatif |
| `pieces[]` | fichiers : PDF, PNG/JPEG, USDZ (15 Mo max chacun) |

Réponse : `{ok, message, id, decision_reference?}`. Ce que le PC fait de chaque type :

- **`regie`** — bon de régie signé sur place par le client. Le PC prépare la **facture de régie** dans Bexio
  (brouillon) et crée une `Decision` `envoyer_facture` (`envoi_tiers: true`), liée au chantier.
  `donnees = {numero, chantier_id?, chantier, client, lieu?, date, travaux, heures: [{intervenant, heures}],
  materiel: [{designation, quantite, unite}], deplacement: bool, remarques, signataire, signe_le}`.
  Pièces : `<numero>.pdf` (bon signé), `<numero>-signature.png`, photos. **Aucun prix sur le bon** : les tarifs
  sont ceux du bureau.
- **`bon_livraison`** — bon fournisseur photographié. Le PC rattache le matériel au chantier (« à refacturer »)
  et le rapproche de la facture fournisseur quand elle arrive. Aucune décision nécessaire.
  `donnees = {fournisseur?, numero?, date?, commande?, commission?, chantier_id?, chantier?,
  articles: [{reference?, designation, quantite?, unite?}], texte_lu}`. Pièces : pages en JPEG.
- **`releve`** — relevé 3D (RoomPlan, LiDAR). Le PC prépare une **offre** (brouillon + `Decision` si elle
  doit partir). `donnees = {piece, chantier_id?, chantier?, date, murs: [{largeur, hauteur}],
  ouvertures: [{type: porte|fenetre|ouverture, largeur, hauteur}], contour_sol: [{x, y}],
  objets: [{categorie, largeur, profondeur, hauteur}], remarques, releve_par?}` (mètres). Pièces : plan PNG, `.usdz`.
  `releve_par` : prénom de l’ouvrier quand le relevé vient d’un lien d’équipe (absent pour le patron) ; l’offre
  préparée reste une décision du patron, jamais montrée à l’ouvrier.
- **`journee`** — heures d’un ouvrier (lien d’équipe). Le PC reporte les heures par chantier.
  `donnees = {date, ouvrier, lignes: [{chantier_id, chantier, heures}], pointages: [{chantier_id, chantier, debut, fin}],
  remarques}` (heures arrondies au quart d’heure).

Repli (404) : `POST /saisie` avec `texte = "[Pour l’agent <Domaine>] <Type> depuis l’iPhone. <resume>"`
(Comptabilité pour une régie, Achats pour un bon, Offres pour un relevé, Chantiers pour une journée) et les
seules images en `photos[]`.

### Entretiens récurrents

| Route | Réponse |
| --- | --- |
| `GET /entretiens` | `{entretiens: [Entretien]}` — repérés par le PC dans Bexio (chaudières, chauffe-eau, adoucisseurs, PAC…) |
| `POST /entretiens/{id}/proposer` | corps `{consignes?}` → `{ok, message, decision_reference}` : le PC **prépare** une proposition de rendez-vous (e-mail, `envoi_tiers: true`) |

```
Entretien = {id, client, lieu?, appareil, periodicite?, dernier?: AAAA-MM-JJ, echeance?: AAAA-MM-JJ,
             statut: "a_planifier"|"propose"|"planifie", decision_reference?, chantier_id?}
```
Repli (404) : saisie `[Pour l’agent Secrétariat] Préparer une proposition de rendez-vous d’entretien pour …`.

### Offres sans réponse

L’app calcule elle-même les offres émises depuis 15 jours ou plus (réglable), à partir de `GET /argent`
(`offres[].emise_le`, `valable_jusqu_au`, nouveau champ facultatif `dernier_suivi: AAAA-MM-JJ`).

| Route | Réponse |
| --- | --- |
| `POST /offres/{offre_id}/suivi` | corps `{consignes?}` → `{ok, message, decision_reference}` : le PC **prépare** un message de suivi courtois (`mail_envoyer`, `envoi_tiers: true`) et note `dernier_suivi` |

Ce n’est **pas** une relance de facture (celles-ci restent interdites sans demande). Repli (404) : saisie
`[Pour l’agent Offres] Préparer un message de suivi pour l’offre …`.

### Équipe (liens d’accès pour les ouvriers)

- `POST /equipe/invitations {nom}` (jeton du patron) → `{ok, lien, expire_le, message}` : lien d’accès
  `…/app/acces/<secret>` à usage unique, que le patron transmet à l’ouvrier (QR code ou message).
- `POST /session` avec un secret d’équipe → `{jeton, appareil_id, valable_jours, entreprise, role: "ouvrier", nom}`.
  Sans `role`, l’app considère `patron` (comportement actuel).
- `GET /equipe/jour` (jeton d’ouvrier) → `{nom, date, chantiers: [{id, titre, client?, lieu?, adresse?, consignes?,
  contact?, telephone?, debut?}], message?}`.
- **Portée du jeton d’ouvrier, appliquée par le PC** : `GET /equipe/jour`, `POST /terrain` (types `journee`,
  `bon_livraison`, `releve`), `POST /saisie`, `GET /evenements`. Tout le reste répond **403** : ni argent, ni
  décisions, ni agents, ni documents. Révocation : `DELETE /appareils/{id}` comme pour le patron.

Fixtures fictives v1.3 : `entretiens.json`, `equipe-jour.json`, `session-ouvrier.json`, `invitation-equipe.json`,
`terrain-ok.json` ; l’`APIDemo` implémente tout v1.3 (une régie reçue devient une facture à valider).

## v1.4 — suivi de chaque geste : de la décision au résultat (à appliquer par le PC)

Constat du 28.09.2026 : une commande validée à 09:12 a bien produit un fichier sur le PC, mais l’app n’en montrait
rien (la décision disparaît de la liste). **Règle** : tout geste du patron — Oui, Non, Corriger, Répondre, saisie,
question, envoi terrain — a un **compte rendu** que l’app lit et affiche jusqu’au résultat. L’app le montre dans
« Fait récemment » (Aujourd’hui), dans une fiche de suivi (étapes, fichiers produits, envois à des tiers) et dans
l’activité du chantier. Aucune route v1.4 n’agit : elles se lisent.

### Ce que le PC doit garantir (même sans la route `/suivi`)
1. **Chaque étape d’exécution est au journal avec `decision_reference`** (ou `saisie_id`) : prise en charge,
   résultat (`type: action`), erreur (`type: erreur`). L’app rapproche le journal par ces champs.
2. **Chaque envoi à un tiers est consigné** : entrée `type: action`, titre « E-mail envoyé à <destinataire> »,
   `decision_reference` de la décision **qui l’a autorisé**. Un Oui sur une décision `envoi_tiers: false` ne fait
   **jamais** partir quoi que ce soit chez un tiers ; un envoi lié (remerciement au client, etc.) est sa propre
   décision `envoi_tiers: true`, validée à part.
3. **Chaque fichier produit est cité** : `« Nom du fichier.ext »` dans `detail`, précédé de son dossier
   (`Bureau › 00 À traiter › Commandes › « Commande AN-00024 ….txt »`).
4. Un Oui exécuté hors horaires ou en file : entrée `type: info` « En file : exécution au prochain passage ».

### Routes

| Route | Réponse |
| --- | --- |
| `GET /suivi?limite=50` | `{suivis: [Suivi]}`, le plus récent d’abord (gestes des 30 derniers jours, faits dans l’app, par notification, sur la montre ou au PC) |
| `GET /suivi/{reference}` | `Suivi` (facultatif : l’app lit la liste) |
| `POST /decisions/{ref}/{action}` | inchangé ; champ facultatif `suivi: Suivi` dans la réponse |

```
Suivi = {reference: "V-…" | null, saisie_id?: "S-…", titre, genre?, outil?, chantier_id?,
         geste: "oui"|"non"|"corriger"|"repondre"|"transmis", geste_le: AAAA-MM-JJTHH:MM:SS,
         source?: "app"|"notification"|"montre"|"pc",
         etat: "transmis"|"en_cours"|"fait"|"erreur"|"ecarte"|"corrige",
         agent?: "secretariat"|"comptabilite"|"offres"|"chantiers"|"achats",
         etapes: [Entree du journal],                      // mêmes champs que GET /journal
         resultat?: {resume, fichiers: [{nom, emplacement?, document?: "/app/doc/fichier/<id>"}],
                     envois: [{destinataire, objet?, canal: "email"|"courrier"|"bexio", horodatage}]},
         erreur?: string, decision_preparee?: "V-…"}       // nouvelle version après « Corriger », décision issue d’une saisie
```

- `GET /app/doc/fichier/{id}` → le fichier produit (texte, PDF, tableur), pour l’ouvrir depuis la fiche de suivi.
- SSE : `event: maj`, `data: {"quoi": "suivi"}` à chaque changement d’état d’un Suivi.
- Push (facultatif) : catégorie `SUIVI` (`reference`, `etat`), seulement pour `fait` et `erreur`.

Tant que `GET /suivi` répond 404, l’app rapproche `GET /journal?limite=80` (règles 1 à 3 ci-dessus) et
`GET /saisies`, et l’indique (« D’après le journal du bureau »). Fixture fictive : `suivi.json`.

## v1.5 — offres signées, nouvelle offre, nouvelle facture (à appliquer par le PC)

### Offres signées reçues
`GET /offres/signees` → `{offres: [OffreSignee]}` : chaque offre revenue signée (pièce jointe d’un e-mail,
courrier scanné, validation dans Bexio), repérée par l’assistant du Secrétariat.

```
OffreSignee = {id, numero, titre?, client, chantier_id?, chantier?, montant?, signee_le?: AAAA-MM-JJ,
               recue_le?: horodatage, source: "email"|"courrier"|"bexio"|"app", expediteur?,
               document_signe?: "/app/doc/fichier/<id>", document?: "/app/doc/offre/<id>",
               suite: "a_planifier"|"planifiee"|"acompte_facture"|"facturee", decision_reference?}
```
L’app les classe par `suite` (À planifier d’abord) dans Finances › Offres signées, ouvre le document signé et
propose « Facturer l’acompte ». Repli (404) : chantiers à l’étape `acceptee` ou `planifie`, signalés comme déduits.
Le PC passe le chantier à l’étape « acceptée » dès qu’il reconnaît une offre signée, et consigne au journal
`type: action`, « Offre AN-… signée reçue de <expéditeur> ».

### Nouvelle offre, nouvelle facture (demandées depuis l’iPhone)
Par `POST /terrain` (même formulaire, même idempotence par `cle`, même file hors ligne que v1.3) :

- **`demande_offre`** — l’assistant (domaine Offres) prépare l’offre **en brouillon dans Bexio**, puis une
  `Decision` `envoyer_offre` (`envoi_tiers: true`, PDF en pièce, destinataire = e-mail du client) ;
- **`demande_facture`** — l’assistant (Comptabilité) prépare la facture en brouillon, puis une `Decision`
  `envoyer_facture` (`envoi_tiers: true`).

```
donnees = {type: "offre"|"facture", chantier_id?, chantier?, client, client_email?, client_adresse?, objet,
           lignes: [{designation, quantite?, unite?, prix_unitaire?}],   // sans prix : tarifs du bureau
           consignes,                                                   // dictée complète, telle quelle
           validite_jours?, offre_numero?, acompte_pourcent?, delai_paiement_jours?, date}
```
Réponse : `{ok, message, id, decision_reference?}` — `decision_reference` dès que le brouillon est prêt (sinon plus
tard, rattachée au Suivi v1.4 par `saisie_id` = `id`). **Rien ne part au client** avant le Oui du patron sur cette
décision (glisser pour envoyer). Repli (404) : saisie `[Pour l’agent Offres] Nouvelle offre depuis l’iPhone. …` ou
`[Pour l’agent Comptabilité] Nouvelle facture depuis l’iPhone. …`. Fixture fictive : `offres-signees.json`.

## v1.6 — heures du secrétariat en détail, assistant en mode direct (à appliquer par le PC)

### Heures du secrétariat
`GET /heures/secretariat?mois=AAAA-MM` (mois en cours sans paramètre) → même objet que `argent.heures_secretariat`,
enrichi (tous les champs sont facultatifs ; `/argent` peut déjà les porter) :

```
{mois: "septembre 2026", periode: "2026-09", heures_decimal, montant?, tarif?,
 lignes: [{date: AAAA-MM-JJ, libelle, heures, client?, categorie?}],
 documents: [{nom, format: "pdf"|"xlsx", chemin: "/app/doc/fichier/<id>"}],
 mois_disponibles: ["2026-09", "2026-08", …]}
```
L’app affiche le détail (par travail, jour par jour), ouvre les documents du bureau (PDF, Excel) et produit
elle-même un tableau Excel (.csv) et un relevé PDF à partir des lignes. Repli (404) : le total seul, et
« Demander le détail au bureau » (question en lecture seule).

### Assistant en mode direct (comme une conversation ouverte)
Constat : les questions posées à la voix attendaient le passage de l’assistant (toutes les 20 min). Le patron
demande que ses questions partent et soient traitées **tout de suite**, comme dans une session Claude ouverte.

- `POST /assistant/question` et `POST /agents/{id}/question` reçoivent `mode: "direct"`, `conversation_id` (même fil
  pour les questions qui se suivent, nouveau fil après 30 min) et `contexte` (trois derniers échanges).
- **Mode direct** : le PC lance l’assistant **immédiatement** (session dédiée, **lecture seule** pour une question,
  outils d’écriture bloqués comme aujourd’hui), sans attendre le passage des 20 min, en gardant le fil de la
  conversation. Réponse `202 {statut:"en_cours", question_id}` puis, dès que c’est prêt :
  `event: reponse` `data: {"question_id": "…"}` sur `/evenements` (l’app relit alors `GET /questions/{id}`).
  Hors horaires, si la direction le souhaite, le mode direct peut rester actif ; sinon `message` explique le délai.
- Une **demande** dictée (« prépare… ») part en saisie comme aujourd’hui ; en mode direct, le PC la traite aussitôt
  et consigne le résultat au journal (Suivi v1.4). Elle ne fait jamais partir quoi que ce soit chez un tiers : les
  envois restent des décisions validées à l’écran.
- Côté app : ce qui est dit part après un court délai d’annulation (réglage « Envoi direct au bureau », actif par
  défaut) ; `GET /questions/{id}` chaque seconde pendant 20 s puis toutes les 2 s jusqu’à 3 min.

### Conversation (écrite ou dictée) — mêmes routes, rien de nouveau à exposer
L’app a un écran « Conversation » (Aujourd’hui › Écrire, Entreprise › Le bureau, assistant vocal, raccourci
« Écrire au bureau ») : un fil écrit comme une session Claude ouverte, partagé avec l’assistant vocal (même
`conversation_id`, mêmes `contexte`). Il utilise uniquement les routes v1.6 :
- **Question** (lecture seule) : `POST /assistant/question` ou `POST /agents/{id}/question` en `mode: "direct"` ;
  la réponse s’affiche dans le fil, mise en forme. Le PC peut répondre en **Markdown léger** (titres `##`, listes
  `-` ou `1.`, **gras**, liens) : l’app le met en forme à l’écran et le retire pour la voix. `decision_reference`
  dans la réponse ajoute un bouton « Voir la décision … à valider ».
- **Demande** (« prépare… », « rédige… ») : `POST /saisie` comme aujourd’hui, avec `[Pour l’agent X] ` en tête
  quand le patron a choisi un domaine ; son avancement vient du Suivi (v1.4) et s’affiche sous la demande.
- Aucun envoi à un tiers ne part d’une conversation : il reste une décision à valider à l’écran.

## v1.7 — tout « Oui » en glissant, mode direct complet, suivi fiable (28.09.2026)

### Décisions : `geste_requis`
- Chaque décision peut porter `geste_requis: "glisser"`. L’app l’honore et **applique la même règle s’il est absent** :
  toute décision se valide par « Glisser pour valider » (« Glisser pour envoyer » quand `envoi_tiers` vaut true).
  Il n’existe plus de « Oui » à simple toucher.
- Aucun « Oui » ne part de la voix, de Siri, des raccourcis, de la montre, des App Intents ni des notifications.
  La voix peut afficher une carte (`proposer_decision`), jamais la valider. `POST /decisions/{ref}` avec
  `action: "oui"` n’est émis qu’après le glissement à l’écran.
- « Non » (avec confirmation) et « Corriger » restent des boutons.

### Notifications
- Aucune catégorie n’a d’action « Oui ». Seule reste « Voir », qui ouvre la carte à glisser.
- `SAISIE_TRAITEE` : la charge peut porter `saisie_id` (texte ou nombre). Sans `decision_reference`, l’app ouvre
  l’historique des saisies sur cette saisie.

### Mode direct : plus de lecture seule
- Une question ou une demande (`/assistant/question`, `/agents/{id}/question`, `/saisie`) est traitée tout de suite
  et le PC fait ce qui est demandé ; les envois deviennent des décisions à glisser.
- Quand `GET /questions/{id}` ne renvoie pas de `message`, l’app n’écrit plus « lecture seule » ni « au prochain
  passage » : elle affiche « Le bureau s’en occupe », puis la réponse. Un `message` (hors horaires, délai) reste
  affiché tel quel.
- Préfixe des questions repliées en saisie : « Question du patron (depuis l’app). Traite-la tout de suite… ».

### Repli d’une question sur `/saisie` (sans doublon)
- L’app ne passe à la route suivante (`/agents/{id}/question` → `/assistant/question` → `/saisie`) que sur **404 ou
  405**. Une erreur 5xx, un délai dépassé, un 2xx illisible ou `en_cours` sans `question_id` : la question est
  considérée comme reçue, **aucun nouvel envoi** (pas de question en double).

### Suivi (v1.4) : le compte rendu arrive toujours
- Une route marquée absente (404) est réessayée **toutes les 5 minutes** et au retour au premier plan.
- L’app lit toujours `GET /saisies` pour rapprocher les saisies ; sur `event: reponse`, elle relit la fiche concernée.
- Journal : une entrée `type: "reponse"` avec `saisie_id` marque l’action correspondante « Fait ».
- Plus de sondage périodique de l’écran Bureau ni de la voix : les événements SSE (`/evenements`) suffisent ; l’app
  relit aussi au retour au premier plan.

### Relevé des heures du secrétariat : produit par le bureau
- L'iPhone ne génère plus de PDF ni de CSV : il ouvre les `documents` de `GET /heures-secretariat` (PDF et `.xlsx`
  mis en page par le bureau) et peut en demander un à jour. La demande part en saisie, préfixée
  `[Pour l’agent Secrétariat]` : PDF (en-tête Endry SA, jour par jour, sous-totaux par travail, total, tarif,
  montant HT) et Excel (mêmes colonnes, un onglet par travail, totaux en formules). Le PC les range avec les
  documents du mois ; le compte rendu arrive dans la conversation.
- Les comptes rendus (`fait` / `erreur`) et les questions `Q-…` du bureau entrent aussi dans le fil
  « Conversation », comme une session ouverte avec Claude.

## v1.8 — conversation quasi instantanée avec le bureau (02.10.2026, à appliquer par le PC)

Demande du patron : « une communication instantanée presque entre l’app et l’agent sur le PC ». Tout ce qui suit est
**facultatif et rétrocompatible** : l’app fonctionne déjà sans, et devient instantanée dès que le PC l’applique.

### Ce que l’app fait déjà (côté iPhone)
- Une seule connexion au PC pour tout (requêtes et `/evenements`), gardée ouverte et chaude ; réchauffée dès
  l’ouverture de la conversation et à la première lettre tapée (`GET /assistant/etat`).
- `GET /questions/{id}` sondé toutes les 0,4 s pendant 10 s, puis 0,8 s jusqu’à 30 s, puis 1,5 s jusqu’à 3 min.
- `event: reponse` traité à l’instant : un seul `GET /questions/{id}` pour la question visée (aucun si la réponse
  est jointe), sans attendre les rechargements en cours.
- Voix : la question part ~1 s après la fin de la phrase (au lieu de ~3,5 s), sans changer la règle du geste
  pour les envois à un tiers.

### À faire sur le PC, par ordre d’effet
1. **Émettre `event: reponse` dès que la réponse est prête**, avec la réponse entière dans `data` :
   `event: reponse` · `data: {"question_id": "Q-…", "statut": "repondu", "agent": "secretariat", "reponse": "…",
   "decision_reference": null}`. L’app l’affiche et la dit sans autre aller-retour. (`data: {"question_id": "…"}`
   seul reste accepté : l’app relit alors `GET /questions/{id}`.)
2. **Réponse en flux** : pendant que l’assistant écrit, `event: reponse_partielle` ·
   `data: {"question_id": "Q-…", "texte": "<texte cumulé depuis le début>"}`, au plus ~5 fois par seconde. L’app
   affiche les mots à mesure dans la conversation ; la réponse finale (`event: reponse`) fait foi.
3. **Attente longue** sur `GET /questions/{id}?attendre=20` : le PC peut garder la requête ouverte jusqu’à 20 s et
   répondre à l’instant où la réponse est prête (sinon `{statut: "en_cours"}` à l’échéance). Un PC qui ignore le
   paramètre répond tout de suite comme aujourd’hui ; l’app relance aussitôt une requête gardée ouverte.
4. **Flux SSE sans tampon** : `Content-Type: text/event-stream`, `Cache-Control: no-cache`,
   `X-Accel-Buffering: no`, écriture et vidage (`flush`) de chaque événement immédiatement ; `: ping` toutes les
   15 s (déjà fait). Un proxy ou un tunnel qui met le flux en tampon retarde tout de plusieurs secondes.
5. **Mode direct sans démarrage à froid** : `POST /assistant/question` répond `202` en moins de 100 ms et lance le
   travail en arrière-plan ; une session de l’assistant reste ouverte par `conversation_id` (pas de nouveau
   démarrage à chaque question). Une question simple peut répondre directement `200 {statut: "repondu"}`.
6. **Connexions gardées** : HTTP/1.1 keep-alive (ou HTTP/2 via le tunnel), sans fermeture après chaque requête.

## v1.9 — documents dans la conversation (02.10.2026, à appliquer par le PC)

Demande du patron : « quand je demande un PDF dans le chat, pouvoir voir l’aperçu et l’enregistrer, comme sur Claude ».

- `Reponse` (réponse à `POST /assistant/question`, `GET /questions/{id}`, `event: reponse`) peut porter
  `documents: [{"nom": "Offre OF-00037.pdf", "url": "/app/doc/offre/OF-00037"}]` (`pieces` ou `fichiers` acceptés).
  `url` : chemin sur le PC (téléchargé avec le jeton de l’appareil) ; PDF, Excel, Word, images.
- À défaut, un lien Markdown vers un document dans le texte de la réponse suffit :
  `[Offre OF-00037.pdf](/app/doc/offre/OF-00037)` — l’app le retire du texte et l’affiche en document joint.
- **App** : sous la réponse, une carte par document (vignette de la première page, nom, type) ; toucher = aperçu
  plein écran (feuilleter, zoomer) ; flèche = « Enregistrer dans Fichiers » ou partager. Les fichiers restent
  dans le dossier temporaire de l’app et sont effacés au lancement et à la déconnexion.
- Le PC sert ces fichiers comme les PDF d’offres et de factures (`GET /app/doc/…`), avec le bon `Content-Type`
  et, en cas d’échec, `503 {erreur: "pdf_indisponible", message}` en JSON.
- **Toute pièce annoncée doit être servie** (02.10.2026) : `Decision.pieces[].url` et `documents[].url` pointent vers
  une route que le PC sert avec le jeton (`GET`). Les PDF Bexio passent déjà par `/app/doc/offre/{id}` et
  `/app/doc/facture/{id}` ; un fichier généré dans le dossier du bureau (ex. « Planning Villa Favre (version
  client).pdf ») doit l’être aussi, par exemple `/app/doc/fichier/{id}` (identifiant opaque, jamais un chemin du
  disque). Constat : la décision V-9DHDTK annonce ce planning, mais son adresse répond 404 — l’iPhone ne peut pas
  l’afficher. L’app affiche alors : « Le bureau n’a pas encore mis … à disposition de l’iPhone ».

## v1.10 — photos et PDF dans la conversation (05.10.2026, en service sur le PC)

Demande du patron : « pouvoir mettre des photos dans le chat avec l’agent ».

- `POST /assistant/question` et `POST /agents/{id}/question` acceptent, en plus du JSON (inchangé), un corps
  `multipart/form-data` avec les mêmes champs (`question`, `agent`, `contexte`, `conversation_id`, `mode`) et un champ
  `photos` répété : JPEG, PNG, HEIC, WebP ou PDF, 15 Mo au plus par fichier. `question` peut être vide s’il y a au
  moins une pièce. Réponse identique : `202 {statut: "en_cours", question_id}`, puis `event: reponse`.
- Erreurs : `400 {statut: "erreur", message}` (« Question vide. », « Photo trop lourde (15 Mo au maximum). »).
- Un même envoi répété (même texte, mêmes tailles de fichiers) rend le même `question_id` : la file hors ligne peut
  rejouer sans doublon.
- **App** : bouton « + » du champ d’écriture (appareil photo, photothèque, fichier PDF), six pièces au plus par
  message, vignettes à retirer avant l’envoi ; images converties en JPEG (2560 px au plus, sans localisation). Dans
  la bulle du patron : vignettes, toucher = aperçu plein écran. Les pièces restent sur l’iPhone à côté du fil
  (`pieces-conversation/`, effacées avec la conversation et à la déconnexion). Avec une pièce jointe, le message part
  toujours comme une question : le bureau regarde, répond et prépare ce qui est demandé ; tout envoi reste une
  décision à glisser. Sans réseau, le message et ses pièces repartent seuls au retour du réseau.

## v1.11 — brouillons d’offres et offre jointe à la réponse (05.10.2026, en service sur le PC)

Constat du patron : une offre préparée par le bureau (brouillon Bexio) n’apparaissait ni dans les offres de l’app ni
en pièce jointe de la réponse dans la conversation.

- `GET /argent` : `offres.brouillons: [Offre]` (mêmes champs, `statut: "brouillon"`), hors de `offres.total`.
  **App** : Finances › Offres, section « Brouillons à relire » ; toucher = PDF au modèle Endry (`/app/doc/offre/{id}`).
- `Reponse.documents` et `documents` des saisies : toute offre créée ou modifiée pour la demande y figure
  (`{nom: "Offre AN-00040.pdf", url: "/app/doc/offre/40"}`), même si aucun fichier n’a été généré.
- **App** : le compte rendu d’un geste abouti (réponse à une question `Q-…`, Oui, Corriger) porte ses fichiers
  produits en documents à ouvrir, plus seulement leurs noms.

## v1.12 — courrier reçu et pièces jointes dans la conversation (06.10.2026, en service sur le PC)

### Courrier reçu

- `GET /app/api/v1/mails?limite=40` → `{"mails": [{id, de, objet, recu, categorie, resume, statut, pieces?}]}`.
  `recu` : heure suisse `AAAA-MM-JJTHH:MM:SS`. `pieces` : `[{nom, taille, emplacement, url, document}]` ; absent tant
  que le PC ne connaît pas encore les pièces de cet e-mail (elles arrivent avec le détail), vide s'il n'y en a pas.
- `GET /app/api/v1/mails/{id}` → le même objet avec `de_nom`, `a`, `cc`, `contenu` (texte) et `pieces`.
  404 `introuvable` pour un e-mail que le PC n'a pas traité ; 503 `messagerie_indisponible` si Zoho ne répond pas.
- `GET /app/doc/piece/{dossier}-{message}-{pièce}` sert la pièce jointe (jeton de l'appareil), avec son nom et son type.
  Réservé au patron : 403 pour un accès d'équipe, 404 pour une pièce d'un e-mail inconnu du PC.

### Pièce reçue par e-mail dans la conversation

Quand le patron demande un document reçu (« donne-moi le PDF de… »), l'assistant appelle `mail_montrer_piece` :
la pièce arrive dans `documents` de la réponse (`GET /questions/{id}`, `/saisies`), comme un document produit,
avec `emplacement: "E-mail reçu"` et une `url` `/app/doc/piece/…`. Rien à changer côté app : `CartesDocuments` l'affiche.
