#!/usr/bin/env python3
"""The motion palette: Meshy's preset clips bought ONCE on one live rig,
archived, and retargeted onto every family for nothing (2026-09-23).

Every family played the same few presets (meshy.py DEFAULT_CLIPS and
CLIP_SETS: every sword-bearer 219/242/102, every caster 129/125/126, every
victory 412, every battle stance 89), so the roster fought and cheered as
one body. Applying a preset through the Animation API costs 3 credits per
clip PER RIG, and a rig task lives about a week; a motion, though, is only
rotations, and tools/retarget.py already carries one from any Meshy rig to
any other (the five gods' bespoke clips, 2026-09-18). So a preset is bought
once on a donor, archived as Art/Motions/preset_<id>.motion.npz, and every
family takes its own combination from the archive (Docs/MOTION.md).

    python3 tools/motion_palette.py buy shield_maiden_serious 97 105 221 --floor 500 --cap 45
    python3 tools/motion_palette.py archive                 # every bought preset not archived yet
    python3 tools/motion_palette.py free 219 242 102        # archive presets some family's LIVE task already applied, for nothing
    python3 tools/motion_palette.py list                    # the palette: name, length, blow frame
    python3 tools/motion_palette.py ship tyr_serious tyr attack_basic=97 attack_heavy=237 ultimate=238 \
        idle_combat=85 victory=88 --bundle /tmp/scratch_bundle
    python3 tools/motion_palette.py board tyr attack_basic,attack_heavy --bundle /tmp/scratch_bundle --out tyr.jpg
    python3 tools/motion_palette.py compare 219 tyr_serious  # our retarget of the archive vs Meshy's own 219 on that rig
    python3 tools/motion_palette.py plan --markdown          # the deal as shipped (Docs/MOTION.md section 9)
    python3 tools/motion_palette.py roll --bundle Pantheon/Resources/Models --real --jobs 2   # ship the plan
    python3 tools/motion_palette.py roll loki surtr --bundle Pantheon/Resources/Models --real # a few families
    python3 tools/motion_palette.py breaks --out DIR [--idle-bundle DIR] --jobs 2 --json r.json  # every family's idle break
    python3 tools/motion_palette.py break-board hera ares --bundle DIR --out board.jpg       # the idle, then the break

The roll-out of 2026-09-24 (Docs/MOTION.md section 10): `plan` deals the pools,
then lays the board judgments over the deal (JUDGED, KEPT); `ship` mirrors a
preset swung in the other hand from the family's weapon (PRESET_SIDE,
WEAPON_HAND) on the donor before the retarget, re-makes clip_fix's judged fixes
(POSE_MIRROR, BOW_WRIST, SNOUT), canonicalises the rig at the height the family
shipped at, and refuses a carrier whose bind differs from the shipped base's.

`ship` writes nothing under Pantheon/ unless --bundle names it: the clips are
retargeted onto the family's rig GLB (Art/Models/<asset>.glb) in a work
folder and shipped by tools/mesh.py with its source and bundle folders
pointed there, so grounding, the carrier and the bind check are the same as
any Meshy clip's. A value may also be a .motion.npz path (a god's bespoke
clip). `idle=natural` is the stages' standing idle, built by
tools/natural_idle.py from the rig's own bind pose after the clips are in
(2026-09-25; `roll` passes it for every family), and `idle_combat=natural`
makes that same file the battle stance - the plan's calm families (CALM).
`idle=natural` also makes the weight-shift alt (<family>_idle_alt.usdz,
natural_idle.py --alt) and, beside the idle just made, the idle break
(`breaks` below); a refused idle takes both with it, since each was made
beside another idle. `idle_combat=ready:<guard>` (2026-09-25; the 73 the deal
left in the guard, READY_OVER) ships the guard - 89 raw, `half` or `stand` -
as the stance first, then tools/ready_stance.py writes the battle's ready
stance over it; refused, the guard stays, loudly. `idle=stand`
(tools/stand_idle.py's derivation of the idle_combat just shipped, the guard
stood up) is kept for the record; `stand` and `half` as a STANCE still stand
the guard up for the battle.

`breaks` (2026-09-25; Docs/PLAN.md, *Natural poses*, steps 7 and 8.3-8.4)
makes each family's idle break, <family>_break.usdz, from the bought presets'
calm windows (PRESET_CUTS' `brk`), dealt by archetype (BREAKS): laid over the
natural idle's mean pose rather than the donor's, its ends eased into that
pose, its feet planted on the idle's spots, quietened down a ladder where it
tears more than the idle (BREAK_LADDER); see make_break and break_for. A
break is made beside ONE idle (its report keeps the idle's hash): a re-shipped
idle wants its break made again, which `ship` (idle=natural), build_asset.sh
and proportions.sh do. BREAK_HOLD names the breaks a judge held (Nephthys).
"""
import argparse
import json
import os
import subprocess
import sys
import time
from datetime import datetime, timedelta, timezone
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
import character                                                          # noqa: E402

REPO = Path(__file__).resolve().parents[1]
ART = REPO / "Art" / "Models"
MOTIONS = REPO / "Art" / "Motions"
MANIFEST = MOTIONS / "palette.json"
WORK = Path(os.environ.get("PALETTE_WORK", "/tmp/motion_palette"))
LIVE_DAYS = 6          # a clip task younger than this still answers (Meshy keeps a rig about a week)
CONTRACT = {"attack_basic": 1.3, "attack_heavy": 1.7, "ultimate": 2.4, "victory": 2.0}   # AnimationClip.fallbackDuration
# BattleSceneController.contactFraction's defaults: where the game fires the
# damage, the flash and the hit-stop in a clip that has no row of its own.
# `ship` warps a palette clip so its blow lands HERE, so a family wearing it
# needs no Swift change.
DEFAULT_CONTACT = {"attack_basic": 0.42, "attack_heavy": 0.55, "ultimate": 0.62}

# How each preset is cut for the game, read off its board on the donor
# (board-archive, 2026-09-23): the frames kept [start, end] at 30 fps, the
# frame the blow lands (source frame), and whether it loops. Meshy authors
# most presets with a lead-in and a long settle - Charged Axe Chop kneels for
# three seconds before it rises, Double Blade Spin ends in a four-second
# crouch - and the game plays a one-shot inside 0.6-2x its contract
# (UnitNode.play), so the window keeps the action and drops the rest.
PRESET_CUTS = {
    # blade
    219: dict(blow=15),                          # Right-hand Sword Slash: one clean forehand cut
    97:  dict(window=(0, 66), blow=21),          # Left Slash: a wide backhand across the body
    242: dict(blow=36),                          # Charged Slash: a wind-up and a two-handed cut
    221: dict(window=(0, 66), blow=31),          # Charged Upward Slash: a crouch and a rising cut
    105: dict(window=(0, 100), blow=74),         # Triple Combo Attack: three cuts, the last the heaviest
    102: dict(blow=38),                          # Sword Judgment: a leap and a slam to one knee
    91:  dict(window=(0, 84), blow=46),          # Double Blade Spin: a spinning cut into a low finish
    86:  dict(window=(24, 120), blow=76),        # Jump Attack: a gather, a leap, the landing strike
    # heavy
    128: dict(blow=45, recover=20),              # Heavy Hammer Swing: overhead and down; ends bent double, so a recovery is added
    237: dict(window=(96, 176), blow=132),       # Charged Axe Chop: rises from the kneel, one chop
    127: dict(blow=50),                          # Charged Ground Slam: overhead, slammed to the floor
    238: dict(blow=27),                          # Axe Spin Attack: a turning swing
    # off hand and unarmed
    206: dict(blow=16),                          # Spartan Kick: a front push-kick
    220: dict(window=(4, 62), blow=32),          # Shield Push Left: the off hand shoved forward
    # casts
    129: dict(blow=29),                          # Mage Spell Cast: one arm raised, thrown forward
    125: dict(blow=57),                          # Charged Spell Cast: arms up, a crouch, up again
    126: dict(blow=74),                          # Charged Spell Cast 1: the long gather and release
    130: dict(window=(0, 80), blow=41),          # Mage Spell Cast 1: both arms flung wide
    133: dict(blow=29),                          # Mage Spell Cast 4: overhead, then a lunging thrust
    136: dict(window=(0, 64), blow=35),          # Mage Spell Cast 7: a two-handed push
    # archery
    224: dict(window=(50, 140), blow=117),      # Archery Shot: an arrow from the quiver, a full draw, the loose at f117
    226: dict(loop=True),                        # Archery Shot 2: a STATIC aim at full draw, never loosed (hands fixed 3.8 s) - a stance, not a shot
    222: dict(window=(110, 230), blow=205),     # Draw and Shoot from Back: the long draw and the loose at f205 (of 236)
    # stances (loop)
    89:  dict(loop=True),                        # Combat Idle: the crouched guard
    85:  dict(window=(140, 183), loop=True),     # Axe Stance: its calm tail (after the kneel and the raise), closed into a loop
    # victories
    412: dict(window=(40, 158)),                 # Victory: arms spread, then raised again and again
    298: dict(),                                 # Cheer with Both Hands Up: a hop with both arms up
    88:  dict(window=(0, 116)),                  # Chest Pound Taunt: fists to the chest, a roar
    # The fifteen bought for the natural poses (2026-09-24, Docs/PLAN.md,
    # *Natural poses*), cut 2026-09-25 off `board-archive` and a per-frame
    # read of each on the donor's shipped carrier (head, chest and pelvis
    # yaw, the hands over the hips, the mean joint angle to the natural
    # idle's mean pose, the speed). A BREAK is a one-shot laid over the
    # running idle (PoseLayer: in over 0.4 s, out over 0.5 s), so its window
    # starts and ends where the preset stands at rest - the pose `breaks`
    # measures every turn from (make_break, additive) - and holds the one
    # gesture between. `brk` marks an idle break's kind (BREAKS deals them): a
    # "look" may be quieted down to the head alone, a "gesture" keeps its arms.
    # breaks: the look-arounds (the content is the head's look)
    336: dict(window=(0, 152), brk="look"),      # Long Breathe and Look Around: a look left (f32-64), a look right with the hips (f104-136), back to the centre at f152 (5.1 s); the other 6 s repeat it
    338: dict(window=(0, 136), brk="look"),      # Short Breathe and Look Around: a look 31 degrees right (f40-80) and back, calm at f136 (4.5 s); f152-192 repeats the look
    335: dict(window=(0, 160), brk="look"),      # Axe Breathe and Look Around: a bladed, knees-bent axe stance throughout (feet 32 cm apart, the pelvis 50 degrees round); a look left (f36-60), then right (f84-120), back at f160 (5.3 s). It starts and ends in the axe stance, so only its turns are laid over the idle
    0:   dict(brk="look"),                       # Idle: stands, turns to look over the left shoulder (the head 104 degrees), then the right (134, the right heel up 5 cm, f24-60), back at f108 (4.0 s); f0 = f120
    2:   dict(brk="look"),                       # Alert: the weapon forward, a look 70 degrees right (f12-48), a crouch, a look 50 left (f84-96), back (4.0 s); f0 = f120
    334: dict(window=(84, 140), brk="look"),     # Lower Weapon, Look, Raise: from the guard, a turn to look back (f24-72), front with the weapon lowered (f84), a look about 60 degrees left (f96-132), the guard again from f144; the window is the lowered look (1.9 s) - the guard at both ends is the battle's
    # breaks: the gestures (the content is the arms)
    318: dict(brk="gesture"),                    # Scheming Hand Rub: a hunch over the hands rubbed at the waist (f14-66), up again, calm at f96 (3.3 s)
    12:  dict(brk="gesture"),                    # Idle 2: a stretch - the arms overhead (f24-72, the hands 57% of the height over the idle's), flung wide, a shoulder rolled - back in the stance at f156 (5.3 s)
    11:  dict(),                                 # Idle 1: the weapon held forward in the right hand, still (2.4 s): no gesture a break could carry (on Aphrodite it read as the idle); not dealt
    # stances (loop)
    377: dict(loop=True),                        # Relax Arms, Then Strike Battle Pose: the battle pose turned 40-60 degrees (f0-24), the arms relaxed (f36-48), the pose struck again (f60-120); f0 = f120, so it closes whole - the champion's stance, for step 4
    231: dict(loop=True),                        # Archery Aim with Lateral Scan: at full draw (f0-24), the bow lowered and a scan 100 degrees left and 56 right (f36-108), the draw again (f120); f0 = f150 - the archers' stance, for step 4
    # victories
    306: dict(),                                 # Cheer with One Hand Up: a crouch, a hop with the right arm up (the feet 37 cm off the floor at f16), back at f40 (1.7 s)
    403: dict(),                                 # Victory Fist Pump: both fists pumped at f12, settled by f40 (1.6 s)
    255: dict(),                                 # Angry Ground Stomp: the arms flung out and the left foot stamped (up 11 cm at f4 and f36), back at f42 (1.4 s); a lifted foot, so never a break (a break plants the feet)
    41:  dict(window=(30, 150)),                 # Formal Bow: stands (f0-40), a deep bow (f50-120), up by f140 (4.0 s); the stand after it is 3 s of nothing
}


def slerp(q0, q1, t):
    """Row-wise slerp of (N, 4) quaternions."""
    q0, q1 = np.asarray(q0, float), np.asarray(q1, float).copy()
    d = np.sum(q0 * q1, axis=-1)
    q1[d < 0] *= -1
    d = np.abs(d)[..., None]
    t = np.asarray(t, float)[..., None] if np.ndim(t) else t
    lin = d > 0.9995
    th = np.arccos(np.clip(d, -1, 1))
    sn = np.where(lin, 1.0, np.sin(th))
    a = np.where(lin, 1 - t, np.sin((1 - t) * th) / sn)
    b = np.where(lin, t, np.sin(t * th) / sn)
    out = a * q0 + b * q1
    return out / np.linalg.norm(out, axis=-1, keepdims=True)


def resample(anim, times):
    """The animation sampled at fractional source frames (T and S linear, R slerped)."""
    F = len(anim["T"])
    times = np.clip(np.asarray(times, float), 0, F - 1)
    i0 = np.floor(times).astype(int)
    i1 = np.minimum(i0 + 1, F - 1)
    w = times - i0
    T = anim["T"][i0] * (1 - w)[:, None, None] + anim["T"][i1] * w[:, None, None]
    S = anim["S"][i0] * (1 - w)[:, None, None] + anim["S"][i1] * w[:, None, None]
    R = np.stack([slerp(anim["R"][i0[k]], anim["R"][i1[k]], w[k]) for k in range(len(times))])
    return {"T": T, "R": R, "S": S, "fps": anim["fps"]}


def prepare(motion, clip, window=None, blow=None, loop=False, recover=0, crossfade=12, limits=(0.5, 2.0)):
    """A palette motion cut for one clip slot: trimmed to its window, its
    blow warped (piecewise-linear time, the length kept) onto the slot's
    default contact fraction, a loop's end blended into its start. Returns
    (Motion, facts)."""
    from retarget import Motion
    a = motion.anim
    F = len(a["T"])
    s, e = window or (0, F - 1)
    e = min(e, F - 1)
    anim = {k: np.asarray(a[k][s:e + 1], float) for k in ("T", "R", "S")}
    anim["fps"] = a["fps"]
    if recover:
        # A clip that ends in its follow-through (Heavy Hammer Swing ends bent
        # double) snapped back to the stance in the game's 0.16 s fade; the
        # last pose is eased back toward the first over `recover` frames.
        w = 0.5 - 0.5 * np.cos(np.pi * (np.arange(1, recover + 1) / recover))
        last = {k: anim[k][-1] for k in ("T", "R", "S")}
        first = {k: anim[k][0] for k in ("T", "R", "S")}
        tail = {"T": np.stack([last["T"] * (1 - x) + first["T"] * x for x in w]),
                "S": np.stack([last["S"] * (1 - x) + first["S"] * x for x in w]),
                "R": np.stack([slerp(last["R"], first["R"], x) for x in w])}
        for k in ("T", "R", "S"):
            anim[k] = np.concatenate([anim[k], tail[k]])
    N = len(anim["T"])
    facts = {"frames": N, "seconds": round(N / a["fps"], 2)}
    target = DEFAULT_CONTACT.get(clip)
    if recover:
        facts["recover"] = recover
    if blow is not None and target is not None and s <= blow <= e:
        b = blow - s
        bt = target * (N - 1)
        lo, hi = limits
        # speeds of the two halves; hold them inside the limits, moving the target as little as needed
        bt = min(max(bt, b / hi, (N - 1) - (N - 1 - b) / lo), b / lo, (N - 1) - (N - 1 - b) / hi)
        u = np.arange(N, dtype=float)
        src = np.where(u <= bt, u * (b / max(bt, 1e-9)), b + (u - bt) * ((N - 1 - b) / max(N - 1 - bt, 1e-9)))
        anim = resample(anim, src)
        facts.update(blow_source=round(b / (N - 1), 3), blow=round(bt / (N - 1), 3), target=target,
                     windup_speed=round(b / max(bt, 1e-9), 2), follow_speed=round((N - 1 - b) / max(N - 1 - bt, 1e-9), 2))
    elif blow is not None:
        facts["blow"] = round((blow - s) / max(N - 1, 1), 3)
    if loop and N > 2 * crossfade:
        k = crossfade
        head = {key: anim[key][:k].copy() for key in ("T", "R", "S")}
        tail = {key: anim[key][N - k:].copy() for key in ("T", "R", "S")}
        w = (np.arange(k) + 0.5) / k
        for key in ("T", "S"):
            anim[key][:k] = tail[key] * (1 - w)[:, None, None] + head[key] * w[:, None, None]
        anim["R"][:k] = np.stack([slerp(tail["R"][j], head["R"][j], w[j]) for j in range(k)])
        for key in ("T", "R", "S"):
            anim[key] = anim[key][:N - k]
        facts.update(frames=N - k, seconds=round((N - k) / a["fps"], 2), loop=True)
    contract = CONTRACT.get(clip)
    if contract:
        rate = facts["seconds"] / contract
        facts["rate"] = round(rate, 2)
        if not 0.6 <= rate <= 2.0:
            facts["warning"] = f"{facts['seconds']} s against a {contract} s contract: the game clamps at 0.6-2x and the blow drifts"
    m = Motion(motion.joints, motion.parents, motion.rest_local,
               {k: (v.astype(np.float32) if k != "fps" else v) for k, v in anim.items()}, motion.source)
    return m, facts


APP_BUNDLE = REPO / "Pantheon" / "Resources" / "Models"


def report_path(bundle, family):
    """Where a family's cut report goes: beside a scratch bundle, but never
    into the app's (a filesystem-synchronised group ships whatever is in it)."""
    bundle = Path(bundle).resolve()
    if bundle == APP_BUNDLE.resolve():
        return MOTIONS / "shipped" / f"{family}.json"
    return bundle / f"{family}.palette.json"


def archive_path(pid):
    return MOTIONS / f"preset_{int(pid)}.motion.npz"


def load_manifest():
    if MANIFEST.exists():
        return json.loads(MANIFEST.read_text())
    return {"note": "Meshy presets archived as motions (tools/motion_palette.py, Docs/MOTION.md)", "presets": {}}


def save_manifest(m):
    MOTIONS.mkdir(parents=True, exist_ok=True)
    tmp = MANIFEST.with_suffix(".tmp")
    tmp.write_text(json.dumps(m, indent=2, sort_keys=False) + "\n")
    tmp.replace(MANIFEST)


def now():
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def meshy_api():
    import meshy
    return meshy, meshy.Meshy(meshy.load_key(None))


def library_names(api):
    try:
        return {it["action_id"]: it.get("name", "") for it in api.library()}
    except SystemExit:
        return {}


# ---------------------------------------------------------------------------
# Buying and archiving
# ---------------------------------------------------------------------------

def cmd_buy(a):
    meshy, api = meshy_api()
    donor = meshy.load_manifest(a.donor) or sys.exit(f"no manifest for {a.donor}")
    rig = donor["stages"].get("rig") or {}
    if rig.get("status") != "SUCCEEDED":
        sys.exit(f"{a.donor} has no finished rig")
    names = library_names(api)
    m = load_manifest()
    start = api.balance()
    todo = [int(p) for p in a.presets if str(int(p)) not in m["presets"] or m["presets"][str(int(p))].get("status") in ("FAILED", "CANCELED", "EXPIRED")]
    price = 3 * len(todo)
    print(f"balance {start}; {len(todo)} preset(s) to apply on {a.donor} at 3 each = {price}")
    if price > a.cap:
        sys.exit(f"{price} credits is over the cap of {a.cap}")
    if start is not None and start - price < a.floor:
        sys.exit(f"the balance would fall to {start - price}, under the {a.floor} floor")
    for pid in todo:
        before = api.balance()
        if before is not None and before - 3 < a.floor:
            sys.exit(f"stopping: {before} would fall under the floor")
        tid = api.create("clip", {"rig_task_id": rig["id"], "action_id": pid})
        m["presets"][str(pid)] = {"name": names.get(pid, ""), "task": tid, "donor": a.donor, "rig_task": rig["id"],
                                  "status": "PENDING", "created": now(), "paid": True}
        save_manifest(m)
        print(f"  {pid:4d} {names.get(pid, ''):32s} task {tid}")
    wait(api, m, [str(p) for p in a.presets])
    end = api.balance()
    print(f"balance {start} -> {end} ({(start - end) if start is not None and end is not None else '?'} spent)")


def wait(api, m, keys):
    pending = [k for k in keys if m["presets"].get(k, {}).get("status") not in ("SUCCEEDED", "FAILED", "CANCELED", "EXPIRED")]
    t0 = time.time()
    while pending:
        for k in list(pending):
            st = m["presets"][k]
            d = api.task("clip", st["task"])
            st["status"] = d.get("status")
            if st["status"] in ("SUCCEEDED", "FAILED", "CANCELED", "EXPIRED"):
                pending.remove(k)
                print(f"  {k:>4s} {st['status']}  (+{int(time.time() - t0)}s)")
                if st["status"] != "SUCCEEDED":
                    st["error"] = (d.get("task_error") or {}).get("message", "")
        save_manifest(m)
        if pending:
            if time.time() - t0 > 3 * 3600:
                sys.exit("timed out; re-run `archive` later - the task ids are in the manifest")
            time.sleep(10)


def fetch_clip_glb(api, task_id, dest):
    import meshy
    import requests
    d = api.task("clip", task_id)
    urls = meshy.urls_in({"result": d.get("result")})
    url = next((u for k, u in urls.items() if k.endswith("animation_glb_url")), None)
    if not url:
        raise RuntimeError(f"task {task_id}: no animation GLB among {list(urls)}")
    dest.parent.mkdir(parents=True, exist_ok=True)
    with requests.get(url, stream=True, timeout=300) as r:
        r.raise_for_status()
        with open(dest, "wb") as f:
            for chunk in r.iter_content(1 << 20):
                f.write(chunk)
    return dest


def blow_frame(motion):
    """The frame a strike lands, estimated: the peak speed of the faster hand
    between a fifth and nine tenths of the clip (a slash's blade is fastest
    as it passes through the target; a cast's hands as they release). The
    boards are the judge; this is where they look first."""
    F = len(motion.anim["T"])
    hands = [motion.joint_index("righthand"), motion.joint_index("lefthand")]
    hands = [h for h in hands if h is not None]
    if F < 5 or not hands:
        return None, None
    pos = np.array([[motion.joint_world_at(f)[h][3, :3] for h in hands] for f in range(F)])   # F x H x 3
    speed = np.linalg.norm(np.diff(pos, axis=0), axis=2).max(axis=1)                          # F-1
    speed = np.convolve(speed, np.ones(3) / 3, mode="same")
    lo, hi = int(0.2 * F), max(int(0.9 * F), int(0.2 * F) + 1)
    f = lo + int(np.argmax(speed[lo:hi]))
    return f, f / max(F - 1, 1)


def archive_glb(glb, pid, record, keep=False):
    from retarget import load_source
    src = load_source(glb)
    src.source = f"meshy preset {pid} '{record.get('name', '')}' applied to {record.get('donor', '?')} (task {record.get('task', '?')})"
    out = archive_path(pid)
    src.save(out)
    F = len(src.anim["T"])
    fps = float(src.anim["fps"])
    f, frac = blow_frame(src)
    record.update(archived=str(out.relative_to(REPO)), frames=F, fps=fps, seconds=round(F / fps, 3),
                  blow_frame=f, blow_fraction=None if frac is None else round(frac, 3), archived_at=now())
    print(f"  {int(pid):4d} {record.get('name', ''):32s} {F:4d} frames {F / fps:5.2f} s  blow ~{f} ({frac if frac is None else round(frac, 2)})  -> {out.relative_to(REPO)}")
    if not keep:
        Path(glb).unlink(missing_ok=True)
    return out


def cmd_archive(a):
    _, api = meshy_api()
    m = load_manifest()
    keys = a.presets or [k for k, st in m["presets"].items() if st.get("status") == "SUCCEEDED" and not archive_path(k).exists()]
    wait(api, m, keys)
    for k in keys:
        st = m["presets"][k]
        if st.get("status") != "SUCCEEDED":
            print(f"  {k}: {st.get('status')} - nothing to archive")
            continue
        if archive_path(k).exists() and not a.force:
            continue
        glb = WORK / "downloads" / f"preset_{k}.glb"
        fetch_clip_glb(api, st["task"], glb)
        archive_glb(glb, k, st, keep=a.keep)
        save_manifest(m)


def cmd_free(a):
    """Presets some family's live task already applied: fetched again and
    archived for nothing. The donor is the newest live task with that id,
    the named --prefer donor first."""
    _, api = meshy_api()
    names = library_names(api)
    m = load_manifest()
    cutoff = datetime.now(timezone.utc) - timedelta(days=LIVE_DAYS)
    live = {}
    for p in ART.glob("*.meshy.json"):
        try:
            man = json.loads(p.read_text())
        except Exception:
            continue
        for key, st in man.get("stages", {}).items():
            if not key.startswith("clip:") or st.get("status") != "SUCCEEDED" or st.get("action_id") is None:
                continue
            created = st.get("created") or st.get("created_at") or ""
            try:
                when = datetime.strptime(created, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc)
            except ValueError:
                continue
            if when < cutoff:
                continue
            rank = (man["asset"] == a.prefer, when)
            best = live.get(st["action_id"])
            if best is None or rank > best[0]:
                live[st["action_id"]] = (rank, man["asset"], st["id"])
    for p in a.presets:
        pid = int(p)
        if archive_path(pid).exists() and not a.force:
            print(f"  {pid:4d} already archived")
            continue
        if pid not in live:
            print(f"  {pid:4d} no live task has applied it - `buy` it")
            continue
        _, asset, tid = live[pid]
        rec = m["presets"].setdefault(str(pid), {})
        rec.update(name=names.get(pid, rec.get("name", "")), task=tid, donor=asset, status="SUCCEEDED", paid=False)
        glb = WORK / "downloads" / f"preset_{pid}.glb"
        try:
            fetch_clip_glb(api, tid, glb)
        except (Exception, SystemExit) as e:                             # an expired task (meshy.call exits on a 404): say so and go on
            print(f"  {pid:4d} {asset}: {e}")
            continue
        archive_glb(glb, pid, rec, keep=a.keep)
        save_manifest(m)


def cmd_list(a):
    m = load_manifest()
    for k, st in sorted(m["presets"].items(), key=lambda kv: int(kv[0])):
        print(f"{int(k):4d} {st.get('name', ''):32s} {'paid' if st.get('paid') else 'free':4s} {st.get('seconds', '?'):>6} s  "
              f"blow {st.get('blow_fraction', '?')}  {st.get('donor', '')}  {'archived' if archive_path(k).exists() else st.get('status')}")


# ---------------------------------------------------------------------------
# Shipping onto a family
# ---------------------------------------------------------------------------

def motion_source(value):
    if value.endswith(".npz"):
        p = Path(value)
        return p if p.is_absolute() else REPO / p
    return archive_path(int(value))


STANCES_NOT_AT_REST = {"226"}


def mirror_motion(motion):
    """A palette motion reflected on its OWN (donor) rig, before it is cut
    and retargeted: every joint takes its partner's world-space turn since
    rest, reflected across the donor's sagittal plane, applied to its own
    rest (tools/clip_fix.py's "delta" mirror; a Meshy rig's rest is its
    bind). Mirrored here, the retarget carries it to the family like any
    preset and mesh.py grounds it on the family's own feet. The same mirror
    made on the family's carrier AFTER shipping (clip_fix's "pose" mode, as
    Hephaestus's and Skadi's were) leaves a foot 0.3 m off its place on a
    rig whose rest pose is asymmetric (the Minotaur's, 0.46 m) and puts the
    hooves 27 cm through the floor. -> (Motion, round-trip error in m)."""
    import copy
    import clip_fix
    from retarget import Motion

    class Rig:                                  # what mirror_anim reads of a character
        pass
    rig = Rig()
    rig.joints, rig.parents, rig.rest_local = motion.joints, motion.parents, np.asarray(motion.rest_local, dtype=np.float64)
    rig.anim = {k: (np.asarray(v, dtype=np.float64) if k != "fps" else v) for k, v in motion.anim.items()}
    rig.joint_world_at_rest = motion.joint_world_at_rest
    rig.bind = np.asarray(motion.joint_world_at_rest(), dtype=np.float64)
    anim, _ = clip_fix.mirror_anim(rig, "delta")
    twice = copy.copy(rig)
    twice.anim = anim
    back, _ = clip_fix.mirror_anim(twice, "delta")
    err = float(max(np.abs(np.asarray(back["T"]) - rig.anim["T"]).max(),
                    np.abs(np.abs(np.sum(np.asarray(back["R"]) * rig.anim["R"], axis=-1)) - 1).max()))
    return Motion(motion.joints, motion.parents, motion.rest_local, anim, motion.source + " (mirrored)"), err
SNOUT_CLIPS = ("attack_basic", "attack_heavy", "ultimate", "victory")


def bind_against_base(bundle, family, clips, tol=1e-3):
    """[problem lines] for each carrier of `clips` whose joints or bind differ
    from the shipped base's (body joints; the base may carry cape joints)."""
    import io
    import contextlib
    bundle = Path(bundle)
    base_path = bundle / f"{family}.usdz"
    if not base_path.exists():
        base_path = APP_BUNDLE / f"{family}.usdz"
    if not base_path.exists():
        return []
    with contextlib.redirect_stdout(io.StringIO()):
        base = character.read_usdz(str(base_path))
    body = character.body_joints(base)
    out = []
    for clip in clips:
        path = bundle / f"{family}_{clip}.usdz"
        if not path.exists():
            continue
        with contextlib.redirect_stdout(io.StringIO()):
            c = character.read_usdz(str(path))
        if list(c.joints) != body:
            out.append(f"{path.name}: joints differ from the base's")
            continue
        d = np.abs(c.bind - base.bind[:len(body)]).max(axis=(1, 2))
        if d.max() > tol:
            out.append(f"{path.name}: bind {d.max():.3f} off the base's at {c.joints[int(d.argmax())].split('/')[-1]}")
    return out


def stand_in_place(bundle, family, clip, keep=1.0):
    """tools/stand_idle.py's sum on one carrier, written as <family>_idle."""
    import io
    import contextlib
    from stand_idle import stand
    with contextlib.redirect_stdout(io.StringIO()):
        c = character.read_usdz(str(Path(bundle) / f"{family}_{clip}.usdz"))
    stand(c, keep)
    c.name = family
    out = Path(bundle) / f"{family}_idle.usdz"
    character.write_usdz(c, out)
    facts = character.verify(out, check_bounds=False, quiet=True)
    probs = [p for p in facts["problems"] if not p.startswith("feet at")]
    if probs:
        print(f"  PROBLEMS in {out.name}: {'; '.join(probs)}")


def post_fixes(family, bundle, assign, report):
    """tools/clip_fix.py's judged fixes, re-made on the palette's carriers
    (2026-09-24), after the mirror (made before the retarget, mirror_motion):
    the bow hand's wrist bent on a mirrored archer's clips (BOW_WRIST, at the
    clip's own blow, which the cut has moved to the slot's contact
    fraction), and a long snout lifted off the chest (SNOUT). Returns a line
    per fix; each clip's facts go into its report entry."""
    import clip_fix
    bundle = Path(bundle)
    mirror = [c for c, r in report.items() if r.get("mirrored")]
    base = None
    done = []
    for clip in dict.fromkeys(LATERAL_CLIPS + SNOUT_CLIPS):
        path = bundle / f"{family}_{clip}.usdz"
        if clip not in assign or not path.exists():
            continue
        if clip in mirror:
            done.append(f"{clip} mirrored to the {'left' if weapon_hand(family) == 'L' else 'right'} hand")
        pid = str(assign.get(clip, "")).split("@")[0]
        do_pose = pid.isdigit() and (family, int(pid)) in POSE_MIRROR
        do_wrist = clip in mirror and family in BOW_WRIST
        do_snout = family in SNOUT and clip in SNOUT_CLIPS
        if not (do_pose or do_wrist or do_snout):
            continue
        c = clip_fix.read(path)
        facts = {}
        if do_pose:
            anim, f = clip_fix.mirror_anim(c, "pose")
            worst, who = clip_fix.check_mirror(c, anim, "pose")
            c.anim = anim
            facts["mirrored"] = dict(mode="pose, on the carrier", weapon_hand=weapon_hand(family),
                                     off_reflection_mm=round(worst * 1000), worst_joint=who, rest_asymmetry_m=f["asymmetry_m"])
            done.append(f"{clip} mirrored on the carrier (pose; {worst * 1000:.0f} mm off the reflection at {who})")
        if do_wrist:
            if base is None:
                own = bundle / f"{family}.usdz"
                base = clip_fix.read(own if own.exists() else APP_BUNDLE / f"{family}.usdz")
            F = len(c.anim["T"])
            b = report.get(clip, {}).get("blow")
            blow = int(round(b * (F - 1))) if b is not None else F // 2
            c.anim, hand, tilt, ext = clip_fix.bow_wrist(c, base, blow)
            facts["bow_wrist"] = dict(hand=hand, degrees=round(tilt), frame=blow)
            done.append(f"{clip} bow wrist {hand} {tilt:.0f} deg at f{blow}")
        if do_snout:
            c.anim, before, after = clip_fix.lift_snout(c, SNOUT[family])
            facts["snout"] = dict(limit=SNOUT[family], closest_before=round(before), closest_after=round(after))
            if before < SNOUT[family]:
                done.append(f"{clip} snout {before:.0f} -> {after:.0f} deg")
        c.name = family
        probs = clip_fix.write_carrier(c, path)
        if probs:
            facts["problems"] = probs
        report.setdefault(clip, {}).update(facts)
    return done


def cmd_ship(a):
    rig = ART / f"{a.asset}.glb"
    if not rig.exists():
        sys.exit(f"no rig {rig.relative_to(REPO)} (meshy.py download {a.asset})")
    bundle = Path(a.bundle).resolve()
    if bundle == APP_BUNDLE.resolve() and not a.real:
        sys.exit("that is the app's bundle; pass --real to write it")
    src_dir = WORK / "src" / a.asset
    src_dir.mkdir(parents=True, exist_ok=True)
    bundle.mkdir(parents=True, exist_ok=True)
    link = src_dir / f"{a.asset}.glb"
    if not link.exists():
        link.symlink_to(rig)
    from retarget import Motion
    assign = dict(item.split("=", 1) for item in a.assign)
    idle_mode = assign.pop("idle", None)
    if idle_mode not in (None, "stand", "natural"):
        sys.exit(f"idle={idle_mode}: the stages' idle is `natural` (tools/natural_idle.py) or `stand` (the guard stood up)")
    natural = idle_mode == "natural"
    stand = idle_mode == "stand"
    stance = assign.get("idle_combat")
    ready_guard = None
    if stance is not None and stance.split(":")[0] == "ready":
        # the battle's ready stance (tools/ready_stance.py): its guard (89 raw,
        # half or stand) is shipped first as the stance - the carrier the
        # ready stance is read from, and the fallback where it is refused
        ready_guard = stance.partition(":")[2] or "89"
        if ready_guard not in READY_OVER:
            sys.exit(f"idle_combat={stance}: a ready stance is made over 89, half or stand")
        stance = ready_guard
        assign["idle_combat"] = ready_guard
    natural_stance = stance == "natural"
    if natural_stance:
        # the stance IS the natural idle: the guard is retargeted only as the
        # carrier mesh.py writes this rig's skeleton on, and
        # tools/natural_idle.py writes the idle over it as both files
        assign["idle_combat"] = "89"
        natural = True
    stance_stand = stance in ("stand", "half")
    if stance_stand:
        assign["idle_combat"] = "89"          # the guard, then stood up (all the way, or half) and worn as the stance
        stand = stand or not natural
    # A stance that is not at rest (226: a bow held at full draw) is no pose
    # for the stages: their standing idle is the guard (89) stood up instead,
    # shipped as `idle` and stood in place below.
    rest_from_guard = stand and str(stance or "").split("@")[0] in STANCES_NOT_AT_REST
    if rest_from_guard:
        assign["idle"] = "89"
    # A preset that carries its weapon in the other hand from the family's is
    # mirrored before the retarget (PRESET_SIDE, WEAPON_HAND).
    mirror = [] if a.no_mirror else mirrored_clips(a.family, assign)
    assign = {clip: value[:-len(NO_MIRROR)] if value.endswith(NO_MIRROR) else value for clip, value in assign.items()}
    prep_dir = WORK / "prepared"
    prep_dir.mkdir(parents=True, exist_ok=True)
    report = {}
    for clip, value in assign.items():
        pid, _, opts = value.partition("@")
        source = motion_source(pid)
        if not source.exists():
            sys.exit(f"{clip}: no archive {source}")
        cut = dict(PRESET_CUTS.get(int(pid), {})) if not pid.endswith(".npz") else {}
        if opts:                                # 97@0:66^21 - a window and a blow of one's own
            w, _, b = opts.partition("^")
            if w:
                cut["window"] = tuple(int(x) for x in w.split(":"))
            if b:
                cut["blow"] = int(b)
        loop = cut.get("loop", False) or clip == "idle"
        raw = Motion.load(source)
        if clip in mirror:
            raw, err = mirror_motion(raw)
        motion, facts = prepare(raw, clip, cut.get("window"), cut.get("blow"), loop, cut.get("recover", 0))
        if clip in mirror:
            facts["mirrored"] = dict(mode="delta, on the donor", weapon_hand=weapon_hand(a.family), round_trip=float(f"{err:.1e}"))
        prepared = prep_dir / f"{a.family}_{clip}.motion.npz"
        motion.save(prepared)
        report[clip] = dict(preset=pid, **facts)
        out = src_dir / f"{a.asset}_{clip}.glb"
        print(f"== {a.family} {clip} <- {source.name} {facts}")
        r = subprocess.run([sys.executable, str(REPO / "tools/retarget.py"), str(prepared), str(rig), "--rig", str(rig),
                            "--out", str(out), "--no-archive"], capture_output=True, text=True)
        print("\n".join(l for l in r.stdout.splitlines() if l.startswith("  ")))
        if r.returncode:
            sys.exit(r.stderr[-800:] or r.stdout[-800:])
    clips = ",".join(assign)
    extra = ["--no-weapon"] + (["--lod", "0"] if a.with_base else ["--only-clips", clips])
    if a.height:
        extra += ["--height", str(a.height)]
    code = (
        "import sys; from pathlib import Path; sys.path.insert(0, %r); import mesh; "
        "mesh.SOURCE_DIR = Path(%r); mesh.BUNDLE_DIR = Path(%r); mesh.REPO = Path('/'); "
        "sys.argv = ['mesh.py', %r, '--as', %r] + %r; sys.exit(mesh.main())"
    ) % (str(REPO / "tools"), str(src_dir), str(bundle), a.asset, a.family, extra)
    r = subprocess.run([sys.executable, "-c", code], capture_output=True, text=True, cwd=str(REPO))
    tail = [l for l in r.stdout.splitlines() if "PROBLEM" in l or "verified" in l or "problem" in l or "bundle folder" in l]
    print("\n".join(tail) or r.stdout[-1500:])
    if r.returncode:
        print(r.stderr[-1500:])
        sys.exit(f"mesh.py failed for {a.family}")
    # Every carrier just written must bind as the SHIPPED base does (the one in
    # this bundle, else the app's): the game plays a clip's tracks on the
    # figure's joints by name, bone lengths and all, so a rig canonicalised at
    # another height stretches the figure to the clip's.
    dev = bind_against_base(bundle, a.family, [c for c in assign])
    if dev:
        for line in dev:
            print(f"  PROBLEM: {line}")
        sys.exit(f"{a.family}: the carriers do not bind as the shipped base does (pass the height it was shipped at: --height)")
    # The clip fixes, on the carriers mesh.py just wrote: a preset swung in
    # the other hand from the family's weapon is mirrored to it (the
    # archer's bow wrist bent after), a long snout kept off the chest.
    fixed = post_fixes(a.family, bundle, assign, report)
    if fixed:
        print("  fixes: " + "; ".join(fixed))

    def stand_idle(keep):
        code = ("import sys; from pathlib import Path; sys.path.insert(0, %r); import stand_idle; "
                "stand_idle.BUNDLE = Path(%r); sys.argv = ['stand_idle.py', %r, '--keep', %r]; stand_idle.main()") % (
            str(REPO / "tools"), str(bundle), a.family, str(keep))
        r = subprocess.run([sys.executable, "-c", code], capture_output=True, text=True, cwd=str(REPO))
        print(((r.stdout + r.stderr).strip().splitlines() or [""])[-1])

    if stance_stand:
        # the stance first: the guard stood fully up ("stand", a caster's or a
        # king's), or half up ("half": stand_idle --keep 2, 70% of the crouch)
        import shutil
        stand_idle(1.0 if stance == "stand" else 2.0)
        shutil.copyfile(bundle / f"{a.family}_idle.usdz", bundle / f"{a.family}_idle_combat.usdz")
        report["idle_combat"]["preset"] = f"89 {stance}"
        print(f"  the battle stance is the guard stood {'up' if stance == 'stand' else 'half up'} ({a.family}_idle_combat.usdz)")
    if natural:
        # the stages' standing idle from the rig's own bind (and, for a calm
        # family, the battle stance as the same file): made AFTER the clips,
        # on the carrier just shipped, so it binds as they do
        import shutil
        cmd = [sys.executable, str(REPO / "tools/natural_idle.py"), "ship", a.family, "--bundle", str(bundle),
               "--jobs", "1", "--alt"] + (["--also-combat"] if natural_stance else [])
        r = subprocess.run(cmd, capture_output=True, text=True, cwd=str(REPO))
        line = next((l for l in r.stdout.splitlines() if l.startswith(a.family)), "")
        print(f"  natural idle: {' '.join(line.split()[1:])[:400]}")
        held = " HELD (" in line
        natural_made = not held and not r.returncode
        alt_made = natural_made and (bundle / f"{a.family}_idle_alt.usdz").exists() and "[written" in line
        report["idle_alt"] = (dict(made="tools/natural_idle.py --alt") if alt_made else
                              dict(made=None, why=(line.split("ALT", 1)[1].strip()[:300] if "ALT" in line
                                                   else "no natural idle")))
        report["idle"] = dict(preset="89 stood: held by tools/natural_idle.py's OVERRIDES" if held
                              else "natural (tools/natural_idle.py)")
        if natural_stance and not held:
            report["idle_combat"]["preset"] = "natural (tools/natural_idle.py)"
        elif natural_stance and held and not r.returncode:
            # a held calm family's stance: the guard stood up, as its idle is
            stand_idle(1.0)
            shutil.copyfile(bundle / f"{a.family}_idle.usdz", bundle / f"{a.family}_idle_combat.usdz")
            report["idle_combat"]["preset"] = "89 stand (held by tools/natural_idle.py's OVERRIDES)"
        if r.returncode:
            why = [l for l in (r.stdout + r.stderr).splitlines() if "PROBLEM" in l or "REFUSED" in l or "Error" in l]
            print(f"  PROBLEM: no natural idle for {a.family}: {'; '.join(why[:2])}")
            # never leave the guard's raw carrier as a stage idle or a calm stance
            stand_idle(1.0)
            report["idle"] = dict(preset="89 stood (the natural idle was refused)")
            if natural_stance:
                shutil.copyfile(bundle / f"{a.family}_idle.usdz", bundle / f"{a.family}_idle_combat.usdz")
                report["idle_combat"]["preset"] = "89 stand (the natural idle was refused)"
        if not natural_made:
            # the alt and the break were made beside another idle: gone with it
            # (PoseLayer then stands the figure on one idle and breaks with the victory)
            for stale in (f"{a.family}_idle_alt.usdz", f"{a.family}_break.usdz"):
                (bundle / stale).unlink(missing_ok=True)
        else:
            # the idle break, made beside the idle just written (a re-shipped idle
            # wants its break made again); none passing, PoseLayer breaks with the victory
            b = break_for(a.family, bundle, idle_bundle=bundle)
            if b.get("deal") in ("victory", "held"):
                report["break"] = dict(preset=b["deal"], why=b.get("reason") or "; ".join(
                    f"{t['preset']}/{t['rung']}: {t['fails'][0]}" for t in b.get("tries", [])[-2:]))
            else:
                report["break"] = dict(preset=str(b["deal"]), name=b.get("name"), rung=b["rung"],
                                       mirrored=b["mirrored"], seconds=b["seconds"], over3=b["over3"],
                                       idle_over3=b["idle_over3"])
            print(f"  idle break: {break_line(b)[23:][:300]}")
    elif rest_from_guard:
        stand_in_place(bundle, a.family, "idle")
        report["idle"]["preset"] = "89 stood (the stance is not at rest)"
        print(f"  the standing idle is the guard stood up ({a.family}_idle.usdz), not the {stance} stance")
    elif stand and stance != "stand":
        stand_idle(1.0)                       # the stages' standing idle, from whatever stance shipped
    if ready_guard is not None:
        # the battle's ready stance over the guard just shipped; refused, the guard stays, loudly
        cmd = [sys.executable, str(REPO / "tools/ready_stance.py"), "ship", a.family, "--bundle", str(bundle),
               "--guard", ready_guard]
        r = subprocess.run(cmd, capture_output=True, text=True, cwd=str(REPO))
        line = next((l for l in r.stdout.splitlines() if l.startswith(a.family)), "")
        guard_word = "89" + ("" if ready_guard == "89" else f" {ready_guard}")
        if r.returncode:
            why = [l for l in (r.stdout + r.stderr).splitlines() if "REFUSED" in l or "Error" in l]
            print(f"  PROBLEM: no ready stance for {a.family}, the guard ({guard_word}) stays: {'; '.join(why[:2])[:400]}")
            report["idle_combat"]["preset"] = f"{guard_word} (the ready stance was refused)"
        else:
            import re
            recipe = (re.search(r"-> (a|b)\b", line) or [None, "?"])[1]
            print(f"  ready stance: {' '.join(line.split()[1:])[:300]}")
            report["idle_combat"] = dict(preset=f"ready ({recipe}) over the {guard_word} guard",
                                         tool="tools/ready_stance.py", guard=report["idle_combat"])
    rp = report_path(bundle, a.family)
    rp.parent.mkdir(parents=True, exist_ok=True)
    before = json.loads(rp.read_text()) if rp.exists() else {}
    rp.write_text(json.dumps({**before, **report}, indent=1) + "\n")
    if not a.keep:
        for clip in assign:
            (src_dir / f"{a.asset}_{clip}.glb").unlink(missing_ok=True)


# ---------------------------------------------------------------------------
# Boards
# ---------------------------------------------------------------------------

def posed_points(base, clip, frame):
    """The base skinned with the clip's frame, joints matched by name - the game's way."""
    leaf = lambda j: j.split("/")[-1]
    cmap = {leaf(j): i for i, j in enumerate(clip.joints)}
    local = np.array(base.rest_local, dtype=np.float64)
    a = clip.anim
    for bi, bj in enumerate(base.joints):
        ci = cmap.get(leaf(bj))
        if ci is not None:
            local[bi] = character.trs(a["T"][frame, ci], a["R"][frame, ci], a["S"][frame, ci])
    return base.skinned_points(character.world_from_local(local, base.parents))


def draw_cell(base, pts, views, size, height, label):
    import preview
    from PIL import Image, ImageDraw
    normals = character.vertex_normals(pts.astype(np.float32), base.faces).astype(np.float64)
    tex = preview.base_colour(base)
    width = int(round(size * 0.78))
    scale = 0.80 * size / max(height * 1.25, 1e-6)          # one scale for every frame: a jump or a crouch shows
    baseline = 0.08 * size
    panels = []
    for v in views:
        p = preview.render_view(pts, normals, base.faces, base.uvs, tex, v, scale, baseline, width, size, True)
        d = ImageDraw.Draw(p)
        y = size - baseline
        d.line([(0, y), (width, y)], fill=(200, 60, 60), width=1)       # the floor
        panels.append(p)
    cell = Image.new("RGB", (width * len(panels), size + 16), (30, 30, 34))
    for i, p in enumerate(panels):
        cell.paste(p, (i * width, 0))
    ImageDraw.Draw(cell).text((4, size + 2), label, fill=(240, 220, 150))
    return cell


PRESET_NAMES = {k: v.get("name", "") for k, v in load_manifest()["presets"].items()}


def cmd_board(a):
    from PIL import Image, ImageDraw
    bundle = Path(a.bundle)
    own = bundle / f"{a.family}.usdz"
    base_path = Path(a.base) if a.base else (own if own.exists() else REPO / "Pantheon/Resources/Models" / f"{a.family}.usdz")
    base = character.read_usdz(str(base_path))
    rep_path = report_path(bundle, a.family)
    report = json.loads(rep_path.read_text()) if rep_path.exists() else {}
    lo, hi = character.bounds(base.points)
    height = float(hi[1] - lo[1])
    rows = []
    for clip in a.clips.split(","):
        path = bundle / f"{a.family}_{clip}.usdz"
        if not path.exists():
            print(f"  no {path}")
            continue
        c = character.read_usdz(str(path))
        F = len(c.anim["T"])
        from retarget import Motion
        frac = report.get(clip, {}).get("blow")
        if frac is None and clip.startswith(("attack", "ultimate")):
            frac = blow_frame(Motion.from_char(c))[1]
        f_blow = None if frac is None else int(round(frac * (F - 1)))
        fracs = [0.0, 0.25, 0.5, 0.75] if f_blow is None else [0.0, frac * 0.5, frac, (frac + 1) / 2, 1.0]
        frames = sorted({min(F - 1, int(round(x * (F - 1)))) for x in fracs})
        cells = []
        for f in frames:
            pts = posed_points(base, c, f)
            tag = " BLOW" if f == f_blow else ""
            cells.append(draw_cell(base, pts, a.views.split(","), a.size, height,
                                   f"{clip} f{f}/{F - 1} ({f / max(F - 1, 1):.2f}){tag}  lowest {pts[:, 1].min():+.2f} m"))
        r = report.get(clip, {})
        rows.append((f"{a.family}_{clip}  <- preset {r.get('preset', '?')} {PRESET_NAMES.get(str(r.get('preset')), '')}  {F} frames {r.get('seconds', '?')} s  "
                     f"rate x{r.get('rate', '?')}  blow {r.get('blow', '-')} (target {r.get('target', '-')})", cells))
    if not rows:
        sys.exit("nothing to board")
    w = max(sum(c.width for c in cells) for _, cells in rows) + 20
    h = sum(cells[0].height + 26 for _, cells in rows) + 10
    sheet = Image.new("RGB", (w, h), (22, 22, 26))
    d = ImageDraw.Draw(sheet)
    y = 6
    for title, cells in rows:
        d.text((10, y), title, fill=(160, 230, 160))
        x = 10
        for c in cells:
            sheet.paste(c, (x, y + 18))
            x += c.width
        y += cells[0].height + 26
    sheet.save(a.out, quality=86)
    print(f"  board -> {a.out}")


def cmd_board_archive(a):
    """An archived motion on its donor's rig (the rig GLB, canonicalised), at
    five fractions and the blow frame - what the preset IS, before any family
    wears it."""
    from PIL import Image, ImageDraw
    from retarget import Motion, retarget
    m = load_manifest()
    rows = []
    for p in a.presets:
        rec = m["presets"].get(str(int(p)), {})
        donor = a.donor or rec.get("donor")
        rig = character.read_glb(str(ART / f"{donor}.glb"))
        src = Motion.load(archive_path(p))
        tgt = rig
        anim, _, _ = retarget(src, Motion.from_char(tgt))
        tgt.anim = {"T": anim["T"], "R": anim["R"], "S": anim["S"], "fps": anim["fps"]}
        character.canonicalise(tgt, height=None)
        character.ground_animation(tgt)
        lo, hi = character.bounds(tgt.points)
        height = float(hi[1] - lo[1])
        F = len(tgt.anim["T"])
        f_blow = rec.get("blow_frame")
        fr = sorted({int(round(x * (F - 1))) for x in np.linspace(0.0, 1.0, a.frames)} | ({f_blow} if f_blow is not None else set()))
        cells = []
        for f in fr:
            pts = tgt.skinned_points(tgt.joint_world_at(f))
            cells.append(draw_cell(tgt, pts, a.views.split(","), a.size, height,
                                   f"f{f}/{F - 1}{' BLOW' if f == f_blow else ''} low {pts[:, 1].min():+.2f}"))
        rows.append((f"preset {int(p)} {rec.get('name', '')}  {rec.get('seconds', '?')} s  on {donor}", cells))
    w = max(sum(c.width for c in cells) for _, cells in rows) + 20
    h = sum(cells[0].height + 26 for _, cells in rows) + 10
    sheet = Image.new("RGB", (w, h), (22, 22, 26))
    d = ImageDraw.Draw(sheet)
    y = 6
    for title, cells in rows:
        d.text((10, y), title, fill=(160, 230, 160))
        x = 10
        for c in cells:
            sheet.paste(c, (x, y + 18))
            x += c.width
        y += cells[0].height + 26
    sheet.save(a.out, quality=86)
    print(f"  board -> {a.out}")


# ---------------------------------------------------------------------------
# How good is the retarget?
# ---------------------------------------------------------------------------

def cmd_compare(a):
    """Our retarget of an archived preset onto a rig, against Meshy's own
    application of the same preset to that rig (a live task, fetched free):
    per-joint world rotation difference and the hands' and feet's positions,
    over every frame."""
    import meshy as meshy_mod
    from retarget import Motion, load_source, retarget
    _, api = meshy_api()
    man = meshy_mod.load_manifest(a.asset) or sys.exit(f"no manifest for {a.asset}")
    st = next((s for k, s in man["stages"].items() if k.startswith("clip:") and s.get("action_id") == int(a.preset)), None)
    if not st:
        sys.exit(f"{a.asset} never had preset {a.preset} applied")
    ref_glb = WORK / "downloads" / f"{a.asset}_ref_{a.preset}.glb"
    if not ref_glb.exists():
        fetch_clip_glb(api, st["id"], ref_glb)
    ref = load_source(ref_glb)
    src = Motion.load(archive_path(a.preset))
    rig = Motion.from_char(character.read_glb(str(ART / f"{a.asset}.glb")))
    anim, missing, facts = retarget(src, rig)
    ours = Motion(rig.joints, rig.parents, rig.rest_local, anim)
    F = min(len(ours.anim["T"]), len(ref.anim["T"]))
    height = rig.joint_world_at_rest()[:, 3, 1].max()
    names = [j.split("/")[-1] for j in rig.joints]
    rmap = {j.split("/")[-1].lower(): i for i, j in enumerate(ref.joints)}
    ang, pos = [], {n: [] for n in ("LeftHand", "RightHand", "LeftFoot", "RightFoot", "Head")}
    from retarget import rotation_part
    ho, hr = ours.joint_index("hips"), ref.joint_index("hips")
    for f in range(F):
        Wo, Wr = ours.joint_world_at(f), ref.joint_world_at(f)
        row = []
        for j, n in enumerate(names):
            i = rmap.get(n.lower())
            if i is None:
                continue
            d = rotation_part(Wo[j]).T @ rotation_part(Wr[i])
            row.append(np.degrees(np.arccos(np.clip((np.trace(d) - 1) / 2, -1, 1))))
            if n in pos:
                pos[n].append(np.linalg.norm(Wo[j][3, :3] - Wr[i][3, :3]))
                # relative to the hips: the root's own offset is locked and grounded at shipping
                pos.setdefault(n + "/hips", []).append(np.linalg.norm((Wo[j][3, :3] - Wo[ho][3, :3]) - (Wr[i][3, :3] - Wr[hr][3, :3])))
        ang.append(row)
    ang = np.array(ang)
    print(f"preset {a.preset} on {a.asset}: ours (from {Path(src.source).name if src.source else 'archive'}) vs Meshy's own, {F} frames, rig {height:.2f} m")
    print(f"  joint world rotation difference: median {np.median(ang):.1f} deg, 90th pct {np.percentile(ang, 90):.1f}, max {ang.max():.1f}")
    worst = np.argsort(-ang.mean(axis=0))[:5]
    print("  worst joints (mean deg): " + ", ".join(f"{names[j]} {ang[:, j].mean():.1f}" for j in worst if j < len(names)))
    for n, v in list(pos.items()):
        if v:
            v = np.array(v)
            print(f"  {n:9s} position: mean {v.mean() * 100:5.1f} cm  max {v.max() * 100:5.1f} cm  ({v.mean() / height * 100:.1f}% of height)")
    if not a.keep:
        ref_glb.unlink(missing_ok=True)


# ---------------------------------------------------------------------------
# The roster's assignment
# ---------------------------------------------------------------------------

# Slot pools by the kind of fighter, from the ARCHIVED palette only (a pool
# grows as presets are bought; `plan` never names one that is not archived).
# Order is preference: the first is the most fitting for the kind.
POOLS = {
    "blade":    {"attack_basic": [219, 97, 220, 206], "attack_heavy": [242, 221, 238, 105], "ultimate": [102, 105, 91, 86],
                 "idle_combat": [89, "half", "stand"], "victory": [412, 298, 88]},
    "polearm":  {"attack_basic": [240, 219, 97, 220], "attack_heavy": [221, 242, 238], "ultimate": [105, 102, 91, 86],
                 "idle_combat": [89, "half", "stand"], "victory": [412, 298, 88]},
    "heavy":    {"attack_basic": [128, 219, 97], "attack_heavy": [237, 128, 242, 221], "ultimate": [127, 238, 102],
                 "idle_combat": [85, 89, "half"], "victory": [88, 412, 298]},
    "unarmed":  {"attack_basic": [97, 206, 219], "attack_heavy": [238, 221, 242], "ultimate": [86, 91, 105],
                 "idle_combat": [89, "half"], "victory": [298, 88, 412]},
    "caster":   {"attack_basic": [129, 136, 133], "attack_heavy": [130, 125, 133, 136], "ultimate": [126, 125, 130],
                 "idle_combat": ["stand", "half"], "victory": [412, 298]},
    "robed":    {"attack_basic": [136, 129, 133], "attack_heavy": [133, 136, 125], "ultimate": [126, 125],
                 "idle_combat": ["stand"], "victory": [412, 298]},
    "archer":   {"attack_basic": ["224@70:135^117"], "attack_heavy": [224], "ultimate": [222],
                 "idle_combat": [89, 226, "half"], "victory": [298, 412]},
}
# How each family STANDS (Docs/PLAN.md, *Natural poses*; the archetypes of the
# craft study of 2026-09-24): the row of tools/natural_idle.py's STYLES its
# standing idle is drawn from. The deal above is by weapon (what the arms can
# swing); this is by character (how the body carries itself at rest) - a king
# still but for a slow survey, a brute's heave, a trickster's cocked hip, a
# beast's crouch. An awakened form takes its family's (`archetype`).
ARCHETYPE = {
    **{f: "sovereign" for f in ("anubis", "horus", "isis", "osiris", "ra", "boss_unwrapped_king", "zeus", "athena",
                                "poseidon", "hera", "hades", "odin", "frigg", "minerva", "neptune", "pluto",
                                "guan_yu")},
    **{f: "champion" for f in ("sekhmet", "anhur", "ares", "perseus", "nike", "achilles", "amazon", "tyr", "sif",
                               "vidar", "valkyrie", "mars", "bellona", "gladiator", "nezha")},
    **{f: "soldier" for f in ("hoplite", "heimdall", "njord", "shield_maiden", "einherjar", "centurion",
                              "scarab_knight")},
    **{f: "brute" for f in ("sobek", "khnum", "taweret", "heracles", "hephaestus", "cyclops", "minotaur", "thor",
                            "surtr", "berserker", "frost_troll", "dwarf_smith", "boss_jotunn")},
    **{f: "mystic" for f in ("thoth", "ptah", "nephthys", "cobra_priestess", "medusa", "hel", "vestal", "nuwa")},
    **{f: "grace" for f in ("maat", "hathor", "apollo", "aphrodite", "demeter", "siren", "nymph", "freya", "baldr",
                            "idunn", "bragi", "light_elf", "chang_e")},
    **{f: "hunter" for f in ("medjay", "artemis", "atalanta", "skadi", "ullr", "diana")},
    **{f: "trickster" for f in ("set", "bes", "satyr", "hermes", "dionysus", "loki", "dark_elf", "mercury",
                                "sun_wukong", "fox_spirit")},
    **{f: "beast" for f in ("bastet", "serqet", "jackal_warrior", "harpy", "fenrir")},
    **{f: "construct" for f in ("shabti", "mummy", "draugr", "jiangshi", "terracotta_soldier", "sandstone_sentinel",
                                "boss_colossus")},
}


def archetype(family):
    """The family's ARCHETYPE row; an awakened form takes its family's. None
    for a family not in the table (tools/natural_idle.py refuses it)."""
    return ARCHETYPE.get(family) or ARCHETYPE.get(family.replace("_awakened", ""))


# The calm archetypes: a family of these whose deal stands the guard up for
# its battle stance (`stand`) stands in its natural idle instead - the
# genre's casters and kings stand calm in battle (Docs/PLAN.md, *Natural
# poses*, step 2). 35 families; the guard's stood-up stance tore 9,994 edges
# past 3x on them, the natural idle a few hundred. The other ten `stand`
# families keep the stood guard until step 4's ready stances.
CALM = ("sovereign", "grace", "mystic")
# The battle's ready stances (Docs/PLAN.md, *Natural poses*, step 4;
# tools/ready_stance.py): every family the deal still stood in the guard -
# raw (89), 70% up (`half`) or fully up (`stand`), 73 of them - stands in its
# ready stance instead, made over that guard (the plan keeps it as `guard`,
# which is also the fallback where the ready stance is refused). The six on
# 85's calm tail, Skadi's 226 and the calm 35's natural idle keep theirs.
READY_OVER = ("89", "half", "stand")


def natural_stances():
    """The families whose plan stance is `natural` (make_plan)."""
    plan, _ = make_plan()
    return sorted(f for f, p in plan.items() if str(p["clips"].get("idle_combat")) == "natural")


BESPOKE = {"anubis", "sekhmet", "zeus", "ares", "thoth"}      # Art/Motions/<family>_<clip>.motion.npz
BRUTES = {"minotaur", "cyclops", "frost_troll", "berserker", "draugr", "fenrir", "sobek", "surtr", "heracles", "boss_colossus", "khnum", "taweret"}
HAND_WRITTEN = {"anubis": 4, "sekhmet": 5, "zeus": 5, "ares": 5, "thoth": 5, "heracles": 4, "perseus": 4,
                "shabti": 3, "hoplite": 3, "satyr": 3, "harpy": 3}
# A family the serious wave does not list (the serious Zeus shipped as the
# test, before serious_wave.txt existed): (asset, family, kind, grade).
EXTRA_ROWS = [("zeus_serious", "zeus", "caster", 5)]      # his height: mesh.py reads it off UnitDatabase.swift
# family -> the height (m) its base was shipped at. `ship` must canonicalise
# the rig at the SAME height, or the carriers' bind (bone lengths, the hips'
# height) differs from the shipped base's and the game stretches the figure
# to the clip's: mesh.py's own default for a table family is 1.9 m, which put
# the first roll-out's carriers 3-7% short on 90 families (2026-09-24).
ROW_HEIGHTS = {}
# Jump Attack (86) leaps 2.3 m: dealt only to the fliers and the leapers,
# where a leap is the character (winged sandals, a cat's pounce, the monkey
# king), never to a giant, a king or a heavy.
JUMPERS = {"bastet", "mercury", "perseus", "achilles", "vidar", "gladiator", "shield_maiden", "sun_wukong",
           "fenrir", "harpy", "valkyrie", "nike"}
# Where the character asks for a move the deal would not give it (applied after
# the deal; `plan` still reports any identical set). Diana's bow is slung and
# bound to her torso (clip_fix --bind-piece), so the archer's held full-draw
# stance (226) would aim an empty hand: she stands.
OVERRIDES = {"diana": {"idle_combat": "stand"}, "sun_wukong": {"ultimate": 86},
             # Hephaestus's hammer arm rests bent across his chest, so a swing
             # retargeted from the donor's hanging arm stays at his shoulder
             # (the deal's 237 on the board of 2026-09-24); his judged heavy is
             # the Heavy Hammer Swing mirrored in pose mode (POSE_MIRROR), which
             # puts the hammer overhead where the empty hand went. The Axe
             # Stance keeps his five clips his own (with the guard he had
             # Draugr's set).
             "hephaestus": {"attack_heavy": 128, "idle_combat": 85}}
# The board judgments of 2026-09-24 (Docs/MOTION.md, *As rolled out*). After
# the roll-out every clip was measured on its family's shipped base and LOD
# against the clip it replaced (the edges a pose stretches past 3x, over 32
# frames); the 24 whose count rose by half again (and 100 more) were boarded
# old beside new at each version's worst frame, and where the new clip
# visibly tore the model more, candidates from the same kit were shipped into
# scratch and measured, and the one that tore least while keeping the
# family's five clips its own REPLACES the deal's clip here - AFTER the deal,
# so no other family's deal moves. `~nm` is a preset left as the donor swings
# it (not mirrored to a left-handed family's weapon hand): on Loki, Surtr,
# Achilles and the Dark Elf every mirrored swing dragged the cloth or the
# blade welded to the weapon arm's side into a sheet, and only the unmirrored
# motion kept to the old count; their basic is the Shield Push mirrored (the
# free right hand shoves, the weapon arm stays back), which tore least of all.
# An awakened form takes its family's judgment (each was measured).
JUDGED = {
    "loki": {"attack_basic": 220, "attack_heavy": "242~nm", "ultimate": "102~nm", "idle_combat": 89},
    "surtr": {"attack_basic": 220, "attack_heavy": "242~nm", "ultimate": "102~nm"},
    "achilles": {"attack_heavy": "242~nm", "ultimate": "102~nm"},
    "dark_elf": {"attack_basic": 220, "attack_heavy": "242~nm", "ultimate": "102~nm"},
    # 125 (arms straight up) lifts a robe with both arms like wings; it tore
    # these robes as their HEAVY before the roll-out and as their ultimate
    # after it. 126 measured at the old count; the victories keep the five
    # clips distinct from Ma'at's, the Siren's and Osiris's, and tear least
    # (Hathor 686 edges against 1,668, the Cobra Priestess 106 against 304,
    # Pluto 683 against 1,568; her half stance 15 against 18).
    "hathor": {"ultimate": 126, "victory": 88},
    "isis": {"ultimate": 126},
    "cobra_priestess": {"ultimate": 126, "victory": 88, "idle_combat": "half"},
    "pluto": {"ultimate": 126, "victory": 88},
    # the heavy's 242 made Athena's five Serqet's: she stands (310 edges, as the guard's 309)
    "athena": {"attack_heavy": 242, "idle_combat": "stand"},
    "dwarf_smith": {"victory": 88},
    # 298 crouches before its hop and stretches a kilt, a skirt or a cloak
    # between the legs; 412 or 88, whichever measured least, and distinct.
    "demeter": {"victory": 412},
    "horus": {"victory": 412},
    "odin": {"victory": 88},
    "medusa": {"victory": 412},
    "mummy": {"victory": 412},
    "sun_wukong": {"victory": 412},
    "bes": {"victory": 88},
    "skadi": {"victory": 412},
    # the second tier: clips whose count rose by a quarter and 250 edges,
    # boarded and judged the same way
    "harpy": {"attack_basic": 220, "ultimate": "102~nm", "victory": 88},
    "bragi": {"ultimate": 126, "victory": 88},
    "frigg": {"ultimate": 126},
    "aphrodite": {"ultimate": 126},
    "jiangshi": {"ultimate": 102},
    "bellona": {"attack_basic": "219~nm", "victory": 88},      # unmirrored, the right hand's whip cracks
    "idunn": {"attack_basic": 129, "idle_combat": "half"},
    "fox_spirit": {"attack_basic": 129, "idle_combat": "half"},
    # the heavy's draw starts after the quiver reach, which dragged her cloak (933 edges against 1,177)
    "atalanta": {"attack_heavy": "224@70:140^117"},
}
# (family, clip): the pre-palette file stays in the bundle (no candidate from
# the kit measured at or under it); `roll` does not ship it.
KEPT = {
    ("dwarf_smith", "attack_basic"): "Meshy's own 219 (891 edges past 3x; the palette's 219 1,145, 128 1,523, 97 1,560)",
}

# (family, preset) mirrored on the CARRIER after shipping, in clip_fix's pose
# mode - each judged on its own board (clip_fix, 2026-09-23): the hand goes
# exactly where the other hand went whatever the arms' rest poses, which is
# what a weapon arm bent at rest needs; on an asymmetric pair of LEGS it
# fails (the Minotaur's hooves, 0.3 m), so it is never the default.
POSE_MIRROR = {("hephaestus", 128)}

# The hand each preset carries its WEAPON in (the figure's own side, as the
# joint names say: LeftHand is the figure's left). Measured on the donor in
# the chest's frame - the hand whose path and reach lead into the blow
# (scratch lead_hand.py, 2026-09-24). 128, the Heavy Hammer Swing, is NOT
# lateral: both hands go overhead (the left 0.30 of the height over the head,
# the right 0.22), and on the boards of 2026-09-24 the Minotaur's axe and
# Thor's hammer go overhead and down UNmirrored and read worse mirrored;
# Hephaestus's (mirrored by clip_fix on 2026-09-23) was the exception, his
# hammer arm bent across his chest at rest, and the deal no longer gives him
# 128. 220 is the OFF hand's shove:
# its weapon hand is the right, the one that does not shove. The archery
# presets hold the bow in the LEFT and draw with the right. A preset not
# named (91's two blades, the casts, the stances but 226, the victories) is
# not lateral: it is never mirrored.
PRESET_SIDE = {219: "R", 97: "R", 242: "R", 221: "R", 105: "R", 102: "R", 86: "R", 237: "R", 238: "R",
               127: "R", 206: "R", 220: "R", 224: "L", 222: "L", 226: "L"}
# The hand each family holds its weapon (an archer: its bow) in, measured on
# the shipped base: the mass the forearm and hand own OUTSIDE the arm's own
# layer (a blade, a haft, a bow), its elongation and its reach past the
# wrist, and every uncertain one looked at on a front render (Docs/MOTION.md,
# *As rolled out*). Default "R". "L": the weapon is in the left hand, so every
# right-handed preset is mirrored to it. None: nothing in either hand's
# weights, or a weapon in each (two axes, two clubs, two daggers) - nothing is
# mirrored. Keyed by the exact family: an awakened mesh holds its own way.
WEAPON_HAND = {
    **{f: "L" for f in ("achilles", "amazon", "bellona", "centurion", "dark_elf", "harpy", "loki", "mercury",
                        "nezha", "njord", "surtr", "artemis", "atalanta", "medjay", "ullr")},
    **{f: None for f in ("diana", "berserker", "frost_troll", "serqet", "boss_colossus", "bastet", "fenrir",
                         "hoplite", "horus", "jiangshi", "mummy", "sun_wukong", "hel", "medusa", "minerva",
                         "idunn", "nephthys")},
}
# The clip fixes of 2026-09-23 (tools/clip_fix.py), re-applied by `ship` to the
# palette's clips so a re-ship keeps them: the bow hand's wrist bent so the
# bow stands upright at the loose (the concept holds it along the forearm),
# and a long snout kept `limit` degrees off the torso's line.
BOW_WRIST = {"skadi"}
SNOUT = {"sobek": 75.0}
LATERAL_CLIPS = ("attack_basic", "attack_heavy", "ultimate", "idle_combat")
NO_MIRROR = "~nm"      # a value's suffix: this clip is NOT mirrored to the family's weapon hand (JUDGED)


def weapon_hand(family):
    return WEAPON_HAND.get(family, "R")


def mirrored_clips(family, assign):
    """The clips of `assign` ({clip: value}) whose preset carries its weapon
    in the other hand from the family's: those `ship` mirrors."""
    hand = weapon_hand(family)
    out = []
    for clip in LATERAL_CLIPS:
        v = str(assign.get(clip, ""))
        if v.endswith(NO_MIRROR):                # judged: this clip stays as the preset swings it
            continue
        v = v.split("@")[0]
        if not v.isdigit() or hand is None:
            continue
        side = PRESET_SIDE.get(int(v))
        if side and side != hand:
            out.append(clip)
    return out


def roster_rows():
    """(asset, family, kit field, sentence, grade) for every serious remake;
    the height each was SHIPPED at (the wave's third field, build_asset.sh's
    --height) goes into ROW_HEIGHTS."""
    heights = {}
    import re
    sentences = {}
    for line in (REPO / "tools/batch/serious_concepts.tsv").read_text().splitlines():
        if "\t" in line:
            k, v = line.split("\t", 1)
            sentences[k] = v
    grades = dict(HAND_WRITTEN)
    src = (REPO / "Pantheon/Core/Data/UnitDatabase+Families.swift").read_text()
    for k, stars in re.findall(r'FamilyRow\(key: "(\w+)",.*?stars: (\d)', src):
        grades[k] = int(stars)
    rows = []
    for line in (REPO / "tools/batch/serious_wave.txt").read_text().splitlines():
        if not line.strip() or line.startswith("#"):
            continue
        f = line.split(":")
        asset, kit, family = f[0], f[4], f[-1]
        heights[family] = float(f[2])
        base = family.replace("_awakened", "")
        grade = grades.get(base, 5 if family.startswith("boss_") else 4)
        rows.append((asset, family, kit, sentences.get(family, ""), grade))
    ROW_HEIGHTS.update(heights)
    listed = {r[1] for r in rows}
    for asset, family, kind, grade in EXTRA_ROWS:
        if family not in listed:
            rows.append((asset, family, "kind:" + kind, sentences.get(family, ""), grade))
    return rows


def kind_of(family, kit, sentence):
    import re
    if kit.startswith("kind:"):
        return kit[5:]
    s = re.sub(r"\bno (great |long )?[a-z]+( and no [a-z]+)?", "", sentence.lower())
    if kit.startswith("archer") or re.search(r"\bbow\b(?! held)", s) and "recurve" in s:
        return "archer"
    if kit.startswith("caster"):
        robe = re.search(r"gown|robe|dress|ending above the ankles|to the ankles|floor-length", s)
        return "robed" if robe else "caster"
    if re.search(r"\b(axe|hammer|mace|club|maul)\b", s) or kit.startswith("heavy"):
        return "heavy" if not re.search(r"\b(spear|trident|bident|halberd|staff|pole)\b", s) else "polearm"
    if re.search(r"\b(spear|trident|bident|halberd|glaive|pole|staff)\b", s):
        return "polearm"
    if re.search(r"empty (open )?hands|\bclaws?\b|\bnails\b|\bfists?\b", s) or not re.search(
            r"\b(sword|khopesh|gladius|xiphos|dagger|knife|seax|blade|sickle|scythe|crook|wand|mace)\b", s):
        return "unarmed"
    return "blade"


def cmd_plan(a):
    plan, taken = make_plan()
    report_plan(a, plan, taken)


def make_plan():
    """Every family its own combination: the families of a kind dealt the
    pools so that no two share more slots than they must, the 5-stars first
    (they get the first pick of the kind's signature moves), the five gods'
    bespoke attacks kept, an awakened form wearing its family's set.
    -> (plan, taken): plan[family] = {asset, kind, grade, clips, hand, mirror}."""
    import itertools
    archived = {k for k in load_manifest()["presets"] if archive_path(k).exists()}

    def ok(v):
        v = str(v).split("@")[0]
        return v in ("stand", "half") or v in archived

    rows = roster_rows()
    base_rows = [r for r in rows if "_awakened" not in r[1]]
    order = sorted(base_rows, key=lambda r: (-r[4], r[1]))
    taken = {}                                     # kind -> list of assigned tuples
    plan = {}
    slots = ("attack_basic", "attack_heavy", "ultimate", "idle_combat", "victory")
    for asset, family, kit, sentence, grade in order:
        kind = kind_of(family, kit, sentence)
        pool = {k: [v for v in POOLS[kind][k] if ok(v) and (family in JUMPERS or str(v).split("@")[0] != "86")]
                for k in slots}
        for k, v in OVERRIDES.get(family, {}).items():
            pool[k] = [v]
        if family in BESPOKE:
            for c in ("attack_basic", "attack_heavy", "ultimate"):
                pool[c] = [f"Art/Motions/{family}_{c}.motion.npz"]
        if family in BRUTES and 88 in pool["victory"]:
            pool["victory"] = [88] + [v for v in pool["victory"] if v != 88]
        best = None
        for combo in itertools.product(*(pool[k] for k in slots)):
            clash = max((sum(x == y for x, y in zip(combo[:3], t[:3])) for t in taken.get(kind, [])), default=0)
            same = sum(combo == t for ts in taken.values() for t in ts)      # an identical set anywhere in the roster
            reuse = sum(sum(x == y for x, y in zip(combo, t)) for t in taken.get(kind, []))
            pref = sum(pool[k].index(v) for k, v in zip(slots, combo))
            attacks = [str(x).split("@")[0] for x in combo[:3]]
            twice = len(attacks) - len(set(attacks))       # one preset in two slots of one family
            score = (twice, same, clash, reuse, pref)
            if best is None or score < best[0]:
                best = (score, combo)
        taken.setdefault(kind, []).append(best[1])
        plan[family] = dict(asset=asset, kind=kind, grade=grade, clips=dict(zip(slots, best[1])))
    for asset, family, kit, sentence, grade in rows:
        if "_awakened" in family:
            base = plan.get(family.replace("_awakened", ""))
            if base:
                clips = dict(base["clips"])
                for c in ("attack_basic", "attack_heavy", "ultimate"):
                    if str(clips[c]).endswith(".npz"):
                        clips[c] = clips[c]                 # the god's own motion, carried onto the awakened rig
                plan[family] = dict(asset=asset, kind=base["kind"], grade=grade, clips=clips)
    for f, p in plan.items():
        p["height"] = ROW_HEIGHTS.get(f)
        base = f.replace("_awakened", "")
        judged = JUDGED.get(f) or (JUDGED.get(base) if f != base else None) or {}
        for clip, value in judged.items():
            p["clips"][clip] = value
        if judged:
            p["judged"] = sorted(judged)
        kept = sorted(c for (fam, c) in KEPT if fam in (f, base))
        if kept:
            p["kept"] = kept
    for f, p in plan.items():
        # after the deal and the judgments, so no other family's deal moves
        if str(p["clips"].get("idle_combat")) == "stand" and archetype(f) in CALM:
            p["clips"]["idle_combat"] = "natural"
        elif str(p["clips"].get("idle_combat")) in READY_OVER:
            p["guard"] = str(p["clips"]["idle_combat"])
            p["clips"]["idle_combat"] = "ready"
    for f, p in plan.items():
        p["hand"] = weapon_hand(f)
        p["mirror"] = mirrored_clips(f, p["clips"])
    return plan, taken


def plan_label(v):
    v = str(v)
    if v.endswith(NO_MIRROR):
        return v[:-len(NO_MIRROR)].split("@")[0]
    if v.endswith(".npz"):
        return "own:" + Path(v).name.split("_")[0]
    if v in ("stand", "half", "natural", "ready"):
        return v
    return v.split("@")[0]


def stance_word(p, clip):
    """A plan slot's label; a ready stance names the guard it is made over."""
    v = p["clips"][clip]
    if clip == "idle_combat" and v == "ready":
        return f"ready ({p['guard']})"
    return plan_label(v)


def report_plan(a, plan, taken):
    slots = ("attack_basic", "attack_heavy", "ultimate", "idle_combat", "victory")
    label = plan_label
    tuples = [tuple(stance_word(p, k) for k in p["clips"]) for f, p in plan.items() if "_awakened" not in f]
    dupes = len(tuples) - len(set(tuples))
    short = {"attack_basic": "basic", "attack_heavy": "heavy", "ultimate": "ult", "idle_combat": "stance"}
    if a.markdown:
        print("| family | grade | kind | hand | basic | heavy | ultimate | stance | victory | mirrored |")
        print("|---|---|---|---|---|---|---|---|---|---|")
        for f, p in sorted(plan.items(), key=lambda kv: (-kv[1]["grade"], kv[1]["kind"], kv[0])):
            print(f"| {f} | {p['grade']}★ | {p['kind']} | {p['hand'] or '-'} | " + " | ".join(stance_word(p, k) for k in slots)
                  + f" | {', '.join(short[x] for x in p['mirror']) or ''} |")
    else:
        for f, p in sorted(plan.items()):
            print(f"{f:24s} {p['grade']} {p['kind']:8s} {p['hand'] or '-'} " + "  ".join(f"{k.split('_')[-1]}={stance_word(p, k)}" for k in p["clips"])
                  + (f"  mirror={','.join(p['mirror'])}" if p["mirror"] else ""))
    from collections import Counter
    print(f"\n{len(plan)} families ({len(tuples)} base); identical five-clip sets: {dupes}", file=sys.stderr)
    # counted on the FINAL deal (JUDGED applied), base families only
    kinds = {}
    for f, p in plan.items():
        if "_awakened" not in f:
            kinds.setdefault(p["kind"], []).append(tuple(label(p["clips"][k]) for k in slots[:3]))
    for kind, ts in sorted(kinds.items()):
        trip = Counter(ts)
        print(f"  {kind:8s} {len(ts):3d} families, {len(trip)} distinct attack triples, the most shared by {max(trip.values())}", file=sys.stderr)
    if a.json:
        Path(a.json).write_text(json.dumps(plan, indent=1) + "\n")


def ship_argv(family, p, bundle, real=False):
    """The `ship` arguments for one family of the plan. A god's attack clips
    are its bespoke motions, already on its rig and its awakened rig and
    timed by BattleSceneController.contactFraction's own row, so only its
    stance and victory are dealt; every family takes the natural idle
    (tools/natural_idle.py) with its weight-shift alt and its idle break,
    a calm one wears the idle as its stance too, and a family in the guard
    stands in its ready stance (`ready:<guard>`, tools/ready_stance.py)."""
    base = family.replace("_awakened", "")
    argv = [p["asset"], family]
    for clip, value in p["clips"].items():
        if base in BESPOKE and clip in ("attack_basic", "attack_heavy", "ultimate"):
            continue
        if clip in p.get("kept", ()):
            continue                            # the pre-palette file stays (KEPT)
        if clip == "idle_combat" and value == "ready":
            value = f"ready:{p['guard']}"       # the guard shipped first, the ready stance made over it
        argv.append(f"{clip}={value}")
    argv += ["idle=natural", "--bundle", str(bundle)] + (["--real"] if real else [])
    if p.get("height"):
        argv += ["--height", str(p["height"])]
    return argv


def cmd_roll(a):
    """The roll-out (Docs/MOTION.md, *As rolled out*): every family of the
    plan (or the ones named) shipped through `ship`, `--jobs` at a time, a
    log per family in WORK/logs; `--skip-done` passes over a family whose
    report is already written (a resumed run)."""
    from concurrent.futures import ThreadPoolExecutor
    plan, _ = make_plan()
    names = a.families or sorted(plan)
    missing = [n for n in names if n not in plan]
    if missing:
        sys.exit(f"not in the plan: {', '.join(missing)}")
    bundle = Path(a.bundle).resolve()
    logs = WORK / "logs"
    logs.mkdir(parents=True, exist_ok=True)
    todo = [n for n in names if not (a.skip_done and report_path(bundle, n).exists())]
    print(f"{len(todo)} famil{'y' if len(todo) == 1 else 'ies'} to ship into {bundle} ({len(names) - len(todo)} done), {a.jobs} at a time")

    def run(name):
        argv = [sys.executable, str(Path(__file__).resolve()), "ship"] + ship_argv(name, plan[name], bundle, a.real)
        if a.dry_run:
            return name, 0, " ".join(argv[2:]), 0.0
        t = time.time()
        with open(logs / f"{name}.log", "w") as log:
            r = subprocess.run(argv, stdout=log, stderr=subprocess.STDOUT, cwd=str(REPO))
        text = (logs / f"{name}.log").read_text()
        probs = [l.strip() for l in text.splitlines() if "PROBLEM" in l]
        return name, r.returncode, "; ".join(probs[:3]), time.time() - t

    failed = []
    with ThreadPoolExecutor(max_workers=max(1, a.jobs)) as pool:
        for name, code, note, dt in pool.map(run, todo):
            if code or note and not a.dry_run:
                failed.append(name)
            print(f"  {name:22s} {'ok' if not code else 'FAILED'} {dt:5.0f} s  {note}", flush=True)
    print(f"{len(todo) - len(failed)} shipped, {len(failed)} failed{': ' + ', '.join(failed) if failed else ''} (logs in {logs})")
    if failed:
        sys.exit(1)


# ---------------------------------------------------------------------------
# Idle breaks (Docs/PLAN.md, *Natural poses*, steps 7 and 8.3-8.4; 2026-09-25)
# ---------------------------------------------------------------------------
#
# A break is the family's <family>_break.usdz: a one-shot PoseLayer lays over
# the running natural idle after 12-18 s untouched on a stage, and on the
# island for most stirs (in over 0.4 s from its first key, let go 0.5 s
# before its last). Made here from a bought preset's calm window (PRESET_CUTS'
# `brk`), onto the family's own carrier, straight - no mesh.py, so no root
# lock:
#   additive  every joint's turn since the window's first key, in the joint's
#             own frame, laid over the natural idle's MEAN pose, and the
#             pelvis's travel since then turned to the idle's facing. The
#             preset's absolute pose puts the donor's arms on the figure, and
#             an arm away from the bind drags the cloth welded to it (Hera's
#             robe 753 edges past 3x on 336 absolute); laid over the idle, a
#             look moves the head and the body round the family's own safe
#             hang (Aphrodite on 11: 137 -> 4).
#   ends      eased into the idle's mean pose over BREAK_EASE, so the first and
#             last keys ARE the idle's (the runtime's blend then crosses
#             nothing).
#   feet      planted on the idle's own spots every key by two-bone IK, the
#             knees on the idle's poles, both feet pivoting on the spot with
#             BREAK_PIVOT of the pelvis's turn, the pelvis lowered (smoothed)
#             where a leg could not reach - so nothing slides, in the break or
#             in the blend (the idle and its alt plant the same spots). A
#             preset that lifts a foot (255's stamp, 306's hop) is never a
#             break.
# The ladder (BREAK_LADDER): where the whole break tears more than the idle
# it plays over, the pelvis's turn and travel, the spine and (for a look) the
# arms are quietened in steps, down to the head alone for a look; a gesture
# keeps its arms and goes to the next candidate instead. Guards (the natural
# idle's, measured on the shipped base at every key): no more edges past 3x
# than the idle's (clip_fix's sum; MOTION.md section 10's rule), no forearm or
# hand through the body past the idle's own count or ARM_COUNT, a foot joint
# within a millimetre of its spot and the soles within the floor guard, and
# for a robed family (the plan's `robed`) hands that stay low (BREAK_HANDS_LOW
# of the height over where the idle holds them - the dress is welded to
# them). A family whose every candidate fails gets no file: PoseLayer then
# breaks with its victory's measured window (`victory` in the report).

# Each archetype's candidates, the first preferred (Docs/PLAN.md, the palette
# table): the sovereign's slow survey, the champion's short look, the
# brute's axe look, the mystic's turn, the trickster's hand rub, the hunter's
# and the beast's alert scan - and the construct's, a sentry's; the soldier's
# weapon lowered and a look. 11 (a still guard) carries no gesture and 12
# (the stretch) only a grace's; 377 and 231 are stances, the four victories
# victories. The awakened form takes its family's row (natural_idle.arch_for,
# the stages' archetype: Bastet in the grace row, Serqet the champion's).
BREAKS = {
    "sovereign": [336, 338, 0],
    "champion": [338, 334, 336],
    "soldier": [334, 338, 2],
    "brute": [335, 338, 336],
    "mystic": [0, 336, 338],
    "grace": [12, 336, 338],
    "trickster": [318, 338, 0],
    "hunter": [2, 338, 334],
    "beast": [2, 338, 336],
    "construct": [2, 338, 0],
}
# The weapon's side of a lateral preset (as PRESET_SIDE): mirrored on the
# donor to a left-handed family. A look that is not lateral is mirrored for
# half the roster by a hash of the family, so the looks go both ways.
BREAK_SIDE = {2: "R", 334: "R", 335: "R", 12: "R"}
# (pelvis turn, pelvis travel, spine, arms, neck and head): each rung's share
# of the preset's own; a look may go down to the head alone and then to half
# the head's turn (a glance), a gesture keeps its arms.
BREAK_LADDER = {
    "look": [(1.0, 1.0, 1.0, 1.0, 1.0), (0.6, 0.6, 0.6, 0.6, 1.0), (0.3, 0.3, 0.35, 0.35, 1.0),
             (0.1, 0.1, 0.15, 0.15, 1.0), (0.0, 0.0, 0.0, 0.0, 1.0), (0.0, 0.0, 0.0, 0.0, 0.5)],
    "gesture": [(1.0, 1.0, 1.0, 1.0, 1.0), (0.5, 0.5, 0.6, 1.0, 1.0), (0.2, 0.2, 0.3, 1.0, 1.0)],
}
# Breaks the judge held (2026-09-25): no file is written for these (a stale
# one is removed), so PoseLayer breaks with the victory's window until the
# `retry` passes a judge; `breaks --retry-held` makes the retry into --out
# for its board. The trickster's hand rub (318) is not held here: MOTION.md
# section 10's rule refused it on all ten (Dionysus 3 edges past 3x against
# the look-around's 0, the Satyr 7), and relaxing that rule is the owner's.
BREAK_HOLD = {
    "nephthys": dict(reason="preset 0 whole turns her head 131 degrees left and 104 right: her body goes to profile "
                            "twice in 1.2 s while her feet swivel 27 degrees on the spot, so she reads as spinning "
                            "(on the donor the same turns are stepped)",
                     retry=dict(rung=2)),        # further down the ladder, as Ptah's 83 degrees
}
BREAK_EASE = (0.5, 0.6)      # s: out of the idle's mean pose, and back into it
BREAK_PIVOT = (0.5, 30.0)    # the share of the pelvis's turn the planted feet pivot with, and its cap (degrees)
BREAK_FPS = 20.0             # keys a second, as the natural idle (tools/natural_idle.py FPS)
BREAK_HANDS_LOW = 0.10       # a robed family's hands may rise this share of the height over the idle's, no more
BREAK_SLIDE = 0.001          # m: a foot joint off its spot


def _ni():
    import natural_idle
    return natural_idle


def _quiet(fn, *a, **k):
    import io
    import contextlib
    with contextlib.redirect_stdout(io.StringIO()):
        return fn(*a, **k)


def _fk(rig, T, R):
    """World rotations (J,3,3) and positions (J,3) of one key."""
    ni = _ni()
    J = len(rig.names)
    local = np.array([character.trs(T[j], R[j], rig.parts[j][2]) for j in range(J)])
    W = character.world_from_local(local, rig.parents)
    return np.array([ni.rotation_part(m) for m in W]), W[:, 3, :3].copy()


def _yaw(rig, Rw, j):
    """Degrees the joint has turned about the vertical since the bind (+: toward the figure's left)."""
    v = np.array([0.0, 0.0, 1.0]) @ (rig.rot0[j].T @ Rw[j])
    return float(np.degrees(np.arctan2(v[0], v[2])))


class BreakFamily:
    """A family's carrier (the skeleton the break is written on), rig,
    shipped base, and the natural idle the break plays over: its mean pose
    and where it plants the feet."""

    def __init__(self, family, idle_bundle=None):
        ni = _ni()
        self.family = family
        self.carrier, self.cpath, self.bpath = ni.carrier_for(family)
        self.base = ni.Base(self.bpath)
        self.rig = rig = ni.Rig(self.carrier, self.base.c)
        path = Path(idle_bundle) / f"{family}_idle.usdz" if idle_bundle else None
        self.idle_path = path if path is not None and path.exists() else APP_BUNDLE / f"{family}_idle.usdz"
        ic = _quiet(character.read_usdz, str(self.idle_path))
        if list(ic.joints) != list(self.carrier.joints):
            raise ValueError(f"{family}: the idle's joints are not its carrier's")
        self.idle, self.joints = ic.anim, ic.joints
        n = len(self.idle["T"]) - 1                       # a loop's last key is its first
        R = np.asarray(self.idle["R"][:n], float)
        R = R * np.where(np.sum(R * R[:1], axis=2, keepdims=True) < 0, -1.0, 1.0)
        q = R.mean(axis=0)
        self.mean_R = q / np.linalg.norm(q, axis=1, keepdims=True)
        self.mean_T = np.asarray(self.idle["T"][:n], float).mean(axis=0)
        self.Rw_mean, self.Pw_mean = _fk(rig, self.mean_T, self.mean_R)
        Rw0, Pw0 = _fk(rig, np.asarray(self.idle["T"][0], float), np.asarray(self.idle["R"][0], float))
        self.foot = {}
        for s in "LR":
            g = rig.leg[s]
            H, K, F = Pw0[g["upleg"]], Pw0[g["knee"]], Pw0[g["foot"]]
            axis = ni.unit(F - H)
            off = (K - H) - ((K - H) @ axis) * axis
            pole = ni.unit(off) if np.linalg.norm(off) > 1e-6 else rig.knee_pole[s]
            self.foot[s] = dict(pos=F.copy(), rot=Rw0[g["foot"]].copy(), pole=pole)
        self.pelvis_yaw = _yaw(rig, self.Rw_mean, rig.hips)
        self.body = [rig.hips] + rig.spine + rig.neck + [rig.head] + [rig.arm[s][k] for s in "LR"
                                                                       for k in ("upper", "fore", "hand")]
        self._idle_m = None

    def idle_measure(self):
        """The guards' measures of the idle itself, at every key: the bar."""
        if self._idle_m is None:
            n = len(self.idle["T"])
            self._idle_m = self.base.measure(self.idle, self.joints, self.rig, frames=np.arange(n))
        return self._idle_m


def _plant(bf, T, R):
    """Every key's legs solved onto the idle's foot spots (in place): the
    pelvis lowered (smoothed) where a leg cannot reach, the feet pivoting on
    the spot with the pelvis's turn, the knees on the idle's poles."""
    ni = _ni()
    rig = bf.rig
    n = len(R)
    P0, R0 = rig.pos0, rig.rot0
    Yax = np.array([0.0, 1.0, 0.0])

    def reach(side):
        br = rig.bind_reach[side]
        return min(0.995, br + 0.01) if br < 0.985 else 0.995
    drops = np.zeros(n)
    for i in range(n):
        _, Pw = _fk(rig, T[i], R[i])
        for s in "LR":
            g = rig.leg[s]
            a = np.linalg.norm(P0[g["knee"]] - P0[g["upleg"]])
            b = np.linalg.norm(P0[g["foot"]] - P0[g["knee"]])
            v = bf.foot[s]["pos"] - Pw[g["upleg"]]
            rm = reach(s) * (a + b)
            drops[i] = max(drops[i], -v[1] - np.sqrt(max(rm * rm - v[0] ** 2 - v[2] ** 2, 0.0)))
    drops = np.maximum(drops, 0.0)
    if drops.max() > 0:
        pad = np.pad(drops, 4, mode="edge")
        wide = np.array([pad[i:i + 9].max() for i in range(n)])
        g = np.exp(-0.5 * (np.arange(-6, 7) / 2.0) ** 2)
        drops = np.convolve(np.pad(wide, 6, mode="edge"), g / g.sum(), mode="valid")
    for r in np.where(rig.parents < 0)[0]:
        T[:, r, 1] -= drops
    pivot = 0.0
    share, cap = BREAK_PIVOT
    for i in range(n):
        Rw, Pw = _fk(rig, T[i], R[i])
        turn_by = float(np.clip(share * (((_yaw(rig, Rw, rig.hips) - bf.pelvis_yaw) + 180) % 360 - 180), -cap, cap))
        pivot = max(pivot, abs(turn_by))
        turn = ni.about(Yax, turn_by)
        for s in "LR":
            g = rig.leg[s]
            u, k, f = g["upleg"], g["knee"], g["foot"]
            a, b = np.linalg.norm(P0[k] - P0[u]), np.linalg.norm(P0[f] - P0[k])
            H, F = Pw[u], bf.foot[s]["pos"]
            d = min(max(np.linalg.norm(F - H), abs(a - b) + 1e-4), (a + b) * 0.9995)
            axis = ni.unit(F - H)
            pole = bf.foot[s]["pole"] @ turn
            pole = ni.unit(pole - (pole @ axis) * axis)
            x = (a * a - b * b + d * d) / (2 * d)
            K = H + axis * x + pole * np.sqrt(max(a * a - x * x, 0.0))
            pole0 = rig.knee_pole[s]
            Rw[u] = R0[u] @ ni.frame_rotation(P0[k] - P0[u], pole0, K - H, pole)
            Pw[k] = H + (P0[k] - P0[u]) @ R0[u].T @ Rw[u]
            Rw[k] = R0[k] @ ni.frame_rotation(P0[f] - P0[k], pole0, F - Pw[k], pole)
            Rw[f] = bf.foot[s]["rot"] @ turn
            for j in (u, k, f):
                p = int(rig.parents[j])
                q = character.rot_to_quat(Rw[j] @ Rw[p].T if p >= 0 else Rw[j])
                R[i, j] = -q if np.dot(q, R[i, j]) < 0 else q
            for t in g["toes"]:
                R[i, t] = bf.mean_R[t]
    return dict(drop_cm=round(float(drops.max()) * 100, 1), pivot=round(pivot, 1))


_DONOR_RIGS = {}


def donor_rig(pid):
    """The Rig of the family the preset was bought on (its shipped carrier:
    the archive's own skeleton, names and all), cached."""
    ni = _ni()
    donor = load_manifest()["presets"].get(str(int(pid)), {}).get("donor", "shield_maiden_serious")
    fam = donor[:-len("_serious")] if donor.endswith("_serious") else donor
    if fam not in _DONOR_RIGS:
        c, _, bp = ni.carrier_for(fam)
        _DONOR_RIGS[fam] = ni.Rig(c, _quiet(character.read_usdz, str(bp)))
    return _DONOR_RIGS[fam]


def by_role(src_rig, tgt_rig):
    """{source joint name: target joint name}, matched by the part each is
    found to be (natural_idle.Rig: by position and by the skull's skin),
    never by name. Eleven rigs call the joint over the hips `neck` and skin
    the skull to Head1 or Spine1 (Zeus, Thor, the smith ...), and three skin
    it to `neck` (Hephaestus, Fenrir, Ullr): matched by name, the donor's
    neck turn went into Zeus's lower back and his skull never turned (the
    retarget matches by name; `ship` still does). A chain of another length
    maps its ends to the ends and spreads the middle; a source joint with no
    place is left out (the world-space retarget still turns the joints above
    it by their own)."""
    out = {}

    def chain(sl, tl):
        if not sl or not tl:
            return
        for i, sj in enumerate(sl):
            k = int(round(i * (len(tl) - 1) / max(len(sl) - 1, 1))) if len(sl) > 1 else len(tl) - 1
            t = tgt_rig.names[tl[k]]
            if t not in out.values():
                out[src_rig.names[sj]] = t
    chain([src_rig.hips], [tgt_rig.hips])
    chain(src_rig.spine, tgt_rig.spine)
    chain(src_rig.neck, tgt_rig.neck)
    chain([src_rig.head], [tgt_rig.head])
    for s in "LR":
        chain([src_rig.leg[s][k] for k in ("upleg", "knee", "foot")] + list(src_rig.leg[s]["toes"][:1]),
              [tgt_rig.leg[s][k] for k in ("upleg", "knee", "foot")] + list(tgt_rig.leg[s]["toes"][:1]))
        chain([src_rig.arm[s][k] for k in ("clav", "upper", "fore", "hand") if src_rig.arm[s][k] is not None],
              [tgt_rig.arm[s][k] for k in ("clav", "upper", "fore", "hand") if tgt_rig.arm[s][k] is not None])
    return out


def make_break(bf, pid, mirror=False, rung=(1.0, 1.0, 1.0, 1.0, 1.0), fps=BREAK_FPS):
    """-> (anim on the family's carrier at `fps` keys a second, facts): the
    preset's PRESET_CUTS window laid over the idle's mean pose (additive,
    each part scaled by `rung`), its ends eased into that pose, its feet
    planted on the idle's spots."""
    ni = _ni()
    from retarget import Motion, retarget
    rig = bf.rig
    J = len(rig.names)
    roots = np.where(rig.parents < 0)[0]
    raw = Motion.load(archive_path(pid))
    if mirror:
        raw, _ = mirror_motion(raw)
    # the source's joints renamed to the target's by part (by_role), so the
    # retarget's name match lands the donor's head on the skull's joint
    names = by_role(donor_rig(pid), rig)
    raw = Motion(["/".join(j.split("/")[:-1] + [names.get(j.split("/")[-1], "_unplaced_" + j.split("/")[-1])])
                  for j in raw.joints], raw.parents, raw.rest_local, raw.anim, raw.source)
    cut, _ = prepare(raw, "break", PRESET_CUTS.get(int(pid), {}).get("window"))
    anim, _, _ = retarget(cut, Motion.from_char(bf.carrier))
    F = len(anim["T"])
    N = int(round((F - 1) * fps / float(anim["fps"]))) + 1
    anim = resample(anim, np.linspace(0, F - 1, N))
    T = np.asarray(anim["T"], float).copy()
    R = np.asarray(anim["R"], float).copy()
    Rw, _ = _fk(rig, T[0], R[0])
    facing = ni.about([0.0, 1.0, 0.0], ((bf.pelvis_yaw - _yaw(rig, Rw, rig.hips)) + 180) % 360 - 180)
    pelvis, travel, spine, arms, head = rung
    share = {int(j): pelvis for j in roots}
    share.update({j: spine for j in rig.spine})
    share.update({j: head for j in list(rig.neck) + [rig.head]})
    share.update({rig.arm[s][k]: arms for s in "LR" for k in ("clav", "upper", "fore", "hand")
                  if rig.arm[s][k] is not None})
    Mref = [character.quat_to_rot(R[0, j]) for j in range(J)]
    Mbase = [character.quat_to_rot(bf.mean_R[j]) for j in range(J)]
    T0 = T[0].copy()
    for i in range(N):
        for j in range(J):
            D = character.quat_to_rot(R[i, j]) @ Mref[j].T          # the joint's turn since the window's first key
            if share.get(j, 1.0) != 1.0:
                D = ni.slerp_rot(D, share[j])
            R[i, j] = character.rot_to_quat(D @ Mbase[j])
        for r in roots:
            T[i, r] = bf.mean_T[r] + travel * ((T[i, r] - T0[r]) @ facing)
    t = np.arange(N) / fps
    dur = (N - 1) / fps
    ease_in, ease_out = BREAK_EASE

    def smooth(x):
        x = np.clip(x, 0.0, 1.0)
        return x * x * (3 - 2 * x)
    e = smooth(t / ease_in) * smooth((dur - t) / ease_out)
    for i in range(N):
        R[i] = slerp(bf.mean_R, R[i], np.full(J, e[i]))
        for r in roots:
            T[i, r] = bf.mean_T[r] * (1 - e[i]) + T[i, r] * e[i]
    facts = _plant(bf, T, R)
    for i in range(1, N):
        R[i] *= np.where(np.sum(R[i] * R[i - 1], axis=1) < 0, -1.0, 1.0)[:, None]
    scales = np.array([rig.parts[j][2] for j in range(J)])
    out = {"T": T.astype(np.float32), "R": R.astype(np.float32),
           "S": np.repeat(scales[None], N, 0).astype(np.float32), "fps": fps}
    facts.update(keys=N, seconds=round(dur, 2))
    return out, facts


def break_measure(bf, anim):
    """The guards' measures of a break at every key, and the break's own:
    each foot joint's distance from its spot, the hands' rise over the
    idle's (share of the height), the head's turn and the widest joint angle
    off the idle's mean (what makes it a break at all)."""
    rig = bf.rig
    n = len(anim["T"])
    m = bf.base.measure(anim, bf.joints, rig, frames=np.arange(n))
    slide, hands, yaws, dist = 0.0, -1.0, [], 0.0
    for i in range(n):
        Rw, Pw = _fk(rig, anim["T"][i], anim["R"][i])
        for s in "LR":
            slide = max(slide, float(np.linalg.norm(Pw[rig.leg[s]["foot"]] - bf.foot[s]["pos"])))
            hands = max(hands, float(Pw[rig.arm[s]["hand"], 1] - bf.Pw_mean[rig.arm[s]["hand"], 1]))
        yaws.append(_yaw(rig, Rw, rig.head) - _yaw(rig, bf.Rw_mean, rig.head))
        d = [np.degrees(np.arccos(np.clip((np.trace(Rw[j].T @ bf.Rw_mean[j]) - 1) / 2, -1, 1))) for j in bf.body]
        dist = max(dist, float(np.mean(d)))
    yaws = (np.array(yaws) + 180) % 360 - 180
    m.update(slide_mm=round(slide * 1000, 2), hands=round(hands / rig.height, 3),
             look=(round(float(yaws.min()), 1), round(float(yaws.max()), 1)), reach_deg=round(dist, 1))
    return m


def break_guard(bf, m, robed):
    """The lines that refuse a break (MOTION.md section 10's rule and the natural idle's guards)."""
    ni = _ni()
    bar = bf.idle_measure()
    fails = []
    if m["over3"] > bar["over3"]:
        fails.append(f"tears {m['over3']} edges past 3x against the idle's {bar['over3']}")
    through = m["through"] + m["through_held"]
    if through > max(ni.ARM_COUNT, bar["through"] + bar["through_held"]):
        fails.append(f"an arm through the body ({m['through']} arm, {m['through_held']} held)")
    if m["slide_mm"] > BREAK_SLIDE * 1000:
        fails.append(f"a foot {m['slide_mm']} mm off its spot")
    sink_ok = ni.override_for(bf.family).get("sink_ok", ni.FLOOR_SINK * max(1.0, bf.rig.height / 1.9))
    if m["sink_mm"] > max(1000 * sink_ok, bar["sink_mm"] + 0.5):
        fails.append(f"a sole {m['sink_mm']} mm into the floor")
    if m["floor_mm"] > max(ni.FLOOR_DRIFT * 1000, bar["floor_mm"] + 0.5):
        fails.append(f"a foot {m['floor_mm']} mm off the floor")
    if robed and m["hands"] > BREAK_HANDS_LOW:
        fails.append(f"the hands rise {m['hands'] * 100:.0f}% of the height (a robe is welded to them)")
    return fails


def break_mirror(family, pid):
    """Whether the preset is mirrored for this family: a lateral one to a
    left-handed family's weapon hand; a look by a hash of the family's key,
    so half the roster looks the other way first."""
    import hashlib
    side = BREAK_SIDE.get(int(pid))
    if side:
        hand = weapon_hand(family)
        return hand is not None and hand != side
    return int(hashlib.sha256(f"{family}:break".encode()).hexdigest()[:8], 16) % 2 == 1


def robed_families():
    import io
    import contextlib
    with contextlib.redirect_stderr(io.StringIO()):
        plan, _ = make_plan()
    return {f for f, p in plan.items() if p["kind"] == "robed"}


def break_for(family, out_dir, idle_bundle=None, robed=None, retry_held=False):
    """The family's break: the archetype's candidates down their ladders,
    the first that passes every guard written as <family>_break.usdz into
    `out_dir` (made in a work folder, re-read by character.verify, bound as
    the base). -> the report: the deal, every try, or `victory` when none
    passed (PoseLayer then breaks with the victory's measured window). A
    family in BREAK_HOLD gets no file (`held`, a stale one removed) unless
    `retry_held`, which starts its ladders at the hold's `retry` rung."""
    import shutil
    import tempfile
    import hashlib
    ni = _ni()
    t0 = time.time()
    arch = ni.arch_for(family)
    rep = dict(family=family, archetype=arch, tries=[])
    hold = BREAK_HOLD.get(family)
    if ni.hold_reason(family):                   # the idle itself is held on the stood guard: nothing to break over
        hold, retry_held = dict(reason=f"its idle is held ({ni.hold_reason(family)})"), False
    if hold and not retry_held:
        stale = Path(out_dir) / f"{family}_break.usdz"
        if stale.exists():
            stale.unlink()
        rep.update(deal="held", reason=hold["reason"], secs=0.0)
        return rep
    first_rung = (hold or {}).get("retry", {}).get("rung", 0) if retry_held else 0
    if robed is None:
        robed = family in robed_families()
    rep["robed"] = bool(robed)
    bf = BreakFamily(family, idle_bundle)
    rep["idle"] = str(bf.idle_path)
    rep["idle_sha"] = hashlib.sha256(bf.idle_path.read_bytes()).hexdigest()[:12]
    bar = bf.idle_measure()
    rep["idle_over3"] = bar["over3"]
    for pid in BREAKS.get(arch, []):
        kind = PRESET_CUTS.get(pid, {}).get("brk")
        mirror = break_mirror(family, pid)
        for k, rung in enumerate(BREAK_LADDER[kind]):
            if k < first_rung:
                continue
            anim, facts = make_break(bf, pid, mirror, rung)
            m = break_measure(bf, anim)
            fails = break_guard(bf, m, robed)
            rep["tries"].append(dict(preset=pid, rung=k, over3=m["over3"], fails=fails))
            if fails and kind == "gesture" and any("hands rise" in x for x in fails):
                break                                 # a robed figure's gesture: no rung lowers the hands
            if fails:
                continue
            work = Path(tempfile.mkdtemp(prefix="break_"))
            try:
                c = copy_char(bf.carrier)
                c.anim, c.name = anim, family
                made = work / f"{family}_break.usdz"
                character.write_usdz(c, made)
                vf = _quiet(character.verify, made, check_bounds=False, quiet=True)
                probs = [x for x in vf["problems"] if not x.startswith("feet at")]
                probs += bind_against_base(work, family, ["break"])       # against the shipped base
                if probs:
                    rep["tries"][-1]["fails"] = probs
                    continue
                Path(out_dir).mkdir(parents=True, exist_ok=True)
                shutil.copyfile(made, Path(out_dir) / made.name)
            finally:
                shutil.rmtree(work, ignore_errors=True)
            rep.update(deal=pid, name=PRESET_NAMES.get(str(pid), ""), rung=k, share=list(rung), mirrored=mirror,
                       seconds=facts["seconds"], keys=facts["keys"], pivot=facts["pivot"], drop_cm=facts["drop_cm"],
                       over3=m["over3"], max=m["max"], through=[m["through"], m["through_held"]],
                       slide_mm=m["slide_mm"], sink_mm=m["sink_mm"], floor_mm=m["floor_mm"], hands=m["hands"],
                       look=m["look"], reach_deg=m["reach_deg"], bytes=(Path(out_dir) / f"{family}_break.usdz").stat().st_size)
            rep["secs"] = round(time.time() - t0, 1)
            return rep
    rep["deal"] = "victory"
    rep["secs"] = round(time.time() - t0, 1)
    stale = Path(out_dir) / f"{family}_break.usdz"
    if stale.exists():
        stale.unlink()
    return rep


def copy_char(c):
    import copy
    return copy.copy(c)


def _break_job(args):
    family, out, idle_bundle, robed, retry_held = args
    try:
        return break_for(family, out, idle_bundle, robed, retry_held)
    except Exception as e:  # noqa: BLE001 - one family's fault is reported, the roster goes on
        return dict(family=family, deal="error", error=f"{type(e).__name__}: {e}")


def break_line(r):
    if r.get("deal") in ("victory", "error", "held"):
        why = r.get("error") or r.get("reason") or "; ".join(f"{t['preset']}/{t['rung']}: {t['fails'][0]}"
                                                              for t in r.get("tries", [])[-3:])
        return f"{r['family']:22s} {r.get('archetype') or '':9s} {r['deal'].upper():8s} {why}"
    share = "whole" if r["rung"] == 0 else "rung %d %s" % (r["rung"], "/".join(f"{x:g}" for x in r["share"]))
    return (f"{r['family']:22s} {r['archetype']:9s} {r['deal']:>4} {r['name'][:30]:30s} {'mirrored ' if r['mirrored'] else ''}{share}; "
            f"{r['seconds']} s, past 3x {r['over3']} (idle {r['idle_over3']}), look {r['look'][0]:+.0f}/{r['look'][1]:+.0f} deg, "
            f"hands {r['hands'] * 100:+.0f}%, pivot {r['pivot']}, drop {r['drop_cm']} cm, {r['bytes'] // 1024} KB, {r['secs']} s")


def cmd_breaks(a):
    """Every family's break (or the ones named) into --out, --jobs at a
    time, a line each and the reports as JSON. Never the app's bundle
    without --real."""
    from concurrent.futures import ProcessPoolExecutor
    out = Path(a.out).resolve()
    if out == APP_BUNDLE.resolve() and not a.real:
        sys.exit("that is the app's bundle; pass --real to write it")
    fams = a.families or sorted(p.name[:-len("_idle.usdz")] for p in APP_BUNDLE.glob("*_idle.usdz"))
    robed = robed_families()
    jobs = [(f, str(out), a.idle_bundle, f in robed, a.retry_held) for f in fams]
    reports = []
    with ProcessPoolExecutor(max_workers=max(1, a.jobs)) as pool:
        for r in pool.map(_break_job, jobs):
            reports.append(r)
            print(break_line(r), flush=True)
    dealt = [r for r in reports if r.get("deal") not in ("victory", "error", "held")]
    size = sum(r["bytes"] for r in dealt)
    print(f"{len(dealt)} breaks written ({size / 1048576:.1f} MB), {sum(r.get('deal') == 'victory' for r in reports)} "
          f"on their victory, {sum(r.get('deal') == 'held' for r in reports)} held (BREAK_HOLD), "
          f"{sum(r.get('deal') == 'error' for r in reports)} errors")
    if a.json:
        before = json.loads(Path(a.json).read_text()) if Path(a.json).exists() else {}
        before.update({r["family"]: r for r in reports})
        Path(a.json).write_text(json.dumps(before, indent=1) + "\n")


def cmd_break_board(a):
    """A family's natural idle, then its break at three instants - the one
    farthest from the idle and the two halfway to either end - front,
    three-quarter and side, on the shipped base."""
    from PIL import Image, ImageDraw
    import preview
    ni = _ni()
    ni.views_setup()
    views = a.views.split(",")
    rows = []
    for fam in a.families:
        path = Path(a.bundle) / f"{fam}_break.usdz"
        if not path.exists():
            print(f"{fam}: no break in {a.bundle}")
            continue
        bf = BreakFamily(fam, a.idle_bundle)
        c = _quiet(character.read_usdz, str(path))
        n = len(c.anim["T"])
        far = []
        for i in range(n):
            Rw, _ = _fk(bf.rig, c.anim["T"][i], c.anim["R"][i])
            far.append(np.mean([np.degrees(np.arccos(np.clip((np.trace(Rw[j].T @ bf.Rw_mean[j]) - 1) / 2, -1, 1)))
                                for j in bf.body]))
        apex = int(np.argmax(far))
        frames = sorted({max(1, apex // 2), apex, min(n - 2, (apex + n - 1) // 2)})
        idle_cells, width = ni.render_cells(bf.base, bf.idle, bf.joints, [0], views, a.size)
        cells, _ = ni.render_cells(bf.base, c.anim, c.joints, frames, views, a.size)
        rows.append((fam, ni.arch_for(fam), idle_cells + cells, width, n, c.anim["fps"], a.notes.get(fam, "")))
    if not rows:
        sys.exit("nothing to board")
    width = rows[0][3]
    cols = max(len(r[2]) for r in rows)
    head, lab = 22, 18
    rh = head + len(views) * a.size + lab + 8
    sheet = Image.new("RGB", (cols * width + 30, rh * len(rows) + 6), (24, 24, 28))
    d = ImageDraw.Draw(sheet)
    for ri, (fam, arch, cells, width, n, fps, note) in enumerate(rows):
        y0 = 4 + ri * rh
        d.text((8, y0), f"{fam} ({arch}) {note}", fill=(160, 230, 160), font=preview.font(14))
        for ci, (f, col) in enumerate(cells):
            x = 10 + ci * width + (10 if ci else 0)
            for vi, img in enumerate(col):
                sheet.paste(img, (x, y0 + head + vi * a.size))
            label = "the natural idle" if ci == 0 else f"break {f / fps:.1f} s of {(n - 1) / fps:.1f}"
            d.text((x + 4, y0 + head + len(views) * a.size + 1), label, fill=(240, 220, 150), font=preview.font(13))
    sheet.save(a.out, quality=86)
    print(f"  board -> {a.out} {sheet.size}")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    p = sub.add_parser("buy"); p.add_argument("donor"); p.add_argument("presets", nargs="+")
    p.add_argument("--floor", type=int, default=500); p.add_argument("--cap", type=int, default=45)
    p = sub.add_parser("archive"); p.add_argument("presets", nargs="*"); p.add_argument("--keep", action="store_true"); p.add_argument("--force", action="store_true")
    p = sub.add_parser("free"); p.add_argument("presets", nargs="+"); p.add_argument("--prefer", default="shield_maiden_serious")
    p.add_argument("--keep", action="store_true"); p.add_argument("--force", action="store_true")
    sub.add_parser("list")
    p = sub.add_parser("ship"); p.add_argument("asset"); p.add_argument("family"); p.add_argument("assign", nargs="+", help="clip=preset_id | clip=path.motion.npz | idle=natural | idle_combat=natural")
    p.add_argument("--bundle", required=True); p.add_argument("--height", type=float); p.add_argument("--keep", action="store_true"); p.add_argument("--real", action="store_true")
    p.add_argument("--with-base", action="store_true", help="also build the base (no LOD) from the same rig, so a board in a scratch bundle is self-consistent")
    p.add_argument("--no-mirror", action="store_true", help="never mirror a clip to the family's weapon hand (WEAPON_HAND), for a before/after board")
    p = sub.add_parser("board"); p.add_argument("family"); p.add_argument("clips"); p.add_argument("--bundle", required=True)
    p.add_argument("--base"); p.add_argument("--out", required=True); p.add_argument("--size", type=int, default=240); p.add_argument("--views", default="front,side")
    p.set_defaults(notes={})
    p = sub.add_parser("board-archive"); p.add_argument("presets", nargs="+"); p.add_argument("--donor"); p.add_argument("--out", required=True)
    p.add_argument("--size", type=int, default=220); p.add_argument("--views", default="front,side"); p.add_argument("--frames", type=int, default=8)
    p = sub.add_parser("compare"); p.add_argument("preset"); p.add_argument("asset"); p.add_argument("--keep", action="store_true")
    p = sub.add_parser("roll", help="ship the plan onto every family (or the ones named), --jobs at a time")
    p.add_argument("families", nargs="*"); p.add_argument("--bundle", required=True); p.add_argument("--real", action="store_true")
    p.add_argument("--jobs", type=int, default=2); p.add_argument("--skip-done", action="store_true"); p.add_argument("--dry-run", action="store_true")
    p = sub.add_parser("plan", help="deal every family its own five clips from the archived palette")
    p.add_argument("--markdown", action="store_true"); p.add_argument("--json")
    p = sub.add_parser("breaks", help="every family's idle break (<family>_break.usdz) into --out (BREAKS, make_break)")
    p.add_argument("families", nargs="*"); p.add_argument("--out", required=True); p.add_argument("--real", action="store_true")
    p.add_argument("--idle-bundle", help="the natural idles the breaks play over (default: the app's bundle)")
    p.add_argument("--jobs", type=int, default=2); p.add_argument("--json")
    p.add_argument("--retry-held", action="store_true", help="make a BREAK_HOLD family's retry (for its board)")
    p = sub.add_parser("break-board", help="families' natural idle, then the break at three instants")
    p.add_argument("families", nargs="+"); p.add_argument("--bundle", required=True, help="where the breaks are")
    p.add_argument("--idle-bundle"); p.add_argument("--out", required=True); p.add_argument("--size", type=int, default=260)
    p.add_argument("--views", default="front,q3,side"); p.set_defaults(notes={})
    a = ap.parse_args()
    {"buy": cmd_buy, "archive": cmd_archive, "free": cmd_free, "list": cmd_list, "ship": cmd_ship,
     "board": cmd_board, "board-archive": cmd_board_archive, "compare": cmd_compare, "plan": cmd_plan, "roll": cmd_roll,
     "breaks": cmd_breaks, "break-board": cmd_break_board}[a.cmd](a)


if __name__ == "__main__":
    main()
