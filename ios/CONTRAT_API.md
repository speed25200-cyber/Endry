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
