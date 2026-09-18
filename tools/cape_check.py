"""How far a SHIPPED family's cape-ish vertices (behind the spine's plane,
knees to shoulders) move at one frame of one of its clips, by the joint that
owns them — the flap in Ares's heavy attack read as shin-owned cape moving
0.75 m. A calf's own back is in the band too, so read this beside
tools/base_plus_clip.py's picture, never alone.

    python3 tools/cape_check.py ares attack_heavy 37"""
import sys, pathlib
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import numpy as np, character
fam, clipname, f = sys.argv[1], sys.argv[2], int(sys.argv[3])
M = "Pantheon/Resources/Models/"
base = character.read_usdz(M+f"{fam}.usdz"); clip = character.read_usdz(M+f"{fam}_{clipname}.usdz")
leaf = lambda j: j.split("/")[-1]
cmap = {leaf(j): i for i, j in enumerate(clip.joints)}
local = np.array(base.rest_local, dtype=np.float64)
for bi, bj in enumerate(base.joints):
    ci = cmap.get(leaf(bj))
    if ci is None: continue
    a = clip.anim; local[bi] = character.trs(a["T"][f, ci], a["R"][f, ci], a["S"][f, ci])
world = character.world_from_local(local, base.parents)
pts = base.skinned_points(world); P0 = base.points.astype(np.float64)
names = [leaf(j) for j in base.joints]
idx = {n.lower(): i for i, n in enumerate(names)}
jw = np.array([base.bind[i][3,:3] for i in range(len(names))])
chain = [n for n in ("hips","spine","spine01","spine1","spine02","spine2") if n in idx]
spine_z = np.mean([jw[idx[n]][2] for n in chain]); h = P0[:,1].max() - P0[:,1].min()
dom = np.array(names)[base.joint_indices[np.arange(len(P0)), np.argmax(base.joint_weights, axis=1)]]
capeish = (P0[:,2] < spine_z - 0.06*h) & (P0[:,1] > 0.16*h) & (P0[:,1] < 0.8*h)
disp = np.linalg.norm(pts - P0, axis=1)
print(f"{fam} {clipname} frame {f}: {int(capeish.sum()):,} cape-ish verts (behind by 6% of {h:.2f} m, knees to shoulders)")
for o in sorted(set(dom[capeish]), key=lambda o: -disp[capeish & (dom==o)].max()):
    m = capeish & (dom == o)
    if m.sum() < 20: continue
    print(f"  {o:12s} {int(m.sum()):5d}  mean move {disp[m].mean():.2f} m  max {disp[m].max():.2f} m")
