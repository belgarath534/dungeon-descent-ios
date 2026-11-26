"""Creates Dungeon Descent Chat's channels (the Discord server's list) in the
game's Firestore database "dungeon-descent", with the Firebase service
account (FIREBASE_SERVICE_ACCOUNT). Only channels that don't exist yet are
made, so names or topics changed later are never overwritten."""
import json, os, sys
from google.oauth2 import service_account
from google.auth.transport.requests import AuthorizedSession

PROJECT = "dungeon-descent-fbaf2"
DATABASE = "dungeon-descent"
CHANNELS = [
    # id, name, topic, only moderators post, only testers see it
    ("announcements", "announcements", "News and updates from the developer", True, False),
    ("general", "general", "Talk about anything Dungeon Descent", False, False),
    ("help", "help", "Questions about the game? Ask here", False, False),
    ("strategy", "strategy", "Classes, builds and tips", False, False),
    ("bug-reports", "bug-reports", "Something broken? Tell us what happened and on which device", False, False),
    ("ideas", "ideas", "Suggestions for the game", False, False),
    ("hall-of-legends", "hall-of-legends", "Show off your best runs", False, False),
    ("co-op-rooms", "co-op-rooms", "Find players for co-op dungeons and raids", False, False),
    ("community-enemies", "community-enemies", "Share the enemies you made", False, False),
    ("community-dungeons", "community-dungeons", "Share the dungeons you made", False, False),
    ("dungeon-descent-testers", "dungeon-descent-testers", "For TestFlight testers: new builds and what to try", False, True),
]

sa = os.environ.get("SA")
if not sa:
    sys.exit("FIREBASE_SERVICE_ACCOUNT isn't set.")
creds = service_account.Credentials.from_service_account_info(json.loads(sa), scopes=["https://www.googleapis.com/auth/datastore"])
s = AuthorizedSession(creds)
base = f"https://firestore.googleapis.com/v1/projects/{PROJECT}/databases/{DATABASE}/documents/chat_channels"
for order, (cid, name, topic, mods, testers) in enumerate(CHANNELS):
    fields = {"name": {"stringValue": name}, "topic": {"stringValue": topic}, "order": {"integerValue": str(order)},
              "modsPost": {"booleanValue": mods}, "testersOnly": {"booleanValue": testers}}
    r = s.patch(f"{base}/{cid}", params={"currentDocument.exists": "false"}, json={"fields": fields})
    if r.ok:
        print("made #" + name)
    elif r.status_code in (400, 409, 412) and ("exist" in r.text.lower() or "precondition" in r.text.lower()):
        print("#" + name, "is already there")
    else:
        print("#" + name, "->", r.status_code, r.text[:500])
        sys.exit(1)
