#!/usr/bin/env python3
"""
Veo, for effects: a short clip of one effect on black becomes a flipbook the
particle systems play (SceneKit image sequences), which is how an explosion
gets to roll and dissipate instead of being a sprite that grows and fades.

    python3 tools/veo.py generate fireburst --prompt "..." --seconds 4     # Art/VFX/fireburst.mp4
    python3 tools/veo.py sheet fireburst --frames 32 --cols 8              # Portraits/vfx_fireburst_sheet.png

Billed per second of video by Google (the owner's word: one clip now, then
about ten dollars a month) — never run `generate` without it, and prefer the
fast model at four seconds. The key is $GEMINI_API_KEY, never printed or
written. The clip is 16:9; the sheet cuts the centre square, drops the black
lead-in and tail, keeps `--frames` evenly spaced frames, and ships them with
alpha from the brightest channel, as tools/vfx_ship.py does for a sprite.
"""
import argparse, io, json, os, sys, time
from pathlib import Path

import numpy as np
import requests
from PIL import Image

REPO = Path(__file__).resolve().parents[1]
SRC = REPO / "Art" / "VFX"
DST = REPO / "Pantheon" / "Resources" / "Portraits"
BASE = "https://generativelanguage.googleapis.com/v1beta"


def key():
    k = os.environ.get("GEMINI_API_KEY", "").strip()
    if not k:
        sys.exit("no GEMINI_API_KEY in the environment")
    return k


def cmd_generate(a):
    SRC.mkdir(parents=True, exist_ok=True)
    out = SRC / f"{a.name}.mp4"
    if out.exists() and not a.force:
        print(f"have {out.relative_to(REPO)}")
        return
    headers = {"x-goog-api-key": key(), "Content-Type": "application/json"}
    body = {
        "instances": [{"prompt": a.prompt}],
        "parameters": {"aspectRatio": "16:9", "durationSeconds": a.seconds, "resolution": a.resolution},
    }
    if a.negative:
        body["parameters"]["negativePrompt"] = a.negative
    r = requests.post(f"{BASE}/models/{a.model}:predictLongRunning", headers=headers, json=body, timeout=60)
    if r.status_code != 200:
        sys.exit(f"{r.status_code}: {r.text[:600]}")
    op = r.json()["name"]
    print(f"{a.model}: operation started, {a.seconds}s at {a.resolution}")
    started = time.time()
    while True:
        time.sleep(10)
        s = requests.get(f"{BASE}/{op}", headers=headers, timeout=60)
        if s.status_code != 200:
            sys.exit(f"poll {s.status_code}: {s.text[:300]}")
        d = s.json()
        if d.get("done"):
            break
        print(f"  … {int(time.time() - started)}s")
        if time.time() - started > 900:
            sys.exit("gave up after fifteen minutes")
    if "error" in d:
        sys.exit(f"failed: {json.dumps(d['error'])[:600]}")
    resp = d.get("response", {})
    samples = resp.get("generateVideoResponse", {}).get("generatedSamples") or resp.get("generatedSamples") or []
    if not samples:
        sys.exit(f"no video in the response: {json.dumps(resp)[:600]}")
    uri = samples[0]["video"]["uri"]
    v = requests.get(uri, headers={"x-goog-api-key": key()}, timeout=300)
    if v.status_code != 200:
        sys.exit(f"download {v.status_code}: {v.text[:300]}")
    out.write_bytes(v.content)
    print(f"  -> {out.relative_to(REPO)}  {len(v.content) // 1024} KB  in {int(time.time() - started)}s")


def read_frames(path):
    import cv2
    cap = cv2.VideoCapture(str(path))
    frames = []
    while True:
        ok, frame = cap.read()
        if not ok:
            break
        frames.append(cv2.cvtColor(frame, cv2.COLOR_BGR2RGB))
    cap.release()
    return frames


def cmd_sheet(a):
    src = SRC / f"{a.name}.mp4"
    frames = read_frames(src)
    if not frames:
        sys.exit(f"no frames read from {src}")
    h, w, _ = frames[0].shape
    side = min(h, w)
    x0, y0 = (w - side) // 2, (h - side) // 2
    lum = np.array([f[y0:y0 + side, x0:x0 + side].max(axis=2).mean() / 255 for f in frames])
    # The effect's life: from the first frame that lights up to the last.
    lit = np.where(lum > a.floor)[0]
    if len(lit) == 0:
        sys.exit("the clip never lights up over the floor")
    first, last = int(lit[0]), int(lit[-1])
    if a.until:
        # Veo kept the fireball burning for its whole four seconds where the
        # prompt asked for it to dissipate: the sheet keeps the burst and the
        # particle's own fade does the dissipating.
        last = min(last, first + int(a.until * 24) - 1)
    picks = np.linspace(first, last, a.frames).round().astype(int)
    print(f"{src.name}: {len(frames)} frames {w}x{h}; lit {first}..{last}; keeping {a.frames}")
    cell = a.cell
    cols = a.cols
    rows = (a.frames + cols - 1) // cols
    sheet = np.zeros((rows * cell, cols * cell, 4), dtype=np.float32)
    for i, f in enumerate(picks):
        im = Image.fromarray(frames[f][y0:y0 + side, x0:x0 + side]).resize((cell, cell), Image.LANCZOS)
        arr = np.asarray(im).astype(np.float32) / 255
        alpha = np.clip((arr.max(axis=2) - 0.06) / 0.94, 0, 1)
        colour = np.where(alpha[..., None] > 0, np.clip(arr / np.maximum(alpha[..., None], 1e-3), 0, 1), 0)
        r, c = divmod(i, cols)
        sheet[r * cell:(r + 1) * cell, c * cell:(c + 1) * cell] = np.dstack([colour, alpha])
    DST.mkdir(parents=True, exist_ok=True)
    out = DST / f"vfx_{a.name}_sheet.png"
    Image.fromarray((sheet * 255).round().astype(np.uint8), "RGBA").save(out, optimize=True)
    print(f"  -> {out.relative_to(REPO)}  {rows} rows x {cols} cols of {cell}px  {out.stat().st_size // 1024} KB")
    if a.preview:
        grey = Image.new("RGB", (cols * cell, rows * cell), (90, 90, 100))
        s = Image.open(out)
        grey.paste(s, (0, 0), s)
        grey.save(a.preview)
        print(f"  preview -> {a.preview}")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    g = sub.add_parser("generate", help="one clip, billed")
    g.add_argument("name")
    g.add_argument("--prompt", required=True)
    g.add_argument("--negative", default="text, watermark, logo, ground, floor, scene, objects, people, faces, camera movement, white background, grey background")
    g.add_argument("--seconds", type=int, default=4, choices=[4, 6, 8])
    g.add_argument("--resolution", default="720p", choices=["720p", "1080p"])
    g.add_argument("--model", default="veo-3.1-fast-generate-preview")
    g.add_argument("--force", action="store_true")
    s = sub.add_parser("sheet", help="cut the clip into a flipbook sheet with alpha")
    s.add_argument("name")
    s.add_argument("--frames", type=int, default=32)
    s.add_argument("--cols", type=int, default=8)
    s.add_argument("--cell", type=int, default=128)
    s.add_argument("--floor", type=float, default=0.04, help="mean brightness below which a frame is dark")
    s.add_argument("--until", type=float, help="keep only this many seconds from the first lit frame")
    s.add_argument("--preview", help="write the sheet over grey to look at")
    a = ap.parse_args()
    {"generate": cmd_generate, "sheet": cmd_sheet}[a.cmd](a)


if __name__ == "__main__":
    main()
