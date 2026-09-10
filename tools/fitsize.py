#!/usr/bin/env python3
"""Resize a painting to an exact pixel size.

The nine-slice menu kit needs this. `Chrome`'s insets (31 points on a panel's
every side, 47 at a gold button's ends) are measured against the file's own
dimensions, so a texture that arrives 1024 wide where the old one was 512
silently halves every inset and the ornament lands in the wrong place. The
painter is asked for whatever size it is happy with; this puts the result on
the number the code expects.
"""
import sys
from PIL import Image

if len(sys.argv) != 5:
    sys.exit("usage: fitsize.py <src> <dst> <width> <height>")
src, dst, width, height = sys.argv[1], sys.argv[2], int(sys.argv[3]), int(sys.argv[4])
Image.open(src).convert("RGB").resize((width, height), Image.LANCZOS).save(dst)
print(f"{src} -> {dst}  {width}x{height}")
