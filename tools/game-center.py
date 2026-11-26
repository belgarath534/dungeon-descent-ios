"""Makes Dungeon Descent's Game Center leaderboards in App Store Connect, each
with a challenge friends can send each other (iOS 26 and later), if they
aren't there yet. Run by the "Game Center setup" GitHub workflow with the
Apple API key the TestFlight workflow finds (GOOD_KEY_ID, ASC_KEY_PATH,
ASC_ISSUER_ID). Safe to run again: it only adds what's missing.

The IDs match GameCenter.Board in the app (GameCenter.swift). New
leaderboards and challenges work on TestFlight right away; they go live on
the App Store with the next version sent to review.
"""
import os, sys, time
import jwt, requests

API = "https://api.appstoreconnect.apple.com/v1"
BUNDLE = "com.dungeon.descent"

BOARDS = [
    {"id": "DD_ENDLESS_BEST_FLOOR", "ref": "Endless Descent deepest floor",
     "en": ("Endless Descent: Deepest Floor", " floor", " floors"),
     "pt": ("Descida Sem Fim: Mais Fundo", " andar", " andares"),
     "challenge": ("Endless Descent Race", "Get deeper in Endless Descent than your friends.",
                   "Corrida da Descida Sem Fim", "Desça mais fundo na Descida Sem Fim do que seus amigos.")},
    {"id": "DD_WEEKLY_LADDER", "ref": "Weekly Ladder score",
     "en": ("Weekly Ladder", " point", " points"),
     "pt": ("Escada Semanal", " ponto", " pontos"),
     "challenge": ("Weekly Ladder Showdown", "Beat your friends' score in this week's one-life dungeon.",
                   "Duelo da Escada Semanal", "Supere a pontuação dos seus amigos na masmorra de uma vida desta semana.")},
    {"id": "DD_SPIRE_BEST_FLOOR", "ref": "The Spire highest floor",
     "en": ("The Spire: Highest Floor", " floor", " floors"),
     "pt": ("A Torre: Andar Mais Alto", " andar", " andares"),
     "challenge": ("Spire Climb", "Climb higher in The Spire than your friends.",
                   "Escalada da Torre", "Suba mais alto na Torre do que seus amigos.")},
]


def token():
    now = int(time.time())
    key = open(os.environ["ASC_KEY_PATH"]).read()
    return jwt.encode({"iss": os.environ["ASC_ISSUER_ID"].strip(), "iat": now, "exp": now + 1000,
                       "aud": "appstoreconnect-v1"}, key, algorithm="ES256",
                      headers={"kid": os.environ["GOOD_KEY_ID"].strip(), "typ": "JWT"})


S = requests.Session()
S.headers["Authorization"] = "Bearer " + token()
problems = []


def call(method, path, body=None, soft=False):
    r = S.request(method, path if path.startswith("http") else API + path, json=body, timeout=60)
    if r.status_code >= 400:
        msg = f"{method} {path} -> {r.status_code}: {r.text[:900]}"
        if soft:
            print("⚠️ " + msg)
            problems.append(msg)
            return None
        sys.exit(msg)
    return r.json() if r.content else {}


def rel(kind, id_):
    return {"data": {"type": kind, "id": id_}}


def all_pages(path):
    out, url = [], path
    while url:
        page = call("GET", url, soft=True)
        if not page:
            break
        out += page.get("data", [])
        url = page.get("links", {}).get("next")
    return out


# Exact match: the filter also matches com.dungeon.descent.chat (Dungeon Descent Chat).
app = next(a["id"] for a in call("GET", f"/apps?filter[bundleId]={BUNDLE}")["data"] if a["attributes"]["bundleId"] == BUNDLE)
detail = call("GET", f"/apps/{app}/gameCenterDetail", soft=True)
if not detail or not detail.get("data"):
    detail = call("POST", "/gameCenterDetails", {"data": {"type": "gameCenterDetails",
                  "relationships": {"app": rel("apps", app)}}})
detail_id = detail["data"]["id"]
print(f"Game Center for app {app}: {detail_id}")

boards = {b["attributes"]["vendorIdentifier"]: b["id"]
          for b in all_pages(f"/gameCenterDetails/{detail_id}/gameCenterLeaderboards?limit=200")}
challenges = {c["attributes"].get("vendorIdentifier"): c["id"]
              for c in all_pages(f"/gameCenterDetails/{detail_id}/gameCenterChallenges?limit=200")}
print("Already there:", sorted(boards), sorted(challenges))

for b in BOARDS:
    lb = boards.get(b["id"])
    if not lb:
        made = call("POST", "/gameCenterLeaderboards", {"data": {
            "type": "gameCenterLeaderboards",
            "attributes": {"referenceName": b["ref"], "vendorIdentifier": b["id"], "defaultFormatter": "INTEGER",
                           "submissionType": "BEST_SCORE", "scoreSortType": "DESC"},
            "relationships": {"gameCenterDetail": rel("gameCenterDetails", detail_id)}}}, soft=True)
        if not made:
            continue
        lb = made["data"]["id"]
        print(f"✅ Leaderboard {b['id']}")
    else:
        print(f"• Leaderboard {b['id']} is already there")
    # Its name in each language (Apple allows 30 characters), if missing.
    have = {l["attributes"]["locale"] for l in all_pages(f"/gameCenterLeaderboards/{lb}/localizations")}
    for locale, (name, one, many) in (("en-US", b["en"]), ("pt-BR", b["pt"])):
        if locale not in have:
            call("POST", "/gameCenterLeaderboardLocalizations", {"data": {
                "type": "gameCenterLeaderboardLocalizations",
                "attributes": {"locale": locale, "name": name, "formatterSuffixSingular": one, "formatterSuffix": many},
                "relationships": {"gameCenterLeaderboard": rel("gameCenterLeaderboards", lb)}}}, soft=True)

    cid = "DD_CHALLENGE_" + b["id"][3:]
    if cid in challenges:
        print(f"• Challenge {cid} is already there")
        continue
    made = call("POST", "/gameCenterChallenges", {"data": {
        "type": "gameCenterChallenges",
        "attributes": {"referenceName": b["challenge"][0], "vendorIdentifier": cid,
                       "challengeType": "LEADERBOARD", "repeatable": True},
        "relationships": {"gameCenterDetail": rel("gameCenterDetails", detail_id),
                          "leaderboard": rel("gameCenterLeaderboards", lb)}}}, soft=True)
    if not made:
        continue
    ch = made["data"]["id"]
    # The name and description players see live on the challenge's version.
    versions = all_pages(f"/gameCenterChallenges/{ch}/versions")
    if versions:
        v = versions[0]["id"]
        en_name, en_desc, pt_name, pt_desc = b["challenge"]
        for locale, name, desc in (("en-US", en_name, en_desc), ("pt-BR", pt_name, pt_desc)):
            call("POST", "/gameCenterChallengeLocalizations", {"data": {
                "type": "gameCenterChallengeLocalizations",
                "attributes": {"locale": locale, "name": name, "description": desc},
                "relationships": {"version": rel("gameCenterChallengeVersions", v)}}}, soft=True)
    print(f"✅ Challenge {cid}")

if problems:
    print(f"\n{len(problems)} step(s) didn't go through; see the ⚠️ lines above.")
    sys.exit(1)
print("\nGame Center is set up.")
