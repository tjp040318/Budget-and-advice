#!/usr/bin/env python3
"""
Ships the painted effect sprites: Art/VFX/vfx_<name>.png (Gemini, 1024 px, a
glowing element on pure black) becomes Pantheon/Resources/Portraits/
vfx_<name>.png at 256 px with a real alpha channel — the brightest channel
is the alpha, and the colour is divided back out of it — so one file works
both added (black adds nothing) and blended (smoke wants edges that fade).

    python3 tools/vfx_ship.py            # everything missing or newer
    python3 tools/vfx_ship.py --force
    python3 tools/vfx_ship.py --sheet x.png   # a contact sheet to look at
"""
import argparse, sys
from pathlib import Path

import numpy as np
from PIL import Image

REPO = Path(__file__).resolve().parents[1]
SRC = REPO / "Art" / "VFX"
DST = REPO / "Pantheon" / "Resources" / "Portraits"
SIZE = 256


def ship(src, dst):
    im = Image.open(src).convert("RGB")
    # Trim the black margin so the element fills the sprite, keeping it square
    # about its own centre of light.
    a = np.asarray(im).astype(np.float32) / 255
    lum = a.max(axis=2)
    ys, xs = np.where(lum > 0.08)
    if len(xs):
        cx, cy = (xs.min() + xs.max()) / 2, (ys.min() + ys.max()) / 2
        half = max(xs.max() - xs.min(), ys.max() - ys.min()) / 2 * 1.08 + 8
        box = (int(max(0, cx - half)), int(max(0, cy - half)), int(min(im.width, cx + half)), int(min(im.height, cy + half)))
        im = im.crop(box)
    im = im.resize((SIZE, SIZE), Image.LANCZOS)
    a = np.asarray(im).astype(np.float32) / 255
    alpha = a.max(axis=2)
    # A soft floor: the faint glow the painter left in the black would be a
    # grey square when blended, so anything under 6% is nothing.
    alpha = np.clip((alpha - 0.06) / 0.94, 0, 1)
    colour = np.where(alpha[..., None] > 0, np.clip(a / np.maximum(alpha[..., None], 1e-3), 0, 1), 0)
    out = np.dstack([colour, alpha])
    Image.fromarray((out * 255).round().astype(np.uint8), "RGBA").save(dst, optimize=True)
    return alpha.mean()


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--force", action="store_true")
    ap.add_argument("--sheet", help="write a contact sheet of the shipped sprites over grey")
    a = ap.parse_args()
    DST.mkdir(parents=True, exist_ok=True)
    shipped = []
    for src in sorted(SRC.glob("vfx_*.png")):
        dst = DST / src.name
        if not a.force and dst.exists() and dst.stat().st_mtime >= src.stat().st_mtime:
            shipped.append(dst)
            continue
        coverage = ship(src, dst)
        print(f"  {src.name} -> {dst.relative_to(REPO)}  {dst.stat().st_size // 1024} KB  coverage {coverage:.2f}")
        shipped.append(dst)
    if a.sheet and shipped:
        cols = min(6, len(shipped))
        rows = (len(shipped) + cols - 1) // cols
        sheet = Image.new("RGB", (cols * SIZE, rows * SIZE), (90, 90, 100))
        for i, p in enumerate(shipped):
            sprite = Image.open(p).convert("RGBA")
            sheet.paste(sprite, ((i % cols) * SIZE, (i // cols) * SIZE), sprite)
        sheet.save(a.sheet)
        print(f"  sheet -> {a.sheet}")


if __name__ == "__main__":
    sys.exit(main())
