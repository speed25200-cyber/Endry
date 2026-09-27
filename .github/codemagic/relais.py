"""Relais Codemagic : lit l'état des builds (et démarre un build sur demande) avec le jeton API
stocké dans les secrets GitHub. N'affiche jamais le jeton."""
import base64, io, json, os, sys, time, urllib.request, urllib.error

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

build_lance = None
if demande.get("action") in ("lancer", "lancer_et_captures"):
    r = appel("/builds", "POST", {"appId": app["_id"], "workflowId": demande["workflow"], "branch": demande["branche"]})
    print("== Build démarré :", r)
    build_lance = (r or {}).get("buildId")
    if build_lance:
        for _ in range(110):
            etat = ((appel(f"/builds/{build_lance}") or {}).get("build") or {}).get("status")
            print("… build", build_lance, etat)
            if etat in ("finished", "failed", "canceled", "timeout", "skipped", "warning"):
                break
            time.sleep(15)

import time
commit = demande.get("commit") or os.environ.get("GITHUB_SHA", "")
builds = (appel(f"/builds?appId={app['_id']}") or {}).get("builds", [])
if demande.get("action") == "attendre" and commit:
    # Attend le build Codemagic de ce commit (jusqu'à ~25 min).
    for _ in range(100):
        miens = [b for b in builds if (b.get("commit") or {}).get("hash", "").startswith(commit[:7])]
        if miens and all(b.get("status") in ("finished", "failed", "canceled", "timeout", "skipped", "warning") for b in miens):
            break
        print("… en attente du build Codemagic de", commit[:7], [b.get("status") for b in miens])
        time.sleep(15)
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


def captures(build_id):
    """Télécharge les captures d'écran du build, les réduit et les imprime en base64 (lisibles dans ce journal)."""
    detail = (appel(f"/builds/{build_id}") or {}).get("build") or {}
    artefacts = detail.get("artefacts") or []
    print(f"\n== Artefacts du build {build_id} :", [a.get("name") for a in artefacts])
    try:
        from PIL import Image
    except ImportError:
        import subprocess
        subprocess.run([sys.executable, "-m", "pip", "install", "-q", "pillow"], check=False)
        from PIL import Image
    noms = {}
    for a in artefacts:
        if a.get("name", "").endswith("manifest.json"):
            try:
                manifeste = json.loads(appel(a["url"], brut=True) or "[]")
                for test in manifeste:
                    for piece in test.get("attachments", []):
                        noms[piece.get("exportedFileName")] = piece.get("suggestedHumanReadableName")
            except Exception as e:
                print("manifeste illisible :", e)
    for a in artefacts:
        nom = a.get("name", "")
        if not nom.lower().endswith((".png", ".jpg", ".jpeg")):
            continue
        req = urllib.request.Request(a["url"], headers={"x-auth-token": JETON})
        try:
            with urllib.request.urlopen(req, timeout=120) as r:
                donnees = r.read()
        except Exception as e:
            print("téléchargement impossible", nom, e)
            continue
        img = Image.open(io.BytesIO(donnees)).convert("RGB")
        img.thumbnail((420, 900))
        tampon = io.BytesIO()
        img.save(tampon, "JPEG", quality=72, optimize=True)
        base = nom.split("/")[-1]
        print(f"##CAPTURE## {noms.get(base, base)} {base64.b64encode(tampon.getvalue()).decode()}")

if demande.get("action") == "lancer_et_captures" and build_lance:
    captures(build_lance)
elif demande.get("action") == "captures":
    cible = demande.get("build") or next((b["_id"] for b in builds if b.get("status") == "finished"
                                          and (b.get("workflowId") or b.get("fileWorkflowId")) == "ios-tests"), None)
    if cible:
        captures(cible)
