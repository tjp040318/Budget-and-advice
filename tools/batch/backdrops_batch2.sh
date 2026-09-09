#!/bin/bash
cd /home/user/Budget-and-advice
OUT=Pantheon/Resources/Portraits
bg() { [ -s "$OUT/$1.png" ] && { echo "have $1"; return; }; python3 tools/genart.py --prompt "$2 environment background for a mobile RPG battle stage, $3, wide establishing view, no characters, no foreground objects, painterly game art, atmospheric depth, dramatic lighting, muted saturated palette, the centre and lower half uncluttered and darker, interest in the upper corners" --out "$OUT/$1.png" --size 2048x2048 >/dev/null 2>&1 && echo "ok $1" || echo "FAILED $1"; }
( bg olympus_gate_bg "Greek Olympus" "a colossal white marble gate and columns on a mountainside above the clouds at dawn, gold light, distant peaks"
  bg aegean_cliffs_bg "Greek coastal" "white limestone cliffs over a deep blue Aegean sea, a small marble temple on the headland, cypress trees, clear noon light"
  bg lerna_marsh_bg "Greek marsh" "a dark reed marsh at dusk with dead trees, green mist over black water, a ruined shrine, cold green light" ) &
( bg midgard_fjord_bg "Norse fjord" "a deep fjord between snow-streaked mountains under grey clouds, a longship on dark water, pine forests, cold blue light"
  bg yggdrasil_roots_bg "Norse mythic" "the colossal roots and trunk of the world tree Yggdrasil filling the sky, glowing green sap in the bark, golden leaves drifting, twilight"
  bg jotunheim_hall_bg "Norse frost giant" "an enormous ice-and-stone hall of the frost giants, pillars of blue ice, torches burning green, snow blowing through, cold light" ) &
( [ -s "$OUT/banner_ravens_gather.png" ] || python3 tools/genart.py --prompt "Mobile gacha summon banner splash, Odin with his two ravens standing on the prow of a longship under the northern lights, Thor and Freya behind him, dramatic backlight, ice blue and gold, cinematic, ornate, the lower third quiet and dark, no text, no logo, no UI" --out "$OUT/banner_ravens_gather.png" --size 1284x800 >/dev/null 2>&1 && echo "ok banner_ravens_gather" || echo "FAILED banner" ) &
wait; echo backdrops-done
