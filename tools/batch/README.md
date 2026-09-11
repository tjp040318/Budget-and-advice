# Batch scripts

The shell scripts a big content session runs, kept here so the next session
(or the next machine) can rerun them. Logs go to `$S`, default
`/tmp/pantheon-batch`. All of them skip work whose output already exists, so
re-running one after a quota or a network failure picks up where it stopped.

| script | what it does |
|---|---|
| `concepts_batch2.sh`, `concepts_redo.sh` | Gemini concepts for the third roster (the second file is the A-pose redraws for the families Meshy could not rig) |
| `portraits_batch2.sh` | the five element cards per family and the awakened cards for the 4★ and 5★ families, from the concepts |
| `backdrops_batch2.sh`, `stage_textures2.sh` | the Greek and Norse stage paintings, the Norse banner, the slate, moss and ice textures |
| `labyrinth_art.sh` | the Labyrinth's own art: the two boss concepts (A-pose), their cards, and a painting per relic dungeon |
| `concepts_batch3.sh`, `portraits_batch3.sh` | batch 3: thirty-six A-pose concepts in the painted-detail style, and their cards (`BASE_ONLY=1` paints every family's five before any awakened card) |
| `concepts_batch4.sh`, `portraits_batch4.sh` | batch 4, Rome and the Jade Court (2026-09-11): twenty A-pose concepts in the painted-detail style — the two dragons on four claws with their own style line — and their cards (`BASE_ONLY=1` as above); a pantheon's banner appears on the summon screen the morning its first family's five cards land |
| `realms_batch4.sh` | the two batch-4 banner paintings (The Eagle Rises, The Jade Court Opens) and the four chapter backdrops (the Forum, the Colosseum, the Peach Garden, the Dragon King's Gate) at 2048 px; until they land the environments borrow older paintings |
| `wave_launch.sh "asset:concept:height:palette:kit:family" …` | Meshy image-to-3D + rig + six clips per spec, in parallel; `meshy.py` waits out the queue cap; `kit` is a `meshy.py` clip set (blade, heavy, caster, archer, or a set plus `,name=id` overrides) |
| `wave3.txt`, `remake_wave.txt` | the wave lists: batch 3 (with batch 2's leftovers) and the `<key>_hd` detail remakes, one spec per line, priority order |
| `wave_run.sh <list> [floor]` | launches every spec in a list that has no manifest yet while the balance minus what the wave still owes stays above the floor (2,000 since 2026-09-11) |
| `ship_wave.sh <list>` | `build_asset.sh` for every finished, unshipped run in a list; leaves `Art/Models/<asset>.shipped` |
| `props_enemies_launch.sh` | Meshy text-to-3D for the Norse props, the beasts and the bosses |
| `build_asset.sh asset family height` | download + `mesh.py --as` + preview sheet for one rigged character |
| `build_queue.sh`, `build_queue2.sh` | the shipped order for the third roster, the beasts and the world tree |
| `ciwait.sh sha` | waits for the CI run of a commit and prints its steps |

Gemini allows 250 image requests a day on this key; a full roster's cards
are about 240, so a day's painting is one roster and the scripts are written
to be run again the next day.

A character's raw exports: the base `Art/Models/<asset>.glb` and the manifest
are committed; the six per-clip GLBs are ignored (each is a 6–7 MB copy of the
mesh carrying one track) and `python3 tools/meshy.py download <asset>` refetches
them when a family has to be reshipped. The CI checkout skips `Art/` entirely.
