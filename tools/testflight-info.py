"""Fills in everything TestFlight asks for, and sends the newest builds to the
external tester groups. Run by .github/workflows/testflight-info.yml (push to
the "testflight-info" branch), after a TestFlight upload.

  1. Test Information (en-US): the beta description, the feedback email and
     the marketing and privacy policy links.
  2. Beta App Review contact details: copied from the App Store version's App
     Review details (name, phone, email), so nothing is typed twice.
  3. Each platform's newest processed build: "What to Test" from
     store/en-US/testflight/<PLATFORM>.txt, and export compliance (no
     non-exempt encryption) if it isn't set yet.
  4. Those builds go to every external tester group, and to Beta App Review
     (needed once per version before external testers get it).

The builds are those of VERSION, by default the MARKETING_VERSION in
swift/App/project.yml of the commit it runs on (so a 12.1 test build never
reaches testers by accident from a 12.0.1 run).

Env: APP_STORE_CONNECT_PRIVATE_KEY (or @file:path), APP_STORE_CONNECT_ISSUER_ID,
APP_STORE_CONNECT_KEY_IDENTIFIER. PLATFORMS (default "IOS MAC_OS VISION_OS").
Contact details are never printed.
"""
import os, sys, time
import jwt, requests

API = "https://api.appstoreconnect.apple.com/v1"
BUNDLE = "com.dungeon.descent"
HERE = os.path.dirname(os.path.abspath(__file__))
NOTES = os.path.join(HERE, "..", "store", "en-US", "testflight")

DESCRIPTION = (
    "Dungeon Descent is a fully accessible dungeon crawler built for VoiceOver and screen reader players. "
    "Beta builds bring new features and fixes before they reach the App Store. Please play what's new in "
    "each build and tell us about bugs: what happened, what you were doing, and your device. Use Send "
    "Feedback in Settings, TestFlight's feedback, or the Dungeon Descent Discord.")
MARKETING_URL = "https://dungen-descent.org"
PRIVACY_URL = "https://dungen-descent.org/privacy.html"
REVIEW_NOTES = (
    "No account is needed to play: create a character and press Play. Signing in (optional) only adds cloud "
    "sync and online features. Co-op needs a second player with a 4-letter room code. The Voice Pack "
    "(Settings, Voice Pack, iPhone and iPad) downloads a speech model on request.")

problems = []


def project_version():
    import re
    try:
        m = re.search(r'MARKETING_VERSION:\s*"([^"]+)"', open(os.path.join(HERE, "..", "swift", "App", "project.yml")).read())
        return m.group(1) if m else None
    except OSError:
        return None


VERSION = os.environ.get("VERSION") or project_version()


def private_key():
    key = os.environ["APP_STORE_CONNECT_PRIVATE_KEY"].strip()
    if key.startswith("@file:"):
        key = open(os.path.expanduser(key[6:])).read()
    key = key.replace("\\n", "\n").strip().strip('"')
    if "BEGIN" not in key:
        body = "".join(key.split())
        key = "-----BEGIN PRIVATE KEY-----\n" + "\n".join(body[i:i + 64] for i in range(0, len(body), 64)) + "\n-----END PRIVATE KEY-----"
    return key


def token():
    now = int(time.time())
    return jwt.encode({"iss": os.environ["APP_STORE_CONNECT_ISSUER_ID"], "iat": now, "exp": now + 1000,
                       "aud": "appstoreconnect-v1"}, private_key(), algorithm="ES256",
                      headers={"kid": os.environ["APP_STORE_CONNECT_KEY_IDENTIFIER"], "typ": "JWT"})


S = requests.Session()
S.headers["Authorization"] = "Bearer " + token()


def call(method, path, ok=(), **kw):
    """The JSON, or None on an error (noted, unless its status is in ok)."""
    r = S.request(method, path if path.startswith("http") else API + path, timeout=60, **kw)
    if r.status_code >= 400:
        if r.status_code not in ok:
            problems.append(f"{method} {path.split('?')[0]} -> {r.status_code}: {r.text[:400]}")
            print(f"⚠️ {problems[-1]}")
        return None
    return r.json() if r.content else {}


# Exact match: the filter also matches com.dungeon.descent.chat (Dungeon Descent Chat).
app = next(a["id"] for a in call("GET", "/apps", params={"filter[bundleId]": BUNDLE})["data"] if a["attributes"]["bundleId"] == BUNDLE)

# 1. Test Information
locs = (call("GET", f"/apps/{app}/betaAppLocalizations") or {"data": []})["data"]
en = next((l for l in locs if l["attributes"].get("locale") == "en-US"), None)

# 2. Contact details, from the newest iPhone App Store version's App Review details.
contact = {}
for v in (call("GET", f"/apps/{app}/appStoreVersions", params={"filter[platform]": "IOS", "limit": 5}) or {"data": []})["data"]:
    d = call("GET", f"/appStoreVersions/{v['id']}/appStoreReviewDetail", ok=(404,))
    a = (d or {}).get("data", {}) and d["data"]["attributes"]
    if a and a.get("contactEmail"):
        contact = {k: a.get(k) for k in ("contactFirstName", "contactLastName", "contactPhone", "contactEmail")}
        break
if not contact:
    problems.append("No App Review contact details on the App Store versions to copy")

attrs = {"description": DESCRIPTION, "marketingUrl": MARKETING_URL, "privacyPolicyUrl": PRIVACY_URL}
if contact.get("contactEmail"):
    attrs["feedbackEmail"] = contact["contactEmail"]
if en:
    if call("PATCH", f"/betaAppLocalizations/{en['id']}",
            json={"data": {"type": "betaAppLocalizations", "id": en["id"], "attributes": attrs}}) is not None:
        print("✅ Test Information (en-US) updated")
else:
    if call("POST", "/betaAppLocalizations", json={"data": {"type": "betaAppLocalizations",
            "attributes": dict(attrs, locale="en-US"),
            "relationships": {"app": {"data": {"type": "apps", "id": app}}}}}) is not None:
        print("✅ Test Information (en-US) created")

rd = call("GET", f"/apps/{app}/betaAppReviewDetail")
if rd and rd.get("data") and contact:
    want = dict(contact, demoAccountRequired=False, notes=REVIEW_NOTES)
    if call("PATCH", f"/betaAppReviewDetails/{rd['data']['id']}",
            json={"data": {"type": "betaAppReviewDetails", "id": rd["data"]["id"], "attributes": want}}) is not None:
        print("✅ Beta App Review contact details copied from App Review (not shown)")

# 3 and 4. The newest processed build of each platform.
groups = [g for g in (call("GET", f"/apps/{app}/betaGroups", params={"limit": 50}) or {"data": []})["data"]
          if not g["attributes"].get("isInternalGroup")]
print(f"External tester groups: {', '.join(g['attributes']['name'] for g in groups) or 'none'}")

for platform in os.environ.get("PLATFORMS", "IOS MAC_OS VISION_OS").split():
    builds = (call("GET", "/builds", params={"filter[app]": app, "filter[preReleaseVersion.platform]": platform,
              "filter[processingState]": "VALID", "sort": "-uploadedDate", "limit": 1,
              **({"filter[preReleaseVersion.version]": VERSION} if VERSION else {}),
              "include": "preReleaseVersion"}) or {"data": []})
    if not builds["data"]:
        print(f"{platform}: no processed build of {VERSION or 'any version'}")
        continue
    b = builds["data"][0]
    ver = next((i["attributes"].get("version") for i in builds.get("included", []) if i["type"] == "preReleaseVersions"), "?")
    print(f"== {platform}: {ver} ({b['attributes'].get('version')})")

    if b["attributes"].get("usesNonExemptEncryption") is None:
        if call("PATCH", f"/builds/{b['id']}", json={"data": {"type": "builds", "id": b["id"],
                "attributes": {"usesNonExemptEncryption": False}}}) is not None:
            print("   export compliance: no non-exempt encryption")

    path = os.path.join(NOTES, f"{platform}.txt")
    if os.path.exists(path):
        text = open(path).read().strip()[:4000]
        bl = (call("GET", f"/builds/{b['id']}/betaBuildLocalizations") or {"data": []})["data"]
        cur = next((l for l in bl if l["attributes"].get("locale") == "en-US"), None)
        if cur:
            ok = call("PATCH", f"/betaBuildLocalizations/{cur['id']}", json={"data": {
                "type": "betaBuildLocalizations", "id": cur["id"], "attributes": {"whatsNew": text}}})
        else:
            ok = call("POST", "/betaBuildLocalizations", json={"data": {"type": "betaBuildLocalizations",
                "attributes": {"locale": "en-US", "whatsNew": text},
                "relationships": {"build": {"data": {"type": "builds", "id": b["id"]}}}}})
        if ok is not None:
            print("   What to Test set")

    for g in groups:
        if call("POST", f"/betaGroups/{g['id']}/relationships/builds",
                json={"data": [{"type": "builds", "id": b["id"]}]}) is not None:
            print(f"   added to {g['attributes']['name']}")

    if groups:
        r = S.post(API + "/betaAppReviewSubmissions", timeout=60, json={"data": {"type": "betaAppReviewSubmissions",
                   "relationships": {"build": {"data": {"type": "builds", "id": b["id"]}}}}})
        if r.ok:
            print("   sent to Beta App Review")
        elif r.status_code == 409 or "already" in r.text.lower():
            print("   Beta App Review: already submitted or approved for this version")
        else:
            problems.append(f"Beta App Review {platform}: {r.status_code}: {r.text[:400]}")
            print(f"⚠️ {problems[-1]}")

if problems:
    sys.exit(f"\n{len(problems)} step(s) didn't go through; see the ⚠️ lines above.")
print("\nTestFlight information is filled in.")
