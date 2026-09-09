#!/bin/bash
cd /home/user/Budget-and-advice
S=${S:-/tmp/pantheon-batch}; mkdir -p "$S"
char() { [ -s "Pantheon/Resources/Models/$2.usdz" ] && { echo "have $2"; return; }; $(dirname "$0")/build_asset.sh "$1" "$2" "$3"; }
char athena athena 2.05
char poseidon poseidon 2.15
char apollo apollo 2.00
char artemis artemis 1.95
char hermes hermes 1.95
char minotaur minotaur 2.40
char cyclops cyclops 2.60
char amazon amazon 1.90
char medusa medusa 1.95
char odin odin 2.10
char thor thor 2.20
char freya freya 2.00
char tyr tyr 2.05
char heimdall heimdall 2.10
char hel hel 2.00
char skadi skadi 2.05
char valkyrie valkyrie 1.95
char draugr draugr 1.95
char berserker berserker 2.00
char frost_troll frost_troll 2.50
char dwarf_smith dwarf_smith 1.40
char shabti shabti 1.60
echo queue2-done
