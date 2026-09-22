"""The robe ring's three numbers, per family, the shipped file BEFORE beside
the ring AFTER (character.reweight_robe, in memory, simulated by
tools/cape_sim.py's RingSim exactly as the phone steps it):

  FLY      arm-held cloth vertices that travel more than 0.3 of the height
           from where the pelvis alone would carry them, at ANY frame of the
           clip (the cloth: owned by an arm or held by one over 30%, below
           the neck, outside the arm's own skin, off the cape — the design's
           `cloth_fly_peak`). The ring must cut it by 80%.
  STRETCH  the 99.9th percentile, over the robe's edges, of each edge's
           worst posed/rest length over the clip. A spike or a tear is 3x or
           more. Two of them: the ring's INTERIOR (faces wholly on robe
           joints: the simulation's own work) must stay under 2.0; the whole
           robe with its seams may be no worse than the shipped file or
           SEAM_CEILING, since every shipped garment creases at the hip under
           linear blend skinning (the controls measure 3.4-21.8).
  REST     the ring settled 120 steps at the bind pose: the largest vertex
           offset from the bind pose, as a share of the height; under 0.005.

    python3 tools/cloth_metrics.py heimdall                  # attack_heavy, walk, death
    python3 tools/cloth_metrics.py heimdall --lod --clips attack_heavy
    python3 tools/cloth_metrics.py --json out.json heimdall pluto baldr

Every frame is played (the scratch measure of 2026-09-22 sampled every
third, so its FLY counts run a little lower than these)."""
import argparse, io, contextlib, json, sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import numpy as np  # noqa: E402
import character  # noqa: E402
import cape_sim  # noqa: E402
import robe_pass  # noqa: E402

BUNDLE = robe_pass.BUNDLE
FLY_LINE = 0.3
# The seam's ceiling: every garment edge's worst stretch at the 99.9th
# percentile, shipped, on the heavy attack — Zeus 3.4, the Sekhmet 6.4,
# Ares 7.4, Diana 9.3, Hades 11.9, Anhur 16.4, Atalanta 21.8 (the last two
# the skirt pass's judged wins). The ring's seams may be no worse than the
# shipped file's, or than this, whichever is higher.
SEAM_CEILING = 16.4


def cloth_mask(char):
    """The design's arm-held cloth (its measure.py): an arm owns it or holds
    it over 30%, below the neck, outside the arm's own skin, off the cape."""
    leaf = [j.split("/")[-1] for j in char.joints]
    kind = [character._bone_kind(l) for l in leaf]
    P = char.points.astype(np.float64)
    N = len(P)
    owner = char.joint_indices[np.arange(N), np.argmax(char.joint_weights, axis=1)]
    _, skin, armk = character._arm_masks(char, P)
    capek = np.array([l.startswith("cape_") for l in leaf])
    W = np.zeros((N, len(leaf)))
    np.add.at(W, (np.broadcast_to(np.arange(N)[:, None], char.joint_indices.shape), char.joint_indices),
              char.joint_weights)
    armw = W[:, armk].sum(axis=1)
    lower = {l.lower(): i for i, l in enumerate(leaf)}
    neck = lower.get("neck", lower.get("head"))
    neck_y = char.bind[neck][3, 1]
    return (armk[owner] | (armw > 0.3)) & (P[:, 1] < neck_y) & ~skin & ~capek[owner]


def frames_of(char, clip, sim=True, ring=True):
    """Every frame's posed points and the hips' world transform."""
    n = len(clip.anim["T"])
    posed, which = cape_sim.play(char, clip, list(range(n)), sim=sim, ring=ring)
    cmap = {j.split("/")[-1]: i for i, j in enumerate(clip.joints)}
    hips = {j.split("/")[-1].lower(): i for i, j in enumerate(char.joints)}["hips"]
    hips_world = []
    a = clip.anim
    for f in which:
        local = np.array(char.rest_local, dtype=np.float64)
        for bi, bj in enumerate(char.joints):
            ci = cmap.get(bj.split("/")[-1])
            if ci is not None:
                local[bi] = character.trs(a["T"][f, ci], a["R"][f, ci], a["S"][f, ci])
        hips_world.append(character.world_from_local(local, char.parents)[hips])
    return posed, hips_world, hips


def fly(char, cloth, posed, hips_world, hips):
    P = char.points.astype(np.float64)[:len(cloth)]
    h = float(np.ptp(char.points[:, 1]))
    inv = np.linalg.inv(char.bind[hips])
    peak = np.zeros(len(cloth))
    for pts, Wh in zip(posed, hips_world):
        rigid = (np.c_[P, np.ones(len(P))] @ (inv @ Wh))[:, :3]
        peak = np.maximum(peak, np.linalg.norm(pts[:len(cloth)] - rigid, axis=1) / h)
    return int((cloth & (peak > FLY_LINE)).sum())


def edges_of(faces, sel):
    f = faces[sel[faces].any(axis=1)]
    e = np.vstack([f[:, [0, 1]], f[:, [1, 2]], f[:, [2, 0]]])
    return np.unique(np.sort(e, axis=1), axis=0)


def stretch(char, edges, posed):
    P = char.points.astype(np.float64)
    rest = np.linalg.norm(P[edges[:, 0]] - P[edges[:, 1]], axis=1)
    ok = rest > 1e-6
    edges, rest = edges[ok], rest[ok]
    worst = np.zeros(len(edges))
    for pts in posed:
        worst = np.maximum(worst, np.linalg.norm(pts[edges[:, 0]] - pts[edges[:, 1]], axis=1) / rest)
    return float(np.percentile(worst, 99.9)) if len(worst) else 1.0, float(worst.max()) if len(worst) else 1.0


def measure(name, clips=("attack_heavy", "walk", "death"), lod=False, bundle=BUNDLE):
    """Before and after, per clip. Returns a dict."""
    with contextlib.redirect_stdout(io.StringIO()):
        base, n, moved = robe_pass.robe_base(name, bundle=bundle)
        after = base
        if lod and n:
            after, _ = robe_pass.robe_lod(name, base, moved, bundle=bundle)
    before = character.read_usdz(bundle / f"{name}{'_lod' if lod else ''}.usdz")
    out = {"family": name, "lod": lod, "ring": bool(n), "clips": {}}
    if not n:
        return out
    n0 = len(before.points)
    # The cloth, not the things the hand holds: a bident or a sword flies
    # with the swing by design, and the design's count of Pluto's 2,198
    # carried his 735-vertex bident (2026-09-22).
    held = robe_pass.held_rows(base, before) if lod else base._robe_sets["held"][:n0]
    cloth = cloth_mask(before) & ~held
    # The robe's own triangles: every face touching a vertex whose weights
    # changed (or a seam copy); the same edges measured on the shipped file.
    changed = np.zeros(len(after.points), bool)
    changed[:n0] = ((after.joint_indices[:n0] != before.joint_indices).any(axis=1)
                    | (np.abs(after.joint_weights[:n0] - before.joint_weights) > 1e-6).any(axis=1))
    changed[n0:] = True
    e_after = edges_of(after.faces, changed)
    e_before = edges_of(before.faces, changed[:n0])
    # The ring's own interior: faces whose three corners hang wholly on robe
    # joints — what the simulation alone governs (a tear between chains, a
    # hem folded through itself), apart from the seams with the legs, the
    # hips and the hand, where linear blend skinning creases every shipped
    # garment (the controls' garments measure 3-22 there, 2026-09-22).
    robe_cols = np.array([j.split("/")[-1].startswith("robe_") for j in after.joints])
    on_ring = (after.joint_weights * robe_cols[after.joint_indices]).sum(axis=1) > 0.999
    f_ring = after.faces[on_ring[after.faces].all(axis=1)]
    e_ring = np.unique(np.sort(np.vstack([f_ring[:, [0, 1]], f_ring[:, [1, 2]], f_ring[:, [2, 0]]]), axis=1), axis=0) \
        if len(f_ring) else np.zeros((0, 2), int)
    out["changed"] = int(changed[:n0].sum())
    out["REST"] = cape_sim.settle_offset(after)
    for c in clips:
        path = bundle / f"{name}_{c}.usdz"
        if not path.exists():
            continue
        clip = character.read_usdz(path)
        pb, hb, hi = frames_of(before, clip, sim=True)
        pr, hr, _ = frames_of(after, clip, sim=True, ring=False)
        pa, ha, _ = frames_of(after, clip, sim=True, ring=True)
        rec = {"frames": len(pa),
               "FLY_before": fly(before, cloth, pb, hb, hi),
               "FLY_rigid": fly(after, cloth, pr, hr, hi),
               "FLY_after": fly(after, cloth, pa, ha, hi)}
        rec["STRETCH_before"], rec["STRETCH_before_max"] = stretch(before, e_before, pb)
        rec["STRETCH_rigid"], rec["STRETCH_rigid_max"] = stretch(after, e_after, pr)
        rec["STRETCH_after"], rec["STRETCH_after_max"] = stretch(after, e_after, pa)
        rec["STRETCH_ring"], rec["STRETCH_ring_max"] = stretch(after, e_ring, pa) if len(e_ring) else (1.0, 1.0)
        fb = rec["FLY_before"]
        rec["FLY_drop"] = 1.0 - rec["FLY_after"] / fb if fb else 0.0
        out["clips"][c] = rec
    return out


def verdict(m):
    """The admission rule on the numbers alone (the boards are the other half)."""
    if not m.get("ring"):
        return False, "no ring"
    fails = []
    heavy = m["clips"].get("attack_heavy")
    if heavy is None:
        fails.append("no attack_heavy")
    elif heavy["FLY_drop"] < 0.80:
        fails.append(f"FLY down only {100 * heavy['FLY_drop']:.0f}%")
    for c, r in m["clips"].items():
        if r["STRETCH_ring"] >= 2.0:
            fails.append(f"ring STRETCH {r['STRETCH_ring']:.2f} on {c}")
        if r["STRETCH_after"] > max(r["STRETCH_before"], SEAM_CEILING):
            fails.append(f"seam STRETCH {r['STRETCH_after']:.1f} on {c} (shipped {r['STRETCH_before']:.1f})")
    if m["REST"] >= 0.005:
        fails.append(f"REST {m['REST']:.4f} h")
    return not fails, "; ".join(fails) or "numbers pass"


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("names", nargs="+")
    ap.add_argument("--clips", default="attack_heavy,walk,death")
    ap.add_argument("--lod", action="store_true")
    ap.add_argument("--json")
    args = ap.parse_args()
    allm = []
    for name in args.names:
        m = measure(name, tuple(c for c in args.clips.split(",") if c), lod=args.lod)
        ok, why = verdict(m)
        allm.append(dict(m, verdict=why, passes=ok))
        tag = f"{name}{' LOD' if args.lod else ''}"
        if not m["ring"]:
            print(f"{tag}: no ring")
            continue
        print(f"{tag}: {m['changed']:,} re-bound, REST {m['REST']:.4f} h — {'PASS' if ok else 'FAIL'} ({why})")
        for c, r in m["clips"].items():
            print(f"   {c:13s} FLY {r['FLY_before']:5d} -> rigid {r['FLY_rigid']:5d} -> ring {r['FLY_after']:5d} "
                  f"({100 * r['FLY_drop']:+.0f}% gone)   STRETCH p99.9 {r['STRETCH_before']:.2f} -> rigid "
                  f"{r['STRETCH_rigid']:.2f} -> ring {r['STRETCH_after']:.2f} (max {r['STRETCH_after_max']:.2f}); "
                  f"ring interior {r['STRETCH_ring']:.2f}")
        sys.stdout.flush()
    if args.json:
        Path(args.json).write_text(json.dumps(allm, indent=1))


if __name__ == "__main__":
    main()
