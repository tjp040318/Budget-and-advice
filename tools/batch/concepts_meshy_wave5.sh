#!/bin/bash
# The concept paintings the Meshy programme of 2026-09-17 needs (the owner:
# Gemini batches "All", the Meshy floor "Spend down to 500"): Neptune and the
# Terracotta Soldier redrawn for the rigger (their pole weapons read as a
# third leg twice - a short weapon flat against the thigh, no cloak), six
# props for the three Labyrinth dungeons on a plain grey ground, and the
# awakened form of thirteen 5-star gods as an edit of each one's own concept
# so the mesh keeps the face the cards were painted from. Twenty-one images,
# about $2.75. Skips what already exists.
#   bash tools/batch/concepts_meshy_wave5.sh
cd /home/user/Budget-and-advice
G="python3 tools/genart.py"
have() { [ -s "$1" ] && { echo "have $1"; return 0; }; return 1; }

KEEP="Keep everything else exactly as it is: the same face, the same costume and colours, the same relaxed A-pose facing the viewer with both feet apart and fully visible and a clear gap between each arm and the torso, the same plain flat light-grey background and floor, soft even studio light, no cast shadows, no text, one character only."

# 1. The two rig refusals, edited from their own concepts.
out=Art/Concepts/neptune_v2_sw.png
have "$out" || { $G --ref Art/Concepts/neptune_sw.png --prompt "Edit this image: remove the trident completely and remove the cloak completely. Give him instead a short bronze sword in a scabbard hanging flat against the outside of his right thigh, held tight to the leg, nothing standing beside the body and nothing reaching the ground but his feet. $KEEP" --out "$out" --size 1024x1024 >/dev/null 2>&1 && echo "ok neptune_v2" || echo "FAILED neptune_v2"; }
out=Art/Concepts/terracotta_soldier_v2_sw.png
have "$out" || { $G --ref Art/Concepts/terracotta_soldier_sw.png --prompt "Edit this image: remove the halberd and its shaft completely. Give him instead a short bronze dao sword in a scabbard hanging flat against the outside of his right thigh, held tight to the leg, nothing standing beside the body and nothing reaching the ground but his feet. $KEEP" --out "$out" --size 1024x1024 >/dev/null 2>&1 && echo "ok terracotta_soldier_v2" || echo "FAILED terracotta_soldier_v2"; }

# 2. Six dungeon props on grey, for image-to-3D (30 credits each).
PROP="A single game prop for a stylised mobile RPG in the manner of Summoners War: chunky simplified shapes with a strong readable silhouette, hand-painted texture with fine detail - carved stone with chipped edges, engraved and worn metal, weathered wood grain - soft natural shading with painted highlights, rich colour. Shown in three-quarter view from slightly above, the whole object visible and centred on a plain flat light-grey background with a plain light-grey floor, soft even studio light, no cast shadows, no text, no frame, no scene, one object only."
prop() { out="Art/Concepts/prop_$1_sw.png"; have "$out" || { $G --prompt "$PROP The object: $2" --out "$out" --size 1024x1024 >/dev/null 2>&1 && echo "ok prop_$1" || echo "FAILED prop_$1"; }; }
prop vault_door "a colossal round bronze vault door set in a sandstone frame, its face a sunburst of riveted bronze plates around a locked hub, verdigris in the grooves, taller than a man, standing upright and closed"
prop pharaoh_head "the fallen head of a giant pharaoh statue lying on its side on the sand, weathered sandstone with traces of blue and gold paint on the striped nemes headdress, a broken nose, the neck a rough break"
prop sarcophagus "a closed Egyptian stone sarcophagus standing upright, its painted lid a stylised king with crossed arms, gold and lapis-blue bands, hieroglyph rows down the sides, chipped and dusty"
prop canopic_jars "a low sandstone altar with four canopic jars standing on it in a row, their lids carved as a jackal, a falcon, a baboon and a human head, painted in faded ochre, blue and gold"
prop dead_tree "a dead marsh tree with a thick twisted trunk, bare clawing branches, hanging moss and black roots splayed over a mound of mud, no leaves"
prop bone_pile "a heap of giant bleached bones and broken skulls of large beasts piled together with a few rusted weapons and a cracked shield sunk among them"

# 3. Thirteen awakened forms, each an edit of the family's own concept.
AWK="Edit this image into the AWAKENED form of the same character for a stylised mobile gacha RPG, in the same painted look: the costume becomes a richer ceremonial version of itself with more ornate armour and jewellery, glowing runic markings painted on the metal and the skin, the eyes glowing the same colour, brighter and more saturated colours overall. Every added piece is attached to the body and lies flat against it - no halo, no crown of light, no floating parts, no aura, no wings spread, no cape flying, nothing standing beside the figure. Still clearly the same character with the same face. $KEEP"
awk_() { out="Art/Concepts/$1_awakened_sw.png"; have "$out" || { $G --ref "Art/Concepts/$1_sw.png" --prompt "$AWK $2" --out "$out" --size 1024x1024 >/dev/null 2>&1 && echo "ok $1_awakened" || echo "FAILED $1_awakened"; }; }
awk_ odin   "The markings glow pale gold; a wolf-pelt mantle lies flat over the shoulders."
awk_ thor   "The markings glow storm blue; the belt and gauntlets become heavy engraved steel."
awk_ ra     "The markings glow sun gold; the pectoral and armbands become blazing gold with carnelian."
awk_ isis   "The markings glow white-gold; the wings on her arms fold flat as engraved gold sleeves."
awk_ athena "The markings glow silver; the breastplate becomes engraved silver with a gorgon device."
awk_ hades  "The markings glow violet; the robe becomes black with gold and amethyst, the crown of dark iron."
awk_ poseidon "The markings glow sea green; the scale armour becomes engraved bronze with pearl."
awk_ horus  "The markings glow gold; the falcon feathers are traced in gold, the armour lapis and gold."
awk_ osiris "The markings glow green; the wrappings become white and gold, the crown taller and jewelled."
awk_ loki   "The markings glow green; the coat becomes black leather with gold serpent embroidery."
awk_ freya  "The markings glow rose gold; the falcon-feather cloak folds flat as an embroidered mantle."
awk_ hera   "The markings glow royal purple; the peplos becomes purple and gold with a peacock pattern."
awk_ mars   "The markings glow red; the cuirass becomes engraved bronze with a gold eagle, the crest taller."
echo "concepts_meshy_wave5 done"
