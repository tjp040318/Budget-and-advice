#!/bin/bash
# Launches and ships the unrigged beasts of a list (tools/batch/beasts4.txt):
# image-to-3D from the concept, stopped after the refine stage (30 credits,
# no rig, no clips), then downloaded and shipped with prop.py under the
# family name at the roster height. A shipped beast has no clips and the
# game moves it procedurally, as it does the Hydra.
# usage: beast_wave.sh <list> [floor]     (floor defaults to 2000)
cd /home/user/Budget-and-advice
S=${S:-/tmp/pantheon-batch}; mkdir -p "$S"
list=$1; floor=${2:-2000}; per=30; launched=0; shipped=0
[ -s "$list" ] || { echo "no list $list"; exit 1; }
TEXTURE="hand-painted stylised mobile game creature textures with fine detail: scales with worn bright edges, layered fins and whiskers, horn and claw with grain, soft natural shading with painted highlights, rich saturated colour, stylised rather than photoreal"
while IFS= read -r line; do
  [[ -z "$line" || "$line" == \#* ]] && continue
  IFS=: read -r asset concept height palette <<< "$line"
  if [ -f "Art/Models/$asset.shipped" ]; then echo "shipped already $asset"; continue; fi
  if [ ! -s "Art/Models/$asset.meshy.json" ]; then
    [ -s "$concept" ] || { echo "no concept for $asset ($concept)"; continue; }
    bal=$(python3 tools/meshy.py balance 2>/dev/null | tail -1)
    need=$((floor + per + 100))
    if ! [[ "$bal" =~ ^[0-9]+$ ]] || [ "$bal" -lt "$need" ]; then
      echo "STOP before $asset: balance ${bal:-unknown}, need $need"; break
    fi
    nohup python3 tools/meshy.py generate "$asset" --image "$concept" --height "$height" --until refine \
      --texture-prompt "$TEXTURE, $palette palette" > "$S/meshy_$asset.log" 2>&1 &
    launched=$((launched + 1)); echo "launched $asset (unrigged)"; sleep 20
    continue
  fi
  if python3 - "$asset" <<'PY'
import json, sys
m = json.load(open(f"Art/Models/{sys.argv[1]}.meshy.json"))
sys.exit(0 if m["stages"].get("image", {}).get("status") == "SUCCEEDED" else 1)
PY
  then
    python3 tools/meshy.py download "$asset" --include-unrigged > "$S/dl_$asset.log" 2>&1 || { echo "DOWNLOAD FAILED $asset"; continue; }
    if python3 tools/prop.py "$asset" --as "$asset" --height "$height" --tris 6000 > "$S/build_$asset.log" 2>&1; then
      python3 tools/preview.py "Pantheon/Resources/Models/$asset.usdz" --out "$S/sheet_$asset.jpg" >/dev/null 2>&1 || true
      touch "Art/Models/$asset.shipped"; shipped=$((shipped + 1)); echo "SHIPPED $asset ($height m); look at $S/sheet_$asset.jpg"
    else
      echo "BUILD FAILED $asset: $(tail -n 2 "$S/build_$asset.log" | tr '\n' ' ')"
    fi
  else
    echo "unfinished $asset"
  fi
done < "$list"
echo "beast_wave: launched $launched, shipped $shipped from $list"
