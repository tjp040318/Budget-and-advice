"""Skins a shipped BASE mesh with a shipped CLIP file's animation the way the
game does (per-joint tracks matched by name onto the base's skeleton) and
renders it, front and side, so a base/clip mismatch or a misbound cape shows
here instead of on the phone.

    python3 tools/base_plus_clip.py Pantheon/Resources/Models/ares.usdz \
        Pantheon/Resources/Models/ares_attack_heavy.usdz out.jpg [--frames 0,37,74]

Without --frames: the first, middle and last frame. The cape pass was judged
on the heavy attack's blow frame (37 for Ares) and the idle (2026-09-18)."""
import sys, pathlib
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import numpy as np
from PIL import Image
import character, preview

def leaf(j): return j.split("/")[-1]

def base_plus_clip(base_path, clip_path, frames=(0, None, -1)):
    base = character.read_usdz(base_path)
    clip = character.read_usdz(clip_path)
    cmap = {leaf(j): i for i, j in enumerate(clip.joints)}
    n = len(clip.anim["T"])
    out = []
    missing = [leaf(j) for j in base.joints if leaf(j) not in cmap]
    # how far the clip's rest skeleton is from the base's, per joint (local translation)
    dt = []
    for bi, bj in enumerate(base.joints):
        ci = cmap.get(leaf(bj))
        if ci is None: continue
        dt.append(np.linalg.norm(base.rest_local[bi][:3, 3] - clip.rest_local[ci][:3, 3]))
    print(f"  {base_path.split('/')[-1]} + {clip_path.split('/')[-1]}: {len(base.joints)} base joints, {len(clip.joints)} clip joints, "
          f"{len(missing)} unmatched {missing[:4]}, rest-local translation gap max {max(dt):.4f} m mean {np.mean(dt):.4f} m; {n} frames")
    for f in frames:
        f = n // 2 if f is None else (n - 1 if f == -1 else f)
        local = np.array(base.rest_local, dtype=np.float64)
        for bi, bj in enumerate(base.joints):
            ci = cmap.get(leaf(bj))
            if ci is None: continue
            a = clip.anim
            local[bi] = character.trs(a["T"][f, ci], a["R"][f, ci], a["S"][f, ci])
        world = character.world_from_local(local, base.parents)
        pts = base.skinned_points(world)
        lo, hi = character.bounds(pts)
        print(f"    frame {f}: {hi[1]-lo[1]:.2f} m tall, size {np.round(hi-lo,2)}")
        posed = character.Character(name=base.name, points=pts.astype(np.float32), faces=base.faces, uvs=base.uvs,
                                    joints=[], parents=np.zeros(0, int), bind=np.zeros((0,4,4)), rest_local=np.zeros((0,4,4)),
                                    joint_indices=None, joint_weights=None, anim=None, textures=base.textures)
        row, _ = preview.render(posed, frame=None, size=520, views=("front", "side"), layout=False, label=f"{base.name} frame {f}")
        out.append(row)
    return out

if __name__ == "__main__":
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    base, clip, outpath = args[0], args[1], args[2]
    frames = (0, None, -1)
    for a in sys.argv[1:]:
        if a.startswith("--frames="):
            frames = tuple(int(x) for x in a.split("=", 1)[1].split(","))
    rows = base_plus_clip(base, clip, frames=frames)
    h = sum(r.height for r in rows); w = max(r.width for r in rows)
    sheet = Image.new("RGB", (w, h), (30, 30, 34)); y = 0
    for r in rows: sheet.paste(r, (0, y)); y += r.height
    sheet.save(outpath, quality=90); print("  ->", outpath)
