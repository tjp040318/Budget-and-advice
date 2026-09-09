#!/bin/bash
# Launches Meshy image-to-3D + rig + six clips for a list of "asset:concept:height:palette" specs.
# usage: wave_launch.sh "ares2:Art/Concepts/x.png:2.1:bronze, crimson" ...
cd /home/user/Budget-and-advice
S=${S:-/tmp/pantheon-batch}; mkdir -p "$S"
for spec in "$@"; do
  IFS=: read -r asset concept height palette <<< "$spec"
  nohup python3 tools/meshy.py generate "$asset" --image "$concept" --height "$height" \
    --texture-prompt "hand-painted stylised mobile game character textures, cel-shaded with crisp baked highlights, $palette palette, no photo realism" \
    > "$S/meshy_$asset.log" 2>&1 &
  echo "launched $asset"
done
