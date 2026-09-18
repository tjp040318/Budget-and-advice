#!/bin/bash
# Re-applies a god's bespoke motions (text-to-motion tasks that still live at
# Meshy, in the <donor> manifest's motion:<clip> stages) to a NEW rig, at the
# 3 credits the application costs rather than the 13 a new motion would:
# the stages are copied into the new asset's manifest, meshy.py motion finds
# each one finished under the same sentence and only applies it, then the
# clips are downloaded and shipped alone under the family's name.
#   bash tools/batch/reapply_motions.sh zeus_serious zeus_m7 zeus
cd "$(dirname "$0")/../.."
asset=$1; donor=$2; family=$3; S=${S:-/tmp/pantheon-batch}; mkdir -p "$S"
python3 - "$asset" "$donor" <<'PY'
import json, sys
asset, donor = sys.argv[1], sys.argv[2]
m = json.load(open(f"Art/Models/{asset}.meshy.json")); d = json.load(open(f"Art/Models/{donor}.meshy.json"))
n = 0
for k, st in d["stages"].items():
    if k.startswith("motion:") and st.get("status") == "SUCCEEDED" and k not in m["stages"]:
        m["stages"][k] = st; n += 1
json.dump(m, open(f"Art/Models/{asset}.meshy.json", "w"), indent=1)
print(f"{asset}: {n} motion stage(s) copied from {donor}")
PY
for clip in attack_basic attack_heavy ultimate; do
  # Tab-separated: the sentence has spaces, and a plain read split it at the first one.
  IFS=$'\t' read -r prompt duration mode < <(python3 -c "
import json; st=json.load(open('Art/Models/$donor.meshy.json'))['stages'].get('motion:$clip',{}).get('request',{})
print(st.get('prompt','').replace('\t',' ') + '\t' + str(st.get('duration',3.0)) + '\t' + st.get('mode','prime'))")
  [ -z "$prompt" ] && { echo "no motion for $clip in $donor"; continue; }
  echo "== $asset $clip"
  python3 tools/meshy.py motion "$asset" "$clip" --prompt "$prompt" --duration "$duration" --mode "$mode" --floor 500 2>&1 | tail -3
done
python3 tools/meshy.py download "$asset" --force 2>&1 | tail -2
python3 tools/mesh.py "$asset" --as "$family" --only-clips attack_basic,attack_heavy,ultimate 2>&1 | tail -3
echo "== motions done $asset -> $family"
