#!/usr/bin/env python3
"""The Hunting Grounds' sounds, synthesized: each beast's call (howl, snort,
wings, hiss, growl) and a looping forest. Saves www/audio/hunt-call-*.mp3 and
www/audio/hunt-forest.mp3.   pip install numpy scipy soundfile imageio-ffmpeg"""
import os, subprocess, tempfile
import numpy as np, soundfile as sf
from scipy.signal import butter, lfilter
import shutil
try:
    import imageio_ffmpeg; FF = imageio_ffmpeg.get_ffmpeg_exe()
except ImportError:
    FF = shutil.which("ffmpeg")

SR = 44100
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "www", "audio")
rng = np.random.default_rng(7)

def t(sec): return np.arange(int(SR * sec)) / SR
def env(n, a=0.02, r=0.3):
    e = np.ones(n); ai, ri = int(SR * a), int(SR * r)
    e[:ai] = np.linspace(0, 1, ai); e[-ri:] = np.linspace(1, 0, ri) ** 2
    return e
def band(x, lo, hi, order=2):
    b, a = butter(order, [lo / (SR / 2), hi / (SR / 2)], btype="band"); return lfilter(b, a, x)
def low(x, f, order=2):
    b, a = butter(order, f / (SR / 2)); return lfilter(b, a, x)
def high(x, f, order=2):
    b, a = butter(order, f / (SR / 2), btype="high"); return lfilter(b, a, x)
def verb(x, mix=0.25):
    y = x.copy()
    for d, g in ((0.031, 0.5), (0.047, 0.4), (0.071, 0.3), (0.113, 0.22), (0.17, 0.15)):
        k = int(SR * d); y[k:] += g * mix * 2 * x[:-k]
    return y
def norm(x, peak=0.85): return x / (np.max(np.abs(x)) + 1e-9) * peak

def howl():
    tt = t(2.2)
    f = 300 + 230 * np.sin(np.pi * np.clip(tt / 1.6, 0, 1)) ** 0.7 - 60 * np.clip((tt - 1.4) / 0.8, 0, 1)
    f = f * (1 + 0.012 * np.sin(2 * np.pi * 5.5 * tt))
    ph = 2 * np.pi * np.cumsum(f) / SR
    x = np.sin(ph) + 0.35 * np.sin(2 * ph) + 0.15 * np.sin(3 * ph) + 0.04 * band(rng.standard_normal(len(tt)), 600, 3000)
    return verb(x * env(len(tt), 0.25, 0.7), 0.5)

def snort():
    parts = []
    for i, d in enumerate((0.18, 0.14, 0.26)):
        n = rng.standard_normal(int(SR * d))
        x = band(n, 180, 1400) * 1.5 + 0.6 * np.sin(2 * np.pi * (95 + 20 * i) * t(d)) * band(n, 50, 300)
        parts += [x * env(len(x), 0.01, d * 0.6), np.zeros(int(SR * 0.07))]
    return verb(np.concatenate(parts), 0.15)

def wings():
    parts = []
    for i in range(5):
        d = 0.09
        n = band(rng.standard_normal(int(SR * d)), 250, 1800) + 0.5 * low(rng.standard_normal(int(SR * d)), 200)
        parts += [n * env(len(n), 0.008, 0.06) * (1 - i * 0.08), np.zeros(int(SR * 0.075))]
    return verb(np.concatenate(parts), 0.2)

def hiss():
    tt = t(1.3)
    x = high(rng.standard_normal(len(tt)), 3500) * (0.7 + 0.3 * np.sin(2 * np.pi * 9 * tt))
    return verb(x * env(len(tt), 0.15, 0.6), 0.15)

def growl():
    tt = t(1.6)
    f = 78 + 10 * np.sin(2 * np.pi * 0.8 * tt)
    ph = 2 * np.pi * np.cumsum(f) / SR
    saw = 2 * ((ph / (2 * np.pi)) % 1) - 1
    rough = 0.55 + 0.45 * np.sign(np.sin(2 * np.pi * 23 * tt)) * (0.5 + 0.5 * rng.random(len(tt)))
    x = low(saw * rough, 900) + 0.5 * band(rng.standard_normal(len(tt)), 80, 500) * rough
    return verb(x * env(len(tt), 0.12, 0.5), 0.2)

def forest(sec=24):
    n = int(SR * sec)
    tt = np.arange(n) / SR
    wind = low(rng.standard_normal(n), 500) * (0.5 + 0.5 * np.sin(2 * np.pi * tt / 8.0) ** 2) * 0.6
    leaves = band(rng.standard_normal(n), 2000, 6000) * (0.04 + 0.05 * np.sin(2 * np.pi * tt / 5.3) ** 2)
    x = wind + leaves
    for _ in range(14):   # birds
        at = rng.uniform(0.5, sec - 1.5)
        f0 = rng.uniform(2200, 3800)
        for k in range(rng.integers(2, 5)):
            d = rng.uniform(0.06, 0.14)
            s = int(SR * (at + k * (d + 0.06)))
            tb = t(d)
            fb = f0 * (1 + rng.choice([-1, 1]) * 0.25 * tb / d)
            ch = np.sin(2 * np.pi * np.cumsum(fb) / SR) * np.sin(np.pi * tb / d) * 0.12
            x[s:s + len(ch)] += ch[: max(0, n - s)]
    fade = int(SR * 1.5)   # seamless loop: crossfade the end into the start
    x[:fade] = x[:fade] * np.linspace(0, 1, fade) + x[-fade:] * np.linspace(1, 0, fade)
    return x[:-fade]

ff = FF
def save(name, x, rate="64k"):
    with tempfile.NamedTemporaryFile(suffix=".wav") as w:
        sf.write(w.name, norm(x), SR)
        subprocess.run([ff, "-y", "-loglevel", "error", "-i", w.name, "-ac", "1", "-b:a", rate, os.path.join(OUT, name)], check=True)
    print(name)

for name, fn in (("howl", howl), ("snort", snort), ("wings", wings), ("hiss", hiss), ("growl", growl)):
    save(f"hunt-call-{name}.mp3", fn())
save("hunt-forest.mp3", forest() * 0.6, "64k")
