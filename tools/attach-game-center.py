"""Makes the Game Center leaderboards and challenges (tools/game-center.py)
ready to go live: each leaderboard gets a release, and each challenge a
version with its English and Portuguese name and description, then a
release. Nothing goes to App Review here. Safe to run again.
"""
import hashlib, os, sys, time
import jwt, requests

API = "https://api.appstoreconnect.apple.com/v1"
BUNDLE = "com.dungeon.descent"
VERSION = os.environ.get("VERSION", "11.9")
PLATFORM = os.environ.get("PLATFORM", "IOS")


def token():
    now = int(time.time())
    return jwt.encode({"iss": os.environ["ASC_ISSUER_ID"].strip(), "iat": now, "exp": now + 1000,
                       "aud": "appstoreconnect-v1"}, open(os.environ["ASC_KEY_PATH"]).read(), algorithm="ES256",
                      headers={"kid": os.environ["GOOD_KEY_ID"].strip(), "typ": "JWT"})


S = requests.Session()
S.headers["Authorization"] = "Bearer " + token()
problems = []


def call(method, path, body=None, params=None):
    r = S.request(method, path if path.startswith("http") else API + path, json=body, params=params, timeout=60)
    if r.status_code == 409 and ("RELEASE_DUPLICATE" in r.text or "IMAGE_ALREADY_EXISTS" in r.text):
        print("• already there")
        return {}
    if r.status_code >= 400:
        msg = f"{method} {path} -> {r.status_code}: {r.text[:900]}"
        print("⚠️ " + msg)
        problems.append(msg)
        return None
    return r.json() if r.content else {}


def rel(kind, id_):
    return {"data": {"type": kind, "id": id_}}


app = call("GET", "/apps", params={"filter[bundleId]": BUNDLE})["data"][0]["id"]
version = call("GET", f"/apps/{app}/appStoreVersions",
               params={"filter[platform]": PLATFORM, "filter[versionString]": VERSION})["data"][0]
detail = call("GET", f"/apps/{app}/gameCenterDetail")["data"]["id"]



CHALLENGE_TEXT = {
    "DD_CHALLENGE_ENDLESS_BEST_FLOOR": ("Endless Descent Race", "Get deeper in Endless Descent than your friends.",
                                        "Corrida da Descida Sem Fim", "Desça mais fundo na Descida Sem Fim do que seus amigos."),
    "DD_CHALLENGE_WEEKLY_LADDER": ("Weekly Ladder Showdown", "Beat your friends' score in this week's one-life dungeon.",
                                   "Duelo da Escada Semanal", "Supere a pontuação dos seus amigos na masmorra de uma vida desta semana."),
    "DD_CHALLENGE_SPIRE_BEST_FLOOR": ("Spire Climb", "Climb higher in The Spire than your friends.",
                                      "Escalada da Torre", "Suba mais alto na Torre do que seus amigos."),
}

lbs = call("GET", f"/gameCenterDetails/{detail}/gameCenterLeaderboards", params={"limit": 200})["data"]
for lb in lbs:
    name = lb["attributes"]["vendorIdentifier"]
    if not name.startswith("DD_"):
        continue
    if (call("GET", f"/gameCenterLeaderboards/{lb['id']}/releases") or {"data": []})["data"]:
        print(f"• {name} already has a release")
        continue
    if call("POST", "/gameCenterLeaderboardReleases", {"data": {"type": "gameCenterLeaderboardReleases",
            "relationships": {"gameCenterDetail": rel("gameCenterDetails", detail),
                              "gameCenterLeaderboard": rel("gameCenterLeaderboards", lb["id"])}}}):
        print(f"✅ {name} released")

fresh = []
chs = (call("GET", f"/gameCenterDetails/{detail}/gameCenterChallenges", params={"limit": 200}) or {"data": []})["data"]
for ch in chs:
    name = ch["attributes"].get("vendorIdentifier")
    if name not in CHALLENGE_TEXT:
        continue
    vs = (call("GET", f"/gameCenterChallenges/{ch['id']}/versions") or {"data": []})["data"]
    if vs:
        v = vs[-1]
        print(f"• {name} has a version ({v['attributes']})")
    else:
        made = call("POST", "/gameCenterChallengeVersions", {"data": {"type": "gameCenterChallengeVersions",
                    "relationships": {"challenge": rel("gameCenterChallenges", ch["id"])}}})
        if not made:
            continue
        v = made["data"]
        print(f"✅ {name}: version made")
    have = {l["attributes"]["locale"] for l in
            (call("GET", f"/gameCenterChallengeVersions/{v['id']}/localizations") or {"data": []})["data"]}
    en_name, en_desc, pt_name, pt_desc = CHALLENGE_TEXT[name]
    for locale, n, d in (("en-US", en_name, en_desc), ("pt-BR", pt_name, pt_desc)):
        if locale in have:
            continue
        if call("POST", "/gameCenterChallengeLocalizations", {"data": {"type": "gameCenterChallengeLocalizations",
                "attributes": {"locale": locale, "name": n, "description": d},
                "relationships": {"version": rel("gameCenterChallengeVersions", v["id"])}}}):
            print(f"   {locale} name set")
    # Each challenge needs its picture (tools/make-challenge-art.py). A
    # picture whose upload never finished is removed and sent again.
    art = os.path.join(os.path.dirname(__file__), f"../store/game-center/{name}.png")
    vv = S.get(API + f"/gameCenterChallengeVersions/{v['id']}", params={"include": "image"}, timeout=60)
    img_id = None
    if vv.ok:
        d = (vv.json()["data"].get("relationships", {}).get("image") or {}).get("data")
        img_id = d and d["id"]
    else:
        print(f"   (couldn't read the version: {vv.status_code} {vv.text[:200]})")
    if img_id:
        im = call("GET", f"/gameCenterChallengeImages/{img_id}")
        state = ((im or {}).get("data", {}).get("attributes", {}).get("assetDeliveryState") or {}).get("state")
        print(f"   picture {img_id}: {state}")
        if state in ("COMPLETE", None) and im:
            pass
        else:
            S.delete(API + f"/gameCenterChallengeImages/{img_id}", timeout=60)
            print("   removed the unfinished picture")
            img_id = None
    if not img_id and os.path.exists(art):
        data = open(art, "rb").read()
        made = call("POST", "/gameCenterChallengeImages", {"data": {"type": "gameCenterChallengeImages",
                    "attributes": {"fileName": os.path.basename(art), "fileSize": len(data)},
                    "relationships": {"version": rel("gameCenterChallengeVersions", v["id"])}}})
        if made:
            im = made["data"]
            for op in im["attributes"].get("uploadOperations") or []:
                part = data[op["offset"]:op["offset"] + op["length"]]
                headers = {h["name"]: h["value"] for h in op.get("requestHeaders") or []}
                r = requests.request(op["method"], op["url"], data=part, headers=headers, timeout=120)
                print(f"   uploaded part: {r.status_code}")
                if r.status_code >= 400:
                    problems.append(f"upload {name}: {r.status_code}")
            if call("PATCH", f"/gameCenterChallengeImages/{im['id']}", {"data": {"type": "gameCenterChallengeImages",
                    "id": im["id"], "attributes": {"uploaded": True,
                                                   "sourceFileChecksum": hashlib.md5(data).hexdigest()}}}):
                print("   picture uploaded")
                fresh.append(im["id"])
    releases = S.get(API + f"/gameCenterChallengeVersions/{v['id']}/releases", timeout=60)
    if releases.ok and releases.json().get("data"):
        print(f"• {name} already released")
        continue
    if call("POST", "/gameCenterChallengeVersionReleases", {"data": {"type": "gameCenterChallengeVersionReleases",
            "relationships": {"gameCenterDetail": rel("gameCenterDetails", detail),
                              "version": rel("gameCenterChallengeVersions", v["id"])}}}):
        print(f"✅ {name} released")

# Apple processes new pictures for a minute or two; the version can't be
# submitted until it has.
for _ in range(20):
    waiting = []
    for iid in fresh:
        im = S.get(API + f"/gameCenterChallengeImages/{iid}", timeout=60)
        st = ((im.json().get("data", {}).get("attributes", {}).get("assetDeliveryState") or {}).get("state")) if im.ok else "?"
        if st != "COMPLETE":
            waiting.append(st)
    if not waiting:
        break
    print(f"Waiting for Apple to process {len(waiting)} picture(s): {waiting}")
    time.sleep(20)

if problems:
    print(f"\n{len(problems)} step(s) didn't go through; see the ⚠️ lines above.")
    sys.exit(1)
print("\nGame Center leaderboards and challenges are released.")
