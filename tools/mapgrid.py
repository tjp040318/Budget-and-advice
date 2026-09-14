#!/usr/bin/env python3
"""Draw a ten-by-ten grid over a painted chapter map so its landmarks can be
read off as fractions for `ChapterMapArt.byChapter`, and check a guess.

    python3 tools/mapgrid.py Pantheon/Resources/Portraits/map_duat_1.jpg --out grid.jpg
    python3 tools/mapgrid.py map_duat_1.jpg --dots 0.13,0.70 0.32,0.47 --chests 0.47,0.83 --out check.jpg

The grid's lines are numbered 1–9 along the top and the left edge; a
landmark's centre is read as (x/10, y/10). `--dots` draws a numbered gold
medallion at each point in stage order and `--chests` a cream chest mark,
so a row of anchors can be looked at before it is committed. The output is
1400 px wide.
"""
import argparse
from PIL import Image, ImageDraw, ImageFont


def parse_points(items):
    points = []
    for item in items or []:
        x, y = item.split(",")
        points.append((float(x), float(y)))
    return points


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("image")
    ap.add_argument("--out", default="mapgrid.jpg")
    ap.add_argument("--dots", nargs="*", help="x,y fractions in stage order")
    ap.add_argument("--chests", nargs="*", help="x,y fractions")
    ap.add_argument("--no-grid", action="store_true")
    args = ap.parse_args()

    im = Image.open(args.image).convert("RGB")
    w, h = im.size
    d = ImageDraw.Draw(im)
    try:
        font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", max(18, w // 90))
    except OSError:
        font = ImageFont.load_default()
    if not args.no_grid:
        for i in range(1, 10):
            x = int(w * i / 10)
            y = int(h * i / 10)
            d.line((x, 0, x, h), fill=(255, 255, 255), width=2)
            d.text((x + 4, 4), str(i), font=font, fill=(255, 255, 0))
            d.line((0, y, w, y), fill=(255, 255, 255), width=2)
            d.text((4, y + 2), str(i), font=font, fill=(255, 255, 0))
    r = max(14, w // 48)
    for index, (fx, fy) in enumerate(parse_points(args.dots), start=1):
        x, y = fx * w, fy * h
        d.ellipse((x - r, y - r, x + r, y + r), fill=(176, 138, 46), outline=(255, 240, 200), width=3)
        label = str(index)
        tw = d.textlength(label, font=font)
        d.text((x - tw / 2, y - r * 0.55), label, font=font, fill=(31, 25, 18))
    s = r * 0.8
    for fx, fy in parse_points(args.chests):
        x, y = fx * w, fy * h
        d.rectangle((x - s, y - s * 0.7, x + s, y + s * 0.7), fill=(244, 237, 221), outline=(140, 109, 34), width=3)
    out_w = 1400
    im.resize((out_w, int(out_w * h / w)), Image.LANCZOS).save(args.out, quality=88)
    print(f"wrote {args.out} from {w}x{h}")


if __name__ == "__main__":
    main()
