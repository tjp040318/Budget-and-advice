#!/usr/bin/env python3
"""
Turns a generator's export into what ships: canonical, reduced, verified.

    python3 tools/mesh.py anubis                      # the whole family, by name
    python3 tools/mesh.py anubis --height 2.05        # override the height read from UnitDatabase.swift
    python3 tools/mesh.py <file.usdz|.glb> --inspect  # what is actually in a file
    python3 tools/mesh.py <file.glb> --out x.usdz     # one file, full resolution

The layout it works across:

    Art/Models/<asset>.usdz|.glb           the rigged export, untouched          (authoring source)
    Art/Models/<asset>_<clip>.usdz|.glb    one export per animation clip        (authoring source)
    Pantheon/Resources/Models/             what this writes, and what the app bundles

`Art/` is outside `Pantheon/`, which matters: the Xcode target is a
filesystem-synchronised group, so anything under `Pantheon/` is copied into the
app. Keeping a 23 MB source beside its 1.6 MB result would ship both.

What happens to each file, in order (tools/character.py does the work and
prints what it measures):

1. Read. Blender's USDZ (Meshy's web app) or Meshy's API GLB, into one model:
   points, faces, UVs, skin weights, skeleton, animation, textures. Every
   transform the exporter left on nodes - the armature's centimetre scale, the
   mesh's 90-degree tilt, the geomBindTransform - is baked out here.
2. Canonicalise. Y-up, metres, feet on the origin, centred, facing +Z (read off
   the toe joints), scaled to the height the roster declares; rest pose = bind
   pose; root joints locked horizontally to the slot; four influences per
   vertex, weights summing to one. The base model decides the transform and
   every clip file gets the same one, so the animations stay in step.
3. Decimate: 5,000 triangles for the shipped model, 1,500 for the `_lod` and
   for every clip file, whose geometry the game reads once and discards.
   UVs and skin weights follow by nearest original vertex.
4. Write, in the prim layout SceneKit has already been seen to load, with
   computed normals and the textures downsampled.
5. Verify: skin the written file again in numpy at the bind pose and at three
   animated frames, and print the bounds. A model that will explode on the
   phone explodes here first.
"""

import argparse, copy, re, sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import character  # noqa: E402

REPO = Path(__file__).resolve().parent.parent
SOURCE_DIR = REPO / "Art" / "Models"
BUNDLE_DIR = REPO / "Pantheon" / "Resources" / "Models"
ROSTER = REPO / "Pantheon" / "Core" / "Data" / "UnitDatabase.swift"


def roster_height(asset):
    """ModelSpec.height for an assetName, straight out of UnitDatabase.swift, so
    the file and the code cannot disagree about how tall a character is."""
    if not ROSTER.exists():
        return None
    src = ROSTER.read_text()
    m = re.search(r'assetName:\s*"%s"(.{0,400}?)height:\s*([0-9.]+)' % re.escape(asset), src, re.S)
    return float(m.group(2)) if m else None


def source_for(name):
    for ext in (".usdz", ".glb"):
        p = SOURCE_DIR / f"{name}{ext}"
        if p.exists():
            return p
    return None


def clip_sources(name):
    out = {}
    for p in sorted(SOURCE_DIR.glob(f"{name}_*.*")):
        if p.suffix.lower() not in (".usdz", ".glb") or p.stem.endswith("_lod"):
            continue
        out.setdefault(p.stem, p)          # .usdz wins over .glb for the same clip
    return list(out.values())


def build(char, out, tris, texture, expect_height):
    work = copy.deepcopy(char)
    character.decimate(work, tris, texture)
    character.ground_animation(work)
    size = character.write_usdz(work, out)
    print(f"  -> {out.relative_to(REPO)}   {work.tris:,} tris  {texture}px  {size / 1048576:.2f} MB")
    facts = character.verify(out, expect_height=expect_height)
    return facts


def run_family(name, args):
    src = source_for(name)
    if src is None:
        sys.exit(f"no {name}.usdz or {name}.glb in {SOURCE_DIR.relative_to(REPO)} - "
                 f"`python3 tools/meshy.py download {name}` puts one there")
    height = args.height or roster_height(name)
    if height is None:
        height = 1.9
        print(f"no ModelSpec for '{name}' in UnitDatabase.swift; assuming {height} m (pass --height)")
    print(f"{name}: {src.relative_to(REPO)}  ->  {BUNDLE_DIR.relative_to(REPO)}/   target height {height} m")

    print(f"  reading {src.name}")
    base = character.read(src)
    character.describe(base)
    print("  canonical:")
    transform = character.canonicalise(base, height=height, lock_root=not args.keep_root_motion)
    if base.anim and not args.keep_base_animation:
        base.anim = None     # the clips carry the motion; the base is the bind pose
    problems = []
    problems += build(base, BUNDLE_DIR / f"{name}.usdz", args.tris, args.texture, height)["problems"]
    if args.lod:
        problems += build(base, BUNDLE_DIR / f"{name}_lod.usdz", args.lod, max(512, args.texture // 2), height)["problems"]

    for clip in clip_sources(name):
        print(f"\n  reading {clip.name}")
        c = character.read(clip)
        character.describe(c)
        if len(c.joints) != len(base.joints) or c.joints != base.joints:
            print(f"    PROBLEM: joint list differs from the base model; the animation will not retarget")
            problems.append(f"{clip.name}: different skeleton")
        print("  canonical (base model's transform):")
        character.canonicalise(c, transform=transform, lock_root=not args.keep_root_motion)
        dev = abs(c.bind - base.bind).max() if len(c.bind) == len(base.bind) else float("inf")
        if dev > 1e-3:
            print(f"    PROBLEM: bind pose differs from the base by {dev:.4f}")
            problems.append(f"{clip.name}: bind pose differs")
        if c.anim is None:
            print("    PROBLEM: no animation in a clip file")
            problems.append(f"{clip.name}: no animation")
        problems += build(c, BUNDLE_DIR / f"{clip.stem}.usdz", args.clip_tris, args.clip_texture, height)["problems"]

    total = sum(p.stat().st_size for p in BUNDLE_DIR.glob(f"{name}*.usdz"))
    print(f"\n  {name}: {total / 1048576:.1f} MB in the bundle folder")
    if problems:
        print(f"  {len(problems)} problem(s):")
        for p in problems:
            print(f"    - {p}")
        return 1
    print("  every file verified clean")
    return 0


def inspect(path):
    print(f"{path}")
    char = character.read(path)
    character.describe(char)
    print("  would canonicalise as:")
    probe = copy.deepcopy(char)
    character.canonicalise(probe, height=None)
    return 0


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("source", help="an asset name (whole family from Art/Models) or a .usdz/.glb path")
    ap.add_argument("--height", type=float, help="metres; default is ModelSpec.height from UnitDatabase.swift")
    ap.add_argument("--tris", type=int, default=5000, help="triangle target for the shipped model")
    ap.add_argument("--lod", type=int, default=1500, help="also emit <name>_lod at this target (0 = skip)")
    ap.add_argument("--texture", type=int, default=1024, help="max texture edge for the shipped model")
    ap.add_argument("--clip-tris", type=int, default=1500, help="triangle target for per-clip files")
    ap.add_argument("--clip-texture", type=int, default=128, help="max texture edge for per-clip files")
    ap.add_argument("--keep-root-motion", action="store_true", help="keep horizontal root motion in clips")
    ap.add_argument("--keep-base-animation", action="store_true", help="keep whatever clip the base export carries")
    ap.add_argument("--inspect", action="store_true", help="report on a file and change nothing")
    ap.add_argument("--out", help="output path for a single file (default: full resolution, beside the source)")
    args = ap.parse_args()

    if not args.source.lower().endswith((".usdz", ".glb")):
        return run_family(args.source, args)
    src = Path(args.source)
    if args.inspect:
        return inspect(src)
    char = character.read(src)
    character.describe(char)
    character.canonicalise(char, height=args.height or roster_height(char.name) or 1.9,
                           lock_root=not args.keep_root_motion)
    out = Path(args.out) if args.out else src.with_name(src.stem + ".canonical.usdz")
    size = character.write_usdz(char, out)
    print(f"  -> {out}   {char.tris:,} tris  {size / 1048576:.2f} MB")
    return 1 if character.verify(out)["problems"] else 0


if __name__ == "__main__":
    sys.exit(main())
