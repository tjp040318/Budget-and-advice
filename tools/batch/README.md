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
| `wave_launch.sh "asset:concept:height:palette" …` | Meshy image-to-3D + rig + six clips per spec, in parallel; `meshy.py` waits out the queue cap |
| `props_enemies_launch.sh` | Meshy text-to-3D for the Norse props, the beasts and the bosses |
| `build_asset.sh asset family height` | download + `mesh.py --as` + preview sheet for one rigged character |
| `build_queue.sh`, `build_queue2.sh` | the shipped order for the third roster, the beasts and the world tree |
| `ciwait.sh sha` | waits for the CI run of a commit and prints its steps |

Gemini allows 250 image requests a day on this key; a full roster's cards
are about 240, so a day's painting is one roster and the scripts are written
to be run again the next day.
