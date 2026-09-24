#!/usr/bin/env python3
"""
Synthesises the game's sound effects into Pantheon/Resources/Audio/*.wav.

The first five sections use no samples, no network and no dependencies:
envelopes over filtered noise, falling pitches and decaying partials. Replace any file with a recorded sample of the
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

The fight's own events (FEEL.md W1.4, 2026-09-24) are the last two sections,
`build_status` and `build_flow`: the heal and every status as it lands, the
counter, the extra turn, a revive, a death, a horn call per realm, a boss's
arrival, the player's turn and the level-up fanfare. They use numpy and scipy,
and the instrumental ones layer CC0 recordings from VSCO 2 Community Edition,
which are fetched on demand and never committed; their header says how, and
what each recording is for.

    python3 tools/sfx.py                     # write them all
    python3 tools/sfx.py status flow         # only the named sections
    python3 tools/sfx.py summon --vsco DIR   # the summon's (FEEL.md W2.7)
    python3 tools/sfx.py spoils --vsco DIR   # the reward box's (FEEL.md W2.2)
    python3 tools/sfx.py flow --out /tmp/x   # somewhere else, to audition
    python3 tools/sfx.py --check             # measure what is on disk
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
# The fight's own events (FEEL.md W1.4, 2026-09-24). `build_status`: the heal,
# the shield and every other status as it lands. `build_flow`: the counter, an
# extra turn, a revive, a death, a horn call per realm when a wave arrives, a
# boss's arrival, the player's turn and the level-up fanfare (W1.6).
#
# Everything above works on Python lists with nothing but the standard library.
# Everything below works on numpy arrays with scipy, because it layers
# recordings, convolves reverb and measures loudness, which lists would take
# minutes over:
#
#     python3 tools/sfx.py status flow            # build only these
#     python3 tools/sfx.py flow --out /tmp/x      # audition somewhere else
#
# Two sources.
#
#   Synthesis, as above, for everything that is not an instrument: the stun's
#   blow and ringing ears, ice forming, fire catching, a shield struck twice,
#   a fuse, a death's fall and the soul leaving it, a crystal ring, the choir
#   and the boss's roar.
#
#   Recordings, for what a synth only imitates: harp, glockenspiel, bell tree,
#   horn, trumpet, oboe, gong, cymbal, timpani, bass drum and an anvil (and,
#   for the summon, string sections in tremolo, a timpani roll, a suspended
#   cymbal and a triangle), all
#   from VSCO 2 Community Edition by Versilian Studios (recorded by Sam
#   Gossner and Simon Dalzell): https://github.com/sgossner/VSCO-2-CE at
#   commit 44030090 (`VSCO_COMMIT`). Its LICENSE file, read 2026-09-24, is
#   CC0 1.0 Universal: no rights reserved, commercial use included. Its readme
#   ASKS, without requiring it, for credit to Versilian Studios / Sam Gossner
#   and Ivy Audio / Simon Dalzell with a link to
#   vis.versilstudios.net/vsco-community.html, and that the samples themselves
#   not be sold; effects built from them are neither. Every file used, and
#   what for, is in `VSCO` below. The recordings are NOT kept in this
#   repository: a sound that needs them is built only when a checkout of those
#   files is found, and is skipped otherwise, which leaves the shipped file
#   alone:
#
#     python3 tools/sfx.py --fetch-vsco /tmp/vsco     # sparse clone, 66 MB
#     python3 tools/sfx.py status flow --vsco /tmp/vsco
#
# Loudness. The effects above are all peaked at 0.89 and are as loud as their
# shape makes them: -21 to -7 LUFS at their loudest 400 ms (K-weighted,
# `loudness`), median -13.3, measured 2026-09-24. Through a phone's speaker,
# which has little under 250 Hz, the hits lose up to 7 dB of that (a crit
# plays at -10.9, a normal hit at -18.5, a heavy one at -19.1) while the
# sounds below lose under 2, because their weight is in the band a phone
# plays. So they are matched by role (`level`) a step under where their
# full-band number would put them, and never peak over 0.89:
#
#     the status cues and the heal  -14.5   at the hooks' 0.8, level with an
#                                           ordinary hit (-16.6), under a
#                                           heavy (-13.3) or critical one
#     counter, extra turn, revive,  -12
#       death
#     the horn calls                -10     victory -10.8
#     the boss, the level-up        -9.5    summon_charge -7
#     the turn chime                -15     AudioLibrary also caps it at 0.35,
#                                           about 7 dB over the battle music
#                                           at its 0.32 (-31.6 LUFS)
#
# The summon's (`build_summon`, W2.7) are levelled as a MIX, because the
# reveal plays up to four of them at once and a phone's mixer sums them
# with no limiter after it: the charge's base -15, its rise -16 and tell
# -16 laid over it, the Light & Dark layer -18 — a 3★'s charge -16.6 at
# the reveal's 0.85, a 4★'s -14.8, a 5★'s -12.7; the bursts -13 (3★), -12
# (4★) and -11 (5★), each a step over its charge; the stars -17.5 rising to
# -15.5; the rites -11 (the awakening) and -12 (an evolution, a relic's
# awakening); the scroll catching light at the button -15.
# `summon_mix_check` plays them at the reveal's own offsets and volumes:
# every grade's sum peaks at or under 0.90 of full scale. The first levels
# (the bursts at -12/-11/-9, the charge's stems 1.5 dB hotter) summed to
# 1.36 over a 5★'s stars and 1.07 in its charge.
# ==============================================================================

try:
    import numpy as np
    from scipy import signal as sps
    from scipy.io import wavfile
    from scipy.ndimage import minimum_filter1d, uniform_filter1d
except ImportError:  # the effects above need neither
    np = None

def _need():
    if np is None:
        sys.exit("the W1.4 sounds need numpy and scipy: pip install numpy scipy")

def seeded(name):
    """Noise seeded by the sound's name, as `random.Random(name)` is above, so
    adding a sound never moves another's waveform."""
    import hashlib
    return np.random.default_rng(int.from_bytes(hashlib.sha256(name.encode()).digest()[:8], "little"))

def N(sec): return max(0, int(round(sec * SR)))
def T(n): return np.arange(n) / SR

class Bus:
    """A timeline to lay layers on: `add(layer, at=seconds, g=gain)`. It grows
    when a layer runs past its end. Every layer's last 4 ms are faded on the
    way in: a layer cut while it still sounds is a click, and the first
    spectrograms of this set showed one at the end of nearly every note."""
    def __init__(self): self.x = np.zeros(1)
    def add(self, layer, at=0.0, g=1.0):
        layer = fade_tail(layer, 0.004); a = N(at); end = a + len(layer)
        if end > len(self.x): self.x = np.concatenate([self.x, np.zeros(end - len(self.x))])
        self.x[a:end] += g * layer
        return self

# ------------------------------------------------------------------- filters

def _butter(kind, f, order):
    return sps.butter(order, f, btype=kind, fs=SR, output="sos")

def lp(x, f, order=2): return sps.sosfilt(_butter("lowpass", min(f, 0.45 * SR), order), x)
def hp(x, f, order=2): return sps.sosfilt(_butter("highpass", f, order), x)
def bp(x, lo, hi, order=2): return sps.sosfilt(_butter("bandpass", [lo, min(hi, 0.45 * SR)], order), x)

def _biquad(kind, f, q):
    """One RBJ-cookbook biquad as an sos row. The band-pass is the constant
    0 dB peak form, so a bank of them (a voice's formants) sums at the gains
    it is given."""
    w = 2 * math.pi * min(f, 0.45 * SR) / SR
    c, al = math.cos(w), math.sin(w) / (2 * q)
    b = {"bp": (al, 0.0, -al),
         "lp": ((1 - c) / 2, 1 - c, (1 - c) / 2),
         "hp": ((1 + c) / 2, -(1 + c), (1 + c) / 2)}[kind]
    a0 = 1 + al
    return [b[0] / a0, b[1] / a0, b[2] / a0, 1.0, -2 * c / a0, (1 - al) / a0]

def reson(x, f, q): return sps.sosfilt(np.array([_biquad("bp", f, q)]), x)

def travel(x, points, q=0.8, kind="bp"):
    """A filter whose frequency travels through [(fraction, Hz), ...]
    (geometric between points, as `moving_lowpass` above), recomputed every
    4 ms with its state carried across so the sweep is one continuous
    movement. A gust, a flame catching or a vowel opening is noise or a buzz
    under a moving filter; a fixed one is only a hiss."""
    x = np.asarray(x, float); n = len(x); blk = N(0.004)
    out = np.empty(n); zi = np.zeros((1, 2))
    for s in range(0, n, blk):
        sos = np.array([_biquad(kind, _at(points, s / max(1, n - 1)), q)])
        out[s:s + blk], zi = sps.sosfilt(sos, x[s:s + blk], zi=zi)
    return out

# ---------------------------------------------------------- envelopes, sources

def fall(n, tau, attack=0.0):
    """Exponential decay over `tau` seconds after a raised-cosine attack."""
    t = T(n); e = np.exp(-np.maximum(0.0, t - attack) / tau)
    if attack > 0:
        e *= np.where(t < attack, 0.5 - 0.5 * np.cos(np.pi * np.clip(t / attack, 0, 1)), 1.0)
    return e

def shape(n, points):
    """A piecewise-linear envelope through [(seconds, level), ...]."""
    ts, vs = zip(*points)
    return np.interp(T(n), ts, vs)

def fade_tail(x, sec):
    """Cosine-squared fade over the last `sec` seconds, so nothing ends on a
    step."""
    x = np.array(x, float); k = min(len(x), N(sec))
    if k: x[len(x) - k:] *= np.cos(np.linspace(0, np.pi / 2, k)) ** 2
    return x

def hz(f, n):
    """A frequency given as a number or as a per-sample curve, as a curve."""
    f = np.asarray(f, float)
    return np.full(n, float(f)) if f.ndim == 0 else f[:n]

def tone(f, n, p0=0.0):
    return np.sin(2 * np.pi * np.cumsum(hz(f, n)) / SR + p0)

def saw(f, n):
    """A band-limited sawtooth (polyBLEP) for voices and growls: a naive one
    aliases audibly under 200 Hz."""
    dt = hz(f, n) / SR
    p = np.cumsum(dt) % 1.0
    y = 2 * p - 1
    m = p < dt; u = p[m] / dt[m]; y[m] -= u + u - u * u - 1
    m = p > 1 - dt; u = (p[m] - 1) / dt[m]; y[m] -= u * u + u + u + 1
    return y

def drop(dur, f0, f1, fall_tau, tau, attack=0.0, wave="sine"):
    """`body` above in numpy: a tone falling from f0 to f1 with time constant
    `fall_tau`, decaying over `tau`. The weight of a blow."""
    n = N(dur); t = T(n)
    f = f1 + (f0 - f1) * np.exp(-t / fall_tau)
    ph = 2 * np.pi * np.cumsum(f) / SR
    v = np.sin(ph) if wave == "sine" else (2 / np.pi) * np.arcsin(np.sin(ph))
    return v * fall(n, tau, attack)

def click(r, dur=0.004, tau=0.0015, fc=9500, lo=1200):
    """`transient` above in numpy: a few milliseconds of band-limited noise,
    the moment of contact."""
    x = bp(r.standard_normal(N(dur) + 8), lo, fc)
    return x * np.exp(-T(len(x)) / tau)

def smooth_noise(r, n, fc):
    """Noise low-passed at `fc` and scaled to about +-1: a slow random curve,
    for jitter, roughness and flicker."""
    v = lp(r.standard_normal(n + N(0.2)), fc, 2)[N(0.2):]
    return v / (3 * np.std(v) + 1e-12)

def modes(dur, base, ratios, taus, gains, split=0.0, glide_to=None, glide_tau=0.1, rng=None):
    """Struck modes, each partial with its own decay: glass, a bar, a gong,
    a shield. `split` Hz divides every mode into a close pair that beats: no
    real glass or bell is perfectly round, and the slow wah of that pair is
    most of what makes one sound real. `glide_to` bends the whole set as it
    rings, which a Peking-opera gong does."""
    n = N(dur); t = T(n); out = np.zeros(n)
    rise = 1.0 if glide_to is None else glide_to + (1 - glide_to) * np.exp(-t / glide_tau)
    top = 1.0 if glide_to is None else max(1.0, glide_to)
    for ratio, tau, g in zip(ratios, taus, gains):
        if base * ratio * top + split > 0.45 * SR: continue
        f = base * ratio * rise
        p0 = 0.0 if rng is None else rng.uniform(0, 2 * np.pi)
        v = tone(f, n, p0)
        if split: v = 0.5 * (v + tone(f + split, n, p0 + 1.3))
        out += g * v * np.exp(-t / tau)
    return out

def pops(r, dur, count, lo, hi, bias=1.6, tau=0.0025):
    """`crackle` above in numpy: tiny band-passed pops, thickest at the start
    (`bias` > 1) — fire, a fuse, frost."""
    n = N(dur); out = np.zeros(n)
    for _ in range(count):
        start = int(n * r.random() ** bias); m = N(r.uniform(0.002, 0.006))
        p = bp(r.standard_normal(m + 8), lo, hi) * np.exp(-T(m + 8) / tau) * r.uniform(0.3, 1.0)
        end = min(n, start + len(p)); out[start:end] += p[:end - start]
    return out

def formants(x, table):
    """A voice: the source through a parallel bank of resonances, one per
    formant, `table` as [(Hz, bandwidth Hz, dB), ...]."""
    return sum(reson(x, f, f / bw) * 10 ** (db / 20) for f, bw, db in table)

# ------------------------------------------------------------- space, loudness

def room(x, rt60=1.2, wet=0.22, pre=0.012, seed="room", bright=1.0, lo_cut=180):
    """Convolution with a made-up room: noise dying 60 dB over `rt60` in three
    bands at different rates (the lows last longest and the highs go first,
    as in stone) after a short pre-delay. `wet` is the tail against the dry
    sound, which is kept whole. The tail loses what is under `lo_cut`, as a
    mixer's reverb return does: a thud's reverb is only mud, and it smeared
    the stun's blow across most of a second."""
    r = seeded("room:" + seed)
    L = N(rt60 * 1.15); t = T(L); w = r.standard_normal(L)
    ir = (lp(w, 400) * np.exp(-6.91 * t / (rt60 * 1.15))
          + bp(w, 400, 3500) * np.exp(-6.91 * t / rt60)
          + bright * hp(w, 3500) * np.exp(-6.91 * t / (rt60 * 0.5)))
    ir[:N(pre)] = 0.0
    ir /= np.sqrt(np.sum(ir ** 2))
    tail = hp(sps.fftconvolve(x, ir), lo_cut)
    return np.concatenate([x, np.zeros(len(tail) - len(x))]) + wet * tail

def _kweight(x):
    """ITU-R BS.1770 K-weighting: a +4 dB shelf over about 1.5 kHz and a
    high-pass at 38 Hz, the ear's weighting for loudness."""
    f0, G, Q = 1681.974450955533, 3.999843853973347, 0.7071752369554196
    K = math.tan(math.pi * f0 / SR); Vh = 10 ** (G / 20); Vb = Vh ** 0.4996667741545416
    a0 = 1 + K / Q + K * K
    shelf = [(Vh + Vb * K / Q + K * K) / a0, 2 * (K * K - Vh) / a0, (Vh - Vb * K / Q + K * K) / a0,
             1.0, 2 * (K * K - 1) / a0, (1 - K / Q + K * K) / a0]
    f0, Q = 38.13547087602444, 0.5003270373238773
    K = math.tan(math.pi * f0 / SR); a0 = 1 + K / Q + K * K
    high = [1.0, -2.0, 1.0, 1.0, 2 * (K * K - 1) / a0, (1 - K / Q + K * K) / a0]
    return sps.sosfilt(np.array([shelf, high]), x)

def loudness(x):
    """The loudest 400 ms in LUFS (BS.1770 momentary, 10 ms hop): how loud a
    short sound is heard at its peak. A file shorter than one window is
    padded, so a 90 ms tick reads low — the same way for every file, which
    is what a comparison needs."""
    y = _kweight(np.asarray(x, float)); b = N(0.4)
    if len(y) < b: y = np.concatenate([y, np.zeros(b - len(y))])
    c = np.concatenate([[0.0], np.cumsum(y * y)])
    ms = (c[b:] - c[:-b])[::N(0.01)] / b
    return -0.691 + 10 * math.log10(max(float(ms.max()), 1e-20))

def limit(x, ceiling=0.89, look=0.008):
    """A look-ahead limiter: the gain every sample needs to stay under the
    ceiling, held over `look` seconds either side and smoothed inside that
    span, so the level dips just before a peak and comes back after it.
    Unlike `finish`'s tanh it adds no harmonics, which a harp or a bell
    would wear as grit."""
    w = max(1, N(look))
    need = np.minimum(1.0, ceiling / np.maximum(np.abs(x), 1e-12))
    return x * uniform_filter1d(minimum_filter1d(need, 2 * w + 1), w + 1)

def level(x, target, ceiling=0.89, most=6.0):
    """Brings a sound to `target` LUFS (`loudness`) with its peak at or under
    `ceiling`: louder through the limiter, by `most` dB at the most, and
    quieter by gain alone. Past about 6 dB a limiter flattens a sound into a
    wall (the first boss_arrival took 12 and lost its hit), so a sound that
    cannot get there is left under its target and said to be — the fix is in
    its mix, not in more limiting."""
    x = x / max(1e-12, float(np.max(np.abs(x)))) * ceiling
    now = loudness(x)
    if now >= target:
        return x * 10 ** ((target - now) / 20)
    lo, hi = 0.0, most
    if loudness(limit(x * 10 ** (hi / 20), ceiling)) < target:
        y = np.clip(limit(x * 10 ** (hi / 20), ceiling), -ceiling, ceiling)
        print(f"    ! {loudness(y):.1f} LUFS after {most:g} dB of limiting, under its {target}")
        return y
    for _ in range(22):
        mid = (lo + hi) / 2
        if loudness(limit(x * 10 ** (mid / 20), ceiling)) < target: lo = mid
        else: hi = mid
    return np.clip(limit(x * 10 ** (hi / 20), ceiling), -ceiling, ceiling)

def save(name, x, target, tail=0.25):
    """Takes the DC and the rumble out, trims what is left under -54 dB at
    the end, fades in over 1 ms and out over `tail` seconds (so a ring or a
    room dies instead of stopping), matches the loudness and writes 16-bit
    mono at 44.1 kHz like every file above."""
    x = hp(np.asarray(x, float), 25)
    keep = np.nonzero(np.abs(x) > np.max(np.abs(x)) * 10 ** (-54 / 20))[0]
    if len(keep): x = x[:keep[-1] + N(0.02)]
    k = N(0.001); x[:k] *= np.linspace(0, 1, k)
    x = level(fade_tail(x, tail), target)
    pcm = np.round(x * 32767).astype("<i2")
    os.makedirs(OUT, exist_ok=True)
    with wave.open(os.path.join(OUT, f"{name}.wav"), "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes(pcm.tobytes())
    rms = float(np.sqrt(np.mean(x ** 2)))
    print(f"  {name}.wav  {len(x) / SR:5.2f}s  peak {np.max(np.abs(x)):.3f}  rms {rms:.3f}"
          f"  {loudness(x):6.1f} LUFS  {len(pcm) * 2 / 1024:4.0f} KB")

# ---------------------------------------------------------------- recordings

VSCO_REPO = "https://github.com/sgossner/VSCO-2-CE.git"
VSCO_COMMIT = "440300901dfe9275fd84e0b7763af1f8443ae62e"
VSCO_DIR = os.environ.get("VSCO_DIR")

# key: (path in VSCO 2 CE, sounding pitch in Hz or None). The library's names
# are not the pitch you hear — its brass and woodwinds call middle C "C3", and
# a glockenspiel sounds two octaves over its written note — so every pitch
# here was MEASURED off the recording (harmonic peaks over a steady 0.8 s, or
# the 0.12 s after a staccato take's attack; a bar's inharmonic overtones left
# out). Rebuilt from a fresh `--fetch-vsco`, every file came out byte for byte
# the same (2026-09-24). All CC0; see the header above.
VSCO = {
    # heal's glissando and the extra turn's doubling
    "harp_F4": ("Strings/Harp/KSHarp_F4_mf.wav", 348.99),
    "harp_A4": ("Strings/Harp/KSHarp_A4_mf.wav", 437.75),
    "harp_C5": ("Strings/Harp/KSHarp_C5_mf.wav", 519.99),
    "harp_E5": ("Strings/Harp/KSHarp_E5_mf.wav", 654.86),
    "harp_G5": ("Strings/Harp/KSHarp_G5_mf.wav", 781.43),
    "harp_B5": ("Strings/Harp/KSHarp_B5_mf.wav", 982.95),
    "harp_D6": ("Strings/Harp/KSHarp_D6_mf.wav", 1169.70),
    "harp_F6": ("Strings/Harp/KSHarp_F6_mf.wav", 1392.08),
    # the buff, the extra turn, the revive's ping and the level-up's run
    "glock_G5": ("Percussion/Glock/glock_medium_G4.wav", 787.70),
    "glock_C6": ("Percussion/Glock/glock_medium_C5.wav", 1053.65),
    "glock_G6": ("Percussion/Glock/glock_medium_G5.wav", 1578.75),
    "glock_C7": ("Percussion/Glock/glock_medium_C6.wav", 2111.58),
    # the buff's rise (reversed), the extra turn's and level-up's shimmer
    "belltree": ("Percussion/BellTree_Stroke3_v1_Sum.wav", None),
    # the counter's steel
    "anvil": ("Percussion/Anvil_Hit1_v3_Sum.wav", None),
    # the boss's boom, gong and cymbal; the level-up's cymbal and drum
    "bass_drum": ("Percussion/BDrumNewhit_v7_rr1_Sum.wav", None),
    "timpani": ("Percussion/Timpani/Timpani1_Hit_v3_rr1_Sum.wav", 89.68),
    "gong": ("Percussion/gongHit_fff.wav", None),
    "crash": ("Percussion/cymbal-crash1_ff_rr1.wav", None),
    # the Norse and Roman calls, the level-up's horns, the roar's throat
    "horn_D#2": ("Brass/F Horn/sus/MOHorn_sus_D#1_v3_1.wav", 77.63),
    "horn_D3": ("Brass/F Horn/sus/MOHorn_sus_D2_v4_1.wav", 147.35),
    "horn_F3": ("Brass/F Horn/sus/MOHorn_sus_F2_v3_1.wav", 174.05),
    "horn_A3": ("Brass/F Horn/sus/MOHorn_sus_A2_v3_1.wav", 219.48),
    "horn_C4": ("Brass/F Horn/sus/MOHorn_sus_C3_v4_1.wav", 260.61),
    "hornshort_F3": ("Brass/F Horn/stac/MOHorn_stac_F2_v3_rr1.wav", 174.71),
    "hornshort_F3~2": ("Brass/F Horn/stac/MOHorn_stac_F2_v3_rr2.wav", 174.58),
    # short trumpet notes: the level-up's pickups and the Greek call's first
    # two. A "~2" key is the same note's second take (its round robin), so a
    # repeated note is never one recording fired twice.
    "tptshort_G4": ("Brass/Trumpet/stac/Sum_SHTrumpet_stac_G3_v3_rr1.wav", 395.93),
    "tptshort_G4~2": ("Brass/Trumpet/stac/Sum_SHTrumpet_stac_G3_v3_rr2.wav", 394.36),
    "tptshort_A#4": ("Brass/Trumpet/stac/Sum_SHTrumpet_stac_A#3_v3_rr1.wav", 465.48),
    "tptshort_D5": ("Brass/Trumpet/stac/Sum_SHTrumpet_stac_D4_v3_rr1.wav", 589.95),
    "tptshort_F5": ("Brass/Trumpet/stac/Sum_SHTrumpet_stac_F4_v3_rr1.wav", 699.70),
    "tptshort_A5": ("Brass/Trumpet/stac/Sum_SHTrumpet_stac_A4_v3_rr1.wav", 886.69),
    # the Greek and Egyptian calls and the level-up's trumpets
    "tpt_G4": ("Brass/Trumpet/sus/Sum_SHTrumpet_sus_G3_v3_rr1.wav", 393.03),
    "tpt_A#4": ("Brass/Trumpet/sus/Sum_SHTrumpet_sus_A#3_v3_rr1.wav", 466.63),
    "tpt_D5": ("Brass/Trumpet/sus/Sum_SHTrumpet_sus_D4_v3_rr1.wav", 588.29),
    "tpt_F5": ("Brass/Trumpet/sus/Sum_SHTrumpet_sus_F4_v3_rr1.wav", 697.06),
    "tpt_C6": ("Brass/Trumpet/sus/Sum_SHTrumpet_sus_C5_v3_rr1.wav", 1043.57),
    # the Egyptian call's silver trumpet: a harmon mute is the nasal rasp
    "muted_A#4": ("Brass/Trumpet/harmonM-sus/Sum_SHTrumpet_harmonM-sus_A#3_v3_rr1.wav", 466.25),
    "muted_D5": ("Brass/Trumpet/harmonM-sus/Sum_SHTrumpet_harmonM-sus_D4_v3_rr1.wav", 587.64),
    # the Jade Court's suona, played on an oboe and roughened
    "oboe_F5": ("Woodwinds/Oboe/Vib/Oboe_Vib_F4_v3_Main.wav", 699.70),
    # The summon (FEEL.md W2.7, 2026-09-24). String sections in tremolo, the
    # sound of a charge gathering in every film score: the violins are
    # named an octave under what they play (VlnEns "A3" sounds A4), the
    # cellos too. Measured on 0.6 s of steady tremolo 0.25 s in (harmonic
    # product spectrum): the ensemble's pitch wanders a few cents inside a
    # note, so these are its centre.
    "vtrem_D4": ("Strings/Violin Section/Trem/VlnEns_Trem_D3_v1.wav", 294.10),
    "vtrem_F#4": ("Strings/Violin Section/Trem/VlnEns_Trem_F#3_v1.wav", 371.80),
    "vtrem_A4": ("Strings/Violin Section/Trem/VlnEns_Trem_A3_v1.wav", 437.40),
    "vtrem_E5": ("Strings/Violin Section/Trem/VlnEns_Trem_E4_v1.wav", 657.80),
    "vtrem_G5": ("Strings/Violin Section/Trem/VlnEns_Trem_G4_v1.wav", 782.60),
    "vtrem_B5": ("Strings/Violin Section/Trem/VlnEns_Trem_B4_v1.wav", 987.80),
    "vtrem_D6": ("Strings/Violin Section/Trem/VlnEns_Trem_D5_v1.wav", 1173.90),
    "ctrem_D3": ("Strings/Cello Section/trem/trem_D2_v1_1.wav", 147.00),
    "ctrem_A3": ("Strings/Cello Section/trem/trem_A2_v1_1.wav", 218.40),
    # the rise: a real timpani roll (the small drum, about D3) and a
    # suspended cymbal rolled with soft mallets in a crescendo that peaks
    # 3.8 s in; the cymbal's soft single stroke; a triangle for the bells
    "timproll_D3": ("Percussion/Timpani/Rolls/Timpani3_Roll_v5_rr1_Sum.wav", 146.00),
    "susproll": ("VSCO 1 Percussion/varMetal/Cymbals/susp/susp_hit_softmall_roll2_cresc.wav", None),
    "susp_soft": ("VSCO 1 Percussion/varMetal/Cymbals/susp/susp_hit_softmall_mp.wav", None),
    "triangle": ("Percussion/Triangle3-Hit_v2_rr1_Sum.wav", None),
}

def have_vsco(names):
    """True when the recordings are on disk; otherwise says which sounds are
    skipped (the shipped files stay as they are) and how to fetch them."""
    if VSCO_DIR and all(os.path.exists(os.path.join(VSCO_DIR, p)) for p, _ in VSCO.values()):
        return True
    print(f"  skipped {names}: they need the VSCO 2 CE recordings "
          f"(python3 tools/sfx.py --fetch-vsco DIR, then --vsco DIR)")
    return False

def fetch_vsco(dest):
    """A sparse, blobless clone of only the recordings in `VSCO`, pinned to
    `VSCO_COMMIT`: 66 MB where the whole library is gigabytes."""
    import subprocess
    def run(*a, **k): subprocess.run(list(a), check=True, **k)
    run("git", "clone", "--filter=blob:none", "--no-checkout", "--depth", "1", VSCO_REPO, dest)
    run("git", "-C", dest, "sparse-checkout", "init", "--no-cone")
    run("git", "-C", dest, "sparse-checkout", "set", "--no-cone", "--stdin",
        input="".join(f"/{p}\n" for p, _ in VSCO.values()), text=True)
    run("git", "-C", dest, "fetch", "--depth", "1", "--filter=blob:none", "origin", VSCO_COMMIT)
    run("git", "-C", dest, "checkout", VSCO_COMMIT)

_recordings = {}

def recording(key):
    """One recording as mono floats at 44.1 kHz, rumble under 30 Hz removed,
    cut to 2 ms before its onset and scaled to a peak of 1."""
    if key not in _recordings:
        import warnings
        with warnings.catch_warnings():
            warnings.simplefilter("ignore")  # the library's files carry chunks scipy skips
            sr, x = wavfile.read(os.path.join(VSCO_DIR, VSCO[key][0]))
        x = x.astype(float) / (32768.0 if x.dtype == np.int16 else 2147483648.0)
        if x.ndim > 1: x = x.mean(axis=1)
        if sr != SR: x = sps.resample_poly(x, SR, sr)
        x = hp(x, 30)
        a = np.abs(x); on = int(np.argmax(a > 0.02 * a.max()))
        x = x[max(0, on - N(0.002)):]
        _recordings[key] = x / np.max(np.abs(x))
    return _recordings[key].copy()

def repitch(x, ratio):
    """Resampling, which is what a sampler does: `ratio` 2 is an octave up in
    half the time. Every note below stays within about three semitones of its
    recording, where the change of length and timbre is not heard."""
    if abs(ratio - 1) < 1e-5: return x
    from fractions import Fraction
    fr = Fraction(1 / ratio).limit_denominator(240)
    return sps.resample_poly(x, fr.numerator, fr.denominator)

def pitch(name):
    """'A4' -> 440.0; sharps and flats as 'C#5', 'Eb5'."""
    k = {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}[name[0]]; i = 1
    while name[i] in "#b": k += 1 if name[i] == "#" else -1; i += 1
    return 440.0 * 2 ** ((k + 12 * (int(name[i:]) + 1) - 69) / 12)

def played(family, note, dur=None, release=0.08, cents=0.0, take=1, settled=False):
    """One note of an instrument at any pitch, from its nearest recording,
    cut to `dur` seconds with a `release` fade when given. `take` 2 plays the
    note's second recording (a "~2" key) where there is one; `settled` irons
    the pitch out of its attack first (`settle`)."""
    f = (pitch(note) if isinstance(note, str) else note) * 2 ** (cents / 1200)
    keys = [k for k in VSCO if k.startswith(family + "_") and "~" not in k]
    key = min(keys, key=lambda k: abs(math.log(f / VSCO[k][1])))
    if take > 1 and f"{key}~{take}" in VSCO: key = f"{key}~{take}"
    x = settle(key) if settled else recording(key)
    x = repitch(x, f / VSCO[key][1])
    if dur is not None:
        x = fade_tail(x[:min(len(x), N(dur + release))], release)
    return x

def glide(x, ratio):
    """Reads `x` at a speed that changes every output sample — a slide, a
    fall or a vibrato on a recording — from a copy upsampled four times, so
    reading between samples stays clean."""
    up = sps.resample_poly(x, 4, 1)
    pos = np.concatenate([[0.0], np.cumsum(ratio[:-1])]) * 4
    pos = pos[pos < len(up) - 1]
    return np.interp(pos, np.arange(len(up)), up)

_settled = {}

def settle(key, until=0.25):
    """A brass recording with the pitch ironed out of its attack. A trumpet or
    a horn arrives at its note from below: measured here, the G4 sustain
    starts 85 cents flat and takes 100 ms to get there, and even the staccato
    takes dip 30-45 cents for their first 60 ms. In a long note that is
    articulation; in a 70 ms note it IS the note, and the level-up's first
    pickups read a quarter-tone flat. So the pitch is tracked over the first
    `until` seconds (the lag of least difference within 0.7-1.4x of the
    period — YIN's difference function — in 25 ms windows every 5 ms, kept
    only where the window is clearly periodic) and the recording re-read at
    the speed that cancels the error, which leaves the attack's bite and
    takes away its scoop."""
    if key in _settled: return _settled[key].copy()
    x = recording(key); hz0 = VSCO[key][1]
    lo, hi = int(SR / (hz0 * 1.4)), int(SR / (hz0 / 1.4)) + 2
    w = max(N(0.025), 3 * hi); hop = N(0.005)
    times, cents = [], []
    for s in range(0, N(until), hop):
        seg = x[s:s + w + hi]
        if len(seg) < w + hi: break
        a = seg[:w]
        d = np.array([np.sum((a - seg[tau:tau + w]) ** 2) for tau in range(lo, hi)])
        i = int(np.argmin(d))
        if not 0 < i < len(d) - 1 or d[i] > 0.3 * np.mean(d): continue
        shift = 0.5 * (d[i - 1] - d[i + 1]) / (d[i - 1] - 2 * d[i] + d[i + 1])
        times.append(s + w / 2)
        cents.append(float(np.clip(1200 * math.log2(SR / (lo + i + shift) / hz0), -120, 120)))
    if len(cents) < 3:
        _settled[key] = x; return x.copy()
    cents = sps.medfilt(np.array(cents), 5)
    t = np.arange(len(x))
    err = np.interp(t, times, cents, left=cents[0], right=cents[-1])
    err *= np.clip((times[-1] + N(0.05) - t) / N(0.05), 0, 1)   # hand back over 50 ms
    y = glide(x, 2 ** (-err / 1200))
    _settled[key] = y
    return y.copy()

def steady(x, after=0.12, win=0.03):
    """Evens a sustained note's level out after its attack, so the envelope
    put on it is the only one heard: the oboe recordings swell by themselves
    about twice a second."""
    e = np.sqrt(uniform_filter1d(x * x, max(1, N(win))) + 1e-12)
    a = N(after); ref = float(np.median(e[a:a + N(0.5)]))
    ramp = np.clip((T(len(x)) - after) / 0.04, 0, 1)
    return x * ((1 - ramp) + ramp * ref / np.maximum(e, ref * 0.1))

# ==============================================================================
# build_status: what lands on a unit. Heard up to four times in a second when a
# skill buffs a whole team, so every one is short, starts on its first
# millisecond and is shaped to cascade rather than pile up.
# ==============================================================================

def heal():
    # A harp glissando upward through the C major pentatonic, eleven strings
    # in a quarter of a second, the notes growing a little as they climb and
    # ringing longer the higher they are, the top one left to die in a small
    # hall. The pentatonic because a glissando on it has no step that can
    # clash with anything under it.
    b = Bus()
    run = ["G4", "A4", "C5", "D5", "E5", "G5", "A5", "C6", "D6", "E6", "G6"]
    for i, note in enumerate(run):
        k = i / (len(run) - 1)
        b.add(played("harp", note, dur=0.45 + 0.4 * k, release=0.3), 0.025 * i, 0.55 + 0.45 * k ** 0.8)
    save("heal", room(hp(b.x, 160), rt60=1.1, wet=0.26, seed="hall")[:N(1.3)], -14.5, tail=0.4)

def status_shield():
    r = seeded("status_shield")
    # A crystal ring. The barrier forms first: 60 ms of breath climbing to the
    # strike, so the cue reads as something closing round the unit and not as
    # a bell. Then two glass voices a fifth apart. Glass is a few pure, high
    # modes (1 : 2.32 : 4.25 : 6.63 here, not a bar's 2.76 and 5.40, which is
    # the glockenspiel in the buff), each split by a few hertz so it beats:
    # that slow wah is what glass does and a synth bell does not. Half a
    # second of ring, so four shields in a row cascade instead of piling up.
    b = Bus()
    n = N(0.09)
    b.add(travel(r.standard_normal(n), [(0, 3000), (1, 9000)], q=1.2) * shape(n, [(0, 0), (0.07, 1), (0.09, 0)]), 0.0, 0.30)
    b.add(click(r, 0.003, 0.0012, 12000, 3000), 0.06, 0.45)
    b.add(modes(1.1, 1760, (1, 2.32, 4.25, 6.63), (0.5, 0.3, 0.18, 0.1), (1, 0.32, 0.14, 0.06), split=2.6, rng=r), 0.06)
    b.add(modes(1.1, 2637, (1, 2.32, 4.25), (0.4, 0.22, 0.12), (1, 0.25, 0.08), split=3.4, rng=r), 0.085, 0.45)
    save("status_shield", room(b.x, rt60=1.2, wet=0.3, seed="glass")[:N(1.1)], -14.5, tail=0.35)

def status_buff():
    # A rising chime: C6 E6 G6 C7 on a real glockenspiel, 32 ms apart, so it
    # answers on its first millisecond; under it the bell tree's first strokes
    # played backwards, a tenth of a second of shimmer swelling into the top
    # note; a harp C and G under it for warmth; after it the bell tree
    # forwards and quiet, the sparkle that hangs. Up, major and bright,
    # against the debuff's down, sour and dark.
    b = Bus()
    tree = hp(recording("belltree"), 1200)
    b.add(tree[:N(0.11)][::-1] * shape(N(0.11), [(0, 0), (0.11, 1)]) ** 2, 0.0, 0.45)
    for i, (note, g) in enumerate([("C6", 0.55), ("E6", 0.65), ("G6", 0.8), ("C7", 1.0)]):
        b.add(played("glock", note, dur=0.75 - 0.05 * i, release=0.25), 0.032 * i, g)
    b.add(played("harp", "C5", dur=0.5, release=0.3), 0.0, 0.3)
    b.add(played("harp", "G5", dur=0.5, release=0.3), 0.032, 0.25)
    b.add(tree[:N(1.0)], 0.1, 0.16)
    save("status_buff", room(b.x, rt60=0.9, wet=0.18, seed="small")[:N(1.0)], -14.5, tail=0.4)

def status_debuff():
    r = seeded("status_debuff")
    # A falling dissonant pair: E5 sliding to C#5, then, 75 ms behind it, A#4
    # sliding to G4 — a tritone apart, both falling, on a sour FM tone (the
    # modulator at 1.41 of the carrier puts its partials between the
    # harmonics) whose filter closes as it sinks. A soft low thud under it
    # gives it somewhere to land.
    b = Bus()
    def sour(f0, f1, dur):
        n = N(dur); t = T(n)
        f = f1 + (f0 - f1) * np.exp(-t / 0.09)
        ph = 2 * np.pi * np.cumsum(f) / SR
        v = np.sin(ph + (0.5 + 1.7 * np.exp(-t / 0.12)) * np.sin(1.41 * ph))
        return fade_tail(travel(v * fall(n, 0.2, 0.005), [(0, 4200), (1, 700)], q=0.7, kind="lp"), 0.25)
    b.add(sour(pitch("E5"), pitch("C#5"), 0.72), 0.0, 1.0)
    b.add(sour(pitch("A#4"), pitch("G4"), 0.72), 0.075, 0.85)
    b.add(drop(0.4, 150, 62, 0.04, 0.09, attack=0.004), 0.0, 0.5)
    save("status_debuff", room(b.x, rt60=0.8, wet=0.16, seed="small")[:N(0.8)], -14.5, tail=0.25)

def status_stun():
    r = seeded("status_stun")
    # Stunned, and not cartoon-dizzy (the owner wants the serious look): a
    # dull blow (a knock at 900 -> 450 Hz over the thud, since a phone plays
    # nothing of a thud under 200), a crackle of the lightning its icon
    # shows, and the ringing in the ears after — two tones 11 Hz apart so
    # they wobble, sagging 8% as they fade. The ring sits at 2.3 kHz, where a
    # phone speaker is clear but it cannot pierce.
    b = Bus()
    b.add(click(r, 0.005, 0.002, 4500, 300), 0.0, 0.8)
    b.add(drop(0.35, 190, 55, 0.03, 0.07, wave="tri"), 0.0, 1.0)
    b.add(drop(0.2, 900, 450, 0.02, 0.045, wave="tri"), 0.0, 0.6)
    n = N(0.2)
    sparks = np.convolve((r.random(n) < 0.004).astype(float), np.exp(-T(N(0.004)) / 0.0008), mode="same")
    buzz = np.sign(np.sin(2 * np.pi * 100 * T(n)))
    b.add(bp(r.standard_normal(n), 1500, 7000) * (1.5 * sparks + 0.2 * buzz + 0.1) * fall(n, 0.06, 0.004), 0.01, 0.7)
    n = N(0.9); t = T(n); sag = 1 - 0.08 * (1 - np.exp(-t / 0.35))
    ring = tone(2350 * sag, n) + tone(2361 * sag, n) + 0.25 * tone(4710 * sag, n)
    b.add(ring * fall(n, 0.28, 0.02) * (1 - 0.3 * (0.5 + 0.5 * np.sin(2 * np.pi * 6.5 * t))), 0.03, 0.22)
    save("status_stun", room(b.x, rt60=0.7, wet=0.15, seed="small")[:N(0.9)], -14.5, tail=0.3)

def status_freeze():
    r = seeded("status_freeze")
    # Ice forming, not ice breaking: a crisp crack with the crunch of ice
    # taking hold under it (350 Hz - 1.4 kHz; without it nothing in the
    # sound was under 2 kHz), then a hundred and forty tiny glass pings
    # spreading over a third of a second (thick in the middle, as a frost
    # front is), a cold breath whose band sinks from 9 kHz to 3.5 (kept low:
    # at its first level it read as hiss), a high glass chord that locks and
    # hangs, and one last clink.
    b = Bus()
    b.add(click(r, 0.003, 0.001, 14000, 3500), 0.0, 0.9)
    b.add(hp(r.standard_normal(N(0.015)), 3000) * fall(N(0.015), 0.004), 0.0, 0.5)
    n = N(0.3)
    b.add(bp(r.standard_normal(n), 350, 1400) * shape(n, [(0, 0), (0.012, 1), (0.3, 0)]) ** 2, 0.0, 0.55)
    b.add(drop(0.2, 900, 420, 0.02, 0.05, wave="tri"), 0.0, 0.35)
    for _ in range(140):
        at = 0.36 * r.beta(2.0, 3.0); f = r.uniform(3200, 9000)
        m = N(r.uniform(0.004, 0.014))
        b.add(tone(f, m, r.uniform(0, 6.28)) * np.exp(-T(m) / (m / SR / 3)), at, r.uniform(0.05, 0.2))
    n = N(0.7)
    b.add(travel(r.standard_normal(n), [(0, 9000), (1, 3500)], q=1.1) * fall(n, 0.2, 0.03), 0.0, 0.14)
    b.add(modes(1.0, 2489, (1, 1.335, 1.78), (0.45, 0.35, 0.3), (1, 0.7, 0.5), split=3.1, rng=r) * fall(N(1.0), 0.4, 0.08), 0.05, 0.24)
    b.add(modes(0.65, 5200, (1, 2.32), (0.12, 0.06), (1, 0.3), rng=r), 0.37, 0.35)
    save("status_freeze", room(b.x, rt60=0.9, wet=0.2, seed="glass")[:N(1.0)], -14.5, tail=0.35)

def status_burn():
    r = seeded("status_burn")
    # Fire catching: a low whump, the fwoosh of a flame taking (noise under a
    # band that jumps from 350 Hz to 2.8 kHz and settles at 900), then crackle
    # and a sizzle kept under 9 kHz. `impact_ember` is the blow of a fire
    # skill; this is the burn left behind, so it is lighter and hisses.
    b = Bus()
    b.add(drop(0.4, 160, 55, 0.05, 0.09, attack=0.008), 0.0, 0.8)
    n = N(0.8)
    b.add(travel(r.standard_normal(n), [(0, 350), (0.2, 2800), (1, 900)], q=0.7) * fall(n, 0.2, 0.03), 0.0, 1.0)
    b.add(pops(r, 0.7, 50, 1500, 7000), 0.04, 0.9)
    n = N(0.75)
    b.add(lp(hp(r.standard_normal(n), 4000), 9000) * np.abs(smooth_noise(r, n, 40)) * fall(n, 0.22, 0.02), 0.05, 0.45)
    save("status_burn", room(b.x, rt60=0.7, wet=0.14, seed="small")[:N(0.8)], -14.5, tail=0.3)

def status_provoke():
    r = seeded("status_provoke")
    # A taunt: a sword hilt beaten twice on a bronze-faced shield, the second
    # blow harder, and a low snarl under the second. Two blows because one
    # would be a block (`block.wav`); the snarl is a band-limited sawtooth
    # roughened at about 35 Hz and shaped to an "o", kept under the blows.
    b = Bus()
    def bash(g):
        x = Bus()
        x.add(click(r, 0.004, 0.0018, 6000, 400), 0.0, 0.9)
        x.add(drop(0.2, 230, 120, 0.02, 0.05, wave="tri"), 0.0, 1.0)
        x.add(modes(0.5, 410, (1, 2.32, 3.87, 5.21), (0.12, 0.09, 0.07, 0.05), (0.6, 0.5, 0.4, 0.3), rng=r), 0.0, 0.8)
        x.add(lp(r.standard_normal(N(0.2)), 2500) * fall(N(0.2), 0.04), 0.0, 0.3)
        return x.x * g
    b.add(bash(0.8), 0.0)
    b.add(bash(1.0), 0.15)
    n = N(0.45); t = T(n)
    f0 = shape(n, [(0, 105), (0.12, 124), (0.45, 92)]) * (1 + 0.02 * smooth_noise(r, n, 10))
    src = saw(f0, n) * (1 + 0.6 * smooth_noise(r, n, 35)) + 0.3 * hp(r.standard_normal(n), 300)
    snarl = formants(src, [(450, 90, 0), (800, 100, -5), (2830, 150, -18)])
    snarl = np.tanh(2.2 * snarl / (np.max(np.abs(snarl)) + 1e-9)) * shape(n, [(0, 0), (0.05, 1), (0.25, 0.7), (0.45, 0)])
    b.add(snarl, 0.14, 0.3)
    save("status_provoke", room(b.x, rt60=0.7, wet=0.15, seed="small")[:N(0.75)], -14.5, tail=0.25)

def status_bomb():
    r = seeded("status_bomb")
    # A bomb set: an iron shell clanked down, the fuse struck (a burst of
    # scratch and sparks), the fuse fizzing, and a clock's tick and tock
    # under it — the one status whose sound says "later".
    b = Bus()
    b.add(click(r, 0.003, 0.0012, 9000, 900), 0.0, 0.8)
    b.add(modes(0.4, 780, (1, 2.7, 5.1), (0.09, 0.06, 0.035), (0.8, 0.45, 0.25), rng=r), 0.0, 1.0)
    b.add(drop(0.12, 300, 150, 0.01, 0.03), 0.0, 0.5)
    n = N(0.08)
    b.add(bp(r.standard_normal(n), 2000, 8000) * fall(n, 0.02, 0.004), 0.07, 0.6)
    b.add(pops(r, 0.08, 14, 2500, 9000, bias=1.0), 0.07, 0.8)
    n = N(0.6)
    fizz = bp(r.standard_normal(n), 3000, 7000) * (0.5 + 0.5 * np.abs(smooth_noise(r, n, 60)))
    b.add(fizz * shape(n, [(0, 0), (0.03, 1), (0.4, 0.7), (0.6, 0)]), 0.1, 0.35)
    b.add(pops(r, 0.55, 30, 3000, 9000, bias=1.0), 0.1, 0.45)
    for at, f in ((0.26, 1650), (0.46, 1150)):
        b.add(modes(0.08, f, (1, 2.4), (0.008, 0.005), (1, 0.4)), at, 0.55)
        b.add(click(r, 0.002, 0.0008, 8000, 1500), at, 0.17)
    save("status_bomb", room(b.x, rt60=0.6, wet=0.12, seed="small")[:N(0.8)], -14.5, tail=0.25)

def build_status():
    _need()
    status_shield(); status_debuff(); status_stun(); status_freeze()
    status_burn(); status_provoke(); status_bomb()
    if have_vsco("heal, status_buff"):
        heal(); status_buff()

# ==============================================================================
# build_flow: the turns and the fight around them.
# ==============================================================================

def counter():
    r = seeded("counter")
    # A steel sting: a blade drawn fast along a blade (a resonant band
    # climbing 2.5 -> 7 kHz in 60 ms) into a real anvil struck, raised two
    # semitones, cut short so it is a parry and not a forge and taken down
    # over 7 kHz, with two synthesised steel rings (1.45 and 2.9 kHz) and a
    # short knock under it. The anvil alone put 81% of the sound over 6 kHz,
    # a whistle rather than a clash.
    b = Bus()
    n = N(0.07)
    b.add(travel(r.standard_normal(n), [(0, 2500), (1, 7000)], q=4.0) * shape(n, [(0, 0), (0.05, 1), (0.07, 0.2)]), 0.0, 0.4)
    anvil = fade_tail(lp(hp(repitch(recording("anvil"), 2 ** (2 / 12)), 500), 7000)[:N(0.75)], 0.4)
    b.add(anvil, 0.055, 0.7)
    b.add(modes(0.75, 1450, (1, 2.44, 4.1), (0.22, 0.12, 0.07), (1, 0.45, 0.2), split=3.0, rng=r), 0.055, 0.8)
    b.add(modes(0.75, 2900, (1, 2.76, 5.4), (0.3, 0.18, 0.1), (0.5, 0.3, 0.15), split=4.0, rng=r), 0.055, 0.35)
    b.add(drop(0.12, 420, 210, 0.015, 0.035, wave="tri"), 0.055, 0.5)
    save("counter", room(b.x, rt60=0.8, wet=0.15, seed="small")[:N(0.8)], -12, tail=0.3)

def extra_turn():
    # A reward, not a status: three notes on the glockenspiel, G5 C6 E6 in a
    # "da-da-DING" 90 ms apart, a harp doubling them an octave down and well
    # under them (at a third of the glockenspiel it still out-rang the top
    # note), and the bell tree's shimmer blooming off the last. The buff
    # runs four notes in a blur; this one is a tune you could hum.
    b = Bus()
    for i, (note, low, g) in enumerate([("G5", "G4", 0.7), ("C6", "C5", 0.8), ("E6", "E5", 1.0)]):
        last = i == 2
        b.add(played("glock", note, dur=1.0 if last else 0.18, release=0.35 if last else 0.06), 0.09 * i, g)
        b.add(played("harp", low, dur=0.45 if last else 0.2, release=0.3 if last else 0.08), 0.09 * i, 0.15 * g)
    b.add(hp(recording("belltree"), 1500)[:N(1.2)], 0.18, 0.3)
    save("extra_turn", room(b.x, rt60=1.0, wet=0.2, seed="hall")[:N(1.3)], -12, tail=0.45)

# The Csound manual's formant table for the vowel "a", per voice part:
# (Hz, bandwidth Hz, dB).
_AH = {
    "bass":    [(600, 60, 0), (1040, 70, -7), (2250, 110, -9), (2450, 120, -9), (2750, 130, -20)],
    "tenor":   [(650, 80, 0), (1080, 90, -6), (2650, 120, -7), (2900, 130, -8), (3250, 140, -22)],
    "alto":    [(800, 80, 0), (1150, 90, -4), (2800, 120, -20), (3500, 130, -36), (4950, 140, -60)],
    "soprano": [(800, 80, 0), (1150, 90, -6), (2900, 120, -32), (3900, 130, -20), (4950, 140, -50)],
}

def choir_part(r, part, notes, n, voices=4):
    """One section singing "ah": `voices` singers, each a sawtooth softened
    above 2.2 kHz (a sung, not a buzzed, source) through the part's formants
    with a breath of noise, their own vibrato (5-6 Hz, fading in after
    0.25 s), a slow drift and a few cents of detune, which is what turns one
    synthetic voice into a section. `notes` is [(seconds, Hz), ...], slid
    between."""
    t = T(n); out = np.zeros(n)
    base = np.interp(t, [a for a, _ in notes], [f for _, f in notes])
    for v in range(voices):
        detune = 2 ** (r.uniform(-7, 7) / 1200)
        vib = 2 ** ((18 / 1200) * np.sin(2 * np.pi * r.uniform(5.0, 6.0) * t + r.uniform(0, 6.28))
                    * np.clip((t - 0.25) / 0.4, 0, 1))
        drift = 2 ** ((6 / 1200) * smooth_noise(r, n, 2))
        f0 = base * detune * vib * drift
        src = lp(saw(f0, n), 2200, 1) + 0.05 * r.standard_normal(n)
        out += formants(src, _AH[part])
    return out / voices

def revive():
    r = seeded("revive")
    # A choir swelling on "ah" from nothing, a suspended chord (the alto on
    # F4) that resolves to C major as the unit stands (the alto slides to E4
    # at 0.6 s): coming back reads as a question answered. The bell tree,
    # reversed, rises into that moment and a single glockenspiel note marks
    # it; a descant G5 enters above. Then it lets go in a long hall. The
    # swell is heard within 50 ms (it took 270 at first, while the unit was
    # visibly getting up) and full by 0.5 s.
    n = N(1.95); choir = Bus()
    choir.add(choir_part(r, "bass", [(0, pitch("C3"))], n), 0.0, 1.0)
    choir.add(choir_part(r, "tenor", [(0, pitch("G3"))], n), 0.0, 0.85)
    choir.add(choir_part(r, "alto", [(0, pitch("F4")), (0.55, pitch("F4")), (0.65, pitch("E4"))], n), 0.0, 0.8)
    choir.add(choir_part(r, "soprano", [(0, pitch("C5"))], n), 0.0, 0.75)
    choir.add(choir_part(r, "soprano", [(0, pitch("G5"))], N(1.35)) * shape(N(1.35), [(0, 0), (0.3, 1), (1.35, 1)]), 0.6, 0.35)
    voices = choir.x[:n] / np.max(np.abs(choir.x))
    b = Bus()
    b.add(voices * shape(n, [(0, 0), (0.5, 1.0), (1.35, 1.0), (1.95, 0.0)]) ** 1.2, 0.0, 1.0)
    tree = hp(recording("belltree"), 1500)
    b.add(tree[:N(0.6)][::-1] * shape(N(0.6), [(0, 0), (0.6, 1)]) ** 2, 0.0, 0.3)
    b.add(played("glock", "C7", dur=1.0, release=0.4), 0.6, 0.3)
    save("revive", room(b.x, rt60=2.0, wet=0.35, seed="hall")[:N(2.05)], -12, tail=0.5)

def death():
    r = seeded("death")
    # A fall, then the soul leaving. The killing blow has already landed
    # (`hit_lethal`), so the fall is soft: a body meeting stone, a rattle of
    # armour, no transient to speak of. Then a breath rising — noise in a
    # narrow band climbing 350 Hz -> 3.8 kHz — with a ghostly tone gliding
    # up an octave and a half on three detuned voices, gone into the hall by
    # 1.3 s.
    b = Bus()
    b.add(drop(0.45, 110, 42, 0.04, 0.11, attack=0.003), 0.05, 0.7)
    b.add(lp(r.standard_normal(N(0.3)), 300) * fall(N(0.3), 0.07, 0.004), 0.05, 0.45)
    for _ in range(7):
        b.add(modes(0.06, r.uniform(1800, 4200), (1, 2.7), (0.012, 0.006), (1, 0.4), rng=r), 0.05 + r.uniform(0, 0.16), r.uniform(0.1, 0.25))
    n = N(1.1); t = T(n)
    b.add(travel(r.standard_normal(n), [(0, 350), (0.6, 2600), (1, 3800)], q=2.5)
          * shape(n, [(0, 0), (0.28, 1), (1.1, 0)]), 0.18, 0.45)
    f = shape(n, [(0, 330), (1.1, 990)])
    ghost = sum(tone(f * 2 ** (c / 1200) * (1 + 0.004 * np.sin(2 * np.pi * 6 * t + c)), n) for c in (-8, 0, 8)) / 3
    b.add(ghost * shape(n, [(0, 0), (0.25, 1), (0.6, 0.5), (1.1, 0)]), 0.2, 0.32)
    save("death", room(b.x, rt60=1.6, wet=0.35, seed="hall")[:N(1.35)], -12, tail=0.4)

def turn_chime():
    r = seeded("turn_chime")
    # The player's turn: one soft note, a vibraphone's A5 with a felt mallet.
    # A tuned bar rings at 1 : 4 : 10 (3.93 and 9.2 here) and the upper two
    # die fast, so what is left is nearly a sine; the motor's 5.4 Hz tremolo
    # keeps it from sounding like a test tone. Heard every turn, so it has no
    # attack to speak of, nothing above 6 kHz, and it is gone in a second.
    n = N(1.1); t = T(n)
    x = modes(1.1, 880, (1, 3.93, 9.2), (0.4, 0.12, 0.05), (1, 0.12, 0.03), rng=r)
    x *= shape(n, [(0, 0), (0.006, 1), (1.1, 1)]) * (1 - 0.12 * (0.5 + 0.5 * np.sin(2 * np.pi * 5.4 * t)))
    save("turn_chime", room(lp(x, 6000), rt60=0.8, wet=0.15, seed="small")[:N(1.05)], -15, tail=0.4)

# ----------------------------------------------------------------- horn calls

def _call_note(family, note, dur, release=0.1, swell=None, fall_st=0.0, fall_len=0.15, cents=0.0,
               take=1, settled=False):
    """One note of a horn call: the recording at pitch, cut to `dur` with a
    release, an optional swell [(seconds, level), ...] and an optional fall
    of `fall_st` semitones over its last `fall_len` seconds — the lip letting
    go that ends a call. `take` and `settled` as `played`: every note under
    about 150 ms is a staccato take with its attack settled."""
    x = played(family, note, cents=cents, take=take, settled=settled)
    n = min(len(x), N(dur + release))
    if fall_st:
        t = T(n); start = dur + release - fall_len
        k = np.clip((t - start) / fall_len, 0, 1) ** 2
        x = glide(x, 2 ** (-fall_st * k / 12))[:n]
    x = fade_tail(x[:n], release)
    if swell: x *= shape(len(x), swell)
    return x

def wave_egypt():
    # The Duat: Tutankhamun was buried with two trumpets, one silver and one
    # bronze, so this is a pair — a harmon-muted trumpet for the silver's
    # nasal rasp, an open one filtered dark for the bronze — sounding A4,
    # then D5 through a grace note a semitone above it (D#5), the Hijaz
    # colour the island's music is written in, and a fall to end it.
    b = Bus()
    for fam, g, tone_ in (("muted", 1.0, None), ("tpt", 0.45, 2200)):
        v = Bus()
        v.add(_call_note(fam, "A4", 0.2, 0.06), 0.0)
        v.add(_call_note(fam, "D#5", 0.05, 0.03), 0.22, 0.8)
        v.add(_call_note(fam, "D5", 0.75, 0.12, swell=[(0, 0.8), (0.4, 1.0), (0.9, 1.0)], fall_st=1.5, fall_len=0.2), 0.27)
        b.add(lp(v.x, tone_) if tone_ else v.x, 0.0, g)
    save("wave_egypt", room(b.x, rt60=1.8, wet=0.28, seed="stone")[:N(1.8)], -10, tail=0.45)

def wave_greece():
    # Olympus: the salpinx, a straight bronze war trumpet, on the open
    # trumpet: C5, G5, C6 — up a fifth and an octave, the simplest heroic
    # call, the first two staccato with their attacks settled — doubled 3
    # cents sharp and 12 ms late, two trumpeters, in open
    # air (a light room with a longer pre-delay). At 7 cents the pair beat
    # four times a second on the long C6, which read as a tremolo.
    b = Bus()
    for cents, at, g in ((0.0, 0.0, 1.0), (3.0, 0.012, 0.6)):
        b.add(_call_note("tptshort", "C5", 0.14, 0.05, cents=cents, settled=True), at, g)
        b.add(_call_note("tptshort", "G5", 0.14, 0.05, cents=cents, settled=True), at + 0.17, g)
        b.add(_call_note("tpt", "C6", 0.75, 0.15, swell=[(0, 0.85), (0.35, 1.0), (0.9, 1.0)], cents=cents), at + 0.34, g)
    save("wave_greece", room(b.x, rt60=1.3, wet=0.25, pre=0.025, seed="open")[:N(1.6)], -10, tail=0.4)

def wave_norse():
    # Yggdrasil: a war horn — one long low D3 swelling, then up a fifth to A3
    # with a fall. Under it a quiet sine an octave down for the size of an
    # animal's horn (quiet, because a phone cannot play it and it would spend
    # the headroom), and a rasp (the horn itself driven hard through
    # 300-2500 Hz), in a fjord-sized hall. The slowest of the five calls, as a
    # horn that big is.
    b = Bus()
    d = _call_note("horn", "D3", 0.8, 0.12, swell=[(0, 0.5), (0.5, 1.0), (0.92, 1.0)])
    a = _call_note("horn", "A3", 0.62, 0.15, swell=[(0, 0.9), (0.2, 1.0), (0.77, 1.0)], fall_st=1.0, fall_len=0.22)
    b.add(d, 0.0); b.add(a, 0.72)
    for x, f, at in ((d, pitch("D2"), 0.0), (a, pitch("A2"), 0.72)):
        env = np.sqrt(uniform_filter1d(x * x, N(0.03)))
        b.add(tone(f, len(x)) * env / (np.max(env) + 1e-9), at, 0.2)
    b.add(np.tanh(3.0 * bp(b.x, 300, 2500) / (np.max(np.abs(b.x)) + 1e-9)), 0.0, 0.18)
    save("wave_norse", room(b.x, rt60=2.3, wet=0.3, seed="fjord")[:N(1.9)], -10, tail=0.5)

def wave_rome():
    # The Seven Hills: a legion's cornu, the big round horn that gave the
    # signals — three short G3s tongued in a triplet (the horn's two
    # staccato takes in turn, their attacks settled) and a long C4, the
    # repeated-note rhythm of a military signal (the Greek call climbs; this
    # one drives). The long note is doubled an octave down.
    b = Bus()
    for i in range(3):
        b.add(_call_note("hornshort", "G3", 0.09, 0.04, take=1 + i % 2, settled=True), 0.13 * i, 0.85 + 0.05 * i)
    b.add(_call_note("horn", "C4", 0.72, 0.15, swell=[(0, 0.8), (0.3, 1.0), (0.87, 1.0)], fall_st=0.7, fall_len=0.18), 0.39)
    b.add(_call_note("horn", "C3", 0.72, 0.15, swell=[(0, 0.8), (0.3, 1.0), (0.87, 1.0)]), 0.40, 0.45)
    save("wave_rome", room(b.x, rt60=1.5, wet=0.26, seed="stone")[:N(1.6)], -10, tail=0.4)

def wave_jade():
    r = seeded("wave_jade")
    # The Jade Court: first the small Peking-opera gong whose pitch RISES as
    # it rings (the "jiang" of the xiaoluo), then a suona — the double-reed
    # horn of every Chinese procession — played on an oboe, driven hard and
    # lifted over 2 kHz, with a synthesised reed buzz on the same pitch, the
    # slides and the vibrato included, because a suona's upper harmonics are
    # nearly as loud as its first and an oboe's are not (the oboe alone put
    # 98% of the call between 500 Hz and 2 kHz): D5, a slide to E5, a leap to
    # A5 with a wide vibrato, and a fall. Pentatonic, as the instrument's
    # calls are.
    b = Bus()
    b.add(click(r, 0.003, 0.0012, 9000, 1500), 0.0, 0.6)
    b.add(modes(1.6, 640, (1, 1.58, 2.46, 3.51, 4.3), (0.5, 0.32, 0.2, 0.14, 0.09),
                (1, 0.55, 0.4, 0.25, 0.15), glide_to=1.12, glide_tau=0.12, rng=r), 0.0, 0.8)
    base = VSCO["oboe_F5"][1]
    n = N(1.25); t = T(n)
    steps = [(0.0, pitch("D5")), (0.13, pitch("D5")), (0.18, pitch("E5")), (0.28, pitch("E5")),
             (0.34, pitch("A5")), (1.02, pitch("A5")), (1.2, pitch("G5"))]
    target = np.interp(t, [a for a, _ in steps], [f for _, f in steps])
    vib = 2 ** ((32 / 1200) * np.sin(2 * np.pi * 6.2 * t) * np.clip((t - 0.45) / 0.15, 0, 1))
    reed = glide(steady(recording("oboe_F5")), target * vib / base)[:n]
    reed = reed + 1.2 * hp(reed, 2000)
    reed = 0.35 * reed + 0.65 * np.tanh(3.2 * reed / (np.max(np.abs(reed)) + 1e-9))
    # The buzz: every harmonic to 6 kHz at 1/sqrt(k) (a sawtooth's 1/k is
    # an oboe; a suona is brighter than a trumpet) on the same pitch, through
    # the nasal formants at 1.6, 2.8 and 4.2 kHz.
    f = target * vib
    phase = 2 * np.pi * np.cumsum(f) / SR
    buzz = sum(np.sin(k * phase) / k ** 0.5 for k in range(1, int(6000 / f.max()) + 1))
    buzz = reson(buzz, 1600, 4) + 0.8 * reson(buzz, 2800, 5) + 0.4 * reson(buzz, 4200, 6)
    m = min(len(reed), n)
    voice = reed[:m] / np.max(np.abs(reed)) + 0.6 * buzz[:m] / np.max(np.abs(buzz))
    voice *= shape(m, [(0, 0), (0.02, 1), (1.05, 1), (1.25, 0)])
    b.add(voice, 0.1, 0.9)
    save("wave_jade", room(b.x, rt60=1.4, wet=0.22, seed="open")[:N(1.65)], -10, tail=0.45)

# ------------------------------------------------------------------ the boss

def boss_arrival():
    r = seeded("boss_arrival")
    # Boom, roar, cymbal — the first cut's synthesised roar was a distorted
    # buzz, so the roar is the orchestra's: four horns on D2 D3 F3 A3, a D
    # minor chord, swelling in over 140 ms and blown past their limit (a
    # tanh on the chord), the cinematic "braaam" that trailers use for a
    # threat, with a growl under it for a throat — a sawtooth whose pitch
    # wanders 6% at 25 Hz, amplitude-modulated at half its own pitch (the
    # period doubling that separates a roar from a hum), through two
    # formants opening "o" -> "a". Under all of it the boom: the bass drum
    # and a low timpani struck together over a sub falling 62 -> 28 Hz; with
    # it the tam-tam, a bright crack and a crash cymbal at full level, and
    # the chord cut 5 dB at 320 Hz with its edge over 2 kHz lifted: at a
    # third of the level, 2% of the sound through a phone's speaker was
    # over 2 kHz, where the shipped heavy hits have 10-22%, and a phone
    # would have played a muddy chord.
    b = Bus()
    boom = Bus()
    boom.add(click(r, 0.008, 0.0035, 5000, 200), 0.0, 0.8)
    boom.add(recording("bass_drum")[:N(2.2)], 0.0, 1.0)
    boom.add(recording("timpani")[:N(2.2)], 0.0, 0.7)
    boom.add(drop(1.6, 62, 28, 0.25, 0.45, attack=0.003), 0.0, 0.5)
    bx = lp(boom.x, 3500)
    b.add(np.tanh(1.6 * bx / np.max(np.abs(bx))), 0.0, 0.7)
    b.add(hp(recording("gong"), 80)[:N(2.4)], 0.0, 0.35)
    b.add(hp(recording("crash"), 400)[:N(2.2)], 0.015, 1.0)
    b.add(click(r, 0.006, 0.0025, 12000, 2500), 0.0, 0.5)
    chord = Bus()
    for note, g in (("D2", 1.0), ("D3", 0.9), ("F3", 0.75), ("A3", 0.7)):
        chord.add(_call_note("horn", note, 1.05, 0.45, swell=[(0, 0.35), (0.14, 1.0), (0.7, 0.9), (1.5, 0.8)]), 0.0, g)
    c = chord.x / np.max(np.abs(chord.x))
    c = lp(0.6 * c + 0.4 * np.tanh(2.8 * c), 5000)
    c = c - 0.45 * reson(c, 320, 1.0) + 0.5 * hp(c, 2000)   # the mud out, the brass's edge up
    b.add(c, 0.07, 0.95)
    n = N(1.35); t = T(n)
    contour = shape(n, [(0, 70), (0.3, 92), (0.8, 84), (1.35, 60)])
    f0 = contour * (1 + 0.06 * smooth_noise(r, n, 25))
    sub_am = 1 + 0.5 * np.sin(np.pi * np.cumsum(f0) / SR)
    src = (lp(saw(f0, n), 1800, 1) * sub_am * (1 + 0.6 * np.clip(smooth_noise(r, n, 45), -1, 1))
           + 0.5 * bp(r.standard_normal(n), 200, 3000))
    throat = (travel(src, [(0, 520), (0.25, 720), (1, 470)], q=3.0)
              + 0.7 * travel(src, [(0, 900), (0.25, 1150), (1, 800)], q=4.0))
    throat = np.tanh(2.0 * throat / (np.max(np.abs(throat)) + 1e-9)) * shape(n, [(0, 0), (0.15, 1), (0.8, 0.8), (1.35, 0)])
    b.add(throat, 0.1, 0.3)
    save("boss_arrival", room(b.x, rt60=2.2, wet=0.25, seed="hall")[:N(2.3)], -9.5, tail=0.6)

# ------------------------------------------------------------------- level up

def level_up():
    # The player's level-up (FEEL.md W1.6): a fanfare. Three trumpet G4s in a
    # triplet pickup (the two staccato takes in turn, their attacks settled,
    # because the sustain's scoop made them a quarter-tone flat), then on the
    # downbeat (0.3 s) a C major chord — three
    # trumpets on C5 E5 G5 over three horns on E3 G3 C4 a hair behind them —
    # swelling for a second and let go, with the glockenspiel running C6 E6
    # G6 C7 over it, the bell tree, a crash cymbal kept back to a shimmer and
    # a bass drum with a sub on C2 for the floor. Bigger than the extra turn,
    # shorter than a cutscene.
    b = Bus()
    for i in range(3):
        b.add(_call_note("tptshort", "G4", 0.07, 0.03, take=1 + i % 2, settled=True), 0.095 * i, 0.75 + 0.05 * i)
    hold = [(0, 0.85), (0.6, 1.0), (1.1, 1.0)]
    for note in ("C5", "E5", "G5"):
        b.add(_call_note("tpt", note, 0.95, 0.35, swell=hold), 0.3, 0.7)
    for note in ("E3", "G3", "C4"):
        b.add(_call_note("horn", note, 0.95, 0.35, swell=hold), 0.315, 0.55)
    for i, note in enumerate(("C6", "E6", "G6", "C7")):
        b.add(played("glock", note, dur=0.8, release=0.4), 0.31 + 0.045 * i, 0.5)
    b.add(hp(recording("belltree"), 1500)[:N(1.4)], 0.3, 0.3)
    b.add(hp(recording("crash"), 500)[:N(1.6)], 0.29, 0.4)
    b.add(recording("bass_drum")[:N(1.6)], 0.3, 0.3)
    b.add(drop(1.2, 70, pitch("C2"), 0.05, 0.35, attack=0.004), 0.3, 0.25)
    save("level_up", room(b.x, rt60=1.6, wet=0.25, seed="hall")[:N(2.0)], -9.5, tail=0.5)

def build_flow():
    _need()
    death(); turn_chime()
    if have_vsco("counter, extra_turn, revive, wave_*, boss_arrival, level_up"):
        counter(); extra_turn(); revive()
        wave_egypt(); wave_greece(); wave_norse(); wave_rome(); wave_jade()
        boss_arrival(); level_up()

# ==============================================================================
# build_summon: the summon that climbs with the grade (FEEL.md W2.7,
# 2026-09-24). One file played at two volumes was the whole summon; now the
# charge is three stems laid on the ladder's own rungs (`ChargeLadder.stems`
# in SummonRevealView.swift) and the burst is the grade's:
#
#   summon_ignite            the scroll catching light at the summon button
#   summon_charge_base       every pull, from the charge's first frame
#   summon_charge_rise       a 4★ or better, from the violet rung (0.44 s)
#   summon_charge_tell       a 5★ alone, from the gold rung (0.88 s)
#   summon_charge_lightdark  the Light & Dark scroll, from the first frame
#   summon_burst_3/_4/_5     the flash: a chime, a brass stab, a gong and choir
#   star_1 … star_6          the stars climbing a glockenspiel's scale
#   rite_awaken / _evolve / _relic_awaken   the three rites that reused the
#                            summon's burst, each its own
#
# The harmony is chosen so every layer agrees with every other whichever of
# them play. The base holds an OPEN FIFTH on D (D3 A3 D4 A4, with E5 over
# it and the harp's D-A-E): no third, so it is neither major nor minor yet.
# A 3★ or a 4★ resolves it to D major at the flash. A 5★'s tell LIFTS it a
# whole step — E major in the high violins and a choir, over the base's
# fifth still ringing, E over D, the tension film scores put before a
# release — and its burst lands in E: the key change the item asks for, on
# the 5★ alone. The stars climb A major's pentatonic (A B C# E F# A), whose
# notes sit in D major and in E major both, so they ring true over either
# burst.
# ==============================================================================

def tremolo(note, dur, start=0.3):
    """A string section's tremolo at `note`, from `start` seconds into the
    recording (past the bow's first accent, where the tremolo is steady),
    `dur` seconds long: the level the envelope laid on it is the only one
    heard."""
    f = pitch(note) if isinstance(note, str) else note
    fam = "ctrem" if f < 260 else "vtrem"
    keys = [k for k in VSCO if k.startswith(fam + "_")]
    key = min(keys, key=lambda k: abs(math.log(f / VSCO[k][1])))
    x = recording(key)[N(start):]
    x = repitch(x, f / VSCO[key][1])
    x = x[:N(dur + 0.05)]
    return fade_tail(steady(x, after=0.02, win=0.06), 0.05)

def swell(n, points, curve=1.0):
    """`shape` bent by `curve`: over 1 the rise hangs back and arrives late,
    which is how a crescendo is played, not a straight ramp."""
    return shape(n, points) ** curve

def summon_ignite():
    r = seeded("summon_ignite")
    # The painted scroll catching light over the ring: the bell tree's stroke
    # for the shimmer, a breath of flame (noise under a band climbing
    # 600 Hz -> 3 kHz and letting go), a low soft whoomp as it takes, and the
    # harp's open D-A-E flicking up an octave and a half. Short, so the
    # reveal's own charge is the one that climbs.
    b = Bus()
    b.add(hp(recording("belltree"), 1200)[:N(1.0)], 0.0, 0.5)
    n = N(0.7)
    b.add(travel(r.standard_normal(n), [(0, 600), (0.45, 3000), (1, 1800)], q=1.2)
          * shape(n, [(0, 0), (0.18, 1.0), (0.7, 0)]), 0.0, 0.3)
    b.add(drop(0.5, 110, 48, 0.06, 0.14, attack=0.02), 0.02, 0.35)
    for i, note in enumerate(["D5", "A5", "E6"]):
        b.add(played("harp", note, dur=0.35, release=0.25), 0.05 + 0.045 * i, 0.4 + 0.15 * i)
    save("summon_ignite", room(b.x, rt60=1.1, wet=0.2, seed="hall")[:N(1.0)], -15, tail=0.3)

def summon_charge_base():
    r = seeded("summon_charge_base")
    # Every pull's charge, the same file for every grade (no sound may tell
    # the pull before its rung): 1.25 s to the flash (1.4 for a 5★, which
    # holds at the top for the extra 0.15 s). The string sections in
    # tremolo on the open fifth, swelling from nothing (the crescendo bent
    # to arrive late); the harp's D-A-E climbing, its notes coming faster
    # and louder as the charge gathers; a heartbeat under it, quickening; and
    # air rising through a band 400 Hz -> 5 kHz.
    n = N(1.62); b = Bus()
    body = [(0, 0.05), (0.06, 0.1), (1.25, 1.0), (1.42, 1.0), (1.62, 0.0)]
    for note, g, at in (("D3", 0.55, 0.0), ("A3", 0.5, 0.01), ("D4", 0.5, 0.02), ("A4", 0.42, 0.03), ("E5", 0.26, 0.05)):
        x = tremolo(note, 1.6)
        b.add(x * swell(len(x), body, 2.2), at, g)
    run = ["D4", "A4", "E5", "D5", "A5", "E6", "D6", "A6", "E6", "D7"]
    for i, note in enumerate(run):
        k = i / (len(run) - 1)
        at = 1.18 * (1 - (1 - k) ** 1.7)
        b.add(played("harp" if note not in ("D7",) else "glock", note, dur=0.3, release=0.2), at, 0.2 + 0.25 * k)
    for at, g in ((0.0, 0.5), (0.46, 0.55), (0.78, 0.62), (1.0, 0.66), (1.15, 0.7)):
        b.add(drop(0.3, 78, 44, 0.03, 0.08, attack=0.004), at, 0.26 * g)
    air = travel(r.standard_normal(n), [(0, 400), (0.78, 5000), (1, 3000)], q=0.9)
    b.add(air * swell(n, [(0, 0), (1.25, 1.0), (1.42, 0.8), (1.62, 0)], 2.0), 0.0, 0.1)
    save("summon_charge_base", room(b.x, rt60=1.4, wet=0.22, seed="hall")[:N(1.75)], -15, tail=0.3)

def summon_charge_rise():
    # A 4★ or better, from the violet rung: a real timpani roll on D (the
    # small drum, steady from 2 s into the recording) and the suspended
    # cymbal's rolled crescendo, both pushed into a crescendo that peaks at
    # 0.81 s, the 4★'s flash, and holds to 0.96 s, the 5★'s; a horn on D
    # swelling under them for the weight. The burst covers the release.
    b = Bus()
    n = N(1.25)
    roll = recording("timproll_D3")[N(2.0):N(2.0) + n]
    roll = repitch(roll, pitch("D3") / VSCO["timproll_D3"][1])[:n]
    b.add(roll * swell(len(roll), [(0, 0.08), (0.81, 1.0), (0.97, 1.0), (1.25, 0.0)], 2.2), 0.0, 0.9)
    cym = recording("susproll")[N(2.9):N(3.95)]
    b.add(hp(cym, 300) * swell(len(cym), [(0, 0.05), (0.81, 1.0), (0.97, 1.0), (1.05, 0.0)], 1.8), 0.0, 0.55)
    b.add(_call_note("horn", "D3", 0.95, 0.25, swell=[(0, 0.1), (0.81, 1.0), (1.2, 1.0)]), 0.0, 0.3)
    save("summon_charge_rise", room(b.x, rt60=1.5, wet=0.2, seed="hall")[:N(1.45)], -16, tail=0.3)

def summon_charge_tell():
    r = seeded("summon_charge_tell")
    # A 5★ alone, from the gold rung, 0.525 s before the flash: the bell's
    # ping (the glockenspiel's E6 and B6 struck together over a triangle),
    # the high violins LIFTING to E major (E5 G#5 B5, the key change), a
    # choir swelling in on E major, and the lightning's crackle round it.
    # The ping lands on the base and the rise near their loudest, so it is
    # a bell and not a blow: struck under the body that follows it, its
    # peak kept for the sum (`summon_mix_check`).
    b = Bus()
    b.add(played("glock", "E6", dur=0.8, release=0.4), 0.0, 0.5)
    b.add(played("glock", "B6", dur=0.8, release=0.4), 0.012, 0.4)
    b.add(hp(recording("triangle"), 2500)[:N(0.9)], 0.0, 0.25)
    lift = [(0, 0.35), (0.5, 1.0), (0.62, 1.0), (0.85, 0.0)]
    for note, g in (("E5", 0.45), ("G#5", 0.4), ("B5", 0.35)):
        x = tremolo(note, 0.85)
        b.add(x * swell(len(x), lift, 1.0), 0.0, g)
    n = N(0.85); choir = Bus()
    for part, notes, g in (("bass", "E3", 0.9), ("tenor", "B3", 0.8), ("alto", "G#4", 0.75), ("soprano", "B4", 0.7), ("soprano", "E5", 0.45)):
        choir.add(choir_part(r, part, [(0, pitch(notes))], n), 0.0, g)
    voices = choir.x[:n] / np.max(np.abs(choir.x))
    b.add(voices * swell(n, [(0, 0.0), (0.52, 1.0), (0.62, 1.0), (0.85, 0.0)], 1.5), 0.0, 0.55)
    b.add(hp(pops(r, 0.55, 46, 2500, 9500, bias=1.1), 1500), 0.0, 0.5)
    b.add(click(r, 0.006, 0.002, 11000, 2500), 0.0, 0.2)
    save("summon_charge_tell", room(b.x, rt60=1.6, wet=0.24, seed="hall")[:N(1.2)], -16, tail=0.35)

def summon_charge_lightdark():
    r = seeded("summon_charge_lightdark")
    # The Light & Dark scroll, from the first frame of every one of its
    # pulls (the scroll, never the result: it tells nothing): the bell
    # tree's stroke and, reversed, a second climbing into the flash; two
    # sopranos on A5 and E6 swelling out of nothing (a fifth, true over D
    # and over E); the glockenspiel twinkling A6 and E6 above it.
    b = Bus()
    tree = hp(recording("belltree"), 1500)
    b.add(tree[:N(1.2)], 0.02, 0.4)
    rise = tree[:N(0.7)][::-1] * shape(N(0.7), [(0, 0), (0.7, 1)]) ** 2
    b.add(rise, 0.55, 0.3)
    n = N(1.5); choir = Bus()
    choir.add(choir_part(r, "soprano", [(0, pitch("A5"))], n), 0.0, 0.8)
    choir.add(choir_part(r, "soprano", [(0, pitch("E6"))], n), 0.0, 0.5)
    voices = choir.x[:n] / np.max(np.abs(choir.x))
    b.add(voices * swell(n, [(0, 0), (1.2, 1.0), (1.35, 1.0), (1.5, 0)], 1.4), 0.0, 0.5)
    for at, note, g in ((0.25, "A6", 0.25), (0.55, "E6", 0.3), (0.85, "A6", 0.35), (1.1, "E6", 0.4)):
        b.add(played("glock", note, dur=0.5, release=0.3), at, g)
    save("summon_charge_lightdark", room(b.x, rt60=1.8, wet=0.3, seed="hall")[:N(1.8)], -18, tail=0.35)

def summon_burst_3():
    r = seeded("summon_burst_3")
    # A 3★'s flash: a chime. The glockenspiel runs up D major (D6 F#6 A6
    # D7, 35 ms apart) over the harp rolling the chord, a triangle's ping,
    # a breath of air for the flash, the cymbal touched softly.
    b = Bus()
    for i, note in enumerate(["D6", "F#6", "A6", "D7"]):
        b.add(played("glock", note, dur=0.9, release=0.45), 0.035 * i, 0.6 + 0.1 * i)
    for i, note in enumerate(["D4", "F#4", "A4", "D5"]):
        b.add(played("harp", note, dur=0.9, release=0.5), 0.012 * i, 0.4)
    b.add(hp(recording("triangle"), 2500)[:N(1.2)], 0.0, 0.3)
    n = N(0.5)
    b.add(bp(r.standard_normal(n), 2500, 9000) * fall(n, 0.12, 0.004), 0.0, 0.2)
    b.add(hp(recording("susp_soft"), 400)[:N(1.4)], 0.0, 0.25)
    save("summon_burst_3", room(b.x, rt60=1.5, wet=0.24, seed="hall")[:N(1.8)], -13, tail=0.45)

def summon_burst_4():
    r = seeded("summon_burst_4")
    # A 4★'s flash: a brass stab on D major — three trumpets (D5 F#5 A5,
    # their staccato takes, the scoop settled out of the attack) over horns
    # on D3 A3 cut short — the timpani struck on D2 under them, the cymbal
    # struck, the glockenspiel's D7 sparkling off the top.
    b = Bus()
    for i, note in enumerate(["D5", "F#5", "A5"]):
        b.add(_call_note("tptshort", note, 0.16, 0.12, settled=True), 0.004 * i, 0.85)
    for note in ("D3", "A3"):
        b.add(_call_note("horn", note, 0.3, 0.25), 0.008, 0.55)
    timp = repitch(recording("timpani"), pitch("D2") / VSCO["timpani"][1])[:N(1.6)]
    b.add(timp, 0.0, 0.55)
    b.add(hp(recording("crash"), 450)[:N(1.8)], 0.012, 0.4)
    b.add(played("glock", "D7", dur=0.8, release=0.4), 0.02, 0.45)
    b.add(click(r, 0.005, 0.002, 9000, 1500), 0.0, 0.2)
    save("summon_burst_4", room(b.x, rt60=1.7, wet=0.24, seed="hall")[:N(2.0)], -12, tail=0.5)

def summon_burst_5():
    r = seeded("summon_burst_5")
    # A 5★'s flash, in the key the tell lifted to, E major, as a HIT and a
    # BLOOM. The hit: the gong and the bass drum struck together over a sub
    # falling to E1, the timpani on E2, the crash. The bloom: trumpets on
    # E5 G#5 B5 over horns on E3 and B3, played forte-piano — struck with
    # the drums, falling back by half inside 0.3 s and held — and a choir
    # on the whole chord (E3 B3 G#4 B4 E5) swelling in over 120 ms and
    # settling under the brass for two seconds; the glockenspiel's E6 and
    # B6 and the bell tree glittering off the top. The loudest moment the
    # summon has is its first 300 ms. Held at full for two seconds it was
    # a wall the limiter pressed flat, and the stars stamped onto it summed
    # to 1.36 of full scale; settled, the stars ring out over the choir.
    b = Bus()
    b.add(hp(recording("gong"), 60)[:N(3.0)], 0.0, 0.55)
    b.add(recording("bass_drum")[:N(2.0)], 0.0, 0.35)
    b.add(drop(1.6, 70, pitch("E1"), 0.08, 0.5, attack=0.004), 0.0, 0.15)
    timp = repitch(recording("timpani"), pitch("E2") / VSCO["timpani"][1])[:N(2.0)]
    b.add(timp, 0.012, 0.45)
    b.add(hp(recording("crash"), 400)[:N(2.4)], 0.01, 0.6)
    n = N(2.6); choir = Bus()
    for part, note, g in (("bass", "E3", 1.0), ("tenor", "B3", 0.85), ("alto", "G#4", 0.8), ("soprano", "B4", 0.75), ("soprano", "E5", 0.55)):
        choir.add(choir_part(r, part, [(0, pitch(note))], n), 0.0, g)
    voices = choir.x[:n] / np.max(np.abs(choir.x))
    b.add(voices * shape(n, [(0, 0), (0.12, 1.0), (0.45, 0.6), (2.1, 0.52), (2.6, 0)]), 0.02, 0.85)
    fp = [(0, 1.0), (0.28, 0.5), (1.6, 0.45)]
    for note in ("E5", "G#5", "B5"):
        b.add(_call_note("tpt", note, 1.5, 0.5, swell=fp), 0.03, 0.5)
    for note in ("E3", "B3"):
        b.add(_call_note("horn", note, 1.5, 0.5, swell=fp), 0.04, 0.5)
    b.add(played("glock", "E6", dur=1.0, release=0.5), 0.05, 0.4)
    b.add(played("glock", "B6", dur=1.0, release=0.5), 0.09, 0.35)
    b.add(hp(recording("belltree"), 1500)[:N(1.4)], 0.06, 0.3)
    b.add(click(r, 0.007, 0.0025, 11000, 2000), 0.0, 0.4)
    save("summon_burst_5", room(b.x, rt60=2.4, wet=0.28, seed="hall")[:N(3.2)], -11, tail=0.7)

# The stars' scale: A major's pentatonic, true over D major and E major both.
STAR_NOTES = ["A5", "B5", "C#6", "E6", "F#6", "A6"]

# The reveal's own mix (`ChargeLadder` in SummonRevealView.swift), kept in
# step with it by hand: every stem at 0.85; at the flash the stems fade out
# over 0.05 s (`AudioLibrary.fadeOut`) and the burst sounds 0.04 s after it
# on the audio device's clock (`AudioLibrary.schedule`), so it lands alone;
# the stars at 0.7 over a 3★'s chime, 0.65 over a 4★'s brass and 0.55 over
# a 5★'s choir (`ChargeLadder.starVolume`); a Quick 3★ (W2.23) has no
# charge, its burst at 0.8 and its stars in a blink. `summon_mix_check`
# sums them.
STEM_VOLUME = 0.85
STEM_FADE = 0.05
BURST_LEAD = 0.04
STAR_VOLUMES = {3: 0.7, 4: 0.65, 5: 0.55}
QUICK_BURST_VOLUME = 0.8

def star_notes():
    r = seeded("star_notes")
    # Each star lands on the next note: the glockenspiel's bar over a felt
    # stamp (a short low thud and a tap, the star pressed into the plaque),
    # a little louder and brighter a step as it climbs, the bell tree's
    # glitter joining from the fourth. `star_1` … `star_6`.
    for i, note in enumerate(STAR_NOTES):
        b = Bus()
        b.add(played("glock", note, dur=0.7, release=0.35), 0.0, 1.0)
        b.add(drop(0.12, 230, 130, 0.015, 0.03, attack=0.001), 0.0, 0.22)
        b.add(click(r, 0.003, 0.0012, 7000, 1800), 0.0, 0.18)
        if i >= 3:
            b.add(hp(recording("belltree"), 3000)[:N(0.6)], 0.01, 0.08 + 0.04 * (i - 3))
        save(f"star_{i + 1}", room(b.x, rt60=0.9, wet=0.18, seed="small")[:N(1.0)], -17.5 + 0.4 * i, tail=0.3)

def rite_awaken():
    r = seeded("rite_awaken")
    # An awakening's reveal lands on this instead of a summon's burst: an
    # ascent into light. The gong breathed, not struck (a soft stroke under
    # the rest); the harp sweeping up two octaves of D's pentatonic; the
    # violins' tremolo opening onto D major (F#5 A5 D6); a choir rising
    # from D major's fifth to its full chord; the glockenspiel's D7 at the
    # top of the sweep.
    b = Bus()
    b.add(lp(hp(recording("gong"), 60)[:N(2.6)], 2500), 0.0, 0.35)
    run = ["D4", "E4", "F#4", "A4", "B4", "D5", "E5", "F#5", "A5", "B5", "D6", "E6", "F#6"]
    for i, note in enumerate(run):
        k = i / (len(run) - 1)
        b.add(played("harp", note, dur=0.5 + 0.4 * k, release=0.3), 0.03 * i, 0.4 + 0.45 * k)
    b.add(played("glock", "D7", dur=1.1, release=0.5), 0.4, 0.5)
    for note, g in (("F#5", 0.35), ("A5", 0.35), ("D6", 0.3)):
        x = tremolo(note, 2.2)
        b.add(x * swell(len(x), [(0, 0.0), (0.5, 1.0), (1.8, 0.9), (2.2, 0.0)], 1.2), 0.05, g)
    n = N(2.4); choir = Bus()
    choir.add(choir_part(r, "bass", [(0, pitch("D3"))], n), 0.0, 0.9)
    choir.add(choir_part(r, "tenor", [(0, pitch("A3"))], n), 0.0, 0.8)
    choir.add(choir_part(r, "alto", [(0, pitch("E4")), (0.35, pitch("E4")), (0.5, pitch("F#4"))], n), 0.0, 0.75)
    choir.add(choir_part(r, "soprano", [(0, pitch("A4")), (0.35, pitch("A4")), (0.5, pitch("D5"))], n), 0.0, 0.7)
    voices = choir.x[:n] / np.max(np.abs(choir.x))
    b.add(voices * swell(n, [(0, 0), (0.45, 1.0), (1.9, 0.9), (2.4, 0)], 1.3), 0.0, 0.6)
    save("rite_awaken", room(b.x, rt60=2.2, wet=0.3, seed="hall")[:N(2.9)], -11, tail=0.6)

def rite_evolve():
    r = seeded("rite_evolve")
    # An evolution: a grade climbs, so the sound climbs a step at a time —
    # the harp rolled up D major, then four staccato trumpets stepping up
    # it (D5 F#5 A5 D6, 90 ms apart, the scoop settled out) and on the last
    # the timpani on D2, the cymbal touched and the horns holding D3 A3, the
    # glockenspiel's D7 over the top. Shorter than the level-up's fanfare
    # and without its pickups, so the two are never mistaken.
    b = Bus()
    for i, note in enumerate(["D4", "F#4", "A4", "D5"]):
        b.add(played("harp", note, dur=0.6, release=0.3), 0.025 * i, 0.45)
    steps = ["D5", "F#5", "A5", "D6"]
    for i, note in enumerate(steps):
        last = i == len(steps) - 1
        b.add(_call_note("tptshort", note, 0.3 if last else 0.09, 0.2 if last else 0.04, take=1 + i % 2,
                         settled=True), 0.12 + 0.09 * i, 0.55 + 0.1 * i)
    top = 0.12 + 0.09 * 3
    timp = repitch(recording("timpani"), pitch("D2") / VSCO["timpani"][1])[:N(1.4)]
    b.add(timp, top, 0.6)
    b.add(hp(recording("susp_soft"), 400)[:N(1.5)], top, 0.35)
    for note in ("D3", "A3"):
        b.add(_call_note("horn", note, 0.8, 0.35, swell=[(0, 0.7), (0.3, 1.0), (1.15, 0.9)]), top, 0.4)
    b.add(played("glock", "D7", dur=0.9, release=0.4), top + 0.02, 0.45)
    b.add(click(r, 0.005, 0.002, 9000, 1500), top, 0.25)
    save("rite_evolve", room(b.x, rt60=1.7, wet=0.24, seed="hall")[:N(2.2)], -12, tail=0.5)

def rite_relic_awaken():
    r = seeded("rite_relic_awaken")
    # A relic's awakening: a stone waking, so glass and metal rather than
    # voices and brass. Crystal struck twice (a fifth, E6 then B6: modes at
    # glass's ratios, each split into a slow beating pair), the triangle
    # and the bell tree reversed rising into the first strike, a low hum on
    # B2 swelling under it, the anvil touched and pitched up a fourth for the
    # setting, and a thin soprano shimmer on E5 and B5.
    b = Bus()
    tree = hp(recording("belltree"), 1500)[:N(0.55)][::-1] * shape(N(0.55), [(0, 0), (0.55, 1)]) ** 2
    b.add(tree, 0.0, 0.35)
    strike = 0.5
    b.add(modes(2.0, pitch("E6"), (1, 2.32, 4.25, 6.63), (1.1, 0.6, 0.35, 0.2), (1, 0.45, 0.25, 0.12), split=2.5, rng=r), strike, 0.6)
    b.add(modes(1.8, pitch("B6"), (1, 2.32, 4.25), (0.9, 0.5, 0.3), (1, 0.4, 0.2), split=3.0, rng=r), strike + 0.16, 0.45)
    b.add(hp(recording("triangle"), 2500)[:N(1.6)], strike, 0.3)
    anvil = fade_tail(lp(hp(repitch(recording("anvil"), 2 ** (5 / 12)), 600), 7000)[:N(0.6)], 0.3)
    b.add(anvil, strike, 0.25)
    n = N(2.2)
    hum = tone(pitch("B2"), n) * swell(n, [(0, 0), (0.6, 1.0), (1.6, 0.8), (2.2, 0)], 1.5)
    b.add(hum, 0.1, 0.18)
    choir = Bus()
    choir.add(choir_part(r, "soprano", [(0, pitch("E5"))], n), 0.0, 0.7)
    choir.add(choir_part(r, "soprano", [(0, pitch("B5"))], n), 0.0, 0.5)
    voices = choir.x[:n] / np.max(np.abs(choir.x))
    b.add(voices * swell(n, [(0, 0), (0.7, 1.0), (1.7, 0.8), (2.2, 0)], 1.4), strike - 0.2, 0.3)
    save("rite_relic_awaken", room(b.x, rt60=2.0, wet=0.3, seed="hall")[:N(2.8)], -12, tail=0.6)

def build_summon():
    _need()
    if have_vsco("summon_*, star_*, rite_*"):
        summon_ignite(); summon_charge_base(); summon_charge_rise(); summon_charge_tell()
        summon_charge_lightdark(); summon_burst_3(); summon_burst_4(); summon_burst_5()
        star_notes(); rite_awaken(); rite_evolve(); rite_relic_awaken()
        summon_mix_check()

# ==============================================================================
# The reward box by rarity (FEEL.md W2.2, 2026-09-24), `build_spoils`: the
# chest's three rattles, each harder; its lid's creak, its thud on the hinge
# and the beam's shimmer as ONE file, so the three stay in step with the lid
# (`ChestTiming` in SpoilsBeats.swift); a crystal clink for every tile, one
# step up D major's pentatonic a tile — twelve steps, D5 to E7 — so a big haul
# plays a melody; a legend's rising three notes and its landing; and the
# relic power-up's short drum roll and its verdict, an anvil's ring or a dull
# crack of stone (`AudioLibrary.Sound.rollLead` after the roll).
#
# Levelled by role, a step under the rites: the rattles -17 rising to -14
# (each played louder too, 0.8/0.9/1.0), the lid -12.5 at 0.9; the clinks
# -18.5 rising to -16.5 at 0.7 (0.8 for an epic), over which a legend's
# three notes land at -12 and full volume; the roll -15, the ring
# -12.5 and the crack -15 at 0.9 (the roll at 0.7). `spoils_mix_check` sums the chest and a
# twelve-spoil shelf with an epic and a legend at the box's own offsets, and
# the power-up's roll into each verdict: every sum peaks at or under 0.90.
# ==============================================================================

# The box's clock, kept in step with SpoilsBeats.swift by hand.
CHEST_RATTLES = [0.0, 0.26, 0.52]
CHEST_LID = 0.8
CHEST_FLASH_AFTER_LID = 1.1
CHEST_FIRST_TILE = 0.2
TILE_STEP = 0.14
EPIC_PAUSE = 0.2
LEGEND_PAUSE = 0.35
LEGEND_LANDING = 0.3
ROLL_LEAD = 0.26
RATTLE_VOLUMES = [0.8, 0.9, 1.0]
LID_VOLUME = 0.9
TILE_VOLUME = 0.7
EPIC_VOLUME = 0.8
RING_VOLUME = 0.9
CRACK_VOLUME = 0.9
ROLL_VOLUME = 0.7

# The shelf's scale: D major's pentatonic from D5, one step a tile.
SPOIL_NOTES = ["D5", "E5", "F#5", "A5", "B5", "D6", "E6", "F#6", "A6", "B6", "D7", "E7"]

def _knock(r, pitch_hz, g=1.0):
    """A knock of wood with iron on it: a short body falling onto its pitch,
    the contact's tick, and a bright scrape of the fittings."""
    b = Bus()
    b.add(drop(0.12, pitch_hz * 1.9, pitch_hz, 0.008, 0.035, attack=0.001), 0.0, 0.8 * g)
    b.add(click(r, 0.004, 0.0014, 7000, 900), 0.0, 0.45 * g)
    n = N(0.05)
    b.add(bp(r.standard_normal(n), 1800, 5200) * fall(n, 0.012), 0.002, 0.18 * g)
    return b.x

def _jingle(r, g=1.0):
    """The lock and the hinges shaking: small iron parts, inharmonic and
    quick, a few of them a few milliseconds apart."""
    b = Bus()
    for i, base in enumerate((2250, 2780, 3370)):
        b.add(modes(0.16, base * r.uniform(0.97, 1.03), (1, 2.76, 5.4), (0.07, 0.04, 0.02), (1, 0.4, 0.15), rng=r),
              0.004 * i + r.uniform(0, 0.006), 0.22 * g)
    return b.x

def chest_rattles():
    # Three rattles, each harder: two knocks and a jingle, then three, then
    # four and the thump of the chest landing from its hop — in the rattle's
    # 0.16 s, the four quarter moves `RewardChestView` shakes it through.
    for i, (knocks, g) in enumerate(((2, 0.6), (3, 0.8), (4, 1.0))):
        r = seeded(f"chest_rattle_{i + 1}")
        b = Bus()
        for k in range(knocks):
            at = 0.04 * k + r.uniform(0, 0.008)
            b.add(_knock(r, r.uniform(150, 210), g=g * (0.8 + 0.2 * r.random())), at, 1.0)
            b.add(_jingle(r, g=g), at + 0.003, 0.9)
        if i == 2:
            b.add(drop(0.2, 120, 58, 0.02, 0.06, attack=0.002), 0.17, 0.5)
            b.add(click(r, 0.005, 0.002, 4000, 400), 0.17, 0.3)
        save(f"chest_rattle_{i + 1}", room(b.x, rt60=0.5, wet=0.12, seed="small")[:N(0.6)], -17 + 1.5 * i, tail=0.15)

def chest_open():
    r = seeded("chest_open")
    # The lid (`ChestTiming.lid`): a creak as it swings — wood sticking and
    # slipping on its hinge pin, a pulse train that speeds up as it goes,
    # rung through the lid's resonances — its thud as it stops against the
    # hinge 0.32 s on, with the iron band's clank, and the beam's shimmer
    # from 0.18 s: the bell tree drawn in reverse into the light, then
    # struck, the glockenspiel's A6 and D7 and air rising through it.
    b = Bus()
    n = N(0.34)
    rate = np.interp(T(n), [0, 0.12, 0.3, 0.34], [34, 48, 62, 40])
    phase = np.cumsum(rate / SR)
    ticks = np.zeros(n)
    edges = np.nonzero(np.diff(np.floor(phase + 0.13 * smooth_noise(r, n, 30))) > 0)[0]
    ticks[edges] = r.uniform(0.6, 1.0, len(edges))
    # Each slip is a few milliseconds of grinding, not a click.
    grit = r.standard_normal(N(0.004)) * fall(N(0.004), 0.0015)
    slips = np.convolve(ticks, grit)[:n]
    wood = formants(slips, [(420, 60, 0), (980, 110, -3), (1850, 200, -6), (3100, 400, -10)])
    wood = wood / (np.max(np.abs(wood)) + 1e-12)
    b.add(wood * shape(n, [(0, 0.2), (0.06, 1.0), (0.26, 0.9), (0.34, 0.0)]), 0.0, 0.5)
    b.add(bp(r.standard_normal(n), 900, 4000) * shape(n, [(0, 0), (0.08, 0.25), (0.3, 0.15), (0.34, 0)]), 0.0, 0.12)
    thud = 0.32
    b.add(drop(0.3, 150, 52, 0.018, 0.08, attack=0.002), thud, 0.6)
    b.add(_knock(r, 130, g=1.0), thud, 0.55)
    clank = fade_tail(hp(recording("anvil"), 900)[:N(0.35)], 0.2)
    b.add(clank, thud + 0.004, 0.12)
    tree = hp(recording("belltree"), 1500)
    swell = tree[:N(0.3)][::-1] * shape(N(0.3), [(0, 0), (0.3, 1)]) ** 2
    b.add(swell, 0.05, 0.3)
    b.add(tree[:N(1.2)], 0.35, 0.3)
    b.add(played("glock", "A6", dur=0.9, release=0.45), 0.36, 0.3)
    b.add(played("glock", "D7", dur=0.9, release=0.45), 0.42, 0.26)
    m = N(1.0)
    b.add(travel(r.standard_normal(m), [(0, 2500), (0.4, 7000), (1, 5000)], q=1.1)
          * shape(m, [(0, 0), (0.25, 1.0), (1.0, 0)]), 0.3, 0.08)
    save("chest_open", room(b.x, rt60=1.2, wet=0.22, seed="hall")[:N(1.8)], -12.5, tail=0.4)

def spoil_notes():
    # A crystal clink for each tile: struck glass (modes at glass's ratios,
    # each split into a slowly beating pair) with the glockenspiel's bar
    # under it and a tick, a little brighter and louder a step as the shelf
    # climbs. `spoil_1` … `spoil_12`.
    for i, note in enumerate(SPOIL_NOTES):
        r = seeded(f"spoil_{i + 1}")
        f = pitch(note)
        b = Bus()
        b.add(modes(0.7, f, (1, 2.32, 4.25, 6.63), (0.5, 0.28, 0.16, 0.09), (1, 0.4, 0.18, 0.08), split=2.2, rng=r),
              0.0, 0.8)
        b.add(played("glock", note, dur=0.45, release=0.3), 0.0, 0.45)
        b.add(click(r, 0.003, 0.001, 9500, 2500), 0.0, 0.2 + 0.01 * i)
        save(f"spoil_{i + 1}", room(b.x, rt60=0.8, wet=0.16, seed="small")[:N(0.9)], -18.5 + 2.0 * i / 11, tail=0.3)

def spoil_legend():
    r = seeded("spoil_legend")
    # A legend's landing: three notes rising (D6, A6, D7, 90 ms apart) in
    # glass and bell over the bell tree, a soft breath of gong under them
    # for the column of light, and the tile's own landing — a low thud and a
    # triangle's ping — as it drops onto the shelf at 0.3 s.
    b = Bus()
    for i, note in enumerate(["D6", "A6", "D7"]):
        f = pitch(note)
        b.add(modes(1.2, f, (1, 2.32, 4.25, 6.63), (0.8, 0.45, 0.25, 0.14), (1, 0.42, 0.2, 0.1), split=2.6, rng=r),
              0.09 * i, 0.5 + 0.1 * i)
        b.add(played("glock", note, dur=0.8, release=0.4), 0.09 * i, 0.4 + 0.1 * i)
    b.add(hp(recording("belltree"), 1500)[:N(1.2)], 0.18, 0.3)
    b.add(lp(hp(recording("gong"), 60)[:N(1.8)], 2200), 0.0, 0.18)
    land = LEGEND_LANDING
    b.add(drop(0.28, 130, 55, 0.02, 0.07, attack=0.002), land, 0.45)
    b.add(hp(recording("triangle"), 2500)[:N(1.0)], land, 0.25)
    b.add(click(r, 0.005, 0.002, 9000, 1500), land, 0.2)
    save("spoil_legend", room(b.x, rt60=1.6, wet=0.26, seed="hall")[:N(2.2)], -12, tail=0.5)

def relic_roll():
    # The power-up's drum roll: the timpani roll on D, steady from two
    # seconds into the recording, in a quick crescendo that peaks just
    # before `ROLL_LEAD` and falls away into the verdict landing on it — a
    # roll into a strike, never the two at their loudest together.
    n = N(ROLL_LEAD + 0.1)
    roll = recording("timproll_D3")[N(2.0):N(2.0) + n]
    b = Bus()
    b.add(roll * shape(len(roll), [(0, 0.25), (ROLL_LEAD - 0.04, 1.0), (ROLL_LEAD + 0.02, 0.15),
                                   (ROLL_LEAD + 0.1, 0.0)]), 0.0, 1.0)
    save("relic_roll", room(b.x, rt60=0.7, wet=0.14, seed="small")[:N(0.6)], -15, tail=0.12)

def relic_ring():
    r = seeded("relic_ring")
    # Success: the anvil struck and let ring, the stone's own glass a
    # fifth over it (E6 and B6) and the triangle's shimmer.
    b = Bus()
    b.add(fade_tail(hp(recording("anvil"), 300)[:N(1.1)], 0.5), 0.0, 0.75)
    b.add(modes(1.0, pitch("E6"), (1, 2.32, 4.25), (0.6, 0.35, 0.2), (1, 0.4, 0.18), split=2.0, rng=r), 0.01, 0.4)
    b.add(modes(0.9, pitch("B6"), (1, 2.32, 4.25), (0.5, 0.3, 0.18), (1, 0.35, 0.15), split=2.4, rng=r), 0.05, 0.3)
    b.add(hp(recording("triangle"), 2500)[:N(1.0)], 0.02, 0.22)
    save("relic_ring", room(b.x, rt60=1.1, wet=0.2, seed="hall")[:N(1.5)], -12.5, tail=0.4)

def relic_crack():
    r = seeded("relic_crack")
    # Failure: a dull crack of stone — a split of dry noise, low-passed so
    # it never rings, a low thud under it, and a few chips crumbling off.
    b = Bus()
    n = N(0.16)
    b.add(lp(bp(r.standard_normal(n), 300, 5000), 2400) * fall(n, 0.035, 0.001), 0.0, 0.7)
    b.add(drop(0.3, 170, 62, 0.02, 0.1, attack=0.002), 0.0, 0.6)
    b.add(click(r, 0.006, 0.002, 3500, 400), 0.0, 0.3)
    b.add(lp(pops(r, 0.45, 26, 400, 3000, bias=1.2), 2500), 0.03, 0.5)
    save("relic_crack", room(b.x, rt60=0.6, wet=0.14, seed="small")[:N(0.8)], -15, tail=0.2)

def spoils_mix_check():
    """The box plays its sounds on top of each other: the rattles, then the
    lid, whose shimmer is still ringing when the tiles begin, and a tile
    every 0.14 s with an epic's pause and a legend's. A phone's mixer sums
    the players with no limiter, so a sum over full scale clips there.
    Prints the chest's sum and a twelve-spoil shelf's (ten plain, an epic,
    a legend: the fullest box), then the power-up's roll into each verdict."""
    worst = 0.0
    lid = _read("chest_open")
    rattles = [_read(f"chest_rattle_{i + 1}") for i in range(3)]
    b = Bus()
    for at, x, g in zip(CHEST_RATTLES, rattles, RATTLE_VOLUMES):
        b.add(x, at, g)
    b.add(lid, CHEST_LID, LID_VOLUME)
    first = CHEST_LID + CHEST_FLASH_AFTER_LID + CHEST_FIRST_TILE
    tiers = ["plain"] * 10 + ["epic", "legend"]
    at = 0.0
    for i, tier in enumerate(tiers):
        if i > 0: at += TILE_STEP
        if tier == "epic": at += EPIC_PAUSE
        if tier == "legend": at += LEGEND_PAUSE
        if tier == "legend":
            b.add(_read("spoil_legend"), first + at, 1.0)
            at += LEGEND_LANDING
        else:
            b.add(_read(f"spoil_{i + 1}"), first + at, EPIC_VOLUME if tier == "epic" else TILE_VOLUME)
    peak = float(np.max(np.abs(b.x))); worst = max(worst, peak)
    print(f"  mix the box (3 rattles, the lid, 12 spoils)  peak {peak:.3f}  chest {loudness(b.x[:N(first)]):6.1f} LUFS"
          f"  whole {loudness(b.x):6.1f} LUFS{'   ! over 0.95' if peak > 0.95 else ''}")
    for verdict, g in (("relic_ring", RING_VOLUME), ("relic_crack", CRACK_VOLUME)):
        b = Bus()
        b.add(_read("relic_roll"), 0.0, ROLL_VOLUME)
        b.add(_read(verdict), ROLL_LEAD, g)
        peak = float(np.max(np.abs(b.x))); worst = max(worst, peak)
        print(f"  mix roll into {verdict[6:]:5s}                    peak {peak:.3f}  whole {loudness(b.x):6.1f} LUFS"
              f"{'   ! over 0.95' if peak > 0.95 else ''}")
    print(f"  the loudest sum peaks at {worst:.3f}")

def build_spoils():
    _need()
    if have_vsco("chest_*, spoil_*, relic_roll/ring/crack"):
        chest_rattles(); chest_open(); spoil_notes(); spoil_legend()
        relic_roll(); relic_ring(); relic_crack()
        spoils_mix_check()

def _read(name):
    with wave.open(os.path.join(OUT, f"{name}.wav"), "rb") as w:
        return np.frombuffer(w.readframes(w.getnframes()), dtype="<i2").astype(float) / 32767.0

def summon_mix_check():
    """The reveal plays several of these at once (`SummonRevealView`,
    `ChargeLadder`): the base and the Light & Dark layer from the charge's
    first frame, the rise from 0.4375 s, the tell from 0.875 s; at the flash
    (1.25 s, 1.4 for a 5★) the stems give way over `STEM_FADE` and the
    burst sounds `BURST_LEAD` after it; the card arrives on the figure's
    first drawn frame, about 0.03 s on, and a star lands every 0.13 s from
    0.26 + 0.11 s after that (`RevealCardTiming.landing`). A phone's mixer
    sums the players, and a sum over full scale clips there. Prints each
    grade's sum: its peak, and the loudness of the charge and of the whole."""
    base, ld, rise, tell = (_read(k) for k in ("summon_charge_base", "summon_charge_lightdark",
                                               "summon_charge_rise", "summon_charge_tell"))
    stars = [_read(f"star_{i + 1}") for i in range(6)]
    def given_way(x, at, flash):
        k = N(max(0.0, flash - at)); y = x.copy()
        if k < len(y):
            y[k:] *= np.clip(1 - T(len(y) - k) / STEM_FADE, 0, 1)
        return y
    worst = 0.0
    for grade, flash, burst in ((3, 1.25, "summon_burst_3"), (4, 1.25, "summon_burst_4"), (5, 1.4, "summon_burst_5")):
        for scroll in ("", " + light & dark"):
            b = Bus()
            b.add(given_way(base, 0.0, flash), 0.0, STEM_VOLUME)
            if scroll: b.add(given_way(ld, 0.0, flash), 0.0, STEM_VOLUME)
            if grade >= 4: b.add(given_way(rise, 0.4375, flash), 0.4375, STEM_VOLUME)
            if grade >= 5: b.add(given_way(tell, 0.875, flash), 0.875, STEM_VOLUME)
            b.add(_read(burst), flash + BURST_LEAD, 1.0)
            for i in range(grade):
                b.add(stars[i], flash + 0.03 + 0.26 + 0.13 * i + 0.16 * 0.7, STAR_VOLUMES[grade])
            peak = float(np.max(np.abs(b.x))); worst = max(worst, peak)
            charge = b.x[:N(flash)]
            print(f"  mix {grade}★{scroll:16s}  peak {peak:.3f}  charge {loudness(charge):6.1f} LUFS"
                  f"  whole {loudness(b.x):6.1f} LUFS{'   ! over 0.95' if peak > 0.95 else ''}")
    # A Quick 3★: the flash at once, the stars from 0.06 s, 0.06 apart
    # (`RevealCardTiming.quick`).
    b = Bus()
    b.add(_read("summon_burst_3"), BURST_LEAD, QUICK_BURST_VOLUME)
    for i in range(3):
        b.add(stars[i], 0.03 + 0.06 + 0.06 * i + 0.1 * 0.7, STAR_VOLUMES[3])
    peak = float(np.max(np.abs(b.x))); worst = max(worst, peak)
    print(f"  mix quick 3★              peak {peak:.3f}  whole {loudness(b.x):6.1f} LUFS"
          f"{'   ! over 0.95' if peak > 0.95 else ''}")
    print(f"  the loudest sum {worst:.3f} of full scale" + ("" if worst <= 0.95 else "   ! the reveal would clip"))

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
    global OUT, VSCO_DIR
    args = sys.argv[1:]
    if "--check" in args:
        check(); return
    def option(flag):
        if flag not in args: return None
        i = args.index(flag); value = args[i + 1]; del args[i:i + 2]
        return value
    fetch = option("--fetch-vsco")
    if fetch:
        fetch_vsco(fetch); return
    OUT = option("--out") or OUT
    VSCO_DIR = option("--vsco") or VSCO_DIR
    sections = {"hits": build_hits, "kinds": build_kinds, "elements": build_elements,
                "defence": build_defence, "rest": build_rest,
                "status": build_status, "flow": build_flow, "summon": build_summon,
                "spoils": build_spoils}
    for name in args or list(sections):
        if name not in sections:
            sys.exit(f"no section {name!r}; the sections are {', '.join(sections)}")
        sections[name]()
    print(f"wrote {len(os.listdir(OUT))} files to {os.path.normpath(OUT)}")

if __name__ == "__main__":
    main()
