"""The weapon pass over SHIPPED families (2026-09-23): a RIGID thing held in
a hand — a sword's blade, a thunderbolt, an ankh, a crook, a spear — that
Meshy's auto-rig bound partly to the THIGH, the hips or the spine goes back
to the hand that holds it, whole, so it swings as one piece with the hand
instead of stretching into a strip toward the hip. It is the skirt pass
turned round (character.reweight_skirt gives an ARM's cloth back to the
body; this gives a BODY's share of a held thing back to the hand).

    python3 tools/weapon_pass.py --survey                    # every shipped base, worst first
    python3 tools/weapon_pass.py --survey zeus_awakened ra   # these only
    python3 tools/weapon_pass.py zeus_awakened --out DIR     # re-weighted base + _lod into DIR
    python3 tools/weapon_pass.py zeus_awakened --in-place    # into the bundle (the owner's call)
    python3 tools/weapon_pass.py --self-test                 # a clean control moves nothing
    python3 tools/weapon_pass.py --all                       # every judged family (WEAPON_FAMILIES), in place

mesh.py runs the pass on a WEAPON_FAMILIES name after shipping it, so a
re-ship keeps the fix (`--no-weapon` skips it).

WHY THE FAULT EXISTS. The rigger's own rule for a concept is "everything held
hangs straight down against the outside of a thigh" — so in the A-pose the
blade, the bolt, the crook's hook lies ON the thigh, the auto-rig's heat
diffusion reaches it from the nearest bone, and the far end of the object
takes 10-45% of the thigh. When the arm swings, the hand's part goes with
the hand and the thigh's part stays at the hip: an edge on the object that
was 1 cm long is 30-80 cm long at the blow frame (zeus_awakened's bolt
measured 84x on the ultimate's frame 32).

THE OPTIONS WEIGHED (research, 2026-09-23):
  A. Re-rig from scratch (Meshy's rigger again, or a separate weapon bone).
     The game's clips reach joints by name, and every shipped clip carrier is
     rigged to THIS skeleton: a new bone would need the clips re-made (3
     credits a clip, and the motion tasks expire in three days). Rejected.
  B. Smooth or clamp the weights (a Laplacian pass over the stretched rows,
     or clamp every vertex's non-hand share under a threshold near the hand).
     A blend is still a blend: a vertex at 90/10 hand/thigh is still 10% at
     the hip, and a clamp by distance cannot tell the blade lying on the
     robe from the robe under it. Rejected.
  C. What the industry's tools do for a prop (Maya/Blender "rigid bind" of a
     prop to one joint, the weapon socket of every game engine; VRM and
     Unity humanoids parent a held prop to the hand bone): find the object
     as a PIECE, bind it wholly to ONE joint, and let the seam where it
     touches something else open instead of stretching. Chosen, with the
     piece found by measurement:
       1. The mesh is welded by position (Meshy splits it at UV seams) and
          the ARM's own skin (character._arm_masks: the upper arm, the
          forearm and the hand — a segment continued 0.12 h past the wrist,
          since Meshy's rigs have no finger bones) is cut out; what touches
          a HAND's skin and falls off the body as its own connected piece
          is a candidate. A thing whose tip is welded to the robe or the
          thigh stays on the body after that cut (freya_awakened's sword),
          so for a hand with no candidate of its own the legs' own surface
          (character._limb_surface round the thigh and the shin, with the
          inward stop) is cut out too.
       2. A candidate is HELD when the arm owns at least `ARM_SHARE` of its
          weight (the rigger itself read it as the hand's: a garment beside
          the hand, like Osiris's kilt panel at 30% hand, is not), when it
          lies mostly PAST the wrist along the forearm (a bracer lies before
          it), when it is under `MAX_SHARE` of the mesh, and when it does not
          WRAP the wrist: sewn to the forearm's skin along over half as much
          edge as to the hand's (jiangshi's sleeve ends, 0.94), or filling
          13 of 16 angle bins round the wrist (the terracotta soldier's
          cuffs, 16; every held thing measured 0-9). Bound to the hand, a
          sleeve's end tore from the forearm at 19x.
       3. It is measured: the shipped base skinned with its shipped clips
          (attack_basic, attack_heavy, ultimate, victory and the standing
          idle, joints matched by leaf name, as the game and
          tools/base_plus_clip.py do) at `SAMPLES` frames each, and the
          worst posed/rest length of every edge on the piece and across its
          border. A piece is re-bound when an edge on it stretches past
          `STRETCH_MIN` (2.0: the fingers of every clean control, blended
          across the wrist, read 1.2-1.5; the fault reads 4-80) AND the
          BODY holds over `BODY_MIN` of one of its rows (the fault's cause).
          A thing blended between the hand and the forearm alone bends at
          the wrist (osiris_awakened's crook and flail, 3.1x) and is left:
          bound to the hand, the flail's tails — a piece of their own on the
          forearm — came off the handle, and the kilt welded to his fist
          rode on it as shards (the board of 2026-09-23).
       4. The fix: every vertex of the piece takes the hand that holds it
          (the hand joint whose skin it touches most, or that owns most of
          its arm-side weight) at 1.0 — one joint, so the object is rigid —
          and every face across the piece's border with something that is
          not the arm's own skin is cut (character.cut_seam with `against`),
          so a blade welded to the robe leaves the robe where it hangs and
          the crack opens instead of the robe stretching after the hand. The
          border with the hand's own skin is kept: both sides follow the
          hand.
       5. A piece touching BOTH hands' skin is two-handed: bound to the hand
          touching it most and FLAGGED in the survey for a human.
       6. The LOD (<family>_lod.usdz, the mesh the battle draws) takes the
          base's verdict vertex by vertex (skirt_pass.transfer) and is cut
          the same way.
  The body, the cloth and the cape are never touched (only the piece's
  vertices change, and cape_*/robe_* joints are never given anything);
  the winged and the tailed (character.CAPE_EXCLUDE) are skipped: a wing
  along an arm touches a hand and is a piece past the wrist.

Judge a family on tools/base_plus_clip.py at the frame the survey names
(`--frames=N`, with the `=`), before and after, never on the count alone."""
import argparse, shutil, sys, tempfile
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
import character  # noqa: E402
import skirt_pass  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]
BUNDLE = ROOT / "Pantheon" / "Resources" / "Models"
SURVEY_OUT = Path("/tmp/claude-0/-home-user-Budget-and-advice/e26163d8-d4d7-5637-8ac3-d67e31cf21e3/scratchpad/weapon/survey.txt")

MEASURED_CLIPS = ("attack_basic", "attack_heavy", "ultimate", "victory", "idle")
SAMPLES = 48            # frames sampled per clip (a spike can live two frames: 16 missed zeus_awakened's 84x)
ARM_SHARE = 0.5         # the arm's share of a piece's weight for it to be a held thing
MAX_SHARE = 0.12        # a piece bigger than this share of the mesh is not a held thing
PAST_WRIST = 0.5        # the share of a piece's vertices past the wrist along the forearm
STRETCH_MIN = 2.0       # a piece whose worst edge stretches past this is re-bound: a finger bent at
                        # the wrist blend reads 1.2-1.5 on every clean control, the fault 3-80
BODY_MIN = 0.05         # ... or on which the body (not the arm) holds over this share of any row
ARM_RADIUS = {"arm": 0.10, "forearm": 0.10, "hand": 0.06, "grip": 0.06}
                        # how far from its bone the arm's own surface may lie (character.ROBE_ARM_RADIUS's
                        # numbers): uncapped, the grip segment's cells took the head of thor's hammer,
                        # 0.155 h out in front of the fist, as the hand's skin, and it stayed on the hips
LOWER_KINDS = ("hips", "upleg", "leg", "foot", "toebase")   # what a forearm and a hand are freed of
GRIP_RAMP = 0.6         # the forearm's body share goes in a ramp from the elbow to 0.6 of the way to the wrist
GRIP_REACH = 0.14       # the forearm and hand's own layer: within this share of the height of the
                        # elbow -> wrist -> grip line: a fist round a haft reaches 0.10 h
                        # from it (thor's hammer, whose rows the skin test gave the hand)
SLEEVE_BORDER = 0.5     # a piece sewn to the forearm's skin along over half as much edge as the
                        # hand's is a sleeve's end or a cuff (jiangshi, the terracotta soldier)
WRIST_RING = 13         # ... or one that goes 13 of 16 bins round the wrist: the terracotta
                        # soldier's cuffs fill 16, every held thing measured 0-9
SECOND_CUT_GROWTH = 0.5 # a second-cut piece that grows by more than half again over arm-held rows is
                        # sewn to a garment the arm holds (loki 6.7x; freya_awakened's sword 0.12x)
MIN_PIECE = 12          # vertices; smaller pieces are specks of the hand's own skin
CLEAN_CONTROLS = ("athena_awakened",)


def leaf(path):
    return path.split("/")[-1]


def families():
    return [n for n in skirt_pass.families()]


def excluded(name):
    return skirt_pass.excluded(name)


# --- measuring ---------------------------------------------------------------

def clip_matrices(base, name, bundle=BUNDLE, samples=SAMPLES):
    """[(clip, frame, (J,4,4) skinning matrices)] for the base skinned with
    each of its shipped clips at `samples` frames, joints matched by leaf
    name as the game does (a joint the clip lacks keeps its rest)."""
    out = []
    inv_bind = np.linalg.inv(base.bind)
    for clip_name in MEASURED_CLIPS:
        path = bundle / f"{name}_{clip_name}.usdz"
        if clip_name == "idle" and not path.exists():
            path = bundle / f"{name}_idle_combat.usdz"
        if not path.exists():
            continue
        clip = character.read_usdz(path)
        if not clip.anim:
            continue
        cmap = {leaf(j): i for i, j in enumerate(clip.joints)}
        a = clip.anim
        n = len(a["T"])
        for f in np.unique(np.linspace(0, n - 1, samples).round().astype(int)):
            local = np.array(base.rest_local, dtype=np.float64)
            for bi, bj in enumerate(base.joints):
                ci = cmap.get(leaf(bj))
                if ci is not None:
                    local[bi] = character.trs(a["T"][f, ci], a["R"][f, ci], a["S"][f, ci])
            world = character.world_from_local(local, base.parents)
            out.append((clip_name, int(f), np.einsum("jab,jbc->jac", inv_bind, world)))
    return out


def unique_edges(faces):
    e = np.vstack([faces[:, [0, 1]], faces[:, [1, 2]], faces[:, [2, 0]]])
    return np.unique(np.sort(e, axis=1), axis=0)


def worst_stretch(P, ji, jw, mats, edges, height):
    """Per edge: the worst posed/rest length over the sampled frames, and the
    index of that frame in `mats`. Edges under 0.1% of the height are 1.0
    (a sliver's ratio is noise)."""
    L0 = np.linalg.norm(P[edges[:, 0]] - P[edges[:, 1]], axis=1)
    ok = L0 > 1e-3 * height
    worst = np.ones(len(edges))
    at = np.zeros(len(edges), int)
    ph = np.c_[P, np.ones(len(P))]
    jw = jw.astype(np.float64)
    for k, (_, _, m) in enumerate(mats):
        per = np.einsum("nc,nkcd->nkd", ph, m[ji])
        Q = np.einsum("nk,nkd->nd", jw, per)[:, :3]
        L = np.linalg.norm(Q[edges[:, 0]] - Q[edges[:, 1]], axis=1) / np.maximum(L0, 1e-12)
        L[~ok] = 1.0
        better = L > worst
        worst[better] = L[better]
        at[better] = k
    return worst, at


def dense_weights(char, n=None):
    n = len(char.points) if n is None else n
    W = np.zeros((n, len(char.joints)))
    rows = np.broadcast_to(np.arange(n)[:, None], char.joint_indices[:n].shape)
    np.add.at(W, (rows, char.joint_indices[:n]), char.joint_weights[:n].astype(np.float64))
    return W


# --- finding the held things ---------------------------------------------------

def _pieces(key, canon, e, removed, n_points):
    from scipy.sparse import coo_matrix
    from scipy.sparse.csgraph import connected_components
    C = len(key)
    rm = np.zeros(C, bool)
    np.logical_or.at(rm, canon, removed)
    keep = ~rm[e[:, 0]] & ~rm[e[:, 1]]
    ee = e[keep]
    g = coo_matrix((np.ones(len(ee)), (ee[:, 0], ee[:, 1])), shape=(C, C))
    _, lab = connected_components(g, directed=False)
    labels = lab[canon].copy()
    labels[removed] = -1
    return labels


def held_pieces(char, report=None):
    """The held things of a base: a list of dicts {verts, hand, hands_touching,
    arm_share, past_wrist, ...}, one per candidate piece judged HELD, and the
    words for every candidate refused (in `report`, a list, if given)."""
    P = char.points.astype(np.float64)
    height = float(P[:, 1].max() - P[:, 1].min())
    leafs = [leaf(j) for j in char.joints]
    kind = [character._bone_kind(l) for l in leafs]
    J = len(leafs)
    jpos = np.array([char.bind[i][3, :3] for i in range(J)])
    normals = character.vertex_normals(P, char.faces).astype(np.float64)
    layer, skin, armkind = character._arm_masks(char, P, normals, radius=ARM_RADIUS)
    hands = [j for j, k in enumerate(kind) if k == "hand"]
    cloth = np.array([l.startswith(character.CLOTH_PREFIXES) for l in leafs])
    W = dense_weights(char)
    owner = np.argmax(W, axis=1)
    key, canon, e = character._welded_edges(P, char.faces)
    C = len(key)
    # Which hand's skin each welded point is (the grip skin: the hand owns it).
    hand_of_c = np.full(C, -1)
    forearm_of_c = np.full(C, -1)
    for h in hands:
        m = skin & (owner == h)
        hand_of_c[canon[m]] = h
        f = char.parents[h]
        forearm_of_c[canon[skin & (owner == f)]] = h
    legs = np.zeros(len(P), bool)
    for j, p in enumerate(char.parents):
        if p >= 0 and kind[j] in ("leg", "foot"):
            legs |= character._limb_surface(P, normals, jpos[p], jpos[j], reach=0.25 * height,
                                             gap=0.012 * height, inward_stop=True)
    # The forearm->hand axis per hand: "past the wrist" is t > 0 along it.
    axis = {}
    for h in hands:
        p = char.parents[h]
        u = jpos[h] - jpos[p]
        axis[h] = (jpos[h], u / max(np.linalg.norm(u), 1e-9))
    arm_cols = np.flatnonzero(armkind)
    found, taken = [], np.zeros(len(P), bool)

    def judge(labels, only_hands, second=False):
        out = []
        biggest = np.bincount(labels[labels >= 0]).argmax() if (labels >= 0).any() else -1
        for lab in np.unique(labels[labels >= 0]):
            if lab == biggest and not second:
                continue
            verts = np.flatnonzero(labels == lab)
            if len(verts) < MIN_PIECE or taken[verts].any():
                continue
            # The hands whose skin it touches, over the welded mesh.
            in_c = np.zeros(C, bool)
            in_c[canon[verts]] = True
            border = e[in_c[e[:, 0]] != in_c[e[:, 1]]]
            outside = np.where(in_c[border[:, 0]], border[:, 1], border[:, 0])
            touching = hand_of_c[outside]
            touching = touching[touching >= 0]
            if not len(touching):
                continue
            counts = {int(h): int((touching == h).sum()) for h in np.unique(touching)}
            sleeve = forearm_of_c[outside]
            if only_hands is not None and not (set(counts) & only_hands):
                continue
            mass = W[verts].sum(axis=0)
            arm_share = float(mass[arm_cols].sum() / max(mass.sum(), 1e-9))
            # The holding hand: the one touching it most, ties to the one
            # owning more of it.
            hand = max(counts, key=lambda h: (counts[h], mass[h]))
            wrist, u = axis[hand]
            past = float(((P[verts] - wrist) @ u > 0.0).mean())
            on_forearm = int((sleeve == hand).sum()) / max(counts[hand], 1)
            # How far round the wrist it goes: the angle bins it fills in a
            # band 2.5% of the height either side of the wrist, within 8%.
            rel = P[verts] - wrist
            tw = rel @ u
            radial = rel - tw[:, None] * u
            helper = np.array([1.0, 0.0, 0.0]) if abs(u[0]) < 0.9 else np.array([0.0, 1.0, 0.0])
            e1 = np.cross(u, helper); e1 /= np.linalg.norm(e1)
            e2 = np.cross(u, e1)
            band = (np.abs(tw) < 0.025 * height) & (np.linalg.norm(radial, axis=1) < 0.08 * height)
            bins = np.floor((np.arctan2(radial @ e2, radial @ e1) + np.pi) / (2 * np.pi) * 16).astype(int) % 16
            ring = len(np.unique(bins[band]))
            share = len(verts) / len(P)
            info = dict(on_forearm=on_forearm, verts=verts, hand=hand, hand_name=leafs[hand], touching={leafs[h]: c for h, c in counts.items()},
                        arm_share=arm_share, past_wrist=past, share=share,
                        two_handed=len(counts) > 1 and min(counts.values()) >= 0.2 * max(counts.values()),
                        body_share=float(1.0 - arm_share))
            words = (f"{len(verts):,} v at {leafs[hand]}, arm {arm_share:.0%}, past the wrist {past:.0%}, "
                     f"{100 * share:.1f}% of the mesh, forearm/hand border {on_forearm:.2f}")
            if share > MAX_SHARE:
                why = "too big to be held"
            elif arm_share < ARM_SHARE:
                why = "the body's (a garment beside the hand)"
            elif past < PAST_WRIST:
                why = "before the wrist (a bracer, a cuff)"
            elif on_forearm > SLEEVE_BORDER or ring >= WRIST_RING:
                why = f"wrapped round the wrist (a sleeve's end, a cuff: {ring}/16 round it)"
            else:
                why = None
            if why:
                if report is not None:
                    report.append(f"refused {words}: {why}")
                continue
            out.append(info)
        return out

    # 1. The arm's skin cut out.
    labels = _pieces(key, canon, e, skin, len(P))
    for info in judge(labels, None):
        found.append(info)
        taken[info["verts"]] = True
    # 2. The legs' surface cut out as well, for a thing welded to the robe
    #    or the thigh at its tip (it stayed on the body above): only pieces
    #    carved out of the body are new.
    body_piece = labels == np.bincount(labels[labels >= 0]).argmax()
    labels2 = _pieces(key, canon, e, skin | legs, len(P))
    labels2[~body_piece] = -1
    arm = W[:, armkind].sum(axis=1)
    pool_c = np.zeros(C, bool)
    pool_c[canon[(arm >= 0.2) & ~skin]] = True
    for info in judge(labels2, None, second=True):
        info["second_cut"] = True
        # Is the piece whole? Carved out of the body by the legs' surface, a
        # thing lying along the thigh can be cut in two — loki's dagger lay
        # along his coat, the second cut took its tip and left its blade on
        # the coat, and bound to the hand the tip flew off the broken blade.
        # So grow it over every row the arm holds a fifth of: a whole thing
        # grows little (freya_awakened's sword 81 rows on 677, its hilt's
        # rim); a thing sewn to a garment the arm holds grows into the
        # garment (loki's 1,637 on 246), and its hand is left for a human.
        seen = np.zeros(C, bool)
        seen[canon[info["verts"]]] = True
        frontier = seen.copy()
        for _ in range(80):
            hit = frontier[e[:, 0]] | frontier[e[:, 1]]
            step = np.zeros(C, bool)
            step[e[hit, 0]] = True
            step[e[hit, 1]] = True
            step &= pool_c & ~seen
            if not step.any():
                break
            seen |= step
            frontier = step
        grown = int((seen[canon] & ~np.isin(np.arange(len(P)), info["verts"])).sum())
        info["grown"] = grown
        if grown > SECOND_CUT_GROWTH * len(info["verts"]):
            info["ambiguous"] = (f"a piece of {len(info['verts']):,} carved off the legs is sewn to {grown:,} rows "
                                 f"the arm holds (a garment): the thing may be cut in two")
        found.append(info)
        taken[info["verts"]] = True
    for info in found:
        assert not cloth[info["hand"]]
    return found, dict(P=P, height=height, leafs=leafs, skin=skin, layer=layer, armkind=armkind, canon=canon, e=e, W=W,
                       axis=axis, jpos=jpos, parents=np.asarray(char.parents))


# --- the pass ----------------------------------------------------------------

def measure(char, name, bundle=BUNDLE, mats=None):
    """(pieces, per-piece worst stretch, the frame it is worst at, context)."""
    report = []
    pieces, ctx = held_pieces(char, report)
    if mats is None:
        mats = clip_matrices(char, name, bundle)
    ctx["mats"] = mats
    ctx["refused"] = report
    if not mats or not pieces:
        return pieces, ctx
    P, height = ctx["P"], ctx["height"]
    edges = unique_edges(char.faces)
    worst, at = worst_stretch(P, char.joint_indices, char.joint_weights, mats, edges, height)
    ctx["edges"], ctx["worst"], ctx["at"] = edges, worst, at
    for info in pieces:
        v = np.zeros(len(char.points), bool)
        v[info["verts"]] = True
        touch = v[edges[:, 0]] | v[edges[:, 1]]
        if touch.any():
            k = np.flatnonzero(touch)[np.argmax(worst[touch])]
            info["stretch"] = float(worst[k])
            clip, frame, _ = mats[at[k]]
            info["worst_at"] = (clip, frame)
        else:
            info["stretch"], info["worst_at"] = 1.0, None
        off = 1.0 - ctx["W"][info["verts"], info["hand"]]
        info["off_hand"] = float(off.max())
        body = ctx["W"][info["verts"]][:, ~ctx["armkind"]].sum(axis=1)
        info["body_max"] = float(body.max())
        info["body_rows"] = int((body > 0.02).sum())
        info["faulty"] = info["stretch"] > STRETCH_MIN and info["body_max"] > BODY_MIN
    # A hand that holds a faulty thing takes every piece it holds that is not
    # rigid (loki's second piece at 4.3x with 4% of the body, left beside the
    # fixed one, tore from it) ...
    hot = {p["hand"] for p in pieces if p["faulty"]}
    for info in pieces:
        if info["hand"] in hot and not info["faulty"] and (info["stretch"] > STRETCH_MIN or info["body_max"] > 0.02):
            info["faulty"] = True
    # ... and a hand holding something the pass cannot see whole is left as
    # it is, all of it, and named for a human.
    ctx["left"] = {}
    for info in pieces:
        if info.get("ambiguous") and info["faulty"]:
            ctx["left"][info["hand_name"]] = info["ambiguous"]
    for info in pieces:
        if info["hand_name"] in ctx["left"]:
            info["faulty"] = False
    return pieces, ctx


def _segment_distance(P, a, b):
    ab = b - a
    t = np.clip(((P - a) @ ab) / max(float(ab @ ab), 1e-12), 0.0, 1.0)
    return np.linalg.norm(P - (a + t[:, None] * ab), axis=1)


def rebind(char, pieces, ctx, verbose=True):
    """Binds each faulty held piece wholly to its hand, frees the FOREARM AND
    HAND of the lower body (their own layer, from the elbow to the grip,
    loses its share of the hips and the legs in a ramp from the elbow:
    freya_awakened's fist was 20-50% LeftUpLeg and her wrist 29%, and with
    the blade freed the fist alone still threw strands to the hip), and
    cuts the border of the piece and the freed grip with everything the
    body owns. Returns (rows changed, the changed mask over the ORIGINAL
    vertices, the rows the cut is made round)."""
    n0 = len(char.points)
    P = ctx["P"]
    height = ctx["height"]
    armkind = ctx["armkind"]
    moved = np.zeros(n0, bool)
    K = char.joint_indices.shape[1]
    ji_before, jw_before = char.joint_indices.copy(), char.joint_weights.copy()
    W = dense_weights(char)
    # The LOWER body: the hips and the legs. A forearm's share of the spine
    # is the rigger's blend where the elbow meets the flank, smooth on both
    # sides, and taken off the forearm alone it tore thor's elbow at 14x.
    lower = np.array([character._bone_kind(l) in LOWER_KINDS for l in ctx["leafs"]])
    body_share = W[:, lower].sum(axis=1)
    grip_rows = 0
    for info in pieces:
        if not info.get("faulty"):
            continue
        v = info["verts"]
        W[v] = 0.0
        W[v, info["hand"]] = 1.0
        moved[v] = True
    cut_rows = moved.copy()
    for hand in sorted({p["hand"] for p in pieces if p.get("faulty")}):
        # The forearm and the hand: the elbow -> wrist -> grip polyline. The
        # body's share is taken off in a RAMP from the elbow (none) to
        # `GRIP_RAMP` of the way to the wrist (all): stripped to a hard line,
        # thor's forearm tore at the line, 89x (the elbow of an A-pose rests
        # by the hips and the rigger gave it a fifth of Hips, legitimately
        # smooth on both sides of the line and a crack between them).
        wrist, u = ctx["axis"][hand]
        elbow = ctx["jpos"][ctx["parents"][hand]]
        forearm = max(float(np.linalg.norm(wrist - elbow)), 1e-6)
        tip = wrist + u * 0.12 * height
        t = (P - elbow) @ u
        d = np.minimum(_segment_distance(P, elbow, wrist), _segment_distance(P, wrist, tip))
        x = np.clip(t / (GRIP_RAMP * forearm), 0.0, 1.0)
        ramp = x * x * (3.0 - 2.0 * x)
        # ... and never on a row the arm holds under a fifth of: the skin
        # test can take a skirt pressed against the fist, and such a row is
        # the body's (it is cut from below, not stripped). Faded by the arm's
        # share instead, the bottom of freya_awakened's fist (arm 0.2-0.4)
        # stayed half on the thigh and tore at 22x.
        arm_share = W[:, armkind].sum(axis=1)
        f = ramp * (arm_share >= 0.2)
        # The arm's LAYER, not its tight skin: a bracer over the forearm is a
        # layer beyond the skin, and stripped under a bracer left on the hips
        # thor's forearm split along the bracer's edge.
        zone = ctx["layer"] & (d < GRIP_REACH * height) & ~moved & (f * body_share > 0.005)
        if zone.any():
            g = W[zone]
            g[:, lower] *= (1.0 - f[zone])[:, None]
            g /= np.maximum(g.sum(axis=1, keepdims=True), 1e-9)
            W[zone] = g
            moved |= zone
            cut_rows |= zone & (f >= 0.5)
            grip_rows += int(zone.sum())
    n = int(moved.sum())
    if not n:
        return 0, moved, moved
    rows = np.flatnonzero(moved)
    top = np.argsort(-W[rows], axis=1)[:, :K]
    wt = np.take_along_axis(W[rows], top, axis=1)
    wt /= np.maximum(wt.sum(axis=1, keepdims=True), 1e-9)
    top[wt <= 0] = top[:, :1].repeat(K, axis=1)[wt <= 0]
    char.joint_indices[rows] = top.astype(char.joint_indices.dtype)
    char.joint_weights[rows] = wt.astype(char.joint_weights.dtype)
    if verbose and grip_rows:
        print(f"    weapon: {grip_rows:,} rows of the grip lose their share of the body")
    # Cut from everything the body owns: the non-arm surface, and any row of
    # the arm's layer the body still holds most of (a skirt the layer took),
    # read off the NEW weights and never a row re-weighted here — cut_seam
    # asks only that a face hold one `against` row, and a stripped forearm
    # row read off its old weights cut the forearm from itself.
    against = (~ctx["layer"] | (W[:, ~armkind].sum(axis=1) > 0.5)) & ~moved
    cut = character.cut_seam(char, cut_rows, ji_before, jw_before, against=against)
    if verbose and cut:
        print(f"    weapon: the border with the body cut, {cut:,} vertices doubled")
    return n, moved, cut_rows


def lod_transfer(base, moved, lod, height, verbose=True, cut_rows=None):
    """The LOD takes the base's verdict, as skirt_pass.transfer: every LOD
    vertex whose nearest base vertex (within 1% of the height) was re-bound
    takes that vertex's new weights (joints matched by name), and its border
    with everything the body owns is cut the same way."""
    from scipy.spatial import cKDTree
    n0 = len(moved)
    lod_index = {leaf(j): i for i, j in enumerate(lod.joints)}
    remap = np.array([lod_index.get(leaf(j), -1) for j in base.joints])
    d, idx = cKDTree(base.points[:n0].astype(np.float64)).query(lod.points.astype(np.float64))
    take = moved[idx] & (d < 0.01 * height)
    if not take.any():
        return 0
    K = lod.joint_indices.shape[1]
    ji_before, jw_before = lod.joint_indices.copy(), lod.joint_weights.copy()
    for v in np.flatnonzero(take):
        ji = remap[base.joint_indices[idx[v]]]
        jw = base.joint_weights[idx[v]].astype(np.float64)
        ok = (ji >= 0) & (jw > 0)
        if not ok.any():
            take[v] = False
            continue
        ji, jw = ji[ok][:K], jw[ok][:K]
        jw = jw / jw.sum()
        row_i = np.full(K, ji[0], dtype=lod.joint_indices.dtype)
        row_w = np.zeros(K, dtype=lod.joint_weights.dtype)
        row_i[:len(ji)] = ji
        row_w[:len(jw)] = jw
        lod.joint_indices[v] = row_i
        lod.joint_weights[v] = row_w
    P = lod.points.astype(np.float64)
    layer, _, armkind = character._arm_masks(lod, P, radius=ARM_RADIUS)
    Wn = dense_weights(lod)
    against = (~layer | (Wn[:, ~armkind].sum(axis=1) > 0.5)) & ~take
    cut_take = take if cut_rows is None else take & cut_rows[idx]
    cut = character.cut_seam(lod, cut_take, ji_before, jw_before, against=against)
    if verbose and cut:
        print(f"    weapon: the LOD's border with the body cut, {cut:,} vertices doubled")
    return int(take.sum())


def process(name, bundle=BUNDLE, out_dir=None, in_place=False, verbose=True):
    """Re-weights one family's base and LOD. Writes into `out_dir` or, with
    `in_place`, over the bundle's files. Returns a summary dict."""
    src = bundle / f"{name}.usdz"
    base = character.read_usdz(src)
    if not base.skinned:
        if verbose:
            print(f"  {name}: unrigged; nothing to do")
        return dict(name=name, pieces=[], before=1.0, after=1.0, moved=0)
    pieces, ctx = measure(base, name, bundle)
    summary = dict(name=name, pieces=pieces, before=max((p["stretch"] for p in pieces), default=1.0))
    summary["left"] = ctx.get("left", {})
    if verbose:
        for r in ctx["refused"]:
            print(f"    {r}")
        for hand, why in ctx.get("left", {}).items():
            print(f"    LEFT FOR A HUMAN, {hand}: {why}")
        for p in pieces:
            print(f"    held: {len(p['verts']):,} v at {p['hand_name']} (touching {p['touching']}), "
                  f"arm {p['arm_share']:.0%}, worst stretch {p['stretch']:.2f} at {p['worst_at']}, "
                  f"off the hand up to {p['off_hand']:.0%}, the body's up to {p['body_max']:.0%} on {p['body_rows']} rows{' — TWO-HANDED' if p['two_handed'] else ''}"
                  f"{' (second cut)' if p.get('second_cut') else ''}{'' if p['faulty'] else ' — rigid already'}")
    height = ctx["height"]
    n, moved, cut_rows = rebind(base, pieces, ctx, verbose)
    summary["moved"] = n
    if n == 0:
        if verbose:
            print(f"  {name}: nothing to move")
        summary["after"] = summary["before"]
        return summary
    # After: the same frames, the same edges (the cut's copies included).
    edges = unique_edges(base.faces)
    worst, at = worst_stretch(base.points.astype(np.float64), base.joint_indices, base.joint_weights,
                              ctx["mats"], edges, height)
    touched = np.zeros(len(base.points), bool)
    for p in pieces:
        if p.get("faulty"):
            touched[p["verts"]] = True
    t = touched[edges[:, 0]] | touched[edges[:, 1]]
    summary["after"] = float(worst[t].max()) if t.any() else 1.0
    targets = []
    if in_place:
        targets.append((base, src))
    else:
        out_dir = Path(out_dir)
        out_dir.mkdir(parents=True, exist_ok=True)
        targets.append((base, out_dir / src.name))
    lod_path = bundle / f"{name}_lod.usdz"
    if lod_path.exists():
        lod = character.read_usdz(lod_path)
        m = lod_transfer(base, moved, lod, height, verbose, cut_rows=cut_rows)
        summary["lod_moved"] = m
        if m:
            targets.append((lod, lod_path if in_place else Path(out_dir) / lod_path.name))
    for char, dst in targets:
        tmp = Path(tempfile.mkdtemp()) / dst.name
        character.write_usdz(char, tmp)
        shutil.move(str(tmp), str(dst))
        if verbose:
            print(f"  {dst}: written")
    if verbose:
        print(f"  {name}: {n:,} vertices bound to the hand; worst stretch on them {summary['before']:.2f} -> "
              f"{summary['after']:.2f}; LOD {summary.get('lod_moved', 0):,} vertices")
    return summary


class _quiet:
    def __init__(self, on):
        self.on = on

    def __enter__(self):
        if self.on:
            import io, contextlib
            self._cm = contextlib.redirect_stdout(io.StringIO())
            self._cm.__enter__()

    def __exit__(self, *a):
        if self.on:
            self._cm.__exit__(*a)


def mask_board(name, out, bundle=BUNDLE, size=620):
    """The base at rest, front / side / back, the pieces the pass would bind
    to a hand in RED (second-cut pieces in ORANGE), held things already rigid
    in GREEN, the rest in grey: what it takes, drawn on the figure."""
    import io
    from PIL import Image
    import preview
    base = character.read_usdz(bundle / f"{name}.usdz")
    pieces, ctx = measure(base, name, bundle)
    val = np.zeros(len(base.points))
    for p in pieces:
        val[p["verts"]] = (0.9 if p.get("second_cut") else 0.6) if p.get("faulty") else 0.3
    pal = np.zeros((4, 256, 3), np.float32)
    pal[:] = 0.72
    pal[:, 60:110] = (0.25, 0.75, 0.3)
    pal[:, 130:180] = (0.9, 0.12, 0.1)
    pal[:, 205:250] = (1.0, 0.55, 0.0)
    buf = io.BytesIO()
    Image.fromarray((pal * 255).astype(np.uint8)).save(buf, "PNG")
    c = character.Character(name=name, points=base.points, faces=base.faces,
                            uvs=np.c_[val, np.full(len(val), 0.5)].astype(np.float32), joints=[],
                            parents=np.zeros(0, int), bind=np.zeros((0, 4, 4)), rest_local=np.zeros((0, 4, 4)),
                            joint_indices=None, joint_weights=None,
                            textures=[character.Texture("base_color", buf.getvalue(), "png")])
    row, _ = preview.render(c, size=size, views=("front", "side", "back"), layout=False,
                            label=f"{name}: red = bound to the hand, orange = second cut, green = rigid already")
    row.save(out, quality=90)
    return row


def survey_line(name, bundle=BUNDLE):
    base = character.read_usdz(bundle / f"{name}.usdz")
    if not base.skinned:
        return dict(name=name, worst=1.0, moved=0, total=len(base.points), hands="-", two=False, at=None,
                    second=False, clean=0, unrigged=True)
    pieces, ctx = measure(base, name, bundle)
    faulty = [p for p in pieces if p.get("faulty")]
    worst = max((p["stretch"] for p in faulty), default=1.0)
    total = len(base.points)
    moved = rebind(base, pieces, ctx, verbose=False)[0] if faulty else 0   # every row the pass changes
    hands = ",".join(sorted({p["hand_name"] for p in faulty})) or "-"
    two = any(p["two_handed"] for p in faulty)
    at = next((p["worst_at"] for p in faulty if p["stretch"] == worst), None)
    second = any(p.get("second_cut") for p in faulty)
    left = ctx.get("left", {})
    left_worst = max((p["stretch"] for p in pieces if p["hand_name"] in left and "stretch" in p), default=1.0)
    return dict(name=name, worst=worst, moved=moved, total=total, hands=hands, two=two, at=at,
                second=second, clean=len(pieces) - len(faulty), left=left, left_worst=left_worst)


def self_test():
    """A clean control moves nothing or near-nothing (athena_awakened's spear
    is rigid to her hand already)."""
    ok = True
    for name in CLEAN_CONTROLS:
        if not (BUNDLE / f"{name}.usdz").exists():
            continue
        line = survey_line(name)
        frac = line["moved"] / line["total"]
        good = frac < 0.005 and line["worst"] < 2.0
        print(f"self-test {name}: {line['moved']} of {line['total']} vertices would move, worst {line['worst']:.2f} "
              f"-> {'ok' if good else 'FAIL'}")
        ok &= good
    return ok


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("names", nargs="*")
    ap.add_argument("--survey", action="store_true")
    ap.add_argument("--out", help="write re-weighted <name>.usdz and <name>_lod.usdz here (a scratch dir)")
    ap.add_argument("--in-place", action="store_true", help="overwrite the bundle's base and LOD")
    ap.add_argument("--self-test", action="store_true")
    ap.add_argument("--mask-board", metavar="DIR", help="draw what the pass takes on each named family into DIR")
    ap.add_argument("--bundle", default=str(BUNDLE), help="read the shipped files from here (a snapshot)")
    ap.add_argument("--include-excluded", action="store_true", help="do not skip CAPE_EXCLUDE families")
    ap.add_argument("--all", action="store_true", help="apply to every judged family (character.WEAPON_FAMILIES), in place")
    args = ap.parse_args()
    bundle = Path(args.bundle)
    if args.self_test:
        sys.exit(0 if self_test() else 1)
    if args.survey:
        names = args.names or [n for n in families() if (bundle / f"{n}.usdz").exists()]
        rows = []
        for name in names:
            try:
                rows.append(survey_line(name, bundle))
                rows[-1]["excluded"] = excluded(name) and not args.include_excluded
            except Exception as exc:  # noqa: BLE001
                rows.append(dict(name=name, error=str(exc)[:80]))
            r = rows[-1]
            print(f"  {name}: {r.get('worst', 0):.2f}" if "worst" in r else f"  {name}: {r}", file=sys.stderr)
        rows.sort(key=lambda r: -max(r.get("worst", 0), r.get("left_worst", 0)))
        lines = [f"{'family':24s} {'worst':>7s} {'moved':>7s} {'of':>7s}  {'hand':22s} {'2H':3s} {'worst at':22s} note"]
        for r in rows:
            if r.get("skipped"):
                lines.append(f"{r['name']:24s} {'-':>7s} {'-':>7s} {'-':>7s}  {'-':22s} {'-':3s} {'-':22s} "
                             f"skipped: winged/tailed (CAPE_EXCLUDE)")
            elif "error" in r:
                lines.append(f"{r['name']:24s} error {r['error']}")
            else:
                at = f"{r['at'][0]}:{r['at'][1]}" if r["at"] else "-"
                note = "second cut (welded to the legs)" if r["second"] else ""
                if r.get("left"):
                    note = (note + "; " if note else "") + "LEFT FOR A HUMAN " + ", ".join(
                        f"{h} ({r['left_worst']:.1f}x: {w})" for h, w in r["left"].items())
                if r.get("unrigged"):
                    note = "unrigged (moved procedurally)"
                if r.get("excluded"):
                    note = (note + "; " if note else "") + "winged/tailed (CAPE_EXCLUDE): measured, not applied"
                lines.append(f"{r['name']:24s} {r['worst']:7.2f} {r['moved']:7d} {r['total']:7d}  {r['hands']:22s} "
                             f"{'YES' if r['two'] else '':3s} {at:22s} {note}")
        text = "\n".join(lines)
        print(text)
        if not args.names:
            SURVEY_OUT.parent.mkdir(parents=True, exist_ok=True)
            SURVEY_OUT.write_text(text + "\n")
            print(f"-> {SURVEY_OUT}")
        return
    if args.mask_board:
        for name in args.names:
            out = Path(args.mask_board) / f"{name}_mask.jpg"
            out.parent.mkdir(parents=True, exist_ok=True)
            mask_board(name, out, bundle)
            print("->", out)
        return
    if args.all:
        args.names = list(character.WEAPON_FAMILIES)
        args.in_place = True
    if not args.names:
        ap.error("name families, or --all, --survey or --self-test")
    if not args.out and not args.in_place:
        ap.error("--out DIR (a scratch dir) or --in-place")
    for name in args.names:
        # A judged name was judged with its wings on the board: not skipped.
        if excluded(name) and not args.include_excluded and name not in character.WEAPON_FAMILIES:
            print(f"== {name}: winged or tailed (character.CAPE_EXCLUDE); skipped")
            continue
        print(f"== {name}")
        process(name, bundle=bundle, out_dir=args.out, in_place=args.in_place)


if __name__ == "__main__":
    main()
