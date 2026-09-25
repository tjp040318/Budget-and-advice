#!/usr/bin/env python3
"""The painted skill effects (2026-09-25; Docs/PLAN.md *Skills that look like
themselves*): every sheet in tools/skills/fx_sheets.tsv painted by Meshy's
painter (`meshy.py picture`, nano-banana-2 at 6 credits, chosen on a fire
burst painted on it and on nano-banana-pro side by side) under ONE style line,
so the sixty-odd effects read as one hand, then shipped.

  python3 tools/skill_fx.py paint                    # every missing one, 4 at a time
  python3 tools/skill_fx.py paint ember_burst tidal  # just these
  python3 tools/skill_fx.py contact x.jpg            # the painted ones, to judge
  python3 tools/skill_fx.py ship                     # sheets through vfx_sheets.py, singles as sprites

A sheet is `Art/VFX/sheet_<name>.png` (so tools/vfx_sheets.py ships it as
Pantheon/Resources/Portraits/vfx_<name>_sheet.png, its cells faded at their
rims); a single is `Art/VFX/<name>.png`, shipped as vfx_<name>.png with its
alpha from the brightest channel (the circles at 512 px, the arrow at 256).
A re-run never pays twice: meshy.py keeps the task beside the file.
"""
import argparse
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

REPO = Path(__file__).resolve().parents[1]
TABLE = REPO / "tools" / "skills" / "fx_sheets.tsv"
ART = REPO / "Art" / "VFX"
PORTRAITS = REPO / "Pantheon" / "Resources" / "Portraits"

SHEET_PREFIX = (
    "Premium fantasy mobile RPG skill VFX, hand-painted with luminous volumetric light, bright white-hot cores "
    "fading into rich saturated colour, fine sparks and particles, soft glow, NO outlines, NO cartoon line art. "
    "IMPORTANT: the whole image is one continuous solid pure black background; every cell sits on the same pure "
    "black, no grey, white or coloured cell backgrounds. A sprite sheet: 16 sequential animation frames of ONE "
    "effect in a 4 by 4 grid, read left to right then top to bottom, every cell exactly the same size, the effect "
    "centred in each cell with black margin all round so nothing touches a cell edge, no borders, no gaps, no "
    "numbers, no text. The effect: "
)
SINGLE_PREFIX = (
    "Premium fantasy mobile RPG VFX texture, hand-painted with luminous glowing light, NO outlines, NO cartoon "
    "line art, on one continuous solid pure black background, no text, no border, nothing touching the image's "
    "edge. The image: "
)


def rows():
    out = []
    for line in TABLE.read_text().splitlines():
        if not line.strip() or line.startswith("#"):
            continue
        name, kind, text = line.split("\t", 2)
        out.append((name.strip(), kind.strip(), text.strip()))
    return out


def source(name, kind):
    return ART / (f"sheet_{name}.png" if kind == "sheet" else f"{name}.png")


def paint_one(row, model, price):
    name, kind, text = row
    out = source(name, kind)
    if out.exists():
        return f"{name}: painted already"
    prompt = (SHEET_PREFIX if kind == "sheet" else SINGLE_PREFIX) + text
    r = subprocess.run([sys.executable, str(REPO / "tools" / "meshy.py"), "picture", out.stem, "--prompt", prompt,
                        "--model", model, "--price", str(price), "--floor", "100", "--out", str(out)],
                       capture_output=True, text=True)
    tail = (r.stdout.strip().splitlines() or [""])[-1]
    return f"{name}: {tail}" if r.returncode == 0 else f"{name}: FAILED {r.stderr.strip()[-300:] or tail}"


def cmd_paint(a):
    table = rows()
    want = [r for r in table if not a.names or r[0] in a.names]
    todo = [r for r in want if not source(r[0], r[1]).exists()]
    print(f"{len(todo)} to paint of {len(want)} on {a.model}")
    with ThreadPoolExecutor(max_workers=a.jobs) as pool:
        for line in pool.map(lambda r: paint_one(r, a.model, a.price), todo):
            print(" ", line, flush=True)


def cmd_contact(a):
    table = [r for r in rows() if source(r[0], r[1]).exists() and (not a.names or r[0] in a.names)]
    cell = 360
    cols = 6
    sheet = Image.new("RGB", (cols * cell, ((len(table) + cols - 1) // cols) * (cell + 22)), (14, 14, 18))
    d = ImageDraw.Draw(sheet)
    for i, (name, kind, _) in enumerate(table):
        im = Image.open(source(name, kind)).convert("RGB").resize((cell, cell))
        x, y = (i % cols) * cell, (i // cols) * (cell + 22)
        sheet.paste(im, (x, y + 22))
        d.text((x + 4, y + 4), f"{name} ({kind})", fill=(230, 230, 230))
    sheet.save(a.out, quality=86)
    print(f"contact -> {a.out} ({len(table)} effects)")


def ship_single(src, dst, px):
    im = Image.open(src).convert("RGB").resize((px, px), Image.LANCZOS)
    rgb = np.asarray(im).astype(np.float32) / 255.0
    alpha = rgb.max(axis=2)
    colour = np.clip(rgb / np.maximum(alpha, 1e-3)[..., None], 0, 1)
    # a soft circular fade at the rim, so no painted corner reaches the edge
    yy, xx = np.mgrid[0:px, 0:px]
    r = np.hypot(xx - (px - 1) / 2, yy - (px - 1) / 2) / (px / 2)
    alpha = alpha * np.clip((1.0 - r) / 0.08, 0, 1)
    out = np.dstack([colour, alpha])
    Image.fromarray(np.clip(out * 255 + 0.5, 0, 255).astype(np.uint8), "RGBA").save(dst, optimize=True)


def cmd_ship(a):
    table = [r for r in rows() if source(r[0], r[1]).exists() and (not a.names or r[0] in a.names)]
    sheets = [n for n, k, _ in table if k == "sheet"]
    if sheets:
        r = subprocess.run([sys.executable, str(REPO / "tools" / "vfx_sheets.py"), "--only", ",".join(sheets)]
                           + (["--force"] if a.force else []), capture_output=True, text=True)
        print(r.stdout.strip() or r.stderr.strip())
    for name, kind, _ in table:
        if kind != "single":
            continue
        dst = PORTRAITS / f"vfx_{name}.png"
        if dst.exists() and not a.force and dst.stat().st_mtime >= source(name, kind).stat().st_mtime:
            continue
        ship_single(source(name, kind), dst, 512 if name.endswith("_circle") else 256)
        print(f"  {name} -> {dst.relative_to(REPO)}")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    p = sub.add_parser("paint"); p.add_argument("names", nargs="*"); p.add_argument("--model", default="nano-banana-2")
    p.add_argument("--price", type=int, default=6); p.add_argument("--jobs", type=int, default=4)
    p = sub.add_parser("contact"); p.add_argument("out"); p.add_argument("names", nargs="*")
    p = sub.add_parser("ship"); p.add_argument("names", nargs="*"); p.add_argument("--force", action="store_true")
    a = ap.parse_args()
    {"paint": cmd_paint, "contact": cmd_contact, "ship": cmd_ship}[a.cmd](a)


if __name__ == "__main__":
    main()
