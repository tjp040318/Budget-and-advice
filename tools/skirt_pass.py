"""The skirt pass over SHIPPED families (2026-09-22): cloth that Meshy's
auto-rig bound to a hand, a forearm or an upper arm — Anhur's tunic panel
swung up with his khopesh, Heimdall's cloak flew out with his arm — is
given back to the body (character.reweight_skirt; the rules and what each
earlier cut got wrong are in its docstring), in the shipped base, in place,
and its LOD takes the base's verdict vertex by vertex (`transfer`); the clip
carriers keep their skinning, which the game never reads.

    python3 tools/skirt_pass.py --survey               # every shipped base: what would move
    python3 tools/skirt_pass.py anhur ptah             # re-weight these (base + _lod), in place
    python3 tools/skirt_pass.py --all                  # the families judged and named in
                                                      # character.SKIRT_FAMILIES

Judge a family on tools/base_plus_clip.py at the heavy attack's BLOW frame
(`--frames=30`, with the `=`) afterwards, never on the count alone: of the
sixteen the survey moves cloth on, three are wins and ten shred or tear
(2026-09-22), and only the judged names are applied."""
import argparse, shutil, sys, tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import character  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]
BUNDLE = ROOT / "Pantheon" / "Resources" / "Models"
CLIPS = ("attack_basic", "attack_heavy", "ultimate", "idle", "idle_combat", "death", "hit_react", "victory", "walk", "lod")


def families():
    out = []
    for p in sorted(BUNDLE.glob("*.usdz")):
        stem = p.stem
        if any(stem.endswith("_" + c) for c in CLIPS) or stem.startswith(("prop_", "boss_", "enemy_")):
            continue
        out.append(stem)
    return out


def excluded(name):
    """The winged and the tailed, as the cape pass: wings along the arms are
    a hand's sheet beside the thighs, and they must stay the arms'."""
    return any(k in name.lower() for k in character.CAPE_EXCLUDE)


def count(name):
    char = character.read_usdz(BUNDLE / f"{name}.usdz")
    return character.reweight_skirt(char), len(char.points)


def transfer(base, moved, lod, height):
    """The LOD takes the base's verdict: every LOD vertex whose nearest base
    vertex (within 2% of the height) was re-bound takes that vertex's new
    weights, joints matched by name. The LOD is a decimation of the same
    surface, and judged on its own it reads its cloth differently — at a
    third of the vertices Heimdall's cloak measured a hair over the solid
    threshold and Njord's weld a few points under — while the battle draws
    the LOD and nothing else. (mesh.py has no such step: it runs the pass
    on the base and decimates the LOD from it afterwards.)"""
    from scipy.spatial import cKDTree
    import numpy as np
    base_leaf = [j.split("/")[-1] for j in base.joints]
    lod_index = {j.split("/")[-1]: i for i, j in enumerate(lod.joints)}
    remap = np.array([lod_index.get(l, -1) for l in base_leaf])
    n0 = len(moved)   # the base's vertices before cut_seam doubled its seam
    d, idx = cKDTree(base.points[:n0].astype(np.float64)).query(lod.points.astype(np.float64))
    take = moved[idx] & (d < 0.02 * height)
    K = lod.joint_indices.shape[1]
    ji_before, jw_before = lod.joint_indices.copy(), lod.joint_weights.copy()
    n = 0
    for v in np.flatnonzero(take):
        src = idx[v]
        ji = remap[base.joint_indices[src]]
        jw = base.joint_weights[src].astype(np.float64)
        ok = ji >= 0
        if not ok.any():
            continue
        ji, jw = ji[ok], jw[ok]
        order = np.argsort(-jw)[:K]
        ji, jw = ji[order], jw[order]
        jw /= max(float(jw.sum()), 1e-9)
        row_i = np.zeros(K, dtype=lod.joint_indices.dtype)
        row_w = np.zeros(K, dtype=lod.joint_weights.dtype)
        row_i[:len(ji)] = ji
        row_w[:len(jw)] = jw
        lod.joint_indices[v] = row_i
        lod.joint_weights[v] = row_w
        n += 1
    if n:
        cut = character.cut_seam(lod, take, ji_before, jw_before)
        if cut:
            print(f"    skirt: the LOD's seam with the arm cut, {cut:,} vertices doubled")
    return n


def apply(name):
    import numpy as np
    src = BUNDLE / f"{name}.usdz"
    base = character.read_usdz(src)
    ji0, jw0 = base.joint_indices.copy(), base.joint_weights.copy()
    n0 = len(base.points)
    n = character.reweight_skirt(base)
    if n == 0:
        print(f"  {src.name}: nothing to move")
        return 0
    moved = ((base.joint_indices[:n0] != ji0).any(axis=1)
             | (np.abs(base.joint_weights[:n0] - jw0) > 1e-6).any(axis=1))
    height = float(base.points[:, 1].max() - base.points[:, 1].min())
    tmp = Path(tempfile.mkdtemp()) / src.name
    character.write_usdz(base, tmp)
    shutil.move(str(tmp), str(src))
    print(f"  {src.name}: {n:,} vertices re-bound, written")
    lod_path = BUNDLE / f"{name}_lod.usdz"
    if lod_path.exists():
        lod = character.read_usdz(lod_path)
        m = transfer(base, moved, lod, height)
        if m:
            tmp = Path(tempfile.mkdtemp()) / lod_path.name
            character.write_usdz(lod, tmp)
            shutil.move(str(tmp), str(lod_path))
            print(f"  {lod_path.name}: {m:,} vertices took the base's verdict, written")
        else:
            print(f"  {lod_path.name}: no vertex within reach of a re-bound one; unchanged")
    return n


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("names", nargs="*")
    ap.add_argument("--survey", action="store_true")
    ap.add_argument("--all", action="store_true")
    args = ap.parse_args()
    if args.survey or args.all:
        flagged = []
        for name in families():
            if excluded(name):
                continue
            try:
                n, total = count(name)
            except Exception as exc:  # noqa: BLE001
                print(f"{name}: unreadable ({exc})")
                continue
            if n:
                flagged.append(name)
                print(f"{name}: {n:,} of {total:,} ({100 * n / total:.1f}%) cloth an arm owned")
            sys.stdout.flush()
        print(f"\n{len(flagged)} flagged: {' '.join(flagged)}")
        judged = [n for n in flagged if n in character.SKIRT_FAMILIES]
        print(f"judged and applied by name (character.SKIRT_FAMILIES): {' '.join(judged)}")
        if args.all:
            for name in judged:
                print(f"== {name}")
                apply(name)
        return
    for name in args.names:
        if excluded(name):
            print(f"== {name}: winged or tailed (character.CAPE_EXCLUDE); skipped")
            continue
        print(f"== {name}")
        apply(name)


if __name__ == "__main__":
    main()
