#!/bin/bash
# Downloads a finished Meshy asset and ships it under the family name.
# usage: build_asset.sh <asset> <family> <height>
cd /home/user/Budget-and-advice
S=${S:-/tmp/pantheon-batch}; mkdir -p "$S"
{
  echo "== download $1"
  python3 tools/meshy.py download "$1" || { echo "DOWNLOAD FAILED $1"; exit 1; }
  echo "== build $1 -> $2 (height $3)"
  python3 tools/mesh.py "$1" --as "$2" --height "$3" || { echo "BUILD FAILED $1"; exit 1; }
  echo "== preview $2"
  python3 tools/preview.py --sheet "$2" --out "$S/sheet_$2.jpg" || echo "PREVIEW FAILED $2"
  echo "== done $1"
} > "$S/build_$1.log" 2>&1
echo "built $1 -> $2: $(tail -n 1 $S/build_$1.log)"
