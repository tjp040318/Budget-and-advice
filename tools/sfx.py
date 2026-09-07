#!/usr/bin/env python3
"""
Synthesises the game's sound effects into Pantheon/Resources/Audio/*.wav.

No samples, no network: envelopes over filtered noise and sine sweeps, which is
how a great many shipped indie games sound and is vastly better than silence.
Replace any file with a recorded sample of the same name and nothing else has
to change — AudioLibrary looks them up by filename.

    python3 tools/sfx.py
"""
import math, random, struct, wave, os
SR = 44100
OUT = os.path.join(os.path.dirname(__file__), "..", "Pantheon", "Resources", "Audio")
rnd = random.Random(7)

def env(i, n, a, d, s_level, r):
    if i < a: return i / a
    if i < a + d: return 1 - (1 - s_level) * (i - a) / d
    if i < n - r: return s_level
    return s_level * max(0, (n - i) / r)

def write(name, samples):
    samples = [max(-1, min(1, x)) for x in samples]
    peak = max(1e-6, max(abs(x) for x in samples)); samples = [x / peak * 0.9 for x in samples]
    os.makedirs(OUT, exist_ok=True)
    with wave.open(os.path.join(OUT, f"{name}.wav"), "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes(b"".join(struct.pack("<h", int(x * 32767)) for x in samples))
    print(f"  {name}.wav  {len(samples) / SR:.2f}s")

def noise(): return rnd.uniform(-1, 1)
def lowpass(xs, alpha):
    y = 0; out = []
    for x in xs: y += alpha * (x - y); out.append(y)
    return out
def sweep(dur, f0, f1, shape=1.0):
    n = int(dur * SR); out = []; ph = 0
    for i in range(n):
        t = i / n; f = f0 * (f1 / f0) ** (t ** shape); ph += 2 * math.pi * f / SR; out.append(math.sin(ph))
    return out
def mix(*layers):
    n = max(len(l) for l in layers); return [sum(l[i] if i < len(l) else 0 for l in layers) for i in range(n)]
def gain(xs, g): return [x * g for x in xs]
def shaped(xs, a, d, s, r): n = len(xs); return [x * env(i, n, a, d, s, r) for i, x in enumerate(xs)]
def S(sec): return int(sec * SR)
def note(f, dur): return shaped(mix(sweep(dur, f, f), gain(sweep(dur, f * 2, f * 2), 0.35)), S(0.01), S(0.05), 0.6, int(dur * SR * 0.5))

n = S(0.12); write("hit_light", shaped(lowpass([noise() for _ in range(n)], 0.12), S(0.002), S(0.03), 0.2, S(0.06)))
n = S(0.18); write("hit_normal", mix(shaped(lowpass([noise() for _ in range(n)], 0.2), S(0.002), S(0.05), 0.25, S(0.08)), gain(shaped(sweep(0.18, 180, 60), S(0.001), S(0.06), 0.1, S(0.08)), 0.9)))
n = S(0.32); write("hit_heavy", mix(shaped(lowpass([noise() for _ in range(n)], 0.28), S(0.003), S(0.08), 0.3, S(0.16)), gain(shaped(sweep(0.32, 140, 40), S(0.001), S(0.1), 0.2, S(0.16)), 1.2)))
n = S(0.36); ping = shaped(mix(sweep(0.36, 2400, 1800), gain(sweep(0.36, 3600, 2700), 0.5)), S(0.001), S(0.04), 0.15, S(0.25))
write("hit_crit", mix(shaped(lowpass([noise() for _ in range(n)], 0.3), S(0.002), S(0.08), 0.3, S(0.18)), gain(shaped(sweep(0.36, 160, 45), S(0.001), S(0.1), 0.2, S(0.18)), 1.1), gain(ping, 0.45)))
n = S(0.7); write("hit_lethal", mix(shaped(lowpass([noise() for _ in range(n)], 0.22), S(0.003), S(0.12), 0.35, S(0.45)), gain(shaped(sweep(0.7, 120, 28), S(0.001), S(0.15), 0.3, S(0.45)), 1.3), gain(shaped(mix(sweep(0.5, 2200, 1500)), S(0.001), S(0.05), 0.1, S(0.3)), 0.35)))
n = S(0.35); write("whoosh", shaped(lowpass([noise() for _ in range(n)], 0.06), S(0.12), S(0.08), 0.6, S(0.12)))
write("ui_tap", shaped(sweep(0.05, 1800, 900), S(0.001), S(0.01), 0.3, S(0.03)))
a = shaped(sweep(0.12, 660, 660), S(0.005), S(0.03), 0.5, S(0.07)); b = shaped(sweep(0.18, 990, 990), S(0.005), S(0.04), 0.5, S(0.12))
write("ui_confirm", mix(a, [0] * S(0.09) + b))
n = S(1.4); write("summon_charge", mix(shaped(sweep(1.4, 120, 1400, 1.6), S(0.3), S(0.2), 0.8, S(0.3)), gain(shaped(lowpass([noise() for _ in range(n)], 0.5), S(0.6), S(0.2), 0.5, S(0.3)), 0.35)))
n = S(0.9); write("summon_burst", mix(shaped(lowpass([noise() for _ in range(n)], 0.4), S(0.002), S(0.1), 0.3, S(0.5)), gain(shaped(sweep(0.9, 900, 300), S(0.001), S(0.2), 0.2, S(0.5)), 0.9), gain(shaped(mix(sweep(0.9, 1320, 1320), gain(sweep(0.9, 1980, 1980), 0.6), gain(sweep(0.9, 2640, 2640), 0.4)), S(0.01), S(0.2), 0.4, S(0.55)), 0.5)))
write("star_tick", shaped(mix(sweep(0.09, 1320, 1320), gain(sweep(0.09, 2640, 2640), 0.4)), S(0.001), S(0.02), 0.3, S(0.06)))
write("victory", mix(note(523, 0.25), [0] * S(0.18) + note(659, 0.25), [0] * S(0.36) + note(784, 0.55)))
write("defeat", mix(note(440, 0.35), [0] * S(0.3) + note(415, 0.35), [0] * S(0.6) + note(349, 0.8)))
