#!/usr/bin/env bash
# Crée le squelette d'une app de pilotage pour une nouvelle entreprise (skill app-pilotage-entreprise).
#
#   scripts/nouveau-projet.sh --dossier ../AtelierPilotage --prefixe Atelier --bundle ch.atelier-sa.pilotage \
#       --nom "Atelier Pilotage" --entreprise "Atelier SA" [--apple-id 0000000000] [--integration Dev]
#
# Ensuite : remplir ios/FICHE_ENTREPRISE.md, compléter ios/CONTRAT_API.md, puis `cd ios/<Prefixe>Kit && swift test`.
set -euo pipefail

SKILL="$(cd "$(dirname "$0")/.." && pwd)"
DOSSIER="" PREFIXE="" BUNDLE="" NOM="" ENTREPRISE="" APPLE_ID="0000000000" INTEGRATION="Dev"
while [ $# -gt 0 ]; do
  case "$1" in
    --dossier) DOSSIER="$2"; shift 2 ;;
    --prefixe) PREFIXE="$2"; shift 2 ;;
    --bundle) BUNDLE="$2"; shift 2 ;;
    --nom) NOM="$2"; shift 2 ;;
    --entreprise) ENTREPRISE="$2"; shift 2 ;;
    --apple-id) APPLE_ID="$2"; shift 2 ;;
    --integration) INTEGRATION="$2"; shift 2 ;;
    *) sed -n 2,7p "$0"; exit 1 ;;
  esac
done
: "${DOSSIER:?--dossier}" "${PREFIXE:?--prefixe}" "${BUNDLE:?--bundle}" "${NOM:?--nom}" "${ENTREPRISE:?--entreprise}"
case "$PREFIXE" in *[!A-Za-z0-9]*|[0-9]*) echo "Préfixe : lettres et chiffres, sans espace (ex. Atelier)."; exit 1 ;; esac
[ -e "$DOSSIER/ios" ] && { echo "$DOSSIER/ios existe déjà : rien n'est écrasé."; exit 1; }

BUNDLE_PREFIXE="${BUNDLE%.*}"
SCHEMA_URL="$(echo "$PREFIXE" | tr '[:upper:]' '[:lower:]')pilotage"

remplacer() {
  python3 - "$1" "$2" "$PREFIXE" "$BUNDLE" "$BUNDLE_PREFIXE" "$NOM" "$ENTREPRISE" "$APPLE_ID" "$INTEGRATION" "$SCHEMA_URL" <<'EOF'
import sys
src, dst, prefixe, bundle, bundle_prefixe, nom, entreprise, apple_id, integration, schema = sys.argv[1:]
s = open(src, encoding="utf-8").read()
for cle, valeur in {
    "{{PREFIXE}}": prefixe, "{{BUNDLE_ID}}": bundle, "{{BUNDLE_PREFIXE}}": bundle_prefixe, "{{NOM_APP}}": nom,
    "{{ENTREPRISE}}": entreprise, "{{APPLE_ID_APP}}": apple_id, "{{INTEGRATION_ASC}}": integration,
    "{{SCHEMA_URL}}": schema,
}.items():
    s = s.replace(cle, valeur)
open(dst, "w", encoding="utf-8").write(s)
EOF
}

T="$SKILL/templates"
APP="$DOSSIER/ios/${PREFIXE}Pilotage"
KIT="$DOSSIER/ios/${PREFIXE}Kit"
mkdir -p "$APP"/{App,Design,Fonctions,Services,Voix,Ressources} "$KIT/Sources/${PREFIXE}Kit"/{API,Modeles,Demo,Stores,Voix,Resources/Fixtures} \
         "$KIT/Tests/${PREFIXE}KitTests" "$DOSSIER/ios/Tests/${PREFIXE}PilotageTests" "$DOSSIER/ios/Tests/${PREFIXE}PilotageUITests"

remplacer "$T/codemagic.yaml" "$DOSSIER/codemagic.yaml"
remplacer "$T/project.yml" "$DOSSIER/ios/project.yml"
remplacer "$T/CONTRAT_API.md" "$DOSSIER/ios/CONTRAT_API.md"
remplacer "$T/fiche-entreprise.md" "$DOSSIER/ios/FICHE_ENTREPRISE.md"
remplacer "$T/Package.swift" "$KIT/Package.swift"
remplacer "$T/swift/Kit/DecodageTolerant.swift" "$KIT/Sources/${PREFIXE}Kit/Modeles/DecodageTolerant.swift"
remplacer "$T/swift/Kit/Modeles.swift" "$KIT/Sources/${PREFIXE}Kit/Modeles/Modeles.swift"
remplacer "$T/swift/Kit/ClientAPI.swift" "$KIT/Sources/${PREFIXE}Kit/API/ClientAPI.swift"
remplacer "$T/swift/Tests/ContratTests.swift" "$KIT/Tests/${PREFIXE}KitTests/ContratTests.swift"
echo '[]' > "$KIT/Sources/${PREFIXE}Kit/Resources/Fixtures/decisions.json"
remplacer "$T/swift/App/App.swift" "$APP/App/${PREFIXE}PilotageApp.swift"
remplacer "$T/swift/App/FileAudio.swift" "$APP/Voix/FileAudio.swift"
for f in Palette Instruments GlisserPourValider; do
  remplacer "$T/swift/App/$f.swift" "$APP/Design/$f.swift"
done
# ApercuDocuments.swift suppose un ModeleApp (app.documents) et une méthode telechargerDocument : à brancher.
remplacer "$T/swift/App/ApercuDocuments.swift" "$APP/Services/Documents.swift.modele"

if [ ! -e "$DOSSIER/.gitignore" ]; then
  cat > "$DOSSIER/.gitignore" <<'EOF'
# Généré
*.xcodeproj/
build/
DerivedData/
.build/
.swiftpm/
# Secrets : jamais dans le dépôt
*.p8
*.p12
*.mobileprovision
.env*
.cm_token
EOF
fi

echo "Squelette créé dans $DOSSIER."
echo "Suite : remplir ios/FICHE_ENTREPRISE.md, compléter ios/CONTRAT_API.md, puis :"
echo "  cd $KIT && swift test"
