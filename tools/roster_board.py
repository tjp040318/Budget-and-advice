#!/usr/bin/env python3
"""
One board of the shipped models of several families, for the owner's eyes:
the base model's three views (front, back, side, with its own texture) cut
from each family's preview sheet, tiled three to a row and named.

    python3 tools/roster_board.py mars minerva pluto --out /tmp/board.jpg
    python3 tools/roster_board.py --list tools/batch/wave4.txt --out /tmp/board.jpg

A family whose sheet is not in $S (default /tmp/pantheon-batch) is rendered
first with tools/preview.py --sheet. The owner's rule (2026-09-11): every
piece of finished work is sent to him as a picture before he tests it, and a
model is a picture of its three views, not a line in a commit message.
"""
import argparse, os, subprocess, sys
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

REPO = Path(__file__).resolve().parent.parent
S = Path(os.environ.get("S", "/tmp/pantheon-batch"))
GUTTER = 8  # preview.py's sheet gutter


def base_cell(family, render):
    sheet = S / f"sheet_{family}.jpg"
    if not sheet.exists() and render:
        S.mkdir(parents=True, exist_ok=True)
        subprocess.run([sys.executable, str(REPO / "tools/preview.py"), "--sheet", family, "--out", str(sheet)],
                       check=False, capture_output=True)
    if not sheet.exists():
        return None
    im = Image.open(sheet)
    if im.height < 700:                       # an unrigged beast: one row, three views then the atlas
        return im.crop((0, 0, int(im.width * 0.65), im.height))
    cell_w = (im.width - GUTTER) // 2           # two cells to a row, the base model first
    return im.crop((0, 0, cell_w, min(530, im.height)))


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("families", nargs="*", help="family names as shipped (mars, sun_wukong, ...)")
    ap.add_argument("--list", help="a wave list: the sixth field (family) of every spec line, or the first")
    ap.add_argument("--out", default=str(S / "roster_board.jpg"))
    ap.add_argument("--per-row", type=int, default=3)
    ap.add_argument("--width", type=int, default=640, help="width of one family's cell on the board")
    ap.add_argument("--no-render", action="store_true", help="skip families with no sheet instead of rendering")
    a = ap.parse_args()
    fams = list(a.families)
    if a.list:
        for line in Path(a.list).read_text().splitlines():
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            f = line.split(":")
            fams.append(f[5] if len(f) > 5 else f[0])
    if not fams:
        sys.exit("no families given")
    cells = []
    for fam in fams:
        c = base_cell(fam, render=not a.no_render)
        if c is None:
            print(f"no sheet for {fam}", file=sys.stderr); continue
        c = c.resize((a.width, int(c.height * a.width / c.width)), Image.LANCZOS)
        cells.append((fam, c))
    if not cells:
        sys.exit("nothing to show")
    h = max(c.height for _, c in cells) + 26
    rows = (len(cells) + a.per_row - 1) // a.per_row
    board = Image.new("RGB", (a.width * a.per_row, h * rows), (235, 226, 207))
    d = ImageDraw.Draw(board)
    try:
        font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", 18)
    except OSError:
        font = ImageFont.load_default()
    for i, (fam, c) in enumerate(cells):
        x, y = (i % a.per_row) * a.width, (i // a.per_row) * h
        board.paste(c, (x, y + 26))
        d.rectangle((x, y, x + a.width - 1, y + 25), fill=(31, 25, 18))
        d.text((x + 8, y + 4), fam.replace("_", " ").title(), fill=(240, 226, 190), font=font)
    board.save(a.out, quality=88)
    print(f"{a.out}  {board.size[0]}x{board.size[1]}  {len(cells)} families")


if __name__ == "__main__":
    main()
