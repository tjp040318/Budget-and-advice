#!/bin/bash
# Norse stage props (preview+refine, ~30 each), campaign enemies and bosses.
# Quadrupeds and serpents cannot be rigged by Meshy, so they stop at refine and
# move procedurally in the game; the humanoids go on to a rig and clips.
cd /home/user/Budget-and-advice
S=${S:-/tmp/pantheon-batch}; mkdir -p "$S"
STYLE="stylised mobile game asset in the manner of Summoners War, chunky readable shapes, hand-painted textures with crisp highlights, clean silhouette, single object, no base scenery, no text"
NEG="text, watermark, people, multiple objects, scene, ground plane, blurry, photo"
prop()  { nohup python3 tools/meshy.py generate "$1" --prompt "$2, $STYLE" --negative "$NEG" --style realistic --polycount 6000 --height 3 --until refine > "$S/meshy_$1.log" 2>&1 & echo "launched $1 (prop)"; }
beast() { nohup python3 tools/meshy.py generate "$1" --prompt "$2, $STYLE" --negative "$NEG" --style realistic --polycount 9000 --height "$3" --until refine > "$S/meshy_$1.log" 2>&1 & echo "launched $1 (unrigged creature)"; }
biped() { nohup python3 tools/meshy.py generate "$1" --prompt "$2, standing in a relaxed A-pose facing the viewer, feet apart, arms lowered a little away from the body, $STYLE" --negative "$NEG" --style realistic --polycount 9000 --height "$3" > "$S/meshy_$1.log" 2>&1 & echo "launched $1 (rigged)"; }
prop  prop_rune_stone "A tall Norse rune stone: a weathered grey standing stone carved with glowing blue runes and knotwork, moss at the base"
prop  prop_longship_prow "The carved wooden prow of a Viking longship: a dragon head on a curving neck with a strip of hull planks and a row of round shields, weathered wood, red and gold paint"
prop  prop_world_tree_root "A huge gnarled tree root and trunk section of Yggdrasil, the world tree: twisted bark, glowing green sap in the cracks, a few golden leaves"
prop  prop_norse_brazier "A Norse fire brazier: an iron bowl held by three carved wooden posts with dragon heads, iron rivets, no fire"
prop  prop_hall_pillar "A carved wooden pillar from a Viking great hall: interlaced knotwork and wolf carvings, iron bands, a painted red and gold capital"
beast enemy_serpopard "A serpopard, an Egyptian mythical beast: a leopard with an impossibly long serpent neck, spotted tawny fur, a snarling leopard head, standing on four legs" 2.0
beast enemy_sun_scarab "A giant Egyptian sun scarab beetle: a glossy blue-green shell with gold edges, a gold sun disc held between its front legs, six legs, walking pose" 1.4
biped enemy_sandstone_sentinel "A sandstone sentinel: an animated Egyptian statue of a guardian warrior with a nemes headdress, cracked sandstone body with glowing blue cracks, a stone shield fused to its left forearm, a stone khopesh held against its right leg" 2.6
beast enemy_ammit "Ammit, the Egyptian devourer: a beast with a crocodile head, a lion's mane and forequarters and a hippopotamus's hindquarters, standing on four legs, jaws slightly open" 2.4
beast enemy_apep "Apep, the giant Egyptian chaos serpent: a colossal coiled cobra rearing up with its hood spread, dark scales with red and gold patterns, glowing red eyes, coils on the ground" 5.0
beast boss_hydra "A Greek hydra: a heavy reptile body on four legs with five serpent necks and heads rearing in different directions, dark green scales with bronze bellies, fangs bared" 4.5
biped boss_jotunn "A Norse jötunn frost giant: a huge bearded giant with frost-blue skin, icicles in his beard, a horned iron crown, bear pelts and iron-banded armour, a massive ice-crusted axe held down against his leg" 4.5
