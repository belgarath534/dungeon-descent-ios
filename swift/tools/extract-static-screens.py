#!/usr/bin/env python3
"""Pulls the text screens (Help, Credits, What's New) out of www/index.html
into swift/App/DungeonDescent/statics.json so the Swift version shows the
same words. Run: python3 swift/tools/extract-static-screens.py
"""
import json
import os
import re


ROOT = os.path.join(os.path.dirname(__file__), "..", "..")

# Reuse the small HTML tree from extract-creation.py without running it.
src = open(os.path.join(os.path.dirname(__file__), "extract-creation.py"), encoding="utf-8").read()
helpers = src[src.index("class Node:"):src.index("start = SRC.index")]
SRC = open(os.path.join(ROOT, "www", "index.html"), encoding="utf-8").read()
ns = {"re": re, "HTMLParser": __import__("html.parser", fromlist=["HTMLParser"]).HTMLParser}
exec(helpers, ns)
Tree, squash = ns["Tree"], ns["squash"]


def screen(id_):
    start = SRC.index('<div id="screen-%s"' % id_)
    nxt = SRC.find('<div id="screen-', start + 10)
    t = Tree()
    t.feed(SRC[start:nxt if nxt != -1 else len(SRC)])
    return t.root


def find(node, cls):
    return node.find_all(lambda n: cls in n.classes)


def text(n):
    return squash(n.text())


# Help: tabs, each with entries of a title and a body.
help_root = screen("help")
intro = next((text(p) for p in help_root.find_all(lambda n: n.tag == "p")), "")
tabs = []
for b in help_root.find_all(lambda n: n.tag == "button" and n.attrs.get("id", "").startswith("help-tab-")):
    tid = b.attrs["id"][len("help-tab-"):]
    sec = help_root.find_all(lambda n: n.attrs.get("id") == "help-" + tid)
    entries = []
    if sec:
        for e in find(sec[0], "help-entry"):
            t = find(e, "help-title")
            body = find(e, "help-body")
            entries.append({"title": text(t[0]) if t else "", "body": " ".join(text(x) for x in body)})
    tabs.append({"id": tid, "label": text(b), "entries": entries})

# Credits: sections with names and roles.
cr = screen("credits")
sections = []
for s in find(cr, "credits-section"):
    title = find(s, "credits-section-title")
    lines = []
    for n in s.find_all(lambda n: any(c in n.classes for c in ("credits-name", "credits-role"))):
        lines.append({"kind": "name" if "credits-name" in n.classes else "role", "text": text(n)})
    sections.append({"title": text(title[0]) if title else "", "label": s.attrs.get("aria-label", ""), "lines": lines})
credits = {"title": text(find(cr, "credits-title")[0]), "sub": text(find(cr, "credits-sub")[0]), "sections": sections}

# What's New: one block per version.
wn = screen("whatsnew")
versions = []
for v in find(wn, "version-block"):
    num = find(v, "version-num")
    date = find(v, "version-date")
    changes = [text(li) for li in v.find_all(lambda n: n.tag == "li")]
    versions.append({"num": text(num[0]) if num else "", "date": text(date[0]) if date else "",
                     "label": v.attrs.get("aria-label", ""), "changes": changes})

out = {"help": {"intro": intro, "tabs": tabs}, "credits": credits, "whatsnew": versions}
dest = os.path.join(ROOT, "swift", "App", "DungeonDescent", "statics.json")
# The Apple versions have no reward codes (App Store guideline 3.1.1): the
# Shadow Realm opens by clearing the Shadow World, so the text says that.
APPLE_TEXT = [
    ("To access it go to Settings, tap Redeem Code, and type SHADOW.",
     "It opens once you clear the Shadow World, and then it is on the main menu."),
    ("new secret mode accessed via Settings → Redeem Code → type SHADOW.",
     "new secret mode that opens when you clear the Shadow World."),
    (" Type the number 4 in the Redeem Code box for a secret exclusive patriot minion only available during this event.", ""),
]
DROP_LINES = ["Fixed Redeem Code button missing", "Secret Console — Alt+F5"]

def apple(o):
    if isinstance(o, dict): return {k: apple(v) for k, v in o.items()}
    if isinstance(o, list): return [apple(v) for v in o if not (isinstance(v, str) and any(d in v for d in DROP_LINES))]
    if isinstance(o, str):
        for a, b in APPLE_TEXT: o = o.replace(a, b)
    return o

out = apple(out)

# Versions only the Apple apps have (the web version's notes stop at 11.8).
SWIFT_VERSIONS = [
    {"num": "v11.9 — Latest", "date": "The Together Update", "label": "Version 11.9", "changes": [
        "🐉 Daily World Boss — a new boss every day that every player fights together. 30,000 shared HP and 10 strikes each a day. If it falls, everyone who struck it gets 750 gold and 2 Soul Fragments. Find it on the main menu.",
        "📆 Weekly Ladder — the third tab in Challenges. One dungeon all week, one life, and a top 10 that starts over every Monday.",
        "🏆 Challenge a friend — Game Center leaderboards for Endless Descent, the Weekly Ladder and The Spire, with Game Center's Challenge button. In Challenges.",
        "🏁 Endless Descent rivals — on iPhone, the Lock Screen and Dynamic Island show the next player above your floor and who you just passed.",
        "⌚ Apple Watch complication — today's World Boss and the hours until the next one, right on your watch face.",
        "🗣 Siri and Shortcuts — \"Start Endless Descent\", \"How's my run\" and \"Use a potion\".",
        "🌙 Welcome back — after an hour or more away, your first character comes back with gold and Soul Fragments.",
        "❓ What just happened — in a run, a two-finger double-tap (or the VoiceOver action) reads the last few lines again.",
        "♿ Settings, Accessibility: short combat lines, and warning sounds when your HP drops low or an elite appears.",
        "🎧 My Tracks — play songs from your Apple Music library in place of the game music, as well as your own audio files.",
        "🇧🇷 Much more of the game is now in Portuguese: combat, loot, events, waves and spells.",
        "⏳ A loading screen at launch, a tutorial the first time you meet The Music Box, and your total playtime in the pause menu.",
        "🔧 Fixed: VoiceOver keeps up with The Spire's Auto Mode instead of reading floors from minutes ago.",
        "🔧 Fixed: the Lock Screen keeps moving in Endless Descent, even when you aren't signed in.",
        "🔧 Fixed: the game's music no longer starts on its own while the app is closed.",
    ]},
    {"num": "v11.8", "date": "The Festival Update", "label": "Version 11.8", "changes": ["🎉 Nine new events come to the dungeon, each with its own enemies, bonuses and twist. Check the Events screen in the menu to see when each one is on.", "🌼 Día de los Muertos (November 1–2) — a fallen hero from your Graveyard returns as a ghost and fights beside you. Earn Marigolds and spend them at 🌼 The Ofrenda.", "🇲🇽 Independencia de México (September 15–16) — the ¡El Grito! battle cry gives you +30% attack for 3 turns, once a fight.", "🎆 New Year (December 31–January 1) — double XP into the new year.", "🐉 Lunar New Year — three days that move with the moon. Enemies sometimes leave a 🧧 red envelope with gold or a Mystery Coin.", "🃏 Chaos Day (April 1) — every fight rolls a random twist.", "🌑 The Longest Night (December 21) — it is night all day, with every night bonus on.", "🌘 The Eclipse — one evening a month the sun goes dark, the same time for every player. Double gold, and much tougher enemies.", "🏮 Night Market — the first weekend of every month, the merchant comes far more often and everything is 25% off.", "🐾 Monster Migration — two days a month, enemies from the other dungeons wander into yours with all their abilities."]},
    {"num": "v11.7.3", "date": "The Swift Rebuild", "label": "Version 11.7.3", "changes": ["🍎 Dungeon Descent has been rebuilt from the ground up as a native iPhone app in Swift. It's faster, smoother and works better with VoiceOver, and your characters and progress come with you.", "🐛 Rebuilding every system found over 100 bugs in the old version, and every one is fixed: 105 skills that did nothing now work, spells finish what they start, subclasses, races, class traits, run modifiers, dungeon conditions and seasonal items all do what they say.", "🏚️ Enemies in The Hollow and the Abyssal Deep use their real abilities: the Bell Ringer, the Wall Crawler, the Door Warden, the Twin, the Pressure Beast, the Deep Stalker and more.", "📜 New: an opening quote for your class, an intro the first time you enter each dungeon, a boss preview before the floor 10 boss, and a class item in every floor shop.", "👑 New: clear all eight dungeons to see the True Ending.", "🏰 The Spire's bosses appear, the Gauntlet has its real last dungeon, the Siege can be won, and the Mine's enemies fight with their own moves.", "🔒 The tournament leaderboard no longer shows players' email addresses."]},
]
for v in out["whatsnew"]:
    v["num"] = v["num"].replace(" — Latest", "")
out["whatsnew"] = SWIFT_VERSIONS + out["whatsnew"]
json.dump(out, open(dest, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
print("help tabs", len(tabs), "entries", sum(len(t["entries"]) for t in tabs), "| credits sections", len(sections),
      "| versions", len(out["whatsnew"]), "->", os.path.relpath(dest, ROOT))
