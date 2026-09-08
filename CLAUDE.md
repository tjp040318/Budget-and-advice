# Working agreements

## Answers

**Give exact, numbered steps.** When the answer involves doing something —
tool settings, a pipeline, a fix — write it as a numbered list of actions to
take in order, not as prose to interpret. Name the specific button, field,
value or filename. If there is a decision point, state the condition and both
branches rather than hedging.

Keep the reasoning, but put it after the steps or inline as a short "why",
never in place of them.

## This project

No Swift toolchain exists in the Claude Code environment — `download.swift.org`
is blocked by egress policy — so nothing here is ever compiled or run before it
is handed over. Two tools stand in and should be run before every commit:

```bash
python3 tools/swiftcheck.py --members --types   # argument order, labels, dead refs,
                                                # undeclared types, resource collisions
python3 tools/balance.py                        # stat curves, win rates, gacha odds
```

`--types` was noise-only until its allow-list covered the frameworks actually
used here; it is now clean and worth running. Every rule in the checker was
proven by reintroducing a real bug and watching it fail.

If a tuning constant changes in Swift, change it in `tools/balance.py` too. They
are kept in step by hand.

The 3D tools need packages that are not preinstalled. PyPI is reachable, so at
the start of a session that will touch models:

```bash
pip install -q usd-core numpy pillow scipy fast-simplification pymeshlab
apt-get install -y libopengl0      # pymeshlab's textured decimation needs it
```

Then `python3 tools/preview.py Pantheon/Resources/Models/<file>.usdz --out x.png`
renders a shipped model with its own texture, and `--sheet <family>` renders
every file of a family. Look before shipping: the marbled Anubis on the phone
was visible in that render.

**The repository compiles itself.** `.github/workflows/build.yml` builds the
simulator app and runs the unit tests on a macOS runner on every push, then
launches the app once per screen with `-tour -tour-step N` (`TourView`,
debug only) and photographs the simulator. Read the run with the GitHub
tools (`actions_list`, `get_job_logs`), and look at the frames with
`python3 tools/ciframes.py`, which fetches the `ci/screens` branch the job
force-pushes them to (the artifact store is on a host the network policy
refuses) and prints the lines that matter from each step's console, which
the job publishes beside the frames (`<step>-console.txt`, the app's stdout
and stderr with the frameworks' os_log lines mirrored in). A frame that came
out wrong can be read as well as looked at. Never push without reading the
run that follows; a push while a run is in progress cancels it, so wait for
the frames first.

## Where things stand

Read `Docs/PLAN.md` first. It has the measurements that decisions were based
on, the phase list, the pipeline costs, and an honest account of what this
environment can and cannot do. The short version:

- The game builds and runs on an iPhone, **landscape only** since this
  session: the battle camera is re-solved for a wide frame (35°, 5.5 m up,
  24° down; the player line a third of the screen tall), the battle HUD is
  one top row and an open-middled bottom bar, the summon reveal is stage
  left and words right, and the island painting is 16:9.
- Battle, summon, collection, arena, campaign and the Hall of Ka (training:
  power-up, skill-ups from duplicates, evolution, awakening) all work.
- Four families are in the code. Anubis: natural 4★. Sekhmet: natural 5★,
  the first damage archetype. Zeus: natural 5★, Greek, the control archetype,
  with the "Olympus Stirs" banner live. Shabti: natural 3★, the gacha's
  common tier and the training fodder, portraits only (sprites in the
  world). Twenty characters in the gacha; a common roll that finds no unit
  of its grade rolls at random within the nearest grade and shows the unit's
  real stars — the "every summon is a fire Anubis" bug.
- Models ship **canonical and decimated**: `tools/mesh.py <family>` reads the
  untouched export in `Art/Models/` (Blender USDZ or Meshy GLB) and writes
  Y-up, metre, feet-on-origin, rest-equals-bind, four-influence files into
  `Pantheon/Resources/Models/` (3–4 MB per family), then re-skins them in numpy
  to prove it. The first Anubis export loaded as gold shards for five reasons
  listed in `Docs/PLAN.md`; the first Meshy file verified at 190 m tall for a
  sixth (the GLB reader assumed which frame the vertices were in; it now reads
  it off the joints). **Nothing has been confirmed on device** since the
  canonical rewrite, and Sekhmet and Zeus have never been seen; the first
  thing worth asking for is the `[ModelLibrary]` console block — the loader
  prints the bounding box and skinner it built, and **More → Diagnostics**
  on the phone holds every line with Copy and Share. Two on-device facts so
  far: a 3v2 battle used the `_lod` files, whose texture was smeared by the
  decimation (fixed; the threshold is now eight combatants and the LOD is
  2,499 triangles), and the units stood in the bind pose, which the loader
  now treats by gathering per-joint tracks into one animation.
- The app opens on the island (`IslandView`): five landmarks over the real
  painting. It was generated at 9:16 and its sea extended to 3:4, because a
  phone shows only the central 62% of the painting's width; the anchors were
  measured off it (`Docs/ART_2D.md` §6). `tools/island.py` is the stand-in
  painter, kept for reference.
- Portraits go through `BundleImage` (UIKit lookup). SwiftUI `Image("name")`
  drew nothing for loose bundle PNGs on device; never use it for one.
- The gacha pool is gated on shipped art (`UnitBlueprint.hasShippedArt`, a
  bundle lookup of `portrait_<id>.png`), which is why all fifteen are in it
  now with no code change. The battle camera is solved for a portrait phone
  (`BattleSceneController`); `tools/appicon.py` drew the icon.
- Meshy is driven from here. `tools/meshy.py` took Sekhmet and then Zeus from
  a prompt to a rigged model with six clips for 53 credits each, and
  `download` fetched the files once the host was opened; the task ids are in
  `Art/Models/*.meshy.json` and the untouched GLBs sit beside them.
- **Concept-first models.** `python3 tools/genart.py --ref <portrait> ...`
  paints a designed full-body A-pose figure (prompts in `Docs/PLAN.md`, *The
  road to Summoners War*), and `python3 tools/meshy.py generate <asset>
  --image Art/Concepts/<file>.png --height H` runs Meshy image-to-3D on it,
  then rigs and animates. `--until preview` stops after the mesh so the
  thumbnail can be judged before the rig and clips are paid for. Three are
  done for Sekhmet (`sekhmet_v2`), Zeus (`zeus_v2`) and Anubis
  (`anubis_v3`; `anubis_v2` failed to rig because of a staff beside the
  figure — keep props in the hand). `python3 tools/mesh.py <asset>_v2 --as
  <asset>` ships a remake under the roster name. Every family in the bundle
  is concept-first now; judge a new one with `tools/preview.py --sheet`.
- `tools/character.py` is the one place a rigged character is read (Blender
  USDZ or Meshy GLB), canonicalised, decimated, written and verified;
  `tools/mesh.py` runs a family through it, `tools/glb2usd.py` converts one
  file at full size. Two Meshy-specific facts live in the GLB reader: the
  vertex frame is recovered from the joints, and an emissive map that is the
  base colour is dropped (the game keeps real emissive maps, so shipping it
  would have made both characters self-lit).
- The **Playtest Log** is an artifact the user logs issues into
  (https://claude.ai/code/artifact/a978f66a-cdde-4c34-841c-0299fc97d553);
  read new entries with the Artifact tool's `read_db` on collection
  `issues` (status `open`), reply and set `working`/`fixed` with `write_db`.
  "Check the issues log" means exactly that.
- Art is done for all four families: 26 painted portraits, 5 stage backdrops,
  3 summon banners, the island painting, a particle sprite and a 10-texture UI
  kit. `tools/genart.py` makes more via Gemini; the key is provided as a
  credential, so it is in the environment and must never be printed or
  written to a file. Every prompt is in `Docs/ART_2D.md`; a family's five
  portraits are one generation plus four `--ref` edits, about two minutes.
- Sound is 14 synthesised effects (`tools/sfx.py`, thunder for Zeus) and two synthesised music
  loops (`tools/music.py`, island and battle), crossfaded by `AudioLibrary`.

### What this environment can reach

`api.meshy.ai` (with `MESHY_API_KEY` provisioned; task creation and polling
work), `assets.meshy.ai` and `cdn.meshy.ai` (finished files download),
`generativelanguage.googleapis.com` (with `GEMINI_API_KEY` provisioned as a
credential; image generation works, ~20 s an image), GitHub including
`raw.githubusercontent.com` (the Khronos sample rigs came from there), and the
package registries. **Not** `docs.meshy.ai`. Tripo, Rodin, OpenAI and Hugging
Face are refused by the environment's network policy with a 403 at CONNECT. Do
not try to route around a policy denial; report it.

To add a host: claude.ai/code → the cloud icon above the message box → hover
the environment → gear → **Network access: Custom** → list the domain →
**tick "Also include default list of common package managers"**. On Pro/Max,
**API credentials** in the same dialog is better for a keyed API: it opens the
host *and* keeps the key out of the session. Either way the change reaches
**new sessions only**.
