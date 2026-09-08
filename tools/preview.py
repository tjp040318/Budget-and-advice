#!/usr/bin/env python3
"""
Renders a character file to a PNG, so a model can be looked at here, where
there is no GPU, no SceneKit and no phone.

    python3 tools/preview.py Pantheon/Resources/Models/anubis.usdz --out x.png     # front, back, side + the UV layout
    python3 tools/preview.py Pantheon/Resources/Models/anubis_death.usdz --frame 40 --out x.png
    python3 tools/preview.py Art/Models/anubis.usdz --out x.png                    # a raw export is canonicalised first
    python3 tools/preview.py --sheet anubis --out anubis_sheet.png                 # every anubis*.usdz on one contact sheet

Pure numpy and Pillow: an orthographic camera, a z-buffer, barycentric UVs,
bilinear texture lookup and Lambert shading from the vertex normals. It is
not SceneKit, but it samples the same triangles with the same UVs from the
same texture, so a texture that is smeared here is smeared in the file, and
one that is right here can only go wrong on the phone in the importer.

The fourth panel draws every triangle in texture space over the texture. A
triangle that spans more than a quarter of the atlas in either direction
cannot be a real piece of surface - it is a seam vertex with the wrong UV -
and those are counted, printed and drawn in red.
"""

import argparse, io, sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont

sys.path.insert(0, str(Path(__file__).resolve().parent))
import character  # noqa: E402

REPO = Path(__file__).resolve().parent.parent
BUNDLE_DIR = REPO / "Pantheon" / "Resources" / "Models"

# world -> view, row-vector convention: columns are screen x, screen y (up)
# and depth towards the camera. Each is a proper rotation, so a triangle
# that is counter-clockwise on screen is front-facing.
VIEWS = {
    "front": np.array([[1, 0, 0], [0, 1, 0], [0, 0, 1]], float),      # camera on +Z, where the enemy stands
    "back": np.array([[-1, 0, 0], [0, 1, 0], [0, 0, -1]], float),
    "side": np.array([[0, 0, 1], [0, 1, 0], [-1, 0, 0]], float),      # camera on +X: (x, y, z) -> (-z, y, x)
}
LIGHT = np.array([-0.35, 0.6, 0.72]); LIGHT /= np.linalg.norm(LIGHT)   # view space: upper left, in front
BACKGROUND = np.array([0.86, 0.88, 0.91], np.float32)
SMEAR_SPAN = 0.25          # a triangle wider than this in UV space is not a piece of surface


# ---------------------------------------------------------------------------
# What to draw
# ---------------------------------------------------------------------------

def load(path, canonical=True):
    """A Character from any file the pipeline reads; a raw export is made
    canonical (Y-up, feet on the origin, facing +Z) so it can be compared with
    the shipped one. Size is kept."""
    char = character.read(path)
    if canonical:
        character.canonicalise(char, height=None)
    return char


def posed(char, frame):
    """(points, frame actually used). The bind pose when there is no clip."""
    if frame is None or not (char.skinned and char.anim):
        return char.points.astype(np.float64), None
    f = min(max(int(frame), 0), len(char.anim["T"]) - 1)
    return char.skinned_points(char.joint_world_at(f)), f


def base_colour(char):
    for t in char.textures:
        if t.role == "base_color":
            return np.asarray(Image.open(io.BytesIO(t.data)).convert("RGB"), dtype=np.float32) / 255.0
    return None


def uv_facts(char):
    """How the UVs look before anything is drawn: seam-split vertices, and
    triangles that span an impossible share of the atlas."""
    facts = {"seam_points": 0, "smeared": 0}
    key = np.round(char.points.astype(np.float64), 5)
    _, counts = np.unique(key, axis=0, return_counts=True)
    facts["seam_points"] = int((counts > 1).sum())
    if char.uvs is not None:
        tri = char.uvs[char.faces]                                   # (M,3,2)
        span = tri.max(axis=1) - tri.min(axis=1)
        facts["smeared"] = int((span.max(axis=1) > SMEAR_SPAN).sum())
    return facts


# ---------------------------------------------------------------------------
# Rasteriser
# ---------------------------------------------------------------------------

def sample(tex, uv):
    """Bilinear, wrapping, USD convention (v up)."""
    h, w = tex.shape[:2]
    x = uv[:, 0] * w - 0.5
    y = (1.0 - uv[:, 1]) * h - 0.5
    x0f, y0f = np.floor(x), np.floor(y)
    fx, fy = (x - x0f)[:, None], (y - y0f)[:, None]
    x0, y0 = x0f.astype(np.int64) % w, y0f.astype(np.int64) % h
    x1, y1 = (x0 + 1) % w, (y0 + 1) % h
    top = tex[y0, x0] * (1 - fx) + tex[y0, x1] * fx
    bottom = tex[y1, x0] * (1 - fx) + tex[y1, x1] * fx
    return top * (1 - fy) + bottom * fy


def rasterise(xy, depth, faces, width, height, cull=True):
    """The nearest triangle under every pixel centre: (face index or -1,
    barycentrics), both (height, width, ...) with y up. Triangles are
    bucketed by the size of their pixel box and each bucket is done in one
    vectorised pass, so 200,000 tiny triangles cost about as much as 5,000."""
    n = width * height
    fid = np.full(n, -1, np.int64)
    zbuf = np.full(n, -np.inf)
    bary = np.zeros((n, 3))
    p0, p1, p2 = xy[faces[:, 0]], xy[faces[:, 1]], xy[faces[:, 2]]
    area = (p1[:, 0] - p0[:, 0]) * (p2[:, 1] - p0[:, 1]) - (p1[:, 1] - p0[:, 1]) * (p2[:, 0] - p0[:, 0])
    keep = (area > 1e-9) if cull else (np.abs(area) > 1e-9)
    lo = np.floor(np.minimum(np.minimum(p0, p1), p2)).astype(np.int64)
    hi = np.floor(np.maximum(np.maximum(p0, p1), p2)).astype(np.int64)
    keep &= (hi[:, 0] >= 0) & (hi[:, 1] >= 0) & (lo[:, 0] < width) & (lo[:, 1] < height)
    lo = np.clip(lo, 0, [width - 1, height - 1])
    hi = np.clip(hi, 0, [width - 1, height - 1])
    size = (hi - lo).max(axis=1) + 1
    b = 1
    while b <= max(width, height):
        sel = np.where(keep & (size <= b) & (size > b // 2))[0]
        if len(sel):
            ox, oy = np.meshgrid(np.arange(b), np.arange(b))
            ox, oy = ox.ravel()[None, :], oy.ravel()[None, :]
            step = max(1, 2_000_000 // (b * b))
            for s in range(0, len(sel), step):
                t = sel[s:s + step]
                px = lo[t, 0][:, None] + ox
                py = lo[t, 1][:, None] + oy
                ok = (px <= hi[t, 0][:, None]) & (py <= hi[t, 1][:, None])
                cx, cy = px + 0.5, py + 0.5
                a0, a1, a2 = p0[t][:, None, :], p1[t][:, None, :], p2[t][:, None, :]
                w0 = (a1[..., 0] - cx) * (a2[..., 1] - cy) - (a1[..., 1] - cy) * (a2[..., 0] - cx)
                w1 = (a2[..., 0] - cx) * (a0[..., 1] - cy) - (a2[..., 1] - cy) * (a0[..., 0] - cx)
                w2 = (a0[..., 0] - cx) * (a1[..., 1] - cy) - (a0[..., 1] - cy) * (a1[..., 0] - cx)
                ar = area[t][:, None]
                b0, b1, b2 = w0 / ar, w1 / ar, w2 / ar
                ok &= (b0 >= -1e-7) & (b1 >= -1e-7) & (b2 >= -1e-7)
                if not ok.any():
                    continue
                ti = np.broadcast_to(t[:, None], ok.shape)[ok]
                b0, b1, b2 = b0[ok], b1[ok], b2[ok]
                z = b0 * depth[faces[ti, 0]] + b1 * depth[faces[ti, 1]] + b2 * depth[faces[ti, 2]]
                idx = py[ok] * width + px[ok]
                np.maximum.at(zbuf, idx, z)
                win = z >= zbuf[idx]
                fid[idx[win]] = ti[win]
                bary[idx[win]] = np.c_[b0[win], b1[win], b2[win]]
        b *= 2
    return fid.reshape(height, width), bary.reshape(height, width, 3)


def render_view(points, normals, faces, uvs, tex, view, scale, baseline, width, height, cull=True):
    v = points @ VIEWS[view]
    xy = np.empty((len(points), 2))
    xy[:, 0] = (v[:, 0] - (v[:, 0].min() + v[:, 0].max()) * 0.5) * scale + width * 0.5
    xy[:, 1] = v[:, 1] * scale + baseline
    fid, bary = rasterise(xy, v[:, 2], faces, width, height, cull)
    img = np.tile(BACKGROUND, (height, width, 1))
    ground = int(round(baseline))
    if 0 <= ground < height:
        img[ground, :] = BACKGROUND * 0.8
    hit = fid >= 0
    if hit.any():
        f, b = faces[fid[hit]], bary[hit]
        n = normals @ VIEWS[view]
        nn = b[:, :1] * n[f[:, 0]] + b[:, 1:2] * n[f[:, 1]] + b[:, 2:] * n[f[:, 2]]
        nn /= np.maximum(np.linalg.norm(nn, axis=1, keepdims=True), 1e-9)
        shade = 0.30 + 0.70 * np.clip(nn @ LIGHT, 0.0, 1.0)
        if tex is not None and uvs is not None:
            uv = b[:, :1] * uvs[f[:, 0]] + b[:, 1:2] * uvs[f[:, 1]] + b[:, 2:] * uvs[f[:, 2]]
            albedo = sample(tex, uv)
        else:
            albedo = np.full((len(f), 3), 0.72, np.float32)
        img[hit] = albedo * shade[:, None]
    return Image.fromarray((np.clip(img[::-1], 0, 1) * 255).astype(np.uint8))


def uv_layout(char, tex, size):
    """Every triangle drawn in texture space over the (darkened) texture;
    the smeared ones in red."""
    if tex is not None:
        img = Image.fromarray((tex * 0.55 * 255).astype(np.uint8)).resize((size, size), Image.BILINEAR)
    else:
        img = Image.new("RGB", (size, size), (40, 40, 40))
    if char.uvs is None:
        return img
    draw = ImageDraw.Draw(img)
    uv = char.uvs.astype(np.float64)
    px = np.c_[uv[:, 0] * (size - 1), (1.0 - uv[:, 1]) * (size - 1)]
    edges = np.sort(np.vstack([char.faces[:, [0, 1]], char.faces[:, [1, 2]], char.faces[:, [2, 0]]]), axis=1)
    edges = np.unique(edges, axis=0)
    for x0, y0, x1, y1 in px[edges].reshape(-1, 4).tolist():
        draw.line([(x0, y0), (x1, y1)], fill=(90, 220, 255), width=1)
    tri = uv[char.faces]
    span = (tri.max(axis=1) - tri.min(axis=1)).max(axis=1)
    for f in char.faces[span > SMEAR_SPAN]:
        draw.polygon([tuple(p) for p in px[f]], outline=(255, 40, 40))
    return img


def font(size=13):
    try:
        return ImageFont.load_default(size=size)
    except TypeError:
        return ImageFont.load_default()


def caption(width, text, height=18):
    strip = Image.new("RGB", (width, height), (30, 30, 34))
    ImageDraw.Draw(strip).text((4, 2), text, fill=(235, 235, 235), font=font())
    return strip


def render(char, frame=None, size=512, views=("front", "back", "side"), layout=True, texture=True, cull=True, label=""):
    """One row: the views, then the UV layout, with a caption. Returns (image, facts)."""
    pts, used = posed(char, frame)
    normals = character.vertex_normals(pts.astype(np.float32), char.faces).astype(np.float64)
    tex = base_colour(char) if texture else None
    width = int(round(size * 0.62))
    lo, hi = character.bounds(pts)
    ymin, ymax = min(0.0, lo[1]), max(hi[1], 0.05)
    horizontal = max(np.ptp((pts @ VIEWS[v])[:, 0]) for v in views)
    scale = 0.9 * min(width / max(horizontal, 1e-6), size / max(ymax - ymin, 1e-6))
    baseline = 0.05 * size - ymin * scale
    panels = [render_view(pts, normals, char.faces, char.uvs, tex, v, scale, baseline, width, size, cull) for v in views]
    if layout:
        panels.append(uv_layout(char, tex, size))
    total = sum(p.width for p in panels)
    row = Image.new("RGB", (total, size + 18), (30, 30, 34))
    x = 0
    for p in panels:
        row.paste(p, (x, 0))
        x += p.width
    facts = uv_facts(char)
    facts.update(tris=char.tris, points=len(char.points), frame=used,
                 texture=None if tex is None else tex.shape[1])
    pose = "bind pose" if used is None else f"frame {used}/{len(char.anim['T']) - 1}"
    text = (f"{label}  {char.tris:,} tris  {len(char.points):,} pts  "
            f"{'no texture' if facts['texture'] is None else str(facts['texture']) + 'px'}  {pose}  "
            f"smeared {facts['smeared']}")
    row.paste(caption(total, text), (0, size))
    return row, facts


def say(name, facts, char):
    pose = "bind pose" if facts["frame"] is None else f"frame {facts['frame']}"
    tex = "no texture" if facts["texture"] is None else f"base colour {facts['texture']}px"
    pct = 100.0 * facts["smeared"] / max(1, facts["tris"])
    print(f"    {name}: {facts['tris']:,} tris, {facts['points']:,} points, {tex}, {pose}; "
          f"{facts['seam_points']:,} points shared by seam-split vertices; "
          f"{facts['smeared']:,} triangles ({pct:.1f}%) span more than {int(SMEAR_SPAN * 100)}% of the atlas")


# ---------------------------------------------------------------------------
# Commands
# ---------------------------------------------------------------------------

def preview(args):
    src = Path(args.source)
    print(f"{src}")
    char = load(src, canonical=not args.raw)
    character.describe(char)
    row, facts = render(char, frame=args.frame, size=args.size, layout=not args.no_layout,
                        texture=not args.no_texture, cull=not args.two_sided, label=src.name)
    say(src.name, facts, char)
    out = Path(args.out) if args.out else Path.cwd() / f"{src.stem}.preview.png"
    out.parent.mkdir(parents=True, exist_ok=True)
    row.save(out)
    print(f"  -> {out}   {row.width}x{row.height}")
    return 0


def sheet(args):
    family = args.sheet
    files = sorted(BUNDLE_DIR.glob(f"{family}*.usdz"), key=lambda p: (p.stem != family, not p.stem.endswith("_lod"), p.name))
    if not files:
        sys.exit(f"no {family}*.usdz in {BUNDLE_DIR.relative_to(REPO)}")
    print(f"{family}: {len(files)} files from {BUNDLE_DIR.relative_to(REPO)}/")
    rows = []
    for p in files:
        char = load(p, canonical=not args.raw)
        frame = None
        if char.anim:
            frame = args.frame if args.frame is not None else len(char.anim["T"]) // 2
        row, facts = render(char, frame=frame, size=args.size, layout=False, texture=not args.no_texture,
                            cull=not args.two_sided, label=p.name)
        say(p.name, facts, char)
        rows.append(row)
    per_row = 2
    cell_w, cell_h = max(r.width for r in rows), max(r.height for r in rows)
    n_rows = (len(rows) + per_row - 1) // per_row
    img = Image.new("RGB", (cell_w * per_row + 8 * (per_row - 1), cell_h * n_rows + 8 * (n_rows - 1)), (60, 60, 66))
    for i, r in enumerate(rows):
        img.paste(r, ((i % per_row) * (cell_w + 8), (i // per_row) * (cell_h + 8)))
    out = Path(args.out) if args.out else Path.cwd() / f"{family}_sheet.png"
    out.parent.mkdir(parents=True, exist_ok=True)
    img.save(out)
    print(f"  -> {out}   {img.width}x{img.height}")
    return 0


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("source", nargs="?", help="a .usdz or .glb to render")
    ap.add_argument("--sheet", metavar="FAMILY", help="render every Pantheon/Resources/Models/<FAMILY>*.usdz on one sheet")
    ap.add_argument("--frame", type=int, help="pose the mesh with the file's clip at this frame (sheet: every clip)")
    ap.add_argument("--size", type=int, default=512, help="pixels per view, tall")
    ap.add_argument("--out", help="output PNG (default: <stem>.preview.png or <family>_sheet.png in the working directory)")
    ap.add_argument("--raw", action="store_true", help="do not canonicalise a raw export first")
    ap.add_argument("--no-texture", action="store_true", help="lit grey, to judge the geometry alone")
    ap.add_argument("--no-layout", action="store_true", help="skip the UV layout panel")
    ap.add_argument("--two-sided", action="store_true", help="draw back faces too (the shipped files are single-sided)")
    args = ap.parse_args()
    if args.sheet:
        return sheet(args)
    if not args.source:
        ap.error("give a file to render or --sheet <family>")
    return preview(args)


if __name__ == "__main__":
    sys.exit(main())
