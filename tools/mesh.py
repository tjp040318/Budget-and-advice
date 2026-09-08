#!/usr/bin/env python3
"""
Turns a generator's export into a game-ready model: decimate, resample the
attributes, shrink the texture, repack.

    python3 tools/mesh.py Pantheon/Resources/Models/anubis.usdz --tris 5000 --lod 1500
    python3 tools/mesh.py <file> --inspect          # report only, change nothing

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
4. Resamples every per-point attribute — UVs, joint indices, joint weights —
   from the nearest original point. Decimation moves vertices rather than only
   removing them, so an index map is not enough; nearest neighbour is the
   standard remap and holds at these ratios.
5. Drops face-varying normals. USD recomputes them, and a decimated mesh's
   original normals would be wrong anyway.
6. Downsamples the texture.
7. Repacks as .usdz with the skeleton, the animation and the materials intact,
   because only the mesh prim is touched.

The skeleton and its animation are never modified, so clips authored against
the source rig keep working against the decimated one.
"""

import argparse, os, shutil, sys, tempfile, zipfile
from pathlib import Path

import numpy as np
from PIL import Image
from pxr import Usd, UsdGeom, UsdSkel, UsdUtils, Sdf, Vt
import fast_simplification
from scipy.spatial import cKDTree


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


def report(stage, label):
    mesh = find_mesh(stage)
    tris = 0
    for prim in stage.Traverse():
        if prim.GetTypeName() == "Mesh":
            counts = UsdGeom.Mesh(prim).GetFaceVertexCountsAttr().Get() or []
            tris += sum(max(0, c - 2) for c in counts)
    pts = len(mesh.GetPointsAttr().Get() or []) if mesh else 0
    print(f"  {label:10s} {tris:9,d} tris  {pts:8,d} points")
    return tris, pts


def process(src, target_tris, out_path, texture_size):
    stage = Usd.Stage.Open(str(src))
    mesh = find_mesh(stage)
    if mesh is None:
        sys.exit("no mesh in the stage")
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

    # --- write out --------------------------------------------------------
    work = Path(tempfile.mkdtemp())
    layer = work / "model.usdc"
    stage.GetRootLayer().Export(str(layer))

    # Carry the textures across, downsampled.
    with zipfile.ZipFile(src) as zf:
        for info in zf.infolist():
            if info.filename.lower().endswith((".png", ".jpg", ".jpeg")):
                dest = work / info.filename
                dest.parent.mkdir(parents=True, exist_ok=True)
                with zf.open(info) as f:
                    img = Image.open(f).convert("RGB")
                if max(img.size) > texture_size:
                    img.thumbnail((texture_size, texture_size), Image.LANCZOS)
                img.save(dest, "PNG", optimize=True)

    if out_path.exists():
        out_path.unlink()
    UsdUtils.CreateNewUsdzPackage(Sdf.AssetPath(str(layer)), str(out_path))
    shutil.rmtree(work, ignore_errors=True)
    return len(new_tris), len(new_points)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("source")
    ap.add_argument("--tris", type=int, default=5000, help="triangle target for the shipped model")
    ap.add_argument("--lod", type=int, default=0, help="also emit <name>_lod at this target (0 = skip)")
    ap.add_argument("--texture", type=int, default=1024, help="max texture edge")
    ap.add_argument("--inspect", action="store_true", help="report and change nothing")
    ap.add_argument("--out", help="output path (default: overwrite the source)")
    args = ap.parse_args()

    src = Path(args.source)
    before = src.stat().st_size
    print(f"{src.name}   {before/1048576:.1f} MB")
    report(Usd.Stage.Open(str(src)), "source")
    if args.inspect:
        return 0

    out = Path(args.out) if args.out else src
    staged = src.with_suffix(".orig.usdz")
    if not staged.exists():
        shutil.copy2(src, staged)     # keep the authoring source next to it

    t, p = process(staged, args.tris, out, args.texture)
    print(f"  shipped    {t:9,d} tris  {p:8,d} points   {out.stat().st_size/1048576:.1f} MB")

    if args.lod:
        lod = out.with_name(out.stem + "_lod.usdz")
        t, p = process(staged, args.lod, lod, max(512, args.texture // 2))
        print(f"  lod        {t:9,d} tris  {p:8,d} points   {lod.stat().st_size/1048576:.1f} MB")

    print(f"  authoring source kept at {staged.name}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
