#!/usr/bin/env python3
"""The natural standing idle: each family's stage idle built from its OWN
BIND POSE, in its archetype's way of standing (Docs/PLAN.md, *Natural poses*,
build step 1; 2026-09-24).

Every figure on the island, the reveal, the Hall of Ka's altar and the
collection's Stage stood in tools/stand_idle.py's derivation of Meshy's
combat guard: the same near-A-pose (the arms kept at 85% of the guard, an
invisible shield in 106 of 117), the same 1.27 s pant, level hips and the
weight centred, and the guard's arms tore the cloth welded to them (22,202
edges past 3x over the roster). The rigs' own binds hang the arms 22 degrees
out with a soft elbow, because the concepts were painted that way for the
rigger, so an idle built from the bind can bring the arms down safely.

What this writes, per family, on the family's shipped carrier (no root lock,
so the hips keep their sway and the feet stay planted):
  contrapposto  the weight on the leg opposite the weapon hand
                (motion_palette.WEAPON_HAND, Polykleitos's chiasm): the pelvis
                over the standing foot (`weight`, a share of the way between
                the feet), rolled up there, the standing foot drawn in toward
                the midline, the spine counter-rolled so the shoulders tilt
                against the hips, the head turned toward the standing side;
                both sides are tried and the chiastic one is kept unless the
                other tears less;
  the feet      planted by two-bone IK (the knee on its bind pole), the free
                foot a little ahead and turned OUT (the prototype turned it
                in); a leg the bind holds bent (a hoof, a paw: the Minotaur's
                and Bes's at 0.70 of their length) is never straightened;
  the arms      the bind's hang, then the archetype's (a mystic's hands low
                before the waist, a brute's held off the body, a beast's
                claws out), a bind wider than 26 degrees brought down
                (`arm_down`), following the chest a beat late; the standing
                side's arm swings out as far as its hip comes out under it,
                and an arm the guard finds in the body swings out 3 degrees at
                a time (four times) before the guard refuses it;
  the motion    a breath (inhale 40%, exhale 60%), a sway, the head's survey
                and glances, a brute's neck roll, a trickster's off-beat
                hitch, a construct's settle and stiff twitch, a giant's breath
                slower by the square root of its size - every one a whole
                number of cycles in the loop, which is written as F+1 keys
                with the last equal to the first (SceneKit's loop is its last
                key's time long, so an F-key loop skipped a frame at every
                wrap).

The archetype (motion_palette.ARCHETYPE; an awakened form takes its
family's) picks the row of STYLES; each number is drawn inside the row's
range from a hash of the family's key, so no two families stand alike.
Joints are found by POSITION in the skeleton, never by name (`Rig`): eleven
rigs call the joint over the hips `neck`, and the head is the joint the
skull's vertices are skinned to - on those eleven the one named Head1 or
Spine1 (their `Head` is an end marker holding no vertex), on Hephaestus,
Fenrir and Ullr the one named `neck`.

Guards that REFUSE a file (each prints its line in `survey`):
  feet   a foot joint that drifts more than a millimetre over the loop; a
         foot whose lowest point rises off its bind height by more (it leaves
         the floor) or sinks 5 mm into it (a heel skinned half to the shin);
  bind   a carrier whose joints or bind differ from the shipped base's
         (motion_palette.bind_against_base);
  tear   more edges stretched past 3x on the shipped base than the idle it
         replaces (clip_fix.clip_stretch's measure and frames, 24 of them);
  arms   a forearm or a hand pushed INTO the thigh or the trunk below the
         armpits: arm vertices (character._arm_masks' skin) that lie behind
         the posed body's own surface (character._limb_surface's layer) more
         than 1.2% of the height deeper than they lay in the bind;
  loop   a last key that is not the first, or a seam whose step is not like
         the loop's own.
A style's flourishes (the weight right over the foot, the drawn-in stance,
the soft knees, the arms' swing, the mystic's hands, the beast's crouch ...)
are all tried at once; when that tears more than the plain stance (the
bind's arms, near-straight legs) plus FLOURISH_SLACK edges, they are added to
the plain stance one at a time, each whole or at half, and kept while the
tear stays in the slack - the line names the ones held back. A pick that
tears nothing then tries its row's BOLD numbers (the sovereigns' fuller
contrapposto) and keeps them only if they still tear nothing. OVERRIDES holds
the judged odd rests (Fenrir's arms 58 degrees out in the bind, the Jotunn's
heels, the Jiangshi's arms held out, arms brought in where a held-back stance
left them wide, Vidar on the other leg from Tyr, Bastet in the grace row and
Serqet in the champion row on the stages - the beast crouch read as a squat)
and any HELD family, which keeps
today's idle (the guard stood up by tools/stand_idle.py); none is held now.

The weapon (hang_weapons; the judge of 2026-09-25: eleven weapons lay level
at the hip because the bind's grip is kept): a long thing a hand holds
(Base.weapons: the weapon pass's own piece, else the hand's far rows) whose
head the pick holds within LEVEL_DEG of level, with the forearm hanging, is
rested - a pole with a head (a spear, a trident, a guandao) stood up 60-75
degrees, anything else (or a pole that tears standing) hung 30-50 degrees
head down by the thigh, forward and turned up to 40 out - by a
turn at the wrist, at the elbow (a weapon the forearm carries a share of) or
split between the two (half the bend at each: the wrist's crease tore on
Thor at 37 degrees); the rests are tried cheapest first through every guard,
the tear held to the file it replaces, the weapon's lowest point 5% of the
height off the floor and no deeper in the body than it lay in the bind. A
weapon skinned to the thigh or a cloak (the Jotunn's axe, Neptune's trident)
is left as the bind holds it: any turn tears it; that is the weapon pass's
work on the base.

The weight shift (`--alt`, PLAN.md step 5; make_alt): <family>_idle_alt.usdz,
the same idle standing on the OTHER leg on the SAME foot spots, of the same
length and phases, so the two can blend: two players blended move the pelvis
on a straight line while the legs turn on arcs, so the planted feet sink at
the blend's middle - the alt's travel and roll are searched apart and the
most visible shift whose blends at 25, 50 and 75% keep every foot joint
within 3 mm, whose tear is no more than its idle's (the blends' too) and
whose weapon stays out of the body in between is kept; a family whose alt
fails keeps none (`blendcheck` re-reads the written pairs).

    python3 tools/natural_idle.py survey [families...] [--jobs 3] [--json out.json] [--bundle DIR]
    python3 tools/natural_idle.py board hera freya --out DIR [--bundle DIR]
    python3 tools/natural_idle.py sheet sovereign --out sovereign.jpg [--bundle DIR]
    python3 tools/natural_idle.py gif zeus hera --out DIR [--bundle DIR]
    python3 tools/natural_idle.py ship hera freya --bundle DIR [--also-combat]
    python3 tools/natural_idle.py ship --all --bundle Pantheon/Resources/Models --calm-stances --alt   # as shipped 2026-09-25
    python3 tools/natural_idle.py survey --bundle DIR --calm-stances --alt --json out.json      # the idles, stances and alts
    python3 tools/natural_idle.py blendcheck --bundle DIR [families...] [--json out.json]        # the written pairs blended
    python3 tools/natural_idle.py altboard ares hades --bundle DIR --out DIR                     # an idle, its alt, their blend

`survey` measures every family (today's idle against the natural one) and,
with --bundle, writes the files as `ship` does. `ship` never writes without
--bundle naming the folder; each file is made in a work folder, re-read by
character.verify, and the guards are run again on the WRITTEN file
(clip_fix.clip_stretch against the files it replaces, measured before
anything is overwritten, and motion_palette.bind_against_base); only a file
that passes is copied into the bundle. `--calm-stances` writes the same file
as `<family>_idle_combat.usdz` for the families motion_palette's plan stands
calm in battle (`idle_combat=natural`: the 35 sovereigns, graces and mystics
among the `stand` families); `--alt` writes the weight-shift variant beside
the idle, through the same checks, and removes a stale one. A held family is
surveyed and boarded with its `retry` laid on and never written; `ship` keeps
its idle, or makes today's again if a re-shipped base left it binding off. `ship` exits 1 when a family
is refused (the batch scripts then stand the guard up instead, loudly).
Every loop is written at FPS keys a second (`--fps`).
"""
import argparse
import contextlib
import copy
import hashlib
import io
import json
import math
import sys
import time
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
import character  # noqa: E402
from character import decompose, quat_to_rot, rot_to_quat, trs, world_from_local  # noqa: E402
import motion_palette as mp  # noqa: E402

REPO = Path(__file__).resolve().parents[1]
APP_BUNDLE = REPO / "Pantheon" / "Resources" / "Models"
# Keys a second (`--fps`). 20, not the clips' 30 (2026-09-25): at 30 the
# roster's idles and the 35 calm stances added 22.8 MB to the bundle against
# the plan's 16, and nothing in a loop needs more - a 4 s breath gets 80 keys a
# cycle, the construct's 0.07 s twitch still lands on a key, and SceneKit
# interpolates between them. 15 is the fallback if `[Mem]` climbs.
FPS = 20.0
X, Y, Z = np.eye(3)

# Totals the survey is judged against (Docs/PLAN.md, *Natural poses*):
# edges past 3x over the 117 shipped standing idles, and over the prototype's.
TODAY_TOTAL = 22202
PROTOTYPE_TOTAL = 1005

# The guards' limits.
FOOT_DRIFT = 0.001            # m: a foot joint's travel over the loop
FLOOR_DRIFT = 0.001           # m: a foot's lowest point risen off its bind height (it leaves the floor)
FLOOR_SINK = 0.005            # m (for a 1.9 m figure; a giant in proportion): ... or sunk into it (a heel
                              # skinned half to the shin dips as the shin leans)
ARM_DEPTH = 0.012             # share of the height: an arm vertex this far behind the body surface is THROUGH it
ARM_COUNT = 12                # vertices through the body at one frame before the file is refused
FLOURISH_SLACK = 5            # edges past 3x a flourish may add over the plain stance
WEAPON_FIST = 0.09            # share of the height: a hand's rows further than this from the wrist are past the fist
WEAPON_MIN = 0.25             # share of the height: a held thing shorter than this is no weapon to hang (a dagger)
# The weapon's hang (hang_weapons; the judge of 2026-09-25: eleven weapons held
# level at the hip because the bind's grip is kept - a blade 30-50 degrees tip
# down, a pole raised to 60-75 like Pluto's and Frigg's)
LEVEL_DEG = 25.0              # a held weapon's head within this of level is held LEVEL (the eleven: -3 to -20)
HANG_FOREARM = -35.0          # ... at the hip: the forearm hanging at least this far below level
HANG_HAND = 0.62              # ... and the hand below this share of the height (Osiris's crook across the chest is not)
HANG_EL = (-50.0, -45.0, -40.0, -35.0, -30.0)   # the head's elevation a hung blade is tried at
STAND_EL = (75.0, 70.0, 65.0, 60.0)             # ... and a stood pole
POLE_LEN = 0.5                # share of the height: a thing gripped between its ends this long, with a head, stands
HEAD_RATIO = 1.25             # ... its head end this much wider round the axis than its butt (a bolt has no head)
WRIST_SWING = 40.0            # degrees a hand may bend off the forearm's line (flexion, deviation)
WRIST_TWIST = 100.0           # ... and turn about it (pronation: a fist hides it)
ELBOW_MAX = 115.0             # degrees a forearm turned at the elbow may bend off the upper arm
WEAPON_FLOOR = 0.05           # share of the height a hung weapon's lowest point keeps off the floor
WEAPON_INSIDE = 6             # rows of a hung weapon allowed deeper in the body than they lay in the bind
CARRIED_MIN = 0.9             # the share of a weapon's rows its pivot must carry (half or more of each row's weight)
HANG_TRIES = 20               # rests tried through the guards, cheapest first (6 missed the smith's)
SPLIT = 0.5                   # the share of a split rest's turn made at the elbow

# ---------------------------------------------------------------------------
# The styles: one row per archetype (motion_palette.ARCHETYPE)
# ---------------------------------------------------------------------------
# A number is a fixed value, a pair (lo, hi) a range the family's hash draws
# inside. Angles in degrees, lengths as shares of the figure's height (the
# head joint over the feet), times in seconds.
#   weight      where the pelvis stands between the feet: 0.5 centred, 1.0
#               over the standing foot (the bind's own pelvis sits anywhere)
#   stand_in    the standing foot drawn this share of the way to the midline
#               (a relaxed stance is narrower than the rigger's shoulder width)
#   roll        the pelvis rolled up over the standing leg
#   hip_yaw     the pelvis turned so the free hip comes forward
#   blade       the pelvis AND the chest turned with it (the hunter's bladed torso)
#   counter     the spine's counter-roll, times the pelvis's roll (the S-line)
#   twist       the chest turned back against the pelvis
#   lean        the spine leaned forward (negative: back, the chest lifted)
#   chin        the head raised (negative: lowered)
#   head_turn   the head turned toward the standing side
#   head_tilt   the head tilted toward the standing side (tilt_flip: the other way)
#   head_face   the share of the torso's turn the head takes back to face the lens
#   neck_steady the share of the chest's roll the neck takes back out
#   period      one breath; `breaths` of them make the loop
#   breath      the spine's breath (the chest lifting), clav the clavicles'
#   clav_fwd    the shoulders rolled forward (negative: back)
#   sway        the lateral sway, one cycle a loop; fore_sway the fore-aft, two
#   bob         the pelvis lifted with the breath (a mystic's float)
#   settle      a slow sink and rise, one a loop (a construct has no breath)
#   survey      the head's slow look along the field, one cycle a loop, held at
#               its ends by survey_k (tanh(k sin)/tanh(k))
#   glance      quicker looks, glance_n a loop, held by glance_k
#   nod         the head's pitch drift, two a loop; bob_head a beast's sniff at the breath's rate
#   neck_roll   the head circling, one a loop (a brute's neck roll)
#   hitch       an off-beat pop of the hip, a share of the contrapposto (a trickster)
#   twitch      a construct's stiff jerk of the head, degrees of yaw
#   arm_in      the upper arm swung toward the body from the bind (negative: away)
#   arm_down    the share of a bind's hang past HANG_TARGET taken back (Fenrir's 58 degrees, Horus's 40)
#   arm_fwd     the upper arm swung forward
#   elbow       the elbow bent further, the forearm forward
#   free_*      the same for the arm that holds nothing (the one opposite the weapon hand)
#   follow, lag the arms follow this share of the chest this long late
#   reach       the standing leg's reach (0.985: straight but not locked); reach_free the free leg's
#   step        the free foot ahead of its bind spot; turn_out its toes turned out
#   narrow      both feet drawn this share of the way toward each other (a mystic)
#   tempo       the breath's rate against the row's (a giant's is slower still)
# `flourish` names the values the PLAIN stance uses in their place (BASE's
# and the row's): the family is tried with the flourishes whole, at half and
# plain, and keeps the most it can while tearing no more than the plain
# stance plus FLOURISH_SLACK edges.
BASE = dict(weight=(0.64, 0.70), stand_in=(0.22, 0.32), roll=(3.5, 4.5), hip_yaw=(1.2, 1.8), blade=0.0,
            counter=(1.5, 1.7), twist=(3.5, 4.5), lean=(-0.5, 0.5), chin=(-0.5, 1.0), head_turn=(5.0, 7.0),
            head_tilt=(1.5, 2.5), tilt_flip=False, head_face=0.0, neck_steady=0.7, period=(3.8, 4.1), breaths=2,
            breath=(1.3, 1.6), clav=(1.3, 1.7), clav_fwd=0.0, sway=(0.0035, 0.0045), fore_sway=(0.0015, 0.0025),
            bob=0.0015, settle=0.0, survey=(2.5, 3.5), survey_k=1.0, glance=0.0, glance_n=3, glance_k=2.0,
            nod=(0.8, 1.2), bob_head=0.0, neck_roll=0.0, hitch=0.0, hitch_at=(0.55, 0.7), twitch=0.0,
            twitch_at=(0.3, 0.8), arm_in=(5.0, 8.0), arm_fwd=(0.0, 2.5), elbow=(6.0, 10.0), follow=(0.55, 0.65),
            lag=(0.22, 0.30), reach=0.985, reach_free=0.97, step=(0.011, 0.015), turn_out=(7.0, 10.0), narrow=0.0,
            tempo=1.0, arm_down=(0.7, 0.9))
# the plain stance: the bind's own arms and nearly its straight legs (a kilt
# skinned to both thighs stretches as either knee bends: Horus 128 -> 71)
BASE_FLOURISH = dict(weight=0.57, stand_in=0.0, arm_in=0.0, arm_fwd=0.0, elbow=0.0, arm_down=0.0, reach=0.995,
                     reach_free=0.99)
HANG_TARGET = 26.0     # degrees: a bind that hangs its arms further out than this brings them down by `arm_down` of the excess

STYLES = {
    # Stillness is power: upright, the chest lifted, the chin up a touch, the
    # weight settled on one leg; one slow breath every 4.4-5 s and a slow
    # survey of the field, held at its ends; no bounce (the prototype's regal).
    "sovereign": dict(weight=(0.62, 0.68), roll=(3.0, 4.0), hip_yaw=(1.0, 1.8), twist=(2.5, 3.5),
                      lean=(-2.0, -1.0), chin=(2.0, 4.0), head_turn=(3.0, 5.0), head_tilt=(0.5, 1.5),
                      period=(4.4, 5.0), breath=(1.0, 1.3), clav=(1.0, 1.4), sway=(0.0025, 0.0035),
                      survey=(5.0, 8.0), survey_k=2.2, nod=(0.6, 1.0), arm_in=(4.0, 7.0), arm_fwd=(0.0, 2.0),
                      elbow=(4.0, 7.0), step=(0.010, 0.014), turn_out=(6.0, 9.0)),
    # Athletic readiness at rest: knees soft, the chest open, quick glances
    # (the prototype's warrior); the bounce belongs to the battle's stance.
    "champion": dict(weight=(0.64, 0.70), roll=(4.0, 5.0), reach=0.98, glance=(3.0, 5.0), glance_n=3,
                     glance_k=2.5, step=(0.012, 0.016), turn_out=(7.0, 11.0)),
    # At ease: square, the chest out and the shoulders back, the breath shown
    # in the shoulders, the head level and still but for a look now and then.
    "soldier": dict(weight=(0.56, 0.62), stand_in=(0.10, 0.18), roll=(2.0, 3.0), twist=(1.5, 2.5),
                    lean=(-1.5, -0.5), chin=(0.0, 1.5), head_turn=(1.5, 3.0), head_tilt=(0.3, 1.0),
                    period=(3.8, 4.2), breath=(1.2, 1.5), clav=(1.8, 2.4), clav_fwd=(-2.0, -1.0),
                    sway=(0.002, 0.003), survey=(1.5, 2.5), glance=(2.0, 3.0), glance_n=2, glance_k=3.0,
                    nod=(0.4, 0.8), arm_in=(2.0, 4.0), arm_fwd=(1.0, 3.0), elbow=(8.0, 12.0), reach=0.99,
                    reach_free=0.975, step=(0.004, 0.008), turn_out=(4.0, 7.0),
                    flourish=dict(weight=0.54)),
    # Mass: a wide base with the knees bent, the shoulders rolled forward, the
    # arms hanging off the body, deep heaves and a slow neck roll (the
    # prototype's brute, a little slower: 16-17.6 breaths a minute).
    "brute": dict(weight=(0.58, 0.64), stand_in=0.0, roll=(2.5, 3.5), twist=(4.0, 6.0), lean=(3.5, 5.5),
                  chin=(-4.0, -2.0), head_turn=(4.0, 6.0), head_tilt=(2.0, 3.0), period=(3.4, 3.7),
                  breath=(1.9, 2.4), clav=(2.6, 3.4), clav_fwd=(3.0, 5.0), sway=(0.0045, 0.0055), survey=(2.0, 3.0),
                  nod=(0.8, 1.2), neck_roll=(2.0, 3.0), arm_in=(-3.0, -1.0), arm_fwd=(2.0, 4.0), elbow=(9.0, 13.0),
                  reach=(0.965, 0.975), reach_free=0.955, step=(0.012, 0.016), turn_out=(8.0, 12.0),
                  flourish=dict(weight=0.55, reach=0.985, reach_free=0.97, lean=1.5, clav_fwd=0.0)),
    # Centred calm: the feet closer, the spine tall, the hands low before the
    # waist, a drift like floating, the head still and the eyes lowered.
    "mystic": dict(weight=(0.56, 0.62), stand_in=0.0, roll=(1.5, 2.5), twist=(1.5, 2.5), lean=(-1.0, 0.0),
                   chin=(-3.0, -1.0), head_turn=(1.0, 2.0), head_tilt=(0.5, 1.0), neck_steady=0.9,
                   period=(3.6, 4.0), breath=(1.0, 1.3), clav=(0.8, 1.2), sway=(0.0015, 0.0025),
                   bob=(0.003, 0.0045), survey=(0.8, 1.2), nod=(0.3, 0.6), arm_in=(6.0, 9.0), arm_fwd=(8.0, 14.0),
                   elbow=(28.0, 40.0), narrow=(0.15, 0.25), step=(0.004, 0.008), turn_out=(3.0, 6.0),
                   flourish=dict(weight=0.54, narrow=0.0)),
    # The S-curve: a strong contrapposto, the hip out, the head tilted, a slow
    # sway; the empty hand held a little forward (the prototype's lithe).
    "grace": dict(weight=(0.72, 0.78), stand_in=(0.28, 0.38), roll=(6.0, 7.5), hip_yaw=(1.5, 2.5),
                  twist=(4.5, 6.0), lean=(-1.5, -0.5), chin=(0.5, 1.5), head_turn=(6.0, 9.0), head_tilt=(3.0, 5.0),
                  period=(4.2, 4.6), breath=(1.2, 1.4), clav=(1.2, 1.6), sway=(0.0055, 0.0065), survey=(3.0, 4.0),
                  arm_in=(5.0, 8.0), arm_fwd=(0.0, 2.0), elbow=(8.0, 12.0), free_elbow=(18.0, 26.0),
                  free_arm_fwd=(4.0, 8.0), step=(0.014, 0.018), turn_out=(10.0, 14.0), reach_free=0.965,
                  flourish=dict(free_elbow=None, free_arm_fwd=None, roll=4.0)),
    # Alert economy: the torso bladed with the bow side leading, the weight on
    # the back leg and the lead foot ahead, the face kept to the front, a slow
    # lateral scan broken by a sudden look.
    "hunter": dict(weight=(0.66, 0.72), roll=(3.0, 4.0), blade=(8.0, 11.0), twist=(-3.0, -1.0), lean=(0.5, 1.5),
                   chin=(0.0, 1.0), head_turn=(0.0, 1.0), head_face=(0.6, 0.75), head_tilt=(1.0, 2.0),
                   survey=(5.0, 8.0), survey_k=1.2, glance=(3.0, 5.0), glance_n=2, glance_k=4.0, nod=(0.5, 0.9),
                   arm_fwd=(0.0, 3.0), elbow=(6.0, 10.0), step=(0.030, 0.040), turn_out=(14.0, 20.0),
                   reach_free=0.965,
                   flourish=dict(blade=0.0, twist=4.0, head_face=0.0, head_turn=5.0, step=0.013, turn_out=8.0)),
    # Broken symmetry: the hip cocked, one knee bent, the head tilted 8-12
    # degrees, sideways glances and an off-beat hitch of the hip, 1.1x tempo.
    "trickster": dict(weight=(0.74, 0.80), stand_in=(0.30, 0.40), roll=(6.5, 8.5), hip_yaw=(2.0, 3.0),
                      twist=(4.0, 6.0), lean=(-0.5, 0.5), chin=(0.0, 2.0), head_turn=(4.0, 7.0),
                      head_tilt=(8.0, 12.0), period=(3.5, 3.8), breath=(1.2, 1.5), clav=(1.2, 1.6),
                      sway=(0.005, 0.006), survey=(2.0, 3.0), glance=(6.0, 9.0), glance_n=3, glance_k=3.0,
                      nod=(0.8, 1.2), hitch=(0.25, 0.35), elbow=(8.0, 12.0), step=(0.014, 0.018),
                      turn_out=(12.0, 16.0), reach_free=(0.955, 0.965),
                      flourish=dict(head_tilt=3.0, roll=4.5)),
    # Predatory: a low crouch leaning over the forefeet, the head low and
    # bobbing, the claws held off the body, twitchy head snaps, 1.2x tempo.
    "beast": dict(weight=(0.55, 0.60), stand_in=0.0, roll=(2.5, 3.5), twist=(3.0, 5.0), lean=(8.0, 12.0),
                  chin=(3.0, 6.0), head_turn=(3.0, 5.0), head_tilt=(1.5, 2.5), period=(3.2, 3.5), breath=(1.5, 1.9),
                  clav=(1.5, 2.0), clav_fwd=(2.0, 4.0), sway=(0.004, 0.005), survey=(3.0, 5.0), glance=(5.0, 8.0),
                  glance_n=4, glance_k=5.0, nod=(0.5, 0.8), bob_head=(1.5, 2.5), arm_in=(-7.0, -4.0),
                  arm_fwd=(6.0, 10.0), elbow=(18.0, 26.0), reach=(0.90, 0.93), reach_free=(0.89, 0.92),
                  step=(0.014, 0.020), turn_out=(6.0, 10.0),
                  flourish=dict(weight=0.54, reach=0.975, reach_free=0.96, lean=4.0, chin=0.0, clav_fwd=0.0)),
    # No breath: a construct stands, a corpse rattles - a slow settle and rise
    # once a loop, a stiff jerk of the head, the smallest contrapposto.
    "construct": dict(weight=(0.53, 0.57), stand_in=0.0, roll=(1.0, 2.0), hip_yaw=(0.5, 1.0), twist=(0.5, 1.5),
                      lean=(0.0, 1.0), chin=(-1.0, 1.0), head_turn=(1.0, 2.0), head_tilt=(0.0, 1.0),
                      period=(4.0, 4.6), breath=(0.1, 0.2), clav=(0.1, 0.2), sway=(0.001, 0.002),
                      fore_sway=(0.0005, 0.001), bob=0.0, settle=(0.002, 0.003), survey=(1.0, 2.0), nod=(0.2, 0.4),
                      twitch=(4.0, 6.0), arm_in=(2.0, 4.0), arm_fwd=(0.0, 1.0), elbow=(3.0, 6.0), follow=(0.8, 0.9),
                      lag=(0.05, 0.1), step=(0.004, 0.008), turn_out=(3.0, 5.0),
                      flourish=dict(weight=0.52)),
}

# A bolder row tried AFTER the pick, on a family whose pick tears nothing, and
# kept only if it still tears nothing (the judge of 2026-09-25: at 3-4 degrees
# of hip tilt the sovereigns' contrapposto barely shows on their sheet).
BOLD = {
    "sovereign": dict(roll=(4.0, 5.5), weight=(0.66, 0.72)),
}

# The judged odd rests (like motion_palette.JUDGED): values laid over the
# drawn row for one family. An awakened form takes its family's entry unless
# it has one of its own (a note alone is an entry: it takes nothing). Filled
# from the boards of 2026-09-24 and the judge's of 2026-09-25. Keys beside the
# style's own:
#   note     why, for the survey and the docs
#   hold     the family keeps TODAY's idle (the guard stood up by
#            tools/stand_idle.py): `ship` never writes it, and re-derives the
#            old one only when a re-shipped base has left it binding off
#   retry    what the re-run of a held family tries: laid on when the held
#            family is surveyed or boarded, never shipped until the hold goes
#   side     the leg the weight goes on first ("L" or "R"), where the chiasm's
#            would stand two figures of a row alike
#   sink_ok  the floor guard's sink, in metres, where the heel's skin is judged
OVERRIDES = {
    # the wolf's bind holds its arms 58 degrees out (the concept's claws
    # spread for the rigger): brought down to a beast's 30-35 in both stances
    "fenrir": dict(plain_arm_in=20.0, note="the bind's arms 58 degrees out: arm_down brings them to ~34, and "
                                           "the plain stance keeps 20 of it"),
    # the Jotunn's heels reach 13 cm behind the ankles and are skinned a
    # third to the shins, which lean back in its bind (hip z +0.69, knee
    # -0.23, ankle -0.37): any stance but the bind's dips them 2 cm under the
    # floor - 0.4% of a 4.5 m giant that stands only in the Codex (its battle
    # stance is its own file); the tolerance is judged, not the pose
    "boss_jotunn": dict(sink_ok=0.025, note="heels a third on the shins: 2 cm under on a 4.5 m giant"),
    # the bronze colossus stands 8 m, so it breathes at two thirds of the
    # row's rate (params_for's Froude term) and its sway is 2 cm
    "boss_colossus": dict(plain_arm_in=6.0, note="the bind's arms 35 degrees out; an 8 m giant, a 13 s loop"),
    # The four the study said keep some tear, judged on their boards of
    # 2026-09-24: each keeps less than the prototype did, from cloth welded
    # where the stance must move - no number of theirs is changed.
    # (the counts as shipped on 2026-09-25, at 20 keys a second)
    "heracles": dict(note="the lion skin across the arms: 1,095 -> 20 edges past 3x (the prototype 164); the lean, "
                          "the free leg's reach, the elbows, the arms' swing and the rolled shoulders held back"),
    "hera": dict(note="the peacock cape on the sceptre arm: 957 -> 7 (the prototype 205), on the right leg, the "
                      "reach held back; the awakened Hera's split skirt 201 -> 75, the weight held back"),
    "freya": dict(note="the cloak welded to both forearms: 1,719 -> 28 (the prototype 143), on the right leg; the "
                       "weight, the roll and the arms held back, the elbows the bind's"),
    # the hopping corpse holds its arms out before it (the craft's one
    # construct with a pose of its own); its long sleeves tear past 45
    # degrees (75: 204 edges past 3x and the forearms through the chest)
    "jiangshi": dict(arm_fwd=(42.0, 48.0), plain_arm_fwd=30.0, elbow=(2.0, 5.0), plain_elbow=3.0, arm_in=(3.0, 5.0),
                     note="arms held out before it, 45 degrees (the sleeves tear past it)"),
    # The judge of 2026-09-25 (every sheet, every board, 32 more):
    # the beast row's crouch (reach 0.90-0.93, a 8-12 degree lean) turns a
    # slim goddess and the scorpion queen into a squat that reads as sitting
    # on nothing, and Serqet's as the combat guard the owner objected to.
    # Held on today's idle until the re-run (lane W1, 2026-09-25): the row's
    # own plain values as the whole style (reach 0.975, a 3-5 degree lean)
    # still read crouched on the board - Bastet's knees soft and her arms 30
    # degrees out like claws, Serqet's daggers held level before her - so each
    # stands in the row the judge named instead, on the STAGES only: the
    # battle's deal keeps motion_palette.ARCHETYPE's beast (`archetype` here
    # moves the style row, not the plan).
    "bastet": dict(archetype="grace",
                   note="the slim goddess in the grace row (the beast crouch read as sitting on nothing; the "
                        "beast row's plain values still bent the knees and held the arms out 30 degrees): 1 -> 0 "
                        "edges past 3x, the arms 19 degrees"),
    "serqet": dict(archetype="champion",
                   note="the scorpion queen in the champion row (the beast crouch read as the combat guard; the "
                        "beast row's plain values held the daggers level before her): 86 -> 0 edges past 3x, the "
                        "arms 12 degrees, the daggers low"),
    # arms left 22-25 degrees out by a stance whose weight and reach were
    # held back (a kilt or a skirt skinned to both thighs): brought in toward
    # 12-15 in both stances, the flourish and the plain
    "horus": dict(arm_in=(13.0, 15.0), plain_arm_in=14.0,
                  note="the pleated kilt skinned to both thighs stretches as a knee bends: the weight and the reach "
                       "held back, the legs near straight; the arms brought in from 22 degrees to 13-14, which tears "
                       "no more"),
    "horus_awakened": dict(note="its own rig: the full style, none of Horus's arms"),
    "diana": dict(arm_in=(8.0, 10.0), plain_arm_in=9.0,
                  note="near the plain stance with open palms at 23-25 degrees read as a mannequin: the arms in by "
                       "2 degrees only - further in tore her (9-12 edges past 3x against 5, the arm_in at 10-18 and "
                       "the plain stance's arms brought down, 2026-09-25)"),
    "ra_awakened": dict(arm_in=(13.0, 15.0), plain_arm_in=14.0,
                        note="the weight and the reach held back, square: the arms in from 23 degrees to 13-14, "
                             "which tears no more"),
    # Tyr and Vidar stood alike (an axe in the right hand, the weight left,
    # the hips +4): Vidar takes the other leg, which tears no more (0 either
    # way), until step 5's alternates stand every figure on both
    "vidar": dict(side="R", note="the weight on the right leg, so he does not stand as Tyr does"),
}


def override_for(family):
    """The family's OVERRIDES entry: its own, else its unawakened family's."""
    if family in OVERRIDES:
        return OVERRIDES[family]
    return OVERRIDES.get(family.replace("_awakened", ""), {})


def arch_for(family):
    """The family's style row: an OVERRIDES `archetype` (the judge's move of
    a family whose motion_palette row stands it wrongly on the stages - the
    battle's deal keeps motion_palette's), else motion_palette.ARCHETYPE's."""
    return override_for(family).get("archetype") or mp.archetype(family)


def hold_reason(family):
    """Why the family keeps today's idle, or None (OVERRIDES' `hold`)."""
    return override_for(family).get("hold")


# ---------------------------------------------------------------------------
# Small maths (row-vector convention: v @ R, as tools/character.py)
# ---------------------------------------------------------------------------

def about(axis, deg):
    """Rotation by `deg` about a world axis, right hand (about(Y, 90) turns +Z to +X)."""
    axis = np.asarray(axis, float)
    n = np.linalg.norm(axis)
    if n < 1e-12 or abs(deg) < 1e-12:
        return np.eye(3)
    axis = axis / n
    th = math.radians(deg) / 2
    return quat_to_rot([*(axis * math.sin(th)), math.cos(th)])


def unit(v):
    n = np.linalg.norm(v)
    return v / n if n > 1e-12 else v


def rotation_part(m):
    a = np.asarray(m, float)[:3, :3].copy()
    s = np.linalg.norm(a, axis=1)
    s[s < 1e-12] = 1e-12
    u, _, vt = np.linalg.svd(a / s[:, None])
    r = u @ vt
    if np.linalg.det(r) < 0:
        u[:, -1] *= -1
        r = u @ vt
    return r


def frame_rotation(u0, p0, u1, p1):
    """The rotation taking the basis (u0, p0) onto (u1, p1)."""
    def basis(u, p):
        u = unit(u)
        p = unit(p - (p @ u) * u)
        return np.array([u, p, np.cross(u, p)])
    return basis(u0, p0).T @ basis(u1, p1)


def slerp_rot(r, t):
    q = rot_to_quat(r)
    if q[3] < 0:
        q = -q
    ang = 2 * math.acos(min(1.0, max(-1.0, q[3])))
    if ang < 1e-9:
        return np.eye(3)
    axis = q[:3] / math.sin(ang / 2)
    return quat_to_rot([*(axis * math.sin(ang * t / 2)), math.cos(ang * t / 2)])


def breath_curve(phase):
    """0..1..0 over one breath: inhale over 40%, exhale over 60%, eased at both ends."""
    phase = phase % 1.0
    if phase < 0.4:
        return 0.5 - 0.5 * math.cos(math.pi * phase / 0.4)
    return 0.5 + 0.5 * math.cos(math.pi * (phase - 0.4) / 0.6)


def held(x, k):
    """sin(x) with its ends held: tanh(k sin x) / tanh(k) (k -> 0 is the sine)."""
    s = math.sin(x)
    return s if k < 0.05 else math.tanh(k * s) / math.tanh(k)


def jerk(t, at, rise, fall):
    """A quick pulse inside the loop: up over `rise`, back over `fall`, 0 elsewhere."""
    d = t - at
    if 0 <= d < rise:
        return 0.5 - 0.5 * math.cos(math.pi * d / rise)
    if rise <= d < rise + fall:
        return 0.5 + 0.5 * math.cos(math.pi * (d - rise) / fall)
    return 0.0


def quiet(fn, *a, **k):
    with contextlib.redirect_stdout(io.StringIO()):
        return fn(*a, **k)


# ---------------------------------------------------------------------------
# The skeleton, read by position
# ---------------------------------------------------------------------------

class Rig:
    """A carrier's skeleton with its parts found by where they sit, never by
    name: the pelvis is the root the most joints hang from; of its children
    the one whose chain rises is the spine and the two that reach the floor
    are the legs (+X is the figure's left); the chest is the first joint up
    the spine that two lateral chains leave (the arms); of the chest's
    children the one that stays on the midline leads to the head, which is
    the highest joint up that chain the mesh is skinned to (the `head_end`
    and `headfront` markers own nothing); the joints between the chest and
    the head are the neck. A spine joint that sits ABOVE the next one up
    (Zeus's and Thor's `neck`, over the belly) bends nothing."""

    def __init__(self, carrier, skin_from=None):
        """`skin_from`: the shipped base (its full skin finds the head; the
        carrier's 1,500 triangles are the fallback)."""
        self.c = carrier
        skin_from = skin_from if skin_from is not None else carrier
        self.names = [j.split("/")[-1] for j in carrier.joints]
        self.parents = np.asarray(carrier.parents)
        W0 = world_from_local(np.asarray(carrier.rest_local, float), self.parents)
        self.rot0 = np.array([rotation_part(m) for m in W0])
        self.pos0 = W0[:, 3, :3].copy()
        self.parts = [decompose(m) for m in carrier.rest_local]
        J = len(self.names)
        self.children = {j: [] for j in range(J)}
        for j, p in enumerate(self.parents):
            if p >= 0:
                self.children[int(p)].append(j)
        P0 = self.pos0

        def sub(j):
            out, stack = [], [j]
            while stack:
                k = stack.pop()
                out.append(k)
                stack.extend(self.children[k])
            return out

        roots = [j for j in range(J) if self.parents[j] < 0]
        self.hips = max(roots, key=lambda r: len(sub(r)))
        kids = self.children[self.hips]
        up = max(kids, key=lambda c: max(P0[k][1] for k in sub(c)))
        legs = sorted((c for c in kids if c != up), key=lambda c: min(P0[k][1] for k in sub(c)))[:2]
        if len(legs) != 2:
            raise ValueError("no two legs under the pelvis")
        self.legs = {}
        for c in legs:
            chain = [c]
            while self.children[chain[-1]]:
                chain.append(min(self.children[chain[-1]], key=lambda k: P0[k][1]))
            if len(chain) < 3:
                raise ValueError("a leg chain shorter than hip, knee, foot")
            self.legs[c] = dict(upleg=chain[0], knee=chain[1], foot=chain[2], toes=chain[3:])
        left, right = sorted(legs, key=lambda c: -P0[c][0])
        self.leg = {"L": self.legs[left], "R": self.legs[right]}
        # the head's height over the feet: the unit every share in STYLES is of
        feet_y = min(P0[self.leg[s]["foot"]][1] for s in "LR")
        path, node = [], up
        H_guess = max(P0[:, 1]) - feet_y
        while True:
            path.append(node)
            ks = self.children[node]
            if not ks:
                raise ValueError("the spine ends before any arm leaves it")
            lateral = [k for k in ks if max(abs(P0[m][0] - P0[node][0]) for m in sub(k)) > 0.08 * H_guess]
            if len(lateral) >= 2 and len(ks) >= 3:
                break
            node = max(ks, key=lambda k: max(P0[m][1] for m in sub(k)))
        self.chest = node
        self.spine = path                                   # the pelvis's child ... the chest
        centre = min((k for k in self.children[node]),
                     key=lambda k: max(abs(P0[m][0] - P0[node][0]) for m in sub(k)))
        arms = [k for k in self.children[node] if k != centre]
        arms = sorted(arms, key=lambda k: -np.mean([P0[m][0] for m in sub(k)]))[:2]
        self.arm = {}
        for side, k in zip("LR", arms):
            chain = [k]
            while self.children[chain[-1]]:
                chain.append(max(self.children[chain[-1]], key=lambda m: np.linalg.norm(P0[m] - P0[k])))
            if len(chain) >= 4:
                self.arm[side] = dict(clav=chain[0], upper=chain[1], fore=chain[2], hand=chain[3])
            elif len(chain) == 3:
                self.arm[side] = dict(clav=None, upper=chain[0], fore=chain[1], hand=chain[2])
            else:
                raise ValueError("an arm chain shorter than arm, forearm, hand")
        self.head = self._find_head(sub, centre, skin_from)
        neck, j = [], int(self.parents[self.head])
        while j != self.chest and j >= 0:
            neck.append(j)
            j = int(self.parents[j])
        self.neck = neck[::-1]                              # the chest's child ... the head's parent
        # the spine joints that bend: those below the next joint up the chain
        nxt = self.spine[1:] + [self.chest]
        self.benders = [j for j, n in zip(self.spine, nxt) if j == self.chest or P0[n][1] > P0[j][1] + 1e-4]
        self.height = float(P0[self.head][1] - feet_y)
        # how straight each leg stands in the bind (hip to ankle over the
        # bones' length): 0.995 on most, but a hoof, a paw or a bent knee
        # the concept was painted with stands at 0.70-0.90, and straightening
        # it sinks a heel skinned half to the shin through the floor
        self.bind_reach = {}
        for s in "LR":
            g = self.leg[s]
            a = np.linalg.norm(P0[g["knee"]] - P0[g["upleg"]])
            b = np.linalg.norm(P0[g["foot"]] - P0[g["knee"]])
            self.bind_reach[s] = float(np.linalg.norm(P0[g["foot"]] - P0[g["upleg"]]) / (a + b))
        # where each knee points: the way the bind bends it (a knee under a
        # long robe that the rig turned out tears the robe least bending that
        # way: Hera 17 edges against 55 with the knees forward), but never
        # INWARD - a straight bind's 1-3 cm of offset pointed Bastet's knees
        # at each other and her crouch went knock-kneed - and over the toes
        # where the bind gives no direction at all
        self.knee_pole = {}
        for s in "LR":
            g = self.leg[s]
            sgn = 1.0 if s == "L" else -1.0
            axis = unit(P0[g["foot"]] - P0[g["upleg"]])
            off = (P0[g["knee"]] - P0[g["upleg"]]) - ((P0[g["knee"]] - P0[g["upleg"]]) @ axis) * axis
            if off[0] * sgn < 0:
                off[0] = 0.0
            if np.linalg.norm(off) < 0.003 * self.height:
                off = (P0[g["toes"][0]] - P0[g["foot"]]) * np.array([1.0, 0.0, 1.0]) if g["toes"] else Z.copy()
            pole = unit(off)
            if pole @ Z < 0.2:                         # a knee's pole points forward
                pole = unit(pole + Z)
            pole = pole - (pole @ axis) * axis
            self.knee_pole[s] = unit(pole)
        # how far each upper arm hangs out from straight down in the bind
        # (22 degrees at the median; Fenrir 58, Apollo 41, Horus 40)
        self.hang = {}
        for s in "LR":
            v = unit(P0[self.arm[s]["fore"]] - P0[self.arm[s]["upper"]])
            self.hang[s] = math.degrees(math.acos(max(-1.0, min(1.0, -float(v[1])))))

    def _find_head(self, sub, centre, skin):
        """The joint that carries the skull: of the chain above the chest,
        the furthest joint with children (a leaf is an end marker: `head_end`,
        `headfront`, or the `Head` of Zeus's rig, which holds no vertex) whose
        subtree holds four fifths of the skull - the vertices in the top tenth
        of the figure skinned to that chain. On the eleven rigs whose joint
        over the hips is named `neck`, that is the joint named Head1 or Spine1
        (Zeus's holds all 1,689 of his skull's vertices, his `Head` none); on
        Hephaestus's it is the one named `neck`."""
        chain = sub(centre)
        leaf = [j.split("/")[-1] for j in skin.joints]
        idx = {n: i for i, n in enumerate(leaf)}
        pts = np.asarray(skin.points, dtype=np.float64)
        dom = np.asarray(skin.joint_indices)[np.arange(len(pts)), np.asarray(skin.joint_weights).argmax(axis=1)]
        top = pts[:, 1] > pts[:, 1].min() + 0.9 * np.ptp(pts[:, 1])
        mine = {j: int(((dom == idx[self.names[j]]) & top).sum()) if self.names[j] in idx else 0 for j in chain}
        total = sum(mine.values())
        if total == 0:                                  # no skin to read: the highest joint with children
            inner = [j for j in chain if self.children[j]] or chain
            return max(inner, key=lambda j: self.pos0[j][1])
        best, depth = centre, -1
        for j in chain:
            if not self.children[j]:
                continue
            held = sum(mine[k] for k in sub(j))
            d, k = 0, j
            while k != centre:
                k, d = int(self.parents[k]), d + 1
            if held >= 0.8 * total and d > depth:
                best, depth = j, d
        return best

    def roles(self):
        """{role: joint name}, for the survey's check against the names."""
        out = {"hips": self.names[self.hips], "chest": self.names[self.chest], "head": self.names[self.head],
               "neck": "/".join(self.names[j] for j in self.neck),
               "spine": "/".join(self.names[j] for j in self.spine)}
        for s in "LR":
            for k, v in self.leg[s].items():
                if k != "toes":
                    out[f"{s}.{k}"] = self.names[v]
            for k, v in self.arm[s].items():
                if v is not None:
                    out[f"{s}.{k}"] = self.names[v]
        return out


# ---------------------------------------------------------------------------
# A family's numbers
# ---------------------------------------------------------------------------

def draw(family, key, value):
    """A number inside `value`'s range from a hash of the family's key."""
    if isinstance(value, tuple):
        lo, hi = value
        u = int(hashlib.sha256(f"{family}:{key}".encode()).hexdigest()[:8], 16) / 2 ** 32
        return lo + (hi - lo) * u
    return value


def params_for(family, height=None, level="full", overrides=None, bold=False):
    """The family's numbers: its archetype's row over BASE (and its BOLD row
    with `bold`), each range drawn from the family's hash, OVERRIDES laid on
    (a held family's `retry` over them), and the flourishes (BASE's and the
    row's `flourish`, and an override's `plain_<key>`) whole, halfway to their
    plain values, or plain, by `level`."""
    if overrides is None:
        overrides = override_for(family)
    arch = overrides.get("archetype") or mp.archetype(family)
    if arch is None:
        raise ValueError(f"{family}: no archetype (motion_palette.ARCHETYPE)")
    row = dict(BASE)
    row.update({k: v for k, v in STYLES[arch].items() if k != "flourish"})
    if bold:
        row.update(BOLD.get(arch, {}))
    flourish = dict(BASE_FLOURISH)
    flourish.update(STYLES[arch].get("flourish", {}))
    over = dict(overrides)
    retry = over.pop("retry", None)
    if over.pop("hold", None) and retry:
        over.update(retry)
    for k in ("note", "side", "archetype"):
        over.pop(k, None)
    for k in list(over):
        if k.startswith("plain_"):
            flourish[k[len("plain_"):]] = over.pop(k)
    p = {k: draw(family, k, v) for k, v in row.items()}
    for k, v in over.items():
        p[k] = draw(family, k, v)
    copies = [k for k in ("arm_in", "arm_fwd", "elbow") if p.get("free_" + k) is None]
    for k in copies:
        p["free_" + k] = p[k]
    mix = {"full": 0.0, "half": 0.5, "plain": 1.0}[level]
    for k in sorted(flourish, key=lambda k: k.startswith("free_")):       # the free arm's after the other's
        plain_v = flourish[k]
        if plain_v is None:
            plain_v = p[k[len("free_"):]] if k.startswith("free_") else p[k]
        if isinstance(p.get(k), bool) or not isinstance(p.get(k), (int, float)):
            continue
        p[k] = p[k] + mix * (plain_v - p[k])
    for k in copies:                                  # an arm the row gives no swing of its own takes the other's
        p["free_" + k] = p[k]
    p["archetype"] = arch
    p["level"] = level
    # phases: every drift starts somewhere of its own
    for k in ("sway", "fore", "survey", "glance", "nod", "roll"):
        p["ph_" + k] = 2 * math.pi * draw(family, "phase:" + k, (0.0, 1.0))
    p["tilt_sign"] = -1.0 if p.get("tilt_flip") else 1.0
    # a giant breathes slower (Froude: a body's time goes as the square root of its size)
    tempo = p.get("tempo", 1.0)
    if height and height > 2.6:
        tempo *= 1.0 / min(1.5, math.sqrt(height / 1.9))
    period = p["period"] / tempo
    frames = int(round(period * p["breaths"] * FPS))
    p["loop"] = frames / FPS                           # a whole number of frames: the components close exactly
    p["period"] = p["loop"] / p["breaths"]
    p["frames"] = frames
    return p


# ---------------------------------------------------------------------------
# The pose at time t
# ---------------------------------------------------------------------------

def pose_at(rig, t, p, stand):
    """World rotations (J,3,3) and positions (J,3) at time t, standing on
    `stand` ("L" or "R")."""
    R0, P0, h = rig.rot0, rig.pos0, rig.height
    L = p["loop"]
    tau = 2 * math.pi
    w = 1.0 if stand == "L" else -1.0                 # +X is the figure's left: the standing side's sign
    wb = p.get("blade_w", w)                          # the hunter's blade: the MAIN's side in its alt (the bow side
                                                      # leads whichever leg stands)
    hitch_at = p["hitch_at"] * L
    n_b = len(rig.benders)
    shares = [(k + 1) / (n_b * (n_b + 1) / 2) for k in range(n_b)]

    def trunk(tt):
        b = breath_curve(tt / p["period"]) * (0.85 + 0.15 * math.cos(tau * tt / L))
        sway = math.sin(tau * tt / L + p["ph_sway"])
        pop = p["hitch"] * jerk(tt % L, hitch_at, 0.12, 0.45) if p["hitch"] else 0.0
        roll = w * p["roll"] * (1 + pop) + w * 0.6 * sway
        D = {rig.hips: about(Z, roll) @ about(Y, w * p["hip_yaw"] + wb * p["blade"])}
        breath = p["breath"] * b
        counter = -p["counter"] * roll
        for j in rig.spine:
            if j in rig.benders:
                k = rig.benders.index(j)
                rs, ts = 1.0 / n_b, shares[k]
                d = (about(Z, counter * rs) @ about(Y, (-w * p["twist"] + wb * p["blade"]) * ts)
                     @ about(X, -(breath * ts) + p["lean"] * rs))
            else:
                d = np.eye(3)
            D[j] = d @ D[int(rig.parents[j])]
        chest_roll = roll + counter
        torso_yaw = w * p["hip_yaw"] + 2 * wb * p["blade"] - w * p["twist"]
        return D, b, sway, chest_roll, breath, torso_yaw, pop

    D, b, sway, chest_roll, breath, torso_yaw, pop = trunk(t)
    Rw = np.empty_like(R0)
    Pw = np.empty_like(P0)
    hips = rig.hips
    free = "R" if stand == "L" else "L"
    mid0 = 0.5 * (P0[rig.leg["L"]["foot"]][0] + P0[rig.leg["R"]["foot"]][0])

    # the feet's spots: the standing foot drawn in, the free foot a step
    # ahead - of the MAIN idle's legs (`feet_on`), so that the weight-shift
    # variant, standing on the other leg, plants both feet on the same spots
    # and the two can blend (`alt`)
    feet_on = p.get("feet_on") or stand

    def target(side):
        T = P0[rig.leg[side]["foot"]].copy()
        T[0] += p["narrow"] * (mid0 - T[0])
        if side == feet_on:
            T[0] += p["stand_in"] * (mid0 - T[0])
        else:
            T[2] += p["step"] * h
        return T
    xs, xf = target(stand)[0], target(free)[0]
    over_x = 0.5 * (xs + xf) + (p["weight"] - 0.5) * (xs - xf) * (1 + pop)     # the weight over the standing foot
    fore = p["fore_sway"] * h * math.sin(2 * tau * t / L + p["ph_fore"])
    Pw[hips] = np.array([over_x + w * p["sway"] * h * sway, P0[hips][1], P0[hips][2] + fore])
    Rw[hips] = R0[hips] @ D[hips]

    # the neck and the head
    look = (p["survey"] * held(tau * t / L + p["ph_survey"], p["survey_k"])
            + p["glance"] * held(tau * p["glance_n"] * t / L + p["ph_glance"], p["glance_k"]))
    pitch = p["nod"] * math.sin(2 * tau * t / L + p["ph_nod"])
    if p["bob_head"]:
        pitch += p["bob_head"] * math.sin(tau * t / p["period"] * 2)
    head_roll = p["neck_roll"] * math.sin(tau * t / L + p["ph_survey"] + math.pi / 2)
    tw = 0.0
    if p["twitch"]:
        at = p["twitch_at"] * L
        tw = p["twitch"] * (jerk(t % L, at, 0.07, 0.35) - 0.6 * jerk(t % L, at + 0.9, 0.09, 0.4))
    face = -p["head_face"] * torso_yaw
    n_n = max(len(rig.neck), 1)
    for j in rig.neck:
        D[j] = (about(Z, -p["neck_steady"] * chest_roll / n_n) @ about(X, breath * 0.5 / n_n)
                @ about(Y, (w * p["head_turn"] * 0.4 + 0.3 * look + 0.4 * face) / n_n)) @ D[int(rig.parents[j])]
    lift = 0.0 if rig.neck else -p["neck_steady"] * chest_roll
    D[rig.head] = (about(Z, -w * p["head_tilt"] * p["tilt_sign"] + head_roll + lift - 0.5 * w * p["roll"] * pop)
                   @ about(Y, w * p["head_turn"] * (0.6 if rig.neck else 1.0) + 0.7 * look + 0.6 * face + tw)
                   @ about(X, -p["chin"] + pitch + breath * 0.3)) @ D[int(rig.parents[rig.head])]

    # the clavicles rise with the breath (and roll forward on a brute)
    for side, sgn in (("L", 1.0), ("R", -1.0)):
        c = rig.arm[side]["clav"]
        if c is not None:
            D[c] = about(Z, sgn * p["clav"] * b) @ about(Y, -sgn * p["clav_fwd"]) @ D[int(rig.parents[c])]

    # the arms hang: from the bind, swung as the style says, following the chest a beat late
    lagged = trunk(t - p["lag"])[0][rig.chest]
    follow = slerp_rot(lagged, p["follow"])
    weapon = mp.weapon_hand(p["family"]) if p.get("family") else "R"
    for side, sgn in (("L", 1.0), ("R", -1.0)):
        a = rig.arm[side]
        ja, jf, jh = a["upper"], a["fore"], a["hand"]
        pre = "" if (weapon is None or weapon == side) else "free_"
        down = unit(P0[jf] - P0[ja])
        inward = -sgn * X
        swing_in = (p[pre + "arm_in"] + p["arm_down"] * max(0.0, rig.hang[side] - HANG_TARGET)
                    - p.get("arm_out_" + side, 0.0))
        # the weapon's hang (hang_for): the arm a little back, the elbow
        # bent or eased, and the wrist turned so a held weapon hangs by the
        # thigh (or a pole stands) - a rotation in the bind's frame, so the
        # weapon rides the hand's own breath and sway
        fwd = p[pre + "arm_fwd"] - p.get("hang_back_" + side, 0.0)
        adj = about(np.cross(down, Z), fwd) @ about(np.cross(down, inward), swing_in)
        D[ja] = adj @ follow
        fdir = unit(P0[jh] - P0[jf])
        D[jf] = about(np.cross(fdir, Z), p[pre + "elbow"] + p.get("hang_elbow_" + side, 0.0)) @ D[ja]
        fore_turn = p.get("fore_turn_" + side)          # a weapon the forearm carries half of turns there
        if fore_turn is not None:
            D[jf] = np.asarray(fore_turn, float) @ D[jf]
        wrist = p.get("wrist_" + side)
        D[jh] = (np.asarray(wrist, float) @ D[jf]) if wrist is not None else D[jf]

    # forward kinematics for everything but the legs
    leg_joints = set()
    for s in "LR":
        g = rig.leg[s]
        leg_joints |= {g["upleg"], g["knee"], g["foot"], *g["toes"]}
    order = range(len(R0))
    for j in order:
        if j == hips or j in leg_joints:
            continue
        pj = int(rig.parents[j])
        if j not in D:
            D[j] = D[pj] if pj >= 0 else np.eye(3)
        Rw[j] = R0[j] @ D[j]
        Pw[j] = Pw[pj] + (P0[j] - P0[pj]) @ R0[pj].T @ Rw[pj]

    # the legs: the pelvis's height set so the standing leg reaches `reach` of its length, then IK
    def parts(side):
        g = rig.leg[side]
        u, k, f = g["upleg"], g["knee"], g["foot"]
        return u, k, f, np.linalg.norm(P0[k] - P0[u]), np.linalg.norm(P0[f] - P0[k])

    drop = -1e9
    # a leg is never straightened past its own bind (a bent bind leg keeps its bend)
    reach_stand = min(p["reach"], rig.bind_reach[stand] - (0.985 - p["reach"]) if rig.bind_reach[stand] < 0.985
                      else p["reach"])
    reach_free = min(p["reach_free"], rig.bind_reach[free] + 0.01)
    for side, reach in ((stand, reach_stand), (free, reach_free)):
        u, k, f, a, bb = parts(side)
        hip_at = Pw[hips] + (P0[u] - P0[hips]) @ R0[hips].T @ Rw[hips]
        T = target(side)
        horiz = math.hypot(*(T - hip_at)[[0, 2]])
        need_h = math.sqrt(max((reach * (a + bb)) ** 2 - horiz ** 2, 1e-9))
        need = (hip_at[1] - T[1]) - need_h
        drop = need if side == stand else max(drop, need)
    Pw[hips][1] -= drop
    Pw[hips][1] += p["bob"] * h * b
    if p["settle"]:
        Pw[hips][1] -= p["settle"] * h * (0.5 - 0.5 * math.cos(tau * t / L + p["ph_roll"]))
    # never lifted past what either leg reaches with its knee still bent: an
    # IK told to reach further plants nothing (the breath's lift on a
    # near-straight leg raised Hel's toes 1.3 mm off the floor)
    for side in "LR":
        u, k, f, a, bb = parts(side)
        hip_at = Pw[hips] + (P0[u] - P0[hips]) @ R0[hips].T @ Rw[hips]
        T = target(side)
        horiz = math.hypot(*(T - hip_at)[[0, 2]])
        top = T[1] + math.sqrt(max((0.998 * (a + bb)) ** 2 - horiz ** 2, 1e-9))
        if hip_at[1] > top:
            Pw[hips][1] -= hip_at[1] - top
    for j in order:
        if j == hips or j in leg_joints:
            continue
        pj = int(rig.parents[j])
        Pw[j] = Pw[pj] + (P0[j] - P0[pj]) @ R0[pj].T @ Rw[pj]

    for side in "LR":
        u, k, f, a, bb = parts(side)
        H = Pw[hips] + (P0[u] - P0[hips]) @ R0[hips].T @ Rw[hips]
        F = target(side)
        d_vec = F - H
        d = min(max(np.linalg.norm(d_vec), abs(a - bb) + 1e-4), (a + bb) * 0.9995)
        axis = unit(d_vec)
        sgn = 1.0 if side == "L" else -1.0
        turn = about(Y, sgn * p["turn_out"]) if side != feet_on else np.eye(3)   # the free foot's toes OUT
        pole0 = rig.knee_pole[side]
        pole = pole0 @ turn                            # the knee follows its foot
        pole = unit(pole - (pole @ axis) * axis)
        x = (a * a - bb * bb + d * d) / (2 * d)
        y = math.sqrt(max(a * a - x * x, 0.0))
        K = H + axis * x + pole * y
        Rw[u] = R0[u] @ frame_rotation(P0[k] - P0[u], pole0, K - H, pole)
        Pw[u] = H
        Rw[k] = R0[k] @ frame_rotation(P0[f] - P0[k], pole0, F - K, pole)
        Pw[k] = Pw[u] + (P0[k] - P0[u]) @ R0[u].T @ Rw[u]
        Rw[f] = R0[f] @ turn
        Pw[f] = Pw[k] + (P0[f] - P0[k]) @ R0[k].T @ Rw[k]
        prev = f
        for jt in rig.leg[side]["toes"]:
            Rw[jt] = R0[jt] @ turn
            Pw[jt] = Pw[prev] + (P0[jt] - P0[prev]) @ R0[prev].T @ Rw[prev]
            prev = jt
    return Rw, Pw


def sample_keys(rig, p, stand, frames):
    """Only the keys at `frames` (the ones a measure reads): the search's
    shortcut, the same poses the written loop has at those frames."""
    J = len(rig.names)
    n = len(frames)
    T = np.empty((n, J, 3))
    R = np.empty((n, J, 4))
    rest_t = np.array([rig.parts[j][0] for j in range(J)])
    scales = np.array([rig.parts[j][2] for j in range(J)])
    for i, fr in enumerate(frames):
        Rw, Pw = pose_at(rig, (fr % p["frames"]) / FPS, p, stand)
        for j in range(J):
            pj = int(rig.parents[j])
            R[i, j] = rot_to_quat(Rw[j] @ Rw[pj].T if pj >= 0 else Rw[j])
        T[i] = rest_t
        T[i, rig.parents < 0] = Pw[rig.parents < 0]
    return {"T": T, "R": R, "S": np.repeat(scales[None], n, 0), "fps": FPS}


def measured_frames(p, samples=24):
    """clip_fix.clip_stretch's frames of the written loop (F+1 keys)."""
    n = p["frames"] + 1
    return np.unique(np.linspace(0, n - 1, samples).round().astype(int))


def synthesize(rig, p, stand):
    """The loop as F+1 keys (the last equal to the first) on the carrier's joints."""
    F = p["frames"]
    J = len(rig.names)
    T = np.empty((F + 1, J, 3))
    R = np.empty((F + 1, J, 4))
    S = np.empty((F + 1, J, 3))
    scales = np.array([rig.parts[j][2] for j in range(J)])
    rest_t = np.array([rig.parts[j][0] for j in range(J)])
    for fr in range(F):
        Rw, Pw = pose_at(rig, fr / FPS, p, stand)
        for j in range(J):
            pj = int(rig.parents[j])
            loc = Rw[j] @ Rw[pj].T if pj >= 0 else Rw[j]
            q = rot_to_quat(loc)
            if fr and np.dot(q, R[fr - 1, j]) < 0:
                q = -q
            R[fr, j] = q
        T[fr] = rest_t
        T[fr, rig.parents < 0] = Pw[rig.parents < 0]
        S[fr] = scales
    # the loop's end: pose_at(L) is pose_at(0) to rounding; written as the first key exactly
    Rw, Pw = pose_at(rig, F / FPS, p, stand)
    end_err = float(np.abs(Pw[rig.hips] - T[0, rig.hips]).max()) if rig.parents[rig.hips] < 0 else 0.0
    T[F], S[F] = T[0], S[0]
    sign = np.sign(np.sum(R[0] * R[F - 1], axis=1))
    sign[sign == 0] = 1.0
    R[F] = R[0] * sign[:, None]
    return {"T": T.astype(np.float32), "R": R.astype(np.float32), "S": S.astype(np.float32), "fps": FPS}, end_err


# ---------------------------------------------------------------------------
# The measures: tear, feet, floor, arms, loop - on the SHIPPED base
# ---------------------------------------------------------------------------

class Base:
    """The family's shipped base mesh, read once, with what the guards need."""

    def __init__(self, path):
        import weapon_pass
        self.path = Path(path)
        c = quiet(character.read_usdz, str(path))
        self.c = c
        self.P = c.points.astype(np.float64)
        self.faces = np.asarray(c.faces)
        self.ji = np.asarray(c.joint_indices)
        self.jw = np.asarray(c.joint_weights, dtype=np.float64)
        self.inv_bind = np.linalg.inv(c.bind)
        self.leaf = [j.split("/")[-1] for j in c.joints]
        self.edges = weapon_pass.unique_edges(self.faces)
        self.h = float(np.ptp(self.P[:, 1]))
        self.L0 = np.linalg.norm(self.P[self.edges[:, 0]] - self.P[self.edges[:, 1]], axis=1)
        self.ok = self.L0 > 1e-3 * self.h
        self.body = character.body_joints(c)
        self._clear = None
        self._bind_side = None

    def worlds(self, anim, joints, frames):
        """(frame, joint world (J,4,4)) of the base posed by a clip, joints matched by name, as the game does."""
        cmap = {j.split("/")[-1]: i for i, j in enumerate(joints)}
        out = []
        for f in frames:
            local = np.array(self.c.rest_local, dtype=np.float64)
            for bi, bj in enumerate(self.leaf):
                ci = cmap.get(bj)
                if ci is not None:
                    local[bi] = trs(anim["T"][f, ci], anim["R"][f, ci], anim["S"][f, ci])
            out.append((int(f), world_from_local(local, self.c.parents)))
        return out

    def skin(self, world):
        m = np.einsum("jab,jbc->jac", self.inv_bind, world)
        ph = np.c_[self.P, np.ones(len(self.P))]
        per = np.einsum("nc,nkcd->nkd", ph, m[self.ji])
        return np.einsum("nk,nkd->nd", self.jw, per)[:, :3]

    def clearance_sets(self, rig):
        """(arm vertices to test, 'held' flags among them, body vertices).
        The arm is its own tight SKIN round the upper arm, the forearm and the
        hand with its grip (character._arm_masks), owned by the arm, the
        shoulder's cap left out; cloth welded to a hand (Freya's cloak, a
        kilt's panel) is not the arm. The body is the thighs' and the trunk's
        OWN layer (character._limb_surface round the thigh bone and round the
        pelvis-to-chest line: the innermost surface up to the first gap), owned
        by the legs or the trunk - a cloak hanging beyond a gap, or an axe
        skinned to the thigh it was painted against, is not the body."""
        if self._clear is not None:
            return self._clear
        idx = {n: i for i, n in enumerate(self.leaf)}
        bpos = self.c.bind[:, 3, :3].astype(np.float64)
        dom = self.ji[np.arange(len(self.P)), self.jw.argmax(axis=1)]
        h = self.h

        def at(j):
            return bpos[idx[rig.names[j]]]
        arm_j, hand_j = set(), set()
        for s in "LR":
            a = rig.arm[s]
            arm_j |= {idx[rig.names[a[k]]] for k in ("upper", "fore", "hand") if rig.names[a[k]] in idx}
            if rig.names[a["hand"]] in idx:
                hand_j.add(idx[rig.names[a["hand"]]])
        trunk_j = {idx[rig.names[j]] for j in [rig.hips] + rig.spine if rig.names[j] in idx}
        leg_j = {idx[rig.names[v]] for s in "LR" for k, v in rig.leg[s].items() if k != "toes"
                 and rig.names[v] in idx}
        normals = character.vertex_normals(self.P.astype(np.float32), self.faces).astype(np.float64)
        _, skin, _ = quiet(character._arm_masks, self.c, self.P, normals, character.ROBE_ARM_RADIUS)
        # the armpit is not tested: the upper arm's half nearest the shoulder
        # is squeezed against the flank by any swing (skinning's own fold,
        # hidden in the pit), where a hand or a forearm in a hip is seen
        near_shoulder = np.zeros(len(self.P), bool)
        for side in "LR":
            a = rig.arm[side]
            if rig.names[a["upper"]] not in idx:
                continue
            u0, u1 = at(a["upper"]), at(a["fore"])
            t = ((self.P - u0) @ (u1 - u0)) / max(float((u1 - u0) @ (u1 - u0)), 1e-12)
            near_shoulder |= (dom == idx[rig.names[a["upper"]]]) & (t < 0.66)
            near_shoulder |= np.linalg.norm(self.P - u0, axis=1) < 0.07 * h
        test = np.isin(dom, list(arm_j)) & skin & ~near_shoulder
        held = np.isin(dom, list(hand_j))
        left_j = {idx[rig.names[v]] for k, v in rig.arm["L"].items() if v is not None and rig.names[v] in idx}
        left = np.isin(dom, list(left_j))
        body = np.zeros(len(self.P), bool)
        for s in "LR":
            g = rig.leg[s]
            body |= character._limb_surface(self.P, normals, at(g["upleg"]), at(g["knee"]), reach=0.2 * h,
                                            gap=0.012 * h, inward_stop=True)
        top = at(rig.chest) + np.array([0.0, 0.08 * h, 0.0])
        trunk = character._limb_surface(self.P, normals, at(rig.hips) - np.array([0.0, 0.05 * h, 0.0]), top,
                                        reach=0.3 * h, gap=0.012 * h, inward_stop=False)
        # the trunk a hanging arm can reach: the flank, the belly and the hips,
        # below the armpits (the shoulders' own mantle is the arm's socket)
        armpit = min(at(rig.arm[s]["upper"])[1] for s in "LR") - 0.08 * h
        body |= trunk & (self.P[:, 1] < armpit)
        body &= np.isin(dom, list(trunk_j | leg_j))
        self._clear = (np.flatnonzero(test), held[test], np.flatnonzero(body), left[test])
        return self._clear

    def feet(self, rig):
        dom = self.ji[np.arange(len(self.P)), self.jw.argmax(axis=1)]
        out = {}
        for s in "LR":
            names = {rig.names[rig.leg[s]["foot"]], *(rig.names[t] for t in rig.leg[s]["toes"])}
            js = [i for i, l in enumerate(self.leaf) if l in names]
            out[s] = np.flatnonzero(np.isin(dom, js))
        return out

    def measure(self, anim, joints, rig, samples=24, arms=True, frames=None):
        """Every measure the guards read, over `samples` frames of the clip
        (clip_fix.clip_stretch's frames and sum, so the counts are its), or
        over every key of `anim` when `frames` names the frames they are."""
        from scipy.spatial import cKDTree
        n = len(anim["T"])
        if frames is None:
            frames = np.unique(np.linspace(0, n - 1, samples).round().astype(int))
            keys = frames
        else:
            keys = np.arange(n)
        ws = self.worlds(anim, joints, keys)
        feet = self.feet(rig)
        e0, e1 = self.edges[:, 0], self.edges[:, 1]
        worst = np.ones(len(self.edges))
        at = np.zeros(len(self.edges), int)
        rise, sink = 0.0, 0.0
        if arms:
            test, held, body, left = self.clearance_sets(rig)
            if self._bind_side is None:
                bind_n = character.vertex_normals(self.P.astype(np.float32), self.faces).astype(np.float64)
                d0, nn0 = cKDTree(self.P[body]).query(self.P[test])
                self._bind_side = np.einsum("ij,ij->i", self.P[test] - self.P[body][nn0], bind_n[body][nn0])
            s0 = self._bind_side
        worst_through, worst_held, at_frame = 0, 0, None
        worst_side = {"L": 0, "R": 0}
        for k, (_, w) in enumerate(ws):
            f = int(frames[k])
            Q = self.skin(w)
            # the tear: weapon_pass.worst_stretch's sum, on the same skinned points
            L = np.linalg.norm(Q[e0] - Q[e1], axis=1) / np.maximum(self.L0, 1e-12)
            L[~self.ok] = 1.0
            better = L > worst
            worst[better] = L[better]
            at[better] = f
            # the floor: each foot's lowest point against its bind height
            for side in "LR":
                if len(feet[side]):
                    d = float(Q[feet[side], 1].min() - self.P[feet[side], 1].min())
                    rise, sink = max(rise, d), max(sink, -d)
            if not arms:
                continue
            nq = character.vertex_normals(Q.astype(np.float32), self.faces).astype(np.float64)
            dist, nn = cKDTree(Q[body]).query(Q[test])
            sd = np.einsum("ij,ij->i", Q[test] - Q[body][nn], nq[body][nn])
            # behind the nearest body point's surface, deep, and INTO it (the
            # offset within ~45 degrees of the inward normal: a point off to
            # the side of a vertex's tangent plane is beside the body, not in
            # it), and deeper than it lay at the bind by the depth: a hand
            # resting against the hip in the bind is not pushed through it
            through = (sd < np.minimum(s0, 0.0) - ARM_DEPTH * self.h) & (-sd >= 0.7 * dist)
            k_arm, k_held = int((through & ~held).sum()), int((through & held).sum())
            side_l, side_r = int((through & left).sum()), int((through & ~left).sum())
            worst_side["L"], worst_side["R"] = max(worst_side["L"], side_l), max(worst_side["R"], side_r)
            if k_arm + k_held > worst_through + worst_held:
                worst_through, worst_held, at_frame = k_arm, k_held, f
        return dict(max=round(float(worst.max()), 1), over2=int((worst > 2).sum()), over3=int((worst > 3).sum()),
                    frame=int(at[worst.argmax()]), floor_mm=round(rise * 1000, 2), sink_mm=round(sink * 1000, 2),
                    through=worst_through, through_held=worst_held, through_frame=at_frame,
                    through_L=worst_side["L"], through_R=worst_side["R"])


    # -- the held weapon ----------------------------------------------------

    def weapons(self, rig):
        """The long things the hands hold, found by measurement on the shipped
        base, never by name: per hand, the piece weapon_pass.held_pieces cuts
        off the arm's skin (the weapon pass's own detection) when it is long
        and thin, else the hand's farthest skinned vertices (the hand owns
        half of them or more, past the fist) - a trident or a spear fused to
        a cloak is no piece of its own (Baldr's, Neptune's). Each is a dict:
        side (the rig's "L"/"R"), the base's hand joint, `verts` (what it is,
        for the floor and the body), the grip (where the axis passes the fist),
        the axis from the grip to the HEAD (the end with the wider cross
        section: a spear's blade, a trident's tines, an axe's head - the end
        that goes up on a pole), the reach to the head and to the butt, the
        share of its rows the hand carries (`carried`: the hand owns half or
        more) and the forearm and hand between them (`carried_arm`: 90% or
        more), and the joints that own the rest (`others`). [] for an
        empty-handed family."""
        if getattr(self, "_weapons", None) is not None:
            return self._weapons
        import weapon_pass
        P, h = self.P, self.h
        idx = {n: i for i, n in enumerate(self.leaf)}
        hand_w = {}
        for s in "LR":
            name = rig.names[rig.arm[s]["hand"]]
            if name in idx:
                hand_w[s] = (idx[name], (self.jw * (self.ji == idx[name])).sum(axis=1))
        try:
            pieces, _ = quiet(weapon_pass.held_pieces, self.c)
        except Exception:  # noqa: BLE001 - a rig the pass cannot read keeps the hand's own rows
            pieces = []
        out = []
        for s, (hj, w) in hand_w.items():
            wrist = self.c.bind[hj][3, :3].astype(np.float64)
            fore_j = int(self.c.parents[hj])
            w_arm = w + (self.jw * (self.ji == fore_j)).sum(axis=1)
            far = np.flatnonzero((w >= 0.5) & (np.linalg.norm(P - wrist, axis=1) > WEAPON_FIST * h))
            cands = []
            for pc in pieces:
                if pc["hand"] != hj or len(pc["verts"]) < 30:
                    continue
                cands.append(("piece", np.asarray(pc["verts"])))
            if len(far) >= 30:
                cands.append(("hand", far))
            best = None
            for how, verts in cands:
                X = P[verts]
                mu = X.mean(axis=0)
                _, sv, vt = np.linalg.svd(X - mu, full_matrices=False)
                axis = vt[0]
                t = (X - mu) @ axis
                length = float(np.ptp(t))
                elong = float(sv[0] / max(sv[1], 1e-9))
                # an axe's broad head makes a short, stout cloud (the Jotunn's 2.1)
                if length < WEAPON_MIN * h or elong < (2.0 if length >= 0.4 * h else 3.0):
                    continue
                if best is None or length > best[2]:
                    best = (how, verts, length, axis, mu)
            if best is None and len(far) >= 20:
                # nothing the hand carries is long: a weapon fused to the body
                # or a cloak shows only its grip on the hand (Neptune's trident,
                # Baldr's spear). Its line is read on for the survey's word -
                # such a weapon is never turned (pivot_for), it would tear
                X = P[far]
                mu = X.mean(axis=0)
                _, sv, vt = np.linalg.svd(X - mu, full_matrices=False)
                axis = vt[0]
                rel = P - mu
                t = rel @ axis
                r = np.linalg.norm(rel - t[:, None] * axis, axis=1)
                line = np.flatnonzero((r < 0.015 * h) & (np.abs(t) < 0.8 * h))
                if len(line) >= 30 and float(np.ptp(t[line])) >= WEAPON_MIN * h and sv[0] >= 2.0 * sv[1]:
                    best = ("line", line, float(np.ptp(t[line])), axis, mu)
            if best is None:
                continue
            how, verts, length, axis, mu = best
            # the grip: the point of the axis nearest the fist (the hand joint
            # carried 0.04 h on along the forearm's line)
            fore = self.c.bind[int(self.c.parents[hj])][3, :3].astype(np.float64)
            fist = wrist + unit(wrist - fore) * 0.04 * h
            grip = mu + ((fist - mu) @ axis) * axis
            t = (P[verts] - grip) @ axis
            r = np.linalg.norm((P[verts] - grip) - t[:, None] * axis, axis=1)
            lo, hi = float(t.min()), float(t.max())
            # the head: the end whose last fifth spreads widest round the axis
            def spread(sel):
                return float(np.percentile(r[sel], 90)) if sel.sum() >= 5 else 0.0
            span = hi - lo
            s_hi, s_lo = spread(t > hi - 0.2 * span), spread(t < lo + 0.2 * span)
            if hi < 0.12 * h or lo > -0.12 * h:      # held at one end: the far end is the head
                head_up = hi >= -lo
            else:
                head_up = s_hi >= s_lo
            if not head_up:
                axis, lo, hi, s_hi, s_lo = -axis, -hi, -lo, s_lo, s_hi
            carried = float((w[verts] >= 0.5).mean())
            carried_arm = float((w_arm[verts] >= 0.9).mean())
            dom = self.ji[verts, self.jw[verts].argmax(axis=1)]
            rest = [self.leaf[k] for k in dom if k not in (hj, fore_j)]
            others = ", ".join(f"{n} {rest.count(n) / len(verts):.0%}" for n in sorted(set(rest), key=rest.count,
                                                                                           reverse=True)[:3])
            out.append(dict(side=s, hand=hj, how=how, verts=verts, grip=grip, axis=axis, head=hi, butt=-lo,
                            spread_head=s_hi, spread_butt=s_lo, carried=carried, carried_arm=carried_arm,
                            others=others, pole=(-lo) >= 0.12 * h))
        self._weapons = out
        return out

    def weapon_facts(self, rig, anim, joints, frames):
        """Per weapon: its head's elevation (degrees above level) at the first
        frame, its lowest point over the frames (a share of the height), and
        the rows of it inside the body (the arm guard's measure: the thighs,
        the shins and the trunk, deeper than they lay in the bind)."""
        from scipy.spatial import cKDTree
        ws = self.weapons(rig)
        if not ws:
            return []
        body = self.weapon_body(rig)
        normals0 = character.vertex_normals(self.P.astype(np.float32), self.faces).astype(np.float64)
        out = []
        tree0 = cKDTree(self.P[body])
        posed = [(f, self.skin(w)) for f, w in self.worlds(anim, joints, frames)]
        for wp in ws:
            v = wp["verts"]
            d0, nn0 = tree0.query(self.P[v])
            s0 = np.einsum("ij,ij->i", self.P[v] - self.P[body][nn0], normals0[body][nn0])
            low, inside, elev = 1e9, 0, None
            for k, (f, Q) in enumerate(posed):
                g = Q[v].mean(axis=0)
                ax = unit((Q[v] - g).T @ ((self.P[v] - self.P[v].mean(axis=0)) @ wp["axis"]))
                if elev is None:
                    elev = math.degrees(math.asin(max(-1.0, min(1.0, float(ax[1])))))
                low = min(low, float(Q[v, 1].min() - self.P[:, 1].min()))
                nq = character.vertex_normals(Q.astype(np.float32), self.faces).astype(np.float64)
                dist, nn = cKDTree(Q[body]).query(Q[v])
                sd = np.einsum("ij,ij->i", Q[v] - Q[body][nn], nq[body][nn])
                through = (sd < np.minimum(s0, 0.0) - ARM_DEPTH * self.h) & (-sd >= 0.7 * dist)
                inside = max(inside, int(through.sum()))
            out.append(dict(side=wp["side"], elev=round(elev, 1), low=round(low / self.h, 3), inside=inside,
                            length=round((wp["head"] + wp["butt"]) / self.h, 2), pole=wp["pole"],
                            carried=round(wp["carried"], 2), how=wp["how"]))
        return out

    def weapon_body(self, rig):
        """The body a held weapon must stay out of: the thighs', the shins' and
        the trunk's own layer (character._limb_surface), owned by the legs or
        the trunk, and not the weapon itself."""
        if getattr(self, "_weapon_body", None) is not None:
            return self._weapon_body
        idx = {n: i for i, n in enumerate(self.leaf)}
        bpos = self.c.bind[:, 3, :3].astype(np.float64)
        dom = self.ji[np.arange(len(self.P)), self.jw.argmax(axis=1)]
        h = self.h
        normals = character.vertex_normals(self.P.astype(np.float32), self.faces).astype(np.float64)

        def at(j):
            return bpos[idx[rig.names[j]]]
        body = np.zeros(len(self.P), bool)
        for s in "LR":
            g = rig.leg[s]
            for a, b in ((g["upleg"], g["knee"]), (g["knee"], g["foot"])):
                if rig.names[a] in idx and rig.names[b] in idx:
                    body |= character._limb_surface(self.P, normals, at(a), at(b), reach=0.2 * h, gap=0.012 * h,
                                                    inward_stop=True)
        top = at(rig.chest) + np.array([0.0, 0.08 * h, 0.0])
        body |= character._limb_surface(self.P, normals, at(rig.hips) - np.array([0.0, 0.05 * h, 0.0]), top,
                                        reach=0.3 * h, gap=0.012 * h, inward_stop=False)
        trunk_j = {idx[rig.names[j]] for j in [rig.hips] + rig.spine if rig.names[j] in idx}
        leg_j = {idx[rig.names[v]] for s in "LR" for k, v in rig.leg[s].items() if k != "toes"
                 and rig.names[v] in idx}
        body &= np.isin(dom, list(trunk_j | leg_j))
        for wp in self.weapons(rig):
            body[wp["verts"]] = False
        self._weapon_body = np.flatnonzero(body)
        return self._weapon_body


def feet_drift(rig, anim):
    """The foot joints' largest travel over the loop (every key), from the written keys."""
    J = len(rig.names)
    first, worst = None, 0.0
    feet = [rig.leg[s]["foot"] for s in "LR"] + [t for s in "LR" for t in rig.leg[s]["toes"][:1]]
    for fr in range(len(anim["T"])):
        local = np.array([trs(anim["T"][fr, j], anim["R"][fr, j], anim["S"][fr, j]) for j in range(J)])
        W = world_from_local(local, rig.parents)
        now = W[feet, 3, :3]
        if first is None:
            first = now
        worst = max(worst, float(np.abs(now - first).max()))
    return worst


def loop_check(anim):
    """(closed, seam ratio): the last key is the first, and the step across
    the wrap (key F-1 to key F) is like the loop's own steps."""
    T, R = np.asarray(anim["T"], float), np.asarray(anim["R"], float)
    dT = float(np.abs(T[-1] - T[0]).max())
    dR = float((1 - np.abs(np.sum(R[-1] * R[0], axis=1))).max())
    closed = dT < 1e-5 and dR < 1e-7

    def step(a, b):
        d = np.abs(np.sum(R[a] * R[b], axis=1)).clip(0, 1)
        return float((2 * np.arccos(d)).max())
    steps = [step(k, k + 1) for k in range(len(R) - 1)]
    typical = float(np.percentile(steps, 90)) + 1e-9
    wrap = step(len(R) - 2, len(R) - 1)
    return closed, wrap / typical


def pose_facts(rig, anim, fr=0):
    """Readable pose numbers at one key: the upper arms' angle from straight
    down, the pelvis's tilt (against the bind's), where the weight sits between the feet (0 over
    the right foot, 1 over the left) and the hips' sway over the loop."""
    J = len(rig.names)

    def world(k):
        local = np.array([trs(anim["T"][k, j], anim["R"][k, j], anim["S"][k, j]) for j in range(J)])
        return world_from_local(local, rig.parents)
    W = world(fr)
    arms = []
    for s in "LR":
        a = rig.arm[s]
        v = unit(W[a["fore"], 3, :3] - W[a["upper"], 3, :3])
        arms.append(math.degrees(math.acos(max(-1.0, min(1.0, -v[1])))))
    hl, hr = W[rig.leg["L"]["upleg"], 3, :3], W[rig.leg["R"]["upleg"], 3, :3]
    # against the bind's own: Heimdall's rig sets its left hip joint 3 cm
    # higher than its right (9.7 degrees), which read as an 11.8 degree tilt
    # on a pelvis rolled 2 (the judge, 2026-09-25)
    bl, br = rig.pos0[rig.leg["L"]["upleg"]], rig.pos0[rig.leg["R"]["upleg"]]
    tilt = (math.degrees(math.atan2(hl[1] - hr[1], hl[0] - hr[0]))
            - math.degrees(math.atan2(bl[1] - br[1], bl[0] - br[0])))
    fl, fr_ = W[rig.leg["L"]["foot"], 3, :3], W[rig.leg["R"]["foot"], 3, :3]
    weight = (W[rig.hips, 3, 0] - fr_[0]) / max(fl[0] - fr_[0], 1e-6)
    hips = np.asarray(anim["T"])[:, rig.hips]
    return dict(arm_l=round(arms[0], 1), arm_r=round(arms[1], 1), hip_tilt=round(tilt, 1),
                weight=round(float(weight), 2), sway_cm=round(float(np.ptp(hips[:, 0])) * 100, 2))


# ---------------------------------------------------------------------------
# Choosing a family's idle
# ---------------------------------------------------------------------------

def carrier_for(family, bundle=None):
    """The skeleton the idle is written on: the family's freshest carrier
    that binds as its base does (a re-shipped base comes with a new combat
    idle; the old standing idle may be stale)."""
    bases = [Path(bundle) / f"{family}.usdz"] if bundle else []
    bases.append(APP_BUNDLE / f"{family}.usdz")
    base_path = next((b for b in bases if b.exists()), None)
    if base_path is None:
        raise FileNotFoundError(f"{family}: no shipped base")
    tried = []
    for folder in ([Path(bundle)] if bundle else []) + [APP_BUNDLE]:
        for clip in ("idle_combat", "idle"):
            path = folder / f"{family}_{clip}.usdz"
            if path.exists() and path not in tried:
                tried.append(path)
    base = quiet(character.read_usdz, str(base_path))
    body = character.body_joints(base)
    for path in tried:
        c = quiet(character.read_usdz, str(path))
        if list(c.joints) != body:
            continue
        dev = float(np.abs(c.bind - base.bind[:len(body)]).max())
        if dev <= 1e-3:
            c.bind_dev = dev
            return c, path, base_path
    raise ValueError(f"{family}: no carrier binds as the base does ({', '.join(p.name for p in tried)})")


def replaced_idle(family, against):
    """The idle the new one replaces (the tear guard's bar)."""
    for clip in ("idle", "idle_combat"):
        path = Path(against) / f"{family}_{clip}.usdz"
        if path.exists():
            return path
    return None


def chiastic_side(family):
    """The leg the chiasm puts the weight on: opposite the weapon hand; with
    no single weapon hand, the family's hash."""
    hand = mp.weapon_hand(family)
    if hand == "R":
        return "L"
    if hand == "L":
        return "R"
    return "L" if draw(family, "side", (0.0, 1.0)) < 0.5 else "R"


def sides_for(family):
    """(the side tried first and preferred, then the other): the chiastic
    side, unless OVERRIDES names a `side` (two figures of a row alike)."""
    first = override_for(family).get("side") or chiastic_side(family)
    return first, ("R" if first == "L" else "L")


def clear_the_hip(rig, p, stand):
    """The standing side's hip comes out under its hand (the pelvis goes over
    the standing foot and rolls up there), so that arm swings out by as much
    as the hip moved out under its shoulder - the style's own swing of the
    arm is kept, only the hip's coming is answered. Sets p["arm_out_<side>"]
    (degrees)."""
    p["arm_out_L"] = p["arm_out_R"] = 0.0
    sgn = 1.0 if stand == "L" else -1.0
    a, g = rig.arm[stand], rig.leg[stand]
    arm_len = float(np.linalg.norm(rig.pos0[a["hand"]] - rig.pos0[a["upper"]]))
    need = 0.0
    for t in np.linspace(0.0, p["loop"], 9)[:-1]:
        _, Pw = pose_at(rig, t, p, stand)
        hip = Pw[g["upleg"]][0] - rig.pos0[g["upleg"]][0]
        shoulder = Pw[a["upper"]][0] - rig.pos0[a["upper"]][0]
        need = max(need, sgn * (hip - shoulder))
    if need > 0:
        p["arm_out_" + stand] = math.degrees(math.atan2(need, arm_len)) * 1.15
    return p["arm_out_" + stand]


def swing_twist(Wm, axis):
    """(swing, twist) of a hand rotation `Wm` about the forearm's `axis`, in
    degrees: how far the hand bends off the forearm's line (a wrist's
    flexion and deviation, what reads as a broken wrist past ~40) and how far
    it turns about it (the forearm's pronation, which a fist hides)."""
    swing = math.degrees(math.acos(max(-1.0, min(1.0, float(axis @ (axis @ Wm))))))
    q = np.asarray(rot_to_quat(Wm), float)
    if q[3] < 0:
        q = -q
    proj = float(q[:3] @ axis)
    twist = abs(math.degrees(2 * math.atan2(abs(proj), q[3])))
    return swing, twist


def turn_onto(a0, c, f0):
    """Two hand rotations (bind frame) taking the weapon's axis `a0` onto `c`:
    the least turn, and a turn about the forearm `f0` (free) followed by the
    least bend off it - the first bends the wrist less for a small change,
    the second for a large one."""
    out = []
    ang = math.degrees(math.acos(max(-1.0, min(1.0, float(a0 @ c)))))
    out.append(about(np.cross(a0, c), ang) if ang > 1e-6 else np.eye(3))
    ap = a0 - (a0 @ f0) * f0
    cp = c - (c @ f0) * f0
    if np.linalg.norm(ap) > 1e-6 and np.linalg.norm(cp) > 1e-6:
        ap, cp = unit(ap), unit(cp)
        tau = math.degrees(math.atan2(float(np.cross(ap, cp) @ f0), float(ap @ cp)))
        T = about(f0, tau)
        a1 = a0 @ T
        sg = math.degrees(math.acos(max(-1.0, min(1.0, float(a1 @ c)))))
        out.append(T @ (about(np.cross(a1, c), sg) if sg > 1e-6 else np.eye(3)))
    return out


def stands_up(w, h):
    """A pole gripped between its ends, long, with a head (a spear, a
    trident, a bident, a guandao): it stands head up; else it hangs."""
    return bool(w["pole"] and w["head"] + w["butt"] >= POLE_LEN * h
                and w["spread_head"] >= HEAD_RATIO * max(w["spread_butt"], 1e-6))


def hang_targets(w, h, mode=None):
    """How a held weapon rests: "stand" - a pole gripped between its ends,
    long, with a head (a spear, a trident, a bident), stood head up like
    Pluto's and Frigg's; "hang" - a blade, an axe, a hammer, a club, a bolt,
    its head toward the floor by the thigh (the judge of 2026-09-25: a blade
    30-50 degrees tip down, a pole raised to 60-75). A pole that cannot
    stand hangs (`mode`). A hung head points forward, turned 0-40 degrees
    out, never in across the body.
    Returns (mode, elevations, leans, elbows, arm backs, the ideal
    elevation)."""
    if (mode or ("stand" if stands_up(w, h) else "hang")) == "stand":
        # the head's elevation; its lean (+ out, - toward the midline); the
        # elbow bent (the forearm forward, so a grip across the fist stands the
        # pole up); the arm forward (a negative back)
        return "stand", STAND_EL, (0.0, -25.0, 25.0), (0.0, 15.0, 30.0, 45.0, 60.0, 75.0), (0.0, -10.0), 68.0
    # the head forward, turned 0-40 degrees out (the boards of 2026-09-25:
    # straight out at 90 stuck a blade out sideways and wrung the wrist 80
    # degrees; trailing back at 135-180 turned Osiris's crook upside down,
    # cocked the sentinel's khopesh up behind him and pointed the butt of
    # Nezha's spear up at the lens - a grip that holds the head behind the
    # hip keeps the bind's)
    leans = (0.0, 20.0, 40.0) if w["pole"] else (0.0, 15.0, 30.0)
    return "hang", HANG_EL, leans, (0.0, -8.0), (0.0, 8.0), -42.0


def weapon_state(rig, base, p, stand, w):
    """(the head's elevation, the forearm's, the hand's height as a share of
    the height) of weapon `w` at the loop's first instant."""
    a = rig.arm[w["side"]]
    Rw, Pw = pose_at(rig, 0.0, p, stand)
    D_h = rig.rot0[a["hand"]].T @ Rw[a["hand"]]
    ax = unit(w["axis"] @ D_h)
    fore = unit(Pw[a["hand"]] - Pw[a["fore"]])
    feet_y = min(rig.pos0[rig.leg[s]["foot"]][1] for s in "LR")
    return (math.degrees(math.asin(max(-1.0, min(1.0, float(ax[1]))))),
            math.degrees(math.asin(max(-1.0, min(1.0, float(fore[1]))))),
            float((Pw[a["hand"]][1] - feet_y) / rig.height))


def pivot_for(w):
    """Where a weapon turns: at the WRIST when the hand carries it (its rows
    the hand owns half of or more), at the ELBOW when the forearm and the
    hand carry it between them (Poseidon's trident is 62% on the forearm:
    turned at the wrist it would break at the join), else nowhere - a
    weapon skinned to the thigh, the hips or a cloak (Baldr's spear,
    Neptune's trident) tears whichever joint turns it."""
    if w["carried"] >= CARRIED_MIN:
        return "hand"
    if w["carried_arm"] >= CARRIED_MIN:
        return "fore"
    return None


def hang_plans(rig, base, p, stand, w, mode=None):
    """The weapon's rests, cheapest first: every (elevation, lean, elbow,
    arm back) of its row turned into a rotation at its pivot (the wrist, or
    the elbow for a weapon the forearm carries) at the loop's first instant,
    each with the bend and turn it asks for, the lowest point of the
    weapon's axis, and a cost that prefers a straight wrist, the arm as the
    style left it and the row's ideal angle. A rest that bends the wrist
    past WRIST_SWING, turns it past WRIST_TWIST, bends the elbow past
    ELBOW_MAX or behind the body, or puts the weapon's end near the floor is
    not offered."""
    mode, els, leans, elbows, backs, ideal = hang_targets(w, base.h, mode)
    pivot = pivot_for(w)
    s = w["side"]
    a = rig.arm[s]
    ja, jf, jh = a["upper"], a["fore"], a["hand"]
    P0 = rig.pos0
    f0 = unit(P0[jh] - P0[jf])
    a0 = unit(w["axis"])
    out_x = 1.0 if s == "L" else -1.0                 # +X is the figure's left
    feet_y = min(P0[rig.leg[k]["foot"]][1] for k in "LR")
    if pivot == "fore":                               # the elbow's own turn does what the grid's elbows did
        elbows = (0.0,)
    plans = []
    for eb in elbows:
        for back in backs:
            q = dict(p)
            q["hang_elbow_" + s], q["hang_back_" + s] = eb, back
            q.pop("wrist_" + s, None)
            q.pop("fore_turn_" + s, None)
            Rw, Pw = pose_at(rig, 0.0, q, stand)
            D_f = rig.rot0[jf].T @ Rw[jf]
            upper = unit(Pw[jf] - Pw[ja])
            for el in els:
                for lean in leans:
                    hd = math.cos(math.radians(lean)) * Z + math.sin(math.radians(lean)) * out_x * X
                    b = math.cos(math.radians(el)) * hd + math.sin(math.radians(el)) * Y
                    c = unit(b @ D_f.T)
                    for Wm in turn_onto(a0, c, f0):
                        # where the turn is made: at the wrist alone (a
                        # weapon the hand carries), at the elbow alone (one
                        # the forearm carries a share of), or SPLIT - half of
                        # it at the elbow, the forearm turned, and the rest at
                        # the wrist (Thor's hammer tore the wrist's crease at
                        # a 37 degree bend that half of it would not)
                        for how in (("hand", "split") if pivot == "hand" else ("fore",)):
                            fore_rot = {"hand": np.eye(3), "split": slerp_rot(Wm, SPLIT), "fore": Wm}[how]
                            wrist_rot = Wm @ fore_rot.T
                            sw, tw = swing_twist(wrist_rot, f0)            # what the wrist is asked
                            fsw, ftw = swing_twist(fore_rot, f0)           # ... and the elbow
                            _, ttw = swing_twist(Wm, f0)                   # the forearm's whole turn about itself
                            D_new = Wm @ D_f
                            D_fore = fore_rot @ D_f
                            if ttw > WRIST_TWIST or (how != "fore" and sw > WRIST_SWING):
                                continue
                            if how != "hand":
                                # the forearm itself turns about the elbow: it
                                # must stay a forearm (bent 0-ELBOW_MAX off the
                                # upper arm, never behind the body or raised)
                                f_new = f0 @ D_fore
                                flex = math.degrees(math.acos(max(-1.0, min(1.0, float(upper @ f_new)))))
                                if flex > ELBOW_MAX or f_new[2] < -0.3 or f_new[1] > 0.2 or ftw > WRIST_TWIST:
                                    continue
                            hand_at = Pw[jf] + (P0[jh] - P0[jf]) @ D_fore
                            grip = hand_at + (w["grip"] - P0[jh]) @ D_new
                            ends = (grip + b * w["head"], grip - b * w["butt"])
                            low = (min(e[1] for e in ends) - feet_y) / base.h
                            if low < WEAPON_FLOOR + 0.02:
                                continue
                            bend = {"hand": sw, "split": sw + 0.5 * fsw, "fore": 0.5 * fsw}[how]
                            cost = bend + 0.3 * ttw + 0.4 * abs(eb) + 0.6 * abs(back) \
                                + 0.5 * abs(el - ideal)
                            plans.append(dict(cost=cost, mode=mode, pivot=how, el=el, lean=lean, elbow=eb,
                                              back=back, swing=round(sw if how != "fore" else fsw, 1),
                                              twist=round(ttw, 1),
                                              elbow_turn=round(fsw, 1) if how == "split" else None,
                                              low=round(low, 3),
                                              turn=tuple(tuple(round(float(x), 6) for x in r) for r in Wm),
                                              fore=tuple(tuple(round(float(x), 6) for x in r) for r in fore_rot)))
    plans.sort(key=lambda d: d["cost"])
    seen, out = set(), []
    for d in plans:                                   # one rest per angle, arm and pivot: the cheaper turn of the two
        k = (d["el"], d["lean"], d["elbow"], d["back"], d["pivot"])
        if k not in seen:
            seen.add(k)
            out.append(d)
    return out


def with_hang(p, side, plan):
    """p with the rest `plan` laid on: the forearm's turn (a split's half, or
    the whole of a forearm pivot's) and what is left of it at the wrist."""
    q = dict(p)
    q.pop("wrist_" + side, None)
    q.pop("fore_turn_" + side, None)
    total = np.asarray(plan["turn"], float)
    fore = np.asarray(plan.get("fore") if plan.get("fore") is not None else
                      (plan["turn"] if plan["pivot"] == "fore" else np.eye(3)), float)
    if plan["pivot"] != "hand":
        q["fore_turn_" + side] = tuple(tuple(float(x) for x in r) for r in fore)
    if plan["pivot"] != "fore":
        q["wrist_" + side] = tuple(tuple(round(float(x), 6) for x in r) for r in total @ fore.T)
    q["hang_elbow_" + side] = plan["elbow"]
    q["hang_back_" + side] = plan["back"]
    return q


def weapon_fails(facts, hung_sides):
    """The weapon guard: a HUNG weapon still within LEVEL_DEG of level as
    written (the arm's own guards moved the hand the rest was planned on:
    the smith's hammer planned at -30 came out at -14), its lowest point
    under WEAPON_FLOOR, or more than WEAPON_INSIDE of its rows deeper in the
    body than in the bind."""
    out = []
    for f in facts:
        if f["side"] not in hung_sides:
            continue
        if abs(f["elev"]) <= LEVEL_DEG:
            out.append(f"the {f['side']} weapon still level ({f['elev']:+.0f} deg)")
        if f["low"] < WEAPON_FLOOR:
            out.append(f"the {f['side']} weapon {f['low']:.3f} h off the floor")
        if f["inside"] > WEAPON_INSIDE:
            out.append(f"the {f['side']} weapon {f['inside']} rows in the body")
    return out


def hang_weapons(family, rig, base, pick, bar, verbose=False):
    """A weapon the pick holds LEVEL at the hip (its head within LEVEL_DEG
    of level, the forearm hanging) is hung by the thigh or stood up:
    hang_plans' rests tried cheapest first (HANG_TRIES), each through every
    guard of evaluate(), the tear held to `bar` (the file the idle
    replaces) and the weapon guard; the first that passes is kept. Returns
    (pick, note, facts): the pick unchanged where nothing hangs or nothing
    passes, and the note says why."""
    m, anim, p = pick
    stand = m["stand"]
    ws = base.weapons(rig)
    notes, hung = [], {}
    q = dict(p)
    for w in ws:
        s = w["side"]
        el0, fel, hy = weapon_state(rig, base, q, stand, w)
        what = f"{s} {'pole' if w['pole'] else 'blade'} {(w['head'] + w['butt']) / base.h:.2f} h"
        if abs(el0) > LEVEL_DEG:
            continue
        if fel > HANG_FOREARM or hy > HANG_HAND:
            notes.append(f"{what} level at {el0:+.0f} but not at the hip (the forearm at {fel:+.0f}, the hand "
                         f"{hy:.2f} h up): left as the bind holds it")
            continue
        if pivot_for(w) is None:
            notes.append(f"{what} level at {el0:+.0f}: the arm carries only {w['carried_arm']:.0%} of it (the rest "
                         f"skinned to {w.get('others') or 'the body'}): any turn would tear it - the weapon pass on "
                         f"the base first")
            continue
        # a pole stands first; one that cannot (a fist whose rows the thigh
        # holds a share of, a dress welded to the hand: Hades, Athena) hangs
        modes = ("stand", "hang") if stands_up(w, base.h) else ("hang",)
        order = []
        for mode in modes:
            plans = hang_plans(rig, base, q, stand, w, mode)
            # the cheapest rest of each arm (a stand: elbow, arm back) or each
            # angle (a hang) first, so the tries go wide before they go deep -
            # the rests of one arm tend to fail alike (the wrist's crease)
            group = ((lambda d: (d["elbow"], d["back"], d["pivot"])) if mode == "stand" else
                     (lambda d: (d["el"], d["pivot"])))
            firsts, seen = [], set()
            for d in plans:
                if group(d) not in seen:
                    seen.add(group(d))
                    firsts.append(d)
            order += (firsts + [d for d in plans if d not in firsts])[:HANG_TRIES]
        if not order:
            notes.append(f"{what} level at {el0:+.0f}: no rest within the wrist's reach and off the floor")
            continue
        why = []
        for plan in order:
            trial = with_hang(q, s, plan)
            _, mt, pt = evaluate(family, rig, base, trial, stand, samples=12, final=False)
            fails = list(mt["fails"])
            if bar is not None and mt["over3"] > bar:
                fails.append(f"{mt['over3']} edges past 3x against {bar}")
            if not fails:
                frames = measured_frames(pt, 12)
                keys = sample_keys(rig, pt, stand, frames)
                fails = weapon_fails(base.weapon_facts(rig, keys, rig.c.joints, np.arange(len(frames))), {s})
            if verbose:
                print(f"  {family} hang {s} {plan['mode']} el {plan['el']:+.0f} lean {plan['lean']:+.0f} elbow "
                      f"{plan['elbow']:+.0f} back {plan['back']:+.0f} wrist {plan['swing']}/{plan['twist']}: "
                      f"past3x {mt['over3']} {'; '.join(fails) or 'ok'}")
            if not fails:
                q = trial
                hung[s] = dict(plan, el0=round(el0, 1))
                break
            why.append(f"{plan['el']:+.0f}/{plan['lean']:+.0f}/{plan['elbow']:+.0f}: {fails[0]}")
        else:
            notes.append(f"{what} level at {el0:+.0f}: no rest passed ({'; '.join(why[:3])})")
    if not hung:
        return pick, "; ".join(notes), None
    anim_h, m_h, p_h = evaluate(family, rig, base, q, stand)
    facts = base.weapon_facts(rig, anim_h, rig.c.joints, measured_frames(p_h, 24))
    fails = list(m_h["fails"]) + weapon_fails(facts, set(hung))
    if bar is not None and m_h["over3"] > bar:
        fails.append(f"{m_h['over3']} edges past 3x against {bar}")
    if fails:
        notes.append(f"the hang failed as written ({'; '.join(fails)})")
        return pick, "; ".join(notes), None
    for k in ("stand", "chiastic", "preferred", "level", "bold"):
        if k in m:
            m_h[k] = m[k]
    words = []
    for s, h in hung.items():
        f = next(x for x in facts if x["side"] == s)
        words.append(f"{'stood' if h['mode'] == 'stand' else 'hung'} {s}: the head {h['el0']:+.0f} -> "
                     f"{f['elev']:+.0f} deg (lean {h['lean']:+.0f}, "
                     f"{dict(hand='wrist', fore='forearm', split='forearm ' + str(h.get('elbow_turn')) + ' + wrist')[h['pivot']]} "
                     f"bend {h['swing']:.0f}, turn "
                     f"{h['twist']:.0f}, elbow {h['elbow']:+.0f}, arm back {h['back']:+.0f}), its lowest "
                     f"{f['low']:.2f} h")
    m_h["hung"] = hung
    return (m_h, anim_h, p_h), "; ".join(words + notes), facts


ARM_STEP = 3.0          # degrees an arm swings out each time its hand is found in the body
ARM_TRIES = 4


def evaluate(family, rig, base, p, stand, samples=24, final=True):
    """Synthesised and measured; an arm whose hand the guard finds in the
    body is swung out ARM_STEP degrees and the stance made again, up to
    ARM_TRIES times, before the guard refuses it (the flourishes elsewhere
    are kept). A search reads only the measured keys (`final=False`, and
    `samples` of them); the stance kept is written whole and read again."""
    p = dict(p)
    clear_the_hip(rig, p, stand)
    frames = measured_frames(p, samples)
    for _ in range(ARM_TRIES + 1):
        keys = sample_keys(rig, p, stand, frames)
        m = base.measure(keys, rig.c.joints, rig, frames=frames)
        if m["through"] + m["through_held"] <= ARM_COUNT:
            break
        for side in "LR":
            if m["through_" + side] > ARM_COUNT // 3:
                p["arm_out_" + side] += ARM_STEP
    anim = None
    if final:
        anim, end_err = synthesize(rig, p, stand)
        m = base.measure(anim, rig.c.joints, rig)
        m["drift_mm"] = round(feet_drift(rig, anim) * 1000, 3)
        closed, seam = loop_check(anim)
        m.update(closed=closed, seam=round(seam, 2), end_err_mm=round(end_err * 1000, 3))
        m.update(pose_facts(rig, anim))
    fails = []
    if final and m["drift_mm"] > FOOT_DRIFT * 1000:
        fails.append(f"feet drift {m['drift_mm']:.2f} mm")
    if m["floor_mm"] > FLOOR_DRIFT * 1000:
        fails.append(f"a foot off the floor by {m['floor_mm']:.2f} mm")
    if m["sink_mm"] > 1000 * p.get("sink_ok", FLOOR_SINK * max(1.0, rig.height / 1.9)):
        fails.append(f"a foot {m['sink_mm']:.2f} mm into the floor")
    if m["through"] + m["through_held"] > ARM_COUNT:
        fails.append(f"arm through the body ({m['through']} arm, {m['through_held']} held, frame {m['through_frame']})")
    if final and not m["closed"]:
        fails.append("the loop does not close")
    if final and m["seam"] > 1.5:
        fails.append(f"the seam steps {m['seam']:.1f}x the loop's own step")
    m["fails"] = fails
    m["arm_out"] = {k: round(p["arm_out_" + k], 1) for k in "LR"}
    m["final"] = final
    return anim, m, p


# The flourishes tried one by one (the ones that make the pose); the rest are
# tried together after them.
MAIN_FLOURISHES = {"weight", "stand_in", "narrow", "roll", "lean", "reach", "reach_free", "blade", "arm_down", "arm_in",
                   "elbow", "arm_fwd", "free_arm_in", "free_elbow", "free_arm_fwd"}
# The order the flourishes are tried in from the plain stance, the ones that
# make the pose first: the weight, the stance, the lean and the knees, then
# the arms, then the rest.
FLOURISH_ORDER = ("weight", "stand_in", "narrow", "roll", "lean", "reach", "reach_free", "blade", "twist",
                  "head_face", "arm_down", "arm_in", "elbow", "arm_fwd", "free_arm_in", "free_elbow", "free_arm_fwd",
                  "clav_fwd", "chin", "head_turn", "head_tilt", "step", "turn_out")


def flourish_order(p_full, p_plain):
    keys = [k for k in p_full if k in p_plain and isinstance(p_full[k], (int, float))
            and not isinstance(p_full[k], bool) and abs(p_full[k] - p_plain[k]) > 1e-9
            and not k.startswith(("ph_", "arm_out_")) and k not in ("loop", "period", "frames")]
    return sorted(keys, key=lambda k: FLOURISH_ORDER.index(k) if k in FLOURISH_ORDER else len(FLOURISH_ORDER))


def choose(family, bundle=None, against=None, overrides=None, verbose=False, alt=False):
    """Every candidate measured; the one to ship and the facts of the choice
    (and, with `alt`, its weight-shift variant: result["alt"], the anim in
    result["alt_anim"])."""
    t0 = time.time()
    carrier, carrier_path, base_path = carrier_for(family, bundle)
    base = Base(base_path)
    rig = Rig(carrier, base.c)
    old_path = replaced_idle(family, against or APP_BUNDLE)
    old = None
    if old_path is not None:
        oc = quiet(character.read_usdz, str(old_path))
        old = base.measure(oc.anim, oc.joints, rig, arms=False)
        old["path"] = old_path.name
        old["seconds"] = round((len(oc.anim["T"]) - 1) / oc.anim["fps"], 2)
    first, other = sides_for(family)
    chi_side = chiastic_side(family)
    tried = []

    def run(p, stand, level, samples=24):
        anim, m, _ = evaluate(family, rig, base, p, stand, samples=samples, final=False)
        m.update(stand=stand, chiastic=stand == chi_side, preferred=stand == first, level=level)
        # The whole style must not tear more than the file it replaces (else
        # the flourishes go one at a time). The plain stance and the trials
        # are steps of the search, not files: the written pick is held to the
        # replaced file below. Were they held to it too, a re-ship over a
        # natural idle - which the plain stance under a robe tears more than
        # (Hera: 18 against the 7 shipped) - could never search its way back.
        if level == "full" and old is not None and m["over3"] > old["over3"]:
            m["fails"].append(f"tears more than the idle it replaces ({m['over3']} edges past 3x against {old['over3']})")
        tried.append((m, anim, p))
        if verbose:
            print(f"  {family} {level:14s} {stand}: past3x {m['over3']} ({m['max']}x) through {m['through']}/"
                  f"{m['through_held']} drift {m.get('drift_mm', '-')} floor {m['floor_mm']} {'; '.join(m['fails'])}")
        return m, anim, p

    def best(rows):
        """The side to keep: the preferred one (the chiastic, unless OVERRIDES
        names a side) unless the other tears less."""
        ok = [r for r in rows if not r[0]["fails"]]
        if not ok:
            return None
        chi = [r for r in ok if r[0]["preferred"]]
        low = min(ok, key=lambda r: (r[0]["over3"], r[0]["through"] + r[0]["through_held"], not r[0]["preferred"]))
        if chi and chi[0][0]["over3"] <= low[0]["over3"]:
            return chi[0]
        return low
    p_plain = dict(params_for(family, rig.height, level="plain", overrides=overrides), family=family)
    p_full = dict(params_for(family, rig.height, level="full", overrides=overrides), family=family)
    plain = best([run(p_plain, st, "plain") for st in (first, other)])
    full = best([run(p_full, st, "full") for st in (first, other)])
    bar = plain[0]["over3"] if plain else None
    pick, note = None, ""
    if full and (bar is None or full[0]["over3"] <= bar + FLOURISH_SLACK):
        pick = full
    elif plain:
        # the flourishes one at a time from the plain stance, on its side:
        # each kept whole, or at half, while the tear stays in the slack
        stand = plain[0]["stand"]
        cur, kept, held_back = dict(p_plain), [], []
        pick = plain
        keys = flourish_order(p_full, p_plain)
        main = [k for k in keys if k in MAIN_FLOURISHES]
        rest = [k for k in keys if k not in MAIN_FLOURISHES]
        for group in [[k] for k in main] + ([rest] if rest else []):
            for share, tag in ((1.0, ""), (0.5, " (half)")):
                trial = dict(cur)
                for key in group:
                    trial[key] = p_plain[key] + share * (p_full[key] - p_plain[key])
                name = group[0] if len(group) == 1 else "the rest"
                r = run(trial, stand, "+" + name + tag, samples=12)
                if not r[0]["fails"] and r[0]["over3"] <= bar + FLOURISH_SLACK:
                    cur, pick = trial, r
                    kept.append(name + tag)
                    break
            else:
                held_back.append(group[0] if len(group) == 1 else "the rest (" + ", ".join(group) + ")")
        pick = (pick[0], pick[1], cur)
        pick[0]["level"] = "partial" if kept else "plain"
        why = (f"the whole style tore {full[0]['over3']} against {bar}" if full else
               "the whole style failed its guards")
        note = f"{pick[0]['level']}: {why}; held back {', '.join(held_back) or '-'}"
    elif full:
        pick = full
        note = "full: the plain stance failed its guards"
    # the stance kept, written whole (every key) and measured again at 24 frames
    if pick is not None:
        level, stand = pick[0]["level"], pick[0]["stand"]
        anim, m, p_fin = evaluate(family, rig, base, pick[2], stand)
        if old is not None and m["over3"] > old["over3"]:
            m["fails"].append(f"tears more than the idle it replaces ({m['over3']} edges past 3x against {old['over3']})")
        if m["fails"] and level != "plain" and plain:
            note = f"plain: the {level} stance failed as written ({'; '.join(m['fails'])})"
            level, stand = "plain", plain[0]["stand"]
            anim, m, p_fin = evaluate(family, rig, base, plain[2], stand)
        m.update(stand=stand, chiastic=stand == chi_side, preferred=stand == first, level=level)
        if m["fails"]:
            tried.append((m, anim, p_fin))
            pick = None
        else:
            pick = (m, anim, p_fin)
    # a pick that tears nothing tries its row's BOLD numbers on the same leg,
    # and keeps them only if they still tear nothing, pass every guard and
    # push no more of the arm or the held piece into the body than the pick
    arch = arch_for(family)
    if pick is not None and arch in BOLD and pick[0]["level"] == "full" and pick[0]["over3"] == 0:
        stand = pick[0]["stand"]
        p_bold = dict(params_for(family, rig.height, level="full", overrides=overrides, bold=True), family=family)
        anim_b, m_b, p_b = evaluate(family, rig, base, p_bold, stand)
        m_b.update(stand=stand, chiastic=stand == chi_side, preferred=stand == first, level="full", bold=True)
        inside = m_b["through"] + m_b["through_held"]
        if not m_b["fails"] and m_b["over3"] == 0 and inside <= pick[0]["through"] + pick[0]["through_held"]:
            pick = (m_b, anim_b, p_b)
            note = "bold: the row's bolder contrapposto, still tearing nothing"
        else:
            tried.append((m_b, anim_b, p_b))
            why = "; ".join(m_b["fails"]) or (f"{m_b['over3']} edges past 3x" if m_b["over3"] else
                                              f"{inside} arm points in the body against "
                                              f"{pick[0]['through'] + pick[0]['through_held']}")
            note = f"bold tried and dropped ({why})"
    # a weapon held level at the hip is hung by the thigh, or stood up
    facts = None
    bar = old["over3"] if old is not None else None
    if pick is not None:
        pick, hang_note, facts = hang_weapons(family, rig, base, pick, bar, verbose)
        if hang_note:
            note = f"{note}; {hang_note}" if note else hang_note
        if facts is None and base.weapons(rig):
            facts = base.weapon_facts(rig, pick[1], rig.c.joints, measured_frames(pick[2], 24))
        pick[0]["weapons"] = facts or []
    result = dict(family=family, archetype=(overrides or {}).get("archetype") or arch_for(family),
                  carrier=carrier_path.name, base=base_path.name,
                  height=round(rig.height, 3), old=old, tried=[r[0] for r in tried], note=note,
                  seconds=round(time.time() - t0, 1), roles=rig.roles(),
                  bind_dev_mm=round(getattr(carrier, "bind_dev", 0.0) * 1000, 3))
    if pick is None:
        result["refused"] = sorted({f"{r[0]['level']} {r[0]['stand']}: {f}" for r in tried for f in r[0]["fails"]})
        return result, None, rig
    m, anim, p = pick
    result["pick"] = m
    result["params"] = {k: (round(v, 4) if isinstance(v, float) else v) for k, v in p.items()}
    if alt:
        result["alt"], result["alt_anim"] = make_alt(family, rig, base, pick, bar)
    return result, anim, rig


# ---------------------------------------------------------------------------
# The weight shift (PLAN.md step 5): the same idle on the other leg
# ---------------------------------------------------------------------------

BLEND_AT = (0.25, 0.5, 0.75)     # the blends the check reads
BLEND_DRIFT = 0.003              # m: a foot joint's travel off its spot in any blend (the plan: within 3 mm)
BLEND_AIM = 0.9                  # the search holds the measured keys to this share of it (every key is read after)
# The alt's pelvis travel past the centre and its roll, each a share of the
# main's. Two players blended move the pelvis on a straight line while the
# legs turn on arcs, so at the blend's middle the planted feet sink by about
# l (1 - cos(dtheta / 2)): 4.7-6.6 mm on Anubis, whose hips travel 17 cm
# between 0.71 over one foot and 0.71 over the other, and 15 mm on Loki's
# trickster hitch - the travel is most of it and the roll the rest, both
# growing as their square. So the most visible shift whose blend keeps the
# feet within BLEND_DRIFT is kept, the travel and the roll searched apart.
ALT_TRAVEL = (1.0, 0.9, 0.8, 0.7, 0.6, 0.5, 0.4, 0.3, 0.2, 0.1)
ALT_ROLL = (1.0, 0.75, 0.5)      # never under half: the hip rising over the other leg is the shift's clearest sign
ALT_MIN_WEIGHT = 0.53            # the alt stands at least this share of the way over its own foot (or as far as the
                                 # main does, a construct's 0.53-0.57)
ALT_TRIES = 8                    # candidates measured through the guards, the most visible first
ALT_WRITES = 3                   # ... of which written whole and blended at every key
# The widened rule (lane A, 2026-09-25), tried only where the 3 mm rule above
# finds no shift, so no alt that passes it changes. A blend's foot error is
# almost all SINK: the pelvis on its chord and the legs on their arcs take the
# feet down along the leg (Anubis at the ladder's floor: 3.0 mm down, 2.1 mm
# sideways, nothing up; the 32 feet refusals of phase 2 were 3.4-9 mm, every
# one of it down). A sole 5 mm into the floor is what the main idle itself is
# allowed (FLOOR_SINK, scaled for a giant, or the family's `sink_ok`), so a
# blend may SINK a foot joint that far - the mesh's lowest point is held to the
# same floor - while the joint still SLIDES (its distance off the spot across
# the floor) and rises no more than BLEND_DRIFT. The widened search reaches
# smaller shifts too, for the alts that tear more than their idle at the
# ladder's shares: the travel down to the centre (the weight at least leaves
# the standing leg, never past it) and the roll down to a quarter. Whatever it
# keeps must still change the hips VISIBLY: either hip joint's loop-mean moves
# ALT_VISIBLE of the height between the idle and the alt (the Terracotta
# Soldier's 2.0%, which the judge of phase 2 could not see, is under it; the
# Shabti's 2.5% is the least any shipped alt moves with no note).
ALT_WIDE_TRAVEL = ALT_TRAVEL + (0.0,)
ALT_WIDE_ROLL = ALT_ROLL + (0.25,)
ALT_VISIBLE = 0.025              # share of the height: the least hip change a widened alt may make
ALT_WIDE_TRIES = 64              # widened candidates measured through the guards, the most visible first (the
                                 # whole grid: a robe's tear falls only at the smallest shifts - Bragi's by the 30th)


def foot_positions(rig, anim):
    """(keys, feet, 3): the world positions of the foot and first toe joints
    at every key (feet_drift's joints)."""
    J = len(rig.names)
    feet = [rig.leg[s]["foot"] for s in "LR"] + [t for s in "LR" for t in rig.leg[s]["toes"][:1]]
    out = np.empty((len(anim["T"]), len(feet), 3))
    for fr in range(len(anim["T"])):
        local = np.array([trs(anim["T"][fr, j], anim["R"][fr, j], anim["S"][fr, j]) for j in range(J)])
        out[fr] = world_from_local(local, rig.parents)[feet, 3, :3]
    return out


def hip_means(rig, anim):
    """(2, 3): the two hip (upper-leg) joints' world positions, each averaged
    over the keys of `anim`."""
    J = len(rig.names)
    hips = [rig.leg[s]["upleg"] for s in "LR"]
    out = np.zeros((2, 3))
    for fr in range(len(anim["T"])):
        local = np.array([trs(anim["T"][fr, j], anim["R"][fr, j], anim["S"][fr, j]) for j in range(J)])
        out += world_from_local(local, rig.parents)[hips, 3, :3]
    return out / max(len(anim["T"]), 1)


def hip_shift(rig, main, alt):
    """How visibly the alt changes the hips: the larger distance either hip
    joint's loop-mean moves between the idle and the alt, a share of the
    height (the travel and the roll's flip together; ALT_VISIBLE)."""
    return float(np.linalg.norm(hip_means(rig, alt) - hip_means(rig, main), axis=1).max()) / rig.height


def sink_limit(rig, sink_ok=None):
    """The main idle's own floor limit (m): FLOOR_SINK, scaled for a giant,
    or the family's `sink_ok`."""
    return sink_ok if sink_ok is not None else FLOOR_SINK * max(1.0, rig.height / 1.9)


def feet_off(spots, moved):
    """How the foot joints leave their spots: (the 3 mm rule's drift - the
    largest travel along any axis - the SLIDE across the floor, the SINK
    into it and the RISE off it), in m."""
    d = moved - spots
    return (float(np.abs(d).max()), float(np.linalg.norm(d[..., [0, 2]], axis=-1).max()),
            float(max(0.0, -d[..., 1].min())), float(max(0.0, d[..., 1].max())))


def as_written(anim):
    """The loop as a written file carries it: the scales rounded to half
    floats (character.write_usdz writes a skeleton's scales as Vec3h)."""
    return dict(anim, S=np.asarray(anim["S"], np.float16).astype(np.float64))


def blend_anims(A, B, u):
    """B laid over A at blend factor `u`, as two animation players blend:
    each joint's translation and scale interpolated, its rotation slerped
    (the nearer hemisphere)."""
    qa = np.asarray(A["R"], float)
    qb = np.asarray(B["R"], float).copy()
    dot = np.sum(qa * qb, axis=-1)
    qb[dot < 0] *= -1
    dot = np.clip(np.abs(dot), -1.0, 1.0)
    th = np.arccos(dot)
    sin = np.sin(th)
    small = sin < 1e-6
    wa = np.where(small, 1.0 - u, np.sin((1.0 - u) * th) / np.where(small, 1.0, sin))
    wb = np.where(small, u, np.sin(u * th) / np.where(small, 1.0, sin))
    R = wa[..., None] * qa + wb[..., None] * qb
    R /= np.linalg.norm(R, axis=-1, keepdims=True)
    return {"T": (1.0 - u) * np.asarray(A["T"], float) + u * np.asarray(B["T"], float), "R": R,
            "S": (1.0 - u) * np.asarray(A["S"], float) + u * np.asarray(B["S"], float), "fps": A["fps"]}


def blend_check(rig, base, main, alt, bar=None, sink_ok=None, weapons=True, rule="3mm"):
    """The two variants blended at BLEND_AT: how far any foot joint leaves
    its spot (the main idle's own, at the same key), the feet's lowest point
    against the floor, the tear of the blended pose (clip_fix's measure) and,
    with `weapons`, each held weapon: a blend may push none deeper into the
    body, nor lower toward the floor, than the idle or its alt holds it (a
    wrist turned differently in the two slerps through poses of its own).
    The feet are held to the 3 mm rule (`rule` "3mm": every foot joint within
    BLEND_DRIFT along every axis) or the widened one ("wide": sliding and
    rising within BLEND_DRIFT, sinking within the main idle's floor limit).
    Returns (facts, fails)."""
    fails = []
    if len(main["T"]) != len(alt["T"]) or abs(main["fps"] - alt["fps"]) > 1e-6:
        return dict(drift_mm=None), [f"the two differ in length ({len(main['T'])} and {len(alt['T'])} keys)"]
    if rule != "3mm":
        # measured as the files will carry them: a USD skeleton's scales are
        # HALF floats, and a centimetre rig's root scale of 0.01 is written
        # 0.0100021 - the whole figure 0.02% larger about the floor, its soles
        # 0.2 mm lower than the in-memory loop's (the awakened Ares's blend
        # sank 4.87 mm here and 5.10 mm off the written pair). The widened rule
        # runs close to the floor limit by design; the 3 mm rule is left as
        # every shipped pair was made.
        main, alt = as_written(main), as_written(alt)
    spots = foot_positions(rig, main)
    drift, worst = 0.0, dict(over3=0, max=1.0, floor_mm=0.0, sink_mm=0.0)
    slide = dip = rise = 0.0
    per = {}
    held = base.weapons(rig) if weapons else []
    wf = np.unique(np.linspace(0, len(main["T"]) - 1, 12).round().astype(int))
    ends = {}
    if held:
        for tag, A in (("main", main), ("alt", alt)):
            for f in base.weapon_facts(rig, A, rig.c.joints, wf):
                ends.setdefault(f["side"], []).append(f)
    for u in BLEND_AT:
        B = blend_anims(main, alt, u)
        d, sl, dp, rs = feet_off(spots, foot_positions(rig, B))
        m = base.measure(B, rig.c.joints, rig, arms=False)
        per[u] = dict(drift_mm=round(d * 1000, 2), over3=m["over3"], slide_mm=round(sl * 1000, 2),
                      dip_mm=round(dp * 1000, 2))
        drift = max(drift, d)
        slide, dip, rise = max(slide, sl), max(dip, dp), max(rise, rs)
        worst = dict(over3=max(worst["over3"], m["over3"]), max=max(worst["max"], m["max"]),
                     floor_mm=max(worst["floor_mm"], m["floor_mm"]), sink_mm=max(worst["sink_mm"], m["sink_mm"]))
        for f in (base.weapon_facts(rig, B, rig.c.joints, wf) if held else []):
            e = ends.get(f["side"], [])
            deep = max((x["inside"] for x in e), default=0)
            low = min((x["low"] for x in e), default=f["low"])
            per[u]["weapon_" + f["side"]] = dict(inside=f["inside"], low=f["low"])
            if f["inside"] > deep:
                fails.append(f"the {f['side']} weapon {f['inside']} rows in the body at {int(u * 100)}% (the pair "
                             f"{deep})")
            if f["low"] < low - 0.01:
                fails.append(f"the {f['side']} weapon {f['low']:.3f} h off the floor at {int(u * 100)}%")
    sink = 1000 * sink_limit(rig, sink_ok)
    if rule == "3mm":
        if drift > BLEND_DRIFT:
            fails.append(f"a foot {drift * 1000:.1f} mm off its spot in the blend")
    else:
        if slide > BLEND_DRIFT:
            fails.append(f"a foot slides {slide * 1000:.1f} mm off its spot in the blend")
        if rise > BLEND_DRIFT:
            fails.append(f"a foot joint rises {rise * 1000:.1f} mm off its spot in the blend")
        if dip * 1000 > sink:
            fails.append(f"a foot joint sinks {dip * 1000:.1f} mm below its spot in the blend (against {sink:.1f})")
    if worst["floor_mm"] > FLOOR_DRIFT * 1000:
        fails.append(f"a foot {worst['floor_mm']:.2f} mm off the floor in the blend")
    if worst["sink_mm"] > sink:
        fails.append(f"a foot {worst['sink_mm']:.2f} mm into the floor in the blend")
    if bar is not None and worst["over3"] > bar:
        fails.append(f"the blend tears {worst['over3']} edges past 3x against {bar}")
    return dict(drift_mm=round(drift * 1000, 2), slide_mm=round(slide * 1000, 2), dip_mm=round(dip * 1000, 2),
                rise_mm=round(rise * 1000, 2), rule=rule, per=per, **worst), fails


def alt_params(p, stand, kt, kr=None):
    """The alt's numbers: the main's, on the main's foot spots (`feet_on`),
    the hunter's blade on the main's side (`blade_w`: the bow side leads
    whichever leg stands), the pelvis's travel past the centre at `kt` of the
    main's (the weight 0.5 + kt (w - 0.5) over the OTHER foot) and its roll at
    `kr` of the main's (`kt` when None)."""
    q = dict(p, feet_on=stand, blade_w=1.0 if stand == "L" else -1.0)
    q["weight"] = 0.5 + kt * (p["weight"] - 0.5)
    q["roll"] = (kt if kr is None else kr) * p["roll"]
    return q


def alt_candidates(rig, p, stand, rule="3mm"):
    """The (travel, roll) shares worth measuring, the most visible shift
    first: at each ALT_ROLL, every travel from the largest whose blend with
    the main keeps the feet within BLEND_AIM of BLEND_DRIFT on the measured
    keys down to ALT_MIN_WEIGHT (the drift grows with the travel, so the
    smaller pass too). Returns (candidates [(kt, kr, drift m)], the drift of
    the smallest travel tried at each roll where none passed).

    With `rule` "wide": every travel of ALT_WIDE_TRAVEL (and the ladder's
    floor) at every roll of ALT_WIDE_ROLL, each measured, kept where its
    blends hold the feet to BLEND_AIM of the widened rule (the slide and the
    rise to BLEND_DRIFT, the sink to the main idle's floor limit) and its hips
    change by ALT_VISIBLE of the height, the most visible (the measured hip
    change) first. Returns (candidates [(kt, kr, facts)], {roll: the least
    sliding visible travel's facts, or the reason none is visible})."""
    if rule != "3mm":
        return wide_candidates(rig, p, stand)
    other = "R" if stand == "L" else "L"
    frames = measured_frames(p, 24)
    main_keys = sample_keys(rig, p, stand, frames)
    spots = foot_positions(rig, main_keys)
    floor_kt = min(1.0, (ALT_MIN_WEIGHT - 0.5) / max(p["weight"] - 0.5, 1e-6))
    travels = sorted({kt for kt in ALT_TRAVEL if kt >= floor_kt - 1e-9} | {round(floor_kt, 4)}, reverse=True)
    out, first = [], {}
    for kr in ALT_ROLL:
        for i, kt in enumerate(travels):
            keys = sample_keys(rig, alt_params(p, stand, kt, kr), other, frames)
            drift = max(float(np.abs(foot_positions(rig, blend_anims(main_keys, keys, u)) - spots).max())
                        for u in BLEND_AT)
            first[kr] = (kt, drift)
            if drift <= BLEND_AIM * BLEND_DRIFT:
                out += [(k, kr, drift if k == kt else None) for k in travels[i:]]
                break
    # the most visible first: the hips' travel and the roll's flip, each a
    # share of the way from the main's to the mirror of it
    out.sort(key=lambda c: -(c[0] + c[1]))
    return out, first


def wide_candidates(rig, p, stand):
    """alt_candidates under the widened rule (see there and ALT_VISIBLE). A
    candidate's facts: its blends' worst slide, sink and rise (mm), its hip
    change (a share of the height) and whether it lies on the 3 mm rule's own
    ladder (`ladder`: the travel down to ALT_MIN_WEIGHT, the roll down to
    half) or is a smaller shift."""
    other = "R" if stand == "L" else "L"
    frames = measured_frames(p, 24)
    main_keys = sample_keys(rig, p, stand, frames)
    spots = foot_positions(rig, main_keys)
    hips0 = hip_means(rig, main_keys)
    lim = sink_limit(rig, p.get("sink_ok"))
    floor_kt = min(1.0, (ALT_MIN_WEIGHT - 0.5) / max(p["weight"] - 0.5, 1e-6))
    travels = sorted(set(ALT_WIDE_TRAVEL) | {round(floor_kt, 4)}, reverse=True)
    out, near = [], {}
    for kr in ALT_WIDE_ROLL:
        for kt in travels:
            keys = sample_keys(rig, alt_params(p, stand, kt, kr), other, frames)
            off = [feet_off(spots, foot_positions(rig, blend_anims(main_keys, keys, u))) for u in BLEND_AT]
            slide, dip, rise = (max(o[i] for o in off) for i in (1, 2, 3))
            shift = float(np.linalg.norm(hip_means(rig, keys) - hips0, axis=1).max()) / rig.height
            facts = dict(slide_mm=round(slide * 1000, 2), dip_mm=round(dip * 1000, 2), rise_mm=round(rise * 1000, 2),
                         shift=round(shift, 4), ladder=bool(kt >= floor_kt - 1e-9 and kr >= min(ALT_ROLL)))
            if shift < ALT_VISIBLE:
                near.setdefault(kr, dict(kt=kt, why=f"the hips change {shift * 100:.1f}% of the height"))
                continue
            if (slide <= BLEND_AIM * BLEND_DRIFT and rise <= BLEND_AIM * BLEND_DRIFT
                    and dip <= BLEND_AIM * lim):
                out.append((kt, kr, facts))
            elif kr not in near or near[kr].get("slide_mm", 1e9) > facts["slide_mm"] or "why" in near[kr]:
                near[kr] = dict(kt=kt, **facts)
    out.sort(key=lambda c: -c[2]["shift"])
    return out, near


def make_alt(family, rig, base, pick, bar):
    """The weight-shift variant of the pick: the same numbers, phases and
    length, the weight on the OTHER leg (the pelvis over it, rolled up there,
    the counter-roll and the head turned with it), both feet on the MAIN's
    spots (`feet_on`), the hung weapon turned as in the main - or, where the
    thigh now coming out under it would take it into the body, rested again
    on the alt's own pose (hang_plans; the blend check reads the weapon in
    between).

    The travel and the roll are searched apart (alt_candidates) and the most
    visible shift that passes is kept: every guard the main is held to, the
    tear to the main's own (and so to the file the main replaces), the
    weapon guard, and blend_check at every key. Only where the 3 mm rule
    finds nothing is the widened rule searched (ALT_VISIBLE's note: the feet
    may sink to the main idle's floor limit, and smaller shifts are tried
    while the hips still visibly change), so an alt the 3 mm rule passes is
    made exactly as before. The facts' `rule` says which passed: "3mm",
    "sink" (a shift on the 3 mm rule's own ladder, its feet sinking further),
    "ladder" (on that ladder and within 3 mm, found past its ALT_TRIES - a
    robe that tears less a few rungs down) or "smaller" (a smaller shift than
    that ladder reaches). Returns
    (facts, anim), anim None when nothing passes - the family keeps no alt."""
    facts, alt = alt_search(family, rig, base, pick, bar, "3mm")
    if alt is not None:
        return facts, alt
    wide, alt = alt_search(family, rig, base, pick, bar, "wide")
    if alt is not None:
        wide["refused_3mm"] = facts["fails"]
        return wide, alt
    wide["fails"] = [f"3 mm: {'; '.join(facts['fails'])}", f"widened: {'; '.join(wide['fails'])}"]
    wide["tried"] = (facts.get("tried") or []) + (wide.get("tried") or [])
    return wide, None


def alt_search(family, rig, base, pick, bar, rule):
    """make_alt's search under one rule ("3mm", or "wide": ALT_VISIBLE's
    note). Returns (facts, anim), anim None when nothing passes."""
    m, anim, p = pick
    stand = m["stand"]
    other = "R" if stand == "L" else "L"
    # the alt replaces no file: it tears no more than the idle it varies (nor
    # than the file that idle replaces) - Heracles's alt tore 20, the shipped
    # idle's count, over a main whose hung club had brought it to 9
    lim = m["over3"] if bar is None else min(bar, m["over3"])
    hung = m.get("hung") or {}
    cands, first = alt_candidates(rig, p, stand, rule)
    tried, written = [], 0
    if not cands and rule == "3mm":
        why = "; ".join(f"roll {kr:.2f}, travel {kt:.2f}: the blend's feet {d * 1000:.1f} mm"
                        for kr, (kt, d) in first.items())
        return dict(stand=other, scale=None, over3=None, hip_tilt=0.0, weight=0.0, blend={},
                    fails=[f"no shift keeps the feet within {BLEND_DRIFT * 1000:g} mm ({why})"]), None
    if not cands:
        why = "; ".join(f"roll {kr:.2f}, travel {n['kt']:.2f}: " + (
            n["why"] if "why" in n else f"the blend's feet slide {n['slide_mm']:.1f} mm, sink {n['dip_mm']:.1f} "
                                        f"mm (hips {n['shift'] * 100:.1f}%)") for kr, n in first.items())
        return dict(stand=other, scale=None, over3=None, hip_tilt=0.0, weight=0.0, blend={}, rule=rule,
                    fails=[f"no visible shift slides under {BLEND_DRIFT * 1000:g} mm and sinks within "
                           f"{sink_limit(rig, p.get('sink_ok')) * 1000:.1f} mm ({why})"]), None
    wbase = {w["side"]: w for w in base.weapons(rig)}
    for kt, kr, drift in cands[:ALT_TRIES if rule == "3mm" else ALT_WIDE_TRIES]:
        tag = f"travel {kt:.2f} roll {kr:.2f}"
        q = alt_params(p, stand, kt, kr)
        _, mq, pq = evaluate(family, rig, base, q, other, samples=12, final=False)
        fails = list(mq["fails"]) + ([f"{mq['over3']} edges past 3x against {lim}"] if mq["over3"] > lim else [])
        if fails:
            tried.append(f"{tag}: {fails[0]}")
            continue
        replanned = {}
        if hung:
            frames = measured_frames(pq, 12)
            wf = weapon_fails(base.weapon_facts(rig, sample_keys(rig, pq, other, frames), rig.c.joints,
                                                np.arange(len(frames))), set(hung))
            for s in sorted({x.split()[1] for x in wf}):
                ok = None
                for plan in hang_plans(rig, base, q, other, wbase[s], hung[s]["mode"])[:HANG_TRIES]:
                    trial = with_hang(q, s, plan)
                    _, mt, pt = evaluate(family, rig, base, trial, other, samples=12, final=False)
                    f2 = list(mt["fails"]) + ([f"{mt['over3']} past 3x"] if mt["over3"] > lim else [])
                    if not f2:
                        fr = measured_frames(pt, 12)
                        f2 = weapon_fails(base.weapon_facts(rig, sample_keys(rig, pt, other, fr), rig.c.joints,
                                                            np.arange(len(fr))), {s})
                    if not f2:
                        ok = (trial, plan)
                        break
                if ok is None:
                    break
                q = ok[0]
                replanned[s] = dict(el=ok[1]["el"], lean=ok[1]["lean"], pivot=ok[1]["pivot"])
            else:
                wf = []
            if wf and len(replanned) < len({x.split()[1] for x in wf}):
                tried.append(f"{tag}: {wf[0]}, and no rest of the alt's own passed")
                continue
        if written >= ALT_WRITES:
            break
        written += 1
        anim_a, m_a, p_a = evaluate(family, rig, base, q, other)
        fails = list(m_a["fails"])
        if m_a["over3"] > lim:
            fails.append(f"tears {m_a['over3']} edges past 3x against {lim}")
        if hung:
            fails += weapon_fails(base.weapon_facts(rig, anim_a, rig.c.joints, measured_frames(p_a, 24)), set(hung))
        if p_a["frames"] != p["frames"]:
            fails.append("its loop differs in length")
        blend, bf = blend_check(rig, base, anim, anim_a, lim, p.get("sink_ok"), rule=rule)
        fails += bf
        shift = hip_shift(rig, anim, anim_a)
        if rule != "3mm" and shift < ALT_VISIBLE:
            fails.append(f"the hips change {shift * 100:.1f}% of the height as written (under "
                         f"{ALT_VISIBLE * 100:g}%)")
        facts = dict(stand=other, scale=round(kt, 3), roll_share=kr, over3=m_a["over3"], max=m_a["max"],
                     drift_mm=m_a["drift_mm"], floor_mm=m_a["floor_mm"], sink_mm=m_a["sink_mm"],
                     through=m_a["through"], through_held=m_a["through_held"], hip_tilt=m_a["hip_tilt"],
                     weight=m_a["weight"], arm_out=m_a["arm_out"], blend=blend, fails=fails, tried=tried,
                     rehung=replanned, hip_shift=round(shift, 4),
                     rule="3mm" if rule == "3mm" else "smaller" if not drift["ladder"] else (
                         "sink" if blend["drift_mm"] > BLEND_DRIFT * 1000 else "ladder"),
                     sampled_drift_mm=(round(drift * 1000, 2) if isinstance(drift, float) else
                                       drift if isinstance(drift, dict) else None))
        if not fails:
            return facts, anim_a
        tried.append(f"{tag}: {fails[0]}")
    return dict(stand=other, scale=None, over3=None, hip_tilt=0.0, weight=0.0, blend={}, rule=rule,
                fails=[f"no shift passed ({'; '.join(tried[-3:])})"], tried=tried), None


# ---------------------------------------------------------------------------
# Writing
# ---------------------------------------------------------------------------

def write(family, rig, anim, bundle, also_combat=False, against=None, alt=None, alt_bar=None, alt_mode=False):
    """The idle written to `bundle` on its carrier (and the same file as the
    battle stance with `also_combat`), verified, and the guards run again on
    the WRITTEN file with the roll-out's own functions. The files are made in
    a work folder and copied into `bundle` only when every guard passes, and
    the files they replace are measured first - a ship into the app's own
    bundle overwrites them. Returns (problems, clip_fix's facts of the new
    file, alt): [] problems when shipped. With `alt` (make_alt's anim) the
    weight-shift variant is written as <family>_idle_alt.usdz beside it,
    through the same checks, its tear held to `alt_bar`; `alt` is then what
    became of it ("written", or why not). In `alt_mode` a family whose alt
    fails keeps no alt; out of it an alt already beside the idle is kept
    only while it still has the new idle's length and binds as the base does
    (an unchanged base re-derives the same idle key for key) - a stale one
    would blend with an idle it was not made beside."""
    import shutil
    import tempfile
    import clip_fix
    bundle = Path(bundle)
    bundle.mkdir(parents=True, exist_ok=True)
    against = Path(against or APP_BUNDLE)
    base_path = bundle / f"{family}.usdz"
    if not base_path.exists():
        base_path = APP_BUNDLE / f"{family}.usdz"
    clips = ["idle"] + (["idle_combat"] if also_combat else [])
    was = {}
    for clip in clips:
        old = replaced_idle(family, against) if clip == "idle" else against / f"{family}_{clip}.usdz"
        if old is not None and old.exists():
            was[clip] = (old.name, quiet(clip_fix.clip_stretch, str(base_path), str(old)))
    work = Path(tempfile.mkdtemp(prefix="natural_idle_"))
    try:
        if (bundle / f"{family}.usdz").exists():
            (work / f"{family}.usdz").symlink_to((bundle / f"{family}.usdz").resolve())
        c = copy.copy(rig.c)
        c.anim = anim
        c.name = family
        made = work / f"{family}_idle.usdz"
        character.write_usdz(c, made)
        written = [made]
        if also_combat:                          # the calm stance is the same file, byte for byte
            shutil.copyfile(made, work / f"{family}_idle_combat.usdz")
            written.append(work / f"{family}_idle_combat.usdz")
        facts = quiet(character.verify, made, check_bounds=False, quiet=True)
        problems = [f"{made.name}: {x}" for x in facts["problems"] if not x.startswith("feet at")]
        problems += mp.bind_against_base(work, family, clips)
        new = quiet(clip_fix.clip_stretch, str(base_path), str(made))
        for clip, (name, old) in was.items():
            if new["over3"] > old["over3"]:
                problems.append(f"{family}_{clip}.usdz: {new['over3']} edges past 3x against {old['over3']} in "
                                f"{name} (clip_fix.clip_stretch)")
        if not problems:
            for w in written:
                shutil.copyfile(w, bundle / w.name)
        alt_state = None
        stale = bundle / f"{family}_idle_alt.usdz"
        if alt is not None and not problems:
            ca = copy.copy(rig.c)
            ca.anim = alt
            ca.name = family
            made_alt = work / f"{family}_idle_alt.usdz"
            character.write_usdz(ca, made_alt)
            fa = quiet(character.verify, made_alt, check_bounds=False, quiet=True)
            aprob = [x for x in fa["problems"] if not x.startswith("feet at")]
            aprob += mp.bind_against_base(work, family, ["idle_alt"])
            na = quiet(clip_fix.clip_stretch, str(base_path), str(made_alt))
            if alt_bar is not None and na["over3"] > alt_bar:
                aprob.append(f"{na['over3']} edges past 3x against {alt_bar} (clip_fix.clip_stretch)")
            if not aprob:
                # the pair as written, blended as blendcheck reads it (the rule
                # it was made under, the feet, the floor, the tear, the weapon)
                mw, _ = load_clip(made)
                aw, _ = load_clip(made_alt)
                _, pf = pair_check(rig, Base(base_path), mw, aw, alt_bar, override_for(family).get("sink_ok"))
                aprob += [f"the written pair: {x}" for x in pf]
            if aprob:
                alt_state = "refused as written: " + "; ".join(aprob)
            else:
                shutil.copyfile(made_alt, stale)
                alt_state = "written"
        if alt_state != "written" and stale.exists() and not problems:
            keep = False
            if not alt_mode:
                old_alt = quiet(character.read_usdz, str(stale))
                keep = (len(old_alt.anim["T"]) == len(anim["T"])
                        and not mp.bind_against_base(bundle, family, ["idle_alt"]))
            if keep:
                alt_state = "the alt beside it kept (the same length, binding as the base)"
            else:
                stale.unlink()
                alt_state = (alt_state or "none") + "; the stale alt removed"
        return problems, new, alt_state
    finally:
        shutil.rmtree(work, ignore_errors=True)


def keep_held(family, bundle):
    """A held family's idle in `bundle`: today's file kept while it binds as
    the base does; when a re-shipped base has left it binding off (or it is
    missing beside a combat idle), today's derivation is made again - the
    combat idle stood up by tools/stand_idle.py. Returns what was done."""
    from stand_idle import stand
    bundle = Path(bundle)
    idle, guard = bundle / f"{family}_idle.usdz", bundle / f"{family}_idle_combat.usdz"
    if idle.exists():
        off = mp.bind_against_base(bundle, family, ["idle"])
        if not off:
            return "today's idle kept"
    elif not guard.exists():
        return "nothing here to keep"
    if not guard.exists():
        return f"today's idle binds off the base and there is no combat idle to stand up ({'; '.join(off)})"
    c = quiet(character.read_usdz, str(guard))
    stand(c, 1.0)
    c.name = family
    character.write_usdz(c, idle)
    facts = quiet(character.verify, idle, check_bounds=False, quiet=True)
    probs = [x for x in facts["problems"] if not x.startswith("feet at")]
    return "today's idle made again from the combat idle (tools/stand_idle.py)" + (
        f"; PROBLEMS: {'; '.join(probs)}" if probs else "")


# ---------------------------------------------------------------------------
# Commands
# ---------------------------------------------------------------------------

def families_in(folder=APP_BUNDLE):
    return sorted(p.name[:-len("_idle.usdz")] for p in Path(folder).glob("*_idle.usdz"))


def survey_line(r):
    fam, arch = r["family"], r["archetype"]
    old = r.get("old") or {}
    held = f"HELD ({r['held']}; {r.get('kept', 'not written')}), the retry measured: " if r.get("held") else ""
    if "pick" not in r:
        return f"{fam:22s} {arch:9s} {held}REFUSED: {'; '.join(r['refused'])}"
    m, p = r["pick"], r["params"]
    side = f"weight {m['stand']}" + ("" if m["chiastic"] else " (not chiastic)")
    other = ([t for t in r["tried"] if t["level"] == m["level"] and t["stand"] != m["stand"]]
             or [t for t in r["tried"] if t["level"] == "plain" and t["stand"] != m["stand"]])
    if other:
        side += f" [{other[0]['stand']}: {other[0]['over3']}{'*' if other[0]['fails'] else ''}]"
    return (f"{fam:22s} {arch:9s} {held}{side:24s} {p['loop']:4.1f} s {60 / p['period']:4.1f}/min  "
            f"feet {m['drift_mm']:.1f} mm floor +{m['floor_mm']:.1f}/-{m['sink_mm']:.1f} mm  "
            f"bind {r.get('bind_dev_mm', 0):.2f} mm  "
            f"loop {'closed' if m['closed'] else 'OPEN'} (seam {m['seam']:.2f})  "
            f"arms {'clear' if m['through'] + m['through_held'] == 0 else 'touch'} ({m['through']}/{m['through_held']})  "
            f"past3x {old.get('over3', '-'):>5} -> {m['over3']:4d} ({m['max']}x)  "
            f"arms {m['arm_l']:.0f}/{m['arm_r']:.0f} deg  tilt {m['hip_tilt']:+.1f}  "
            f"weight {m['weight']:.2f}{'  ' + r['note'] if r['note'] else ''}{weapon_words(m)}{alt_words(r)}")


def weapon_words(m):
    ws = m.get("weapons") or []
    if not ws:
        return ""
    return "  weapon " + ", ".join(f"{w['side']} {w['elev']:+.0f} deg, lowest {w['low']:.2f} h, {w['inside']} in"
                                   for w in ws)


def alt_words(r):
    a = r.get("alt")
    if not a:
        return ""
    b = a.get("blend") or {}
    if a.get("scale") is None:
        return f"  ALT {a['stand']} REFUSED ({'; '.join(a['fails'])})"
    head = (f"  ALT {a['stand']} (travel {a['scale']}, roll {a.get('roll_share')}, rule {a.get('rule', '3mm')}, hips "
            f"{a.get('hip_shift', 0) * 100:.1f}%): past3x {a['over3']} tilt "
            f"{a['hip_tilt']:+.1f} weight {a['weight']:.2f}, blend feet {b.get('drift_mm')} mm (slide "
            f"{b.get('slide_mm')}, sink {b.get('dip_mm')}) past3x {b.get('over3')}"
            + (f" rehung {a['rehung']}" if a.get("rehung") else ""))
    if a["fails"]:
        return head + f" REFUSED ({'; '.join(a['fails'])})"
    return head + (f" [{r['alt_written']}]" if r.get("alt_written") else "")


def process(family, bundle=None, also_combat=False, against=None, overrides=None, verbose=False, calm=(),
            alt=False):
    """One family chosen and, with `bundle`, written (the battle stance as
    well with `also_combat`, or when the family is in `calm`; the
    weight-shift variant with `alt`). A held family is measured with its
    retry and never written: its idle is kept_held."""
    held = hold_reason(family) if overrides is None else None
    try:
        r, anim, rig = choose(family, bundle, against, overrides, verbose, alt=alt)
    except Exception as e:  # noqa: BLE001 - one family must not stop the roster
        r, anim = dict(family=family, archetype=arch_for(family) or "?", refused=[f"failed: {e!r}"], tried=[]), None
    if held:
        r["held"] = held
        if bundle:
            r["kept"] = keep_held(family, bundle)
            stale = Path(bundle) / f"{family}_idle_alt.usdz"
            if stale.exists():                   # made beside a natural idle the held family no longer has
                stale.unlink()
                r["kept"] += "; the stale alt removed"
        return r
    alt_anim = r.pop("alt_anim", None)
    if anim is not None and bundle:
        bar = (r.get("old") or {}).get("over3", r["pick"]["over3"])
        problems, official, alt_state = write(family, rig, anim, bundle, also_combat or family in calm, against,
                                              alt=alt_anim, alt_bar=min(bar, r["pick"]["over3"]), alt_mode=alt)
        r["written"] = not problems
        r["combat"] = not problems and (also_combat or family in calm)
        r["official"] = official
        if alt:
            r["alt_written"] = alt_state
        if problems:
            r.pop("pick")
            r["refused"] = problems
    return r


def run_many(fams, jobs, **kw):
    if jobs > 1 and len(fams) > 1:
        from multiprocessing import Pool
        with Pool(jobs) as pool:
            return pool.starmap(_proc, [(f, kw) for f in fams])
    return [_proc(f, kw) for f in fams]


def _proc(f, kw):
    r = process(f, **kw)
    print(survey_line(r), file=sys.stderr, flush=True)      # progress; the table goes to stdout once, in order
    return r


def calm_stances(named):
    """The families of `named` whose battle stance is their natural idle
    (motion_palette's plan: `idle_combat=natural`, the 35 calm ones)."""
    calm = set(mp.natural_stances())
    return {f for f in named if f in calm}


def cmd_survey(a):
    fams = a.families or families_in()
    t0 = time.time()
    calm = calm_stances(fams) if a.calm_stances else set()
    results = run_many(fams, a.jobs, bundle=a.bundle, also_combat=a.also_combat, verbose=a.verbose, calm=calm,
                       alt=a.alt)
    order = {f: i for i, f in enumerate(fams)}
    results.sort(key=lambda r: order[r["family"]])
    for r in results:
        print(survey_line(r))
    held = [r for r in results if r.get("held")]
    done = [r for r in results if "pick" in r and not r.get("held")]
    today = sum((r.get("old") or {}).get("over3", 0) for r in results)
    new = sum(r["pick"]["over3"] for r in done)
    kept = sum((r.get("old") or {}).get("over3", 0) for r in held)
    worse = [r["family"] for r in done if r["pick"]["over3"] > (r.get("old") or {}).get("over3", 1 << 30)]
    none = sum(1 for r in done if r["pick"]["over3"] == 0)
    med_old = float(np.median([(r.get("old") or {}).get("max", 0) for r in done])) if done else 0
    med_new = float(np.median([r["pick"]["max"] for r in done])) if done else 0
    refused = [r for r in results if "pick" not in r and not r.get("held")]
    plain = [f"{r['family']} ({r['pick']['level']})" for r in done if r["pick"]["level"] != "full"]
    bold = [r["family"] for r in done if r["pick"].get("bold")]
    other = [r["family"] for r in done if not r["pick"]["chiastic"]]
    print(f"\n{len(results)} families, {len(done)} natural idles, {len(held)} held on today's idle, "
          f"{len(refused)} refused, {time.time() - t0:.0f} s at {FPS:g} keys a second")
    print(f"edges past 3x on the shipped bases: today's idles {today} (the plan measured {TODAY_TOTAL}), "
          f"the natural idles {new} (the prototype {PROTOTYPE_TOTAL}) and the held families' own {kept}, "
          f"{new + kept} as shipped; families with none {none} of {len(done)}; "
          f"median worst stretch {med_old:.1f}x -> {med_new:.1f}x; worse than today: {len(worse)} {worse}")
    print(f"held on today's idle: {len(held)} {[r['family'] for r in held]}")
    print(f"standing on the other side from the chiasm: {len(other)} {other}")
    print(f"flourishes held back (half or plain): {len(plain)} {plain}")
    print(f"the bolder row kept (it tears nothing): {len(bold)} {bold}")
    if a.bundle:
        combat = [r["family"] for r in done if r.get("combat")]
        print(f"written to {a.bundle}: {sum(1 for r in done if r.get('written'))} idles, and the battle stance of "
              f"{len(combat)} {combat}")
    roled = [r for r in results if r.get("roles")]
    odd = [r for r in roled if "neck" in r["roles"].get("spine", "").split("/")]
    print(f"joints found by position on {len(roled)} rigs: the head is the joint named Head on "
          f"{sum(1 for r in roled if r['roles'].get('head') == 'Head')}; the joint over the hips is named "
          f"`neck` on {len(odd)} ({', '.join(r['family'] for r in odd)}), where the spine read is "
          f"{sorted({r['roles']['spine'] for r in odd})} and the neck {sorted({r['roles']['neck'] for r in odd})}")
    hung = [r for r in done if r["pick"].get("hung")]
    print(f"weapons hung by the thigh or stood up: {len(hung)} "
          f"{[r['family'] + ':' + ','.join(r['pick']['hung']) for r in hung]}")
    level = [r for r in done if not r["pick"].get("hung") and any(
        abs(w["elev"]) <= LEVEL_DEG for w in r["pick"].get("weapons") or [])]
    print(f"weapons still within {LEVEL_DEG:g} deg of level: {len(level)} "
          f"{[level_word(r) for r in level]}")
    if getattr(a, "alt", False):
        alts = [r for r in results if r.get("alt")]
        ok_alt = [r for r in alts if not r["alt"]["fails"]]
        drifts = [r["alt"]["blend"]["drift_mm"] for r in ok_alt if r["alt"]["blend"].get("drift_mm") is not None]
        print(f"weight-shift alts: {len(ok_alt)} of {len(alts)} pass; blend drift {min(drifts or [0]):.2f}-"
              f"{max(drifts or [0]):.2f} mm (median {float(np.median(drifts or [0])):.2f}); the alts tear "
              f"{sum(r['alt']['over3'] for r in ok_alt)} and their blends {sum(r['alt']['blend']['over3'] for r in ok_alt)} "
              f"edges past 3x; refused: {[r['family'] for r in alts if r['alt']['fails']]}")
        for rule in ("3mm", "ladder", "sink", "smaller"):
            by = [r for r in ok_alt if r["alt"].get("rule", "3mm") == rule]
            if by:
                print(f"  by the {rule} rule: {len(by)} (the blends slide "
                      f"{max(r['alt']['blend'].get('slide_mm', 0) for r in by):.2f} mm and sink "
                      f"{max(r['alt']['blend'].get('dip_mm', 0) for r in by):.2f} mm at most; the hips change "
                      f"{min(r['alt'].get('hip_shift', 0) for r in by) * 100:.1f}-"
                      f"{max(r['alt'].get('hip_shift', 0) for r in by) * 100:.1f}% of the height) "
                      f"{[r['family'] for r in by] if rule != '3mm' else ''}")
    for r in refused:
        print(f"REFUSED {r['family']}: {'; '.join(r['refused'])}")
    if a.json:
        Path(a.json).write_text(json.dumps(results, indent=1, default=str))
        print("facts ->", a.json)
    return 1 if refused else 0


def level_word(r):
    return r["family"] + " " + ",".join(f"{w['side']}{w['elev']:+.0f}" for w in r["pick"]["weapons"])


def cmd_ship(a):
    if not a.bundle:
        sys.exit("ship writes only where --bundle names")
    fams = families_in() if a.all else a.families
    if not fams:
        sys.exit("name the families, or --all")
    calm = calm_stances(fams) if a.calm_stances else set()
    results = run_many(fams, a.jobs, bundle=a.bundle, also_combat=a.also_combat, calm=calm, alt=a.alt)
    for r in results:
        print(survey_line(r))
    held = [r for r in results if r.get("held")]
    bad = [r for r in results if "pick" not in r and not r.get("held")]
    for r in bad:
        print(f"PROBLEM {r['family']}: {'; '.join(r['refused'])}")
    ok = len(results) - len(bad) - len(held)
    combat = sum(1 for r in results if r.get("combat"))
    if a.alt:
        alts = [r for r in results if r.get("alt_written") == "written"]
        print(f"\nweight-shift alts written: {len(alts)}; none for "
              f"{[r['family'] + ' (' + '; '.join((r.get('alt') or {}).get('fails') or [str(r.get('alt_written'))]) + ')' for r in results if r.get('alt_written') != 'written' and not r.get('held')]}")
    print(f"\n{ok} natural idles written to {a.bundle} ({combat} as the battle stance too), {len(held)} held"
          f"{': ' + ', '.join(r['family'] + ' - ' + r.get('kept', '') for r in held) if held else ''}, "
          f"{len(bad)} refused{': ' + ', '.join(r['family'] for r in bad) if bad else ''}")
    return 1 if bad else 0


def load_clip(path):
    c = quiet(character.read_usdz, str(path))
    return c.anim, c.joints


def natural_anim(family, bundle=None):
    """The natural idle from `bundle` when it is there, else made now."""
    if bundle and (Path(bundle) / f"{family}_idle.usdz").exists():
        a, j = load_clip(Path(bundle) / f"{family}_idle.usdz")
        return a, j, None
    r, anim, rig = choose(family)
    if anim is None:
        return None, None, r
    return anim, rig.c.joints, r


def render_cells(base, anim, joints, frames, views, size):
    """[(frame, [one image per view])] of the base posed by the clip, and the cell width."""
    import preview
    from PIL import ImageDraw
    tex = preview.base_colour(base.c)
    width = int(round(size * 0.62))
    scale = 0.82 * size / max(base.h * 1.18, 1e-6)
    baseline = 0.06 * size
    out = []
    for f, w in base.worlds(anim, joints, frames):
        Q = base.skin(w)
        normals = character.vertex_normals(Q.astype(np.float32), base.faces).astype(np.float64)
        col = []
        for v in views:
            img = preview.render_view(Q, normals, base.faces, base.c.uvs, tex, v, scale, baseline, width, size, True)
            d = ImageDraw.Draw(img)
            d.line([(0, size - baseline), (width, size - baseline)], fill=(200, 60, 60), width=1)
            col.append(img)
        out.append((f, col))
    return out, width


def views_setup():
    import preview
    c35, s35 = math.cos(math.radians(35)), math.sin(math.radians(35))
    preview.VIEWS["q3"] = np.array([[c35, 0, -s35], [0, 1, 0], [s35, 0, c35]], float)   # the stages' three-quarter


def cmd_board(a):
    from PIL import Image, ImageDraw
    import preview
    views_setup()
    out_dir = Path(a.out)
    out_dir.mkdir(parents=True, exist_ok=True)
    views = ("front", "q3", "side")
    for fam in a.families:
        anim, joints, r = natural_anim(fam, a.bundle)
        if anim is None:
            print(f"{fam}: refused, no board ({'; '.join(r.get('refused', []))})")
            continue
        base_path = APP_BUNDLE / f"{fam}.usdz"
        base = Base(base_path)
        rig = Rig(quiet(character.read_usdz, str(carrier_for(fam)[1])), base.c)
        m = base.measure(anim, joints, rig)
        old_path = replaced_idle(fam, APP_BUNDLE)
        oa, oj = load_clip(old_path)
        om = base.measure(oa, oj, rig)
        F = len(anim["T"]) - 1
        fr = [int(round(x * F)) for x in (0.0, 0.25, 0.5, 0.75)]
        size = a.size
        old_cells, width = render_cells(base, oa, oj, [0], views, size)
        new_cells, _ = render_cells(base, anim, joints, fr, views, size)
        head = 46
        lab = 16
        cols = 1 + len(new_cells)
        sheet = Image.new("RGB", (cols * width + 30, head + len(views) * size + lab + 10), (24, 24, 28))
        d = ImageDraw.Draw(sheet, "RGB")
        facts = pose_facts(rig, anim)
        d.text((8, 4), f"{fam} ({arch_for(fam)}): natural idle {F / anim['fps']:.1f} s loop, "
                       f"edges past 3x {m['over3']} (worst {m['max']}x) against today's {om['over3']} ({om['max']}x); "
                       f"arms through the body {m['through']}/{m['through_held']}; feet planted",
               fill=(160, 230, 160), font=preview.font(14))
        d.text((8, 24), f"arms {facts['arm_l']:.0f}/{facts['arm_r']:.0f} deg from straight down, hips tilted "
                        f"{facts['hip_tilt']:+.1f} deg, the weight {facts['weight']:.2f} of the way to the left foot, "
                        f"the hips sway {facts['sway_cm']:.1f} cm. Rows: front, three-quarter, side.",
               fill=(220, 220, 200), font=preview.font(13))
        for ci, (f, col) in enumerate(old_cells + new_cells):
            x = 10 + ci * width + (10 if ci else 0)
            for vi, img in enumerate(col):
                sheet.paste(img, (x, head + vi * size))
            label = f"today's idle, {om['over3']} past 3x" if ci == 0 else f"{round(100 * f / F)}% ({f / anim['fps']:.1f} s)"
            d.text((x + 4, head + len(views) * size + 2), label, fill=(240, 220, 150), font=preview.font(13))
        path = out_dir / f"board_{fam}.jpg"
        sheet.save(path, quality=86)
        print(f"{fam}: board -> {path}  (past 3x {om['over3']} -> {m['over3']})")


def cmd_sheet(a):
    from PIL import Image, ImageDraw
    import preview
    views_setup()
    fams = [f for f in families_in() if arch_for(f) == a.archetype]
    cells = []
    size = a.size
    for fam in fams:
        anim, joints, r = natural_anim(fam, a.bundle)
        base = Base(APP_BUNDLE / f"{fam}.usdz")
        if anim is None:
            cells.append((fam, None, "REFUSED"))
            continue
        F = len(anim["T"]) - 1
        f = int(round(a.at * F))
        col, width = render_cells(base, anim, joints, [f], ("front", "q3"), size)
        rig = Rig(quiet(character.read_usdz, str(carrier_for(fam)[1])), base.c)
        facts = pose_facts(rig, anim, f)
        cells.append((fam + ("  HELD, the retry" if hold_reason(fam) else ""), col[0][1],
                      f"{F / anim['fps']:.1f} s  arms {facts['arm_l']:.0f}/{facts['arm_r']:.0f}  "
                      f"tilt {facts['hip_tilt']:+.0f}"))
    width = int(round(size * 0.62))
    per_row = a.per_row
    cw = 2 * width + 6
    rows = (len(cells) + per_row - 1) // per_row
    head, lab = 30, 34
    sheet = Image.new("RGB", (per_row * cw + 12, head + rows * (size + lab) + 6), (24, 24, 28))
    d = ImageDraw.Draw(sheet)
    d.text((8, 6), f"{a.archetype}: {len(fams)} rigs in the natural idle at {round(a.at * 100)}% of the loop "
                   f"(front, three-quarter)", fill=(160, 230, 160), font=preview.font(15))
    for i, (fam, imgs, label) in enumerate(cells):
        x = 6 + (i % per_row) * cw
        y = head + (i // per_row) * (size + lab)
        if imgs:
            sheet.paste(imgs[0], (x, y))
            sheet.paste(imgs[1], (x + width, y))
        d.text((x + 4, y + size + 1), fam, fill=(240, 220, 150), font=preview.font(15))
        d.text((x + 4, y + size + 17), label, fill=(200, 200, 200), font=preview.font(12))
    Path(a.out).parent.mkdir(parents=True, exist_ok=True)
    sheet.save(a.out, quality=86)
    print(f"{a.archetype}: {len(fams)} rigs -> {a.out}")


def cmd_gif(a):
    """Today's idle and the natural one moving side by side (three-quarter),
    one loop of the natural idle, today's looping under it."""
    from PIL import Image, ImageDraw
    import preview
    views_setup()
    out_dir = Path(a.out)
    out_dir.mkdir(parents=True, exist_ok=True)
    for fam in a.families:
        anim, joints, r = natural_anim(fam, a.bundle)
        if anim is None:
            print(f"{fam}: refused, no gif")
            continue
        base = Base(APP_BUNDLE / f"{fam}.usdz")
        oa, oj = load_clip(replaced_idle(fam, APP_BUNDLE))
        F, Fo = len(anim["T"]) - 1, len(oa["T"]) - 1
        n = a.frames
        size = a.size
        frames = []
        for k in range(n):
            t = k / n * F / anim["fps"]
            fn = int(round(k / n * F))
            fo = int(round((t * oa["fps"]) % max(Fo, 1)))
            new_cells, width = render_cells(base, anim, joints, [fn], ("q3",), size)
            old_cells, _ = render_cells(base, oa, oj, [fo], ("q3",), size)
            img = Image.new("RGB", (2 * width, size + 18), (24, 24, 28))
            img.paste(old_cells[0][1][0], (0, 0))
            img.paste(new_cells[0][1][0], (width, 0))
            d = ImageDraw.Draw(img)
            d.text((4, size + 2), f"today {Fo / oa['fps']:.2f} s loop", fill=(240, 220, 150), font=preview.font(12))
            d.text((width + 4, size + 2), f"natural {F / anim['fps']:.1f} s  {t:4.1f} s", fill=(160, 230, 160),
                   font=preview.font(12))
            frames.append(img)
        path = out_dir / f"{fam}_idle.gif"
        frames[0].save(path, save_all=True, append_images=frames[1:], duration=int(1000 * F / anim["fps"] / n),
                       loop=0, optimize=True)
        print(f"{fam}: gif -> {path}")


def pair_check(rig, base, main, alt, bar=None, sink_ok=None):
    """A written pair held to the rule it was made under: the 3 mm rule, or
    where that fails the widened one (the feet sinking to the floor limit, the
    hips changing ALT_VISIBLE of the height). Returns blend_check's (facts,
    fails) with the rule read and the hip change."""
    facts, fails = blend_check(rig, base, main, alt, bar, sink_ok)
    if fails:
        facts, fails = blend_check(rig, base, main, alt, bar, sink_ok, rule="wide")
    shift = hip_shift(rig, main, alt)
    facts["hip_shift"] = round(shift, 4)
    if facts.get("rule") == "wide" and shift < ALT_VISIBLE:
        fails.append(f"the hips change {shift * 100:.1f}% of the height (under {ALT_VISIBLE * 100:g}%)")
    return facts, fails


def _blend_row(fam, bundle):
    bundle = Path(bundle)
    try:
        main, joints = load_clip(bundle / f"{fam}_idle.usdz")
        alt, _ = load_clip(bundle / f"{fam}_idle_alt.usdz")
        carrier, _, base_path = carrier_for(fam, bundle)
        base = Base(base_path)
        rig = Rig(carrier, base.c)
        shipped = replaced_idle(fam, APP_BUNDLE)
        bar = None
        if shipped is not None:
            sa, sj = load_clip(shipped)
            bar = base.measure(sa, sj, rig, arms=False)["over3"]
        mm = base.measure(main, joints, rig, arms=False)
        ma = base.measure(alt, joints, rig, arms=False)
        lim = mm["over3"] if bar is None else min(bar, mm["over3"])      # make_alt's bar: the idle it varies
        facts, fails = pair_check(rig, base, main, alt, lim, override_for(fam).get("sink_ok"))
        if ma["over3"] > lim:
            fails.append(f"the alt tears {ma['over3']} edges past 3x against {lim}")
        return dict(family=fam, archetype=arch_for(fam), keys=len(main["T"]), main=mm["over3"], alt=ma["over3"],
                    shipped=bar, main_facts=pose_facts(rig, main), alt_facts=pose_facts(rig, alt), **facts,
                    fails=fails)
    except Exception as e:  # noqa: BLE001
        return dict(family=fam, fails=[f"failed: {e!r}"])


def cmd_blendcheck(a):
    """The written pairs in --bundle blended at BLEND_AT (the players' own
    sum: translations interpolated, rotations slerped): every foot joint
    against its spot, the feet against the floor, the blended pose's tear and
    the alt's own (neither over the idle's), and each held weapon in between."""
    bundle = Path(a.bundle)
    fams = a.families or sorted(p.name[:-len("_idle_alt.usdz")] for p in bundle.glob("*_idle_alt.usdz"))
    if a.jobs > 1 and len(fams) > 1:
        from multiprocessing import Pool
        with Pool(a.jobs) as pool:
            rows = pool.starmap(_blend_row, [(f, bundle) for f in fams])
    else:
        rows = [_blend_row(f, bundle) for f in fams]
    for r in rows:
        if "per" not in r:
            print(f"{r['family']:22s} FAILED: {'; '.join(r['fails'])}")
            continue
        per = "  ".join(f"{int(u * 100)}%: {v['drift_mm']:.2f} mm (slide {v.get('slide_mm', 0):.2f}, sink "
                        f"{v.get('dip_mm', 0):.2f})/{v['over3']}" for u, v in r["per"].items())
        print(f"{r['family']:22s} {r['archetype']:9s} {r['keys']} keys  weight {r['main_facts']['weight']:.2f} -> "
              f"{r['alt_facts']['weight']:.2f}, tilt {r['main_facts']['hip_tilt']:+.1f} -> {r['alt_facts']['hip_tilt']:+.1f}"
              f", hips {r.get('hip_shift', 0) * 100:.1f}%  past3x shipped {r['shipped']} main {r['main']} alt {r['alt']}"
              f"  blend {per}  floor +{r['floor_mm']:.2f}/-{r['sink_mm']:.2f} mm  rule {r.get('rule', '3mm')}  "
              f"{'PASS' if not r['fails'] else 'FAIL: ' + '; '.join(r['fails'])}")
    ok = [r for r in rows if "per" in r and not r["fails"]]
    strict = [r for r in ok if r.get("rule", "3mm") == "3mm"]
    wide = [r for r in ok if r.get("rule") == "wide"]
    drifts = [r["drift_mm"] for r in strict]
    print(f"\n{len(ok)} of {len(rows)} pairs pass: {len(strict)} blend within {BLEND_DRIFT * 1000:g} mm (the worst "
          f"drift {max(drifts or [0]):.2f} mm, median {float(np.median(drifts or [0])):.2f}), {len(wide)} by the "
          f"widened rule (slide {max([r['slide_mm'] for r in wide] or [0]):.2f} mm, sink "
          f"{max([r['dip_mm'] for r in wide] or [0]):.2f} mm at most; the hips "
          f"{min([r['hip_shift'] for r in wide] or [0]) * 100:.1f}% of the height at least); the blends tear "
          f"{sum(r['over3'] for r in ok)} edges past 3x (the mains {sum(r['main'] for r in ok)}, the alts "
          f"{sum(r['alt'] for r in ok)})")
    if a.json:
        Path(a.json).write_text(json.dumps(rows, indent=1, default=str))
    return 0 if len(ok) == len(rows) else 1


def cmd_altboard(a):
    """A weight-shift pair: the idle, its alt and the two blended half and
    half at the loop's start, then the idle and the alt at its middle - front,
    three-quarter and side - with the feet's spots marked."""
    from PIL import Image, ImageDraw
    import preview
    views_setup()
    out_dir = Path(a.out)
    out_dir.mkdir(parents=True, exist_ok=True)
    views = ("front", "q3", "side")
    for fam in a.families:
        bundle = Path(a.bundle)
        if not (bundle / f"{fam}_idle_alt.usdz").exists():
            print(f"{fam}: no alt in {bundle}")
            continue
        main, joints = load_clip(bundle / f"{fam}_idle.usdz")
        alt, _ = load_clip(bundle / f"{fam}_idle_alt.usdz")
        base = Base(APP_BUNDLE / f"{fam}.usdz")
        rig = Rig(quiet(character.read_usdz, str(carrier_for(fam)[1])), base.c)
        F = len(main["T"]) - 1
        mid = F // 2
        mix = blend_anims(main, alt, 0.5)
        cols = [("the idle, 0%", main, 0), ("the alt, 0%", alt, 0), ("blended 50/50, 0%", mix, 0),
                (f"the idle, 50% ({mid / main['fps']:.1f} s)", main, mid), ("the alt, 50%", alt, mid)]
        size = a.size
        cells = []
        for label, anim, fr in cols:
            c, width = render_cells(base, anim, joints, [fr], views, size)
            cells.append((label, c[0][1], pose_facts(rig, anim, fr)))
        facts, fails = pair_check(rig, base, main, alt, None, override_for(fam).get("sink_ok"))
        head, lab = 46, 30
        sheet = Image.new("RGB", (len(cells) * width + 20, head + len(views) * size + lab + 6), (24, 24, 28))
        d = ImageDraw.Draw(sheet, "RGB")
        d.text((8, 4), f"{fam} ({arch_for(fam)}): the weight shift - the idle and its alt on the other leg, the same "
                       f"foot spots; the blend's feet within {facts['drift_mm']} mm of them (slide "
                       f"{facts['slide_mm']}, sink {facts['dip_mm']}; rule {facts['rule']}); the hips change "
                       f"{facts['hip_shift'] * 100:.1f}% of the height{'' if not fails else '  FAILS: ' + fails[0]}",
               fill=(160, 230, 160) if not fails else (240, 140, 120), font=preview.font(14))
        d.text((8, 24), "blends 25/50/75%: " + ", ".join(f"{v['drift_mm']:.2f} mm (sink {v['dip_mm']:.2f}), "
                                                         f"{v['over3']} past 3x"
                                                         for v in facts["per"].values())
               + "; rows front, three-quarter, side", fill=(220, 220, 200), font=preview.font(13))
        for ci, (label, col, pf) in enumerate(cells):
            x = 10 + ci * width
            for vi, img in enumerate(col):
                sheet.paste(img, (x, head + vi * size))
            d.text((x + 4, head + len(views) * size + 1), label, fill=(240, 220, 150), font=preview.font(13))
            d.text((x + 4, head + len(views) * size + 16), f"weight {pf['weight']:.2f}, tilt {pf['hip_tilt']:+.1f}",
                   fill=(200, 200, 200), font=preview.font(12))
        path = out_dir / f"alt_{fam}.jpg"
        sheet.save(path, quality=86)
        print(f"{fam}: alt board -> {path}")


def set_fps(fps):
    """The keys a second every loop is written at (a module global, so the
    survey's workers inherit it)."""
    global FPS
    FPS = float(fps)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    s = sub.add_parser("survey", help="every family measured (and written, with --bundle)")
    s.add_argument("families", nargs="*")
    s.add_argument("--bundle", help="also write the natural idles here")
    s.add_argument("--also-combat", action="store_true")
    s.add_argument("--jobs", type=int, default=3)
    s.add_argument("--json")
    s.add_argument("--verbose", action="store_true")
    s.set_defaults(fn=cmd_survey)
    b = sub.add_parser("board", help="front, three-quarter and side at 0/25/50/75%% of the loop")
    b.add_argument("families", nargs="+")
    b.add_argument("--out", required=True)
    b.add_argument("--bundle", help="read the natural idles from here (else they are made now)")
    b.add_argument("--size", type=int, default=300)
    b.set_defaults(fn=cmd_board)
    h = sub.add_parser("sheet", help="one archetype's rigs in the natural idle at one instant")
    h.add_argument("archetype", choices=sorted(STYLES))
    h.add_argument("--out", required=True)
    h.add_argument("--bundle")
    h.add_argument("--at", type=float, default=0.25, help="the instant, a share of the loop")
    h.add_argument("--size", type=int, default=280)
    h.add_argument("--per-row", type=int, default=5)
    h.set_defaults(fn=cmd_sheet)
    g = sub.add_parser("gif", help="today's idle beside the natural one, moving")
    g.add_argument("families", nargs="+")
    g.add_argument("--out", required=True)
    g.add_argument("--bundle")
    g.add_argument("--frames", type=int, default=40)
    g.add_argument("--size", type=int, default=320)
    g.set_defaults(fn=cmd_gif)
    k = sub.add_parser("blendcheck", help="the written idle and alt pairs blended at 25/50/75%%: feet and tear")
    k.add_argument("families", nargs="*")
    k.add_argument("--bundle", required=True)
    k.add_argument("--jobs", type=int, default=3)
    k.add_argument("--json")
    k.set_defaults(fn=cmd_blendcheck)
    ab = sub.add_parser("altboard", help="the idle, its alt and their blend, front, three-quarter and side")
    ab.add_argument("families", nargs="+")
    ab.add_argument("--bundle", required=True)
    ab.add_argument("--out", required=True)
    ab.add_argument("--size", type=int, default=300)
    ab.set_defaults(fn=cmd_altboard)
    w = sub.add_parser("ship", help="write <family>_idle.usdz (and _idle_combat with --also-combat)")
    w.add_argument("families", nargs="*")
    w.add_argument("--all", action="store_true")
    w.add_argument("--bundle", required=True)
    w.add_argument("--also-combat", action="store_true")
    w.add_argument("--jobs", type=int, default=3)
    w.set_defaults(fn=cmd_ship)
    for q in (s, w):
        q.add_argument("--alt", action="store_true",
                       help="also write <family>_idle_alt.usdz: the same idle on the other leg, on the same foot spots, "
                            "of the same length (the weight shift, PLAN.md step 5); a family whose alt fails keeps none")
        q.add_argument("--calm-stances", action="store_true",
                       help="also write <family>_idle_combat.usdz for the families motion_palette's plan stands in "
                            "the natural idle in battle (the 35 calm sovereigns, graces and mystics)")
        q.add_argument("--fps", type=float, default=FPS, help=f"keys a second (default {FPS:g})")
    a = ap.parse_args()
    set_fps(a.fps if hasattr(a, "fps") else FPS)
    sys.exit(a.fn(a) or 0)


if __name__ == "__main__":
    main()
