# Sécurité et règles métier

## Dépôt public
- Aucun secret : clés d'API, jetons, mots de passe, `.p8`, certificats, URL d'accès, adresses de
  tunnel, identifiants de compte. Vérifier avant chaque commit :
  `git diff --cached | grep -nEi 'token|secret|apikey|bearer [a-z0-9]|\.p8|ts\.net|-----BEGIN'`.
- Aucune donnée réelle : clients, fournisseurs, employés, montants, adresses, IBAN, numéros de
  facture réels. Fixtures et démo : **fictives crédibles** (noms plausibles, montants ronds réalistes,
  adresses inventées).
- `.gitignore` : `*.xcodeproj` généré, `build/`, `*.p8`, `*.mobileprovision`, `.env*`, `DerivedData`.
- Les identifiants publics (bundle id, Apple ID numérique de l'app, appId Codemagic) peuvent figurer
  dans la config CI.

## Données sur l'iPhone
- Jeton dans le **trousseau** (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`), jamais dans
  `UserDefaults`.
- `URLSession` éphémère : pas de cache disque, pas de cookies.
- Cache hors ligne chiffré par la protection de fichiers iOS (`.completeUntilFirstUserAuthentication`).
- Face ID facultatif à l'ouverture ; masquage du contenu dans le sélecteur d'apps.
- Position (rappel à l'arrivée sur chantier) : ne quitte jamais l'iPhone.

## Gestes et décisions
- **Tout « Oui » se donne en glissant** ; un envoi à un tiers (`envoi_tiers`) jamais depuis une
  notification, jamais par un tap.
- « Non » et « Corriger » toujours disponibles ; « Corriger » ouvre un texte pré-rempli si `modifiable`.
- « Oui » plus long que le délai : « L'envoi prend plus de temps que prévu : vérifiez dans un instant »,
  puis relecture — le PC refuse un double traitement.
- Interdits de l'entreprise (ex. aucune relance automatique de facture) : aucune UI ne propose
  l'action interdite ; les questions de la voix sont exécutées **en lecture seule** par le PC.

## Mode « devant le client »
Un interrupteur masque tout ce qui ne doit pas être vu par un client à côté du patron : à payer,
solde net, marges, salaires. L'accueil montre alors seulement l'ancienneté de ce qui est dû.

## Rôles
- Patron : tout. Ouvrier (mode équipe) : ses chantiers, pointage, bons, photos ; pas de finances.
- Le rôle vient du jeton (`session.role`), jamais d'un réglage local.

## Langue et ton
- Langue et région de l'entreprise (français de Suisse : `’` pour les milliers, « CHF », « septante »
  dans la voix si souhaité). Vouvoiement, phrases courtes, aucune jargon technique visible
  (« le bureau », « l'assistant », pas « API », « SSE », « 404 »).
