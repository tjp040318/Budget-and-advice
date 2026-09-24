#!/usr/bin/env python3
"""Clips that do not fit their mesh (2026-09-23): fixes made on the CLIP
CARRIERS (and, for one family, the base mesh) of shipped families, found by
measurement and judged on before/after boards, the way tools/weapon_pass.py
is. Nothing here spends a credit.

    python3 tools/clip_fix.py --mirror hephaestus attack_heavy --out DIR
    python3 tools/clip_fix.py --survey-arms                      # every family's arms vs the archived preset
    python3 tools/clip_fix.py --rearm baldr --out DIR            # every clip; the standing idle re-derived
    python3 tools/clip_fix.py --mirror skadi attack_basic,attack_heavy,ultimate --bow-wrist --out DIR
    python3 tools/clip_fix.py --lift-snout sobek attack_heavy,ultimate --limit 75 --out DIR
    python3 tools/clip_fix.py --skirt skadi --out DIR            # character.reweight_skirt, base + LOD
    python3 tools/clip_fix.py --pieces diana                     # connected pieces, largest first
    python3 tools/clip_fix.py --bind-piece diana 1 Spine01 --out DIR
    python3 tools/clip_fix.py --self-test
    python3 tools/clip_fix.py --board hephaestus attack_heavy --frames 25,36 --out DIR   # before | after
    python3 tools/clip_fix.py --apply-all --out DIR              # every judged fix (FIXES) into DIR

Every mode reads the shipped files from --bundle (default the app's bundle)
and writes into --out, the same file names; `--in-place` writes the bundle
(the owner's call, never the default). A carrier keeps its 1,500-triangle
mesh, its skeleton, bind and rest exactly; only the animation changes, so
the game drops it in: ModelLibrary.firstAnimation gathers a clip's tracks
by the NODE NAME of each joint (`"/\\(track.node).\\(keyPath)"`, the joint's
leaf name) and plays them on the figure's own nodes of that name, the way
tools/base_plus_clip.py matches them.

1. MIRROR (--mirror). A clip swung by the empty hand: the Heavy Hammer Swing
   (preset 128) raises the LEFT arm, and Hephaestus holds his hammer in the
   RIGHT; the archer presets (224, 226, 222) hold the bow in the LEFT and
   draw with the right, and Skadi's bow is in her right. The clip is
   reflected across the figure's own sagittal plane, measured off the rest
   skeleton (the mid-points of the Left/Right joint pairs and the mean
   left-minus-right direction; the canonical figures stand 11-13 cm off x=0,
   so x=0 is not the plane). No per-axis quaternion rule is trusted — Meshy's
   joint frames are not mirror images of each other (Baldr's left forearm is
   rolled 90 degrees from the right's). The mirror is done on what the mesh
   SEES, the skinning matrix: for a reflection M (an involution), joint m(j)
   (the other side's joint, or j itself on the spine) takes
       W'[m(j)] = B[m(j)] . M . B[j]^-1 . W[j] . M          (row vectors)
   so a vertex bound to m(j), mirrored, lands where the mirror image of j's
   vertex lands: the posed mesh is the reflection of the original pose for a
   symmetric body. The local tracks are read back off W' through the rig's
   own parents; every joint but the root keeps its own translation track
   (its bone length), the root takes the reflected hips' travel. The feet
   swap, the stance is the other foot forward; heights are kept (the plane
   is vertical), so the grounding holds.

2. RE-ARM (--rearm). Frigg, Baldr, Chang'e and the Cobra Priestess hold
   both arms overhead in EVERY clip, the walk and the combat idle included.
   The cause is not in this pipeline: the carriers' bind and rest equal the
   base's to 0.0, the raw rig GLB's rest equals the shipped one, the hips'
   120-degree rest-to-clip turn is the canonical frame (every family has
   it). It is in Meshy's application of its presets to these rigs: measured
   against the same preset archived on the donor rig
   (Art/Motions/preset_<id>.motion.npz, tools/motion_palette.py), every
   body joint's world-space turn from rest agrees within 8 degrees on every
   family, and the ARM chain (Arm, ForeArm, Hand, both sides) is off by
   106-155 degrees on these four, 89 on Odin and Pluto, 70 on Atalanta,
   40-54 on Njord, Heimdall and the dark elf (`--survey-arms`; a clean family
   reads 1-20). The fix replaces the arm chain's LOCAL rotation tracks with
   the ones tools/retarget.py's world-space delta puts on this rig from the
   archived preset (the same preset id the family shipped, read off
   Art/Models/<asset>.meshy.json; the frame counts match to the frame), and
   keeps every other track as shipped — the hips, legs and spine, and so the
   grounding and the feet, do not move. The standing idle (<fam>_idle.usdz)
   is re-derived from the fixed combat idle by tools/stand_idle.py's own sum.

   --bow-wrist: the concept's grip (the rigger's rule: everything held
   hangs along the thigh) holds a bow ALONG the forearm, so an arm raised to
   aim lays it flat; a constant bend of the bow hand, found at the loose
   (motion_palette.PRESET_CUTS' blow frame), stands it upright (bow_wrist).

3. THE SNOUT (--lift-snout). A human's head looks down its own front on a
   follow-through; Sobek's half-metre jaw goes into his ribs (25 degrees
   from the torso line on the Charged Ground Slam). The head and neck are
   turned out to `--limit` degrees from the neck->hips line (lift_snout).
   Damping the neck and head's local turn (--damp-neck, kept for the record)
   changed nothing a board shows: the fold is the torso's lean.

4. PIECES (--pieces, --bind-piece, --skirt). Diana's bow is slung, not held
   (24 cm from her hand, 34% shoulder / 28% thigh / 12% arm): bound rigidly
   to the torso. Apollo's third arm is in his concept and welded into the
   torso and skirt: --drop-piece refuses, and says why.
"""
import argparse
import copy
import io
import contextlib
import json
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
import character                                                            # noqa: E402
from character import decompose, local_from_world, trs, world_from_local   # noqa: E402

REPO = Path(__file__).resolve().parents[1]
BUNDLE = REPO / "Pantheon" / "Resources" / "Models"
ART = REPO / "Art" / "Models"
MOTIONS = REPO / "Art" / "Motions"

# The judged fixes (each on its board, see the report of 2026-09-23). Filled
# in as the boards pass; --apply-all runs exactly these.
#
# The motion palette's roll-out (2026-09-24, Docs/MOTION.md *As rolled out*)
# replaced every family's attack, stance and victory clips, and
# tools/motion_palette.py `ship` now makes the clip-level fixes itself on the
# clips it deals: a preset swung in the other hand from the family's weapon
# is MIRRORED before the retarget (motion_palette.PRESET_SIDE, WEAPON_HAND),
# Skadi's bow wrist is bent after (BOW_WRIST) and Sobek's snout lifted
# (SNOUT). So Hephaestus's mirror of his old heavy (128; the deal gives him
# 237 now, swung in his own hammer hand), Skadi's mirror and Sobek's snout are
# out of this table: run again on the palette's clips they would undo the
# palette's fix or mirror a clip already in the right hand. Their markers
# (Art/Models/<family>.clipfix.json) record what was applied on the 23rd. The
# re-arm stays: it still fits the walk, hit and death clips the palette does
# not deal, and it refuses a palette clip by its frame count.
FIXES = {
    # the coat panel welded to Skadi's bow hand given back to the body (the skirt pass, base + LOD)
    "skadi": [("skirt", None, {})],
    # Meshy put the presets' arms 40-175 degrees off on these rigs: the arm chains re-expressed from the
    # archive (every clip that IS its preset; bespoke clips are refused by frame count and body match)
    **{f: [("rearm", None, {})] for f in ("frigg", "baldr", "chang_e", "cobra_priestess", "pluto", "odin",
                                          "atalanta", "njord", "heimdall", "ares", "dark_elf")},
    # judged and left: fenrir (38 deg; the board is a wash and the stretch rose 3-13%), and nuwa, aphrodite,
    # light_elf, horus (22-32 deg: nothing a frame shows changes)
    # the slung bow, blended over shoulder, thigh and arm, made rigid on the torso (a stopgap: her archer
    # clips still draw with empty hands - the concept slings the bow, it does not hold it)
    "diana": [("bind", None, {"rank": 1, "size": 799, "joint": "Spine01"})],
}


def leaf(j):
    return j.split("/")[-1]


def read(path):
    with contextlib.redirect_stdout(io.StringIO()):
        return character.read_usdz(str(path))


def write_carrier(char, out):
    out = Path(out)
    out.parent.mkdir(parents=True, exist_ok=True)
    size = character.write_usdz(char, out)
    facts = character.verify(out, check_bounds=False, quiet=True)
    probs = [p for p in facts["problems"] if not p.startswith("feet at")]
    print(f"    -> {out}  {size / 1024:.0f} KB{'  PROBLEMS: ' + '; '.join(probs) if probs else ''}")
    return probs


def continuous(R):
    """One sign along every quaternion track, so nothing spins the long way."""
    R = R.copy()
    for f in range(1, len(R)):
        flip = np.sum(R[f] * R[f - 1], axis=-1) < 0
        R[f, flip] *= -1
    return R


# ---------------------------------------------------------------------------
# 1. Mirror
# ---------------------------------------------------------------------------

def mirror_map(joints):
    names = [leaf(j) for j in joints]
    idx = {n: i for i, n in enumerate(names)}
    out = []
    for n in names:
        if n.startswith("Left"):
            out.append(idx.get("Right" + n[4:]))
        elif n.startswith("Right"):
            out.append(idx.get("Left" + n[5:]))
        else:
            out.append(idx[n])
    if None in out:
        raise SystemExit(f"a Left/Right joint has no partner: {[names[i] for i, m in enumerate(out) if m is None]}")
    return out


TWIST_JOINTS = ("Hips", "Spine", "Spine01", "Spine02", "neck", "Head", "LeftUpLeg", "LeftLeg", "LeftFoot",
                "LeftShoulder", "RightUpLeg", "RightLeg", "RightFoot", "RightShoulder")


def plane_twist(char, pairs, n, R0=None):
    """The rms twist (degrees) that the reflection across normal n leaves
    between each body joint's mirrored rest frame and its partner's."""
    A = np.eye(3) - 2 * np.outer(n, n)
    R0 = R0 if R0 is not None else [unit_rot(m) for m in char.joint_world_at_rest()]
    names = [leaf(j) for j in char.joints]
    err = []
    for j, k in enumerate(pairs):
        if names[j] not in TWIST_JOINTS:
            continue
        err.append(min(angle(np.diag([-1.0 if i == ax else 1.0 for i in range(3)]) @ R0[j] @ A, R0[k]) for ax in range(3)))
    return float(np.sqrt(np.mean(np.square(err))))


def sagittal_plane(char, pairs):
    """(n, c, asymmetry): the figure's mirror plane. Its normal is found where
    Meshy's own joint FRAMES are mirror images (the donor rig's left and
    right frames are, to 1-2 degrees, under the plain reflection): a search
    over the yaw of a vertical plane for the least twist between each body
    joint's reflected rest frame and its partner's. The joint POSITIONS are
    no guide - an A-pose stands with one foot ahead, which reads as a plane
    turned 6-19 degrees. It passes through the hips. The asymmetry is the
    worst Left/Right pair's distance from the reflection of its partner at
    rest (a weapon arm bent across the chest reads 0.3 m)."""
    W = char.joint_world_at_rest()
    P = W[:, 3, :3]
    R0 = [unit_rot(m) for m in W]
    best = None
    for yaw in np.radians(np.arange(-45.0, 45.01, 0.5)):
        n = np.array([np.cos(yaw), 0.0, np.sin(yaw)])
        t = plane_twist(char, pairs, n, R0)
        if best is None or t < best[0]:
            best = (t, n)
    twist, n = best
    L = [i for i, m in enumerate(pairs) if m != i and leaf(char.joints[i]).startswith("Left")]
    d = np.sum([P[i] - P[pairs[i]] for i in L], axis=0)
    if np.dot(d, n) < 0:
        n = -n
    hips = next((i for i, j in enumerate(char.joints) if leaf(j).lower() == "hips"), 0)
    c = P[hips]
    refl = lambda p: p - 2 * np.dot(p - c, n) * n
    asym = max(np.linalg.norm(refl(P[i]) - P[pairs[i]]) for i in L)
    return n, c, asym


def reflection(n, c):
    """4x4 row-vector reflection across the plane through c with normal n."""
    A = np.eye(3) - 2 * np.outer(n, n)
    M = np.eye(4)
    M[:3, :3] = A
    M[3, :3] = 2 * np.dot(c, n) * n
    return M


def unit_rot(m):
    r = np.asarray(m, dtype=np.float64)[:3, :3]
    return r / np.linalg.norm(r, axis=1)[:, None]


def swing(u, v):
    """The shortest world rotation (row form) taking unit u to unit v."""
    u, v = u / np.linalg.norm(u), v / np.linalg.norm(v)
    w = np.cross(u, v)
    s, c = np.linalg.norm(w), float(np.dot(u, v))
    if s < 1e-9:
        if c > 0:
            return np.eye(3)
        q = np.cross(u, np.eye(3)[np.argmin(np.abs(u))])
        q /= np.linalg.norm(q)
        return 2 * np.outer(q, q) - np.eye(3)
    k = w / s
    K = np.array([[0, -k[2], k[1]], [k[2], 0, -k[0]], [-k[1], k[0], 0]])
    col = np.eye(3) + s * K + (1 - c) * K @ K
    return col.T


def bone_axes(char):
    """Each joint's bone axis in its own frame: the direction of its first
    child's rest offset (a leaf takes its parent's)."""
    J = len(char.joints)
    axes = [None] * J
    for j in range(J):
        kids = [k for k in range(J) if char.parents[k] == j]
        if kids:
            t = char.rest_local[kids[0]][3, :3]
            if np.linalg.norm(t) > 1e-6:
                axes[j] = t / np.linalg.norm(t)
    for j in range(J):
        if axes[j] is None:
            p = char.parents[j]
            axes[j] = axes[p] if p >= 0 and axes[p] is not None else np.array([0.0, 1.0, 0.0])
    return axes


def kabsch_rows(X, Y):
    """The rotation C (row form) minimising sum |x C - y|^2 over the rows."""
    H = X.T @ Y
    U, _, Vt = np.linalg.svd(H)
    d = np.sign(np.linalg.det(U @ Vt))
    D = np.diag([1.0, 1.0, d])
    return U @ D @ Vt


def mirror_calibration(char, pairs, n):
    """Per joint k (the image of j): P_k, the local axis the reflection
    flips (the one of three landing nearest k's rest frame - the local X on
    every Meshy rig measured), and C_k, the local correction that makes
    C_k . P_k . R_j . A a frame in k's own convention:
      * a joint with two or more children (the hips, the upper spine): the
        rotation that carries its children's offsets onto their partners'
        (t[m(c)] . C . P = t[c], a least-squares fit) - so the legs and the
        shoulders land where the reflection puts them;
      * a joint with one child or none (every limb bone, the neck): a pure
        TWIST about its bone, read off the rest (Meshy's left and right
        frames are rolled differently about the bone - Baldr's forearms 90
        degrees - and a twist moves no joint), never a swing, which would
        carry the rest POSE's asymmetry (a weapon arm bent across the chest)
        into the mirror."""
    A = np.eye(3) - 2 * np.outer(n, n)
    R0 = [unit_rot(m) for m in char.joint_world_at_rest()]
    axes = bone_axes(char)
    J = len(pairs)
    kids = [[c for c in range(J) if char.parents[c] == j] for j in range(J)]
    P, C = [None] * J, [None] * J
    for j, k in enumerate(pairs):
        best = None
        single = len([c for c in kids[j] if np.linalg.norm(char.rest_local[c][3, :3]) > 1e-6]) < 2
        for ax in range(3):
            if single and abs(axes[j][ax]) > 0.7:
                continue      # never the bone's own axis: the bone would point backwards
            Pm = np.eye(3); Pm[ax, ax] = -1
            G = Pm @ R0[j] @ A
            d = angle(G, R0[k])
            if best is None or d < best[0]:
                best = (d, Pm, G)
        _, Pm, G = best
        P[k] = Pm
        offs = [(char.rest_local[pairs[c]][3, :3], char.rest_local[c][3, :3]) for c in kids[j]]
        offs = [(x, y) for x, y in offs if np.linalg.norm(x) > 1e-6]
        if len(offs) >= 2:
            X = np.array([x for x, _ in offs]); Y = np.array([y @ Pm for _, y in offs])
            # t[m(c)] . C . P = t[c]  <=>  t[m(c)] . C = t[c] . P
            C[k] = kabsch_rows(X, Y)
        else:
            b = axes[k]
            G2 = G @ swing(b @ G, b @ R0[k])
            C[k] = R0[k] @ G2.T
    return P, C, A


def mirror_anim(char, mode="pose"):
    """-> (anim, facts). mode "pose": every joint takes the REFLECTION of its
    partner's posed world frame, in its own frame convention (see
    mirror_calibration) - the hand goes exactly where the other hand went,
    whatever the two arms' rest poses. mode "delta": every joint takes its
    partner's world-space turn since rest, reflected, applied to its own rest
    (W'[m(j)] = B[m(j)] . M . B[j]^-1 . W[j] . M) - what Meshy's own
    retarget would have made of a mirrored preset; the two differ exactly as
    much as the rest pose is asymmetric (Hephaestus's right arm is bent
    across his chest holding the hammer, his left hangs)."""
    a = char.anim
    pairs = mirror_map(char.joints)
    n, c, asym = sagittal_plane(char, pairs)
    M = reflection(n, c)
    F, J = a["T"].shape[:2]
    T = np.array(a["T"], dtype=np.float64)
    R = np.empty((F, J, 4))
    S = np.array(a["S"], dtype=np.float64)
    if mode == "pose":
        P, C, A = mirror_calibration(char, pairs, n)
    else:
        B, Binv = char.bind, np.linalg.inv(char.bind)
    refl = lambda p: p - 2 * np.dot(p - c, n) * n
    for f in range(F):
        local = np.array([trs(a["T"][f, j], a["R"][f, j], a["S"][f, j]) for j in range(J)])
        W = world_from_local(local, char.parents)
        if mode == "pose":
            Rw = [None] * J
            for j in range(J):
                k = pairs[j]
                Rw[k] = C[k] @ P[k] @ unit_rot(W[j]) @ A
            for k in range(J):
                p = char.parents[k]
                loc = Rw[k] @ Rw[p].T if p >= 0 else Rw[k]
                R[f, k] = character.rot_to_quat(loc)
                if p < 0:
                    T[f, k] = refl(W[k][3, :3]) if pairs[k] == k else refl(W[pairs.index(k)][3, :3])
        else:
            Wm = np.empty_like(W)
            for j in range(J):
                k = pairs[j]
                Wm[k] = B[k] @ M @ Binv[j] @ W[j] @ M
            loc = local_from_world(Wm, char.parents)
            for k in range(J):
                t, q, _ = decompose(loc[k])
                R[f, k] = q
                if char.parents[k] < 0:
                    T[f, k] = t
    # the non-root joints keep their own bone (translation) and scale tracks
    for k in range(J):
        if char.parents[k] >= 0:
            T[:, k] = a["T"][:, k]
            S[:, k] = a["S"][:, k]
    R = continuous(R)
    return {"T": T.astype(np.float32), "R": R.astype(np.float32), "S": S.astype(np.float32), "fps": a["fps"]}, \
        dict(normal=np.round(n, 3).tolist(), point=np.round(c, 3).tolist(), asymmetry_m=round(float(asym), 4))


def check_mirror(char, anim, mode="pose"):
    """What the mode promises. "pose": every joint of the mirrored clip
    against the reflection of its partner in the shipped clip, in metres (the
    bones' own lengths are kept, so a few mm). "delta": the round trip, the
    mirror of the mirror against the shipped clip (a reflection is its own
    inverse). -> the worst joint in metres."""
    pairs = mirror_map(char.joints)
    n, c, _ = sagittal_plane(char, pairs)
    refl = lambda p: p - 2 * np.dot(p - c, n) * n
    if mode == "delta":
        twice = copy.deepcopy(char)
        twice.anim = anim
        anim, _ = mirror_anim(twice, mode)
    worst, who = 0.0, ""
    for f in range(0, len(anim["T"]), max(1, len(anim["T"]) // 8)):
        W = char.joint_world_at(f)
        loc = np.array([trs(anim["T"][f, j], anim["R"][f, j], anim["S"][f, j]) for j in range(len(char.joints))])
        V = world_from_local(loc, char.parents)
        for j, k in enumerate(pairs):
            want = W[j][3, :3] if mode == "delta" else refl(W[j][3, :3])
            got = V[j][3, :3] if mode == "delta" else V[k][3, :3]
            d = np.linalg.norm(want - got)
            if d > worst:
                worst, who = d, leaf(char.joints[k])
    return worst, who


# ---------------------------------------------------------------------------
# 2. Re-arm from the archived preset
# ---------------------------------------------------------------------------

BODY_MATCH = 25.0     # a clip IS the preset when its body joints turn within this of the archive's
ARM_JOINTS = ("LeftArm", "LeftForeArm", "LeftHand", "RightArm", "RightForeArm", "RightHand")


def asset_of(family):
    for cand in (f"{family}_serious", family):
        if (ART / f"{cand}.meshy.json").exists():
            return cand
    return None


def preset_ids(family):
    asset = asset_of(family)
    if asset is None:
        return {}
    m = json.loads((ART / f"{asset}.meshy.json").read_text())
    out = {}
    for k, v in m.get("stages", {}).items():
        if k.startswith("clip:") and v.get("status") == "SUCCEEDED":
            out[k[5:]] = v.get("action_id") or v.get("request", {}).get("action_id")
    return out


def world_turns(motion_like, frames):
    """Per frame, per joint: the world rotation's turn since rest (3x3)."""
    from retarget import rotation_part
    W0 = motion_like.joint_world_at_rest()
    R0 = [rotation_part(m) for m in W0]
    out = []
    for f in frames:
        W = motion_like.joint_world_at(f)
        out.append([R0[j].T @ rotation_part(W[j]) for j in range(len(W))])
    return out


def angle(A, B):
    r = A @ B.T
    return float(np.degrees(np.arccos(np.clip((np.trace(r) - 1) / 2, -1, 1))))


def arm_error(char, source, frames=None):
    """-> (worst arm-chain degrees, worst body degrees): the carrier's world
    turn from rest against the archived preset's, joint by joint."""
    frames = frames or sorted({0, len(char.anim["T"]) // 2, len(char.anim["T"]) - 1})
    sn = {leaf(j): i for i, j in enumerate(source.joints)}
    cn = [leaf(j) for j in char.joints]
    a = world_turns(source, frames)
    b = world_turns(char, frames)
    arm = body = 0.0
    for fi in range(len(frames)):
        for ci, name in enumerate(cn):
            si = sn.get(name)
            if si is None:
                continue
            d = angle(a[fi][si], b[fi][ci])
            if name in ARM_JOINTS:
                arm = max(arm, d)
            elif name in ("Spine02", "neck", "Head", "LeftUpLeg", "RightUpLeg", "LeftLeg", "RightLeg"):
                body = max(body, d)
    return arm, body


def rearm_anim(char, source):
    from retarget import Motion, retarget
    tgt = Motion.from_char(char)
    anim, missing, facts = retarget(source, tgt)
    if len(anim["T"]) != len(char.anim["T"]):
        raise SystemExit(f"frame counts differ: preset {len(anim['T'])}, shipped {len(char.anim['T'])}")
    out = {k: np.array(char.anim[k], dtype=np.float64) for k in ("T", "R", "S")}
    out["fps"] = char.anim["fps"]
    for j, name in enumerate(char.joints):
        if leaf(name) in ARM_JOINTS:
            out["R"][:, j] = anim["R"][:, j]
    out["R"] = continuous(out["R"])
    return {k: (v.astype(np.float32) if k != "fps" else v) for k, v in out.items()}


def survey_arms(bundle, names=None):
    from retarget import Motion
    rows = []
    names = names or sorted(p.name[: -len("_idle_combat.usdz")] for p in bundle.glob("*_idle_combat.usdz"))
    src = Motion.load(MOTIONS / "preset_89.motion.npz")
    for fam in names:
        pid = preset_ids(fam).get("idle_combat")
        if str(pid) != "89":
            continue
        c = read(bundle / f"{fam}_idle_combat.usdz")
        if len(c.anim["T"]) != len(src.anim["T"]):
            continue
        arm, body = arm_error(c, src, frames=[0, 25])
        rows.append((arm, body, fam))
    rows.sort(reverse=True)
    print("family                   arms off the preset (deg)   body (deg)")
    for arm, body, fam in rows:
        flag = "  <- re-arm" if arm > 40 else ""
        print(f"  {fam:24s} {arm:6.1f}                     {body:5.1f}{flag}")
    return rows


# ---------------------------------------------------------------------------
# 3. Neck damping
# ---------------------------------------------------------------------------

def damp_neck(char, keep=0.4, joints=("neck", "Head")):
    from stand_idle import slerp
    a = char.anim
    out = {k: np.array(a[k], dtype=np.float64) for k in ("T", "R", "S")}
    out["fps"] = a["fps"]
    F = len(a["T"])
    for j, name in enumerate(char.joints):
        if leaf(name) in joints:
            rest_q = decompose(char.rest_local[j])[1]
            out["R"][:, j] = slerp(np.repeat(rest_q[None], F, 0), out["R"][:, j], keep)
    return {k: (v.astype(np.float32) if k != "fps" else v) for k, v in out.items()}


# ---------------------------------------------------------------------------
# 1b. The bow wrist
# ---------------------------------------------------------------------------

def held_axis(base, hand):
    """(axis in the hand's local frame, vertex count, extent): the long axis
    of what the hand joint owns (its dominant weight) - a bow's limbs."""
    dom = base.joint_indices[np.arange(len(base.points)), base.joint_weights.argmax(1)]
    j = [leaf(x) for x in base.joints].index(hand)
    P = base.points[dom == j].astype(np.float64)
    if len(P) < 50:
        return None, len(P), 0.0
    X = P - P.mean(0)
    _, sv, vt = np.linalg.svd(X, full_matrices=False)
    u = vt[0]
    # into the hand's frame at bind (row form: world = local . R)
    u_local = u @ unit_rot(base.bind[j]).T
    return u_local / np.linalg.norm(u_local), len(P), float(np.ptp(X @ u))


def bow_hand(base):
    best = None
    for hand in ("LeftHand", "RightHand"):
        ax, count, ext = held_axis(base, hand)
        if ax is not None and (best is None or ext > best[2]):
            best = (hand, ax, ext)
    return best


def bow_wrist(char, base, blow, hand=None):
    """A constant bend of the bow hand's wrist, found at the blow frame: the
    rotation that stands the bow's long axis upright there (the concept's
    grip, per the rigger's rule, holds the bow along the forearm, so an arm
    raised to aim lays it flat), applied to the hand's local track at every
    frame - the grip changes once, the motion is the clip's."""
    if hand is None:
        hand, ax, ext = bow_hand(base)
    else:
        ax, _, ext = held_axis(base, hand)
    names = [leaf(j) for j in char.joints]
    h = names.index(hand)
    a = char.anim
    W = char.joint_world_at(blow)
    Rw = unit_rot(W[h])
    u = ax @ Rw
    up = np.array([0.0, 1.0 if u[1] >= 0 else -1.0, 0.0])
    Q = swing(u, up)
    K = Rw @ Q @ Rw.T
    tilt = angle(Q, np.eye(3))
    out = {k: np.array(a[k], dtype=np.float64) for k in ("T", "R", "S")}
    out["fps"] = a["fps"]
    for f in range(len(a["T"])):
        L = unit_rot(trs(a["T"][f, h], a["R"][f, h], [1, 1, 1]))
        out["R"][f, h] = character.rot_to_quat(K @ L)
    out["R"] = continuous(out["R"])
    return {k: (v.astype(np.float32) if k != "fps" else v) for k, v in out.items()}, hand, tilt, ext


# ---------------------------------------------------------------------------
# Stretch: the mesh's edges under a clip (tools/weapon_pass.py's measure)
# ---------------------------------------------------------------------------

def clip_stretch(base_path, clip_path, samples=24):
    """-> dict: the worst posed/rest edge ratio of the base mesh over
    `samples` frames of the clip, and how many edges pass 2x and 3x (a
    clean family's fingers read 1.2-1.5; a tear 4-80)."""
    import weapon_pass
    base = read(base_path)
    clip = read(clip_path)
    cmap = {leaf(j): i for i, j in enumerate(clip.joints)}
    inv_bind = np.linalg.inv(base.bind)
    a = clip.anim
    n = len(a["T"])
    mats = []
    for f in np.unique(np.linspace(0, n - 1, samples).round().astype(int)):
        local = np.array(base.rest_local, dtype=np.float64)
        for bi, bj in enumerate(base.joints):
            ci = cmap.get(leaf(bj))
            if ci is not None:
                local[bi] = trs(a["T"][f, ci], a["R"][f, ci], a["S"][f, ci])
        world = world_from_local(local, base.parents)
        mats.append(("", int(f), np.einsum("jab,jbc->jac", inv_bind, world)))
    edges = weapon_pass.unique_edges(base.faces)
    h = float(np.ptp(base.points[:, 1]))
    worst, at = weapon_pass.worst_stretch(base.points.astype(np.float64), base.joint_indices, base.joint_weights, mats, edges, h)
    return dict(max=round(float(worst.max()), 1), over2=int((worst > 2).sum()), over3=int((worst > 3).sum()),
                frame=int(mats[int(at[worst.argmax()])][1]))


def stretch_map(base_path, clip_path, frame, size=420):
    """A heat map of the posed mesh at one frame, front and side, every
    vertex coloured by the worst stretch of its edges (grey under 1.5x,
    yellow 2x, red 3x and over)."""
    from PIL import Image, ImageDraw
    import weapon_pass
    base = read(base_path)
    clip = read(clip_path)
    cmap = {leaf(j): i for i, j in enumerate(clip.joints)}
    a = clip.anim
    local = np.array(base.rest_local, dtype=np.float64)
    for bi, bj in enumerate(base.joints):
        ci = cmap.get(leaf(bj))
        if ci is not None:
            local[bi] = trs(a["T"][frame, ci], a["R"][frame, ci], a["S"][frame, ci])
    Q = base.skinned_points(world_from_local(local, base.parents))
    P = base.points.astype(np.float64)
    e = weapon_pass.unique_edges(base.faces)
    L0 = np.maximum(np.linalg.norm(P[e[:, 0]] - P[e[:, 1]], axis=1), 1e-6)
    r = np.linalg.norm(Q[e[:, 0]] - Q[e[:, 1]], axis=1) / L0
    r[L0 < 1e-3 * np.ptp(P[:, 1])] = 1.0
    v = np.ones(len(P))
    np.maximum.at(v, e[:, 0], r); np.maximum.at(v, e[:, 1], r)
    img = Image.new("RGB", (size * 2, size), (240, 240, 244))
    d = ImageDraw.Draw(img)
    lo, hi = Q.min(0), Q.max(0)
    span = max(hi - lo) * 1.05
    order = np.argsort(v)
    for col, (ax, depth) in enumerate(((0, 2), (2, 0))):
        for i in order:
            x = (Q[i, ax] - (lo[ax] + hi[ax]) / 2) / span * size + size / 2 + col * size
            if col == 1:
                x = size - ((Q[i, ax] - (lo[ax] + hi[ax]) / 2) / span * size + size / 2) + size
            y = size - ((Q[i, 1] - lo[1]) / span * size + size * 0.025)
            t = v[i]
            c = (150, 150, 158) if t < 1.5 else ((235, 200, 40) if t < 3 else (220, 30, 30))
            rr = 1 if t < 1.5 else 2
            d.ellipse((x - rr, y - rr, x + rr, y + rr), fill=c)
    d.text((6, 6), f"stretch f{frame}: {int((v > 2).sum())} verts >2x, {int((v > 3).sum())} >3x, max {v.max():.1f}", fill=(20, 20, 20))
    return img


def lift_snout(char, limit=60.0, share_neck=0.4):
    """A long head kept out of its own chest: at every frame the snout
    (Head -> headfront) is measured against the torso's line (neck -> hips),
    and where it comes within `limit` degrees of it the head is turned away,
    about the axis across the two, `share_neck` of the turn at the neck and
    the rest at the head. A human's short face can look down its own front
    on a follow-through (the presets do: Hephaestus reaches 32 degrees on
    the Charged Ground Slam); a crocodile's half-metre jaw at 25 degrees is
    inside its ribs. The figure's lean and every other joint are kept. (A
    limit on the pitch below the horizon was tried first: on a body bent
    double and twisted by the swing there is no stable horizon ahead, and
    it turned the jaw sideways.)"""
    names = [leaf(j) for j in char.joints]
    h, nk = names.index("Head"), names.index("neck")
    if "headfront" not in names:
        raise SystemExit("no headfront joint to read the snout off")
    tip = names.index("headfront")
    hips = names.index("Hips")
    a = char.anim
    out = {k: np.array(a[k], dtype=np.float64) for k in ("T", "R", "S")}
    out["fps"] = a["fps"]
    closest_before, closest_after = 180.0, 180.0

    def turn(axis, t):
        K = np.array([[0, -axis[2], axis[1]], [axis[2], 0, -axis[0]], [-axis[1], axis[0], 0]])
        return (np.eye(3) + np.sin(t) * K + (1 - np.cos(t)) * K @ K).T

    for f in range(len(a["T"])):
        local = np.array([trs(a["T"][f, j], a["R"][f, j], a["S"][f, j]) for j in range(len(char.joints))])
        W = world_from_local(local, char.parents)
        s = W[tip][3, :3] - W[h][3, :3]
        D = W[hips][3, :3] - W[nk][3, :3]
        s, D = s / np.linalg.norm(s), D / np.linalg.norm(D)
        gap = float(np.degrees(np.arccos(np.clip(np.dot(s, D), -1, 1))))
        closest_before = min(closest_before, gap)
        if gap >= limit:
            closest_after = min(closest_after, gap)
            continue
        axis = np.cross(D, s)
        if np.linalg.norm(axis) < 1e-6:
            continue
        axis /= np.linalg.norm(axis)
        want = np.radians(limit - gap)
        # row form: v . turn(axis, t) turns v by t about axis, D -> s is positive
        Rn = unit_rot(W[nk]) @ turn(axis, want * share_neck)
        Rp = unit_rot(W[char.parents[nk]])
        out["R"][f, nk] = character.rot_to_quat(Rn @ Rp.T)
        Rh = unit_rot(W[h]) @ turn(axis, want)
        out["R"][f, h] = character.rot_to_quat(Rh @ Rn.T)
        closest_after = min(closest_after, limit)
    out["R"] = continuous(out["R"])
    return {k: (v.astype(np.float32) if k != "fps" else v) for k, v in out.items()}, closest_before, closest_after


# ---------------------------------------------------------------------------
# Boards
# ---------------------------------------------------------------------------

def board(base_before, before_clip, base_after, after_clip, frames, out_jpg, label=""):
    from PIL import Image, ImageDraw
    from base_plus_clip import base_plus_clip
    rows = []
    for tag, base_path, clip in (("BEFORE", base_before, before_clip), ("AFTER", base_after, after_clip)):
        with contextlib.redirect_stdout(io.StringIO()):
            r = base_plus_clip(str(base_path), str(clip), frames=tuple(frames))
        for i, row in enumerate(r):
            d = ImageDraw.Draw(row)
            d.rectangle((0, 0, 360, 22), fill=(20, 20, 24))
            d.text((6, 5), f"{tag} {label} f{frames[i]}", fill=(255, 220, 120) if tag == "AFTER" else (200, 200, 210))
        rows.append(r)
    w = max(x.width for x in rows[0]); h = max(x.height for x in rows[0])
    # columns: before | after, a row per frame, each cell shrunk to half
    scale = 0.5
    cw, ch = int(w * scale), int(h * scale)
    sheet = Image.new("RGB", (cw * 2, ch * len(frames)), (30, 30, 34))
    for col, r in enumerate(rows):
        for i, row in enumerate(r):
            sheet.paste(row.resize((cw, ch)), (col * cw, i * ch))
    Path(out_jpg).parent.mkdir(parents=True, exist_ok=True)
    sheet.save(out_jpg, quality=85)
    print(f"    board -> {out_jpg}")


# ---------------------------------------------------------------------------
# Driver
# ---------------------------------------------------------------------------

def target_dir(args):
    if args.in_place:
        return BUNDLE
    if not args.out:
        raise SystemExit("--out DIR (or --in-place, the owner's call)")
    out = Path(args.out).resolve()
    if out == BUNDLE.resolve():
        raise SystemExit("that is the app's bundle; pass --in-place to write it")
    out.mkdir(parents=True, exist_ok=True)
    return out


def all_clips(bundle, family):
    skip = {"lod", "idle"}
    out = []
    for p in sorted(bundle.glob(f"{family}_*.usdz")):
        rest = p.stem[len(family) + 1:]
        if rest in skip or rest.startswith("lod") or not rest.replace("_", "").isalpha():
            continue
        # a different family sharing the prefix (e.g. ra / ra_awakened) is not a clip
        if rest.split("_")[0] in ("awakened", "serious"):
            continue
        out.append(rest)
    return out


def blow_frame(family, clip, frames):
    """The frame an archer's shot looses: the preset's own (motion_palette's
    PRESET_CUTS, read off each preset's board), else the middle."""
    try:
        from motion_palette import PRESET_CUTS
        b = PRESET_CUTS.get(int(preset_ids(family).get(clip) or -1), {}).get("blow")
    except Exception:            # noqa: BLE001 - the palette is optional
        b = None
    return b if b is not None and b < frames else frames // 2


def do_mirror(family, clips, bundle, out, mode="pose", wrist=False):
    # the bow's axis is read off the base as it will ship (after the skirt pass, when one ran into out)
    base_path = out / f"{family}.usdz" if (out / f"{family}.usdz").exists() else bundle / f"{family}.usdz"
    base = read(base_path) if wrist else None
    for clip in clips:
        src = bundle / f"{family}_{clip}.usdz"
        c = read(src)
        anim, facts = mirror_anim(c, mode)
        worst, who = check_mirror(c, anim, mode)
        print(f"  {family}_{clip}: mirrored ({mode}) across n={facts['normal']} through {facts['point']}; "
              f"rest asymmetry (worst pair) {facts['asymmetry_m']} m; "
              f"{'joints off the reflected pose' if mode == 'pose' else 'round trip'} {worst * 1000:.0f} mm ({who})")
        c.anim = anim
        if wrist:
            blow = blow_frame(family, clip, len(anim["T"]))
            c.anim, hand, tilt, ext = bow_wrist(c, base, blow)
            print(f"    bow wrist: {hand} bent {tilt:.0f} deg so the {ext:.2f} m bow stands upright at f{blow}")
        c.name = family
        write_carrier(c, out / src.name)


def do_rearm(family, clips, bundle, out, idle=True):
    from retarget import Motion
    ids = preset_ids(family)
    clips = clips or [c for c in all_clips(bundle, family) if c in ids]
    for clip in clips:
        pid = ids.get(clip)
        arch = MOTIONS / f"preset_{pid}.motion.npz"
        if pid is None or not arch.exists():
            print(f"  {family}_{clip}: no archived preset ({pid}); left as shipped")
            continue
        src = Motion.load(arch)
        c = read(bundle / f"{family}_{clip}.usdz")
        if len(c.anim["T"]) != len(src.anim["T"]):
            print(f"  {family}_{clip}: {len(c.anim['T'])} frames, preset {pid} has {len(src.anim['T'])} - "
                  f"not that preset (a bespoke or palette clip); left as shipped")
            continue
        before = arm_error(c, src)
        if before[1] > BODY_MATCH:
            print(f"  {family}_{clip}: the body is {before[1]:.0f} deg off preset {pid} - not that preset; left as shipped")
            continue
        c.anim = rearm_anim(c, src)
        after = arm_error(c, src)
        print(f"  {family}_{clip} <- preset {pid}: arms off the preset {before[0]:.0f} -> {after[0]:.0f} deg "
              f"(body {before[1]:.0f} -> {after[1]:.0f})")
        c.name = family
        write_carrier(c, out / f"{family}_{clip}.usdz")
    if idle and (out / f"{family}_idle_combat.usdz").exists() and (bundle / f"{family}_idle.usdz").exists():
        from stand_idle import stand
        c = read(out / f"{family}_idle_combat.usdz")
        stand(c, 1.0)
        c.name = family
        print(f"  {family}_idle: the standing idle re-derived from the fixed combat idle")
        write_carrier(c, out / f"{family}_idle.usdz")


def do_neck(family, clips, bundle, out, keep):
    for clip in clips:
        src = bundle / f"{family}_{clip}.usdz"
        c = read(src)
        c.anim = damp_neck(c, keep)
        c.name = family
        print(f"  {family}_{clip}: neck and head keep {keep:.0%} of their turn")
        write_carrier(c, out / src.name)


def do_snout(family, clips, bundle, out, limit):
    for clip in clips:
        src = bundle / f"{family}_{clip}.usdz"
        c = read(src)
        c.anim, before, after = lift_snout(c, limit)
        c.name = family
        print(f"  {family}_{clip}: the snout's closest to the torso line {before:.0f} -> {after:.0f} deg")
        write_carrier(c, out / src.name)


def self_test(bundle):
    """Controls that must move nothing (or exactly undo themselves)."""
    from retarget import Motion
    ok = True
    c = read(bundle / "diana_attack_basic.usdz")
    anim, _ = mirror_anim(c, "delta")
    back, _ = check_mirror(c, anim, "delta")
    print(f"  delta mirror, twice, on diana's basic: worst joint {back * 1000:.2f} mm (want < 1)"); ok &= back < 1e-3
    anim, _ = mirror_anim(c, "pose")
    off, who = check_mirror(c, anim, "pose")
    print(f"  pose mirror on diana's basic (a symmetric rest): off the reflection {off * 1000:.0f} mm at {who} (want < 40)"); ok &= off < 0.04
    # a clip that IS its Meshy preset: the walk (preset 30; the motion palette,
    # 2026-09-24, re-dealt the combat idle this control used to be, cut and
    # looped, so its frames no longer match the preset's)
    c = read(bundle / "anubis_walk.usdz")
    src = Motion.load(MOTIONS / "preset_30.motion.npz")
    before = arm_error(c, src)[0]
    new = rearm_anim(c, src)
    worst = max(angle(unit_rot(trs([0, 0, 0], c.anim["R"][f, j], [1, 1, 1])), unit_rot(trs([0, 0, 0], new["R"][f, j], [1, 1, 1])))
                for f in (0, 25, 50) for j, n in enumerate(c.joints) if leaf(n) in ARM_JOINTS)
    print(f"  re-arm on anubis's walk (arms {before:.1f} deg off the preset): tracks move {worst:.1f} deg (want < 6)"); ok &= worst < 6
    c = read(bundle / "hephaestus_idle_combat.usdz")
    _, b, a2 = lift_snout(c, 75.0) if "headfront" in [leaf(j) for j in c.joints] else (None, 180, 180)
    print(f"  snout lift on hephaestus's combat idle: closest {b:.0f} -> {a2:.0f} deg (want unchanged)"); ok &= abs(b - a2) < 1e-6
    print("  self-test", "PASSED" if ok else "FAILED")
    return ok


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--mirror", nargs=2, metavar=("FAMILY", "CLIPS"))
    ap.add_argument("--rearm", nargs="+", metavar="FAMILY [CLIPS]")
    ap.add_argument("--damp-neck", nargs=2, metavar=("FAMILY", "CLIPS"))
    ap.add_argument("--keep", type=float, default=0.4)
    ap.add_argument("--lift-snout", nargs=2, metavar=("FAMILY", "CLIPS"))
    ap.add_argument("--limit", type=float, default=60.0, help="--lift-snout: the least angle between the snout and the torso's line")
    ap.add_argument("--bow-wrist", action="store_true", help="--mirror: then bend the bow hand's wrist so the bow stands upright at the loose")
    ap.add_argument("--mode", choices=("pose", "delta"), default="pose", help="--mirror: reflect the pose (default) or the turn since rest")
    ap.add_argument("--drop-piece", metavar="FAMILY")
    ap.add_argument("--pieces", metavar="FAMILY", help="list the mesh's connected pieces, largest first")
    ap.add_argument("--bind-piece", nargs=3, metavar=("FAMILY", "RANK", "JOINT"), help="bind piece RANK (from --pieces) rigidly to JOINT, base and LOD, into --out")
    ap.add_argument("--skirt", metavar="FAMILY", help="the skirt pass (character.reweight_skirt) on the base and LOD, into --out")
    ap.add_argument("--survey-arms", nargs="*")
    ap.add_argument("--board", nargs=2, metavar=("FAMILY", "CLIP"))
    ap.add_argument("--frames", default=None)
    ap.add_argument("--after", default=None, help="the folder the fixed files are in (for --board; default --out)")
    ap.add_argument("--apply-all", action="store_true")
    ap.add_argument("--self-test", action="store_true")
    ap.add_argument("--bundle", default=str(BUNDLE))
    ap.add_argument("--out")
    ap.add_argument("--in-place", action="store_true")
    ap.add_argument("--no-idle", action="store_true")
    args = ap.parse_args()
    bundle = Path(args.bundle)

    if args.self_test:
        sys.exit(0 if self_test(bundle) else 1)
    if args.survey_arms is not None:
        survey_arms(bundle, args.survey_arms or None)
        return
    if args.board:
        fam, clip = args.board
        after = Path(args.after or args.out)
        frames = [int(x) for x in (args.frames or "0").split(",")]
        pick = lambda name: after / name if (after / name).exists() else bundle / name
        board(bundle / f"{fam}.usdz", bundle / f"{fam}_{clip}.usdz", pick(f"{fam}.usdz"), pick(f"{fam}_{clip}.usdz"),
              frames, after / "boards" / f"{fam}_{clip}.jpg", label=f"{fam} {clip}")
        return
    if args.pieces:
        list_pieces(args.pieces, bundle)
        return
    out = target_dir(args)
    if args.bind_piece:
        fam, rank, joint = args.bind_piece
        do_bind_piece(fam, int(rank), joint, bundle, out)
    if args.mirror:
        fam, clips = args.mirror
        do_mirror(fam, clips.split(","), bundle, out, args.mode, args.bow_wrist)
    if args.rearm:
        fam = args.rearm[0]
        clips = args.rearm[1].split(",") if len(args.rearm) > 1 else None
        do_rearm(fam, clips, bundle, out, idle=not args.no_idle)
    if args.damp_neck:
        fam, clips = args.damp_neck
        do_neck(fam, clips.split(","), bundle, out, args.keep)
    if args.lift_snout:
        fam, clips = args.lift_snout
        do_snout(fam, clips.split(","), bundle, out, args.limit)
    if args.skirt:
        do_skirt(args.skirt, bundle, out)
    if args.drop_piece:
        do_drop_piece(args.drop_piece, bundle, out)
    if args.apply_all:
        # A mirror is its own inverse, so a second run over a bundle that already
        # carries it would put the empty hand back: an in-place run leaves
        # Art/Models/<family>.clipfix.json naming the steps it applied, and every
        # run skips a step named there (and says so).
        for fam, steps in FIXES.items():
            marker = ART / f"{fam}.clipfix.json"
            done = json.loads(marker.read_text()) if marker.exists() else []
            for mode, clips, opts in steps:
                key = f"{mode}:{','.join(clips or [])}"
                if key in done:
                    print(f"== {fam}: {mode} {clips or ''} - already applied ({marker.name}); skipped")
                    continue
                print(f"== {fam}: {mode} {clips or ''}")
                if mode == "mirror":
                    do_mirror(fam, clips, bundle, out, opts.get("mode", "pose"), opts.get("bow_wrist", False))
                elif mode == "rearm":
                    do_rearm(fam, clips, bundle, out)
                elif mode == "neck":
                    do_neck(fam, clips, bundle, out, opts.get("keep", 0.4))
                elif mode == "snout":
                    do_snout(fam, clips, bundle, out, opts.get("limit", 60.0))
                elif mode == "skirt":
                    do_skirt(fam, bundle, out)
                elif mode == "bind":
                    do_bind_piece(fam, opts["rank"], opts["joint"], bundle, out, expect=opts.get("size"))
                if args.in_place:
                    done.append(key)
                    marker.write_text(json.dumps(done, indent=1) + "\n")


def do_skirt(family, bundle, out):
    """tools/skirt_pass.py's apply() into --out: the arm's cloth given back to
    the body in the base (character.reweight_skirt), the LOD taking the
    base's verdict (skirt_pass.transfer). A mirrored clip moves the OTHER arm
    through the garment, and a panel the rigger welded to that hand, still
    in the base, is pulled into a sheet (Skadi's coat, Hephaestus's tunic)."""
    import skirt_pass
    base = read(bundle / f"{family}.usdz")
    ji0, jw0 = base.joint_indices.copy(), base.joint_weights.copy()
    n0 = len(base.points)
    n = character.reweight_skirt(base)
    if not n:
        print(f"  {family}: the skirt pass moves nothing")
        return 0
    moved = ((base.joint_indices[:n0] != ji0).any(axis=1) | (np.abs(base.joint_weights[:n0] - jw0) > 1e-6).any(axis=1))
    height = float(np.ptp(base.points[:, 1]))
    base.name = family
    write_carrier(base, out / f"{family}.usdz")
    lod_path = bundle / f"{family}_lod.usdz"
    if lod_path.exists():
        lod = read(lod_path)
        m = skirt_pass.transfer(base, moved, lod, height)
        print(f"  {family}_lod: {m:,} vertices took the base's verdict")
        write_carrier(lod, out / lod_path.name)
    return n


def pieces(char):
    """The mesh's connected pieces (welded by position: Meshy splits the
    surface at UV seams), largest first: [(vertex indices, size)]."""
    from scipy.sparse import coo_matrix
    from scipy.sparse.csgraph import connected_components
    P = char.points.astype(np.float64)
    _, canon = np.unique(np.round(P, 5), axis=0, return_inverse=True)
    canon = canon.ravel()
    F = canon[char.faces]
    e = np.vstack([F[:, [0, 1]], F[:, [1, 2]], F[:, [2, 0]]])
    m = int(canon.max()) + 1
    _, lab = connected_components(coo_matrix((np.ones(len(e)), (e[:, 0], e[:, 1])), shape=(m, m)), directed=False)
    lab = lab[canon]
    sizes = np.bincount(lab)
    order = np.argsort(-sizes)
    return [np.flatnonzero(lab == k) for k in order]


def list_pieces(family, bundle):
    import weapon_pass
    base = read(bundle / f"{family}.usdz")
    names = [leaf(j) for j in base.joints]
    W = weapon_pass.dense_weights(base)
    for i, idx in enumerate(pieces(base)):
        if len(idx) < 20:
            break
        share = W[idx].sum(0) / len(idx)
        top = np.argsort(-share)[:4]
        ext = np.ptp(base.points[idx], 0)
        print(f"  piece {i}: {len(idx):,} vertices, {np.round(ext, 2)} m, centre {np.round(base.points[idx].mean(0), 2)}; "
              + ", ".join(f"{names[t]} {share[t]:.2f}" for t in top))


def bind_piece(char, idx, joint):
    """Every vertex of one piece to ONE joint at 1.0 - rigid, the weapon
    pass's rule for a held thing, here for a thing the concept SLUNG on the
    body (Diana's bow across her front: 34% shoulder, 28% thigh, 12% upper
    arm, so every step and every raised arm smeared it)."""
    j = [leaf(x) for x in char.joints].index(joint)
    char.joint_indices[idx] = 0
    char.joint_weights[idx] = 0
    char.joint_indices[idx, 0] = j
    char.joint_weights[idx, 0] = 1.0


def do_bind_piece(family, rank, joint, bundle, out, expect=None):
    import skirt_pass
    base = read(bundle / f"{family}.usdz")
    idx = pieces(base)[rank]
    if expect is not None and len(idx) != expect:
        raise SystemExit(f"{family}: piece {rank} has {len(idx)} vertices, the judged one had {expect} - "
                         f"the base changed since; list it again with --pieces and judge it on a board")
    h = float(np.ptp(base.points[:, 1]))
    moved = np.zeros(len(base.points), bool)
    moved[idx] = True
    bind_piece(base, idx, joint)
    base.name = family
    print(f"  {family}: piece {rank} ({len(idx):,} vertices) bound to {joint}")
    write_carrier(base, out / f"{family}.usdz")
    lod_path = bundle / f"{family}_lod.usdz"
    if lod_path.exists():
        lod = read(lod_path)
        m = skirt_pass.transfer(base, moved, lod, h)
        print(f"  {family}_lod: {m:,} vertices took the base's verdict")
        write_carrier(lod, out / lod_path.name)


def do_drop_piece(family, bundle, out):
    raise SystemExit("--drop-piece: not built - Apollo's third arm is welded into the torso and the skirt "
                     "(one connected piece with the body; no gap between them from 0.95 to 1.15 m), so "
                     "deleting it leaves a hole; it is in the concept, and a remake needs the repaint "
                     "(see the report)")


if __name__ == "__main__":
    main()
