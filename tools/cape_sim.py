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
(canonical, serious2, the cape pass) instead of the shipped bundle file, so
a pass can be judged before it ships."""
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
    for line in buf.getvalue().splitlines():
        if "cape:" in line:
            print("  " + line.strip())
    return ch


def play(base, clip, frames, sim=True, loops=1):
    """Skins the base with the clip frame by frame (tracks matched by name,
    the chain simulated), returns the requested frames' posed points."""
    cmap = {_leaf(j): i for i, j in enumerate(clip.joints)}
    a = clip.anim
    n = len(a["T"])
    fps = float(a.get("fps", 30.0))
    engine = CapeSim(base) if sim and character.cape_joint_count(base) else None
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
            if engine is not None:
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


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("family")
    ap.add_argument("clip")
    ap.add_argument("--frames", default="0,,-1", help="comma list; empty = the middle, -1 = the last")
    ap.add_argument("--out", default="cape_board.jpg")
    ap.add_argument("--no-sim", action="store_true", help="the chain held at rest (what a spine-bound cape did)")
    ap.add_argument("--source", action="store_true", help="read Art/Models through the pipeline instead of the bundle")
    args = ap.parse_args()
    frames = tuple(None if f == "" else int(f) for f in args.frames.split(","))
    board(args.family, args.clip, frames=frames, out=args.out, sim=not args.no_sim, source=args.source)


if __name__ == "__main__":
    main()
