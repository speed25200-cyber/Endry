# Endry Pilotage — application iPhone

Application iPhone native (SwiftUI, iOS 18 minimum) de la direction d’Endry SA. Elle ne fait que **consommer l’API v1**
de l’assistant administratif qui tourne sur le PC du bureau (`/app/api/v1/…`) : aucune logique métier dans l’app,
aucune donnée inventée, aucun paiement, **aucune relance de facture**.

```
ios/
├── project.yml            Projet Xcode (XcodeGen) : app, tests, tests UI
├── EndryKit/              Paquet Swift : modèles, client API, lien d’accès, trousseau, cache hors ligne,
│                          mode démo (fixtures JSON), modèles d’écran (@Observable) — testé avec `swift test`
├── EndryPilotage/         App SwiftUI
│   ├── App/               Point d’entrée, état global, onglets
│   ├── Design/            Palette, typographie, montants CHF, carte héros (shader Metal), verre, animations
│   ├── Fonctions/         Connexion, Décisions, Chantiers, Saisie, Argent, Planning, Réglages
│   ├── Services/          Dictée fr-CH, Face ID, notifications, documents PDF
│   └── Ressources/        Icône (clair / sombre / teintée), polices Inter + Inter Tight (OFL)
└── Tests/                 Tests unitaires de l’app et tests UI (flux principaux + captures)
```

## Écrans

| Onglet | Contenu |
| --- | --- |
| **Décisions** | Salutation, carte héros « À encaisser » (ancienneté à échoir / 0–30 j / > 30 j), offres en attente, à payer cette semaine ; cartes E-mail / Facture / Offre / Question / Paiement avec contrôle qualité, texte complet dépliable, pièces jointes PDF (QuickLook). **Oui / Corriger / Non** : « Glisser pour envoyer » obligatoire quand `outil` envoie quelque chose à un tiers (`mail_envoyer`, `mail_repondre`, `mail_transferer`, `envoyer_facture`, `envoyer_offre`), bouton simple sinon ; « Non » demande confirmation ; « Corriger » et les questions `Q-…` se répondent par dictée ou texte. |
| **Chantiers** | Filtres par étape avec compteurs, rail d’avancement 7 étapes, pastille « Décision en attente », bloc « Sur les chantiers · 7 jours ». Détail : documents, achats fournisseurs, notes, « Dicter pour ce chantier ». Tirer pour actualiser (`POST /actualiser`). |
| **Dicter** (micro doré) | Dictée fr-CH (sur l’appareil si possible), scanner de documents, photos, appareil photo, envoi `POST /saisie`, confirmation « Transmis ». |
| **Argent** | À encaisser par client (retard, 4 tranches), à payer, offres en attente, matériel à refacturer, versements non identifiés, heures de secrétariat. « Suivi seulement : aucune relance sans votre demande. » |
| **Planning** | Semaine en cours et abonnement au calendrier (`webcal://…/app/planning.ics`). |

Réglages (pastille « E » en haut de Décisions) : serveur actuel, nouveau lien, Face ID, notifications, déconnexion.

## Terrain, suivi et équipe (v1.3)

| Fonction | Où | Ce qui se passe |
| --- | --- | --- |
| **Bon de régie signé** | Saisie, fiche chantier, Siri « Bon de régie Endry », Centre de contrôle | Dictée remplie par Apple Intelligence (analyse locale en repli) : travaux, heures par personne, matériel, déplacement ; photos ; écran tourné vers le client, signature au doigt (PencilKit) ; PDF signé à partager. Transmis par `POST /terrain` : le bureau prépare la facture, qui attend votre Oui. Aucun prix sur le bon. |
| **Bon de livraison** | Saisie, fiche chantier, Siri, Centre de contrôle, mode équipe | Scanner (bords détectés), lecture de la structure du document sur l’iPhone (tableaux, iOS 26), extraction Apple Intelligence ; chantier suggéré depuis la commission ; aucun montant lu. Le bureau ajoute le matériel à « à refacturer ». |
| **Relevé 3D** | Saisie, fiche chantier, Siri, mode équipe | RoomPlan (LiDAR, iPhone Pro) : surfaces, périmètre, ouvertures, WC / baignoire / lavabos, plan coté et fichier USDZ ; relevé manuel sinon. Le bureau prépare l’offre. |
| **Entretiens récurrents** | Entreprise › Entretiens | Chaudières, chauffe-eau, adoucisseurs repérés dans Bexio ; « Proposer » : le bureau prépare le rendez-vous, qui attend votre Oui. |
| **Offres sans réponse** | Finances | Offres émises depuis 15 jours (réglable) ; « Préparer un suivi » : message préparé par le bureau, jamais envoyé sans votre Oui. Pas une relance de facture. |
| **Mode équipe** | Entreprise › Inviter un ouvrier (lien + QR) | L’ouvrier voit ses chantiers du jour (consignes, itinéraire, contact), pointe en un geste, relève une pièce en 3D (« Relever » sur chaque chantier), scanne un bon de livraison, dicte ses remarques, envoie photos et journée. Même app, autre accès : jamais l’argent, les décisions, les agents ni la liste du bureau ; pas de bon de régie (il engage une facture) ; le PC limite son jeton. |
| **Suivi de chaque geste** | Aujourd’hui › Fait récemment, fiche chantier › Activité | Chaque Oui, Non, Corriger, saisie ou question reste visible jusqu’au résultat : étapes de l’assistant, fichiers produits, **envois à des tiers (destinataire, heure)**, erreurs ; « Demander au bureau où ça en est » (question en lecture seule). Contrat v1.4 (`GET /suivi`) ; en attendant, rapprochement du journal. |
| **Nouvelle offre, nouvelle facture** | Finances, fiche chantier, Siri (« Nouvelle offre Endry ») | Dictée → client, objet et lignes (Apple Intelligence sur l’iPhone, repli local) ; prix facultatifs (sinon tarifs du bureau). L’assistant prépare le brouillon dans Bexio et une décision d’envoi : rien ne part au client sans le Oui. Contrat v1.5. |
| **Offres signées** | Finances › Offres signées | Offres revenues signées (e-mail, courrier, Bexio), classées : à planifier, planifiées, acompte facturé, facturées ; document signé, « Facturer l’acompte ». Contrat v1.5 ; repli sur les chantiers acceptés. |
| **Heures du secrétariat** | Finances › Heures de secrétariat | Détail par travail et jour par jour, autres mois, documents du bureau (PDF, Excel), tableau Excel et relevé PDF produits sur l’iPhone. Contrat v1.6. |
| **Assistant : envoi direct** | Assistant vocal, Réglages › Voix d’Endry | Ce qui est dit part aussitôt au bureau (un instant pour annuler), dans le même fil de conversation ; réponse attendue en direct (contrat v1.6). Les Oui et les envois aux clients gardent leur geste à l’écran. |
| **Siri, Spotlight, bouton Action** | « Briefing Endry », « Décisions Endry », « Demander à Endry », « Ouvrir \<chantier\> dans Endry »… | Lecture seule ; rien n’est validé ni transmis depuis Siri. Montants dits par Siri seulement si vous l’activez. Chantiers dans Spotlight (effacés à la déconnexion). |
| **Briefing du matin** | Aujourd’hui (carte « Écouter »), notification 7 h en semaine, Siri, CarPlay | Chantiers du jour, décisions, encaissements, échéances, offres et entretiens ; rafraîchi en arrière-plan ; aucun montant sur l’écran verrouillé. |
| **Rappel d’arrivée** | Réglages › Suivi et rappels | 20 zones de 150 m autour des chantiers de la période ; en arrivant : ce qui attend, et « Bon de régie » / « Bon de livraison ». La position ne quitte pas l’iPhone. |
| **Widgets** | Écran d’accueil, écran verrouillé, Centre de contrôle | Décisions, chantiers du jour, encaissements (montants au choix) ; boutons Bon de régie, Bon de livraison, Parler à Endry. Voir « Widgets » ci-dessous pour TestFlight. |

Contrat du PC : `CONTRAT_API.md`, section v1.3. Tant que le PC ne connaît pas une route v1.3, l’app passe par la
saisie (`POST /saisie`) : tout fonctionne déjà, en moins structuré.

## Design et performance

**iPhone et iPad (app universelle).** Sur iPad (`Design/Adaptatif.swift`) : toutes les orientations, Split View et
Stage Manager ; dock flottant centré ; Aujourd'hui, Finances, Entreprise et la fiche chantier en **deux colonnes** ;
chantiers en **grille** (autant de cartes de front que la largeur le permet) ; carrousel de décisions à cartes de
largeur fixe (plusieurs visibles) ; formulaires, outils de terrain, conversation et assistant vocal en colonne
centrée de largeur lisible. En Split View étroit, l'app reprend la mise en page iPhone. Clavier : ⌘1…⌘5 (espaces),
⌘K (Parler à Endry), ⌘N (Écrire au bureau), ⌘R (Actualiser), ⌘↩ (envoyer dans la conversation), Échap (fermer
l'assistant) ; maintenir ⌘ les affiche. La CI capture aussi l'iPad Pro 13 pouces, en portrait et en paysage.

**Identité : la maison Endry SA (style « Galerie »).** Couleurs du logo et du site : brun `#211A13`, crème dorée
`#F9DBA3`, bronze `#9F722A`, papier `#F6F5F2`. Monogramme EY et logo détourés (`Assets.xcassets`), photos
d'ambiance en plein écran (`PhotosMarque`, voir `CREDITS.md` ; deux d'entre elles portent la mention « Ambiance
illustrative »). L'écran Aujourd'hui est une photo sous
une feuille brune ; les décisions sont des cartes papier dans un carrousel, et toucher une carte ouvre sa fiche complète
(texte intégral, destinataires, contrôle, pièces jointes, chantier lié, tous les gestes). Thème clair : papier et
encre brune ; choix Système / Clair / Sombre dans Réglages › Affichage. Jetons dans `EndryPilotage/Design/Palette.swift`.

**Typographie.** Titres en Cormorant Garamond (proche du « ENDRY SA » du logo), étiquettes en capitales Cinzel
(comme la devise « Sanitaire Chauffage Ventilation »), texte et chiffres tabulaires en SF Pro (police du site).
Échelle fixe 34 / 28 / 22 / 17 / 15 / 13 (`Echelle` dans `Typographie.swift`), tout suit Dynamic Type.
Polices embarquées sous licence OFL (instances statiques tirées des polices variables de Google Fonts).

**Mouvement.** Un seul ressort, `Animation.endry` (`response 0.42`, `dampingFraction 0.86`), aucune animation linéaire ;
« Réduire les animations » remplace les déplacements par des fondus (`Animation.endry(reduire:)`).

**Mesurer la fluidité (120 Hz, iPhone 13 ou plus récent).**
1. Sur un Mac, ouvrir le projet, choisir un iPhone réel branché, *Product › Profile* (build Release).
2. Modèle Instruments **Animation Hitches** : lancer l'enregistrement, faire défiler Aujourd'hui, Chantiers,
   Planning et Finances, balayer la pile de décisions, glisser le curseur d'envoi.
3. Critère : aucune *hitch* au-dessus de 5 ms/s de défilement (« Hitch Time Ratio » < 5 ms/s) et aucune image
   au-delà de 8.3 ms dans la piste *Frame Lifetimes*.
4. Si une hitch apparaît : piste **SwiftUI** (mises à jour de vues inutiles) puis **Time Profiler** sur le
   thread principal pendant la même plage.
5. Premier affichage : modèle **App Launch** ; l'écran Aujourd'hui s'affiche depuis le cache hors ligne,
   cible < 300 ms entre le lancement et la première image utile.

## Assistant vocal

Toucher court du micro central : dictée d'une saisie terrain. **Toucher long** (ou « Parler à Endry ») : assistant vocal plein écran
(sphère d'or liquide en Metal, transcription en direct, cartes contextuelles).

- **Moteur temps réel** (`Voix/MoteurTempsReel.swift`) : API Realtime parole-à-parole en **WebSocket natif**
  (`URLSessionWebSocketTask`), sans aucune dépendance tierce : pas de WebRTC à embarquer. L'app ne détient
  jamais de clé : elle demande une session éphémère au PC (`POST /app/api/v1/voix/session`) et utilise le
  `client_secret` de courte durée. Audio en `.voiceChat` (annulation d'écho, haut-parleur, AirPods, CarPlay),
  PCM 16 bits 24 kHz, barge-in (la voix s'arrête net, la réponse est tronquée à ce qui a été entendu).
- **Moteur sur l'iPhone** (`Voix/MoteurLocal.swift`), utilisé si le PC répond `disponible: false` ou n'est
  pas joignable : SpeechAnalyzer / SpeechTranscriber sur iOS 26, SFSpeechRecognizer fr-CH sinon (vocabulaire
  métier en `contextualStrings`), synthèse avec la meilleure voix française installée.
  - **Apple Intelligence** (`Voix/CerveauEndry.swift`, framework FoundationModels, iOS 26, iPhone 15 Pro et
    suivants) : le modèle d'Apple, **entièrement sur l'iPhone**, comprend les questions libres et lit les
    données par les mêmes outils que le moteur temps réel (`accueil`, `decisions`, `chantiers`, `chantier`,
    `argent`, `saisie`, `proposer_decision`). Aucune clé, aucun coût, rien n'est envoyé ailleurs.
    Consignes : `EndryKit/Voix/ConsignesCerveau.swift`.
  - Sans Apple Intelligence : réponses locales aux questions simples (qui doit quoi, chantiers, décisions),
    le reste part en saisie vers l'assistant du PC (gardée hors ligne).
- **Le bureau** (Entreprise › Le bureau, bandeau sur Aujourd'hui, `Fonctions/Bureau/`) : chaque agent de Claude
  (Secrétariat, Comptabilité, Chantiers, Offres, Achats… la liste vient du PC) avec son état en direct, sa tâche,
  sa journée et son journal ; sa fiche permet de **lui poser une question** (réponse affichée, sources, décision
  liée) et de **lui confier un travail** (saisie « Pour l'agent … », rien ne part sans geste). Contrat
  **v1.2** dans [`CONTRAT_API.md`](CONTRAT_API.md) : `GET /agents`, `GET /agents/{id}/journal`, `GET /journal`,
  `POST /agents/{id}/question`, `POST /assistant/question`, `GET /questions/{id}`, événements SSE `agent`,
  `journal`, `reponse`. Tant que le PC ne les publie pas (404), l'app se replie sur v1.1 sans rien perdre.
- **Claude, sur le PC** (`EndryKit/Voix/BureauClaude.swift`) : l'assistant vocal interroge Claude, l'assistant du
  bureau, par le contrat existant, sans modifier le serveur :
  - *« Que fait Claude ? »* (outil `bureau`, pastille en haut de l'assistant) : pause, demandes en cours, derniers
    travaux et décisions à valider (`GET /assistant/etat` + `GET /saisies`) ;
  - *« Demande à Claude… »* et toute question que les données de l'app ne couvrent pas (outil `demander_claude`) :
    la question part comme une saisie marquée « Question du patron… ne prépare et n'envoie rien » (`POST /saisie`),
    une carte « Claude cherche » s'affiche, puis la réponse (le `resume` de la saisie, suivi par `GET /saisies`)
    s'affiche et est lue à voix haute dès qu'elle arrive ;
  - **agents** (`EndryKit/Voix/AgentsBureau.swift`) : Secrétariat (e-mails, courrier, téléphone, rendez-vous),
    Comptabilité (Bexio, factures, paiements), Chantiers, Offres, Achats. L'agent est détecté (« demande au
    secrétariat… », « la compta a payé ? », « des e-mails ? ») et écrit dans la question (`[Pour l'agent
    Secrétariat]`) : Claude, sur le PC, la confie à cet agent ; la carte et la réponse disent quel agent répond ;
  - facultatif : si le PC expose `POST /app/api/v1/assistant/question` (`{question}` → `{reponse}`), la réponse
    est immédiate ; sinon (404) l'app passe par la saisie.
- **Vos mots en direct** : chaque mot reconnu s'écrit en grand pendant que vous parlez (fondu, flou qui se
  dissipe ; mots encore incertains plus pâles), puis se retire au-dessus de la réponse, qui s'allume mot à mot
  au rythme de la voix. Avec le moteur temps réel, une « oreille » SpeechAnalyzer sur l'iPhone (iOS 26) affiche
  les mots pendant la phrase ; la transcription du serveur fait foi à la fin. Texte en SF Pro.
- **Écrire plutôt que parler** : suggestions à toucher et champ « Écrire à Endry… » dans l'assistant
  (mêmes outils, mêmes règles). Toucher la sphère pendant qu'Endry parle l'interrompt.
- **Réponses longues** : dès qu'une réponse dépasse quelques lignes (ou qu'une carte s'affiche), la sphère se range
  en haut à gauche et la réponse se lit en texte courant, aligné à gauche, qui défile (fondu en haut et en bas).
  La réponse du bureau n'est plus répétée dans une carte : un lien discret « Continuer dans la conversation ».
- **Modèle d'Apple au centre de la conversation** (`Voix/CerveauEndry.swift`, `Voix/MoteurLocal.swift`) : en envoi
  direct aussi, ce qui n'est pas une réponse instantanée passe par le modèle embarqué (outils : accueil, décisions,
  chantiers, argent, bureau, briefing ; il pose lui-même la question au bureau quand il le faut). Réponse **en flux** :
  le texte s'écrit à l'écran et chaque phrase est dite dès qu'elle est complète (`DecoupeurPhrases`), sans attendre
  la fin. **Mémoire** de la conversation d'une ouverture à l'autre (page blanche après 30 min ou « on change de
  sujet ») ; les réponses instantanées et celles du bureau lui sont rappelées ; conversation trop longue : nouvelle
  session qui reprend le fil. Consignes « conversation en direct » (phrase courte d'abord, pas de formule creuse,
  une question si c'est ambigu, ne se répète pas après avoir été coupé). Modèle préchargé à chaque ouverture ;
  « Je regarde. » quand un outil prend plus d'une seconde ; on coupe aussi Endry pendant qu'il réfléchit.
- **Conversation continue** (gratuite, sur l’iPhone, iOS 26 et suivants ; expérimentale, à activer dans Réglages › Voix) : le micro reste
  ouvert pendant qu'Endry parle ; sa voix passe par le même moteur audio que le micro (annulation d'écho du système,
  `CanalAudioTempsReel`), et ce qui reste d'écho est écarté (`Interruption`). Le patron **coupe Endry en parlant**
  (deux vrais mots, ou « stop », « attends », « non ») ; s'il reprend la parole moins de 4 s après le début de la
  réponse, c'est la suite de sa phrase et les deux morceaux partent ensemble. Repli automatique sur le tour à tour.
- **Fluidité** (`EndryKit/Voix/FluiditeVoix.swift`) : fin de phrase adaptative qui ne coupe pas la parole (1,2 à
  2,4 s de silence selon la phrase, plus après « euh », « et », « pour ») ; réglages « Temps avant la réponse »
  (court, normal, long) et « Répondre seulement quand je touche la sphère » ; toucher la sphère pendant qu'on
  parle fait répondre tout de suite ; micro rouvert plus vite entre deux tours (langue et modèle de
  dictée vérifiés une fois, modèle préchargé, session audio gardée) ; longues réponses du bureau **dites en résumé**
  (le début, puis « la suite est à l'écran »), réglage « Lire les longues réponses en entier » ; **débit** de la voix
  (posé, normal, rapide, très rapide) ; toucher la réponse interrompt Endry. **Commandes dites**, traitées sur
  l'iPhone sans attendre : « répète », « plus lentement », « plus vite », « ouvre la conversation », « on change de
  sujet », « merci, c'est tout » (ferme l'assistant).
- **Conversation** (`Fonctions/Conversation/`, `EndryKit/Voix/ConversationBureau.swift`) : l'endroit réservé pour
  parler au bureau **par écrit ou en dictée**, comme une session Claude ouverte (Aujourd'hui › « Écrire »,
  Entreprise › Le bureau, bouton en haut de l'assistant vocal, raccourci « Écrire au bureau »). Fil partagé avec
  l'assistant vocal (même `conversation_id`), gardé sur l'iPhone (effacé à la déconnexion). **Question** : part
  tout de suite en lecture seule, « L'assistant réfléchit… » puis la réponse mise en forme (titres, listes, gras),
  à copier. **Demande** (« prépare… », deviné d'après la tournure, modifiable d'un toucher) : part en saisie et
  son avancement (Suivi) s'affiche dessous jusqu'au résultat. Choix du domaine (Secrétariat, Offres…) en haut.
  Rien ne part chez un tiers depuis la conversation.
  Sous chaque réponse : écouter, copier, partager ; sous la dernière, relances d'un toucher (« Plus de détails »,
  « Résume en une phrase », « Et ensuite ? »). Sans réseau, la question est gardée et part seule au retour du
  réseau. Réponse arrivée conversation fermée : un bandeau le signale.
- **Recherche globale** (loupe d'Aujourd'hui, ⌘F ; `EndryKit/Stores/RechercheGlobale.swift`) : décisions,
  chantiers, factures, offres, fournisseurs (sans montant d'achat, masqués devant le client) et conversation,
  instantanément, sur l'iPhone ; toucher un résultat ouvre la décision, le chantier, le PDF ou la conversation.
- **Entrées** : bouton « Parler à Endry » sur Aujourd'hui, toucher long du micro central, et Siri
  (« Parler à Endry », raccourci App Intents ; l'assistant ne s'ouvre qu'après Face ID).
- **La voix ne valide jamais un envoi** : `proposer_decision` affiche la carte, le patron fait le geste
  (« Oui » ou « Glisser pour envoyer »).

## Crédits

Images, polices et licences : [`CREDITS.md`](CREDITS.md). `PhotoRobinetterie` et `PhotoSalleDeBain` sont des
ambiances illustratives (origine non confirmée) : elles ne sont pas présentées comme des réalisations d'Endry SA.

## Sécurité

- Le jeton est rangé **uniquement dans le trousseau iOS** (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`), dans un
  Jamais en clair, jamais dans les journaux, jamais envoyé à un autre hôte que celui du lien.
- Verrouillage Face ID à l’ouverture (réglable) ; contenu masqué dans le sélecteur d’apps.
- Cache hors ligne chiffré par iOS, exclu des sauvegardes, effacé à la déconnexion. Hors ligne : lecture seule, actions désactivées.
- Aucun SDK tiers : uniquement les frameworks Apple. Aucun secret dans le dépôt.

## Développer sur un Mac

Prérequis : Xcode 26 (SDK iOS 26 pour le verre « Liquid Glass » ; repli automatique sur iOS 18) et XcodeGen.

```bash
brew install xcodegen
cd ios
xcodegen generate          # crée EndryPilotage.xcodeproj (non versionné)
open EndryPilotage.xcodeproj
```

- **Mode démo** : sur l’écran de connexion, « Découvrir en mode démo », ou argument de lancement `-demo`
  (Product › Scheme › Edit Scheme › Arguments, déjà présent mais décoché). Données fictives (villas vaudoises et
  fribourgeoises), aucune requête réseau. Les aperçus SwiftUI (`#Preview`) utilisent les mêmes fixtures.
- Arguments utiles : `-sombre` / `-clair` (forcer l’apparence), `-uitests` (tests UI).
- Tests du socle, sans simulateur : `cd ios/EndryKit && swift test` (fonctionne aussi sous Linux).
- Tests de l’app : `xcodebuild test -project EndryPilotage.xcodeproj -scheme EndryPilotage -destination 'platform=iOS Simulator,name=iPhone 17' CODE_SIGNING_ALLOWED=NO`.
- Si Xcode 26 signale « Metal Toolchain missing » : `xcodebuild -downloadComponent MetalToolchain`.

Fixtures JSON : `EndryKit/Sources/EndryKit/Resources/Fixtures/` (accueil, décisions, chantiers, détail des chantiers,
argent, session, erreurs 401). Ce sont aussi les exemples du contrat d’API.

## Connexion au serveur

1. L’assistant envoie à la direction un e-mail avec le lien `https://<hôte>/app/acces/<secret>`.
2. Dans l’app : **Coller** (bouton système, sans alerte), saisie manuelle ou **scan du QR code**.
3. L’app extrait l’hôte et le secret, appelle `POST /app/api/v1/session`, range le jeton dans le trousseau.

L’adresse n’est jamais codée en dur. Quand le tunnel `trycloudflare.com` change, ou lors du passage à Tailscale
(`http://100.x.y.z:8080`), le serveur répond 401 ou ne répond plus : l’app affiche **« Connexion perdue : collez le
nouveau lien »** ; il suffit de coller le nouveau lien (Réglages › Coller un nouveau lien).

### Connexion recommandée : Tailscale (réseau privé, adresse fixe en HTTPS)

Le PC n’est visible que de vos appareils Tailscale (WireGuard) ; aucun port ouvert, rien d’exposé sur Internet.

1. **Console** [login.tailscale.com](https://login.tailscale.com/admin/dns) › **DNS** : activer **MagicDNS** et
   **HTTPS Certificates**.
2. **PC Windows** : installer Tailscale, se connecter ; menu Tailscale › **Run unattended** (fonctionne sans session
   ouverte). Console › Machines › PC › **Disable key expiry**.
3. **PC, invite de commandes** : `tailscale serve --bg 8080` (port de l’assistant). L’adresse affichée,
   `https://<pc>.<tailnet>.ts.net`, est fixe et dispose d’un vrai certificat HTTPS.
4. **Assistant** : utiliser cette adresse dans les liens d’accès : `https://<pc>.<tailnet>.ts.net/app/acces/<secret>`.
5. **iPhone** : app Tailscale (App Store), même compte ; Réglages de l’app Tailscale › **VPN On Demand** pour
   qu’elle se reconnecte seule. Puis, dans Endry, coller le lien.

> Le tunnel `trycloudflare.com` n’est alors plus nécessaire. L’app autorise aussi `http://100.x.y.z:8080`
> (`NSAllowsLocalNetworking`), mais l’adresse HTTPS `*.ts.net` est préférable.

## Codemagic et TestFlight

Le fichier [`codemagic.yaml`](../codemagic.yaml) à la racine du dépôt contient deux workflows :

| Workflow | Déclenchement | Ce qu’il fait |
| --- | --- | --- |
| `ios-tests` | chaque push / pull request touchant `ios/` | `swift test` (EndryKit), build + tests unitaires + tests UI sur simulateur, rapport JUnit, **captures d’écran clair/sombre** en artefacts (`ios/build/captures`) |
| `ios-testflight` | tag `ios-v*` ou lancement manuel | signature automatique Codemagic (certificat + profil App Store), numéro de build, IPA signée, **envoi sur TestFlight** |

Codemagic n’a pas besoin de fastlane : sa CLI (`app-store-connect`, `xcode-project`) gère signature et publication.

### À faire une seule fois (vous)

> **Configuration actuelle** : le workflow `ios-testflight` utilise l’intégration App Store Connect
> **« Dev »** (la clé d’équipe App Store Connect déjà configurée dans Codemagic) et la signature
> automatique de Codemagic (`ios_signing`, bundle `com.endrysa.endry`). Il lance **tous** les tests
> (EndryKit, app, UI) avant de construire l’IPA. Rien n’est stocké dans le dépôt.
>
> Signature : Codemagic › Code signing identities › *iOS certificates* doit contenir un certificat **Apple Distribution**
> avec sa clé (sinon *Generate certificate*), et *iOS provisioning profiles* le profil App Store de `com.endrysa.endry`
> créé **avec ce certificat** (« Certificate : Uploaded »).
>
> Publication : `git tag ios-v2.0.0 && git push origin ios-v2.0.0`, ou *Start new build* › `iOS · TestFlight`.

**1. Clé API App Store Connect** (`ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8`)
- [appstoreconnect.apple.com](https://appstoreconnect.apple.com) › **Utilisateurs et accès** › onglet **Intégrations** ›
  **API App Store Connect** › **Clés d’équipe** › « + » (générer une clé), accès **Gestionnaire d’app** (App Manager).
- Notez l’**ID de la clé** (`ASC_KEY_ID`) et l’**ID de l’émetteur** affiché au-dessus du tableau (`ASC_ISSUER_ID`).
- Téléchargez le fichier `AuthKey_XXXX.p8` (possible **une seule fois**) : son contenu complet, lignes
  `-----BEGIN PRIVATE KEY-----` comprises, devient `ASC_KEY_P8`.

**2. Team ID** (`APPLE_TEAM_ID`) : [developer.apple.com/account](https://developer.apple.com/account) › **Membership details** › Team ID (10 caractères).

**3. Clé privée du certificat de distribution** (`CERTIFICATE_PRIVATE_KEY`) — à générer sur votre Mac :
```bash
ssh-keygen -t rsa -b 2048 -m PEM -f endry_cert_key -q -N ""
cat endry_cert_key          # tout le contenu → CERTIFICATE_PRIVATE_KEY ; gardez le fichier en lieu sûr
```
Codemagic crée avec elle un certificat « Apple Distribution » s’il n’en trouve pas un correspondant.
À ajouter dans Codemagic › app Endry › Environment variables › groupe **`endry_signature`**, cochée **Secure**.
Sous Windows : `ssh-keygen -t rsa -b 2048 -m PEM -f endry_cert_key -q -N '""'` dans PowerShell.

**4. Identifiants dans le portail développeur** — [Certificates, Identifiers & Profiles](https://developer.apple.com/account/resources/identifiers/list) :
- **App IDs** › « + » : `com.endrysa.endry` avec la capacité **Push Notifications** (seule capacité requise).
- **Profiles** › « + » › App Store Connect › `com.endrysa.endry`, avec le certificat de distribution **dont Codemagic
  a la clé** (Codemagic › Code signing identities › iOS certificates), puis Codemagic › iOS provisioning profiles ›
  **Fetch profiles** : le profil doit afficher « Certificate : Uploaded ».
- Si vous préférez un autre identifiant que `com.endrysa.endry` : remplacez-le dans `ios/project.yml`,
  `ios/EndryPilotage/Services/Configuration.swift` et `codemagic.yaml` (`BUNDLE_ID`).

**5. Fiche de l’app** : App Store Connect › **Apps** › « + » › Nouvelle app › iOS, nom « Endry Pilotage »,
langue principale Français, identifiant de lot `com.endrysa.endry`, SKU libre (ex. `endry-pilotage`).
L’**identifiant Apple** numérique affiché dans « Informations sur l’app » peut être ajouté en `APP_STORE_APPLE_ID`
(facultatif : numéros de build calés sur TestFlight).

**6. Codemagic** — [codemagic.io](https://codemagic.io) :
- **Add application** › GitHub › dépôt `speed25200-cyber/Endry` › type « Other » (configuration par `codemagic.yaml`).
- Application › **Environment variables** › groupe **`endry_app_store`** : ajoutez `ASC_KEY_ID`, `ASC_ISSUER_ID`,
  `ASC_KEY_P8`, `APPLE_TEAM_ID`, `CERTIFICATE_PRIVATE_KEY` (cochez **Secure** pour la clé `.p8` et la clé privée),
  et éventuellement `APP_STORE_APPLE_ID`.
- Les secrets restent dans Codemagic, jamais dans le dépôt ni dans GitHub.

**7. Première publication TestFlight**
```bash
git tag ios-v1.0.0 && git push origin ios-v1.0.0
```
ou, dans Codemagic, **Start new build** › workflow `iOS · TestFlight`. Après traitement par Apple (10–30 min),
l’app apparaît dans App Store Connect › TestFlight : ajoutez-vous comme testeur interne et installez-la avec l’app TestFlight.
La question sur le chiffrement est déjà réglée (`ITSAppUsesNonExemptEncryption = NO`, HTTPS uniquement).

### Widgets dans TestFlight (une fois)

Les widgets sont compilés et testés à chaque push, mais pas encore envoyés dans TestFlight : il leur faut leur propre
identifiant et profil.
1. [Identifiers](https://developer.apple.com/account/resources/identifiers/list) › « + » › App IDs ›
   `com.endrysa.endry.widgets` (aucune capacité à cocher).
2. Profiles › « + » › App Store Connect › `com.endrysa.endry.widgets`, avec le **même** certificat de distribution que
   l’app ; puis Codemagic › Code signing identities › iOS provisioning profiles › **Fetch profiles**.
3. Dans `codemagic.yaml`, workflow `ios-testflight`, ajoutez `ENDRY_WIDGETS: "1"` sous `vars:` (ou demandez-le-moi).

Le jeton est alors rangé dans un groupe de trousseau partagé avec le widget (`…com.endrysa.endry.partage`) ; l’app
l’y déplace toute seule, sans nouvelle connexion.

### Private Cloud Compute (facultatif)

Le modèle d’Apple sur ses serveurs privés (iOS 27) rendrait l’assistant bien plus intelligent. Il demande une
autorisation (entitlement) Private Cloud Compute pour Foundation Models, à demander à Apple depuis votre compte
développeur pour `com.endrysa.endry`. Dites-moi quand elle est accordée : je le branche, avec repli automatique sur
le modèle de l’iPhone.

## Notifications push : ce qu’il reste à brancher côté PC

L’app demande l’autorisation après la connexion, puis envoie son jeton APNs au PC :
`POST /app/api/v1/appareils` `{"jeton_apns": "<hex>", "nom": "iPhone", "environnement": "sandbox" | "production"}`
(`sandbox` pour une build Xcode de développement, `production` pour TestFlight / App Store).

Pour envoyer, le PC a besoin de :
- une **clé APNs `.p8`** : Certificates, IDs & Profiles › **Keys** › « + » › cocher *Apple Push Notifications service (APNs)* ;
  notez le **Key ID** et téléchargez le fichier (une seule fois) ;
- le **Team ID** ; le **bundle id** `com.endrysa.endry` (en-tête `apns-topic`) ;
- l’hôte selon l’environnement enregistré : `api.sandbox.push.apple.com` ou `api.push.apple.com` (HTTP/2, jeton JWT ES256).

Charge utile attendue par l’app — la clé `reference` ouvre la bonne carte au toucher :

```json
{"aps": {"alert": {"title": "Nouvelle décision", "body": "Réponse à Mme Bersier — offre salle de bains"}, "badge": 5, "sound": "default"},
 "reference": "V-7K3F9Q"}
```

Exemple Python (à adapter dans l’assistant, dépendances `httpx[http2]` et `pyjwt[crypto]`) :

```python
import time, jwt, httpx

def envoyer_push(jeton_apns, environnement, titre, texte, reference, badge):
    cle = open("AuthKey_KEYID.p8").read()
    jwt_apns = jwt.encode({"iss": TEAM_ID, "iat": int(time.time())}, cle, algorithm="ES256", headers={"kid": KEY_ID})
    hote = "api.sandbox.push.apple.com" if environnement == "sandbox" else "api.push.apple.com"
    with httpx.Client(http2=True) as client:
        r = client.post(
            f"https://{hote}/3/device/{jeton_apns}",
            headers={"authorization": f"bearer {jwt_apns}", "apns-topic": "com.endrysa.endry", "apns-push-type": "alert"},
            json={"aps": {"alert": {"title": titre, "body": texte}, "badge": badge, "sound": "default"}, "reference": reference},
        )
    return r.status_code  # 410 : jeton périmé → le supprimer
```

## Ce qui n’a pas pu être vérifié ici

Le développement a eu lieu sur une machine Linux, sans Xcode :
- **Vérifié** : le paquet `EndryKit` compile en Swift 6 strict et ses 35 tests passent (décodage de toutes les fixtures,
  décodage tolérant, parsing du lien, client API contre un serveur factice `URLProtocol`, 401 / hors ligne / cache,
  Oui / Non / Corriger / question en mode démo, saisie multipart, trousseau en mémoire) ; la syntaxe de tous les fichiers
  Swift de l’app ; le `project.yml` (projet généré avec XcodeGen) ; le `codemagic.yaml` (YAML valide).
- **À vérifier par la première build Codemagic** : compilation SwiftUI / Metal, tests unitaires et UI sur simulateur,
  captures d’écran clair/sombre (artefacts du workflow `ios-tests`).
- **À vérifier sur un iPhone réel** : Face ID, dictée fr-CH sur l’appareil, scanner VisionKit, appareil photo, QR code,
  abonnement `webcal://`, notifications APNs (dépend de l’envoi côté PC), connexion via Tailscale.
