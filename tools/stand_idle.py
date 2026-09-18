"""A standing idle for every family, derived from its combat idle.

No family ships a plain `idle` (2026-09-18: 0 of 116), so every stage that
shows a figure at rest — the summon reveal, the Hall of Ka's altar, the
collection's Stage, the island — played Meshy's *combat idle* preset, a
crouched guard stance with the knees bent and the spine folded forward. On a
wide armoured figure (the Ares family) it photographs as a hunch seen from
behind, which the owner sent back twice. The battle wants the crouch; a
stage does not.

This derives `<name>_idle.usdz` from `<name>_idle_combat.usdz`: every joint's
animated rotation is blended toward its REST rotation — the spine chain and
the hips most (a third of the crouch kept), the legs a little less, the arms
least (the guard's arms stay) — the hips' dip toward the floor is halved, and
each frame is re-grounded on the FOOT JOINTS so the feet stay where the
combat idle's were (the carrier's 1,500-triangle mesh is no reference for a
floor). The breathing and the sway survive because they are the clip's own
deviations, scaled; a family whose combat idle already stood upright (the
meshy-7 gods) changes by almost nothing.

    python3 tools/stand_idle.py                 # every family in the bundle
    python3 tools/stand_idle.py ares_awakened   # one
    python3 tools/stand_idle.py --keep 0.5      # keep more of the crouch
"""
import argparse
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
import character  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]
BUNDLE = ROOT / "Pantheon" / "Resources" / "Models"

# How much of the combat idle's deviation from the rest pose each joint keeps.
KEEP = {
    "spine": 0.35,    # Hips (rotation), Spine, Spine1, Spine2, Neck, Head
    "legs": 0.45,     # UpLeg, Leg, Foot, ToeBase
    "arms": 0.85,     # Shoulder, Arm, ForeArm, Hand, fingers
    "hips_dip": 0.5,  # the hips' vertical drop below rest, before re-grounding
}
FEET = ("LeftFoot", "RightFoot", "LeftToeBase", "RightToeBase", "LeftToe_End", "RightToe_End")


def group(leaf):
    n = leaf.lower()
    if any(k in n for k in ("hips", "spine", "neck", "head")):
        return "spine"
    if any(k in n for k in ("upleg", "leg", "foot", "toe")):
        return "legs"
    return "arms"


def slerp(q0, q1, t):
    """Quaternions xyzw, arrays (...,4). t is the share of q1."""
    q0 = q0 / np.linalg.norm(q0, axis=-1, keepdims=True)
    q1 = q1 / np.linalg.norm(q1, axis=-1, keepdims=True)
    dot = np.sum(q0 * q1, axis=-1, keepdims=True)
    q1 = np.where(dot < 0, -q1, q1)
    dot = np.abs(dot)
    theta = np.arccos(np.clip(dot, -1.0, 1.0))
    sin = np.sin(theta)
    near = sin < 1e-6
    w0 = np.where(near, 1 - t, np.sin((1 - t) * theta) / np.where(near, 1, sin))
    w1 = np.where(near, t, np.sin(t * theta) / np.where(near, 1, sin))
    out = w0 * q0 + w1 * q1
    return out / np.linalg.norm(out, axis=-1, keepdims=True)


def lowest_foot(char, local):
    world = character.world_from_local(local, char.parents)
    ys = [world[j][3, 1] for j, name in enumerate(char.joints) if name.split("/")[-1] in FEET]
    return min(ys) if ys else world[0][3, 1]


def stand(char, keep_scale=1.0):
    a = char.anim
    frames, joints = a["T"].shape[0], len(char.joints)
    rest_t = np.array([character.decompose(char.rest_local[j])[0] for j in range(joints)])
    rest_q = np.array([character.decompose(char.rest_local[j])[1] for j in range(joints)])
    T = a["T"].astype(np.float64).copy()
    R = a["R"].astype(np.float64).copy()
    S = a["S"].astype(np.float64).copy()
    hips = next((j for j, n in enumerate(char.joints) if n.split("/")[-1].lower() == "hips"), 0)
    hips_before = float(np.mean(T[:, hips, 1]))
    for j, name in enumerate(char.joints):
        leaf = name.split("/")[-1]
        keep = min(1.0, KEEP[group(leaf)] * keep_scale)
        R[:, j] = slerp(np.repeat(rest_q[j][None], frames, 0), R[:, j], keep)
        if j == hips:
            # The dip below rest is halved; the sway (x, z) kept.
            dip = np.minimum(T[:, j, 1] - rest_t[j][1], 0.0)
            T[:, j, 1] = T[:, j, 1] - dip * (1 - min(1.0, KEEP["hips_dip"] * keep_scale))
        else:
            T[:, j] = rest_t[j]     # a limb's length is the rest's; the clip's are the same to rounding
    # Re-ground: the feet stay where the combat idle's were, frame by frame.
    for f in range(frames):
        original = np.array([character.trs(a["T"][f, j], a["R"][f, j], a["S"][f, j]) for j in range(joints)])
        blended = np.array([character.trs(T[f, j], R[f, j], S[f, j]) for j in range(joints)])
        T[f, hips, 1] += lowest_foot(char, original) - lowest_foot(char, blended)
    char.anim = {"T": T.astype(np.float32), "R": R.astype(np.float32), "S": S.astype(np.float32), "fps": a["fps"]}
    return hips_before, float(np.mean(T[:, hips, 1])), float(rest_t[hips][1])


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("names", nargs="*", help="asset names; default every family with a combat idle in the bundle")
    ap.add_argument("--keep", type=float, default=1.0, help="scale on every KEEP share (0.5 stands straighter)")
    args = ap.parse_args()
    names = args.names or sorted(p.name[: -len("_idle_combat.usdz")] for p in BUNDLE.glob("*_idle_combat.usdz"))
    made, failed = 0, []
    for name in names:
        src = BUNDLE / f"{name}_idle_combat.usdz"
        out = BUNDLE / f"{name}_idle.usdz"
        if not src.exists():
            print(f"{name}: no combat idle"); failed.append(name); continue
        try:
            char = character.read_usdz(src)
            if not char.anim or not char.skinned:
                print(f"{name}: no animation in the carrier"); failed.append(name); continue
            before, after, rest = stand(char, args.keep)
            char.name = name
            size = character.write_usdz(char, out)
            facts = character.verify(out, check_bounds=False, quiet=True)
            probs = [p for p in facts["problems"] if not p.startswith("feet at")]
            print(f"{name}: hips {before:.3f} -> {after:.3f} m (rest {rest:.3f}), {len(char.anim['T'])} frames, "
                  f"{size / 1024:.0f} KB{'  PROBLEMS: ' + '; '.join(probs) if probs else ''}")
            if probs:
                failed.append(name)
            else:
                made += 1
        except Exception as e:  # noqa: BLE001 - one bad family must not stop the batch
            print(f"{name}: FAILED {e}"); failed.append(name)
    print(f"\n{made} standing idles written, {len(failed)} failed{': ' + ', '.join(failed) if failed else ''}")


if __name__ == "__main__":
    main()
