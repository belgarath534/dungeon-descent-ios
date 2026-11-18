"""Makes the next App Store version (VERSION, default 11.9) for iPhone, Mac
and Apple Vision Pro in App Store Connect, if it isn't there yet, and fills in
"What's New" in English and Portuguese. Run by the "New App Store version"
GitHub workflow with the key the TestFlight workflow finds. Safe to run again.
The build is picked and the version sent to review separately
(store/submit_version.py), once the TestFlight builds are processed.
"""
import os, sys, time
import jwt, requests

API = "https://api.appstoreconnect.apple.com/v1"
BUNDLE = "com.dungeon.descent"
VERSION = os.environ.get("VERSION", "11.9")

WHATS_NEW = {
    "en-US": """New in 11.9:
• Daily World Boss: one boss a day that every player fights together.
• Weekly Ladder: one dungeon all week, one life, a new top 10 every Monday.
• Game Center leaderboards and friend challenges for Endless Descent, the Weekly Ladder and The Spire.
• Endless Descent rivals on the Lock Screen.
• Apple Watch complication for the Daily World Boss.
• Siri and Shortcuts: start Endless Descent, check your run, use a potion.
• A Welcome back reward after time away.
• "What just happened": two-finger double-tap in a run reads the last few lines.
• Short combat lines and warning sounds (Settings, Accessibility).
• My Tracks: play songs from your Apple Music library.
• Much more of the game in Portuguese.
• A loading screen, the Music Box tutorial and your total playtime.
• Fixes: VoiceOver keeps up in The Spire's Auto Mode, the Lock Screen keeps moving in Endless Descent, and music no longer starts while the app is closed.""",
    "pt-BR": """Novidades da 11.9:
• Chefe Mundial Diário: um chefe por dia que todos os jogadores enfrentam juntos.
• Escada Semanal: uma masmorra a semana toda, uma vida, um novo top 10 toda segunda.
• Placares e desafios entre amigos no Game Center para a Descida Sem Fim, a Escada Semanal e a Torre.
• Rivais da Descida Sem Fim na Tela Bloqueada.
• Complicação do Chefe Mundial Diário no Apple Watch.
• Siri e Atalhos: comece a Descida Sem Fim, veja sua jornada, use uma poção.
• Recompensa de Bem-vindo de volta depois de um tempo fora.
• "O que aconteceu": toque duplo com dois dedos numa jornada lê as últimas linhas.
• Linhas de combate curtas e sons de aviso (Ajustes, Acessibilidade).
• Minhas Músicas: toque músicas da sua biblioteca do Apple Music.
• Muito mais do jogo em português.
• Tela de carregamento, tutorial da Caixa de Música e seu tempo total de jogo.
• Correções: o VoiceOver acompanha o Modo Automático da Torre, a Tela Bloqueada continua atualizando na Descida Sem Fim e a música não toca mais com o app fechado.""",
}
# The Mac and Vision Pro have no watch, Lock Screen or Apple Music picker.
SKIP = {
    "MAC_OS": ("Lock Screen", "Apple Watch", "Siri", "two-finger", "Tela Bloqueada", "dois dedos", "Apple Music"),
    "VISION_OS": ("Lock Screen", "Apple Watch", "Tela Bloqueada", "two-finger", "dois dedos", "Apple Music"),
}


def token():
    now = int(time.time())
    return jwt.encode({"iss": os.environ["ASC_ISSUER_ID"].strip(), "iat": now, "exp": now + 1000,
                       "aud": "appstoreconnect-v1"}, open(os.environ["ASC_KEY_PATH"]).read(), algorithm="ES256",
                      headers={"kid": os.environ["GOOD_KEY_ID"].strip(), "typ": "JWT"})


S = requests.Session()
S.headers["Authorization"] = "Bearer " + token()
problems = []


def call(method, path, body=None, params=None):
    r = S.request(method, API + path, json=body, params=params, timeout=60)
    if r.status_code >= 400:
        msg = f"{method} {path} -> {r.status_code}: {r.text[:900]}"
        print("⚠️ " + msg)
        problems.append(msg)
        return None
    return r.json() if r.content else {}


def notes(platform, locale):
    lines = WHATS_NEW[locale].split("\n")
    skip = SKIP.get(platform, ())
    lines = [l for l in lines if not any(s in l for s in skip)]
    return "\n".join(lines)


app = call("GET", "/apps", params={"filter[bundleId]": BUNDLE})["data"][0]["id"]
for platform in ("IOS", "MAC_OS", "VISION_OS"):
    found = call("GET", f"/apps/{app}/appStoreVersions",
                 params={"filter[platform]": platform, "filter[versionString]": VERSION})
    if found is None:
        continue
    if found["data"]:
        v = found["data"][0]
        print(f"• {platform} {VERSION} is already there ({v['attributes'].get('appStoreState')})")
    else:
        made = call("POST", "/appStoreVersions", {"data": {"type": "appStoreVersions",
                    "attributes": {"platform": platform, "versionString": VERSION},
                    "relationships": {"app": {"data": {"type": "apps", "id": app}}}}})
        if not made:
            continue
        v = made["data"]
        print(f"✅ Made {platform} {VERSION}")
    locs = call("GET", f"/appStoreVersions/{v['id']}/appStoreVersionLocalizations") or {"data": []}
    for loc in locs["data"]:
        locale = loc["attributes"]["locale"]
        key = "pt-BR" if locale.startswith("pt") else "en-US"
        if call("PATCH", f"/appStoreVersionLocalizations/{loc['id']}", {"data": {
                "type": "appStoreVersionLocalizations", "id": loc["id"],
                "attributes": {"whatsNew": notes(platform, key)}}}) is not None:
            print(f"   What's New set ({locale})")

if problems:
    print(f"\n{len(problems)} step(s) didn't go through; see the ⚠️ lines above.")
    sys.exit(1)
print(f"\nVersion {VERSION} is ready on all three platforms.")
