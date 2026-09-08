#!/usr/bin/env python3
"""
Fetches the screenshots the CI job took of the app and lays them out on one
sheet, so a session that cannot run the simulator can look at the game.

    python3 tools/ciframes.py                 # -> /tmp/ci_frames/ and ci_sheet.jpg beside it
    python3 tools/ciframes.py --out my.jpg
    python3 tools/ciframes.py --log-lines 200 # more of each step's console

The job also publishes each step's console (<step>-console.txt: the app's
stdout and stderr, with the frameworks' os_log lines mirrored in) and the
simulator's log for the process (system-log.txt). This prints the lines that
matter from each — the [ModelLibrary] block and anything that says error or
shader — and leaves the files in frames/.

The job (.github/workflows/build.yml) launches the app in a simulator once per
screen with `-tour -tour-step N`, photographs it, and force-pushes small JPEGs
of the frames to the orphan branch `ci/screens`, which this fetches. The
artifact store keeps the full-size PNGs, but it lives on a host the session's
network policy refuses; the branch does not.

The simulator captures a landscape-only app in a portrait framebuffer, so a
frame taller than it is wide is stood up here.
"""
import argparse, glob, os, subprocess, sys

from PIL import Image, ImageDraw

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--out", default="/tmp/ci_frames/ci_sheet.jpg")
    ap.add_argument("--width", type=int, default=640, help="width of one frame on the sheet")
    ap.add_argument("--cols", type=int, default=3)
    ap.add_argument("--log-lines", type=int, default=40, help="console lines of interest to print per step")
    a = ap.parse_args()

    out_dir = os.path.dirname(os.path.abspath(a.out))
    frames_dir = os.path.join(out_dir, "frames")
    os.makedirs(frames_dir, exist_ok=True)
    for f in glob.glob(os.path.join(frames_dir, "*")):
        os.remove(f)

    subprocess.run(["git", "-C", REPO, "fetch", "-q", "origin", "ci/screens"], check=True)
    names = subprocess.run(["git", "-C", REPO, "ls-tree", "--name-only", "origin/ci/screens"],
                           capture_output=True, text=True, check=True).stdout.split()
    for n in names:
        data = subprocess.run(["git", "-C", REPO, "show", f"origin/ci/screens:{n}"], capture_output=True, check=True).stdout
        with open(os.path.join(frames_dir, n), "wb") as fh:
            fh.write(data)
    source = os.path.join(frames_dir, "SOURCE.txt")
    if os.path.exists(source):
        print(open(source).read().strip())

    # The job also publishes what the app printed during each step. The lines
    # that decide anything are the loader's and the frameworks' complaints;
    # the rest is there in the file for when they are not enough.
    for log in sorted(glob.glob(os.path.join(frames_dir, "*-console.txt"))):
        lines = open(log, errors="replace").read().splitlines()
        wanted = [l for l in lines if "[ModelLibrary]" in l or "[Diagnostics]" in l
                  or any(k in l for k in ("rror", "SCNMetal", "shader", "Shader", "compile", "fatal", "Fatal"))]
        print(f"-- {os.path.basename(log)}: {len(lines)} lines, {len(wanted)} of interest")
        for l in wanted[:a.log_lines]:
            print("   " + l[:220])
        if len(wanted) > a.log_lines:
            print(f"   … {len(wanted) - a.log_lines} more in {log}")

    files = sorted(f for f in glob.glob(os.path.join(frames_dir, "*")) if f.lower().endswith((".jpg", ".png")))
    if not files:
        sys.exit("no frames on ci/screens")
    thumbs = []
    for f in files:
        im = Image.open(f).convert("RGB")
        if im.height > im.width:
            im = im.rotate(90, expand=True)
        thumbs.append((os.path.basename(f), im))
    w = a.width
    h = int(thumbs[0][1].height * w / thumbs[0][1].width)
    rows = (len(thumbs) + a.cols - 1) // a.cols
    sheet = Image.new("RGB", (a.cols * w, rows * (h + 18)), (10, 10, 16))
    draw = ImageDraw.Draw(sheet)
    for i, (name, im) in enumerate(thumbs):
        x, y = (i % a.cols) * w, (i // a.cols) * (h + 18)
        sheet.paste(im.resize((w, h)), (x, y + 18))
        draw.text((x + 4, y + 3), name, fill=(255, 230, 120))
    sheet.save(a.out, quality=80)
    print(f"{len(thumbs)} frames -> {a.out}  {sheet.size[0]}x{sheet.size[1]}")


if __name__ == "__main__":
    main()
