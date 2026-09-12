#!/usr/bin/env python3
"""Render the relic stones: one PNG per (set, slot), a rim template per slot
and an emblem template per set.

A relic is drawn the way the genre draws a rune: the SLOT decides the
silhouette (1 crystal, 2 medallion, 3 shield, 4 hexagon, 5 vial, 6 tablet),
the SET decides the stone's colour and the emblem engraved on it, the
QUALITY decides the rim (tinted by the app from the template) and the grade
and level are drawn by SwiftUI around it.

Every stone is a bevelled gem-cut slab lit from the top left: a distance
transform of the silhouette gives a height field, its gradient a normal map,
and a lambert-plus-specular shade over the set's colour with a stone grain
and a gloss. The emblem is engraved — the same shading with the light turned
round, so its top-left edge is in shadow — in gold, or in dark bronze on a
light stone.

    python3 tools/relic_art.py --sheet /tmp/relics/sheet.jpg    # judge first
    python3 tools/relic_art.py --ship                            # write the bundle files

Gemini is paused (CLAUDE.md), so these are drawn here rather than painted;
a painted set dropped in under the same names replaces them with no code
change.
"""
import argparse
import math
import os
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont
from scipy import ndimage

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "Pantheon" / "Resources" / "Portraits"

SIZE = 320          # shipped pixels
SS = 4              # supersampling
S4 = SIZE * SS

SETS = [
    # name, stone colour, emblem
    ("fury", "#B8323A", "flame"),
    ("aegis", "#3D5A8A", "shield"),
    ("bulwark", "#3E7A4A", "keep"),
    ("zephyr", "#3A9BA6", "wing"),
    ("thunder", "#D08A1E", "bolt"),
    ("ruin", "#6E2A5A", "burst"),
    ("oracle", "#6B4FB0", "eye"),
    ("wards", "#35437A", "seal"),
    ("ichor", "#8E3A1E", "chalice"),
    ("wrath", "#A0306E", "triskelion"),
    ("styx", "#23414A", "waves"),
    ("chains", "#55606B", "links"),
    ("fates", "#C9CCD3", "wheel"),
    ("nemesis", "#7A2E2E", "scales"),
    ("titanfall", "#7A5A3A", "mountain"),
    ("vigil", "#7C6428", "return"),
]

SLOT_SHAPES = {1: "crystal", 2: "medallion", 3: "shield", 4: "hexagon", 5: "vial", 6: "tablet"}

# The app's rarity metals (Theme.Rarity.frameStops), top stop then bottom.
QUALITY_METALS = {
    "normal": ("#6E7590", "#3B4157"),
    "magic": ("#7FD6A0", "#2F7A50"),
    "rare": ("#7FC4FF", "#2A5FA8"),
    "hero": ("#C89BFF", "#6B34B8"),
    "legend": ("#FFE49B", "#C08A23"),
}


# ---------------------------------------------------------------- geometry

def hex_to_rgb(h):
    h = h.lstrip("#")
    return np.array([int(h[i:i + 2], 16) for i in (0, 2, 4)], dtype=np.float32) / 255.0


class Path2D:
    """A tiny path builder in unit coordinates (x right, y UP, -1..1) that
    samples curves into polygons. Mirrors SwiftUI's Path vocabulary so the
    numbers could be ported if the drawing ever moves into the app."""

    def __init__(self):
        self.subpaths = []
        self.current = []

    def move(self, x, y):
        self.close()
        self.current = [(x, y)]
        return self

    def line(self, x, y):
        self.current.append((x, y))
        return self

    def quad(self, cx, cy, x, y, n=24):
        x0, y0 = self.current[-1]
        for i in range(1, n + 1):
            t = i / n
            px = (1 - t) ** 2 * x0 + 2 * (1 - t) * t * cx + t * t * x
            py = (1 - t) ** 2 * y0 + 2 * (1 - t) * t * cy + t * t * y
            self.current.append((px, py))
        return self

    def curve(self, c1x, c1y, c2x, c2y, x, y, n=28):
        x0, y0 = self.current[-1]
        for i in range(1, n + 1):
            t = i / n
            a, b, c, d = (1 - t) ** 3, 3 * (1 - t) ** 2 * t, 3 * (1 - t) * t * t, t ** 3
            self.current.append((a * x0 + b * c1x + c * c2x + d * x, a * y0 + b * c1y + c * c2y + d * y))
        return self

    def arc(self, cx, cy, r, a0, a1, n=48):
        """Degrees, counter-clockwise in a y-up frame. Continues the subpath."""
        pts = [(cx + r * math.cos(math.radians(a0 + (a1 - a0) * i / n)),
                cy + r * math.sin(math.radians(a0 + (a1 - a0) * i / n))) for i in range(n + 1)]
        if not self.current:
            self.current = pts
        else:
            self.current.extend(pts)
        return self

    def close(self):
        if len(self.current) >= 3:
            self.subpaths.append(self.current)
        self.current = []
        return self

    def circle(self, cx, cy, r):
        self.close()
        self.arc(cx, cy, r, 0, 360, 96)
        return self.close()

    def polygon(self, pts):
        self.close()
        self.current = list(pts)
        return self.close()

    def rounded_polygon(self, pts, radius, n=10):
        """Corners rounded by `radius` (a quadratic per corner)."""
        self.close()
        out = []
        k = len(pts)
        for i in range(k):
            p0, p1, p2 = np.array(pts[i - 1]), np.array(pts[i]), np.array(pts[(i + 1) % k])
            d0 = p0 - p1
            d2 = p2 - p1
            l0, l2 = np.linalg.norm(d0), np.linalg.norm(d2)
            r = min(radius, l0 / 2, l2 / 2)
            a = p1 + d0 / l0 * r
            b = p1 + d2 / l2 * r
            out.append(tuple(a))
            for j in range(1, n + 1):
                t = j / n
                q = (1 - t) ** 2 * a + 2 * (1 - t) * t * p1 + t * t * b
                out.append(tuple(q))
        self.current = out
        return self.close()

    def transformed(self, scale=1.0, dx=0.0, dy=0.0, rotate=0.0):
        p = Path2D()
        c, s = math.cos(math.radians(rotate)), math.sin(math.radians(rotate))
        for sp in self.subpaths:
            p.subpaths.append([((x * c - y * s) * scale + dx, (x * s + y * c) * scale + dy) for x, y in sp])
        return p

    def bbox(self):
        xs = [x for sp in self.subpaths for x, _ in sp]
        ys = [y for sp in self.subpaths for _, y in sp]
        return min(xs), min(ys), max(xs), max(ys)


def mask_of(path, size=S4, scale=None, offset=(0.0, 0.0)):
    """Even-odd fill of the path's subpaths into a bool array (size×size).
    Unit coordinate (0,0) is the centre; +y is up; `scale` px per unit."""
    if scale is None:
        scale = size / 2 * 0.94
    acc = None
    for sp in path.subpaths:
        img = Image.new("L", (size, size), 0)
        d = ImageDraw.Draw(img)
        pts = [(size / 2 + (x + offset[0]) * scale, size / 2 - (y + offset[1]) * scale) for x, y in sp]
        d.polygon(pts, fill=255)
        m = np.array(img) > 127
        acc = m if acc is None else (acc ^ m)
    return acc if acc is not None else np.zeros((size, size), bool)


# ---------------------------------------------------------------- slot shapes

def shape_path(name):
    p = Path2D()
    if name == "crystal":
        # A tall gem: pointed top and bottom, a shoulder above the middle.
        return p.rounded_polygon([(0, 1.0), (0.58, 0.42), (0.58, -0.5), (0, -1.0), (-0.58, -0.5), (-0.58, 0.42)], 0.06)
    if name == "medallion":
        return p.circle(0, 0, 0.94)
    if name == "shield":
        p.move(-0.86, 0.72)
        p.quad(-0.86, 0.9, -0.62, 0.9)
        p.line(0.62, 0.9)
        p.quad(0.86, 0.9, 0.86, 0.72)
        p.line(0.86, 0.15)
        p.curve(0.86, -0.45, 0.42, -0.85, 0, -1.0)
        p.curve(-0.42, -0.85, -0.86, -0.45, -0.86, 0.15)
        return p.close()
    if name == "hexagon":
        pts = [(0.95 * math.cos(math.radians(a)), 0.95 * math.sin(math.radians(a))) for a in range(30, 390, 60)]
        return p.rounded_polygon(pts, 0.08)
    if name == "vial":
        # A drop: the apex at the top, a round belly.
        p.move(0, 1.0)
        p.curve(0.34, 0.55, 0.78, 0.2, 0.78, -0.3)
        p.arc(0, -0.3, 0.78, 0, -180, 60)
        p.curve(-0.78, 0.2, -0.34, 0.55, 0, 1.0)
        return p.close()
    if name == "tablet":
        w, h, c = 0.82, 0.96, 0.26
        return p.rounded_polygon([(-w + c, h), (w - c, h), (w, h - c), (w, -h + c), (w - c, -h), (-w + c, -h), (-w, -h + c), (-w, h - c)], 0.05)
    raise ValueError(name)


# ---------------------------------------------------------------- emblems

def emblem_path(name):
    p = Path2D()
    if name == "flame":
        p.move(0, 1.0)
        p.curve(0.55, 0.55, 0.72, 0.1, 0.5, -0.4)
        p.curve(0.4, -0.7, 0.2, -0.95, 0, -1.0)
        p.curve(-0.2, -0.95, -0.62, -0.7, -0.56, -0.2)
        p.curve(-0.52, 0.15, -0.3, 0.3, -0.36, 0.55)
        p.curve(-0.2, 0.5, -0.12, 0.35, -0.1, 0.2)
        p.curve(0.1, 0.5, 0.15, 0.75, 0, 1.0)
        p.close()
        # An inner tongue, cut out.
        p.move(0.02, 0.12)
        p.curve(0.3, -0.15, 0.32, -0.45, 0.1, -0.68)
        p.curve(-0.12, -0.5, -0.3, -0.3, -0.16, -0.05)
        p.curve(-0.08, 0.05, 0.0, 0.05, 0.02, 0.12)
        return p.close()
    if name == "shield":
        p.move(-0.8, 0.75).line(0.8, 0.75).line(0.8, 0.1)
        p.curve(0.8, -0.5, 0.35, -0.85, 0, -1.0)
        p.curve(-0.35, -0.85, -0.8, -0.5, -0.8, 0.1)
        p.close()
        # A chevron cut out of it.
        p.move(-0.5, 0.25).line(0, -0.2).line(0.5, 0.25).line(0.5, -0.05).line(0, -0.5).line(-0.5, -0.05)
        return p.close()
    if name == "keep":
        # A crenellated tower with a door.
        pts = [(-0.7, -1.0), (-0.7, 0.55), (-0.45, 0.55), (-0.45, 0.95), (-0.15, 0.95), (-0.15, 0.55),
               (0.15, 0.55), (0.15, 0.95), (0.45, 0.95), (0.45, 0.55), (0.7, 0.55), (0.7, -1.0)]
        p.polygon(pts)
        p.move(-0.2, -1.0).line(-0.2, -0.35)
        p.arc(0, -0.35, 0.2, 180, 0, 20)
        p.line(0.2, -1.0)
        p.close()
        # Two arrow slits.
        p.polygon([(-0.32, 0.05), (-0.18, 0.05), (-0.18, 0.4), (-0.32, 0.4)])
        p.polygon([(0.18, 0.05), (0.32, 0.05), (0.32, 0.4), (0.18, 0.4)])
        return p
    if name == "wing":
        # Three swept feathers from a root at the lower left.
        for i, (tipx, tipy, w) in enumerate([(0.95, 0.75, 0.26), (0.95, 0.15, 0.24), (0.8, -0.5, 0.22)]):
            rx, ry = -0.85, -0.7 + i * 0.12
            p.move(rx, ry)
            p.curve(rx + 0.3, ry + 0.9 - i * 0.25, tipx - 0.5, tipy + 0.35, tipx, tipy)
            p.curve(tipx - 0.35, tipy - 0.1 - w, rx + 0.45, ry + 0.25, rx, ry)
            p.close()
        return p
    if name == "bolt":
        return p.polygon([(0.15, 1.0), (-0.55, 0.05), (-0.05, 0.05), (-0.35, -1.0), (0.55, 0.15), (0.05, 0.15)])
    if name == "burst":
        pts = []
        for i in range(8):
            a = math.radians(90 + i * 45)
            r = 1.0 if i % 2 == 0 else 0.42
            pts.append((r * math.cos(a), r * math.sin(a)))
            a2 = math.radians(90 + i * 45 + 22.5)
            pts.append((0.42 * math.cos(a2), 0.42 * math.sin(a2)) if i % 2 == 0 else (0.72 * math.cos(a2), 0.72 * math.sin(a2)))
        p.polygon(pts)
        p.circle(0, 0, 0.16)
        return p
    if name == "eye":
        p.move(-1.0, 0)
        p.curve(-0.55, 0.62, 0.55, 0.62, 1.0, 0)
        p.curve(0.55, -0.62, -0.55, -0.62, -1.0, 0)
        p.close()
        p.circle(0, 0, 0.36)
        p.circle(0, 0, 0.16)
        return p
    if name == "seal":
        p.circle(0, 0, 1.0)
        p.circle(0, 0, 0.8)
        tri = [(0, -0.72), (0.62, 0.36), (-0.62, 0.36)]
        p.polygon(tri)
        p.polygon([(0, -0.42), (0.36, 0.21), (-0.36, 0.21)])
        p.circle(0, 0, 0.12)
        return p
    if name == "chalice":
        p.move(-0.85, 0.85).line(0.85, 0.85)
        p.curve(0.85, 0.25, 0.55, -0.1, 0.12, -0.15)
        p.line(0.12, -0.55)
        p.line(0.45, -0.72).line(0.45, -0.95).line(-0.45, -0.95).line(-0.45, -0.72).line(-0.12, -0.55)
        p.line(-0.12, -0.15)
        p.curve(-0.55, -0.1, -0.85, 0.25, -0.85, 0.85)
        p.close()
        p.polygon([(-0.62, 0.7), (0.62, 0.7), (0.62, 0.52), (-0.62, 0.52)])
        return p
    if name == "triskelion":
        for k in range(3):
            arm = Path2D()
            arm.move(0, 0)
            arm.curve(0.55, 0.15, 0.85, 0.55, 0.55, 0.95)
            arm.curve(0.95, 0.7, 0.95, 0.1, 0.3, -0.15)
            arm.close()
            p.subpaths.extend(arm.transformed(rotate=k * 120).subpaths)
        p.circle(0, 0, 0.2)
        return p
    if name == "waves":
        for y0 in (0.45, -0.05, -0.55):
            p.move(-1.0, y0)
            p.curve(-0.7, y0 + 0.45, -0.3, y0 + 0.45, 0, y0)
            p.curve(0.3, y0 - 0.45, 0.7, y0 - 0.45, 1.0, y0)
            p.line(1.0, y0 - 0.22)
            p.curve(0.7, y0 - 0.67, 0.3, y0 - 0.67, 0, y0 - 0.22)
            p.curve(-0.3, y0 + 0.23, -0.7, y0 + 0.23, -1.0, y0 - 0.22)
            p.close()
        return p
    if name == "links":
        for dx, dy in ((-0.38, 0.32), (0.38, -0.32)):
            ring = Path2D()
            outer = [(0.72 * math.cos(math.radians(a)), 0.5 * math.sin(math.radians(a))) for a in range(0, 360, 6)]
            inner = [(0.44 * math.cos(math.radians(a)), 0.24 * math.sin(math.radians(a))) for a in range(0, 360, 6)]
            ring.polygon(outer)
            ring.polygon(inner)
            p.subpaths.extend(ring.transformed(rotate=-40, dx=dx, dy=dy).subpaths)
        return p
    if name == "wheel":
        p.circle(0, 0, 1.0)
        p.circle(0, 0, 0.78)
        for k in range(8):
            spoke = Path2D().polygon([(-0.09, 0), (0.09, 0), (0.09, 0.9), (-0.09, 0.9)])
            p.subpaths.extend(spoke.transformed(rotate=k * 45).subpaths)
        p.circle(0, 0, 0.22)
        return p
    if name == "scales":
        p.polygon([(-0.08, -0.6), (0.08, -0.6), (0.08, 0.72), (-0.08, 0.72)])          # post
        p.polygon([(-0.95, 0.62), (0.95, 0.62), (0.95, 0.5), (-0.95, 0.5)])            # beam
        p.polygon([(-0.4, -0.6), (0.4, -0.6), (0.5, -0.78), (-0.5, -0.78)])            # foot
        for sx in (-0.72, 0.72):
            pan = Path2D()
            pan.move(-0.36, 0.0)
            pan.arc(0, 0.0, 0.36, 180, 360, 24)
            pan.close()
            p.subpaths.extend(pan.transformed(dx=sx, dy=-0.1).subpaths)
            p.polygon([(sx - 0.03, 0.5), (sx + 0.03, 0.5), (sx + 0.03, -0.1), (sx - 0.03, -0.1)])
        return p
    if name == "mountain":
        p.polygon([(-1.0, -0.8), (-0.35, 0.55), (-0.05, 0.15), (0.3, 0.95), (1.0, -0.8)])
        # Snow caps cut out as the far side's shading.
        p.polygon([(0.3, 0.95), (0.55, 0.42), (0.42, 0.42), (0.3, 0.55), (0.18, 0.42), (0.05, 0.42)])
        return p
    if name == "return":
        # A U-turn arrow: a thick arc from the lower right round the top to
        # the left, ending in a head pointing down.
        p.move(0.55, -0.75)
        p.line(0.55, 0.1)
        p.arc(0.05, 0.1, 0.5, 0, 180, 40)
        p.line(-0.45, -0.25)
        p.line(-0.15, -0.25)
        p.line(-0.15, 0.1)
        p.arc(0.05, 0.1, 0.2, 180, 0, 20)
        p.line(0.25, -0.75)
        p.close()
        p.polygon([(-0.85, -0.2), (-0.05, -0.2), (-0.45, -0.85)])
        return p
    raise ValueError(name)


# ---------------------------------------------------------------- shading

def normalize(v):
    return v / (np.linalg.norm(v) + 1e-9)


LIGHT = normalize(np.array([-0.55, -0.75, 0.55]))   # image space: y down, so -y is up
HALF = normalize(LIGHT + np.array([0, 0, 1.0]))


def height_field(mask, width_px, profile="pillow"):
    d = ndimage.distance_transform_edt(mask)
    h = np.clip(d / max(1.0, width_px), 0, 1)
    if profile == "pillow":
        h = np.sin(h * math.pi / 2)
    return h.astype(np.float32)


def shade(h, steep=2.2, light=LIGHT, spec_power=28.0):
    gy, gx = np.gradient(h)
    nx, ny, nz = -gx * steep, -gy * steep, np.ones_like(h) / 1.0
    n = np.stack([nx, ny, nz], -1)
    n /= np.linalg.norm(n, axis=-1, keepdims=True) + 1e-9
    diffuse = np.clip(n @ light, 0, 1)
    half = normalize(light + np.array([0, 0, 1.0]))
    spec = np.clip(n @ half, 0, 1) ** spec_power
    return diffuse, spec


def smooth_noise(size, cells, seed):
    rng = np.random.default_rng(seed)
    small = rng.random((cells, cells)).astype(np.float32)
    img = Image.fromarray((small * 255).astype(np.uint8)).resize((size, size), Image.BICUBIC)
    return np.array(img).astype(np.float32) / 255.0


def render_stone(set_name, colour_hex, emblem_name, slot):
    shape = shape_path(SLOT_SHAPES[slot])
    M = mask_of(shape)
    base = hex_to_rgb(colour_hex)
    lum = float(0.299 * base[0] + 0.587 * base[1] + 0.114 * base[2])

    yy, xx = np.mgrid[0:S4, 0:S4].astype(np.float32)
    u = (xx / S4) * 2 - 1
    v = (yy / S4) * 2 - 1     # +1 at the bottom

    # The stone's colour: lighter at the top, darker at the bottom, a gloss
    # at the upper left, and a grain.
    top = np.clip(base * 1.0 + (1 - base) * 0.22, 0, 1)
    bottom = np.clip(base * 0.62, 0, 1)
    t = ((v + 1) / 2)[..., None]
    col = top * (1 - t) + bottom * t
    gloss = np.exp(-(((u + 0.35) ** 2 + (v + 0.5) ** 2) / 0.32))
    col = col + gloss[..., None] * 0.20
    # A faint grain: a broad marbling and a fine tooth. The first cut had
    # ten percent of blotch and photographed as camouflage.
    grain = (smooth_noise(S4, 9, 7) - 0.5) * 0.06 + (smooth_noise(S4, 160, 11) - 0.5) * 0.025
    col = col * (1 + grain[..., None])

    # The cut edge.
    bevel = 0.075 * S4
    h = height_field(M, bevel)
    diffuse, spec = shade(h, steep=2.4)
    lit = 0.50 + 0.62 * diffuse
    col = col * lit[..., None] + spec[..., None] * 0.55
    # A darker line along the very edge so the silhouette holds on cream.
    edge = M & ~ndimage.binary_erosion(M, iterations=int(0.012 * S4))
    col = np.where(edge[..., None], col * 0.55, col)

    # The emblem, engraved. Fitted into the stone's inner box.
    inner = ndimage.binary_erosion(M, iterations=int(0.125 * S4))
    ys, xs = np.nonzero(inner)
    cx, cy = (xs.min() + xs.max()) / 2, (ys.min() + ys.max()) / 2
    iw, ih = xs.max() - xs.min(), ys.max() - ys.min()
    emblem = emblem_path(emblem_name)
    bx0, by0, bx1, by1 = emblem.bbox()
    ew, eh = bx1 - bx0, by1 - by0
    fit = min(iw / ew, ih / eh) * 0.98
    ecx, ecy = (bx0 + bx1) / 2, (by0 + by1) / 2
    E = mask_of(emblem.transformed(dx=-ecx, dy=-ecy), scale=fit,
                offset=((cx - S4 / 2) / fit, -(cy - S4 / 2) / fit))
    E &= M

    if lum > 0.55:
        gold_top, gold_bot = hex_to_rgb("#5C4611"), hex_to_rgb("#2E2208")
    else:
        gold_top, gold_bot = hex_to_rgb("#F6DC8C"), hex_to_rgb("#A8802A")
    te = np.clip(((yy - (cy - ih / 2)) / max(1, ih)), 0, 1)[..., None]
    gold = gold_top * (1 - te) + gold_bot * te
    he = height_field(E, 0.018 * S4, profile="linear")
    ed, es = shade(he, steep=3.0, light=normalize(np.array([0.55, 0.75, 0.55])), spec_power=20)
    gold = gold * (0.55 + 0.6 * ed)[..., None] + es[..., None] * 0.35
    # A shadow ring around the carve, on the stone.
    ring = ndimage.binary_dilation(E, iterations=int(0.008 * S4)) & ~E
    col = np.where(ring[..., None], col * 0.72, col)
    col = np.where(E[..., None], gold, col)

    col = np.clip(col, 0, 1)
    rgba = np.zeros((S4, S4, 4), np.float32)
    rgba[..., :3] = col
    rgba[..., 3] = M.astype(np.float32)
    img = Image.fromarray((rgba * 255).astype(np.uint8), "RGBA")
    # Premultiply-safe downscale: the colour outside the mask is black, so
    # blur the colour under the alpha edge before resampling.
    return img.resize((SIZE, SIZE), Image.LANCZOS)


def render_rim(slot, width=0.05):
    """The quality rim as a template: white, alpha only. Tinted in the app."""
    M = mask_of(shape_path(SLOT_SHAPES[slot]))
    inner = ndimage.binary_erosion(M, iterations=int(width * S4))
    R = M & ~inner
    h = height_field(R, 0.5 * width * S4)
    diffuse, spec = shade(h, steep=2.0)
    a = R.astype(np.float32) * (0.72 + 0.28 * diffuse) + spec * 0.3
    rgba = np.zeros((S4, S4, 4), np.float32)
    rgba[..., :3] = 1.0
    rgba[..., 3] = np.clip(a, 0, 1)
    return Image.fromarray((rgba * 255).astype(np.uint8), "RGBA").resize((SIZE, SIZE), Image.LANCZOS)


def render_emblem(name, size=128):
    E = mask_of(emblem_path(name).transformed(scale=0.92), size=size * SS)
    rgba = np.zeros((size * SS, size * SS, 4), np.float32)
    rgba[..., :3] = 1.0
    rgba[..., 3] = E
    return Image.fromarray((rgba * 255).astype(np.uint8), "RGBA").resize((size, size), Image.LANCZOS)


# ---------------------------------------------------------------- sheets

def tint(template, top_hex, bottom_hex):
    """The app's `.foregroundStyle(rarity.frame)` on a template image."""
    a = np.array(template).astype(np.float32)[..., 3] / 255.0
    h = template.size[1]
    t = (np.arange(h) / max(1, h - 1))[:, None]
    top, bottom = hex_to_rgb(top_hex), hex_to_rgb(bottom_hex)
    col = top[None, None, :] * (1 - t[..., None]) + bottom[None, None, :] * t[..., None]
    col = np.broadcast_to(col, (h, template.size[0], 3))
    out = np.zeros((h, template.size[0], 4), np.float32)
    out[..., :3] = col
    out[..., 3] = a
    return Image.fromarray((out * 255).astype(np.uint8), "RGBA")


def composed(stone, rim, quality, px):
    icon = stone.resize((px, px), Image.LANCZOS)
    icon.alpha_composite(tint(rim, *QUALITY_METALS[quality]).resize((px, px), Image.LANCZOS))
    return icon


def sheet(path, stones, rims):
    cream = (0xEB, 0xE2, 0xCF)
    cell, pad = 104, 8
    cols = 6
    font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", 13)
    small = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", 11)
    w = 150 + cols * (cell + pad) + pad
    h = pad + len(SETS) * (cell + pad) + 520
    img = Image.new("RGB", (w, h), cream)
    d = ImageDraw.Draw(img)
    qualities = list(QUALITY_METALS)
    for r, (name, colour, emblem) in enumerate(SETS):
        y = pad + r * (cell + pad)
        d.text((10, y + cell / 2 - 8), name.upper(), fill=(0x1F, 0x19, 0x12), font=font)
        for c in range(6):
            slot = c + 1
            q = qualities[(r + c) % 5]
            icon = composed(stones[(name, slot)], rims[slot], q, cell - 12)
            x = 150 + c * (cell + pad)
            img.paste(icon, (x + 6, y + 2), icon)
            d.text((x + 6, y + cell - 12), f"{slot} · {q}", fill=(0x6D, 0x5F, 0x4B), font=small)
    # The sizes the app draws: 30, 44, 64 and 110 points, at 3x (device
    # pixels) and at 1x (about what the eye gets on the phone).
    y = pad + len(SETS) * (cell + pad) + 4
    d.text((10, y), "at the app's sizes: 30pt row, 44pt tile, 64pt slot, 110pt card - device pixels (3x), then 1x", fill=(0x1F, 0x19, 0x12), font=font)
    x = 12
    for px in (90, 132, 192, 330):
        for sample in (("fury", 3, "legend"), ("styx", 5, "rare")):
            icon = composed(stones[(sample[0], sample[1])], rims[sample[1]], sample[2], px)
            img.paste(icon, (x, y + 30 + (330 - px)), icon)
            x += px + 10
        x += 20
    x = 12
    for px in (30, 44, 64, 110):
        icon = composed(stones[("fury", 3)], rims[3], "legend", px)
        img.paste(icon, (x, y + 380), icon)
        x += px + 16
    img.save(path, quality=92)
    return path


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--sheet", help="write a preview sheet (jpg) instead of shipping")
    ap.add_argument("--ship", action="store_true", help="write the bundle files")
    ap.add_argument("--only", help="one set name, for a quick look")
    ap.add_argument("--emblems", help="write a sheet of the sixteen emblems alone")
    args = ap.parse_args()

    sets = [s for s in SETS if not args.only or s[0] == args.only]
    stones, rims = {}, {}
    for slot in range(1, 7):
        rims[slot] = render_rim(slot)
    for name, colour, emblem in sets:
        for slot in range(1, 7):
            stones[(name, slot)] = render_stone(name, colour, emblem, slot)
        print(f"rendered {name}")

    if args.emblems:
        cream = (0xEB, 0xE2, 0xCF)
        img = Image.new("RGB", (16 * 72 + 8, 80), cream)
        for i, (name, colour, emblem) in enumerate(SETS):
            e = tint(render_emblem(emblem, 64), "#B08A2E", "#8C6D22")
            img.paste(e, (8 + i * 72, 8), e)
        img.save(args.emblems, quality=92)
        print("wrote", args.emblems)
    if args.sheet:
        print("wrote", sheet(args.sheet, stones, rims))
    if args.ship:
        OUT.mkdir(parents=True, exist_ok=True)
        for (name, slot), img in stones.items():
            img.save(OUT / f"relic_{name}_{slot}.png", optimize=True)
        for slot, img in rims.items():
            img.save(OUT / f"relic_rim_{slot}.png", optimize=True)
        for name, colour, emblem in SETS:
            render_emblem(emblem).save(OUT / f"relic_emblem_{name}.png", optimize=True)
        total = sum(f.stat().st_size for f in OUT.glob("relic_*.png"))
        print(f"shipped {len(list(OUT.glob('relic_*.png')))} files, {total / 1e6:.1f} MB")


if __name__ == "__main__":
    main()
