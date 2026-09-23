#!/usr/bin/env python3
"""The painted item icons: every thing the game pays out, as Gemini sheets.

    python3 tools/item_icons.py --list                      # the keys, per sheet
    python3 tools/item_icons.py --paint currencies          # one sheet (about 14 cents)
    python3 tools/item_icons.py --paint all
    python3 tools/item_icons.py --split currencies          # key, trim, ship item_<key>.png
    python3 tools/item_icons.py --split all
    python3 tools/item_icons.py --split scrolls --sheet scrolls_2k --px 512 --only scroll_
                                                            # the eight scrolls from the 2K sheet, glow ramped
    python3 tools/item_icons.py --preview icons.jpg         # a contact sheet of what shipped

GEMINI IS PAUSED (CLAUDE.md): `--paint` is run only on the owner's word for
this batch. Five sheets at about 14 cents each is about $0.70, plus any
re-roll.

A sheet is one image: a grid of icons, each centred in its own equal cell
on a plain black ground, painted in one hand so the set agrees with itself
— the way the sixteen relic stones were repainted as one sheet. `--split`
cuts the cells, keys each icon off the black by a flood fill from the
cell's border (a dark line inside the icon is kept), trims it to its
bounds, pads it square and writes `Pantheon/Resources/Portraits/
item_<key>.png` at 256 px with a real alpha channel. A sheet in HALO_RAMP
(the scrolls, whose glows fade into the black) also has the fade's dark
skirt ramped out (`halo_alpha`), or it ships as a dark rim round the icon. `ItemArt` (in
Components.swift) finds a painting by that name and every `ItemIcon` and
`RewardTile` in the game shows it the moment it is in the bundle; without
one an item draws as its glyph, so a sheet can ship one at a time.
"""
import argparse
import subprocess
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont
from scipy import ndimage

ROOT = Path(__file__).resolve().parent.parent
ART = ROOT / "Art" / "Items"
OUT = ROOT / "Pantheon" / "Resources" / "Portraits"

STYLE = (
    "painted in a rich stylised fantasy style with strong readable silhouettes, "
    "glossy highlights, soft rim light and fine gold detail, a Greek-temple palette "
    "of gold, cream marble, lapis blue and verdigris, each icon a single clear object "
    "seen slightly from above"
)

# key -> what the painter draws. The order is the grid's, left to right then
# top to bottom.
SHEETS = {
    "currencies": (3, 3, [
        ("drachma", "a neat stack of gleaming gold drachma coins stamped with an owl, a few coins fanned beside it"),
        ("divinity", "a cluster of glowing violet-white crystals rising from a small gold base, light pouring out of them"),
        ("energy", "a bright gold lightning bolt standing upright inside a small ring of blue light"),
        ("unit_exp", "an open ancient codex with glowing turquoise runes floating up from its pages"),
        ("player_exp", "a laurel-wreathed gold medallion with a rising sun stamped on it"),
        ("laurels", "a gold laurel wreath tied with a red ribbon"),
        ("rank_points", "a gold trophy cup with two handles on a marble plinth"),
        ("level_up", "three gold chevrons stacked upward with sparks rising from the top one"),
        ("bundle", "a small cream-and-gold gift box tied with a red ribbon, its lid slightly lifted with light inside"),
    ]),
    "scrolls": (3, 3, [
        ("scroll_mystical", "a rolled papyrus scroll tied with a blue ribbon and sealed with a blue wax seal, faint blue glow"),
        ("scroll_pantheonic", "a rolled scroll with gold-capped rods, a gold ribbon and a large gold wax seal, gold glow"),
        ("scroll_divine", "a rolled white scroll with ivory rods, a white ribbon and a small gold crown resting on it, radiant light"),
        ("scroll_unknown", "a plain rolled papyrus scroll tied with grey twine, its seal a plain grey wax blob"),
        ("scroll_light_dark", "a rolled scroll that is white on one half and black on the other, tied with a violet ribbon, a violet seal"),
        ("scroll_ember", "a rolled scroll with red-orange edges that seem to smoulder, tied with a red ribbon, a flame-shaped seal"),
        ("scroll_tide", "a rolled scroll with deep blue edges beaded with water drops, tied with a blue ribbon, a wave-shaped seal"),
        ("scroll_gale", "a rolled scroll with green edges and a few leaves caught on it, tied with a green ribbon, a leaf-shaped seal"),
        ("relic_cache", "a small gold-hinged marble box, open, holding one glowing hexagonal gemstone"),
    ]),
    "essences_a": (3, 3, [
        ("essence_magic_low", "one small teal crystal shard"),
        ("essence_magic_mid", "a cluster of three teal crystal shards"),
        ("essence_magic_high", "a large glowing teal crystal cluster on a gold base, light pouring out"),
        ("essence_radiance_low", "one small white-gold crystal shard"),
        ("essence_radiance_mid", "a cluster of three white-gold crystal shards"),
        ("essence_radiance_high", "a large glowing white-gold crystal cluster on a gold base, radiant"),
        ("essence_umbra_low", "one small dark violet crystal shard"),
        ("essence_umbra_mid", "a cluster of three dark violet crystal shards"),
        ("essence_umbra_high", "a large glowing dark violet crystal cluster on a gold base, purple light"),
    ]),
    "essences_b": (3, 3, [
        ("essence_ember_mid", "a cluster of three red-orange crystal shards with fire inside them"),
        ("essence_tide_mid", "a cluster of three deep blue crystal shards with water light inside them"),
        ("essence_gale_mid", "a cluster of three green crystal shards with wind swirls inside them"),
        ("awakening_cache_ember", "a small ornate gold reliquary box with a red-orange flame gem set in its lid"),
        ("awakening_cache_tide", "a small ornate gold reliquary box with a deep blue wave gem set in its lid"),
        ("awakening_cache_gale", "a small ornate gold reliquary box with a green leaf gem set in its lid"),
        ("awakening_cache_radiance", "a small ornate gold reliquary box with a white-gold sun gem set in its lid"),
        ("awakening_cache_umbra", "a small ornate gold reliquary box with a dark violet moon gem set in its lid"),
        ("chest_gold", "a small closed gold treasure chest with a bronze lock"),
    ]),
    "essences_c": (3, 2, [
        ("essence_ember_low", "one small red-orange crystal shard with fire inside it"),
        ("essence_tide_low", "one small deep blue crystal shard with water light inside it"),
        ("essence_gale_low", "one small green crystal shard with a wind swirl inside it"),
        ("essence_ember_high", "a large glowing red-orange crystal cluster on a gold base, fire pouring out"),
        ("essence_tide_high", "a large glowing deep blue crystal cluster on a gold base, water light pouring out"),
        ("essence_gale_high", "a large glowing green crystal cluster on a gold base, wind swirling out"),
    ]),
    "stones": (3, 2, [
        ("whetstone_rare", "a flat grey-blue whetstone with a faint blue rune glowing on it"),
        ("whetstone_hero", "a flat violet whetstone with a violet rune glowing on it"),
        ("whetstone_legend", "a flat gold-veined whetstone with a gold rune blazing on it"),
        ("gem_rare", "a cut blue gemstone glinting"),
        ("gem_hero", "a cut violet gemstone glinting"),
        ("gem_legend", "a cut gold gemstone blazing with inner light"),
    ]),
}

# The sheets whose icons carry a painted GLOW, keyed with the halo ramp
# (`halo_alpha`): the glow fades into the black ground, the flood fill keeps
# everything brighter than 34, and the fade's dark skirt shipped as a rim of
# ground round every scroll — a dirty black outline on the charge's bright
# disc and the summon screen's painting (run 221). (lo, hi) is the ramp on
# the max channel: under lo the skirt is gone, over hi it is paint.
HALO_RAMP = {"scrolls": (70, 110)}


def prompt(cols, rows, items):
    numbered = "; ".join(f"{i + 1}) {words}" for i, (_, words) in enumerate(items))
    return (
        f"A grid of {len(items)} game item icons for a mobile fantasy RPG, {cols} columns by {rows} rows, "
        f"every icon centred in its own equal cell with wide margins of empty black around it, on a PLAIN PURE "
        f"BLACK background with nothing else, {STYLE}; no borders, no frames, no cell lines, no text, no numbers, "
        f"no letters, no labels. Reading left to right, then top to bottom: {numbered}"
    )


def paint(name):
    cols, rows, items = SHEETS[name]
    ART.mkdir(parents=True, exist_ok=True)
    out = ART / f"sheet_{name}.png"
    if out.exists():
        print(f"have {out.name}")
        return
    size = "1024x1024" if rows == cols else ("1024x768" if rows < cols else "768x1024")
    subprocess.run([sys.executable, str(ROOT / "tools" / "genart.py"), "--prompt", prompt(cols, rows, items),
                    "--out", str(out), "--size", size], check=True)
    print(f"painted {out.name}")


def key(cell_rgb):
    """The icon in a cell: everything not black, flood-filled from the
    border so a dark line inside the icon is kept; the largest piece."""
    a = cell_rgb.astype(np.float32)
    dark = a.max(-1) < 34
    lab, _ = ndimage.label(dark)
    border = set(np.unique(np.concatenate([lab[0], lab[-1], lab[:, 0], lab[:, -1]])))
    border.discard(0)
    ground = np.isin(lab, list(border))
    # A sheet the painter put on WHITE with a black square per cell (the
    # essences sheet of 2026-09-17 came back that way): when the cell's
    # border is mostly white, the white margin is ground, and so is every
    # black piece that touches the margin - the square the icon sits in. A
    # white highlight inside the icon is never reached from there.
    bright = (a.min(-1) > 225) & ((a.max(-1) - a.min(-1)) < 18)
    edge = np.concatenate([bright[0], bright[-1], bright[:, 0], bright[:, -1]])
    if edge.mean() > 0.5:
        blab, _ = ndimage.label(bright)
        bborder = set(np.unique(np.concatenate([blab[0], blab[-1], blab[:, 0], blab[:, -1]])))
        bborder.discard(0)
        margin = np.isin(blab, list(bborder))
        touching = set(np.unique(lab[ndimage.binary_dilation(margin, iterations=2) & dark]))
        touching.discard(0)
        ground = margin | np.isin(lab, list(touching))
    icon = ~ground
    lab, n = ndimage.label(icon)
    if n == 0:
        return icon
    sizes = ndimage.sum(icon, lab, range(1, n + 1))
    keep = lab == (1 + int(np.argmax(sizes)))
    # A detached spark or a second piece of the same icon within a short
    # reach of the main piece stays; a stray speck across the cell goes.
    near = ndimage.binary_dilation(keep, iterations=18)
    return icon & near


def _disk(r):
    y, x = np.ogrid[-r:r + 1, -r:r + 1]
    return (x * x + y * y) <= r * r


def halo_alpha(cell_rgb, lo=70, hi=110, seed=40, tol=4.0, edge=8.0, close=3, reach=160):
    """The glow's dark skirt as a ramp to transparent (2026-09-23): 1 on the
    icon's paint, 0 on the skirt's darkest, a ramp from `lo` to `hi` between.

    The skirt is what is reached from the cell's border by CLIMBING the glow:
    it starts on the ground (darker than `seed`, touching the border) and
    grows one pixel at a time into a pixel under `hi` that is no darker than
    the brightest skirt pixel beside it less `tol`, on smooth paint (a
    gradient under `edge` per pixel), and outside the icon's silhouette (its
    bright paint and every painted edge, closed over `close`-pixel gaps and
    filled). So a dark detail INSIDE the icon is never reached: the black half
    of the Light & Dark scroll sits behind the violet glow's crest (the climb
    would have to go down to reach it), and a dark ribbon, the shadow inside a
    rolled end or a vine inside its outline is inside the filled silhouette.

    Brightness is the MAX CHANNEL, not luma: a glow painted on black scales
    every channel together, so the max channel is the glow's own strength
    whatever its hue, while luma calls saturated paint dark — the mystical
    scroll's royal-blue ribbon is luma 67 and max 200, and a luma ramp made
    it transparent (the first cut here)."""
    v = cell_rgb.astype(np.float32).max(-1)
    vs = ndimage.gaussian_filter(v, 1.0)
    grad = np.hypot(ndimage.sobel(vs, 1), ndimage.sobel(vs, 0)) / 8.0
    solid = ndimage.binary_fill_holes(ndimage.binary_closing((grad >= edge) | (vs >= hi), structure=_disk(close)))
    lab, _ = ndimage.label(vs < seed)
    border = set(np.unique(np.concatenate([lab[0], lab[-1], lab[:, 0], lab[:, -1]])))
    border.discard(0)
    skirt = np.isin(lab, list(border)) & ~solid
    climbable = (vs < hi) & (grad < edge) & ~solid
    for _ in range(reach):
        crest = ndimage.maximum_filter(np.where(skirt, vs, -1e9), size=3)
        grow = ~skirt & climbable & (crest > -1e8) & (vs >= crest - tol)
        if not grow.any():
            break
        skirt |= grow
    ramp = np.clip((v - lo) / float(hi - lo), 0.0, 1.0)
    return np.where(skirt, ramp, 1.0).astype(np.float32)


def ship_cell(cell, path, px=256, margin=0.08, ramp=None):
    """`ramp` is (lo, hi) for a sheet in HALO_RAMP: the glow's dark skirt
    fades out (`halo_alpha`) instead of shipping as a rim of ground. The
    framing is the key's either way, so an icon keeps its size in the UI."""
    rgb = np.asarray(cell.convert("RGB"))
    mask = key(rgb)
    if not mask.any():
        print(f"  EMPTY {path.name}")
        return False
    ys, xs = np.where(mask)
    y0, y1, x0, x1 = ys.min(), ys.max() + 1, xs.min(), xs.max() + 1
    side = max(y1 - y0, x1 - x0)
    pad = int(side * margin)
    side += 2 * pad
    canvas = np.zeros((side, side, 4), dtype=np.float32)
    if ramp:
        alpha = ndimage.gaussian_filter(mask.astype(np.float32) * halo_alpha(rgb, *ramp), 0.7)
    else:
        alpha = ndimage.gaussian_filter(mask.astype(np.float32), 0.7)
    h, w = y1 - y0, x1 - x0
    oy, ox = pad + (side - 2 * pad - h) // 2, pad + (side - 2 * pad - w) // 2
    canvas[oy:oy + h, ox:ox + w, :3] = rgb[y0:y1, x0:x1] / 255.0
    canvas[oy:oy + h, ox:ox + w, 3] = alpha[y0:y1, x0:x1]
    im = Image.fromarray((np.clip(canvas, 0, 1) * 255).astype(np.uint8), "RGBA").resize((px, px), Image.LANCZOS)
    im.save(path)
    print(f"  {path.name}  ({int(mask.mean() * 100)}% of the cell)")
    return True


def split(name, px=256, sheet_name=None, ramp="sheet", only=None):
    """Ships every cell of `sheet_<name>.png` (or of `sheet_<sheet_name>.png`
    laid out as `name` — the scrolls' 2K repaint, `sheet_scrolls_2k.png`, is
    the scrolls sheet's own nine cells painted again as a `--ref` edit of it,
    2026-09-17) at `px` pixels. The scrolls ship at 512 because the summoning
    circle draws one at a quarter of the ring; everything else at 256.
    `ramp` is the sheet's own HALO_RAMP entry unless given ((lo, hi), or None
    for the plain key); `only` ships just the keys starting with one of its
    prefixes (`--only scroll_` leaves the sheet's relic cache as it is)."""
    cols, rows, items = SHEETS[name]
    if ramp == "sheet":
        ramp = HALO_RAMP.get(name)
    src = ART / f"sheet_{sheet_name or name}.png"
    if not src.exists():
        sys.exit(f"no {src}; paint it first")
    sheet = Image.open(src).convert("RGB")
    w, h = sheet.size
    cw, ch = w / cols, h / rows
    OUT.mkdir(parents=True, exist_ok=True)
    for i, (item_key, _) in enumerate(items):
        if only and not any(item_key.startswith(p) for p in only):
            continue
        r, c = divmod(i, cols)
        cell = sheet.crop((int(c * cw), int(r * ch), int((c + 1) * cw), int((r + 1) * ch)))
        ship_cell(cell, OUT / f"item_{item_key}.png", px=px, ramp=ramp)


def preview(out):
    keys = [k for _, (_, _, items) in SHEETS.items() for k, _ in items]
    shipped = [(k, OUT / f"item_{k}.png") for k in keys if (OUT / f"item_{k}.png").exists()]
    if not shipped:
        sys.exit("nothing shipped yet")
    cols = 9
    cell = 150
    rows = (len(shipped) + cols - 1) // cols
    board = Image.new("RGB", (cols * cell, rows * (cell + 24)), (235, 226, 207))
    d = ImageDraw.Draw(board)
    try:
        font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 12)
    except OSError:
        font = ImageFont.load_default()
    for i, (k, p) in enumerate(shipped):
        r, c = divmod(i, cols)
        im = Image.open(p).convert("RGBA").resize((cell - 30, cell - 30), Image.LANCZOS)
        board.paste(im, (c * cell + 15, r * (cell + 24) + 8), im)
        d.text((c * cell + 6, r * (cell + 24) + cell - 14), k, fill=(31, 25, 18), font=font)
    board.save(out, quality=90)
    print(f"wrote {out}: {len(shipped)} icons")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--list", action="store_true")
    ap.add_argument("--paint", help="a sheet name, or all")
    ap.add_argument("--split", help="a sheet name, or all")
    ap.add_argument("--preview", help="write a contact sheet of the shipped icons here")
    ap.add_argument("--px", type=int, default=256, help="the shipped size (the scrolls ship at 512)")
    ap.add_argument("--sheet", help="split this painted sheet instead (e.g. scrolls_2k for --split scrolls)")
    ap.add_argument("--ramp", help="LO,HI: key the glow's dark skirt with this ramp (HALO_RAMP gives the scrolls 70,110)")
    ap.add_argument("--no-ramp", action="store_true", help="the plain flood-fill key even for a sheet in HALO_RAMP")
    ap.add_argument("--only", help="comma-separated key prefixes: ship just these cells (e.g. scroll_)")
    args = ap.parse_args()
    ramp = None if args.no_ramp else (tuple(float(x) for x in args.ramp.split(",")) if args.ramp else "sheet")
    only = [p for p in args.only.split(",") if p] if args.only else None
    if args.list:
        for name, (cols, rows, items) in SHEETS.items():
            print(f"{name} ({cols}x{rows}): " + ", ".join(k for k, _ in items))
        print(f"{sum(len(items) for _, (_, _, items) in SHEETS.items())} icons in {len(SHEETS)} sheets")
    if args.paint:
        for name in (SHEETS if args.paint == "all" else [args.paint]):
            paint(name)
    if args.split:
        for name in (SHEETS if args.split == "all" else [args.split]):
            print(name)
            split(name, px=args.px, sheet_name=args.sheet, ramp=ramp, only=only)
    if args.preview:
        preview(args.preview)


if __name__ == "__main__":
    main()
