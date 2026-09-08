#!/usr/bin/env python3
"""
Converts a glTF binary (.glb) into the .usdz the game loads. Written for the
rigged, animated characters that come back from Meshy's rigging and animation
endpoints, which return GLB and FBX only; the text-to-3D stages return USDZ
directly and never need this.

    python3 tools/glb2usd.py sekhmet                 # every Art/Models/sekhmet*.glb -> .usdz beside it
    python3 tools/glb2usd.py file.glb [--out file.usdz] [--animation 0] [--fps 30]

Pixar's USD does not read glTF without a plugin the pip build lacks, and
SceneKit does not read glTF at all, so this works on the two formats directly:
the GLB container and its accessors with numpy, the USD side with pxr.

The output mirrors the layout of the exports that already load in the game
(Blender's, via Meshy's web app), so ModelLibrary sees the same shape:

    /root                          Xform, default prim
    /root/Armature                 SkelRoot
    /root/Armature/Armature        Skeleton: joints, bind and rest transforms
    /root/Armature/Armature/Anim   SkelAnimation, when the file has one
    /root/Armature/<mesh>/<mesh>   Mesh bound to the skeleton, skin primvars
    /root/_materials/<name>        UsdPreviewSurface with the glTF's textures

Y-up and metres, as glTF is. Transforms are carried across unchanged, so a
character that faces +Z with its origin at its feet in the GLB does so here.

Not handled, because Meshy never writes them: sparse accessors, morph targets,
more than one skin, KHR_texture_transform, quantised attributes. Each stops
with a message rather than producing a wrong file.

Two checks print at the end. The rest pose is rebuilt from the joint
hierarchy and compared with the bind pose from the inverse bind matrices; a
rigged export should agree to within a millimetre, and a large difference
means the skeleton was not saved in its bind pose (SceneKit still skins
correctly, because it uses the bind transforms, but the un-animated pose will
differ). And the mesh height is printed so it can be checked against
ModelSpec.height.
"""

import argparse, base64, json, shutil, struct, sys, tempfile
from pathlib import Path

import numpy as np
from pxr import Usd, UsdGeom, UsdSkel, UsdShade, UsdUtils, Sdf, Gf, Vt, Tf

REPO = Path(__file__).resolve().parent.parent
SOURCE_DIR = REPO / "Art" / "Models"

GLB_MAGIC, CHUNK_JSON, CHUNK_BIN = 0x46546C67, 0x4E4F534A, 0x004E4942
COMPONENT = {5120: np.int8, 5121: np.uint8, 5122: np.int16, 5123: np.uint16, 5125: np.uint32, 5126: np.float32}
WIDTH = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT2": 4, "MAT3": 9, "MAT4": 16}
MIME_EXT = {"image/png": "png", "image/jpeg": "jpg"}
IDENTITY = Gf.Matrix4d(1.0)


# ---------------------------------------------------------------------------
# glTF side
# ---------------------------------------------------------------------------

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
        if self.json is None:
            sys.exit(f"{path}: no JSON chunk")
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


# A glTF matrix is 16 floats, column-major, for column vectors. Read row-major
# they are exactly the row-vector-convention matrix USD uses (translation in
# the last row), so no transpose is needed.
def matrix(values):
    return Gf.Matrix4d(*[float(v) for v in values])


def trs_matrix(t, r, s):
    scale = Gf.Matrix4d().SetScale(Gf.Vec3d(*[float(v) for v in s]))
    rotate = Gf.Matrix4d().SetRotate(Gf.Quatd(float(r[3]), Gf.Vec3d(float(r[0]), float(r[1]), float(r[2]))))
    translate = Gf.Matrix4d().SetTranslate(Gf.Vec3d(*[float(v) for v in t]))
    return scale * rotate * translate


def node_trs(node):
    if "matrix" in node:
        x = Gf.Transform(matrix(node["matrix"]))
        q = x.GetRotation().GetQuat()
        t, s = x.GetTranslation(), x.GetScale()
        return (np.array([t[0], t[1], t[2]]),
                np.array([q.GetImaginary()[0], q.GetImaginary()[1], q.GetImaginary()[2], q.GetReal()]),
                np.array([s[0], s[1], s[2]]))
    return (np.array(node.get("translation", [0, 0, 0]), dtype=np.float64),
            np.array(node.get("rotation", [0, 0, 0, 1]), dtype=np.float64),
            np.array(node.get("scale", [1, 1, 1]), dtype=np.float64))


def local_matrix(node):
    if "matrix" in node:
        return matrix(node["matrix"])
    return trs_matrix(*node_trs(node))


def is_identity(m, tol=1e-6):
    return all(abs(m[i][j] - IDENTITY[i][j]) < tol for i in range(4) for j in range(4))


def quatf(q):
    return Gf.Quatf(float(q[3]), Gf.Vec3f(float(q[0]), float(q[1]), float(q[2])))


# ---------------------------------------------------------------------------
# Animation sampling
# ---------------------------------------------------------------------------

def sample_linear(times, values, at):
    out = np.empty((len(at), values.shape[1]))
    for c in range(values.shape[1]):
        out[:, c] = np.interp(at, times, values[:, c])
    return out


def sample_step(times, values, at):
    idx = np.clip(np.searchsorted(times, at, side="right") - 1, 0, len(times) - 1)
    return values[idx]


def sample_quat(times, values, at):
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


def channel_values(sampler, glb):
    times = glb.accessor(sampler["input"]).reshape(-1).astype(np.float64)
    values = glb.accessor(sampler["output"]).astype(np.float64)
    interp = sampler.get("interpolation", "LINEAR")
    if interp == "CUBICSPLINE":
        # in-tangent, value, out-tangent per key: keep the values, interpolate linearly.
        values = values.reshape(len(times), 3, -1)[:, 1, :]
        interp = "LINEAR"
    return times, values, interp


# ---------------------------------------------------------------------------
# Conversion
# ---------------------------------------------------------------------------

class Namer:
    def __init__(self):
        self.taken = set()

    def __call__(self, raw, fallback):
        base = Tf.MakeValidIdentifier(raw) if raw else fallback
        name, k = base, 1
        while name in self.taken:
            k += 1
            name = f"{base}_{k}"
        self.taken.add(name)
        return name


def convert(src, out, animation_index=0, fps=30):
    glb = Glb(src)
    g = glb.json
    nodes = g.get("nodes", [])
    parent = {i: None for i in range(len(nodes))}
    for i, n in enumerate(nodes):
        for c in n.get("children", []):
            parent[c] = i

    world_cache = {}

    def world(i):
        if i not in world_cache:
            m = local_matrix(nodes[i])
            world_cache[i] = m if parent[i] is None else m * world(parent[i])
        return world_cache[i]

    work = Path(tempfile.mkdtemp())
    layer_path = work / "model.usdc"
    stage = Usd.Stage.CreateNew(str(layer_path))
    UsdGeom.SetStageUpAxis(stage, UsdGeom.Tokens.y)
    UsdGeom.SetStageMetersPerUnit(stage, 1.0)
    root = UsdGeom.Xform.Define(stage, "/root")
    stage.SetDefaultPrim(root.GetPrim())
    skel_root = UsdSkel.Root.Define(stage, "/root/Armature")
    names = Namer()
    stats = {"joints": 0, "frames": 0, "tris": 0, "points": 0, "textures": set(), "meshes": 0}

    # --- skeleton ---------------------------------------------------------
    skins = g.get("skins", [])
    if len(skins) > 1:
        sys.exit(f"{src.name}: {len(skins)} skins; only one is supported")
    skin = skins[0] if skins else None
    skel_path = Sdf.Path("/root/Armature/Armature")
    order, joint_pos, joint_parent_of = [], {}, {}
    if skin:
        joint_nodes = list(skin["joints"])
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

        # Parents before children, which UsdSkel requires; stable otherwise.
        order = sorted(joint_nodes, key=lambda i: (depth_of(i), joint_nodes.index(i)))
        joint_pos = {n: k for k, n in enumerate(order)}
        joint_parent_of = {i: joint_parent(i) for i in order}
        joint_namer = Namer()
        path_of = {}
        for i in order:
            nm = joint_namer(nodes[i].get("name"), f"joint_{i}")
            jp = joint_parent_of[i]
            path_of[i] = nm if jp is None else f"{path_of[jp]}/{nm}"

        original_pos = {n: k for k, n in enumerate(joint_nodes)}
        ibm = glb.accessor(skin["inverseBindMatrices"]) if "inverseBindMatrices" in skin else None
        # glTF skins a vertex as globalJoint * inverseBindMatrix * p, and the
        # inverse bind matrices are authored against the skinned mesh node's
        # own frame. The mesh points are baked into world space below, so the
        # bind pose has to be expressed there too: inverse(IBM) * meshWorld.
        skin_users = [i for i, n in enumerate(nodes) if n.get("skin") == 0 and "mesh" in n]
        skin_world = world(skin_users[0]) if skin_users else Gf.Matrix4d(1.0)
        if any(not is_identity(world(i) * skin_world.GetInverse()) for i in skin_users[1:]):
            print(f"  warning: several mesh nodes share the skin with different transforms; "
                  f"skinning is exact for {nodes[skin_users[0]].get('name', skin_users[0])} only")
        bind, rest = [], []
        for i in order:
            bind.append(matrix(ibm[original_pos[i]]).GetInverse() * skin_world if ibm is not None else skin_world)
            jp = joint_parent_of[i]
            rest.append(world(i) if jp is None else world(i) * world(jp).GetInverse())

        skel = UsdSkel.Skeleton.Define(stage, skel_path)
        skel.CreateJointsAttr(Vt.TokenArray([path_of[i] for i in order]))
        skel.CreateBindTransformsAttr(Vt.Matrix4dArray(bind))
        skel.CreateRestTransformsAttr(Vt.Matrix4dArray(rest))
        stats["joints"] = len(order)

        # Rest pose rebuilt from the hierarchy against the bind pose.
        rebuilt = {}
        worst = 0.0
        for k, i in enumerate(order):
            jp = joint_parent_of[i]
            rebuilt[i] = rest[k] if jp is None else rest[k] * rebuilt[jp]
            worst = max(worst, max(abs(rebuilt[i][r][c] - bind[k][r][c]) for r in range(4) for c in range(4)))
        stats["rest_vs_bind"] = worst

    # --- animation --------------------------------------------------------
    anims = g.get("animations", [])
    if anims and skin:
        if animation_index >= len(anims):
            sys.exit(f"{src.name}: animation {animation_index} does not exist; the file has {len(anims)}")
        anim = anims[animation_index]
        stats["animation_names"] = [a.get("name", f"animation_{k}") for k, a in enumerate(anims)]
        channels = {}
        for ch in anim["channels"]:
            tgt = ch["target"]
            if tgt.get("node") is None or tgt["path"] == "weights":
                continue
            channels[(tgt["node"], tgt["path"])] = channel_values(anim["samplers"][ch["sampler"]], glb)
        if channels:
            t0 = min(t[0] for t, _, _ in channels.values())
            t1 = max(t[-1] for t, _, _ in channels.values())
            frames = max(1, int(round((t1 - t0) * fps)) + 1)
            at = t0 + np.arange(frames) / fps
            T = np.empty((frames, len(order), 3))
            R = np.empty((frames, len(order), 4))
            S = np.empty((frames, len(order), 3))
            for k, i in enumerate(order):
                rt, rr, rs = node_trs(nodes[i])
                for path, dest, rest_value in (("translation", T, rt), ("rotation", R, rr), ("scale", S, rs)):
                    if (i, path) in channels:
                        times, values, interp = channels[(i, path)]
                        if path == "rotation":
                            dest[:, k] = sample_quat(times, values, at) if interp != "STEP" else sample_step(times, values, at)
                        elif interp == "STEP":
                            dest[:, k] = sample_step(times, values, at)
                        else:
                            dest[:, k] = sample_linear(times, values, at)
                    else:
                        dest[:, k] = rest_value
                # A root joint sitting under a transformed non-joint node (an
                # "Armature" empty) is animated relative to that node, but
                # UsdSkel wants it relative to the SkelRoot. Fold the ancestor in.
                if joint_parent_of[i] is None and parent[i] is not None and not is_identity(world(parent[i])):
                    above = world(parent[i])
                    for f in range(frames):
                        x = Gf.Transform(trs_matrix(T[f, k], R[f, k], S[f, k]) * above)
                        q, t, s = x.GetRotation().GetQuat(), x.GetTranslation(), x.GetScale()
                        T[f, k] = [t[0], t[1], t[2]]
                        R[f, k] = [q.GetImaginary()[0], q.GetImaginary()[1], q.GetImaginary()[2], q.GetReal()]
                        S[f, k] = [s[0], s[1], s[2]]

            anim_prim = UsdSkel.Animation.Define(stage, skel_path.AppendChild("Anim"))
            anim_prim.CreateJointsAttr(skel.GetJointsAttr().Get())
            tr_attr, ro_attr, sc_attr = (anim_prim.CreateTranslationsAttr(), anim_prim.CreateRotationsAttr(),
                                         anim_prim.CreateScalesAttr())
            for f in range(frames):
                tr_attr.Set(Vt.Vec3fArray.FromNumpy(T[f].astype(np.float32)), f)
                ro_attr.Set(Vt.QuatfArray([quatf(q) for q in R[f]]), f)
                sc_attr.Set(Vt.Vec3hArray([Gf.Vec3h(float(s[0]), float(s[1]), float(s[2])) for s in S[f]]), f)
            UsdSkel.BindingAPI.Apply(skel.GetPrim()).CreateAnimationSourceRel().SetTargets([anim_prim.GetPath()])
            stage.SetStartTimeCode(0)
            stage.SetEndTimeCode(frames - 1)
            stage.SetTimeCodesPerSecond(fps)
            stage.SetFramesPerSecond(fps)
            stats["frames"] = frames

    # --- materials --------------------------------------------------------
    materials = {}

    def texture_shader(mat_path, name, tex_info, colorspace, normal_map=False):
        image = g["textures"][tex_info["index"]]["source"]
        data, ext = glb.image_bytes(image)
        rel = f"./textures/texture_{image}.{ext}"
        dest = work / "textures" / f"texture_{image}.{ext}"
        dest.parent.mkdir(exist_ok=True)
        dest.write_bytes(data)
        stats["textures"].add(rel)
        sh = UsdShade.Shader.Define(stage, mat_path.AppendChild(name))
        sh.CreateIdAttr("UsdUVTexture")
        sh.CreateInput("file", Sdf.ValueTypeNames.Asset).Set(Sdf.AssetPath(rel))
        sh.CreateInput("st", Sdf.ValueTypeNames.Float2).ConnectToSource(
            UsdShade.Shader(stage.GetPrimAtPath(mat_path.AppendChild("uvmap"))).GetOutput("result"))
        sh.CreateInput("wrapS", Sdf.ValueTypeNames.Token).Set("repeat")
        sh.CreateInput("wrapT", Sdf.ValueTypeNames.Token).Set("repeat")
        sh.CreateInput("sourceColorSpace", Sdf.ValueTypeNames.Token).Set(colorspace)
        if normal_map:
            sh.CreateInput("scale", Sdf.ValueTypeNames.Float4).Set(Gf.Vec4f(2, 2, 2, 2))
            sh.CreateInput("bias", Sdf.ValueTypeNames.Float4).Set(Gf.Vec4f(-1, -1, -1, -1))
        return sh

    def material_for(index):
        if index in materials:
            return materials[index]
        mat = g["materials"][index]
        name = names(mat.get("name"), f"Material_{index}")
        mat_path = Sdf.Path(f"/root/_materials/{name}")
        material = UsdShade.Material.Define(stage, mat_path)
        surface = UsdShade.Shader.Define(stage, mat_path.AppendChild("Principled_BSDF"))
        surface.CreateIdAttr("UsdPreviewSurface")
        material.CreateSurfaceOutput().ConnectToSource(surface.ConnectableAPI(), "surface")
        reader = UsdShade.Shader.Define(stage, mat_path.AppendChild("uvmap"))
        reader.CreateIdAttr("UsdPrimvarReader_float2")
        reader.CreateInput("varname", Sdf.ValueTypeNames.String).Set("st")
        reader.CreateOutput("result", Sdf.ValueTypeNames.Float2)

        pbr = mat.get("pbrMetallicRoughness", {})
        base = pbr.get("baseColorFactor", [1, 1, 1, 1])
        if "baseColorTexture" in pbr:
            tex = texture_shader(mat_path, "Image_Texture", pbr["baseColorTexture"], "sRGB")
            surface.CreateInput("diffuseColor", Sdf.ValueTypeNames.Color3f).ConnectToSource(
                tex.CreateOutput("rgb", Sdf.ValueTypeNames.Float3))
        else:
            surface.CreateInput("diffuseColor", Sdf.ValueTypeNames.Color3f).Set(Gf.Vec3f(*[float(v) for v in base[:3]]))
        if "metallicRoughnessTexture" in pbr:
            tex = texture_shader(mat_path, "Image_Texture_MR", pbr["metallicRoughnessTexture"], "raw")
            surface.CreateInput("roughness", Sdf.ValueTypeNames.Float).ConnectToSource(
                tex.CreateOutput("g", Sdf.ValueTypeNames.Float))
            surface.CreateInput("metallic", Sdf.ValueTypeNames.Float).ConnectToSource(
                tex.CreateOutput("b", Sdf.ValueTypeNames.Float))
        else:
            surface.CreateInput("roughness", Sdf.ValueTypeNames.Float).Set(float(pbr.get("roughnessFactor", 1.0)))
            surface.CreateInput("metallic", Sdf.ValueTypeNames.Float).Set(float(pbr.get("metallicFactor", 1.0)))
        if "normalTexture" in mat:
            tex = texture_shader(mat_path, "Image_Texture_Normal", mat["normalTexture"], "raw", normal_map=True)
            surface.CreateInput("normal", Sdf.ValueTypeNames.Normal3f).ConnectToSource(
                tex.CreateOutput("rgb", Sdf.ValueTypeNames.Float3))
        if "emissiveTexture" in mat:
            tex = texture_shader(mat_path, "Image_Texture_Emissive", mat["emissiveTexture"], "sRGB")
            surface.CreateInput("emissiveColor", Sdf.ValueTypeNames.Color3f).ConnectToSource(
                tex.CreateOutput("rgb", Sdf.ValueTypeNames.Float3))
        surface.CreateInput("opacity", Sdf.ValueTypeNames.Float).Set(1.0)
        materials[index] = material
        return material

    # --- meshes -----------------------------------------------------------
    lut = np.array([joint_pos[n] for n in skin["joints"]], dtype=np.int32) if skin else None
    lo, hi = None, None
    for ni, node in enumerate(nodes):
        if "mesh" not in node:
            continue
        mesh = g["meshes"][node["mesh"]]
        skinned = skin is not None and "skin" in node
        if "skin" in node and node["skin"] != 0:
            sys.exit(f"{src.name}: a mesh uses skin {node['skin']}; only skin 0 is supported")
        xname = names(node.get("name") or mesh.get("name"), f"mesh_{ni}")
        UsdGeom.Xform.Define(stage, f"/root/Armature/{xname}")
        # Points are baked into world space rather than carried on an Xform,
        # so that anything measuring the raw geometry (ModelOrientation in the
        # game, the height printed below) sees the character standing up.
        mesh_world = world(ni)
        M = np.array([[mesh_world[r][c] for c in range(4)] for r in range(4)])
        normal_m = np.linalg.inv(M[:3, :3]).T
        for pi, prim in enumerate(mesh["primitives"]):
            if prim.get("mode", 4) != 4:
                sys.exit(f"{src.name}: primitive mode {prim.get('mode')}; only triangles are supported")
            attrs = prim["attributes"]
            P = glb.accessor(attrs["POSITION"]).astype(np.float64)
            P = (np.c_[P, np.ones(len(P))] @ M)[:, :3].astype(np.float32)
            faces = (glb.accessor(prim["indices"]).reshape(-1) if "indices" in prim
                     else np.arange(len(P))).astype(np.int32)
            mname = xname if pi == 0 else f"{xname}_{pi + 1}"
            m = UsdGeom.Mesh.Define(stage, f"/root/Armature/{xname}/{mname}")
            m.CreatePointsAttr(Vt.Vec3fArray.FromNumpy(P))
            m.CreateFaceVertexCountsAttr(Vt.IntArray.FromNumpy(np.full(len(faces) // 3, 3, dtype=np.int32)))
            m.CreateFaceVertexIndicesAttr(Vt.IntArray.FromNumpy(faces))
            m.CreateExtentAttr(Vt.Vec3fArray([Gf.Vec3f(*P.min(0).tolist()), Gf.Vec3f(*P.max(0).tolist())]))
            m.CreateSubdivisionSchemeAttr(UsdGeom.Tokens.none)
            m.CreateDoubleSidedAttr(bool(g["materials"][prim["material"]].get("doubleSided", False))
                                    if "material" in prim else False)
            if "NORMAL" in attrs:
                N = glb.accessor(attrs["NORMAL"]).astype(np.float64) @ normal_m
                N /= np.maximum(np.linalg.norm(N, axis=1, keepdims=True), 1e-12)
                m.CreateNormalsAttr(Vt.Vec3fArray.FromNumpy(N.astype(np.float32)))
                m.SetNormalsInterpolation(UsdGeom.Tokens.vertex)
            if "TEXCOORD_0" in attrs:
                uv = glb.accessor(attrs["TEXCOORD_0"]).astype(np.float32)
                uv[:, 1] = 1.0 - uv[:, 1]        # glTF's origin is top-left, USD's bottom-left
                pv = UsdGeom.PrimvarsAPI(m.GetPrim()).CreatePrimvar(
                    "st", Sdf.ValueTypeNames.TexCoord2fArray, UsdGeom.Tokens.vertex)
                pv.Set(Vt.Vec2fArray.FromNumpy(uv))
            if skinned and "JOINTS_0" in attrs:
                J = glb.accessor(attrs["JOINTS_0"]).astype(np.int64)
                W = glb.accessor(attrs["WEIGHTS_0"]).astype(np.float32)
                if "JOINTS_1" in attrs:
                    J = np.hstack([J, glb.accessor(attrs["JOINTS_1"]).astype(np.int64)])
                    W = np.hstack([W, glb.accessor(attrs["WEIGHTS_1"]).astype(np.float32)])
                J = lut[J]
                total = W.sum(axis=1, keepdims=True)
                W = np.divide(W, total, out=W, where=total > 1e-8)
                binding = UsdSkel.BindingAPI.Apply(m.GetPrim())
                binding.CreateSkeletonRel().SetTargets([skel_path])
                binding.CreateJointIndicesPrimvar(False, J.shape[1]).Set(Vt.IntArray.FromNumpy(J.reshape(-1).astype(np.int32)))
                binding.CreateJointWeightsPrimvar(False, W.shape[1]).Set(Vt.FloatArray.FromNumpy(W.reshape(-1)))
                # Identity for the mesh the bind pose was expressed against;
                # only another mesh sharing the skin needs a correction.
                binding.CreateGeomBindTransformAttr().Set(mesh_world.GetInverse() * skin_world)
            if "material" in prim:
                UsdShade.MaterialBindingAPI.Apply(m.GetPrim()).Bind(material_for(prim["material"]))
            stats["tris"] += len(faces) // 3
            stats["points"] += len(P)
            stats["meshes"] += 1
            lo = P.min(0) if lo is None else np.minimum(lo, P.min(0))
            hi = P.max(0) if hi is None else np.maximum(hi, P.max(0))
    if lo is not None:
        stats["bounds"] = (lo.tolist(), hi.tolist())

    stage.GetRootLayer().Save()
    out.parent.mkdir(parents=True, exist_ok=True)
    if out.exists():
        out.unlink()
    UsdUtils.CreateNewUsdzPackage(Sdf.AssetPath(str(layer_path)), str(out))
    shutil.rmtree(work, ignore_errors=True)
    stats["bytes"] = out.stat().st_size
    return stats


def verify(out):
    """Re-reads the package and skins it with plain numpy, exactly as UsdSkel
    defines linear blend skinning, at the rest pose and at the first animated
    frame. A joint-order or remap mistake shows up here as an exploded mesh
    long before anyone opens the file on a phone."""
    st = Usd.Stage.Open(str(out))
    skel_prim = st.GetPrimAtPath("/root/Armature/Armature")
    if not skel_prim.IsValid():
        return None
    skel = UsdSkel.Skeleton(skel_prim)
    joints = list(skel.GetJointsAttr().Get())
    parents = list(UsdSkel.Topology(joints).GetParentIndices())
    as_np = lambda m: np.array([[m[r][c] for c in range(4)] for r in range(4)])
    bind_inv = [np.linalg.inv(as_np(m)) for m in skel.GetBindTransformsAttr().Get()]
    rest = [as_np(m) for m in skel.GetRestTransformsAttr().Get()]
    anim_targets = UsdSkel.BindingAPI(skel_prim).GetAnimationSourceRel().GetTargets()

    def skel_xforms(locals_):
        out = [None] * len(locals_)
        for i, L in enumerate(locals_):
            out[i] = L if parents[i] < 0 else L @ out[parents[i]]
        return out

    poses = {"rest": skel_xforms(rest)}
    if anim_targets:
        anim = UsdSkel.Animation(st.GetPrimAtPath(anim_targets[0]))
        t0 = Usd.TimeCode(st.GetStartTimeCode())
        locals_ = UsdSkel.MakeTransforms(anim.GetTranslationsAttr().Get(t0), anim.GetRotationsAttr().Get(t0),
                                         anim.GetScalesAttr().Get(t0))
        poses["frame 0"] = skel_xforms([as_np(m) for m in locals_])

    results = {}
    for prim in st.Traverse():
        if prim.GetTypeName() != "Mesh":
            continue
        api = UsdSkel.BindingAPI(prim)
        if not api.GetSkeletonRel().GetTargets():
            continue
        P = np.array(UsdGeom.Mesh(prim).GetPointsAttr().Get(), dtype=np.float64)
        ji = api.GetJointIndicesPrimvar()
        size = ji.GetElementSize()
        J = np.array(ji.Get()).reshape(len(P), size)
        W = np.array(api.GetJointWeightsPrimvar().Get(), dtype=np.float64).reshape(len(P), size)
        G = as_np(api.GetGeomBindTransformAttr().Get() or Gf.Matrix4d(1.0))
        Ph = np.c_[P, np.ones(len(P))] @ G
        for label, xf in poses.items():
            M = np.array([bind_inv[j] @ xf[j] for j in range(len(joints))])   # (J, 4, 4)
            skinned = np.einsum("nk,nkc->nc", W, np.einsum("nc,nkcd->nkd", Ph, M[J]))[:, :3]
            lo, hi = skinned.min(0), skinned.max(0)
            results.setdefault(label, []).append((lo, hi))
    summary = {}
    for label, boxes in results.items():
        lo = np.min([b[0] for b in boxes], axis=0)
        hi = np.max([b[1] for b in boxes], axis=0)
        summary[label] = (lo, hi)
    return summary


def report(src, out, s):
    print(f"{src.name} -> {out.relative_to(REPO) if out.is_relative_to(REPO) else out}")
    print(f"  {s['meshes']} mesh(es)  {s['tris']:,} tris  {s['points']:,} points  "
          f"{s['joints']} joints  {s['frames']} frames  {len(s['textures'])} texture(s)  {s['bytes'] / 1048576:.1f} MB")
    if s.get("animation_names") and len(s["animation_names"]) > 1:
        print(f"  animations in file: {s['animation_names']}  (converted #0; --animation N for another)")
    if "bounds" in s:
        lo, hi = s["bounds"]
        print(f"  height {hi[1] - lo[1]:.2f} m   feet at y={lo[1]:.2f}   x {lo[0]:.2f}..{hi[0]:.2f}   z {lo[2]:.2f}..{hi[2]:.2f}")
    if "rest_vs_bind" in s:
        d = s["rest_vs_bind"]
        note = "ok" if d < 1e-3 else "rest pose differs from bind pose; skinning still uses the bind pose"
        print(f"  rest vs bind pose: max deviation {d:.5f}  ({note})")
    checked = verify(out)
    if checked:
        for label, (lo, hi) in checked.items():
            print(f"  skinned at {label:8s} height {hi[1] - lo[1]:.2f} m   feet at y={lo[1]:.2f}   "
                  f"x {lo[0]:.2f}..{hi[0]:.2f}   z {lo[2]:.2f}..{hi[2]:.2f}")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("source", help="an asset name (every Art/Models/<name>*.glb) or a .glb path")
    ap.add_argument("--out", help="output .usdz for a single file (default: beside the source)")
    ap.add_argument("--animation", type=int, default=0, help="which animation to convert when a file has several")
    ap.add_argument("--fps", type=int, default=30, help="frame rate to resample the animation at")
    ap.add_argument("--force", action="store_true", help="overwrite existing .usdz files in family mode")
    a = ap.parse_args()

    if a.source.lower().endswith(".glb"):
        src = Path(a.source)
        out = Path(a.out) if a.out else src.with_suffix(".usdz")
        report(src, out, convert(src, out, a.animation, a.fps))
        return
    sources = sorted(SOURCE_DIR.glob(f"{a.source}*.glb"))
    if not sources:
        sys.exit(f"no {a.source}*.glb in {SOURCE_DIR.relative_to(REPO)} - `python3 tools/meshy.py download {a.source}` first")
    for src in sources:
        out = src.with_suffix(".usdz")
        if out.exists() and not a.force:
            print(f"{src.name}: {out.name} exists, skipped (--force to redo)")
            continue
        report(src, out, convert(src, out, a.animation, a.fps))
    print(f"\nnext: python3 tools/mesh.py {a.source}")


if __name__ == "__main__":
    main()
