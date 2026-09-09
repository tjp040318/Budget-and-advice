#!/bin/bash
# Ships everything Meshy has finished, one after another (decimation is CPU-bound).
cd /home/user/Budget-and-advice
S=${S:-/tmp/pantheon-batch}; mkdir -p "$S"
char() { # asset family height
  [ -s "Pantheon/Resources/Models/$2.usdz" ] && { echo "have $2"; return; }
  $(dirname "$0")/build_asset.sh "$1" "$2" "$3"
}
beast() { # asset shipname height
  [ -s "Pantheon/Resources/Models/$2.usdz" ] && { echo "have $2"; return; }
  python3 tools/meshy.py download "$1" --include-unrigged > "$S/dl_$1.log" 2>&1 || { echo "DOWNLOAD FAILED $1"; return; }
  python3 tools/prop.py "$1" --as "$2" --height "$3" --tris 6000 > "$S/build_$1.log" 2>&1 && echo "built $1 -> $2" || echo "BUILD FAILED $1: $(tail -n 2 $S/build_$1.log | tr '\n' ' ')"
}
prop() { # asset height
  [ -s "Pantheon/Resources/Models/$1.usdz" ] && { echo "have $1"; return; }
  python3 tools/meshy.py download "$1" --include-unrigged > "$S/dl_$1.log" 2>&1 || { echo "DOWNLOAD FAILED $1"; return; }
  python3 tools/prop.py "$1" --height "$2" > "$S/build_$1.log" 2>&1 && echo "built $1" || echo "BUILD FAILED $1: $(tail -n 2 $S/build_$1.log | tr '\n' ' ')"
}
char horus horus 2.10
char isis isis 2.00
char set set 2.20
char jackal_warrior jackal_warrior 1.90
char mummy mummy 1.90
char scarab_knight scarab_knight 1.90
char sobek sobek 2.30
prop prop_world_tree_root 5.0
beast enemy_serpopard serpopard 2.0
beast enemy_sun_scarab sun_scarab 1.4
beast enemy_ammit ammit 2.4
beast enemy_apep apep 5.0
beast boss_hydra boss_hydra 4.2
echo queue-done
