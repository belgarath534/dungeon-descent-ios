"""Gets one platform's 11.8 version of Dungeon Descent ready and sends it to
App Store review. Run by the "store-submit" Codemagic workflow.

  PLATFORM   VISION_OS, MAC_OS or IOS (the version to submit)
  VERSION    default 11.8
  SUBMIT     "yes" to send it to review; anything else only checks and fills in

What it does:
  1. Copies what this version is missing from the iPhone version: copyright,
     support / marketing URLs, and the App Review contact details and notes.
  2. Selects the newest processed build of this platform and version.
  3. With SUBMIT=yes, sends the version to App Review.
"""
import os, sys, time
import jwt, requests

API = "https://api.appstoreconnect.apple.com/v1"
BUNDLE = "com.dungeon.descent"


def private_key():
    key = os.environ["APP_STORE_CONNECT_PRIVATE_KEY"].strip()
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
    now = int(time.time())
    return jwt.encode({"iss": os.environ["APP_STORE_CONNECT_ISSUER_ID"], "iat": now, "exp": now + 1000,
                       "aud": "appstoreconnect-v1"}, private_key(), algorithm="ES256",
                      headers={"kid": os.environ["APP_STORE_CONNECT_KEY_IDENTIFIER"], "typ": "JWT"})


S = requests.Session()
S.headers["Authorization"] = "Bearer " + token()


def call(method, path, ok404=False, **kw):
    r = S.request(method, path if path.startswith("http") else API + path, timeout=60, **kw)
    if ok404 and r.status_code == 404:
        return None
    if r.status_code >= 400:
        sys.exit(f"{method} {path} -> {r.status_code}: {r.text[:800]}")
    return r.json() if r.content else {}


platform = os.environ["PLATFORM"]
version = os.environ.get("VERSION", "11.8")
submit = os.environ.get("SUBMIT", "") == "yes"

app = call("GET", "/apps", params={"filter[bundleId]": BUNDLE})["data"][0]["id"]

# STATUS=yes: only print where this platform's version is in review.
if os.environ.get("STATUS") == "yes":
    for v in call("GET", f"/apps/{app}/appStoreVersions", params={"filter[platform]": platform, "limit": 3})["data"]:
        a = v["attributes"]
        print(f"{platform} {a.get('versionString')}: {a.get('appStoreState') or a.get('appVersionState')}"
              f" (release: {a.get('releaseType')})")
        b = call("GET", f"/appStoreVersions/{v['id']}/build", ok404=True)
        if b and b.get("data"):
            print(f"  build {b['data']['attributes'].get('version')}, uploaded {b['data']['attributes'].get('uploadedDate')}")
    for st in ("WAITING_FOR_REVIEW", "IN_REVIEW", "UNRESOLVED_ISSUES", "COMPLETE"):
        for o in call("GET", "/reviewSubmissions", params={"filter[app]": app, "filter[platform]": platform,
                      "filter[state]": st, "limit": 2})["data"]:
            print(f"  submission {o['id'][:8]}: {st}, submitted {o['attributes'].get('submittedDate')}")
    sys.exit(0)

# CANCEL=yes: take this platform's version back out of App Review (to add
# something before it's reviewed), then stop. Submitting again later works
# as usual (the version goes back to "Developer Rejected").
if os.environ.get("CANCEL") == "yes":
    found = False
    for st in ("WAITING_FOR_REVIEW", "IN_REVIEW", "READY_FOR_REVIEW"):
        for o in call("GET", "/reviewSubmissions", params={"filter[app]": app, "filter[platform]": platform,
                      "filter[state]": st})["data"]:
            found = True
            r = S.patch(API + f"/reviewSubmissions/{o['id']}", timeout=60, json={"data": {"type": "reviewSubmissions",
                        "id": o["id"], "attributes": {"canceled": True}}})
            print(f"{platform}: submission {o['id']} ({st}) -> {'canceled' if r.ok else f'{r.status_code}: {r.text[:300]}'}")
            if not r.ok:
                sys.exit(1)
    print(f"{platform}: " + ("taken out of review." if found else "nothing in review."))
    sys.exit(0)


def version_of(p):
    v = call("GET", f"/apps/{app}/appStoreVersions",
             params={"filter[platform]": p, "filter[versionString]": version})["data"]
    return v[0] if v else None


# AUTO_RELEASE=yes: release this version as soon as it's approved, then stop.
if os.environ.get("AUTO_RELEASE") == "yes":
    v = version_of(platform)
    if not v:
        sys.exit(f"No {platform} {version} version")
    before = v["attributes"].get("releaseType")
    if before != "AFTER_APPROVAL":
        call("PATCH", f"/appStoreVersions/{v['id']}", json={"data": {"type": "appStoreVersions", "id": v["id"],
             "attributes": {"releaseType": "AFTER_APPROVAL"}}})
    now = version_of(platform)["attributes"].get("releaseType")
    print(f"{platform} {version}: release {before} -> {now}")
    sys.exit(0)

target = version_of(platform)
if not target:
    sys.exit(f"No {platform} {version} version")
state = target["attributes"].get("appStoreState") or target["attributes"].get("appVersionState")
print(f"{platform} {version}: {state}")
# READY_FOR_REVIEW: in a submission that hasn't been sent yet.
if state not in ("PREPARE_FOR_SUBMISSION", "READY_FOR_REVIEW", "DEVELOPER_REJECTED", "REJECTED", "METADATA_REJECTED"):
    sys.exit(f"It's {state}, nothing to do.")
source = version_of("IOS")
# The iPhone version itself: copy from the iPhone version before it (a new
# 12.0.1 starts without App Review details).
if platform == "IOS" or not source:
    for v in call("GET", f"/apps/{app}/appStoreVersions", params={"filter[platform]": "IOS", "limit": 5})["data"]:
        if v["id"] != target["id"]:
            source = v
            break

# 1. Copyright
if not target["attributes"].get("copyright") and source and source["attributes"].get("copyright"):
    call("PATCH", f"/appStoreVersions/{target['id']}", json={"data": {"type": "appStoreVersions", "id": target["id"],
         "attributes": {"copyright": source["attributes"]["copyright"]}}})
    print("Copyright copied from the iPhone version")

# URLs on the en-US listing
def en_us(v):
    locs = call("GET", f"/appStoreVersions/{v['id']}/appStoreVersionLocalizations")["data"]
    return next((l for l in locs if l["attributes"]["locale"] == "en-US"), locs[0] if locs else None)

tl, sl = en_us(target), (en_us(source) if source else None)
if tl and sl:
    fill = {k: sl["attributes"][k] for k in ("supportUrl", "marketingUrl")
            if sl["attributes"].get(k) and not tl["attributes"].get(k)}
    if fill:
        call("PATCH", f"/appStoreVersionLocalizations/{tl['id']}", json={"data": {
            "type": "appStoreVersionLocalizations", "id": tl["id"], "attributes": fill}})
        print("Copied from the iPhone listing:", ", ".join(fill))

# App Review contact and notes
def review(v):
    r = call("GET", f"/appStoreVersions/{v['id']}/appStoreReviewDetail", ok404=True)
    return (r or {}).get("data")

tr, sr = review(target), (review(source) if source else None)
fields = ("contactFirstName", "contactLastName", "contactPhone", "contactEmail", "notes", "demoAccountRequired")
if sr:
    want = {k: sr["attributes"].get(k) for k in fields if sr["attributes"].get(k) is not None}
    if not tr:
        call("POST", "/appStoreReviewDetails", json={"data": {"type": "appStoreReviewDetails", "attributes": want,
             "relationships": {"appStoreVersion": {"data": {"type": "appStoreVersions", "id": target["id"]}}}}})
        print("App Review contact details copied from the iPhone version")
    else:
        missing = {k: v for k, v in want.items() if not tr["attributes"].get(k)}
        if missing:
            call("PATCH", f"/appStoreReviewDetails/{tr['id']}", json={"data": {
                "type": "appStoreReviewDetails", "id": tr["id"], "attributes": missing}})
            print("App Review details filled in:", ", ".join(missing))

# 2. The newest processed build of this platform and version
builds = call("GET", "/builds", params={"filter[app]": app, "filter[preReleaseVersion.platform]": platform,
                                       "filter[preReleaseVersion.version]": version,
                                       "filter[processingState]": "VALID", "sort": "-uploadedDate", "limit": 1})["data"]
if not builds:
    sys.exit(f"No processed {platform} {version} build yet")
build = builds[0]
call("PATCH", f"/appStoreVersions/{target['id']}/relationships/build",
     json={"data": {"type": "builds", "id": build["id"]}})
print(f"Build {build['attributes']['version']} selected")

# Screenshots present?
sets = call("GET", f"/appStoreVersionLocalizations/{tl['id']}/appScreenshotSets")["data"] if tl else []
count = sum(len(call("GET", f"/appScreenshotSets/{s['id']}/appScreenshots")["data"]) for s in sets)
print(f"Screenshots: {count}")
if count == 0:
    sys.exit("No screenshots yet: not submitting")

if not submit:
    print("Check only (SUBMIT is not yes): ready to submit.")
    sys.exit(0)

# Released as soon as it's approved.
if target["attributes"].get("releaseType") != "AFTER_APPROVAL":
    call("PATCH", f"/appStoreVersions/{target['id']}", json={"data": {"type": "appStoreVersions", "id": target["id"],
         "attributes": {"releaseType": "AFTER_APPROVAL"}}})
    print("Release: as soon as it's approved")

# 3. Send to App Review
# Screenshots that were just uploaded need a few minutes of processing first.
for _ in range(30):
    pending = []
    for st in sets:
        for shot in call("GET", f"/appScreenshotSets/{st['id']}/appScreenshots")["data"]:
            state = ((shot["attributes"].get("assetDeliveryState") or {}).get("state"))
            if state != "COMPLETE":
                pending.append(state)
    if not pending:
        break
    print(f"Waiting for Apple to process {len(pending)} screenshot(s)…")
    time.sleep(30)

# After a rejection the version stays in its old submission ("unresolved
# issues"): resubmitting means sending that one again. Otherwise reuse a
# submission left open by an earlier try, else start one.
def subs(state):
    return call("GET", "/reviewSubmissions", params={"filter[app]": app, "filter[platform]": platform,
                "filter[state]": state})["data"]
open_subs = subs("READY_FOR_REVIEW")
rejected = subs("UNRESOLVED_ISSUES")
if rejected:
    # Empty submissions from failed tries would stand in the way: cancel them.
    for o in open_subs:
        if not call("GET", f"/reviewSubmissions/{o['id']}/items")["data"]:
            # Not every state can be canceled; one that can't is left alone.
            S.patch(API + f"/reviewSubmissions/{o['id']}", timeout=60, json={"data": {"type": "reviewSubmissions",
                    "id": o["id"], "attributes": {"canceled": True}}})
    open_subs = rejected
sub = open_subs[0] if open_subs else call("POST", "/reviewSubmissions", json={"data": {"type": "reviewSubmissions",
           "attributes": {"platform": platform},
           "relationships": {"app": {"data": {"type": "apps", "id": app}}}}})["data"]
items = call("GET", f"/reviewSubmissions/{sub['id']}/items")["data"]
for it in items:
    print(f"Submission {sub['id']} ({sub['attributes'].get('state')}): item {it['id']} is {it['attributes'].get('state')}")
    # A rejected item has to be marked resolved before the submission goes back.
    if it["attributes"].get("state") == "REJECTED":
        call("PATCH", f"/reviewSubmissionItems/{it['id']}", json={"data": {"type": "reviewSubmissionItems",
             "id": it["id"], "attributes": {"resolved": True}}})
        print(f"  marked resolved")
if not items:
    call("POST", "/reviewSubmissionItems", json={"data": {"type": "reviewSubmissionItems", "relationships": {
         "reviewSubmission": {"data": {"type": "reviewSubmissions", "id": sub["id"]}},
         "appStoreVersion": {"data": {"type": "appStoreVersions", "id": target["id"]}}}}})
call("PATCH", f"/reviewSubmissions/{sub['id']}", json={"data": {"type": "reviewSubmissions", "id": sub["id"],
     "attributes": {"submitted": True}}})
print(f"Submitted {platform} {version} (build {build['attributes']['version']}) for App Review.")
