#!/bin/bash
# The marble-and-verdigris-bronze menu kit, chosen by the owner on 2026-09-10
# after "the menu colours are awful looking". Four nine-slice textures.
# Everything skips what already exists, so it can be rerun after a quota or a
# network failure.
#
# NINE-SLICE IS THE WHOLE CONSTRAINT. Each of these is stretched from the
# middle: the corners and the ends are drawn once and the centre is repeated,
# so the prompt asks for ornament ONLY at the edges and a flat, even middle. A
# painting with a crest in the centre or a gradient across it smears the moment
# a panel is wider than the source.
#
# THE OUTPUT SIZE IS NOT NEGOTIABLE. Chrome's insets (Theme.swift) are measured
# against the file's own dimensions — panel 31 a side, gold button 47 at the
# ends, dark button 17, ribbon 17 — so every file is resized to exactly what
# the old one was. tools/fitsize.py does that.
#
# When all four land, set `Chrome.holdBackOldMenuArt = false` in Theme.swift
# and delete it with its list.
cd "$(dirname "$0")/../.."
OUT=Pantheon/Resources/Portraits

MATERIAL="Aged white-grey marble with fine grey veining, and frames of old bronze that has turned verdigris green in the recesses. Palette: marble #D9D4C8, dark slate stone #1C2027, bronze #A8894F, pale bronze highlight #D6BE86, verdigris #4E8A72. Hand-painted mobile game UI art in the manner of a premium collection RPG, crisp and clean, no photographic texture, no text, no letters, no numbers, no logo, no watermark, straight-on orthographic view with no perspective, filling the frame edge to edge with no margin and no drop shadow outside the artwork."

gen() {
  name=$1; prompt=$2; ask=$3; w=$4; h=$5
  out="$OUT/$name@3x.png"
  [ -s "$out" ] && { echo "have $name"; return; }
  tmp="/tmp/ui_$name.png"
  if python3 tools/genart.py --prompt "$prompt $MATERIAL" --out "$tmp" --size "$ask" >/dev/null 2>&1 \
     && python3 tools/fitsize.py "$tmp" "$out" "$w" "$h" >/dev/null 2>&1; then
    echo "ok $name"
  else
    echo "FAILED $name"
  fi
}

gen ui_panel "A square nine-slice panel for a game menu. A slab of dark polished slate fills the whole square. Around it runs a narrow bronze frame about two percent of the width thick, with a small scrolled acanthus corner ornament at each of the four corners and nothing at all along the straight runs between them. The centre two thirds of the square is completely flat, even, unornamented dark slate with only the faintest marble veining. No crest, no motif, no gradient, no vignette, nothing in the middle whatsoever." 1024x1024 512 512

gen ui_ribbon "A wide, short horizontal title plate, five times wider than it is tall. A bar of polished marble with a bronze edge along the top and along the bottom, and a small bronze end-cap finial at the left end and at the right end. The entire middle of the bar is flat, even marble with no ornament, no crest and no gradient." 1536x384 640 128

gen ui_button_gold "A wide, short horizontal button plate, three times wider than it is tall. A bar of polished bronze, brightest across the upper third and dark along the bottom edge so it reads as metal with a thickness, with an ornate scrolled bronze cap at the left end and at the right end and a fine verdigris line where the metal meets each cap. The entire middle of the bar is flat, even bronze with no ornament." 1536x448 640 192

gen ui_button_dark "A wide, short horizontal button plate, three times wider than it is tall. A bar of dark slate stone with a thin bronze edge all the way round and plain square ends with no ornament. The entire middle of the bar is flat, even dark slate." 1536x448 640 192

echo ui-marble-done
# NOT shrink_art.py: the UI kit is one of the three groups it deliberately
# leaves as PNG, and a JPEG nine-slice rings at every ornate edge.
