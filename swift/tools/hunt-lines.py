#!/usr/bin/env python3
"""Every line the Hunting Grounds narrator says, in English and Portuguese.

Writes swift/DungeonCore/Sources/DungeonCore/Resources/hunt-lines.json
({id: {"en": ..., "pt": ...}}). The game shows the text and plays
www/audio/hunt/<lang>/<id>.mp3, made from these lines with Kokoro
(tools/hunt-voice.py: Lewis in English, Alex in Portuguese).
Run it again after changing a line, then make the voice again.
"""
import json, os

L = {}
def line(i, en, pt): L[i] = {"en": en, "pt": pt}

# ── The beasts (same ids as Tracking.prey in DungeonCore) ──
PREY = {
  # id: (English name, Portuguese name, en trophy, pt trophy, gold)
  "wolf":     ("Grey Wolf", "Lobo Cinzento", "a Wolf Pelt", "uma Pele de Lobo", 60),
  "boar":     ("Wild Boar", "Javali Selvagem", "a Boar Tusk", "uma Presa de Javali", 55),
  "owl":      ("Shadow Owl", "Coruja das Sombras", "a Night Feather", "uma Pena Noturna", 65),
  "serpent":  ("Vine Serpent", "Serpente das Vinhas", "a Serpent Scale", "uma Escama de Serpente", 70),
  "stalker":  ("Night Stalker", "Espreitador Noturno", "a Stalker Fang", "uma Presa de Espreitador", 100),
  "bear":     ("Cave Bear", "Urso das Cavernas", "a Bear Claw", "uma Garra de Urso", 110),
  "greyfang": ("The Grey Fang", "o Presa Cinzenta", "the Grey Fang's Crown", "a Coroa do Presa Cinzenta", 500),
  "stag":     ("The White Stag", "o Cervo Branco", "a White Antler", "um Chifre Branco", 750),
  "swampking":("The Swamp King", "o Rei do Pântano", "the Swamp King's Eye", "o Olho do Rei do Pântano", 1000),
  "nightmother":("The Night Mother", "a Mãe da Noite", "a Moonlit Wing", "uma Asa de Luar", 1500),
  "forest":   ("The Forest Itself", "a Própria Floresta", "the Heartwood", "o Cerne da Floresta", 3000),
}
INTRO = {
  "wolf": ("You're tracking a Grey Wolf. Listen for its howl.", "Você está rastreando um Lobo Cinzento. Escute o uivo dele."),
  "boar": ("You're tracking a Wild Boar. Listen for its snorting.", "Você está rastreando um Javali Selvagem. Escute o bufar dele."),
  "owl": ("You're tracking a Shadow Owl. Listen for its wings.", "Você está rastreando uma Coruja das Sombras. Escute as asas dela."),
  "serpent": ("You're tracking a Vine Serpent. Listen for its hiss.", "Você está rastreando uma Serpente das Vinhas. Escute o sibilo dela."),
  "stalker": ("You're tracking a Night Stalker. Listen for its growl. Careful. It hunts back.", "Você está rastreando um Espreitador Noturno. Escute o rosnado dele. Cuidado. Ele caça de volta."),
  "bear": ("You're tracking a Cave Bear. Listen for its growl. Careful. If it hears you, it charges.", "Você está rastreando um Urso das Cavernas. Escute o rosnado dele. Cuidado. Se ele ouvir você, ele avança."),
  "greyfang": ("A legend walks these woods. The Grey Fang, king of wolves. Listen for his howl.", "Uma lenda anda por esta mata. O Presa Cinzenta, rei dos lobos. Escute o uivo dele."),
  "stag": ("A legend walks these woods. The White Stag. Nobody has ever caught it. Listen for its breath.", "Uma lenda anda por esta mata. O Cervo Branco. Ninguém nunca o pegou. Escute o fôlego dele."),
  "swampking": ("A legend waits in the marsh. The Swamp King. Listen for his hiss.", "Uma lenda espera no pântano. O Rei do Pântano. Escute o sibilo dele."),
  "nightmother": ("A legend circles above the trees. The Night Mother. Listen for her wings.", "Uma lenda voa sobre as árvores. A Mãe da Noite. Escute as asas dela."),
  "forest": ("The trees are moving. You are not hunting the forest. The forest is hunting you. Listen.", "As árvores estão se mexendo. Você não está caçando a floresta. A floresta está caçando você. Escute."),
}
for k, (en, pt) in INTRO.items(): line(f"intro_{k}", en, pt)
FEMININE = {"owl", "serpent"}
cap = lambda s: s[0].upper() + s[1:]
for k, (n, npt, tr, trpt, g) in PREY.items():
    legend = n.startswith("The ")
    a_en, the_en = ("", "") if legend else ("A ", "The ")
    a_pt, the_pt = ("", "") if legend else (("Uma ", "A ") if k in FEMININE else ("Um ", "O "))
    line(f"found_{k}", f"There. {a_en}{n}. It hasn't seen you yet.", f"Ali. {a_pt}{cap(npt) if legend else npt}. Ainda não viu você.")
    line(f"win_{k}", f"{the_en}{n} falls. You earn {g} gold and {tr}.", f"{the_pt}{cap(npt) if legend else npt} cai. Você ganha {g} de ouro e {trpt}.")

# ── Listening: the call, where it comes from, how far ──
CALLS = {
  "howl": ("A howl", "Um uivo"), "snort": ("Snorting", "Um bufar"), "wings": ("Wings beating", "Asas batendo"),
  "hiss": ("A hiss", "Um sibilo"), "growl": ("A growl", "Um rosnado"),
}
DIRS = {
  "north": ("ahead of you", "à sua frente"), "northeast": ("ahead and to your right", "à frente, à direita"),
  "east": ("to your right", "à sua direita"), "southeast": ("behind you, to the right", "atrás de você, à direita"),
  "south": ("behind you", "atrás de você"), "southwest": ("behind you, to the left", "atrás de você, à esquerda"),
  "west": ("to your left", "à sua esquerda"), "northwest": ("ahead and to your left", "à frente, à esquerda"),
}
COMPASS = {"north": ("north", "norte"), "northeast": ("north-east", "nordeste"), "east": ("east", "leste"),
           "southeast": ("south-east", "sudeste"), "south": ("south", "sul"), "southwest": ("south-west", "sudoeste"),
           "west": ("west", "oeste"), "northwest": ("north-west", "noroeste")}
DIST = {"close": ("Very close.", "Bem perto."), "near": ("Not far.", "Não muito longe."), "far": ("Far away.", "Bem longe.")}
for c, (cen, cpt) in CALLS.items():
    for d, (den, dpt) in DIRS.items():
        for k, (ken, kpt) in DIST.items():
            line(f"hear_{c}_{d}_{k}", f"{cen}, {den}. {COMPASS[d][0].capitalize()}. {ken}",
                 f"{cpt}, {dpt}. {COMPASS[d][1].capitalize()}. {kpt}")
line("hear_nothing", "You listen. Nothing but the wind.", "Você escuta. Nada além do vento.")

# ── Tracks ──
for d, (en, pt) in COMPASS.items():
    line(f"tracks_{d}_fresh", f"Fresh tracks in the mud, heading {en}.", f"Pegadas frescas na lama, indo para o {pt}.")
    line(f"tracks_{d}_old", f"Old tracks, heading {en}. It passed here a while ago.", f"Pegadas antigas, indo para o {pt}. Passou por aqui faz um tempo.")
line("tracks_none", "You search the ground. No tracks here.", "Você procura no chão. Nenhuma pegada aqui.")

# ── Moving ──
for d, (en, pt) in COMPASS.items():
    if "-" in en: continue
    line(f"walk_{d}", f"You walk {en}.", f"Você anda para o {pt}.")
    line(f"sneak_{d}", f"You creep {en}, quietly.", f"Você avança para o {pt}, em silêncio.")
line("tree", "Thick trees block the way. Try another direction.", "Árvores grossas bloqueiam o caminho. Tente outra direção.")

# ── It notices you ──
line("heard_flee", "It heard you. It's running away.", "Ele ouviu você. Está fugindo.")
line("heard_charge", "It heard you, and it's coming for you!", "Ele ouviu você, e está vindo atrás de você!")
line("noise_warn", "Your footsteps are loud. Try sneaking.", "Seus passos estão altos. Tente avançar em silêncio.")
line("cold", "The trail goes cold. The beast is gone. The hunt is over.", "O rastro esfriou. A fera sumiu. A caçada acabou.")

# ── Found it ──
line("ambush", "You strike from the shadows. A perfect ambush!", "Você ataca das sombras. Uma emboscada perfeita!")
line("ambush_seen", "It turns just in time. No surprise now.", "Ele se vira bem a tempo. Nada de surpresa agora.")
line("trap_ok", "The trap snaps shut. It's stuck!", "A armadilha fecha. Ele está preso!")
line("trap_fail", "It sees the trap and slips away.", "Ele vê a armadilha e escapa.")
line("fight", "You step out and face it.", "Você sai do esconderijo e o enfrenta.")

# ── Fighting ──
line("hit", "You hit it.", "Você acerta.")
line("hit_hard", "A crushing blow!", "Um golpe esmagador!")
line("miss", "You swing and miss.", "Você golpeia e erra.")
line("defend", "You raise your guard and strike back.", "Você se protege e contra-ataca.")
line("bandage", "You bind your wounds.", "Você enfaixa suas feridas.")
line("no_bandage", "No bandages left.", "Sem ataduras.")
line("its_hit", "It hits you.", "Ele acerta você.")
line("its_hit_hard", "It tears into you!", "Ele dilacera você!")
line("its_stuck", "It's still stuck in the trap.", "Ele continua preso na armadilha.")
line("blocked", "You block most of it.", "Você bloqueia quase tudo.")
line("hurt", "You're hurt.", "Você está ferido.")
line("badly_hurt", "You're badly hurt. Bandage up or finish it fast.", "Você está muito ferido. Enfaixe-se ou acabe logo com isso.")
line("prey_weak", "It's weakening.", "Ele está enfraquecendo.")
line("prey_dying", "It's almost finished.", "Ele está quase no fim.")
line("legend_flee", "Wounded, the legend breaks away and vanishes into the trees. Track it again.", "Ferida, a lenda escapa e some entre as árvores. Rastreie-a de novo.")
line("lost", "You fall. The hunters carry you home. No reward this time.", "Você cai. Os caçadores levam você para casa. Sem recompensa desta vez.")
line("bounty_done", "Bounty complete. The reward is doubled!", "Recompensa da caçada cumprida. O prêmio é dobrado!")
line("legend_done", "A legend falls. The forest will remember your name.", "Uma lenda cai. A floresta vai lembrar o seu nome.")
line("rank_up", "Your bounty rank rises.", "Seu nível de caçador sobe.")

# ── The relaxing auto-hunt (Brian's old lines) ──
OLD = {
 "enter": [("The forest swallows you whole. Something watches from the dark.", "A floresta engole você por inteiro. Algo observa do escuro."),
           ("Leaves crunch beneath your feet. The hunt begins.", "Folhas estalam sob seus pés. A caçada começa."),
           ("The trees close in. You are not alone here.", "As árvores se fecham. Você não está sozinho aqui.")],
 "enemy": [("Something emerges from the shadows.", "Algo surge das sombras."), ("A creature blocks your path.", "Uma criatura bloqueia seu caminho."),
           ("You are not alone. Something approaches.", "Você não está sozinho. Algo se aproxima."), ("The undergrowth stirs. An enemy reveals itself.", "A vegetação se mexe. Um inimigo se revela.")],
 "kill": [("The creature falls. The forest grows quiet.", "A criatura cai. A floresta fica em silêncio."), ("Another enemy defeated. Your blade runs dark.", "Mais um inimigo derrotado. Sua lâmina escurece."),
          ("It is done. You press deeper into the forest.", "Está feito. Você avança mais fundo na floresta."), ("The hunt continues. Another falls before you.", "A caçada continua. Mais um cai diante de você.")],
 "item": [("Something catches your eye in the dirt.", "Algo chama sua atenção na terra."), ("A glint in the darkness. You reach down.", "Um brilho no escuro. Você se abaixa."),
          ("Among the fallen leaves, you find something useful.", "Entre as folhas caídas, você encontra algo útil.")],
 "hurt": [("You take a wound. Stay focused.", "Você se fere. Mantenha o foco."), ("The enemy draws blood. Keep moving.", "O inimigo tira sangue. Continue andando."),
          ("That one hurt. You press on regardless.", "Essa doeu. Você segue mesmo assim.")],
 "lowHp": [("Your wounds are severe. The forest senses weakness.", "Seus ferimentos são graves. A floresta sente a fraqueza."),
           ("You are bleeding. The darkness grows bolder.", "Você está sangrando. A escuridão fica mais ousada."),
           ("Critical condition. One more hit could end this hunt.", "Estado crítico. Mais um golpe pode acabar com esta caçada.")],
 "rest": [("A moment of stillness. You catch your breath.", "Um momento de calma. Você recupera o fôlego."), ("The forest is quiet for now.", "A floresta está quieta por enquanto."),
          ("Nothing stirs. You recover slightly.", "Nada se mexe. Você se recupera um pouco.")],
 "return": [("You emerge from the forest. The hunt is over.", "Você sai da floresta. A caçada acabou."), ("Daylight returns. You carry your spoils home.", "A luz do dia volta. Você leva seus espólios para casa."),
            ("The forest releases you. For now.", "A floresta liberta você. Por enquanto.")],
}
for k, lines in OLD.items():
    for i, (en, pt) in enumerate(lines): line(f"auto_{k}_{i}", en, pt)
line("auto_fallen", "Your hunter has fallen. The forest claims another. The hunt is over.", "Seu caçador caiu. A floresta leva mais um. A caçada acabou.")
for n in (10, 25, 50): line(f"auto_kills_{n}", f"Remarkable. {n} enemies have fallen before you.", f"Impressionante. {n} inimigos caíram diante de você.")
line("auto_coin", "An ancient coin catches the light. Worth 50 gold.", "Uma moeda antiga reflete a luz. Vale 50 de ouro.")
FINDS = {"Iron Scrap": "Sucata de Ferro", "Shadow Essence": "Essência Sombria", "Forest Herb": "Erva da Floresta", "Bone Fragment": "Fragmento de Osso",
         "Void Crystal": "Cristal do Vazio", "Hunters Rune": "Runa do Caçador", "Dark Pelt": "Pele Sombria"}
for en, pt in FINDS.items():
    line("find_" + en.lower().replace(" ", "_"), f"{en}.", f"{pt}.")
line("find_rare", "Something rare.", "Algo raro.")

out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "DungeonCore", "Sources", "DungeonCore", "Resources", "hunt-lines.json")
json.dump(L, open(out, "w", encoding="utf-8"), ensure_ascii=False, indent=0, sort_keys=True)
print(len(L), "lines ->", os.path.relpath(out))
