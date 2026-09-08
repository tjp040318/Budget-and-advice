#!/usr/bin/env python3
"""
Converts one glTF binary (.glb) into a canonical .usdz at full resolution.

    python3 tools/glb2usd.py Art/Models/sekhmet.glb [--out sekhmet.usdz] [--height 2.0]

This is `tools/mesh.py <file.glb>` without decimation, kept as its own command
because "convert this file and let me look at it" is a step people take before
"ship it". All the work is in tools/character.py; see tools/mesh.py for the
family pipeline, which reads .glb sources directly.
"""

import argparse, sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import character  # noqa: E402
from mesh import roster_height  # noqa: E402


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("source", help="a .glb file")
    ap.add_argument("--out", help="output .usdz (default: beside the source)")
    ap.add_argument("--height", type=float, help="metres; default from UnitDatabase.swift, else 1.9")
    ap.add_argument("--animation", type=int, default=0, help="which animation to convert when a file has several")
    ap.add_argument("--fps", type=int, default=30)
    ap.add_argument("--keep-root-motion", action="store_true")
    a = ap.parse_args()

    src = Path(a.source)
    char = character.read_glb(src, animation_index=a.animation, fps=a.fps)
    print(f"{src.name}")
    character.describe(char)
    character.canonicalise(char, height=a.height or roster_height(char.name) or 1.9, lock_root=not a.keep_root_motion)
    character.ground_animation(char)
    out = Path(a.out) if a.out else src.with_suffix(".usdz")
    size = character.write_usdz(char, out)
    print(f"  -> {out}   {char.tris:,} tris  {size / 1048576:.2f} MB")
    return 1 if character.verify(out)["problems"] else 0


if __name__ == "__main__":
    sys.exit(main())
