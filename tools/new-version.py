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
VERSION = os.environ.get("VERSION", "12.0")

WHATS_NEW = {
    "en-US": """New in 12.0, The Legends Update:
• Co-op Dungeon: fight through ten floors with up to three friends, on iPhone, Mac, Apple Vision Pro and the web together. Share a 4-letter room code.
• A new main menu with tabs along the bottom: Play, Modes, Multiplayer, More and Settings. Prefer the old list? Settings, Gameplay, Classic Menu.
• Hunting Grounds, remade: track a beast by sound. Listen for its call, read its tracks, sneak up, then ambush or trap it. Three bounties a day and five legends to hunt, narrated by Lewis, a new recorded narrator.
• Battle Pass: 50 tiers a season, earned by playing, never bought, with five new quests every Monday.
• Prestige: start a max-level character over for a permanent star, up to 10.
• Cloud sync: your whole save travels between your devices and the web.
• Audio Map: hear the whole floor as sounds around you. Best with headphones.
• Apple Watch: World Boss strikes, the Battle Pass, your daily reward, Quick Fight with the Digital Crown, wrist alerts, Siri and new complications.
• The whole game is now in Portuguese.
• Game Center is in the Multiplayer tab.""",
    "pt-BR": """Novidades da 12.0, A Atualização das Lendas:
• Masmorra Cooperativa: atravesse dez andares com até três amigos, no iPhone, Mac, Apple Vision Pro e na web juntos. Compartilhe um código de sala de 4 letras.
• Um novo menu principal com abas na parte de baixo: Jogar, Modos, Multijogador, Mais e Ajustes. Prefere a lista antiga? Ajustes, Jogabilidade, Menu Clássico.
• Campo de Caça, refeito: rastreie uma fera pelo som. Escute o chamado, leia as pegadas, chegue em silêncio e embosque ou arme uma armadilha. Três caçadas por dia e cinco lendas, narradas por Alex, um novo narrador gravado.
• Passe de Batalha: 50 níveis por temporada, ganhos jogando, nunca comprados, com cinco missões novas toda segunda.
• Prestígio: recomece um personagem no nível máximo em troca de uma estrela permanente, até 10.
• Sincronização na nuvem: seu salvamento inteiro viaja entre seus aparelhos e a web.
• Mapa Sonoro: ouça o andar inteiro como sons ao seu redor. Melhor com fones de ouvido.
• Apple Watch: golpes no Chefe Mundial, o Passe de Batalha, a recompensa diária, Luta Rápida com a Digital Crown, alertas no pulso, Siri e novas complicações.
• O jogo inteiro agora está em português.
• O Game Center está na aba Multijogador.""",
}
PROMO = {
    "en-US": "New in 12.0: play together. Co-op dungeons with friends on iPhone, Mac, Vision Pro and the web, a Battle Pass, and hunting by sound.",
    "pt-BR": "Novo na 12.0: jogue junto. Masmorras cooperativas com amigos no iPhone, Mac, Vision Pro e web, Passe de Batalha e caça pelo som.",
}
# The Mac and Vision Pro have no watch, Lock Screen or Apple Music picker.
SKIP = {
    "MAC_OS": ("Apple Watch",),
    "VISION_OS": ("Apple Watch",),
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
                "attributes": {"whatsNew": notes(platform, key), "promotionalText": PROMO[key]}}}) is not None:
            print(f"   What's New and promotional text set ({locale})")

if problems:
    print(f"\n{len(problems)} step(s) didn't go through; see the ⚠️ lines above.")
    sys.exit(1)
print(f"\nVersion {VERSION} is ready on all three platforms.")
