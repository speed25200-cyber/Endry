# Endry SA

Site vitrine d'Endry SA — sanitaire, chauffage et ventilation, Bussy FR
(Fribourg · Vaud · Valais).

## Contenu

Site statique, sans dépendance ni étape de build :

- `index.html` — page principale (expertises, dépannage, réalisations, contact)
- `mentions-legales.html`, `confidentialite.html` — pages légales
- `styles.css`, `site.js` — styles et interactions
- `assets/` — logo, photographies et plaquette PDF
- `robots.txt` — le site est actuellement en `Disallow: /` (accessible par
  lien, mais non indexé par les moteurs de recherche)

## Publication

Le déploiement est automatisé par `.github/workflows/pages.yml` : chaque push
sur `main` publie le site sur GitHub Pages.

Adresse une fois le premier déploiement terminé :
<https://speed25200-cyber.github.io/Endry/>

Si le workflow ne parvient pas à activer Pages tout seul, l'activer une fois
dans **Settings → Pages → Source : GitHub Actions**, puis relancer le workflow.

## Aperçu en local

```sh
python3 -m http.server 8000
# puis ouvrir http://localhost:8000
```
