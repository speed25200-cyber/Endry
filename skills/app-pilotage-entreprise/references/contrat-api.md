# Contrat d'API (modèle)

Le contrat est le **seul** point de contact entre l'app et l'équipe qui maintient le PC du bureau.
On l'écrit avant de coder, on le versionne (v1.0, v1.1…), on y note ce qui est **implémenté sur le PC**
(fait foi) et ce qui est **demandé** (l'app le gère déjà, de façon tolérante). Modèle complet :
`templates/CONTRAT_API.md`.

## Conventions
- Préfixe `/app/api/v1`, JSON UTF-8, `Authorization: Bearer <jeton>`, `Accept-Language: fr-CH`.
- Hôte privé (Tailscale, WireGuard, VPN) — jamais exposé sur Internet, jamais écrit dans le code.
- Erreurs : `{erreur: "<code>", message: "<phrase pour l'humain>"}` ; l'app affiche `message` tel quel.
- Dates ISO 8601 ; montants en nombre (l'app accepte aussi `"1'250.50"`).
- Champs nouveaux toujours **optionnels à la lecture** ; un serveur plus ancien reste compatible.

## Routes de base
| Route | Rôle |
|---|---|
| `POST /session {acces, appareil:{nom,modele}}` | jeton propre à l'appareil, `entreprise`, `valable_jours` |
| `GET /appareils`, `DELETE /appareils/{id}` | liste et révocation immédiate |
| `POST /appareils {jeton_apns,…}` | notifications push |
| `GET /accueil` | tout le poste de pilotage en une requête (encaisser, payer, ancienneté, offres, semaine, chantiers 7 jours, résumé du jour) |
| `GET /decisions` | cartes à valider : `id, type, titre, resume, envoi_tiers, modifiable, pieces[], chantier_id` |
| `POST /decisions/{id} {reponse: oui|non|corriger, texte?}` | exécution par le PC ; refus d'un double traitement |
| `GET /argent`, `GET /chantiers`, `GET /chantiers/{id}` | espaces détaillés |
| `GET /agents`, `GET /journal` | bureau en direct : état, tâche, file, traitées du jour |
| `POST /saisie` (multipart `texte`, `photos[]`, `agent?`) | saisie terrain, idempotente 15 min |
| `POST /assistant/question {question, agent?, contexte?}` | `202 {question_id, statut:"en_cours"}` |
| `GET /questions/{id}?attendre=20` | long-poll : répond dès que c'est prêt, au plus 20 s |
| `GET /evenements` | flux SSE (voir plus bas) |
| `GET /app/doc/<type>/<id>` | documents (PDF), avec le même jeton |
| `POST /actualiser` | relire l'ERP ; `503 erp_indisponible` |

## Règles qui ont coûté cher (à mettre dans chaque contrat)

### Décisions
- `envoi_tiers: true` pour tout ce qui sort de l'entreprise → **glissement obligatoire**, jamais de
  « Oui » dans une notification.
- Un « Oui » s'exécute même quand l'assistant est en pause (la pause n'arrête que la préparation).
- Questions de l'agent au patron = cartes `Q-…` avec `envoi_tiers: false`.

### Conversation quasi instantanée (v1.8 d'Endry)
- `event: reponse` sur le flux SSE avec la **réponse complète** jointe
  (`{question_id, statut, agent, reponse}`) : l'app l'affiche sans requête supplémentaire.
  Sans texte : simple signal, l'app relit `GET /questions/{id}`.
- `event: reponse_partielle` `{question_id, texte}` : texte cumulé au fil de la génération ;
  l'app l'affiche en direct, un fragment plus court qu'un précédent est ignoré.
- `GET /questions/{id}?attendre=20` : long-poll en secours du SSE.
- Serveur : SSE **sans tampon** (`X-Accel-Buffering: no`, flush à chaque événement), keep-alive
  `: ping` toutes les 15 s, pas de démarrage à froid de l'agent pour une question (process chaud).

### Documents dans les réponses (v1.9)
- `reponse.documents[] = {nom, url, type?, taille?}` (alias acceptés : `pieces`, `fichiers`) ;
  les liens Markdown `[Offre OF-00037.pdf](/app/doc/offre/OF-00037)` dans le texte sont aussi extraits.
- **Toute pièce annoncée doit être servie** par `GET /app/doc/…` avec le jeton de l'appareil.
  Un 404/410 est un bug du PC ; l'app affiche « Le bureau n'a pas encore mis « X » à disposition
  de l'iPhone » (jamais « Not Found »).
- Échec de génération : `503 {erreur:"pdf_indisponible", message}` en JSON (pas un PDF vide).

### Flux d'événements (SSE)
```
event: maj
data: {"quoi": "decisions"}          → l'app recharge l'écran concerné (coalescé)

event: reponse
data: {"question_id": "Q-7", "statut": "repondu", "agent": "secretariat", "reponse": "…", "documents": [...]}

event: reponse_partielle
data: {"question_id": "Q-7", "texte": "Deux factures"}
```
Reconnexion côté app : 0,3 s, 2 s, 5 s puis 15 s ; au retour au premier plan, reconnexion immédiate.

### Horaires de l'assistant
Hors horaires : `202` avec `message` (« L'assistant répondra à son prochain passage… ») — l'app
l'affiche, ne réessaie pas en boucle.
