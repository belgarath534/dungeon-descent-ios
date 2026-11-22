#!/usr/bin/env python3
"""The Hunting Grounds narrator's voice: every line of hunt-lines.json spoken
with Kokoro (open-source text to speech), Lewis in English and Alex in
Portuguese, saved as www/audio/hunt/<en|pt>/<id>.mp3.

  pip install kokoro-onnx soundfile imageio-ffmpeg
  python3 swift/tools/hunt-voice.py <folder with kokoro-v1.0.onnx and voices-v1.0.bin>

Only lines whose text changed are made again (www/audio/hunt/manifest.json).
"""
import hashlib, json, os, subprocess, sys, tempfile
import soundfile as sf
from kokoro_onnx import Kokoro
try:
    import imageio_ffmpeg; FFMPEG = imageio_ffmpeg.get_ffmpeg_exe()
except Exception:
    FFMPEG = "ffmpeg"

HERE = os.path.dirname(os.path.abspath(__file__))
LINES = os.path.join(HERE, "..", "DungeonCore", "Sources", "DungeonCore", "Resources", "hunt-lines.json")
OUT = os.path.join(HERE, "..", "..", "www", "audio", "hunt")
VOICES = {"en": ("bm_lewis", "en-gb"), "pt": ("pm_alex", "pt-br")}

models = sys.argv[1] if len(sys.argv) > 1 else "."
k = Kokoro(os.path.join(models, "kokoro-v1.0.onnx"), os.path.join(models, "voices-v1.0.bin"))
lines = json.load(open(LINES, encoding="utf-8"))
man_path = os.path.join(OUT, "manifest.json")
manifest = json.load(open(man_path)) if os.path.exists(man_path) else {}
made = 0
for lang, (voice, code) in VOICES.items():
    os.makedirs(os.path.join(OUT, lang), exist_ok=True)
    for i, t in lines.items():
        text = t[lang]
        key = f"{lang}/{i}"
        h = hashlib.sha1(f"{voice}|{text}".encode()).hexdigest()[:12]
        mp3 = os.path.join(OUT, lang, f"{i}.mp3")
        if manifest.get(key) == h and os.path.exists(mp3): continue
        s, sr = k.create(text, voice=voice, speed=0.95, lang=code)
        with tempfile.NamedTemporaryFile(suffix=".wav") as w:
            sf.write(w.name, s, sr)
            subprocess.run([FFMPEG, "-y", "-loglevel", "error", "-i", w.name, "-ac", "1", "-b:a", "48k", mp3], check=True)
        manifest[key] = h
        made += 1
        if made % 50 == 0:
            print(made, "made", flush=True)
            json.dump(manifest, open(man_path, "w"), indent=0, sort_keys=True)
# Drop clips for lines that no longer exist.
for key in list(manifest):
    lang, i = key.split("/", 1)
    if i not in lines:
        try: os.remove(os.path.join(OUT, lang, f"{i}.mp3"))
        except FileNotFoundError: pass
        del manifest[key]
json.dump(manifest, open(man_path, "w"), indent=0, sort_keys=True)
print(f"done: {made} new clips, {len(manifest)} in all")
