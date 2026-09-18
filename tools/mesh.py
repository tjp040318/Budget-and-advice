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
3. Ground each clip on the full mesh (the median frame's lowest point goes
   to y = 0), then decimate: 9,000 triangles for the shipped model, 3,500
   for the `_lod` and 1,500 for every clip file, whose geometry the game
   reads once and discards. MeshLab's quadric edge collapse with texture
   does it, so the UVs go through the reduction and every seam stays a
   seam; skin weights follow by nearest original vertex. (Copying the
   nearest vertex's UV as well, as the first version did, smeared the atlas
   across the whole body.) The clip files are grounded and measured BEFORE
   their reduction: at 1,500 triangles a small shell can vanish outright
   (Diana's boots did, and the carrier's lowest point rose 17 cm), so a
   clip grounded on the reduced mesh would sink the figure into the floor,
   and a height check on it is a check of nothing.
4. Write, in the prim layout SceneKit has already been seen to load, with
   computed normals and the textures downsampled.
5. Verify: skin the written file again in numpy at the bind pose and at three
   animated frames, and print the bounds. A model that will explode on the
   phone explodes here first.
"""

import argparse, copy, io, re, sys

from PIL import Image
from pathlib import Path

import numpy as np

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


# The clips the game plays (AnimationClip's raw values), the only stems a
# family's clip file may carry after its name.
CLIP_NAMES = {"idle", "idle_combat", "attack_basic", "attack_heavy", "cast_loop", "cast_release",
              "ultimate", "hit_react", "death", "victory", "summon_reveal", "walk"}


def clip_sources(name):
    out = {}
    for p in sorted(SOURCE_DIR.glob(f"{name}_*.*")):
        if p.suffix.lower() not in (".usdz", ".glb"):
            continue
        # `download --include-unrigged` leaves the unrigged stages beside the
        # clips as <asset>_image / _preview / _refine; they carry no skeleton.
        if p.stem.endswith(("_lod", "_image", "_preview", "_refine")):
            continue
        # Another family whose name starts with this one — `ra_awakened` and
        # its clips beside `ra` (2026-09-17: three families read their new
        # awakened forms' files as their own clips and failed the bind check).
        # A clip is <name>_<clip> where <clip> is a clip the game knows.
        if p.stem[len(name) + 1:] not in CLIP_NAMES:
            continue
        out.setdefault(p.stem, p)          # .usdz wins over .glb for the same clip
    return list(out.values())


def build(char, out, tris, texture, expect_height, carrier=False, grade=None):
    """Writes one bundle file from a canonical model and verifies it.
    `carrier` marks a per-clip file: its 1,500-triangle mesh only carries
    the skeleton and the clip (the game reads the mesh once and discards
    it), so the height and feet are measured on the full mesh before the
    reduction, and the clip is grounded on the full mesh too. A reduction
    that steep can collapse a small shell entirely - Diana's boots went,
    and her carrier's lowest point rose 17 cm - and a clip grounded on
    that carrier would have sunk her that far into the floor."""
    work = copy.deepcopy(char)
    character.ground_animation(work)
    lo, hi = character.bounds(work.points.astype(np.float64))
    character.decimate(work, tris, texture, grade=grade)
    size = character.write_usdz(work, out)
    print(f"  -> {out.relative_to(REPO)}   {work.tris:,} tris  {texture}px  {size / 1048576:.2f} MB")
    facts = character.verify(out, expect_height=None if carrier else expect_height, check_bounds=not carrier)
    if carrier:
        height = hi[1] - lo[1]
        if expect_height and abs(height - expect_height) > 0.02 * expect_height:
            facts["problems"].append(f"source height {height:.3f} != {expect_height}")
        if abs(lo[1]) > 0.01:
            facts["problems"].append(f"source feet at y={lo[1]:.3f}")
        for prob in facts["problems"]:
            if prob.startswith("source "):
                print("    PROBLEM: " + prob)
    return facts


def merge_material_maps(base, name, explicit=None):
    """Takes the metallic-roughness and normal maps from the generator's
    textured stage file when the rigged export has none.

    Meshy's rigged and animated GLBs carry the base colour alone; the maps
    are in the refine (text-to-3D) or image (image-to-3D) stage's own
    model, which `meshy.py download` saves as `<asset>_refine.glb` or
    `<asset>_image.glb` since 2026-09-17 (the props' `_refine.usdz` carry
    them too). The rig keeps the atlas, so a map from that file fits the
    rigged mesh's UVs (Zeus: 43,070 vertices before the rig, 43,152 after,
    the same layout). A normal map that is nearly flat — Meshy puts the
    relief in the mesh; the text-to-3D Zeus's measured 6/255 on its
    busiest channel — is left out below 8/255, since it would cost the
    bundle two megabytes and show nothing."""
    have = {t.role for t in base.textures}
    if "metallic_roughness" in have or ("roughness" in have and "metallic" in have):
        return
    candidates = [Path(explicit)] if explicit else [
        SOURCE_DIR / f"{name}_{stage}.{ext}" for stage in ("image", "refine") for ext in ("glb", "usdz")
    ]
    sibling = next((c for c in candidates if c.exists()), None)
    if sibling is None:
        return
    print(f"  material maps from {sibling.name}")
    try:
        textured = character.read(sibling)
    except Exception as e:      # noqa: BLE001 - a stage file that will not read is a note, not a failure
        print(f"    could not read it ({e}); shipping the base colour alone")
        return
    for tex in textured.textures:
        if tex.role in have or tex.role not in ("metallic_roughness", "roughness", "metallic", "normal"):
            continue
        if tex.role == "normal":
            arr = np.asarray(Image.open(io.BytesIO(tex.data)).convert("RGB"), dtype=np.float32)
            relief = float(arr.reshape(-1, 3).std(axis=0).max())
            if relief < 8.0:
                print(f"    normal map is nearly flat (std {relief:.1f}/255); left out")
                continue
        base.textures.append(tex)
        have.add(tex.role)
        print(f"    + {tex.role} ({tex.size[0]}x{tex.size[1]} {tex.ext})")


def run_family(name, args):
    src = source_for(name)
    if src is None:
        sys.exit(f"no {name}.usdz or {name}.glb in {SOURCE_DIR.relative_to(REPO)} - "
                 f"`python3 tools/meshy.py download {name}` puts one there")
    # A concept-first remake is generated under another asset name
    # (`sekhmet_v2`) and ships under the roster's (`--as sekhmet`), so the
    # game's ModelSpec never changes.
    out_name = args.as_name or name
    height = args.height or roster_height(out_name)
    if height is None:
        height = 1.9
        print(f"no ModelSpec for '{out_name}' in UnitDatabase.swift; assuming {height} m (pass --height)")
    print(f"{name}: {src.relative_to(REPO)}  ->  {BUNDLE_DIR.relative_to(REPO)}/{out_name}*   target height {height} m")

    print(f"  reading {src.name}")
    base = character.read(src)
    character.describe(base)
    merge_material_maps(base, name, args.maps_from)
    print("  canonical:")
    transform = character.canonicalise(base, height=height, lock_root=not args.keep_root_motion)
    if base.anim and not args.keep_base_animation:
        base.anim = None     # the clips carry the motion; the base is the bind pose
    # The serious proportions (2026-09-17): head, hands and feet scaled at
    # their joints and baked, the same on every clip carrier below.
    scales = character.PROPORTIONS[args.proportions] if args.proportions else None
    fit = character.reproportion(base, scales, height=height) if scales else None
    # A cape bound to the arms and a shin by the auto-rig is re-bound to the
    # spine (2026-09-18); the winged and tailed families are left alone.
    if not args.no_cape and not any(k in out_name.lower() for k in character.CAPE_EXCLUDE):
        character.reweight_cape(base)
    problems = []
    base.name = out_name
    only = {c.strip() for c in args.only_clips.split(",") if c.strip()} if args.only_clips else None
    if only is None:
        problems += build(base, BUNDLE_DIR / f"{out_name}.usdz", args.tris, args.texture, height, grade=args.grade)["problems"]
        if args.lod:
            # The LOD's texture was always half the base's (1,024 for 2,048)
            # until 2026-09-17, when the fight — which draws the LOD and
            # nothing else — was measured against the file that was paid
            # for; --lod-texture 2048 keeps the painting whole.
            lod_texture = args.lod_texture or max(512, args.texture // 2)
            problems += build(base, BUNDLE_DIR / f"{out_name}_lod.usdz", args.lod, lod_texture, height, grade=args.grade)["problems"]
    else:
        # One clip re-shipped on its own - a bespoke motion replacing a preset
        # - leaves the base, the LOD and the other clips' files untouched, so
        # the change in the bundle is the one file. The base is still read
        # and canonicalised, because the clip is retargeted through its
        # transform and checked against its bind pose.
        print(f"  shipping only: {', '.join(sorted(only))}")

    clips = {}
    for clip in clip_sources(name):
        if args.no_clips:
            # A budget change to the base and the LOD alone: the clip files
            # are 1,500-triangle carriers whose content does not depend on
            # the base's budget, and rewriting them would only churn the
            # bundle.
            break
        if only is not None and clip.stem[len(name) + 1:] not in only:
            continue
        print(f"\n  reading {clip.name}")
        c = character.read(clip)
        character.describe(c)
        if len(c.joints) != len(base.joints) or c.joints != base.joints:
            print(f"    PROBLEM: joint list differs from the base model; the animation will not retarget")
            problems.append(f"{clip.name}: different skeleton")
        print("  canonical (base model's transform):")
        character.canonicalise(c, transform=transform, lock_root=not args.keep_root_motion)
        if scales:
            character.reproportion(c, scales, fit=fit)
        dev = abs(c.bind - base.bind).max() if len(c.bind) == len(base.bind) else float("inf")
        if dev > 1e-3:
            print(f"    PROBLEM: bind pose differs from the base by {dev:.4f}")
            problems.append(f"{clip.name}: bind pose differs")
        if c.anim is None:
            print("    PROBLEM: no animation in a clip file")
            problems.append(f"{clip.name}: no animation")
        clips[clip.stem[len(name) + 1:]] = c

    # A hit reaction is a flinch. If the exported one is a knock-up or a
    # knockdown, ship a synthesised flinch built from the combat idle instead;
    # the export stays in Art/Models for the day a real flinch replaces it.
    hit = clips.get("hit_react")
    if args.no_clips:
        hit = None
    if only is not None and only - set(clips):
        sys.exit(f"no source for clip(s) {', '.join(sorted(only - set(clips)))} beside {src.name}")
    if hit is not None and not args.keep_hit_react and character.looks_like_a_fall(hit):
        source = clips.get("idle_combat") or clips.get("idle") or base
        print(f"\n  hit_react: the exported clip is a knock-up or knockdown; "
              f"synthesising a 0.45 s flinch from {'the combat idle' if source is not base else 'the bind pose'} instead "
              f"(--keep-hit-react ships the export)")
        clips["hit_react"] = character.synthesize_flinch(source)

    for clip_name, c in clips.items():
        c.name = out_name
        print(f"\n  building {out_name}_{clip_name}")
        problems += build(c, BUNDLE_DIR / f"{out_name}_{clip_name}.usdz", args.clip_tris, args.clip_texture, height,
                          carrier=True)["problems"]

    total = sum(p.stat().st_size for p in BUNDLE_DIR.glob(f"{out_name}*.usdz"))
    print(f"\n  {out_name}: {total / 1048576:.1f} MB in the bundle folder")
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
    ap.add_argument("--as", dest="as_name", help="ship under this asset name (a remake generated as <name>_v2 ships as <name>)")
    ap.add_argument("--tris", type=int, default=9000, help="triangle target for the shipped model")
    ap.add_argument("--lod", type=int, default=3500, help="also emit <name>_lod at this target (0 = skip)")
    ap.add_argument("--texture", type=int, default=2048, help="max texture edge for the shipped model")
    ap.add_argument("--lod-texture", type=int, default=0, help="max texture edge for the LOD (default: half of --texture, 512 at least)")
    ap.add_argument("--no-clips", action="store_true", help="ship the base and the LOD only; leave the clip files as they are")
    ap.add_argument("--proportions", choices=sorted(character.PROPORTIONS), help="scale the head, hands and feet at their joints and bake it (character.PROPORTIONS)")
    ap.add_argument("--grade", choices=sorted(character.GRADES), help="a colour grade on the textures at shipping (character.GRADES; gold: olive to burnished gold, magenta runes to ember)")
    ap.add_argument("--no-cape", action="store_true", help="skip the cape re-bind (character.reweight_cape)")
    ap.add_argument("--maps-from", help="a textured stage file (.glb/.usdz) to take the metallic-roughness and normal maps from; "
                                        "default: <name>_image or <name>_refine beside the source")
    ap.add_argument("--clip-tris", type=int, default=1500, help="triangle target for per-clip files")
    ap.add_argument("--clip-texture", type=int, default=128, help="max texture edge for per-clip files")
    ap.add_argument("--keep-root-motion", action="store_true", help="keep horizontal root motion in clips")
    ap.add_argument("--keep-base-animation", action="store_true", help="keep whatever clip the base export carries")
    ap.add_argument("--only-clips", help="ship just these clips (comma list, e.g. ultimate) and leave the rest of the family's files as they are")
    ap.add_argument("--keep-hit-react", action="store_true",
                    help="ship the exported hit_react even when it is a knock-up or knockdown")
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
