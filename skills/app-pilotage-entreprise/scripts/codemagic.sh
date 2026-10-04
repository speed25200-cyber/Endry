#!/usr/bin/env bash
# Lancer et suivre un build Codemagic depuis le terminal (skill app-pilotage-entreprise).
#
# Le jeton API Codemagic n'est JAMAIS dans le dépôt : variable CM_TOKEN, ou fichier désigné par CM_TOKEN_FILE
# (hors dépôt, ex. un dossier temporaire). CM_APP_ID = identifiant (public) de l'app dans Codemagic.
#
#   scripts/codemagic.sh lancer ios-testflight [branche]   → affiche l'id du build
#   scripts/codemagic.sh suivre <id>                       → affiche chaque changement d'état jusqu'à la fin
#   scripts/codemagic.sh etapes <id>                       → état de chaque étape
#   scripts/codemagic.sh journal <id> <nom d'étape>        → journal d'une étape (lignes d'erreur en tête)
#   scripts/codemagic.sh annuler <id>
#   scripts/codemagic.sh derniers                          → 5 derniers builds
set -euo pipefail

API=https://api.codemagic.io
if [ -z "${CM_TOKEN:-}" ] && [ -n "${CM_TOKEN_FILE:-}" ]; then CM_TOKEN="$(cat "$CM_TOKEN_FILE")"; fi
: "${CM_TOKEN:?Définir CM_TOKEN (ou CM_TOKEN_FILE) — jamais dans le dépôt}"

appel() { curl -sS -m 60 -H "x-auth-token: $CM_TOKEN" -H 'Content-Type: application/json' "$@"; }

case "${1:-}" in
  lancer)
    : "${CM_APP_ID:?Définir CM_APP_ID}"
    WORKFLOW="${2:?workflow (ios-testflight, ios-tests)}"
    BRANCHE="${3:-$(git rev-parse --abbrev-ref HEAD)}"
    appel -X POST "$API/builds" -d "{\"appId\":\"$CM_APP_ID\",\"workflowId\":\"$WORKFLOW\",\"branch\":\"$BRANCHE\"}" \
      | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("buildId") or d)'
    ;;
  suivre)
    ID="${2:?id du build}"; PRECEDENT=""
    while true; do
      ETAT=$(appel "$API/builds/$ID" | python3 -c '
import json, sys
b = json.load(sys.stdin)["build"]
en_cours = [a["name"] for a in b.get("buildActions", []) if a.get("status") == "building"]
print(b["status"], ("· " + en_cours[0]) if en_cours else "")')
      if [ "$ETAT" != "$PRECEDENT" ]; then echo "$(date +%H:%M) $ETAT"; PRECEDENT="$ETAT"; fi
      case "$ETAT" in finished*|failed*|canceled*|timeout*|skipped*) exit 0 ;; esac
      sleep 40
    done
    ;;
  etapes)
    appel "$API/builds/${2:?id}" | python3 -c '
import json, sys
for a in json.load(sys.stdin)["build"].get("buildActions", []):
    print("%-10s %s  (%s)" % (a.get("status", "?"), a["name"], a["_id"]))'
    ;;
  journal)
    ID="${2:?id}"; NOM="${3:?nom d’étape}"
    ETAPE=$(appel "$API/builds/$ID" | python3 -c '
import json, sys
nom = sys.argv[1]
for a in json.load(sys.stdin)["build"].get("buildActions", []):
    if nom.lower() in a["name"].lower(): print(a["_id"]); break' "$NOM")
    : "${ETAPE:?étape introuvable}"
    JOURNAL=$(appel "$API/builds/$ID/step/$ETAPE")
    echo "$JOURNAL" | grep -nE 'error:|fatal|FAILED|\*\* BUILD' | head -40 || true
    echo "──── fin du journal ────"; echo "$JOURNAL" | tail -60
    ;;
  annuler)
    appel -X POST "$API/builds/${2:?id}/cancel"; echo
    ;;
  derniers)
    : "${CM_APP_ID:?Définir CM_APP_ID}"
    appel "$API/builds?appId=$CM_APP_ID" | python3 -c '
import json, sys
for b in json.load(sys.stdin).get("builds", [])[:5]:
    message = ((b.get("commit") or {}).get("commitMessage") or "").strip().split("\n")[0][:60]
    print(b["_id"], b["status"], b.get("fileWorkflowId"), b.get("branch"), message)'
    ;;
  *)
    sed -n 2,13p "$0"; exit 1 ;;
esac
