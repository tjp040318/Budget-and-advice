#!/bin/bash
# The realms of batch 4: the two banner paintings (The Eagle Rises, The Jade
# Court Opens — `Banner.eagleRises`, `.jadeCourtOpens`) and the four chapter
# backdrops (`BattleEnvironment.forumRome`, `.colosseumSands`, `.peachGarden`,
# `.dragonGate`), six images. Until a backdrop lands its environment shows an
# older painting (`backdropName`), and the summon screen shows a banner
# without its art, so nothing here blocks anything. Everything skips what
# already exists, so it can be rerun after a quota or a network failure. No
# figure in a banner is a named person: the gods are described.
cd "$(dirname "$0")/../.."
OUT=Pantheon/Resources/Portraits

bg() { { [ -s "$OUT/$1.png" ] || [ -s "$OUT/$1.jpg" ]; } && { echo "have $1"; return; }; python3 tools/genart.py --prompt "$2 environment background for a mobile RPG battle stage, $3, wide establishing view, no characters, no foreground objects, painterly game art, atmospheric depth, dramatic lighting, muted saturated palette, the centre and lower half uncluttered and darker, interest in the upper corners" --out "$OUT/$1.png" --size 2048x2048 >/dev/null 2>&1 && echo "ok $1" || echo "FAILED $1"; }
banner() { { [ -s "$OUT/$1.png" ] || [ -s "$OUT/$1.jpg" ]; } && { echo "have $1"; return; }; python3 tools/genart.py --prompt "Mobile gacha summon banner splash, $2, dramatic backlight, cinematic, ornate, painterly game art with fine painted detail, the lower third quiet and dark, no text, no logo, no UI, no real person" --out "$OUT/$1.png" --size 1284x800 >/dev/null 2>&1 && echo "ok $1" || echo "FAILED $1"; }

( bg forum_rome_bg "Roman Forum at midnight" "the Roman Forum under a full moon, white marble temples and a triumphal arch, rows of columns casting long moonlit shadows, the Capitol on its hill behind, a cold blue-violet night with a few torches burning low, mist along the paving"
  bg colosseum_sands_bg "Roman amphitheatre" "the inside of a vast Roman amphitheatre seen from the raked sand of the arena floor, tiers of stone seating rising into hot afternoon sunlight, a striped awning against a hard blue sky, the emperor's box hung with red, dust in the air" ) &
( bg peach_garden_bg "Chinese celestial orchard" "an immortal peach orchard on terraces among the clouds at dawn, gnarled peach trees in pink blossom, a jade pavilion with an upturned red roof, stone lanterns along a winding path, mist between the terraces, soft rose and gold light"
  bg dragon_gate_bg "Chinese undersea palace" "the great gate of a dragon king's crystal palace at the bottom of the East Sea, towering pillars of green jade and coral, a red lacquered gate with gold studs, shafts of blue light falling through deep water, pearls and drifting kelp, a colossal dragon's shadow far above" ) &
( banner banner_eagle_rises "a Roman war god in a bronze crested helmet and red cloak raising a legionary eagle standard on the steps of the Capitol at dawn, a helmeted goddess with an owl on her shoulder and a bearded sea god with a trident behind him, marble temples and a rising sun, red and gold and bronze"
  banner banner_jade_court "the Monkey King with a golden-hooped staff standing on a somersault cloud before the open gates of a jade palace in the clouds, an azure Chinese dragon coiling through the clouds behind him, a boy on fiery wheels and a long-bearded general with a crescent halberd at his sides, red lanterns and gold, jade green and vermilion" ) &
wait
echo realms-batch4-done
# The paintings ship as JPEG (tools/shrink_art.py); genart.py writes PNG, so
# convert whatever this run added before it is committed.
python3 tools/shrink_art.py
