#!/usr/bin/env python3
"""Pulls the character creation screen (#screen-creation) out of
www/index.html into swift/App/DungeonDescent/creation.json, so the Swift
"Forge Your Legend" shows the web version's exact cards and text.

Each step keeps its heading, title and description; each card keeps its
data key, VoiceOver label, whether it's disabled, and its visible text
pieces with their CSS class. Run: python3 swift/tools/extract-creation.py
"""
import html
import json
import os
import re
from html.parser import HTMLParser

ROOT = os.path.join(os.path.dirname(__file__), "..", "..")
SRC = open(os.path.join(ROOT, "www", "index.html"), encoding="utf-8").read()


class Node:
    def __init__(self, tag, attrs, parent):
        self.tag, self.attrs, self.parent, self.children = tag, dict(attrs), parent, []

    def text(self):
        out = []
        for c in self.children:
            out.append(c if isinstance(c, str) else c.text())
        return "".join(out)

    def find_all(self, pred):
        found = []
        for c in self.children:
            if isinstance(c, Node):
                if pred(c):
                    found.append(c)
                found.extend(c.find_all(pred))
        return found

    @property
    def classes(self):
        return self.attrs.get("class", "").split()


VOID = {"br", "img", "input", "meta", "link", "hr"}


class Tree(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.root = Node("root", [], None)
        self.cur = self.root

    def handle_starttag(self, tag, attrs):
        n = Node(tag, attrs, self.cur)
        self.cur.children.append(n)
        if tag not in VOID:
            self.cur = n

    def handle_endtag(self, tag):
        n = self.cur
        while n is not None and n.tag != tag:
            n = n.parent
        if n is not None and n.parent is not None:
            self.cur = n.parent

    def handle_data(self, data):
        self.cur.children.append(data)


def squash(s):
    return re.sub(r"\s+", " ", s).strip()


def parts(node):
    """Visible text pieces of a card, in order, with the class (or a style hint)."""
    out = []

    def walk(n):
        for c in n.children:
            if isinstance(c, str):
                t = squash(c)
                if t:
                    cls = n.classes[0] if n.classes else ""
                    hidden = n.attrs.get("aria-hidden") == "true"
                    style = n.attrs.get("style", "")
                    color = re.search(r"(?:^|;)\s*color:\s*([^;]+)", style)
                    out.append({"cls": cls, "text": t, "hidden": hidden,
                                "color": color.group(1).strip() if color else ""})
            else:
                walk(c)

    walk(node)
    # Merge runs of text inside the same element.
    merged = []
    for p in out:
        if merged and merged[-1]["cls"] == p["cls"] and p["cls"] and merged[-1]["hidden"] == p["hidden"] \
                and p["cls"] not in ("stat-pip",):
            merged[-1]["text"] += " " + p["text"]
        else:
            merged.append(p)
    return merged


start = SRC.index('<div id="screen-creation"')
end = SRC.index('<div id="screen-dungeon"')
tree = Tree()
tree.feed(SRC[start:end])

steps = []
for sec in tree.root.find_all(lambda n: n.tag == "section" and n.attrs.get("id", "").startswith("cp-")):
    num = int(sec.attrs["id"][3:])
    def one(cls):
        f = sec.find_all(lambda n: cls in n.classes)
        return squash(f[0].text()) if f else ""
    cards = []
    for c in sec.find_all(lambda n: n.attrs.get("role") == "radio"):
        key = next((v for k, v in c.attrs.items() if k.startswith("data-") and k not in ("data-lang", "data-pt")), None)
        cards.append({
            "id": c.attrs.get("id", ""),
            "kind": c.classes[0] if c.classes else "",
            "key": key or "",
            "label": html.unescape(c.attrs.get("aria-label", "")),
            "disabled": "disabled" in c.attrs,
            "parts": parts(c),
        })
    extras = []
    for d in sec.find_all(lambda n: n.tag in ("div", "p") and not n.classes and n.attrs.get("role") not in ("radio", "slider")
                          and not n.find_all(lambda m: m.attrs.get("role") == "radio" or m.tag in ("button", "input"))
                          and n.parent is not None and not any(a.attrs.get("role") == "radio" for a in [n.parent, n.parent.parent] if a is not None)):
        t = squash(d.text())
        if t:
            extras.append({"id": d.attrs.get("id", ""), "text": t})
    steps.append({"step": num, "heading": one("step-heading"), "title": one("step-title"),
                  "desc": one("step-desc"), "cards": cards, "extras": extras})


def js_array(name):
    m = re.search(r"var " + name + r"\s*=\s*\[(.*?)\];", SRC, re.S)
    return re.findall(r"'([^']*)'", m.group(1)) if m else []


def js_object(name):
    m = re.search(r"var " + name + r"\s*=\s*\{(.*?)\};", SRC, re.S)
    if not m:
        return {}
    return {(a or b): c for a, b, c in re.findall(r"(?:'([^']+)'|(\w+))\s*:\s*'([^']*)'", m.group(1))}


sliders = {
    "class": {"order": js_array("_CLASSES"), "descs": js_object("_clsDescs")},
    "race": {"order": js_array("_RACES"), "descs": js_object("_raceDescs")},
    "prof": {"order": js_array("_PROFS"), "descs": js_object("_profDescs")},
}
names = {"prefixes": js_array("_NAME_PREFIXES"), "mids": js_array("_NAME_MIDS"), "suffixes": js_array("_NAME_SUFFIXES")}



def js_records(name, fields):
    """The simple string/number fields of each object in a JS array literal."""
    i = SRC.index("var " + name + " = [")
    depth, j = 0, SRC.index("[", i)
    for k in range(j, len(SRC)):
        if SRC[k] == "[":
            depth += 1
        elif SRC[k] == "]":
            depth -= 1
            if depth == 0:
                body = SRC[j + 1:k]
                break
    recs = []
    for chunk in re.split(r"\n\s*\{\s*id\s*:", body)[1:]:
        chunk = "id:" + chunk
        r = {}
        for f in fields:
            m = re.search(r"(?<![\w])" + f + r"\s*:\s*(?:'((?:[^'\\]|\\.)*)'|\"([^\"]*)\"|(-?[\d.]+))", chunk)
            if m:
                v = m.group(1) if m.group(1) is not None else m.group(2) if m.group(2) is not None else float(m.group(3))
                r[f] = v.replace("\\'", "'") if isinstance(v, str) else v
        recs.append(r)
    return recs


spirit_fields = ["id", "name", "icon", "rarity", "ability", "desc"]
spirits = {"starter": js_records("STARTER_SPIRITS", spirit_fields),
           "rare": js_records("RARE_SPIRITS", spirit_fields),
           "elite": js_records("ELITE_SPIRITS", spirit_fields)}
backstories = js_records("BACKSTORIES", ["id", "name", "bonus", "bonusKey", "bonusVal", "desc", "journal"])
stat_legend = [squash(html.unescape(re.sub(r"<[^>]+>", "", d))) for d in
               re.findall(r"<div[^>]*>(.*?)</div>", SRC[SRC.index('id="stat-legend"'):SRC.index('id="stat-legend"') + 3000])][:7]

# The guide's portrait on step 11.
import base64
cp11 = SRC[SRC.index('id="cp-11"'):]
m = re.search(r'<img src="data:image/(\w+);base64,([^"]+)"', cp11)
if m:
    asset = os.path.join(ROOT, "swift", "App", "DungeonDescent", "Assets.xcassets", "GuidePortrait.imageset")
    os.makedirs(asset, exist_ok=True)
    fn = "guide." + ("jpg" if m.group(1) == "jpeg" else m.group(1))
    open(os.path.join(asset, fn), "wb").write(base64.b64decode(m.group(2)))
    json.dump({"images": [{"filename": fn, "idiom": "universal"}], "info": {"author": "xcode", "version": 1}},
              open(os.path.join(asset, "Contents.json"), "w"))

out = {"steps": sorted(steps, key=lambda s: s["step"]), "sliders": sliders, "names": names,
       "spirits": spirits, "backstories": backstories, "statLegend": stat_legend}
dest = os.path.join(ROOT, "swift", "App", "DungeonDescent", "creation.json")
with open(dest, "w", encoding="utf-8") as f:
    json.dump(out, f, ensure_ascii=False, indent=1)
print("steps", len(steps), "cards", sum(len(s["cards"]) for s in steps), "->", dest)
