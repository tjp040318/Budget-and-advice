#!/usr/bin/env python3
"""Reads the CI tour's battle frames and says how bright they are, so "too
bright" is a number rather than an opinion.

    python3 tools/framelight.py                 # every battle frame
    python3 tools/framelight.py --all           # every frame of the tour
    python3 tools/framelight.py --only 29-realm # frames whose name matches

Run `python3 tools/ciframes.py` first: this reads the same
/tmp/ci_frames/frames directory it fetches.

Per frame it prints three bands — the painting's band across the top, the
middle where the enemies stand, the near floor under the team — and for
each the MEAN luminance (0-255) and the share of pixels at 240 or over,
which are pixels with no detail left in them. The owner's complaint of
2026-09-15 ("Lighting and contrast feels too bright doesnt it?") measured
25.2% of Olympus's near floor and 16.5% of the fjord's sky as pure white
while the Duat and the arena sat at 0.2%; the target since is every band
under 2% with its mean between 70 and 130.
"""
import argparse
import glob
import os

import numpy as np
from PIL import Image

FRAMES = "/tmp/ci_frames/frames"
BANDS = (("painting", 0.0, 0.28), ("middle", 0.28, 0.62), ("near floor", 0.62, 1.0))
CLIPPED = 240
TARGET_CLIP = 2.0
# A night marsh and a dusk garden are legitimately dark and a sunlit temple
# legitimately bright; only the ends of the range are worth a flag. The
# CLIPPED share is the rule.
TARGET_MEAN = (35, 155)


def luminance(path):
    a = np.asarray(Image.open(path).convert("RGB")).astype(np.float32)
    return 0.2126 * a[..., 0] + 0.7152 * a[..., 1] + 0.0722 * a[..., 2]


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--dir", default=FRAMES)
    ap.add_argument("--all", action="store_true", help="every frame, not only the battles")
    ap.add_argument("--only", help="substring of the frame's name")
    a = ap.parse_args()

    files = sorted(glob.glob(os.path.join(a.dir, "*.jpg")) + glob.glob(os.path.join(a.dir, "*.png")))
    if not files:
        raise SystemExit(f"no frames in {a.dir} — run python3 tools/ciframes.py first")
    rows, worst = [], (0.0, "")
    for path in files:
        name = os.path.splitext(os.path.basename(path))[0]
        if a.only and a.only not in name:
            continue
        if not a.all and not a.only and "battle" not in name:
            continue
        y = luminance(path)
        height = y.shape[0]
        cells = []
        for _, low, high in BANDS:
            band = y[int(height * low):int(height * high)]
            clip = float((band > CLIPPED).mean() * 100)
            cells.append((float(band.mean()), clip))
            if clip > worst[0]:
                worst = (clip, f"{name} {_}")
        rows.append((name, cells))
    if not rows:
        raise SystemExit("no frames matched")
    head = "".join(f"{label:>18s}" for label, _, _ in BANDS)
    print(f"{'frame':26s}{head}")
    for name, cells in rows:
        line = f"{name:26s}"
        for mean, clip in cells:
            flag = "!" if clip > TARGET_CLIP or not (TARGET_MEAN[0] <= mean <= TARGET_MEAN[1]) else " "
            line += f"{mean:11.0f} {clip:4.1f}%{flag}"
        print(line)
    print(f"\nworst band {worst[0]:.1f}% clipped ({worst[1]}); target is under {TARGET_CLIP}% "
          f"with the mean in {TARGET_MEAN[0]}-{TARGET_MEAN[1]}")
    print("! marks a band outside the target.")


if __name__ == "__main__":
    main()
