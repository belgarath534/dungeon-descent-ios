"""Copies what the web game saved in the "(default)" Firestore database into
"dungeon-descent" (where the apps and, from now on, the web game keep it).
Only copies documents that "dungeon-descent" doesn't have yet; nothing is
overwritten or deleted. With APPLY unset it only prints what it would copy
(counts, never contents)."""
import json, os
from google.oauth2 import service_account
from google.auth.transport.requests import AuthorizedSession

PROJECT = "dungeon-descent-fbaf2"
APPLY = os.environ.get("APPLY") == "yes"
COLLECTIONS = ["users", "usernames", "saves", "scores", "leaderboard", "deaths", "community_enemies"]
creds = service_account.Credentials.from_service_account_info(json.loads(os.environ["SA"]), scopes=["https://www.googleapis.com/auth/datastore"])
s = AuthorizedSession(creds)
base = lambda db: f"https://firestore.googleapis.com/v1/projects/{PROJECT}/databases/{db}/documents"

def docs(db, path):
    out, token = [], None
    while True:
        r = s.get(f"{base(db)}/{path}", params={"pageSize": 300, **({"pageToken": token} if token else {})})
        r.raise_for_status()
        j = r.json()
        out += j.get("documents", [])
        token = j.get("nextPageToken")
        if not token:
            return out

print("APPLYING" if APPLY else "DRY RUN (nothing is written)")
for c in COLLECTIONS:
    src = docs("(default)", c)
    have = {d["name"].rsplit("/", 1)[1] for d in docs("dungeon-descent", c)}
    missing = [d for d in src if d["name"].rsplit("/", 1)[1] not in have]
    clash = len(src) - len(missing)
    print(f"{c:20} in (default): {len(src):4}   already in dungeon-descent: {clash:4}   to copy: {len(missing):4}")
    if APPLY:
        for d in missing:
            did = d["name"].rsplit("/", 1)[1]
            r = s.patch(f"{base('dungeon-descent')}/{c}/{did}", params={"currentDocument.exists": "false"},
                        json={"fields": d.get("fields", {})})
            if not r.ok:
                print("   couldn't copy one:", r.status_code)
        # Sub-collections (a profile's inbox) come along too.
        if c == "users":
            for d in missing:
                did = d["name"].rsplit("/", 1)[1]
                for sub in docs("(default)", f"users/{did}/inbox"):
                    sid = sub["name"].rsplit("/", 1)[1]
                    s.patch(f"{base('dungeon-descent')}/users/{did}/inbox/{sid}", params={"currentDocument.exists": "false"},
                            json={"fields": sub.get("fields", {})})
print("Done." if APPLY else "Dry run done. Run with APPLY=yes (the db-merge branch) to copy.")
