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
  session: the battle camera is SOLVED, not written down (`CameraDirector`
  measures the figures on their marks and frames them), and it stands the
  genre's way — 55° round to the right of the field, 16° down, a 26° lens
  about 20 m out — so the two lines-abreast the stage places read as two
  COLUMNS: the player's at the lower left, its front unit nearest the
  camera, the enemy's on the right stepping back toward the top, an open
  middle between them, and the painting filling the top half behind the
  far rim (`StageBuilder.farBackdrop` is turned to face the camera). A
  **boss** (`Combatant.isBoss`) stands over the far rim at z = −9.6, sunk
  42% of its height below the platform, 6–8 m tall in the data (Apep 7.2,
  Hydra 7.0, Jötunn 7.5, Colossus 8.0, the Unwrapped King 6.0), with no 3D
  bar or ring (the HUD's boss bar reads), never dashes, and is framed by
  its head (`bossTopLine`) rather than its box; its adds stand on the marks
  in front, closing over the boss's slot (`markIndex`). The earlier
  27°/21° solve with rows abreast was photographed from the owner's phone
  as "a small tilted disc in a void" and called ugly. The battle HUD is one
  top row and an open-middled bottom bar whose actor plate is one 54-pt
  translucent row (it was 129 pt and solid), the summon reveal is stage
  left and words right, and the island painting is 16:9.
- Battle, summon, collection, arena, campaign and the Hall of Ka (training:
  power-up, skill-ups from duplicates, evolution, awakening) all work. So do
  the **Labyrinth** (a building on the island, `LabyrinthView`: three
  relic dungeons and the five Halls of Essence; `DungeonDatabase`;
  a dungeon level is one battle of three waves), **auto-repeat**
  (the briefing asks for 1/5/10/20 runs; `BattleViewModel.conclude()`
  swaps engines and tots up the loot), the **relic inventory** (Collection
  → Relics: sell, lock, reappraise, efficiency; `RelicInventoryView`), the
  **bazaar** (tap the wallet on the island, or More; `ShopService`, game
  currency only, a free daily offering) and the **living island** (the
  campaign team stands on the painting; `IslandSceneView`).
- **Seventy-nine families.** Eleven hand-written (`UnitDatabase.swift`,
  `UnitDatabase+Roster.swift`: Anubis, Sekhmet, Thoth, Shabti, Zeus, Ares,
  Heracles, Perseus, Hoplite, Satyr, Harpy) and sixty-eight from one table
  (`UnitDatabase+Families.swift`: a `FamilyRow` per family and eight
  `Kit`s — the third roster's thirty-two, Egypt 9, Greece 10, Norse 13, and
  **batch 3**'s thirty-six, Egypt 12, Greece 10, Norse 14, whose concepts,
  cards and meshes are `tools/batch/concepts_batch3.sh`,
  `portraits_batch3.sh` and `wave3.txt`; a batch-3 family is in the pool the
  moment its five cards land). Egypt, Greece and Norse are live,
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
- **The campaign opens on the map** (`CampaignView`): a strip of chapter
  chips along the top and the chapter the player is in below
  (`ChapterMapView`: the stage's painting, a dotted road and a medallion
  per stage — gold, pulsing ring, lock, a crown for the boss), so the
  island's gate is one tap from a stage. `WorldMapView` (the realms and
  which boss shuts a chapter) is a sheet behind the Realms button;
  `world_map.png` shows above the realms once painted.
- **The Labyrinth** (`DungeonDatabase.labyrinths`, `LabyrinthView`,
  `DungeonLevelsView`): the Vault of the Colossus (boss `boss_colossus`),
  the Lair of the Hydra (`boss_hydra`) and the Necropolis of the Unwrapped
  King (`boss_unwrapped_king`), ten levels each, every level one battle of
  three waves (two of mobs, then the boss with two more) and a relic of
  the dungeon's own six sets every run, 3★ on B1–3 up to 6★ on B10; the
  Halls of Essence live in the same building. Each dungeon is its own
  `BattleEnvironment` (`colossusVault`, `hydraLair`, `necropolis`) with a
  `StageBuilder` recipe of its pantheon's props and its own painting;
  `BattleEnvironment.backdropName` shows the parent place's painting until
  the dungeon's own lands (`tools/batch/labyrinth_art.sh` paints the two
  boss concepts, their cards and the three backdrops; the boss meshes are
  Meshy image-to-3D from those concepts, 53 credits each). Waves are
  `Stage.laterWaves`: `BattleEngine` brings the next one on when the
  field is clear (`.waveStarted`; `BattleSceneController` removes the
  fallen and walks the arrivals in from the back), the HUD shows "Wave
  2/3", and `StageRewards.relicSets` restricts the drop. The curve is
  `python3 tools/balance.py --labyrinths` (a run carries wounds and
  cooldowns across waves): B1 for a 3★ team, B4 for 4★s, B7 for 5★s with
  relics, B10 for maxed 6★s; the Colossus is the soft one.
- **The six systems added 2026-09-10**, built by six agents against disjoint
  files with a standing rule that none of them touch `GameStore`, then wired
  by a single agent that made every `GameStore` change at once. **Fusion**
  (`FusionService` in `ProgressionService.swift`, the screen in
  `TrainingView`): four named ingredients at a required grade and level plus
  drachma buy a unit in no banner; locked units and units already spoken for
  by another slot are never eaten. **The Endless Tower**
  (`DungeonDatabase.towerTiers`, the Tower wing of `LabyrinthView`): a
  hundred floors of one battle, three mobs and a warden with two adds every
  tenth, five themed tiers cycled twice, progress a high-water mark; the
  curve is `balance.py --tower`. **The relic optimiser and named loadouts**
  (`RelicService.OptimiserGoal`, `RelicInventoryView`): a loadout saves relic
  IDs, never relics, so a relic sold since cannot leave a stale copy in a
  save. **Raids** (`RaidBossProfile` on an `EnemySpawn`, `StageDatabase.raids`,
  the Raids wing): a barrier that regenerates and stuns when broken, guard
  adds that come back and drain the boss while they live, enrage stacks on a
  clock, and a weakness that rotates; the raid stages are deliberately NOT in
  `chapters` so they cannot appear on the campaign map. The boss bar draws
  the barrier ON the health bar in the current weakness's colour, and reads
  the three values straight off the engine rather than a published mirror —
  they move on the boss's turn while `displayedCombatants` lags for the
  animation. **The guided first hour** (`FirstHourStep`, `IslandView`): four
  steps pointing at the landmark each wants, with a skip chip and a chapter
  intro card shown once. Five new save fields, every one Optional with a nil
  default.
- **The unit sheet is one landscape screen** (`UnitDetailView`): the card,
  level bar, power and the Power up / Evolve / Awaken buttons on the left,
  the six relic slots in a ring around the element in the middle (slot 1
  at the top, clockwise), the stats with their relic bonuses on the right,
  the skills along the bottom with the selected one's words, cooldown,
  estimated damage and skill-up dots; the lore is behind the book, the
  awakening panel is `AwakeningSheet`, auto-equip is in the toolbar. A
  slot opens `RelicPickerView`: candidates best-fit-first on the left,
  and on the right the relic now, the relic picked, every stat before →
  after with the delta, and the sets completed or broken, before Equip.
- **Relic power-up is the genre's rune power-up** (`RelicService.upgrade`
  → `PowerUpOutcome`; `RelicDetailView` is the screen, opened from a worn
  slot on the unit sheet and from the inventory): an attempt costs drachma
  either way and succeeds at `powerUpChances[level - 1]` — sure to +3,
  then a step down a level to 40% at +15; +3, +6, +9 and +12 add a sub
  stat while there are fewer than four, then grow one; +15 rolls nothing
  and lifts the main stat to 3× (`Relic.effectiveMainStat` is linear to
  +14). The screen shows the odds, the cost, the next main-stat value, the
  level track with the sub-stat levels ringed, and the last roll marked;
  a success glows, a failure shakes. The chance table is modelled on the
  genre's published rules (the data sites are refused by the network
  policy, so the per-level numbers are ours); `balance.py --economy`
  prints the expected drachma to +15 with the odds. Change the table in
  both files.
- **The detail pass (2026-09-09).** The playtest called the characters too
  cartoony and the attacks ugly (a leg thrown out). Four things changed, all
  in one place each: the Meshy texture prompt in `tools/batch/wave_launch.sh`
  asks for painted detail (engraved metal, woven cloth, hair in strands)
  instead of "cel-shaded with crisp baked highlights"; `tools/mesh.py` ships
  9,000 triangles at 2048 px (was 5,000 at 1024; the LOD is 3,500 at 1024);
  `ModelLibrary`'s lighting ramp is `smoothstep(0.16, 0.86)` over
  0.30 + 0.70 with a 36-power specular and a 3.2 / 0.42 rim (was a two-tone
  0.28–0.72 band and a 2.6 / 0.55 rim that outlined every figure in white);
  and `tools/meshy.py` cuts sword clips by default (219 Right-hand Sword
  Slash, 242 Charged Slash, 102 Sword Judgment) with `CLIP_SETS` per kit —
  `heavy` (128 Heavy Hammer Swing, 127 Charged Ground Slam), `caster`
  (129 / 125 / 126 spell casts), `archer` (224 / 226 / 222) — chosen by the
  fifth field of a wave spec. The remakes are `<key>_hd` from the same
  concept, shipped over the old files (`tools/batch/remake_wave.txt`;
  `wave_run.sh <list> <floor>` launches, `ship_wave.sh <list>` ships and
  leaves an `Art/Models/<asset>.shipped` marker). Zeus, Sekhmet and Anubis
  went first; judge a remake on its preview sheet before the routine spends
  on the rest.
- Three SwiftUI gotchas that each cost a screen. **`.clipped()` and
  `.clipShape` do not clip hit-testing**, so a painting scaled to fill a
  short frame swallows taps far above and below it — every decorative
  painting carries `.allowsHitTesting(false)` (the Chapters/Halls switch,
  the banner chips and the first stage rows were all dead). **`.clipped()`
  does not clip the reported SIZE either**, so a fill-aspect painting under
  an unbounded `.frame(maxWidth: .infinity, maxHeight: .infinity)` measures
  larger than the window and grows every ancestor with it: as a sibling in
  `DungeonLevelsView`'s content stack it pushed the strip and both panels'
  top-aligned contents off the top of the phone, and the CI tour
  photographed the Halls and a relic dungeon as two tall empty panel frames
  (2026-09-10). **A full-screen painting is a `.background(...)`, never a
  sibling** — a background is measured by its parent and can never do this;
  the same pattern is safe inside a card, and safe with a fixed
  `.frame(width:height:)` off a GeometryReader, which is what the island
  does. And a camera node looks along its own −Z: orient it with
  `SCNNode.look(at:)`, never `atan2(dx, dz)` (that was half a turn off and
  the orbit shot showed the empty side of the stage).
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
  brighter rim, an aura), and loads `<asset>_awakened.usdz` with its own
  clips when a family has shipped one. **Ares and Thoth have**, as of
  2026-09-10 — the first two — at 53 credits a family; every other family
  keeps the recolour until its mesh arrives. Thoth's first attempt was
  refused by Meshy's rigger and the concept says why: the four faults the
  rigger cannot read are an arm crossing the chest, a tall staff standing
  beside the figure like a second object, legs wrapped into one sheath with
  no gap at the hip, and anything floating detached from the body. Repaint in
  a symmetrical A-pose with background visible either side of the torso and
  everything held straight down against the outside of a thigh, and it rigs
  first time. The
  Hall of Ka shows both forms before awakening and plays the reveal after.
- **3D stages.** `StageBuilder` builds every battle set and the summoning
  circle from parts: a floating platform (tileable painted textures in
  `Pantheon/Resources/Stage/`), Meshy props (`prop_*.usdz`, shipped by
  `tools/prop.py <asset> --height H` from `Art/Models/<asset>_refine.usdz`),
  braziers with fire, mist, dust, and the environment painting far behind
  for parallax. A missing prop gets a built stand-in. **Meshy text-to-3D
  props cost 30 credits each, not 15**. The user bought the 8,000-credit plan on
  2026-09-09; the floor is now **3,000**, and `tools/batch/wave_run.sh` keeps
  every wave above it.
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
  pass. The CI tour is twenty screens: an arena battle (step 8) as well
  as the campaign one, the Labyrinth, a dungeon's levels, the relic
  picker, a Labyrinth run on auto (`dungeon_battle`, four frames, so the
  waves are seen walking on) and the power-up screen.
- **The fight reads.** Status effects are tiles over the health bar
  (`StatusIconRenderer`: blue for a buff, red for a debuff, the effect's
  glyph, the turns left in the corner; `UnitNode.setStatuses` takes
  `[ActiveStatus]` and the scene updates them on `.statusApplied` /
  `.statusExpired`), and named chips in the actor plate and the boss bar.
  The HUD keeps the field clear: the skill in hand is worded inside the
  actor plate at bottom left, the target prompt is one slim line under the
  top row, a boss (`Combatant.isBoss`: a primordial or anything 3 m tall)
  gets a wide red bar across the top, and an ultimate plays a **cut-in**
  (`BattleViewModel.cutIn`: the caster's card and the skill's name sweep
  across a dark band for a second). Damage numbers are a rounded semibold
  with a thin edge, not the heavy outlined figures of the first build.
- **Motion.** A melee unit's dash is a 0.3 s leap (the model container
  hops while the node moves), clips cross-fade over 0.22/0.30 s
  (`ModelLibrary`), one-shot clips are never sped past 2× (the contracts in
  `AnimationClip.fallbackDuration` were lengthened instead: basic 1.3 s,
  heavy 1.7 s), every skill without an effect of its own lands in its
  caster's element (`VFXLibrary` `impact_<element>`) and a closing strike
  draws a slash arc across the victim (`slash`). Bloom is 0.3 over 0.94:
  the old 0.55 over 0.85 turned a sunlit floor into a sheet of light.
- **Stand-ins by name.** `ModelSpec.standInAsset` names a shipped mesh to
  fight in a missing one's place, stood up and scaled to the spec's height
  with the stand-in's own clips (`UnitNode.clipAsset`), so a boss whose
  mesh is still on the way is a giant of its kind rather than the
  loader's primitive: the Colossus stands in as a 4.5 m sentinel, the
  Unwrapped King as a 3.2 m mummy.
- Portraits go through `BundleImage` (UIKit lookup). SwiftUI `Image("name")`
  drew nothing for loose bundle PNGs on device; never use it for one.
- **The paintings ship as JPEG.** A Gemini card is a 1024 px painting with no
  transparency and its PNG was 1.3 MB, so 154 cards were 209 MB of the bundle
  and batch 3's three hundred more would have added four hundred.
  `python3 tools/shrink_art.py` converts every alpha-less painting in
  `Pantheon/Resources` to JPEG at quality 92 (235 MB → 38 MB) and every card
  script ends by calling it; the UI kit, the tiling stage textures and the
  three sprites keep their alpha and stay PNG. `UIImage(named:)` finds a file
  whatever its extension, but a lookup by name *and* extension does not, so
  `hasShippedArt` and `ModelSpec.portraitName(awakened:)` go through
  `BundleArt` (Presentation.swift), which tries jpg then png. The concepts in
  `Art/Concepts` stay PNG: Meshy reads them.
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
  is **3,000 credits** (raised from 500 with the 8,000-credit plan on
  2026-09-09): check `python3 tools/meshy.py balance` before every launch and
  never plan past it. A character is 53: 30 image-to-3D, 5 rig, 3 a clip.
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
