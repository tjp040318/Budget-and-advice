#!/usr/bin/env python3
"""
Turns a portrait into a world-space cut-out: the dark background becomes
transparent so the creature stands in the scene instead of floating on a black
card.

Writes `<name>_cut.png` beside each source. The renderer uses the cut-out for a
unit that has a portrait but no 3D model.

    python3 tools/cutouts.py

Alpha is a soft luminance ramp, not a hard key: these paintings have a radial
glow behind the subject, and a hard threshold either clips it into a halo or
leaves a black rectangle. The ramp keeps the glow as a fade to nothing.
"""
import os, sys
from PIL import Image, ImageFilter

SRC = os.path.join(os.path.dirname(__file__), "..", "Pantheon", "Resources", "Portraits")
# Enemies only: the five Anubis are drawn as cards in the UI, never in world
# space, and Anubis himself has a real mesh.
NAMES = ["portrait_shabti", "portrait_serpopard", "portrait_sun_scarab",
         "portrait_sandstone_sentinel", "portrait_ammit", "portrait_apep"]

LOW, HIGH = 52, 132          # luminance: fully transparent below, fully opaque above


def cut(name):
    path = os.path.join(SRC, f"{name}.png")
    if not os.path.exists(path):
        print(f"  skip {name} (no source)"); return
    img = Image.open(path).convert("RGB")
    lum = img.convert("L")
    alpha = lum.point(lambda v: 0 if v <= LOW else (255 if v >= HIGH else int(255 * (v - LOW) / (HIGH - LOW))))
    # Soften the edge so the cut-out does not look scissored, and so the glow
    # falls off rather than stopping.
    alpha = alpha.filter(ImageFilter.GaussianBlur(1.6))

    out = img.convert("RGBA")
    out.putalpha(alpha)
    # Trim fully-transparent margin so the sprite's height is the creature's
    # height, not the canvas's — otherwise every card is padded differently and
    # nothing lines up on the ground.
    box = out.getbbox()
    if box:
        out = out.crop(box)
    dst = os.path.join(SRC, f"{name}_cut.png")
    out.save(dst, "PNG", optimize=True)
    w, h = out.size
    print(f"  {name}_cut.png  {w}x{h}  {os.path.getsize(dst)//1024} KB")


if __name__ == "__main__":
    for n in NAMES:
        cut(n)
