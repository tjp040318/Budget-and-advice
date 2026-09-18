#!/usr/bin/env python3
"""Retarget a clip from one Meshy rig onto another, offline (2026-09-18).

Meshy keeps a text-to-motion task about THREE days (its task list held one
of the five gods' fifteen bespoke motions on the 18th, the ultimate remade
on the 17th; every task of the 15th answered 404), and the Animation API
applies a motion by its task id, so a re-rigged family cannot have its paid
clips re-applied at Meshy once the tasks are gone. The clips themselves
survive as the rigged GLBs `meshy.py download` fetched at the time
(`Art/Models/<asset>_<clip>.glb`: the OLD mesh and rig with the motion on
it), and a motion is only rotations: this tool carries them over.

The sum: both rigs are read with `character.read_glb` (the same Y-up world),
the joints are matched by name (Meshy's auto-rig names them the same on
every body: Hips, Spine, LeftArm, ...), and for every matched joint the
change of its WORLD rotation from the source's rest pose to the source's
animated pose is applied to the target's rest world rotation - a
world-space delta, so the two rigs' local joint frames (which Meshy does
not keep consistent: the base Ares's pelvis sat 150 degrees from the
awakened one's, run 190) do not matter, only that both rest poses stand
the same way, which two A-poses do. The hips' travel is scaled by the two
hips' rest heights; every other joint keeps the target's bone lengths.
The result is written back into the target's clip GLB (the preset clip the
wave made, kept beside it as `.preset.glb`) as ONE animation of the source's
length and rate, so `mesh.py <asset> --as <family> --only-clips <clip>`
ships it through the same path as any Meshy clip - grounding, carrier,
bind check - and `BattleSceneController.contactFraction`'s blow frames,
measured on the source clips, still hold because the timing is the same.

A `.motion.npz` archive (`--archive`, default Art/Motions/<family>_<clip>)
keeps the source rig's names, rest and tracks - about a fifth of a
megabyte - and is accepted as a source in place of the GLB, so the paid
motions outlive both Meshy's retention and this container.

  python3 tools/retarget.py Art/Models/anubis_m7_ultimate.glb Art/Models/anubis_serious_ultimate.glb \
      --archive Art/Motions/anubis_ultimate.motion.npz --board /tmp/retarget_anubis_ultimate.jpg
  python3 tools/retarget.py Art/Motions/anubis_ultimate.motion.npz Art/Models/anubis_serious_ultimate.glb
  python3 tools/mesh.py anubis_serious --as anubis --only-clips ultimate
"""
import argparse
import json
import struct
import subprocess
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
import character                                                         # noqa: E402
from character import Glb, decompose, quat_to_rot, read_glb, rot_to_quat, trs, world_from_local   # noqa: E402

REPO = Path(__file__).resolve().parents[1]
GLB_MAGIC, CHUNK_JSON, CHUNK_BIN = 0x46546C67, 0x4E4F534A, 0x004E4942


def leaf(joint):
    return joint.split("/")[-1].lower()


def rotation_part(m):
    """The 3x3 rotation of a row-convention TRS, scale and any mirror removed."""
    a = m[:3, :3].copy()
    s = np.linalg.norm(a, axis=1)
    s[s < 1e-12] = 1e-12
    r = a / s[:, None]
    if np.linalg.det(r) < 0:
        r[2] *= -1
    u, _, vt = np.linalg.svd(r)
    r = u @ vt
    if np.linalg.det(r) < 0:
        u[:, -1] *= -1
        r = u @ vt
    return r


class Motion:
    """A rig's joints, rest and one clip - what a retarget needs of a source."""

    def __init__(self, joints, parents, rest_local, anim, source=""):
        self.joints, self.parents, self.rest_local, self.anim, self.source = list(joints), np.asarray(parents), np.asarray(rest_local), anim, source

    def joint_world_at_rest(self):
        return world_from_local(self.rest_local, self.parents)

    def joint_world_at(self, frame):
        a = self.anim
        local = np.array([trs(a["T"][frame, j], a["R"][frame, j], a["S"][frame, j]) for j in range(len(self.joints))])
        return world_from_local(local, self.parents)

    def joint_index(self, suffix):
        hits = [i for i, j in enumerate(self.joints) if leaf(j).endswith(suffix.lower())]
        return hits[0] if hits else None

    @classmethod
    def from_char(cls, char):
        return cls(char.joints, char.parents, char.rest_local, char.anim, char.source)

    @classmethod
    def load(cls, path):
        z = np.load(path, allow_pickle=False)
        anim = {"T": z["T"], "R": z["R"], "S": z["S"], "fps": float(z["fps"])}
        return cls([str(j) for j in z["joints"]], z["parents"], z["rest_local"], anim, str(path))

    def save(self, path):
        path = Path(path)
        path.parent.mkdir(parents=True, exist_ok=True)
        a = self.anim
        np.savez_compressed(path, joints=np.array(self.joints), parents=self.parents, rest_local=self.rest_local,
                            T=a["T"].astype(np.float32), R=a["R"].astype(np.float32), S=a["S"].astype(np.float32),
                            fps=np.float64(a["fps"]), source=np.array(self.source))


def load_source(path):
    path = Path(path)
    if path.suffix == ".npz":
        return Motion.load(path)
    char = read_glb(path)
    if not char.anim:
        sys.exit(f"{path.name}: no animation to retarget")
    return Motion.from_char(char)


def facing_yaw(rig):
    """The yaw (radians about Y) the rig's rest pose faces: left shoulder minus
    right, crossed with up (a figure facing +Z keeps its left at +X)."""
    W = rig.joint_world_at_rest()
    pairs = (("leftarm", "rightarm"), ("leftshoulder", "rightshoulder"), ("leftupleg", "rightupleg"), ("leftfoot", "rightfoot"))
    for l, r in pairs:
        li, ri = rig.joint_index(l), rig.joint_index(r)
        if li is not None and ri is not None:
            d = W[li][3, :3] - W[ri][3, :3]
            f = np.cross(d, np.array([0.0, 1.0, 0.0]))
            if np.linalg.norm(f) > 1e-9:
                return float(np.arctan2(f[0], f[2]))
    return 0.0


def y_rotation(angle):
    return trs([0, 0, 0], [0.0, np.sin(angle / 2), 0.0, np.cos(angle / 2)], [1, 1, 1])


def retarget(src, tgt):
    """-> (anim for the target's joints, unmatched target joints, facts)."""
    by_name = {leaf(j): i for i, j in enumerate(src.joints)}
    match = [by_name.get(leaf(j)) for j in tgt.joints]
    missing = [tgt.joints[i] for i, m in enumerate(match) if m is None]
    unused = sorted(set(by_name) - {leaf(tgt.joints[i]) for i, m in enumerate(match) if m is not None})

    # Both rest poses must stand the same way in the world; a rig that faces
    # elsewhere is turned about Y first (the delta is then read in the turned world).
    yaw_s, yaw_t = facing_yaw(src), facing_yaw(tgt)
    diff = (yaw_t - yaw_s + np.pi) % (2 * np.pi) - np.pi
    if abs(diff) < np.radians(15):
        diff = 0.0            # two A-poses a few degrees apart are the same facing; the shoulders' asymmetry is not a turn
    turn = y_rotation(diff)
    Ws0 = src.joint_world_at_rest() @ turn
    Wt0 = tgt.joint_world_at_rest()
    Rs0 = [rotation_part(m) for m in Ws0]
    Rt0 = [rotation_part(m) for m in Wt0]

    hs, ht = src.joint_index("hips"), tgt.joint_index("hips")
    if hs is None or ht is None:
        hs, ht = 0, 0
    k = Wt0[ht][3, 1] / Ws0[hs][3, 1] if Ws0[hs][3, 1] > 1e-6 and Wt0[ht][3, 1] > 1e-6 else 1.0

    F, J = len(src.anim["T"]), len(tgt.joints)
    rest_parts = [decompose(m) for m in tgt.rest_local]
    T = np.empty((F, J, 3))
    R = np.empty((F, J, 4))
    S = np.empty((F, J, 3))
    for f in range(F):
        Ws = src.joint_world_at(f) @ turn
        Wt_rot = [None] * J
        for j in range(J):
            sj, p = match[j], tgt.parents[j]
            if sj is None:
                loc_r = rotation_part(tgt.rest_local[j])
                Wt_rot[j] = loc_r @ Wt_rot[p] if p >= 0 else loc_r
                q = rest_parts[j][1]
            else:
                delta = Rs0[sj].T @ rotation_part(Ws[sj])          # the bone's own turn since rest, in the world
                Rw = Rt0[j] @ delta
                Wt_rot[j] = Rw
                loc_r = Rw @ Wt_rot[p].T if p >= 0 else Rw
                q = rot_to_quat(loc_r)
            if f and np.dot(q, R[f - 1, j]) < 0:
                q = -q                                             # one sign along the track, so nothing spins the long way
            R[f, j] = q
            S[f, j] = rest_parts[j][2]
            if p < 0 and sj is not None:
                T[f, j] = Wt0[j][3, :3] + k * (Ws[sj][3, :3] - Ws0[sj][3, :3])
            else:
                T[f, j] = rest_parts[j][0]
    facts = dict(frames=F, fps=src.anim["fps"], matched=J - len(missing), joints=J, source_joints=len(src.joints),
                 unused=unused, hips_scale=k, yaw_source=np.degrees(yaw_s), yaw_target=np.degrees(yaw_t))
    return {"T": T, "R": R, "S": S, "fps": src.anim["fps"]}, missing, facts


def joint_node_order(g):
    """The skin's joint nodes in character.read_glb's order (depth, then the skin's order)."""
    nodes = g.get("nodes", [])
    parent = {i: None for i in range(len(nodes))}
    for i, n in enumerate(nodes):
        for c in n.get("children", []):
            parent[c] = i
    skin_def = g["skins"][0]
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
    return order, parent


def write_clip(target_glb, out_path, tgt, anim, name):
    """The target GLB with its animation replaced by `anim` (the target's joints, in character order)."""
    glb = Glb(target_glb)
    g = glb.json
    if "skins" not in g or not g["skins"]:
        sys.exit(f"{target_glb}: no skin")
    if g["buffers"][0].get("uri"):
        sys.exit(f"{target_glb}: buffer 0 is external; only an embedded BIN chunk is supported")
    order, parent = joint_node_order(g)
    nodes = g["nodes"]
    if len(order) != len(tgt.joints):
        sys.exit(f"{target_glb}: {len(order)} joint nodes but the rig read {len(tgt.joints)} joints")
    for k, i in enumerate(order):
        want = leaf(tgt.joints[k])
        have = (nodes[i].get("name") or f"joint_{i}").lower()
        if not (have == want or want.startswith(have) or have.replace(".", "_").replace("-", "_") == want):
            sys.exit(f"{target_glb}: joint {k} is node {i} '{nodes[i].get('name')}' but the rig read '{tgt.joints[k]}'")

    world_cache = {}

    def world(i):
        if i not in world_cache:
            m = trs(*character._node_trs(nodes[i]))
            world_cache[i] = m if parent[i] is None else m @ world(parent[i])
        return world_cache[i]

    bin_ = bytearray(glb.bin)
    accessors = g.setdefault("accessors", [])
    views = g.setdefault("bufferViews", [])

    def add(arr, typ, minmax=False):
        arr = np.ascontiguousarray(arr, dtype=np.float32)
        while len(bin_) % 4:
            bin_.append(0)
        off = len(bin_)
        bin_.extend(arr.tobytes())
        views.append({"buffer": 0, "byteOffset": off, "byteLength": int(arr.nbytes)})
        acc = {"bufferView": len(views) - 1, "componentType": 5126, "count": int(arr.shape[0]), "type": typ}
        if minmax:
            acc["min"] = [float(arr.min())]
            acc["max"] = [float(arr.max())]
        accessors.append(acc)
        return len(accessors) - 1

    F = len(anim["T"])
    t_in = add(np.arange(F) / anim["fps"], "SCALAR", minmax=True)
    samplers, channels = [], []
    for k, i in enumerate(order):
        Tk, Rk, Sk = anim["T"][:, k].copy(), anim["R"][:, k].copy(), anim["S"][:, k].copy()
        if tgt.parents[k] < 0 and parent[i] is not None:
            above = world(parent[i])
            if not np.allclose(above, np.eye(4), atol=1e-6):
                # read_glb folded the non-joint node above the root into the
                # root's track; the file wants the root relative to that node.
                inv = np.linalg.inv(above)
                for f in range(F):
                    Tk[f], Rk[f], Sk[f] = decompose(trs(Tk[f], Rk[f], Sk[f]) @ inv)
                for f in range(1, F):
                    if np.dot(Rk[f], Rk[f - 1]) < 0:
                        Rk[f] = -Rk[f]
        for path, data, typ in (("translation", Tk, "VEC3"), ("rotation", Rk, "VEC4"), ("scale", Sk, "VEC3")):
            samplers.append({"input": t_in, "output": add(data, typ), "interpolation": "LINEAR"})
            channels.append({"sampler": len(samplers) - 1, "target": {"node": i, "path": path}})
    g["animations"] = [{"name": name, "samplers": samplers, "channels": channels}]
    g["buffers"][0]["byteLength"] = len(bin_)

    js = json.dumps(g, separators=(",", ":")).encode("utf-8")
    while len(js) % 4:
        js += b" "
    while len(bin_) % 4:
        bin_.append(0)
    out_path = Path(out_path)
    with open(out_path, "wb") as f:
        f.write(struct.pack("<III", GLB_MAGIC, 2, 12 + 8 + len(js) + 8 + len(bin_)))
        f.write(struct.pack("<II", len(js), CHUNK_JSON))
        f.write(js)
        f.write(struct.pack("<II", len(bin_), CHUNK_BIN))
        f.write(bytes(bin_))
    return out_path


def check(out_path, tgt, anim, frames=(0, None, -1)):
    """Re-read the written file and measure how far its world rotations are from the intended ones."""
    back = read_glb(out_path)
    if len(back.anim["T"]) != len(anim["T"]):
        return float("inf"), f"{len(back.anim['T'])} frames read back, {len(anim['T'])} written"
    worst = 0.0
    for f in frames:
        f = len(anim["T"]) // 2 if f is None else (len(anim["T"]) - 1 if f == -1 else f)
        want = world_from_local(np.array([trs(anim["T"][f, j], anim["R"][f, j], anim["S"][f, j]) for j in range(len(tgt.joints))]), tgt.parents)
        got = back.joint_world_at(f)
        for j in range(len(tgt.joints)):
            d = rotation_part(want[j]).T @ rotation_part(got[j])
            ang = np.degrees(np.arccos(np.clip((np.trace(d) - 1) / 2, -1, 1)))
            worst = max(worst, ang)
    return worst, ""


def board(source_glb, out_glb, out_jpg, fractions=(0.0, 0.25, 0.5, 0.75, 1.0), size=240):
    """Source and result posed at the same fractions of the clip, side by side."""
    from PIL import Image, ImageDraw
    src, res = read_glb(source_glb), read_glb(out_glb)
    rows = []
    for fr in fractions:
        pair = []
        for path, ch in ((source_glb, src), (out_glb, res)):
            n = max(0, min(int(round(fr * (len(ch.anim["T"]) - 1))), len(ch.anim["T"]) - 1))
            png = Path("/tmp") / f"retarget_{Path(path).stem}_{n}.png"
            subprocess.run([sys.executable, str(REPO / "tools/preview.py"), str(path), "--frame", str(n), "--size", str(size), "--out", str(png)],
                           check=True, capture_output=True)
            pair.append((n, Image.open(png).convert("RGB")))
        rows.append((fr, pair))
    w = max(a.width + b.width for _, ((_, a), (_, b)) in rows) + 30
    h = sum(max(a.height, b.height) + 30 for _, ((_, a), (_, b)) in rows) + 10
    sheet = Image.new("RGB", (w, h), (36, 36, 36))
    d = ImageDraw.Draw(sheet)
    y = 10
    for fr, ((na, a), (nb, b)) in rows:
        d.text((12, y), f"{int(fr * 100)}%   source {Path(source_glb).name} frame {na}", fill=(255, 220, 120))
        d.text((a.width + 22, y), f"retargeted {Path(out_glb).name} frame {nb}", fill=(160, 255, 160))
        sheet.paste(a, (10, y + 18))
        sheet.paste(b, (a.width + 20, y + 18))
        y += max(a.height, b.height) + 30
    sheet.save(out_jpg, quality=88)
    return out_jpg


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("source", help="the clip to carry over: a rigged GLB with the motion on it, or a .motion.npz archive")
    ap.add_argument("target", help="the new rig's clip GLB (Art/Models/<asset>_<clip>.glb); its animation is replaced")
    ap.add_argument("--out", help="write here instead of over the target (the target is then left alone)")
    ap.add_argument("--rig", help="read the target rig from this GLB instead (default: the .preset.glb kept beside the target, else the target)")
    ap.add_argument("--archive", help="save the source motion as this .motion.npz (default Art/Motions/<family>_<clip>.motion.npz for a GLB source)")
    ap.add_argument("--no-archive", action="store_true")
    ap.add_argument("--board", help="render source and result at five fractions of the clip to this JPEG")
    ap.add_argument("--dry-run", action="store_true", help="retarget and report, write nothing")
    args = ap.parse_args()

    target = Path(args.target)
    preset = target.with_suffix(".preset.glb")
    rig_path = Path(args.rig) if args.rig else (preset if preset.exists() else target)
    print(f"source  {args.source}")
    print(f"rig     {rig_path}")
    src = load_source(args.source)
    tgt = read_glb(rig_path)
    anim, missing, facts = retarget(src, tgt)
    print(f"  {facts['frames']} frames at {facts['fps']:.0f} fps; {facts['matched']} of {facts['joints']} target joints matched "
          f"(source has {facts['source_joints']}); hips scale x{facts['hips_scale']:.3f}; "
          f"facing {facts['yaw_source']:.0f} deg -> {facts['yaw_target']:.0f} deg")
    if missing:
        print(f"  target joints kept at rest (no source joint of the name): {', '.join(leaf(j) for j in missing)}")
    if facts["unused"]:
        print(f"  source joints without a target: {', '.join(facts['unused'])}")
    if facts["matched"] < 0.8 * facts["joints"]:
        sys.exit("  fewer than 80% of the joints matched by name; not the same rigger's skeleton")

    if not args.no_archive and Path(args.source).suffix != ".npz":
        arch = Path(args.archive) if args.archive else REPO / "Art/Motions" / (Path(args.source).stem.replace("_m7_", "_").replace("_hd_", "_") + ".motion.npz")
        src.save(arch)
        print(f"  archived the source motion -> {arch.relative_to(REPO) if arch.is_relative_to(REPO) else arch}")
    if args.dry_run:
        return
    out = Path(args.out) if args.out else target
    if out == target and not preset.exists():
        target.rename(preset)
        print(f"  kept the target's own clip as {preset.name}")
        rig_path = preset
    write_clip(rig_path, out, tgt, anim, f"{target.stem}")
    worst, why = check(out, tgt, anim)
    print(f"  wrote {out}  ({out.stat().st_size / 1048576:.1f} MB); read back: worst joint {worst:.2f} deg from the intended pose {why}")
    if worst > 0.5:
        sys.exit("  the file does not read back as written")
    if args.board:
        print(f"  board -> {board(args.source if Path(args.source).suffix == '.glb' else str(rig_path), out, args.board)}")


if __name__ == "__main__":
    main()
