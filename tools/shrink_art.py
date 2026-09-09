#!/usr/bin/env python3
"""Ships the paintings as JPEG instead of PNG.

A Gemini card is a 1024x1024 painting with no transparency, and a PNG of one
is about 1.3 MB: 154 cards are 209 MB of the bundle, and batch 3's three
hundred more would have added 400 MB. The same image as JPEG at quality 92 is
about a fifth of that with no loss of resolution and no visible artefact on
painted art, so the reveal and the unit sheet still have their pixels.

Only files with no alpha channel are converted, which is exactly the paintings
(cards, backdrops, banners, the island). The UI kit, the particle sprite and
the rune ring keep their transparency and stay PNG.

`UIImage(named:)` finds a bundle file by name whatever its extension, so
nothing in SwiftUI changes; the two places that tested for a file by name and
extension go through `BundleArt.url(_:)` instead (Presentation.swift,
UnitBlueprint.swift).

    python3 tools/shrink_art.py                 # convert what is left
    python3 tools/shrink_art.py --dry-run
"""
import argparse
import sys
from pathlib import Path

from PIL import Image

REPO = Path(__file__).resolve().parent.parent
DIRS = [REPO / "Pantheon" / "Resources" / "Portraits", REPO / "Pantheon" / "Resources" / "Stage"]
QUALITY = 92


def convertible(path):
    """True for a painting: no alpha, and not one of the tiling stage
    textures, whose seams JPEG would soften."""
    if path.name.endswith("@3x.png") or path.name.startswith(("ui_", "floor_", "rock_", "sky_")) \
            or path.stem in ("mist", "rune_ring", "spark"):
        return False
    with Image.open(path) as im:
        return im.mode in ("RGB", "L") or (im.mode == "P" and "transparency" not in im.info)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--quality", type=int, default=QUALITY)
    a = ap.parse_args()
    before = after = 0
    done = skipped = 0
    for folder in DIRS:
        for png in sorted(folder.glob("*.png")):
            if not convertible(png):
                skipped += 1
                continue
            jpg = png.with_suffix(".jpg")
            before += png.stat().st_size
            if a.dry_run:
                done += 1
                continue
            with Image.open(png) as im:
                im.convert("RGB").save(jpg, "JPEG", quality=a.quality, optimize=True, progressive=True)
            after += jpg.stat().st_size
            png.unlink()
            done += 1
    print(f"converted {done}, kept {skipped} as PNG (alpha or a tiling texture)")
    if not a.dry_run and done:
        print(f"{before / 1048576:.0f} MB -> {after / 1048576:.0f} MB ({100 * after / before:.0f}%)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
