#!/bin/bash
# Every battle and dungeon backdrop repainted at 4K from its own file (the
# owner, 2026-09-17: "All" of the Gemini batches, the 4K backdrops among
# them, about 24 cents each): an edit pass that keeps the composition and
# adds the painted detail a 1K generation never had. The 4K source is kept
# as Art/Backdrops/<name>_4k.jpg; the bundle ships the same 2048 size it
# always did, fitted down from the 4K (a phone never shows more, and a 4K
# texture is 67 MB of GPU memory). The island and the Hall of Ka are left
# alone: their anchors were measured on the paintings, and an edit pass
# drifts a little. Skips what is done.
#   bash tools/batch/backdrops_4k.sh [name ...]
cd /home/user/Budget-and-advice
PROMPT="Repaint this exact painting at a much higher resolution with much finer painted detail. Keep the composition, the horizon, every structure, figure, colour and the light exactly where they are: this must read as the same painting, only sharper, with finer brushwork, visible texture in the stone, sand, water, foliage and cloud, crisp edges on the architecture and more detail in the distance. No text, no frame, no border, no new elements."
mkdir -p /tmp/pantheon-batch/4k Art/Backdrops
names=("$@")
[ ${#names[@]} -eq 0 ] && for f in Pantheon/Resources/Portraits/*_bg.jpg; do names+=("$(basename "$f" .jpg)"); done
for name in "${names[@]}"; do
  case "$name" in island_bg|hall_of_ka_bg) continue;; esac
  f="Pantheon/Resources/Portraits/$name.jpg"
  [ -s "$f" ] || { echo "no $f"; continue; }
  [ -s "Art/Backdrops/${name}_4k.jpg" ] && { echo "have $name"; continue; }
  size=$(python3 -c "from PIL import Image; im=Image.open('$f'); print(f'{im.width}x{im.height}')")
  if python3 tools/genart.py --ref "$f" --resolution 4K --size "$size" --raw "/tmp/pantheon-batch/4k/${name}_raw.png" --out "/tmp/pantheon-batch/4k/${name}.png" --prompt "$PROMPT" >/dev/null 2>&1; then
    python3 - "$name" <<'PY'
import sys
from PIL import Image
name = sys.argv[1]
raw = Image.open(f"/tmp/pantheon-batch/4k/{name}_raw.png").convert("RGB")
raw.save(f"Art/Backdrops/{name}_4k.jpg", "JPEG", quality=92, optimize=True)
fitted = Image.open(f"/tmp/pantheon-batch/4k/{name}.png").convert("RGB")
fitted.save(f"Pantheon/Resources/Portraits/{name}.jpg", "JPEG", quality=92, optimize=True)
print(f"ok {name}  raw {raw.size}  shipped {fitted.size}")
PY
  else
    echo "FAILED $name"
  fi
done
echo "backdrops_4k done"
