#!/usr/bin/env python3
"""
Turns a generator's export into what ships: decimate, resample the attributes,
shrink the texture, repack.

    python3 tools/mesh.py anubis                   # the whole family, by name
    python3 tools/mesh.py <file.usdz> --inspect    # report only, change nothing
    python3 tools/mesh.py <file.usdz> --out <path> --tris 5000

The layout it works across:

    Art/Models/<asset>.usdz            the rigged Meshy export, untouched   (authoring source)
    Art/Models/<asset>_<clip>.usdz     one export per animation clip        (authoring source)
    Pantheon/Resources/Models/         what this writes, and what the app bundles

`Art/` is outside `Pantheon/`, which matters: the Xcode target is a
filesystem-synchronised group, so anything under `Pantheon/` is copied into the
app. Keeping a 23 MB source beside its 1.6 MB result would ship both.

Why this exists. Meshy ships ~200,000 triangles with a 2048 texture, which is
the right thing for an authoring source and the wrong thing to put in an app.
A Summoners War monster is 2,000-5,000 triangles with a single texture; at the
size these are drawn on a phone nothing above that is visible, and ten of them
on screen at 200k each is far beyond the frame budget. So the heavy export is
the source of truth and this produces what actually ships.

What it does, in order:

1. Reads the mesh, the skeleton binding and the primvars with Pixar's USD.
2. Collapses face-varying UVs to one per point. A generator mesh has a single
   UV island per vertex except at seams, and after an 80-97% reduction the
   seam error is far below a pixel.
3. Quadric-decimates to the triangle target.
4. Resamples every per-point attribute - UVs, joint indices, joint weights -
   from the nearest original point. Decimation moves vertices rather than only
   removing them, so an index map is not enough; nearest neighbour is the
   standard remap and holds at these ratios.
5. Drops face-varying normals. USD recomputes them, and a decimated mesh's
   original normals would be wrong anyway.
6. Removes any light the exporter added. `BattleSceneController` owns the
   lighting; a dome light inside a character file would fight it.
7. Downsamples the texture.
8. Repacks as .usdz with the skeleton, the animation and the materials intact,
   because only the mesh prim is touched.

The skeleton and its animation are never modified, so clips authored against
the source rig keep working against the decimated one.

Per-clip files are reduced harder than the base model (1,500 triangles, a
128-pixel texture). `ModelLibrary` opens them only to lift the animation out;
their geometry and texture are read once and discarded, so they need to be
valid, not pretty. Six of them at that size are about a megabyte.
"""

import argparse, shutil, sys, tempfile, zipfile
from pathlib import Path

import numpy as np
from PIL import Image
from pxr import Usd, UsdGeom, UsdSkel, UsdUtils, Sdf, Vt
import fast_simplification
from scipy.spatial import cKDTree

REPO = Path(__file__).resolve().parent.parent
SOURCE_DIR = REPO / "Art" / "Models"
BUNDLE_DIR = REPO / "Pantheon" / "Resources" / "Models"
LIGHT_TYPES = {"DomeLight", "DistantLight", "SphereLight", "RectLight", "DiskLight", "CylinderLight"}
IMAGE_SUFFIXES = (".png", ".jpg", ".jpeg")


def find_mesh(stage):
    for prim in stage.Traverse():
        if prim.GetTypeName() == "Mesh":
            return UsdGeom.Mesh(prim)
    return None


def triangulate(counts, indices):
    """Fan-triangulate, and return the source face-vertex slot of each corner
    so face-varying data can follow the triangles."""
    tris, slots = [], []
    o = 0
    for c in counts:
        for k in range(1, c - 1):
            tris.append((indices[o], indices[o + k], indices[o + k + 1]))
            slots.append((o, o + k, o + k + 1))
        o += c
    return np.array(tris, dtype=np.int64), np.array(slots, dtype=np.int64)


def facevarying_to_point(values, tris, slots, point_count, width):
    """One value per point, taken from that point's first corner."""
    out = np.zeros((point_count, width), dtype=np.float32)
    seen = np.zeros(point_count, dtype=bool)
    flat_pts, flat_slots = tris.reshape(-1), slots.reshape(-1)
    for p, s in zip(flat_pts, flat_slots):
        if not seen[p]:
            out[p] = values[s]
            seen[p] = True
    return out


def count_tris(stage):
    tris = 0
    for prim in stage.Traverse():
        if prim.GetTypeName() == "Mesh":
            counts = UsdGeom.Mesh(prim).GetFaceVertexCountsAttr().Get() or []
            tris += sum(max(0, c - 2) for c in counts)
    return tris


def report(stage, label):
    mesh = find_mesh(stage)
    tris = count_tris(stage)
    pts = len(mesh.GetPointsAttr().Get() or []) if mesh else 0
    print(f"  {label:10s} {tris:9,d} tris  {pts:8,d} points")
    return tris, pts


def process(src, target_tris, out_path, texture_size):
    stage = Usd.Stage.Open(str(src))
    mesh = find_mesh(stage)
    if mesh is None:
        sys.exit(f"no mesh in {src}")
    prim = mesh.GetPrim()
    pv_api = UsdGeom.PrimvarsAPI(prim)

    points = np.array(mesh.GetPointsAttr().Get(), dtype=np.float32)
    counts = np.array(mesh.GetFaceVertexCountsAttr().Get())
    indices = np.array(mesh.GetFaceVertexIndicesAttr().Get())
    tris, slots = triangulate(counts, indices)

    # --- per-point attributes to carry across -----------------------------
    carried = {}
    st_pv = pv_api.GetPrimvar("st")
    if st_pv and st_pv.HasValue():
        st = np.array(st_pv.Get(), dtype=np.float32)
        carried["st"] = (
            facevarying_to_point(st, tris, slots, len(points), 2)
            if st_pv.GetInterpolation() == UsdGeom.Tokens.faceVarying
            else st.reshape(len(points), -1)
        )

    skin = {}
    for name, dtype in (("skel:jointIndices", np.int32), ("skel:jointWeights", np.float32)):
        pv = pv_api.GetPrimvar(name)
        if pv and pv.HasValue():
            size = pv.GetElementSize()
            skin[name] = (np.array(pv.Get(), dtype=dtype).reshape(len(points), size), size)

    # --- decimate ---------------------------------------------------------
    reduction = max(0.0, 1.0 - target_tris / len(tris))
    new_points, new_tris = fast_simplification.simplify(points, tris.astype(np.int32), reduction)
    new_points = np.asarray(new_points, dtype=np.float32)
    new_tris = np.asarray(new_tris, dtype=np.int32)

    # --- resample attributes from the nearest original point --------------
    nearest = cKDTree(points).query(new_points, k=1)[1]

    mesh.GetPointsAttr().Set(Vt.Vec3fArray.FromNumpy(new_points))
    mesh.GetFaceVertexCountsAttr().Set(Vt.IntArray.FromNumpy(np.full(len(new_tris), 3, dtype=np.int32)))
    mesh.GetFaceVertexIndicesAttr().Set(Vt.IntArray.FromNumpy(new_tris.reshape(-1)))
    # Face-varying normals no longer match the topology, and a decimated mesh
    # wants recomputed ones anyway.
    mesh.GetNormalsAttr().Clear()
    mesh.SetNormalsInterpolation(UsdGeom.Tokens.vertex)
    mesh.GetExtentAttr().Set(UsdGeom.PointBased(prim).ComputeExtent(Vt.Vec3fArray.FromNumpy(new_points)))

    if "st" in carried:
        pv = pv_api.GetPrimvar("st")
        pv.Set(Vt.Vec2fArray.FromNumpy(carried["st"][nearest]))
        pv.SetInterpolation(UsdGeom.Tokens.vertex)
        pv.SetElementSize(1)

    for name, (values, size) in skin.items():
        pv = pv_api.GetPrimvar(name)
        remapped = values[nearest]
        if name.endswith("jointWeights"):
            # Renormalise: the nearest-neighbour copy is already normalised,
            # but guard against a source that was not.
            total = remapped.sum(axis=1, keepdims=True)
            remapped = np.divide(remapped, total, out=remapped, where=total > 1e-6)
            pv.Set(Vt.FloatArray.FromNumpy(remapped.reshape(-1).astype(np.float32)))
        else:
            pv.Set(Vt.IntArray.FromNumpy(remapped.reshape(-1).astype(np.int32)))
        pv.SetInterpolation(UsdGeom.Tokens.vertex)
        pv.SetElementSize(size)

    # --- drop the exporter's lights ---------------------------------------
    # Blender writes the world as a dome light with a tiny HDR beside the
    # textures. The stage supplies its own key, fill and ambient, and a light
    # riding along inside every character would add up across a 5v5.
    for light in [p for p in stage.Traverse() if p.GetTypeName() in LIGHT_TYPES]:
        stage.RemovePrim(light.GetPath())

    # --- write out --------------------------------------------------------
    work = Path(tempfile.mkdtemp())
    layer = work / "model.usdc"
    stage.GetRootLayer().Export(str(layer))

    # Carry the textures across, downsampled. Anything else the package holds
    # (an .hdr for the light just removed) is copied untouched, and the
    # packager only includes what the layer still references.
    with zipfile.ZipFile(src) as zf:
        for info in zf.infolist():
            if info.filename.lower().endswith((".usdc", ".usda", ".usd")):
                continue
            dest = work / info.filename
            dest.parent.mkdir(parents=True, exist_ok=True)
            if info.filename.lower().endswith(IMAGE_SUFFIXES):
                with zf.open(info) as f:
                    img = Image.open(f).convert("RGB")
                if max(img.size) > texture_size:
                    img.thumbnail((texture_size, texture_size), Image.LANCZOS)
                img.save(dest, "PNG", optimize=True)
            else:
                dest.write_bytes(zf.read(info))

    out_path.parent.mkdir(parents=True, exist_ok=True)
    if out_path.exists():
        out_path.unlink()
    UsdUtils.CreateNewUsdzPackage(Sdf.AssetPath(str(layer)), str(out_path))
    shutil.rmtree(work, ignore_errors=True)
    return len(new_tris), len(new_points)


def run_one(src, out, tris, texture):
    before = src.stat().st_size
    t, p = process(src, tris, out, texture)
    after = out.stat().st_size
    print(f"  {out.name:32s} {t:7,d} tris  {p:7,d} pts  {texture:4d}px  {before/1048576:6.1f} -> {after/1048576:5.1f} MB")
    return before, after


def run_family(name, args):
    base = SOURCE_DIR / f"{name}.usdz"
    if not base.exists():
        sys.exit(f"no authoring source at {base.relative_to(REPO)} - `python3 tools/meshy.py download {name}` puts it there")
    clips = sorted(p for p in SOURCE_DIR.glob(f"{name}_*.usdz") if p.stem != f"{name}_lod")
    print(f"{name}: {base.relative_to(REPO)} + {len(clips)} clip files -> {BUNDLE_DIR.relative_to(REPO)}/")
    report(Usd.Stage.Open(str(base)), "source")

    total_before, total_after = 0, 0
    b, a = run_one(base, BUNDLE_DIR / f"{name}.usdz", args.tris, args.texture)
    total_before, total_after = total_before + b, total_after + a
    if args.lod:
        _, a = run_one(base, BUNDLE_DIR / f"{name}_lod.usdz", args.lod, max(512, args.texture // 2))
        total_after += a
    for clip in clips:
        b, a = run_one(clip, BUNDLE_DIR / clip.name, args.clip_tris, args.clip_texture)
        total_before, total_after = total_before + b, total_after + a
    print(f"  {'total':32s} {'':>34s} {total_before/1048576:6.1f} -> {total_after/1048576:5.1f} MB")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("source", help="an asset name (whole family from Art/Models) or a .usdz path")
    ap.add_argument("--tris", type=int, default=5000, help="triangle target for the shipped model")
    ap.add_argument("--lod", type=int, default=1500, help="also emit <name>_lod at this target (0 = skip)")
    ap.add_argument("--texture", type=int, default=1024, help="max texture edge for the shipped model")
    ap.add_argument("--clip-tris", type=int, default=1500, help="triangle target for per-clip files")
    ap.add_argument("--clip-texture", type=int, default=128, help="max texture edge for per-clip files")
    ap.add_argument("--inspect", action="store_true", help="report and change nothing")
    ap.add_argument("--out", help="output path for a single file (default: <name>.usdz in the bundle folder)")
    args = ap.parse_args()

    if not args.source.lower().endswith((".usdz", ".usdc", ".usda", ".usd")):
        return run_family(args.source, args)

    src = Path(args.source)
    print(f"{src.name}   {src.stat().st_size/1048576:.1f} MB")
    report(Usd.Stage.Open(str(src)), "source")
    if args.inspect:
        return 0
    out = Path(args.out) if args.out else BUNDLE_DIR / src.name
    if out.resolve() == src.resolve():
        sys.exit("refusing to overwrite the authoring source; pass --out")
    run_one(src, out, args.tris, args.texture)
    if args.lod:
        run_one(src, out.with_name(out.stem + "_lod.usdz"), args.lod, max(512, args.texture // 2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
