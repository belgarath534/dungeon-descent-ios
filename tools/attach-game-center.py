"""Puts the Game Center leaderboards and challenges (tools/game-center.py)
into the iPhone 11.9 review submission next to the app version, like the Game
Center section on the version page, so they go live with it. Doesn't submit:
store/submit_version.py does that, reusing this submission. Safe to run again.
"""
import os, sys, time
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

# The newest version of each leaderboard and challenge.
parts = []
for kind, path, item_rel, vtype in (
        ("leaderboard", "gameCenterLeaderboards", "gameCenterLeaderboardVersion", "gameCenterLeaderboardVersions"),
        ("challenge", "gameCenterChallenges", "gameCenterChallengeVersion", "gameCenterChallengeVersions")):
    things = (call("GET", f"/gameCenterDetails/{detail}/{path}", params={"limit": 200}) or {"data": []})["data"]
    for t in things:
        name = t["attributes"].get("vendorIdentifier") or t["id"]
        if not name.startswith("DD_"):
            continue
        vs = (call("GET", f"/{path}/{t['id']}/versions") or {"data": []})["data"]
        if not vs:
            print(f"⚠️ {name} has no version to add")
            problems.append(name)
            continue
        parts.append((name, item_rel, vtype, vs[-1]["id"], vs[-1]["attributes"].get("state")))
print("To add:", [(p[0], p[4]) for p in parts])

# The open submission for this platform, or a new one (not submitted).
subs = call("GET", "/reviewSubmissions", params={"filter[app]": app, "filter[platform]": PLATFORM,
            "filter[state]": "READY_FOR_REVIEW"})["data"]
sub = subs[0] if subs else call("POST", "/reviewSubmissions", {"data": {"type": "reviewSubmissions",
      "attributes": {"platform": PLATFORM}, "relationships": {"app": rel("apps", app)}}})["data"]
items = call("GET", f"/reviewSubmissions/{sub['id']}/items",
             params={"include": "appStoreVersion,gameCenterLeaderboardVersion,gameCenterChallengeVersion"}) or {"data": []}
have = set()
for it in items["data"]:
    for r in it.get("relationships", {}).values():
        d = (r or {}).get("data")
        if d:
            have.add(d["id"])

if version["id"] not in have:
    if call("POST", "/reviewSubmissionItems", {"data": {"type": "reviewSubmissionItems", "relationships": {
            "reviewSubmission": rel("reviewSubmissions", sub["id"]),
            "appStoreVersion": rel("appStoreVersions", version["id"])}}}):
        print(f"✅ {PLATFORM} {VERSION} added to the submission")
for name, item_rel, vtype, vid, state in parts:
    if vid in have:
        print(f"• {name} is already in it")
        continue
    if call("POST", "/reviewSubmissionItems", {"data": {"type": "reviewSubmissionItems", "relationships": {
            "reviewSubmission": rel("reviewSubmissions", sub["id"]), item_rel: rel(vtype, vid)}}}):
        print(f"✅ {name} added")

if problems:
    print(f"\n{len(problems)} step(s) didn't go through; see the ⚠️ lines above.")
    sys.exit(1)
print("\nGame Center is attached to the version (not submitted yet).")
