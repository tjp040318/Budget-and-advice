"""The cloth optimiser (2026-09-24): the skinning weights of a garment that
TEARS — a kilt, a tunic, a chiton, a robe that Meshy's auto-rig welded to the
hand resting on it in the A-pose — are SOLVED for, against every clip the
family ships, instead of moved by a rule.

    python3 tools/cloth_opt.py --survey hoplite mercury        # what it would free (no solve)
    python3 tools/cloth_opt.py hoplite --out DIR --board B     # solve; base + LOD into DIR, boards into B
    python3 tools/cloth_opt.py --self-test                     # the clean controls are refused
    python3 tools/cloth_opt.py hoplite --in-place              # into the bundle (the owner's call)
    python3 tools/cloth_opt.py --all                           # every judged family (CLOTH_FAMILIES), in place

About 3.5 minutes a family on one core (the base about two, its LOD solved on
its own about one, the measure the rest); 5 with the boards.

WHAT THE EARLIER PASSES LEARNED. The skirt pass (character.reweight_skirt)
gives an arm's cloth to the NEAREST body bone by rule: three wins, ten
families shredded (cloth welded along a sleeve comes off in slivers; a
floor-length robe given to ONE leg tears between the legs). The robe ring
(character.reweight_robe) hung the lower garment on eight spring chains; the
lower garment stopped flying on seven of nine and every one then failed ABOVE
the hips, and the simulation itself added nothing. Both chose a vertex's
weights by a rule about where it IS; neither looked at what the weights DO.

THE OPTIONS WEIGHED (research, 2026-09-23):
  A. Bounded biharmonic weights (Jacobson, Baran, Popovic & Sorkine 2011):
     smooth weights under bounds and a partition of unity. Blind to the
     animation (no pose in the energy), and it re-derives the whole skin.
     A smoothness prior, not the fix.
  B. Delta Mush / Direct Delta Mush (Mancewicz et al. 2014; Le & Lewis
     2019): the film cure for LBS artefacts, but a deformer SceneKit's
     four-influence linear skinner cannot run. Not shippable.
  C. SSDR (Le & Deng 2012, "Smooth Skinning Decomposition with Rigid
     Bones"): per-vertex non-negative least squares for weights (sum to
     one, at most K) against EXAMPLE POSES. Its weight step is the right
     tool, but the only example poses here are the broken ones.
  D. Elasticity-inspired weights (Kavan & Sorkine 2012, "Elasticity-Inspired
     Deformers for Character Articulation"): choose LBS weights so the
     skinned mesh approximates an elastic deformation over sampled poses of
     the skeleton — an energy, not a target shape. CHOSEN, with C's
     constraints and the elastic energy that suits CLOTH: edge springs
     (Liu et al. 2013, Projective Dynamics — Bouaziz et al. 2014), which
     resist stretching and not bending (ARAP's rotations would stiffen a
     skirt into a board).

THE SOLVE. Unknowns: the weights of every free point on its candidate joints.
LBS is LINEAR in the weights (posed point = Y_i(f) w_i, Y the rest point
carried by each joint at frame f), so with the edge directions of a local
step held fixed the energy is a sparse quadratic: projective dynamics with
the weights as the unknowns. The constraints (w >= 0, sum 1, candidates only,
then at most K=4) are an ADMM split (Overby, Brown, Li & Narain 2017, "ADMM ⊇
Projective Dynamics"): a CG solve, a projection onto the simplex per point.
128 frames solved (16 per clip, eight clips), 256 measured, so every number
includes frames the solve never saw. Deterministic: same bytes of weights
run to run (checked on hades).

What had to be learned, each by a board or a number:
  1. Plain least squares is the FAULT ITSELF. It prefers a stretch spread
     over many edges to one concentrated in a few, so its optimum is the
     smooth sheet from the hip to the hand (the hoplite: energy -77%, the
     sheet unchanged on the board). The energy is ROBUST — a Huber loss on
     each edge's RMS stretch (`HUBER`, by iteratively reweighted least
     squares), which prices a crack by its length and not its square.
  2. From the shipped weights the solve does not leave the hand: a panel
     riding the fist is a local minimum (moved halfway it stretches the
     tear line as much as it relaxes it). It STARTS from the body's reading
     — the forearm and hand taken out of every free point (the upper arm
     only below the elbow), a point the arm held wholly given its
     neighbours' weights by diffusion — and the arm joints stay candidates,
     so the solve can put an arm back where that lowers the energy.
  3. The fist is a DECISION, not a blend (`ARM_SNAP`): after the solve a
     point keeps the forearm and hand wholly or not at all (a fifth of a
     raised hand on a kilt is a strip 20 cm long), and the faces between a
     fist and the garment still stretched past `CUT_AT` are cut
     (character.cut_seam, the FIST as the moved side, so a copied vertex
     never takes a half-hand blend: that was a 78x spike on nezha).
  4. What stays fixed: the arm's own skin where the arm holds at least half
     (a garment pressed against the fist is measured as its skin too), but
     not the fist's skin that the rigger blended with the thigh it rested
     on (fixed, the freed fingers tore from it); a THING HELD
     (weapon_pass.held_pieces, faulty or not: mercury's caduceus, freed as
     cloth, broke at the waist); a free piece with nothing on the body to
     hang from (a sword or a cuff); a cape_/robe_ joint's cloth (the game
     simulates it).
  5. Legs and arms are capsules (their measured skin): a free point that a
     clip carries inside one gets a target on its surface, so the garment
     never goes rigid-and-wrong through a thigh. Penetrating (point, frame)
     pairs fell on every family solved.
  6. The energy is a GUARD: a family whose solve leaves the robust energy
     over `ENERGY_MAX` of the shipped one is refused and nothing is
     written. The clean controls (athena_awakened, tyr) are refused so.
  7. The LOD (the mesh the battle draws) is SOLVED ON ITS OWN by the same
     energy (`LOD_MODE`). The base's weights copied point by point
     (skirt_pass.transfer's way, `--lod transfer`) tore nezha's LOD along the
     free region's border, where its decimated faces bridge the tunic and
     the fist differently; solved, it came out cleaner than the base.

The FREE points: every point off the arm's skin that the forearm or the hand
holds over `ARM_CAUSE` (or the upper arm, below the elbow) — the cause — plus
the stretched points (an edge past `STRETCH`) near them, grown `GROW` rings;
only regions holding an edge past `SEED` are solved. The mesh is welded by
position first (Meshy splits it at UV seams), so a UV seam never opens.

Judge a family on its boards (`--board`: the three worst frames before |
after, the LOD, both hands close up, the free mask), never on the count
alone.

THE VERDICTS (2026-09-24; every board looked at; the numbers are the FINAL
meshes, the cut included, over the edges touching a changed row, 256 frames
of eight clips: worst edge, the worst clip's p99, edges past 4x summed over
the clips; base / LOD):
  APPLIED (CLOTH_FAMILIES):
    hoplite   32.0 -> 7.7, p99 7.7 -> 2.8, >4x 2,992 -> 92 / LOD 17.0 -> 4.2, 1,100 -> 17.
              The kilt no longer rises to the fists; a scrap a few cm across
              stays on the right fist.
    hades     31.9 -> 6.0, 10.2 -> 2.7, 2,581 -> 33 / LOD 17.7 -> 3.7, 1,040 -> 0. Clean.
    osiris    24.7 -> 5.7, 9.8 -> 2.7, 1,928 -> 22 / LOD 21.1 -> 3.9, 675 -> 0.
              The linen sheet from hip to fist is gone; crook and flail intact.
    ptah      11.8 -> 6.7, 5.9 -> 2.9, 698 -> 84 / LOD 13.2 -> 3.7, 294 -> 0.
              The robe's flap is gone; thin slivers at the side in the ultimate.
    mercury   39.5 -> 24.6, 12.1 -> 5.8, 5,038 -> 1,077 / LOD 32.1 -> 14.5, 2,023 -> 365.
              The tunic wedge from arm to knee is gone and the pouch stays on the
              belt; what is left is the CAPE's own shredding (another fault) and
              two specks by the raised hand.
    nezha     15.7 -> 5.7, 8.2 -> 2.4, 2,967 -> 16 / LOD 13.8 -> 3.4, 1,163 -> 0.
              The tunic sheet to the baton hand is gone; a red sash sliver at the
              left fist.
  NOT APPLIED, a human's call (better than shipped on the board, not clean):
    athena    the robe's sheets are gone, but small white flaps stay at the hip
              seam and the LOD keeps one thin strand from the spear hand to the
              hip (55x on a single edge).
    hathor    the skirt sheets are gone, but cloth tufts ride the sistrum fist
              and a side panel stands off the leg like a stick.
  REFUSED by the energy guard (the solve could not lower it): heimdall
    (78% of the mesh free; the cloak IS the arms'), aphrodite, set, serqet —
    the ten the robe ring failed on are the same class: cloth lying ON the arm
    along its length, which no weighting parts without tearing.
  The clean controls athena_awakened and tyr are refused (energies 106 -> 87,
  200 -> 171): nothing written.
  Tried and taken out, each by a board: a start ON the fist for pieces the
  hand holds wholly (RIGID_HAND, off at 1.01: it left tufts of hathor's skirt
  and scraps of the hoplite's kilt on the fists and saved nothing that the
  guard had not refused); the arm's LAYER as the fixed arm (it took kilt by
  the fist); the upper arm's share taken off above the elbow (holes at the
  hoplite's shoulders); a held thing grown by a ring (it took nezha's fist)."""
import argparse, io, contextlib, shutil, sys, tempfile, time
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
import character  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]
BUNDLE = ROOT / "Pantheon" / "Resources" / "Models"

CLIPS = ("attack_basic", "attack_heavy", "ultimate", "victory", "idle", "walk", "hit_react", "death")
SAMPLES = 32            # frames per clip MEASURED
SOLVE_SAMPLES = 16      # frames per clip SOLVED on (a subset of other frames: the rest are held out)
STRETCH = 1.6           # an edge past this over the clips marks its vertices
SEED = 2.0              # ... and a free region must hold an edge past this (a real tear), or it is left
GROW = 4                # rings the free set grows through non-limb vertices
CAND_RINGS = 3          # a point may take the joints of its neighbours within this many rings
ARM_SEAM = 0.02         # the weight of an edge from the garment to the arm's own skin
CUT_AT = 1.8            # a seam edge to the arm still stretched past this after the solve is cut
MU = 0.02               # pull to the original weights (per unit of the edge term)
SIGMA = 0.05            # weight smoothness to the welded neighbours
LAMBDA = 4.0            # penetration target strength (per unit of the vertex's edge term)
COMPRESS = 0.33         # a compressed edge pulls at this share
SWEEPS = 80             # ADMM iterations before the influences are pruned (30 more after)
HUBER = 0.5             # an edge's RMS stretch past this share of its length is priced linearly (IRLS)
REWEIGHT = 10           # sweeps between the robust reweights
START = "body"          # where the solve starts (see optimise)
RIGID_HAND = 1.01       # a point the forearm and hand hold this wholly starts on them (a held thing)
RIGID_REACH = 0.15      # ... and that reach this far (a share of the height) from every wrist
ENERGY_MAX = 0.75       # a solve that leaves the robust energy over this share of the shipped one is refused
LOD_MODE = "solve"     # the LOD: its own solve ("solve"), or the base's weights point by point ("transfer")
ARM_SNAP = 0.5          # after the solve a point keeps the forearm and hand only if they hold this much
ARM_FIXED = "skin"      # the arm's own surface held fixed: its LAYER (fingers and all), not the tight skin
RHO = 1.0               # the ADMM penalty (per unit of the point's edge stiffness)
ARM_RADIUS = {"arm": 0.10, "forearm": 0.10, "hand": 0.06, "grip": 0.06}
K = 4                   # influences per vertex (SceneKit's skinner)
LEG_RADIUS = 0.09       # the legs' own skin lies within this share of the height of the bone (the robe ring's)
ARM_CAUSE = 0.05        # a seed holds this share of a forearm or a hand (or of an upper arm below the elbow)

CLOTH_FAMILIES = ("hoplite", "osiris", "hades", "ptah", "mercury", "nezha")
                        # judged on their before/after boards (2026-09-24): the ones --all applies
CLEAN_CONTROLS = ("athena_awakened", "tyr")
                        # clean in the audit: the energy guard must refuse them (nothing to gain)


def leaf(p):
    return p.split("/")[-1]


# --- the clips ---------------------------------------------------------------

def clip_mats(base, name, bundle, samples):
    """[(clip, frame)], (F,J,4,4) skinning matrices (row-vector convention:
    posed = [x,1] @ M), for every shipped clip at `samples` frames."""
    inv_bind = np.linalg.inv(base.bind)
    tags, mats = [], []
    for clip_name in CLIPS:
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
            tags.append((clip_name, int(f)))
            mats.append(np.einsum("jab,jbc->jac", inv_bind, world))
    return tags, np.array(mats)


def dense_weights(ji, jw, J):
    n = len(ji)
    W = np.zeros((n, J))
    np.add.at(W, (np.repeat(np.arange(n), ji.shape[1]), ji.reshape(-1)), jw.reshape(-1).astype(np.float64))
    return W


def posed(X, W, mats):
    """(F,n,3) LBS posed points of rest points X (n,3) with dense weights W."""
    xh = np.c_[X, np.ones(len(X))]
    out = np.empty((len(mats), len(X), 3))
    for f, m in enumerate(mats):
        blend = np.einsum("nj,jab->nab", W, m)
        out[f] = np.einsum("na,nab->nb", xh, blend)[:, :3]
    return out


def edge_stretch(Pf, X, edges, height):
    """Per frame and edge: posed/rest length (edges under 0.1% of the height read 1)."""
    L0 = np.linalg.norm(X[edges[:, 0]] - X[edges[:, 1]], axis=1)
    L = np.linalg.norm(Pf[:, edges[:, 0]] - Pf[:, edges[:, 1]], axis=2)
    s = L / np.maximum(L0, 1e-12)
    s[:, L0 < 1e-3 * height] = 1.0
    return s


# --- the masks ---------------------------------------------------------------

class Welded:
    """The base welded by position: unique points, each vertex's point, the
    welded edges (unique, a<b), the neighbours as CSR, dense weights per point."""

    def __init__(self, base):
        P = base.points.astype(np.float64)
        key, canon, e = character._welded_edges(P, base.faces)
        e = np.unique(np.sort(e, axis=1), axis=0)
        self.X, self.canon, self.edges = key.astype(np.float64), canon, e
        J = len(base.joints)
        self.J = J
        Wv = dense_weights(base.joint_indices, base.joint_weights, J)
        C = len(key)
        W = np.zeros((C, J))
        cnt = np.zeros(C)
        np.add.at(W, canon, Wv)
        np.add.at(cnt, canon, 1)
        self.W = W / cnt[:, None]
        from scipy.sparse import coo_matrix
        A = coo_matrix((np.ones(2 * len(e)), (np.r_[e[:, 0], e[:, 1]], np.r_[e[:, 1], e[:, 0]])), shape=(C, C)).tocsr()
        self.adj = A
        self.n = C


def ring_grow(adj, mask, rings, through):
    m = mask.copy()
    for _ in range(rings):
        m = m | ((adj @ m.astype(float)) > 0) & through
    return m


def limb_masks(base, wd):
    """On the welded points: the arms' own skin (capped radius, as the weapon
    pass), the legs' own surface (inward stop), and per-joint kinds."""
    P = wd.X
    height = float(P[:, 1].max() - P[:, 1].min())
    # _arm_masks and _limb_surface read a Character's points; give them the welded one.
    faces = wd.canon[base.faces]
    faces = faces[(faces[:, 0] != faces[:, 1]) & (faces[:, 1] != faces[:, 2]) & (faces[:, 0] != faces[:, 2])]
    shim = character.Character(name="w", points=P.astype(np.float32), faces=faces, uvs=None, joints=base.joints,
                               parents=base.parents, bind=base.bind, rest_local=base.rest_local,
                               joint_indices=None, joint_weights=None)
    normals = character.vertex_normals(P, faces).astype(np.float64)
    layer, skin, armkind = character._arm_masks(shim, P, normals, radius=ARM_RADIUS)
    leafs = [leaf(j) for j in base.joints]
    kind = [character._bone_kind(l) for l in leafs]
    jpos = np.array([base.bind[i][3, :3] for i in range(len(leafs))])
    legs = np.zeros(len(P), bool)
    segs = []
    for j, p in enumerate(base.parents):
        if p >= 0 and kind[j] in ("leg", "foot"):
            s = character._limb_surface(P, normals, jpos[p], jpos[j], reach=0.25 * height, gap=0.006 * height,
                                        slack=1.2, inward_stop=True)
            s &= seg_dist(P, jpos[p], jpos[j])[0] <= LEG_RADIUS * height
            legs |= s
            # the capsule's radius: the leg's own surface, its 60th percentile distance from the bone
            a, b = jpos[p], jpos[j]
            d = seg_dist(P[s], a, b)[0] if s.any() else np.array([0.05 * height])
            segs.append((p, j, float(np.percentile(d, 60))))
    # The arm's capsules as well (the upper arm and the forearm): a sleeve or
    # a drape freed from the arm must not let the arm through it.
    for j, p in enumerate(base.parents):
        if p >= 0 and kind[j] in ("forearm", "hand") and kind[p] in ("arm", "forearm"):
            a, b = jpos[p], jpos[j]
            m = skin & (seg_dist(P, a, b)[0] <= 0.10 * height) & (seg_dist(P, a, b)[1] > 0) & (seg_dist(P, a, b)[1] < 1)
            d = seg_dist(P[m], a, b)[0] if m.any() else np.array([0.035 * height])
            segs.append((p, j, float(np.percentile(d, 60))))
    # The WELD: the arm's skin that the forearm and the hand own (the fist a
    # garment was fused to). An edge from the garment to it is cheap and may
    # be cut; an edge to the upper arm's skin is a sleeve's junction and is
    # neither (cut, it opened holes at the hoplite's shoulders).
    Wd = wd.W
    low = np.array([k == "forearm" or k.startswith("hand") for k in kind])
    weld = (layer if ARM_FIXED == "layer" else skin) & (Wd[:, low].sum(axis=1) >= 0.5)
    return dict(skin=skin, weld=weld, layer=layer, armkind=armkind, legs=legs, segs=segs, kind=kind, leafs=leafs,
                jpos=jpos, height=height, faces=faces)


def seg_dist(P, a, b):
    ab = b - a
    t = ((P - a) @ ab) / max(float(ab @ ab), 1e-12)
    tc = np.clip(t, 0.0, 1.0)
    c = a + tc[:, None] * ab
    return np.linalg.norm(P - c, axis=1), t, c


# --- the solve ---------------------------------------------------------------

def simplex_project(V, mask):
    """Rows of V projected onto the probability simplex restricted to `mask`."""
    big = -1e9
    U = np.where(mask, V, big)
    s = -np.sort(-U, axis=1)
    cs = np.cumsum(np.where(s > big / 2, s, 0.0), axis=1) - 1.0
    k = np.arange(1, V.shape[1] + 1)
    cond = (s - cs / k > 0) & (s > big / 2)
    r = cond.sum(axis=1)
    r = np.maximum(r, 1)
    theta = cs[np.arange(len(V)), r - 1] / r
    out = np.maximum(U - theta[:, None], 0.0)
    return np.where(mask, out, 0.0)


def optimise(base, name, bundle, verbose=True, sweeps=SWEEPS, report=None):
    """Returns (new dense welded weights, context). Changes nothing on `base`."""
    t0 = time.time()
    wd = Welded(base)
    lm = limb_masks(base, wd)
    height = lm["height"]
    tags_m, mats_m = clip_mats(base, name, bundle, SAMPLES)
    X = wd.X
    J = wd.J
    Pm = posed(X, wd.W, mats_m)
    S = edge_stretch(Pm, X, wd.edges, height)
    worst = S.max(axis=0)
    # Meshy's figure is ONE shell: under a kilt there is no thigh, the kilt IS
    # the leg's surface there. So only the ARM's skin is fixed by geometry;
    # everything else is fixed by not being free.
    # ... and only where the arm holds at least half: the hand's measured skin
    # takes the garment pressed against the fist too (nezha's tunic at 0.31
    # hand, fixed so, tore from its freed neighbours into a 78x spike).
    fixed_limb = lm[ARM_FIXED] & (wd.W[:, lm["armkind"]].sum(axis=1) >= 0.5)
    # The fist's own skin that the rigger blended with the thigh it rested on
    # (nezha's 0.77 hand / 0.23 thigh) is solved too: fixed so, the freed
    # fingers beside it tore from it at 28x. (The HAND's skin only: the
    # forearm's share of the hips is the elbow's rest by the flank, which the
    # weapon pass takes off on a ramp.)
    handj = np.array([k.startswith("hand") for k in lm["kind"]])
    lowerj = np.array([k in ("hips", "upleg", "leg", "foot", "toebase") for k in lm["kind"]])
    fist_weld = lm[ARM_FIXED] & (wd.W[:, handj].sum(axis=1) >= 0.5) & (wd.W[:, lowerj].sum(axis=1) > 0.02)
    fixed_limb &= ~fist_weld
    leafs = lm["leafs"]
    cloth_j = np.array([l.startswith(character.CLOTH_PREFIXES) for l in leafs])
    head_j = np.array([k in ("head", "head_end", "headfront", "neck") or k.startswith("head") or "eye" in k or "jaw" in k
                       for k in lm["kind"]])
    on_cloth_joint = wd.W[:, cloth_j].sum(axis=1) > 1e-4 if cloth_j.any() else np.zeros(wd.n, bool)
    # A thing HELD (a staff, a sword, a caduceus: weapon_pass.held_pieces, the
    # weapon pass's own finding of what a hand holds, faulty or not) is rigid
    # and the hand's; freed as cloth, mercury's caduceus was given to the
    # body and broke into pieces at the waist.
    held_things = np.zeros(wd.n, bool)
    try:
        import weapon_pass
        with contextlib.redirect_stdout(io.StringIO()):
            pieces, _ = weapon_pass.held_pieces(base)
        for pc in pieces:
            held_things[wd.canon[pc["verts"]]] = True
    except Exception as exc:  # noqa: BLE001
        if verbose:
            print(f"    (held things not read: {exc})")
    # (Not grown: grown a ring, it took nezha's fist skin that the rigger
    # blended with his thigh, and the fist beside it, solved rigid, tore from
    # it at 28x.)
    lm["held_things"] = held_things
    movable = ~fixed_limb & ~on_cloth_joint & ~held_things
    # The CAUSE: cloth off the arm's skin that an arm holds — a forearm or a
    # hand, or an upper arm below the elbow (above it, the arm's share is the
    # shoulder's own blend, and the armpit stretches on every clean figure).
    kinds = lm["kind"]
    lowarm = np.array([k == "forearm" or k.startswith("hand") for k in kinds])
    uparm = np.array([k == "arm" for k in kinds])
    elbow_y = min((lm["jpos"][j][1] for j, k in enumerate(kinds) if k == "forearm"), default=0.0)
    held = (wd.W[:, lowarm].sum(axis=1) > ARM_CAUSE) | ((wd.W[:, uparm].sum(axis=1) > ARM_CAUSE) & (X[:, 1] < elbow_y))
    held &= ~(lm[ARM_FIXED] & ~fist_weld & (wd.W[:, lm["armkind"]].sum(axis=1) >= 0.5))
    hot_e = worst > STRETCH
    hot = np.zeros(wd.n, bool)
    hot[wd.edges[hot_e, 0]] = True
    hot[wd.edges[hot_e, 1]] = True
    # Free: all the held cloth (a panel that rides the hand is not stretched
    # INSIDE itself; only its junction with the body is, so the stretch alone
    # finds the tear line and leaves the panel on the hand), with the
    # stretched cloth near it, grown GROW rings for room.
    held_c = held & movable
    near_held = ring_grow(wd.adj, held_c, 2 * GROW, movable)
    free = held_c | (hot & movable & near_held)
    free = ring_grow(wd.adj, free, GROW, movable)
    # A free piece with nothing on the BODY to hang from — its only fixed
    # neighbours are the arm's skin — is a thing held (a sword the weapon
    # pass did not read as one: heimdall's blade, solved as cloth from the
    # body's start, broke off at the fist) or a cuff: it keeps its weights.
    from scipy.sparse.csgraph import connected_components
    sub = wd.adj[free][:, free]
    ncomp, lab = connected_components(sub, directed=False)
    fidx0 = np.flatnonzero(free)
    ee = wd.edges
    cross = free[ee[:, 0]] ^ free[ee[:, 1]]
    fin = np.where(free[ee[cross, 0]], ee[cross, 0], ee[cross, 1])
    fout = np.where(free[ee[cross, 0]], ee[cross, 1], ee[cross, 0])
    lab_full = -np.ones(wd.n, int)
    lab_full[fidx0] = lab
    arm_fixed = fixed_limb | held_things
    body_touch = np.zeros(ncomp, bool)
    np.logical_or.at(body_touch, lab_full[fin], ~arm_fixed[fout])
    orphan = ~body_touch[lab]
    if verbose and orphan.any():
        print(f"    kept as shipped: {int(orphan.sum()):,} free points in {len(np.unique(lab[orphan]))} piece(s) "
              f"that hang from the arm alone")
    free[fidx0[orphan]] = False
    # keep only the free components holding a real tear
    sub = wd.adj[free][:, free]
    ncomp, lab = connected_components(sub, directed=False)
    fidx = np.flatnonzero(free)
    seed_v = np.zeros(wd.n, bool)
    se = worst > SEED
    seed_v[wd.edges[se, 0]] = True
    seed_v[wd.edges[se, 1]] = True
    keep_c = np.zeros(ncomp, bool)
    keep_c[np.unique(lab[seed_v[fidx]])] = True
    comp_size = np.bincount(lab, minlength=ncomp)
    keep_c &= comp_size >= 8
    free[fidx[~keep_c[lab]]] = False
    fidx = np.flatnonzero(free)
    ctx = dict(wd=wd, lm=lm, tags=tags_m, mats=mats_m, before=S, free=free, height=height)
    if verbose:
        print(f"  {name}: {wd.n:,} welded points, {len(tags_m)} frames measured; free {len(fidx):,} "
              f"({100 * len(fidx) / wd.n:.1f}%); worst edge {worst.max():.1f}x")
    if len(fidx) == 0:
        ctx["W"] = wd.W.copy()
        return wd.W.copy(), ctx
    n = len(fidx)
    loc = -np.ones(wd.n, int)
    loc[fidx] = np.arange(n)
    # Candidates.
    near = free.copy()
    Wsupp = wd.W > 1e-4
    cand = Wsupp[fidx].copy()
    reach = np.zeros(wd.n, bool)
    Rv = wd.adj.copy()
    # joints on the neighbours within CAND_RINGS rings: propagate support
    supp = Wsupp.astype(float)
    for _ in range(CAND_RINGS):
        supp = supp + wd.adj @ supp
    cand |= supp[fidx] > 0
    base_kinds = ("hips", "spine", "spine01", "spine02", "spine1", "spine2", "spine3", "upleg", "leg")
    chain = np.array([k in base_kinds or k.startswith("spine") for k in lm["kind"]])
    cand |= chain[None, :]
    cand &= ~cloth_j[None, :] & ~head_j[None, :]
    # a vertex's own current joints stay allowed (a head-owned vertex keeps its head)
    cand |= Wsupp[fidx]
    # The solve's frames: every other measured frame per clip.
    tags_s, mats_s = clip_mats(base, name, bundle, SOLVE_SAMPLES)
    ctx["solve_frames"] = len(mats_s)
    if sweeps == 0:
        ctx["W"] = wd.W.copy()
        return wd.W.copy(), ctx
    # The start. The energy is not convex (the edge directions, the robust
    # weights), and from the SHIPPED weights the panel that rides the hand is
    # a local minimum: moved halfway to the hips it stretches the tear line
    # as much as it relaxes it, and the solve never leaves (the hoplite's
    # kilt: 0.40 hand before, 0.41 after, while a start with the arm taken
    # out scored 12% lower on the same energy). So the solve starts from the
    # BODY's reading of the garment — every free point's arm share taken
    # out and renormalised, a point the arm held wholly given its body-held
    # neighbours' mean by diffusion — and the arm joints stay candidates, so
    # the solve puts an arm back wherever it lowers the energy (a sleeve).
    # (The upper arm's share is taken only below the elbow: above it the
    # share is the shoulder's own blend, and taken out it tore the tunic
    # from the upper arm at the hoplite's shoulders.)
    armj = lowarm | uparm
    Wb = wd.W[fidx].copy()
    fist_f = fist_weld[fidx]
    keep_fist = Wb[fist_f].copy()
    keep_fist[:, ~lowarm] = 0.0
    Wb[:, lowarm] = 0.0
    below = X[fidx, 1] < elbow_y
    Wb[np.ix_(below, uparm)] = 0.0
    tot = Wb.sum(axis=1)
    known = tot > 0.5
    Wb[known] /= tot[known, None]
    Wb[~known] = 0.0
    Wb[fist_f] = keep_fist / np.maximum(keep_fist.sum(axis=1, keepdims=True), 1e-12)   # the fist starts as the fist
    known[fist_f] = True
    # A point the forearm and the hand hold wholly (RIGID_HAND) starts where
    # it is: it moves rigidly with the fist in every clip, which is a thing
    # held (heimdall's blade, fused into the body's piece so no piece test
    # finds it, broke off at the fist from the body's start), and the solve
    # will not carry a rigid thing across on its own.
    # Only a piece that REACHES past the fingertips (a point of it over
    # `RIGID_REACH` of the height from every wrist) is such a thing: the
    # hoplite's kilt, wholly the hand's for a few centimetres beside the
    # fist, started there, stayed there and rode both raised fists as scraps.
    whole = wd.W[:, lowarm].sum(axis=1) >= RIGID_HAND
    wrists = [lm["jpos"][j] for j, k in enumerate(kinds) if k == "hand"]
    far = np.min([np.linalg.norm(X - w, axis=1) for w in wrists], axis=0) > RIGID_REACH * height if wrists else \
        np.zeros(wd.n, bool)
    pool = free & whole
    sub2 = wd.adj[pool][:, pool]
    _, lab2 = connected_components(sub2, directed=False)
    pidx = np.flatnonzero(pool)
    reach_lab = np.unique(lab2[far[pidx]])
    rigid_full = np.zeros(wd.n, bool)
    rigid_full[pidx[np.isin(lab2, reach_lab)]] = True
    rigid = rigid_full[fidx]
    ctx["rigid_start"] = int(rigid.sum())
    if verbose and rigid.any():
        print(f"    {int(rigid.sum()):,} points start on the fist: pieces the hand holds wholly that reach past the fingers")
    Wb[rigid] = wd.W[fidx][rigid]
    known[rigid] = True
    Wfull = wd.W.copy()
    Wfull[fidx] = Wb
    kn_full = np.ones(wd.n, bool)
    kn_full[fidx[~known]] = False
    kn_full &= ~(wd.W[:, armj].sum(axis=1) > 0.5) | free   # a fixed arm-owned point is no donor
    deg_all = np.asarray(wd.adj.sum(axis=1)).ravel()
    unk = fidx[~known]
    for _ in range(300):
        donors = Wfull * kn_full[:, None]
        cnt = wd.adj @ kn_full.astype(float)
        avg = (wd.adj @ donors) / np.maximum(cnt[:, None], 1e-9)
        got = cnt[unk] > 0
        Wfull[unk[got]] = avg[unk[got]]
        kn_full[unk[got]] = True
    Wb = Wfull[fidx] * cand
    empty = Wb.sum(axis=1) < 1e-6
    Wb[empty] = wd.W[fidx][empty] * cand[empty]
    Wb /= np.maximum(Wb.sum(axis=1, keepdims=True), 1e-12)
    ctx["start"] = START
    W_start = Wb if START == "body" else None
    Wf, info = admm_solve(wd, lm, free, cand, mats_s, height, sweeps=sweeps, verbose=verbose, t0=t0, start=W_start)
    Wnew = wd.W.copy()
    Wnew[fidx] = Wf
    ctx.update(info)
    ctx["W"] = Wnew
    ctx["time"] = time.time() - t0
    return Wnew, ctx


def admm_solve(wd, lm, free, cand, mats, height, sweeps=SWEEPS, verbose=True, t0=0.0, start=None):
    """The global solve. Unknowns: the weights of every free point on its
    candidate joints (one vector). Energy, with the edge directions of the
    local step held fixed: sum over region edges e=(a,b) and frames f of
    w_e h_e |(p_a(f) - p_b(f)) - d_e(f)|^2 / F, with p = Y w + c (centred: c
    the point under its ORIGINAL weights, so the quadratic is conditioned on
    the weight DIFFERENCES and not on where the figure stands), plus the pull
    to the original weights, the smoothness to the neighbours' weights and
    the limb targets.

    h_e is the ROBUST part (iteratively reweighted least squares, a Huber
    loss on each edge's RMS stretch over the frames): 1 while the edge
    stretches under `HUBER` of its length, `HUBER / stretch` past it. A plain
    least-squares elastic energy was tried first and is the fault itself —
    it prefers a stretch SPREAD over many edges to one concentrated in a
    few, so its optimum is the smooth sheet from the hip to the hand (the
    hoplite's kilt: energy down 77%, the sheet unchanged on the board). The
    Huber loss prices a crack by its length, not by its square, so the
    panel lets go of the hand along the cheapest line — the seam to the
    arm's skin — which is then cut.

    The simplex (w >= 0, sum 1, candidates only) is the ADMM split (Overby,
    Brown, Li & Narain 2017, "ADMM ⊇ Projective Dynamics"): x-step a sparse
    SPD solve by preconditioned CG, z-step a projection per point, the
    multiplier its running residual. Deterministic."""
    from scipy.sparse import coo_matrix, diags
    from scipy.sparse.linalg import cg
    X, J = wd.X, wd.J
    fidx = np.flatnonzero(free)
    n = len(fidx)
    loc = -np.ones(wd.n, int)
    loc[fidx] = np.arange(n)
    F = len(mats)
    W0 = wd.W[fidx] * cand
    W0 /= np.maximum(W0.sum(axis=1, keepdims=True), 1e-12)
    xh = np.c_[X[fidx], np.ones(n)]
    Y = np.einsum("na,fjab->fnjb", xh, mats[:, :, :, :3])                  # (F,n,J,3)
    Pall = posed(X, wd.W, mats)                                            # (F,N,3) shipped
    c = np.einsum("fnjb,nj->fnb", Y, W0)                                   # the centre: the original (masked) pose
    Y = ((Y - c[:, :, None, :]) * cand[None, :, :, None]).astype(np.float32)
    # Region edges.
    e = wd.edges
    E = e[free[e[:, 0]] | free[e[:, 1]]]
    L0 = np.linalg.norm(X[E[:, 0]] - X[E[:, 1]], axis=1)
    keep = L0 > 1e-3 * height
    E, L0 = E[keep], L0[keep]
    skin = lm["weld"]
    seam = (skin[E[:, 0]] & ~free[E[:, 0]]) | (skin[E[:, 1]] & ~free[E[:, 1]])
    Lref = np.maximum(L0, 0.004 * height)
    we = (1.0 / Lref ** 2) * np.where(seam, ARM_SEAM, 1.0) / F
    fa, fb = free[E[:, 0]], free[E[:, 1]]
    nE = len(E)
    var = -np.ones((n, J), int)
    var[cand] = np.arange(int(cand.sum()))
    nv = int(cand.sum())
    ia_all, ib_all = loc[E[:, 0]], loc[E[:, 1]]
    # Per-edge blocks, once: B_aa = sum_f Ya'Ya, B_bb, B_ab (zero where an end is fixed).
    Baa = np.zeros((nE, J, J), np.float32)
    Bbb = np.zeros((nE, J, J), np.float32)
    Bab = np.zeros((nE, J, J), np.float32)
    CH = 1000
    for s0 in range(0, nE, CH):
        sl = slice(s0, s0 + CH)
        m0, m1 = fa[sl], fb[sl]
        ya = Y[:, np.maximum(ia_all[sl], 0)] * m0[None, :, None, None]
        yb = Y[:, np.maximum(ib_all[sl], 0)] * m1[None, :, None, None]
        Baa[sl] = np.einsum("fmja,fmka->mjk", ya, ya, optimize=True)
        Bbb[sl] = np.einsum("fmja,fmka->mjk", yb, yb, optimize=True)
        Bab[sl] = np.einsum("fmja,fmka->mjk", ya, yb, optimize=True)
    del ya, yb
    Jd = np.arange(J)

    def assemble(h):
        """The sparse matrix of the edge term with robust weights h (E,)."""
        k = (we * h)[:, None, None]
        rows, cols, vals = [], [], []

        def put(ia, ib, M, m):
            va, vb = var[ia[m]], var[ib[m]]
            M = M[m]
            R = np.broadcast_to(va[:, :, None], M.shape)
            C = np.broadcast_to(vb[:, None, :], M.shape)
            ok = (R >= 0) & (C >= 0) & (M != 0)
            rows.append(R[ok]); cols.append(C[ok]); vals.append(M[ok].astype(np.float64))
        put(ia_all, ia_all, Baa * k, fa)
        put(ib_all, ib_all, Bbb * k, fb)
        both = fa & fb
        put(ia_all, ib_all, -Bab * k, both)
        put(ib_all, ia_all, -np.transpose(Bab, (0, 2, 1)) * k, both)
        return coo_matrix((np.concatenate(rows), (np.concatenate(cols) * 0 + np.concatenate(rows), np.concatenate(cols))),
                          shape=(nv, nv)).tocsr() if False else \
            coo_matrix((np.concatenate(vals), (np.concatenate(rows), np.concatenate(cols))), shape=(nv, nv)).tocsr()

    # The stiffness per unit weight of each point's own edge term (h = 1).
    diag_scale = np.zeros(n)
    tr_a = np.trace(Baa, axis1=1, axis2=2) * we
    tr_b = np.trace(Bbb, axis1=1, axis2=2) * we
    np.add.at(diag_scale, ia_all[fa], tr_a[fa])
    np.add.at(diag_scale, ib_all[fb], tr_b[fb])
    ncand = cand.sum(axis=1)
    scale = np.maximum(diag_scale / np.maximum(ncand, 1), 1e-9)
    mu = MU * scale
    rho = RHO * scale

    def diag_block(dvals):
        """(n,J) diagonal entries -> sparse."""
        m = cand & (dvals != 0)
        v = var[m]
        return coo_matrix((dvals[m], (v, v)), shape=(nv, nv)).tocsr()

    # Smoothness: free-free edges as a graph Laplacian on the common joints;
    # free-fixed edges pull toward the fixed neighbour's weights.
    ff = E[fa & fb]
    rows, cols, vals = [], [], []
    if len(ff):
        ia, ib = loc[ff[:, 0]], loc[ff[:, 1]]
        sg = SIGMA * 0.5 * (scale[ia] + scale[ib])
        common = cand[ia] & cand[ib]
        for (p, q) in ((ia, ib), (ib, ia)):
            m = common
            vp, vq = var[p][m], var[q][m]
            sv = np.broadcast_to(sg[:, None], m.shape)[m]
            rows += [vp, vp]; cols += [vp, vq]; vals += [sv, -sv]
    Asm = coo_matrix((np.concatenate(vals), (np.concatenate(rows), np.concatenate(cols))), shape=(nv, nv)).tocsr() \
        if rows else None
    mix = fa ^ fb
    fx = E[mix]
    fx_free = np.where(fa[mix], fx[:, 0], fx[:, 1])
    fx_fixed = np.where(fa[mix], fx[:, 1], fx[:, 0])
    Dfx = np.zeros((n, J))
    Wfx = np.zeros((n, J))
    sfx = SIGMA * scale[loc[fx_free]]
    np.add.at(Dfx, loc[fx_free], sfx[:, None] * cand[loc[fx_free]])
    np.add.at(Wfx, loc[fx_free], sfx[:, None] * wd.W[fx_fixed] * cand[loc[fx_free]])
    Areg = diag_block((mu + rho)[:, None] * cand + Dfx)
    if Asm is not None:
        Areg = Areg + Asm

    # Limb capsules.
    segs = lm["segs"]
    jpos = lm["jpos"]
    jposh = np.c_[jpos, np.ones(len(jpos))]
    allowed = np.stack([np.minimum(seg_dist(X[fidx], jpos[a], jpos[b])[0], r) for a, b, r in segs], axis=1) \
        if segs else np.zeros((n, 0))
    ends = [(np.einsum("a,fab->fb", jposh[a], mats[:, a])[:, :3], np.einsum("a,fab->fb", jposh[b], mats[:, b])[:, :3])
            for a, b, _ in segs]

    def positions(W):
        P = Pall.copy()
        P[:, fidx] = np.einsum("fnja,nj->fna", Y, W) + c
        return P

    def limb_targets(P):
        out = []
        for s, (pa, pb) in enumerate(ends):
            ab = pb - pa
            rel = P[:, fidx] - pa[:, None]
            tt = np.einsum("fna,fa->fn", rel, ab) / np.maximum((ab * ab).sum(axis=1), 1e-12)[:, None]
            cc = pa[:, None] + np.clip(tt, 0, 1)[..., None] * ab[:, None]
            rv = P[:, fidx] - cc
            dist = np.linalg.norm(rv, axis=2)
            lim = allowed[None, :, s]
            bad = (tt > 0.08) & (tt < 1.0) & (dist < 0.92 * lim)
            if bad.any():
                fi, vi = np.nonzero(bad)
                q = cc[fi, vi] + rv[fi, vi] / np.maximum(dist[fi, vi, None], 1e-9) * lim[0, vi, None]
                out.append((fi, vi, q))
        if not out:
            return None
        return (np.concatenate([o[0] for o in out]), np.concatenate([o[1] for o in out]),
                np.concatenate([o[2] for o in out]))

    def limb_terms(lt):
        if lt is None:
            return None, np.zeros((n, J))
        fi, vi, q = lt
        lam = LAMBDA * scale[vi] / F
        Yp = Y[fi, vi].astype(np.float64)
        M = np.zeros((n, J, J))
        np.add.at(M, vi, np.einsum("pja,pka->pjk", Yp, Yp) * lam[:, None, None])
        g = np.zeros((n, J))
        np.add.at(g, vi, np.einsum("pja,pa->pj", Yp, q - c[fi, vi]) * lam[:, None])
        R = np.broadcast_to(var[:, :, None], M.shape)
        C = np.broadcast_to(var[:, None, :], M.shape)
        ok = (R >= 0) & (C >= 0) & (M != 0)
        return coo_matrix((M[ok], (R[ok], C[ok])), shape=(nv, nv)).tocsr(), g

    def edge_rhs_and_stretch(P, h):
        rhs = np.zeros((n, J))
        rms = np.zeros(nE)
        for s0 in range(0, nE, CH):
            sl = slice(s0, s0 + CH)
            Es, ws, l0 = E[sl], we[sl] * h[sl], L0[sl]
            d = P[:, Es[:, 0]] - P[:, Es[:, 1]]
            L = np.linalg.norm(d, axis=2)
            rms[sl] = np.sqrt((((L - l0[None]) / Lref[sl][None]) ** 2).mean(axis=0))
            u = d / np.maximum(L[..., None], 1e-12)
            proj = u * l0[None, :, None]
            tgt = np.where((L < l0[None, :])[..., None], d + COMPRESS * (proj - d), proj)
            ca = np.where(fa[sl][None, :, None], c[:, np.maximum(ia_all[sl], 0)], P[:, Es[:, 0]])
            cb = np.where(fb[sl][None, :, None], c[:, np.maximum(ib_all[sl], 0)], P[:, Es[:, 1]])
            r = tgt - (ca - cb)
            for side, sgn in ((0, 1.0), (1, -1.0)):
                m = (fa if side == 0 else fb)[sl]
                if not m.any():
                    continue
                iv = (ia_all if side == 0 else ib_all)[sl][m]
                g = np.einsum("fmja,fma->mj", Y[:, iv], r[:, m], optimize=True) * (sgn * ws[m])[:, None]
                np.add.at(rhs, iv, g)
        return rhs, rms

    rtol_kw = "rtol" if _cg_has_rtol() else "tol"
    z = W0.copy() if start is None else start.copy()
    lam_ = np.zeros((n, J))
    xw = z.copy()
    anchor = z.copy()        # the pull is to the START (the body's reading, or the shipped weights)
    mask = cand.copy()
    h = np.ones(nE)
    Aedge = assemble(h)
    Mlimb, glimb = None, np.zeros((n, J))
    info = dict(history=[])
    total = sweeps + 30
    npen = 0
    for it in range(total):
        if it == sweeps:
            # At most K influences: the top K of z, and the solve goes on on that support.
            top = np.argsort(-z, axis=1)[:, :K]
            supp = np.zeros_like(mask)
            np.put_along_axis(supp, top, True, axis=1)
            supp &= (z > 1e-4) | (Jd[None, :] == top[:, :1])
            # ... and the fist is a DECISION, not a blend: a point that the
            # forearm and the hand hold under ARM_SNAP loses them. A fifth of
            # a raised hand on a kilt is a strip 20 cm long (the hoplite's
            # right side, 0.72 thigh / 0.20 hand after the solve).
            lowj = np.array([k == "forearm" or k.startswith("hand") for k in lm["kind"]])
            low_share = (z * lowj[None, :]).sum(axis=1)
            snap = low_share < ARM_SNAP
            supp[np.ix_(snap, lowj)] = False
            # and a point that keeps the fist keeps ONLY the fist (0.6 hand,
            # 0.4 thigh drifted back to 0.31 hand on nezha while the solve
            # went on): the share is 0 or 1 from here, and the seam between
            # the two is cut.
            supp[np.ix_(~snap, ~lowj)] = False
            none = ~supp.any(axis=1)
            supp[none] = cand[none] & ~lowj[None, :]
            none = ~supp.any(axis=1)
            supp[none] = cand[none]
            mask = supp
            z = simplex_project(z, mask)
            lam_ = lam_ * mask
        P = positions(z)
        rhs_e, rms = edge_rhs_and_stretch(P, h)
        if it % REWEIGHT == 0 and it > 0 and HUBER is not None:
            h = np.where(rms > HUBER, HUBER / np.maximum(rms, 1e-9), 1.0)
            Aedge = assemble(h)
            rhs_e, rms = edge_rhs_and_stretch(P, h)
        if it % 5 == 0:
            lt = limb_targets(P)
            npen = 0 if lt is None else len(lt[0])
            Mlimb, glimb = limb_terms(lt)
        A = Aedge + Areg if Mlimb is None else Aedge + Areg + Mlimb
        dinv = 1.0 / np.maximum(A.diagonal(), 1e-12)
        rhs = rhs_e + mu[:, None] * anchor + Wfx + glimb + rho[:, None] * (z - lam_)
        v, _ = cg(A, rhs[cand], x0=xw[cand], M=diags(dinv), maxiter=80, **{rtol_kw: 1e-7})
        xw = np.zeros((n, J))
        xw[cand] = v
        z_old = z
        z = simplex_project(xw + lam_, mask)
        lam_ = lam_ + xw - z
        if verbose and (it % 25 == 0 or it == total - 1):
            d = P[:, E[:, 0]] - P[:, E[:, 1]]
            st = (np.linalg.norm(d, axis=2) / L0[None]).max(axis=0)
            inner = ~seam
            info["history"].append((it, float(st[inner].max()), float(np.percentile(st[inner], 99)), npen))
            print(f"    admm {it:3d}: garment worst {st[inner].max():.2f}, p99 {np.percentile(st[inner], 99):.2f}, "
                  f"edges>2x {int((st[inner] > 2).sum())}, seam>2x {int((st[seam] > 2).sum())}, limb pairs {npen}, "
                  f"robust {int((h < 1).sum())}, moved {np.abs(z - z_old).max():.4f}, {time.time() - t0:.0f}s")
    info["seam_edges"] = E[seam]
    # The robust energy of the result and of the shipped weights, on the solve's frames.
    def robust(Wd):
        P = positions(Wd)
        L = np.linalg.norm(P[:, E[:, 0]] - P[:, E[:, 1]], axis=2)
        r = np.sqrt((((L - L0[None]) / Lref[None]) ** 2).mean(axis=0))
        hub = np.where(r < HUBER, r * r, 2 * HUBER * r - HUBER * HUBER) * np.where(seam, ARM_SEAM, 1.0)
        return float(hub.sum())
    info["energy_shipped"] = robust(W0)
    info["energy_solved"] = robust(z)
    if verbose:
        print(f"    robust energy: shipped {info['energy_shipped']:.1f} -> solved {info['energy_solved']:.1f}")
    return z, info


def _cg_has_rtol():
    import inspect
    from scipy.sparse.linalg import cg
    return "rtol" in inspect.signature(cg).parameters


# --- applying ----------------------------------------------------------------

def to_sparse(W, dtype_i, dtype_w):
    top = np.argsort(-W, axis=1)[:, :K]
    wt = np.take_along_axis(W, top, axis=1)
    wt /= np.maximum(wt.sum(axis=1, keepdims=True), 1e-12)
    top = np.where(wt > 0, top, top[:, :1])
    return top.astype(dtype_i), wt.astype(dtype_w)


def stretch_cut(char, moved, ji0, jw0, mats, height, lowarm_j):
    """Cuts `char` where a re-weighted vertex meets a vertex the forearm or
    the hand owns (after the pass, and not re-weighted) along an edge that
    still stretches past CUT_AT over the frames — the weld of a garment to a
    fist, which no weighting can keep whole. The same rule on the base and
    on the LOD (whose decimated faces bridge the kilt and the fist
    differently, so it is measured on its own edges). Returns (vertices
    doubled, the rows cut round)."""
    n0 = len(moved)
    W = dense_weights(char.joint_indices, char.joint_weights, len(char.joints))
    # The fist's side: every point the forearm and the hand hold at least
    # half of AFTER the pass (a free finger included); the garment's side:
    # a re-weighted point they hold under half.
    against = W[:, lowarm_j].sum(axis=1) >= 0.5
    garment = moved & ~against
    f = char.faces
    e = np.vstack([f[:, [0, 1]], f[:, [1, 2]], f[:, [2, 0]]])
    e = np.unique(np.sort(e, axis=1), axis=0)
    cross = (garment[e[:, 0]] & against[e[:, 1]]) | (garment[e[:, 1]] & against[e[:, 0]])
    moved = garment
    ec = e[cross]
    if not len(ec):
        return 0, np.zeros(n0, bool)
    X = char.points.astype(np.float64)
    P = posed(X, W, mats)
    st = edge_stretch(P, X, ec, height).max(axis=0)
    bad = ec[st > CUT_AT]
    cut_rows = np.zeros(len(char.points), bool)
    for c in (0, 1):
        cut_rows[bad[:, c][moved[bad[:, c]]]] = True
    if not cut_rows.any():
        return 0, cut_rows[:n0]
    # cut_seam splits a face by MAJORITY between its `moved` set and the rest
    # and gives a doubled vertex the mean of the majority's weights. Called
    # with the garment as `moved`, a face of one garment point, one fist
    # point and one body point went to the "rest" and the garment's copy took
    # the mean of the fist and the body — a third of a raised hand, and a
    # 78x spike on nezha's tunic. So the FIST is `moved` (a face with two
    # fist points goes with the fist; any other goes with the garment and
    # the body, whose weights agree), and `against` narrows the cut to faces
    # holding a garment point on a stretched edge.
    return character.cut_seam(char, against, ji0, jw0, against=cut_rows), cut_rows[:n0]


def apply(base, Wnew, ctx, name, bundle, verbose=True):
    """Writes the welded solution into `base` (every split copy of a point
    alike), then cuts the weld (stretch_cut). Returns the moved mask over
    the original vertices."""
    wd = ctx["wd"]
    free = ctx["free"]
    n0 = len(base.points)
    ji0, jw0 = base.joint_indices.copy(), base.joint_weights.copy()
    rows = np.flatnonzero(free[wd.canon])
    ji, jw = to_sparse(Wnew[wd.canon[rows]], base.joint_indices.dtype, base.joint_weights.dtype)
    base.joint_indices[rows] = ji
    base.joint_weights[rows] = jw
    moved = np.zeros(n0, bool)
    moved[rows] = True
    low = np.array([k == "forearm" or k.startswith("hand") for k in ctx["lm"]["kind"]])
    cut, cut_rows = stretch_cut(base, moved, ji0, jw0, ctx["mats"], ctx["height"], low)
    if verbose:
        print(f"    weld: {int(cut_rows.sum())} rows still stretched past {CUT_AT}x to a fist; cut, {cut:,} vertices doubled")
    return moved


def lod_transfer(base, moved, lod, height, name, bundle):
    """The LOD takes the base's result: every LOD vertex whose nearest base
    vertex (within 1% of the height) was re-weighted takes its weights
    (joints by leaf name), then the LOD's own weld is cut by the same rule."""
    from scipy.spatial import cKDTree
    n0 = len(moved)
    lod_index = {leaf(j): i for i, j in enumerate(lod.joints)}
    remap = np.array([lod_index.get(leaf(j), -1) for j in base.joints])
    d, idx = cKDTree(base.points[:n0].astype(np.float64)).query(lod.points.astype(np.float64))
    take = moved[idx] & (d < 0.01 * height)
    Kl = lod.joint_indices.shape[1]
    ji_before, jw_before = lod.joint_indices.copy(), lod.joint_weights.copy()
    for v in np.flatnonzero(take):
        ji = remap[base.joint_indices[idx[v]]]
        jw = base.joint_weights[idx[v]].astype(np.float64)
        ok = (ji >= 0) & (jw > 0)
        if not ok.any():
            take[v] = False
            continue
        ji, jw = ji[ok][:Kl], jw[ok][:Kl]
        jw = jw / jw.sum()
        ri = np.full(Kl, ji[0], dtype=lod.joint_indices.dtype)
        rw = np.zeros(Kl, dtype=lod.joint_weights.dtype)
        ri[:len(ji)] = ji
        rw[:len(jw)] = jw
        lod.joint_indices[v] = ri
        lod.joint_weights[v] = rw
    _, mats = clip_mats(lod, name, bundle, SAMPLES)
    kinds = [character._bone_kind(leaf(j)) for j in lod.joints]
    low = np.array([k == "forearm" or k.startswith("hand") for k in kinds])
    cut, _ = stretch_cut(lod, take, ji_before, jw_before, mats, height, low)
    return int(take.sum()), cut


# --- measuring ---------------------------------------------------------------

def per_clip(tags, S, emask):
    """{clip: (max, p99 of the per-edge worst, edges past 2x)} over the masked edges."""
    out = {}
    clips = [t[0] for t in tags]
    for c in dict.fromkeys(clips):
        rows = np.array([k for k, t in enumerate(clips) if t == c])
        w = S[rows][:, emask].max(axis=0) if emask.any() else np.ones(1)
        out[c] = (float(w.max()), float(np.percentile(w, 99)), int((w > 2.0).sum()))
    return out


def penetration(Pf, X, free_idx, segs, jpos, mats):
    """Share of (free point, frame) pairs inside 0.8 of the allowed leg radius."""
    if not segs or not len(free_idx):
        return 0.0, 0
    jposh = np.c_[jpos, np.ones(len(jpos))]
    bad = np.zeros((len(mats), len(free_idx)), bool)
    for a, b, r in segs:
        rho0 = seg_dist(X[free_idx], jpos[a], jpos[b])[0]
        lim = np.minimum(rho0, r)
        pa = np.einsum("a,fab->fb", jposh[a], mats[:, a])[:, :3]
        pb = np.einsum("a,fab->fb", jposh[b], mats[:, b])[:, :3]
        ab = pb - pa
        rel = Pf[:, free_idx] - pa[:, None]
        tt = np.einsum("fna,fa->fn", rel, ab) / np.maximum((ab * ab).sum(axis=1), 1e-12)[:, None]
        c = pa[:, None] + np.clip(tt, 0, 1)[..., None] * ab[:, None]
        dist = np.linalg.norm(Pf[:, free_idx] - c, axis=2)
        bad |= (tt > 0.08) & (tt < 1.0) & (dist < 0.8 * lim[None])
    return float(bad.mean()), int(bad.any(axis=0).sum())


def measure_result(ctx, Wnew, name, verbose=True):
    wd, tags, mats = ctx["wd"], ctx["tags"], ctx["mats"]
    free = ctx["free"]
    e = wd.edges
    region = free[e[:, 0]] | free[e[:, 1]]
    # the seam edges to the arm are judged apart: after the solve they are cut
    seam = np.zeros(len(e), bool)
    skin = ctx["lm"]["weld"]
    seam = region & ((skin[e[:, 0]] & ~free[e[:, 0]]) | (skin[e[:, 1]] & ~free[e[:, 1]]))
    inner = region & ~seam
    Sb = ctx["before"]
    Pa = posed(wd.X, Wnew, mats)
    Sa = edge_stretch(Pa, wd.X, e, ctx["height"])
    fidx = np.flatnonzero(free)
    Pb = posed(wd.X, wd.W, mats)
    lm = ctx["lm"]
    pb = penetration(Pb, wd.X, fidx, lm["segs"], lm["jpos"], mats)
    pa = penetration(Pa, wd.X, fidx, lm["segs"], lm["jpos"], mats)
    res = dict(before=per_clip(tags, Sb, inner), after=per_clip(tags, Sa, inner),
               seam_before=per_clip(tags, Sb, seam), seam_after=per_clip(tags, Sa, seam),
               pen_before=pb, pen_after=pa, free=int(free.sum()), n=wd.n, Sa=Sa, Sb=Sb, inner=inner, seam=seam)
    # the worst frames, before, for the boards
    wb = Sb[:, inner].max(axis=1) if inner.any() else np.ones(len(tags))
    res["worst_frames"] = [tags[k] for k in np.argsort(-wb)]
    if verbose:
        print(f"  {name}: free {res['free']:,} of {res['n']:,}; penetrating (pairs, points) "
              f"{pb[0]:.4f}/{pb[1]} -> {pa[0]:.4f}/{pa[1]}")
        print(f"    (the solve, welded, BEFORE the cut; the final mesh is measured below)")
        print(f"    {'clip':13s} {'garment max':>18s} {'p99':>13s} {'edges>2x':>13s}   {'arm seam max':>16s}")
        for c in res["before"]:
            b, a = res["before"][c], res["after"][c]
            sb, sa = res["seam_before"][c], res["seam_after"][c]
            print(f"    {c:13s} {b[0]:8.2f} -> {a[0]:6.2f} {b[1]:5.2f} -> {a[1]:5.2f} {b[2]:5d} -> {a[2]:5d}   "
                  f"{sb[0]:6.2f} -> {sa[0]:6.2f}")
    return res


# --- boards ------------------------------------------------------------------

def board(name, after_dir, frames, out, bundle=BUNDLE, size=420, lod=False):
    """Rows of (before | after) at the given (clip, frame)s, front and side."""
    from PIL import Image, ImageDraw
    import base_plus_clip as bpc
    import preview
    rows = []
    for clip, f in frames:
        cp = bundle / f"{name}_{clip}.usdz"
        if clip == "idle" and not cp.exists():
            cp = bundle / f"{name}_idle_combat.usdz"
        pair = []
        for src in (bundle, Path(after_dir)):
            bp = src / f"{name}{'_lod' if lod else ''}.usdz"
            with contextlib.redirect_stdout(io.StringIO()):
                r = _render(bp, cp, f, size)
            pair.append(r)
        w = sum(p.width for p in pair) + 8
        h = max(p.height for p in pair)
        row = Image.new("RGB", (w, h), (30, 30, 34))
        row.paste(pair[0], (0, 0))
        row.paste(pair[1], (pair[0].width + 8, 0))
        d = ImageDraw.Draw(row)
        d.rectangle((0, 0, 360, 18), fill=(20, 20, 24))
        d.text((4, 3), f"{name}{' LOD' if lod else ''} {clip} f{f}: BEFORE (left) | AFTER (right)", fill=(255, 220, 120))
        rows.append(row)
    W = max(r.width for r in rows)
    sheet = Image.new("RGB", (W, sum(r.height for r in rows)), (30, 30, 34))
    y = 0
    for r in rows:
        sheet.paste(r, (0, y))
        y += r.height
    sheet.save(out, quality=85)
    return out


def hand_board(name, after_dir, frames, out, bundle=BUNDLE, size=300, radius=0.13):
    """Close-ups of both hands, BEFORE | AFTER, at the given frames: the mesh
    within `radius` of the height of each posed hand joint, rendered alone
    (so it fills the panel). A pass that tears, bends or empties a hand shows
    here before it shows anywhere else."""
    from PIL import Image, ImageDraw
    import preview
    rows = []
    for clip, f in frames:
        cp = bundle / f"{name}_{clip}.usdz"
        if clip == "idle" and not cp.exists():
            cp = bundle / f"{name}_idle_combat.usdz"
        cells = []
        for side in ("Left", "Right"):
            for src in (bundle, Path(after_dir)):
                base = character.read_usdz(src / f"{name}.usdz")
                pts, world = _posed_points(base, cp, f)
                hj = [i for i, j in enumerate(base.joints) if character._bone_kind(leaf(j)) == "hand"
                      and leaf(j).lower().startswith(side.lower())]
                if not hj:
                    continue
                c0 = world[hj[0]][3, :3]
                h = float(base.points[:, 1].max() - base.points[:, 1].min())
                near = np.linalg.norm(pts - c0, axis=1) < radius * h
                fm = near[base.faces].all(axis=1)
                if not fm.any():
                    continue
                used = np.unique(base.faces[fm])
                remap = -np.ones(len(pts), int)
                remap[used] = np.arange(len(used))
                sub = pts[used] - np.array([0.0, pts[used][:, 1].min(), 0.0])   # on the ground, so it fills the panel
                pc = character.Character(name=name, points=sub.astype(np.float32), faces=remap[base.faces[fm]],
                                         uvs=None if base.uvs is None else base.uvs[used],
                                         joints=[], parents=np.zeros(0, int), bind=np.zeros((0, 4, 4)),
                                         rest_local=np.zeros((0, 4, 4)), joint_indices=None, joint_weights=None,
                                         anim=None, textures=base.textures)
                with contextlib.redirect_stdout(io.StringIO()):
                    r, _ = preview.render(pc, size=size, views=("front", "side"), layout=False, label="")
                d = ImageDraw.Draw(r)
                d.text((4, 3), f"{side} hand {'before' if src == bundle else 'AFTER'} {clip} f{f}", fill=(200, 30, 30))
                cells.append(r)
        if cells:
            w = sum(c.width for c in cells) + 4 * len(cells)
            row = Image.new("RGB", (w, max(c.height for c in cells)), (30, 30, 34))
            x = 0
            for c in cells:
                row.paste(c, (x, 0))
                x += c.width + 4
            rows.append(row)
    W = max(r.width for r in rows)
    sheet = Image.new("RGB", (W, sum(r.height for r in rows)), (30, 30, 34))
    y = 0
    for r in rows:
        sheet.paste(r, (0, y))
        y += r.height
    sheet.save(out, quality=85)
    return out


def _posed_points(base, clip_path, f):
    clip = character.read_usdz(clip_path)
    cmap = {leaf(j): i for i, j in enumerate(clip.joints)}
    local = np.array(base.rest_local, dtype=np.float64)
    a = clip.anim
    f = min(f, len(a["T"]) - 1)
    for bi, bj in enumerate(base.joints):
        ci = cmap.get(leaf(bj))
        if ci is not None:
            local[bi] = character.trs(a["T"][f, ci], a["R"][f, ci], a["S"][f, ci])
    world = character.world_from_local(local, base.parents)
    return base.skinned_points(world), world


def _render(base_path, clip_path, f, size):
    import preview
    base = character.read_usdz(base_path)
    clip = character.read_usdz(clip_path)
    cmap = {leaf(j): i for i, j in enumerate(clip.joints)}
    local = np.array(base.rest_local, dtype=np.float64)
    a = clip.anim
    f = min(f, len(a["T"]) - 1)
    for bi, bj in enumerate(base.joints):
        ci = cmap.get(leaf(bj))
        if ci is not None:
            local[bi] = character.trs(a["T"][f, ci], a["R"][f, ci], a["S"][f, ci])
    world = character.world_from_local(local, base.parents)
    pts = base.skinned_points(world)
    posed_c = character.Character(name=base.name, points=pts.astype(np.float32), faces=base.faces, uvs=base.uvs,
                                  joints=[], parents=np.zeros(0, int), bind=np.zeros((0, 4, 4)),
                                  rest_local=np.zeros((0, 4, 4)), joint_indices=None, joint_weights=None, anim=None,
                                  textures=base.textures)
    row, _ = preview.render(posed_c, frame=None, size=size, views=("front", "side"), layout=False, label="")
    return row


def mask_board(name, ctx, out, size=520):
    """The base at rest: free points in RED, the arm skin BLUE, the legs GREEN."""
    from PIL import Image
    import preview
    wd = ctx["wd"]
    base_pts = wd.X[wd.canon]
    lm = ctx["lm"]
    val = np.full(len(wd.X), 0.02)
    val[lm["legs"]] = 0.3
    val[lm["skin"]] = 0.55
    val[ctx["free"]] = 0.85
    pal = np.zeros((4, 256, 3), np.float32)
    pal[:] = 0.72
    pal[:, 60:110] = (0.25, 0.7, 0.3)
    pal[:, 125:170] = (0.2, 0.35, 0.9)
    pal[:, 200:240] = (0.9, 0.12, 0.1)
    buf = io.BytesIO()
    Image.fromarray((pal * 255).astype(np.uint8)).save(buf, "PNG")
    v = val[wd.canon]
    return v, pal, buf


def mask_render(name, base, ctx, out, size=480):
    from PIL import Image
    import preview
    v, pal, buf = mask_board(name, ctx, out)
    c = character.Character(name=name, points=base.points, faces=base.faces,
                            uvs=np.c_[v, np.full(len(v), 0.5)].astype(np.float32), joints=[],
                            parents=np.zeros(0, int), bind=np.zeros((0, 4, 4)), rest_local=np.zeros((0, 4, 4)),
                            joint_indices=None, joint_weights=None,
                            textures=[character.Texture("base_color", buf.getvalue(), "png")])
    row, _ = preview.render(c, size=size, views=("front", "side", "back"), layout=False,
                            label=f"{name}: red = free (solved), blue = arm skin, green = legs")
    row.save(out, quality=85)


# --- the command ---------------------------------------------------------------

def mesh_stretch(before, after, name, bundle, samples=SAMPLES):
    """Before and after on the FINAL meshes (the cut included), per clip, over
    the edges touching a row the pass changed (its weights, or a copy the
    cut made): (max, p99, edges past 2x, edges past 4x)."""
    n0 = len(before.points)
    J = len(before.joints)
    Wb = dense_weights(before.joint_indices, before.joint_weights, J)
    Wa = dense_weights(after.joint_indices, after.joint_weights, J)
    changed = np.r_[np.abs(Wa[:n0] - Wb).sum(axis=1) > 1e-3, np.ones(len(after.points) - n0, bool)]
    tags, mats = clip_mats(before, name, bundle, samples)
    h = float(before.points[:, 1].max() - before.points[:, 1].min())
    out = {}
    for label, char, W, ch in (("before", before, Wb, changed[:n0]), ("after", after, Wa, changed)):
        f = char.faces
        e = np.unique(np.sort(np.vstack([f[:, [0, 1]], f[:, [1, 2]], f[:, [2, 0]]]), axis=1), axis=0)
        e = e[ch[e[:, 0]] | ch[e[:, 1]]]
        X = char.points.astype(np.float64)
        S = edge_stretch(posed(X, W, mats), X, e, h)
        clips = [t[0] for t in tags]
        for c in dict.fromkeys(clips):
            rows = [k for k, t in enumerate(clips) if t == c]
            w = S[rows].max(axis=0)
            out.setdefault(c, {})[label] = (float(w.max()), float(np.percentile(w, 99)), int((w > 2).sum()),
                                            int((w > 4).sum()))
    return out


def process(name, bundle=BUNDLE, out_dir=None, board_dir=None, in_place=False, verbose=True, board_frames=3,
            force=False, lod_mode=None):
    lod_mode = lod_mode or LOD_MODE
    base = character.read_usdz(bundle / f"{name}.usdz")
    if not base.skinned:
        print(f"  {name}: unrigged")
        return None
    Wnew, ctx = optimise(base, name, bundle, verbose=verbose)
    res = measure_result(ctx, Wnew, name, verbose=verbose)
    res["time"] = ctx.get("time", 0.0)
    if not ctx["free"].any():
        return res
    height = ctx["height"]
    skin_rows = ctx["lm"]["skin"][ctx["wd"].canon]
    res["energy"] = (ctx.get("energy_shipped", 0.0), ctx.get("energy_solved", 0.0))
    if ctx.get("energy_solved", 0.0) > ENERGY_MAX * ctx.get("energy_shipped", 1.0) and not force:
        res["refused"] = (f"the solve lowered the robust energy only {ctx['energy_shipped']:.0f} -> "
                          f"{ctx['energy_solved']:.0f} (over {ENERGY_MAX:.0%}): nothing written")
        if verbose:
            print(f"  {name}: REFUSED — {res['refused']}")
        return res
    shipped = character.read_usdz(bundle / f"{name}.usdz")
    moved = apply(base, Wnew, ctx, name, bundle, verbose=verbose)
    res["mesh"] = mesh_stretch(shipped, base, name, bundle)
    if verbose:
        print(f"    FINAL MESH (cut included), edges touching changed rows:")
        print(f"    {'clip':13s} {'max':>15s} {'p99':>13s} {'>2x':>13s} {'>4x':>11s}")
        for c, d in res["mesh"].items():
            b, a = d["before"], d["after"]
            print(f"    {c:13s} {b[0]:6.2f} -> {a[0]:6.2f} {b[1]:5.2f} -> {a[1]:5.2f} {b[2]:5d} -> {a[2]:5d} {b[3]:4d} -> {a[3]:4d}")
    targets = []
    dst_dir = bundle if in_place else Path(out_dir)
    dst_dir.mkdir(parents=True, exist_ok=True)
    targets.append((base, dst_dir / f"{name}.usdz"))
    lod_path = bundle / f"{name}_lod.usdz"
    if lod_path.exists():
        lod = character.read_usdz(lod_path)
        if lod_mode == "solve":
            # The LOD solved on its own edges, by the same energy: its decimated
            # faces bridge the garment and the fist differently from the base's,
            # and nezha's LOD, given the base's weights point by point, tore
            # along the free region's border where the base did not.
            lod_shipped = character.read_usdz(lod_path)
            Wl, ctxl = optimise(lod, name, bundle, verbose=verbose)
            if ctxl.get("energy_solved", 0.0) > ENERGY_MAX * ctxl.get("energy_shipped", 1.0):
                if verbose:
                    print("    LOD: its own solve gained too little; it takes the base's weights instead")
                m, _ = lod_transfer(base, moved, lod, height, name, bundle)
            else:
                apply(lod, Wl, ctxl, name, bundle, verbose=verbose)
            res["lod_mesh"] = mesh_stretch(lod_shipped, lod, name, bundle)
            res["lod_moved"] = int(ctxl["free"].sum())
            if verbose:
                print(f"    LOD solved on its own: {res['lod_moved']:,} free points, energy "
                      f"{ctxl.get('energy_shipped', 0):.0f} -> {ctxl.get('energy_solved', 0):.0f}")
        else:
            m, cut = lod_transfer(base, moved, lod, height, name, bundle)
            res["lod_moved"] = m
            if verbose:
                print(f"    LOD: {m:,} vertices took the base's weights, {cut:,} doubled at the seam")
        targets.append((lod, dst_dir / lod_path.name))
    for char, dst in targets:
        tmp = Path(tempfile.mkdtemp()) / dst.name
        character.write_usdz(char, tmp)
        shutil.move(str(tmp), str(dst))
    if board_dir and not in_place:
        bd = Path(board_dir)
        bd.mkdir(parents=True, exist_ok=True)
        # the worst frame of each of the three worst clips
        seen, frames = set(), []
        for c, f in res["worst_frames"]:
            if c in seen:
                continue
            seen.add(c)
            frames.append((c, f))
            if len(frames) == board_frames:
                break
        res["board"] = str(board(name, dst_dir, frames, bd / f"{name}_board.jpg", bundle))
        res["board_lod"] = str(board(name, dst_dir, frames[:1], bd / f"{name}_lod_board.jpg", bundle, lod=True))
        mask_render(name, character.read_usdz(bundle / f"{name}.usdz"), ctx, bd / f"{name}_mask.jpg")
        res["board_hands"] = str(hand_board(name, dst_dir, frames[:2], bd / f"{name}_hands.jpg", bundle))
        res["mask"] = str(bd / f"{name}_mask.jpg")
        res["frames"] = frames
    return res


def self_test(bundle=BUNDLE):
    """The clean controls are refused by the energy guard: nothing written."""
    ok = True
    for name in CLEAN_CONTROLS:
        if not (bundle / f"{name}.usdz").exists():
            continue
        with _quiet():
            res = process(name, bundle, out_dir=tempfile.mkdtemp(), verbose=False)
        e0, e1 = res.get("energy", (0.0, 0.0))
        good = bool(res.get("refused"))
        print(f"self-test {name}: energy {e0:.0f} -> {e1:.0f}, {'refused -> ok' if good else 'WRITTEN -> FAIL'}")
        ok &= good
    return ok


class _quiet:
    def __enter__(self):
        self._cm = contextlib.redirect_stdout(io.StringIO())
        self._cm.__enter__()

    def __exit__(self, *a):
        self._cm.__exit__(*a)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("names", nargs="*")
    ap.add_argument("--out", help="write <name>.usdz and <name>_lod.usdz here (a scratch dir)")
    ap.add_argument("--board", help="before/after boards (worst frames, the LOD, both hands, the free mask) here")
    ap.add_argument("--bundle", default=str(BUNDLE), help="read the shipped files from here")
    ap.add_argument("--in-place", action="store_true", help="overwrite the bundle's base and LOD (the owner's call)")
    ap.add_argument("--all", action="store_true", help="every judged family (CLOTH_FAMILIES), in place")
    ap.add_argument("--survey", action="store_true", help="what each named family would free, no solve")
    ap.add_argument("--self-test", action="store_true")
    ap.add_argument("--lod", choices=("transfer", "solve"), default=None, help="how the LOD takes the result")
    ap.add_argument("--force", action="store_true", help="write even when the energy guard refuses")
    args = ap.parse_args()
    bundle = Path(args.bundle)
    if args.self_test:
        sys.exit(0 if self_test(bundle) else 1)
    if args.survey:
        for name in args.names:
            base = character.read_usdz(bundle / f"{name}.usdz")
            optimise(base, name, bundle, verbose=True, sweeps=0)
        return
    if args.all:
        args.names = list(CLOTH_FAMILIES)
        args.in_place = True
    if not args.names:
        ap.error("name families, or --all, --survey or --self-test")
    if not args.out and not args.in_place:
        ap.error("--out DIR (a scratch dir) or --in-place")
    for name in args.names:
        print(f"== {name}")
        process(name, bundle, args.out, args.board, args.in_place, force=args.force, lod_mode=args.lod)


if __name__ == "__main__":
    main()
