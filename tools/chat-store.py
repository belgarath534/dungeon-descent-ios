"""Fills in Dungeon Descent Chat's App Store page (com.dungeon.descent.chat)
from store-chat/: subtitle, description, keywords, promotional text, the
category, the age rating answers, content rights, the price (free), and the
App Review details. Support, marketing and privacy policy links and the App
Review contact are copied from the game's own page (com.dungeon.descent).
Safe to run again. Run by the "Chat app store page" workflow.

Needs ASC_KEY_PATH, GOOD_KEY_ID and ASC_ISSUER_ID (from check_asc_key.rb).
Optional: CHAT_REVIEW_EMAIL and CHAT_REVIEW_PASSWORD (the reviewer's demo
account, from GitHub secrets; never written to the repository).

What Apple doesn't allow from a tool: making the app ("New App") and the App
Privacy answers. Those are done on the website.
"""
import os, sys, time
import jwt, requests

API = "https://api.appstoreconnect.apple.com/v1"
CHAT = "com.dungeon.descent.chat"
GAME = "com.dungeon.descent"
HERE = os.path.join(os.path.dirname(__file__), "..", "store-chat")


def token():
    now = int(time.time())
    return jwt.encode({"iss": os.environ["ASC_ISSUER_ID"].strip(), "iat": now, "exp": now + 1000,
                       "aud": "appstoreconnect-v1"}, open(os.environ["ASC_KEY_PATH"]).read(), algorithm="ES256",
                      headers={"kid": os.environ["GOOD_KEY_ID"].strip(), "typ": "JWT"})


S = requests.Session()
S.headers["Authorization"] = "Bearer " + token()
problems = []


def call(method, path, ok404=False, **kw):
    r = S.request(method, path if path.startswith("http") else API + path, timeout=60, **kw)
    if ok404 and r.status_code == 404:
        return None
    if r.status_code >= 300:
        msg = f"{method} {path.split('?')[0]} -> {r.status_code}: {r.text[:600]}"
        print("  ⚠ " + msg)
        problems.append(msg)
        return None
    return r.json() if r.text else {}


def text(name):
    return open(os.path.join(HERE, name)).read().strip()


def app_for(bundle):
    d = call("GET", "/apps", params={"filter[bundleId]": bundle})
    return next((a for a in (d or {}).get("data", []) if a["attributes"]["bundleId"] == bundle), None)


chat, game = app_for(CHAT), app_for(GAME)
if not chat:
    sys.exit("Dungeon Descent Chat isn't in App Store Connect yet. Make it first: Apps, +, New App, "
             "iOS, name Dungeon Descent Chat, bundle ID com.dungeon.descent.chat, SKU ddchat.")
print("Chat app:", chat["attributes"]["name"], chat["id"])

# 1. App information: category, subtitle, privacy policy link, content rights.
info = call("GET", f"/apps/{chat['id']}/appInfos")["data"]
info = next((i for i in info if i["attributes"].get("appStoreState") != "READY_FOR_SALE"), info[0])
call("PATCH", f"/appInfos/{info['id']}", json={"data": {"type": "appInfos", "id": info["id"], "relationships": {
    "primaryCategory": {"data": {"type": "appCategories", "id": "SOCIAL_NETWORKING"}},
    "secondaryCategory": {"data": {"type": "appCategories", "id": "ENTERTAINMENT"}}}}})
print("Category: Social Networking (and Entertainment)")

game_privacy = None
if game:
    for gi in call("GET", f"/apps/{game['id']}/appInfos")["data"]:
        for loc in call("GET", f"/appInfos/{gi['id']}/appInfoLocalizations")["data"]:
            if loc["attributes"]["locale"] == "en-US" and loc["attributes"].get("privacyPolicyUrl"):
                game_privacy = loc["attributes"]["privacyPolicyUrl"]
locs = call("GET", f"/appInfos/{info['id']}/appInfoLocalizations")["data"]
loc = next((l for l in locs if l["attributes"]["locale"] == "en-US"), None)
attrs = {"subtitle": text("en-US/subtitle.txt")}
if game_privacy:
    attrs["privacyPolicyUrl"] = game_privacy
if loc:
    call("PATCH", f"/appInfoLocalizations/{loc['id']}", json={"data": {"type": "appInfoLocalizations", "id": loc["id"], "attributes": attrs}})
print("Subtitle and privacy policy link:", attrs)

call("PATCH", f"/apps/{chat['id']}", json={"data": {"type": "apps", "id": chat["id"],
     "attributes": {"contentRightsDeclaration": "DOES_NOT_USE_THIRD_PARTY_CONTENT"}}})
print("Content rights: no third-party content")

# 2. Age rating. Chat is user-generated content with messaging; nothing else
# applies. Answered one at a time, so a question Apple has renamed or
# removed only skips itself.
age = call("GET", f"/appInfos/{info['id']}/ageRatingDeclaration")
if age:
    aid = age["data"]["id"]
    answers = {
        "alcoholTobaccoOrDrugUseOrReferences": "NONE", "contests": "NONE", "gamblingSimulated": "NONE",
        "horrorOrFearThemes": "NONE", "matureOrSuggestiveThemes": "NONE", "medicalOrTreatmentInformation": "NONE",
        "profanityOrCrudeHumor": "NONE", "sexualContentGraphicAndNudity": "NONE", "sexualContentOrNudity": "NONE",
        "violenceCartoonOrFantasy": "NONE", "violenceRealistic": "NONE",
        "violenceRealisticProlongedGraphicOrSadistic": "NONE", "gunsOrOtherWeapons": "NONE",
        "healthOrWellnessTopics": False, "gambling": False, "lootBox": False, "unrestrictedWebAccess": False,
        "messagingAndChat": True, "userGeneratedContent": True, "socialMedia": True, "advertising": False,
        "parentalControls": False, "ageAssurance": False,
    }
    # All at once (Apple wants the whole questionnaire); any question it
    # names as unknown or invalid is dropped and the rest sent again.
    for attempt in range(6):
        r = S.patch(API + f"/ageRatingDeclarations/{aid}", timeout=60, json={"data": {
            "type": "ageRatingDeclarations", "id": aid, "attributes": answers}})
        if r.ok:
            print(f"Age rating: {len(answers)} answers set (messaging and user-generated content: yes)")
            break
        errs = r.json().get("errors", []) if r.text else []
        print(f"  age rating try {attempt + 1}: {r.status_code}")
        for er in errs:
            print("   ", er.get("code"), "|", er.get("detail", "")[:300], "|", (er.get("source") or {}).get("pointer"))
        bad = {(er.get("source") or {}).get("pointer", "").rsplit("/", 1)[-1] for er in errs} & set(answers)
        if not bad:
            problems.append("age rating: " + r.text[:600])
            break
        for k in bad:
            answers.pop(k)

# 3. Price: free, everywhere.
pts = call("GET", f"/apps/{chat['id']}/appPricePoints", params={"filter[territory]": "USA", "limit": 200})
free = next((p for p in (pts or {}).get("data", []) if float(p["attributes"].get("customerPrice") or 1) == 0), None)
if free:
    if True:
        call("POST", "/appPriceSchedules", json={
            "data": {"type": "appPriceSchedules", "relationships": {
                "app": {"data": {"type": "apps", "id": chat["id"]}},
                "baseTerritory": {"data": {"type": "territories", "id": "USA"}},
                "manualPrices": {"data": [{"type": "appPrices", "id": "${free}"}]}}},
            "included": [{"type": "appPrices", "id": "${free}", "attributes": {"startDate": None},
                          "relationships": {"appPricePoint": {"data": {"type": "appPricePoints", "id": free["id"]}}}}]})
        print("Price: free")

# 4. The version's store text and links.
versions = call("GET", f"/apps/{chat['id']}/appStoreVersions", params={"filter[platform]": "IOS", "limit": 5})["data"]
ver = next((v for v in versions if v["attributes"].get("appStoreState") in
            ("PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED", "METADATA_REJECTED", None)), None)
if not ver:
    print("No editable version (it's in review or live): store text left as it is.")
else:
    print("Version", ver["attributes"]["versionString"], ver["attributes"].get("appStoreState"))
    links, gv = {}, []
    if game:
        gv = call("GET", f"/apps/{game['id']}/appStoreVersions", params={"filter[platform]": "IOS", "limit": 1})["data"]
        if gv:
            for gl in call("GET", f"/appStoreVersions/{gv[0]['id']}/appStoreVersionLocalizations")["data"]:
                if gl["attributes"]["locale"] == "en-US":
                    links = {k: gl["attributes"][k] for k in ("supportUrl", "marketingUrl") if gl["attributes"].get(k)}
    vl = call("GET", f"/appStoreVersions/{ver['id']}/appStoreVersionLocalizations")["data"]
    vl = next((l for l in vl if l["attributes"]["locale"] == "en-US"), None)
    store = {"description": text("en-US/description.txt"), "keywords": text("en-US/keywords.txt"),
             "promotionalText": text("en-US/promotional_text.txt"), **links}
    if vl:
        call("PATCH", f"/appStoreVersionLocalizations/{vl['id']}", json={"data": {
            "type": "appStoreVersionLocalizations", "id": vl["id"], "attributes": store}})
    else:
        call("POST", "/appStoreVersionLocalizations", json={"data": {"type": "appStoreVersionLocalizations",
             "attributes": {"locale": "en-US", **store},
             "relationships": {"appStoreVersion": {"data": {"type": "appStoreVersions", "id": ver["id"]}}}}})
    print("Description, keywords, promotional text" + (", " + ", ".join(links) if links else ""))
    cr = call("GET", f"/apps/{game['id']}/appStoreVersions", params={"limit": 1}) if game else None
    if cr and cr["data"] and cr["data"][0]["attributes"].get("copyright"):
        call("PATCH", f"/appStoreVersions/{ver['id']}", json={"data": {"type": "appStoreVersions", "id": ver["id"],
             "attributes": {"copyright": cr["data"][0]["attributes"]["copyright"]}}})
        print("Copyright:", cr["data"][0]["attributes"]["copyright"])

    # 5. App Review details: the game's contact, our notes, the demo account.
    contact = {}
    if game and gv:
        g = call("GET", f"/appStoreVersions/{gv[0]['id']}/appStoreReviewDetail", ok404=True)
        if g and g.get("data"):
            contact = {k: g["data"]["attributes"][k] for k in ("contactFirstName", "contactLastName", "contactPhone", "contactEmail")
                       if g["data"]["attributes"].get(k)}
    review = {**contact, "notes": text("review_notes.txt")}
    email, pw = os.environ.get("CHAT_REVIEW_EMAIL", "").strip(), os.environ.get("CHAT_REVIEW_PASSWORD", "").strip()
    if email and pw:
        review.update({"demoAccountRequired": True, "demoAccountName": email, "demoAccountPassword": pw})
    else:
        print("  (no CHAT_REVIEW_EMAIL / CHAT_REVIEW_PASSWORD secrets yet: the demo account is left empty)")
    d = call("GET", f"/appStoreVersions/{ver['id']}/appStoreReviewDetail", ok404=True)
    if d and d.get("data"):
        call("PATCH", f"/appStoreReviewDetails/{d['data']['id']}", json={"data": {
            "type": "appStoreReviewDetails", "id": d["data"]["id"], "attributes": review}})
    else:
        call("POST", "/appStoreReviewDetails", json={"data": {"type": "appStoreReviewDetails", "attributes": review,
             "relationships": {"appStoreVersion": {"data": {"type": "appStoreVersions", "id": ver["id"]}}}}})
    print("App Review details:", ", ".join(k for k in review if k != "demoAccountPassword"))

print()
print("Still by hand on the website: App Privacy (Apple has no API for it), and screenshots once the app runs.")
if problems:
    print(f"{len(problems)} thing(s) Apple refused (above).")
    sys.exit(1)
