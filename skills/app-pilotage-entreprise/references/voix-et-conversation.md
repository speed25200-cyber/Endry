# Voix et conversation — latence quasi nulle

## Architecture
```
iPhone                                         PC du bureau
───────                                        ─────────────
Conversation (texte) ──POST /assistant/question──▶ agent (process chaud)
        ▲  SSE: reponse_partielle / reponse ◀──────┘
        └─ long-poll GET /questions/{id}?attendre=20 (secours)

Assistant vocal
  Micro ─▶ transcription locale (SpeechAnalyzer iOS 26 / SFSpeechRecognizer)
        ─▶ fin de phrase détectée (FinDePhrase) ─▶ même chemin que le texte
  ou : moteur temps réel (WebSocket audio bidirectionnel) — relais vers le bureau pour les données
  Réponse ─▶ synthèse vocale + texte affiché en deux blocs
```
L'app ne met **aucune clé d'IA** dans le code : soit la voix passe par le PC (relais), soit le PC
fournit un jeton éphémère pour le moteur temps réel.

## Conversation
- `ModeleConversation` (Kit, `@MainActor @Observable`) : messages `envoye / attente / recu / erreur`,
  `consignerQuestion`, `attendre(id, suivi:)`, `recevoirPartiel(questionId:texte:)` (ignore un fragment
  plus court que le texte déjà affiché, ne touche plus un message reçu), `recevoirReponse(questionId:reponse:)`.
- Chemin le plus rapide gagne : événement SSE `reponse` (avec texte) → affichage immédiat ; sinon
  long-poll ; sinon sondage adaptatif. Les trois écrivent dans le même modèle, sans doublon
  (`questionsSuivies`, `dejaDites`).
- Préchauffer : `.task` de l'écran → connexion SSE + requête légère ; première frappe → idem.
- Réponse longue : afficher le texte en flux ; la voix ne lit qu'un résumé.

## Documents dans le chat (« comme sur Claude »)
- `ReponseAgent.documents` : depuis `documents`/`pieces`/`fichiers` **et** les liens Markdown du texte.
- Carte document sous la réponse : vignette de la 1ʳᵉ page (PDFKit, hors fil principal), nom, type,
  taille ; **toucher = aperçu QuickLook**, `ShareLink` = enregistrer dans Fichiers / partager ;
  bouton « Réessayer » en cas d'échec.
- Téléchargement avec le jeton (même hôte uniquement), fichier temporaire au **vrai nom et à la vraie
  extension** (QuickLook en dépend), cache par URL.
- 404/410 : message humain + règle du contrat « toute pièce annoncée est servie ».

## QuickLook au bon endroit
Une feuille (sheet) recouvre l'écran racine : un `.quickLookPreview` posé sur la racine s'ouvre
**sous** la feuille → « le PDF ne s'ouvre pas ». Solution : un service `Documents` avec une **pile**
de présentateurs ; chaque feuille/plein écran applique `.apercuDocuments()` et seul le présentateur
au sommet affiche l'aperçu (`templates/swift/App/ApercuDocuments.swift`).

## Assistant vocal sans gel
1. Ouverture : l'écran apparaît **immédiatement** (état « Je vous écoute »), le démarrage audio se fait
   en tâche de fond sur `FileAudio`.
2. Compteur de génération (`lancement`) : un démarrage encore en cours quand l'écran se ferme s'arrête
   tout seul en arrivant.
3. Délais bornés : modèle de transcription prêt en ≤ 2,5 s sinon repli ; poignée de main WebSocket ≤ 6 s ;
   choix du moteur ≤ 4 s.
4. Boucle de réception audio dans une tâche détachée qui joue l'audio directement et ne repasse au
   MainActor que pour l'interface ; texte coalescé à ~10 Hz ; niveau du micro à ~60 ms.
5. Fermeture : état de l'app d'abord (l'écran part), arrêt des moteurs ensuite, désactivation de la
   session audio (`notifyOthersOnDeactivation`) sur la file audio.
6. Fin de phrase : délais de base 2,4 s / 1,3 s / 0,8 s / 1,0 s selon la confiance ; patience du relais
   ≥ 1,2 s ; annulation d'une réponse si l'utilisateur reprend la parole dans les 600 ms.
7. Vocabulaire métier injecté dans la reconnaissance (noms de produits, clients fictifs en démo).

## Disposition de l'écran vocal (une seule)
`barreHaute` (fermer, minuteur) → `sphère` (`aspectRatio(1, .fit)`, hauteur 300 ou 128 en compact) →
infos (agent, état) → `ZoneTexte` (deux `Text` : ce que j'ai dit / la réponse, dans une ScrollView) →
cartes (documents) → suggestions (opacité) → champ question. Fermer : bouton en verre + glisser vers le bas.

## Tests (Kit, Linux)
- `LatenceTests` : décodage `event: reponse` complet/signal, `reponse_partielle`, cadence 0,4/0,8/1,5 s,
  `suiviQuestion(id, attente: 20)`, fusion partiel → final, fragment tardif ignoré.
- `DocumentsReponseTests` : extraction des documents (champs + liens Markdown), extension et libellé.
- `FluiditeTests`, `VoixTests` : délais de fin de phrase, patience du relais.
