#!/bin/bash
# Cards for batch 4 (Rome and the Jade Court): an ember base edited from each
# concept, four element recolours, and for the 4* and 5* families an awakened
# edit of each. Skips existing cards. About 170 images for the whole batch
# (twenty families' five cards, then fourteen families' five awakened cards),
# which fits one of Gemini's 250-a-day quotas if the concepts are already
# painted; base cards come before awakened ones (BASE_ONLY=1 paints every
# family's five and stops there). A family joins the gacha pool the moment
# its five cards land (`hasShippedArt`), and the pantheon's banner appears
# with it.
cd "$(dirname "$0")/../.."
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
have() { [ -s "$1.jpg" ] || [ -s "$1.png" ]; }   # a painting ships as JPEG (tools/shrink_art.py)
gen() { python3 tools/genart.py --prompt "$1" --ref "$2" --out "$3" --size 1024x1024 >/dev/null 2>&1; }
family() { # name facing awakened(0/1)
  name=$1; facing=$2; awakened=$3
  [ -s "Art/Concepts/${name}_sw.png" ] || { echo "no concept for $name"; return; }
  base="$OUT/portrait_${name}_ember.png"
  if ! have "$OUT/portrait_${name}_ember"; then
    gen "${CARD/FACING/$facing} $EMBER" "Art/Concepts/${name}_sw.png" "$base" && echo "ok $name ember" || { echo "FAILED $name ember"; return; }
  fi
  # The four recolours are edits of the ember card, which is a JPEG once
  # shrink_art.py has run over it (genart.py reads either).
  [ -s "$base" ] || base="$OUT/portrait_${name}_ember.jpg"
  for el in tide gale radiance umbra; do
    out="$OUT/portrait_${name}_${el}.png"
    have "$OUT/portrait_${name}_${el}" || { gen "${RECOLOUR[$el]}" "$base" "$out" && echo "ok $name $el" || echo "FAILED $name $el"; }
  done
  [ "$awakened" = 1 ] || return
  [ "${BASE_ONLY:-0}" = 1 ] && return   # BASE_ONLY=1: every family's five cards first, awakened later
  for el in ember tide gale radiance umbra; do
    src="$OUT/portrait_${name}_${el}.png"; [ -s "$src" ] || src="$OUT/portrait_${name}_${el}.jpg"
    out="$OUT/portrait_${name}_${el}_awakened.png"
    [ -s "$src" ] || continue
    have "$OUT/portrait_${name}_${el}_awakened" || { gen "$AWAKEN" "$src" "$out" && echo "ok $name $el awakened" || echo "FAILED $name $el awakened"; }
  done
}
L="three-quarter left"; R="three-quarter right"; F="the viewer directly"
# The two dragons are the 5* and the 4* whose card is a head-and-shoulders
# of the creature; the CARD prompt's "upper body and head" reads the same.
( family mars "$L" 1; family minerva "$R" 1; family neptune "$F" 1; family pluto "$L" 1; family diana "$R" 1 ) &
( family mercury "$F" 1; family bellona "$L" 1; family centurion "$R" 0; family gladiator "$F" 0; family vestal "$L" 0 ) &
( family sun_wukong "$R" 1; family azure_dragon "$F" 1; family nezha "$L" 1; family guan_yu "$R" 1; family chang_e "$F" 1 ) &
( family nuwa "$L" 1; family dragon_king "$R" 1; family fox_spirit "$F" 0; family jiangshi "$L" 0; family terracotta_soldier "$R" 0 ) &
wait
echo portraits-batch4-done
# The paintings ship as JPEG (tools/shrink_art.py); genart.py writes PNG, so
# convert whatever this run added before it is committed.
python3 tools/shrink_art.py
