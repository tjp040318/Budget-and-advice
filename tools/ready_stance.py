#!/usr/bin/env python3
"""The battle's ready stances (Docs/PLAN.md, *Natural poses*, build step 4;
2026-09-25).

73 families still stood in battle in Meshy's 89 Combat Idle - raw (26), stood
70% up (`half`, 37) or stood fully up (`stand`, the ten step 2 left: Surtr, Sun
Wukong, Diana, Nike, Set, Dionysus, Sobek, the Centurion, the Hoplite, the
Terracotta Soldier). Every one held the same guard and panted the same 1.27 s
loop, its arms dragged the cloth welded to them (17,600 edges past 3x), its
root lock slid its feet (12 mm at the median) and its 39-key loop skipped a
frame at the wrap. The guard, measured: the pelvis turned 52 degrees to the
figure's right, the chest 55 and folded 33 forward, the face 32 to the right
and 26 down (at the floor), the left foot 0.33 m ahead and the right 0.33 m
behind and turned out 81 - an orthodox fighting stance toward +Z, the enemy.
This builds both of the plan's recipes for each and keeps the better:

  (a) guard   the guard's own motion capture kept - its bounce (3.4 cm), its
              breath, its chest's 6-degree turn, its head and its arms' small
              motion, every joint's deviation from the loop's mean pose -
              with the MEAN pose moved (GUARD_ROWS, per archetype): the arms
              per kit toward the bind, the spine's and the pelvis's fold part
              of the way up (the pelvis keeps its turn: the stance stays
              bladed), the face turned back to the front (a third at the
              spine, the rest at the head) and raised to `gaze`, the knees
              still bent (never deeper than the guard's own), the stagger
              brought part of the way to the bind's spots, the feet planted
              by two-bone IK (no root lock: the hips sway, the feet stay), the
              loop a little slower for the calmer rows, closed as F+1 keys;
  (b) synth   a stance synthesised like the stage idle (natural_idle.pose_at,
              on the same rig read by position) in a READY row per archetype -
              bladed like the guard (the pelvis about 20 degrees, the chest
              23) with the weight on the back leg and the left foot a stride
              ahead, the knees bent, the face to the front, a quick breath (a
              champion's 1.3 s) with a bounce of the hips - and the guard's
              ARMS per kit laid over it (the arm chain's mean local pose,
              blended from the bind), carried by the chest.

"The arms per kit" is one table (ARM_KEEP): the share of the guard's arm pose
kept, from the bind (0) to the guard (1): blades and fists up, casters' and
robed hands low. Each recipe is tried at the kit's share times ARM_STEPS
(down to the bind's arms); where nothing tears no more than today (or no more
than LEVEL_ENOUGH edges), a recipe is tried again at LEVELS 1 and 2: (a)'s
knees straighter and spine taller, then its feet closer; (b) squared (the
blade and the stride mostly out), then its knees straighter. A recipe keeps
(pick_of), of the candidates that pass every guard and tear no more than
today, those within `slack` of the least tear, preferring an arm clear of the
body, then the most guard. The family keeps (choose) the recipe that tears
least; within the slack, the archetype's own (TIE_PREFER: the fighters the
guard's crouch, the kings, graces, mystics and constructs standing tall).
Nothing is kept that tears more than today's stance (Docs/MOTION.md §10's
rule), measured again on the written file by clip_fix.clip_stretch.

The guards (natural_idle's, on the SHIPPED base): the feet planted (a foot
joint drifting under a millimetre), a foot never off the floor (1 mm) nor more
than 5 mm (or today's own sink) into it, no forearm or hand through the thigh
or the trunk beyond natural_idle's ARM_COUNT (or today's own count), the loop
closed, and the carrier binding as the base does.

The raw guard of a `half` or `stand` family is recovered from its shipped
stance by running tools/stand_idle.py's sum backwards: each joint was slerped
toward its rest by a keep share, so the guard is the same slerp EXTRAPOLATED
by its inverse (exact on the geodesic), and the hips' height is re-grounded
on the foot joints as the sum grounded them (`unstand`; a raw family stood up
and recovered comes back to 0.05 degrees and 0.03 mm).

    python3 tools/ready_stance.py survey [families] --json F [--jobs 3]            # measure both recipes
    python3 tools/ready_stance.py survey --out DIR --json F                         # and write the chosen, as <family>_idle_combat.usdz
    python3 tools/ready_stance.py board [families] --json F --out DIR [--per-sheet 4]   # at battle distance: today, (a), (b)
    python3 tools/ready_stance.py ship <families> --bundle DIR [--guard 89]         # a re-ship's derivation (below)

`survey --out` never writes the app's bundle. Since the ship of 2026-09-25 the
app's bundle holds the ready stances themselves (72 as the survey chose, and
Poseidon's (a) by JUDGED), so the guard can no longer be read there: `survey`
and `board` take `--bundle`, a folder `motion_palette.py ship` has written the
guard into, and refuse a stance whose cut report says it is ready already.
`ship` is the derivation that keeps a re-ship from putting the guard back:
`motion_palette.py ship` (a plan stance of `ready:<guard>`), build_asset.sh and
proportions.sh write the guard, then call it; it writes the chosen stance over
the guard, and where nothing passes the guard stays (READY STANCE REFUSED). `natural_idle` is imported from tools/ (only what it had at commit
30dcc775: Rig, Base, carrier_for, pose_at, params_for, draw, feet_drift,
loop_check, pose_facts, the guards' limits and the small maths);
READY_STANCE_NATURAL_IDLE names another copy of it to use.
"""
import argparse
import copy
import importlib.util
import json
import math
import os
import sys
import time
from pathlib import Path

import numpy as np

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import character  # noqa: E402
from character import decompose, quat_to_rot, rot_to_quat, trs, world_from_local  # noqa: E402
import motion_palette as mp  # noqa: E402


def _natural_idle():
    """tools/natural_idle.py, or the copy READY_STANCE_NATURAL_IDLE names
    (another lane edits the tool; a pinned copy keeps a long survey steady)."""
    path = os.environ.get("READY_STANCE_NATURAL_IDLE")
    if not path:
        import natural_idle
        return natural_idle
    spec = importlib.util.spec_from_file_location("natural_idle", path)
    mod = importlib.util.module_from_spec(spec)
    sys.modules["natural_idle"] = mod
    spec.loader.exec_module(mod)
    mod.REPO = HERE.parent
    mod.APP_BUNDLE = HERE.parent / "Pantheon" / "Resources" / "Models"
    return mod


ni = _natural_idle()
REPO = HERE.parent
APP_BUNDLE = REPO / "Pantheon" / "Resources" / "Models"
X, Y, Z = np.eye(3)

# The families this makes a stance for, by their plan stance: the guard raw
# (89), stood 70% up (half) or stood fully up (stand). The calm 35 wear their
# natural idle (step 2); the six on 85's calm tail, Skadi's full draw, the
# Jotunn and the sentinel keep theirs.
STANCES = ("89", "half", "stand")
# stand_idle.KEEP scaled as motion_palette's ship scaled it: `half` is
# stand_idle --keep 2 (70% of the crouch, the arms whole), `stand` --keep 1
STAND_SCALE = {"half": 2.0, "stand": 1.0}
TODAY_TOTAL = 27884           # edges past 3x over the 117 battle stances before step 2 (Docs/PLAN.md)
GUARD_FPS = 30.0              # the guard's keys a second (Meshy's 30); (a) is written at it

# The share of the guard's ARM pose kept, by kit: 1 is the guard's (the
# hands up before the body), 0 the bind's hang. A blade, a pole and a fist
# are held ready; a heavy weapon rests lower; a caster's and a robed figure's
# hands come down (the robe is welded to them; MOTION.md §6).
ARM_KEEP = {"blade": 0.70, "polearm": 0.65, "unarmed": 0.75, "heavy": 0.60, "archer": 0.55, "caster": 0.45,
            "robed": 0.35}
ARM_STEPS = (1.0, 0.72, 0.45, 0.2, 0.0)      # the kit's share times these, most guard first (0: the bind's arms)

# (a): how far the mean pose moves, by archetype (each range drawn from the
# family's hash): `spine` the share of the spine's and the pelvis's tilt stood
# up toward the bind (the guard folds the chest 33 degrees forward; a ready
# fighter leans, a king stands), `reach` the legs' reach at the mean (the knees
# bent, never deeper than the guard's own), `feet` the share of the way the
# feet come from the guard's stagger (a stride 0.42-0.48 of the height, the
# left foot ahead) toward the bind's spots, `face` the share of the guard's
# look to its right (32 degrees) turned back by turning the whole figure,
# `gaze` where the face then looks (degrees, below level: the guard looks 26
# down, at the floor), `tempo` the loop against the guard's 1.3 s.
GUARD_ROWS = {
    "champion": dict(spine=(0.30, 0.40), reach=(0.950, 0.958), feet=(0.30, 0.40), face=1.0, gaze=(-9.0, -6.0),
                     tempo=(0.97, 1.05)),
    "soldier": dict(spine=(0.45, 0.55), reach=(0.960, 0.968), feet=(0.40, 0.50), face=1.0, gaze=(-6.0, -3.0),
                    tempo=(1.08, 1.15)),
    "brute": dict(spine=(0.20, 0.30), reach=(0.940, 0.950), feet=(0.25, 0.35), face=1.0, gaze=(-12.0, -9.0),
                  tempo=(1.12, 1.20)),
    "sovereign": dict(spine=(0.55, 0.65), reach=(0.965, 0.972), feet=(0.50, 0.60), face=1.0, gaze=(-4.0, -1.0),
                      tempo=(1.22, 1.30)),
    "grace": dict(spine=(0.50, 0.60), reach=(0.960, 0.968), feet=(0.45, 0.55), face=1.0, gaze=(-5.0, -2.0),
                  tempo=(1.15, 1.25)),
    "mystic": dict(spine=(0.60, 0.70), reach=(0.968, 0.975), feet=(0.55, 0.65), face=1.0, gaze=(-8.0, -5.0),
                   tempo=(1.28, 1.35)),
    "hunter": dict(spine=(0.35, 0.45), reach=(0.950, 0.958), feet=(0.30, 0.40), face=1.0, gaze=(-5.0, -2.0),
                   tempo=(1.02, 1.08)),
    "trickster": dict(spine=(0.35, 0.45), reach=(0.950, 0.958), feet=(0.30, 0.40), face=1.0, gaze=(-7.0, -4.0),
                      tempo=(0.95, 1.02)),
    "beast": dict(spine=(0.15, 0.25), reach=(0.935, 0.945), feet=(0.25, 0.35), face=1.0, gaze=(-12.0, -8.0),
                  tempo=(0.92, 0.98)),
    "construct": dict(spine=(0.50, 0.60), reach=(0.965, 0.972), feet=(0.50, 0.60), face=1.0, gaze=(-5.0, -2.0),
                      tempo=(1.30, 1.40)),
}


def guard_row(family, level=0):
    """(a)'s numbers for the family: its archetype's GUARD_ROWS row drawn
    from its hash. A family whose stance still tears more than today's is
    tried again at `level` 1 - the knees 0.025 straighter and the spine 0.3
    further up (the cloth between the legs stretches as the knees bend: Sun
    Wukong 111 edges past 3x at a reach of 0.95, 56 at 0.985) - and 2, the
    feet also half the rest of the way to the bind's spots."""
    row = {k: ni.draw(family, "ready_a:" + k, v) for k, v in GUARD_ROWS[mp.archetype(family)].items()}
    if level >= 1:
        row["reach"] = min(0.985, row["reach"] + 0.025)
        row["spine"] = min(0.9, row["spine"] + 0.3)
    if level >= 2:
        row["feet"] = row["feet"] + 0.5 * (1.0 - row["feet"])
    return row


# (b): the READY row laid over natural_idle's archetype row (the same keys as
# its STYLES). The knees bent (reach), the lead foot a stride ahead (step, as a
# share of the height) and turned out, the weight nearer the middle, the
# chest over the feet (lean) with the chin lifted back to level, the face to
# the front, a quick breath (period) with a bounce of the hips (bob, negative:
# the hips sink as the chest lifts), alert glances.
READY_BASE = dict(weight=(0.56, 0.60), stand_in=0.0, narrow=0.0, roll=(1.5, 2.5), hip_yaw=(1.0, 2.0), blade=(17.0, 20.0),
                  twist=(14.0, 17.0), lean=(3.0, 4.5), chin=(2.0, 3.0), head_turn=(1.0, 2.0), head_tilt=(0.5, 1.2),
                  head_face=(0.9, 1.0), period=(1.25, 1.35), breaths=4, breath=(2.0, 2.6), clav=(1.8, 2.4),
                  sway=(0.003, 0.004), fore_sway=(0.0015, 0.0025), bob=(-0.0065, -0.0050), settle=0.0,
                  survey=(1.0, 2.0), survey_k=1.5, glance=(2.0, 3.5), glance_n=2, glance_k=3.0, nod=(0.5, 0.9),
                  bob_head=0.0, neck_roll=0.0, hitch=0.0, twitch=0.0, reach=(0.945, 0.955), reach_free=(0.935, 0.945),
                  step=(0.080, 0.110), turn_out=(12.0, 18.0), tempo=1.0)
# The guard stands bladed - the pelvis 52 degrees to its right, the chest 55,
# the face 32 - so its arms are held for a turned torso: (b) blades the torso
# the same way (after (a)'s face turn it is 20 degrees at the pelvis and 23 at
# the chest; pose_at turns the pelvis by hip_yaw + blade and the chest by
# hip_yaw + 2 blade - twist), the weight on the back (right) leg and the left
# foot a stride ahead, and turns the head back to the front (head_face).
READY = {
    "champion": dict(),
    "soldier": dict(weight=(0.53, 0.56), blade=(14.0, 17.0), twist=(12.0, 15.0), lean=(1.5, 2.5), chin=(1.0, 2.0),
                    period=(1.45, 1.55), breath=(1.6, 2.0), bob=(-0.004, -0.003), reach=(0.955, 0.965),
                    reach_free=(0.945, 0.955), step=(0.070, 0.090), turn_out=(10.0, 14.0), glance=(2.0, 3.0)),
    "brute": dict(weight=(0.54, 0.58), blade=(15.0, 18.0), twist=(12.0, 15.0), lean=(5.0, 7.0), chin=(3.0, 4.0),
                  period=(1.6, 1.75), breaths=3, breath=(2.6, 3.2), clav=(2.8, 3.4), clav_fwd=(2.0, 3.5),
                  bob=(-0.008, -0.006), neck_roll=(1.5, 2.5), reach=(0.935, 0.945), reach_free=(0.925, 0.935),
                  step=(0.080, 0.100)),
    "sovereign": dict(weight=(0.58, 0.62), blade=(10.0, 13.0), twist=(8.0, 10.0), lean=(1.0, 2.0), chin=(1.5, 2.5),
                      period=(1.8, 2.0), breaths=3, breath=(1.4, 1.8), bob=(-0.0035, -0.0025), reach=(0.960, 0.968),
                      reach_free=(0.950, 0.958), step=(0.060, 0.080), turn_out=(8.0, 12.0), glance=(1.0, 2.0),
                      survey=(3.0, 4.5)),
    "grace": dict(weight=(0.60, 0.64), roll=(2.5, 3.5), blade=(12.0, 15.0), twist=(10.0, 12.0), lean=(1.5, 2.5),
                  chin=(1.5, 2.5), period=(1.6, 1.8), breaths=3, breath=(1.6, 2.0), bob=(-0.004, -0.003),
                  reach=(0.958, 0.966), reach_free=(0.945, 0.955), step=(0.070, 0.090)),
    "mystic": dict(weight=(0.55, 0.58), blade=(6.0, 9.0), twist=(4.0, 6.0), lean=(0.5, 1.5), chin=(0.5, 1.5),
                   period=(1.9, 2.1), breaths=3, breath=(1.3, 1.6), bob=(0.0025, 0.0035), reach=(0.965, 0.972),
                   reach_free=(0.955, 0.962), step=(0.040, 0.060), turn_out=(6.0, 9.0), glance=(0.5, 1.0),
                   survey=(1.0, 2.0)),
    "hunter": dict(weight=(0.62, 0.66), blade=(20.0, 24.0), twist=(14.0, 18.0), period=(1.4, 1.5),
                   glance=(2.5, 4.0), glance_k=4.0, survey=(2.5, 3.5), step=(0.100, 0.130), turn_out=(15.0, 20.0)),
    "trickster": dict(weight=(0.62, 0.66), roll=(3.5, 4.5), hip_yaw=(2.0, 3.0), head_tilt=(3.0, 5.0),
                      period=(1.2, 1.3), glance=(3.5, 5.0), glance_n=3, hitch=(0.15, 0.25)),
    "beast": dict(weight=(0.54, 0.57), blade=(10.0, 14.0), twist=(8.0, 11.0), lean=(7.0, 9.0), chin=(5.0, 7.0),
                  period=(1.1, 1.2), breaths=5, breath=(2.2, 2.8), clav_fwd=(1.5, 3.0), bob=(-0.008, -0.006),
                  bob_head=(1.0, 1.8), glance=(3.0, 4.5), glance_n=4, glance_k=5.0, reach=(0.925, 0.935),
                  reach_free=(0.915, 0.925), step=(0.070, 0.090)),
    "construct": dict(weight=(0.52, 0.55), roll=(0.8, 1.5), blade=(4.0, 7.0), twist=(3.0, 5.0), lean=(1.0, 2.0),
                      chin=(0.5, 1.5), period=(2.1, 2.3), breaths=3, breath=(0.15, 0.3), clav=(0.2, 0.4), bob=0.0,
                      settle=(0.002, 0.003), glance=0.0, twitch=(4.0, 6.0), reach=(0.965, 0.972),
                      reach_free=(0.958, 0.965), step=(0.040, 0.060), turn_out=(5.0, 8.0)),
}
LEVEL_ENOUGH = 20                 # a recipe's best at a level tearing more than this tries the next level too
LEVELS = (0, 1, 2)                # the fallbacks (guard_row, ready_params' square), each tried only where the one before failed
ARM_OUT = (4.0, 8.0, 12.0)        # (b)'s swing out of an arm the guard finds in the body, tried in turn
STAND_B = "R"         # (b) stands on the guard's back leg, the left foot ahead, as the guard does
# On a tie (within the slack), which recipe reads as the archetype's ready
# stance: the fighters keep the guard's bladed crouch and its captured
# bounce, the kings, the graces, the mystics and the constructs stand tall.
TIE_PREFER = {"champion": "a", "soldier": "a", "brute": "a", "trickster": "a", "hunter": "a", "beast": "a",
              "sovereign": "b", "grace": "b", "mystic": "b", "construct": "b"}         # (b) stands on the guard's back leg, the left foot ahead, as the guard does

# Families whose ready stance is judged, not dealt: laid over both recipes.
#   arms     "natural": the arms are natural_idle's for its row (the Jiangshi
#            holds its arms out before it, which the guard would drop)
#   keep     the family keeps today's stance, with the reason
#   prefer   "a" or "b": the recipe to keep where both pass (the boards' call)
JUDGED = {
    # The judge of 2026-09-25 held the sovereign's tie-break (b) on Poseidon: it
    # holds the trident out LEVEL to the side, the fault the idles' weapon hang
    # had just mended; (a) lowers it and tears less (2 edges past 3x against 5).
    "poseidon": {"prefer": "a", "note": "trident lowered, not level"},
}


# ---------------------------------------------------------------------------
# Quaternions (x, y, z, w), row-vector rotations as tools/character.py
# ---------------------------------------------------------------------------

def qnorm(q):
    q = np.asarray(q, float)
    return q / np.linalg.norm(q, axis=-1, keepdims=True)


def qslerp(q0, q1, t):
    """Slerp along the short arc; t outside 0..1 extrapolates on the same
    great circle (what running stand_idle's slerp backwards needs)."""
    q0, q1 = qnorm(q0), qnorm(q1)
    dot = np.sum(q0 * q1, axis=-1, keepdims=True)
    q1 = np.where(dot < 0, -q1, q1)
    dot = np.clip(np.abs(dot), -1.0, 1.0)
    th = np.arccos(dot)
    s = np.sin(th)
    near = s < 1e-7
    w0 = np.where(near, 1 - t, np.sin((1 - t) * th) / np.where(near, 1, s))
    w1 = np.where(near, t, np.sin(t * th) / np.where(near, 1, s))
    return qnorm(w0 * q0 + w1 * q1)


def qmean(qs):
    """The mean of a small cloud of rotations (every one on the first's hemisphere)."""
    qs = np.asarray(qs, float)
    sign = np.sign(np.sum(qs * qs[0], axis=-1))
    sign[sign == 0] = 1
    return qnorm((qs * sign[:, None]).sum(0))


def mrot(q):
    return quat_to_rot(q)


def continuous(R):
    """One sign along each track (F, J, 4)."""
    R = np.array(R, float)
    for f in range(1, len(R)):
        flip = np.sum(R[f] * R[f - 1], axis=1) < 0
        R[f, flip] *= -1
    return R


# ---------------------------------------------------------------------------
# The guard
# ---------------------------------------------------------------------------

def plan_rows():
    """{family: (guard, kind)} for the families this makes a stance for: the
    plan's `ready` stances (motion_palette.make_plan), each over its guard as
    the deal had it - 89 raw, `half` or `stand` (the plan's `guard`)."""
    plan, _ = mp.make_plan()
    out = {}
    for f, p in sorted(plan.items()):
        s = str(p.get("guard") or p["clips"].get("idle_combat"))
        if s in STANCES:
            out[f] = (s, p["kind"])
    return out


def stand_group(leaf):
    """stand_idle.group: which KEEP share a joint took."""
    n = leaf.lower()
    if any(k in n for k in ("hips", "spine", "neck", "head")):
        return "spine"
    if any(k in n for k in ("upleg", "leg", "foot", "toe")):
        return "legs"
    return "arms"


def fk(char, anim, f):
    local = np.array([trs(anim["T"][f, j], anim["R"][f, j], anim["S"][f, j]) for j in range(len(char.joints))])
    return world_from_local(local, char.parents)


def lowest_foot(char, W):
    """stand_idle.lowest_foot on a world pose."""
    from stand_idle import FEET
    ys = [W[j][3, 1] for j, name in enumerate(char.joints) if name.split("/")[-1] in FEET]
    return min(ys) if ys else W[0][3, 1]


def unstand(char, scale):
    """The raw guard back from a stance tools/stand_idle.py stood up with
    `scale` (motion_palette's `half` 2.0, `stand` 1.0): every joint's rotation
    was slerped from its rest by keep k = min(1, KEEP[group] x scale), so the
    raw is that slerp extrapolated to 1/k; the hips' x and z were kept, their
    dip below rest halved (stand) and the frame re-grounded on the foot
    joints, so the raw's hips stand where its lowest foot is the stood one's."""
    from stand_idle import KEEP
    a = char.anim
    F, J = a["T"].shape[:2]
    rest_q = np.array([decompose(char.rest_local[j])[1] for j in range(J)])
    R = np.array(a["R"], float)
    for j, name in enumerate(char.joints):
        k = min(1.0, KEEP[stand_group(name.split("/")[-1])] * scale)
        if k < 1.0:
            R[:, j] = qslerp(np.repeat(rest_q[j][None], F, 0), R[:, j], 1.0 / k)
    T = np.array(a["T"], float)
    raw = {"T": T, "R": continuous(R), "S": np.array(a["S"], float), "fps": a["fps"]}
    hips = next((j for j, n in enumerate(char.joints) if n.split("/")[-1].lower() == "hips"), 0)
    for f in range(F):
        stood = lowest_foot(char, fk(char, a, f))
        now = lowest_foot(char, fk(char, raw, f))
        T[f, hips, 1] += stood - now
    return raw


def guard_for(family, carrier, stance):
    """The family's raw guard on its carrier (float64 keys)."""
    a = carrier.anim
    if stance == "89":
        return {"T": np.array(a["T"], float), "R": continuous(a["R"]), "S": np.array(a["S"], float), "fps": a["fps"]}
    return unstand(carrier, STAND_SCALE[stance])


def local_rots(anim):
    """(F, J, 3, 3) local rotation matrices of a clip."""
    F, J = anim["R"].shape[:2]
    out = np.empty((F, J, 3, 3))
    for f in range(F):
        for j in range(J):
            out[f, j] = mrot(anim["R"][f, j])
    return out


class Guard:
    """The raw guard read once: its mean local pose, each key's deviation
    from it, and the world facts a stance needs (the feet, the hips over
    them, the knees' plane)."""

    def __init__(self, rig, anim):
        self.rig, self.anim = rig, anim
        c = rig.c
        F, J = anim["R"].shape[:2]
        self.F, self.J = F, J
        # a loop of F keys whose key F would be key 0 (prepare() drops the
        # tail it blended into the head), or F keys with the last the first
        closed = np.abs(anim["T"][-1] - anim["T"][0]).max() < 1e-5 and \
            (1 - np.abs(np.sum(anim["R"][-1] * anim["R"][0], axis=1))).max() < 1e-7
        self.n = F - 1 if closed else F
        R = anim["R"][:self.n]
        self.mean_q = np.array([qmean(R[:, j]) for j in range(J)])
        self.mean = np.array([mrot(q) for q in self.mean_q])
        Wf = [fk(c, anim, f) for f in range(self.n)]
        self.world = np.array(Wf)
        legs = {s: rig.leg[s] for s in "LR"}
        feet = {s: self.world[:, legs[s]["foot"], 3, :3] for s in "LR"}
        anchor = 0.5 * (feet["L"] + feet["R"])
        self.anchor0 = anchor.mean(0)
        # the hips over the feet, key by key: the shipped guard's root lock
        # pinned the hips and slid the feet, so the sway is read against them
        hips = self.world[:, rig.hips, 3, :3]
        self.hips_rel = hips - anchor
        self.feet_rel = {s: (feet[s] - anchor).mean(0) for s in "LR"}
        self.foot_rot = {s: qmean([rot_to_quat(ni.rotation_part(w)) for w in self.world[:, legs[s]["foot"]]])
                         for s in "LR"}
        # the knee's plane and each leg's reach at the mean
        self.pole, self.reach = {}, {}
        for s in "LR":
            u, k, fj = legs[s]["upleg"], legs[s]["knee"], legs[s]["foot"]
            P = self.world[:, [u, k, fj], 3, :3].mean(0)
            axis = ni.unit(P[2] - P[0])
            off = (P[1] - P[0]) - ((P[1] - P[0]) @ axis) * axis
            a_len = np.linalg.norm(rig.pos0[k] - rig.pos0[u])
            b_len = np.linalg.norm(rig.pos0[fj] - rig.pos0[k])
            self.reach[s] = float(np.linalg.norm(P[2] - P[0]) / (a_len + b_len))
            self.pole[s] = ni.unit(off) if np.linalg.norm(off) > 0.01 * rig.height else rig.knee_pole[s]

    def deviation(self, f):
        """(J, 3, 3): key f's local rotation against the mean, in each bone's own frame (R_f = D @ M)."""
        f = f % self.n
        R = np.array([mrot(q) for q in self.anim["R"][f]])
        return np.einsum("jab,jcb->jac", R, self.mean)

    def facts(self):
        """Readable numbers of the guard: the arms from straight down, the legs' reach, the hips' travel."""
        rig = self.rig
        W = self.world
        arms = []
        for s in "LR":
            a = rig.arm[s]
            v = ni.unit(W[:, a["fore"], 3, :3].mean(0) - W[:, a["upper"], 3, :3].mean(0))
            arms.append(round(math.degrees(math.acos(max(-1.0, min(1.0, -v[1])))), 1))
        return dict(arms=arms, reach={s: round(v, 3) for s, v in self.reach.items()},
                    bob_cm=round(float(np.ptp(self.hips_rel[:, 1])) * 100, 2),
                    sway_cm=round(float(np.ptp(self.hips_rel[:, 0])) * 100, 2),
                    feet_slide_cm=round(float(np.ptp(self.world[:, rig.leg["L"]["foot"], 3, 0])) * 100, 2),
                    loop_s=round(self.n / self.anim["fps"], 3))


# ---------------------------------------------------------------------------
# Building a stance
# ---------------------------------------------------------------------------

def bind_local(rig):
    """(J, 3, 3) each joint's bind rotation against its parent's (row vectors: W_j = L_j @ W_p)."""
    R0 = rig.rot0
    out = np.empty_like(R0)
    for j in range(len(R0)):
        p = int(rig.parents[j])
        out[j] = R0[j] @ R0[p].T if p >= 0 else R0[j]
    return out


def mslerp(a, b, t):
    """Slerp between two rotation matrices (t=0 a, t=1 b)."""
    return mrot(qslerp(rot_to_quat(a), rot_to_quat(b), t))


def leg_joints(rig):
    out = set()
    for s in "LR":
        g = rig.leg[s]
        out |= {g["upleg"], g["knee"], g["foot"], *g["toes"]}
    return out


def arm_chain(rig, side):
    a = rig.arm[side]
    return [j for j in (a["clav"], a["upper"], a["fore"], a["hand"]) if j is not None]


def arm_subtree(rig, side):
    """The arm's joints and everything under them (a hand's markers)."""
    start = arm_chain(rig, side)[0]
    out, stack = [], [start]
    while stack:
        k = stack.pop()
        out.append(k)
        stack.extend(rig.children[k])
    return out


def two_bone(rig, side, H, F, pole0, pole, turn_rot, Rw, Pw):
    """natural_idle.pose_at's leg: the hip at H, the ankle on F, the knee
    toward `pole` (the bind's `pole0`), the foot's world rotation its bind's
    turned by `turn_rot`; the toes ride with it. Writes Rw, Pw."""
    R0, P0 = rig.rot0, rig.pos0
    g = rig.leg[side]
    u, k, f = g["upleg"], g["knee"], g["foot"]
    a, bb = np.linalg.norm(P0[k] - P0[u]), np.linalg.norm(P0[f] - P0[k])
    d_vec = F - H
    d = min(max(np.linalg.norm(d_vec), abs(a - bb) + 1e-4), (a + bb) * 0.9995)
    axis = ni.unit(d_vec)
    pole = ni.unit(pole - (pole @ axis) * axis)
    x = (a * a - bb * bb + d * d) / (2 * d)
    y = math.sqrt(max(a * a - x * x, 0.0))
    K = H + axis * x + pole * y
    Rw[u] = R0[u] @ ni.frame_rotation(P0[k] - P0[u], pole0, K - H, pole)
    Pw[u] = H
    Rw[k] = R0[k] @ ni.frame_rotation(P0[f] - P0[k], pole0, F - K, pole)
    Pw[k] = Pw[u] + (P0[k] - P0[u]) @ R0[u].T @ Rw[u]
    Rw[f] = R0[f] @ turn_rot
    Pw[f] = Pw[k] + (P0[f] - P0[k]) @ R0[k].T @ Rw[k]
    prev = f
    for jt in g["toes"]:
        Rw[jt] = R0[jt] @ turn_rot
        Pw[jt] = Pw[prev] + (P0[jt] - P0[prev]) @ R0[prev].T @ Rw[prev]
        prev = jt


def fk_rest_of(rig, Rloc, skip, Rw, Pw):
    """World rotations and positions from local rotations for every joint
    not in `skip` (parents first; the root's position already in Pw)."""
    R0, P0 = rig.rot0, rig.pos0
    for j in range(len(R0)):
        if j in skip:
            continue
        p = int(rig.parents[j])
        if p < 0:
            Rw[j] = Rloc[j]
            continue
        Rw[j] = Rloc[j] @ Rw[p]
        Pw[j] = Pw[p] + (P0[j] - P0[p]) @ R0[p].T @ Rw[p]


def to_keys(rig, frames_world, fps):
    """F+1 keys (the last the first) from world poses [(Rw, Pw)] on the carrier's joints."""
    J = len(rig.names)
    F = len(frames_world)
    T = np.empty((F + 1, J, 3))
    R = np.empty((F + 1, J, 4))
    S = np.empty((F + 1, J, 3))
    rest_t = np.array([rig.parts[j][0] for j in range(J)])
    scales = np.array([rig.parts[j][2] for j in range(J)])
    roots = rig.parents < 0
    for fr, (Rw, Pw) in enumerate(frames_world):
        for j in range(J):
            p = int(rig.parents[j])
            q = rot_to_quat(Rw[j] @ Rw[p].T if p >= 0 else Rw[j])
            if fr and np.dot(q, R[fr - 1, j]) < 0:
                q = -q
            R[fr, j] = q
        T[fr] = rest_t
        T[fr, roots] = Pw[roots]
        S[fr] = scales
    T[F], S[F] = T[0], S[0]
    sign = np.sign(np.sum(R[0] * R[F - 1], axis=1))
    sign[sign == 0] = 1.0
    R[F] = R[0] * sign[:, None]
    return {"T": T.astype(np.float32), "R": R.astype(np.float32), "S": S.astype(np.float32), "fps": float(fps)}


def reach_targets(rig, row_reach, guard_reach=None):
    """Each leg's reach at the mean: the row's, measured from the leg's own
    bind where the bind holds it bent (a hoof, a paw: pose_at's rule), and
    never deeper than the guard's own (the ready stance crouches less)."""
    out = {}
    for s in "LR":
        b = rig.bind_reach[s]
        r = row_reach if b >= 0.985 else b - (0.985 - row_reach)
        if guard_reach is not None:
            r = max(r, min(guard_reach[s], b - 0.002))
        out[s] = min(r, 0.998)
    return out


def hips_height(rig, Rw_hips, hip_xz, feet, reach):
    """The hips' height that stands each leg at no more than its reach over
    its foot target (the lower of the two answers)."""
    R0, P0 = rig.rot0, rig.pos0
    ys = []
    for s in "LR":
        g = rig.leg[s]
        u, k, f = g["upleg"], g["knee"], g["foot"]
        a, bb = np.linalg.norm(P0[k] - P0[u]), np.linalg.norm(P0[f] - P0[k])
        off = (P0[u] - P0[rig.hips]) @ R0[rig.hips].T @ Rw_hips
        hx, hz = hip_xz[0] + off[0], hip_xz[1] + off[2]
        horiz = math.hypot(feet[s][0] - hx, feet[s][2] - hz)
        need = math.sqrt(max((reach[s] * (a + bb)) ** 2 - horiz ** 2, 1e-9))
        ys.append(feet[s][1] + need - off[1])
    return min(ys)


def clamp_reach(rig, Pw_hips, Rw_hips, feet, top=0.998):
    """Lowers the hips where a leg would have to reach past `top` of its length."""
    R0, P0 = rig.rot0, rig.pos0
    y = Pw_hips[1]
    for s in "LR":
        g = rig.leg[s]
        u, k, f = g["upleg"], g["knee"], g["foot"]
        a, bb = np.linalg.norm(P0[k] - P0[u]), np.linalg.norm(P0[f] - P0[k])
        off = (P0[u] - P0[rig.hips]) @ R0[rig.hips].T @ Rw_hips
        hx, hz = Pw_hips[0] + off[0], Pw_hips[2] + off[2]
        horiz = math.hypot(feet[s][0] - hx, feet[s][2] - hz)
        lim = feet[s][1] + math.sqrt(max((top * (a + bb)) ** 2 - horiz ** 2, 1e-9)) - off[1]
        y = min(y, lim)
    out = Pw_hips.copy()
    out[1] = y
    return out


def yaw_of(rig, W, j):
    """The world yaw (degrees, +Z toward +X) joint j has turned since the bind."""
    D = rig.rot0[j].T @ ni.rotation_part(W[j])
    f = Z @ D
    return math.degrees(math.atan2(f[0], f[2]))


def pitch_of(rig, W, j):
    """The world pitch (degrees, up positive) of the direction joint j faced (+Z) in the bind."""
    f = Z @ (rig.rot0[j].T @ ni.rotation_part(W[j]))
    return math.degrees(math.atan2(f[1], math.hypot(f[0], f[2])))


def rot_world(rig, Rloc):
    """(J, 3, 3) world rotations from local ones."""
    out = np.empty_like(Rloc)
    for j in range(len(Rloc)):
        p = int(rig.parents[j])
        out[j] = Rloc[j] @ out[p] if p >= 0 else Rloc[j]
    return out


def tilt_up(rig, Rloc, W, j, deg):
    """Joint j's local rotation with its world pitch raised by `deg` (about
    the world axis across the way it faces)."""
    f = Z @ (rig.rot0[j].T @ W[j])
    axis = ni.unit(np.cross(Y, np.array([f[0], 0.0, f[2]])))
    p = int(rig.parents[j])
    Wp = W[p] if p >= 0 else np.eye(3)
    return Rloc[j] @ Wp @ ni.about(axis, -deg) @ Wp.T


def face_joint(rig):
    """The joint whose turn says where the face looks: the one NAMED Head
    (the retarget gave every rig the donor's Head by name; on the eleven
    rigs where it is an end marker it still carries the donor's turn), else
    the joint carrying the skull."""
    return rig.names.index("Head") if "Head" in rig.names else rig.head


def turn_at(rig, Rloc, W, j, deg):
    """Joint j's local rotation with its world rotation turned `deg` about
    the vertical (everything above it turns with it)."""
    p = int(rig.parents[j])
    Wp = W[p] if p >= 0 else np.eye(3)
    return Rloc[j] @ Wp @ ni.about(Y, deg) @ Wp.T


def recipe_a(rig, guard, arm_keep, row, arms_natural=None):
    """(a): the guard's motion over a moved mean pose (module docstring).
    `arm_keep`: the share of the guard's arm pose kept (0 the bind's). `row`:
    spine (the share of the spine's and the pelvis's tilt stood up; the
    pelvis keeps its turn), reach (the knees), feet (the share of the way
    the feet come from the guard's long stagger and turned-out back foot
    toward the bind's spots and facing), face (the share of the guard's look
    off to its right turned back to the front - a third at the spine, the
    rest at the head, the bladed stance kept), gaze (the face's pitch),
    tempo (the loop against the guard's 1.3 s). Returns (anim, facts)."""
    J = len(rig.names)
    Lb = bind_local(rig)
    M = guard.mean
    R0, P0 = rig.rot0, rig.pos0
    s_spine = row["spine"]
    Mn = M.copy()
    for j in rig.spine + rig.neck + [rig.head]:
        Mn[j] = mslerp(M[j], Lb[j], s_spine)
    # the pelvis stood up but still turned: toward the bind turned by the guard's own yaw
    Wm = rot_world(rig, M)
    hip_yaw = yaw_of(rig, Wm, rig.hips)
    Mn[rig.hips] = mslerp(M[rig.hips], R0[rig.hips] @ ni.about(Y, hip_yaw), s_spine)
    for s in "LR":
        for j in arm_chain(rig, s):
            Mn[j] = mslerp(M[j], Lb[j], 1.0 - arm_keep)
    legs = leg_joints(rig)
    # the face to the front: a third of the look at the spine's foot, the rest at the head
    Wn = rot_world(rig, Mn)
    look = yaw_of(rig, Wn, face_joint(rig))
    turn_back = -row.get("face", 1.0) * look
    Mn[rig.spine[0]] = turn_at(rig, Mn, Wn, rig.spine[0], turn_back / 3)
    Wn = rot_world(rig, Mn)
    Mn[rig.head] = turn_at(rig, Mn, Wn, rig.head, -row.get("face", 1.0) * yaw_of(rig, Wn, face_joint(rig)))
    # the face raised (or lowered) to `gaze` below level, at the joint that carries the skull
    Wn = rot_world(rig, Mn)
    pitch = pitch_of(rig, Wn, face_joint(rig))
    Mn[rig.head] = tilt_up(rig, Mn, Wn, rig.head, row.get("gaze", pitch) - pitch)
    # the feet: the guard's stagger (the left foot ahead, the right behind
    # and turned out), brought `feet` of the way toward the bind's spots and
    # facing, flat as in the bind; each knee turned with its foot
    mid0 = 0.5 * (P0[rig.leg["L"]["foot"]] + P0[rig.leg["R"]["foot"]])
    share = row.get("feet", 0.0)
    feet, turn, pole = {}, {}, {}
    for s in "LR":
        fj = rig.leg[s]["foot"]
        rel = (1 - share) * guard.feet_rel[s] + share * (P0[fj] - mid0)
        T = guard.anchor0 + rel
        T[1] = P0[fj][1]
        feet[s] = T
        f = Z @ (R0[fj].T @ mrot(guard.foot_rot[s]))
        yaw_g = math.degrees(math.atan2(f[0], f[2]))
        turn[s] = ni.about(Y, (1 - share) * yaw_g)
        pole[s] = guard.pole[s] @ ni.about(Y, -share * yaw_g)
    reach = reach_targets(rig, row["reach"], guard.reach)
    rel_mean = guard.hips_rel.mean(0)
    hip_xz = (guard.anchor0 + rel_mean)[[0, 2]]
    y0 = hips_height(rig, Mn[rig.hips], hip_xz, feet, reach)
    tempo = row.get("tempo", 1.0)
    n_out = int(round(guard.n * tempo))
    frames_world = []
    for i in range(n_out):
        u = i * guard.n / n_out
        f0 = int(math.floor(u)) % guard.n
        f1 = (f0 + 1) % guard.n
        w = u - math.floor(u)
        D0, D1 = guard.deviation(f0), guard.deviation(f1)
        rel = (1 - w) * guard.hips_rel[f0] + w * guard.hips_rel[f1] - rel_mean
        Rloc = np.empty((J, 3, 3))
        for j in range(J):
            if j in legs:
                Rloc[j] = Lb[j]
                continue
            D = mslerp(D0[j], D1[j], w) if w > 1e-9 else D0[j]
            Rloc[j] = D @ Mn[j]
        if arms_natural is not None:
            for j, Rj in arms_natural(i / n_out).items():
                Rloc[j] = Rj
        Rw = np.empty((J, 3, 3))
        Pw = np.empty((J, 3))
        Rw[rig.hips] = Rloc[rig.hips]
        hip = np.array([hip_xz[0] + rel[0], y0 + rel[1], hip_xz[1] + rel[2]])
        Pw[rig.hips] = clamp_reach(rig, hip, Rw[rig.hips], feet)
        fk_rest_of(rig, Rloc, legs | {rig.hips}, Rw, Pw)
        for s in "LR":
            g = rig.leg[s]
            H = Pw[rig.hips] + (P0[g["upleg"]] - P0[rig.hips]) @ R0[rig.hips].T @ Rw[rig.hips]
            two_bone(rig, s, H, feet[s], rig.knee_pole[s], pole[s], turn[s], Rw, Pw)
        frames_world.append((Rw, Pw))
    anim = to_keys(rig, frames_world, guard.anim["fps"])
    return anim, dict(recipe="a", arm_keep=round(arm_keep, 3), reach={s: round(v, 3) for s, v in reach.items()},
                      spine=round(s_spine, 3), feet=round(share, 3), face=round(turn_back, 1),
                      gaze=round(row.get("gaze", pitch), 1), guard_gaze=round(pitch, 1),
                      loop=round(n_out / guard.anim["fps"], 3))


def ready_params(family, rig, natural_arms=False, square=0.0):
    """(b)'s numbers: natural_idle's row for the family, the READY rows laid
    over it (each range drawn from the family's hash), the loop a whole
    number of quick breaths. With `natural_arms` the family keeps
    natural_idle's OVERRIDES (the Jiangshi's arms held out before it)."""
    p = dict(ni.params_for(family, rig.height, level="full", overrides=None if natural_arms else {}), family=family)
    arch = mp.archetype(family)
    row = dict(READY_BASE)
    row.update(READY.get(arch, {}))
    for k, v in row.items():
        p[k] = ni.draw(family, "ready:" + k, v)
    # `square` 1 takes the blade and the stride most of the way out (a skirt
    # or a tail between the legs tears in the bladed stance), 2 the knees
    # 0.025 straighter as well
    if square >= 1:
        for k in ("blade", "twist", "step"):
            p[k] *= 0.4
    if square >= 2:
        p["reach"] = min(0.985, p["reach"] + 0.025)
        p["reach_free"] = min(0.975, p["reach_free"] + 0.025)
    tempo = p.get("tempo", 1.0)
    if rig.height > 2.6:
        tempo *= 1.0 / min(1.5, math.sqrt(rig.height / 1.9))
    fps = SYNTH_FPS
    frames = int(round(p["period"] / tempo * p["breaths"] * fps))
    p["loop"] = frames / fps
    p["period"] = p["loop"] / p["breaths"]
    p["frames"] = frames
    p["arm_out_L"] = p["arm_out_R"] = 0.0
    return p


SYNTH_FPS = 20.0      # (b)'s keys a second, as the stage idles (natural_idle.FPS)


def recipe_b(rig, guard, p, stand, arm_keep, arms_natural=False, arm_out=0.0):
    """(b): natural_idle.pose_at in the READY row, with the guard's arms
    (the arm chain's mean local pose, `arm_keep` of the way from the bind)
    laid over it, carried by the chest; the clavicles keep the breath.
    `arm_out` swings both upper arms that many degrees out from the body in
    the chest's own plane (the guard found a hand in the body)."""
    Lb = bind_local(rig)
    M = guard.mean
    arms = {}
    for s in "LR":
        for j in arm_chain(rig, s):
            arms[j] = mslerp(Lb[j], M[j], arm_keep)
    frames_world = []
    R0, P0 = rig.rot0, rig.pos0
    for fr in range(p["frames"]):
        Rw, Pw = ni.pose_at(rig, fr / SYNTH_FPS, p, stand)
        if not arms_natural:
            for s in "LR":
                chain = arm_chain(rig, s)
                clav = rig.arm[s]["clav"]
                for j in arm_subtree(rig, s):
                    pj = int(rig.parents[j])
                    if j in arms:
                        L = arms[j]
                        if j == clav:
                            posed = Rw[j] @ Rw[pj].T
                            L = (posed @ Lb[j].T) @ arms[j]
                    else:
                        L = Lb[j] if j not in chain else Rw[j] @ Rw[pj].T
                    Rw[j] = L @ Rw[pj]
                    if arm_out and j == rig.arm[s]["upper"]:
                        fwd = Z @ (R0[rig.chest].T @ Rw[rig.chest])
                        Rw[j] = Rw[j] @ ni.about(fwd, (1.0 if s == "L" else -1.0) * arm_out)
                    Pw[j] = Pw[pj] + (P0[j] - P0[pj]) @ R0[pj].T @ Rw[pj]
        frames_world.append((Rw.copy(), Pw.copy()))
    anim = to_keys(rig, frames_world, SYNTH_FPS)
    return anim, dict(recipe="b", arm_keep=round(arm_keep, 3), stand=stand, loop=round(p["loop"], 3),
                      breath_s=round(p["period"], 3), arm_out=arm_out, blade=round(p["blade"], 1),
                      step=round(p["step"], 3))


# ---------------------------------------------------------------------------
# Measuring
# ---------------------------------------------------------------------------

def measure(base, rig, anim, samples=24, sink_ok=None, through_ok=None):
    """natural_idle's measures on the shipped base (the tear is
    clip_fix.clip_stretch's frames and count) and its guards' verdicts. A
    stance is allowed the floor sink and the arm points in the body that the
    stance it replaces already has (`sink_ok` in mm, `through_ok`): a guard
    whose heel is skinned half to a bent shin sinks in battle today."""
    m = base.measure(anim, rig.c.joints, rig, samples=samples)
    m["drift_mm"] = round(ni.feet_drift(rig, anim) * 1000, 3)
    closed, seam = ni.loop_check(anim)
    m.update(closed=closed, seam=round(seam, 2))
    m.update(ni.pose_facts(rig, anim))
    sink_lim = max(1000 * ni.FLOOR_SINK * max(1.0, rig.height / 1.9), sink_ok or 0.0)
    through_lim = max(ni.ARM_COUNT, through_ok or 0)
    fails = []
    if m["drift_mm"] > ni.FOOT_DRIFT * 1000:
        fails.append(f"feet drift {m['drift_mm']:.2f} mm")
    if m["floor_mm"] > ni.FLOOR_DRIFT * 1000:
        fails.append(f"a foot off the floor by {m['floor_mm']:.2f} mm")
    if m["sink_mm"] > sink_lim:
        fails.append(f"a foot {m['sink_mm']:.2f} mm into the floor")
    if m["through"] + m["through_held"] > through_lim:
        fails.append(f"arm through the body ({m['through']} arm, {m['through_held']} held)")
    if not closed:
        fails.append("the loop does not close")
    if seam > 1.5:
        fails.append(f"the seam steps {seam:.1f}x the loop's own step")
    m["fails"] = fails
    return m


def motion_facts(rig, anim):
    """How much the stance moves: the hips' bob and sway (cm), the chest's
    turn and the head's yaw (degrees, peak to peak), the loop (s)."""
    J = len(rig.names)
    n = len(anim["T"]) - 1
    hips = np.asarray(anim["T"])[:n, rig.hips]
    yaw_c, yaw_h = [], []
    for f in range(n):
        local = np.array([trs(anim["T"][f, j], anim["R"][f, j], anim["S"][f, j]) for j in range(J)])
        W = world_from_local(local, rig.parents)
        for j, out in ((rig.chest, yaw_c), (rig.head, yaw_h)):
            fwd = np.array([0.0, 0.0, 1.0]) @ (rig.rot0[j].T @ ni.rotation_part(W[j]))
            out.append(math.degrees(math.atan2(fwd[0], fwd[2])))
    return dict(bob_cm=round(float(np.ptp(hips[:, 1])) * 100, 2), sway_cm=round(float(np.ptp(hips[:, 0])) * 100, 2),
                chest_deg=round(float(np.ptp(yaw_c)), 2), head_deg=round(float(np.ptp(yaw_h)), 2),
                loop_s=round(n / anim["fps"], 2))


# ---------------------------------------------------------------------------
# Boards at battle distance
# ---------------------------------------------------------------------------
# The battle camera (Docs/PLAN.md, the camera of 2026-09-24): square behind
# the team at a 19 degree pitch through a 28 degree lens, the team 0.30 of
# the frame tall and the enemies 0.18 on a 390-point landscape frame. A board
# draws each figure at the team's size (about a third of 390 points, drawn at
# two pixels a point), from behind and a little to one side as the camera
# sees a team member off the frame's centre line, and from the front at the
# same pitch as it sees an enemy.
PITCH = 19.0
TEAM_YAW = 155.0          # from behind (180), turned 25 degrees: three-quarter from behind
POINTS_TALL = 390 * 0.30  # the team's height on the phone, in points
PX_PER_POINT = 2.0


def view_matrix(yaw, pitch):
    """p @ M -> (screen right, screen up, toward the camera) for a camera at
    `yaw` degrees round +Y from the figure's front (+Z) and `pitch` above."""
    y, p = math.radians(yaw), math.radians(pitch)
    c = np.array([math.sin(y) * math.cos(p), math.sin(p), math.cos(y) * math.cos(p)])
    r = ni.unit(np.cross(Y, c))
    u = np.cross(c, r)
    return np.column_stack([r, u, c])


def battle_views():
    import preview
    preview.VIEWS["team"] = view_matrix(TEAM_YAW, PITCH)
    preview.VIEWS["enemy"] = view_matrix(0.0, PITCH)
    return ("team", "enemy")


def render_pose(base, anim, joints, frame, views, tex):
    """One image per view of the base posed at `frame`, the figure drawn
    POINTS_TALL points tall at PX_PER_POINT."""
    import preview
    size = int(round(POINTS_TALL * PX_PER_POINT))
    (f, w), = base.worlds(anim, joints, [frame])
    Q = base.skin(w)
    normals = character.vertex_normals(Q.astype(np.float32), base.faces).astype(np.float64)
    out = []
    for v in views:
        M = preview.VIEWS[v]
        proj = base.P @ M                    # the bind's projected height sets the scale, the same in every cell
        scale = size / max(float(np.ptp(proj[:, 1])), 1e-6)
        width = int(round(size * 0.66))
        height = int(round(size * 1.18))
        baseline = 0.08 * height - float(proj[:, 1].min()) * scale     # the bind's lowest point 8% up
        out.append(preview.render_view(Q, normals, base.faces, base.c.uvs, tex, v, scale, baseline, width, height,
                                       True))
    return out


# ---------------------------------------------------------------------------
# Choosing a family's stance
# ---------------------------------------------------------------------------

def stance_path(family, bundle=APP_BUNDLE):
    return Path(bundle) / f"{family}_idle_combat.usdz"


def already_ready(family, bundle):
    """Whether the stance in `bundle` is a ready stance already, by the
    family's cut report (motion_palette.report_path: Art/Motions/shipped for
    the app's bundle, <family>.palette.json beside a scratch one)."""
    rp = mp.report_path(bundle, family)
    if not rp.exists():
        return False
    return str(json.loads(rp.read_text()).get("idle_combat", {}).get("preset", "")).startswith("ready")


def load(family, bundle=None, fresh=False):
    """(rig, base, carrier, today's stance anim) for a family: the carrier is
    the stance in `bundle` (the app's by default) itself (it binds as the base
    does), which must be the GUARD - raw, or stood half or fully up - since the
    guard is recovered from it. Since the ship of 2026-09-25 the app's bundle
    holds the ready stances themselves, so a survey or a board reads a bundle
    `motion_palette.py ship` has just written the guard into; `fresh` (the
    ship, called right after that) skips the report's check."""
    bundle = Path(bundle or APP_BUNDLE)
    carrier, cpath, bpath = ni.carrier_for(family, bundle)
    if cpath != bundle / f"{family}_idle_combat.usdz":
        raise ValueError(f"{family}: the stance {family}_idle_combat.usdz does not bind as the base does")
    if not fresh and already_ready(family, bundle):
        raise ValueError(f"{family}: the stance in {bundle} is a ready stance already (its cut report says so), "
                         f"not the guard: survey a bundle `motion_palette.py ship` has written the guard into")
    base = ni.Base(bpath)
    rig = ni.Rig(carrier, base.c)
    today = {k: (np.asarray(v, float) if k != "fps" else v) for k, v in carrier.anim.items()}
    return rig, base, carrier, today


def short(m):
    """The facts of a measured candidate worth keeping."""
    keys = ("over3", "over2", "max", "through", "through_held", "floor_mm", "sink_mm", "drift_mm", "arm_l", "arm_r",
            "hip_tilt", "weight", "fails")
    return {k: m[k] for k in keys if k in m}


def pick_of(cands, today_over3):
    """The candidate a recipe keeps: of those that pass every guard and tear
    no more than today, the most guard (arm_keep) among the ones within the
    slack of the least tear - tear first, then an arm clear of the body (a
    stance may keep the arm points in the body today's has, but one that
    keeps under natural_idle's ARM_COUNT wins: Serqet's daggers), then the
    readiest arms it costs nothing to keep; with none at or under today, the
    one that tears least."""
    ok = [c for c in cands if not c["m"]["fails"]]
    if not ok:
        return None
    within = [c for c in ok if c["m"]["over3"] <= today_over3]
    if within:
        low = min(c["m"]["over3"] for c in within)
        near = [c for c in within if c["m"]["over3"] <= low + slack(today_over3)]
        return max(near, key=lambda c: (c["m"]["through"] + c["m"]["through_held"] <= ni.ARM_COUNT,
                                        round(c["facts"]["arm_keep"], 3), -c.get("level", 0),
                                        -c["facts"].get("arm_out", 0), -c["m"]["over3"]))
    return min(ok, key=lambda c: (c["m"]["over3"], -c["facts"]["arm_keep"]))


def slack(today_over3):
    """The tear two candidates may differ by and still count as a tie: a
    tenth of today's count, at least 5 edges and at most SLACK_CAP (a
    torn family's tenth would buy 125 edges for a readier arm: Bellona)."""
    return max(5, min(SLACK_CAP, int(0.10 * today_over3)))


SLACK_CAP = 30


def choose(family, rows=None, verbose=False, keep_anims=True, bundle=None, guard=None, fresh=False):
    """Both recipes searched and measured; the family's pick and the facts.
    The guard is read off the stance in `bundle` (the app's by default), in
    the form the plan dealt it or `guard` (89, half, stand)."""
    t0 = time.time()
    rows = rows or plan_rows()
    stance, kind = rows[family]
    stance = guard or stance
    arch = mp.archetype(family)
    rig, base, carrier, today_anim = load(family, bundle, fresh)
    today = measure(base, rig, today_anim)
    sink_ok = today["sink_mm"] + 0.5
    through_ok = today["through"] + today["through_held"]
    guard = Guard(rig, guard_for(family, carrier, stance))
    judged = JUDGED.get(family, {})
    natural_arms = judged.get("arms") == "natural"
    k0 = ARM_KEEP[kind]
    out = dict(family=family, stance=stance, kind=kind, archetype=arch, height=round(rig.height, 3),
               today=dict(short(today), **motion_facts(rig, today_anim)), guard=guard.facts(), a=[], b=[])
    anims = {}

    def run(tag, anim, facts, level=0):
        m = measure(base, rig, anim, sink_ok=sink_ok, through_ok=through_ok)
        c = dict(tag=tag, facts=facts, level=level, m=short(m))
        out[tag[0]].append(c)
        if keep_anims:
            anims[(tag, facts["arm_keep"], level, facts.get("arm_out", 0.0))] = anim
        if verbose:
            print(f"  {family} {tag} keep {facts['arm_keep']:.2f} level {level}: past3x {m['over3']} ({m['max']}x) "
                  f"{'; '.join(m['fails'])}", file=sys.stderr)
        return c

    # (a) the guard's motion over a moved mean; at levels 1 and 2 where
    # nothing at the level before tore no more than today
    def under(tag):
        """Done at this level: something passes, tears no more than today
        and no more than LEVEL_ENOUGH edges (a level further stands taller)."""
        return any(not c["m"]["fails"] and c["m"]["over3"] <= min(today["over3"], LEVEL_ENOUGH) for c in out[tag])
    for level in LEVELS:
        if level and under("a"):
            break
        for step in ARM_STEPS:
            anim, facts = recipe_a(rig, guard, k0 * step, guard_row(family, level))
            run("a", anim, facts, level=level)
    # (b) the synthesised stance with the guard's arms; an arm the guard
    # finds in the body swings out ARM_OUT degrees at a time; where nothing
    # tears no more than today, the stance squared (the blade and the stride
    # mostly taken out) is tried as well
    def b_pass(level):
        p = ready_params(family, rig, natural_arms, square=float(level))
        for step in ((1.0,) if natural_arms else ARM_STEPS):
            for out_deg in (0.0,) + ARM_OUT:
                anim, facts = recipe_b(rig, guard, p, STAND_B, k0 * step, arms_natural=natural_arms, arm_out=out_deg)
                facts["arms"] = "natural" if natural_arms else "guard"
                c = run("b", anim, facts, level=level)
                if not any(f.startswith("arm through") for f in c["m"]["fails"]):
                    break
    for level in LEVELS:
        if level and under("b"):
            break
        b_pass(level)
    pa, pb = pick_of(out["a"], today["over3"]), pick_of(out["b"], today["over3"])
    out["pick_a"], out["pick_b"] = pa, pb
    ok = [c for c in (pa, pb) if c is not None and c["m"]["over3"] <= today["over3"]]
    if judged.get("keep"):
        chosen, why = None, judged["keep"]
    elif not ok:
        chosen = None
        best = min([c for c in (pa, pb) if c is not None], key=lambda c: c["m"]["over3"], default=None)
        why = (f"both recipes tear more than today's {today['over3']}: the best {best['tag']} {best['m']['over3']}"
               if best else "no candidate passed the guards")
    elif judged.get("prefer") and any(c["tag"] == judged["prefer"] for c in ok):
        chosen = next(c for c in ok if c["tag"] == judged["prefer"])
        why = f"judged: {judged.get('note', 'the board')}"
    else:
        low = min(ok, key=lambda c: c["m"]["over3"])
        ties = [c for c in ok if c["m"]["over3"] <= low["m"]["over3"] + slack(today["over3"])]
        prefer = TIE_PREFER.get(arch, "a")
        chosen = max(ties, key=lambda c: (c["tag"] == prefer, round(c["facts"]["arm_keep"], 2), -c["m"]["over3"]))
        other = [c for c in ok if c is not chosen]
        why = ("tears least" if chosen is low else
               f"within the slack of the least, and the {arch}'s stance ({'the guard crouch' if prefer == 'a' else 'standing tall'})")
        if other:
            why += f" ({chosen['tag']} {chosen['m']['over3']} against {other[0]['tag']} {other[0]['m']['over3']})"
    out["chosen"] = chosen["tag"] if chosen else None
    out["why"] = why
    if chosen is not None:
        key = (chosen["tag"], chosen["facts"]["arm_keep"], chosen["level"], chosen["facts"].get("arm_out", 0.0))
        out["chosen_motion"] = motion_facts(rig, anims[key]) if keep_anims else None
    out["seconds"] = round(time.time() - t0, 1)
    out["_anims"] = anims
    out["_rig"] = rig
    return out


# ---------------------------------------------------------------------------
# Writing
# ---------------------------------------------------------------------------

def write_stance(family, rig, anim, out_dir, against=None, ship=False):
    """The stance written as <family>_idle_combat.usdz in `out_dir`, re-read
    by character.verify, its bind checked against the shipped base and its
    tear measured by clip_fix.clip_stretch against the stance it replaces
    (the one in `against`, the app's bundle by default). A survey never
    writes the app's bundle; `ship` (the derivation after a re-ship, over the
    guard just written there) may. Returns (problems, facts)."""
    import shutil
    import tempfile
    import clip_fix
    out_dir = Path(out_dir)
    against = Path(against or APP_BUNDLE)
    if out_dir.resolve() == APP_BUNDLE.resolve() and not ship:
        raise SystemExit("ready_stance's survey writes to scratch only; `ship` writes a bundle")
    out_dir.mkdir(parents=True, exist_ok=True)
    work = Path(tempfile.mkdtemp(prefix="ready_stance_", dir=None if ship else str(out_dir)))   # never inside a bundle
    try:
        c = copy.copy(rig.c)
        c.anim = anim
        c.name = family
        made = work / f"{family}_idle_combat.usdz"
        ni.quiet(character.write_usdz, c, made)
        facts = ni.quiet(character.verify, made, check_bounds=False, quiet=True)
        problems = [f"{made.name}: {x}" for x in facts["problems"] if not x.startswith("feet at")]
        if (against / f"{family}.usdz").exists():
            (work / f"{family}.usdz").symlink_to((against / f"{family}.usdz").resolve())
        problems += mp.bind_against_base(work, family, ["idle_combat"])
        base_path = against / f"{family}.usdz"
        if not base_path.exists():
            base_path = APP_BUNDLE / f"{family}.usdz"
        new = ni.quiet(clip_fix.clip_stretch, str(base_path), str(made))
        old = ni.quiet(clip_fix.clip_stretch, str(base_path), str(stance_path(family, against)))
        if new["over3"] > old["over3"]:
            problems.append(f"{made.name}: {new['over3']} edges past 3x against today's {old['over3']} (clip_fix.clip_stretch)")
        info = dict(official=new, today_official=old, kb=round(made.stat().st_size / 1024), keys=len(anim["T"]),
                    fps=anim["fps"])
        lod = against / f"{family}_lod.usdz"
        if not lod.exists():
            lod = APP_BUNDLE / f"{family}_lod.usdz"
        if lod.exists():           # the mesh a battle draws (clip_fix.clip_stretch reads the LOD's own skin)
            info["lod"] = ni.quiet(clip_fix.clip_stretch, str(lod), str(made))
            info["today_lod"] = ni.quiet(clip_fix.clip_stretch, str(lod), str(stance_path(family, against)))
        if not problems:
            shutil.copyfile(made, out_dir / made.name)
        return problems, info
    finally:
        shutil.rmtree(work, ignore_errors=True)


def process(family, out=None, verbose=False, bundle=None, guard=None, ship=False):
    try:
        r = choose(family, verbose=verbose, bundle=bundle, guard=guard, fresh=ship)
    except Exception as e:  # noqa: BLE001 - one family must not stop the roster
        import traceback
        return dict(family=family, error=f"{e!r}", trace=traceback.format_exc()[-1500:])
    anims, rig = r.pop("_anims"), r.pop("_rig")
    if out and r["chosen"]:
        c = r["pick_" + r["chosen"]]
        anim = anims[(c["tag"], c["facts"]["arm_keep"], c["level"], c["facts"].get("arm_out", 0.0))]
        problems, info = write_stance(family, rig, anim, out, against=bundle, ship=ship)
        r["written"] = not problems
        r["write"] = info
        if problems:
            r["write_problems"] = problems
    return r


def _proc(args):
    f, out, verbose, bundle = args
    r = process(f, out, verbose, bundle)
    print(line(r), file=sys.stderr, flush=True)
    return r


def line(r):
    if r.get("error"):
        return f"{r['family']:20s} ERROR {r['error']}"
    t = r["today"]

    def cand(c):
        if c is None:
            return "-"
        return f"{c['m']['over3']}@{c['facts']['arm_keep']:.2f}{'n' if c.get('level') else ''}"
    ch = r["chosen"] or "today"
    w = r.get("write", {}).get("official", {})
    return (f"{r['family']:20s} {r['stance']:5s} {r['kind']:7s} {r['archetype']:9s} today {t['over3']:5d} ({t['max']}x)"
            f"  a {cand(r['pick_a']):>10s}  b {cand(r['pick_b']):>10s}  -> {ch:5s}"
            f"{'  written ' + str(w.get('over3')) if r.get('written') else ''}"
            f"{'  PROBLEMS ' + '; '.join(r['write_problems']) if r.get('write_problems') else ''}  {r['why']}")


def cmd_survey(a):
    rows = plan_rows()
    fams = a.families or sorted(rows)
    t0 = time.time()
    args = [(f, a.out, a.verbose, a.bundle) for f in fams]
    if a.jobs > 1 and len(fams) > 1:
        from multiprocessing import Pool
        with Pool(a.jobs) as pool:
            results = pool.map(_proc, args, chunksize=1)
    else:
        results = [_proc(x) for x in args]
    for r in results:
        print(line(r))
    good = [r for r in results if not r.get("error")]
    today = sum(r["today"]["over3"] for r in good)

    def after(r):
        if r["chosen"] and (not a.out or r.get("written")):
            return r["pick_" + r["chosen"]]["m"]["over3"]
        return r["today"]["over3"]
    new = sum(after(r) for r in good)
    chosen = {k: [r["family"] for r in good if r["chosen"] == k] for k in ("a", "b")}
    kept = [r["family"] for r in good if not r["chosen"]]
    print(f"\n{len(results)} families in {time.time() - t0:.0f} s: (a) {len(chosen['a'])}, (b) {len(chosen['b'])}, "
          f"left as they are {len(kept)} {kept}")
    print(f"edges past 3x on their stances: today {today} -> {new}")
    errs = [r for r in results if r.get("error")]
    for r in errs:
        print(f"ERROR {r['family']}: {r['error']}\n{r['trace']}")
    if a.json:
        Path(a.json).write_text(json.dumps(results, indent=1, default=str))
        print("facts ->", a.json)
    return 1 if errs else 0


def rebuild(family, cand, rig, guard, rows=None):
    """A candidate's stance made again from its facts (the recipes are
    deterministic in the family, the arm share and the feet level)."""
    if cand is None:
        return None
    keep = cand["facts"]["arm_keep"]
    if cand["tag"] == "a":
        return recipe_a(rig, guard, keep, guard_row(family, cand.get("level", 0)))[0]
    natural = cand["facts"].get("arms") == "natural"
    return recipe_b(rig, guard, ready_params(family, rig, natural, square=float(cand.get("level", 0))), STAND_B, keep,
                    arms_natural=natural, arm_out=cand["facts"].get("arm_out", 0.0))[0]


def cmd_board(a):
    """Sheets of families at battle distance: per family today's stance, (a)
    and (b) from behind as the camera sees the team, then the three from the
    front as it sees the enemies, each at a quarter of its loop; the chosen
    one framed in gold."""
    import preview
    from PIL import Image, ImageDraw
    results = {r["family"]: r for r in json.loads(Path(a.json).read_text()) if not r.get("error")}
    fams = a.families or sorted(results)
    views = battle_views()
    rows = plan_rows()
    out_dir = Path(a.out)
    out_dir.mkdir(parents=True, exist_ok=True)
    blocks = []
    for fam in fams:
        r = results[fam]
        rig, base, carrier, today = load(fam, a.bundle)
        guard = Guard(rig, guard_for(fam, carrier, rows[fam][0]))
        tex = preview.base_colour(base.c)
        cols = []
        for tag, anim in (("today", today), ("a", rebuild(fam, r["pick_a"], rig, guard)),
                          ("b", rebuild(fam, r["pick_b"], rig, guard))):
            if anim is None:
                cols.append((tag, None))
                continue
            n = len(anim["T"]) - 1
            cols.append((tag, render_pose(base, anim, carrier.joints, n // 4, views, tex)))
        blocks.append((fam, r, cols))
    cw, ch = next(c[1][0].size for b in blocks for c in b[2] if c[1] is not None)
    lab = 34
    for k in range(0, len(blocks), a.per_sheet):
        part = blocks[k:k + a.per_sheet]
        sheet = Image.new("RGB", (6 * cw + 16, 26 + len(part) * (ch + lab)), (24, 24, 28))
        d = ImageDraw.Draw(sheet)
        d.text((6, 5), "Ready stances at battle distance (a third of a 390-point frame, 2 px a point): today, (a) the "
                       "guard's motion on a moved pose, (b) synthesised with the guard's arms - from behind as the team "
                       "is seen, then from the front as the enemies are; the chosen framed in gold",
               fill=(160, 230, 160), font=preview.font(12))
        for i, (fam, r, cols) in enumerate(part):
            y = 26 + i * (ch + lab)
            chosen = r["chosen"] or "today"
            for vi in range(2):
                for ci, (tag, imgs) in enumerate(cols):
                    x = 4 + (vi * 3 + ci) * cw + (8 if vi else 0)
                    if imgs is None:
                        continue
                    sheet.paste(imgs[vi], (x, y))
                    if tag == chosen:
                        d.rectangle([x, y, x + cw - 1, y + ch - 1], outline=(235, 190, 60), width=3)
                    c = r["today"] if tag == "today" else r["pick_" + tag]
                    m = c if tag == "today" else c["m"]
                    txt = f"{tag} {m['over3']}" + ("" if tag == "today" else f" arms {c['facts']['arm_keep']:.2f}")
                    d.text((x + 3, y + 2), txt, fill=(30, 30, 30), font=preview.font(12))
            d.text((6, y + ch + 2), f"{fam} ({r['stance']}, {r['kind']}, {r['archetype']}): {chosen} - {r['why']}"[:170],
                   fill=(240, 220, 150), font=preview.font(13))
            mot = r.get("chosen_motion") or r["today"]
            d.text((6, y + ch + 18), f"today's loop {r['today']['loop_s']} s, bob {r['today']['bob_cm']} cm; chosen "
                                     f"loop {mot['loop_s']} s, bob {mot['bob_cm']} cm, sway {mot['sway_cm']} cm, chest "
                                     f"{mot['chest_deg']} deg, head {mot['head_deg']} deg",
                   fill=(200, 200, 200), font=preview.font(12))
        path = out_dir / f"ready_{k // a.per_sheet + 1:02d}.jpg"
        sheet.save(path, quality=84)
        print(f"board -> {path} ({', '.join(b[0] for b in part)})")


def cmd_ship(a):
    """The derivation after a re-ship (motion_palette.py ship, build_asset.sh,
    proportions.sh): the stance just written into --bundle is the guard (in
    the plan's form, or --guard's), the chosen ready stance is written over it
    after every guard and the tear rule, and where nothing is chosen or the
    written file fails, the guard stays - loudly (READY STANCE REFUSED), as
    the idle falls back to the stood guard. A family the plan gives another
    stance (the calm 35's natural idle, 85's tail, Skadi's draw) or none is
    left alone."""
    rows = plan_rows()
    bundle = Path(a.bundle)
    refused = 0
    for fam in a.families:
        if fam not in rows:
            print(f"{fam:20s} no ready stance in the plan: the stance in the bundle stays")
            continue
        if not (bundle / f"{fam}_idle_combat.usdz").exists():
            print(f"READY STANCE REFUSED for {fam}: no {fam}_idle_combat.usdz in {bundle} to read the guard from")
            refused += 1
            continue
        r = process(fam, out=str(bundle), bundle=str(bundle), guard=a.guard, ship=True)
        print(line(r))
        if r.get("error") or not r.get("written"):
            why = r.get("error") or "; ".join(r.get("write_problems") or []) or r.get("why", "")
            print(f"READY STANCE REFUSED for {fam}: {why}; the guard stance stays")
            refused += 1
    return 1 if refused else 0


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    s = sub.add_parser("survey", help="both recipes searched for every family; with --out, the chosen written there")
    s.add_argument("families", nargs="*")
    s.add_argument("--out", help="write each chosen stance here as <family>_idle_combat.usdz (scratch; never the bundle)")
    s.add_argument("--json")
    s.add_argument("--jobs", type=int, default=3)
    s.add_argument("--verbose", action="store_true")
    s.add_argument("--bundle", help="read the guard stances from here (default: the app's bundle, which holds the "
                                    "ready stances since 2026-09-25 - a survey reads a bundle ship wrote the guard into)")
    s.set_defaults(fn=cmd_survey)
    b = sub.add_parser("board", help="today, (a) and (b) at battle distance, from a survey's --json and --out")
    b.add_argument("families", nargs="*")
    b.add_argument("--json", required=True)
    b.add_argument("--out", required=True, help="the board folder")
    b.add_argument("--per-sheet", type=int, default=8)
    b.add_argument("--bundle", help="where the guard stances are (as survey's)")
    b.set_defaults(fn=cmd_board)
    w = sub.add_parser("ship", help="the ready stance written over the guard just shipped into --bundle (a re-ship's "
                                    "derivation); refused, the guard stays")
    w.add_argument("families", nargs="+")
    w.add_argument("--bundle", required=True)
    w.add_argument("--guard", choices=STANCES, help="the form of the guard in the bundle (default: the plan's; "
                                                    "mesh.py ships Meshy's raw 89)")
    w.set_defaults(fn=cmd_ship)
    a = ap.parse_args()
    sys.exit(a.fn(a) or 0)


if __name__ == "__main__":
    main()
