#!/usr/bin/env python3
"""
Ships a stage prop: a Meshy text-to-3D export (no rig) becomes a canonical,
decimated .usdz in the bundle, standing on the origin at the height the stage
wants.

    python3 tools/prop.py prop_obelisk --height 7            # Art/Models/prop_obelisk_refine.usdz -> Pantheon/Resources/Models/prop_obelisk.usdz
    python3 tools/prop.py prop_brazier --height 1.4 --tris 2500

The reader, canonicaliser, decimator and writer are tools/character.py's; a
prop is a character with no joints. `--yaw` turns it about Y in degrees when
the generator's idea of the front is not the game's (+Z faces the camera).
"""
import argparse, math, sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
import character  # noqa: E402

REPO = Path(__file__).resolve().parents[1]
ART = REPO / "Art" / "Models"
BUNDLE = REPO / "Pantheon" / "Resources" / "Models"


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("asset", help="manifest name, e.g. prop_obelisk")
    ap.add_argument("--height", type=float, required=True, help="metres tall in the game")
    ap.add_argument("--tris", type=int, default=3000)
    ap.add_argument("--texture", type=int, default=1024)
    ap.add_argument("--yaw", type=float, default=0, help="degrees about Y after canonicalising")
    ap.add_argument("--source", help="a .glb to read instead of Art/Models/<asset>_refine.glb")
    a = ap.parse_args()

    src = Path(a.source) if a.source else None
    if src is None:
        for cand in (ART / f"{a.asset}_refine.usdz", ART / f"{a.asset}_refine.glb", ART / f"{a.asset}.usdz",
                     ART / f"{a.asset}.glb", ART / f"{a.asset}_preview.usdz", ART / f"{a.asset}_preview.glb"):
            if cand.exists():
                src = cand
                break
    if src is None or not src.exists():
        sys.exit(f"no export for {a.asset} in {ART.relative_to(REPO)} - `python3 tools/meshy.py download {a.asset} --include-unrigged`")

    print(f"{a.asset}: {src.relative_to(REPO) if src.is_relative_to(REPO) else src}  ->  {BUNDLE.relative_to(REPO)}/{a.asset}.usdz   {a.height} m")
    char = character.read(src)
    character.describe(char)
    print("  canonical:")
    character.canonicalise(char, height=a.height, lock_root=False)
    if a.yaw:
        r = math.radians(a.yaw)
        rot = np.array([[math.cos(r), 0, math.sin(r)], [0, 1, 0], [-math.sin(r), 0, math.cos(r)]])
        character.apply_similarity(char, rot, 1.0, np.zeros(3))
        print(f"    turned {a.yaw:+.0f}° about Y")
    char.anim = None
    char.name = a.asset
    character.decimate(char, a.tris, a.texture)
    BUNDLE.mkdir(parents=True, exist_ok=True)
    out = BUNDLE / f"{a.asset}.usdz"
    size = character.write_usdz(char, out)
    print(f"  -> {out.relative_to(REPO)}   {char.tris:,} tris  {size / 1048576:.2f} MB")
    facts = character.verify(out, expect_height=a.height)
    return 1 if facts["problems"] else 0


if __name__ == "__main__":
    sys.exit(main())
