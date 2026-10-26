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
json.dump(out, open(dest, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
print("help tabs", len(tabs), "entries", sum(len(t["entries"]) for t in tabs), "| credits sections", len(sections),
      "| versions", len(versions), "->", os.path.relpath(dest, ROOT))
