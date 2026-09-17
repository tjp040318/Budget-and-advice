#!/usr/bin/env python3
"""Thumbnails for the island's decoration catalogue.

Renders each prop with tools/preview.py (its own texture, the front view),
keys the renderer's flat ground to alpha, trims to the piece and ships
Pantheon/Resources/Portraits/decor_<id>.png at 240 px. Re-run after a prop
is reshipped. The ids and assets mirror IslandDatabase.decorations.

    python3 tools/decor_thumbs.py            # every piece
    python3 tools/decor_thumbs.py sphinx     # one
"""
import subprocess, sys, tempfile, pathlib
from PIL import Image

ROOT = pathlib.Path(__file__).resolve().parent.parent
PIECES = {
    "brazier": "prop_brazier", "tripod_brazier": "prop_tripod_brazier",
    "broken_column": "prop_broken_column", "doric_column": "prop_doric_column",
    "lotus_column": "prop_lotus_column", "sphinx": "prop_sphinx",
    "temple_ruin": "prop_temple_ruin", "world_tree_root": "prop_world_tree_root",
    "obelisk": "prop_obelisk", "zeus_statue": "prop_zeus_statue",
    "anubis_colossus": "prop_anubis_colossus",
}
SIZE = 240

def key_out(img, tolerance=18):
    """The renderer's ground is one flat colour: read it off a corner and
    flood every pixel near it, from the border, to transparent."""
    img = img.convert("RGBA")
    w, h = img.size
    px = img.load()
    bg = px[2, 2][:3]
    seen = bytearray(w * h)
    stack = [(x, y) for x in range(w) for y in (0, h - 1)] + [(x, y) for y in range(h) for x in (0, w - 1)]
    while stack:
        x, y = stack.pop()
        i = y * w + x
        if seen[i]:
            continue
        seen[i] = 1
        r, g, b, a = px[x, y]
        if abs(r - bg[0]) + abs(g - bg[1]) + abs(b - bg[2]) > tolerance:
            continue
        px[x, y] = (r, g, b, 0)
        if x > 0: stack.append((x - 1, y))
        if x < w - 1: stack.append((x + 1, y))
        if y > 0: stack.append((x, y - 1))
        if y < h - 1: stack.append((x, y + 1))
    return img

def main():
    wanted = sys.argv[1:] or list(PIECES)
    out_dir = ROOT / "Pantheon/Resources/Portraits"
    for piece in wanted:
        asset = PIECES[piece]
        with tempfile.TemporaryDirectory() as tmp:
            raw = pathlib.Path(tmp) / f"{asset}.png"
            subprocess.run([sys.executable, str(ROOT / "tools/preview.py"), str(ROOT / "Pantheon/Resources/Models" / f"{asset}.usdz"),
                            "--size", "420", "--no-layout", "--out", str(raw)], check=True, capture_output=True)
            img = Image.open(raw)
            w, h = img.size
            # Three views side by side over a caption strip: the front is the
            # left third, the strip is the bottom 24 px.
            front = img.crop((0, 0, w // 3, h - 24))
            keyed = key_out(front)
            box = keyed.getbbox()
            if box:
                keyed = keyed.crop(box)
            # Fit into a square with a margin, feet on the bottom edge.
            scale = min((SIZE - 16) / keyed.width, (SIZE - 16) / keyed.height)
            keyed = keyed.resize((max(1, int(keyed.width * scale)), max(1, int(keyed.height * scale))), Image.LANCZOS)
            sheet = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
            sheet.paste(keyed, ((SIZE - keyed.width) // 2, SIZE - 8 - keyed.height), keyed)
            out = out_dir / f"decor_{piece}.png"
            sheet.save(out, optimize=True)
            print(f"{piece:<18} {keyed.size[0]}x{keyed.size[1]} -> {out.relative_to(ROOT)}")

if __name__ == "__main__":
    main()
