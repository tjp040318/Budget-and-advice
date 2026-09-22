"""The studio environment map for the figure stages.

The reveal, the Hall of Ka's altar and the collection's Stage lit their
figures with four lights and no environment (2026-09-18): a metal marked by
the surface shader had nothing to reflect, and the shadow side of a figure
was whatever the ambient gave it, flat. This writes one small equirectangular
image — a cool sky above, a warm cream horizon, a warm dark ground below, and
two soft softbox highlights high on the left and right so gold shows a shape
in its reflection — for `scene.lightingEnvironment.contents`. It is LDR (a
PNG), which SceneKit accepts, at an intensity the stages set (about 0.6).

    python3 tools/studio_ibl.py            # writes Pantheon/Resources/Stage/studio_ibl.png
"""
from pathlib import Path
import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "Pantheon" / "Resources" / "Stage" / "studio_ibl.png"

W, H = 512, 256
SKY = np.array([0.80, 0.86, 0.96])      # a cool, quiet sky (0.72/0.80/0.92 until 2026-09-22)
HORIZON = np.array([0.93, 0.88, 0.78])  # the cream of the temple
GROUND = np.array([0.36, 0.30, 0.22])   # warm dark stone under the figure


def main():
    v = np.linspace(0, 1, H)[:, None]            # 0 at the zenith, 1 at the nadir
    u = np.linspace(0, 1, W)[None, :]
    # Sky to horizon over the upper half, horizon to ground over the lower.
    upper = np.clip(v / 0.5, 0, 1)
    lower = np.clip((v - 0.5) / 0.5, 0, 1)
    column = np.where(v[..., None] < 0.5,
                      SKY[None, None, :] * (1 - upper[..., None]) + HORIZON[None, None, :] * upper[..., None],
                      HORIZON[None, None, :] * (1 - lower[..., None]) + GROUND[None, None, :] * lower[..., None])
    img = np.repeat(column, W, axis=1)            # (H, W, 3)
    # Two softboxes, high left and high right, warm and soft: what a gold
    # bracer reflects. Gaussian blobs in equirect space.
    # Brighter since 2026-09-22 (0.55 and 0.40 before): gold reflected
    # nothing worth the name and read as tan paint.
    for cu, cv, amp in ((0.30, 0.22, 0.95), (0.72, 0.26, 0.72)):
        du = np.minimum(np.abs(u - cu), 1 - np.abs(u - cu))
        blob = np.exp(-((du / 0.09) ** 2 + ((v - cv) / 0.10) ** 2))
        img = img + amp * blob[..., None] * np.array([1.0, 0.96, 0.88])[None, None, :]
    img = np.clip(img, 0, 1)
    OUT.parent.mkdir(parents=True, exist_ok=True)
    Image.fromarray((img * 255).astype(np.uint8), "RGB").save(OUT, optimize=True)
    print(f"wrote {OUT.relative_to(ROOT)} {W}x{H}")


if __name__ == "__main__":
    main()
