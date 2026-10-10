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
# « application » dans la demande : choisit l'app Codemagic par le nom de son dépôt (défaut : Endry).
voulue = (demande.get("application") or "").lower()
if voulue:
    app = next((a for a in apps if voulue in json.dumps(a.get("repository", {})).lower()), None)
    if not app:
        sys.exit(f"Aucune application Codemagic pour le dépôt « {demande['application']} » : elle doit d'abord être ajoutée dans Codemagic.")
else:
    app = next((a for a in apps if "endry" in json.dumps(a.get("repository", {})).lower()), apps[0] if apps else None)
if not app:
    sys.exit("Aucune application trouvée.")
print("== Application retenue :", app.get("appName"))

# Annule des builds en file (doublons qui bloquent la file) avant tout lancement.
for a_annuler in demande.get("annuler", []):
    print("== Annulation du build", a_annuler, ":", appel(f"/builds/{a_annuler}/cancel", "POST", {}))

if demande.get("file"):
    # Vue de la file de l'équipe : ce qui tourne ou attend, toutes applications confondues (un build qui reste
    # « queued » attend presque toujours qu'un autre se termine).
    print("== File Codemagic (toutes les applications)")
    for a in apps:
        for b in ((appel(f"/builds?appId={a['_id']}") or {}).get("builds", []))[:10]:
            if b.get("status") not in ("finished", "failed", "canceled", "timeout", "skipped", "warning"):
                print(f"- {a.get('appName')} {b.get('_id')} {b.get('status')} workflow={b.get('workflowId') or b.get('fileWorkflowId')} "
                      f"branche={b.get('branch')} créé={b.get('createdAt')} début={b.get('startedAt')}")
    print("== fin de la file")
    # Minutes de build du mois en cours, d'après les builds que l'API liste (minimum : la liste est limitée).
    from datetime import datetime, timezone
    mois, total = datetime.now(timezone.utc).strftime("%Y-%m"), 0.0
    for a in apps:
        minutes = nombre = 0
        for b in (appel(f"/builds?appId={a['_id']}") or {}).get("builds", []):
            debut, fin = b.get("startedAt"), b.get("finishedAt")
            if debut and fin and str(debut).startswith(mois):
                minutes += (datetime.fromisoformat(str(fin).replace("Z", "+00:00"))
                            - datetime.fromisoformat(str(debut).replace("Z", "+00:00"))).total_seconds() / 60
                nombre += 1
        total += minutes
        print(f"- {a.get('appName')} : {nombre} builds, {minutes:.0f} minutes en {mois}")
    print(f"== minutes de build en {mois} (builds listés) : {total:.0f}")

def champs_simples(b):
    """Champs simples d'un build, sans rien de sensible : le journal de ce relais est public."""
    interdits = ("token", "secret", "password", "key", "url", "email")
    return {k: (v[:140] if isinstance(v, str) else v) for k, v in b.items()
            if (v is None or isinstance(v, (str, int, float, bool))) and not any(m in k.lower() for m in interdits)}


def minutes_entre(debut, fin):
    from datetime import datetime
    if not debut or not fin:
        return None
    lire = lambda t: datetime.fromisoformat(str(t).replace("Z", "+00:00"))
    return round((lire(fin) - lire(debut)).total_seconds() / 60, 1)


if demande.get("recents"):
    # Derniers builds de chaque application : attente en file (création → début) et durée, pour voir depuis quand
    # la file ne part plus et sur quel type de machine.
    print("== Derniers builds par application (attente en file, durée)")
    for a in apps:
        for b in ((appel(f"/builds?appId={a['_id']}") or {}).get("builds", []))[: demande["recents"]]:
            print(f"- {a.get('appName')} {b.get('_id')} {b.get('status')} machine={b.get('instanceType')} "
                  f"workflow={b.get('workflowId') or b.get('fileWorkflowId')} créé={b.get('createdAt')} "
                  f"attente={minutes_entre(b.get('createdAt'), b.get('startedAt'))} min "
                  f"durée={minutes_entre(b.get('startedAt'), b.get('finishedAt'))} min message={str(b.get('message'))[:120]}")
    print("== fin des derniers builds")

for ident in demande.get("detail", []):
    b = (appel(f"/builds/{ident}") or {}).get("build") or {}
    print(f"== Détail du build {ident}")
    print("  clés :", sorted(b.keys()))
    print("  champs :", json.dumps(champs_simples(b), ensure_ascii=False))
    print("  étapes :", [(e.get("name"), e.get("status")) for e in b.get("buildActions") or []])
    if isinstance(b.get("config"), dict):
        print("  config, clés :", sorted(b["config"].keys()))
        print("  config, champs :", json.dumps(champs_simples(b["config"]), ensure_ascii=False))

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
if demande.get("action") in ("attendre", "attendre_et_captures") and commit:
    # Attend le build Codemagic de ce commit (jusqu’à ~55 min, file d’attente comprise).
    for _ in range(220):
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

cibles = [b for b in builds[: max(5, demande.get("n", 1))]
          if b.get("status") in ("failed", "timeout") or b.get("_id") == demande.get("build")][: demande.get("n", 1)]
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
        # Durée de chaque test d'interface : repère celui qui traîne.
        durees = [l for l in lignes if "Test Case" in l and ("passed" in l or "failed" in l)]
        print(f"  ---- {len(durees)} tests terminés ----")
        for l in durees[:80]:
            print("  ⏱ " + l[:300])
        lances = [l for l in lignes if "Test Case" in l and "started" in l]
        if lances:
            print("  dernier test lancé :", lances[-1][:300])
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
    """Télécharge les artefacts zippés du build, extrait les captures d'écran, les réduit
    et les range dans captures-out/ (publiées ensuite sur la branche « captures-ci »)."""
    import zipfile
    from PIL import Image
    detail = (appel(f"/builds/{build_id}") or {}).get("build") or {}
    artefacts = detail.get("artefacts") or []
    print(f"\n== Artefacts du build {build_id} :", [a.get("name") for a in artefacts])
    os.makedirs("captures-out", exist_ok=True)
    for a in artefacts:
        nom = a.get("name", "")
        if not nom.endswith(".zip") or "xcresult" in nom:
            continue
        req = urllib.request.Request(a["url"], headers={"x-auth-token": JETON})
        with urllib.request.urlopen(req, timeout=300) as r:
            archive = zipfile.ZipFile(io.BytesIO(r.read()))
        noms = {}
        for entree in archive.namelist():
            if entree.endswith("manifest.json"):
                try:
                    for test in json.loads(archive.read(entree)):
                        for piece in test.get("attachments", []):
                            noms[piece.get("exportedFileName")] = piece.get("suggestedHumanReadableName")
                except Exception as e:
                    print("manifeste illisible :", e)
        for entree in archive.namelist():
            base = entree.split("/")[-1]
            suggere = noms.get(base) or base
            bas = entree.lower()
            if bas.endswith(".txt"):
                # Diagnostic d'un test en échec : hiérarchie de l'écran et description.
                if any(m in suggere.lower() for m in ("hierarchy", "issue", "debug description")):
                    nom = "".join(c if c.isalnum() or c in "-_" else "_" for c in suggere)[:50]
                    with open(f"captures-out/{nom}.txt", "wb") as f:
                        f.write(archive.read(entree)[:80_000])
                continue
            if bas.endswith((".mp4", ".json", "/")) or "." in base and not bas.endswith((".png", ".jpg", ".jpeg")):
                continue
            lisible = suggere.rsplit(".", 1)[0] if suggere.lower().endswith((".png", ".jpg", ".jpeg")) else suggere
            lisible = "".join(c if c.isalnum() or c in "-_" else "_" for c in lisible)[:60]
            try:
                img = Image.open(io.BytesIO(archive.read(entree))).convert("RGB")
            except Exception:
                continue
            img.thumbnail((440, 960))
            img.save(f"captures-out/{lisible}.jpg", "JPEG", quality=80, optimize=True)
            print("capture :", lisible)
    with open("captures-out/BUILD.txt", "w") as f:
        f.write(f"{build_id}\n")

if demande.get("action") == "lancer_et_captures" and build_lance:
    captures(build_lance)
elif demande.get("action") == "attendre_et_captures":
    du_commit = [b for b in builds if (b.get("commit") or {}).get("hash", "").startswith(commit[:7])
                 and (b.get("workflowId") or b.get("fileWorkflowId")) == "ios-tests" and b.get("status") in ("finished", "failed")]
    if du_commit:
        captures(du_commit[0]["_id"])
elif demande.get("action") == "captures":
    cible = demande.get("build") or next((b["_id"] for b in builds if b.get("status") == "finished"
                                          and (b.get("workflowId") or b.get("fileWorkflowId")) == "ios-tests"), None)
    if cible:
        captures(cible)
