#!/usr/bin/env python3
"""Skill moves (2026-09-25; Docs/PLAN.md *Skills that look like themselves*).

Every skill its own motion: a family's signature basic attack and ultimate
from a sentence (Meshy Text to Motion), and the second skill's shared moves
COMPOSED from single strikes (`compose`), so a three-hit skill strikes three
times and its contacts are known.

A sentence is made once, applied once to the donor rig (the only way Meshy
hands a motion back as a clip), and archived as a `.motion.npz` beside the
presets (`Art/Motions/<key>.motion.npz`). From there `retarget.py` and
`motion_palette.py ship` put it on any rig for nothing. The prime task's own
FBX is an SMPL-H skeleton in a T-pose with a mannequin (16 MB, read on the
25th), not Meshy's rig, so the 3-credit apply is kept: it is Meshy's own
retarget onto the donor's skeleton, the one every archive here is on.

  python3 tools/skill_moves.py say rite_robed 3 "A robed priest raises ..."
  python3 tools/skill_moves.py launch tools/skills/signatures.tsv --only horus,isis
  python3 tools/skill_moves.py run                 # advance every task, archive what finished
  python3 tools/skill_moves.py list
  python3 tools/skill_moves.py contacts Art/Motions/rite_robed.motion.npz --expect 1

The manifest is `Art/Motions/skills.json` (task ids, prompts, what each cost
and where it was archived); a re-run resumes, and never pays twice for a
key whose prompt is unchanged.
"""
import argparse
import csv
import json
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))

REPO = Path(__file__).resolve().parents[1]
MOTIONS = REPO / "Art" / "Motions"
MANIFEST = MOTIONS / "skills.json"
WORK = Path("/tmp/skill_moves")
DONOR = "shield_maiden_serious"
TERMINAL = ("SUCCEEDED", "FAILED", "CANCELED", "EXPIRED")


def now():
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def load():
    if MANIFEST.exists():
        return json.loads(MANIFEST.read_text())
    return {"note": "Skill moves from sentences (tools/skill_moves.py, Docs/PLAN.md *Skills that look like themselves*)",
            "donor": DONOR, "moves": {}}


def save(m):
    """Writes the manifest MERGED with what is on disk, record by record, the
    newer `touched` winning: a long `run` holds its copy for an hour, and a
    plain write from it once undid a judged contact written meanwhile."""
    MOTIONS.mkdir(parents=True, exist_ok=True)
    disk = load() if MANIFEST.exists() else {"moves": {}}
    merged = dict(m)
    moves = dict(disk.get("moves", {}))
    for k, rec in m.get("moves", {}).items():
        old = moves.get(k)
        if old is None or rec.get("touched", 0) >= old.get("touched", 0):
            moves[k] = rec
    merged["moves"] = moves
    tmp = MANIFEST.with_suffix(".tmp")
    tmp.write_text(json.dumps(merged, indent=2) + "\n")
    tmp.replace(MANIFEST)


def touch(rec):
    """Marks a record changed now (the merge in `save` keeps the newest)."""
    rec["touched"] = time.time()
    return rec


def api():
    import meshy
    return meshy, meshy.Meshy(meshy.load_key(None))


def donor_rig(meshy, name):
    man = meshy.load_manifest(name) or sys.exit(f"no manifest for the donor {name}")
    rig = man["stages"].get("rig") or {}
    if rig.get("status") != "SUCCEEDED":
        sys.exit(f"{name} has no finished rig")
    return rig["id"]


def archive_path(key):
    return MOTIONS / f"{key}.motion.npz"


def add(m, key, seconds, prompt, mode="prime", role=""):
    """Queue a sentence under a key. A changed prompt is a new motion; the old
    record keeps its place in the key's history."""
    if (seconds * 2) != int(seconds * 2) or not 2 <= seconds <= 10:
        sys.exit(f"{key}: the duration is 2 to 10 seconds in 0.5 s steps")
    rec = m["moves"].get(key)
    if rec and rec.get("prompt") == prompt and rec.get("seconds") == seconds and rec.get("mode") == mode:
        return False
    if rec:
        rec.setdefault("history", [])
        old = {k: v for k, v in rec.items() if k != "history"}
        m["moves"][key] = {"history": rec["history"] + [old]}
    m["moves"][key] = touch(dict(m["moves"].get(key, {}), prompt=prompt, seconds=seconds, mode=mode, role=role,
                                 queued=now(), state="queued"))
    return True


def step(meshy, client, m, key, rig_id, floor):
    """Advance one move by one stage: create the motion, wait for it, apply
    it to the donor, wait for that, archive. Returns True when it moved."""
    rec = m["moves"][key]
    state = rec.get("state")
    if state == "queued":
        bal = client.balance()
        price = (10 if rec["mode"] == "prime" else 3) + 3
        if bal is not None and bal - price < floor:
            print(f"  {key}: the balance {bal} would fall under the floor {floor}; left queued")
            return False
        tid = client.create("motion", {"prompt": rec["prompt"], "duration": rec["seconds"], "mode": rec["mode"]})
        rec.update(motion_task=tid, state="motion", motion_created=now(), balance_before=bal)
        print(f"  {key}: motion {tid}")
        return True
    if state == "motion":
        d = client.task("motion", rec["motion_task"])
        st = d.get("status")
        if st not in TERMINAL:
            return False
        rec["motion_status"] = st
        urls = meshy.urls_in({"result": d.get("result")})
        rec["motion_urls"] = urls
        if st != "SUCCEEDED":
            rec["state"] = "failed"
            rec["error"] = (d.get("task_error") or {}).get("message", "") or st
            print(f"  {key}: motion {st} {rec['error']}")
            return True
        # The prime task's own FBX (`motion_urls`) is an SMPL-H skeleton in a
        # T-pose (read on the 25th), not Meshy's rig: the apply below is what
        # puts the motion on a Meshy skeleton our retarget reads.
        tid = client.create("clip", {"rig_task_id": rig_id, "motion_task_id": rec["motion_task"]})
        rec.update(clip_task=tid, state="clip", clip_created=now(), donor=DONOR)
        print(f"  {key}: motion done, applying to {DONOR}: {tid}")
        return True
    if state == "clip":
        d = client.task("clip", rec["clip_task"])
        st = d.get("status")
        if st not in TERMINAL:
            return False
        rec["clip_status"] = st
        if st != "SUCCEEDED":
            rec["state"] = "failed"
            rec["error"] = (d.get("task_error") or {}).get("message", "") or st
            print(f"  {key}: apply {st} {rec['error']}")
            return True
        from motion_palette import fetch_clip_glb, blow_frame
        from retarget import load_source
        glb = WORK / "downloads" / f"{key}.glb"
        fetch_clip_glb(client, rec["clip_task"], glb)
        src = load_source(glb)
        src.source = (f"meshy text-to-motion '{rec['prompt'][:120]}' ({rec['mode']}, {rec['seconds']} s, task "
                      f"{rec['motion_task']}) applied to {DONOR} (task {rec['clip_task']})")
        out = archive_path(key)
        src.save(out)
        F = len(src.anim["T"])
        fps = float(src.anim["fps"])
        f, frac = blow_frame(src)
        rec.update(state="archived", archived=str(out.relative_to(REPO)), frames=F, fps=fps,
                   seconds_made=round(F / fps, 3), blow_frame=f,
                   blow_fraction=None if frac is None else round(frac, 3), archived_at=now())
        glb.unlink(missing_ok=True)
        print(f"  {key}: archived {F} frames {F / fps:.2f} s -> {out.relative_to(REPO)}")
        return True
    return False


def cmd_say(a):
    m = load()
    if add(m, a.key, a.seconds, a.prompt, a.mode, a.role):
        save(m)
        print(f"{a.key}: queued")
    else:
        print(f"{a.key}: already queued with this prompt ({m['moves'][a.key].get('state')})")


def cmd_launch(a):
    m = load()
    only = set(a.only.split(",")) if a.only else None
    added = 0
    with open(a.tsv, newline="") as f:
        for row in csv.reader(f, delimiter="\t"):
            if not row or row[0].startswith("#"):
                continue
            key, seconds, prompt = row[0].strip(), float(row[1]), row[2].strip()
            role = row[3].strip() if len(row) > 3 else ""
            fam = key.split(":")[0]
            if only and fam not in only and key not in only:
                continue
            added += add(m, key.replace(":", "_"), seconds, prompt, a.mode, role)
    save(m)
    print(f"{added} sentence(s) queued")


def cmd_run(a):
    meshy, client = api()
    m = load()
    rig_id = donor_rig(meshy, DONOR)
    keys = [k for k, r in m["moves"].items() if r.get("state") not in ("archived", "failed")]
    if a.keys:
        keys = [k for k in keys if k in set(a.keys)]
    print(f"{len(keys)} move(s) to advance; balance {client.balance()}")
    t0 = time.time()
    in_flight_cap = a.parallel
    while keys:
        moved = False
        flying = sum(1 for k in keys if m["moves"][k].get("state") in ("motion", "clip"))
        for k in list(keys):
            rec = m["moves"][k]
            if rec.get("state") == "queued" and flying >= in_flight_cap:
                continue
            try:
                did = step(meshy, client, m, k, rig_id, a.floor)
            except SystemExit as e:
                print(f"  {k}: {e}")
                rec["state"] = "failed"
                rec["error"] = str(e)[:300]
                did = True
            if did:
                touch(rec)
                moved = True
                save(m)
                if rec.get("state") == "motion" and rec.get("motion_created") and "motion_task" in rec:
                    flying += 1 if rec.get("clip_task") is None else 0
            if rec.get("state") in ("archived", "failed"):
                keys.remove(k)
                flying = sum(1 for kk in keys if m["moves"][kk].get("state") in ("motion", "clip"))
        if keys and not moved:
            if time.time() - t0 > a.timeout:
                sys.exit("timed out; re-run `run` later")
            time.sleep(10)
    print(f"done; balance {client.balance()}")


def cmd_list(a):
    m = load()
    for k, r in m["moves"].items():
        print(f"{k:40s} {r.get('state', '?'):9s} {r.get('seconds', '?'):>4} s  {r.get('seconds_made', '')!s:>6}  "
              f"blow {r.get('blow_fraction', '')!s:6s} {r.get('prompt', '')[:70]}")


# ---------------------------------------------------------------------------
# Contacts: where a clip's strikes land
# ---------------------------------------------------------------------------

def joint_worlds(motion):
    """World positions of every joint at every frame (F, J, 3), from a Motion
    (row convention: the translation is the matrix's last row)."""
    F = len(motion.anim["T"])
    return np.stack([motion.joint_world_at(f)[:, 3, :3] for f in range(F)])


def find_joint(motion, *names):
    low = [j.split("/")[-1].lower() for j in motion.joints]
    for n in names:
        if n.lower() in low:
            return low.index(n.lower())
    return None


def strike_signal(motion, hands="both"):
    """How hard the body is striking at each frame: the speed of the hand(s)
    RELATIVE TO THE HIPS (so a step or a leap does not read as a blow),
    smoothed over three frames. A slash or a thrust is fastest as it passes
    through the target; a cast's hands as they release."""
    P = joint_worlds(motion)
    fps = float(motion.anim["fps"])
    hips = find_joint(motion, "Hips", "hips", "pelvis")
    picks = []
    if hands in ("both", "right"):
        picks.append(find_joint(motion, "RightHand", "RightForeArm"))
    if hands in ("both", "left"):
        picks.append(find_joint(motion, "LeftHand", "LeftForeArm"))
    picks = [p for p in picks if p is not None]
    rel = P[:, picks, :] - (P[:, [hips], :] if hips is not None else 0)
    v = np.linalg.norm(np.diff(rel, axis=0), axis=2) * fps          # (F-1, hands) m/s
    v = v.max(axis=1)
    v = np.convolve(v, np.ones(3) / 3, mode="same")
    return np.concatenate([[0.0], v])


def contacts(motion, expect=None, hands="both", min_gap=0.18, lo=0.06, hi=0.97):
    """The frames a clip strikes on: the peaks of `strike_signal` at least
    `min_gap` seconds apart and at least 45% of the strongest, inside
    [lo, hi] of the clip. With `expect`, the `expect` strongest peaks in time
    order (fewer if the clip has fewer). Returns (frames, signal)."""
    sig = strike_signal(motion, hands)
    fps = float(motion.anim["fps"])
    F = len(sig)
    gap = max(1, int(round(min_gap * fps)))
    a, b = int(lo * (F - 1)), int(hi * (F - 1))
    peaks = [i for i in range(max(1, a), min(F - 1, b)) if sig[i] >= sig[i - 1] and sig[i] >= sig[i + 1]]
    peaks.sort(key=lambda i: -sig[i])
    chosen = []
    top = sig[peaks[0]] if peaks else 0
    for i in peaks:
        if sig[i] < 0.45 * top and (expect is None or len(chosen) >= expect):
            break
        if all(abs(i - c) >= gap for c in chosen):
            chosen.append(i)
        if expect is not None and len(chosen) >= expect:
            break
    return sorted(chosen), sig


def cmd_contacts(a):
    from retarget import Motion
    mo = Motion.load(a.npz)
    frames, sig = contacts(mo, a.expect, a.hands)
    F = len(sig)
    print(f"{Path(a.npz).name}: {F} frames at {mo.anim['fps']} fps; contacts {frames} = "
          f"{[round(f / (F - 1), 3) for f in frames]}; peak speed {sig.max():.2f} m/s")


# ---------------------------------------------------------------------------
# Composing: a multi-strike move chained from single strikes
# ---------------------------------------------------------------------------
#
# Meshy's text-to-motion does worst at exactly what a three-hit skill is (a
# multi-beat sequence), and the preset library has few combos. So a style
# move is CHAINED from single strikes: each segment is a window of an archived
# motion (from its wind-up to part-way through its recovery), the next one
# starts from the pose the last one reached (blended over `blend` frames), the
# chain ends by easing back to the first frame's stance, and the contacts are
# the segments' blow frames on the new timeline - known, not guessed.

def segment_anim(src, start, end, speed=1.0, mirror=False, onto=None):
    """Frames [start, end] of an archived motion as an anim dict, optionally
    retargeted onto another rig first (`onto`, a Motion: a preset archived on
    the Colossus's rig carries hips 2.4 m up, and its local turns are that
    rig's), mirrored and retimed (speed > 1 is faster)."""
    from retarget import Motion, retarget
    from motion_palette import mirror_motion, resample
    mo = Motion.load(src) if not isinstance(src, Motion) else src
    if onto is not None and not (len(onto.joints) == len(mo.joints)
                                 and np.allclose(onto.rest_local, mo.rest_local, atol=1e-4)):
        anim, _, _ = retarget(mo, onto)
        mo = Motion(onto.joints, onto.parents, onto.rest_local, anim, mo.source)
    if mirror:
        mo, _ = mirror_motion(mo)
    a = mo.anim
    F = len(a["T"])
    end = min(end, F - 1)
    anim = {k: np.asarray(a[k][start:end + 1], float) for k in ("T", "R", "S")}
    anim["fps"] = a["fps"]
    if abs(speed - 1.0) > 1e-3:
        n = len(anim["T"])
        out = max(2, int(round((n - 1) / speed)) + 1)
        anim = resample(anim, np.linspace(0, n - 1, out))
    return mo, anim


def chain(segments, blend=6, recover=12, lock_root=True):
    """Chains segments: [{"src": path, "from": f0, "to": f1, "blow": fb,
    "speed": 1.0, "mirror": False}, ...] -> (Motion, contacts as frame
    indices). Each segment's first `blend` frames are slerped from the pose
    the chain has reached, so the cut is never seen; the hips' horizontal
    travel is taken off each segment (the game moves the unit), so a step in
    one strike does not carry the next one away; the last pose eases back to
    the first over `recover` frames."""
    from retarget import Motion
    from motion_palette import slerp
    T = R = S = None
    fps = None
    base = None
    origin = None
    contacts = []
    for i, seg in enumerate(segments):
        path = REPO / seg["src"] if not str(seg["src"]).startswith("/") else Path(seg["src"])
        if base is None:
            # every segment is carried onto the first one's rig before it is cut
            from retarget import Motion
            base = Motion.load(path)
        mo, anim = segment_anim(path, seg["from"], seg["to"], seg.get("speed", 1.0), seg.get("mirror", False),
                                onto=base)
        if fps is None:
            fps = anim["fps"]
        n = len(anim["T"])
        hips = 0                                  # Meshy's rigs put the Hips first; checked below
        if lock_root:
            # every segment's hips held over the FIRST segment's first frame:
            # a strike cut from late in a preset starts a metre or more from
            # where the preset began, and a per-segment lock would slide the
            # whole body that far over the blend
            names = [j.split("/")[-1].lower() for j in mo.joints]
            hips = names.index("hips") if "hips" in names else 0
            if origin is None:
                origin = (float(anim["T"][0, hips, 0]), float(anim["T"][0, hips, 2]))
            anim["T"][:, hips, 0] = origin[0]
            anim["T"][:, hips, 2] = origin[1]
        blow = seg.get("blow")
        if blow is not None:
            local = (blow - seg["from"]) / max(seg.get("speed", 1.0), 1e-3)
        if T is None:
            T, R, S = anim["T"], anim["R"], anim["S"]
            if blow is not None:
                contacts.append(int(round(local)))
            continue
        k = min(blend, n - 1, len(T) - 1)
        # the new segment's opening frames, blended from where the chain is
        w = (np.arange(1, k + 1) / (k + 1))
        last_T, last_R, last_S = T[-1], R[-1], S[-1]
        head_T = np.stack([last_T * (1 - x) + anim["T"][j] * x for j, x in enumerate(w)])
        head_S = np.stack([last_S * (1 - x) + anim["S"][j] * x for j, x in enumerate(w)])
        head_R = np.stack([slerp(last_R, anim["R"][j], x) for j, x in enumerate(w)])
        offset = len(T)
        T = np.concatenate([T, head_T, anim["T"][k:]])
        R = np.concatenate([R, head_R, anim["R"][k:]])
        S = np.concatenate([S, head_S, anim["S"][k:]])
        if blow is not None:
            contacts.append(int(round(offset + local)))
    if recover:
        w = 0.5 - 0.5 * np.cos(np.pi * (np.arange(1, recover + 1) / recover))
        first_T, first_R, first_S, last_T, last_R, last_S = T[0], R[0], S[0], T[-1], R[-1], S[-1]
        T = np.concatenate([T, np.stack([last_T * (1 - x) + first_T * x for x in w])])
        S = np.concatenate([S, np.stack([last_S * (1 - x) + first_S * x for x in w])])
        R = np.concatenate([R, np.stack([slerp(last_R, first_R, x) for x in w])])
    anim = {"T": T.astype(np.float32), "R": R.astype(np.float32), "S": S.astype(np.float32), "fps": fps}
    names = ", ".join(f"{Path(str(s['src'])).stem}[{s['from']}:{s['to']}]{'~m' if s.get('mirror') else ''}" for s in segments)
    return Motion(base.joints, base.parents, base.rest_local, anim, f"composed: {names}"), contacts


def recipes():
    path = REPO / "tools" / "skills" / "style_moves.json"
    return json.loads(path.read_text()) if path.exists() else {}


def cmd_compose(a):
    book = recipes()
    names = a.names or sorted(book)
    for name in names:
        rec = book.get(name) or sys.exit(f"no recipe '{name}' in tools/skills/style_moves.json")
        motion, hits = chain(rec["segments"], rec.get("blend", 6), rec.get("recover", 12))
        out = archive_path(name)
        motion.save(out)
        F = len(motion.anim["T"])
        fps = float(motion.anim["fps"])
        facts = dict(frames=F, seconds=round(F / fps, 3), contacts=hits,
                     contact_fractions=[round(h / (F - 1), 3) for h in hits])
        side = out.with_suffix("").with_suffix(".json")
        side.write_text(json.dumps(dict(recipe=name, **facts), indent=1) + "\n")
        print(f"{name}: {F} frames {F / fps:.2f} s, contacts {hits} {facts['contact_fractions']} -> {out.relative_to(REPO)}")


# ---------------------------------------------------------------------------
# Boards: a motion on the donor, frame by frame, with its strike signal
# ---------------------------------------------------------------------------

def motion_path(name):
    p = Path(name)
    if p.suffix == ".npz" and p.exists():
        return p
    for cand in (MOTIONS / f"{name}.motion.npz", MOTIONS / f"preset_{name}.motion.npz"):
        if cand.exists():
            return cand
    sys.exit(f"no archived motion '{name}'")


def render_rows(names, frames_for, size=210, views="front,side", donor=DONOR, expects=None, wrap=None):
    """One row per motion: the donor wearing it at the frames `frames_for`
    picks, each cell labelled, and under the row the strike signal with the
    detected contacts marked. -> PIL image."""
    import character
    from PIL import Image, ImageDraw
    from retarget import Motion, retarget
    from motion_palette import draw_cell
    rows = []
    for name in names:
        path = motion_path(name)
        src = Motion.load(path)
        tgt = character.read_glb(str(REPO / "Art" / "Models" / f"{donor}.glb"))
        anim, _, _ = retarget(src, Motion.from_char(tgt))
        tgt.anim = {"T": anim["T"], "R": anim["R"], "S": anim["S"], "fps": anim["fps"]}
        character.canonicalise(tgt, height=None)
        character.ground_animation(tgt)
        lo, hi = character.bounds(tgt.points)
        height = float(hi[1] - lo[1])
        F = len(tgt.anim["T"])
        side = path.with_suffix("").with_suffix(".json")
        known = json.loads(side.read_text()).get("contacts") if side.exists() else None
        expect = (expects or {}).get(name)
        found, sig = contacts(src, expect)
        marks = known if known is not None else found
        cells = []
        for f in frames_for(F, marks):
            pts = tgt.skinned_points(tgt.joint_world_at(f))
            tag = " HIT" if f in marks else ""
            cells.append(draw_cell(tgt, pts, views.split(","), size, height, f"f{f}/{F - 1}{tag}"))
        # the strike signal under the row
        W = sum(c.width for c in cells)
        plot = Image.new("RGB", (W, 60), (30, 30, 36))
        d = ImageDraw.Draw(plot)
        top = max(1e-6, float(sig.max()))
        xs = [int(i / max(1, F - 1) * (W - 1)) for i in range(F)]
        ys = [int(56 - 52 * float(v) / top) for v in sig]
        d.line(list(zip(xs, ys)), fill=(120, 200, 255), width=2)
        for m in marks:
            x = int(m / max(1, F - 1) * (W - 1))
            d.line([(x, 0), (x, 59)], fill=(255, 120, 90), width=2)
        for t in range(0, F, 10):
            x = int(t / max(1, F - 1) * (W - 1))
            d.text((x + 2, 2), str(t), fill=(150, 150, 150))
        title = f"{path.stem}  {F} frames {F / float(src.anim['fps']):.2f} s  contacts {marks}"
        rows.append((title, cells, plot))
    # wrapped `wrap` cells to a line, so a board stays legible when viewed
    per = max(1, wrap or max(len(c) for _, c, _ in rows))
    cw, ch = rows[0][1][0].width, rows[0][1][0].height
    w = per * cw + 20
    h = sum(((len(cells) + per - 1) // per) * (ch + 4) + 60 + 30 for _, cells, _ in rows) + 10
    sheet = Image.new("RGB", (w, h), (22, 22, 26))
    d = ImageDraw.Draw(sheet)
    y = 6
    for title, cells, plot in rows:
        d.text((10, y), title, fill=(160, 230, 160))
        y += 18
        for i, c in enumerate(cells):
            sheet.paste(c, (10 + (i % per) * cw, y + (i // per) * (ch + 4)))
        y += ((len(cells) + per - 1) // per) * (ch + 4)
        sheet.paste(plot.resize((per * cw, 60)), (10, y))
        y += 60 + 12
    return sheet


def cmd_board(a):
    def frames_for(F, marks):
        if a.every:
            base = set(range(0, F, a.every)) | {F - 1}
        else:
            base = {int(round(x * (F - 1))) for x in np.linspace(0, 1, a.frames)}
        return sorted(base | set(marks))
    expects = {}
    for item in a.expect or []:
        k, _, v = item.partition("=")
        expects[k] = int(v)
    sheet = render_rows(a.names, frames_for, a.size, a.views, expects=expects, wrap=a.wrap)
    sheet.save(a.out, quality=86)
    print(f"board -> {a.out}")


# ---------------------------------------------------------------------------
# Shipping onto the families, and the timing table the game reads
# ---------------------------------------------------------------------------

SHAPE_CLIP = {"x2": "skill_x2", "x3": "skill_x3", "x4": "skill_x4", "x5": "skill_x5",
              "area": "skill_area", "rite": "cast_release"}
SKILL_CLIPS = ("attack_basic", "attack_heavy", "ultimate") + tuple(SHAPE_CLIP.values())
TIMINGS = REPO / "Pantheon" / "Resources" / "Models" / "clip_timings.json"


def second_skill_shapes():
    """family -> the shapes its five forms' SECOND skills take (balance.py's
    mirrors of every blueprint): x1 is the family's own attack_heavy and is
    not listed; x2..x5, area and rite each want a clip."""
    import balance as B
    out = {}

    def shape(h, aoe):
        return "rite" if h == 0 else ("area" if aoe else f"x{min(h, 5)}")
    for key, name, stars, kit, hp, atk, df, spd in B.FAMILY_ROWS:
        forms = [B.kit_skills(kit, stars, hp, atk, el) for el in B.ELEMENTS]
        out[key] = sorted({shape(f[1][2], f[1][6]) for f in forms if len(f) > 1} - {"x1"})
    for key, bp in B.HANDWRITTEN:
        forms = [B.handwritten_skills(key, el, bp) for el in B.ELEMENTS]
        out[key] = sorted({shape(f[1][2], f[1][6]) for f in forms if len(f) > 1} - {"x1"})
    # the Labyrinth's two rigged bosses (UnitDatabase.swift, `enemy(...)`): their
    # special hits the whole line (`specialTarget: .allEnemies`)
    out.update(BOSS_SHAPES)
    return out


BOSS_SHAPES = {"boss_colossus": ["area"], "boss_unwrapped_king": ["area"]}


def rite_ultimates():
    """The families whose third skill deals no damage in any of their five
    forms: their ultimate is a rite, which has no blow to aim."""
    import balance as B
    out = set()
    for key, name, stars, kit, hp, atk, df, spd in B.FAMILY_ROWS:
        forms = [B.kit_skills(kit, stars, hp, atk, el) for el in B.ELEMENTS]
        thirds = [f[2] for f in forms if len(f) > 2]
        if thirds and all(t[2] == 0 for t in thirds):
            out.add(key)
    for key, bp in B.HANDWRITTEN:
        forms = [B.handwritten_skills(key, el, bp) for el in B.ELEMENTS]
        thirds = [f[2] for f in forms if len(f) > 2]
        if thirds and all(t[2] == 0 for t in thirds):
            out.add(key)
    return out

# The hand a family ACTS with where its mesh holds things otherwise than
# motion_palette.WEAPON_HAND reads them, looked at on front renders
# (2026-09-25, the sentence writers' notes): Heimdall's sword is in his LEFT
# hand (the horn in his right was measured as the weapon), and Idunn's basket
# is in her right, so her free left hand throws. Dark elf and Bellona act
# with the RIGHT hand though the table reads them left: his dagger hangs at
# his left hip, skinned to the thigh with that arm welded to it, and her whip
# is in her right hand while the sword in her left is half-skinned and drags.
HAND_OVERRIDE = {"heimdall": "L", "idunn": "L", "dark_elf": "R", "bellona": "R"}


def source_side(kind):
    """The hand every source of a kind holds its weapon in: a sentence is
    written right-handed and a composed move is cut from right-handed
    presets, except an archer's, written - like the palette's own archer
    presets (PRESET_SIDE 224, 222, 226) - with the bow in the LEFT hand."""
    return "L" if kind == "archer" else "R"


# ---------------------------------------------------------------------------
# Archers aim at the target (2026-09-25)
# ---------------------------------------------------------------------------
#
# Every archery motion - Meshy's presets and our sentences alike - stands
# side-on with the bow arm out to the figure's LEFT, 50 to 90 degrees off the
# way it faces (preset 224 at its loose: +82; Artemis's own shot: +81). The
# battle turns a unit to face its target, so every archer loosed into the side
# of the arena while the arrow flew straight. An archer's clip is turned about
# its hips so the bow arm points at the target at the loose: the figure turns
# side-on as the shot comes, as an archer does.

AIMED = MOTIONS / "aimed"
HEAVY_ARCHERY = (224, dict(window=(50, 140), blow=117))     # the archers' own heavy shot, as the palette cuts it


def bow_yaw(motion, frames):
    """Where the bow arm points, in degrees from +Z toward +X, at `frames`:
    the left arm's shoulder to its hand, the source holding the bow left."""
    names = [j.split("/")[-1].lower() for j in motion.joints]
    arm, hand = names.index("leftarm"), names.index("lefthand")
    heading = np.zeros(3)
    for f in frames:
        W = motion.joint_world_at(int(f))
        d = W[hand][3, :3] - W[arm][3, :3]
        d[1] = 0.0
        heading += d / max(np.linalg.norm(d), 1e-6)
    return float(np.degrees(np.arctan2(heading[0], heading[2])))


def turned(motion, degrees):
    """The whole motion turned `degrees` about the vertical through its first
    frame's hips (+ turns +Z toward +X): the root's transform only, so every
    joint below it goes with it."""
    from character import decompose, quat_to_rot, trs
    from retarget import Motion
    root = int(np.where(np.asarray(motion.parents) < 0)[0][0])
    a = motion.anim
    T, R, S = (np.array(a[k], dtype=np.float64) for k in ("T", "R", "S"))
    th = np.radians(degrees)
    Y = np.eye(4)
    Y[:3, :3] = quat_to_rot([0.0, np.sin(th / 2), 0.0, np.cos(th / 2)])
    pivot = T[0, root].copy()
    pivot[1] = 0.0
    there, back = np.eye(4), np.eye(4)
    there[3, :3], back[3, :3] = -pivot, pivot
    M = there @ Y @ back
    for f in range(len(T)):
        t, q, sc = decompose(trs(T[f, root], R[f, root], S[f, root]) @ M)
        if f and np.dot(q, R[f - 1, root]) < 0:
            q = -q
        T[f, root], R[f, root], S[f, root] = t, q, sc
    anim = dict(a, T=T.astype(np.float32), R=R.astype(np.float32), S=S.astype(np.float32))
    return Motion(motion.joints, motion.parents, motion.rest_local, anim, f"{motion.source} turned {degrees:+.0f}")


def turned_over(motion, degrees, weights):
    """The motion turned about the vertical through its first frame's hips by
    `degrees` times each frame's weight (0..1): a turn that comes and goes."""
    from character import decompose, quat_to_rot, trs
    from retarget import Motion
    root = int(np.where(np.asarray(motion.parents) < 0)[0][0])
    a = motion.anim
    T, R, S = (np.array(a[k], dtype=np.float64) for k in ("T", "R", "S"))
    pivot = T[0, root].copy()
    pivot[1] = 0.0
    there, back = np.eye(4), np.eye(4)
    there[3, :3], back[3, :3] = -pivot, pivot
    for f in range(len(T)):
        th = np.radians(degrees * float(weights[f]))
        Y = np.eye(4)
        Y[:3, :3] = quat_to_rot([0.0, np.sin(th / 2), 0.0, np.cos(th / 2)])
        t, q, sc = decompose(trs(T[f, root], R[f, root], S[f, root]) @ (there @ Y @ back))
        if f and np.dot(q, R[f - 1, root]) < 0:
            q = -q
        T[f, root], R[f, root], S[f, root] = t, q, sc
    anim = dict(a, T=T.astype(np.float32), R=R.astype(np.float32), S=S.astype(np.float32))
    return Motion(motion.joints, motion.parents, motion.rest_local, anim, f"{motion.source} aimed {degrees:+.0f}")


def blow_heading(motion, frame):
    """Where a blow lands at `frame`, in degrees from +Z toward +X: the hand
    furthest from the hips, or between both hands when they strike together."""
    names = [j.split("/")[-1].lower() for j in motion.joints]
    W = motion.joint_world_at(int(frame))
    hips = W[names.index("hips")][3, :3]
    r = W[names.index("righthand")][3, :3] - hips
    l = W[names.index("lefthand")][3, :3] - hips
    r[1] = l[1] = 0.0
    nr, nl = np.linalg.norm(r), np.linalg.norm(l)
    if min(nr, nl) > 0.3 and np.dot(r, l) < 0:
        return None                                 # both arms flung apart: a spread, not a blow with a heading
    if min(nr, nl) > 0.75 * max(nr, nl) and np.dot(r, l) > 0.5 * nr * nl:
        d = r + l                                   # both hands out the same way: one blow
    else:
        d = r if nr >= nl else l
    return float(np.degrees(np.arctan2(d[0], d[2])))


AIM_TOLERANCE = 20.0          # degrees: a blow this close to the target is left as made


def aim_blows(motion, contacts):
    """A signature motion turned so its blows land on the target: the mean
    heading of its blows at the judged contacts, if more than AIM_TOLERANCE
    off +Z, is taken off by a turn that grows from a quarter of the way to
    the first contact, holds through the last and eases away by the end, so
    the figure starts and finishes square to the target. -> (Motion, degrees)."""
    F = len(motion.anim["T"])
    if not contacts:
        return motion, 0.0
    heads = [h for h in (blow_heading(motion, c) for c in contacts) if h is not None]
    if not heads:
        return motion, 0.0
    heads = np.radians(heads)
    mean = float(np.degrees(np.arctan2(np.sin(heads).mean(), np.cos(heads).mean())))
    if abs(mean) <= AIM_TOLERANCE:
        return motion, 0.0
    first, last = min(contacts), max(contacts)
    f = np.arange(F, dtype=float)
    a0, a1 = 0.25 * first, float(first)
    b0 = last + 0.35 * (F - 1 - last)
    rise = np.clip((f - a0) / max(a1 - a0, 1.0), 0, 1)
    fall = 1 - np.clip((f - b0) / max(F - 1 - b0, 1.0), 0, 1)
    w = np.minimum(rise * rise * (3 - 2 * rise), fall * fall * (3 - 2 * fall))
    return turned_over(motion, -mean, w), -mean


def loose_frames(key, motion):
    """The frames an archer's motion looses on: the judge's contacts for a
    sentence, the recipe's for a composed move, else the frame its bow arm
    reaches furthest in the middle of the clip."""
    rec = load()["moves"].get(key, {})
    if rec.get("contact_frames"):
        return rec["contact_frames"]
    side = MOTIONS / f"{key}.json"
    if side.exists() and json.loads(side.read_text()).get("contacts"):
        return json.loads(side.read_text())["contacts"]
    names = [j.split("/")[-1].lower() for j in motion.joints]
    arm, hand = names.index("leftarm"), names.index("lefthand")
    F = len(motion.anim["T"])
    reach = [np.linalg.norm((motion.joint_world_at(f)[hand] - motion.joint_world_at(f)[arm])[3, [0, 2]])
             for f in range(F)]
    lo, hi = int(0.3 * F), int(0.85 * F)
    return [lo + int(np.argmax(reach[lo:hi]))]


def aimed(src, key=None):
    """An archived archer motion turned to aim (above), written beside the
    archive in Art/Motions/aimed/ and rebuilt when the archive changes;
    returns its path."""
    from retarget import Motion
    src = Path(src)
    out = AIMED / src.name
    note = AIMED / src.name.replace(".motion.npz", ".aim.json")
    m = Motion.load(src)
    frames = [int(f) for f in loose_frames(key or src.name.replace(".motion.npz", ""), m)]
    # rebuilt when the archive changes or the judge moves its loose
    if out.exists() and note.exists() and out.stat().st_mtime >= src.stat().st_mtime \
            and json.loads(note.read_text()).get("frames") == frames:
        return out
    yaw = bow_yaw(m, frames)
    AIMED.mkdir(parents=True, exist_ok=True)
    turned(m, -yaw).save(out)
    note.write_text(json.dumps(dict(frames=frames, yaw=round(yaw, 1)), indent=1) + "\n")
    print(f"  aimed {src.name}: the bow arm pointed {yaw:+.0f} deg at the loose (f{frames}); turned {-yaw:+.0f}")
    return out


def aimed_blow(src, key):
    """A signature or composed motion whose blows land beside the target,
    turned onto it (`aim_blows`, at the judged or composed contacts) and
    written to Art/Motions/aimed/; the archive itself when it needs no
    turn or has no contacts to aim by."""
    from retarget import Motion
    src = Path(src)
    rec = load()["moves"].get(key, {})
    frames = rec.get("contact_frames")
    side = MOTIONS / f"{key}.json"
    if not frames and side.exists():
        frames = json.loads(side.read_text()).get("contacts")
    if not frames:
        return src
    frames = [int(f) for f in frames]
    out = AIMED / src.name
    note = AIMED / src.name.replace(".motion.npz", ".aim.json")
    if note.exists() and json.loads(note.read_text()).get("frames") == frames \
            and note.stat().st_mtime >= src.stat().st_mtime:
        return out if json.loads(note.read_text()).get("turned") else src
    m, degrees = aim_blows(Motion.load(src), frames)
    AIMED.mkdir(parents=True, exist_ok=True)
    if degrees:
        m.save(out)
        print(f"  aimed {src.name}: its blows landed {-degrees:+.0f} deg off the target; turned {degrees:+.0f}")
    note.write_text(json.dumps(dict(frames=frames, turned=round(degrees, 1)), indent=1) + "\n")
    return out if degrees else src


def aimed_heavy():
    """The archers' heavy shot (preset 224, cut and its loose warped as the
    palette cuts it), turned to aim; its contact in a side record."""
    from retarget import Motion
    from motion_palette import prepare
    pid, cut = HEAVY_ARCHERY
    src = MOTIONS / f"preset_{pid}.motion.npz"
    out = AIMED / f"preset_{pid}_heavy.motion.npz"
    side = AIMED / f"preset_{pid}_heavy.json"
    if out.exists() and side.exists() and out.stat().st_mtime >= src.stat().st_mtime:
        return out
    m, facts = prepare(Motion.load(src), "attack_heavy", **cut)
    F = len(m.anim["T"])
    blow = facts.get("blow", 0.55)
    yaw = bow_yaw(m, [int(round(blow * (F - 1)))])
    AIMED.mkdir(parents=True, exist_ok=True)
    turned(m, -yaw).save(out)
    side.write_text(json.dumps(dict(recipe=f"preset {pid} {cut}, aimed", frames=F, seconds=round(F / m.anim['fps'], 3),
                                    contact_fractions=[blow]), indent=1) + "\n")
    print(f"  aimed preset {pid} as the heavy shot: the bow arm pointed {yaw:+.0f} deg; turned {-yaw:+.0f}")
    return out


RITE_ULTIMATES = set()


def skill_assign(family, plan_row, shapes):
    """The skill clips one family (or its awakened form) wears: its signature
    basic and ultimate where they are archived (the five gods keep their
    bespoke ones), and its kind's composed move for every second-skill shape
    its forms use. A source is mirrored (`~m`) when the family holds its
    weapon in the other hand from the source's (`source_side`); a family
    with nothing in either hand, or a weapon in each, is never mirrored."""
    from motion_palette import BESPOKE, weapon_hand
    base = family.replace("_awakened", "")
    kind = plan_row.get("kind")
    hand = HAND_OVERRIDE.get(base, weapon_hand(family))
    side = "~m" if hand is not None and hand != source_side(kind) else ""
    archer = kind == "archer"

    moves = load()["moves"]

    def usable(key):
        """A bought move plays once it is archived and no judge has sent it
        back; a move sent back plays nothing until its new take lands (the
        family keeps the clip the palette dealt it). A composed move has no
        record and always plays."""
        rec = moves.get(key)
        return rec is None or (rec.get("state") == "archived" and rec.get("judged") != "reroll")

    def source(src, key, blow=True):
        if archer:
            src = aimed(src, key)
        elif blow:
            src = aimed_blow(src, key)
        # a take whose hands came out the wrong way round (judged: `flip`)
        flip = moves.get(key, {}).get("flip")
        sided = ("" if side else "~m") if flip else side
        return str(Path(src).relative_to(REPO)) + sided
    assign = {}
    if base not in BESPOKE:
        for clip in ("attack_basic", "ultimate"):
            src = archive_path(f"{base}_{clip}")
            if src.exists() and usable(f"{base}_{clip}"):
                assign[clip] = source(src, f"{base}_{clip}", blow=not (clip == "ultimate" and base in RITE_ULTIMATES))
    for shape in shapes.get(base, []):
        src = archive_path(f"style_{kind}_{shape}")
        if src.exists() and usable(f"style_{kind}_{shape}"):
            assign[SHAPE_CLIP[shape]] = source(src, f"style_{kind}_{shape}", blow=shape.startswith("x"))
    if archer:
        # the heavy shot the palette dealt every archer, re-shipped aimed
        assign["attack_heavy"] = str(aimed_heavy().relative_to(REPO)) + side
    return assign


def cmd_ship(a):
    from concurrent.futures import ThreadPoolExecutor
    import subprocess
    from motion_palette import make_plan
    plan, _ = make_plan()
    shapes = second_skill_shapes()
    RITE_ULTIMATES.update(rite_ultimates())
    names = a.families or sorted(plan)
    logs = WORK / "logs"
    logs.mkdir(parents=True, exist_ok=True)

    # every source aimed and written HERE, one family after another: a family
    # and its awakened form share their signature files, and two threads
    # writing one aimed file at once would tear it
    assigns = {name: skill_assign(name, plan[name], shapes) for name in names if name in plan}

    def run(name):
        row = plan.get(name)
        if row is None:
            return name, "not in the palette's plan", 1
        assign = assigns[name]
        if not assign:
            return name, "nothing to ship", 0
        argv = [sys.executable, str(REPO / "tools" / "motion_palette.py"), "ship", row["asset"], name] + \
               [f"{k}={v}" for k, v in assign.items()] + ["--bundle", str(Path(a.bundle).resolve())] + \
               (["--real"] if a.real else []) + (["--height", str(row["height"])] if row.get("height") else [])
        if a.dry_run:
            return name, " ".join(argv[3:]), 0
        with open(logs / f"{name}.log", "w") as log:
            r = subprocess.run(argv, stdout=log, stderr=subprocess.STDOUT, cwd=str(REPO))
        text = (logs / f"{name}.log").read_text()
        probs = [l.strip() for l in text.splitlines() if "PROBLEM" in l]
        return name, f"{len(assign)} clip(s) {'; '.join(probs[:2])}", r.returncode

    failed = []
    with ThreadPoolExecutor(max_workers=max(1, a.jobs)) as pool:
        for name, note, code in pool.map(run, names):
            if code:
                failed.append(name)
            print(f"  {name:24s} {'ok' if not code else 'FAILED'}  {note}", flush=True)
    print(f"{len(names) - len(failed)} done, {len(failed)} failed{': ' + ', '.join(failed) if failed else ''} (logs in {logs})")


def source_contacts(value):
    """The contact fractions of a shipped clip's source: a composed move's
    side record, a sentence's judged contacts in the manifest, a preset's
    blow as the palette cut it."""
    value = value.split("~")[0].replace("+abs", "")
    if value.endswith(".npz"):
        stem = Path(value).name.replace(".motion.npz", "")
        side = MOTIONS / f"{stem}.json"
        if not side.exists():
            side = AIMED / f"{stem}.json"
        if side.exists():
            rec = json.loads(side.read_text())
            if rec.get("contact_fractions"):
                return rec["contact_fractions"]
        rec = load()["moves"].get(stem, {})
        if rec.get("contacts"):
            return rec["contacts"]
        if rec.get("blow_fraction") is not None:
            return [rec["blow_fraction"]]
    return None


def cmd_timings(a):
    """clip_timings.json from the cut reports: every family's skill clips, the
    seconds each was shipped at and where its strikes land. A preset clip
    keeps the one blow the palette warped it to; a composed move and a
    sentence carry their own contact list; the five gods' bespoke clips keep
    BattleSceneController's measured rows."""
    gods = {"anubis": {"attack_basic": 0.38, "attack_heavy": 0.50, "ultimate": 0.55},
            "sekhmet": {"attack_basic": 0.45, "attack_heavy": 0.42, "ultimate": 0.45},
            "zeus": {"attack_basic": 0.47, "attack_heavy": 0.40, "ultimate": 0.78},
            "ares": {"attack_basic": 0.47, "attack_heavy": 0.50, "ultimate": 0.45},
            "thoth": {"attack_basic": 0.55, "attack_heavy": 0.60, "ultimate": 0.65}}
    table = {}
    for report in sorted((MOTIONS / "shipped").glob("*.json")):
        family = report.stem
        rep = json.loads(report.read_text())
        clips = rep.get("clips", rep)
        entry = {}
        for clip in SKILL_CLIPS:
            facts = clips.get(clip)
            if not isinstance(facts, dict):
                continue
            seconds = facts.get("seconds")
            hits = source_contacts(str(facts.get("preset", "")))
            if hits is None and facts.get("blow") is not None:
                hits = [facts["blow"]]
            if seconds and hits:
                entry[clip] = {"seconds": round(float(seconds), 3), "contacts": [round(float(h), 3) for h in hits]}
        base = family.replace("_awakened", "")
        for clip, frac in gods.get(base, {}).items():
            entry.setdefault(clip, {"seconds": None, "contacts": [frac]})
        if entry:
            table[family] = entry
    # a god's bespoke clip has no report: its length is read off the shipped file
    for family, entry in table.items():
        for clip, rec in entry.items():
            if rec["seconds"] is None:
                rec["seconds"] = usdz_seconds(REPO / "Pantheon" / "Resources" / "Models" / f"{family}_{clip}.usdz")
    table = {f: {c: r for c, r in e.items() if r["seconds"]} for f, e in table.items()}
    TIMINGS.write_text(json.dumps({"version": 1, "assets": table}, indent=1, sort_keys=True) + "\n")
    n = sum(len(e) for e in table.values())
    print(f"{TIMINGS.relative_to(REPO)}: {len(table)} assets, {n} clips")


def usdz_seconds(path):
    """A shipped clip's length in seconds, off its USD stage."""
    if not path.exists():
        return None
    from pxr import Usd
    stage = Usd.Stage.Open(str(path))
    fps = stage.GetTimeCodesPerSecond() or 30.0
    return round((stage.GetEndTimeCode() - stage.GetStartTimeCode()) / fps, 3)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    p = sub.add_parser("say", help="queue one sentence under a key")
    p.add_argument("key"); p.add_argument("seconds", type=float); p.add_argument("prompt")
    p.add_argument("--mode", default="prime", choices=["prime", "swift"]); p.add_argument("--role", default="")
    p = sub.add_parser("launch", help="queue every row of a TSV: key, seconds, sentence[, role]")
    p.add_argument("tsv"); p.add_argument("--only"); p.add_argument("--mode", default="prime", choices=["prime", "swift"])
    p = sub.add_parser("run", help="advance every queued move: text-to-motion, apply to the donor, archive")
    p.add_argument("keys", nargs="*"); p.add_argument("--floor", type=int, default=100)
    p.add_argument("--parallel", type=int, default=12); p.add_argument("--timeout", type=int, default=4 * 3600)
    sub.add_parser("list")
    p = sub.add_parser("contacts", help="where an archived motion strikes")
    p.add_argument("npz"); p.add_argument("--expect", type=int); p.add_argument("--hands", default="both", choices=["both", "right", "left"])
    p = sub.add_parser("compose", help="chain single strikes into the style moves of tools/skills/style_moves.json")
    p.add_argument("names", nargs="*")
    p = sub.add_parser("board", help="motions on the donor frame by frame, with the strike signal and contacts")
    p.add_argument("names", nargs="+"); p.add_argument("--out", required=True); p.add_argument("--every", type=int)
    p.add_argument("--frames", type=int, default=12); p.add_argument("--size", type=int, default=210)
    p.add_argument("--views", default="front,side"); p.add_argument("--expect", nargs="*", help="name=N strongest contacts")
    p.add_argument("--wrap", type=int, help="cells to a line (a legible board is about 2,000 px wide)")
    p = sub.add_parser("ship", help="every family's skill clips through motion_palette.py ship")
    p.add_argument("families", nargs="*"); p.add_argument("--bundle", required=True); p.add_argument("--real", action="store_true")
    p.add_argument("--jobs", type=int, default=2); p.add_argument("--dry-run", action="store_true")
    sub.add_parser("timings", help="write Pantheon/Resources/Models/clip_timings.json from the cut reports")
    a = ap.parse_args()
    {"say": cmd_say, "launch": cmd_launch, "run": cmd_run, "list": cmd_list, "contacts": cmd_contacts,
     "compose": cmd_compose, "board": cmd_board,
     "ship": cmd_ship, "timings": cmd_timings}[a.cmd](a)


if __name__ == "__main__":
    main()
