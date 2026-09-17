#!/usr/bin/env bash
# Every family that is not in the hero tier re-shipped at the hero budgets
# (2026-09-17, the owner: "Every family, size is fine"): 16,000 triangles
# for the menus and a 6,000-triangle LOD at the full 2,048 texture for the
# fight, the clip carriers left alone. About four seconds a family here;
# a marker per family so a re-run skips what is done.
#   bash tools/batch/all_budget.sh          # everything not yet done
set -u
cd "$(dirname "$0")/../.."
S=${ALL_BUDGET_DIR:-/tmp/all_budget}
mkdir -p "$S"
HERO=" anubis sekhmet thoth shabti ares heracles perseus hoplite satyr harpy zeus ares_awakened zeus_awakened sekhmet_awakened boss_colossus boss_unwrapped_king "
for marker in Art/Models/*.shipped; do
  src=$(basename "$marker" .shipped)
  name=$src
  if [ ! -f "Pantheon/Resources/Models/$name.usdz" ]; then name=${src%_hd}; fi
  if [ ! -f "Pantheon/Resources/Models/$name.usdz" ]; then name=$(echo "$src" | sed -E 's/_v[0-9]+$//'); fi
  if [ ! -f "Pantheon/Resources/Models/$name.usdz" ]; then echo "$src: no shipped file to replace; skipped"; continue; fi
  case "$HERO" in *" $name "*) continue;; esac
  [ -f "$S/$name.done" ] && continue
  if [ ! -f "Art/Models/$src.glb" ] && [ ! -f "Art/Models/$src.usdz" ]; then echo "$name: no source $src; skipped"; continue; fi
  echo "$(date -u +%T) $name <- $src"
  if python3 tools/mesh.py "$src" --as "$name" --tris 16000 --lod 6000 --lod-texture 2048 --no-clips > "$S/$name.log" 2>&1; then
    touch "$S/$name.done"; grep -E "every file verified" "$S/$name.log"
  else
    echo "  FAILED: $(tail -n 3 "$S/$name.log" | tr '\n' ' ')"
  fi
done
echo "$(date -u +%T) done; $(ls $S/*.done 2>/dev/null | wc -l) families re-shipped"
