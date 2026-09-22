#!/usr/bin/env python3
"""Paints and ships the painted doors: the five tab-bar icons and the island
header's four (PLAN.md, *Phase B of the premium pass*, "The painted doors").

    python3 tools/tab_icons.py                    # the nine cells and the prompt
    python3 tools/tab_icons.py --paint            # one 3x3 sheet, 9 Meshy credits
    python3 tools/tab_icons.py --paint --single arena   # one cell again, 9 credits
    python3 tools/tab_icons.py --split            # key and ship tab_<key>.png
    python3 tools/tab_icons.py --preview x.jpg    # the shipped set on cream and on a dark socket

The sheet is painted by `meshy.py picture` on nano-banana-pro, the model that
painted the item icons, and the style clause is `item_icons.STYLE` itself,
imported, so the doors and the wallet's icons are one hand. Every cell is an
OBJECT on pure black with no disc or frame behind it: the socket and the
selected glow are drawn in code (`MedallionIcon`), so a painted frame would
be a frame inside a frame. Cells are keyed by `item_icons.ship_cell` (a flood
fill from the cell's border, so a dark line inside an object survives) and
shipped at 256 px with alpha. A re-rolled cell, `single_<key>.png`, wins over
the sheet's cell on --split. Described, never named: the rule that keeps a
god from coming back as a photograph.
"""
import argparse
import subprocess
import sys
from pathlib import Path

from PIL import Image, ImageDraw

sys.path.insert(0, str(Path(__file__).resolve().parent))
from item_icons import STYLE, ship_cell  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
ART = ROOT / "Art" / "TabIcons"
OUT = ROOT / "Pantheon" / "Resources" / "Portraits"
MODEL = "nano-banana-pro"
PRICE = 9
FLOOR = 500
PX = 256
GRID = 3

# key -> the object, in the sheet's order (left to right, top to bottom).
ICONS = [
    ("island", "a tiny round island of golden sand ringed by turquoise shallows, one leaning palm tree and a small white marble temple with four columns and a triangular roof standing on it"),
    ("campaign", "a folded parchment map lying open at an angle, green hills and a blue coast painted on it and a winding red dotted road across it ending at a small red pennant on a bronze pin, no writing on the map"),
    ("arena", "a round bronze shield seen face on with a raised gold lion's head at its centre, two short steel swords with gold hilts crossed behind it so their points and hilts show at the four corners"),
    ("summon", "an ornate scroll with gold end caps and a violet ribbon, half unrolled and floating upright, a curl of golden light and a few small violet stars rising close around its open page"),
    ("collection", "a white marble bust of a stern bearded man with curled hair wearing a gold laurel wreath, on a small round marble plinth with a gold band"),
    ("missions", "a tall white feather quill standing in a round bronze inkwell, beside it a small stack of three wax writing tablets in wooden frames tied with red cord"),
    ("allies", "only two forearms and hands, no bodies, in bronze arm guards, clasping each other at the wrists in a warrior's handshake, red cloth at the cuffs, a small green laurel sprig behind the clasp"),
    ("events", "a golden horn of plenty lying on its side, spilling gold coins, purple grapes and a split red pomegranate from its mouth"),
    ("decor", "a block of white marble with a scrolled column capital half carved out of its top, a bronze chisel standing in the stone and a wooden mallet leaning against it"),
]

RULES = (
    "every icon compact and about as wide as it is tall, its darkest shadows a deep warm brown and never black, "
    "any light kept tight to the object with no wide glow or haze; no round medallion, disc, coin, badge, plaque, "
    "tile or frame behind any icon, no ground or floor under them; no borders, no frames, no cell lines, no text, "
    "no numbers, no letters, no labels, no runes, no signature"
)


def prompt():
    numbered = "; ".join(f"{i + 1}) {words}" for i, (_, words) in enumerate(ICONS))
    return (
        f"A grid of {len(ICONS)} game menu icons for a mobile fantasy RPG, {GRID} columns by {GRID} rows, "
        f"every icon centred in its own equal cell with wide margins of empty black around it, on a PLAIN PURE "
        f"BLACK background with nothing else, {STYLE}; {RULES}. Reading left to right, then top to bottom: {numbered}"
    )


def single_prompt(key):
    words = dict(ICONS)[key]
    return (
        f"One game menu icon for a mobile fantasy RPG, centred with wide margins of empty black around it, on a "
        f"PLAIN PURE BLACK background with nothing else, {STYLE}; {RULES}. The icon: {words}"
    )


def paint(single, floor, force):
    ART.mkdir(parents=True, exist_ok=True)
    if single:
        out, name, text = ART / f"single_{single}.png", f"tab_single_{single}", single_prompt(single)
    else:
        out, name, text = ART / "sheet_tabs.png", "tab_sheet", prompt()
    if out.exists() and not force:
        print(f"have {out.relative_to(ROOT)} (--force to paint again)")
        return
    subprocess.run([sys.executable, str(ROOT / "tools" / "meshy.py"), "picture", name, "--prompt", text,
                    "--out", str(out), "--model", MODEL, "--price", str(PRICE), "--floor", str(floor)], check=True)


def split():
    sheet_path = ART / "sheet_tabs.png"
    sheet = Image.open(sheet_path).convert("RGB") if sheet_path.exists() else None
    OUT.mkdir(parents=True, exist_ok=True)
    for i, (key, _) in enumerate(ICONS):
        single = ART / f"single_{key}.png"
        if single.exists():
            cell = Image.open(single).convert("RGB")
        elif sheet is not None:
            w, h = sheet.size
            cw, ch = w / GRID, h / GRID
            r, c = divmod(i, GRID)
            cell = sheet.crop((int(c * cw), int(r * ch), int((c + 1) * cw), int((r + 1) * ch)))
        else:
            print(f"  {key}: nothing painted yet")
            continue
        ship_cell(cell, OUT / f"tab_{key}.png", px=PX)


def preview(out):
    shipped = [(k, OUT / f"tab_{k}.png") for k, _ in ICONS if (OUT / f"tab_{k}.png").exists()]
    if not shipped:
        sys.exit("nothing shipped yet")
    cell = 150
    board = Image.new("RGB", (len(shipped) * cell, 2 * cell + 22), (235, 226, 207))
    d = ImageDraw.Draw(board)
    for i, (k, p) in enumerate(shipped):
        icon = Image.open(p).convert("RGBA").resize((cell - 40, cell - 40), Image.LANCZOS)
        # Top row on the cream band, bottom row in the dark socket the game draws.
        board.paste(icon, (i * cell + 20, 12), icon)
        d.ellipse((i * cell + 8, cell + 8, i * cell + cell - 8, 2 * cell - 8), fill=(40, 31, 22), outline=(176, 138, 46), width=3)
        small = icon.resize((cell - 44, cell - 44), Image.LANCZOS)
        board.paste(small, (i * cell + 22, cell + 22), small)
        d.text((i * cell + 8, 2 * cell + 4), k, fill=(31, 25, 18))
    board.save(out, quality=90)
    print(f"wrote {out}: {len(shipped)} icons")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--paint", action="store_true", help="paint the sheet (or --single KEY); spends Meshy credits")
    ap.add_argument("--single", choices=[k for k, _ in ICONS])
    ap.add_argument("--force", action="store_true")
    ap.add_argument("--split", action="store_true")
    ap.add_argument("--preview")
    ap.add_argument("--floor", type=int, default=FLOOR)
    a = ap.parse_args()
    if not (a.paint or a.split or a.preview):
        for i, (k, words) in enumerate(ICONS, start=1):
            print(f"{i}. {k}: {words}")
        print(f"\n{prompt()}\n\n--paint spends {PRICE} credits on {MODEL}")
        return
    if a.paint:
        paint(a.single, a.floor, a.force)
    if a.split:
        split()
    if a.preview:
        preview(a.preview)


if __name__ == "__main__":
    main()
