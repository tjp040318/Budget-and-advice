#!/usr/bin/env python3
"""
Synthesises the two music loops into Pantheon/Resources/Audio/.

    python3 tools/music.py          # music_island.wav (40 s), music_battle.wav (30 s)

Same idea as tools/sfx.py: no samples, no network, and vastly better than
silence. Both loops are in E Phrygian dominant (E F G# A B C D), the "Hijaz"
scale that reads as Egyptian to a Western ear. The island loop is pads, a
drone, a sparse plucked melody and wind; the battle loop is a kick, a frame
drum, a shaker, a bass ostinato, pads and chord stabs at 96 BPM, twelve bars.
Each loop is rendered with a four-second tail that is folded back onto its
head, so it repeats without a seam.

AudioLibrary looks the files up by name; replace either with a real recording
of the same name and nothing else changes. 22.05 kHz stereo, 16-bit.
"""

import math, wave, struct
from pathlib import Path

import numpy as np
from scipy.signal import butter, lfilter

REPO = Path(__file__).resolve().parent.parent
OUT = REPO / "Pantheon" / "Resources" / "Audio"
SR = 22050
rng = np.random.default_rng(11)

# E Phrygian dominant, as frequencies by octave and degree.
def hz(note, octave):
    semis = {"E": 0, "F": 1, "G#": 4, "A": 5, "B": 7, "C": 8, "D": 10}[note]
    return 41.2034 * 2 ** (octave - 1) * 2 ** (semis / 12)          # E1 = 41.2 Hz


# ---------------------------------------------------------------------------
# Building blocks
# ---------------------------------------------------------------------------

def secs(s):
    return int(round(s * SR))


def env(n, a, d, s, r):
    """Attack, decay, sustain level, release — all in seconds but the level."""
    a, d, r = max(1, secs(a)), max(1, secs(d)), max(1, secs(r))
    out = np.full(n, s, dtype=np.float64)
    out[:a] = np.linspace(0, 1, a)
    dd = min(d, max(0, n - a))
    out[a:a + dd] = np.linspace(1, s, dd)
    rr = min(r, n)
    out[n - rr:] *= np.linspace(1, 0, rr)
    return out


def osc(freq, n, kind="tri", cents=0.0, phase=None):
    f = freq * 2 ** (cents / 1200)
    t = np.arange(n) / SR
    ph = 2 * np.pi * f * t + (rng.uniform(0, 2 * np.pi) if phase is None else phase)
    if kind == "sine":
        return np.sin(ph)
    if kind == "tri":
        return 2 / np.pi * np.arcsin(np.sin(ph))
    return 2 * ((ph / (2 * np.pi)) % 1.0) - 1          # saw


def lowpass(x, cutoff, order=2):
    b, a = butter(order, min(0.99, cutoff / (SR / 2)))
    return lfilter(b, a, x)


def highpass(x, cutoff, order=2):
    b, a = butter(order, min(0.99, cutoff / (SR / 2)), btype="high")
    return lfilter(b, a, x)


def bandpass(x, lo, hi):
    return highpass(lowpass(x, hi), lo)


def moving_lowpass(x, cutoffs):
    """Low-pass whose cutoff follows `cutoffs` (one per 0.25 s block)."""
    block = secs(0.25)
    out = np.empty_like(x)
    zi = None
    for i, c in enumerate(cutoffs):
        seg = x[i * block:(i + 1) * block]
        if len(seg) == 0:
            break
        b, a = butter(2, min(0.99, c / (SR / 2)))
        if zi is None:
            zi = np.zeros(max(len(a), len(b)) - 1)
        y, zi = lfilter(b, a, seg, zi=zi)
        out[i * block:i * block + len(y)] = y
    return out


def reverb(x, wet=0.3, decay=0.78):
    dry = x
    y = np.zeros_like(x)
    for d in (0.0297, 0.0371, 0.0411, 0.0437):
        D = secs(d)
        a = np.zeros(D + 1); a[0] = 1; a[-1] = -decay
        y += lfilter([1.0], a, x)
    y = lowpass(y / 4, 2800)
    for d in (0.005, 0.0017):
        D = secs(d); g = 0.7
        b = np.zeros(D + 1); b[0] = -g; b[-1] = 1
        a = np.zeros(D + 1); a[0] = 1; a[-1] = -g
        y = lfilter(b, a, y)
    return dry * (1 - wet) + y * wet


def pan(mono, position):
    """position 0 = left, 1 = right -> (2, n)."""
    th = position * np.pi / 2
    return np.vstack([mono * np.cos(th), mono * np.sin(th)])


class Mix:
    def __init__(self, duration, tail=4.0):
        self.n = secs(duration + tail)
        self.loop = secs(duration)
        self.buf = np.zeros((2, self.n))

    def add(self, stereo, at=0.0, gain=1.0):
        start = secs(at)
        length = min(stereo.shape[1], self.n - start)
        if length > 0:
            self.buf[:, start:start + length] += stereo[:, :length] * gain

    def render(self):
        # Fold the tail back onto the head so the loop point is silent about it.
        tail = self.buf[:, self.loop:]
        out = self.buf[:, :self.loop].copy()
        out[:, :tail.shape[1]] += tail
        peak = np.abs(out).max() or 1.0
        return out / peak * 0.72


def write(name, stereo):
    OUT.mkdir(parents=True, exist_ok=True)
    data = np.clip(stereo, -1, 1)
    inter = np.empty(data.shape[1] * 2)
    inter[0::2], inter[1::2] = data[0], data[1]
    path = OUT / f"{name}.wav"
    with wave.open(str(path), "wb") as w:
        w.setnchannels(2); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes((inter * 32767).astype("<i2").tobytes())
    print(f"  {path.relative_to(REPO)}  {data.shape[1] / SR:.1f} s  {path.stat().st_size // 1024} KB")


# ---------------------------------------------------------------------------
# Instruments
# ---------------------------------------------------------------------------

def pad(freqs, duration, cutoff=(700, 1300), attack=2.0, release=2.5):
    n = secs(duration)
    voices = []
    for k, f in enumerate(freqs):
        v = sum(osc(f, n, "saw", cents=c) for c in (-6, 0, 6)) / 3 + 0.35 * osc(f * 2, n, "tri")
        voices.append(pan(v, 0.3 + 0.4 * (k / max(1, len(freqs) - 1))))
    x = sum(voices) / len(voices)
    blocks = int(math.ceil(n / secs(0.25)))
    lfo = [cutoff[0] + (cutoff[1] - cutoff[0]) * (0.5 + 0.5 * math.sin(2 * math.pi * i * 0.25 / 11.0)) for i in range(blocks)]
    x = np.vstack([moving_lowpass(x[0], lfo), moving_lowpass(x[1], lfo)])
    return x * env(n, attack, 0.5, 0.85, release)


def pluck(freq, duration=3.0, brightness=1.0):
    n = secs(duration)
    t = np.arange(n) / SR
    tone = np.zeros(n)
    for h, amp, tau in ((1, 1.0, 1.4), (2, 0.35 * brightness, 0.8), (3, 0.18 * brightness, 0.5), (5, 0.06, 0.3)):
        tone += amp * np.sin(2 * np.pi * freq * h * t + rng.uniform(0, 6.28)) * np.exp(-t / tau)
    tone *= env(n, 0.004, 0.05, 1.0, 0.3)
    return tone / (1.6 * brightness)


def kick(duration=0.35):
    n = secs(duration); t = np.arange(n) / SR
    f = 46 + 90 * np.exp(-t / 0.045)
    body = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t / 0.13)
    click = lowpass(rng.uniform(-1, 1, n), 3000) * np.exp(-t / 0.006) * 0.5
    return body + click


def frame_drum(duration=0.4):
    n = secs(duration); t = np.arange(n) / SR
    tone = np.sin(2 * np.pi * 165 * t) * np.exp(-t / 0.18) * 0.7
    skin = bandpass(rng.uniform(-1, 1, n), 250, 1600) * np.exp(-t / 0.09)
    return tone + skin


def shaker(duration=0.12):
    n = secs(duration); t = np.arange(n) / SR
    return bandpass(rng.uniform(-1, 1, n), 3200, 7500) * np.exp(-t / 0.028)


def bass(freq, duration):
    n = secs(duration)
    x = 0.7 * osc(freq, n, "saw") + 0.5 * osc(freq, n, "sine")
    return lowpass(x, 420) * env(n, 0.006, 0.12, 0.65, 0.05)


def stab(freqs, duration=1.2):
    n = secs(duration)
    x = sum(sum(osc(f, n, "saw", cents=c) for c in (-8, 0, 8)) for f in freqs) / (3 * len(freqs))
    blocks = int(math.ceil(n / secs(0.25)))
    sweep = [3200 * math.exp(-i * 0.25 / 0.35) + 400 for i in range(blocks)]
    x = moving_lowpass(x, sweep)
    return x * env(n, 0.005, 0.35, 0.3, 0.5)


def wind(duration):
    n = secs(duration)
    x = bandpass(rng.uniform(-1, 1, n), 300, 900)
    t = np.arange(n) / SR
    swell = 0.55 + 0.45 * np.sin(2 * np.pi * t / 13.0 + 1.0) * np.sin(2 * np.pi * t / 7.3)
    left, right = x * swell, np.roll(x, secs(0.031)) * (1.1 - swell)
    return np.vstack([left, right])


# ---------------------------------------------------------------------------
# The two pieces
# ---------------------------------------------------------------------------

def island():
    dur = 40.0
    mix = Mix(dur)
    # drone
    n = secs(dur + 4)
    drone = 0.6 * osc(hz("E", 1), n, "sine") + 0.4 * osc(hz("E", 2), n, "tri")
    t = np.arange(n) / SR
    drone *= 0.85 + 0.15 * np.sin(2 * np.pi * t / 9.0)
    mix.add(pan(lowpass(drone, 200), 0.5), 0, 0.30)
    # four chords, ten seconds each, overlapping by their releases
    chords = [
        [("E", 3), ("G#", 3), ("B", 3), ("E", 4)],
        [("F", 3), ("A", 3), ("C", 4), ("F", 4)],
        [("D", 3), ("F", 3), ("A", 3), ("D", 4)],
        [("E", 3), ("G#", 3), ("B", 3), ("D", 4)],
    ]
    for i, chord in enumerate(chords):
        mix.add(reverb(pad([hz(*c) for c in chord], 12.0), 0.35), i * 10.0, 0.42)
    # the melody: two phrases, one note every two and a half seconds
    phrase = [("B", 4), ("A", 4), ("G#", 4), ("E", 4), ("F", 4), ("E", 4), ("B", 4), ("D", 5),
              ("C", 5), ("B", 4), ("A", 4), ("G#", 4), ("F", 4), ("E", 4), ("G#", 4), ("B", 4)]
    for i, note in enumerate(phrase):
        at = 1.0 + i * 2.5 + rng.uniform(-0.05, 0.05)
        mix.add(reverb(pan(pluck(hz(*note), 3.5), 0.35 + 0.3 * rng.random()), 0.4), at, 0.30)
    mix.add(wind(dur + 4), 0, 0.06)
    return mix.render()


def battle():
    bpm, bars = 96, 12
    beat = 60 / bpm
    dur = bars * 4 * beat
    mix = Mix(dur)
    root = [("E", 2), ("E", 2), ("E", 2), ("F", 2), ("E", 2), ("D", 2), ("E", 2), ("E", 2)]
    walk = [("E", 2), ("E", 2), ("G#", 2), ("A", 2), ("B", 2), ("A", 2), ("G#", 2), ("F", 2)]
    for bar in range(bars):
        t0 = bar * 4 * beat
        # kick on 1 and 3, an extra pick-up every fourth bar
        for b in ([0, 2, 3.5] if bar % 4 == 3 else [0, 2]):
            mix.add(pan(kick(), 0.5), t0 + b * beat, 0.9)
        # frame drum on 2 and 4, doubled at the phrase ends
        for b in ([1, 3, 3.5] if bar % 4 == 3 else [1, 3]):
            mix.add(pan(frame_drum(), 0.42), t0 + b * beat, 0.5)
        # shaker on every eighth, quieter off the beat
        for e in range(8):
            mix.add(pan(shaker(), 0.62), t0 + e * beat / 2, 0.16 if e % 2 == 0 else 0.10)
        # bass ostinato
        pattern = walk if bar % 8 in (4, 5, 6) else root
        if bar == bars - 1:
            pattern = [("D", 2), ("D", 2), ("E", 2), ("E", 2), ("F", 2), ("F", 2), ("E", 2), ("E", 2)]
        for e, note in enumerate(pattern):
            mix.add(pan(bass(hz(*note), beat / 2 * 0.95), 0.5), t0 + e * beat / 2, 0.55)
        # stabs on phrase starts, the b2 chord at the turn
        if bar % 4 == 0:
            mix.add(reverb(pan(stab([hz("E", 4), hz("G#", 4), hz("B", 4)]), 0.5), 0.25), t0, 0.32)
        if bar % 4 == 3:
            mix.add(reverb(pan(stab([hz("F", 4), hz("A", 4), hz("C", 5)], 0.8), 0.5), 0.25), t0 + 2 * beat, 0.26)
    # a dark pad under everything, in two halves
    for i, chord in enumerate(([("E", 3), ("B", 3), ("E", 4)], [("E", 3), ("B", 3), ("F", 4)])):
        mix.add(pad([hz(*c) for c in chord], dur / 2 + 2, cutoff=(450, 800), attack=1.0, release=2.0), i * dur / 2, 0.22)
    # a bell figure at the phrase ends
    for bar in (3, 7, 11):
        t0 = bar * 4 * beat
        for k, note in enumerate((("E", 5), ("D", 5), ("B", 4))):
            mix.add(reverb(pan(pluck(hz(*note), 2.0, 1.3), 0.3 + 0.2 * k), 0.35), t0 + (2.5 + k * 0.5) * beat, 0.24)
    return mix.render()


if __name__ == "__main__":
    print("music:")
    write("music_island", island())
    write("music_battle", battle())
