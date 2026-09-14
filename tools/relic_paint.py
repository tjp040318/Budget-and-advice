#!/usr/bin/env python3
"""Paint the sixteen relic stones with Gemini, from the rendered stones as
the reference, and fit the paintings into the app's own hexagon.

    python3 tools/relic_paint.py --reference out/ref.png          # the 4×4 sheet of rendered stones on black
    python3 tools/relic_paint.py --paint out/ref.png out/paint.png # ONE Gemini image (about 14 cents)
    python3 tools/relic_paint.py --split out/paint.png --sheet out/judge.jpg   # key, cut, fit, judge
    python3 tools/relic_paint.py --split out/paint.png --ship                  # write relic_<set>.png
    python3 tools/relic_paint.py --single fury --reference out/fury_ref.png    # one stone's reference, for a re-roll
    python3 tools/relic_paint.py --single fury --split out/fury_paint.png --ship

Why a sheet and not sixteen singles: one painting of sixteen stones is one
style by construction, and one image is a seventh of the price of sixteen;
a cell that came out wrong is re-rolled alone from its own render. Why the
rendered stones as the reference: the seals are ours (the aspis, the Doric
column, the torch) and a reference holds the painter to them, where a
description would not. Why black: the stones are keyed off the ground by
darkness, flood-filled from the border so a dark carve inside a stone
survives; the sprites learned the same on 2026-09-10.

The painting supplies the surface — the mineral, the gloss, the carved
gold — and the code supplies the cut: every painted stone is scaled to
cover the renderer's hexagon (`relic_art.stone_path`) and clipped to it,
so the rim template the app tints still fits and no Swift changes. The
emblems stay the line seals; they are chips at twelve points.

Gemini's key is `GEMINI_API_KEY` in the environment; this tool never
prints or writes it. It calls the painter only under `--paint`, once per
call, and only when the owner has said so for this batch (2026-09-14: "Do
the painted relics. I want those to look better.").
"""
import argparse
import subprocess
import sys
from pathlib import Path

import numpy as np
from PIL import Image
from scipy import ndimage

sys.path.insert(0, str(Path(__file__).resolve().parent))
import relic_art  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "Pantheon" / "Resources" / "Portraits"

GRID = 4
CANVAS = 2048
CELL = 480
MARGIN = (CANVAS - GRID * CELL) // 2    # 64
STONE = 360                             # the rendered stone's size in a cell
SINGLE_CANVAS = 1024

PROMPT = (
    "Repaint this reference sheet as premium hand-painted fantasy game icons: "
    "{count} relic stones, each a polished faceted gemstone slab cut as the SAME "
    "pointy-top hexagon with a bevelled edge that catches a soft light from the "
    "upper left, rich saturated mineral colour with subtle veining and a glossy "
    "highlight, and its symbol ENGRAVED into the face as fine chiselled gold "
    "linework with an inner shadow. Keep every stone in exactly the same position, "
    "size, orientation, colour family and symbol as in the reference, {layout}, on "
    "a pure black background. Painterly AAA mobile RPG icon style, crisp and "
    "readable at small size. No glow, no drop shadow, no reflection on the ground, "
    "nothing between or around the stones"
)


# The sixteen devices, described for a sculptor. The first paintings copied
# the line seals of `relic_art.emblem_strokes` faithfully and the owner
# called the symbols "basic, as if drawn by a kid" (2026-09-14): the seals
# were drawn for legibility at twelve points, and a painter handed a
# stick figure paints a stick figure. Each set's subject is kept — the
# aspis, the column, the torch — and given the detail a coin's device has.
SYMBOLS = {
    "fury": "a roaring flame with three curling tongues and embers rising from it",
    "aegis": "a round Greek hoplite shield seen face on, a snarling gorgon's head as its boss, a laurel wreath around its rim",
    "bulwark": "a Doric temple column with a fluted shaft, a carved capital and a stepped base, a fortress wall behind it",
    "zephyr": "a single feathered wing sweeping to the right with three streaming wind lines behind it",
    "thunder": "a jagged thunderbolt clasped in an eagle's talon, sparks at its tips",
    "ruin": "two swords with ornate hilts crossed over a broken laurel wreath",
    "oracle": "an all-seeing eye within a sunburst of rays, a teardrop of the Eye of Horus below it",
    "wards": "a pentagonal amulet with a ring of small runes around it and a gem at its centre, engraved directly into the stone's face with the stone visible around it, not a coin and not a medallion",
    "ichor": "an ornate two-handled chalice overflowing with the golden blood of the gods, three drops falling",
    "wrath": "a triskelion of three spiralling arms with a burst of light at its centre",
    "styx": "three cresting waves of the river of the dead with a ferryman's oar across them and a crescent moon above",
    "chains": "three heavy chain links in a diagonal, the last one broken open, engraved directly into the stone's face with the stone visible around them, no plaque, no inner hexagon, no frame",
    "fates": "an eight-spoked wheel of fate with a spindle and a thread wound through its rim",
    "nemesis": "a balance scale whose beam is a sword, a feather in one pan and a heart in the other",
    "titanfall": "a jagged mountain peak split by a lightning crack, a fallen crown at its foot",
    "vigil": "an upright burning torch wrapped in a laurel vine, its flame leaning in a wind",
}

SYMBOL_PROMPT = (
    "Keep this painted hexagonal gemstone exactly as it is: its pointy-top cut, its "
    "colour, its facets and its gloss, on the same pure black background. REPLACE the "
    "thin gold line symbol on its face with an ornate, richly detailed emblem of "
    "{device}, sculpted as a gold bas-relief set into the stone: bevelled edges, fine "
    "chiselled detail, bright highlights on the raised gold and deep shadow in the "
    "recesses, like the device struck on an ancient coin, filling the central sixty "
    "percent of the face, crisp and readable at small size, one emblem only. No glow, "
    "no drop shadow, no lettering, nothing outside the stone"
)


def symbol_reference(name, path):
    """The shipped painted stone, stood on black at the single's size, as the
    reference for its emblem's repaint."""
    stone = Image.open(OUT / f"relic_{name}.png").convert("RGBA")
    size = int(SINGLE_CANVAS * 0.72)
    stone = stone.resize((size, size), Image.LANCZOS)
    img = Image.new("RGB", (SINGLE_CANVAS, SINGLE_CANVAS), (0, 0, 0))
    img.paste(stone, ((SINGLE_CANVAS - size) // 2, (SINGLE_CANVAS - size) // 2), stone)
    img.save(path)
    print("wrote", path)


def paint_symbol(name, reference_path, out_path):
    cmd = [sys.executable, str(ROOT / "tools" / "genart.py"),
           "--prompt", SYMBOL_PROMPT.format(device=SYMBOLS[name]),
           "--ref", str(reference_path), "--out", str(out_path),
           "--size", f"{SINGLE_CANVAS}x{SINGLE_CANVAS}", "--raw", str(Path(out_path).with_suffix(".raw.png"))]
    subprocess.run(cmd, check=True)


def names(single):
    return [single] if single else [s[0] for s in relic_art.SETS]


def render(name):
    entry = next(s for s in relic_art.SETS if s[0] == name)
    return relic_art.render_stone(*entry)


def cells(single):
    """(name, x, y, size) per cell on the canvas."""
    if single:
        size = int(SINGLE_CANVAS * 0.72)
        return [(single, (SINGLE_CANVAS - size) // 2, (SINGLE_CANVAS - size) // 2, size)]
    out = []
    for index, name in enumerate(names(None)):
        row, col = divmod(index, GRID)
        x = MARGIN + col * CELL + (CELL - STONE) // 2
        y = MARGIN + row * CELL + (CELL - STONE) // 2
        out.append((name, x, y, STONE))
    return out


def reference(path, single=None):
    canvas = SINGLE_CANVAS if single else CANVAS
    img = Image.new("RGB", (canvas, canvas), (0, 0, 0))
    for name, x, y, size in cells(single):
        stone = render(name).resize((size, size), Image.LANCZOS)
        img.paste(stone, (x, y), stone)
    img.save(path)
    print("wrote", path)


def paint(reference_path, out_path, single=None):
    count = "one" if single else "sixteen"
    layout = "centred" if single else "four rows of four, evenly spaced"
    canvas = SINGLE_CANVAS if single else CANVAS
    cmd = [sys.executable, str(ROOT / "tools" / "genart.py"),
           "--prompt", PROMPT.format(count=count, layout=layout),
           "--ref", str(reference_path), "--out", str(out_path),
           "--size", f"{canvas}x{canvas}", "--raw", str(Path(out_path).with_suffix(".raw.png"))]
    subprocess.run(cmd, check=True)


def key(cell_rgb):
    """The stone in a cell: everything not black, flood-filled from the
    border so a dark carve inside the stone is kept. A bool mask."""
    a = cell_rgb.astype(np.float32)
    dark = a.max(-1) < 30
    lab, _ = ndimage.label(dark)
    border = set(np.unique(np.concatenate([lab[0], lab[-1], lab[:, 0], lab[:, -1]])))
    border.discard(0)
    ground = np.isin(lab, list(border))
    stone = ~ground
    # The largest piece, so a stray speck of paint is not the stone.
    lab, n = ndimage.label(stone)
    if n == 0:
        return stone
    sizes = ndimage.sum(stone, lab, range(1, n + 1))
    return lab == (1 + int(np.argmax(sizes)))


def fit(cell_rgb, mask):
    """Scale the painted stone to cover the renderer's hexagon and clip it
    to that hexagon, returning a SIZE×SIZE RGBA image."""
    S4 = relic_art.S4
    M = relic_art.mask_of(relic_art.stone_path())
    mys, mxs = np.nonzero(M)
    tw, th = mxs.max() - mxs.min() + 1, mys.max() - mys.min() + 1
    tcx, tcy = (mxs.min() + mxs.max()) / 2, (mys.min() + mys.max()) / 2
    ys, xs = np.nonzero(mask)
    pw, ph = xs.max() - xs.min() + 1, ys.max() - ys.min() + 1
    scale = 1.03 * max(tw / pw, th / ph)
    # Colour where the painted alpha is zero would bleed black into the
    # clip; fill every outside pixel with its nearest stone pixel first.
    idx = ndimage.distance_transform_edt(~mask, return_distances=False, return_indices=True)
    filled = cell_rgb[idx[0], idx[1]]
    rgba = np.zeros(cell_rgb.shape[:2] + (4,), np.uint8)
    rgba[..., :3] = filled
    rgba[..., 3] = mask.astype(np.uint8) * 255
    img = Image.fromarray(rgba, "RGBA")
    new_w, new_h = int(round(img.width * scale)), int(round(img.height * scale))
    img = img.resize((new_w, new_h), Image.LANCZOS)
    # Centre the painted stone's box on the hexagon's box.
    pcx, pcy = (xs.min() + xs.max()) / 2 * scale, (ys.min() + ys.max()) / 2 * scale
    canvas = Image.new("RGBA", (S4, S4), (0, 0, 0, 0))
    canvas.paste(img, (int(round(tcx - pcx)), int(round(tcy - pcy))), img)
    arr = np.array(canvas).astype(np.float32)
    # The cut: the renderer's hexagon, with its darker line along the edge
    # so the silhouette holds on cream under a Normal rim.
    edge = M & ~ndimage.binary_erosion(M, iterations=int(0.012 * S4))
    col = arr[..., :3] / 255.0
    col = np.where(edge[..., None], col * 0.6, col)
    out = np.zeros((S4, S4, 4), np.float32)
    out[..., :3] = col
    out[..., 3] = M.astype(np.float32)
    return Image.fromarray((out * 255).astype(np.uint8), "RGBA").resize((relic_art.SIZE, relic_art.SIZE), Image.LANCZOS)


def split(painted_path, single=None):
    """The painted sheet cut into stones, keyed and fitted: {name: image}."""
    img = np.array(Image.open(painted_path).convert("RGB"))
    stones = {}
    for name, x, y, size in cells(single):
        pad = size // 6 if not single else 0
        x0, y0 = max(0, x - pad), max(0, y - pad)
        x1, y1 = min(img.shape[1], x + size + pad), min(img.shape[0], y + size + pad)
        cell = img[y0:y1, x0:x1]
        mask = key(cell)
        coverage = mask.mean()
        if coverage < 0.15 or coverage > 0.95:
            print(f"  {name}: suspicious coverage {coverage:.2f}")
        stones[name] = fit(cell, mask)
        print(f"  cut {name}  ({coverage:.0%} of its cell)")
    return stones


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--single", help="one set name: a 1×1 reference / painting instead of the sheet")
    ap.add_argument("--reference", metavar="PNG", help="write the reference sheet here")
    ap.add_argument("--paint", nargs=2, metavar=("REF", "OUT"), help="call Gemini once with REF, write OUT")
    ap.add_argument("--split", metavar="PAINTED", help="key, cut and fit a painted sheet")
    ap.add_argument("--sheet", metavar="JPG", help="with --split: the judging sheet at the app's sizes")
    ap.add_argument("--ship", action="store_true", help="with --split: write relic_<set>.png into the bundle")
    ap.add_argument("--symbol-reference", metavar="PNG", help="with --single: the shipped stone on black, for its emblem's repaint")
    ap.add_argument("--paint-symbol", nargs=2, metavar=("REF", "OUT"), help="with --single: ONE Gemini image repainting the emblem")
    args = ap.parse_args()

    if args.symbol_reference:
        symbol_reference(args.single, args.symbol_reference)
    if args.paint_symbol:
        paint_symbol(args.single, args.paint_symbol[0], args.paint_symbol[1])

    if args.reference:
        reference(args.reference, args.single)
    if args.paint:
        paint(args.paint[0], args.paint[1], args.single)
    if args.split:
        stones = split(args.split, args.single)
        if args.sheet:
            rim = relic_art.render_rim()
            print("wrote", relic_art.sheet(args.sheet, stones, rim))
        if args.ship:
            OUT.mkdir(parents=True, exist_ok=True)
            for name, img in stones.items():
                img.save(OUT / f"relic_{name}.png", optimize=True)
            print(f"shipped {len(stones)} painted stones")


if __name__ == "__main__":
    main()
