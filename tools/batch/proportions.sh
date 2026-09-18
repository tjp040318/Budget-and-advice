#!/usr/bin/env bash
# Every rigged character re-shipped through the proportion pass
# (character.PROPORTIONS["serious2"] since 2026-09-18, "serious" on 2026-09-17: the owner, "I honestly
# don't like the big hands and cartoony look"): head, hands and feet
# scaled down at their joints, thighs and shins lengthened, baked into
# the mesh, the clips re-shipped so their channels follow; the hero
# budgets throughout. The source for a family is the one its newest
# .shipped marker names, or the explicit map for the ones shipped by
# hand today. A marker per family so a re-run skips what is done.
#   bash tools/batch/proportions.sh            # everything not yet done
#   bash tools/batch/proportions.sh zeus ares  # just these
set -u
cd "$(dirname "$0")/../.."
S=${PROPORTIONS_DIR:-/tmp/proportions2}; mkdir -p "$S"
RECIPE=${PROPORTIONS_RECIPE:-serious2}   # character.PROPORTIONS; serious2 since 2026-09-18 (longer legs, narrower body)
# A family whose texture came back off its cards is graded on the way
# (character.GRADES): the Ares family, olive against two gold cards.
declare -A GRADE=( [ares]="--grade gold" [ares_awakened]="--grade gold" )
declare -A SRC=( [zeus]=zeus_m7 [sekhmet]=sekhmet_m7 [anubis]=anubis_m7 [ares]=ares_m7 [thoth]=thoth_m7
                 [neptune]=neptune_v2 [terracotta_soldier]=terracotta_soldier_v2 [hades]=hades_v2 [ptah]=ptah_v2
                 [sentinel]=sentinel_v2 [jotunn]=jotunn_v2 [bastet]=bastet_v3 [hathor]=hathor_v2 [thoth_awakened]=thoth_awakened_v2 )
source_for() {   # the newest shipped source for a family name
  local name=$1
  if [ -n "${SRC[$name]:-}" ]; then echo "${SRC[$name]}"; return; fi
  local best="" bestt=0
  for cand in "$name" "${name}_hd" "${name}"_v[0-9]*; do
    [ -f "Art/Models/$cand.glb" ] || [ -f "Art/Models/$cand.usdz" ] || continue
    local t=0
    [ -f "Art/Models/$cand.shipped" ] && t=$(stat -c %Y "Art/Models/$cand.shipped")
    [ "$t" -eq 0 ] && [ -f "Art/Models/$cand.glb" ] && t=$(( $(stat -c %Y "Art/Models/$cand.glb") / 2 ))
    if [ "$t" -gt "$bestt" ] || [ -z "$best" ]; then best=$cand; bestt=$t; fi
  done
  echo "$best"
}
names=("$@")
if [ ${#names[@]} -eq 0 ]; then
  for f in Pantheon/Resources/Models/*_idle_combat.usdz; do names+=("$(basename "$f" _idle_combat.usdz)"); done
fi
done_n=0
for name in "${names[@]}"; do
  [ -f "$S/$name.done" ] && continue
  src=$(source_for "$name")
  [ -z "$src" ] && { echo "$name: no source; skipped"; continue; }
  echo "$(date -u +%T) $name <- $src"
  if python3 tools/mesh.py "$src" --as "$name" --tris 16000 --lod 6000 --lod-texture 2048 --proportions "$RECIPE" ${GRADE[$name]:-} > "$S/$name.log" 2>&1 && python3 tools/stand_idle.py "$name" >> "$S/$name.log" 2>&1; then
    touch "$S/$name.done"; done_n=$((done_n + 1)); grep -E "proportions:|every file verified" "$S/$name.log" | tail -2
  else
    echo "  FAILED: $(grep -E 'PROBLEM|Error|Traceback' "$S/$name.log" | head -2 | tr '\n' ' ')"
  fi
done
echo "$(date -u +%T) done; $done_n re-shipped this run, $(ls $S/*.done 2>/dev/null | wc -l) in all"
