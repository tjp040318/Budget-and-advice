#!/bin/bash
# Cards for batch 3: an ember base edited from each concept, four element
# recolours, and for the 4* and 5* families an awakened edit of each. Skips
# existing cards. About 300 images for the whole batch, so it spans two of
# Gemini's 250-a-day quotas; base cards come before awakened ones.
cd /home/user/Budget-and-advice
OUT=Pantheon/Resources/Portraits
CARD="Edit this image into a mobile gacha RPG character portrait card of the SAME character in the SAME painted stylised look with the same level of detail: upper body and head only, filling the square frame with the head in the upper two thirds, facing FACING, dramatic rim light from behind, a dark background with a soft radial glow behind the head, rich saturated colour, no text, no frame, no border, one character."
EMBER="The costume's gold and warm metal glow molten orange with ember cracks, warm firelight; this is the fire form."
declare -A RECOLOUR=(
  [tide]="Edit this image: keep everything identical except that every gold, bronze or warm-metal part of the costume becomes deep teal and turquoise metal, the glow and rim light turn cool underwater blue-green. Same character, same pose, same style."
  [gale]="Edit this image: keep everything identical except that every gold, bronze or warm-metal part of the costume becomes pale jade green and silver, the glow and rim light turn cold jade. Same character, same pose, same style."
  [radiance]="Edit this image: keep everything identical except that every gold, bronze or warm-metal part of the costume becomes luminous white-gold, with a bright warm halo of light from above. Same character, same pose, same style."
  [umbra]="Edit this image: keep everything identical except that every gold, bronze or warm-metal part of the costume becomes deep violet and black metal, the glow and rim light turn cold violet with shadow smoke curling from the shoulders. Same character, same pose, same style."
)
AWAKEN="Edit this image into the AWAKENED form of the same character for a mobile gacha RPG card, in the same painted stylised look, same pose, same crop, same facing: the costume becomes a richer ceremonial version of itself with more ornate armour and jewellery, glowing runic markings on the metal and skin in the same colour as the existing glow, the eyes glowing that colour, a bright halo or crown of light behind the head, wisps of that light rising off the shoulders. Still clearly the same character. No text, no frame, no border."
gen() { python3 tools/genart.py --prompt "$1" --ref "$2" --out "$3" --size 1024x1024 >/dev/null 2>&1; }
family() { # name facing awakened(0/1)
  name=$1; facing=$2; awakened=$3
  [ -s "Art/Concepts/${name}_sw.png" ] || { echo "no concept for $name"; return; }
  base="$OUT/portrait_${name}_ember.png"
  if [ ! -s "$base" ]; then
    gen "${CARD/FACING/$facing} $EMBER" "Art/Concepts/${name}_sw.png" "$base" && echo "ok $name ember" || { echo "FAILED $name ember"; return; }
  fi
  for el in tide gale radiance umbra; do
    out="$OUT/portrait_${name}_${el}.png"
    [ -s "$out" ] || { gen "${RECOLOUR[$el]}" "$base" "$out" && echo "ok $name $el" || echo "FAILED $name $el"; }
  done
  [ "$awakened" = 1 ] || return
  [ "${BASE_ONLY:-0}" = 1 ] && return   # BASE_ONLY=1: every family's five cards first, awakened later
  for el in ember tide gale radiance umbra; do
    src="$OUT/portrait_${name}_${el}.png"; out="$OUT/portrait_${name}_${el}_awakened.png"
    [ -s "$src" ] || continue
    [ -s "$out" ] || { gen "$AWAKEN" "$src" "$out" && echo "ok $name $el awakened" || echo "FAILED $name $el awakened"; }
  done
}
L="three-quarter left"; R="three-quarter right"; F="the viewer directly"
( family ra "$L" 1; family osiris "$R" 1; family ptah "$F" 1; family khnum "$L" 1; family nephthys "$R" 1; family maat "$F" 1; family serqet "$L" 1; family taweret "$R" 1; family anhur "$F" 1 ) &
( family bes "$L" 0; family medjay "$R" 0; family cobra_priestess "$F" 0; family hera "$L" 1; family hephaestus "$R" 1; family demeter "$F" 1; family dionysus "$L" 1; family aphrodite "$R" 1; family nike "$F" 1 ) &
( family achilles "$L" 1; family atalanta "$R" 0; family siren "$F" 0; family nymph "$L" 0; family baldr "$R" 1; family frigg "$F" 1; family surtr "$L" 1; family njord "$R" 1; family idunn "$F" 1 ) &
( family sif "$L" 1; family ullr "$R" 1; family vidar "$F" 1; family fenrir "$L" 1; family bragi "$R" 1; family einherjar "$F" 0; family shield_maiden "$L" 0; family light_elf "$R" 0; family dark_elf "$F" 0 ) &
wait
echo portraits-batch3-done
