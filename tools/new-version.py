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
VERSION = os.environ.get("VERSION", "12.2")
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
# 12.0.2: what's new after 12.0.1.
WHATS_NEW_12_0_2 = {
    "en-US": """12.0.2:
• Endless Descent now goes up to level 50 (it stopped at 10). Each level asks for more XP, and still gives HP, attack and a stat point.
• 3D Mode: VoiceOver is quick again. The 3D room isn't drawn while VoiceOver is on, which made VoiceOver wait seconds to move and speak; the spatial sound, Echo-Location and directions are all still there.
• Legacy Mode now goes up to level 50 (it stopped at 25). Prestige still needs level 25.
• The Spire gives XP: every kill counts toward your level, and you can level up during a climb (+25 max HP, +2 attack), up to 50.
• Leveling past 10 takes the same XP in the dungeon as in Endless Descent.
• Later dungeons are harder: from Frosthold Abyss on, enemies and bosses have more health and hit harder, more in each dungeon after it.
• Level points stay where you spent them when your level carries over (Legacy, Continue Journey), and the Level Points button lets you spend new ones any time you're exploring.
• Selling to the merchant: the same items are one row with a count (10 elixirs were 10 rows).""",
    "pt-BR": """12.0.2:
• A Descida Infinita agora vai até o nível 50 (parava no 10). Cada nível pede mais XP e continua dando HP, ataque e um ponto de atributo.
• Modo 3D: o VoiceOver está rápido de novo. A sala em 3D não é desenhada com o VoiceOver ligado, o que fazia o VoiceOver esperar segundos para mover e falar; o som espacial, a Ecolocalização e as direções continuam iguais.
• O Modo Legado agora vai até o nível 50 (parava no 25). O Prestígio continua pedindo nível 25.
• A Torre dá XP: cada inimigo derrotado conta para o seu nível, e você pode subir de nível durante a escalada (+25 de HP máximo, +2 de ataque), até o 50.
• Subir depois do nível 10 pede o mesmo XP na masmorra e na Descida Infinita.
• As masmorras mais fundas estão mais difíceis: a partir do Abismo Glacial, inimigos e chefes têm mais vida e batem mais forte, e mais ainda em cada masmorra seguinte.
• Os pontos de nível continuam onde você os gastou quando o seu nível passa para a próxima partida (Legado, Continuar Jornada), e o botão Pontos de Nível deixa você gastar os novos a qualquer momento explorando.
• Vender ao mercador: itens iguais ficam numa linha só com a quantidade (10 elixires eram 10 linhas).""",
}
# 12.0.1 never shipped, so 12.0.2's notes carry its fixes too.
WHATS_NEW_12_0_2 = {k: v + "\n" + WHATS_NEW_12_0_1[k].split("\n", 1)[1] for k, v in WHATS_NEW_12_0_2.items()}
WHATS_NEW_12_1 = {
    "en-US": """New in 12.1:
• Raid Boss: invite up to three friends to fight one giant boss together. Win gold, XP, diamonds and raid gear.
• Co-op with your real character: your gear, level, prestige stars, skills, gun and potions come with you. Revive or protect a friend.
• Community Dungeons: build your own dungeon and play other players' dungeons.
• Friends: your Game Center friends who play, who's online, and an invite to your co-op room.
• Voice commands in fights: say attack, defend, a skill's name and more.
• Choose a Dungeon: after a win, go to any dungeon you've unlocked, normally or as New Game+.
• Four new enemies made for listening: The Liar, The Bell Choir, The Counting Thing and The Silent One.
• Insane Mode has its sanity bar, with The Distorted, The Sanity Drainer and the Insanity Potion.
• The Conductor: a rare hall where you move only while the music plays.
• A low HP heartbeat you can hear and feel.
• Events now cover the screen until you choose, and 3D Mode always tells you the way to a new room.
• Skill Book: reorder your skills. Holiday enemies use their own moves. Endless enemies from floor 20.
• Apple Watch: make your co-op moves from your wrist.
• High Contrast, Lewis's speed and Keep Up, and a two-finger scrub to go back.
• Many more fixes.""",
    "pt-BR": """Novo na 12.1:
• Chefe de Raide: convide até três amigos para enfrentar juntos um chefe gigante. Ganhe ouro, XP, diamantes e equipamento de raide.
• Cooperativo com o seu personagem de verdade: equipamento, nível, estrelas de prestígio, habilidades, arma e poções vão com você. Reviva ou proteja um amigo.
• Masmorras da Comunidade: crie a sua masmorra e jogue as dos outros jogadores.
• Amigos: seus amigos do Game Center que jogam, quem está online e um convite para a sua sala.
• Comandos de voz nas lutas: diga atacar, defender, o nome de uma habilidade e mais.
• Escolher uma Masmorra: depois de vencer, vá para qualquer masmorra desbloqueada, normal ou em Novo Jogo+.
• Quatro inimigos novos feitos para ouvir: O Mentiroso, O Coro de Sinos, A Coisa que Conta e O Silencioso.
• O Modo Insano tem sua barra de sanidade, com O Distorcido, O Drenador de Sanidade e a Poção da Insanidade.
• O Maestro: um salão raro onde você só anda enquanto a música toca.
• Um batimento cardíaco de HP baixo que você ouve e sente.
• Eventos agora cobrem a tela até você escolher, e o Modo 3D sempre indica o caminho para uma sala nova.
• Livro de Habilidades: reorganize suas habilidades. Inimigos de feriados usam seus golpes. Inimigos do Infinito a partir do andar 20.
• Apple Watch: faça suas jogadas do cooperativo pelo pulso.
• Alto Contraste, velocidade do Lewis e Acompanhar, e o gesto de dois dedos para voltar.
• Muitas outras correções.""",
}
WHATS_NEW_12_1_1 = {
    "en-US": """New in 12.1.1:
• The Magic Chamber: a rare, glowing room in any dungeon where a unicorn waits. Approach it and Starlight the Unicorn joins you as a minion. It fights beside you and heals you every round, and every time you find the chamber again it restores your HP and SP. Asked for by a player on our Discord.
""" + WHATS_NEW_12_1["en-US"],
    "pt-BR": """Novo na 12.1.1:
• A Câmara Mágica: uma sala rara e brilhante em qualquer masmorra, onde um unicórnio espera. Aproxime-se e Estrelinha, o Unicórnio, se junta a você como lacaio. Ele luta ao seu lado e te cura a cada rodada, e toda vez que você encontra a câmara de novo ela restaura seu HP e SP. Um pedido de um jogador no nosso Discord.
""" + WHATS_NEW_12_1["pt-BR"],
}
WHATS_NEW_12_2 = {
    "en-US": """New in 12.2:
• Guilds: join or start a guild of up to 20 players, with its own chat and a Guild Boss every week. Bring it down together for gold and Soul Fragments. In the Multiplayer tab.
• Co-op for five: bring up to four friends into a Co-op Dungeon or a Raid.
• The Mine goes deeper: new bosses at depths 75, 150, 200, 300 and 500, and from 600 one every 100 depths, forever.
• The Mountainbreaker: a legendary warhammer forged at the Blacksmith from five Heartstone Shards found deep in the Mine. Every third hit is a quake.
• Four new guns: the Harpoon Gun, the Flare Gun, the Blunderbuss and the Tesla Coil. Every gun now has its own sound.
• Two rare rooms: the Wishing Well and the Forgotten Music Room.
• My Enemies: rename, strengthen or delete the community enemies you made.
• Long lists like the inventory and the shop's selling now open as their own pages, and the Settings button appears only once.
• Balance, thanks to a player's report: bosses grow to match strong characters, prestige stars now add damage to every hit, and the Gambler's Spirit only bets the gold you earned on that floor.
• Weapons upgrade past level 10 at rising prices, and enemies grow with them. The Mystery Coin Shop has 8 new upgrades and Mastery ranks that never run out.
• Losing a normal dungeon run costs half the gold you carry. Keep your gold in your Home safe.
• Fixed: with an Apocalypse weapon, shield skills like Arcane Armor could be cast again and again for an endless shield. Shields now top up instead of stacking.
• Many more fixes.""",
    "pt-BR": """Novo na 12.2:
• Guildas: entre ou crie uma guilda de até 20 jogadores, com chat próprio e um Chefe da Guilda toda semana. Derrubem ele juntos e ganhem ouro e Fragmentos de Alma. Na aba Multijogador.
• Cooperativo para cinco: leve até quatro amigos para uma Masmorra Cooperativa ou um Raide.
• A Mina fica mais funda: novos chefes nas profundidades 75, 150, 200, 300 e 500, e a partir da 600 um a cada 100 de profundidade, para sempre.
• O Quebra-Montanhas: um martelo de guerra lendário forjado no Ferreiro com cinco Fragmentos do Coração da Pedra achados no fundo da Mina. A cada três golpes, um terremoto.
• Quatro armas de fogo novas: o Arpão, a Pistola Sinalizadora, o Bacamarte e a Bobina de Tesla. Cada arma agora tem o seu próprio som.
• Duas salas raras: o Poço dos Desejos e a Sala de Música Esquecida.
• Meus Inimigos: renomeie, fortaleça ou apague os inimigos da comunidade que você criou.
• Listas longas, como o inventário e a venda na loja, agora abrem em páginas próprias, e o botão de Configurações aparece só uma vez.
• Equilíbrio, graças ao relato de um jogador: os chefes crescem conforme a força do personagem, as estrelas de prestígio agora somam dano a cada golpe, e o Espírito do Apostador só aposta o ouro ganho naquele andar.
• As armas melhoram além do nível 10 por preços crescentes, e os inimigos crescem junto. A Loja de Moedas Misteriosas tem 8 melhorias novas e níveis de Maestria que nunca acabam.
• Perder uma partida normal custa metade do ouro que você carrega. Guarde seu ouro no cofre da sua Casa.
• Corrigido: com uma arma Apocalipse, habilidades de escudo como a Armadura Arcana podiam ser usadas sem parar para um escudo sem fim. Agora os escudos se recarregam em vez de se acumular.
• Muitas outras correções.""",
}
WHATS_NEW = {"12.2": WHATS_NEW_12_2, "12.1.1": WHATS_NEW_12_1_1, "12.1": WHATS_NEW_12_1, "12.0.2": WHATS_NEW_12_0_2, "12.0.1": WHATS_NEW_12_0_1}.get(VERSION, WHATS_NEW_12_0)

PROMO = {
    "en-US": "New in 12.2: Guilds with a weekly Guild Boss, co-op for five, a deeper Mine with a legendary hammer, and four new guns.",
    "pt-BR": "Novo na 12.2: Guildas com um Chefe semanal, cooperativo para cinco, uma Mina mais funda com um martelo lendário e quatro armas novas.",
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
