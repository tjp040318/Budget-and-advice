"""Relief for the stage textures: a tangent-space normal map per tile.

Summoners War's floors are carved patterns with bevelled edges, and what
makes them read is the light catching the edge of every tile. Ours are
painted tiles (Gemini, `tools/batch/stage_textures.sh`) with the shading
baked flat, so the key light slides over them as over a photograph. This
derives a height field from each painting's own luminance — the grout is
dark and low, the stone bright and high, the cracks dark and low — and
writes the normal map SceneKit shades with (`SCNMaterial.normal`,
`StageBuilder.floorMaterial`): the tile edges bevel, the cracks cut in,
and a directional light at 36° draws every one.

    python3 tools/floor_relief.py                 # every floor_* and rock_* tile
    python3 tools/floor_relief.py --only floor_marble
    python3 tools/floor_relief.py --sheet x.jpg   # the maps and a lit preview to look at

Writes `Pantheon/Resources/Stage/<name>_n.png` at 512 px (the tile spans
about three metres on the slab, 14 m from the lens: 512 is more than the
screen resolves). `shrink_art.py` leaves `floor_`/`rock_` files alone, so
the maps stay PNG, which a normal map must (JPEG's ringing is a surface
full of dents).

Convention: OpenGL / SceneKit tangent space — red is +X to the right of
the image, green is +Y toward the TOP of the image, blue is out of the
surface. Height is a blend of three blurs of the luminance: a 1 px one
for the cracks and the engraving, a 3.5 px one that turns the grout's
step into a bevel, a 9 px one for the tile's gentle cushion. The slope
scale puts the steepest 5% of the surface at about 35° so nothing reads
as a cliff.
"""
from __future__ import annotations

import argparse
from pathlib import Path

import numpy as np
from PIL import Image
from scipy import ndimage

REPO = Path(__file__).resolve().parents[1]
STAGE = REPO / "Pantheon" / "Resources" / "Stage"
SIZE = 512
TILT = np.tan(np.radians(35))


def height_field(image: Image.Image) -> np.ndarray:
    rgb = np.asarray(image.convert("RGB").resize((SIZE, SIZE), Image.LANCZOS), dtype=np.float32) / 255.0
    lum = rgb @ np.array([0.299, 0.587, 0.114], dtype=np.float32)
    fine = ndimage.gaussian_filter(lum, 1.0, mode="wrap")
    bevel = ndimage.gaussian_filter(lum, 3.5, mode="wrap")
    cushion = ndimage.gaussian_filter(lum, 9.0, mode="wrap")
    height = 0.55 * fine + 0.30 * bevel + 0.15 * cushion
    height -= height.mean()
    return height


def normal_map(height: np.ndarray) -> np.ndarray:
    # Sobel over a wrapped field so the seams stay seamless. axis=1 is x
    # (right), axis=0 is y (down the image).
    hx = ndimage.sobel(height, axis=1, mode="wrap") / 8.0
    hy = ndimage.sobel(height, axis=0, mode="wrap") / 8.0
    slope = np.hypot(hx, hy)
    k = TILT / max(1e-6, float(np.percentile(slope, 95)))
    nx = -hx * k
    ny = hy * k  # y-down gradient → y-up normal
    nz = np.ones_like(nx)
    length = np.sqrt(nx * nx + ny * ny + nz * nz)
    normal = np.stack([nx / length, ny / length, nz / length], axis=-1)
    return normal


def to_image(normal: np.ndarray) -> Image.Image:
    rgb = np.clip((normal * 0.5 + 0.5) * 255.0 + 0.5, 0, 255).astype(np.uint8)
    return Image.fromarray(rgb, "RGB")


def lit_preview(source: Image.Image, normal: np.ndarray) -> Image.Image:
    """The painting shaded by its own relief, light from the upper left."""
    light = np.array([-0.45, 0.55, 0.70])
    light /= np.linalg.norm(light)
    shade = np.clip(normal @ light, 0, 1)
    rgb = np.asarray(source.convert("RGB").resize((SIZE, SIZE), Image.LANCZOS), dtype=np.float32) / 255.0
    lit = rgb * (0.45 + 0.75 * shade[..., None])
    return Image.fromarray(np.clip(lit * 255 + 0.5, 0, 255).astype(np.uint8), "RGB")


def tiles(only: str | None) -> list[Path]:
    names = sorted(p for p in STAGE.glob("*.png")
                   if (p.name.startswith(("floor_", "rock_")) and not p.stem.endswith("_n")))
    if only:
        names = [p for p in names if p.stem == only]
    return names


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--only", help="one tile's stem, e.g. floor_marble")
    parser.add_argument("--sheet", help="write a contact sheet (source, normal map, lit) to this path")
    args = parser.parse_args()

    rows = []
    for path in tiles(args.only):
        source = Image.open(path)
        normal = normal_map(height_field(source))
        out = path.with_name(f"{path.stem}_n.png")
        to_image(normal).save(out, optimize=True)
        print(f"{out.relative_to(REPO)}  {out.stat().st_size // 1024} KB")
        if args.sheet:
            rows.append((path.stem, source.convert("RGB").resize((SIZE, SIZE), Image.LANCZOS),
                         to_image(normal), lit_preview(source, normal)))

    if args.sheet and rows:
        from PIL import ImageDraw
        cell = 300
        sheet = Image.new("RGB", (3 * (cell + 8) + 8, len(rows) * (cell + 28) + 8), (24, 22, 20))
        draw = ImageDraw.Draw(sheet)
        for r, (name, *images) in enumerate(rows):
            y = 8 + r * (cell + 28)
            draw.text((8, y + 2), f"{name}: painting · normal map · lit by the map", fill=(230, 222, 200))
            for c, image in enumerate(images):
                sheet.paste(image.resize((cell, cell), Image.LANCZOS), (8 + c * (cell + 8), y + 20))
        sheet.save(args.sheet, quality=90)
        print("sheet", args.sheet)


if __name__ == "__main__":
    main()
