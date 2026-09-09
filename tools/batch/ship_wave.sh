#!/bin/bash
# Ships every finished Meshy run in a wave list that is not shipped yet:
# build_asset.sh <asset> <family> <height> (download, mesh.py --as, preview
# sheet), then a marker Art/Models/<asset>.shipped so a rerun skips it.
# usage: ship_wave.sh <list>
cd /home/user/Budget-and-advice
S=${S:-/tmp/pantheon-batch}; mkdir -p "$S"
list=$1; shipped=0
while IFS= read -r line; do
  [[ -z "$line" || "$line" == \#* ]] && continue
  IFS=: read -r asset concept height palette kit family <<< "$line"
  family=${family:-$asset}
  [ -s "Art/Models/$asset.meshy.json" ] || { echo "not launched $asset"; continue; }
  [ -f "Art/Models/$asset.shipped" ] && { echo "shipped already $asset"; continue; }
  if python3 - "$asset" <<'PY'
import json, sys
m = json.load(open(f"Art/Models/{sys.argv[1]}.meshy.json"))
st = m["stages"]
clips = [k for k in st if k.startswith("clip:")]
need = ["image" if "image" in st else "refine", "rig"] + clips
ok = len(clips) >= 6 and all(st.get(k, {}).get("status") == "SUCCEEDED" for k in need)
sys.exit(0 if ok else 1)
PY
  then
    bash tools/batch/build_asset.sh "$asset" "$family" "$height"
    if grep -q "== done" "$S/build_$asset.log"; then
      touch "Art/Models/$asset.shipped"; shipped=$((shipped + 1)); echo "SHIPPED $asset -> $family ($height m); sheet $S/sheet_$family.jpg"
    else
      echo "BUILD PROBLEM $asset: $(grep -m1 -E "FAILED|Error|error" "$S/build_$asset.log")"
    fi
  else
    echo "unfinished $asset ($(python3 -c "
import json; m=json.load(open('Art/Models/$asset.meshy.json')); print(', '.join(f'{k} {v.get(\"status\")}' for k,v in m['stages'].items() if v.get('status')!='SUCCEEDED') or 'no failed stage; clips missing')"))"
  fi
done < "$list"
echo "ship_wave: shipped $shipped from $list"
