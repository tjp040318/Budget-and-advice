#!/usr/bin/env python3
"""
Synthesises the game's sound effects into Pantheon/Resources/Audio/*.wav.

No samples, no network, no dependencies: envelopes over filtered noise, falling
pitches and decaying partials. Replace any file with a recorded sample of the
same name and nothing else has to change — AudioLibrary looks them up by
filename.

Every percussive sound is built from the same three layers, because that is
what the ear reads as an impact. The first version of this file had only the
last two, which is why every hit sounded like a thump through a wall:

  transient  2-8 ms of bright noise (most of its energy above 2 kHz, reaching
             to 8-10 kHz), decayed exponentially. This is the moment of
             contact. It is short enough that it costs no room in the mix and
             it is the single thing that makes a hit sound like a hit.
  body       a pitched element whose frequency falls fast — 400 Hz to 80 Hz in
             about 60 ms for a heavy blow. This carries the weight and the
             tier: the lower and the longer the fall, the bigger the blow.
  tail       filtered noise under the body, 80-400 ms by tier and always
             quieter than it. This is the room the blow happened in.

Then `space` adds two to four attenuated delayed copies and an all-pass, so
the sound has somewhere to be, and `finish` soft-clips the sum with tanh so
the peaks are dense rather than harsh. Order matters: normalise, then clip,
then normalise again in `write`, or the drive means nothing.

The tiers are meant to be different sounds, not one sound at five volumes:
light is short, bright and dry; normal has real body; heavy is longer and
lower with a tail; crit adds inharmonic partials (1 : 2.7 : 5.1, which is
metal, not a bell) and more space; lethal is the heaviest with a slow low
tail. `--check` measures them and will show it.

Each sound seeds its own noise from its name, so adding an effect no longer
changes the waveform of every effect written after it (the old file had to
append thunder at the end for exactly that reason).

    python3 tools/sfx.py            # write them all
    python3 tools/sfx.py --check    # measure what is on disk
"""
import cmath, math, random, struct, sys, wave, os

SR = 44100
OUT = os.path.join(os.path.dirname(__file__), "..", "Pantheon", "Resources", "Audio")

def S(sec): return int(sec * SR)

# ---------------------------------------------------------------- primitives

def noise(n, rng): return [rng.uniform(-1, 1) for _ in range(n)]

def lowpass(xs, fc):
    """One-pole low-pass, cutoff in Hz (the old file spelled these as raw
    coefficients, which nobody could tune)."""
    a = 1 - math.exp(-2 * math.pi * fc / SR)
    y = 0.0; out = []
    for x in xs:
        y += a * (x - y); out.append(y)
    return out

def highpass(xs, fc):
    """One-pole high-pass. Used to keep a transient out of the body's way."""
    a = math.exp(-2 * math.pi * fc / SR)
    y = 0.0; prev = 0.0; out = []
    for x in xs:
        y = a * (y + x - prev); prev = x; out.append(y)
    return out

def _at(points, t):
    """Geometric interpolation through [(fraction, Hz), ...]."""
    for (t0, f0), (t1, f1) in zip(points, points[1:]):
        if t <= t1:
            u = 0.0 if t1 <= t0 else (t - t0) / (t1 - t0)
            return f0 * (f1 / f0) ** max(0.0, min(1.0, u))
    return points[-1][1]

def moving_lowpass(xs, points):
    """Low-pass whose cutoff travels. A gust or a splash is noise with a
    moving filter; a fixed one just sounds like a hiss."""
    n = max(1, len(xs) - 1); y = 0.0; out = []
    for i, x in enumerate(xs):
        a = 1 - math.exp(-2 * math.pi * _at(points, i / n) / SR)
        y += a * (x - y); out.append(y)
    return out

def decay(xs, tau, attack=0.0):
    """Exponential decay with time constant `tau` seconds, optionally after a
    linear attack. Percussion decays exponentially; ADSR is for the tonal
    cues below."""
    a = max(1, S(attack)); out = []
    for i, x in enumerate(xs):
        e = math.exp(-max(0, i - a) / SR / tau)
        if attack > 0 and i < a: e *= i / a
        out.append(x * e)
    return out

def _tri(ph):
    return (2 / math.pi) * math.asin(math.sin(ph))

def mix(*layers):
    n = max(len(l) for l in layers)
    return [sum(l[i] if i < len(l) else 0 for l in layers) for i in range(n)]

def gain(xs, g): return [x * g for x in xs]
def pad(sec, xs): return [0.0] * S(sec) + list(xs)

# ------------------------------------------------------------- the three layers

def transient(rng, dur=0.004, tau=0.0015, fc=9500, hp=1200, g=1.0):
    """Layer 1. Noise band-limited to `hp`..`fc` and gone in a few
    milliseconds. Keep `dur` between 0.002 and 0.008: longer reads as a hiss
    rather than as contact."""
    xs = highpass(lowpass(noise(S(dur), rng), fc), hp)
    return gain(decay(xs, tau), g)

def body(dur, f0, f1, fall, tau, wave="sine", g=1.0, attack=0.0):
    """Layer 2. A tone whose pitch falls from `f0` to `f1` with time constant
    `fall` (so it is most of the way down after 3 x fall), decaying over
    `tau`. Sine for a clean weight, triangle for grit."""
    n = S(dur); ph = 0.0; out = []
    for i in range(n):
        f = f1 + (f0 - f1) * math.exp(-i / SR / fall)
        ph += 2 * math.pi * f / SR
        out.append(math.sin(ph) if wave == "sine" else _tri(ph))
    return gain(decay(out, tau, attack), g)

def tail(rng, dur, fc, tau, g, hp=200, attack=0.0, moving=None):
    """Layer 3. The room. Always below the body: if the tail is as loud as the
    body the hit turns into a wash."""
    xs = noise(S(dur), rng)
    xs = moving_lowpass(xs, moving) if moving else lowpass(xs, fc)
    return gain(decay(highpass(xs, hp), tau, attack), g)

def partials(dur, base, ratios, taus, gains):
    """Struck metal: a few detuned partials, each with its own decay. Whole
    ratios ring like a bell, ratios like 2.7 and 5.1 ring like a blade or an
    anvil, and the shorter the decays the duller the object."""
    n = S(dur); out = [0.0] * n
    for r, tau, g in zip(ratios, taus, gains):
        w = 2 * math.pi * base * r / SR
        for i in range(n):
            out[i] += g * math.sin(w * i) * math.exp(-i / SR / tau)
    return out

def crackle(rng, dur, count, lo, hi, tau=0.0025, g=1.0, bias=1.6):
    """Fire: a scatter of tiny band-passed pops, thickest at the start."""
    n = S(dur); out = [0.0] * n
    for _ in range(count):
        start = int(n * rng.random() ** bias)
        m = S(rng.uniform(0.002, 0.005))
        pop = decay(highpass(lowpass(noise(m, rng), hi), lo), tau)
        amp = g * rng.uniform(0.3, 1.0)
        for i, x in enumerate(pop):
            if start + i < n: out[start + i] += amp * x
    return out

def glitter(rng, dur, f0, f1, count, tau=0.05, g=1.0):
    """Magic: short sine pings climbing from f0 to f1 across the tail."""
    n = S(dur); out = [0.0] * n
    for k in range(count):
        t = k / max(1, count - 1)
        f = f0 * (f1 / f0) ** t * rng.uniform(0.94, 1.07)
        start = int(n * t * 0.8)
        m = min(n - start, S(0.09))
        for i in range(m):
            out[start + i] += g * (1 - 0.5 * t) * math.sin(2 * math.pi * f * i / SR) * math.exp(-i / SR / tau)
    return out

# ------------------------------------------------------------------- space, clip

def allpass(xs, delay=0.0071, k=0.55):
    """Diffusion. Flat in level, scrambled in phase, which smears the
    reflections into something less like two distinct echoes."""
    d = max(1, S(delay)); buf = [0.0] * d; p = 0; out = []
    for x in xs:
        v = buf[p]; y = -k * x + v
        buf[p] = x + k * y; p = (p + 1) % d
        out.append(y)
    return out

def space(xs, taps, diffuse=0.0071):
    """A room in four lines: attenuated delayed copies, then one all-pass.
    Under 20 ms the taps read as thickness, past 40 ms as a room."""
    extra = S(max(d for d, _ in taps)) if taps else 0
    out = list(xs) + [0.0] * extra
    for d, g in taps:
        k = S(d)
        for i, x in enumerate(xs): out[i + k] += g * x
    return allpass(out, diffuse) if diffuse else out

def finish(xs, drive=1.8):
    """Normalise, then soft-clip with tanh. Driving the peaks into the curve
    lifts the average level without the crunch of hard clipping, which is
    what makes a phone speaker sound loud."""
    peak = max(1e-9, max(abs(x) for x in xs))
    k = math.tanh(drive)
    return [math.tanh(drive * x / peak) / k for x in xs]

# ----------------------------------------------------------------------- output

def write(name, samples, fade=0.012):
    """Normalises to 0.89 of full scale — a little headroom, because four
    voices of the same hit can overlap — and fades the last few milliseconds
    so the file does not end on a step."""
    xs = list(samples)
    k = min(len(xs), S(fade))
    for i in range(k): xs[len(xs) - k + i] *= 1 - i / k
    peak = max(1e-9, max(abs(x) for x in xs))
    xs = [x / peak * 0.89 for x in xs]
    frames = [max(-32767, min(32767, int(round(x * 32767)))) for x in xs]
    os.makedirs(OUT, exist_ok=True)
    with wave.open(os.path.join(OUT, f"{name}.wav"), "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes(b"".join(struct.pack("<h", v) for v in frames))
    rms = math.sqrt(sum(x * x for x in xs) / len(xs))
    print(f"  {name}.wav  {len(xs) / SR:5.2f}s  peak {max(abs(x) for x in xs):.3f}  rms {rms:.3f}")

# ------------------------------------------------- ADSR, for the tonal cues only

def env(i, n, a, d, s_level, r):
    if i < a: return i / a
    if i < a + d: return 1 - (1 - s_level) * (i - a) / d
    if i < n - r: return s_level
    return s_level * max(0, (n - i) / r)

def shaped(xs, a, d, s, r):
    n = len(xs); return [x * env(i, n, a, d, s, r) for i, x in enumerate(xs)]

def sweep(dur, f0, f1, shape=1.0):
    n = int(dur * SR); out = []; ph = 0
    for i in range(n):
        t = i / n; f = f0 * (f1 / f0) ** (t ** shape)
        ph += 2 * math.pi * f / SR; out.append(math.sin(ph))
    return out

def note(f, dur):
    return shaped(mix(sweep(dur, f, f), gain(sweep(dur, f * 2, f * 2), 0.35)),
                  S(0.01), S(0.05), 0.6, int(dur * SR * 0.5))

# ==============================================================================
# The five damage tiers. Juice.sound(for:) picks one per hit, so they are heard
# next to each other constantly and must not be variations of one noise.
# ==============================================================================

def build_hits():
    r = random.Random("hit_light")
    # Light: a tap. Nearly all transient, a body that is gone in 30 ms, a tail
    # short enough to be dry. Six of these land inside one multi-hit skill.
    write("hit_light", finish(space(mix(
        transient(r, dur=0.003, tau=0.0012, fc=11000, hp=1500, g=1.60),
        body(0.07, 900, 300, fall=0.012, tau=0.020, g=0.50),
        tail(r, 0.08, fc=5000, tau=0.025, g=0.25, hp=600),
    ), [(0.011, 0.16), (0.019, 0.09)], diffuse=0.0043), drive=1.4))

    r = random.Random("hit_normal")
    # Normal: the reference blow. Same transient, but the body drops an octave
    # lower and lasts five times as long, which is the whole difference.
    write("hit_normal", finish(space(mix(
        transient(r, dur=0.005, tau=0.0020, fc=9500, hp=900, g=1.70),
        body(0.16, 480, 130, fall=0.030, tau=0.055, g=1.00),
        tail(r, 0.16, fc=3000, tau=0.050, g=0.30, hp=300),
    ), [(0.013, 0.20), (0.027, 0.12), (0.041, 0.06)]), drive=1.7))

    r = random.Random("hit_heavy")
    # Heavy: 400 -> 80 Hz in about 60 ms, on a triangle so there is something
    # to distort, plus a sub under it and a tail long enough to be a room.
    write("hit_heavy", finish(space(mix(
        transient(r, dur=0.007, tau=0.0028, fc=8000, hp=700, g=1.60),
        body(0.30, 400, 80, fall=0.020, tau=0.095, wave="tri", g=1.15),
        body(0.34, 90, 52, fall=0.060, tau=0.130, g=0.50),
        tail(r, 0.30, fc=1600, tau=0.095, g=0.34, hp=150),
    ), [(0.017, 0.26), (0.033, 0.16), (0.052, 0.09)], diffuse=0.0091), drive=2.15))

    r = random.Random("hit_crit")
    # Crit: normal's weight with metal on top. 900 Hz at 1 : 2.7 : 5.1 — the
    # inharmonic ratios are what make it read as struck steel and not a chime —
    # and the widest taps of the five tiers, so a crit sounds like a bigger room.
    write("hit_crit", finish(space(mix(
        transient(r, dur=0.005, tau=0.0018, fc=12000, hp=1400, g=1.80),
        body(0.22, 520, 110, fall=0.022, tau=0.070, g=0.95),
        gain(partials(0.52, 900, (1.0, 2.7, 5.1), (0.50, 0.38, 0.24), (0.50, 0.30, 0.18)), 0.62),
        tail(r, 0.30, fc=4500, tau=0.080, g=0.30, hp=500),
    ), [(0.019, 0.30), (0.037, 0.20), (0.061, 0.12), (0.089, 0.07)], diffuse=0.0113), drive=1.8))

    r = random.Random("hit_lethal")
    # Lethal: the killing blow, and the only hit allowed to be long. The body
    # falls to 46 Hz, the sub sits under it for most of a second, and the tail
    # is dark (900 Hz) so the length reads as weight rather than as noise.
    write("hit_lethal", finish(space(mix(
        transient(r, dur=0.008, tau=0.0035, fc=8000, hp=500, g=1.70),
        body(0.50, 320, 46, fall=0.050, tau=0.200, wave="tri", g=1.20),
        body(0.85, 60, 32, fall=0.120, tau=0.340, g=0.70),
        tail(r, 0.85, fc=900, tau=0.300, g=0.40, hp=90),
        tail(r, 0.26, fc=5000, tau=0.080, g=0.30, hp=800),
    ), [(0.023, 0.30), (0.047, 0.20), (0.079, 0.13), (0.115, 0.08)], diffuse=0.0131), drive=3.0))

# ==============================================================================
# Hits by kind. A sword, a club and a spell all land as `hit_normal` today;
# these give the caller something to pick with.
# ==============================================================================

def build_kinds():
    r = random.Random("hit_blade")
    # Blade: the transient is the shortest here (2 ms, band-limited high) and
    # the ring is short — steel that is being held, not a struck bell. The
    # band-passed "cut" sweeping down is the edge passing the ear.
    write("hit_blade", finish(space(mix(
        transient(r, dur=0.002, tau=0.0009, fc=13000, hp=2500, g=1.00),
        gain(decay(moving_lowpass(noise(S(0.09), r), [(0, 6000), (1, 1500)]), 0.030), 0.50),
        gain(partials(0.20, 2400, (1.0, 2.24, 3.61), (0.16, 0.11, 0.07), (0.50, 0.32, 0.20)), 0.60),
        body(0.10, 700, 220, fall=0.020, tau=0.030, g=0.35),
    ), [(0.013, 0.18), (0.029, 0.10)], diffuse=0.0037), drive=1.6))

    r = random.Random("hit_blunt")
    # Blunt: the transient is deliberately dull (rolled off at 3 kHz, a
    # quarter of the level) — that absence is what makes wood and stone read
    # as wood and stone. The weight is all in the body.
    write("hit_blunt", finish(space(mix(
        transient(r, dur=0.004, tau=0.0020, fc=4500, hp=250, g=0.70),
        body(0.26, 320, 95, fall=0.018, tau=0.090, wave="tri", g=1.20),
        gain(partials(0.14, 260, (1.0, 2.1, 4.7), (0.05, 0.035, 0.02), (0.30, 0.16, 0.10)), 1.10),
        tail(r, 0.20, fc=900, tau=0.060, g=0.22, hp=100),
    ), [(0.021, 0.20), (0.039, 0.11)], diffuse=0.0083), drive=2.0))

    r = random.Random("hit_magic")
    # Magic: no contact at all. A 25 ms swell instead of a transient, a low
    # tone that hangs, and pings climbing 1.2 -> 4.8 kHz over the tail.
    write("hit_magic", finish(space(mix(
        gain(decay(lowpass(noise(S(0.45), r), 1800), 0.120, attack=0.025), 0.35),
        body(0.45, 300, 150, fall=0.080, tau=0.180, g=0.70, attack=0.020),
        gain(glitter(r, 0.55, 1200, 4800, count=14, tau=0.045), 0.75),
    ), [(0.025, 0.30), (0.051, 0.20), (0.083, 0.12)], diffuse=0.0117), drive=1.4))

# ==============================================================================
# One impact per element, for `impact_<element>`, which BattleSceneController
# already asks for by name whenever a skill has no effect of its own.
# ==============================================================================

def build_elements():
    r = random.Random("impact_ember")
    # Ember: a low whoomp, then forty small pops thinning out over 450 ms. The
    # crackle is the fire; the hiss underneath is the air it is eating.
    write("impact_ember", finish(space(mix(
        transient(r, dur=0.004, tau=0.0018, fc=8000, hp=900, g=0.55),
        body(0.28, 300, 70, fall=0.030, tau=0.100, g=0.70),
        gain(crackle(r, 0.50, count=55, lo=2000, hi=7000, tau=0.0025), 1.00),
        tail(r, 0.45, fc=2500, tau=0.140, g=0.25, hp=400),
    ), [(0.017, 0.22), (0.037, 0.13)], diffuse=0.0079), drive=1.8))

    r = random.Random("impact_tide")
    # Tide: the slap first (a short body), then spray above 3 kHz that is gone
    # in 70 ms, then the gurgle — noise whose cutoff falls 4 kHz -> 400 Hz,
    # which is water closing over the hole it made.
    write("impact_tide", finish(space(mix(
        transient(r, dur=0.004, tau=0.0016, fc=9000, hp=1500, g=0.60),
        body(0.20, 520, 150, fall=0.025, tau=0.060, g=0.70),
        gain(decay(highpass(noise(S(0.25), r), 3000), 0.070), 0.50),
        tail(r, 0.45, fc=0, tau=0.200, g=0.35, hp=120, moving=[(0, 4000), (1, 400)]),
    ), [(0.019, 0.25), (0.041, 0.15), (0.067, 0.08)], diffuse=0.0097), drive=1.7))

    r = random.Random("impact_gale")
    # Gale: no contact, all movement. The cutoff climbs 300 Hz -> 3.5 kHz and
    # falls back to 600 over 600 ms; a fixed filter here is just a hiss. The
    # quiet falling tone is the edge of the gust passing.
    write("impact_gale", finish(space(mix(
        transient(r, dur=0.004, tau=0.0020, fc=6000, hp=800, g=0.15),
        tail(r, 0.60, fc=0, tau=0.220, g=1.00, hp=250, attack=0.080,
             moving=[(0, 300), (0.35, 3500), (1, 600)]),
        body(0.40, 1500, 700, fall=0.180, tau=0.220, g=0.22, attack=0.060),
    ), [(0.023, 0.28), (0.049, 0.18)], diffuse=0.0107), drive=1.5))

    r = random.Random("impact_radiance")
    # Radiance: a bell. 1.2 kHz at the classic slightly-off ratios (2.97, 5.44
    # are what a bell actually rings at), the longest decays in the file, and a
    # shimmer of high noise over the top.
    write("impact_radiance", finish(space(mix(
        transient(r, dur=0.003, tau=0.0010, fc=13000, hp=3000, g=0.80),
        gain(partials(0.65, 1200, (1.0, 2.0, 2.97, 5.44, 8.1),
                      (0.55, 0.42, 0.30, 0.20, 0.12),
                      (0.50, 0.35, 0.25, 0.15, 0.09)), 0.90),
        body(0.12, 700, 300, fall=0.030, tau=0.040, g=0.35),
        tail(r, 0.40, fc=12000, tau=0.180, g=0.15, hp=4000),
    ), [(0.021, 0.30), (0.045, 0.20), (0.077, 0.13), (0.107, 0.08)], diffuse=0.0127), drive=1.4))

    r = random.Random("impact_umbra")
    # Umbra: the transient is muffled on purpose (3.5 kHz, a third of the
    # level) and everything swells rather than strikes — 120 ms of attack, a
    # sub at 55 -> 28 Hz, and a tail rolled off at 500 Hz for most of a second.
    write("impact_umbra", finish(space(mix(
        transient(r, dur=0.006, tau=0.0030, fc=4500, hp=200, g=0.50),
        body(0.50, 165, 58, fall=0.100, tau=0.300, g=1.10, attack=0.100),
        body(0.90, 78, 42, fall=0.200, tau=0.400, g=0.60, attack=0.120),
        tail(r, 0.90, fc=700, tau=0.400, g=0.44, hp=60, attack=0.150),
    ), [(0.029, 0.30), (0.059, 0.20), (0.097, 0.13)], diffuse=0.0139), drive=2.1))

# ==============================================================================
# Defence.
# ==============================================================================

def build_defence():
    r = random.Random("block")
    # Block: a crit's metal with the ring damped to a tenth of a second and
    # the room taken away. Struck steel that is being held against something.
    write("block", finish(space(mix(
        transient(r, dur=0.004, tau=0.0016, fc=6000, hp=800, g=1.00),
        gain(partials(0.16, 430, (1.0, 2.42, 3.12), (0.10, 0.07, 0.05), (0.50, 0.30, 0.20)), 1.00),
        body(0.16, 240, 95, fall=0.020, tau=0.060, wave="tri", g=0.90),
        tail(r, 0.16, fc=1800, tau=0.050, g=0.25, hp=200),
    ), [(0.015, 0.20), (0.031, 0.11)], diffuse=0.0061), drive=1.9))

    r = random.Random("dodge")
    # Dodge: half the length of `whoosh` and four times as bright, so the two
    # are not mistaken for each other — this is a body moving out of the way,
    # not a weapon swinging through.
    write("dodge", finish(space(mix(
        tail(r, 0.20, fc=0, tau=0.050, g=1.00, hp=400, attack=0.045,
             moving=[(0, 600), (0.45, 4200), (1, 900)]),
    ), [(0.011, 0.15)], diffuse=0.0031), drive=1.3))

# ==============================================================================
# The rest: unchanged in design from the first version of this file, and every
# one of them is named by AudioLibrary.Sound.
# ==============================================================================

def build_rest():
    r = random.Random("whoosh")
    # A weapon swinging: slow in, slow out, nothing above 430 Hz.
    write("whoosh", shaped(lowpass(noise(S(0.35), r), 434), S(0.12), S(0.08), 0.6, S(0.12)))
    write("ui_tap", shaped(sweep(0.05, 1800, 900), S(0.001), S(0.01), 0.3, S(0.03)))
    a = shaped(sweep(0.12, 660, 660), S(0.005), S(0.03), 0.5, S(0.07))
    b = shaped(sweep(0.18, 990, 990), S(0.005), S(0.04), 0.5, S(0.12))
    write("ui_confirm", mix(a, pad(0.09, b)))

    r = random.Random("summon_charge")
    n = S(1.4)
    write("summon_charge", mix(
        shaped(sweep(1.4, 120, 1400, 1.6), S(0.3), S(0.2), 0.8, S(0.3)),
        gain(shaped(lowpass(noise(n, r), 4870), S(0.6), S(0.2), 0.5, S(0.3)), 0.35)))

    r = random.Random("summon_burst")
    n = S(0.9)
    write("summon_burst", mix(
        shaped(lowpass(noise(n, r), 3590), S(0.002), S(0.1), 0.3, S(0.5)),
        gain(shaped(sweep(0.9, 900, 300), S(0.001), S(0.2), 0.2, S(0.5)), 0.9),
        gain(shaped(mix(sweep(0.9, 1320, 1320), gain(sweep(0.9, 1980, 1980), 0.6),
                        gain(sweep(0.9, 2640, 2640), 0.4)), S(0.01), S(0.2), 0.4, S(0.55)), 0.5)))

    write("star_tick", shaped(mix(sweep(0.09, 1320, 1320), gain(sweep(0.09, 2640, 2640), 0.4)),
                              S(0.001), S(0.02), 0.3, S(0.06)))
    write("victory", mix(note(523, 0.25), pad(0.18, note(659, 0.25)), pad(0.36, note(784, 0.55))))
    write("defeat", mix(note(440, 0.35), pad(0.3, note(415, 0.35)), pad(0.6, note(349, 0.8))))

    # Thunder, for the Zeus kit: a crack of unfiltered noise, then a long low
    # rumble and a sub-bass sweep under it.
    r = random.Random("thunder")
    n = S(1.5)
    crack = shaped(noise(S(0.07), r), S(0.001), S(0.02), 0.35, S(0.05)) + [0] * (n - S(0.07))
    rumble = shaped(lowpass(noise(n, r), 290), S(0.03), S(0.4), 0.45, S(0.9))
    boom = shaped(sweep(1.5, 95, 30), S(0.002), S(0.35), 0.3, S(0.9))
    write("thunder", mix(gain(crack, 1.0), gain(rumble, 1.2), gain(boom, 0.9)))

# ==============================================================================
# Measurement. There is no listening in this environment, so the only check on
# any of the above is the numbers: `python3 tools/sfx.py --check`.
# ==============================================================================

def _fft(xs):
    n = len(xs)
    if n == 1: return [complex(xs[0])]
    even = _fft(xs[0::2]); odd = _fft(xs[1::2]); out = [0j] * n
    for k in range(n // 2):
        t = cmath.exp(-2j * math.pi * k / n) * odd[k]
        out[k] = even[k] + t; out[k + n // 2] = even[k] - t
    return out

def _spectrum(xs, start, size=1024):
    """Hann-windowed magnitudes of one window, zero-padded if short."""
    w = list(xs[start:start + size]) + [0.0] * max(0, size - len(xs[start:start + size]))
    w = [v * 0.5 * (1 - math.cos(2 * math.pi * i / (size - 1))) for i, v in enumerate(w)]
    return [abs(v) for v in _fft(w)[:size // 2]]

def _bands(mag, size=1024):
    edges = [0, 500, 2000, 6000, SR / 2]
    out = []
    for lo, hi in zip(edges, edges[1:]):
        i0 = int(lo * size / SR); i1 = max(i0 + 1, int(hi * size / SR))
        out.append(sum(m * m for m in mag[i0:i1]))
    total = max(1e-18, sum(out))
    return [v / total for v in out]

def _zcr(xs):
    if len(xs) < 2: return 0.0
    c = sum(1 for a, b in zip(xs, xs[1:]) if (a >= 0) != (b >= 0))
    return c / (len(xs) / SR)

def check():
    names = sorted(f for f in os.listdir(OUT) if f.endswith(".wav") and not f.startswith("music_"))
    print(f"{'file':18} {'dur':>6} {'peak':>6} {'rms':>6} {'centre':>7} "
          f"{'zcr<10ms':>9} {'zcr>100ms':>10} {'hi<10ms':>8} {'hi>100ms':>9}  bands lo/mid/hi/top")
    for f in names:
        with wave.open(os.path.join(OUT, f), "rb") as w:
            n = w.getnframes(); raw = w.readframes(n)
        xs = [v / 32768.0 for (v,) in struct.iter_unpack("<h", raw)]
        dur = n / SR
        peak = max(abs(x) for x in xs)
        rms = math.sqrt(sum(x * x for x in xs) / max(1, n))
        # Energy-weighted spectral centre over the whole file.
        num = den = 0.0; acc = [0.0] * 4
        for s in range(0, max(1, n - 1024), 2048):
            mag = _spectrum(xs, s)
            w = sum(m * m for m in mag)
            for i, m in enumerate(mag):
                e = m * m; num += e * i * SR / 1024; den += e
            for i, v in enumerate(_bands(mag)): acc[i] += v * w
        centre = num / max(1e-18, den)
        bands = [v / max(1e-18, den) for v in acc]
        early = xs[:S(0.010)]
        late = xs[S(0.100):S(0.110)] or [0.0]
        b_early = _bands(_spectrum(xs, 0, 512), 512)
        b_late = _bands(_spectrum(xs, S(0.100), 512), 512)
        print(f"{f[:-4]:18} {dur:6.3f} {peak:6.3f} {rms:6.3f} {centre:7.0f} "
              f"{_zcr(early):9.0f} {_zcr(late):10.0f} "
              f"{b_early[2] + b_early[3]:8.2f} {b_late[2] + b_late[3]:9.2f}  "
              + "/".join(f"{v:.2f}" for v in bands))
        if peak >= 0.999: print(f"    ! {f} clips")
        if rms < 1e-4: print(f"    ! {f} is silent")

def main():
    if "--check" in sys.argv:
        check(); return
    build_hits(); build_kinds(); build_elements(); build_defence(); build_rest()
    print(f"wrote {len(os.listdir(OUT))} files to {os.path.normpath(OUT)}")

main()
