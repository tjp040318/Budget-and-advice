# Working agreements

## Answers

**Give exact, numbered steps.** When the answer involves doing something —
tool settings, a pipeline, a fix — write it as a numbered list of actions to
take in order, not as prose to interpret. Name the specific button, field,
value or filename. If there is a decision point, state the condition and both
branches rather than hedging.

Keep the reasoning, but put it after the steps or inline as a short "why",
never in place of them.

## The owner's two standing rules (2026-09-11)

**1. Finished work is shown, not described.** When a piece of work is done —
a screen, a fight, a fix, a batch of models — send the owner pictures of it
with the report, before he tests anything: `SendUserFile` with the CI frames
of the screens touched (`python3 tools/ciframes.py`, then compose the frames
that matter into one or two sheets with PIL, portrait frames stood up with
`rotate(90, expand=True)`) and, for models, the preview sheets
(`tools/preview.py --sheet`) or one board of the families shipped
(`python3 tools/roster_board.py <families> --out board.jpg`: each family's
base model in its three views, named). "Send me screenshots of what you did
even before I test. This includes the Meshy models. This will help me
respond faster." A picture he can see in the chat; a sentence about a
picture is not the rule.

**2. Research the best way before building, every time.** "When I tell you
to do something, ALWAYS research the most effective way to do it with the
highest quality. This game is my livelihood and it will be my full-time job.
I need this at 10000% quality." So a task starts with its research, not
its first edit: how the best of the genre does this thing (Summoners War
first — its screens, its camera, its numbers — then Epic Seven, Raid and
whatever the task calls for), what the tools can actually do (Meshy's
API options, SceneKit's features, Apple's documentation, the packages
reachable from here), and what this project already learned (`Docs/PLAN.md`
and the git history hold every camera, every rig refusal and every measured
cost). Compare the approaches, pick the one that gives the best result
rather than the quickest, and write the options and the choice into
`Docs/PLAN.md` before building — the owner reads that reasoning. Then build
it whole, verify it (the CI frames, the preview sheets, `swiftcheck`,
`balance.py`), judge it against the genre's own screen before handing it
over, and show it (rule 1). Never ship the first thing that works when a
better way is one search away; never leave a known lesser version in place
without saying so and what the better one costs.

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

- The game builds and runs on an iPhone, **landscape only**. **The battle
  is laid out the genre's way (2026-09-11 evening, the fourth camera, and
  the owner's own words for it: "Summoners War has it from the back but
  slightly off to the right").** The camera stands BEHIND the player's
  team, above it and a little to the right (`CameraDirector.homeYaw`
  −15°, `homePitch` 26°, a 30° lens, solved by `CameraDirector` from the
  figures on their marks: about 14 m out for a three-a-side, the team's
  figures a quarter of the frame tall, 16 m for a five); the team stands
  in a ROW across the bottom of the frame with its back to the camera at
  z = +3.0, the enemy in a row across the middle facing it at z = −3.0,
  2.4 m from mark to mark and the enemy row 0.6 m to the right so no enemy
  is ever straight behind a player (`BattleSceneController.position`),
  which puts every enemy alone against the floor where a finger finds it,
  the enemies' feet a tenth of the frame above the team's heads; the
  ground is a 44 m square slab (`StageBuilder.slab`, `battleFloorSize`)
  whose only edge in view is the far one, a low parapet level across the
  frame about 27% down (`battleFloorFarEdge` −8.4) with the painting
  above it; and the sets' side pieces stand at 8.5 m, the frame's edge
  (`StageBuilder.clearOfTheWings`). The three cameras before it are in the
  git history with their lessons: rows abreast at 27° over a small disc
  photographed as "a tilted disc in a void"; lines abreast turned 58°
  round read as columns but turned the whole world with them and were
  called "slanted" twice; and a straight-up-the-field 0° with the teams as
  two wings at the sides, on a 20° pitch, was "AWFUL — how do you expect
  me to click on the target I attack?" with a floor that "continues to
  look angled" (the 20° foreshortened it into a ramp). Rotating a cylinder
  cap's texture with `contentsTransform` did nothing visible in CI. A boss
  fight is framed the same way but wider (`bossYaw` −12°, `bossPitch`
  20°, the team's feet at `bossFeetLine` 0.92 — they were allowed just
  below the bottom edge at 1.05 until the unit plates went under the
  feet, which put the team's bars below the frame in every boss fight —
  and the head allowed to `bossTopLine` 0.90, the aim centred on the
  boss's head via `FramePoint.isBoss`: about 25 m out, the head 22% down
  under the bar; the numbers come from a sweep of a Python port of the
  solve; likewise `nearFeetLine` is 0.65, down from 0.74, so an ordinary
  fight's team plates clear the HUD's bottom bar), and the painting is
  hung between the two yaws
  (`StageBuilder.farBackdrop` turned to face `backdropYaw`). The field is
  measured when a wave is placed and at every turn's start, not only when
  the queue drains: an auto fight never drains it, so a boss arriving with
  the third wave was never measured for three runs of frames. A **boss**
  (`Combatant.isBoss`) stands a stride beyond the far edge at (0, −9.8),
  on a `StageBuilder.breach` (boulders, a rent in the floor, thrown
  tiles), lit like an awakened unit with an aura rising from below the
  edge, sunk 42% of its height below the floor, 6–8 m tall in the data
  (Apep 7.2, Hydra 7.0, Jötunn 7.5, Colossus 8.0, the Unwrapped King 6.0),
  with no 3D bar or ring (the HUD's boss bar reads), never dashes, and is
  framed by its head (`bossTopLine`) rather than its box; its adds stand
  on the marks in front, closing over the boss's slot (`markIndex`).
  Nothing tall stands nearer the camera than the team's row (z > 4): that
  is the foreground.
  On a player's turn every enemy wears a matchup arrow beside its bar
  (`UnitNode.setMatchup`: green up, yellow even, red down). The battle HUD is one
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
  currency only, a free daily offering; since 2026-09-11 a **Testing**
  stall gives every essence free and an **Essences** stall sells one
  awakening in a box per element, `awakening_cache_<element>`, so an
  awakening can be tested without a week of halls) and the **living
  island** (the campaign team stands on the painting; `IslandSceneView`).
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
- **Every element fights its own way (2026-09-10).** A table family's
  second and third skills are the element's, not the kit's:
  `UnitDatabase.elementalSkill(slot:kit:element:id:name:)` holds the forty
  (kit, element) pairs — fire burns and grows, water freezes, slows and
  drags the bar, wind repeats and hastens, light shields, cleanses and
  reveals, dark drains, strips and brands — and `elementalSkillNames`
  (the end of `UnitDatabase+Families.swift`) names them per family, ten
  names in `Element.allCases` order; a family missing from the table
  keeps its row's two names. `tools/balance.py` mirrors the pairs as
  `ELEMENT_SKILLS` and `--variants` prints the five forms of one family
  per kit against Anubis (the sim reads Burn, Stun, Def Break and
  "(Crit)" off a skill's name and nothing else, so a healer's or a
  warden's spread is a floor). Change a number in both files. The eleven
  hand-written families got the same by hand (2026-09-10, evening): each
  variant builder holds `let second: Skill; let third: Skill; switch
  element {...}` built with the `smite`/`ritual`/`status` helpers in
  `UnitDatabase+Roster.swift`, one element per family keeping the skill
  as first written (Anubis and Shabti dark, Sekhmet, Zeus, Ares and
  Heracles fire, Perseus light, Thoth, Hoplite and Harpy water, Satyr
  wind); `balance.py`'s `HANDWRITTEN_VARIANTS` mirrors all fifty-five and
  an import-time assert refuses to run if a reference blueprint drifts
  from its row. `DamageSpec.bonusPerMissingHealth` is the bonus at ZERO
  health, scaled by the fraction missing (`1 + bonus × fraction`): 0.8
  means up to 80% more, and 0.008 meant nothing.
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
- **Campaign tiers** (`CampaignDifficulty` in `StageDatabase.swift`): every
  chapter plays at Normal, Hard and Hell, chosen by three chips above the
  chapter map. A tier is DERIVED from the Normal chapter — `Stage.at(_:)`,
  `Chapter.at(_:)` suffix every id (`duat_1_5@hard`) — so each tier keeps
  its own high-water mark under its own key in `campaignProgress` with no
  new save field, and `StageDatabase.stage/chapter` and
  `CampaignService.isUnlocked` read the tier back off the id. Hard is a
  grade up, level ×1.15, stats ×1.2, every stage dropping a 5★+ relic,
  ×1.7 drachma/EXP; Hell two grades up, ×1.25, ×1.5, 6★ relics, ×2.6. Hard
  opens when Normal's boss falls, Hell when Hard's. `balance.py --tiers`
  measures it; change the numbers in both files.
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
- **Rome and the Jade Court exist as data (2026-09-11).** Twenty families
  in `UnitDatabase+Families.swift` (`familyRowsRoman`: Mars, Minerva 5★;
  Neptune, Pluto, Diana, Mercury, Bellona 4★; Centurion, Gladiator, Vestal
  3★ — `familyRowsChinese`: Sun Wukong and the Azure Dragon 5★; Nezha,
  Guan Yu, Chang'e, Nüwa and the Dragon King 4★; Fox Spirit, Jiangshi,
  Terracotta Soldier 3★), each with its ten elemental skill names; two
  banners (`Banner.eagleRises`, `.jadeCourtOpens`, offered once a family
  has cards); four chapters after Jötunheim (`rome_1` The Forum at
  Midnight, `rome_2` The Sand of the Colosseum, `jade_1` The Peach Garden,
  `jade_2` The Dragon King's Gate) whose enemies borrow the commons' models
  and stand in as shipped meshes until then (`enemy_centurion` … 
  `boss_bronze_colossus` on the Colossus, `boss_longmen_dragon` on Apep);
  four `BattleEnvironment`s (`forumRome`, `colosseumSands`, `peachGarden`,
  `dragonGate`) borrowing older paintings until theirs land, with sets in
  `StageBuilder.recipe(for:)` (`prop_stone_lion` and `prop_pagoda_lantern`
  are stand-ins until made). Both pantheons are in `Pantheon.live`. The
  concepts, cards, banners and backdrops are `tools/batch/concepts_batch4.sh`,
  `portraits_batch4.sh` and `realms_batch4.sh` for the night routine. **The
  meshes are in (2026-09-11 afternoon):** the owner said "don't wait till
  tonight, just do it now", so the twenty went to Meshy as text-to-3D from
  their written descriptions (`tools/batch/text_wave.py`, the concept
  script's sentence after an A-pose prefix; Gemini was capped), 1,063
  credits, and eighteen shipped: sixteen rigged characters from
  `wave4.txt` and the two dragons from `beasts4.txt` (four claws, no rig,
  `beast_wave.sh`, moved procedurally like the Hydra). Meshy's rigger
  refused **Neptune and the Terracotta Soldier** twice — a pole weapon held
  out beside the body with its shaft on the ground reads as a third leg —
  so they fight as Poseidon and the sandstone sentinel (`FamilyRow.standIn`)
  until the owner pays for a `_v2` (56 each, a short weapon flat against
  the thigh, no cloak; the balance would end near 2,021). The Dragon of
  Longmen stands in as the Dragon King's mesh now, the Colossus of the Sun
  still as the Vault's. Their cards are tonight's Gemini batch, so the
  families join the gacha pool in the morning; the meshes are seen at once
  in the Rome and Jade chapters, whose enemies wear them. The owner
  lowered the floor to **2,000** on 2026-09-11 (1,500 for an hour, then
  "2000 is okay") for exactly these twenty; the balance is 2,133.
  `balance.py --chapters` and `--families` measure them; the rows and the
  four chapter lines are mirrored there.
- **The collection has two layouts (2026-09-11)**, switched in the strip and
  remembered (`collectionLayout`): **Cards** — the grid at 55% of the width
  and a plate on the right for the unit picked (portrait, grade, level,
  power, the four stats with the relics' share, the six slots as a 3×2 of
  `RelicSlotTile`s, the sets, Full sheet / Train); **Stage** — a rail of
  small cards along the bottom, the unit's real model on a rune ring in
  the right half of the summoning hall (`CollectionStageView`, the Hall
  of Ka's altar without the rites; a drag across that half turns it) and
  the same words and slots on a cream plate over the left. A tap on a
  card PICKS; Full sheet opens the unit sheet, a slot opens the picker for
  that slot. The tour's step 21 photographs the Stage.
- **The UI is cream and gold (2026-09-11)** — "like a Greek temple", the
  owner said of the black. Every token in `Theme.swift` turned: ink
  #1F1912 is the text, the grounds are `surface` #EBE2CF, `surfaceRaised`
  #F6F0E3, `surfaceHigh` #FDF9F0, the accents gold #B08A2E / #8C6D22 /
  #5C4611, and a translucent plate over a stage or a painting is
  `Theme.plate` (#F4EDDD) at 0.4–0.85, never `Theme.ink` — ink text on an
  ink plate is the black UI back again. `GameScreen` forces
  `.preferredColorScheme(.light)`. The marble menu kit's slate panel and
  slate button (`ui_panel`, `ui_button_dark`) are held back by
  `Chrome.awaitingCreamRepaint` until `tools/batch/ui_marble.sh` repaints
  them cream with a gold frame; the marble ribbon and the bronze button
  are live.
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
- **The Hall of Ka is a place (2026-09-10).** `TrainingView` is the summon
  screen's shape: the sanctuary painting `hall_of_ka_bg` (16:9, its
  altar dais in the left third, centre 29% across and top 80% down) as
  a `.background`, the chosen unit's real model standing on the painted
  dais in a transparent SceneKit view the size of the frame
  (`AltarStageView`: rune ring, contact shadow, the reveal's lens,
  camera shifted not turned so the feet land on the dais), the roster
  a rail of single cards down the left edge, and the mode's fodder,
  requirements, cost and button a 424-pt panel over the right. A rite
  plays on the altar (`AltarCeremony`, stamped so each plays once): fed
  units fly in as orbs of the element and the figure flares under a
  beam, an evolution or awakening swells it in a pillar of light, and
  the words of the moment (`AltarStamp`: LEVEL UP!, EVOLVED) spring in
  over it. The fusion board keeps its row of panels over the painting.
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
  to prove it. **A clip file's mesh is a 1,500-triangle carrier** (the game
  reads it once and discards it), so since 2026-09-11 each clip is grounded
  and measured on the FULL mesh before the reduction — at that budget a
  small shell can vanish outright (Diana's boots did; the carrier's lowest
  point rose 17 cm and a clip grounded on it would have sunk her that far)
  — and a clip is grounded on the **feet** while the pelvis stands above
  45% of its rest height, on the body with the legs left out when lying
  down (`character.ground_animation`): the Fox Spirit's nine tails are
  weighted to a thigh, swing 24 cm below the floor in her idle and 55 cm
  in her death, and stood her in the air both times. Families shipped before that
  day were grounded on their lowest vertex; a tail, a hem or a weapon
  carried low in most frames of a clip would have lifted them, and a
  reship fixes it. The first Anubis export loaded as gold shards for five reasons
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
  for parallax. A missing prop gets a built stand-in. **A Meshy prop is 30
  credits either way** — text-to-3D (preview + refine) or image-to-3D — as
  `Docs/PLAN.md` measured over ten props; the `cost` a manifest records per
  task is the balance's drop while that task ran, which twenty parallel
  tasks and Meshy's refunds turn into noise (a clip at −6, a preview at
  290), so never read a price off a manifest. **A prop goes image-to-3D
  from a Gemini concept** because the concept sets the look — paint it on
  a plain grey ground as `Art/Concepts/prop_<name>_sw.png`, then
  `python3 tools/meshy.py generate prop_<name> --image <concept> --until
  refine`, `download --include-unrigged` (the file is `_image.usdz`) and
  `tools/prop.py`. The reward chest went that way on 2026-09-10
  (`prop_reward_chest`), and `prop.py --split-lid 0.625` cut the one mesh
  into the box and a lid whose origin is its back-bottom edge
  (`RewardChestView` in `BattleView.swift` hinges it there: shake, lid,
  beam, flash, gone, spoils). The user bought the 8,000-credit plan on
  2026-09-09; the floor was 3,000 and is **2,000** since 2026-09-11 ("you can
  bring us down to 2000 credits, that's okay"), and `tools/batch/wave_run.sh` keeps
  every wave above it.
- **Battle feel.** A melee unit (`ModelSpec.melee`) dashes to its one victim
  for an attack clip and back at the next turn, and every hit flashes the
  victim white. **The camera is fixed by default** (`CameraDirector`): one
  home framing for the whole fight, a short push toward an ultimate's
  caster and back, a shake on heavy hits, nothing else — the genre's way,
  and what the user asked for after the old close shot left its look-at
  constraint on across a turn change. **Since 2026-09-11 (late) the fixed
  camera never turns**: a special, an ultimate and a killing blow get a
  dolly along the home line of sight toward the caster (or the victim, for
  an impact) and back — `CameraDirector.zoom`: the same yaw, pitch and
  lens, the figure about half the frame tall, eased in over 0.22 s and out
  over 0.30 s — which is Summoners War's skill camera. The hard CUTS it
  replaced (a three-quarter medium over a player's shoulder, a face-on shot
  of an enemy caster) were composed ANGLES, and the owner's arena frame of
  an enemy's turn showed the tiles running diagonally and both rows swung
  round: any frame in which the floor's lines run a different way from the
  home frame is a bug, whatever the shot was meant to be. The cuts, leans
  and orbits survive behind More → Sound & camera → Cinematic battle camera
  (`UserDefaults` key `cinematicCamera`). `returnHome()` clears the
  constraints, because cancelling a shot's action skips the completion that
  used to. The HUD's top centre is the **attack gauge** (`BattleView.turnGauge`:
  portraits on one track by `attackBar`, ready unit in gold); tapping a
  skill shows its name and description above the skill row and holding one
  opens a card. The painted chrome is drawn at 1/1.4 (`Chrome.shrink`),
  fonts at 0.9 (`Theme.fontScale`), cards 76pt: the playtest's density
  pass. The CI tour is twenty-two screens (steps 0–21): an arena battle
  (step 8) as well as the campaign one, the Labyrinth, a dungeon's
  levels, the relic picker, a Labyrinth run on auto (`dungeon_battle`,
  four frames, so the waves are seen walking on), the power-up screen,
  the victory's chest in three frames and the collection's Stage layout
  (21).
- **The fight reads.** **Every unit's bars are a screen-space plate under
  its feet (2026-09-11, night):** `UnitPlateOverlay`, a SpriteKit scene laid
  over the `SCNView` (`overlaySKScene`, in `BattleSceneView.swift`), one
  `UnitPlate` per non-boss unit, placed every frame by
  `BattleSceneController.layoutPlates` from `projectPoint` of the node's
  feet (view points, origin top; the overlay's origin is bottom, so y is
  flipped by the scene height). The plate is the genre's: a 64×5.5 pt green
  health bar (dark rounded track, gradient fill, amber under 30%, a cream
  trail that drains 0.35 s after a hit), the 64×2.5 pt light-blue
  **attack bar** under it (tweened to the engine's value when playback
  settles — `syncPlates` — and on `attackBarChanged`; gold and pulsing at
  100%), the element pip at the left, the status tiles above, the matchup
  arrow at the right, a gold rim on the acting unit. Green for both sides,
  as the genre has it. The 3D bar in `UnitNode` still exists for the
  island and the Hall of Ka and is hidden the moment a plate is attached;
  before this it hung 0.34 m over the head, lit and bloomed, and from the
  camera behind the team a player's bar landed on the floor at the
  enemies' feet as a gray block — the owner read those as the enemies'
  bars. Status effects are tiles over the health bar
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
- **Effects are painted sprites moved by code (2026-09-10).** Twelve
  element sprites (fireball, flame, ember, bolt, splash, ice shard, wind
  crescent, leaf, flare, ring, shadow wisp, smoke) are painted by Gemini
  on black (`tools/batch/vfx_sprites.sh`, sources in `Art/VFX/`) and
  shipped by `tools/vfx_ship.py` as `Portraits/vfx_<name>.png` at 256 px
  with alpha from the brightest channel (a sprite Gemini paints on WHITE
  ships as a white square — repaint it as a `--ref` edit of one that is
  on black; the flame took three tries). `VFXLibrary.sprite(_:)` finds
  them by name, `puff` throws them screen-facing, spinning, growing and
  fading, each `impact_<element>` is built from its own two, and
  `projectile` flies the element's sprite from a ranged caster's chest to
  the victim's on an arc, launched by `BattleSceneController` to land on
  the frame of contact. A missing sprite falls back to the spark. An
  effect authored in Xcode's particle editor and dropped in the bundle as
  `<identifier>.scnp` replaces the code-built one, so the owner can design
  a hit by hand. The key also lists Veo 3.1 video models (a clip on black
  cut into frames would be a real flipbook); it is billed per second and
  is not to be used without the owner's word. **Since 2026-09-11** a cast
  (`castRelease`, `ultimate`) opens a rune ring under the caster
  (`UnitNode.castRing`), every melee swing draws a ribbon from the weapon
  hand (`UnitNode.swingTrail`: a triangle strip re-sampled each frame from
  the hand bone, additive, steel for an attack and the element for an
  ultimate), and a non-speech cut-in flashes the screen white for half a
  second (`BattleView.ultimateFlash`).
- **Bespoke clips from a sentence (2026-09-11).** Meshy's Text to Motion
  API makes a motion clip from a description (10 credits in prime mode,
  3 in swift; 2–10 s in 0.5 s steps) and the Animation API applies it to
  a rigged character in place of a preset (`motion_task_id`, 3 credits):
  `python3 tools/meshy.py motion zeus_hd ultimate --prompt "..." --duration
  3` creates both, resumably, and files the clip in the manifest under the
  clip's name, so `download` and `python3 tools/mesh.py zeus_hd --as zeus
  --only-clips ultimate` ship it as `zeus_ultimate.usdz` alone and the
  game plays it with no change. Ask for 3 s for an ultimate and 2 s for an
  attack: the engine retimes every one-shot to its contract (2.4 s and
  1.3–1.7 s) between 0.6× and 2×, so a 4.5 s clip is a flicker. Judge a
  clip with `python3 tools/preview.py Art/Models/<asset>_<clip>.glb
  --frame N` at a few frames. Zeus's ultimate was the first (both arms
  overhead gathering, a lunge and an overhand hurl, a settle; 26 credits
  for two takes). `docs.meshy.ai` is closed to this environment; the
  field names were read off the API's own validation errors, which an
  empty body returns without creating anything.
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
  written to a file. **GEMINI IS PAUSED (2026-09-11).** The owner: "don't
  use the Gemini API. You used $100 worth of it already! Stick to $10 per
  month." Nothing here may call it — no batch script, no `genart.py`, no
  night routine — without his word for that specific batch, and the cap is
  $10 a month. The painter's default is `gemini-3-pro-image`, a pro-priced
  model; the ~720 shipped images plus their retries came to the $100, so
  a night's batch of 250 is roughly $30 at that price and $10 buys about
  80 images — or about 250 on `--model gemini-2.5-flash-image`, whose
  cards would have to be judged first. **One batch is authorised** (the
  owner, later that evening: "finish with that $32 worth of art you need
  and then stop for now until I can figure out costs"): the cream repaint
  of `ui_panel`/`ui_button_dark` (2 images), Rome and the Jade Court's
  banners and backdrops (6), concepts (20) and base cards (100), and batch
  3's missing awakened cards (about 130) — the night-3 routine
  (`trig_01VJjUcbfKs8vRHiC1qHtAH7`, 00:25 UTC) runs exactly that list,
  spills its leftover to one more night if the 250-a-day quota ends it,
  reports the image count, and nothing else is painted afterwards. Batch
  4's awakened cards are NOT in it. Gemini's key allows 250 image requests a day; a
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
  is **2,000 credits** (500, then 3,000 with the 8,000-credit plan on
  2026-09-09, then 2,000 on 2026-09-11 to afford Rome and the Jade Court's
  twenty): check `python3 tools/meshy.py balance` before every launch and
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
