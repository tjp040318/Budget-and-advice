#!/bin/bash
# Launches every spec in a wave list (tools/batch/wave3.txt, remake_wave.txt)
# that has no manifest yet, in order, while the balance stays above a floor.
# usage: wave_run.sh <list> [floor]      (floor defaults to 2000, the owner's since 2026-09-11)
# A character costs 53: 30 for the image-to-3D when it is created, then 5
# for the rig and 3 per clip as those stages run, so every launch of this run
# still has 23 to charge when the next balance is read - that is counted.
cd /home/user/Budget-and-advice
list=$1; floor=${2:-2000}; per=53; later=23; launched=0
[ -s "$list" ] || { echo "no list $list"; exit 1; }
while IFS= read -r line; do
  [[ -z "$line" || "$line" == \#* ]] && continue
  asset=${line%%:*}
  IFS=: read -r _ concept height _ <<< "$line"
  [ -s "Art/Models/$asset.meshy.json" ] && { echo "have $asset (manifest exists)"; continue; }
  [ -s "$concept" ] || { echo "no concept for $asset ($concept)"; continue; }
  case "$height" in *[!0-9.]*|"") echo "bad height for $asset: '$height'"; continue;; esac
  bal=$(python3 tools/meshy.py balance 2>/dev/null | tail -1)
  need=$((floor + per + later * launched + 100))
  if ! [[ "$bal" =~ ^[0-9]+$ ]] || [ "$bal" -lt "$need" ]; then
    echo "STOP before $asset: balance ${bal:-unknown}, need $need (floor $floor + this one + what the $launched already launched still owe)"; break
  fi
  bash tools/batch/wave_launch.sh "$line"
  launched=$((launched + 1))
  sleep 20   # let the image-to-3D charge land before the next read
done < "$list"
echo "wave_run: launched $launched from $list"
