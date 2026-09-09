#!/bin/bash
cd /home/user/Budget-and-advice
OUT=Pantheon/Resources/Stage
gen() { [ -s "$OUT/$1.png" ] && { echo "have $1"; return; }; python3 tools/genart.py --prompt "$2" --out "$OUT/$1.png" --size "$3" >/dev/null 2>&1 && echo "ok $1" || echo "FAILED $1"; }
gen floor_slate "Seamless tileable texture, viewed straight down, of a Norse great-hall floor: dark grey slate flagstones with cold blue-grey veining, a few carved knotwork runes worn into the stone, thin frost in the joints, hand-painted stylised mobile game texture with crisp painted highlights, flat even lighting, no shadows, no perspective, edges continue seamlessly, no text" 1024x1024 &
gen rock_ice "Seamless tileable texture of a frozen cliff face: dark layered rock in cold grey and blue under sheets of pale blue ice and hanging frost, deep cracks, snow on the ledges, hand-painted stylised mobile game texture with crisp painted highlights, flat even lighting, no perspective, edges continue seamlessly, no text" 1024x1024 &
gen floor_moss "Seamless tileable texture, viewed straight down, of an ancient Greek marsh-side pavement: cracked grey stone slabs half sunk in wet green moss and reeds, shallow dark water in the gaps, hand-painted stylised mobile game texture with crisp painted highlights, flat even lighting, no shadows, no perspective, edges continue seamlessly, no text" 1024x1024 &
wait; echo textures2-done
