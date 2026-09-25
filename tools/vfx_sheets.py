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
    python3 tools/vfx_sheets.py --refade fireburst:4x8   # fade a shipped sheet's cells in place

`--refade` is for a sheet that never came through here: the Veo fireburst of
2026-09-10 (4 rows of 8, 128 px cells) was cut by `tools/veo.py sheet` with
no fade, its later frames reached their cell borders at 22-32 of 255, and
every ember hit drew a hard-edged square of fire (run 224, 29-d). It runs the
same fade over the file's own alpha, once — a second run would fade the
already faded ring again.

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
    rgb = remove_cell_grounds(rgb, GRID, GRID)
    alpha = rgb.max(axis=2)
    # Un-premultiply so the colour of a faint pixel is its hue at full
    # strength and the alpha carries the faintness.
    colour = rgb / np.maximum(alpha, 1e-3)[..., None]
    colour = np.clip(colour, 0, 1)
    alpha = alpha * cell_fade(SIZE // GRID, SIZE // GRID, GRID, GRID)
    out = np.dstack([colour, alpha])
    Image.fromarray(np.clip(out * 255 + 0.5, 0, 255).astype(np.uint8), "RGBA").save(dst, optimize=True)


def remove_cell_grounds(rgb: np.ndarray, rows: int, cols: int) -> np.ndarray:
    """Takes each cell's own ground off it: the painter sometimes lays a few
    frames on a dark tinted square instead of the sheet's black (the wind
    burst and pillar of 2026-09-25 put dark green behind three frames each),
    and with the alpha read off the brightest channel that square would draw
    as a faint block of colour over the field. The ground is the median of
    the cell's outer ring (the effect never reaches its rim - the prompt
    keeps a black margin - so the ring is ground), subtracted and the rest
    rescaled so the brightest light keeps its value."""
    out = rgb.copy()
    h, w = rgb.shape[:2]
    ch, cw = h // rows, w // cols
    ring = max(2, min(ch, cw) // 24)
    for r in range(rows):
        for c in range(cols):
            cell = out[r * ch:(r + 1) * ch, c * cw:(c + 1) * cw]
            border = np.concatenate([cell[:ring].reshape(-1, 3), cell[-ring:].reshape(-1, 3),
                                     cell[:, :ring].reshape(-1, 3), cell[:, -ring:].reshape(-1, 3)])
            ground = np.median(border, axis=0)
            if ground.max() < 0.02:
                continue
            lifted = np.clip((cell - ground) / np.maximum(1e-3, 1 - ground), 0, 1)
            out[r * ch:(r + 1) * ch, c * cw:(c + 1) * cw] = lifted
    return out


def cell_fade(cell_w: int, cell_h: int, rows: int, cols: int) -> np.ndarray:
    """A soft circular fade over every cell's outer ring, so no frame ends at
    a straight edge whatever the painter did in the corners: full inside 72%
    of the way out, gone at the edge midpoints, tiled over the sheet."""
    yy, xx = np.mgrid[0:cell_h, 0:cell_w]
    radius = np.hypot((xx + 0.5) / cell_w - 0.5, (yy + 0.5) / cell_h - 0.5) * 2  # 0 at the centre, 1 at the edge midpoints
    fade = np.clip((1.0 - radius) / 0.28, 0, 1)
    fade = fade * fade * (3 - 2 * fade)
    return np.tile(fade, (rows, cols))


def refade(name: str, rows: int, cols: int) -> None:
    """Fade the cells of an already shipped sheet in place (see `--refade`)."""
    path = DST / f"vfx_{name}_sheet.png"
    im = np.asarray(Image.open(path).convert("RGBA")).astype(np.float32) / 255.0
    height, width = im.shape[:2]
    mask = cell_fade(width // cols, height // rows, rows, cols)
    im[..., 3] = im[..., 3] * mask
    Image.fromarray(np.clip(im * 255 + 0.5, 0, 255).astype(np.uint8), "RGBA").save(path, optimize=True)
    print(f"faded {path.name}: {rows} x {cols} cells of {width // cols} x {height // rows}")


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--force", action="store_true")
    ap.add_argument("--only", help="comma list of names (claw, sunburst, ...)")
    ap.add_argument("--contact", help="write a contact sheet of the shipped files here")
    ap.add_argument("--refade", help="NAME:ROWSxCOLS - fade a shipped sheet's cells in place, once")
    a = ap.parse_args()
    if a.refade:
        name, grid = a.refade.split(":")
        rows, cols = (int(n) for n in grid.lower().split("x"))
        refade(name, rows, cols)
        return
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
