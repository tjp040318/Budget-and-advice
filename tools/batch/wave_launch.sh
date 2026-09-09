#!/bin/bash
# Launches Meshy image-to-3D + rig + six clips for a list of
# "asset:concept:height:palette[:kit[:family]]" specs (tools/batch/wave3.txt). The kit picks the attack clips
# (meshy.py CLIP_SETS): blade (the default; striker, duelist, warden), heavy
# (bruiser), caster (healer, oracle, trickster), archer (a marksman whose
# concept holds a bow).
# usage: wave_launch.sh "ares2:Art/Concepts/x.png:2.1:bronze, crimson:blade" ...
cd /home/user/Budget-and-advice
S=${S:-/tmp/pantheon-batch}; mkdir -p "$S"
# The texture prompt asks for painted detail rather than flat cel shading:
# the first roster's "cel-shaded with crisp baked highlights" came back as
# three flat tones per part and read as cartoony on the phone.
TEXTURE="hand-painted stylised mobile game character textures with fine detail: engraved and embossed metal with worn bright edges, layered cloth with a woven weave and stitched trim, hair and fur in defined strands, leather with grain, skin with subtle warmth, clear contrast between metal, cloth, leather and skin, soft natural shading with painted highlights, rich saturated colour, stylised rather than photoreal"
for spec in "$@"; do
  IFS=: read -r asset concept height palette kit family <<< "$spec"   # family: the roster name, used by ship_wave.sh
  nohup python3 tools/meshy.py generate "$asset" --image "$concept" --height "$height" --clips "${kit:-blade}" \
    --texture-prompt "$TEXTURE, $palette palette" \
    > "$S/meshy_$asset.log" 2>&1 &
  echo "launched $asset (${kit:-blade})"
done
