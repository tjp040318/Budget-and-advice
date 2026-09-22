"""The cape's spring simulation, in Python, for the boards — the SAME sum as
Pantheon/Render/ClothChain.swift, constant for constant, so a board rendered
here shows what the phone will draw. Change a number in both files.

A cape's joints (`cape_0` … `cape_3`, character.reweight_cape) are a chain
of spring bones the way VRM and the genre's own capes are: each joint keeps
a TAIL particle in world space that carries its velocity (Verlet), is drawn
back toward the bone's rest direction in its parent's current frame
(stiffness — the cape follows the back it hangs from), pulled down by
gravity, held at the bone's length, and pushed out of spheres on the
pelvis, the torso and the legs; the joint's rotation is whatever turns the
rest direction onto the tail. Nothing moves a joint's origin: that is the
parent's, so the chain never detaches.

    python3 tools/cape_sim.py ares attack_heavy --frames 0,20,37,55 --out board.jpg
    python3 tools/cape_sim.py ares_m7 idle_combat --frames 0,15,30 --out board.jpg --source --no-sim

`--source` reads the family from Art/Models through the full pipeline
(canonical, serious2, the cape pass, and the skirt pass or the robe ring
for a family named in SKIRT_FAMILIES or ROBE_FAMILIES) instead of the
shipped bundle file, so a pass can be judged before it ships.

The ROBE RING (character.reweight_robe) is `RingSim` below, the twin of
ClothChain.swift's `ClothRing`, constant for constant:

    python3 tools/cape_sim.py pluto attack_heavy --robe --frames 0,20,30,45,-1 --out board.jpg
                        # shipped | the ring held rigid | the ring simulated, front and side
    python3 tools/cape_sim.py pluto attack_heavy --robe --lod --out board_lod.jpg
    python3 tools/cape_sim.py --selftest pluto [--reference capes.npz]
                        # the capes unmoved, the ring settled at its bind pose,
                        # and the numbers the Swift's DEBUG block prints"""
import sys, pathlib, argparse, io, contextlib
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import numpy as np
from PIL import Image
import character

# --- the constants (mirror: ClothChain.swift `Cloth`) -----------------------
STEP = 1.0 / 60.0            # the simulation's own step; a frame is split into as many as it needs
MAX_SUBSTEPS = 4
# A pull is a velocity added each step and re-normalised to the bone, so it
# reads as an acceleration of pull / STEP: gravity 0.35 is 21 m/s^2, twice the
# real thing, which swings a 26 cm segment with a 0.7 s period — a heavy cloth.
DRAG = 0.15                  # of the tail's velocity lost per step (about half-critical damping at that period)
GRAVITY = 0.35               # m/s per step, at 1.9 m; scaled by the figure's height
STIFFNESS_ROOT = 0.25        # toward the rest direction in the parent's frame, at the shoulder line …
STIFFNESS_HEM = 0.12         # … and at the hem; the joints between take a line between them
REFERENCE_HEIGHT = 1.9
# Spheres the tails stay out of: (joint a, joint b, fraction along a->b, radius as a share of the
# height): the pelvis, the chest, two on each thigh, one on each shin. Every radius is CAPPED at
# 0.97 of the sphere's rest distance to the chain, so nothing pushes at rest.
# And a PLANE through the hips facing backward: a tail never crosses in front of it, so the hem
# cannot swing forward between the legs when the figure stops (the spheres catch only what
# enters them). Its offset is the chain's rest clearance behind the pelvis, at most this share.
BACK_PLANE = ("hips", 0.06)
COLLIDERS = (
    ("hips", "hips", 0.0, 0.085),
    ("spine01", "spine01", 0.0, 0.09),
    ("leftupleg", "leftleg", 0.40, 0.06), ("leftupleg", "leftleg", 0.80, 0.06),
    ("rightupleg", "rightleg", 0.40, 0.06), ("rightupleg", "rightleg", 0.80, 0.06),
    ("leftleg", "leftfoot", 0.50, 0.045), ("rightleg", "rightfoot", 0.50, 0.045),
)


def _leaf(j):
    return j.split("/")[-1]


def _rot_col(world_row):
    """The rotation of a row-convention 4x4 as a column matrix (R @ v), scale stripped."""
    m = world_row[:3, :3]
    s = np.linalg.norm(m, axis=1)
    return (m / np.maximum(s, 1e-12)[:, None]).T


def _from_to(a, b):
    """The column rotation taking unit vector a onto unit vector b."""
    v = np.cross(a, b)
    c = float(np.dot(a, b))
    s = float(np.linalg.norm(v))
    if s < 1e-9:
        if c > 0:
            return np.eye(3)
        helper = np.array([1.0, 0.0, 0.0]) if abs(a[0]) < 0.9 else np.array([0.0, 1.0, 0.0])
        axis = np.cross(a, helper); axis /= np.linalg.norm(axis)
        return 2 * np.outer(axis, axis) - np.eye(3)
    k = v / s
    K = np.array([[0, -k[2], k[1]], [k[2], 0, -k[0]], [-k[1], k[0], 0]])
    return np.eye(3) + s * K + (1 - c) * (K @ K)


class CapeSim:
    """One chain on one character. `char.joints` must carry cape_0…; the
    rest transforms are read once, the state lives in the tails.

    Meshy's rigs carry a SCALE on every body joint (0.009 on Ares, the
    armature's own unit, cancelled by the bind), so a cape joint's rest
    local transform under the spine is that scale's inverse and the spine's
    inverse rotation: what the simulation replaces each step is the local
    ROTATION alone, the rest translation and the rest scale kept, exactly as
    the Swift sets `simdOrientation` and nothing else. Lengths and the
    forces are in the mesh's metres; a scaled model node is the Swift
    side's `worldScale`, which is 1 here."""

    def __init__(self, char):
        leaf = [_leaf(j) for j in char.joints]
        self.idx = {n.lower(): i for i, n in enumerate(leaf)}
        self.chain = [i for i, n in enumerate(leaf) if n.startswith("cape_")]
        if not self.chain:
            raise ValueError("no cape joints")
        self.anchor = int(char.parents[self.chain[0]])
        P = char.points.astype(np.float64)
        self.height = float(P[:, 1].max() - P[:, 1].min())
        self.unit = self.height / REFERENCE_HEIGHT
        self.rest_t, self.rest_R, self.rest_s = [], [], []
        for j in self.chain:
            t, q, sc = character.decompose(char.rest_local[j])
            self.rest_t.append(t); self.rest_R.append(character.quat_to_rot(q).T); self.rest_s.append(sc)
        # The bone axis: toward the child in this joint's own frame, which is
        # world-aligned at rest (the chain's bind transforms are translations);
        # the last joint repeats the segment above it.
        axes, lengths = [], []
        for k in range(len(self.chain)):
            off = self.rest_t[k + 1] if k + 1 < len(self.chain) else (self.rest_t[k] if k > 0 else np.array([0.0, -0.1, 0.0]))
            L = float(np.linalg.norm(off))
            axes.append(off / max(L, 1e-9)); lengths.append(L)
        self.axes, self.lengths = axes, lengths
        n = len(self.chain)
        self.stiffness = [STIFFNESS_ROOT + (STIFFNESS_HEM - STIFFNESS_ROOT) * k / max(n - 1, 1) for k in range(n)]
        # The colliders, in the bind pose, each radius capped at its rest clearance.
        rest_world = char.joint_world_at_rest()
        self.colliders = []
        chain_pts = self._rest_particles(rest_world)
        for a, b, frac, share in COLLIDERS:
            ia, ib = self.idx.get(a), self.idx.get(b)
            if ia is None or ib is None:
                continue
            centre = rest_world[ia][3, :3] * (1 - frac) + rest_world[ib][3, :3] * frac
            clearance = float(np.min(np.linalg.norm(chain_pts - centre, axis=1)))
            self.colliders.append((ia, ib, frac, min(share * self.height, 0.97 * clearance)))
        # The back plane: the hips' backward direction in the hips' own frame,
        # so it turns with the pelvis, and its offset from the hips' origin.
        self.plane = None
        ih = self.idx.get(BACK_PLANE[0])
        if ih is not None:
            R_hips = _rot_col(rest_world[ih])
            back = np.array([0.0, 0.0, -1.0])            # a canonical figure faces +Z
            depth = float(np.min((chain_pts - rest_world[ih][3, :3]) @ back))
            self.plane = (ih, R_hips.T @ back, min(BACK_PLANE[1] * self.height, 0.97 * depth))
        self.tails = None
        self.prev = None
        self.carry = 0.0

    def _joint(self, k, parent):
        """A chain joint's world position and its REST world rotation under a parent world transform."""
        R_parent = _rot_col(parent)
        pos = (np.append(self.rest_t[k], 1.0) @ parent)[:3]
        return pos, R_parent, R_parent @ self.rest_R[k]

    def _place(self, k, parent, R_world):
        """The joint's local row transform for a world rotation: rest translation and scale, new rotation."""
        R_local = _rot_col(parent).T @ R_world
        local = np.eye(4)
        local[:3, :3] = np.diag(self.rest_s[k]) @ R_local.T
        local[3, :3] = self.rest_t[k]
        return local

    def _rest_particles(self, world):
        """The tails at rest: each joint's origin plus its bone, in world space."""
        pts = []
        parent = world[self.anchor]
        for k, j in enumerate(self.chain):
            pos, _, R_rest = self._joint(k, parent)
            pts.append(pos + R_rest @ self.axes[k] * self.lengths[k])
            parent = self._place(k, parent, R_rest) @ parent
        return np.array(pts)

    def reset(self, world):
        self.tails = self._rest_particles(world)
        self.prev = self.tails.copy()
        self.carry = 0.0

    def step(self, world, dt):
        """`world` (J,4,4) row-convention world transforms with the chain at
        rest local; writes the chain's rows of `world` to the simulated pose."""
        if self.tails is None:
            self.reset(world)
        self.carry += dt
        substeps = int(min(MAX_SUBSTEPS, self.carry // STEP + 1e-9))
        self.carry -= substeps * STEP
        for _ in range(substeps):
            self._substep(world, STEP)
        if substeps == 0:
            self._pose(world)

    def _centres(self, world):
        return [(world[ia][3, :3] * (1 - frac) + world[ib][3, :3] * frac, r) for ia, ib, frac, r in self.colliders]

    def _substep(self, world, h):
        centres = self._centres(world)
        parent = world[self.anchor]
        for k, j in enumerate(self.chain):
            pos, R_parent, R_rest = self._joint(k, parent)
            rest_dir = R_rest @ self.axes[k]
            L = self.lengths[k]
            tail, prev = self.tails[k], self.prev[k]
            nxt = (tail + (tail - prev) * (1.0 - DRAG)
                   + rest_dir * (self.stiffness[k] * self.unit * h)
                   + np.array([0.0, -GRAVITY * self.unit * h, 0.0]))
            d = nxt - pos
            nxt = pos + d / max(np.linalg.norm(d), 1e-9) * L
            # A sphere the tail has entered pushes it out along the radius; the
            # push is a position correction and carries NO velocity into the
            # next step (the tail's history moves with it), or a thigh swinging
            # through the hem would fling the cape at ten times the speed of
            # anything the figure does.
            free = nxt.copy()
            for centre, r in centres:
                v = nxt - centre
                dist = float(np.linalg.norm(v))
                if dist < r:
                    nxt = centre + v / max(dist, 1e-9) * r
                    d = nxt - pos
                    nxt = pos + d / max(np.linalg.norm(d), 1e-9) * L
            if self.plane is not None:
                ih, back_local, offset = self.plane
                back = _rot_col(world[ih]) @ back_local
                depth = float((nxt - world[ih][3, :3]) @ back)
                if depth < offset:
                    nxt = nxt + back * (offset - depth)
                    d = nxt - pos
                    nxt = pos + d / max(np.linalg.norm(d), 1e-9) * L
            self.prev[k], self.tails[k] = tail + (nxt - free), nxt
            R_world = _from_to(rest_dir, (nxt - pos) / L) @ R_rest
            world[j] = self._place(k, parent, R_world) @ parent
            parent = world[j]

    def _pose(self, world):
        """No substep this frame: re-derive the pose from the tails as they stand."""
        parent = world[self.anchor]
        for k, j in enumerate(self.chain):
            pos, R_parent, R_rest = self._joint(k, parent)
            rest_dir = R_rest @ self.axes[k]
            d = self.tails[k] - pos
            R_world = _from_to(rest_dir, d / max(np.linalg.norm(d), 1e-9)) @ R_rest
            world[j] = self._place(k, parent, R_world) @ parent
            parent = world[j]


# --- the robe ring (mirror: ClothChain.swift `ClothRing`, `enum Robe`) --------
# Up to eight chains round the hips (character.reweight_robe: robe_<sector>_0
# under Hips down to robe_<sector>_3), stepped LEVEL-MAJOR: every chain's
# first joint, then the ties between neighbouring chains at that level, then
# the second joint, and so on — so a tie always pulls on tails whose parents
# have already moved this substep. Each tail: inertia (1 - drag), a pull
# toward the rest direction in the parent's current frame, gravity, the
# bone's length, the push out of the capsules on the thighs, the shins and
# the swinging hands and a sphere on the pelvis (a position correction that
# carries NO velocity, as the cape's), then the CONE: never more than
# ROBE_CONE_DEG off the rest direction, whatever the clip does — the robe
# can never become Pluto's wing again. Then the ties: two passes over the
# neighbouring pairs at this level, each pair's tails moved half the excess
# toward or away from each other when their distance leaves 0.70–1.30 of
# its rest, and each re-projected to its bone. Every correction after the
# free step (the pushes, the cone, the ties) moves the tail's history with
# it, so the next step's velocity is the free motion alone.
ROBE_SECTORS = tuple(n for n, _ in character.ROBE_SECTORS)
ROBE_AZIMUTH = {n: a for n, a in character.ROBE_SECTORS}
ROBE_DRAG = 0.20
ROBE_GRAVITY = 0.35           # m/s per step at 1.9 m, as the cape's, but measured FROM THE BIND POSE:
# the pull is ROBE_GRAVITY x (world down - the parent's REST down carried by
# the parent's current rotation), zero while the parent stands as it was
# bound. A robe flares, so plain gravity against a stiffness of 0.2-0.4
# sagged every ring at rest by 0.017-0.105 of the height (measured on the
# ten, 2026-09-22) — the whole robe collapsing inward the moment a stage
# opened. The cape keeps plain gravity: it hangs near vertical.
ROBE_STIFF_ROOT = 0.40
ROBE_STIFF_HEM = 0.20
ROBE_CONE_DEG = 55.0
ROBE_TIE = (0.70, 1.30)
ROBE_TIE_ITER = 2
ROBE_NEIGHBOUR_DEG = 90.0     # chains are tied when the forward azimuth gap between them is at most this
# (joint a, joint b or None, radius as a share of the height, hand): a hand
# capsule runs from the hand joint 0.12 h on along the forearm's direction
# (Meshy's rigs have no finger bones). Every radius is CAPPED at 0.97 of its
# rest clearance to the ring's tails, so nothing pushes at rest.
ROBE_CAPSULES = (
    ("leftupleg", "leftleg", 0.070, False), ("rightupleg", "rightleg", 0.070, False),
    ("leftleg", "leftfoot", 0.050, False), ("rightleg", "rightfoot", 0.050, False),
    ("lefthand", None, 0.035, True), ("righthand", None, 0.035, True),
    ("hips", "hips", 0.085, False),
)
ROBE_HAND_SEGMENT = 0.12
# The FLOOR: no tail below the figure's feet plane (the model's own y = 0,
# which the Swift reads as the model node's origin) plus this share of the
# height. A figure that dies lies down, and with the hips flat every chain
# hung straight through the ground on the death boards (2026-09-22).
ROBE_FLOOR = 0.01


def _closest_on_segment(p, a, b):
    ab = b - a
    ll = float(ab @ ab)
    t = 0.0 if ll < 1e-12 else min(max(float((p - a) @ ab) / ll, 0.0), 1.0)
    return a + ab * t


class RingSim:
    """The robe ring on one character: every robe_<sector>_0 under Hips and
    its chain, in the fixed sector order. The rest transforms are read once,
    the state lives in the tails, and what a step replaces is each joint's
    local ROTATION alone (rest translation and scale kept), as the cape."""

    def __init__(self, char):
        leaf = [_leaf(j) for j in char.joints]
        self.idx = {n.lower(): i for i, n in enumerate(leaf)}
        self.names, self.chains, self.azimuths = [], [], []
        for s in ROBE_SECTORS:
            chain = []
            k = 0
            while f"robe_{s}_{k}" in self.idx:
                chain.append(self.idx[f"robe_{s}_{k}"]); k += 1
            if chain:
                self.names.append(s); self.chains.append(chain); self.azimuths.append(ROBE_AZIMUTH[s])
        if len(self.chains) < 2:
            raise ValueError("no robe ring")
        self.parents = np.asarray(char.parents)
        P = char.points.astype(np.float64)
        self.height = float(P[:, 1].max() - P[:, 1].min())
        self.unit = self.height / REFERENCE_HEIGHT
        self.rest_t, self.rest_R, self.rest_s, self.axes, self.lengths, self.stiffness = [], [], [], [], [], []
        for chain in self.chains:
            rt, rR, rs = [], [], []
            for j in chain:
                t, q, sc = character.decompose(char.rest_local[j])
                rt.append(t); rR.append(character.quat_to_rot(q).T); rs.append(sc)
            axes, lengths = [], []
            for k in range(len(chain)):
                off = rt[k + 1] if k + 1 < len(chain) else (rt[k] if k > 0 else np.array([0.0, -0.1, 0.0]))
                L = float(np.linalg.norm(off))
                axes.append(off / max(L, 1e-9)); lengths.append(L)
            n = len(chain)
            self.rest_t.append(rt); self.rest_R.append(rR); self.rest_s.append(rs)
            self.axes.append(axes); self.lengths.append(lengths)
            self.stiffness.append([ROBE_STIFF_ROOT + (ROBE_STIFF_HEM - ROBE_STIFF_ROOT) * k / max(n - 1, 1)
                                   for k in range(n)])
        self.levels = max(len(c) for c in self.chains)
        # Each joint's REST down in its parent's frame: the parent's bind
        # rotation, inverted, applied to world down.
        rest_world0 = char.joint_world_at_rest()
        self.down_rest = []
        for c, chain in enumerate(self.chains):
            downs = []
            parent = rest_world0[int(char.parents[chain[0]])]
            for k, j in enumerate(chain):
                downs.append(_rot_col(parent).T @ np.array([0.0, -1.0, 0.0]))
                pos, _, R_rest = self._joint(c, k, parent)
                parent = self._place(c, k, parent, R_rest) @ parent
            self.down_rest.append(downs)
        # Neighbours: adjacent chains in the sector order whose FORWARD azimuth
        # gap is at most 90°; two chains are one pair, never two.
        self.pairs = []
        m = len(self.chains)
        for a in range(m):
            b = (a + 1) % m
            if b == a or (m == 2 and a == 1):
                continue
            gap = (self.azimuths[b] - self.azimuths[a]) % 360.0
            if gap <= ROBE_NEIGHBOUR_DEG + 1e-6:
                self.pairs.append((a, b))
        rest_world = char.joint_world_at_rest()
        tails = self._rest_particles(rest_world)
        allp = np.concatenate([np.array(t) for t in tails])
        self.colliders = []
        for a, b, share, hand in ROBE_CAPSULES:
            ia = self.idx.get(a)
            ib = self.idx.get(b) if b is not None else (int(self.parents[ia]) if ia is not None else None)
            if ia is None or ib is None:
                continue
            A, B = self._segment(rest_world, ia, ib, hand)
            clearance = float(min(np.linalg.norm(p - _closest_on_segment(p, A, B)) for p in allp))
            self.colliders.append((ia, ib, hand, min(share * self.height, 0.97 * clearance)))
        # The ties' rest lengths, per pair per level.
        self.tie_rest = []
        for a, b in self.pairs:
            n = min(len(self.chains[a]), len(self.chains[b]))
            self.tie_rest.append([float(np.linalg.norm(tails[a][k] - tails[b][k])) for k in range(n)])
        self.tails = None
        self.prev = None
        self.carry = 0.0

    def _segment(self, world, ia, ib, hand):
        A = world[ia][3, :3]
        if not hand:
            return A, world[ib][3, :3]
        u = A - world[ib][3, :3]                 # ib is the forearm: the hand's own direction
        n = float(np.linalg.norm(u))
        return A, A + (u / max(n, 1e-9)) * ROBE_HAND_SEGMENT * self.height

    def _joint(self, c, k, parent):
        R_parent = _rot_col(parent)
        pos = (np.append(self.rest_t[c][k], 1.0) @ parent)[:3]
        return pos, R_parent, R_parent @ self.rest_R[c][k]

    def _place(self, c, k, parent, R_world):
        R_local = _rot_col(parent).T @ R_world
        local = np.eye(4)
        local[:3, :3] = np.diag(self.rest_s[c][k]) @ R_local.T
        local[3, :3] = self.rest_t[c][k]
        return local

    def _parent_world(self, world, c, k):
        return world[int(self.parents[self.chains[c][k]])]

    def _rest_particles(self, world):
        out = []
        for c, chain in enumerate(self.chains):
            pts = []
            parent = self._parent_world(world, c, 0)
            for k, j in enumerate(chain):
                pos, _, R_rest = self._joint(c, k, parent)
                pts.append(pos + R_rest @ self.axes[c][k] * self.lengths[c][k])
                parent = self._place(c, k, parent, R_rest) @ parent
            out.append(pts)
        return out

    def reset(self, world):
        self.tails = [np.array(t) for t in self._rest_particles(world)]
        self.prev = [t.copy() for t in self.tails]
        self.carry = 0.0

    def step(self, world, dt):
        if self.tails is None:
            self.reset(world)
        self.carry += dt
        substeps = int(min(MAX_SUBSTEPS, self.carry // STEP + 1e-9))
        self.carry -= substeps * STEP
        for _ in range(substeps):
            self._substep(world, STEP)
        if substeps == 0:
            self._pose(world)

    @staticmethod
    def _to_length(pos, p, L):
        d = p - pos
        return pos + d / max(float(np.linalg.norm(d)), 1e-9) * L

    def _substep(self, world, h):
        segs = [(self._segment(world, ia, ib, hand), r) for ia, ib, hand, r in self.colliders]
        cos_cone = float(np.cos(np.radians(ROBE_CONE_DEG)))
        sin_cone = float(np.sin(np.radians(ROBE_CONE_DEG)))
        g = ROBE_GRAVITY * self.unit * h
        down = np.array([0.0, -1.0, 0.0])
        for k in range(self.levels):
            live = [c for c in range(len(self.chains)) if k < len(self.chains[c])]
            state = {}
            for c in live:
                parent = self._parent_world(world, c, k)
                pos, R_parent, R_rest = self._joint(c, k, parent)
                rest_dir = R_rest @ self.axes[c][k]
                L = self.lengths[c][k]
                tail, prev = self.tails[c][k], self.prev[c][k]
                gravity = (down - R_parent @ self.down_rest[c][k]) * g
                nxt = (tail + (tail - prev) * (1.0 - ROBE_DRAG)
                       + rest_dir * (self.stiffness[c][k] * self.unit * h) + gravity)
                nxt = self._to_length(pos, nxt, L)
                free = nxt.copy()
                for (A, B), r in segs:
                    q = _closest_on_segment(nxt, A, B)
                    v = nxt - q
                    dist = float(np.linalg.norm(v))
                    if dist < r:
                        nxt = self._to_length(pos, q + v / max(dist, 1e-9) * r, L)
                floor = ROBE_FLOOR * self.height
                if nxt[1] < floor:
                    nxt = nxt.copy(); nxt[1] = floor
                    nxt = self._to_length(pos, nxt, L)
                d = (nxt - pos) / L
                cosang = float(d @ rest_dir)
                if cosang < cos_cone:
                    perp = d - cosang * rest_dir
                    pn = float(np.linalg.norm(perp))
                    if pn < 1e-9:
                        helper = np.array([1.0, 0.0, 0.0]) if abs(rest_dir[0]) < 0.9 else np.array([0.0, 1.0, 0.0])
                        perp = np.cross(rest_dir, helper); pn = float(np.linalg.norm(perp))
                    nxt = pos + (rest_dir * cos_cone + perp / pn * sin_cone) * L
                state[c] = [pos, parent, R_rest, rest_dir, L, tail, free, nxt]
            lo, hi = ROBE_TIE
            for _ in range(ROBE_TIE_ITER):
                for pi, (a, b) in enumerate(self.pairs):
                    if a not in state or b not in state or k >= len(self.tie_rest[pi]):
                        continue
                    pa, pb = state[a][7], state[b][7]
                    v = pb - pa
                    dist = float(np.linalg.norm(v))
                    rest = self.tie_rest[pi][k]
                    if dist < 1e-9:
                        continue
                    if dist < lo * rest:
                        excess = dist - lo * rest
                    elif dist > hi * rest:
                        excess = dist - hi * rest
                    else:
                        continue
                    move = v / dist * (0.5 * excess)
                    state[a][7] = self._to_length(state[a][0], pa + move, state[a][4])
                    state[b][7] = self._to_length(state[b][0], pb - move, state[b][4])
            for c in live:
                pos, parent, R_rest, rest_dir, L, tail, free, nxt = state[c]
                self.prev[c][k] = tail + (nxt - free)
                self.tails[c][k] = nxt
                R_world = _from_to(rest_dir, (nxt - pos) / L) @ R_rest
                world[self.chains[c][k]] = self._place(c, k, parent, R_world) @ parent

    def _pose(self, world):
        for c, chain in enumerate(self.chains):
            parent = self._parent_world(world, c, 0)
            for k, j in enumerate(chain):
                pos, _, R_rest = self._joint(c, k, parent)
                rest_dir = R_rest @ self.axes[c][k]
                d = self.tails[c][k] - pos
                R_world = _from_to(rest_dir, d / max(np.linalg.norm(d), 1e-9)) @ R_rest
                world[j] = self._place(c, k, parent, R_world) @ parent
                parent = world[j]

    def describe(self):
        """What the Swift's DEBUG block prints, for comparison line by line."""
        lines = [f"[ClothRing] {len(self.chains)} chains, {self.levels} levels, h {self.height:.3f} m, "
                 f"unit {self.unit:.4f}"]
        for c, s in enumerate(self.names):
            lines.append(f"  robe_{s}: az {self.azimuths[c]:+.0f}, lengths "
                         + " ".join(f"{L:.4f}" for L in self.lengths[c])
                         + ", stiffness " + " ".join(f"{v:.3f}" for v in self.stiffness[c]))
        for pi, (a, b) in enumerate(self.pairs):
            lines.append(f"  tie robe_{self.names[a]}~robe_{self.names[b]}: rest "
                         + " ".join(f"{v:.4f}" for v in self.tie_rest[pi]))
        leaf_of = {i: n for n, i in self.idx.items()}
        for ia, ib, hand, r in self.colliders:
            lines.append(f"  collider {leaf_of[ia]}-{'hand+0.12h' if hand else leaf_of[ib]}: radius {r:.4f} m "
                         f"({r / self.height:.4f} h)")
        return "\n".join(lines)


def settle_offset(char, steps=120, cape=False):
    """REST: the robe settled `steps` steps at the bind pose, the largest
    vertex offset from the bind pose itself, as a share of the height."""
    world = char.joint_world_at_rest()
    sims = []
    if cape and character.cape_joint_count(char):
        sims.append(CapeSim(char))
    try:
        sims.append(RingSim(char))
    except ValueError:
        pass
    w = world.copy()
    for _ in range(steps):
        w = world.copy()
        for sim in sims:
            sim.step(w, STEP)
    bind = char.skinned_points(world)
    settled = char.skinned_points(w)
    P = char.points.astype(np.float64)
    h = float(P[:, 1].max() - P[:, 1].min())
    return float(np.max(np.linalg.norm(settled - bind, axis=1))) / h


# --- the board ---------------------------------------------------------------

def load_family(name, source=False):
    """The shipped base (Pantheon/Resources/Models) or, with `source`, the
    Art/Models export run through the pipeline as mesh.py would."""
    if not source:
        return character.read_usdz(f"Pantheon/Resources/Models/{name}.usdz")
    import mesh
    src = mesh.source_for(name)
    out_name = roster_name(name)
    h = mesh.roster_height(out_name) or 1.9
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        ch = character.read(src)
        character.canonicalise(ch, height=h)
        ch.anim = None
        character.reproportion(ch, character.PROPORTIONS["serious2"], height=h)
        character.reweight_cape(ch)
        if out_name.lower() in character.SKIRT_FAMILIES:
            character.reweight_skirt(ch)
        if out_name.lower() in character.ROBE_FAMILIES:
            character.reweight_robe(ch)
    for line in buf.getvalue().splitlines():
        if "cape:" in line or "robe:" in line:
            print("  " + line.strip())
    return ch


def play(base, clip, frames, sim=True, loops=1, ring=True):
    """Skins the base with the clip frame by frame (tracks matched by name,
    the chain simulated), returns the requested frames' posed points."""
    cmap = {_leaf(j): i for i, j in enumerate(clip.joints)}
    a = clip.anim
    n = len(a["T"])
    fps = float(a.get("fps", 30.0))
    engines = []
    if sim and character.cape_joint_count(base):
        engines.append(CapeSim(base))
    if sim and ring and any(_leaf(j).startswith("robe_") for j in base.joints):
        engines.append(RingSim(base))
    want = {(n // 2 if f is None else (n - 1 if f == -1 else f)) for f in frames}
    out = {}
    for pass_ in range(loops):
        for f in range(n):
            local = np.array(base.rest_local, dtype=np.float64)
            for bi, bj in enumerate(base.joints):
                ci = cmap.get(_leaf(bj))
                if ci is not None:
                    local[bi] = character.trs(a["T"][f, ci], a["R"][f, ci], a["S"][f, ci])
            world = character.world_from_local(local, base.parents)
            for engine in engines:
                engine.step(world, 1.0 / fps)
            if pass_ == loops - 1 and f in want:
                out[f] = base.skinned_points(world)
    return [out[f] for f in sorted(out)], sorted(out)


def roster_name(name):
    """`ares_m7` ships as `ares`: the clips and the bundle file are under the roster's name."""
    return name.split("_m7")[0].split("_v")[0].split("_hd")[0]


def board(name, clipname, frames=(0, None, -1), out="cape_board.jpg", sim=True, source=False, views=("front", "side"), size=460):
    import preview
    base = load_family(name, source=source)
    clip = character.read_usdz(f"Pantheon/Resources/Models/{roster_name(name)}_{clipname}.usdz")
    posed, which = play(base, clip, frames, sim=sim)
    rows = []
    for pts, f in zip(posed, which):
        lo, hi = character.bounds(pts)
        print(f"    frame {f}: {hi[1] - lo[1]:.2f} m tall, size {np.round(hi - lo, 2)}")
        stat = character.Character(name=base.name, points=pts.astype(np.float32), faces=base.faces, uvs=base.uvs,
                                   joints=[], parents=np.zeros(0, int), bind=np.zeros((0, 4, 4)), rest_local=np.zeros((0, 4, 4)),
                                   joint_indices=None, joint_weights=None, anim=None, textures=base.textures)
        row, _ = preview.render(stat, frame=None, size=size, views=views, layout=False,
                                label=f"{name} {clipname} f{f}{' sim' if sim else ' rest'}")
        rows.append(row)
    h = sum(r.height for r in rows); w = max(r.width for r in rows)
    sheet = Image.new("RGB", (w, h), (30, 30, 34)); y = 0
    for r in rows:
        sheet.paste(r, (0, y)); y += r.height
    sheet.save(out, quality=90)
    print("  ->", out)
    return sheet


def robe_board(name, clipname, frames=(0, 20, 30, 45, -1), out="robe_render.jpg", lod=False, size=280,
               views=("front", "side")):
    """The robe ring's render board: per frame, the SHIPPED file (its cape
    simulated, as the phone draws it today), the ring HELD RIGID (what a
    hip-bound robe would do) and the ring SIMULATED, each front and side.
    The ring is character.reweight_robe run in memory on the shipped base
    (and, with `lod`, carried to the shipped _lod by tools/robe_pass.py)."""
    import preview
    import robe_pass
    suffix = "_lod" if lod else ""
    before = character.read_usdz(f"Pantheon/Resources/Models/{name}{suffix}.usdz")
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        after, n, moved = robe_pass.robe_base(name)
        if lod and n:
            after, _ = robe_pass.robe_lod(name, after, moved)
    if not n:
        raise SystemExit(f"{name}: the ring takes nothing")
    clip = character.read_usdz(f"Pantheon/Resources/Models/{roster_name(name)}_{clipname}.usdz")
    nfr = len(clip.anim["T"])
    frames = tuple(nfr // 2 if f is None else f for f in frames)
    variants = (("shipped", before, dict(sim=True, ring=False)), ("ring rigid", after, dict(sim=True, ring=False)),
                ("ring sim", after, dict(sim=True, ring=True)))
    posed = []
    for label, ch, kw in variants:
        pts, which = play(ch, clip, frames, **kw)
        posed.append((label, ch, dict(zip(which, pts))))
    rows = []
    for f in sorted({(nfr - 1 if f == -1 else f) for f in frames}):
        panels = []
        for label, ch, by in posed:
            stat = character.Character(name=ch.name, points=by[f].astype(np.float32), faces=ch.faces, uvs=ch.uvs,
                                       joints=[], parents=np.zeros(0, int), bind=np.zeros((0, 4, 4)),
                                       rest_local=np.zeros((0, 4, 4)), joint_indices=None, joint_weights=None,
                                       anim=None, textures=ch.textures)
            row, _ = preview.render(stat, frame=None, size=size, views=views, layout=False,
                                    label=f"{name}{suffix} {clipname} f{f} {label}")
            panels.append(row)
        w = sum(p.width for p in panels) + 4 * (len(panels) - 1)
        line = Image.new("RGB", (w, max(p.height for p in panels)), (200, 170, 60))
        x = 0
        for p in panels:
            line.paste(p, (x, 0)); x += p.width + 4
        rows.append(line)
    h = sum(r.height for r in rows); w = max(r.width for r in rows)
    sheet = Image.new("RGB", (w, h), (30, 30, 34)); y = 0
    for r in rows:
        sheet.paste(r, (0, y)); y += r.height
    sheet.save(out, quality=88)
    print("  ->", out, sheet.size)
    return sheet


SELFTEST_CAPES = (("ares_m7", True), ("njord", False), ("freya", False))
SELFTEST_FRAMES = (0, 20, 37, 55, 72)


def cape_points(families=SELFTEST_CAPES, frames=SELFTEST_FRAMES):
    """The capes' posed points the selftest compares: each family on its
    attack_heavy, the cape simulated, NO robe ring (a shipped file)."""
    out = {}
    for name, src in families:
        with contextlib.redirect_stdout(io.StringIO()):
            base = load_family(name, source=src)
        clip = character.read_usdz(f"Pantheon/Resources/Models/{roster_name(name)}_attack_heavy.usdz")
        pts, which = play(base, clip, frames)
        for p, f in zip(pts, which):
            out[f"{name}_{f}"] = p
    return out


def selftest(family=None, reference=None, write_reference=None):
    """1. The cape: Ares (Art/Models through the pipeline), Njord and Freya
    on attack_heavy at frames 0, 20, 37, 55, 72 give the same points as the
    reference taken before the ring was added (np.allclose, atol 1e-6), when
    a reference is given; and a caped family WITH a ring poses its cape
    exactly as without one (the two sims never touch each other's joints).
    2. The ring: every family in character.ROBE_FAMILIES (or `family`),
    ring applied in memory, settles 120 steps at its bind pose within 0.005
    of the height. 3. Prints the numbers the Swift's DEBUG block prints."""
    import robe_pass
    ok = True
    if write_reference or reference:
        pts = cape_points()
        if write_reference:
            np.savez_compressed(write_reference, **pts)
            print(f"  wrote {write_reference}: {len(pts)} frames")
        if reference:
            ref = np.load(reference)
            for k in sorted(ref.files):
                same = k in pts and pts[k].shape == ref[k].shape and np.allclose(pts[k], ref[k], atol=1e-6)
                worst = float(np.abs(pts[k] - ref[k]).max()) if k in pts and pts[k].shape == ref[k].shape else float("inf")
                print(f"  cape {k}: {'same' if same else 'MOVED'} (worst {worst:.2e} m)")
                ok &= same
    names = [family] if family else list(character.ROBE_FAMILIES)
    for name in names:
        with contextlib.redirect_stdout(io.StringIO()):
            base, n, _ = robe_pass.robe_base(name)
        if not n:
            print(f"  {name}: no ring"); continue
        rest = settle_offset(base)
        print(f"  {name}: REST {rest:.5f} h ({'ok' if rest < 0.005 else 'FAIL'})")
        ok &= rest < 0.005
        if character.cape_joint_count(base):
            clip = character.read_usdz(f"Pantheon/Resources/Models/{roster_name(name)}_attack_heavy.usdz")
            cape_rows = np.isin(base.joint_indices, [i for i, j in enumerate(base.joints) if _leaf(j).startswith("cape_")]).any(axis=1)
            a, _ = play(base, clip, SELFTEST_FRAMES, ring=False)
            b, _ = play(base, clip, SELFTEST_FRAMES, ring=True)
            ring_rows = np.isin(base.joint_indices, [i for i, j in enumerate(base.joints) if _leaf(j).startswith("robe_")]).any(axis=1)
            only_cape = cape_rows & ~ring_rows
            same = all(np.allclose(x[only_cape], y[only_cape], atol=1e-9) for x, y in zip(a, b))
            print(f"  {name}: the cape with the ring beside it {'unchanged' if same else 'MOVED'}")
            ok &= same
        print(RingSim(base).describe())
    print("selftest:", "PASS" if ok else "FAIL")
    return 0 if ok else 1


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("family", nargs="?")
    ap.add_argument("clip", nargs="?")
    ap.add_argument("--frames", default="0,,-1", help="comma list; empty = the middle, -1 = the last")
    ap.add_argument("--out", default="cape_board.jpg")
    ap.add_argument("--no-sim", action="store_true", help="the chain held at rest (what a spine-bound cape did)")
    ap.add_argument("--source", action="store_true", help="read Art/Models through the pipeline instead of the bundle")
    ap.add_argument("--robe", action="store_true",
                    help="the robe ring's board: shipped | ring held rigid | ring simulated, per frame")
    ap.add_argument("--lod", action="store_true", help="with --robe: the shipped _lod, carried as robe_pass does")
    ap.add_argument("--size", type=int, default=280)
    ap.add_argument("--selftest", action="store_true",
                    help="the cape refactor moved no cape; the ring settles at its bind pose; prints the Swift's numbers")
    ap.add_argument("--reference", help="with --selftest: an npz of cape points to compare against")
    ap.add_argument("--write-reference", help="with --selftest: write the capes' points to this npz")
    args = ap.parse_args()
    if args.selftest:
        sys.exit(selftest(args.family, reference=args.reference, write_reference=args.write_reference))
    frames = tuple(None if f == "" else int(f) for f in args.frames.split(","))
    if args.robe:
        robe_board(args.family, args.clip, frames=frames, out=args.out, lod=args.lod, size=args.size)
        return
    board(args.family, args.clip, frames=frames, out=args.out, sim=not args.no_sim, source=args.source)


if __name__ == "__main__":
    main()
