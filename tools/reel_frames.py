#!/usr/bin/env python3
"""The CI skill reel as pictures (2026-09-25; Docs/PLAN.md *Skills that look
like themselves*): the video the build job records during the `skill_reel`
tour step (fetched by tools/ciframes.py into its shots folder) cut into
contact sheets, so a motion or an effect can be judged here, frame by frame,
and the owner can be sent the sheets beside the video itself.

  python3 tools/reel_frames.py <video> --out /tmp/reel         # every 0.25 s, 16 to a sheet
  python3 tools/reel_frames.py <video> --out /tmp/reel --from 12 --to 18 --every 0.1

Needs a static ffmpeg: `pip install imageio-ffmpeg`.
"""
import argparse
import subprocess
import tempfile
from pathlib import Path

from PIL import Image, ImageDraw


def ffmpeg():
    import imageio_ffmpeg
    return imageio_ffmpeg.get_ffmpeg_exe()


def frames(video, start, end, every, width):
    tmp = Path(tempfile.mkdtemp(prefix="reel_"))
    args = [ffmpeg(), "-v", "error", "-ss", str(start)] + (["-to", str(end)] if end else []) + \
           ["-i", str(video), "-vf", f"fps={1.0 / every},scale={width}:-1", str(tmp / "f_%05d.jpg")]
    subprocess.run(args, check=True)
    return sorted(tmp.glob("f_*.jpg"))


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("video")
    ap.add_argument("--out", required=True)
    ap.add_argument("--from", dest="start", type=float, default=0.0)
    ap.add_argument("--to", dest="end", type=float)
    ap.add_argument("--every", type=float, default=0.25, help="seconds between frames")
    ap.add_argument("--per", type=int, default=16, help="frames to a sheet (4 across)")
    ap.add_argument("--width", type=int, default=480)
    a = ap.parse_args()
    out = Path(a.out)
    out.mkdir(parents=True, exist_ok=True)
    shots = frames(a.video, a.start, a.end, a.every, a.width)
    cols = 4
    for s in range(0, len(shots), a.per):
        chunk = shots[s:s + a.per]
        first = Image.open(chunk[0])
        w, h = first.size
        rows = (len(chunk) + cols - 1) // cols
        sheet = Image.new("RGB", (cols * w, rows * (h + 18)), (16, 16, 20))
        d = ImageDraw.Draw(sheet)
        for i, path in enumerate(chunk):
            x, y = (i % cols) * w, (i // cols) * (h + 18)
            sheet.paste(Image.open(path), (x, y + 18))
            t = a.start + (s + i) * a.every
            d.text((x + 4, y + 3), f"{t:6.2f} s", fill=(235, 235, 235))
        dest = out / f"reel_{s // a.per + 1:02d}.jpg"
        sheet.save(dest, quality=85)
        print(dest)


if __name__ == "__main__":
    main()
