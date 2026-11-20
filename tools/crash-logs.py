#!/usr/bin/env python3
"""The newest TestFlight crash reports (the ones testers shared), with the
crash log's top: the exception and the crashed thread's first frames."""
import os, time, jwt, requests

API = "https://api.appstoreconnect.apple.com/v1"
def token():
    now = int(time.time())
    return jwt.encode({"iss": os.environ["ASC_ISSUER_ID"].strip(), "iat": now, "exp": now + 1000,
                       "aud": "appstoreconnect-v1"}, open(os.environ["ASC_KEY_PATH"]).read(), algorithm="ES256",
                      headers={"kid": os.environ["GOOD_KEY_ID"].strip(), "typ": "JWT"})
H = {"Authorization": "Bearer " + token()}
def get(path, **params):
    r = requests.get(API + path, headers=H, params=params, timeout=60)
    if r.status_code >= 400:
        print(f"{path} -> {r.status_code}: {r.text[:400]}"); return None
    return r.json()

app = get("/apps", **{"filter[bundleId]": "com.dungeon.descent"})["data"][0]["id"]
subs = get(f"/apps/{app}/betaFeedbackCrashSubmissions", sort="-createdDate", limit=5) or {"data": []}
print(f"{len(subs['data'])} shared crash report(s)")
for s in subs["data"]:
    a = s["attributes"]
    print("\n======", a.get("createdDate"), a.get("deviceModel"), a.get("osVersion"), "build", a.get("buildBundleId"), "|", a.get("comment"))
    log = get(f"/betaFeedbackCrashSubmissions/{s['id']}/crashLog")
    text = ((log or {}).get("data") or {}).get("attributes", {}).get("logText") or ""
    lines = text.splitlines()
    keep, crashed = [], False
    for l in lines:
        if any(k in l for k in ("Exception Type", "Exception Codes", "Termination Reason", "Crashed Thread", "Triggered by Thread", "Application Specific", "Version:", "Abort", "fatal")):
            keep.append(l)
        if "Crashed:" in l: crashed = True; keep.append(l); continue
        if crashed:
            if not l.strip(): crashed = False
            else: keep.append(l)
    print("\n".join(keep[:70]) if keep else text[:3000])
