#!/usr/bin/env python3
"""
Generates one 2D asset with Google's Gemini image models and saves it at the
exact pixel size the app expects.

    python3 tools/genart.py --prompt "..." --out portrait_anubis_ember.png --size 1024x1024
    python3 tools/genart.py --prompt "..." --ref base.png --out variant.png --size 1024x1024

`--ref` attaches a reference image, which is how the five elemental Anubis
portraits stay the same character: generate one, then edit it four times.

The key is read from $GEMINI_API_KEY or from --key-file. Never from the repo.

Every prompt and filename the project needs is in Docs/ART_2D.md; this script
is only the plumbing. The composition rules in that document are appended to
every prompt automatically so a hand-typed call cannot forget them.
"""

import argparse, base64, json, os, sys, time, io
from pathlib import Path

import requests
from PIL import Image

ENDPOINT = "https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent"

# Rules that apply to every image regardless of what it is. Generators love
# adding frames and captions, and a baked-in frame fights the one the code draws.
ALWAYS_AVOID = ("no text, no lettering, no caption, no watermark, no logo, no signature, "
                "no border, no frame, no user interface elements")


def load_key(path):
    if os.environ.get("GEMINI_API_KEY"):
        return os.environ["GEMINI_API_KEY"].strip()
    if path and Path(path).exists():
        return Path(path).read_text().strip()
    sys.exit("no API key: set GEMINI_API_KEY or pass --key-file")


def build_request(prompt, ref_path, aspect):
    parts = [{"text": f"{prompt}. {ALWAYS_AVOID}."}]
    if ref_path:
        data = base64.b64encode(Path(ref_path).read_bytes()).decode()
        mime = "image/png" if ref_path.lower().endswith(".png") else "image/jpeg"
        parts.append({"inline_data": {"mime_type": mime, "data": data}})
    body = {
        "contents": [{"parts": parts}],
        "generationConfig": {
            "responseModalities": ["IMAGE"],
            "imageConfig": {"aspectRatio": aspect},
        },
    }
    return body


def call(model, key, body, attempts=4):
    url = ENDPOINT.format(model=model)
    delay = 3
    for attempt in range(1, attempts + 1):
        r = requests.post(url, params={"key": key}, json=body, timeout=180)
        if r.status_code == 200:
            return r.json()
        # Rate limits and transient 5xx are worth waiting out; anything else is
        # a real error and retrying it just burns quota.
        if r.status_code in (429, 500, 502, 503, 504) and attempt < attempts:
            print(f"  {r.status_code} — retrying in {delay}s", file=sys.stderr)
            time.sleep(delay)
            delay *= 2
            continue
        try:
            msg = r.json()["error"]["message"]
        except Exception:
            msg = r.text[:400]
        sys.exit(f"Gemini {r.status_code}: {msg}")
    sys.exit("gave up after retries")


def extract_image(response):
    for cand in response.get("candidates", []):
        for part in cand.get("content", {}).get("parts", []):
            inline = part.get("inlineData") or part.get("inline_data")
            if inline and inline.get("data"):
                return base64.b64decode(inline["data"])
    # The model sometimes answers with text instead of an image — usually a
    # safety refusal or a misread prompt. Surface it rather than saving nothing.
    texts = [p.get("text", "") for c in response.get("candidates", [])
             for p in c.get("content", {}).get("parts", [])]
    finish = [c.get("finishReason") for c in response.get("candidates", [])]
    sys.exit(f"no image in response. finish={finish} text={' '.join(texts)[:400]!r}")


def fit(image_bytes, size):
    """Centre-crops to the target aspect, then resizes. Never stretches."""
    w, h = size
    img = Image.open(io.BytesIO(image_bytes)).convert("RGB")
    src_ratio, dst_ratio = img.width / img.height, w / h
    if abs(src_ratio - dst_ratio) > 0.01:
        if src_ratio > dst_ratio:
            new_w = int(img.height * dst_ratio)
            left = (img.width - new_w) // 2
            img = img.crop((left, 0, left + new_w, img.height))
        else:
            new_h = int(img.width / dst_ratio)
            top = (img.height - new_h) // 2
            img = img.crop((0, top, img.width, top + new_h))
    return img.resize((w, h), Image.LANCZOS)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--prompt", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--size", default="1024x1024", help="WxH")
    ap.add_argument("--ref", help="reference image to edit from")
    ap.add_argument("--model", default="gemini-3-pro-image")
    ap.add_argument("--key-file")
    ap.add_argument("--raw", help="also save the untouched model output here")
    args = ap.parse_args()

    w, h = (int(v) for v in args.size.lower().split("x"))
    aspect = {1.0: "1:1", 16 / 9: "16:9", 9 / 16: "9:16", 4 / 3: "4:3", 3 / 4: "3:4"}
    ratio = w / h
    aspect_str = min(aspect.items(), key=lambda kv: abs(kv[0] - ratio))[1]

    key = load_key(args.key_file)
    body = build_request(args.prompt, args.ref, aspect_str)

    print(f"{args.model}  {aspect_str}  -> {args.out}" + (f"  (ref: {Path(args.ref).name})" if args.ref else ""))
    t0 = time.time()
    response = call(args.model, key, body)
    image_bytes = extract_image(response)
    if args.raw:
        Path(args.raw).parent.mkdir(parents=True, exist_ok=True)
        Path(args.raw).write_bytes(image_bytes)

    out = fit(image_bytes, (w, h))
    Path(args.out).parent.mkdir(parents=True, exist_ok=True)
    out.save(args.out, "PNG", optimize=True)
    kb = Path(args.out).stat().st_size // 1024
    print(f"  saved {w}x{h}  {kb} KB  in {time.time() - t0:.0f}s")


if __name__ == "__main__":
    main()
