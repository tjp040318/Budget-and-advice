#!/usr/bin/env python3
"""Paints and ships the twenty-seven skill icons.

    python3 tools/skill_icons.py --paint          # three 3x3 sheets, 6 credits each
    python3 tools/skill_icons.py --ship           # key them off the black and ship
    python3 tools/skill_icons.py --sheet x.jpg    # what shipped, to look at
    python3 tools/skill_icons.py --paint --only 3 # one sheet again (a re-roll)

`SkillArt` in Components.swift maps every skill in the game to one of these
twenty-seven keys by what the skill DOES — a painted icon per skill would be
thousands of images for seventy-nine families at five elements each, and the
genre pays an artist for exactly that; this pays for twenty-seven and lets
the caster's element be the light behind the art.

The sheets are painted by `meshy.py picture` (Meshy credits, ~6 a sheet,
while Gemini is paused) as a 3 x 3 grid on pure black, which is the shape
the effect flipbooks proved. Shipping keys each cell off the BACKGROUND
rather than off brightness — a flood fill from the cell's border, so a dark
line inside an icon survives where `vfx_sheets.py`'s brightest-channel alpha
would have eaten it — trims to the paint, squares it and writes
`Pantheon/Resources/Portraits/skill_<key>.png` at 256 px.
"""
import argparse
import subprocess
import sys
from pathlib import Path

import numpy as np
from PIL import Image

REPO = Path(__file__).resolve().parents[1]
SRC = REPO / "Art" / "SkillIcons"
DST = REPO / "Pantheon" / "Resources" / "Portraits"
SIZE = 256
FLOOR = 1500

# key -> what a painter is told to paint. Described, never named: the rule
# that keeps a god from coming back as a photograph of an actor.
ICONS = {
    # Sheet 1, the blow.
    "strike": "a single curved sword sweeping through its own arc of white light, steel blade, gold hilt",
    "cleave": "a broad double-headed axe mid-swing carving one wide crescent of light, splinters flying",
    "pierce": "a bronze spear point punching through a cracked round shield, the crack spreading from the hole",
    "volley": "three long arrows in flight side by side, fletching trailing thin streaks of light",
    "multi": "three parallel claw gashes torn through the air, the torn edges glowing hot",
    "slam": "a heavy stone war hammer striking flagstones, chips and dust bursting upward",
    "nova": "a thin sharp ring of white force bursting outward from a single bright point",
    "beam": "a column of golden light falling from above onto a small circle of scorched ground",
    "crit": "a white starburst impact with a cracked centre and four long spikes of light",
    # Sheet 2, the elements and the curses.
    "burn": "a coiling orange flame with a white-hot core and embers rising from it",
    "freeze": "a cluster of pale blue ice shards thrust upward with frost feathering from their base",
    "gale": "three pale green crescent blades of wind curling around one another",
    "surge": "a curling crest of deep blue water with white spray along its lip",
    "bolt": "a jagged forked lightning bolt, white at its core with a violet edge",
    "shadow": "a curl of black smoke wrapping around one hollow violet eye",
    "brand": "a glowing sigil burned into dark stone, its lines molten gold",
    "bomb": "a round iron sphere bound in chains with a short lit fuse sparking",
    "drain": "a crescent of red light drawing thin threads of blood upward into itself",
    # Sheet 3, the shapers.
    "heal": "a golden chalice overflowing with soft green light",
    "revive": "a single burning feather falling onto an open upturned palm",
    "shield": "a round bronze shield seen face on with a glowing rim",
    "cleanse": "a small bronze bell ringing, clean white light washing down from it",
    "strip": "a hand tearing a glowing veil away, the veil ripping into light",
    "buff": "a laurel wreath rising on a pair of small white wings",
    "debuff": "a cracked laurel wreath sinking with its leaves falling and a dark downward arrow",
    "stun": "a cracked white star with three small rings spiralling around it",
    "tempo": "an hourglass wrapped in a curl of wind, its sand streaming sideways",
}
KEYS = list(ICONS)
GRID = 3
PER_SHEET = GRID * GRID
SHEETS = [KEYS[i:i + PER_SHEET] for i in range(0, len(KEYS), PER_SHEET)]

# The first take of sheet 3 came back with a gold frame drawn around every
# icon and a dark brown ground inside it, which both breaks the keying and
# stops it matching the other two: the object itself has to float on the
# black. The refusals below are what fixed it on the re-roll.
STYLE = (
    "A 3 by 3 grid of nine separate square video-game skill icons, "
    "painted in a rich ancient-Greek and Egyptian mythology style with bold "
    "readable silhouettes, warm rim light and painted highlights. "
    "The entire image background is solid pure black, edge to edge, and "
    "every icon floats directly on that same black with black space around "
    "it. Each icon is a single object painted against black and touches "
    "nothing else. No frames, no borders, no square panels, no tiles, no "
    "plaques, no cards, no gold edging around the icons, no grid lines, no "
    "ground or floor under the objects, no background scenery, no drop "
    "shadows. No text, no letters, no numbers, no runes, no captions, no "
    "signature. "
)
ROWS = ("Top row, left to right: ", "Middle row, left to right: ", "Bottom row, left to right: ")


def prompt_for(keys):
    parts = [STYLE]
    for row in range(GRID):
        cells = keys[row * GRID:(row + 1) * GRID]
        parts.append(ROWS[row] + "; ".join(ICONS[k] for k in cells) + ". ")
    return "".join(parts)


def paint(only, floor, model):
    SRC.mkdir(parents=True, exist_ok=True)
    for index, keys in enumerate(SHEETS, start=1):
        if only and index != only:
            continue
        out = SRC / f"sheet_{index}.png"
        cmd = [sys.executable, str(REPO / "tools" / "meshy.py"), "picture", f"skill_sheet_{index}",
               "--prompt", prompt_for(keys), "--out", str(out), "--floor", str(floor), "--model", model]
        print(f"sheet {index}: {', '.join(keys)}")
        subprocess.run(cmd, check=True)


def background_mask(cell):
    """True where the cell is its black ground: the dark pixels CONNECTED to
    the cell's border. A dark line inside the painted icon is not background
    and keeps its alpha, which is the difference between this and an alpha
    taken from brightness."""
    from scipy import ndimage
    grey = np.asarray(cell.convert("L")).astype(np.float32) / 255
    dark = grey < 0.13
    labels, count = ndimage.label(dark)
    if count == 0:
        return np.zeros_like(dark)
    edge = set(labels[0, :]) | set(labels[-1, :]) | set(labels[:, 0]) | set(labels[:, -1])
    edge.discard(0)
    return np.isin(labels, list(edge))


def ship(only):
    from scipy import ndimage
    DST.mkdir(parents=True, exist_ok=True)
    written = []
    for index, keys in enumerate(SHEETS, start=1):
        if only and index != only:
            continue
        path = SRC / f"sheet_{index}.png"
        if not path.exists():
            print(f"  sheet {index}: not painted yet ({path.relative_to(REPO)})")
            continue
        sheet = Image.open(path).convert("RGB")
        side = min(sheet.size)
        sheet = sheet.resize((side, side), Image.LANCZOS)
        step = side // GRID
        for position, key in enumerate(keys):
            row, column = divmod(position, GRID)
            cell = sheet.crop((column * step, row * step, (column + 1) * step, (row + 1) * step))
            back = background_mask(cell)
            alpha = (~back).astype(np.float32)
            # Soften the cut by a pixel or two so nothing ends on a stair.
            alpha = ndimage.gaussian_filter(alpha, 1.2)
            rgb = np.asarray(cell).astype(np.float32) / 255
            keep = np.argwhere(alpha > 0.35)
            if keep.size == 0:
                print(f"  {key}: the cell is empty — re-roll sheet {index}")
                continue
            top, left = keep.min(axis=0)
            bottom, right = keep.max(axis=0) + 1
            # Square the crop around the paint so every icon draws the same size.
            height, width = bottom - top, right - left
            span = int(max(height, width) * 1.1)
            centre_y, centre_x = (top + bottom) // 2, (left + right) // 2
            y0, x0 = centre_y - span // 2, centre_x - span // 2
            out = np.zeros((span, span, 4), dtype=np.float32)
            ys = slice(max(0, y0), min(cell.height, y0 + span))
            xs = slice(max(0, x0), min(cell.width, x0 + span))
            oy, ox = ys.start - y0, xs.start - x0
            out[oy:oy + (ys.stop - ys.start), ox:ox + (xs.stop - xs.start), :3] = rgb[ys, xs]
            out[oy:oy + (ys.stop - ys.start), ox:ox + (xs.stop - xs.start), 3] = alpha[ys, xs]
            image = Image.fromarray(np.clip(out * 255 + 0.5, 0, 255).astype(np.uint8), "RGBA")
            image = image.resize((SIZE, SIZE), Image.LANCZOS)
            target = DST / f"skill_{key}.png"
            image.save(target, optimize=True)
            written.append(target)
            print(f"  {key:8s} -> {target.relative_to(REPO)}  {target.stat().st_size // 1024} KB")
    return written


def contact(out_path):
    files = [DST / f"skill_{key}.png" for key in KEYS]
    files = [f for f in files if f.exists()]
    if not files:
        sys.exit("nothing shipped yet")
    cell = 150
    columns = 9
    rows = (len(files) + columns - 1) // columns
    sheet = Image.new("RGB", (columns * cell, rows * cell), (26, 20, 14))
    for i, f in enumerate(files):
        icon = Image.open(f).convert("RGBA").resize((cell - 8, cell - 8))
        ground = Image.new("RGBA", icon.size, (40, 32, 22, 255))
        ground.alpha_composite(icon)
        sheet.paste(ground.convert("RGB"), ((i % columns) * cell + 4, (i // columns) * cell + 4))
    sheet.save(out_path, quality=90)
    print(f"contact {out_path} ({len(files)} icons)")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--paint", action="store_true", help="paint the sheets (spends Meshy credits)")
    ap.add_argument("--ship", action="store_true", help="key the painted sheets and ship the icons")
    ap.add_argument("--only", type=int, help="one sheet (1, 2 or 3)")
    ap.add_argument("--sheet", help="write a contact sheet of what shipped here")
    ap.add_argument("--floor", type=int, default=FLOOR)
    ap.add_argument("--model", default="nano-banana-2")
    a = ap.parse_args()
    if not (a.paint or a.ship or a.sheet):
        for index, keys in enumerate(SHEETS, start=1):
            print(f"sheet {index}: {', '.join(keys)}")
        print(f"\n{len(KEYS)} icons over {len(SHEETS)} sheets; --paint spends about {6 * len(SHEETS)} credits")
        return
    if a.paint:
        paint(a.only, a.floor, a.model)
    if a.ship:
        ship(a.only)
    if a.sheet:
        contact(a.sheet)


if __name__ == "__main__":
    main()
