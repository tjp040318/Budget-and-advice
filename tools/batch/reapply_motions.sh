#!/bin/bash
# Carries a god's bespoke motions onto a NEW rig without Meshy (2026-09-18,
# 18:20): Meshy keeps a text-to-motion task about three days, so the 15th's
# fourteen were gone by the 18th and the Animation API had nothing to apply
# (the first version of this script found every task 404 and re-shipped the
# presets in silence). tools/retarget.py reads the motion off the ARCHIVE -
# Art/Motions/<family>_<clip>.motion.npz, written from the rigged clip GLB
# the day it was fetched - or, failing that, off the donor's clip GLB
# (Art/Models/<donor>_<clip>.glb), and puts it on the new rig's clip file;
# mesh.py then ships the three clips alone under the family's name.
#   bash tools/batch/reapply_motions.sh anubis_serious anubis_m7 anubis
#   CLIPS="attack_basic attack_heavy" bash tools/batch/reapply_motions.sh zeus_serious zeus_m7 zeus   # Zeus's ultimate is Meshy's own (its task lives)
cd "$(dirname "$0")/../.."
asset=$1; donor=$2; family=$3; S=${S:-/tmp/pantheon-batch}; mkdir -p "$S"
clips=${CLIPS:-attack_basic attack_heavy ultimate}; done_clips=""; failed=0
for clip in $clips; do
  archive="Art/Motions/${family}_${clip}.motion.npz"
  if [ -s "$archive" ]; then source="$archive"; elif [ -s "Art/Models/${donor}_${clip}.glb" ]; then source="Art/Models/${donor}_${clip}.glb"; else echo "no motion for $clip: neither $archive nor Art/Models/${donor}_${clip}.glb"; failed=1; continue; fi
  target="Art/Models/${asset}_${clip}.glb"
  [ -s "$target" ] || { echo "no clip file to write into: $target (download the asset first)"; failed=1; continue; }
  echo "== $asset $clip <- $source"
  if python3 tools/retarget.py "$source" "$target" --board "$S/retarget_${family}_${clip}.jpg" 2>&1 | grep -E "^  [0-9]|matched|wrote|archived|kept|board|joints|Error|error|not the same" ; then
    done_clips="$done_clips,$clip"
  else
    echo "  RETARGET FAILED $asset $clip"; failed=1
  fi
done
done_clips=${done_clips#,}
[ -n "$done_clips" ] && python3 tools/mesh.py "$asset" --as "$family" --only-clips "$done_clips" 2>&1 | tail -3
echo "== motions done $asset -> $family ($done_clips)$( [ $failed = 1 ] && echo '  WITH FAILURES')"
exit $failed
