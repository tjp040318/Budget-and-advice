#!/bin/bash
# Ships the serious remakes as they finish, every three minutes for up to
# eight hours: ship_wave.sh over serious_wave.txt (idempotent: .shipped
# markers), and for a god with bespoke motions, reapply_motions.sh once its
# family has shipped (a .motions marker beside the manifest).
#   nohup bash tools/batch/serious_shipper.sh > /tmp/pantheon-batch/shipper.log 2>&1 &
cd "$(dirname "$0")/../.."
declare -A DONOR=( [sekhmet]=sekhmet_m7 [anubis]=anubis_m7 [thoth]=thoth_m7 )
for i in $(seq 1 160); do
  bash tools/batch/ship_wave.sh tools/batch/serious_wave.txt 2>&1 | grep -E "SHIPPED|BUILD PROBLEM|FAILED"
  for fam in "${!DONOR[@]}"; do
    if [ -f "Art/Models/${fam}_serious.shipped" ] && [ ! -f "Art/Models/${fam}_serious.motions" ]; then
      echo "$(date -u +%T) motions $fam"
      bash tools/batch/reapply_motions.sh "${fam}_serious" "${DONOR[$fam]}" "$fam" > "/tmp/pantheon-batch/motions_${fam}.log" 2>&1 && touch "Art/Models/${fam}_serious.motions"
      tail -1 "/tmp/pantheon-batch/motions_${fam}.log"
    fi
  done
  sleep 180
done
