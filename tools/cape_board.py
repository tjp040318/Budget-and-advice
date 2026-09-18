"""Draws what the cape pass (character.reweight_cape) re-binds, per family:
the figure's vertices from behind and from the side, the re-bound ones in
red when a limb owned them and orange when the torso did, over the body in
grey, with the counts and the owners in the caption. The pass is run here
exactly as mesh.py runs it, on the source mesh made canonical and passed
through the serious2 proportions, without shipping anything.

    python3 tools/cape_board.py ares_m7 zeus_m7 diana        # -> cape_board_ares_m7.png

Every rule in the pass was set by reading this board (2026-09-18): the false
positives — a cyclops's arms, Sekhmet's arm bands, Zeus's bolt, Hades's
bident, Diana's bow — are visible here and invisible in the count."""
import sys, io, contextlib, pathlib
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import numpy as np, character, mesh
from PIL import Image, ImageDraw

def mask_for(ch):
    import copy
    leaf = np.array([j.split("/")[-1] for j in ch.joints])
    before = (ch.joint_indices.copy(), ch.joint_weights.copy())
    owner = leaf[ch.joint_indices[np.arange(len(ch.points)), np.argmax(ch.joint_weights, axis=1)]]
    character.reweight_cape(ch, min_share=0.0)
    changed = (ch.joint_indices != before[0]).any(axis=1) | (np.abs(ch.joint_weights - before[1]) > 1e-6).any(axis=1)
    limb_owned = np.array([character._bone_kind(n) in character.LIMB_BONES for n in leaf])[before[0][np.arange(len(ch.points)), np.argmax(before[1], axis=1)]]
    return ch.points.astype(np.float64), changed, limb_owned, owner

def panel(P, cloth, limb_owned, size=480):
    img = Image.new("RGB", (size*2, size), (245, 242, 235)); d = ImageDraw.Draw(img)
    lo, hi = P.min(0), P.max(0); s = (size-20) / max(hi[1]-lo[1], 1e-6)
    def px(u, v, ox):  # u horizontal coordinate, v = y
        return ox + size/2 + u*s, size-10 - (v-lo[1])*s
    order = np.argsort(cloth.astype(int))  # selected drawn last
    for i in order:
        x, y, z = P[i]
        col = (200, 30, 30) if cloth[i] and limb_owned[i] else (230, 150, 60) if cloth[i] else (150, 150, 150)
        bx, by = px(-x, y, 0)          # from behind: x mirrored
        d.point((bx, by), fill=col)
        sx, sy = px(-z, y, size)       # from the figure's right: +z (the front) to the left
        d.point((sx, sy), fill=col)
    d.line([(size, 0), (size, size)], fill=(120,120,120))
    return img

rows = []
for name in sys.argv[1:]:
    out_name = name.split("_m7")[0].split("_v")[0].split("_hd")[0]
    src = mesh.source_for(name)
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        ch = character.read(src); h = mesh.roster_height(out_name) or 1.9
        character.canonicalise(ch, height=h); ch.anim = None
        character.reproportion(ch, character.PROPORTIONS["serious2"], height=h)
    P, cloth, limb_owned, own = mask_for(ch)
    img = panel(P, cloth, limb_owned)
    d = ImageDraw.Draw(img)
    counts = {}
    for o in own[cloth & limb_owned]: counts[o] = counts.get(o,0)+1
    top = ", ".join(f"{k} {v}" for k,v in sorted(counts.items(), key=lambda kv:-kv[1])[:4])
    d.text((6, 4), f"{out_name}: {int(cloth.sum()):,} selected, {int((cloth & limb_owned).sum()):,} limb-owned (red): {top}", fill=(20,20,20))
    rows.append(img)
W = max(r.width for r in rows); H = sum(r.height for r in rows)
sheet = Image.new("RGB", (W, H), (255,255,255)); y = 0
for r in rows: sheet.paste(r, (0, y)); y += r.height
out = f"cape_board_{sys.argv[1]}.png"
sheet.save(out); print("->", out, sheet.size)
