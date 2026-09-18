#!/bin/bash
# Paints the serious concepts (tools/batch/serious_roster.py -> serious_concepts.tsv)
# through Meshy's painter in the credits the owner bought — nano-banana-pro,
# the same Google model that painted every chibi concept, 9 credits a picture
# (measured on Ares, 2026-09-18) — never through Gemini's own key (paused,
# $10 a month). Skips what exists. Judge a sheet (serious_sheet.py) before
# the wave spends 59 on each mesh.
#   bash tools/batch/serious_concepts.sh [N]     # the next N missing, in roster order (default 8)
cd "$(dirname "$0")/../.."
source tools/batch/serious_style.sh
n=${1:-8}; done_n=0
while IFS=$'\t' read -r family sentence; do
  [ -z "$family" ] && continue
  out="Art/Concepts/${family}_serious_sw.png"
  [ -s "$out" ] && continue
  [ "$done_n" -ge "$n" ] && break
  echo "$(date -u +%T) painting $family"
  if python3 tools/meshy.py picture "${family}_serious" --prompt "$SERIOUS_STYLE $sentence $SERIOUS_AVOID" \
       --model nano-banana-pro --out "$out" --price 9 --floor 500 > "/tmp/pantheon-batch/picture_$family.log" 2>&1 && [ -s "$out" ]; then
    done_n=$((done_n + 1)); echo "  ok $family ($(stat -c %s "$out") bytes)"
  else
    echo "  FAILED $family: $(grep -m1 -iE 'error|balance|floor' "/tmp/pantheon-batch/picture_$family.log")"
    grep -q "floor" "/tmp/pantheon-batch/picture_$family.log" && break
  fi
done < tools/batch/serious_concepts.tsv
echo "$(date -u +%T) painted $done_n; balance $(python3 tools/meshy.py balance | tail -1)"
