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
used here; it is now clean and worth running. Swift's leading-dot shorthand
has no compiler here, so the checker reads it: a switch must handle every
case of the enum its subject is declared as, and `: SomeEnum = .case` must
name a real one (`var element: Element = .light` cost a CI run on
2026-09-15 — the elements are `.ember`, `.tide`, `.gale`, `.radiance`,
`.umbra`). Two more rules came out of 2026-09-16's red build: a call must
fill every `init` parameter that has no default, counting trailing
closures as well as parenthesised arguments (`GameScreen { ... }` filled
one of three — every screen writes it `GameScreen("Title", subtitle:,
dismiss:) { bar } content: { ... }`), and a lowerCamelCase name the whole
tree spells exactly ONCE and reads as a value is a name nothing declares
(`unseenIntroChapter`, left behind when the property it read was deleted
with the code around it). Three more came out of the same day's later
runs: a switch whose subject type cannot be read off the enclosing
function is identified by its case LABELS instead (nine of ten cases and
no default is a switch that has drifted); `case ...: return nil` inside a
function declared non-Optional is an error; and a `?:` whose two branches
are design tokens of DIFFERENT types will not compile —
`canReroll ? Theme.goldPlate : Theme.surface` mixes a LinearGradient with
a Color, and every screen that needs that uses a `Group { if … else … }`.
And a rewrite that replaces a declaration from its first line leaves the
OLD `@ViewBuilder` above the new doc comment, so the declaration carries
two ("only one result builder attribute can be attached", run 163): the
checker reads a builder attribute followed, through comments, by another.
And a STATIC member on a class named `Coordinator` makes the checker read
every `Coordinator.x` in the tree as that class's — the battle view's
`#selector(Coordinator.handleTap(_:))` is another class of the name — so the
island's coordinator keeps its constants as instance lets (2026-09-17, twice).
And no constant or variable may be named with a keyword: `let internal =
info.internal` failed run 249 (the member after a dot is fine, the binding is
not), and `check_keyword_bindings` reads every `let`/`var` for one.
Every rule in the checker was
proven by reintroducing a real bug and watching it fail.

If a tuning constant changes in Swift, change it in `tools/balance.py` too. They
are kept in step by hand.

**And grep `PantheonTests/` for it in the same breath.** That is the THIRD
place a constant lives and the one neither checker can see: `swiftcheck` reads
shapes, not numbers, and `balance.py` is a mirror the tests know nothing about.
Capping the Halls at 5★ on 2026-09-16 cost a red run because
`DungeonTests.testFloorsClimbAndPayTheirElement` pinned the top floor to `6` —
the build compiled and five tests failed. A test that pins a tuning number
should say the INTENT beside it (the Hall's floor is now asserted to be *below*
`labyrinthGrade(level: 10)`, not merely equal to 5), so the next change to
either number fails loudly instead of drifting.

**And keep arithmetic out of an assert's parentheses.** `XCTAssertEqual(a.x
/ b.x, 1 + Family.base, accuracy: 1e-6)` is an autoclosure the type checker
solves with every numeric overload in play, seconds each; forty of them in
`BoonTests` and `ResonanceTests` took the test target's compile from six
minutes to ten on 2026-09-16 and put run 161 over the job's 40-minute limit
(70 after run 222 took 50 of 55 on a slow simulator; 90 since run 237, whose tour of 52 steps and a 5-minute checkout left ten minutes spare). Hoist into typed lets — `let lift: Double = …` — and assert the
names. The tests themselves run in twenty seconds.

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
tools (`actions_list`, `get_job_logs`) — but for a RED BUILD read
`python3 tools/ciframes.py` FIRST: the log API serves only the TAIL of a
job, a compiler error sits near the top of a 550-line job whose last 300
lines are the simulator booting, and chasing one through the tail cost
three whole-log fetches on 2026-09-16. The job now publishes its error
lines to `ci/screens` as `build-errors.txt` and `test-errors.txt`, which
`ciframes.py` prints before anything else, for nothing. Look at the frames with
`python3 tools/ciframes.py`, which fetches the `ci/screens` branch the job
force-pushes them to (the artifact store is on a host the network policy
refuses) and prints the lines that matter from each step's console, which
the job publishes beside the frames (`<step>-console.txt`, the app's stdout
and stderr with the frameworks' os_log lines mirrored in). A frame that came
out wrong can be read as well as looked at — `python3 tools/framelight.py`
prints how bright every battle frame is, per band, and what share of it
has no detail left (the target is under 2% over 240 with the mean in
70-130) — and a launch that died leaves
its crash report beside the frames (`crash-*.txt`, the host's report for
the app, its crashed thread printed by `ciframes.py`; `system-log.txt`
covers the whole tour; a relaunch within a step, the workflow's `again`,
appends its own output to the step's console under the arguments it ran
with, since run 223). Never push without reading the
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
  20°, the team's feet at `bossFeetLine` 0.82 — they were allowed just
  below the bottom edge at 1.05 until the unit plates went under the
  feet, which put the team's bars below the frame in every boss fight;
  0.92 still had them on the edge under the actor plate —
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
  On a player's turn every enemy wears a matchup arrow over its plate
  (`UnitNode.setMatchup`: green up, yellow even, red down). **The cameras
  are the genre's since 2026-09-15** (the owner's Summoners War frames,
  measured): home `homeYaw` −32°, `homePitch` 36°, `nearFeetLine` 0.82 —
  HIGH, so the floor reads, and turned so the two rows lie on a diagonal,
  the team across the lower left, the enemies across the upper right;
  the boss `bossYaw` −8°, `bossPitch` 8°, `bossFeetLine` 0.94,
  `bossTopLine` 0.98 — LOW and close, the boss ON the rim
  (`bossMark` z −8.4, `bossSink` 0.32) filling the upper half of the frame
  with its head at the top edge, the team large at the bottom, and a warm
  spot light riding with every boss aimed at its chest ("it's hard to
  see the boss"). The numbers before them (−15°/26°, −12°/20°, the boss
  at −9.8 sunk 42%) are the paragraph above and the git history.
  **Since 2026-09-24 (the owner's two Summoners War frames, measured:
  pitch 19° off the arena's gold ring for any lens, yaw 0, a 24–30°
  lens, the rows ten metres apart and the team a third of the frame
  tall; PLAN.md *The owner's angle and the clean frame*)** the camera
  stands square BEHIND the team: `homeYaw` 0, `homePitch` 19°, a 28°
  lens, its distance solved in closed form from two feet lines, the
  team's on `nearFeetLine` 0.72 (86% down) and the enemies' on
  `farFeetLine` 0.26 (37%) — about 18 m out, the team 0.30 of the frame
  tall and the enemies 0.18, the team's feet held inside 0.24–0.76 of the
  width (`teamWidthMargin` 0.64; a five-a-side stands 2.0 m apart); the
  boss `bossYaw` 0, `bossPitch` 9°, `bossFeetLine` 0.92, `bossTopLine`
  0.88, every boss's head 7–17% down. The rows stand
  `StageBuilder.arenaRowDepth` 5.2 m either side of `arenaCentre` z +1.8
  (the team +7.0, the enemies −3.4: the whole field moved toward the
  camera, not the enemies into the sets' back row), the team 2.4 m apart
  with every other mark 0.5 m nearer, the enemies 3.2 m apart with every
  other one 1.0 m further back, no sideways push; a wave walks on from
  2 m behind its marks. The far edge is −11 (`battleFloorFarEdge`, the
  parapet 24% down), the boss on it and the sets' back row carried back
  with it (`StageBuilder.withTheFarEdge`); the side walls stand at ±11.3
  (`arenaHalfWidth`, clear of the long wing pieces); the floor under the
  fight is a medallion per pantheon built at runtime as geometry
  (`StageBuilder+Arena.swift`: stone courses, a raised gold band round
  both rows, the pantheon's emblem; it replaced `arenaInlay`); and every
  battle unit stands on a soft oval (`UnitNode.attachGroundShadow`) and
  casts no key-light shadow of its own. `tools/camera_solve.py` is the
  solve's Python port: change a camera number, a mark or the far edge
  there and in Swift together. The older numbers in this bullet
  (−15°/26°, −32°/36°, −8°/8°, the rows at ±3, the edge at −8.4, the boss
  at −9.8) are history. The summon reveal is stage left and words right,
  and the island painting is 16:9.
- Battle, summon, collection, arena, campaign and the Hall of Ka (training:
  power-up, skill-ups from duplicates, evolution, awakening) all work. So do
  the **Labyrinth** (a building on the island, `LabyrinthView`: three
  relic dungeons and the five Halls of Essence; `DungeonDatabase`;
  a dungeon level is one battle of three waves), **the sweep**
  (`SweepService`, `SweepView.swift`: a stage THREE-STARRED at this tier,
  whose campaign team still meets its recommended power, is cleared N times
  with no battle for the same energy — the button sits beside Begin in the
  briefing and on the stage popup, the receipt is the win's own
  `SpoilsPanel`, and every run goes through `CampaignService.settle`, the
  one path a fought run takes as well, so the two cannot pay differently;
  `balance.py --sweep`; tour step 34), **auto-repeat**
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
- Twelve chapters: Duat 1–2, Olympus 1–3, Yggdrasil 1–3, Rome 1–2, the
  Jade Court 1–2. **Every campaign stage is THREE WAVES (2026-09-15; the
  owner: "most bosses and levels are 3 waves, 1 being a boss"):** two of
  the chapter's mobs at ×0.75 then ×0.85, and a third with two adds and
  either the chapter's boss (×1.4, the last stage) or a leader of the
  roster a grade up and ×1.3 (`generatedChapter`; Duat 1 by hand in
  `laterWaves`); wounds and cooldowns carry across waves, the boss speaks
  when its wave arrives (`announceBoss(ifPresentIn:)`), and the third
  star's par is the old 18/30 turns × the waves × 0.8. The generated ones
  take `enemyStars` and `difficulty` (later chapters field the same
  creatures at a higher grade, not at absurd levels); the curve is measured
  by `python3 tools/balance.py --chapters` (three waves, `generated_waves`),
  `--campaign` and `--halls`, and a change to a chapter's numbers goes
  into both files. Campaign enemies borrow the
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
- **Mileage and the selector** (`MileageService`, `SelectorService`,
  `MileageView.swift`): one point per summon on a banner, spent on a unit of
  the player's own choosing from THAT banner's pool (per banner, so the cheap
  Unknown Scroll cannot be farmed into a 5★ god). The price is anchored to
  the banner's OWN hard pity at 1.7× what the guarantee costs, with a flat
  divinity target (3★ 2,000, 4★ 6,000, 5★ 15,000) as a second floor for the
  banners that have none — a flat target alone priced a Light & Dark 5★ at
  0.28 of its pity, which `balance.py --mileage` caught and now asserts
  ("the cheapest ratio on any banner is 1.70x -> correct"). The exchange is a
  chip in the summon room's header. The **selector** is one 4★ of the Duat
  picked on day one, five candidates derived one per element and sorted by id
  so the list never changes under the player; it opens itself the first time
  the summon screen appears and is spent once ever
  (`Player.selectorClaimed`). The pity chip counts DOWN ("5★ in 78"), which
  is how every published tracker in the genre words it. Tour steps 35 and 36.
- **Scrolls are banners** (`Banner.scrollBanners`): Unknown (3★ commons),
  Divine (4★+), Light & Dark, Fire, Water, Wind, each spending its own
  `ScrollType` and drawing from `SummonService.pool(where:)`. The summon
  screen has two chip rows, pantheons and scrolls, with counts. The
  bazaar sells every one (Unknown for drachma).
- **The campaign is two maps and a popup (2026-09-14).** `CampaignView`
  opens on the world road (`WorldRoadMapView`: the painted world with a
  city per chapter); a city opens the chapter as a PLACE —
  `ChapterMapView` full bleed: **the chapter's own painted map** where it
  has one (`ChapterMapArt.byChapter`: the region seen from above with its
  road and landmarks, `map_<chapter>.jpg`, one Gemini image at 21:9 —
  Duat 1 first on 2026-09-14 (14 cents) so the owner could judge one,
  then, on his "I love it, go ahead and make the other maps", the other
  eleven the same evening (`tools/batch/chapter_maps.sh`, $1.55), so
  EVERY chapter has its map; the medallions and the chests stand on landmarks MEASURED
  off the painting with a grid, in 0…1 of the painting, placed through
  the fill's crop by `ChapterMapArt.place` — `python3 tools/mapgrid.py
  <map> --dots x,y … --chests x,y …` draws the grid and a guessed row on
  the painting, and every row was looked at that way; a ten-stage
  chapter's medallions stand on its five landmarks and the road between
  them; the code road is not drawn on a painted map; CI step 28
  `chapter_maps` relaunches the app once per chapter with
  `-tour-chapter K` and photographs all twelve) or, for a chapter without a row, the stage's
  painting with the dotted road winding through the middle band and a medallion per stage
  (52 pt, 64 for the boss; gold with a check once cleared, a pulsing ring
  where the player stands, a lock beyond, star pips under each), the
  three tribute chests along the bottom of the road, one plate at the
  top left (realm · chapter, the story line, progress, Next, YIELDS,
  and Hard's or Hell's terms as its last line), the tier chips
  (`TierChips`) in the empty CENTRE OF THE STRIP — the genre's top-bar
  tabs; they stood at the top centre of the painted map for one run of
  frames and collided with the plate, and the World button gave up its
  place since the chevron is the same door — and an arrow at either
  edge to the chapter before and after. No header panel, no list: the
  owner, of the strip-over-panel-over-list it replaced, "looks so dumb …
  I want just a map". A tap on a medallion opens `StagePopup` over the
  dimmed map (the end of `CampaignView.swift`): the stage and its place
  on the road, the chapter's story line, the first wave's enemies as
  cards, DROPS with the chapter's two set gems first, the relic chance
  and grade, essences, scrolls, drachma and the first-clear divinity,
  your power against the stage's, "Team & runs" (the full
  `StageBriefingView` sheet) and "Fight — N energy" (one run with the
  campaign team). The chapter strip is gone; the Realms sheet
  (`WorldMapView`) still lists every chapter, Rome and the Jade Court
  included, which have no city on the world painting yet. Tour step 13
  is the map, step 27 the popup on the fourth stage.
- **Campaign tiers** (`CampaignDifficulty` in `StageDatabase.swift`): every
  chapter plays at Normal, Hard and Hell, chosen by three chips above the
  chapter map. A tier is DERIVED from the Normal chapter — `Stage.at(_:)`,
  `Chapter.at(_:)` suffix every id (`duat_1_5@hard`) — so each tier keeps
  its own high-water mark under its own key in `campaignProgress` with no
  new save field, and `StageDatabase.stage/chapter` and
  `CampaignService.isUnlocked` read the tier back off the id. Hard is a
  grade up, level ×1.15, stats ×1.2, ×1.7 drachma/EXP; Hell two grades up,
  ×1.25, ×1.5, ×2.6. Hard opens when Normal's boss falls, Hell when Hard's.
  **The relic floor climbs with the CHAPTER as well as the tier
  (2026-09-16)** — `relicGradeFloor(chapterOrder:)`, Hard `3 + (chapter-1)/3`
  and Hell one better, capped at 6, with `StageDatabase.chapterOrder(of:)`
  reading a chapter's place off the road and an unknown falling back to the
  FIRST chapter's floor, never the last. It was flat (Hard 5★, Hell 6★ on
  every chapter), which had chapter 1 on Hell paying a 6★ for 22,400 power
  where Labyrinth B10 asks 30,645 — and once that is true every harder thing
  in the game is something a softer thing already out-paid. **`balance.py
  --drops`** ranks every source by the power it asks against the grade it
  pays and is what caught it; it also caught the Halls out-dropping the
  Labyrinth (capped at 5★ now — they are the ESSENCE farm) and the Endless
  Tower under-paying (`towerGrade` is `3 + (floor-1)/16`, so F50 pays the 6★
  its own notes say needs a maxed 6★ team, where it used to pay 5★). The
  earliest 6★ in the game went from 13,476 power to 30,300. `balance.py
  --tiers` measures the rest; change the numbers in both files.
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
  animation. **A raid is graded F→SSS and pays Aether (2026-09-16, phase 1
  of the Titans; `RaidGradeService`, `Docs/PLAN.md` *Awakened relics and
  the Titans*):** a kill on its PACE against `enrageTurn` (SSS inside 70%,
  SS 85%, S before it enrages, A within 130%, any kill B), a run the boss
  survived on `BattleResult.raidShare` (C from 60% of its health, D from
  30%, F below — never a B, so a kill always outranks a non-kill); total
  damage would run backwards on a killable boss (the barrier regenerates,
  the guard heals). Aether by grade — F 0, D 2, C 4, B 5+1 pure, A 6+1,
  S 8+2, SS 10+3, SSS 12+4 — in the boss's element (`aether_ember`,
  `aether_gale`) plus `aether_pure` from a kill only; `Player.aether` and
  `Player.raidGrades` (the best grade per raid), both Optional; S/SS lift
  the raid's relic to Hero, SSS to Legend. The reckoning and the spoils
  panel wear the stamp (`RaidGradeStamp`), a lost raid opens the chest on
  its aether alone, the raid card shows the best grade and the mark to beat.
  `balance.py --grades` grades the raid sim's ladders (the best team sits on
  the serpent's S/A line by design) and asserts the shape; change a number
  in both files and in `RaidGradeTests`. Tour steps 38 (`raid_grade`) and
  39 (`raids`). **Relic awakening (2026-09-16, phase 2):** `Relic.awakened`
  (Optional; `isAwakened`, `subStatCap` 5 instead of 4 — EVERY place that
  adds a sub stat reads `subStatCap`, never a literal 4), the +15 main stat
  at `Relic.awakenedPeak` 3.6× instead of `peak` 3.0×, a halo on
  `RelicIcon`, an Awakened chip and filter. `RelicService.awaken` on a 6★
  +15 only: 60 aether of the set's own colour (`RelicSet.aetherElement`) or
  90 of any other, plus 15 pure — the colour is a PRICE, not a gate, so
  every set is awakenable from the two Titans that exist — and the fifth
  sub opens as the same choice of two a +3 offers (`pendingRoll`). An
  awakened DROP (`generate(awakened:)`, one more sub than its quality;
  `StageRewards.awakenedChance`: Labyrinth B10 4%, Tower F90+ 6%, Hell from
  chapter 7 2%, raids SS 8% / SSS 15%). The panel and the rite
  (`RelicAwakeningRite`) are on `RelicDetailView`, not the Hall of Ka — a
  relic is a stone, not a figure for the dais; PLAN.md says why.
  `balance.py --awakening` asserts a well-rolled ordinary 6★ still beats a
  badly-rolled awakened one and the average premium sits in 1.05–1.40×.
  Tour step 40 (`relic_awaken`, two frames). **The five Titans (2026-09-16,
  phase 3, no credits):** the Raids wing is the **Titans** wing — a rail of
  five down the left and one card (`LabyrinthView.titansWing`) — and
  `StageDatabase.raids` holds one Titan per element: the serpent (ember),
  the Jötunn (gale), and the three Labyrinth bosses fought as raids, the
  Hydra (tide, `raid_hydra`: the GUARD, heads that grow back), the
  Colossus (radiance, `raid_colossus`: the SHELL, 16% bronze and a 2-turn
  stun when it cracks), the Unwrapped King (umbra, `raid_unwrapped_king`:
  the CLOCK, an enrage at 55). Their meshes, paintings and lines were
  already in the bundle. A Titan's enrage turn is set where the sim's best
  team's median kill falls (`balance.py --grades`, `RAIDS`): 65, 60, 80,
  82, 55. `testShippedRaidsAreWellFormed` asserts one Titan per element.
  **The guided first hour** (`FirstHourStep`, `IslandView`): four
  steps pointing at the landmark each wants, with a skip chip and a chapter
  intro card shown once. Five new save fields, every one Optional with a nil
  default.
- **Boons: the earned socket (2026-09-16).** The disc at the centre of a
  unit's relic ring is a SOCKET holding ONE conditional line — a `Boon`
  (`Boon.swift`: nine `BoonFamily`s, a Bane and a Ward in the five
  colours, so seventeen `BoonKind`s; grade 4–6★; a rolled `magnitude`;
  up to five `pushes`). A `BoonCache` opens as THREE DOORS derived from
  its seed (`BoonService.offers`), the kind chosen rolls 0.75–1.25× the
  grade's base, and a push (drachma + four aether of the colour, or two
  pure) is a choice of two bumps through `pendingRoll`, five at most.
  The engine reads the line at four hooks (`BattleEngine.
  boonDamageMultiplier`, the battle start, the turn start, after the
  hits) and it changes no stat. Caches come from a Titan at S+ (25%,
  6★), Labyrinth B10 (10%, 5★), the Tower's milestones and Hell's
  Judgment; never the Halls. `BoonPickerView` is the list and the panel
  (tour step 41); the Relics menu opens it as the inventory. Every base
  is MEASURED: `balance.py --boons` plays each kind on five fights and
  asserts every kind's best fight lifts 6–18% and none tops more than
  two — change a base in `BoonFamily.base` and `BOONS` together, and
  `lastStandBelow` with `BOON_THRESHOLDS`. Last Stand is +70% under
  HALF health (the design's "+30% under 40%" measured 0%), Hydra's
  Blood 5% (10% gave back 30% of the damage taken). The sim numbers
  fighters at birth to break speed ties (`Fighter.seq`); it broke them
  on `id(f)` before, which made a report's numbers differ between
  processes.
- **Pantheon resonance (2026-09-16): set bonuses that read the whole
  lineup.** `Resonance.swift`/`ResonanceService`: a PAIR of one pantheon
  lights its resonance at rank I, THREE or more at rank II, four
  different pantheons the Concord — The Weighing of Hearts (Egypt, +8/12%
  damage against a debuffed enemy; rank II's first fallen leaves its Ka,
  the others heal 15%), Olympian Hubris (Greece, crit damage; a kill feeds
  25 bar), Valhalla (Norse, attack; a fall gives the others Attack Up a
  turn), The Legion (Rome, defence; the first under half gets a 20%
  shield, once), The Mandate of Heaven (Jade Court, health; the first
  under half gets Recovery, once), Concord (+6% attack/health/defence,
  +5% accuracy/resistance). Read in `BattleEngine.init` for the PLAYER's
  lineup and the arena's defender only — never a campaign wave, so the
  tuned curves stand — and applied in `buildSide` in a leader skill's
  terms; the hooks are `resonanceDamageMultiplier`, `resonanceOnFall`,
  `resonanceOnKill`, `resonanceOnLowHealth`. The team picker's rail shows
  the lit ones and the nearest unlit hint (tour step 42). Every rank is
  measured by `balance.py --resonance` on the mean of two real-lineup
  fights (rank I 3–8%, rank II 8–16%, asserted); change a number in
  `ResonanceService` and `RESONANCE`/`RESONANCE_HOOKS` together. Four of
  the design's lines were moved by the measurement (PLAN.md has which and
  why): a flat opening shield or heal is never worth what it looks like.
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
  are live. **The night-3 routine repainted both (2026-09-12, first roll
  each):** a cream marble panel with a thin gold frame and scrolled
  acanthus corners that reach 95 px in (`Chrome.panelInsets` 98), and a
  cream plate with a gold border and 19 px gold ends (`darkButtonInsets`
  22); the hold-back set is empty and every piece of the kit draws.
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
- **The app opens on a loading screen that is a piece of key art
  (2026-09-12, night).** `LaunchView` (RootView.swift) sits over
  `RootView` in `PantheonApp.gate` until `LaunchProgress.finished`: one
  of the five banner paintings full-bleed, anchored to its top so the
  faces stay (the five take turns by `launchCount` in UserDefaults),
  pushed in 7% over nine seconds, faded up from ink, a vignette top and
  bottom, embers on a `TimelineView` canvas, PANTHEON in Cinzel on the
  clouds with the five pantheons under it, a 280-pt gold bar tied to
  four real steps (`UnitDatabase.summonPool`, `StageDatabase.allStages`,
  the Labyrinth, the bundle's index), a tip from ten, the version. Held
  no shorter than 2.6 s, then a 0.9 s dissolve; no "touch to start",
  which is a server handshake this offline game has no use for. The
  system launch screen is ink (`LaunchBackground` in the asset
  catalogue, `INFOPLIST_KEY_UILaunchScreen_UIColorName` in the pbxproj)
  so the first frame and the fade match. The tour's step 24 photographs
  it frozen at 62%. **The painting is the game's own key art since
  2026-09-12 (night):** `launch_key_art.jpg`, one Gemini image the owner
  authorised ("Do it"), the five pantheons' gods on a summit over a sea
  of cloud at dawn, described and not named, its lower half dark for the
  name (`LaunchProgress.keyArt`; the banners take turns only in a bundle
  without it); the painter lettered the eagle standard's plaque and the
  letters were dissolved here rather than re-rolled. The wordmark sits at
  0.58 of the height, on the summit's base under the figures.
- **Every relic is the same stone (2026-09-12, night).** The owner, with
  the collection's six differently shaped ghosts in front of him: "They
  should be all the same shape but have the different symbols." One
  pointy-top hexagon — the ring's own shape — in the set's colour with
  the set's seal, `relic_<set>.png` ×16 and one `relic_rim.png`
  (`tools/relic_art.py --ship` clears the old per-slot files); the slot
  is a number badge on the stone's top-left corner wherever it stands
  alone (`RelicIcon.showsSlot`, on in the inventory grid) and the
  socket's place on the ring, and a filter chip says "Slot 1 · ATK".
  **The set reference** (`RelicSetsSheet`, the end of
  `RelicInventoryView.swift`): every set with its seal, its pieces, its
  effect, and owned/worn counts; opened from "Set effects" on the
  inventory's rail and in its menu, and from the unit sheet's sets row,
  where it also counts that unit's pieces per set. The unit sheet's sets
  row is progress chips — "Fury 2/2" lit, "Fates 1/4" dim — and a worn
  relic in the grid wears its wearer's face (`WearerBadge`); the card
  prints the +15 main stat (`Relic.projectedMainStat(atLevel:)`). Tour
  step 25 photographs the reference. **Cards** (`UnitCard`): the carved
  frame texture was an overlay on the whole card and hid the star row
  under its gold bar ("why can I not see how many stars"); it is drawn
  under the badges now and only on cards of 90 points and up
  (`paintedFrameFrom`), the small cards wear the grade's thin metal
  stroke, and a unit with a leader skill wears a gold crown at the top
  right. **Meshy paints 2D too:** `POST /openapi/v1/text-to-image` exists
  (read off its validation errors, nothing created) and takes `prompt`
  and `ai_model` from nano-banana, nano-banana-pro, nano-banana-2,
  nano-banana-2-lite, gpt-image-2 and two gpt-image-2-5 variants — the
  same Google and OpenAI models, billed in Meshy credits; the price per
  image is unknown until one is made, and the floor rule applies.
- **The campaign pays as it is walked (2026-09-13): sets by road, and
  tributes.** The owner: "I like how the campaign has rewards as you
  complete it, and specific rune types depending on the area. How can we
  do that without copying exactly?" Every chapter yields TWO sets, one
  stat set and one effect set of its realm's myth (`Chapter.relicSets`,
  the `sets:` argument of `generatedChapter`; `yielding` for the
  hand-written Duat 1: Oracle and Nemesis, the Eye and the scales), on
  every stage's `rewards.relicSets` at every tier, printed on the chapter
  map's header as emblem chips — the genre hides which area drops which
  set; this shows it. A stage's star rating (survivors, turns) is saved as
  a high-water mark (`Player.stageStars`, Optional) and drawn as pips
  under the medallions and in the list. Three **tribute chests** stand on
  each chapter's road at each tier (`TributeService` in
  `CampaignService.swift`; `Tribute`, `TributeMilestone`): the road's by
  the third stage (a Pantheon scroll and divinity), the gate's by the boss
  (the realm's essence and a guaranteed relic of the chapter's set), the
  judgment beyond it (every stage at three stars: the finest relic, a
  Legend 6★ on Hell). The table is `TributeService.payout`, mirrored in
  `tools/balance.py` as `TRIBUTES` (`--tributes` prints it: a Normal
  chapter's three chests are worth about 4.6 pantheon summons, Hell's
  9.1); the claim is once per chest (`Player.tributesClaimed`, Optional).
  A chest is `ui_tribute_chest.png` (the reward chest's concept keyed off
  its grey ground) in a lane away from the road, pulsing gold when
  earned; its card (`TributeCard`, the end of `CampaignMapView.swift`)
  opens the victory's 3D chest on Claim and lists what it paid. Tour step
  26 photographs the card; step 13 the road with its chests.
- **The type is Cinzel and Manrope, and nothing is under ten points
  (2026-09-12, evening).** The owner: "the UI looks overwhelming",
  "a nice cleaner font", "make things size correctly". Two OFL faces
  ship in `Pantheon/Resources/Fonts/` (eight static instances cut from
  Google's variable files with fontTools; the licences beside them) and
  are registered at launch by `FontLibrary.registerBundledFonts()`
  (Theme.swift, CoreText — the Info.plist is generated, so no
  `UIAppFonts`): **Cinzel** (Roman inscriptional capitals) for
  `Theme.display`/`title` — the carved roles, in capitals, never under
  12 — and **Manrope** for `body` and `numeric` (Manrope-Bold with
  `monospacedDigit()`, its `tnum`, so stat columns line up without a
  monospaced face). A missing file falls back to the system faces. The
  **type floor** is in the same four functions: `body` ≥ 10, `numeric`
  ≥ 10.5, `title` ≥ 12 after `fontScale`; the density pass had ninety
  call sites at 7–9 (6.3–8.1 on the phone) and the floor lifted them all.
  The console's `[Fonts] registered N of N` line says whether the faces
  arrived. The other screens' bars, wallet strips and sentence panels
  are the next pass (task #50); this one changed the type everywhere and
  the relic screens' shape.
- **Relics are objects, and the rune management is the genre's
  (2026-09-12).** A relic draws as a stone: the SLOT is the silhouette
  (1 crystal, 2 medallion, 3 shield, 4 hexagon, 5 vial, 6 tablet), the
  SET the colour and an **engraved line seal** — one stroke weight for
  all sixteen, classical motifs: an aspis for Aegis, a Doric column for
  Bulwark, a torch for Vigil, a chalice for Ichor, a spiral for Wrath,
  scales for Nemesis, a wheel for Fates, crossed swords for Ruin, a
  ringed pentagon for Wards, an eye, a bolt, waves, links, a mountain,
  wind, a flame (the first cut's filled symbols were "clip art", the
  owner's word) — the QUALITY the rim, the grade the stars under it, the
  level a badge — `RelicIcon` in `RelicInventoryView.swift`, on every
  screen a relic appears. **The stones are PAINTED (2026-09-14):** the owner, "Do the painted
  relics. I want those to look better." `tools/relic_paint.py` put the
  sixteen rendered stones on black as ONE reference sheet and had Gemini
  repaint it as one image (14 cents; one hand across all sixteen, every
  position, colour and seal kept), re-rolled Ichor and Titanfall alone
  from their own renders (the sheet had made them lavender and obsidian;
  14 cents each), keyed each stone off the black ground (flood-filled from
  the border), scaled it to cover the renderer's hexagon and clipped it to
  it, and shipped `relic_<set>.png` ×16 (1.6 MB) under the same names —
  so the tinted `relic_rim.png` still fits and nothing in Swift changed;
  the emblems stay the line seals. Then the owner, of that sheet: "the symbols on
  the relics look basic and shitty, as if they were drawn by a kid" — the
  painter had copied the line seals faithfully. So each set's device was
  DESCRIBED for a sculptor instead (`relic_paint.SYMBOLS`: a gorgon aspis,
  a fluted column before a wall, a wing, a talon clasping a bolt, crossed
  swords over a laurel, an eye in a sunburst, a rune amulet, an
  overflowing chalice, a triskelion, waves with a ferryman's oar, broken
  chain links, a wheel with its thread, a sword-beamed scale, a split
  peak with a fallen crown, a laurelled torch) and repainted on each
  shipped stone as a gold bas-relief (`--single X --symbol-reference`
  then `--paint-symbol`, the stone itself as the reference so the gem
  stays; Chains and Wards re-rolled once when a plaque and a coin
  swallowed the stone). Twenty-one images in all, about $2.95. The chips
  show the painted gem itself (`RelicSetEmblem`, `RelicSet.stoneImageName`,
  the name beside it everywhere; `lineSeal: true` keeps the tinted line
  seal for the loading screen's gold rule): a device cut down to thirteen
  pixels was tried and is a blob. The renders (`python3 tools/relic_art.py
  --sheet x.jpg`, `--only fury,aegis`) are the reference and the fallback:
  `--ship` writes the rim and the emblems only, and `--ship --ship-stones`
  would put the renders back over the paintings. **The
  inventory is the genre's grid** (2026-09-12, evening): the stones at
  38 pt, eight a row, ONE panel at the right for the relic tapped (name,
  quality, main, subs, set, fit, wearer; Open, Equip on…/Change, Lock,
  Sell), a second tap opens the card, the set rail is sixteen emblems
  with a count; the bar is four controls (Filter, Sort, Select, a glyph
  menu for the fit and the optimiser). The text rows it replaced showed
  forty-eight sub stats at once and were called overwhelming. **Quality** (`RelicQuality`: Normal, Magic, Rare,
  Hero, Legend = 0–4 sub stats at the drop) is rolled by grade
  (`RelicQuality.weights`, a 6★ Legend one in eight), floored at Magic on
  Hell tiers and Rare from raids (`StageRewards.qualityFloor`), stored as
  an Optional (`Relic.quality`; `resolvedQuality` reads an old relic's off
  its subs and level), and colours the rim and the name everywhere.
  **Whetstones and gems** (`RelicStone`: three tiers, one kind of each,
  never per set) hone a sub stat (`Relic.honed`, a bonus kept apart from
  the roll, the better kept on a re-hone) or replace one (`Relic.gemmed`,
  one per relic); they drop from the raids, Hell bosses, Labyrinth B7+
  and the Tower's milestones (`StageRewards.stoneChances`,
  `Grant.stones`), live in `Player.relicStones`, and are spent on the
  relic card's Hone & gem sheet (`RelicStoneSheet`). The inventory has a
  **filter sheet** (`RelicFilter`: slot, grade, quality, main, subs —
  every ticked sub must be on the relic — set, worn, locked), eight
  sorts, "All shown" while selecting; a relic's card has **Equip on…**
  (`RelicWearerPicker`, the roster with the delta) and **Power up to +N**
  (`GameStore.powerUpRelic(_:to:)`); a relic on the chest's shelf opens
  the **drop card** (`RelicDropCard`: Sell, Keep, Lock and keep); the unit
  sheet has Unequip all. Removal is free on purpose. Every number is
  mirrored in `balance.py` (`QUALITY_WEIGHTS`, `STONE_RANGES`,
  `STONE_COSTS`; `--relics` prints the odds, the stone spans and the bill
  to each milestone).
- **The detail pass (2026-09-09).** The playtest called the characters too
  cartoony and the attacks ugly (a leg thrown out). Four things changed, all
  in one place each: the Meshy texture prompt in `tools/batch/wave_launch.sh`
  asks for painted detail (engraved metal, woven cloth, hair in strands)
  instead of "cel-shaded with crisp baked highlights"; `tools/mesh.py` ships
  9,000 triangles at 2048 px (was 5,000 at 1024; the LOD is 3,500 at 1024)
  — **and since 2026-09-17 a hero family ships 16,000 with a 6,000 LOD at
  2048 (`--tris 16000 --lod 6000 --lod-texture 2048 --no-clips`; Zeus
  first, the owner: "not detailed enough"), because a BATTLE draws the LOD
  and nothing else and the fight was showing a sixteenth of the geometry
  Meshy delivers (~56k); `ModelLibrary.predecodeTextures` decodes every
  texture on the parsing thread so a 2048 battle texture no longer hitches
  the main thread (the reason the LOD's texture was 1024). Meshy deletes a
  finished task within about a week, and the animated exports carry the
  base colour alone, so the metallic-roughness maps are gone for every
  family made so far: the surface modifier reads the METAL off the
  painting instead (bright, saturated, within a few degrees of gold's hue
  → metalness 0.85, roughness 0.28) and the lighting modifier's specular
  follows roughness and metalness (70-power and bright on gold, 16-power
  and faint on linen; the band opened to 0.12–0.90). The next wave's
  `download` must save the image or refine stage's own `model.glb` the day
  it finishes — the three maps are inside it (`Docs/PLAN.md`, *Graphics*).**
  `ModelLibrary`'s lighting ramp was `smoothstep(0.16, 0.86)` over
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
  (2026-09-10). **A full-screen painting is `PaintingFill`
  (Components.swift), never a fill image under a flexible frame** —
  `Color.clear` at exactly the space it is given, with the painting as an
  overlay, which is never measured. As a `.background` a fill image cannot
  grow its host, but it still DRAWS at its own size, centred on it: behind
  the dungeon levels it spilled over the strip and painted the title, the
  wallet and the back button out of existence on that one screen for a
  week (the owner, 2026-09-17: "There's no back button on this"; the CI
  frames showed a strip-less screen all week and nobody read it). A fixed
  `.frame(width:height:)` off a GeometryReader is also safe, which is what
  the island and the Hall of Ka do. The same size overflow, in a band:
  the Titan card's band had the painting under `.frame(maxWidth: .infinity,
  maxHeight: .infinity)` inside `.frame(height: 104)`, the square painting's
  fill size grew the ZStack to its own height, and the label aligned to the
  stack's bottom was carried below the clip — a black slab with no name on
  it for two runs of frames (2026-09-16). And a `.shadow` on a stack is
  cast by EVERY child, so a glow meant for a rim falls inward over
  whatever the stack holds: the chosen tab's socket photographed khaki
  for six runs until `.compositingGroup()` went before its halo
  (2026-09-23). A fill painting clipped to a band still takes the taps
  of everything its overhang covers — the tab bar's marble, 240 points
  over the foot of every tab screen, was caught by a reviewer before it
  shipped — so it carries `.allowsHitTesting(false)` like `PaintingFill`.
  And a camera node looks along its own −Z: orient it with
  `SCNNode.look(at:)`, never `atan2(dx, dz)` (that was half a turn off and
  the orbit shot showed the empty side of the stage). **And a clip
  added to a figure BEFORE the figure is in a scene that is already
  rendering never starts (2026-09-17):** the Hall of Ka opened from the
  island picks its unit a beat after it appears, so its figure went into
  the live scene with the idle already attached, and Zeus stood on the
  dais in his bind pose through three runs of frames (the owner: "Why
  are the characters stuck in this position"), while the Awaken step,
  which names its unit up front and so builds its figure before the
  view's first frame, animated on the same code. `SCNNode.startLoop`
  (ModelLibrary.swift) is the one way a stage starts an idle: the figure
  into the scene first, then an `SCNAnimationPlayer` told to `play()`;
  the stage views set `isPlaying` as well, and `TrainingView.target`
  falls back to the rail's first unit so the hall never opens empty. A
  unit picked from a rail afterwards always goes into a live scene, so
  the order matters on every stage. Found on the way, and kept:
  **SceneKit's importer is driven from ONE thread at a time** — the
  warm pass and the main thread parsed at once, the USD library logged
  "TBB Global TLS count is not == 1, instead it is: 2" and 'zeus' was
  parsed twice; every `SCNScene(url:)` and `SCNSceneSource` in the app
  goes through `ModelLibrary.parseScene` / `withImporter` (one lock held
  around the parse only, never the caches) and `loadOrCached` parses a
  mesh ONCE when two threads ask at the same moment. Never call the
  importer directly. Serialising the parses alone did NOT start the
  idle (run 170); the attach order did. And **a node with a
  one-shot particle system goes only after the system has finished**:
  SceneKit's particle manager keeps a finished instance and looks its
  node up when it dies, and a host removed while its motes still lived
  crashed the fight twice on 2026-09-15 — hidden-element assertions when
  the removal was an action, a SIGSEGV in
  `SCNNodeRemoveDeadParticleInstance` when it was the main thread (the
  crash report the CI job now publishes read it). Every `spawn` host waits
  3 s over sub-second bursts; the ultimate's charge waits 1.5 wind-ups + 1
  s. And nothing swaps a texture or touches the scene graph inside an
  `SCNAction` block — hygiene, not the cause. **Run 239 (2026-09-24)
  crashed the same way on the render queue** (an element the pipeline
  should have dropped, drawn from freed memory, a tenth of a second after
  the "Hidden nodes should have been removed" assertion) as Set's
  ultimate's swing trail came off the stage: `UnitNode.swingTrail` set a
  geometry sixty times a second from a `customAction`. It is a main-thread
  `Timer` now (it counts only while the scene runs, so a hit-stop holds
  it), and every effect host leaves through `VFXLibrary.retire` /
  `dismiss` — scene time first, then on the main thread its particle
  systems taken off and hidden, then removed half a second later — with
  a `[VFX] … still carried N particle system(s)` line if one was live and
  stamped `[VFX] HH:mm:ss` retire lines under `-tour` to name the node on
  a repeat. A projectile is dismissed the same way on arrival.
- **The random crashes were memory (2026-09-24; the owner: "when I do many
  summons, or sometimes when I play chapters, or randomly the app
  crashes").** A foreground app over its memory limit is killed with no
  report, and nothing let go: `ModelLibrary` kept every family it had ever
  parsed with its 2048 textures decoded (about 32 MB a family) and
  `BundleArt` every full-size painting. Now the model cache is an LRU —
  14 files or 480 MB of decoded pixels, halved within 512 MB of the
  process's limit, an entry any live clone came from never dropped (a
  weak list of clones), the last 20 s protected — textures shared between
  a base file and its `_lod` decoded once (by the archive member's CRC),
  `BundleArt` an `NSCache` with `uncachedImage` for the battle's backdrop,
  and `MemoryRelief` (Core/Models) the one place a cache hears pressure:
  `observe` for UIKit's warning and the kernel's CRITICAL level (a full
  purge; the clip sets stay, a figure fetches its clip on every play),
  `observeEarly` for the kernel's first warning (a trim to the halved
  limits). `warm(forms:)` warms the form a unit HAS; a screen about to
  change the form (the Hall of Ka's Awaken, `warmAwakening`) warms the
  other one itself. **Seeing it:** `CrashReporter` (MetricKit crash, hang
  and exit diagnostics saved and replayed into Diagnostics every launch,
  the crashes before the daily metrics) and `MemoryProbe`
  (`phys_footprint`, `os_proc_available_memory`, a peak, a clean-exit
  flag so the next launch says the last one died; in the simulator the
  kernel's pressure is the HOST's and is only noted) — `[Mem]` and
  `[Crash]` lines. CI step 53 `stress` relaunches with `-tour-stress
  summon` (thirty singles, three ten-pulls through the reveal) and
  `-tour-stress battle` (six auto-repeat runs), a footprint after each;
  `shots/memory.txt` is every launch's curve and `ciframes.py` prints it
  as MEMORY, a death as STRESS: THE APP DIED and a wait that ran out as
  TIMED OUT.
  **And a 3D stage lets go of its scene when its view leaves** (run 242:
  76 → 1,439 MB over thirty summons, about 30 MB a reveal kept): an
  `SCNView` in a `UIViewRepresentable` with no `dismantleUIView` keeps its
  scene, its figure's clone and its uploaded textures as long as SwiftUI
  keeps the old view, and a live clone pins its family in the model cache.
  Every stage — `SummonStageView`, `AltarStageView`, `CollectionStageView`,
  `RewardChestView`, `BattleSceneView` — has `static func dismantleUIView`:
  the renderer stopped first, particle hosts through `VFXLibrary.dismiss`,
  actions and animations off, and `SummonStageView.teardownSettle` later the
  children, the scene and the links (the battle's view drops only its own
  links: the model owns the controller's scene). A new stage gets the same;
  `[Mem] reveal stage released` and `[Mem] battle stage released` say in the
  console that one really went (PLAN.md, *The random crashes, part two*).
  Every `[Mem]` line also counts the live 3D views (`views battle N, island
  N, reveal N`, from `StageRenderGovernor`, the view's own associated
  object) and the Metal device's allocations (`gpu N MB`): runs 243–244 had
  one live view per stage throughout and the summon curve unchanged, so the
  ~16 MB a reveal still unaccounted for is neither the views, the graphs nor
  the card images (`BundleArt` reads a JPEG from its file, never through
  `UIImage(named:)`'s system cache). And a fight opens under a black veil
  (`BattleView.stageShown`) until the renderer has drawn three frames of the
  built stage (`BattleSceneController.onStageShown`), five seconds at most:
  run 243's first battle frame was white under the HUD.
- **A card's wear scales with the card (2026-09-14).** The owner, of the
  popup's 50-point enemy cards: "Do the elemental symbols need to be so
  big? We can't see the picture." `UnitCard.wear` is `size / 80` clamped
  to 0.6…1 and scales the element badge (`ElementBadge.scale`), the
  awakened sun, the lock, the crown, the star row and their paddings, so
  a small card is mostly portrait. The next areas of the density pass
  (task #50), in the owner's order once he picks them: the battle HUD,
  the menu bars and wallet strips, the popups' and panels' spacing.
- **Rewards are tiles, and the win ends in the genre's reward box
  (2026-09-14, late).** The owner, with Summoners War's reward popup beside
  our victory frame: "Why does ours look so basic and ugly?" `RewardTile`
  (Components.swift) is the one reward tile — a stone-plate socket in a
  bronze bevel, the item at three quarters of it, the count printed bold
  with an edge on the corner (`OutlinedText`), a graded thing's colour on
  the rim and its stars under it, the name below, a relic as its own stone;
  `init(grant:)` for anything the bazaar or the quests pay. `ItemIcon`
  draws `item_<key>.png` when it is in the bundle and the glyph in its tint
  until then (`ItemArt`: keys, glyphs, tints; the keys are the game's ids —
  an essence's, a stone's, `scroll_<type>`, `awakening_cache_<element>` —
  or one word: `drachma`, `divinity`, `energy`, `unit_exp`, `laurels`,
  `rank_points`, `relic_cache`). `SpoilsPanel` (BattleView.swift) is the
  win's third act: the marble panel with a ribbon, the chest and the stars
  as its header, one or two rows of tiles popping in, Continue inside. The
  tile also draws the tribute card's grants, the bazaar's offers and the
  login gift's days; the stage popup's drop rows and `BarWallet` carry
  `ItemIcon`. **The paintings are NOT made yet:** `tools/item_icons.py`
  paints forty-two icons as five 3×3 sheets on black (about $0.70), keys
  them off the ground and ships them; it runs on the owner's word only.
- **The essence ladder (2026-09-17).** `UnitDatabase.awakeningCost(element:
  naturalStars:)` is the ONE recipe every `Awakening` reads (5★ Mid 15 +
  High 10 + Magic Mid 10 + Magic High 5; 4★ 10/5/8/3; 3★ Low 10 + Mid 5 +
  Magic Low 5 + Magic Mid 5), `DungeonDatabase.hallEssenceChances(element:
  floor:)` pays it (B1–2 Low sure + Mid 40–50%, B3–5 Mid sure + High
  25–50%), the awakening caches grant the 5★ bill, and `balance.py
  --essences` asserts shipped == PLAN.md's table. Change a number in both
  files and grep `ProgressionTests`/`DungeonTests`.
- **The Regalia (2026-09-17): one named item per family**, levelled I–V by
  duplicates fed in the Hall of Ka once the skills are capped (`GameStore.
  levelUp` → `RegaliaService.feed`; it banks while locked), unlocked by the
  awakening or at 6★ for a family without one. `Regalia.swift` (eight
  templates by kit, `RegaliaTemplate.magnitudes`), `RegaliaService`,
  `Unit.regaliaLevel` (Optional), the names and blurbs beside
  `elementalSkillNames`, hooks in `BattleEngine` and `DamageCalculator`
  for the player's units and the arena defender only, the plate on the
  unit sheet and `RegaliaSheet` (tour step 46). `balance.py --regalia`
  measures every template (Heavy Hand V 15.3%, under the 16% rank-II cap);
  change a magnitude in `RegaliaTemplate.magnitudes`, `REGALIA` and
  `RegaliaTests` together.
- **Events (2026-09-17; `Docs/EVENTS.md`).** `EventCalendar` derives the
  week from the date: Mon drachma ×2, Tue XP ×2, Wed campaign energy ×0.5
  (rounded up), Thu laurels ×2, Fri–Sun a Hall's essence ×2 or, every
  fourth week, a Labyrinth's relic roll twice; every fourth week the
  Festival's gift a day (`Player.eventGiftsClaimed`, Optional). The hooks
  are one line each (`CampaignService.settle` → `boosts(for:at:)`, the
  energy charges, `ArenaService.applyResult`), every energy label prints
  `EventCalendar.energyCost(for:)`, and `applyRewards` never reads a
  clock, so a test's relic count holds on any weekday. `EventsView` is
  the calendar beside the missions scroll and on More; `balance.py
  --events`; tour step 45.
- **Allies — the social layer (2026-09-17; `Docs/SOCIAL.md`; it was called
  "Summoners" for a day — the owner: "we shouldnt use that name" — and
  the player is a DEMIGOD everywhere the game names him, never a
  summoner; the tour step is `allies`).**
  `SocialBackend` (protocol), `CloudKitSocialBackend` (the public database
  of `iCloud.com.pantheon.game`, used only when the binary is entitled AND
  the device has an account — `isEntitled` reads the code-signature
  entitlements first, because an unentitled `CKContainer` is an uncatchable
  exception and CI signs nothing), `LocalSocialBackend` (the seeded offline
  world every CI frame shows), `SocialService` (`GameStore.social`),
  `SocialView` from the island header and More: friends, mail with grants
  (`GameStore.receive`), guilds with a board and an async war fought as
  `BattleContext.guildWar` (settled by `finishWarAttack`, never through
  `.arena`), two leaderboards. `Pantheon/Pantheon.entitlements` is the
  app target's `CODE_SIGN_ENTITLEMENTS` (pbxproj and project.yml). The
  owner's Xcode/Dashboard steps are in SOCIAL.md. Tour step 47.
- **The feature day (2026-09-23, evening; PLAN.md *The feature day*).**
  Four features built by four agents on their own files and wired by one
  hand. **The Codex** (`Docs/CODEX.md`: `CodexService`, `CodexView`, the
  Collection strip's book button and More's door, `Player.codexClaims`):
  every family × five elements plus the awakened faces, each new page
  paying divinity by grade — and any new way of getting a unit must
  insert into `player.codex`, which the book reads as "ever owned".
  **The Draft Arena** (`Docs/DRAFT.md`: `DraftService`, `DraftView`,
  `BattleContext.draft`, `Player.draft`): the World Arena's 1-2-2-2-2-1
  draft with a ban each against AI demigods, Elo from 1,000, a week that
  never out-pays the arena (`DraftTests`). **Hidden Shrines**
  (`Docs/SHRINES.md`: `ShrineService`, the Labyrinth's Shrines wing,
  `Player.shrines`, `Player.shrinePieces`): a Labyrinth or Hall win may
  open an hour-long shrine of one fire, water or wind form, never Light or
  Dark, paying pieces spent 20 / 40 / 100 on a 3★ / 4★ / 5★;
  `balance.py --shrines` asserts a 5★ by pieces is slower than by mileage.
  **Settings and App Store readiness** (`Docs/SETTINGS.md`,
  `Docs/BACKEND.md` §7): local reminders (`NotificationService`, asked
  only from a toggle or the first empty energy), `GraphicsSettings`
  (frame rate, effects, shadows; the defaults are today's look), Reduce
  Motion, in-app account deletion (`AccountDeletion`, the SQL
  `delete_my_account()`, the `apple-revoke` Edge Function for Sign in
  with Apple — the owner's setup steps are BACKEND.md §7),
  `PrivacyInfo.xcprivacy`, `ITSAppUsesNonExemptEncryption = NO`,
  `LegalLinks.plist`. Tour steps 49 `codex`, 50 `draft`, 51 `shrines`;
  step 9 relaunches with `-tour-more notifications|graphics|delete`.
  swiftcheck accepts the labels of an init declared in an EXTENSION (Swift
  keeps the memberwise one beside it) and still fails a misspelt label.
  **The Treasury** (`Docs/STORE.md`, PLAN.md *The feature day*): real
  money through StoreKit 2 — six divinity packs doubled on first
  purchase, a once-per-save starter, the Blessing (a NON-renewing 30
  days) — with `PurchaseService.swift` the one file that imports
  StoreKit, `TreasuryService` the payout, and the order verify → grant
  and record (`Player.treasury`) → synchronous save → `finish()`. It is
  the bazaar's first stall; tour step 52 `treasury`; `balance.py
  --store` checks the catalog against `Pantheon.storekit`; CI has no
  StoreKit. Turn off the Testing stall
  (`ShopService.testingPacksEnabled`) before any review build.
  **Anonymous play data** (`Docs/ANALYTICS.md`): `AnalyticsService`
  batches listed events to the Supabase `analytics_events` table on the
  anon key with a random install number, never under `-tour` or the
  tests; the owner reads the `analytics.*` views; the Support board's
  switch turns it off and forgets the number. A new kind of play worth
  counting gets an event in `Analytics.swift` and a column in a view,
  never a free-text field.
- **The paid programme of 2026-09-17** (PLAN.md, *The paid programme*):
  the five gods are meshy-7 now (`_m7`, judged on boards, better in every
  one), their bespoke motions re-applied, Zeus's ultimate remade (blow at
  0.78); a **walk clip** (preset 30, `AnimationClip.walk`, in
  `BATTLE_CLIPS`) and **the island wander** (`IslandSceneView.wander`: a
  figure with a walk clip strolls near its stand when it stirs, placed by
  a custom action off the latest layout; the others hop) — only families
  rigged from today walk, the rigs of 2026-09-09 are gone from Meshy;
  Neptune and the Terracotta Soldier in their own meshes (a short sword
  flat on the thigh rigs first time); six Labyrinth props on the sets
  (`vaultSet`, `lairSet`, `necropolisSet`); ten awakened meshes (Mars and
  Hera painted and waiting on credits, Loki's concept refused twice); 48
  item icons; batch 4's awakened cards; nineteen backdrops repainted at 4K
  and shipped at 2048 (`tools/batch/backdrops_4k.sh`; the raws in
  `Art/Backdrops/`). `genart.py --resolution` reaches the request now —
  the call site had dropped it. **A Meshy MESH task expires within about a week and a MOTION task in about three days (2026-09-18: every motion of the 15th was 404 on the 18th and the first re-application shipped presets in silence)**: the bespoke clips live in `Art/Motions/<family>_<clip>.motion.npz` and `tools/retarget.py` puts them on any new rig for nothing (`reapply_motions.sh`), a world-space delta per joint judged on its board; `tools/batch/build_asset.sh` ships at the hero budgets.
- **The serious look (2026-09-17, evening; the owner: "I honestly don't
  like the big hands and cartoony look. I want it a little more serious
  feeling and look").** Every concept was painted "five heads tall, big
  hands and feet", so the meshes were. The free half is in the pipeline:
  `character.reproportion` (`mesh.py --proportions serious`,
  `tools/batch/proportions.sh` over every rigged family) scales the head,
  hands and feet down at their joints, lengthens the thighs and shins,
  BAKES it into the mesh and rebuilds the skeleton with no scale in it,
  the clip carriers re-shipped through the same pass (their translation
  channels follow); the ramp is near-Lambert (0.04–0.96) with a quieter
  rim (3.6 / 0.30). The real answer is a new concept style — from scratch,
  never a `--ref` edit of a chibi concept, which keeps its body — and a
  remake at 59 credits a family (PLAN.md, *The serious look*: about
  5,700 for the roster); `zeus_serious` is the one paid test, judged on a
  board of the three Zeuses. A mesh made in the new style must NOT go
  through the pass. **The pass is `serious2` since 2026-09-18** (PLAN.md,
  *The stronger pass*): `reproportion` has a `{"width": W}` operation
  beside `length`, and the recipe narrows the hips, spine and limbs a
  tenth, lengthens the thighs 28% and the shins 22%, the head at 0.80 —
  the first recipe left the chibi WIDTH and the owner still saw cartoons;
  `tools/batch/proportions.sh` (`PROPORTIONS_RECIPE`, markers in
  `/tmp/proportions2`, the Ares family `--grade gold` on the way) re-ships
  every family and derives its standing idle. A remake is 68 credits a
  family now (the walk clip and the bespoke motions), about 6,400 for
  the roster. `mesh.py`'s clip finder accepts only `<name>_<clip>`
  for a clip the game knows (`CLIP_NAMES`): `ra_awakened`'s files beside
  `ra` were read as Ra's clips and failed the bind check for three families.
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
  decimation (fixed; a battle always draws the LOD now, 3,500 triangles at
  1024 for a common family and 6,000 at 2048 for a hero since 2026-09-17), and the units stood in the bind pose, which the loader
  now treats by gathering per-joint tracks into one animation.
- **The app opens on the island, and the island is Summoners War's Isle
  (2026-09-17; the owner: "I want it upgraded to be more like summoners
  war. The home island I mean").** `IslandView` is a diorama on the
  painting: a pinch zooms 1.0–1.6× within the painting's pixels and a drag
  pans, the painting always covering the screen (`IslandCamera`: zoom and
  pan, clamped; a double tap on the sand resets; every anchor, footprint,
  stand and slot is a point of the painting, so the whole island moves as
  one); the BUILDINGS are the buttons (`Landmark.footprint`, measured off
  the painting — the tap target, a pulsing light on the sand under one
  with something to do, a bobbing bubble over it with the glyph and count
  of what it wants (`IslandBubble`), a small name chip under it, a pop on
  the press before the screen opens); the figures react to a tap
  (`IslandReaction`: a hop, the victory clip where the family shipped one
  and the basic swing where not, "Zeus · Lv.12" over the head for 1.6 s)
  and one stirs by itself every 9–15 s; the daily offering is a gold
  bubble over the pool that claims through `GameStore.buy` of the same
  item the bazaar sells, with the grants as `RewardTile`s in a toast; the
  header is the player's card (the campaign leader's face in a ring, name,
  level, experience) with the missions scroll, a chisel and the wallet;
  and the living layer (`IslandSceneView`, orthographic, one point per
  unit, depth by height on the painting) draws the team, the pool's sparks,
  the obelisk's flame, sun glitter on the sea, fireflies in the scrub after
  20:00 and the **decorations**: eleven props already in the bundle as a
  catalogue priced in drachma (`IslandDatabase.decorations`, a brazier at
  4,000 to the colossus at 60,000, level-gated), bought once for good and
  stood in one of six sand patches (`decorSlots`) or moved for nothing
  (`IslandDecorService`; `Player.decorationsOwned`, `Player.islandDecor`,
  both Optional; `GameStore.buyDecoration/placeDecoration/clearDecoration`;
  the sheet is `IslandDecorView` from the chisel; the thumbnails are
  `decor_<id>.png` from `tools/decor_thumbs.py`), a brazier burning with a
  flame, a light and a glow on the sand. The tour seeds a brazier and the
  sphinx. `UnitNode.restartIdle()` restarts a figure rebuilt into the live
  scene. The painting was generated at 9:16 and its sea extended to 3:4,
  because a phone shows only the central 62% of the painting's width; the
  anchors were measured off it (`Docs/ART_2D.md` §6). `tools/island.py` is
  the stand-in painter, kept for reference. `Docs/PLAN.md` *The home island
  as Summoners War's* has the three options (this, a wider painting for
  under a dollar on the owner's word, a 3D island when the credits exist).
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
  for parallax. A missing prop gets a built stand-in. **The arena is
  dressed (2026-09-15, the free half of "I want THAT level of detail"):**
  every floor and rock tile ships a normal map derived from its own
  painting (`tools/floor_relief.py` → `<tile>_n.png`, 512 px, PNG; the
  grout low, the stone high; `StageBuilder.applyRelief`) so the 36° key
  light bevels every grout line, marble is polished (0.52) and moss is
  not (`floorRoughness`); the slab's tint is clouds of shade drawn at
  runtime (`mottle`, 1.6 repeats across 44 m) so fourteen identical tiles
  stop reading as wallpaper; the arena has SIDE WALLS (`sideWalls`, a
  0.9 m balustrade with coping and posts at x ±9.8 from the far parapet
  to z +9, projected in the camera port first: the far-side one runs
  diagonally down the upper left of the home frame) and a floor INLAY
  (`arenaInlay`, 6.6 m round at (0.3, 0): an outer band, ticks, rings and
  an eight-point star drawn at runtime and MULTIPLIED over the tiles as
  grooves — geometry only, no device); the set and the painting are lit
  as one place — `PaintingPalette` reads the painting's sky, horizon and
  ground off a 32 × 32 reduction and the fog, the sky, the fill and the
  ambient take theirs from it, mixed with the hand-picked `fogHex` so a
  night painting keeps its intent; the camera wears one grade per place
  (`StageBuilder.grade(for:)`: saturation, contrast, exposure, vignette,
  plus what the painting itself asks for — see the shoulder below);
  and each realm has weather (`StageBuilder.weather(for:)` →
  `VFXLibrary.weather`: embers in Egypt and the arenas, leaves in the
  marsh and under Yggdrasil, snow in the fjord and Jötunheim, petals in
  the Peach Garden, wisps in the deeps, motes on Olympus). The half that
  COSTS — Gemini floor tiles with a carved arena pattern (about ten at
  14 cents) and Meshy set pieces (30 credits each over a floor of 2,000
  with 2,133 in hand) — waits on the owner's word (`Docs/PLAN.md`). **A Meshy prop is 30
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
- **The light has a shoulder (2026-09-15).** The owner, of four battle
  frames: "Lighting and contrast feels too bright doesnt it?" It was not
  global — `tools/framelight.py` measured the Duat and the arena at 0.2%
  of their pixels blown and Olympus's near floor at 25.2%, the fjord's
  sky at 16.5%: the PALE sets. `SCNCamera.whitePoint` had sat at
  SceneKit's default 1.0 for the life of the project, which clips every
  surface at or over 1.0 flat to paper; it is **1.85** now, so the tone
  curve keeps rolling and lit marble keeps its grain. With it: each set's
  exposure takes the grade's hand-picked number PLUS
  `PaintingPalette.exposureCompensation`, which reads the backdrop's own
  mean luminance off the same 32x32 reduction that colours the fog and
  pulls a pale painting down as far as half a stop (a night is lifted a
  quarter), so a set is lit to MATCH its painting rather than on top of
  it; the key is 1,150 (was 1,400), the fill 400, the ambient 240, the
  image-based light 1.15 (was 1.6); bloom is 0.22 over 0.975, because
  bloom on a clipped floor is what spreads the white onto the figures
  standing on it; and marble's roughness went 0.52 to 0.62, since a
  polished floor threw the key straight back as one sheet. Check a run's
  frames with `framelight.py` before believing a lighting change — it
  prints each band's mean and clipped share AND the most blown 64 x 64
  patch, because a band's mean misses a white blob over a fifth of the
  screen.
- **An effect may not relight the set (2026-09-15, later).** The owner sent
  back the one frame still bleached: `VFXLibrary.flash`, the point light
  every one of the twenty-four impacts spawns, was a flat 4,000 reaching
  FOUR TIMES its radius — three and a half times the key light, nine
  metres wide for a basic attack and twenty-eight through `skyFlash`, so
  every hit relit the arena instead of the victim, and no camera shoulder
  can save a surface genuinely lit to four times white. It reaches
  `radius × 1.5` now, falls off from a third of the way out, and scales
  from 1,320 to a cap of 2,400; `skyFlash` is a quarter strength and is
  spent on a heavy or an ultimate only; and the lightning sheet is tinted
  off pure white so an additive layer cannot climb past the bloom
  threshold alone. Brightness belongs to the SPRITE, which covers only its
  own pixels; a light in an effect reaches about as far as the thing it is
  lighting. The boss's warm spot was the same mistake one screen further
  on — 3,000 through a 75° cone reaching 34 m, so a boss walking on lit
  the whole 44 m slab and the Labyrinth's third wave photographed as a
  pale wash with only the health bars in it; it is 2,400 through a 46°
  cone, gone by 14 m, which is the boss and nothing else.
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
  used to. **Since 2026-09-15 the zoom is told where a leaping caster will
  land** (`perform(_:on:target:focus:)`, `UnitNode.dashDestination`): the
  push-in on Sekhmet's Seven Arrows was aimed at her mark and held on the
  empty floor while she fought four metres away (the owner: "the camera
  zooms really close to nothing"). **The basic attack is armed the moment
  a player's turn opens** (`BattleViewModel.armBasicAttack`, aimed at the
  obvious target), so one tap on an enemy attacks; skills 2 and 3 arm
  first and commit on a second tap, and a tap on the armed basic's square
  commits it on the marked target (the owner: "attacks should default to
  skill 1, so I don't ALWAYS have to click skill 1 if 2 and 3 are on
  cooldown"). The HUD's top centre WAS the **attack gauge** (`BattleView.turnGauge`, deleted 2026-09-15:
  portraits on one track by `attackBar`, ready unit in gold); tapping a
  skill shows its name and description above the skill row and holding one
  opens a card. The painted chrome is drawn at 1/1.4 (`Chrome.shrink`),
  fonts at 0.9 (`Theme.fontScale`), cards 76pt: the playtest's density
  pass. **A skill square carries its ART and nothing else since
  2026-09-15** (the owner: "I hate having the NUMBER show on top of the
  skill. We dont need that. Lets do it like summoners war and only show
  the damage when the character attacks"): the painted icon fills the
  60-pt square with the caster's element as the light behind it, the
  cooldown is a number over a veil, the target badge is drawn only when
  the skill is not a plain single-enemy one, and the estimate and the
  name are on the held card. `SkillArt` (Components.swift) maps every
  skill in the game to one of TWENTY-SEVEN painted icons by what it does
  — its named `vfx` first, then its effect (revive, heal, cleanse,
  strip, shield, buff, a bar drag, a stun, a defence break, a burn, a
  drain, a brand), then its shape (all enemies, three hits, a heavy
  single blow, thrown or swung), then its element's mark — and
  `SkillIcon` draws it for the battle squares and the unit sheet alike;
  `tools/skill_icons.py --paint --ship` paints the three 3x3 sheets
  through Meshy (6 credits each) and keys them off the black by a flood
  fill from the cell's border. A painted icon per skill would be
  thousands of images. The CI tour is forty-nine screens (steps 0–48): the sign-in screen (48,
  `sign_in`), the reveal twice (5, `reveal`: a fire Sekhmet, then relaunched
  with `-tour-reveal awakened` for an awakened light Ares on the beam — the
  frame that judges the awakened look every run), the Allies screen (47,
  `allies`, four frames, one per tab by `-tour-social-tab`), the Regalia
  sheet (46), the events calendar on a Festival Monday (45), the island's decoration
  sheet (44, `island_decor`; step 0 is photographed twice, at rest and
  relaunched with `-tour-island-zoom 1.5` onto the circle), the Hall of Ka's
  Awaken panel (43, `awaken`: the seed's strongest unawakened unit with
  the bill met, since the training step opens on Power up), an arena battle
  (step 8) as well as the campaign one, the Labyrinth, a dungeon's
  levels, the relic picker, a Labyrinth run on auto (`dungeon_battle`,
  four frames, so the waves are seen walking on), the power-up screen,
  the victory's chest in three frames, the collection's Stage layout
  (21), the relic drop card (22), the relic filter sheet (23) and the
  loading screen (24), the relic set reference (25), a tribute chest's card (26), a stage's popup over the chapter map (27), every chapter's painted map (28, twelve frames a–l) and a fight on six other realms' sets (29, `realm_battle`, relaunched with `-tour-environment <rawValue>`: Olympus, the marsh, the fjord, Jötunheim, Rome, the Peach Garden — the other battle steps only ever show Egypt).
- **The premium feel's battle half (2026-09-24; `Docs/FEEL.md` W1.1–W1.3,
  W1.6, W1.7, W1.9, L1, each with its *As built*).** The speed steps ×1 → ×2
  → ×3 (`BattleSpeed`, remembered in `UserDefaults` under `battleSpeed`,
  never under `-tour`); ×3 SCALES the juice (a third of each freeze over a 20
  ms floor, half the shake, haptics only for a crit, a kill or an ultimate)
  and Skip (`flush`) is the one mode with no feedback — `Juice.skipThreshold`
  is gone. The hit-stop's tremble (`Tremor`) and the final blow's slow motion
  (`timeScale`, multiplied into the speed as `pace`) tick on `FrameTicker`s,
  120-Hz main-run-loop `Timer`s through a `WeakTickTarget` (the display
  link's stand-in: swiftcheck's `--types` list has no `CADisplayLink`) that
  stop themselves once their owner has gone; `Juice.stopTremor` (every impact
  and release, and `Juice.release` in `flush`, `halt` and `build`) and
  `endSlowMotion` (its own end, a new one, `flush`, `halt`, `build`,
  `celebrate`, `drainColour`) and the controller's deinit invalidate them.
  `CameraDirector` reads the realm's grade at init; `impactFrame()` hands
  back the punch and the restore as two closures, which
  `BattleSceneController.renderUpdate` (the coordinator's `updateAtTime`)
  runs on the RENDER thread two drawn frames apart (`impactFrames`, counted
  in `frameDrawn`) — a restore queued on main waited out a stall and run
  245's arena frame came out grey, and a main-thread punch waits in its
  transaction and can land AFTER a render-thread restore; never over a
  drain or under Reduce Motion — and `stopMoves()` (shot, shake, fov)
  replaced `removeAllActions` so a return home never cancels `drainColour`'s
  `grade` action. One impact frame per cast, the final blow's when the cast
  has one. Lights: figures on category 2 (`UnitNode.markFigure`; a category
  is not inherited, so mark anything hung on a unit again), the set on 4
  (`StageBuilder.separateBattleSet`, a prop's materials COPIED before they
  are tuned), figure lights 2 | 1, set lights 4; `-tour-layers off` builds
  the old shared rig. The scene's contract with `BattleView`:
  `celebrate(experience:)` once on the last run's win (keyed by COMBATANT id:
  the survivors turn to the lens and pose at ×1, `frameTeam`, gold EXP bars,
  LEVEL UP), `drainColour(duration:)` on a loss or a draw, `triumphDuration`
  2.4 s; `forfeit()` calls `halt()`. The level-up beat (`BattleResultView`'s
  `.levelUp`, `PlayerLevelUp`) comes between the reckoning and the chest, one
  per auto-repeat, and `GameStore.pendingLevelCelebration` (never saved;
  `takeLevelCelebration()`) bursts the island's level ring once. Tour frames:
  `6-battle-layers-off`; `-tour-victory field` (a real Duat 1-1 win at ×3,
  the pose slowed to `tourPosePace` 0.25 because a screenshot lands two to
  three seconds late) gives `20-victory-0`, `-triumph` and `-levelup`, and
  `-tour-victory defeat` gives `20-victory-defeat`; `-tour-triumph win|loss`
  is a lab nobody photographs. The job's limit is 110 minutes.
- **The premium feel's Wave 2, the battle's half (2026-09-24; `Docs/FEEL.md`
  W2.1, W2.8–W2.11, each with its *As built*).** The numbers are
  `Pantheon/Render/FieldBeats.swift`'s (`UltimateSplash`, `Spotlight`,
  `WaveStamp`, `WalkOn`, `Dissolve`, `BossEntrance`; `FieldBeatsTests`), the
  views `Pantheon/UI/Battle/FieldBeatViews.swift`'s, and the scene tells the
  view through ONE closure, `BattleSceneController.onFieldCue` (`FieldCue`,
  written into `BattleView`'s state through bindings by `receive`). **An
  ultimate owns the screen:** `holdForCutIn` holds the world
  (`Juice.holdWorld`/`releaseWorld`, a token that outranks a freeze) and
  hands the splash's length to the queue as frozen time; the cast's picture
  is drawn by `performCast` (a `CastPlan`) as it lets go, strictly before
  the clip starts, so `contactFraction` stays true — never draw a cast in
  `present` again. The setting is `ultimateSplash` (Always / First / Off,
  always under `-tour`). A splash's card is decoded ahead only when a splash
  will draw it (`BattleViewModel.splashCasters` → `warmSplashCards`, as a
  turn's events reach the scene), never every fighter's at every turn: four
  megabytes a card. The view model's `cutIn` is `bossSpeech` (a chapter
  boss's line; a giant's rides its entrance's ribbon) and the white
  `ultimateFlash` is gone: an ultimate's light is a two-frame exposure punch
  (`CameraDirector.exposurePunch`) through the impact frame's queue.
  **The spotlight** is written on the render thread in `renderUpdate` with
  the impact frame (`SpotlightRig`, `SpotlightTimeline`): the set's lights
  to 35% with a figures' own key (category 2 | 1, idle at 0.001 of the key —
  never add or light one from nothing mid-fight, it compiles every figure's
  shader) taking up what the key lost, the painting's diffuse intensity
  armed at 0.999, the braziers through `StageBuilder.battleSetDimmer`.
  **Deaths leave:** `UnitNode.onFallen` (a death played AND marked, in the
  same life — `lifeSerial`) → `leaveTheField` (fade, `VFXLibrary.soulColumn`,
  `soulLight`, a glyph on the mark that a tap reaches, the ground oval gone
  for good — `restingShadowOpacity`, since every turn walks the fallen home;
  a boss `sinkBelowRim` in `rimDust`); a revive takes it all back, and so
  does a Skip's `sync` when it dropped the revive. **Waves walk** on their
  walk clip at the island's stroll (`WalkOn`), under a WAVE stamp that only
  a NEW wave wears (`WaveStamp.stamps`: a raid's guard comes back under the
  wave the fight is on); a chapter boss's line waits for the stamp and
  belongs to the wave the boss walks on with (`Stage.speakerWave`, the last
  wave that fields its kind). **A boss enters** (`beginBossEntrance`: rise,
  roar, ribbon, its bar filling from empty), a Titan in the opening line
  only once the stage is seen, booming as it rises — the queue waits on
  `queueHeldOpen`/`queueHeldUntil` through `continueWhenFree`, and
  `cancelBeats` (skip, forfeit, a new run) ends every beat where it stands.
  Labs: `-tour-cutin` (`6-battle-cutin`, `-spotlight`), `-tour-dissolve`
  (`6-battle-dissolve`), `-tour-waves` (`18-dungeon_battle-wave`, `-boss`).
- **The premium feel's summon half (2026-09-24; `Docs/FEEL.md` W2.4, W2.13,
  W2.23, W2.7, each with its *As built*).** At the flash the reveal's scene
  holds 70 ms (110 for a 5★), then the figure plays its VICTORY clip's
  measured window (`RevealEntrance.swift`: the three motion presets are known
  by the length SceneKit reports, 1.90 / 3.93 / 3.87 s) and blends back into
  its idle, the camera kicks on its own rig, the shockwave lies under the
  feet and a 5★'s sunburst stands behind, and the name slams on the clip's
  high point reported on the scene's clock (`onApex`). The words are
  `RevealNameCard`: a plaque in the grade's metal, the element's crest, stars
  stamped on two `keyframeAnimator`s (the arrival from the figure's first
  drawn frame, the naming from the high point); under Reduce Motion no
  spring on it rings. Skip goes to the next 5★ or NEW 4★ and says so, but
  NEVER names the pull on the beam before its rung: a single's reads plain
  Skip, and a pull of several changes its words only when a pull lands
  (`RevealSkip.label`) — plain Skip on the stop's own charge would be the
  tell. A 0.6 s hold skips all, a tap on a 5★'s charge lands its flash, and
  Quick summons (`summon.quick`, the room's header) flashes a 3★ in 0.5 s
  (`RevealSkip.swift`). **A `DragGesture`'s `onEnded` never comes for a
  CANCELLED touch** (an edge swipe iOS takes, a call): a press read from
  touch to lift also follows the finger through `@GestureState`, which
  SwiftUI resets on a cancel, springs the press back a main-queue turn after
  that reset if no lift came, and still accepts a lift that came late
  (`RevealSkipControl.letGo`, `releasedPress`). The sound is `tools/sfx.py
  summon --vsco DIR`: charge stems on the ladder's rungs off `result.stars`
  alone, a Light & Dark layer off the scroll spent, a burst per grade (the
  5★'s in E, the key the tell lifts to), six star notes and three rites,
  LEVELLED AS A MIX — the stems fade over 50 ms at the flash and the burst is
  scheduled 40 ms after it on the audio clock (`AudioLibrary.fadeOut`,
  `schedule`), and `summon_mix_check` sums every grade at the reveal's
  offsets (the loudest 0.895 of full scale); change a volume in
  `ChargeLadder` and sfx.py's `STEM_VOLUME`/`STAR_VOLUMES` together. Tour:
  `-tour-reveal-hold apex`, `-tour-reveal ten`, `-tour-reveal-skip`.
- **The fight reads.** **Every unit's bars are a screen-space plate OVER
  ITS HEAD (2026-09-15; under the feet from 2026-09-11 until the owner,
  with Summoners War's frame beside ours: "The health bars are not above
  the heads"):** `UnitPlateOverlay`, a SpriteKit scene laid over the
  `SCNView` (`overlaySKScene`, in `BattleSceneView.swift`), one
  `UnitPlate` per non-boss unit, placed every frame by
  `BattleSceneController.layoutPlates` from `projectPoint` of the top of
  the figure (`spec.height` over the node's feet; view points, origin
  top; the overlay's origin is bottom, so y is flipped by the scene
  height), the track's bottom 12 pt above it. The plate is the genre's:
  ONE track in a silver bevelled frame (65 × 17.5 since 2026-09-24,
  measured off the owner's Summoners War frame; a see-through dark
  66 × 14.5 before) holding the 6.5-pt glossy green health bar (seven
  stops, amber under 30%, a cream trail that drains 0.35 s after a hit)
  and the 4-pt blue **attack bar** under it (3 pt before; tweened to the
  engine's value when playback settles — `syncPlates` — and on
  `attackBarChanged`; gold and pulsing at 100%), the **level badge** over
  the frame's left end (a 27-pt metal sphere in the element's colour,
  ringed in the frame's silver, with `Combatant.level` on it in heavy
  white figures, `PlateArt.levelBadge`; a 22-pt dark disc before), the
  status tiles on the frame, the matchup arrow above them, a gold rim on
  the acting unit. Green for both sides, as the genre has it. **The HUD
  is the genre's (2026-09-15):** the boss bar the full width of the very top
  (gold health over blue attack in one track), the stage and the wave
  small at the top left, three 42-pt controls 16 apart at the bottom left
  (gear → log or forfeit, ×N, play/pause; see-through black in a 2-pt
  white outline, the white glyph the state — 36 pt and 6 apart before
  2026-09-24), the three 65-pt skill squares 13 apart at the bottom right
  (60 and 10 before; `SkillButton`: a dark socket lit in the caster's
  element, a gold frame, the estimate on the bottom edge, a veil with the
  turns left) with nothing behind them, both bottom corners standing ON
  the safe area's edges (16 pt off the glass where the phone has no
  inset; 8 pt inside the safe area before). The actor plate, the team
  column, the combat feed, the turn gauge and the target strip were
  deleted — the
  owner: "the UI of the skills and the descriptions like the bottom left
  UI and more I just don't like." The 3D bar in `UnitNode` still exists for the
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
  across a dark band for a second). **Damage numbers and skill words are
  SpriteKit labels in the plate overlay, ABOVE the plates (2026-09-23)**
  (`FloatingLabel`, `UnitPlateOverlay.floatLayer`, placed by
  `BattleSceneController.layoutFloats` from `projectPoint`): Manrope
  numbers and Cinzel words with a dark edge, a crit capped near 32 pt;
  they were SceneKit planes under the plates, and a crit grew to 75 pt
  off the top of the frame. **Since fix round 4 (run 221):** a float
  starts at its unit's chest and stops under its plate, a unit's floats
  stack newest lowest, a float whose unit leaves the frame (a skill zoom)
  FADES where it stands instead of being pinned to an edge — "542
  blocked" sat on the gear — and on-frame floats are clamped inside the
  window's safe area (`BattleStageView` reports it) and above the HUD's
  bottom corners, whose sizes `BattleSceneController` mirrors from
  `BattleView` by hand (`hudControls` 158 × 42, `hudSkills` 223 × 67
  since 2026-09-24; the plates keep under the top strip's chips and boss
  bar by the same mirror, `hudChipsFoot` and `hudBarFoot`); a boss's
  floats stand beside its head. The boss's warm spot is scaled by its
  own paint (`UnitNode.measurePaint`,
  the texture's mean in linear light: 2,400 × min(1, max(0.3, 0.14 /
  albedo)) — the Colossus about 1,390, the Unwrapped King the 720
  floor), and a pale boss drops the awakened costume glow. The plate's
  level is Manrope-ExtraBold 13 with a 1.7-pt dark edge in the 27-pt
  badge (Manrope-Bold 11 in a 22-pt one before 2026-09-24), the status
  tiles 16 pt with an 11-pt turn chip, and the matchup marker sits beside
  the frame's right end (even is a double arrow). The skill camera has no
  motion blur (it smeared the frame on every push-in), and a boss's matchup
  arrow is in the boss bar, never on it.
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
  the frame of contact. A missing sprite falls back to the spark, and
  since 2026-09-23 so does a BAD one: `VFXLibrary.sprite` refuses any
  sprite whose border is bright and opaque (a 32 × 32 read, one `[VFX]`
  line in the console) — `vfx_ring` and `vfx_wisp` were painted on
  WHITE, shipped as opaque squares, and drawn additive at nine times
  their size they put a pink-white slab over two thirds of the frame on
  every ultimate. Both need repainting on black (their sources in
  `Art/VFX/` are white too) before they come back. An
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
  for two takes). **The five-god test (2026-09-15, night; the owner: "I
  want REAL animated attacks (that includes effects, not just the
  animated model)", floor 1,500):** Anubis, Sekhmet, Zeus, Ares and Thoth
  each got a bespoke basic, heavy and ultimate from a sentence
  (`scratchpad/motion_wave.sh` holds the fourteen sentences; every one
  read right at the first take, 182 credits), shipped with
  `mesh.py <asset>_hd --as <name> --only-clips attack_basic,attack_heavy,ultimate`;
  each clip's blow frame is in `BattleSceneController.contactFraction`'s
  per-god table so the freeze and the flash land on it; Zeus is ranged
  (`melee: false`) since his clips hurl. **The effects are painted
  flipbooks:** `meshy.py picture` paints in MESHY credits (6 a picture on
  nano-banana-2, measured) while Gemini is paused, and
  `tools/vfx_sheets.py` ships `Art/VFX/sheet_<name>.png` (4 × 4, sixteen
  frames on black) as `vfx_<name>_sheet.png` with alpha and a fade over
  every cell's outer ring; eight sheets — claw, sunburst, shadow,
  lightning, blood, script, shockwave, bless (54 credits with one
  re-roll; the blood sheet's first take put its cells on grey) — play
  under the named skill effects (`VFXLibrary.addFlipbook`), the
  shockwave lies flat on the floor under every heavy blow
  (`groundFlipbook`, frames swapped as the material's contents), and an
  ultimate gathers motes round its caster through the wind-up
  (`charge`). Ares's Slaughter is `blood_slash`. 242 credits in all,
  2,133 → 1,891, six of them a probe that painted the prompt "x". `docs.meshy.ai` is closed to this environment; the
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
  4's awakened cards are NOT in it. **The batch ran on the night of
  2026-09-12 (00:26–01:00 UTC) and is complete: 263 images painted** — the
  2 kit textures, the 6 realm paintings (`banner_eagle_rises`,
  `banner_jade_court`, `forum_rome_bg`, `colosseum_sands_bg`,
  `peach_garden_bg`, `dragon_gate_bg`, every one looked at), batch 4's 20
  concepts, its 100 base cards (Mercury's five repainted once: the first
  set kept the concept's grey ground), and batch 3's 130 awakened cards;
  two lane failures were retried and no quota error came. Every batch-3
  and batch-4 family has its five cards, so all twenty of Rome and the
  Jade Court are in the gacha pool and both banners are offered; batch 4's
  70 awakened cards are the one thing still unpainted. Six batch-4
  families' cards (Neptune, Mercury, Vestal, Chang'e, Jiangshi, the
  Terracotta Soldier) came back full-figure rather than the portrait crop
  the prompt asks for — usable, on the dark ground with the glow, but not
  the same crop as the rest; a re-roll is five images a family and the
  owner's call. **Gemini is off again** until his word. Gemini's key allows 250 image requests a day; a
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
- **The scrolls are pictures, and the awakened look is quiet (2026-09-17,
  evening).** The owner, with the summon screen: "I really want my scrolls
  designed to have distinct looks … and then use that artwork IN the
  summoning circle. I just feel like this whole UI is sloppy/not the
  easiest to understand without that artwork." The eight scroll icons
  painted that afternoon (`item_scroll_<type>.png`) were already distinct;
  the screen never drew them. Now the menu rows, the strip's count chip,
  both summon plates and the rates popup carry the painting (`BarCount`
  and `PrimaryButton` take an `itemKey`; the glyph is the fallback) and
  the scroll itself hangs over the ring in `SummoningCircle`
  (`scrollOverTheRing`: a disc of its light, a breath, a drop and a flare
  when charging). The nine cells of `Art/Items/sheet_scrolls.png` were
  repainted at 2K as a `--ref` edit of the sheet (every design kept; 24
  cents) and ship at 512 (`sheet_scrolls_2k.png`; `item_icons.py --px 512
  --sheet scrolls_2k`). And the owner's phone frame of Ares Aureate on the
  reveal — "If awakened characters look like this we have a HUGE problem"
  — was the RENDER, not the mesh (`preview.py` draws a bronze hoplite):
  `MaterialTuner.applyAwakenedLook` put a 2.0-power rim at 0.95 (nine
  times the base at mid-facing, in the element colour) and a 0.55 costume
  glow on a camera with no white point. It is 3.2 / 0.42 and 0.20 now
  (`awakenedRimPower`, `awakenedRimStrength`, `awakenedCostumeGlow`), and
  every HDR stage camera — the reveal, the altar, the collection's Stage,
  the chest — wears the battle's `whitePoint` 1.85 shoulder.
- **Light and Dark are the premium (2026-09-17, evening).** The owner, of
  the Fuse board offering a 5★ light Ares and a 5★ dark Horus: "we should
  NEVER offer a 5 star Light or dark mon like this. it should ONLY be
  availble at like a 1% or less rate through the LD scrolls (like summoners
  war). They are PREMIUM PREMIUM mons that need to be better than the
  rest". So Radiance and Umbra come from the **Light & Dark scroll alone**
  — `Banner.excludingLightDark` is the one place the rule is spelled, every
  pool and featured list is built through it and `SummonService.eligibleIDs`
  filters every draw again, so the selector, the mileage board and the
  night market follow; `lightDarkWeight` is gone (featured ×2 is the only
  weight); `UnitDatabase.summonPool` stays the full set. The scroll is
  **0.8% / 9% / 90.2% with NO hard or soft pity** (`legendaryPity` nil; the
  4★ guarantee at 15 stays), so a 5★ is about 125 scrolls (56,250 divinity)
  and mileage is the floor: a banner without a pity anchors its 5★ to
  `ceil(1.3 / rate)` (`MileageService.expectedMultiple`, 163 points on L&D;
  every other price unchanged). Every light or dark roster form carries
  **`UnitDatabase.lightDarkPremium` ×1.08 on attack, health and defence**,
  applied ONCE in `UnitDatabase.roster` on the way into the registry (the
  builders never know), measured by `balance.py --variants` at ×1.07
  damage, ×1.09 survival and a sibling win rate 49% → 68%; the sim applies
  it only where it mirrors a shipped L/D blueprint (`ANUBIS_DARK`,
  `form()`), never on a stand-in team. The six fusion prizes are fire,
  water and wind 5★s now (The Red Beer → sekhmet_tide, The Screaming
  Charge → ares_gale, The Falcon's Noon → horus_ember, The Storm at Sea →
  zeus_tide, The Five Stolen Days → thoth_gale, The River of Fire →
  hades_ember) with no L/D corner. Change a rate, the premium or a mileage
  number in Swift, `balance.py` (`SCROLL_ODDS`, `LIGHT_DARK_PREMIUM`,
  `MILEAGE_*`) and `ScrollTests`/`SummonTests`/`ProgressionTests` together.
- **Accounts (2026-09-17, evening; `Docs/PLAN.md` *Accounts — Sign in with
  Apple*, `Docs/SOCIAL.md` *Sign in with Apple*).** The owner: "accounts
  that need to be created using an apple id or email. That way users are
  separate." Sign in with Apple IS the account (`Pantheon/Core/Account/`:
  `Account`, `AccountService`, `CloudSaveStore`; `SignInView`): Apple's
  stable user id, or `guest-<uuid>` for "Continue without an account"; the
  save is `pantheon_save_<key>.json` with `key` the first 16 hex of
  SHA-256(id), and the old `pantheon_save.json` is RENAMED to the first
  account that signs in on the phone (`SaveStore.migrateLegacySave`, once),
  so the owner's save survives the sign-in screen. A guest binds later from
  More → Account (his file renamed to the Apple key if that key has none);
  sign-out keeps the file; Apple's `credentialState` is checked on launch
  and every foreground, and `.revoked`/`.notFound` drop the account.
  `SignInView` (the key art, PANTHEON, the SYSTEM `SignInWithAppleButton` —
  a custom one is a rejection) is the root while no account exists;
  `AppSession` (PantheonApp.swift) REBUILDS `GameStore` per account and
  `retire()`s the old one so a pending 400 ms save cannot land in the next
  account's file. **The cloud copy:** an Apple account on an ENTITLED build
  mirrors its save to the container's PRIVATE database as one `Save`
  record (`save_<key>`, the JSON as a `CKAsset`, `modifiedAt`, and
  `createdAt` as the LINEAGE), at most once per 60 s and on `.background`;
  a new phone restores it at sign-in ("RESTORING"); never an older copy
  over a newer one and never ANOTHER lineage overwritten — that one is
  offered as "Restore from iCloud" on the Account panel. Gated like the
  social layer (`CloudKitSocialBackend.isEntitled`, then `accountStatus`).
  The entitlement `com.apple.developer.applesignin` is in
  `Pantheon.entitlements`; the owner must tick Sign in with Apple on the
  App ID and in Xcode's Signing & Capabilities or the button answers error
  1000 (worded on the screen); a Simulator signed in to an Apple ID tests
  the flow, CI cannot. Under `-tour` the app is the fixed guest
  `AccountService.tourAccount`; tour step 48 `sign_in` photographs the
  screen and step 9's Account panel shows the guest's rows and his six-hex
  "Player ID" (the tail of the CloudKit record name — how a support
  request finds the record). `AccountTests` (9). No email/password yet
  (option B in PLAN.md; `AccountProvider` is the door).
- **The backend is Supabase, and Reset account reaches the cloud
  (2026-09-22; `Docs/BACKEND.md`, PLAN.md *The backend — Supabase, and
  starting over*; the owner: "lets get the database for it going. I have
  supabase or turso").** `Pantheon/Core/Backend/`: `CloudSaveSyncing` is
  the protocol the CloudKit store and `SupabaseSaveStore` both implement
  (`GameStore.cloudSave` is typed by it; the Account panel prints
  `serviceName`, "iCloud" or "Pantheon Cloud"); `BackendConfig` reads
  `Resources/Backend.plist` (`SupabaseURL`, `SupabaseAnonKey`; FILLED
  since 2026-09-22 with the owner's project `kqlblqnioumkdoudhibi` —
  the anon key is public by design — and both empty = no backend; never
  under `-tour`; the owner's first paste was the dashboard's REST URL,
  `…/rest/v1/`, which would have put every call at `…/rest/v1/auth/v1/…`,
  so `from(dictionary:)` strips a service path and a trailing slash, and
  `BackendTests` asserts the bundled plist holds a bare project URL and a
  key whose role is `anon`, never a secret — the old test asserted the
  plist EMPTY and went red the moment he filled it, run 206); `SupabaseClient` is URLSession only (no SDK — the project has
  no package dependencies): an anonymous user for a GUEST, Apple's
  identity token (`AppleCredential.identityToken`, `grant_type=id_token`)
  for an Apple ID, the session in `backend_session_<key>.json`, a refresh
  a minute before expiry and once on a 401; the save is one row of
  `saves` with the JSON as TEXT (byte-for-byte), guarded on the server by
  the `saves_guard` trigger raising `lineage`/`stale`
  (`Backend/supabase/migrations/`, applied by the owner in the SQL
  editor — `supabase.com` is closed to this environment). **Reset
  account** (Settings → Delete everything) is `AppSession.startOver`: the
  save moved aside as `reset_<stamp>_…` (`SaveStore.archive`, never
  deleted), `LocalSocialBackend.wipe()`, `cloudSave.erase()`, then
  `open(account, freshStart: true)` which skips the legacy migration and
  every restore; an unreachable cloud leaves its copy to come back as a
  foreign save the panel offers. `GameStore.resetAccount()` is gone.
  Turso was weighed and kept out: no auth, no RLS, no functions, so it
  would need an API of our own in front of it. `BackendTests` (11) run
  every path against a canned transport. **A `static func` on a
  `@MainActor` class is isolated too** (run 200: nine "call to main
  actor-isolated static method … in a synchronous nonisolated context"
  errors from the tests): a pure helper a test calls from plain code is
  `nonisolated static`, and a non-Sendable stored static it needs (a
  formatter) lives in a private enum beside the class. And a test of a
  store that saves under `account.storageKey` plants its file under
  that key, not a literal (run 201).
- **The premium pass, phase A (2026-09-22; PLAN.md *The figure on the
  phone, the tunic on the hand, and the premium pass*; the owner: "It
  feels like a cheap copy as opposed to a premium game").** The rule is
  the genre's: cream marble CHROME, dark glass over ART, carved gold for
  display type, nothing under 11 points. `Theme.fontScale` is 1.0, the
  floors 11 / 11.5 / 13; `Theme.goldText` + `View.carved()` is a display
  title, `Theme.glass`/`glassRim`/`onGlass` a plate over a painting
  (`GlassPlate`); `GameScreen`'s strip is 52 points with the title carved
  at 21 and a bronze medallion for Back; `BarWallet`/`BarCount` sit in a
  dark `BarWell`; `GameTabBar` (RootView.swift) is the bottom bar — the
  system tab bar is hidden with `.toolbar(.hidden, for: .tabBar)` inside
  `GameScreen` and on every tab, and the bar is laid out BELOW the
  TabView in a `VStack` (it was the TabView's bottom `safeAreaInset`,
  which never reaches content inside a `NavigationStack`, so the bar
  covered the foot of every tab screen until run 217 — see phase B); `PrimaryButton` is 46 tall with a gloss sweep on gold
  and a `.glass` style; `LightShafts` and `Motes` are the ambience over a
  hero painting. The summon screen is the first screen rebuilt to it (the
  painting covers the frame, the banners a rail of cards on glass, the
  deck floating on the dark foot). A nested type must not share a name
  with another type in the tree: the checker keys structs by NAME, so
  `GameTabBar.Item` was read against `ShopService.Item`'s memberwise init
  (it is `TabItem`). **The strip's rule (2026-09-22, evening; the owner,
  of run 207's crops: "look how sloppy this is"):** every control in
  the strip is ONE material — `ScreenChrome.well`, the wallet's dark
  capsule with a gold rim (`BarButton`, `BarSegments`, the element
  toggles, the sort menu, `TierChips`; the chosen segment a gold plate
  with ink) — 34 points tall, its label on one line at its own width
  (`fixedSize`); the strip's title shrinks to half before anything else
  gives, and a truncated control means the screen has too many. No
  ellipsis anywhere in the chrome: the More tiles' captions were
  rewritten to fit their line, the Labyrinth cards' names have two
  lines, the chapter plate's story four. The tour's chip sits under the
  strip, not on the tab bar. And a tint a `BarButton` is given is read
  through `BarButton.onWell` — the two ink colours are cream ON the dark
  well, gold the pale gold, danger/info/success themselves — because run
  209 drew every "off" toggle (Filter, Select, Lock, Free) in ink-brown
  on the dark capsule, which reads as disabled; `fixedSize` goes on the
  LABEL of a strip control as well as its value (the sort menu's wrapped).
  The title's floor is 0.7 (13.3 points), and a strip that still
  truncates has too many controls, never a smaller title: the collection's
  layout switch is one glyph and its element filter has no ALL tile (the
  lit element toggles off), run 210. The tour's chip stands on its side
  in the LEFT safe-area inset (`TourView`), where nothing draws. A card's
  painting is `PaintingFill`, never a `.fill` image under a flexible
  frame — the Labyrinth cards carried their names below the clip. And
  the unit sheet's columns scroll when taller than the frame: its strip
  was cut in half at the top from run 204 to 210.
- **The premium pass, phase B (2026-09-22/23; PLAN.md *Phase B of the
  premium pass* and *Wave 1 as built*).** Every PLACE — the arena, the
  Labyrinth's rooms and wings, the Titans, the Hall of Ka, the chapter
  map with its popup and briefing, the bazaar, missions, events, the
  mileage and selector boards — is its painting full-bleed
  (`PlaceBackdrop`, bleeding under the safe areas) with dark glass where
  the words go; the shared parts are `Pantheon/UI/Common/Glass.swift`
  (`GlassPlate`, `GlassSection`, `PlaceRail`, `GlassBead`, `GlassMeter`,
  `UnitPortraitTile`, `CostWell`, `ClaimPlate`, `GrantReceipt`, …) and
  the painted doors are `tab_<key>.png` (`tools/tab_icons.py`, nine
  cells on Meshy). **A tab screen ends where the tab bar begins**:
  `RootView` is a `VStack` of the TabView and `GameTabBar`, never an
  inset; a card over a tab dims the bar with `.dimsTabBar(_:)`; the
  island sizes its figures off the painting's frame
  (`IslandSceneView.stageHeight`), not the view's height. Sweep never
  spends on one tap — it opens a choice of counts. `PortraitPainting`
  zooms thirty-eight full-figure families' cards to a bust in a square
  (every base card was looked at on contact sheets on 2026-09-23; the
  mummy's crop starts lower, `topOverride`, for its white sheet). The
  tour photographs `4-summon-root` (the bar in its real place),
  `3-training-evolve`, `16-dungeon-sweep` and `11-relics-legend` (the
  fullest worn relic, `-tour-relic legend`). **A rail lands on whole
  rows by re-planning**: `WholeRowRail` (Glass.swift; the Labyrinth's
  floors and Titans and the Hall of Ka's roster) re-plans on every height
  change until the player takes it, because a rail passes through
  heights on its way to its own (87 and 259 points against 304 in run
  221's consoles) and one plan on the first of them landed nowhere. Lists
  rest on whole rows (`RestingList`, `restingRow()`), and the Night
  Market never shows a ware twice (`NightMarketService.twinRedraws`).
  **Round 5 (2026-09-23; PLAN.md, *Round 5: stopped …* and *Round 5,
  resumed*):** the chapter map's haze is Core Image's clamped blur
  (`SoftMapPainting`; SwiftUI's opaque blur takes in black at its
  bounds). **A cast on several victims is drawn ONCE over the row**
  (`VFXLibrary.spawnArea`, `Reach.row`: its sheets off white, at 0.4
  strength and at most 3.4 m, one light kept under the key
  (`rowLightStrength` 0.35), and every victim its own sparks;
  an element's hit or a heal stays on each victim as `Reach.member`, with
  no light of its own). Drawn per victim, four white sheets made a slab
  over the whole team. A sheet that would reach the floor STANDS as a
  camera-facing plane faded into it by a baked mask
  (`standingFlipbook`, `floorFadeMask`): the floor cut the particle
  version with a hard line (run 234), and a fragment modifier reading
  `_surface.position` drew nothing at all (run 235) — no custom shader
  on an effect. An effect's scale on a unit is capped at a 2.6 m unit
  (`BattleSceneController.effectScale`). The tour casts an area ultimate
  on the team every run (`-tour-aoe`, frames `8-arena_battle-aoe-*`). The
  fifty judged faults are in `tools/patches/round5_faults.json`, and
  `round5_wip.patch` is applied except its `BattleSceneView` half.
- **The skirt pass (2026-09-22).** `character.reweight_skirt` (in
  `mesh.py` after the cape pass; `tools/skirt_pass.py --survey | <names>
  | --all` over the SHIPPED base and `_lod` files): cloth that Meshy's
  rigger gave to a HAND, a FOREARM or an UPPER ARM — a tunic's panel, a
  kilt's apron, a robe's drape, a cloak's side, because the concept's
  hands rest on the thighs — goes back to the body (the nearest
  body-owned neighbour's weights, the seam blended over three rings).
  Anhur's red tunic swung up with his khopesh and read on the phone as a
  blade across his chest; Heimdall's cloak flew out with his arm. The
  candidates are arm-owned vertices below the neck and OUTSIDE the arm's
  own surface (`_limb_surface`, the HAND a segment continued 0.12 h past
  the wrist — Meshy's rigs have no finger bones, and without it every
  hand in the roster was "a thing held"); each connected piece then stays
  with the arm when it is a rod (a weapon), far from every body bone (the
  Minotaur's axe), a solid (thick: Bes's drum), WELDED TO THE ARM (under
  two fifths of its edge on body-owned mesh — the awakened Ares's shield,
  Mars's scutum, Bragi's lyre, the smith's hammer at 0–4%; a garment's
  panel is sewn to the garment at 42–73%; a panel between, welded to the
  hand along most of its edge, stretches to a SPIKE when the hand swings
  away from the leg it was given to, so it stays), held at its middle
  (its centre within 0.075 h of a wrist) or lying on the arm (three
  fifths within 0.02 h of the arm's surface). Then, each demanded by a
  blow-frame render: the sheet GROWS back through the arm's layer (never
  its skin) to take the cloth's rows nearest the hand; the copied weights
  lose every ARM SHARE (Meshy blends smoothly — the garment's body-owned
  rows beside the hand hold the hand at a third to a half, and so did
  the "moved" tunic), as do the garment's rows within fourteen rings; and
  `character.cut_seam` DOUBLES the seam's vertices so the weld Meshy
  fused between a tunic's corner and the hand opens as a crack instead of
  stretching into a spike. The LOD takes the base's verdict vertex by
  vertex and is cut the same way (`skirt_pass.transfer`); `mesh.py`
  decimates the LOD from the re-bound base. Three earlier rules are in
  the docstring with what each took: a compact-object test on the span
  took shields and a lyre, a "hanging" test refused Anhur's tunic, a
  waist-to-knee band cut Heimdall's cloak at the knee. Judge on
  `base_plus_clip.py` at the heavy attack's BLOW frame (`--frames=30`,
  with the `=`: without it the tool renders the clip's first frame, the
  hands at rest, and a board of that passed a broken pass) and the
  ownership board (`skirt_mask_board.py` in the scratch), never on the
  count. The pass is APPLIED BY NAME (`character.SKIRT_FAMILIES`: Anhur,
  Atalanta, the awakened Sekhmet — `mesh.py` and `skirt_pass.py --all`
  read it): of the sixteen families the survey moves cloth on, those
  three are clear wins on the board, ten shred or tear (cloth welded to
  the arm along a whole sleeve or a wrapped robe comes off the cut in
  slivers — Heimdall, Pluto, Centurion, Njord, Satyr, the smith,
  Aphrodite, Baldr, Loki, Freya) and stay as rigged, and three change
  nothing a frame shows. A robe the arms pass through is the cape pass's
  next problem (cloth bones through the sheet), not this one's; a new
  family is judged on its board and added to the list.
  **The robe ring (2026-09-22, night) was built and admitted NOTHING**
  (PLAN.md, *The robe ring's verdict*): `character.reweight_robe` hangs the
  lower garment on up to eight spring chains round the hips
  (`robe_pass.py`, `robe_board.py`, `cloth_metrics.py`, `cape_sim.RingSim`),
  gated by name on `ROBE_FAMILIES`, which is empty; it stopped the lower
  garment flying on seven of the ten arm-welded families and every one
  still tore ABOVE the hips, where the cloth lies on the arm. The Swift
  `ClothRing` is `tools/patches/robe_ring_swift.patch`, out of the build
  until a family passes. The fix left is a remake (about 77 credits a
  family); the simulation added nothing on the attack and hurt the death.
- **A stage draws a dramatic beat once out of sight first (2026-09-23).**
  A shader compiles the first time something is DRAWN with it: run 221's
  5★ reveal showed its name card over an empty dais because the figure,
  the beam's column and the contact shadow were first drawn at the flash,
  SceneKit compiled 21 shaders there and the main thread stalled a
  second behind them. `SummonStageView` now draws all three at alpha
  0.01 before the charge's clock starts, the words are timed from the
  figure's first drawn frame (`onShown`), and the flash runs on the wall
  clock in a `TimelineView`. `SCNSceneRenderer.prepare` was weighed and
  not trusted: it is documented to upload textures and geometry, not to
  build the pipelines a frame needs. Never read the scene graph from the
  main thread on a timer during such a beat.
- **The figure stages are exposed and coloured (2026-09-22).**
  `FigureStageLighting`: key 1,150, fill 320, rim 420, ambient 140, the
  studio map at 1.0 (brighter softboxes; the old map is `studio_ibl_v1`),
  the key 92% to white (`keyTintMix`), `paintSaturation` 1.0 (the
  textures as the boards draw them; 0.85 read as grey on the phone), and
  a real metal map's metal at 0.55 of its roughness (`metalShine`). Every
  one of those is a `static var` read off the reveal lab, and
  `-tour-reveal-lab previous` photographs the rig of the 18th beside the
  new one every run (`5-reveal-awakened-previous`).
- **The figures are lit physically, and the paint is tempered (2026-09-20;
  PLAN.md *The serious look in the light*; the owner: "why do the renders
  make the colors and the look of the characters, even the redesigned,
  look more cartoony?").** Four causes, none in the meshes, all measured
  first: Meshy's texturing doubles a concept's saturation (Sif's base
  colour 118 of 255 against her concept's 60; the old texture prompt
  asked for "rich saturated colour"), the figure shader replaced
  SceneKit's physically based model with a Lambert ramp and a Blinn-Phong
  pop while the floors had the real model, no battle ever had an
  environment to reflect (one flat colour at 0.35), and the battle grades
  had `SCNCamera.contrast` at 1.03–1.12 — an ADDITION to a default of 0,
  so double the contrast — with saturation pushed on top. Now: NO
  `.lightingModel` modifier (`MaterialTuner.lightingModifier` is nil; the
  ramp and the half-Lambert are `-tour-shading ramp|legacy` for the CI
  lab, which photographs the awakened Ares five ways), `paintSaturation`
  0.85 in the surface shader, the painted-gold guess only without a real
  metalness map (`hasMetalMap`), the rim 4.2 / 0.12 (awakened 4.0 /
  0.18), the recolour capped at 0.85 saturation, a lighting environment
  made from each battle's painting (`StageBuilder.environmentMap`,
  `PaintingPalette.environment`, intensity 0.7, the ambient 150 with it),
  the grades at contrast 0.06–0.14 and saturation 0.92–1.0, the reveal's
  camera at 0.10 / 1.0, colour fringe 0.10–0.12. The texture prompt for
  every future wave asks for a natural restrained palette (`wave_launch.sh`,
  `beast_wave.sh`); a retexture of the shipped serious families is about
  10 credits each, on the owner's word. Run 198 judged it: every battle frame's mean saturation fell 7–37 points (the Duat 205 → 176) and brightened 10–15, no band over 2% clipped; the lab's five frames show the metal in the physically based figure and flat paint in the ramps. The boards are a flat software
  render and never show the light; judge a lighting change on the CI
  frames and `framelight.py`.
- **The figure stages are lit properly (2026-09-18; PLAN.md *The figure
  stages' light*).** The owner, of the reveal frames: "the renders all
  fucked up." Three causes, none in the meshes: the shading ramp was a
  half-Lambert over a 30% floor (`MaterialTuner.lightingModifier` is TRUE
  Lambert now, `saturate((ndl + 0.15) / 1.15)`, the specular gated to the
  lit side; the old ramp is `legacyLightingModifier` for the lab only); the
  reveal, the altar and the collection's Stage had no environment and no
  shadow (`FigureStageLighting`: one rig — key 900, fill 240, rim 400,
  ambient 100 — the studio map `Stage/studio_ibl.png` from
  `tools/studio_ibl.py` at 0.5, a deferred shadow from the key with ONLY
  the figure casting via `restrictShadows(in:to:)`, called after the figure
  is placed and again after the reveal's beam and shadow patch arrive,
  because those quads would throw solid black shapes); and the reveal stood
  on cream (a dusk now, `dusk*` in SummonRevealView, cream words). The
  reveal step photographs the awakened Ares four ways every run (the rig,
  `-tour-reveal-lab dark`, `-tour-reveal-lab bare`, `-tour-shading legacy`)
  so a lighting change is judged against its control. And a mesh whose
  texture came back off its cards is graded at shipping, not re-textured:
  `mesh.py <asset> --grade gold` (`character.GRADES`; the Ares family was
  olive with magenta runes against two gold cards). The awakened Ares's
  paper-white skin (#F7DAD4, value 0.96) was paint too: `gold_skin`
  takes it to #A37B69 beside the base Ares's own, applied on 2026-09-23
  to the shipped textures alone, and `proportions.sh` names it.
- **Every family has a standing idle now, and the stages play it
  (2026-09-18).** No family shipped a plain `idle` (0 of 116), so the
  reveal, the altar, the collection's Stage and the island had always
  played Meshy's *combat idle* preset — a crouched guard stance, knees bent
  and spine folded — and on the Ares family it photographed as a hunch seen
  from behind (the owner: "the screenshot is still fucked"). Skinning the
  shipped base with its shipped clip offline (`tools/base_plus_clip.py`,
  joints matched by name as the game does) reproduced the frame exactly and
  the raw Meshy clip has the same pose: the clip, not the pipeline.
  `tools/stand_idle.py` derives `<name>_idle.usdz` from the combat idle for
  every family (rotations slerped toward rest — spine 35%, legs 45%, arms
  85% kept — the hips' dip halved, every frame re-grounded on the FOOT
  JOINTS), `UnitNode.restingIdle` prefers it on the island and in
  `restartIdle`, and the three stages already preferred `.idle`; the battle
  keeps the crouch. `build_asset.sh` and `proportions.sh` derive it after
  every ship — a re-shipped combat idle leaves a stale standing one.
- Sound is 14 synthesised effects (`tools/sfx.py`, thunder for Zeus) and two synthesised music
  loops (`tools/music.py`, island and battle), crossfaded by `AudioLibrary`.

- **The serious roster (2026-09-18, 17:30; the owner, with 6,505 credits:
  "Go ahead and work on the upgrades for the characters … I DONT want the
  cartoony, Chibi Stlye. I want more serious, more detailed work").** Every
  rigged family is remade from a from-scratch SERIOUS concept
  (`tools/batch/serious_style.sh`: seven and a half heads, true hands, a
  mature face, the painted detail kept; the design sentences of
  `concepts_*.sh` with "cartoon" read out, the first roster's and the
  awakened forms' written in `serious_roster.py`), painted through
  MESHY's painter — `meshy.py picture --model nano-banana-pro`, the same
  Google pro model as every chibi concept, 9 credits a picture, in the
  credits he bought, never through Gemini's own key — and remade on
  meshy-7 with the eight clips: 68 a family. `serious_roster.py` writes
  `serious_wave.txt` (the spending order: the four gods, the roster as
  made, the awakened forms, the bosses) and `serious_concepts.tsv`;
  `serious_concepts.sh N` paints the next N; `serious_sheet.py` makes the
  sheet a batch is JUDGED on before `AI_MODEL=meshy-7 wave_run.sh
  serious_wave.txt 500` buys its meshes; `ship_wave.sh` ships through
  `build_asset.sh` (the hero budgets, the cape pass, the standing idle) —
  NEVER through the proportion pass; `reapply_motions.sh <asset> <donor>
  <family>` re-applies a god's bespoke motions to the new rig at 3 a clip
  while the motion tasks live (about a week). The serious Zeus shipped
  first for nothing (`Art/Models/tests` since the test). The cards stay
  chibi busts until the owner decides (PLAN.md, *The serious roster*). **The rigger's two rules (18:10):** nothing held reaches the ground or below the knee, and the feet stand a shoulder-width apart — Artemis's bow on the floor, Sekhmet's khopesh swept out to the ankle and Bastet's feet together under a knee-length dress were refused ("Pose estimation failed", 90 credits unrigged); a refused attempt is kept as `.rigfail1` beside its family and the wave relaunches the asset from the repainted concept. **The disk (2026-09-19):** the session's allowance is about 40 GB and a shipped family's raw clip downloads are 56 MB of it — once a family's bundle files are committed, delete `Art/Models/<asset>_serious_<clip>.glb` (keep the rig, the image usdz and the five gods' `_m7_` clips); the 18th's run-out corrupted thirteen concepts and one download and restarted the container. **Where it stands (2026-09-23, 22:00): every rigged family is serious** — the last 22 base families, all 16 awakened forms (Hera's made for the first time) and both Labyrinth bosses shipped on the owner's new credits (3,570 → 594; 58 pictures at 9 and 40 meshes at 59), judged on `roster/board_*.jpg` and sent to him; the awakened Ares, Sekhmet, Thoth and Zeus play their god's bespoke clips retargeted onto the new rigs. **The weapon stretch and its pass (2026-09-23, 23:00):** a weapon painted against the thigh — where the rigger's own rule puts it — is rigged partly to the leg and stretched from hand to hip on every arm swing (Ra's ankh 77x, the Siren's harp 246x). `tools/weapon_pass.py` (the skirt pass turned round) finds the held piece by measurement over the shipped clips and binds it wholly to the hand, cutting the seam where it touches the body; it is applied by name to the nineteen families judged on before/after boards (`character.WEAPON_FAMILIES`, `weapon_pass.py --all`), and `mesh.py` re-runs it on those names after a re-ship (`--no-weapon` skips it). The audit of all 114 bases on eight-cell pose sheets (`scratchpad/audit/audit_sheet.py`, findings in `audit.json`) found cloth tearing the largest fault left (56 severe), then limb welds, clips that do not fit their mesh, and Apollo's third arm (PLAN.md, *Where the serious roster stands*). Every concept since asks for the weapon held clear of the thigh.
- **The cape pass (2026-09-18, 03:00).** `character.reweight_cape` runs in
  `mesh.py` after the proportions (`--no-cape` skips it; `CAPE_EXCLUDE`
  names the winged and tailed families): a cape Meshy's auto-rig gave to
  the shins and the upper arms (Ares's lifted with his arms like a bat's
  wing; the owner: "fucked") is hung on FOUR JOINTS OF ITS OWN, `cape_0`
  at the sheet's top down to `cape_3` above the hem, children of the spine
  joint it hangs from (a belt cloth's is `Hips`), the sheet skinned to them
  by height with its seam blended over four rings, and the game swings
  them every frame with a spring simulation — `Render/ClothChain.swift`
  (VRM's spring bone: tails with velocity, a pull toward the rest
  direction, gravity, the bone's length, eight spheres and a back plane
  through the hips, a fixed 1/60 s step), attached in `ModelLibrary.node`
  after `repairSkinners` and stepped from every stage's
  `didApplyAnimationsAtTime` (the battle coordinator, `StageDoctor`, a
  `ClothStepper` on the reveal and the island). `tools/cape_sim.py` is the
  SAME sum in Python: change a constant in both files, and judge it on
  its board (`python3 tools/cape_sim.py ares_m7 attack_heavy --frames
  0,20,37,55,72 --source`; `--no-sim` is the chain held rigid) before
  shipping. A clip carrier NEVER carries the chain — a rest track would
  pin the cape — so `mesh.py` matches carriers against
  `character.body_joints`. And a figure plays the clips of the MESH on
  the stage, chosen by `ModelLibrary.clipAsset(for:awakened:)` in every
  stage: the reveal, the altar and the collection's Stage played the base
  rig's idle on the awakened mesh until 2026-09-18, which posed the
  awakened Ares's pelvis 150° off and sent his cape round to the front
  (PLAN.md, *Run 188's frame*). The spine binding it replaced was a rigid board
  that stood in front of Ares's legs in every reveal frame (the owner:
  "ares is STILL broken"). The rules for FINDING a cape and why each
  exists are in `Docs/PLAN.md` *The cape pass* and *Cape bones and a
  spring simulation*: behind the spine's plane, outside every
  limb's own measured surface (`_limb_surface`: the layer up to the first
  gap, inward face or 1.8× the innermost, so a cyclops keeps his arms and
  Sekhmet her arm bands), one connected SHEET by shape from the shoulder
  line (`_big_sheets`: thin one way, a foot across the other; a bident is
  a rod, a bolt a lump, a bow too narrow — never by who owns it, since
  the awakened Ares's cape was skinned to his hand), not a WRAP (free
  cloth in front over 80% of the sheet's height is a skirt or a robe:
  the gladiator's tunic re-bound to the hips tore off his legs), longer
  than wide (Khnum's round shield is a sheet), and only when a limb
  dominates 4% of the mesh out there — under that a family is left as
  rigged; the winged (Nephthys, Isis, Ma'at, the siren: wings along the
  arms ARE a sheet), Khnum (a shield behind the hip) and the nymph (a jar
  in the hand against her hair) are excluded by name. Judge a change on `tools/cape_board.py` (the mask
  drawn on the figure) and `tools/cape_check.py` (how far the cape moves at a
  clip's frame), never on the count alone: the first cut's count looked
  right and had warped the torso. Bone lookups are case blind (`neck`).

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
