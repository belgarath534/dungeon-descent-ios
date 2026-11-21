#!/usr/bin/env python3
"""How much of the Swift version is in Portuguese.

Reads every Swift file in the app and DungeonCore, finds the text a player
can see or hear, and checks it the way the game itself would:

  • A label written straight into Text(...), Button(...), Label(...) or
    .accessibilityLabel(...) is looked up by SwiftUI in Localizable.xcstrings.
    One with a value inside it (Text("Floor \\(n)")) needs a format key
    ("Floor %lld") that the catalog doesn't have, so it stays in English.
  • Everything else (announcements, combat lines, menu text built in code)
    goes through Language.t: an exact match in the catalog, then the
    Portuguese patterns in Language.swift, then sentence by sentence.

Prints the percentage and writes the missing text to pt-missing.txt.
  python3 swift/tools/pt-coverage.py            the report
  python3 swift/tools/pt-coverage.py --list     and every missing line
"""
import json, os, re, sys

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
APP = os.path.join(ROOT, "App", "DungeonDescent")
CORE = os.path.join(ROOT, "DungeonCore", "Sources", "DungeonCore")

catalog = json.load(open(os.path.join(APP, "Localizable.xcstrings")))["strings"]
translated = {k for k, v in catalog.items() if "pt-BR" in v.get("localizations", {})}

# The patterns, compiled like Patterns.compiled in Language.swift.
lang = open(os.path.join(APP, "Language.swift"), encoding="utf-8").read()
pat_src = re.findall(r'^\s*\("((?:[^"\\]|\\.)*)", "(?:[^"\\]|\\.)*"\),?\s*$', lang, re.M)
def unescape(s): return s.replace('\\"', '"').replace("\\\\", "\\")
patterns = []
for en in pat_src:
    en = unescape(en)
    rx = re.escape(en)
    n = 0
    while True:
        token = re.escape("{%d}" % n)
        if token not in rx: break
        rx = rx.replace(token, "(.*?)", 1)
        n += 1
    try: patterns.append(re.compile("^" + rx + "$", re.S))
    except re.error: pass

def exact(s): return s in translated
def pattern(s): return any(p.match(s) for p in patterns)

def sentences(s):
    out, cur = [], []
    for w in s.split(" "):
        cur.append(w)
        if w and w[-1] in ".!?":
            out.append(" ".join(cur)); cur = []
    if cur: out.append(" ".join(cur))
    return [x for x in out if x]

def through_language_t(s):
    """Whether Language.t would give Portuguese for every part of s."""
    if exact(s): return True
    core = s.strip()
    if not core or not words(core): return True
    if core != s: return through_language_t(core)
    if "\n" in s: return all(through_language_t(l) for l in s.split("\n"))
    if pattern(s): return True
    parts = sentences(s)
    if len(parts) <= 1:
        for sep in (": ", " — "):
            if sep in s:
                head, tail = s.split(sep, 1)
                if exact(head + sep.strip()): return through_language_t(tail)
        return False
    return all(exact(p) or pattern(p) or not words(p) for p in parts)

def words(s): return re.findall(r"[A-Za-z]{2,}", re.sub(r"\{\d+\}|◊", " ", s))

# ── Reading the Swift ──
def literals(src):
    """(start index, text with interpolations kept as \\(...)) for each literal."""
    out, i, n = [], 0, len(src)
    while i < n:
        c = src[i]
        if c == "/" and src.startswith("//", i):
            j = src.find("\n", i); i = n if j < 0 else j; continue
        if c == "/" and src.startswith("/*", i):
            j = src.find("*/", i); i = n if j < 0 else j + 2; continue
        if c == '"':
            if src.startswith('"""', i):
                j = src.find('"""', i + 3); i = n if j < 0 else j + 3; continue
            j, buf, depth = i + 1, "", 0
            while j < n:
                ch = src[j]
                if depth == 0 and ch == "\\" and j + 1 < n and src[j + 1] == "(":
                    depth = 1; buf += "\\("; j += 2; continue
                if depth > 0:
                    if ch == "(": depth += 1
                    elif ch == ")": depth -= 1
                    elif ch == '"':
                        # a literal inside an interpolation: skip it
                        k = j + 1
                        while k < n and src[k] != '"':
                            k += 2 if src[k] == "\\" else 1
                        buf += src[j:k + 1]; j = k + 1; continue
                    buf += ch; j += 1; continue
                if ch == "\\": buf += src[j:j + 2]; j += 2; continue
                if ch == '"' or ch == "\n": break
                buf += ch; j += 1
            out.append((i, buf)); i = j + 1; continue
        i += 1
    return out

UI_CALL = re.compile(r'(?:\bText|\bButton|\bLabel|\bToggle|\.accessibilityLabel|\.accessibilityHint|\.navigationTitle|\bSection)\(\s*$')
SKIP_LINE = re.compile(r'\b(print|debugPrint|NSLog|fatalError|assert|precondition|Logger|os_log)\(|getItem\(|setItem\(|removeItem\(|forKey:|UserDefaults|systemImage:|Image\(|Sound\.(sfx|track|ambient)\(|\.child\(|collection\(|document\(|reference\(withPath|URL\(string|forResource|NotificationCenter|identifier:|\bcase\s+"|kind:\s*"|rawValue|\bid:\s*"|\.tag\(|beginBackgroundTask\(')
SKIP_TEXT = re.compile(r'^(dd_|swift_|sfx-|music-|ambient-|http|com\.|tournament|worldboss-|weekly-|afk-rivals|DD_|DD-|DD2-|DD[A-Z]|[a-z]+[A-Z][A-Za-z0-9]*$|[a-z_]+$|%|#|--|\^'
                       r'|[a-z0-9]+(-[a-z0-9]+)+-?(◊)?$|[A-Za-z]+/[a-z0-9-]+$|[A-Za-z◊/]+/[a-z]+$'
                       r'|[a-z0-9.-]+\.(mp3|wav|json|com|be|org|fill|circle|vial|square)$'
                       r'|[A-Z][a-z]+[A-Z][A-Za-z]+$|(Cinzel|Crimson)[A-Za-z-]*$|[IVXL]+$|[A-Z]{20,}|[EMyd ]+$|MMMM d|Bearer|Authorization$|Content-Type$|POST$'
                       r'|CFBundle|S◊[A-Z]|[\w.-]+@[\w.-]+$|[A-Za-z0-9]{24,}$)')

def interpolations_to_x(s):
    out, i = "", 0
    while i < len(s):
        if s.startswith("\\(", i):
            d, i = 1, i + 2
            while i < len(s) and d:
                if s[i] == "(": d += 1
                elif s[i] == ")": d -= 1
                i += 1
            out += "◊"
        else:
            out += s[i]; i += 1
    return out.replace('\\"', '"').replace("\\n", "\n")

# Names, keys and the moderation report (which goes to the developer, in English).
NOT_SHOWN = {"yyyy-MM-dd", "Gerald", "Mr. Bones Jr.", "Mira", "dd.filestore", "phase4Reached", "Chat username◊"}

def visible(t):
    if t.strip() in NOT_SHOWN or t.startswith("REPORTED ◊"): return False
    t = t.strip()
    if SKIP_TEXT.match(t): return False
    w = words(t)
    if not w: return False
    if len(w) == 1 and " " not in t.strip(): return t[:1].isupper() and len(t) > 2
    return True

results = {"ui": [0, []], "ui_value": [0, []], "code": [0, []]}
seen = set()
files = [os.path.join(d, f) for d in (APP, CORE) for f in sorted(os.listdir(d)) if f.endswith(".swift")]
for path in files:
    name = os.path.basename(path)
    if name in ("Language.swift",): continue
    commands = name.startswith("CommandCenter")
    src = open(path, encoding="utf-8").read()
    for start, raw in literals(src):
        line_start = src.rfind("\n", 0, start) + 1
        line = src[line_start:src.find("\n", start)]
        if SKIP_LINE.search(line): continue
        text = interpolations_to_x(raw)
        if not visible(text): continue
        if commands and text == text.lower(): continue
        before = src[max(0, start - 60):start]
        is_ui = bool(UI_CALL.search(before)) and "verbatim:" not in before[-12:]
        # "…" as String, or more code after it: a String, so Language.t.
        after = src[start + 2 + len(raw):start + 14 + len(raw)].lstrip()
        if is_ui and (after.startswith("as String") or (after and after[0] not in ",)")):
            is_ui = False
        has_value = "\\(" in raw
        key = (is_ui, has_value, text)
        if key in seen: continue
        seen.add(key)
        if is_ui and not has_value:
            cat, ok = "ui", exact(text) or through_language_t(text)
        elif is_ui and has_value:
            # SwiftUI looks up a format key the catalog doesn't have.
            cat, ok = "ui_value", False
        else:
            cat, ok = "code", through_language_t(text)
        results[cat][0] += 1
        if not ok: results[cat][1].append(f"{name}: {text}")

total = sum(r[0] for r in results.values())
missing = sum(len(r[1]) for r in results.values())
names = {"ui": "Fixed labels on screen", "ui_value": "Labels with a value in them", "code": "Announcements and text built in code"}
print("PORTUGUESE COVERAGE — Swift version")
for k, (n, miss) in results.items():
    pct = 100 * (n - len(miss)) / n if n else 100
    print(f"  {names[k]:<40} {n - len(miss):>5} of {n:<5} {pct:5.1f}%")
print(f"  {'Everything':<40} {total - missing:>5} of {total:<5} {100 * (total - missing) / total:5.1f}%")
out = os.path.join(ROOT, "tools", "pt-missing.txt")
with open(out, "w", encoding="utf-8") as f:
    for k, (n, miss) in results.items():
        f.write(f"## {names[k]} ({len(miss)})\n")
        f.write("\n".join(sorted(miss)) + "\n\n")
print(f"Missing text written to {os.path.relpath(out, os.path.join(ROOT, '..'))}")
if "--list" in sys.argv:
    print(open(out, encoding="utf-8").read())
sys.exit(0)
