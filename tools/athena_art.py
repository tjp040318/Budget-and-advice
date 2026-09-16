#!/usr/bin/env python3
"""Paints and ships the guide's portraits.

    python3 tools/athena_art.py                  # what it would paint
    python3 tools/athena_art.py --paint          # one 2x2 sheet, 6 credits
    python3 tools/athena_art.py --ship           # key off the black and ship
    python3 tools/athena_art.py --sheet x.jpg    # what shipped, to look at

The guide of the opening (`Guide.swift`) is a VOICE, never a unit — the
owner: "Athena should be just a voice. Ellia can't battle." So she needs
portraits and nothing else: no cards, no mesh, no place in the collection.

FOUR expressions in ONE image, as a 2 x 2 grid. One generation, because
`meshy.py picture` takes a prompt and nothing else — there is no reference
image on that endpoint, so two generations are two different women. A 1024
sheet gives 512-pixel cells, which is the size a 140-point bust wants on a
3x phone; nine cells would have given 341 and a softer face. Proud and
delighted are a second sheet if they are ever wanted, and that sheet's face
will drift from this one, which is the cost of the endpoint.

She is DESCRIBED, never named: a named god comes back as a photograph of an
actor (Loki did, and the file was deleted).
"""
import argparse
import subprocess
import sys
from pathlib import Path

import numpy as np
from PIL import Image

REPO = Path(__file__).resolve().parents[1]
SRC = REPO / "Art" / "Guide"
DST = REPO / "Pantheon" / "Resources" / "Portraits"
GRID = 2
SIZE = 512
FLOOR = 1500

# The order is the reading order of the grid: top-left, top-right,
# bottom-left, bottom-right.
FACES = [
    ("calm", "calm and composed, looking straight at the viewer"),
    ("pleased", "warm and pleased, a small proud smile"),
    ("concerned", "concerned, her brows drawn together"),
    ("urging", "urgent and commanding, one hand raised with the index finger pointing"),
]

STYLE = (
    "A 2 by 2 grid of four painted portrait busts of the SAME young woman — "
    "the same face, the same hair, the same costume in all four cells, only "
    "her expression changes. Painted in a rich classical Greek mythology "
    "video game style with warm rim light, painted brush detail and a "
    "luminous edge. She has grey eyes and dark hair bound up, a bronze war "
    "helmet pushed back off her forehead, a white chiton with a gold "
    "shoulder clasp, and a small owl perched at her shoulder. Each bust is "
    "shown from the chest up, turned slightly so she faces into the picture. "
    "The entire image background is solid pure black, edge to edge, and each "
    "bust floats on that black with black space around it. No frames, no "
    "borders, no panels, no plaques, no text, no letters, no captions, no "
    "signature, no background scenery. "
)


def prompt() -> str:
    rows = [
        "Top row, left to right: " + "; ".join(FACES[i][1] for i in (0, 1)) + ". ",
        "Bottom row, left to right: " + "; ".join(FACES[i][1] for i in (2, 3)) + ". ",
    ]
    return STYLE + "".join(rows)


def paint(floor: int, model: str) -> None:
    SRC.mkdir(parents=True, exist_ok=True)
    out = SRC / "sheet.png"
    cmd = [sys.executable, str(REPO / "tools" / "meshy.py"), "picture", "athena_sheet",
           "--prompt", prompt(), "--out", str(out), "--floor", str(floor), "--model", model]
    print("painting:", ", ".join(name for name, _ in FACES))
    subprocess.run(cmd, check=True)


def background(cell: Image.Image) -> np.ndarray:
    """The black GROUND: dark pixels connected to the cell's border. A dark
    fold in her cloak is not background, which is why this is a flood fill
    and not a threshold on brightness."""
    from scipy import ndimage
    grey = np.asarray(cell.convert("L")).astype(np.float32) / 255
    labels, count = ndimage.label(grey < 0.12)
    if count == 0:
        return np.zeros(grey.shape, dtype=bool)
    edge = set(labels[0, :]) | set(labels[-1, :]) | set(labels[:, 0]) | set(labels[:, -1])
    edge.discard(0)
    return np.isin(labels, list(edge))


def ship() -> list[Path]:
    from scipy import ndimage
    path = SRC / "sheet.png"
    if not path.exists():
        sys.exit(f"not painted yet: {path.relative_to(REPO)}")
    DST.mkdir(parents=True, exist_ok=True)
    sheet = Image.open(path).convert("RGB")
    side = min(sheet.size)
    sheet = sheet.resize((side, side), Image.LANCZOS)
    step = side // GRID
    written = []
    for index, (name, _) in enumerate(FACES):
        row, column = divmod(index, GRID)
        cell = sheet.crop((column * step, row * step, (column + 1) * step, (row + 1) * step))
        alpha = (~background(cell)).astype(np.float32)
        alpha = ndimage.gaussian_filter(alpha, 1.0)
        keep = np.argwhere(alpha > 0.4)
        if keep.size == 0:
            print(f"  {name}: empty cell — re-roll")
            continue
        top, left = keep.min(axis=0)
        bottom, right = keep.max(axis=0) + 1
        rgb = np.asarray(cell).astype(np.float32) / 255
        out = np.dstack([rgb, alpha])[top:bottom, left:right]
        image = Image.fromarray(np.clip(out * 255 + 0.5, 0, 255).astype(np.uint8), "RGBA")
        # Square it so every expression draws at the same size in the plate.
        span = max(image.size)
        square = Image.new("RGBA", (span, span), (0, 0, 0, 0))
        square.alpha_composite(image, ((span - image.width) // 2, span - image.height))
        square = square.resize((SIZE, SIZE), Image.LANCZOS)
        target = DST / f"athena_{name}.png"
        square.save(target, optimize=True)
        written.append(target)
        print(f"  {name:10s} -> {target.relative_to(REPO)}  {target.stat().st_size // 1024} KB")
    return written


def contact(out_path: str) -> None:
    files = [DST / f"athena_{name}.png" for name, _ in FACES]
    files = [f for f in files if f.exists()]
    if not files:
        sys.exit("nothing shipped yet")
    cell = 420
    sheet = Image.new("RGB", (cell * len(files), cell), (24, 18, 12))
    for i, f in enumerate(files):
        icon = Image.open(f).convert("RGBA").resize((cell, cell))
        ground = Image.new("RGBA", icon.size, (36, 28, 18, 255))
        ground.alpha_composite(icon)
        sheet.paste(ground.convert("RGB"), (i * cell, 0))
    sheet.save(out_path, quality=92)
    print(f"contact {out_path}")


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--paint", action="store_true")
    ap.add_argument("--ship", action="store_true")
    ap.add_argument("--sheet")
    ap.add_argument("--floor", type=int, default=FLOOR)
    ap.add_argument("--model", default="nano-banana-2")
    a = ap.parse_args()
    if not (a.paint or a.ship or a.sheet):
        print(prompt())
        print(f"\n{len(FACES)} expressions in one sheet, about 6 credits")
        return
    if a.paint:
        paint(a.floor, a.model)
    if a.ship:
        ship()
    if a.sheet:
        contact(a.sheet)


if __name__ == "__main__":
    main()
