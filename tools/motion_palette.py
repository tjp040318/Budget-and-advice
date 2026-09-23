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

`ship` writes nothing under Pantheon/ unless --bundle names it: the clips are
retargeted onto the family's rig GLB (Art/Models/<asset>.glb) in a work
folder and shipped by tools/mesh.py with its source and bundle folders
pointed there, so grounding, the carrier and the bind check are the same as
any Meshy clip's. A value may also be a .motion.npz path (a god's bespoke
clip) or `stand` for `idle` (tools/stand_idle.py's standing idle, derived
from the idle_combat just shipped).
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
    stand = assign.pop("idle", None) == "stand"
    stance = assign.get("idle_combat")
    stance_stand = stance in ("stand", "half")
    if stance_stand:
        assign["idle_combat"] = "89"          # the guard, then stood up (all the way, or half) and worn as the stance
        stand = True
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
        motion, facts = prepare(Motion.load(source), clip, cut.get("window"), cut.get("blow"), cut.get("loop", False), cut.get("recover", 0))
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
    if stand and stance != "stand":
        stand_idle(1.0)                       # the stages' standing idle, from whatever stance shipped
    rp = report_path(bundle, a.family)
    rp.parent.mkdir(parents=True, exist_ok=True)
    rp.write_text(json.dumps(report, indent=1) + "\n")
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
BESPOKE = {"anubis", "sekhmet", "zeus", "ares", "thoth"}      # Art/Motions/<family>_<clip>.motion.npz
BRUTES = {"minotaur", "cyclops", "frost_troll", "berserker", "draugr", "fenrir", "sobek", "surtr", "heracles", "boss_colossus", "khnum", "taweret"}
HAND_WRITTEN = {"anubis": 4, "sekhmet": 5, "zeus": 5, "ares": 5, "thoth": 5, "heracles": 4, "perseus": 4,
                "shabti": 3, "hoplite": 3, "satyr": 3, "harpy": 3}


def roster_rows():
    """(asset, family, kit field, sentence, grade) for every serious remake."""
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
        base = family.replace("_awakened", "")
        grade = grades.get(base, 5 if family.startswith("boss_") else 4)
        rows.append((asset, family, kit, sentences.get(family, ""), grade))
    return rows


def kind_of(family, kit, sentence):
    import re
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
    """Every family its own combination: the families of a kind dealt the
    pools so that no two share more slots than they must, the 5-stars first
    (they get the first pick of the kind's signature moves), the five gods'
    bespoke attacks kept, an awakened form wearing its family's set."""
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
        pool = {k: [v for v in POOLS[kind][k] if ok(v)] for k in slots}
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
    def label(v):
        v = str(v)
        if v.endswith(".npz"):
            return "own:" + Path(v).name.split("_")[0]
        if v in ("stand", "half"):
            return v
        return v.split("@")[0]
    tuples = [tuple(label(v) for v in p["clips"].values()) for f, p in plan.items() if "_awakened" not in f]
    dupes = len(tuples) - len(set(tuples))
    if a.markdown:
        print("| family | grade | kind | basic | heavy | ultimate | stance | victory |")
        print("|---|---|---|---|---|---|---|---|")
        for f, p in sorted(plan.items(), key=lambda kv: (-kv[1]["grade"], kv[1]["kind"], kv[0])):
            c = p["clips"]
            print(f"| {f} | {p['grade']}★ | {p['kind']} | " + " | ".join(label(c[k]) for k in slots) + " |")
    else:
        for f, p in sorted(plan.items()):
            print(f"{f:24s} {p['grade']} {p['kind']:8s} " + "  ".join(f"{k.split('_')[-1]}={label(v)}" for k, v in p["clips"].items()))
    from collections import Counter
    print(f"\n{len(plan)} families ({len(tuples)} base); identical five-clip sets: {dupes}", file=sys.stderr)
    for kind, ts in sorted(taken.items()):
        trip = Counter(tuple(label(v) for v in t[:3]) for t in ts)
        print(f"  {kind:8s} {len(ts):3d} families, {len(trip)} distinct attack triples, the most shared by {max(trip.values())}", file=sys.stderr)
    if a.json:
        Path(a.json).write_text(json.dumps(plan, indent=1) + "\n")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    p = sub.add_parser("buy"); p.add_argument("donor"); p.add_argument("presets", nargs="+")
    p.add_argument("--floor", type=int, default=500); p.add_argument("--cap", type=int, default=45)
    p = sub.add_parser("archive"); p.add_argument("presets", nargs="*"); p.add_argument("--keep", action="store_true"); p.add_argument("--force", action="store_true")
    p = sub.add_parser("free"); p.add_argument("presets", nargs="+"); p.add_argument("--prefer", default="shield_maiden_serious")
    p.add_argument("--keep", action="store_true"); p.add_argument("--force", action="store_true")
    sub.add_parser("list")
    p = sub.add_parser("ship"); p.add_argument("asset"); p.add_argument("family"); p.add_argument("assign", nargs="+", help="clip=preset_id | clip=path.motion.npz | idle=stand")
    p.add_argument("--bundle", required=True); p.add_argument("--height", type=float); p.add_argument("--keep", action="store_true"); p.add_argument("--real", action="store_true")
    p.add_argument("--with-base", action="store_true", help="also build the base (no LOD) from the same rig, so a board in a scratch bundle is self-consistent")
    p = sub.add_parser("board"); p.add_argument("family"); p.add_argument("clips"); p.add_argument("--bundle", required=True)
    p.add_argument("--base"); p.add_argument("--out", required=True); p.add_argument("--size", type=int, default=240); p.add_argument("--views", default="front,side")
    p.set_defaults(notes={})
    p = sub.add_parser("board-archive"); p.add_argument("presets", nargs="+"); p.add_argument("--donor"); p.add_argument("--out", required=True)
    p.add_argument("--size", type=int, default=220); p.add_argument("--views", default="front,side"); p.add_argument("--frames", type=int, default=8)
    p = sub.add_parser("compare"); p.add_argument("preset"); p.add_argument("asset"); p.add_argument("--keep", action="store_true")
    p = sub.add_parser("plan", help="deal every family its own five clips from the archived palette")
    p.add_argument("--markdown", action="store_true"); p.add_argument("--json")
    a = ap.parse_args()
    {"buy": cmd_buy, "archive": cmd_archive, "free": cmd_free, "list": cmd_list, "ship": cmd_ship,
     "board": cmd_board, "board-archive": cmd_board_archive, "compare": cmd_compare, "plan": cmd_plan}[a.cmd](a)


if __name__ == "__main__":
    main()
