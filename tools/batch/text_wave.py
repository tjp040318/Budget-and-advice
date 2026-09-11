#!/usr/bin/env python3
"""Launches a wave of Meshy characters from their WRITTEN descriptions (text-to-3D)
when the Gemini concepts they were meant to be built from cannot be painted yet.

    python3 tools/batch/text_wave.py tools/batch/wave4.txt tools/batch/beasts4.txt --floor 2000

Each asset in a wave list (asset:concept:height:palette:kit:family) or a beast
list (asset:concept:height:palette) takes its description from the `gen <key>
"..."` / `dragon <key> "..."` line of tools/batch/concepts_batch4.sh — the same
words the concept would have been painted from — fitted into Meshy's 600
characters after a pose prefix, and runs `meshy.py generate` in the background:
preview, refine, rig and the kit's clips for a character (20 + 10 + 5 + 7 x 3 =
56 credits), preview and refine only for a beast (30; a four-clawed dragon will
not rig). An asset with a manifest is skipped, so the night routine's
wave_run.sh/beast_wave.sh find nothing to relaunch and ship_wave.sh ships these.
The balance is read before every launch and the wave stops at the floor, what
the launched ones still owe counted in.
"""
import argparse, re, subprocess, sys, time, os
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent.parent
os.chdir(REPO)
PREFIX = ("Full body game character standing in a symmetrical A-pose, arms lowered and held "
          "away from the body, legs straight and shoulder-width apart, facing forward: ")
BEAST_PREFIX = ("Full body creature, a serpentine Chinese dragon standing on four clawed legs in a "
                "symmetrical pose, head up, body straight, no wings: ")
SUFFIX = " Plain empty background, no base."
NEGATIVE = ("base, pedestal, plinth, stand, background, scenery, text, watermark, two characters, "
            "extra limbs, crossed arms, arms raised, arms in front of the body, weapon held out, "
            "floating, cape flying, long dress hiding the feet, realistic proportions, photorealism")
BEAST_NEGATIVE = "wings, coiled body, base, pedestal, background, scenery, text, watermark, two creatures, photorealism"
LIMIT = 600

def descriptions():
    src = (REPO / "tools/batch/concepts_batch4.sh").read_text()
    out = {}
    for kind, key, desc in re.findall(r'^(gen|dragon) (\w+) "(.*)"$', src, re.M):
        # The painter's framing ("The Roman god of X as an original cartoon character:") is
        # for Gemini; the modeller gets the visual sentence after the colon.
        body = desc.split(":", 1)[1].strip() if ":" in desc[:120] else desc
        out[key] = (kind, body)
    return out

def fit(prefix, body):
    room = LIMIT - len(prefix) - len(SUFFIX)
    if len(body) <= room:
        return prefix + body + SUFFIX
    cut = body[:room]
    stop = max(cut.rfind(". "), cut.rfind(", "))
    cut = cut[:stop + 1] if stop > room // 2 else cut
    return prefix + cut.rstrip(", ") + "." + SUFFIX

def balance():
    r = subprocess.run([sys.executable, "tools/meshy.py", "balance"], capture_output=True, text=True)
    try:
        return int(r.stdout.strip().splitlines()[-1])
    except Exception:
        return None

def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("lists", nargs="+", help="wave lists (6 fields) and/or beast lists (4 fields)")
    ap.add_argument("--floor", type=int, default=2000)
    ap.add_argument("--dry-run", action="store_true", help="print the prompts and stop")
    a = ap.parse_args()
    descs = descriptions()
    logs = Path("/tmp/pantheon-batch"); logs.mkdir(exist_ok=True)
    launched, owed = 0, 0
    for path in a.lists:
        for line in Path(path).read_text().splitlines():
            if not line.strip() or line.startswith("#"):
                continue
            fields = line.split(":")
            asset, height, palette = fields[0], fields[2], fields[3]
            kit = fields[4] if len(fields) > 4 else None
            beast = len(fields) <= 4
            if asset not in descs:
                print(f"no description for {asset} in concepts_batch4.sh"); continue
            kind, body = descs[asset]
            prompt = fit(BEAST_PREFIX if beast else PREFIX, body + f" Palette {palette}." if "Palette" not in body else body)
            if a.dry_run:
                print(f"{asset} ({len(prompt)} chars, {'beast' if beast else kit}):\n  {prompt}\n"); continue
            if (REPO / f"Art/Models/{asset}.meshy.json").exists():
                print(f"have {asset} (manifest exists)"); continue
            now, later = (20, 10) if beast else (20, 36)
            bal = balance()
            need = a.floor + now + later + owed + 100
            if bal is None or bal < need:
                print(f"STOP before {asset}: balance {bal}, need {need} (floor {a.floor} + this one + what the {launched} launched still owe)"); break
            cmd = [sys.executable, "tools/meshy.py", "generate", asset, "--prompt", prompt, "--negative",
                   BEAST_NEGATIVE if beast else NEGATIVE, "--height", height]
            if beast:
                cmd += ["--until", "refine"]
            else:
                cmd += ["--clips", kit or "blade"]
            with open(logs / f"meshy_{asset}.log", "w") as log:
                subprocess.Popen(cmd, stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
            launched += 1; owed += later
            print(f"launched {asset} ({'beast' if beast else kit}, {len(prompt)} chars) balance {bal}")
            time.sleep(20)
    print(f"text_wave: launched {launched}")

if __name__ == "__main__":
    main()
