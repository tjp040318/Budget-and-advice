#!/usr/bin/env python3
"""
One representation of a rigged, animated character, and the code that reads it
out of a generator's file, makes it canonical, reduces it, writes what the game
loads, and then skins the written file again in numpy to prove it.

    import character
    char = character.read("Art/Models/anubis.usdz")          # Blender/Meshy-web USDZ or Meshy-API GLB
    xf   = character.canonicalise(char, height=2.05)         # Y-up, metres, feet at origin, faces +Z ...
    character.decimate(char, target_tris=5000, texture_size=1024)
    character.write_usdz(char, "Pantheon/Resources/Models/anubis.usdz")
    character.verify("Pantheon/Resources/Models/anubis.usdz")

Why this exists. The first Anubis export loaded as gold shards. Opening it with
USD showed why, and none of it was the game's fault:

  - the armature's transform (scale 0.01, i.e. centimetres to metres) was
    written as a single time sample with no default, so at rest the file
    describes a 170-unit figure and only the animated frames are life-size;
  - the skeleton's rest pose was not its bind pose - the hips sat 68 units to
    one side and twisted 40 degrees, so the un-animated model was displaced;
  - the mesh was a Y-up asset rotated 90 degrees by its own node inside a Z-up
    stage, with the same rotation repeated in geomBindTransform;
  - every vertex carried ten bone influences, padded from a mean of three.
    Model I/O's skinning attributes are four wide, and a reader that assumes
    four per vertex mis-strides the array and glues vertices to random bones -
    which is exactly what shards look like;
  - the animation clips carried horizontal root motion, so a character slid
    off its stage slot the moment a clip started.

A model loader should not have to survive any of that. So the cleverness lives
here, once, and the file the game gets is boring on purpose:

  Y-up, metres, feet on the origin, centred, facing +Z, scaled to the height
  the roster declares; the mesh points ARE the bind pose; rest == bind; four
  influences per vertex, weights summing to one; joints ordered parents-first;
  root joints locked horizontally to the slot; one identity SkelRoot; the
  Blender prim layout that SceneKit has already been seen to load.

Every step prints what it measured, and `verify` re-skins the written file at
the bind pose and at three animated frames. If the numbers here are right and
the phone still disagrees, the disagreement is in SceneKit's importer, and the
numbers are what to send to Apple.

Conventions: matrices are 4x4 in USD's row-vector convention (translation in
the last row, `p @ M`), quaternions are (x, y, z, w) internally.
"""

import copy, io, json, re, shutil, struct, sys, tempfile, zipfile, base64
from dataclasses import dataclass, field
from pathlib import Path
from typing import Optional, List

import numpy as np
from PIL import Image
from pxr import Usd, UsdGeom, UsdSkel, UsdShade, UsdUtils, Sdf, Gf, Vt, Tf

REPO = Path(__file__).resolve().parent.parent

# ---------------------------------------------------------------------------
# Small matrix toolbox (row-vector convention)
# ---------------------------------------------------------------------------

# Z-up (x, y, z) -> Y-up (x, z, -y).
ROT_Z_UP_TO_Y_UP = np.array([[1.0, 0.0, 0.0], [0.0, 0.0, -1.0], [0.0, 1.0, 0.0]])
# About-face around Y.
ROT_Y_180 = np.array([[-1.0, 0.0, 0.0], [0.0, 1.0, 0.0], [0.0, 0.0, -1.0]])


def quat_to_rot(q):
    """(x, y, z, w) -> 3x3 rotation in row-vector convention."""
    x, y, z, w = np.asarray(q, dtype=np.float64) / np.linalg.norm(q)
    col = np.array([
        [1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
        [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
        [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)],
    ])
    return col.T


def rot_to_quat(r_row):
    """3x3 row-vector rotation -> (x, y, z, w). Orthonormalises first."""
    u, _, vt = np.linalg.svd(r_row)
    r_row = u @ vt
    if np.linalg.det(r_row) < 0:
        u[:, -1] *= -1
        r_row = u @ vt
    m = r_row.T
    tr = m[0, 0] + m[1, 1] + m[2, 2]
    if tr > 0:
        s = np.sqrt(tr + 1.0) * 2
        q = [(m[2, 1] - m[1, 2]) / s, (m[0, 2] - m[2, 0]) / s, (m[1, 0] - m[0, 1]) / s, 0.25 * s]
    elif m[0, 0] > m[1, 1] and m[0, 0] > m[2, 2]:
        s = np.sqrt(1.0 + m[0, 0] - m[1, 1] - m[2, 2]) * 2
        q = [0.25 * s, (m[0, 1] + m[1, 0]) / s, (m[0, 2] + m[2, 0]) / s, (m[2, 1] - m[1, 2]) / s]
    elif m[1, 1] > m[2, 2]:
        s = np.sqrt(1.0 + m[1, 1] - m[0, 0] - m[2, 2]) * 2
        q = [(m[0, 1] + m[1, 0]) / s, 0.25 * s, (m[1, 2] + m[2, 1]) / s, (m[0, 2] - m[2, 0]) / s]
    else:
        s = np.sqrt(1.0 + m[2, 2] - m[0, 0] - m[1, 1]) * 2
        q = [(m[0, 2] + m[2, 0]) / s, (m[1, 2] + m[2, 1]) / s, 0.25 * s, (m[1, 0] - m[0, 1]) / s]
    q = np.array(q)
    return q / np.linalg.norm(q)


def trs(t, q, s):
    m = np.eye(4)
    m[:3, :3] = np.diag(np.asarray(s, dtype=np.float64)) @ quat_to_rot(q)
    m[3, :3] = t
    return m


def decompose(m):
    """4x4 -> (t, q_xyzw, s). Exact for rotation + scale + translation; no shear."""
    a = m[:3, :3].copy()
    s = np.linalg.norm(a, axis=1)
    s[s < 1e-12] = 1e-12
    r = a / s[:, None]
    if np.linalg.det(r) < 0:
        s[2] *= -1
        r[2] *= -1
    return m[3, :3].copy(), rot_to_quat(r), s


def gf_to_np(m):
    return np.array([[m[r][c] for c in range(4)] for r in range(4)], dtype=np.float64)


def np_to_gf(m):
    return Gf.Matrix4d(*[float(v) for v in np.asarray(m).reshape(-1)])


def world_from_local(local, parents):
    world = np.empty_like(local)
    for i in range(len(local)):
        world[i] = local[i] if parents[i] < 0 else local[i] @ world[parents[i]]
    return world


def local_from_world(world, parents):
    local = np.empty_like(world)
    for i in range(len(world)):
        local[i] = world[i] if parents[i] < 0 else world[i] @ np.linalg.inv(world[parents[i]])
    return local


def skin(points, joint_indices, joint_weights, bind, joint_world):
    """Linear blend skinning exactly as UsdSkel defines it, geomBindTransform = I."""
    m = np.einsum("jab,jbc->jac", np.linalg.inv(bind), joint_world)      # (J,4,4)
    ph = np.c_[points, np.ones(len(points))]
    per = np.einsum("nc,nkcd->nkd", ph, m[joint_indices])                 # (N,K,4)
    return np.einsum("nk,nkd->nd", joint_weights, per)[:, :3]


def similarity_parts(m):
    """A 4x4 that is rotation + uniform scale + translation -> (R, s, t). Warns otherwise."""
    t, q, s = decompose(m)
    if np.ptp(np.abs(s)) > 1e-3 * max(1.0, abs(s).max()):
        print(f"  warning: non-uniform scale {s} in a transform that should be uniform; using the mean")
    return quat_to_rot(q), float(np.abs(s).mean()), t


# ---------------------------------------------------------------------------
# The character
# ---------------------------------------------------------------------------

@dataclass
class Texture:
    role: str             # base_color | normal | metallic_roughness | roughness | metallic | emissive
    data: bytes
    ext: str              # png | jpg

    @property
    def size(self):
        return Image.open(io.BytesIO(self.data)).size


@dataclass
class Character:
    name: str
    points: np.ndarray                      # (N,3) float32 - world space, bind pose
    faces: np.ndarray                       # (M,3) int32
    uvs: Optional[np.ndarray]               # (N,2) float32, USD convention (v up)
    joints: List[str]                       # USD joint paths, parents first
    parents: np.ndarray                     # (J,) -1 for roots
    bind: np.ndarray                        # (J,4,4) world-space bind transforms
    rest_local: np.ndarray                  # (J,4,4) local rest transforms
    joint_indices: Optional[np.ndarray]     # (N,K) int32
    joint_weights: Optional[np.ndarray]     # (N,K) float32
    anim: Optional[dict] = None             # {"T": (F,J,3), "R": (F,J,4) xyzw, "S": (F,J,3), "fps": float}
    textures: List[Texture] = field(default_factory=list)
    roughness: float = 0.55
    metallic: float = 0.1
    up_axis: str = "Y"
    source: str = ""

    @property
    def skinned(self):
        return self.joint_indices is not None and len(self.joints) > 0

    def joint_world_at_rest(self):
        return world_from_local(self.rest_local, self.parents)

    def joint_world_at(self, frame):
        a = self.anim
        local = np.array([trs(a["T"][frame, j], a["R"][frame, j], a["S"][frame, j]) for j in range(len(self.joints))])
        return world_from_local(local, self.parents)

    def skinned_points(self, joint_world):
        if not self.skinned:
            return self.points.astype(np.float64)
        return skin(self.points.astype(np.float64), self.joint_indices, self.joint_weights.astype(np.float64),
                    self.bind, joint_world)

    def joint_index(self, suffix):
        hits = [i for i, j in enumerate(self.joints) if j.split("/")[-1].lower().endswith(suffix.lower())]
        return hits[0] if hits else None

    @property
    def tris(self):
        return len(self.faces)


def bounds(p):
    return p.min(0), p.max(0)


# ---------------------------------------------------------------------------
# Reading: USDZ (Blender export via Meshy's web app, or one of our own files)
# ---------------------------------------------------------------------------

def _triangulate(counts, indices):
    tris, slots, o = [], [], 0
    for c in counts:
        for k in range(1, c - 1):
            tris.append((indices[o], indices[o + k], indices[o + k + 1]))
            slots.append((o, o + k, o + k + 1))
        o += c
    return np.array(tris, dtype=np.int64), np.array(slots, dtype=np.int64)


def split_seams(faces, corner_uvs):
    """Per-corner (faceVarying / wedge) UVs -> per-vertex UVs, exactly: a point
    that carries N distinct UVs across the corners that use it becomes N
    vertices. Returns (orig, faces, uvs): which input point each new vertex
    came from - index every other per-point array by it - the faces
    re-indexed, and one UV per new vertex. Equality is on the float bits, so
    a seam is wherever the exporter wrote two different values; nothing is
    merged that the file kept apart."""
    corner_points = np.asarray(faces).reshape(-1).astype(np.int64)
    uv = np.ascontiguousarray(corner_uvs, dtype=np.float32).reshape(-1, 2)
    key = np.c_[corner_points, uv.view(np.int32).astype(np.int64)]
    _, first, inverse = np.unique(key, axis=0, return_index=True, return_inverse=True)
    inverse = np.asarray(inverse).reshape(-1)
    return corner_points[first], inverse.reshape(-1, 3), uv[first]


def weld(points, faces, decimals=6):
    """The opposite: vertices at the same position (to a micron) become one, so
    a mesh split at its UV seams is a closed surface again. Returns (welded
    points, index of the welded vertex for each input vertex, faces
    re-indexed)."""
    key = np.round(np.asarray(points, dtype=np.float64), decimals)
    _, first, inverse = np.unique(key, axis=0, return_index=True, return_inverse=True)
    inverse = np.asarray(inverse).reshape(-1)
    return np.asarray(points)[first], inverse, inverse[np.asarray(faces)]


def uv_smear(uvs, faces, span=0.25):
    """How many triangles cover more than `span` of the atlas in u or v. A real
    piece of surface never does; a seam vertex with the wrong UV always does."""
    if uvs is None or len(faces) == 0:
        return 0
    tri = uvs[faces]
    return int(((tri.max(axis=1) - tri.min(axis=1)).max(axis=1) > span).sum())


def _zip_member(path, asset_path):
    rel = str(asset_path).lstrip("./")
    with zipfile.ZipFile(path) as zf:
        names = zf.namelist()
        if rel in names:
            return zf.read(rel)
        tail = [n for n in names if n.endswith(Path(rel).name)]
        return zf.read(tail[0]) if tail else None


def _textures_from_material(stage, mesh_prim, usdz_path, char):
    api = UsdShade.MaterialBindingAPI(mesh_prim)
    mat = api.ComputeBoundMaterial()[0] if api else None
    if not mat or not mat.GetPrim().IsValid():
        return
    surf = mat.ComputeSurfaceSource()[0]
    if not surf:
        return
    files = {}
    for inp in surf.GetInputs():
        name = inp.GetBaseName()
        src = inp.GetConnectedSource()
        if src:
            shader = UsdShade.Shader(src[0].GetPrim())
            f = shader.GetInput("file")
            if f and f.Get():
                files[name] = (str(f.Get().path), src[1])
        elif name == "roughness" and inp.Get() is not None:
            char.roughness = float(inp.Get())
        elif name == "metallic" and inp.Get() is not None:
            char.metallic = float(inp.Get())
    roles = {"diffuseColor": "base_color", "normal": "normal", "emissiveColor": "emissive",
             "roughness": "roughness", "metallic": "metallic"}
    base_file = files.get("diffuseColor", (None,))[0]
    if "roughness" in files and "metallic" in files and files["roughness"][0] == files["metallic"][0]:
        files["metallic_roughness"] = files.pop("roughness")
        files.pop("metallic")
        roles["metallic_roughness"] = "metallic_roughness"
    for inp, (path, _out) in files.items():
        role = roles.get(inp)
        if not role:
            continue
        if role == "emissive" and path == base_file:
            continue      # Blender wires the base colour into emission; that is not an authored glow
        data = _zip_member(usdz_path, path)
        if data:
            ext = Path(path).suffix.lstrip(".").lower().replace("jpeg", "jpg") or "png"
            char.textures.append(Texture(role, data, ext))


def read_usdz(path):
    path = Path(path)
    stage = Usd.Stage.Open(str(path))
    up = str(UsdGeom.GetStageUpAxis(stage))
    t0 = Usd.TimeCode(stage.GetStartTimeCode()) if stage.HasAuthoredTimeCodeRange() else Usd.TimeCode.Default()
    tcps = stage.GetTimeCodesPerSecond() or 24.0

    mesh_prim = next((p for p in stage.Traverse() if p.GetTypeName() == "Mesh"), None)
    if mesh_prim is None:
        sys.exit(f"{path.name}: no Mesh prim")
    mesh = UsdGeom.Mesh(mesh_prim)
    binding = UsdSkel.BindingAPI(mesh_prim)
    skel_targets = binding.GetSkeletonRel().GetTargets()
    skel_prim = stage.GetPrimAtPath(skel_targets[0]) if skel_targets else \
        next((p for p in stage.Traverse() if p.GetTypeName() == "Skeleton"), None)

    points = np.array(mesh.GetPointsAttr().Get(t0), dtype=np.float64)
    counts = np.array(mesh.GetFaceVertexCountsAttr().Get(t0))
    indices = np.array(mesh.GetFaceVertexIndicesAttr().Get(t0))
    tris, slots = _triangulate(counts, indices)

    uvs, orig = None, None
    pv_api = UsdGeom.PrimvarsAPI(mesh_prim)
    st = pv_api.GetPrimvar("st")
    if st and st.HasValue():
        flat = np.array(st.ComputeFlattened(t0), dtype=np.float32).reshape(-1, 2)
        if st.GetInterpolation() == UsdGeom.Tokens.faceVarying:
            # Blender writes one UV per face corner. A point on a UV seam has
            # several, and a mesh with one UV per point can keep only one of
            # them: the first one seen used to be kept, and every triangle
            # touching a seam then stretched across the atlas. So the point
            # is split instead - one vertex per distinct UV, faces re-indexed,
            # skin weights duplicated with it below - and nothing is lost.
            n_before = len(points)
            orig, tris, uvs = split_seams(tris, flat[slots.reshape(-1)])
            on_seam = int((np.bincount(orig, minlength=n_before) > 1).sum())
            print(f"    st is per face corner: {on_seam:,} of {n_before:,} points sit on UV seams; "
                  f"split into {len(orig):,} vertices so every corner keeps its own UV")
        elif len(flat) == len(points):
            uvs = flat

    joints, parents, bind, rest_local, ji, jw, anim = [], np.zeros(0, int), np.zeros((0, 4, 4)), np.zeros((0, 4, 4)), None, None, None
    world = np.eye(4)
    if skel_prim is not None and skel_prim.IsValid():
        skel = UsdSkel.Skeleton(skel_prim)
        joints = list(skel.GetJointsAttr().Get())
        parents = np.array(UsdSkel.Topology(joints).GetParentIndices(), dtype=np.int64)
        bind = np.array([gf_to_np(m) for m in skel.GetBindTransformsAttr().Get()])
        rest_attr = skel.GetRestTransformsAttr().Get()
        rest_local = np.array([gf_to_np(m) for m in rest_attr]) if rest_attr else local_from_world(bind, parents)
        # The skeleton's own world transform at the first sample: for Blender's
        # export that is the armature object's centimetre-to-metre scale, which
        # exists only as a time sample.
        world = gf_to_np(UsdGeom.Xformable(skel_prim).ComputeLocalToWorldTransform(t0))

        jip, jwp = pv_api.GetPrimvar("skel:jointIndices"), pv_api.GetPrimvar("skel:jointWeights")
        if jip and jip.HasValue() and jwp and jwp.HasValue():
            k = jip.GetElementSize()
            ji = np.array(jip.Get(t0), dtype=np.int64).reshape(len(points), k)
            jw = np.array(jwp.Get(t0), dtype=np.float64).reshape(len(points), k)
            own_order = binding.GetJointsAttr().Get()
            if own_order:
                lut = np.array([joints.index(j) for j in own_order], dtype=np.int64)
                ji = lut[ji]
            gbt = binding.GetGeomBindTransformAttr().Get(t0)
            g = gf_to_np(gbt) if gbt is not None else np.eye(4)
            points = (np.c_[points, np.ones(len(points))] @ g)[:, :3]        # into skeleton space
        else:
            # An unskinned mesh next to a skeleton: place it by its own transform.
            mw = gf_to_np(UsdGeom.Xformable(mesh_prim).ComputeLocalToWorldTransform(t0))
            points = (np.c_[points, np.ones(len(points))] @ mw @ np.linalg.inv(world))[:, :3]

        anim_targets = UsdSkel.BindingAPI(skel_prim).GetAnimationSourceRel().GetTargets()
        anim_prim = stage.GetPrimAtPath(anim_targets[0]) if anim_targets else \
            next((p for p in Usd.PrimRange(skel_prim) if p.GetTypeName() == "SkelAnimation"), None)
        if anim_prim is not None and anim_prim.IsValid():
            a = UsdSkel.Animation(anim_prim)
            times = a.GetTranslationsAttr().GetTimeSamples() or a.GetRotationsAttr().GetTimeSamples()
            if times:
                a_joints = list(a.GetJointsAttr().Get())
                order = [a_joints.index(j) if j in a_joints else -1 for j in joints]
                T = np.zeros((len(times), len(joints), 3)); R = np.zeros((len(times), len(joints), 4)); S = np.ones((len(times), len(joints), 3))
                rest_t = np.array([decompose(m)[0] for m in rest_local]); rest_r = np.array([decompose(m)[1] for m in rest_local])
                for f, t in enumerate(times):
                    tt = np.array(a.GetTranslationsAttr().Get(t), dtype=np.float64)
                    rr = a.GetRotationsAttr().Get(t)
                    ss = a.GetScalesAttr().Get(t)
                    for j, src_idx in enumerate(order):
                        if src_idx < 0:
                            T[f, j], R[f, j] = rest_t[j], rest_r[j]
                            continue
                        T[f, j] = tt[src_idx]
                        q = rr[src_idx]
                        R[f, j] = [q.GetImaginary()[0], q.GetImaginary()[1], q.GetImaginary()[2], q.GetReal()]
                        if ss is not None and len(ss) > src_idx:
                            S[f, j] = np.array(ss[src_idx], dtype=np.float64)
                dt = np.median(np.diff(times)) if len(times) > 1 else 1.0
                anim = {"T": T, "R": R, "S": S, "fps": float(tcps / dt)}
    else:
        world = gf_to_np(UsdGeom.Xformable(mesh_prim).ComputeLocalToWorldTransform(t0))

    if orig is not None:
        points = points[orig]
        if ji is not None:
            ji, jw = ji[orig], jw[orig]

    char = Character(
        name=path.stem.split("_")[0], points=points.astype(np.float32), faces=tris.astype(np.int32), uvs=uvs,
        joints=joints, parents=parents, bind=bind, rest_local=rest_local,
        joint_indices=ji.astype(np.int32) if ji is not None else None,
        joint_weights=jw.astype(np.float32) if jw is not None else None,
        anim=anim, up_axis=up, source=str(path),
    )
    _textures_from_material(stage, mesh_prim, path, char)
    # Fold the skeleton's world transform in, so the character is in the
    # source file's world space and the SkelRoot can be identity from here on.
    r, s, t = similarity_parts(world)
    apply_similarity(char, r, s, t)
    return char


# ---------------------------------------------------------------------------
# Reading: GLB (Meshy's rigging and animation endpoints)
# ---------------------------------------------------------------------------

GLB_MAGIC, CHUNK_JSON, CHUNK_BIN = 0x46546C67, 0x4E4F534A, 0x004E4942
COMPONENT = {5120: np.int8, 5121: np.uint8, 5122: np.int16, 5123: np.uint16, 5125: np.uint32, 5126: np.float32}
WIDTH = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT2": 4, "MAT3": 9, "MAT4": 16}
MIME_EXT = {"image/png": "png", "image/jpeg": "jpg"}


class Glb:
    def __init__(self, path):
        self.path = Path(path)
        data = self.path.read_bytes()
        magic, _version, length = struct.unpack_from("<III", data, 0)
        if magic != GLB_MAGIC:
            sys.exit(f"{path} is not a GLB")
        self.json, self.bin, off = None, b"", 12
        while off < length:
            clen, ctype = struct.unpack_from("<II", data, off)
            off += 8
            chunk, off = data[off:off + clen], off + clen
            if ctype == CHUNK_JSON:
                self.json = json.loads(chunk.decode("utf-8"))
            elif ctype == CHUNK_BIN:
                self.bin = chunk
        self.buffers = []
        for b in self.json.get("buffers", []):
            uri = b.get("uri")
            if uri is None:
                self.buffers.append(self.bin)
            elif uri.startswith("data:"):
                self.buffers.append(base64.b64decode(uri.split(",", 1)[1]))
            else:
                self.buffers.append((self.path.parent / uri).read_bytes())

    def view(self, index):
        bv = self.json["bufferViews"][index]
        buf = self.buffers[bv.get("buffer", 0)]
        start = bv.get("byteOffset", 0)
        return buf[start:start + bv["byteLength"]], bv.get("byteStride", 0)

    def accessor(self, index):
        acc = self.json["accessors"][index]
        if "sparse" in acc:
            sys.exit("sparse accessors are not supported")
        dtype, width, count = np.dtype(COMPONENT[acc["componentType"]]), WIDTH[acc["type"]], acc["count"]
        if "bufferView" not in acc:
            arr = np.zeros((count, width), dtype)
        else:
            raw, stride = self.view(acc["bufferView"])
            offset, item = acc.get("byteOffset", 0), dtype.itemsize * width
            if stride and stride != item:
                rows = np.frombuffer(raw, dtype=np.uint8, count=stride * (count - 1) + item, offset=offset)
                arr = np.lib.stride_tricks.as_strided(rows, shape=(count, item), strides=(stride, 1)).copy()
                arr = arr.view(dtype).reshape(count, width)
            else:
                arr = np.frombuffer(raw, dtype=dtype, count=count * width, offset=offset).reshape(count, width)
        if acc.get("normalized") and dtype.kind in "iu":
            arr = arr.astype(np.float32) / np.iinfo(dtype).max
        return arr

    def image_bytes(self, image_index):
        img = self.json["images"][image_index]
        if "bufferView" in img:
            data, _ = self.view(img["bufferView"])
            return bytes(data), MIME_EXT.get(img.get("mimeType"), "png")
        uri = img["uri"]
        if uri.startswith("data:"):
            head, payload = uri.split(",", 1)
            return base64.b64decode(payload), MIME_EXT.get(head[5:].split(";")[0], "png")
        p = self.path.parent / uri
        return p.read_bytes(), p.suffix.lstrip(".").lower().replace("jpeg", "jpg")


def _gltf_matrix(values):
    # column-major for column vectors == row-major for row vectors; no transpose
    return np.array(values, dtype=np.float64).reshape(4, 4)


def _node_trs(node):
    if "matrix" in node:
        return decompose(_gltf_matrix(node["matrix"]))
    return (np.array(node.get("translation", [0, 0, 0]), dtype=np.float64),
            np.array(node.get("rotation", [0, 0, 0, 1]), dtype=np.float64),
            np.array(node.get("scale", [1, 1, 1]), dtype=np.float64))


def _sample_linear(times, values, at):
    out = np.empty((len(at), values.shape[1]))
    for c in range(values.shape[1]):
        out[:, c] = np.interp(at, times, values[:, c])
    return out


def _sample_step(times, values, at):
    idx = np.clip(np.searchsorted(times, at, side="right") - 1, 0, len(times) - 1)
    return values[idx]


def _sample_quat(times, values, at):
    out = np.empty((len(at), 4))
    for k, t in enumerate(at):
        j = np.searchsorted(times, t, side="right") - 1
        if j < 0:
            q = values[0]
        elif j >= len(times) - 1:
            q = values[-1]
        else:
            q0, q1 = values[j], values[j + 1]
            span = times[j + 1] - times[j]
            u = (t - times[j]) / span if span > 0 else 0.0
            d = float(np.dot(q0, q1))
            if d < 0:
                q1, d = -q1, -d
            if d > 0.9995:
                q = q0 + u * (q1 - q0)
            else:
                th = np.arccos(min(1.0, d))
                q = (np.sin((1 - u) * th) * q0 + np.sin(u * th) * q1) / np.sin(th)
        out[k] = q / np.linalg.norm(q)
    return out


def read_glb(path, animation_index=0, fps=30):
    path = Path(path)
    glb = Glb(path)
    g = glb.json
    nodes = g.get("nodes", [])
    parent = {i: None for i in range(len(nodes))}
    for i, n in enumerate(nodes):
        for c in n.get("children", []):
            parent[c] = i
    world_cache = {}

    def world(i):
        if i not in world_cache:
            m = trs(*_node_trs(nodes[i]))
            world_cache[i] = m if parent[i] is None else m @ world(parent[i])
        return world_cache[i]

    skins = g.get("skins", [])
    if len(skins) > 1:
        sys.exit(f"{path.name}: {len(skins)} skins; only one is supported")
    skin_def = skins[0] if skins else None

    joints, parents, bind, rest_local, order, joint_pos = [], np.zeros(0, int), np.zeros((0, 4, 4)), np.zeros((0, 4, 4)), [], {}
    vertex_frame = np.eye(4)
    if skin_def:
        joint_nodes = list(skin_def["joints"])
        joint_set = set(joint_nodes)

        def joint_parent(i):
            p = parent[i]
            while p is not None and p not in joint_set:
                p = parent[p]
            return p

        depth = {}

        def depth_of(i):
            if i not in depth:
                jp = joint_parent(i)
                depth[i] = 0 if jp is None else 1 + depth_of(jp)
            return depth[i]

        order = sorted(joint_nodes, key=lambda i: (depth_of(i), joint_nodes.index(i)))
        joint_pos = {n: k for k, n in enumerate(order)}
        taken, path_of = set(), {}
        for i in order:
            base = Tf.MakeValidIdentifier(nodes[i].get("name") or f"joint_{i}")
            nm, k = base, 1
            while nm in taken:
                k += 1
                nm = f"{base}_{k}"
            taken.add(nm)
            jp = joint_parent(i)
            path_of[i] = nm if jp is None else f"{path_of[jp]}/{nm}"
        joints = [path_of[i] for i in order]
        parents = np.array([-1 if joint_parent(i) is None else joint_pos[joint_parent(i)] for i in order], dtype=np.int64)
        rest_world = np.array([world(i) for i in order])
        rest_local = local_from_world(rest_world, parents)
        original_pos = {n: k for k, n in enumerate(joint_nodes)}
        ibm = glb.accessor(skin_def["inverseBindMatrices"]) if "inverseBindMatrices" in skin_def else None
        inv_ibm = np.array([np.linalg.inv(_gltf_matrix(ibm[original_pos[i]])) if ibm is not None else np.eye(4)
                            for i in order])
        # glTF skins a vertex as p @ IBM[j] @ G[j] and says the skinned mesh
        # node's own transform is ignored, so the frame the vertices were
        # authored in is whatever the exporter chose: the world (Blender bakes
        # skinned meshes, so Meshy's files - the mesh node carries the
        # armature's centimetre scale and the vertices are already metres),
        # the mesh node's frame (the older Khronos samples), or an ancestor's
        # (RiggedSimple). Assuming the mesh node's frame read Meshy's export
        # as a two-centimetre figure whose clips exploded to 190 m. With the
        # rest pose equal to the bind pose, IBM[j] @ G_rest[j] IS that frame
        # and every joint agrees on it, so it is read off the joints; only
        # when they disagree (rest != bind) is the mesh node's frame assumed.
        skin_users = [i for i, n in enumerate(nodes) if n.get("skin") == 0 and "mesh" in n]
        skin_world = world(skin_users[0]) if skin_users else np.eye(4)
        frames_ = np.einsum("jab,jbc->jac", np.linalg.inv(inv_ibm), rest_world)
        spread = np.abs(frames_ - frames_[0]).max()
        if spread <= 1e-3 * max(1.0, np.abs(frames_[0]).max()):
            vertex_frame = frames_[0]
            how = "the joints agree on it (rest pose == bind pose)"
        else:
            vertex_frame = skin_world
            how = f"the joints disagree by {spread:.3g} (rest pose != bind pose); assuming the mesh node's"
        if np.allclose(vertex_frame, np.eye(4), atol=1e-5):
            what = "identity"
        elif np.allclose(vertex_frame, skin_world, atol=1e-5):
            what = "the mesh node's"
        else:
            what = "an ancestor node's"
        _, _, vf_scale = decompose(vertex_frame)
        print(f"    vertex frame: {what}, scale {vf_scale.mean():.4g} - {how}")
        bind = inv_ibm @ vertex_frame

    # --- meshes (all primitives concatenated, baked to world space) --------
    P, F, UV, JI, JW, mats = [], [], [], [], [], []
    base = 0
    lut = np.array([joint_pos[n] for n in skin_def["joints"]], dtype=np.int64) if skin_def else None
    for ni, node in enumerate(nodes):
        if "mesh" not in node:
            continue
        mesh = g["meshes"][node["mesh"]]
        skinned = skin_def is not None and "skin" in node
        # A skinned mesh's points are in the vertex frame worked out above,
        # which is where the bind transforms now live too; the node's own
        # transform is ignored, as glTF says. An unskinned mesh is placed by
        # its node like any other.
        mw = vertex_frame if skinned else world(ni)
        for prim in mesh["primitives"]:
            if prim.get("mode", 4) != 4:
                sys.exit(f"{path.name}: primitive mode {prim.get('mode')}; only triangles are supported")
            attrs = prim["attributes"]
            p = glb.accessor(attrs["POSITION"]).astype(np.float64)
            p = (np.c_[p, np.ones(len(p))] @ mw)[:, :3]
            f = (glb.accessor(prim["indices"]).reshape(-1) if "indices" in prim else np.arange(len(p))).astype(np.int64)
            uv = None
            if "TEXCOORD_0" in attrs:
                uv = glb.accessor(attrs["TEXCOORD_0"]).astype(np.float32)
                uv[:, 1] = 1.0 - uv[:, 1]
            if skinned and "JOINTS_0" in attrs:
                j = glb.accessor(attrs["JOINTS_0"]).astype(np.int64)
                w = glb.accessor(attrs["WEIGHTS_0"]).astype(np.float64)
                if "JOINTS_1" in attrs:
                    j = np.hstack([j, glb.accessor(attrs["JOINTS_1"]).astype(np.int64)])
                    w = np.hstack([w, glb.accessor(attrs["WEIGHTS_1"]).astype(np.float64)])
                j = lut[j]
            else:
                j = np.zeros((len(p), 1), dtype=np.int64)
                w = np.ones((len(p), 1))
            P.append(p); F.append(f.reshape(-1, 3) + base); UV.append(uv); JI.append(j); JW.append(w)
            if "material" in prim:
                mats.append(prim["material"])
            base += len(p)
    if not P:
        sys.exit(f"{path.name}: no mesh")
    points = np.vstack(P)
    faces = np.vstack(F)
    uvs = np.vstack(UV) if all(u is not None for u in UV) else None
    K = max(j.shape[1] for j in JI)
    ji = np.vstack([np.pad(j, ((0, 0), (0, K - j.shape[1]))) for j in JI])
    jw = np.vstack([np.pad(w, ((0, 0), (0, K - w.shape[1]))) for w in JW])

    # --- animation --------------------------------------------------------
    anim = None
    anims = g.get("animations", [])
    if anims and skin_def:
        a = anims[min(animation_index, len(anims) - 1)]
        channels = {}
        for ch in a["channels"]:
            tgt = ch["target"]
            if tgt.get("node") is None or tgt["path"] == "weights":
                continue
            sampler = a["samplers"][ch["sampler"]]
            times = glb.accessor(sampler["input"]).reshape(-1).astype(np.float64)
            values = glb.accessor(sampler["output"]).astype(np.float64)
            interp = sampler.get("interpolation", "LINEAR")
            if interp == "CUBICSPLINE":
                values = values.reshape(len(times), 3, -1)[:, 1, :]
                interp = "LINEAR"
            channels[(tgt["node"], tgt["path"])] = (times, values, interp)
        if channels:
            t0 = min(t[0] for t, _, _ in channels.values())
            t1 = max(t[-1] for t, _, _ in channels.values())
            frames = max(1, int(round((t1 - t0) * fps)) + 1)
            at = t0 + np.arange(frames) / fps
            T = np.empty((frames, len(order), 3)); R = np.empty((frames, len(order), 4)); S = np.empty((frames, len(order), 3))
            for k, i in enumerate(order):
                rt, rr, rs = _node_trs(nodes[i])
                for pth, dest, restv in (("translation", T, rt), ("rotation", R, rr), ("scale", S, rs)):
                    if (i, pth) in channels:
                        times, values, interp = channels[(i, pth)]
                        if pth == "rotation" and interp != "STEP":
                            dest[:, k] = _sample_quat(times, values, at)
                        elif interp == "STEP":
                            dest[:, k] = _sample_step(times, values, at)
                        else:
                            dest[:, k] = _sample_linear(times, values, at)
                    else:
                        dest[:, k] = restv
                # A root joint under a transformed non-joint node is animated
                # relative to that node; the skeleton wants it relative to the root.
                if parents[k] < 0 and parent[i] is not None:
                    above = world(parent[i])
                    if not np.allclose(above, np.eye(4), atol=1e-6):
                        for f in range(frames):
                            T[f, k], R[f, k], S[f, k] = decompose(trs(T[f, k], R[f, k], S[f, k]) @ above)
            anim = {"T": T, "R": R, "S": S, "fps": float(fps)}

    char = Character(
        name=path.stem.split("_")[0], points=points.astype(np.float32), faces=faces.astype(np.int32), uvs=uvs,
        joints=joints, parents=parents, bind=bind, rest_local=rest_local,
        joint_indices=ji.astype(np.int32) if skin_def else None, joint_weights=jw.astype(np.float32) if skin_def else None,
        anim=anim, up_axis="Y", source=str(path),
    )
    if mats:
        mat = g["materials"][mats[0]]
        pbr = mat.get("pbrMetallicRoughness", {})
        # glTF's defaults are 1.0 for both. A file that says nothing about
        # roughness gets the project's 0.55, the same default the game's
        # MaterialTuner applies, rather than fully matte.
        if "roughnessFactor" in pbr:
            char.roughness = float(pbr["roughnessFactor"])
        char.metallic = float(pbr.get("metallicFactor", 1.0))
        base_image = g["textures"][pbr["baseColorTexture"]["index"]]["source"] if "baseColorTexture" in pbr else None
        for key, role in (("baseColorTexture", "base_color"), ("metallicRoughnessTexture", "metallic_roughness")):
            if key in pbr:
                data, ext = glb.image_bytes(g["textures"][pbr[key]["index"]]["source"])
                char.textures.append(Texture(role, data, ext))
        for key, role in (("normalTexture", "normal"), ("emissiveTexture", "emissive")):
            if key not in mat:
                continue
            image = g["textures"][mat[key]["index"]]["source"]
            if role == "emissive" and (image == base_image or max(mat.get("emissiveFactor", [0, 0, 0])) <= 0):
                # Meshy's rigged export wires the base colour into emission at
                # full strength. That is not an authored glow; shipped, it
                # would make the whole figure self-lit and flat, and the game
                # keeps any emissive map an export carries.
                print("    emissive texture is the base colour; dropped (not an authored glow)")
                continue
            data, ext = glb.image_bytes(image)
            char.textures.append(Texture(role, data, ext))
    return char


def read(path, **kw):
    path = Path(path)
    if path.suffix.lower() == ".glb":
        return read_glb(path, **kw)
    return read_usdz(path)


# ---------------------------------------------------------------------------
# Transforms
# ---------------------------------------------------------------------------

def apply_similarity(char, r, s, t):
    """Moves the whole character - points, bind pose, rest pose, animation - by
    p' = p R s + t. Exact: every joint's world transform becomes world @ W."""
    w = np.eye(4)
    w[:3, :3] = r * s
    w[3, :3] = t
    char.points = ((char.points.astype(np.float64) @ (r * s)) + t).astype(np.float32)
    if len(char.joints) == 0:
        return
    char.bind = char.bind @ w
    roots = np.where(char.parents < 0)[0]
    for j in roots:
        char.rest_local[j] = char.rest_local[j] @ w
    if char.anim:
        a = char.anim
        for f in range(len(a["T"])):
            for j in roots:
                a["T"][f, j], a["R"][f, j], a["S"][f, j] = decompose(trs(a["T"][f, j], a["R"][f, j], a["S"][f, j]) @ w)


def facing(char):
    """+1 if the toes point along +Z, -1 along -Z, 0 if there are no feet to ask."""
    for side in ("Left", "Right"):
        foot, toe = char.joint_index(f"{side}Foot"), char.joint_index(f"{side}ToeBase")
        if foot is not None and toe is not None:
            d = char.bind[toe][3, :3] - char.bind[foot][3, :3]
            if abs(d[2]) > 1e-6:
                return 1 if d[2] > 0 else -1
    return 0


def canonicalise(char, height=None, transform=None, lock_root=True, influences=4):
    """Y-up, metres, feet at the origin, centred, facing +Z, `height` tall;
    rest == bind; root joints locked horizontally; at most `influences` per
    vertex. Returns the similarity used, so clip files can be given the same
    one (`transform=`) and stay in step with their base model."""
    log = []
    if transform is None:
        r = np.eye(3)
        if char.up_axis.upper() == "Z":
            r = r @ ROT_Z_UP_TO_Y_UP
            log.append("Z-up source rotated to Y-up")
        # Facing and height are read off the bind pose after that rotation.
        probe = copy.deepcopy(char)
        apply_similarity(probe, r, 1.0, np.zeros(3))
        f = facing(probe)
        if f < 0:
            r = r @ ROT_Y_180
            apply_similarity(probe, ROT_Y_180, 1.0, np.zeros(3))
            log.append("toes pointed to -Z; turned about-face")
        elif f == 0:
            log.append("no foot/toe joints; facing left as authored")
        lo, hi = bounds(probe.points.astype(np.float64))
        h = hi[1] - lo[1]
        s = (height / h) if height else 1.0
        t = np.array([-(lo[0] + hi[0]) * 0.5 * s, -lo[1] * s, -(lo[2] + hi[2]) * 0.5 * s])
        log.append(f"height {h:.3f} -> {h * s:.3f} (x{s:.5f}); moved by ({t[0]:+.3f}, {t[1]:+.3f}, {t[2]:+.3f})")
        transform = {"R": r, "s": float(s), "t": t}
    apply_similarity(char, transform["R"], transform["s"], transform["t"])
    char.up_axis = "Y"

    if len(char.joints):
        # The un-animated pose is the bind pose, so the raw points are what a
        # viewer shows and what any bounding-box code measures.
        char.rest_local = local_from_world(char.bind, char.parents)
        if char.anim:
            a = char.anim
            for j in np.where(char.parents < 0)[0]:
                hips = char.bind[j][3, :3]
                drift = np.linalg.norm(a["T"][:, j, [0, 2]] - a["T"][0, j, [0, 2]], axis=1).max()
                start_off = a["T"][0, j, [0, 2]] - hips[[0, 2]]
                if lock_root:
                    a["T"][:, j, 0] = hips[0]
                    a["T"][:, j, 2] = hips[2]
                    log.append(f"root '{char.joints[j].split('/')[-1]}' locked to the slot "
                               f"(started {np.linalg.norm(start_off):.2f} m off, drifted {drift:.2f} m)")
                else:
                    a["T"][:, j, 0] -= start_off[0]
                    a["T"][:, j, 2] -= start_off[1]
                    log.append(f"root '{char.joints[j].split('/')[-1]}' start moved onto the slot; "
                               f"{drift:.2f} m of root motion kept")
        limit_influences(char, influences)
        log.append(f"{char.joint_weights.shape[1]} influences per vertex")
    for line in log:
        print(f"    {line}")
    return transform


PROPORTIONS = {
    # The owner, 2026-09-17: "I honestly don't like the big hands and
    # cartoony look. I want it a little more serious feeling and look."
    # Every concept was painted "about five heads tall with a slightly
    # large head, big hands and feet", and the meshes followed. This is
    # the free half of the answer: the head, the hands and the feet scaled
    # down at their own joints, the thigh and the shin bones lengthened
    # (everything below a lengthened bone moves down rigidly), and the
    # deformation BAKED into the mesh, so the skeleton keeps no scale and
    # every clip plays as before. A number is a uniform scale about the
    # joint that its children inherit; {"length": L} stretches the bone
    # toward its first child by L.
    "serious": {"Head": 0.85, "LeftHand": 0.74, "RightHand": 0.74, "LeftFoot": 0.88, "RightFoot": 0.88,
                "LeftUpLeg": {"length": 1.10}, "RightUpLeg": {"length": 1.10},
                "LeftLeg": {"length": 1.08}, "RightLeg": {"length": 1.08}},
    # The stronger recipe (2026-09-18): the first one moved a five-head
    # chibi to five and a half and the owner still saw "cartoony" — the
    # body's WIDTH is the chibi as much as the head is. {"width": W}
    # squashes a bone's own vertices in the two axes across it and moves its
    # children in with it: the torso and hips a tenth narrower, the limbs
    # slimmer, the legs a quarter longer, the head at four fifths — about
    # six and a half heads tall, the genre's "serious" hero.
    "serious2": {"Head": 0.80, "LeftHand": 0.70, "RightHand": 0.70, "LeftFoot": 0.82, "RightFoot": 0.82,
                 "Hips": {"width": 0.90}, "Spine": {"width": 0.90},
                 "Spine1": {"width": 0.92}, "Spine2": {"width": 0.94}, "Spine01": {"width": 0.92}, "Spine02": {"width": 0.94},
                 "LeftUpLeg": {"length": 1.28, "width": 0.90}, "RightUpLeg": {"length": 1.28, "width": 0.90},
                 "LeftLeg": {"length": 1.22, "width": 0.92}, "RightLeg": {"length": 1.22, "width": 0.92},
                 "LeftArm": {"length": 1.06, "width": 0.88}, "RightArm": {"length": 1.06, "width": 0.88},
                 "LeftForeArm": {"length": 1.06, "width": 0.88}, "RightForeArm": {"length": 1.06, "width": 0.88}},
}


# Families whose geometry behind the back is meant to move with the limbs:
# wings on arms, tails on a thigh. The cape pass leaves them alone.
CAPE_EXCLUDE = ("harpy", "fox", "nike", "valkyr", "sphinx", "pegasus", "griffin", "dragon", "hydra",
                "phoenix", "raven", "eagle", "wing", "apep", "serpent", "jotunn", "colossus", "unwrapped",
                # wings along the ARMS, which the pass read as a cape (2026-09-18): the winged
                # goddesses and the bird-woman; and the nymph, whose water jar hangs from the
                # hand against her hair and would have left the hand with it
                "nephthys", "isis", "maat", "siren", "nymph",
                # a round shield carried behind the hip, a sheet by every rule but roundness,
                # and merged with the arm it is not round enough
                "khnum")


# The bones whose geometry a cape must NOT follow (the limbs), and the
# owners whose geometry is left alone whatever it looks like: hair, a hood,
# a plume hang from the head and move with it. The hands are NOT here: a
# weapon is skinned to the hand that holds it, but so was the awakened
# Ares's whole cape (5,185 vertices on his LeftHand, the bat's wing of the
# owner's reveal frame), so a weapon is told from a cape by its SHAPE
# (`_big_sheets`), never by who owns it.
LIMB_BONES = ("upleg", "leg", "foot", "toebase", "shoulder", "arm", "forearm", "hand")
SURFACE_BONES = ("upleg", "leg", "foot", "toebase", "arm", "forearm", "hand")   # a clavicle is where a cape hangs from
HELD_BONES = ("head", "neck", "eye", "jaw")

# The cape chain (2026-09-18, evening): a cape hangs from its OWN joints,
# `cape_0` at the shoulder line down to `cape_3` above the hem, children of
# the spine joint it hangs from, and the game swings them with a spring
# simulation every frame (Pantheon/Render/ClothChain.swift; tools/cape_sim.py
# is the same sum in Python, for the boards). A clip carrier's skeleton does
# NOT carry them: a clip's tracks reach a joint by name, and a joint with no
# track keeps whatever the simulation set — a rest track on the chain would
# pin the cape to its bind pose. `body_joints` is what a carrier must match.
CAPE_CHAIN = 4


# Every joint the game SIMULATES rather than animates: the cape chain and,
# since 2026-09-22, the robe ring (`reweight_robe`: robe_<sector>_<k>). A
# clip carrier never carries one of them — a rest track on a robe joint
# would pin the robe to its bind pose exactly as it would a cape.
CLOTH_PREFIXES = ("cape_", "robe_")


def _is_cloth_joint(path):
    return path.split("/")[-1].startswith(CLOTH_PREFIXES)


def cape_joint_count(char):
    return sum(1 for j in char.joints if j.split("/")[-1].startswith("cape_"))


def cloth_joint_count(char):
    """The simulated joints of either kind, cape and robe."""
    return sum(1 for j in char.joints if _is_cloth_joint(j))


def body_joints(char):
    """The joint list without the simulated cloth (the cape chain and the
    robe ring): a clip carrier's whole skeleton."""
    return [j for j in char.joints if not _is_cloth_joint(j)]


def _append_joint(char, name, parent, position):
    """Adds a joint at a world position, unrotated, as the LAST joint of the
    skeleton (parents-first order holds: its parent is already there). A
    base that still carries an animation gets a rest track for it."""
    bind = np.eye(4)
    bind[3, :3] = position
    char.joints = list(char.joints) + [f"{char.joints[parent]}/{name}"]
    char.parents = np.append(np.asarray(char.parents), parent)
    char.bind = np.concatenate([char.bind, bind[None]])
    char.rest_local = np.concatenate([char.rest_local, (bind @ np.linalg.inv(char.bind[parent]))[None]])
    if char.anim is not None:
        a = char.anim
        frames = len(a["T"])
        a["T"] = np.concatenate([a["T"], np.repeat(char.rest_local[-1][3, :3][None, None], frames, 0)], axis=1)
        a["R"] = np.concatenate([a["R"], np.tile(np.array([0.0, 0.0, 0.0, 1.0]), (frames, 1, 1))], axis=1)
        a["S"] = np.concatenate([a["S"], np.ones((frames, 1, 3))], axis=1)
    return len(char.joints) - 1


def _bone_kind(leaf_name):
    """'RightForeArm' -> 'forearm', 'neck' -> 'neck' (Meshy's rigs mix cases)."""
    n = leaf_name.lower()
    for side in ("left", "right", "l_", "r_"):
        if n.startswith(side):
            n = n[len(side):]
            break
    return n.strip("_")


def _limb_surface(P, normals, pa, pb, reach, gap, t_bins=4, angle_bins=16, slack=1.8, inward_stop=True):
    """True for the points that are the limb's OWN surface around the bone
    pa->pb: a limb is a closed tube round its bone, so at every angle and
    station along it the mesh nearest the bone is the limb — skin, band,
    pauldron and all, one continuous layer facing OUTWARD — and a hanging
    cape is a separate layer beyond it. Per cell of angle and station the
    distances are sorted, and the limb's layer ends at the first of: an
    empty `gap`, the first face turned INWARD toward the bone (a tube has
    none; a cape lying against the calf shows its inner face first), or
    `slack` times the innermost distance. Whatever its size, then: a
    cyclops's arm is as thick as a cape is far, Sekhmet's gold arm bands
    bulge a half again past her skin with no gap, and Ares's cape hugging
    his calf is cut where it turns to face the leg. The inward stop is for
    the LEGS (`inward_stop`): beside an upper arm the torso's flank faces
    the bone too, and read as one it gave Sekhmet's arms to the cape."""
    ab = pb - pa
    length = float(np.linalg.norm(ab))
    if length < 1e-6:
        return np.zeros(len(P), bool)
    u = ab / length
    rel = P - pa
    t = rel @ u
    radial = rel - t[:, None] * u
    d = np.linalg.norm(radial, axis=1)
    helper = np.array([1.0, 0.0, 0.0]) if abs(u[0]) < 0.9 else np.array([0.0, 1.0, 0.0])
    e1 = np.cross(u, helper); e1 /= np.linalg.norm(e1)
    e2 = np.cross(u, e1)
    angle = np.arctan2(radial @ e2, radial @ e1)
    near = (t > -0.1 * length) & (t < 1.1 * length) & (d < reach)
    tb = np.clip(np.floor(t / length * t_bins), 0, t_bins - 1).astype(int)
    an = (np.floor((angle + np.pi) / (2 * np.pi) * angle_bins)).astype(int) % angle_bins
    cell = tb * angle_bins + an
    inward = (np.einsum("ij,ij->i", normals, radial) / np.maximum(d, 1e-9)) < -0.35
    cells = t_bins * angle_bins
    idx = np.flatnonzero(near)
    order = idx[np.lexsort((d[idx], cell[idx]))]
    cs, ds = cell[order], d[order]
    limit = np.full(cells, np.inf)
    innermost = np.full(cells, np.inf)
    np.minimum.at(innermost, cs, ds)
    limit = np.minimum(limit, slack * innermost)
    same = cs[1:] == cs[:-1]
    for k in np.flatnonzero(same & (ds[1:] - ds[:-1] > gap))[::-1]:   # walking back, a cell's FIRST gap wins
        limit[cs[k]] = min(limit[cs[k]], ds[k])
    if inward_stop:
        first_in = np.full(cells, np.inf)
        np.minimum.at(first_in, cs[inward[order]], ds[inward[order]])
        limit = np.minimum(limit, first_in - 0.005)
    return near & (d <= limit[cell])


def _sheet_shape(points, min_width):
    """A principal-axis fit: thin one way, wide the other two, at least
    `min_width` across the second axis, and longer than wide (a disc is a
    shield). The third axis may reach three tenths of the second: a cloak
    wraps the body's side (Diana's, at 0.27) where a flat cape is under a
    tenth."""
    centred = points - points.mean(axis=0)
    lam = np.sort(np.linalg.eigvalsh(centred.T @ centred / len(points)))[::-1]   # descending
    width = 2.0 * np.sqrt(3.0 * max(lam[1], 0.0))          # a uniform slab's extent along its second axis
    # A cape hangs longer than it is wide; a sheet whose two large axes are
    # near equal is a DISC — Khnum's round shield, carried behind his hip,
    # passed every other test (2026-09-18). The line is 0.8: at 0.5 the
    # awakened Ares's broad cloak went with the shield.
    return 0.04 * lam[0] <= lam[1] <= 0.8 * lam[0] and lam[2] <= 0.30 * max(lam[1], 1e-12) and width >= min_width


def _big_sheets(P, faces, mask, uncut, min_count, min_span, top_at, min_width, merge_gap):
    """Keeps the connected pieces of `mask` (over the mesh's edges, across UV
    seams) that are SHEETS (`_sheet_shape`: thin in one direction, wide in
    the other two, at least `min_width` across), taking sheet-shaped pieces
    within `merge_gap` of one another as one sheet — the limbs' surfaces
    are cut out of the mask before this, and the cut splits a cloak where
    it brushes an arm (Diana's) — and keeping a sheet that is at least
    `min_count` welded vertices, spans `min_span` in height and hangs from
    the shoulders: its piece of the UNCUT band (`uncut`, the same mask
    before the limbs were cut out) reaches up to `top_at`, the shoulder
    line, which the cut piece itself seldom does once the arms have taken
    the cloak's top. A cape is one large sheet hanging from
    the shoulders most of the way down the back; a pauldron's back edge and
    a loincloth's tail are too short, a bident carried behind the hip is a
    rod, a thunderbolt is a lump, and an axe head is too narrow."""
    if not mask.any() or len(faces) == 0:
        return mask
    key, canon = np.unique(np.round(P, 5), axis=0, return_inverse=True)
    canon = canon.reshape(-1)
    f = canon[faces]
    edges = np.vstack([f[:, [0, 1]], f[:, [1, 2]], f[:, [2, 0]]])
    edges = edges[edges[:, 0] != edges[:, 1]]

    def components(vertex_mask):
        inside = np.zeros(len(key), bool)
        inside[canon[vertex_mask]] = True
        e = edges[inside[edges[:, 0]] & inside[edges[:, 1]]]
        labels = np.arange(len(key))
        try:
            from scipy.sparse import coo_matrix
            from scipy.sparse.csgraph import connected_components
            graph = coo_matrix((np.ones(len(e)), (e[:, 0], e[:, 1])), shape=(len(key), len(key)))
            labels = connected_components(graph, directed=False)[1]
        except ImportError:          # label propagation: the smallest label wins along every edge
            for _ in range(10000):
                low = np.minimum(labels[e[:, 0]], labels[e[:, 1]])
                before = labels.copy()
                np.minimum.at(labels, e[:, 0], low)
                np.minimum.at(labels, e[:, 1], low)
                if np.array_equal(before, labels):
                    break
        return inside, labels

    ys = key[:, 1]
    # Which uncut pieces reach the shoulder line; a cut piece inherits it.
    in_uncut, uncut_labels = components(uncut)
    reaches = np.zeros(len(key), bool)
    for lab in np.unique(uncut_labels[in_uncut]):
        members = np.flatnonzero((uncut_labels == lab) & in_uncut)
        if ys[members].max() >= top_at:
            reaches[members] = True
    in_mask, labels = components(mask)
    # The sheet-shaped pieces, then the ones within reach of each other
    # joined (union-find over the pieces).
    pieces = []
    for lab in np.unique(labels[in_mask]):
        members = np.flatnonzero((labels == lab) & in_mask)
        if len(members) >= 40 and reaches[members].any() and _sheet_shape(key[members], min_width):
            pieces.append(members)
    parent = list(range(len(pieces)))
    def find(i):
        while parent[i] != i:
            parent[i] = parent[parent[i]]
            i = parent[i]
        return i
    if len(pieces) > 1:
        try:
            from scipy.spatial import cKDTree
            trees = [cKDTree(key[m]) for m in pieces]
            for i in range(len(pieces)):
                for j in range(i + 1, len(pieces)):
                    d, _ = trees[j].query(key[pieces[i]], distance_upper_bound=merge_gap)
                    if np.isfinite(d).any():
                        parent[find(i)] = find(j)
        except ImportError:
            for i in range(len(pieces)):
                for j in range(i + 1, len(pieces)):
                    a = key[pieces[i]][::max(1, len(pieces[i]) // 400)]
                    b = key[pieces[j]][::max(1, len(pieces[j]) // 400)]
                    if np.min(np.linalg.norm(a[:, None, :] - b[None, :, :], axis=2)) < merge_gap:
                        parent[find(i)] = find(j)
    keep = np.zeros(len(key), bool)
    groups = {}
    for i, m in enumerate(pieces):
        groups.setdefault(find(i), []).append(m)
    for parts in groups.values():
        members = np.concatenate(parts)
        if len(members) >= min_count and ys[members].max() - ys[members].min() >= min_span \
                and _sheet_shape(key[members], min_width):
            keep[members] = True
    return mask & keep[canon]


def reweight_cape(char, back=0.03, floor=0.16, min_share=0.04, rings=4):
    """Binds whatever hangs behind the back — a cape, a cloak, a lion skin —
    to the spine chain by height, instead of to the arms and the shins Meshy's
    auto-rig chose (2026-09-18). The shipped Ares had thousands of cape
    vertices owned by the RIGHT SHIN and the two upper arms: his cape swung
    with one leg and lifted with the arms like a bat's wing on every attack
    (the owner: "fucked").

    A cape is the geometry that is FAR FROM EVERY BONE: the body's own
    surface lies within a limb's thickness of its bone, a hanging sheet does
    not. So a vertex is cloth when it is behind the spine's plane by `back`
    of the figure's height (6 cm on a 1.9 m figure; a belted cloak hugs the
    waist, and 10 cm cut Diana's in two there), above the knees
    (`floor`), below the neck, outside every LIMB's own surface
    (`_limb_surface`: the outward-facing layer of mesh round the bone up
    to the first gap or inward face, measured, so a cyclops's arm keeps
    its arm, Sekhmet keeps her arm bands and a shin gives up the cape
    lying against it; the first cut used the back plane
    alone and re-bound three quarters of Ares — the whole back of a thick
    armoured torso is "10 cm behind the spine" — and one radius for every
    bone then left the cape's foot on the shin, its top on the arm, and
    took the cyclops's arms), part of ONE large sheet hanging from the
    shoulders a fifth of the height or more, and shaped like one — thin
    one way, a foot or more across the other (`_big_sheets`; a pauldron's
    back edge and a loincloth's tail are too short, Hades's bident is a
    rod, Zeus's bolt a lump, and they stay with the hand — while the
    awakened Ares's cape, which the auto-rig gave to his LEFT HAND, is a
    sheet and comes off it), not the head's (hair, a hood, a plume move
    with the head), and held by a limb at all (a vertex the spine owns
    outright is left alone).
    Each takes its weight from the two spine joints bracketing its height,
    blended by height, so the cloth bends with the back and hangs from the
    hips; then the weights are averaged over `rings` rings of mesh
    neighbours across the seam, so the sheet's top blends into the shoulders
    it hangs from instead of tearing off them when an arm rises. Nothing
    happens unless a limb OWNS `min_share` of the mesh out there — a figure
    with no cape has a few hundred back-plate vertices sharing a little
    weight with a shoulder, and is left as rigged. Returns the count."""
    if not char.skinned:
        return 0
    leaf = [j.split("/")[-1] for j in char.joints]
    idx = {n.lower(): i for i, n in enumerate(leaf)}
    chain = [n for n in ("hips", "spine", "spine01", "spine1", "spine02", "spine2", "spine03", "spine3") if n in idx]
    neck = next((n for n in ("neck", "head") if n in idx), None)
    if len(chain) < 2 or neck is None:
        return 0
    J = len(leaf)
    jw = np.array([char.bind[i][3, :3] for i in range(J)], dtype=np.float64)
    chain_y = np.array([jw[idx[n]][1] for n in chain])
    order = np.argsort(chain_y)
    chain = [chain[i] for i in order]
    chain_y = chain_y[order]
    spine_z = float(np.mean([jw[idx[n]][2] for n in chain]))
    neck_y = float(jw[idx[neck]][1])
    P = char.points.astype(np.float64)
    height = float(P[:, 1].max() - P[:, 1].min())
    owner = np.asarray(char.joint_indices)[np.arange(len(P)), np.argmax(char.joint_weights, axis=1)]
    kind = [_bone_kind(n) for n in leaf]
    held_bone = np.array([k in HELD_BONES for k in kind])
    held_w = (held_bone[char.joint_indices] * char.joint_weights).sum(axis=1)
    band = (P[:, 1] > floor * height) & (P[:, 1] < neck_y) & (held_w <= 0.5)
    behind = band & (P[:, 2] < spine_z - back * height)
    uncut = behind.copy()
    # Clear of every limb's own surface (_limb_surface); the spine, hips
    # and head block nothing — what hangs behind them is the cloth. Cut
    # FIRST, so a weapon in a hand behind the hip is not bridged to the
    # shoulders through the arm's own back (Sekhmet's khopesh was).
    normals = vertex_normals(P, char.faces).astype(np.float64) if len(char.faces) else np.zeros_like(P)
    limb_layer = np.zeros(len(P), bool)
    for j, p in enumerate(char.parents):
        if p < 0 or kind[j] not in SURFACE_BONES:
            continue
        limb_layer |= _limb_surface(P, normals, jw[p], jw[j], reach=0.25 * height, gap=0.012 * height,
                                    inward_stop=kind[j] in ("upleg", "leg", "foot"))
    sheet = behind & ~limb_layer
    # One large sheet hanging from the shoulders (its uncut piece above the
    # second spine joint) a good way down the back, not a scatter of
    # patches at the shoulders (a figure with no cape has those), a
    # loincloth's tail from the belt, nor a weapon carried behind the hip
    # (a rod or a lump, not a sheet).
    sheet = _big_sheets(P, char.faces, sheet, uncut, min_count=max(300, len(P) // 150), min_span=0.20 * height,
                        top_at=chain_y[-2] - 0.02 * height, min_width=0.12 * height, merge_gap=0.03 * height)
    # A skirt, a robe, a tunic is not a cape: it WRAPS the legs, so the
    # same free-hanging cloth exists in FRONT of the figure over the same
    # heights, and re-bound to the hips it holds still while the legs
    # inside it move — the gladiator's knee-length tunic and his leg
    # wrappings tore off his legs in every attack (2026-09-18). A cape has
    # no front: Ares's pteruges hang over a third of his cape's height,
    # Diana's tunic under her cloak over 73%, the gladiator's tunic 86%,
    # Guan Yu's robe 91%, the centurion's 94%, the troll's loincloth 100%;
    # the line is 80%. The awakened Ares's shield is the hand's, not counted.
    if sheet.any():
        body = np.array([k in ("hips", "spine", "spine01", "spine1", "spine02", "spine2", "spine03", "spine3",
                               "upleg", "leg", "foot", "toebase") for k in kind])[owner]
        front = band & (P[:, 2] > spine_z + back * height) & ~limb_layer & body
        front = _big_sheets(P, char.faces, front, front, min_count=40, min_span=0.0, top_at=-np.inf,
                            min_width=0.06 * height, merge_gap=0.0)
        lo, hi = float(P[sheet, 1].min()), float(P[sheet, 1].max())
        edges = np.arange(lo, hi + 1e-6, 0.02 * height)
        if len(edges) > 2 and front.any():
            counts = np.histogram(P[front, 1], bins=edges)[0]
            covered = float((counts >= 5).mean())
            if covered >= 0.8:
                print(f"    cape: a skirt or a robe — free-hanging cloth in front over {100 * covered:.0f}% of the "
                      f"back sheet's height; left as rigged")
                return 0
    # Only what a limb has a hold on moves: a vertex the spine already owns
    # outright is left exactly as it is.
    limb = np.array([k in LIMB_BONES for k in kind])
    limb_weight = (limb[char.joint_indices] * char.joint_weights).sum(axis=1)
    cloth = sheet & (limb_weight > 0.15)
    n = int(cloth.sum())
    # A cape is a sheet a limb OWNS by the thousand — 8-13% of the mesh on
    # Ares, Diana and the centurion; a figure with no cape has under 3% of
    # its back plates and shoulder lumps sharing weight with a limb, and is
    # left exactly as Meshy rigged it.
    if int((cloth & limb[owner]).sum()) < min_share * len(P):
        return 0
    # --- the cape chain ---------------------------------------------------
    # The cloth is not re-bound to the spine any more: on the spine a cape
    # is a rigid board, and in a twisted stance it stood in front of Ares's
    # legs in every reveal frame (the owner, 2026-09-18: "ares is STILL
    # broken"). It hangs from `CAPE_CHAIN` joints of its own down its centre
    # line, the game's spring simulation swings them, and what hangs from
    # them is EVERY sheet vertex outside the torso's own surface, whoever
    # Meshy gave it to — the spine-owned half of a cape swinging on the
    # chain while the limb-owned half hung still would tear it down the
    # middle. The torso's own surface is `_limb_surface` round the spine
    # chain and the pelvis with the inward stop on: a cape's inner face is
    # the first thing behind the back that faces it, and where a cape lies
    # fused against the back with no gap and no inner face it stays the
    # back's, which is what the eye expects of the top of a cape.
    torso = np.zeros(len(P), bool)
    torso_kinds = ("spine", "spine01", "spine1", "spine02", "spine2", "spine03", "spine3", "neck")
    for j, p in enumerate(char.parents):
        if p >= 0 and kind[j] in torso_kinds:
            torso |= _limb_surface(P, normals, jw[p], jw[j], reach=0.25 * height, gap=0.012 * height, inward_stop=True)
    uplegs = [i for i, k in enumerate(kind) if k == "upleg"]
    hips_at = jw[idx[chain[0]]]
    crotch = np.array([hips_at[0], float(np.mean([jw[i][1] for i in uplegs])) if uplegs else hips_at[1] - 0.1 * height, hips_at[2]])
    torso |= _limb_surface(P, normals, crotch, hips_at, reach=0.25 * height, gap=0.012 * height, inward_stop=True)
    hang = (sheet & ~torso) | cloth
    n = int(hang.sum())
    if n < 100:
        return 0
    # The joints: `CAPE_CHAIN` of them down the sheet's centre line from its
    # top to a step above its hem, under the spine joint the top hangs from.
    y_top = min(float(np.percentile(P[hang, 1], 97)), neck_y)
    y_hem = float(np.percentile(P[hang, 1], 3))
    anchor = int(np.clip(np.searchsorted(chain_y, y_top + 0.02 * height) - 1, 0, len(chain) - 1))
    levels = np.array([y_top - k * (y_top - y_hem) / CAPE_CHAIN for k in range(CAPE_CHAIN)])
    first = len(char.joints)
    parent = idx[chain[anchor]]
    # One x for the whole chain (a cape's centre line is vertical; a clasp on
    # one shoulder put cape_0 half a metre out to the side on Ares) and each
    # level's own depth, since a cape flares away from the legs toward the hem.
    x_mid = float(np.median(P[hang, 0]))
    for yk in levels:
        band_k = hang & (np.abs(P[:, 1] - yk) < 0.06 * height)
        if band_k.sum() < 5:
            band_k = hang
        parent = _append_joint(char, f"cape_{len(char.joints) - first}", parent,
                               np.array([x_mid, yk, float(np.median(P[band_k, 2]))]))
    J = len(char.joints)
    # Dense weights, the hanging rows replaced by the height blend between
    # the two cape joints bracketing each vertex; over the shoulder line the
    # collar blends from cape_0 up into the spine joint it hangs from, and
    # under the last joint the hem is that joint's alone.
    W = np.zeros((len(P), J), dtype=np.float64)
    rows = np.arange(len(P))[:, None]
    np.add.at(W, (np.broadcast_to(rows, char.joint_indices.shape), char.joint_indices), char.joint_weights.astype(np.float64))
    rows = np.flatnonzero(hang)
    yv = P[rows, 1]
    above = yv >= levels[0]
    below = yv <= levels[-1]
    mid = ~above & ~below
    upper = np.clip(np.searchsorted(-levels, -yv, side="right") - 1, 0, CAPE_CHAIN - 2)
    t = np.clip((levels[upper] - yv) / np.maximum(levels[upper] - levels[upper + 1], 1e-6), 0.0, 1.0)
    W[rows] = 0.0
    W[rows[mid], first + upper[mid]] = 1.0 - t[mid]
    W[rows[mid], first + upper[mid] + 1] += t[mid]
    W[rows[below], first + CAPE_CHAIN - 1] = 1.0
    collar = np.clip((yv - levels[0]) / max(float(P[hang, 1].max()) - levels[0], 1e-6), 0.0, 1.0)
    W[rows[above], first] = 1.0 - collar[above]
    W[rows[above], idx[chain[anchor]]] += collar[above]
    # The seam: average each hanging vertex's weights with its mesh neighbours
    # (across UV seams, by position) for a few rings, the body's rows fixed.
    if rings > 0 and len(char.faces):
        key, canon = np.unique(np.round(P, 5), axis=0, return_inverse=True)
        canon = canon.reshape(-1)
        f = canon[char.faces]
        e = np.vstack([f[:, [0, 1]], f[:, [1, 2]], f[:, [2, 0]]])
        e = np.unique(np.sort(e, axis=1), axis=0)
        e = e[e[:, 0] != e[:, 1]]
        C = len(key)
        Wc = np.zeros((C, J)); cnt = np.zeros(C)
        np.add.at(Wc, canon, W); np.add.at(cnt, canon, 1.0)
        Wc /= np.maximum(cnt, 1.0)[:, None]
        hang_c = np.zeros(C, bool); hang_c[canon[hang]] = True
        deg = np.zeros(C); np.add.at(deg, e[:, 0], 1.0); np.add.at(deg, e[:, 1], 1.0)
        for _ in range(rings):
            acc = Wc.copy()
            np.add.at(acc, e[:, 0], Wc[e[:, 1]]); np.add.at(acc, e[:, 1], Wc[e[:, 0]])
            acc /= (deg + 1.0)[:, None]
            Wc[hang_c] = acc[hang_c]
        W[hang] = Wc[canon[hang]]
    K = char.joint_indices.shape[1]
    top = np.argsort(-W[hang], axis=1)[:, :K]
    wt = np.take_along_axis(W[hang], top, axis=1)
    wt /= np.maximum(wt.sum(axis=1, keepdims=True), 1e-9)
    top[wt <= 0] = 0
    char.joint_indices[hang] = top.astype(char.joint_indices.dtype)
    char.joint_weights[hang] = wt.astype(char.joint_weights.dtype)
    was = {}
    for o in owner[hang]:
        was[leaf[o]] = was.get(leaf[o], 0) + 1
    was = ", ".join(f"{k} {v:,}" for k, v in sorted(was.items(), key=lambda kv: -kv[1])[:4])
    print(f"    cape: {n:,} of {len(P):,} vertices hang clear of the body behind the back (were {was}); "
          f"hung on cape_0..cape_{CAPE_CHAIN - 1} under {leaf[idx[chain[anchor]]]}, "
          f"{levels[0]:.2f} m down to {levels[-1]:.2f} m, the seam blended over {rings} rings")
    return n


# The families the skirt pass is APPLIED to, by name (2026-09-22): every one
# judged on the render board at the heavy attack's blow frame, base and LOD.
# Of the sixteen the survey moves cloth on, three are clear wins — Anhur's
# tunic hangs from his hips with the khopesh free, Atalanta stands visible
# where her cloak had tented over her head, the awakened Sekhmet's skirt tab
# hangs — and the pass is on for them. Ten shred or tear: cloth welded to
# the arm along a whole sleeve or a wrapped robe comes off the cut in
# slivers (Heimdall's cloak and Pluto's robe outright; Centurion's,
# Njord's, Satyr's and the smith's apron in shards; Aphrodite's and Baldr's
# a torn edge; Loki's and Freya's a spike), and they stay as rigged — a
# robe through which the arms pass is the cape pass's next problem, cloth
# bones through the sheet. Three (Anubis, Bes, Nezha) change nothing a
# frame shows, so nothing is risked on them. mesh.py runs the pass on
# these names alone; a new family is judged on its board and added here.
SKIRT_FAMILIES = ("anhur", "atalanta", "sekhmet_awakened")


def cut_seam(char, moved, ji_before, jw_before, against=None):
    """Opens the mesh along the seam between the vertices `moved` to another
    bone and the rest: every face with vertices on both sides goes to the
    side that holds two of its three, and the third vertex is DOUBLED — the
    same point and UV, the majority side's skinning (the copy takes the mean
    of the face's two majority vertices, on either side; `ji_before` and
    `jw_before` are the weights before the pass, for a caller that wants to
    read them). Meshy fuses a tunic's corner to the hand
    resting on it, and however the corner is skinned the triangles across
    that weld stretch from the hip to wherever the hand swings — Anhur's
    tunic flared toward his khopesh at the blow frame with the panel on his
    legs (2026-09-22). Cut, the hand leaves the corner where it hangs and
    the crack between two things that only touched in the concept opens
    instead. Returns the number of vertices doubled.

    `against` (the robe ring, 2026-09-22) narrows the cut to faces that hold
    a moved vertex AND an `against` vertex — the hand's own skin — so a robe
    is cut from the hand and nowhere else; its seams with the legs and the
    torso are the seam blend's. Without it every mixed face is cut, as the
    skirt pass has it."""
    faces = char.faces
    side = moved[faces]
    n_in = side.sum(axis=1)
    touch = (n_in > 0) & (n_in < 3)
    if against is not None:
        touch &= np.asarray(against, bool)[faces].any(axis=1)
    mixed = np.flatnonzero(touch)
    if len(mixed) == 0:
        return 0
    J = len(char.joints)
    K = char.joint_indices.shape[1]

    def dense(ji, jw):
        w = np.zeros(J, dtype=np.float64)
        np.add.at(w, ji, jw.astype(np.float64))
        return w

    def sparse(w):
        top = np.argsort(-w)[:K]
        wt = w[top]
        wt = wt / max(float(wt.sum()), 1e-9)
        top = top.copy()
        top[wt <= 0] = 0
        return top.astype(char.joint_indices.dtype), wt.astype(char.joint_weights.dtype)

    new_points, new_uvs, new_ji, new_jw = [], [], [], []
    dup = {}
    new_faces = faces.copy()
    N = len(char.points)
    for f in mixed:
        tri = faces[f]
        ss = side[f]
        majority_moved = int(ss.sum()) >= 2
        for k in range(3):
            v = int(tri[k])
            if bool(ss[k]) == majority_moved:
                continue
            key = (v, majority_moved)
            if key not in dup:
                # The copy takes the mean of the face's majority vertices on
                # either side: the arm's copy of a cloth vertex with the
                # cloth's OLD blend (half hand, half leg) left a fringe of
                # slivers stretched from the hip to the hand.
                others = [int(tri[m]) for m in range(3) if bool(ss[m]) == majority_moved]
                w = np.mean([dense(char.joint_indices[o], char.joint_weights[o]) for o in others], axis=0)
                ji, jw = sparse(w)
                dup[key] = N + len(new_points)
                new_points.append(char.points[v])
                if char.uvs is not None:
                    new_uvs.append(char.uvs[v])
                new_ji.append(ji)
                new_jw.append(jw)
            new_faces[f, k] = dup[key]
    if not new_points:
        return 0
    char.points = np.vstack([char.points, np.array(new_points, dtype=char.points.dtype)])
    if char.uvs is not None:
        char.uvs = np.vstack([char.uvs, np.array(new_uvs, dtype=char.uvs.dtype)])
    char.joint_indices = np.vstack([char.joint_indices, np.array(new_ji, dtype=char.joint_indices.dtype)])
    char.joint_weights = np.vstack([char.joint_weights, np.array(new_jw, dtype=char.joint_weights.dtype)])
    char.faces = new_faces.astype(faces.dtype)
    return len(new_points)


def _welded_edges(P, faces):
    """The mesh welded by position (across UV seams): the unique points, each
    vertex's index into them, and every edge between two different ones."""
    key, canon = np.unique(np.round(P, 5), axis=0, return_inverse=True)
    canon = canon.reshape(-1)
    f = canon[faces]
    e = np.vstack([f[:, [0, 1]], f[:, [1, 2]], f[:, [2, 0]]])
    e = e[e[:, 0] != e[:, 1]]
    return key, canon, e


def _held_objects(P, faces, normals, mask, owner, kind, jw, parents, height, arm_surface, min_count, reach=0.22,
                  rod_width=None, weld_min=0.4, arm_owned=None, arm_share=None, cape_is_body=False):
    """The skirt pass's "a thing held, not cloth" rules, in one place for
    `reweight_skirt` and `reweight_robe` (factored out 2026-09-22 without
    changing a count: `tools/skirt_pass.py --survey` before and after).
    The connected pieces of `mask` over the welded mesh are judged one by
    one; a piece is HELD — stays with the hand — when it is a rod (the
    second principal extent under a tenth of the first), carried far from
    every body bone (median over `reach` of the height), a solid (median
    thickness over 2.5% of the height), welded to the arm alone (under two
    fifths of its edge on body-owned mesh), held at its middle (centre
    within 7.5% of the height of a wrist) or lying on the arm (three fifths
    within 2% of the height of `arm_surface`). A piece under `min_count`
    is neither: it stays where it is and is not reported. Returns (held,
    cloth, refused): the two vertex masks and the words for what was held.
    Why each rule exists is in `reweight_skirt`'s docstring.

    The robe ring judges a wider mask — everything hanging below the hips,
    whoever owns it — and its measurements moved four of the rules
    (2026-09-22), each by a keyword the skirt pass leaves at its default:
    a ROD must also be narrower than `rod_width` (Freya's cloak edges are
    0.056 and 0.073 h across and read as rods; the bident, the spear and
    the Centurion's blade are 0.030–0.039 h); the solid, weld, grip and
    on-the-arm rules apply only to a piece the arm owns at least
    `arm_share` of (`arm_owned`, per vertex: the smith's thick leather coat
    skirt and Loki's coat tail are the legs' and read as solids); a weld
    counts the cape's rows as the body's (`cape_is_body`: Freya's edges are
    sewn to her caped back); and the weld line is `weld_min`."""
    from scipy.spatial import cKDTree
    from scipy.sparse import coo_matrix
    from scipy.sparse.csgraph import connected_components
    bodykind = np.array([k in ("hips", "spine", "spine01", "spine1", "spine02", "spine2", "spine03", "spine3",
                               "neck", "upleg", "leg") for k in kind])
    weldkind = bodykind | np.array([k.startswith("cape_") for k in kind]) if cape_is_body else bodykind
    # The distance of every point to the nearest BODY bone segment.
    body_near = np.full(len(P), np.inf)
    for j, p in enumerate(parents):
        if p >= 0 and (bodykind[j] or bodykind[p]):
            a, b = jw[p], jw[j]
            ab = b - a
            t = np.clip(((P - a) @ ab) / max(float(ab @ ab), 1e-9), 0.0, 1.0)
            body_near = np.minimum(body_near, np.linalg.norm(P - (a + t[:, None] * ab), axis=1))
    # Where a thing is held: the wrists.
    grips = [jw[j] for j, k in enumerate(kind) if k == "hand"]
    arm_tree = cKDTree(P[arm_surface]) if arm_surface.any() else None
    # The connected pieces of the mask over the welded mesh.
    key, canon, e = _welded_edges(P, faces)
    mask_c = np.zeros(len(key), bool)
    mask_c[canon[mask]] = True
    e_in = e[mask_c[e[:, 0]] & mask_c[e[:, 1]]]
    graph = coo_matrix((np.ones(len(e_in)), (e_in[:, 0], e_in[:, 1])), shape=(len(key), len(key)))
    _, label = connected_components(graph, directed=False)
    labels = label[canon]
    body_c = np.zeros(len(key), bool)
    np.logical_or.at(body_c, canon, weldkind[owner])
    sheet = np.zeros(len(P), bool)
    held = np.zeros(len(P), bool)
    refused = []
    for lab in np.unique(labels[mask]):
        piece = mask & (labels == lab)
        count = int(piece.sum())
        if count < min_count:
            continue
        Q = P[piece]
        centre = Q.mean(axis=0)
        q = Q - centre
        cov = q.T @ q / max(len(q), 1)
        ev, vec = np.linalg.eigh(cov)
        order = np.argsort(ev)[::-1]
        ev, vec = ev[order], vec[:, order]
        if ev[0] <= 1e-12 or (ev[1] / ev[0] < 0.10
                              and (rod_width is None or 2.0 * np.sqrt(3.0 * ev[1]) < rod_width * height)):
            refused.append(f"a rod of {count:,}")
            held |= piece
            continue
        body_d = float(np.median(body_near[piece]))
        if body_d > reach * height:
            refused.append(f"a piece of {count:,} carried {body_d / height:.2f} h from the body")
            held |= piece
            continue
        if arm_share is not None and float(arm_owned[piece].mean()) < arm_share:
            sheet |= piece          # the body's own garment: the hand's rules do not apply
            continue
        # Thickness: the distance to the nearest neighbour whose face is turned the other way.
        N = normals[piece]
        k = min(40, len(Q))
        d, nb = cKDTree(Q).query(Q, k=k)
        opposed = np.einsum("ij,ikj->ik", N, N[nb]) < -0.5
        has = opposed.any(axis=1)
        first = np.argmax(opposed, axis=1)
        thick = d[np.arange(len(Q)), first][has]
        if has.mean() > 0.3 and float(np.median(thick)) > 0.025 * height:
            refused.append(f"a solid of {count:,} ({float(np.median(thick)) / height:.3f} h thick)")
            held |= piece
            continue
        # Welded to the arm alone: a thing held touches nothing but the hand,
        # a garment's panel is sewn to the rest of the garment.
        in_piece = np.zeros(len(key), bool)
        in_piece[canon[piece]] = True
        touching = e[in_piece[e[:, 0]] != in_piece[e[:, 1]]]
        outside = np.unique(np.concatenate([touching[:, 0][~in_piece[touching[:, 0]]],
                                            touching[:, 1][~in_piece[touching[:, 1]]]]))
        weld = float(body_c[outside].mean()) if len(outside) else 0.0
        if weld < weld_min:
            refused.append(f"a thing of {count:,} welded to the arm alone ({100 * weld:.0f}% of its edge on the body)")
            held |= piece
            continue
        grip_d = min((float(np.linalg.norm(centre - g)) for g in grips), default=np.inf)
        if grip_d < 0.075 * height:
            refused.append(f"a thing of {count:,} held at its middle ({grip_d / height:.2f} h from the wrist)")
            held |= piece
            continue
        # On the arm: its vertices within 2% of the height of the arm's own surface.
        if arm_tree is not None:
            da, _ = arm_tree.query(Q)
            on_arm = float((da < 0.02 * height).mean())
        else:
            on_arm = 0.0
        if on_arm > 0.6:
            refused.append(f"a piece of {count:,} lying on the arm")
            held |= piece
            continue
        sheet |= piece
    return held, sheet, refused


def reweight_skirt(char, min_count=None, rings=3, reach=0.22):
    """Hands back to the body the CLOTH Meshy's auto-rig gave to a hand, a
    forearm or an upper arm (2026-09-22): a tunic's front panel, a kilt's
    apron, a robe's drape, a cloak's side — cloth beside a hand resting on
    the thigh or an arm folded over the chest in the A-pose, which the
    rigger bound to the nearest bone. Anhur's red tunic swung up with his
    khopesh in every clip (on the owner's phone the reveal read as a blade
    held across his chest), Atalanta's cloak rose as a tent with her bow
    arms, Hathor's and Aphrodite's drapes lifted like curtains, Heimdall's
    cloak flew out to the side.

    A vertex is a candidate when a hand, a forearm or an upper arm owns it,
    it lies below the neck, and it is OUTSIDE the arm's own surface
    (`_limb_surface` on the upper arm, the forearm and the HAND — Meshy's
    rigs have no finger bones, so the hand is a segment of `hand_length`
    continued past the wrist: without it every hand in the roster was a
    piece of its own at the hand, 0.08 of the height across, and read as a
    thing held). The connected pieces of that mask (over the welded mesh)
    are then judged one by one, and a piece STAYS with the arm when it is
    any of: under `min_count` vertices (120 on a 15,000-vertex base, scaled
    to the mesh, so the LOD the battle draws moves the same pieces); a ROD
    (the second principal extent
    under a tenth of the first: a khopesh, a spear, a staff, a bow); far
    from every body bone (its median distance over `reach` of the height:
    the Minotaur's axe, Zeus's bolt); a SOLID (its median thickness, the
    distance to the nearest face turned the other way, over 2.5% of the
    height: Bes's drum, a pauldron); WELDED TO THE ARM (fewer than two
    fifths of the mesh neighbours along its edge are the body's: the
    awakened Ares's shield, Mars's scutum, Bragi's lyre, the smith's
    hammer, a horn at 0–4% — a garment's panel is sewn to the rest of the
    garment on the hips, the thighs or the chest, at 42–73%, and a thing
    held touches nothing but the hand; a panel between, welded to the hand
    along most of its edge, would stretch to a spike when the hand swings
    away from the body it was given to, the awakened Ares's tunic side at
    35% did, so it stays); HELD AT ITS MIDDLE (its centre within 7.5% of the height
    of a wrist: a thing in the palm); or lying ON the arm (three fifths of
    it within 2% of the height of the arm's own surface: a sleeve's drape,
    a bracer's fringe). Every one of those rules was read off the roster's
    own pieces (`tools/skirt_pass.py --survey` and the boards): a compact-
    object test on the span alone took the awakened Ares's shield, Mars's
    scutum, the lyre, the hammer and Neptune's sword with the hand welded
    to it; a "hanging" test refused Anhur's tunic, which is beside the hand
    and not below it; and a waist-to-knee band left Heimdall's hem below
    the knee with the arm while the cloak above it went to the legs. What
    is moved takes its nearest body-owned neighbour's weights — the
    garment's other panels on the hips, the thighs and the spine — so the
    cloth moves with the body as the rest of the garment does, and the seam
    is averaged over `rings` rings of mesh neighbours. Returns the count."""
    if not char.skinned or not len(char.faces):
        return 0
    leaf = [j.split("/")[-1] for j in char.joints]
    kind = [_bone_kind(l) for l in leaf]
    idx = {k: i for i, k in enumerate(kind)}
    if "hips" not in idx:
        return 0
    J = len(leaf)
    jw = np.array([char.bind[i][3, :3] for i in range(J)], dtype=np.float64)
    P = char.points.astype(np.float64)
    if min_count is None:
        # 120 on a 15,000-vertex base; the 4,000-vertex LOD the battle draws
        # keeps the same pieces at a third of the count.
        min_count = max(40, int(round(0.008 * len(P))))
    height = float(P[:, 1].max() - P[:, 1].min())
    neck = next((idx[n] for n in ("neck", "head") if n in idx), None)
    neck_y = float(jw[neck][1]) if neck is not None else P[:, 1].max()
    owner = np.asarray(char.joint_indices)[np.arange(len(P)), np.argmax(char.joint_weights, axis=1)]
    armkind = np.array([k in ("arm", "forearm") or k.startswith("hand") for k in kind])
    bodykind = np.array([k in ("hips", "spine", "spine01", "spine1", "spine02", "spine2", "spine03", "spine3",
                               "neck", "upleg", "leg") for k in kind])
    candidates = armkind[owner] & (P[:, 1] < neck_y)
    if int(candidates.sum()) < min_count:
        return 0
    normals = vertex_normals(P, char.faces).astype(np.float64)
    # The arm's own surface: the clavicle's, the upper arm's, the forearm's
    # and the hand's, the hand a segment continued past the wrist.
    hand_length = 0.12 * height
    segments = []
    hand_segments = []
    for j, p in enumerate(char.parents):
        if p >= 0 and armkind[j]:
            segments.append((jw[p], jw[j]))
            if kind[j] == "hand":
                u = jw[j] - jw[p]
                norm = float(np.linalg.norm(u))
                if norm > 1e-6:
                    hand_segments.append((jw[j], jw[j] + u / norm * hand_length))
    segments += hand_segments
    arm_layer = np.zeros(len(P), bool)
    for a, b in segments:
        arm_layer |= _limb_surface(P, normals, a, b, reach=0.25 * height, gap=0.012 * height, inward_stop=False)
    # The arm's own SKIN, tighter than the layer: 1.2x the innermost surface
    # of each cell, a 0.6% gap. Cloth lying on the sleeve or under the palm
    # is in the layer and not in the skin.
    arm_skin = np.zeros(len(P), bool)
    for a, b in segments:
        arm_skin |= _limb_surface(P, normals, a, b, reach=0.25 * height, gap=0.006 * height, slack=1.2,
                                  inward_stop=False)
    mask = candidates & ~arm_layer
    if int(mask.sum()) < min_count:
        return 0
    from scipy.spatial import cKDTree
    arm_surface = candidates & arm_layer
    held, sheet, refused = _held_objects(P, char.faces, normals, mask, owner, kind, jw, char.parents, height,
                                         arm_surface, min_count, reach=reach)
    key, canon, e = _welded_edges(P, char.faces)
    if refused:
        print(f"    skirt: left with the arm — {'; '.join(refused)}")
    if not sheet.any():
        return 0
    # The cloth's own rows nearest the arm sit inside the arm's generous
    # layer (1.8x the skin) and were never candidates; left with the hand
    # they drag the panel's edge after it (Anhur's tunic flared toward the
    # sword hand at the blow frame, Heimdall's cloak left shards on his
    # forearm). The sheet grows back through them — arm-owned, in the
    # layer, NOT the arm's own skin — over the welded mesh, as far as the
    # pool reaches (`grow` rings is a backstop).
    grow = 60
    pool = candidates & arm_layer & ~arm_skin & ~sheet
    if pool.any():
        e_u = np.unique(np.sort(e, axis=1), axis=0)
        C = len(key)
        pool_c = np.zeros(C, bool); pool_c[canon[pool]] = True
        seen = np.zeros(C, bool); seen[canon[sheet]] = True
        frontier = seen.copy()
        for _ in range(grow):
            hit = frontier[e_u[:, 0]] | frontier[e_u[:, 1]]
            step = np.zeros(C, bool)
            step[e_u[hit, 0]] = True; step[e_u[hit, 1]] = True
            step &= pool_c & ~seen
            if not step.any():
                break
            seen |= step
            frontier = step
        grown = pool & seen[canon]
        if grown.any():
            print(f"    skirt: {int(grown.sum()):,} rows of the cloth inside the hand's layer go with it")
            sheet |= grown
    n = int(sheet.sum())
    # Dense weights; each cloth vertex takes its nearest body-owned neighbour's.
    W = np.zeros((len(P), J), dtype=np.float64)
    rows = np.arange(len(P))[:, None]
    np.add.at(W, (np.broadcast_to(rows, char.joint_indices.shape), char.joint_indices), char.joint_weights.astype(np.float64))
    body = bodykind[owner] & ~sheet
    if int(body.sum()) < 10:
        return 0
    tree = cKDTree(P[body])
    body_rows = np.flatnonzero(body)
    _, nearest = tree.query(P[sheet], k=1)
    W[sheet] = W[body_rows[nearest]]
    # No arm in it. Meshy's rigger blends smoothly, so the garment's own
    # rows beside the hand — the ones the copy is taken from — carry the
    # hand at a third to a half; copied as they were, Anhur's "moved" tunic
    # still followed his khopesh at 48% (measured, 2026-09-22). The sheet
    # takes the body part of the weights alone, and so do the garment's
    # body-owned rows within `zone` rings of it (the rigger's blend zone:
    # 950 of the 3,025 body-owned vertices of Anhur's tunic band held over
    # a fifth of hand), never the arm's own skin (its layer, yes: the tunic
    # rows under the palm kept a 40% hand and threw slivers to the hand).
    arm_cols = np.flatnonzero(armkind)
    body_cols = np.flatnonzero(~armkind)

    def strip_arm(rows):
        w = W[rows]
        keep = w[:, body_cols].sum(axis=1) > 1e-6
        w[np.ix_(keep, arm_cols)] = 0.0
        w[keep] /= w[keep].sum(axis=1, keepdims=True)
        W[rows] = w

    strip_arm(sheet)
    zone = 14
    e_u = np.unique(np.sort(e, axis=1), axis=0)
    C = len(key)
    zone_ok = np.zeros(C, bool)
    np.logical_or.at(zone_ok, canon, bodykind[owner] & ~arm_skin & ~sheet)
    seen = np.zeros(C, bool); seen[canon[sheet]] = True
    frontier = seen.copy()
    reached = np.zeros(C, bool)
    for _ in range(zone):
        hit = frontier[e_u[:, 0]] | frontier[e_u[:, 1]]
        step = np.zeros(C, bool)
        step[e_u[hit, 0]] = True; step[e_u[hit, 1]] = True
        step &= zone_ok & ~seen
        if not step.any():
            break
        seen |= step; reached |= step
        frontier = step
    stripped = reached[canon] & (W[:, arm_cols].sum(axis=1) > 0.02)
    if stripped.any():
        strip_arm(stripped)
        print(f"    skirt: {int(stripped.sum()):,} rows of the garment beside it lose their share of the arm")
    # The seam, as the cape pass: averaged with the mesh neighbours across
    # UV seams for a few rings, the body's own rows fixed.
    # The arm's own vertices are left out of the averaging: the cloth's edge
    # is the garment's, all the way to the seam the cut below opens.
    if rings > 0:
        arm_c = np.zeros(C, bool)
        np.logical_or.at(arm_c, canon, armkind[owner] & ~sheet)
        e_b = e_u[~arm_c[e_u[:, 0]] & ~arm_c[e_u[:, 1]]]
        Wc = np.zeros((C, J)); cnt = np.zeros(C)
        np.add.at(Wc, canon, W); np.add.at(cnt, canon, 1.0)
        Wc /= np.maximum(cnt, 1.0)[:, None]
        sheet_c = np.zeros(C, bool); sheet_c[canon[sheet]] = True
        deg = np.zeros(C); np.add.at(deg, e_b[:, 0], 1.0); np.add.at(deg, e_b[:, 1], 1.0)
        for _ in range(rings):
            acc = Wc.copy()
            np.add.at(acc, e_b[:, 0], Wc[e_b[:, 1]]); np.add.at(acc, e_b[:, 1], Wc[e_b[:, 0]])
            acc /= (deg + 1.0)[:, None]
            Wc[sheet_c] = acc[sheet_c]
        W[sheet] = Wc[canon[sheet]]
    K = char.joint_indices.shape[1]
    ji_before, jw_before = char.joint_indices.copy(), char.joint_weights.copy()
    changed = sheet | stripped
    top = np.argsort(-W[changed], axis=1)[:, :K]
    wt = np.take_along_axis(W[changed], top, axis=1)
    wt /= np.maximum(wt.sum(axis=1, keepdims=True), 1e-9)
    top[wt <= 0] = 0
    char.joint_indices[changed] = top.astype(char.joint_indices.dtype)
    char.joint_weights[changed] = wt.astype(char.joint_weights.dtype)
    cut = cut_seam(char, changed, ji_before, jw_before)
    if cut:
        print(f"    skirt: the seam with the arm cut, {cut:,} vertices doubled")
    was = {}
    for o in owner[sheet]:
        was[leaf[o]] = was.get(leaf[o], 0) + 1
    was = ", ".join(f"{k} {v:,}" for k, v in sorted(was.items(), key=lambda kv: -kv[1])[:3])
    now = {}
    ji_now, jw_now = np.asarray(char.joint_indices)[:len(P)], np.asarray(char.joint_weights)[:len(P)]
    new_owner = ji_now[np.arange(len(P)), np.argmax(jw_now, axis=1)]
    for o in new_owner[sheet]:
        now[leaf[o]] = now.get(leaf[o], 0) + 1
    now = ", ".join(f"{k} {v:,}" for k, v in sorted(now.items(), key=lambda kv: -kv[1])[:3])
    print(f"    skirt: {n:,} of {len(P):,} vertices of cloth were an arm's ({was}); "
          f"now the body's ({now}), the seam blended over {rings} rings")
    return n


# --- the robe ring (2026-09-22) ---------------------------------------------
# A LOWER garment — a robe, a floor-length cloak, a coat's skirts — that
# Meshy's rigger gave to the hands resting on it in the A-pose hangs from
# joints of its OWN: up to eight chains round the hips, one per 45° sector,
# `ROBE_CHAIN` joints each (robe_<sector>_0 under Hips down to
# robe_<sector>_3 a step above the hem), which the game swings with a spring
# ring (Pantheon/Render/ClothChain.swift `ClothRing`; tools/cape_sim.py
# `RingSim` is the same sum in Python). The azimuth is atan2(x - hips_x,
# z - hips_z) in degrees: a canonical figure faces +Z, so +X — 90° — is
# the figure's LEFT. The fixed order below is the order the Swift walks.
ROBE_SECTORS = (("f", 0.0), ("fl", 45.0), ("l", 90.0), ("bl", 135.0),
                ("b", 180.0), ("br", -135.0), ("r", -90.0), ("fr", -45.0))
ROBE_CHAIN = 4
# The held-object rules as the ring reads them (`_held_objects`): a rod is
# under 0.045 h across, and a piece the arm owns is the hand's when under a
# fifth of its edge is sewn to the body or the cape.
ROBE_ROD_WIDTH = 0.045
ROBE_WELD_MIN = 0.2
# How far from its bone a leg's own surface can lie, by the joint that ends
# the segment ("leg" is the thigh, "foot" the shin). A floor-length robe with
# no legs modelled inside it IS the innermost surface round the thigh, and
# `_limb_surface` alone gave Pluto's whole robe to his legs (the ring took a
# fringe at the hem and tore from it). Measured on the roster, 2026-09-22:
# a real thigh's surface lies at 0.05-0.08 h (the 90th percentile; Diana,
# Loki, Njord, Baldr, Anhur), a shin's under 0.07 h with the boot; the robed
# thighs run to 0.15-0.22 h (Pluto, Freya, Aphrodite, the smith, the
# Centurion's tunic).
ROBE_LEG_RADIUS = {"upleg": 0.09, "leg": 0.09, "foot": 0.07, "toebase": 0.07}
# The same cap on the arm's own surface (`_arm_masks`), by the joint that
# ends the segment: "forearm" ends the upper arm, "hand" the forearm, "grip"
# is the hand's 0.12 h past the wrist. Uncapped, the upper arm's surface is
# the torso flank too (0.18-0.23 h, every family, controls included) and the
# cloak on Heimdall's back stayed with his arms; at 0.08 the smith's mail
# sleeves and Aphrodite's sleeves went to the spine; 0.10 is the design's
# own measured sleeve line (no arm-owned vertex outside the skin within
# 0.09 h of the bone, on all ten). The hand's own skin: 0.03-0.07 h.
ROBE_ARM_RADIUS = {"arm": 0.10, "forearm": 0.10, "hand": 0.06, "grip": 0.06}
# Above the hip line the arm-held cloth goes to the spine and is CUT from the
# arm (0, the design's rule), or — per family, ROBE_OVERRIDES {"upper_blend":
# N} — hands over from the arm to the spine across N rings of mesh, uncut.
# Measured both ways on the ten (2026-09-22): the cut leaves the cloak lying
# on the forearm as shards at the blow frame and opens holes where a coat's
# back was the arm's (the smith, Loki, Pluto's mantle); the blend tents the
# cloak from the raised hand instead (Heimdall at 8 rings). Neither saves a
# garment whose top IS the arm's surface; the cut is the lesser on Heimdall.
ROBE_UPPER_BLEND = 0
# The families the ring is APPLIED to, by name — each admitted only when its
# boards pass (tools/cloth_metrics.py: the flying cloth down 80% on the heavy
# attack, the ring's own triangles under 2x at the 99.9th percentile, its
# seams no worse than the shipped file's, the settled ring within half a
# percent of the height of its bind pose; and on the render boards no tear,
# spike or shard, no leg through the robe, no garment stuck to the hips like
# a board; Docs/PLAN.md *The robe ring*). mesh.py and tools/robe_pass.py
# --all read it.
#
# EMPTY on 2026-09-22, every one of the ten judged and refused. The ring
# does what it was built for below the hips — Pluto's robe, Heimdall's and
# Baldr's cloaks, Aphrodite's skirt panels and Freya's cloak edges stop
# flying (the flying cloth down 81-99% on the heavy attack for eight of
# the nine that take a ring; the Centurion's 10% and Njord's 46%) — but on every board the garment's TOP, lying on the arm's own
# surface, still tears: shards on the raised arm (Heimdall, Baldr, Freya,
# Aphrodite's himation), tattered wings at Pluto's shoulders and his rear
# foot through the back of the robe, holes where the smith's coat and the
# Centurion's tunic were welded to the hand; the Satyr has no lower garment
# and his pelt is held at the hand's middle. The per-family verdicts and
# numbers belong in Docs/PLAN.md *The robe ring*. What would admit one is option D (a concept
# with the hands clear of the cloth) or the design's named second step, a
# clavicle-hung cloak-edge chain with arm capsules.
ROBE_FAMILIES = ()
# Per family: {"sectors_off": ["fl", ...], "upper_blend": rings}. The safety valve.
ROBE_OVERRIDES = {}
assert not set(ROBE_FAMILIES) & set(SKIRT_FAMILIES), "a family is either the skirt pass's or the robe ring's"


def _arm_masks(char, P=None, normals=None, radius=None):
    """The arm's own LAYER (1.8x the innermost surface, a 1.2% gap) and its
    tighter SKIN (1.2x, a 0.6% gap) round the upper arm, the forearm and the
    hand — the hand a segment continued 0.12 h past the wrist, since Meshy's
    rigs have no finger bones — exactly as `reweight_skirt` measures them.
    Returns (layer, skin, armkind) with armkind a per-joint bool.

    `radius` ({"arm": h-share, "forearm": …, "hand": …, "grip": …}, keyed by
    the kind of the joint that ENDS the segment, "grip" the hand's segment
    past the wrist) caps how far from its bone the arm's own surface can lie.
    Uncapped, the upper arm's layer is the torso flank as well — its 90th
    percentile lies 0.18-0.23 h from the bone on every family measured, the
    controls included — which is harmless to the skirt pass and gave the
    cloak lying on Heimdall's back to his arms in the robe ring's first cut."""
    leaf = [j.split("/")[-1] for j in char.joints]
    kind = [_bone_kind(l) for l in leaf]
    J = len(leaf)
    jw = np.array([char.bind[i][3, :3] for i in range(J)], dtype=np.float64)
    if P is None:
        P = char.points.astype(np.float64)
    height = float(P[:, 1].max() - P[:, 1].min())
    if normals is None:
        normals = vertex_normals(P, char.faces).astype(np.float64)
    armkind = np.array([k in ("arm", "forearm") or k.startswith("hand") for k in kind])
    segments, hand_segments = [], []
    for j, p in enumerate(char.parents):
        if p >= 0 and armkind[j]:
            segments.append((jw[p], jw[j], "hand" if kind[j].startswith("hand") else kind[j]))
            if kind[j] == "hand":
                u = jw[j] - jw[p]
                norm = float(np.linalg.norm(u))
                if norm > 1e-6:
                    hand_segments.append((jw[j], jw[j] + u / norm * 0.12 * height, "grip"))
    segments += hand_segments
    layer = np.zeros(len(P), bool)
    skin = np.zeros(len(P), bool)
    for a, b, k in segments:
        near = np.ones(len(P), bool)
        if radius is not None and k in radius:
            ab = b - a
            t = np.clip(((P - a) @ ab) / max(float(ab @ ab), 1e-12), 0.0, 1.0)
            near = np.linalg.norm(P - (a + t[:, None] * ab), axis=1) <= radius[k] * height
        layer |= near & _limb_surface(P, normals, a, b, reach=0.25 * height, gap=0.012 * height, inward_stop=False)
        skin |= near & _limb_surface(P, normals, a, b, reach=0.25 * height, gap=0.006 * height, slack=1.2,
                                     inward_stop=False)
    return layer, skin, armkind


def robe_joint_plan(char):
    """The robe joints a char carries, in skeleton order, as (leaf, parent
    leaf, bind position) — what the LOD must append, the same names in the
    same order at the same places, before it can take the base's weights."""
    leaf = [j.split("/")[-1] for j in char.joints]
    out = []
    for i, n in enumerate(leaf):
        if n.startswith("robe_"):
            out.append((n, leaf[int(char.parents[i])], char.bind[i][3, :3].astype(np.float64).copy()))
    return out


def append_robe_joints(char, plan):
    """Appends `robe_joint_plan`'s joints to another file of the same family
    (the LOD), parents by leaf name. Returns the count appended."""
    leaf = {j.split("/")[-1]: i for i, j in enumerate(char.joints)}
    n = 0
    for name, parent, position in plan:
        if name in leaf:
            continue
        leaf[name] = _append_joint(char, name, leaf[parent], position)
        n += 1
    return n


def reweight_robe(char, rings=14, min_sector=80, overrides=None, report=None):
    """Hangs the garment below the hips on the ROBE RING (2026-09-22): the
    lower cloth the resting hands touched in the A-pose, which Meshy's
    rigger bound to those hands — Heimdall's floor-length cloak, Pluto's
    robe, Freya's cloak edges, Baldr's cloak front, the Centurion's tunic —
    and which flew out with every swing (995 to 3,928 vertices more than
    0.3 of the height from where the pelvis alone would carry them at the
    heavy attack). The skirt pass re-bound such cloth to the nearest body
    bone, which for floor-length cloth is ONE LEG, and a robe tore between
    the legs; held rigid to the hips, the legs stab through it. So it gets
    joints of its own, the cape's way.

    (1) The HANG set: below the hip line (hips - 0.02 h), above 0.04 h,
    outside the legs' own surface (`_limb_surface` with the inward stop,
    CAPPED at `ROBE_LEG_RADIUS` from the bone, since a robe with no legs
    modelled inside it is itself the innermost surface), outside the
    pelvis's own surface, outside the arm's layer (capped at
    `ROBE_ARM_RADIUS`, since uncapped it is the torso flank as well), off
    the cape. With it, the arm-held cloth ABOVE the hip line (arm-owned,
    below the neck, outside the arm's layer). The connected pieces of the
    two together are judged by `_held_objects` in the ring's terms (a rod
    under `ROBE_ROD_WIDTH` across, the hand's rules only on a piece the arm
    owns, the cape counted as the body, `ROBE_WELD_MIN`) — a spear, a
    bident, a hammer stays with the hand, a crumb under 0.8% of the mesh
    stays as it was — and what survives grows back through the arm's layer
    (never its skin), as the skirt pass grows. (2) SECTORS: each hanging
    vertex falls in its nearest `ROBE_SECTORS` sector; a sector under
    `min_sector` vertices is dropped, as is every sector `ROBE_OVERRIDES`
    turns off; with fewer than two there is no ring, and the arm-held cloth
    above the hips alone goes to the spine when there is enough of it.
    (3) JOINTS: per sector, `ROBE_CHAIN` levels evenly from its top (the
    hip line or the 97th percentile of its height, the lower) to a step
    above its hem (the 3rd percentile), each at the sector's azimuth and at
    the MEDIAN radial distance of its hanging vertices within 0.06 h of the
    level. (4) WEIGHTS: bilinear — by angle between the two neighbouring
    present chains (never across a forward gap over 90°: there the nearer
    chain alone) and by height between the two levels bracketing the
    vertex — so four; above a chain's first level the collar blends into
    Hips, below its last the last joint alone. The arm-held cloth above the
    hip line goes to the two spine joints bracketing its height with no arm
    in it (or, per family, hands over from the arm across `upper_blend`
    rings, uncut). Every arm-owned row below the hips outside the arm's
    skin that is not a thing held (the ORPHANS: Heimdall's hem on his shin)
    takes its nearest non-arm row's weights. (5) The body-owned rows within
    14 rings lose their arm share, the seam is averaged over `rings` rings
    (14: at 4 the ring-to-thigh seam of Loki's coat stretched 37x) with the
    arm's own rows left out, ISLANDS of arm-held rows cut off from every arm
    joint's own stretch of mesh go with the cloth, and the weld with every
    row the arm still holds — and nothing else — is cut (`cut_seam(...,
    against=)`). Returns the number of vertices re-bound; the masks are
    left on `char._robe_sets` for the boards and the metrics."""
    if not char.skinned or not len(char.faces):
        return 0
    say = report if report is not None else print
    ov = dict((overrides if overrides is not None else ROBE_OVERRIDES.get(char.name.lower(), {})) or {})
    leaf = [j.split("/")[-1] for j in char.joints]
    kind = [_bone_kind(l) for l in leaf]
    if any(l.startswith("robe_") for l in leaf):
        say("    robe: the ring is already there; left as it is")
        return 0
    lower = {n.lower(): i for i, n in enumerate(leaf)}
    if "hips" not in lower:
        return 0
    hips = lower["hips"]
    upper_blend = int(ov.get("upper_blend", ROBE_UPPER_BLEND))
    J = len(leaf)
    jw = np.array([char.bind[i][3, :3] for i in range(J)], dtype=np.float64)
    P = char.points.astype(np.float64)
    N = len(P)
    height = float(P[:, 1].max() - P[:, 1].min())
    hx, hy, hz = jw[hips]
    hip_line = hy - 0.02 * height
    neck = next((lower[n] for n in ("neck", "head") if n in lower), None)
    neck_y = float(jw[neck][1]) if neck is not None else float(P[:, 1].max())
    owner = np.asarray(char.joint_indices)[np.arange(N), np.argmax(char.joint_weights, axis=1)]
    normals = vertex_normals(P, char.faces).astype(np.float64)
    W = np.zeros((N, J), dtype=np.float64)
    rows = np.arange(N)[:, None]
    np.add.at(W, (np.broadcast_to(rows, char.joint_indices.shape), char.joint_indices), char.joint_weights.astype(np.float64))
    # (1) The masks.
    legs = np.zeros(N, bool)
    for j, p in enumerate(char.parents):
        if p >= 0 and kind[j] in ROBE_LEG_RADIUS:
            a, b = jw[p], jw[j]
            ab = b - a
            t = np.clip(((P - a) @ ab) / max(float(ab @ ab), 1e-12), 0.0, 1.0)
            near = np.linalg.norm(P - (a + t[:, None] * ab), axis=1) <= ROBE_LEG_RADIUS[kind[j]] * height
            legs |= near & _limb_surface(P, normals, a, b, reach=0.25 * height, gap=0.012 * height, inward_stop=True)
    uplegs = [i for i, k in enumerate(kind) if k == "upleg"]
    crotch = np.array([hx, float(np.mean([jw[i][1] for i in uplegs])) if uplegs else hy - 0.1 * height, hz])
    pelvis = _limb_surface(P, normals, crotch, jw[hips], reach=0.25 * height, gap=0.012 * height, inward_stop=True)
    arm_layer, arm_skin, armkind = _arm_masks(char, P, normals, radius=ROBE_ARM_RADIUS)
    capek = np.array([l.startswith("cape_") for l in leaf])
    cape_w = W[:, capek].sum(axis=1) if capek.any() else np.zeros(N)
    below = (P[:, 1] < hip_line) & (P[:, 1] > 0.04 * height)
    hang0 = below & ~legs & ~pelvis & ~arm_layer & (cape_w < 0.2)
    upper0 = armkind[owner] & (P[:, 1] >= hip_line) & (P[:, 1] < neck_y) & ~arm_layer & (cape_w < 0.2)
    min_count = max(40, int(round(0.008 * N)))
    held, cloth, refused = _held_objects(P, char.faces, normals, hang0 | upper0, owner, kind, jw, char.parents,
                                         height, armkind[owner] & arm_layer, min_count, rod_width=ROBE_ROD_WIDTH,
                                         weld_min=ROBE_WELD_MIN, arm_owned=armkind[owner], arm_share=0.5,
                                         cape_is_body=True)
    if refused:
        say(f"    robe: left with the hand — {'; '.join(refused)}")
    key, canon, e = _welded_edges(P, char.faces)
    C = len(key)
    e_u = np.unique(np.sort(e, axis=1), axis=0)
    # Grown back through the arm's layer, never its skin: the cloth's own
    # rows nearest the hand (as the skirt pass grows).
    pool = arm_layer & ~arm_skin & ~held & (cape_w < 0.2) & (
        (armkind[owner] & (P[:, 1] < neck_y)) | (below & ~legs & ~pelvis))
    if cloth.any() and pool.any():
        pool_c = np.zeros(C, bool); pool_c[canon[pool]] = True
        seen = np.zeros(C, bool); seen[canon[cloth]] = True
        frontier = seen.copy()
        for _ in range(60):
            hit = frontier[e_u[:, 0]] | frontier[e_u[:, 1]]
            step = np.zeros(C, bool)
            step[e_u[hit, 0]] = True; step[e_u[hit, 1]] = True
            step &= pool_c & ~seen
            if not step.any():
                break
            seen |= step
            frontier = step
        grown = pool & seen[canon] & ~cloth
        if grown.any():
            say(f"    robe: {int(grown.sum()):,} rows of the cloth inside the hand's layer go with it")
            cloth |= grown
    hang = cloth & below
    spine_set = cloth & (P[:, 1] >= hip_line)
    if int(hang.sum()) < min_count and int(spine_set.sum()) < min_count:
        return 0
    # (2) Sectors.
    names = [n for n, _ in ROBE_SECTORS]
    az = np.array([a for _, a in ROBE_SECTORS])
    theta = np.degrees(np.arctan2(P[:, 0] - hx, P[:, 2] - hz))
    diff = (theta[:, None] - az[None, :] + 180.0) % 360.0 - 180.0
    nearest = np.argmin(np.abs(diff), axis=1)
    counts = np.bincount(nearest[hang], minlength=len(names))
    off = set(ov.get("sectors_off", ()))
    present = [s for s in range(len(names)) if counts[s] >= min_sector and names[s] not in off]
    say("    robe: sectors " + ", ".join(f"{names[s]} {int(counts[s]):,}" for s in range(len(names)))
        + f" (kept {' '.join(names[s] for s in present) or 'none'})")
    ringless = len(present) < 2
    if ringless:
        # No lower garment to hang (the Satyr's goat legs carry a pelt across
        # the belly, above the hip line): the arm-held cloth above the hips
        # still goes to the spine when there is enough of it; the rows below
        # the hips are left to the orphan rule.
        if int(spine_set.sum()) < min_count:
            say("    robe: fewer than two sectors hang and too little arm-held cloth above the hips; left as rigged")
            return 0
        say("    robe: fewer than two sectors hang — no ring; the arm-held cloth above the hips goes to the spine")
        hang = np.zeros(N, bool)
        present = []
    # (3) The joints, sector by sector in the fixed order.
    theta_h = theta[hang]
    # Each hanging vertex's two neighbouring present chains, by FORWARD
    # azimuth in the sector order (0, 45, … 315).
    fwd = np.array([az[s] % 360.0 for s in present])
    t360 = theta_h % 360.0
    after = np.searchsorted(fwd, t360, side="right")          # the first present sector past the vertex
    a_i = (after - 1) % max(len(present), 1)
    b_i = after % max(len(present), 1)
    gap = (fwd[b_i] - fwd[a_i]) % 360.0
    into = (t360 - fwd[a_i]) % 360.0
    w_theta = np.where(gap > 1e-6, into / np.maximum(gap, 1e-6), 0.0)
    wide = gap > 90.0 + 1e-6
    # Across a gap wider than 90° the nearer chain alone.
    w_theta = np.where(wide, (into > gap - into).astype(float), w_theta)
    # Which vertices each chain carries at all (its share > 0), for its levels.
    first = len(char.joints)
    chains = {}
    Ph = P[hang]
    radial = np.hypot(Ph[:, 0] - hx, Ph[:, 2] - hz)
    for ci, s in enumerate(present):
        members = ((a_i == ci) & (w_theta < 1.0)) | ((b_i == ci) & (w_theta > 0.0))
        near = nearest[hang] == s
        pick = near if near.sum() >= 5 else members
        ys = Ph[pick, 1]
        y_top = min(hip_line, float(np.percentile(ys, 97)))
        y_hem = float(np.percentile(ys, 3))
        levels = np.array([y_top - k * (y_top - y_hem) / ROBE_CHAIN for k in range(ROBE_CHAIN)])
        phi = np.radians(az[s])
        parent = hips
        ids = []
        for k, yk in enumerate(levels):
            band_k = pick & (np.abs(Ph[:, 1] - yk) < 0.06 * height)
            r = float(np.median(radial[band_k])) if band_k.sum() >= 5 else float(np.median(radial[pick]))
            pos = np.array([hx + r * np.sin(phi), yk, hz + r * np.cos(phi)])
            parent = _append_joint(char, f"robe_{names[s]}_{k}", parent, pos)
            ids.append(parent)
        chains[ci] = (levels, ids, float(Ph[pick, 1].max()))
    J2 = len(char.joints)
    W = np.concatenate([W, np.zeros((N, J2 - J))], axis=1)
    W0 = W.copy()
    # (4) The weights.
    rows_h = np.flatnonzero(hang)
    yv = P[rows_h, 1]
    W[rows_h] = 0.0

    def height_share(ci, share, sel):
        levels, ids, top = chains[ci]
        r = rows_h[sel]; y = yv[sel]; w = share[sel]
        above = y >= levels[0]
        under = y <= levels[-1]
        mid = ~above & ~under
        upper = np.clip(np.searchsorted(-levels, -y, side="right") - 1, 0, ROBE_CHAIN - 2)
        t = np.clip((levels[upper] - y) / np.maximum(levels[upper] - levels[upper + 1], 1e-6), 0.0, 1.0)
        ids_a = np.array(ids)
        np.add.at(W, (r[mid], ids_a[upper[mid]]), w[mid] * (1.0 - t[mid]))
        np.add.at(W, (r[mid], ids_a[upper[mid] + 1]), w[mid] * t[mid])
        np.add.at(W, (r[under], np.full(int(under.sum()), ids[-1])), w[under])
        collar = np.clip((y - levels[0]) / max(max(top, hip_line) - levels[0], 1e-6), 0.0, 1.0)
        np.add.at(W, (r[above], np.full(int(above.sum()), ids[0])), w[above] * (1.0 - collar[above]))
        np.add.at(W, (r[above], np.full(int(above.sum()), hips)), w[above] * collar[above])

    everyone = np.ones(len(rows_h), bool)
    for ci in range(len(present)):
        share_a = np.where(a_i == ci, 1.0 - w_theta, 0.0)
        share_b = np.where(b_i == ci, w_theta, 0.0)
        share = share_a + share_b
        height_share(ci, share, everyone & (share > 0))
    # The arm-held cloth above the hip line: the spine joints bracketing its
    # height, blended by height, no arm in it.
    spine_names = [n for n in ("hips", "spine", "spine01", "spine1", "spine02", "spine2", "spine03", "spine3", "neck")
                   if n in lower]
    if spine_set.any() and len(spine_names) >= 2:
        sp = np.array([lower[n] for n in spine_names])
        sy = jw[sp, 1]
        o = np.argsort(sy); sp, sy = sp[o], sy[o]
        rows_s = np.flatnonzero(spine_set)
        y = P[rows_s, 1]
        lo = np.clip(np.searchsorted(sy, y, side="right") - 1, 0, len(sp) - 2)
        t = np.clip((y - sy[lo]) / np.maximum(sy[lo + 1] - sy[lo], 1e-6), 0.0, 1.0)
        W[rows_s] = 0.0
        np.add.at(W, (rows_s, sp[lo]), 1.0 - t)
        np.add.at(W, (rows_s, sp[lo + 1]), t)
    sheet = hang | spine_set
    # Nothing below the hips stays the arm's unless it is the arm's own skin
    # or a thing the hand holds: the hem rows Meshy gave to a hand that lie
    # in the legs' own surface (Heimdall's cloak at the shin, 0.21 h, the
    # worst edges of the first cut at 146x their length) and the crumbs too
    # small to judge take their nearest non-arm row's weights, the arm out.
    orphans = armkind[owner] & below & ~arm_skin & ~held & ~sheet
    if orphans.any():
        from scipy.spatial import cKDTree
        donors = np.flatnonzero((sheet | ~armkind[owner]) & ~orphans)
        _, near = cKDTree(P[donors]).query(P[orphans], k=1)
        W[orphans] = W[donors[near]]
        wo = W[orphans]
        wo[:, np.flatnonzero(armkind)] = 0.0
        wo /= np.maximum(wo.sum(axis=1, keepdims=True), 1e-9)
        W[orphans] = wo
        say(f"    robe: {int(orphans.sum()):,} arm-owned rows below the hips, outside the hand, take their "
            f"nearest non-arm neighbour's weights")
        sheet = sheet | orphans
    # (5) The garment's body-owned rows beside the sheet lose their arm share
    # (the rigger's blend zone, as the skirt pass), never the arm's skin.
    arm_cols = np.flatnonzero(np.concatenate([armkind, np.zeros(J2 - J, bool)]))
    body_cols = np.setdiff1d(np.arange(J2), arm_cols)
    bodykind = np.array([k in ("hips", "spine", "spine01", "spine1", "spine02", "spine2", "spine03", "spine3",
                               "neck", "upleg", "leg") for k in kind])

    def strip_arm(rws):
        w = W[rws]
        keep = w[:, body_cols].sum(axis=1) > 1e-6
        w[np.ix_(keep, arm_cols)] = 0.0
        w[keep] /= w[keep].sum(axis=1, keepdims=True)
        W[rws] = w

    zone_ok = np.zeros(C, bool)
    np.logical_or.at(zone_ok, canon, bodykind[owner] & ~arm_skin & ~sheet)
    seen = np.zeros(C, bool); seen[canon[sheet]] = True
    frontier = seen.copy()
    reached = np.zeros(C, bool)
    for _ in range(14):
        hit = frontier[e_u[:, 0]] | frontier[e_u[:, 1]]
        step = np.zeros(C, bool)
        step[e_u[hit, 0]] = True; step[e_u[hit, 1]] = True
        step &= zone_ok & ~seen
        if not step.any():
            break
        seen |= step; reached |= step
        frontier = step
    stripped = reached[canon] & (W[:, arm_cols].sum(axis=1) > 0.02)
    if upper_blend:
        stripped &= below
    if stripped.any():
        strip_arm(stripped)
        say(f"    robe: {int(stripped.sum()):,} rows of the garment beside it lose their share of the arm")
    # The seam: averaged over `rings` rings of the welded mesh, the arm's own
    # rows left out of the averaging and the body's rows fixed.
    if rings > 0:
        arm_c = np.zeros(C, bool)
        np.logical_or.at(arm_c, canon, armkind[owner] & ~sheet)
        e_b = e_u[~arm_c[e_u[:, 0]] & ~arm_c[e_u[:, 1]]]
        Wc = np.zeros((C, J2)); cnt = np.zeros(C)
        np.add.at(Wc, canon, W); np.add.at(cnt, canon, 1.0)
        Wc /= np.maximum(cnt, 1.0)[:, None]
        sheet_c = np.zeros(C, bool); sheet_c[canon[sheet]] = True
        deg = np.zeros(C); np.add.at(deg, e_b[:, 0], 1.0); np.add.at(deg, e_b[:, 1], 1.0)
        for _ in range(rings):
            acc = Wc.copy()
            np.add.at(acc, e_b[:, 0], Wc[e_b[:, 1]]); np.add.at(acc, e_b[:, 1], Wc[e_b[:, 0]])
            acc /= (deg + 1.0)[:, None]
            Wc[sheet_c] = acc[sheet_c]
        W[sheet] = Wc[canon[sheet]]
    # Above the hip line the cloth is NOT cut from the arm: it hands over
    # from the arm to the spine across `ROBE_UPPER_BLEND` rings of mesh from
    # the rows the arm keeps. A hard spine binding with the weld cut punched
    # holes in the smith's back, Loki's coat and Pluto's mantle and left
    # shards on Heimdall's shoulders at the blow frame (2026-09-22); a cloak
    # lying on the upper arm lifts a little with it, as cloth does.
    if spine_set.any() and upper_blend > 0:
        kept_c = np.zeros(C, bool)
        np.logical_or.at(kept_c, canon, armkind[owner] & ~sheet)
        spine_c = np.zeros(C, bool); spine_c[canon[spine_set]] = True
        dist = np.full(C, np.inf); dist[kept_c] = 0.0
        frontier = kept_c.copy()
        for ring in range(1, upper_blend + 1):
            hit = frontier[e_u[:, 0]] | frontier[e_u[:, 1]]
            step = np.zeros(C, bool)
            step[e_u[hit, 0]] = True; step[e_u[hit, 1]] = True
            step &= spine_c & ~np.isfinite(dist)
            if not step.any():
                break
            dist[step] = ring
            frontier = step
        share = np.clip(dist[canon[spine_set]] / (upper_blend + 1.0), 0.0, 1.0)[:, None]
        W[spine_set] = share * W[spine_set] + (1.0 - share) * W0[spine_set]
    # Islands: rows the arm still holds that are NOT the arm — cut off from
    # every arm joint's own stretch of mesh, bordering the re-bound cloth,
    # not a thing held — are cloth the capped masks left behind (a strip of
    # Pluto's mantle over the shoulder, 76 and 72 rows); cut, each would be
    # a shard riding the arm. They take their nearest re-bound row's weights.
    arm_now0 = (W * np.concatenate([armkind, np.zeros(J2 - J, bool)])[None, :]).sum(axis=1)
    kept = ((arm_now0 > 0.5) | armkind[owner]) & ~sheet & ~held
    if kept.any() and sheet.any():
        from scipy.sparse import coo_matrix
        from scipy.sparse.csgraph import connected_components
        from scipy.spatial import cKDTree
        kept_c = np.zeros(C, bool); np.logical_or.at(kept_c, canon, kept)
        sheet_c2 = np.zeros(C, bool); np.logical_or.at(sheet_c2, canon, sheet)
        e_k = e_u[kept_c[e_u[:, 0]] & kept_c[e_u[:, 1]]]
        lab = connected_components(coo_matrix((np.ones(len(e_k)), (e_k[:, 0], e_k[:, 1])), shape=(C, C)),
                                   directed=False)[1]
        rows_k = np.flatnonzero(kept_c)
        tree = cKDTree(key[rows_k])
        anchors = set()
        for j in np.flatnonzero(armkind):
            p = int(char.parents[j])
            for at in (jw[j], 0.5 * (jw[j] + jw[p])):
                _, q = tree.query(at)
                anchors.add(int(lab[rows_k[q]]))
        border = e_u[kept_c[e_u[:, 0]] ^ kept_c[e_u[:, 1]]]
        inner = np.where(kept_c[border[:, 0]], border[:, 0], border[:, 1])
        outer = np.where(kept_c[border[:, 0]], border[:, 1], border[:, 0])
        touches = np.zeros(C, bool)
        touches[inner[sheet_c2[outer]]] = True
        island_labels = set(np.unique(lab[touches & kept_c]).tolist()) - anchors
        if island_labels:
            island = kept & np.isin(lab[canon], list(island_labels))
            donors = np.flatnonzero(sheet)
            _, near = cKDTree(P[donors]).query(P[island], k=1)
            W[island] = W[donors[near]]
            say(f"    robe: {int(island.sum()):,} rows of cloth in {len(island_labels)} islands the arm held go with it")
            sheet = sheet | island
    K = char.joint_indices.shape[1]
    ji_before, jw_before = char.joint_indices.copy(), char.joint_weights.copy()
    changed = sheet | stripped
    top = np.argsort(-W[changed], axis=1)[:, :K]
    wt = np.take_along_axis(W[changed], top, axis=1)
    wt /= np.maximum(wt.sum(axis=1, keepdims=True), 1e-9)
    top[wt <= 0] = 0
    char.joint_indices[changed] = top.astype(char.joint_indices.dtype)
    char.joint_weights[changed] = wt.astype(char.joint_weights.dtype)
    # The cut runs wherever the re-bound cloth meets a row the ARM still
    # holds — its skin, a thing held, a sleeve left on the forearm — and
    # nowhere else (the legs and the torso are the seam blend's). The first
    # cut ran against the hand's skin alone and left the welds to the held
    # pieces whole: the Satyr's pelt end, the smith's tongs, Loki's knives
    # stretched to 40-170 times their length with the ring or without it.
    arm_now = (np.asarray(char.joint_weights, np.float64)
               * np.concatenate([armkind, np.zeros(J2 - J, bool)])[char.joint_indices]).sum(axis=1)
    arm_cols2 = np.concatenate([armkind, np.zeros(J2 - J, bool)])
    owner_now = char.joint_indices[np.arange(N), np.argmax(char.joint_weights[:N], axis=1)]
    against = ((arm_now > 0.5) | arm_cols2[owner_now]) & ~changed
    cut = cut_seam(char, (changed & below) if upper_blend else changed, ji_before, jw_before, against=against)
    if cut:
        say(f"    robe: the weld with what the arm keeps cut, {cut:,} vertices doubled")
    was = {}
    for o in owner[sheet]:
        was[leaf[o]] = was.get(leaf[o], 0) + 1
    was = ", ".join(f"{k} {v:,}" for k, v in sorted(was.items(), key=lambda kv: -kv[1])[:4])
    say(f"    robe: {int(hang.sum()):,} of {N:,} vertices hang on {len(present)} chains "
        f"({', '.join('robe_' + names[s] for s in present)}), {int(spine_set.sum()):,} arm-held above the hips "
        f"to the spine (were {was}), the seam blended over {rings} rings")
    char._robe_sets = dict(hang=hang, spine=spine_set, stripped=stripped, held=held, orphans=orphans,
                           changed=changed, n0=N)
    return int(sheet.sum())


def reproportion(char, scales, height=None, fit=None):
    """Scales named joints (by their leaf name) about their own origins or
    along their bones, bakes the skinned result into the points, and
    rebuilds the skeleton WITHOUT the scale: every joint keeps its
    rotation, a scaled joint's children move to where the scale put them,
    and the clips' translation channels for those children follow. Then
    the figure is stood back on the origin at `height` (or moved by the
    base model's `fit`, so a clip carrier lands exactly where its base
    did). Returns the fit applied."""
    if not char.skinned:
        return fit
    J = len(char.joints)
    leaf = [j.split("/")[-1] for j in char.joints]
    spec = {i: scales[name] for i, name in enumerate(leaf) if name in scales}
    if not spec:
        return fit
    children = {i: [c for c in range(J) if char.parents[c] == i] for i in range(J)}
    local = local_from_world(char.bind, char.parents)
    # Two transforms per joint: the one its OWN vertices are skinned with
    # (the scale included) and the one its children hang from (a uniform
    # scale is inherited; a lengthening is not - the subtree below a longer
    # bone is only moved along it).
    skin_world = np.empty_like(char.bind)
    hang_world = np.empty_like(char.bind)
    local_new = local.copy()
    t_factor = np.ones((J, 3))     # per joint: what its local translation was multiplied by
    for i in range(J):
        parent_hang = np.eye(4) if char.parents[i] < 0 else hang_world[char.parents[i]]
        li = local[i].copy()
        if char.parents[i] >= 0 and isinstance(spec.get(char.parents[i]), dict):
            # A child of a lengthened bone is moved out along it; of a
            # narrowed one, in across it.
            pspec = spec[char.parents[i]]
            pk = children[char.parents[i]]
            u = local[pk[0]][3, :3] if pk else np.array([0.0, 1.0, 0.0])
            u = u / max(np.linalg.norm(u), 1e-9)
            t = local[i][3, :3]
            tp = np.dot(t, u) * u
            new_t = pspec.get("length", 1.0) * tp + pspec.get("width", 1.0) * (t - tp)
            li[3, :3] = new_t
            safe = np.abs(t) > 1e-6
            t_factor[i] = np.where(safe, new_t / np.where(safe, t, 1.0), 1.0)
        local_new[i] = li
        plain = li @ parent_hang
        sc = spec.get(i)
        if sc is None:
            skin_world[i] = plain
            hang_world[i] = plain
        elif isinstance(sc, dict):
            kids = children[i]
            u = local[kids[0]][3, :3] if kids else np.array([0.0, 1.0, 0.0])
            u = u / max(np.linalg.norm(u), 1e-9)
            L = sc.get("length", 1.0)
            W = sc.get("width", 1.0)
            stretch = np.eye(4)
            # Along the bone by L, across it by W, in the joint's own space.
            stretch[:3, :3] = np.eye(3) + (L - 1.0) * np.outer(u, u) + (W - 1.0) * (np.eye(3) - np.outer(u, u))
            skin_world[i] = stretch @ plain
            hang_world[i] = plain
        else:
            scaled = np.diag([sc, sc, sc, 1.0]) @ li @ parent_hang
            skin_world[i] = scaled
            hang_world[i] = scaled      # a uniform scale is inherited by the children
    baked = skin(char.points.astype(np.float64), char.joint_indices, char.joint_weights.astype(np.float64),
                 char.bind, skin_world)
    # The skeleton without any scale: the old rotation, the new position.
    bind_new = char.bind.copy()
    for i in range(J):
        bind_new[i][3, :3] = hang_world[i][3, :3]
    char.points = baked.astype(np.float32)
    char.bind = bind_new
    char.rest_local = local_from_world(bind_new, char.parents)
    if char.anim:
        a = char.anim
        for i in range(J):
            p = char.parents[i]
            if p >= 0 and isinstance(spec.get(p), (int, float)):
                a["T"][:, i, :] *= spec[p]
            elif not np.allclose(t_factor[i], 1.0):
                a["T"][:, i, :] *= t_factor[i]
    # Back on the ground at the asked height (the head shrank, the legs
    # grew, the feet lifted the soles), or exactly as the base went.
    if fit is None:
        lo, hi = bounds(char.points.astype(np.float64))
        h = hi[1] - lo[1]
        s2 = (height / h) if height else 1.0
        t2 = np.array([-(lo[0] + hi[0]) * 0.5 * s2, -lo[1] * s2, -(lo[2] + hi[2]) * 0.5 * s2])
        fit = {"s": float(s2), "t": t2}
        def word(k, v):
            if not isinstance(v, dict):
                return f"{k} x{v}"
            parts = []
            if "length" in v:
                parts.append(f"+{int(round((v['length'] - 1) * 100))}% long")
            if "width" in v:
                parts.append(f"x{v['width']} wide")
            return f"{k} " + " ".join(parts)
        words = ", ".join(word(k, v) for k, v in scales.items() if k in leaf)
        print(f"    proportions: {words}; height {h:.3f} -> {h * s2:.3f}")
    apply_similarity(char, np.eye(3), fit["s"], fit["t"])
    return fit


def ground_animation(char, tolerance=0.005):
    """Shifts a clip vertically so its typical frame stands on y = 0.
    Retargeted library clips float or sink by a few centimetres because the
    library's rig and this one disagree about leg length. The median of the
    per-frame lowest point is used: a standing clip is planted in most frames
    and only dips in a few, and a fall spends most of its frames lying down,
    so the median grounds the pose the player actually sees."""
    if not (char.skinned and char.anim):
        return 0.0
    frames = len(char.anim["T"])
    # The feet decide while the figure is on its feet, not the whole mesh:
    # the Fox Spirit's nine tails are weighted to a thigh and swing 24 cm
    # below the floor in her idle, and a clip grounded on its lowest vertex
    # stood her that far in the air. A frame with the pelvis below 45% of
    # its rest height is a figure lying down (a death, a knockdown), and
    # there the body's lowest point is what touches, as before - grounding
    # a corpse on its soles would sink Pluto's robe 16 cm into the floor.
    # Lying down, the legs are left out of the measure as well: a skirt, a
    # robe or a tail is weighted to a thigh, and a thigh turned flat swings it
    # through the floor (the Fox Spirit's tails, 55 cm under in her death),
    # while the torso, the head, the arms and the feet are all on the ground.
    feet = foot_vertices(char)
    body = body_without_legs(char)
    pelvis = pelvis_index(char)
    rest_hip = char.joint_world_at_rest()[pelvis][3, 1] if pelvis is not None else 0.0
    floor, on_feet = [], 0
    for f in range(frames):
        world = char.joint_world_at(f)
        sp = char.skinned_points(world)
        standing = feet is not None and pelvis is not None and world[pelvis][3, 1] >= 0.45 * rest_hip
        floor.append(sp[feet, 1].min() if standing else sp[body if body is not None else slice(None), 1].min())
        on_feet += standing
    floor = np.array(floor)
    which = "the feet" if on_feet > frames / 2 else ("the body lying down, legs left out" if body is not None else "the whole mesh")
    # The median frame, not the lowest: a standing clip has its feet planted in
    # most frames and dips in a few, and a fall spends most of its frames on
    # the ground. Either way the typical frame is the one that must touch.
    shift = float(np.median(floor))
    if abs(shift) <= tolerance:
        return 0.0
    for j in np.where(char.parents < 0)[0]:
        char.anim["T"][:, j, 1] -= shift
    print(f"    clip grounded by {-shift:+.3f} m on {which} (typical frame stood at y={shift:+.3f}; "
          f"lowest {floor.min():+.3f}, highest {floor.max():+.3f})")
    return shift


def pelvis_index(char):
    """The joint whose height says whether the figure is standing: the one
    named Hips or pelvis, else the highest-standing root joint; None for a
    rig without joints."""
    if not len(char.joints):
        return None
    for i, j in enumerate(char.joints):
        if j.rsplit("/", 1)[-1].lower() in ("hips", "pelvis", "hip"):
            return i
    roots = np.where(char.parents < 0)[0]
    rest = char.joint_world_at_rest()
    return int(max(roots, key=lambda j: rest[j][3, 1]))


def body_without_legs(char, minimum=12):
    """A mask of the vertices whose heaviest joint is not a leg (the feet and
    toes stay in), for measuring a figure lying down; None when the rig has
    no leg joints or too few vertices would remain."""
    if not char.skinned or not len(char.joints):
        return None
    legs = np.array(["leg" in j.rsplit("/", 1)[-1].lower() for j in char.joints])
    if not legs.any():
        return None
    dominant = char.joint_indices[np.arange(len(char.joint_indices)), char.joint_weights.argmax(axis=1)]
    mask = ~legs[dominant]
    return mask if mask.sum() >= minimum else None


def foot_vertices(char, minimum=12):
    """A mask of the vertices whose heaviest joint is a foot or a toe, or None
    when the rig has no such joints or too few vertices follow them (a beast,
    a hovering spirit, a rig with other names) - then the whole mesh stands in."""
    if not char.skinned or not len(char.joints):
        return None
    feet = np.array([j.rsplit("/", 1)[-1].lower().endswith(("foot", "toebase", "toe", "toe_end", "foot_end"))
                     for j in char.joints])
    if not feet.any():
        return None
    dominant = char.joint_indices[np.arange(len(char.joint_indices)), char.joint_weights.argmax(axis=1)]
    mask = feet[dominant]
    return mask if mask.sum() >= minimum else None


def smoothstep(x):
    x = min(1.0, max(0.0, x))
    return x * x * (3 - 2 * x)


def looks_like_a_fall(char):
    """True when a clip leaves the ground or ends lying down: a knock-up or a
    knockdown, not the flinch a hit reaction is meant to be."""
    if not (char.skinned and char.anim):
        return False
    lo, hi = bounds(char.points.astype(np.float64))
    standing = hi[1] - lo[1]
    frames = len(char.anim["T"])
    feet, heights = [], []
    for f in range(0, frames, max(1, frames // 24)):
        sp = char.skinned_points(char.joint_world_at(f))
        feet.append(sp[:, 1].min())
        heights.append(sp[:, 1].max() - sp[:, 1].min())
    last = char.skinned_points(char.joint_world_at(frames - 1))
    return max(feet) > 0.35 * standing or (last[:, 1].max() - last[:, 1].min()) < 0.6 * standing


def synthesize_flinch(source, duration=0.45, fps=30.0, recoil=0.06):
    """A hit reaction built from a clip's first frame: the torso and head pitch
    back, the hips give a few centimetres, and everything eases home in under
    half a second. It exists because the hit reaction Meshy's library offered
    was a knock-up, and a character launched into the air on every hit is not a
    fight anyone can read. The source is the combat idle when there is one,
    the bind pose otherwise."""
    char = copy.deepcopy(source)
    J = len(char.joints)
    if char.anim:
        t0, r0, s0 = char.anim["T"][0].copy(), char.anim["R"][0].copy(), char.anim["S"][0].copy()
    else:
        parts = [decompose(m) for m in char.rest_local]
        t0 = np.array([q[0] for q in parts]); r0 = np.array([q[1] for q in parts]); s0 = np.array([q[2] for q in parts])
    world0 = world_from_local(np.array([trs(t0[j], r0[j], s0[j]) for j in range(J)]), char.parents)
    frames = max(4, int(round(duration * fps)) + 1)
    peak = {"spine": 5.0, "spine1": 5.0, "spine2": 6.0, "neck": 4.0, "head": 7.0}     # degrees, matched on the joint's leaf name
    roots = [j for j in range(J) if char.parents[j] < 0]
    head = char.joint_index("Head")

    def build(sign):
        T = np.tile(t0, (frames, 1, 1)); R = np.tile(r0, (frames, 1, 1)); S = np.tile(s0, (frames, 1, 1))
        for f in range(frames):
            p = f / (frames - 1)
            amt = smoothstep(p / 0.28) if p < 0.28 else 1 - smoothstep((p - 0.28) / 0.72)
            for j in roots:
                T[f, j] = t0[j] + amt * np.array([0.0, -0.02, -recoil])
            for j, name in enumerate(char.joints):
                # "Spine02", "spine_1" and "Spine" are all the spine.
                deg = peak.get(re.sub(r"[^a-z]", "", name.split("/")[-1].lower()))
                if deg is None:
                    continue
                theta = sign * np.radians(deg) * amt
                rx = quat_to_rot([np.sin(theta / 2), 0.0, 0.0, np.cos(theta / 2)])
                pw = world0[char.parents[j]][:3, :3] if char.parents[j] >= 0 else np.eye(3)
                u, _, vt = np.linalg.svd(pw)
                pw = u @ vt
                delta = pw @ rx @ pw.T
                R[f, j] = rot_to_quat(quat_to_rot(r0[j]) @ delta)
        return {"T": T, "R": R, "S": S, "fps": float(fps)}

    # Whichever sign moves the head backwards (toward -Z, away from the enemy) is the flinch.
    anim = build(-1.0)
    if head is not None:
        char.anim = anim
        dz = char.joint_world_at(frames // 4)[head][3, 2] - world0[head][3, 2]
        if dz > 0:
            anim = build(1.0)
    char.anim = anim
    return char


def limit_influences(char, k=4):
    ji, jw = char.joint_indices.astype(np.int64), char.joint_weights.astype(np.float64)
    if ji.shape[1] > k:
        top = np.argsort(-jw, axis=1)[:, :k]
        rows = np.arange(len(ji))[:, None]
        ji, jw = ji[rows, top], jw[rows, top]
    jw[jw < 0] = 0
    total = jw.sum(axis=1, keepdims=True)
    bad = total[:, 0] <= 1e-8
    jw[bad, 0] = 1.0
    total[bad] = 1.0
    jw /= total
    ji[jw <= 0] = 0
    char.joint_indices, char.joint_weights = ji.astype(np.int32), jw.astype(np.float32)


# ---------------------------------------------------------------------------
# Reduction
# ---------------------------------------------------------------------------

def _meshlab_available():
    try:
        import pymeshlab
    except ImportError:
        return "pymeshlab is not installed (pip install pymeshlab)"
    if not hasattr(pymeshlab.MeshSet(), "meshing_decimation_quadric_edge_collapse_with_texture"):
        return ("pymeshlab loaded without its meshing plugin - it needs libOpenGL.so.0 "
                "(apt-get install libopengl0)")
    return None


def _decimate_meshlab(char, target_tris):
    """MeshLab's quadric edge collapse with texture. It wants the closed
    surface with one UV per face corner (wedge), so the seam-split vertices
    are welded back by position, the corner UVs written beside them to an OBJ
    with a stand-in material (the filter refuses faces that carry no texture
    index), and the result is split at its seams again on the way out."""
    import pymeshlab
    from scipy.spatial import cKDTree
    wpts, _welded, wfaces = weld(char.points, char.faces)
    good = (wfaces[:, 0] != wfaces[:, 1]) & (wfaces[:, 1] != wfaces[:, 2]) & (wfaces[:, 0] != wfaces[:, 2])
    corner_uv = char.uvs[char.faces][good].reshape(-1, 2) if char.uvs is not None else None
    wfaces = wfaces[good]
    work = Path(tempfile.mkdtemp())
    try:
        buf = io.StringIO()
        buf.write("mtllib mesh.mtl\n")
        np.savetxt(buf, wpts, fmt="v %.7f %.7f %.7f")
        if corner_uv is not None:
            np.savetxt(buf, corner_uv, fmt="vt %.7f %.7f")
            corners = np.arange(len(wfaces) * 3).reshape(-1, 3) + 1
            rows = np.c_[wfaces[:, 0] + 1, corners[:, 0], wfaces[:, 1] + 1, corners[:, 1], wfaces[:, 2] + 1, corners[:, 2]]
            buf.write("usemtl atlas\n")
            np.savetxt(buf, rows, fmt="f %d/%d %d/%d %d/%d")
        else:
            np.savetxt(buf, wfaces + 1, fmt="f %d %d %d")
        (work / "mesh.obj").write_text(buf.getvalue())
        (work / "mesh.mtl").write_text("newmtl atlas\nKd 1 1 1\nmap_Kd atlas.png\n")
        Image.new("RGB", (4, 4), (128, 128, 128)).save(work / "atlas.png")
        ms = pymeshlab.MeshSet()
        ms.load_new_mesh(str(work / "mesh.obj"))
        if corner_uv is not None:
            ms.meshing_decimation_quadric_edge_collapse_with_texture(
                targetfacenum=int(target_tris), qualitythr=0.3, extratcoordw=1.0, preserveboundary=True,
                boundaryweight=1.0, optimalplacement=True, preservenormal=True, planarquadric=False)
        else:
            ms.meshing_decimation_quadric_edge_collapse(
                targetfacenum=int(target_tris), qualitythr=0.3, preserveboundary=True, boundaryweight=1.0,
                optimalplacement=True, preservenormal=True, planarquadric=False)
        m = ms.current_mesh()
        pts = np.asarray(m.vertex_matrix(), dtype=np.float64)
        faces = np.asarray(m.face_matrix(), dtype=np.int64)
        if corner_uv is not None:
            orig, faces, uvs = split_seams(faces, np.asarray(m.wedge_tex_coord_matrix(), dtype=np.float32))
        else:
            orig = np.unique(faces.reshape(-1))
            remap = np.full(len(pts), -1, dtype=np.int64)
            remap[orig] = np.arange(len(orig))
            faces, uvs = remap[faces], None
        pts = pts[orig]
    finally:
        shutil.rmtree(work, ignore_errors=True)
    nearest = cKDTree(char.points.astype(np.float64)).query(pts, k=1)[1]
    if char.joint_indices is not None:
        char.joint_indices, char.joint_weights = char.joint_indices[nearest], char.joint_weights[nearest]
    char.points, char.faces, char.uvs = pts.astype(np.float32), faces.astype(np.int32), uvs


def _decimate_fast(char, target_tris):
    """fast_simplification, with the UV seams frozen: the mesh is already split
    at its seams, so they are borders, and `preserve_border` keeps every
    border vertex where it is. Each surviving vertex keeps its own UV and
    weights (the collapses are replayed to learn which original vertex each
    new one is). Seams frozen means a mesh with many islands cannot reach a
    low target; the count printed afterwards says how close it got."""
    import fast_simplification
    from scipy.spatial import cKDTree
    pts32, faces32 = np.ascontiguousarray(char.points, dtype=np.float32), np.ascontiguousarray(char.faces, dtype=np.int32)
    _, _, collapses = fast_simplification.simplify(pts32, faces32, target_count=int(target_tris),
                                                   preserve_border=True, return_collapses=True)
    collapses = np.asarray(collapses, dtype=np.int64).reshape(-1, 2)
    pts, faces, mapping = fast_simplification.replay_simplification(pts32, faces32, collapses)
    pts, faces, mapping = np.asarray(pts, dtype=np.float64), np.asarray(faces, dtype=np.int64), np.asarray(mapping).reshape(-1)
    alive = np.ones(len(pts32), dtype=bool)
    alive[collapses[:, 1]] = False
    survivor = np.full(len(pts), -1, dtype=np.int64)
    idx = np.where(alive)[0]
    survivor[mapping[idx]] = idx
    missing = survivor < 0
    if missing.any():
        survivor[missing] = cKDTree(pts32).query(pts[missing], k=1)[1]
    if char.uvs is not None:
        char.uvs = char.uvs[survivor]
    if char.joint_indices is not None:
        char.joint_indices, char.joint_weights = char.joint_indices[survivor], char.joint_weights[survivor]
    char.points, char.faces = pts.astype(np.float32), faces.astype(np.int32)


# ---------------------------------------------------------------------------
# Texture grades
# ---------------------------------------------------------------------------

# A colour correction on a family's textures at shipping time (2026-09-18).
# Meshy's texturing does not always land the palette the cards were painted
# in: the awakened Ares — "Ares Aureate", gold on both his cards — came back
# olive-khaki with pink runes, and no light can turn olive into gold. A grade
# is a set of HSV moves on bands of hue, named so a family's ship command
# says which (`mesh.py <asset> --grade gold`), applied to the base colour and
# the emissive map alike, and never to a normal or a roughness map.
#
#   band: (hue lo, hue hi) in degrees, inclusive, wrapping past 360;
#   sat / val: the range of pixels the move touches;
#   hue: the hue moved toward, and `pull` how far (0 stays, 1 lands on it);
#   sat_mul / val_mul: multipliers, clamped to 1; val_gamma: a curve on the
#   value (0.6 lifts 0.43 to 0.60 and 0.80 to 0.87 — a burnish that brightens
#   the dark metal without clipping what is already bright).
GRADES = {
    # Olive and khaki to the cards' burnished gold; the magenta runes to the
    # cards' ember glow. The crimson cape (hue 350°, value under 0.6) and the
    # skin (hue 20–30°) are outside both bands. The first take (sat ×1.45,
    # val ×1.12) moved 18% of the atlas and changed nothing visible: the
    # armour's own values sit at 0.4, and a tenth more of 0.4 is still 0.4.
    "gold": [
        dict(band=(36, 82), sat=(0.14, 0.85), val=(0.16, 1.0), hue=40, pull=0.8, sat_mul=1.8, val_mul=1.0, val_gamma=0.6),
        dict(band=(300, 348), sat=(0.35, 1.0), val=(0.66, 1.0), hue=28, pull=1.0, sat_mul=1.15, val_mul=1.0),
    ],
}


def grade_texture(img, grade):
    """Applies one named grade to a PIL image (RGB or RGBA), returning a new
    image; pixels outside every band are untouched."""
    moves = GRADES[grade]
    mode = img.mode
    rgba = np.asarray(img.convert("RGBA")).astype(np.float32) / 255.0
    rgb = rgba[..., :3]
    mx = rgb.max(-1); mn = rgb.min(-1); delta = mx - mn
    sat = np.where(mx > 1e-6, delta / np.maximum(mx, 1e-6), 0.0)
    val = mx
    hue = np.zeros_like(mx)
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    nz = delta > 1e-6
    rm = nz & (mx == r); gm = nz & (mx == g) & ~rm; bm = nz & ~rm & ~gm
    hue[rm] = ((g[rm] - b[rm]) / delta[rm]) % 6.0
    hue[gm] = (b[gm] - r[gm]) / delta[gm] + 2.0
    hue[bm] = (r[bm] - g[bm]) / delta[bm] + 4.0
    hue = (hue * 60.0) % 360.0
    touched = 0
    for m in moves:
        lo, hi = m["band"]
        inband = (hue >= lo) & (hue <= hi) if lo <= hi else (hue >= lo) | (hue <= hi)
        sel = inband & (sat >= m["sat"][0]) & (sat <= m["sat"][1]) & (val >= m["val"][0]) & (val <= m["val"][1]) & nz
        touched += int(sel.sum())
        # Move the hue the short way round toward the target.
        d = ((m["hue"] - hue[sel] + 180.0) % 360.0) - 180.0
        hue[sel] = (hue[sel] + d * m["pull"]) % 360.0
        sat[sel] = np.clip(sat[sel] * m["sat_mul"], 0.0, 1.0)
        val[sel] = np.clip(np.power(np.clip(val[sel], 0.0, 1.0), m.get("val_gamma", 1.0)) * m["val_mul"], 0.0, 1.0)
    # HSV back to RGB.
    h6 = hue / 60.0
    c = val * sat
    x = c * (1.0 - np.abs((h6 % 2.0) - 1.0))
    z = np.zeros_like(c)
    idx = np.floor(h6).astype(int) % 6
    r2 = np.select([idx == 0, idx == 1, idx == 2, idx == 3, idx == 4, idx == 5], [c, x, z, z, x, c])
    g2 = np.select([idx == 0, idx == 1, idx == 2, idx == 3, idx == 4, idx == 5], [x, c, c, x, z, z])
    b2 = np.select([idx == 0, idx == 1, idx == 2, idx == 3, idx == 4, idx == 5], [z, z, x, c, c, x])
    mm = val - c
    out = np.stack([r2 + mm, g2 + mm, b2 + mm, rgba[..., 3]], -1)
    result = Image.fromarray((np.clip(out, 0, 1) * 255 + 0.5).astype(np.uint8), "RGBA")
    print(f"    graded '{grade}': {touched:,} of {mx.size:,} texels moved")
    return result.convert(mode) if mode != "RGBA" else result


def decimate(char, target_tris, texture_size=1024, method=None, grade=None):
    """Reduces the mesh to about `target_tris` triangles and the textures to
    `texture_size` on their long edge. The UVs go through the reduction, not
    around it: MeshLab's quadric edge collapse with texture carries the corner
    UVs through every collapse and treats each seam as a crease, so a reduced
    triangle still maps to the piece of atlas its surface came from. (Copying
    the UV of the nearest original vertex, as before, crossed islands at every
    seam; with an atlas of hundreds of islands most triangles touched one.)
    Skin weights do follow by nearest original vertex - they are smooth over
    the surface, so nearest is right for them. `method` is None (MeshLab,
    falling back to fast_simplification when pymeshlab is unusable) or "fast"
    to force the fallback."""
    if target_tris and target_tris < char.tris:
        tris0, pts0 = char.tris, len(char.points)
        how = method or "meshlab"
        if how == "meshlab":
            why_not = _meshlab_available()
            if why_not:
                print(f"    {why_not}; falling back to fast_simplification with the seams frozen")
                how = "fast"
        if how == "meshlab":
            _decimate_meshlab(char, target_tris)
            how = "MeshLab quadric edge collapse with texture"
        else:
            _decimate_fast(char, target_tris)
            how = "fast_simplification, seams frozen"
        smeared = uv_smear(char.uvs, char.faces)
        print(f"    decimated {tris0:,} -> {char.tris:,} tris, {pts0:,} -> {len(char.points):,} vertices ({how}); "
              f"{smeared:,} triangles ({100.0 * smeared / max(1, char.tris):.1f}%) span more than a quarter of the atlas")
    if texture_size:
        for tex in char.textures:
            img = Image.open(io.BytesIO(tex.data))
            # Always written out again through PIL, pixels only: a texture
            # that was small enough used to ship as Meshy's own bytes, and
            # UIKit logs "Error -17102 decompressing image -- possibly
            # corrupt" for two of them per model on the simulator (run 176)
            # - it decodes them still, but a clean PNG says nothing.
            img = img.convert("RGBA" if tex.ext == "png" and img.mode in ("RGBA", "LA", "P") else "RGB")
            # A named grade on the colour and the glow, never on a normal or
            # a roughness map (their pixels are not colours).
            if grade and getattr(tex, "role", "base_color") in ("base_color", "emissive", "diffuse", None):
                img = grade_texture(img, grade)
            if max(img.size) > texture_size:
                img.thumbnail((texture_size, texture_size), Image.LANCZOS)
            buf = io.BytesIO()
            img.save(buf, "PNG", optimize=True)
            tex.data, tex.ext = buf.getvalue(), "png"


# ---------------------------------------------------------------------------
# Writing
# ---------------------------------------------------------------------------

def vertex_normals(points, faces):
    """Area-weighted, and shared across UV seams: the vertices a seam split a
    point into get one normal between them, so a seam is not a crease in the
    shading."""
    p = np.asarray(points, dtype=np.float64)
    faces = np.asarray(faces)
    _, welded, wfaces = weld(p, faces)
    fn = np.cross(p[faces[:, 1]] - p[faces[:, 0]], p[faces[:, 2]] - p[faces[:, 0]])
    n = np.zeros((int(welded.max()) + 1 if len(welded) else 0, 3))
    for k in range(3):
        np.add.at(n, wfaces[:, k], fn)
    n = n[welded]
    n /= np.maximum(np.linalg.norm(n, axis=1, keepdims=True), 1e-12)
    return n.astype(np.float32)


def write_usdz(char, out):
    out = Path(out)
    work = Path(tempfile.mkdtemp())
    layer = work / "model.usdc"
    stage = Usd.Stage.CreateNew(str(layer))
    UsdGeom.SetStageUpAxis(stage, UsdGeom.Tokens.y)
    UsdGeom.SetStageMetersPerUnit(stage, 1.0)
    root = UsdGeom.Xform.Define(stage, "/root")
    stage.SetDefaultPrim(root.GetPrim())
    UsdSkel.Root.Define(stage, "/root/Armature")
    name = Tf.MakeValidIdentifier(char.name)
    # Every node gets a distinct name: the game rebinds skinners to a cloned
    # hierarchy by looking bones and the skeleton up by name.
    skel_path = Sdf.Path("/root/Armature/Skeleton")

    if len(char.joints):
        skel = UsdSkel.Skeleton.Define(stage, skel_path)
        skel.CreateJointsAttr(Vt.TokenArray(list(char.joints)))
        skel.CreateBindTransformsAttr(Vt.Matrix4dArray([np_to_gf(m) for m in char.bind]))
        skel.CreateRestTransformsAttr(Vt.Matrix4dArray([np_to_gf(m) for m in char.rest_local]))
        if char.anim:
            a = char.anim
            anim = UsdSkel.Animation.Define(stage, skel_path.AppendChild("Anim"))
            anim.CreateJointsAttr(Vt.TokenArray(list(char.joints)))
            tr, ro, sc = anim.CreateTranslationsAttr(), anim.CreateRotationsAttr(), anim.CreateScalesAttr()
            frames = len(a["T"])
            for f in range(frames):
                tr.Set(Vt.Vec3fArray.FromNumpy(a["T"][f].astype(np.float32)), f)
                ro.Set(Vt.QuatfArray([Gf.Quatf(float(q[3]), Gf.Vec3f(float(q[0]), float(q[1]), float(q[2]))) for q in a["R"][f]]), f)
                sc.Set(Vt.Vec3hArray([Gf.Vec3h(float(s[0]), float(s[1]), float(s[2])) for s in a["S"][f]]), f)
            UsdSkel.BindingAPI.Apply(skel.GetPrim()).CreateAnimationSourceRel().SetTargets([anim.GetPath()])
            stage.SetStartTimeCode(0)
            stage.SetEndTimeCode(frames - 1)
            stage.SetTimeCodesPerSecond(a["fps"])
            stage.SetFramesPerSecond(a["fps"])

    UsdGeom.Xform.Define(stage, f"/root/Armature/{name}")
    mesh = UsdGeom.Mesh.Define(stage, f"/root/Armature/{name}/{name}_mesh")
    mesh.CreatePointsAttr(Vt.Vec3fArray.FromNumpy(char.points.astype(np.float32)))
    mesh.CreateFaceVertexCountsAttr(Vt.IntArray.FromNumpy(np.full(len(char.faces), 3, dtype=np.int32)))
    mesh.CreateFaceVertexIndicesAttr(Vt.IntArray.FromNumpy(char.faces.reshape(-1).astype(np.int32)))
    lo, hi = bounds(char.points)
    mesh.CreateExtentAttr(Vt.Vec3fArray([Gf.Vec3f(*lo.tolist()), Gf.Vec3f(*hi.tolist())]))
    mesh.CreateSubdivisionSchemeAttr(UsdGeom.Tokens.none)
    mesh.CreateDoubleSidedAttr(False)
    mesh.CreateNormalsAttr(Vt.Vec3fArray.FromNumpy(vertex_normals(char.points, char.faces)))
    mesh.SetNormalsInterpolation(UsdGeom.Tokens.vertex)
    if char.uvs is not None:
        pv = UsdGeom.PrimvarsAPI(mesh.GetPrim()).CreatePrimvar("st", Sdf.ValueTypeNames.TexCoord2fArray, UsdGeom.Tokens.vertex)
        pv.Set(Vt.Vec2fArray.FromNumpy(char.uvs.astype(np.float32)))
    if char.skinned:
        binding = UsdSkel.BindingAPI.Apply(mesh.GetPrim())
        binding.CreateSkeletonRel().SetTargets([skel_path])
        k = char.joint_indices.shape[1]
        binding.CreateJointIndicesPrimvar(False, k).Set(Vt.IntArray.FromNumpy(char.joint_indices.reshape(-1).astype(np.int32)))
        binding.CreateJointWeightsPrimvar(False, k).Set(Vt.FloatArray.FromNumpy(char.joint_weights.reshape(-1).astype(np.float32)))
        binding.CreateGeomBindTransformAttr().Set(Gf.Matrix4d(1.0))

    # --- material ---------------------------------------------------------
    mat_path = Sdf.Path(f"/root/_materials/{name}_material")
    material = UsdShade.Material.Define(stage, mat_path)
    surface = UsdShade.Shader.Define(stage, mat_path.AppendChild("Principled_BSDF"))
    surface.CreateIdAttr("UsdPreviewSurface")
    material.CreateSurfaceOutput().ConnectToSource(surface.ConnectableAPI(), "surface")
    reader = UsdShade.Shader.Define(stage, mat_path.AppendChild("uvmap"))
    reader.CreateIdAttr("UsdPrimvarReader_float2")
    reader.CreateInput("varname", Sdf.ValueTypeNames.String).Set("st")
    st_out = reader.CreateOutput("result", Sdf.ValueTypeNames.Float2)
    (work / "textures").mkdir(exist_ok=True)

    def tex_shader(tex, shader_name, colorspace, normal_map=False):
        rel = f"./textures/{tex.role}.{tex.ext}"
        (work / "textures" / f"{tex.role}.{tex.ext}").write_bytes(tex.data)
        sh = UsdShade.Shader.Define(stage, mat_path.AppendChild(shader_name))
        sh.CreateIdAttr("UsdUVTexture")
        sh.CreateInput("file", Sdf.ValueTypeNames.Asset).Set(Sdf.AssetPath(rel))
        sh.CreateInput("st", Sdf.ValueTypeNames.Float2).ConnectToSource(st_out)
        sh.CreateInput("wrapS", Sdf.ValueTypeNames.Token).Set("repeat")
        sh.CreateInput("wrapT", Sdf.ValueTypeNames.Token).Set("repeat")
        sh.CreateInput("sourceColorSpace", Sdf.ValueTypeNames.Token).Set(colorspace)
        if normal_map:
            sh.CreateInput("scale", Sdf.ValueTypeNames.Float4).Set(Gf.Vec4f(2, 2, 2, 2))
            sh.CreateInput("bias", Sdf.ValueTypeNames.Float4).Set(Gf.Vec4f(-1, -1, -1, -1))
        return sh

    by_role = {t.role: t for t in char.textures}
    if "base_color" in by_role:
        sh = tex_shader(by_role["base_color"], "Image_Texture", "sRGB")
        surface.CreateInput("diffuseColor", Sdf.ValueTypeNames.Color3f).ConnectToSource(sh.CreateOutput("rgb", Sdf.ValueTypeNames.Float3))
    else:
        surface.CreateInput("diffuseColor", Sdf.ValueTypeNames.Color3f).Set(Gf.Vec3f(0.6, 0.6, 0.6))
    if "metallic_roughness" in by_role:
        sh = tex_shader(by_role["metallic_roughness"], "Image_Texture_MR", "raw")
        surface.CreateInput("roughness", Sdf.ValueTypeNames.Float).ConnectToSource(sh.CreateOutput("g", Sdf.ValueTypeNames.Float))
        surface.CreateInput("metallic", Sdf.ValueTypeNames.Float).ConnectToSource(sh.CreateOutput("b", Sdf.ValueTypeNames.Float))
    else:
        if "roughness" in by_role:
            sh = tex_shader(by_role["roughness"], "Image_Texture_Roughness", "raw")
            surface.CreateInput("roughness", Sdf.ValueTypeNames.Float).ConnectToSource(sh.CreateOutput("r", Sdf.ValueTypeNames.Float))
        else:
            surface.CreateInput("roughness", Sdf.ValueTypeNames.Float).Set(float(min(0.95, max(0.35, char.roughness))))
        if "metallic" in by_role:
            sh = tex_shader(by_role["metallic"], "Image_Texture_Metallic", "raw")
            surface.CreateInput("metallic", Sdf.ValueTypeNames.Float).ConnectToSource(sh.CreateOutput("r", Sdf.ValueTypeNames.Float))
        else:
            # A generator's "metallic 1.0" on a whole character turns it chrome
            # under a flat environment; the game clamps to 0.25 anyway.
            surface.CreateInput("metallic", Sdf.ValueTypeNames.Float).Set(float(min(0.2, max(0.0, char.metallic))))
    if "normal" in by_role:
        sh = tex_shader(by_role["normal"], "Image_Texture_Normal", "raw", normal_map=True)
        surface.CreateInput("normal", Sdf.ValueTypeNames.Normal3f).ConnectToSource(sh.CreateOutput("rgb", Sdf.ValueTypeNames.Float3))
    if "emissive" in by_role:
        sh = tex_shader(by_role["emissive"], "Image_Texture_Emissive", "sRGB")
        surface.CreateInput("emissiveColor", Sdf.ValueTypeNames.Color3f).ConnectToSource(sh.CreateOutput("rgb", Sdf.ValueTypeNames.Float3))
    surface.CreateInput("opacity", Sdf.ValueTypeNames.Float).Set(1.0)
    UsdShade.MaterialBindingAPI.Apply(mesh.GetPrim()).Bind(material)

    stage.GetRootLayer().Save()
    out.parent.mkdir(parents=True, exist_ok=True)
    if out.exists():
        out.unlink()
    UsdUtils.CreateNewUsdzPackage(Sdf.AssetPath(str(layer)), str(out))
    shutil.rmtree(work, ignore_errors=True)
    return out.stat().st_size


# ---------------------------------------------------------------------------
# Checking what was written
# ---------------------------------------------------------------------------

def verify(path, expect_height=None, quiet=False, check_bounds=True):
    """Re-reads a written file and skins it in numpy at the bind pose and at
    the first, middle and last animated frames. Returns the facts; prints them.
    `check_bounds=False` skips the height and feet checks on the bind pose:
    a per-clip file's mesh is a 1,500-triangle carrier for the skeleton and
    the clip, and its bounds are measured by the caller on the full mesh."""
    char = read_usdz(path)      # our own file: identity SkelRoot, so this is a plain read
    facts = {"file": str(path), "tris": char.tris, "points": len(char.points), "joints": len(char.joints),
             "frames": len(char.anim["T"]) if char.anim else 0, "problems": []}
    lo, hi = bounds(char.points.astype(np.float64))
    facts["bind"] = {"height": hi[1] - lo[1], "feet": lo[1], "centre": ((lo[0] + hi[0]) / 2, (lo[2] + hi[2]) / 2)}
    facts["facing"] = facing(char) if len(char.joints) else 0
    if char.skinned:
        k = char.joint_indices.shape[1]
        facts["influences"] = k
        sums = char.joint_weights.sum(axis=1)
        if k > 4:
            facts["problems"].append(f"{k} influences per vertex")
        if abs(sums - 1).max() > 1e-3:
            facts["problems"].append(f"weights do not sum to 1 (worst {abs(sums - 1).max():.4f})")
        if (char.joint_indices >= len(char.joints)).any() or (char.joint_indices < 0).any():
            facts["problems"].append("joint index out of range")
        for j, p in enumerate(char.parents):
            if p >= j:
                facts["problems"].append("joints are not ordered parents-first")
                break
        rest_world = char.joint_world_at_rest()
        dev = np.abs(rest_world - char.bind).max()
        facts["rest_vs_bind"] = dev
        if dev > 1e-3:
            facts["problems"].append(f"rest pose differs from bind pose by {dev:.4f}")
        at_rest = char.skinned_points(rest_world)
        d = np.abs(at_rest - char.points).max()
        if d > 1e-3:
            facts["problems"].append(f"skinning at rest moves the mesh by {d:.4f}")
        if char.anim:
            frames = len(char.anim["T"])
            facts["poses"] = {}
            for label, f in (("first", 0), ("middle", frames // 2), ("last", frames - 1)):
                sp = char.skinned_points(char.joint_world_at(f))
                l2, h2 = bounds(sp)
                facts["poses"][label] = {"height": h2[1] - l2[1], "feet": l2[1], "centre": ((l2[0] + h2[0]) / 2, (l2[2] + h2[2]) / 2),
                                         "size": (h2 - l2)}
                if not np.isfinite(sp).all() or (h2 - l2).max() > 4 * facts["bind"]["height"]:
                    facts["problems"].append(f"{label} frame explodes: size {(h2 - l2).round(2)}")
    if check_bounds and expect_height and abs(facts["bind"]["height"] - expect_height) > 0.02 * expect_height:
        facts["problems"].append(f"height {facts['bind']['height']:.3f} != {expect_height}")
    if check_bounds and abs(facts["bind"]["feet"]) > 0.01:
        facts["problems"].append(f"feet at y={facts['bind']['feet']:.3f}")
    if facts["facing"] < 0:
        facts["problems"].append("faces -Z")
    if not quiet:
        report(facts)
    return facts


def report(f):
    b = f["bind"]
    face = {1: "faces +Z", -1: "FACES -Z", 0: "facing unknown"}[f["facing"]]
    line = "    bind pose: %.3f m tall, feet at y=%+.3f, centre (%+.3f, %+.3f), %s" % (
        b["height"], b["feet"], b["centre"][0], b["centre"][1], face)
    if "influences" in f:
        line += ", %d influences" % f["influences"]
    if "rest_vs_bind" in f:
        line += ", rest==bind to %.1e" % f["rest_vs_bind"]
    print(line)
    for label, p in f.get("poses", {}).items():
        print("    %-6s frame: %.2f m tall, feet y=%+.2f, centre (%+.2f, %+.2f)" % (
            label, p["height"], p["feet"], p["centre"][0], p["centre"][1]))
    for prob in f["problems"]:
        print("    PROBLEM: " + prob)


def describe(char):
    lo, hi = bounds(char.points.astype(np.float64))
    tex = ", ".join(f"{t.role} {t.size[0]}px" for t in char.textures) or "no textures"
    frames = len(char.anim["T"]) if char.anim else 0
    infl = char.joint_indices.shape[1] if char.skinned else 0
    rate = " @ %.0f fps" % char.anim["fps"] if frames else ""
    print("    %s tris, %s points, %d joints, %d influences, %d frames%s, %s-up, %s" % (
        f"{char.tris:,}", f"{len(char.points):,}", len(char.joints), infl, frames, rate, char.up_axis, tex))
    print("    bounds x %.2f..%.2f  y %.2f..%.2f  z %.2f..%.2f" % (lo[0], hi[0], lo[1], hi[1], lo[2], hi[2]))
