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

`--split-lid F` cuts a chest in two at F of its height: every triangle whose
centre lies above the cut becomes `<asset>_lid.usdz`, with its origin moved to
the lid's back-bottom edge so the game can hinge it there, and the rest ships
as the box under the asset's own name. The reward chest is the reason: one
Meshy mesh at 30 credits, two files, and a lid that really opens.
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
    ap.add_argument("--as", dest="ship_as", help="bundle name to ship under, e.g. serpopard for enemy_serpopard")
    ap.add_argument("--split-lid", type=float, help="fraction of the height at which the lid parts from the box")
    a = ap.parse_args()

    src = Path(a.source) if a.source else None
    if src is None:
        for cand in (ART / f"{a.asset}_refine.usdz", ART / f"{a.asset}_refine.glb", ART / f"{a.asset}.usdz",
                     ART / f"{a.asset}.glb", ART / f"{a.asset}_image.usdz", ART / f"{a.asset}_image.glb",
                     ART / f"{a.asset}_preview.usdz", ART / f"{a.asset}_preview.glb"):
            if cand.exists():
                src = cand
                break
    if src is None or not src.exists():
        sys.exit(f"no export for {a.asset} in {ART.relative_to(REPO)} - `python3 tools/meshy.py download {a.asset} --include-unrigged`")

    name = a.ship_as or a.asset
    print(f"{a.asset}: {src.relative_to(REPO) if src.is_relative_to(REPO) else src}  ->  {BUNDLE.relative_to(REPO)}/{name}.usdz   {a.height} m")
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
    char.name = name
    character.decimate(char, a.tris, a.texture)
    BUNDLE.mkdir(parents=True, exist_ok=True)
    if a.split_lid is not None:
        return ship_split(char, name, a.split_lid, a.height)
    out = BUNDLE / f"{name}.usdz"
    size = character.write_usdz(char, out)
    print(f"  -> {out.relative_to(REPO)}   {char.tris:,} tris  {size / 1048576:.2f} MB")
    facts = character.verify(out, expect_height=a.height)
    return 1 if facts["problems"] else 0


def part(char, keep, name):
    """A copy of `char` holding only the faces in `keep`, re-indexed."""
    import copy
    faces = char.faces[keep]
    used = np.unique(faces)
    remap = np.full(len(char.points), -1, dtype=np.int64)
    remap[used] = np.arange(len(used))
    piece = copy.copy(char)
    piece.name = name
    piece.points = char.points[used].copy()
    piece.faces = remap[faces].astype(np.int32)
    piece.uvs = None if char.uvs is None else char.uvs[used].copy()
    piece.joint_indices = None
    piece.joint_weights = None
    piece.joints, piece.parents = [], np.zeros(0, dtype=np.int64)
    piece.bind = np.zeros((0, 4, 4)); piece.rest_local = np.zeros((0, 4, 4))
    return piece


def ship_split(char, name, fraction, height):
    """The box under `name`, the lid under `name_lid` with its origin on the
    hinge: the middle of the lid's back-bottom edge (−Z is the back, the game's
    camera looks at +Z). Rotating the lid node about X by a negative angle lifts
    its front edge, which is what opening looks like."""
    seam = fraction * height
    centres = char.points[char.faces].mean(axis=1)
    lid_faces = centres[:, 1] >= seam
    box = part(char, ~lid_faces, name)
    lid = part(char, lid_faces, f"{name}_lid")
    lo, hi = character.bounds(lid.points)
    hinge = np.array([0.0, lo[1], lo[2]], dtype=np.float32)
    lid.points = lid.points - hinge
    print(f"  split at {seam:.3f} m: box {len(box.faces):,} tris, lid {len(lid.faces):,} tris, "
          f"hinge at (0, {hinge[1]:.3f}, {hinge[2]:.3f})")
    problems = False
    for piece in (box, lid):
        out = BUNDLE / f"{piece.name}.usdz"
        size = character.write_usdz(piece, out)
        print(f"  -> {out.relative_to(REPO)}   {piece.tris:,} tris  {size / 1048576:.2f} MB")
        facts = character.verify(out, quiet=True)
        problems = problems or bool(facts["problems"])
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
