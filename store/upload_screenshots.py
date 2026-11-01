"""Uploads App Store screenshots for one platform of Dungeon Descent.

Run by the "store-screenshots" Codemagic workflow, which provides the App
Store Connect key (APP_STORE_CONNECT_ISSUER_ID, _KEY_IDENTIFIER, _PRIVATE_KEY).

  PLATFORM      IOS, MAC_OS or VISION_OS
  DISPLAY_TYPE  App Store Connect screenshot type, e.g. APP_APPLE_VISION_PRO
  SHOTS_DIR     folder of PNGs, uploaded in file-name order
  VERSION       the version to fill (default 11.8)

The version's en-US screenshots of that type are replaced.
"""
import glob, hashlib, os, sys, time
import jwt, requests

API = "https://api.appstoreconnect.apple.com/v1"
BUNDLE = "com.dungeon.descent"


def private_key():
    """Codemagic's integration hands the key over as text, a file path
    (@file:...) or another variable (@env:...), sometimes with escaped
    newlines or without the PEM header."""
    key = os.environ["APP_STORE_CONNECT_PRIVATE_KEY"].strip()
    raw = key
    print(f"Key format: {len(raw)} chars, starts with @: {raw.startswith('@')}, PEM header: {'BEGIN' in raw}, "
          f"escaped newlines: {chr(92) + 'n' in raw}, real newlines: {chr(10) in raw}")
    if key.startswith("@file:"):
        key = open(os.path.expanduser(key[6:])).read()
    elif key.startswith("@env:"):
        key = os.environ[key[5:]]
    key = key.replace("\\n", "\n").strip().strip('"')
    if "BEGIN" not in key:
        body = "".join(key.split())
        key = "-----BEGIN PRIVATE KEY-----\n" + "\n".join(body[i:i + 64] for i in range(0, len(body), 64)) + "\n-----END PRIVATE KEY-----"
    return key


def token():
    key = private_key()
    now = int(time.time())
    return jwt.encode({"iss": os.environ["APP_STORE_CONNECT_ISSUER_ID"], "iat": now, "exp": now + 1000,
                       "aud": "appstoreconnect-v1"}, key, algorithm="ES256",
                      headers={"kid": os.environ["APP_STORE_CONNECT_KEY_IDENTIFIER"], "typ": "JWT"})


S = requests.Session()
S.headers["Authorization"] = "Bearer " + token()


def call(method, path, **kw):
    r = S.request(method, path if path.startswith("http") else API + path, timeout=60, **kw)
    if r.status_code >= 400:
        sys.exit(f"{method} {path} -> {r.status_code}: {r.text[:600]}")
    return r.json() if r.content else {}


platform = os.environ["PLATFORM"]
display = os.environ["DISPLAY_TYPE"]
version = os.environ.get("VERSION", "11.8")
files = sorted(glob.glob(os.path.join(os.environ["SHOTS_DIR"], "*.png")))
if not files:
    sys.exit("No screenshots found in " + os.environ["SHOTS_DIR"])

app = call("GET", "/apps", params={"filter[bundleId]": BUNDLE})["data"][0]["id"]
versions = call("GET", f"/apps/{app}/appStoreVersions",
                params={"filter[platform]": platform, "filter[versionString]": version})["data"]
if not versions:
    sys.exit(f"No {platform} {version} version in App Store Connect")
locs = call("GET", f"/appStoreVersions/{versions[0]['id']}/appStoreVersionLocalizations")["data"]
loc = next((l for l in locs if l["attributes"]["locale"] == "en-US"), None) or locs[0]

sets = call("GET", f"/appStoreVersionLocalizations/{loc['id']}/appScreenshotSets",
            params={"filter[screenshotDisplayType]": display})["data"]
if sets:
    set_id = sets[0]["id"]
    for old in call("GET", f"/appScreenshotSets/{set_id}/appScreenshots")["data"]:
        call("DELETE", f"/appScreenshots/{old['id']}")
        print("Removed an old screenshot")
else:
    set_id = call("POST", "/appScreenshotSets", json={"data": {
        "type": "appScreenshotSets", "attributes": {"screenshotDisplayType": display},
        "relationships": {"appStoreVersionLocalization": {"data": {"type": "appStoreVersionLocalizations", "id": loc["id"]}}}}})["data"]["id"]

for path in files:
    data = open(path, "rb").read()
    shot = call("POST", "/appScreenshots", json={"data": {
        "type": "appScreenshots", "attributes": {"fileName": os.path.basename(path), "fileSize": len(data)},
        "relationships": {"appScreenshotSet": {"data": {"type": "appScreenshotSets", "id": set_id}}}}})["data"]
    for op in shot["attributes"]["uploadOperations"]:
        part = data[op["offset"]:op["offset"] + op["length"]]
        headers = {h["name"]: h["value"] for h in op.get("requestHeaders", [])}
        r = requests.request(op["method"], op["url"], headers=headers, data=part, timeout=120)
        if r.status_code >= 400:
            sys.exit(f"Upload of {path} failed: {r.status_code} {r.text[:300]}")
    call("PATCH", f"/appScreenshots/{shot['id']}", json={"data": {
        "type": "appScreenshots", "id": shot["id"],
        "attributes": {"uploaded": True, "sourceFileChecksum": hashlib.md5(data).hexdigest()}}})
    print("Uploaded", os.path.basename(path))

print(f"Done: {len(files)} screenshots in {platform} {version} ({display}).")
