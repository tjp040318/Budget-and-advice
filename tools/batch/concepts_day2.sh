#!/bin/bash
# The two concepts Gemini's quota did not allow on the day: an original
# trickster in place of a named god (the name came back as an actor's
# photo), and Hades redrawn in the A-pose Meshy's rigger needs.
cd "$(dirname "$0")/../.."
STYLE="Full-body character concept for a stylised mobile gacha RPG in the manner of Summoners War: about five heads tall with a slightly large head, big hands and feet, chunky simplified shapes and a strong readable silhouette, hand-painted cel-shaded textures with crisp highlights, a strict palette of three colours plus black and skin. Standing in a relaxed A-pose facing the viewer, feet apart and both feet fully visible, arms lowered a little away from the body with a clear gap between each arm and the torso, any weapon held in one hand tight against the outside of the leg. The whole figure is visible head to toe and centred on a plain flat light-grey background with a plain light-grey floor, soft even studio light, no cast shadows, no text, no frame, one character only."
AVOID="Avoid: realistic proportions, photorealism, a real person or actor, anything standing beside the figure, arms crossed or held in front of the body, a weapon held out away from the body, a cape or cloth flying away from the body, a floor-length robe hiding the feet, multiple characters, cropping, a dramatic background, text, watermark."
gen() { out="Art/Concepts/$1_sw.png"; [ -s "$out" ] && { echo "have $1"; return; }; python3 tools/genart.py --prompt "$STYLE $2 $AVOID" --out "$out" --size 1024x1024 >/dev/null 2>&1 && echo "ok $1" || echo "FAILED $1"; }
gen loki "A sly fox-faced Norse trickster: a lean grinning young man with sharp features, slicked-back black hair and a bronze helmet with two long curved horns, a green tunic with gold knotwork trim under a short dark leather coat that hangs straight down, a curved dagger held against the outside of his right leg. Palette green, gold, black."
gen hades "Hades, Greek god of the underworld, as an original cartoon character: a pale bearded man with a dark iron crown, a black and violet chiton ending above the knees over dark greaves, both sandalled feet visible, a dull gold pectoral, a two-pronged bident held upright tight against the outside of his right leg. Palette black, violet, dull gold."
gen bastet "Bastet, Egyptian cat goddess, as an original cartoon character: a slender dark-skinned woman with a human face, sharp cat-like eyes and cat ears rising from her black bobbed hair, gold hoop earrings, a fitted emerald green and gold dress ending above the knees, a wide gold collar, gold anklets, bare feet, empty open hands at her sides. Palette black, emerald green, gold."

# The scroll banners and the world map, 1284x800 and 2048x1152 like the ones
# they sit beside. Leave the lower third of a banner quiet: the pull buttons.
BANNER="Mobile gacha summon banner splash, DESC, dramatic backlight, cinematic, ornate, hand-painted stylised mobile game art, the lower third of the image calm and uncluttered, no text, no logo, no UI"
paint() { out="Pantheon/Resources/Portraits/$1.png"; { [ -s "$out" ] || [ -s "Pantheon/Resources/Portraits/$1.jpg" ]; } && { echo "have $1"; return; }; python3 tools/genart.py --prompt "$2" --out "$out" --size "$3" >/dev/null 2>&1 && echo "ok $1" || echo "FAILED $1"; }
paint banner_unknown "${BANNER/DESC/a plain clay tablet scroll glowing faintly on a stone altar among rows of sandstone shabti figurines, dusty amber and grey}" 1284x800
paint banner_divine "${BANNER/DESC/a golden scroll bound in light floating above the silhouettes of gods on a mountaintop, blinding white-gold and violet}" 1284x800
paint banner_light_dark "${BANNER/DESC/a scroll split down the middle, one half white-gold sunlight and one half violet-black night full of stars}" 1284x800
paint banner_fire "${BANNER/DESC/a burning scroll held over a volcanic forge, red and orange fire, embers rising}" 1284x800
paint banner_water "${BANNER/DESC/a scroll of sea-green light drifting over dark deep water with foam and bubbles}" 1284x800
paint banner_wind "${BANNER/DESC/a scroll caught in a jade-green whirlwind over a cliff top, leaves and feathers flying}" 1284x800
paint world_map "A painted fantasy world map for a mobile game, seen from above like an old chart but in full colour: a desert land with pyramids and a river on the left, a Greek mountain with white temples in the middle, a Norse fjord with snowy peaks and a great tree on the right, dotted roads between them, sea all around with sea monsters at the edges, hand-painted stylised mobile game art, no text, no labels, no borders" 2048x1152
echo concepts-day2-done
# The paintings ship as JPEG (tools/shrink_art.py); genart.py writes PNG, so
# convert whatever this run added before it is committed.
python3 tools/shrink_art.py
