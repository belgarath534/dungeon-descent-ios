#!/usr/bin/env python3
"""Which App Group each App ID uses (for the watch complications).

Apple's API can't list App Groups, but a provisioning profile carries the
groups its App ID is set up with. For each App ID this prints its
capabilities, then makes a throwaway App Store profile, reads the groups out
of it, and deletes it again.
"""
import base64, os, plistlib, re, time
import jwt, requests

IDS = ["com.dungeon.descent", "com.dungeon.descent.watchkitapp", "com.dungeon.descent.watchkitapp.widget"]
WANT = "group.com.dungeon.descent"
API = "https://api.appstoreconnect.apple.com"

def token():
    now = int(time.time())
    return jwt.encode({"iss": os.environ["ASC_ISSUER_ID"].strip(), "iat": now, "exp": now + 1000,
                       "aud": "appstoreconnect-v1"}, open(os.environ["ASC_KEY_PATH"]).read(), algorithm="ES256",
                      headers={"kid": os.environ["GOOD_KEY_ID"].strip(), "typ": "JWT"})

def call(method, path, body=None, params=None):
    r = requests.request(method, API + path, json=body, params=params,
                         headers={"Authorization": "Bearer " + token()}, timeout=60)
    if r.status_code >= 400:
        print(f"  {method} {path} → {r.status_code}: {r.text[:300]}")
        return None
    return r.json() if r.text else {}

certs = call("GET", "/v1/certificates", params={"limit": 50}) or {"data": []}
dist = [c for c in certs["data"] if c["attributes"]["certificateType"] in ("DISTRIBUTION", "IOS_DISTRIBUTION")]
print(f"Distribution certificates: {len(dist)}")
ok = True
for ident in IDS:
    print(f"\n== {ident}")
    b = call("GET", "/v1/bundleIds", params={"filter[identifier]": ident, "limit": 5})
    match = [x for x in (b or {}).get("data", []) if x["attributes"]["identifier"] == ident]
    if not match:
        print("  App ID not found"); ok = False; continue
    bid = match[0]["id"]
    caps = call("GET", f"/v1/bundleIds/{bid}/bundleIdCapabilities") or {"data": []}
    types = sorted(c["attributes"]["capabilityType"] for c in caps["data"])
    print("  Capabilities:", ", ".join(types) or "none")
    if "APP_GROUPS" not in types:
        print("  ✗ App Groups is NOT turned on"); ok = False; continue
    if not dist:
        print("  (no distribution certificate to test with)"); continue
    p = call("POST", "/v1/profiles", body={"data": {"type": "profiles",
        "attributes": {"name": f"app-group-check {ident} {int(time.time())}", "profileType": "IOS_APP_STORE"},
        "relationships": {"bundleId": {"data": {"type": "bundleIds", "id": bid}},
                          "certificates": {"data": [{"type": "certificates", "id": dist[0]["id"]}]}}}})
    if not p: ok = False; continue
    raw = base64.b64decode(p["data"]["attributes"]["profileContent"])
    m = re.search(rb"<\?xml.*</plist>", raw, re.S)
    ents = plistlib.loads(m.group(0)).get("Entitlements", {}) if m else {}
    groups = ents.get("com.apple.security.application-groups", [])
    print("  Groups:", ", ".join(groups) or "none")
    print("  ✓ Correct" if WANT in groups else f"  ✗ {WANT} is not one of them")
    if WANT not in groups: ok = False
    call("DELETE", f"/v1/profiles/{p['data']['id']}")
print("\nALL GOOD" if ok else "\nSOMETHING NEEDS FIXING (see above)")
