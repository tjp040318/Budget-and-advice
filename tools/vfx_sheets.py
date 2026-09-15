#!/usr/bin/env python3
"""Ships the painted effect FLIPBOOK sheets: Art/VFX/sheet_<name>.png (a 4 x 4
grid of sixteen frames on pure black, painted by `meshy.py picture` in Meshy
credits while Gemini is paused) becomes Pantheon/Resources/Portraits/
vfx_<name>_sheet.png, which `VFXLibrary.flipbook(name, rows: 4, cols: 4, ...)`
plays as one screen-facing particle whose texture steps through the cells.

    python3 tools/vfx_sheets.py                 # everything missing or newer
    python3 tools/vfx_sheets.py --force
    python3 tools/vfx_sheets.py --only claw,sunburst
    python3 tools/vfx_sheets.py --contact x.jpg # the shipped sheets, to look at

Unlike `vfx_ship.py` nothing is trimmed: the cells must stay on their grid.
The alpha is the brightest channel, the colour divided back out of it (so the
file works added and blended), and every cell is faded to nothing over its
outer ring — a painter's brightest frame fills its cell to the corners, and a
square of light bursting on a victim was the one thing a sheet could do
wrong. Sheets are 1024 px (256 a frame); a burst 2.4 m wide 14 m from the
lens is about 150 px on the phone.
"""
import argparse
from pathlib import Path

import numpy as np
from PIL import Image

REPO = Path(__file__).resolve().parents[1]
SRC = REPO / "Art" / "VFX"
DST = REPO / "Pantheon" / "Resources" / "Portraits"
GRID = 4
SIZE = 1024


def ship(src: Path, dst: Path) -> None:
    im = Image.open(src).convert("RGB")
    if im.size != (SIZE, SIZE):
        im = im.resize((SIZE, SIZE), Image.LANCZOS)
    rgb = np.asarray(im).astype(np.float32) / 255.0
    alpha = rgb.max(axis=2)
    # Un-premultiply so the colour of a faint pixel is its hue at full
    # strength and the alpha carries the faintness.
    colour = rgb / np.maximum(alpha, 1e-3)[..., None]
    colour = np.clip(colour, 0, 1)
    # A soft circular fade over every cell's outer ring, so no frame ends at
    # a straight edge whatever the painter did in the corners.
    cell = SIZE // GRID
    yy, xx = np.mgrid[0:cell, 0:cell]
    radius = np.hypot((xx + 0.5) / cell - 0.5, (yy + 0.5) / cell - 0.5) * 2  # 0 at the centre, 1 at the edge midpoints
    fade = np.clip((1.0 - radius) / 0.28, 0, 1)  # full inside 72% of the way out, gone at the edge
    fade = fade * fade * (3 - 2 * fade)
    mask = np.tile(fade, (GRID, GRID))
    alpha = alpha * mask
    out = np.dstack([colour, alpha])
    Image.fromarray(np.clip(out * 255 + 0.5, 0, 255).astype(np.uint8), "RGBA").save(dst, optimize=True)


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--force", action="store_true")
    ap.add_argument("--only", help="comma list of names (claw, sunburst, ...)")
    ap.add_argument("--contact", help="write a contact sheet of the shipped files here")
    a = ap.parse_args()
    only = {n.strip() for n in a.only.split(",")} if a.only else None
    shipped = []
    for src in sorted(SRC.glob("sheet_*.png")):
        name = src.stem[len("sheet_"):]
        if only and name not in only:
            continue
        dst = DST / f"vfx_{name}_sheet.png"
        if dst.exists() and not a.force and dst.stat().st_mtime >= src.stat().st_mtime:
            print(f"  {name:12s} up to date")
            shipped.append(dst)
            continue
        ship(src, dst)
        print(f"  {name:12s} -> {dst.relative_to(REPO)}  {dst.stat().st_size // 1024} KB")
        shipped.append(dst)
    if a.contact and shipped:
        cell = 300
        sheet = Image.new("RGB", (4 * (cell + 8) + 8, ((len(shipped) + 3) // 4) * (cell + 8) + 8), (40, 40, 40))
        for i, dst in enumerate(shipped):
            im = Image.open(dst).convert("RGBA")
            ground = Image.new("RGBA", im.size, (40, 40, 40, 255))
            ground.alpha_composite(im)
            sheet.paste(ground.convert("RGB").resize((cell, cell)), (8 + (i % 4) * (cell + 8), 8 + (i // 4) * (cell + 8)))
        sheet.save(a.contact, quality=88)
        print("contact", a.contact)


if __name__ == "__main__":
    main()
