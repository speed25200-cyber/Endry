"""Relais Codemagic : lit l'état des builds (et démarre un build sur demande) avec le jeton API
stocké dans les secrets GitHub. N'affiche jamais le jeton."""
import json, os, sys, urllib.request, urllib.error

API = "https://api.codemagic.io"
JETON = os.environ.get("CM_JETON", "").strip()
if not JETON:
    sys.exit("Aucun jeton Codemagic : secret GitHub introuvable (noms essayés : CODEMAGIC_API_TOKEN, "
             "CODEMAGIC_TOKEN, CM_API_TOKEN, CODEMAGIC_API_KEY, CODEMAGIC).")

def appel(chemin, methode="GET", corps=None, brut=False):
    url = chemin if chemin.startswith("http") else API + chemin
    donnees = json.dumps(corps).encode() if corps is not None else None
    req = urllib.request.Request(url, data=donnees, method=methode,
                                 headers={"x-auth-token": JETON, "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            contenu = r.read()
            return contenu.decode("utf-8", "replace") if brut else json.loads(contenu or b"{}")
    except urllib.error.HTTPError as e:
        print(f"HTTP {e.code} sur {chemin} : {e.read()[:300]!r}")
        return None

demande = json.load(open(".github/codemagic/demande.json"))
apps = (appel("/apps") or {}).get("applications", [])
print("== Applications Codemagic")
for a in apps:
    print(f"- {a.get('appName')} id={a.get('_id')} dépôt={a.get('repository', {}).get('htmlUrl')} workflows={list((a.get('workflows') or {}).keys())}")
app = next((a for a in apps if "endry" in json.dumps(a.get("repository", {})).lower()), apps[0] if apps else None)
if not app:
    sys.exit("Aucune application trouvée.")

if demande.get("action") == "lancer":
    r = appel("/builds", "POST", {"appId": app["_id"], "workflowId": demande["workflow"], "branch": demande["branche"]})
    print("== Build démarré :", r)

builds = (appel(f"/builds?appId={app['_id']}") or {}).get("builds", [])
print(f"\n== {len(builds)} builds (les plus récents d'abord)")
for b in builds[: max(5, demande.get("n", 1))]:
    print(f"- {b.get('_id')} {b.get('status')} workflow={b.get('workflowId') or b.get('fileWorkflowId')} "
          f"branche={b.get('branch')} tag={b.get('tag')} commit={(b.get('commit') or {}).get('hash', '')[:7]} "
          f"début={b.get('startedAt')} fin={b.get('finishedAt')} message={b.get('message')}")

cibles = [b for b in builds[: max(5, demande.get("n", 1))] if b.get("status") == "failed"][: demande.get("n", 1)]
for b in cibles:
    print(f"\n==== Détail du build {b.get('_id')} ({b.get('status')})")
    detail = appel(f"/builds/{b['_id']}") or {}
    b = detail.get("build", b)
    for etape in b.get("buildActions", []) or []:
        print(f"  [{etape.get('status')}] {etape.get('name')}")
        if etape.get("status") not in ("failed", "canceled", "timeout"):
            continue
        print("  clés :", sorted(etape.keys()))
        candidats = [etape.get("logUrl"), etape.get("logsUrl"),
                     f"{API}/builds/{b['_id']}/step/{etape.get('_id')}",
                     f"{API}/builds/{b['_id']}/actions/{etape.get('_id')}/log"]
        journal = ""
        for url in [c for c in candidats if c]:
            journal = appel(url, brut=True) or ""
            if journal:
                print("  journal lu depuis", url.replace(API, "API"))
                break
        lignes = journal.splitlines()
        erreurs = [l for l in lignes if "error:" in l or "** BUILD FAILED" in l or "** TEST FAILED" in l or "failed" in l.lower() and "Test Case" in l]
        print(f"  ---- {len(erreurs)} lignes d'erreur ----")
        for l in erreurs[:120]:
            print("  ! " + l[:400])
        print("  ---- fin du journal ----")
        for l in lignes[-120:]:
            print("  | " + l[:400])
    if b.get("message"):
        print("  message :", b.get("message"))
