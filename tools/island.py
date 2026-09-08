#!/usr/bin/env python3
"""
Paints the island backdrop procedurally, so the hub screen has a horizon to
stand on before a painted one exists.

    python3 tools/island.py                    # -> Pantheon/Resources/Portraits/island_bg.png

The real painting is a Gemini job (the prompt is in Docs/ART_2D.md, section 6)
and replaces this file with the same name and size. Until then: a dusk sky, a
low sun, a sea with its reflection, one island of sand and scrub, and a stone
footprint under every landmark so the tap targets in IslandView sit on
something. Landmark positions are mirrored from Core/Models/Island.swift and
must move together.

Drawn at twice the size and downsampled, which is the cheap way to get
anti-aliased edges out of PIL.
"""

import math, random
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

REPO = Path(__file__).resolve().parent.parent
OUT = REPO / "Pantheon" / "Resources" / "Portraits" / "island_bg.png"
W, H = 1536, 2048
S = 2                                  # supersampling
HORIZON = 0.40

# Normalised (x, y) of each landmark's footprint centre - the same numbers as
# IslandDatabase in Swift, where the tap targets are.
LANDMARKS = {
    "gate":     (0.24, 0.72),
    "circle":   (0.50, 0.60),
    "arena":    (0.77, 0.68),
    "hall":     (0.30, 0.52),
    "obelisk":  (0.70, 0.49),
}


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


def gradient_rows(height, stops):
    """stops: [(t, (r,g,b)), ...] with t in 0..1 -> (height, 3) uint8."""
    out = np.zeros((height, 3), dtype=np.uint8)
    for y in range(height):
        t = y / max(1, height - 1)
        for (t0, c0), (t1, c1) in zip(stops, stops[1:]):
            if t0 <= t <= t1:
                u = (t - t0) / max(1e-9, (t1 - t0))
                out[y] = lerp(c0, c1, u)
                break
    return out


def blob(cx, cy, rx, ry, seed, points=48, wobble=0.18):
    rnd = random.Random(seed)
    phase = [rnd.uniform(0, math.tau) for _ in range(4)]
    amp = [rnd.uniform(0.4, 1.0) * wobble / (k + 1) for k in range(4)]
    pts = []
    for i in range(points):
        a = math.tau * i / points
        r = 1.0 + sum(amp[k] * math.sin((k + 2) * a + phase[k]) for k in range(4))
        pts.append((cx + math.cos(a) * rx * r, cy + math.sin(a) * ry * r))
    return pts


def main():
    w, h = W * S, H * S
    rnd = random.Random(7)

    # --- sky ---------------------------------------------------------------
    sky = gradient_rows(int(h * HORIZON) + 1, [
        (0.00, (14, 10, 40)), (0.45, (58, 34, 92)), (0.78, (168, 84, 96)), (1.00, (246, 158, 88)),
    ])
    canvas = np.zeros((h, w, 3), dtype=np.uint8)
    canvas[:len(sky)] = sky[:, None, :]
    # --- sea ---------------------------------------------------------------
    sea = gradient_rows(h - len(sky), [
        (0.00, (214, 124, 92)), (0.06, (74, 92, 124)), (0.35, (30, 58, 96)), (1.00, (8, 18, 44)),
    ])
    canvas[len(sky):] = sea[:, None, :]
    img = Image.fromarray(canvas)
    draw = ImageDraw.Draw(img, "RGBA")

    # sun and its glow
    sx, sy = int(w * 0.62), int(h * HORIZON) - int(h * 0.035)
    for r, a in ((int(w * 0.30), 28), (int(w * 0.18), 48), (int(w * 0.10), 80)):
        draw.ellipse([sx - r, sy - r, sx + r, sy + r], fill=(255, 190, 120, a))
    draw.ellipse([sx - w * 0.045, sy - w * 0.045, sx + w * 0.045, sy + w * 0.045], fill=(255, 236, 190, 255))
    # cloud bands
    for i in range(7):
        cy = int(h * rnd.uniform(0.08, 0.34))
        cw = int(w * rnd.uniform(0.25, 0.7)); ch = int(h * rnd.uniform(0.006, 0.02))
        cx = int(w * rnd.uniform(0.0, 1.0))
        draw.ellipse([cx - cw, cy - ch, cx + cw, cy + ch], fill=(255, 205, 170, rnd.randint(30, 70)))
    # sun path on the water
    for i in range(160):
        y = int(h * HORIZON) + int((h * 0.55) * (i / 160) ** 1.6)
        spread = w * 0.03 + (y - h * HORIZON) * 0.35
        x = sx + rnd.gauss(0, spread * 0.5)
        ln = int(rnd.uniform(w * 0.01, w * 0.06))
        draw.line([(x - ln, y), (x + ln, y)], fill=(255, 200, 140, rnd.randint(20, 90)), width=S * 2)
    img = img.filter(ImageFilter.GaussianBlur(S * 1.5))
    draw = ImageDraw.Draw(img, "RGBA")

    # --- the island ----------------------------------------------------------
    cx, cy = w * 0.50, h * 0.66
    rx, ry = w * 0.44, h * 0.19
    # shallow water halo, then wet sand, sand, scrub, in from the shore
    for scale, colour in ((1.10, (92, 150, 160, 120)), (1.03, (188, 170, 130, 255)), (1.00, (222, 196, 142, 255))):
        draw.polygon(blob(cx, cy, rx * scale, ry * scale, seed=3), fill=colour)
    draw.polygon(blob(cx, cy + h * 0.005, rx * 0.86, ry * 0.80, seed=3), fill=(146, 128, 78, 255))
    draw.polygon(blob(cx - w * 0.03, cy - h * 0.01, rx * 0.66, ry * 0.58, seed=5), fill=(112, 118, 66, 255))
    # dunes and hills
    for (hx, hy, hr, hs, col) in ((0.36, 0.60, 0.14, 11, (132, 128, 74)), (0.62, 0.58, 0.16, 12, (124, 118, 68)),
                                  (0.50, 0.53, 0.12, 13, (150, 140, 84)), (0.20, 0.66, 0.09, 14, (172, 156, 104))):
        draw.polygon(blob(w * hx, h * hy, w * hr, h * hr * 0.45, seed=hs, wobble=0.25), fill=col + (255,))
        draw.polygon(blob(w * hx - w * 0.01, h * hy - h * 0.012, w * hr * 0.7, h * hr * 0.28, seed=hs + 1, wobble=0.25),
                     fill=lerp(col, (255, 230, 180), 0.25) + (200,))
    img = img.filter(ImageFilter.GaussianBlur(S * 0.8))
    draw = ImageDraw.Draw(img, "RGBA")

    # --- structures at the landmarks -----------------------------------------
    stone, stone_lit, stone_dark = (166, 150, 120), (214, 200, 168), (92, 80, 62)

    def footprint(name, r):
        x, y = LANDMARKS[name]
        x, y = x * w, y * h
        draw.ellipse([x - r, y - r * 0.42, x + r, y + r * 0.42], fill=stone_dark + (200,))
        draw.ellipse([x - r * 0.9, y - r * 0.36 - S * 6, x + r * 0.9, y + r * 0.36 - S * 6], fill=stone + (255,))
        return x, y

    def glow(x, y, r, colour):
        for k in range(6, 0, -1):
            draw.ellipse([x - r * k / 3, y - r * k / 3, x + r * k / 3, y + r * k / 3], fill=colour + (10 + 8 * (6 - k),))

    # Summoning circle: a ring of pillars around a lit disc.
    x, y = footprint("circle", w * 0.13)
    glow(x, y, w * 0.05, (120, 220, 255))
    for i in range(10):
        a = math.tau * i / 10
        px, py = x + math.cos(a) * w * 0.10, y + math.sin(a) * w * 0.042
        ph = h * 0.05 * (0.85 + 0.15 * math.sin(a))
        draw.rectangle([px - S * 9, py - ph, px + S * 9, py], fill=(stone_lit if math.sin(a) < 0 else stone) + (255,))
    draw.ellipse([x - w * 0.045, y - w * 0.018, x + w * 0.045, y + w * 0.018], fill=(150, 235, 255, 150))

    # Gate of the Duat: two pylons and a lintel.
    x, y = footprint("gate", w * 0.11)
    for dx in (-w * 0.05, w * 0.05):
        draw.polygon([(x + dx - w * 0.022, y), (x + dx + w * 0.022, y), (x + dx + w * 0.016, y - h * 0.10), (x + dx - w * 0.016, y - h * 0.10)],
                     fill=stone + (255,))
        draw.polygon([(x + dx - w * 0.022, y), (x + dx - w * 0.010, y), (x + dx - w * 0.008, y - h * 0.10), (x + dx - w * 0.016, y - h * 0.10)],
                     fill=stone_lit + (255,))
    draw.rectangle([x - w * 0.075, y - h * 0.115, x + w * 0.075, y - h * 0.095], fill=stone_dark + (255,))
    glow(x, y - h * 0.05, w * 0.03, (255, 160, 80))

    # Arena of Souls: an oval of tiered stone.
    x, y = footprint("arena", w * 0.12)
    for k, (rw, rh, col) in enumerate(((0.11, 0.044, stone_dark), (0.095, 0.038, stone), (0.075, 0.03, stone_lit), (0.055, 0.022, (120, 96, 70)))):
        draw.ellipse([x - w * rw, y - w * rh - k * S * 8, x + w * rw, y + w * rh - k * S * 8], fill=col + (255,))
    glow(x, y - S * 24, w * 0.02, (255, 120, 90))

    # Hall of Ka: a low pillared hall.
    x, y = footprint("hall", w * 0.10)
    draw.rectangle([x - w * 0.085, y - h * 0.055, x + w * 0.085, y - h * 0.045], fill=stone_dark + (255,))
    for i in range(7):
        px = x - w * 0.075 + i * (w * 0.15 / 6)
        draw.rectangle([px - S * 7, y - h * 0.046, px + S * 7, y], fill=(stone_lit if i % 2 else stone) + (255,))
    draw.polygon([(x - w * 0.095, y - h * 0.055), (x + w * 0.095, y - h * 0.055), (x, y - h * 0.085)], fill=stone + (255,))
    glow(x, y - h * 0.03, w * 0.025, (255, 220, 140))

    # Obelisk: one needle with a lit tip.
    x, y = footprint("obelisk", w * 0.05)
    draw.polygon([(x - w * 0.016, y), (x + w * 0.016, y), (x + w * 0.006, y - h * 0.15), (x - w * 0.006, y - h * 0.15)], fill=stone + (255,))
    draw.polygon([(x - w * 0.016, y), (x - w * 0.004, y), (x - w * 0.002, y - h * 0.15), (x - w * 0.006, y - h * 0.15)], fill=stone_lit + (255,))
    draw.polygon([(x - w * 0.006, y - h * 0.15), (x + w * 0.006, y - h * 0.15), (x, y - h * 0.165)], fill=(255, 226, 150, 255))
    glow(x, y - h * 0.16, w * 0.02, (255, 226, 150))

    # --- palms along the shore -----------------------------------------------
    for i in range(14):
        a = rnd.uniform(0, math.tau)
        px, py = cx + math.cos(a) * rx * 0.86, cy + math.sin(a) * ry * 0.86
        if any(abs(px / w - lx) < 0.09 and abs(py / h - ly) < 0.07 for lx, ly in LANDMARKS.values()):
            continue
        th = h * rnd.uniform(0.035, 0.06)
        lean = rnd.uniform(-0.25, 0.25)
        top = (px + lean * th, py - th)
        draw.line([(px, py), top], fill=(70, 52, 34, 255), width=S * 4)
        for k in range(6):
            fa = math.tau * k / 6 + rnd.uniform(-0.2, 0.2)
            fl = th * 0.45
            mid = (top[0] + math.cos(fa) * fl * 0.6, top[1] + math.sin(fa) * fl * 0.3 - fl * 0.15)
            end = (top[0] + math.cos(fa) * fl, top[1] + math.sin(fa) * fl * 0.5 + fl * 0.25)
            draw.line([top, mid, end], fill=(58, 96, 52, 255), width=S * 3)

    # --- finish: grain and a vignette -----------------------------------------
    arr = np.asarray(img).astype(np.int16)
    noise = np.random.default_rng(3).integers(-2, 3, size=arr.shape[:2], dtype=np.int16)[:, :, None]
    arr = np.clip(arr + noise, 0, 255).astype(np.uint8)
    img = Image.fromarray(arr).resize((W, H), Image.LANCZOS)
    yy, xx = np.mgrid[0:H, 0:W]
    v = np.sqrt(((xx - W / 2) / (W / 2)) ** 2 + ((yy - H / 2) / (H / 2)) ** 2)
    shade = np.clip(1.0 - 0.45 * np.clip(v - 0.55, 0, 1) ** 1.5, 0, 1)
    out = (np.asarray(img).astype(np.float32) * shade[:, :, None]).astype(np.uint8)
    OUT.parent.mkdir(parents=True, exist_ok=True)
    Image.fromarray(out).save(OUT, "PNG", optimize=True)
    print(f"{OUT.relative_to(REPO)}  {W}x{H}  {OUT.stat().st_size // 1024} KB")


if __name__ == "__main__":
    main()
