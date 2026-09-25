#!/bin/bash
# Downloads a finished Meshy asset and ships it under the family name.
# usage: build_asset.sh <asset> <family> <height>
cd /home/user/Budget-and-advice
S=${S:-/tmp/pantheon-batch}; mkdir -p "$S"
{
  echo "== download $1"
  python3 tools/meshy.py download "$1" || { echo "DOWNLOAD FAILED $1"; exit 1; }
  echo "== build $1 -> $2 (height $3)"
  # 16,000 triangles with a 6,000 LOD at the full 2,048 texture since
  # 2026-09-17 (the owner: "Every family, size is fine").
  python3 tools/mesh.py "$1" --as "$2" --height "$3" --tris 16000 --lod 6000 --lod-texture 2048 || { echo "BUILD FAILED $1"; exit 1; }
  # The standing idle the stages play, built from the rig's own bind pose by
  # tools/natural_idle.py (2026-09-25; it was the combat idle stood up by
  # tools/stand_idle.py since 2026-09-18), after the ship because a re-shipped
  # base can change the bind; a calm family (motion_palette.CALM) wears it as
  # its battle stance too, and a held family keeps its stood guard. A family
  # the tool refuses (no motion_palette.ARCHETYPE row, a guard) gets the guard
  # stood up, loudly, so the stages still have an idle that binds.
  python3 tools/natural_idle.py ship "$2" --bundle Pantheon/Resources/Models --calm-stances --jobs 1 || {
    echo "NATURAL IDLE REFUSED for $2: the guard stood up instead - fix it and re-run tools/natural_idle.py ship $2"
    python3 tools/stand_idle.py "$2" || echo "no standing idle for $2"
  }
  echo "== preview $2"
  python3 tools/preview.py --sheet "$2" --out "$S/sheet_$2.jpg" || echo "PREVIEW FAILED $2"
  echo "== done $1"
} > "$S/build_$1.log" 2>&1
echo "built $1 -> $2: $(tail -n 1 $S/build_$1.log)"
