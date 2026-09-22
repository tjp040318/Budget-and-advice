"""The robe ring over SHIPPED families (2026-09-22): the lower garment that
Meshy's auto-rig bound to the hands resting on it — Heimdall's cloak,
Pluto's robe, Freya's cloak edges — is hung on joints of its own round the
hips (character.reweight_robe; the rules and why each exists are in its
docstring), in the shipped base, in place, and the LOD takes the base's
verdict vertex by vertex AFTER the same robe joints are appended to it in
the same order at the same bind positions (`transfer`); the clip carriers
are never touched — they carry no robe joint, and must not.

    python3 tools/robe_pass.py --survey               # every shipped base: what the ring would take
    python3 tools/robe_pass.py heimdall pluto         # re-weight these (base + _lod), in place —
                                                      # only names in character.ROBE_FAMILIES,
                                                      # unless --force-name
    python3 tools/robe_pass.py --all                  # the families judged and named in
                                                      # character.ROBE_FAMILIES

Judge a family BEFORE it is named: `tools/robe_board.py` (who owns what),
`tools/cape_sim.py <family> attack_heavy --robe --frames 0,20,30,45,-1`
(shipped, the ring held rigid, the ring simulated) and
`tools/cloth_metrics.py <family>` (FLY, STRETCH, REST). Never on the count."""
import argparse, io, contextlib, shutil, sys, tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import numpy as np  # noqa: E402
import character  # noqa: E402
from skirt_pass import families, excluded  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]
BUNDLE = ROOT / "Pantheon" / "Resources" / "Models"


def robe_base(name, quiet=False, bundle=BUNDLE):
    """The shipped base with the ring applied, in memory. Returns (base, n,
    moved) with `moved` the base's rows (before the seam was cut) whose
    weights changed."""
    base = character.read_usdz(bundle / f"{name}.usdz")
    base.name = name
    ji0, jw0 = base.joint_indices.copy(), base.joint_weights.copy()
    n0 = len(base.points)
    buf = io.StringIO()
    if quiet:
        with contextlib.redirect_stdout(buf):
            n = character.reweight_robe(base)
    else:
        n = character.reweight_robe(base)
    if not n:
        return base, 0, np.zeros(n0, bool)
    K = ji0.shape[1]
    moved = ((base.joint_indices[:n0] != ji0).any(axis=1)
             | (np.abs(base.joint_weights[:n0] - jw0) > 1e-6).any(axis=1))
    return base, n, moved


def transfer(base, moved, lod, height):
    """The LOD takes the base's verdict. FIRST the base's robe joints are
    appended to the LOD — same names, same order, same bind positions —
    because the weights are matched by leaf name and a name the LOD lacks
    would be dropped in silence (every robe weight would vanish); THEN every
    LOD vertex whose nearest base vertex (within 2% of the height) was
    re-bound takes that vertex's new weights; THEN the LOD's weld with its
    own hand's skin is cut, and nothing else. Returns the vertices taken."""
    from scipy.spatial import cKDTree
    plan = character.robe_joint_plan(base)
    character.append_robe_joints(lod, plan)
    base_leaf = [j.split("/")[-1] for j in base.joints]
    lod_index = {j.split("/")[-1]: i for i, j in enumerate(lod.joints)}
    remap = np.array([lod_index.get(l, -1) for l in base_leaf])
    assert (remap >= 0).all(), "the LOD lacks a joint the base has"
    n0 = len(moved)
    Plod = lod.points.astype(np.float64)
    owner0 = lod.joint_indices[np.arange(len(Plod)), np.argmax(lod.joint_weights, axis=1)]
    d, idx = cKDTree(base.points[:n0].astype(np.float64)).query(Plod)
    take = moved[idx] & (d < 0.02 * height)
    K = lod.joint_indices.shape[1]
    ji_before, jw_before = lod.joint_indices.copy(), lod.joint_weights.copy()
    n = 0
    for v in np.flatnonzero(take):
        src = idx[v]
        ji = remap[base.joint_indices[src]]
        jw = base.joint_weights[src].astype(np.float64)
        order = np.argsort(-jw)[:K]
        ji, jw = ji[order], jw[order]
        jw /= max(float(jw.sum()), 1e-9)
        row_i = np.zeros(K, dtype=lod.joint_indices.dtype)
        row_w = np.zeros(K, dtype=lod.joint_weights.dtype)
        row_i[:len(ji)] = ji
        row_w[:len(jw)] = jw
        row_i[row_w <= 0] = 0
        lod.joint_indices[v] = row_i
        lod.joint_weights[v] = row_w
        n += 1
    if n:
        leaf = [j.split("/")[-1] for j in lod.joints]
        armkind = np.array([k in ("arm", "forearm") or k.startswith("hand")
                            for k in (character._bone_kind(l) for l in leaf)])
        arm_now = (lod.joint_weights.astype(np.float64) * armkind[lod.joint_indices]).sum(axis=1)
        owner_now = lod.joint_indices[np.arange(len(Plod)), np.argmax(lod.joint_weights[:len(Plod)], axis=1)]
        against = ((arm_now > 0.5) | armkind[owner_now]) & ~take
        cut = character.cut_seam(lod, take, ji_before, jw_before, against=against)
        if cut:
            print(f"    robe: the LOD's weld with what the arm keeps cut, {cut:,} vertices doubled")
    return n


def robe_lod(name, base, moved, bundle=BUNDLE):
    lod = character.read_usdz(bundle / f"{name}_lod.usdz")
    lod.name = f"{name}_lod"
    height = float(base.points[:, 1].max() - base.points[:, 1].min())
    m = transfer(base, moved, lod, height)
    return lod, m


def held_rows(base, lod):
    """The LOD's vertices whose nearest base vertex the ring left with the
    hand (a weapon, a shield), for the metrics."""
    from scipy.spatial import cKDTree
    held = base._robe_sets["held"]
    n0 = len(held)
    _, idx = cKDTree(base.points[:n0].astype(np.float64)).query(lod.points.astype(np.float64))
    return held[idx]


def _write(char, path):
    tmp_dir = Path(tempfile.mkdtemp())
    tmp = tmp_dir / path.name
    character.write_usdz(char, tmp)
    facts = character.verify(tmp, quiet=True)
    if facts["problems"]:
        shutil.rmtree(tmp_dir, ignore_errors=True)
        raise RuntimeError(f"{path.name}: not written — {'; '.join(facts['problems'])}")
    shutil.move(str(tmp), str(path))
    shutil.rmtree(tmp_dir, ignore_errors=True)
    return facts


def apply(name):
    """Runs the ring on the shipped base and its LOD and writes both (through
    a temp file, verified). The clip carriers are not opened."""
    src = BUNDLE / f"{name}.usdz"
    base, n, moved = robe_base(name)
    if n == 0:
        print(f"  {src.name}: nothing to hang")
        return 0
    _write(base, src)
    print(f"  {src.name}: {n:,} vertices re-bound, {character.cloth_joint_count(base)} cloth joints, written")
    lod_path = BUNDLE / f"{name}_lod.usdz"
    if lod_path.exists():
        lod, m = robe_lod(name, base, moved)
        _write(lod, lod_path)
        print(f"  {lod_path.name}: {m:,} vertices took the base's verdict, {character.cloth_joint_count(lod)} cloth "
              f"joints, written")
    return n


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("names", nargs="*")
    ap.add_argument("--survey", action="store_true")
    ap.add_argument("--all", action="store_true")
    ap.add_argument("--force-name", action="store_true",
                    help="apply to a name not (yet) in character.ROBE_FAMILIES — for a scratch bundle only")
    args = ap.parse_args()
    if args.survey:
        flagged = []
        for name in families():
            if excluded(name):
                continue
            try:
                buf = io.StringIO()
                with contextlib.redirect_stdout(buf):
                    base, n, _ = robe_base(name)
            except Exception as exc:  # noqa: BLE001
                print(f"{name}: unreadable ({exc})")
                continue
            if n:
                flagged.append(name)
                sectors = next((l.strip() for l in buf.getvalue().splitlines() if "robe: sectors" in l), "")
                print(f"{name}: {n:,} of {len(base.points):,} re-bound; {sectors[len('robe: '):]}")
            sys.stdout.flush()
        print(f"\n{len(flagged)} would take a ring: {' '.join(flagged)}")
        print(f"judged and applied by name (character.ROBE_FAMILIES): {' '.join(character.ROBE_FAMILIES) or '(none)'}")
        return
    names = list(character.ROBE_FAMILIES) if args.all else args.names
    for name in names:
        if excluded(name):
            print(f"== {name}: winged or tailed (character.CAPE_EXCLUDE); skipped")
            continue
        if name not in character.ROBE_FAMILIES and not args.force_name:
            print(f"== {name}: not in character.ROBE_FAMILIES — judge it on its boards first; skipped")
            continue
        print(f"== {name}")
        apply(name)


if __name__ == "__main__":
    main()
