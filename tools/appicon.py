#!/usr/bin/env python3
"""
Draws the app icon: a gold jackal head inside a gold ring on deep indigo.

    python3 tools/appicon.py    # -> Pantheon/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png

The icon set shipped empty, so the home screen showed a blank tile. This is
geometry, not a painting: two tall ears, a long muzzle, a gold ring, the same
indigo and gold the interface uses. Drawn at twice the size and downsampled.
"""

from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

REPO = Path(__file__).resolve().parent.parent
OUT = REPO / "Pantheon" / "Resources" / "Assets.xcassets" / "AppIcon.appiconset" / "AppIcon.png"
N = 1024
S = 2


def main():
    n = N * S
    img = Image.new("RGB", (n, n), (7, 6, 15))
    draw = ImageDraw.Draw(img, "RGBA")
    # indigo radial lift behind the head
    for k in range(40, 0, -1):
        r = n * 0.02 * k
        a = int(6 + 3 * (40 - k))
        draw.ellipse([n / 2 - r, n * 0.44 - r, n / 2 + r, n * 0.44 + r], fill=(44, 34, 88, min(a, 120)))
    # gold ring
    ring_r, ring_w = n * 0.425, n * 0.022
    for colour, inset in (((122, 92, 36, 255), 0), ((247, 227, 155, 255), ring_w * 0.35), ((217, 174, 78, 255), ring_w * 0.7)):
        r = ring_r - inset
        draw.ellipse([n / 2 - r, n / 2 - r, n / 2 + r, n / 2 + r], outline=colour, width=int(ring_w * 0.5))
    # the head: skull, muzzle, ears, in polished gold (three tones for a bevel)
    cx, cy = n * 0.52, n * 0.56
    gold, gold_dark, gold_light = (217, 174, 78), (138, 107, 40), (247, 227, 155)

    def head(dx, dy, colour):
        skull = [(cx - n * 0.14 + dx, cy - n * 0.04 + dy), (cx + n * 0.12 + dx, cy - n * 0.10 + dy),
                 (cx + n * 0.15 + dx, cy + n * 0.06 + dy), (cx + n * 0.06 + dx, cy + n * 0.20 + dy),
                 (cx - n * 0.10 + dx, cy + n * 0.16 + dy), (cx - n * 0.16 + dx, cy + n * 0.04 + dy)]
        muzzle = [(cx - n * 0.14 + dx, cy - n * 0.02 + dy), (cx - n * 0.36 + dx, cy + n * 0.05 + dy),
                  (cx - n * 0.37 + dx, cy + n * 0.10 + dy), (cx - n * 0.12 + dx, cy + n * 0.17 + dy)]
        ear_l = [(cx - n * 0.12 + dx, cy - n * 0.03 + dy), (cx - n * 0.10 + dx, cy - n * 0.34 + dy), (cx + n * 0.01 + dx, cy - n * 0.08 + dy)]
        ear_r = [(cx + n * 0.02 + dx, cy - n * 0.08 + dy), (cx + n * 0.10 + dx, cy - n * 0.36 + dy), (cx + n * 0.13 + dx, cy - n * 0.09 + dy)]
        for poly in (ear_l, ear_r, skull, muzzle):
            draw.polygon(poly, fill=colour + (255,))

    head(n * 0.006, n * 0.008, gold_dark)
    head(0, 0, gold)
    # highlight along the upper edges
    draw.polygon([(cx - n * 0.12, cy - n * 0.03), (cx - n * 0.10, cy - n * 0.34), (cx - n * 0.07, cy - n * 0.30), (cx - n * 0.10, cy - n * 0.05)], fill=gold_light + (200,))
    draw.polygon([(cx + n * 0.02, cy - n * 0.08), (cx + n * 0.10, cy - n * 0.36), (cx + n * 0.12, cy - n * 0.31), (cx + n * 0.05, cy - n * 0.09)], fill=gold_light + (200,))
    draw.polygon([(cx - n * 0.14, cy - n * 0.02), (cx - n * 0.36, cy + n * 0.05), (cx - n * 0.35, cy + n * 0.07), (cx - n * 0.13, cy + n * 0.01)], fill=gold_light + (170,))
    # the eye: a pale glowing slit
    ex, ey = cx - n * 0.06, cy + n * 0.03
    for r, a in ((n * 0.035, 60), (n * 0.022, 120)):
        draw.ellipse([ex - r, ey - r * 0.6, ex + r, ey + r * 0.6], fill=(127, 224, 200, a))
    draw.ellipse([ex - n * 0.014, ey - n * 0.008, ex + n * 0.014, ey + n * 0.008], fill=(230, 255, 245, 255))

    out = img.filter(ImageFilter.GaussianBlur(0.6)).resize((N, N), Image.LANCZOS)
    OUT.parent.mkdir(parents=True, exist_ok=True)
    out.save(OUT, "PNG", optimize=True)
    print(f"{OUT.relative_to(REPO)}  {N}x{N}  {OUT.stat().st_size // 1024} KB")


if __name__ == "__main__":
    main()
