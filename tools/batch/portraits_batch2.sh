#!/bin/bash
# Cards for the third roster: an ember base edited from each concept, four
# element recolours, and for the 4* and 5* families an awakened edit of each.
cd /home/user/Budget-and-advice
OUT=Pantheon/Resources/Portraits
CARD="Edit this image into a mobile gacha RPG character portrait card of the SAME character in the SAME cel-shaded stylised look: upper body and head only, filling the square frame with the head in the upper two thirds, facing FACING, dramatic rim light from behind, a dark background with a soft radial glow behind the head, rich saturated colour, no text, no frame, no border, one character."
EMBER="The costume's gold and warm metal glow molten orange with ember cracks, warm firelight; this is the fire form."
declare -A RECOLOUR=(
  [tide]="Edit this image: keep everything identical except that every gold, bronze or warm-metal part of the costume becomes deep teal and turquoise metal, the glow and rim light turn cool underwater blue-green. Same character, same pose, same style."
  [gale]="Edit this image: keep everything identical except that every gold, bronze or warm-metal part of the costume becomes pale jade green and silver, the glow and rim light turn cold jade. Same character, same pose, same style."
  [radiance]="Edit this image: keep everything identical except that every gold, bronze or warm-metal part of the costume becomes luminous white-gold, with a bright warm halo of light from above. Same character, same pose, same style."
  [umbra]="Edit this image: keep everything identical except that every gold, bronze or warm-metal part of the costume becomes deep violet and black metal, the glow and rim light turn cold violet with shadow smoke curling from the shoulders. Same character, same pose, same style."
)
AWAKEN="Edit this image into the AWAKENED form of the same character for a mobile gacha RPG card, in the same cel-shaded stylised look, same pose, same crop, same facing: the costume becomes a richer ceremonial version of itself with more ornate armour and jewellery, glowing runic markings on the metal and skin in the same colour as the existing glow, the eyes glowing that colour, a bright halo or crown of light behind the head, wisps of that light rising off the shoulders. Still clearly the same character. No text, no frame, no border."
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
  for el in ember tide gale radiance umbra; do
    src="$OUT/portrait_${name}_${el}.png"; [ -s "$src" ] || src="$OUT/portrait_${name}_${el}.jpg"
    out="$OUT/portrait_${name}_${el}_awakened.png"
    [ -s "$src" ] || continue
    have "$OUT/portrait_${name}_${el}_awakened" || { gen "$AWAKEN" "$src" "$out" && echo "ok $name $el awakened" || echo "FAILED $name $el awakened"; }
  done
}
L="three-quarter left"; R="three-quarter right"; F="the viewer directly"
( family horus "$L" 1; family set "$R" 1; family scarab_knight "$F" 0; family athena "$L" 1; family apollo "$R" 1; family cyclops "$F" 0; family odin "$L" 1 ) &
( family isis "$R" 1; family sobek "$F" 1; family mummy "$L" 0; family poseidon "$R" 1; family artemis "$F" 1; family amazon "$L" 0; family thor "$R" 1 ) &
( family jackal_warrior "$F" 0; family hades "$L" 1; family hermes "$R" 1; family medusa "$F" 0; family freya "$L" 1; family tyr "$R" 1; family valkyrie "$F" 0 ) &
( family heimdall "$L" 1; family hel "$R" 1; family skadi "$F" 1; family draugr "$L" 0; family berserker "$R" 0; family frost_troll "$F" 0; family dwarf_smith "$L" 0; family minotaur "$R" 0 ) &
wait
echo portraits-batch2-done
# The paintings ship as JPEG (tools/shrink_art.py); genart.py writes PNG, so
# convert whatever this run added before it is committed.
python3 tools/shrink_art.py
