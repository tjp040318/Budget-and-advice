"""Contact sheets of the serious concepts, eight a sheet with the family's
name, to judge proportions and the rigger's rules before a mesh is bought.
    python3 tools/batch/serious_sheet.py [--all | family ...] [--out prefix]"""
import sys, glob, os
from PIL import Image, ImageDraw, ImageFont
REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
args = [a for a in sys.argv[1:] if not a.startswith("--")]
prefix = sys.argv[sys.argv.index("--out") + 1] if "--out" in sys.argv else "/tmp/pantheon-batch/serious_sheet"
files = sorted(glob.glob(os.path.join(REPO, "Art/Concepts/*_serious_sw.png")), key=os.path.getmtime)
if args:
    files = [f for f in files if os.path.basename(f)[:-len("_serious_sw.png")] in args]
font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", 18)
for s in range(0, len(files), 8):
    chunk = files[s:s + 8]
    tiles = []
    for f in chunk:
        im = Image.open(f).convert("RGB"); im.thumbnail((380, 380))
        t = Image.new("RGB", (im.width, im.height + 26), (24, 22, 20))
        ImageDraw.Draw(t).text((6, 4), os.path.basename(f)[:-len("_serious_sw.png")], fill=(245, 235, 210), font=font)
        t.paste(im, (0, 26)); tiles.append(t)
    cols = 4; rows = (len(tiles) + 3) // 4
    tw = max(t.width for t in tiles); th = max(t.height for t in tiles)
    sheet = Image.new("RGB", (cols * tw, rows * th), (24, 22, 20))
    for i, t in enumerate(tiles):
        sheet.paste(t, ((i % cols) * tw, (i // cols) * th))
    out = f"{prefix}_{s // 8 + 1}.jpg"; sheet.save(out, quality=86); print(out, [os.path.basename(f).split("_serious")[0] for f in chunk])
