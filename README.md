# Endry SA — Site et suivi privé de chantier

## Version du 14 septembre 2026

Le site vitrine est conservé dans `public/`. Un backend Worker et une base D1 permettent le suivi privé des chantiers ; R2 stocke les photos. Le code source de ces espaces est dans `worker/index.js`, `public/portail.html`, `public/portail.js` et `public/portail.css`. Aucun dossier client ni secret n’est inclus dans Git.

- `/suivi` : accès client avec un code personnel réutilisable.
- `/admin` : création des chantiers, avancement, nouvelles, photos, remplacement des codes et désactivation des accès.
- Actualisation client toutes les 15 secondes lorsque la page est visible.
- Sur Sites : connexion administrateur avec le compte ChatGPT autorisé côté serveur.
- Sur un hébergement autonome : connexion administrateur avec phrase secrète ; les en-têtes ChatGPT sont ignorés.

Installation : `npm ci`. Construction : `npm run build`. Vérifications backend : `npm test` (Node.js 24+). Aucun serveur ni identifiant externe requis pour ces tests avec SQLite local et stockage simulé. Ils ne remplacent pas la recette sur le domaine final. Aucun test navigateur n’a été demandé.

Voir **[DEPLOIEMENT.md](DEPLOIEMENT.md)** pour l’hébergement indépendant sur Cloudflare Workers/D1/R2 et un nom de domaine propre. Un dépôt GitHub ou un simple espace FTP ne suffit pas à exécuter ce backend.

## Application iPhone « Endry Pilotage »

Le dossier [`ios/`](ios/README.md) contient l’application iPhone native (SwiftUI) de la direction, qui consomme l’API v1 de l’assistant administratif du bureau. Build, tests et publication TestFlight passent par Codemagic ([`codemagic.yaml`](codemagic.yaml)). Voir **[ios/README.md](ios/README.md)**.

Les informations ci-dessous documentent l’historique de la vitrine, pas l’état actuel des accès ou du backend.

## Historique de la vitrine

Version préparée le 5 septembre 2026. Site statique en français de Suisse.

## Identité et sources
- Référentiel Endry SA et consignes projet du 05.09.2026.
- Logo extrait sans redessin de Plaquette_Endry_SA_07_Eclat.pdf ; palette originale or clair #F9DBA3 et bronze #9F722A.
- Photos de réalisations extraites de la page 4 de cette plaquette, noms et attribution conservés.
- Deux images de synthèse illustratives créées pour le site et explicitement légendées.
- Téléphone confirmé : 079 962 30 60 ; e-mail : info@endry.ch.

## Fonctionnement
Le site présente les trois métiers, la méthode, les réalisations, les réponses aux questions et un contact. Galerie accessible via dialogues natifs. Menu mobile, liens téléphoniques, plaquette téléchargeable.
Le formulaire prépare une demande dans la messagerie du visiteur. Il ne transmet pas directement les données à un serveur et ne simule jamais un envoi. Aucun outil d'analyse d'audience, carte distante ou stockage persistant des demandes.

## Mise en ligne publique
Cette édition est déployée en accès privé pour revue. Avant publication publique :
1. Confirmer les horaires et le statut d'accueil à Bussy ; actuellement aucun horaire ni engagement 24/7 n'est publié.
2. Relire la notice de confidentialité selon la messagerie, les durées de conservation et l'hébergement retenus. Compléter les mentions si nécessaire avec les données vérifiées.
3. Choisir un domaine sous contrôle d'Endry SA et le connecter. La boîte info@endry.ch ne prouve pas la disponibilité ni la propriété d'un nom de domaine.
4. Retirer les balises noindex,nofollow et l'interdiction dans robots.txt ; renseigner les URL canoniques et le sitemap avec le domaine public exact.
5. Faire passer l'accès à public uniquement sur mandat explicite, puis redéployer et vérifier les liens sur mobile.
6. Ajouter le domaine public à Google Business Profile et à Search Console. Ne pas y inscrire le lien de revue privé.
7. Si un envoi direct du formulaire est souhaité, raccorder un service de messagerie ou un traitement serveur choisi par Endry SA ; prévoir les retours d'erreur, l'anti-spam et une notice adaptée.

## Vérification effectuée
Syntaxe JavaScript, présence des routes, ressources locales, ancres et alternatives d'images. Pas de test navigateur demandé ni exécuté.

## Modification du 05.09.2026 — Dépannage
À la demande explicite de l’utilisateur, ajout du dépannage dans la présentation, les prestations, une section dédiée avec appel direct, la FAQ et le formulaire. L’objet de l’e-mail distingue les demandes de dépannage. Aucun horaire ni délai d’intervention garanti n’est ajouté. Modification enregistrée dans une nouvelle version, sans modifier l’audience du site.

## Correction demandée — fixe et dépannage visible
Ajout du fixe 026 663 30 60 en complément du mobile 079 962 30 60 dans l’accueil, le contact, le dépannage, le pied de page et les pages informatives. Le dépannage est souligné dès l’accueil. Publication de cette correction sur le site existant demandée par l’utilisateur signalant l’absence des modifications en ligne.
