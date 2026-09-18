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
                "phoenix", "raven", "eagle", "wing", "apep", "serpent", "jotunn", "colossus", "unwrapped")


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
    `min_width` across the second axis. The third axis may reach three
    tenths of the second: a cloak wraps the body's side (Diana's, at
    0.27) where a flat cape is under a tenth."""
    centred = points - points.mean(axis=0)
    lam = np.sort(np.linalg.eigvalsh(centred.T @ centred / len(points)))[::-1]   # descending
    width = 2.0 * np.sqrt(3.0 * max(lam[1], 0.0))          # a uniform slab's extent along its second axis
    return lam[1] >= 0.04 * lam[0] and lam[2] <= 0.30 * max(lam[1], 1e-12) and width >= min_width


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
    sheet = ((P[:, 2] < spine_z - back * height) & (P[:, 1] > floor * height) & (P[:, 1] < neck_y)
             & (held_w <= 0.5))
    uncut = sheet.copy()
    # Clear of every limb's own surface (_limb_surface); the spine, hips
    # and head block nothing — what hangs behind them is the cloth. Cut
    # FIRST, so a weapon in a hand behind the hip is not bridged to the
    # shoulders through the arm's own back (Sekhmet's khopesh was).
    normals = vertex_normals(P, char.faces).astype(np.float64) if len(char.faces) else np.zeros_like(P)
    for j, p in enumerate(char.parents):
        if p < 0 or kind[j] not in SURFACE_BONES:
            continue
        sheet &= ~_limb_surface(P, normals, jw[p], jw[j], reach=0.25 * height, gap=0.012 * height,
                                inward_stop=kind[j] in ("upleg", "leg", "foot"))
    # One large sheet hanging from the shoulders (its uncut piece above the
    # second spine joint) a good way down the back, not a scatter of
    # patches at the shoulders (a figure with no cape has those), a
    # loincloth's tail from the belt, nor a weapon carried behind the hip
    # (a rod or a lump, not a sheet).
    sheet = _big_sheets(P, char.faces, sheet, uncut, min_count=max(300, len(P) // 150), min_span=0.20 * height,
                        top_at=chain_y[-2] - 0.02 * height, min_width=0.12 * height, merge_gap=0.03 * height)
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
    # Dense weights, the cloth rows replaced by the height blend.
    W = np.zeros((len(P), J), dtype=np.float64)
    rows = np.arange(len(P))[:, None]
    np.add.at(W, (np.broadcast_to(rows, char.joint_indices.shape), char.joint_indices), char.joint_weights.astype(np.float64))
    y = P[cloth, 1]
    upper = np.clip(np.searchsorted(chain_y, y), 1, len(chain) - 1)
    lower = upper - 1
    span = np.maximum(chain_y[upper] - chain_y[lower], 1e-6)
    t_up = np.clip((y - chain_y[lower]) / span, 0.0, 1.0)
    W[cloth] = 0.0
    W[np.flatnonzero(cloth), [idx[chain[i]] for i in lower]] = 1.0 - t_up
    W[np.flatnonzero(cloth), [idx[chain[i]] for i in upper]] += t_up
    # The seam: average each cloth vertex's weights with its mesh neighbours
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
        cloth_c = np.zeros(C, bool); cloth_c[canon[cloth]] = True
        deg = np.zeros(C); np.add.at(deg, e[:, 0], 1.0); np.add.at(deg, e[:, 1], 1.0)
        for _ in range(rings):
            acc = Wc.copy()
            np.add.at(acc, e[:, 0], Wc[e[:, 1]]); np.add.at(acc, e[:, 1], Wc[e[:, 0]])
            acc /= (deg + 1.0)[:, None]
            Wc[cloth_c] = acc[cloth_c]
        W[cloth] = Wc[canon[cloth]]
    K = char.joint_indices.shape[1]
    top = np.argsort(-W[cloth], axis=1)[:, :K]
    wt = np.take_along_axis(W[cloth], top, axis=1)
    wt /= np.maximum(wt.sum(axis=1, keepdims=True), 1e-9)
    top[wt <= 0] = 0
    char.joint_indices[cloth] = top.astype(char.joint_indices.dtype)
    char.joint_weights[cloth] = wt.astype(char.joint_weights.dtype)
    was = {}
    for o in owner[cloth]:
        was[leaf[o]] = was.get(leaf[o], 0) + 1
    was = ", ".join(f"{k} {v:,}" for k, v in sorted(was.items(), key=lambda kv: -kv[1])[:4])
    print(f"    cape: {n:,} of {len(P):,} vertices hang clear of every bone behind the back "
          f"(were {was}); re-bound to {' > '.join(leaf[idx[n]] for n in chain)} by height, the seam blended over {rings} rings")
    return n


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
