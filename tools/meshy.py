#!/usr/bin/env python3
"""
Drives Meshy's API from a prompt to a rigged, animated character, and records
every task id so that a re-run never pays for the same step twice.

    python3 tools/meshy.py balance
    python3 tools/meshy.py library --grep punch
    python3 tools/meshy.py generate sekhmet --height 2.0 \
        --prompt "..." --negative "..."           # first run; later runs resume
    python3 tools/meshy.py status sekhmet
    python3 tools/meshy.py download sekhmet         # -> Art/Models/sekhmet*.glb
    python3 tools/meshy.py motion zeus_hd ultimate --prompt "raises both arms, gathers a storm overhead, hurls it forward"
                                                    # a bespoke clip from a sentence, applied to the rig
    python3 tools/glb2usd.py sekhmet                 # -> Art/Models/sekhmet*.usdz
    python3 tools/mesh.py sekhmet                    # -> Pantheon/Resources/Models/, decimated

This is the pipeline Docs/ART_PIPELINE.md describes for the web app, done by
machine:

    text-to-3d preview  ->  refine (textures, PBR)  ->  rig (humanoid, real height)
                        ->  one animation task per clip in AnimationClip

Every stage writes its task id into Art/Models/<asset>.meshy.json BEFORE it
waits on the task, so an interrupted run, a dead session or a second
invocation resumes the existing task instead of creating - and paying for -
another. Only a task that Meshy reports FAILED, CANCELED or EXPIRED is
replaced. The manifest is committed: it is the durable pointer to the heavy
exports, which are too large to want in git more than once.

The key is read from $MESHY_API_KEY or --key-file. Never from the repo.

Two hosts are involved. api.meshy.ai creates and polls tasks; the finished
files are served from assets.meshy.ai. An environment can have the first open
and the second closed, in which case everything up to `download` works and
`download` names the host that needs adding.
"""

import argparse, base64, json, os, sys, time
from datetime import datetime, timezone
from pathlib import Path
from urllib.parse import urlparse

import requests

API = "https://api.meshy.ai/openapi"
REPO = Path(__file__).resolve().parent.parent
ART = REPO / "Art" / "Models"

# Meshy's motion library uses its own names, so these are the picks for each
# clip in AnimationClip (Core/Models/Presentation.swift), chosen from the
# catalogue for in-place motion of roughly the contracted length. `library`
# prints the whole catalogue; --clips overrides any of them.
#
# The first roster was cut with 96 "Kung Fu Punch" and 237 "Charged Axe Chop":
# a martial-arts strike that throws a leg out and an overhead chop with a wide
# stance, which read as ugly on a robed god the moment the camera framed the
# whole figure. The defaults are now sword cuts with the feet planted, and
# CLIP_SETS below swaps the three attacks for the kits that do not swing a
# blade: a caster casts, a hammer-bearer swings, an archer draws.
DEFAULT_CLIPS = {
    "idle_combat":    89,   # "Combat Idel"  - fighting stance, loops
    "attack_basic":  219,   # "Right-hand Sword Slash" - one clean one-handed cut, feet planted
    "attack_heavy":  242,   # "Charged Slash" - a wind-up and one big two-handed cut
    "hit_react":     178,   # "Hit Reaction" - a flinch that stays in place
    "death":           8,   # "Dead" - collapse
    "ultimate":      102,   # "Sword Judgment" - the rite: the blade raised high and brought down
    "victory":       412,   # "Victory"
    "idle":            0,   # "Idle" - relaxed breathing
    "summon_reveal": 377,   # "Relax Arms, Then Strike Battle Pose"
}
# Per-kit overrides of the attack clips. `--clips <set>` (optionally followed
# by ",name=id" overrides) picks one; wave_launch.sh passes the spec's fifth
# field through. The kits map: striker, duelist, warden -> blade; bruiser ->
# heavy; healer, oracle, trickster -> caster; marksman -> archer (only when the
# concept actually holds a bow - a staff-bearer is a caster).
CLIP_SETS = {
    "blade":  {},
    "heavy":  {"attack_heavy": 128,                        # "Heavy Hammer Swing"
               "ultimate":     127},                       # "Charged Ground Slam"
    "caster": {"attack_basic": 129,                        # "Mage Spell Cast" - a one-handed cast
               "attack_heavy": 125,                        # "Charged Spell Cast" - both hands, a gather and release
               "ultimate":     126},                       # "Charged Spell Cast 1" - the long gather
    "archer": {"attack_basic": 224,                        # "Archery Shot"
               "attack_heavy": 226,                        # "Archery Shot 2"
               "ultimate":     222},                       # "Draw and Shoot from Back"
}
# What a battle needs to read as finished. `victory` joined the set on
# 2026-09-10: the scene controller has always played it when the player wins
# (BattleSceneController, on `.battleEnded`), but no character shipped the
# file, so a win ended with the team standing still. Seven clips is 21 credits
# of the 53 a character costs.
BATTLE_CLIPS = ["idle_combat", "attack_basic", "attack_heavy", "hit_react", "death", "ultimate", "victory"]

POLL_SECONDS = 10
TASK_TIMEOUT = 4 * 60 * 60   # a big wave queues behind itself for hours
TERMINAL = {"SUCCEEDED", "FAILED", "CANCELED", "EXPIRED"}
ENDPOINT = {
    "preview": "/v2/text-to-3d",
    "refine":  "/v2/text-to-3d",
    "image":   "/v1/image-to-3d",
    "rig":     "/v1/rigging",
    "clip":    "/v1/animations",
    # Text to Motion (2026): a motion clip from a sentence, no character needed
    # - `prompt`, `duration` 2-10 s in 0.5 s steps, `mode` prime (10 credits,
    # the quality to ship) or swift (3). The Animation API then takes
    # `motion_task_id` in place of a preset `action_id`, for the usual 3.
    # The docs host is closed to this environment; the field names were read
    # off the API's own validation errors (an empty body creates nothing).
    "motion":  "/v1/text-to-motion",
}


# ---------------------------------------------------------------------------
# API
# ---------------------------------------------------------------------------

def load_key(path):
    if os.environ.get("MESHY_API_KEY"):
        return os.environ["MESHY_API_KEY"].strip()
    if path and Path(path).exists():
        return Path(path).read_text().strip()
    sys.exit("no API key: set MESHY_API_KEY or pass --key-file")


class Meshy:
    def __init__(self, key):
        self.s = requests.Session()
        self.s.headers["Authorization"] = f"Bearer {key}"

    def call(self, method, path, body=None, attempts=6):
        delay = 5
        queue_waits = 0
        attempt = 0
        while attempt < attempts:
            attempt += 1
            try:
                r = self.s.request(method, f"{API}{path}", json=body, timeout=60)
            except requests.exceptions.RequestException as e:
                # The proxy drops a connection now and then; a poll or a
                # create is safe to repeat (a create that never answered
                # never charged).
                if attempt < attempts:
                    print(f"  {type(e).__name__} - retrying in {delay}s", file=sys.stderr)
                    time.sleep(delay)
                    delay = min(delay * 2, 60)
                    continue
                raise
            if r.status_code < 300:
                return r.json() if r.content else {}
            # The plan caps the number of queued tasks. A wave of launches
            # trips it, and the only cure is to wait for the queue to
            # drain, so that particular 429 is waited out for up to two
            # hours (and does not count against the retry budget).
            if r.status_code == 429 and "NoMorePendingTasks" in r.text and queue_waits < 120:
                queue_waits += 1
                if queue_waits in (1, 10, 30, 60, 90):
                    print(f"  Meshy queue is full - waiting for a slot ({queue_waits} min so far)", file=sys.stderr)
                time.sleep(60)
                attempt -= 1
                continue
            # Rate limits and transient 5xx are worth waiting out. Anything
            # else is a real error and retrying it would only burn credits.
            if r.status_code in (429, 500, 502, 503, 504) and attempt < attempts:
                print(f"  {r.status_code} from Meshy - retrying in {delay}s", file=sys.stderr)
                time.sleep(delay)
                delay = min(delay * 2, 60)
                continue
            try:
                msg = r.json().get("message") or r.text
            except Exception:
                msg = r.text
            sys.exit(f"Meshy {r.status_code} on {method} {path}: {str(msg)[:600]}")
        sys.exit("gave up after retries")

    def balance(self):
        return self.call("GET", "/v1/balance").get("balance")

    def library(self):
        d = self.call("GET", "/v1/animations/library?page_size=1000")
        return d if isinstance(d, list) else d.get("result", d)

    def create(self, kind, body):
        d = self.call("POST", ENDPOINT[kind], body)
        tid = d.get("result") if isinstance(d, dict) else None
        if not tid:
            sys.exit(f"unexpected create response: {d}")
        return tid

    def task(self, kind, tid):
        return self.call("GET", f"{ENDPOINT[kind]}/{tid}")


# ---------------------------------------------------------------------------
# Manifest
# ---------------------------------------------------------------------------

def now():
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def manifest_path(asset):
    return ART / f"{asset}.meshy.json"


def load_manifest(asset):
    p = manifest_path(asset)
    return json.loads(p.read_text()) if p.exists() else None


def save_manifest(m):
    p = manifest_path(m["asset"])
    p.parent.mkdir(parents=True, exist_ok=True)
    tmp = p.with_suffix(".tmp")
    tmp.write_text(json.dumps(m, indent=2) + "\n")
    tmp.replace(p)


def urls_in(obj, prefix=""):
    """Every URL-valued field of a task response, flattened:
    {'model_urls.usdz': 'https://...', 'result.animation_glb_url': ...}."""
    out = {}
    if isinstance(obj, dict):
        for k, v in obj.items():
            out.update(urls_in(v, f"{prefix}{k}."))
    elif isinstance(obj, list):
        for i, v in enumerate(obj):
            out.update(urls_in(v, f"{prefix}{i}."))
    elif isinstance(obj, str) and obj.startswith("http"):
        out[prefix[:-1]] = obj
    return out


def record(st, d):
    """Copies what matters from a task response into the manifest entry."""
    st["status"] = d.get("status")
    st["progress"] = d.get("progress")
    st["urls"] = urls_in({k: d.get(k) for k in
                          ("model_urls", "thumbnail_url", "video_url", "texture_urls", "result")})
    for k in ("created_at", "started_at", "finished_at", "preceding_tasks", "art_style", "name"):
        if d.get(k) is not None:
            st[k] = d[k]
    if d.get("task_error"):
        st["error"] = d["task_error"]
    st["polled"] = now()


def stage_key(kind, clip=None):
    if not clip:
        return kind
    return f"clip:{clip}" if kind == "clip" else f"{kind}:{clip}"


# ---------------------------------------------------------------------------
# Stages
# ---------------------------------------------------------------------------

def ensure_task(api, m, kind, body, clip=None):
    """The task id for a stage - resumed if one is live, created only if not."""
    key = stage_key(kind, clip)
    st = m["stages"].get(key)
    if st and st.get("status") not in ("FAILED", "CANCELED", "EXPIRED"):
        print(f"  {key:22s} resuming {st['id']} ({st.get('status') or 'created'})")
        return st["id"]
    if st:
        m.setdefault("history", []).append(st)

    before = api.balance()
    tid = api.create(kind, body)
    after = api.balance()
    st = {"id": tid, "kind": kind, "created": now(), "status": "PENDING",
          "request": body, "cost": (before - after) if before is not None and after is not None else None}
    if clip:
        st["clip"] = clip
        if body.get("action_id") is not None:
            st["action_id"] = body["action_id"]
        if body.get("motion_task_id"):
            st["motion_task_id"] = body["motion_task_id"]
    m["stages"][key] = st
    save_manifest(m)
    print(f"  {key:22s} created  {tid}   ({st['cost']} credits)")
    return tid


def wait(api, m, keys):
    """Polls the listed stages until each is terminal. Returns the failures."""
    t0, last, pending = time.time(), {}, set(keys)
    while pending:
        for key in sorted(pending):
            st = m["stages"][key]
            d = api.task(st["kind"], st["id"])
            record(st, d)
            status, progress = st["status"], st.get("progress")
            queue = st.get("preceding_tasks") or 0
            if (status, progress) != last.get(key):
                q = f"  {queue} ahead in queue" if queue else ""
                print(f"  {key:22s} {status:12s} {progress if progress is not None else 0:>3}%"
                      f"  +{int(time.time() - t0):d}s{q}")
                last[key] = (status, progress)
            if status in TERMINAL:
                pending.discard(key)
                if status != "SUCCEEDED":
                    msg = (st.get("error") or {}).get("message", "")
                    print(f"  {key:22s} {status}: {msg}")
        save_manifest(m)
        if pending:
            if time.time() - t0 > TASK_TIMEOUT:
                sys.exit("timed out waiting on Meshy; the tasks are in the manifest - re-run to keep waiting")
            time.sleep(POLL_SECONDS)
    return [k for k in keys if m["stages"][k]["status"] != "SUCCEEDED"]


def parse_clips(spec):
    """'all' | 'battle' | a CLIP_SETS name | 'idle_combat,attack_basic' |
    'caster,ultimate=127' (a set, then name=id overrides on top)."""
    if not spec or spec == "battle":
        return {k: DEFAULT_CLIPS[k] for k in BATTLE_CLIPS}
    if spec == "all":
        return dict(DEFAULT_CLIPS)
    items = [i.strip() for i in spec.split(",") if i.strip()]
    out = {}
    if items and items[0] in CLIP_SETS:
        out = {k: DEFAULT_CLIPS[k] for k in BATTLE_CLIPS}
        out.update(CLIP_SETS[items.pop(0)])
    for item in items:
        if "=" in item:
            name, aid = item.split("=", 1)
            out[name.strip()] = int(aid)
        elif item in CLIP_SETS:
            out.update(CLIP_SETS[item])
        elif item in DEFAULT_CLIPS:
            out[item] = DEFAULT_CLIPS[item]
        else:
            sys.exit(f"unknown clip '{item}' - name one of {', '.join(DEFAULT_CLIPS)}, a set ({', '.join(CLIP_SETS)}) or name=action_id")
    return out


def summary(m):
    total = sum(st.get("cost") or 0 for st in m["stages"].values())
    total += sum(st.get("cost") or 0 for st in m.get("history", []))
    print(f"\n{m['asset']}   {manifest_path(m['asset']).relative_to(REPO)}")
    for key, st in m["stages"].items():
        fields = sorted(k.replace("result.", "").replace("model_urls.", "") for k in st.get("urls", {}))
        cost = f"{st['cost']} cr" if st.get("cost") is not None else ""
        print(f"  {key:22s} {(st.get('status') or '?'):10s} {st['id']}  {cost:>6}   {' '.join(fields)}")
    print(f"  credits spent on this asset: {total}")


# ---------------------------------------------------------------------------
# Commands
# ---------------------------------------------------------------------------

def cmd_balance(a):
    print(Meshy(load_key(a.key_file)).balance())


def cmd_library(a):
    items = Meshy(load_key(a.key_file)).library()
    needle = (a.grep or "").lower()
    for it in items:
        text = f"{it.get('name', '')} {it.get('category', '')} {it.get('sub_category', '')}".lower()
        if needle in text:
            print(f"{it['action_id']:4d}  {it.get('category', ''):15s} {it.get('sub_category', ''):22s} {it.get('name', '')}")


def image_data_uri(path):
    p = Path(path)
    mime = "image/png" if p.suffix.lower() == ".png" else "image/jpeg"
    return f"data:{mime};base64," + base64.b64encode(p.read_bytes()).decode()


def cmd_generate(a):
    api = Meshy(load_key(a.key_file))
    m = load_manifest(a.asset)
    if m is None:
        if not a.prompt and not a.image:
            sys.exit("the first run for an asset needs --prompt or --image; later runs resume from the manifest")
        m = {
            "asset": a.asset,
            "created": now(),
            "prompt": a.prompt or "",
            "negative_prompt": a.negative or "",
            # Concept-first: a designed full-body drawing (from the portrait,
            # via Gemini) becomes the model through image-to-3D, which is far
            # more faithful than a sentence and makes the model match its card.
            "image": (str(Path(a.image).resolve().relative_to(REPO)) if Path(a.image).resolve().is_relative_to(REPO)
                      else str(Path(a.image).resolve())) if a.image else "",
            "texture_prompt": a.texture_prompt or "",
            "settings": {
                "ai_model": a.ai_model, "art_style": a.style, "topology": a.topology,
                "target_polycount": a.polycount, "symmetry_mode": a.symmetry,
                "height_meters": a.height,
            },
            "stages": {},
            "history": [],
        }
        save_manifest(m)
    elif a.prompt and a.prompt != m["prompt"]:
        sys.exit(f"{a.asset} already has a manifest with a different prompt; "
                 f"use another asset name or delete {manifest_path(a.asset)} to start over")
    s = m["settings"]
    start = api.balance()
    print(f"{a.asset}: {start} credits available")

    if m.get("image"):
        # One task does what preview + refine do for text: geometry from the
        # drawing, remeshed, and textured with PBR maps.
        print("image-to-3d")
        image_path = REPO / m["image"] if not Path(m["image"]).is_absolute() else Path(m["image"])
        body = {
            "image_url": image_data_uri(image_path),
            "ai_model": s["ai_model"], "topology": s["topology"],
            "target_polycount": s["target_polycount"], "should_remesh": True,
            "should_texture": True, "enable_pbr": True, "symmetry_mode": s["symmetry_mode"],
        }
        if m.get("texture_prompt"):
            body["texture_prompt"] = m["texture_prompt"]
        ensure_task(api, m, "image", body)
        if wait(api, m, ["image"]):
            summary(m)
            sys.exit("image-to-3d failed - re-run to try again with a fresh task")
        if a.until in ("preview", "refine"):
            return summary(m)
        mesh_task = m["stages"]["image"]["id"]
    else:
        print("preview")
        body = {
            "mode": "preview", "prompt": m["prompt"],
            "art_style": s["art_style"], "ai_model": s["ai_model"], "topology": s["topology"],
            "target_polycount": s["target_polycount"], "should_remesh": True,
            "symmetry_mode": s["symmetry_mode"],
        }
        if m["negative_prompt"]:
            body["negative_prompt"] = m["negative_prompt"]
        ensure_task(api, m, "preview", body)
        if wait(api, m, ["preview"]):
            summary(m)
            sys.exit("preview failed - re-run to try again with a fresh task")
        if a.until == "preview":
            return summary(m)

        print("refine")
        ensure_task(api, m, "refine", {
            "mode": "refine", "preview_task_id": m["stages"]["preview"]["id"], "enable_pbr": True,
        })
        if wait(api, m, ["refine"]):
            summary(m)
            sys.exit("refine failed - re-run to try again with a fresh task")
        if a.until == "refine":
            return summary(m)
        mesh_task = m["stages"]["refine"]["id"]

    print("rig")
    ensure_task(api, m, "rig", {
        "input_task_id": mesh_task, "height_meters": s["height_meters"],
    })
    if wait(api, m, ["rig"]):
        summary(m)
        sys.exit("rigging failed - see the error above; a fresh mesh may be needed")
    if a.until == "rig":
        return summary(m)

    print("clips")
    clips = parse_clips(a.clips)
    keys = []
    for name, action_id in clips.items():
        ensure_task(api, m, "clip", {"rig_task_id": m["stages"]["rig"]["id"], "action_id": action_id}, clip=name)
        keys.append(stage_key("clip", name))
    failed = wait(api, m, keys)
    summary(m)
    end = api.balance()
    print(f"  balance {start} -> {end}")
    if failed:
        sys.exit(f"clips failed: {', '.join(failed)} - re-run to retry just those")
    print(f"\nnext: python3 tools/meshy.py download {a.asset}")


def cmd_motion(a):
    """A bespoke clip from a sentence. Text-to-motion makes the motion, the
    Animation API applies it to the asset's finished rig under the clip name
    given, and from there `download` and `mesh.py` treat it exactly like a
    preset clip: it lands as Art/Models/<asset>_<clip>.glb and ships as
    Pantheon/Resources/Models/<asset>_<clip>.usdz. A preset clip of the same
    name is moved to the manifest's history, so the family keeps one file
    per clip and the game needs no change to play it."""
    api = Meshy(load_key(a.key_file))
    m = load_manifest(a.asset) or sys.exit(f"no manifest for {a.asset}")
    rig = m["stages"].get("rig")
    if not rig or rig.get("status") != "SUCCEEDED":
        sys.exit(f"{a.asset} has no finished rig - run generate first")
    if a.clip not in DEFAULT_CLIPS:
        sys.exit(f"'{a.clip}' is not a clip the game plays; one of {', '.join(DEFAULT_CLIPS)}")
    if (a.duration * 2) != int(a.duration * 2) or not 2 <= a.duration <= 10:
        sys.exit("--duration is 2 to 10 seconds in 0.5 s steps")
    start = api.balance()
    print(f"{a.asset}: {start} credits available")
    price = (10 if a.mode == "prime" else 3) + 3
    if start is not None and start - price < a.floor:
        sys.exit(f"a {a.mode} clip is about {price} credits and the balance would fall below the {a.floor} floor")

    print("motion")
    mkey = stage_key("motion", a.clip)
    st = m["stages"].get(mkey)
    if st and st.get("request", {}).get("prompt") != a.prompt:
        # A new sentence is a new motion; the old one keeps its place in history.
        m.setdefault("history", []).append(m["stages"].pop(mkey))
    ensure_task(api, m, "motion", {"prompt": a.prompt, "duration": a.duration, "mode": a.mode}, clip=a.clip)
    if wait(api, m, [mkey]):
        summary(m)
        sys.exit("text-to-motion failed - re-run to try again, or reword the prompt")
    motion_id = m["stages"][mkey]["id"]

    print("clip")
    ckey = stage_key("clip", a.clip)
    st = m["stages"].get(ckey)
    if st and st.get("motion_task_id") != motion_id:
        m.setdefault("history", []).append(m["stages"].pop(ckey))
    ensure_task(api, m, "clip", {"rig_task_id": rig["id"], "motion_task_id": motion_id}, clip=a.clip)
    failed = wait(api, m, [ckey])
    summary(m)
    end = api.balance()
    print(f"  balance {start} -> {end}")
    if failed:
        sys.exit("the animation failed - re-run to retry it")
    print(f"\nnext: python3 tools/meshy.py download {a.asset} --force   # the old {a.clip} file is replaced")


def refresh(api, m):
    for key, st in m["stages"].items():
        record(st, api.task(st["kind"], st["id"]))
    m["refreshed"] = now()
    save_manifest(m)


def cmd_status(a):
    m = load_manifest(a.asset) or sys.exit(f"no manifest for {a.asset}")
    refresh(Meshy(load_key(a.key_file)), m)
    summary(m)


def pick(urls, formats, must_contain):
    """The first URL matching the preferred formats, e.g. 'result.rigged_character_usdz_url'
    or 'model_urls.usdz', restricted to keys that mention `must_contain`."""
    for fmt in formats:
        for key, url in urls.items():
            if must_contain not in key:
                continue
            if key.endswith(f".{fmt}") or key.endswith(f"_{fmt}_url") or key.endswith(f"_{fmt}"):
                return url, fmt
    return None, None


def fetch(url, dest):
    try:
        with requests.get(url, stream=True, timeout=300) as r:
            r.raise_for_status()
            dest.parent.mkdir(parents=True, exist_ok=True)
            with open(dest, "wb") as f:
                for chunk in r.iter_content(1 << 20):
                    f.write(chunk)
    except requests.exceptions.ProxyError:
        host = urlparse(url).netloc
        sys.exit(
            f"\nthe environment's proxy refused {host}, so the finished files cannot be fetched from here.\n"
            f"Nothing is lost: the tasks are in the manifest. To open the host:\n"
            f"  1. claude.ai/code -> cloud icon above the message box -> hover the environment -> gear\n"
            f"  2. Network access: Custom -> add '{host}' beside api.meshy.ai\n"
            f"  3. keep 'Also include default list of common package managers' ticked, save\n"
            f"  4. start a NEW session and run: python3 tools/meshy.py download {dest.name.split('_')[0].split('.')[0]}\n"
        )
    return dest.stat().st_size


def cmd_download(a):
    m = load_manifest(a.asset) or sys.exit(f"no manifest for {a.asset}")
    api = Meshy(load_key(a.key_file))
    refresh(api, m)        # signed URLs expire; always fetch fresh ones
    formats = [f.strip() for f in a.formats.split(",")]
    dest = Path(a.dest) if a.dest else ART

    jobs = []
    rig = m["stages"].get("rig")
    if rig and rig.get("status") == "SUCCEEDED":
        jobs.append((rig, "rigged_character", a.asset))
    for key, st in m["stages"].items():
        if key.startswith("clip:") and st.get("status") == "SUCCEEDED":
            jobs.append((st, "animation", f"{a.asset}_{st['clip']}"))
    if a.include_unrigged:
        for stage in ("refine", "preview", "image"):
            st = m["stages"].get(stage)
            if st and st.get("status") == "SUCCEEDED":
                jobs.append((st, "model_urls", f"{a.asset}_{stage}"))
    if not jobs:
        sys.exit("nothing finished to download yet - run `status` or `generate`")

    for st, hint, name in jobs:
        url, fmt = pick(st.get("urls", {}), formats, hint)
        if not url:
            have = ", ".join(sorted(st.get("urls", {}))) or "none"
            print(f"  {name:28s} no {'/'.join(formats)} URL among: {have}")
            continue
        out = dest / f"{name}.{fmt}"
        if out.exists() and not a.force:
            print(f"  {name:28s} exists ({out.stat().st_size / 1048576:.1f} MB) - skipped, --force to refetch")
            continue
        size = fetch(url, out)
        st.setdefault("downloaded", {})[fmt] = str(out.relative_to(REPO)) if out.is_relative_to(REPO) else str(out)
        print(f"  {name:28s} {fmt:5s} {size / 1048576:6.1f} MB  -> {out}")
    save_manifest(m)
    fetched = {fmt for st in m["stages"].values() for fmt in st.get("downloaded", {})}
    if "glb" in fetched:
        print(f"\nnext: python3 tools/glb2usd.py {a.asset}   # GLB -> USDZ, the rig and clips only come as GLB")
        print(f"      python3 tools/mesh.py {a.asset}      # decimate into Pantheon/Resources/Models/")
    else:
        print(f"\nnext: python3 tools/mesh.py {a.asset}      # decimate into Pantheon/Resources/Models/")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--key-file")
    sub = ap.add_subparsers(dest="cmd", required=True)

    sub.add_parser("balance", help="credits left on the account")

    p = sub.add_parser("library", help="print Meshy's animation catalogue")
    p.add_argument("--grep", help="case-insensitive filter on name/category")

    p = sub.add_parser("generate", help="prompt -> preview -> refine -> rig -> clips, resumable")
    p.add_argument("asset", help="assetName in ModelSpec, e.g. sekhmet")
    p.add_argument("--prompt", help="required on the first run for an asset, unless --image")
    p.add_argument("--negative", help="negative prompt")
    p.add_argument("--image", help="a designed full-body concept drawing: image-to-3D instead of text-to-3D")
    p.add_argument("--texture-prompt", help="guides the texturing of an --image model")
    p.add_argument("--height", type=float, default=2.0, help="character height in metres (Docs/ART_PIPELINE.md §6)")
    p.add_argument("--style", default="realistic", choices=["realistic", "sculpture"])
    p.add_argument("--ai-model", default="latest", help="Meshy model: latest, meshy-5, ...")
    p.add_argument("--topology", default="quad", choices=["quad", "triangle"])
    p.add_argument("--polycount", type=int, default=30000, help="target polycount for the generator's remesh")
    p.add_argument("--symmetry", default="on", choices=["on", "off", "auto"])
    p.add_argument("--clips", default="battle",
                   help="'battle' (the six that make a fight read), 'all' (nine), a kit set (blade, heavy, caster, archer), "
                        "a comma list of clip names, or name=action_id pairs; a set may be followed by overrides")
    p.add_argument("--until", choices=["preview", "refine", "rig", "clips"], default="clips",
                   help="stop after this stage")

    p = sub.add_parser("motion", help="a bespoke clip from a sentence: text-to-motion, applied to the asset's rig")
    p.add_argument("asset", help="an asset with a finished rig in its manifest, e.g. zeus_hd")
    p.add_argument("clip", help="the clip it becomes: ultimate, attack_heavy, attack_basic, ...")
    p.add_argument("--prompt", required=True, help="the motion in a sentence or two; in place, feet planted")
    p.add_argument("--duration", type=float, default=4.0, help="2-10 seconds in 0.5 s steps")
    p.add_argument("--mode", default="prime", choices=["prime", "swift"], help="prime (10 credits) or swift (3); +3 to apply")
    p.add_argument("--floor", type=int, default=2000, help="never spend below this balance (the owner's floor, 2,000 since 2026-09-11)")

    p = sub.add_parser("status", help="re-poll every task in an asset's manifest")
    p.add_argument("asset")

    p = sub.add_parser("download", help="fetch the finished files into Art/Models/")
    p.add_argument("asset")
    p.add_argument("--formats", default="usdz,glb", help="preference order")
    p.add_argument("--dest", help="folder (default Art/Models)")
    p.add_argument("--include-unrigged", action="store_true", help="also fetch the preview and refine meshes")
    p.add_argument("--force", action="store_true", help="refetch files that already exist")

    a = ap.parse_args()
    {"balance": cmd_balance, "library": cmd_library, "generate": cmd_generate, "motion": cmd_motion,
     "status": cmd_status, "download": cmd_download}[a.cmd](a)


if __name__ == "__main__":
    main()
