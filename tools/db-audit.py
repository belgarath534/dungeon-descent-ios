"""Read-only: counts the documents in each top-level collection of both
Firestore databases ("(default)" and "dungeon-descent"), to see which one
the web game and the iPhone game actually use. Reads no document contents."""
import json, os, sys
from google.oauth2 import service_account
from google.auth.transport.requests import AuthorizedSession

PROJECT = "dungeon-descent-fbaf2"
COLLECTIONS = ["users", "usernames", "saves", "scores", "leaderboard", "tournament", "deaths", "community_enemies",
               "community_dungeons", "guilds", "guildNames", "chat_members", "chat_channels"]
creds = service_account.Credentials.from_service_account_info(json.loads(os.environ["SA"]), scopes=["https://www.googleapis.com/auth/datastore"])
s = AuthorizedSession(creds)
print(f"{'collection':22}{'(default)':>12}{'dungeon-descent':>18}")
for c in COLLECTIONS:
    row = []
    for db in ["(default)", "dungeon-descent"]:
        url = f"https://firestore.googleapis.com/v1/projects/{PROJECT}/databases/{db}/documents:runAggregationQuery"
        body = {"structuredAggregationQuery": {"structuredQuery": {"from": [{"collectionId": c}]},
                                                "aggregations": [{"alias": "n", "count": {}}]}}
        r = s.post(url, json=body)
        if not r.ok:
            row.append(f"err {r.status_code}")
            continue
        res = [x for x in r.json() if "result" in x]
        row.append(str(res[0]["result"]["aggregateFields"]["n"]["integerValue"]) if res else "0")
    print(f"{c:22}{row[0]:>12}{row[1]:>18}")
