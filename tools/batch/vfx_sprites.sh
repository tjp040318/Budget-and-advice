#!/bin/bash
# The effect sprites: one painted element each on pure black, for the
# particle systems in VFXLibrary to fly, spin and fade — a fireball is a
# painted fireball moving, not a red circle. Everything skips what exists,
# so it can be rerun after a quota or a network failure. Sources stay here
# in Art/VFX; tools/vfx_ship.py cuts them to the bundle's sizes.
cd "$(dirname "$0")/../.."
STYLE="Game visual effect sprite for a stylised mobile RPG in the manner of Summoners War: hand-painted, crisp, high contrast, glowing, a single effect element centred and filling most of the frame, on a solid PURE BLACK (#000000) background that fills the whole frame — never white, never grey — nothing else in the frame, no ground, no scene, no text, no frame, no watermark."
gen() { out="Art/VFX/$1.png"; [ -s "$out" ] && { echo "have $1"; return; }; python3 tools/genart.py --prompt "$STYLE $2" --out "$out" --size 1024x1024 >/dev/null 2>&1 && echo "ok $1" || echo "FAILED $1"; }
gen vfx_fireball  "A blazing fireball seen from the side, flying to the right: a white-hot core wrapped in swirling orange and red flame that streams off to the left in a tail."
gen vfx_flame     "A single tongue of fire rising straight up out of the dark: a yellow-white core, orange body, deep red licking edges, the black background showing all around it."
gen vfx_ember     "A small glowing ember: a soft orange-yellow point of light with a faint round halo."
gen vfx_lightning "A jagged bolt of electric blue-white lightning running from the top of the frame to the bottom, with a few small forks and a soft blue glow along it."
gen vfx_splash    "A burst of water frozen mid-splash: a crown of blue-white droplets thrown up from a glowing cyan core."
gen vfx_slash     "A curved crescent slash of wind: a sharp bright white streak, thick in the middle and tapering to both ends, with a pale green trailing edge."
gen vfx_flare     "A bright four-pointed star flare of golden white light with a soft round halo, the kind of flash a holy spell makes."
gen vfx_wisp      "A wisp of violet and black shadow smoke curling upward, with a faint purple glow inside it."
gen vfx_smoke     "A soft round puff of grey smoke, lit from the upper left, edges fading to nothing."
gen vfx_ring      "A thin glowing ring of light seen face-on, a white core with a golden edge, a shockwave's ring."
gen vfx_shard     "A small splinter of ice: a sharp blue-white crystal shard with an inner glow, pointing up."
gen vfx_leaf      "A single small leaf caught in the wind, pale green and glowing at the edges, floating alone in the black."
echo vfx-sprites-done
