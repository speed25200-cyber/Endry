# Endry SA — mise en ligne indépendante

Cette version comprend le site vitrine, `/suivi` pour les clients, `/admin` pour Endry SA, le backend et les migrations de base de données. Elle peut fonctionner sans ChatGPT sur **Cloudflare Workers + D1 + R2**, avec un nom de domaine propre. Elle ne se déploie pas telle quelle sur un simple hébergement FTP/PHP ni sur GitHub Pages : ces services ne fournissent pas ce backend. Aucun compte d’hébergement indépendant ni domaine n’est créé par ces fichiers.

## Préparer le compte et le déploiement

Utiliser Node.js 24+, npm et Wrangler. Les commandes ci-dessous sont à exécuter par le propriétaire ou son prestataire dans le dépôt. Elles créent des ressources chez l’hébergeur : vérifier son offre, sa facturation et les lieux de traitement des données avant de les exécuter. Ne pas saisir de secret dans GitHub.

1. `npm ci` puis `npm run build` et `npm test`.
2. `npx wrangler login` pour connecter votre compte Cloudflare.
3. `npx wrangler d1 create endry-sa` et conserver l’identifiant retourné.
4. `npx wrangler r2 bucket create endry-sa-photos`. Garder ce bucket **privé** : aucun domaine public ni accès r2.dev.
5. Copier `wrangler.example.jsonc` vers `wrangler.jsonc`, remplacer `REMPLACER_PAR_ID_D1` et adapter les noms si nécessaire. Conserver `ADMIN_AUTH_MODE: "password"` sur un hébergement indépendant. Le mode `sites` n’est sûr que derrière le dispatcher authentifié Sites ; ne jamais l’activer sur un Worker autonome.
6. `npx wrangler d1 migrations apply DB --remote --config wrangler.jsonc` : crée les tables. Les migrations déjà appliquées ne doivent jamais être modifiées.
7. `node scripts/admin-secret.mjs` : choisir et confirmer une phrase secrète unique d’au moins 20 caractères. Le script affiche uniquement son empreinte salée. La conserver temporairement de manière privée.
8. `npx wrangler secret put ADMIN_PASSWORD_HASH --config wrangler.jsonc` : coller cette empreinte complète dans l’invite, sans guillemets. Ne pas la mettre dans le dépôt. Ne pas déployer un mot de passe de démonstration.
9. `npx wrangler deploy --config wrangler.jsonc`. Si le Worker n’existe pas encore et que l’étape 8 le demande, créer/déployer le Worker puis recommencer l’étape 8. Tant que le secret manque, l’administration refuse toute connexion.
10. Dans le tableau de bord du Worker, ajouter le domaine final via **Settings → Domains & Routes → Add → Custom Domain** et finaliser le DNS/HTTPS. Ne pas ajouter ce domaine directement sur le bucket photos. Tester `/`, `/admin` et `/suivi` sur ce domaine avant de communiquer l’adresse aux clients.

## Utilisation

- Ouvrir `/admin` : connexion avec votre phrase secrète (sur Sites : votre compte ChatGPT autorisé).
- Créer un chantier. Le code client aléatoire est affiché une fois à l’administrateur, mais est **réutilisable par le client**. Copier le message et le remettre personnellement au bon client.
- Le client saisit ce code sur `/suivi`. Il voit exclusivement son chantier. L’actualisation se fait toutes les 15 secondes lorsque la page est visible ; ce n’est pas une diffusion vidéo.
- Modifier le pourcentage et le statut, publier des nouvelles et des photos. L’interface réduit les images à 2400 px maximum et les réencode en JPEG sans métadonnées EXIF. Les fichiers HEIC non lisibles doivent être exportés en JPEG.
- « Remplacer le code » invalide l’ancien code et les sessions existantes. Le nouveau code doit être transmis au client. « Accès client activé » permet de fermer/réouvrir l’accès. Mettre le statut « Terminé » ne ferme pas automatiquement l’accès.
- Un cookie de session client dure au maximum 14 jours ; le client peut ressaisir son code ensuite. La session administrateur autonome dure 8 heures. Une nouvelle empreinte de mot de passe invalide les sessions administrateur existantes.
- Ne partager aucun mot de passe administrateur avec les clients. Quiconque possède un code client peut consulter le chantier correspondant : le code est un accès confidentiel, pas une preuve d’identité.

## Sécurité et exploitation

Codes aléatoires de 100 bits, stockés sous forme d’empreintes SHA-256. Cookies Secure/HttpOnly/SameSite, contrôles d’accès serveur sur les photos et les écritures, vérification d’origine des actions, limitation des tentatives, requêtes préparées et absence de cache sur les réponses privées. Connexion autonome : PBKDF2-SHA256 salé, 100 000 itérations (compatibilité Web Crypto Workers) ; utiliser une longue phrase secrète aléatoire. Pour des exigences renforcées, faire ajouter une authentification administrateur multifacteur avant exploitation.

Limites initiales : 500 chantiers listés, 500 nouvelles et 500 photos affichées par chantier, 8 Mo par photo côté serveur, 100 envois de photos par jour au total. Adapter ces limites et prévoir une pagination si le volume augmente. Les photos sont réellement stockées en R2 ; aucun fichier client n’est stocké dans GitHub. La suppression d’une photo depuis l’administration est définitive dans l’application et ne remplace pas une politique de sauvegarde.

Avant de recevoir de vrais dossiers : vérifier les deux parcours sur le domaine final, la séparation de deux clients, le remplacement d’un code, les erreurs d’envoi, les quotas du compte et une restauration de sauvegarde. Activer des sauvegardes/exportations D1 et une sauvegarde séparée du bucket R2. Définir avec Endry SA une durée de conservation et un processus de suppression des dossiers, et adapter la notice de confidentialité à l’hébergement retenu. Aucune suppression automatique des dossiers n’est configurée.

Le domaine indépendant dispose de sa propre base et de son propre stockage. Les données du site Sites ne sont **pas** automatiquement transférées ni synchronisées. Si des chantiers y sont déjà créés, prévoir une migration privée de D1/R2, ou recréer les dossiers et réémettre les codes. Le code du dépôt reste indépendant ; ne pas copier de données clients dans un commit pour migrer.

Le site vitrine conserve actuellement les directives `noindex` et `robots.txt` de la version de validation. Après validation du domaine final, autoriser l’indexation **des pages vitrines seulement**. L’espace de suivi et l’administration doivent rester non indexables. Le formulaire de contact vitrine continue à préparer un e-mail, sans envoi serveur automatique.

## Références hébergeur

- [Configuration Wrangler et bindings](https://developers.cloudflare.com/workers/wrangler/configuration/)
- [Migrations D1](https://developers.cloudflare.com/d1/reference/migrations/)
- [Secrets Workers](https://developers.cloudflare.com/workers/configuration/secrets/)

Le déploiement indépendant exige votre compte hébergeur, le domaine choisi et le secret administrateur. Ces accès ne sont ni fournis ni inclus dans le code.
