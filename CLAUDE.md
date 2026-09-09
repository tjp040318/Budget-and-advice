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
  power-up, skill-ups from duplicates, evolution, awakening) all work. So do
  the **Halls of Essence** (Campaign → second segment: one hall per
  element, five floors, repeatable; `DungeonDatabase`), **auto-repeat**
  (the briefing asks for 1/5/10/20 runs; `BattleViewModel.conclude()`
  swaps engines and tots up the loot), the **relic inventory** (Collection
  → Relics: sell, lock, reappraise, efficiency; `RelicInventoryView`), the
  **bazaar** (tap the wallet on the island, or More; `ShopService`, game
  currency only, a free daily offering) and the **living island** (the
  campaign team stands on the painting; `IslandSceneView`).
- **Forty-three families.** Eleven hand-written (`UnitDatabase.swift`,
  `UnitDatabase+Roster.swift`: Anubis, Sekhmet, Thoth, Shabti, Zeus, Ares,
  Heracles, Perseus, Hoplite, Satyr, Harpy) and thirty-two from one table
  (`UnitDatabase+Families.swift`: a `FamilyRow` per family and eight
  `Kit`s — Egypt 9, Greece 10, Norse 13). Egypt, Greece and Norse are live,
  each with its banner (The Duat Opens, Olympus Stirs, The Ravens Gather;
  the Endless Scroll is everyone). The gacha gates on cards
  (`hasShippedArt`), so a family joins the pool the moment its five
  `portrait_<id>.png` files are in the bundle; the third roster's cards are
  still being painted (Gemini allows 250 images a day) and
  `tools/batch/portraits_batch2.sh` paints what is missing. A common roll
  that finds no unit of its grade rolls at random within the nearest grade
  and shows the unit's real stars — the "every summon is a fire Anubis" bug.
- Eight chapters: Duat 1–2, Olympus 1–3, Yggdrasil 1–3. The generated ones
  take `enemyStars` and `difficulty` (later chapters field the same
  creatures at a higher grade, not at absurd levels); the curve is measured
  by `python3 tools/balance.py --chapters` and `--halls`, and a change to
  a chapter's numbers goes into both files. Campaign enemies borrow the
  roster's models and cards (`enemy(... assetName:portraitName:)`); the
  Hydra and the Jötunn are unrigged meshes moved procedurally.
- New save fields must be **Optional** (`Player.lastDailyPackClaim` is the
  pattern): the synthesised decoder tolerates a missing optional key and
  nothing else; a non-optional field would wipe every existing save.
- **The earning loop** (`QuestService`): eight daily missions, sixteen
  feats plus one per chapter, a seven-day login gift, and 25 divinity per
  summoner level. `GameStore` calls `QuestService.record(...)` at every
  mutation that counts (stage and hall clears, arena results, summons,
  power-ups, evolutions, awakenings, relic upgrades, the daily offering,
  energy spent); `refreshDay` runs with the energy tick. The Missions
  screen opens from the scroll beside the wallet on the island and from
  More. Scrolls also drop from stages (unknown, mystical) and halls (the
  element's own).
- **Scrolls are banners** (`Banner.scrollBanners`): Unknown (3★ commons),
  Divine (4★+), Light & Dark, Fire, Water, Wind, each spending its own
  `ScrollType` and drawing from `SummonService.pool(where:)`. The summon
  screen has two chip rows, pantheons and scrolls, with counts. The
  bazaar sells every one (Unknown for drachma).
- **The campaign is a map** (`CampaignMapView`): `WorldMapView` lists the
  realms and their chapters and says which boss shuts a chapter;
  `ChapterMapView` draws the stage's painting, a dotted road and a
  medallion per stage (gold, pulsing ring, lock, a crown for the boss).
  `world_map.png` shows above the realms once painted. The Halls stay a
  list.
- Two SwiftUI gotchas that cost a playtest: **`.clipped()` and
  `.clipShape` do not clip hit-testing**, so a painting scaled to fill a
  short frame swallows taps far above and below it — every decorative
  painting carries `.allowsHitTesting(false)` (the Chapters/Halls switch,
  the banner chips and the first stage rows were all dead). And a camera
  node looks along its own −Z: orient it with `SCNNode.look(at:)`, never
  `atan2(dx, dz)` (that was half a turn off and the orbit shot showed the
  empty side of the stage).
- **Five tabs.** An iPhone folds a sixth tab into a system "More" list, so
  Settings opens over the island from the Obelisk (and Missions, the
  bazaar from the header); `RootView.Tab(destination)` is failable for the
  two that open as sheets.
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
- **Awakened forms.** Two cards per awakenable character (`portrait_<id>.png`
  and `portrait_<id>_awakened.png`); `ModelSpec.portraitName(awakened:)`
  picks. On the stage an awakened unit gets the awakened look (costume glow,
  brighter rim, an aura) and would load `<asset>_awakened.usdz` with its own
  clips if a family shipped one — none has; that is 53 credits a family. The
  Hall of Ka shows both forms before awakening and plays the reveal after.
- **3D stages.** `StageBuilder` builds every battle set and the summoning
  circle from parts: a floating platform (tileable painted textures in
  `Pantheon/Resources/Stage/`), Meshy props (`prop_*.usdz`, shipped by
  `tools/prop.py <asset> --height H` from `Art/Models/<asset>_refine.usdz`),
  braziers with fire, mist, dust, and the environment painting far behind
  for parallax. A missing prop gets a built stand-in. **Meshy text-to-3D
  props cost 30 credits each, not 15**; the balance is about 61.
- **Battle feel.** A melee unit (`ModelSpec.melee`) dashes to its one victim
  for an attack clip and back at the next turn, and every hit flashes the
  victim white. **The camera is fixed by default** (`CameraDirector`): one
  home framing for the whole fight, a short push toward an ultimate's
  caster and back, a shake on heavy hits, nothing else — the genre's way,
  and what the user asked for after the old close shot left its look-at
  constraint on across a turn change. The cuts, leans and orbits survive
  behind More → Sound & camera → Cinematic battle camera
  (`UserDefaults` key `cinematicCamera`). `returnHome()` clears the
  constraints, because cancelling a shot's action skips the completion that
  used to. The HUD's top centre is the **attack gauge** (`BattleView.turnGauge`:
  portraits on one track by `attackBar`, ready unit in gold); tapping a
  skill shows its name and description above the skill row and holding one
  opens a card. The painted chrome is drawn at 1/1.4 (`Chrome.shrink`),
  fonts at 0.9 (`Theme.fontScale`), cards 76pt: the playtest's density
  pass. The CI tour photographs an arena battle (step 8) as well as the
  campaign one.
- Portraits go through `BundleImage` (UIKit lookup). SwiftUI `Image("name")`
  drew nothing for loose bundle PNGs on device; never use it for one.
- The gacha pool is gated on shipped art (`UnitBlueprint.hasShippedArt`, a
  bundle lookup of `portrait_<id>.png`): a family joins the pool the moment
  its five cards are in the bundle. The battle camera is solved for a portrait phone
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
- Art: cards for the first eleven families (base and awakened), 11 stage
  backdrops, 4 summon banners, the island painting, a particle sprite, a
  10-texture UI kit, 9 stage textures, and stylised concepts for all 43
  families. `tools/genart.py` makes more via Gemini; the key is provided as
  a credential, so it is in the environment and must never be printed or
  written to a file. **Gemini's key allows 250 image requests a day**; a
  roster's cards are about 240, so a big batch spans two days and every
  batch script skips what already exists. A named god can come back as a
  photo of an actor (Loki did; the file was deleted) — describe, don't
  name, and never ship a likeness. Every prompt is in `Docs/ART_2D.md` and
  `tools/batch/`; a family's five portraits are one generation plus four
  `--ref` edits, about two minutes.
- Meshy: `tools/meshy.py` waits out the plan's queued-task cap (a wave of
  twenty-three launched at once finished by itself) and retries proxy
  drops. "Pose estimation failed" at the rig step is about the mesh's
  pose: a gap between the arms and the body, both feet visible, no crossed
  arms, no weapon held out; redraw, run as `<asset>_v2`, ship with
  `mesh.py <asset>_v2 --as <asset>`. Text-to-3D props are charged by what
  Meshy generates, 30–300 credits each, not a flat rate. The user's floor
  is **500 credits**: check `python3 tools/meshy.py balance` before every
  launch and never plan past it.
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
