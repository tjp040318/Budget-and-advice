#!/bin/bash
# The Labyrinth's own art: the two boss concepts (A-pose, for Meshy's rigger),
# their cards, and a painting per relic dungeon. Seven images. Everything skips
# what already exists, so it can be rerun after a quota or a network failure.
cd "$(dirname "$0")/../.."
OUT=Pantheon/Resources/Portraits

STYLE="Full-body character concept for a stylised mobile gacha RPG in the manner of Summoners War: about five heads tall with a slightly large head, big hands and feet, chunky simplified shapes and a strong readable silhouette, hand-painted cel-shaded textures with crisp highlights, a strict palette of three colours plus black. Standing in a relaxed A-pose facing the viewer, feet apart and both feet fully visible, arms lowered a little away from the body with a clear gap between each arm and the torso, anything held kept in one hand tight against the outside of the leg. The whole figure is visible head to toe and centred on a plain flat light-grey background with a plain light-grey floor, soft even studio light, no cast shadows, no text, no frame, one character only."
AVOID="Avoid: realistic proportions, photorealism, a real person or actor, anything standing beside the figure, arms crossed or held in front of the body, a weapon held out away from the body, cloth or bandages flying away from the body, anything hiding the feet, multiple characters, cropping, a dramatic background, text, watermark."
gen() { out="Art/Concepts/$1_sw.png"; [ -s "$out" ] && { echo "have $1"; return; }; python3 tools/genart.py --prompt "$STYLE $2 $AVOID" --out "$out" --size 1024x1024 >/dev/null 2>&1 && echo "ok $1" || echo "FAILED $1"; }
gen boss_colossus "A colossal animated statue of a pharaoh carved from cracked sandstone: gold seams glowing between the cracks, a striped nemes headdress and a false beard of stone, a broad chest of fitted stone plates, huge stone fists hanging at its sides, turquoise light burning in the eye sockets, thick stone legs and flat stone feet. Palette sandstone, gold, turquoise."
gen boss_unwrapped_king "A mummified pharaoh standing tall, his linen wrappings hanging loose and unwound from his face and one arm, a gold death mask pushed up onto his brow above a withered grinning face, a black and gold pectoral over the bandaged chest, a golden crook held tight against the outside of one leg and a flail against the other, bandaged feet. Palette linen, gold, black."

CARD="Edit this image into a mobile gacha RPG character portrait card of the SAME character in the SAME cel-shaded stylised look: upper body and head only, filling the square frame with the head in the upper two thirds, facing FACING, dramatic rim light from behind, a dark background with a soft radial glow behind the head, rich saturated colour, no text, no frame, no border, one character."
card() { out="$OUT/portrait_$1.png"; { [ -s "$out" ] || [ -s "$OUT/portrait_$1.jpg" ]; } && { echo "have card $1"; return; }; [ -s "Art/Concepts/$1_sw.png" ] || { echo "no concept for $1"; return; }; python3 tools/genart.py --prompt "${CARD/FACING/$2}" --ref "Art/Concepts/$1_sw.png" --out "$out" --size 1024x1024 >/dev/null 2>&1 && echo "ok card $1" || echo "FAILED card $1"; }
card boss_colossus "slightly left"
card boss_unwrapped_king "slightly right"

bg() { { [ -s "$OUT/$1.png" ] || [ -s "$OUT/$1.jpg" ]; } && { echo "have $1"; return; }; python3 tools/genart.py --prompt "$2 environment background for a mobile RPG battle stage, $3, wide establishing view, no characters, no foreground objects, painterly game art, atmospheric depth, dramatic lighting, muted saturated palette, the centre and lower half uncluttered and darker, interest in the upper corners" --out "$OUT/$1.png" --size 2048x2048 >/dev/null 2>&1 && echo "ok $1" || echo "FAILED $1"; }
bg colossus_vault_bg "Egyptian underground vault" "a vast sandstone vault under a pyramid, rows of colossal seated pharaoh statues receding into torchlit dark, gold seams in the stone, turquoise light from deep within, dust hanging in the air"
bg hydra_lair_bg "Greek marsh cave" "the mouth of a flooded cave in a black marsh at night, dead trees, green witch-light on the water, bones along the shore, low mist"
bg necropolis_bg "Egyptian necropolis" "an endless hall of tombs under the earth, rows of sarcophagi and canopic jars, violet ghost-light in the doorways, walls of hieroglyphs, dust and cobwebs, a cold shaft of light from above"
echo labyrinth-art-done
# The paintings ship as JPEG (tools/shrink_art.py); genart.py writes PNG, so
# convert whatever this run added before it is committed.
python3 tools/shrink_art.py
