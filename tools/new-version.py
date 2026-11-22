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
VERSION = os.environ.get("VERSION", "12.0.2")
# Only these platforms (store-submit-ios: "IOS").
PLATFORMS = os.environ.get("PLATFORMS", "IOS MAC_OS VISION_OS").split()

WHATS_NEW_12_0 = {
    "en-US": """New in 12.0, The Legends Update:
• Co-op Dungeon: fight through ten floors with up to three friends, on iPhone, Mac, Apple Vision Pro and the web together. Share a 4-letter room code.
• A new main menu with tabs along the bottom: Play, Modes, Multiplayer, More and Settings. Prefer the old list? Settings, Gameplay, Classic Menu.
• Hunting Grounds, remade: track a beast by sound. Listen for its call, read its tracks, sneak up, then ambush or trap it. Three bounties a day and five legends to hunt, narrated by Lewis, a new recorded narrator.
• Lewis Voice Pack (iPhone and iPad): Lewis can read the whole game to you in place of VoiceOver's voice. A free download in Settings, Voice Pack; he speaks on your device, no internet needed after that. English only for now.
• Battle Pass: 50 tiers a season, earned by playing, never bought, with five new quests every Monday.
• Prestige: start a max-level character over for a permanent star, up to 10.
• Cloud sync: your whole save travels between your devices and the web.
• Twice the character slots: keep up to 10 characters.
• Audio Map: hear the whole floor as sounds around you. Best with headphones.
• Apple Watch: World Boss strikes, the Battle Pass, your daily reward, Quick Fight with the Digital Crown, wrist alerts, Siri and new complications.
• The whole game is now in Portuguese.
• Game Center is in the Multiplayer tab.
• Fixes: the VoiceOver rotor no longer jumps back to Actions in the dungeon, forged spirits show up when creating a character, and the Gauntlet Champion title is now given.""",
    "pt-BR": """Novidades da 12.0, A Atualização das Lendas:
• Masmorra Cooperativa: atravesse dez andares com até três amigos, no iPhone, Mac, Apple Vision Pro e na web juntos. Compartilhe um código de sala de 4 letras.
• Um novo menu principal com abas na parte de baixo: Jogar, Modos, Multijogador, Mais e Ajustes. Prefere a lista antiga? Ajustes, Jogabilidade, Menu Clássico.
• Campo de Caça, refeito: rastreie uma fera pelo som. Escute o chamado, leia as pegadas, chegue em silêncio e embosque ou arme uma armadilha. Três caçadas por dia e cinco lendas, narradas por Alex, um novo narrador gravado.
• Pacote de Voz Lewis (iPhone e iPad): Lewis pode ler o jogo inteiro para você no lugar da voz do VoiceOver. Download grátis em Ajustes, Pacote de Voz; ele fala no próprio aparelho, sem internet depois disso. Por enquanto só em inglês.
• Passe de Batalha: 50 níveis por temporada, ganhos jogando, nunca comprados, com cinco missões novas toda segunda.
• Prestígio: recomece um personagem no nível máximo em troca de uma estrela permanente, até 10.
• Sincronização na nuvem: seu salvamento inteiro viaja entre seus aparelhos e a web.
• O dobro de vagas de personagem: tenha até 10 personagens.
• Mapa Sonoro: ouça o andar inteiro como sons ao seu redor. Melhor com fones de ouvido.
• Apple Watch: golpes no Chefe Mundial, o Passe de Batalha, a recompensa diária, Luta Rápida com a Digital Crown, alertas no pulso, Siri e novas complicações.
• O jogo inteiro agora está em português.
• O Game Center está na aba Multijogador.
• Correções: o rotor do VoiceOver não volta mais para Ações na masmorra, espíritos forjados aparecem ao criar um personagem e o título Campeão do Desafio agora é concedido.""",
}
# 12.0.1: fixes only; What's New lists them.
WHATS_NEW_12_0_1 = {
    "en-US": """12.0.1:
• New in Endless Descent: stat points. Every level gained in a run gives a point to spend on +20 max HP, +2 attack or +1 defense, kept for every Endless run.
Fixes:
• Lewis now says numbers right: "twenty-one", "three thousand eighty-two", "forty percent" (he said "floor one" for floor 21, and "three eighty-two" for 3,082).
• Prestige no longer crashes the game. If it crashed for you, your character is safe: prestige again.
• Legacy characters now keep every level the moment they reach it, even if they die or leave the run.
• Co-op: VoiceOver no longer jumps around during a fight, and your action buttons stay on screen after you choose.
• VoiceOver no longer jumps to the top after pressing buttons at Home, in the Gun Workshop and Gun Shop, the Arcane Shop and the Command Center switch.
• VoiceOver keeps its place on the fight buttons, in the Mine, the Spire, the Siege and other modes' button grids, and on the merchant after you buy.
• Co-op: Play Again now pays your gold and Battle Pass progress for every run, not just the first.
• The merchant's night discount now shows the right "before" price (the daytime price with your run's modifiers).
• A run no longer crashes if a cloud save with fewer characters loads while you play.
• "Choose a save" no longer appears when you only play on one device.
• Easier to read: dim text and gold are brighter, and the Discord link is easier to tap.""",
    "pt-BR": """12.0.1:
• Novo na Descida Infinita: pontos de atributo. Cada nível ganho numa partida dá um ponto para gastar em +20 de HP máximo, +2 de ataque ou +1 de defesa, guardado para todas as partidas da Descida Infinita.
Correções:
• O Lewis agora fala os números certo: "twenty-one", "three thousand eighty-two" (ele dizia "floor one" no andar 21 e "three eighty-two" para 3.082).
• O Prestígio não trava mais o jogo. Se travou para você, seu personagem está a salvo: faça o Prestígio de novo.
• Personagens do Modo Legado agora guardam cada nível assim que o alcançam, mesmo se morrerem ou saírem da partida.
• Cooperativo: o VoiceOver não pula mais pela tela durante a luta, e seus botões de ação continuam na tela depois que você escolhe.
• O VoiceOver não volta mais para o topo depois de tocar em botões na Casa, na Oficina e na Loja de Armas, na Loja Arcana e na opção da Central de Comando.
• O VoiceOver não perde mais o lugar nos botões de luta, nas grades de botões da Mina, da Torre, do Cerco e de outros modos, e no mercador depois de comprar.
• Cooperativo: Jogar de Novo agora paga seu ouro e o progresso do Passe de Batalha em todas as partidas, não só na primeira.
• O desconto noturno do mercador agora mostra o preço "antes" certo (o preço do dia com os modificadores da sua partida).
• Uma partida não trava mais se um salvamento na nuvem com menos personagens carregar enquanto você joga.
• "Escolha um salvamento" não aparece mais quando você joga em um só aparelho.
• Mais fácil de ler: textos apagados e dourados estão mais claros, e o link do Discord é mais fácil de tocar.""",
}
# 12.0.2: two fixes after 12.0.1.
WHATS_NEW_12_0_2 = {
    "en-US": """12.0.2:
• Endless Descent now goes up to level 50 (it stopped at 10). Each level asks for more XP, and still gives HP, attack and a stat point.
• 3D Mode: VoiceOver is quick again. The 3D room isn't drawn while VoiceOver is on, which made VoiceOver wait seconds to move and speak; the spatial sound, Echo-Location and directions are all still there.""",
    "pt-BR": """12.0.2:
• A Descida Infinita agora vai até o nível 50 (parava no 10). Cada nível pede mais XP e continua dando HP, ataque e um ponto de atributo.
• Modo 3D: o VoiceOver está rápido de novo. A sala em 3D não é desenhada com o VoiceOver ligado, o que fazia o VoiceOver esperar segundos para mover e falar; o som espacial, a Ecolocalização e as direções continuam iguais.""",
}
# 12.0.1 never shipped, so 12.0.2's notes carry its fixes too.
WHATS_NEW_12_0_2 = {k: v + "\n" + WHATS_NEW_12_0_1[k].split("\n", 1)[1] for k, v in WHATS_NEW_12_0_2.items()}
WHATS_NEW = {"12.0.2": WHATS_NEW_12_0_2, "12.0.1": WHATS_NEW_12_0_1}.get(VERSION, WHATS_NEW_12_0)

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
for platform in PLATFORMS:
    found = call("GET", f"/apps/{app}/appStoreVersions",
                 params={"filter[platform]": platform, "filter[versionString]": VERSION})
    if found is None:
        continue
    # A version that was never released (taken out of review, or never sent)
    # is renamed instead: App Store Connect allows one at a time.
    unsent = None
    if not found["data"]:
        for o in (call("GET", f"/apps/{app}/appStoreVersions", params={"filter[platform]": platform, "limit": 5}) or {"data": []})["data"]:
            if (o["attributes"].get("appStoreState") or "") in ("PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED", "METADATA_REJECTED"):
                unsent = o
                break
    if found["data"]:
        v = found["data"][0]
        print(f"• {platform} {VERSION} is already there ({v['attributes'].get('appStoreState')})")
    elif unsent:
        old = unsent["attributes"].get("versionString")
        if call("PATCH", f"/appStoreVersions/{unsent['id']}", {"data": {"type": "appStoreVersions", "id": unsent["id"],
                "attributes": {"versionString": VERSION}}}) is None:
            continue
        v = unsent
        print(f"✅ {platform} {old} renamed to {VERSION}")
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
print(f"\nVersion {VERSION} is ready on {', '.join(PLATFORMS)}.")
