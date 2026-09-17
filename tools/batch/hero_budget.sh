#!/usr/bin/env bash
# The hero tier re-shipped at the budgets the fight deserves (2026-09-17,
# Docs/PLAN.md *Graphics*): 16,000 triangles for the menus, a 6,000-triangle
# LOD at the full 2,048 texture for the battle, the clip carriers left alone.
# Zeus went first (run 174 judged it); this runs the rest, one family at a
# time, and writes each family's log beside a marker so a re-run skips what
# is done. About a minute and a half a family here.
#
#   bash tools/batch/hero_budget.sh            # every hero family
#   bash tools/batch/hero_budget.sh anubis     # one
set -u
cd "$(dirname "$0")/../.."
S=${HERO_BUDGET_DIR:-/tmp/hero_budget}   # logs and markers outside the repo
mkdir -p "$S"
# source asset -> roster name
FAMILIES="anubis_hd:anubis sekhmet_hd:sekhmet thoth_hd:thoth shabti_hd:shabti ares_hd:ares heracles_hd:heracles perseus_hd:perseus hoplite_hd:hoplite satyr_hd:satyr harpy_hd:harpy ares_awakened:ares_awakened zeus_awakened:zeus_awakened sekhmet_awakened:sekhmet_awakened boss_colossus:boss_colossus boss_unwrapped_king:boss_unwrapped_king"
for pair in $FAMILIES; do
  src=${pair%%:*}; name=${pair##*:}
  if [ $# -gt 0 ] && [ "$1" != "$name" ]; then continue; fi
  if [ -f "$S/$name.done" ]; then echo "$name: done already"; continue; fi
  if [ ! -f "Art/Models/$src.glb" ] && [ ! -f "Art/Models/$src.usdz" ]; then echo "$name: no source $src in Art/Models; skipped"; continue; fi
  echo "$(date -u +%T) $name <- $src"
  if python3 tools/mesh.py "$src" --as "$name" --tris 16000 --lod 6000 --lod-texture 2048 --no-clips > "$S/$name.log" 2>&1; then
    touch "$S/$name.done"
    grep -E "^  -> |every file verified" "$S/$name.log"
  else
    echo "  FAILED: $(tail -n 3 "$S/$name.log" | tr '\n' ' ')"
  fi
done
echo "$(date -u +%T) done; $(ls $S/*.done 2>/dev/null | wc -l) families re-shipped"
