"""The robe ring's ownership board (character.reweight_robe, run in memory on
the SHIPPED base): every vertex at the bind pose from the front, the right
side and the back, coloured by what owns it AFTER the pass —

  grey      the body (as rigged, untouched)
  green     the cape chain
  a colour  per robe sector (f orange, fl cyan, l blue, bl violet, b teal,
            br brown, r sky, fr salmon), by the chain that holds it most
  red       arm-held cloth ABOVE the hips, given to the spine
  magenta   a thing the hand keeps (a weapon, a shield: `_held_objects`)
  yellow    an arm still owns it below the hips, outside its own skin
            (what the pass left behind — should be a speck or nothing)
  navy      the arm's own skin below the hips (the hand)

One row per family, 300 px a view. A family NOT in character.ROBE_FAMILIES
is drawn as the pass would leave it only with --dry (the default is what
mesh.py would ship: a control must show no robe colour at all).

    python3 tools/robe_board.py heimdall pluto --dry --out board.jpg
    python3 tools/robe_board.py anhur atalanta ares diana sekhmet --out controls.jpg"""
import argparse, io, contextlib, sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import numpy as np  # noqa: E402
from PIL import Image, ImageDraw  # noqa: E402
import character  # noqa: E402

BUNDLE = Path(__file__).resolve().parents[1] / "Pantheon" / "Resources" / "Models"
# One colour per robe sector, none of them the flags' red, magenta, yellow,
# green or navy (a hue wheel put robe_fr on magenta and robe_f on red).
SECTOR_RGB = {"f": (250, 130, 20), "fl": (0, 200, 220), "l": (40, 90, 255), "bl": (140, 60, 220),
              "b": (0, 130, 110), "br": (150, 95, 40), "r": (110, 175, 255), "fr": (255, 150, 150)}
GREY, GREEN, RED, MAGENTA, YELLOW, NAVY = (150, 150, 150), (40, 170, 60), (220, 30, 30), (210, 40, 210), \
    (240, 200, 20), (30, 30, 120)


def colours(name, dry):
    char = character.read_usdz(BUNDLE / f"{name}.usdz")
    char.name = name
    before = char.joint_indices.copy(), char.joint_weights.copy()
    n0 = len(char.points)
    log = io.StringIO()
    n = 0
    if dry or name in character.ROBE_FAMILIES:
        with contextlib.redirect_stdout(log):
            n = character.reweight_robe(char)
    P = char.points.astype(np.float64)[:n0]
    leaf = [j.split("/")[-1] for j in char.joints]
    owner = char.joint_indices[np.arange(n0), np.argmax(char.joint_weights[:n0], axis=1)]
    owner0 = before[0][np.arange(n0), np.argmax(before[1], axis=1)]
    kind = [character._bone_kind(l) for l in leaf]
    armk = np.array([k in ("arm", "forearm") or k.startswith("hand") for k in kind])
    col = np.tile(np.array(GREY, np.uint8), (n0, 1))
    for i, l in enumerate(leaf):
        sel = owner == i
        if l.startswith("cape_"):
            col[sel] = GREEN
        elif l.startswith("robe_"):
            col[sel] = SECTOR_RGB.get(l.split("_")[1], (0, 0, 0))
    sets = getattr(char, "_robe_sets", None)
    hips = [i for i, l in enumerate(leaf) if l.lower() == "hips"][0]
    h = float(np.ptp(P[:, 1]))
    below = P[:, 1] < char.bind[hips][3, 1] - 0.02 * h
    _, skin, _ = character._arm_masks(char)
    skin = skin[:n0]
    if sets is not None:
        col[sets["spine"][:n0]] = RED
        col[sets["held"][:n0]] = MAGENTA
    col[armk[owner] & below & ~skin & ~(sets["held"][:n0] if sets is not None else False)] = YELLOW
    col[armk[owner] & below & skin] = NAVY
    counts = {}
    for i in np.unique(owner[armk[owner0]]):
        counts[leaf[i]] = int((owner[armk[owner0]] == i).sum())
    return P, col, n, log.getvalue(), counts


def panel(P, col, size=300):
    views = (("front", lambda p: p[:, 0], lambda p: p[:, 2]),
             ("right side", lambda p: -p[:, 2], lambda p: -p[:, 0]),
             ("back", lambda p: -p[:, 0], lambda p: -p[:, 2]))
    img = np.full((size, size * 3, 3), 246, np.uint8)
    lo, hi = P.min(0), P.max(0)
    s = (size - 24) / max(hi[1] - lo[1], 1e-6)
    for v, (_, uf, df) in enumerate(views):
        u, dep = uf(P), df(P)
        o = np.argsort(dep)                          # far first, near drawn over it
        x = (v * size + size / 2 + u[o] * s).astype(int)
        y = (size - 8 - (P[o, 1] - lo[1]) * s).astype(int)
        for dx in (0, 1):
            for dy in (0, 1):
                xx, yy = np.clip(x + dx, 0, size * 3 - 1), np.clip(y + dy, 0, size - 1)
                img[yy, xx] = col[o]
    return Image.fromarray(img)


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("names", nargs="+")
    ap.add_argument("--dry", action="store_true", help="run the pass whether or not the family is named")
    ap.add_argument("--out", default="robe_board.jpg")
    ap.add_argument("--size", type=int, default=300)
    args = ap.parse_args()
    rows = []
    for name in args.names:
        P, col, n, log, counts = colours(name, args.dry)
        img = panel(P, col, args.size)
        d = ImageDraw.Draw(img)
        sectors = next((l.strip()[len("robe: "):] for l in log.splitlines() if "robe: sectors" in l), "no ring")
        d.text((4, 2), f"{name}: {n:,} re-bound  (front | right side | back)", fill=(0, 0, 0))
        d.text((4, 14), sectors[:110], fill=(40, 40, 40))
        d.text((4, args.size - 14), "grey body  green cape  red arm-cloth->spine  magenta held  yellow LEFT on arm  navy hand",
               fill=(60, 60, 60))
        rows.append(img)
        print(f"{name}: {n:,} re-bound; {sectors}")
    W = max(r.width for r in rows)
    H = sum(r.height for r in rows)
    sheet = Image.new("RGB", (W, H), "white")
    y = 0
    for r in rows:
        sheet.paste(r, (0, y))
        y += r.height
    sheet.save(args.out, quality=85)
    print("->", args.out, sheet.size)


if __name__ == "__main__":
    main()
